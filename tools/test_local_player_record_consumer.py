#!/usr/bin/env python3
"""Read-only frozen codec corpus verifier for an explicitly pinned Session binary.

No build, native emission, Java/reference extraction, kernel run or fixture write.
The consumer supplies its final full dependency manifest and executable digest.
"""
from __future__ import annotations
import hashlib
import importlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
FROZEN=ROOT/'build/local-player-record/generation-1/prepared.json'
FROZEN_SHA256='14442c45e5eaffb36e8be6413866e3573481724cbcbff6027de359d7fd95bdc9'


def digest(data): return hashlib.sha256(data).hexdigest()


def canonical(value): return json.dumps(value,sort_keys=True,separators=(',',':')).encode()


def pin(path):
    path=Path(path).absolute()
    return {'path':str(path),'bytes':path.stat().st_size,'sha256':digest(path.read_bytes())}


def persist(path,value):
    path=Path(path)
    # All receipts are exclusive; failed/repeated runs cannot replace evidence.
    with path.open('x') as out: out.write(json.dumps(value,indent=2,sort_keys=True)+'\n')


def assert_file(path,expected):
    actual=pin(path)
    if actual['sha256']!=expected['sha256'] or actual['bytes']!=expected['bytes']:
        raise RuntimeError('changed dependency: '+str(path))
    return actual


def consumer_manifest(path):
    raw=Path(path).read_bytes();value=json.loads(raw)
    payload={k:v for k,v in value.items() if k!='seal_sha256'}
    if value.get('schema')!=1 or value.get('seal_sha256')!=digest(canonical(payload)) or not isinstance(value.get('files'),dict):
        raise RuntimeError('invalid consumer manifest seal')
    for name,item in value['files'].items(): assert_file(name,item)
    return value,pin(path)


def frozen_manifest():
    raw=FROZEN.read_bytes()
    if digest(raw)!=FROZEN_SHA256: raise RuntimeError('frozen preparation changed')
    value=json.loads(raw)
    if value['cases']!=755: raise RuntimeError('frozen corpus count changed')
    for items in (value['closure']['bend_imports'],value['closure']['python_imports']):
        for item in items: assert_file(item['path'],item)
    assert_file(value['closure']['compiler']['path'],value['closure']['compiler'])
    assert_file(value['closure']['python_interpreter']['path'],value['closure']['python_interpreter'])
    for item in value['fixtures']: assert_file(ROOT/item['path'],item)
    return value


def bounded_batch(argv,timeout,directory,label):
    stdout=directory/(label+'.stdout');stderr=directory/(label+'.stderr');receipt=directory/(label+'.process.json')
    if any(p.exists() for p in (stdout,stderr,receipt)): raise RuntimeError('existing batch attempt: '+label)
    argv=list(map(str,argv));start=time.monotonic();timed=False;proc=None;launch_error=None;rc=None
    # Pending command is durable before attempting to launch the process.
    persist(directory/(label+'.attempt.json'),{'argv':argv,'timeout_seconds':timeout})
    with stdout.open('xb') as out,stderr.open('xb') as err:
        try:
            proc=subprocess.Popen(argv,cwd=ROOT,start_new_session=True,stdout=out,stderr=err)
            try: rc=proc.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed=True
                try: os.killpg(proc.pid,signal.SIGTERM)
                except ProcessLookupError: pass
                try: rc=proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    try: os.killpg(proc.pid,signal.SIGKILL)
                    except ProcessLookupError: pass
                    rc=proc.wait(timeout=5)
        except Exception as e:
            launch_error=type(e).__name__+': '+str(e)
        finally:
            if proc is not None:
                try: os.killpg(proc.pid,signal.SIGKILL)
                except ProcessLookupError: pass
                if proc.poll() is None: proc.wait(timeout=5)
    result={'argv':argv,'timeout_seconds':timeout,'timed_out':timed,'exit_code':rc,'launch_error':launch_error,'seconds':time.monotonic()-start,'pid':proc.pid if proc else None,'stdout':pin(stdout),'stderr':pin(stderr)}
    persist(receipt,result)
    return result,stdout.read_text(errors='replace'),stderr.read_text(errors='replace')


