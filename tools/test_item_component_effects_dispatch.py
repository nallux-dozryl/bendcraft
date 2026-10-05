#!/usr/bin/env python3
"""Executor-only checks of the actual effect decoder and existing stew receiver."""
from __future__ import annotations

import base64
import argparse
import hashlib
import json
import sys
from pathlib import Path

import item_component_check as Previous
from reference_inventory import ROOT, canonical

ENTRY = ROOT / 'tests/item_component_effects_dispatch.bend'
REGISTRY = ROOT / 'generated/reference_registries.tsv'
REFERENCE = ROOT / 'reference/item_component.json'
EFFECT_REGISTRY = ROOT / 'reference/crafting_recipe_components.json'
UNKNOWN = 'unknown suspicious stew effect'


def pin(path):
    path = Path(path).resolve()
    data = path.read_bytes()
    return {'path': str(path), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


def corpus():
    reference = json.loads(REFERENCE.read_text())
    assert reference['pin'] == '26.3'
    assert hashlib.sha256(canonical(reference['default_components'])).hexdigest() == reference['default_components_sha256']
    registry = [line.split('\t')[2] for line in REGISTRY.read_text().splitlines()
                if line.split('\t')[0] == 'minecraft:mob_effect']
    observed = json.loads(EFFECT_REGISTRY.read_text())['effects']
    observed = [row['id'] if isinstance(row, dict) else row for row in observed]
    assert len(registry) == 40 and len(set(registry)) == 40 and set(registry) == set(observed)
    result = [{'name': name, 'mode': 'effect', 'id': name, 'ticks': 160, 'expected': True}
              for name in registry]
    for ticks in [0, 1, 159, 161, -1, -2147483648, 2147483647]:
        result.append({'name': 'speed/' + str(ticks), 'mode': 'effect',
                       'id': 'minecraft:speed', 'ticks': ticks & 0xffffffff, 'expected': True})
    bad = ['', 'minecraft:', 'minecraft:unknown', 'other:speed',
           'minecraft:speed\0', 'minecraft:speed§', 'minecraft:speed😀', 'x' * 4096]
    for name in registry:
        bad.extend([name.removeprefix('minecraft:'), name.upper(), name + ' '])
    for name in dict.fromkeys(bad):
        assert name not in registry
        result.append({'name': 'refusal/' + repr(name[:64]), 'mode': 'effect',
                       'id': name, 'ticks': 160, 'expected': False})
    base = reference['default_components']
    for row in reference['rows'][:17]:
        assert row['accepted'] and row['same_after_nbt']
        key = Previous.identity(row['components'], base)
        effects = Previous.unsigned_effects(row['components'][Previous.EFFECTS])
        result.append(Previous.fixture(row['id'] + '/validate', 'validate',
                                       id=Previous.ITEM, components=key, count=1,
                                       defaults=True, effects=effects, java_tag=row['tag']))
        result.append(Previous.fixture(row['id'] + '/nbt', 'nbt',
                                       bytes=list(base64.b64decode(row['nbt_base64'])),
                                       defaults=True, effects=effects, key=key))
    return result


def verify(case, actual):
    if case['mode'] != 'effect':
        Previous.verify(case, actual)
        return
    if not case['expected']:
        assert actual == {'accepted': False, 'error': UNKNOWN}, (case['name'], actual)
        return
    word = case['ticks']
    signed = word if word <= 0x7fffffff else word - 0x100000000
    tag = {'id': case['id']}
    if word != 160:
        tag['duration'] = signed
    expected = {'accepted': True, 'id': case['id'], 'json': tag,
                'json_read': [case['id'], word], 'nbt_read': [case['id'], word]}
    assert actual == expected, (case['name'], actual, expected)


def prepare(directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    cases = corpus()
    excluded = {'name', 'expected', 'effects', 'java_tag', 'key'}
    path = directory / 'fixtures.json'
    path.write_bytes(canonical([{k: v for k, v in case.items() if k not in excluded} for case in cases]))
    # Comparator controls cover registry aliasing, incorrect refusal and raw
    # duration loss. They do not invoke Bend or manufacture game observations.
    first = cases[0]
    controls = [({'accepted': True, 'id': 'minecraft:unknown', 'json': {'id': first['id']},
                 'json_read': [first['id'], 160], 'nbt_read': [first['id'], 160]}, first),
                ({'accepted': False, 'error': 'different refusal'}, next(x for x in cases if not x['expected'])),
                ({'accepted': True, 'id': first['id'], 'json': {'id': first['id']},
                  'json_read': [first['id'], 160], 'nbt_read': [first['id'], 161]}, first)]
    refused = 0
    for bad, case in controls:
        try:
            verify(case, bad)
        except AssertionError:
            refused += 1
    assert refused == len(controls)
    return {'input': pin(path), 'registry': pin(REGISTRY), 'effect_registry': pin(EFFECT_REGISTRY), 'reference': pin(REFERENCE),
            'helper': pin(__file__), 'entry': pin(ENTRY), 'cases': len(cases),
            'mapping': 40, 'signed_word_edges': 7,
            'unknown_refusals': sum(not c['expected'] for c in cases),
            'existing_java_recipe_receiver_cases': 34, 'comparator_controls_refused': refused}


def suite(executor, directory):
    cases = corpus()
    manifest = prepare(directory)
    before = [pin(REGISTRY), pin(EFFECT_REGISTRY), pin(REFERENCE), pin(__file__), pin(ENTRY)]
    stdout, process = executor('effect-registry-and-existing-stew', [manifest['input']['path']])
    rows = [json.loads(line) for line in stdout.splitlines()]
    assert len(rows) == len(cases), (len(rows), len(cases))
    for case, row in zip(cases, rows, strict=True):
        verify(case, row)
    assert before == [pin(REGISTRY), pin(EFFECT_REGISTRY), pin(REFERENCE), pin(__file__), pin(ENTRY)]
    return {'status': 'passed', **manifest, 'process': process,
            'stdout_sha256': hashlib.sha256(stdout.encode()).hexdigest()}


def main():
    import build_native as Build
    import test_remote_resource_client as R
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true')
    parser.add_argument('--binary', type=Path)
    parser.add_argument('--_build-child', type=Path)
    args = parser.parse_args()
    if args._build_child:
        from test_fall_reset_world_continuation_r2 import retry_scope
        with retry_scope(Build):
            report = Build.ensure_native(ENTRY, args._build_child / 'native',
                                         bend=Previous.BEND,
                                         cache_dir=ROOT / 'build/item-component-effects/native-cache')
        assert report['retries'] == 0
        R.write(args._build_child / 'build.json', report, True)
        return
    if not args.build and not args.binary:
        parser.error('Supply --build or an actual --binary')
    work = ROOT / 'build/item-component-effects/native-001'
    work.mkdir(exist_ok=False)
    R.WORK = work
    before = [pin(ENTRY), pin(__file__), pin(ROOT / 'src/item_component_effects.bend')]
    if args.build:
        build = R.bounded([sys.executable, str(Path(__file__).resolve()),
                           '--_build-child', str(work)], 180, 'build')
        R.write(work / 'build-process.json', build, True)
        R.process_ok(build)
    binary = (args.binary or work / 'native').resolve()
    binary_before = pin(binary)
    def executor(label, argv):
        row = R.bounded([str(binary), '--gpu', 'off', '--threads', '1', '--', *argv], 30, label)
        R.write(work / 'native-process.json', row, True)
        R.process_ok(row)
        return Path(row['stdout']['path']).read_text(), row
    result = suite(executor, work / 'fixtures')
    assert before == [pin(ENTRY), pin(__file__), pin(ROOT / 'src/item_component_effects.bend')]
    assert binary_before == pin(binary)
    result.update(binary=binary_before, source_inputs=before,
                  sources_unchanged=True, binary_unchanged=True)
    R.write(work / 'result.json', result, True)
    print(json.dumps({'status': result['status'], 'cases': result['cases'],
                      'seconds': result['process']['seconds'], 'binary': binary_before}))


if __name__ == '__main__':
    main()
