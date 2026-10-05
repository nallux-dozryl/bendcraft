#!/usr/bin/env python3
"""Actual future actor cooking publication/TCP/atomic-save consumer; never builds.

File-only preparation needs no actor. Native execution requires an explicitly
selected genuine producer after020. Each attempt retains every socket exchange,
physical save and process teardown. No menu queue is retroactively attested.
"""
from __future__ import annotations

import argparse
import copy
import json
import sys
import time
from pathlib import Path

import test_playable_client_cooking_menu as Menu
import playable_client_cooking_publication_expectations as J

C19, B, A, P, R, S, H = Menu.C19, Menu.B, Menu.A, Menu.P, Menu.R, Menu.S, Menu.H
Storage, Entity = Menu.Storage, Menu.Storage.E
ROOT = Menu.ROOT
WORK = ROOT / 'build/playable-client-cooking-publication'
POSITIONS = (('minecraft:overworld', 12, 8, 12), ('minecraft:overworld', 18, 8, 12))
COUNTERS = (3, 5)
REMOVED = 'minecraft:the_nether/4294967295/2147483648/2147483647'
CRITICAL = ('src/cooking_effect_publication.bend', 'src/cooking_effect_publication_journal.bend',
    'src/local_player_cooking_publication_codec.bend', 'src/local_player_cooking_publication_owner.bend',
    'src/local_player_cooking_publication_delivery.bend', 'src/local_player_cooking_dirty_stamp.bend',
    'src/player_cooking_menu.bend', 'src/local_player_session.bend', 'src/extended_persistence.bend',
    'src/cooking_effect_recovery.bend', 'src/local_player_cooking_storage.bend',
    'remote_resource_server.bend')


def runtime_pins():
    return Menu.runtime_pins() | {str(path): R.pin(path) for path in
        (Path(__file__), Path(J.__file__), Path(Entity.__file__),
         ROOT / 'reference/cooking_effect_publication.json',
         ROOT / 'reference/cooking_effect_entities.json')}


def catalog():
    return json.loads((ROOT / 'reference/cooking_world.json').read_bytes())


def map_bit(key, index):
    character, offset = divmod(index, 33)
    if character >= len(key):
        return 0
    return 1 if offset == 0 else (key[character] >> (32 - offset)) & 1


def map_tree(rows, beginning=0):
    """Independent first-differing-bit Patricia fixture; retain its full shape."""
    if not rows:
        return J.tip()
    if len(rows) == 1:
        return J.leaf(*rows[0])
    bound = (max(len(key) for key, _ in rows) + 1) * 33
    split = next(index for index in range(beginning, bound)
                 if len({map_bit(key, index) for key, _ in rows}) == 2)
    low = [(key, value) for key, value in rows if map_bit(key, split) == 0]
    high = [(key, value) for key, value in rows if map_bit(key, split) == 1]
    return J.node(split, map_tree(low, split + 1), map_tree(high, split + 1))


def counters():
    return map_tree([(J.words('/'.join((point[0], *map(str, point[1:])))), value)
                     for point, value in zip(POSITIONS, COUNTERS, strict=True)] +
                    [(J.words(REMOVED), 9)])


def source(facts, index, *, lit=False, incarnation=None):
    point = J.position(*POSITIONS[index])
    return J.source(point, J.binding_for(catalog(), facts['lit'] if lit else facts['unlit']),
                    COUNTERS[index] if incarnation is None else incarnation)


def owned(producer):
    return J.effect(6, producer['position'], producer)


def physical(facts, slots, *, progress=0, remaining=0, total=200, lit_total=10):
    """Exact physical Java Details, original names/order/duplicates/raw bits."""
    original = C19.body_root(facts, progress=progress, remaining=remaining)
    items = tuple(C19.JavaBody.item(index, item['id'], item['count'])
                  for index, item in enumerate(slots) if item is not None)
    replace = {S.N.text('cooking_total_time'): S.WC.integer(total),
               S.N.text('lit_total_time'): S.WC.integer(lit_total),
               S.N.text('Items'): S.N.Value(9, (10 if items else 0, items))}
    return S.N.encode_root(S.N.RootTag(original.name, S.N.Value(10, tuple(
        (name, replace.get(name, value)) for name, value in original.value.payload))))


