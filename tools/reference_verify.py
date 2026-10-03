#!/usr/bin/env python3
"""Independently read emitted tables and compare them with official reports.

Also check that every generated table matches its recorded digest. This checks
the extractor and table transport, never Minecraft gameplay implementation.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import itertools
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def rows(root: pathlib.Path, name: str) -> list[dict[str, str]]:
    with (root / "generated" / f"reference_{name}.tsv").open() as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=pathlib.Path, default=ROOT)
    args = parser.parse_args()
    root = args.root
    evidence = json.loads((root / "evidence/reference_inventory.json").read_text())
    for name, recorded in evidence["generated_tables"].items():
        data = (root / name).read_bytes()
        require(len(data) == recorded["bytes"], f"Table byte count mismatch: {name}")
        require(hashlib.sha256(data).hexdigest() == recorded["sha256"], f"Table hash mismatch: {name}")
        require(len(data.splitlines()) - 1 == recorded["rows"], f"Table row count mismatch: {name}")
    report_root = root / "reference/reports/reports"
    blocks = json.loads((report_root / "blocks.json").read_text())
    registries = json.loads((report_root / "registries.json").read_text())
    block_rows = rows(root, "blocks")
    require(len(block_rows) == len(blocks), "Block table count mismatch")
    state_ids = []
    for row in block_rows:
        identifier = row["identifier"]
        require(identifier in blocks, f"Unknown block: {identifier}")
        require(int(row["block_protocol_id"]) == registries["minecraft:block"]["entries"][identifier]["protocol_id"], f"Block numeric ID mismatch: {identifier}")
        properties = json.loads(row["ordered_properties_json"])
        first = int(row["first_state_id"])
        default = int(row["default_state_id"])
        choices = itertools.product(*(prop["values"] for prop in properties))
        expected = sorted(blocks[identifier]["states"], key=lambda state: state["id"])
        actual = [{"id": first + ordinal, "properties": dict(zip((prop["name"] for prop in properties), values)), "default": first + ordinal == default}
                  for ordinal, values in enumerate(choices)]
        require(len(actual) == int(row["state_count"]) == len(expected), f"State count mismatch: {identifier}")
        for emitted, official in zip(actual, expected):
            require(emitted["id"] == official["id"] and emitted["properties"] == official.get("properties", {}) and emitted["default"] == official.get("default", False),
                    f"State reconstruction mismatch: {identifier} state {emitted['id']}")
            state_ids.append(emitted["id"])
    require(sorted(state_ids) == list(range(len(state_ids))), "Duplicate, missing or nonzero-origin state IDs")
    expected_entries = {(registry, str(entry["protocol_id"]), identifier)
                        for registry, record in registries.items() for identifier, entry in record["entries"].items()}
    registry_rows = rows(root, "registries")
    actual_entries = {(row["registry"], row["protocol_id"], row["identifier"]) for row in registry_rows}
    require(actual_entries == expected_entries and len(actual_entries) == len(registry_rows), "Registry table mismatch or duplicates")
    packets = json.loads((report_root / "packets.json").read_text())
    expected_packets = {(state, direction, identifier, str(record["protocol_id"]))
                        for state, directions in packets.items() for direction, records in directions.items()
                        for identifier, record in records.items()}
    packet_rows = rows(root, "packets")
    actual_packets = {(row["state"], row["direction"], row["identifier"], row["protocol_id"]) for row in packet_rows}
    require(actual_packets == expected_packets and len(actual_packets) == len(packet_rows), "Packet table mismatch or duplicates")
    command_root = json.loads((report_root / "commands.json").read_text())
    command_nodes = {}
    def walk(node: dict, path: tuple[str, ...]):
        command_nodes[path] = (node["type"], int(node.get("executable", False)), node.get("parser", ""), node.get("properties", {}), node.get("redirect", []))
        for name, child in node.get("children", {}).items():
            walk(child, path + (name,))
    walk(command_root, ())
    command_rows = rows(root, "commands")
    require(len(command_rows) == len(command_nodes), "Command table count mismatch")
    seen_paths = set()
    for row in command_rows:
        path = tuple(json.loads(row["path_segments_json"]))
        actual = (row["node_type"], int(row["executable"]), row["parser"], json.loads(row["properties_json"]), json.loads(row["redirect_json"]))
        require(path in command_nodes and actual == command_nodes[path] and path not in seen_paths, f"Command node mismatch or duplicate: {path}")
        seen_paths.add(path)
    result = {"pin": "26.3", "kind": "extraction_verification", "tables_digest_verified": len(evidence["generated_tables"]),
              "blocks_reconstructed": len(block_rows), "states_compared": len(state_ids), "registry_entries_compared": len(actual_entries),
              "packet_ids_compared": len(actual_packets), "behavioral_parity_established": False}
    result["command_nodes_compared"] = len(command_rows)
    (root / "evidence/reference_verification.json").write_text(json.dumps(result, sort_keys=True, indent=2) + "\n")
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
