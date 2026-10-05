#!/usr/bin/env python3
"""Check the actual loader's original source and unchanged theorem closure."""
from pathlib import Path
import argparse
import hashlib
import json
import sys

from test_local_player_cooking_edit import source_check, NODE, KERNEL
from test_player_block_inside_stuck import run
from bendtt_closure import retain

ROOT = Path(__file__).resolve().parents[1]
PROOF = ROOT / 'src/entity_chunk_loading_proof.bend'
EXPORTER = ROOT / 'tools/entity_chunk_loading_proof.mjs'

def require(value, message):
    if not value:
        raise AssertionError(message)

def pin(path):
    path = Path(path)
    data = path.read_bytes()
    return {'path': str(path.resolve()), 'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest()}

def proof_check(work):
    _, export = run([NODE, '--expose-gc', '--max-old-space-size=8192', '--stack-size=4096',
                     '--experimental-transform-types', EXPORTER, work], work, 'export', 120)
    selection = json.loads((work / 'selection.json').read_text())
    scope = json.loads((work / 'scope.json').read_text())
    require(selection['ordinary_source_api_check_passed'] and selection['holes'] == 0 and
            selection['checked_types_and_bodies_unchanged'] and
            selection['all_original_tlds_ctrs_tmps_retained'], 'Original checked book changed')
    require(not scope['exclusions'], 'Actual theorem export has exclusions')
    roots = [name.replace(':', '.') for name in selection['roots']]
    exact, manifest = retain((work / 'selected.bendtt').read_bytes(), roots)
    closure = work / 'closure.bendtt'
    closure.write_bytes(exact)
    (work / 'closure.json').write_text(json.dumps(manifest, indent=2) + '\n')
    output, kernel = run(['/usr/bin/env', 'LEAN_STACK_SIZE=67108864', KERNEL, closure],
                         work, 'kernel', 60)
    require(b'ALL PROOFS CHECK' in output and not (work / 'kernel.stderr').read_bytes(),
            'Independent kernel did not accept the unchanged complete closure')
    return {'certified_roots': roots, 'export': export, 'kernel': kernel,
            'selection': pin(work / 'selection.json'), 'closure': pin(closure),
            'closure_manifest': pin(work / 'closure.json'), 'kernel_binary': pin(KERNEL)}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['source', 'proof'], default='source')
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=False)
    try:
        checked = source_check(work, PROOF) if args.mode == 'source' else proof_check(work)
        result = {'status': 'pass', 'mode': args.mode, 'checks': checked,
                  'proof_source': pin(PROOF), 'exporter': pin(EXPORTER),
                  'boundary': 'Actual transient loader metadata laws only. No real ChunkMap futures, terrain generation, entity bundle file loading, manager recovery installation, native lifecycle execution or live actor consumer is established.'}
        (work / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps({'status': result['status'], 'mode': args.mode, 'result': str(work / 'result.json')}))
    except BaseException as error:
        (work / 'failure.json').write_text(json.dumps({'status': 'failed', 'mode': args.mode,
            'error': repr(error), 'proof_source': pin(PROOF), 'exporter': pin(EXPORTER)}, indent=2) + '\n')
        raise

if __name__ == '__main__':
    main()
