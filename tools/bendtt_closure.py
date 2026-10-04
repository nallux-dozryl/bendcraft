#!/usr/bin/env python3
"""Retain an exact, conservative declaration closure from a full BendTT export.

This only removes declarations. It never rewrites types, implementation terms,
law statements or proof terms. Its output still needs independent kernel checking.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def retain(source: bytes, roots: list[str]) -> tuple[bytes, dict]:
    text = source.decode("utf-8")
    # BendTT Parse.name admits alphanumeric characters, '_' and '.'. Unicode
    # Python \w conservatively also admits every exported alphanumeric name.
    # Opaque primitive types are declarations too. Their unchanged bytes must
    # accompany any retained owner/type that refers to them.
    headers = list(re.finditer(r"^(?:opaque )?([\w.]+) : ", text, re.MULTILINE))
    if not headers or text[:headers[0].start()].strip():
        raise ValueError("Expected a full declaration-only BendTT export")
    chunks: dict[str, str] = {}
    order: list[str] = []
    for index, match in enumerate(headers):
        name = match.group(1)
        if name in chunks:
            raise ValueError(f"Duplicate declaration: {name}")
        end = headers[index + 1].start() if index + 1 < len(headers) else len(text)
        chunks[name] = text[match.start():end]
        order.append(name)
    missing = set(roots) - chunks.keys()
    if missing:
        raise ValueError(f"Missing root declarations: {sorted(missing)}")
    references = {}
    for name, chunk in chunks.items():
        tokens = set(re.findall(r"[\w.]+", chunk))
        # Labels are included conservatively when they share a declaration name.
        tokens |= {token.lstrip(".") for token in tokens}
        references[name] = tokens & chunks.keys()
    included: set[str] = set()
    pending = list(roots)
    while pending:
        name = pending.pop()
        if name not in included:
            included.add(name)
            pending.extend(references[name] - included)
    if any(references[name] - included for name in included):
        raise ValueError("Declaration closure is incomplete")
    output = "".join(chunks[name] for name in order if name in included).encode("utf-8")
    manifest = {
        "scope": "Exact conservative declaration closure; no kernel verdict implied",
        "roots": roots,
        "source": {"bytes": len(source), "sha256": digest(source)},
        "output": {"bytes": len(output), "sha256": digest(output)},
        "declarations_total": len(order),
        "retained": [{"name": name, "sha256": digest(chunks[name].encode("utf-8"))}
                     for name in order if name in included],
        "omitted": [name for name in order if name not in included],
        "source_order_preserved": True,
        "all_retained_declared_references_present": True,
        "terms_rewritten": False,
    }
    return output, manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--root", action="append", required=True)
    args = parser.parse_args()
    output, manifest = retain(args.source.read_bytes(), args.root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(output)
    args.output.with_suffix(".closure.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({key: manifest[key] for key in ["roots", "source", "output", "declarations_total"]}))


if __name__ == "__main__":
    main()
