#!/usr/bin/env python3
"""Independent Unicode/byte/split oracle for the native pure-Bend NDJSON framer.

Python produces fixtures and expectations. The compiled Bend executable owns
the buffer, record framing, limits, UTF-8 decoding and EOF decision under test.
"""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import platform
from pathlib import Path
import random
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
BYTE_LIMIT = 65536
SCALAR_LIMIT = 16384


@dataclass(frozen=True)
class Case:
    name: str
    chunks: tuple[tuple[int, ...], ...]


def fnv_reversed(pending: list[int]) -> int:
    value = 2166136261
    for byte in reversed(pending):
        value = ((value ^ byte) * 16777619) & 0xFFFFFFFF
    return value


def oracle(case: Case) -> dict:
    pending: list[int] = []
    steps = []
    for chunk in case.chunks:
        lines = []
        error = None
        for byte in chunk:
            if not 0 <= byte <= 255:
                error = "input byte exceeds 255"
                break
            if byte == 10:
                record = pending[:-1] if pending[-1:] == [13] else pending
                try:
                    # CPython's strict decoder is independent of Bend's state
                    # machine. It rejects overlong forms, surrogate encodings,
                    # out-of-range scalars and incomplete sequences.
                    text = bytes(record).decode("utf-8", errors="strict")
                except UnicodeDecodeError:
                    error = "UTF-8"
                    break
                if len(text) > SCALAR_LIMIT:
                    error = "line exceeds 16384 Unicode scalar code points"
                    break
                lines.append([ord(character) for character in text])
                pending = []
            else:
                if len(pending) >= BYTE_LIMIT:
                    error = "line exceeds 65536 bytes before LF"
                    break
                pending.append(byte)
        if error is not None:
            # No lines from the failing feed call may escape, even if it
            # contained earlier valid complete records.
            steps.append({"ok": False, "error": error})
            return {"steps": steps, "eof": False}
        steps.append({"ok": True, "lines": lines, "pending_size": len(pending),
                      "pending_reverse_fnv1a32": fnv_reversed(pending)})
    return {"steps": steps, "eof": not pending}


def partition(data: bytes | list[int], cuts: list[int]) -> tuple[tuple[int, ...], ...]:
    positions = [0, *cuts, len(data)]
    return tuple(tuple(data[left:right]) for left, right in zip(positions, positions[1:]))


