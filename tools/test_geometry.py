#!/usr/bin/env python3
"""Run the pure Bend AABB substrate against pinned Java raw-bit observations.

Python serializes test requests and checks observations; it never computes the
production collision result. Shape construction and union observations are
explicitly excluded because this module only implements occupied box cells.
"""
from __future__ import annotations
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import time
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BEND = Path('/Users/chuah/.bend/bin/bend')
BINARY = ROOT / 'build/geometry-tests'
FIXTURES = ROOT / 'reference/geometry.json'
EVIDENCE = ROOT / 'evidence/geometry-verification.json'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def verify_fixture_provenance(fixtures):
    assert fixtures['pin'] == '26.3'
    canonical = json.dumps(fixtures['cases'], sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()
    assert hashlib.sha256(canonical).hexdigest() == fixtures['cases_sha256']
    release = json.loads((ROOT / 'reference/release.json').read_text())
    assert release['internal_version']['id'] == '26.3'
    assert fixtures['server_bundle_sha256'] == release['server_bundle']['sha256']
    assert fixtures['server_class_jar_sha256'] == release['server_bundle']['nested_server_sha256']
    jar = ROOT / 'reference/cache/versions/26.3/server-26.3.jar'
    assert sha(jar) == fixtures['server_class_jar_sha256']
    classes = fixtures['source']['classes']
    with zipfile.ZipFile(jar) as archive:
        for name, value in classes.items():
            assert hashlib.sha256(archive.read(value['class_entry'])).hexdigest() == value['class_sha256'], name
    return {'pin': fixtures['pin'], 'cases_sha256': fixtures['cases_sha256'],
            'server_bundle_sha256': fixtures['server_bundle_sha256'],
            'server_class_jar_sha256': fixtures['server_class_jar_sha256'],
            'probe_java_source_sha256': fixtures['probe_java_source_sha256'],
            'random_input_seed': fixtures['random_input_seed'],
            'runtime_version': fixtures['runtime_version'],
            'class_sha256': {name: value['class_sha256'] for name, value in classes.items()},
            'source_method_count': sum(len(value['methods']) for value in classes.values())}


def run(argv, timeout=600, required=True):
    start = time.monotonic()
    process = subprocess.run([str(x) for x in argv], cwd=ROOT, text=True,
                             capture_output=True, timeout=timeout)
    result = {'command': [str(x) for x in argv], 'exit_code': process.returncode,
              'seconds': round(time.monotonic() - start, 6),
              'stdout': process.stdout, 'stderr': process.stderr}
    if required and process.returncode:
        raise RuntimeError(json.dumps(result, indent=2))
    return result


def words(bits):
    assert isinstance(bits, str) and len(bits) == 16
    value = int(bits, 16)
    return [str(value >> 32), str(value & 0xffffffff)]


def word_vector(values):
    return [word for value in values for word in words(value)]


def bits(value):
    return struct.pack('>d', value).hex()


def shape_words(shape):
    if shape['kind'] == 'empty':
        return ['empty']
    assert shape['kind'] == 'raw_array_box', shape
    return ['box', *word_vector(shape['box'])]


def request(case, mode=None):
    operation = case['operation']; value = case['input']; name = case['id']
    operation = {'aabb_construct': 'constructor'}.get(operation, operation.removeprefix('aabb_'))
    if operation in {'constructor', 'move', 'inflate', 'deflate', 'contains', 'intersects',
                     'inflate_scalar', 'deflate_scalar'}:
        emitted = operation.removesuffix('_scalar')
        fields = [name, emitted, *word_vector(value['box'])]
        if operation in {'move', 'inflate', 'deflate'}:
            fields += word_vector(value['vector'])
        elif operation in {'inflate_scalar', 'deflate_scalar'}:
            fields += word_vector([value['scalar']] * 3)
        elif operation == 'contains':
            fields += word_vector(value['point'])
        elif operation == 'intersects':
            fields += word_vector(value['other'])
        return '|'.join(fields)
    if operation in {'raw_array_box_collide', 'raw_array_boxes_collide'}:
        shapes = value.get('shapes', [value.get('shape')])
        if operation == 'raw_array_box_collide':
            emitted = mode or 'clip_collider'
        else:
            emitted = mode or 'clip'
        fields = [name, emitted, *word_vector(value['moving_box']), value['axis'], *words(value['delta'])]
        for shape in shapes:
            fields += shape_words(shape)
        return '|'.join(fields)
    return None


def parse_output(line):
    fields = line.split('|'); name, kind, *payload = fields
    if kind == 'box':
        assert len(payload) == 12
        return name, {'box': [f'{int(payload[i]):08x}{int(payload[i+1]):08x}' for i in range(0, 12, 2)]}
    if kind == 'f64':
        assert len(payload) == 2
        return name, {'f64_bits': f'{int(payload[0]):08x}{int(payload[1]):08x}'}
    if kind == 'bool':
        assert payload in [['0'], ['1']]
        return name, {'boolean': payload == ['1']}
    if kind == 'error':
        return name, {'error': '|'.join(payload)}
    raise AssertionError(line)


def execute(cases, command_results, label):
    # Keep arguments below platform exec limits; every case runs the native API.
    for offset in range(0, len(cases), 100):
        chunk = cases[offset:offset+100]
        result = run([BINARY, '--gpu', 'off', *[request for _, request, _ in chunk]])
        command_results.append({'lane': label, 'offset': offset, 'count': len(chunk),
                                'exit_code': result['exit_code'], 'seconds': result['seconds']})
        lines = result['stdout'].splitlines()
        assert len(lines) == len(chunk), (offset, lines, result['stderr'])
        for (name, _, expected), line in zip(chunk, lines, strict=True):
            observed_name, observed = parse_output(line)
            assert observed_name == name, (name, observed_name)
            assert observed == expected, (name, expected, observed)


def validation_cases():
    unit = [bits(x) for x in [0., 0., 0., 1., 1., 1.]]
    nonfinite = ['7ff0000000000000', 'fff0000000000000', '7ff8000000000123', 'fff0000000000042']
    cases = []
    for field in range(6):
        for value in nonfinite:
            box = unit.copy(); box[field] = value
            name = f'checked-new-{field}-{value}'
            cases.append((name, '|'.join([name, 'checked_new', *word_vector(box)]), {'error': f'coordinate|{field}'}))
    # First invalid original argument wins even when a later argument is NaN.
    box = unit.copy(); box[2] = nonfinite[0]; box[3] = nonfinite[2]
    cases.append(('checked-new-priority', '|'.join(['checked-new-priority', 'checked_new', *word_vector(box)]),
                  {'error': 'coordinate|2'}))
    for axis in 'XYZ':
        for value in nonfinite:
            name = f'checked-delta-{axis}-{value}'
            cases.append((name, '|'.join([name, 'checked_clip', *word_vector(unit), axis, *words(value)]),
                          {'error': 'delta'}))
    for field in range(6):
        box = unit.copy(); box[field] = nonfinite[2]
        # Constructor propagates NaN to both endpoints of that axis.
        normalized_field = field % 3
        name = f'checked-moving-{field}'
        cases.append((name, '|'.join([name, 'checked_clip', *word_vector(box), 'X', *words(bits(1.))]),
                      {'error': f'moving|{normalized_field}'}))
        for index in range(3):
            name = f'checked-obstacle-{index}-{field}'
            shapes = []
            for j in range(3):
                shapes += ['box', *word_vector(box if j == index else unit)]
            cases.append((name, '|'.join([name, 'checked_clip', *word_vector(unit), 'X', *words(bits(1.)), *shapes]),
                          {'error': f'obstacle|{index}|{field}'}))
    name = 'checked-clip-success'
    obstacle = [bits(x) for x in [2., 0., 0., 3., 1., 1.]]
    cases.append((name, '|'.join([name, 'checked_clip', *word_vector(unit), 'X', *words(bits(2.)), 'box', *word_vector(obstacle)]),
                  {'f64_bits': bits(1.)}))
    # Validation happens before collision early-exit, including a later invalid
    # obstacle when an earlier obstacle would reduce delta to zero.
    bad = unit.copy(); bad[1] = nonfinite[2]
    name = 'checked-obstacle-before-tiny-shortcut'
    cases.append((name, '|'.join([name, 'checked_clip', *word_vector(unit), 'X', *words(bits(0.)),
                                'box', *word_vector(unit), 'box', *word_vector(bad)]), {'error': 'obstacle|1|1'}))
    name = 'checked-moving-before-delta'
    cases.append((name, '|'.join([name, 'checked_clip', *word_vector(bad), 'X', *words(nonfinite[0])]),
                  {'error': 'moving|1'}))
    name = 'checked-delta-before-obstacle'
    cases.append((name, '|'.join([name, 'checked_clip', *word_vector(unit), 'X', *words(nonfinite[0]),
                                'box', *word_vector(bad)]), {'error': 'delta'}))
    return cases


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--skip-build', action='store_true')
    args = parser.parse_args()
    fixtures = json.loads(FIXTURES.read_text())
    assert fixtures['schema_version'] == 1
    provenance = verify_fixture_provenance(fixtures)
    checks = []
    for source in ['src/geometry.bend', 'tests/geometry.bend']:
        checks.append(run([BEND, source, '--check-only']))
        checks.append(run([BEND, source, '--verdict'], required=False))
    builds = []
    if not args.skip_build:
        builds.append(run([BEND, 'tests/geometry.bend', '-o', 'build/geometry-tests.c']))
        builds.append(run([BEND, 'tests/geometry.bend', '-o', BINARY]))
    native = []; oracle = []; excluded = Counter(); operation_counts = Counter(); tag_counts = Counter()
    names = set()
    box_api_cases = []
    for case in fixtures['cases']:
        assert case['id'] not in names, case['id']; names.add(case['id'])
        query = request(case)
        if query is None:
            excluded[case['operation']] += 1
            continue
        oracle.append((case['id'], query, case['expected']))
        operation_counts[case['operation']] += 1
        tag_counts.update(case.get('tags', []))
        # Independently exercise public List<AABB> clipping, in addition to the
        # Collider lane, only when there are no explicit empty shape entries.
        if case['operation'] == 'raw_array_boxes_collide' and all(s['kind'] == 'raw_array_box' for s in case['input']['shapes']):
            additional = dict(case, id=case['id'] + '-box-api')
            box_api_cases.append((additional['id'], request(additional, 'clip_boxes'), case['expected']))
    assert oracle and operation_counts['raw_array_box_collide'] and operation_counts['raw_array_boxes_collide']
    execute(oracle, native, 'java-oracle')
    execute(box_api_cases, native, 'public-box-list')
    validation = validation_cases()
    execute(validation, native, 'explicit-validation-policy')
    malformed = []
    unit = [bits(x) for x in [0., 0., 0., 1., 1., 1.]]
    for query in ['broken', '|'.join(['axis-error', 'clip', *word_vector(unit), 'W', *words(bits(1.))]),
                  '|'.join(['short-box', 'constructor', '0', '0']),
                  '|'.join(['short-collider', 'clip', *word_vector(unit), 'X', *words(bits(1.)), 'box'])]:
        result = run([BINARY, '--gpu', 'off', query], required=False)
        assert result['exit_code'] == 2 and 'invalid geometry' in result['stderr'], result
        malformed.append({'query': query, 'exit_code': result['exit_code'], 'stderr': result['stderr']})
    c_path = ROOT / 'build/geometry-tests.c'
    c = c_path.read_text() if c_path.exists() else ''
    scalar_helpers = re.findall(r'INLINE Term spin_\d+\([^)]*\) \{.*?\n\}', c, re.S)
    floating_helpers = [index for index, body in enumerate(scalar_helpers)
                        if re.search(r'\b(?:double|float|f32|F32_BIN|F32_PRM)\b', body)]
    assert not floating_helpers, floating_helpers
    sources = ['src/geometry.bend', 'src/f64.bend', 'tests/geometry.bend', 'tools/test_geometry.py', 'docs/GEOMETRY.md']
    result = {
        'schema_version': 1, 'status': 'native-oracle-pass', 'scope': 'AABB and ordered occupied single-cell box collision substrate',
        'minecraft_version': '26.3', 'compiler': run([BEND, 'version'])['stdout'].strip(),
        'fixture_path': str(FIXTURES.relative_to(ROOT)), 'fixture_sha256': sha(FIXTURES),
        'fixture_provenance': provenance,
        'source_sha256': {path: sha(ROOT / path) for path in sources if (ROOT / path).exists()},
        'binary_sha256': sha(BINARY), 'emitted_c_sha256': sha(c_path) if c_path.exists() else None,
        'emitted_c_bytes': len(c.encode()), 'checks': checks, 'builds': builds,
        'emitted_c_inspection': {'scalar_inline_helpers': len(scalar_helpers),
                                'host_float_scalar_helpers': len(floating_helpers),
                                'u32_scalar_helper_operations': sum(body.count('U32_BIN(') for body in scalar_helpers),
                                'note': 'Shared runtime contains F32 IO and command-line heap parsing; inspected scalar geometry/numeric/test helpers have no host float type or primitive.'},
        'implementation_laws': re.findall(r'^law ([A-Za-z0-9_]+):', (ROOT / 'src/geometry.bend').read_text(), re.M),
        'native_commands': native, 'java_oracle_cases': len(oracle), 'java_operation_counts': dict(operation_counts),
        'java_tags': dict(tag_counts), 'public_box_list_oracle_cases': len(box_api_cases),
        'explicit_validation_cases': len(validation), 'malformed_protocol_cases': malformed,
        'excluded_out_of_substrate_operations': dict(excluded),
        'kernel_pass': all(c['exit_code'] == 0 for c in checks if '--verdict' in c['command']),
        'not_implemented': ['Shapes.box snapping', 'voxel shape union/merger', 'multi-cell VoxelShape collision', 'full player motion'],
        'confidence': 'high for recorded finite fixtures; no exhaustive IEEE geometry theorem'
    }
    EVIDENCE.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps({key: result[key] for key in ['status', 'java_oracle_cases', 'java_operation_counts',
          'public_box_list_oracle_cases', 'explicit_validation_cases', 'kernel_pass', 'excluded_out_of_substrate_operations']}, indent=2))


if __name__ == '__main__':
    main()
