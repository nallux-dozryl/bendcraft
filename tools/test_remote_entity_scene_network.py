#!/usr/bin/env python3
"""Paused tag20/reply9 socket observer for an explicitly selected future actor.

Never builds. File-only preparation reuses a verified complete entity save;
native execution consumes the existing bounded actor/socket/process helpers.
"""
from __future__ import annotations

import argparse
import copy
import json
import struct
import sys
from pathlib import Path

import test_playable_client_cooking_entities as C
import test_playable_client_cooking_publication as Publication

B, A, P, R, S, H, E = C.B, C.A, C.P, C.R, C.S, C.H, C.E
J = Publication.J
ROOT = C.ROOT
WORK = ROOT / 'build/remote-entity-scene-network'
VERIFIED = ROOT / 'evidence/playable-client-cooking-entities-native-005.json'
PARTIALS = (0x3f000000, 0x80000000, 0x3f800000)
REGION = (-4, -1, -4, 8, 6, 8)
SCOPE = ('Actual paused private TCP tag20/reply9, complete saved-owner Item/Orb projection, '
         'old tag13 compatibility and read coherence, lease/header refusals, and complete '
         'physical owner retention. No constructor, simulation, sampler/renderer parity, '
         'OS presentation, or whole-game acceptance claim.')


def retained_fixture():
    retained = json.loads(VERIFIED.read_bytes())
    S.require(retained['status'] == 'PASS_NARROW', 'Successful real entity-save receipt required')
    source = Path(retained['final_atomic_snapshot']['path'])
    S.require(R.pin(source) == retained['final_atomic_snapshot'], 'Retained real entity save changed')
    facts = C.expected_facts()
    data = source.read_bytes()
    world, player, full, bodies, highwater, view, clocks = C.projection(data, facts)
    S.require(not bodies and not clocks and view == retained['final_entity_view'] and
              [row['kind'] for row in view['records']] == [0, 0, 1],
              'Retained full two-Item/one-Orb owner, drained effects and clock queue')
    record = S.decode_local(player)
    S.require(C.bundle(world, highwater, record, full, bodies, view) == data,
              'Every actual seed Core/player/inventory/body/entity/RNG/factory byte retained')
    return facts, world, record, full, bodies, highwater, view, source, data


def network_fixture():
    facts, retained, record, full, bodies, highwater, view, source, data = retained_fixture()
    world = copy.deepcopy(retained)
    present = {section['key'] for section in world['sections']}
    added = []
    # WG.Unspecified preserves the real default transient region. Supply its
    # missing resident sections as static fixture input, without inventing a
    # generation policy, ticking, or modifying any retained section/entity.
    for z in (-16, 0):
        for y in (-16, 0):
            for x in (-16, 0):
                key = S.BASE.section_key(x, y, z)
                if key not in present:
                    world['sections'].append({'key': key, 'cells': (facts['palette']['minecraft:air'],) * 4096})
                    present.add(key); added.append(key)
    world['sections'].sort(key=lambda section: section['key'])
    S.P.canonical_expected(world)
    seed = C.bundle(world, highwater, record, full, bodies, view)
    observed = C.projection(seed, facts)
    S.require(observed[1:] == (S.local_bytes(record), full, bodies, highwater, view, ()),
              'Every retained player/inventory/body/entity/RNG/factory/clock owner word remains exact')
    S.require(all(section in world['sections'] for section in retained['sections']) and
        {key: value for key, value in world.items() if key != 'sections'} ==
        {key: value for key, value in retained.items() if key != 'sections'},
        'Static resident fixture changes only absent Core sections')
    detail = {'retained_seed': R.pin(source), 'fixture_seed_sha256': S.sha(seed),
        'added_sections': added, 'added_state': 'minecraft:air', 'existing_sections_unchanged': True,
        'complete_player_inventory_entities_unchanged': True, 'generation_metadata_unchanged': True,
        'region': list(REGION), 'fixture_only': True, 'simulation_executed': False}
    return facts, world, record, full, bodies, highwater, view, source, seed, detail


