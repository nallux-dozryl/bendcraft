#!/usr/bin/env python3
"""Independent CPython strict-UTF8 oracle for the reusable pure Bend codec.

Python creates inputs and expected results; native Bend executes the codec.
Small cases compare every output value. Large/exhaustive cases compare length
and FNV-1a-32 summaries to avoid serializing millions of decimal output values.
"""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
NAT48_MAX = (1 << 48) - 1
REGISTRY_LIMIT = 4 * 1024 * 1024
ZIP_NAME_LIMIT = 65535
SEED = 0xC0DEC0DE


@dataclass(frozen=True)
class Case:
    name: str
    mode: str
    limit: int
    chunks: tuple[tuple[int, ...], ...]

    @property
    def values(self) -> tuple[int, ...]:
        return tuple(value for chunk in self.chunks for value in chunk)

    def specification(self) -> str:
        return f"{self.mode}|{self.limit}|" + ";".join(
            ",".join(str(value) for value in chunk) for chunk in self.chunks)


def oracle(mode: str, limit: int, values: tuple[int, ...]) -> dict:
    try:
        if mode == "d":
            # bytes() independently rejects U32 values above 255. CPython's
            # strict UTF-8 decoder rejects malformed sequences and preserves
            # ASCII/NUL, BOM, noncharacters and all valid scalar values.
            text = bytes(values).decode("utf-8", errors="strict")
            output = [ord(character) for character in text]
        elif mode == "e":
            text = "".join(chr(value) for value in values)
            output = list(text.encode("utf-8", errors="strict"))
        else:
            raise AssertionError(f"unknown oracle mode: {mode}")
    except (UnicodeError, ValueError, OverflowError):
        return {"ok": False}
    return {"ok": True, "values": output} if len(output) <= limit else {"ok": False}


def summary(values) -> dict:
    length = 0
    value_hash = 2166136261
    for value in values:
        length += 1
        value_hash = ((value_hash ^ value) * 16777619) & 0xFFFFFFFF
    return {"ok": True, "length": length, "fnv1a32": value_hash}


def normalized(observed: dict) -> dict:
    if observed.get("ok") is False:
        if set(observed) != {"ok", "error"} or not isinstance(observed["error"], str) or not observed["error"]:
            raise AssertionError("failure exposed output or omitted its diagnostic")
        return {"ok": False}
    return observed


