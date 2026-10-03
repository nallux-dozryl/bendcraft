#!/usr/bin/env python3
"""Exact pinned Entity.turn reference and rational/native pure-Bend comparisons.

Java is the production behavior oracle. Python constructs validation fixtures,
checks exact binary32 arithmetic with Fractions, and orchestrates processes only.
"""
from __future__ import annotations
import argparse
import collections
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess
import time
from fractions import Fraction

import reference_player_look_probe as P
from build_native import ensure_native
from reference_inventory import fingerprint

ROOT = Path(__file__).resolve().parents[1]
BEND = Path('/Users/chuah/.bend/bin/bend')
BINARY = ROOT / 'build/player-look-tests'
REFERENCE = ROOT / 'reference/player_look.json'
EVIDENCE = ROOT / 'evidence/player-look-native.json'
KERNEL = ROOT / 'evidence/player-look-kernel.json'
BUILD_RECORD = ROOT / 'build/player-look-build.json'
F32_INF = 0x7f800000
F32_SIGN = 0x80000000
F64_INF = 0x7ff0000000000000


def sha(data):
    return hashlib.sha256(data).hexdigest()


def finite32(bits):
    return bits & F32_INF != F32_INF


def finite64(bits):
    return bits & F64_INF != F64_INF


def power2(exponent):
    return Fraction(1 << exponent) if exponent >= 0 else Fraction(1, 1 << -exponent)


def exact(bits, width):
    frac_bits, exp_bits, bias = (23, 8, 127) if width == 32 else (52, 11, 1023)
    exponent = (bits >> frac_bits) & ((1 << exp_bits) - 1)
    if exponent == (1 << exp_bits) - 1:
        raise ValueError('nonfinite exact rational input')
    significand = bits & ((1 << frac_bits) - 1)
    if exponent:
        significand |= 1 << frac_bits
    value = significand * power2((exponent if exponent else 1) - bias - frac_bits)
    return -value if bits >> (width - 1) else value


def round32(value, negative_zero=False):
    """Integer rational RN-even, including subnormals and overflow boundary."""
    if not value:
        return F32_SIGN if negative_zero else 0
    sign = F32_SIGN if value < 0 else 0
    value = abs(value)
    exponent = value.numerator.bit_length() - value.denominator.bit_length()
    if value < power2(exponent):
        exponent -= 1
    if exponent >= 128:
        return sign | F32_INF
    scaled = value / power2(exponent - 23 if exponent >= -126 else -149)
    retained, remainder = divmod(scaled.numerator, scaled.denominator)
    retained += int(2 * remainder > scaled.denominator or
                    2 * remainder == scaled.denominator and retained & 1)
    if exponent < -126:
        return sign | retained
    if retained == 1 << 24:
        exponent += 1
        retained >>= 1
    if exponent > 127:
        return sign | F32_INF
    return sign | ((exponent + 127) << 23) | (retained - (1 << 23))


def narrow(bits):
    assert finite64(bits)
    return round32(exact(bits, 64), bool(bits >> 63))


def add32(a, b):
    assert finite32(a) or a & 0x7fffffff == F32_INF
    assert finite32(b) or b & 0x7fffffff == F32_INF
    if not finite32(a):
        assert finite32(b) or (a ^ b) & F32_SIGN == 0
        return a
    if not finite32(b):
        return b
    return round32(exact(a, 32) + exact(b, 32), a == b == F32_SIGN)


def delta(bits):
    value = narrow(bits)
    if not finite32(value):
        return value
    return round32(exact(value, 32) * exact(0x3e19999a, 32), bool(value & F32_SIGN))


def clamp(bits):
    if bits == F32_INF:
        return 0x42b40000
    if bits == F32_SIGN | F32_INF:
        return 0xc2b40000
    value = exact(bits, 32)
    return 0xc2b40000 if value < -90 else 0x42b40000 if value > 90 else bits


def remainder360(bits):
    value = exact(bits, 32)
    quotient = abs(value) // 360
    if value < 0:
        quotient = -quotient
    return round32(value - quotient * 360, bool(bits & F32_SIGN))


def rational_turn(state, dx, dy):
    assert all(map(finite32, state)) and finite64(dx) and finite64(dy)
    x, y = delta(dx), delta(dy)
    yaw = add32(state[0], x)
    pitch = add32(state[1], y)
    return [yaw if finite32(yaw) else state[0],
            clamp(remainder360(pitch) if finite32(pitch) else state[1]),
            add32(state[2], x), clamp(add32(state[3], y))]


