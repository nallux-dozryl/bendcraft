#!/usr/bin/env python3
"""Small real Actor018 cooking/startup/atomic-save consumer; never builds.

The file-only mode constructs a one-section physical save from retained pinned
Java receiver observations. Native mode uses the existing bounded actor/TCP/MCP
owners. Gameplay, cooking, admission and durable publication stay in Bend.
"""
from __future__ import annotations

import argparse
import base64
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


def wrapper(player, body):
    dimension, x, y, z = POSITION
    location = S.WC.compound([('dimension', S.WC.txt(dimension)),
        ('x', S.WC.integer(x)), ('y', S.WC.integer(y)), ('z', S.WC.integer(z)),
        ('body', S.N.Value(7, body))])
    return S.N.encode_root(S.N.RootTag(S.N.text(WRAPPER), S.WC.compound([
        ('format', S.WC.integer(1)), ('player', S.N.Value(7, player)),
        ('bodies', S.N.Value(9, (10, (location,))))])))


def bundle(world, highwater, record, full, body):
    ordinary = S.N.parse(B.bundle(world, highwater, record, full, ''))
    extra = S.WC.fields(dict(ordinary.value.payload)[S.N.text('extension')], S.EXTENSION_FIELDS)
    extension = S.WC.compound([('namespace', extra['namespace']), ('schema', extra['schema']),
                              ('payload', S.N.Value(7, wrapper(bytes(extra['payload'].payload), body)))])
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
    saved = S.WC.fields(nested.value, ('format', 'player', 'bodies'))
    S.require(S.WC.uint(saved['format']) == 1 and saved['player'].kind == 7 and
              saved['bodies'].kind == 9 and saved['bodies'].payload[0] == 10 and
              len(saved['bodies'].payload[1]) == 1, 'Complete one-body wrapper')
    body = S.WC.fields(saved['bodies'].payload[1][0], ('dimension', 'x', 'y', 'z', 'body'))
    S.require((S.WC.scalar_text(body['dimension']), *(S.WC.uint(body[k]) for k in ('x', 'y', 'z')))
              == POSITION and body['body'].kind == 7, 'Actual keyed physical body location')
    player, full = B.Inventory.parse_inventory_full(bytes(saved['player'].payload))
    return world, player, full, bytes(body['body'].payload), S.WC.uint(fields['peer_highwater'])


def acknowledge(client, path, facts, world, record, full, highwater, progress, remaining, directory, label):
    reply = client.call('world.save', {})
    actual = path.read_bytes()
    expected_body = S.N.encode_root(body_root(facts, progress=progress, remaining=remaining))
    expected = bundle(world, highwater, record, full, expected_body)
    observed_world, player, observed_full, physical, observed_peer = projection(actual, facts)
    S.require(reply == {'status': 'durable', 'published': True, 'durable': True,
        'bytes': len(actual), 'peer_highwater': highwater} and actual == expected,
        'Complete atomic Core/player/inventory/status/generation/body/Details bytes: ' + label)
    S.require(S.P.canonical_expected(observed_world) == S.P.canonical_expected(world) and
              player == S.local_bytes(record) and observed_full == full and
              physical == expected_body and observed_peer == highwater,
              'Independent physical full-envelope projection: ' + label)
    receipt = {'label': label, 'reply': reply, 'bytes': len(actual), 'sha256': S.sha(actual),
               'expected_sha256': S.sha(expected), 'body_sha256': S.sha(physical),
               'full_atomic_bytes_equal': True, 'exact_root_name_extras_duplicates_raw_bits': True}
    S.exclusive_json(directory / (label + '.json'), receipt)
    return actual, receipt


def scenario(directory, binary, bridge):
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
                                  40, 10, directory, 'loaded-physical-startup')
        saves.append(receipt)
        raw.call('simulation.step', {'ticks': 1})
        S.BASE.apply_tick(world)
        record = S.decode_local(bytes(raw.call('player.inspect', {})['nbt_bytes']))
        S.require(record.count == 1 and raw.call('world.clock') == S.P.clock(world),
                  'One actual sole-Core scheduled cooking/player tick')
        acknowledged, receipt = acknowledge(developer, path, facts, world, record, full,
            highwater, 41, 9, directory, 'effect-free-furnace-tick')
        saves.append(receipt)
        raw.call('simulation.step', {'ticks': 1})
        S.require(path.read_bytes() == acknowledged, 'Unsaved in-progress tick changed acknowledged file')
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
                                  41, 9, directory, 'cold-physical-restore')
        saves.append(receipt)
        durable = path.read_bytes()
        # Actual accepted teardown and fresh replacement reach CW OwnerReset.
        # The transport has no effect-drain or keyed-Details inspection consumer;
        # asserting save refusal protects the required undelivered intents.
        tick = world['tick'] + 1
        for state in (facts['palette']['minecraft:air'], facts['unlit']):
            S.queue_set(raw, world, POSITION, state, tick)
        raw.call('simulation.step', {'ticks': 1})
        S.BASE.apply_tick(world)
        S.require(raw.call('world.clock') == S.P.clock(world) and
                  raw.call('world.block.get', dict(zip(('dimension', 'x', 'y', 'z'), POSITION)))
                  == {'state': facts['unlit']}, 'Actual accepted remove/recreate sole-Core edits')
        refusal = raw.call('world.save', {}, fault='SaveEncodingFailed')
        S.require(refusal['error']['message'] == 'local-cooking:save-undelivered-effects' and
                  path.read_bytes() == durable, 'OwnerReset/drop intents refuse lossy publication')
        S.exclusive_json(directory / 'owner-reset-save-refusal.json', refusal)
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop()
    result = {'status': 'PASS_NARROW', 'generation': 'Actor004/producer018', 'backends': 2,
        'world_generation_metadata': 'Unspecified; existing loaded legacy terrain retained',
        'world_generation_sha256': S.sha(full['generation']),
        'actual_TCP_MCP': True, 'scheduled_furnace_ticks': 2, 'acknowledged_tick': 1,
        'atomic_saves': saves, 'actual_SIGKILL_cold_restore': True,
        'OwnerReset_Core_remove_recreate_observed': True,
        'OwnerReset_keyed_Details_clear_observed': False,
        'OwnerReset_save_refusal_preserves_undelivered_intents': True,
        'missing_consumer': 'No public cooking body inspect/load or effects-drain command; '
                            'no production Session.cooking_take_effects caller. Keyed extras '
                            'after reset cannot be inspected through the current transport.',
        'tick_expectation_scope': facts['inference'], 'actual_operation_names': names,
        'scope': 'Current real actor startup/sole-Core effect-free furnace progression/physical '
                 'Details atomic save and cold restoration. Reset save refusal is tested; '
                 'post-reset Details clearing, completion/drop/XP delivery, cooking UI, visible '
                 'native client controls and whole-game parity remain unverified.'}
    S.exclusive_json(directory / 'summary.json', result)
    return result


