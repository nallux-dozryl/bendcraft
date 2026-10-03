#!/usr/bin/env python3
"""Independent Core.World snapshot-schema fixtures for the native Bend codec.

Python specifies fixtures and expected bytes only; snapshot encode/decode under
verification execute in build/world-codec-tests. This format persists the current
Core.World representation, not Minecraft's vanilla save-file formats.
"""
from __future__ import annotations

import argparse
import collections
import dataclasses
import hashlib
import json
import random
import re
import subprocess
import time
from pathlib import Path

import test_nbt as N

ROOT = Path(__file__).resolve().parents[1]
BEND = Path('/Users/chuah/.bend/bin/bend')
BUILD = ROOT / 'build/world-codec-reference'
REGISTRY = 'fixture-registry'
COUNT = 16
NAT_MAX = (1 << 48) - 1
MAX_SECTIONS = 512
MAX_NAT_DIGITS = 15
MAX_STRING_UNITS = 65535
DIMENSIONS = ('minecraft:overworld', 'minecraft:the_nether', 'minecraft:the_end')
COLLISION_KEYS = ('minecraft:overworld/12009114/36153475/77999535',
                  'minecraft:overworld/21442934/118325841/132352103')
ROOT_FIELDS = ('format', 'minecraft', 'registry', 'state_count', 'tick', 'day_time',
               'paused', 'daylight', 'revision', 'sections', 'pending', 'events')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def txt(value):
    return N.Value(8, N.text(str(value)))


def integer(bits):
    return N.Value(3, bits)


def byte(bits):
    return N.Value(1, bits)


def compound(fields):
    return N.Value(10, tuple((N.text(key), value) for key, value in fields))


def listing(values, element=10):
    return N.Value(9, (element, tuple(values)))


def replace_field(value, key, replacement):
    assert value.kind == 10
    target = N.text(key)
    assert sum(name == target for name, _ in value.payload) == 1
    return N.Value(10, tuple((name, replacement if name == target else v) for name, v in value.payload))


def fnv(key):
    acc = 2166136261
    for c in key:
        acc = ((acc ^ ord(c)) * 16777619) & 0xffffffff
    return acc


def scalar_text(value):
    if value.kind != 8:
        raise ValueError('expected TAG_String')
    if len(value.payload) > MAX_STRING_UNITS:
        raise ValueError('string UTF-16 unit limit')
    raw = b''.join(c.to_bytes(2, 'big') for c in value.payload)
    return raw.decode('utf-16-be', errors='strict')


def fields(value, names):
    if value.kind != 10:
        raise ValueError('expected TAG_Compound')
    result = {}
    for units, item in value.payload:
        key = scalar_text(N.Value(8, units))
        if key in result:
            raise ValueError('duplicate member')
        result[key] = item
    if set(result) != set(names):
        raise ValueError('unknown or missing member')
    return result


def uint(value):
    if value.kind != 3:
        raise ValueError('expected TAG_Int raw U32')
    return value.payload


def small(value, upper):
    if value.kind != 1 or not 0 <= value.payload <= upper:
        raise ValueError('expected bounded TAG_Byte')
    return value.payload


def natural(value):
    s = scalar_text(value)
    if len(s) > MAX_NAT_DIGITS or not re.fullmatch(r'0|[1-9][0-9]*', s):
        raise ValueError('noncanonical or oversized Nat decimal')
    # Current Bend 2.0.35 native Nat uses a 48-bit immediate representation.
    if len(s) > 15 or len(s) == 15 and s > str(NAT_MAX):
        raise ValueError('Nat exceeds the verified native bound')
    return int(s)


def sequence(value, capacity):
    if value.kind != 9 or value.payload[0] != 10:
        raise ValueError('expected TAG_List with declared compound element ID')
    items = value.payload[1]
    if len(items) > capacity:
        raise ValueError('container capacity')
    return items


def key_string(value):
    key = scalar_text(value)
    parts = key.split('/')
    if len(parts) != 4 or parts[0] not in DIMENSIONS:
        raise ValueError('noncanonical section dimension/key')
    for token in parts[1:]:
        if not re.fullmatch(r'0|[1-9][0-9]*', token):
            raise ValueError('noncanonical section coordinate decimal')
        coordinate = int(token)
        if coordinate > 0xffffffff or not (coordinate < 134217728 or coordinate >= 4160749568):
            raise ValueError('section coordinate outside signed-world decomposition range')
    return key


def stamp(fields_map):
    return (natural(fields_map['tick']), uint(fields_map['peer']), natural(fields_map['sequence']))


def mutation(value, state_count):
    if value.kind != 10:
        raise ValueError('expected mutation compound')
    peek = dict(value.payload).get(N.text('kind'))
    if peek is None:
        raise ValueError('missing mutation kind')
    kind = small(peek, 3)
    names = ('kind', 'dimension', 'x', 'y', 'z', 'state') if kind < 2 else (('kind', 'day_time') if kind == 2 else ('kind', 'enabled'))
    f = fields(value, names)
    if kind < 2:
        dimension = scalar_text(f['dimension'])
        state = uint(f['state'])
        if dimension not in DIMENSIONS or state >= state_count:
            raise ValueError('invalid queued position dimension/state')
        return {'kind': kind, 'dimension': dimension, 'x': uint(f['x']), 'y': uint(f['y']), 'z': uint(f['z']), 'state': state}
    if kind == 2:
        return {'kind': kind, 'day_time': natural(f['day_time'])}
    return {'kind': kind, 'enabled': bool(small(f['enabled'], 1))}


