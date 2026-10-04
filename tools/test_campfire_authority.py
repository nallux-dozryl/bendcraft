#!/usr/bin/env python3
"""Compile the actual Bend owner/loader and compare retained actual Java receivers."""
from __future__ import annotations
import copy,hashlib,json,os,re,shutil,signal,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'build/campfire-authority-native'
BEND=Path.home()/'.bend/bin/bend'
KERNEL=Path('/Users/chuah/.bend/bendtt/e15042434e73aab0/bendtt')
NODE=Path('/opt/homebrew/Cellar/node/23.5.0/bin/node')
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def run(tag,args,timeout=120,max_rss=2*1024**3):
    started=time.monotonic();peak=0;stop=None
    out=WORK/(tag+'.stdout');err=WORK/(tag+'.stderr')
    with out.open('w') as o,err.open('w') as e:
        p=subprocess.Popen(list(map(str,args)),cwd=ROOT,stdout=o,stderr=e,start_new_session=True)
        while p.poll() is None:
            table=[tuple(map(int,s.split())) for s in subprocess.check_output(['ps','-axo','pid,ppid,rss'],text=True).splitlines()[1:] if len(s.split())==3]
            owners={p.pid}
            for _ in range(6):owners.update(pid for pid,ppid,rss in table if ppid in owners)
            rss=sum(rss*1024 for pid,ppid,rss in table if pid in owners);peak=max(peak,rss)
            if rss>max_rss or time.monotonic()-started>timeout:
                stop='RSS bound' if rss>max_rss else 'time bound';os.killpg(p.pid,signal.SIGTERM)
                try:p.wait(5)
                except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
                break
            time.sleep(.2)
    row={'kind':tag,'command':list(map(str,args)),'exit':p.returncode,'seconds':round(time.monotonic()-started,4),'sampled_process_tree_peak_rss_bytes':peak,'bounded_stop':stop,'stdout_sha256':digest(out),'stderr_sha256':digest(err)}
    timing=re.search(r'(\d+)\s+maximum resident set size',err.read_text())
    if timing:row['peak_rss_bytes']=int(timing.group(1))
    (WORK/(tag+'.json')).write_text(json.dumps(row,indent=2)+'\n')
    assert p.returncode==0 and stop is None,(row,err.read_text()[-2500:],out.read_text()[-2500:])
    return row

def decoded_slot(slot,defaults):
    if slot is None:return None
    result=copy.deepcopy(slot);identity=result['components']
    if not identity:result['components']=defaults[result['id']]
    else:
        marker,limit,payload=identity.split('\t',2)
        assert marker=='BendCraftComponents1' and int(limit)>0
        result['components']=json.loads(payload)
        assert result['components'].get('minecraft:max_stack_size',1)==int(limit)
    return result

def aggregate(drops):
    result=[]
    for item in drops:
        if item is None:continue
        if result and item['id']==result[-1]['id'] and item['components']==result[-1]['components']:result[-1]['count']+=item['count']
        else:result.append(copy.deepcopy(item))
    return result

def normalize(cases,defaults,native):
    result=copy.deepcopy(cases)
    for case in result:
        for obs in case['observations']:
            obs.pop('xp_entities',None)
            if native:
                obs['state']['items']=[decoded_slot(s,defaults) for s in obs['state']['items']]
                obs['drops']=[decoded_slot(s,defaults) for s in obs['drops']]
                if 'held' in obs:obs['held']=decoded_slot(obs['held'],defaults)
            obs['drops']=aggregate(obs['drops'])
    return result

