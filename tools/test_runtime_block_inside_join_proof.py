#!/usr/bin/env python3
"""Check actual runtime block-inside laws and their full checked dependency export."""
from __future__ import annotations
import json, pathlib, time
from reference_inventory import fingerprint, write_json
from test_player_motion_current import run

ROOT = pathlib.Path(__file__).resolve().parents[1]
KERNEL = pathlib.Path('/Users/chuah/.bend/bendtt/e15042434e73aab0/bendtt')
NODE = pathlib.Path('/opt/homebrew/Cellar/node/23.5.0/bin/node')

def main():
    folder = ROOT / 'build/runtime-block-inside-join-proof' / str(time.time_ns())
    folder.mkdir(parents=True, exist_ok=False)
    checks = []
    try:
        _, ordinary = run(['/Users/chuah/.bend/bin/bend', ROOT / 'src/runtime_block_inside_join_proof.bend', '--check-only'],
                          folder, 'ordinary', 120)
        checks.append(ordinary)
        _, exported = run([NODE, '--experimental-transform-types', '--stack-size=4096',
                           ROOT / 'tools/runtime_block_inside_join_proof.mjs', folder], folder, 'export', 180)
        checks.append(exported)
        scope = json.loads((folder / 'scope.json').read_text())
        selection = json.loads((folder / 'selection.json').read_text())
        assert scope['exclusions'] == []
        assert selection['checked_types_and_bodies_unchanged'] and selection['all_original_tlds_ctrs_tmps_retained']
        assert selection['selected_root_count'] == 13
        stdout, checked = run(['/usr/bin/env', 'LEAN_STACK_SIZE=4194304', KERNEL, folder / 'selected.bendtt'],
                             folder, 'independent-kernel', 60)
        checks.append(checked)
        assert stdout.strip() == 'ALL PROOFS CHECK', stdout
        evidence = {'status': 'passed', 'folder': str(folder), 'laws': 13, 'roots': selection['roots'], 'scope_exclusions': [],
                    'checked_types_and_bodies_unchanged': True, 'all_original_declaration_maps_retained': True,
                    'receipts': checks, 'selection': fingerprint(folder / 'selection.json'),
                    'artifact': fingerprint(folder / 'selected.bendtt'), 'kernel': fingerprint(KERNEL),
                    'source_pins': fingerprint(folder / 'source-pins.json'),
                    'term_pins': selection['term_pins'], 'export_script': fingerprint(ROOT / 'tools/runtime_block_inside_join_proof.mjs'),
                    'compiler_api': [fingerprint(pathlib.Path('/Users/chuah/Documents/ChatGPT/bendex/bend/bend2') / name)
                                     for name in ['bend.ts', 'safe.ts']], 'node': fingerprint(NODE),
                    'scope': 'Actual X Metadata/Work receiver updates and preservation through player/control/pose setters; actual selected flying mode and old-position callback inputs; outer finish and callback refusal restore full canonical pre-travel anchor, including receiver, under named actual service premises; startup success clears unsaved receiver while preserving affine owners and failed validation retains runtime; changed actual RT bundle detour law with arbitrary complete runtime owner. OS effects, whole native tick execution, general shapes/fluids and nonzero impulse persistence are outside these laws.'}
        write_json(ROOT / 'evidence/runtime-block-inside-join-proof.json', evidence)
        print(json.dumps({'status': evidence['status'], 'laws': 13, 'artifact_bytes': evidence['artifact']['bytes'],
                          'seconds': [x['seconds'] for x in checks]}))
    except BaseException as error:
        write_json(folder / 'failure.json', {'status': 'failed', 'error': repr(error), 'receipts': checks})
        raise

if __name__ == '__main__': main()
