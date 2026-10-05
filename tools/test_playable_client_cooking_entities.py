#!/usr/bin/env python3
"""Explicit Actor020 real entity delivery/atomic-save consumer; never builds.

Reuses the successful Actor019 socket/process/world-save helpers without
changing its fixture or receipt. File-only preparation needs no Actor020 binary.
"""
from __future__ import annotations

import argparse
import copy
import json
import sys
import time
from pathlib import Path

import test_playable_client_cooking as C19
import playable_client_cooking_entities_expectations as E

B, A, P, R, S, H = C19.B, C19.A, C19.P, C19.R, C19.S, C19.H
ROOT = C19.ROOT
WORK = ROOT / 'build/playable-client-cooking-entities'
REFERENCE = ROOT / 'reference/cooking_effect_entities.json'
VERIFIED19 = ROOT / 'evidence/playable-client-cooking-native-011.json'
POSITION = ('minecraft:overworld', 12, 8, 12)
USES = 20
RATE_BITS = 0x3eb33333


def runtime_pins():
    return C19.runtime_pins() | {str(path): R.pin(path) for path in
        (REFERENCE, ROOT / 'reference/vanilla_entity_fields.json',
         ROOT / 'generated/reference_slab_collision.tsv', VERIFIED19,
         Path(C19.__file__), Path(E.__file__))}


def monotonic_ns():
    # The actual native Clock FFI uses clock_gettime(CLOCK_MONOTONIC).
    return time.clock_gettime_ns(time.CLOCK_MONOTONIC)


def physical(facts, progress=40, remaining=10):
    root = C19.body_root(facts, progress=progress, remaining=remaining)
    known_uses = S.WC.compound([('minecraft:cooked_beef', S.WC.integer(USES))])
    return S.N.encode_root(S.N.RootTag(root.name, S.N.Value(10, tuple(
        (name, known_uses if name == S.N.text('RecipesUsed') else value)
        for name, value in root.value.payload))))


def expected_facts():
    facts = C19.independent_expectations()
    ref = json.loads(C19.REFERENCES[2].read_bytes())
    recipe = next(r for r in ref['recipes'] if r['id'] == 'minecraft:cooked_beef')
    S.require(recipe['experience_bits'] == RATE_BITS and
              E.f32(USES * E.f32(.35)) == 7., 'Actual beef recipe gives exact7 XP without fractional LEVEL draw')
    retained = json.loads(VERIFIED19.read_bytes())
    S.require(retained['status'] == 'PASS_NARROW' and retained['summary']['actual_SIGKILL_cold_restores'] == 2,
              'Retained successful019 consumer scope remains fixed')
    constructor_ref = json.loads(REFERENCE.read_bytes())
    S.require(constructor_ref['provenance']['client']['sha256'] == R.pin(B.JAR)['sha256'],
              'Constructor observations use the same pinned original26.3 JAR')
    facts['constructor_reference'] = E.verify_retained_java(REFERENCE)
    return facts


def wrapper(player, bodies, entities=None, clocks=()):
    dimension, x, y, z = POSITION
    locations = tuple(S.WC.compound([('dimension', S.WC.txt(dimension)),
        ('x', S.WC.integer(x)), ('y', S.WC.integer(y)), ('z', S.WC.integer(z)),
        ('body', S.N.Value(7, body))]) for body in bodies)
    values = [('format', S.WC.integer(1 if entities is None else 3)),
              ('player', S.N.Value(7, player)), ('bodies', S.N.Value(9, (10, locations)))]
    if entities is not None:
        values.extend([('effects', S.N.Value(7, C19.pending_bytes(()))),
                       ('entities', S.N.Value(7, E.encode(entities))),
                       ('clock_inputs', S.N.Value(12, tuple(clocks)))])
    return S.N.encode_root(S.N.RootTag(S.N.text(C19.WRAPPER), S.WC.compound(values)))


