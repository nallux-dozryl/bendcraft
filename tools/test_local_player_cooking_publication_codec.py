#!/usr/bin/env python3
"""Actual native publication recovery codec against independent ordered NBT.

This owns fixtures and bounded processes only. Production decoding, validation
and encoding run in the unchanged Bend codec. It does not authenticate a catalog
or establish durable actor recovery, publisher behavior or a proof verdict.
"""
from __future__ import annotations

import argparse
import dataclasses
import json
import os
from pathlib import Path
import sys

import test_local_player_effect_entities_codec as H

Build, N = H.Build, H.N
ROOT, BEND = H.ROOT, H.BEND
ENTRY = ROOT / 'tests/local_player_cooking_publication_codec.bend'
CODEC = ROOT / 'src/local_player_cooking_publication_codec.bend'
WORK = ROOT / 'build/local-player-cooking-publication-codec'
MAX_NAT, LARGE = 281474976710655, 1099511627783
BLOCK = 'fixture:\0§😀\ud800\udfff'
KEYS = ('minecraft:overworld/0/0/0', 'minecraft:overworld/0/0/1',
        'minecraft:overworld/0/0/2',
        'minecraft:the_nether/4294967295/2147483648/2147483647')
GUARDS = (
    'encode byte budget refuses', 'encode depth budget refuses', 'encode element budget refuses',
    'empty owner roundtrip', 'empty trie branch refuses', 'duplicate trie key refuses',
    'noncanonical position key refuses', 'missing latest receipt refuses', 'duplicate dirty chunk refuses',
    'complete tree and raw source roundtrip', 'exact byte depth element bounds accept',
    'one byte below encode bound refuses', 'one byte below decode bound refuses',
    'one level below encode bound refuses', 'one level below decode bound refuses',
    'one element below encode bound refuses', 'one element below decode bound refuses',
    'decode byte budget refuses', 'decode depth budget refuses',
    'decode element budget refuses', 'truncated input refuses', 'trailing input refuses',
)
compound, integer, array, words = H.compound, H.integer, H.array, H.string_words
at, changed, pin, write, require = H.at, H.changed, H.pin, H.write, H.require


def natural(value):
    return words(str(value))


def leaf(key, value):
    return compound(kind=integer(1), key=words(key), value=natural(value))


def tip():
    return compound(kind=integer(0))


def node(position, lo, hi):
    return compound(kind=integer(2), position=natural(position), lo=lo, hi=hi)


def counters():
    # Fixed independent Patricia bitstream: each char has presence1 + 32 raw
    # bits. The first differing bits for these four keys are358,823,824.
    return node(358, node(823, node(824, leaf(KEYS[0], 0), leaf(KEYS[1], LARGE)),
                          leaf(KEYS[2], 1)), leaf(KEYS[3], MAX_NAT))


def position(dimension='minecraft:the_nether', x=0xffffffff, y=0x80000000, z=0x7fffffff):
    return compound(dimension=words(dimension), x=integer(x), y=integer(y), z=integer(z))


def chunk(dimension='minecraft:the_nether', x=0xffffffff, z=0x07ffffff):
    return compound(dimension=words(dimension), x=integer(x), z=integer(z))


def binding(family=5, lit=1):
    return compound(state=integer(0xfffffffe if lit else 0x80000000), block=words(BLOCK),
                    family=integer(family), lit=integer(lit), unlit_state=integer(0x80000000),
                    lit_state=integer(0xfffffffe))


def source(family=5, lit=1, incarnation=MAX_NAT):
    return compound(position=position(), binding=binding(family, lit), incarnation=natural(incarnation))


def receipt(family=5, lit=1, incarnation=MAX_NAT, sequence=MAX_NAT):
    return compound(position=position(), source=source(family, lit, incarnation), chunk=chunk(),
                    sequence=natural(sequence))


def dirty(target, sequence):
    return compound(chunk=target, sequence=natural(sequence))


