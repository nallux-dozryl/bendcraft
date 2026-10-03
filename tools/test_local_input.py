#!/usr/bin/env python3
"""Exact Bend control/input phases against direct pinned client observations.

Python only serializes raw observations and compares results. It does not
compute keyboard, sprint, input modification, jumping or travel expectations.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

from reference_inventory import canonical, fingerprint
from test_geometry import run, sha, word_vector

ROOT = Path(__file__).resolve().parents[1]
BEND = Path('/Users/chuah/.bend/bin/bend')
BINARY = ROOT / 'build/local-input-tests'
TABLE = ROOT / 'generated/reference_mth_sin.f32'
FIXTURE = ROOT / 'reference/local_input.json'
SOURCES = ['src/local_input.bend', 'tests/local_input.bend', 'src/player_input.bend',
           'src/player_tick.bend', 'src/travel.bend', 'src/locomotion.bend',
           'src/movement.bend', 'src/geometry.bend', 'src/f64.bend']


def source_hashes():
    return {path: sha(ROOT / path) for path in SOURCES}


def signed(word):
    value = int(word)
    return value if value < 2**31 else value - 2**32


def f32(word):
    return f'{int(word):08x}'


def f64(words):
    assert len(words) % 2 == 0
    return [f'{int(words[i]):08x}{int(words[i+1]):08x}'
            for i in range(0, len(words), 2)]


def mask(keys):
    assert len(keys) == 7
    return sum(int(value) << i for i, value in enumerate(keys))


def keys(word):
    return [bool(int(word) & (1 << i)) for i in range(7)]


def local_state(words):
    assert len(words) == 9
    return {'key_presses': keys(words[0]),
            'move_vector_f32_bits': [f32(x) for x in words[1:3]],
            'sprint_trigger_time': signed(words[3]), 'crouching': bool(int(words[4])),
            'bob_f32_bits': [f32(x) for x in words[5:9]]}


def player_state(words):
    assert len(words) == 39
    return {'position': f64(words[:6]), 'box': f64(words[6:18]),
            'velocity': f64(words[18:24]), 'width_f32_bits': f32(words[24]),
            'height_f32_bits': f32(words[25]),
            'flags': [bool(int(x)) for x in words[26:30]],
            'input_f32_bits': [f32(x) for x in words[30:33]],
            'jumping': bool(int(words[33])), 'jump_delay': signed(words[34]),
            'jump_trigger': signed(words[35]), 'needs_sync': bool(int(words[36])),
            'stored_speed_f32_bits': f32(words[37]), 'head_yaw_f32_bits': f32(words[38])}


def parse(line):
    id, kind, *words = line.split('|')
    if kind == 'error':
        return id, {'error': '|'.join(words)}
    if kind == 'keyboard':
        assert len(words) == 4
        return id, {'key_presses': keys(words[0]),
                    'move_vector_f32_bits': [f32(x) for x in words[1:3]],
                    'has_forward_impulse': bool(int(words[3]))}
    if kind == 'vector':
        assert len(words) == 5
        return id, {'square_f32_bits': [f32(x) for x in words[:2]],
                    'distance_to_unit_square_f32_bits': f32(words[2]),
                    'length_f32_bits': f32(words[3]),
                    'length_squared_f32_bits': f32(words[4])}
    if kind == 'modify':
        assert len(words) == 2
        return id, [f32(x) for x in words]
    if kind == 'bob':
        assert len(words) == 1
        return id, f32(words[0])
    if kind == 'predicates':
        assert len(words) == 2
        return id, {'sprinting_possible': bool(int(words[0])),
                    'can_start_sprinting': bool(int(words[1]))}
    if kind == 'controls':
        assert len(words) == 12
        count, bits = int(words[10]), int(words[11])
        return id, {**local_state(words[:9]), 'sprinting': bool(int(words[9])),
                    'sprint_updates': [bool(bits & (1 << i)) for i in range(count-1, -1, -1)]}
    if kind in ['applied', 'prepared']:
        assert len(words) == (48 if kind == 'applied' else 56), (kind, len(words))
        value = {'local': local_state(words[:9]), 'player': player_state(words[9:48])}
        if kind == 'prepared':
            value.update(travel_input=f64(words[48:54]),
                         jump_attempted=bool(int(words[54])), jumped=bool(int(words[55])))
        return id, value
    raise AssertionError((id, kind, words))


def request(id, op, words):
    return '|'.join([id, op, *[str(value & 0xffffffff) for value in words]])


def local_words(value, sprinting=None):
    words = [mask(value['key_presses']), *[int(x, 16) for x in value['move_vector_f32_bits']],
             value['sprint_trigger_time'], int(value['crouching']),
             *[int(x, 16) for x in value['bob_f32_bits']]]
    if sprinting is not None:
        words.append(int(sprinting))
    return words


def player_words(value):
    return [*[int(x) for x in word_vector(value['position'] + value['box'] + value['velocity'])],
            int(value['width_f32_bits'], 16), int(value['height_f32_bits'], 16),
            *map(int, value['flags']), *[int(x, 16) for x in value['input_f32_bits']],
            int(value['jumping']), value['jump_delay'], value['jump_trigger'],
            int(value['needs_sync']), int(value['stored_speed_f32_bits'], 16),
            int(value['head_yaw_f32_bits'], 16)]


def phase_request(id, operation, local, player, context_words, sprinting):
    return ';'.join([id + '|' + operation,
                     '|'.join(str(x & 0xffffffff) for x in local_words(local, sprinting)),
                     '|'.join(str(x & 0xffffffff) for x in player_words(player)),
                     '|'.join(str(x & 0xffffffff) for x in context_words)])


def compare(actual, expected):
    """Raw equality, except Java's unspecified NaN payload class in helper calls."""
    if isinstance(expected, dict):
        assert isinstance(actual, dict)
        return all(key in actual and compare(actual[key], value) for key, value in expected.items())
    if isinstance(expected, list):
        return isinstance(actual, list) and len(actual) == len(expected) and all(
            compare(a, e) for a, e in zip(actual, expected, strict=True))
    if isinstance(expected, str) and len(expected) == 8 and re.fullmatch('[0-9a-f]{8}', expected):
        raw = int(expected, 16)
        if raw & 0x7f800000 == 0x7f800000 and raw & 0x7fffff:
            if not isinstance(actual, str) or not re.fullmatch('[0-9a-f]{8}', actual):
                return False
            observed = int(actual, 16)
            return observed & 0x7f800000 == 0x7f800000 and bool(observed & 0x7fffff)
    return actual == expected