def legacy_frame(control, world, record):
    response_begin = control.responses.tell()
    frame = control.call([13, 128, 128], 7)[4]
    words, _ = S.PC.parse_snapshot(S.PR.decode(record.motion)[0])
    position = tuple(struct.unpack('>d', struct.pack('>Q', raw))[0] for raw in S.PC.bits64(words[:6]))
    eye = (position[0], position[1] + S.PC.f32(record.eye), position[2])
    sections = {section['key']: section['cells'] for section in world['sections']}
    def mixed(seed, index):
        return ((seed ^ (((index + 1) & 0xffffffff) * 2246822519 & 0xffffffff)) * 3266489917) & 0xffffffff
    x0, y0, z0, width, height, depth = REGION
    cells = []
    for z in range(z0, z0 + depth):
        for y in range(y0, y0 + height):
            for x in range(x0, x0 + width):
                raw = tuple(map(S.unsigned, (x, y, z)))
                boundary = sum((value == base or value == base + size - 1)
                               for value, base, size in zip((x, y, z), REGION[:3], REGION[3:], strict=True))
                state = sections[S.BASE.section_key(x, y, z)][(x & 15) + ((z & 15) << 4) + ((y & 15) << 8)]
                seed = mixed(mixed(mixed(0, raw[0]), raw[1]), raw[2])
                cells.append([*raw, boundary, state, seed, [[], 4294967295, 0, 0, False, 128]])
    expected = [world['registry'], world['tick'], world['revision'],
                list(S.PC.words64(tuple(map(S.PC.raw64, eye)))), [0, 0, 0, *words[39:41]], cells]
    S.require(S.canonical(frame) == S.canonical(expected),
              'Every actual default-region cell/order/state/seed/policy and pose-aware sample stamp')
    return frame, {'sample_sha256': S.sha(S.canonical(frame)), 'cells': len(cells),
        'region': list(REGION), 'tick': world['tick'], 'revision': world['revision'],
        'actual_reply_ASCII_bytes': control.responses.tell() - response_begin - 1,
        'state_ids': sorted({value[4] for value in cells})}


def projected(view):
    """Independent literal DTO projection from the retained full owner."""
    rows = []
    for record in view['records']:
        c, p = record['common'], record['payload']
        common = [c['dimension'], c['id'], c['fields']['position'], c['fields']['position_old'],
                  c['tick_count'], bool(c['removed']), bool(c['accessible']), int(c['section_order'])]
        rows.append([0, common, B.slot(p['item']), p['bob']] if record['kind'] == 0
                    else [1, common, p['value']])
    return [1, rows]


def empty_publication():
    # The retained format3 seed has no body/effect or publication recovery.
    # Entry creates a fresh journal; this read-only scenario never edits/ticks.
    return J.encode_publication(J.tip(), 0, (), None, Publication.catalog())


def acknowledge(client, path, facts, world, record, full, highwater, bodies,
                view, directory, label):
    reply = client.call('world.save', {})
    data = path.read_bytes()
    physical = directory / (label + '.nbt')
    physical.write_bytes(data)
    actual = Publication.projection(data, facts)
    keyed_bodies = tuple((C.POSITION, body) for body in bodies)
    publication = empty_publication()
    expected = Publication.bundle(world, highwater, record, full, keyed_bodies,
                                  (), view, (), publication)
    S.require(reply == {'status': 'durable', 'published': True, 'durable': True,
        'bytes': len(data), 'peer_highwater': highwater} and data == expected,
        'Every current format4 atomic byte, including complete publication: ' + label)
    S.require(S.P.canonical_expected(actual['world']) == S.P.canonical_expected(world) and
        actual['player'] == S.local_bytes(record) and actual['full'] == full and
        actual['bodies'] == keyed_bodies and actual['highwater'] == highwater and
        actual['entities'] == view and not actual['effects'] and not actual['clock_inputs'] and
        actual['publication']['raw'] == publication,
        'Independent full Core/player/inventory/Details/entity/RNG/factory/publication owner: ' + label)
    receipt = {'label': label, 'reply': reply, 'physical': R.pin(physical),
        'independent_expected_sha256': S.sha(expected), 'complete_bytes_equal': True,
        'format': 4, 'publication_sha256': S.sha(publication),
        'publication': actual['publication']['journal'], 'incarnations': actual['publication']['incarnations'],
        'entities_sha256': S.sha(E.encode(view)), 'pending_effects': 0, 'unconsumed_clock_inputs': 0}
    S.exclusive_json(directory / (label + '.json'), receipt)
    return data, receipt


