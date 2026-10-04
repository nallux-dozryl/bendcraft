#!/usr/bin/env python3
"""Small explicitly selected cooking/startup/atomic-save consumer; never builds.

The file-only mode constructs a one-section physical save from retained pinned
Java receiver observations. Native mode uses the existing bounded actor/TCP/MCP
owners. Gameplay, cooking, admission and durable publication stay in Bend.
"""
from __future__ import annotations

import argparse
import base64
import copy
import json
import sys
import zipfile
from pathlib import Path

import test_playable_client_actor004_boundary as B
import reference_cooking_block_entity_codec as JavaBody
from reference_inventory import canonical

A, P, R, S, H = B.A, B.P, B.R, B.S, B.H
ROOT = A.ROOT
WORK = ROOT / 'build/playable-client-cooking'
REFERENCES = tuple(ROOT / ('reference/' + name + '.json') for name in
    ('cooking_block_entity_codec', 'furnace_authority', 'cooking_recipe', 'cooking_world'))
POSITION = ('minecraft:overworld', 12, 1, 12)
WRAPPER = 'bendex:local-player-cooking-record'
EFFECTS_ROOT = 'bendex:cooking-effects'


def runtime_pins():
    paths = (*REFERENCES, B.JAR, S.P.OFFICIAL, S.TABLE, B.FACTS, B.TABLE,
             ROOT / 'reference/block_light_registry.tsv',
             ROOT / 'reference/cooking_world_bindings.tsv')
    return {str(path): R.pin(path) for path in paths}


def independent_expectations():
    """Read actual Java receipts/JAR only; no compiler, Java or native process."""
    codec, furnace, recipes, bindings = [json.loads(path.read_bytes()) for path in REFERENCES]
    S.require(all(value['pin'] == '26.3' for value in (codec, furnace, recipes, bindings)),
              'Pinned cooking Java reference version')
    S.require(codec['inputs_sha256'] == S.sha(canonical(JavaBody.inputs())),
              'Retained physical Java fixture inputs changed')
    jar_pin = R.pin(B.JAR)
    S.require(furnace['provenance']['client']['sha256'] == jar_pin['sha256'] ==
              recipes['provenance']['client']['sha256'], 'Actual pinned original JAR identity')
    step = next(row for row in furnace['cases'] if row['id'] == 'lit_progress')['steps'][0]
    after = step['after']
    S.require(after['cookingTimer'] == 41 and after['cookingTotalTime'] == 200 and
              after['litTimeRemaining'] == 9 and after['litTotalTime'] == 10 and
              after['speed_bits'] == 0x3f800000 and not step['dirty'] and
              step['lit_change'] is None and not step['drops'],
              'Independent effect-free in-progress Java furnace tick changed')
    recipe = next(row for row in recipes['recipes'] if row['id'] == 'minecraft:cooked_beef')
    S.require(recipe['accepted'] and recipe['cooking_time'] == 200 and
              recipe['output']['id'] == 'minecraft:cooked_beef' and
              recipe['output']['count'] == 1 and any(row['matches'] for row in recipe['matches']),
              'Actual Java beef smelting receiver changed')
    with zipfile.ZipFile(B.JAR) as jar:
        source = json.loads(jar.read('data/minecraft/recipe/cooked_beef.json'))
    S.require(source['type'] == 'minecraft:smelting' and source['ingredient'] == 'minecraft:beef'
              and source['result']['id'] == 'minecraft:cooked_beef'
              and source.get('cookingtime', 200) == 200, 'Actual original-JAR beef recipe changed')
    unknown = next(row for row in JavaBody.inputs() if row['id'] == 'unknown_root_field')
    accepted = next(row for row in codec['observations'] if row['id'] == 'unknown_root_field')
    S.require(accepted['status'] == 'accepted', 'Java unknown-root physical receiver acceptance')
    basic = next(row for row in codec['observations'] if row['id'] == 'slots_basic')
    S.require(basic['status'] == 'accepted' and
              all(any(slot and slot['id'] == name and slot['patch'] == {}
                      for slot in basic['state']['slots'])
                  for name in ('minecraft:beef', 'minecraft:coal')),
              'Actual Java default beef/coal physical patches remain empty')
    extras = S.N.parse(base64.b64decode(unknown['bytes'])).value.payload
    lit = next(row for row in bindings['bindings'] if row['block'] == 'minecraft:furnace'
               and row['properties']['facing'] == 'north' and row['lit'])
    palette, identity, count = B.palette_and_registry()
    S.require(identity == bindings['registry_identity'] and count == bindings['state_count'],
              'Actual loaded registry and cooking state bindings disagree')
    return {'palette': palette, 'identity': identity, 'count': count,
            'lit': lit['state'], 'unlit': lit['unlit_state'], 'extras': extras,
            'java_tick': {'reference': str(REFERENCES[1]), 'case': 'lit_progress', 'step': 0},
            'java_recipe': {'reference': str(REFERENCES[2]), 'id': recipe['id']},
            'java_body': {'reference': str(REFERENCES[0]), 'case': unknown['id']},
            'inference': 'Apply the observed effect-free timer/burn progression to the actual '
                         'Java-decoded beef recipe with the same 200-tick cooking time. The '
                         'retained furnace tick uses a controlled recipe; this composed expectation '
                         'is not a retained full-world Java beef tick observation.'}


