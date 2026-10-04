#!/usr/bin/env python3
"""Observe actual scheduler snapshots; host code encodes and compares, never ticks."""
from __future__ import annotations

import argparse
import collections
import copy
import hashlib
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import reference_entity_common_tick_probe as P
from build_native import Snapshot, source_graph
from reference_inventory import ROOT, canonical, fingerprint, write_json

BEND = Path('/Users/chuah/.bend/bin/bend')
SOURCE = ROOT / 'src/entity_common_tick.bend'
HARNESS = ROOT / 'tests/entity_common_tick.bend'
WORK = ROOT / 'build/entity-common-tick-verification'
BINARY = WORK / 'entity-common-tick-tests'
RECEIPT = WORK / 'native-build-full.json'
PREPARED = ROOT / 'evidence/entity-common-tick-prepared.json'
NATIVE = ROOT / 'evidence/entity-common-tick-native.json'
KERNEL = ROOT / 'evidence/entity-common-tick-kernel.json'


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def pin(path):
    path = Path(path)
    return {'path': str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path), **fingerprint(path)}


def generation():
    snapshot = Snapshot()
    source_graph(HARNESS, (BEND.resolve().parent.parent / 'bend2/base.bend').resolve(), dict(os.environ), snapshot)
    return snapshot.manifest()


def tool_pins():
    names = ['test_entity_common_tick.py', 'reference_entity_common_tick_probe.py',
             'reference_local_input_probe.py', 'reference_inventory.py',
             'reference_model_probe.py', 'build_native.py']
    return {name: pin(ROOT / 'tools' / name) for name in names}


def closure():
    return {'generation': generation(), 'tools': tool_pins(), 'reference': pin(P.OUTPUT), 'compiler': pin(BEND)}


def bound(kind, cap):
    WORK.mkdir(parents=True, exist_ok=True)
    before = closure()
    command = ([sys.executable, str(ROOT / 'tools/build_native.py'), str(HARNESS), '-o', str(BINARY),
                '--cache-dir', str(WORK / 'cache'), '--report', str(RECEIPT)] if kind == 'build' else
               [str(BEND), str(SOURCE if kind.endswith('source') else HARNESS),
                '--check-only' if kind.startswith('ordinary') else '--verdict'])
    start = time.monotonic()
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, start_new_session=True)
    print(json.dumps({'phase': kind, 'pid': process.pid, 'cap_seconds': cap}), flush=True)
    expired = False
    try:
        out, err = process.communicate(timeout=cap)
    except subprocess.TimeoutExpired:
        expired = True
        os.killpg(process.pid, signal.SIGKILL)
        out, err = process.communicate()
    stdout, stderr = WORK / (kind + '.stdout'), WORK / (kind + '.stderr')
    stdout.write_text(out)
    stderr.write_text(err)
    result = {'status': 'inconclusive' if expired else 'passed' if process.returncode == 0 else 'failed',
              'phase': kind, 'command': command, 'pid': process.pid, 'cap_seconds': cap,
              'seconds': round(time.monotonic() - start, 6), 'exit_code': process.returncode,
              'timed_out': expired, 'stdout': pin(stdout), 'stderr': pin(stderr),
              'closure': before, 'closure_sha256': digest(before), 'closure_unchanged': before == closure()}
    if kind == 'build' and result['status'] == 'passed':
        build = json.loads(RECEIPT.read_text())
        verify_build(build)
        result['build'] = build_summary(build)
    write_json(ROOT / f'evidence/entity-common-tick-{kind}.json', result)
    assert result['closure_unchanged'], 'Verification closure changed during ' + kind
    return result


def words(raw):
    value = int(raw, 16)
    return [value >> 32, value & 0xffffffff]


def vec(values):
    return [words(x) for x in values]


def metadata(observed):
    return {'position_o': vec(observed['position_o_f64_bits']),
            'position_old': vec(observed['position_old_f64_bits']),
            'invulnerable': observed['invulnerable_time_u32'], 'count': observed['tick_count_u32']}


def request(observed, flags=0):
    return {'position': vec(observed['position_f64_bits']),
            'look': [int(x, 16) for x in observed['rotation_f32_bits']],
            'context': (flags >> 4) & 3, 'nonempty_tail': bool(flags & 128)}


