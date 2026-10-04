#!/usr/bin/env python3
"""One original Book checks nine laws; five cooking owner joins reach the kernel."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import time

from reference_inventory import fingerprint, write_json
from test_player_block_inside_stuck import run, require

ROOT = Path(__file__).resolve().parents[1]
NODE = Path('/opt/homebrew/Cellar/node/23.5.0/bin/node')
KERNEL = Path('/Users/chuah/.bend/bendtt/e15042434e73aab0/bendtt')
EXPORT = ROOT / 'tools/local_player_cooking_proof.mjs'
BASE = ROOT / 'build/local-player-cooking-proof'
EVIDENCE = ROOT / 'evidence/local-player-cooking-proof-020.json'
API = Path('/Users/chuah/Documents/ChatGPT/bendex/bend/bend2')


def runner_pins():
    return {str(path): fingerprint(path) for path in [
        Path(__file__).resolve(), EXPORT, ROOT / 'tools/test_player_block_inside_stuck.py',
        ROOT / 'tools/reference_inventory.py', API / 'bend.ts', API / 'safe.ts', NODE, KERNEL]}


def verify_sources(pins):
    for path, digest in pins.items():
        require(hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest, 'proof source changed: ' + path)


def prior_failed_attempts():
    attempts = []
    for path in sorted((ROOT / 'evidence').glob('local-player-cooking-proof-failure-*.json')):
        data = json.loads(path.read_text())
        require(data['status'] == 'failed', 'invalid prior failure ledger: ' + str(path))
        diagnosis = data.get('diagnosis', {})
        attempts.append({'path':str(path), 'fingerprint':fingerprint(path),
                         'folder':data['folder'], 'receipts':data['receipts'],
                         'phase':diagnosis.get('phase', data['error']),
                         'source_api_check_passed':diagnosis.get('source_api_check_passed'),
                         'kernel_executed':diagnosis.get('kernel_executed',
                             any('independent-kernel' in item['stdout']['file'] for item in data['receipts'])),
                         'native_executed':False})
    return attempts


def main():
    folder = BASE / str(time.time_ns())
    folder.mkdir(parents=True, exist_ok=False)
    runners, receipts, history = runner_pins(), [], prior_failed_attempts()
    try:
        # The Node call performs the sole book_valid pass. A separate CLI
        # ordinary check would needlessly check these same imports again.
        _, checked = run([NODE, '--experimental-transform-types', '--stack-size=4096', EXPORT, folder],
                         folder, 'original-book-check-and-export', 180)
        receipts.append(checked)
        selection = json.loads((folder / 'selection.json').read_text())
        scope = json.loads((folder / 'scope.json').read_text())
        sources = json.loads((folder / 'source-pins.json').read_text())
        require(scope['exclusions'] == [], 'export scope exclusions')
        require(selection['selected_root_count'] == 5 and len(selection['roots']) == 5, 'five selected cooking owner joins')
        require(len(selection['ordinary_roots']) == 9 and len(selection['ordinary_only_roots']) == 4,
                'nine ordinary laws with four explicit export boundaries')
        require(selection['original_book_checks'] == 1 and selection['shared_imports_loaded_once'], 'duplicated original Book checking')
        require(selection['checked_types_and_bodies_unchanged']
                and selection['all_original_tlds_ctrs_tmps_retained'], 'altered original declarations')
        verify_sources(sources)
        require(runners == runner_pins(), 'proof runner/toolchain changed')
        stdout, verdict = run(['/usr/bin/env', 'LEAN_STACK_SIZE_KB=4194304', KERNEL, folder / 'selected.bendtt'],
                              folder, 'independent-kernel', 60)
        receipts.append(verdict)
        require(stdout.strip() == b'ALL PROOFS CHECK', stdout.decode(errors='replace'))
        verify_sources(sources)
        require(runners == runner_pins(), 'proof runner/toolchain changed during kernel')
        require(history == prior_failed_attempts(), 'prior failure evidence changed during proof')
        evidence = {'status':'passed', 'generation':20, 'folder':str(folder), 'kernel_laws':5, 'ordinary_laws':9, 'roots':selection['roots'],
                    'ordinary_roots':selection['ordinary_roots'], 'ordinary_only_roots':selection['ordinary_only_roots'],
                    'ordinary_only_reason':selection['ordinary_only_reason'],
                    'scope_exclusions':[], 'original_book_checks':1, 'ordinary_entries':selection['ordinary_entries'],
                    'ordinary_seconds':selection['ordinary_seconds'], 'export_seconds':scope['export_seconds'],
                    'checked_types_and_bodies_unchanged':True, 'all_original_declaration_maps_retained':True,
                    'selection':fingerprint(folder / 'selection.json'), 'artifact':fingerprint(folder / 'selected.bendtt'),
                    'source_pins':sources, 'source_pin_manifest':fingerprint(folder / 'source-pins.json'),
                    'term_pins':selection['term_pins'], 'ordinary_law_term_pins':selection['ordinary_law_term_pins'],
                    'ordinary_only_term_pins':selection['ordinary_only_term_pins'],
                    'runner_pins':runners, 'receipts':receipts, 'prior_failed_attempts':history,
                    'scope':'Independent kernel checks complete Session cooking query and inventory query supplier-result publication, actual pending-effect delivery suffix publication, public restore refusal preserving an already bound actual entity/RNG carrier, and complete entity-delivery result publication through the actual constructor continuation. Arbitrary complete Core, Registry, cooking arrays/incarnation/reset acknowledgement/entity-carrier/tail, inventory and all player/save/tail fields are retained where specified. The bound carrier law retains the actual Model.State and exact pending Bits64 clock list; it does not construct or validate a random stream and fixes the outer Sidecar tail to empty. The entity-delivery helper law permits an arbitrary affine tail and uses actual Adapter.status formatting; it establishes no raw-error payload preservation or public delivery admission/IO theorem. Initialized-begin refusal, paused admitted idle tick retention, malformed-context physical-save refusal and admitted active-tick recursive-tail refusal remain ordinary-only because actual public declarations retain the observed Nat.show export limitation. All nine laws, existing runtime test annotation and Detached join laws receive one ordinary check in the same original Book. Tick-wide rollback, physical codec/durable save, entity spawning/delivery fidelity, separate kernel replay of old laws, native behavior and OS integration are outside this proof scope.'}
        write_json(EVIDENCE, evidence)
        print(json.dumps({'status':'passed', 'generation':20, 'kernel_laws':5, 'ordinary_laws':9, 'artifact_bytes':evidence['artifact']['bytes'],
                          'original_book_checks':1, 'ordinary_seconds':selection['ordinary_seconds'],
                          'export_seconds':scope['export_seconds'], 'kernel_seconds':verdict['seconds']}))
    except BaseException as error:
        for name in ['original-book-check-and-export', 'independent-kernel']:
            path = folder / (name + '.json')
            if path.exists():
                receipt = json.loads(path.read_text())
                if not any(item['pid'] == receipt['pid'] for item in receipts): receipts.append(receipt)
        selection_path = folder / 'selection.json'
        passed = None
        if selection_path.exists():
            try:
                passed = json.loads(selection_path.read_text()).get('ordinary_source_api_check_passed')
            except (OSError, ValueError):
                pass
        kernel_executed = any('independent-kernel' in item['stdout']['file'] for item in receipts)
        diagnosis = {'source_api_check_passed':passed, 'kernel_executed':kernel_executed, 'native_executed':False,
                     'phase':'independent-kernel' if kernel_executed else
                             'source-checked/export-or-pin-validation' if passed else 'original-book-load/check'}
        for name in ['selection.json', 'scope.json', 'source-pins.json', 'selected.bendtt']:
            path = folder / name
            if path.exists(): diagnosis[name] = fingerprint(path)
        failure = {'status':'failed', 'folder':str(folder), 'error':repr(error), 'runner_pins':runners,
                   'receipts':receipts, 'diagnosis':diagnosis}
        write_json(folder / 'failure.json', failure)
        write_json(ROOT / 'evidence' / ('local-player-cooking-proof-failure-' + folder.name + '.json'), failure)
        raise


if __name__ == '__main__':
    main()
