#!/usr/bin/env python3
"""Prepare, or explicitly run, the actual standalone generic catalog client.

Preparation reads saved fixtures, Java observations and original JAR textures;
it starts no Bend, Java, compiler, backend or Window process. --native consumes
successful immutable build receipts and uses the existing process owners. The
RGB oracle targets the current CPU renderer with Java-baked geometry, not a
vanilla GPU frame, atlas, AO, lightmap or Java positionRandom implementation.
"""
from __future__ import annotations

import argparse
import copy
import io
import json
import math
import os
import struct
import sys
import zipfile
from pathlib import Path
from unittest import mock

PYTHON = Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
if Path(sys.executable).resolve() != PYTHON.resolve():
    os.execv(str(PYTHON), [str(PYTHON), '-B', __file__, *sys.argv[1:]])
sys.dont_write_bytecode = True

import resource_block_catalog_test as Catalog
import test_mesh_render as Pixels
import test_playable_client_actor004_boundary as Boundary
import test_playable_resource_client as Pair

R, S, Host = Pair.R, Boundary.S, Pair.Host
ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT/'build/generic-resource-world-sample-client-native/002/renderer'
PREFIX = 'generic_resource_world_sample_client_runtime'
CATALOG_REFERENCE = ROOT/'reference/resource_block_catalog.json'
MODEL_REFERENCE = ROOT/'reference/model_semantics.json'
JAR = Boundary.JAR
WIDTH = HEIGHT = 128
require, pin, digest, canonical = R.require, R.pin, R.digest, R.canonical


def exclusive(path, value):
    R.write(path, value, True)


def mixed(seed, index):
    return ((seed ^ (((index + 1) & 0xffffffff) * 2246822519 & 0xffffffff))
            * 3266489917) & 0xffffffff


def expected_sample(world, record):
    """Read every Core cell independently; no native reply supplies expectations."""
    words, _ = S.PC.parse_snapshot(S.PR.decode(record.motion)[0])
    body = tuple(struct.unpack('>d', struct.pack('>Q', value))[0]
                 for value in S.PC.bits64(words[:6]))
    eye = (body[0], body[1] + S.PC.f32(record.eye), body[2])
    low = tuple(math.floor(value) - 4 for value in body)
    sections = {row['key']: row['cells'] for row in world['sections']}
    cells = []
    for z in range(low[2], low[2] + 8):
        for y in range(low[1], low[1] + 8):
            for x in range(low[0], low[0] + 8):
                xyz = (x, y, z)
                raw = tuple(value & 0xffffffff for value in xyz)
                state = sections[S.BASE.section_key(*xyz)][
                    (x & 15) + ((z & 15) << 4) + ((y & 15) << 8)]
                boundary = sum(value in (start, start + 7)
                               for value, start in zip(xyz, low))
                seed = mixed(mixed(mixed(0, raw[0]), raw[1]), raw[2])
                cells.append([*raw, boundary, state, seed,
                              [[], 0xffffffff, 0, 0, False, 128]])
    require(len(cells) == 512, 'Independent complete default aperture cardinality')
    return [world['registry'], world['tick'], world['revision'],
            list(S.PC.words64(tuple(map(S.PC.raw64, eye)))),
            [0, 0, 0, *words[39:41]], cells]


def fixture(glass=False):
    palette, identity, count = Boundary.palette_and_registry()
    world = Boundary.terrain(count, identity, palette)
    if not glass:
        S.BASE.set_block(world, -1, -60, 0, palette['minecraft:air'])
    record = Boundary.A.playable_look(Boundary.A.playable_spawn((0.5, -60., -2.5)), 15.)
    _, full = Boundary.Inventory.parse_inventory_full(Boundary.FULL_FIXTURE.read_bytes())
    full = copy.deepcopy(full)
    full['main']['selected'] = 4
    full['main']['slots'] = [None] * 36
    for slot, name, count in ((0, 'dirt', 4), (4, 'stone', 17),
                              (8, 'oak_planks', 6), (10, 'stone', 23),
                              (35, 'oak_planks', 6)):
        full['main']['slots'][slot] = Boundary.stack('minecraft:' + name, count)
    sample = expected_sample(world, record)
    require(len(world['sections']) == 104 and world['paused'], 'Complete paused default world')
    wanted = {palette['minecraft:oak_slab'], palette['minecraft:oak_stairs']}
    require(wanted <= {row[4] for row in sample[5]}, 'Real slab and stairs cells absent')
    payload = Boundary.bundle(world, 40, record, full, '')
    return {'world': world, 'record': record, 'full': full, 'sample': sample,
            'payload': payload, 'palette': palette,
            'authority': Boundary.authority(full, Boundary.empty_menu()),
            'glass': glass}


