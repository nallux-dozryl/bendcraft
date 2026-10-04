#!/usr/bin/env python3
"""Compare the actual production travel/stuck/collision phases with pinned Java."""
from __future__ import annotations
import argparse, collections, copy, hashlib, json, os, pathlib, signal, subprocess, time
from reference_inventory import canonical, fingerprint, write_json
from test_geometry import word_vector
from test_movement import shape_words
from reference_player_motion_current_probe import validate

ROOT = pathlib.Path(__file__).resolve().parents[1]
BEND = pathlib.Path('/Users/chuah/.bend/bin/bend')
BINARY = ROOT / 'build/player-motion-current-tests'
FIXTURE = ROOT / 'reference/player_motion_current.json'
TABLE = ROOT / 'generated/reference_mth_sin.f32'
SOURCES = ['src/movement.bend', 'src/travel.bend', 'src/local_travel_history.bend',
           'src/player_motion_current_laws.bend', 'src/player_motion_current_proof.bend',
           'tests/player_motion_current.bend', 'tools/test_player_motion_current.py']

def request(c, op):
    v = {**c['input'], **c['observation']['actual_input']}
    fields = [c['id'], op, *word_vector(v['position']), *word_vector(v['box']),
              *word_vector(v['velocity']), str(int(v['width_f32_bits'], 16)),
              str(int(v['height_f32_bits'], 16)), *[str(int(x)) for x in v['flags']],
              *word_vector(v['input']), *[str(x & 0xffffffff) for x in c['observation']['below_position']],
              str(int(v['block_friction_f32_bits'], 16)),
              *word_vector([v[k] for k in ['movement_speed', 'gravity', 'friction_modifier', 'air_drag_modifier']]),
              str(int(v['yaw_f32_bits'], 16)), str(int(v['maximum_f32_bits'], 16)),
              *[str(int(v[k])) for k in ['sprinting', 'no_gravity', 'discard_friction']], '0',
              *word_vector(v['stuck_multiplier'])]
    return ';'.join(['|'.join(fields), shape_words(v['initial']), shape_words(v['step'])])

def values(fields):
    assert len(fields) % 2 == 0
    return [f'{int(fields[i]):08x}{int(fields[i + 1]):08x}' for i in range(0, len(fields), 2)]

def body(fields):
    assert len(fields) == 30
    return {'position': values(fields[:6]), 'box': values(fields[6:18]),
            'velocity': values(fields[18:24]), 'width_f32_bits': f'{int(fields[24]):08x}',
            'height_f32_bits': f'{int(fields[25]):08x}', 'flags': [bool(int(x)) for x in fields[26:]]}

def parse(line):
    ident, kind, *fields = line.split('|')
    if kind == 'error': return ident, {'error': '|'.join(fields)}
    if kind == 'body': return ident, body(fields)
    if kind == 'prepared':
        assert len(fields) == 8
        return ident, {'requested': values(fields[:6]), 'friction_f32_bits': f'{int(fields[6]):08x}',
                       'acceleration_f32_bits': f'{int(fields[7]):08x}'}
    assert kind == 'phase' and len(fields) == 42
    return ident, {'requested': values(fields[:6]), 'body': body(fields[6:36]),
                   'multiplier': values(fields[36:])}

def expected(c, op):
    obs = c['observation']
    if 'expected_error' in c: return {'error': c['expected_error']}
    if op == 'travel': return c['expected']
    if op == 'movement': return obs['post_move_body']
    if op == 'phase':
        return {'requested': obs['stuck_phase']['entry_request'],
                'body': obs['stuck_phase']['entry_body'], 'multiplier': obs['stuck_phase']['entry_multiplier']}
    return {'requested': obs['requested'] if op == 'prepare' else obs['stuck_phase']['entry_request'],
            'friction_f32_bits': obs['friction_f32_bits'], 'acceleration_f32_bits': obs['acceleration_f32_bits']}