def error(value):
    if value.kind != 10:
        raise ValueError('expected error compound')
    peek = dict(value.payload).get(N.text('kind'))
    if peek is None:
        raise ValueError('missing error kind')
    kind = small(peek, 7)
    suffix = {1: ('dimension',), 2: ('state',), 3: ('key',), 4: ('key',)}.get(kind, ())
    f = fields(value, ('kind',) + suffix)
    result = {'kind': kind}
    if kind == 1:
        result['dimension'] = scalar_text(f['dimension'])
    elif kind == 2:
        result['state'] = uint(f['state'])
    elif kind in (3, 4):
        result['key'] = key_string(f['key'])
    return result


def validate(root, expected_count=COUNT, expected_registry=REGISTRY):
    if root.name != N.text('bendex:world'):
        raise ValueError('wrong named root')
    f = fields(root.value, ROOT_FIELDS)
    if uint(f['format']) != 1 or scalar_text(f['minecraft']) != '26.3':
        raise ValueError('format/version mismatch')
    registry = scalar_text(f['registry'])
    state_count = uint(f['state_count'])
    if state_count != expected_count or registry != expected_registry:
        raise ValueError('registry/count mismatch')
    tick, day_time, revision = natural(f['tick']), natural(f['day_time']), natural(f['revision'])
    paused, daylight = bool(small(f['paused'], 1)), bool(small(f['daylight'], 1))
    sections = []
    previous = None
    for item in sequence(f['sections'], MAX_SECTIONS):
        s = fields(item, ('key', 'cells'))
        key = key_string(s['key'])
        if previous is not None and key <= previous:
            raise ValueError('section keys must be strictly increasing')
        previous = key
        cells = s['cells']
        if cells.kind != 11 or len(cells.payload) != 4096 or any(v >= state_count for v in cells.payload):
            raise ValueError('invalid section cell type/count/state')
        sections.append({'key': key, 'cells': cells.payload})
    pending, max_peer, previous_stamp = [], None, None
    for item in sequence(f['pending'], 4096):
        p = fields(item, ('tick', 'peer', 'sequence', 'mutation'))
        st = stamp(p)
        if st[0] <= tick or previous_stamp is not None and st < previous_stamp:
            raise ValueError('pending stamp order/future tick')
        previous_stamp = st
        pending.append({'stamp': st, 'mutation': mutation(p['mutation'], state_count)})
        max_peer = st[1] if max_peer is None else max(max_peer, st[1])
    events, previous_stamp = [], None
    for item in sequence(f['events'], 1024):
        if item.kind != 10:
            raise ValueError('expected event compound')
        peek = dict(item.payload).get(N.text('kind'))
        if peek is None:
            raise ValueError('missing event kind')
        kind = small(peek, 1)
        e = fields(item, ('tick', 'peer', 'sequence', 'kind', 'revision' if kind == 0 else 'error'))
        st = stamp(e)
        if st[0] > tick or previous_stamp is not None and st > previous_stamp:
            raise ValueError('event stamp order/past tick')
        previous_stamp = st
        event = {'stamp': st, 'kind': kind}
        if kind == 0:
            rev = natural(e['revision'])
            if not 0 < rev <= revision:
                raise ValueError('applied event revision bound')
            event['revision'] = rev
        else:
            event['error'] = error(e['error'])
        events.append(event)
        max_peer = st[1] if max_peer is None else max(max_peer, st[1])
    return {'registry': registry, 'state_count': state_count, 'tick': tick, 'day_time': day_time,
            'paused': paused, 'daylight': daylight, 'revision': revision, 'sections': sections,
            'pending': pending, 'events': events, 'max_peer': max_peer}


def mutation_value(m):
    f = [('kind', byte(m['kind']))]
    if m['kind'] < 2:
        f += [('dimension', txt(m['dimension']))] + [(name, integer(m[name])) for name in ('x', 'y', 'z', 'state')]
    elif m['kind'] == 2:
        f += [('day_time', txt(m['day_time']))]
    else:
        f += [('enabled', byte(int(m['enabled'])))]
    return compound(f)


def error_value(e):
    f = [('kind', byte(e['kind']))]
    if e['kind'] == 1:
        f += [('dimension', txt(e['dimension']))]
    elif e['kind'] == 2:
        f += [('state', integer(e['state']))]
    elif e['kind'] in (3, 4):
        f += [('key', txt(e['key']))]
    return compound(f)


def stamp_values(st):
    return [('tick', txt(st[0])), ('peer', integer(st[1])), ('sequence', txt(st[2]))]


def snapshot_root(w):
    sections = [compound([('key', txt(s['key'])), ('cells', N.Value(11, tuple(s['cells'])))]) for s in w['sections']]
    pending = [compound(stamp_values(p['stamp']) + [('mutation', mutation_value(p['mutation']))]) for p in w['pending']]
    events = [compound(stamp_values(e['stamp']) + [('kind', byte(e['kind'])),
                       ('revision', txt(e['revision'])) if e['kind'] == 0 else ('error', error_value(e['error']))]) for e in w['events']]
    return N.RootTag(N.text('bendex:world'), compound([
        ('format', integer(1)), ('minecraft', txt('26.3')), ('registry', txt(w['registry'])),
        ('state_count', integer(w['state_count'])), ('tick', txt(w['tick'])), ('day_time', txt(w['day_time'])),
        ('paused', byte(int(w['paused']))), ('daylight', byte(int(w['daylight']))), ('revision', txt(w['revision'])),
        ('sections', listing(sections)), ('pending', listing(pending)), ('events', listing(events)),
    ]))


def empty_world(count=COUNT, registry=REGISTRY):
    return {'registry': registry, 'state_count': count, 'tick': 0, 'day_time': 0,
            'paused': True, 'daylight': True, 'revision': 0, 'sections': [], 'pending': [], 'events': []}