def model_key(value):
    return (value['model'], value.get('x', 0), value.get('y', 0),
            value.get('z', 0), value.get('uvlock', False))


def decision(root, seed):
    def ticket(choice, value):
        if choice['kind'] == 'single':
            return None
        require(choice['total'] > 0, 'Independent nonzero weighted total')
        return value % choice['total']
    if root['kind'] == 'variant':
        return {'ticket': ticket(root['choice'], seed)}
    return {'parts': {str(part['index']): ticket(part['choice'], mixed(seed, part['index']))
                      for part in root['parts']}}


def geometry(data):
    """Use actual Java vertex bits, retaining grouped-order uncertainty explicitly."""
    reference = json.loads(CATALOG_REFERENCE.read_bytes())
    java = json.loads(MODEL_REFERENCE.read_bytes())
    jar_pin = pin(JAR)
    require(jar_pin['sha256'] == reference['sources']['client']['sha256'], 'Pinned installed JAR drift')
    with zipfile.ZipFile(JAR) as jar:
        for row in java['source']['classes']:
            actual = jar.read(row['class'].replace('.', '/') + '.class')
            require(len(actual) == row['bytes'] and digest(actual) == row['sha256'],
                    'Java model observation class drift: ' + row['class'])
        layers = reference['static_solid_cutout_profile']['sprite_layers']
        names = sorted(layers)
        slots = {name: index for index, name in enumerate(names)}
        textures, texture_pins = [], []
        for name in names:
            path = Catalog.resource(name, 'textures', '.png')
            encoded = jar.read(path)
            textures.append(Pixels.np.array(Pixels.Image.open(io.BytesIO(encoded)).convert('RGBA')))
            texture_pins.append({'sprite': name, 'slot': slots[name], 'resource': path,
                                 'bytes': len(encoded), 'sha256': digest(encoded),
                                 'explicit_profile_layer': layers[name]})
    states = {state['id']: (block['identifier'], state)
              for block in reference['blocks'].values() for state in block['states']}
    baked = {model_key(row['input']): row['result']
             for row in java['observations']['baked_variants']}
    origin = tuple(S.PC.f64(word) for word in S.PC.bits64(data['sample'][3]))
    quads, selections = [], []
    for cell in data['sample'][5]:
        if cell[4] == data['palette']['minecraft:air']:
            continue
        require(cell[4] in states, 'State absent from independent catalog observation')
        name, state = states[cell[4]]
        require(state['render_shape'] == 'MODEL' and not state['has_block_entity']
                and state['fluid']['identifier'] == 'minecraft:empty', 'Fixture renderer requirement')
        selected = decision(state['root'], cell[5])
        variants = Catalog.selected_variants(state['root'], selected)
        selections.append({'point': cell[:3], 'state': cell[4], 'block': name,
                           'seed': cell[5], 'selection': selected, 'variants': variants})
        position = tuple(value if value < 0x80000000 else value - 0x100000000 for value in cell[:3])
        offset = tuple(Pixels.f(value - eye) for value, eye in zip(position, origin))
        for variant in variants:
            key = model_key(variant)
            require(key in baked, 'Missing actual Java baked variant: ' + repr(key))
            # These observations are grouped by cull direction. Their order is
            # not a claim about Bend's source element/face traversal order.
            for group in baked[key]['quad_groups'].values():
                for raw in group:
                    require(raw['tint_index'] == -1 and raw['layer'] == 'SOLID'
                            and layers[raw['sprite']] == 'solid', 'Narrow fixture material obligations')
                    quad = Pixels.production_quad(raw, slots, len(quads))
                    quad['order'] = len(quads)  # Current WM shared accumulator count.
                    quad['material']['tint'] = 0xffffffff
                    quad['fixture_state'] = cell[4]
                    quads.append(Pixels.transform(quad, offset))
    require(0 < len(quads) <= 4096, 'Current complete frame quad budget')
    camera = tuple(Pixels.unbits(value) for value in data['sample'][4])
    scene = Pixels.scene(quads, camera)
    return scene, textures, {'JAR': jar_pin, 'references': [pin(CATALOG_REFERENCE), pin(MODEL_REFERENCE)],
                            'textures': texture_pins, 'selections': selections,
                            'quads': len(quads), 'rendered_instances': len(selections)}