def body_root(facts, *, progress=40, remaining=10):
    # Known fields use the physical Java receiver's tag types. Exact extra member
    # order and duplicate names/raw bits are storage requirements, not a base
    # BlockEntity CustomName/Lock interpretation claim.
    items = tuple(JavaBody.item(index, name, 2) for index, name in
                  ((0, 'minecraft:beef'), (1, 'minecraft:coal')))
    known = S.WC.compound([
        ('cooking_time_spent', S.WC.integer(progress)),
        ('cooking_total_time', S.WC.integer(200)),
        ('lit_time_remaining', S.WC.integer(remaining)),
        ('lit_total_time', S.WC.integer(10)),
        ('speed_multiplier', S.N.Value(5, 0x3f800000)),
        ('Items', S.N.Value(9, (10, items))), ('RecipesUsed', S.WC.compound([]))])
    extras = (*facts['extras'], (S.N.text('probe:extra'), S.N.Value(5, 0x7fa12345)),
              (S.N.text('probe:extra'), S.N.Value(4, 0x80000001ffffffff)))
    name = (*S.N.text('probe:physical-cooker'), 0, 0xd800)
    return S.N.RootTag(name, S.N.Value(10, (*known.payload, *extras)))


def fresh_body():
    # The recreated empty furnace has no prior physical Details. Empty Items
    # is TAG_End-list framing, matching the actual physical receiver encoder.
    return S.N.encode_root(S.N.RootTag((), S.WC.compound([
        ('cooking_time_spent', S.WC.integer(0)), ('cooking_total_time', S.WC.integer(0)),
        ('lit_time_remaining', S.WC.integer(0)), ('lit_total_time', S.WC.integer(0)),
        ('speed_multiplier', S.N.Value(5, 0x3f800000)),
        ('Items', S.N.Value(9, (0, ()))), ('RecipesUsed', S.WC.compound([]))])))


def removal_pending():
    # Retained Java slots_basic observes empty physical patches for these
    # defaults. The inventory's unchanged-default identity is the empty string.
    # Safe delivery consumes OwnerReset but retains every Drop call, including
    # the empty output, until a real item/entity/RNG owner exists.
    return ((0, B.Inventory.stack('minecraft:beef', 2)),
            (1, B.Inventory.stack('minecraft:coal', 2)), (2, None))


def pending_bytes(pending):
    dimension, x, y, z = POSITION
    point = S.WC.compound([('dimension', S.N.Value(11, tuple(map(ord, dimension)))),
        ('x', S.WC.integer(x)), ('y', S.WC.integer(y)), ('z', S.WC.integer(z))])
    values = []
    for slot, item in pending:
        stack = S.WC.compound([]) if item is None else S.WC.compound([
            ('id', S.N.Value(11, tuple(map(ord, item['id'])))),
            ('components', S.N.Value(11, tuple(map(ord, item['components'])))),
            ('count', S.WC.integer(item['count']))])
        values.append(S.WC.compound([('kind', S.WC.integer(1)), ('position', point),
            ('payload', S.WC.compound([('slot', S.WC.integer(slot)), ('item', stack)]))]))
    return S.N.encode_root(S.N.RootTag(S.N.text(EFFECTS_ROOT), S.WC.compound([
        ('format', S.WC.integer(1)), ('effects', S.N.Value(9, (10, tuple(values))))])))


