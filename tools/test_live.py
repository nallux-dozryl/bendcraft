#!/usr/bin/env python3
"""Declarative native Bend dispatcher scenarios; no transport/game implementation."""
from __future__ import annotations
import argparse
import hashlib
import json
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BEND = Path('/Users/chuah/.bend/bin/bend')
TOKEN = 'fixture-token'
POSITION = {'dimension': 'minecraft:overworld', 'x': -1, 'y': 64, 'z': -17}
BASE_CLOCK = {'tick': 0, 'day_time': 0, 'paused': True, 'daylight': True, 'revision': 0, 'pending': 0}


def req(op, args=None, at=None):
    value = {'op': op}
    if args is not None:
        value['args'] = args
    if at is not None:
        value['at'] = at
    return value


def stamp(tick, sequence):
    return {'tick': tick, 'peer': 7, 'sequence': sequence}


class Scenario:
    def __init__(self, name, token=TOKEN):
        self.name, self.token = name, token
        self.requests, self.expected = [], []
        self.clock, self.mode = dict(BASE_CLOCK), 'observer'

    def add(self, value, *, error=None, result=None, clock=None, mode=None, raw=False):
        seq = len(self.requests) + 1
        if not raw:
            value = {'id': str(seq), **value}
            source = json.dumps(value, ensure_ascii=False, separators=(',', ':'))
        else:
            source = value
            value = json.loads(source)
        if clock:
            self.clock.update(clock)
        if mode:
            self.mode = mode
        id_value = value.get('id', '') if isinstance(value, dict) else ''
        if not isinstance(id_value, str):
            id_value = ''
        self.requests.append(source)
        self.expected.append({'id': id_value, 'sequence': seq, 'mode': self.mode,
                              'clock': dict(self.clock), 'error': error, 'result': result})
        return seq

    def developer(self):
        sequence = len(self.requests) + 1
        return self.add(req('session.open', {'mode': 'developer', 'token': TOKEN}),
                        result={'mode': 'developer', 'peer': 7, 'sequence': sequence}, mode='developer')