def error(state, dx, dy, output=None):
    for index, value in enumerate(state):
        if not finite32(value):
            return {'kind': 'InvalidState', 'field': index}
    for index, value in enumerate((dx, dy)):
        if not finite64(value):
            return {'kind': 'InvalidInput', 'field': index}
    if output is not None:
        for index, value in enumerate(output):
            if not finite32(value):
                return {'kind': 'NonFiniteResult', 'field': index}
    return None


def expected_report(state, dx, dy, output=None):
    prior_error = error(state, dx, dy)
    if prior_error:
        return {'ok': False, 'error': prior_error}
    assert output is not None
    final_error = error(state, dx, dy, output)
    return ({'ok': False, 'error': final_error, 'raw_state': output} if final_error else
            {'ok': True, 'state': output, 'raw_state': output})


def words(state, dx, dy):
    return [*state, dx >> 32, dx & 0xffffffff, dy >> 32, dy & 0xffffffff]


def run(command, timeout=180, allow_failure=False):
    start = time.monotonic()
    result = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    if result.returncode and not allow_failure:
        raise RuntimeError(f'command failed ({result.returncode}): {command}\n{result.stdout[-6000:]}\n{result.stderr[-6000:]}')
    return {'command': list(map(str, command)), 'exit_code': result.returncode,
            'stdout': result.stdout, 'stderr': result.stderr, 'seconds': round(time.monotonic() - start, 6)}


def imports(paths):
    todo, found = list(paths), set()
    while todo:
        path = todo.pop().resolve()
        if path in found:
            continue
        found.add(path)
        for relative in re.findall(r'^import\s+(\.[^\s]+)', path.read_text(), re.M):
            todo.append(path.parent / relative)
    return {str(p.relative_to(ROOT)): sha(p.read_bytes()) for p in sorted(found)}


def verify_build(build):
    for item in build['dependencies']:
        path = Path(item['lookup'])
        assert str(path.resolve()) == item['path'], 'native dependency alias changed: ' + str(path)
        assert path.is_file() and path.stat().st_size == item['bytes']
        assert sha(path.read_bytes()) == item['sha256'], 'native dependency changed: ' + str(path)
    artifact = Path(build['artifact'])
    assert artifact.stat().st_size == build['binary_bytes']
    assert sha(artifact.read_bytes()) == build['binary_sha256'], 'native artifact digest changed'
    return artifact


def reference_cases(data):
    cases, chains, rational_checks, unsupported = [], [], 0, 0
    for fixture, observed in zip(data['inputs'], data['observations']['cases'], strict=True):
        state = [int(v, 16) for v in fixture['input']['state_f32_bits']]
        deltas = [fixture['input'], *fixture['chain']]
        chain_reports = []
        for index, (step_input, step) in enumerate(zip(deltas, observed['steps'], strict=True)):
            dx, dy = [int(step_input[key], 16) for key in ('dx_f64_bits', 'dy_f64_bits')]
            output = [int(v, 16) for v in step['state_f32_bits']]
            assert step['exception_class'] is None, (fixture['id'], index, step)
            admitted = error(state, dx, dy) is None
            if admitted:
                rational = rational_turn(state, dx, dy)
                assert rational == output, ('production/rational mismatch', fixture['id'], index, rational, output)
                rational_checks += 1
            else:
                unsupported += 1
            expected = expected_report(state, dx, dy, output)
            cases.append({'id': fixture['id'] + '/' + str(index), 'category': fixture['category'],
                          'words': words(state, dx, dy), 'expected': expected})
            chain_reports.append(expected)
            state = output
        if fixture['chain']:
            assert all(r['ok'] for r in chain_reports), 'chained fixture crossed checked admission'
            args = [*map(lambda v: int(v, 16), fixture['input']['state_f32_bits'])]
            for item in deltas:
                dx, dy = [int(item[key], 16) for key in ('dx_f64_bits', 'dy_f64_bits')]
                args += [dx >> 32, dx & 0xffffffff, dy >> 32, dy & 0xffffffff]
            chains.append((fixture['id'], args, chain_reports))
    return cases, chains, rational_checks, unsupported


