#!/usr/bin/env python3
"""Native pure-Bend mod-kernel tests with independent tuple/DAG reference logic."""
from __future__ import annotations
import argparse
import copy
import hashlib
import heapq
import json
import random
import re
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BEND = Path('/Users/chuah/.bend/bin/bend')
API = (1, 0, 0)


def version(value):
    if isinstance(value, str):
        if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', value):
            raise ValueError('version grammar')
        result = tuple(map(int, value.split('.')))
    elif isinstance(value, list) and len(value) == 3 and all(type(x) is int for x in value):
        result = tuple(value)
    else:
        raise ValueError('version type/arity')
    if not all(0 <= x <= 0xFFFFFFFF for x in result):
        raise ValueError('component range')
    return result


def in_range(v, bounds):
    for endpoint, comparison in [('min', -1), ('max', 1)]:
        if endpoint in bounds:
            bound = bounds[endpoint]
            expected = version(bound['version'])
            if (comparison == -1 and v < expected) or (comparison == 1 and v > expected):
                return False
            if v == expected and not bound['inclusive']:
                return False
    return True


def oracle_order(manifests, side):
    by_id = {item['id']: item for item in manifests}
    assert len(by_id) == len(manifests)
    for item in manifests:
        assert version(item['api_version']) == API
        for dep in item.get('dependencies', []):
            provider = by_id[dep['id']]
            assert provider['side'] == 'both' or provider['side'] == item['side']
            assert in_range(version(provider['version']), dep['range'])
        for target in item.get('before', []) + item.get('after', []):
            provider = by_id[target]
            assert provider['side'] == 'both' or provider['side'] == item['side']
    active = {key: item for key, item in by_id.items() if item['side'] in [side, 'both']}
    graph = {key: set() for key in active}
    indegree = {key: 0 for key in active}
    def edge(first, second):
        if second not in graph[first]:
            graph[first].add(second)
            indegree[second] += 1
    for key, item in active.items():
        for dependency in item.get('dependencies', []):
            edge(dependency['id'], key)
        for prior in item.get('after', []):
            edge(prior, key)
        for later in item.get('before', []):
            edge(key, later)
    ready = [key for key, degree in indegree.items() if degree == 0]
    heapq.heapify(ready)
    ordered = []
    while ready:
        key = heapq.heappop(ready)
        ordered.append(key)
        for following in graph[key]:
            indegree[following] -= 1
            if indegree[following] == 0:
                heapq.heappush(ready, following)
    if len(ordered) != len(active):
        raise ValueError('cycle')
    return ordered


def manifest(id='fixture:a', **changes):
    value = {'id': id, 'version': '1.0.0', 'api_version': '1.0.0', 'side': 'both',
             'data_version': 0, 'reload': 'restart'}
    value.update(changes)
    return value


def dependency(id, minimum=None, maximum=None, lo=True, hi=False):
    bounds = {}
    if minimum is not None: bounds['min'] = {'version': minimum, 'inclusive': lo}
    if maximum is not None: bounds['max'] = {'version': maximum, 'inclusive': hi}
    return {'id': id, 'range': bounds}


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'))


@dataclass
class Case:
    name: str
    mode: str
    a: str
    b: str
    expected: dict | str