def section(key, fill=0, edits=()):
    cells = [fill] * 4096
    for index, state in edits:
        cells[index] = state
    return {'key': key, 'cells': tuple(cells)}


def scenario_worlds():
    worlds = {'empty': empty_world(), 'collision': empty_world(), 'signed': empty_world(), 'rich': empty_world()}
    worlds['collision']['sections'] = [section(COLLISION_KEYS[0], 1), section(COLLISION_KEYS[1], 2)]
    worlds['signed']['sections'] = sorted([
        section('minecraft:overworld/4294967295/0/4294967294', 3),
        section('minecraft:the_end/4160749568/134217727/0', 4),
    ], key=lambda s: s['key'])
    rich = worlds['rich']
    rich.update(tick=42, day_time=1000, paused=False, daylight=False, revision=4)
    rich['sections'] = [section('minecraft:overworld/0/0/0', 0, [(0, 7), (4095, 15)]),
                        section('minecraft:the_nether/1/0/0', 2, [(17, 3)])]
    rich['pending'] = [
        {'stamp': (43, 7, 1), 'mutation': {'kind': 0, 'dimension': DIMENSIONS[0], 'x': 32, 'y': 0, 'z': 0, 'state': 4}},
        {'stamp': (43, 8, 2), 'mutation': {'kind': 1, 'dimension': DIMENSIONS[1], 'x': 16, 'y': 0, 'z': 0, 'state': 3}},
        {'stamp': (44, 3, 100), 'mutation': {'kind': 2, 'day_time': 999}},
        {'stamp': (44, 3, 101), 'mutation': {'kind': 3, 'enabled': False}},
    ]
    rich['events'] = [
        {'stamp': (42, 7, 2), 'kind': 0, 'revision': 4},
        {'stamp': (41, 6, 1), 'kind': 1, 'error': {'kind': 1, 'dimension': 'custom:unknown'}},
        {'stamp': (40, 1, 3), 'kind': 0, 'revision': 1},
    ]
    return worlds


@dataclasses.dataclass(frozen=True)
class Case:
    name: str
    data: bytes
    count: int
    registry: str
    expected: bytes | None
    peer: int | None
    category: str


