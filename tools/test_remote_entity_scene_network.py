#!/usr/bin/env python3
"""Paused tag20/reply9 socket observer for an explicitly selected future actor.

Never builds. File-only preparation reuses a verified complete entity save;
native execution consumes the existing bounded actor/socket/process helpers.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import test_playable_client_cooking_entities as C

B, A, P, R, S, H, E = C.B, C.A, C.P, C.R, C.S, C.H, C.E
ROOT = C.ROOT
WORK = ROOT / 'build/remote-entity-scene-network'
VERIFIED = ROOT / 'evidence/playable-client-cooking-entities-native-005.json'
PARTIALS = (0x3f000000, 0x80000000, 0x3f800000)
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


def runtime_pins():
    source = Path(json.loads(VERIFIED.read_bytes())['final_atomic_snapshot']['path'])
    paths = (VERIFIED, Path(C.__file__), Path(E.__file__), Path(B.__file__),
             Path(A.__file__), Path(P.__file__), Path(R.__file__), Path(S.__file__), Path(H.__file__), source)
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
    }
    for name, required in markers.items():
        S.require(name in frozen, 'Selected actual graph lacks entity endpoint: ' + name)
        text = frozen[name].read_text()
        S.require(all(value in text for value in required), 'Selected graph lacks real tag20 DTO/capture: ' + name)
    return build


def scene(control, sample, entities, dimension, partial, checks, label):
    sequence = control.sequence
    reply = control.call([20, 128, 128, partial], 9)
    S.require(S.canonical(reply[4:]) == S.canonical([[sample, entities, dimension, partial]]),
              'Exact full projected records, current/old words, ItemKey, bob, order and stamp: ' + label)
    checks.append({'label': label, 'epoch': control.epoch, 'sequence': sequence,
        'partial_raw_F32': partial, 'frame_sha256': S.sha(S.canonical(reply[4])),
        'sample_sha256': S.sha(S.canonical(sample)), 'records': len(entities[1])})


def scenario(directory, binary, bridge):
    directory.mkdir(exist_ok=False)
    facts, world, record, full, bodies, _, view, source, seed = retained_fixture()
    path = directory / 'owner.nbt'
    path.write_bytes(seed)
    actor = A.PlayableBackend(directory / 'paused-owner', binary, path, bridge)
    checks, faults, saves = [], [], []
    try:
        raw, ping = actor.tcp(True)
        S.require(raw.call('world.clock') == S.P.clock(world), 'Loaded sole Core clock remains paused')
        S.inspect(raw, record)
        before, saved, _ = C.acknowledge(raw, path, facts, world, record, full, ping['peer'],
            bodies, view, directory, 'before-read-owner')
        saves.append(saved)
        control = B.connect(actor)
        sample = control.call([13, 128, 128], 7)[4]
        # This existing helper independently checks saved pose/clock and every
        # declared default sample cell. Cross-endpoint equality is read coherence.
        legacy = B.generic_frame(control, world, record)
        S.require(S.sha(S.canonical(sample)) == legacy['sample_sha256'], 'Paused tag13 compatibility')
        _, dimension = S.PC.parse_snapshot(S.PR.decode(record.motion)[0])
        entities = projected(view)
        for partial in PARTIALS:
            scene(control, sample, entities, dimension, partial, checks, 'partial-' + str(partial))
        for label, request, expected in (
            ('bad-capability', [1, 0, 'wrong-verification-capability'], [1, 3, '', 0, 'RendererAuthenticationFailed']),
            ('second-owner', [1, 0, actor.token], [1, 3, '', 0, 'RendererLeaseBusy']),
            ('unassigned-scene-socket', [1, 1, control.epoch, control.sequence, [20, 128, 128, PARTIALS[0]]],
             [1, 3, control.epoch, control.sequence, 'Wire:SocketEpoch']),
            ('bad-version', [2, 0, actor.token], [1, 3, '', 0, 'Wire:MalformedRequest'])):
            B.peer_fault(actor, request, expected, directory, label)
            faults.append(label)
        scene(control, sample, entities, dimension, PARTIALS[0], checks, 'owner-after-foreign-faults')
        bad = control.sequence + 1
        answer = control.exchange([1, 1, control.epoch, bad, [20, 128, 128, PARTIALS[0]]])
        S.require(answer == [1, 3, control.epoch, bad, 'RendererLeaseOrSequence'], 'Exact stale sequence refusal')
        S.exclusive_json(directory / 'stale-sequence.json', {'reply': answer})
        faults.append('stale-owner-sequence')
        control.close(); actor.private = None
        control = B.connect(actor)
        scene(control, sample, entities, dimension, PARTIALS[0], checks, 'reacquired-owner')
        S.require(raw.call('world.clock') == S.P.clock(world), 'Polling never advances sole Core')
        S.inspect(raw, record)
        after, saved, _ = C.acknowledge(raw, path, facts, world, record, full, ping['peer'],
            bodies, view, directory, 'after-read-owner')
        S.require(after == before, 'Whole physical read-side owner unchanged, including all RNG/factory/clock bytes')
        saves.append(saved)
        summary = {'status': 'PASS_NARROW', 'generation': A.generation_name(), 'actual_TCP': True,
            'paused': True, 'seed': R.pin(source), 'scene_checks': checks, 'lease_header_faults': faults,
            'legacy_catalog': legacy, 'atomic_saves': saves, 'whole_read_owner_bytes_equal': True,
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
    _, _, _, _, _, _, view, source, seed = retained_fixture()
    number, directory = fresh_directory()
    (directory / 'seed.nbt').write_bytes(seed)
    S.exclusive_json(directory / 'expected-entities.json', projected(view))
    value = {'status': 'PREPARED_FILE_ONLY; future actor native pending', 'native_executed': False,
        'actor_generation': generation, 'runtime_inputs': runtime_pins(), 'runner': R.pin(Path(__file__)),
        'retained_seed': R.pin(source), 'seed': R.pin(directory / 'seed.nbt'),
        'expected_entities': R.pin(directory / 'expected-entities.json'),
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
        result = scenario(directory / 'actors', A.ACTOR, bridge)
        S.require(runtime_pins() == before, 'Socket observer inputs changed')
        identity()
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
    success = process['exit_code'] == 0 and not process['timed_out']
    value = {'status': 'PASS_NARROW' if success else 'FAIL', 'binary': build['binary'],
        'inputs': R.pin(directory / 'inputs.json'), 'process': R.pin(directory / 'execution/result.full.json'),
        'cleanup': R.pin(directory / 'cleanup.json'), 'scope': SCOPE}
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