def wrapper(player, bodies, effects, entities, clocks, publication):
    locations = tuple(S.WC.compound([
        ('dimension', S.WC.txt(point[0])),
        *[(name, S.WC.integer(value)) for name, value in zip(('x', 'y', 'z'), point[1:], strict=True)],
        ('body', S.N.Value(7, body))]) for point, body in bodies)
    return S.N.encode_root(S.N.RootTag(S.N.text(C19.WRAPPER), S.WC.compound([
        ('format', S.WC.integer(4)), ('player', S.N.Value(7, player)),
        ('bodies', S.N.Value(9, (10, locations))),
        ('effects', S.N.Value(7, J.encode_effects(effects, catalog()))),
        ('entities', S.N.Value(7, b'' if entities is None else Entity.encode(entities))),
        ('clock_inputs', S.N.Value(12, tuple(clocks))),
        ('publication', S.N.Value(7, publication))])))


def bundle(world, highwater, record, full, bodies, effects, entities, clocks, publication):
    ordinary = S.N.parse(B.bundle(world, highwater, record, full, ''))
    extension_fields = S.WC.fields(dict(ordinary.value.payload)[S.N.text('extension')], S.EXTENSION_FIELDS)
    extension = S.WC.compound([
        ('namespace', extension_fields['namespace']), ('schema', extension_fields['schema']),
        ('payload', S.N.Value(7, wrapper(bytes(extension_fields['payload'].payload),
            bodies, effects, entities, clocks, publication)))])
    return S.N.encode_root(S.N.RootTag(ordinary.name, S.N.Value(10, tuple(
        (name, extension if name == S.N.text('extension') else value)
        for name, value in ordinary.value.payload))))


def ordered(value, names):
    S.require(value.kind == 10 and tuple(name for name, _ in value.payload) ==
              tuple(S.N.text(name) for name in names), 'Exact ordered physical fields: ' + ','.join(names))
    return {name: member for name, (_, member) in zip(names, value.payload, strict=True)}


def projection(data, facts):
    outer = S.N.Reader(data, max_bytes=33624064, max_depth=16, max_elements=33624064).root()
    S.require(outer.name == S.N.text('bendex:bundle'), 'Full atomic envelope root')
    fields = ordered(outer.value, S.BUNDLE_FIELDS)
    S.require(S.WC.uint(fields['format']) == 1 and S.WC.scalar_text(fields['minecraft']) == '26.3' and
              S.WC.scalar_text(fields['registry']) == facts['identity'], 'Pinned atomic envelope identity')
    S.require(fields['core'].kind == 7, 'Full Core ByteArray')
    world = S.WC.validate(S.N.parse(fields['core'].payload), facts['count'], facts['identity'])
    extension = ordered(fields['extension'], S.EXTENSION_FIELDS)
    S.require(S.WC.scalar_text(extension['namespace']) == S.NAMESPACE and
              S.WC.uint(extension['schema']) == 1 and extension['payload'].kind == 7,
              'Existing atomic namespace/schema')
    root = S.N.parse(bytes(extension['payload'].payload))
    S.require(root.name == S.N.text(C19.WRAPPER), 'Cooking format4 physical root')
    saved = ordered(root.value, ('format', 'player', 'bodies', 'effects', 'entities', 'clock_inputs', 'publication'))
    S.require(S.WC.uint(saved['format']) == 4 and all(saved[name].kind == 7 for name in
        ('player', 'effects', 'entities', 'publication')) and saved['clock_inputs'].kind == 12 and
        saved['bodies'].kind == 9 and saved['bodies'].payload[0] == 10, 'Complete format4 framing')
    player, full = B.Inventory.parse_inventory_full(bytes(saved['player'].payload))
    bodies, seen = [], set()
    for raw in saved['bodies'].payload[1]:
        body = ordered(raw, ('dimension', 'x', 'y', 'z', 'body'))
        point = (S.WC.scalar_text(body['dimension']), *(S.WC.uint(body[key]) for key in ('x', 'y', 'z')))
        S.require(point not in seen and body['body'].kind == 7, 'Unique complete keyed physical body')
        seen.add(point); bodies.append((point, bytes(body['body'].payload)))
    effects = J.decode_effects(bytes(saved['effects'].payload), catalog())
    entity_bytes = bytes(saved['entities'].payload)
    entities = Entity.decode(entity_bytes) if entity_bytes else None
    clocks = tuple(saved['clock_inputs'].payload)
    S.require(entities is not None or not clocks, 'No clock inputs without entity owner')
    publication = J.decode_publication(bytes(saved['publication'].payload), catalog())
    result = {'world': world, 'player': player, 'full': full, 'bodies': tuple(bodies),
              'highwater': S.WC.uint(fields['peer_highwater']), 'effects': effects,
              'entities': entities, 'clock_inputs': clocks, 'publication': publication}
    # Byte equality covers complete Core topology/events/schedule, all player
    # metadata and43 durable cells, physical Details and every entity/RNG word.
    record = S.decode_local(player)
    rebuilt = bundle(world, result['highwater'], record, full, result['bodies'], effects,
                     entities, clocks, publication['raw'])
    S.require(data == rebuilt, 'Independent full physical reconstruction')
    return result


