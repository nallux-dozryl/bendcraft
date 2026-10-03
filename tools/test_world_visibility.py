#!/usr/bin/env python3
"""Independent Java visibility, source-resource bake and flat-pixel verification.

Python only orchestrates native Bend execution and compares observed results.
The native harness receives original pinned model JSON and registry bindings;
expected visibility masks, Java geometry and pixels never become its inputs.
"""
from __future__ import annotations

import argparse
import copy
from datetime import datetime, timezone
from fractions import Fraction
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PYTHON = Path.home() / '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
# Re-exec before importing the NumPy helper, whose standalone entry uses this
# same dependency runtime. Importing under another Python must not run it.
if Path(sys.executable).resolve() != PYTHON.resolve():
    os.execv(str(PYTHON), [str(PYTHON), __file__, *sys.argv[1:]])

import numpy as np
from PIL import Image, __version__ as PILLOW_VERSION
import test_world_mesh as WM
import reference_world_visibility_probe as V

BEND = Path.home() / '.bend/bin/bend'
BINARY = ROOT / 'build/world-visibility-tests'
SAMPLER_BINARY = ROOT / 'build/world-visibility-sampler'
GEOMETRY_BINARY = ROOT / 'build/world-visibility-geometry'
BAKE_BINARY = ROOT / 'build/block-bake-tests'
BAKE_RECEIPT = ROOT / 'evidence/block-bake-tests.json'
WORK = ROOT / 'build/world-visibility-oracle'
REFERENCE = ROOT / 'reference/world_visibility.json'
REFERENCE_SHA = 'c81f6e26110d2275905a6d94f30462935814e8951fdd8e6c10f9a084febacbde'
OFFICIAL = WM.OFFICIAL
EVIDENCE = ROOT / 'evidence/world-visibility-native.json'
DIRECTIONS = ('down', 'up', 'north', 'south', 'west', 'east')
STATE_ORDER = ('minecraft:air', 'minecraft:stone', 'minecraft:dirt', 'minecraft:oak_planks')
MATERIALS = {'minecraft:stone': 0, 'minecraft:dirt': 1, 'minecraft:oak_planks': 2}
ERRORS = {
    'valid': 'Done',
    **{name: 'SampleAlignment' for name in (
        'missing-masks', 'extra-mask', 'mask-range', 'mask-cell', 'mask-state',
        'duplicate-raw', 'raw-material', 'palette-alias', 'relative-coordinate',
        'read-count', 'invalid-origin')},
    'missing-binding': 'Mesh:MissingState', 'pre-filter-budget': 'Mesh:QuadLimit',
    'unsupported-neighbor-limit': 'LimitsOrRegion', 'unsupported-mesh-limit': 'LimitsOrRegion',
    'block-limit': 'BlockLimit', 'neighbor-limit': 'NeighborReadLimit',
    'invalid-region': 'LimitsOrRegion', 'no-palette': 'Palette', 'palette-mismatch': 'Palette',
    'cached-duplicate': 'SnapshotAlignment', 'cached-material': 'SnapshotAlignment',
}
OWNER_IDS = ('unsupported-neighbor-limit', 'unsupported-mesh-limit', 'block-limit',
             'neighbor-limit', 'invalid-region', 'no-palette', 'palette-mismatch',
             'cached-duplicate', 'cached-material')
require, digest, sha, canonical = WM.require, WM.digest, WM.sha, WM.canonical


def visibility_reference():
    require(digest(REFERENCE) == REFERENCE_SHA, 'sealed actual Java visibility fixture changed')
    result = json.loads(REFERENCE.read_text())
    V.validate(result)
    require(result['fresh_jvm_reproductions'] == 2, 'missing independent fresh JVM reproductions')
    require(result['provenance']['client']['sha256'] == WM.JAR_SHA, 'visibility JAR differs from bake JAR')
    return result


def model_library():
    """Extract only the six original parent-chain resources; keep source text."""
    pending = list(WM.ROOTS)
    models, resources = {}, {}
    with zipfile.ZipFile(WM.JAR) as archive:
        while pending:
            identifier = pending.pop()
            if identifier in models:
                continue
            path = WM.J.model_path(identifier)
            raw = archive.read(path)
            source = raw.decode('utf-8')
            models[identifier] = source
            resources[path] = {'bytes': len(raw), 'sha256': sha(raw)}
            parent = json.loads(source).get('parent')
            if parent:
                pending.append(parent if ':' in parent else 'minecraft:' + parent)
    # Only object keys are serialized here; the embedded original model bytes,
    # including decimal spellings, are preserved exactly.
    text = '{' + ','.join(json.dumps(name) + ':' + models[name] for name in sorted(models)) + '}'
    target = WORK / 'source-model-library.json'
    target.write_text(text)
    return target, {'path': str(target.relative_to(ROOT)), 'sha256': digest(target),
                    'models': sorted(models), 'original_resources': resources}


def verified_bake_binary():
    receipt = json.loads(BAKE_RECEIPT.read_text())['native_compilation']
    require(receipt['exit_code'] == 0 and digest(BAKE_BINARY) == receipt['native_binary_sha256'],
            'existing BlockBake executable differs from its verified compilation receipt')
    for name, expected in receipt['transitive_sources'].items():
        require(digest(ROOT / name) == expected, f'BlockBake compiled dependency changed: {name}')
    return {'binary_path': str(BAKE_BINARY.relative_to(ROOT)), 'binary_sha256': digest(BAKE_BINARY),
            'receipt_sha256': digest(BAKE_RECEIPT), 'transitive_sources': receipt['transitive_sources'],
            'original_compile_seconds': receipt['elapsed_seconds']}


def actual_baked(models, java_quads):
    """Reuse the verified Bend baker; never construct production input from Java."""
    provenance = verified_bake_binary()
    sprites = {name: {'slot': slot, 'layer': 'SOLID', 'animated': False}
               for name, slot in WM.SLOTS.items()}
    inputs = ['{"models":' + models.read_text() + ',"root":' + json.dumps(name) +
              ',"x":0,"y":0,"z":0,"uvlock":false,"sprites":' + json.dumps(sprites, separators=(',', ':')) + '}'
              for name in WM.ROOTS]
    stdout, execution = run([BAKE_BINARY, '--gpu', 'off', *inputs], timeout=120)
    execution['input_json_files'] = []
    for index, source in enumerate(inputs):
        path = WORK / f'bake-source-{index}.json'
        path.write_text(source)
        execution['input_json_files'].append({'path': str(path.relative_to(ROOT)), 'sha256': digest(path)})
        execution['command'][3 + index] = '<original-source JSON argument from input_json_files>'
    lines = stdout.splitlines()
    require(len(lines) == 3, 'expected exactly three actual native bake outputs')
    observed = {}
    for name, line in zip(WM.ROOTS, lines, strict=True):
        result = json.loads(line)
        require(result['status'] == 'ok', {'bake_root': name, 'actual_bend_result': result})
        expected = []
        for direction, quad in zip(DIRECTIONS, java_quads[name], strict=True):
            expected.append({**quad, 'cull': direction, 'slot': WM.SLOTS[name],
                             'force_translucent': False, 'animated': False})
        difference = WM.K.first_difference(expected, result['quads'])
        require(difference is None, {'bake_root': name, 'actual_bend_vs_java_difference': difference})
        # This is the actual emitted native object, even after equality succeeds.
        observed[name] = result['quads']
    path = WORK / 'actual-bend-baked.json'
    path.write_text(json.dumps(observed, sort_keys=True, indent=2) + '\n')
    require(verified_bake_binary() == provenance, 'BlockBake binary/dependencies changed during execution')
    return observed, {'provenance': provenance, 'run': execution, 'quads_compared': 18,
                       'output_file': str(path.relative_to(ROOT)), 'output_sha256': digest(path),
                       'expected_java_geometry_supplied_as_native_input': False}


def native_input(models, textures, fixture=None):
    text = '{"models":' + models.read_text() + ',"textures":' + json.dumps(texture_records(textures), separators=(',', ':'))
    if fixture is not None:
        text += ',"fixture":' + json.dumps(fixture, separators=(',', ':'))
    return text + '}'


def texture_records(textures):
    records = []
    for pixels in textures:
        # Pillow returns RGBA; the checked native texture constructor uses ARGB.
        rgba = pixels.astype(np.uint32)
        words = ((rgba[:, :, 3] << 24) | (rgba[:, :, 0] << 16) |
                 (rgba[:, :, 1] << 8) | rgba[:, :, 2]).reshape(-1).tolist()
        records.append({'width': pixels.shape[1], 'height': pixels.shape[0], 'pixels': words})
    return records


def compact_baked(record):
    vertices = [[int(value, 16) for value in vertex['position_f32'] + vertex['uv_f32']]
                for vertex in record['vertices']]
    return [*vertices, record['direction'], record['cull'], record['sprite'], record['slot'],
            record['tint_index'], record['light_emission'], record['shade_direction_override'],
            record['layer'], record['force_translucent'], record['animated'],
            int(record['default_directional_brightness_f32'], 16),
            int(record['nether_directional_brightness_f32'], 16)]


def geometry_input(sample, baked, textures):
    palette = sample['palette']
    bindings = [[palette[index], [compact_baked(record) for record in baked['minecraft:block/' + name]]]
                for index, name in ((1, 'stone'), (2, 'dirt'), (3, 'oak_planks'))]
    return json.dumps({'sample': sample, 'bindings': bindings, 'textures': texture_records(textures)},
                      separators=(',', ':'))


