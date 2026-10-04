#!/usr/bin/env python3
"""Prepare/check and optionally run the actual native block catalog IO harness.

The default is source checking plus independent fixture preparation. Explicit
--build-native or --reuse-native runs the narrow production import graph; no
projected implementation, substituted parser or host game semantics is used.
"""
from __future__ import annotations

import argparse
import collections
import copy
import csv
import hashlib
import io
import json
import os
import pathlib
import signal
import struct
import subprocess
import sys
import time
import zipfile
import zlib

import build_native
import test_registry
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
BEND = pathlib.Path.home() / ".bend/bin/bend"
ENTRY = ROOT / "tests/resource_block_catalog.bend"
REFERENCE = ROOT / "reference/resource_block_catalog.json"
REFERENCE_EVIDENCE = ROOT / "evidence/resource-block-catalog-reference.json"
EVIDENCE = ROOT / "evidence/resource-block-catalog-tests.json"
WORK = ROOT / "build/resource-block-catalog-tests"
BINARY = WORK / "native"
PRIVATE = WORK / "private-001"
PRIVATE_BASIS = ROOT / "build/playable-renderer-current/004"
PRODUCER_BASIS = ROOT / "build/compiler-producer-diagnostic-012"
JAR = pathlib.Path.home() / "Library/Application Support/minecraft/versions/26.3/26.3.jar"
REGISTRY = ROOT / "generated/reference_blocks.tsv"
ENV = {**os.environ, "BEND_MINECRAFT_LAUNCH_MODE": "hidden"}
HEADER = "block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json"


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def sha(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def sources():
    snapshot = build_native.Snapshot()
    base = BEND.resolve().parent.parent / "bend2/base.bend"
    build_native.source_graph(ENTRY, base.resolve(), ENV, snapshot)
    return {item["lookup"]: {"sha256": item["sha256"], "bytes": item["bytes"], "kind": item["kind"]}
            for item in snapshot.manifest()} | {str(BEND): {"sha256": sha(BEND), "kind": "compiler", "bytes": BEND.stat().st_size}}


class ProcessFailure(RuntimeError):
    def __init__(self, receipt):
        self.receipt = receipt
        super().__init__(f"{receipt['tag']} {receipt['status']}; logs retained under {WORK}")


def run(command, tag, timeout):
    started = time.monotonic()
    print(json.dumps({"phase": tag, "status": "running"}), flush=True)
    command = list(map(str, command))
    process = subprocess.Popen(command, cwd=ROOT, env=ENV, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, start_new_session=True)
    timed_out = False
    timeout_signals = []
    def signal_group(value):
        try:
            os.killpg(process.pid, value)
            timeout_signals.append(signal.Signals(value).name)
        except ProcessLookupError:
            pass
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        signal_group(signal.SIGTERM)
        try:
            stdout, stderr = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            signal_group(signal.SIGKILL)
            try:
                stdout, stderr = process.communicate(timeout=5)
            except subprocess.TimeoutExpired as error:
                # A descendant that deliberately changed its process group
                # can retain a pipe. Close our pipes and still bound cleanup.
                stdout = error.stdout.decode(errors="replace") if isinstance(error.stdout, bytes) else error.stdout or ""
                stderr = error.stderr.decode(errors="replace") if isinstance(error.stderr, bytes) else error.stderr or ""
                process.stdout.close()
                process.stderr.close()
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=5)
        # A child may close inherited pipes before exiting. Reap only this
        # isolated command's group, never unrelated compiler processes.
        signal_group(signal.SIGKILL)
    result = subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
    (WORK / f"{tag}.stdout.log").write_text(result.stdout)
    (WORK / f"{tag}.stderr.log").write_text(result.stderr)
    receipt = {"tag": tag, "command": command, "pid": process.pid, "process_group": process.pid,
               "status": "timed_out" if timed_out else "passed" if result.returncode == 0 else "failed",
               "timeout_signals": timeout_signals, "leader_reaped": process.returncode is not None,
               "timeout_seconds": timeout, "exit_code": result.returncode,
               "seconds": round(time.monotonic() - started, 3), "stdout_sha256": sha(WORK / f"{tag}.stdout.log"),
               "stderr_sha256": sha(WORK / f"{tag}.stderr.log")}
    print(json.dumps({"phase": tag, "exit_code": result.returncode, "seconds": receipt["seconds"]}), flush=True)
    (WORK / f"{tag}.receipt.json").write_bytes(canonical(receipt) + b"\n")
    if timed_out or result.returncode != 0:
        if tag.startswith("native") and EVIDENCE.is_file():
            evidence = json.loads(EVIDENCE.read_text())
            evidence["status"] = "source_checked_native_timeout" if timed_out else "source_checked_native_failed"
            evidence.setdefault("native_attempts", []).append({**receipt, "driver_sha256": sha(__file__),
                "source_manifest_sha256": hashlib.sha256(canonical(evidence["sources"])).hexdigest(),
                "binary_created": BINARY.is_file(), "isolated_process_group_signalled_on_timeout": timed_out})
            EVIDENCE.write_text(json.dumps(evidence, sort_keys=True, indent=2) + "\n")
        raise ProcessFailure(receipt)
    return result, receipt