def bundle(world, highwater, record, full, bodies, entities=None, clocks=()):
    ordinary = S.N.parse(B.bundle(world, highwater, record, full, ''))
    fields = S.WC.fields(dict(ordinary.value.payload)[S.N.text('extension')], S.EXTENSION_FIELDS)
    extension = S.WC.compound([('namespace', fields['namespace']), ('schema', fields['schema']),
        ('payload', S.N.Value(7, wrapper(bytes(fields['payload'].payload), bodies, entities, clocks)))])
    return S.N.encode_root(S.N.RootTag(ordinary.name, S.N.Value(10, tuple(
        (name, extension if name == S.N.text('extension') else value)
        for name, value in ordinary.value.payload))))


def fixture(facts):
    world, record, full, _, _ = C19.fixture(facts)
    # The geometry capture's expanded scan must stay entirely resident. This
    # is a new020 fixture change; the verified019 fixture remains at y1.
    S.BASE.set_block(world, *C19.POSITION[1:], facts['palette']['minecraft:air'])
    S.BASE.set_block(world, *POSITION[1:], facts['lit'])
    body = physical(facts)
    return world, record, full, body, bundle(world, 40, record, full, (body,))


def projection(data, facts, *, allow_legacy=False):
    outer = S.N.Reader(data, max_bytes=33624064, max_depth=16, max_elements=33624064).root()
    S.require(outer.name == S.N.text('bendex:bundle'), 'Actual full atomic envelope root')
    fields = S.WC.fields(outer.value, S.BUNDLE_FIELDS)
    S.require(S.WC.uint(fields['format']) == 1 and S.WC.scalar_text(fields['minecraft']) == '26.3' and
              S.WC.scalar_text(fields['registry']) == facts['identity'], 'Pinned atomic envelope identity')
    world = S.WC.validate(S.N.parse(fields['core'].payload), facts['count'], facts['identity'])
    extension = S.WC.fields(fields['extension'], S.EXTENSION_FIELDS)
    S.require(S.WC.scalar_text(extension['namespace']) == S.NAMESPACE and
              S.WC.uint(extension['schema']) == 1, 'Unchanged atomic codec namespace/schema')
    nested = S.N.parse(bytes(extension['payload'].payload))
    S.require(nested.name == S.N.text(C19.WRAPPER), 'Cooking physical/recovery wrapper root')
    version = S.WC.uint(dict(nested.value.payload)[S.N.text('format')])
    S.require(version == 3 or allow_legacy and version == 1, 'Complete entity recovery format3 required')
    names = ('format', 'player', 'bodies') + (('effects', 'entities', 'clock_inputs') if version == 3 else ())
    saved = S.WC.fields(nested.value, names)
    S.require(saved['player'].kind == 7 and saved['bodies'].kind == 9 and
              saved['bodies'].payload[0] == 10 and len(saved['bodies'].payload[1]) <= 1,
              'Focused actual physical body list')
    bodies = []
    for raw in saved['bodies'].payload[1]:
        body = S.WC.fields(raw, ('dimension', 'x', 'y', 'z', 'body'))
        S.require((S.WC.scalar_text(body['dimension']), *(S.WC.uint(body[k]) for k in ('x', 'y', 'z')))
                  == POSITION and body['body'].kind == 7, 'Exact actual keyed body position')
        bodies.append(bytes(body['body'].payload))
    player, full = B.Inventory.parse_inventory_full(bytes(saved['player'].payload))
    entities, clocks = None, ()
    if version == 3:
        S.require(saved['effects'].kind == saved['entities'].kind == 7 and saved['clock_inputs'].kind == 12,
                  'Entity bytes and actual unconsumed constructor-clock LongArray')
        S.require(bytes(saved['effects'].payload) == C19.pending_bytes(()),
                  'Actual effect queue completely drained through joined publishers')
        entities = E.decode(bytes(saved['entities'].payload))
        clocks = tuple(saved['clock_inputs'].payload)
    return world, player, full, tuple(bodies), S.WC.uint(fields['peer_highwater']), entities, clocks


