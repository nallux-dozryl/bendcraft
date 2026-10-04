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
SCOPE = ('Actual standalone remote_resource_catalog_client production graph, '
         'including correlated catalog frames, CW.Assets, WRF.draw_catalog, '
         'hardware-key/menu consumer and native Window loop. Compilation alone '
         'does not establish a native transport, presentation or pixel result. '
         'The static resource profile remains an explicit coverage instrument; '
         'registry-backed demand loading and named renderer/material requirements '
         'remain separate consumer work.')


def configure(number):
    global WORK
    assert 1 <= number <= 999
    WORK = ROOT/'build/generic-resource-world-sample-client-native'/f'{number:03d}'
    Catalog.ENTRY = ENTRY
    Catalog.WORK = WORK
    Catalog.PRIVATE = WORK/'private'
    Catalog.BINARY = WORK/'renderer'
    Remote.WORK = WORK


def write(path, value):
    Path(path).write_text(json.dumps(value, sort_keys=True, indent=2)+'\n')


def prepare():
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
    assert Catalog.sources() == before
    assert all(Catalog.sha(path) == sha for path, sha in manifest['files'].items())
    public = {'status':'frozen_native_pending', 'scope':SCOPE,
              'entry':Remote.pin(ENTRY), 'source_map':Remote.pin(Catalog.PRIVATE/'source-map.json'),
              'manifest':Remote.pin(Catalog.PRIVATE/'manifest.json'), 'basis':manifest['basis'],
              'production_sources':before, 'original_compiler_untouched':True,
              'native_consumer_run':False, 'window_opened':False,
              'commands':{'prepare':'python3 tools/generic_resource_world_sample_client_native.py',
                          'build':'python3 tools/generic_resource_world_sample_client_native.py --build'}}
    if not EVIDENCE.exists():
        write(EVIDENCE, public)
    return manifest


def build():
    manifest = prepare()
    receipt_path = Catalog.PRIVATE/'receipt.json'
    assert not receipt_path.exists(), 'Preserve the existing attempt; use a substantive fresh generation'
    _, emission = Catalog.run([sys.executable, Catalog.PRIVATE/'run.py'], 'private-emission', 620)
    receipt = json.loads(receipt_path.read_text())
    assert receipt['returncode'] == 0 and receipt['termination_reason'] is None
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
              'window_transform':Remote.pin(WORK/'window-transform.json'),
              'original_compiler_untouched':True, 'native_consumer_run':False, 'window_opened':False}
    write(WORK/'build.json', result)
    write(EVIDENCE, result)
    print(json.dumps({'status':result['status'], 'binary':result['binary'],
                     'emission_seconds':receipt['seconds'], 'native_seconds':native['seconds']}), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--generation', type=int, default=1)
    parser.add_argument('--build', action='store_true')
    args = parser.parse_args()
    configure(args.generation)
    try:
        if args.build:
            build()
        else:
            manifest = prepare()
            print(json.dumps({'status':'frozen_native_pending', 'entry':manifest['entry'],
                              'source_map':Remote.pin(Catalog.PRIVATE/'source-map.json')}))
    except BaseException as error:
        write(WORK/'failure.json', {'status':'failed', 'scope':SCOPE, 'type':type(error).__name__,
              'message':str(error), 'retained_receipts':[Remote.pin(path) for path in sorted(WORK.glob('*.receipt.json'))]})
        raise
