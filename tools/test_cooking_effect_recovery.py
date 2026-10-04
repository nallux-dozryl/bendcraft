#!/usr/bin/env python3
"""Actual Bend delivery/codec checks with independent physical NBT fixtures."""
from __future__ import annotations

import argparse
import dataclasses
import json
import os
import sys
from pathlib import Path

import build_native as Build
import test_campfire_authority as Paths
import test_nbt as N
import test_remote_resource_client as R

ROOT = Path(__file__).resolve().parents[1]
ENTRY = ROOT / 'tests/cooking_effect_recovery.bend'
LAWS = ROOT / 'src/cooking_effect_delivery_laws.bend'
ROOTS = ['missing_item_owner_retains_complete_ordered_suffix',
         'missing_xp_owner_retains_complete_ordered_suffix',
         'missing_comparator_owner_retains_complete_ordered_suffix',
         'missing_block_publisher_retains_complete_ordered_suffix',
         'missing_event_publisher_retains_complete_ordered_suffix',
         'acknowledged_local_marker_preserves_remaining_delivery']
GUARDS = ['local marker and zero notifications acknowledge only safe prefix',
          'empty item drop remains a real RNG-owner refusal',
          'XP keeps raw uses rate and unavailable owner',
          'dirty keeps comparator publication intent',
          'nonzero block update keeps actual count',
          'nonzero game event keeps actual count',
          'all acknowledged local effects complete', 'empty effect delivery complete',
          'byte budget refuses complete recovery encode',
          'depth budget refuses complete recovery encode',
          'element budget refuses complete recovery encode',
          'ordered duplicate raw effect queue roundtrip', 'truncated recovery refuses']


def compound(**fields):
    return N.Value(10, tuple((N.text(k), v) for k, v in fields.items()))


def integer(value):
    return N.Value(3, value)


def string_words(value):
    return N.Value(11, tuple(map(ord, value)))


def effect(kind, payload=None):
    return compound(kind=integer(kind), position=compound(
        dimension=string_words('minecraft:the_nether'), x=integer(0x80000000),
        y=integer(0xffffffff), z=integer(0x7fffffff)),
        payload=compound() if payload is None else payload)


def fixture():
    empty = effect(1, compound(slot=integer(0), item=compound()))
    component = 'BendCraftComponents1\t64\t{"text":"§😀"}\0'
    return [effect(0), effect(4, string_words('0')), effect(5, string_words('0')),
            empty, effect(1, compound(slot=integer(2), item=compound(
                id=string_words('minecraft:stone'), components=string_words(component), count=integer(3)))),
            effect(2, compound(recipe=string_words('minecraft:cooked_beef'), uses=integer(3), experience_bits=integer(0x3f000000))),
            effect(2, compound(recipe=string_words('fixture:zero'), uses=integer(0x80000000), experience_bits=integer(0x80000000))),
            effect(2, compound(recipe=string_words('fixture:nan'), uses=integer(0xffffffff), experience_bits=integer(0x7fc01211))),
            effect(3), effect(4, string_words('4294967296')), effect(5, string_words('17')),
            effect(0), empty]


def root(values, *, name='bendex:cooking-effects', format=1, element=10):
    return N.RootTag(N.text(name), compound(format=integer(format), effects=N.Value(9, (element, tuple(values)))))


def replace_field(value, key, replacement):
    return N.Value(10, tuple((k, replacement if k == N.text(key) else v) for k, v in value.payload))


