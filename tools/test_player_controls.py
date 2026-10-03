#!/usr/bin/env python3
"""Independent exact controls composition corpus; no production PC oracle.

Frozen direct Java mouse/look fields decide their corresponding projections.
Actual KeyboardInput supplies logical movement samples. Fraction RN-even helpers
compose the declared packet contract, including its explicit release/drain policy.
This runner never invokes a Bend compiler or kernel; the parent builds the harness.
"""
from __future__ import annotations
import argparse
import collections
import copy
import hashlib
import json
from pathlib import Path
import random
import subprocess
import time
from fractions import Fraction

import reference_mouse_input_probe as MP
import reference_player_look_probe as LP
import test_player_input as K
import test_player_look as L
import test_mouse_input as M
from reference_inventory import fingerprint
from reference_model_probe import verified_client_classpath

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'build/player-controls-reference-cache'
BINARY = ROOT / 'build/player-controls-tests'
REFERENCE_EVIDENCE = ROOT / 'evidence/player-controls-reference.json'
NATIVE_EVIDENCE = ROOT / 'evidence/player-controls-native.json'
DEFAULT_BINDINGS = [119, 115, 97, 100, 32, 65592, 65595]
DEFAULT_LOOK = [0x41200000, 0x41a00000, 0x41f00000, 0x42200000]
DEFAULT_MOUSE = [0, 0, 0, 0, False]
DEFAULT_OPTIONS = [0x3fe0000000000000, False, False, False, False]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def controller(mask=0, look=None, mouse=None, options=None):
    return {'buttons': mask, 'look': list(DEFAULT_LOOK if look is None else look),
            'mouse': list(DEFAULT_MOUSE if mouse is None else mouse),
            'options': list(DEFAULT_OPTIONS if options is None else options)}


def controller_words(value):
    return [value['buttons'], *value['look'], *M.state_words(value['mouse']), *M.options_words(value['options'])]


def packet(actions=(), focused=True, captured=True):
    return {'focused': bool(focused), 'captured': bool(captured), 'actions': [list(a) for a in actions]}


def key(code, down, captured=True):
    return [1, code, int(down), int(captured), 0, 0]


def look(dx, dy, captured=True):
    return [2, dx, dy, int(captured), 0, 0]


RELEASE = [0, 0, 0, 0, 0, 0]


def widen(raw):
    assert L.finite32(raw)
    return M.round64(L.exact(raw, 32), bool(raw & L.F32_SIGN))


def widenable(raw):
    return L.finite64(raw) and widen(L.narrow(raw)) == raw


def keyboard(mask, records):
    result = list(map(int, records['tick', mask].split('|')))
    assert len(result) == 4 and result[0] == mask
    return result


def success(value, records):
    return {'ok': True, 'controller': controller_words(value), 'keyboard': keyboard(value['buttons'], records)}


def failure(original, family, detail):
    return {'ok': False, 'error': {'family': family, **detail}, 'retained_controller': controller_words(original)}


def initial_error(value):
    error = M.state_error(value['mouse']) or M.options_error(value['options'])
    if error:
        return 'Mouse', error
    for field, raw in enumerate(value['look']):
        if not L.finite32(raw):
            return 'Look', {'kind': 'InvalidState', 'field': field}
    return None


def release_raw(value):
    result = copy.deepcopy(value)
    result['buttons'] = 0
    result['mouse'][2:5] = [0, 0, True]
    return result


def apply_expected(original, bindings, frame, records):
    prior_error = initial_error(original)
    if prior_error:
        return failure(original, *prior_error), copy.deepcopy(original), None
    result = copy.deepcopy(original)
    for action in frame['actions']:
        tag, a, b, captured, d, e = action
        if tag == 0:
            result = release_raw(result)
        elif tag == 1:
            if captured:
                for bit, code in enumerate(bindings):
                    if code == a:
                        result['buttons'] = result['buttons'] | (1 << bit) if b else result['buttons'] & ~(1 << bit)
        elif tag == 2:
            for field, raw in ((2, a), (3, b)):
                if not L.finite32(raw):
                    return failure(original, 'Mouse', {'kind': 'InvalidMove', 'field': field}), copy.deepcopy(original), None
            if captured:
                state = result['mouse']
                output = M.move_raw(state, [state[0], state[1], widen(a), widen(b), True], True, True)
                for field, raw in enumerate(output[2:4]):
                    if not L.finite64(raw):
                        return failure(original, 'Mouse', {'kind': 'NonFiniteAccumulation', 'field': field}), copy.deepcopy(original), None
                result['mouse'] = output
        else:
            assert tag in (3, 4, 5, 6), 'unknown fixture action'
    # The drain and final focus/capture gates are the declared wrapper contract;
    # the actual private Java turn only supplies scaling and angle observations.
    delta = None
    if frame['focused'] and frame['captured']:
        delta = M.scaled(result['mouse'], result['options'])
        for field, raw in enumerate(delta):
            if not L.finite64(raw):
                return failure(original, 'Mouse', {'kind': 'NonFiniteDeltas', 'field': field}), copy.deepcopy(original), None
        output = L.rational_turn(result['look'], *delta)
        for field, raw in enumerate(output):
            if not L.finite32(raw):
                return failure(original, 'Look', {'kind': 'NonFiniteResult', 'field': field}), copy.deepcopy(original), delta
        result['look'] = output
    result['mouse'] = M.clear(result['mouse'])
    return success(result, records), result, delta


