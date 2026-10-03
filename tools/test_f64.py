#!/usr/bin/env python3
"""Independent native binary64 bit fixtures and an arithmetic-only C oracle."""
from __future__ import annotations
import argparse
from collections import Counter
from fractions import Fraction
import hashlib
import itertools
import json
import math
import platform
from pathlib import Path
import random
import re
import statistics
import struct
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
SIGN = 1 << 63
EXP = 0x7FF0000000000000
FRAC = (1 << 52)-1
QUIET = 1 << 51
CANONICAL_NAN = EXP | QUIET

# This generated test-only program performs hardware double arithmetic. It has
# no gameplay/state semantics and is never linked into the Bend implementation.
REFERENCE_C = r'''
#include <fenv.h>
#include <inttypes.h>
#include <math.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
static double from_bits(uint64_t bits) { double value; memcpy(&value,&bits,8); return value; }
static uint64_t to_bits(double value) { uint64_t bits; memcpy(&bits,&value,8); return bits; }
static uint64_t now_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return (uint64_t)t.tv_sec*1000000000+(uint64_t)t.tv_nsec; }
static void print_conversion(double value, int use_floor) {
  if (isnan(value)) { printf("nan"); return; }
  double integer=use_floor?floor(value):trunc(value);
  if (!isfinite(integer) || integer<INT32_MIN || integer>INT32_MAX) { printf("range"); return; }
  printf("ok:%" PRIu32,(uint32_t)(int32_t)integer);
}
int main(int argc,char **argv) {
  if (sizeof(double)!=8 || fesetround(FE_TONEAREST)!=0) return 2;
  if (argc==5 && (strcmp(argv[1],"bench")==0 || strcmp(argv[1],"benchmul")==0 || strcmp(argv[1],"benchdiv")==0)) {
    uint64_t iterations=strtoull(argv[2],0,10);
    double accumulator=from_bits(strtoull(argv[3],0,16));
    double delta=from_bits(strtoull(argv[4],0,16));
    uint64_t started=now_ns();
    if (strcmp(argv[1],"benchmul")==0) { for(uint64_t i=0;i<iterations;i++) accumulator*=delta; }
    else if (strcmp(argv[1],"benchdiv")==0) { for(uint64_t i=0;i<iterations;i++) accumulator/=delta; }
    else { for(uint64_t i=0;i<iterations;i++) accumulator+=delta; }
    uint64_t elapsed=now_ns()-started;
    printf("%016" PRIx64 "|%" PRIu64 "\n",to_bits(accumulator),elapsed);
    return 0;
  }
  if (argc==2 && strcmp(argv[1],"convert")==0) {
    uint32_t word; uint64_t bits;
    while(scanf("%" SCNx32 " %" SCNx64,&word,&bits)==2) {
      int32_t signed_word; float single;
      memcpy(&signed_word,&word,4); memcpy(&single,&word,4);
      printf("%016" PRIx64 " %016" PRIx64 " %016" PRIx64 " ",to_bits((double)word),to_bits((double)signed_word),to_bits((double)single));
      print_conversion(from_bits(bits),0); printf(" "); print_conversion(from_bits(bits),1); printf("\n");
    }
    return 0;
  }
  uint64_t a,b;
  while (scanf("%" SCNx64 " %" SCNx64,&a,&b)==2) {
    volatile double left=from_bits(a),right=from_bits(b);
    double sum=left+right,difference=left-right,product=left*right,quotient=left/right;
    printf("%016" PRIx64 " %016" PRIx64 " %016" PRIx64 " %016" PRIx64 "\n",to_bits(sum),to_bits(difference),to_bits(product),to_bits(quotient));
  }
  return 0;
}
'''


def float_bits(value: float) -> int:
    return int.from_bytes(struct.pack(">d", value), "big")


def bits_float(bits: int) -> float:
    return struct.unpack(">d", bits.to_bytes(8, "big"))[0]