def section_order(world):
    def path(section):
        value = 2166136261
        for char in section['key']:
            value = ((value ^ ord(char)) * 16777619) & 0xffffffff
        return int(f'{value:032b}'[::-1], 2)
    return sorted(world['sections'], key=path)


def cooker_order(world):
    # Core's fixed hash trie enumerates lo then hi. Cooking discovers sections
    # in that order and prepends each section's ascending-index cooker entries.
    discovered = []
    for section in section_order(world):
        points = [point for point in POSITIONS if S.BASE.section_key(*point[1:]) == section['key']]
        points.sort(key=lambda point: (point[1] & 15) + ((point[3] & 15) << 4) + ((point[2] & 15) << 8))
        discovered = points + discovered
    return tuple(discovered)


def fixture(facts, *, empty=False, pending=()):
    world, record, full, _, _, _ = Menu.E.fixture(facts)
    second = [facts['palette']['minecraft:air']] * 4096
    second[7 * 256:8 * 256] = [facts['palette']['minecraft:stone']] * 256
    world['sections'].append({'key': S.BASE.section_key(16, 0, 0), 'cells': tuple(second)})
    world['sections'].sort(key=lambda section: section['key'])
    for point in POSITIONS:
        S.BASE.set_block(world, *point[1:], facts['unlit'])
    record = A.playable_spawn((15.5, 8.0, 10.5))
    slots = [None] * 3 if empty else [B.stack('minecraft:beef', 2), B.stack('minecraft:coal', 2), None]
    body = physical(facts, slots, total=0 if empty else 200, lit_total=0 if empty else 10)
    bodies = tuple((point, body) for point in cooker_order(world))
    publication = J.encode_publication(counters(), 0, (), None, catalog())
    data = bundle(world, 40, record, full, bodies, pending, None, (), publication)
    return world, record, full, slots, bodies, data


def validate_neighbours(world, facts):
    for point in POSITIONS:
        for dx, dz in ((0, -1), (1, 0), (0, 1), (-1, 0)):
            x, y, z = point[1] + dx, point[2], point[3] + dz
            section = next(section for section in world['sections'] if section['key'] == S.BASE.section_key(x, y, z))
            S.require(section['cells'][(x & 15) + ((z & 15) << 4) + ((y & 15) << 8)] ==
                      facts['palette']['minecraft:air'], 'Actual four loaded air neighbour cells')


def ignition_reference():
    retained = json.loads(C19.REFERENCES[1].read_bytes())
    result = next(row for row in retained['cases'] if row['id'] == 'ignite')['steps'][0]
    after = result['after']
    S.require(result['dirty'] and result['lit_change'] is True and
              (after['litTimeRemaining'], after['litTotalTime'], after['cookingTimer'],
               after['cookingTotalTime']) == (1600, 1600, 1, 200), 'Retained Java ignition progression')
    return {'reference': R.pin(C19.REFERENCES[1]), 'case': 'ignite', 'step': 0,
            'composition': 'Pinned coal ignition/timers composed with actual original-JAR beef recipe; no full-world Java sequence is claimed.'}


def handle(menu, index, peer, *, incarnation=None):
    return [1, menu, peer, list(POSITIONS[index]), 'minecraft:furnace', 0,
            COUNTERS[index] if incarnation is None else incarnation]


