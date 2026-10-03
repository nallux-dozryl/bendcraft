#!/usr/bin/env python3
"""Verify native snapshot -> resource bake -> world mesh -> flat render.

Python supplies independent finite-world, IEEE, cached Java-quad and pixel
oracles. Production Bend receives source resources and registry bindings only;
it never receives the expected Java geometry or expected image bytes.
"""
from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
from fractions import Fraction
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PYTHON = Path.home() / '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
# The imported renderer oracle has the same dependency runtime requirement.
# Re-execute this runner first, so importing it cannot launch its own old suite.
if Path(sys.executable).resolve() != PYTHON.resolve():
    os.execv(str(PYTHON), [str(PYTHON), __file__, *sys.argv[1:]])

import numpy as np
from PIL import Image, __version__ as PILLOW_VERSION
import test_client_world as C
import test_mesh_render as M
import test_block_bake as K
import reference_model_probe as J

BEND = Path.home() / '.bend/bin/bend'
BINARY = ROOT / 'build/world-mesh-tests'
WORK = ROOT / 'build/world-mesh-oracle'
OFFICIAL = ROOT / 'generated/reference_blocks.tsv'
REFERENCE = ROOT / 'reference/model_semantics.json'
JAR = Path.home() / 'Library/Application Support/minecraft/versions/26.3/26.3.jar'
EVIDENCE = ROOT / 'evidence/world-mesh-native.json'
JAR_SHA = '4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d'
REFERENCE_SHA = '3cbe8aa7780f14c1b37159a885710b04680e3b6c4ffa4975b4d8297015f11e7e'
ROOTS = ['minecraft:block/dirt', 'minecraft:block/oak_planks', 'minecraft:block/stone']
SLOTS = {name: index for index, name in enumerate(ROOTS)}
CAMERA = [0, 0, 0, 0, 0x3e4ccccd]
HEADER = 'block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json'
ERRORS = {
    'valid': 'Done', 'empty': 'Done', 'missing-state': 'MissingState',
    'duplicate-state': 'DuplicateState', 'binding-limit': 'BindingLimit',
    'source-limit': 'SourceQuadLimit', 'block-limit': 'BlockLimit',
    'quad-limit': 'QuadLimit', 'translucent-limit': 'TranslucentLimit',
    'unsupported-limits': 'Limits', 'relative-camera': 'RelativeCamera',
    'nan-camera': 'RelativeCamera', 'dimensions-low': 'Frame',
    'dimensions-high': 'Frame', 'infinite-settings': 'Frame',
    'texture-count': 'TextureCount', 'texture-index': 'BakedQuad',
    'nan-source': 'BakedQuad', 'nan-uv': 'BakedQuad', 'nan-shade': 'BakedQuad',
    'light-alpha': 'Appearance', 'cutout-threshold': 'Appearance',
    'duplicate-tint': 'Appearance', 'untinted-map': 'Appearance',
    'tint-limit': 'Appearance', 'missing-tint': 'MissingTint',
    'mapped-tint': 'Done', 'animation': 'UnsupportedAnimation',
    'force-layer': 'BakedMetadata', 'emission-range': 'BakedMetadata',
    'nan-origin': 'BlockOrigin', 'translated-bound': 'TranslatedQuad',
}
APPEARANCE_FIXTURES = {'mapped-tint': [
    0x3f800000, 0x3f800000, 0, 0, 0,
    0x3f800000, 0, 0, 0, 0x3f800000,
    0, 0, 0, 0x3f800000, 0x3f800000,
    0, 0x3f800000, 0, 0x3f800000, 0,
    0, 0xff112233, 0xffffffff, 0x3f666666, 0, 0, 1, 0, 0,
]}


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def digest(path):
    return sha(Path(path).read_bytes())


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()


def source_fingerprints():
    """Hash local transitive Bend imports plus every imported oracle helper."""
    pending = [ROOT / 'tests/world_mesh.bend']
    seen = set()
    while pending:
        path = pending.pop().resolve()
        if path in seen:
            continue
        require(path.is_file(), f'missing native source {path}')
        seen.add(path)
        for name in re.findall(r'^import\s+(\.[^\s]+\.bend)', path.read_text(), re.MULTILINE):
            pending.append(path.parent / name)
    seen.update(ROOT / name for name in (
        'tools/test_world_mesh.py', 'tools/test_client_world.py',
        'tools/test_mesh_render.py', 'tools/test_block_bake.py',
        'tools/reference_model_probe.py', 'tools/reference_inventory.py',
        'tools/reference_block_probe.py', 'tools/reference_movement_probe.py'))
    return {str(path.relative_to(ROOT)): digest(path) for path in sorted(seen)}