def read_pending(data):
    root = S.N.parse(data)
    S.require(root.name == S.N.text(EFFECTS_ROOT), 'Exact recovery root')
    fields = S.WC.fields(root.value, ('format', 'effects'))
    S.require(S.WC.uint(fields['format']) == 1 and fields['effects'].kind == 9 and
              fields['effects'].payload[0] == 10, 'Exact ordered recovery framing')
    pending = []
    for value in fields['effects'].payload[1]:
        effect = S.WC.fields(value, ('kind', 'position', 'payload'))
        point = S.WC.fields(effect['position'], ('dimension', 'x', 'y', 'z'))
        S.require(S.WC.uint(effect['kind']) == 1 and point['dimension'].kind == 11 and
                  (''.join(map(chr, point['dimension'].payload)),
                   *(S.WC.uint(point[k]) for k in ('x', 'y', 'z'))) == POSITION,
                  'Actual ordered removal Drop intent and position')
        payload = S.WC.fields(effect['payload'], ('slot', 'item'))
        stack = payload['item']
        S.require(stack.kind == 10, 'Recovery item is Compound')
        item = None
        if stack.payload:
            members = S.WC.fields(stack, ('id', 'components', 'count'))
            S.require(members['id'].kind == members['components'].kind == 11,
                      'Raw recovery item identity words')
            item = {'id': ''.join(map(chr, members['id'].payload)),
                    'components': ''.join(map(chr, members['components'].payload)),
                    'count': S.WC.uint(members['count'])}
        pending.append((S.WC.uint(payload['slot']), item))
    return tuple(pending)


def wrapper(player, body, pending=()):
    dimension, x, y, z = POSITION
    location = S.WC.compound([('dimension', S.WC.txt(dimension)),
        ('x', S.WC.integer(x)), ('y', S.WC.integer(y)), ('z', S.WC.integer(z)),
        ('body', S.N.Value(7, body))])
    fields = [('format', S.WC.integer(2 if pending else 1)), ('player', S.N.Value(7, player)),
              ('bodies', S.N.Value(9, (10, (location,))))]
    if pending:
        fields.append(('effects', S.N.Value(7, pending_bytes(pending))))
    return S.N.encode_root(S.N.RootTag(S.N.text(WRAPPER), S.WC.compound(fields)))


def bundle(world, highwater, record, full, body, pending=()):
    ordinary = S.N.parse(B.bundle(world, highwater, record, full, ''))
    extra = S.WC.fields(dict(ordinary.value.payload)[S.N.text('extension')], S.EXTENSION_FIELDS)
    extension = S.WC.compound([('namespace', extra['namespace']), ('schema', extra['schema']),
                              ('payload', S.N.Value(7, wrapper(bytes(extra['payload'].payload), body, pending)))])
    return S.N.encode_root(S.N.RootTag(ordinary.name, S.N.Value(10, tuple(
        (name, extension if name == S.N.text('extension') else value)
        for name, value in ordinary.value.payload))))


def legacy_generation():
    # Production WGCodec.root(W.Unspecified{}), not absent or dummy metadata.
    # Scene.ensure_legacy retains the loaded sole section. This consumer makes
    # no generated-terrain claim and preserves these exact WG bytes on save.
    return S.N.encode_root(S.N.RootTag(S.N.text('bendex:world-generation-settings'),
        S.WC.compound([('format', S.WC.integer(1)), ('kind', S.WC.txt('unspecified')),
                       ('payload', S.WC.compound([]))])))


def fixture(facts):
    world = S.WC.empty_world(facts['count'], facts['identity'])
    world['daylight'] = False
    cells = [facts['palette']['minecraft:air']] * 4096
    cells[:256] = [facts['palette']['minecraft:stone']] * 256
    world['sections'] = [{'key': S.BASE.section_key(0, 0, 0), 'cells': tuple(cells)}]
    S.BASE.set_block(world, *POSITION[1:], facts['lit'])
    record = A.playable_spawn((8.5, 1.0, 8.5))
    full = {'main': B.Inventory.empty(creative=True), 'equipment': [None] * 7,
            'status': dict(zip(B.Inventory.STATUS_FIELDS,
                (True, True, False, 1036831949, 1028443341), strict=True)),
            'generation': legacy_generation()}
    physical = S.N.encode_root(body_root(facts))
    return world, record, full, physical, bundle(world, 40, record, full, physical)


