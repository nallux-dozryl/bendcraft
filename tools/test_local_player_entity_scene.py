#!/usr/bin/env python3
"""Check the complete actual Entry plus atomic frame and publication owner laws."""
from __future__ import annotations
import argparse
import json
import pathlib
import time
from reference_inventory import fingerprint, write_json
from test_player_motion_current import run

ROOT = pathlib.Path(__file__).resolve().parents[1]
NODE = pathlib.Path('/opt/homebrew/bin/node')
KERNEL = pathlib.Path('/Users/chuah/.bend/bendtt/e15042434e73aab0/bendtt')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--generation',type=int,required=True)
    options = parser.parse_args()
    directory = ROOT / 'build/local-player-entity-scene' / f'proof-{options.generation:03d}-{time.time_ns()}'
    directory.mkdir(parents=True,exist_ok=False)
    try:
        _, source_receipt = run([NODE,'--expose-gc','--max-old-space-size=8192','--stack-size=4096',
            '--experimental-transform-types',ROOT / 'tools/local_player_entity_scene_proof.mjs',directory],
            directory,'original-source-export',120)
        source = json.loads((directory / 'source-checked.json').read_bytes())
        write_json(ROOT / f'evidence/local-player-entity-scene-source-{options.generation:03d}.json',
            {**source,'receipt':source_receipt,'directory':str(directory),
             'runner':fingerprint(pathlib.Path(__file__)),
             'checker':fingerprint(ROOT / 'tools/local_player_entity_scene_proof.mjs')})
        result = json.loads((directory / 'source-proof.json').read_bytes())
        assert result['original_book_checks'] == 1 and result['holes'] == 0
        assert result['exclusions'] == [] and len(result['roots']) == 12
        stdout,kernel_receipt = run(['/usr/bin/env','LEAN_STACK_SIZE_KB=4194304',KERNEL,
            directory / 'entity-scene.bendtt'],directory,'independent-kernel',60)
        assert stdout.strip() == 'ALL PROOFS CHECK',stdout
        for item in result['source_files']:
            assert fingerprint(pathlib.Path(item['path']))['sha256'] == item['sha256'],item['path']
        evidence = {**result,'status':'passed','generation':options.generation,'directory':str(directory),
            'source_receipt':source_receipt,'kernel_receipt':kernel_receipt,
            'artifact':fingerprint(directory / 'entity-scene.bendtt'),'kernel':fingerprint(KERNEL),
            'runner':fingerprint(pathlib.Path(__file__)),
            'checker':fingerprint(ROOT / 'tools/local_player_entity_scene_proof.mjs'),
            'native_or_transport_claim':False}
        write_json(ROOT / f'evidence/local-player-entity-scene-proof-{options.generation:03d}.json',evidence)
        print(json.dumps({'status':'passed','declarations':result['declarations'],
            'roots':len(result['roots']),'source_seconds':source_receipt['seconds'],
            'kernel_seconds':kernel_receipt['seconds']}))
    except BaseException as error:
        if (directory / 'source-checked.json').exists():
            source = json.loads((directory / 'source-checked.json').read_bytes())
            receipt = json.loads((directory / 'original-source-export.json').read_bytes())
            write_json(ROOT / f'evidence/local-player-entity-scene-source-{options.generation:03d}.json',
                {**source,'receipt':receipt,'directory':str(directory),'proof_followup_failed':repr(error),
                 'runner':fingerprint(pathlib.Path(__file__)),
                 'checker':fingerprint(ROOT / 'tools/local_player_entity_scene_proof.mjs')})
        write_json(directory / 'failure.json',{'status':'failed','error':repr(error)})
        raise

if __name__ == '__main__':
    main()
