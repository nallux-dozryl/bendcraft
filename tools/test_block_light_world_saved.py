#!/usr/bin/env python3
"""Bootstrap actual saved Core section arrays; no Python light propagation."""
from __future__ import annotations
import hashlib,itertools,json,os,re,shutil,signal,subprocess,time
from pathlib import Path
import test_world_codec as WC
import test_nbt as N
import reference_block_light_probe as J
from reference_model_probe import verified_client_classpath,JAVA

ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'build/block-light-world-saved'
BEND=Path.home()/'.bend/bin/bend'
SAVE=ROOT/'build/playable-renderer-current/005/hidden-startup-003/fresh-world.nbt'
OWNED=('tests/block_light_world_saved.bend','tools/test_block_light_world_saved.py')
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def command(tag,args,timeout=60,env=None):
    started=time.monotonic()
    p=subprocess.run(list(map(str,args)),cwd=ROOT,capture_output=True,text=True,timeout=timeout,env=env)
    row={'kind':tag,'command':list(map(str,args)),'exit':p.returncode,
         'seconds':round(time.monotonic()-started,4),'stdout':p.stdout.strip(),'stderr':p.stderr.strip()}
    (WORK/(tag+'.json')).write_text(json.dumps(row,indent=2)+'\n')
    assert p.returncode==0,row
    return row
def checksum(key,cells):
    h=2166136261
    for c in key:h=((h^ord(c))*16777619)&0xffffffff
    for cell in cells:h=((h^cell)*16777619)&0xffffffff
    return h
def native(args):
    started=time.monotonic();peak=0;failure=None
    with (WORK/'native.stdout').open('w') as out,(WORK/'native.stderr').open('w') as err:
        p=subprocess.Popen(list(map(str,args)),cwd=ROOT,stdout=out,stderr=err,start_new_session=True)
        while p.poll() is None:
            rows=subprocess.run(['ps','-axo','pid,ppid,rss'],capture_output=True,text=True,check=True).stdout.splitlines()[1:]
            table=[tuple(map(int,line.split())) for line in rows if len(line.split())==3]
            owners={p.pid}
            for _ in range(4):owners.update(pid for pid,ppid,rss in table if ppid in owners)
            rss=sum(rss*1024 for pid,ppid,rss in table if pid in owners);peak=max(peak,rss)
            if rss>1024**3 or time.monotonic()-started>120:
                failure='sampledRSS exceeded1GiB' if rss>1024**3 else 'elapsed exceeded120seconds'
                os.killpg(p.pid,signal.SIGTERM)
                try:p.wait(5)
                except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
                break
            time.sleep(.25)
        row={'exit':p.returncode,'seconds':round(time.monotonic()-started,4),
             'sampled_process_tree_peak_rss_bytes':peak,'bounded_stop':failure,
             'stdout':(WORK/'native.stdout').read_text().strip(),
             'stderr':(WORK/'native.stderr').read_text().strip()}
    (WORK/'native.json').write_text(json.dumps(row,indent=2)+'\n')
    return row