def category(bits: int) -> int:
    exponent = bits & EXP
    fraction = bits & FRAC
    if exponent == EXP:
        return 4 if fraction else 3
    if exponent == 0:
        return 1 if fraction else 0
    return 2


def expected_arithmetic(a: int, b: int, operation: str) -> int:
    # Explicit module NaN policy is checked separately from hardware payloads.
    if category(a) == 4:
        return a | QUIET
    if category(b) == 4:
        return b | QUIET
    left, right = bits_float(a), bits_float(b)
    if operation == "div":
        if right == 0.0:
            return CANONICAL_NAN if left == 0.0 else EXP | ((a ^ b) & SIGN)
        result = left/right
    else:
        result = left*right if operation == "mul" else left-right if operation == "sub" else left+right
    return CANONICAL_NAN if math.isnan(result) else float_bits(result)


def expected(a: int, b: int) -> list[int]:
    left, right = bits_float(a), bits_float(b)
    unordered = math.isnan(left) or math.isnan(right)
    order = 3 if unordered else 0 if left < right else 2 if left > right else 1
    relations = (left == right, left != right, left < right, left <= right,
                 left > right, left >= right)
    mask = sum(int(value) << index for index, value in enumerate(relations))
    sum_bits = expected_arithmetic(a, b, "add")
    difference_bits = expected_arithmetic(a, b, "sub")
    product_bits = expected_arithmetic(a, b, "mul")
    quotient_bits = expected_arithmetic(a, b, "div")
    negative_bits, absolute_bits = a ^ SIGN, a & ~SIGN
    return [sum_bits >> 32, sum_bits & 0xFFFFFFFF,
            difference_bits >> 32, difference_bits & 0xFFFFFFFF,
            product_bits >> 32, product_bits & 0xFFFFFFFF,
            quotient_bits >> 32, quotient_bits & 0xFFFFFFFF,
            order, category(a), category(b), int(bool(a & SIGN)), int(bool(b & SIGN)),
            int(category(a) < 3), int(category(b) < 3), mask,
            negative_bits >> 32, negative_bits & 0xFFFFFFFF,
            absolute_bits >> 32, absolute_bits & 0xFFFFFFFF]