def opaque_oracle(scene, textures):
    """Full nearest-hit RGB plus an order-independent winning-tie audit."""
    np = Pixels.np
    n = WIDTH * HEIGHT
    directions = Pixels.directions(scene['camera'], WIDTH, HEIGHT, scene['settings'][2])
    origin = np.array(scene['camera'][:3], dtype=np.float32)
    background = scene['settings'][3]
    colors = np.tile([(background >> shift) & 255 for shift in (16, 8, 0)], (n, 1)).astype(np.uint32)
    best = np.full(n, np.float32(scene['settings'][1]) + np.float32(1), dtype=np.float32)
    ambiguity = np.zeros(n, dtype=bool)
    winners = np.full(n, 0xffffffff, dtype=np.uint32)
    for quad in scene['quads']:
        require(quad['material']['mode'] == 'Opaque', 'Opaque-only ordering audit')
        valid, depth, coords = Pixels.quad_hits(quad, origin, directions, scene['settings'])
        color = Pixels.color_sample(quad['material'], coords, textures)[:, :3]
        nearer = valid & (depth < best)
        tied = valid & (depth == best)
        ambiguity[tied] |= np.any(colors[tied] != color[tied], axis=1)
        ambiguity[nearer] = False
        best[nearer] = depth[nearer]
        colors[nearer] = color[nearer]
        winners[nearer] = quad['fixture_state']
    rgb = colors.astype(np.uint8).tobytes()
    # Cross-check the existing independent CPU oracle, including tie keys.
    require(rgb == Pixels.reference(scene, WIDTH, HEIGHT, textures), 'Independent oracle agreement')
    return rgb, [int(index) for index in np.flatnonzero(ambiguity)], winners


def prepare():
    data = fixture()
    scene, textures, evidence = geometry(data)
    world_rgb, ambiguous, winners = opaque_oracle(scene, textures)
    hud_textures = [textures[row['slot']] for model in R.Pixels.MODELS
                    for row in evidence['textures'] if row['sprite'] == model]
    require(len(hud_textures) == len(R.Pixels.MODELS), 'Independent HUD texture mapping')
    rgb = Pair.hud_oracle(world_rgb, data['full']['main'], hud_textures)
    unchanged = Pixels.np.all(Pixels.np.frombuffer(world_rgb, dtype=Pixels.np.uint8).reshape(-1, 3) ==
                             Pixels.np.frombuffer(rgb, dtype=Pixels.np.uint8).reshape(-1, 3), axis=1)
    visible = {name: int(Pixels.np.count_nonzero((winners == data['palette'][name]) & unchanged))
               for name in ('minecraft:oak_slab', 'minecraft:oak_stairs')}
    require(all(visible.values()), 'Slab/stairs must contribute uncovered full oracle pixels')
    report = {'status': 'prepared_native_pending', 'native_consumer_run': False,
              'source': pin(__file__), 'sections': len(data['world']['sections']),
              'sample_cells': len(data['sample'][5]), 'sample_sha256': digest(canonical(data['sample'])),
              'fixture_bytes': len(data['payload']), 'fixture_sha256': digest(data['payload']),
              'full_authority_sha256': digest(canonical(data['authority'])),
              'state_ids': sorted({row[4] for row in data['sample'][5]}),
              'oracle': {**evidence, 'extent': [WIDTH, HEIGHT], 'world_rgb_sha256': digest(world_rgb),
                         'world_HUD_rgb_sha256': digest(rgb), 'unresolved_order_pixels': ambiguous,
                         'slab_stairs_pixels_unchanged_by_HUD': visible,
                         'full_exact_pixel_expectation_ready': not ambiguous,
                         'scope': 'Java baked bits plus current CPU nearest/clamp, white light/tint and explicit GS seed tickets; grouped Java quads omit source traversal order, audited at all winning equal-depth hits. No Java positionRandom, AO/lightmap/atlas/GPU or vanilla frame claim.'},
              'helpers': Pair.observer(),
              'pending_artifacts': {'client': str(CLIENT), 'actor': str(Boundary.A.ACTOR)},
              'no_process_launched': True}
    return data, rgb, report