def packet_words(frame):
    return [int(frame['focused']), int(frame['captured']), len(frame['actions']), *[word for action in frame['actions'] for word in action]]


def request_words(case):
    values = [case['mode'], *controller_words(case['initial'])]
    if case['mode'] != 1:
        values.extend(case['bindings'])
        if case['mode'] == 2:
            values.append(len(case['packets']))
        for frame in case['packets']:
            values.extend(packet_words(frame))
    return values


def make_case(identity, category, initial, bindings, frames, records, mode=0, origin=None):
    state = copy.deepcopy(initial)
    reports = []
    deltas = []
    if mode == 1:
        state = release_raw(state)
        reports.append(success(state, records))
    else:
        for frame in frames:
            report, state, delta = apply_expected(state, bindings, frame, records)
            reports.append(report)
            deltas.append(delta)
    case = {'id': identity, 'category': category, 'mode': mode, 'initial': initial,
            'bindings': list(bindings), 'packets': list(frames),
            'expected': reports if mode == 2 else reports[0], 'expected_turn_deltas': deltas}
    if origin:
        case['origin'] = origin
    assert len(controller_words(initial)) == 20
    assert all(0 <= word <= 0xffffffff for word in request_words(case))
    return case


def reference_corpus(mouse_data, look_data, unit_sensitivity, records):
    cases = []
    checks = collections.Counter()
    for fixture, observed in zip(mouse_data['inputs'], mouse_data['observations']['cases'], strict=True):
        if fixture['category'] != 'two-move-native-pipeline':
            continue
        events = fixture['events'][:2]
        deltas = [[int(event[name], 16) for name in ('relative_x_f64_bits', 'relative_y_f64_bits')] for event in events]
        if not all(widenable(raw) for pair in deltas for raw in pair):
            checks['two_move_not_exact_f32_widenable'] += 1
            continue
        initial = fixture['initial']
        value = controller(look=list(map(lambda x: int(x, 16), initial['state_f32_bits'])),
                           mouse=[*map(lambda x: int(x, 16), initial['mouse_f64_bits']), initial['ignore_first_move']],
                           options=[int(initial['sensitivity_f64_bits'], 16), initial['invert_x'], initial['invert_y'], False, False])
        frame = packet([look(L.narrow(dx), L.narrow(dy)) for dx, dy in deltas])
        case = make_case('java_mouse/' + fixture['id'], 'actual-two-move-composition', value, DEFAULT_BINDINGS, [frame], records, origin=fixture['id'])
        final = observed['steps'][-1]
        expected_angles = list(map(lambda x: int(x, 16), final['state_f32_bits']))
        assert case['expected']['ok'] and case['expected']['controller'][1:5] == expected_angles
        player_trace = final['trace'][1]
        assert case['expected_turn_deltas'][0] == [int(player_trace[name], 16) for name in ('dx_f64_bits', 'dy_f64_bits')]
        # Relative convenience preserves initial absolute position, while the
        # real Java onMove fixture also assigns its supplied absolute positions.
        state = value['mouse'][:]
        for dx, dy in deltas:
            state = M.move_raw(state, [state[0], state[1], dx, dy, True], True, True)
        assert state[2:] == [*map(lambda x: int(x, 16), observed['steps'][1]['mouse_f64_bits'][2:]), observed['steps'][1]['ignore_first_move']]
        checks['actual_two_move_raw_deltas_angles_accumulation'] += 1
        cases.append(case)
    admissible = []
    for fixture, observed in zip(look_data['inputs'], look_data['observations']['cases'], strict=True):
        state = list(map(lambda x: int(x, 16), fixture['input']['state_f32_bits']))
        delta = [int(fixture['input'][name], 16) for name in ('dx_f64_bits', 'dy_f64_bits')]
        if all(L.finite32(v) for v in state) and all(L.finite64(v) for v in delta):
            admissible.append((fixture, observed, state, delta))
    # Initial semantics, signed zero/remainder/boundaries first; then seeded
    # samples across the complete pinned corpus. No decimal expectation decides.
    selected = admissible[:128]
    chosen = {fixture['id'] for fixture, _, _, _ in selected}
    rng = random.Random(0x26_03_5043)
    remainder = [row for row in admissible if row[0]['id'] not in chosen]
    selected.extend(rng.sample(remainder, 128))
    for fixture, observed, angles, delta in selected:
        value = controller(look=angles, mouse=[0, 0, *delta, False], options=[unit_sensitivity, False, False, False, False])
        case = make_case('java_look/' + fixture['id'], 'actual-entity-turn-composition', value, DEFAULT_BINDINGS, [packet()], records, origin=fixture['id'])
        raw_output = list(map(lambda x: int(x, 16), observed['steps'][0]['state_f32_bits']))
        rational_output = L.rational_turn(angles, *delta)
        assert raw_output == rational_output
        assert case['expected_turn_deltas'][0] == delta
        if all(L.finite32(v) for v in raw_output):
            assert case['expected']['ok'] and case['expected']['controller'][1:5] == raw_output
        else:
            assert not case['expected']['ok'] and case['expected']['error']['family'] == 'Look'
        checks['actual_entity_turn_raw_angles'] += 1
        cases.append(case)
    return cases, dict(checks)