def corpus() -> list[Case]:
    cases: list[Case] = []

    def add(name: str, mode: str, limit: int, values, cuts: list[int] | None = None) -> None:
        points = [0, *(cuts or []), len(values)]
        chunks = tuple(tuple(values[left:right]) for left, right in zip(points, points[1:]))
        cases.append(Case(name, mode, limit, chunks))

    for mode in ("d", "e"):
        for limit in (0, 1, 65535, REGISTRY_LIMIT, (1 << 32) - 1, NAT48_MAX):
            add(f"empty-{mode}-{limit}", mode, limit, [])

    noncharacters = [*range(0xFDD0, 0xFDF0), *[plane * 0x10000 + end for plane in range(17) for end in (0xFFFE, 0xFFFF)]]
    boundaries = sorted(set([
        0, 1, 9, 10, 13, 31, 32, 0x7E, 0x7F, 0x80, 0x81, 0xBF,
        0xC0, 0xFF, 0x100, 0x7FE, 0x7FF, 0x800, 0x801, 0xD7FE,
        0xD7FF, 0xE000, 0xE001, 0xFEFF, 0xFFFD, 0xFFFE, 0xFFFF,
        0x10000, 0x10001, 0x10FFFE, 0x10FFFF, *noncharacters,
    ]))
    for scalar in boundaries:
        encoded = chr(scalar).encode("utf-8")
        for limit in (0, 1, 2, NAT48_MAX):
            add(f"scalar-decode-{scalar}-limit-{limit}", "d", limit, encoded)
        for limit in sorted(set([0, len(encoded) - 1, len(encoded), len(encoded) + 1, NAT48_MAX])):
            add(f"scalar-encode-{scalar}-limit-{limit}", "e", limit, [scalar])
        # Every nonempty partition and every single split with empty chunks.
        # decode is a complete-input API: the native harness assembles these
        # lists before invoking it, including splits inside a multibyte scalar.
        for mask in range(1 << (len(encoded) - 1)):
            cuts = [index for index in range(1, len(encoded)) if mask & (1 << (index - 1))]
            add(f"scalar-chunks-{scalar}-{mask}", "d", 1, encoded, cuts)
        for cut in range(len(encoded) + 1):
            add(f"scalar-empty-chunks-{scalar}-{cut}", "d", 1, encoded, [0, cut, cut, len(encoded)])
        for end in range(1, len(encoded)):
            add(f"scalar-incomplete-{scalar}-{end}", "d", 1, encoded[:end])

    for byte in range(256):
        for limit in (0, 1):
            add(f"single-byte-{byte}-{limit}", "d", limit, [byte])
    for byte in (256, 257, 65535, 1 << 31, (1 << 32) - 1):
        for values in ([byte], [97, byte], [194, byte], [240, 144, byte, 128]):
            add(f"not-byte-{byte}-{len(values)}", "d", 10, values)

    # All forged surrogate scalars and their actual three-byte encodings.
    # The host never converts these inputs to String for the encoder: native
    # Bend constructs Chr{code} from the decimal U32 fixture values.
    for scalar in range(0xD800, 0xE000):
        add(f"forged-surrogate-{scalar}", "e", 4, [scalar])
        encoded = [0xE0 | (scalar >> 12), 0x80 | ((scalar >> 6) & 63), 0x80 | (scalar & 63)]
        add(f"encoded-surrogate-{scalar}", "d", 1, encoded)
    for scalar in (0x110000, 0x110001, 0x1FFFFF, 0x200000, 1 << 31, (1 << 32) - 1):
        add(f"forged-out-of-range-{scalar}", "e", 100, [scalar])
        add(f"forged-out-of-range-prefix-{scalar}", "e", 100, [97, 0x1F600, scalar])

    malformed = [
        [0x80], [0xBF], [0xC0, 0x80], [0xC1, 0xBF],
        [0xE0, 0x80, 0x80], [0xE0, 0x9F, 0xBF],
        [0xF0, 0x80, 0x80, 0x80], [0xF0, 0x8F, 0xBF, 0xBF],
        [0xF4, 0x90, 0x80, 0x80], [0xF4, 0xBF, 0xBF, 0xBF],
        [0xF5, 0x80, 0x80, 0x80], [0xF8, 0x88, 0x80, 0x80, 0x80],
        [0xFC, 0x84, 0x80, 0x80, 0x80, 0x80], [0xFE], [0xFF],
        [0xC2], [0xE0], [0xE1, 0x80], [0xF0], [0xF0, 0x90], [0xF4, 0x8F, 0xBF],
        [0xC2, 0], [0xC2, 0x7F], [0xC2, 0xC0], [0xC2, 0xFF],
        [0xE1, 0x80, 65], [0xF1, 0x80, 0x80, 65], [0xC2, 0x80, 0x80],
    ]
    for index, values in enumerate(malformed):
        for cut in range(len(values) + 1):
            add(f"malformed-{index}-cut-{cut}", "d", 100, values, [cut])
        add(f"malformed-after-valid-{index}", "d", 100, [97, 0, 0xF0, 0x9F, 0x98, 0x80, *values])
    for lead in (0xC0, 0xC1):
        for continuation in range(0x80, 0xC0):
            add(f"overlong-two-{lead}-{continuation}", "d", 100, [lead, continuation])
    for lead in range(0xC2, 0xF5):
        size = 2 if lead < 0xE0 else 3 if lead < 0xF0 else 4
        for position in range(1, size):
            for invalid in (0, 0x7F, 0xC0, 0xFF, 256):
                values = [lead, *([0x80] * (size - 1))]
                values[position] = invalid
                add(f"invalid-continuation-{lead}-{position}-{invalid}", "d", 100, values)

    rng = random.Random(SEED)
    for index in range(1000):
        scalars = [rng.choice([rng.randrange(0, 0xD800), rng.randrange(0xE000, 0x110000)])
                   for _ in range(rng.randrange(0, 65))]
        text = "".join(chr(scalar) for scalar in scalars)
        encoded = text.encode("utf-8")
        cuts = sorted(rng.randrange(len(encoded) + 1) for _ in range(rng.randrange(0, 15)))
        add(f"random-valid-decode-{index}", "d", len(scalars), encoded, cuts)
        add(f"random-valid-encode-{index}", "e", len(encoded), scalars)
        if scalars:
            add(f"random-scalar-limit-{index}", "d", len(scalars) - 1, encoded, cuts)
            add(f"random-byte-limit-{index}", "e", len(encoded) - 1, scalars)
    for index in range(1000):
        values = [rng.randrange(256) for _ in range(rng.randrange(0, 49))]
        cuts = sorted(rng.randrange(len(values) + 1) for _ in range(rng.randrange(0, 12)))
        add(f"random-bytes-{index}", "d", 100, values, cuts)

    return cases