def refusals(base):
    result = []
    for axis in range(3):
        for value in ['7ff0000000000000', 'fff0000000000000', '7ff8000000000123']:
            c = copy.deepcopy(base)
            c['id'] = f'refusal:multiplier-{axis}-{value}'
            c['observation']['actual_input']['stuck_multiplier'][axis] = value
            c['expected_error'] = f'movement|body|3|{axis}'
            result.append(c)
    c = copy.deepcopy(base)
    c['id'] = 'refusal:scaled-request-overflow'
    c['observation']['actual_input']['stuck_multiplier'] = ['7fefffffffffffff'] * 3
    c['observation']['actual_input']['velocity'][0] = '7fefffffffffffff'
    c['expected_error'] = 'movement|result|3|0'
    result.append(c)
    return result

def run(argv, folder, name, timeout):
    start = time.monotonic()
    process = subprocess.Popen([str(x) for x in argv], cwd=ROOT, text=True, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, start_new_session=True)
    timed_out = False
    try: stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
    (folder / (name + '.stdout')).write_text(stdout)
    (folder / (name + '.stderr')).write_text(stderr)
    try: os.killpg(process.pid, 0)
    except ProcessLookupError: group_absent = True
    else:
        group_absent = False
        os.killpg(process.pid, signal.SIGKILL)
    receipt = {'argv': [str(x) for x in argv], 'pid': process.pid, 'exit_code': process.returncode,
               'seconds': round(time.monotonic() - start, 6), 'timed_out': timed_out,
               'group_absent': group_absent, 'stdout': fingerprint(folder / (name + '.stdout')),
               'stderr': fingerprint(folder / (name + '.stderr'))}
    write_json(folder / (name + '.json'), receipt)
    assert not timed_out and process.returncode == 0 and group_absent, receipt
    return stdout, receipt

def compare(folder, name, cases, op):
    stdout, receipt = run([BINARY, '--gpu', 'off', TABLE, *[request(c, op) for c in cases]], folder, name, 60)
    lines = stdout.splitlines()
    assert len(lines) == len(cases), (name, len(lines), len(cases))
    for c, line in zip(cases, lines, strict=True):
        ident, observed = parse(line)
        assert ident == c['id'] and observed == expected(c, op), (ident, op, expected(c, op), observed)
    return receipt

def retained_build():
    receipt = json.loads((ROOT / 'evidence/player-motion-current-build.json').read_text())
    summary = receipt['build_report']
    path = pathlib.Path(receipt['folder']) / summary['full_report']['file']
    assert fingerprint(path) == summary['full_report'], 'retained build report changed'
    report = json.loads(path.read_text())
    assert fingerprint(BINARY)['sha256'] == report['binary_sha256'], 'native artifact changed'
    assert fingerprint(pathlib.Path(report['artifact']))['sha256'] == report['binary_sha256']
    for item in report['dependencies']:
        path = pathlib.Path(item['lookup'])
        assert str(path.resolve()) == item['path'], ('dependency alias changed', item['lookup'])
        actual = fingerprint(path)
        assert actual['sha256'] == item['sha256'] and actual['bytes'] == item['bytes'], ('stale native dependency', item['lookup'])
    assert report['retries'] == 0
    return {**summary, 'all_retained_dependency_hashes_checked': True, 'artifact_digest_checked': True}