def projection(data, facts):
    outer = S.N.Reader(data, max_bytes=33624064, max_depth=16,
                       max_elements=33624064).root()
    S.require(outer.name == S.N.text('bendex:bundle'), 'Atomic envelope root')
    fields = S.WC.fields(outer.value, S.BUNDLE_FIELDS)
    S.require(S.WC.uint(fields['format']) == 1 and
              S.WC.scalar_text(fields['minecraft']) == '26.3' and
              S.WC.scalar_text(fields['registry']) == facts['identity'], 'Atomic envelope identity')
    world = S.WC.validate(S.N.parse(fields['core'].payload), facts['count'], facts['identity'])
    extension = S.WC.fields(fields['extension'], S.EXTENSION_FIELDS)
    S.require(S.WC.scalar_text(extension['namespace']) == S.NAMESPACE and
              S.WC.uint(extension['schema']) == 1, 'Existing atomic codec namespace/schema')
    nested = S.N.parse(bytes(extension['payload'].payload))
    S.require(nested.name == S.N.text(WRAPPER), 'Physical cooking wrapper root')
    version = S.WC.uint(dict(nested.value.payload)[S.N.text('format')])
    S.require(version in (1, 2), 'Existing or recovery cooking wrapper')
    saved = S.WC.fields(nested.value, ('format', 'player', 'bodies') +
                       (('effects',) if version == 2 else ()))
    pending = ()
    if version == 2:
        S.require(saved['effects'].kind == 7, 'Recovery queue is complete ByteArray')
        pending = read_pending(bytes(saved['effects'].payload))
        S.require(bool(pending), 'Nonempty recovery wrapper queue')
    S.require(saved['player'].kind == 7 and
              saved['bodies'].kind == 9 and saved['bodies'].payload[0] == 10 and
              len(saved['bodies'].payload[1]) == 1, 'Complete one-body wrapper')
    body = S.WC.fields(saved['bodies'].payload[1][0], ('dimension', 'x', 'y', 'z', 'body'))
    S.require((S.WC.scalar_text(body['dimension']), *(S.WC.uint(body[k]) for k in ('x', 'y', 'z')))
              == POSITION and body['body'].kind == 7, 'Actual keyed physical body location')
    player, full = B.Inventory.parse_inventory_full(bytes(saved['player'].payload))
    return world, player, full, bytes(body['body'].payload), S.WC.uint(fields['peer_highwater']), pending


def acknowledge(client, path, facts, world, record, full, highwater, expected_body, pending, directory, label):
    reply = client.call('world.save', {})
    actual = path.read_bytes()
    expected = bundle(world, highwater, record, full, expected_body, pending)
    observed_world, player, observed_full, physical, observed_peer, observed_pending = projection(actual, facts)
    S.require(reply == {'status': 'durable', 'published': True, 'durable': True,
        'bytes': len(actual), 'peer_highwater': highwater} and actual == expected,
        'Complete atomic Core/player/inventory/status/generation/body/Details/intent bytes: ' + label)
    S.require(S.P.canonical_expected(observed_world) == S.P.canonical_expected(world) and
              player == S.local_bytes(record) and observed_full == full and
              physical == expected_body and observed_peer == highwater and observed_pending == pending,
              'Independent physical full-envelope projection: ' + label)
    receipt = {'label': label, 'reply': reply, 'bytes': len(actual), 'sha256': S.sha(actual),
               'expected_sha256': S.sha(expected), 'body_sha256': S.sha(physical),
               'full_atomic_bytes_equal': True, 'exact_physical_body_bytes_equal': True,
               'pending_ordered_drop_slots': [slot for slot, item in observed_pending],
               'pending_sha256': S.sha(pending_bytes(observed_pending)) if observed_pending else None}
    S.exclusive_json(directory / (label + '.json'), receipt)
    return actual, receipt


