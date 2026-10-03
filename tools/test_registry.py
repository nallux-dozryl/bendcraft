#!/usr/bin/env python3
"""Check the native Bend registry against every explicit pinned Java state.

Python creates requests/oracles and orchestrates processes. Registry loading,
TSV/property parsing, forward resolution, and reverse resolution run in Bend.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
BEND = Path('/Users/chuah/.bend/bin/bend')
SOURCE = ROOT / 'generated/reference_blocks.tsv'
BLOCK_REPORT = ROOT / 'reference/reports/reports/blocks.json'
REGISTRY_REPORT = ROOT / 'reference/reports/reports/registries.json'
BINARY = ROOT / 'build/registry-tests'
WORK = ROOT / 'build/registry-oracle'
HEADER = 'block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json'


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(argv, timeout=180):
    started = time.monotonic()
    process = subprocess.run([str(x) for x in argv], cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    if process.returncode:
        raise RuntimeError(f'{argv}: exit {process.returncode}\n{process.stdout}\n{process.stderr}')
    return process.stdout, round(time.monotonic() - started, 5)


def assignments(mapping):
    # Deliberately reverse lexical order rather than using TSV property order.
    return json.dumps([{'name': key, 'value': mapping[key]} for key in sorted(mapping, reverse=True)], separators=(',', ':'))


def resolve(name, mapping, policy='exact'):
    return '\t'.join(['resolve', name, policy, assignments(mapping)])


def metadata(name, value, protocol):
    states = sorted(value['states'], key=lambda x: x['id'])
    strides = {}
    for key in value.get('properties', {}):
        transitions = [i for i in range(1, len(states))
                       if states[i]['properties'][key] != states[i - 1]['properties'][key]]
        strides[key] = min(transitions, default=len(states))
    properties = []
    for key in sorted(strides, key=lambda x: (-strides[x], x)):
        domain = list(dict.fromkeys(state['properties'][key] for state in states))
        properties.append({'name': key, 'values': domain, 'count': len(domain), 'stride': strides[key]})
    default = [state for state in states if state.get('default')]
    assert len(default) == 1
    return {'protocol': protocol, 'first': states[0]['id'], 'count': len(states), 'default': default[0]['id'],
            'properties': properties, 'states': states, 'default_properties': default[0].get('properties', {})}


def corpus(blocks, protocols):
    cases = [('summary', 'summary', ('summary', 1286, 35723))]
    counts = {'metadata_blocks': 0, 'forward_states': 0, 'reverse_states': 0,
              'block_defaults': 0, 'partial_defaults': 0, 'strict_missing': 0,
              'wrong_properties': 0, 'wrong_values': 0, 'duplicate_properties': 0}
    schemas = {}
    for name, report in sorted(blocks.items(), key=lambda kv: protocols[kv[0]]):
        schema = metadata(name, report, protocols[name]); schemas[name] = schema
        cases.append((f'meta:{name}', 'meta\t' + name, ('meta', schema)))
        counts['metadata_blocks'] += 1
        for state in schema['states']:
            identifier = state['id']; props = state.get('properties', {})
            cases.append((f'forward:{identifier}', resolve(name, props), ('id', identifier)))
            cases.append((f'reverse:{identifier}', f'decode\t{identifier}', ('decode', name, props,
                                                                          [p['name'] for p in schema['properties']])))
            counts['forward_states'] += 1; counts['reverse_states'] += 1
        cases.append((f'default:{name}', resolve(name, {}, 'defaults'), ('id', schema['default'])))
        counts['block_defaults'] += 1
        if schema['properties']:
            cases.append((f'missing:{name}', resolve(name, {}), ('error', 'missing-property:' + schema['properties'][0]['name'])))
            counts['strict_missing'] += 1
            default_props = schema['default_properties']
            lookup = {tuple(sorted(s.get('properties', {}).items())): s['id'] for s in schema['states']}
            for prop in schema['properties']:
                key = prop['name']; alternate = next(v for v in prop['values'] if v != default_props[key])
                expected_props = dict(default_props); expected_props[key] = alternate
                expected = lookup[tuple(sorted(expected_props.items()))]
                cases.append((f'partial:{name}:{key}', resolve(name, {key: alternate}, 'defaults'), ('id', expected)))
                counts['partial_defaults'] += 1
            first = schema['properties'][0]['name']; value = default_props[first]
            cases.append((f'bad-value:{name}', resolve(name, {first: '__invalid_value__'}, 'defaults'),
                          ('error', f'invalid-value:{first}=__invalid_value__')))
            counts['wrong_values'] += 1
            duplicate = json.dumps([{'name': first, 'value': value}, {'name': first, 'value': '__invalid_value__'}], separators=(',', ':'))
            cases.append((f'duplicate:{name}', f'resolve\t{name}\tdefaults\t{duplicate}', ('error', 'duplicate-property:' + first)))
            counts['duplicate_properties'] += 1
        cases.append((f'bad-property:{name}', resolve(name, {'__invalid_property__': 'true'}, 'defaults'),
                      ('error', 'unknown-property:__invalid_property__')))
        counts['wrong_properties'] += 1
    for name in ['', 'stone', 'Minecraft:stone', 'minecraft:', ':stone', 'minecraft:Stone',
                 'minecraft:foo bar', 'minecraft:a:b', 'minecraft:a\\b']:
        cases.append((f'bad-resource:{name}', resolve(name, {}, 'defaults'), ('error', 'invalid-resource:' + name)))
    for name in ['minecraft:__unknown_block__', 'mod:stone']:
        cases.append((f'unknown-resource:{name}', resolve(name, {}, 'defaults'), ('error', 'unknown-block:' + name)))
    for identifier in [35723, 35724, 2147483648, 4294967295]:
        cases.append((f'bad-state:{identifier}', f'decode\t{identifier}', ('error', f'invalid-state:{identifier}')))
    for identifier in ['-1', '4294967296', '00', '1.0']:
        cases.append((f'bad-state-number:{identifier}', f'decode\t{identifier}', ('error', 'schema:0:invalid U32 state ID')))
    for value in ['', '01', 'TRUE']:
        cases.append((f'bad-level:{value}', resolve('minecraft:water', {'level': value}), ('error', 'invalid-value:level=' + value)))
    # The same registry remains usable after every rejected lookup/assignment.
    cases.append(('after-errors', resolve('minecraft:oak_log', {'axis': 'y'}), ('id', 140)))
    return cases, counts


def compare(case, observed):
    name, command, expected = case
    pieces = observed.split('\t'); kind = expected[0]
    if kind == 'summary': passed = pieces == ['summary', str(expected[1]), str(expected[2])]
    elif kind == 'id': passed = pieces == ['ok', str(expected[1])]
    elif kind == 'error': passed = pieces == ['error', expected[1]]
    elif kind == 'decode':
        passed = len(pieces) == 3 and pieces[:2] == ['ok', expected[1]]
        if passed:
            values = json.loads(pieces[2]); keys = [v['name'] for v in values]
            passed = keys == expected[3] and len(set(keys)) == len(keys) and {v['name']: v['value'] for v in values} == expected[2]
    elif kind == 'meta':
        schema = expected[1]
        passed = len(pieces) == 6 and pieces[:5] == ['meta', str(schema['protocol']), str(schema['first']), str(schema['count']), str(schema['default'])]
        if passed: passed = json.loads(pieces[5]) == schema['properties']
    else: raise AssertionError(kind)
    if not passed:
        raise AssertionError(f'{name}\ncommand={command}\nexpected={expected}\nobserved={observed}')


def execute(cases, registry=SOURCE):
    total = 0; elapsed = 0.0; chunks = 0; group = []; size = 0
    def flush(group):
        nonlocal total, elapsed, chunks
        path = WORK / f'queries-{chunks:03d}.tsv'
        path.write_text(''.join(case[1] + '\n' for case in group))
        output, duration = run([BINARY, '--threads', '1', '--gpu', 'off', registry, 'batch', path])
        lines = output.splitlines()
        if len(lines) != len(group): raise AssertionError(f'{path}: {len(lines)} lines for {len(group)} requests: {output[:500]}')
        for case, observed in zip(group, lines): compare(case, observed)
        total += len(group); elapsed += duration; chunks += 1
    for case in cases:
        length = len(case[1].encode()) + 1
        if size + length > 1_000_000 and group:
            flush(group); group = []; size = 0
        group.append(case); size += length
    if group: flush(group)
    return {'requests': total, 'native_seconds': round(elapsed, 5), 'batches': chunks}


def row(protocol=0, name='demo:base', first=0, count=1, default=0, properties=None):
    return '\t'.join(map(str, [protocol, name, first, count, default, json.dumps(properties or [], separators=(',', ':'))]))


def loader_cases():
    base = row(); second = row(1, 'demo:next', 1, 1, 1)
    prop = {'name': 'axis', 'values': ['x', 'y', 'z']}
    cases = [('empty', ''), ('header-only', HEADER + '\n'), ('bad-header', 'wrong\n' + base + '\n'),
             ('missing-header', base + '\n'), ('few-columns', HEADER + '\n0\tdemo:base\n'),
             ('extra-column', HEADER + '\n' + base + '\textra\n'),
             ('protocol-gap', HEADER + '\n' + row(protocol=1) + '\n'),
             ('first-state-gap', HEADER + '\n' + row(first=1, default=1) + '\n'),
             ('duplicate-name', HEADER + '\n' + base + '\n' + row(1, 'demo:base', 1, 1, 1) + '\n'),
             ('interval-gap', HEADER + '\n' + base + '\n' + row(1, 'demo:next', 2, 1, 2) + '\n'),
             ('zero-count', HEADER + '\n' + row(count=0) + '\n'),
             ('count-product', HEADER + '\n' + row(count=2) + '\n'),
             ('default-outside', HEADER + '\n' + row(default=1) + '\n'),
             ('state-overflow', HEADER + '\n' + row(first=4294967295, count=2, default=4294967295) + '\n'),
             ('number-overflow', HEADER + '\n' + row(protocol=4294967296) + '\n'),
             ('number-negative', HEADER + '\n' + row(protocol=-1) + '\n'),
             ('number-leading-zero', HEADER + '\n' + base.replace('0\t', '00\t', 1) + '\n'),
             ('bad-resource', HEADER + '\n' + row(name='Demo:base') + '\n'),
             ('blank-middle', HEADER + '\n' + base + '\n\n' + second + '\n')]
    bad_properties = [[], [{'name': 'axis', 'values': []}], [{'name': 'axis', 'values': ['x', 'x']}],
                      [{'name': 'axis', 'values': [1]}], [{'name': '', 'values': ['x']}],
                      [{'name': 'Axis', 'values': ['x']}], [{'name': 'axis', 'values': ['']}],
                      [{'name': 'axis', 'values': ['x'], 'extra': 1}],
                      [{'name': 'axis', 'values': ['x']}, {'name': 'axis', 'values': ['y']}],
                      [{'name': 'axis', 'values': ['x' * 257]}],
                      [{'name': 'axis', 'values': [str(i) for i in range(257)]}],
                      [{'name': f'p{i}', 'values': ['true', 'false']} for i in range(65)],
                      [{'name': f'p{i}', 'values': ['true', 'false']} for i in range(32)]]
    for index, properties in enumerate(bad_properties):
        cases.append((f'properties-{index}', HEADER + '\n' + row(count=3, properties=properties) + '\n'))
    cases.extend([('property-root', HEADER + '\n' + base.rsplit('\t', 1)[0] + '\t{}\n'),
                  ('malformed-json', HEADER + '\n' + base.rsplit('\t', 1)[0] + '\t[\n'),
                  ('file-byte-limit', ' ' * 4_194_305)])
    capacity_text = HEADER + '\n' + ''.join(row(i, f'demo:b{i}', i, 1, i) + '\n' for i in range(4097))
    cases.append(('block-capacity-4097', capacity_text))
    escaped_values = '[{"name":"axis","values":["x","\\u0078"]}]'
    escaped_names = '[{"name":"axis","values":["x"]},{"name":"\\u0061xis","values":["y"]}]'
    for name, properties in [('duplicate-escaped-values', escaped_values), ('duplicate-escaped-names', escaped_names)]:
        cases.append((name, HEADER + '\n' + base.rsplit('\t', 1)[0] + '\t' + properties + '\n'))
    observed = []
    for name, text in cases:
        path = WORK / f'bad-{name}.tsv'; path.write_text(text)
        output, duration = run([BINARY, '--threads', '1', '--gpu', 'off', path])
        if not output.startswith('load-error\t'): raise AssertionError((name, output))
        observed.append({'name': name, 'outcome': output.strip()})
    # A custom namespace and domain layout exercise the dynamic metadata path.
    custom = WORK / 'custom.tsv'
    props = [{'values': ['true', 'false'], 'name': 'powered'}, {'name': 'axis', 'values': ['x', 'y', 'z']}]
    custom.write_text(HEADER + '\r\n' + base + '\r\n' + row(1, 'demo:machine', 1, 6, 4, props) + '\r\n')
    queries = [('custom-default', resolve('demo:machine', {}, 'defaults'), ('id', 4)),
               ('custom-order', resolve('demo:machine', {'axis': 'z', 'powered': 'false'}), ('id', 6)),
               ('custom-reverse', 'decode\t6', ('decode', 'demo:machine', {'powered': 'false', 'axis': 'z'}, ['powered', 'axis']))]
    custom_results = execute(queries, custom)
    eof_registry = WORK / 'custom-no-final-newline.tsv'
    eof_registry.write_text(HEADER + '\n' + base)
    eof_results = execute([('no-final-newline', resolve('demo:base', {}), ('id', 0))], eof_registry)
    capacity = WORK / 'capacity-4096.tsv'
    capacity.write_text(HEADER + '\n' + ''.join(row(i, f'demo:b{i}', i, 1, i) + '\n' for i in range(4096)))
    capacity_results = execute([('capacity-summary', 'summary', ('summary', 4096, 4096)),
                                ('capacity-last', 'decode\t4095', ('decode', 'demo:b4095', {}, [])),
                                ('capacity-first', 'decode\t0', ('decode', 'demo:b0', {}, [])),
                                ('capacity-name', resolve('demo:b4095', {}), ('id', 4095))], capacity)
    return {'rejected_inputs': len(observed), 'cases': observed, 'custom_registry': custom_results, 'capacity_boundary': capacity_results, 'no_final_newline': eof_results}


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--skip-build', action='store_true'); options = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    release = json.loads((ROOT / 'reference/release.json').read_text()); assert release['pin'] == '26.3'
    blocks = json.loads(BLOCK_REPORT.read_text()); registries = json.loads(REGISTRY_REPORT.read_text())
    for name, value in [('blocks.json', blocks), ('registries.json', registries)]:
        assert hashlib.sha256(canonical(value)).hexdigest() == release['reports']['principal_reports'][name]['canonical_json_sha256']
    protocols = {name: value['protocol_id'] for name, value in registries['minecraft:block']['entries'].items()}
    assert len(blocks) == len(protocols) == 1286
    assert sum(len(value['states']) for value in blocks.values()) == 35723
    assert sorted(state['id'] for value in blocks.values() for state in value['states']) == list(range(35723))
    checks = {}
    for source in ['src/registry.bend', 'tests/registry.bend']:
        output, seconds = run([BEND, source, '--check-only']); checks[source] = output.strip()
        if 'ALL PROOFS CHECK' not in output: raise AssertionError(output)
    if not options.skip_build: run([BEND, 'tests/registry.bend', '-o', BINARY])
    cpath = ROOT / 'build/registry-tests.c'; run([BEND, 'tests/registry.bend', '-o', cpath])
    cases, counts = corpus(blocks, protocols); results = execute(cases); loading = loader_cases()
    proof = subprocess.run([str(BEND), 'src/registry.bend', '--verdict'], cwd=ROOT, capture_output=True, text=True)
    evidence = {'schema_version': 1, 'pin': '26.3', 'compiler': run([BEND, 'version'])[0].strip(),
                'command': 'python3 tools/test_registry.py', 'source_tsv': str(SOURCE.relative_to(ROOT)),
                'source_tsv_sha256': sha(SOURCE), 'official_blocks_canonical_sha256': hashlib.sha256(canonical(blocks)).hexdigest(),
                'official_registries_canonical_sha256': hashlib.sha256(canonical(registries)).hexdigest(),
                'checks': checks, 'kernel': {'exit_code': proof.returncode, 'stdout': proof.stdout.strip(), 'stderr': proof.stderr.strip()},
                'coverage': counts, 'execution': results, 'loader': loading,
                'source_sha256': {name: sha(ROOT / name) for name in ['src/registry.bend', 'tests/registry.bend', 'src/json.bend', 'tools/test_registry.py', 'docs/REGISTRY.md']},
                'native_c_sha256': sha(cpath), 'all_execution_checks_passed': True,
                'scope': 'Complete pinned inventory loading, metadata, state-ID/name/property conversion and validation only. No block behaviors, pack loading or mod lifecycle implemented.'}
    (ROOT / 'evidence/registry-verification.json').write_text(json.dumps(evidence, indent=2, sort_keys=True) + '\n')
    print(json.dumps({'coverage': counts, 'execution': results, 'loader_rejections': loading['rejected_inputs'],
                      'kernel_exit_code': proof.returncode, 'all_execution_checks_passed': True}, sort_keys=True))

if __name__ == '__main__': main()