def initial_state(before, flags=0):
    tail = []
    if flags & 64:
        tail = [{'metadata': {'position_o': vec([P.d(7.), P.d(8.), P.d(9.)]),
                              'position_old': vec([P.d(0.)] * 3), 'invulnerable': 7, 'count': 99},
                 'tail_nonempty': False}]
    return {'metadata': metadata(before), 'tail': tail}


def accepted(before, actual, flags=0):
    fields = metadata(actual)
    return {'state': {'metadata': fields, 'tail': []},
            'status': {'ok': True, 'snapshot': {'metadata': fields,
                       'look': [int(x, 16) for x in actual['rotation_f32_bits']]}},
            'request': request(before, flags)}


def rejected(before, flags, error):
    return {'state': initial_state(before, flags), 'status': {'ok': False, 'error': error},
            'request': request(before, flags)}


def args(before, flags):
    values = [flags, before['invulnerable_time_u32'], before['tick_count_u32']]
    for name in ['position_o_f64_bits', 'position_old_f64_bits', 'position_f64_bits']:
        values.extend(word for raw in before[name] for word in words(raw))
    values.extend(int(x, 16) for x in before['rotation_f32_bits'])
    assert len(values) == 25 and all(0 <= v <= 0xffffffff for v in values)
    return values


def repaired_request(before):
    # This is the harness's explicit recovery policy, not game behavior. Recovery
    # outputs below come only from independently measured finite Java fixtures.
    result = copy.deepcopy(before)
    for field in ['position_o_f64_bits', 'position_old_f64_bits', 'position_f64_bits']:
        result[field] = ['0000000000000000' if int(v, 16) & 0x7ff0000000000000 == 0x7ff0000000000000 else v
                         for v in result[field]]
    result['rotation_f32_bits'] = ['00000000' if int(v, 16) & 0x7f800000 == 0x7f800000 else v
                                   for v in result['rotation_f32_bits']]
    return result


