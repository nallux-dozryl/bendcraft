#!/usr/bin/env python3
"""Independent physical NBT corpus for the complete Bend membership View.

Python constructs test inputs and bounds owned processes. Production encoding,
decoding, structural admission, and affine owner retention execute in Bend.
--prepare writes fixtures only; it never starts Bend, a native build, or Java.
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
ENTRY = ROOT / 'tests/entity_membership_codec.bend'
CODEC = ROOT / 'src/entity_membership_codec.bend'
WORK = ROOT / 'build/entity-membership-codec'
MAX_NAT = (1 << 48) - 1
LARGE_ORDER = (256 << 32) | 7
MASK = (1 << 22) - 1
OPAQUE = (*map(ord, 'fixture:'), 0, 0xa7, 0x1f600, 0xdfff, 0xffffffff)
NORMAL = tuple(map(ord, 'minecraft:overworld'))
K0, K1, K2 = (MASK, (1 << 20) - 1, 0), (0, 0, MASK), (1 << 21, 1 << 19, MASK)
GUARDS = (
    'encode byte budget refuses complete snapshot',
    'encode depth budget refuses complete snapshot',
    'encode element budget refuses complete snapshot',
    'empty five-list View roundtrip',
    'public inspect encode retains complete manager and actual snapshot',
    'invalid registry encode retains complete manager',
    'invalid packed-key encode retains complete manager',
    'duplicate UUID encode retains complete manager',
    'section ID order refusal retains complete manager',
    'empty section refusal retains complete manager',
    'masked chunk duplicate refusal retains complete manager',
    'missing chunk refusal retains complete manager',
    'visibility mismatch refusal retains complete manager',
    'missing tracking refusal retains complete manager',
    'byte-budget encode refusal retains complete manager',
    'depth-budget encode refusal retains complete manager',
    'element-budget encode refusal retains complete manager',
    'complete raw membership View roundtrip',
    'all five independent list orders roundtrip',
    'decode byte budget refuses complete snapshot',
    'decode depth budget refuses complete snapshot',
    'decode element budget refuses complete snapshot',
    'truncated complete snapshot refuses',
    'trailing complete snapshot refuses',
)

compound, integer, array = H.compound, H.integer, H.array
at, changed, pin, write, require = H.at, H.changed, H.pin, H.write, H.require


def dimension(value):
    return array(*map(ord, value)) if isinstance(value, str) else array(*value)


def long(value):
    return N.Value(4, value)


def list_tag(values=()):
    return N.Value(9, (10, tuple(values)))


def uuid(index):
    return array(0x01234567 + index, 0x89abcdef + index,
                 0xfedcba98 - index, 0x76543210 + index)


def box(index):
    return array(0x7ff81234, 0x56789abc + index, 0x80000000, index,
                 0x3ff00000, 1 + index, 0xfff8abcd, 0x10203040 + index,
                 0x7ff00000, index, 0x00100000, 8 + index)


def member(d, identity, key, order, index, uuid_index):
    return compound(dimension=dimension(d), id=integer(identity), key=array(*key),
                    order=long(order), box=box(index), uuid=uuid(uuid_index))


def section(d, key, visibility, *ids):
    return compound(dimension=dimension(d), key=array(*key),
                    visibility=integer(visibility), ids=array(*ids))


def chunk(d, x, z, loaded, visibility):
    return compound(dimension=dimension(d), x=integer(x), z=integer(z),
                    loaded=integer(loaded), visibility=integer(visibility))


def registration(d, identity):
    return compound(dimension=dimension(d), id=integer(identity))


def root(*, members=None, sections=None, chunks=None, tracked=None, ticked=None):
    # This independent ordered tree is not extracted from Bend's serializer.
    members = [member(OPAQUE, 0xffffffff, K0, MAX_NAT, 0, 0),
               member(NORMAL, 0xffffffff, K1, LARGE_ORDER, 1, 0),
               member(OPAQUE, 0x80000000, K2, 0, 2, 1),
               member(OPAQUE, 0x7fffffff, K0, 7, 3, 2),
               member(NORMAL, 0x80000000, K1, LARGE_ORDER, 4, 3)] if members is None else members
    sections = [section(NORMAL, K1, 2, 0x80000000, 0xffffffff),
                section(OPAQUE, K0, 1, 0x7fffffff, 0xffffffff),
                section(OPAQUE, K2, 0, 0x80000000)] if sections is None else sections
    chunks = [chunk('', 0x80000000, 0x7fffffff, 0, 2),
              chunk(OPAQUE, 0xffe00000, 0xffffffff, 1, 0),
              chunk(OPAQUE, 0xffffffff, 0, 0, 1),
              chunk(NORMAL, 0, 0xffffffff, 1, 2)] if chunks is None else chunks
    tracked = [registration(OPAQUE, 0x7fffffff), registration(NORMAL, 0xffffffff),
               registration(OPAQUE, 0xffffffff), registration(NORMAL, 0x80000000)] if tracked is None else tracked
    ticked = [registration(NORMAL, 0x80000000), registration(NORMAL, 0xffffffff)] if ticked is None else ticked
    return N.RootTag(N.text('bendex:entity-membership'), compound(
        format=integer(1), members=list_tag(members), sections=list_tag(sections),
        chunks=list_tag(chunks), tracked=list_tag(tracked), ticked=list_tag(ticked)))


def empty():
    return root(members=[], sections=[], chunks=[], tracked=[], ticked=[])


def list_items(document, key):
    return at(document.value, (key,)).payload[1]


def changed_list(document, key, values):
    return changed(document, (key,), list_tag(values))


def relabel(document, old, new):
    output = document
    for key in ('members', 'sections', 'chunks', 'tracked', 'ticked'):
        for index, entry in enumerate(list_items(document, key)):
            if at(entry, ('dimension',)).payload == old:
                output = changed(output, (key, index, 'dimension'), dimension(new))
    return output


def corpus():
    """Explicit expectations; mutations probe distinct physical/owner failures."""
    full = root()
    rows = []

    def add(name, document, accepted=False):
        rows.append((name, N.encode_root(document), accepted))

    add('full-raw-independent-orders-and-duplicate-numeric-orders', full, True)
    add('empty-all-five-lists', empty(), True)
    unused = [chunk('observation:' + str(loaded) + ':' + str(vis), 0xffffffff,
                    0x80000000, loaded, vis) for loaded in (0, 1) for vis in (0, 1, 2)]
    add('unused-chunks-all-loaded-visibility-combinations',
        root(members=[], sections=[], chunks=unused, tracked=[], ticked=[]), True)
    add('populated-unloaded-ticking-section', changed(full, ('chunks', 3, 'loaded'), integer(0)), True)
    add('positive-masked-chunk-aliases-retain-raw-words',
        changed(changed(full, ('chunks', 2, 'x'), integer(MASK)), ('chunks', 3, 'z'), integer(MASK)), True)
    shuffled = full
    for key in ('sections', 'chunks', 'tracked', 'ticked'):
        shuffled = changed_list(shuffled, key, reversed(list_items(full, key)))
    add('independent-section-chunk-track-tick-permutations', shuffled, True)
    interleaved = list(list_items(full, 'members'))
    interleaved[0], interleaved[1] = interleaved[1], interleaved[0]
    add('cross-section-member-interleave', changed_list(full, 'members', interleaved), True)
    reversed_members = changed_list(full, 'members', reversed(list_items(full, 'members')))
    for index, value in enumerate(list_items(full, 'sections')):
        reversed_members = changed(reversed_members, ('sections', index, 'ids'), array(*reversed(at(value, ('ids',)).payload)))
    add('member-order-reversed-with-matching-section-orders', reversed_members, True)
    add('empty-opaque-dimension', relabel(full, OPAQUE, ()), True)
    add('zero-uuid-words', changed(full, ('members', 0, 'uuid'), array(0, 0, 0, 0)), True)
    add('same-dimension-uuid-differs-only-in-last-word', changed(full, ('members', 3, 'uuid'),
        array(0x01234567, 0x89abcdef, 0xfedcba98, 0x76543211)), True)
    upper_key = (MASK, (1 << 20) - 2, 0)
    shared_column = changed(full, ('members', 3, 'key'), array(*upper_key))
    shared_column = changed(shared_column, ('sections', 1, 'ids'), array(0xffffffff))
    shared_column = changed_list(shared_column, 'sections', list_items(shared_column, 'sections') +
                                 (section(OPAQUE, upper_key, 1, 0x7fffffff),))
    add('distinct-section-heights-share-one-chunk-fact', shared_column, True)
    zero_id = changed(full, ('members', 0, 'id'), integer(0))
    zero_id = changed(zero_id, ('sections', 1, 'ids'), array(0x7fffffff, 0))
    zero_id = changed(zero_id, ('tracked', 2, 'id'), integer(0))
    add('raw-zero-entity-id', zero_id, True)
    for value in (0, 1 << 31, (1 << 32) - 1, 1 << 32, MAX_NAT):
        add('nat48-boundary-' + str(value), changed(full, ('members', 0, 'order'), long(value)), True)
    add('bbox-signed-zeros-infinities-and-distinct-nans', changed(full, ('members', 0, 'box'),
        array(0, 0, 0x80000000, 0, 0x7ff00000, 0,
              0xfff00000, 0, 0x7ff00000, 1, 0xfff81234, 0x89abcdef)), True)
    add('bbox-inverted-finite-endpoints', changed(full, ('members', 0, 'box'),
        array(0x40240000, 0, 0x40340000, 0, 0x403e0000, 0,
              0xc0240000, 0, 0xc0340000, 0, 0xc03e0000, 0)), True)

    add('wrong-root-name', dataclasses.replace(full, name=N.text('wrong')))
    add('wrong-root-type', dataclasses.replace(full, value=integer(1)))
    for value in (0, 2, 0xffffffff):
        add('format-' + str(value), changed(full, ('format',), integer(value)))

    compounds = [(), ('members', 0), ('sections', 0), ('chunks', 0), ('tracked', 0), ('ticked', 0)]
    for path in compounds:
        value = at(full.value, path)
        label = '-'.join(map(str, path)) or 'root'
        for index, (key, child) in enumerate(value.payload):
            name = ''.join(chr(unit) for unit in key)
            add(label + '-missing-' + name, changed(full, path, N.Value(10, value.payload[:index] + value.payload[index + 1:])))
            add(label + '-duplicate-' + name, changed(full, path, N.Value(10, value.payload[:index + 1] + ((key, child),) + value.payload[index + 1:])))
            add(label + '-wrong-type-' + name, changed(full, path + (name,), N.Value(8, N.text('wrong'))))
        add(label + '-unknown-field', changed(full, path, N.Value(10, value.payload + ((N.text('unexpected'), integer(0)),))))
        for index in range(len(value.payload) - 1):
            values = list(value.payload)
            values[index], values[index + 1] = values[index + 1], values[index]
            add(label + '-field-order-' + str(index), changed(full, path, N.Value(10, tuple(values))))

    fixed = [('members', 0, 'key'), ('members', 0, 'box'), ('members', 0, 'uuid'), ('sections', 0, 'key')]
    for path in fixed:
        value = at(full.value, path)
        label = '-'.join(map(str, path))
        for suffix, payload in [('short', value.payload[:-1]), ('long', value.payload + (0,))]:
            add(label + '-' + suffix, changed(full, path, array(*payload)))
        for suffix, replacement in [('long-array', N.Value(12, value.payload)),
                                    ('byte-array', N.Value(7, bytes(word & 255 for word in value.payload))),
                                    ('int-list', N.Value(9, (3, tuple(integer(word) for word in value.payload))))]:
            add(label + '-' + suffix, changed(full, path, replacement))
    for path in [('members', 0, 'dimension'), ('sections', 0, 'ids'), ('chunks', 0, 'dimension'), ('tracked', 0, 'dimension')]:
        value = at(full.value, path)
        add('-'.join(map(str, path)) + '-long-array', changed(full, path, N.Value(12, value.payload)))
    for key in ('members', 'sections', 'chunks', 'tracked', 'ticked'):
        for kind in (0, 3, 11, 13):
            add(key + '-empty-list-element-' + str(kind), changed(empty(), (key,), N.Value(9, (kind, ()))))
        add(key + '-nonempty-int-list', changed(full, (key,), N.Value(9, (3, (integer(0),)))))
    for path in [('format',), ('members', 0, 'id'), ('sections', 0, 'visibility'), ('chunks', 0, 'loaded'),
                 ('chunks', 0, 'x'), ('chunks', 0, 'z'), ('tracked', 0, 'id'), ('ticked', 0, 'id')]:
        value = at(full.value, path).payload
        for kind in (1, 2, 4):
            payload = value & ({1: 255, 2: 65535, 4: (1 << 64) - 1}[kind])
            add('-'.join(map(str, path)) + '-numeric-tag-' + str(kind), changed(full, path, N.Value(kind, payload)))
    for path in [('sections', 0, 'visibility'), ('chunks', 0, 'visibility')]:
        for value in (3, 0xffffffff):
            add('-'.join(map(str, path)) + '-visibility-' + str(value), changed(full, path, integer(value)))
    for value in (2, 0xffffffff):
        add('chunk-loaded-' + str(value), changed(full, ('chunks', 0, 'loaded'), integer(value)))
    for path in [('members', 0, 'key'), ('sections', 0, 'key')]:
        for index, bad in enumerate((1 << 22, 1 << 20, 1 << 22)):
            payload = list(at(full.value, path).payload)
            payload[index] = bad
            add('-'.join(map(str, path)) + '-axis-overflow-' + str(index), changed(full, path, array(*payload)))
    for value in (1 << 48, (1 << 63) - 1, 1 << 63, (1 << 64) - 1):
        add('order-outside-nat48-' + str(value), changed(full, ('members', 0, 'order'), long(value)))
    for replacement in (integer(0), array(0, 0), N.Value(12, (0,)), N.Value(8, N.text('0'))):
        add('order-wrong-type-' + str(replacement.kind), changed(full, ('members', 0, 'order'), replacement))

    members = list_items(full, 'members')
    sections = list_items(full, 'sections')
    chunks = list_items(full, 'chunks')
    tracked = list_items(full, 'tracked')
    ticked = list_items(full, 'ticked')
    add('duplicate-member-identity', changed_list(full, 'members', members + (members[0],)))
    add('same-dimension-member-id-collision', changed(full, ('members', 3, 'id'), integer(0xffffffff)))
    add('same-dimension-member-uuid-collision', changed(full, ('members', 3, 'uuid'), uuid(0)))
    add('unlinked-member', changed_list(full, 'members', members + (member(OPAQUE, 123, K0, 2, 6, 9),)))
    add('member-wrong-dimension', changed(full, ('members', 0, 'dimension'), dimension('wrong')))
    add('member-wrong-section-key', changed(full, ('members', 0, 'key'), array(1, 2, 3)))
    add('missing-member-with-retained-section-id', changed_list(full, 'members', members[1:]))
    add('duplicate-section', changed_list(full, 'sections', sections + (sections[0],)))
    add('missing-section', changed_list(full, 'sections', sections[:1] + sections[2:]))
    add('section-wrong-dimension', changed(full, ('sections', 1, 'dimension'), dimension('wrong')))
    add('empty-section-ids', changed(full, ('sections', 1, 'ids'), array()))
    add('duplicate-section-id', changed(full, ('sections', 1, 'ids'), array(0x7fffffff, 0xffffffff, 0xffffffff)))
    add('dangling-section-id', changed(full, ('sections', 1, 'ids'), array(0x7fffffff, 123)))
    add('member-listed-in-wrong-section', changed(full, ('sections', 1, 'ids'), array(0x7fffffff, 0x80000000)))
    add('section-id-order-only', changed(full, ('sections', 1, 'ids'), array(0xffffffff, 0x7fffffff)))
    add('empty-extra-section', changed_list(full, 'sections', sections + (section(OPAQUE, (2, 3, 4), 0),)))
    add('duplicate-raw-chunk', changed_list(full, 'chunks', chunks + (chunks[2],)))
    add('duplicate-masked-x-chunk', changed_list(full, 'chunks', chunks + (chunk(OPAQUE, MASK, 0, 0, 1),)))
    add('duplicate-masked-z-chunk', changed_list(full, 'chunks', chunks + (chunk(NORMAL, 0, MASK, 1, 2),)))
    add('missing-referenced-chunk', changed_list(full, 'chunks', chunks[:2] + chunks[3:]))
    add('chunk-wrong-dimension', changed(full, ('chunks', 2, 'dimension'), dimension('wrong')))
    add('chunk-section-visibility-mismatch', changed(full, ('chunks', 2, 'visibility'), integer(0)))
    add('section-chunk-visibility-mismatch', changed(full, ('sections', 1, 'visibility'), integer(2)))
    for key, values in [('tracked', tracked), ('ticked', ticked)]:
        add(key + '-missing-required', changed_list(full, key, values[1:]))
        add(key + '-duplicate-registration', changed_list(full, key, values + (values[0],)))
        add(key + '-unknown-registration', changed_list(full, key, values + (registration(OPAQUE, 123),)))
        add(key + '-hidden-registration', changed_list(full, key, values + (registration(OPAQUE, 0x80000000),)))
        add(key + '-wrong-dimension', changed(full, (key, 0, 'dimension'), dimension('wrong')))
    add('tracked-only-member-scheduled', changed_list(full, 'ticked', ticked + (registration(OPAQUE, 0xffffffff),)))
    add('hidden-section-enters-tracking-without-registry',
        changed(changed(full, ('sections', 2, 'visibility'), integer(1)), ('chunks', 1, 'visibility'), integer(1)))
    add('ticking-section-loses-ticking-with-stale-registry',
        changed(changed(full, ('sections', 0, 'visibility'), integer(1)), ('chunks', 3, 'visibility'), integer(1)))

    wire = N.encode_root(full)
    for name, size in [('root-kind', 1), ('root-name-length', 2), ('root-name', 9),
                       ('inside-payload', len(wire) // 2), ('final-terminator', len(wire) - 1)]:
        rows.append(('truncated-' + name, wire[:size], False))
    rows.append(('trailing-byte', wire + b'\0', False))
    rows.append(('malformed-root-mutf', wire[:3] + b'\xff' + wire[4:], False))
    rows.append(('invalid-root-tag', bytes((13,)) + wire[1:], False))
    for name, tag in [('members', 9), ('sections', 9), ('tracked', 9), ('key', 11), ('box', 11), ('uuid', 11)]:
        frame = bytes((tag,)) + N.mutf_encode(N.text(name))
        offset = wire.index(frame) + len(frame) + (1 if tag == 9 else 0)
        for suffix, raw in [('negative', b'\xff' * 4), ('oversized', b'\x7f\xff\xff\xff')]:
            rows.append((suffix + '-count-' + name, wire[:offset] + raw + wire[offset + 4:], False))
    for name, tag, length in [('order', 4, 8), ('box', 11, 52), ('uuid', 11, 20)]:
        frame = bytes((tag,)) + N.mutf_encode(N.text(name))
        start = wire.index(frame) + len(frame)
        rows.append(('truncated-payload-' + name, wire[:start + length - 1], False))
    require(len({name for name, _, _ in rows}) == len(rows), 'Duplicate membership corpus label')
    return rows


def new_directory():
    base = WORK / 'checks'
    base.mkdir(parents=True, exist_ok=True)
    number = 1
    while (directory := base / f'{number:03}').exists():
        number += 1
    directory.mkdir()
    return number, directory


def write_corpus(directory):
    cases = []
    for name, wire, accepted in corpus():
        if accepted:
            require(N.encode_root(N.parse(wire)) == wire, 'Independent accepted fixture is not canonical physical NBT: ' + name)
        path = directory / (name + '.nbt')
        path.write_bytes(wire)
        cases.append({'name': name, 'input': pin(path), 'accepted': accepted})
    expected = directory / 'expected.nbt'
    expected.write_bytes(N.encode_root(root()))
    write(directory / 'corpus.json', {'schema': 1, 'cases': cases, 'expected_wire': pin(expected)})
    return cases


def source_pins():
    snapshot = Build.Snapshot()
    base = BEND.resolve().parent.parent / 'bend2/base.bend'
    Build.source_graph(ENTRY, base, os.environ, snapshot)
    for row in list(snapshot.files.values()):
        if row['kind'] in ('bend', 'base'):
            source = Path(row['path'])
            for foreign in Build.foreign_paths(source.read_text()):
                if foreign.endswith('.js'):
                    snapshot.add(source.parent / foreign, 'javascript-effect')
    for path in (Path(__file__), Path(H.__file__), Path(N.__file__), Path(Build.__file__), BEND, Path(sys.executable)):
        snapshot.add(path, 'verification-tool')
    return snapshot.manifest()


def build_child(directory):
    with H.forbid_retries():
        report = Build.ensure_native(ENTRY, directory / 'native', bend=BEND,
                                     cache_dir=WORK / 'native-cache')
    require(report['retries'] == 0, 'Membership codec native builder retried')
    write(directory / 'build.json', report)


def prepare():
    number, directory = new_directory()
    cases = write_corpus(directory)
    result = {'schema': 1, 'status': 'PREPARED', 'cases': cases,
              'expected_wire': pin(directory / 'expected.nbt'), 'entry': pin(ENTRY),
              'harness': pin(Path(__file__)),
              'scope': 'File-only independent physical corpus. No Bend/source check, native emit/build, native execution, or Java was started.'}
    write(directory / 'prepared.json', result)
    print(json.dumps({'status': result['status'], 'accepted': sum(case['accepted'] for case in cases),
                      'refused': sum(not case['accepted'] for case in cases), 'directory': str(directory)}), flush=True)


def main():
    number, directory = new_directory()
    before = source_pins()
    write(directory / 'sources.json', before)
    processes = []
    try:
        def run(argv, label, cap=30):
            result = H.bounded(directory, argv, label, cap)
            processes.append(result)
            H.process_ok(result)
            return result

        ordinary = run([BEND, ENTRY, '--check-only'], 'ordinary', 60)
        require('ALL PROOFS CHECK' in Path(ordinary['stdout']['path']).read_text() and
                not Path(ordinary['stderr']['path']).read_bytes(), 'Original complete membership source check failed')
        run([sys.executable, Path(__file__), '--build-child', directory], 'native-build', 600)
        binary = pin(directory / 'native')
        observed = run([directory / 'native', 'cases'], 'actual-native', 60)
        lines = Path(observed['stdout']['path']).read_text().splitlines()
        require(len(lines) == len(GUARDS) + 1 and lines[:-1] == ['ok ' + label for label in GUARDS] and
                lines[-1].startswith('bytes ') and not Path(observed['stderr']['path']).read_bytes(),
                'Membership owner guards or harness protocol differ')
        actual = H.parse_bytes(lines[-1][6:])
        expected = N.encode_root(root())
        (directory / 'actual.nbt').write_bytes(actual)
        (directory / 'expected.nbt').write_bytes(expected)
        require(actual == expected and N.parse(actual) == root(),
                'Complete membership snapshot differs from independent ordered physical NBT')
        cases = write_corpus(directory)
        checked = run([directory / 'native', 'decode', *[case['input']['path'] for case in cases]],
                      'physical-corpus-native', 60)
        outputs = Path(checked['stdout']['path']).read_text().splitlines()
        require(len(outputs) == len(cases) and not Path(checked['stderr']['path']).read_bytes(),
                'Membership corpus output count or diagnostics differ')
        roundtrips = 0
        for case, line in zip(cases, outputs):
            if case['accepted']:
                prefix = 'accepted ' + case['input']['path'] + ' '
                require(line.startswith(prefix), 'Valid membership fixture refused: ' + case['name'])
                wire = H.parse_bytes(line[len(prefix):])
                original = Path(case['input']['path']).read_bytes()
                require(wire == original and N.parse(wire) == N.parse(original),
                        'Accepted membership fixture did not roundtrip exactly: ' + case['name'])
                roundtrips += 1
            else:
                require(line == 'refused ' + case['input']['path'],
                        'Invalid membership fixture accepted: ' + case['name'])
        require(before == source_pins(), 'Membership inputs changed during execution')
        require(binary == pin(directory / 'native'), 'Membership binary changed during execution')
        result = {'schema': 1, 'status': 'PASS', 'mode': 'native', 'guards': list(GUARDS),
                  'cases': cases, 'processes': processes, 'physical_roundtrips': roundtrips,
                  'actual_wire': pin(directory / 'actual.nbt'), 'expected_wire': pin(directory / 'expected.nbt'),
                  'source_manifest': pin(directory / 'sources.json'), 'codec': pin(CODEC),
                  'binary': binary, 'build': pin(directory / 'build.json'),
                  'scope': 'Actual native Bend codec for the complete ordered membership View and inspect-return M.State. Independent physical bytes include raw F64/UUID/U32/charwords, Nat48, independent registry orders, dimension-scoped identities, masked chunk aliases, strict schema/cardinality/links, and budget/structural owner refusal. Durable IO and actual loader-authorized installation remain consumer obligations.'}
        write(directory / 'result.json', result)
        write(ROOT / f'evidence/entity-membership-codec-{number:03}.json', result)
        print(json.dumps({'status': 'PASS', 'guards': len(GUARDS), 'physical_cases': len(cases),
                          'physical_roundtrips': roundtrips, 'directory': str(directory)}), flush=True)
    except BaseException as error:
        result = {'schema': 1, 'status': 'FAIL', 'type': type(error).__name__, 'message': str(error),
                  'processes': processes, 'source_manifest': pin(directory / 'sources.json')}
        write(directory / 'failure.json', result)
        write(ROOT / f'evidence/entity-membership-codec-{number:03}-failure.json', result)
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native', action='store_true', help='Run the native acceptance lane (default)')
    parser.add_argument('--prepare', action='store_true', help='Write the independent corpus without starting any compiler/build/execution')
    parser.add_argument('--build-child', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.build_child:
        build_child(args.build_child)
    elif args.prepare:
        prepare()
    else:
        main()