def validation_cases():
    cases = []
    for index in range(4):
        for raw in (0x7f800000, 0xff800000, 0x7fc00123, 0x7f800001, 0xffc00123, 0xff800001):
            state = [0, 0, 0, 0]; state[index] = raw
            cases.append({'id': f'invalid-state-{index}-{raw:08x}', 'category': 'checked-state-admission',
                          'words': words(state, 0, 0), 'expected': expected_report(state, 0, 0)})
    for axis in range(2):
        for raw in (0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000000123,
                    0x7ff0000000000001, 0xfff8000000000123, 0xfff0000000000001):
            dx, dy = (raw, 0) if axis == 0 else (0, raw)
            cases.append({'id': f'invalid-input-{axis}-{raw:016x}', 'category': 'checked-input-admission',
                          'words': words([0] * 4, dx, dy), 'expected': expected_report([0] * 4, dx, dy)})
    for state, dx, dy in (([F32_INF] * 4, F64_INF, F64_INF), ([0, F32_INF, F32_INF, 0], F64_INF, F64_INF),
                          ([0] * 4, F64_INF, F64_INF)):
        cases.append({'id': f'error-order-{len(cases)}', 'category': 'first-error-order',
                      'words': words(state, dx, dy), 'expected': expected_report(state, dx, dy)})
    return cases