def explicit_corpus(records):
    cases = []
    def add(identity, category, value, actions=(), bindings=DEFAULT_BINDINGS, focused=True, captured=True, mode=0, frames=None):
        frames = [packet(actions, focused, captured)] if frames is None and mode != 1 else ([] if mode == 1 else frames)
        cases.append(make_case(identity, category, value, bindings, frames, records, mode))
    policies = [DEFAULT_BINDINGS, [9] * 7, [0, 0xffffffff, 0x80000000, 0x7fffffff, 1, 65536, 0xfffffffe]]
    for mask in range(128):
        add(f'keyboard_mask_{mask}', 'actual-keyboard-sample-all-masks', controller(mask), focused=False, captured=False)
    for policy_index, bindings in enumerate(policies):
        for mask in (0, 1, 42, 85, 127):
            for code in sorted(set(bindings + [2, 47163, 0xffffffff])):
                for down in (False, True):
                    add(f'key_{policy_index}_{mask}_{code}_{int(down)}', 'shared-high-u32-key-binding', controller(mask), [key(code, down), key(code, down)], bindings=bindings, focused=False, captured=False)
    for final_focus in (False, True):
        for final_capture in (False, True):
            for captured in (False, True):
                actions = [key(119, True, captured), look(0x3f800000, 0xbf800000, captured), key(65595, True, captured)]
                add(f'final_gates_{int(final_focus)}_{int(final_capture)}_{int(captured)}', 'action-capture-versus-final-frame-gates', controller(42), actions, focused=final_focus, captured=final_capture)
    for first in (False, True):
        actions = [look(0x3f800000, 0xbf800000, False), look(0x40000000, 0xc0400000), look(0x40800000, 0xc0a00000)]
        add(f'uncaptured_look_first_{int(first)}', 'uncaptured-look-preserves-first-discard', controller(mouse=[0, 0, 0, 0, first]), actions)
    for angles in (DEFAULT_LOOK, [0x80000000] * 4, [0, 0x43b68000, 0, 0x43b68000]):
        label = '_'.join(f'{v:08x}' for v in angles)
        value = controller(127, angles, [0x8000000000000000, 0, 0x4000000000000000, 0xc008000000000000, False])
        add('release_direct_' + label, 'pure-release-owner-preservation', value, mode=1)
        add('release_inactive_' + label, 'release-packet-preserves-angles', value, [RELEASE], focused=False, captured=False)
        add('release_active_' + label, 'release-followed-by-one-zero-turn', value, [RELEASE])
        add('empty_active_' + label, 'active-empty-normalizes-with-one-turn', controller(127, angles))
    for order, actions in enumerate(([RELEASE, key(119, True), look(0x3f800000, 0xbf800000), look(0x40000000, 0xc0000000)],
                                     [key(119, True), look(0x3f800000, 0xbf800000), RELEASE],
                                     [look(0x3f800000, 0xbf800000), RELEASE, look(0x40000000, 0xc0000000), look(0x40400000, 0xc0400000)],
                                     [RELEASE, RELEASE, key(65595, True), look(0x3f800000, 0xbf800000)])):
        add(f'release_order_{order}', 'ordered-release-key-look-composition', controller(127), actions)
    ignored = [[3, 0xffffffff, 0x80000000, 9, 1, 1], [4, 0xffffffff, 0x80000000, 1, 0, 0],
               [5, 123, 456, 0x7fc00123, 0xff800000, 1], [6, 0, 0, 1, 0, 0]]
    for index, action in enumerate(ignored):
        add(f'ignored_event_{index}', 'other-base-events-ignored-even-payload-nonfinite', controller(85), [action], focused=False, captured=False)
    for mask in range(32):
        value = controller(look=[0x80000000] * 4, mouse=[0x8000000000000000 if mask & 1 else 0,
                           0x8000000000000000 if mask & 2 else 0, 0x8000000000000000 if mask & 4 else 0,
                           0x8000000000000000 if mask & 8 else 0, bool(mask & 16)],
                           options=[0x8000000000000000 if mask & 1 else 0x3fe0000000000000, bool(mask & 2), bool(mask & 4), False, False])
        add(f'signed_zero_{mask}', 'signed-zero-controller-composition', value, [look(0x80000000 if mask & 8 else 0, 0x80000000 if mask & 16 else 0)])
    nonfinite32 = [0x7f800000, 0xff800000, 0x7fc00123, 0x7f800001]
    nonfinite64 = [0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000000123, 0x7ff0000000000001]
    for raw in nonfinite64:
        for field in range(4):
            value = controller(127)
            value['mouse'][field] = raw
            add(f'invalid_mouse_{field}_{raw:016x}', 'initial-mouse-validation', value, [RELEASE], focused=False, captured=False)
            add(f'invalid_mouse_release_{field}_{raw:016x}', 'invalid-controller-pure-release', value, mode=1)
    for raw in nonfinite32:
        for field in range(4):
            value = controller(127)
            value['look'][field] = raw
            add(f'invalid_look_{field}_{raw:08x}', 'initial-look-validation', value, [RELEASE], focused=False, captured=False)
            add(f'invalid_look_release_{field}_{raw:08x}', 'invalid-controller-pure-release', value, mode=1)
        for captured in (False, True):
            for field in range(2):
                action = look(raw if field == 0 else 0, raw if field == 1 else 0, captured)
                for release_first in (False, True):
                    actions = [key(119, True), *([RELEASE] if release_first else []), action, key(65595, True)]
                    add(f'invalid_event_{field}_{raw:08x}_{int(captured)}_{int(release_first)}', 'nonfinite-look-atomic-even-uncaptured', controller(42), actions, focused=False, captured=False)
    sensitivity_values = [0x8000000000000001, 0x3ff0000000000001, *nonfinite64]
    for raw in sensitivity_values:
        value = controller(127, options=[raw, False, False, False, False])
        add(f'invalid_sensitivity_{raw:016x}', 'initial-options-validation', value, [RELEASE], focused=False, captured=False)
        add(f'invalid_sensitivity_release_{raw:016x}', 'invalid-controller-pure-release', value, mode=1)
    for index, name in ((3, 'smooth'), (4, 'scope')):
        value = controller(127)
        value['options'][index] = True
        add('unsupported_' + name, 'initial-options-validation', value, [RELEASE], focused=False, captured=False)
        add('unsupported_release_' + name, 'invalid-controller-pure-release', value, mode=1)
    # Explicit precedence collisions, justified by the frozen public contract.
    value = controller(127, look=[0x7fc00001] * 4, mouse=[0x7ff8000000000001] * 4 + [True], options=[0x7ff8000000000001, True, True, True, True])
    for field in range(4):
        value['mouse'][field] = 0
        add(f'precedence_mouse_{field}', 'initial-error-precedence', copy.deepcopy(value), [RELEASE], focused=False, captured=False)
    value['options'][0] = 0x3fe0000000000000
    add('precedence_smooth', 'initial-error-precedence', copy.deepcopy(value), focused=False, captured=False)
    value['options'][3] = False
    add('precedence_scope', 'initial-error-precedence', copy.deepcopy(value), focused=False, captured=False)
    value['options'][4] = False
    for field in range(4):
        add(f'precedence_look_{field}', 'initial-error-precedence', copy.deepcopy(value), focused=False, captured=False)
        value['look'][field] = 0
    add('event_dx_precedes_dy', 'event-error-precedence', controller(), [look(0x7fc00001, 0xff800000, False)], focused=False, captured=False)
    for sensitivity in (0x3fe0000000000000, 0x3ff0000000000000):
        for sign in (0, 1):
            value = controller(42, mouse=[0, 0, 0x7fefffffffffffff | sign << 63, 0, False], options=[sensitivity, False, False, False, False])
            add(f'overflow_{sensitivity:016x}_{sign}', 'atomic-final-mouse-or-look-overflow', value, [key(119, True)])
    # Zero magnitude deltas remain exact, but a previous finite yaw sum can
    # overflow after float narrowing and multiplication in the one final turn.
    add('past_yaw_overflow', 'atomic-final-look-overflow', controller(42, look=[0, 0, 0x7f7fffff, 0], mouse=[0, 0, widen(0x7f7fffff), 0, False], options=[0, False, False, False, False]), [key(119, True)])
    for bits in (0, 0x80000000, 1, 0x80000001, 0x007fffff, 0x00800000, 0x3f7fffff,
                 0x3f800000, 0x3f800001, 0x7f7fffff, 0xff7fffff):
        for ix, iy in ((False, False), (True, True)):
            add(f'f32_boundary_{bits:08x}_{int(ix)}', 'f32-widen-scale-turn-boundaries', controller(options=[0x3fe0000000000000, ix, iy, False, False]), [look(bits, bits)])
    rng = random.Random(0x26_03_4350)
    for i in range(128):
        raw32 = lambda: rng.randrange(0, 0x7f800000) | rng.getrandbits(1) << 31
        actions = [key(rng.choice(policies[i % 3] + [47163]), rng.getrandbits(1), rng.getrandbits(1)),
                   look(raw32(), raw32(), rng.getrandbits(1)),
                   *([RELEASE] if i % 4 == 0 else []), look(raw32(), raw32(), rng.getrandbits(1))]
        value = controller(rng.randrange(128), mouse=[0, 0, 0, 0, bool(rng.getrandbits(1))],
                           options=[int(MP.b64(rng.random()), 16), bool(rng.getrandbits(1)), bool(rng.getrandbits(1)), False, False])
        add(f'random_packet_{i}', 'seeded-mixed-action-packets', value, actions, bindings=policies[i % 3], focused=bool(rng.getrandbits(1)), captured=bool(rng.getrandbits(1)))
    for chain in range(64):
        bindings = policies[chain % 3]
        frames = []
        for step in range(8):
            actions = [key(rng.choice(bindings + [47163]), rng.getrandbits(1), rng.getrandbits(1)),
                       look(L.round32(Fraction(rng.randrange(-10000, 10001), 8)), L.round32(Fraction(rng.randrange(-10000, 10001), 8)), rng.getrandbits(1))]
            if step % 3 == 0:
                actions.insert(0, RELEASE)
            if step == 5:
                actions.extend((key(bindings[0], True), look(0x7fc00123, 0, False)))
            frames.append(packet(actions, bool(rng.getrandbits(1)), bool(rng.getrandbits(1))))
        add(f'sequential_packets_{chain}', 'genuine-state-carrying-sequential-packets', controller(look=[0x80000000] * 4, mouse=[0, 0, 0, 0, True]), bindings=bindings, mode=2, frames=frames)
    add('packet4096', 'harness-supported-long-key-packet', controller(85), [key(0xffffffff, bool(i & 1)) for i in range(4096)], bindings=policies[2], focused=False, captured=False)
    add('packet64', 'harness-supported-max-sequential-packets', controller(127), mode=2,
        frames=[packet([key(119, bool(i & 1)), *([RELEASE] if i % 7 == 0 else [])], False, False) for i in range(64)])
    add('empty_sequence', 'harness-supported-empty-sequence', controller(127), mode=2, frames=[])
    return cases


