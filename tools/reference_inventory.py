#!/usr/bin/env python3
"""Inventory only: extract pinned Minecraft 26.3 official release data.

No accounts, launcher profiles, world saves, or credentials are inspected.
Downloaded/extracted originals and generator output stay in ignored directories.
The emitted files describe reference inputs; they do not implement gameplay.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import itertools
import json
import pathlib
import shlex
import subprocess
import sys
import urllib.parse
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
PIN = "26.3"
INSTALL = pathlib.Path.home() / "Library/Application Support/minecraft"
JAVA = INSTALL / "runtime/java-runtime-epsilon/mac-os-arm64/java-runtime-epsilon/jre.bundle/Contents/Home/bin/java"


def digest(data: bytes, algorithm: str = "sha256") -> str:
    return hashlib.new(algorithm, data).hexdigest()


def canonical(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def write_json(path: pathlib.Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n")


def write_tsv(path: pathlib.Path, headers: list[str], rows: list[list[object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    def cell(value: object) -> str:
        if isinstance(value, (dict, list)):
            value = canonical(value).decode()
        value = str(value)
        if any(c in value for c in "\t\r\n"):
            raise ValueError(f"TSV delimiter in {value!r}")
        return value
    path.write_text("\t".join(headers) + "\n" + "".join("\t".join(map(cell, row)) + "\n" for row in rows))


def fingerprint(path: pathlib.Path) -> dict:
    data = path.read_bytes()
    return {"file": path.name, "bytes": len(data), "sha1": digest(data, "sha1"), "sha256": digest(data)}


def verify_download(path: pathlib.Path, metadata: dict) -> None:
    got = fingerprint(path)
    if got["bytes"] != metadata["size"] or got["sha1"] != metadata["sha1"]:
        raise ValueError(f"Pinned artifact mismatch: {path.name}: {got}")


def obtain(path: pathlib.Path, metadata: dict, local: pathlib.Path | None = None) -> pathlib.Path:
    if path.exists():
        verify_download(path, metadata)
        return path
    if local is not None and local.exists():
        verify_download(local, metadata)
        return local
    url = urllib.parse.urlparse(metadata["url"])
    if url.scheme != "https" or url.hostname not in {"piston-data.mojang.com", "piston-meta.mojang.com"}:
        raise ValueError("Only pinned official artifact hosts are permitted")
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_suffix(path.suffix + ".part")
    with urllib.request.urlopen(metadata["url"], timeout=60) as source, partial.open("wb") as target:
        while chunk := source.read(1024 * 1024):
            target.write(chunk)
    verify_download(partial, metadata)
    partial.replace(path)
    return path


def tree_hash(rows: list[tuple[str, str]]) -> str:
    """SHA256 of sorted UTF-8 `path<TAB>content_sha256<LF>` records."""
    return digest("".join(f"{path}\t{sha}\n" for path, sha in sorted(rows)).encode())


def data_location(path: str) -> tuple[str, str, str, str] | None:
    parts = path.split("/")
    if len(parts) < 4 or parts[0] != "data":
        return None
    scope = "vanilla"
    if parts[2] == "datapacks":
        if len(parts) < 7 or parts[4] != "data":
            return None  # pack.mcmeta is metadata, not a registry element.
        scope = parts[3]
        parts = parts[4:]
    namespace, rest = parts[1], parts[2:]
    if rest[0] == "tags":
        category_length = 3 if len(rest) > 2 and rest[1] == "worldgen" else 2
    else:
        category_length = 2 if rest[0] == "worldgen" else 1
    category = "/".join(rest[:category_length])
    tail = pathlib.PurePosixPath(*rest[category_length:])
    return scope, category, namespace + ":" + str(tail.with_suffix("")), tail.suffix.lstrip(".")


def json_shape(values: list[object]) -> dict:
    roots = collections.Counter(type(value).__name__ for value in values)
    keys = collections.Counter(key for value in values if isinstance(value, dict) for key in value)
    types = collections.Counter(value["type"] for value in values if isinstance(value, dict) and isinstance(value.get("type"), str))
    return {"json_count": len(values), "root_types": dict(sorted(roots.items())),
            "top_level_keys": dict(sorted(keys.items())), "top_level_type_discriminators": dict(sorted(types.items()))}


def block_schema(identifier: str, value: dict, protocol_id: int) -> dict:
    states = sorted(value["states"], key=lambda state: state["id"])
    ids = [state["id"] for state in states]
    if ids != list(range(ids[0], ids[0] + len(ids))):
        raise ValueError(f"Noncontiguous block states: {identifier}")
    props = value.get("properties", {})
    # Java map iteration is not a reliable property significance order. Infer
    # mixed-radix strides from the explicit reference state sequence, then
    # reconstruct and compare every state, including all default markings.
    strides = {}
    for key in props:
        first = states[0]["properties"][key]
        strides[key] = next((i for i, state in enumerate(states) if state["properties"][key] != first), len(states))
    ordered = sorted(props, key=lambda key: (-strides[key], key))
    domains = [{"name": key, "values": list(dict.fromkeys(state["properties"][key] for state in states))} for key in ordered]
    products = list(itertools.product(*(domain["values"] for domain in domains)))
    if len(products) != len(states):
        raise ValueError(f"Noncartesian states: {identifier}")
    for state, product in zip(states, products):
        if dict(zip(ordered, product)) != state.get("properties", {}):
            raise ValueError(f"State mapping mismatch: {identifier} at {state['id']}")
    defaults = [state["id"] for state in states if state.get("default", False)]
    if len(defaults) != 1:
        raise ValueError(f"Expected one default state: {identifier}")
    return {"protocol_id": protocol_id, "identifier": identifier, "first_state_id": ids[0],
            "state_count": len(states), "default_state_id": defaults[0], "properties": domains}


def commands_table(root: dict) -> tuple[list[list[object]], dict]:
    rows, types, parsers = [], collections.Counter(), collections.Counter()
    def visit(node: dict, path: list[str]) -> None:
        types[node["type"]] += 1
        parser = node.get("parser", "")
        if parser:
            parsers[parser] += 1
        rows.append(["/".join(path), path, node["type"], int(node.get("executable", False)), parser,
                     node.get("properties", {}), node.get("redirect", [])])
        for name, child in sorted(node.get("children", {}).items()):
            visit(child, path + [name])
    visit(root, [])
    return rows, {"root_count": len(root["children"]), "roots": sorted(root["children"]),
                  "nodes": len(rows), "node_types": dict(types),
                  "executable_nodes": sum(row[3] for row in rows),
                  "redirect_nodes": sum(bool(row[6]) for row in rows), "parsers": dict(sorted(parsers.items()))}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version-dir", type=pathlib.Path, default=INSTALL / "versions" / PIN)
    parser.add_argument("--java", type=pathlib.Path, default=JAVA)
    parser.add_argument("--skip-generator", action="store_true", help="Use already generated reports; still verify all inputs")
    args = parser.parse_args()
    version_path, client = args.version_dir / f"{PIN}.json", args.version_dir / f"{PIN}.jar"
    version = json.loads(version_path.read_text())
    if version["id"] != PIN:
        raise ValueError("Version metadata is not the requested 26.3 pin")
    verify_download(client, version["downloads"]["client"])
    cache, reports = ROOT / "reference/cache", ROOT / "reference/reports"
    cache.mkdir(parents=True, exist_ok=True)
    server = obtain(cache / f"{PIN}-server.jar", version["downloads"]["server"])
    asset_meta = version["assetIndex"]
    asset_index = obtain(cache / f"{asset_meta['id']}.json", asset_meta,
                         args.version_dir.parents[1] / "assets/indexes" / f"{asset_meta['id']}.json")
    java_version = subprocess.run([str(args.java), "-version"], capture_output=True, text=True, check=True)
    command = [str(args.java), "-DbundlerMainClass=net.minecraft.data.Main", "-jar", str(server),
               "--server", "--reports", "--output", str(reports)]
    if not args.skip_generator:
        result = subprocess.run(command, cwd=cache, capture_output=True, text=True)
        (cache / "report-run.log").write_text(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError(f"Official data generator failed ({result.returncode}); see {cache / 'report-run.log'}")
    report_root = reports / "reports"
    load_report = lambda name: json.loads((report_root / name).read_text())
    registries, blocks = load_report("registries.json"), load_report("blocks.json")
    commands, packets = load_report("commands.json"), load_report("packets.json")
    datapack, rpc = load_report("datapack.json"), load_report("json-rpc-api-schema.json")
    registry_rows = [[registry, entry["protocol_id"], name] for registry, record in sorted(registries.items())
                     for name, entry in sorted(record["entries"].items(), key=lambda pair: pair[1]["protocol_id"])]
    registry_counts = {registry: len(record["entries"]) for registry, record in sorted(registries.items())}
    block_entries = registries["minecraft:block"]["entries"]
    if set(blocks) != set(block_entries):
        raise ValueError("Block registry and block state report disagree")
    schemas = sorted([block_schema(name, value, block_entries[name]["protocol_id"]) for name, value in blocks.items()],
                     key=lambda schema: schema["protocol_id"])
    state_ids = sorted(state["id"] for value in blocks.values() for state in value["states"])
    if state_ids != list(range(len(state_ids))):
        raise ValueError("Global block state IDs are not unique contiguous IDs from zero")
    command_rows, command_summary = commands_table(commands)
    packet_rows = [[state, direction, name, record["protocol_id"]] for state, directions in sorted(packets.items())
                   for direction, entries in sorted(directions.items())
                   for name, record in sorted(entries.items(), key=lambda pair: pair[1]["protocol_id"])]
    item_rows, component_counts = [], collections.Counter()
    for path in sorted((report_root / "minecraft/components/item").glob("*.json")):
        value = json.loads(path.read_text())
        components = value["components"]
        component_counts.update(components.keys())
        item_rows.append(["minecraft:" + path.stem, sorted(components), digest(canonical(components))])
    if set(row[0] for row in item_rows) != set(registries["minecraft:item"]["entries"]):
        raise ValueError("Default component item report does not cover the complete item registry")

    data_rows, resource_rows, data_groups, resource_groups = [], [], {}, {}
    data_payloads, source_classes, built_in_packs, dimensions = {}, [], {}, {}
    generated_data = {str(path.relative_to(reports)): path for path in (reports / "data").rglob("*") if path.is_file()}
    comparisons = collections.Counter()
    compare_errors = []
    with zipfile.ZipFile(client) as jar:
        internal_version = json.loads(jar.read("version.json"))
        if internal_version["id"] != PIN:
            raise ValueError("Client internal version disagrees with metadata pin")
        for name in sorted(jar.namelist()):
            if name.endswith("/"):
                continue
            if name.startswith("net/minecraft/") and name.endswith(".class"):
                source_classes.append(name)
            if name.startswith("data/"):
                payload = jar.read(name)
                data_payloads[name] = payload
                location = data_location(name)
                if location:
                    scope, category, identifier, format_name = location
                    data_rows.append([scope, category, identifier, format_name, name, digest(payload)])
                    key = scope + ":" + category
                    group = data_groups.setdefault(key, {"scope": scope, "category": category, "files": [], "formats": collections.Counter(), "json": []})
                    group["files"].append((name, digest(payload)))
                    group["formats"][format_name] += 1
                    if format_name == "json":
                        parsed = json.loads(payload)
                        group["json"].append(parsed)
                        if category == "worldgen/world_preset":
                            dimensions[identifier] = parsed.get("dimensions", {})
                if "/datapacks/" in name and name.endswith("/pack.mcmeta"):
                    built_in_packs[name.split("/")[3]] = json.loads(payload)
                if name in generated_data:
                    generated = generated_data[name].read_bytes()
                    if payload == generated:
                        comparisons["byte_equal"] += 1
                    elif name.endswith(".json") and canonical(json.loads(payload)) == canonical(json.loads(generated)):
                        comparisons["json_equal_only"] += 1
                    else:
                        compare_errors.append(name)
            elif name.startswith("assets/"):
                payload = jar.read(name)
                parts = name.split("/")
                category = parts[2] if len(parts) > 2 else "_root"
                group = resource_groups.setdefault("client_jar:" + category, {"source": "client_jar", "category": category, "files": [], "formats": collections.Counter(), "json": []})
                group["files"].append((name, digest(payload)))
                extension = pathlib.PurePosixPath(name).suffix.lstrip(".") or "none"
                group["formats"][extension] += 1
                if extension in {"json", "mcmeta"}:
                    group["json"].append(json.loads(payload))
                resource_rows.append(["client_jar", category, name, extension, len(payload), digest(payload)])
        jar_entries, jar_files = len(jar.namelist()), sum(not name.endswith("/") for name in jar.namelist())
    missing_generated = sorted(set(generated_data) - set(data_payloads))
    expected_ungenerated = sorted(name for name in data_payloads if name not in generated_data)
    if compare_errors or missing_generated:
        raise ValueError(f"Official client/server generated data disagreement: {compare_errors[:5]}, {missing_generated[:5]}")
    if any(name != "data/.mcassetsroot" and "/structure/" not in name for name in expected_ungenerated):
        raise ValueError("Generator missed non-structure data content")
    asset_objects = json.loads(asset_index.read_text())["objects"]
    external_groups = collections.Counter()
    for name, record in sorted(asset_objects.items()):
        # Asset-index hashes are SHA-1 object addresses; objects are not fetched.
        category = "/".join(name.split("/")[:2]) if name.startswith("minecraft/") else name.split("/")[0]
        external_groups[category] += 1
        resource_rows.append(["asset_index", category, name, pathlib.PurePosixPath(name).suffix.lstrip(".") or "none", record["size"], record["hash"]])

    summarize = lambda group: {key: value for key, value in group.items() if key not in {"files", "json", "formats"}} | {
        "file_count": len(group["files"]), "content_tree_sha256": tree_hash(group["files"]),
        "formats": dict(sorted(group["formats"].items())), "observed_json_shapes": json_shape(group["json"])}
    data_summary = {key: summarize(value) for key, value in sorted(data_groups.items())}
    resource_summary = {key: summarize(value) for key, value in sorted(resource_groups.items())}
    class_groups = collections.Counter("/".join(name.split("/")[2:4]) for name in source_classes)
    report_hashes = {str(path.relative_to(reports)): {"bytes": path.stat().st_size, "canonical_json_sha256": digest(canonical(json.loads(path.read_text())))}
                     for path in sorted(report_root.rglob("*.json"))}
    report_summary = {"file_count": len(report_hashes),
                      "canonical_tree_sha256": tree_hash([(name, record["canonical_json_sha256"]) for name, record in report_hashes.items()]),
                      "principal_reports": {name: report_hashes["reports/" + name] for name in ["blocks.json", "registries.json", "commands.json", "packets.json", "datapack.json", "json-rpc-api-schema.json"]}}
    with zipfile.ZipFile(server) as bundle:
        libraries = [line.split("\t")[1] for line in bundle.read("META-INF/libraries.list").decode().splitlines()]
        version_bundle = bundle.read("META-INF/versions.list").decode().split("\t")
        nested_path = "META-INF/versions/" + version_bundle[2].strip()
        nested = bundle.read(nested_path)
        if digest(nested) != version_bundle[0]:
            raise ValueError("Bundled server inner SHA-256 mismatch")
    outputs = {}
    def table(name: str, headers: list[str], rows: list[list[object]]) -> None:
        path = ROOT / "generated" / ("reference_" + name + ".tsv")
        write_tsv(path, headers, rows)
        outputs[str(path.relative_to(ROOT))] = fingerprint(path) | {"rows": len(rows)}
    table("registries", ["registry", "protocol_id", "identifier"], registry_rows)
    table("blocks", ["block_protocol_id", "identifier", "first_state_id", "state_count", "default_state_id", "ordered_properties_json"],
          [[schema[k] for k in ["protocol_id", "identifier", "first_state_id", "state_count", "default_state_id", "properties"]] for schema in schemas])
    table("data", ["scope", "category", "identifier", "format", "jar_path", "sha256"], data_rows)
    table("resources", ["source", "category", "logical_path", "format", "bytes", "content_hash"], resource_rows)
    table("packets", ["state", "direction", "identifier", "protocol_id"], packet_rows)
    table("commands", ["display_path", "path_segments_json", "node_type", "executable", "parser", "properties_json", "redirect_json"], command_rows)
    table("item_components", ["item_identifier", "component_identifiers_json", "components_canonical_sha256"], item_rows)
    table("rpc_methods", ["name", "parameter_schema_json", "result_schema_json"],
          [[method["name"], method.get("params", []), method.get("result", {})] for method in sorted(rpc["methods"], key=lambda method: method["name"])])
    release = {"pin": PIN, "authority": "Installed client/version metadata; official downloads named by that metadata", "version_metadata": fingerprint(version_path),
               "client": fingerprint(client) | {"official": version["downloads"]["client"], "zip_entries": jar_entries, "zip_files": jar_files},
               "server_bundle": fingerprint(server) | {"official": version["downloads"]["server"], "nested_server_sha256": digest(nested), "libraries": libraries},
               "asset_index": fingerprint(asset_index) | {"official": asset_meta},
               "release_time": version["releaseTime"], "internal_version": internal_version,
               "runtime_version": (java_version.stdout + java_version.stderr).strip().splitlines(),
               "reports": report_summary}
    write_json(ROOT / "reference/release.json", release)
    inventory = {"pin": PIN, "inventory_is_implementation": False, "registry_counts": registry_counts,
                 "static_registry_count": len(registries), "static_registry_entry_count": len(registry_rows),
                 "block_state_count": len(state_ids), "block_state_id_range": [state_ids[0], state_ids[-1]],
                 "data_categories": data_summary, "resource_categories": resource_summary,
                 "built_in_data_packs": built_in_packs, "world_preset_dimensions": dimensions,
                 "asset_index_objects": len(asset_objects), "asset_index_unique_objects": len(set(record["hash"] for record in asset_objects.values())),
                 "asset_index_categories": dict(sorted(external_groups.items())), "asset_objects_downloaded_by_extractor": 0,
                 "commands": command_summary, "packet_count": len(packet_rows),
                 "packet_counts": {state: {direction: len(entries) for direction, entries in directions.items()} for state, directions in packets.items()},
                 "item_default_component_files": len(item_rows), "item_default_component_presence": dict(sorted(component_counts.items())),
                 "server_rpc": {"info": rpc["info"], "openrpc": rpc["openrpc"], "method_count": len(rpc["methods"]), "schema_count": len(rpc["components"]["schemas"])},
                 "named_client_class_files": len(source_classes), "named_class_groups": dict(sorted(class_groups.items())), "generated_tables": outputs,
                 "limitations": ["Static registry protocol IDs describe the pinned base release, not a modded registry order.",
                                 "Data identifiers have no assigned runtime protocol IDs in these tables.",
                                 "Observed JSON keys/discriminators are an empirical shape inventory, not complete codec schemas.",
                                 "Command syntax, packet IDs, default components and RPC schemas do not establish their executable semantics.",
                                 "Remote asset-index objects were inventoried by official metadata, not downloaded or decoded.",
                                 "Inventory extraction does not establish any implementation or behavioral verification coverage."]}
    write_json(ROOT / "reference/inventory.json", inventory)
    write_json(ROOT / "reference/datapack_structure.json", {"pin": PIN, "source": "official reports/datapack.json", "structure": datapack,
                                                          "codec_schemas_complete": False})
    checks = {"pinned_client_sha1_and_size": True, "pinned_server_sha1_and_size": True, "pinned_asset_index_sha1_and_size": True,
              "bundled_server_sha256": True, "all_block_report_ids_match_registry": True, "all_state_ids_unique_and_contiguous": True,
              "all_states_reconstructed_from_compact_schemas": True,
              "all_items_have_default_components": True, "generator_executed": not args.skip_generator,
              "generator_exit_code": 0 if not args.skip_generator else None,
              "client_vs_generated_data": {"generated_files": len(generated_data), **dict(comparisons), "mismatches": compare_errors,
                                           "generated_paths_absent_from_client": missing_generated,
                                           "client_paths_not_emitted": {"structure_nbt": sum("/structure/" in name for name in expected_ungenerated),
                                                                        "mcassetsroot": int("data/.mcassetsroot" in expected_ungenerated)}}}
    evidence = {"pin": PIN, "kind": "reference_inventory_only", "command": shlex.join(command), "working_directory": str(cache),
                "reproduce": "python3 tools/reference_inventory.py", "checks": checks,
                "counts": {"blocks": len(blocks), "states": len(state_ids), "items": len(item_rows),
                           "entities": registry_counts["minecraft:entity_type"], "static_registries": len(registries), "static_entries": len(registry_rows),
                           "data_elements_and_tags": len(data_rows), "client_resources": sum(row[0] == "client_jar" for row in resource_rows),
                           "external_asset_names": len(asset_objects), "command_nodes": len(command_rows), "packets": len(packet_rows), "rpc_methods": len(rpc["methods"])},
                "official_reference_hashes": {"client_sha256": fingerprint(client)["sha256"], "server_sha256": fingerprint(server)["sha256"],
                                              "asset_index_sha256": fingerprint(asset_index)["sha256"], "reports_canonical_tree_sha256": report_summary["canonical_tree_sha256"]},
                "generated_tables": outputs, "behavioral_parity_established": False}
    write_json(ROOT / "evidence/reference_inventory.json", evidence)
    print(json.dumps(evidence["counts"], sort_keys=True))


if __name__ == "__main__":
    main()
