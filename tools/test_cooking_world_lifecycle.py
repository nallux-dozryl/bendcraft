#!/usr/bin/env python3
"""Observe actual accepted cooking lifecycle and export its two owner laws.

Reuses the existing bounded process-group runner. The executable observations
use Bend's default JavaScript route; this helper makes no native actor claim.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

import build_native as Build
import test_campfire_authority as Paths
import test_remote_resource_client as Runner

ROOT = Path(__file__).resolve().parents[1]
ENTRY = ROOT / 'tests/cooking_world_lifecycle.bend'
WORK = ROOT / 'build/cooking-world-lifecycle'
ROOTS = ['teardown_precedes_original_ordered_intents',
         'same_block_branch_retains_owner_without_reset']
EXPECTED = [
    'remove-recreate-remove two markers and exact ordered drops/XP',
    'final cooking owner removed',
    'exactly one tick three accepted edits',
    'actual Core final block',
    'same block LIT has no teardown markers or output intents',
    'same block LIT retains original furnace contents/timers',
    'retained owner exact Core revision',
    'actual Core final block',
    'replacement reset precedes preserved drops/XP',
    'different cooking block installs fresh actual owner',
    'replacement exactly one accepted tick/edit',
    'actual Core final block',
    'rejected missing section write emits no reset',
    'same block LIT retains original furnace contents/timers',
    'retained owner exact Core revision',
    'actual Core final block',
]


def source_pins():
    snapshot = Build.Snapshot()
    base = Paths.BEND.resolve().parent.parent / 'bend2/base.bend'
    Build.source_graph(ENTRY, base, os.environ, snapshot)
    # Default JS execution also consumes JavaScript effect bodies.
    for row in list(snapshot.files.values()):
        if row['kind'] in ('bend', 'base'):
            path = Path(row['path'])
            for effect in Build.foreign_paths(path.read_text()):
                if effect.endswith('.js'):
                    snapshot.add(path.parent / effect, 'javascript-effect')
    for path in (Path(__file__), Paths.BEND, Paths.NODE, Paths.KERNEL,
                 ROOT / 'tools/cooking_world_proof.mjs'):
        snapshot.add(path, 'verification-tool')
    return snapshot.manifest()


def fresh_directory():
    WORK.mkdir(parents=True, exist_ok=True)
    for number in range(1, 10000):
        directory = WORK / f'{number:03}'
        try:
            directory.mkdir()
            return number, directory
        except FileExistsError:
            continue
    raise RuntimeError('No unused numbered lifecycle directory')


def run(with_kernel=True):
    number, directory = fresh_directory()
    before = source_pins()
    Runner.write(directory / 'sources.json', before, True)
    original_work = Runner.WORK
    rows = []
    try:
        Runner.WORK = directory
        checked = Runner.bounded([Paths.BEND, ENTRY, '--check-only'], 30, 'ordinary')
        rows.append(checked)
        Runner.process_ok(checked)
        output = Path(checked['stdout']['path']).read_text()
        Runner.require('ALL PROOFS CHECK' in output and not Path(checked['stderr']['path']).read_bytes(),
                       'Lifecycle ordinary checking did not accept every proof')
        observed = Runner.bounded([Paths.BEND, ENTRY], 30, 'actual-js')
        rows.append(observed)
        Runner.process_ok(observed)
        lines = Path(observed['stdout']['path']).read_text().splitlines()
        actual = [line[3:] for line in lines if line.startswith('ok ')]
        Runner.require(actual == EXPECTED and not Path(observed['stderr']['path']).read_bytes(),
                       'Actual lifecycle guards or diagnostics differ')
        proof = None
        if with_kernel:
            # Reuse the established exact-root exporter; declarations, checked
            # types and bodies remain intact, only Book.order selects two laws.
            exporter = (ROOT / 'tools/cooking_world_proof.mjs').read_text()
            start = exporter.index('const roots=')
            end = exporter.index(';', start) + 1
            exporter = exporter[:start] + 'const roots=' + json.dumps(ROOTS) + ';' + exporter[end:]
            script = directory / 'proof.mjs'
            script.write_text(exporter)
            exported = Runner.bounded([Paths.NODE, '--max-old-space-size=1536', '--stack-size=4096',
                                      '--experimental-transform-types', script, directory, ENTRY],
                                     30, 'proof-export')
            rows.append(exported)
            Runner.process_ok(exported)
            scope = json.loads((directory / 'scope.json').read_bytes())
            Runner.require(not scope['exclusions'], 'Lifecycle proof export excluded actual roots')
            kernel = Runner.bounded(['/usr/bin/env', 'LEAN_STACK_SIZE=67108864', Paths.KERNEL,
                                    directory / 'selected.bendtt'], 30, 'kernel')
            rows.append(kernel)
            Runner.process_ok(kernel)
            proof = {'roots': ROOTS, 'selection': Runner.pin(directory / 'selection.json'),
                     'scope': Runner.pin(directory / 'scope.json'),
                     'ir': Runner.pin(directory / 'selected.bendtt'),
                     'source_pins': Runner.pin(directory / 'source-pins.json')}
        Runner.require(before == source_pins(), 'Lifecycle input changed during checks')
        result = {'schema': 1, 'status': 'pass', 'entry': Runner.pin(ENTRY),
                  'store': Runner.pin(ROOT / 'src/cooking_world_store.bend'),
                  'api': 'Effect.OwnerReset{position:Core.Position}',
                  'guards': actual, 'processes': rows, 'proof': proof,
                  'source_manifest': Runner.pin(directory / 'sources.json'),
                  'scope': 'Actual Core scheduled lifecycle and affine cooking owner; default JS observations. '
                           'No native actor, keyed Details sidecar, save/reload or cooking-tick parity claim.'}
        Runner.write(directory / 'result.json', result, True)
        evidence = ROOT / f'evidence/cooking-world-lifecycle-{number:03}.json'
        Runner.write(evidence, result, True)
        print(json.dumps({'status': 'pass', 'evidence': str(evidence), 'guards': len(actual),
                          'kernel_laws': len(ROOTS) if with_kernel else 0}), flush=True)
        return result
    except BaseException as error:
        Runner.write(directory / 'failure.json', {'status': 'failed', 'type': type(error).__name__,
                     'message': str(error), 'processes': rows}, True)
        raise
    finally:
        Runner.WORK = original_work


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-kernel', action='store_true', help='Observe actual JS lifecycle only')
    arguments = parser.parse_args()
    run(not arguments.skip_kernel)