def corpus():
    cases = []
    def ok(name, pack, side='server'):
        cases.append(Case(name, side, encode(pack), '', {'ok': True, 'order': oracle_order(pack, side)}))
    def fail(name, pack, prefix, side='server'):
        cases.append(Case(name, side, encode(pack), '', prefix))
    fixture_files = sorted((ROOT / 'mods/fixtures').glob('*.json'))
    fixture = [json.loads(path.read_text()) for path in fixture_files]
    ok('representative-server-pack', fixture)
    ok('representative-client-pack', fixture, 'client')
    client = [item for item in fixture if item['side'] != 'server']
    server = [item for item in fixture if item['side'] != 'client']
    shared = [id for id in oracle_order(client, 'client') if next(x for x in client if x['id'] == id)['side'] == 'both']
    cases.append(Case('representative-match', 'match', encode(client), encode(server),
                      {'ok': True, 'match': {'client_order': oracle_order(client, 'client'),
                                            'server_order': oracle_order(server, 'server'), 'shared': shared}}))
    ok('empty-pack', [])
    ok('lexical-ready-tie', [manifest('fixture:z'), manifest('fixture:a'), manifest('fixture:m')])
    ok('maximum-64-pack', [manifest(f'fixture:m{i:02d}') for i in range(64)])
    fail('over-64-pack', [manifest(f'fixture:m{i:02d}') for i in range(65)], 'TooManyMods')
    fail('invalid-target-both', [manifest()], 'InvalidTarget', side='both')
    fail('duplicate-ids', [manifest(), manifest(version='2.0.0')], 'DuplicateId')
    fail('missing-dependency', [manifest(dependencies=[dependency('fixture:missing')])], 'MissingDependency')
    fail('incompatible-version', [manifest('fixture:base', version='2.0.0'), manifest(dependencies=[dependency('fixture:base', '1.0.0', '2.0.0')])], 'IncompatibleDependency')
    ok('inclusive-upper-bound', [manifest('fixture:base', version=[2, 0, 0]), manifest(dependencies=[dependency('fixture:base', [1, 0, 0], '2.0.0', hi=True)])])
    fail('exclusive-lower-bound', [manifest('fixture:base'), manifest(dependencies=[dependency('fixture:base', '1.0.0', lo=False)])], 'IncompatibleDependency')
    fail('reversed-range', [manifest(dependencies=[dependency('fixture:x', '2.0.0', '1.0.0')])], 'InvalidManifest')
    fail('empty-equal-range', [manifest(dependencies=[dependency('fixture:x', '1.0.0', '1.0.0')])], 'InvalidManifest')
    ok('equal-inclusive-range', [manifest('fixture:base'), manifest(dependencies=[dependency('fixture:base', '1.0.0', '1.0.0', hi=True)])])
    fail('missing-order-target', [manifest(before=['fixture:missing'])], 'MissingOrderTarget')
    fail('self-cycle', [manifest(after=['fixture:a'])], 'Cycle')
    fail('dependency-cycle', [manifest('fixture:a', dependencies=[dependency('fixture:b')]), manifest('fixture:b', dependencies=[dependency('fixture:c')]), manifest('fixture:c', dependencies=[dependency('fixture:a')])], 'Cycle')
    fail('ordering-cycle', [manifest('fixture:a', before=['fixture:b']), manifest('fixture:b', before=['fixture:a'])], 'Cycle')
    fail('both-needs-client', [manifest('fixture:client', side='client'), manifest(dependencies=[dependency('fixture:client')])], 'ForbiddenSide')
    fail('server-needs-client', [manifest('fixture:client', side='client'), manifest(side='server', dependencies=[dependency('fixture:client')])], 'ForbiddenSide')
    fail('both-orders-server', [manifest('fixture:server', side='server'), manifest(after=['fixture:server'])], 'ForbiddenSide')
    fail('api-version', [manifest(api_version='1.0.1')], 'ApiVersionMismatch')
    fail('callable-collision', [manifest('fixture:a', operations=['world.clock']), manifest('fixture:b', queries=['world.clock'])], 'ConflictingName')
    fail('event-collision', [manifest('fixture:a', events=['world.changed']), manifest('fixture:b', events=['world.changed'])], 'ConflictingName')
    ok('event-callable-separate-namespaces', [manifest('fixture:a', operations=['world.clock']), manifest('fixture:b', events=['world.clock'])])
    ok('inactive-sides-may-reuse-name', [manifest('fixture:a', side='client', operations=['same.name']), manifest('fixture:b', side='server', operations=['same.name'])])
    invalid_metadata = [
        {'id': 'missing-colon'}, {'id': ':empty'}, {'id': 'empty:'}, {'id': 'A:b'}, {'id': 'a:b:c'},
        {'id': 'a:b space'}, {'id': 'a:😀'}, {'id': 'a:' + 'x' * 127},
        {'operations': ['a b']}, {'operations': ['same'], 'queries': ['same']}, {'events': ['same', 'same']},
        {'before': ['fixture:a', 'fixture:a']}, {'dependencies': [dependency('fixture:a'), dependency('fixture:a')]},
    ]
    for i, change in enumerate(invalid_metadata):
        fail(f'invalid-metadata-{i}', [manifest(**change)], 'InvalidMetadata')
    invalid_manifest = [
        {'extra': True}, {'version': '01.0.0'}, {'version': '1.0'}, {'version': '1.0.0-alpha'},
        {'version': '1.0.0+build'}, {'version': [1, 0]}, {'version': [1.0, 0, 0]}, {'version': [True, 0, 0]},
        {'data_version': -1}, {'data_version': 1.0}, {'side': 'Both'}, {'reload': 'dynamic'},
        {'dependencies': [{'id': 'fixture:a'}]}, {'dependencies': [{'id': 'fixture:a', 'range': {'min': {'version': '1.0.0'}}}]},
        {'dependencies': [{'id': 'fixture:a', 'range': {'min': {'version': '1.0.0', 'inclusive': 1}}}]},
        {'dependencies': [{'id': 'fixture:a', 'range': {'caret': '1.0.0'}}]},
        {'before': [1]}, {'events': 'event'}, {'operations': [None]},
    ]
    for i, change in enumerate(invalid_manifest):
        fail(f'invalid-manifest-{i}', [manifest(**change)], 'InvalidManifest')
    for key in ['id', 'version', 'api_version', 'side', 'data_version', 'reload']:
        item = manifest(); del item[key]
        fail('missing-' + key, [item], 'InvalidManifest')

    rng = random.Random(0x4D4F4453)
    for i in range(200):
        count = rng.randrange(1, 21)
        ranks = list(range(count)); rng.shuffle(ranks)
        mods = [manifest(f'generated:m{rank:02d}', version=[rng.randrange(4), rng.randrange(8), rng.randrange(8)],
                         operations=[f'generated:m{rank:02d}.operation'], events=[f'generated:m{rank:02d}.event']) for rank in ranks]
        for target in range(1, count):
            predecessors = rng.sample(range(target), min(target, rng.randrange(4)))
            for prior in predecessors:
                source = mods[prior]
                kind = rng.randrange(3)
                if kind == 0:
                    v = version(source['version'])
                    mods[target].setdefault('dependencies', []).append(dependency(source['id'], list(v), [v[0], v[1], v[2] + 1]))
                elif kind == 1:
                    mods[target].setdefault('after', []).append(source['id'])
                else:
                    source.setdefault('before', []).append(mods[target]['id'])
        # Logical generation rank guarantees a DAG, independent of ID/input ordering.
        rng.shuffle(mods)
        ok(f'generated-dag-{i}', mods)
        permuted = copy.deepcopy(mods); rng.shuffle(permuted)
        ok(f'permuted-dag-{i}', permuted)
        assert oracle_order(mods, 'server') == oracle_order(permuted, 'server')

    version_values = ['0.0.0', '1.2.3', '4294967295.4294967295.4294967295', [1, 2, 3], [0, 0, 0],
                      '01.0.0', '1.0.0 ', '1.0.0-alpha', '1.0.0+build', '1e0.0.0', '-1.0.0',
                      '4294967296.0.0', [1, 0], [1, 0, 0, 0], [1.0, 0, 0], [True, 0, 0], '']
    for i, value in enumerate(version_values):
        try: v = version(value)
        except ValueError: expected = 'InvalidManifest'
        else: expected = {'ok': True, 'version': '.'.join(map(str, v))}
        cases.append(Case(f'version-{i}', 'version', encode(value), '', expected))

    shared = manifest('fixture:shared', operations=['a', 'b'], events=['event'])
    def match_case(name, c, s, expected):
        cases.append(Case(name, 'match', encode(c), encode(s), expected))
    match_case('missing-shared', [shared], [], 'MissingSharedMod')
    match_case('server-missing-shared', [], [shared], 'MissingSharedMod')
    match_case('shared-version-mismatch', [shared], [{**shared, 'version': '2.0.0'}], 'SharedVersionMismatch')
    match_case('shared-data-mismatch', [shared], [{**shared, 'data_version': 1}], 'SharedDataVersionMismatch')
    match_case('shared-declaration-mismatch', [shared], [{**shared, 'events': ['other']}], 'SharedManifestMismatch')
    match_case('forbidden-client-deployment', [manifest(side='server')], [], 'ForbiddenDeploymentSide')
    match_case('forbidden-server-deployment', [], [manifest(side='client')], 'ForbiddenDeploymentSide')
    reordered = {**shared, 'operations': ['b', 'a'], 'version': [1, 0, 0]}
    match_case('normalized-metadata-equality', [shared], [reordered], {'ok': True, 'match': {'client_order': ['fixture:shared'], 'server_order': ['fixture:shared'], 'shared': ['fixture:shared']}})
    a, b = manifest('fixture:a'), manifest('fixture:b')
    z = manifest('fixture:z', side='client', before=['fixture:a'])
    match_case('relative-shared-order-mismatch', [a, b, z], [a, b], 'SharedOrderMismatch')
    side_only_c = manifest('fixture:client', side='client')
    side_only_s = manifest('fixture:server', side='server')
    match_case('side-only-independent', [side_only_c], [side_only_s], {'ok': True, 'match': {'client_order': ['fixture:client'], 'server_order': ['fixture:server'], 'shared': []}})

    old = manifest(reload='safe')
    for name, change, classification in [
        ('unchanged', {}, 'no-change'), ('upgrade-safe', {'version': '1.0.1'}, 'safe-candidate'),
        ('data-migration', {'version': '1.0.1', 'data_version': 1}, 'restart-required'),
        ('api-break', {'api_version': '2.0.0'}, 'incompatible'), ('identity-break', {'id': 'fixture:b'}, 'incompatible'),
        ('declarations-change', {'operations': ['world.clock']}, 'restart-required'),
        ('side-change', {'side': 'client'}, 'restart-required'), ('downgrade', {'version': '0.9.0'}, 'restart-required'),
        ('policy-change', {'reload': 'restart'}, 'restart-required'),
    ]:
        cases.append(Case('reload-' + name, 'reload', encode(old), encode({**old, **change}), 'CLASS:' + classification))
    restart = manifest()
    cases.append(Case('reload-restart-upgrade', 'reload', encode(restart), encode({**restart, 'version': '1.0.1'}), 'CLASS:restart-required'))
    return cases, fixture_files