def corpus() -> list[Case]:
    cases: list[Case] = []

    def add(name: str, *chunks: bytes | list[int]) -> None:
        cases.append(Case(name, tuple(tuple(chunk) for chunk in chunks)))

    def every_cut(name: str, data: bytes) -> None:
        for cut in range(len(data) + 1):
            cases.append(Case(f"{name}-cut-{cut}", partition(data, [cut])))

    boundaries = [0, 1, 9, 11, 12, 13, 31, 32, 0x7F, 0x80, 0xBF, 0xC0,
                  0xFF, 0x100, 0x7FF, 0x800, 0xD7FF, 0xE000, 0xFFFF,
                  0x10000, 0x10FFFF]
    for scalar in boundaries:
        encoded = chr(scalar).encode("utf-8") + b"\n"
        every_cut(f"scalar-{scalar}", encoded)
        # Enumerate every nonempty-chunk partition of each encoding + LF.
        for mask in range(1 << (len(encoded) - 1)):
            cuts = [index for index in range(1, len(encoded)) if mask & (1 << (index - 1))]
            cases.append(Case(f"scalar-{scalar}-partition-{mask}", partition(encoded, cuts)))

    payload = ('{"id":1,"name":"é€😀ไทย"}\r\n'
               '{"id":2,"value":"\\uD83D\\uDE00"}\n'
               '\n{"id":3,"bom":"\ufeff"}\npartial😀').encode("utf-8")
    every_cut("json-records", payload)
    for width in range(1, 21):
        chunks = tuple(tuple(payload[offset:offset + width]) for offset in range(0, len(payload), width))
        cases.append(Case(f"json-records-width-{width}", chunks))
    add("empty-feed", b"")
    add("empty-chunks", b"", b"", b"\n", b"", b"\r", b"", b"\n", b"")
    add("crlf-trims-one", b"a\r", b"\n\r\r\n")
    add("interior-cr-retained", b"a\rb\n")
    add("bom-retained", b"\xef\xbb\xbfnull\n")
    add("nul-retained", b"a\x00b\n")
    add("ascii-tail-no-newline", b"{}")
    add("partial-codepoint-eof", b"\xf0", b"\x9f\x98")
    add("malformed-deferred", b"\xff")
    add("malformed-completed-next-call", b"\xff", b"\n")

    # Every possible single byte is classified by Python's strict decoder,
    # with CR/LF handled by the record envelope before decoding.
    for byte in range(256):
        add(f"single-byte-{byte}", bytes([byte, 10]))
    for byte in [256, 257, 65535, 4294967295]:
        add(f"not-a-byte-{byte}", [byte])
        add(f"not-a-byte-after-valid-{byte}", [97, 10, byte, 10])

    malformed = [
        b"\x80", b"\xbf", b"\xc0\x80", b"\xc1\xbf",
        b"\xe0\x80\x80", b"\xe0\x9f\xbf", b"\xf0\x80\x80\x80",
        b"\xf0\x8f\xbf\xbf", b"\xed\xa0\x80", b"\xed\xbf\xbf",
        b"\xf4\x90\x80\x80", b"\xf4\xbf\xbf\xbf", b"\xf5\x80\x80\x80",
        b"\xf8\x88\x80\x80\x80", b"\xfc\x84\x80\x80\x80\x80", b"\xfe", b"\xff",
        b"\xc2", b"\xe0", b"\xe1\x80", b"\xf0", b"\xf0\x90", b"\xf4\x8f\xbf",
        b"\xc2\x00", b"\xc2\x7f", b"\xc2\xc0", b"\xc2\xff",
        b"\xe1\x80A", b"\xf1\x80\x80A", b"\xc2\x80\x80",
    ]
    for index, data in enumerate(malformed):
        every_cut(f"malformed-{index}", data + b"\n")
        add(f"atomic-failed-feed-{index}", b"previous\n", b"valid\n" + data + b"\nignored\n")

    rng = random.Random(0xF8F33)
    for index in range(150):
        text = "".join(chr(rng.choice([rng.randrange(0, 0xD800), rng.randrange(0xE000, 0x110000)]))
                       for _ in range(rng.randrange(1, 50))) + "a"
        data = text.encode("utf-8") + b"\n"
        cuts = sorted(rng.randrange(len(data) + 1) for _ in range(rng.randrange(1, 20)))
        cases.append(Case(f"random-valid-{index}", partition(data, cuts)))
    for index in range(150):
        data = bytes(rng.randrange(256) for _ in range(rng.randrange(1, 40))) + b"\n"
        cuts = sorted(rng.randrange(len(data) + 1) for _ in range(rng.randrange(1, 15)))
        cases.append(Case(f"random-bytes-{index}", partition(data, cuts)))

    maximum = "\U0010ffff".encode("utf-8")
    add("scalar-limit-exact", b"a" * SCALAR_LIMIT + b"\n")
    add("scalar-limit-exceeded", b"a" * (SCALAR_LIMIT + 1) + b"\n")
    add("scalar-limit-split", b"a" * SCALAR_LIMIT, b"\n")
    add("byte-and-scalar-limits-exact", maximum * SCALAR_LIMIT, b"\n")
    add("crlf-byte-limit-exact", maximum * (SCALAR_LIMIT - 1) + "€".encode("utf-8") + b"\r", b"\n")
    add("crlf-byte-limit-exceeded", maximum * SCALAR_LIMIT, b"\r\n")
    add("pending-byte-limit-exact", b"\x80" * BYTE_LIMIT)
    add("pending-byte-limit-split", b"\x80" * (BYTE_LIMIT - 1), b"\x80")
    add("pending-byte-limit-exceeded", b"\x80" * BYTE_LIMIT, b"\x80")
    add("pending-ascii-deferred-scalar-limit", b"a" * BYTE_LIMIT)
    add("pending-ascii-completed-scalar-limit", b"a" * BYTE_LIMIT, b"\n")
    add("byte-limit-after-earlier-record", b"previous\n", b"valid\n" + b"\x80" * (BYTE_LIMIT + 1))
    add("out-of-range-precedes-byte-limit", b"\x80" * BYTE_LIMIT, [256])
    return cases


def specification(case: Case) -> str:
    return ";".join(",".join(str(byte) for byte in chunk) for chunk in case.chunks)


def normalize(observed: dict) -> dict:
    for step in observed["steps"]:
        if step.get("ok") is False:
            if set(step) != {"ok", "error"} or not isinstance(step["error"], str) or not step["error"]:
                raise AssertionError("a failed feed exposed lines/buffer or omitted its diagnostic")
            if "UTF-8" in step["error"]:
                step["error"] = "UTF-8"
    return observed


def command(args: list[str | Path], timeout: int = 120) -> dict:
    result = subprocess.run([str(arg) for arg in args], cwd=ROOT, text=True,
                            capture_output=True, timeout=timeout)
    if result.returncode != 0:
        raise RuntimeError(f"command failed ({result.returncode}): {args}\n{result.stdout}{result.stderr}")
    return {"command": [str(arg) for arg in args], "stdout": result.stdout, "stderr": result.stderr,
            "returncode": result.returncode}