def run_pairs(pairs, batches, size=60):
    for start in range(0, len(pairs), size):
        chunk = pairs[start:start+size]
        result = run([BINARY, '--gpu', 'off', TABLE, *[arg for arg, expected in chunk]])
        lines = result['stdout'].splitlines()
        assert len(lines) == len(chunk), result
        for (arg, expected), line in zip(chunk, lines, strict=True):
            id, actual = parse(line)
            assert id == arg.split('|')[0] and compare(actual, expected), (id, expected, actual)
        batches.append({'requests': len(chunk), 'seconds': result['seconds']})


def project_local(value):
    return {key: value[key] for key in ['key_presses', 'move_vector_f32_bits',
            'sprint_trigger_time', 'crouching', 'bob_f32_bits']}


def project_player(value):
    keys = ['position', 'box', 'velocity', 'width_f32_bits', 'height_f32_bits',
            'input_f32_bits', 'jumping', 'jump_delay', 'jump_trigger', 'needs_sync',
            'stored_speed_f32_bits', 'head_yaw_f32_bits']
    return {**{key: value[key] for key in keys}, 'flags': value['body_flags']}


def apply_words(value, context):
    sample = context['ground_sample']
    return [*sample['position'], int(sample['friction_f32_bits'], 16),
            *[int(x) for x in word_vector([value[key] for key in
                    ['movement_speed', 'gravity', 'friction_modifier', 'air_drag_modifier']])],
            int(value['rotation_f32_bits'][0], 16), int(value['maximum_f32_bits'], 16),
            int(value['sprinting']), 0, 0,
            *[int(x) for x in word_vector([value['jump_strength']])],
            int(context['jump_factor_f32_bits'], 16), 1,
            *[int(x) for x in word_vector([value['sneaking_speed']])],
            int(value['rotation_f32_bits'][1], 16)]


