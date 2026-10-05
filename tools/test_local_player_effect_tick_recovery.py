#!/usr/bin/env python3
"""Independent ordered NBT for the actual full Tick.State recovery projection.

Reuse the existing entity-codec single-attempt builder/process workflow. Python
constructs physical fixtures only; runtime ownership and codec semantics stay
in the production Bend modules. This does not change actor persistence format.
"""
from __future__ import annotations

import argparse
import dataclasses
import json
from pathlib import Path
import sys

import test_local_player_effect_entities_codec as H
import test_nbt as N

ROOT = H.ROOT
ENTRY = ROOT / 'tests/local_player_effect_tick_recovery.bend'
CODEC = ROOT / 'src/local_player_effect_tick_recovery_codec.bend'
WORK = ROOT / 'build/local-player-effect-tick-recovery'
H.ENTRY = ENTRY
H.CODEC = CODEC
GUARDS = (
    'encode byte limit refuses', 'encode depth limit refuses', 'encode element limit refuses',
    'old snapshot has no runtime authority', 'old snapshot has no sound authority',
    'old snapshot cannot restore guessed runtimes',
    'known empty runtime restores without invented sound',
    'known empty runtime differs from unavailable',
    'noncanonical tail refuses while original owner survives',
    'complete raw runtime and separate sound roundtrip',
    'sole entity owner survives restore and repeated inspect',
    'decode byte limit refuses', 'decode depth limit refuses', 'decode element limit refuses',
    'truncated snapshot refuses', 'trailing snapshot refuses',
)


def vector(index=0):
    return H.array(0x7ff81234, 0x56789abc + index, 0x80000000, index,
                   0xfff80bcd, 0x10203040 + index)


def fluid(index):
    return H.compound(height=H.array(0x7ff00000, index), flow=vector(index + 10),
                      count=H.integer(0xffffffff - index), present=H.integer(index == 1))


def movement(index):
    return H.compound(**{'from': vector(index), 'to': vector(index + 1), 'requested': vector(index + 2)})


def runtime(index):
    return H.compound(
        physical=H.compound(no_gravity=H.integer(1), no_physics=H.integer(0),
                            suppress_bounce=H.integer(1), horizontal=H.integer(0),
                            vertical=H.integer(1), below=H.integer(0),
                            minor_horizontal=H.integer(1), stuck=vector(index + 20)),
        base=H.compound(invulnerable_time=H.integer(0xffffffff - index),
                        boarding_cooldown=H.integer(0x80000000 + index),
                        was_touching_water=H.integer(1), was_eye_water=H.integer(0),
                        powder_snow=H.integer(1), was_powder_snow=H.integer(0),
                        sprinting=H.integer(1), swimming=H.integer(0), freezing=H.integer(1), silent=H.integer(0),
                        last_position=N.Value(9, (11, () if index == 0 else (vector(index),))),
                        speed=vector(index + 30)),
        fluids=H.compound(water=fluid(0), lava=fluid(1), eye_water=H.integer(0),
                          eye_lava=H.integer(1), fast_lava=H.integer(0)),
        pending=N.Value(9, (10, (movement(index), movement(index + 3), movement(index)))),
        movements=N.Value(9, (10, (movement(index + 6), movement(index + 9)))),
        support=H.compound(main=H.array() if index == 0 else H.array(0xffffffff, 0x80000000, 0x7fffffff),
                           on_ground_no_blocks=H.integer(index == 0)),
        tail=N.Value(9, (10, ())))


def entry(identity, index):
    return H.compound(id=H.integer(identity), runtime=runtime(index))


def root(*, entities=None, runtimes=True, entries=None, sound=True):
    values = (entry(0xffffffff, 0), entry(0x80000000, 1), entry(0xffffffff, 0)) if entries is None else tuple(entries)
    runtime_value = H.compound(present=H.integer(0)) if not runtimes else H.compound(
        present=H.integer(1), entries=N.Value(9, (10, values)))
    sound_value = N.Value(9, (10, (H.random_source(0, 0xffff, 0xffffffff),))) if sound is True else (
        N.Value(9, (10, ())) if sound is False else N.Value(9, (10, (sound,))))
    return N.RootTag(N.text('bendex:local-player-effect-tick-recovery'), H.compound(
        format=H.integer(1), entities=H.root().value if entities is None else entities,
        runtimes=runtime_value, sound=sound_value))


