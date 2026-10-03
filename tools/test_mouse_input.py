#!/usr/bin/env python3
"""Native pure-Bend mouse state/scaling against pinned untouched Java handlers.

Direct onMove/turnPlayer observations are distinguished from the unexecuted
frame wrapper's capture/focus/player gate and accumulation-reset bytecode policy.
"""
from __future__ import annotations
import argparse
import collections
import json
from pathlib import Path
import re
import time

import reference_mouse_input_probe as P
import test_player_look as L
from build_native import ensure_native
from reference_inventory import fingerprint

ROOT = Path(__file__).resolve().parents[1]
BEND = Path('/Users/chuah/.bend/bin/bend')
BINARY = ROOT / 'build/mouse-input-tests'
BUILD_RECORD = ROOT / 'build/mouse-input-build.json'
EVIDENCE = ROOT / 'evidence/mouse-input-native.json'
KERNEL = ROOT / 'evidence/mouse-input-kernel.json'
SIGN = 1 << 63
INF = 0x7ff0000000000000
ZERO_STATE = [0, 0, 0, 0, False]
DEFAULT_OPTIONS = [0x3fe0000000000000, False, False, False, False]


def round64(value, negative_zero=False):
    if not value:
        return SIGN if negative_zero else 0
    sign = SIGN if value < 0 else 0
    value = abs(value)
    exponent = value.numerator.bit_length() - value.denominator.bit_length()
    if value < L.power2(exponent):
        exponent -= 1
    if exponent >= 1024:
        return sign | INF
    scaled = value / L.power2(exponent - 52 if exponent >= -1022 else -1074)
    retained, remainder = divmod(scaled.numerator, scaled.denominator)
    retained += int(2 * remainder > scaled.denominator or
                    2 * remainder == scaled.denominator and retained & 1)
    if exponent < -1022:
        return sign | retained
    if retained == 1 << 53:
        exponent += 1
        retained >>= 1
    if exponent > 1023:
        return sign | INF
    return sign | ((exponent + 1023) << 52) | (retained - (1 << 52))


def add(a, b):
    assert L.finite64(a) and L.finite64(b)
    return round64(L.exact(a, 64) + L.exact(b, 64), a == b == SIGN)


def mul(a, b):
    assert L.finite64(a) and L.finite64(b)
    return round64(L.exact(a, 64) * L.exact(b, 64), bool((a ^ b) & SIGN))


def add_extended(a, b):
    if not L.finite64(b):
        assert b & ~SIGN == INF and L.finite64(a)
        return b
    return add(a, b)


def scale(sensitivity):
    a = add(mul(sensitivity, 0x3fe3333340000000), 0x3fc99999a0000000)
    return mul(mul(mul(a, a), a), 0x4020000000000000)


def scaled(state, options):
    factor = scale(options[0])
    return [mul(state[2], factor) ^ (SIGN if options[1] else 0),
            mul(state[3], factor) ^ (SIGN if options[2] else 0)]


def state_error(state):
    for index, value in enumerate(state[:4]):
        if not L.finite64(value):
            return {'kind': 'InvalidState', 'field': index}
    return None


def options_error(options):
    if not L.finite64(options[0]) or not 0 <= L.exact(options[0], 64) <= 1:
        return {'kind': 'InvalidSensitivity'}
    if options[3]:
        return {'kind': 'UnsupportedSmoothCamera'}
    if options[4]:
        return {'kind': 'UnsupportedScoping'}
    return None


def error_report(error):
    return {'ok': False, 'error': error}


def state_words(state):
    return [word for value in state[:4] for word in (value >> 32, value & 0xffffffff)] + [int(state[4])]


def move_words(move):
    return [word for value in move[:4] for word in (value >> 32, value & 0xffffffff)] + [int(move[4])]


def options_words(options):
    return [options[0] >> 32, options[0] & 0xffffffff, *map(int, options[1:])]


def clear(state):
    return [state[0], state[1], 0, 0, state[4]]


def move_raw(state, move, focused, captured):
    if not move[4]:
        return state[:]
    if state[4]:
        return [move[0], move[1], state[2], state[3], False]
    ax, ay = state[2:4]
    if focused:
        dx, dy = move[2:4] if captured else [add(move[i], state[i] ^ SIGN) for i in (0, 1)]
        ax, ay = add_extended(ax, dx), add_extended(ay, dy)
    return [move[0], move[1], ax, ay, False]