def control_words(value, context, held, mode=0, prior=None, current=None):
    cache = project_local(value) if prior is None else prior
    return [*local_words(cache), int(value['sprinting'] if current is None else current), held,
            int(context['fits']['standing']), int(context['fits']['crouching']), context['food'],
            int(context['mayfly']), int(context['flying']), int(context['mobility_restricted']),
            int(value['body_flags'][1]), int(value['minor_horizontal_collision']), context['sprint_window'],
            {'STANDING': 0, 'CROUCHING': 1}.get(value['pose'], 2), mode]


def eligible_context(value, context):
    return (value['pose'] in ['STANDING', 'CROUCHING'] and not value['visually_crawling']
            and not context['mayfly'] and not context['flying']
            and not context['mobility_restricted'] and context['controlled_camera']
            and not any(context[key] for key in ['in_shallow_water', 'underwater',
                      'fall_flying', 'using_item', 'is_passenger']))


def fixture_pairs(data):
    pairs = {'keyboard': [], 'vectors': [], 'modify': [], 'bob': [], 'predicates': [],
             'apply': [], 'controls': [], 'prepare': []}
    for case in data['keyboard']:
        expected = case['expected']
        pairs['keyboard'].append((request(case['id'], 'keyboard', [case['mask']]),
            {'key_presses': expected['keys'], 'move_vector_f32_bits': expected['move_f32_bits'],
             'has_forward_impulse': expected['has_forward']}))
    for case in data['vectors']:
        expected = case['expected']
        pairs['vectors'].append((request(case['id'], 'vector', [int(x, 16) for x in case['input_f32_bits']]),
            {'square_f32_bits': expected['square_f32_bits'],
             'distance_to_unit_square_f32_bits': expected['distance_f32_bits'],
             'length_f32_bits': expected['length_f32_bits'],
             'length_squared_f32_bits': expected['length_squared_f32_bits']}))
    for case in data['receivers']:
        before, expected, context = case['before'], case['expected'], case['context']
        pairs['modify'].append((request(case['id']+':modify', 'modify',
            [*[int(x, 16) for x in before['move_vector_f32_bits']],
             *[int(x) for x in word_vector([before['sneaking_speed']])], int(before['moving_slowly'])]),
            [expected['input_f32_bits'][i] for i in [0, 2]]))
        for index, angle in [(0, 1), (1, 0)]:
            pairs['bob'].append((request(case['id']+':bob:'+str(index), 'bob',
                [int(before['bob_f32_bits'][index], 16), int(before['rotation_f32_bits'][angle], 16)]),
                expected['bob_f32_bits'][index]))
        assert expected['input_f32_bits'][1] == before['input_f32_bits'][1]
        assert expected['bob_f32_bits'][2:] == before['bob_f32_bits'][:2]
        assert expected['jumping'] == before['key_presses'][4]
        assert expected['rotation_f32_bits'] == before['rotation_f32_bits']
        assert not any(context[key] for key in ['in_shallow_water', 'underwater', 'fall_flying', 'using_item', 'is_passenger'])
        pairs['predicates'].append((request(case['id']+':predicates', 'predicates',
            [int(before['sprinting']), *[int(x, 16) for x in before['move_vector_f32_bits']],
             context['food'], int(context['mayfly']), int(context['mobility_restricted']), int(before['moving_slowly'])]),
            {'sprinting_possible': case['sprinting_possible'], 'can_start_sprinting': case['can_start_sprinting']}))
        if eligible_context(before, context):
            pairs['apply'].append((phase_request(case['id']+':apply', 'apply', project_local(before),
                project_player(before), apply_words(before, context), before['sprinting']),
                {'local': project_local(expected), 'player': project_player(expected)}))
    for case in data['ai_step']:
        for index, step in enumerate(case['steps']):
            id = case['id']+':'+str(index)
            before, context = step['before'], step['context']
            control = step['control_snapshot']
            state = control['state']
            assert not step['control_velocity_changed'], 'Push-out changes are outside current admission'
            assert state['rotation_f32_bits'] == before['rotation_f32_bits'] == step['expected']['rotation_f32_bits']
            assert state['sprinting'] == step['expected']['sprinting']
            if not eligible_context(before, context):
                continue
            pairs['controls'].append((request(id+':controls', 'controls',
                control_words(before, context, step['input']['held_mask'])),
                {**project_local(state), 'sprinting': state['sprinting'],
                 'sprint_updates': control['sprint_updates']}))
            before_input = step['before_apply_input']['state']
            after_input = step['after_input']['state']
            pairs['apply'].append((phase_request(id+':apply', 'apply', project_local(before_input),
                project_player(before_input), apply_words(state, context), state['sprinting']),
                {'local': project_local(after_input), 'player': project_player(after_input)}))
            pre = step['pre_travel']
            # Compare real raw state/vector. The extra project-only jump labels
            # have no vanilla field and are deliberately outside this equality.
            pairs['prepare'].append((phase_request(id+':prepare', 'prepare', project_local(state),
                project_player(state), apply_words(state, context), state['sprinting']),
                {'local': project_local(pre['state']), 'player': project_player(pre['state']),
                 'travel_input': pre['input']}))
    return pairs