def corpus():
    full = root()
    rows = [('complete-raw', N.encode_root(full), True),
            ('known-empty', N.encode_root(root(entities=H.root([]).value, entries=[], sound=False)), True),
            ('legacy-unavailable', N.encode_root(root(runtimes=False, sound=False)), True),
            ('runtime-unavailable-sound-known', N.encode_root(root(runtimes=False)), True),
            ('known-runtime-sound-unavailable', N.encode_root(root(sound=False)), True),
            ('sound-zero-xoroshiro', N.encode_root(root(sound=H.random_source(1, 0, 0, 0, 0))), True),
            ('sound-raw-legacy-words', N.encode_root(root(sound=H.random_source(0, 0xffffffff, 0x80000000))), True),
            ('ordered-reversed-runtime-list', N.encode_root(root(entries=[entry(0x80000000, 1), entry(0xffffffff, 0)])), True),
            ('known-empty-runtime-nonempty-records', N.encode_root(root(entries=[])), True)]

    def add(name, document):
        rows.append((name, N.encode_root(document), False))

    add('wrong-root-name', dataclasses.replace(full, name=N.text('wrong')))
    add('wrong-root-type', dataclasses.replace(full, value=H.integer(1)))
    for number in (0, 2, 0xffffffff):
        add(f'format-{number}', H.changed(full, ('format',), H.integer(number)))

    compounds = [(), ('runtimes',), ('runtimes', 'entries', 0),
                 ('runtimes', 'entries', 0, 'runtime'), ('runtimes', 'entries', 0, 'runtime', 'physical'),
                 ('runtimes', 'entries', 0, 'runtime', 'base'), ('runtimes', 'entries', 0, 'runtime', 'fluids'),
                 ('runtimes', 'entries', 0, 'runtime', 'fluids', 'water'),
                 ('runtimes', 'entries', 0, 'runtime', 'fluids', 'lava'),
                 ('runtimes', 'entries', 0, 'runtime', 'support'),
                 ('runtimes', 'entries', 0, 'runtime', 'pending', 0),
                 ('runtimes', 'entries', 0, 'runtime', 'movements', 0), ('sound', 0)]
    booleans, arrays, lists = [], [], []

    def walk(value, path):
        if value.kind == 10:
            for key, member in value.payload:
                name = ''.join(map(chr, key))
                child = path + (name,)
                walk(member, child)
                if name in ('no_gravity', 'no_physics', 'suppress_bounce', 'horizontal', 'vertical', 'below',
                            'minor_horizontal', 'was_touching_water', 'was_eye_water', 'powder_snow',
                            'was_powder_snow', 'sprinting', 'swimming', 'freezing', 'silent', 'present',
                            'eye_water', 'eye_lava', 'fast_lava', 'on_ground_no_blocks') and member.kind == 3:
                    booleans.append(child)
        elif value.kind == 9:
            lists.append(path)
            for i, member in enumerate(value.payload[1]):
                walk(member, path + (i,))
        elif value.kind == 11:
            arrays.append(path)

    walk(H.at(full.value, ('runtimes', 'entries', 0)), ('runtimes', 'entries', 0))
    for path in compounds:
        value = H.at(full.value, path)
        label = '-'.join(map(str, path)) or 'root'
        for i, (key, member) in enumerate(value.payload):
            name = ''.join(map(chr, key))
            add(f'{label}-missing-{name}', H.changed(full, path, N.Value(10, value.payload[:i] + value.payload[i + 1:])))
            add(f'{label}-duplicate-{name}', H.changed(full, path, N.Value(10, value.payload[:i + 1] + ((key, member),) + value.payload[i + 1:])))
            add(f'{label}-wrong-type-{name}', H.changed(full, path + (name,), N.Value(8, N.text('wrong'))))
        add(label + '-extra', H.changed(full, path, N.Value(10, value.payload + ((N.text('unexpected'), H.integer(0)),))))
        for i in range(len(value.payload) - 1):
            members = list(value.payload)
            members[i], members[i + 1] = members[i + 1], members[i]
            add(f'{label}-order-{i}', H.changed(full, path, N.Value(10, tuple(members))))
    for path in booleans:
        label = '-'.join(map(str, path))
        for number in (2, 0xffffffff):
            add(f'{label}-nonbool-{number}', H.changed(full, path, H.integer(number)))
    for path in arrays:
        value = H.at(full.value, path)
        label = '-'.join(map(str, path))
        # The empty support optional can become exactly3; length1/2/4 are invalid.
        lengths = (1, 2, 4) if path[-1] == 'main' else (len(value.payload) - 1, len(value.payload) + 1)
        for size in lengths:
            add(f'{label}-count-{size}', H.changed(full, path, H.array(*range(size))))
        add(label + '-long-tag', H.changed(full, path, N.Value(12, value.payload)))
    for path in lists:
        value = H.at(full.value, path)
        for kind in (0, 3, 11 if value.payload[0] != 11 else 10):
            if kind != value.payload[0]:
                add('-'.join(map(str, path)) + '-element-' + str(kind), H.changed(full, path, N.Value(9, (kind, ()))))
    for path in [('runtimes', 'entries', 0, 'runtime', 'base', 'last_position'), ('sound',)]:
        kind, values = H.at(full.value, path).payload
        # last_position in runtime0 is None, but two Some values are never allowed.
        values = (vector(0), vector(1)) if kind == 11 else (H.random_source(0, 0, 1), H.random_source(0, 0, 2))
        add('-'.join(map(str, path)) + '-two-values', H.changed(full, path, N.Value(9, (kind, values))))
    add('noncanonical-runtime-tail', H.changed(full, ('runtimes', 'entries', 0, 'runtime', 'tail'), N.Value(9, (10, (runtime(1),)))))
    add('runtime-present-discriminant', H.changed(full, ('runtimes', 'present'), H.integer(2)))
    add('runtime-unavailable-with-entries', H.changed(full, ('runtimes', 'present'), H.integer(0)))
    add('sound-invalid-kind', H.changed(full, ('sound', 0, 'kind'), H.integer(2)))
    for count in (0, 1, 3, 4):
        add('sound-legacy-word-count-' + str(count), H.changed(full, ('sound', 0, 'words'), H.array(*range(count))))

    # Reuse independently constructed entity-schema corruptions within the new
    # outer snapshot, without re-running the historical entity observer.
    for name, wire, accepted in H.corpus():
        if name.startswith(('truncated-', 'trailing', 'malformed-', 'invalid-root-', 'negative-count-')):
            continue
        try:
            document = N.parse(wire)
        except ValueError:
            # Invalid physical list tags have no host typed tree to embed.
            # New outer physical corruption cases are constructed below.
            continue
        if name in ('wrong-root-name', 'wrong-root-type'):
            continue
        combined = root(entities=document.value)
        rows.append(('entities-' + name, N.encode_root(combined), accepted))
    wire = rows[0][1]
    rows.extend([('truncated-header', wire[:2], False), ('truncated-middle', wire[:len(wire) // 2], False),
                 ('truncated-end', wire[:-1], False), ('trailing-byte', wire + b'\0', False),
                 ('invalid-root-tag', b'\x0d' + wire[1:], False),
                 ('malformed-root-mutf', wire[:3] + b'\xff' + wire[4:], False)])
    H.require(len({name for name, _, _ in rows}) == len(rows), 'Duplicate corpus label')
    return rows


def directory():
    (WORK / 'checks').mkdir(parents=True, exist_ok=True)
    number = 1
    while (path := WORK / 'checks' / f'{number:03}').exists():
        number += 1
    path.mkdir()
    return number, path


def prepare():
    path = WORK / 'prepared'
    path.mkdir(parents=True, exist_ok=True)
    cases = corpus()
    for name, wire, accepted in cases:
        (path / (name + '.nbt')).write_bytes(wire)
    expected = N.encode_root(root())
    H.require(N.parse(expected) == root(), 'Independent typed NBT tree failed host roundtrip')
    report = {'status': 'PREPARED', 'cases': len(cases), 'accepted': sum(c[2] for c in cases),
              'golden_bytes': len(expected), 'golden_sha256': __import__('hashlib').sha256(expected).hexdigest(),
              'runtime_entry_order': [0xffffffff, 0x80000000, 0xffffffff], 'guards': list(GUARDS),
              'scope': 'Independent physical fixture preparation only; no Bend or native execution.'}
    (path / 'prepared.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))


def build_child(path):
    with H.forbid_retries():
        report = H.Build.ensure_native(ENTRY, path / 'native', bend=H.BEND, cache_dir=WORK / 'native-cache')
    H.require(report['retries'] == 0, 'Recovery build retried')
    H.write(path / 'build.json', report)


def source_pins():
    rows = H.source_pins()
    own = H.pin(Path(__file__))
    return rows + [dict(own, lookup=own['path'], kind='verification-tool')]


def main(source_only=False):
    number, path = directory()
    before = source_pins()
    H.write(path / 'sources.json', before)
    processes = []
    try:
        def run(argv, label, cap):
            result = H.bounded(path, argv, label, cap)
            processes.append(result)
            H.process_ok(result)
            return result
        ordinary = run([H.BEND, ENTRY, '--check-only'], 'ordinary', 60)
        H.require('ALL PROOFS CHECK' in Path(ordinary['stdout']['path']).read_text() and
                  not Path(ordinary['stderr']['path']).read_bytes(), 'Recovery ordinary check failed')
        if source_only:
            report = {'status': 'SOURCE_PASS', 'processes': processes, 'source_manifest': H.pin(path / 'sources.json')}
        else:
            run([sys.executable, Path(__file__), '--build-child', path], 'native-build', 600)
            binary = H.pin(path / 'native')
            actual = run([path / 'native', '--gpu', 'off', '--threads', '1', 'cases'], 'actual-native', 60)
            lines = Path(actual['stdout']['path']).read_text().splitlines()
            H.require(lines[:-1] == ['ok ' + label for label in GUARDS] and lines[-1].startswith('bytes ') and
                      not Path(actual['stderr']['path']).read_bytes(), 'Runtime guards differ')
            wire = H.parse_bytes(lines[-1][6:])
            expected = N.encode_root(root())
            (path / 'actual.nbt').write_bytes(wire)
            (path / 'expected.nbt').write_bytes(expected)
            H.require(wire == expected and N.parse(wire) == root(), 'Full raw recovery differs from independent ordered NBT')
            cases = []
            for name, raw, accepted in corpus():
                fixture = path / (name + '.nbt')
                fixture.write_bytes(raw)
                cases.append({'name': name, 'input': H.pin(fixture), 'accepted': accepted})
            output = run([path / 'native', '--gpu', 'off', '--threads', '1', 'decode', *[c['input']['path'] for c in cases]],
                         'physical-corpus-native', 120)
            lines = Path(output['stdout']['path']).read_text().splitlines()
            H.require(len(lines) == len(cases) and not Path(output['stderr']['path']).read_bytes(), 'Corpus output mismatch')
            for case, line in zip(cases, lines):
                prefix = 'accepted ' + case['input']['path'] + ' '
                if case['accepted']:
                    H.require(line.startswith(prefix) and H.parse_bytes(line[len(prefix):]) == Path(case['input']['path']).read_bytes(),
                              'Accepted bytes changed/refused: ' + case['name'])
                else:
                    H.require(line == 'refused ' + case['input']['path'], 'Malformed recovery accepted: ' + case['name'])
            H.require(binary == H.pin(path / 'native'), 'Binary drift')
            report = {'status': 'PASS', 'guards': list(GUARDS), 'cases': cases, 'processes': processes,
                      'accepted': sum(c['accepted'] for c in cases), 'binary': binary,
                      'actual_wire': H.pin(path / 'actual.nbt'), 'expected_wire': H.pin(path / 'expected.nbt'),
                      'source_manifest': H.pin(path / 'sources.json'), 'build': H.pin(path / 'build.json'),
                      'scope': 'Actual native full Tick.State Data projection, exact raw ordered NBT and strict refusals. No sound bootstrap, Java transient persistence claim, actor format5/save/coldrestart integration, or live entity section authority.'}
        H.require(before == source_pins(), 'Recovery source drift')
        H.write(path / 'result.json', report)
        H.write(ROOT / f'evidence/local-player-effect-tick-recovery-{number:03}.json', report)
        print(json.dumps({'status': report['status'], 'cases': len(report.get('cases', [])), 'directory': str(path)}))
    except BaseException as error:
        report = {'status': 'FAIL', 'error': repr(error), 'processes': processes, 'source_manifest': H.pin(path / 'sources.json')}
        H.write(path / 'failure.json', report)
        H.write(ROOT / f'evidence/local-player-effect-tick-recovery-{number:03}-failure.json', report)
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--prepare', action='store_true')
    group.add_argument('--ordinary', action='store_true')
    group.add_argument('--native', action='store_true')
    parser.add_argument('--build-child', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.build_child:
        build_child(args.build_child)
    elif args.prepare:
        prepare()
    else:
        main(args.ordinary)
