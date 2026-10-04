#!/usr/bin/env python3
"""Exact two-tick original movement through the current saved actor artifact.

No build, Java probe or host movement model. Reuse the existing actor/private
socket and bounded process owners. Raw transient Receiver fields are unexposed.
"""
from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path

import test_playable_client_actor004_boundary as B

A, P, R, S, H = B.A, B.P, B.R, B.S, B.H
ROOT = A.ROOT


def helper_pins():
    return {str(Path(module.__file__)): R.pin(Path(module.__file__))
            for module in (A, B, P, R, S, H, S.PH)}


def original_case():
    data = json.loads(S.REFERENCE.read_bytes())
    S.PH.integrity(data)
    case = S.PH.decode(next(row for row in data['cases'] if row['id'] == 'scheduled_jump'))
    steps = case['steps']
    S.require(len(steps) == 2 and all(step['ok'] for step in steps)
              and [step['input']['held_mask'] for step in steps] == [17, 1],
              'Original two-tick neutral movement capture changed')
    records = [S.observed_record(steps[0]['before']),
               *(S.observed_record(step['after']) for step in steps)]
    S.require([S.sha(S.local_bytes(record)) for record in records] == [
        '2ad59d55560d9d26c35edc99bc89b450b613f537070b857e0ff45340ca097985',
        'a0d6202940cbb30cd0be640d339c5dd68430d274ce6963cc6800ead619c00899',
        'a0c7556af80af60c510a4ab0cee917398f917b462fa123a86ab3de6dfb71da8b'],
        'Original complete durable records differ')
    return case, records


def defaults():
    # The original fixture has the checked no-flight neutral profile. Legacy
    # decoding supplies these exact defaults and preserves loaded terrain.
    return {'main': P.playable_inventory(False, True), 'equipment': [None] * 7,
            'status': dict(zip(B.Inventory.STATUS_FIELDS,
                (False, False, False, 1036831949, 1028443341), strict=True))}


def requirements():
    case, records = original_case()
    palette, identity, count = B.palette_and_registry()
    S.require(palette['minecraft:air'] == 0 and palette['minecraft:stone'] == 1,
              'Original world state identities differ')
    world = S.scene_world(count, identity)
    return {'status': 'prepared; actual actor behavior pending',
        'reference': R.pin(S.REFERENCE), 'case': case['id'],
        'records': [{'bytes': len(S.local_bytes(record)),
                     'sha256': S.sha(S.local_bytes(record))} for record in records],
        'held_masks': [17, 1], 'world_sections': 8, 'stone_floor_cells': 25,
        'initial_core_sha256': S.sha(S.P.canonical_expected(world)),
        'profile': defaults(), 'artifact': str(A.WORK / 'native-build.json'),
        'cases': ['exact original W+Space tick and W-only tick',
                  'permission and invalid-step refusal without durable state change',
                  'nonfinite private input refusal, disconnect and reacquisition',
                  'actual Generic FrameCatalog before and after movement',
                  'acknowledged complete Core/Local save, unsaved tick, SIGKILL',
                  'cold restore and exact original second-tick continuation'],
        'scope': 'Actual private input/public simulation.step/FrameCatalog and complete '
                 'represented durable Core+Local+default inventory/status/WG profile. '
                 'Original observed raw records, no translated coordinates or movement equations. '
                 'Default no-flight legacy profile intentionally re-encodes as plain Local payload. '
                 'Raw Receiver, owner tails/cache, OS input and nonneutral cobweb/berry gameplay '
                 'are unexposed and unclaimed.'}


def packet(mask):
    codes = (119, 115, 97, 100, 32, 65592, 65595)
    events = [[0], *[[1, True, [0, code, bool(mask & (1 << index))]]
                     for index, code in enumerate(codes)]]
    return [1, [True, True, events]]


def inspect(client, record, world):
    S.inspect(client, record)
    S.require(client.call('world.clock') == S.P.clock(world),
              'Actual saved actor complete Core clock differs')


def tick(client, world, record):
    reply = client.call('simulation.step', {'ticks': 1})
    S.BASE.apply_tick(world)
    S.require(reply == S.P.clock(world), 'Actual one scheduled tick clock differs')
    inspect(client, record, world)


def save(client, path, world, highwater, record, directory, label):
    receipts = []
    S.save(client, path, world, highwater, record, receipts, label)
    S.exclusive_json(directory / (label + '.json'), receipts[0])
    return path.read_bytes(), receipts[0]