def corpus():
    cases = []
    def add(name, root, *, valid=True, count=COUNT, registry=REGISTRY, category='schema'):
        raw = N.encode_root(root)
        add_raw(name, raw, valid=valid, count=count, registry=registry, category=category)
    def add_raw(name, raw, *, valid=True, count=COUNT, registry=REGISTRY, category='schema'):
        try:
            model = validate(N.parse(raw), count, registry)
            canonical = N.encode_root(snapshot_root(model))
        except ValueError:
            if valid:
                raise
            canonical, peer = None, None
        else:
            if not valid:
                raise AssertionError('independent oracle accepted intended invalid fixture: ' + name)
            peer = model['max_peer']
        cases.append(Case(name, raw, count, registry, canonical, peer, category))
    worlds = scenario_worlds()
    for name, world in worlds.items():
        add('scenario-' + name, snapshot_root(world), category='constructed-scenario')
    empty, rich = snapshot_root(worlds['empty']), snapshot_root(worlds['rich'])
    for field in ('tick', 'day_time', 'revision'):
        for number in (1, 4294967295, 4294967296, 2**40 + 17, NAT_MAX):
            add(f'large-nat-{field}-{number}', dataclasses.replace(empty, value=replace_field(empty.value, field, txt(number))), category='native-nat-range')
        for token in ('', '00', '01', '-0', '-1', '+1', ' 1', '1 ', '1.0', '1e3', '\x00', str(NAT_MAX + 1), str(2**64), '9' * 4096):
            add(f'bad-nat-{field}-{sha(token.encode())[:8]}', dataclasses.replace(empty, value=replace_field(empty.value, field, txt(token))), valid=False, category='nat-rejection')
    for count in (0, 1, 2, 33, 0xffffffff):
        world = empty_world(count)
        if count:
            world['sections'] = [section('minecraft:overworld/0/0/0', count - 1)]
        add(f'state-count-{count}', snapshot_root(world), count=count, category='state-domain')
    world = empty_world(registry='fixture:é€😀ไทย')
    add('unicode-registry-match', snapshot_root(world), registry=world['registry'], category='scalar-strings')
    add('count-mismatch', empty, count=17, valid=False, category='registry-identity')
    add('registry-mismatch', empty, registry='other-registry', valid=False, category='registry-identity')
    add('wrong-root-name', dataclasses.replace(empty, name=N.text('wrong:world')), valid=False)
    add('wrong-root-value', N.RootTag(empty.name, integer(1)), valid=False)
    add('root-end', N.RootTag((), N.Value(0)), valid=False)
    for field, replacement in [('format', integer(0)), ('format', integer(2)), ('minecraft', txt('26.2')), ('minecraft', txt('26.3 ')),
                               ('paused', byte(2)), ('paused', byte(255)), ('daylight', byte(2)), ('daylight', byte(255))]:
        add(f'bad-header-{field}-{replacement.payload}', dataclasses.replace(empty, value=replace_field(empty.value, field, replacement)), valid=False)
    for field in ('sections', 'pending', 'events'):
        for element in (0, 1, 12):
            add(f'bad-empty-list-header-{field}-{element}', dataclasses.replace(empty, value=replace_field(empty.value, field, listing([], element))), valid=False)
    for label, value in [('root', rich.value)]:
        schema_corruptions(label, value, lambda v: dataclasses.replace(rich, value=v), add)
    rich_fields = dict(rich.value.payload)
    for list_name in ('sections', 'pending', 'events'):
        items = rich_fields[N.text(list_name)].payload[1]
        for index, item in enumerate(items):
            def wrap(v, *, name=list_name, pos=index, items=items):
                updated = list(items); updated[pos] = v
                return dataclasses.replace(rich, value=replace_field(rich.value, name, listing(updated)))
            schema_corruptions(f'{list_name}-{index}', item, wrap, add)
            nested_name = 'mutation' if list_name == 'pending' else ('error' if list_name == 'events' and index == 1 else None)
            if nested_name:
                nested = dict(item.payload)[N.text(nested_name)]
                schema_corruptions(f'{list_name}-{index}-{nested_name}', nested,
                                   lambda v, item=item, nested_name=nested_name, wrap=wrap: wrap(replace_field(item, nested_name, v)), add)
    rng = random.Random(0x26_03_574f)
    for i in range(20):
        members = list(rich.value.payload); rng.shuffle(members)
        add(f'root-member-permutation-{i}', dataclasses.replace(rich, value=N.Value(10, tuple(members))), category='member-order-canonicalization')
    def all_member_shuffle(value):
        if value.kind == 10:
            members = [(name, all_member_shuffle(v)) for name, v in value.payload]
            rng.shuffle(members)
            return N.Value(10, tuple(members))
        if value.kind == 9:
            return N.Value(9, (value.payload[0], tuple(all_member_shuffle(v) for v in value.payload[1])))
        return value
    add('all-compound-member-orders-permuted', dataclasses.replace(rich, value=all_member_shuffle(rich.value)), category='member-order-canonicalization')
    for key in ('minecraft:overworld/0/0/0', 'minecraft:overworld/134217727/4160749568/4294967295',
                'minecraft:the_nether/4160749568/134217727/0', 'minecraft:the_end/0/0/0'):
        world = empty_world(); world['sections'] = [section(key, 15)]
        add('valid-section-key-' + key, snapshot_root(world), category='signed-section-keys')
    for key in ('minecraft:overworld/-1/0/0', 'minecraft:overworld/00/0/0', 'minecraft:overworld/01/0/0',
                'minecraft:overworld/4294967296/0/0', 'minecraft:overworld/134217728/0/0',
                'minecraft:overworld/4160749567/0/0', 'minecraft:overworld/2147483648/0/0',
                'minecraft:overworld/0/0', 'minecraft:overworld/0/0/0/', 'minecraft:unknown/0/0/0',
                'minecraft:overworld/0/0/ 0', 'minecraft:overworld/0/0/0\x00'):
        world = empty_world(); world['sections'] = [section(key)]
        add('bad-section-key-' + repr(key), snapshot_root(world), valid=False, category='section-key-rejection')
    for size in (0, 1, 4095, 4097):
        world = empty_world(); world['sections'] = [{'key': 'minecraft:overworld/0/0/0', 'cells': (0,) * size}]
        add(f'bad-section-cell-count-{size}', snapshot_root(world), valid=False, category='cell-domain')
    for bad_state in (16, 0xffffffff):
        world = empty_world(); world['sections'] = [section('minecraft:overworld/0/0/0', 0, [(4095, bad_state)])]
        add(f'bad-section-cell-state-{bad_state}', snapshot_root(world), valid=False, category='cell-domain')
    for cells in (N.Value(7, b'\0' * 4096), listing([integer(0)] * 4096, 3)):
        item = compound([('key', txt('minecraft:overworld/0/0/0')), ('cells', cells)])
        add(f'bad-section-cells-type-{cells.kind}', dataclasses.replace(empty, value=replace_field(empty.value, 'sections', listing([item]))), valid=False, category='cell-domain')
    duplicate = section('minecraft:overworld/0/0/0')
    world = empty_world(); world['sections'] = [duplicate, duplicate]
    add('duplicate-section-key', snapshot_root(world), valid=False, category='section-order')
    world = worlds['collision'].copy(); world['sections'] = list(reversed(world['sections']))
    add('descending-section-key-order', snapshot_root(world), valid=False, category='section-order')
    for count in (512, 513):
        world = empty_world(); world['sections'] = sorted([section(f'minecraft:overworld/{i}/0/0', i % 16) for i in range(count)], key=lambda s: s['key'])
        add(f'section-capacity-{count}', snapshot_root(world), valid=count <= 512, category='capacity-boundaries')
    world = empty_world(); world.update(tick=10, day_time=NAT_MAX, revision=NAT_MAX)
    world['pending'] = [
        {'stamp': (11, 0, 0), 'mutation': {'kind': 0, 'dimension': DIMENSIONS[0], 'x': 0xffffffff, 'y': 0x80000000, 'z': 0x7fffffff, 'state': 15}},
        {'stamp': (11, 0xffffffff, NAT_MAX), 'mutation': {'kind': 1, 'dimension': DIMENSIONS[2], 'x': 0x80000000, 'y': 0xffffffff, 'z': 0, 'state': 0}},
        {'stamp': (12, 2, 4294967296), 'mutation': {'kind': 2, 'day_time': NAT_MAX}},
        {'stamp': (12, 2, 4294967297), 'mutation': {'kind': 3, 'enabled': True}},
    ]
    error_payloads = [{'kind': 0}, {'kind': 1, 'dimension': 'mod:é😀\x00unknown'}, {'kind': 2, 'state': 0xffffffff},
                      {'kind': 3, 'key': 'minecraft:overworld/4294967295/0/0'}, {'kind': 4, 'key': 'minecraft:the_end/0/0/0'},
                      {'kind': 5}, {'kind': 6}, {'kind': 7}]
    world['events'] = [{'stamp': (10 - i, 20 + i, NAT_MAX - i), 'kind': 1, 'error': e} for i, e in enumerate(error_payloads)]
    typed = snapshot_root(world)
    add('all-typed-mutations-errors-u32-peers-nats', typed, category='typed-variants')
    for i, e in enumerate(world['events']):
        event = dict(typed.value.payload)[N.text('events')].payload[1][i]
        error_compound = dict(event.payload)[N.text('error')]
        def wrap_error(v, *, i=i, event=event):
            events = list(dict(typed.value.payload)[N.text('events')].payload[1]); events[i] = replace_field(event, 'error', v)
            return dataclasses.replace(typed, value=replace_field(typed.value, 'events', listing(events)))
        schema_corruptions(f'error-kind-{i}', error_compound, wrap_error, add)
    for list_name in ('pending', 'events'):
        original_items = dict(typed.value.payload)[N.text(list_name)].payload[1]
        for index, item in enumerate(original_items):
            for name in ('tick', 'sequence'):
                for token in ('01', str(NAT_MAX + 1), str(2**64)):
                    items = list(original_items); items[index] = replace_field(item, name, txt(token))
                    add(f'bad-nat-{list_name}-{index}-{name}-{token}', dataclasses.replace(typed, value=replace_field(typed.value, list_name, listing(items))), valid=False, category='nat-rejection')
            if list_name == 'pending':
                m = dict(item.payload)[N.text('mutation')]
                if dict(m.payload)[N.text('kind')].payload == 2:
                    for token in ('01', str(NAT_MAX + 1), str(2**64)):
                        items = list(original_items); items[index] = replace_field(item, 'mutation', replace_field(m, 'day_time', txt(token)))
                        add(f'bad-nat-mutation-day-time-{token}', dataclasses.replace(typed, value=replace_field(typed.value, 'pending', listing(items))), valid=False, category='nat-rejection')
    maximum = empty_world(); maximum.update(tick=NAT_MAX - 1, day_time=NAT_MAX, revision=NAT_MAX)
    maximum['pending'] = [{'stamp': (NAT_MAX, 0xffffffff, NAT_MAX), 'mutation': {'kind': 2, 'day_time': NAT_MAX}}]
    maximum['events'] = [{'stamp': (NAT_MAX - 1, 0xfffffffe, NAT_MAX), 'kind': 0, 'revision': NAT_MAX}]
    add('all-nat-fields-at-native-upper-bound', snapshot_root(maximum), category='native-nat-range')
    for token in ('01', str(NAT_MAX + 1), str(2**64)):
        applied = compound(stamp_values((0, 17, 1)) + [('kind', byte(0)), ('revision', txt(token))])
        add('bad-nat-applied-event-revision-' + token, dataclasses.replace(empty, value=replace_field(empty.value, 'events', listing([applied]))), valid=False, category='nat-rejection')
    for field in ('pending', 'events'):
        items = list(dict(typed.value.payload)[N.text(field)].payload[1])
        add(f'descending-required-order-{field}', dataclasses.replace(typed, value=replace_field(typed.value, field, listing(list(reversed(items))))), valid=False, category='stamp-order')
    pending_first = dict(typed.value.payload)[N.text('pending')].payload[1][0]
    for tick in (0, 10):
        add(f'pending-not-future-{tick}', dataclasses.replace(empty, value=replace_field(empty.value, 'pending', listing([replace_field(pending_first, 'tick', txt(tick))]))), valid=tick > 0, category='stamp-temporality')
    add('pending-tick-equals-world', dataclasses.replace(typed, value=replace_field(typed.value, 'pending', listing([replace_field(pending_first, 'tick', txt(10))]))), valid=False, category='stamp-temporality')
    first_event = dict(typed.value.payload)[N.text('events')].payload[1][0]
    add('event-future-tick', dataclasses.replace(typed, value=replace_field(typed.value, 'events', listing([replace_field(first_event, 'tick', txt(11))]))), valid=False, category='stamp-temporality')
    equal = empty_world(); equal.update(tick=1, revision=2)
    equal['pending'] = [{'stamp': (2, 77, 5), 'mutation': {'kind': 2, 'day_time': 1}},
                        {'stamp': (2, 77, 5), 'mutation': {'kind': 3, 'enabled': False}}]
    equal['events'] = [{'stamp': (1, 99, 7), 'kind': 0, 'revision': 1},
                       {'stamp': (1, 99, 7), 'kind': 1, 'error': {'kind': 0}}]
    add('equal-stamps-preserve-distinct-payloads', snapshot_root(equal), category='equal-stamps')
    for capacity, field in [(4096, 'pending'), (1024, 'events')]:
        for count in (capacity, capacity + 1):
            world = empty_world(); world.update(tick=1, revision=1)
            if field == 'pending':
                world[field] = [{'stamp': (2, i, i), 'mutation': {'kind': 3, 'enabled': bool(i % 2)}} for i in range(count)]
            else:
                world[field] = [{'stamp': (1, i, i), 'kind': 1, 'error': {'kind': 0}} for i in reversed(range(count))]
            add(f'{field}-capacity-{count}', snapshot_root(world), valid=count <= capacity, category='capacity-boundaries')
    for revision in (0, 5, NAT_MAX):
        applied = compound(stamp_values((0, 17, 1)) + [('kind', byte(0)), ('revision', txt(revision))])
        world = empty_world(); world['revision'] = 4
        root = snapshot_root(world)
        add(f'applied-revision-outside-world-{revision}', dataclasses.replace(root, value=replace_field(root.value, 'events', listing([applied]))), valid=False, category='event-revision')
    for kind in (2, 255):
        bad = replace_field(first_event, 'kind', byte(kind))
        add(f'unknown-event-kind-{kind}', dataclasses.replace(typed, value=replace_field(typed.value, 'events', listing([bad]))), valid=False, category='typed-rejection')
    for kind in (4, 255):
        bad = replace_field(pending_first, 'mutation', compound([('kind', byte(kind))]))
        add(f'unknown-mutation-kind-{kind}', dataclasses.replace(typed, value=replace_field(typed.value, 'pending', listing([bad]))), valid=False, category='typed-rejection')
    for kind in (3, 4):
        for key in ('garbage', 'minecraft:unknown/0/0/0', 'minecraft:overworld/-1/0/0', 'minecraft:overworld/134217728/0/0'):
            bad = replace_field(first_event, 'error', compound([('kind', byte(kind)), ('key', txt(key))]))
            add(f'bad-error-section-key-{kind}-{key}', dataclasses.replace(typed, value=replace_field(typed.value, 'events', listing([bad]))), valid=False, category='section-key-rejection')
    zero = empty_world(0)
    zero['sections'] = [section('minecraft:overworld/0/0/0', 0)]
    add('zero-state-count-with-cells', snapshot_root(zero), count=0, valid=False, category='state-domain')
    zero = empty_world(0)
    zero['pending'] = [{'stamp': (1, 0, 0), 'mutation': {'kind': 0, 'dimension': DIMENSIONS[0], 'x': 0, 'y': 0, 'z': 0, 'state': 0}}]
    add('zero-state-count-with-position-mutation', snapshot_root(zero), count=0, valid=False, category='state-domain')
    historical = empty_world()
    historical['sections'] = [section('minecraft:overworld/0/0/0')]
    historical['events'] = [{'stamp': (0, 9, 0), 'kind': 1, 'error': {'kind': 3, 'key': 'minecraft:overworld/0/0/0'}},
                            {'stamp': (0, 8, 0), 'kind': 1, 'error': {'kind': 1, 'dimension': DIMENSIONS[0]}}]
    add('historical-errors-retain-recorded-payloads', snapshot_root(historical), category='typed-variants')
    for kind in (8, 255):
        bad = replace_field(first_event, 'error', compound([('kind', byte(kind))]))
        add(f'unknown-error-kind-{kind}', dataclasses.replace(typed, value=replace_field(typed.value, 'events', listing([bad]))), valid=False, category='typed-rejection')
    for replacement in [('dimension', txt('mod:unknown')), ('state', integer(16))]:
        m = dict(pending_first.payload)[N.text('mutation')]
        bad = replace_field(pending_first, 'mutation', replace_field(m, *replacement))
        add('invalid-position-' + replacement[0], dataclasses.replace(typed, value=replace_field(typed.value, 'pending', listing([bad]))), valid=False, category='typed-rejection')
    m = compound([('kind', byte(3)), ('enabled', byte(2))])
    bad = replace_field(pending_first, 'mutation', m)
    add('invalid-daylight-byte', dataclasses.replace(typed, value=replace_field(typed.value, 'pending', listing([bad]))), valid=False, category='typed-rejection')
    for label, units in [('lone-high', (0xd800,)), ('lone-low', (0xdc00,)), ('mismatched-pair', (0xd800, 0x61)), ('reversed-pair', (0xdc00, 0xd800))]:
        e = replace_field(first_event, 'error', compound([('kind', byte(1)), ('dimension', N.Value(8, units))]))
        add('world-string-' + label, dataclasses.replace(typed, value=replace_field(typed.value, 'events', listing([e]))), valid=False, category='scalar-strings')
    world = empty_world(); world['events'] = [{'stamp': (0, 7, 0), 'kind': 1, 'error': {'kind': 1, 'dimension': 'a' * 65535}}]
    add('string-units-boundary-65535', snapshot_root(world), category='capacity-boundaries')
    rng = random.Random(0xC0_52_26_03)
    for i in range(120):
        count = rng.choice([1, 2, 16, 33, 0xffffffff])
        world = empty_world(count)
        world.update(tick=rng.randrange(1000), day_time=rng.choice([rng.randrange(10000), 2**40 + i]),
                     paused=bool(rng.randrange(2)), daylight=bool(rng.randrange(2)), revision=rng.randrange(1, 10000))
        for j in range(rng.randrange(4)):
            key = f'{DIMENSIONS[j % 3]}/{rng.choice([j, 4294967295 - j, 4160749568 + j])}/0/{j}'
            cells = tuple((index * (j + 3) + i) % count for index in range(4096))
            world['sections'].append({'key': key, 'cells': cells})
        world['sections'].sort(key=lambda s: s['key'])
        for j in range(rng.randrange(8)):
            kind = rng.randrange(4)
            m = {'kind': kind}
            if kind < 2:
                m.update(dimension=rng.choice(DIMENSIONS), x=rng.getrandbits(32), y=rng.getrandbits(32), z=rng.getrandbits(32), state=rng.randrange(count))
            elif kind == 2:
                m['day_time'] = rng.choice([j, NAT_MAX - i])
            else:
                m['enabled'] = bool(rng.randrange(2))
            world['pending'].append({'stamp': (world['tick'] + rng.randrange(1, 20), rng.getrandbits(32), rng.choice([j, 2**40 + j])), 'mutation': m})
        world['pending'].sort(key=lambda p: p['stamp'])
        for j in range(rng.randrange(8)):
            event = {'stamp': (rng.randrange(world['tick'] + 1), rng.getrandbits(32), j), 'kind': rng.randrange(2)}
            if event['kind'] == 0:
                event['revision'] = rng.randrange(1, world['revision'] + 1)
            else:
                event['error'] = rng.choice(error_payloads)
            world['events'].append(event)
        world['events'].sort(key=lambda e: e['stamp'], reverse=True)
        add(f'generated-{i}', snapshot_root(world), count=count, category='generated')
    raw_empty = N.encode_root(empty)
    for n in range(len(raw_empty)):
        add_raw(f'truncated-empty-{n}', raw_empty[:n], valid=False, category='truncation')
    raw_rich = N.encode_root(rich)
    for n in sorted(set([0, 1, 2, 3, 4, 16, 64, 128, len(raw_rich) // 2, len(raw_rich) - 1] + list(range(len(raw_rich) - 32, len(raw_rich))))):
        add_raw(f'truncated-rich-{n}', raw_rich[:n], valid=False, category='truncation')
    marker = b'\x08\x00\x04tick\x00\x01' + b'0'
    assert raw_empty.count(marker) == 1
    add_raw('noncanonical-mutf-nat-digit', raw_empty.replace(marker, b'\x08\x00\x04tick\x00\x02\xc0\xb0'), category='nbt-normalization')
    assert raw_empty[:4] == b'\x0a\x00\x0cb'
    add_raw('noncanonical-mutf-root-name', b'\x0a\x00\x0d\xc1\xa2' + raw_empty[4:], category='nbt-normalization')
    add_raw('trailing-input', raw_empty + b'\xff', valid=False, category='nbt-policy')
    deep = byte(0)
    for _ in range(513):
        deep = N.Value(9, (deep.kind, (deep,)))
    add('nbt-depth-overflow-before-schema', dataclasses.replace(empty, value=N.Value(10, empty.value.payload + ((N.text('extra'), deep),))), valid=False, category='nbt-policy')
    return cases, worlds


def schema_corruptions(label, value, wrap, add):
    assert value.kind == 10
    for index, (name, item) in enumerate(value.payload):
        key = scalar_text(N.Value(8, name))
        add(f'{label}-missing-{key}', wrap(N.Value(10, value.payload[:index] + value.payload[index + 1:])), valid=False, category='exact-fieldsets')
        add(f'{label}-duplicate-{key}', wrap(N.Value(10, value.payload + ((name, item),))), valid=False, category='exact-fieldsets')
        wrong = byte(0) if item.kind == 8 else txt('wrong-type')
        add(f'{label}-wrong-type-{key}', wrap(N.Value(10, value.payload[:index] + ((name, wrong),) + value.payload[index + 1:])), valid=False, category='typed-rejection')
    add(f'{label}-unknown-field', wrap(N.Value(10, value.payload + ((N.text('extra'), byte(0)),))), valid=False, category='exact-fieldsets')


def run(command, timeout=180):
    process = subprocess.run([str(x) for x in command], cwd=ROOT, text=True, capture_output=True, timeout=timeout)
    if process.returncode:
        raise RuntimeError(f'command failed ({process.returncode}): {command}\n{process.stdout}{process.stderr}')
    return process.stdout


def execute(binary, cases, *, peers=False):
    results = []
    groups = collections.defaultdict(list)
    for case in cases:
        groups[(case.count, case.registry)].append(case)
    for (count, registry), group in groups.items():
        batch, size = [], len(registry.encode())
        def check(items, lines):
            if len(items) != len(lines):
                raise AssertionError('native output count mismatch')
            for case, line in zip(items, lines):
                expected = ('none' if case.peer is None else f'peer\t{case.peer}') if peers else ('error' if case.expected is None else 'ok\t' + case.expected.hex())
                passed = line.startswith('error\t') if case.expected is None else line == expected
                if not passed:
                    raise AssertionError(f'{case.name}: expected {expected[:180]!r}, observed {line[:180]!r}; input bytes={len(case.data)} sha256={sha(case.data)}')
                results.append((case, line))
        def consume():
            nonlocal batch, size
            if batch:
                lines = run([binary, '--threads', '1', 'peer-batch' if peers else 'batch', count, registry, *(c.data.hex() for c in batch)], timeout=600).splitlines()
                check(batch, lines); batch, size = [], len(registry.encode())
        for case in group:
            if len(case.data) * 2 > 80_000:
                consume()
                target = BUILD / 'input.hex'; target.write_text(case.data.hex())
                lines = run([binary, '--threads', '1', 'peer-file' if peers else 'file', count, registry, target], timeout=600).splitlines()
                check([case], lines)
            else:
                if batch and (len(batch) >= 25 or size + len(case.data) * 2 > 180_000):
                    consume()
                batch.append(case); size += len(case.data) * 2
        consume()
        print(f'{"peers" if peers else "roundtrips"}: {len(results)}/{len(cases)} cases checked', flush=True)
    return results


def main():
    executed_oracle_sha256 = sha(Path(__file__).read_bytes())
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-build', action='store_true')
    parser.add_argument('--oracle-only', action='store_true')
    options = parser.parse_args()
    started = time.monotonic(); BUILD.mkdir(parents=True, exist_ok=True)
    cases, worlds = corpus()
    assert fnv(COLLISION_KEYS[0]) == fnv(COLLISION_KEYS[1]) == 4257771677
    if options.oracle_only:
        print(json.dumps({'cases': len(cases), 'accepted': sum(c.expected is not None for c in cases),
                          'rejected': sum(c.expected is None for c in cases), 'collision_keys': COLLISION_KEYS,
                          'collision_hash': fnv(COLLISION_KEYS[0])}, indent=2))
        return
    binary = ROOT / 'build/world-codec-tests'
    checks = {}
    for source in ('src/world_codec.bend', 'tests/world_codec.bend'):
        output = run([BEND, source, '--check-only'])
        if 'ALL PROOFS CHECK' not in output:
            raise AssertionError(output)
        checks[source] = output.strip()
    if not options.skip_build:
        run([BEND, 'tests/world_codec.bend', '-o', binary], timeout=300)
    if run([binary, '--threads', '1']).strip() != 'regressions\tpass':
        raise AssertionError('native built-in regressions failed')
    emissions = {}
    for name, world in worlds.items():
        line = run([binary, '--threads', '1', 'emit', name]).strip()
        expected = N.encode_root(snapshot_root(world))
        if line != 'ok\t' + expected.hex():
            raise AssertionError('native constructed scenario differs from independent expected bytes: ' + name)
        emissions[name] = {'bytes': len(expected), 'sha256': sha(expected)}
    results = execute(binary, cases)
    valid = [c for c in cases if c.expected is not None]
    canonical_cases = [dataclasses.replace(c, name='canonical-' + c.name, data=c.expected) for c in valid]
    execute(binary, canonical_cases)
    peer_results = execute(binary, valid, peers=True)
    pure = (ROOT / 'src/world_codec.bend').read_text()
    if '@unsafe' in pure or re.search(r'\bIO[.<(]|import\s+"', pure):
        raise AssertionError('world snapshot codec contains unsafe/effect-backed logic')
    kernel = {}
    for source in ('src/world_codec.bend', 'tests/world_codec.bend'):
        process = subprocess.run([str(BEND), source, '--verdict'], cwd=ROOT, text=True, capture_output=True, timeout=120)
        kernel[source] = {'exit_code': process.returncode, 'output': (process.stdout + process.stderr).strip()}
    dependencies = ['src/core.bend', 'src/section.bend', 'src/section_map.bend', 'src/schedule.bend', 'src/nbt.bend']
    report = {
        'schema': 1, 'kind': 'independent_core_world_snapshot_schema_and_native_roundtrips', 'pin': '26.3',
        'compiler': run([BEND, 'version']).strip(), 'source_sha256': sha(pure.encode()),
        'harness_sha256': sha((ROOT / 'tests/world_codec.bend').read_bytes()),
        'native_binary_sha256': sha(binary.read_bytes()), 'oracle_sha256': executed_oracle_sha256,
        'current_oracle_sha256': sha(Path(__file__).read_bytes()), 'nbt_oracle_sha256': sha((ROOT / 'tools/test_nbt.py').read_bytes()),
        'dependency_sha256': {p: sha((ROOT / p).read_bytes()) for p in dependencies},
        'checker': checks, 'kernel_verdict': kernel, 'native_builtin_regressions': 'pass',
        'independent_cases': len(cases), 'accepted_cases': len(valid), 'rejected_cases': len(cases) - len(valid),
        'canonical_roundtrips': len(canonical_cases), 'max_peer_fixtures': len(peer_results), 'native_constructed_scenarios': emissions,
        'category_counts': dict(sorted(collections.Counter(c.category for c in cases).items())),
        'input_tree_sha256': sha(''.join(c.name + '\t' + str(c.count) + '\t' + c.registry + '\t' + sha(c.data) + '\n' for c in cases).encode()),
        'output_tree_sha256': sha(''.join(c.name + '\t' + sha(line.encode()) + '\n' for c, line in results).encode()),
        'max_peer_output_tree_sha256': sha(''.join(c.name + '\t' + line + '\n' for c, line in peer_results).encode()),
        'all_cases_passed': True, 'elapsed_seconds': round(time.monotonic() - started, 3),
        'hash_collision': {'keys': COLLISION_KEYS, 'fnv_scalar32': fnv(COLLISION_KEYS[0]), 'search_seed': 26032026, 'collision_search_iteration': 167771},
        'limits': {'sections': MAX_SECTIONS, 'raw_owned_map_nodes': 65536, 'native_nat_max': NAT_MAX, 'default_nat_digits': MAX_NAT_DIGITS,
                   'string_utf16_units': MAX_STRING_UNITS, 'pending': 4096, 'events': 1024, 'nbt': {'bytes': N.DEFAULT_BYTES, 'depth': N.DEFAULT_DEPTH, 'elements': N.DEFAULT_ELEMENTS}},
        'native_nat_evidence': {'base': 'Nat.read.fits gates against 281474976710655 before Nat.read.go',
                                'compiler': 'comp.ts defines NAT_IMM ((1ull << 48) - 1); nat_chk posts ERR_NATS above it',
                                'base_sha256': sha((ROOT.parent / 'bend/bend2/base.bend').read_bytes()),
                                'compiler_sha256': sha((ROOT.parent / 'bend/bend2/comp.ts').read_bytes())},
        'qualification': ['This verifies the current Core.World snapshot schema, not vanilla Minecraft saves, migration, region files or crash recovery.',
                          'The native Nat representation cannot store values above 2^48-1; above-U32 values are verified, above-U64 inputs must be rejected.',
                          'Affine owner preservation and invalid direct constructors execute in the parent-owned native built-in regressions.',
                          'Registry identity is a caller-supplied string, not an independently computed registry digest.'],
        'commands': ['python3 tools/test_world_codec.py' + (' --skip-build' if options.skip_build else ''),
                     '/Users/chuah/.bend/bin/bend src/world_codec.bend --check-only',
                     '/Users/chuah/.bend/bin/bend tests/world_codec.bend --check-only',
                     '/Users/chuah/.bend/bin/bend tests/world_codec.bend -o build/world-codec-tests',
                     './build/world-codec-tests --threads 1', './build/world-codec-tests --threads 1 emit rich',
                     './build/world-codec-tests --threads 1 batch 16 fixture-registry HEX...',
                     './build/world-codec-tests --threads 1 peer-batch 16 fixture-registry HEX...',
                     '/Users/chuah/.bend/bin/bend src/world_codec.bend --verdict',
                     '/Users/chuah/.bend/bin/bend tests/world_codec.bend --verdict'],
    }
    (ROOT / 'evidence/world-codec-tests.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({k: report[k] for k in ['independent_cases', 'accepted_cases', 'rejected_cases', 'canonical_roundtrips', 'max_peer_fixtures', 'all_cases_passed', 'elapsed_seconds']}, indent=2))


if __name__ == '__main__':
    main()