def runtime_pins():
    source = Path(json.loads(VERIFIED.read_bytes())['final_atomic_snapshot']['path'])
    paths = (VERIFIED, Path(C.__file__), Path(E.__file__), Path(B.__file__),
             Path(A.__file__), Path(P.__file__), Path(R.__file__), Path(S.__file__), Path(H.__file__),
             Path(Publication.__file__), Path(J.__file__), ROOT / 'reference/cooking_world.json', source)
    return C.runtime_pins() | {str(path): R.pin(path) for path in paths}


def artifact():
    build = B.artifact()
    S.require(A.generation() > 20 and build['generation'] == A.generation_name(),
              'Explicit successful future actor required; immutable020 lacks tag20')
    mapping = json.loads((A.SOURCE / 'source-map.json').read_bytes())
    frozen = {}
    for row in mapping['files']:
        path = Path(row['mapped']['resolved'])
        S.require(R.pin(path)['sha256'] == row['mapped']['sha256'],
                  'Frozen mapped graph changed: ' + row['path'])
        frozen[row['path']] = path
    markers = {
        'src/resource_client_wire.bend': ('SceneFrame{width:U32,height:U32,partial:F32}',
            'SceneFrameReply{epoch:String,sequence:Nat,frame:EntityFrame.Frame}',
            'J.JNumber{"20"}', 'J.JNumber{"9"}'),
        'src/remote_resource_transport.bend': ('case W.SceneFrame{', 'EntityBackend.frame('),
        'src/remote_entity_frame.bend': ('sample:GS.Sample,entities:D.Snapshot',),
        'src/local_player_entity_scene.bend': ('Sample.snapshot(', 'S.cooking_entities('),
        'src/local_player_cooking_storage.bend': ('P.member("format",N.Int{4})',),
        'src/client_world.bend': ('Bounds{4294967292, 4294967295, 4294967292, 8, 6, 8}',),
    }
    for name, required in markers.items():
        S.require(name in frozen, 'Selected actual graph lacks entity endpoint: ' + name)
        text = frozen[name].read_text()
        S.require(all(value in text for value in required), 'Selected graph lacks real tag20 DTO/capture: ' + name)
    return build


def scene(control, sample, entities, dimension, partial, checks, label):
    sequence = control.sequence
    response_begin = control.responses.tell()
    reply = control.call([20, 128, 128, partial], 9)
    S.require(S.canonical(reply) == S.canonical([1, 9, control.epoch, sequence,
                                               [sample, entities, dimension, partial]]),
              'Exact full projected records, current/old words, ItemKey, bob, order and stamp: ' + label)
    checks.append({'label': label, 'epoch': control.epoch, 'sequence': sequence,
        'partial_raw_F32': partial, 'frame_sha256': S.sha(S.canonical(reply[4])),
        'actual_reply_ASCII_bytes': control.responses.tell() - response_begin - 1,
        'sample_sha256': S.sha(S.canonical(sample)), 'records': len(entities[1])})