def scenario(directory, binary, bridge, generation):
    directory.mkdir(exist_ok=False)
    facts = independent_expectations()
    world, record, full, physical, initial = fixture(facts)
    path = directory / 'cooking.nbt'
    path.write_bytes(initial)
    saves = []
    actor = A.PlayableBackend(directory / 'loaded-startup', binary, path, bridge)
    try:
        raw, ping = actor.tcp(True)
        developer, mping = actor.mcp()
        highwater = max(ping['peer'], mping['peer'])
        names = [tool['name'] for tool in developer.request('tools/list')['result']['tools']]
        S.require({'simulation.step', 'world.save', 'world.block.set', 'world.block.get',
                   'player.inspect'} <= set(names), 'Actual cooking consumer operation hooks')
        S.require(raw.call('world.clock') == S.P.clock(world), 'Startup discovery never ticks sole Core')
        S.inspect(raw, record)
        _, receipt = acknowledge(developer, path, facts, world, record, full, highwater,
                                  physical, (), directory, 'loaded-physical-startup')
        saves.append(receipt)
        raw.call('simulation.step', {'ticks': 1})
        S.BASE.apply_tick(world)
        record = S.decode_local(bytes(raw.call('player.inspect', {})['nbt_bytes']))
        S.require(record.count == 1 and raw.call('world.clock') == S.P.clock(world),
                  'One actual sole-Core scheduled cooking/player tick')
        acknowledged, receipt = acknowledge(developer, path, facts, world, record, full,
            highwater, S.N.encode_root(body_root(facts, progress=41, remaining=9)),
            (), directory, 'effect-free-furnace-tick')
        saves.append(receipt)
        transient_world = copy.deepcopy(world)
        S.BASE.apply_tick(transient_world)
        S.require(raw.call('simulation.step', {'ticks': 1}) == S.P.clock(transient_world) and
                  raw.call('world.clock') == S.P.clock(transient_world) and
                  S.decode_local(bytes(raw.call('player.inspect', {})['nbt_bytes'])).count == 2 and
                  path.read_bytes() == acknowledged,
                  'Unsaved sole-Core/player tick advanced while acknowledged file stayed exact')
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop(kill=not actor.stopped)

    actor = A.PlayableBackend(directory / 'cold-restore', binary, path, bridge)
    try:
        raw, ping = actor.tcp(True)
        S.require(raw.call('world.clock') == S.P.clock(world) and path.read_bytes() == acknowledged,
                  'SIGKILL/cold restore acknowledged Core tick and physical save')
        S.inspect(raw, record)
        _, receipt = acknowledge(raw, path, facts, world, record, full, ping['peer'],
            S.N.encode_root(body_root(facts, progress=41, remaining=9)),
            (), directory, 'cold-physical-restore')
        saves.append(receipt)
        # Actual accepted teardown and fresh replacement reach CW OwnerReset.
        # Unsupported Drop calls remain the atomic recovery queue; physical
        # body bytes expose the fresh incarnation's cleared keyed Details.
        tick = world['tick'] + 1
        for state in (facts['palette']['minecraft:air'], facts['unlit']):
            S.queue_set(raw, world, POSITION, state, tick)
        raw.call('simulation.step', {'ticks': 1})
        S.BASE.apply_tick(world)
        S.require(raw.call('world.clock') == S.P.clock(world) and
                  raw.call('world.block.get', dict(zip(('dimension', 'x', 'y', 'z'), POSITION)))
                  == {'state': facts['unlit']}, 'Actual accepted remove/recreate sole-Core edits')
        record = S.decode_local(bytes(raw.call('player.inspect', {})['nbt_bytes']))
        S.require(record.count == 2, 'Reset tick completes common/player once before delivery')
        reset_acknowledged, receipt = acknowledge(raw, path, facts, world, record, full,
            ping['peer'], fresh_body(), removal_pending(), directory, 'owner-reset-atomic-recovery')
        saves.append(receipt)
        S.require(raw.call('simulation.step', {'ticks': 1}) == S.P.clock(world) and
                  path.read_bytes() == reset_acknowledged,
                  'Undelivered Drop queue blocks next Core tick without loss')
        S.inspect(raw, record)
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop(kill=not actor.stopped)

    actor = A.PlayableBackend(directory / 'cold-pending-restore', binary, path, bridge)
    try:
        raw, ping = actor.tcp(True)
        S.require(raw.call('world.clock') == S.P.clock(world) and
                  path.read_bytes() == reset_acknowledged,
                  'Second SIGKILL/cold restore preserves reset Core/body/ordered Drop queue')
        S.inspect(raw, record)
        S.require(raw.call('simulation.step', {'ticks': 1}) == S.P.clock(world),
                  'Restored unsupported Drop queue blocks the next Core tick')
        S.inspect(raw, record)
        _, receipt = acknowledge(raw, path, facts, world, record, full, ping['peer'],
            fresh_body(), removal_pending(), directory, 'cold-pending-atomic-recovery')
        saves.append(receipt)
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop()
    result = {'status': 'PASS_NARROW', 'generation': f'Actor004/producer{generation:03}', 'backends': 3,
        'world_generation_metadata': 'Unspecified; existing loaded legacy terrain retained',
        'world_generation_sha256': S.sha(full['generation']),
        'actual_TCP_MCP': True, 'furnace_scene_Core_ticks_before_first_kill': 2,
        'first_tick_physical_furnace_progression_observed': True, 'reset_tick_calls': 1,
        'progression_acknowledged_tick': 1, 'final_acknowledged_tick': world['tick'],
        'blocked_next_tick_requests': 2,
        'atomic_saves': saves, 'actual_SIGKILL_cold_restores': 2,
        'OwnerReset_Core_remove_recreate_observed': True,
        'OwnerReset_saved_keyed_Details_clear_observed': True,
        'ordered_pending_Drops_atomic_save_and_cold_restore_observed': True,
        'pending_Drops_gate_next_Core_tick_observed': True,
        'missing_consumer': 'No real item-entity/XP-orb/level-RNG/comparator publishers exist. '
                            'Unsupported ordered Drop calls, including empty output, remain '
                            'saved/restored intents; no host simulation or effects drain substitutes.',
        'tick_expectation_scope': facts['inference'], 'actual_operation_names': names,
        'scope': 'Current real actor startup/sole-Core effect-free furnace progression/physical '
                 'Details atomic save and cold restoration. Reset physical Details clearing and '
                 'ordered unsupported intent recovery are tested; completion/drop/XP delivery, cooking UI, visible '
                 'native client controls and whole-game parity remain unverified.'}
    S.exclusive_json(directory / 'summary.json', result)
    return result


