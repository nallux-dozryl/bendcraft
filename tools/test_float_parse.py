#!/usr/bin/env python3
"""Exact direct decimal/F32 fixtures, independently observed in Java and C."""
from __future__ import annotations
import argparse
from collections import Counter
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import platform
import random
import re
import subprocess
import time

from reference_inventory import JAVA, fingerprint

ROOT = Path(__file__).resolve().parents[1]
SIGN = 1 << 31
INFINITY = 0x7F800000
GRAMMAR = re.compile(r"(-?)(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?\Z", re.ASCII)

REFERENCE_C = r'''
#define _POSIX_C_SOURCE 200809L
#include <fenv.h>
#include <float.h>
#include <inttypes.h>
#include <locale.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(void) {
  if(sizeof(float)!=4 || FLT_RADIX!=2 || FLT_MANT_DIG!=24 || setlocale(LC_NUMERIC,"C")==NULL || fesetround(FE_TONEAREST)!=0) return 2;
  char *line=NULL; size_t capacity=0; ssize_t size;
  while((size=getline(&line,&capacity,stdin))!=-1) {
    if(size && line[size-1]=='\n') line[--size]=0;
    char *end; float value=strtof(line,&end); uint32_t bits; memcpy(&bits,&value,4);
    if(end==line || *end!=0) puts("error"); else printf("%08" PRIx32 "\n",bits);
  }
  free(line); return 0;
}
'''

REFERENCE_JAVA = r'''
import java.io.*;
public class DecimalF32Reference {
  public static void main(String[] args) throws Exception {
    BufferedReader input=new BufferedReader(new InputStreamReader(System.in));
    PrintWriter output=new PrintWriter(System.out); String line;
    while((line=input.readLine())!=null) {
      try { output.println(Integer.toUnsignedString(Float.floatToRawIntBits(Float.parseFloat(line)),16)); }
      catch(NumberFormatException bad) { output.println("error"); }
    }
    output.flush(); if(output.checkError()) throw new IOException("Decimal observation failed");
  }
}
'''


def run(command: list[str], stdin: str | None = None, timeout: int = 180) -> subprocess.CompletedProcess:
    result = subprocess.run(command, cwd=ROOT, input=stdin, text=True, capture_output=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"Command failed: {command[:6]}\n{result.stdout[:2000]}\n{result.stderr[:2000]}")
    return result


def exact_f32(word: int) -> Fraction:
    """Positive finite payload; infinity is represented by virtual 2^128."""
    if word == INFINITY:
        return Fraction(1 << 128)
    exponent, mantissa = word >> 23, word & 0x7FFFFF
    if exponent:
        mantissa |= 1 << 23
    power = exponent-150 if exponent else -149
    return Fraction(mantissa << power) if power >= 0 else Fraction(mantissa, 1 << -power)


def decimal_text(value: Fraction) -> str:
    """Emit a dyadic/decimal rational exactly, without host float conversion."""
    sign = "-" if value < 0 else ""
    numerator, denominator = abs(value.numerator), value.denominator
    twos = fives = 0
    while denominator % 2 == 0:
        denominator //= 2
        twos += 1
    while denominator % 5 == 0:
        denominator //= 5
        fives += 1
    assert denominator == 1
    places = max(twos, fives)
    digits = str(numerator*(2**(places-twos))*(5**(places-fives)))
    if places:
        digits = digits.zfill(places+1)
        digits = digits[:-places]+"."+digits[-places:]
    return sign+digits


def exact_decimal(text: str) -> tuple[bool, Fraction | str]:
    match = GRAMMAR.fullmatch(text)
    if not match:
        raise AssertionError(f"Oracle received invalid JSON decimal: {text!r}")
    sign, whole, fraction, exponent = match.groups()
    fraction = fraction or ""
    digits = (whole+fraction).lstrip("0")
    if not digits:
        return bool(sign), Fraction(0)
    power = int(exponent or "0")-len(fraction)
    adjusted = power+len(digits)-1
    if adjusted > 38:
        return bool(sign), "overflow"
    if adjusted < -46:
        return bool(sign), "underflow"
    numerator = int(digits)
    value = Fraction(numerator*(10**power)) if power >= 0 else Fraction(numerator, 10**-power)
    return bool(sign), value