def cases(data):
    rows = []

    def add(name, before, flags, expected, category):
        rows.append({'id': name, 'args': args(before, flags), 'expected': expected, 'category': category})

    for fixture in data['fixtures']:
        for i, step in enumerate(fixture['steps']):
            flags = 1 if step['operation'] == 'common_tick' else 0
            add(fixture['id'] + '/step:' + str(i), step['before'], flags,
                {'steps': [accepted(step['before'], step['expected'])]}, 'actual_' + step['operation'])
        if len(fixture['steps']) > 1:
            operations = fixture['operations']
            flags = (2 | (len(operations) << 8)) if all(op == 'common_tick' for op in operations) else 4
            assert flags != 4 or operations == ['set_old_pos_and_rot', 'common_tick', 'set_old_pos_and_rot', 'common_tick']
            add(fixture['id'] + '/owned-chain', fixture['steps'][0]['before'], flags,
                {'steps': [accepted(s['before'], s['expected']) for s in fixture['steps']]}, 'actual_owned_chain')

    indexed = {f['id']: f for f in data['fixtures']}
    baseline = indexed['common_tick/signed-invulnerability:10']['steps'][0]
    before = baseline['before']
    child_actual = indexed['repair/owned-child']['steps'][0]

    def recovery(name, value, flags, error, actual_repaired):
        first = rejected(value, flags, error)
        corrected = repaired_request(value)
        # The Java fixture must contain precisely the repaired finite phase input.
        # Compare every raw word, without deriving a game output in Python.
        assert metadata(corrected) == metadata(actual_repaired['before']), (name, 'metadata repair input')
        assert request(corrected) == request(actual_repaired['before']), (name, 'position/angles repair input')
        children = []
        if flags & 64:
            child_before = copy.deepcopy(child_actual['before'])
            # This case has an unchanged finite request; the child is measured
            # separately with identical current position and camera payloads.
            assert request(corrected) == request(child_before)
            children.append(accepted(child_before, child_actual['expected']))
        expected = {'first': first, 'recovery': {'root': accepted(corrected, actual_repaired['expected']),
                                                'children': children}}
        add(name, value, flags | 3, expected, 'explicit_policy_owner_recovery')

    for context in [1, 2, 3]:
        flags = 3 | (context << 4)
        recovery('policy/context:' + str(context), before, flags,
                 {'kind': 'UnsupportedContext', 'context': context}, baseline)
    for flags, error in [(64 | 3, {'kind': 'NonCanonicalState'}),
                         (128 | 3, {'kind': 'NonCanonicalRequest'}),
                         (64 | 128 | 3, {'kind': 'NonCanonicalState'})]:
        recovery('policy/tail:' + str(flags), before, flags, error, baseline)
    for field in range(13):
        key = ('position_o_f64_bits' if field < 3 else 'position_old_f64_bits' if field < 6 else
               'position_f64_bits' if field < 9 else 'rotation_f32_bits')
        index = field if field < 3 else field - 3 if field < 6 else field - 6 if field < 9 else field - 9
        bad_values = ['7ff0000000000000', 'fff0000000000000', '7ff8000000000000', '7ff123456789abcd'] if field < 9 else [
                     '7f800000', 'ff800000', '7fc00000', '7fa12345']
        repaired = indexed['repair/field:' + str(field)]['steps'][0]
        for bad in bad_values:
            value = copy.deepcopy(before)
            value[key][index] = bad
            error = {'kind': 'NonFinite', 'field': field}
            for op in [0, 1]:
                add(f'policy/nonfinite:{field}:{bad}:{op}', value, op,
                    {'steps': [rejected(value, op, error)]}, 'explicit_policy_nonfinite_retention')
            recovery(f'policy/repair:{field}:{bad}', value, 3, error, repaired)
    # Combined refusals prove error priority and original payload retention.
    invalid = copy.deepcopy(before)
    invalid['position_o_f64_bits'][0] = '7ff8000000001234'
    invalid['position_old_f64_bits'][2] = 'fff0000000000000'
    invalid['position_f64_bits'][1] = '7ff0000000000000'
    invalid['rotation_f32_bits'][0] = '7fa12345'
    for flags, error in [(1, {'kind': 'NonFinite', 'field': 0}),
                         (1 | 16, {'kind': 'UnsupportedContext', 'context': 1}),
                         (1 | 128 | 16, {'kind': 'NonCanonicalRequest'}),
                         (1 | 64 | 128 | 16, {'kind': 'NonCanonicalState'})]:
        add('policy/priority:' + str(flags), invalid, flags,
            {'steps': [rejected(invalid, flags, error)]}, 'explicit_policy_priority')
    assert len({r['id'] for r in rows}) == len(rows)
    return rows


def verify_reference():
    result = P.verify_existing(selftest=True)
    assert len(result['failure_injections']) == 6
    data = json.loads(P.OUTPUT.read_text())
    assert len(data['fixtures']) == len(data['inputs']) and len(data['fixtures']) > 0
    for fixture in data['fixtures']:
        for step in fixture['steps']:
            before, after = step['before'], step['expected']
            phases = [p['snapshot'] for p in step['phases']]
            assert len(phases) == 4
            assert all(p['tick_count_u32'] == before['tick_count_u32'] for p in phases)
            assert all(p['invulnerable_time_u32'] == after['invulnerable_time_u32'] for p in phases)
            for name in ['position_o_f64_bits', 'position_old_f64_bits']:
                assert phases[0][name] == before[name]
                assert all(p[name] == after[name] for p in phases[1:])
            assert all(p['rotation_f32_bits'] == before['rotation_f32_bits'] for p in phases[:3])
            assert phases[3]['rotation_f32_bits'] == after['rotation_f32_bits']
            assert all(p['body'] == before['body'] and p['position_f64_bits'] == before['position_f64_bits']
                       and not p['interpolation_active'] for p in phases)
    repeat = json.loads((ROOT / 'evidence/entity-common-tick-reference-rerun.json').read_text())
    extract = json.loads((ROOT / 'evidence/entity-common-tick-reference-extract.json').read_text())
    assert repeat['independent_parity'] and extract['producer'] == repeat['producer'] == fingerprint(Path(P.__file__))
    assert repeat['fixtures_sha256'] == extract['fixtures_sha256'] == data['fixtures_sha256']
    for report in [extract, repeat]:
        raw = ROOT / report['raw_report']['path']
        assert report['raw_report'] == {'path': report['raw_report']['path'], **fingerprint(raw)}
        assert report['observations_sha256'] == digest(json.loads(raw.read_text())['observations'])
    return data, result