def command(args: list[str | Path], timeout: int = 120) -> dict:
    environment = os.environ.copy()
    lean_bin = ROOT / ".runtime/toolchains/lean-4.34.0-darwin_aarch64/bin"
    # Lean bundles its own clang, which lacks the macOS SDK search path. Only
    # kernel checking needs that PATH; native Bend builds use host Apple clang.
    if lean_bin.is_dir() and "--verdict" in args:
        environment["PATH"] = str(lean_bin) + os.pathsep + environment.get("PATH", "")
    completed = subprocess.run([str(arg) for arg in args], cwd=ROOT, env=environment,
                               text=True, capture_output=True, timeout=timeout)
    result = {"command": [str(arg) for arg in args], "stdout": completed.stdout,
              "stderr": completed.stderr, "returncode": completed.returncode}
    if completed.returncode != 0:
        raise RuntimeError(f"command failed: {args}\n{completed.stdout}{completed.stderr}")
    return result


def execute(binary: Path, cases: list[Case]) -> tuple[list[dict], int]:
    groups: list[list[Case]] = []
    group: list[Case] = []
    size = 0
    for case in cases:
        added = len(case.specification()) + 1
        if group and (size + added > 300000 or len(group) >= 200):
            groups.append(group)
            group, size = [], 0
        group.append(case)
        size += added
    if group:
        groups.append(group)
    observations = []
    for group in groups:
        output = command([binary, "--threads", "1", "--gpu", "off", *[case.specification() for case in group]])["stdout"]
        rows = output.splitlines()
        if len(rows) != len(group):
            raise AssertionError(f"native batch yielded {len(rows)} rows, expected {len(group)}")
        for case, row in zip(group, rows):
            observed = json.loads(row)
            expected = oracle(case.mode, case.limit, case.values)
            if normalized(observed) != expected:
                raise AssertionError(f"{case.name}: expected {expected}, observed {observed}")
            observations.append({"name": case.name, "result": observed})
    return observations, len(groups)


