#!/usr/bin/env python3
"""Build the actual standalone catalog client through the tested private route.

Default preparation only freezes sources. Compilation uses the existing queue
producer and bounded runner; native presentation uses the existing platform
transform. No product/compiler implementation is supplied by this helper.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

PYTHON = Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
if Path(sys.executable).resolve() != PYTHON.resolve():
    import os
    os.execv(str(PYTHON), [str(PYTHON), __file__, *sys.argv[1:]])

import resource_block_catalog_test as Catalog
import platform_build as Platform
import test_remote_resource_client as Remote

ROOT = Path(__file__).resolve().parents[1]
ENTRY = ROOT/'remote_resource_catalog_client.bend'
EVIDENCE = ROOT/'evidence/generic_resource_world_sample_client_native.json'
WORK = ROOT/'build/generic-resource-world-sample-client-native/001'
MEMORY_BASIS = ROOT/'build/actor-compiler-memory-001'
MEMORY_EVIDENCE = ROOT/'evidence/actor-compiler-memory-001.json'
SCOPE = ('Actual standalone remote_resource_catalog_client production graph, '
         'including correlated catalog frames, CW.Assets, WRF.draw_catalog, '
         'hardware-key/menu consumer and native Window loop. Compilation alone '
         'does not establish a native transport, presentation or pixel result. '
         'The static resource profile remains an explicit coverage instrument; '
         'registry-backed demand loading and named renderer/material requirements '
         'remain separate consumer work.')


def configure(number):
    global WORK, EVIDENCE
    assert 1 <= number <= 999
    WORK = ROOT/'build/generic-resource-world-sample-client-native'/f'{number:03d}'
    if number != 1:
        EVIDENCE = ROOT/'evidence'/f'generic_resource_world_sample_client_native_{number:03d}.json'
    Catalog.ENTRY = ENTRY
    Catalog.WORK = WORK
    Catalog.PRIVATE = WORK/'private'
    Catalog.BINARY = WORK/'renderer'
    Remote.WORK = WORK


def write(path, value):
    Path(path).write_text(json.dumps(value, sort_keys=True, indent=2)+'\n')


def commands(memory):
    base = ('python3 tools/generic_resource_world_sample_client_native.py '
            f'--generation {int(WORK.name)}')
    if memory:
        base += ' --memory-producer'
    return {'prepare':base, 'build':base+' --build'}


def record_failure(error):
    value = {'status':'failed', 'scope':SCOPE, 'type':type(error).__name__,
             'message':str(error),
             'retained_receipts':[Remote.pin(path) for path in sorted(WORK.glob('*.receipt.json'))]}
    # The latest alias is convenient, but every distinct attempt stays intact.
    records = sorted(WORK.glob('failure-attempt-*.json'))
    latest = WORK/'failure.json'
    if latest.exists() and not any(path.read_bytes() == latest.read_bytes() for path in records):
        retained = WORK/f'failure-attempt-{len(records)+1:03d}.json'
        retained.write_bytes(latest.read_bytes())
        records.append(retained)
    write(WORK/f'failure-attempt-{len(records)+1:03d}.json', value)
    write(latest, value)
    producer = Catalog.PRIVATE/'receipt.json'
    if producer.exists() and EVIDENCE.exists():
        receipt = json.loads(producer.read_text())
        if receipt['returncode'] != 0 or receipt['termination_reason'] is not None:
            public = json.loads(EVIDENCE.read_text())
            public.update(status='native_emission_failed', native_consumer_run=False,
                window_opened=False, producer=Remote.pin(producer),
                emission_failure={key:receipt.get(key) for key in (
                    'seconds','returncode','termination_reason','sampled_peak_rss_bytes',
                    'group_absent','complete_C')},
                failure=Remote.pin(latest))
            write(EVIDENCE, public)


def memory_producer(manifest):
    """Relocate the separately verified cache/progress correction, byte checked."""
    assert WORK.name != '001', 'Preserve the failed original generation'
    proof = json.loads(MEMORY_EVIDENCE.read_text())
    assert proof['verification']['status'] == 'PASS'
    assert proof['verification']['exact_C_equal_graphs'] == 9
    assert proof['verification']['native_independent_expected_outputs'] == 9
    assert proof['verification']['C_equal_under_GC'] is True
    for row in proof['candidate_files']:
        assert Remote.pin(row['path']) == row
    assert Remote.pin(proof['private_compiler']['path']) == proof['private_compiler']
    api = ROOT.parent/'bend/bend2/bend.ts'
    assert Remote.pin(api) == proof['original_checker']
    assert Remote.pin(api.with_name('comp.ts')) == proof['original_compiler']
    if manifest.get('memory_producer'):
        assert manifest['memory_producer']['evidence'] == Remote.pin(MEMORY_EVIDENCE)
        return manifest
    assert not (Catalog.PRIVATE/'receipt.json').exists()
    original = json.loads((MEMORY_BASIS/'manifest.json').read_text())
    compiler = (MEMORY_BASIS/'comp_instrumented.ts').read_text()
    compiler = compiler.replace(api.as_uri(), (Catalog.PRIVATE/'source-api/bend.ts').as_uri())
    emitter = (MEMORY_BASIS/'diagnose.mjs').read_text()
    emitter = emitter.replace(str(MEMORY_BASIS), str(Catalog.PRIVATE))
    emitter = emitter.replace(original['entry'], manifest['entry'])
    emitter = emitter.replace(api.as_uri(), (Catalog.PRIVATE/'source-api/bend.ts').as_uri())
    assert original['entry'] not in emitter and manifest['entry'] in emitter
    (Catalog.PRIVATE/'comp_instrumented.ts').write_text(compiler)
    (Catalog.PRIVATE/'diagnose.mjs').write_text(emitter)
    (Catalog.PRIVATE/'run.py').write_bytes((MEMORY_BASIS/'run.py').read_bytes())
    for path in (Catalog.PRIVATE/'comp_instrumented.ts', Catalog.PRIVATE/'diagnose.mjs', Catalog.PRIVATE/'run.py',
                 MEMORY_EVIDENCE, MEMORY_BASIS/'comp_instrumented.ts', MEMORY_BASIS/'diagnose.mjs', MEMORY_BASIS/'run.py'):
        manifest['files'][str(path)] = Catalog.sha(path)
    manifest['limits'] = {'heap_mib':8192, 'total_seconds':600, 'sampled_rss_bytes':8589934592,
                          'silence_only_cutoff':False}
    manifest['memory_producer'] = {'evidence':Remote.pin(MEMORY_EVIDENCE),
          'compiler':proof['private_compiler'], 'verification':proof['verification'],
          'substantive_delta':'WeakMap telescope cache, completed-function/pass-boundary GC and actual work telemetry',
          'environment':{'BEND_PRODUCER_LOG':str(Catalog.PRIVATE/'producer.jsonl'), 'BEND_PRODUCER_GC':'1'}}
    write(Catalog.PRIVATE/'manifest.json', manifest)
    return manifest


def prepare(memory=False):
    WORK.mkdir(parents=True, exist_ok=True)
    before = Catalog.sources()
    manifest = Catalog.prepare_private(before)
    emitter = Catalog.PRIVATE/'diagnose.mjs'
    expected = str(Catalog.PRIVATE/'source'/ENTRY.name)
    if manifest['entry'] != expected:
        old = str(Catalog.PRIVATE/'source/tests/resource_block_catalog.bend')
        assert manifest['entry'] == old and old in emitter.read_text()
        emitter.write_text(emitter.read_text().replace(old, expected))
        manifest['files'][str(emitter)] = Catalog.sha(emitter)
        manifest.update(entry=expected, scope=SCOPE)
        write(Catalog.PRIVATE/'manifest.json', manifest)
    if memory:
        manifest = memory_producer(manifest)
    assert Catalog.sources() == before
    assert all(Catalog.sha(path) == sha for path, sha in manifest['files'].items())
    public = {'status':'frozen_native_pending', 'scope':SCOPE,
              'entry':Remote.pin(ENTRY), 'source_map':Remote.pin(Catalog.PRIVATE/'source-map.json'),
              'manifest':Remote.pin(Catalog.PRIVATE/'manifest.json'), 'basis':manifest['basis'],
              'production_sources':before, 'original_compiler_untouched':True,
              'memory_producer':manifest.get('memory_producer'),
              'native_consumer_run':False, 'window_opened':False,
              'commands':commands(memory)}
    if not EVIDENCE.exists():
        write(EVIDENCE, public)
    return manifest


def build(memory=False):
    manifest = prepare(memory)
    receipt_path = Catalog.PRIVATE/'receipt.json'
    assert not receipt_path.exists(), 'Preserve the existing attempt; use a substantive fresh generation'
    _, emission = Catalog.run([sys.executable, Catalog.PRIVATE/'run.py'], 'private-emission', 620)
    receipt = json.loads(receipt_path.read_text())
    assert receipt['returncode'] == 0 and receipt['termination_reason'] is None, (
        f"Private producer {receipt['termination_reason']}: returncode {receipt['returncode']}; "
        f"complete_C {receipt['complete_C']}")
    assert receipt['group_absent'] and receipt['complete_C']
    assert receipt['source_before'] == receipt['source_after'] == manifest['files']
    loaded = json.loads((Catalog.PRIVATE/'loaded-source-pins.json').read_text())
    assert loaded == json.loads((Catalog.PRIVATE/'final-source-pins.json').read_text())
    assert all(Catalog.sha(path) == sha for path, sha in loaded.items())
    raw_path = Catalog.PRIVATE/'diagnostic.c'
    assert Catalog.sha(raw_path) == receipt['C']['sha256']
    raw = raw_path.read_text()
    assert re.search(r'^#define BANGS\s+0$', raw, re.M)
    Catalog.build_native.guard_route(raw)
    transformed = WORK/'renderer.c'
    transformed.write_text(Platform.transform(raw))
    write(WORK/'window-transform.json', {'base_window_sha256':Platform.PINNED_WINDOW_SHA256,
          'raw':Remote.pin(raw_path), 'transformed':Remote.pin(transformed), 'gpu_bangs':False})
    compiled, native = Catalog.run(['/usr/bin/clang', '-x', 'objective-c', '-fobjc-arc', '-fmodules',
                '-std=c11', '-O3', transformed, '-lpthread', '-lm', '-o', Catalog.BINARY], 'native-clang', 300)
    assert compiled.stderr == ''
    assert all(Catalog.sha(path) == sha for path, sha in manifest['files'].items())
    result = {'status':'native_built_consumer_run_pending', 'scope':SCOPE,
              'entry':Remote.pin(Catalog.PRIVATE/'source'/ENTRY.name), 'binary':Remote.pin(Catalog.BINARY),
              'source_map':Remote.pin(Catalog.PRIVATE/'source-map.json'), 'manifest':Remote.pin(Catalog.PRIVATE/'manifest.json'),
              'emission':emission, 'producer':Remote.pin(receipt_path), 'native':native,
              'sampled_peak_rss_bytes':receipt['sampled_peak_rss_bytes'], 'basis':manifest['basis'],
              'memory_producer':manifest.get('memory_producer'),
              'window_transform':Remote.pin(WORK/'window-transform.json'),
              'commands':commands(memory),
              'original_compiler_untouched':True, 'native_consumer_run':False, 'window_opened':False}
    write(WORK/'build.json', result)
    write(EVIDENCE, result)
    print(json.dumps({'status':result['status'], 'binary':result['binary'],
                     'emission_seconds':receipt['seconds'], 'native_seconds':native['seconds']}), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--generation', type=int, default=1)
    parser.add_argument('--build', action='store_true')
    parser.add_argument('--memory-producer', action='store_true',
                        help='Use the separately byte/native-verified private cache/progress correction')
    args = parser.parse_args()
    configure(args.generation)
    try:
        if args.build:
            build(args.memory_producer)
        else:
            manifest = prepare(args.memory_producer)
            print(json.dumps({'status':'frozen_native_pending', 'entry':manifest['entry'],
                              'source_map':Remote.pin(Catalog.PRIVATE/'source-map.json')}))
    except BaseException as error:
        record_failure(error)
        raise