def acknowledge(raw, path, facts, world, record, full, bodies, highwater, entities,
                directory, label, *, expected_effects=None, expected_journal=None, fresh_interval=None):
    reply = raw.call('world.save', {})
    data = path.read_bytes()
    (directory / (label + '.nbt')).write_bytes(data)
    actual = projection(data, facts)
    S.require(reply == {'status': 'durable', 'published': True, 'durable': True,
        'bytes': len(data), 'peer_highwater': highwater}, 'Actual full atomic durable acknowledgement: ' + label)
    S.require(S.P.canonical_expected(actual['world']) == S.P.canonical_expected(world) and
        actual['player'] == S.local_bytes(record) and actual['full'] == full and actual['bodies'] == bodies and
        actual['highwater'] == highwater and not actual['clock_inputs'],
        'Independent complete Core/player/all43 cells/Details/clocks: ' + label)
    S.require(actual['publication']['incarnations'] == counters(), 'Full raw incarnation topology: ' + label)
    if entities is None:
        S.require(fresh_interval is not None and actual['entities'] is not None, 'Real fresh owner must be observed once')
        constructor = Entity.fresh_expected(actual['entities'], *fresh_interval)
        entities = actual['entities']
    else:
        constructor = None
        S.require(actual['entities'] == entities, 'Complete entity/RNG/factory/IDs unchanged: ' + label)
    if expected_effects is not None:
        S.require(actual['effects'] == expected_effects, 'Exact ordered pending effects: ' + label)
    if expected_journal is not None:
        S.require(actual['publication']['journal'] == expected_journal, 'Exact latest receipt/clean projection: ' + label)
    expected = bundle(world, highwater, record, full, bodies, actual['effects'], entities, (),
        J.encode_publication(counters(), actual['publication']['journal']['sequence'],
            actual['publication']['journal']['unsaved'], actual['publication']['journal']['last'], catalog()))
    S.require(data == expected, 'Exact full atomic bytes: ' + label)
    receipt = {'label': label, 'reply': reply, 'physical': R.pin(directory / (label + '.nbt')),
        'independent_expected_sha256': S.sha(expected), 'complete_bytes_equal': True,
        'pending_effects': actual['effects'], 'publication': actual['publication']['journal'],
        'constructor': constructor, 'full_incarnation_topology_equal': True,
        'full_entity_owner_equal': True, 'clock_inputs': []}
    S.exclusive_json(directory / (label + '.json'), receipt)
    return data, receipt, entities, actual


def live_step(raw, world, *, ignite=False):
    S.BASE.apply_tick(world)
    if ignite:
        for point in cooker_order(world):
            S.BASE.set_block(world, *point[1:], C19.independent_expectations()['lit'])
            world['revision'] += 1
            world['events'].insert(0, {'stamp': (world['tick'], 0, world['revision']),
                                      'kind': 0, 'revision': world['revision']})
    S.require(raw.call('simulation.step', {'ticks': 1}) == S.P.clock(world) and
              raw.call('world.clock') == S.P.clock(world), 'Actual explicit sole-Core step')
    return Menu.inspect_record(raw)


