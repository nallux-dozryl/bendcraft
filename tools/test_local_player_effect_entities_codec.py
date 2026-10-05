#!/usr/bin/env python3
"""Compare actual Bend entity storage to independent, ordered physical NBT.

Python constructs fixtures and owns bounded test processes only. Entity state,
serialization, parsing, and refusal remain the actual production Bend graph.
Native preserves raw F32 NaN payloads; --js records measured representation gaps.
"""
from __future__ import annotations

import argparse
import contextlib
import dataclasses
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

import build_native as Build
import test_nbt as N

ROOT = Path(__file__).resolve().parents[1]
ENTRY = ROOT / 'tests/local_player_effect_entities_codec.bend'
CODEC = ROOT / 'src/local_player_effect_entities_codec.bend'
BEND = Path('/Users/chuah/.bend/bin/bend')
NAN = 0x7fc01211
MAX_NAT = 281474976710655
LARGE_ORDER = 1099511627783
COMPONENTS = 'BendCraftComponents1\t64\t{"text":"§😀"}\0\ud800'
DIMENSIONS = ('minecraft:the_nether', 'fixture:\0§😀\udfff', 'minecraft:overworld')
GUARDS = (
    'encode byte budget refuses complete snapshot',
    'encode depth budget refuses complete snapshot',
    'encode element budget refuses complete snapshot',
    'empty records retain actual RNG and owner cursors',
    'complete raw state and duplicate ordered records roundtrip',
    'one affine install and inspect retain complete snapshot',
    'decode byte budget refuses complete snapshot',
    'decode depth budget refuses complete snapshot',
    'decode element budget refuses complete snapshot',
    'truncated complete snapshot refuses',
    'trailing complete snapshot refuses',
)


def compound(**members):
    return N.Value(10, tuple((N.text(k), v) for k, v in members.items()))


def integer(value):
    return N.Value(3, value)


def array(*values):
    return N.Value(11, tuple(values))


def string_words(value):
    # Bend String is charwords; these are deliberately not UTF-16 NBT strings.
    return array(*map(ord, value))


def random_source(kind, *words):
    return compound(kind=integer(kind), words=array(*words))


def fields(index=0, nan=NAN):
    """Distinct raw words in every selected field; index offsets finite payloads."""
    return compound(
        position=array(0x7ff81234, 0x56789abc + index, 0x80000000, index,
                       0x3ff00000, 0x00000001 + index),
        velocity=array(0xbff00000, 0x00000002 + index, 0x00000000, 0x00000003 + index,
                       0x7ff00000, index),
        position_o=array(0x40000000, 0x00000004 + index, 0xfff8abcd, 0x10203040 + index,
                         0x40080000, 0x00000005 + index),
        position_old=array(0x40100000, 0x00000006 + index, 0xc0140000, 0x00000007 + index,
                           0x00100000, 0x00000008 + index),
        look=array(nan, 0x80000000, 0x3f123456 + index, 0xbf654321 + index),
        head_yaw=integer(0x7fc12345), body_yaw=integer(0x80000000),
        fall_distance=array(0x7ff85678, 0x9abcdef0 + index),
        on_ground=integer(index % 2), air=integer(0x80000001 + index),
        fire=integer(0xfffffffe - index), portal_cooldown=integer(0x7fffffff - index),
        invulnerable=integer(1), needs_sync=integer(index % 2))


def common(index=0, nan=NAN):
    sources = (random_source(0, 0xaaaaaaaa, 0x55555555),
               random_source(1, 0x11121314, 0x15161718, 0x21222324, 0x25262728),
               random_source(0, 0xffffffff, 0x80000000))
    return compound(
        dimension=string_words(DIMENSIONS[index]), id=integer((0xffffffff, 0x80000000, 0x7fffffff)[index]),
        uuid_most=array(0x01234567 + index, 0x89abcdef + index),
        uuid_least=array(0xfedcba98 - index, 0x76543210 + index),
        random=sources[index], fields=fields(index, nan), tick_count=integer(0x80000005 + index),
        first_tick=integer(index != 1), removed=integer(index == 2), accessible=integer(index != 2),
        section_order=string_words(str((MAX_NAT, LARGE_ORDER, 0)[index])))