def round_fraction(value: Fraction) -> int:
    """Independent quotient/remainder rounding, not payload midpoint search."""
    if not value:
        return 0
    numerator, denominator = value.numerator, value.denominator
    exponent = numerator.bit_length()-denominator.bit_length()
    if (numerator < denominator << exponent) if exponent >= 0 else (numerator << -exponent < denominator):
        exponent -= 1
    quantum = -149 if exponent < -126 else exponent-23
    scaled_numerator, scaled_denominator = (numerator << -quantum, denominator) if quantum < 0 else (numerator, denominator << quantum)
    retained, remainder = divmod(scaled_numerator, scaled_denominator)
    if 2*remainder > scaled_denominator or (2*remainder == scaled_denominator and retained & 1):
        retained += 1
    if exponent < -126:
        return retained
    if retained == 1 << 24:
        retained >>= 1
        exponent += 1
    if exponent > 127:
        return INFINITY
    return ((exponent+127) << 23)|(retained & 0x7FFFFF)


def expected(text: str) -> int:
    negative, value = exact_decimal(text)
    word = INFINITY if value == "overflow" else 0 if value == "underflow" else round_fraction(value)
    return word|(SIGN if negative else 0)


def interval_check(text: str, result: int) -> str:
    _, value = exact_decimal(text)
    word = result & ~SIGN
    if isinstance(value, str):
        return value+"_decimal_exponent_bound"
    if word == 0:
        if value > exact_f32(1)/2:
            raise AssertionError("Incorrect zero rounding interval")
        return "half_minimum_tie" if value == exact_f32(1)/2 else "zero"
    if word == INFINITY:
        boundary = (exact_f32(INFINITY-1)+exact_f32(INFINITY))/2
        if value < boundary:
            raise AssertionError("Incorrect infinity rounding interval")
        return "overflow_tie" if value == boundary else "overflow"
    center = exact_f32(word)
    low = (exact_f32(word-1)+center)/2
    high = (center+exact_f32(word+1))/2
    if value < low or value > high or ((value == low or value == high) and word & 1):
        raise AssertionError(f"Incorrect exact midpoint interval: {text!r} -> {result:08x}")
    return "midpoint_tie" if value in (low, high) else "exact" if value == center else "rounded"