def move_report(state, move, focused, captured):
    error = state_error(state)
    if error:
        return error_report(error)
    for index, value in enumerate(move[:4]):
        if not L.finite64(value):
            return error_report({'kind': 'InvalidMove', 'field': index})
    output = move_raw(state, move, focused, captured)
    for index, value in enumerate(output[2:4]):
        if not L.finite64(value):
            return error_report({'kind': 'NonFiniteAccumulation', 'field': index})
    return {'ok': True, 'state': state_words(output)}


def finish_report(state, options, focused, captured, player):
    error = state_error(state) or options_error(options)
    if error:
        return error_report(error)
    turn = None
    if focused and captured and player:
        turn = scaled(state, options)
        for index, value in enumerate(turn):
            if not L.finite64(value):
                return error_report({'kind': 'NonFiniteDeltas', 'field': index})
        turn = [word for value in turn for word in (value >> 32, value & 0xffffffff)]
    return {'ok': True, 'state': state_words(clear(state)), 'turn': turn}


def relative_report(state, dx, dy, focused, captured):
    if not captured:
        return error_report({'kind': 'UnsupportedRelativeMode'})
    return move_report(state, [state[0], state[1], dx, dy, True], focused, True)


def from_observation(observed):
    return [*map(lambda v: int(v, 16), observed['mouse_f64_bits']), observed['ignore_first_move']]