def fixture(nan=NAN):
    item = compound(kind=integer(0), common=common(0, nan), payload=compound(
        item=compound(id=string_words('minecraft:stone'), components=string_words(COMPONENTS), count=integer(0xffffffff)),
        age=integer(0x80000001), pickup_delay=integer(0xfffffffd), health=integer(0x7fffffff),
        thrower=array(0xa1a2a3a4, 0xa5a6a7a8, 0xb1b2b3b4, 0xb5b6b7b8), target=array(), bob=integer(nan)))
    orb = compound(kind=integer(1), common=common(1, nan), payload=compound(
        value=integer(0xffffffff), age=integer(0x80000002), health=integer(0x7ffffffe), count=integer(0),
        following=array(0xc1c2c3c4, 0xc5c6c7c8, 0xd1d2d3d4, 0xd5d6d7d8)))
    empty_item = compound(kind=integer(0), common=common(2, nan), payload=compound(
        item=compound(), age=integer(0), pickup_delay=integer(0x7fffffff), health=integer(0xffffffff),
        thrower=array(), target=array(0xe1e2e3e4, 0xe5e6e7e8, 0xf1f2f3f4, 0xf5f6f7f8), bob=integer(0x80000000)))
    untracked_orb = compound(kind=integer(1), common=common(2, nan), payload=compound(
        value=integer(0), age=integer(0xffffffff), health=integer(0), count=integer(0x80000000), following=array()))
    return [item, orb, item, empty_item, untracked_orb, orb]


def root(records=None, *, nan=NAN):
    return N.RootTag(N.text('bendex:cooking-effect-entities'), compound(
        format=integer(1), level_random=random_source(1, 0x01020304, 0x05060708, 0x090a0b0c, 0x0d0e0f10),
        seed_uniquifier=array(0xfedcba98, 0x76543210), last_id=integer(0xffffffff),
        next_section_order=string_words(str(MAX_NAT)),
        records=N.Value(9, (10, tuple(fixture(nan) if records is None else records)))))


def at(value, path):
    for part in path:
        if isinstance(part, int):
            value = value.payload[1][part]
        else:
            value = next(v for k, v in value.payload if k == N.text(part))
    return value


def replace_at(value, path, replacement):
    if not path:
        return replacement
    head, *tail = path
    if isinstance(head, int):
        element, items = value.payload
        return N.Value(9, (element, tuple(replace_at(v, tail, replacement) if i == head else v for i, v in enumerate(items))))
    return N.Value(10, tuple((key, replace_at(v, tail, replacement) if key == N.text(head) else v) for key, v in value.payload))


def changed(document, path, replacement):
    return dataclasses.replace(document, value=replace_at(document.value, path, replacement))