def positive(directory, binary, bridge):
    directory.mkdir(exist_ok=False)
    facts = C19.independent_expectations()
    world, record, full, slots, bodies, initial = fixture(facts)
    validate_neighbours(world, facts)
    path = directory / 'publication.nbt'; path.write_bytes(initial)
    checks, saves = [], []
    current = B.empty_menu()
    began = Storage.monotonic_ns()
    actor = A.PlayableBackend(directory / 'menu-queued-and-ignition', binary, path, bridge, lifetime_seconds=240)
    try:
        raw, ping = actor.tcp(True)
        S.require(ping['peer'] == 42, 'Durable40 -> local41/public42')
        control = Menu.connect(actor)
        S.inspect(raw, record)
        changed_bodies = dict(bodies)
        for index, point in enumerate(POSITIONS):
            menu_id = index + 1
            current['opened'] = True
            opened = handle(menu_id, index, 41)
            Menu.cooking(control, checks, [14, list(point)], f'open-current-owner-{index}',
                Menu.E.snapshot(full, current, opened, Menu.E.view(slots, [0, 10, 0, 200])))
            changed = [B.stack('minecraft:beef', 1), B.stack('minecraft:coal', 2), None]
            current.update(carried=B.stack('minecraft:beef', 1), revision=current['revision'] + 1)
            Menu.cooking(control, checks, [16, menu_id, 0, 1], f'actual-menu-owned-dirty-{index}',
                Menu.E.snapshot(full, current, opened, Menu.E.view(changed, [0, 10, 0, 200])))
            # Close returns the actual carried stack into durable main inventory.
            full['main']['slots'][1] = B.stack('minecraft:beef', index + 1)
            current.update(carried=None, opened=False, revision=current['revision'] + 1)
            Menu.cooking(control, checks, [18, menu_id], f'close-real-return-{index}',
                Menu.E.snapshot(full, current, [0], [0]))
            changed_bodies[point] = physical(facts, changed)
        bodies = tuple((point, changed_bodies[point]) for point in cooker_order(world))
        _, receipt, entities, captured = acknowledge(raw, path, facts, world, record, full, bodies,
            ping['peer'], None, directory, 'nonzero-menu-queue', fresh_interval=(began, Storage.monotonic_ns()))
        saves.append(receipt)
        # A real paused50ms pulse may have published an earlier prefix. The
        # physical save itself determines which genuine prefix was committed.
        journal = captured['publication']['journal']
        sequence = journal['sequence']
        producers = tuple(source(facts, index) for index in range(2))
        S.require(0 <= sequence <= 2 and captured['effects'] == tuple(map(owned, producers[sequence:])) and
                  not journal['unsaved'], 'Real menu OwnedDirty suffix and covered clean projection')
        previous = None if sequence == 0 else J.receipt(producers[sequence - 1]['position'],
            producers[sequence - 1], J.chunk_for(producers[sequence - 1]['position']), sequence)
        S.require(journal['last'] == previous, 'Actual earlier pulse prefix is exact and ordered')
        record = live_step(raw, world, ignite=True)
        S.require(record.count == 1, 'Exactly one player/common tick')
        cooked = [B.stack('minecraft:beef', 1), B.stack('minecraft:coal', 1), None]
        bodies = tuple((point, physical(facts, cooked, progress=1, remaining=1600, lit_total=1600))
                       for point in cooker_order(world))
        last_index = POSITIONS.index(cooker_order(world)[-1])
        producer = source(facts, last_index)
        final_journal = {'sequence': 4, 'unsaved': (), 'last': J.receipt(producer['position'],
            producer, J.chunk_for(producer['position']), 4)}
        acknowledged, receipt, _, _ = acknowledge(raw, path, facts, world, record, full, bodies,
            ping['peer'], entities, directory, 'two-chunk-ignition-durable',
            expected_effects=(), expected_journal=final_journal)
        saves.append(receipt)
        S.require(final_journal['last']['source']['binding']['lit'] == 0 and all(
            raw.call('world.block.get', dict(zip(('dimension', 'x', 'y', 'z'), point))) ==
            {'state': facts['lit']} for point in POSITIONS), 'Cached-unlit same incarnation versus actual lit Core')
        S.exclusive_json(directory / 'before-cold.json', {'status': 'PASS', 'journal_sequence': 4,
            'menu_mutations': 2, 'ignition_publications': 2, 'covered_chunks': [0, 1],
            'nonzero_real_pending_captured': len(captured['effects']),
            'nonzero_pending_observation': 'OBSERVED' if captured['effects'] else 'UNOBSERVED; actual50ms pulse published before save',
            'core_ticks': 1,
            'cached_unlit_source_survives_same_incarnation_LIT_change': True})
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop(kill=not actor.stopped)

    S.require(path.read_bytes() == acknowledged, 'SIGKILL after acknowledgement retains exact saved bytes')
    actor = A.PlayableBackend(directory / 'cold-current-owner', binary, path, bridge, lifetime_seconds=240)
    try:
        raw, ping = actor.tcp(True)
        S.require(ping['peer'] == 44 and raw.call('world.clock') == S.P.clock(world) and
                  path.read_bytes() == acknowledged, 'Actual SIGKILL/cold restore durable owners')
        S.inspect(raw, record)
        _, receipt, _, restored = acknowledge(raw, path, facts, world, record, full, bodies, ping['peer'],
            entities, directory, 'cold-full-incarnation-and-receipt', expected_effects=(), expected_journal=final_journal)
        saves.append(receipt)
        control = Menu.connect(actor)
        current = B.empty_menu(); current['opened'] = True
        opened = handle(1, 0, 43)
        Menu.cooking(control, checks, [14, list(POSITIONS[0])], 'cold-open-restored-incarnation3',
            Menu.E.snapshot(full, current, opened, Menu.E.view(cooked, [1600, 1600, 1, 200])))
        # Fuel count1->empty changes the actual menu; input remains beef1 so
        # no input-identity reset or extra Dirty is expected.
        changed = [B.stack('minecraft:beef', 1), None, None]
        current.update(carried=B.stack('minecraft:coal', 1), revision=1)
        Menu.cooking(control, checks, [16, 1, 1, 0], 'cold-new-owned-dirty-cached-lit',
            Menu.E.snapshot(full, current, opened, Menu.E.view(changed, [1600, 1600, 1, 200])))
        full['main']['slots'][2] = B.stack('minecraft:coal', 1)
        current.update(carried=None, opened=False, revision=2)
        Menu.cooking(control, checks, [18, 1], 'cold-close-real-coal-return',
            Menu.E.snapshot(full, current, [0], [0]))
        record = live_step(raw, world)
        S.require(record.count == 2, 'Cold continuation player/common exactly once')
        bodies = tuple((point, physical(facts, changed if point == POSITIONS[0] else cooked,
            progress=2, remaining=1599, lit_total=1600)) for point in cooker_order(world))
        continued_source = source(facts, 0, lit=True)
        continued_journal = {'sequence': 5, 'unsaved': (), 'last': J.receipt(continued_source['position'],
            continued_source, J.chunk_for(continued_source['position']), 5)}
        _, receipt, _, _ = acknowledge(raw, path, facts, world, record, full, bodies, ping['peer'],
            entities, directory, 'cold-new-mutation-continued-sequence', expected_effects=(), expected_journal=continued_journal)
        saves.append(receipt)
        # A further acknowledged save with no mutation must retain every byte.
        stable, receipt, _, _ = acknowledge(raw, path, facts, world, record, full, bodies, ping['peer'],
            entities, directory, 'no-duplicate-publication-after-ack', expected_effects=(), expected_journal=continued_journal)
        saves.append(receipt)
        S.require(stable == (directory / 'cold-new-mutation-continued-sequence.nbt').read_bytes(),
                  'Unchanged owner after durable commit has no duplicate notification or save-byte drift')
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop()
    result = {'status': 'PASS', 'backends': 2, 'actual_SIGKILL_cold_restores': 1,
        'actual_TCP': True, 'cooking_checks': checks, 'atomic_saves': saves,
        'final_publication_sequence': 5, 'actual_menu_mutations': 3, 'actual_ignition_publications': 2,
        'actual_two_chunk_full_save': True, 'raw_incarnation_map_topology_retained': True,
        'cached_unlit_current_lit_same_incarnation': True,
        'scope': 'Complete durable Core/player/all43 inventory cells/physical Details/empty full entity owner and RNG/factory/IDs/clocks/publication map/latest receipt. Player motion is cross-checked against the complete public inspect result; no new movement oracle is claimed. Journal dirty lists are projected clean by the real full save; live internal unsaved flags are not exposed by TCP.'}
    S.exclusive_json(directory / 'summary.json', result)
    return result


