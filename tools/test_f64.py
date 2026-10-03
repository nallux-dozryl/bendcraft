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

from reference_inventory import JAVA, fingerprint

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
#include <float.h>
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
static uint32_t single_bits(float value) { uint32_t bits; memcpy(&bits,&value,4); return bits; }
static uint64_t now_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return (uint64_t)t.tv_sec*1000000000+(uint64_t)t.tv_nsec; }
static void print_conversion(double value, int use_floor) {
  if (isnan(value)) { printf("nan"); return; }
  double integer=use_floor?floor(value):trunc(value);
  if (!isfinite(integer) || integer<INT32_MIN || integer>INT32_MAX) { printf("range"); return; }
  printf("ok:%" PRIu32,(uint32_t)(int32_t)integer);
}
int main(int argc,char **argv) {
  if (sizeof(double)!=8 || sizeof(float)!=4 || FLT_RADIX!=2 || DBL_MANT_DIG!=53 || DBL_MAX_EXP!=1024 || FLT_MANT_DIG!=24 || FLT_MAX_EXP!=128 || fesetround(FE_TONEAREST)!=0) return 2;
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
  if (argc==2 && strcmp(argv[1],"narrow")==0) {
    uint64_t bits;
    while(scanf("%" SCNx64,&bits)==1) { volatile double value=from_bits(bits); printf("%08" PRIx32 "\n",single_bits((float)value)); }
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


NARROW_JAVA = r'''
import java.io.*;
public class F64NarrowingReference {
  public static void main(String[] args) throws Exception {
    BufferedReader input=new BufferedReader(new InputStreamReader(System.in));
    PrintWriter output=new PrintWriter(System.out); String line;
    while((line=input.readLine())!=null) {
      double value=Double.longBitsToDouble(Long.parseUnsignedLong(line,16));
      output.println(Integer.toUnsignedString(Float.floatToRawIntBits((float)value),16));
    }
    output.flush(); if(output.checkError()) throw new IOException("Cast observation failed");
  }
}
'''


def single_value(bits: int) -> float:
    return struct.unpack(">f", bits.to_bytes(4, "big"))[0]


def narrowing_expected(bits: int) -> int:
    if category(bits) == 4:
        return ((bits >> 32) & 0x80000000) | 0x7F800000 | ((bits & FRAC) >> 29) | 0x400000
    value = bits_float(bits)
    try:
        return int.from_bytes(struct.pack(">f", value), "big")
    except OverflowError:
        return 0x7F800000 | (0x80000000 if bits & SIGN else 0)


def narrowing_fixtures(seed: int, count: int, step_samples: Path | None = None) -> list[tuple[str, int]]:
    edges = {0, SIGN, 1, SIGN | 1, EXP, SIGN | EXP, EXP | 1, EXP | FRAC,
             CANONICAL_NAN, EXP | (1 << 29), EXP | (1 << 51), EXP | ((1 << 29)-1)}
    edges |= {bits | SIGN for bits in tuple(edges)}
    cases = [("special", bits) for bits in sorted(edges)]
    singles = {0, 1, 2, 3, 4, 0x007FFFFE, 0x007FFFFF, 0x00800000, 0x00800001,
               0x3F000000, 0x3F19999A, 0x3F800000, 0x4B800000, 0x7F7FFFFE, 0x7F7FFFFF}
    # Entire exponent range, both even/odd significands, and overflow midpoint.
    for exponent in range(1, 255):
        singles.update((exponent << 23 | fraction) for fraction in (0, 1, 2, 0x3FFFFF, 0x7FFFFE))
    rng = random.Random(seed ^ 0xF32CA57)
    singles.update(rng.randrange(0x7F7FFFFF) for _ in range(2000))
    for word in sorted(singles):
        lower = single_value(word)
        upper = math.ldexp(1.0, 128) if word == 0x7F7FFFFF else single_value(word+1)
        midpoint = (lower+upper)/2  # Exact double: endpoints have <=24-bit significands.
        for value in (math.nextafter(midpoint, 0.0), midpoint, math.nextafter(midpoint, math.inf)):
            for negative in (False, True):
                cases.append(("f32_halfway_neighbor", float_bits(-value if negative else value)))
        for negative in (False, True):
            cases.append(("f32_exact_roundtrip", float_bits(-lower if negative else lower)))
    # Step-up candidate neighborhoods requested by the 26.3 movement owner.
    for center in (0.0, -0.0, 0.5, single_value(0x3F19999A), 1e-7,
                   single_value(0x3727C5AC), math.ldexp(1.0, -150),
                   math.ldexp(1.0, 24), single_value(0x7F7FFFFF)):
        for value in (math.nextafter(center, -math.inf), center, math.nextafter(center, math.inf)):
            cases.append(("step_height_requested_neighborhood", float_bits(value)))
    if step_samples is not None:
        observed = json.loads(step_samples.read_text())
        for raw in observed["candidate_delta_f64_bits"]:
            cases.append(("step_height_observed_26_3", int(raw, 16)))
    for _ in range(count):
        cases.append(("uniform_payload", rng.getrandbits(64)))
    return cases


def rational_narrowing(bits: int) -> int:
    """Independent exact nearest-neighbor search, not a significand-shift algorithm."""
    sign = 0x80000000 if bits & SIGN else 0
    value = Fraction(abs(bits_float(bits)))
    if value >= Fraction(single_value(0x7F7FFFFF)) + Fraction(2)**103:
        return sign | 0x7F800000
    low, high = 0, 0x7F7FFFFF
    while low < high:
        middle = (low+high+1)//2
        if Fraction(single_value(middle)) <= value:
            low = middle
        else:
            high = middle-1
    if low == 0x7F7FFFFF:
        return sign | low
    midpoint = (Fraction(single_value(low))+Fraction(single_value(low+1)))/2
    rounded = low+1 if value > midpoint or (value == midpoint and low & 1) else low
    return sign | rounded


def check_narrowing(binary: Path, reference: Path, seed: int, count: int, step_samples: Path | None = None) -> dict:
    started = time.perf_counter()
    cases = narrowing_fixtures(seed, count, step_samples)
    expected_rows = [narrowing_expected(bits) for _, bits in cases]
    payloads = "".join(f"{bits:016x}\n" for _, bits in cases)
    c_rows = run([str(reference), "narrow"], stdin=payloads).stdout.splitlines()
    build = ROOT/"build"
    java_source = build/"F64NarrowingReference.java"
    java_source.write_text(NARROW_JAVA)
    compile_command = [str(JAVA.parent/"javac"), "-d", str(build), str(java_source)]
    run(compile_command)
    java_command = [str(JAVA), "-cp", str(build), "F64NarrowingReference"]
    java_rows = run(java_command, stdin=payloads).stdout.splitlines()
    if len(c_rows) != len(cases) or len(java_rows) != len(cases):
        raise AssertionError("Hardware narrowing oracle row count mismatch")
    nan_checks = 0
    for index, ((kind, bits), expected_bits, c, java) in enumerate(zip(cases, expected_rows, c_rows, java_rows, strict=True)):
        c_bits, java_bits = int(c, 16), int(java, 16)
        if category(bits) == 4:
            nan_checks += 1
            if not all((word & 0x7F800000) == 0x7F800000 and word & 0x7FFFFF for word in (c_bits, java_bits)):
                raise AssertionError("C/Java narrowing NaN class disagreement")
        elif c_bits != expected_bits or java_bits != expected_bits:
            raise AssertionError(f"Python/C/Java cast disagreement: {kind} {bits:016x} expected{expected_bits:08x} C{c_bits:08x} Java{java_bits:08x}")
    native_started = time.perf_counter()
    for first in range(0, len(cases), 128):
        arguments = [f"narrow|{bits >> 32}|{bits & 0xFFFFFFFF}|0|0|0" for _, bits in cases[first:first+128]]
        observed = run([str(binary), "--gpu", "off", "--threads", "1", "--", *arguments]).stdout.splitlines()
        if len(observed) != len(arguments):
            raise AssertionError("Native narrowing row count mismatch")
        for index, line in enumerate(observed, first):
            label, actual = line.split("|")
            if label != "narrow" or int(actual) != expected_rows[index]:
                raise AssertionError(f"Native cast mismatch: {cases[index]} expected{expected_rows[index]:08x} actual{int(actual):08x}")
    native_elapsed = time.perf_counter()-native_started
    rational_checks = 0
    for index, (kind, bits) in enumerate(cases):
        if category(bits) >= 3:
            continue
        if kind == "f32_halfway_neighbor" or kind.startswith("step_height") or (kind == "uniform_payload" and rational_checks < 20000):
            if rational_narrowing(bits) != expected_rows[index]:
                raise AssertionError(f"Exact nearest-neighbor cast disagreement: {kind} {bits:016x}")
            rational_checks += 1
    return {"cases": len(cases), "fixture_kinds": dict(sorted(Counter(kind for kind, _ in cases).items())),
            "native_exact_bit_comparisons": len(cases), "c_exact_non_nan_comparisons": len(cases)-nan_checks,
            "java_exact_non_nan_comparisons": len(cases)-nan_checks, "c_and_java_nan_class_checks_each": nan_checks,
            "exact_fraction_nearest_neighbor_checks": rational_checks,
            "nan_policy": "retain sign; highest23 payload bits; set F32 quiet bit",
            "fixture_sha256": hashlib.sha256("\n".join(f"{kind}|{bits:016x}" for kind, bits in cases).encode()).hexdigest(),
            "native_wall_seconds": native_elapsed, "total_wall_seconds": time.perf_counter()-started,
            "java_runtime": fingerprint(JAVA), "java_source_sha256": hashlib.sha256(NARROW_JAVA.encode()).hexdigest(),
            "java_compile_command": compile_command, "java_run_command": java_command,
            "step_sample_file": str(step_samples) if step_samples else None,
            "step_sample_sha256": hashlib.sha256(step_samples.read_bytes()).hexdigest() if step_samples else None}


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


SQRT_LONG_C = r'''
#include <fenv.h>
#include <float.h>
#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static double from_bits(uint64_t b) { double v; memcpy(&v,&b,8); return v; }
static uint64_t bits(double v) { uint64_t b; memcpy(&b,&v,8); return b; }
int main(int argc,char **argv) {
  if(argc!=2 || sizeof(double)!=8 || FLT_RADIX!=2 || DBL_MANT_DIG!=53 || fesetround(FE_TONEAREST)!=0) return 2;
  uint64_t input;
  while(scanf("%" SCNx64,&input)==1) {
    volatile double v=from_bits(input);
    if(strcmp(argv[1],"sqrt")==0) printf("%016" PRIx64 "\n",bits(sqrt(v)));
    else {
      /* Guard the C cast: conversion outside signed64 range is undefined in C. */
      int64_t out=isnan(v)?0:v>=0x1p63?INT64_MAX:v<=-0x1p63?INT64_MIN:(int64_t)v;
      printf("%016" PRIx64 "\n",(uint64_t)out);
    }
  }
  return 0;
}
'''

SQRT_LONG_JAVA = r'''
import java.io.*;
public class F64SqrtLongReference {
  public static void main(String[] args) throws Exception {
    BufferedReader input=new BufferedReader(new InputStreamReader(System.in));
    PrintWriter output=new PrintWriter(System.out); String line;
    while((line=input.readLine())!=null) {
      double v=Double.longBitsToDouble(Long.parseUnsignedLong(line,16));
      if(args[0].equals("sqrt")) output.println(Long.toUnsignedString(Double.doubleToRawLongBits(Math.sqrt(v)),16)+" "+Long.toUnsignedString(Double.doubleToRawLongBits(StrictMath.sqrt(v)),16));
      else output.println(Long.toUnsignedString((long)v,16));
    }
    output.flush(); if(output.checkError()) throw new IOException("Numeric observation failed");
  }
}
'''


def exact_dyadic(bits: int) -> Fraction:
    """Decode raw binary64 with integer arithmetic, including subnormals."""
    exponent = (bits >> 52) & 2047
    mantissa = bits & FRAC
    power = -1074 if exponent == 0 else exponent-1075
    if exponent:
        mantissa |= 1 << 52
    value = Fraction(mantissa << power, 1) if power >= 0 else Fraction(mantissa, 1 << -power)
    return -value if bits & SIGN else value


def sqrt_integer_expected(bits: int) -> int:
    """Independent arbitrary-integer isqrt and squared midpoint rounding."""
    kind = category(bits)
    if kind == 4:
        return bits | QUIET
    if kind == 0:
        return bits
    if bits & SIGN:
        return CANONICAL_NAN
    if kind == 3:
        return bits
    exponent = (bits >> 52) & 2047
    mantissa = bits & FRAC
    if exponent:
        mantissa |= 1 << 52
    shift = 53-mantissa.bit_length()
    mantissa <<= shift
    exponent = (exponent or 1)-1023-shift
    output_exponent = exponent // 2
    radicand = (mantissa << (exponent & 1)) << 52
    retained = math.isqrt(radicand)
    relation = 4*radicand-(2*retained+1)**2
    if relation > 0 or (relation == 0 and retained & 1):
        retained += 1
    if retained == 1 << 53:
        retained >>= 1
        output_exponent += 1
    return ((output_exponent+1023) << 52) | (retained & FRAC)


def sqrt_interval_check(input_bits: int, output_bits: int) -> str:
    """Compare x with exact squares of both rounding-cell midpoints."""
    value = exact_dyadic(input_bits)
    lower, center, upper = (exact_dyadic(output_bits+offset) for offset in (-1, 0, 1))
    lower_square, upper_square = ((lower+center)/2)**2, ((center+upper)/2)**2
    if value < lower_square or value > upper_square:
        raise AssertionError(f"sqrt outside exact midpoint interval: {input_bits:016x} -> {output_bits:016x}")
    if value in (lower_square, upper_square) and output_bits & 1:
        raise AssertionError("sqrt midpoint tie did not choose even significand")
    return "exact_square" if value == center*center else "lower_half" if value < center*center else "upper_half"


def sqrt_fixtures(seed: int, count: int) -> list[tuple[str, int]]:
    rng = random.Random(seed ^ 0x5A7)
    cases = [("special", bits) for bits in (0, SIGN, EXP, SIGN|EXP, EXP|1, EXP|QUIET, SIGN|EXP|1, SIGN|EXP|QUIET|FRAC)]
    for exponent in range(1, 2047):
        for mantissa in (0, 1, 2, (1 << 51)-1, 1 << 51, FRAC-1, FRAC):
            cases.append(("normal_exponent_edges", (exponent << 52)|mantissa))
    for power in range(52):
        for delta in (-1, 0, 1):
            bits = (1 << power)+delta
            if bits:
                cases.extend((("subnormal_ladder", bits), ("negative_subnormal", bits|SIGN)))
    for bits in (float_bits(float(n*n)) for n in range(1, 101)):
        cases.extend(("integer_square_neighbors", bits+delta) for delta in (-1, 0, 1))
    for _ in range(count):
        bits = rng.getrandbits(64)
        cases.append(("uniform_raw_bits", bits))
        cases.append(("uniform_positive_bits", bits & ~SIGN))
    # Square the exact midpoint between adjacent output doubles. Inputs nearest
    # that rational are deliberately hard rounding cases; no host sqrt is used.
    for _ in range(5000):
        output = (rng.randrange(486, 1535) << 52) | rng.getrandbits(52)
        midpoint = (exact_dyadic(output)+exact_dyadic(output+1))/2
        try:
            candidate = float_bits(float(midpoint*midpoint))
        except OverflowError:
            continue
        if 0 < candidate < EXP:
            for delta in (-1, 0, 1):
                if 0 < candidate+delta < EXP:
                    cases.append(("squared_midpoint_neighbors", candidate+delta))
    return cases


def java_long_expected(bits: int) -> int:
    kind = category(bits)
    if kind == 4:
        return 0
    if kind == 3:
        return 1 << 63 if bits & SIGN else (1 << 63)-1
    value = exact_dyadic(bits)
    magnitude = abs(value.numerator)//value.denominator
    integer = -magnitude if value < 0 else magnitude
    return min((1 << 63)-1, max(-(1 << 63), integer)) & ((1 << 64)-1)


def long_fixtures(seed: int, count: int) -> list[tuple[str, int]]:
    rng = random.Random(seed ^ 0x1064)
    cases = [("special", bits) for bits in (0, SIGN, EXP, SIGN|EXP, EXP|1, EXP|QUIET|FRAC, SIGN|EXP|1, SIGN|EXP|FRAC)]
    for exponent in range(2047):
        for mantissa in (0, 1, (1 << 51)-1, 1 << 51, FRAC):
            for sign in (0, SIGN):
                cases.append(("every_exponent_edges", sign|(exponent << 52)|mantissa))
    for power in range(64):
        for sign in (1, -1):
            center = float_bits(float(sign*(1 << power)))
            for delta in range(-4, 5):
                cases.append(("power_integer_neighbors", center+delta))
    for _ in range(count):
        cases.append(("uniform_raw_bits", rng.getrandbits(64)))
        value = rng.randrange(-(1 << 63), 1 << 63)
        center = float_bits(float(value))
        cases.extend(("long_range_random_neighbors", center+delta) for delta in (-1, 0, 1))
    # Exercise the actual double operands passed to the Minecraft 26.3 table
    # index cast. Java expression integration is validated by player_motion.
    for word in [0, 0x80000000, 0x3F800000, 0xBF800000, 0x7F800000, 0xFF800000, 0x7FC00000, 0x7F7FFFFF, 0xFF7FFFFF]+[rng.getrandbits(32) for _ in range(2000)]:
        angle = single_value(word)
        scaled = angle*10430.378350470453
        cases.extend((("mth_scaled_angle", float_bits(scaled)), ("mth_scaled_cos_angle", float_bits(scaled+16384.0))))
    return cases


def check_sqrt_long(binary: Path, reference: Path, java_command: list[str], operation: str, seed: int, count: int) -> dict:
    started = time.perf_counter()
    cases = sqrt_fixtures(seed, count) if operation == "sqrt" else long_fixtures(seed, count)
    expected_rows = [(sqrt_integer_expected if operation == "sqrt" else java_long_expected)(bits) for _, bits in cases]
    payload = "".join(f"{bits:016x}\n" for _, bits in cases)
    c_rows = run([str(reference), operation], stdin=payload).stdout.splitlines()
    java_rows = run([*java_command, operation], stdin=payload).stdout.splitlines()
    if len(c_rows) != len(cases) or len(java_rows) != len(cases):
        raise AssertionError("sqrt/long reference row count mismatch")
    nan_checks = 0
    for (kind, bits), expected_bits, c, java in zip(cases, expected_rows, c_rows, java_rows, strict=True):
        words = [int(c, 16), *(int(word, 16) for word in java.split())]
        if operation == "sqrt" and category(expected_bits) == 4:
            nan_checks += 1
            if any(category(word) != 4 for word in words):
                raise AssertionError(f"sqrt NaN-class mismatch {bits:016x}")
        elif any(word != expected_bits for word in words):
            raise AssertionError(f"{operation} C/Java/exact mismatch: {kind} {bits:016x}, expected {expected_bits:016x}, references {words}")
    native_started = time.perf_counter()
    for first in range(0, len(cases), 128):
        arguments = [f"{operation}|{bits >> 32}|{bits & 0xFFFFFFFF}|0|0|0" for _, bits in cases[first:first+128]]
        rows = run([str(binary), "--gpu", "off", "--threads", "1", "--", *arguments]).stdout.splitlines()
        if len(rows) != len(arguments):
            raise AssertionError("sqrt/long native row count mismatch")
        for index, row in enumerate(rows, first):
            label, hi, lo = row.split("|")
            actual = (int(hi) << 32)|int(lo)
            if label != operation or actual != expected_rows[index]:
                raise AssertionError(f"Native {operation} mismatch: {cases[index]} expected {expected_rows[index]:016x} actual {actual:016x}")
    native_elapsed = time.perf_counter()-native_started
    intervals = Counter()
    if operation == "sqrt":
        for (_, bits), result in zip(cases, expected_rows, strict=True):
            if not bits & SIGN and category(bits) in (1, 2):
                intervals[sqrt_interval_check(bits, result)] += 1
    outcomes = Counter("zero" if result == 0 else "min" if result == 1 << 63 else "max" if result == (1 << 63)-1 else "finite_integer" for result in expected_rows) if operation == "long" else None
    return {"operation": operation, "cases": len(cases), "fixture_kinds": dict(sorted(Counter(kind for kind, _ in cases).items())),
            "native_exact_bit_comparisons": len(cases), "c_exact_bit_comparisons": len(cases)-nan_checks,
            "java_exact_bit_comparisons": len(cases)-nan_checks, "strictmath_exact_bit_comparisons": len(cases)-nan_checks if operation == "sqrt" else None,
            "nan_class_checks_each": nan_checks, "exact_squared_midpoint_interval_checks": sum(intervals.values()),
            "interval_outcomes": dict(intervals), "long_outcomes": dict(outcomes) if outcomes else None,
            "fixture_sha256": hashlib.sha256("\n".join(f"{kind}|{bits:016x}" for kind, bits in cases).encode()).hexdigest(),
            "native_wall_seconds_including_process_startup_and_io": native_elapsed, "total_wall_seconds": time.perf_counter()-started}


def sqrt_long_regression_smoke(binary: Path, seed: int) -> dict:
    all_cases = fixtures(seed, 256)
    edges = [case for case in all_cases if case[0] == "edge"]
    cases = [edges[index*len(edges)//128] for index in range(128)]
    cases += [case for case in all_cases if case[0] == "uniform_finite"]
    cases += [case for case in all_cases if case[0].startswith("division_")]
    for first in range(0, len(cases), 128):
        args = [f"regression|{a >> 32}|{a & 0xFFFFFFFF}|{b >> 32}|{b & 0xFFFFFFFF}|0" for _, a, b in cases[first:first+128]]
        rows = run([str(binary), "--gpu", "off", "--threads", "1", "--", *args]).stdout.splitlines()
        if len(rows) != len(args):
            raise AssertionError("Arithmetic regression row count mismatch")
        for (_, a, b), row in zip(cases[first:first+128], rows, strict=True):
            if [int(word) for word in row.split("|")[1:]] != expected(a, b):
                raise AssertionError(f"Existing arithmetic regression: {a:016x} {b:016x}")
    casts = narrowing_fixtures(seed, 0)[:256]
    for first in range(0, len(casts), 128):
        args = [f"narrow|{bits >> 32}|{bits & 0xFFFFFFFF}|0|0|0" for _, bits in casts[first:first+128]]
        rows = run([str(binary), "--gpu", "off", "--threads", "1", "--", *args]).stdout.splitlines()
        if len(rows) != len(args):
            raise AssertionError("Narrowing regression row count mismatch")
        for (_, bits), row in zip(casts[first:first+128], rows, strict=True):
            if int(row.split("|")[1]) != narrowing_expected(bits):
                raise AssertionError(f"Existing narrowing regression: {bits:016x}")
    return {"arithmetic_pair_cases": len(cases), "arithmetic_result_bit_comparisons": 4*len(cases),
            "classification_order_sign_relation_negation_abs_pairs": len(cases), "narrowing_bit_comparisons": len(casts),
            "scope": "bounded regression smoke; historical full arithmetic evidence remains separate"}


def sqrt_long_main(options) -> None:
    build = ROOT/"build"
    build.mkdir(exist_ok=True)
    binary, reference = build/"f64_sqrtlong_test", build/"f64_sqrtlong_reference"
    c_source, java_source = build/"f64_sqrtlong_reference.c", build/"F64SqrtLongReference.java"
    c_source.write_text(SQRT_LONG_C)
    java_source.write_text(SQRT_LONG_JAVA)
    commands = [[options.bend, "src/f64.bend", "--verdict"], [options.bend, "tests/f64.bend", "--verdict"],
                [options.bend, "tests/f64.bend", "-o", str(binary)], [options.bend, "tests/f64.bend", "-o", str(binary)+".c"],
                ["clang", "-O3", "-fno-fast-math", "-ffp-contract=off", str(c_source), "-o", str(reference)],
                [str(JAVA.parent/"javac"), "-d", str(build), str(java_source)]]
    timings, verdicts = {}, []
    for index, command in enumerate(commands):
        started = time.perf_counter()
        result = run(command)
        timings[str(index)] = time.perf_counter()-started
        if index < 2:
            if "ALL PROOFS CHECK" not in result.stdout:
                raise AssertionError(result.stdout)
            verdicts.append(result.stdout.strip())
    java_command = [str(JAVA), "-cp", str(build), "F64SqrtLongReference"]
    # The emitted implementation may use integer C operations, never hardware
    # floating sqrt/casts as a hidden simulation dependency.
    emitted = Path(str(binary)+".c").read_text()
    scalar_helpers = re.findall(r'(?ms)^INLINE Term spin_\d+\([^\n]+\) \{\n.*?^\}', emitted)
    scalar_text = "\n".join(scalar_helpers)
    if re.search(r"\b(?:sqrt|sqrtf|sqrtl)\s*\(", emitted) or re.search(r'\bdouble\b|f32_unbox|f32_rewrap', scalar_text):
        raise AssertionError("Emitted Bend implementation contains a host float operation")
    regressions = sqrt_long_regression_smoke(binary, options.seed)
    for operation in ("sqrt", "long"):
        result = check_sqrt_long(binary, reference, java_command, operation, options.seed, options.random)
        evidence = {"schema": 1, "result": "pass", "scope": f"targeted pure F64 {operation}; old arithmetic evidence preserved",
                    "verification_scope": "independent kernel type/termination validity plus finite laws and native oracle fixtures; no universal IEEE theorem",
                    "kernel_verdicts": dict(zip(("source", "tests"), verdicts, strict=True)), "build_wall_seconds": timings,
                    "seed": options.seed, "random_cases_requested": options.random, "regression_smoke": regressions,
                    "reproduce": ["python3", "tools/test_f64.py", "--sqrt-long-only", "--seed", str(options.seed), "--random", str(options.random)],
                    "policy": "RN-even; preserve signed zero/+infinity; quiet input NaN preserving payload/sign; negative nonzero -> positive canonical quiet NaN" if operation == "sqrt" else "Java signed64 narrowing: NaN0, truncate toward zero, saturate; output hi/lo two's-complement words",
                    "platform": {"system": platform.system(), "release": platform.release(), "machine": platform.machine()},
                    "compiler": run([options.bend, "version"]).stdout.strip(), "checks": result,
                    "compiler_file": fingerprint(Path(options.bend)), "native_binary": fingerprint(binary), "c_reference_binary": fingerprint(reference),
                    "emitted_c": {"sha256": hashlib.sha256(emitted.encode()).hexdigest(), "scalar_inline_helpers": len(scalar_helpers), "scalar_helpers_use_host_float_arithmetic": False, "host_sqrt_call_present": False},
                    "java_runtime": fingerprint(JAVA), "java_version": run([str(JAVA), "-version"]).stderr.strip(),
                    "reference_source_sha256": {"c": hashlib.sha256(SQRT_LONG_C.encode()).hexdigest(), "java": hashlib.sha256(SQRT_LONG_JAVA.encode()).hexdigest()},
                    "source_sha256": {path: hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for path in ("src/f64.bend", "tests/f64.bend", "tools/test_f64.py")},
                    "commands": commands+[[*java_command, operation], [str(reference), operation]],
                    "official_semantics": "https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/Math.html#sqrt(double)" if operation == "sqrt" else "https://docs.oracle.com/javase/specs/jls/se25/html/jls-5.html#jls-5.1.3"}
        destination = ROOT/f"evidence/f64-{operation}-oracle.json"
        destination.write_text(json.dumps(evidence, indent=2)+"\n")
        print(json.dumps({"evidence": str(destination), "checks": result}, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bend", default="/Users/chuah/.bend/bin/bend")
    parser.add_argument("--seed", type=int, default=640263)
    parser.add_argument("--random", type=int, default=20000)
    parser.add_argument("--iterations", type=int, default=1000000)
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--evidence", default="evidence/f64-oracle.json")
    parser.add_argument("--cast-only", action="store_true")
    parser.add_argument("--sqrt-long-only", action="store_true")
    parser.add_argument("--step-samples", type=Path)
    options = parser.parse_args()
    if options.random < 10000:
        raise ValueError("At least 10,000 random finite pairs are required")
    if options.sqrt_long_only:
        sqrt_long_main(options)
        return
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    binary, reference = build/"f64_test", build/"f64_reference"
    reference_source, emitted_c = build/"f64_reference.c", build/"f64_test.c"
    reference_source.write_text(REFERENCE_C)
    build_timings = {}
    def timed_build(label: str, command: list[str]):
        started = time.perf_counter()
        result = run(command)
        build_timings[label] = time.perf_counter()-started
        if "SOME PROOFS FAIL" in result.stdout:
            raise AssertionError(result.stdout)
        return result
    checked = timed_build("kernel", [options.bend, "src/f64.bend", "--verdict"])
    if "ALL PROOFS CHECK" not in checked.stdout:
        raise AssertionError(checked.stdout)
    timed_build("native_bend", [options.bend, "tests/f64.bend", "-o", "build/f64_test"])
    timed_build("emit_c", [options.bend, "tests/f64.bend", "-o", "build/f64_test.c"])
    timed_build("reference_c", ["clang", "-O3", "-fno-fast-math", "-ffp-contract=off", str(reference_source), "-o", str(reference)])
    narrowing = check_narrowing(binary, reference, options.seed, options.random, options.step_samples)
    if options.cast_only:
        destination = ROOT/("evidence/f64-cast-targeted.json" if options.evidence == "evidence/f64-oracle.json" else options.evidence)
        evidence = {"schema": 1, "result": "pass", "scope": "F64 to F32 targeted cast validation; arithmetic regressions recorded separately",
                    "kernel_verdict": checked.stdout.strip(), "build_wall_seconds": build_timings, "narrowing": narrowing,
                    "source_sha256": {path: hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for path in ("src/f64.bend", "tests/f64.bend", "tools/test_f64.py")}}
        destination.write_text(json.dumps(evidence, indent=2)+"\n")
        print(json.dumps(evidence, indent=2))
        return
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
        "narrowing": narrowing,
        "build_wall_seconds": build_timings,
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