def validation_pairs(data):
    case = next(case for case in data['ai_step'] if case['id'] == 'ai:held_forward')
    step = case['steps'][0]
    before, context = step['before'], step['context']
    base = control_words(before, context, step['input']['held_mask'])
    pairs = []
    for mode in range(1, 16):
        words = base.copy(); words[-1] = mode
        pairs.append((request('rejected:mode:'+str(mode), 'controls', words), {'error': 'mode'}))
    for mayfly, flying in [(1, 0), (0, 1), (1, 1)]:
        words = base.copy(); words[14:16] = [mayfly, flying]
        pairs.append((request('rejected:abilities:'+str(mayfly)+str(flying), 'controls', words), {'error': 'abilities'}))
    words = base.copy(); words[-2] = 2
    pairs.append((request('rejected:pose', 'controls', words), {'error': 'pose'}))
    for field, offset in enumerate([1, 2, 5, 6, 7, 8]):
        words = base.copy(); words[offset] = 0x7fc00123
        pairs.append((request('rejected:state:'+str(field), 'controls', words), {'error': 'state|'+str(field)}))
    state = step['control_snapshot']['state']
    local, player, attrs = project_local(state), project_player(state), apply_words(state, context)
    for raw in ['7ff0000000000000', 'fff0000000000000', '7ff8000000000123', 'bff0000000000000', '4000000000000000']:
        words = attrs.copy(); words[21:23] = [int(x) for x in word_vector([raw])]
        pairs.append((phase_request('rejected:sneak:'+raw, 'prepare', local, player, words, state['sprinting']), {'error': 'attribute'}))
    words = attrs.copy(); words[-1] = 0x7fc00123
    pairs.append((phase_request('rejected:pitch', 'prepare', local, player, words, state['sprinting']), {'error': 'pitch'}))
    words = attrs.copy(); words[14] = 1-int(state['sprinting'])
    pairs.append((phase_request('rejected:sprint', 'prepare', local, player, words, state['sprinting']), {'error': 'sprint'}))
    return pairs