def corpus():
    rows = [('full-raw', N.encode_root(root(fixture())), True),
            ('empty', N.encode_root(root([])), True)]
    invalid = [root([], name='wrong'), root([], format=2), root([], element=3)]
    good = root([])
    invalid.append(dataclasses.replace(good, value=N.Value(10, good.value.payload + ((N.text('extra'), integer(0)),))))
    invalid.append(dataclasses.replace(good, value=N.Value(10, good.value.payload[:1])))
    variants = [effect(6), replace_field(effect(0), 'position', integer(0)),
                effect(0, compound(extra=integer(0))),
                effect(2, compound(recipe=string_words('fixture:nan'), uses=integer(1), experience_bits=N.Value(5, 0x7fc01211))),
                effect(1, compound(slot=N.Value(2, 0), item=compound())),
                effect(1, compound(slot=integer(0), item=compound(id=string_words('minecraft:stone'), components=N.Value(8, N.text('')), count=integer(1)))),
                effect(4, string_words('01')), effect(5, string_words('-1'))]
    point = effect(0).payload[1][1]
    variants.append(replace_field(effect(0), 'position', N.Value(10, tuple(reversed(point.payload)))))
    base = effect(0)
    variants.append(N.Value(10, base.payload + (base.payload[0],)))
    invalid.extend(root([v]) for v in variants)
    rows.extend((f'schema-{i:02}', N.encode_root(v), False) for i, v in enumerate(invalid))
    wire = rows[0][1]
    rows.extend([('truncated', wire[:-1], False), ('trailing', wire + b'\0', False)])
    return rows


def source_pins():
    snapshot = Build.Snapshot()
    base = Paths.BEND.resolve().parent.parent / 'bend2/base.bend'
    for entry in (ENTRY, LAWS):
        Build.source_graph(entry, base, os.environ, snapshot)
    for row in list(snapshot.files.values()):
        if row['kind'] in ('bend', 'base'):
            path = Path(row['path'])
            for foreign in Build.foreign_paths(path.read_text()):
                if foreign.endswith('.js'):
                    snapshot.add(path.parent / foreign, 'javascript-effect')
    for path in (Path(__file__), Path(N.__file__), Paths.BEND, Paths.NODE, Paths.KERNEL,
                 ROOT / 'tools/cooking_world_proof.mjs'):
        snapshot.add(path, 'verification-tool')
    return snapshot.manifest()


def build_child(directory):
    from test_fall_reset_world_continuation_r2 import retry_scope
    with retry_scope(Build):
        report = Build.ensure_native(ENTRY, directory / 'native', bend=Paths.BEND,
                                     cache_dir=ROOT / 'build/cooking-effect-recovery/native-cache')
    R.require(report['retries'] == 0, 'Recovery native builder retried')
    R.write(directory / 'build.json', report, True)


