#!/usr/bin/env python3
"""Check actual player-motion laws and their unchanged full dependency export."""
from __future__ import annotations
import json, pathlib, time
from reference_inventory import fingerprint, write_json
from test_player_motion_current import run

ROOT = pathlib.Path(__file__).resolve().parents[1]
KERNEL = pathlib.Path('/Users/chuah/.bend/bendtt/e15042434e73aab0/bendtt')
NODE = pathlib.Path('/opt/homebrew/Cellar/node/23.5.0/bin/node')

def main():
    folder = ROOT / 'build/player-block-inside-stuck-proof' / str(time.time_ns())
    folder.mkdir(parents=True, exist_ok=False)
    checks = []
    try:
        _, ordinary = run(['/Users/chuah/.bend/bin/bend', ROOT / 'src/player_block_inside_stuck_proof.bend', '--check-only'],
                          folder, 'ordinary', 60)
        checks.append(ordinary)
        _, exported = run([NODE, '--experimental-transform-types', '--stack-size=4096',
                           ROOT / 'tools/player_block_inside_stuck_proof.mjs', folder], folder, 'export', 60)
        checks.append(exported)
        scope = json.loads((folder / 'scope.json').read_text())
        selection = json.loads((folder / 'selection.json').read_text())
        assert scope['exclusions'] == []
        assert selection['checked_types_and_bodies_unchanged'] and selection['all_original_tlds_ctrs_tmps_retained']
        assert selection['selected_root_count'] == 15
        stdout, checked = run(['/usr/bin/env', 'LEAN_STACK_SIZE=4194304', KERNEL, folder / 'selected.bendtt'],
                             folder, 'independent-kernel', 60)
        checks.append(checked)
        assert stdout.strip() == 'ALL PROOFS CHECK', stdout
        evidence = {'status': 'passed', 'folder': str(folder), 'laws': 15, 'roots': selection['roots'], 'scope_exclusions': [],
                    'checked_types_and_bodies_unchanged': True, 'all_original_declaration_maps_retained': True,
                    'receipts': checks, 'selection': fingerprint(folder / 'selection.json'),
                    'artifact': fingerprint(folder / 'selected.bendtt'), 'kernel': fingerprint(KERNEL),
                    'source_pins': fingerprint(folder / 'source-pins.json'),
                    'term_pins': selection['term_pins'], 'export_script': fingerprint(ROOT / 'tools/player_block_inside_stuck_proof.mjs'),
                    'compiler_api': [fingerprint(pathlib.Path('/Users/chuah/Documents/ChatGPT/bendex/bend/bend2') / name)
                                     for name in ['bend.ts', 'safe.ts']], 'node': fingerprint(NODE),
                    'scope': 'Actual block callbacks, arbitrary complete Core/Registry/receiver/history owner retention, speculative callback rejection, transient consumption and actual MH join retention. IEEE constants and shape/traversal specifications independently observed against pinned Java.'}
        write_json(ROOT / 'evidence/player-block-inside-stuck-proof.json', evidence)
        print(json.dumps({'status': evidence['status'], 'laws': 15, 'artifact_bytes': evidence['artifact']['bytes'],
                          'seconds': [x['seconds'] for x in checks]}))
    except BaseException as error:
        write_json(folder / 'failure.json', {'status': 'failed', 'error': repr(error), 'receipts': checks})
        raise

if __name__ == '__main__': main()