def acknowledge(client, path, facts, world, record, full, highwater, bodies,
                expected_entities, directory, label, *, validate_entities=None):
    reply = client.call('world.save', {})
    actual = path.read_bytes()
    observed_world, player, observed_full, observed_bodies, peer, observed_entities, clocks = projection(actual, facts)
    detail = validate_entities(observed_entities) if validate_entities else None
    if expected_entities is None:
        S.require(validate_entities is not None, 'Unpredictable fresh authority must be independently constrained')
        expected_entities = observed_entities
    S.require(clocks == () and observed_entities == expected_entities,
              'Complete sole entity owner and consumed constructor-clock queue: ' + label)
    expected = bundle(world, highwater, record, full, bodies, expected_entities)
    S.require(reply == {'status': 'durable', 'published': True, 'durable': True,
        'bytes': len(actual), 'peer_highwater': highwater} and actual == expected,
        'All Core/player/inventory/status/generation/body/entity/RNG/factory bytes: ' + label)
    S.require(S.P.canonical_expected(observed_world) == S.P.canonical_expected(world) and
              player == S.local_bytes(record) and observed_full == full and observed_bodies == tuple(bodies)
              and peer == highwater, 'Independent complete atomic projection: ' + label)
    receipt = {'label': label, 'reply': reply, 'bytes': len(actual), 'sha256': S.sha(actual),
        'expected_sha256': S.sha(expected), 'full_atomic_bytes_equal': True,
        'body_sha256': [S.sha(body) for body in observed_bodies],
        'entities_sha256': S.sha(E.encode(observed_entities)), 'pending_effects': 0,
        'unconsumed_clock_inputs': 0, 'LEVEL': observed_entities['level_random'],
        'factory': observed_entities['seed_uniquifier'], 'last_id': observed_entities['last_id'],
        'typed_record_kinds': [r['kind'] for r in observed_entities['records']],
        'constructor_boundary': detail}
    S.exclusive_json(directory / (label + '.json'), receipt)
    return actual, receipt, observed_entities