def png():
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\0\xff\xff\xff\xff")) + chunk(b"IEND", b""))


def archive(name, entries):
    path = WORK / (name + ".zip")
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as target:
        for key, value in sorted(entries.items()):
            info = zipfile.ZipInfo(key, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            target.writestr(info, value.encode() if isinstance(value, str) else value)
    return path


def resource(identifier, category, extension):
    namespace, path = identifier.split(":", 1)
    return f"assets/{namespace}/{category}/{path}{extension}"


def resource_usage(config, roots, sprite_layers):
    """ZIP declarations and Pillow dimensions, independent of production counters."""
    pending, models = list(roots), set()
    text_bytes = png_bytes = pixels = 0
    with zipfile.ZipFile(config["jar"]) as jar:
        while pending:
            name = pending.pop()
            if name in models:
                continue
            models.add(name)
            raw = jar.read(resource(name, "models", ".json"))
            text_bytes += len(raw)
            parent = json.loads(raw).get("parent")
            if parent:
                pending.append(parent if ":" in parent else "minecraft:" + parent)
        entries = set(jar.namelist())
        for name in sprite_layers:
            path = resource(name, "textures", ".png")
            raw = jar.read(path)
            png_bytes += len(raw)
            with Image.open(io.BytesIO(raw)) as image:
                width, height = image.size
                pixels += width * height
            if path + ".mcmeta" in entries:
                text_bytes += len(jar.read(path + ".mcmeta"))
    return {"models": len(models), "sprites": len(sprite_layers), "text": text_bytes,
            "png": png_bytes, "pixels": pixels}


def variant(name, y=0, lock=False):
    return {"model": "test:block/" + name, "x": 0, "y": y, "z": 0, "uvlock": lock}


def single(value):
    return {"kind": "single", "variant": value}


def weighted(entries):
    return {"kind": "weighted", "total": sum(weight for value, weight in entries),
            "entries": [{"variant": value, "weight": weight} for value, weight in entries]}


def selected(choice, ticket):
    if choice["kind"] == "single":
        return choice["variant"]
    assert ticket is not None and 0 <= ticket < choice["total"]
    remaining = ticket
    for entry in choice["entries"]:
        if remaining < entry["weight"]:
            return entry["variant"]
        remaining -= entry["weight"]
    raise AssertionError("Unreachable weighted oracle")


def selected_variants(root, query):
    if root is None:
        return []
    ticket = 0 if query.get("first") else query.get("ticket")
    if root["kind"] == "variant":
        return [selected(root["choice"], ticket)]
    return [selected(part["choice"], 0 if query.get("first") else query.get("parts", {}).get(str(part["index"])))
            for part in root["parts"]]


def registry_records(path):
    records = []
    with pathlib.Path(path).open() as source:
        for row in csv.DictReader(source, delimiter="\t"):
            ordered = json.loads(row["ordered_properties_json"])
            stride = 1
            properties = []
            for prop in reversed(ordered):
                properties.append({"name": prop["name"], "values": prop["values"], "count": len(prop["values"]), "stride": stride})
                stride *= len(prop["values"])
            records.append({"protocol": int(row["block_protocol_id"]), "name": row["identifier"],
                            "first": int(row["first_state_id"]), "count": int(row["state_count"]),
                            "default": int(row["default_state_id"]), "properties": list(reversed(properties))})
    return records


def state_identity(block, state):
    return {"block_protocol_id": block["block_protocol_id"], "identifier": block["identifier"],
            "id": state["id"], "properties": state["properties"]}


def synthetic_geometry():
    return {"face_count": 6, "texture_usage": [{"sprite": "test:block/tex", "layer": "solid", "tintindex": -1, "faces": 6}]}


def fixture_data():
    fixture = json.loads(REFERENCE.read_text())
    seal = json.loads(REFERENCE_EVIDENCE.read_text())
    assert fixture["pin"] == seal["pin"] == "26.3"
    assert sha(REFERENCE) == seal["fixture"]["sha256"]
    assert sha(JAR) == fixture["sources"]["client"]["sha256"]
    assert sha(REGISTRY) == fixture["sources"]["tables"]["generated/reference_blocks.tsv"]["sha256"]
    states = {}
    for name in fixture["static_solid_cutout_profile"]["blocks"]:
        block = fixture["blocks"][name]
        for state in block["states"]:
            states[state["id"]] = {**state, "identity": state_identity(block, state), "mode": "model"}
    states[0] = {"id": 0, "properties": {}, "identity": {"block_protocol_id": 0, "identifier": "minecraft:air", "id": 0, "properties": {}},
                 "root": None, "dependencies": [], "mode": "invisible"}
    return fixture, states


def cases(fixture, official):
    out = []
    profile = fixture["static_solid_cutout_profile"]
    official_identity = test_registry.identity_hash(registry_records(REGISTRY))
    def add(name, config, *, code=None, states=official, models=fixture["models"], sprite_layers=profile["sprite_layers"],
            registry_identity=official_identity, root_names=None, query_errors=None, pure=False):
        config = {"jar": str(JAR), "registry": str(REGISTRY), **config}
        requests = config.get("requests")
        if root_names is None and not pure:
            requested = set(profile["blocks"]) if requests is None else {item["name"].split(":", 1)[-1] for item in requests if item.get("mode", "model") != "invisible"}
            root_names = sorted({dependency for state in states.values() if state["identity"]["identifier"].split(":", 1)[-1] in requested for dependency in state["dependencies"]})
        out.append({"name": name, "config": config, "expected": {"code": code, "states": states,
                    "models": models, "sprite_layers": sprite_layers, "registry_identity": registry_identity,
                    "model_roots": root_names, "query_errors": query_errors or {}, "pure": pure}})
    queries = [{"state": state, "first": True} for state in sorted(official)]
    for state in official.values():
        root = state["root"]
        if root is not None and root["kind"] == "variant" and root["choice"]["kind"] == "weighted":
            queries.extend({"state": state["id"], "ticket": ticket} for ticket in range(root["choice"]["total"]))
    errors = {}
    for state in (1, 9, 10, 121):
        for query, code in (({"state": state}, "MissingRandomTicket"),
                            ({"state": state, "ticket": 4}, "Blockstate:TicketOutOfRange"),
                            ({"state": state, "ticket": 4294967295}, "Blockstate:TicketOutOfRange")):
            errors[len(queries)] = code
            queries.append(query)
        queries.append({"state": state, "ticket": 0})
    queries += [{"state": 15}, {"state": 15, "ticket": 4294967295}]
    errors[len(queries)] = "StateNotLoaded"
    queries.append({"state": 35722, "first": True})
    add("official-all-states-and-weighted-boundaries", {"queries": queries}, query_errors=errors)
    reverse_requests = [{"name": "minecraft:" + name, "mode": "model"} for name in reversed(profile["blocks"])] + [{"name": "minecraft:air", "mode": "invisible"}]
    add("official-reordered-requests", {"requests": reverse_requests, "queries": queries}, query_errors=errors)
    text_bytes = sum(fixture["resources"][f"assets/minecraft/blockstates/{name}.json"]["bytes"] for name in profile["blocks"])
    add("official-exact-catalog-budgets", {"queries": [{"state": 8666, "first": True}, {"state": 0}],
                                          "max_blocks": 12, "max_states": 130, "max_state_text": text_bytes})
    for name, edit, code in (("request-budget", {"max_blocks": 11}, "BlockBudget"),
                             ("state-budget", {"max_states": 129}, "StateBudget"),
                             ("blockstate-text-budget", {"max_state_text": text_bytes - 1}, "BlockstateByteBudget"),
                             ("invalid-catalog-limits", {"max_states": 65536}, "Limits"),
                             ("resource-root-budget", {"resources": {"models": 0}}, "Resource:RootBudget"),
                             ("resource-model-closure-budget", {"resources": {"models": 19}}, "Resource:ModelBudget"),
                             ("resource-sprite-budget", {"resources": {"sprites": 0}}, "Resource:SpriteBudget")):
        add(name, edit, code=code)
    nonexistent = str(WORK / "does-not-exist.zip")
    for name, request_values, code in (("duplicate-block", [{"name": "minecraft:stone"}] * 2, "DuplicateBlock"),
                                       ("missing-block", [{"name": "test:missing"}], "Registry"),
                                       ("unsupported-water", [{"name": "minecraft:water"}], "UnsupportedRenderer"),
                                       ("unsupported-chest", [{"name": "minecraft:chest"}], "UnsupportedRenderer")):
        add(name, {"jar": nonexistent, "requests": request_values}, code=code)
    add("official-glass-metadata", {"requests": [{"name": "minecraft:glass", "mode": "model"}],
                                    "layers": {"minecraft:block/glass": "translucent"}}, code="Resource:UnsupportedMetadata")
    add("unclassified-water-animation-rejection", {"requests": [{"name": "minecraft:water", "mode": "model"}],
        "layers": {"minecraft:block/water_still": "translucent"}, "resources": {"side": 1024}}, code="Resource:UnsupportedAnimation")

    registry = WORK / "custom-registry.tsv"
    registry.write_text(HEADER + '\n0\ttest:signal\t0\t2\t0\t[{"name":"lit","values":["false","true"]}]\n')
    custom_identity = test_registry.identity_hash(registry_records(registry))
    cube = {"textures": {"all": "test:block/tex"}, "elements": [{"from": [0, 0, 0], "to": [16, 16, 16],
            "faces": {direction: {"texture": "#all", "cullface": direction} for direction in ("down", "up", "north", "south", "west", "east")}}]}
    base_entries = {resource("test:block/tex", "textures", ".png"): png()}
    for name in ("off", "on", "base", "alternate"):
        base_entries[resource("test:block/" + name, "models", ".json")] = canonical(cube)
    variant_definition = {"variants": {"lit=false": {"model": "test:block/off"}, "lit=true": {"model": "test:block/on", "y": 90, "uvlock": True}}}
    part_definition = {"multipart": [{"apply": {"model": "test:block/base"}},
        {"when": {"lit": "true"}, "apply": [{"model": "test:block/on", "y": 90, "uvlock": True, "weight": 1},
                                               {"model": "test:block/alternate", "y": 180, "weight": 3}]}]}
    v_off, v_on, v_base, v_alt = variant("off"), variant("on", 90, True), variant("base"), variant("alternate", 180)
    roots = {"variant": [{"kind": "variant", "choice": single(v_off)}, {"kind": "variant", "choice": single(v_on)}],
             "multipart": [{"kind": "multipart", "parts": [{"index": 0, "choice": single(v_base)}]},
                           {"kind": "multipart", "parts": [{"index": 0, "choice": single(v_base)},
                             {"index": 1, "choice": weighted([(v_on, 1), (v_alt, 3)])}]}]}
    custom_models = {"test:block/" + name: {"geometry": synthetic_geometry()} for name in ("off", "on", "base", "alternate")}
    all_custom = {}
    for kind in ("variant", "multipart"):
        dependencies = [["test:block/off"], ["test:block/on"]] if kind == "variant" else [["test:block/alternate", "test:block/base", "test:block/on"]] * 2
        custom = {state: {"id": state, "properties": {"lit": lit}, "identity": {"block_protocol_id": 0, "identifier": "test:signal", "id": state, "properties": {"lit": lit}},
                          "root": roots[kind][state], "dependencies": dependencies[state], "mode": "model"}
                  for state, lit in enumerate(("false", "true"))}
        all_custom[kind] = custom
        q = [{"state": 0}, {"state": 1, "first": True}]
        qerrors = {}
        if kind == "multipart":
            q += [{"state": 1, "parts": {"1": ticket}} for ticket in range(4)]
            for query, code in (({"state": 1}, "MissingRandomTicket"),
                                ({"state": 1, "parts": {"0": 0}}, "MissingRandomTicket"),
                                ({"state": 1, "parts": {"1": 4}}, "Blockstate:TicketOutOfRange")):
                qerrors[len(q)] = code
                q.append(query)
            q += [{"state": 0, "parts": {"1": 4294967295}}, {"state": 1, "parts": {"1": 3}}]
        else:
            q += [{"state": 1, "ticket": 4294967295}]
        add("pure-generic-" + kind, {"mode": "pure", "kind": kind, "queries": q}, states=custom, models=custom_models,
            sprite_layers={"test:block/tex": "solid"}, registry_identity="synthetic-registry-identity", query_errors=qerrors, pure=True)
        entries = {**base_entries, resource("test:signal", "blockstates", ".json"): canonical(variant_definition if kind == "variant" else part_definition)}
        custom_jar = archive("custom-" + kind, entries)
        add("io-generic-" + kind, {"jar": str(custom_jar), "registry": str(registry), "requests": [{"name": "test:signal", "mode": "model"}],
            "layers": {"test:block/tex": "solid"}, "queries": q}, states=custom, models=custom_models,
            sprite_layers={"test:block/tex": "solid"}, registry_identity=custom_identity, query_errors=qerrors)
    add("pure-forged-state-identity", {"mode": "pure", "kind": "forged", "queries": [{"state": 0}]}, states=all_custom["variant"],
        query_errors={0: "StateIdentityMismatch"}, pure=True)
    def custom_case(name, entries, code=None, queries=None, query_errors=None):
        add(name, {"jar": str(archive(name, entries)), "registry": str(registry),
                   "requests": [{"name": "test:signal", "mode": "model"}], "layers": {"test:block/tex": "solid"},
                   "queries": queries or []}, code=code, states=all_custom["variant"], models=custom_models,
            sprite_layers={"test:block/tex": "solid"}, registry_identity=custom_identity, query_errors=query_errors)
    state_path = resource("test:signal", "blockstates", ".json")
    custom_case("missing-blockstate", {}, "MissingBlockstate")
    partial = {"variants": {"lit=false": {"model": "test:block/off"}}}
    custom_case("partial-state-model", {**base_entries, state_path: canonical(partial)}, "MissingStateModel")
    custom_case("unknown-selector-property", {**base_entries, state_path: canonical({"variants": {"missing=true": {"model": "test:block/off"}}})}, "BlockstateDiagnostic:SelectorUnknownProperty")
    missing_model = {key: value for key, value in base_entries.items() if key != resource("test:block/on", "models", ".json")}
    custom_case("missing-unselected-variant-model", {**missing_model, state_path: canonical(variant_definition)}, "Resource:MissingResource")
    empty_entries = {**base_entries, state_path: canonical(variant_definition), resource("test:block/off", "models", ".json"): '{"textures":{"particle":"test:block/tex"}}'}
    custom_case("particle-only-model-bind-rejection", empty_entries, queries=[{"state": 0}, {"state": 1}], query_errors={0: "EmptyModelGeometry"})
    invisible = {**all_custom["variant"]}
    invisible = {key: {**value, "root": None, "dependencies": [], "mode": "invisible"} for key, value in invisible.items()}
    add("custom-invisible-needs-no-blockstate", {"jar": str(archive("empty", {})), "registry": str(registry),
        "requests": [{"name": "test:signal", "mode": "invisible"}], "layers": {}, "queries": [{"state": 0}, {"state": 1}],
        "max_blocks": 1, "max_states": 2, "max_state_text": 0}, states=invisible, models={}, sprite_layers={}, registry_identity=custom_identity, root_names=[])
    add("empty-request-zero-catalog-budgets", {"jar": str(WORK / "empty.zip"), "requests": [], "layers": {},
        "max_blocks": 0, "max_states": 0, "max_state_text": 0, "queries": []}, states=official, models={}, sprite_layers={}, root_names=[])
    for case in out:
        expected = case["expected"]
        if not expected["pure"] and expected["code"] is None:
            expected["usage"] = resource_usage(case["config"], expected["model_roots"], expected["sprite_layers"])
    return out


def verify(case, report):
    expected, config = case["expected"], case["config"]
    first = expected["states"].get(0)
    if not expected["pure"]:
        assert report["registry_after"] == first["identity"], (case["name"], "registry owner/readback", report)
    if expected["code"]:
        assert report["status"] == "error" and report["code"] == expected["code"], (case["name"], report, expected["code"])
        return {"name": case["name"], "status": "rejected", "code": report["code"]}
    assert report["status"] == "ok", (case["name"], report)
    if expected["pure"] and config.get("kind") != "forged":
        assert report["states"] == len(expected["states"])
        assert report["models"] == sorted({name for state in expected["states"].values() for name in state["dependencies"]})
    if not expected["pure"]:
        assert report["registry_identity"] == expected["registry_identity"], (case["name"], "registry identity")
        assert report["model_roots"] == expected["model_roots"], (case["name"], "model root closure", report["model_roots"], expected["model_roots"])
        assert report["usage"] == expected["usage"], (case["name"], "resource usage", report["usage"], expected["usage"])
        actual_sprites = {sprite["id"]: sprite for sprite in report["sprites"]}
        assert sorted(actual_sprites) == sorted(expected["sprite_layers"]), (case["name"], "sprite closure")
        for slot, name in enumerate(sorted(expected["sprite_layers"])):
            sprite = actual_sprites[name]
            with zipfile.ZipFile(config["jar"]) as jar:
                with Image.open(io.BytesIO(jar.read(resource(name, "textures", ".png")))) as image:
                    rgba = image.convert("RGBA").tobytes()
                    width, height = image.size
            pixels = [(a << 24) | (r << 16) | (g << 8) | b for r, g, b, a in zip(rgba[0::4], rgba[1::4], rgba[2::4], rgba[3::4])]
            assert sprite == {"id": name, "slot": slot, "width": width, "height": height, "layer": expected["sprite_layers"][name],
                              "texture_width": width, "texture_height": height, "side": 1 << (max(width, height) - 1).bit_length(),
                              "pixels": pixels}, (case["name"], name, "texture pixel/header readback")
        slots = {name: sprite["slot"] for name, sprite in actual_sprites.items()}
    else:
        slots = {}
    assert len(report["queries"]) == len(config.get("queries", []))
    successes = errors = quads = 0
    for index, (query, actual) in enumerate(zip(config.get("queries", []), report["queries"])):
        state = query["state"]
        if index in expected["query_errors"] and expected["query_errors"][index] in ("StateNotLoaded", "StateIdentityMismatch"):
            assert actual["status"] == "error" and actual["code"] == expected["query_errors"][index], (case["name"], query, actual)
            errors += 1
            continue
        reference = expected["states"][state]
        assert actual["state"] == state
        assert actual["lookup"] == {"identity": reference["identity"], "mode": reference["mode"], "root": reference["root"],
                                    "dependencies": reference["dependencies"]}, (case["name"], query, "lookup", actual["lookup"], reference)
        result = actual["selected" if expected["pure"] else "bound"]
        if index in expected["query_errors"]:
            assert result["status"] == "error" and result["code"] == expected["query_errors"][index], (case["name"], query, result)
            errors += 1
            continue
        variants = selected_variants(reference["root"], query)
        assert result["status"] == "ok" and result["variants"] == variants, (case["name"], query, "selected variants", result, variants)
        successes += 1
        if expected["pure"]:
            continue
        assert result["identity"] == reference["identity"] and result["state"] == state
        usages = collections.Counter()
        for chosen in variants:
            for usage in expected["models"][chosen["model"]]["geometry"]["texture_usage"]:
                usages[(usage["sprite"], usage["layer"], usage["tintindex"] & 0xffffffff)] += usage["faces"]
        observed = collections.Counter((quad["sprite"], quad["layer"], quad["tintindex"]) for quad in result["quads"])
        assert observed == usages, (case["name"], query, "quad texture/layer/tint summary", observed, usages)
        assert result["quad_count"] == sum(usages.values()) == len(result["quads"]), (case["name"], query, "quad count")
        for quad in result["quads"]:
            assert quad["texture"] == slots[quad["sprite"]] and not quad["animated"] and not quad["force_translucent"], (case["name"], query, quad)
        quads += result["quad_count"]
    pixel_hashes = {} if expected["pure"] else {name: hashlib.sha256(b"".join(pixel.to_bytes(4, "big") for pixel in sprite["pixels"])).hexdigest()
                                              for name, sprite in actual_sprites.items()}
    return {"name": case["name"], "status": "passed", "query_successes": successes, "query_rejections": errors, "checked_quads": quads,
            "texture_argb_sha256": pixel_hashes}


def native(corpus, iteration):
    reports, receipts = [], []
    for start in range(0, len(corpus), 8):
        group = corpus[start:start + 8]
        result, receipt = run([BINARY, "--threads", "1", "--gpu", "off", *[canonical(case["config"]).decode() for case in group]],
                              f"native-{iteration}-{start}", 180)
        lines = result.stdout.splitlines()
        assert len(lines) == len(group), ("native report count", start, result.stdout[-1500:])
        reports.extend(json.loads(line) for line in lines)
        receipts.append(receipt)
    return reports, receipts


def prepare_private(before):
    """Relocate the measured queue/zero-guard producer; retain exact source bytes."""
    manifest_path = PRIVATE / "manifest.json"
    if manifest_path.is_file():
        manifest = json.loads(manifest_path.read_text())
        assert manifest["production_sources"] == before, "Private source generation differs"
        assert all(sha(path) == expected for path, expected in manifest["files"].items()), "Private generation changed"
        return manifest
    assert not PRIVATE.exists(), "Unrecorded private generation; preserve rather than overwrite"
    basis = json.loads((PRIVATE_BASIS / "emission-receipt.json").read_text())
    assert basis["exit_code"] == 0 and not basis["timed_out"] and basis["cleanup"]["live_group_absent"]
    private_compiler = PRIVATE_BASIS / "comp_instrumented.ts"
    api = ROOT.parent / "bend/bend2/bend.ts"
    foreign_root = (BEND.resolve().parent.parent / "bend2").resolve()
    original_compiler = api.with_name("comp.ts")
    known = json.loads((PRODUCER_BASIS / "receipt.json").read_text())["source_before"]
    assert sha(api) == known[str(api)] and sha(original_compiler) == known[str(original_compiler)]
    assert sha(PRODUCER_BASIS / "comp_instrumented.ts") == known[str(PRODUCER_BASIS / "comp_instrumented.ts")]
    # The two measured private producers differ only in their output directory.
    assert private_compiler.read_text().replace(str(PRIVATE_BASIS), str(PRODUCER_BASIS)) == (PRODUCER_BASIS / "comp_instrumented.ts").read_text()
    PRIVATE.mkdir(parents=True)
    files, mapping = {}, []
    def frozen(original, target, expected):
        raw = original.read_bytes()
        assert hashlib.sha256(raw).hexdigest() == expected, (original, "source changed before freezing")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
        target.chmod(0o444)
        files[str(target)] = expected
        mapping.append({"original": str(original), "mapped": str(target), "sha256": expected, "bytes": len(raw)})
    seen = set()
    for lookup, pin in before.items():
        original = pathlib.Path(lookup).resolve()
        if original in seen or pin["kind"] == "compiler":
            continue
        seen.add(original)
        if original.is_relative_to(ROOT):
            target = PRIVATE / "source" / original.relative_to(ROOT)
        else:
            assert original.is_relative_to(foreign_root), (original, "unexpected foreign dependency")
            relative = original.relative_to(foreign_root)
            assert sha(api.parent / relative) == pin["sha256"], (original, "installed/source-API foreign bytes differ")
            target = PRIVATE / "source-api" / relative
        frozen(original, target, pin["sha256"])
    frozen(api, PRIVATE / "source-api/bend.ts", sha(api))
    # Path relocation changes only module/log destinations in the existing
    # private compiler. The queue and available-arity guard remain untouched.
    compiler_text = private_compiler.read_text().replace(str(PRIVATE_BASIS), str(PRIVATE)).replace(api.as_uri(), (PRIVATE / "source-api/bend.ts").as_uri())
    (PRIVATE / "comp_instrumented.ts").write_text(compiler_text)
    emitter_text = (PRIVATE_BASIS / "emit.mjs").read_text().replace(str(PRIVATE_BASIS), str(PRIVATE)).replace(api.as_uri(), (PRIVATE / "source-api/bend.ts").as_uri())
    emitter_text = emitter_text.replace(str(PRIVATE / "source/remote_resource_client.bend"), str(PRIVATE / "source/tests/resource_block_catalog.bend"))
    (PRIVATE / "diagnose.mjs").write_text(emitter_text)
    (PRIVATE / "run.py").write_bytes((PRODUCER_BASIS / "run.py").read_bytes())
    source_map = PRIVATE / "source-map.json"
    source_map.write_bytes(canonical({"schema": 1, "files": mapping}) + b"\n")
    for path in (PRIVATE / "comp_instrumented.ts", PRIVATE / "diagnose.mjs", PRIVATE / "run.py", source_map,
                 api, original_compiler, private_compiler, PRIVATE_BASIS / "emit.mjs", PRODUCER_BASIS / "run.py", pathlib.Path(basis["argv"][0])):
        files[str(path)] = sha(path)
    assert sources() == before, "Production bytes changed during freezing"
    manifest = {"schema": 1, "scope": "Exact catalog observer graph and foreign source bytes; existing measured private queue/zero-arity producer relocated only. Original compiler untouched; no product-cache promotion.",
                "production_sources": before, "files": files, "entry": str(PRIVATE / "source/tests/resource_block_catalog.bend"),
                "limits": {"heap_mib": 6144, "total_seconds": 600, "producer_stall_seconds": 90, "sampled_rss_bytes": 8589934592},
                "basis": {"emission_receipt_sha256": sha(PRIVATE_BASIS / "emission-receipt.json"), "private_compiler_sha256": sha(private_compiler),
                          "source_api_sha256": sha(api), "original_compiler_sha256": sha(original_compiler), "bounded_runner_sha256": sha(PRODUCER_BASIS / "run.py")}}
    manifest_path.write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n")
    return manifest


def build_private(before):
    manifest = prepare_private(before)
    assert not (PRIVATE / "receipt.json").exists(), "Private attempt already recorded; no equivalent retry"
    result, envelope = run([sys.executable, PRIVATE / "run.py"], "native-private-emission", 620)
    receipt = json.loads((PRIVATE / "receipt.json").read_text())
    assert receipt["returncode"] == 0 and receipt["termination_reason"] is None and receipt["group_absent"] and receipt["complete_C"], receipt
    assert receipt["source_before"] == receipt["source_after"] == manifest["files"]
    loaded = json.loads((PRIVATE / "loaded-source-pins.json").read_text())
    assert loaded == json.loads((PRIVATE / "final-source-pins.json").read_text())
    assert all(sha(path) == expected for path, expected in loaded.items())
    generated = PRIVATE / "diagnostic.c"
    assert sha(generated) == receipt["C"]["sha256"] and generated.stat().st_size == receipt["C"]["bytes"]
    build_native.guard_route(generated.read_text())
    sdk = subprocess.check_output(["/usr/bin/xcrun", "--show-sdk-path"], text=True).strip()
    command = ["/usr/bin/env", "SDKROOT=" + sdk, "/usr/bin/clang", "-std=c11", "-O3", generated, "-lpthread", "-lm", "-o", BINARY]
    clang_before = sha("/usr/bin/clang")
    compiled, native_receipt = run(command, "native-private-clang", 300)
    assert compiled.stderr == "" and sha("/usr/bin/clang") == clang_before and sources() == before
    return {"route": "measured-private-source-api-producer", "emission": envelope, "producer_receipt_sha256": sha(PRIVATE / "receipt.json"),
            "manifest_sha256": sha(PRIVATE / "manifest.json"), "source_map_sha256": sha(PRIVATE / "source-map.json"),
            "loaded_source_pins_sha256": sha(PRIVATE / "loaded-source-pins.json"), "C": receipt["C"],
            "sampled_peak_rss_bytes": receipt["sampled_peak_rss_bytes"], "clang": native_receipt,
            "basis": manifest["basis"], "product_cache_promoted": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--build-native", action="store_true", help="build/run after coordinating a heavy-job slot")
    mode.add_argument("--reuse-native", action="store_true", help="run only a binary with an exact source stamp")
    mode.add_argument("--prepare-private", action="store_true", help="freeze the existing measured private producer without emission")
    mode.add_argument("--build-private", action="store_true", help="emit with the existing measured private producer after slot coordination")
    parser.add_argument("--build-timeout", type=int, default=600)
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    previous = json.loads(EVIDENCE.read_text()) if EVIDENCE.is_file() else {}
    native_attempts = previous.get("native_attempts", [])
    fixture, states = fixture_data()
    corpus = cases(fixture, states)
    (WORK / "cases.json").write_bytes(canonical(corpus) + b"\n")
    before = sources()
    assert before[str(BEND)]["sha256"] == build_native.PINNED_BEND_SHA256
    check_reused = bool((args.prepare_private or args.build_private) and previous.get("sources") == before
                        and previous.get("source_check", {}).get("exit_code") == 0)
    if check_reused:
        check_receipt = previous["source_check"]
    else:
        check, check_receipt = run([BEND, ENTRY, "--check-only"], "source-check", 90)
        assert "ALL PROOFS CHECK" in check.stdout, check.stdout
    assert sources() == before, "Production source changed during source checking"
    status = "source_checked_native_timeout" if native_attempts and native_attempts[-1]["status"] == "timed_out" else "source_checked_native_pending"
    evidence = {"schema": 1, "status": status, "confidence": "high for independent fixture preparation and source checking; native behavior unverified",
                "commands": {"prepare": "python3 tools/resource_block_catalog_test.py", "native": "python3 tools/resource_block_catalog_test.py --build-native",
                             "private_prepare": "python3 tools/resource_block_catalog_test.py --prepare-private", "private_native": "python3 tools/resource_block_catalog_test.py --build-private"},
                "sources": before, "driver_sha256": sha(__file__), "reference_sha256": sha(REFERENCE), "jar_sha256": sha(JAR),
                "source_check": check_receipt, "source_check_reused_for_identical_bytes": check_reused,
                "preparation": {"cases": len(corpus), "official_states_including_air": len(states),
                    "official_queries": len(corpus[0]["config"]["queries"]), "fixture_manifest_sha256": sha(WORK / "cases.json"),
                    "native_invocations": 0, "native_checked_quads": 0},
                "native_attempts": native_attempts,
                "cases": [{"name": case["name"], "expected_load_error": case["expected"]["code"], "expected_usage": case["expected"].get("usage"),
                           "queries": len(case["config"].get("queries", [])), "expected_query_errors": case["expected"]["query_errors"]} for case in corpus],
                "scope": ["Actual production catalog, IO loader, profile, registry, archive, PNG, blockstate and bake imports remain byte-identical; no projected clone.",
                          "Prepared native checks cover all 129 official static block state components plus air, and all four alternatives of each weighted official root.",
                          "Prepared cases cover arbitrary test: namespace variant/multipart planning and real IO loading, explicit ticket and budget boundaries, and state-0 decode from the returned registry after load success/failure.",
                          "Prepared oracle compares per-quad texture slot, sprite, layer, tint and count metadata to independent Java-derived summaries, Image pixel readback to Pillow PNG decoding, and Usage to ZIP model closure plus PNG dimensions.",
                          "Coordinates, caller-supplied appearance, atlas, world tint and final presentation remain separate checks."]}
    if "runner_cleanup_check" in previous:
        evidence["runner_cleanup_check"] = previous["runner_cleanup_check"]
    if args.prepare_private or args.build_private:
        manifest = prepare_private(before)
        evidence["private_preparation"] = {"status": "frozen", "manifest_sha256": sha(PRIVATE / "manifest.json"),
            "source_map_sha256": sha(PRIVATE / "source-map.json"), "basis": manifest["basis"], "entry": manifest["entry"],
            "limits": manifest["limits"], "project_and_foreign_bytes_unchanged": True}
    EVIDENCE.write_text(json.dumps(evidence, sort_keys=True, indent=2) + "\n")
    if not (args.build_native or args.reuse_native or args.build_private):
        print(json.dumps({"status": evidence["status"], **evidence["preparation"]}, sort_keys=True))
        return
    stamp = WORK / "native-build.json"
    if args.build_native or args.build_private:
        if args.build_private:
            try:
                build_receipt = build_private(before)
            except (AssertionError, ProcessFailure):
                failed = json.loads(EVIDENCE.read_text())
                failed["status"] = "source_checked_native_private_failed"
                if (PRIVATE / "receipt.json").is_file():
                    failed["private_producer_failure"] = json.loads((PRIVATE / "receipt.json").read_text())
                EVIDENCE.write_text(json.dumps(failed, sort_keys=True, indent=2) + "\n")
                raise
        else:
            built, build_receipt = run([BEND, ENTRY, "-o", BINARY], "native-build", args.build_timeout)
        assert BINARY.is_file() and sources() == before, "Native build source changed or binary missing"
        stamp.write_text(json.dumps({"sources": before, "binary_sha256": sha(BINARY), "receipt": build_receipt}, sort_keys=True, indent=2) + "\n")
    else:
        build = json.loads(stamp.read_text())
        assert build["sources"] == before and build["binary_sha256"] == sha(BINARY), "Cached native artifact differs from source/binary stamp"
        build_receipt = build["receipt"]
    one, first_runs = native(corpus, 1)
    summaries = [verify(case, report) for case, report in zip(corpus, one)]
    two, second_runs = native(corpus, 2)
    assert one == two, "Two native observations differ"
    assert sources() == before, "Production source changed during native validation"
    assert one[0] == one[1], "Reordered request load changed catalog/binding outputs"
    evidence.update(status="passed", confidence="high for executed native metadata/geometry checks within stated scope",
                    native_build=build_receipt, native_binary_sha256=sha(BINARY), native_runs=first_runs + second_runs,
                    native_reports_sha256=hashlib.sha256(canonical(one)).hexdigest(), cases=summaries,
                    validation={"two_native_runs_equal": True, "reordered_requests_equal": True,
                                "checked_quads": sum(case.get("checked_quads", 0) for case in summaries),
                                "query_successes": sum(case.get("query_successes", 0) for case in summaries),
                                "query_rejections": sum(case.get("query_rejections", 0) for case in summaries),
                                "load_rejections": sum(case["status"] == "rejected" for case in summaries)})
    EVIDENCE.write_text(json.dumps(evidence, sort_keys=True, indent=2) + "\n")
    print(json.dumps({"status": "passed", "cases": len(corpus), **evidence["validation"]}, sort_keys=True))


if __name__ == "__main__":
    main()
