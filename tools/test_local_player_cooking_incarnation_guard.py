#!/usr/bin/env python3
"""Narrow original Core/CW admission proofs and actual due-batch receiver.

No JVM/reference recapture or actor build. Native uses original C.apply as its
status oracle and the complete structural Core observer, including collisions
and short/malformed arrays. The independent kernel checks original proof roots.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import time

from reference_inventory import fingerprint, write_json
from test_player_block_inside_stuck import require, run
from test_player_look import imports

ROOT = Path(__file__).resolve().parents[1]
BEND = Path('/Users/chuah/.bend/bin/bend')
NODE = Path('/opt/homebrew/Cellar/node/23.5.0/bin/node')
KERNEL = Path('/Users/chuah/.bend/bendtt/e15042434e73aab0/bendtt')
ENTRY = ROOT / 'tests/local_player_cooking_incarnation_guard.bend'
PROOF = ROOT / 'tools/local_player_cooking_incarnation_guard_proof.mjs'
BASE = ROOT / 'build/local-player-cooking-incarnation-guard'
EVIDENCE = ROOT / 'evidence/local-player-cooking-incarnation-guard.json'
EXPECTED_GUARDS = [
    'ok prospective retains complete raw Core owner',
    'ok prospective ordered statuses agree with actual apply',
] * 3 + [
    'ok MAX teardown retains full Core/light/physical furnace',
    'ok MAX-1 rejects second replacement before either write',
    'ok remove recreate remove counts both teardown markers',
    'ok new entry after absent owner is tracked before later teardown',
    'ok accepted section create overlay and 4096 fresh headers admit later reset before any allocation',
    'ok late refusal restores earlier prospective LIT edit and whole due queue',
    'ok rejected existing-section fill and same-block properties have no resets',
    'ok rejected missing-section write cannot reset loaded owner',
    'ok two replacements admit at exactly two remaining tokens',
    'ok acknowledged reset prefix does not consume a token twice',
]
OPEN_OBLIGATIONS = [
    'Universal observed-counter exhaustion at the concrete MAX48 comparison: '
    'the original checker normalization stack overflowed while unfolding '
    'Nat.is_lt(current, maximum()). The selected proof establishes only the '
    'actual counted(False, ...) refusal branch; actual numeric thresholds '
    'require the separate native receiver.',
    'Universal prospective admission status agreement and ordered metadata '
    'completeness are outside the selected owner laws.',
]


def source_pins():
    paths = {ROOT / relative for relative in imports([ENTRY, ROOT / 'src/local_player_cooking_incarnation_guard_proof.bend'])}
    paths.update([Path(__file__).resolve(), PROOF,
                  ROOT / 'tools/test_player_block_inside_stuck.py',
                  ROOT / 'tools/test_player_look.py', ROOT / 'tools/reference_inventory.py',
                  Path('/Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts'),
                  Path('/Users/chuah/Documents/ChatGPT/bendex/bend/bend2/safe.ts'), BEND, NODE, KERNEL])
    return {str(path):fingerprint(path) for path in sorted(paths)}


def unchanged(pins):
    for path, pin in pins.items():
        require(fingerprint(Path(path)) == pin, 'source or tool changed: ' + path)


def prior_attempts():
    attempts = []
    for path in sorted((ROOT / 'evidence').glob('local-player-cooking-incarnation-guard-failure-*.json')):
        value = json.loads(path.read_text())
        attempts.append({'evidence':fingerprint(path), 'folder':value['folder'],
                         'error':value['error'],
                         'kernel_executed':value['kernel_executed'],
                         'native_executed':value['native_executed'],
                         'receipts':value['receipts']})
    return attempts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--proof-only', action='store_true')
    parser.add_argument('--source-only', action='store_true',
                        help='check/export original source and stop before kernel or native stages')
    parser.add_argument('--prepare', action='store_true', help='file-only source manifest; starts no checker/native process')
    args = parser.parse_args()
    require(not (args.source_only and args.proof_only), 'choose source-only or proof-only')
    folder = BASE / str(time.time_ns())
    folder.mkdir(parents=True, exist_ok=False)
    pins, receipts, previous = source_pins(), [], prior_attempts()
    write_json(folder / 'input-source-pins.json', pins)
    if args.prepare:
        print(json.dumps({'status':'prepared', 'folder':str(folder), 'source_files':len(pins),
                          'compiler_executed':False, 'kernel_executed':False, 'native_executed':False}))
        return
    try:
        _, receipt = run([NODE, '--experimental-transform-types', '--stack-size=4096', PROOF, folder],
                         folder, 'original-source-and-export', 180)
        receipts.append(receipt)
        selected = json.loads((folder / 'selection.json').read_text())
        scope = json.loads((folder / 'scope.json').read_text())
        require(selected['selected_root_count'] == 9 and len(selected['roots']) == 9, 'wrong original proof roots')
        require(selected['original_book_checks'] == 1 and selected['checked_types_and_bodies_unchanged']
                and selected['all_original_tlds_ctrs_tmps_retained'], 'original declarations changed')
        require(scope['exclusions'] == [], 'selected roots excluded')
        for path, pin in json.loads((folder / 'source-pins.json').read_text()).items():
            require(hashlib.sha256(Path(path).read_bytes()).hexdigest() == pin, 'export source changed')
        unchanged(pins)
        if args.source_only:
            evidence = {'status':'source-and-export-passed', 'folder':str(folder),
                        'ordinary_laws':11, 'selected_unverified_kernel_roots':selected['roots'],
                        'term_pins':selected['term_pins'], 'original_book_checks':1,
                        'checked_types_and_bodies_unchanged':True,
                        'all_original_declaration_maps_retained':True,
                        'source_pins':pins, 'receipts':receipts, 'prior_attempts':previous,
                        'artifact':fingerprint(folder / 'selected.bendtt'),
                        'kernel_executed':False, 'native_executed':False,
                        'open_obligations':OPEN_OBLIGATIONS}
            write_json(ROOT / 'evidence/local-player-cooking-incarnation-guard-source.json', evidence)
            print(json.dumps({'status':'source-and-export-passed','folder':str(folder),
                              'kernel_executed':False,'native_executed':False}))
            return
        stdout, receipt = run(['/usr/bin/env', 'LEAN_STACK_SIZE_KB=4194304', KERNEL, folder / 'selected.bendtt'],
                              folder, 'independent-kernel', 90)
        receipts.append(receipt)
        require(stdout.strip() == b'ALL PROOFS CHECK', 'independent kernel did not accept all selected original roots')
        native = None
        if not args.proof_only:
            _, receipt = run([BEND, ENTRY, '-o', folder / 'receiver.c'], folder, 'native-emission', 150)
            receipts.append(receipt)
            _, receipt = run([shutil.which('clang') or '/usr/bin/clang', '-std=c11', '-O1', folder / 'receiver.c',
                              '-lpthread', '-lm', '-o', folder / 'receiver'], folder, 'clang', 90)
            receipts.append(receipt)
            stdout, receipt = run([folder / 'receiver', '--gpu', 'off', '--threads', '1'], folder, 'native-receiver', 60)
            receipts.append(receipt)
            lines = stdout.decode().splitlines()
            require(lines == EXPECTED_GUARDS, 'native exact guard set/order differs')
            native = {'guards':lines,'emitted_c':fingerprint(folder / 'receiver.c'),
                      'binary':fingerprint(folder / 'receiver')}
        unchanged(pins)
        evidence = {'status':'passed','folder':str(folder),'proof_only':args.proof_only,
                    'ordinary_laws':11,'kernel_laws':9,'roots':selected['roots'],
                    'term_pins':selected['term_pins'],'original_book_checks':1,
                    'checked_types_and_bodies_unchanged':True,'all_original_declaration_maps_retained':True,
                    'scope_exclusions':[],'source_pins':pins,'receipts':receipts,
                    'prior_attempts':previous,'open_obligations':OPEN_OBLIGATIONS,
                    'artifact':fingerprint(folder / 'selected.bendtt'),'native':native,
                    'scope':'Inductive complete-trie retention on every actual readonly admission route; successful-created-key overlay World retention; rejected actual Core applications cannot change lifecycle metadata; real same-block identity has no teardown; the actual exhausted counted(False) branch refuses before increment; reset acknowledgement preserves counter map; failure cancels later scan; actual prepared CW guard refusal retains complete Core/light/Entry/loading/phase/key owners before clock/due publication. Native compares ordered prospective admission to unchanged C.apply on original empty/malformed/collision tries, observes full World topology/array words, and exercises MAX late refusal with physical furnace padding and light FIFO retention. Native, when run, uses a declared synthetic lifecycle fixture rather than a Java parity oracle. Universal observed MAX48 comparison correctness, application-status agreement, whole-batch metadata completeness, physical save recovery, direct player edit preflight, actual actor/menu/OS input and Java timing are outside these stated laws.'}
        write_json(EVIDENCE, evidence)
        print(json.dumps({'status':'passed','folder':str(folder),'kernel_laws':9,
                          'native_guards':len(native['guards']) if native else 0}))
    except BaseException as error:
        for name in ['original-source-and-export','independent-kernel','native-emission','clang','native-receiver']:
            path = folder / (name + '.json')
            if path.exists():
                receipt = json.loads(path.read_text())
                if not any(item['pid'] == receipt['pid'] for item in receipts): receipts.append(receipt)
        failure = {'status':'failed','folder':str(folder),'error':repr(error),'source_pins':pins,'receipts':receipts,
                   'prior_attempts':previous,'open_obligations':OPEN_OBLIGATIONS,
                   'kernel_executed':any(item['stdout']['file'].endswith('independent-kernel.stdout') for item in receipts),
                   'native_executed':any(item['stdout']['file'].endswith('native-receiver.stdout') for item in receipts)}
        selection_path = folder / 'selection.json'
        if selection_path.exists():
            failure['original_source_check'] = json.loads(selection_path.read_text())
            failure['ordinary_source_check_passed'] = True
        else:
            failure['ordinary_source_check_passed'] = False
        write_json(folder / 'failure.json',failure)
        write_json(ROOT / 'evidence' / ('local-player-cooking-incarnation-guard-failure-' + folder.name + '.json'),failure)
        raise


if __name__ == '__main__':
    main()
