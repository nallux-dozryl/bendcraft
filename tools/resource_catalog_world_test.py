#!/usr/bin/env python3
"""Actual catalog-world IO/native observer with retained Java geometry oracle."""
from __future__ import annotations
import argparse, copy, hashlib, io, json, os, sys, time, zipfile
from pathlib import Path

PYTHON = Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
if Path(sys.executable).resolve() != PYTHON.resolve():
    os.execv(str(PYTHON), [str(PYTHON), __file__, *sys.argv[1:]])

import resource_block_catalog_test as Catalog
import test_mesh_render as Pixels

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT/'build/resource-catalog-world-tests'
ENTRY = ROOT/'tests/resource_catalog_world.bend'
EVIDENCE = ROOT/'evidence/resource_catalog_world_native.json'
Catalog.ENTRY = ENTRY
Catalog.WORK = WORK
Catalog.BINARY = WORK/'native'
Catalog.PRIVATE = WORK/'private-001'
Catalog.EVIDENCE = EVIDENCE

def generation(number):
    global WORK
    assert 1 <= number <= 999
    if number != 1:
        WORK = ROOT/'build/resource-catalog-world-tests'/f'generation-{number:03d}'
    Catalog.WORK = WORK
    Catalog.BINARY = WORK/'native'
    Catalog.PRIVATE = WORK/'private-001'