def scenario(directory, binary, bridge):
    directory.mkdir(exist_ok=False)
    facts = expected_facts()
    world, record, full, body, initial = fixture(facts)
    path = directory / 'cooking.nbt'
    path.write_bytes(initial)
    saves = []
    launch_ns = monotonic_ns()
    actor = A.PlayableBackend(directory / 'loaded-startup', binary, path, bridge)
    try:
        raw, ping = actor.tcp(True)
        developer, mping = actor.mcp()
        highwater = max(ping['peer'], mping['peer'])
        S.require(raw.call('world.clock') == S.P.clock(world), 'Fresh owner initialization never advances sole Core')
        S.inspect(raw, record)
        def fresh(observed):
            return E.fresh_expected(observed, launch_ns, monotonic_ns())
        _, receipt, before = acknowledge(developer, path, facts, world, record, full,
            highwater, (body,), None, directory, 'fresh-owner-startup', validate_entities=fresh)
        saves.append(receipt)
        raw.call('simulation.step', {'ticks': 1})
        S.BASE.apply_tick(world)
        record = S.decode_local(bytes(raw.call('player.inspect', {})['nbt_bytes']))
        S.require(record.count == 1 and raw.call('world.clock') == S.P.clock(world), 'Effect-free actual sole Core/player tick')
        acknowledged, receipt, _ = acknowledge(developer, path, facts, world, record, full,
            highwater, (physical(facts, 41, 9),), before, directory, 'effect-free-furnace-tick')
        saves.append(receipt)
        transient_world = copy.deepcopy(world)
        S.BASE.apply_tick(transient_world)
        S.require(raw.call('simulation.step', {'ticks': 1}) == S.P.clock(transient_world) and
                  raw.call('world.clock') == S.P.clock(transient_world) and
                  S.decode_local(bytes(raw.call('player.inspect', {})['nbt_bytes'])).count == 2 and
                  path.read_bytes() == acknowledged, 'Unsaved tick never alters last acknowledged owner authority')
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop(kill=not actor.stopped)

    actor = A.PlayableBackend(directory / 'cold-owner-restore', binary, path, bridge)
    try:
        raw, ping = actor.tcp(True)
        S.require(raw.call('world.clock') == S.P.clock(world) and path.read_bytes() == acknowledged,
                  'First SIGKILL/cold restore acknowledged Core and owner bytes')
        S.inspect(raw, record)
        S.queue_set(raw, world, POSITION, facts['palette']['minecraft:air'], world['tick'] + 1)
        begin = monotonic_ns()
        S.BASE.apply_tick(world)
        S.require(raw.call('simulation.step', {'ticks': 1}) == S.P.clock(world),
                  'Actual Item/Orb delivery completes reset tick through IO consumer')
        end = monotonic_ns()
        S.require(raw.call('world.clock') == S.P.clock(world) and
                  raw.call('world.block.get', dict(zip(('dimension', 'x', 'y', 'z'), POSITION)))
                  == {'state': facts['palette']['minecraft:air']}, 'Actual removal opens resident constructor geometry')
        record = S.decode_local(bytes(raw.call('player.inspect', {})['nbt_bytes']))
        S.require(record.count == 2, 'Completed reset tick advances common/player exactly once')
        constructor = {}
        def published(observed):
            expected, evidence = E.reset_expected(before, observed, begin, end, POSITION,
                [B.Inventory.stack('minecraft:beef', 2), B.Inventory.stack('minecraft:coal', 2)])
            constructor.update(evidence)
            return evidence
        _, receipt, delivered = acknowledge(raw, path, facts, world, record, full,
            ping['peer'], (), None, directory, 'actual-item-orb-delivery', validate_entities=published)
        saves.append(receipt)
        S.queue_set(raw, world, POSITION, facts['unlit'], world['tick'] + 1)
        S.BASE.apply_tick(world)
        S.require(raw.call('simulation.step', {'ticks': 1}) == S.P.clock(world), 'Drained queue permits recreation tick')
        record = S.decode_local(bytes(raw.call('player.inspect', {})['nbt_bytes']))
        S.require(record.count == 3, 'Recreation continues sole Core/player once')
        acknowledged, receipt, _ = acknowledge(raw, path, facts, world, record, full,
            ping['peer'], (C19.fresh_body(),), delivered, directory, 'fresh-details-with-complete-owner')
        saves.append(receipt)
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop(kill=not actor.stopped)

    actor = A.PlayableBackend(directory / 'cold-published-owner', binary, path, bridge)
    try:
        raw, ping = actor.tcp(True)
        S.require(raw.call('world.clock') == S.P.clock(world) and path.read_bytes() == acknowledged,
                  'Second SIGKILL/cold restore published typed entities/factory/RNG/full bytes')
        S.inspect(raw, record)
        S.queue_set(raw, world, POSITION, facts['palette']['minecraft:air'], world['tick'] + 1)
        S.BASE.apply_tick(world)
        S.require(raw.call('simulation.step', {'ticks': 1}) == S.P.clock(world),
                  'Cold-restored owner delivers actual three EmptyDrops')
        record = S.decode_local(bytes(raw.call('player.inspect', {})['nbt_bytes']))
        S.require(record.count == 4, 'Cold continuation advances player exactly once')
        continued = copy.deepcopy(delivered)
        level = E.Legacy(E.source_raw(continued['level_random']))
        for _ in range(3):
            E.drop_position(level, POSITION[1:])
        S.require(level.draws == 18, 'Three real EmptyDrop calls advance LEVEL eighteen primitive draws')
        continued['level_random'] = E.source(level.raw)
        _, receipt, _ = acknowledge(raw, path, facts, world, record, full,
            ping['peer'], (), continued, directory, 'cold-owner-continued-empty-drops')
        saves.append(receipt)
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop()
    summary = {'status': 'PASS_NARROW', 'generation': 'Actor004/producer020',
        'atomic_saves': saves, 'backends': 3, 'actual_SIGKILL_cold_restores': 2,
        'actual_TCP_MCP': True, 'sole_Core_final_tick': world['tick'],
        'actual_typed_Items': 2, 'actual_typed_Orbs': 1, 'XP_value': 7,
        'all_effects_delivered': True, 'fresh_keyed_Details_cleared': True,
        'constructor_boundary': constructor, 'clock_inputs_remaining': 0,
        'cold_LEVEL_continuation_primitive_draws': 18,
        'complete_entity_records_preserved_after_restore': True,
        'Java_constructor_expectations': facts['constructor_reference'],
        'scope': 'Declared isolated overworld entity factory/allocator and per-Level Legacy RNG, '
                 'real actor Item/Orb publication, complete atomic format3 storage, two SIGKILL '
                 'restores and continued EmptyDrop authority. No pickup/touch, entity movement, '
                 'render/UI, comparator/nonzero Dirty delivery, shared multi-Level factory or full-game parity claim.'}
    S.exclusive_json(directory / 'summary.json', summary)
    return summary