def fixtures(seed: int, count: int) -> list[tuple[str, int, int]]:
    cases: list[tuple[str, int, int]] = []
    edges = {0, 1, 2, 3, FRAC-1, FRAC, 1 << 52, (1 << 52)+1,
             (1 << 52)+2, 0x7FEFFFFFFFFFFFFE, 0x7FEFFFFFFFFFFFFF,
             EXP, EXP | 1, EXP | FRAC, CANONICAL_NAN, CANONICAL_NAN | 12345}
    for exponent in (-1022, -1021, -1000, -53, -52, -51, -1, 0, 1, 2, 31, 32, 51, 52, 53, 54, 1000, 1023):
        value = float_bits(math.ldexp(1.0, exponent))
        edges.update((value, value-1, value+1))
    edges |= {value | SIGN for value in tuple(edges)}
    for a, b in itertools.product(sorted(edges), repeat=2):
        cases.append(("edge", a, b))
    rng = random.Random(seed)
    finite_random = 0
    while finite_random < count:
        a, b = rng.getrandbits(64), rng.getrandbits(64)
        if category(a) < 3 and category(b) < 3:
            cases.append(("uniform_finite", a, b))
            finite_random += 1
    # Independent nextafter-based halfway neighborhoods, exponent gaps, and
    # cancellation patterns emphasize failure modes sparse uniform bits miss.
    for _ in range(max(2000, count//4)):
        exponent = rng.randrange(-1021, 1024)
        a = ((exponent+1023) << 52) | rng.getrandbits(52)
        half = math.ldexp(1.0, exponent-53)
        delta = rng.choice((half, math.nextafter(half, 0.0), math.nextafter(half, math.inf)))
        b = float_bits(delta)
        a |= rng.choice((0, SIGN))
        b |= rng.choice((0, SIGN))
        cases.append(("halfway_neighbor", a, b))
        near = (a & ~SIGN) + rng.choice((-2, -1, 0, 1, 2))
        if 0 < near < EXP:
            cases.append(("cancellation", a, near | (0 if a & SIGN else SIGN)))
    for numerator in (1, 3, 5, 7, FRAC, (1 << 52)+1, (1 << 52)+3):
        for denominator in (2.0, 4.0, 8.0, math.nextafter(2.0, 0.0), math.nextafter(2.0, math.inf)):
            for sign_a, sign_b in itertools.product((0, SIGN), repeat=2):
                cases.append(("division_subnormal_tie", numerator | sign_a, float_bits(denominator) | sign_b))
    for a in (0x7FEFFFFFFFFFFFFF, 0x7FEFFFFFFFFFFFFE, 0x0010000000000000, 1):
        for b in (float_bits(0.5), float_bits(2.0), float_bits(math.nextafter(1.0, 0.0)), float_bits(math.nextafter(1.0, math.inf))):
            cases.append(("division_range_boundary", a, b))
    return cases


def run(args: list[str], *, stdin: str | None = None, timeout: int = 120) -> subprocess.CompletedProcess:
    result = subprocess.run(args, cwd=ROOT, input=stdin, text=True,
                            capture_output=True, timeout=timeout, check=False)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {args[:8]}\n{result.stdout[:1000]}\n{result.stderr}")
    return result


def rational_check(cases: list[tuple[str, int, int]], expected_rows: list[list[int]]) -> dict:
    checked = 0
    # Python Fraction computes the exact rational result with arbitrary-size
    # integers; float conversion supplies a second, independent rounding path.
    for index, (kind, a, b) in enumerate(cases):
        if kind == "edge" or category(a) >= 3 or category(b) >= 3:
            continue
        left, right = bits_float(a), bits_float(b)
        if left == 0.0 or right == 0.0:
            continue
        for operation in ("add", "sub", "mul", "div"):
            exact = Fraction(left)/Fraction(right) if operation == "div" else Fraction(left)*Fraction(right) if operation == "mul" else Fraction(left)-Fraction(right) if operation == "sub" else Fraction(left)+Fraction(right)
            if exact == 0:
                reference = 0  # Exact nonzero cancellation is +0 under RN-even.
            else:
                try:
                    reference = float_bits(float(exact))
                except OverflowError:
                    reference = EXP | (SIGN if exact < 0 else 0)
            offset = {"add": 0, "sub": 2, "mul": 4, "div": 6}[operation]
            observed = (expected_rows[index][offset] << 32) | expected_rows[index][offset+1]
            if observed != reference:
                raise AssertionError(f"Rational oracle disagrees: {a:016x}, {b:016x}, operation={operation}")
        checked += 1
        if checked == 2000:
            break
    boundary_divisions = 0
    for index, (kind, a, b) in enumerate(cases):
        if not kind.startswith("division_"):
            continue
        exact = Fraction(bits_float(a))/Fraction(bits_float(b))
        try:
            reference = float_bits(float(exact))
        except OverflowError:
            reference = EXP | (SIGN if exact < 0 else 0)
        row = expected_rows[index]
        if reference != ((row[6] << 32) | row[7]):
            raise AssertionError(f"Exact division-boundary oracle disagrees: {a:016x}, {b:016x}")
        boundary_divisions += 1
    return {"random_operand_pairs": checked, "random_arithmetic_checks": 4*checked,
            "targeted_division_boundary_checks": boundary_divisions,
            "total": 4*checked+boundary_divisions}


def conversion_expected(word: int, bits: int) -> list[str]:
    signed = word if word < 2**31 else word-2**32
    unsigned_bits, signed_bits = float_bits(float(word)), float_bits(float(signed))
    float_exponent, float_fraction = (word >> 23) & 255, word & 0x7FFFFF
    if float_exponent == 255 and float_fraction:
        widened = ((word & 0x80000000) << 32) | EXP | (float_fraction << 29) | QUIET
    else:
        widened = float_bits(struct.unpack(">f", word.to_bytes(4, "big"))[0])
    value = bits_float(bits)
    statuses = []
    for use_floor in (False, True):
        if math.isnan(value):
            status = "nan"
        elif math.isinf(value):
            status = "range"
        else:
            integer = math.floor(value) if use_floor else math.trunc(value)
            status = f"ok:{integer & 0xFFFFFFFF}" if -2**31 <= integer < 2**31 else "range"
        statuses.append(status)
    values = (unsigned_bits >> 32, unsigned_bits & 0xFFFFFFFF,
              signed_bits >> 32, signed_bits & 0xFFFFFFFF,
              widened >> 32, widened & 0xFFFFFFFF)
    return [str(value) for value in values] + statuses


def conversion_fixtures(seed: int, count: int) -> list[tuple[int, int]]:
    words = {0, 1, 2, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 0x007FFFFF,
             0x00800000, 0x3F800000, 0x3F800001, 0x3DCCCCCD, 0x7F7FFFFF,
             0x7F800000, 0x7F800001, 0x7FC00000, 0x7FFFFFFF}
    words |= {word | 0x80000000 for word in tuple(words)}
    values = {0, SIGN, 1, SIGN | 1, EXP, SIGN | EXP, EXP | 1, SIGN | EXP | 1,
              CANONICAL_NAN, SIGN | CANONICAL_NAN}
    for value in (-2**31-1, -2**31, -2**31+1, -2**31-0.9, -2**31-0.5,
                  -1.5, -1.0, -0.5, 0.5, 1.0, 1.5, 2**31-1.0,
                  2**31-0.9, 2**31-0.5, 2**31-0.1, 2**31, 2**31+1.0):
        values.update((float_bits(float(value)), float_bits(math.nextafter(float(value), -math.inf)),
                       float_bits(math.nextafter(float(value), math.inf))))
    cases = list(itertools.product(sorted(words), sorted(values)))
    rng = random.Random(seed ^ 0x32F64)
    for _ in range(count):
        word = rng.getrandbits(32)
        bits = rng.getrandbits(64)
        cases.append((word, bits))
    # Dense movement-like finite fractions, rather than almost-all range errors.
    for _ in range(max(2000, count//4)):
        word = rng.getrandbits(32)
        value = rng.randrange(-2**31, 2**31) + rng.choice((-0.999, -0.5, 0.0, 0.5, 0.999))
        cases.append((word, float_bits(value)))
    return cases


def check_conversions(binary: Path, reference: Path, seed: int, count: int) -> dict:
    cases = conversion_fixtures(seed, count)
    rows = [conversion_expected(word, bits) for word, bits in cases]
    hardware = run([str(reference), "convert"], stdin="".join(f"{word:08x} {bits:016x}\n" for word, bits in cases))
    hardware_rows = hardware.stdout.splitlines()
    if len(hardware_rows) != len(cases):
        raise AssertionError("C conversion oracle row count mismatch")
    c_nan_class_checks = 0
    for index, line in enumerate(hardware_rows):
        unsigned, signed, widened, trunc_status, floor_status = line.split()
        bits = (int(unsigned, 16), int(signed, 16), int(widened, 16))
        row = rows[index]
        expected_bits = tuple((int(row[offset]) << 32) | int(row[offset+1]) for offset in (0, 2, 4))
        if bits[:2] != expected_bits[:2] or [trunc_status, floor_status] != row[6:]:
            raise AssertionError(f"C conversion disagreement on {cases[index]}, {line}, {row}")
        if category(expected_bits[2]) == 4:
            c_nan_class_checks += 1
            if category(bits[2]) != 4:
                raise AssertionError("C widening NaN class mismatch")
        elif bits[2] != expected_bits[2]:
            raise AssertionError(f"C exact widening mismatch on {cases[index]}")
    outcomes = Counter()
    for first in range(0, len(cases), 128):
        arguments = [f"convert|{word}|{bits >> 32}|{bits & 0xFFFFFFFF}|0|0"
                     for word, bits in cases[first:first+128]]
        observed = run([str(binary), "--gpu", "off", "--threads", "1", "--", *arguments]).stdout.splitlines()
        if len(observed) != len(arguments):
            raise AssertionError("Native conversion row count mismatch")
        for index, line in enumerate(observed, first):
            label, word, *row = line.split("|")
            if label != "convert" or int(word) != cases[index][0] or row != rows[index]:
                raise AssertionError(json.dumps({"word": f"{cases[index][0]:08x}", "value": f"{cases[index][1]:016x}",
                                                 "expected": rows[index], "observed": row}, indent=2))
            outcomes[f"trunc:{row[-2].split(':')[0]}"] += 1
            outcomes[f"floor:{row[-1].split(':')[0]}"] += 1
    return {"cases": len(cases), "native_from_word_bit_comparisons": 3*len(cases),
            "native_checked_i32_comparisons": 2*len(cases),
            "c_exact_widening_comparisons": len(cases)-c_nan_class_checks,
            "c_nan_widening_class_checks": c_nan_class_checks,
            "outcomes": dict(sorted(outcomes.items())),
            "fixture_sha256": hashlib.sha256("\n".join(f"{word:08x}|{bits:016x}" for word,bits in cases).encode()).hexdigest()}


def benchmark(binary: Path, reference: Path, iterations: int, repeats: int) -> dict:
    results = []
    for name, operation, initial, delta in (("unit_increment", "bench", 0, float_bits(1.0)),
                                            ("decimal_increment", "bench", float_bits(1.0), float_bits(0.1)),
                                            ("near_unity_product", "benchmul", float_bits(1.0), float_bits(1.0)+1),
                                            ("near_unity_quotient", "benchdiv", float_bits(1.0), float_bits(1.0)+1)):
        argument = f"{operation}|{iterations}|{initial >> 32}|{initial & 0xFFFFFFFF}|{delta >> 32}|{delta & 0xFFFFFFFF}"
        bend_ms, c_ns, bend_wall_ns = [], [], []
        for _ in range(repeats):
            started = time.perf_counter_ns()
            native = run([str(binary), "--gpu", "off", "--threads", "1", "--", argument])
            bend_wall_ns.append(time.perf_counter_ns()-started)
            tag, hi, lo, millis = native.stdout.strip().split("|")
            bend_bits = (int(hi) << 32) | int(lo)
            hardware = run([str(reference), operation, str(iterations), f"{initial:016x}", f"{delta:016x}"])
            bits, nanos = hardware.stdout.strip().split("|")
            if tag != "bench" or bend_bits != int(bits, 16):
                raise AssertionError(f"Benchmark bit mismatch: {native.stdout}, {hardware.stdout}")
            bend_ms.append(int(millis))
            c_ns.append(int(nanos))
        bend_median_ms = statistics.median(bend_ms)
        c_median_ns = statistics.median(c_ns)
        results.append({"workload": name, "iterations": iterations,
                        "result_bits": f"{bend_bits:016x}", "bend_loop_milliseconds": bend_ms,
                        "c_double_loop_nanoseconds": c_ns, "bend_process_wall_nanoseconds": bend_wall_ns,
                        "median_bend_ns_per_operation": bend_median_ms*1_000_000/iterations,
                        "median_c_ns_per_operation": c_median_ns/iterations,
                        "median_soft_to_hardware_ratio": bend_median_ms*1_000_000/c_median_ns})
    return {"backend": "native CPU; --gpu off --threads 1", "repeats": repeats,
            "timing": "Bend IO.now: 1ms resolution, sequenced around evaluated loop; C CLOCK_MONOTONIC: ns; process startup separately recorded",
            "workloads": results}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bend", default="/Users/chuah/.bend/bin/bend")
    parser.add_argument("--seed", type=int, default=640263)
    parser.add_argument("--random", type=int, default=20000)
    parser.add_argument("--iterations", type=int, default=1000000)
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--evidence", default="evidence/f64-oracle.json")
    options = parser.parse_args()
    if options.random < 10000:
        raise ValueError("At least 10,000 random finite pairs are required")
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    binary, reference = build/"f64_test", build/"f64_reference"
    reference_source, emitted_c = build/"f64_reference.c", build/"f64_test.c"
    reference_source.write_text(REFERENCE_C)
    checked = run([options.bend, "src/f64.bend", "--verdict"])
    if "ALL PROOFS CHECK" not in checked.stdout:
        raise AssertionError(checked.stdout)
    run([options.bend, "tests/f64.bend", "-o", "build/f64_test"])
    run([options.bend, "tests/f64.bend", "-o", "build/f64_test.c"])
    run(["clang", "-O3", "-fno-fast-math", "-ffp-contract=off", str(reference_source), "-o", str(reference)])
    cases = fixtures(options.seed, options.random)
    expected_rows = [expected(a, b) for _, a, b in cases]
    rational_count = rational_check(cases, expected_rows)
    # Cross-check all ordinary results against independently compiled C double.
    ordinary_indices = [index for index, (_, a, b) in enumerate(cases)
                        if category(a) < 3 and category(b) < 3]
    reference_input = "".join(f"{cases[index][1]:016x} {cases[index][2]:016x}\n" for index in ordinary_indices)
    hardware = run([str(reference)], stdin=reference_input)
    hardware_rows = hardware.stdout.splitlines()
    if len(hardware_rows) != len(ordinary_indices):
        raise AssertionError("C oracle row count mismatch")
    for index, line in zip(ordinary_indices, hardware_rows, strict=True):
        sum_bits, difference_bits, product_bits, quotient_bits = map(lambda text: int(text, 16), line.split())
        row = expected_rows[index]
        if (sum_bits, difference_bits, product_bits) != ((row[0] << 32) | row[1], (row[2] << 32) | row[3], (row[4] << 32) | row[5]):
            raise AssertionError(f"Python/C oracle disagreement on fixture {index}")
        if category((row[6] << 32) | row[7]) != 4 and quotient_bits != ((row[6] << 32) | row[7]):
            raise AssertionError(f"Python/C division disagreement on fixture {index}")
        if category((row[6] << 32) | row[7]) == 4 and category(quotient_bits) != 4:
            raise AssertionError(f"Python/C division class disagreement on fixture {index}")
    started = time.perf_counter()
    for first in range(0, len(cases), 128):
        arguments = [f"c{index}|{a >> 32}|{a & 0xFFFFFFFF}|{b >> 32}|{b & 0xFFFFFFFF}|0"
                     for index, (_, a, b) in enumerate(cases[first:first+128], first)]
        result = run([str(binary), "--gpu", "off", "--threads", "1", "--", *arguments], timeout=30)
        lines = result.stdout.splitlines()
        if len(lines) != len(arguments):
            raise AssertionError("Native row count mismatch")
        for index, line in enumerate(lines, first):
            label, *values = line.split("|")
            observed = list(map(int, values))
            if label != f"c{index}" or observed != expected_rows[index]:
                kind, a, b = cases[index]
                raise AssertionError(json.dumps({"index": index, "fixture": kind,
                    "a_bits": f"{a:016x}", "b_bits": f"{b:016x}",
                    "expected": expected_rows[index], "observed": observed}, indent=2))
    native_elapsed = time.perf_counter()-started
    conversions = check_conversions(binary, reference, options.seed, options.random)
    bench = benchmark(binary, reference, options.iterations, options.repeats)
    generated = emitted_c.read_text()
    scalar_helpers = re.findall(r'(?ms)^INLINE Term spin_\d+\([^\n]+\) \{\n.*?^\}', generated)
    scalar_text = "\n".join(scalar_helpers)
    if re.search(r'\bdouble\b|f32_unbox|f32_rewrap', scalar_text):
        raise AssertionError("Software arithmetic unexpectedly contains host floating arithmetic")
    evidence = {
        "schema": 1, "result": "pass", "platform": {"system": platform.system(), "release": platform.release(), "machine": platform.machine()}, "compiler": run([options.bend, "version"]).stdout.strip(),
        "kernel_verdict": checked.stdout.strip(), "verification_scope": "type/termination validity, not an IEEE arithmetic theorem",
        "fixture_pairs": len(cases), "finite_pairs": len(ordinary_indices), "finite_add_sub_mul_div_bit_comparisons": 4*len(ordinary_indices),
        "random_finite_pairs": options.random, "seed": options.seed,
        "fixture_kinds": dict(Counter(kind for kind, _, _ in cases)),
        "conversions": conversions,
        "c_double_nan_class_checks": sum(category(a) == 0 and category(b) == 0 for _, a, b in cases),
        "c_double_exact_finite_input_result_comparisons": 4*len(ordinary_indices)-sum(category(a) == 0 and category(b) == 0 for _, a, b in cases),
        "exact_fraction_rounding_cross_checks": rational_count["total"],
        "exact_fraction_breakdown": rational_count,
        "fixture_sha256": hashlib.sha256("\n".join(f"{kind}|{a:016x}|{b:016x}" for kind,a,b in cases).encode()).hexdigest(),
        "native_fixture_wall_seconds": native_elapsed,
        "nan_policy": "first input NaN retains sign/payload and is quieted; invalid infinities produce canonical +quiet NaN",
        "rounding": "nearest, ties to even; gradual underflow; signed-zero arithmetic",
        "benchmark": bench,
        "emitted_c": {"bytes": emitted_c.stat().st_size, "lines": len(generated.splitlines()),
                      "scalar_inline_helpers": len(scalar_helpers),
                      "scalar_helper_u32_operations": scalar_text.count("U32_BIN("),
                      "scalar_helpers_use_host_floating_arithmetic": False,
                      "sha256": hashlib.sha256(emitted_c.read_bytes()).hexdigest()},
        "native_binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
        "reference_c_sha256": hashlib.sha256(reference_source.read_bytes()).hexdigest(),
        "source_sha256": {path: hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for path in
                          ("src/f64.bend", "tests/f64.bend", "tools/test_f64.py")},
        "commands": [[options.bend, "src/f64.bend", "--verdict"],
                     [options.bend, "tests/f64.bend", "-o", "build/f64_test"],
                     [options.bend, "tests/f64.bend", "-o", "build/f64_test.c"],
                     ["clang", "-O3", "-fno-fast-math", "-ffp-contract=off", "build/f64_reference.c", "-o", "build/f64_reference"],
                     ["python3", "tools/test_f64.py", "--seed", str(options.seed), "--random", str(options.random),
                      "--iterations", str(options.iterations), "--repeats", str(options.repeats)]],
        "unsupported": ["remainder/sqrt/transcendentals", "decimal parsing/formatting", "i64 input/output", "rounding modes other than RN-even", "floating exception flags", "Minecraft collision/movement parity"],
    }
    destination = ROOT/options.evidence
    destination.write_text(json.dumps(evidence, indent=2)+"\n")
    print(json.dumps({"result": "pass", "fixture_pairs": len(cases), "finite_pairs": len(ordinary_indices),
                      "finite_bit_comparisons": 4*len(ordinary_indices), "native_seconds": round(native_elapsed, 3),
                      "conversions": conversions, "benchmark": bench, "evidence": str(destination)}, indent=2))


if __name__ == "__main__":
    main()
