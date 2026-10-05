#!/usr/bin/env python3
"""Reuse the real catalog client/actor owners for a missing-family demand case.

Default mode reads original furnace resources only. --native consumes a changed,
completed renderer and an explicitly selected actor. Furnace blocks deliberately
sit behind the camera: exact old visible pixels test coherent texture replacement,
not a new Java furnace baked-geometry or vanilla drawable claim.
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import sys
import zipfile
from pathlib import Path

PYTHON = Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
if Path(sys.executable).resolve() != PYTHON.resolve():
    import os
    os.execv(str(PYTHON), [str(PYTHON), '-B', __file__, *sys.argv[1:]])
sys.dont_write_bytecode = True

import generic_resource_world_sample_client_runtime as G
from PIL import Image

ROOT, require, pin, digest, canonical = G.ROOT, G.require, G.pin, G.digest, G.canonical


class ObservedExchanges(list):
    """Timestamp the unchanged relay's actual completed replies."""
    def append(self, value):
        super().append({**value, 'observed_reply_monotonic_ns': G.time.monotonic_ns()})


class DemandRelay(G.Pair.Relay):
    """Retain the existing actual relay outcome even when the thread fails first."""
    def serve(self):
        self.records = ObservedExchanges(self.records)
        try:
            super().serve()
        finally:
            G.exclusive(G.Pair.WORK/(self.label+'-stopped.json'), {
                'exchanges': self.records, 'failure': self.failure,
                'unchanged_native_bytes': True, 'capability_redacted': True})


class DemandRenderer(G.Renderer):
    """Retain the original OS observer response before its assertions run."""
    def finish_generic(self, **kwargs):
        original = self.proc.communicate
        def retained(*args, **options):
            out, err = original(*args, **options)
            G.exclusive(self.directory/'observer-completion.json',
                        {'stdout': out, 'stderr': err})
            return out, err
        with G.mock.patch.object(self.proc, 'communicate', retained):
            return super().finish_generic(**kwargs)


def correlated(relay, data, *, pairs=2):
    """Observe contiguous real sequences, allowing only release-only load beats."""
    epoch, sequence, pending = None, 1, None
    observations, beats, beat_times = [], [], []
    sample_time = None
    for exchange in relay['exchanges']:
        request, reply = exchange['request'], exchange['reply']
        require(exchange['forwarded_unchanged'], 'Relay substituted bytes')
        if request[:2] == [1, 0]:
            require(epoch is None and len(reply) == 4 and reply[:2] == [1, 0] and reply[3] == 0,
                    'Actual Hello correlation')
            epoch = reply[2]
            continue
        require(epoch is not None and canonical(request[:4]) == canonical([1, 1, epoch, sequence])
                and reply[0] == 1 and canonical(reply[2:4]) == canonical([epoch, sequence]),
                'Actual socket epoch/sequence')
        command = request[4]
        sequence += 1
        if command[0] == 13:
            require(command == [13, G.WIDTH, G.HEIGHT] and reply[1] == 7 and len(reply) == 5
                    and pending is None, 'Actual FrameCatalog admission')
            require(canonical(reply[4]) == canonical(data['sample']),
                    'ALL512 actual raw cells/appearance/seed/eye/camera differ')
            pending, beats, beat_times = request[3], [], []
            sample_time = exchange['observed_reply_monotonic_ns']
        elif command[0] == 8:
            require(command == [8] and reply[1] == 6 and len(reply) == 7
                    and canonical(reply[4:6]) == canonical([True, ''])
                    and canonical(reply[6]) == canonical(data['authority'])
                    and pending is not None and request[3] == pending + 1 + len(beats),
                    'Complete typed authoritative menu pair after actual release-only beats')
            menu_time = exchange['observed_reply_monotonic_ns']
            reply_times = [sample_time, *beat_times, menu_time]
            gaps = [(right - left) / 1_000_000
                    for left, right in zip(reply_times, reply_times[1:])]
            observations.append({'sample_sequence': pending, 'menu_sequence': request[3],
                'all_cells': 512, 'sample_sha256': digest(canonical(data['sample'])),
                'menu_sha256': digest(canonical(reply[6])), 'load_heartbeat_sequences': beats,
                'sample_to_menu_milliseconds':
                    (menu_time - sample_time) / 1_000_000,
                'heartbeat_reply_offsets_milliseconds':
                    [(value - sample_time) / 1_000_000 for value in beat_times],
                'maximum_observed_reply_gap_milliseconds': max(gaps),
                'scope': 'Reply observations; cooperative timer scheduling is not a fixed-interval guarantee.'})
            pending = None
        elif command[0] == 1:
            require(reply == [1, 2, epoch, request[3]] and len(command) == 2
                    and canonical(command[1][:2]) == canonical([False, False])
                    and all(action == [0] for action in command[1][2]), 'Hidden release-only input')
            if pending is not None:
                require(command[1][2] == [], 'Resource heartbeat must not carry actions')
                beats.append(request[3])
                beat_times.append(exchange['observed_reply_monotonic_ns'])
        else:
            require(command == [2] and reply == [1, 2, epoch, request[3]], 'Unexpected hidden command')
    require(epoch is not None and pending is None and len(observations) == pairs,
            'Complete actual sample/menu pairs')
    require(observations[0]['load_heartbeat_sequences'] and not observations[1]['load_heartbeat_sequences'],
            'Only actual cold demand may schedule heartbeats; warm frame stays direct')
    cold = observations[0]
    require(cold['sample_to_menu_milliseconds'] < 1000 or
            len(cold['load_heartbeat_sequences']) >= 2,
            'A longer cold load must observe recurring heartbeats beyond the immediate release')
    require(cold['maximum_observed_reply_gap_milliseconds'] < 5000,
            'Observed cold-load replies exceed the actual five-second socket renewal bound')
    return observations