def fresh_directory():
    WORK.mkdir(exist_ok=True)
    for index in range(1, 10000):
        directory = WORK / f'{index:03}'
        try:
            directory.mkdir()
            return index, directory
        except FileExistsError:
            pass
    raise RuntimeError('No fresh entity consumer directory')


def prepare():
    facts = expected_facts()
    world, record, full, body, data = fixture(facts)
    projected = projection(data, facts, allow_legacy=True)
    S.require(S.P.canonical_expected(projected[0]) == S.P.canonical_expected(world) and
              projected[1:] == (S.local_bytes(record), full, (body,), 40, None, ()), 'Independent complete legacy startup fixture')
    # This synthetic DTO is only framing evidence; actual native expectations
    # start from the fresh first save and never supply fixed constructor entropy.
    empty = {'level_random': E.source(123), 'seed_uniquifier': E.words(E.factory_after(E.INITIAL_FACTORY, 2)),
             'last_id': 0, 'next_section_order': '0', 'records': []}
    recovery = bundle(world, 40, record, full, (body,), empty, (0x0123456789abcdef,))
    recovered = projection(recovery, facts)
    S.require(S.P.canonical_expected(recovered[0]) == S.P.canonical_expected(world) and
              recovered[1:] == (S.local_bytes(record), full, (body,), 40, empty, (0x0123456789abcdef,)),
              'Complete format3 DTO plus exact unconsumed clock framing')
    index, directory = fresh_directory()
    (directory / 'seed.nbt').write_bytes(data)
    (directory / 'format3-framing.nbt').write_bytes(recovery)
    result = {'status': 'PREPARED_FILE_ONLY; actual generation20 native pending', 'native_executed': False,
        'explicit_actor_generation': 20, 'runtime_inputs': runtime_pins(),
        'runner': R.pin(Path(__file__)), 'oracle': R.pin(Path(E.__file__)),
        'seed': R.pin(directory / 'seed.nbt'), 'framing_fixture': R.pin(directory / 'format3-framing.nbt'),
        'Java_constructor_expectations': facts['constructor_reference'],
        'recipesUsed': {'minecraft:cooked_beef': USES}, 'experience_bits': RATE_BITS, 'XP_award': 7,
        'cooking_position': POSITION,
        'resident_geometry_scan_halo': {'min': [9, 5, 9], 'max_inclusive': [15, 11, 15],
                                        'sections': [[0, 0, 0]], 'absent_air_fallback': False},
        'expected_records': ['Item beef2/full default component identity', 'Item coal2/full default component identity', 'Orb7'],
        'live_entropy_policy': 'First actual save reveals LEVEL seed; recover constructor times from stored local raw RNG and bound them within actual CLOCK_MONOTONIC launch/operation intervals. No fixed clock/UUID is supplied.',
        'effect_queue': 'Must drain completely where Item/Orb publishers and actual resident geometry are joined; any real missing-owner refusal fails this claimed delivery sequence.',
        'planned_scope': 'Five full atomic byte comparisons, two real SIGKILL/cold restores, fresh body Details clearing, exact complete typed records/RNG/factory/IDs and continued three-EmptyDrop LEVEL authority.',
        'profile': {'dimension': 'minecraft:overworld', 'factory': 'fresh isolated Level then Sound constructor order; initial cursor0',
                    'limits': [4096, 65536, 65536], 'reserved_ids': []},
        'scope_limits': ['No new Actor020 binary exists for this preparation', 'No native/source/kernel/Java replay',
                         'No item playerTouch/pickup, entity ticking, UI, multi-Level owner or whole-game parity'],
        'planned_native_argv': [sys.executable, '-B', str(Path(__file__)), '--actor-generation', '20', '--native']}
    output = ROOT / f'evidence/playable-client-cooking-entities-prepared-{index:03}.json'
    R.write(output, result, True)
    print(json.dumps({'status': result['status'], 'evidence': str(output)}), flush=True)