def scenarios():
    output = []
    auth = Scenario('authorization-and-session-retention')
    auth.add(req('world.clock'), error='PermissionDenied')
    auth.add(req('session.open', {'mode': 'developer', 'token': 'wrong'}), error='AuthenticationFailed')
    auth.add(req('session.open', {'mode': 'developer'}), error='AuthenticationFailed')
    auth.add(req('session.open', {'mode': 'unrecognized'}), error='InvalidArguments')
    auth.add(req('session.open', {'mode': 'player', 'token': TOKEN}), error='PlayerUnavailable')
    auth.add(req('discover'), result='DISCOVERY')
    auth.add(req('ping'), result={'version': '26.3', 'peer': 7, 'sequence': 7, 'mode': 'observer'})
    auth.developer()
    auth.add(req('session.open', {'mode': 'developer', 'token': 'wrong'}), error='AuthenticationFailed')
    auth.add(req('world.clock'), result=dict(BASE_CLOCK))
    auth.add(req('session.open', {'mode': 'observer'}), result={'mode': 'observer', 'peer': 7, 'sequence': 11}, mode='observer')
    auth.add(req('world.clock'), error='PermissionDenied')
    output.append(auth)
    empty = Scenario('empty-configured-token', token='')
    empty.add(req('session.open', {'mode': 'developer', 'token': ''}), error='AuthenticationFailed')
    empty.add(req('session.open', {'mode': 'developer', 'token': TOKEN}), error='AuthenticationFailed')
    empty.add(req('ping'), result={'version': '26.3', 'peer': 7, 'sequence': 3, 'mode': 'observer'})
    output.append(empty)

    permissions = Scenario('observer-core-operation-denials')
    valid_arguments = {
        'world.clock': {}, 'simulation.pause': {'paused': True}, 'simulation.step': {'ticks': 1},
        'world.section.create': {**POSITION, 'fill': 0}, 'world.block.get': POSITION,
        'world.block.set': {**POSITION, 'state': 0}, 'world.time.set': {'day_time': 0},
        'world.daylight.set': {'enabled': False}, 'action.cancel': {'peer': 7, 'sequence': 1}, 'world.events': {},
    }
    for op, args in valid_arguments.items():
        permissions.add(req(op, args), error='PermissionDenied')
    output.append(permissions)

    state = Scenario('admission-application-cancellation-and-owned-sections')
    state.developer()
    create = state.add(req('world.section.create', {**POSITION, 'fill': 0}),
                       result={'accepted': True, 'stamp': stamp(1, 2)}, clock={'pending': 1})
    block = state.add(req('world.block.set', {**POSITION, 'state': 7}),
                      result={'accepted': True, 'stamp': stamp(1, 3)}, clock={'pending': 2})
    state.add(req('world.block.get', POSITION), error='MissingSection')
    state.add(req('simulation.step', {'ticks': 1}),
              result={'tick': 1, 'day_time': 1, 'paused': True, 'daylight': True, 'revision': 2, 'pending': 0},
              clock={'tick': 1, 'day_time': 1, 'revision': 2, 'pending': 0})
    state.add(req('world.block.get', POSITION), result={'state': 7})
    queued = state.add(req('world.block.set', {**POSITION, 'state': 9}, at=3),
                       result={'accepted': True, 'stamp': stamp(3, 7)}, clock={'pending': 1})
    time_set = state.add(req('world.time.set', {'day_time': 100}, at=2),
                         result={'accepted': True, 'stamp': stamp(2, 8)}, clock={'pending': 2})
    daylight = state.add(req('world.daylight.set', {'enabled': False}, at=2),
                         result={'accepted': True, 'stamp': stamp(2, 9)}, clock={'pending': 3})
    state.add(req('world.clock'), result=dict(state.clock))
    state.add(req('simulation.step', {'ticks': 1}),
              result={'tick': 2, 'day_time': 100, 'paused': True, 'daylight': False, 'revision': 4, 'pending': 1},
              clock={'tick': 2, 'day_time': 100, 'daylight': False, 'revision': 4, 'pending': 1})
    applied = [{'kind': 'applied', 'stamp': stamp(2, daylight), 'revision': 4},
               {'kind': 'applied', 'stamp': stamp(2, time_set), 'revision': 3},
               {'kind': 'applied', 'stamp': stamp(1, block), 'revision': 2},
               {'kind': 'applied', 'stamp': stamp(1, create), 'revision': 1}]
    state.add(req('world.events'), result={'order': 'newest-first', 'events': applied})
    state.add(req('action.cancel', {'peer': 7, 'sequence': queued, 'tick': 999}),
              result={'cancelled': True, 'peer': 7, 'sequence': queued}, clock={'pending': 0})
    state.add(req('simulation.step', {'ticks': 1}),
              result={'tick': 3, 'day_time': 100, 'paused': True, 'daylight': False, 'revision': 4, 'pending': 0}, clock={'tick': 3})
    state.add(req('world.block.get', POSITION), result={'state': 7})
    exists = state.add(req('world.section.create', {**POSITION, 'fill': 0}),
                       result={'accepted': True, 'stamp': stamp(4, 16)}, clock={'pending': 1})
    missing_position = {'dimension': 'minecraft:overworld', 'x': 100, 'y': 0, 'z': 100}
    missing = state.add(req('world.block.set', {**missing_position, 'state': 4}),
                        result={'accepted': True, 'stamp': stamp(4, 17)}, clock={'pending': 2})
    state.add(req('simulation.step', {'ticks': 1}),
              result={'tick': 4, 'day_time': 100, 'paused': True, 'daylight': False, 'revision': 4, 'pending': 0},
              clock={'tick': 4, 'pending': 0})
    state.add(req('world.block.get', POSITION), result={'state': 7})
    state.add(req('world.events'), result={'order': 'newest-first', 'events': [
        {'kind': 'rejected', 'stamp': stamp(4, missing), 'error': {'code': 'MissingSection', 'message': 'section does not exist: minecraft:overworld/6/0/6'}},
        {'kind': 'rejected', 'stamp': stamp(4, exists), 'error': {'code': 'SectionExists', 'message': 'section already exists: minecraft:overworld/4294967295/4/4294967294'}},
        *applied]})
    state.add(req('world.block.set', {**POSITION, 'state': 16}), error='InvalidState')
    state.add(req('world.section.create', {**POSITION, 'dimension': 'invalid:dimension', 'fill': 0}), error='UnknownDimension')
    state.add(req('world.block.set', {**POSITION, 'state': 0}, at=4), error='PastTick')
    state.add(req('world.block.set', {**POSITION, 'state': 0}, at=3), error='PastTick')
    far = state.add(req('world.time.set', {'day_time': 4294967295}, at=4294967295),
                    result={'accepted': True, 'stamp': stamp(4294967295, 25)}, clock={'pending': 1})
    state.add(req('action.cancel', {'peer': 7, 'sequence': far}),
              result={'cancelled': True, 'peer': 7, 'sequence': far}, clock={'pending': 0})
    state.add(req('simulation.step', {'ticks': 1000}),
              result={'tick': 1004, 'day_time': 100, 'paused': True, 'daylight': False, 'revision': 4, 'pending': 0}, clock={'tick': 1004})
    state.add(req('simulation.step', {'ticks': 0}), error='InvalidArguments')
    state.add(req('simulation.step', {'ticks': 1001}), error='InvalidArguments')
    state.add(req('simulation.pause', {'paused': False}), result={**state.clock, 'paused': False}, clock={'paused': False})
    state.add(req('world.clock'), result=dict(state.clock))
    output.append(state)

    cancellation = Scenario('cancellation-identity-and-nonexistent-actions')
    cancellation.developer()
    cancellation.add(req('world.time.set', {'day_time': 5}, at=2), result={'accepted': True, 'stamp': stamp(2, 2)}, clock={'pending': 1})
    cancellation.add(req('action.cancel', {'peer': 8, 'sequence': 2}), error='PermissionDenied')
    cancellation.add(req('action.cancel', {'peer': 7, 'sequence': 4}), error='PermissionDenied')
    cancellation.add(req('action.cancel', {'peer': 7, 'sequence': 99}), error='PermissionDenied')
    cancellation.add(req('action.cancel', {'peer': 7, 'sequence': 1}), result={'cancelled': False, 'peer': 7, 'sequence': 1})
    cancellation.add(req('action.cancel', {'peer': 7, 'sequence': 2}), result={'cancelled': True, 'peer': 7, 'sequence': 2}, clock={'pending': 0})
    cancellation.add(req('action.cancel', {'peer': 7, 'sequence': 2}), result={'cancelled': False, 'peer': 7, 'sequence': 2})
    output.append(cancellation)

    bad = Scenario('strict-envelope-and-argument-schemas')
    bad.developer()
    for value in [None, [], 'string', {'id': 1, 'op': 'ping'}, {'id': 'x'}, {'op': 1},
                  {'op': 'ping', 'extra': 0}, {'op': 'ping', 'args': None}, {'op': 'ping', 'args': []},
                  {'op': 'ping', 'at': -1}, {'op': 'ping', 'at': 1.0}, {'op': 'ping', 'at': True},
                  {'op': 'ping', 'at': 4294967296}]:
        if isinstance(value, dict):
            bad.add(value, error='InvalidRequest')
        else:
            bad.add(json.dumps(value), error='InvalidRequest', raw=True)
    bad.add({'id': 'unknown', 'op': 'not.implemented'}, error='UnknownOperation')
    for op in ['batch', 'world.subscribe', 'world.save', 'player.move']:
        bad.add(req(op), error='UnknownOperation')
    for op, args in valid_arguments.items():
        bad.add(req(op, {**args, 'extra': False}), error='InvalidArguments')
        if op not in ['world.section.create', 'world.block.set', 'world.time.set', 'world.daylight.set']:
            bad.add(req(op, args, at=1), error='InvalidArguments')
    malformed = [
        ('simulation.pause', {}), ('simulation.pause', {'paused': 0}), ('simulation.pause', {'paused': 'true'}),
        ('simulation.step', {'ticks': -1}), ('simulation.step', {'ticks': 1.0}), ('simulation.step', {'ticks': True}),
        ('world.section.create', {**POSITION, 'fill': -1}), ('world.block.set', {**POSITION, 'state': '1'}),
        ('world.time.set', {'day_time': 1.0}), ('world.time.set', {'day_time': -1}),
        ('world.daylight.set', {'enabled': 'false'}), ('action.cancel', {'peer': 7, 'sequence': 0}),
        ('action.cancel', {'peer': 7, 'sequence': 1, 'tick': 'ignored'}),
        ('session.open', {'mode': 'developer', 'token': 1}),
    ]
    for axis in ['x', 'y', 'z']:
        for value in [-2147483649, 2147483648, 1.0, True, '0']:
            malformed.append(('world.block.get', {**POSITION, axis: value}))
    for op, args in malformed:
        bad.add(req(op, args), error='InvalidArguments')
    for source in ['{"id":"fraction","op":"simulation.step","args":{"ticks":1e0}}',
                   '{"id":"negative-zero","op":"world.time.set","args":{"day_time":-0}}']:
        bad.add(source, raw=True, error='InvalidArguments')
    bad.add(req('world.clock'), result=dict(BASE_CLOCK))
    output.append(bad)

    bounds = Scenario('signed-boundaries-dimensions-and-query-ownership')
    bounds.developer()
    extremes = {'dimension': 'minecraft:the_end', 'x': -2147483648, 'y': 2147483647, 'z': -16}
    bounds.add(req('world.section.create', {**extremes, 'fill': 3}), result={'accepted': True, 'stamp': stamp(1, 2)}, clock={'pending': 1})
    bounds.add(req('simulation.step', {'ticks': 1}), result={'tick': 1, 'day_time': 1, 'paused': True, 'daylight': True, 'revision': 1, 'pending': 0}, clock={'tick': 1, 'day_time': 1, 'revision': 1, 'pending': 0})
    for _ in range(3):
        bounds.add(req('world.block.get', extremes), result={'state': 3})
    bounds.add(req('world.block.get', {**extremes, 'dimension': 'unknown'}), error='UnknownDimension')
    bounds.add(req('world.block.set', {**extremes, 'state': 15}), result={'accepted': True, 'stamp': stamp(2, 8)}, clock={'pending': 1})
    bounds.add(req('simulation.step', {'ticks': 1}), result={'tick': 2, 'day_time': 2, 'paused': True, 'daylight': True, 'revision': 2, 'pending': 0}, clock={'tick': 2, 'day_time': 2, 'revision': 2, 'pending': 0})
    bounds.add(req('world.block.get', extremes), result={'state': 15})
    bounds.add(req('world.block.get', {**extremes, 'x': -2147483647, 'z': -15}), result={'state': 3})
    output.append(bounds)
    return output