def original_furnace():
    with G.REGISTRY.open() as source:
        row = next(row for row in csv.DictReader(source, delimiter='\t')
                   if row['identifier'] == 'minecraft:furnace')
    require((int(row['first_state_id']), int(row['state_count']), int(row['default_state_id']))
            == (6883, 8, 6884), 'Pinned actual furnace registry states')
    require(json.loads(row['ordered_properties_json']) == [
        {'name': 'facing', 'values': ['north', 'south', 'west', 'east']},
        {'name': 'lit', 'values': ['true', 'false']}], 'Actual state-product ordering')
    resources = {}
    with zipfile.ZipFile(G.JAR) as jar:
        for name in ('blockstates/furnace', 'models/block/furnace',
                     'models/block/furnace_on', 'models/block/orientable'):
            path = 'assets/minecraft/' + name + '.json'
            raw = jar.read(path)
            resources[path] = {'bytes': len(raw), 'sha256': digest(raw),
                               'decoded': json.loads(raw)}
        variants = resources['assets/minecraft/blockstates/furnace.json']['decoded']['variants']
        wanted = {f'facing={facing},lit={lit}': {
            'model': 'minecraft:block/furnace' + ('_on' if lit == 'true' else ''),
            **({'y': yaw} if yaw else {})}
            for facing, yaw in (('north', 0), ('south', 180), ('west', 270), ('east', 90))
            for lit in ('true', 'false')}
        require(variants == wanted, 'Actual eight original model selections')
        for name in ('furnace_top', 'furnace_side', 'furnace_front', 'furnace_front_on'):
            path = 'assets/minecraft/textures/block/' + name + '.png'
            raw = jar.read(path)
            require(path + '.mcmeta' not in jar.namelist(), 'Animated furnace material is not admitted')
            with Image.open(io.BytesIO(raw)) as image:
                rgba = image.convert('RGBA')
                require(rgba.size == (16, 16) and rgba.getextrema()[3] == (255, 255),
                        'Actual static opaque furnace texture')
                resources[path] = {'bytes': len(raw), 'sha256': digest(raw),
                    'extent': [16, 16], 'rgba_sha256': digest(rgba.tobytes()),
                    'caller_layer': 'Solid', 'animation_metadata': False}
        current = resources['assets/minecraft/models/block/orientable.json']['decoded']
        for _ in range(32):
            if 'elements' in current:
                break
            parent = current['parent']
            namespace, name = parent.split(':', 1) if ':' in parent else ('minecraft', parent)
            path = 'assets/' + namespace + '/models/' + name + '.json'
            raw = jar.read(path)
            current = json.loads(raw)
            resources[path] = {'bytes': len(raw), 'sha256': digest(raw), 'decoded': current}
        require('elements' in current, 'Original furnace parent geometry budget')
        box = current['elements']
        require(len(box) == 1 and box[0]['from'] == [0, 0, 0]
                and box[0]['to'] == [16, 16, 16] and len(box[0]['faces']) == 6,
                'Original furnace model occupies exactly its unit cell')
    return {'JAR': pin(G.JAR), 'registry': pin(G.REGISTRY), 'row': row,
            'resources': resources, 'states': list(range(6883, 6891)),
            'scope': 'Original resource/state metadata and explicit caller layer admission; no new Java geometry extraction.'}