class Renderer(R.Renderer):
    """Reuse the real desktop observer and cleanup; keep genuine generic markers."""
    def __init__(self, binary, backend, label, helpers, *, frames=2):
        original = R.subprocess.Popen
        def launch(argv, *args, **kwargs):
            require(argv[:2] == [helpers['observer']['artifact'], str(binary)], 'Unexpected renderer launch')
            return original([*argv, '--width', str(WIDTH), '--height', str(HEIGHT),
                             '--render-scale', '100', '--hud-scale', '0', '--item-table',
                             str(ROOT/'generated/reference_item_metadata.tsv')], *args, **kwargs)
        with mock.patch.object(R.subprocess, 'Popen', launch):
            super().__init__(binary, backend, label, helpers, frames=frames, jar=JAR)

    def generic_frames(self):
        result = []
        for line in self.out.read_text().splitlines():
            if line.startswith('catalog.frame|'):
                words = line.split('|')
                require(len(words) == 6, 'Actual generic frame marker cardinality')
                result.append({'marker': line, 'serial': int(words[1]), 'registry': words[2],
                               'tick': int(words[3]), 'revision': int(words[4]), 'cells': int(words[5])})
        return result

    def finish_generic(self, *, status=0, markers=2):
        # R's legacy JSON frame counter stays zero; no invented legacy marker or
        # renderer identity is supplied to its observer checks.
        observation = super().finish(status=status)
        actual = self.generic_frames()
        require(len(actual) == markers and [row['serial'] for row in actual] == list(range(markers)),
                'Actual generic frame markers differ')
        timings = []
        for line in self.out.read_text().splitlines():
            if line.startswith('client.timing|'):
                fields = line.split('|')
                require(len(fields) == 3, 'Actual frame timing record shape')
                timings.append({'serial': int(fields[1]), 'milliseconds': int(fields[2])})
        require([row['serial'] for row in timings] == (list(range(markers)) if status == 0 else []),
                'Actual Window.frame timing serials differ')
        result = {'observer': observation, 'generic_frames': actual, 'Window_frame_timings': timings,
                  'legacy_JSON_frame_descriptions': 0, 'generic_marker_adapter': True}
        exclusive(self.directory/'generic-process.json', result)
        return result


def client_artifact(binary):
    binary = Path(binary).resolve()
    receipt = binary.parent/'build.json'
    value = json.loads(receipt.read_bytes())
    require(value['status'] == 'native_built_consumer_run_pending' and value['binary'] == pin(binary),
            'Actual standalone generic client build receipt/binary mismatch')
    for name in ('source_map', 'manifest'):
        require(value[name] == pin(value[name]['path']), 'Standalone client frozen input drift: ' + name)
    manifest = json.loads(Path(value['manifest']['path']).read_bytes())
    for path, expected in manifest['files'].items():
        require(pin(path)['sha256'] == expected, 'Standalone client immutable input drift: ' + path)
    return value