def check_discovery(value):
    assert value['version'] == '26.3' and value['surface'] == 'section-and-tick-foundation'
    assert value['subscriptions'] is False and value['batch'] is False and value['player_mode'] is False
    operations = {entry['name']: entry for entry in value['operations']}
    expected = {'discover', 'ping', 'session.open', 'world.clock', 'simulation.pause', 'simulation.step',
                'world.section.create', 'world.block.get', 'world.block.set', 'world.time.set', 'world.daylight.set', 'action.cancel', 'world.events'}
    assert set(operations) == expected and len(value['operations']) == 13
    scheduled = {'world.section.create', 'world.block.set', 'world.time.set', 'world.daylight.set'}
    for name, entry in operations.items():
        assert entry['version'] == '26.3' and entry['status'] == 'implemented-foundation'
        assert entry['permitted_mode'] == ('observer' if name in {'discover', 'ping', 'session.open'} else 'developer')
        assert entry['scheduled'] == (name in scheduled)
        schema = entry['input_schema']
        assert schema['type'] == 'object' and schema['additionalProperties'] is False
        assert set(schema['properties']) == ({'id', 'op', 'args', 'at'} if name in scheduled else {'id', 'op', 'args'})
        assert schema['properties']['op']['const'] == name
        args = schema['properties']['args']
        assert args['type'] == 'object' and args['additionalProperties'] is False
        assert set(schema['required']) == ({'id', 'op', 'args'} if args['required'] else {'id', 'op'})
        assert set(args['required']) <= set(args['properties'])
    step = operations['simulation.step']['input_schema']['properties']['args']['properties']['ticks']
    assert step['minimum'] == 1 and step['maximum'] == 1000
    coord = operations['world.block.get']['input_schema']['properties']['args']['properties']['x']
    assert coord['minimum'] == -2147483648 and coord['maximum'] == 2147483647