def negative(directory, binary, bridge, *, stale):
    directory.mkdir(exist_ok=False)
    facts = C19.independent_expectations()
    first = owned(source(facts, 0, incarnation=2)) if stale else J.effect(3, J.position(*POSITIONS[0]))
    # Complete suffix includes a separately authentic queued notification. It
    # must never pass the first refused effect or acquire retrospective source.
    pending = (first, owned(source(facts, 1)))
    world, record, full, slots, bodies, seed = fixture(facts, empty=True, pending=pending)
    path = directory / 'refused.nbt'; path.write_bytes(seed)
    began = Storage.monotonic_ns()
    actor = A.PlayableBackend(directory / 'ordered-refusal', binary, path, bridge, lifetime_seconds=120)
    try:
        raw, ping = actor.tcp(True)
        expected = 'cooking-publication:stale-block-entity-incarnation' if stale else \
                   'cooking-entities:block-entity-and-comparator-publisher-required'
        failure = raw.call('simulation.step', {'ticks': 1}, fault='PlayerStepUnavailable')
        S.require(expected in failure['error']['message'] and raw.call('world.clock') == S.P.clock(world),
                  'Genuine refused ordered suffix blocks the next Core tick')
        S.inspect(raw, record)
        _, receipt, entities, saved = acknowledge(raw, path, facts, world, record, full, bodies,
            ping['peer'], None, directory, 'refused-complete-owner-save', expected_effects=pending,
            expected_journal={'sequence': 0, 'unsaved': (), 'last': None},
            fresh_interval=(began, Storage.monotonic_ns()))
        _, second, _, _ = acknowledge(raw, path, facts, world, record, full, bodies,
            ping['peer'], entities, directory, 'refused-no-retroattestation-or-tail-drain',
            expected_effects=pending, expected_journal={'sequence': 0, 'unsaved': (), 'last': None})
        S.require(receipt['physical']['sha256'] == second['physical']['sha256'], 'Whole refusal state remains stable')
        result = {'status': 'PASS', 'kind': 'stale-current-incarnation' if stale else 'legacy-position-only',
            'genuine_failure': failure, 'pending_count': 2, 'complete_ordered_suffix_retained': True,
            'Core_and_player_tick_unchanged': True, 'legacy_source_not_attested': not stale,
            'journal_sequence': 0, 'atomic_saves': [receipt, second]}
        S.exclusive_json(directory / 'summary.json', result)
        return result
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop()