def root(tree=None, *, sequence=MAX_NAT, unsaved=None, latest=None):
    if tree is None:
        tree = counters()
    if unsaved is None:
        unsaved = (dirty(chunk(), MAX_NAT), dirty(chunk('minecraft:overworld', 16, 0xffffffff), LARGE))
    if latest is None:
        latest = (receipt(),)
    return N.RootTag(N.text('bendex:cooking-publication'), compound(
        format=integer(1), incarnations=tree,
        journal=compound(sequence=natural(sequence), unsaved=N.Value(9, (10, tuple(unsaved))),
                         last=N.Value(9, (10, tuple(latest))))))


def corpus():
    full = root()
    empty = root(tip(), sequence=0, unsaved=(), latest=())
    rows = [('full-topology-raw', N.encode_root(full), True), ('empty', N.encode_root(empty), True),
            ('removed-owner-counter-max', N.encode_root(root(leaf(KEYS[3], MAX_NAT), sequence=0,
                                                            unsaved=(), latest=())), True),
            ('saved-journal-no-dirties', N.encode_root(root(unsaved=())), True)]

    def add(label, document, accepted=False):
        rows.append((label, N.encode_root(document), accepted))

    for family in range(6):
        for lit in range(2):
            add(f'family-{family}-lit-{lit}', root(latest=(receipt(family, lit),)), True)
    # Historical latest-source token may precede the durable current counter.
    add('historical-incarnation', root(latest=(receipt(incarnation=0),)), True)
    add('missing-counter-incarnation-zero', root(tip(), latest=(receipt(incarnation=0),)), True)
    add('missing-counter-positive-incarnation', root(tip(), latest=(receipt(incarnation=1),)))
    add('counter-less-than-receipt', root(leaf(KEYS[3], 1), latest=(receipt(incarnation=2),)))
    # Prefix termination is a real Patricia split bit, not a character payload.
    add('prefix-key-split', root(node(825, leaf('minecraft:overworld/0/0/1', 1),
                                             leaf('minecraft:overworld/0/0/10', MAX_NAT)),
                                 sequence=0, unsaved=(), latest=()), True)
    for key in ('minecraft:overworld/4294967295/2147483648/4294967295',
                'minecraft:the_end/0/4294967295/2147483647'):
        add('known-key-' + key.split('/')[0].split(':')[1],
            root(leaf(key, LARGE), sequence=0, unsaved=(), latest=()), True)

    add('wrong-root-name', dataclasses.replace(full, name=N.text('wrong')))
    add('root-name-with-nul', dataclasses.replace(full, name=N.text('bendex:cooking-publication\0')))
    add('root-name-with-surrogate', dataclasses.replace(full, name=N.text('bendex:cooking-publication\ud800')))
    add('wrong-root-type', dataclasses.replace(full, value=integer(1)))
    for value in (0, 2, 0xffffffff):
        add(f'format-{value}', changed(full, ('format',), integer(value)))

    compounds = [(), ('incarnations',), ('incarnations', 'lo'), ('incarnations', 'lo', 'lo'),
                 ('incarnations', 'lo', 'lo', 'lo'), ('incarnations', 'hi'), ('journal',),
                 ('journal', 'unsaved', 0), ('journal', 'unsaved', 0, 'chunk'),
                 ('journal', 'last', 0), ('journal', 'last', 0, 'position'),
                 ('journal', 'last', 0, 'source'), ('journal', 'last', 0, 'source', 'position'),
                 ('journal', 'last', 0, 'source', 'binding'), ('journal', 'last', 0, 'chunk')]
    for path in compounds:
        value = at(full.value, path)
        label = '-'.join(map(str, path)) or 'root'
        for index, (name, member) in enumerate(value.payload):
            field = ''.join(chr(c) for c in name)
            add(f'{label}-missing-{field}', changed(full, path, N.Value(10, value.payload[:index] + value.payload[index+1:])))
            add(f'{label}-duplicate-{field}', changed(full, path, N.Value(10, value.payload[:index+1] + ((name, member),) + value.payload[index+1:])))
            add(f'{label}-wrong-type-{field}', changed(full, path + (field,), N.Value(8, N.text('wrong'))))
            add(f'{label}-malformed-name-{field}', changed(full, path, N.Value(10,
                value.payload[:index] + ((N.text(field + '\0'), member),) + value.payload[index+1:])))
        add(label + '-unknown', changed(full, path, N.Value(10, value.payload + ((N.text('unexpected'), integer(0)),))))
        for index in range(len(value.payload) - 1):
            members = list(value.payload)
            members[index], members[index+1] = members[index+1], members[index]
            add(f'{label}-order-{index}', changed(full, path, N.Value(10, tuple(members))))
    for path in [('incarnations', 'kind'), ('incarnations', 'hi', 'kind')]:
        for value in (3, 0xffffffff):
            add('kind-' + '-'.join(path) + '-' + str(value), changed(full, path, integer(value)))

    # Invalid exact tree structure, not a normalized sequence of map inserts.
    add('node-empty-lo', changed(full, ('incarnations', 'lo'), tip()))
    add('node-empty-hi', changed(full, ('incarnations', 'hi'), tip()))
    add('node-wrong-first-difference', changed(full, ('incarnations', 'position'), natural(359)))
    add('node-position-max', changed(full, ('incarnations', 'position'), natural(MAX_NAT)))
    add('node-children-swapped', changed(full, ('incarnations',), node(358, at(full.value, ('incarnations', 'hi')),
                                                                            at(full.value, ('incarnations', 'lo')))))
    add('node-duplicate-leaf', changed(full, ('incarnations', 'lo', 'lo', 'hi'), leaf(KEYS[0], 1)))
    add('node-duplicate-equal-sentinel', changed(full, ('incarnations',), node(825, leaf(KEYS[0], 1), leaf(KEYS[0], 2))))
    add('node-nonincreasing-position', changed(full, ('incarnations', 'lo', 'position'), natural(358)))
    add('node-descendant-wrong-partition', changed(full, ('incarnations', 'lo', 'lo', 'hi'), leaf(KEYS[2], 1)))
    invalid_keys = ('', 'minecraft:unknown/0/0/0', 'minecraft:overworld/0/0',
                    'minecraft:overworld/0/0/0/0', 'minecraft:overworld//0/0',
                    'minecraft:overworld/00/0/0', 'minecraft:overworld/-1/0/0',
                    'minecraft:overworld/+1/0/0', 'minecraft:overworld/4294967296/0/0',
                    'minecraft:overworld/999999999999/0/0', 'minecraft:overworld/0/0/1\0',
                    'minecraft:overworld/١/0/0', 'minecraft:overworld/１/0/0',
                    'minecraft:overworld/\ud800/0/0')
    for index, key in enumerate(invalid_keys):
        add(f'noncanonical-position-key-{index}', root(leaf(key, 1), sequence=0, unsaved=(), latest=()))
    naturals = ('', '00', '01', '+1', '-1', ' 1', '1 ', '1\0', 'a', '١', '１',
                str(MAX_NAT + 1), '18446744073709551616', '9' * 512)
    for path in [('incarnations', 'position'), ('incarnations', 'hi', 'value'),
                 ('journal', 'sequence'), ('journal', 'unsaved', 0, 'sequence'),
                 ('journal', 'last', 0, 'sequence'), ('journal', 'last', 0, 'source', 'incarnation')]:
        for index, raw in enumerate(naturals):
            add('natural-' + '-'.join(map(str, path)) + '-' + str(index), changed(full, path, words(raw)))

    add('zero-sequence-with-receipt', changed(full, ('journal', 'sequence'), natural(0)))
    add('positive-sequence-no-receipt', changed(full, ('journal', 'last'), N.Value(9, (10, ()))))
    add('multiple-latest-receipts', changed(full, ('journal', 'last'), N.Value(9, (10, (receipt(), receipt())))))
    add('receipt-sequence-not-latest', changed(full, ('journal', 'last', 0, 'sequence'), natural(MAX_NAT - 1)))
    add('receipt-position-mismatch', changed(full, ('journal', 'last', 0, 'position', 'y'), integer(0)))
    add('receipt-chunk-mismatch', changed(full, ('journal', 'last', 0, 'chunk', 'x'), integer(0)))
    add('dirty-zero-revision', changed(full, ('journal', 'unsaved', 0, 'sequence'), natural(0)))
    smaller = root(sequence=2, unsaved=(dirty(chunk(), 2),), latest=(receipt(sequence=2),))
    add('dirty-future-revision', changed(smaller, ('journal', 'unsaved', 0, 'sequence'), natural(3)))
    add('dirty-duplicate-chunk', root(unsaved=(dirty(chunk(), 1), dirty(chunk(), MAX_NAT))))
    for path in [('journal', 'unsaved', 0, 'chunk'), ('journal', 'last', 0, 'source', 'position')]:
        add('unknown-dimension-' + '-'.join(map(str, path)), changed(full, path + ('dimension',), words('fixture:unknown')))
    for value in (134217728, 4160749567):
        add('dirty-invalid-chunk-coordinate-' + str(value), changed(full, ('journal', 'unsaved', 0, 'chunk', 'x'), integer(value)))
    for value in (6, 0xffffffff):
        add('invalid-family-' + str(value), changed(full, ('journal', 'last', 0, 'source', 'binding', 'family'), integer(value)))
    for value in (2, 0xffffffff):
        add('noncanonical-lit-' + str(value), changed(full, ('journal', 'last', 0, 'source', 'binding', 'lit'), integer(value)))
    add('cached-state-lit-mismatch', changed(full, ('journal', 'last', 0, 'source', 'binding', 'state'), integer(0x80000000)))
    for path in [('journal', 'unsaved'), ('journal', 'last')]:
        for kind in (0, 3, 11, 13):
            add('wrong-empty-list-element-' + '-'.join(path) + '-' + str(kind), changed(empty, path, N.Value(9, (kind, ()))))

    wire = N.encode_root(full)
    for label, size in [('root-kind', 1), ('name-length', 2), ('root-name', 8),
                        ('inside-body', len(wire)//2), ('terminator', len(wire)-1)]:
        rows.append(('truncated-' + label, wire[:size], False))
    rows.extend([('trailing', wire + b'\0', False), ('invalid-root-kind', bytes((13,)) + wire[1:], False),
                 ('malformed-root-mutf', wire[:3] + b'\xff' + wire[4:], False)])
    for name, tag in [('key', 11), ('unsaved', 9)]:
        frame = bytes((tag,)) + N.mutf_encode(N.text(name))
        offset = wire.index(frame) + len(frame) + (1 if tag == 9 else 0)
        rows.append(('negative-length-' + name, wire[:offset] + b'\xff'*4 + wire[offset+4:], False))
    require(len(rows) == len({name for name, _, _ in rows}), 'Unique corpus labels')
    return rows


def source_pins():
    snapshot = Build.Snapshot()
    base = BEND.resolve().parent.parent / 'bend2/base.bend'
    Build.source_graph(ENTRY, base, os.environ, snapshot)
    for row in list(snapshot.files.values()):
        if row['kind'] in ('bend', 'base'):
            path = Path(row['path'])
            for foreign in Build.foreign_paths(path.read_text()):
                if foreign.endswith('.js'):
                    snapshot.add(path.parent / foreign, 'javascript-effect')
    for path in (Path(__file__), Path(H.__file__), Path(N.__file__), Path(Build.__file__), BEND, Path(sys.executable)):
        snapshot.add(path, 'verification-tool')
    return snapshot.manifest()


def build_child(directory):
    with H.forbid_retries():
        report = Build.ensure_native(ENTRY, directory / 'native', bend=BEND, cache_dir=WORK / 'native-cache')
    require(report['retries'] == 0, 'Publication codec builder retried')
    write(directory / 'build.json', report)


def process_summary(process):
    directory = Path(process['stdout']['path']).parent
    return {key: process[key] for key in ('pid', 'exit_code', 'timed_out', 'error', 'cleanup', 'seconds',
                                         'stdout', 'stderr')} | {
        'argument_count': len(process['argv']), 'attempt': pin(directory / 'attempt.json'),
        'complete_process_receipt': pin(directory / 'result.json')}


def main():
    checks = WORK / 'checks'
    checks.mkdir(parents=True, exist_ok=True)
    number = 1
    while (directory := checks / f'{number:03}').exists():
        number += 1
    directory.mkdir()
    before, processes = source_pins(), []
    write(directory / 'sources.json', before)
    try:
        def run(argv, label, cap=60):
            process = H.bounded(directory, argv, label, cap)
            processes.append(process)
            H.process_ok(process)
            return process
        ordinary = run([BEND, ENTRY, '--check-only'], 'ordinary')
        require('ALL PROOFS CHECK' in Path(ordinary['stdout']['path']).read_text() and
                not Path(ordinary['stderr']['path']).read_bytes(), 'Complete original publication source check')
        run([sys.executable, '-B', Path(__file__), '--build-child', directory], 'native-build', 600)
        binary = pin(directory / 'native')
        native = run([directory / 'native', 'cases'], 'native-guards')
        output = Path(native['stdout']['path']).read_text().splitlines()
        require(output[:-1] == ['ok ' + label for label in GUARDS] and output[-1].startswith('bytes ') and
                not Path(native['stderr']['path']).read_bytes(), 'Native guard protocol')
        actual, expected = H.parse_bytes(output[-1][6:]), N.encode_root(root())
        (directory / 'actual.nbt').write_bytes(actual)
        (directory / 'expected.nbt').write_bytes(expected)
        require(actual == expected and N.parse(actual) == root(), 'Independent complete ordered publication golden bytes')
        cases = []
        for label, wire, accepted in corpus():
            path = directory / (label + '.nbt')
            path.write_bytes(wire)
            cases.append({'name': label, 'input': pin(path), 'accepted': accepted})
        write(directory / 'corpus.json', cases)
        checked = run([directory / 'native', 'decode', *[case['input']['path'] for case in cases]], 'native-physical-corpus')
        output = Path(checked['stdout']['path']).read_text().splitlines()
        require(len(output) == len(cases) and not Path(checked['stderr']['path']).read_bytes(), 'Physical corpus protocol')
        for case, line in zip(cases, output):
            if case['accepted']:
                prefix = 'accepted ' + case['input']['path'] + ' '
                require(line.startswith(prefix), 'Golden accepted fixture refused: ' + case['name'])
                require(H.parse_bytes(line[len(prefix):]) == Path(case['input']['path']).read_bytes(),
                        'Topology or raw identity changed: ' + case['name'])
            else:
                require(line == 'refused ' + case['input']['path'], 'Malformed fixture accepted: ' + case['name'])
        require(before == source_pins() and binary == pin(directory / 'native'), 'Inputs and native artifact unchanged')
        result = {'schema': 1, 'status': 'PASS_NARROW', 'mode': 'native', 'guards': list(GUARDS), 'cases': cases,
                  'physical_roundtrips': sum(case['accepted'] for case in cases), 'refusals': sum(not case['accepted'] for case in cases),
                  'processes': processes, 'codec': pin(CODEC), 'binary': binary, 'build': pin(directory / 'build.json'),
                  'source_manifest': pin(directory / 'sources.json'), 'actual_wire': pin(directory / 'actual.nbt'),
                  'expected_wire': pin(directory / 'expected.nbt'), 'scope': __doc__}
        write(directory / 'result.json', result)
        compact = {key: value for key, value in result.items() if key not in ('cases', 'processes')} | {
            'processes': [process_summary(process) for process in processes],
            'corpus': {'total': len(cases), 'accepted': result['physical_roundtrips'],
                       'refused': result['refusals'], 'manifest': pin(directory / 'corpus.json'),
                       'accepted_names': [case['name'] for case in cases if case['accepted']]},
            'complete_receipt': pin(directory / 'result.json')}
        write(ROOT / f'evidence/local-player-cooking-publication-codec-native-{number:03}.json', compact)
        print(json.dumps({'status': result['status'], 'guards': len(GUARDS), 'cases': len(cases),
                          'physical_roundtrips': result['physical_roundtrips'], 'directory': str(directory)}), flush=True)
    except BaseException as error:
        result = {'status': 'FAIL', 'type': type(error).__name__, 'message': str(error), 'processes': processes,
                  'source_manifest': pin(directory / 'sources.json')}
        write(directory / 'failure.json', result)
        compact = result | {'processes': [process_summary(process) for process in processes],
                            'complete_receipt': pin(directory / 'failure.json')}
        write(ROOT / f'evidence/local-player-cooking-publication-codec-{number:03}-failure.json', compact)
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native', action='store_true', help='Explicit actual native source/codec check (default)')
    parser.add_argument('--build-child', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.build_child:
        build_child(args.build_child)
    else:
        main()
