#!/usr/bin/env python3
"""Independent literal entity-scene packets through the actual Bend wire codec.

The host assembles fixtures and expected typed observations, not an admission
implementation. Preparation starts no Bend, native, or Java process. Later
phases must be scheduled by the lead under the repository heavy-job limit.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil
import sys

from reference_inventory import canonical, fingerprint, write_json
from build_native import foreign_paths
from test_player_block_inside_stuck import run as checked_run
from test_player_look import imports, verify_build
from test_player_cooking_wire import (
    COMPONENT_HEADER, empty_menu, identity_literal, observed_reply as cooking_observed,
    observed_request, profiles, slot,
)

ROOT = Path(__file__).resolve().parents[1]
BEND = Path('/Users/chuah/.bend/bin/bend')
ENTRY = ROOT / 'tests/remote_entity_scene_wire.bend'
WORK = ROOT / 'build/remote-entity-scene-wire/001'
BINARY = WORK / 'receiver'
BUILD = WORK / 'native-build.json'
REFERENCE = ROOT / 'reference/item_component.json'
EVIDENCE = ROOT / 'evidence/remote-entity-scene-wire-native.json'
EPOCH = 'entity-scene-wire'
NAT_MAX = (1 << 48) - 1
U32_MAX = (1 << 32) - 1
REGISTRY = 'entity-fixture:26.3'
DIMENSION = 'minecraft:the_end'
ORIGIN = [2147483648, 0, 1078984704, 0, 3220176896, 0]
CAMERA = [2147483648, 0, 2147483648, 1119092736, 3258187776]
CURRENT = [2147483648, 0, 1072693248, 1, 3220176896, 0]
OLD = [0, 1, 1073741824, 0, 3221225472, 0]
PARTIAL = 1056964608
APPEARANCE = [[[2, U32_MAX], [0, 4278190080]], U32_MAX, 1, 1, True, 127]
CELL = [U32_MAX, 2147483648, 0, 3, 321, U32_MAX, APPEARANCE]


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def compact(value):
    return json.dumps(value, ensure_ascii=True, separators=(',', ':'))


def replace(value, path, replacement):
    result = copy.deepcopy(value)
    at = result
    for index in path[:-1]:
        at = at[index]
    at[path[-1]] = replacement
    return result


def common(identifier=23, *, dimension=DIMENSION, order=NAT_MAX,
           removed=False, accessible=True):
    return [dimension, identifier, copy.deepcopy(CURRENT), copy.deepcopy(OLD),
            U32_MAX, removed, accessible, order]


def sample():
    return [REGISTRY, NAT_MAX, NAT_MAX - 1, copy.deepcopy(ORIGIN),
            copy.deepcopy(CAMERA), [copy.deepcopy(CELL)]]


def scene_reply(components, variant='bound', *, bob=1048576000, count=1):
    records = [
        [0, common(), slot('minecraft:suspicious_stew', count, components), bob],
        [1, common(7, dimension='minecraft:overworld', order=0,
                   removed=True, accessible=False), U32_MAX],
        [0, common(U32_MAX, order=0), slot('minecraft:stone', 99), 2147483648],
    ]
    entities = [1, records]
    if variant == 'unbound':
        entities = [0]
    elif variant == 'empty':
        entities = [1, []]
    elif variant == 'item_empty':
        records[0][2] = [0]
    elif variant == 'orb_zero':
        records[1][2] = 0
    elif variant == 'id_zero':
        records[0][1][1] = 0
    elif variant == 'duplicate_id':
        records[1][1][1] = 23
    elif variant == 'current_infinity':
        records[0][1][2][0:2] = [2146435072, 0]
    elif variant == 'old_nan':
        records[0][1][3][4:6] = [2146959360, 123]
    elif variant == 'bob_nan':
        records[0][3] = 2143289345
    elif variant == 'bob_infinity':
        records[0][3] = 2139095040
    elif variant == 'multi_large':
        records[2][2] = slot('minecraft:suspicious_stew', 1, components)
    elif variant == 'unknown_dimension':
        pass  # Canonical dimension identifiers are structurally represented.
    frame = [sample(), entities, 'fixture:other_dimension' if variant == 'unknown_dimension' else DIMENSION, PARTIAL]
    return [1, 9, EPOCH, NAT_MAX, frame]


def observed_slot(value):
    return None if value == [0] else dict(id=value[1], components=value[2], count=value[3])


def observed_sample(value):
    registry, tick, revision, origin, camera, cells = value
    return dict(registry=registry, tick=tick, revision=revision, origin=origin,
                camera=camera, cells=cells)


def observed_common(value):
    dimension, identifier, current, old, tick_count, removed, accessible, order = value
    return dict(dimension=dimension, id=identifier, current=current, old=old,
                tick_count=tick_count, removed=removed, accessible=accessible,
                source_order=order)


def observed_entities(value):
    if value == [0]:
        return dict(bound=False)
    records = []
    for record in value[1]:
        row = dict(kind=record[0], common=observed_common(record[1]))
        if record[0] == 0:
            row.update(item=observed_slot(record[2]), bob=record[3])
        else:
            row['value'] = record[2]
        records.append(row)
    return dict(bound=True, records=records)


def observed_stamp(frame):
    s, _, dimension, partial = frame
    return dict(registry=s[0], tick=s[1], revision=s[2], dimension=dimension,
                origin=s[3], camera=s[4], partial=partial)


def observed_reply(packet):
    if packet[1] == 9:
        frame = packet[4]
        return dict(tag=9, epoch=packet[2], sequence=packet[3],
                    frame=dict(sample=observed_sample(frame[0]), entities=observed_entities(frame[1]),
                               dimension=frame[2], partial=frame[3]))
    if packet[1] == 7:
        return dict(tag=7, epoch=packet[2], sequence=packet[3], sample=observed_sample(packet[4]))
    if packet[1] == 1:
        tick, revision, origin, camera, palette, reads, cells = packet[4]
        require(cells == [], 'legacy observer fixture must have no cells')
        return dict(tag=1, epoch=packet[2], sequence=packet[3], sample=dict(
            tick=tick, revision=revision, origin=origin, camera=camera, palette=palette,
            reads=reads, raw_count=0, blocks_count=0, masks_count=0))
    return cooking_observed(packet)


class Corpus:
    def __init__(self):
        self.inputs = []
        self.expected = []

    def add(self, name, mode, packet=None, *, accepted=True, scope='wire-contract', **fields):
        require(name not in {row['id'] for row in self.inputs}, 'duplicate case: ' + name)
        incoming = dict(id=name, mode=mode, **fields)
        if mode.startswith('decode_'):
            incoming['text'] = compact(packet)
        expected = dict(id=name, mode=mode, accepted=accepted, scope=scope)
        if mode == 'stamp':
            matches = fields['variant'] in ('same', 'same_zero_partial')
            expected.update(stamp=observed_stamp(packet[4]), matches=matches,
                checked=dict(accepted=True) if matches else dict(
                    accepted=False, error='entity-wire:capture-stamp-mismatch'))
        elif mode == 'correlation':
            expected['observed'] = fields['expected']
            del incoming['expected']
        elif accepted:
            require(packet is not None, name + ': missing literal packet')
            expected.update(text=compact(packet), observed=(observed_reply(packet)
                if mode.endswith('reply') else observed_request(packet)))
        self.inputs.append(incoming)
        self.expected.append(expected)

    def raw(self, name, mode, text):
        self.add(name, mode, accepted=False)
        self.inputs[-1]['text'] = text


def corpus():
    data = Corpus()
    components = profiles()[0][1]
    base = scene_reply(components)
    call = lambda body: [1, 1, EPOCH, NAT_MAX, body]

    # Original tags retain literal version1 shapes. This does not run the old
    # full dispatcher, world producer, or framing suite.
    data.add('legacy/hello', 'decode_request', [1, 0, 'legacy-capability'])
    old_commands = [[0, 16, 16], [1, [True, False, []]], [2], [3, 1], [4, 8], [5],
        [6, 0, 1, 3, 0], [7, 0, ['minecraft:stone', ''], 4], [8], [9], [10],
        [11, 43, [0, 1]], [12, 8], [13, 16, 16],
        [14, ['minecraft:the_end', U32_MAX, 2147483648, U32_MAX - 1]],
        [15, 0], [16, 23, 38, 1], [17, 23, 38], [18, 23], [19, True]]
    for body in old_commands:
        data.add('legacy/command-' + str(body[0]), 'decode_request', call(body))
    replies = [
        [1, 0, EPOCH, 0], [1, 1, EPOCH, NAT_MAX,
            [17, 19, [0] * 6, [0] * 5, [0, 1, 2, 3], 0, []]],
        [1, 2, EPOCH, NAT_MAX], [1, 3, EPOCH, NAT_MAX, 'legacy fault'],
        [1, 4, EPOCH, NAT_MAX, empty_menu()[0]],
        [1, 5, EPOCH, NAT_MAX, True, 'legacy action'],
        [1, 6, EPOCH, NAT_MAX, False, 'legacy menu', empty_menu()],
        [1, 7, EPOCH, NAT_MAX, sample()],
        [1, 8, EPOCH, NAT_MAX, False, 'legacy cooking', [[0], [0], empty_menu()]],
    ]
    for packet in replies:
        data.add('legacy/reply-' + str(packet[1]), 'decode_reply', packet)
    data.add('request/default', 'decode_request', call([20, 16, 32, PARTIAL]))
    data.add('request/default-typed', 'encode_request', call([20, 16, 32, PARTIAL]),
             width=16, height=32, partial=PARTIAL)
    for word in (0, 2147483648, 1, 1065353216):
        data.add('request/partial-' + str(word), 'decode_request', call([20, 4, 4096, word]))
        data.add('request/typed-partial-' + str(word), 'encode_request', call([20, 4, 4096, word]),
                 width=4, height=4096, partial=word)
    for width, height in ((3, 16), (16, 3), (4097, 16), (16, 4097), (0, 0), (U32_MAX, U32_MAX)):
        data.add(f'request/dimensions-{width}-{height}', 'decode_request', call([20, width, height, PARTIAL]), accepted=False)
        data.add(f'request/typed-dimensions-{width}-{height}', 'encode_request', accepted=False,
                 width=width, height=height, partial=PARTIAL)
    for path, name in (([4, 1], 'width'), ([4, 2], 'height'), ([4, 3], 'partial')):
        marked = compact(replace(call([20, 16, 32, PARTIAL]), path, '__LEXEME__'))
        for suffix, lexeme in (('negative-zero', '-0'), ('fraction', '16.0'),
                               ('exponent', '16e0'), ('leading-zero', '016'), ('overflow', '4294967296')):
            data.raw(f'request/lexeme-{name}-{suffix}', 'decode_request', marked.replace('"__LEXEME__"', lexeme))
    for word in (2139095040, 4286578688, 2143289345, 3212836864, 1065353217):
        data.add('request/invalid-partial-' + str(word), 'decode_request', call([20, 16, 16, word]), accepted=False)
        data.add('request/typed-invalid-partial-' + str(word), 'encode_request', accepted=False,
                 width=16, height=16, partial=word)
    for name, body in (('short', [20, 16, 16]), ('long', [20, 16, 16, PARTIAL, 0]),
                       ('object', {'width': 16, 'height': 16, 'partial': PARTIAL}),
                       ('partial-string', [20, 16, 16, str(PARTIAL)]),
                       ('partial-bool', [20, 16, 16, True])):
        data.add('request/' + name, 'decode_request', call(body), accepted=False)

    for variant in ('bound', 'unbound', 'empty', 'item_empty', 'orb_zero', 'id_zero', 'unknown_dimension'):
        packet = scene_reply(components, variant)
        data.add('reply/' + variant, 'decode_reply', packet)
        data.add('reply/typed-' + variant, 'encode_reply', packet, variant=variant, components=components, count=1, bob=1048576000)
    for profile_name, payload in profiles():
        packet = scene_reply(payload)
        data.add('reply/modified-' + profile_name, 'decode_reply', packet, scope='structural-provisional')
        data.add('reply/typed-modified-' + profile_name, 'encode_reply', packet,
                 variant='bound', components=payload, count=1, bob=1048576000,
                 scope='structural-provisional')
    for bob in (0, 2147483648, 1, 2139095039, 4286578687, 1065353217):
        packet = scene_reply(components, bob=bob)
        data.add('reply/bob-' + str(bob), 'decode_reply', packet)
        data.add('reply/typed-bob-' + str(bob), 'encode_reply', packet, variant='bound', components=components, count=1, bob=bob)
    for variant in ('duplicate_id', 'current_infinity', 'old_nan', 'bob_nan', 'bob_infinity'):
        data.add('reply/' + variant, 'decode_reply', scene_reply(components, variant), accepted=False)
        data.add('reply/typed-' + variant, 'encode_reply', accepted=False, variant=variant, components=components, count=1, bob=1048576000)
    for count in (0, 2, 99, 100):
        data.add('decline/typed-modified-count-' + str(count), 'encode_reply', accepted=False,
                 variant='bound', components=components, count=count, bob=1048576000)
    for name, invalid in (
        ('opaque-components', 'opaque'),
        ('unknown-component-map', identity_literal({'fixture:unknown': 1})),
        ('duplicate-component-map', COMPONENT_HEADER + '{"minecraft:damage":0,"minecraft:damage":1}'),
        ('unsorted-component-map', COMPONENT_HEADER + '{"minecraft:max_stack_size":1,"minecraft:damage":0}'),
        ('wrong-component-envelope', 'BendCraftComponents2\t1\t{}'),
    ):
        data.add('decline/typed-' + name, 'encode_reply', accepted=False,
                 variant='bound', components=invalid, count=1, bob=1048576000)

    # Only the named field changes; all other literal DTO data remain valid.
    structural = (
        ('frame-short', [4], base[4][:-1]), ('frame-long', [4], base[4] + [0]),
        ('frame-object', [4], {}), ('sample-short', [4, 0], base[4][0][:-1]),
        ('sample-long', [4, 0], base[4][0] + [0]), ('sample-object', [4, 0], {}),
        ('entities-short', [4, 1], []), ('entities-long-unbound', [4, 1], [0, []]),
        ('entities-short-bound', [4, 1], [1]), ('entities-long-bound', [4, 1], [1, [], 0]),
        ('entities-unknown-tag', [4, 1], [2, []]), ('entities-object', [4, 1], {}),
        ('records-object', [4, 1, 1], {}), ('item-short', [4, 1, 1, 0], base[4][1][1][0][:-1]),
        ('item-long', [4, 1, 1, 0], base[4][1][1][0] + [0]),
        ('orb-short', [4, 1, 1, 1], base[4][1][1][1][:-1]),
        ('orb-long', [4, 1, 1, 1], base[4][1][1][1] + [0]),
        ('record-object', [4, 1, 1, 0], {}), ('record-tag2', [4, 1, 1, 0, 0], 2),
        ('common-short', [4, 1, 1, 0, 1], base[4][1][1][0][1][:-1]),
        ('common-long', [4, 1, 1, 0, 1], base[4][1][1][0][1] + [0]),
        ('common-object', [4, 1, 1, 0, 1], {}),
        ('current-short', [4, 1, 1, 0, 1, 2], CURRENT[:-1]),
        ('current-long', [4, 1, 1, 0, 1, 2], CURRENT + [0]),
        ('old-short', [4, 1, 1, 0, 1, 3], OLD[:-1]),
        ('old-long', [4, 1, 1, 0, 1, 3], OLD + [0]),
        ('current-object', [4, 1, 1, 0, 1, 2], {}),
        ('removed-word', [4, 1, 1, 0, 1, 5], 0),
        ('accessible-string', [4, 1, 1, 0, 1, 6], 'true'),
        ('dimension-empty', [4, 2], ''), ('dimension-unqualified', [4, 2], 'overworld'),
        ('dimension-uppercase', [4, 2], 'Minecraft:overworld'),
        ('dimension-empty-namespace', [4, 2], ':overworld'),
        ('dimension-empty-path', [4, 2], 'minecraft:'),
        ('dimension-multiple-colons', [4, 2], 'minecraft:over:world'),
        ('dimension-namespace-slash', [4, 2], 'mine/craft:overworld'),
        ('record-dimension-empty', [4, 1, 1, 0, 1, 0], ''),
        ('record-dimension-unqualified', [4, 1, 1, 0, 1, 0], 'overworld'),
        ('record-dimension-empty-namespace', [4, 1, 1, 0, 1, 0], ':overworld'),
        ('record-dimension-empty-path', [4, 1, 1, 0, 1, 0], 'minecraft:'),
        ('record-dimension-multiple-colons', [4, 1, 1, 0, 1, 0], 'minecraft:over:world'),
        ('registry-empty', [4, 0, 0], ''), ('registry-space', [4, 0, 0], 'invalid identity'),
        ('origin-nonfinite', [4, 0, 3, 0], 2146435072),
        ('camera-position', [4, 0, 4, 0], 1065353216),
        ('camera-nan', [4, 0, 4, 3], 2143289345),
        ('cell-duplicate', [4, 0, 5], [copy.deepcopy(CELL), copy.deepcopy(CELL)]),
        ('cell-short', [4, 0, 5, 0], CELL[:-1]), ('cell-long', [4, 0, 5, 0], CELL + [0]),
        ('boundary4', [4, 0, 5, 0, 3], 4),
        ('tint-duplicate', [4, 0, 5, 0, 6, 0], [[2, U32_MAX], [2, 0]]),
        ('tint-index-sentinel', [4, 0, 5, 0, 6, 0, 0, 0], U32_MAX),
        ('light-missing-alpha', [4, 0, 5, 0, 6, 1], 16777215),
        ('partial-negative', [4, 3], 3212836864), ('partial-over1', [4, 3], 1065353217),
        ('partial-nan', [4, 3], 2143289345), ('partial-string', [4, 3], '0.5'),
    )
    for name, path, value in structural:
        data.add('decline/' + name, 'decode_reply', replace(base, path, value), accepted=False)
    item_path = [4, 1, 1, 0, 2]
    for name, value in (
        ('slot-object', {}), ('empty-extra', [0, 0]),
        ('stack-short', [1, 'minecraft:stone', '']), ('stack-long', [1, 'minecraft:stone', '', 1, 0]),
        ('count0', slot('minecraft:stone', 0)), ('count100', slot('minecraft:stone', 100)),
        ('modified-count2', slot('minecraft:suspicious_stew', 2, components)),
        ('bad-identifier', slot('Minecraft:Stone')), ('opaque-components', slot('minecraft:stone', components='opaque')),
        ('unknown-components', slot('minecraft:stone', components=identity_literal({'fixture:unknown': 1}))),
        ('duplicate-component-map', slot('minecraft:diamond_sword', components=COMPONENT_HEADER + '{"minecraft:damage":0,"minecraft:damage":1}')),
        ('unsorted-component-map', slot('minecraft:diamond_sword', components=COMPONENT_HEADER + '{"minecraft:max_stack_size":1,"minecraft:damage":0}')),
    ):
        data.add('decline/' + name, 'decode_reply', replace(base, item_path, value), accepted=False)
    for name, value in (
        ('empty-effective-map', COMPONENT_HEADER + '{}'),
        ('modified-stack64', identity_literal({'minecraft:max_stack_size': 64}, 64)),
    ):
        packet = replace(base, item_path, slot('minecraft:stone', 1 if name == 'empty-effective-map' else 64, value))
        data.add('provisional/' + name, 'decode_reply', packet, scope='structural-provisional')
    for axis in range(3):
        for field, vector_index in (('current', 2), ('old', 3)):
            for name, words in (('positive-infinity', [2146435072, 0]),
                                ('negative-infinity', [4293918720, 0]),
                                ('nan-payload', [2146959360, 123])):
                vector = list(CURRENT if field == 'current' else OLD)
                vector[axis * 2:axis * 2 + 2] = words
                data.add(f'decline/{field}-{axis}-{name}', 'decode_reply',
                         replace(base, [4, 1, 1, 0, 1, vector_index], vector), accepted=False)
    swapped = replace(base, [4, 1, 1, 0, 1, 2], OLD)
    swapped = replace(swapped, [4, 1, 1, 0, 1, 3], CURRENT)
    data.add('reply/current-old-swapped-retained', 'decode_reply', swapped)
    finite_extreme = replace(base, [4, 1, 1, 0, 1, 2], [2146435071, U32_MAX, 4293918719, U32_MAX, 0, 1])
    data.add('reply/finite-extreme-positions', 'decode_reply', finite_extreme)
    order = [copy.deepcopy(base[4][1][1][2]), copy.deepcopy(base[4][1][1][0]), copy.deepcopy(base[4][1][1][1])]
    data.add('reply/arbitrary-record-and-source-order', 'decode_reply', replace(base, [4, 1, 1], order))
    duplicate_across_dimensions = replace(base, [4, 1, 1, 1, 1, 1], 23)
    data.add('decline/duplicate-id-across-dimensions', 'decode_reply', duplicate_across_dimensions, accepted=False)

    # Canonical U32/Nat48 words are tested as actual JSON lexemes; typed native
    # values beyond their representable widths cannot be constructed.
    lexical_paths = [([4, 3], 'partial'), ([4, 1, 1, 0, 1, 1], 'entity-id'),
                     ([4, 1, 1, 0, 1, 4], 'tick-count'), ([4, 1, 1, 0, 3], 'bob'),
                     ([4, 1, 1, 1, 2], 'orb-value'), ([4, 1, 1, 0, 1, 2, 1], 'f64-low')]
    for path, name in lexical_paths:
        marked = compact(replace(base, path, '__LEXEME__'))
        for suffix, lexeme in (('negative-zero', '-0'), ('negative', '-1'), ('fraction', '1.0'),
                               ('exponent', '1e0'), ('leading-zero', '01'), ('overflow', '4294967296')):
            data.raw(f'lexeme/{name}-{suffix}', 'decode_reply', marked.replace('"__LEXEME__"', lexeme))
        for suffix, value in (('boolean', True), ('string', '1'), ('null', None), ('array', []), ('object', {})):
            data.add(f'type/{name}-{suffix}', 'decode_reply', replace(base, path, value), accepted=False)
    nat_paths = [([3], 'sequence'), ([4, 0, 1], 'sample-tick'), ([4, 0, 2], 'sample-revision'),
                 ([4, 1, 1, 0, 1, 7], 'source-order')]
    for path, name in nat_paths:
        marked = compact(replace(base, path, '__LEXEME__'))
        for suffix, lexeme in (('negative-zero', '-0'), ('fraction', '1.0'), ('exponent', '1e0'),
                               ('leading-zero', '01'), ('overflow', '281474976710656')):
            data.raw(f'lexeme/{name}-{suffix}', 'decode_reply', marked.replace('"__LEXEME__"', lexeme))
        for suffix, value in (('boolean', True), ('string', '1'), ('null', None), ('array', []), ('object', {})):
            data.add(f'type/{name}-{suffix}', 'decode_reply', replace(base, path, value), accepted=False)
    for mode, packet in (('decode_request', call([20, 16, 16, PARTIAL])), ('decode_reply', base)):
        for name, path, value in (('version2', [0], 2), ('sequence0', [3], 0),
                                  ('sequence-overflow', [3], NAT_MAX + 1), ('epoch-empty', [2], ''),
                                  ('outer-extra', [], packet + [0]), ('outer-short', [], packet[:-1])):
            incoming = value if not path else replace(packet, path, value)
            data.add(mode + '/' + name, mode, incoming, accepted=False)

    # EW.matches must compare every stamp field by raw words, including zero
    # signs. A mismatched expectation is a consumer refusal, not malformed JSON.
    for variant in ('same', 'registry', 'tick', 'revision', 'dimension', 'origin_x_hi',
                    'origin_x_lo', 'origin_y_hi', 'origin_y_lo', 'origin_z_hi', 'origin_z_lo',
                    'camera_x', 'camera_y', 'camera_z', 'camera_yaw', 'camera_pitch', 'partial'):
        data.add('stamp/' + variant, 'stamp', base, variant=variant, components=components,
                 count=1, bob=1048576000)
    for variant in ('same_zero_partial', 'partial_zero_sign'):
        packet = replace(base, [4, 3], 2147483648)
        data.add('stamp/' + variant, 'stamp', packet, variant=variant, components=components,
                 count=1, bob=1048576000)
    correlation_rows = (
        ('same', True, True, True, True),
        ('wrong_epoch', False, True, False, False),
        ('wrong_sequence', False, True, False, False),
        ('wrong_partial', True, False, False, True),
        ('wrong_stamp', True, True, True, False),
        ('legacy', True, False, False, False),
        ('same_zero_partial', True, True, True, True),
        ('partial_zero_sign', True, False, False, False),
    )
    for variant, header, fraction, fraction_bound, stamp_bound in correlation_rows:
        data.add('correlation/' + variant, 'correlation', variant=variant, components=components,
                 count=1, bob=1048576000, expected=dict(correlation=header,
                 fraction_valid=fraction, fraction_matches=fraction_bound, stamp_matches=stamp_bound))

    large_effective = copy.deepcopy(json.loads(REFERENCE.read_text())['default_components'])
    large_effective['minecraft:suspicious_stew_effects'] = [dict(duration=0, id='minecraft:saturation') for _ in range(1200)]
    large = identity_literal(large_effective)
    single = scene_reply(large)
    multiple = scene_reply(large, 'multi_large')
    require(len(compact(single)) < 65536 < len(compact(multiple)), 'independent aggregate byte witnesses changed')
    data.add('budget/single-large', 'decode_reply', single, scope='wire-budget')
    data.add('budget/typed-single-large', 'encode_reply', single, variant='bound', components=large, count=1, bob=1048576000, scope='wire-budget')
    data.add('budget/multiple-large', 'decode_reply', multiple, accepted=False, scope='wire-budget')
    data.add('budget/typed-multiple-large', 'encode_reply', accepted=False, variant='multi_large', components=large, count=1, bob=1048576000, scope='wire-budget')
    tiny_records = [[1, ['a:b', index, [0] * 6, [0] * 6, 0, False, True, 0], 0] for index in range(700)]
    aggregate = replace(base, [4, 1], [1, tiny_records])
    require(len(compact(aggregate)) < 65536, 'AST-only witness exceeds byte budget')
    data.add('budget/ast-only-700-records', 'decode_reply', aggregate, accepted=False, scope='wire-budget')
    data.raw('syntax/malformed-json', 'decode_reply', compact(base)[:-1])
    data.raw('syntax/raw-nonascii', 'decode_reply', compact(base).replace(REGISTRY, 'entity-fixture:α'))
    data.raw('syntax/depth-nine', 'decode_reply', '[' * 9 + '0' + ']' * 9)
    return data


def prepare(folder):
    data = corpus()
    folder.mkdir(parents=True, exist_ok=True)
    write_json(folder / 'input.json', data.inputs)
    write_json(folder / 'expected.json', data.expected)
    return data


def compare(data, stdout):
    actual = [json.loads(line) for line in stdout.decode().splitlines() if line.startswith('{')]
    require(len(actual) == len(data.expected), dict(actual=len(actual), expected=len(data.expected)))
    for expected, row in zip(data.expected, actual, strict=True):
        require(row.get('id') == expected['id'], dict(expected=expected['id'], actual=row))
        result = row['result']
        if expected['mode'] == 'correlation':
            require(result == expected['observed'], dict(case=expected['id'], actual=result, expected=expected['observed']))
            continue
        if expected['mode'] == 'stamp':
            require(result == dict(stamp=expected['stamp'], matches=expected['matches'], checked=expected['checked']),
                    dict(case=expected['id'], actual=result, expected=expected))
            continue
        admission = result['encoded'] if expected['mode'].startswith('encode_') else result
        require(admission['accepted'] == expected['accepted'], dict(case=expected['id'], result=result))
        if not expected['accepted']:
            require(isinstance(admission.get('error'), str) and admission['error'], 'missing refusal diagnostic: ' + expected['id'])
            continue
        decoded = result['decoded'] if expected['mode'].startswith('encode_') else result
        require(decoded['accepted'], dict(case=expected['id'], result=result))
        require(decoded['observed'] == expected['observed'], dict(case=expected['id'], observed=decoded['observed'], expected=expected['observed']))
        require(decoded['encoded'] == dict(accepted=True, text=expected['text']), dict(case=expected['id'], encoded=decoded['encoded'], expected=expected['text']))
        if expected['mode'].startswith('encode_'):
            require(admission == dict(accepted=True, text=expected['text']), dict(case=expected['id'], encoded=admission, expected=expected['text']))
    return actual


def pins():
    result = imports([ENTRY])
    for path in (Path(__file__).resolve(), REFERENCE, ROOT / 'tools/test_player_cooking_wire.py',
                 ROOT / 'tools/build_native.py', ROOT / 'tools/test_player_block_inside_stuck.py',
                 ROOT / 'tools/test_player_look.py', ROOT / 'tools/reference_inventory.py'):
        result[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def unchanged(source_pins):
    require(all(hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest
                for name, digest in source_pins.items()), 'entity-scene wire source/input changed during run')


def frozen_receiver(folder):
    """Copy the actual project closure once, including relative foreign files."""
    names = imports([ENTRY])
    for name in list(names):
        source = ROOT / name
        for foreign in foreign_paths(source.read_text()):
            path = (source.parent / foreign).resolve()
            if path.is_relative_to(ROOT):
                names[str(path.relative_to(ROOT))] = fingerprint(path)['sha256']
    mapped = []
    for name, digest in sorted(names.items()):
        source, target = ROOT / name, folder / 'source' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as output:
            output.write(source.read_bytes())
        require(fingerprint(source)['sha256'] == digest == fingerprint(target)['sha256'],
                'Source changed during frozen copy: ' + name)
        mapped.append(dict(original=str(source), path=str(target), sha256=digest))
    require(all(fingerprint(Path(row['original']))['sha256'] == row['sha256'] for row in mapped),
            'Original source changed during closure copy')
    write_json(folder / 'source-map.json', mapped)
    return folder / 'source' / ENTRY.relative_to(ROOT)


def unchanged_owned(source_pins):
    owned = {'src/remote_entity_frame.bend', 'src/remote_entity_snapshot_wire.bend',
             'src/resource_client_wire.bend', str(ENTRY.relative_to(ROOT))}
    unchanged({name: digest for name, digest in source_pins.items()
               if name in owned or not name.endswith('.bend')})


def verified_artifact(report):
    if report.get('route') != 'verified-private-producer':
        return verify_build(report)
    require(report['complete_original_checker'], 'private producer did not check complete source')
    for row in report['dependencies']:
        require(fingerprint(Path(row['path']))['sha256'] == row['sha256'], 'compiled dependency drift: ' + row['path'])
    for row in (report['producer_basis'], report['private_compiler'],
                report['original_checker'], report['original_compiler'], report['c_source'],
                report['emitter'], report['compiler'], report['source_manifest'], report['source_map']):
        require(fingerprint(Path(row['path']))['sha256'] == row['sha256'], 'producer/C pin changed: ' + row['path'])
    require(fingerprint(Path(report['artifact']))['sha256'] == report['binary_sha256'], 'private binary changed')
    return Path(report['artifact'])


def private_build(folder, binary, build_report):
    """Existing nine-graph verified producer; no original compiler mutation."""
    c_source = folder / 'receiver.c'
    entry = frozen_receiver(folder)
    _, emitted = checked_run(['/usr/bin/env', 'BEND_PRODUCER_GC=1',
        'BEND_PRODUCER_LOG=' + str(folder / 'emit-functions.jsonl'),
        '/opt/homebrew/bin/node', '--expose-gc', '--max-old-space-size=8192',
        '--stack-size=4096', '--experimental-transform-types',
        ROOT / 'tools/player_cooking_menu_emit.mjs', entry, c_source], folder, 'emit', 900)
    compiler = Path(shutil.which('clang') or '/usr/bin/clang').resolve()
    _, compiled = checked_run([compiler, '-std=c11', '-O3', c_source,
        '-lpthread', '-lm', '-o', binary], folder, 'clang', 300)
    manifest = json.loads(Path(str(c_source) + '.sources.json').read_bytes())
    require(manifest['complete_original_checker'], 'full original source check missing')
    record = dict(route='verified-private-producer', artifact=str(binary),
        original_entry=str(ENTRY), frozen_entry=str(entry),
        binary_sha256=fingerprint(binary)['sha256'], complete_original_checker=True,
        dependencies=[dict(path=path, sha256=digest) for path, digest in manifest['source_sha256'].items()],
        c_source=dict(path=str(c_source), sha256=fingerprint(c_source)['sha256']),
        producer_basis=manifest['producer_basis'], private_compiler=manifest['private_compiler'],
        original_checker=manifest['original_checker'], original_compiler=manifest['original_compiler'],
        emitter=dict(path=str(ROOT / 'tools/player_cooking_menu_emit.mjs'),
                     sha256=fingerprint(ROOT / 'tools/player_cooking_menu_emit.mjs')['sha256']),
        compiler=dict(path=str(compiler), sha256=fingerprint(compiler)['sha256']),
        cpu_flags=['-std=c11', '-O3', '-lpthread', '-lm'],
        source_manifest=dict(path=str(c_source) + '.sources.json',
                             sha256=fingerprint(Path(str(c_source) + '.sources.json'))['sha256']),
        source_map=dict(path=str(folder / 'source-map.json'),
                        sha256=fingerprint(folder / 'source-map.json')['sha256']),
        scope='The already verified cached/private C producer checks the complete original source book and source/foreign pins. Its nine-graph C/GC equivalence basis is retained; this new graph is exercised by the literal native codec consumer, not claimed byte-equal to a new original-CLI emission.')
    verified_artifact(record)
    write_json(build_report, record)
    return [emitted, compiled]


def run(phase, folder, binary, build_report, private_producer=False):
    data = prepare(folder)
    prepared = dict(status='prepared', cases=len(data.inputs),
        accepted=sum(row['accepted'] for row in data.expected),
        refused=sum(not row['accepted'] for row in data.expected),
        stamp_observations=sum(row['mode'] == 'stamp' for row in data.expected),
        correlation_observations=sum(row['mode'] == 'correlation' for row in data.expected))
    if phase == 'prepare':
        write_json(folder / 'preparation.json', dict(prepared,
            input=fingerprint(folder / 'input.json'), expected=fingerprint(folder / 'expected.json'),
            observer=fingerprint(ENTRY), driver=fingerprint(Path(__file__).resolve()),
            reference=fingerprint(REFERENCE), boundary='Fixture preparation and literal consistency only. '
            'No Bend source check, native execution, Java observation, or passing protocol verdict. '
            'The host supplies admission expectations and typed field literals; actual admission is exercised only in later scheduled phases.'))
        print(json.dumps(prepared))
        return
    source_pins = pins()
    checks = []
    if phase in ('source', 'all'):
        _, receipt = checked_run([BEND, ENTRY, '--check-only'], folder, 'source', 120)
        checks.append(receipt)
        unchanged(source_pins)
    if phase == 'source':
        print(json.dumps(dict(prepared, status='source-checked', checks=checks)))
        return
    if phase in ('build', 'all'):
        if private_producer:
            checks.extend(private_build(folder, binary, build_report))
        else:
            _, receipt = checked_run([sys.executable, ROOT / 'tools/build_native.py', ENTRY,
                '-o', binary, '--bend', BEND, '--report', build_report], folder, 'build', 900)
            checks.append(receipt)
        (unchanged_owned if private_producer else unchanged)(source_pins)
    report = json.loads(build_report.read_text())
    artifact = verified_artifact(report)
    require(fingerprint(binary)['sha256'] == report['binary_sha256'], 'binary differs from verified artifact')
    require((report.get('original_entry') == str(ENTRY) if report.get('route') == 'verified-private-producer'
             else any(Path(item['path']) == ENTRY.resolve() for item in report['dependencies'])), 'native report lacks observer')
    build_pin = fingerprint(build_report)
    if phase == 'build':
        print(json.dumps(dict(prepared, status='built', native_build=build_pin)))
        return
    if phase == 'receipt':
        native = json.loads((folder / 'native.json').read_bytes())
        require(native['exit_code'] == 0 and not native['timed_out'] and native['group_absent'],
                'Retained execution did not succeed or reap')
        require(fingerprint(folder / 'native.stdout') == native['stdout'], 'Retained native output changed')
        stdout = (folder / 'native.stdout').read_bytes()
    else:
        stdout, native = checked_run([artifact, '--gpu', 'off', '--threads', '1', folder / 'input.json'], folder, 'native', 180)
    actual = compare(data, stdout)
    (unchanged_owned if report.get('route') == 'verified-private-producer' else unchanged)(source_pins)
    verified_artifact(report)
    require(fingerprint(build_report) == build_pin, 'build receipt changed during replay')
    evidence = dict(prepared, status='passed', native=native, checks=checks, native_build=build_pin,
        compiled_artifact=fingerprint(artifact), source_sha256=source_pins,
        input=fingerprint(folder / 'input.json'), expected=fingerprint(folder / 'expected.json'),
        reference=fingerprint(REFERENCE), boundary='Actual W.decode_request/decode_reply and encode_request/encode_reply. Independent literals for command20/reply9 and typed entity/sample fields, plus literal old tags0..19/replies0..8. Common current/old F64 raw words, signed zero, finite bob F32 words, item keys/counts, flags and retained record/source order are observed directly. EW.matches checks literal mismatched consumer stamps. Duplicate IDs and malformed component maps refuse; cross-dimension records, empty items, orb0, ID0 and repeated unordered source_order remain structurally represented. Component structural admission is separate from initialized item authority. Aggregate byte/value budgets are observed without truncation. No entity simulation, world capture atomicity, renderer drawing, sockets, native presentation or Java parity verdict is inferred.')
    if report.get('route') == 'verified-private-producer':
        evidence['compiled_source_manifest'] = report['source_manifest']
        evidence['producer_basis'] = report['producer_basis']
        evidence['frozen_source_map'] = report['source_map']
        evidence['post_emission_import_drift'] = [dict(original=row['original'],
            compiled_sha256=row['sha256'], current_sha256=fingerprint(Path(row['original']))['sha256'])
            for row in json.loads(Path(report['source_map']['path']).read_bytes())
            if fingerprint(Path(row['original']))['sha256'] != row['sha256']]
    EVIDENCE.parent.mkdir(parents=True, exist_ok=True)
    write_json(EVIDENCE, evidence)
    print(json.dumps(dict(prepared, status='passed', cases=len(actual))))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase', choices=('prepare', 'source', 'build', 'native', 'receipt', 'all'), default='prepare')
    parser.add_argument('--work', type=Path, default=WORK)
    parser.add_argument('--binary', type=Path, default=BINARY)
    parser.add_argument('--build-report', type=Path, default=BUILD)
    parser.add_argument('--verified-producer', action='store_true',
        help='Use the existing nine-graph C/GC verified private producer after an original CLI boundary is retained.')
    args = parser.parse_args()
    run(args.phase, args.work.resolve(), args.binary.resolve(), args.build_report.resolve(), args.verified_producer)


if __name__ == '__main__':
    main()