def corpus():
    """One independent golden tree; each schema mutation changes one property."""
    full = root()
    rows = [('full-raw', N.encode_root(full), True), ('empty', N.encode_root(root([])), True)]
    zero_xoro = changed(full, ('level_random',), random_source(1, 0, 0, 0, 0))
    zero_xoro = changed(zero_xoro, ('records', 1, 'common', 'random'), random_source(1, 0, 0, 0, 0))
    raw_legacy = changed(full, ('level_random',), random_source(0, 0xffffffff, 0x80000000))
    raw_legacy = changed(raw_legacy, ('records', 0, 'common', 'random'), random_source(0, 0xfedcba98, 0x76543210))
    rows.extend([('zero-xoroshiro-state', N.encode_root(zero_xoro), True),
                 ('legacy-arbitrary-highwords', N.encode_root(raw_legacy), True)])

    def add(name, document):
        rows.append((name, N.encode_root(document), False))

    add('wrong-root-name', dataclasses.replace(full, name=N.text('wrong')))
    add('wrong-root-type', dataclasses.replace(full, value=integer(1)))
    for number in (0, 2, 0xffffffff):
        add(f'format-{number}', changed(full, ('format',), integer(number)))
    for path in [('level_random', 'kind'), ('records', 0, 'kind'), ('records', 1, 'kind'),
                 ('records', 0, 'common', 'random', 'kind'), ('records', 1, 'common', 'random', 'kind')]:
        for number in (2, 0xffffffff):
            add('discriminant-' + '-'.join(map(str, path)) + '-' + str(number), changed(full, path, integer(number)))

    compounds = [(), ('level_random',), ('records', 0), ('records', 0, 'common'),
                 ('records', 0, 'common', 'random'), ('records', 1, 'common', 'random'),
                 ('records', 0, 'common', 'fields'), ('records', 0, 'payload'),
                 ('records', 1, 'payload'), ('records', 0, 'payload', 'item')]
    for path in compounds:
        value = at(full.value, path)
        label = '-'.join(map(str, path)) or 'root'
        for index, (name, member) in enumerate(value.payload):
            field = ''.join(chr(c) for c in name)
            add(f'{label}-missing-{field}', changed(full, path, N.Value(10, value.payload[:index] + value.payload[index + 1:])))
            add(f'{label}-duplicate-{field}', changed(full, path, N.Value(10, value.payload[:index + 1] + ((name, member),) + value.payload[index + 1:])))
            add(f'{label}-wrong-type-{field}', changed(full, path + (field,), N.Value(8, N.text('wrong'))))
        add(label + '-unknown', changed(full, path, N.Value(10, value.payload + ((N.text('unexpected'), integer(0)),))))
        for index in range(len(value.payload) - 1):
            members = list(value.payload)
            members[index], members[index + 1] = members[index + 1], members[index]
            add(f'{label}-order-{index}', changed(full, path, N.Value(10, tuple(members))))

    fixed_arrays = [('level_random', 'words'), ('seed_uniquifier',), ('records', 0, 'common', 'uuid_most'),
                    ('records', 0, 'common', 'uuid_least'), ('records', 0, 'common', 'random', 'words'),
                    ('records', 1, 'common', 'random', 'words')]
    fixed_arrays += [('records', 0, 'common', 'fields', key) for key in
                     ('position', 'velocity', 'position_o', 'position_old', 'look', 'fall_distance')]
    for path in fixed_arrays:
        value = at(full.value, path)
        label = '-'.join(map(str, path))
        for suffix, payload in [('short', value.payload[:-1]), ('long', value.payload + (0,))]:
            add(label + '-' + suffix, changed(full, path, N.Value(11, payload)))
        for suffix, replacement in [('long-array', N.Value(12, value.payload)),
                                    ('byte-array', N.Value(7, bytes(v & 255 for v in value.payload))),
                                    ('int-list', N.Value(9, (3, tuple(integer(v) for v in value.payload))))]:
            add(label + '-' + suffix, changed(full, path, replacement))
    add('legacy-words-xoroshiro-count', changed(full, ('records', 0, 'common', 'random', 'words'), array(1, 2, 3, 4)))
    add('xoroshiro-words-legacy-count', changed(full, ('records', 1, 'common', 'random', 'words'), array(1, 2)))

    booleans = [('records', 0, 'common', key) for key in ('first_tick', 'removed', 'accessible')]
    booleans += [('records', 0, 'common', 'fields', key) for key in ('on_ground', 'invulnerable', 'needs_sync')]
    for path in booleans:
        label = '-'.join(map(str, path))
        for number in (2, 0xffffffff):
            add(label + '-' + str(number), changed(full, path, integer(number)))
        for number in (0, 1):
            add(label + '-byte-' + str(number), changed(full, path, N.Value(1, number)))

    for path in [('records', 0, 'payload', 'thrower'), ('records', 0, 'payload', 'target'),
                 ('records', 1, 'payload', 'following')]:
        label = '-'.join(map(str, path))
        for size in (1, 2, 3, 5):
            add(label + '-length-' + str(size), changed(full, path, array(*range(size))))
    bad_naturals = ('', '00', '01', '+1', '-1', ' 1', '1 ', '1\0', 'a', '١', '１',
                    str(MAX_NAT + 1), '18446744073709551616', '9' * 512)
    for path in [('next_section_order',), ('records', 0, 'common', 'section_order')]:
        label = '-'.join(map(str, path))
        for index, raw in enumerate(bad_naturals):
            add(label + '-noncanonical-' + str(index), changed(full, path, string_words(raw)))

    add('item-with-orb-payload', changed(full, ('records', 0, 'payload'), at(full.value, ('records', 1, 'payload'))))
    add('orb-with-item-payload', changed(full, ('records', 1, 'payload'), at(full.value, ('records', 0, 'payload'))))
    for kind in (0, 3, 11, 13):
        add(f'empty-list-element-{kind}', changed(root([]), ('records',), N.Value(9, (kind, ()))))
    add('look-float-type', changed(full, ('records', 0, 'common', 'fields', 'look'), N.Value(5, NAN)))
    add('fall-distance-double-type', changed(full, ('records', 0, 'common', 'fields', 'fall_distance'), N.Value(6, 0x7ff856789abcdef0)))
    add('bob-float-type', changed(full, ('records', 0, 'payload', 'bob'), N.Value(5, NAN)))
    add('empty-item-has-member', changed(full, ('records', 3, 'payload', 'item'), compound(count=integer(0))))

    wire = rows[0][1]
    for name, size in [('root-kind', 1), ('root-name-length', 2), ('root-name', 9),
                       ('inside-payload', len(wire) // 2), ('final-terminator', len(wire) - 1)]:
        rows.append(('truncated-' + name, wire[:size], False))
    rows.append(('trailing', wire + b'\0', False))
    rows.append(('malformed-root-mutf', wire[:3] + b'\xff' + wire[4:], False))
    rows.append(('invalid-root-tag', bytes((13,)) + wire[1:], False))
    # Locate tag/name frames independently; signed length mutations stay physical.
    for name, tag in [('seed_uniquifier', 11), ('records', 9)]:
        frame = bytes((tag,)) + N.mutf_encode(N.text(name))
        offset = wire.index(frame) + len(frame) + (1 if tag == 9 else 0)
        rows.append(('negative-count-' + name, wire[:offset] + b'\xff' * 4 + wire[offset + 4:], False))
    assert len({name for name, _, _ in rows}) == len(rows)
    return rows


def js_canonicalized(document):
    """Expected observed JS boundary, restricted to actual F32 field locations."""
    def canonical_nan(word):
        return 0x7fc00000 if word & 0x7f800000 == 0x7f800000 and word & 0x007fffff else word

    output = document
    records = at(document.value, ('records',)).payload[1]
    for index, record in enumerate(records):
        base = ('records', index, 'common', 'fields')
        look = at(document.value, base + ('look',))
        output = changed(output, base + ('look',), array(*map(canonical_nan, look.payload)))
        for key in ('head_yaw', 'body_yaw'):
            word = at(document.value, base + (key,)).payload
            output = changed(output, base + (key,), integer(canonical_nan(word)))
        if at(record, ('kind',)).payload == 0:
            path = ('records', index, 'payload', 'bob')
            output = changed(output, path, integer(canonical_nan(at(document.value, path).payload)))
    return output


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def pin(path):
    path = Path(path).resolve(strict=True)
    data = path.read_bytes()
    return {'path': str(path), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


def write(path, value):
    with Path(path).open('x', encoding='utf-8') as stream:
        json.dump(value, stream, ensure_ascii=True, sort_keys=True, indent=2)
        stream.write('\n')


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
    for path in (Path(__file__), Path(N.__file__), Path(Build.__file__), BEND, Path(sys.executable)):
        snapshot.add(path, 'verification-tool')
    return snapshot.manifest()


def group_members(group):
    result = subprocess.run(['/bin/ps', '-axo', 'pid=,pgid=,stat=,args='], capture_output=True, text=True, check=True)
    return [{'pid': int(parts[0]), 'group': int(parts[1]), 'state': parts[2], 'argv': parts[3]}
            for line in result.stdout.splitlines() if len(parts := line.strip().split(None, 3)) == 4 and int(parts[1]) == group]


def live_members(group):
    return [row for row in group_members(group) if not row['state'].startswith('Z')]


def cleanup(process):
    before = group_members(process.pid)
    errors = []
    for sig, cap in [(signal.SIGTERM, .5), (signal.SIGKILL, 2)]:
        if process.poll() is not None and not live_members(process.pid):
            break
        try:
            os.killpg(process.pid, sig)
        except ProcessLookupError:
            pass
        except OSError as error:
            errors.append({'signal': int(sig), 'error': str(error)})
        try:
            process.wait(timeout=cap)
        except subprocess.TimeoutExpired:
            pass
        deadline = time.monotonic() + cap
        while live_members(process.pid) and time.monotonic() < deadline:
            time.sleep(.02)
    after = group_members(process.pid)
    return {'before': before, 'after': after, 'errors': errors, 'leader_reaped': process.poll() is not None,
            'live_group_absent': not any(not row['state'].startswith('Z') for row in after)}


def bounded(directory, argv, label, cap=30):
    """Single attempt, complete captured streams, unconditional process cleanup."""
    work = directory / label
    work.mkdir()
    argv = list(map(str, argv))
    started = time.monotonic()
    attempt = {'argv': argv, 'cwd': str(ROOT), 'cap_seconds': cap, 'attempts': 1}
    write(work / 'attempt.json', attempt)
    process = None
    error = None
    timed_out = False
    cleaned = None
    with (work / 'stdout').open('xb') as stdout, (work / 'stderr').open('xb') as stderr:
        try:
            process = subprocess.Popen(argv, cwd=ROOT, stdout=stdout, stderr=stderr, start_new_session=True)
            print(json.dumps({'phase': label, 'pid': process.pid, 'process_group': process.pid, 'cap_seconds': cap}), flush=True)
            try:
                process.wait(timeout=cap)
            except subprocess.TimeoutExpired:
                timed_out = True
        except BaseException as cause:
            error = {'type': type(cause).__name__, 'message': str(cause)}
        finally:
            if process is not None:
                try:
                    cleaned = cleanup(process)
                except BaseException as cause:
                    cleaned = {'error': str(cause), 'leader_reaped': process.poll() is not None, 'live_group_absent': False}
    result = dict(attempt, pid=process.pid if process else None, exit_code=process.returncode if process else None,
                  timed_out=timed_out, error=error, cleanup=cleaned, seconds=time.monotonic() - started,
                  stdout=pin(work / 'stdout'), stderr=pin(work / 'stderr'))
    write(work / 'result.json', result)
    return result


def process_ok(result):
    require(not result['timed_out'] and result['error'] is None and result['exit_code'] == 0 and
            result['cleanup']['leader_reaped'] and result['cleanup']['live_group_absent'] and
            not result['cleanup'].get('errors') and not result['cleanup'].get('error'), 'Bounded owned process failed: ' + str(result))


class UnretriedInputDrift(RuntimeError):
    pass


@contextlib.contextmanager
def forbid_retries():
    original = Build.InputsChanged
    class RefusedInputsChanged(original):
        def __new__(cls, *args, **kwargs):
            raise UnretriedInputDrift(*args)
    Build.InputsChanged = RefusedInputsChanged
    try:
        yield
    finally:
        Build.InputsChanged = original


def build_child(directory):
    with forbid_retries():
        report = Build.ensure_native(ENTRY, directory / 'native', bend=BEND,
                                     cache_dir=ROOT / 'build/local-player-effect-entities-codec/native-cache')
    require(report['retries'] == 0, 'Entity codec native builder retried')
    write(directory / 'build.json', report)


def parse_bytes(raw):
    values = [int(value) for value in raw.split(',')]
    require(all(0 <= value <= 255 for value in values), 'Harness emitted an invalid byte')
    return bytes(values)


def main(native=True):
    work = ROOT / 'build/local-player-effect-entities-codec/checks'
    work.mkdir(parents=True, exist_ok=True)
    number = 1
    while (directory := work / f'{number:03}').exists():
        number += 1
    directory.mkdir()
    before = source_pins()
    write(directory / 'sources.json', before)
    processes = []
    try:
        def run(argv, label, cap=30):
            result = bounded(directory, argv, label, cap)
            processes.append(result)
            process_ok(result)
            return result

        binary = None
        ordinary = run([BEND, ENTRY, '--check-only'], 'ordinary', 60)
        require('ALL PROOFS CHECK' in Path(ordinary['stdout']['path']).read_text() and
                not Path(ordinary['stderr']['path']).read_bytes(), 'Original complete entity codec source check failed')
        if native:
            run([sys.executable, Path(__file__), '--build-child', directory], 'native-build', 600)
            binary = pin(directory / 'native')
            invoke = [directory / 'native']
        else:
            invoke = [BEND, ENTRY, '--']
        if native:
            observed = run([*invoke, 'cases', str(NAN)], 'actual-native', 60)
        else:
            observed = bounded(directory, [*invoke, 'cases', str(NAN)], 'actual-js', 60)
            processes.append(observed)
            if observed['exit_code'] != 0:
                require(observed['exit_code'] == 1 and not observed['timed_out'] and observed['error'] is None and
                        observed['cleanup']['leader_reaped'] and observed['cleanup']['live_group_absent'] and
                        not observed['cleanup'].get('errors') and not observed['cleanup'].get('error') and
                        not Path(observed['stdout']['path']).read_bytes() and
                        Path(observed['stderr']['path']).read_text() == 'bend: 55296 is not a Unicode scalar value\n',
                        'Default-JS failure differs from the measured isolated-surrogate boundary')
                require(before == source_pins(), 'Entity codec inputs changed during JS diagnostic')
                result = {'schema': 1, 'status': 'EXPECTED_FAILURE', 'mode': 'default-JS', 'guards': [],
                          'processes': processes, 'source_manifest': pin(directory / 'sources.json'),
                          'representation_boundary': 'Isolated surrogate Chr{55296} is rejected during JavaScript lowering before the actual fixture can run.',
                          'scope': 'Measured host representation negative, not product acceptance. Source typing passed; no guards or NaN byte comparison executed. Native retains these same raw character words.'}
                write(directory / 'result.json', result)
                write(ROOT / f'evidence/local-player-effect-entities-codec-{number:03}.json', result)
                print(json.dumps({'status': result['status'], 'guards': 0, 'physical_cases': 0,
                                  'directory': str(directory)}), flush=True)
                return
            process_ok(observed)
        lines = Path(observed['stdout']['path']).read_text().splitlines()
        require(len(lines) == len(GUARDS) + 1 and lines[-1].startswith('bytes ') and
                lines[:-1] == ['ok ' + label for label in GUARDS] and
                not Path(observed['stderr']['path']).read_bytes(), 'Entity guards or harness protocol differ')
        guards = list(GUARDS)
        actual = parse_bytes(lines[-1][6:])
        expected = N.encode_root(root())
        (directory / 'actual.nbt').write_bytes(actual)
        (directory / 'expected.nbt').write_bytes(expected)
        if not native:
            require(actual != expected, 'Default-JS unexpectedly preserved every raw F32 NaN; update measured boundary')
            require(actual == N.encode_root(js_canonicalized(root())) and N.parse(actual) == js_canonicalized(root()),
                    'Default-JS difference exceeds the measured F32 NaN canonicalization boundary')
            require(before == source_pins(), 'Entity codec inputs changed during JS diagnostic')
            result = {'schema': 1, 'status': 'EXPECTED_FAILURE', 'mode': 'default-JS', 'guards': guards,
                      'processes': processes, 'actual_wire': pin(directory / 'actual.nbt'),
                      'expected_wire': pin(directory / 'expected.nbt'), 'source_manifest': pin(directory / 'sources.json'),
                      'scope': 'Negative diagnostic: every physical byte equals the independent fixture except canonicalized F32 NaN payloads at actual F32 field locations. Raw F64 NaN words and all other owner state remain byte-identical. No native acceptance claim.'}
        else:
            require(actual == expected and N.parse(actual) == root(), 'Entity owner snapshot differs from independent complete raw physical NBT')
            cases = []
            for name, wire, accepted in corpus():
                path = directory / (name + '.nbt')
                path.write_bytes(wire)
                cases.append({'name': name, 'input': pin(path), 'accepted': accepted})
            checked = run([*invoke, 'decode', *[case['input']['path'] for case in cases]], 'physical-corpus-native', 60)
            outputs = Path(checked['stdout']['path']).read_text().splitlines()
            require(len(outputs) == len(cases) and not Path(checked['stderr']['path']).read_bytes(), 'Physical entity corpus output count or diagnostics differs')
            roundtrips = 0
            for case, line in zip(cases, outputs):
                if case['accepted']:
                    prefix = 'accepted ' + case['input']['path'] + ' '
                    require(line.startswith(prefix), 'Valid physical entity fixture refused: ' + case['name'])
                    again = parse_bytes(line[len(prefix):])
                    require(again == Path(case['input']['path']).read_bytes() and N.parse(again) == N.parse(Path(case['input']['path']).read_bytes()),
                            'Accepted entity physical fixture did not roundtrip exactly: ' + case['name'])
                    roundtrips += 1
                else:
                    require(line == 'refused ' + case['input']['path'], 'Invalid physical entity fixture accepted: ' + case['name'])
            require(before == source_pins(), 'Entity codec inputs changed during execution')
            require(binary == pin(directory / 'native'), 'Entity codec binary changed during execution')
            result = {'schema': 1, 'status': 'PASS', 'mode': 'native', 'guards': guards, 'cases': cases, 'processes': processes,
                      'physical_roundtrips': roundtrips, 'actual_wire': pin(directory / 'actual.nbt'),
                      'expected_wire': pin(directory / 'expected.nbt'), 'source_manifest': pin(directory / 'sources.json'),
                      'codec': pin(CODEC), 'binary': binary, 'build': pin(directory / 'build.json'),
                      'scope': 'Actual native Bend complete ordered entity owner snapshot and strict physical codec. Independent NBT bytes compare all fields, raw F64/F32, charwords, RNG, large Nat, optional UUIDs and duplicate records. Durable files and actor cold restore require their real consumer.'}
        write(directory / 'result.json', result)
        write(ROOT / f'evidence/local-player-effect-entities-codec-{number:03}.json', result)
        print(json.dumps({'status': result['status'], 'guards': len(guards), 'physical_cases': len(result.get('cases', [])),
                          'directory': str(directory)}), flush=True)
    except BaseException as error:
        result = {'status': 'FAIL', 'type': type(error).__name__, 'message': str(error), 'processes': processes,
                  'source_manifest': pin(directory / 'sources.json')}
        write(directory / 'failure.json', result)
        write(ROOT / f'evidence/local-player-effect-entities-codec-{number:03}-failure.json', result)
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--native', action='store_true', help='Run the native physical codec acceptance lane (default)')
    mode.add_argument('--js', action='store_true', help='Record default-JS raw F32 NaN payload loss as an expected negative diagnostic')
    parser.add_argument('--build-child', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.build_child:
        build_child(args.build_child)
    else:
        main(not args.js)
