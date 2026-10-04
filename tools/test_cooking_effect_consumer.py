#!/usr/bin/env python3
"""Actual entity/clock facade fixtures; caller supplies the bounded executor.

No process launch, build or game implementation occurs in this helper. Complete
owner/pending NBT is independently constructed with the existing physical codec
fixtures. Two installed-Java receiver rows supply the empty-drop RNG advance
and the seeded single-item constructor fields. Live Core geometry is not mocked:
the focused callback refuses unavailable new-orb placement explicitly.
"""
from __future__ import annotations

import copy
import hashlib
import json
import time
from pathlib import Path

import test_nbt as N
import test_cooking_effect_recovery as Recovery
import test_local_player_effect_entities_codec as Codec

ROOT = Path(__file__).resolve().parents[1]
ENTRY = ROOT / 'tests/cooking_effect_consumer.bend'
FIRST_CLOCK = [1333781, 1777858490]
CLOCKS = [FIRST_CLOCK, [111, 222], [333, 444]]
LAWS = ['empty_delivery_retains_complete_entity_owner_and_clock_inputs',
        'zero_clock_budget_returns_complete_actual_delivery',
        'publisher_refusal_retains_complete_committed_prefix_and_entropy',
        'completed_delivery_retains_all_unused_constructor_clocks']


def source(value):
    if value['kind'] == 'legacy':
        return Codec.random_source(0, *value['seed'])
    return Codec.random_source(1, *value['low'], *value['high'])


def java_item(value):
    """Observed constructor words plus explicitly neutral internal caches."""
    c = value['common']
    vector = lambda key: Codec.array(*(v for pair in c[key] for v in pair))
    zero = Codec.array(0, 0, 0, 0, 0, 0)
    fields = Codec.compound(
        position=vector('position'), velocity=vector('velocity'), position_o=vector('position_o'),
        position_old=zero, look=Codec.array(c['yaw'], c['pitch'], c['yaw_o'], c['pitch_o']),
        head_yaw=Codec.integer(0), body_yaw=Codec.integer(0), fall_distance=Codec.array(0, 0),
        on_ground=Codec.integer(c['on_ground']), air=Codec.integer(c['air']), fire=Codec.integer(c['fire']),
        portal_cooldown=Codec.integer(c['portal_cooldown']), invulnerable=Codec.integer(c['invulnerable']),
        needs_sync=Codec.integer(c['needs_sync']))
    common = Codec.compound(
        dimension=Codec.string_words(c['dimension']), id=Codec.integer(c['id']),
        uuid_most=Codec.array(*c['uuid_most']), uuid_least=Codec.array(*c['uuid_least']),
        random=source(c['random']), fields=fields, tick_count=Codec.integer(c['tick_count']),
        first_tick=Codec.integer(c['first_tick']), removed=Codec.integer(c['removed']),
        accessible=Codec.integer(c['accessible']), section_order=Codec.string_words(str(c['section_order'])))
    item = Codec.compound(id=Codec.string_words(value['item']['id']),
                          components=Codec.string_words(''), count=Codec.integer(value['item']['count']))
    payload = Codec.compound(
        item=item, age=Codec.integer(value['age']), pickup_delay=Codec.integer(value['pickup_delay']),
        health=Codec.integer(value['health']), thrower=Codec.array(), target=Codec.array(),
        bob=Codec.integer(value['bob']))
    return Codec.compound(kind=Codec.integer(0), common=common, payload=payload)


def effect(kind, payload=None):
    value = Recovery.effect(kind, payload)
    return Recovery.replace_field(value, 'position', Recovery.compound(
        dimension=Recovery.string_words('minecraft:overworld'),
        x=Recovery.integer(0xfffffff9), y=Recovery.integer(65), z=Recovery.integer(3)))


def drop(count=None, slot=0):
    item = Recovery.compound() if count is None else Recovery.compound(
        id=Recovery.string_words('minecraft:stone'), components=Recovery.string_words(''),
        count=Recovery.integer(count))
    return effect(1, Recovery.compound(slot=Recovery.integer(slot), item=item))


