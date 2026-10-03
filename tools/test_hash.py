#!/usr/bin/env python3
"""Compare native pure Bend SHA-256 to NIST examples and independent providers.

This script generates byte fixtures and orchestrates tests. Runtime hashing is
performed entirely by src/hash.bend. OpenSSL and Python are test oracles only.
"""
from __future__ import annotations
import _sha2
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import random
import re
import ssl
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
BEND = Path('/Users/chuah/.bend/bin/bend')
BINARY = ROOT / 'build/hash-tests'
WORK = ROOT / 'build/hash-oracle'
EVIDENCE = ROOT / 'evidence/hash-verification.json'
NAT_MAX = (1 << 48) - 1
SEED = 263_180_4
FIPS = 'https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf'
EXAMPLES = 'https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Standards-and-Guidelines/documents/examples/SHA256.pdf'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(argv, *, payload=None, required=True, timeout=180):
    start = time.monotonic()
    process = subprocess.run([str(x) for x in argv], cwd=ROOT, input=payload,
                             capture_output=True, timeout=timeout)
    result = {'command': [str(x) for x in argv], 'exit_code': process.returncode,
              'seconds': round(time.monotonic() - start, 6),
              'stdout': process.stdout.decode(errors='replace'),
              'stderr': process.stderr.decode(errors='replace')}
    if required and process.returncode:
        raise RuntimeError(json.dumps(result, indent=2))
    return result, process.stdout


def oracle(data):
    expected = hashlib.sha256(data).hexdigest()
    portable = _sha2.sha256(data).hexdigest()
    _, openssl = run(['openssl', 'dgst', '-sha256', '-binary'], payload=data)
    assert expected == portable == openssl.hex()
    return expected


def expected_digest(data):
    digest = oracle(data)
    return ('digest', digest, bytes.fromhex(digest))


def decode_observation(line):
    name, kind, *fields = line.split('|')
    if kind == 'digest':
        assert len(fields) == 2 and re.fullmatch('[0-9a-f]{64}', fields[0])
        values = bytes(map(int, fields[1].split(',')))
        assert len(values) == 32
        return name, (kind, fields[0], values)
    if kind == 'error':
        return name, (kind, fields[0])
    if kind == 'length':
        return name, (kind, bytes(map(int, fields[0].split(','))))
    if kind == 'rotate':
        return name, (kind, int(fields[0]))
    raise AssertionError(line)


def execute(cases, records, lane):
    chunks = []; current = []; size = 0
    for case in cases:
        if current and (size + len(case[1]) > 120000 or len(current) >= 80):
            chunks.append(current); current = []; size = 0
        current.append(case); size += len(case[1])
    if current:
        chunks.append(current)
    for index, chunk in enumerate(chunks):
        result, _ = run([BINARY, '--gpu', 'off', *[query for _, query, _ in chunk]])
        records.append({'lane': lane, 'batch': index, 'count': len(chunk),
                        'seconds': result['seconds'], 'exit_code': result['exit_code']})
        lines = result['stdout'].splitlines()
        assert len(lines) == len(chunk), result
        for (name, _, expected), line in zip(chunk, lines, strict=True):
            observed_name, observed = decode_observation(line)
            assert observed_name == name and observed == expected, (name, expected, observed)


