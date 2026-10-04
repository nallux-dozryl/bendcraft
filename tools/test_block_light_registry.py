#!/usr/bin/env python3
"""Run real Bend authenticated loader and compare every pinned Java state/face."""
from __future__ import annotations
import hashlib,json,os,re,shutil,signal,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'build/block-light-registry-check'
BEND=Path.home()/'.bend/bin/bend'
FILES=('src/block_light_registry.bend','src/block_light_registry_decoder.bend',
 'src/block_light_registry_loader.bend','src/block_light_registry_laws.bend',
 'src/block_light_registry_proof.bend','tests/block_light_registry.bend',
 'tools/test_block_light_registry.py','reference/block_light_registry.tsv',
 'reference/block_light_registry.json','src/block_light.bend','src/hash.bend','src/unicode.bend')
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def run(tag,args,env=None,timeout=120,max_rss=2*1024**3):
    started=time.monotonic();peak=0;stop=None
    out=WORK/(tag+'.stdout');err=WORK/(tag+'.stderr')
    with out.open('w') as o,err.open('w') as e:
        p=subprocess.Popen(list(map(str,args)),cwd=ROOT,stdout=o,stderr=e,env=env,start_new_session=True)
        while p.poll() is None:
            lines=subprocess.run(['ps','-axo','pid,ppid,rss'],capture_output=True,text=True,check=True).stdout.splitlines()[1:]
            table=[tuple(map(int,s.split())) for s in lines if len(s.split())==3]
            owners={p.pid}
            for _ in range(5):owners.update(pid for pid,ppid,rss in table if ppid in owners)
            rss=sum(rss*1024 for pid,ppid,rss in table if pid in owners);peak=max(peak,rss)
            if rss>max_rss or time.monotonic()-started>timeout:
                stop='RSS bound' if rss>max_rss else 'time bound'
                os.killpg(p.pid,signal.SIGTERM)
                try:p.wait(5)
                except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
                break
            time.sleep(.2)
    row={'kind':tag,'command':list(map(str,args)),'exit':p.returncode,
      'seconds':round(time.monotonic()-started,4),'sampled_process_tree_peak_rss_bytes':peak,
      'bounded_stop':stop,'stdout_sha256':digest(out),'stderr_sha256':digest(err)}
    timing=re.search(r'(\d+)\s+maximum resident set size',err.read_text())
    if timing:row['peak_rss_bytes']=int(timing.group(1))
    (WORK/(tag+'.json')).write_text(json.dumps(row,indent=2)+'\n')
    assert p.returncode==0 and stop is None,(row,err.read_text()[-3000:],out.read_text()[-3000:])
    return row

def main():
    WORK.mkdir(parents=True,exist_ok=True)
    pins={p:digest(ROOT/p) for p in FILES}
    reference=json.loads((ROOT/'reference/block_light_registry.json').read_text())
    assert reference['table_sha256']==pins['reference/block_light_registry.tsv']
    states=[]
    for start,size,*properties in reference['ranges']:
        assert start==len(states)
        states += [[i,*properties] for i in range(start,start+size)]
    assert len(states)==reference['state_count']
    raw=ROOT/'build/block-light-registry/registry-output.json'
    raw_checked=False
    if raw.exists():
        assert digest(raw)==reference['observations_sha256']
        observed=json.loads(raw.read_text())
        assert states==observed['states'] and reference['matrix_rows']==observed['matrix_rows']
        raw_checked=True
    env=os.environ.copy();env['PATH']=str(ROOT/'.runtime/toolchains/lean-4.34.0-darwin_aarch64/bin')+os.pathsep+env['PATH']
    clang=shutil.which('clang') or '/usr/bin/clang'
    checks=[run('ordinary',[BEND,'tests/block_light_registry.bend','--check-only']),
      run('proof',[BEND,'src/block_light_registry_proof.bend','--verdict'],env=env),
      run('emit',[BEND,'tests/block_light_registry.bend','-o',WORK/'receiver.c']),
      run('clang',[clang,'-std=c11','-O3',WORK/'receiver.c','-lpthread','-lm','-o',WORK/'receiver'])]
    row=run('native',['/usr/bin/time','-l',WORK/'receiver','--gpu','off','--threads','1'],max_rss=1024**3)
    got=(WORK/'native.stdout').read_text().splitlines()
    guards=[s for s in got if s.startswith('guard ')]
    assert len(guards)==23,guards
    assert all(s.split()[-1].split('/')[0]==s.split()[-1].split('/')[1] for s in guards),guards
    expected=[f"meta {len(states)} {reference['shape_count']}"]
    matrix=reference['matrix_rows'];n=reference['shape_count']
    def closed(a,b):return (matrix[a][b//32]>>(b%32))&1
    opposite=(1,0,3,2,5,4)
    for s in states:
        i=s[0];target=states[(i*7919+13)%len(states)]
        edges=''.join(str(closed(s[3+d],target[3+opposite[d]])) for d in range(6))
        expected.append('S '+' '.join(map(str,s))+' '+edges)
    for i in range(n):expected.append(f'F {i} '+''.join(str(closed(i,j)) for j in range(n)))
    expected += ['outside ? ? ? ? ?','closed 1']
    actual=[s for s in got if not s.startswith('guard ')]
    if actual!=expected:
        mismatch=next((i for i,(a,b) in enumerate(zip(actual,expected)) if a!=b),min(len(actual),len(expected)))
        raise AssertionError({'row':mismatch,'actual':actual[mismatch:mismatch+2],'expected':expected[mismatch:mismatch+2],
                              'actual_rows':len(actual),'expected_rows':len(expected)})
    proof=(WORK/'proof.stdout').read_text();assert 'ALL PROOFS CHECK' in proof,proof[-3000:]
    assert all(digest(ROOT/p)==h for p,h in pins.items()),'sources changed during checks'
    evidence={'status':'passed','command':'python3 tools/test_block_light_registry.py','source_sha256':pins,
      'checks':checks,'native':row,'state_property_and_six_face_rows_compared':len(states),
      'directed_composed_occlusion_queries_compared':6*len(states),'exact_unique_face_pairs_compared':n*n,
      'guard_cases':guards,'kernel_laws':11,'raw_java_observations_compared':raw_checked,
      'java_settled_phases_rerun':0,'native_emitted_c_sha256':digest(WORK/'receiver.c'),
      'expected_stdout_sha256':hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest(),
      'boundary':'Actual production Bend authenticated file loader, contiguous full-registry decoder, descriptor/face providers, packed matrix and source-to-target opposite-face composition. Independent retained Java cached state/face observations; no Python runtime provider or lighting algorithm. Native resource/read/ownership checks remain distinct from11 independent-kernel laws. Actor/frame adoption remains lead-owned; sky light is outside this block-light provider.'}
    (ROOT/'evidence/block-light-registry-provider.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps({k:evidence[k] for k in ('status','state_property_and_six_face_rows_compared',
      'directed_composed_occlusion_queries_compared','exact_unique_face_pairs_compared','kernel_laws')}))
if __name__=='__main__':main()