def main():
    WORK.mkdir(parents=True,exist_ok=True)
    pin={p:digest(ROOT/p) for p in (*OWNED,'src/block_light_world.bend',
      'src/block_light_world_laws.bend','src/block_light_world_proof.bend','src/core.bend',
      'src/block_light.bend','src/section.bend','src/section_map_read.bend')}
    root=N.Reader(SAVE.read_bytes(),max_bytes=16846848,max_depth=6,max_elements=16846848).root()
    fields={WC.scalar_text(N.Value(8,key)):value for key,value in root.value.payload}
    core=N.parse(bytes(fields['core'].payload));cf=WC.fields(core.value,WC.ROOT_FIELDS)
    world=WC.validate(core,35723,WC.scalar_text(cf['registry']))
    assert len(world['sections'])==104 and not world['pending']
    assert all(e['kind']==0 for e in world['events'])
    request=J.inputs();request['states']['dirt']={'name':'dirt','properties':{}};request['scenarios']=[]
    (WORK/'inputs.json').write_text(json.dumps(request)+'\n')
    (WORK/'BlockLightReference.java').write_text(J.SOURCE)
    retained=ROOT/'reference/block_light_world_saved.json'
    previous=json.loads(retained.read_text()) if retained.exists() else None
    reuse=previous and (WORK/'output.json').exists() and previous['observations_sha256']==digest(WORK/'output.json') and previous['harness_sha256']==hashlib.sha256(J.SOURCE.encode()).hexdigest()
    if reuse:
        observed=json.loads((WORK/'java-properties-only.json').read_text())
        provenance=previous['classpath_provenance']
    else:
        paths,provenance=verified_client_classpath()
        observed=command('java-properties-only',[JAVA,'-Xmx512m','--source','25','--class-path',
          os.pathsep.join(map(str,paths)),WORK/'BlockLightReference.java',WORK/'inputs.json',WORK/'output.json'],90)
    raw=json.loads((WORK/'output.json').read_text());assert raw['version']=='26.3' and not raw['scenarios']
    props={p['id']:p for p in raw['properties']};assert props['dirt']['state']==10
    assert props['dirt']['emission']==0 and props['dirt']['dampening']==15
    closed=[{'from':props[e['from']]['state'],'to':props[e['to']]['state'],'direction':e['direction']}
            for e in raw['edges'] if e['closed']]
    reference={'pin':'26.3','settled_phases_rerun':0,'properties':raw['properties'],
      'directed_edges_observed':len(raw['edges']),'closed_edges':closed,
      'observations_sha256':digest(WORK/'output.json'),'classpath_provenance':provenance,
      'harness_sha256':hashlib.sha256(J.SOURCE.encode()).hexdigest(),
      'command':observed['command'],'boundary':'Narrow additional dirt/catalog query; unchanged31 settled-phase receiver evidence retained separately.'}
    (ROOT/'reference/block_light_world_saved.json').write_text(json.dumps(reference,indent=2)+'\n')
    args=[len(props)]
    for p in props.values():args += [p['state'],p['emission'],p['dampening']]
    args += [len(closed)]
    for e in closed:args += [e['from'],e['to'],e['direction']]
    args += [world['tick'],world['day_time'],int(world['paused']),int(world['daylight']),world['revision'],world['state_count'],len(world['sections'])]
    total=0;fingerprint=0
    for s in world['sections']:
        runs=[(len(list(group)),state) for state,group in itertools.groupby(s['cells'])]
        args += [s['key'],len(runs)]
        for n,state in runs:args += [n,state]
        total+=len(s['cells']);fingerprint ^= checksum(s['key'],s['cells'])
    args += [len(world['events'])]
    for e in world['events']:args += [*e['stamp'],e['revision']]
    assert total==425984
    args=list(map(str,args));(WORK/'receiver-inputs.json').write_text(json.dumps(args)+'\n')
    env=os.environ.copy();env['PATH']=str(ROOT/'.runtime/toolchains/lean-4.34.0-darwin_aarch64/bin')+os.pathsep+env['PATH']
    checks=[command('ordinary',[BEND,'tests/block_light_world_saved.bend','--check-only']),
      command('proof',[BEND,'src/block_light_world_proof.bend','--verdict'],env=env),
      command('emit',[BEND,'tests/block_light_world_saved.bend','-o',WORK/'receiver.c']),
      command('clang',[shutil.which('clang') or '/usr/bin/clang','-std=c11','-O3',WORK/'receiver.c','-lpthread','-lm','-o',WORK/'receiver'])]
    row=native(['/usr/bin/time','-l',WORK/'receiver','--gpu','off','--threads','1','--',*args])
    summary=f'104/425984/{fingerprint}'
    old=json.loads((ROOT/'reference/block_light.json').read_text())
    seed=next(s for s in old['inputs']['scenarios'] if s['id']=='partial_complementary')
    oracle=next(s for s in old['observations']['scenarios'] if s['id']==seed['id'])['phases'][0]
    blocks={tuple(p):0 for p in seed['domain']}
    for w in seed['phases'][0]['writes']:blocks[tuple(w['position'])]=props[w['state']]['state']
    seed_cells=' '.join(f'{blocks[tuple(p)]}:{level}' for p,level in zip(seed['domain'],oracle['levels']))+' ?:?'
    disabled=' '.join(f'{blocks[tuple(p)]}:0' for p in seed['domain'])+' ?:?'
    want='\n'.join(('seed_pending refused','seed stable 0/0 '+seed_cells,
      'disabled stable 0/0 '+disabled,
      f'{summary} {summary} {world["tick"]}/{world["day_time"]}/{world["revision"]}/0 425984',
      f'stable {world["tick"]}/{world["revision"]}',
      f'add stable {world["tick"]}/{world["revision"]+1} 4926:14 0:13 0:13 ?:?',
      f'remove stable {world["tick"]}/{world["revision"]+2} 0:0 0:0 0:0 ?:?'))
    lines=[line.rstrip() for line in row['stdout'].splitlines()]
    timing=[int(line.split()[1]) for line in lines if line.startswith('bootstrap_ms ')]
    row['bootstrap_ms']=timing[0] if len(timing)==1 else None
    passed=row['exit']==0 and len(timing)==1 and '\n'.join(line for line in lines if not line.startswith('bootstrap_ms '))==want
    peak=re.search(r'(\d+)\s+maximum resident set size',row['stderr'])
    if peak:row['peak_rss_bytes']=int(peak.group(1))
    evidence={'status':'passed' if passed else 'failed','command':'python3 tools/test_block_light_world_saved.py',
      'source_sha256':pin,'actual_save':str(SAVE.relative_to(ROOT)),'actual_save_sha256':digest(SAVE),
      'actual_save_core_bytes_sha256':hashlib.sha256(bytes(fields['core'].payload)).hexdigest(),
      'sections':104,'cells':425984,'catalog_properties_observed':len(props),'java_settled_phases_rerun':0,
      'checks':checks,'native':row,'expected_stdout':want,'full_bootstrap_passed':passed,
      'java_catalog_query_reused':bool(reuse),'bootstrap_initial_emitter_java_sample_pairs':25,
      'bootstrap_disabled_sample_pairs':25,'post_saved_world_edit_samples':8,
      'boundary':'Actual104 saved section scalar IDs independently decoded, losslessly run-length input to actual Bend-owned Section arrays/Core.World, then production bootstrap; no Python light implementation. Count/checksum/clock retention, settled nonemitting initialization, add/remove actual Core edits/revisions and explicit unknowns tested. New preexisting-emitter initialization compares25 retained Java partial-occlusion phase samples; disabled emission tests actual Core IDs with zero effective light. No replay of unchanged propagation corpus. This receiver does not claim persistence parser adoption, complete event equality, sky light, or actual actor/frame entry wiring.'}
    (ROOT/'evidence/block-light-world-saved.json').write_text(json.dumps(evidence,indent=2)+'\n')
    assert all(digest(ROOT/p)==h for p,h in pin.items()),'owned sources changed'
    assert passed,evidence
    print(json.dumps({'status':'passed','sections':104,'cells':425984,'seconds':row['seconds'],
      'sampled_rss':row['sampled_process_tree_peak_rss_bytes'],'peak_rss':row.get('peak_rss_bytes')}))
if __name__=='__main__':main()