def large_cases(binary: Path, folder: Path) -> list[dict]:
    observations: list[dict] = []

    def check(name: str, spec: str, expected: dict, input_digest: str | None = None) -> None:
        result = command([binary, "--threads", "1", "--gpu", "off", spec])
        observed = json.loads(result["stdout"])
        if normalized(observed) != expected:
            raise AssertionError(f"{name}: expected {expected}, observed {observed}")
        observations.append({"name": name, "specification": spec, "expected": expected,
                             "observed": observed, "input_sha256": input_digest})

    def decode_file(name: str, raw: bytes, scalar_limit: int) -> None:
        path = folder / (name + ".bin")
        path.write_bytes(raw)
        try:
            text = raw.decode("utf-8", errors="strict")
            expected = summary(map(ord, text)) if len(text) <= scalar_limit else {"ok": False}
        except UnicodeDecodeError:
            expected = {"ok": False}
        check(name, f"dfile|{scalar_limit}|{path}", expected, hashlib.sha256(raw).hexdigest())

    # Every one of the 1,112,064 valid scalar values appears in independently
    # generated strict-UTF8 decoding input and native String encoding input.
    all_scalars = "".join(chr(code) for code in range(0xD800)) + "".join(chr(code) for code in range(0xE000, 0x110000))
    decode_file("exhaustive-valid-scalars", all_scalars.encode("utf-8"), len(all_scalars))
    for begin, end in ((0, 0xD800), (0xE000, 0x110000)):
        text = "".join(chr(code) for code in range(begin, end))
        raw = text.encode("utf-8")
        check(f"exhaustive-encode-{begin}-{end}", f"erange|{len(raw)}|{begin}|{end - begin}", summary(raw))

    for code, count, limit, name in [
        (97, ZIP_NAME_LIMIT, ZIP_NAME_LIMIT, "zip-ascii-exact"),
        (97, ZIP_NAME_LIMIT + 1, ZIP_NAME_LIMIT, "zip-ascii-exceeded"),
        (0x800, ZIP_NAME_LIMIT // 3, ZIP_NAME_LIMIT, "zip-three-byte-exact"),
        (0x800, ZIP_NAME_LIMIT // 3 + 1, ZIP_NAME_LIMIT, "zip-three-byte-exceeded"),
        (0x10FFFF, ZIP_NAME_LIMIT // 4, ZIP_NAME_LIMIT, "zip-four-byte-fit"),
        (0x10FFFF, ZIP_NAME_LIMIT // 4 + 1, ZIP_NAME_LIMIT, "zip-four-byte-exceeded"),
        (97, REGISTRY_LIMIT, REGISTRY_LIMIT, "registry-ascii-exact"),
        (97, REGISTRY_LIMIT + 1, REGISTRY_LIMIT, "registry-ascii-exceeded"),
        (0x10FFFF, REGISTRY_LIMIT // 4, REGISTRY_LIMIT, "registry-four-byte-exact"),
        (0x10FFFF, REGISTRY_LIMIT // 4 + 1, REGISTRY_LIMIT, "registry-four-byte-exceeded"),
    ]:
        raw = chr(code).encode("utf-8") * count
        expected = summary(raw) if len(raw) <= limit else {"ok": False}
        check(name, f"erepeat|{limit}|{code}|{count}", expected)

    decode_file("registry-decode-ascii-exact", b"a" * REGISTRY_LIMIT, REGISTRY_LIMIT)
    decode_file("registry-decode-ascii-scalar-exceeded", b"a" * (REGISTRY_LIMIT + 1), REGISTRY_LIMIT)
    maximum = chr(0x10FFFF).encode("utf-8")
    decode_file("registry-decode-four-byte-exact", maximum * (REGISTRY_LIMIT // 4), REGISTRY_LIMIT // 4)
    decode_file("registry-decode-four-byte-scalar-exceeded", maximum * (REGISTRY_LIMIT // 4 + 1), REGISTRY_LIMIT // 4)
    decode_file("registry-malformed-tail", b"a" * (REGISTRY_LIMIT - 1) + b"\xc2", REGISTRY_LIMIT)
    decode_file("registry-surrogate-tail", b"a" * (REGISTRY_LIMIT - 3) + b"\xed\xa0\x80", REGISTRY_LIMIT)
    return observations


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def emitted_c_review(path: Path) -> dict:
    text = path.read_text()
    # Record the representation boundary and implementation symbols; an
    # independent kernel checks the Bend source, while this inspection confirms
    # that the actual native lane retains the Nat48 budget representation.
    lines = text.splitlines()
    matches = [{"line": index, "text": line.strip()} for index, line in enumerate(lines, 1)
               if ("#define NAT_IMM" in line or "#define CID____SRC_UNICODE_" in line
                   or "Term _remaining_0 = (_room_1 - 1)" in line
                   or "U32_BIN(_code_1, >=, 55296ull)" in line
                   or "U32_BIN(_code_1, <=, 1114111ull)" in line
                   or "U32_BIN(_byte_0, <=, 255ull)" in line
                   or "U32_BIN(_byte_1, <=, 191ull)" in line)]
    if "#define NAT_IMM   ((1ull << 48) - 1)" not in text:
        raise AssertionError("emitted C has no expected 48-bit value mask")
    for symbol in ("CID____SRC_UNICODE_DECODER", "CID____SRC_UNICODE_ENCODER"):
        if symbol not in text:
            raise AssertionError(f"emitted C has no {symbol} symbol")
    debit_positions = [index for index, line in enumerate(lines) if "Term _remaining_0 = (_room_1 - 1)" in line]
    if len(debit_positions) < 2:
        raise AssertionError("emitted C omitted expected encoder/decoder budget predecessor operations")
    debit_excerpts = [{"first_line": max(1, index - 14), "last_line": index + 2,
                      "text": "\n".join(lines[max(0, index - 15):index + 2])}
                     for index in debit_positions[:2]]
    return {"path": str(path.relative_to(ROOT)), "sha256": digest(path),
            "nat48_mask_present": True, "codec_state_symbols_present": True,
            "selected_lines": matches[:30],
            "budget_excerpts": debit_excerpts,
            "compiler_observation": "Public decode/encode definitions are inlined into native harness entry paths; their Data state constructors remain named.",
            "scope": "Representation, scalar/byte guards and zero-guarded budget predecessor review, not a separate C correctness proof."}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bend", type=Path, default=Path.home() / ".bend/bin/bend")
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--evidence", type=Path, default=ROOT / "evidence/unicode-native.json")
    args = parser.parse_args()
    started = time.monotonic()
    binary = ROOT / "build/unicode-tests"
    emitted = ROOT / "build/unicode-tests.c"
    folder = ROOT / "build/unicode-fixtures"
    folder.mkdir(parents=True, exist_ok=True)
    try:
        version = command([args.bend, "version"])
        if version["stdout"].strip() != "bend 2.0.35":
            raise AssertionError("compiler differs from pinned 2.0.35")
        checks = [command([args.bend, source, "--verdict"]) for source in ("src/unicode.bend", "tests/unicode.bend")]
        if any(check["stdout"].strip() != "ALL PROOFS CHECK" for check in checks):
            raise AssertionError("independent kernel verdict missing")
        if not args.skip_build:
            command([args.bend, "tests/unicode.bend", "-o", binary])
        command([args.bend, "tests/unicode.bend", "-o", emitted])
        c_review = emitted_c_review(emitted)
        cases = corpus()
        observations, batch_count = execute(binary, cases)
        large = large_cases(binary, folder)
        errors = Counter(item["result"]["error"] for item in observations if not item["result"]["ok"])
        sources = [ROOT / "src/unicode.bend", ROOT / "tests/unicode.bend", Path(__file__).resolve()]
        report = {
            "status": "passed", "confidence": "high for the stated codec behavior and tested native limits",
            "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
            "elapsed_seconds": time.monotonic() - started,
            "platform": platform.platform(), "python": platform.python_version(), "random_seed": SEED,
            "compiler_version": version["stdout"].strip(), "compiler_sha256": digest(args.bend),
            "native_binary_sha256": digest(binary),
            "source_sha256": {str(path.relative_to(ROOT)): digest(path) for path in sources},
            "independent_kernel_results": checks, "emitted_c_review": c_review,
            "small_case_count": len(cases), "small_native_batch_count": batch_count,
            "assembled_chunk_count": sum(len(case.chunks) for case in cases),
            "exact_output_comparison_count": sum(item["result"]["ok"] for item in observations),
            "large_case_count": len(large), "all_valid_scalar_count_per_direction": 0x110000 - 0x800,
            "all_surrogate_count_per_direction": 0x800, "failure_counts": dict(sorted(errors.items())),
            "corpus_sha256": hashlib.sha256(json.dumps([case.__dict__ for case in cases], sort_keys=True).encode()).hexdigest(),
            "observed_sha256": hashlib.sha256(json.dumps(observations, sort_keys=True).encode()).hexdigest(),
            "large_cases": large,
            "commands": [[str(args.bend), "src/unicode.bend", "--verdict"],
                         [str(args.bend), "tests/unicode.bend", "--verdict"],
                         [str(args.bend), "tests/unicode.bend", "-o", str(binary)],
                         [str(args.bend), "tests/unicode.bend", "-o", str(emitted)],
                         ["python3", "tools/test_unicode.py"] + (["--skip-build"] if args.skip_build else [])],
            "proof_scope": ["Six general empty-input/budget-transition laws and eleven finite codec regression equalities.",
                            "No universal Unicode round-trip, parser soundness or game-parity theorem is claimed.",
                            "No unsafe, foreign or axiom dependency exists in src/unicode.bend."],
            "boundaries": ["Public APIs operate on complete inputs; chunk assembly tests do not claim a streaming API.",
                           "Caller limits are native Nat values in [0, 2^48-1]; only predecessor operations consume them.",
                           "Decoder bounds scalar output count, encoder bounds byte output count; callers separately enforce input byte limits.",
                           "Large outputs use length/FNV-1a-32 comparisons, which are empirical checks with hash collision limits.",
                           "Python and standard Base File/IO only orchestrate native tests; the codec implementation is pure Bend."],
        }
        args.evidence.parent.mkdir(parents=True, exist_ok=True)
        args.evidence.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({"status": "passed", "small_cases": len(cases), "large_cases": len(large),
                          "valid_scalars_per_direction": report["all_valid_scalar_count_per_direction"],
                          "evidence": str(args.evidence)}))
        return 0
    except (AssertionError, OSError, subprocess.SubprocessError, ValueError, RuntimeError) as error:
        print(f"Unicode verification failed: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