def oracle_preparation():
    CACHE.mkdir(parents=True, exist_ok=True)
    mouse_data = json.loads((ROOT / 'reference/mouse_input.json').read_text())
    look_data = json.loads((ROOT / 'reference/player_look.json').read_text())
    MP.validate(mouse_data)
    LP.validate(look_data)
    # Helpers must continue to agree with all finite recorded production rows.
    _, _, look_checks, _ = L.reference_cases(look_data)
    _, _, mouse_checks = M.reference_cases(mouse_data)
    prior_root = K.ROOT
    try:
        K.ROOT = CACHE
        records, keyboard_evidence = K.oracle()
    finally:
        K.ROOT = prior_root
    unit_sensitivity = M.round64((Fraction(1, 2) - L.exact(0x3fc99999a0000000, 64)) / L.exact(0x3fe3333340000000, 64))
    assert M.scale(unit_sensitivity) == 0x3ff0000000000000
    fixture = copy.deepcopy(MP.fixtures()[0])
    fixture['id'] = 'player_controls_exact_unit_scale'
    fixture['initial']['sensitivity_f64_bits'] = f'{unit_sensitivity:016x}'
    classpath, _ = verified_client_classpath()
    prior_cache = MP.CACHE
    try:
        MP.CACHE = CACHE / 'unit-scale-mouse-probe'
        unit_observations, unit_run = MP.execute([fixture], classpath, 'unit-scale')
    finally:
        MP.CACHE = prior_cache
    trace = unit_observations['cases'][0]['steps'][0]['trace']
    assert [item['method'] for item in trace] == ['Tutorial.onMouse', 'LocalPlayer.turn']
    assert all(item[name] == '3ff0000000000000' for item in trace for name in ('dx_f64_bits', 'dy_f64_bits'))
    cases, actual_checks = reference_corpus(mouse_data, look_data, unit_sensitivity, records)
    cases.extend(explicit_corpus(records))
    failed = [case for case in cases if case['mode'] == 0 and not case['expected']['ok']]
    for case in failed:
        if initial_error(case['initial']) is None:
            cases.append(make_case(case['id'] + '/retained-recovery', 'atomic-failure-and-retained-owner-recovery',
                                   case['initial'], case['bindings'], [*case['packets'], packet(focused=False, captured=False)], records, mode=2))
    assert len(cases) == len({case['id'] for case in cases})
    raw_cases = MP.canonical(cases)
    (CACHE / 'corpus.json').write_bytes(raw_cases)
    evidence = {'status': 'passed', 'pin': '26.3', 'confidence': 'high within the stated neutral packet-composition fixture corpus',
                'scope': 'Independent expected composition from public packet contract, actual logical KeyboardInput samples, direct frozen MouseHandler relative accumulation/scaling and Entity.turn raw fields, exact Fraction IEEE RN-even operations',
                'reference_files': {path: fingerprint(ROOT / path) for path in ('reference/mouse_input.json', 'reference/player_look.json')},
                'helper_identities': {path: fingerprint(ROOT / path) for path in ('tools/reference_mouse_input_probe.py', 'tools/reference_player_look_probe.py', 'tools/test_mouse_input.py', 'tools/test_player_look.py', 'tools/test_player_input.py')},
                'mouse_observations_sha256': mouse_data['observations_sha256'], 'look_observations_sha256': look_data['observations_sha256'],
                'full_frozen_reference_rational_checks': {'look': look_checks, 'mouse': mouse_checks},
                'actual_composition_checks': actual_checks, 'actual_keyboard': keyboard_evidence,
                'actual_unit_scale_sensitivity_f64_bits': f'{unit_sensitivity:016x}', 'actual_unit_scale_observation': unit_observations,
                'actual_unit_scale_java_run': unit_run, 'corpus_sha256': sha(raw_cases), 'cases': len(cases),
                'categories': dict(collections.Counter(case['category'] for case in cases)),
                'reports': sum(len(case['expected']) if case['mode'] == 2 else 1 for case in cases),
                'bounded_fixture_limits': 'Native harness packet count<=64 and action count<=4096; these are harness bounds, not claimed pure API limits',
                'oracle_boundary': 'No whole Minecraft controller/packet/OS lifecycle is claimed. Base.Look has only relative F32 deltas, so absolute mouse position is retained by the declared relative adapter. Frame-final gate/drain, release, binding updates, atomic failure and initial validation precedence are declared composition policy. Actual private Java turn does not execute handleAccumulatedMovement.',
                'unsupported': ['smooth-camera/scoping branches', 'real OS key/mouse/focus/capture/window handling', 'GUI routing and complete mouse frame timer', 'gameplay movement or network integration'],
                'reproduce': 'python3 tools/test_player_controls.py --oracle-only', 'runner': fingerprint(Path(__file__))}
    REFERENCE_EVIDENCE.write_text(json.dumps(evidence, indent=2, sort_keys=True) + '\n')
    return cases, records, evidence