def verify_existing_binary(binary,prefix,expected_binary_sha256,manifest_path,receipt_dir,*,runs=2):
    """Verify all 755 original fixtures, preserving them and every failed receipt.

    manifest_path: schema1 files mapping absolute paths->{sha256,bytes}; its
    seal_sha256 hashes canonical JSON of every key except seal_sha256.
    The caller owns construction of the full immutable consumer build manifest.
    """
    if runs!=2: raise ValueError('two complete same-generation runs required')
    binary=Path(binary).resolve(strict=True);directory=Path(receipt_dir).absolute()
    directory.relative_to(ROOT)
    directory.mkdir(parents=True,exist_ok=True)
    if any(directory.iterdir()): raise RuntimeError('existing verification receipts: '+str(directory))
    persist(directory/'reservation.json',{'binary':str(binary),'expected_sha256':expected_binary_sha256,'prefix':list(prefix),'runs':runs,'scope':'frozen custom record cases in actual consumer artifact'})
    summary={'status':'running','binary':str(binary),'binary_sha256':expected_binary_sha256,'prefix':list(prefix),'frozen_seal_sha256':FROZEN_SHA256,'cases':755,'runs':runs,'batches':[],'completed_executions':0}
    try:
        original=frozen_manifest();manifest,manifest_pin=consumer_manifest(manifest_path)
        summary['consumer_manifest']=manifest_pin
        bp=pin(binary)
        if bp['sha256']!=expected_binary_sha256: raise RuntimeError('consumer binary digest mismatch')
        manifest_files=manifest['files']
        if str(binary) not in manifest_files or manifest_files[str(binary)]['sha256']!=expected_binary_sha256:
            raise RuntimeError('consumer manifest must pin this exact binary')
        for p in (Path(__file__).resolve(),ROOT/'tools/test_local_player_record.py'):
            if str(p) not in manifest_files: raise RuntimeError('consumer manifest lacks codec verifier/oracle: '+str(p))
        # Import only after the original oracle/helper pins were checked.
        module=importlib.import_module('test_local_player_record');cases=module.corpus()
        files,args=module.prepared(cases,emit=False)
        if files!=original['fixtures'] or [list(x) for x in args]!=original['arguments']:
            raise RuntimeError('frozen oracle/arguments diverged')
        for run in range(runs):
            for start in range(0,len(cases),48):
                frozen_manifest();assert_file(manifest_path,manifest_pin);consumer_manifest(manifest_path)
                if pin(binary)['sha256']!=expected_binary_sha256: raise RuntimeError('consumer executable changed')
                batch=cases[start:start+48];argv=[str(binary),*map(str,prefix)];outputs=[]
                for i,(mode,inp,_) in enumerate(args[start:start+48]):
                    out=directory/f'run-{run}-case-{start+i:04}.nbt'
                    if out.exists(): raise RuntimeError('existing case output')
                    outputs.append(out);argv.extend((mode,inp,str(out)))
                label=f'run-{run}-batch-{start:04}'
                process,out,err=bounded_batch(argv,120,directory,label)
                expected=['error='+c.error if c.error else 'ok=record' for c in batch]
                matches=[];actual_outputs=[]
                for c,p in zip(batch,outputs):
                    actual=p.read_bytes() if p.exists() else None
                    matches.append(actual==c.expected)
                    actual_outputs.append({'path':str(p),'sha256':digest(actual) if actual is not None else None,'bytes':len(actual) if actual is not None else None})
                comparison={'case_names':[c.name for c in batch],'expected_lines':expected,'actual_lines':out.splitlines(),'expected_output_sha256':[digest(c.expected) if c.expected is not None else None for c in batch],'actual_outputs':actual_outputs,'bytes_match':matches,'stderr':err,'process':process}
                persist(directory/(label+'.comparison.json'),comparison)
                summary['batches'].append({'process':process,'comparison':pin(directory/(label+'.comparison.json'))})
                if process['exit_code']!=0 or process['timed_out'] or process['launch_error'] or out.splitlines()!=expected or not all(matches):
                    raise RuntimeError('codec consumer batch mismatch: '+label)
                # A concurrent generation change invalidates this batch before
                # any subsequent batch may run; original inputs are never fixed.
                frozen_manifest();assert_file(manifest_path,manifest_pin);consumer_manifest(manifest_path)
                summary['completed_executions']+=len(batch)
        summary['status']='PASS'
        summary['scope']='1,510 fixture executions in the sealed real Session binary; no independent component emission, TCP/persistence/Java/visible acceptance claim from these codec cases'
        persist(directory/'summary.json',summary)
        return summary
    except BaseException as e:
        summary['status']='FAIL';summary['error']=type(e).__name__+': '+str(e)
        if not (directory/'summary.json').exists(): persist(directory/'summary.json',summary)
        raise