def prepare(data, integrity, ordinary):
    rows = cases(data)
    WORK.mkdir(parents=True, exist_ok=True)
    raw = WORK / 'expected-cases.json'
    write_json(raw, rows)
    record = {'status': 'ordinary-prepared-native-and-kernel-pending', 'pin': '26.3',
              'source': pin(SOURCE), 'harness': pin(HARNESS), 'closure': closure(),
              'ordinary': ordinary, 'reference_integrity': integrity,
              'actual_fixture_count': len(data['fixtures']),
              'actual_reference_step_count': sum(len(f['steps']) for f in data['fixtures']),
              'native_case_count': len(rows), 'case_categories': dict(collections.Counter(r['category'] for r in rows)),
              'expected_cases_sha256': digest(rows), 'expected_cases': pin(raw),
              'source_law_count': SOURCE.read_text().count('\nlaw '),
              'harness_law_count': HARNESS.read_text().count('\nlaw '),
              'native_runs_planned': 2, 'caps_seconds': {'build': 600, 'native_run': 120, 'source_kernel': 60, 'harness_kernel': 60},
              'queued_native_command': 'PYTHONDONTWRITEBYTECODE=1 python3 tools/test_entity_common_tick.py --native --skip-ordinary',
              'queued_kernel_command': 'PYTHONDONTWRITEBYTECODE=1 python3 tools/test_entity_common_tick.py --kernel --skip-ordinary',
              'domain': 'All finite raw F64 positions/old triples and F32 camera fields; conditional neutral client inactive interpolation; canonical empty ownership/request tails.',
              'limits': 'No handler cancel/reset internals, active interpolation, lifecycle, Entity.tick, LocalPlayer.tick or runtime consumer integration.'}
    write_json(PREPARED, record)
    return record


def verify_build(build):
    for value in build['dependencies']:
        path = Path(value['lookup'])
        assert path.resolve() == Path(value['path']) and fingerprint(path)['sha256'] == value['sha256'] and path.stat().st_size == value['bytes'], 'Native dependency changed: ' + str(path)
    assert fingerprint(BINARY)['sha256'] == build['binary_sha256'] and BINARY.stat().st_size == build['binary_bytes']
    return BINARY


def build_summary(build):
    names = ['artifact', 'binary_bytes', 'binary_sha256', 'cache_key', 'cache_hit', 'identity', 'timings']
    return {**{k: build[k] for k in names}, 'compiler': {k: v for k, v in build['compiler'].items() if k != 'driver_probe'},
            'full_receipt': pin(RECEIPT), 'dependency_count': len(build['dependencies']),
            'dependencies_sha256': digest(build['dependencies']),
            'project_dependencies': [d for d in build['dependencies'] if d['path'].startswith(str(ROOT) + '/')],
            'associated_preflight_c_sha256': build['emitted_c_sha256'],
            'c_scope': 'Content-keyed preflight C. Installed CLI internal temporary C/flags are not asserted captured or identical.'}


def native_run(binary, rows, index):
    start = time.monotonic()
    observations, receipts = [], []
    for offset in range(0, len(rows), 16):
        group = rows[offset:offset + 16]
        command = [str(binary), '--gpu', 'off', '--threads', '1', '--',
                   *[str(word) for row in group for word in row['args']]]
        remaining = 120 - (time.monotonic() - start)
        assert remaining > 0, '120-second entire native run bound exhausted'
        process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, start_new_session=True)
        try:
            out, err = process.communicate(timeout=remaining)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            out, err = process.communicate()
            raise AssertionError('Entire native run timeout')
        observed = [json.loads(line) for line in out.splitlines() if line.startswith('{')]
        receipt = {'offset': offset, 'pid': process.pid, 'command': command,
                   'exit_code': process.returncode, 'stdout': out, 'stderr': err}
        receipts.append(receipt)
        raw = WORK / f'native-run-{index}.full.json'
        write_json(raw, {'receipts': receipts, 'observations': observations + observed})
        assert process.returncode == 0 and len(observed) == len(group), (offset, receipt)
        for wanted, got in zip(group, observed):
            assert got == wanted['expected'], (wanted['id'], wanted['expected'], got)
        observations.extend(observed)
    return {'status': 'passed', 'case_count': len(rows), 'process_count': len(receipts),
            'observations_sha256': digest(observations), 'raw_report': pin(raw),
            'seconds': round(time.monotonic() - start, 6)}


