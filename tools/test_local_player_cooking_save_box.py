#!/usr/bin/env python3
"""Check the changed actual save consumer and its new complete-owner laws."""
from __future__ import annotations
import argparse
import json
import pathlib
import time
from reference_inventory import fingerprint, write_json
from test_player_motion_current import run

ROOT=pathlib.Path(__file__).resolve().parents[1]
NODE=pathlib.Path('/opt/homebrew/bin/node')
KERNEL=pathlib.Path('/Users/chuah/.bend/bendtt/e15042434e73aab0/bendtt')

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--generation',type=int,required=True)
    options=parser.parse_args()
    directory=ROOT/'build/local-player-cooking-save-box'/f'proof-{options.generation:03d}-{time.time_ns()}'
    directory.mkdir(parents=True,exist_ok=False)
    helper=ROOT/'tools/local_player_cooking_save_box_proof.mjs'
    source=None
    try:
        _,source_receipt=run([NODE,'--expose-gc','--max-old-space-size=8192','--stack-size=4096',
            '--experimental-transform-types',helper,directory],directory,'original-source-export',120)
        source=json.loads((directory/'source-checked.json').read_bytes())
        write_json(ROOT/f'evidence/local-player-cooking-save-box-source-{options.generation:03d}.json',
            {**source,'receipt':source_receipt,'directory':str(directory),'kernel_or_native_claim':False,
             'runner':fingerprint(pathlib.Path(__file__)),'checker':fingerprint(helper)})
        scope=json.loads((directory/'scope.json').read_bytes())
        assert source['original_book_checks']==1 and source['holes']==0
        assert scope['exclusions']==[] and scope['roots']==source['roots']
        stdout,kernel_receipt=run(['/usr/bin/env','LEAN_STACK_SIZE_KB=4194304',KERNEL,directory/'save-box.bendtt'],
            directory,'independent-kernel',60)
        assert stdout.strip()=='ALL PROOFS CHECK',stdout
        for item in source['source_files']:
            assert fingerprint(pathlib.Path(item['path']))['sha256']==item['sha256'],item['path']
        write_json(ROOT/f'evidence/local-player-cooking-save-box-proof-{options.generation:03d}.json',
            {**source,'status':'passed','scope_selection':scope,'source_receipt':source_receipt,'kernel_receipt':kernel_receipt,
             'directory':str(directory),'artifact':fingerprint(directory/'save-box.bendtt'),'kernel':fingerprint(KERNEL),
             'runner':fingerprint(pathlib.Path(__file__)),'checker':fingerprint(helper),
             'native_io_or_actor_claim':False})
        print(json.dumps({'status':'passed','roots':len(source['roots']),'declarations':source['declarations'],
            'source_seconds':source_receipt['seconds'],'kernel_seconds':kernel_receipt['seconds']}))
    except BaseException as error:
        if(directory/'source-checked.json').exists():
            source=json.loads((directory/'source-checked.json').read_bytes())
            write_json(ROOT/f'evidence/local-player-cooking-save-box-source-{options.generation:03d}.json',
                {**source,'receipt':json.loads((directory/'original-source-export.json').read_bytes()),
                 'directory':str(directory),'kernel_or_native_claim':False,'followup_failed':repr(error),
                 'runner':fingerprint(pathlib.Path(__file__)),'checker':fingerprint(helper)})
        attempt={'status':'failed','error':repr(error),'directory':str(directory),
            'source_checked':source is not None,'runner':fingerprint(pathlib.Path(__file__)),
            'checker':fingerprint(helper),'native_io_or_actor_claim':False}
        write_json(directory/'failure.json',attempt)
        write_json(ROOT/f'evidence/local-player-cooking-save-box-attempt-{options.generation:03d}.json',attempt)
        raise

if __name__=='__main__':
    main()
