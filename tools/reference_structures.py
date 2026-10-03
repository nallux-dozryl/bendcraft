#!/usr/bin/env python3
"""Inspect official bundled structure NBT; this is reference extraction only."""
from __future__ import annotations

import collections
import gzip
import hashlib
import json
import struct
import zipfile

from reference_inventory import ROOT, INSTALL, write_json, fingerprint

TAG_NAMES = {0: "end", 1: "byte", 2: "short", 3: "int", 4: "long", 5: "float", 6: "double", 7: "byte_array", 8: "string", 9: "list", 10: "compound", 11: "int_array", 12: "long_array"}


class Reader:
    def __init__(self, data: bytes):
        self.data, self.offset = data, 0
        self.types = collections.Counter()
        self.root_types = {}

    def take(self, size: int) -> bytes:
        if size < 0 or self.offset + size > len(self.data):
            raise ValueError("Truncated NBT or negative length")
        value = self.data[self.offset:self.offset + size]
        self.offset += size
        return value

    def number(self, format_name: str):
        return struct.unpack(">" + format_name, self.take(struct.calcsize(format_name)))[0]

    def string(self) -> str:
        data = self.take(self.number("H"))
        # DataInput modified UTF-8 uses C0 80 for NUL and can encode surrogate
        # halves. Preserve those without lossy replacement if encountered.
        return data.replace(b"\xc0\x80", b"\x00").decode("utf-8", errors="surrogatepass")

    def value(self, kind: int, depth: int = 0):
        if depth > 512:
            raise ValueError("NBT nesting exceeds extraction safety bound")
        if kind not in TAG_NAMES or kind == 0:
            raise ValueError(f"Invalid NBT payload type {kind}")
        self.types[TAG_NAMES[kind]] += 1
        if kind in {1, 2, 3, 4, 5, 6}:
            return self.number({1: "b", 2: "h", 3: "i", 4: "q", 5: "f", 6: "d"}[kind])
        if kind == 7:
            return self.take(self.number("i"))
        if kind == 8:
            return self.string()
        if kind == 9:
            element, length = self.number("B"), self.number("i")
            if length < 0:
                raise ValueError("Negative NBT list length")
            return [self.value(element, depth + 1) for _ in range(length)]
        if kind == 10:
            value = {}
            while True:
                child = self.number("B")
                if child == 0:
                    return value
                name = self.string()
                if name in value:
                    raise ValueError("Duplicate NBT compound key")
                if depth == 0:
                    self.root_types[name] = TAG_NAMES[child]
                value[name] = self.value(child, depth + 1)
        length = self.number("i")
        if length < 0:
            raise ValueError("Negative NBT array length")
        return [self.number("i" if kind == 11 else "q") for _ in range(length)]

    def root(self):
        kind, name = self.number("B"), self.string()
        if kind != 10:
            raise ValueError("Structure root is not a named compound")
        result = self.value(kind)
        if self.offset != len(self.data):
            raise ValueError("Trailing bytes after structure NBT root")
        return name, result


def main() -> None:
    counts, types, versions, root_keys, palette_blocks, sizes = [collections.Counter() for _ in range(6)]
    blocks_total = entities_total = palette_entries_total = 0
    palette_fields, block_fields, entity_fields = [collections.Counter() for _ in range(3)]
    unknown_blocks = set()
    block_registry = set(json.loads((ROOT / "reference/reports/reports/blocks.json").read_text()))
    hashes = []
    client = INSTALL / "versions/26.3/26.3.jar"
    release = json.loads((ROOT / "reference/release.json").read_text())
    if fingerprint(client)["sha256"] != release["client"]["sha256"]:
        raise ValueError("Pinned reference client SHA-256 mismatch")
    with zipfile.ZipFile(client) as jar:
        names = sorted(name for name in jar.namelist() if name.startswith("data/minecraft/structure/") and name.endswith(".nbt"))
        for name in names:
            raw = jar.read(name)
            compressed = raw.startswith(b"\x1f\x8b")
            counts["gzip" if compressed else "uncompressed"] += 1
            reader = Reader(gzip.decompress(raw) if compressed else raw)
            root_name, value = reader.root()
            counts["empty_root_name" if not root_name else "named_root"] += 1
            types.update(reader.types)
            root_keys.update(key + ":" + kind for key, kind in reader.root_types.items())
            versions[str(value.get("DataVersion", "missing"))] += 1
            size = tuple(value["size"])
            if len(size) != 3:
                raise ValueError("Structure does not have three size axes")
            sizes["x" + str(size[0]) + "_y" + str(size[1]) + "_z" + str(size[2])] += 1
            blocks_total += len(value.get("blocks", []))
            entities_total += len(value.get("entities", []))
            block_fields.update(key for record in value.get("blocks", []) for key in record)
            entity_fields.update(key for record in value.get("entities", []) for key in record)
            palettes = value.get("palettes", [value.get("palette", [])])
            counts["palette_sets"] += len(palettes)
            for palette in palettes:
                palette_entries_total += len(palette)
                for state in palette:
                    palette_fields.update(state.keys())
                    identifier = state.get("id", state.get("Name"))
                    if not isinstance(identifier, str):
                        raise ValueError("Structure palette does not identify a block")
                    palette_blocks[identifier] += 1
                    if identifier not in block_registry:
                        unknown_blocks.add(identifier)
            hashes.append((name, hashlib.sha256(raw).hexdigest()))
    write_json(ROOT / "reference/structures.json", {"pin": "26.3", "templates": len(names), "compression_and_root_counts": dict(sorted(counts.items())),
                                                  "observed_data_versions": dict(sorted(versions.items())), "observed_root_key_types": dict(sorted(root_keys.items())),
                                                  "observed_tag_payload_counts": dict(sorted(types.items())), "size_distribution": dict(sorted(sizes.items())),
                                                  "stored_block_records": blocks_total, "stored_entity_records": entities_total,
                                                  "palette_entries": palette_entries_total, "unique_palette_block_identifiers": len(palette_blocks),
                                                  "palette_state_fields": dict(sorted(palette_fields.items())),
                                                  "block_record_fields": dict(sorted(block_fields.items())), "entity_record_fields": dict(sorted(entity_fields.items())),
                                                  "palette_block_identifier_occurrences": dict(sorted(palette_blocks.items())),
                                                  "palette_identifiers_absent_from_pinned_block_registry": sorted(unknown_blocks),
                                                  "content_tree_sha256": hashlib.sha256("".join(path + "\t" + sha + "\n" for path, sha in hashes).encode()).hexdigest(),
                                                  "limits": "Observed NBT topology only; no placement, processor, migration, jigsaw or generation behavior verified."})
    write_json(ROOT / "evidence/reference_structures.json", {"pin": "26.3", "kind": "structure_metadata_extraction", "templates_fully_parsed": len(names),
                                                           "all_roots_compound": True, "all_inputs_consumed_without_trailing_bytes": True,
                                                           "unknown_palette_blocks": sorted(unknown_blocks), "reproduce": "python3 tools/reference_structures.py",
                                                           "behavioral_parity_established": False})
    print(json.dumps({"templates": len(names), "block_records": blocks_total, "entity_records": entities_total, "unknown_palette_blocks": sorted(unknown_blocks)}, sort_keys=True))


if __name__ == "__main__":
    main()