def verify_prepared(rows):
    prepared = json.loads(PREPARED.read_text())
    assert prepared['closure'] == closure(), 'Sealed preflight closure changed'
    assert prepared['expected_cases_sha256'] == digest(rows), 'Sealed expected cases changed'
    return prepared


def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--prepare', action='store_true')
    group.add_argument('--native', action='store_true')
    group.add_argument('--build-only', action='store_true')
    group.add_argument('--kernel', action='store_true')
    parser.add_argument('--skip-ordinary', action='store_true')
    parser.add_argument('--skip-build', action='store_true')
    args_ = parser.parse_args()
    ordinary = []
    if not args_.skip_ordinary:
        for kind in ['ordinary-source', 'ordinary-harness']:
            result = bound(kind, 30)
            ordinary.append(result)
            assert result['status'] == 'passed', result
    data, integrity = verify_reference()
    rows = cases(data)
    if not (args_.native or args_.kernel or args_.build_only):
        report = prepare(data, integrity, ordinary)
        print(json.dumps({k: report[k] for k in ['status', 'actual_fixture_count', 'actual_reference_step_count',
                                               'native_case_count', 'case_categories', 'source_law_count', 'harness_law_count']}))
        return
    prepared = verify_prepared(rows)
    if args_.kernel:
        evidence = json.loads(NATIVE.read_text())
        assert evidence['status'] == 'passed_neutral_scheduler_projection' and evidence['closure'] == closure()
        verify_build(json.loads(RECEIPT.read_text()))
        attempts = [bound('kernel-source', 60)]
        skipped = None
        if attempts[0]['status'] == 'passed':
            attempts.append(bound('kernel-harness', 60))
        else:
            skipped = 'Source full imported graph failed or timed out; harness importing that graph was not repeated.'
        record = {'status': 'passed' if skipped is None and all(r['status'] == 'passed' for r in attempts) else 'incomplete',
                  'closure': closure(), 'source_law_count': 5, 'harness_law_count': 5,
                  'attempts': attempts, 'skipped_harness': skipped,
                  'scope': 'Exactly the ten stated helper/owner laws and typed definitions, not universal Java tick parity.'}
        write_json(KERNEL, record)
        print(json.dumps({'kernel_status': record['status'], 'attempts': [{k: a[k] for k in ['phase', 'status', 'seconds']} for a in attempts], 'skipped_harness': skipped}))
        return
    if not args_.skip_build:
        result = bound('build', 600)
        assert result['status'] == 'passed', result
    if args_.build_only:
        return
    build = json.loads(RECEIPT.read_text())
    binary = verify_build(build)
    before = closure()
    first = native_run(binary, rows, 1)
    second = native_run(binary, rows, 2)
    assert first['observations_sha256'] == second['observations_sha256']
    verify_build(build)
    assert before == closure() == prepared['closure'], 'Native generation changed'
    report = {'schema': 1, 'status': 'passed_neutral_scheduler_projection', 'pin': '26.3',
              'closure': before, 'closure_sha256': digest(before), 'closure_unchanged': True,
              'build': build_summary(build), 'reference_integrity': integrity,
              'actual_fixture_count': len(data['fixtures']),
              'actual_reference_step_count': sum(len(f['steps']) for f in data['fixtures']),
              'case_categories': dict(collections.Counter(r['category'] for r in rows)),
              'expected_cases_sha256': digest(rows), 'native': [first, second],
              'scope': prepared['domain'], 'limits': prepared['limits'],
              'reproduce': [prepared['queued_native_command'], prepared['queued_kernel_command']]}
    write_json(NATIVE, report)
    print(json.dumps({'native_status': report['status'], 'case_count': len(rows), 'native_seconds': [first['seconds'], second['seconds']], 'binary_sha256': build['binary_sha256']}))


if __name__ == '__main__':
    main()