def main(native=True):
    work = ROOT / 'build/cooking-effect-recovery/checks'
    work.mkdir(parents=True, exist_ok=True)
    number = 1
    while (directory := work / f'{number:03}').exists():
        number += 1
    directory.mkdir()
    before = source_pins()
    R.write(directory / 'sources.json', before, True)
    old_work = R.WORK
    processes = []
    try:
        R.WORK = directory

        def run(argv, label, cap=30):
            row = R.bounded(argv, cap, label)
            processes.append(row)
            R.process_ok(row)
            return row

        ordinary = run([Paths.BEND, ENTRY, '--check-only'], 'ordinary')
        R.require('ALL PROOFS CHECK' in Path(ordinary['stdout']['path']).read_text() and
                  not Path(ordinary['stderr']['path']).read_bytes(), 'Recovery ordinary check failed')
        binary = None
        if native:
            run([sys.executable, Path(__file__), '--build-child', directory], 'native-build', 600)
            binary = R.pin(directory / 'native')
            invoke = [directory / 'native']
        else:
            invoke = [Paths.BEND, ENTRY, '--']
        observed = run([*invoke, 'cases', str(0x7fc01211)], 'actual-native' if native else 'actual-js')
        lines = Path(observed['stdout']['path']).read_text().splitlines()
        R.require(lines[:len(GUARDS)] == ['ok ' + guard for guard in GUARDS] and
                  len(lines) == len(GUARDS) + 1 and not Path(observed['stderr']['path']).read_bytes(),
                  'Delivery/recovery guards or diagnostics differ')
        prefix, byte_text = lines[-1].split(' ', 1)
        R.require(prefix == 'bytes', 'Missing actual recovery bytes')
        actual = bytes(map(int, byte_text.split(',')))
        expected = N.encode_root(root(fixture()))
        R.require(actual == expected and N.parse(actual) == root(fixture()),
                  'Recovery differs from independently constructed complete raw NBT')
        (directory / 'actual.nbt').write_bytes(actual)
        cases = []
        for name, wire, accepted in corpus():
            path = directory / (name + '.nbt')
            path.write_bytes(wire)
            cases.append({'name': name, 'input': R.pin(path), 'accepted': accepted})
        checked = run([*invoke, 'decode', *[c['input']['path'] for c in cases]],
                      'physical-corpus-native' if native else 'physical-corpus-js')
        R.require(Path(checked['stdout']['path']).read_text().splitlines() ==
                  [('accepted ' if c['accepted'] else 'refused ') + c['input']['path'] for c in cases] and
                  not Path(checked['stderr']['path']).read_bytes(), 'Strict physical recovery corpus differs')
        exporter = (ROOT / 'tools/cooking_world_proof.mjs').read_text()
        start = exporter.index('const roots=')
        end = exporter.index(';', start) + 1
        exporter = exporter[:start] + 'const roots=' + json.dumps(ROOTS) + ';' + exporter[end:]
        script = directory / 'proof.mjs'
        script.write_text(exporter)
        run([Paths.NODE, '--max-old-space-size=1536', '--stack-size=4096', '--experimental-transform-types',
             script, directory, LAWS], 'proof-export')
        scope = json.loads((directory / 'scope.json').read_bytes())
        R.require(not scope['exclusions'], 'Actual delivery proof roots excluded')
        run(['/usr/bin/env', 'LEAN_STACK_SIZE=67108864', Paths.KERNEL, directory / 'selected.bendtt'], 'kernel')
        R.require(before == source_pins(), 'Recovery inputs changed during execution')
        if binary:
            R.require(binary == R.pin(directory / 'native'), 'Recovery binary changed during execution')
        result = {'schema': 1, 'status': 'PASS', 'guards': GUARDS, 'cases': cases, 'processes': processes,
                  'actual_wire': R.pin(directory / 'actual.nbt'), 'source_manifest': R.pin(directory / 'sources.json'),
                  'delivery': R.pin(ROOT / 'src/cooking_effect_delivery.bend'),
                  'recovery': R.pin(ROOT / 'src/cooking_effect_recovery.bend'),
                  'proof': json.loads((directory / 'selection.json').read_bytes()),
                  'ir': R.pin(directory / 'selected.bendtt'), 'exclusions': scope['exclusions'],
                  'binary': binary, 'build': R.pin(directory / 'build.json') if native else None,
                  'scope': 'Actual Bend ' + ('native' if native else 'default-JS') + ' delivery refusal and strict complete raw queue codec; '
                           'six independent-kernel delivery contracts. Actor atomic publication, cold restore '
                           'and real item/XP/RNG/publication owners require their live consumer.'}
        R.write(directory / 'result.json', result, True)
        R.write(ROOT / f'evidence/cooking-effect-recovery-{number:03}.json', result, True)
        print(json.dumps({'status': 'PASS', 'guards': len(GUARDS), 'physical_cases': len(cases),
                          'kernel_laws': len(ROOTS), 'directory': str(directory)}), flush=True)
    except BaseException as error:
        failed = {'status': 'FAIL', 'type': type(error).__name__, 'message': str(error), 'processes': processes}
        R.write(directory / 'failure.json', failed, True)
        R.write(ROOT / f'evidence/cooking-effect-recovery-{number:03}-failure.json', failed, True)
        raise
    finally:
        R.WORK = old_work


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--js', action='store_true', help='Reproduce default-JS raw NaN representation boundary')
    parser.add_argument('--build-child', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.build_child:
        build_child(args.build_child)
    else:
        main(not args.js)
