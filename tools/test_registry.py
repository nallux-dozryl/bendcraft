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
KERNEL = Path('/Users/chuah/.bend/bendtt/e15042434e73aab0/bendtt')
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


def kernel_verdict(source, timeout=120):
    command = [str(BEND), source, '--verdict']; started = time.monotonic()
    try:
        proof = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
        return {'source': source, 'command': command, 'exit_code': proof.returncode,
                'stdout': proof.stdout.strip(), 'stderr': proof.stderr.strip(),
                'seconds': round(time.monotonic() - started, 5), 'timed_out': False}
    except subprocess.TimeoutExpired as proof:
        def text(value):
            return (value.decode(errors='replace') if isinstance(value, bytes) else value or '').strip()
        return {'source': source, 'command': command, 'exit_code': None,
                'stdout': text(proof.stdout), 'stderr': text(proof.stderr),
                'seconds': round(time.monotonic() - started, 5), 'timed_out': True,
                'timeout_seconds': timeout}


def identity_kernel_evidence():
    source = (ROOT / 'src/registry.bend').read_text()
    slices = {
        'metadata_types': source[source.index('type Property is Data:'):source.index('def empty_block()')],
        'bounded_byte_reader': source[source.index('# File bytes are bounded'):source.index('def Registry.load.result(')],
        'canonical_identity_and_laws': source[source.index('# Canonical identity v1'):source.index('# Small implementation laws;')],
    }
    projection = ROOT / 'build/registry-identity-laws.bend'
    projection.write_text('import Base\nimport ../src/hash.bend as Hash\nimport ../src/unicode.bend as Unicode\n\n' + ''.join(slices.values()))
    # The implementation bodies/types/laws are copied byte-for-byte. Only
    # unrelated TSV/JSON parsing/resolution and their imports are excluded.
    checked, _ = run([BEND, projection, '--check-only'])
    projected = kernel_verdict(str(projection.relative_to(ROOT)))
    assert projected['exit_code'] == 0 and not projected['timed_out'], projected
    serialized = ROOT / 'build/registry-identity.bendtt'
    emitted, _ = run([BEND, 'src/registry.bend', '-o', serialized])
    started = time.monotonic()
    direct = subprocess.run([str(KERNEL), str(serialized)], cwd=ROOT, capture_output=True, text=True, timeout=120)
    result = {
        'schema_version': 1, 'compiler': run([BEND, 'version'])[0].strip(),
        'production_source_sha256': sha(ROOT / 'src/registry.bend'),
        'imported_source_sha256': {name: sha(ROOT / name) for name in ['src/hash.bend', 'src/unicode.bend', 'src/json.bend']},
        'projection': {'path': str(projection.relative_to(ROOT)), 'sha256': sha(projection),
                       'slice_sha256': {name: hashlib.sha256(value.encode()).hexdigest() for name, value in slices.items()},
                       'check_command': [str(BEND), str(projection), '--check-only'], 'check_stdout': checked.strip(),
                       'verdict': projected},
        'full_production_diagnostic': {'emit_command': [str(BEND), 'src/registry.bend', '-o', str(serialized)],
            'emit_stdout': emitted.strip(), 'serialized_bytes': serialized.stat().st_size, 'serialized_sha256': sha(serialized),
            'kernel_binary': str(KERNEL), 'kernel_sha256': sha(KERNEL),
            'command': [str(KERNEL), str(serialized)], 'exit_code': direct.returncode,
            'stdout': direct.stdout.strip(), 'stderr': direct.stderr.strip(), 'seconds': round(time.monotonic() - started, 5)},
        'scope': ['Metadata types, bounded raw-byte reader, canonical identity implementation and three new laws are projected verbatim.',
                  'Projection passes independent kernel typing/termination and all its stated implementation laws.',
                  'Projection excludes unrelated JSON parser/resolver definitions; it does not establish a full registry-module verdict.',
                  'No compiler/kernel edits, unsafe declarations, foreign implementation, axioms or unfilled proofs.']}
    (ROOT / 'evidence/registry-identity-kernel.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    return result


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


def identity_bytes(records):
    """Independent binary-format oracle over metadata, never source TSV bytes."""
    output = bytearray(b'BendRegistryIdentity\0')
    def word(value):
        assert 0 <= value <= 0xffffffff
        output.extend(value.to_bytes(4, 'big'))
    def string(value):
        encoded = value.encode('utf-8', errors='strict')
        word(len(encoded)); output.extend(encoded)
    word(1); word(len(records)); word(sum(record['count'] for record in records))
    for record in records:
        word(record['protocol']); string(record['name'])
        for key in ['first', 'count', 'default']:
            word(record[key])
        word(len(record['properties']))
        for prop in record['properties']:
            string(prop['name']); word(prop['count']); word(prop['stride'])
            assert prop['count'] == len(prop['values'])
            for value in prop['values']:
                string(value)
    return bytes(output)


def identity_hash(records):
    return hashlib.sha256(identity_bytes(records)).hexdigest()


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
    records = [dict(schemas[name], name=name) for name in sorted(schemas, key=protocols.get)]
    digest = identity_hash(records)
    cases.insert(1, ('identity-before', 'identity', ('identity', digest)))
    cases.extend([('identity-after', 'identity', ('identity', digest)),
                  ('identity-surrogate-error', 'identity-forged-surrogate', ('identity-error', 'canonical UTF-8: invalid Unicode scalar in String')),
                  ('identity-after-surrogate', 'identity', ('identity', digest)),
                  ('identity-range-error', 'identity-forged-range', ('identity-error', 'canonical UTF-8: invalid Unicode scalar in String')),
                  ('identity-after-range', 'identity', ('identity', digest)),
                  ('lookup-after-identity-errors', resolve('minecraft:oak_log', {'axis': 'y'}), ('id', 140))])
    counts['canonical_identity_calls'] = 4
    counts['identity_failure_retains_owner'] = 2
    return cases, counts


def compare(case, observed):
    name, command, expected = case
    pieces = observed.split('\t'); kind = expected[0]
    if kind == 'summary': passed = pieces == ['summary', str(expected[1]), str(expected[2])]
    elif kind in ['identity', 'identity-error']: passed = pieces == list(expected)
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
    valid_prefix = (HEADER + '\n' + base + '\n').encode()
    malformed_utf8 = [
        ('overlong-nul', b'\xc0\x80'), ('overlong-two', b'\xc1\xbf'),
        ('overlong-three', b'\xe0\x80\xaf'), ('overlong-four', b'\xf0\x80\x80\xaf'),
        ('surrogate-high', b'\xed\xa0\x80'), ('surrogate-low', b'\xed\xbf\xbf'),
        ('out-of-range', b'\xf4\x90\x80\x80'), ('invalid-leading', b'\xff'),
        ('stray-continuation', b'\x80'), ('invalid-continuation', b'\xc2 '),
        ('truncated-two', b'\xc2'), ('truncated-three', b'\xe2\x82'),
        ('truncated-four', b'\xf0\x9f\x92')]
    for name, suffix in malformed_utf8:
        cases.append(('utf8-' + name, valid_prefix + suffix))
    observed = []
    for name, text in cases:
        path = WORK / f'bad-{name}.tsv'; path.write_bytes(text if isinstance(text, bytes) else text.encode())
        output, duration = run([BINARY, '--threads', '1', '--gpu', 'off', path])
        if not output.startswith('load-error\t'): raise AssertionError((name, output))
        if name.startswith('utf8-') and not output.startswith('load-error\tschema:0:UTF-8: '):
            raise AssertionError((name, 'not rejected by strict decoder before TSV parse', output))
        if name == 'file-byte-limit' and output.strip() != 'load-error\tschema:0:file exceeds 4194304 bytes':
            raise AssertionError((name, output))
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
    # Exactly 4 MiB remains valid. Spread permitted JSON spaces over rows so
    # each property JSON remains well within its independent 16,384-scalar cap.
    capacity_lines = capacity.read_text().splitlines()
    padding = 4_194_304 - len(capacity.read_bytes())
    per_row, extra = divmod(padding, 4096)
    exact_lines = [capacity_lines[0]] + [line[:-1] + ' ' * (per_row + (index < extra)) + ']'
                   for index, line in enumerate(capacity_lines[1:])]
    exact = WORK / 'capacity-exact-4mib.tsv'
    exact.write_bytes(('\n'.join(exact_lines) + '\n').encode())
    assert exact.stat().st_size == 4_194_304
    capacity_records = [fixture_record(f'demo:b{i}', i, i, [], i) for i in range(4096)]
    exact_results = execute([('exact-byte-limit-summary', 'summary', ('summary', 4096, 4096)),
                             ('exact-byte-limit-identity', 'identity', ('identity', identity_hash(capacity_records)))], exact)
    return {'rejected_inputs': len(observed), 'malformed_utf8_inputs': len(malformed_utf8), 'cases': observed,
            'custom_registry': custom_results, 'capacity_boundary': capacity_results,
            'exact_4mib': exact_results, 'no_final_newline': eof_results}


def fixture_record(name, protocol=0, first=0, properties=None, default=None):
    domains = properties or []
    product = 1; assigned = []
    for prop in reversed(domains):
        assigned.insert(0, {'name': prop['name'], 'values': prop['values'], 'count': len(prop['values']), 'stride': product})
        product *= len(prop['values'])
    return {'protocol': protocol, 'name': name, 'first': first, 'count': product,
            'default': first if default is None else default, 'properties': assigned}


def fixture_tsv(records, *, ending='\n', final=True, ascii=False, reverse_members=False, spaces=False, slash_escape=False):
    lines = [HEADER]
    for record in records:
        props = [({'values': prop['values'], 'name': prop['name']} if reverse_members else
                  {'name': prop['name'], 'values': prop['values']}) for prop in record['properties']]
        text = json.dumps(props, ensure_ascii=ascii, separators=(', ', ': ') if spaces else (',', ':'))
        if slash_escape:
            text = text.replace('/', '\\/')
        lines.append('\t'.join(map(str, [record['protocol'], record['name'], record['first'], record['count'], record['default'], text])))
    return (ending.join(lines) + (ending if final else '')).encode('utf-8')


def identity_cases():
    manifests = []; seen = {}; fixtures = []
    base = fixture_record('demo:base')
    props = [{'name': 'powered', 'values': ['true', 'false']}, {'name': 'axis', 'values': ['x', 'y', 'z']}]
    machine = fixture_record('demo:machine', 1, 1, props, 4)
    def add(name, records, *, same=None, different=None, **layout):
        data = fixture_tsv(records, **layout); expected = identity_hash(records)
        if same is not None: assert expected == seen[same]
        if different is not None: assert expected != seen[different]
        seen[name] = expected; fixtures.append((name, data, records, expected))
        manifests.append({'name': name, 'file_bytes': len(data), 'raw_tsv_sha256': hashlib.sha256(data).hexdigest(),
                          'canonical_bytes': len(identity_bytes(records)), 'identity': expected,
                          'equal_to': same, 'different_from': different})
    add('machine', [base, machine])
    add('machine-crlf', [base, machine], ending='\r\n', same='machine')
    add('machine-eof', [base, machine], final=False, same='machine')
    add('machine-json-space-members', [base, machine], reverse_members=True, spaces=True, same='machine')
    add('block-name', [base, dict(machine, name='demo:changed')], different='machine')
    add('default-id', [base, dict(machine, default=5)], different='machine')
    renamed = [{'name': 'enabled', 'values': ['true', 'false']}, props[1]]
    add('property-name', [base, fixture_record('demo:machine', 1, 1, renamed, 4)], different='machine')
    changed = [props[0], {'name': 'axis', 'values': ['x', 'y', 'q']}]
    add('domain-value', [base, fixture_record('demo:machine', 1, 1, changed, 4)], different='machine')
    reversed_values = [props[0], {'name': 'axis', 'values': ['z', 'y', 'x']}]
    add('domain-order', [base, fixture_record('demo:machine', 1, 1, reversed_values, 4)], different='machine')
    add('property-order', [base, fixture_record('demo:machine', 1, 1, list(reversed(props)), 4)], different='machine')
    add('block-order', [fixture_record('demo:machine', 0, 0, props, 3), fixture_record('demo:base', 1, 6)], different='machine')
    extra = [props[0], {'name': 'axis', 'values': ['x', 'y', 'z', 'w']}]
    add('state-count', [base, fixture_record('demo:machine', 1, 1, extra, 4)], different='machine')
    strings = ['é', '🙂', 'a/b', '\0', '\t', '\n', '"', '\\']
    unicode_record = [fixture_record('demo:unicode', properties=[{'name': 'text', 'values': strings}])]
    add('unicode-literal', unicode_record)
    add('unicode-json-escaped', unicode_record, ascii=True, same='unicode-literal')
    add('unicode-slash-escaped', unicode_record, slash_escape=True, same='unicode-literal')
    add('unicode-json-members', unicode_record, reverse_members=True, spaces=True, same='unicode-literal')
    add('prefix-ab-c', [fixture_record('demo:prefix', properties=[{'name': 'p', 'values': ['ab', 'c']}])])
    add('prefix-a-bc', [fixture_record('demo:prefix', properties=[{'name': 'p', 'values': ['a', 'bc']}])], different='prefix-ab-c')
    add('normalization-composed', [fixture_record('demo:normalize', properties=[{'name': 'p', 'values': ['é']}])])
    add('normalization-decomposed', [fixture_record('demo:normalize', properties=[{'name': 'p', 'values': ['e\u0301']}])], different='normalization-composed')
    for length in [1, 63, 64, 127, 128, 255, 256]:
        for char, tag in [('a', 'ascii'), ('é', 'two-byte'), ('🙂', 'four-byte')]:
            add(f'prefix-{tag}-{length}', [fixture_record('demo:length', properties=[{'name': 'p', 'values': [char * length]}])])
    dense = [{'name': f'p{i}', 'values': [f'v{j}' for j in range(256)]} for i in range(3)]
    add('dense-domains', [fixture_record('demo:dense', properties=dense)])
    native = []
    for name, data, records, expected in fixtures:
        path = WORK / f'identity-{name}.tsv'; path.write_bytes(data)
        queries = [(name, 'identity', ('identity', expected)),
                   (name+'-repeat', 'identity', ('identity', expected)),
                   (name+'-summary', 'summary', ('summary', len(records), sum(record['count'] for record in records))),
                   (name+'-first', 'decode\t0', ('decode', records[0]['name'],
                      {prop['name']: prop['values'][0] for prop in records[0]['properties']},
                      [prop['name'] for prop in records[0]['properties']]))]
        native.append(dict(name=name, **execute(queries, path)))
    return {'format_version': 1, 'fixture_count': len(fixtures), 'fixtures': manifests, 'execution': native,
            'canonical_magic_hex': b'BendRegistryIdentity\0'.hex(), 'canonical_limit': 67_108_864}


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
    cases, counts = corpus(blocks, protocols); results = execute(cases); loading = loader_cases(); identity = identity_cases()
    proofs = [kernel_verdict(source) for source in ['src/registry.bend', 'tests/registry.bend']]
    identity_proof = identity_kernel_evidence()
    official_records = [dict(metadata(name, blocks[name], protocols[name]), name=name) for name in sorted(blocks, key=protocols.get)]
    identity['pinned_canonical_bytes'] = len(identity_bytes(official_records))
    identity['pinned_identity'] = identity_hash(official_records)
    evidence = {'schema_version': 1, 'pin': '26.3', 'compiler': run([BEND, 'version'])[0].strip(),
                'command': 'python3 tools/test_registry.py', 'source_tsv': str(SOURCE.relative_to(ROOT)),
                'source_tsv_sha256': sha(SOURCE), 'official_blocks_canonical_sha256': hashlib.sha256(canonical(blocks)).hexdigest(),
                'official_registries_canonical_sha256': hashlib.sha256(canonical(registries)).hexdigest(),
                'checks': checks, 'kernel': proofs[0], 'kernel_checks': proofs, 'identity_kernel_evidence': identity_proof,
                'coverage': counts, 'execution': results, 'loader': loading, 'canonical_identity': identity,
                'source_sha256': {name: sha(ROOT / name) for name in ['src/registry.bend', 'tests/registry.bend', 'src/json.bend', 'src/hash.bend', 'src/unicode.bend', 'tools/test_registry.py', 'docs/REGISTRY.md', 'docs/REGISTRY_IDENTITY.md'] if (ROOT / name).exists()},
                'native_binary_sha256': sha(BINARY), 'native_c_sha256': sha(cpath),
                'native_c_bytes': cpath.stat().st_size, 'all_execution_checks_passed': True,
                'scope': 'Complete pinned inventory loading, metadata, state-ID/name/property conversion and validation only. No block behaviors, pack loading or mod lifecycle implemented.'}
    (ROOT / 'evidence/registry-verification.json').write_text(json.dumps(evidence, indent=2, sort_keys=True) + '\n')
    print(json.dumps({'coverage': counts, 'execution': results, 'loader_rejections': loading['rejected_inputs'],
                      'kernel_exit_codes': [proof['exit_code'] for proof in proofs], 'identity_fixtures': identity['fixture_count'],
                      'pinned_identity': identity['pinned_identity'], 'all_execution_checks_passed': True}, sort_keys=True))

if __name__ == '__main__': main()