def run(command, timeout=120):
    result = subprocess.run([str(arg) for arg in command], cwd=ROOT, text=True,
                            capture_output=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f'{command[:4]} failed ({result.returncode}):\n{result.stdout}{result.stderr}')
    return result.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--skip-build', action='store_true')
    options = parser.parse_args()
    start = time.monotonic()
    binary = ROOT / 'build/live-tests'
    checker = {}
    for source in ['src/live.bend', 'tests/live.bend']:
        checker[source] = run([BEND, source, '--check-only']).strip()
        assert 'ALL PROOFS CHECK' in checker[source]
    if not options.skip_build:
        run([BEND, 'tests/live.bend', '-o', binary])
    records = []
    for scenario in scenarios():
        lines = run([binary, '--threads', 1, scenario.token, *scenario.requests]).removesuffix('\n').split('\n')
        assert len(lines) == len(scenario.expected), (scenario.name, len(lines), len(scenario.expected))
        for index, (line, expected) in enumerate(zip(lines, scenario.expected), 1):
            value = json.loads(line)
            prefix = f'{scenario.name} request {index}'
            assert set(value) == {'response', 'session', 'clock'}, prefix
            assert value['session'] == {'peer': 7, 'sequence': expected['sequence'], 'mode': expected['mode']}, (prefix, value['session'], expected)
            assert value['clock'] == expected['clock'], (prefix, value['clock'], expected['clock'])
            response = value['response']
            assert response['id'] == expected['id'], (prefix, response)
            assert response['ok'] is (expected['error'] is None), (prefix, response)
            if expected['error']:
                assert set(response) == {'id', 'ok', 'error'}, prefix
                assert response['error']['code'] == expected['error'], (prefix, response, expected['error'])
                assert isinstance(response['error']['message'], str) and response['error']['message'], prefix
            else:
                assert set(response) == {'id', 'ok', 'result'}, prefix
                if expected['result'] == 'DISCOVERY':
                    check_discovery(response['result'])
                else:
                    assert response['result'] == expected['result'], (prefix, response['result'], expected['result'])
            assert TOKEN not in line, (prefix, 'token leak')
        records.append({'name': scenario.name, 'requests': len(lines), 'passed': True})
    capacity = json.loads(run([binary, '--threads', 1, 'capacity']))
    assert capacity['clock'] == {**BASE_CLOCK, 'pending': 4096}, capacity
    assert capacity['session'] == {'peer': 7, 'sequence': 4098, 'mode': 'developer'}, capacity
    assert capacity['response']['ok'] is False and capacity['response']['error']['code'] == 'TooManyPending', capacity
    records.append({'name': 'real-dispatch-pending-capacity-4096', 'requests': 4098, 'passed': True})
    source = (ROOT / 'src/live.bend').read_text()
    assert '@unsafe' not in source and 'C.apply(' not in source
    assert 'import "' not in source and 'IO(' not in source
    kernel = {}
    for path in ['src/live.bend', 'tests/live.bend']:
        result = subprocess.run([str(BEND), path, '--verdict'], cwd=ROOT, text=True, capture_output=True, timeout=60)
        kernel[path] = {'exit_code': result.returncode, 'output': (result.stdout + result.stderr).strip()}
    report = {'schema': 1, 'compiler': run([BEND, 'version']).strip(), 'checker': checker,
              'kernel_verdicts': kernel, 'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
              'native_binary': 'build/live-tests', 'native_binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
              'dependency_sha256': {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                                    for name in ['src/json.bend', 'src/core.bend', 'src/schedule.bend', 'src/section.bend', 'src/section_map.bend']},
              'scenarios': records,
              'native_requests': sum(row['requests'] for row in records), 'all_scenarios_passed': True,
              'finite_checker_fixtures': 2, 'elapsed_seconds': round(time.monotonic() - start, 3),
              'scope': 'pure dispatcher only; actual TCP/MCP transport is tested separately by the lead',
              'commands': ['python3 tools/test_live.py', '/Users/chuah/.bend/bin/bend src/live.bend --check-only',
                           '/Users/chuah/.bend/bin/bend tests/live.bend --check-only',
                           '/Users/chuah/.bend/bin/bend tests/live.bend -o build/live-tests',
                           '/Users/chuah/.bend/bin/bend src/live.bend --verdict', '/Users/chuah/.bend/bin/bend tests/live.bend --verdict']}
    target = ROOT / 'evidence/live-tests.json'
    target.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'native_requests': report['native_requests'], 'scenarios': len(records),
                      'all_scenarios_passed': True, 'elapsed_seconds': report['elapsed_seconds']}, indent=2))

if __name__ == '__main__':
    main()