def child(directory, generation):
    build = B.artifact()
    S.require(build['generation'] == f'immutable-actor004/producer{generation:03}',
              'Explicit selected actor generation only')
    before = runtime_pins()
    journal = directory / 'owned-groups.jsonl'
    journal.touch(exist_ok=False)
    bridge, _ = P.retained_bridge()
    def identity():
        S.require(R.pin(A.ACTOR) == build['binary'], 'Selected actor binary changed')
    with H.bindings(S, {'SERVER': A.ACTOR, 'ROOT': ROOT, 'activation': identity,
                        'OWNED_GROUPS': journal}):
        result = scenario(directory / 'actors', A.ACTOR, bridge, generation)
        S.require(runtime_pins() == before, 'Pinned cooking consumer inputs changed')
        identity()
    print(json.dumps({'status': result['status'], 'atomic_saves': len(result['atomic_saves'])}), flush=True)


def fresh_directory():
    WORK.mkdir(exist_ok=True)
    for number in range(1, 10000):
        directory = WORK / f'{number:03}'
        try:
            directory.mkdir()
            return number, directory
        except FileExistsError:
            continue
    raise RuntimeError('No unused cooking consumer output directory')


def prepare(generation):
    facts = independent_expectations()
    world, record, full, body, data = fixture(facts)
    observed_world, player, observed_full, physical, peer, pending = projection(data, facts)
    S.require(S.P.canonical_expected(observed_world) == S.P.canonical_expected(world) and
              player == S.local_bytes(record) and observed_full == full and
              physical == body and peer == 40 and not pending,
              'Independent complete legacy file-only cooking fixture roundtrip')
    reset_world = copy.deepcopy(world)
    S.BASE.set_block(reset_world, *POSITION[1:], facts['unlit'])
    recovery = bundle(reset_world, 40, record, full, fresh_body(), removal_pending())
    recovered_world, player, recovered_full, physical, peer, pending = projection(recovery, facts)
    S.require(S.P.canonical_expected(recovered_world) == S.P.canonical_expected(reset_world) and
              player == S.local_bytes(record) and recovered_full == full and
              physical == fresh_body() and peer == 40 and pending == removal_pending(),
              'Independent complete fresh-body/ordered pending recovery fixture roundtrip')
    number, directory = fresh_directory()
    (directory / 'seed.nbt').write_bytes(data)
    (directory / 'reset-recovery.nbt').write_bytes(recovery)
    value = {'status': 'PREPARED; actual native behavior pending', 'native_executed': False,
        'runtime_inputs': runtime_pins(), 'runner': R.pin(Path(__file__)),
        'actor_generation': generation, 'actor_build_directory': str(A.WORK),
        'seed': R.pin(directory / 'seed.nbt'), 'sections': 1, 'cooking_bodies': 1,
        'recovery_fixture': R.pin(directory / 'reset-recovery.nbt'),
        'pending_ordered_drop_slots': [slot for slot, item in removal_pending()],
        'fresh_body_sha256': S.sha(fresh_body()),
        'pending_effects_sha256': S.sha(pending_bytes(removal_pending())),
        'world_generation_metadata': 'Unspecified; existing loaded legacy terrain retained',
        'world_generation_sha256': S.sha(full['generation']),
        'bootstrap_budget': 4100, 'initial_body_sha256': S.sha(body),
        'java_expectations': {key: facts[key] for key in
            ('java_tick', 'java_recipe', 'java_body', 'inference')},
        'actual_hooks': ['Entry startup CookingStorage body admission', 'simulation.step',
                        'world.save', 'world.block.set', 'world.block.get', 'player.inspect'],
        'missing_consumers': ['real item-entity/XP-orb/level-RNG/comparator publishers',
            'cooking UI and physical effect delivery'],
        'planned_native_argv': [sys.executable, '-B', str(Path(__file__)),
                                '--actor-generation', str(generation), '--native'],
        'planned_scope': 'Three paused selected-generation actors, five complete atomic save byte comparisons, '
                        'one saved in-progress tick, one unsaved tick followed by actual SIGKILL/cold '
                        'restoration, accepted remove/recreate clearing physical Details, atomically '
                        'retained ordered unsupported Drop intents, second SIGKILL/cold restore '
                        'and pending-intent gating of the next Core tick.'}
    R.write(directory / 'prepared.json', value, True)
    output = ROOT / f'evidence/playable-client-cooking-prepared-{number:03}.json'
    R.write(output, value, True)
    print(json.dumps({'status': value['status'], 'evidence': str(output)}), flush=True)