def execute(binary: Path, cases: list[Case]) -> tuple[list[dict], int]:
    observed_cases = []
    groups: list[list[tuple[Case, str]]] = []
    group: list[tuple[Case, str]] = []
    size = 0
    # macOS ARG_MAX is bounded. The largest boundary fixture gets a batch of
    # its own, while ordinary fixtures share processes for a reproducible run.
    for case in cases:
        encoded = specification(case)
        if group and (size + len(encoded) > 350000 or len(group) >= 40):
            groups.append(group)
            group, size = [], 0
        group.append((case, encoded))
        size += len(encoded) + 1
    if group:
        groups.append(group)
    for group in groups:
        output = command([binary, "--threads", "1", "--gpu", "off", "batch", *[encoded for _, encoded in group]])["stdout"]
        rows = output.splitlines()
        if len(rows) != len(group):
            raise AssertionError(f"native batch returned {len(rows)} rows for {len(group)} cases")
        for (case, _), row in zip(group, rows):
            observed = normalize(json.loads(row))
            expected = oracle(case)
            if observed != expected:
                raise AssertionError(f"{case.name}: expected {str(expected)[:500]}, observed {str(observed)[:500]}")
            observed_cases.append({"name": case.name, "result": observed})
    return observed_cases, len(groups)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bend", type=Path, default=Path.home() / ".bend/bin/bend")
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--evidence", type=Path, default=ROOT / "evidence/framing-native.json")
    args = parser.parse_args()
    started = time.monotonic()
    binary = ROOT / "build/framing-tests"
    checks = []
    try:
        version = command([args.bend, "version"])
        if version["stdout"].strip() != "bend 2.0.35":
            raise AssertionError("compiler version differs from project pin")
        checks.append(command([args.bend, "src/framing.bend", "--verdict"]))
        checks.append(command([args.bend, "tests/framing.bend", "--verdict"]))
        if any("ALL PROOFS CHECK" not in check["stdout"] + check["stderr"] for check in checks):
            raise AssertionError("missing mathematical checker success")
        if not args.skip_build:
            checks.append(command([args.bend, "tests/framing.bend", "-o", binary]))
        checks.append(command([binary, "--threads", "1", "--gpu", "off"]))
        if checks[-1]["stdout"].strip() != "framing fixtures pass":
            raise AssertionError("native fixed regressions failed")
        cases = corpus()
        observations, batches = execute(binary, cases)
        signatures = [{"name": case.name, "chunks": case.chunks, "expected": oracle(case)} for case in cases]
        failure_counts = Counter(step["error"] for observed in observations
                                 for step in observed["result"]["steps"] if step["ok"] is False)
        report = {
            "status": "passed", "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
            "elapsed_seconds": time.monotonic() - started, "platform": platform.platform(),
            "python": platform.python_version(), "compiler_version": version["stdout"].strip(),
            "compiler_sha256": digest(args.bend), "native_binary_sha256": digest(binary),
            "source_sha256": {str(path.relative_to(ROOT)): digest(path) for path in
                              [ROOT / "src/framing.bend", ROOT / "tests/framing.bend", Path(__file__).resolve()]},
            "case_count": len(cases), "native_batch_count": batches,
            "receive_chunk_count": sum(len(case.chunks) for case in cases),
            "failure_counts": dict(sorted(failure_counts.items())),
            "corpus_sha256": hashlib.sha256(json.dumps(signatures, sort_keys=True).encode()).hexdigest(),
            "observed_sha256": hashlib.sha256(json.dumps(observations, sort_keys=True).encode()).hexdigest(),
            "commands": [check["command"] for check in checks] + [
                ["python3", "tools/test_framing.py"] + (["--skip-build"] if args.skip_build else [])],
            "checker_results": [{"command": check["command"], "stdout": check["stdout"],
                                 "stderr": check["stderr"], "returncode": check["returncode"]}
                                for check in checks[:2]],
            "limit_cases": [{"name": observed["name"], "steps": [
                {key: value for key, value in step.items() if key != "lines"} |
                ({"line_scalar_counts": [len(line) for line in step["lines"]]} if step["ok"] else {})
                for step in observed["result"]["steps"]], "eof": observed["result"]["eof"]}
                for observed in observations if "limit" in observed["name"]],
            "coverage": [
                "Every partition of scalar-boundary UTF-8 encodings plus LF; every single split of multirecord JSON bytes.",
                "All 256 single byte values; explicit U32 values above 255; strict malformed UTF-8 classifications.",
                "Seeded Unicode and arbitrary-byte receive splits, including empty chunks and codepoint splits.",
                "CRLF, retained interior CR/BOM/NUL, incomplete EOF and deferred malformed partial bytes.",
                "65536-byte and 16384-scalar exact/exceeded bounds; failed-feed batch atomicity.",
            ],
            "boundary": [
                "Native tests exercise pure Bend framing; Python supplies only inputs and an independent strict-decoder oracle.",
                "The five finite checked fixtures are not a universal UTF-8 or segmentation theorem.",
                "No TCP transport integration, Minecraft parity or foreign implementation is claimed.",
                "Buffer invariants assume construction through new/feed, not manually forged Buffer constructors.",
            ],
        }
        args.evidence.parent.mkdir(parents=True, exist_ok=True)
        args.evidence.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({"status": "passed", "cases": len(cases), "native_batches": batches,
                          "receive_chunks": report["receive_chunk_count"], "evidence": str(args.evidence)}))
        return 0
    except (AssertionError, OSError, subprocess.SubprocessError, ValueError, KeyError, RuntimeError) as error:
        print(f"framing verification failed: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
