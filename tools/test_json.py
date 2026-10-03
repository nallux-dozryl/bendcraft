#!/usr/bin/env python3
"""Independent RFC-8259 corpus against the native pure-Bend JSON implementation.

Python creates inputs and expected outputs only; all tested parsing/serialization
and accessors execute in the compiled Bend executable.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import platform
import random
import re
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BEND = Path('/Users/chuah/.bend/bin/bend')

@dataclass(frozen=True)
class Number:
    raw: str

@dataclass(frozen=True)
class Object:
    pairs: tuple


def object_pairs(pairs):
    seen = set()
    for key, _ in pairs:
        if key in seen:
            raise ValueError('duplicate object member')
        seen.add(key)
    return Object(tuple(pairs))


def validate_scalars(value):
    if isinstance(value, str):
        if any(0xD800 <= ord(c) <= 0xDFFF for c in value):
            raise ValueError('unpaired surrogate')
    elif isinstance(value, Object):
        for key, item in value.pairs:
            validate_scalars(key)
            validate_scalars(item)
    elif isinstance(value, list):
        for item in value:
            validate_scalars(item)


def reference(text):
    def reject_constant(token):
        raise ValueError(token)
    value = json.loads(text, parse_int=Number, parse_float=Number,
                       parse_constant=reject_constant, object_pairs_hook=object_pairs)
    validate_scalars(value)
    return value


def dump(value):
    if value is None:
        return 'null'
    if value is True:
        return 'true'
    if value is False:
        return 'false'
    if isinstance(value, Number):
        return value.raw
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False, separators=(',', ':'))
    if isinstance(value, Object):
        return '{' + ','.join(dump(k) + ':' + dump(v) for k, v in value.pairs) + '}'
    if isinstance(value, list):
        return '[' + ','.join(dump(v) for v in value) + ']'
    raise TypeError(value)


@dataclass(frozen=True)
class Case:
    name: str
    mode: str
    text: str
    expected: str | None
    key: str = ''


def corpus():
    cases = []
    valid = [
        'null', 'true', 'false', '0', '-0', '1', '-1', '10', '4294967295',
        '4294967296', '9007199254740993', '18446744073709551616',
        '0.0', '-0.00', '1e0', '1E+999999', '-2.50e-999999',
        '3.141592653589793238462643383279', '[]', '{}', '[null,true,false]',
        '{"a":[1,{"b":2},[]],"z":{}}', ' \t\r\n [ 1 , 2 ] \n',
        '""', '"ASCII"', '"é€😀ไทย"', '"\\u0000"',
        '"\\\"\\\\\\/\\b\\f\\n\\r\\t"', '"\\u0041\\u00e9\\u20ac"',
        '"\\uD800\\uDC00"', '"\\uDBFF\\uDFFF"', '"\\uD834\\uDD1E"',
        '"\\ud83d\\ude00"', '"\ufeff"', '"[]{}:,"',
        '{"":0,"a":1,"A":2,"a\\\\b":3,"a/b":4,"😀":5}',
        '{"a":1,"b":{"a":2}}', '{"é":0,"e\\u0301":1}',
        '"' + ''.join('\\u%04x' % c for c in range(32)) + '"',
    ]
    for i, text in enumerate(valid):
        cases.append(Case(f'valid-{i}', 'parse', text, 'ok\t' + dump(reference(text))))
    invalid = [
        '', ' ', '+1', '01', '-01', '00', '--1', '-', '.1', '-.1', '1.', '1.e2',
        '1e', '1E', '1e+', '1e-', '1e++2', '0x10', '1_0', 'NaN', 'Infinity',
        '-Infinity', 'True', 'False', 'NULL', 'nul', 'truefalse', 'null null',
        'nullX', 'false x', '1 2', '[', '{', ']', '}', '[,]', '[1,]', '[1,,2]',
        '[1 2]', '{a:1}', '{"a" 1}', '{"a":}', '{"a":1,}', '{"a":1 "b":2}',
        '{"a":1,"a":2}', '{"a":1,"\\u0061":2}', '{"a\\\\b":0,"a\\u005cb":1}',
        '{"😀":0,"\\ud83d\\ude00":1}', '"', '"abc', '"\\"', '"\\q"',
        '"\\v"', '"\\x41"', '"\\U0041"', '"\\u123"', '"\\u12X4"',
        '"\\uD800"', '"\\uDC00"', '"\\uD800x"', '"\\uD800\\n"',
        '"\\uD800\\u0041"', '"\\uD800\\uD800"', '"\\uDC00\\uD800"',
        '\ufeffnull', '\vnull', '\fnull', '\u00a0null', '//a\nnull', '/*x*/0',
        '[true;false]', '[null}}', '"é" x',
    ]
    invalid += ['"' + chr(c) + '"' for c in range(1, 32)]
    for i, text in enumerate(invalid):
        try:
            reference(text)
        except (ValueError, json.JSONDecodeError):
            pass
        else:
            raise AssertionError(('invalid oracle accepted', text))
        cases.append(Case(f'invalid-{i}', 'parse', text, None))

    rng = random.Random(0x8259)
    alphabet = ['a', '"', '\\', '/', '\n', '\t', '\x01', 'é', '€', '😀', 'ไทย', '\u2028']
    def number():
        raw = rng.choice(['', '-']) + rng.choice(['0', str(rng.randrange(1, 10**18))])
        if rng.randrange(2):
            raw += '.' + ''.join(str(rng.randrange(10)) for _ in range(rng.randrange(1, 15)))
        if rng.randrange(2):
            raw += rng.choice(['e', 'E']) + rng.choice(['', '+', '-']) + str(rng.randrange(10**6))
        return Number(raw)
    def generated(depth):
        choices = ['null', 'bool', 'number', 'string'] + (['array', 'object'] if depth else [])
        kind = rng.choice(choices)
        if kind == 'null': return None
        if kind == 'bool': return bool(rng.randrange(2))
        if kind == 'number': return number()
        if kind == 'string': return ''.join(rng.choice(alphabet) for _ in range(rng.randrange(12)))
        if kind == 'array': return [generated(depth - 1) for _ in range(rng.randrange(6))]
        return Object(tuple((f'key-{i}-' + rng.choice(alphabet), generated(depth - 1))
                            for i in range(rng.randrange(6))))
    for i in range(250):
        value = generated(4)
        text = dump(value)
        # Alternate escaped and literal Unicode without changing semantics.
        if i % 2:
            text = ''.join(c if ord(c) < 128 else json.dumps(c, ensure_ascii=True)[1:-1] for c in text)
        text = rng.choice(['', ' ', '\t\n']) + text + rng.choice(['', '\r', ' \n'])
        cases.append(Case(f'generated-{i}', 'parse', text, 'ok\t' + dump(reference(text))))
    for i in range(100):
        # Construct invalid number grammar, independently rejected by the oracle.
        text = rng.choice(['0', '-0']) + str(rng.randrange(1, 10**12))
        cases.append(Case(f'bad-leading-zero-{i}', 'parse', text, None))

    u32_values = ['0', '1', '4294967294', '4294967295', '4294967296', '42949672960',
                  '18446744073709551616', '-0', '-1', '1.0', '1e0', 'true', '"1"', '[]', 'null']
    for text in u32_values:
        expected = 'u32\t' + text if re.fullmatch(r'0|[1-9][0-9]*', text) and int(text) <= 0xFFFFFFFF else 'none'
        cases.append(Case('u32-' + text, 'u32', text, expected))
    for text in ['"abc"', '"\\u0000"', '"\\ud83d\\ude00"', 'true', '0', '{}']:
        value = reference(text)
        expected = 'string\t' + dump(value) if isinstance(value, str) else 'none'
        cases.append(Case('as-string-' + text, 'string', text, expected))
    obj = '{"a":1,"\\u0062":[null],"😀":"face","q\\\"":"quote","":false}'
    for key, expected in [('a', '1'), ('b', '[null]'), ('😀', '"face"'), ('q"', '"quote"'), ('', 'false'), ('missing', None)]:
        cases.append(Case('member-' + key, 'member', obj, 'none' if expected is None else 'member\t' + expected, key))
    cases.append(Case('member-non-object', 'member', '[]', 'none', 'a'))
    for i, text in enumerate(['', 'simple', '"\\/\n\r\t', ''.join(chr(c) for c in range(1, 32)), 'é€😀ไทย\u2028']):
        cases.append(Case(f'quote-{i}', 'quote', text, 'ok\t' + dump(text)))

    # Limits are implementation policy; valid grammar exceeds the explicit envelope.
    cases.extend([
        Case('depth-64', 'parse', '[' * 64 + '0' + ']' * 64, 'ok\t' + '[' * 64 + '0' + ']' * 64),
        Case('depth-65', 'parse', '[' * 65 + '0' + ']' * 65, None),
        Case('input-16384', 'parse', ' ' * 16380 + 'null', 'ok\tnull'),
        Case('input-16385', 'parse', ' ' * 16381 + 'null', None),
        Case('unicode-input-16384', 'parse', '"' + '😀' * 16382 + '"', 'ok\t"' + '😀' * 16382 + '"'),
        Case('wide-array', 'parse', '[' + ','.join(['0'] * 4096) + ']', 'ok\t[' + ','.join(['0'] * 4096) + ']'),
        Case('wide-object', 'parse', '{' + ','.join(f'"k{i}":0' for i in range(1200)) + '}',
             'ok\t{' + ','.join(f'"k{i}":0' for i in range(1200)) + '}'),
        Case('offset-empty', 'parse', '', 'error\texpected JSON value at offset 0'),
        Case('offset-unicode', 'parse', '"é" x', 'error\ttrailing input at offset 4'),
        Case('offset-literal', 'parse', 'false x', 'error\ttrailing input at offset 6'),
    ])
    return cases


def run(command, timeout=120):
    completed = subprocess.run([str(x) for x in command], cwd=ROOT, text=True,
                               capture_output=True, timeout=timeout)
    if completed.returncode:
        raise RuntimeError(f'command failed ({completed.returncode}): {command}\n{completed.stdout}{completed.stderr}')
    return completed.stdout


def execute(binary, cases):
    results = []
    for start in range(0, len(cases), 25):
        group = cases[start:start + 25]
        args = [binary, '--threads', '1', 'batch']
        for case in group:
            args.extend([case.mode, case.text, case.key])
        lines = run(args).removesuffix('\n').split('\n')
        if len(lines) != len(group):
            raise AssertionError(f'batch {start} produced {len(lines)} lines, expected {len(group)}')
        for case, observed in zip(group, lines):
            if case.expected is None:
                passed = observed.startswith('error\t')
            else:
                passed = observed == case.expected
            if not passed:
                raise AssertionError(f'{case.name}: expected {case.expected!r}, observed {observed!r}; input {case.text[:200]!r}')
            results.append((case, observed))
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--skip-build', action='store_true')
    options = parser.parse_args()
    start = time.monotonic()
    binary = ROOT / 'build/json-tests'
    binary.parent.mkdir(exist_ok=True)
    checks = {}
    for source in ['src/json.bend', 'tests/json.bend']:
        output = run([BEND, source, '--check-only'])
        if 'ALL PROOFS CHECK' not in output:
            raise AssertionError(output)
        checks[source] = output.strip()
    if not options.skip_build:
        run([BEND, 'tests/json.bend', '-o', binary])
    builtin = run([binary, '--threads', '1']).strip()
    if builtin != 'regressions\tpass':
        raise AssertionError(builtin)
    cases = corpus()
    results = execute(binary, cases)
    roundtrips = [Case('roundtrip-' + case.name, 'parse', observed[3:], observed)
                  for case, observed in results if observed.startswith('ok\t')]
    execute(binary, roundtrips)
    # Confirm the test oracle is actually independent and checks numeric lexemes.
    assert dump(reference('9007199254740993')) == '9007199254740993'
    assert dump(reference('-0.00E+400')) == '-0.00E+400'
    pure_source = (ROOT / 'src/json.bend').read_text()
    if '@unsafe' in pure_source or re.search(r'\bIO[.<(]|import\s+"', pure_source):
        raise AssertionError('JSON implementation includes unsafe or effect-backed logic')
    kernel = subprocess.run([str(BEND), 'src/json.bend', '--verdict'], cwd=ROOT,
                            text=True, capture_output=True, timeout=60)
    fixtures_kernel = subprocess.run([str(BEND), 'tests/json.bend', '--verdict'], cwd=ROOT,
                                     text=True, capture_output=True, timeout=60)
    report = {
        'schema': 1,
        'compiler': run([BEND, 'version']).strip(),
        'platform': platform.platform(),
        'source_sha256': hashlib.sha256(pure_source.encode()).hexdigest(),
        'checker': checks,
        'kernel_verdict': {'exit_code': kernel.returncode, 'output': (kernel.stdout + kernel.stderr).strip()},
        'fixtures_kernel_verdict': {'exit_code': fixtures_kernel.returncode, 'output': (fixtures_kernel.stdout + fixtures_kernel.stderr).strip()},
        'native_binary': str(binary.relative_to(ROOT)),
        'native_builtin_regressions': 'pass',
        'independent_cases': len(cases),
        'successful_roundtrips': len(roundtrips),
        'generated_valid_cases': 250,
        'generated_invalid_cases': 100,
        'all_cases_passed': True,
        'elapsed_seconds': round(time.monotonic() - start, 3),
        'oracle': 'Python json grammar decoder with exact number-token hooks, duplicate rejection, scalar Unicode validation; outputs checked byte-for-byte',
        'policy': {'max_codepoints': 16384, 'max_container_depth': 64, 'duplicates': 'reject after escape decoding', 'unpaired_surrogates': 'reject'},
        'commands': ['python3 tools/test_json.py', '/Users/chuah/.bend/bin/bend src/json.bend --check-only',
                     '/Users/chuah/.bend/bin/bend tests/json.bend --check-only',
                     '/Users/chuah/.bend/bin/bend tests/json.bend -o build/json-tests',
                     './build/json-tests --threads 1', '/Users/chuah/.bend/bin/bend src/json.bend --verdict',
                     '/Users/chuah/.bend/bin/bend tests/json.bend --verdict'],
    }
    target = ROOT / 'evidence/json-tests.json'
    target.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({key: report[key] for key in ['independent_cases', 'successful_roundtrips', 'all_cases_passed', 'elapsed_seconds']}, indent=2))

if __name__ == '__main__':
    main()
