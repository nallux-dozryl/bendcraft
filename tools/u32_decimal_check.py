#!/usr/bin/env python3
"""Check the shared unsigned decimal renderer without component dependencies."""
from __future__ import annotations
import argparse, hashlib, json, subprocess, time
from pathlib import Path
import build_native
from reference_inventory import ROOT, fingerprint, write_json

BEND=Path.home()/'.bend/bin/bend';BUILD=ROOT/'build/u32_decimal'

def run(args):
    start=time.monotonic();p=subprocess.run(list(map(str,args)),cwd=ROOT,capture_output=True,text=True,timeout=60)
    receipt={'command':list(map(str,args)),'exit_code':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'seconds':round(time.monotonic()-start,6)}
    assert p.returncode==0,receipt;return receipt

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--build',action='store_true');args=parser.parse_args();BUILD.mkdir(parents=True,exist_ok=True)
    paths=[ROOT/'src/u32_decimal.bend',ROOT/'src/u32_decimal_laws.bend',ROOT/'src/u32_decimal_proof.bend',ROOT/'tests/u32_decimal.bend',Path(__file__)]
    before=[{'path':str(p),**fingerprint(p)} for p in paths]
    proof=run([BEND,paths[2],'--verdict']);assert proof['stdout'].strip()=='ALL PROOFS CHECK'
    export=run([BEND,paths[2],'-o',BUILD/'proof.bendtt'])
    binary=BUILD/'observer';build=build_native.ensure_native(paths[3],binary,bend=BEND) if args.build else None
    assert binary.is_file(),'Run --build with a coordinated CPU compile slot'
    values=list(range(65536));values.extend([0xffffffff,0x80000000,0x7fffffff,0xfffffffe])
    for power in range(10):
        n=10**power;values.extend(v for v in [n-1,n,n+1] if v<=0xffffffff)
    seed=0x26c3a175
    for _ in range(8192):
        seed^=(seed<<13)&0xffffffff;seed^=seed>>17;seed^=(seed<<5)&0xffffffff;values.append(seed)
    values=list(dict.fromkeys(values));fixture=BUILD/'words.txt';fixture.write_text('\n'.join(map(str,values))+'\n')
    observed=run([binary,'--gpu','off','--threads','1','--',fixture]);lines=observed['stdout'].splitlines();assert lines==list(map(str,values)),next(((i,a,b) for i,(a,b) in enumerate(zip(lines,map(str,values))) if a!=b),'wrong report count')
    assert before==[{'path':str(p),**fingerprint(p)} for p in paths]
    evidence={'status':'passed','source_identities':before,'kernel_laws':4,'kernel':proof,'export':export,'artifact':fingerprint(BUILD/'proof.bendtt'),'build':build,'native_cases':len(values),'native_seconds':observed['seconds'],'native_stdout_sha256':hashlib.sha256(observed['stdout'].encode()).hexdigest(),'fixture':fingerprint(fixture),'binary':fingerprint(binary),'scope':'Four actual production laws: exact zero/maximum spellings and complete accumulated suffix at the two termination boundaries. Native tests cover every word0..65535, decimal powers, unsigned extremes and8192 deterministic full-width words. No universal arithmetic roundtrip theorem is claimed.','reproduce':'python3 tools/u32_decimal_check.py --build'}
    write_json(ROOT/'evidence/u32_decimal.json',evidence);print(json.dumps({'status':'passed','laws':4,'native_cases':len(values),'seconds':observed['seconds']}))

if __name__=='__main__':main()