def reference_cases(data):
    cases, pairs = [], []
    counts = collections.Counter()
    def add_case(identity, category, mode, args, expected):
        cases.append({'id': identity, 'category': category, 'mode': mode, 'args': args, 'expected': expected})
    for fixture, record in zip(data['inputs'], data['observations']['cases'], strict=True):
        initial = fixture['initial']
        prior = {'mouse_f64_bits': initial['mouse_f64_bits'], 'ignore_first_move': initial['ignore_first_move'],
                 'focused': initial['focused'], 'mouse_grabbed': initial['mouse_grabbed']}
        options = [int(initial['sensitivity_f64_bits'], 16), initial['invert_x'], initial['invert_y'], False, False]
        for index, (event, observed) in enumerate(zip(fixture['events'], record['steps'], strict=True)):
            assert observed['exception_class'] is None, (fixture['id'], index, observed)
            state = from_observation(prior)
            identity = fixture['id'] + '/' + str(index)
            focused, captured = prior['focused'], prior['mouse_grabbed']
            if event['op'] == 'move':
                move = [int(event[key], 16) for key in ('x_f64_bits', 'y_f64_bits', 'relative_x_f64_bits', 'relative_y_f64_bits')]
                move += [event['window_handle'] == P.HANDLE]
                expected = move_report(state, move, focused, captured)
                if state_error(state) is None and all(L.finite64(v) for v in move[:4]):
                    rational = move_raw(state, move, focused, captured)
                    assert rational == from_observation(observed), ('rational/production onMove mismatch', identity, rational, observed)
                    counts['rational_actual_on_move'] += 1
                else:
                    counts['outside_finite_on_move_projection'] += 1
                add_case(identity, fixture['category'], 'move', state_words(state) + move_words(move) + [int(focused), int(captured)], expected)
                counts['native_move_cases'] += 1
                if move[4] and captured and state_error(state) is None and all(L.finite64(v) for v in move[:4]):
                    rel = relative_report(state, move[2], move[3], focused, True)
                    if rel['ok']:
                        assert rel['state'][4:] == state_words(from_observation(observed))[4:]
                    args = state_words(state) + move_words([move[2], move[3], 0, 0, False])[:4] + [int(focused), 1]
                    add_case(identity + '/relative', 'captured-relative-convenience-projection', 'relative', args, rel)
                    counts['native_relative_projection_cases'] += 1
            elif event['op'] == 'turn':
                trace = observed['trace']
                assert [t['method'] for t in trace] == ['Tutorial.onMouse', 'LocalPlayer.turn']
                assert observed['mouse_f64_bits'] == prior['mouse_f64_bits'], 'private turn unexpectedly cleared accumulation'
                assert observed['smooth_x_f64_bits'] == observed['smooth_y_f64_bits'] == ['0000000000000000'] * 3
                expected = finish_report(state, options, True, True, True)
                if state_error(state) is None and options_error(options) is None:
                    actual = [int(trace[1][key], 16) for key in ('dx_f64_bits', 'dy_f64_bits')]
                    rational = scaled(state, options)
                    assert actual == rational, ('rational/production scaling mismatch', identity, rational, actual)
                    tutorial = [int(trace[0][key], 16) for key in ('dx_f64_bits', 'dy_f64_bits')]
                    assert tutorial == [rational[i] ^ (SIGN if options[i + 1] else 0) for i in range(2)]
                    counts['rational_actual_turn_scaling'] += 1
                else:
                    counts['outside_finite_turn_projection'] += 1
                # Force active for the actual private-method scaling projection;
                # wrapper gate/reset are separate bytecode policy observations.
                add_case(identity, 'actual-private-neutral-turn-scaling', 'finish', state_words(state) + options_words(options) + [1, 1, 1], expected)
                counts['native_actual_private_scaling_cases'] += 1
                add_case(identity + '/frame-gates', 'unexecuted-wrapper-bytecode-policy', 'finish',
                         state_words(state) + options_words(options) + [int(focused), int(captured), 1],
                         finish_report(state, options, focused, captured, True))
                counts['native_wrapper_policy_cases'] += 1
            elif event['op'] == 'set_ignore_first':
                assert observed['event_boundary'] == 'actual-production-call'
                assert observed['mouse_f64_bits'] == prior['mouse_f64_bits'] and observed['ignore_first_move']
                add_case(identity, 'actual-first-move-rearm', 'arm', state_words(state), {'ok': True, 'state': state_words(from_observation(observed))})
                counts['actual_first_move_rearm'] += 1
            else:
                assert observed['event_boundary'] == 'explicit-fixture-field-mutation'
                counts['explicit_fixture_mutations'] += 1
            prior = observed
        if fixture['category'] in ('two-move-native-pipeline', 'two-move-uncaptured-diagnostic'):
            state = [*map(lambda v: int(v, 16), initial['mouse_f64_bits']), initial['ignore_first_move']]
            focused, captured = initial['focused'], initial['mouse_grabbed']
            moves = []
            for event in fixture['events'][:2]:
                moves.append([*[int(event[key], 16) for key in ('x_f64_bits', 'y_f64_bits', 'relative_x_f64_bits', 'relative_y_f64_bits')], event['window_handle'] == P.HANDLE])
            midway = move_raw(state, moves[0], focused, captured)
            final = move_raw(midway, moves[1], focused, captured)
            assert final == from_observation(record['steps'][1])
            expected = finish_report(final, options, focused, captured, True)
            args = state_words(state) + move_words(moves[0]) + move_words(moves[1]) + options_words(options) + [int(focused), int(captured), 1]
            pairs.append({'id': fixture['id'], 'category': fixture['category'], 'mode': 'pair', 'args': args, 'expected': expected})
    return cases, pairs, dict(counts)