def child(directory):
    build = B.artifact()
    S.require(build['generation'] == 'immutable-actor004/producer020', 'Only explicit actual Actor020 artifact')
    before = runtime_pins()
    journal = directory / 'owned-groups.jsonl'
    journal.touch(exist_ok=False)
    bridge, _ = P.retained_bridge()
    def identity():
        S.require(R.pin(A.ACTOR) == build['binary'], 'Frozen actual020 actor binary changed')
    with H.bindings(S, {'SERVER': A.ACTOR, 'ROOT': ROOT, 'activation': identity, 'OWNED_GROUPS': journal}):
        result = scenario(directory / 'actors', A.ACTOR, bridge)
        S.require(runtime_pins() == before, 'Entity consumer pinned inputs changed')
        identity()
    print(json.dumps({'status': result['status'], 'atomic_saves': len(result['atomic_saves'])}), flush=True)


def native():
    build = B.artifact()
    S.require(build['generation'] == 'immutable-actor004/producer020', 'Only explicit actual020 successful artifact')
    index, directory = fresh_directory()
    before, runner = runtime_pins(), R.pin(Path(__file__))
    S.exclusive_json(directory / 'inputs.json', {'binary': build['binary'], 'source_map': build['source_map'],
        'build': R.pin(A.WORK / 'native-build.json'), 'runtime': before, 'runner': runner})
    bridge, _ = P.retained_bridge()
    with H.bindings(R, {'WORK': directory}):
        try:
            process = R.bounded([sys.executable, '-B', str(Path(__file__)), '--actor-generation', '20',
                                 '--_child', str(directory)], 600, 'execution')
        finally:
            B.descendant_cleanup(directory, bridge)
    common = {'binary': build['binary'], 'inputs': R.pin(directory / 'inputs.json'),
              'process': R.pin(directory / 'execution/result.full.json'), 'cleanup': R.pin(directory / 'cleanup.json')}
    try:
        R.process_ok(process)
    except BaseException:
        R.write(ROOT / f'evidence/playable-client-cooking-entities-failure-{index:03}.json',
            {'status': 'FAIL', **common, 'runtime_error': R.pin(directory / 'execution/stderr'),
             'scope': 'Actual changed020 consumer failed. Exact dynamic socket responses, durable file and owned process journals retained; no native delivery acceptance claim.'}, True)
        raise
    S.require(runtime_pins() == before and R.pin(Path(__file__)) == runner, 'Native020 inputs/runner changed')
    summary = json.loads((directory / 'actors/summary.json').read_bytes())
    output = ROOT / f'evidence/playable-client-cooking-entities-native-{index:03}.json'
    R.write(output, {'status': summary['status'], **common, 'summary': summary,
                     'summary_pin': R.pin(directory / 'actors/summary.json')}, True)
    print(json.dumps({'status': summary['status'], 'evidence': str(output)}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--actor-generation', required=True, type=int, choices=(20,))
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument('--expectations', action='store_true')
    modes.add_argument('--native', action='store_true')
    modes.add_argument('--_child', type=Path)
    args = parser.parse_args()
    selected = ROOT / 'build/compiler-producer-diagnostic-020'
    with H.bindings(A, {'WORK': selected, 'SOURCE': selected / 'source', 'ACTOR': selected / 'actor'}):
        if args.expectations:
            prepare()
        elif args._child:
            child(args._child)
        else:
            native()


if __name__ == '__main__':
    main()