def pin(path):
    data = Path(path).read_bytes()
    return {'path': str(path), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


def selected_state(reference, name, properties=None):
    block = reference['blocks'][name]
    if properties is None:
        return next(s for s in block['states'] if s['id'] == block['default_state_id'])
    return next(s for s in block['states'] if s['properties'] == properties)


def decisions(root, ticket=0):
    if root['kind'] == 'variant':
        return {'ticket': ticket} if root['choice']['kind'] == 'weighted' else {}
    return {'parts': {str(p['index']): ticket for p in root['parts'] if p['choice']['kind'] == 'weighted'}}


def model_key(value):
    return (value['model'], value.get('x', 0), value.get('y', 0), value.get('z', 0), value.get('uvlock', False))


def geometry_key(value):
    return (value['texture'], value['tint'], tuple(tuple(v) for v in value['vertices']))


def prepare():
    WORK.mkdir(exist_ok=True)
    target = WORK/'preparation.json'
    assert not target.exists(), 'Preserve the existing preparation; do not overwrite it'
    reference = json.loads(Catalog.REFERENCE.read_text())
    java = json.loads(Pixels.REFERENCE.read_text())['observations']['baked_variants']
    baked = {model_key(v['input']): v for v in java}
    profile = reference['static_solid_cutout_profile']
    names = sorted(profile['sprite_layers'])
    slots = {name: i for i, name in enumerate(names)}
    textures = []
    assert Catalog.sha(Catalog.JAR) == '4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d'
    with zipfile.ZipFile(Catalog.JAR) as archive:
        for name in names:
            textures.append(Pixels.np.array(Pixels.Image.open(io.BytesIO(archive.read(Catalog.resource(name, 'textures', '.png')))).convert('RGBA'), dtype=Pixels.np.uint8))
    frames = []
    expected = []

    def instance(state, offset=(-.5, -1.4, 2.5), tint=None, ticket=0):
        return {'state': state['id'], 'x': Pixels.bits(offset[0]), 'y': Pixels.bits(offset[1]), 'z': Pixels.bits(offset[2]),
                **decisions(state['root'], ticket), **({'tints': [{'index': 0, 'color': tint}]} if tint is not None else {})}

    def add(name, rows, error=None, **options):
        config = {'name': name, 'width': 31, 'height': 17, 'pitch': Pixels.bits(.22), 'instances': rows, **options}
        frames.append(config)
        result = {'name': name, 'error': error, 'width': config['width'], 'height': config['height']}
        if error is None:
            quads = []
            geometry = []
            for row in rows:
                state = next(s for block in reference['blocks'].values() for s in block['states'] if s['id'] == row['state'])
                if state.get('render_shape') == 'INVISIBLE':
                    continue
                offset = tuple(Pixels.unbits(row[a]) for a in ['x', 'y', 'z'])
                colors = {t['index']: t['color'] for t in row.get('tints', [])}
                variants = Catalog.selected_variants(state['root'], row)
                for variant in variants:
                    actual_java = baked[model_key(variant)]
                    for raw in (q for group in actual_java['result']['quad_groups'].values() for q in group):
                        q = Pixels.production_quad(raw, slots, len(quads))
                        # production_quad contains the older fixture's cutout
                        # priority. CW/WM currently assigns sequential order.
                        q['order'] = len(quads)
                        q['material']['tint'] = colors.get(raw['tint_index'], 0xffffffff) if raw['tint_index'] >= 0 else 0xffffffff
                        q = Pixels.transform(q, offset)
                        quads.append(q)
                        geometry.append({'texture': q['material']['texture'], 'tint': q['material']['tint'],
                                         'vertices': [[*(Pixels.bits(x) for x in p), *(Pixels.bits(x) for x in uv)] for p, uv in q['vertices']]})
            rgb = Pixels.reference(Pixels.scene(quads, (0, 0, 0, 0, .22)), config['width'], config['height'], textures)
            result['pixels'] = [0xff000000 | int(r)<<16 | int(g)<<8 | int(b) for r, g, b in zip(rgb[::3], rgb[1::3], rgb[2::3])]
            result['geometry'] = geometry
        expected.append(result)

    stone = selected_state(reference, 'stone')
    grass = selected_state(reference, 'grass_block', {'snowy': 'false'})
    add('empty', [])
    add('stone-with-unused-untinted-grass-catalog', [instance(stone)])
    add('dirt', [instance(selected_state(reference, 'dirt'))])
    add('oak-planks', [instance(selected_state(reference, 'oak_planks'))])
    add('slab-bottom', [instance(selected_state(reference, 'oak_slab', {'type': 'bottom', 'waterlogged': 'false'}))])
    add('slab-top', [instance(selected_state(reference, 'oak_slab', {'type': 'top', 'waterlogged': 'false'}))])
    add('stairs-east-inner-left', [instance(selected_state(reference, 'oak_stairs', {'facing': 'east', 'half': 'bottom', 'shape': 'inner_left', 'waterlogged': 'false'}))])
    add('fence-north-east', [instance(selected_state(reference, 'oak_fence', {'east': 'true', 'north': 'true', 'south': 'false', 'waterlogged': 'false', 'west': 'false'}))])
    add('same-stone-state-distinct-weighted-tickets', [instance(stone, (-1.3, -.5, 2.5), ticket=0), instance(stone, (.3, -.5, 2.5), ticket=1)])
    add('grass-tint', [instance(grass, tint=0xff78b44a)])
    add('same-grass-state-distinct-cell-tints', [instance(grass, (-1.3, -.5, 2.5), 0xffff8080), instance(grass, (.3, -.5, 2.5), 0xff80ff80)])
    add('identity-before-unknown-state', [{'state': 9999999}], 'RegistryIdentityMismatch', identity='wrong-registry')
    add('state-not-loaded', [{'state': 9999999}], 'StateNotLoaded')
    add('missing-world-tint', [instance(grass)], 'WorldMesh:MissingTint')
    add('invalid-world-origin', [{**instance(stone), 'x': 0x7fc00000}], 'WorldMesh:BlockOrigin')
    add('block-budget-before-unknown-state', [{'state': 9999999}], 'WorldMesh:BlockLimit', blocks=0)
    add('binding-budget-before-unknown-state', [{'state': 9999999}], 'WorldMesh:BindingLimit', bindings=0)
    add('invalid-frame', [instance(stone)], 'WorldMesh:Frame', width=0)
    config = {'jar': str(Catalog.JAR), 'registry': str(Catalog.REGISTRY), 'frames': frames}
    data = {'entry': pin(ENTRY), 'sources': Catalog.sources(), 'catalog_reference': pin(Catalog.REFERENCE),
            'java_vertex_reference': pin(Pixels.REFERENCE), 'jar': pin(Catalog.JAR), 'config': config, 'expected': expected,
            'expected_texture_count': len(textures), 'scope': 'Actual generic RF catalog loader/world draw adapter; retained Java baked vertex/UV/material words plus official local textures and existing independent binary32/Pillow pixel oracle under current sequential world order. Geometry is compared as a multiset because Java quad groups do not retain element/face order. Explicit per-cell selection/tint; current grass coplanar side overlay ordering remains unresolved. No Java final raster, actor/wire, fluid, occlusion, GPU or presentation parity claim.'}
    target.write_text(json.dumps(data, indent=2, sort_keys=True)+'\n')
    print(json.dumps({'prepared_frames': len(frames), 'successful_pixel_frames': sum(r['error'] is None for r in expected), 'path': str(target)}))


def build():
    prep = json.loads((WORK/'preparation.json').read_text())
    assert prep['sources'] == Catalog.sources()
    manifest = Catalog.prepare_private(prep['sources'])
    emitter = Catalog.PRIVATE/'diagnose.mjs'
    old = str(Catalog.PRIVATE/'source/tests/resource_block_catalog.bend')
    new = str(Catalog.PRIVATE/'source/tests/resource_catalog_world.bend')
    text = emitter.read_text()
    assert old in text
    emitter.write_text(text.replace(old, new))
    manifest['files'][str(emitter)] = Catalog.sha(emitter)
    manifest['entry'] = new
    (Catalog.PRIVATE/'manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True)+'\n')
    receipt = Catalog.build_private(prep['sources'])
    (WORK/'build.json').write_text(json.dumps(receipt, indent=2, sort_keys=True)+'\n')


def run():
    prep = json.loads((WORK/'preparation.json').read_text())
    assert prep['sources'] == Catalog.sources()
    reports = []
    for repeat in range(2):
        result, process = Catalog.run([Catalog.BINARY, '--gpu', 'off', '--threads', '2', json.dumps(prep['config'], separators=(',', ':'))], f'world-native-{repeat}', 120)
        rows = [json.loads(line) for line in result.stdout.splitlines()]
        header, frames = rows[0], rows[1:]
        assert header['status'] == 'loaded' and header['textures'] == prep['expected_texture_count']
        assert header['registry_after']['id'] == 0 and header['registry_after']['identifier'] == 'minecraft:air'
        assert len(frames) == len(prep['expected'])
        checked = []
        for wanted, got in zip(prep['expected'], frames):
            assert wanted['name'] == got['name']
            assert got['retained_identity'] == header['registry_identity'] and got['retained_textures'] == header['textures']
            if wanted['error']:
                config = next(f for f in prep['config']['frames'] if f['name'] == wanted['name'])
                resource = 'world' if wanted['error'].startswith('WorldMesh:') else 'catalog'
                detail = '' if wanted['error'] == 'WorldMesh:Frame' else str(config['instances'][0]['state'])
                if wanted['error'] == 'RegistryIdentityMismatch':
                    detail = config['identity']+':'+header['registry_identity']
                diagnostic = {'status': 'error', 'code': wanted['error'], 'resource': resource, 'detail': detail}
                assert got['scene'] == got['render'] == diagnostic, (wanted['name'], got)
                checked.append({'name': wanted['name'], 'diagnostic': diagnostic, 'owner_retained': True})
            else:
                assert got['scene']['status'] == got['render']['status'] == 'ok', (wanted['name'], got)
                assert sorted(map(geometry_key, got['scene']['quads'])) == sorted(map(geometry_key, wanted['geometry'])), wanted['name']
                assert got['render']['pixels'] == wanted['pixels'], (wanted['name'], 'pixel mismatch')
                assert [q['order'] for q in got['scene']['quads']] == list(range(len(wanted['geometry']))), wanted['name']
                checked.append({'name': wanted['name'], 'pixels': len(wanted['pixels']), 'quads': len(wanted['geometry']), 'exact': True, 'owner_retained': True})
        reports.append({'process': process, 'frames': checked})
    load_failures = []
    absent = WORK/'unsupported-renderer-must-not-open.jar'
    assert not absent.exists()
    for name, requests, code in [
            ('unsupported-fluid-retains-registry', [{'name': 'minecraft:water'}], 'UnsupportedRenderer'),
            ('duplicate-request-retains-registry', [{'name': 'minecraft:stone'}]*2, 'DuplicateBlock')]:
        config = {'jar': str(absent), 'registry': str(Catalog.REGISTRY), 'requests': requests, 'frames': []}
        result, process = Catalog.run([Catalog.BINARY, '--gpu', 'off', '--threads', '2', json.dumps(config, separators=(',', ':'))], name, 120)
        rows = [json.loads(line) for line in result.stdout.splitlines()]
        assert len(rows) == 1 and rows[0]['status'] == 'error' and rows[0]['code'] == code, (name, rows)
        assert rows[0]['registry_after']['id'] == 0 and rows[0]['registry_after']['identifier'] == 'minecraft:air'
        load_failures.append({'name': name, 'code': code, 'registry_owner_retained': True, 'process': process})
    assert Catalog.sources() == prep['sources']
    evidence = {'status': 'PASS', 'scope': prep['scope'], 'preparation': pin(WORK/'preparation.json'), 'driver': pin(__file__),
                'entry': pin(ENTRY), 'binary': pin(Catalog.BINARY), 'build': pin(WORK/'build.json'), 'sources': prep['sources'],
                'reports': reports, 'load_failures': load_failures, 'no_window_opened': True, 'unchanged_sources': True}
    EVIDENCE.write_text(json.dumps(evidence, indent=2, sort_keys=True)+'\n')
    print(json.dumps({'status': 'PASS', 'frames_per_run': len(prep['expected']), 'repeats': 2, 'evidence': str(EVIDENCE)}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['prepare', 'build', 'run'])
    parser.add_argument('--generation', type=int, default=1, help='Fresh preserved generation after a source correction')
    args = parser.parse_args()
    generation(args.generation)
    try:
        {'prepare': prepare, 'build': build, 'run': run}[args.mode]()
    except BaseException as error:
        failure = EVIDENCE.with_name(f'resource_catalog_world_{args.mode}_failure_{time.time_ns()}.json')
        failure.write_text(json.dumps({'status': 'FAIL', 'mode': args.mode, 'error_type': type(error).__name__,
            'message': str(error), 'driver': pin(__file__), 'work': str(WORK),
            'retained_process_receipts': [pin(p) for p in sorted(WORK.glob('*.receipt.json'))]}, indent=2, sort_keys=True)+'\n')
        raise