def native_run(cases, binary):
    records = []
    failures = []
    pending = []
    pending_bytes = 0
    def flush():
        nonlocal pending, pending_bytes
        if not pending:
            return
        arguments = ['|'.join(map(str, request_words(case))) for case in pending]
        command = [str(binary), '--gpu', 'off', '--threads', '1', '--', *arguments]
        start = time.monotonic()
        run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=300)
        elapsed = time.monotonic() - start
        if run.returncode:
            raise RuntimeError(f'native controls process failed ({run.returncode}): {run.stderr[-6000:]}{run.stdout[-2000:]}')
        lines = run.stdout.splitlines()
        wanted = [(case, index, report) for case in pending for index, report in enumerate(
            case['expected'] if case['mode'] == 2 else [case['expected']])]
        if len(lines) != len(wanted):
            raise AssertionError(('native response count', len(lines), len(wanted), run.stdout[-2000:]))
        for (case, index, expected), line in zip(wanted, lines, strict=True):
            actual = json.loads(line)
            if actual != expected:
                failures.append({'id': case['id'], 'packet_index': index, 'expected': expected, 'actual': actual})
        records.append({'cases': len(pending), 'seconds': round(elapsed, 6), 'stdout_sha256': sha(run.stdout.encode()),
                        'reports': len(wanted),
                        'stderr_bytes': len(run.stderr.encode()), 'stderr_sha256': sha(run.stderr.encode()),
                        'first_case': pending[0]['id'], 'last_case': pending[-1]['id']})
        pending, pending_bytes = [], 0
    for case in cases:
        size = len('|'.join(map(str, request_words(case))).encode()) + 1
        if pending and (len(pending) >= 32 or pending_bytes + size > 100000):
            flush()
        pending.append(case)
        pending_bytes += size
    flush()
    return records, failures