def native_batches(cases, binary):
    reports, failures = [], []
    for offset in range(0, len(cases), 48):
        batch = cases[offset:offset + 48]
        args = [str(v) for case in batch for v in case['words']]
        result = run([binary, '--gpu', 'off', '--threads', '1', '--', *args], timeout=180)
        lines = result['stdout'].splitlines()
        assert len(lines) == len(batch), ('native output count', offset, len(lines), len(batch))
        assert not result['stderr'], result['stderr']
        for case, line in zip(batch, lines, strict=True):
            actual = json.loads(line)
            if actual != case['expected']:
                failures.append({'id': case['id'], 'words': case['words'], 'expected': case['expected'], 'actual': actual})
        reports.append({'offset': offset, 'cases': len(batch), 'seconds': result['seconds'],
                        'stdout_sha256': sha(result['stdout'].encode())})
    return reports, failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-build', action='store_true')
    parser.add_argument('--skip-kernel', action='store_true')
    parser.add_argument('--oracle-only', action='store_true')
    args = parser.parse_args()
    data = json.loads(REFERENCE.read_text())
    fixture_integrity = P.validate(data)
    cp, provenance = P.verified_client_classpath()
    assert provenance == data['provenance'], 'production runtime/classpath changed'
    assert P.source_records(cp) == data['source'], 'production class bytes/probe source changed'
    cases, chains, rational_checks, unsupported = reference_cases(data)
    validation = validation_cases()
    assert round32(Fraction(1, 1 << 150)) == 0
    assert round32(Fraction(3, 1 << 150)) == 2
    assert round32(Fraction((1 << 24) + 1, 1 << 24)) == 0x3f800000
    assert round32(power2(128) - power2(103)) == F32_INF
    assert remainder360(0xc4340000) == F32_SIGN  # -720 exact remainder
    if args.oracle_only:
        print(json.dumps({'status': 'passed', 'fixture_integrity': fixture_integrity,
                          'rational_production_comparisons': rational_checks, 'outside_finite_input_projection': unsupported,
                          'validation_cases': len(validation), 'chains': len(chains)}));return
    paths = [ROOT / 'src/player_look.bend', ROOT / 'tests/player_look.bend']
    sources = imports(paths)
    checks = [run([BEND, p, '--check-only']) for p in paths]
    kernel_checks = []
    if not args.skip_kernel:
        kernel_checks = [run([BEND, p, '--verdict'], timeout=600) for p in paths]
        assert all('ALL PROOFS CHECK' in c['stdout'] for c in kernel_checks)
        KERNEL.write_text(json.dumps({'status': 'passed', 'commands': kernel_checks, 'sources_sha256': sources,
                          'laws': re.findall(r'^law (\w+):', paths[1].read_text(), re.M),
                          'proof_scope': 'Independent type/termination checks of actual full imported source and the stated fixture/ownership laws; no universal IEEE or Entity equivalence theorem'}, indent=2) + '\n')
    if args.skip_build:
        record = json.loads(BUILD_RECORD.read_text())
        assert record['sources_sha256'] == sources, 'native build sources changed'
        build = record['build']
    else:
        build = ensure_native(paths[1], BINARY, bend=BEND)
        BUILD_RECORD.write_text(json.dumps({'sources_sha256': sources, 'build': build}, indent=2) + '\n')
    binary = verify_build(build)
    assert binary.is_file()
    start = time.monotonic()
    batches, failures = native_batches(cases + validation, binary)
    chain_runs = []
    for identity, chain_args, expected in chains:
        result = run([binary, '--gpu', 'off', '--threads', '1', '--', 'chain', *chain_args])
        actual = [json.loads(line) for line in result['stdout'].splitlines()]
        assert actual == expected, ('native state-carrying chain mismatch', identity, actual, expected)
        chain_runs.append({'id': identity, 'steps': len(expected), 'seconds': result['seconds'],
                           'stdout_sha256': sha(result['stdout'].encode())})
    good = {'id': 'validation-recovery', 'words': words([0] * 4, 0, 0),
            'expected': expected_report([0] * 4, 0, 0, [0] * 4)}
    followups = [item for invalid in validation for item in (invalid, good)]
    follow_batches, follow_failures = native_batches(followups, binary)
    malformed = []
    for arguments in (['0'], ['nope'] * 8, ['4294967296'] + ['0'] * 7,
                      ['chain', '0', '0', '0', '0', 'bad', '0', '0', '0'],
                      ['chain', '0', '0', '0', '0', '0']):
        result = run([binary, '--gpu', 'off', '--threads', '1', '--', *arguments], allow_failure=True)
        assert result['exit_code'] == 2 and not result['stdout'], result
        malformed.append(result)
    assert sources == imports(paths), 'sources changed during verification'
    verify_build(build)
    assert not failures + follow_failures, json.dumps((failures + follow_failures)[:5])
    statuses = collections.Counter('ok' if c['expected']['ok'] else c['expected']['error']['kind'] for c in cases)
    evidence = {'status': 'passed', 'pin': '26.3', 'confidence': 'high for recorded admitted neutral Entity.turn projection',
                'reference': fingerprint(REFERENCE), 'reference_producer': fingerprint(Path(P.__file__)),
                'fixture_integrity': fixture_integrity, 'production_provenance': provenance,
                'native_production_step_comparisons': len(cases), 'rational_production_comparisons': rational_checks,
                'outside_finite_input_projection_rejections': unsupported, 'native_checked_statuses': dict(statuses),
                'state_carrying_chains': len(chains), 'state_carrying_turn_steps': sum(len(v[2]) for v in chains),
                'explicit_validation_cases': len(validation), 'successful_same_process_rejection_followups': len(validation),
                'malformed_protocol_cases': malformed, 'native_batches': batches, 'chain_runs': chain_runs,
                'recovery_batches': follow_batches, 'seconds_including_startup_argument_output_io': round(time.monotonic() - start, 6),
                'sources_sha256': sources, 'binary': fingerprint(binary), 'native_build': build,
                'runner': fingerprint(Path(__file__)), 'ordinary_checks': checks,
                'kernel_checks_this_run': kernel_checks, 'kernel_evidence': str(KERNEL.relative_to(ROOT)) if KERNEL.exists() else None,
                'categories': dict(collections.Counter(c['category'] for c in cases)),
                'oracle': 'Direct pinned Entity.turn raw fields and ordered setter/getter trace; independent Fraction RN-even cast/multiply/add/remainder/clamp over every admitted step; no host float arithmetic decides expectations',
                'scope': data['scope'], 'mouse_boundary': data['mouse_boundary'],
                'simulation_boundary': 'Pure checked F64 word arithmetic and exact bounded integer remainder; no Foreign/unsafe, no native F32 math or host gameplay adapter',
                'logging_boundary': 'Exact state/error projection; Java logging is recorded by reference only. Bend does not emit setter warnings or invoke passenger callbacks.',
                'proof_scope': 'Recorded finite fixtures plus stated laws, not a universal Entity/IEEE equivalence theorem',
                'platform': {'system': platform.system(), 'machine': platform.machine()},
                'commands': ['python3 tools/reference_player_look_probe.py selftest', 'python3 tools/test_player_look.py']}
    EVIDENCE.write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps({'status': 'passed', 'steps': len(cases), 'statuses': dict(statuses), 'chains': len(chains),
                      'validation_cases': len(validation), 'evidence': str(EVIDENCE.relative_to(ROOT))}))


if __name__ == '__main__':
    main()