def validation_cases():
    cases = []
    def append(mode, state, extra, expected, name):
        cases.append({'id': name, 'category': 'explicit-admission', 'mode': mode,
                      'args': state_words(state) + extra, 'expected': expected})
    bads = (INF, SIGN | INF, 0x7ff8000000000123, 0x7ff0000000000001, 0xfff8000000000123, 0xfff0000000000001)
    for index in range(4):
        for bad in bads:
            state = ZERO_STATE[:]; state[index] = bad
            append('move', state, move_words([0, 0, 0, 0, True]) + [1, 1],
                   move_report(state, [0, 0, 0, 0, True], True, True), f'invalid-state-move-{index}-{bad:x}')
            append('finish', state, options_words(DEFAULT_OPTIONS) + [1, 1, 1],
                   finish_report(state, DEFAULT_OPTIONS, True, True, True), f'invalid-state-finish-{index}-{bad:x}')
    for index in range(4):
        for bad in bads:
            move = [0, 0, 0, 0, True]; move[index] = bad
            append('move', ZERO_STATE, move_words(move) + [1, 1], move_report(ZERO_STATE, move, True, True), f'invalid-move-{index}-{bad:x}')
    for bad in (*bads, SIGN | 1, 0xbff0000000000000, 0x3ff0000000000001, 0x4000000000000000):
        options = DEFAULT_OPTIONS[:]; options[0] = bad
        for active in (False, True):
            append('finish', ZERO_STATE, options_words(options) + [int(active)] * 3,
                   finish_report(ZERO_STATE, options, active, active, active), f'invalid-sensitivity-{bad:x}-{active}')
    for smooth, scoping in ((True, False), (False, True), (True, True)):
        options = DEFAULT_OPTIONS[:]; options[3:5] = [smooth, scoping]
        for active in (False, True):
            append('finish', ZERO_STATE, options_words(options) + [int(active)] * 3,
                   finish_report(ZERO_STATE, options, active, active, active), f'unsupported-policy-{smooth}-{scoping}-{active}')
    for focus in (False, True):
        for first in (False, True):
            state = ZERO_STATE[:]; state[4] = first
            append('relative', state, [0, 0, 0, 0, int(focus), 0], relative_report(state, 0, 0, focus, False), f'uncaptured-relative-{focus}-{first}')
    maximum = 0x7fefffffffffffff
    for axis in (0, 1):
        for negative in (False, True):
            state = ZERO_STATE[:]; state[2 + axis] = maximum | (SIGN if negative else 0)
            move = [0, 0, 0, 0, True]; move[2 + axis] = state[2 + axis]
            append('move', state, move_words(move) + [1, 1], move_report(state, move, True, True), f'accumulation-overflow-{axis}-{negative}')
            append('finish', state, options_words(DEFAULT_OPTIONS) + [1, 1, 1], finish_report(state, DEFAULT_OPTIONS, True, True, True), f'scale-overflow-{axis}-{negative}')
    for focused in (False, True):
        for captured in (False, True):
            for player in (False, True):
                state = [0x3ff0000000000000, SIGN, 0x4000000000000000, SIGN, True]
                append('finish', state, options_words(DEFAULT_OPTIONS) + list(map(int, (focused, captured, player))),
                       finish_report(state, DEFAULT_OPTIONS, focused, captured, player), f'frame-admission-{focused}-{captured}-{player}')
    return cases


