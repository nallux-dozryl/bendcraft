#!/usr/bin/env python3
"""Select numeric inputs from executed, pinned Java model-codec receipts.

Preparation reads existing verified observations and launches no game or compiler.
The optional Java phase executes an unchanged original harness on exponent inputs;
it does not derive expected outputs from either Bend implementation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time

import reference_model_probe as probe
import test_block_model as model
import test_blockstate_model as state

ROOT = Path(__file__).resolve().parents[1]
DEFAULT = ROOT / 'build/generic-resource-world-sample-numeric-original-corpus-001'
MODEL_IDS = {f'integer-light-{i}' for i in range(17)}
STATE_IDS = {f'edge_dispatcher_{i}' for i in (*range(32, 40), *range(58, 68))}
EXPONENTS = (
    ('rotation_positive', 'x', '9e1'),
    ('rotation_positive_sign', 'x', '9e+1'),
    ('rotation_negative_exponent', 'x', '9e-1'),
    ('rotation_wrapped_decimal', 'x', '4.294967386e9'),
    ('rotation_large_positive', 'x', '1e+40'),
    ('rotation_large_negative', 'x', '1e-40'),
    ('weight_zero_exponent', 'weight', '1e0'),
    ('weight_positive_exponent', 'weight', '1e1'),
    ('weight_negative_exponent', 'weight', '1e-1'),
    ('weight_signed_boundary', 'weight', '2.147483648e9'),
)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def pin(path):
    path = Path(path).resolve(strict=True)
    return {'path': str(path), 'bytes': path.stat().st_size, 'sha256': sha(path)}


def write(path, value):
    with Path(path).open('x') as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write('\n')


def cache(directory):
    directory = ROOT / directory
    meta = json.loads((directory / 'metadata.json').read_text())
    for name, filename in (
        ('harness_sha256', 'ReferenceModelProbe.java'),
        ('input_sha256', 'inputs.json'),
        ('observation_sha256', 'observations.json'),
    ):
        assert sha(directory / filename) == meta[name], (directory, name)
    return (json.loads((directory / 'inputs.json').read_text()),
            json.loads((directory / 'observations.json').read_text()),
            {'directory': str(directory), 'metadata': pin(directory / 'metadata.json'),
             'harness': pin(directory / 'ReferenceModelProbe.java'),
             'inputs': pin(directory / 'inputs.json'),
             'observations': pin(directory / 'observations.json'),
             'client': meta['client'], 'java': meta['java'],
             'java_version': meta['java_version'],
             'library_provenance_sha256': meta['library_provenance_sha256']})


def blockstate_rows(inputs, observations, wanted=None):
    rows = []
    cases, actuals = inputs['dispatcher_cases'], observations['dispatcher_cases']
    assert len(cases) == len(actuals)
    for case, actual in zip(cases, actuals):
        ident = case['id']
        assert ident == actual['id']
        if wanted is not None and ident not in wanted:
            continue
        schema = observations['schemas'][case['block']]
        request = {'mode': 'dispatcher', 'text': case['json'],
                   'schema': {k: schema[k] for k in ('owner', 'properties')},
                   'states': schema['states']}
        expected = ({'status': 'error'} if actual['status'] == 'error'
                    else state.dispatcher_projection(actual['result']))
        rows.append({'id': ident, 'kind': 'blockstate', 'request': request,
                     'expected': expected, 'java_observation': actual})
    return rows


def prepare(directory):
    assert not directory.exists(), 'Use a fresh corpus directory'
    inputs, observations, model_provenance = cache('build/block-model-edges')
    state_inputs, state_observations, state_provenance = cache('build/blockstate-model-oracle')
    assert model_provenance['client'] == state_provenance['client']
    seen = {v['id']: v for v in observations['parse_cases']}
    rows = []
    for case in inputs['parse_cases']:
        if case['id'] not in MODEL_IDS:
            continue
        actual = seen[case['id']]
        expected = {'status': actual['status']}
        if actual['status'] == 'ok':
            expected['parsed'] = model.parsed(actual['parsed'])
        rows.append({'id': case['id'], 'kind': 'model', 'text': case['json'],
                     'expected': expected, 'java_observation': actual})
    rows.extend(blockstate_rows(state_inputs, state_observations, STATE_IDS))
    assert len(rows) == 35
    directory.mkdir(parents=True)
    write(directory / 'cached-corpus.json', {
        'schema': 'generic-numeric-original-corpus-v1',
        'status': 'original_java_observations_verified',
        'cases': rows, 'case_count': len(rows),
        'provenance': {'model': model_provenance, 'blockstate': state_provenance,
                       'projections': [pin(ROOT / 'tools/test_block_model.py'),
                                       pin(ROOT / 'tools/test_blockstate_model.py')]},
        'scope': 'Accepted outputs use complete existing Java-to-Bend projections; '
                 'rejected inputs compare rejection status, not Java/Bend error wording. '
                 'No candidate source, kernel, C, or native verdict is asserted.'})
    java_directory = directory / 'exponent-java'
    java_directory.mkdir()
    source = ROOT / 'build/blockstate-model-oracle/ReferenceModelProbe.java'
    shutil.copy2(source, java_directory / source.name)
    assert sha(java_directory / source.name) == sha(source)
    dispatcher = []
    for name, field, lexeme in EXPONENTS:
        value = '{"model":"minecraft:block/stone","' + field + '":' + lexeme + '}'
        if field == 'weight':
            value = '[' + value + ']'
        dispatcher.append({'id': 'exponent_' + name, 'block': 'oak_fence',
                           'json': '{"variants":{"":' + value + '}}'})
    data = {'models': {}, 'blockstates': {}, 'variants': [], 'parse_cases': [],
            'graph_cases': [], 'selector_cases': [], 'condition_cases': [],
            'dispatcher_cases': dispatcher, 'ticket_cases': [],
            'schema_blocks': ['oak_fence']}
    write(java_directory / 'inputs.json', data)
    write(directory / 'preparation.json', {
        'status': 'source_only_prepared', 'cached_corpus': pin(directory / 'cached-corpus.json'),
        'pending_java_harness': pin(java_directory / source.name),
        'pending_java_inputs': pin(java_directory / 'inputs.json'),
        'pending_java_case_count': len(dispatcher),
        'client': state_provenance['client'],
        'scope': 'Exponent inputs are prepared only; expected behavior remains unknown '
                 'until the original pinned Java harness executes.'})
    return {'directory': str(directory), 'cached_cases': len(rows),
            'pending_java_cases': len(dispatcher), 'native_run': False, 'java_run': False}


def run_java(directory):
    work = directory / 'exponent-java'
    assert not (work / 'observations.json').exists(), 'Do not overwrite a Java attempt'
    preparation = json.loads((directory / 'preparation.json').read_text())
    assert pin(work / 'ReferenceModelProbe.java') == preparation['pending_java_harness']
    assert pin(work / 'inputs.json') == preparation['pending_java_inputs']
    cp, provenance = probe.verified_client_classpath()
    assert provenance['client'] == preparation['client']
    command = [str(probe.JAVA), '--enable-native-access=ALL-UNNAMED', '-cp',
               ':'.join(map(str, cp)), str(work / 'ReferenceModelProbe.java'),
               str(work / 'inputs.json'), str(probe.CLIENT), str(work / 'observations.json')]
    began = time.monotonic()
    p = subprocess.run(command, cwd=work, capture_output=True, text=True, timeout=180)
    (work / 'stdout.log').write_text(p.stdout)
    (work / 'stderr.log').write_text(p.stderr)
    metadata = {'command': command, 'returncode': p.returncode,
                'elapsed_seconds': time.monotonic() - began,
                'harness': pin(work / 'ReferenceModelProbe.java'),
                'inputs': pin(work / 'inputs.json'), 'client': provenance['client'],
                'java': provenance['java'], 'java_version': provenance['java_version'],
                'library_provenance_sha256': hashlib.sha256(json.dumps(
                    provenance['libraries'], sort_keys=True).encode()).hexdigest()}
    write(work / 'metadata.json', metadata)
    assert p.returncode == 0, (p.returncode, p.stderr[-2000:])
    result = project_java(directory)
    return {**result, 'java_run': True}


def project_java(directory):
    """Project an existing successful attempt without repeating Java execution."""
    work = directory / 'exponent-java'
    metadata = json.loads((work / 'metadata.json').read_text())
    assert metadata['returncode'] == 0
    assert pin(work / 'ReferenceModelProbe.java') == metadata['harness']
    assert pin(work / 'inputs.json') == metadata['inputs']
    inputs = json.loads((work / 'inputs.json').read_text())
    observations = json.loads((work / 'observations.json').read_text())
    rows = blockstate_rows(inputs, observations)
    assert len(rows) == len(EXPONENTS)
    write(directory / 'exponent-corpus.json', {
        'schema': 'generic-numeric-original-corpus-v1',
        'status': 'original_java_observations_executed',
        'cases': rows, 'case_count': len(rows),
        'provenance': {'metadata': pin(work / 'metadata.json'),
                       'observations': pin(work / 'observations.json')},
        'scope': 'Original Java blockstate codec results; no candidate native verdict.'})
    return {'directory': str(directory), 'java_cases': len(rows),
            'original_java_executed': True, 'java_run': False, 'native_run': False}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--directory', type=Path, default=DEFAULT)
    phases = ap.add_mutually_exclusive_group()
    phases.add_argument('--run-java', action='store_true')
    phases.add_argument('--project-java', action='store_true')
    options = ap.parse_args()
    directory = options.directory.resolve()
    result = (run_java(directory) if options.run_java else
              project_java(directory) if options.project_java else prepare(directory))
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    main()