def scenario(directory, binary, bridge):
    directory.mkdir(exist_ok=False)
    facts, world, record, full, bodies, _, view, source, seed, fixture = network_fixture()
    path = directory / 'owner.nbt'
    initial = directory / 'loaded-seed.nbt'
    initial.write_bytes(seed)
    path.write_bytes(seed)
    actor = A.PlayableBackend(directory / 'paused-owner', binary, path, bridge)
    checks, faults, saves = [], [], []
    try:
        raw, ping = actor.tcp(True)
        S.require(raw.call('world.clock') == S.P.clock(world), 'Loaded sole Core clock remains paused')
        S.inspect(raw, record)
        before, saved = acknowledge(raw, path, facts, world, record, full, ping['peer'],
            bodies, view, directory, 'before-read-owner')
        saves.append(saved)
        control = B.connect(actor)
        sample, legacy = legacy_frame(control, world, record)
        _, dimension = S.PC.parse_snapshot(S.PR.decode(record.motion)[0])
        entities = projected(view)
        for partial in PARTIALS:
            scene(control, sample, entities, dimension, partial, checks, 'partial-' + str(partial))
        for label, request, expected in (
            ('bad-capability', [1, 0, 'wrong-verification-capability'], [1, 3, '', 0, 'RendererAuthenticationFailed']),
            ('second-owner', [1, 0, actor.token], [1, 3, '', 0, 'RendererLeaseBusy']),
            ('unassigned-scene-socket', [1, 1, control.epoch, control.sequence, [20, 128, 128, PARTIALS[0]]],
             [1, 3, control.epoch, control.sequence, 'Wire:SocketEpoch']),
            ('invalid-width', [1, 1, control.epoch, control.sequence, [20, 0, 128, PARTIALS[0]]],
             [1, 3, '', 0, 'Wire:MalformedRequest']),
            ('negative-fraction', [1, 1, control.epoch, control.sequence, [20, 128, 128, 0xbf000000]],
             [1, 3, '', 0, 'Wire:MalformedRequest']),
            ('nonfinite-fraction', [1, 1, control.epoch, control.sequence, [20, 128, 128, 0x7f800000]],
             [1, 3, '', 0, 'Wire:MalformedRequest']),
            ('bad-version', [2, 0, actor.token], [1, 3, '', 0, 'Wire:MalformedRequest'])):
            B.peer_fault(actor, request, expected, directory, label)
            observed = json.loads((directory / (label + '.json')).read_bytes())
            S.require(S.canonical(observed['reply']) == S.canonical(expected), 'Strict correlated fault: ' + label)
            faults.append(label)
        scene(control, sample, entities, dimension, PARTIALS[0], checks, 'owner-after-foreign-faults')
        bad = control.sequence - 1
        answer = control.exchange([1, 1, control.epoch, bad, [20, 128, 128, PARTIALS[0]]])
        S.require(S.canonical(answer) == S.canonical([1, 3, control.epoch, bad, 'RendererLeaseOrSequence']),
                  'Exact stale sequence refusal')
        S.exclusive_json(directory / 'stale-sequence.json', {'reply': answer})
        faults.append('stale-owner-sequence')
        control.close(); actor.private = None
        control = B.connect(actor)
        scene(control, sample, entities, dimension, PARTIALS[0], checks, 'reacquired-owner')
        S.require(raw.call('world.clock') == S.P.clock(world), 'Polling never advances sole Core')
        S.inspect(raw, record)
        after, saved = acknowledge(raw, path, facts, world, record, full, ping['peer'],
            bodies, view, directory, 'after-read-owner')
        S.require(after == before, 'Whole physical read-side owner unchanged, including all RNG/factory/clock bytes')
        saves.append(saved)
        summary = {'status': 'PASS_NARROW', 'generation': A.generation_name(), 'actual_TCP': True,
            'paused': True, 'seed': R.pin(source), 'scene_checks': checks, 'lease_header_faults': faults,
            'resident_fixture': fixture, 'loaded_fixture': R.pin(initial),
            'legacy_catalog': legacy, 'atomic_saves': saves, 'whole_read_owner_bytes_equal': True,
            'storage_format': 4, 'loaded_seed_format': 3, 'fresh_empty_publication_retained': True,
            'entity_projection': entities, 'network_snapshot_binding': 'Bound; full actual retained owner',
            'network_Unbound': 'NOT_EXERCISED; Entry initializes an entity owner; separate codec corpus checks Unbound versus Bound-empty',
            'client_rng_factory_constructor_clock_fields': False, 'scope': SCOPE}
        S.exclusive_json(directory / 'summary.json', summary)
        return summary
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop()


def fresh_directory():
    WORK.mkdir(exist_ok=True)
    for number in range(1, 10000):
        directory = WORK / f'{number:03}'
        try:
            directory.mkdir()
            return number, directory
        except FileExistsError:
            continue
    raise RuntimeError('No unused entity-scene observer directory')