def fresh_directory():
    WORK.mkdir(exist_ok=True)
    for index in range(1, 10000):
        directory = WORK / f'{index:03}'
        try:
            directory.mkdir()
            return index, directory
        except FileExistsError:
            continue
    raise RuntimeError('No unused publication directory')


def prepare(generation):
    facts = C19.independent_expectations()
    reference = ignition_reference()
    Menu.E.reference_cases()
    world, record, full, slots, bodies, seed = fixture(facts)
    validate_neighbours(world, facts)
    actual = projection(seed, facts)
    S.require(S.P.canonical_expected(actual['world']) == S.P.canonical_expected(world) and
        actual['player'] == S.local_bytes(record) and actual['full'] == full and actual['bodies'] == bodies and
        actual['effects'] == () and actual['entities'] is None and actual['clock_inputs'] == () and
        actual['publication']['incarnations'] == counters() and
        actual['publication']['journal'] == {'sequence': 0, 'unsaved': (), 'last': None},
        'Independent empty-history physical fixture roundtrip')
    index, directory = fresh_directory()
    (directory / 'seed.nbt').write_bytes(seed)
    for stale, label in ((False, 'legacy'), (True, 'stale')):
        first = owned(source(facts, 0, incarnation=2)) if stale else J.effect(3, J.position(*POSITIONS[0]))
        negative_fixture = fixture(facts, empty=True, pending=(first, owned(source(facts, 1))))
        raw = negative_fixture[-1]
        decoded = projection(raw, facts)
        S.require(decoded['effects'] == (first, owned(source(facts, 1))) and
                  decoded['publication']['journal']['sequence'] == 0, 'Physical ordered negative fixture')
        (directory / (label + '-pending.nbt')).write_bytes(raw)
    result = {'status': 'PREPARED_FILE_ONLY; actual actor after020 pending', 'native_executed': False,
        'actor_generation': generation, 'runtime_inputs': runtime_pins(), 'seed': R.pin(directory / 'seed.nbt'),
        'legacy_fixture': R.pin(directory / 'legacy-pending.nbt'), 'stale_fixture': R.pin(directory / 'stale-pending.nbt'),
        'positions': POSITIONS, 'incarnations': [],
        'initial_journal_sequence': 0, 'no_synthetic_journal_receipts': True,
        'real_four_loaded_neighbours_each': True, 'body_order': cooker_order(world),
        'Java_ignition': reference, 'planned_final_sequence': 5,
        'planned_native_argv': [sys.executable, '-B', str(Path(__file__)), '--actor-generation', str(generation), '--native'],
        'timing_limit': 'The real backend publishes on50ms pulses even while paused. Capture the menu-to-save queue once; if a pulse wins, record UNOBSERVED for nonzero pending and continue actual Step/durable/cold assertions without retry or a fake timer.',
        'planned_scope': 'Real menu mutations, exact ordered effect suffix, explicit same-incarnation cached-LIT ignition, two loaded chunk publications, full actual atomic durable save, one real acknowledged-save SIGKILL/cold restore, exact incarnation topology/latest receipt, new mutation sequence5/no duplicates; distinct legacy/stale suffix refusals.',
        'limits': 'No live internal journal introspection, nonzero comparator/conductor, renderer/OS, unfinished-write crash, or fresh movement oracle.'}
    # Raw map keys are Char tuples; JSON uses explicit readable key rows.
    result['incarnations'] = [{'key_words': list(key), 'value': value} for key, value in J.map_items(counters()).items()]
    output = ROOT / f'evidence/playable-client-cooking-publication-prepared-{index:03}.json'
    R.write(directory / 'prepared.json', result, True); R.write(output, result, True)
    print(json.dumps({'status': result['status'], 'evidence': str(output)}), flush=True)


