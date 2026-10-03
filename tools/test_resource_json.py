#!/usr/bin/env python3
"""Compare native pure-Bend resource parsing with pinned production Java trees.

Python supplies test inputs, Java expectations, and process orchestration only.
It does not implement the game's resource parser. The existing strict live JSON
parser and its serializer are never modified.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import platform
import random
import struct
import subprocess
import time
import zipfile
from dataclasses import dataclass
from pathlib import Path

from reference_inventory import ROOT, fingerprint
from reference_model_probe import CLIENT, verified_client_classpath
import reference_resource_json_probe as probe

BEND = Path('/Users/chuah/.bend/bin/bend')
BUILD = ROOT / 'build/resource-json'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def run(command, timeout=180, allow_failure=False):
    started = time.perf_counter()
    try:
        result = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True,
                                text=True, timeout=timeout)
        item = {'command': list(map(str, command)), 'exit_code': result.returncode,
                'stdout': result.stdout[-6000:], 'stderr': result.stderr[-6000:],
                'wall_seconds': time.perf_counter() - started}
    except subprocess.TimeoutExpired as error:
        def decoded(value):
            return value.decode(errors='replace') if isinstance(value, bytes) else value or ''
        item = {'command': list(map(str, command)), 'status': 'timeout',
                'stdout': decoded(error.stdout)[-6000:], 'stderr': decoded(error.stderr)[-6000:],
                'wall_seconds': time.perf_counter() - started}
        if not allow_failure:
            raise RuntimeError(item)
        return None, item
    if result.returncode and not allow_failure:
        raise RuntimeError(item)
    return result, item


def units(text):
    raw = text.encode('utf-16-be', errors='surrogatepass')
    return [int.from_bytes(raw[i:i+2], 'big') for i in range(0, len(raw), 2)]


def text_projection(text):
    raw = text.encode('utf-16-be', errors='surrogatepass')
    if len(raw) // 2 <= 2048:
        return {'utf16_hex': raw.hex()}
    value = 2166136261
    for unit in units(text):
        value = ((value ^ unit) * 16777619) & 0xffffffff
    return {'utf16_length': len(raw)//2, 'utf16_fnv1a32': value}


def tree_projection(tree):
    kind = tree['kind']
    if kind == 'null':
        return {'kind': kind}
    if kind == 'boolean':
        return {'kind': kind, 'value': tree['value']}
    if kind == 'number':
        return {'kind': kind, 'lexeme': tree['lexeme']}
    if kind == 'string':
        # UTF-16 hex, rather than Python's surrogate-pair normalization, is the
        # authoritative Java string representation in the recorded reference.
        text = bytes.fromhex(tree['utf16_hex']).decode('utf-16-be', errors='surrogatepass')
        return {'kind': kind, 'text': text_projection(text)}
    if kind == 'array':
        return {'kind': kind, 'elements': [tree_projection(x) for x in tree['elements']]}
    if kind == 'object':
        return {'kind': kind, 'members': [
            {'key': text_projection(bytes.fromhex(x['utf16_hex']).decode('utf-16-be', errors='surrogatepass')),
             'value': tree_projection(x['value'])} for x in tree['members']]}
    raise ValueError(kind)


def generated_tree(fixture):
    """Expand declarative stress shapes, not arbitrary JSON syntax.

    The production Java output independently records node counts, depth, kinds,
    and largest scalar hash for each of these fixtures.
    """
    spec = fixture['input_spec']
    kind, size = spec['kind'], spec['size']
    if kind in ('number_repeat', 'object_number_repeat'):
        tree = {'kind': 'number', 'lexeme': '1' * size}
    elif kind in ('exponent_repeat', 'object_exponent_repeat'):
        tree = {'kind': 'number', 'lexeme': '1e' + '1' * size}
    elif kind == 'quoted_repeat':
        text = 'x' * size
        return {'kind': 'string', 'text': text, 'utf16_hex': text.encode('utf-16-be').hex()}
    elif kind == 'array_repeat':
        return {'kind': 'array', 'elements': [{'kind': 'number', 'lexeme': '0'}] * size}
    elif kind in ('nested_array', 'nested_object'):
        tree = {'kind': 'number', 'lexeme': '0'}
        for _ in range(size):
            tree = ({'kind': 'array', 'elements': [tree]} if kind == 'nested_array' else
                    {'kind': 'object', 'members': [{'text': 'a', 'utf16_hex': '0061', 'value': tree}]})
        return tree
    else:
        raise ValueError('Unexpected accepted generated stress kind: ' + kind)
    if kind.startswith('object_'):
        tree = {'kind': 'object', 'members': [{'text': 'a', 'utf16_hex': '0061', 'value': tree}]}
    return tree


def summary(tree):
    counts, depth, largest = collections.Counter(), 0, None
    stack = [(tree, 0)]
    while stack:
        item, container_depth = stack.pop()
        kind = item['kind']
        counts[kind] += 1
        if kind in ('array', 'object'):
            container_depth += 1
            depth = max(depth, container_depth)
        if kind in ('number', 'string'):
            text = item['lexeme'] if kind == 'number' else item['text']
            raw = text.encode('utf-16-be', errors='surrogatepass')
            candidate = {'kind': kind, 'utf16_length': len(raw)//2,
                         'utf16be_sha256': sha(raw), 'prefix': text[:32], 'suffix': text[-32:],
                         'has_unpaired_surrogate': False}
            if largest is None or candidate['utf16_length'] > largest['utf16_length']:
                largest = candidate
        elif kind == 'array':
            stack.extend((x, container_depth) for x in reversed(item['elements']))
        elif kind == 'object':
            stack.extend((x['value'], container_depth) for x in reversed(item['members']))
    return {'node_count': sum(counts.values()), 'node_kinds': dict(counts),
            'max_depth': depth, 'largest_scalar': largest}


@dataclass
class Case:
    identifier: str
    category: str
    text: str
    expected: dict | None
    max_codepoints: int = 1048576
    max_depth: int = 255
    policy: bool = False


def recorded_cases(reference):
    cases = []
    for fixture, observed in zip(reference['inputs'], reference['observations']['cases']):
        result = observed['results']['gson_helper_tree']
        text = probe.fixture_text(fixture)
        expected = None
        if result['status'] == 'ok':
            tree = result.get('tree')
            if tree is None:
                tree = generated_tree(fixture)
                actual = summary(tree)
                if actual != result['tree_summary']:
                    raise AssertionError(('declarative shape disagrees with direct Java summary', fixture['id'], actual, result['tree_summary']))
            expected = tree_projection(tree)
        # The one large stress string exceeds the default whole-input budget;
        # test it at an explicitly raised supported budget, and test default
        # rejection independently below.
        cases.append(Case(fixture['id'], fixture['category'], text, expected,
                          max(1048576, len(text))))
    return cases


def fresh_cases(seed, random_count, cp):
    rng = random.Random(seed)
    inputs = []
    def add(category, text):
        inputs.append({'id': 'fresh_' + str(len(inputs)), 'category': category, 'input': text})
    alphabet = ['a', 'b', '\\', '"', '/', '\x00', '\n', '\r', '\t', 'é', 'ไทย', '😀', '\u2028', '\ud800', '\udc00']
    def string():
        text = ''.join(rng.choice(alphabet) for _ in range(rng.randrange(0, 18)))
        return json.dumps(text, ensure_ascii=bool(rng.randrange(2)))
    def number():
        text = rng.choice(['', '-']) + rng.choice(['0', str(rng.randrange(1, 10**21))])
        if rng.randrange(2):
            text += '.' + ''.join(str(rng.randrange(10)) for _ in range(rng.randrange(1, 21)))
        if rng.randrange(2):
            text += rng.choice(['e', 'E']) + rng.choice(['', '+', '-']) + str(rng.randrange(10**9))
        return text
    def tree(depth):
        kind = rng.randrange(6 if depth else 4)
        if kind == 0: return 'null'
        if kind == 1: return rng.choice(['true', 'false'])
        if kind == 2: return number()
        if kind == 3: return string()
        if kind == 4: return '[' + ','.join(tree(depth-1) for _ in range(rng.randrange(6))) + ']'
        keys = ['a', 'b', 'a', '😀', '\ud800', 'é']
        return '{' + ','.join(json.dumps(rng.choice(keys), ensure_ascii=True) + ':' + tree(depth-1)
                              for _ in range(rng.randrange(7))) + '}'
    for _ in range(random_count):
        text = tree(5)
        # Direct Java decides any token/lookahead effect of this suffix.
        text += rng.choice(['', ' ', ' {}', ' /*unterminated', 'x', ';', '\fgarbage'])
        add('generated_direct_java', rng.choice(['', '\ufeff', ' \t\n']) + text)
    for size in [1, 2, 15, 16, 17, 511, 512, 1020, 1021, 1022, 1023, 1024, 1025]:
        for wrapper in ['', '[', '{"k":']:
            suffix = '' if not wrapper else ']' if wrapper == '[' else '}'
            for prefix in ['', ' ' * 1020]:
                add('numeric_buffer_boundary', prefix + wrapper + '1' * size + suffix)
    for _ in range(120):
        token = rng.choice(['01', '-01', '+1', '.5', '5.', '1e', 'NaN', 'Infinity', 'TRUE', 'nUlL'])
        add('malformed_token_direct_java', rng.choice(['', '[', '{"a":']) + token + rng.choice(['', ']', '}', ',0]']))
    # Exact real model JSON text, read only from the verified pinned client JAR.
    with zipfile.ZipFile(CLIENT) as jar:
        names = sorted(x for x in jar.namelist() if x.startswith('assets/minecraft/models/') and x.endswith('.json'))
        selected = rng.sample(names, min(64, len(names)))
        for name in selected:
            item = {'id': 'asset_' + str(len(inputs)), 'category': 'pinned_model_resource',
                    'input': jar.read(name).decode('utf-8'), 'entry': name}
            inputs.append(item)
    observed, execution = probe.execute(inputs, cp, 'native-random')
    cases = []
    for fixture, result in zip(inputs, observed['cases']):
        outcome = result['results']['gson_helper_tree']
        expected = tree_projection(outcome['tree']) if outcome['status'] == 'ok' else None
        cases.append(Case(fixture['id'], fixture['category'], fixture['input'], expected))
    return cases, {'inputs_sha256': sha(probe.encoded(inputs)), 'observations_sha256': sha(probe.encoded(observed)),
                   'execution': execution, 'cases': len(cases), 'reference_assets': [x['entry'] for x in inputs if 'entry' in x]}


def policy_cases():
    cases = []
    def add(identifier, text, expected, size=1048576, depth=255):
        cases.append(Case(identifier, 'explicit_policy', text, expected, size, depth, True))
    add('limit_empty_zero', '', None, 0)
    add('limit_scalar_exact', 'null', {'kind': 'null'}, 4)
    add('limit_scalar_below', 'null', None, 3)
    add('limit_trailing_budget', '{} ' + 'x'*16, None, 2)
    add('limit_surrogate_pair_counts_one_scalar', '"😀"', {'kind': 'string', 'text': text_projection('😀')}, 3)
    add('limit_depth_zero_scalar', '0', {'kind': 'number', 'lexeme': '0'}, depth=0)
    add('limit_depth_zero_container', '[]', None, depth=0)
    add('limit_depth_one_exact', '[0]', {'kind': 'array', 'elements': [{'kind': 'number', 'lexeme': '0'}]}, depth=1)
    add('limit_depth_one_below', '[[]]', None, depth=1)
    add('limit_depth_above_java_is_clamped', '['*256+'0'+']'*256, None, depth=0xffffffff)
    add('limit_input_u32_max_supported', 'true', {'kind': 'boolean', 'value': True}, 0xffffffff)
    add('limit_input_above_u32_unsupported', 'true', None, 0x100000000)
    add('limit_default_exact', ' '* (1048576-4) + 'null', {'kind': 'null'})
    add('limit_default_plus_one', ' '* (1048576-3) + 'null', None)
    add('limit_big_quoted_default_reject', '"'+'x'*1048576+'"', None)
    add('limit_duplicate_supplementary_canonical', '{"😀":1,"\\ud83d\\ude00":2}',
        {'kind':'object','members':[{'key':text_projection('😀'),'value':{'kind':'number','lexeme':'2'}}]})
    return cases


def kernel_projection():
    source = (ROOT/'src/resource_json.bend').read_text()
    ast_source = (ROOT/'src/json.bend').read_text()
    ast = ast_source[ast_source.index('type Value is Data:'):ast_source.index('def default_limits()')]
    names = ['Value', 'Member', 'Limits', 'JNull', 'JBool', 'JNumber', 'JString', 'JArray', 'JObject', 'JMember']
    import re
    for name in names:
        ast = re.sub(r'\b' + name + r'\b', 'ResourceAST_' + name, ast)
    body = source.replace('import Base\n', '', 1).replace('import ./json.bend as J\n', '', 1)
    body = body.replace('J.', 'ResourceAST_')
    helpers = (ROOT/'tests/resource_json.bend').read_text().split('# Native harness.')[0]
    helpers = '\n'.join(x for x in helpers.splitlines() if not x.startswith('import '))
    helpers = helpers.replace('J.', 'ResourceAST_').replace('R.', '')
    module = 'import Base\n\n' + ast + '\n' + body + '\n' + helpers + '\n'
    path = BUILD/'parser-kernel.bend'
    path.write_text(module)
    return path, {'source_sha256': sha(source.encode()), 'ast_declarations_sha256': sha(ast_source[ast_source.index('type Value is Data:'):ast_source.index('def default_limits()')].encode()),
                  'projection_sha256': sha(module.encode()), 'source_characters': len(source),
                  'transformation': 'Retain every production parser definition verbatim except import deletion and J. namespace substitution; retain exact Value/Member/Limits declarations except a capture-avoiding namespace prefix; append verbatim seven finite-law helpers with import/namespace substitution. No production definition, check, fuel, or law is omitted.'}


def native_cases(binary, cases):
    started, observed_rows = time.perf_counter(), []
    paths = []
    for index, case in enumerate(cases):
        path = BUILD/('input-%04d.u32le' % index)
        # Python Unicode characters are transmitted as raw values, so a literal
        # supplementary scalar and two UTF-16 units both exercise the parser.
        path.write_bytes(b''.join(struct.pack('<I', ord(c)) for c in case.text))
        paths.append(path)
    commands, categories, accepted, rejected = [], collections.Counter(), 0, 0
    for offset in range(0, len(cases), 24):
        args = []
        batch = cases[offset:offset+24]
        for path, case in zip(paths[offset:offset+24], batch):
            args.extend([str(path), str(case.max_codepoints), str(case.max_depth)])
        result, item = run([binary, '--gpu', 'off', '--threads', '1', '--', *args], timeout=180)
        commands.append({k: v for k, v in item.items() if k not in ['stdout', 'stderr']})
        rows = result.stdout.splitlines()
        if len(rows) != len(batch):
            raise AssertionError(('native row count', offset, len(rows), len(batch), result.stdout[-2000:], result.stderr))
        for case, row in zip(batch, rows):
            observed = json.loads(row)
            if case.expected is None:
                if observed.get('ok') is not False:
                    raise AssertionError(('unexpected native acceptance', case.identifier, repr(case.text[:200]), observed))
                rejected += 1
            else:
                if not observed.get('ok') or observed['tree'] != case.expected:
                    raise AssertionError(('tree differs from actual Java projection', case.identifier, repr(case.text[:200]), observed, case.expected))
                accepted += 1
            categories[case.category] += 1
            observed_rows.append({'id':case.identifier, 'output': observed})
    return {'accepted': accepted, 'rejected': rejected, 'categories': dict(categories),
            'observed_sha256': sha(probe.encoded(observed_rows)),
            'wall_seconds_including_startup_file_read_parser_observer_output': time.perf_counter()-started,
            'batches': len(commands)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend', type=Path, default=BEND)
    parser.add_argument('--random', type=int, default=512)
    parser.add_argument('--seed', type=int, default=0x2634a50)
    parser.add_argument('--native-only', action='store_true', help='Skip independent-kernel attempts during development')
    parser.add_argument('--recorded-only', action='store_true', help='Use pinned observations without additional Java fuzz inputs')
    args = parser.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)
    reference = json.loads((ROOT/'reference/resource_json.json').read_text())
    probe.validate(reference)
    cp, provenance = verified_client_classpath()
    if probe.encoded(provenance) != probe.encoded(reference['provenance']):
        raise AssertionError('Installed pinned runtime provenance differs from reference')
    commands = []
    for source in ['src/resource_json.bend', 'tests/resource_json.bend']:
        _, item = run([args.bend, source])
        commands.append(item)
    kernel, projection = kernel_projection()
    if not args.native_only:
        for source in ['src/resource_json.bend', 'tests/resource_json.bend']:
            _, item = run([args.bend, source, '--verdict'], timeout=120, allow_failure=True)
            commands.append(item)
        verdict, item = run([args.bend, kernel, '--verdict'], timeout=180, allow_failure=True)
        commands.append(item)
        if verdict is None or verdict.returncode or 'ALL PROOFS CHECK' not in verdict.stdout:
            raise AssertionError(('complete production parser projection did not pass independent kernel', item))
    binary = BUILD/'resource-json-tests'
    _, item = run([args.bend, 'tests/resource_json.bend', '-o', binary], timeout=240)
    commands.append(item)
    cases = recorded_cases(reference)
    fresh = None
    if not args.recorded_only:
        additions, fresh = fresh_cases(args.seed, args.random, cp)
        cases.extend(additions)
    cases.extend(policy_cases())
    result = native_cases(binary, cases)
    evidence = {'schema':1, 'status':'pass', 'scope':'Pinned 26.3 production GsonHelper STRICT first-tree text behavior; caller Cuboid/model semantics and general LENIENT parser compatibility are not established.',
                'confidence':'high for recorded and tested cases; no universal Gson correctness theorem',
                'independent_kernel_status':'skipped' if args.native_only else 'complete production-definition projection and seven finite laws pass; full import-closure attempts recorded separately',
                'reference':fingerprint(ROOT/'reference/resource_json.json'), 'reference_counts':reference['counts'],
                'reference_observations_sha256':reference['observations_sha256'], 'fresh_java':fresh,
                'native':result, 'case_count':len(cases), 'explicit_policy_cases':sum(x.policy for x in cases),
                'default_budget':{'max_input_bend_characters':1048576,'max_container_depth':255,'max_numeric_ascii_units':1023},
                'large_string_check_boundary':'Strings <=2048 UTF-16 units compare every unit; larger declarative stress strings compare parsed kind, unit count, and 32-bit FNV, not every output unit. Expected stress shape is separately checked against actual Java SHA256/depth/node summary.',
                'kernel_projection':projection, 'commands':commands,
                'input_sha256':sha(probe.encoded([{'id':x.identifier,'text':x.text,'limit':x.max_codepoints,'depth':x.max_depth} for x in cases])),
                'source_files':{p:fingerprint(ROOT/p) for p in ['src/resource_json.bend','tests/resource_json.bend','tools/test_resource_json.py','tools/reference_resource_json_probe.py']},
                'compiler':fingerprint(args.bend), 'native_binary':fingerprint(binary),
                'platform':{'system':platform.system(),'release':platform.release(),'machine':platform.machine()},
                'reproduce':'python3 tools/reference_resource_json_probe.py selftest; python3 tools/test_resource_json.py'}
    destination = ROOT/'evidence/resource-json-native.json'
    destination.write_text(json.dumps(evidence, ensure_ascii=True, sort_keys=True, indent=2)+'\n')
    print(json.dumps({'evidence':str(destination),'case_count':len(cases),'native':result,
                      'kernel':[{k:v for k,v in item.items() if k in ['command','exit_code','status','stdout']} for item in commands if '--verdict' in item['command']]}, indent=2))


if __name__ == '__main__':
    main()
