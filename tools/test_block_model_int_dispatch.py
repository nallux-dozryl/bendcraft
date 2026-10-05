#!/usr/bin/env python3
"""Reuse the pinned numeric Java corpus against the changed real model decoder."""
from __future__ import annotations

import argparse
from contextlib import redirect_stdout
import json
from pathlib import Path

import test_remote_resource_client as R

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / 'build/generic-resource-world-sample-numeric-original-corpus-001'
OLD = ROOT / 'build/generic-resource-world-sample-numeric-continuations-001/candidate-001/focused-native-001'
CONTROL = ROOT / 'build/generic-resource-world-sample-numeric-first-order-003/candidate-blockstate_model/native'
PINS = {
    'cached-corpus.json': '96a3769487bb57897b3bd1dc7ad7baead828b586eed7260739565fb3e9fc293a',
    'exponent-corpus.json': 'ccfd19ce6afd53666679a3718a4bed9133d96af31348db96421ea873fb0d75ac',
}
CONTROL_SHA = '8212dc03bd81c14ac073d66051ae88b785beaa4bcb025c29ca838c335e4860db'


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False)


def run(binary, work):
    binary, work = Path(binary).resolve(), Path(work).resolve()
    work.mkdir(parents=True, exist_ok=False)
    R.WORK = work
    for name, expected in PINS.items():
        assert R.pin(CORPUS / name)['sha256'] == expected
    rows = sum((json.loads((CORPUS / name).read_text())['cases'] for name in PINS), [])
    prior_result = json.loads((OLD / 'native-result.json').read_text())
    prior_observed = json.loads((OLD / 'native-observations.json').read_text())['candidate']
    assert prior_result['status'] == 'PASS' and prior_result['original_java_cases_per_variant'] == 45
    assert prior_result['corpus_sha256'] == PINS
    assert R.pin(OLD / 'native-observations.json')['sha256'] == prior_result['observations_sha256']
    assert R.pin(OLD / 'refusal-inputs.json')['sha256'] == prior_result['refusal_inputs_sha256']
    refusals = json.loads((OLD / 'refusal-inputs.json').read_text())['cases']
    assert len(rows) == 45 and len(refusals) == 4
    assert R.pin(CONTROL)['sha256'] == CONTROL_SHA
    observed, processes = {'original_java': [], 'bounded_refusals': []}, []
    for kind, executable in [('model', binary), ('blockstate', CONTROL)]:
        before = R.pin(executable)
        for label, cases in [('original_java', rows), ('bounded_refusals', refusals)]:
            selected = [row for row in cases if row['kind'] == kind]
            offset = 0
            while offset < len(selected):
                chunk, args = [], []
                for row in selected[offset:]:
                    value = row['text'] if kind == 'model' else canonical(row['request'])
                    if args and (len(args) >= 15 or sum(map(len, args)) + len(value) > 65536):
                        break
                    chunk.append(row)
                    args.append(value)
                name = kind + '-' + label + '-' + str(offset)
                with (work / 'launches.log').open('a') as log, redirect_stdout(log):
                    process = R.bounded([executable, '--threads', '1', *args], 30, name)
                R.process_ok(process)
                print(json.dumps({'case_group': name, 'seconds': process['seconds'], 'exit': process['exit_code']}), flush=True)
                processes.append(process)
                stdout = Path(process['stdout']['path']).read_text().splitlines()
                assert len(stdout) == len(chunk) and process['stderr']['bytes'] == 0
                for row, raw in zip(chunk, stdout, strict=True):
                    if kind == 'model':
                        prefix, separator, payload = raw.partition('\t')
                        assert separator and prefix in ('ok', 'error')
                        actual = {'status': 'ok', 'parsed': json.loads(payload)} if prefix == 'ok' else {'status': 'error'}
                    else:
                        actual = json.loads(raw)
                    if label == 'original_java':
                        assert actual['status'] == row['expected']['status']
                        if actual['status'] == 'ok':
                            comparable = {k: v for k, v in actual.items() if k != 'diagnostics'} if kind == 'blockstate' else actual
                            assert canonical(comparable) == canonical(row['expected'])
                    else:
                        prior = next(old for old in prior_observed[label] if old['id'] == row['id'])
                        assert actual['status'] == 'error' and canonical(actual) == canonical(prior['actual'])
                        if kind == 'model':
                            assert raw == prior['raw']
                    observed[label].append({'id': row['id'], 'kind': kind, 'raw': raw, 'actual': actual})
                offset += len(chunk)
        assert R.pin(executable) == before
    for name, expected in PINS.items():
        assert R.pin(CORPUS / name)['sha256'] == expected
    R.write(work / 'observations.json', observed, True)
    result = {'status': 'PASS', 'changed_model_java_cases': 17, 'changed_model_exact_refusals': 2,
              'unchanged_cached_blockstate_java_controls': 28, 'unchanged_cached_blockstate_refusals': 2,
              'changed_binary': R.pin(binary), 'cached_control_binary': R.pin(CONTROL),
              'corpus_sha256': PINS, 'observations': R.pin(work / 'observations.json'),
              'processes': processes, 'scope': 'Complete existing Java success projections and exact cached bounded refusal records; no whole-parser theorem or renderer acceptance.'}
    R.write(work / 'result.json', result, True)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    result = run(**vars(parser.parse_args()))
    print(json.dumps({k: result[k] for k in ('status', 'changed_model_java_cases', 'changed_model_exact_refusals', 'unchanged_cached_blockstate_java_controls', 'unchanged_cached_blockstate_refusals')}))