def prepare(generation):
    facts, world, record, full, bodies, highwater, view, source, seed, fixture = network_fixture()
    number, directory = fresh_directory()
    (directory / 'seed.nbt').write_bytes(seed)
    S.exclusive_json(directory / 'expected-entities.json', projected(view))
    expected_save = Publication.bundle(world, highwater, record, full,
        tuple((C.POSITION, body) for body in bodies), (), view, (), empty_publication())
    (directory / 'expected-format4-save.nbt').write_bytes(expected_save)
    observed = Publication.projection(expected_save, facts)
    S.require(observed['entities'] == view and not observed['effects'] and not observed['clock_inputs'] and
        observed['publication']['raw'] == empty_publication(), 'Prepared physical format4 literal round trip')
    value = {'status': 'PREPARED_FILE_ONLY; future actor native pending', 'native_executed': False,
        'actor_generation': generation, 'runtime_inputs': runtime_pins(), 'runner': R.pin(Path(__file__)),
        'retained_seed': R.pin(source), 'seed': R.pin(directory / 'seed.nbt'),
        'expected_entities': R.pin(directory / 'expected-entities.json'),
        'resident_fixture': fixture,
        'expected_format4_template': R.pin(directory / 'expected-format4-save.nbt'),
        'template_peer_highwater': highwater,
        'format4_template_scope': 'Independent physical serialization only; native save uses the actual allocated public peer highwater.',
        'network_Unbound': 'NOT_EXERCISED; Entry initializes a bound owner', 'scope': SCOPE,
        'planned_native_argv': [sys.executable, '-B', str(Path(__file__)), '--actor-generation', str(generation), '--native']}
    R.write(directory / 'prepared.json', value, True)
    output = ROOT / f'evidence/remote-entity-scene-network-prepared-{number:03}.json'
    R.write(output, value, True)
    print(json.dumps({'status': value['status'], 'evidence': str(output)}), flush=True)


def child(directory):
    build, before = artifact(), runtime_pins()
    journal = directory / 'owned-groups.jsonl'; journal.touch(exist_ok=False)
    bridge, _ = P.retained_bridge()
    def identity():
        S.require(artifact() == build, 'Selected full actor artifact/source identity changed')
    with H.bindings(S, {'SERVER': A.ACTOR, 'ROOT': ROOT, 'activation': identity, 'OWNED_GROUPS': journal}):
        try:
            result = scenario(directory / 'actors', A.ACTOR, bridge)
            S.require(runtime_pins() == before, 'Socket observer inputs changed')
            identity()
        except BaseException as error:
            S.exclusive_json(directory / 'first-failure.json',
                             {'type': type(error).__name__, 'message': str(error)})
            raise
    print(json.dumps({'status': result['status'], 'scene_checks': len(result['scene_checks'])}), flush=True)


def native():
    build, before, own = artifact(), runtime_pins(), R.pin(Path(__file__))
    number, directory = fresh_directory()
    S.exclusive_json(directory / 'inputs.json', {'binary': build['binary'], 'source_map': build['source_map'],
        'build': R.pin(A.WORK / 'native-build.json'), 'runtime': before, 'runner': own})
    bridge, _ = P.retained_bridge()
    with H.bindings(R, {'WORK': directory}):
        try:
            process = R.bounded([sys.executable, '-B', str(Path(__file__)), '--actor-generation',
                str(A.generation()), '--_child', str(directory)], 300, 'execution')
        finally:
            B.descendant_cleanup(directory, bridge)
    process_failure = None
    try:
        R.process_ok(process)
    except BaseException as error:
        process_failure = {'type': type(error).__name__, 'message': str(error)}
    success = process_failure is None
    value = {'status': 'PASS_NARROW' if success else 'FAIL', 'binary': build['binary'],
        'inputs': R.pin(directory / 'inputs.json'), 'process': R.pin(directory / 'execution/result.full.json'),
        'cleanup': R.pin(directory / 'cleanup.json'), 'scope': SCOPE}
    if process_failure is not None:
        value['process_failure'] = process_failure
    if success:
        S.require(runtime_pins() == before and R.pin(Path(__file__)) == own and artifact() == build,
                  'Native observer inputs or selected full artifact changed')
        value['summary'] = json.loads((directory / 'actors/summary.json').read_bytes())
    output = ROOT / f'evidence/remote-entity-scene-network-native-{number:03}.json'
    R.write(output, value, True)
    R.process_ok(process)
    print(json.dumps({'status': value['status'], 'evidence': str(output)}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--actor-generation', required=True, type=int)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument('--expectations', action='store_true')
    modes.add_argument('--native', action='store_true')
    modes.add_argument('--_child', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.actor_generation <= 20:
        parser.error('--actor-generation must select a future producer greater than20 with the actual tag20 endpoint')
    selected = ROOT / f'build/compiler-producer-diagnostic-{args.actor_generation:03}'
    with H.bindings(A, {'WORK': selected, 'SOURCE': selected / 'source', 'ACTOR': selected / 'actor'}):
        if args.expectations:
            prepare(args.actor_generation)
        elif args._child:
            child(args._child)
        else:
            native()


if __name__ == '__main__':
    main()