def main():
    WORK.mkdir(parents=True,exist_ok=True)
    files=[str(p.relative_to(ROOT)) for glob in ('src/campfire_authority*.bend','tests/campfire_authority*.bend','tools/*campfire_authority*') for p in ROOT.glob(glob)]
    files += ['reference/campfire_authority.json','src/cooking_recipe.bend','src/cooking_recipe_decoder.bend','src/crafting_recipe_components.bend','src/inventory.bend']
    pins={p:digest(ROOT/p) for p in files}
    ref=json.loads((ROOT/'reference/campfire_authority.json').read_text());assert ref['pin']=='26.3'
    inputs=ref['inputs'];(WORK/'input.json').write_text(json.dumps(inputs,separators=(',',':'))+'\n')
    defaults={v['id']:v['components'] for v in inputs['catalog']['items']}
    clang=shutil.which('clang') or '/usr/bin/clang'
    checks=[]
    try:
        checks.append(run('ordinary',[BEND,'tests/campfire_authority.bend','--check-only']))
        checks.append(run('proof-export',[NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=1536','tools/campfire_authority_proof.mjs',WORK]))
        selection=json.loads((WORK/'selection.json').read_text());scope=json.loads((WORK/'scope.json').read_text())
        assert scope['exclusions']==[] and selection['selected_root_count']==14 and selection['checked_types_and_bodies_unchanged'] and selection['all_original_tlds_ctrs_tmps_retained']
        checks.append(run('independent-kernel',['/usr/bin/env','LEAN_STACK_SIZE=4194304',KERNEL,WORK/'selected.bendtt']))
        assert (WORK/'independent-kernel.stdout').read_text().strip()=='ALL PROOFS CHECK'
        checks.append(run('emit',[BEND,'tests/campfire_authority.bend','-o',WORK/'receiver.c']))
        checks.append(run('clang',[clang,'-std=c11','-O3',WORK/'receiver.c','-lpthread','-lm','-o',WORK/'receiver']))
        native=run('native',['/usr/bin/time','-l',WORK/'receiver','--gpu','off','--threads','1',WORK/'input.json'],max_rss=1024**3)
        got=json.loads((WORK/'native.stdout').read_text());assert len(got['guards'])==12 and all(g['ok'] for g in got['guards']),got['guards'];expected=normalize(ref['observations']['cases'],defaults,False);actual=normalize(got['cases'],defaults,True)
        (WORK/'expected.json').write_text(json.dumps(expected,indent=2)+'\n');(WORK/'actual.json').write_text(json.dumps(actual,indent=2)+'\n')
        for a,b in zip(actual,expected):
            for i,(x,y) in enumerate(zip(a['observations'],b['observations'])):assert x==y,{'case':a['id'],'observation':i,'actual':x,'expected':y}
        assert actual==expected
        assert all(digest(ROOT/p)==h for p,h in pins.items()),'source changed during checks'
        evidence={'status':'passed','command':'python3 tools/test_campfire_authority.py','source_sha256':pins,'checks':checks,'native':native,'cases':len(expected),'actual_java_observations_compared':sum(len(c['observations']) for c in expected),'guard_cases':got['guards'],'initialized_item_definitions':len(defaults),'kernel_laws':14,'ordinary_laws':15,'scope_exclusions':[],'term_pins':selection['term_pins'],'kernel_sha256':digest(KERNEL),'selected_artifact_sha256':digest(WORK/'selected.bendtt'),'native_emitted_c_sha256':digest(WORK/'receiver.c'),'boundary':'Actual production affine Bend four-slot owner and loaded recipe/component/feature admission. Full effective components, cached recipe order, timers, dirty/update/change counts and aggregate ordered complete drop quantities compared to actual retained Java receiver. Actual Java drop fragmentation/positions/velocity/RNG belong to the actor world-drop adapter; no native entity spawning, NBT codec or Core integration claimed. No unchanged recipe-corpus or Java propagation replay.'}
        (ROOT/'evidence/campfire-authority-native.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps({k:evidence[k] for k in ('status','cases','actual_java_observations_compared','initialized_item_definitions','kernel_laws')}))
    except BaseException as e:
        (WORK/'failure.json').write_text(json.dumps({'error':repr(e),'checks':checks},indent=2)+'\n');raise
if __name__=='__main__':main()