def scenario(directory, binary, bridge):
    directory.mkdir(exist_ok=False)
    _, records = original_case()
    before, first, second = records
    _, identity, count = B.palette_and_registry()
    world = S.scene_world(count, identity)
    path = directory / 'movement.nbt'
    initial = S.bundle_bytes(world, 40, before)
    path.write_bytes(initial)
    S.exclusive_json(directory / 'fixture.json', {
        'bundle': R.pin(path), 'expectations': requirements()})
    frames, saves, checks = [], [], []
    full, menu = defaults(), B.empty_menu()
    actor = A.PlayableBackend(directory / 'movement', binary, path, bridge)
    try:
        raw, ping = actor.tcp(True)
        observer, oping = actor.tcp(False)
        highwater = max(ping['peer'], oping['peer'])
        control = B.connect(actor)
        B.admitted_menu(control, full, menu, checks, [8], 'original-neutral-default-authority')
        inspect(raw, before, world)
        frames.append(B.generic_frame(control, world, before))
        observer.call('simulation.step', {'ticks': 1}, fault='PermissionDenied')
        observer.call('world.save', {}, fault='PermissionDenied')
        raw.call('simulation.step', {'ticks': 0}, fault='InvalidArguments')
        inspect(raw, before, world)
        S.require(path.read_bytes() == initial, 'Refused operations published a save')

        control.call(packet(17))
        tick(raw, world, first)
        frames.append(B.generic_frame(control, world, first))
        acknowledged, receipt = save(raw, path, world, highwater, first, directory,
                                     'acknowledged-original-first-tick')
        saves.append(receipt)
        saved_world = copy.deepcopy(world)
        # An actual nonfinite Look fault closes this private lease. Its cleanup
        # releases physical controls; that is not an atomic-controller claim.
        reply = control.call([1, [True, True, [
            [1, True, [0, 115, True]], [1, True, [3, 2143289344, 0]]]]], 3)
        S.require(reply[4:] == ['mouse-event-2'], 'Actual nonfinite input refusal differs')
        S.require(control.socket.recv(1) == b'', 'Faulted private lease remains connected')
        control.close()
        inspect(raw, first, world)
        S.require(path.read_bytes() == acknowledged, 'Refused input changed acknowledged save')
        control = B.connect(actor)
        control.call(packet(1))
        tick(raw, world, second)
        frames.append(B.generic_frame(control, world, second))
        B.admitted_menu(control, full, menu, checks, [8], 'recovered-neutral-authority')
        S.require(path.read_bytes() == acknowledged, 'Unsaved original second tick published')
        actor.stop(kill=True)
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop()

    world = saved_world
    actor = A.PlayableBackend(directory / 'cold-reload', binary, path, bridge)
    try:
        raw, ping = actor.tcp(True)
        inspect(raw, first, world)
        S.require(path.read_bytes() == acknowledged, 'Cold startup rewrote acknowledged save')
        control = B.connect(actor)
        B.admitted_menu(control, full, menu, checks, [8], 'cold-restored-default-authority')
        frames.append(B.generic_frame(control, world, first))
        control.call(packet(1))
        tick(raw, world, second)
        frames.append(B.generic_frame(control, world, second))
        _, receipt = save(raw, path, world, ping['peer'], second, directory,
                          'cold-continuation-original-second-tick')
        saves.append(receipt)
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop()
    result = {'status': 'passed', 'original_case': 'scheduled_jump',
        'actual_original_ticks': 3, 'backends': 2, 'frames': frames,
        'saves': saves, 'authority_checks': checks, 'actual_SIGKILL': True,
        'scope': requirements()['scope']}
    S.exclusive_json(directory / 'summary.json', result)
    return result


def child(directory):
    build = B.artifact()
    journal = directory / 'owned-groups.jsonl'
    journal.touch(exist_ok=False)
    bridge, _ = P.retained_bridge()
    def identity():
        S.require(R.pin(A.ACTOR) == build['binary'], 'Current actor changed during motion run')
    with H.bindings(S, {'SERVER': A.ACTOR, 'ROOT': ROOT, 'activation': identity,
                        'OWNED_GROUPS': journal}):
        result = scenario(directory / 'actors', A.ACTOR, bridge)
        identity()
    print(json.dumps({'status': result['status'], 'actual_original_ticks': 3}), flush=True)


def native():
    build = B.artifact()
    number = 1
    while (A.WORK / ('motion-' + str(number).zfill(3))).exists():
        number += 1
    directory = A.WORK / ('motion-' + str(number).zfill(3))
    directory.mkdir(exist_ok=False)
    inputs = {'binary': build['binary'], 'build': R.pin(A.WORK / 'native-build.json'),
              'source_map': build['source_map'], 'runner': R.pin(Path(__file__)),
              'helpers': helper_pins(), 'expectations': requirements()}
    S.exclusive_json(directory / 'inputs.json', inputs)
    bridge, _ = P.retained_bridge()
    with H.bindings(R, {'WORK': directory}):
        try:
            process = R.bounded([sys.executable, str(Path(__file__)), '--_child', str(directory)],
                                180, 'execution')
        finally:
            B.descendant_cleanup(directory, bridge)
    R.process_ok(process)
    S.require(inputs['runner'] == R.pin(Path(__file__)) and B.artifact()['binary'] == inputs['binary']
              and inputs['expectations'] == requirements() and inputs['helpers'] == helper_pins(),
              'Motion input or artifact changed')
    summary = json.loads((directory / 'actors/summary.json').read_bytes())
    R.write(ROOT / ('evidence/runtime-block-inside-actor-motion-' + str(number).zfill(3) + '.json'),
            {**inputs, 'status': summary['status'], 'summary': summary,
             'seconds': process['seconds'],
             'process': R.pin(directory / 'execution/result.full.json'),
             'cleanup': R.pin(directory / 'cleanup.json')}, True)
    print(json.dumps({'status': summary['status'], 'directory': str(directory)}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native', action='store_true')
    parser.add_argument('--_child', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args._child:
        child(args._child)
    elif args.native:
        native()
    else:
        print(json.dumps(requirements(), indent=2), flush=True)


if __name__ == '__main__':
    main()