def bounded_check(kind, timeout):
    before = source_hashes()
    argv = ([str(BEND), 'tests/local_input.bend', '-o', str(BINARY)] if kind == 'build'
            else [str(BEND), 'tests/local_input.bend', '--verdict'])
    started = time.monotonic()
    process = subprocess.Popen(argv, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, start_new_session=True)
    print(json.dumps({'job': kind, 'pid': process.pid, 'timeout_seconds': timeout}), flush=True)
    timed_out = False
    samples = []
    while True:
        remaining = timeout - (time.monotonic() - started)
        if remaining <= 0:
            timed_out = True
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                stdout, stderr = process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                stdout, stderr = process.communicate()
            break
        try:
            stdout, stderr = process.communicate(timeout=min(5, remaining))
            break
        except subprocess.TimeoutExpired:
            sample = subprocess.run(['ps', '-ax', '-o', 'pid=,pgid=,rss=,vsz=,etime='],
                                    capture_output=True, text=True, check=True)
            rows = []
            for line in sample.stdout.splitlines():
                fields = line.split()
                if len(fields) == 5 and int(fields[1]) == process.pid:
                    rows.append({'pid': int(fields[0]), 'rss_kib': int(fields[2]),
                                 'virtual_kib': int(fields[3]), 'elapsed': fields[4]})
            samples.append({'seconds': round(time.monotonic()-started, 6), 'processes': rows})
    record = {'status': 'passed' if process.returncode == 0 and not timed_out else 'inconclusive' if timed_out else 'failed',
              'command': argv, 'pid': process.pid, 'exit_code': process.returncode,
              'seconds': round(time.monotonic()-started, 6), 'timeout_seconds': timeout,
              'timed_out': timed_out, 'stdout': stdout, 'stderr': stderr,
              'memory_samples': samples,
              'memory_sample_scope': 'Process-group RSS/virtual sizes sampled every 5 seconds only while unexpectedly slow; RSS is not physical footprint or a game benchmark',
              'source_sha256': before, 'source_hashes_unchanged': source_hashes() == before,
              'compiler': fingerprint(BEND),
              'version_probe': run([BEND, 'version'])}
    if kind == 'build' and record['status'] == 'passed':
        record['binary'] = fingerprint(BINARY)
    (ROOT / f'evidence/local-input-{kind}-final.json').write_text(json.dumps(record, sort_keys=True, indent=2)+'\n')
    assert record['status'] == 'passed' and record['source_hashes_unchanged'], record
    return record


def completed(kind):
    record = json.loads((ROOT / f'evidence/local-input-{kind}-final.json').read_text())
    assert record['status'] == 'passed' and record['exit_code'] == 0 and record['source_hashes_unchanged']
    assert source_hashes() == record['source_sha256'], kind
    if kind == 'build':
        assert record['binary'] == fingerprint(BINARY)
    return record