def pin(path):
    path = Path(path)
    data = path.read_bytes()
    return {'path': str(path.resolve()), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


def prepare(directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    reference_path = ROOT / 'reference/cooking_effect_entities.json'
    reference = json.loads(reference_path.read_text())
    assert reference['pin'] == '26.3'
    rows = {row['id']: row for row in reference['observations']['cases']}
    empty, single = rows['legacy-empty'], rows['legacy-single']
    assert empty['level_before'] == single['level_before'] and single['times'] == [FIRST_CLOCK]
    assert single['records'][0]['item']['count'] == 1
    assert single['records'][0]['item']['components']['minecraft:max_stack_size'] == 64
    owner = Codec.root()
    root = owner.value
    for name, value in [('level_random', source(empty['level_before'])),
                        ('seed_uniquifier', Codec.array(*single['unique_before'])),
                        ('last_id', Codec.integer(0)), ('next_section_order', Codec.string_words('0'))]:
        root = Codec.replace_at(root, [name], value)
    owner = N.RootTag(owner.name, root)
    after_empty = N.RootTag(owner.name, Codec.replace_at(root, ['level_random'], source(empty['level_after'])))
    after_single = root
    for name, value in [('level_random', source(single['level_after'])),
                        ('seed_uniquifier', Codec.array(*single['unique_after'])),
                        ('last_id', Codec.integer(single['cursor_after'])),
                        ('next_section_order', Codec.string_words('1'))]:
        after_single = Codec.replace_at(after_single, [name], value)
    records = Codec.at(root, ['records']).payload[1]
    after_single = N.RootTag(owner.name, Codec.replace_at(after_single, ['records'],
        N.Value(9, (10, (*records, java_item(single['records'][0]))))))
    blocked = [effect(3), effect(0), drop()]
    dirty = 'refused:cooking-entities:block-entity-and-comparator-publisher-required'
    xp = effect(2, Recovery.compound(recipe=Recovery.string_words('minecraft:cooked_beef'),
        uses=Recovery.integer(1), experience_bits=Recovery.integer(0x3f800000)))
    cases = [
        ('empty-pure', 'done', owner, [], CLOCKS),
        ('acknowledged-prefix', 'done', owner, [], CLOCKS),
        ('dirty-retains-owner', dirty, owner, blocked, CLOCKS),
        ('empty-prefix-blocked', dirty, after_empty, blocked, CLOCKS),
        ('empty-drop-io', 'done', after_empty, [], CLOCKS),
        ('zero-budget-required-clock', 'entropy:1', owner, [drop(1, 1), *blocked], []),
        ('zero-budget-prefix', 'entropy:1', after_empty, [drop(1, 1), *blocked], []),
        ('clock-budget-refusal', 'entropy:1', owner, [drop(64, 1), *blocked], None),
        ('supplied-clock-item-prefix', dirty, after_single, blocked, CLOCKS[1:]),
        ('unavailable-xp-placement', 'refused:actual-world-orb-placement-unavailable', owner, [xp, *blocked], CLOCKS),
    ]
    path = directory / 'owner.nbt'
    path.write_bytes(N.encode_root(owner))
    expectations = [{'label': label, 'status': status, 'owner': N.encode_root(state),
                     'pending': N.encode_root(Recovery.root(pending)), 'clocks': copy.deepcopy(clocks)}
                    for label, status, state, pending, clocks in cases]
    for row in expectations:
        (directory / (row['label'] + '.owner.nbt')).write_bytes(row['owner'])
        (directory / (row['label'] + '.pending.nbt')).write_bytes(row['pending'])
    return {'input': pin(path), 'reference': pin(reference_path), 'expectations': expectations,
            'scope': 'Complete raw owner/queue/clock facade retention; two actual Java receiver rows. '
                     'Single plain-stone authority fixture and refused actual-world newOrb placement. '
                     'Neutral internal constructor caches are explicit fixture policy; no whole entity/world parity claim.'}


def suite(executor, directory):
    prepared = prepare(directory)
    before = time.clock_gettime_ns(time.CLOCK_MONOTONIC)
    stdout, process = executor('cooking-effect-consumer', [prepared['input']['path']])
    after = time.clock_gettime_ns(time.CLOCK_MONOTONIC)
    actual = stdout.decode() if isinstance(stdout, bytes) else stdout
    lines = actual.splitlines()
    assert len(lines) == len(prepared['expectations']), 'Wrong actual facade observation count'
    for line, expected in zip(lines, prepared['expectations']):
        label, status, owner, pending, clocks = line.split('\t')
        assert (label, status) == (expected['label'], expected['status']), (label, status)
        assert bytes(map(int, owner.split(','))) == expected['owner'], ('owner', label)
        assert bytes(map(int, pending.split(','))) == expected['pending'], ('pending', label)
        words = [] if not clocks else list(map(int, clocks.split(',')))
        assert len(words) % 2 == 0
        times = [words[i:i + 2] for i in range(0, len(words), 2)]
        if expected['clocks'] is None:
            assert len(times) == 1, ('clock acquisition budget', times)
            value = (times[0][0] << 32) | times[0][1]
            assert before <= value <= after, ('actual native CLOCK_MONOTONIC boundary', value, before, after)
        else:
            assert times == expected['clocks'], ('unused constructor clocks', label, times)
    assert pin(prepared['reference']['path']) == prepared['reference'], 'Java reference changed during native run'
    return {'result': 'pass', 'cases': len(lines), 'process': process,
            'input': prepared['input'], 'reference': prepared['reference'], 'scope': prepared['scope']}