def native(cases, binary):
    reports, failures = [], []
    for start in range(0, len(cases), 32):
        batch = cases[start:start + 32]
        arguments = [item for case in batch for item in (case['mode'], *map(str, case['args']))]
        result = L.run([binary, '--gpu', 'off', '--threads', '1', '--', *arguments])
        lines = result['stdout'].splitlines()
        assert len(lines) == len(batch) and not result['stderr'], (start, result)
        for case, line in zip(batch, lines, strict=True):
            actual = json.loads(line)
            if actual != case['expected']:
                failures.append({'id': case['id'], 'mode': case['mode'], 'args': case['args'], 'actual': actual, 'expected': case['expected']})
        reports.append({'offset': start, 'cases': len(batch), 'seconds': result['seconds'], 'stdout_sha256': L.sha(result['stdout'].encode())})
    return reports, failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--oracle-only', action='store_true')
    parser.add_argument('--skip-build', action='store_true')
    parser.add_argument('--skip-kernel', action='store_true')
    args = parser.parse_args()
    data = json.loads(P.OUTPUT.read_text()); integrity = P.validate(data)
    cp, provenance = P.verified_client_classpath()
    assert provenance == data['provenance'] and P.source_records(cp) == data['source']
    cases, pairs, counts = reference_cases(data)
    validation = validation_cases()
    assert scale(0x3fe0000000000000) == 0x3ff000001800000c
    if args.oracle_only:
        print(json.dumps({'status': 'passed', 'counts': counts, 'pair_cases': len(pairs), 'validation_cases': len(validation), 'integrity': integrity}));return
    paths = [ROOT / 'src/mouse_input.bend', ROOT / 'tests/mouse_input.bend']
    sources = L.imports(paths)
    checks = [L.run([BEND, p, '--check-only']) for p in paths]
    kernel = []
    if not args.skip_kernel:
        kernel = [L.run([BEND, p, '--verdict'], timeout=600) for p in paths]
        assert all('ALL PROOFS CHECK' in row['stdout'] for row in kernel)
        KERNEL.write_text(json.dumps({'status': 'passed', 'checks': kernel, 'sources_sha256': sources,
                          'laws': re.findall(r'^law (\w+):', paths[1].read_text(), re.M),
                          'scope': 'Actual full-import independent type/termination plus stated fixture/owner laws; no universal MouseHandler/IEEE theorem'}, indent=2) + '\n')
    if args.skip_build:
        record = json.loads(BUILD_RECORD.read_text()); assert record['sources_sha256'] == sources
        build = record['build']
    else:
        build = ensure_native(paths[1], BINARY, bend=BEND)
        BUILD_RECORD.write_text(json.dumps({'sources_sha256': sources, 'build': build}, indent=2) + '\n')
    binary = L.verify_build(build)
    start = time.monotonic()
    batches, failures = native(cases + pairs + validation, binary)
    bad = [v for v in validation if not v['expected']['ok']]
    good = {'id': 'recovery-success', 'mode': 'finish', 'args': state_words(ZERO_STATE) + options_words(DEFAULT_OPTIONS) + [1, 1, 1],
            'expected': finish_report(ZERO_STATE, DEFAULT_OPTIONS, True, True, True)}
    recovery, recovery_failures = native([item for case in bad for item in (case, good)], binary)
    malformed = []
    for arguments in (['move'], ['finish'] + ['x'] * 18, ['relative'] + ['0'] * 14 + ['2'],
                      ['move'] + ['0'] * 8 + ['2'] + ['0'] * 11, ['finish'] + ['4294967296'] + ['0'] * 17):
        result = L.run([binary, '--gpu', 'off', '--threads', '1', '--', *arguments], allow_failure=True)
        assert result['exit_code'] == 2 and not result['stdout'], result
        malformed.append(result)
    assert not failures + recovery_failures, json.dumps((failures + recovery_failures)[:5])
    assert sources == L.imports(paths); L.verify_build(build)
    evidence = {'status': 'passed', 'pin': '26.3', 'confidence': 'high for executed admitted neutral methods and explicit pure wrapper policy',
                'reference': fingerprint(P.OUTPUT), 'reference_producer': fingerprint(Path(P.__file__)), 'integrity': integrity,
                'production_provenance': provenance, 'counts': counts, 'native_cases': len(cases) + len(pairs) + len(validation),
                'native_carried_two_move_pipelines': sum(p['category'] == 'two-move-native-pipeline' for p in pairs),
                'native_uncaptured_pair_wrapper_policy_cases': sum(p['category'] == 'two-move-uncaptured-diagnostic' for p in pairs),
                'validation_cases': len(validation), 'successful_same_process_recovery_calls': len(bad), 'malformed_protocol': malformed,
                'statuses': dict(collections.Counter('Done' if c['expected']['ok'] else c['expected']['error']['kind'] for c in cases + pairs + validation)),
                'native_batches': batches, 'recovery_batches': recovery, 'native_seconds_including_startup_argument_output_io': round(time.monotonic() - start, 6),
                'default_scale_f64_bits': '3ff000001800000c', 'sources_sha256': sources, 'binary': fingerprint(binary),
                'build': build, 'runner': fingerprint(Path(__file__)), 'oracle_helpers': fingerprint(Path(L.__file__)),
                'ordinary_checks': checks, 'kernel_checks_this_run': kernel,
                'oracle': 'Actual onMove mouse rawfields; actual Tutorial preinvert and player postinvert double arguments; exact Fraction binary64 RN-even after each operation, no host float expectation decisions',
                'scope': data['scope'], 'wrapper_boundary': data['wrapper_boundary'],
                'relative_boundary': 'Captured-only convenience retains unobserved absolute position; actual matching onMove compares accumulation and ignore-first projection',
                'admission_boundary': 'Finite position/accumulation/event/deltas, finite sensitivity in[0,1]; smooth/scoping/uncaptured-relative rejected; options checked even on inactive frames',
                'proof_scope': 'Recorded exact fixtures and stated laws, not universal MouseHandler/SDL/client behavior',
                'commands': ['python3 tools/reference_mouse_input_probe.py selftest', 'python3 tools/test_mouse_input.py']}
    EVIDENCE.write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps({'status': 'passed', 'counts': counts, 'pairs': len(pairs), 'validation': len(validation), 'evidence': str(EVIDENCE.relative_to(ROOT))}))


if __name__ == '__main__':
    main()