def fixture_cases():
    rng = random.Random(SEED); cases = []; counts = Counter(); digest = hashlib.sha256()
    def add(name, data, tag, limit=None):
        expected = expected_digest(data)
        query = '|'.join([name, 'hex', str(len(data) if limit is None else limit), data.hex()])
        cases.append((name, query, expected)); counts[tag] += 1
        digest.update(name.encode() + b'\0' + data)
    examples = [
        ('nist-one-block', b'abc', 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'),
        ('nist-two-block', b'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
         '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1')]
    for name, data, fixed in examples:
        assert oracle(data) == fixed
        add(name, data, 'nist-published')
    add('empty', b'', 'empty', limit=0)
    add('abc-native-max-budget', b'abc', 'native-max-budget', limit=NAT_MAX)
    for value in range(256):
        add(f'octet-{value}', bytes([value]), 'all-single-bytes')
    for length in range(257):
        for pattern in range(4):
            data = [bytes(length), bytes([255]) * length,
                    bytes(i & 255 for i in range(length)), rng.randbytes(length)][pattern]
            add(f'padding-{pattern}-{length}', data, 'padding-and-block-boundaries')
    for index in range(512):
        length = rng.randrange(8193)
        add(f'random-{index}', rng.randbytes(length), 'seeded-random')
    # Finite-message truncation and byte rejection are separate checked-API
    # observations; no partial hash is returned on failure.
    errors = []
    for length in [1, 2, 3, 4, 55, 56, 63, 64, 65, 119, 120, 127, 128, 129, 255, 256, 257]:
        data = bytes(i & 255 for i in range(length))
        name = f'limit-{length}'
        errors.append((name, '|'.join([name, 'hex', str(length-1), data.hex()]), ('error', 'byte limit exceeded')))
    for value in [256, 257, 65535, 65536, 2147483648, 4294967295]:
        for index in [0, 1, 3, 55, 56, 63, 64, 65, 127, 128, 129]:
            values = [i & 255 for i in range(index)] + [value, 0, 255]
            name = f'invalid-{value}-{index}'
            errors.append((name, '|'.join([name, 'values', str(len(values)), ','.join(map(str, values))]),
                           ('error', 'input byte exceeds 255')))
    # Exhausted budget wins at that position; an earlier invalid byte wins
    # before the next position can consume budget.
    errors += [('priority-budget', 'priority-budget|values|0|256', ('error', 'byte limit exceeded')),
               ('priority-invalid', 'priority-invalid|values|1|256,0', ('error', 'input byte exceeds 255'))]
    lengths = []
    for size in [0, 1, 55, 56, 63, 64, 65, (1<<29)-1, 1<<29, (1<<32)-1, 1<<32,
                 (1<<32)+1, (1<<40)+63, NAT_MAX]:
        name = f'length-{size}'
        lengths.append((name, f'{name}|length|{size >> 32}|{size & 0xffffffff}', ('length', (size*8).to_bytes(8, 'big'))))
    rotations = []
    for word in [0, 1, 2147483648, 2147483649, 4294967295, 305419896, 252645135]:
        for shift in [*range(64), 127, 128, 129, 65535, NAT_MAX]:
            n = shift % 32
            expected = ((word >> n) | (word << ((32-n) % 32))) & 0xffffffff
            name = f'rotate-{word}-{shift}'
            rotations.append((name, f'{name}|rotate|{word}|{shift}', ('rotate', expected)))
    return cases, errors, lengths, rotations, counts, digest.hexdigest(), examples


def large_cases():
    WORK.mkdir(parents=True, exist_ok=True)
    rng = random.Random(SEED + 1); cases = []; manifest = []
    datasets = [('million-a', b'a' * 1000000), ('million-zero', bytes(1000000)),
                ('million-ff', bytes([255]) * 1000000), ('four-mib-pattern', bytes(range(256)) * 16384),
                ('large-random', rng.randbytes(2 * 1024 * 1024 + 63)),
                ('registry-tsv', (ROOT / 'generated/reference_blocks.tsv').read_bytes())]
    for name, data in datasets:
        path = WORK / (name + '.bin'); path.write_bytes(data)
        expected = expected_digest(data)
        query = f'{name}|file|{len(data)}|{path}'
        cases.append((name, query, expected))
        cases.append((name+'-short', f'{name}-short|file|{len(data)-1}|{path}', ('error', 'byte limit exceeded')))
        manifest.append({'name': name, 'bytes': len(data), 'sha256': expected[1]})
    assert manifest[0]['sha256'] == 'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0'
    for count in [0, 1, 55, 56, 63, 64, 65, 1000000]:
        data = b'a' * count; name = f'repeated-a-{count}'
        cases.append((name, f'{name}|repeat|{count}|{count}|97', expected_digest(data)))
    return cases, manifest


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--skip-build', action='store_true'); args = parser.parse_args()
    commands = []
    for source in ['src/hash.bend', 'tests/hash.bend']:
        for flag in ['--check-only', '--verdict']:
            commands.append(run([BEND, source, flag])[0])
    if not args.skip_build:
        commands.append(run([BEND, 'tests/hash.bend', '-o', 'build/hash-tests.c'])[0])
        commands.append(run([BEND, 'tests/hash.bend', '-o', BINARY])[0])
    cases, errors, lengths, rotations, counts, corpus, examples = fixture_cases()
    large, manifest = large_cases(); native = []
    execute(cases, native, 'independent-hash-oracles')
    execute(errors, native, 'checked-byte-and-budget-errors')
    execute(lengths, native, '64-bit-bit-length-fields')
    execute(rotations, native, 'rotations-modulo-32')
    execute(large, native, 'large-messages-and-replication')
    malformed = []
    for query in ['broken', 'odd|hex|1|0', 'invalid|hex|1|gg',
                  f'oversized-budget|hex|{NAT_MAX+1}|', 'negative-budget|hex|-1|00']:
        result, _ = run([BINARY, '--gpu', 'off', query], required=False)
        assert result['exit_code'] == 2, result
        malformed.append({'query': query, 'exit_code': result['exit_code'], 'stderr': result['stderr']})
    c_path = ROOT / 'build/hash-tests.c'; c = c_path.read_text()
    helpers = re.findall(r'(?:INLINE|FAR) Term spin_\d+\([^)]*\) \{.*?\n\}', c, re.S)
    assert helpers, 'C inspection must include emitted helper bodies'
    assert all(not re.search(r'\b(?:double|float|f32|F32_BIN|F32_PRM)\b', body) for body in helpers)
    # The shared runtime defines blk_copy, but emitted digest code never calls
    # it. The single owned schedule allocation remains visible at entry.
    assert c.count('blk_copy(') == 1
    allocations = [line.strip() for line in c.splitlines() if 'blk_new(e, 0, 6ull,' in line]
    assert len(allocations) == 1
    source = (ROOT / 'src/hash.bend').read_text()
    result = {'schema_version': 1, 'status': 'native-and-independent-kernel-pass',
              'confidence': 'high for recorded SHA-256 fixtures; no cryptographic security theorem',
              'primary_sources': {'standard': FIPS, 'nist_one_and_two_block_examples': EXAMPLES},
              'standard_sections': ['4.1.2', '4.2.2', '5.1.1', '5.2.1', '5.3.3', '6.2.2'],
              'compiler': run([BEND, 'version'])[0]['stdout'].strip(), 'commands': commands,
              'source_sha256': {name: sha(ROOT / name) for name in ['src/hash.bend', 'tests/hash.bend', 'tools/test_hash.py', 'docs/HASH.md'] if (ROOT / name).exists()},
              'binary_sha256': sha(BINARY), 'emitted_c_sha256': sha(c_path),
              'emitted_c_bytes': len(c.encode()), 'emitted_c_lines': c.count('\n'),
              'emitted_c_scalar_helpers': len(helpers), 'host_float_scalar_helpers': 0,
              'emitted_c_array_clone_calls': 0, 'owned_schedule_allocation': allocations[0],
              'oracle_providers': {'hashlib_module': hashlib.sha256.__module__, 'hashlib_openssl': ssl.OPENSSL_VERSION,
                                   'independent_portable_python_module': _sha2.__file__, 'openssl_cli': run(['openssl', 'version'])[0]['stdout'].strip()},
              'random_seed': SEED, 'corpus_sha256': corpus, 'native_batches': native,
              'small_digest_cases': len(cases), 'small_digest_categories': dict(counts),
              'large_and_replication_cases': len(large), 'large_inputs': manifest,
              'successful_digest_cases': len(cases) + sum(expected[0] == 'digest' for _, _, expected in large),
              'total_checked_error_cases': len(errors) + sum(expected[0] == 'error' for _, _, expected in large),
              'native_observations': sum(len(lane) for lane in [cases, errors, lengths, rotations, large]),
              'checked_error_cases': len(errors), 'bit_length_cases': len(lengths), 'rotation_cases': len(rotations),
              'malformed_test_protocol_cases': malformed, 'implementation_laws': re.findall(r'^law (\w+):', source, re.M),
              'native_input_limit': NAT_MAX, 'public_digest_formats': {'bytes': 32, 'hex_characters': 64},
              'boundaries': ['one-shot reusable-byte API', 'one owned 64-word schedule', 'byte-oriented messages only',
                             'test file transport is bounded to 4 MiB', 'not a universal SHA-256 theorem', 'not a NIST validated module']}
    EVIDENCE.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps({key: result[key] for key in ['status', 'small_digest_cases', 'large_and_replication_cases',
          'checked_error_cases', 'bit_length_cases', 'rotation_cases', 'emitted_c_bytes', 'implementation_laws']}, indent=2))


if __name__ == '__main__':
    main()