def compact_receipt(folder, receipt):
    name = receipt['stdout']['file'].removesuffix('.stdout')
    return {k: receipt[k] for k in ['seconds', 'exit_code', 'timed_out', 'group_absent']} | {
        'full_receipt': fingerprint(folder / (name + '.json')),
        'argv_sha256': hashlib.sha256(canonical(receipt['argv'])).hexdigest()}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--skip-build', action='store_true')
    args = parser.parse_args()
    data = json.loads(FIXTURE.read_text())
    validate(data)
    folder = ROOT / 'build/player-motion-current' / str(time.time_ns())
    folder.mkdir(parents=True, exist_ok=False)
    pins = {p: fingerprint(ROOT / p) for p in SOURCES}
    receipts = []
    try:
        if not args.skip_build:
            _, receipt = run(['python3', ROOT / 'tools/build_native.py', ROOT / 'tests/player_motion_current.bend',
                              '-o', BINARY, '--report', folder / 'native-build.json'], folder, 'build', 180)
            receipts.append(receipt)
        build = None
        if not args.skip_build:
            report = json.loads((folder / 'native-build.json').read_text())
            build = {k: report[k] for k in ['artifact', 'binary_bytes', 'binary_sha256', 'cache_hit',
                                           'cache_key', 'emitted_c_sha256', 'identity', 'retries', 'timings']}
            build['full_report'] = fingerprint(folder / 'native-build.json')
            build['dependency_count'] = len(report['dependencies'])
            build['dependencies_sha256'] = hashlib.sha256(canonical(report['dependencies'])).hexdigest()
        else:
            build = retained_build()
        assert pins == {p: fingerprint(ROOT / p) for p in SOURCES}, 'owned source changed during build'
        if args.build_only:
            evidence = {'status': 'build-passed', 'folder': str(folder), 'receipts': receipts,
                        'build_report': build, 'sources': pins, 'binary': fingerprint(BINARY)}
            write_json(ROOT / 'evidence/player-motion-current-build.json', evidence)
            print(json.dumps({'status': evidence['status'], 'folder': str(folder)}))
            return
        for op in ['prepare', 'phase', 'stuck', 'movement', 'travel']:
            for offset in range(0, len(data['cases']), 40):
                receipts.append(compare(folder, f'{op}-{offset}', data['cases'][offset:offset + 40], op))
        failures = refusals(data['cases'][0])
        recovery = []
        for i, bad in enumerate(failures):
            good = copy.deepcopy(data['cases'][i])
            good['id'] = f'recovery:{i}'
            recovery.extend([bad, good])
        receipts.append(compare(folder, 'rejections-and-owned-table-recovery', recovery, 'travel'))
        # Comparison corruption must be detected independently of the checksum.
        corrupted = copy.deepcopy(data['cases'][0])
        corrupted['expected']['velocity'][0] = '405ec00000000000'
        try: compare(folder, 'expected-corruption-injection', [corrupted], 'travel')
        except AssertionError: corruption_rejected = True
        else: raise AssertionError('Corrupt expected body accepted')
        assert pins == {p: fingerprint(ROOT / p) for p in SOURCES}, 'owned source changed during comparison'
        evidence = {'status': 'passed', 'pin': '26.3', 'folder': str(folder), 'actual_java_cases': len(data['cases']),
                    'phase_comparisons': {op: len(data['cases']) for op in ['prepare', 'phase', 'stuck', 'movement', 'travel']},
                    'checked_rejections': len(failures), 'same_process_table_owner_recoveries': len(failures),
                    'expected_corruption_rejected': corruption_rejected,
                    'receipts': [compact_receipt(folder, receipt) for receipt in receipts],
                    'reference': fingerprint(FIXTURE), 'table': fingerprint(TABLE), 'sources': pins,
                    'binary': fingerprint(BINARY), 'build_report': build,
                    'scope': 'Actual production T.prepare, M.stuck, T.stuck, M.move and T.finish against full actual Player.travel; TH whole-owner laws are a separate kernel result.'}
        write_json(ROOT / 'evidence/player-motion-current-native.json', evidence)
        print(json.dumps({k: evidence[k] for k in ['status', 'actual_java_cases', 'phase_comparisons', 'checked_rejections', 'same_process_table_owner_recoveries']}))
    except BaseException as error:
        write_json(folder / 'failure.json', {'status': 'failed', 'error': repr(error), 'sources': pins, 'receipts': receipts})
        raise

if __name__ == '__main__': main()