def native(generation):
    build = B.artifact()
    S.require(build['generation'] == f'immutable-actor004/producer{generation:03}',
              'Explicit selected actor generation only')
    number, directory = fresh_directory()
    before, own_pin = runtime_pins(), R.pin(Path(__file__))
    S.exclusive_json(directory / 'inputs.json', {'binary': build['binary'],
        'build': R.pin(A.WORK / 'native-build.json'), 'source_map': build['source_map'],
        'runtime': before, 'runner': own_pin})
    bridge, _ = P.retained_bridge()
    with H.bindings(R, {'WORK': directory}):
        try:
            process = R.bounded([sys.executable, '-B', str(Path(__file__)),
                                 '--actor-generation', str(generation), '--_child', str(directory)],
                                 600, 'execution')
        finally:
            B.descendant_cleanup(directory, bridge)
    R.process_ok(process)
    S.require(runtime_pins() == before and R.pin(Path(__file__)) == own_pin,
              'Native cooking consumer inputs or runner changed')
    summary = json.loads((directory / 'actors/summary.json').read_bytes())
    output = ROOT / f'evidence/playable-client-cooking-native-{number:03}.json'
    R.write(output, {'status': summary['status'], 'binary': build['binary'],
        'build': R.pin(A.WORK / 'native-build.json'), 'summary': summary,
        'summary_pin': R.pin(directory / 'actors/summary.json'),
        'process': R.pin(directory / 'execution/result.full.json'),
        'cleanup': R.pin(directory / 'cleanup.json')}, True)
    print(json.dumps({'status': summary['status'], 'evidence': str(output)}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--actor-generation', type=int,
                        help='required explicit immutable producer generation; no fallback')
    parser.add_argument('--expectations', action='store_true', help='file-only fixture preparation')
    parser.add_argument('--native', action='store_true', help='consume the selected successful actor; never build')
    parser.add_argument('--_child', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not (args._child or args.native or args.expectations):
        parser.print_help()
        return
    if args.actor_generation is None or args.actor_generation < 19:
        parser.error('--actor-generation must explicitly select producer19 or later with recovery support')
    if sum((bool(args._child), args.native, args.expectations)) != 1:
        parser.error('select exactly one mode')
    selected = ROOT / f'build/compiler-producer-diagnostic-{args.actor_generation:03}'
    with H.bindings(A, {'WORK': selected, 'SOURCE': selected / 'source', 'ACTOR': selected / 'actor'}):
        if args._child:
            child(args._child, args.actor_generation)
        elif args.native:
            native(args.actor_generation)
        else:
            prepare(args.actor_generation)


if __name__ == '__main__':
    main()