def malformed_requests():
    """Host fixture admission, separate from the pure controller contract."""
    base = controller_words(controller())
    prefix = [0, *base, *DEFAULT_BINDINGS]
    requests = []
    def add(identity, words):
        requests.append((identity, '|'.join(map(str, words))))
    for value in ('', 'x', '-1', '4294967296', '0|1', '0|1|not-a-word'):
        requests.append(('non_u32_or_incomplete/' + value, value))
    add('truncated_controller', [0, *base[:19]])
    add('invalid_mode', [3, *base, *DEFAULT_BINDINGS, 0, 0, 0])
    add('release_trailing_word', [1, *base, 0])
    add('packet_trailing_word', [*prefix, 0, 0, 0, 0])
    bad = base[:]
    bad[0] = 128
    add('button_mask_bounds', [1, *bad])
    for index in (13, 16, 17, 18, 19):
        bad = base[:]
        bad[index] = 2
        add(f'controller_bool_{index}', [1, *bad])
    for focused, captured in ((2, 0), (0, 2)):
        add(f'packet_bool_{focused}_{captured}', [*prefix, focused, captured, 0])
    for count in (4097, 65536, 0x7fffffff, 0xffffffff):
        add(f'action_count_bomb_{count}', [*prefix, 0, 0, count])
    for count in (65, 65536, 0x7fffffff, 0xffffffff):
        add(f'packet_count_bomb_{count}', [2, *base, *DEFAULT_BINDINGS, count])
    add('truncated_action', [*prefix, 0, 0, 1, 2, 0, 0, 1, 0])
    add('unknown_action_tag', [*prefix, 0, 0, 1, 7, 0, 0, 0, 0, 0])
    valid = [RELEASE, key(0xffffffff, True), look(0x3f800000, 0xbf800000),
             [3, 0xffffffff, 0x80000000, 0xffffffff, 1, 1], [4, 123, 456, 1, 0, 0],
             [5, 123, 456, 0x7fc00123, 0xff800000, 1], [6, 0, 0, 1, 0, 0]]
    padding = {0: (1, 2, 3, 4, 5), 1: (4, 5), 2: (4, 5), 4: (4, 5), 6: (1, 2, 4, 5)}
    boolean_fields = {1: (2, 3), 2: (3,), 3: (4, 5), 4: (3,), 5: (5,), 6: (3,)}
    for tag, fields in padding.items():
        for field in fields:
            action = valid[tag][:]
            action[field] = 1
            add(f'action_padding_{tag}_{field}', [*prefix, 0, 0, 1, *action])
    for tag, fields in boolean_fields.items():
        for field in fields:
            action = valid[tag][:]
            action[field] = 2
            add(f'action_bool_{tag}_{field}', [*prefix, 0, 0, 1, *action])
    first_packet = packet([key(119, True), look(0x3f800000, 0x3f800000)])
    # Both second-packet parse errors must be detected before the valid first
    # packet can emit or publish a controller report.
    add('complete_sequence_rejected_before_output/padding', [2, *base, *DEFAULT_BINDINGS, 2, *packet_words(first_packet), 1, 1, 1, 2, 0, 0, 1, 1, 0])
    add('complete_sequence_rejected_before_output/truncation', [2, *base, *DEFAULT_BINDINGS, 2, *packet_words(first_packet), 1, 1, 1, 1, 119])
    add('complete_sequence_rejected_before_output/trailing', [2, *base, *DEFAULT_BINDINGS, 2, *packet_words(first_packet), 0, 0, 0, 0])
    return requests


