#!/usr/bin/env python3
"""Literal cooking wire packets through the actual Bend decoder and encoder.

The host assembles expected JSON and compares observed typed fields. It does
not implement admission. A few literal legacy/default records and v2 refusals
run independently of old dispatchers. The default phase starts no process.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys

from reference_inventory import canonical, fingerprint, write_json
from test_player_block_inside_stuck import run as checked_run
from test_player_look import imports, verify_build

ROOT = Path(__file__).resolve().parents[1]
BEND = Path('/Users/chuah/.bend/bin/bend')
ENTRY = ROOT / 'tests/player_cooking_wire.bend'
WORK = ROOT / 'build/player-cooking-wire/001'
BINARY = WORK / 'receiver'
BUILD = WORK / 'native-build.json'
REFERENCE = ROOT / 'reference/item_component.json'
EVIDENCE = ROOT / 'evidence/player-cooking-wire-native.json'
NAT_MAX = (1 << 48) - 1
U32_MAX = (1 << 32) - 1
EPOCH = 'cooking-wire'
POSITION = ['minecraft:the_end', U32_MAX, 1 << 31, U32_MAX - 1]
TIMERS = [U32_MAX, 1 << 31, U32_MAX - 1, (1 << 31) - 1]
MESSAGE = 'refused "quoted" \\ path α'
COMPONENT_HEADER = 'BendCraftComponents1\t1\t'
# Independent literal lengths for the retained default map plus1200 ordered
# saturation/duration0 effects. No per-key fixture size becomes a product cap.
LARGE_LENGTHS = dict(component_payload_codepoints=52257, component_key_codepoints=52280,
    quoted_key_ascii_bytes=59538, single_reply_ascii_bytes=60082,
    full_reply_ascii_bytes=299540, single_raw_json_codepoints=60077, single_raw_json_utf8_bytes=60078)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def compact(value):
    return json.dumps(value, ensure_ascii=True, separators=(',', ':'))


def identity_literal(effective, limit=1):
    # Fixture assembly with an explicit envelope limit, not host admission.
    return 'BendCraftComponents1\t' + str(limit) + '\t' + canonical(effective).decode()


def slot(identifier, count=1, components=''):
    return [1, identifier, components, count]


def menu(components):
    main = [slot('minecraft:stone', index + 1) for index in range(36)]
    main[7] = slot('minecraft:suspicious_stew', components=components)
    equipment = [slot(name) for name in (
        'minecraft:diamond_boots', 'minecraft:diamond_leggings',
        'minecraft:diamond_chestplate', 'minecraft:diamond_helmet',
        'minecraft:shield', 'minecraft:wolf_armor', 'minecraft:saddle')]
    craft = [slot('minecraft:diamond'), slot('minecraft:stone', 2),
             slot('minecraft:suspicious_stew', components=components),
             slot('minecraft:oak_planks', 4)]
    carried = slot('minecraft:suspicious_stew', components=components)
    return [[8, True, False, main], equipment,
            [True, False, True, 2147483648, 2143289345], craft,
            carried, [1, copy.deepcopy(carried)], True, NAT_MAX]


def empty_menu():
    return [[0, False, True, [[0] for _ in range(36)]],
            [[0] for _ in range(7)], [False, False, False, 1036831949, 1028443341],
            [[0] for _ in range(4)], [0], [0], False, 0]


def cooking_reply(components, family=0, *, closed=False, unavailable=False):
    block = ['minecraft:furnace', 'minecraft:blast_furnace', 'minecraft:smoker'][family]
    handle = [0] if closed else [1, 23, 7, copy.deepcopy(POSITION), block, family, NAT_MAX]
    body = [0] if closed or unavailable else [
        1, family, slot('minecraft:iron_ore', 64), slot('minecraft:coal', 17),
        slot('minecraft:suspicious_stew', components=components), *TIMERS]
    return [1, 8, EPOCH, NAT_MAX, False, MESSAGE, [handle, body, menu(components)]]


def observed_slot(value):
    return None if value == [0] else dict(id=value[1], components=value[2], count=value[3])


def observed_inventory(i):
    m, equipment, status, craft, carried, result, opened, revision = i
    return dict(selected=m[0], abilities=m[1:3], main=[observed_slot(v) for v in m[3]],
        equipment=[observed_slot(v) for v in equipment], status=status,
        craft=[observed_slot(v) for v in craft], carried=observed_slot(carried),
        result=None if result == [0] else observed_slot(result[1]), opened=opened, revision=revision)


def observed_reply(packet):
    # Interpret the explicit fixture positions only; this is not a validator.
    tag = packet[1]
    if tag != 8:
        result = dict(tag=tag, epoch=packet[2], sequence=packet[3])
        if tag == 3:
            result['message'] = packet[4]
        elif tag == 4:
            m = packet[4]
            result['snapshot'] = dict(selected=m[0], abilities=m[1:3], slots=[observed_slot(v) for v in m[3]])
        elif tag == 5:
            result.update(changed=packet[4], message=packet[5])
        elif tag == 6:
            result.update(accepted=packet[4], message=packet[5], inventory=observed_inventory(packet[6]))
        return result
    h, f, i = packet[6]
    handle = None if h == [0] else dict(menu=h[1], peer=h[2], position=h[3],
        block=h[4], kind=h[5], incarnation=h[6])
    furnace = None if f == [0] else dict(kind=f[1], slots=[observed_slot(v) for v in f[2:5]], timers=f[5:9])
    return dict(epoch=packet[2], sequence=packet[3], accepted=packet[4], message=packet[5],
                handle=handle, furnace=furnace, inventory=observed_inventory(i))


def observed_request(packet):
    if packet[1] == 0:
        return dict(capability=packet[2])
    return dict(epoch=packet[2], sequence=packet[3], command=packet[4])


def replace(value, path, replacement):
    result = copy.deepcopy(value)
    at = result
    for index in path[:-1]:
        at = at[index]
    at[path[-1]] = replacement
    return result


class Corpus:
    def __init__(self):
        self.inputs = []
        self.expected = []

    def add(self, name, mode, packet=None, accepted=True, scope='wire-contract', **fields):
        require(name not in {row['id'] for row in self.inputs}, 'duplicate case: ' + name)
        incoming = dict(id=name, mode=mode, **fields)
        if mode.startswith('decode_'):
            incoming['text'] = compact(packet)
        expectation = dict(id=name, mode=mode, accepted=accepted, scope=scope)
        if accepted:
            require(packet is not None, name + ': missing independent packet')
            expectation['text'] = compact(packet)
            expectation['observed'] = observed_reply(packet) if mode.endswith('reply') else observed_request(packet)
        self.inputs.append(incoming)
        self.expected.append(expectation)

    def raw(self, name, mode, text):
        self.add(name, mode, accepted=False)
        self.inputs[-1]['text'] = text


def profiles():
    reference = json.loads(REFERENCE.read_text())
    require(reference['pin'] == '26.3', 'component reference version changed')
    require(hashlib.sha256(canonical(reference['default_components'])).hexdigest() ==
            reference['default_components_sha256'], 'retained default component digest changed')
    rows = reference['rows'][:17]
    require(len(rows) == 17 and all(row['accepted'] and row['count'] == 1 for row in rows),
            'retained primary recipe profiles changed')
    return [(row['id'], COMPONENT_HEADER + canonical(row['components']).decode()) for row in rows]


def corpus():
    data = Corpus()
    primary = profiles()
    components = primary[0][1]
    call = lambda command: [1, 1, EPOCH, NAT_MAX, command]
    # Keep the new corpus independent of the old full dispatcher. These exact
    # packets exercise every old command tag and representative default replies.
    data.add('legacy-hello', 'decode_request', [1, 0, 'legacy-capability'])
    old_commands = [[0, 16, 16], [1, [True, False, []]], [2], [3, 1], [4, 8], [5],
        [6, 0, 1, 3, 0], [7, 0, ['minecraft:stone', ''], 4], [8], [9], [10],
        [11, 43, [0, 1]], [12, 8], [13, 16, 16]]
    for command in old_commands:
        data.add('legacy-command-' + str(command[0]), 'decode_request', call(command))
    for name, packet in (
        ('hello-ack', [1, 0, EPOCH, 0]), ('ack', [1, 2, EPOCH, 1]),
        ('fault', [1, 3, EPOCH, 1, 'legacy fault']),
        ('inventory-default', [1, 4, EPOCH, 1, empty_menu()[0]]),
        ('action', [1, 5, EPOCH, 1, True, 'legacy action']),
        ('menu-default', [1, 6, EPOCH, 1, False, 'legacy menu', empty_menu()])):
        data.add('legacy-reply-' + name, 'decode_reply', packet)
    commands = [
        ('open', [14, copy.deepcopy(POSITION)], {}),
        ('inspect-zero', [15, 0], dict(variant='inspect', menu=0)),
        ('inspect-max', [15, U32_MAX], dict(variant='inspect', menu=U32_MAX)),
        ('click-first-left', [16, 23, 0, 0], dict(variant='click', index=0, button=0)),
        ('click-last-right', [16, 23, 38, 1], dict(variant='click', index=38, button=1)),
        ('quick-first', [17, 23, 0], dict(variant='quick_move', index=0)),
        ('quick-last', [17, 23, 38], dict(variant='quick_move', index=38)),
        ('close', [18, 23], {}),
        ('use-main', [19, False], dict(variant='use_main')),
        ('use-offhand', [19, True], dict(variant='use_offhand')),
    ]
    for name, command, overrides in commands:
        fields = dict(variant=name, menu=23, index=0, button=0)
        fields.update(overrides)
        data.add(name + '/decode', 'decode_request', call(command))
        data.add(name + '/encode', 'encode_request', call(command), **fields)
    # Every new command has its own exact cardinality and closed tag.
    for tag, command in {command[0]: command for _, command, _ in commands}.items():
        data.add('command-short-' + str(tag), 'decode_request', call(command[:-1]), accepted=False)
        data.add('command-long-' + str(tag), 'decode_request', call(command + [0]), accepted=False)
    for name, command in (
        ('unknown-command', [20]), ('open-unknown-dimension', [14, ['fixture:unknown', 0, 0, 0]]),
        ('open-short-position', [14, POSITION[:-1]]), ('open-long-position', [14, POSITION + [0]]),
        ('open-negative-number', [14, ['minecraft:the_end', -1, 0, 0]]),
        ('open-u32-overflow', [14, ['minecraft:the_end', U32_MAX + 1, 0, 0]]),
        ('inspect-u32-overflow', [15, U32_MAX + 1]), ('click-menu-zero', [16, 0, 0, 0]),
        ('click-index39', [16, 23, 39, 0]), ('click-button2', [16, 23, 0, 2]),
        ('quick-menu-zero', [17, 0, 0]), ('quick-index39', [17, 23, 39]),
        ('close-menu-zero', [18, 0]), ('use-numeric', [19, 1]), ('use-null', [19, None])):
        data.add(name, 'decode_request', call(command), accepted=False)
    for name, fields in (
        ('typed-open-unknown-dimension', dict(variant='unknown_dimension')),
        ('typed-click-menu-zero', dict(variant='click', menu=0)),
        ('typed-click-index39', dict(variant='click', index=39)),
        ('typed-click-button2', dict(variant='click', button=2)),
        ('typed-quick-menu-zero', dict(variant='quick_move', menu=0)),
        ('typed-quick-index39', dict(variant='quick_move', index=39)),
        ('typed-close-menu-zero', dict(variant='close', menu=0))):
        values = dict(menu=23, index=0, button=0)
        values.update(fields)
        data.add(name, 'encode_request', accepted=False, **values)
    for name, packet in (
        ('v2-request', replace(call([15, 0]), [0], 2)),
        ('zero-sequence', replace(call([15, 0]), [3], 0)),
        ('sequence-overflow', replace(call([15, 0]), [3], NAT_MAX + 1)),
        ('request-short-header', call([15, 0])[:-1]),
        ('request-long-header', call([15, 0]) + [0])):
        data.add(name, 'decode_request', packet, accepted=False)
    data.raw('fractional-command', 'decode_request', '[1,1,"cooking-wire",1,[16,23,0,1.0]]')

    for family, variant in enumerate(('smelting', 'blasting', 'smoking')):
        packet = cooking_reply(components, family)
        data.add(variant + '/decode', 'decode_reply', packet)
        data.add(variant + '/encode', 'encode_reply', packet, variant=variant, components=components)
    for variant, fields in (('closed', dict(closed=True)), ('unavailable', dict(unavailable=True))):
        packet = cooking_reply(components, **fields)
        data.add(variant + '/decode', 'decode_reply', packet)
        data.add(variant + '/encode', 'encode_reply', packet, variant=variant, components=components)
    # Empty/default DTOs are accepted independently of the richer full fixture.
    default = [1, 8, EPOCH, 1, True, '', [[0], [0], empty_menu()]]
    data.add('empty-default-reply', 'decode_reply', default)
    for identifier, profile in primary:
        packet = cooking_reply(profile)
        data.add(identifier + '/decode', 'decode_reply', packet)
        data.add(identifier + '/encode', 'encode_reply', packet, variant='smelting', components=profile)
    base = cooking_reply(components)
    data.add('peer-zero-observation', 'decode_reply', replace(base, [6, 0, 2], 0))
    data.add('incarnation-zero-observation', 'decode_reply', replace(base, [6, 0, 6], 0))
    data.add('empty-result-observation', 'decode_reply', replace(base, [6, 2, 5], [1, [0]]))
    data.add('no-result-observation', 'decode_reply', replace(base, [6, 2, 5], [0]))

    for name, path, value in (
        ('unknown-handle-tag', [6, 0, 0], 2), ('unknown-kind', [6, 0, 5], 9),
        ('campfire-handle-kind', [6, 0, 5], 3), ('block-kind-mismatch', [6, 0, 4], 'minecraft:smoker'),
        ('handle-menu-zero', [6, 0, 1], 0), ('handle-menu-overflow', [6, 0, 1], U32_MAX + 1),
        ('unknown-dimension', [6, 0, 3, 0], 'fixture:unknown'),
        ('incarnation-overflow', [6, 0, 6], NAT_MAX + 1), ('incarnation-negative', [6, 0, 6], -1),
        ('furnace-unknown-tag', [6, 1, 0], 2), ('furnace-unknown-kind', [6, 1, 1], 9),
        ('furnace-campfire-kind', [6, 1, 1], 3), ('furnace-kind-mismatch', [6, 1, 1], 2),
        ('closed-with-furnace', [6, 0], [0]), ('invalid-selected', [6, 2, 0, 0], 9),
        ('invalid-ability', [6, 2, 0, 1], 1), ('invalid-status-flag', [6, 2, 2, 0], 1),
        ('result-unknown-tag', [6, 2, 5], [2]), ('result-short', [6, 2, 5], [1]),
        ('result-long', [6, 2, 5], [0, [0]]), ('invalid-opened', [6, 2, 6], 1),
        ('revision-overflow', [6, 2, 7], NAT_MAX + 1), ('v2-reply', [0], 2),
        ('unknown-reply-tag', [1], 9), ('reply-invalid-accepted', [4], 1)):
        data.add(name, 'decode_reply', replace(base, path, value), accepted=False)
    for name, path in (
        ('reply', []), ('snapshot', [6]), ('handle', [6, 0]), ('position', [6, 0, 3]),
        ('furnace', [6, 1]), ('inventory', [6, 2]), ('main', [6, 2, 0]),
        ('status', [6, 2, 2]), ('main-slots', [6, 2, 0, 3]),
        ('equipment-slots', [6, 2, 1]), ('craft-slots', [6, 2, 3])):
        value = base
        for index in path:
            value = value[index]
        for suffix, changed in (('short', value[:-1]), ('long', value + [0])):
            packet = replace(base, path, changed) if path else changed
            data.add(name + '-' + suffix, 'decode_reply', packet, accepted=False)
    for index in range(5, 9):
        for suffix, value in (('negative', -1), ('overflow', U32_MAX + 1), ('bool', True)):
            data.add('timer-' + str(index - 5) + '-' + suffix, 'decode_reply',
                     replace(base, [6, 1, index], value), accepted=False)
    # Wire admission authenticates canonical structure and implemented mutable
    # codecs, rather than the initialized item's complete default component map.
    # Indices43 and46 are the first/last crafting fields.
    paths = {'main': [6, 2, 0, 3, 7], 'equipment': [6, 2, 1, 6],
             'craft43': [6, 2, 3, 0], 'craft46': [6, 2, 3, 3],
             'carried': [6, 2, 4], 'result': [6, 2, 5, 1],
             'furnace-input': [6, 1, 2], 'furnace-fuel': [6, 1, 3], 'furnace-output': [6, 1, 4]}
    unknown_effect = copy.deepcopy(json.loads(components[len(COMPONENT_HEADER):]))
    unknown_effect['minecraft:suspicious_stew_effects'][0]['id'] = 'fixture:unknown_effect'
    unknown = COMPONENT_HEADER + canonical(unknown_effect).decode()
    unknown_component = copy.deepcopy(json.loads(components[len(COMPONENT_HEADER):]))
    unknown_component['fixture:unknown_component'] = {}
    unknown_component = COMPONENT_HEADER + canonical(unknown_component).decode()
    for name, path in paths.items():
        for suffix, value in (
            ('unknown-components', slot('minecraft:suspicious_stew', components=unknown)),
            ('unknown-component-key', slot('minecraft:suspicious_stew', components=unknown_component)),
            ('opaque-components', slot('minecraft:stone', components='opaque prior')),
            ('modified-count2', slot('minecraft:suspicious_stew', 2, components)),
            ('zero-count', slot('minecraft:stone', 0)),
            ('long-empty', [0, 0]), ('short-stack', [1, 'minecraft:stone', '']),
            ('long-stack', [1, 'minecraft:stone', '', 1, 0])):
            data.add(name + '/' + suffix, 'decode_reply', replace(base, path, value), accepted=False)
        data.add(name + '/provisional-empty-effective-map', 'decode_reply',
                 replace(base, path, slot('minecraft:suspicious_stew', components=COMPONENT_HEADER + '{}')),
                 scope='structural-provisional')

    # These canonical DTOs are structurally admitted. Initialized D.metadata
    # must separately authenticate them through Components.authenticated using
    # the actual item's defaults;
    # this corpus neither executes nor predicts that separate authority result.
    removed_immutable = copy.deepcopy(json.loads(components[len(COMPONENT_HEADER):]))
    del removed_immutable['minecraft:food']
    changed_immutable = copy.deepcopy(json.loads(components[len(COMPONENT_HEADER):]))
    changed_immutable['minecraft:item_model'] = 'fixture:changed_model'
    removed_mutable = copy.deepcopy(json.loads(components[len(COMPONENT_HEADER):]))
    del removed_mutable['minecraft:suspicious_stew_effects']
    for name, value in (
        ('immutable-removed', slot('minecraft:suspicious_stew', components=identity_literal(removed_immutable))),
        ('immutable-changed', slot('minecraft:suspicious_stew', components=identity_literal(changed_immutable))),
        ('mutable-removed', slot('minecraft:suspicious_stew', components=identity_literal(removed_mutable))),
        ('damageable', slot('minecraft:diamond_sword', components=identity_literal({
            'minecraft:damage': 7, 'minecraft:max_damage': 32, 'minecraft:max_stack_size': 1}))),
        ('effective-stack64', slot('minecraft:stone', 64, identity_literal({'minecraft:max_stack_size': 64}, 64)))):
        data.add('provisional-' + name, 'decode_reply', replace(base, [6, 2, 4], value),
                 scope='structural-provisional')
    data.add('effective-stack64-count65', 'decode_reply', replace(base, [6, 2, 4],
             slot('minecraft:stone', 65, identity_literal({'minecraft:max_stack_size': 64}, 64))), accepted=False)
    data.add('typed-provisional-empty-effective-map', 'encode_reply', cooking_reply(COMPONENT_HEADER + '{}'),
             variant='smelting', components=COMPONENT_HEADER + '{}', scope='structural-provisional')

    # Every refusal below follows canonical structure or one of the implemented
    # mutable codecs. No immutable-default equality is imposed by the host.
    malformed_identities = (
        ('marker-version', 'BendCraftComponents2\t1\t{}'),
        ('envelope-wrong-limit', 'BendCraftComponents1\t2\t{}'),
        ('envelope-leading-zero', 'BendCraftComponents1\t01\t{}'),
        ('envelope-extra-field', COMPONENT_HEADER + '{}\textra'),
        ('envelope-body-whitespace', COMPONENT_HEADER + ' {}'),
        ('effective-not-object', COMPONENT_HEADER + '[]'),
        ('effective-unsorted-names', COMPONENT_HEADER + '{"minecraft:max_stack_size":1,"minecraft:damage":0}'),
        ('effective-duplicate-name', COMPONENT_HEADER + '{"minecraft:damage":0,"minecraft:damage":1}'),
        ('effective-malformed-json', COMPONENT_HEADER + '{'),
        ('damage-negative-zero-lexeme', COMPONENT_HEADER + '{"minecraft:damage":-0}'),
        ('damage-exponent-lexeme', COMPONENT_HEADER + '{"minecraft:damage":1e0}'))
    for name, invalid in malformed_identities:
        data.add(name, 'decode_reply', replace(base, [6, 2, 4],
                 slot('minecraft:diamond_sword', components=invalid)), accepted=False)
    mutable_refusals = (
        ('damage-string', {'minecraft:damage': '7'}, 1),
        ('damage-negative', {'minecraft:damage': -1}, 1),
        ('damage-above-signed-max', {'minecraft:damage': 2147483648}, 1),
        ('damage-fractional-lexeme', {'minecraft:damage': 1.0}, 1),
        ('repair-cost-negative', {'minecraft:repair_cost': -1}, 1),
        ('max-damage-zero', {'minecraft:max_damage': 0}, 1),
        ('max-damage-negative', {'minecraft:max_damage': -1}, 1),
        ('max-damage-above-signed-max', {'minecraft:max_damage': 2147483648}, 1),
        ('max-damage-fractional-lexeme', {'minecraft:max_damage': 1.0}, 1),
        ('max-damage-string', {'minecraft:max_damage': '32'}, 1),
        ('max-stack-zero', {'minecraft:max_stack_size': 0}, 0),
        ('max-stack100', {'minecraft:max_stack_size': 100}, 100),
        ('max-stack-fractional-lexeme', {'minecraft:max_stack_size': 1.0}, 1),
        ('max-stack-string', {'minecraft:max_stack_size': '1'}, 1),
        ('unbreakable-boolean', {'minecraft:unbreakable': True}, 1),
        ('unbreakable-nonempty', {'minecraft:unbreakable': {'show_in_tooltip': True}}, 1),
        ('glint-nonboolean', {'minecraft:enchantment_glint_override': 1}, 1),
        ('effects-not-array', {'minecraft:suspicious_stew_effects': {}}, 1),
        ('effect-missing-id', {'minecraft:suspicious_stew_effects': [{}]}, 1),
        ('effect-fractional-duration', {'minecraft:suspicious_stew_effects': [
            {'duration': 1.5, 'id': 'minecraft:speed'}]}, 1),
        ('effect-noncanonical-default-duration', {'minecraft:suspicious_stew_effects': [
            {'duration': 160, 'id': 'minecraft:speed'}]}, 1),
        ('damageable-effective-stack2', {'minecraft:max_damage': 32, 'minecraft:max_stack_size': 2}, 2))
    for name, effective, limit in mutable_refusals:
        data.add(name, 'decode_reply', replace(base, [6, 2, 4],
                 slot('minecraft:diamond_sword', components=identity_literal(effective, limit))), accepted=False)
    for variant in ('campfire', 'wrong_block', 'menu_zero', 'unknown_dimension',
                    'kind_mismatch', 'closed_with_furnace',
                    'short_main', 'long_main', 'short_equipment', 'long_equipment',
                    'short_craft', 'long_craft'):
        data.add('typed-' + variant, 'encode_reply', accepted=False, variant=variant, components=components)
    for name, invalid in (('unknown-components', unknown), ('unknown-component-key', unknown_component),
                          ('malformed-components', components[:-1])):
        data.add('typed-' + name, 'encode_reply', accepted=False, variant='smelting', components=invalid)
    large_effective = copy.deepcopy(json.loads(REFERENCE.read_text())['default_components'])
    large_effective['minecraft:suspicious_stew_effects'] = [
        dict(duration=0, id='minecraft:saturation') for _ in range(1200)]
    large = identity_literal(large_effective)
    full_large = cooking_reply(large)
    single_large = replace(full_large, [6, 2], empty_menu())
    single_large = replace(single_large, [6, 1, 2], [0])
    single_large = replace(single_large, [6, 1, 3], [0])
    raw_single = json.dumps(single_large, ensure_ascii=False, separators=(',', ':'))
    require(len(large[len(COMPONENT_HEADER):]) == LARGE_LENGTHS['component_payload_codepoints'] and
            len(large) == LARGE_LENGTHS['component_key_codepoints'] and
            len(compact(large).encode('ascii')) == LARGE_LENGTHS['quoted_key_ascii_bytes'],
            'large key independent literal lengths changed')
    require(len(compact(single_large).encode('ascii')) == LARGE_LENGTHS['single_reply_ascii_bytes'] and
            len(compact(full_large).encode('ascii')) == LARGE_LENGTHS['full_reply_ascii_bytes'] and
            len(raw_single) == LARGE_LENGTHS['single_raw_json_codepoints'] and
            len(raw_single.encode('utf-8')) == LARGE_LENGTHS['single_raw_json_utf8_bytes'],
            'whole CookingReply independent literal lengths changed')
    data.add('large-single/decode', 'decode_reply', single_large, scope='wire-budget')
    data.add('large-single/encode', 'encode_reply', single_large, variant='single_large', components=large,
             scope='wire-budget')
    data.add('large-full/decode', 'decode_reply', full_large, accepted=False, scope='wire-budget')
    data.add('large-full/encode', 'encode_reply', accepted=False, variant='smelting', components=large,
             scope='wire-budget')
    # A shorter Unicode JSON string still violates this private wire's ASCII
    # input contract. Valid encoder output instead contains the six ASCII bytes
    # for the escaped Greek scalar, already included in the60082-byte literal.
    data.raw('large-single/non-ascii-raw-input', 'decode_reply', raw_single)
    data.raw('malformed-reply-json', 'decode_reply', compact(base)[:-1])
    data.raw('fractional-furnace-kind', 'decode_reply', compact(base).replace(
        '[1,0,[1,"minecraft:iron_ore"', '[1,0.0,[1,"minecraft:iron_ore"', 1))
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
        if expected['mode'].startswith('encode_'):
            admission = result['encoded']
        else:
            admission = result
        require(admission['accepted'] == expected['accepted'], dict(case=expected['id'], result=result))
        if not expected['accepted']:
            require(isinstance(admission.get('error'), str) and admission['error'],
                    'refusal omitted diagnostic: ' + expected['id'])
            continue
        decoded = result['decoded'] if expected['mode'].startswith('encode_') else result
        require(decoded['accepted'], dict(case=expected['id'], result=result))
        require(decoded['observed'] == expected['observed'],
                dict(case=expected['id'], observed=decoded['observed'], expected=expected['observed']))
        require(decoded['encoded'] == dict(accepted=True, text=expected['text']),
                dict(case=expected['id'], encoded=decoded['encoded'], expected=expected['text']))
        if expected['mode'].startswith('encode_'):
            require(admission == dict(accepted=True, text=expected['text']),
                    dict(case=expected['id'], encoded=admission, expected=expected['text']))
    return actual


def pins():
    result = imports([ENTRY])
    for path in (Path(__file__).resolve(), REFERENCE, ROOT / 'tools/build_native.py',
                 ROOT / 'tools/test_player_block_inside_stuck.py', ROOT / 'tools/test_player_look.py',
                 ROOT / 'tools/reference_inventory.py'):
        result[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def unchanged(source_pins):
    require(all(hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest
                for name, digest in source_pins.items()), 'cooking wire input/source changed during run')


def run(phase, folder, binary, build_report):
    data = prepare(folder)
    source_pins = pins()
    prepared = dict(status='prepared', cases=len(data.inputs),
                    accepted=sum(row['accepted'] for row in data.expected),
                    refused=sum(not row['accepted'] for row in data.expected),
                    structurally_provisional=sum(row['scope'] == 'structural-provisional' for row in data.expected))
    if phase == 'prepare':
        print(json.dumps(prepared))
        return
    checks = []
    if phase in ('source', 'all'):
        _, receipt = checked_run([BEND, ENTRY, '--check-only'], folder, 'source', 120)
        checks.append(receipt)
        unchanged(source_pins)
    if phase == 'source':
        print(json.dumps(dict(status='source-checked', checks=checks, **{k: v for k, v in prepared.items() if k != 'status'})))
        return
    if phase in ('build', 'all'):
        _, receipt = checked_run([sys.executable, ROOT / 'tools/build_native.py', ENTRY,
            '-o', binary, '--bend', BEND, '--report', build_report], folder, 'build', 900)
        checks.append(receipt)
        unchanged(source_pins)
    report = json.loads(build_report.read_text())
    artifact = verify_build(report)
    require(fingerprint(binary)['sha256'] == report['binary_sha256'], 'requested binary differs from verified artifact')
    require(any(Path(item['path']) == ENTRY.resolve() for item in report['dependencies']),
            'native report does not contain this actual observer')
    # Report dependencies pin Base, transitive Bend sources, foreign effects,
    # compiler and toolchain. Revalidate the same compiled inputs after replay.
    build_pin = fingerprint(build_report)
    if phase == 'build':
        print(json.dumps(dict(status='built', native_build=build_pin, **{k: v for k, v in prepared.items() if k != 'status'})))
        return
    stdout, native = checked_run([artifact, '--gpu', 'off', '--threads', '1', folder / 'input.json'],
                                 folder, 'native', 180)
    actual = compare(data, stdout)
    unchanged(source_pins)
    verify_build(report)
    require(fingerprint(build_report) == build_pin, 'native build receipt changed during replay')
    require(fingerprint(binary)['sha256'] == report['binary_sha256'], 'published binary changed during replay')
    evidence = dict(status='passed', cases=len(actual), accepted=prepared['accepted'], refused=prepared['refused'],
        structurally_provisional=prepared['structurally_provisional'],
        whole_cooking_reply_budget_literals=LARGE_LENGTHS,
        native=native, checks=checks, native_build=build_pin, compiled_artifact=fingerprint(artifact),
        source_sha256=source_pins, input=fingerprint(folder / 'input.json'), expected=fingerprint(folder / 'expected.json'),
        reference=fingerprint(REFERENCE),
        boundary='Actual W.decode_request/decode_reply and W.encode_request/encode_reply, independently literal new tags14-19/reply8 and full typed MenuSnapshot, plus literal old command/default reply records and v2 refusals. Raw U32 coordinate/timer/status words retained. Canonical empty maps, valid removals/immutable changes and mutable metadata cases labelled structural-provisional require separate initialized catalogue metadata authority, which this corpus does not execute or predict. Canonical envelope/registered-name/implemented mutable codec/count/max_damage refusals remain strict. One1200-effect key admits in a60082-byte CookingReply while five copies refuse at299540 ASCII bytes; raw non-ASCII input refuses despite fewer codepoints. This establishes only DTO aggregate-budget behavior, not two-owner rollback. Nat48 overflow is supplied as JSON text only; abstract typed values beyond native Nat48 are unrepresentable. No old full dispatcher or framing suite is invoked. No cooking simulation, full affine owner, backend authority, socket, OS presentation or Java GUI verdict is inferred.')
    EVIDENCE.parent.mkdir(parents=True, exist_ok=True)
    write_json(EVIDENCE, evidence)
    print(json.dumps(dict(status='passed', cases=len(actual), accepted=prepared['accepted'], refused=prepared['refused'])))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase', choices=('prepare', 'source', 'build', 'native', 'all'), default='prepare')
    parser.add_argument('--work', type=Path, default=WORK)
    parser.add_argument('--binary', type=Path, default=BINARY)
    parser.add_argument('--build-report', type=Path, default=BUILD)
    args = parser.parse_args()
    run(args.phase, args.work.resolve(), args.binary.resolve(), args.build_report.resolve())


if __name__ == '__main__':
    main()