def correlated(relay, data, *, pairs=2):
    epoch, sequence, pending = None, 1, None
    observations = []
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
            require(command == [13, WIDTH, HEIGHT] and reply[1] == 7 and len(reply) == 5
                    and pending is None, 'Actual FrameCatalog admission')
            require(canonical(reply[4]) == canonical(data['sample']),
                    'ALL512 actual raw cells/appearance/seed/eye/camera differ')
            pending = request[3]
        elif command[0] == 8:
            require(command == [8] and reply[1] == 6 and len(reply) == 7
                    and canonical(reply[4:6]) == canonical([True, ''])
                    and canonical(reply[6]) == canonical(data['authority'])
                    and pending is not None and request[3] == pending + 1, 'Complete typed authoritative menu pair')
            observations.append({'sample_sequence': pending, 'menu_sequence': request[3],
                                 'all_cells': 512, 'sample_sha256': digest(canonical(data['sample'])),
                                 'menu_sha256': digest(canonical(reply[6]))})
            pending = None
        elif command[0] == 1:
            require(reply == [1, 2, epoch, request[3]] and len(command) == 2
                    and canonical(command[1][:2]) == canonical([False, False])
                    and all(action == [0] for action in command[1][2]), 'Hidden release-only input')
        else:
            require(command == [2] and reply == [1, 2, epoch, request[3]], 'Unexpected hidden command')
    require(epoch is not None and pending is None and len(observations) == pairs, 'Complete actual sample/menu pairs')
    return observations