def artifact():
    build = B.artifact()
    mapping = json.loads((A.SOURCE / 'source-map.json').read_bytes())
    rows = {row['path']: row for row in mapping['files']}
    S.require(all(path in rows for path in CRITICAL), 'Selected actor includes the complete actual publication/save graph')
    S.require(all(R.pin(Path(rows[path]['mapped']['resolved']))['sha256'] == rows[path]['mapped']['sha256']
                  for path in CRITICAL), 'Immutable mapped production graph bytes')
    return build


def child(directory):
    build = artifact()
    before = runtime_pins()
    journal = directory / 'owned-groups.jsonl'; journal.touch(exist_ok=False)
    bridge, _ = P.retained_bridge()
    def identity():
        S.require(R.pin(A.ACTOR) == build['binary'], 'Selected actual actor changed')
    with H.bindings(S, {'SERVER': A.ACTOR, 'ROOT': ROOT, 'activation': identity, 'OWNED_GROUPS': journal}):
        try:
            positive_result = positive(directory / 'positive', A.ACTOR, bridge)
            legacy = negative(directory / 'legacy', A.ACTOR, bridge, stale=False)
            stale = negative(directory / 'stale', A.ACTOR, bridge, stale=True)
            S.require(runtime_pins() == before, 'Inputs changed during actual publication run')
            identity()
            result = {'status': 'PASS', 'generation': A.generation_name(), 'positive': positive_result,
                      'legacy': legacy, 'stale': stale}
            S.exclusive_json(directory / 'summary.json', result)
        except BaseException as cause:
            S.exclusive_json(directory / 'first-failure.json', {'type': type(cause).__name__, 'message': str(cause)})
            raise
    print(json.dumps({'status': 'PASS', 'final_sequence': 5, 'backends': 4}), flush=True)


def native():
    build = artifact()
    index, directory = fresh_directory()
    before = runtime_pins()
    S.exclusive_json(directory / 'inputs.json', {'binary': build['binary'],
        'build': R.pin(A.WORK / 'native-build.json'), 'source_map': build['source_map'], 'runtime_inputs': before})
    bridge, _ = P.retained_bridge()
    with H.bindings(R, {'WORK': directory}):
        try:
            process = R.bounded([sys.executable, '-B', str(Path(__file__)), '--actor-generation',
                str(A.generation()), '--_child', str(directory)], 660, 'execution')
        finally:
            B.descendant_cleanup(directory, bridge)
    output = ROOT / f'evidence/playable-client-cooking-publication-native-{index:03}.json'
    result = {'status': 'PASS' if process['exit_code'] == 0 and not process['timed_out'] else 'FAIL',
        'binary': build['binary'], 'process': R.pin(directory / 'execution/result.full.json'),
        'cleanup': R.pin(directory / 'cleanup.json'), 'inputs': R.pin(directory / 'inputs.json')}
    for name in ('summary.json', 'first-failure.json', 'positive/before-cold.json', 'positive/summary.json',
                 'legacy/summary.json', 'stale/summary.json'):
        path = directory / name
        if path.exists():
            result[name] = json.loads(path.read_bytes())
    R.write(output, result, True)
    R.process_ok(process)
    S.require(runtime_pins() == before, 'Runtime or runner changed during bounded execution')
    print(json.dumps({'status': result['status'], 'evidence': str(output)}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--actor-generation', type=int, required=True)
    parser.add_argument('--expectations', action='store_true')
    parser.add_argument('--native', action='store_true')
    parser.add_argument('--_child', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.actor_generation <= 20 or sum((args.expectations, args.native, bool(args._child))) != 1:
        parser.error('explicit genuine producer after020 and exactly one mode required')
    selected = ROOT / f'build/compiler-producer-diagnostic-{args.actor_generation:03}'
    with H.bindings(A, {'WORK': selected, 'SOURCE': selected / 'source', 'ACTOR': selected / 'actor'}):
        if args._child:
            child(args._child)
        elif args.native:
            native()
        else:
            prepare(args.actor_generation)


if __name__ == '__main__':
    main()