def fixtures(seed: int, random_count: int) -> list[tuple[str, str]]:
    cases = [("supplied_model", text) for text in ("0.1", "-0.0", "0.10000000149011612", "1e-45", "1.000000059604644775390625", "1.0000000596046449", "1e40")]
    rng = random.Random(seed)
    words = {0, 1, 2, 3, 0x7FFFFE, 0x7FFFFF, 0x800000, INFINITY-2, INFINITY-1}
    for exponent in range(1, 255):
        words.update((exponent << 23)|mantissa for mantissa in (0, 1, 2, 0x7FFFFE, 0x7FFFFF))
    for word in sorted(words):
        midpoint = (exact_f32(word)+exact_f32(word+1))/2
        places = len(decimal_text(midpoint).split(".")[1]) if "." in decimal_text(midpoint) else 0
        epsilon = Fraction(1, 10**(places+20))
        for sign in (1, -1):
            cases.append(("exact_f32_roundtrip", decimal_text(sign*exact_f32(word))))
            cases.extend(("all_exponent_midpoint_neighbors", decimal_text(sign*(midpoint+delta*epsilon))) for delta in (-1, 0, 1))
    for _ in range(random_count):
        size = rng.randrange(1, 257)
        digits = str(rng.randrange(1, 10))+"".join(str(rng.randrange(10)) for _ in range(size-1))
        sign = rng.choice(("", "-"))
        point = rng.randrange(size+1)
        mantissa = "0."+digits if point == 0 else digits if point == size else digits[:point]+"."+digits[point:]
        exponent = rng.randrange(-46, 39)-(point or 0)+1
        cases.append(("random_decimal", f"{sign}{mantissa}e{exponent:+d}"))
    for size in (511, 512, 1023, 1024):
        for _ in range(16):
            digits = str(rng.randrange(1, 10))+"".join(str(rng.randrange(10)) for _ in range(size-1))
            cases.append(("long_mantissa", f"{rng.choice(('', '-'))}{digits}e{rng.randrange(-46, 39)-size+1}"))
    for zeros in (1, 20, 500, 1000):
        for negative in ("", "-"):
            cases.extend(("huge_exponent", f"{negative}1e{sign}{'9'*zeros}") for sign in ("+", "-"))
            cases.append(("zero_huge_exponent", f"{negative}0.0e{'9'*zeros}"))
    cases.extend(("budget_boundary", text) for text in ("1"+"0"*1023+"e-1023", "0."+"0"*1021+"1", "1e"+"0"*4093+"1", "-0e"+"9"*4093))
    # Tails smaller than an F64 ulp produce real decimal->F64->F32 double
    # rounding failures. Direct F32 parsing must preserve the midpoint side.
    tie = Fraction(1)+Fraction(1, 1 << 24)
    for digits in (30, 100, 500, 1000):
        for sign in (1, -1):
            cases.append(("f64_double_rounding_trap", decimal_text(sign*(tie+Fraction(1, 10**digits)))))
            cases.append(("f64_double_rounding_trap", decimal_text(sign*(tie-Fraction(1, 10**digits)))))
    return cases


def invalid_fixtures() -> list[tuple[str, str]]:
    invalid = ("", "-", "+1", ".5", "5.", "01", "-01", "00", "1.e1", "1e", "1e+", "1e-", "1e++1", "1e--1", "1e1.0", "1 2", " 1", "1 ", "\t1", "1\n", "1\r", "1_0", "NaN", "Infinity", "-Infinity", "0x1p0", "1f", "1d", "１", "١", "1,2", "--1", "1E+2x", "@nul", "@surrogate")
    cases = [(text, "InvalidDecimal") for text in invalid]
    cases.extend((("1"+"0"*1024, "DigitLimit"), ("0."+"0"*1024, "DigitLimit"), ("1e"+"0"*4094+"1", "InputLimit"), ("0"*4097, "InputLimit")))
    return cases