def run(command, timeout=180):
    result = subprocess.run([str(x) for x in command], cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f'{command[:4]} failed ({result.returncode}):\n{result.stdout}{result.stderr}')
    return result.stdout


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--skip-build', action='store_true')
    options = parser.parse_args()
    start = time.monotonic(); binary = ROOT / 'build/mods-tests'
    checked = {}
    for source in ['src/mods.bend', 'tests/mods.bend']:
        checked[source] = run([BEND, source, '--check-only']).strip()
        assert 'ALL PROOFS CHECK' in checked[source]
    if not options.skip_build: run([BEND, 'tests/mods.bend', '-o', binary])
    assert run([binary, '--threads', 1]).strip() == 'fixtures pass'
    cases, fixtures = corpus()
    for start_index in range(0, len(cases), 15):
        group = cases[start_index:start_index + 15]
        command = [binary, '--threads', 1, 'batch']
        for case in group: command.extend([case.mode, case.a, case.b])
        lines = run(command).removesuffix('\n').split('\n')
        assert len(lines) == len(group), (start_index, len(lines), len(group))
        for case, line in zip(group, lines):
            observed = json.loads(line)
            if isinstance(case.expected, dict):
                assert observed == case.expected, (case.name, observed, case.expected)
            elif case.expected.startswith('CLASS:'):
                assert observed['ok'] is True, (case.name, observed)
                report = observed['reload']
                assert report['classification'] == case.expected[6:] and report['execution_verified'] is False, (case.name, report)
                assert report['reasons'] and all(isinstance(x, str) and x for x in report['reasons']), case.name
            else:
                assert observed['ok'] is False and observed['error'].startswith(case.expected + ':'), (case.name, observed, case.expected)
    source_text = (ROOT / 'src/mods.bend').read_text()
    assert '@unsafe' not in source_text and 'IO(' not in source_text and 'import "' not in source_text
    verdicts = {}
    for path in ['src/mods.bend', 'tests/mods.bend']:
        result = subprocess.run([str(BEND), path, '--verdict'], cwd=ROOT, capture_output=True, text=True, timeout=90)
        verdicts[path] = {'exit_code': result.returncode, 'output': (result.stdout + result.stderr).strip()}
    report = {'schema': 1, 'compiler': run([BEND, 'version']).strip(), 'source_sha256': hashlib.sha256(source_text.encode()).hexdigest(),
              'json_dependency_sha256': hashlib.sha256((ROOT / 'src/json.bend').read_bytes()).hexdigest(),
              'native_binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(), 'checker': checked, 'kernel_verdicts': verdicts,
              'independent_cases': len(cases), 'generated_dags': 200, 'input_permutations': 200,
              'all_cases_passed': True, 'finite_fixture_laws': 1, 'general_laws': ['both-side provider covers every side'],
              'fixtures': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in fixtures},
              'semantics': 'Own typed core-version/range/DAG/side/metadata compatibility, independent of Java mod loaders; no lifecycle execution claim',
              'elapsed_seconds': round(time.monotonic() - start, 3),
              'commands': ['python3 tools/test_mods.py', '/Users/chuah/.bend/bin/bend src/mods.bend --check-only',
                           '/Users/chuah/.bend/bin/bend tests/mods.bend --check-only', '/Users/chuah/.bend/bin/bend tests/mods.bend -o build/mods-tests',
                           '/Users/chuah/.bend/bin/bend src/mods.bend --verdict', '/Users/chuah/.bend/bin/bend tests/mods.bend --verdict']}
    (ROOT / 'evidence/mods-tests.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: report[key] for key in ['independent_cases', 'generated_dags', 'input_permutations', 'all_cases_passed', 'elapsed_seconds']}, indent=2))

if __name__ == '__main__': main()