def run_chain(data, batches):
    ticks = histories = 0
    for case in data['ai_step']:
        if not all(eligible_context(step['before'], step['context']) for step in case['steps']):
            continue
        prior = current = None
        for index, step in enumerate(case['steps']):
            id = case['id']+':chain:'+str(index)
            before, context = step['before'], step['context']
            arg = request(id+':controls', 'controls', control_words(before, context,
                step['input']['held_mask'], prior=prior, current=current))
            result = run([BINARY, '--gpu', 'off', TABLE, arg])
            name, selected = parse(result['stdout'].strip())
            control = step['control_snapshot']
            expected = {**project_local(control['state']), 'sprinting': control['state']['sprinting'],
                        'sprint_updates': control['sprint_updates']}
            assert name == id+':controls' and compare(selected, expected), (name, expected, selected)
            state = control['state']
            arg = phase_request(id+':prepare', 'prepare', project_local(selected),
                project_player(state), apply_words(state, context), selected['sprinting'])
            prepared_run = run([BINARY, '--gpu', 'off', TABLE, arg])
            name, prepared = parse(prepared_run['stdout'].strip())
            expected = {'local': project_local(step['pre_travel']['state']),
                        'player': project_player(step['pre_travel']['state']),
                        'travel_input': step['pre_travel']['input']}
            assert name == id+':prepare' and compare(prepared, expected), (name, expected, prepared)
            prior, current = prepared['local'], selected['sprinting']
            batches.append({'case': case['id'], 'chained_controller_tick': index,
                            'seconds': result['seconds']+prepared_run['seconds']})
            ticks += 1
        histories += 1
    return histories, ticks


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--kernel-only', action='store_true')
    parser.add_argument('--skip-build', action='store_true')
    parser.add_argument('--skip-checks', action='store_true')
    parser.add_argument('--reuse-checked', action='store_true')
    args = parser.parse_args()
    if args.build_only:
        print(json.dumps(bounded_check('build', 600), indent=2)); return
    if args.kernel_only:
        print(json.dumps(bounded_check('kernel', 60), indent=2)); return
    from reference_local_input_probe import verify_existing
    data = json.loads(FIXTURE.read_text())
    provenance = verify_existing(selftest=True)
    pairs = fixture_pairs(data)
    rejected = validation_pairs(data)
    checks = [] if args.skip_checks else [bounded_check('kernel', 60)]
    builds = [] if args.skip_build else [bounded_check('build', 600)]
    if args.reuse_checked:
        assert args.skip_build and args.skip_checks, 'Reuse requires both explicit skip flags'
        checks, builds = [completed('kernel')], [completed('build')]
    started = time.monotonic()
    batches = []
    for group in pairs.values():
        run_pairs(group, batches)
    run_pairs(rejected, batches)
    # A failed preparation hands its real Tables owner to a following valid
    # preparation in the same native process. Pure cache/body values remain in
    # the caller and are supplied unchanged; no world/body rollback is claimed.
    valid = pairs['prepare'][0]
    for failure in rejected:
        run_pairs([failure, valid], batches, size=2)
    histories, ticks = run_chain(data, batches)
    malformed = []
    for value in ['broken', 'bad|vector|abc', 'bad|vector|0', 'bad|unknown|0', 'bad|prepare;;;;']:
        result = run([BINARY, '--gpu', 'off', TABLE, value], required=False)
        assert result['exit_code'] == 2 and 'invalid local input' in result['stderr'], result
        malformed.append({'exit_code': result['exit_code'], 'stderr': result['stderr']})
    source = (ROOT / 'src/local_input.bend').read_text()
    assert not re.search(r'@unsafe|\bimport\s+["\']|\w!\(', source)
    record = {'status': 'passed' if not args.skip_checks or args.reuse_checked else 'native_passed_checks_skipped',
              'pin': '26.3', 'kernel_pass': not args.skip_checks or args.reuse_checked,
              'checks_reused_with_exact_source_hashes': args.reuse_checked,
              'counts': {key: len(value) for key, value in pairs.items()},
              'actual_java_ai_step_histories': data['counts']['ai_step'],
              'actual_java_ai_step_ticks': data['counts']['ai_step_ticks'],
              'chained_native_controller_histories': histories,
              'chained_native_controller_cache_ticks': ticks,
              'chain_scope': 'Native LI key/vector/timer/crouch/bob and final sprint cache feeds next control phase; next authoritative Body/PT metadata comes from direct Java observations. No native full physical tick trajectory claim.',
              'static_helper_normalize_scope': 'Generic actual Vec2.normalized observations are retained as reference only; native normalization coverage is the complete 128 KeyboardInput masks through existing frozen PI specialization.',
              'nan_comparison_scope': 'Exact raw finite/infinite/signed-zero values; static helper NaNs compare NaN class because payload sign propagation is not a portability promise.',
              'extra_jump_label_scope': 'Native project-only jump_attempted/jumped booleans are not equated to nonexistent vanilla fields; raw actual pre-travel state/vector and observed branch calls are retained.',
              'checks': checks, 'builds': builds, 'native_batches': batches,
              'explicit_rejection_cases': len(rejected), 'owner_retention_followups': len(rejected),
              'malformed_protocol': malformed,
              'native_validation_seconds': round(time.monotonic()-started, 6),
              'fixture': fingerprint(FIXTURE), 'fixture_provenance': provenance,
              'observations_sha256': data['observations_sha256'],
              'binary': fingerprint(BINARY), 'sources_sha256': source_hashes(),
              'tool_sha256': sha(Path(__file__)),
              'reference_tool_sha256': sha(ROOT / 'tools/reference_local_input_probe.py'),
              'reference_evidence_storage': 'Compact local-input-summary-v1 reports retain canonical observation/count/class/provenance hashes; full Java observations and manifests are ignored local build reports. Checked reference/local_input.json retains all fixture values.',
              'command': 'python3 tools/test_local_input.py' + (' --skip-build' if args.skip_build else '') + (' --skip-checks' if args.skip_checks else '') + (' --reuse-checked' if args.reuse_checked else ''),
              'laws': re.findall(r'^law (\w+):', source, re.M),
              'scope': data['fixture_boundary'], 'confidence': data['confidence']}
    (ROOT / 'evidence/local-input-verification.json').write_text(json.dumps(record, sort_keys=True, indent=2)+'\n')
    print(json.dumps({key: record[key] for key in ['status', 'counts', 'kernel_pass',
        'chained_native_controller_cache_ticks', 'explicit_rejection_cases', 'native_validation_seconds']}, indent=2))


if __name__ == '__main__':
    main()