def batches(cases, maximum_count: int = 128, maximum_characters: int = 48000):
    batch, characters = [], 0
    for case in cases:
        text = case[1]
        if batch and (len(batch) == maximum_count or characters+len(text) > maximum_characters):
            yield batch
            batch, characters = [], 0
        batch.append(case)
        characters += len(text)
    if batch:
        yield batch


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bend", default="/Users/chuah/.bend/bin/bend")
    parser.add_argument("--seed", type=int, default=322603)
    parser.add_argument("--random", type=int, default=10000)
    parser.add_argument("--evidence", default="evidence/float-parse-native.json")
    options = parser.parse_args()
    if options.random < 1000:
        raise ValueError("At least 1000 random decimal fixtures are required")
    build = ROOT/"build"
    build.mkdir(exist_ok=True)
    binary, reference = build/"float_parse_test", build/"float_parse_reference"
    source, java_source = build/"float_parse_reference.c", build/"DecimalF32Reference.java"
    source.write_text(REFERENCE_C)
    java_source.write_text(REFERENCE_JAVA)
    commands = [[options.bend, "src/big_uint.bend", "--verdict"], [options.bend, "src/float_parse.bend", "--verdict"], [options.bend, "tests/float_parse.bend", "--verdict"],
                [options.bend, "tests/float_parse.bend", "-o", str(binary)], [options.bend, "tests/float_parse.bend", "-o", str(binary)+".c"],
                ["clang", "-O3", "-fno-fast-math", "-ffp-contract=off", str(source), "-o", str(reference)],
                [str(JAVA.parent/"javac"), "-d", str(build), str(java_source)]]
    timings, verdicts = {}, {}
    for index, command in enumerate(commands):
        started = time.perf_counter()
        result = run(command)
        timings[str(index)] = time.perf_counter()-started
        if index < 3:
            if "ALL PROOFS CHECK" not in result.stdout:
                raise AssertionError(result.stdout)
            verdicts[command[1]] = result.stdout.strip()
    cases = fixtures(options.seed, options.random)
    expected_rows = [expected(text) for _, text in cases]
    payload = "".join(text+"\n" for _, text in cases)
    java_command = [str(JAVA), "-cp", str(build), "DecimalF32Reference"]
    c_rows, java_rows = run([str(reference)], payload).stdout.splitlines(), run(java_command, payload).stdout.splitlines()
    if len(c_rows) != len(cases) or len(java_rows) != len(cases):
        raise AssertionError("Oracle row count mismatch")
    for (kind, text), result, c, java in zip(cases, expected_rows, c_rows, java_rows, strict=True):
        if c == "error" or java == "error" or int(c, 16) != result or int(java, 16) != result:
            raise AssertionError(f"C/Java/exact oracle mismatch {kind} {text!r}: exact{result:08x}, C{c}, Java{java}")
    started = time.perf_counter()
    for batch in batches(list(enumerate(text for _, text in cases))):
        rows = run([str(binary), "--gpu", "off", "--threads", "1", "--", *(text for _, text in batch)]).stdout.splitlines()
        if len(rows) != len(batch):
            raise AssertionError("Native row count mismatch")
        for (index, text), row in zip(batch, rows, strict=True):
            if row != f"ok|{expected_rows[index]}":
                raise AssertionError(f"Native exact parse mismatch {cases[index][0]} {text!r}: expected {expected_rows[index]:08x}, observed {row}")
    native_wall = time.perf_counter()-started
    invalid = invalid_fixtures()
    invalid_rows = run([str(binary), "--gpu", "off", "--threads", "1", "--", *(text for text, _ in invalid)]).stdout.splitlines()
    if len(invalid_rows) != len(invalid):
        raise AssertionError("Invalid fixture row count mismatch")
    for (text, error), row in zip(invalid, invalid_rows, strict=True):
        if row != "error|"+error:
            raise AssertionError(f"Expected explicit error {error} for {text!r}; observed {row}")
    intervals = Counter(interval_check(text, result) for (_, text), result in zip(cases, expected_rows, strict=True))
    exponent_bound_checks = sum(count for outcome, count in intervals.items() if outcome.endswith("_decimal_exponent_bound"))
    emitted = Path(str(binary)+".c").read_text()
    helpers = re.findall(r'(?ms)^INLINE Term spin_\d+\([^\n]+\) \{\n.*?^\}', emitted)
    if re.search(r'\bdouble\b|f32_unbox|f32_rewrap', "\n".join(helpers)):
        raise AssertionError("Parser scalar helpers unexpectedly use host floating arithmetic")
    observed_model = ROOT/"reference/model_semantics.json"
    model_checks = []
    if observed_model.exists():
        model = json.loads(observed_model.read_text())
        inputs = {row["id"]: row for row in model["inputs"]["parse_cases"]}
        observations = {row["id"]: row for row in model["observations"]["parse_cases"]}
        for case_id in ("raw_json_94", "raw_json_95"):
            raw = json.loads(inputs[case_id]["json"], parse_float=str, parse_int=str)
            actual = observations[case_id]["parsed"]["geometry"]["elements"][0]
            lexemes = raw["elements"][0]["from"] if case_id == "raw_json_94" else raw["elements"][0]["faces"]["north"]["uv"]
            bits = actual["from"] if case_id == "raw_json_94" else [actual["faces"]["north"]["uvs"][key] for key in ("minU", "minV", "maxU", "maxV")]
            for text, word in zip(lexemes, bits, strict=True):
                if expected(text) != int(word, 16):
                    raise AssertionError(f"Observed production model scalar mismatch {case_id}: {text}")
                model_checks.append({"case_id": case_id, "lexeme": text, "observed_f32_bits": word})
    evidence = {"schema": 1, "result": "pass", "scope": "strict JSON decimal token -> direct RN-even F32, no Java textual-coercion grammar claim",
                "grammar": "-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?", "budgets": {"codepoints": 4096, "mantissa_digits": 1024, "exponent_scan_saturation": 100000, "maximum_rounding_comparisons": 31, "integer_capacity_bound_bits": 4096},
                "seed": options.seed, "random_cases_requested": options.random, "accepted_cases": len(cases), "native_exact_bit_comparisons": len(cases), "java25_exact_bit_comparisons": len(cases), "c_strtof_exact_bit_comparisons": len(cases),
                "fixture_kinds": dict(Counter(kind for kind, _ in cases)), "invalid_cases": len(invalid), "error_counts": dict(Counter(error for _, error in invalid)),
                "exact_rational_rounding_interval_checks": len(cases)-exponent_bound_checks, "decimal_exponent_bound_checks": exponent_bound_checks,
                "interval_outcomes": dict(intervals), "native_wall_seconds_including_startup_argument_and_output_io": native_wall,
                "kernel_verdicts": verdicts, "verification_scope": "independent type/termination checks plus finite grammar/zero laws and independent native/exact fixtures; no universal decimal-rounding theorem",
                "fixture_sha256": hashlib.sha256("\n".join(f"{kind}|{text}" for kind, text in cases).encode()).hexdigest(), "invalid_fixture_sha256": hashlib.sha256(json.dumps(invalid).encode()).hexdigest(),
                "source_sha256": {path: hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for path in ("src/big_uint.bend", "src/float_parse.bend", "tests/float_parse.bend", "tools/test_float_parse.py")},
                "reference_sha256": {"c": hashlib.sha256(REFERENCE_C.encode()).hexdigest(), "java": hashlib.sha256(REFERENCE_JAVA.encode()).hexdigest()}, "compiler": run([options.bend, "version"]).stdout.strip(), "compiler_file": fingerprint(Path(options.bend)),
                "java_runtime": fingerprint(JAVA), "java_version": run([str(JAVA), "-version"]).stderr.strip(), "native_binary": fingerprint(binary), "reference_binary": fingerprint(reference),
                "emitted_c": {"sha256": hashlib.sha256(emitted.encode()).hexdigest(), "scalar_inline_helpers": len(helpers), "scalar_helpers_use_host_float_arithmetic": False},
                "platform": {"system": platform.system(), "release": platform.release(), "machine": platform.machine()}, "build_wall_seconds": timings,
                "model_reference": {"file": "reference/model_semantics.json", "sha256": hashlib.sha256(observed_model.read_bytes()).hexdigest(), "checks": model_checks, "scope": "observed scalar lexemes only; not model-field policy or gameplay parity"} if observed_model.exists() else None,
                "commands": commands+[java_command, [str(reference)]], "reproduce": ["python3", "tools/test_float_parse.py", "--seed", str(options.seed), "--random", str(options.random)],
                "official_sources": ["https://www.rfc-editor.org/rfc/rfc8259#section-6", "https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/Float.html#valueOf(java.lang.String)"]}
    destination = ROOT/options.evidence
    destination.write_text(json.dumps(evidence, indent=2)+"\n")
    print(json.dumps({"evidence": str(destination), "accepted_cases": len(cases), "invalid_cases": len(invalid), "fixtures": evidence["fixture_kinds"], "intervals": dict(intervals), "native_wall_seconds_including_io": native_wall}, indent=2))


if __name__ == "__main__":
    main()
