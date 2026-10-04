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
    data, rgb, prepared = G.prepare()
    require(prepared['oracle']['full_exact_pixel_expectation_ready'], 'Existing independent visible oracle')
    data = demand_fixture(data)
    actor_work = ROOT/'build'/f'compiler-producer-diagnostic-{actor_generation:03d}'
    client = G.client_artifact(binary)
    directory = ROOT/'build/generic-resource-world-sample-demand-runtime'/f'{generation:03d}'
    directory.mkdir(parents=True, exist_ok=False)
    G.exclusive(directory/'original-resources.json', original)
    G.exclusive(directory/'expected-sample.json', data['sample'])
    G.exclusive(directory/'preparation.json', prepared)
    with G.Host.bindings(G.Boundary.A, {'WORK': actor_work, 'SOURCE': actor_work/'source',
                                      'ACTOR': actor_work/'actor'}):
        actor = G.Boundary.artifact()
        with G.Host.bindings(G.Pair, {'WORK': directory}), G.Host.bindings(G.R, {
                'WORK': directory, 'GROUPS': directory/'owned-groups.ndjson'}):
            try:
                result, path = G.launch_lane(Path(binary), G.Boundary.A.ACTOR, directory,
                                            data, rgb, prepared['helpers'])
                output = (directory/'renderer-supported/stdout').read_text()
                publications = [line for line in output.splitlines() if line.startswith('catalog.demand|')]
                require(publications == ['catalog.demand|12|13|minecraft:furnace'],
                        'One coherent missing-family publication; second frame must stay warm')
                reload = G.reload_lane(G.Boundary.A.ACTOR, directory, path, data, result.pop('saved_bytes'))
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