def pixels(renderer, data, expected):
    frames = renderer.generic_frames()
    require(len(frames) == 2, 'Two actual presented generic descriptions')
    receipts = []
    for serial, row in enumerate(frames):
        require((row['registry'], row['tick'], row['revision'], row['cells']) ==
                (data['world']['registry'], data['world']['tick'], data['world']['revision'], 512),
                'Actual generic description identity')
        path = renderer.images/(str(serial) + '.ppm')
        raw = path.read_bytes()
        header = b'P6\n128 128\n255\n'
        require(raw.startswith(header) and len(raw) == len(header) + WIDTH * HEIGHT * 3,
                'Actual returned Window.frame physical PPM extent')
        actual = raw[len(header):]
        differences = [index for index in range(WIDTH * HEIGHT)
                       if actual[index*3:index*3+3] != expected[index*3:index*3+3]]
        receipt = {'serial': serial, 'PPM': pin(path), 'actual_rgb_sha256': digest(actual),
                   'expected_rgb_sha256': digest(expected), 'different_pixels': len(differences),
                   'first_differences': [{'pixel': index, 'xy': [index % WIDTH, index // WIDTH],
                       'actual': list(actual[index*3:index*3+3]),
                       'expected': list(expected[index*3:index*3+3])} for index in differences[:16]]}
        exclusive(renderer.directory/('pixels-' + str(serial) + '.json'), receipt)
        require(not differences, 'Full current generic renderer Java-geometry+HUD RGB differs; retained pixel receipt')
        receipts.append(receipt)
    return {'frames': 2, 'compared_pixels': 2 * WIDTH * HEIGHT, 'full_RGB_exact': True,
            'returned_Window_frame_CPU_Image': True, 'drawable_readback': False, 'receipts': receipts}


def finish_owned(actions, path):
    """Finish every owner while retaining the primary semantic failure."""
    primary = sys.exc_info()[1]
    errors = []
    for label, action in actions:
        try:
            action()
        except BaseException as error:
            errors.append((label, error))
    if errors:
        exclusive(path, {'primary': None if primary is None else {
            'type': type(primary).__name__, 'message': str(primary)},
            'secondary': [{'owner': label, 'type': type(error).__name__, 'message': str(error)}
                          for label, error in errors]})
        if primary is None:
            raise errors[0][1]


def sweep_owned(directory):
    primary = sys.exc_info()[1]
    try:
        rows = R.registered_cleanup()
        exclusive(directory/'owned-groups-cleanup.json', rows)
        require(all(not row['errors'] and not R.live(row['after']) for row in rows),
                'Owned native process group cleanup incomplete')
    except BaseException as error:
        exclusive(directory/'owned-groups-cleanup-secondary.json', {
            'type': type(error).__name__, 'message': str(error),
            'primary': None if primary is None else {'type': type(primary).__name__, 'message': str(primary)}})
        if primary is None:
            raise


def launch_lane(binary, actor_binary, directory, data, rgb, helpers, *, refusal=False):
    path = directory/'world.nbt'
    with path.open('xb') as handle:
        handle.write(data['payload'])
    actor = Pair.Backend(actor_binary, 'backend-glass' if refusal else 'backend-supported', path)
    renderer = relay = None
    try:
        raw, ping = actor.tcp(True)
        require(ping['peer'] == 42, 'Saved40 reserves player41 then actual public42')
        S.inspect(raw, data['record'])
        require(raw.call('world.clock') == S.P.clock(data['world']), 'Actual paused fixture clock')
        relay = Pair.Relay(actor, 'relay-glass' if refusal else 'relay-supported')
        renderer = Renderer(binary, relay, 'renderer-glass' if refusal else 'renderer-supported', helpers)
        observation = renderer.finish_generic(status=1 if refusal else 0, markers=1 if refusal else 2)
        relayed, relay_pin = relay.finish()
        pairs = correlated(relayed, data, pairs=1 if refusal else 2)
        if refusal:
            message = 'render: StateNotLoaded:catalog:' + str(data['palette']['minecraft:glass'])
            require(renderer.err.read_text().strip() == message and not list(renderer.images.iterdir()),
                    'Actual glass StateNotLoaded refusal or absence of presented pixels differs')
            result = {'status': 'expected_StateNotLoaded_refusal', 'message': message}
        else:
            result = pixels(renderer, data, rgb)
            S.inspect(raw, data['record'])
            saved, receipt = Boundary.saved(raw, path, data['world'], ping['peer'], data['record'],
                                            data['full'], '', directory, 'exact-typed-save')
            result['typed_save'] = receipt
            result['saved_bytes'] = saved
        result.update(observation=observation, relay=relay_pin, sample_menu_pairs=pairs)
        return result, path
    finally:
        actions = []
        if renderer is not None:
            actions.append(('renderer', renderer.cleanup))
        if relay is not None and relay.thread.is_alive():
            actions.append(('relay', lambda: relay.finish(failed=True)))
        actions.append(('backend', lambda: R.finish_backend(actor)))
        finish_owned(actions, actor.directory/'owners-cleanup-secondary.json')


def reload_lane(actor_binary, directory, path, data, saved):
    actor = Pair.Backend(actor_binary, 'backend-cold-reload', path)
    control = None
    try:
        raw, ping = actor.tcp(True)
        require(ping['peer'] == 44 and path.read_bytes() == saved, 'Exact cold save/reload public highwater')
        S.inspect(raw, data['record'])
        require(raw.call('world.clock') == S.P.clock(data['world']), 'Cold complete paused Core clock')
        control = Boundary.connect(actor)
        frame = control.call([13, WIDTH, HEIGHT], 7)
        menu = control.call([8], 6)
        require(canonical(frame[4]) == canonical(data['sample'])
                and canonical(menu[4:]) == canonical([True, '', data['authority']]),
                'Cold ALL512 sample and typed main/equipment/status/menu recovery')
        control.call([2], 2)
        control.close()
        _, receipt = Boundary.saved(raw, path, data['world'], ping['peer'], data['record'],
                                     data['full'], '', directory, 'exact-typed-reloaded-save')
        return {'status': 'exact_typed_cold_reload', 'sample_cells': 512, 'receipt': receipt}
    finally:
        actions = [] if control is None else [('private', control.close)]
        actions.append(('backend', lambda: R.finish_backend(actor)))
        finish_owned(actions, actor.directory/'owners-cleanup-secondary.json')


def native(binary, generation):
    data, rgb, preparation = prepare()
    require(preparation['oracle']['full_exact_pixel_expectation_ready'],
            'Java grouped geometry leaves differing winning tie colors; source traversal evidence required')
    actor_build = Boundary.artifact()
    client_build = client_artifact(binary)
    directory = ROOT/'build/generic-resource-world-sample-client-runtime'/f'{generation:03d}'
    directory.mkdir(parents=True, exist_ok=False)
    exclusive(directory/'preparation.json', preparation)
    exclusive(directory/'expected-sample.json', data['sample'])
    (directory/'expected.rgb').write_bytes(rgb)
    before = Boundary.runtime_pins()
    with Host.bindings(Pair, {'WORK': directory}), Host.bindings(R, {
            'WORK': directory, 'GROUPS': directory/'owned-groups.ndjson'}):
        try:
            supported, path = launch_lane(binary, Boundary.A.ACTOR, directory, data, rgb,
                                          preparation['helpers'])
            saved = supported.pop('saved_bytes')
            reload = reload_lane(Boundary.A.ACTOR, directory, path, data, saved)
            # Save the supported fixture separately before preparing the refusal
            # lane, so no file or already admitted expected result is replaced.
            glass_dir = directory/'glass-refusal'
            glass_dir.mkdir()
            with Host.bindings(Pair, {'WORK': glass_dir}), Host.bindings(R, {
                    'WORK': glass_dir, 'GROUPS': glass_dir/'owned-groups.ndjson'}):
                try:
                    glass, _ = launch_lane(binary, Boundary.A.ACTOR, glass_dir, fixture(True), rgb,
                                           preparation['helpers'], refusal=True)
                finally:
                    sweep_owned(glass_dir)
            require(Boundary.runtime_pins() == before, 'Actual fixture/JAR/reference/runtime input drift')
            require(Boundary.artifact() == actor_build and client_artifact(binary) == client_build,
                    'Admitted native artifact drift')
            result = {'status': 'PASS', 'native_consumer_run': True, 'source': pin(__file__),
                      'client': client_build, 'actor': actor_build,
                      'preparation': pin(directory/'preparation.json'), 'supported': supported,
                      'typed_cold_reload': reload, 'glass_refusal': glass,
                      'scope': preparation['oracle']['scope']}
            exclusive(directory/'result.json', result)
            return result
        except BaseException as error:
            exclusive(directory/'first-failure.json', {'status': 'failed',
                'type': type(error).__name__, 'message': str(error), 'native_consumer_run': True})
            raise
        finally:
            sweep_owned(directory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native', action='store_true', help='Explicitly launch admitted actual native artifacts')
    parser.add_argument('--client', type=Path, default=CLIENT)
    parser.add_argument('--generation', type=int, default=1, help='Fresh runtime receipt directory only')
    parser.add_argument('--prepare-directory', type=Path, help='Write pure independent prepared data to a NEW directory')
    args = parser.parse_args()
    require(1 <= args.generation <= 999, 'Runtime generation range')
    if args.native:
        require(args.prepare_directory is None, 'Native and preparation destinations are distinct')
        result = native(args.client, args.generation)
        print(json.dumps({'status': result['status'], 'native_consumer_run': True,
                          'compared_pixels': result['supported']['compared_pixels']}))
    else:
        data, rgb, report = prepare()
        if args.prepare_directory is not None:
            args.prepare_directory.mkdir(parents=True, exist_ok=False)
            exclusive(args.prepare_directory/'preparation.json', report)
            exclusive(args.prepare_directory/'expected-sample.json', data['sample'])
            with (args.prepare_directory/'fixture.nbt').open('xb') as handle:
                handle.write(data['payload'])
            with (args.prepare_directory/'expected.rgb').open('xb') as handle:
                handle.write(rgb)
        print(json.dumps({'status': report['status'], 'native_consumer_run': False,
                          'sections': report['sections'], 'sample_cells': report['sample_cells'],
                          'quads': report['oracle']['quads'],
                          'unresolved_order_pixels': len(report['oracle']['unresolved_order_pixels']),
                          'full_exact_pixel_expectation_ready': report['oracle']['full_exact_pixel_expectation_ready'],
                          'slab_stairs_pixels_unchanged_by_HUD': report['oracle']['slab_stairs_pixels_unchanged_by_HUD'],
                          'expected_RGB_sha256': report['oracle']['world_HUD_rgb_sha256']}))


if __name__ == '__main__':
    main()