def demand_fixture(data):
    # Both different missing state IDs map to one complete family load.
    for point, state in (((0, -60, -6), 6883), ((1, -60, -6), 6884)):
        G.S.BASE.set_block(data['world'], *point, state)
    data['world']['revision'] += 2
    data['sample'] = G.expected_sample(data['world'], data['record'])
    data['payload'] = G.Boundary.bundle(data['world'], 40, data['record'], data['full'], '')
    wanted = {6883, 6884}
    require(wanted <= {cell[4] for cell in data['sample'][5]}, 'Both real missing states must be sampled')
    eye_z = G.S.PC.f64(G.S.PC.bits64(data['sample'][3])[2])
    rays = G.Pixels.directions(tuple(G.Pixels.unbits(x) for x in data['sample'][4]),
                              G.WIDTH, G.HEIGHT, G.Pixels.scene([], [])['settings'][2])
    require(float(rays[:, 2].min()) > 0 and -5 < eye_z,
            'Every actual comparison ray points away from both original unit-cell furnace models')
    return data


def native(binary, actor_generation, generation):
    original = original_furnace()
    actor_work = ROOT/'build'/f'compiler-producer-diagnostic-{actor_generation:03d}'
    selected_actor = {'WORK': actor_work, 'SOURCE': actor_work/'source',
                      'ACTOR': actor_work/'actor'}
    with G.Host.bindings(G.Boundary.A, selected_actor), \
         G.Host.bindings(G, {'CLIENT': Path(binary)}):
        data, rgb, prepared = G.prepare()
    require(prepared['oracle']['full_exact_pixel_expectation_ready'], 'Existing independent visible oracle')
    data = demand_fixture(data)
    client = G.client_artifact(binary)
    directory = ROOT/'build/generic-resource-world-sample-demand-runtime'/f'{generation:03d}'
    directory.mkdir(parents=True, exist_ok=False)
    G.exclusive(directory/'original-resources.json', original)
    G.exclusive(directory/'expected-sample.json', data['sample'])
    G.exclusive(directory/'preparation.json', prepared)
    with G.Host.bindings(G.Boundary.A, selected_actor):
        actor = G.Boundary.artifact()
        before = G.Boundary.runtime_pins()
        with G.Host.bindings(G.Pair, {'WORK': directory}), G.Host.bindings(G.R, {
                'WORK': directory, 'GROUPS': directory/'owned-groups.ndjson'}):
          with G.mock.patch.object(G.Pair, 'Relay', DemandRelay), \
               G.mock.patch.object(G, 'Renderer', DemandRenderer), \
               G.mock.patch.object(G, 'correlated', correlated):
            try:
                result, path = G.launch_lane(Path(binary), G.Boundary.A.ACTOR, directory,
                                            data, rgb, prepared['helpers'])
                output = (directory/'renderer-supported/stdout').read_text()
                publications = [line for line in output.splitlines() if line.startswith('catalog.demand|')]
                require(publications == ['catalog.demand|12|13|minecraft:furnace'],
                        'One coherent missing-family publication; second frame must stay warm')
                reload = G.reload_lane(G.Boundary.A.ACTOR, directory, path, data, result.pop('saved_bytes'))
                require(G.Boundary.runtime_pins() == before,
                        'Actual fixture/JAR/reference/runtime input drift')
                require(G.Boundary.artifact() == actor and G.client_artifact(binary) == client,
                        'Admitted demand native artifact drift')
                record = {'schema': 'generic-resource-demand-runtime-v1', 'status': 'PASS',
                    'client': client['binary'], 'actor': actor['binary'], 'actor_generation': actor_generation,
                    'publications': publications, 'sample_cells': 512, 'missing_states': [6883, 6884],
                    'loaded_family_states': original['states'], 'render': result, 'cold_reload': reload,
                    'original_resources': pin(directory/'original-resources.json'),
                    'limits': ['Furnace contributes no visible pixels in this case; exact prior visible pixels verify coherent texture replacement.',
                               'No Java furnace baked-geometry, positionRandom, full-light, drawable or visible-input claim.',
                               'Other material, tint, animation and special-renderer requirements remain named admission failures.']}
                G.exclusive(directory/'result.json', record)
                print(json.dumps({'status': record['status'], 'result': str(directory/'result.json'),
                                  'publications': publications}))
            except BaseException as error:
                G.exclusive(directory/'first-failure.json', {'status': 'failed',
                    'type': type(error).__name__, 'message': str(error),
                    'notes': getattr(error, '__notes__', []), 'native_consumer_run': True})
                raise
            finally:
                G.sweep_owned(directory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native', action='store_true')
    parser.add_argument('--client', type=Path)
    parser.add_argument('--actor-generation', type=int)
    parser.add_argument('--generation', type=int, default=1)
    args = parser.parse_args()
    if args.native:
        require(args.client is not None and args.actor_generation is not None,
                'Native demand requires an explicit completed client and actor generation')
        native(args.client.resolve(), args.actor_generation, args.generation)
    else:
        print(json.dumps(original_furnace(), sort_keys=True, indent=2))


if __name__ == '__main__':
    main()