def run(args, env=None, timeout=240):
    start = time.monotonic()
    process = subprocess.run(list(map(str, args)), cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=timeout)
    require(process.returncode == 0, {'command': list(map(str, args)),
                                     'exit_code': process.returncode,
                                     'stdout': process.stdout[-3000:],
                                     'stderr': process.stderr[-3000:]})
    return process.stdout, {'command': list(map(str, args)),
                            'seconds': round(time.monotonic() - start, 6),
                            'stdout_sha256': sha(process.stdout.encode()),
                            'stderr': process.stderr[-2000:]}


def registry_states(path):
    with Path(path).open() as stream:
        rows = csv.DictReader(stream, delimiter='\t')
        return {row['identifier']: int(row['default_state_id']) for row in rows}


def reference_inputs():
    require(digest(JAR) == JAR_SHA, 'installed client JAR is not the pinned 26.3 input')
    require(digest(REFERENCE) == REFERENCE_SHA, 'cached executed Java fixture changed')
    reference = json.loads(REFERENCE.read_text())
    J.validate(reference)
    quads, textures, resources = {}, [], {}
    with zipfile.ZipFile(JAR) as archive:
        # Validate the original model chains used by the existing Java probe.
        for name, source in reference['inputs']['models'].items():
            path = J.model_path(name)
            require(archive.read(path) == source.encode(), f'Java fixture source mismatch: {path}')
        for path, expected in reference['inputs']['resources'].items():
            data = archive.read(path)
            require(sha(data) == expected['sha256'] and len(data) == expected['bytes'],
                    f'cached Java resource fingerprint mismatch: {path}')
        for name in ROOTS:
            variant = next(v for v in reference['observations']['baked_variants']
                           if v['input'] == {'model': name})
            require(variant['status'] == 'ok' and variant['result']['quad_count'] == 6,
                    f'missing executed Java cube: {name}')
            groups = K.project_java(variant['result'])
            quads[name] = [q for group in K.ORDER for q in groups[group]]
            for quad in quads[name]:
                require(quad['sprite'] == name and quad['layer'] == 'SOLID' and
                        quad['tint_index'] == 0xffffffff and quad['material_flags'] == 0,
                        f'unexpected reference cube material: {name}')
            path = 'assets/minecraft/textures/' + name.split(':', 1)[1] + '.png'
            data = archive.read(path)
            with Image.open(io.BytesIO(data)) as image:
                array = np.array(image.convert('RGBA'), dtype=np.uint8)
            textures.append(array)
            resources[path] = {'sha256': sha(data), 'bytes': len(data),
                               'width': int(array.shape[1]), 'height': int(array.shape[0])}
    return quads, textures, {'client_sha256': JAR_SHA, 'reference_sha256': REFERENCE_SHA,
                             'cached_actual_java_cube_variants': 3, 'cached_actual_java_quads': 18,
                             'java_cube_state_ids': {
                                 'minecraft:' + name: reference['observations']['official_blockstates'][name]['states'][0]['state_id']
                                 for name in ('stone', 'dirt', 'oak_planks')},
                             'java_executed_in_this_run': False, 'textures': resources,
                             'atlas_policy': 'StaticNormalized, full-image [0,1] UVs; all Solid',
                             'slots': SLOTS}


def relative_words(cell, position):
    origin = [C.exact_ieee(value, 52, 11) for value in position]
    origin[1] = C.exact_ieee(C.exact_round(origin[1] + C.exact_ieee(0x3fcf5c29, 23, 8), 52, 11), 52, 11)
    return [C.exact_round(C.exact_ieee(C.exact_round(Fraction(value) - eye, 52, 11), 52, 11), 23, 8)
            for value, eye in zip(cell, origin, strict=True)]