def native_malformed(binary):
    results = []
    for identity, request in malformed_requests():
        start = time.monotonic()
        run = subprocess.run([str(binary), '--gpu', 'off', '--threads', '1', '--', request], cwd=ROOT,
                             capture_output=True, text=True, timeout=30)
        assert run.returncode == 2 and run.stdout == '' and 'invalid controller packet fixture' in run.stderr, (
            identity, run.returncode, run.stdout, run.stderr)
        results.append({'id': identity, 'exit_code': run.returncode, 'stdout_bytes': 0,
                        'stderr_sha256': sha(run.stderr.encode()), 'seconds': round(time.monotonic() - start, 6)})
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--oracle-only', action='store_true')
    parser.add_argument('--skip-build', action='store_true', help='Compatibility flag: this runner never builds or checks Bend source')
    parser.add_argument('--binary', type=Path, default=BINARY)
    args = parser.parse_args()
    start = time.monotonic()
    cases, records, reference = oracle_preparation()
    if args.oracle_only:
        print(json.dumps({'status': 'passed', 'cases': len(cases), 'reports': reference['reports'], 'actual_composition_checks': reference['actual_composition_checks'], 'malformed_protocol_cases_prepared': len(malformed_requests()), 'corpus_sha256': reference['corpus_sha256']}))
        return
    if not args.binary.is_file():
        raise RuntimeError('Parent-built controls harness unavailable; use --oracle-only for Java/reference preparation')
    # Dependency scanning supplies hashes only; it does not enter the oracle.
    identities = L.imports([ROOT / 'src/player_controls.bend', ROOT / 'tests/player_controls.bend'])
    binary_before = fingerprint(args.binary)
    batches, failures = native_run(cases, args.binary)
    # Every failed single request is followed by an independent valid request
    # in the same native process; valid-owner failures also have true sequences.
    bad = [case for case in cases if case['mode'] == 0 and not case['expected']['ok']]
    good = make_case('successful_same_process_recovery', 'recovery-control', controller(), DEFAULT_BINDINGS, [packet(focused=False, captured=False)], records)
    recovery_cases = [entry for case in bad for entry in (case, good)]
    recovery_batches, recovery_failures = native_run(recovery_cases, args.binary)
    failures.extend(recovery_failures)
    malformed = native_malformed(args.binary)
    assert identities == L.imports([ROOT / 'src/player_controls.bend', ROOT / 'tests/player_controls.bend']), 'source generation changed during native run'
    assert binary_before == fingerprint(args.binary), 'native binary changed during run'
    assert reference['reference_files'] == {path: fingerprint(ROOT / path) for path in reference['reference_files']}, 'frozen Java references changed during run'
    assert reference['helper_identities'] == {path: fingerprint(ROOT / path) for path in reference['helper_identities']}, 'oracle helper generation changed during run'
    evidence = {'status': 'failed' if failures else 'passed', 'pin': '26.3', 'cases': len(cases), 'reports': reference['reports'],
                'corpus_sha256': reference['corpus_sha256'], 'categories': reference['categories'],
                'same_process_failed_request_recoveries': len(bad), 'native_batches': batches, 'recovery_batches': recovery_batches,
                'malformed_complete_protocol': malformed,
                'failures': failures, 'source_identities': identities, 'binary': binary_before, 'runner': fingerprint(Path(__file__)),
                'binary_path': str(args.binary.resolve()),
                'reference_evidence': fingerprint(REFERENCE_EVIDENCE), 'seconds_including_reference_preparation_and_native_io': round(time.monotonic() - start, 6),
                'confidence': 'high for recorded neutral atomic controls composition and genuine sequential/native owner retention if passed',
                'kernel_boundary': 'No compiler, ordinary check or independent kernel invoked by this runner; source/check/kernel evidence is parent-owned',
                'scope': reference['scope'], 'oracle_boundary': reference['oracle_boundary'], 'unsupported': reference['unsupported'],
                'reproduce': 'python3 tools/test_player_controls.py --skip-build'}
    NATIVE_EVIDENCE.write_text(json.dumps(evidence, indent=2, sort_keys=True) + '\n')
    if failures:
        print(json.dumps({'status': 'failed', 'failure_count': len(failures), 'first_failures': failures[:3]}))
        raise SystemExit(1)
    print(json.dumps({'status': 'passed', 'cases': len(cases), 'reports': reference['reports'], 'same_process_failed_request_recoveries': len(bad), 'corpus_sha256': reference['corpus_sha256']}))


if __name__ == '__main__':
    main()