def expected_origin(position):
    words = list(position)
    y = WM.C.exact_ieee(words[1], 52, 11) + WM.C.exact_ieee(0x3fcf5c29, 23, 8)
    words[1] = WM.C.exact_round(y, 52, 11)
    return [int(word) for value in words for word in WM.C.words(f'{value:016x}')]


def raw_expectations(java_scene, states):
    low, sizes = java_scene['snapshot_bounds'][:3], java_scene['snapshot_bounds'][3:]
    output = []
    for block in java_scene['blocks']:
        boundary = sum(point == origin or point == origin + size - 1
                       for point, origin, size in zip(block['position'], low, sizes, strict=True))
        output.append([*block['position_u32'], boundary, states[block['state']], MATERIALS[block['state']]])
    return output


def with_sampledata(expected, java_scene, states, position):
    raw = raw_expectations(java_scene, states)
    return {**expected, 'sampledata': {'origin': expected_origin(position),
                                      'palette': [states[name] for name in STATE_ORDER], 'raw': raw},
            'maskdata': [[*row[:5], mask[4]] for row, mask in zip(raw, expected['masks'], strict=True)]}


def fixture_input(java_scene, position):
    """Explicitly allocate all snapshot and one-cell halo sections as air."""
    x, y, z, w, h, d = java_scene['snapshot_bounds']
    section_set = {(px // 16, py // 16, pz // 16)
                   for pz in range(z - 1, z + d + 1)
                   for py in range(y - 1, y + h + 1)
                   for px in range(x - 1, x + w + 1)}
    # Include explicit fixture cells outside the one-cell halo as well. Those
    # cells demonstrate that the sample does not accidentally widen its bounds.
    section_set.update(tuple(value // 16 for value in cell['position'])
                       for cell in java_scene['world_nonair_cells'])
    sections = [[(value * 16) & 0xffffffff for value in point]
                for point in sorted(section_set, key=lambda point: (point[2], point[1], point[0]))]
    cells = [[*[value & 0xffffffff for value in cell['position']], cell['state']]
             for cell in java_scene['world_nonair_cells']]
    return {'bounds': [x & 0xffffffff, y & 0xffffffff, z & 0xffffffff, w, h, d],
            'body_words': [int(word) for value in position for word in WM.C.words(f'{value:016x}')],
            'sections': sections, 'cells': cells}


def source_fingerprints():
    pending = [ROOT / 'tests/world_visibility.bend']
    seen = set()
    while pending:
        path = pending.pop().resolve()
        if path in seen:
            continue
        require(path.is_file(), f'missing native source {path}')
        seen.add(path)
        for name in re.findall(r'^import\s+(\.[^\s]+\.bend)', path.read_text(), re.MULTILINE):
            pending.append(path.parent / name)
    # These are all local transitive Python oracle/provenance helper files.
    seen.update(ROOT / name for name in (
        'tools/test_world_visibility.py', 'tools/reference_world_visibility_probe.py',
        'tools/test_world_mesh.py', 'tools/test_client_world.py', 'tools/test_mesh_render.py',
        'tools/test_block_bake.py', 'tools/reference_model_probe.py', 'tools/reference_inventory.py',
        'tools/reference_block_probe.py', 'tools/reference_movement_probe.py'))
    return {str(path.relative_to(ROOT)): digest(path) for path in sorted(seen)}


def scene(reference, identifier):
    return next(item for item in reference['observations']['scenes'] if item['id'] == identifier)


def expected_masks(java_scene, states):
    return [[*block['position_u32'], states[block['state']], block['visible_direction_mask']]
            for block in java_scene['blocks']]


def scene_snapshot(java_scene, states, position, tick, revision):
    blocks = [WM.relative_words(block['position'], position) +
              [states[block['state']], MATERIALS[block['state']]]
              for block in java_scene['blocks']]
    return {'tick': tick, 'revision': revision, 'count': len(blocks),
            'camera': WM.CAMERA, 'blocks': blocks}


def visible_quads(snapshot, masks, states, java_quads):
    """Filter measured directional groups while preserving every retained word."""
    full = WM.expected_quads(snapshot, states, java_quads)
    require(len(full) == 6 * len(masks), 'closed cube reference must contain exactly six grouped quads')
    result = []
    for block_index, mask in enumerate(masks):
        require(mask[3] == snapshot['blocks'][block_index][3], 'oracle raw/relative state alignment')
        for direction in range(6):
            if mask[4] & (1 << direction):
                # Keep the pre-filter sequential order, including resulting gaps.
                result.append(full[6 * block_index + direction])
    return result


def standalone_quads(states, java_quads):
    snapshot = {'blocks': [[0, 0, 0, states['minecraft:stone'], 0]]}
    down = WM.expected_quads(snapshot, states, java_quads)[0]
    down[23] = int(java_quads['minecraft:block/stone'][0]['nether_directional_brightness_f32'], 16)
    down[26], down[27] = 1, 0  # Repeat, NoCull: deliberately retained metadata.
    return {'ungrouped-hidden-neighbors': [down], 'declared-east-normal-down': [down],
            'declared-east-hidden': []}


def pair_expectations(reference):
    return {(STATE_ORDER.index(record['current']), STATE_ORDER.index(record['adjacent']),
             record['direction_ordinal']): record['should_render_face']
            for record in reference['observations']['state_pair_matrix']
            if record['position_id'] == 'origin'}


def neighbor_expectations(reference):
    return {(record['position_id'], record['direction_ordinal']): record['neighbor_u32']
            for record in reference['observations']['neighbor_steps']}


def process_samples(parent):
    result = subprocess.run(['ps', '-axo', 'pid=,ppid=,rss=,etime=,command='],
                            capture_output=True, text=True, check=True)
    processes = []
    for line in result.stdout.splitlines():
        fields = line.split(None, 4)
        if len(fields) == 5:
            processes.append({'pid': int(fields[0]), 'ppid': int(fields[1]),
                              'rss_kib': int(fields[2]), 'elapsed': fields[3], 'command': fields[4]})
    owned = {parent}
    while True:
        extended = owned | {item['pid'] for item in processes if item['ppid'] in owned}
        if extended == owned:
            break
        owned = extended
    return [item for item in processes if item['pid'] in owned]


class CommandFailure(RuntimeError):
    def __init__(self, execution, stdout):
        self.execution = execution
        self.stdout = stdout
        super().__init__({'execution': execution, 'stdout': stdout[-3000:]})


def run(command, environment=None, timeout=240, build=False):
    started = time.monotonic()
    process = subprocess.Popen(list(map(str, command)), cwd=ROOT, env=environment,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, start_new_session=True)
    execution = {'command': list(map(str, command)), 'pid': process.pid, 'rss_samples': [], 'build': build}
    if build:
        print(json.dumps({'build_started': True, 'python_pid': os.getpid(),
                          'bend_pid': process.pid, 'timeout_seconds': timeout}), flush=True)
    try:
        try:
            stdout, stderr = process.communicate(timeout=min(timeout, 120) if build else timeout)
        except subprocess.TimeoutExpired:
            if not build or timeout <= 120:
                raise
            sample = {'seconds': round(time.monotonic() - started, 6), 'processes': process_samples(process.pid)}
            execution['rss_samples'].append(sample)
            print(json.dumps({'compiler_rss_sample': sample}), flush=True)
            stdout, stderr = process.communicate(timeout=max(0.1, timeout - (time.monotonic() - started)))
    except subprocess.TimeoutExpired:
        # A timed-out code generator can have clang descendants. Kill this
        # runner's isolated process group, rather than only the immediate Bend.
        execution['timeout'] = True
        execution['rss_samples'].append({'seconds': round(time.monotonic() - started, 6),
                                         'processes': process_samples(process.pid)})
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass  # It completed after the timeout and before signal delivery.
        try:
            stdout, stderr = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            stdout, stderr = process.communicate()
        execution.update(seconds=round(time.monotonic() - started, 6), exit_code=process.returncode,
                         stdout_sha256=sha(stdout.encode()), stderr=stderr[-3000:])
        raise CommandFailure(execution, stdout)
    execution.update(seconds=round(time.monotonic() - started, 6), exit_code=process.returncode,
                     stdout_sha256=sha(stdout.encode()), stderr=stderr[-3000:])
    if process.returncode != 0:
        raise CommandFailure(execution, stdout)
    return stdout, execution


def parse_records(stdout):
    records = {key: {} for key in ('snapshots', 'masks', 'maskdata', 'sampledata', 'quads', 'frames', 'errors', 'owners', 'pairs', 'neighbors')}
    records['regressions'] = []
    for line in stdout.splitlines():
        fields = line.split('|')
        kind = fields[0]
        if kind == 'snapshot':
            require(len(fields) == 7 and fields[1] not in records['snapshots'], f'snapshot record: {line[:150]}')
            records['snapshots'][fields[1]] = WM.C.snapshot('|'.join([fields[1], 'snapshot', *fields[2:]]))
        elif kind == 'mask':
            require(len(fields) == 4 and fields[1] not in records['masks'], f'mask record: {line[:150]}')
            values = [list(map(int, row.split(','))) for row in fields[3].split(';') if row]
            require(all(len(row) == 5 and all(0 <= word <= 0xffffffff for word in row) and row[4] <= 63
                        for row in values), 'visibility mask words')
            records['masks'][fields[1]] = {'neighbor_reads': int(fields[2]), 'values': values}
        elif kind == 'quad':
            require(len(fields) == 4, f'quad record: {line[:150]}')
            values = list(map(int, fields[3].split(',')))
            require(len(values) == 29 and all(0 <= word <= 0xffffffff for word in values), 'quad words')
            output = records['quads'].setdefault(fields[1], [])
            require(int(fields[2]) == len(output), 'quad index sequence')
            output.append(values)
        elif kind == 'sampledata':
            require(len(fields) == 5 and fields[1] not in records['sampledata'], f'sampledata record: {line[:150]}')
            origin = list(map(int, fields[2].split(',')))
            palette = list(map(int, fields[3].split(',')))
            raw = [list(map(int, row.split(','))) for row in fields[4].split(';') if row]
            require(len(origin) == 6 and len(palette) == 4 and all(len(row) == 6 for row in raw), 'sampledata framing')
            require(all(0 <= value <= 0xffffffff for value in [*origin, *palette, *[word for row in raw for word in row]]),
                    'sampledata raw words')
            records['sampledata'][fields[1]] = {'origin': origin, 'palette': palette, 'raw': raw}
        elif kind == 'maskdata':
            require(len(fields) == 3 and fields[1] not in records['maskdata'], f'maskdata record: {line[:150]}')
            values = [list(map(int, row.split(','))) for row in fields[2].split(';') if row]
            require(all(len(row) == 6 and row[3] <= 3 and row[5] <= 63 and
                        all(0 <= word <= 0xffffffff for word in row) for row in values), 'maskdata raw words')
            records['maskdata'][fields[1]] = values
        elif kind == 'frame':
            require(len(fields) == 5 and fields[1] not in records['frames'], f'frame record: {line}')
            path = Path(fields[4])
            records['frames'][fields[1]] = (int(fields[2]), int(fields[3]), path if path.is_absolute() else ROOT / path)
        elif kind == 'error':
            require(len(fields) == 3 and fields[1] not in records['errors'], f'error record: {line}')
            records['errors'][fields[1]] = fields[2]
        elif kind == 'owner':
            require(len(fields) == 3 and fields[1] not in records['owners'], f'owner record: {line}')
            values = list(map(int, fields[2].split(',')))
            require(len(values) == 3 and all(value >= 0 for value in values), 'owner observation words')
            records['owners'][fields[1]] = values
        elif kind == 'pair':
            require(len(fields) == 5 and fields[4] in ('true', 'false'), f'pair record: {line}')
            key = tuple(map(int, fields[1:4]))
            require(key not in records['pairs'], 'duplicate pair record')
            records['pairs'][key] = fields[4] == 'true'
        elif kind == 'neighbor':
            require(len(fields) == 4, f'neighbor record: {line}')
            key = (fields[1], int(fields[2]))
            require(key not in records['neighbors'], 'duplicate neighbor record')
            values = list(map(int, fields[3].split(',')))
            require(len(values) == 3 and all(0 <= word <= 0xffffffff for word in values), 'neighbor coordinate words')
            records['neighbors'][key] = values
        elif line == 'regressions\tpass':
            records['regressions'].append(line)
        else:
            raise AssertionError(f'unrecognized native record: {line[:200]}')
    return records


def verify_records(stdout, expected, states, java_quads, textures, prefix,
                   errors=None, owners=None, pairs=None, neighbors=None, standalone=None):
    observed = parse_records(stdout)
    require(set(observed['snapshots']) == set(expected), 'native snapshot scenario set differs')
    require(set(observed['masks']) == set(expected), 'native visibility-mask scenario set differs')
    require(set(observed['quads']) <= set(expected) | set(standalone or {}), 'unrecognized native quad scenario')
    require(set(observed['frames']) == {name for name, value in expected.items() if value.get('draw', True)},
            'native frame selection differs from requested finite scenarios')
    require(observed['errors'] == (errors or {}), {'errors': observed['errors'], 'expected': errors or {}})
    require(observed['owners'] == (owners or {}), {'owners': observed['owners'], 'expected': owners or {}})
    require(observed['pairs'] == (pairs or {}), 'native pair matrix differs from sealed Java')
    require(observed['neighbors'] == (neighbors or {}), 'native signed stepping differs from sealed Java')
    report = {'snapshots': 0, 'blocks': 0, 'neighbor_reads': 0, 'visible_faces': 0, 'hidden_faces': 0,
              'quads': 0, 'frames': [], 'pair_results': len(observed['pairs']),
              'neighbor_results': len(observed['neighbors']), 'validation_outcomes': len(observed['errors']),
              'negative_rejections': sum(value != 'Done' for value in observed['errors'].values()),
              'owner_recoveries_checked': len(observed['owners']),
              'standalone_group_cases': len(standalone or {}),
              'standalone_quads_checked': sum(len(value) for value in (standalone or {}).values()),
              'builtin_regressions': len(observed['regressions'])}
    for name, wanted in (standalone or {}).items():
        difference = WM.K.first_difference(wanted, observed['quads'].get(name, []))
        require(difference is None, {'standalone_cull_group': name, 'quad_difference': difference})
    for name, value in expected.items():
        snapshot, masks = value['snapshot'], value['masks']
        difference = WM.K.first_difference(snapshot, observed['snapshots'][name])
        require(difference is None, {'scenario': name, 'snapshot_difference': difference})
        reads = 6 * len(masks)
        difference = WM.K.first_difference({'neighbor_reads': reads, 'values': masks}, observed['masks'][name])
        require(difference is None, {'scenario': name, 'visibility_difference': difference})
        if 'sampledata' in value:
            difference = WM.K.first_difference(value['sampledata'], observed['sampledata'].get(name))
            require(difference is None, {'scenario': name, 'sampledata_difference': difference})
            difference = WM.K.first_difference(value['maskdata'], observed['maskdata'].get(name))
            require(difference is None, {'scenario': name, 'maskdata_difference': difference})
        quads = visible_quads(snapshot, masks, states, java_quads)
        difference = WM.K.first_difference(quads, observed['quads'].get(name, []))
        require(difference is None, {'scenario': name, 'quad_difference': difference})
        report['snapshots'] += 1
        report['blocks'] += len(masks)
        report['neighbor_reads'] += reads
        report['visible_faces'] += len(quads)
        report['hidden_faces'] += reads - len(quads)
        report['quads'] += len(quads)
        if name not in observed['frames']:
            continue
        width, height, path = observed['frames'][name]
        require((width, height) == (32, 24), 'native fixture must render the requested 32x24 frame')
        require(path.read_bytes().startswith(b'P6\n'), 'native output must be binary PPM')
        with Image.open(path) as image:
            require(image.format == 'PPM' and image.size == (width, height), 'native frame format/dimensions')
            actual = image.convert('RGB').tobytes()
        wanted = WM.M.reference(WM.oracle_scene(snapshot, quads), width, height, textures)
        if actual != wanted:
            different = np.where(np.any(np.frombuffer(actual, np.uint8).reshape(-1, 3) !=
                                       np.frombuffer(wanted, np.uint8).reshape(-1, 3), axis=1))[0]
            raise AssertionError({'scenario': name, 'pixel_mismatches': len(different),
                                  'first_pixel': int(different[0]),
                                  'actual_rgb': list(actual[3 * different[0]:3 * different[0] + 3]),
                                  'expected_rgb': list(wanted[3 * different[0]:3 * different[0] + 3])})
        preview = WORK / f'{prefix}-{name}.png'
        Image.frombytes('RGB', (width, height), actual).save(preview)
        report['frames'].append({'scenario': name, 'width': width, 'height': height,
                                 'pixels': width * height, 'rgb_sha256': sha(actual),
                                 'native_ppm_sha256': digest(path),
                                 'preview_png': str(preview.relative_to(ROOT)),
                                 'preview_png_sha256': digest(preview)})
    return report


def prepare():
    WORK.mkdir(parents=True, exist_ok=True)
    reference = visibility_reference()
    quads, textures, bake_reference = WM.reference_inputs()
    models, model_source = model_library()
    states = WM.registry_states(OFFICIAL)
    require([states[name] for name in STATE_ORDER] ==
            [record['state_id'] for record in reference['observations']['states']],
            'official registry differs from measured Java default state IDs')
    for identifier, edited in (('fixture-39', False), ('fixture-edited-40', True)):
        java_scene = scene(reference, identifier)
        snapshot = scene_snapshot(java_scene, states,
                                  [0x3fe0000000000000, 0x3ff0000000000000, 0xc004000000000000], 1, 47)
        require(snapshot == WM.basic_snapshot(states, edited), 'independent Java fixture/snapshot disagrees with finite-world oracle')
        masks = expected_masks(java_scene, states)
        retained = visible_quads(snapshot, masks, states, quads)
        require(len(retained) == java_scene['visible_faces'], 'visible quad and Java face counts differ')
    return reference, quads, textures, bake_reference, models, model_source, states


def custom_cases(reference):
    origin = scene(reference, 'halo-edge-origin')
    origin_position = [WM.C.exact_round(value, 52, 11)
                       for value in (Fraction(1, 2), Fraction(1, 2), Fraction(-5, 2))]
    fixture = fixture_input(origin, origin_position)
    output = [{'id': 'halo-edge-origin', 'java_scene': origin, 'position': origin_position,
               'fixture': fixture, 'draw': True,
               'revision': len(fixture['sections']) + len(fixture['cells'])}]
    for index, case in enumerate(WM.C.far_cases()):
        source = scene(reference, f'halo-edge-far-{index // 4}')
        position = [int(value, 16) for value in case['position']]
        fixture = fixture_input(source, position)
        output.append({'id': case['id'], 'java_scene': source, 'position': position,
                       'fixture': fixture, 'draw': index % 4 == 0, 'base': case['base'],
                       'revision': len(fixture['sections']) + len(fixture['cells'])})
    return output


def custom_expected(case, states):
    return {'snapshot': scene_snapshot(case['java_scene'], states, case['position'], 1, case['revision']),
            'masks': expected_masks(case['java_scene'], states), 'draw': case['draw']}


def halo_edit_case(reference, states):
    original = custom_cases(reference)[0]
    source = copy.deepcopy(original['java_scene'])
    source['snapshot_bounds'] = [*source['blocks'][0]['position'], 1, 1, 1]
    fixture = fixture_input(source, original['position'])
    revision = len(fixture['sections']) + len(fixture['cells'])
    snapshot = scene_snapshot(source, states, original['position'], 1, revision)
    masks = expected_masks(source, states)
    after = copy.deepcopy(masks)
    after[0][4] |= 1  # Actual sealed air-adjacent pair result for Down.
    return fixture, {name: {'snapshot': snapshot, 'masks': after if edited else masks}
                     for name, edited in (('halo-initial', False), ('halo-cached', False),
                                          ('halo-edit', True), ('halo-recached', True))}


def compare_edit_frames(group):
    frames = group['frames']
    require([frame['scenario'] for frame in frames] == ['initial', 'cached', 'raw-edit', 'uncached'],
            'basic frame sequence')
    require(frames[0]['rgb_sha256'] == frames[1]['rgb_sha256'], 'cached initial pixels differ')
    require(frames[2]['rgb_sha256'] == frames[3]['rgb_sha256'], 'uncached edited pixels differ')
    with Image.open(ROOT / frames[0]['preview_png']) as a, Image.open(ROOT / frames[2]['preview_png']) as b:
        different = int(np.count_nonzero(np.any(np.array(a, np.uint8) != np.array(b, np.uint8), axis=2)))
    require(different > 0 and frames[0]['rgb_sha256'] != frames[2]['rgb_sha256'],
            'raw inside-region edit must change the actual rendered frame')
    return {'initial_and_cached_rgb_equal': True, 'edited_and_uncached_rgb_equal': True,
            'edit_changes_pixels': True, 'pixels_changed_by_edit': different,
            'tick_before_and_after': 1, 'revision_before_and_after': 47,
            'blocks_before': 39, 'blocks_after': 40, 'quads_before': 108, 'quads_after': 112}


def combined_main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--skip-build', action='store_true')
    parser.add_argument('--prepare-only', action='store_true', help='validate independent inputs; perform no Bend execution')
    args = parser.parse_args()
    reference, quads, textures, bake_reference, models, model_source, states = prepare()
    if args.prepare_only:
        cases = custom_cases(reference)
        for case in cases:
            expected = custom_expected(case, states)
            require(len(visible_quads(expected['snapshot'], expected['masks'], states, quads)) == 3,
                    'closed halo oracle has three visible quads')
            require(len(native_input(models, textures, case['fixture']).encode()) < 100000,
                    'native input exceeds the bounded argument budget')
        halo_fixture, halo_expected = halo_edit_case(reference, states)
        require(halo_expected['halo-initial']['snapshot'] == halo_expected['halo-edit']['snapshot'],
                'halo edit must preserve inside snapshot metadata')
        require(halo_expected['halo-initial']['masks'][0][4] == 22 and
                halo_expected['halo-edit']['masks'][0][4] == 23, 'halo edit oracle masks')
        print(json.dumps({'status': 'prepared', 'java_visibility_sha256': REFERENCE_SHA,
                          'pair_expectations': len(pair_expectations(reference)),
                          'neighbor_expectations': len(neighbor_expectations(reference)),
                          'source_model_count': len(model_source['models']),
                          'source_model_sha256': model_source['sha256'],
                          'custom_cases': len(cases), 'rendered_custom_cases': sum(case['draw'] for case in cases),
                          'halo_edit_revision': len(halo_fixture['sections']) + len(halo_fixture['cells']),
                          'production_expected_geometry_input': False}))
        return
    started = time.monotonic()
    sources = source_fingerprints()
    alternative = WORK / 'alternate-registry.tsv'
    alternative.write_text(WM.HEADER + '\n' + ''.join(
        f'{index}\tminecraft:{name}\t{index}\t1\t{index}\t[]\n'
        for index, name in enumerate(('oak_planks', 'stone', 'air', 'dirt'))))
    alternate_states = WM.registry_states(alternative)
    input_files = {str(models.relative_to(ROOT)): digest(models)}
    input_seals = {'official_registry': digest(OFFICIAL), 'alternate_registry': digest(alternative),
                   'java_visibility': digest(REFERENCE), 'java_bake': digest(WM.REFERENCE),
                   'client_jar': digest(WM.JAR)}
    report = {'schema': 1, 'pin': '26.3', 'status': 'running',
              'timestamp_utc': datetime.now(timezone.utc).isoformat(),
              'scope': 'Measured vanilla air/full-cube neighbor masks, exact camera-relative source-baked '
                       'retained quads and finite CPU flat pixels',
              'reference': {'visibility_sha256': REFERENCE_SHA, 'bake': bake_reference,
                            'visibility_observations_sha256': reference['observations_sha256'],
                            'visibility_fresh_jvm_reproductions': reference['fresh_jvm_reproductions'],
                            'source_models': model_source},
              'source_sha256_begin': sources, 'oracle_sha256': sources['tools/test_world_visibility.py'],
              'input_sha256_begin': input_seals,
              'oracle_environment': {'python': sys.version.split()[0], 'numpy': np.__version__, 'pillow': PILLOW_VERSION},
              'bend_executable_sha256': digest(BEND), 'builds': [], 'runs': [], 'groups': [],
              'boundaries': [
                  'Production receives only original model JSON, decoded original texture pixels and explicit registry bindings.',
                  'Expected Java visibility masks, baked quads and pixels are never native input.',
                  'Actual Java references were independently executed and sealed before this native run; no fresh Java execution during it.',
                  'Closed air/stone/dirt/oak_planks domain, full-cube occlusion only; contextual and other block shapes are rejected.',
                  'All required halo sections are explicitly allocated air; missing Core sections are errors, never implicit air.',
                  'Every nonair block performs six ordered neighbor reads, including intentionally repeated adjacent-cell reads.',
                  'Filtering preserves quad UVs/materials/sparse original order; ungrouped cull faces are retained.',
                  'Static normalized sprites, white tint/light and directional shade; weighted blockstate visual selection is outside this run.',
                  'Native PPM RGB compares exactly against an independent NumPy oracle; PNG previews are conversions of observed pixels.',
                  'Finite hidden CPU verification does not establish visible client acceptance or whole-game parity.',
              ]}
    environment = os.environ.copy()
    environment.update(MC_BLOCK_REGISTRY=str(OFFICIAL), MC_HIDDEN_LAUNCH='1')
    command = [BINARY, '--gpu', 'off']

    def invoke(name, expected, registry_states, registry, fixture=None, native_args=(),
               source=True, errors=None, owners=None, pairs=None, neighbors=None, standalone=None):
        environment['MC_BLOCK_REGISTRY'] = str(registry)
        if source:
            text = native_input(models, textures, fixture)
            path = WORK / f'input-{name}.json'
            path.write_text(text)
            input_files[str(path.relative_to(ROOT))] = digest(path)
            argv = [*command, text, *native_args]
        else:
            path = None
            argv = [*command, *native_args]
        stdout, execution = run(argv, environment)
        if path is not None:
            execution['input_json_file'] = str(path.relative_to(ROOT))
            execution['input_json_sha256'] = digest(path)
            execution['command'][3] = '<original-source JSON argument from input_json_file>'
        report['runs'].append(execution)
        group = {'name': name, **verify_records(stdout, expected, registry_states, quads, textures, name,
                                               errors=errors, owners=owners, pairs=pairs, neighbors=neighbors,
                                               standalone=standalone)}
        report['groups'].append(group)
        return group

    try:
        if not args.skip_build:
            _, build = run([BEND, 'tests/world_visibility.bend', '-o', BINARY], timeout=600, build=True)
            report['builds'].append(build)
        require(BINARY.is_file(), 'missing native visibility harness')
        report['binary_sha256_begin'] = digest(BINARY)
        invoke('pairs', {}, states, OFFICIAL, native_args=('pairs',), source=False,
               pairs=pair_expectations(reference))
        invoke('neighbors', {}, states, OFFICIAL, native_args=('neighbors',), source=False,
               neighbors=neighbor_expectations(reference))
        invoke('validation', {}, states, OFFICIAL, native_args=('errors',), errors=ERRORS,
               owners={name: [1, 47, states['minecraft:stone']] for name in OWNER_IDS},
               standalone=standalone_quads(states, quads))
        missing_source = {'id': 'missing-halo', 'snapshot_bounds': [0, 0, 0, 1, 1, 1],
                          'world_nonair_cells': [{'position': [0, 0, 0], 'state': 'minecraft:stone'}]}
        missing_fixture = fixture_input(missing_source, [0, 0, 0])
        missing_fixture['sections'] = [[0, 0, 0]]  # Deliberately omit the required Down section.
        invoke('missing-halo', {}, states, OFFICIAL, fixture=missing_fixture,
               native_args=('sample-error', 'missing-halo'), errors={'missing-halo': 'NeighborRead'},
               owners={'missing-halo': [1, 2, states['minecraft:stone']]})
        invoke('unknown-halo', {}, states, OFFICIAL, native_args=('unknown-halo',),
               errors={'unknown-halo': 'UnsupportedState'}, owners={'unknown-halo': [1, 47, states['minecraft:stone']]})
        empty_source = {'id': 'empty-known-air', 'snapshot_bounds': [0, 0, 0, 1, 1, 1],
                        'world_nonair_cells': [], 'blocks': []}
        empty_fixture = fixture_input(empty_source, [0, 0, 0])
        empty_fixture['sections'] = [[0, 0, 0]]
        # No halo sections exist here: filtering air before face collection must
        # avoid every neighbor read, rather than fail on absent neighbors.
        empty_expected = {'empty-known-air': {'snapshot': scene_snapshot(empty_source, states, [0, 0, 0], 1, 1),
                                               'masks': []}}
        invoke('empty-known-air', empty_expected, states, OFFICIAL, fixture=empty_fixture,
               native_args=('empty-known-air', '1'))
        basic_expected = {name: {'snapshot': WM.basic_snapshot(states, edited),
                                'masks': expected_masks(scene(reference, 'fixture-edited-40' if edited else 'fixture-39'), states)}
                          for name, edited in (('initial', False), ('cached', False), ('raw-edit', True), ('uncached', True))}
        basic = invoke('official', basic_expected, states, OFFICIAL)
        alternate_expected = {name: {'snapshot': WM.basic_snapshot(alternate_states, edited),
                                    'masks': expected_masks(scene(reference, 'fixture-edited-40' if edited else 'fixture-39'), alternate_states)}
                              for name, edited in (('initial', False), ('cached', False), ('raw-edit', True), ('uncached', True))}
        alternate = invoke('alternate', alternate_expected, alternate_states, alternative)
        require([frame['rgb_sha256'] for frame in basic['frames']] ==
                [frame['rgb_sha256'] for frame in alternate['frames']], 'registry remapping changed actual pixels')
        report['cache_observations'] = compare_edit_frames(basic)
        report['cache_observations']['alternate_registry_same_rgb'] = True
        halo_fixture, halo_expected = halo_edit_case(reference, states)
        halo = invoke('halo-cache-edit', halo_expected, states, OFFICIAL, fixture=halo_fixture, native_args=('halo-edit',))
        report['halo_cache_observations'] = {
            'before_mask': 22, 'after_mask': 23, 'before_quads': 3, 'after_quads': 4,
            'inside_snapshot_unchanged': True, 'tick_before_and_after': halo_expected['halo-initial']['snapshot']['tick'],
            'revision_before_and_after': halo_expected['halo-initial']['snapshot']['revision'],
            'inside_snapshot_cache_retained_by_fixture': True,
            'six_actual_neighbor_reads_each_sample': True,
            'initial_cached_rgb_equal': halo['frames'][0]['rgb_sha256'] == halo['frames'][1]['rgb_sha256'],
            'edited_recached_rgb_equal': halo['frames'][2]['rgb_sha256'] == halo['frames'][3]['rgb_sha256']}
        require(report['halo_cache_observations']['initial_cached_rgb_equal'] and
                report['halo_cache_observations']['edited_recached_rgb_equal'], 'halo cache frame stability')
        cases = custom_cases(reference)
        report['custom_fixture_sha256'] = sha(canonical([{key: value for key, value in case.items() if key != 'java_scene'}
                                                       for case in cases]))
        for case in cases:
            invoke(case['id'], {case['id']: custom_expected(case, states)}, states, OFFICIAL,
                   fixture=case['fixture'], native_args=(case['id'], str(int(case['draw']))))
        groups = report['groups']
        report['counters'] = {'native_invocations': len(report['runs']),
                              **{key: sum(group[key] for group in groups) for key in (
                                  'snapshots', 'blocks', 'neighbor_reads', 'visible_faces', 'hidden_faces', 'quads',
                                  'pair_results', 'neighbor_results', 'validation_outcomes', 'negative_rejections',
                                  'owner_recoveries_checked', 'builtin_regressions')},
                              'standalone_group_cases': sum(group['standalone_group_cases'] for group in groups),
                              'standalone_quads_checked': sum(group['standalone_quads_checked'] for group in groups),
                              'frames': sum(len(group['frames']) for group in groups),
                              'pixels': sum(frame['pixels'] for group in groups for frame in group['frames']),
                              'far_coordinate_cases': 32, 'far_sign_combinations': 8,
                              'signed_neighbor_wrap_cases': reference['counts']['overflowing_neighbor_steps']}
        report['counters'].update(exact_position_f32_words=12 * report['counters']['quads'],
                                  exact_uv_f32_words=8 * report['counters']['quads'],
                                  exact_material_order_words=9 * report['counters']['quads'],
                                  exact_standalone_quad_words=29 * report['counters']['standalone_quads_checked'])
        report['status'] = 'passed'
        report['confidence'] = 'high for the stated measured domain and finite CPU comparisons'
    except Exception as error:
        report['status'] = 'failed'
        report['failure'] = str(error)
        raise
    finally:
        report['source_sha256_end'] = source_fingerprints()
        report['sources_unchanged_during_run'] = report['source_sha256_end'] == sources
        report['input_sha256_end'] = {'official_registry': digest(OFFICIAL), 'alternate_registry': digest(alternative),
                                     'java_visibility': digest(REFERENCE), 'java_bake': digest(WM.REFERENCE),
                                     'client_jar': digest(WM.JAR)}
        report['inputs_unchanged_during_run'] = report['input_sha256_end'] == input_seals
        report['native_input_files_sha256'] = input_files
        report['native_inputs_unchanged_during_run'] = all(digest(ROOT / path) == expected for path, expected in input_files.items())
        if BINARY.is_file():
            report['binary_sha256_end'] = digest(BINARY)
            report['binary_unchanged_during_run'] = report.get('binary_sha256_begin') == report['binary_sha256_end']
        report['seconds'] = round(time.monotonic() - started, 6)
        if report['status'] == 'passed' and not all(report.get(key) for key in (
                'sources_unchanged_during_run', 'inputs_unchanged_during_run',
                'native_inputs_unchanged_during_run', 'binary_unchanged_during_run')):
            report['status'] = 'failed'
            report['failure'] = 'source, binary or input changed during execution'
        EVIDENCE.write_text(json.dumps(report, sort_keys=True, indent=2) + '\n')
        print(json.dumps({key: report.get(key) for key in ('status', 'seconds', 'counters', 'failure')}), flush=True)
        require(report['status'] == 'passed', report.get('failure', 'native visibility verification failed'))


def generate_entry(kind):
    original = (ROOT / 'tests/world_visibility.bend').read_text()
    selector = kind + '_arguments'
    require('def ' + selector + '(' in original, f'missing split entry {selector}')
    marker = 'IO.bind(List<String>,Unit,IO.args(),arguments)'
    require(original.count(marker) == 1, 'expected exactly one standalone harness main selector')
    source = original.replace(marker, 'IO.bind(List<String>,Unit,IO.args(),' + selector + ')', 1)
    path = ROOT / f'build/world-visibility-{kind}.bend'
    path.write_text(source)
    return path, {'path': str(path.relative_to(ROOT)), 'sha256': digest(path),
                  'source_harness_sha256': sha(original.encode()), 'selector': selector,
                  'changes': 'Only the main IO.args selector; no test module imports or implementation edits'}


def case_groups(reference, official, alternate):
    position = [0x3fe0000000000000, 0x3ff0000000000000, 0xc004000000000000]
    groups = [
        {'name': 'pairs', 'expected': {}, 'registry': 'official', 'args': ('pairs',), 'source': False,
         'pairs': pair_expectations(reference)},
        {'name': 'neighbors', 'expected': {}, 'registry': 'official', 'args': ('neighbors',), 'source': False,
         'neighbors': neighbor_expectations(reference)},
        {'name': 'ownership-validation', 'expected': {}, 'registry': 'official', 'args': ('errors',),
         'errors': {name: ERRORS[name] for name in OWNER_IDS},
         'owners': {name: [1, 47, official['minecraft:stone']] for name in OWNER_IDS}},
    ]
    missing = {'bounds': [0, 0, 0, 1, 1, 1], 'body_words': [0] * 6,
               'sections': [[0, 0, 0]], 'cells': [[0, 0, 0, 'minecraft:stone']]}
    groups += [
        {'name': 'missing-halo', 'expected': {}, 'registry': 'official', 'fixture': missing,
         'args': ('sample-error', 'missing-halo'), 'errors': {'missing-halo': 'NeighborRead'},
         'owners': {'missing-halo': [1, 2, official['minecraft:stone']]}},
        {'name': 'unknown-halo', 'expected': {}, 'registry': 'official', 'args': ('unknown-halo',),
         'errors': {'unknown-halo': 'UnsupportedState'}, 'owners': {'unknown-halo': [1, 47, official['minecraft:stone']]}},
    ]
    empty = {'blocks': [], 'snapshot_bounds': [0, 0, 0, 1, 1, 1]}
    empty_fixture = {'bounds': empty['snapshot_bounds'], 'body_words': [0] * 6,
                     'sections': [[0, 0, 0]], 'cells': []}
    expected = {'snapshot': scene_snapshot(empty, official, [0, 0, 0], 1, 1), 'masks': []}
    groups.append({'name': 'empty-known-air', 'expected': {'empty-known-air': with_sampledata(expected, empty, official, [0, 0, 0])},
                   'registry': 'official', 'fixture': empty_fixture, 'args': ('empty-known-air', '1')})
    for registry, states in (('official', official), ('alternate', alternate)):
        expected = {}
        for name, edited in (('initial', False), ('cached', False), ('raw-edit', True), ('uncached', True)):
            source = scene(reference, 'fixture-edited-40' if edited else 'fixture-39')
            expected[name] = with_sampledata({'snapshot': WM.basic_snapshot(states, edited),
                                               'masks': expected_masks(source, states)}, source, states, position)
        groups.append({'name': registry, 'expected': expected, 'registry': registry, 'args': ()})
    fixture, expected = halo_edit_case(reference, official)
    halo_source = copy.deepcopy(scene(reference, 'halo-edge-origin'))
    halo_source['snapshot_bounds'] = [*halo_source['blocks'][0]['position'], 1, 1, 1]
    halo_position = custom_cases(reference)[0]['position']
    expected = {name: with_sampledata(value, halo_source, official, halo_position) for name, value in expected.items()}
    groups.append({'name': 'halo-cache-edit', 'expected': expected, 'registry': 'official', 'fixture': fixture,
                   'args': ('halo-edit',)})
    for case in custom_cases(reference):
        expected = with_sampledata(custom_expected(case, official), case['java_scene'], official, case['position'])
        groups.append({'name': case['id'], 'expected': {case['id']: expected}, 'registry': 'official',
                       'fixture': case['fixture'], 'args': (case['id'], str(int(case['draw'])))})
    require(len(groups) == 42, 'frozen world case invocation count')
    return groups


def verify_sampler(stdout, group):
    observed = parse_records(stdout)
    expected = group['expected']
    for name in ('snapshots', 'masks', 'sampledata', 'maskdata'):
        require(set(observed[name]) == set(expected), {'sampler_record_kind': name, 'ids': list(observed[name])})
    require(not observed['quads'] and not observed['frames'], 'sampler must have no geometry/render output')
    for name in ('errors', 'owners', 'pairs', 'neighbors'):
        left, right = group.get(name, {}), observed[name]
        if name in ('pairs', 'neighbors'):
            left = [[list(key), value] for key, value in sorted(left.items())]
            right = [[list(key), value] for key, value in sorted(right.items())]
        difference = WM.K.first_difference(left, right)
        require(difference is None, {'sampler_group': group['name'], 'kind': name, 'difference': difference})
        require(name not in ('pairs', 'neighbors') or group.get(name, {}) == observed[name],
                {'sampler_group': group['name'], 'kind': name, 'exact_mapping_equality': False})
    actual = {}
    for name, wanted in expected.items():
        for kind, left, right in (
                ('snapshot', wanted['snapshot'], observed['snapshots'][name]),
                ('mask', {'neighbor_reads': 6 * len(wanted['masks']), 'values': wanted['masks']}, observed['masks'][name]),
                ('sampledata', wanted['sampledata'], observed['sampledata'][name]),
                ('maskdata', wanted['maskdata'], observed['maskdata'][name])):
            difference = WM.K.first_difference(left, right)
            require(difference is None, {'scenario': name, 'kind': kind, 'difference': difference})
        # Serialize only actual native records. The independent expected object
        # is deliberately never substituted after these comparisons succeed.
        snapshot, masks, data = observed['snapshots'][name], observed['masks'][name], observed['sampledata'][name]
        full_masks = observed['maskdata'][name]
        require([[*row[:3], row[4], row[5]] for row in full_masks] == masks['values'],
                'actual full visibility metadata differs from five-word comparison projection')
        require([row[:5] for row in full_masks] == [row[:5] for row in data['raw']],
                'actual visibility cells differ from actual raw cell boundary/state metadata')
        actual[name] = {'tick': snapshot['tick'], 'revision': snapshot['revision'], 'blocks': snapshot['blocks'],
                        'camera': snapshot['camera'], 'raw': data['raw'], 'masks': full_masks,
                        'origin': data['origin'], 'palette': data['palette'], 'reads': masks['neighbor_reads']}
    return actual, {'name': group['name'], 'snapshots': len(expected),
                    'blocks': sum(value['snapshot']['count'] for value in expected.values()),
                    'neighbor_reads': sum(6 * len(value['masks']) for value in expected.values()),
                    'pair_results': len(observed['pairs']), 'neighbor_results': len(observed['neighbors']),
                    'validation_outcomes': len(observed['errors']),
                    'owner_recoveries_checked': len(observed['owners']),
                    'negative_rejections': sum(code != 'Done' for code in observed['errors'].values())}


def capture_run(binary, text, native_args, label, environment, report):
    command = [binary, '--gpu', 'off']
    if text is not None:
        path = WORK / f'{label}-input.json'
        path.write_text(text)
        command.append(text)
    else:
        path = None
    stdout, execution = run([*command, *native_args], environment)
    output = WORK / f'{label}-stdout.txt'
    output.write_text(stdout)
    execution.update(stdout_file=str(output.relative_to(ROOT)), stdout_file_sha256=digest(output))
    if path:
        execution.update(input_json_file=str(path.relative_to(ROOT)), input_json_sha256=digest(path))
        execution['command'][3] = '<JSON argument from input_json_file>'
    report['runs'].append(execution)
    return stdout


def split_main():
    global SAMPLER_BINARY
    parser = argparse.ArgumentParser()
    parser.add_argument('--skip-build', action='store_true')
    parser.add_argument('--prepare-only', action='store_true', help='independent oracle preparation only; no Bend execution')
    parser.add_argument('--prepare-bake', action='store_true', help='reuse only the verified existing three-root native baker')
    parser.add_argument('--sampler-only', action='store_true')
    parser.add_argument('--geometry-only', action='store_true')
    parser.add_argument('--sampler-binary', type=Path, help='explicit retained sampler artifact; requires its build receipt')
    parser.add_argument('--sampler-build-receipt', type=Path, help='pinned exact-C lower-optimization compilation receipt')
    parser.add_argument('--geometry-build-receipt', type=Path, help='explicit retained installed-O3 geometry compilation receipt')
    args = parser.parse_args()
    require(not (args.sampler_only and args.geometry_only), 'choose one partial stage')
    require(bool(args.sampler_binary) == bool(args.sampler_build_receipt), 'sampler binary and build receipt must be supplied together')
    require(not args.sampler_binary or args.skip_build or args.geometry_only, 'a retained sampler override must not emit Bend again')
    require(not args.geometry_build_receipt or args.skip_build, 'a retained geometry compilation receipt requires --skip-build')
    reference, quads, textures, bake_reference, models, model_source, official = prepare()
    alternative = WORK / 'alternate-registry.tsv'
    alternative.write_text(WM.HEADER + '\n' + ''.join(
        f'{index}\tminecraft:{name}\t{index}\t1\t{index}\t[]\n'
        for index, name in enumerate(('oak_planks', 'stone', 'air', 'dirt'))))
    alternate = WM.registry_states(alternative)
    groups = case_groups(reference, official, alternate)
    if args.prepare_only or args.prepare_bake:
        baked_receipt = None
        if args.prepare_bake:
            baked, baked_receipt = actual_baked(models, quads)
            for name, records in baked.items():
                require(all(len(compact_baked(value)) == 16 for value in records), 'compact native Baked DTO size')
            path = ROOT / 'evidence/world-visibility-bake-preparation.json'
            path.write_text(json.dumps({'schema': 1, 'pin': '26.3', 'status': 'passed_actual_bend_bake_preparation',
                                        'oracle_sha256': digest(Path(__file__)), 'original_source_models': model_source,
                                        'java_bake_reference_sha256': WM.REFERENCE_SHA,
                                        'actual_bend_bake': baked_receipt}, sort_keys=True, indent=2) + '\n')
        for group in groups:
            for name, value in group['expected'].items():
                data = value['sampledata']
                require(len(data['raw']) == value['snapshot']['count'] and len(data['origin']) == 6 and
                        len(data['palette']) == 4, 'prepared sampledata dimensions')
                require(all(len(row) == 6 and row[3] <= 3 for row in data['raw']), 'prepared raw cell boundaries')
                # Exercise parser/framing using explicitly synthetic expected
                # records. They are not saved as an actual native handoff.
                line = 'sampledata|' + name + '|' + ','.join(map(str, data['origin'])) + '|' + \
                    ','.join(map(str, data['palette'])) + '|' + ''.join(','.join(map(str, row)) + ';' for row in data['raw'])
                require(parse_records(line)['sampledata'][name] == data, 'sampledata parser must preserve every raw word')
                line = 'maskdata|' + name + '|' + ''.join(','.join(map(str, row)) + ';' for row in value['maskdata'])
                require(parse_records(line)['maskdata'][name] == value['maskdata'], 'maskdata parser must preserve cell boundary metadata')
        print(json.dumps({'status': 'prepared', 'case_groups': len(groups),
                          'snapshots': sum(len(group['expected']) for group in groups),
                          'sampler_owned_failures': 11, 'geometry_pure_validations': 14,
                          'actual_baked_preparation': baked_receipt is not None,
                          'oracle_sha256': digest(Path(__file__))}))
        return
    started = time.monotonic()
    sources = source_fingerprints()
    sampler_override, override_files, geometry_reuse_files = None, {}, {}
    if args.sampler_binary:
        SAMPLER_BINARY = args.sampler_binary.resolve()
        receipt_path = args.sampler_build_receipt.resolve()
        compiled = json.loads(receipt_path.read_text())
        require(compiled['status'] == 'compiled_lower_optimization_cpu_artifact' and
                compiled['pinned_files_unchanged'] and compiled['sources_unchanged'], 'fallback compilation did not pass its integrity checks')
        require(SAMPLER_BINARY == (ROOT / compiled['binary']['path']).resolve() and
                digest(SAMPLER_BINARY) == compiled['binary']['sha256'], 'explicit sampler artifact differs from its compilation receipt')
        require({name: value for name, value in compiled['source_sha256_end'].items() if name != 'tools/test_world_visibility.py'} ==
                {name: value for name, value in sources.items() if name != 'tools/test_world_visibility.py'}, 'compiled sampler sources or comparison dependencies changed')
        generation_path = ROOT / 'evidence/world-visibility-runner-override.json'
        generation = json.loads(generation_path.read_text())
        require(generation['previous_runner_sha256'] == compiled['oracle_sha256'] and
                generation['current_runner_sha256'] == sources['tools/test_world_visibility.py'] and
                generation['all_module_nodes_except_split_main_and_verify_sampler_unchanged'] and
                generation['native_sample_handoff_and_snapshot_checks_unchanged'], 'runner override generation lacks unchanged comparison provenance')
        override_files = {**compiled['pinned_files_sha256_end'], str(receipt_path): digest(receipt_path),
                          str(generation_path): digest(generation_path)}
        require(all(digest(Path(path)) == expected for path, expected in override_files.items()), 'fallback C/compiler/header/SDK provenance changed')
        sampler_override = {'variant': 'exact_emitted_C_at_O0_CPU_behavioral_only',
                            'binary_path': str(SAMPLER_BINARY), 'binary_sha256': digest(SAMPLER_BINARY),
                            'build_receipt': {'path': str(receipt_path.relative_to(ROOT)), 'sha256': digest(receipt_path)},
                            'runner_generation': {'path': str(generation_path.relative_to(ROOT)), 'sha256': digest(generation_path)},
                            'compiled_runner_sha256': compiled['oracle_sha256'],
                            'pinned_files_sha256_begin': override_files}
    environment = {**os.environ, 'MC_BLOCK_REGISTRY': str(OFFICIAL), 'MC_HIDDEN_LAUNCH': '1'}
    seals = {'client_jar': digest(WM.JAR), 'visibility_reference': digest(REFERENCE),
             'bake_reference': digest(WM.REFERENCE), 'official_registry': digest(OFFICIAL),
             'alternate_registry': digest(alternative), 'models': digest(models)}
    report = {'schema': 2, 'pin': '26.3', 'status': 'running', 'timestamp_utc': datetime.now(timezone.utc).isoformat(),
              'scope': 'Split actual Core.World visibility sampler and actual Bend-baked geometry/flat-render integration',
              'oracle_sha256': sources['tools/test_world_visibility.py'], 'source_sha256_begin': sources,
              'input_sha256_begin': seals, 'builds': [], 'runs': [], 'groups': [], 'generated_entries': [],
              'binary_sha256_begin': {}, 'reference': {'visibility_sha256': REFERENCE_SHA, 'bake': bake_reference,
                                                     'original_source_models': model_source},
              'registry_states': {'official': {name: official[name] for name in STATE_ORDER}, 'alternate': alternate},
              'selected_stage': 'sampler' if args.sampler_only else 'geometry' if args.geometry_only else 'complete',
              'boundaries': ['Python serializes actual native sampler and native baker output losslessly as checked DTOs; it implements no game semantics.',
                             'Actual sampler masks/raw coordinates/eye origin and actual Bend bake geometry are native stage inputs; expected Java masks/quads/pixels are never stage inputs.',
                             'The closed four-state full-cube domain, explicit normalized sprites and finite hidden CPU scenarios do not establish whole-game or visible-client parity.',
                             'The original combined600s build-limit receipt is preserved separately with exact original harness source.']}
    if sampler_override:
        report['sampler_binary_override'] = sampler_override
        report['boundaries'].append('The sampler is the separately pinned exact-C -O0 CPU behavioral artifact; installed Bend -O3 compilation remains unverified at its stated600s limit.')
    sampler_receipt = ROOT / 'evidence/world-visibility-sampler.json'
    samples_path = WORK / 'actual-sampler-samples.json'
    sampler_stdout = {}
    samples = {}
    output_path = sampler_receipt if args.sampler_only else EVIDENCE
    try:
        if not args.geometry_only:
            generated, generation = generate_entry('sampler')
            report['generated_entries'].append(generation)
            if not args.skip_build:
                _, build = run([BEND, generated, '-o', SAMPLER_BINARY], timeout=600, build=True)
                report['builds'].append(build)
            require(SAMPLER_BINARY.is_file(), 'missing split sampler native binary')
            report['binary_sha256_begin']['sampler'] = digest(SAMPLER_BINARY)
            for group in groups:
                environment['MC_BLOCK_REGISTRY'] = str(alternative if group['registry'] == 'alternate' else OFFICIAL)
                text = None if not group.get('source', True) else json.dumps(
                    {'fixture': group['fixture']} if 'fixture' in group else {}, separators=(',', ':'))
                stdout = capture_run(SAMPLER_BINARY, text, group['args'], 'sampler-' + group['name'], environment, report)
                actual, summary = verify_sampler(stdout, group)
                report['groups'].append(summary)
                summary['stage'] = 'sampler'
                samples[group['name']] = actual
                sampler_stdout[group['name']] = stdout
            samples_path.write_text(json.dumps({'schema': 1, 'samples': samples, 'stdout': sampler_stdout,
                                               'source_sha256': sources,
                                               'sampler_binary_sha256': digest(SAMPLER_BINARY)},
                                              sort_keys=True, indent=2) + '\n')
            report['actual_sampler_samples'] = {'path': str(samples_path.relative_to(ROOT)), 'sha256': digest(samples_path)}
            if args.sampler_only:
                report['status'] = 'passed_native_sampler'
        else:
            receipt = json.loads(sampler_receipt.read_text())
            require(receipt['status'] == 'passed_native_sampler', 'prior native sampler stage did not pass')
            require(digest(samples_path) == receipt['actual_sampler_samples']['sha256'], 'actual sampler handoff changed')
            actual = json.loads(samples_path.read_text())
            if actual['source_sha256'] != sources:
                generation = json.loads((ROOT / 'evidence/world-visibility-runner-override.json').read_text())
                require(generation['native_sampler_runner_sha256'] == actual['source_sha256']['tools/test_world_visibility.py'] and
                        generation['current_runner_sha256'] == sources['tools/test_world_visibility.py'] and
                        generation['native_sampler_to_current_module_nodes_except_split_main_unchanged'] and
                        {name: value for name, value in actual['source_sha256'].items() if name != 'tools/test_world_visibility.py'} ==
                        {name: value for name, value in sources.items() if name != 'tools/test_world_visibility.py'},
                        'sampler handoff differs beyond the sealed orchestration-only runner generation')
                report['handoff_runner_compatibility'] = {'native_sampler_runner_sha256': generation['native_sampler_runner_sha256'],
                                                        'current_runner_sha256': sources['tools/test_world_visibility.py'],
                                                        'unchanged_dependency_count': len(sources) - 1,
                                                        'generation_receipt_sha256': digest(ROOT / 'evidence/world-visibility-runner-override.json')}
            require(digest(SAMPLER_BINARY) == actual['sampler_binary_sha256'], 'sampler executable changed since observed outputs')
            samples, sampler_stdout = actual['samples'], actual['stdout']
            report['prior_sampler_receipt'] = {'path': str(sampler_receipt.relative_to(ROOT)), 'sha256': digest(sampler_receipt)}
            report['actual_sampler_samples'] = {'path': str(samples_path.relative_to(ROOT)), 'sha256': digest(samples_path)}
            report['binary_sha256_begin']['sampler'] = digest(SAMPLER_BINARY)
        if not args.sampler_only:
            baked, bake_execution = actual_baked(models, quads)
            report['actual_bend_bake'] = bake_execution
            generated, generation = generate_entry('geometry')
            report['generated_entries'].append(generation)
            if args.geometry_build_receipt:
                prior_build_path = args.geometry_build_receipt.resolve()
                prior_build = json.loads(prior_build_path.read_text())
                require(prior_build['builds'][0]['exit_code'] == 0 and prior_build['sources_unchanged_during_run'] and
                        digest(GEOMETRY_BINARY) == prior_build['binary_sha256_end']['geometry'] and
                        any(entry['sha256'] == generation['sha256'] for entry in prior_build['generated_entries']) and
                        {name: value for name, value in prior_build['source_sha256_end'].items() if name != 'tools/test_world_visibility.py'} ==
                        {name: value for name, value in sources.items() if name != 'tools/test_world_visibility.py'},
                        'retained geometry binary differs from its successful frozen compilation')
                emission_path = ROOT / 'evidence/world-visibility-geometry-emission.json'
                emission = json.loads(emission_path.read_text())
                retained_c = ROOT / emission['retained']['path']
                require(emission['C_unchanged_during_copy'] and digest(retained_c) == emission['retained']['sha256'],
                        'retained emitted geometry C changed')
                geometry_reuse_files = {str(prior_build_path): digest(prior_build_path), str(emission_path): digest(emission_path),
                                        str(retained_c): digest(retained_c)}
                report['retained_geometry_build'] = {'receipt': {'path': str(prior_build_path.relative_to(ROOT)), 'sha256': digest(prior_build_path)},
                                                   'emission_receipt': {'path': str(emission_path.relative_to(ROOT)), 'sha256': digest(emission_path)},
                                                   'binary_sha256': digest(GEOMETRY_BINARY), 'original_build_seconds': prior_build['builds'][0]['seconds'],
                                                   'original_runner_sha256': prior_build['oracle_sha256'], 'pinned_files_sha256_begin': geometry_reuse_files}
            if not args.skip_build:
                _, build = run([BEND, generated, '-o', GEOMETRY_BINARY], timeout=600, build=True)
                report['builds'].append(build)
            require(GEOMETRY_BINARY.is_file(), 'missing split geometry/render native binary')
            report['binary_sha256_begin']['geometry'] = digest(GEOMETRY_BINARY)
            text = geometry_input(samples['official']['initial'], baked, textures)
            stdout = capture_run(GEOMETRY_BINARY, text, ('errors',), 'geometry-validation', environment, report)
            pure = {name: code for name, code in ERRORS.items() if name not in OWNER_IDS}
            report['groups'].append({'name': 'geometry-validation', **verify_records(
                stdout, {}, official, quads, textures, 'geometry-validation', errors=pure,
                standalone=standalone_quads(official, quads))})
            report['groups'][-1]['stage'] = 'geometry'
            for group in groups:
                if not group['expected']:
                    continue
                geometry_stdout = ''
                for name, wanted in group['expected'].items():
                    text = geometry_input(samples[group['name']][name], baked, textures)
                    stdout = capture_run(GEOMETRY_BINARY, text, (name, str(int(wanted.get('draw', True)))),
                                         'geometry-' + group['name'] + '-' + name, environment, report)
                    geometry_stdout += stdout
                states = alternate if group['registry'] == 'alternate' else official
                summary = verify_records(sampler_stdout[group['name']].rstrip('\n') + '\n' + geometry_stdout,
                                         group['expected'], states, quads, textures, group['name'])
                report['groups'].append({'name': group['name'] + '-geometry', **summary})
                report['groups'][-1]['stage'] = 'geometry'
            completed = {group['name']: group for group in report['groups'] if group['name'].endswith('-geometry')}
            report['cache_observations'] = compare_edit_frames(completed['official-geometry'])
            require([frame['rgb_sha256'] for frame in completed['official-geometry']['frames']] ==
                    [frame['rgb_sha256'] for frame in completed['alternate-geometry']['frames']], 'registry remapping changed native pixels')
            report['halo_cache_observations'] = {'before_mask': 22, 'after_mask': 23, 'quads_before': 3, 'quads_after': 4,
                                                'inside_snapshot_and_cache_retained': True, 'tick': 1, 'revision': 7,
                                                'actual_sampler_output_supplied_to_geometry': True}
            report['status'] = 'passed_split_native_integration'
    except Exception as error:
        timed_out = isinstance(error, CommandFailure) and error.execution.get('timeout')
        build_limit = timed_out and error.execution['build']
        report['status'] = 'unverified_native_build_resource_limit' if build_limit else 'failed'
        report['failure_kind'] = 'native_build_time_limit' if build_limit else 'native_runtime_time_limit' if timed_out else 'verification_failure'
        if isinstance(error, CommandFailure):
            report['failed_execution'] = error.execution
            if error.execution['build']:
                report['builds'].append(error.execution)
            failure_output = WORK / 'failed-execution-stdout.txt'
            failure_output.write_text(error.stdout)
            report['failed_execution_stdout'] = {'path': str(failure_output.relative_to(ROOT)),
                                                 'sha256': digest(failure_output)}
        report['failure'] = str(error)
        raise
    finally:
        report['source_sha256_end'] = source_fingerprints()
        report['sources_unchanged_during_run'] = report['source_sha256_end'] == sources
        report['input_sha256_end'] = {'client_jar': digest(WM.JAR), 'visibility_reference': digest(REFERENCE),
                                     'bake_reference': digest(WM.REFERENCE), 'official_registry': digest(OFFICIAL),
                                     'alternate_registry': digest(alternative), 'models': digest(models)}
        report['inputs_unchanged_during_run'] = report['input_sha256_end'] == seals
        report['binary_sha256_end'] = {kind: digest(path) for kind, path in (
            ('sampler', SAMPLER_BINARY), ('geometry', GEOMETRY_BINARY)) if kind in report['binary_sha256_begin']}
        report['binaries_unchanged_during_run'] = report['binary_sha256_end'] == report['binary_sha256_begin']
        report['generated_entries_sha256_end'] = {entry['path']: digest(ROOT / entry['path']) for entry in report['generated_entries']}
        report['generated_entries_unchanged_during_run'] = all(
            report['generated_entries_sha256_end'][entry['path']] == entry['sha256'] for entry in report['generated_entries'])
        report['native_inputs_unchanged_during_run'] = all(
            digest(ROOT / execution['input_json_file']) == execution['input_json_sha256']
            for execution in report['runs'] if 'input_json_file' in execution)
        report['native_outputs_unchanged_during_run'] = all(
            digest(ROOT / execution['stdout_file']) == execution['stdout_file_sha256'] for execution in report['runs'])
        report['sampler_handoff_unchanged_during_run'] = 'actual_sampler_samples' not in report or \
            digest(samples_path) == report['actual_sampler_samples']['sha256']
        report['sampler_override_files_unchanged_during_run'] = all(
            digest(Path(path)) == expected for path, expected in override_files.items())
        if sampler_override:
            report['sampler_binary_override']['pinned_files_sha256_end'] = {
                path: digest(Path(path)) for path in override_files}
        report['geometry_reuse_files_unchanged_during_run'] = all(
            digest(Path(path)) == expected for path, expected in geometry_reuse_files.items())
        if geometry_reuse_files:
            report['retained_geometry_build']['pinned_files_sha256_end'] = {
                path: digest(Path(path)) for path in geometry_reuse_files}
        report['seconds'] = round(time.monotonic() - started, 6)
        report['counters'] = {'native_invocations_this_stage': len(report['runs']),
                              'sampler_invocations_this_stage': sum('sampler-' in run.get('stdout_file', '') for run in report['runs']),
                              'geometry_invocations_this_stage': sum('geometry-' in run.get('stdout_file', '') for run in report['runs'])}
        sampler_groups = [group for group in report['groups'] if group.get('stage') == 'sampler']
        geometry_groups = [group for group in report['groups'] if group.get('stage') == 'geometry']
        report['sampler_counters'] = {key: sum(group.get(key, 0) for group in sampler_groups) for key in (
            'snapshots', 'blocks', 'neighbor_reads', 'pair_results', 'neighbor_results',
            'validation_outcomes', 'owner_recoveries_checked', 'negative_rejections')}
        report['geometry_counters'] = {key: sum(group.get(key, 0) for group in geometry_groups) for key in (
            'snapshots', 'blocks', 'neighbor_reads', 'quads', 'visible_faces', 'hidden_faces',
            'validation_outcomes', 'negative_rejections', 'standalone_group_cases', 'standalone_quads_checked')}
        report['geometry_counters'].update(frames=sum(len(group.get('frames', [])) for group in geometry_groups),
                                            pixels=sum(frame['pixels'] for group in geometry_groups for frame in group.get('frames', [])))
        successful = report['status'] in ('passed_native_sampler', 'passed_split_native_integration')
        if successful and not all(report[key] for key in (
                'sources_unchanged_during_run', 'inputs_unchanged_during_run', 'binaries_unchanged_during_run',
                'generated_entries_unchanged_during_run', 'native_inputs_unchanged_during_run',
                'native_outputs_unchanged_during_run', 'sampler_handoff_unchanged_during_run',
                'sampler_override_files_unchanged_during_run', 'geometry_reuse_files_unchanged_during_run')):
            report['status'], report['failure'] = 'failed', 'source, inputs or binaries changed during execution'
        output_path.write_text(json.dumps(report, sort_keys=True, indent=2) + '\n')
        print(json.dumps({key: report.get(key) for key in ('status', 'seconds', 'counters', 'failure')}), flush=True)
        if successful:
            require(report['status'] in ('passed_native_sampler', 'passed_split_native_integration'), report.get('failure'))


if __name__ == '__main__':
    split_main()