def basic_snapshot(states, edited=False):
    cells = {(x, 0, z): 'minecraft:dirt' if x == 2 else 'minecraft:stone'
             for z in range(-3, 3) for x in range(-3, 3)}
    cells.update({(1, 1, 1): 'minecraft:dirt', (2, 1, 2): 'minecraft:oak_planks',
                  (2, 2, 2): 'minecraft:oak_planks'})
    if edited:
        cells[(0, 1, 0)] = 'minecraft:oak_planks'
    position = [0x3fe0000000000000, 0x3ff0000000000000, 0xc004000000000000]
    palette = {'minecraft:stone': 0, 'minecraft:dirt': 1, 'minecraft:oak_planks': 2}
    ordered = sorted(cells, key=lambda point: (point[2], point[1], point[0]))
    blocks = [relative_words(point, position) + [states[cells[point]], palette[cells[point]]]
              for point in ordered]
    return {'tick': 1, 'revision': 47, 'count': len(blocks), 'camera': CAMERA, 'blocks': blocks}


def far_snapshot(case, states):
    blocks = C.relative_expected(case)
    for block in blocks:
        block[3] = states['minecraft:stone']
    return {'tick': 1, 'revision': 1, 'count': 18, 'camera': CAMERA, 'blocks': blocks}


def add_f32(left, right):
    # The Fraction zero has no sign. IEEE nearest/even preserves -0 + -0;
    # cancellation of finite opposite values otherwise produces +0.
    if left == right == 0x80000000:
        return 0x80000000
    return C.exact_round(C.exact_ieee(left, 23, 8) + C.exact_ieee(right, 23, 8), 23, 8)


def expected_quads(snapshot, states, java_quads):
    models = {states['minecraft:' + name]: 'minecraft:block/' + name
              for name in ('stone', 'dirt', 'oak_planks')}
    result = []
    for block in snapshot['blocks']:
        require(block[3] in models, f'oracle state is unbound: {block[3]}')
        for quad in java_quads[models[block[3]]]:
            words = []
            for vertex in quad['vertices']:
                for local, origin in zip(vertex['position_f32'], block[:3], strict=True):
                    words.append(add_f32(int(local, 16), origin))
                words.extend(int(word, 16) for word in vertex['uv_f32'])
            words.extend([SLOTS[quad['sprite']], 0xffffffff, 0xffffffff,
                          int(quad['default_directional_brightness_f32'], 16),
                          0, 0, 0, 1, len(result)])
            require(len(words) == 29, 'oracle quad wire size')
            result.append(words)
    return result


def oracle_scene(snapshot, quads):
    output = []
    for words in quads:
        vertices = [(tuple(M.unbits(value) for value in words[i:i + 3]),
                     tuple(M.unbits(value) for value in words[i + 3:i + 5]))
                    for i in range(0, 20, 5)]
        texture, tint, light, shade, mode, threshold, address, cull, order = words[20:]
        output.append({'vertices': vertices,
                       'material': M.mat(texture, mode=('Opaque', 'Cutout', 'Translucent')[mode],
                                         tint=tint, light=light, shade=M.unbits(shade),
                                         address=('Clamp', 'Repeat')[address], threshold=threshold),
                       'cull': ('NoCull', 'Back')[cull], 'order': order})
    return M.scene(output, camera=tuple(M.unbits(word) for word in snapshot['camera']))


def parse_records(stdout):
    snapshots, quads, frames, errors, regressions, fixtures = {}, {}, {}, {}, [], {}
    for line in stdout.splitlines():
        fields = line.split('|')
        kind = fields[0]
        if kind == 'snapshot':
            require(len(fields) == 7 and fields[1] not in snapshots, f'snapshot record: {line[:150]}')
            snapshots[fields[1]] = C.snapshot('|'.join([fields[1], 'snapshot', *fields[2:]]))
        elif kind == 'quad':
            require(len(fields) == 4, f'quad record: {line[:150]}')
            values = list(map(int, fields[3].split(',')))
            require(len(values) == 29 and all(0 <= word <= 0xffffffff for word in values), 'quad words')
            output = quads.setdefault(fields[1], [])
            require(int(fields[2]) == len(output), 'quad index sequence')
            output.append(values)
        elif kind == 'frame':
            require(len(fields) == 5 and fields[1] not in frames, f'frame record: {line}')
            path = Path(fields[4])
            frames[fields[1]] = (int(fields[2]), int(fields[3]), path if path.is_absolute() else ROOT / path)
        elif kind == 'error':
            require(len(fields) == 3 and fields[1] not in errors, f'error record: {line}')
            errors[fields[1]] = fields[2]
        elif kind == 'fixture':
            require(len(fields) == 3 and fields[1] not in fixtures, f'fixture record: {line}')
            values = list(map(int, fields[2].split(',')))
            require(len(values) == 29 and all(0 <= word <= 0xffffffff for word in values), 'fixture quad words')
            fixtures[fields[1]] = values
        elif line == 'regressions\tpass':
            regressions.append(line)
        else:
            raise AssertionError(f'unrecognized native record: {line[:200]}')
    return snapshots, quads, frames, errors, regressions, fixtures