def child(directory):
    build = B.artifact()
    S.require(A.WORK.name == 'compiler-producer-diagnostic-018' and
              build['generation'] == 'immutable-actor004/producer018', 'Actual Actor018 only')
    before = runtime_pins()
    journal = directory / 'owned-groups.jsonl'
    journal.touch(exist_ok=False)
    bridge, _ = P.retained_bridge()
    def identity():
        S.require(R.pin(A.ACTOR) == build['binary'], 'Actor018 binary changed')
    with H.bindings(S, {'SERVER': A.ACTOR, 'ROOT': ROOT, 'activation': identity,
                        'OWNED_GROUPS': journal}):
        result = scenario(directory / 'actors', A.ACTOR, bridge)
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


def prepare():
    facts = independent_expectations()
    world, record, full, body, data = fixture(facts)
    observed_world, player, observed_full, physical, peer = projection(data, facts)
    S.require(S.P.canonical_expected(observed_world) == S.P.canonical_expected(world) and
              player == S.local_bytes(record) and observed_full == full and
              physical == body and peer == 40, 'Independent complete file-only cooking fixture roundtrip')
    number, directory = fresh_directory()
    (directory / 'seed.nbt').write_bytes(data)
    value = {'status': 'PREPARED; actual native behavior pending', 'native_executed': False,
        'runtime_inputs': runtime_pins(), 'runner': R.pin(Path(__file__)),
        'seed': R.pin(directory / 'seed.nbt'), 'sections': 1, 'cooking_bodies': 1,
        'world_generation_metadata': 'Unspecified; existing loaded legacy terrain retained',
        'world_generation_sha256': S.sha(full['generation']),
        'bootstrap_budget': 4100, 'initial_body_sha256': S.sha(body),
        'java_expectations': {key: facts[key] for key in
            ('java_tick', 'java_recipe', 'java_body', 'inference')},
        'actual_hooks': ['Entry startup CookingStorage body admission', 'simulation.step',
                        'world.save', 'world.block.set', 'world.block.get', 'player.inspect'],
        'missing_consumers': ['public cooking body load/save/inspect commands',
            'production Session.cooking_take_effects caller',
            'public post-OwnerReset keyed Details observation'],
        'planned_native_argv': [sys.executable, '-B', str(Path(__file__)), '--native'],
        'planned_scope': 'Two paused Actor018 processes, three complete atomic save byte comparisons, '
                        'one saved in-progress tick, one unsaved tick followed by actual SIGKILL/cold '
                        'restoration, accepted remove/recreate and truthful undelivered-intent save refusal.'}
    R.write(directory / 'prepared.json', value, True)
    output = ROOT / f'evidence/playable-client-cooking-prepared-{number:03}.json'
    R.write(output, value, True)
    print(json.dumps({'status': value['status'], 'evidence': str(output)}), flush=True)


def native():
    build = B.artifact()
    S.require(A.WORK.name == 'compiler-producer-diagnostic-018' and
              build['generation'] == 'immutable-actor004/producer018', 'Actual Actor018 only')
    number, directory = fresh_directory()
    before, own_pin = runtime_pins(), R.pin(Path(__file__))
    S.exclusive_json(directory / 'inputs.json', {'binary': build['binary'],
        'build': R.pin(A.WORK / 'native-build.json'), 'source_map': build['source_map'],
        'runtime': before, 'runner': own_pin})
    bridge, _ = P.retained_bridge()
    with H.bindings(R, {'WORK': directory}):
        try:
            process = R.bounded([sys.executable, '-B', str(Path(__file__)),
                                 '--_child', str(directory)], 360, 'execution')
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
    parser.add_argument('--expectations', action='store_true', help='file-only fixture preparation')
    parser.add_argument('--native', action='store_true', help='consume successful current Actor018; never build')
    parser.add_argument('--_child', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args._child:
        child(args._child)
    elif args.native:
        native()
    elif args.expectations:
        prepare()
    else:
        parser.print_help()


if __name__ == '__main__':
    main()