def verify_records(stdout, expected, states, java_quads, textures, prefix, errors=None, fixtures=None):
    snapshots, observed, frames, failures, regressions, actual_fixtures = parse_records(stdout)
    require(set(snapshots) == set(expected), {'snapshot_ids': list(snapshots), 'expected': list(expected)})
    require(set(observed) == set(expected), 'one quad collection per snapshot')
    require(failures == (errors or {}), {'errors': failures, 'expected': errors or {}})
    difference = K.first_difference(fixtures or {}, actual_fixtures)
    require(difference is None, {'appearance_fixture_difference': difference})
    summary = {'snapshots': 0, 'blocks': 0, 'quads': 0, 'frames': [],
               'negative_cases': sum(code != 'Done' for code in failures.values()),
               'appearance_quads_checked': len(actual_fixtures),
               'builtin_regressions': len(regressions)}
    for name, snapshot in expected.items():
        difference = K.first_difference(snapshot, snapshots[name])
        require(difference is None, {'scenario': name, 'snapshot_difference': difference})
        quads = expected_quads(snapshot, states, java_quads)
        difference = K.first_difference(quads, observed[name])
        require(difference is None, {'scenario': name, 'quad_difference': difference})
        summary['snapshots'] += 1
        summary['blocks'] += snapshot['count']
        summary['quads'] += len(quads)
        if name in frames:
            width, height, path = frames[name]
            require(path.is_file(), f'missing native PPM: {path}')
            require(path.read_bytes().startswith(b'P6\n'), 'native output must be binary PPM')
            with Image.open(path) as image:
                require(image.format == 'PPM' and image.size == (width, height), 'native frame format/dimensions')
                actual = image.convert('RGB').tobytes()
            wanted = M.reference(oracle_scene(snapshot, quads), width, height, textures)
            if actual != wanted:
                different = np.where(np.any(np.frombuffer(actual, np.uint8).reshape(-1, 3) !=
                                           np.frombuffer(wanted, np.uint8).reshape(-1, 3), axis=1))[0]
                raise AssertionError({'scenario': name, 'pixel_mismatches': len(different),
                                      'first_pixel': int(different[0]),
                                      'actual_rgb': list(actual[3 * different[0]:3 * different[0] + 3]),
                                      'expected_rgb': list(wanted[3 * different[0]:3 * different[0] + 3])})
            preview = WORK / f'{prefix}-{name}.png'
            Image.frombytes('RGB', (width, height), actual).save(preview)
            summary['frames'].append({'scenario': name, 'width': width, 'height': height,
                                      'pixels': width * height, 'rgb_sha256': sha(actual),
                                      'native_ppm_sha256': digest(path),
                                      'preview_png': str(preview.relative_to(ROOT)),
                                      'preview_png_sha256': digest(preview)})
    require(set(frames) <= set(expected), 'unrecognized frame scenario')
    return summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--skip-build', action='store_true')
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    sources = source_fingerprints()
    java_quads, textures, reference = reference_inputs()
    official_states = registry_states(OFFICIAL)
    require({name: official_states[name] for name in reference['java_cube_state_ids']} ==
            reference['java_cube_state_ids'], 'official fixture IDs differ from actual pinned Java registry observations')
    alternative = WORK / 'alternate-registry.tsv'
    alternative.write_text(HEADER + '\n' + ''.join(
        f'{index}\tminecraft:{name}\t{index}\t1\t{index}\t[]\n'
        for index, name in enumerate(('oak_planks', 'stone', 'air', 'dirt'))))
    alternative_states = registry_states(alternative)
    report = {'schema': 1, 'pin': '26.3', 'status': 'running',
              'timestamp_utc': datetime.now(timezone.utc).isoformat(),
              'scope': 'Finite camera-relative Core.World snapshots, explicit registry state bindings, '
                       'actual JAR resource loading and pure Bend cube baking/world mesh/flat pixels',
              'reference': reference, 'source_sha256_begin': sources,
              'oracle_sha256': sources['tools/test_world_mesh.py'],
              'oracle_environment': {'python': sys.version.split()[0],
                                     'numpy': np.__version__, 'pillow': PILLOW_VERSION},
              'input_sha256_begin': {'official_registry': digest(OFFICIAL),
                                     'alternate_registry': digest(alternative),
                                     'java_reference': REFERENCE_SHA, 'client_jar': JAR_SHA},
              'bend_executable_sha256': digest(BEND), 'builds': [], 'runs': [], 'groups': [],
              'registry_inputs': {'official_sha256': digest(OFFICIAL),
                                  'official_cube_states': {name: official_states['minecraft:' + name]
                                                           for name in ('stone', 'dirt', 'oak_planks')},
                                  'alternate_sha256': digest(alternative),
                                  'alternate_states': alternative_states},
              'boundaries': [
                  'Production consumes original JAR JSON/PNG and explicit bindings, never expected Java quads.',
                  'Java bake observations were previously executed and sealed; no fresh Java process in this run.',
                  'Static normalized full-image sprites, nearest sampling, explicit white tint/light and directional shade.',
                  'Bindings explicitly select unrotated cube models; weighted/multipart blockstate visual selection is outside this run.',
                  'All six faces retained; no neighbor occlusion, biome tint, AO, live lighting, animation or production atlas stitch.',
                  'Native binary PPM RGB is compared exactly; PNG previews are Python conversions of those observed pixels.',
                  'Hidden finite CPU verification does not establish visible client acceptance or whole-game parity.',
              ]}
    try:
        if not args.skip_build:
            _, build = run([BEND, 'tests/world_mesh.bend', '-o', BINARY], timeout=600)
            report['builds'].append(build)
        require(BINARY.is_file(), 'missing native world mesh harness; build it first')
        report['binary_sha256_begin'] = digest(BINARY)
        command = [BINARY, '--gpu', 'off']
        environment = os.environ.copy()
        environment.update(MC_WORLD_MESH_JAR=str(JAR), MC_BLOCK_REGISTRY=str(OFFICIAL), MC_HIDDEN_LAUNCH='1')
        stdout, execution = run([*command, 'errors'], environment)
        report['runs'].append(execution)
        report['groups'].append({'name': 'validation', **verify_records(
            stdout, {}, official_states, java_quads, textures, 'validation', errors=ERRORS,
            fixtures=APPEARANCE_FIXTURES)})
        expected = {name: basic_snapshot(official_states, name in ('raw-edit', 'uncached'))
                    for name in ('initial', 'cached', 'raw-edit', 'uncached')}
        stdout, execution = run(command, environment)
        report['runs'].append(execution)
        basic = verify_records(stdout, expected, official_states, java_quads, textures, 'official')
        require(len(basic['frames']) == 4, 'all basic/cached/edit frames must render')
        report['groups'].append({'name': 'official-fixture', **basic})
        environment['MC_BLOCK_REGISTRY'] = str(alternative)
        expected = {name: basic_snapshot(alternative_states, name in ('raw-edit', 'uncached'))
                    for name in ('initial', 'cached', 'raw-edit', 'uncached')}
        stdout, execution = run(command, environment)
        report['runs'].append(execution)
        alternate = verify_records(stdout, expected, alternative_states, java_quads, textures, 'alternate')
        require(len(alternate['frames']) == 4, 'all remapped-registry frames must render')
        require([frame['rgb_sha256'] for frame in basic['frames']] ==
                [frame['rgb_sha256'] for frame in alternate['frames']],
                'registry state remapping changed rendered material/geometry')
        report['groups'].append({'name': 'alternate-registry', **alternate})
        environment['MC_BLOCK_REGISTRY'] = str(OFFICIAL)
        far_cases = C.far_cases()
        report['far_inputs_sha256'] = sha(canonical(far_cases))
        for index, case in enumerate(far_cases):
            draw = index % 4 == 0
            fields = ['far', case['id'], str(int(draw)),
                      *[str(value & 0xffffffff) for value in case['base']],
                      *[word for value in case['position'] for word in C.words(value)]]
            stdout, execution = run([*command, *fields], environment)
            report['runs'].append(execution)
            expected = {case['id']: far_snapshot(case, official_states)}
            group = verify_records(stdout, expected, official_states, java_quads, textures, 'official')
            require(len(group['frames']) == int(draw), 'far frame selection must match draw flag')
            report['groups'].append({'name': case['id'], 'base': case['base'],
                                     'body_position_f64_hex': case['position'], **group})
        groups = report['groups']
        report['counters'] = {
            'native_invocations': len(report['runs']),
            'snapshots': sum(group['snapshots'] for group in groups),
            'blocks_checked': sum(group['blocks'] for group in groups),
            'quads_checked': sum(group['quads'] for group in groups),
            'exact_vertex_position_f32_words': 12 * sum(group['quads'] for group in groups),
            'exact_uv_f32_words': 8 * sum(group['quads'] for group in groups),
            'exact_material_and_order_words': 9 * sum(group['quads'] for group in groups),
            'frames': sum(len(group['frames']) for group in groups),
            'pixels': sum(frame['pixels'] for group in groups for frame in group['frames']),
            'far_coordinate_cases': len(far_cases), 'far_sign_combinations': 8,
            'validation_outcomes': len(ERRORS), 'negative_rejections': sum(value != 'Done' for value in ERRORS.values()),
            'positive_validation_outcomes': sum(value == 'Done' for value in ERRORS.values()),
            'appearance_quads_checked': sum(group['appearance_quads_checked'] for group in groups),
        }
        report['cache_observations'] = {
            'before_blocks': 39, 'after_blocks': 40, 'before_quads': 234, 'after_quads': 240,
            'tick_before_and_after': 1, 'revision_before_and_after': 47,
            'initial_and_cached_rgb_equal': basic['frames'][0]['rgb_sha256'] == basic['frames'][1]['rgb_sha256'],
            'edited_and_uncached_rgb_equal': basic['frames'][2]['rgb_sha256'] == basic['frames'][3]['rgb_sha256'],
            'edit_changes_pixels': basic['frames'][0]['rgb_sha256'] != basic['frames'][2]['rgb_sha256'],
            'alternate_state_ids_same_rgb': True,
        }
        with Image.open(ROOT / basic['frames'][0]['preview_png']) as before_image, \
                Image.open(ROOT / basic['frames'][2]['preview_png']) as after_image:
            before_pixels = np.array(before_image, dtype=np.uint8)
            after_pixels = np.array(after_image, dtype=np.uint8)
        report['cache_observations']['pixels_changed_by_edit'] = int(np.count_nonzero(
            np.any(before_pixels != after_pixels, axis=2)))
        require(report['cache_observations']['edit_changes_pixels'] and
                report['cache_observations']['pixels_changed_by_edit'] > 0,
                'raw edit must change the actual rendered frame')
        report['appearance_observation'] = {
            'tint': 0xff112233, 'light': 0xffffffff, 'shade_f32_hex': '3f666666',
            'address': 'Repeat', 'cull': 'NoCull', 'order': 0,
            'source_default_shade_f32_hex': '3f19999a',
            'explicit_nether_shade_selected': True,
        }
        require(report['cache_observations']['initial_and_cached_rgb_equal'] and
                report['cache_observations']['edited_and_uncached_rgb_equal'], 'cache frame mismatch')
        report['source_sha256_end'] = source_fingerprints()
        report['binary_sha256_end'] = digest(BINARY)
        report['input_sha256_end'] = {'official_registry': digest(OFFICIAL),
                                     'alternate_registry': digest(alternative),
                                     'java_reference': digest(REFERENCE), 'client_jar': digest(JAR)}
        report['sources_unchanged_during_run'] = report['source_sha256_end'] == sources
        report['binary_unchanged_during_run'] = report['binary_sha256_begin'] == report['binary_sha256_end']
        report['inputs_unchanged_during_run'] = report['input_sha256_begin'] == report['input_sha256_end']
        require(report['sources_unchanged_during_run'] and report['binary_unchanged_during_run'] and
                report['inputs_unchanged_during_run'], 'source, native binary or reference input changed during execution')
        report['status'] = 'passed'
        report['confidence'] = 'high for the stated finite CPU scenarios and exact observed comparisons'
    except Exception as error:
        report['status'] = 'failed'
        report['failure'] = str(error)
        raise
    finally:
        report['seconds'] = round(time.monotonic() - started, 6)
        EVIDENCE.write_text(json.dumps(report, sort_keys=True, indent=2) + '\n')
        print(json.dumps({key: report.get(key) for key in ('status', 'seconds', 'counters', 'failure')}))


if __name__ == '__main__':
    main()
