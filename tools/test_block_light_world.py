#!/usr/bin/env python3
"""Actual Core-owned lighting bridge; reuse retained Java26.3 observations."""
from __future__ import annotations
import hashlib,json,os,re,shutil,subprocess,time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'build/block-light-world'
BEND=Path.home()/'.bend/bin/bend'
FILES=('src/block_light_world.bend','src/block_light_world_laws.bend',
       'src/block_light_world_proof.bend','tests/block_light_world_receiver.bend',
       'tools/test_block_light_world.py','docs/BLOCK_LIGHT.md')
def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def run(kind,args,timeout=60,env=None):
    started=time.monotonic()
    p=subprocess.run(list(map(str,args)),cwd=ROOT,capture_output=True,text=True,timeout=timeout,env=env)
    row={'kind':kind,'command':list(map(str,args)),'seconds':round(time.monotonic()-started,4),
         'exit':p.returncode,'stdout':p.stdout.strip(),'stderr':p.stderr.strip()}
    (WORK/(kind+'.json')).write_text(json.dumps(row,indent=2)+'\n')
    assert p.returncode==0,row
    return p.stdout,row
def request(reference,scenario,budget):
    properties={p['id']:p for p in reference['observations']['properties']}
    edges=[e for e in reference['observations']['edges'] if e['closed']]
    args=[budget,len(properties)]
    for p in properties.values():args += [p['state'],p['emission'],p['dampening']]
    args.append(len(edges))
    for e in edges:args += [properties[e['from']]['state'],properties[e['to']]['state'],e['direction']]
    args.append(len(scenario['domain']))
    for pos in scenario['domain']:args += [x & 0xffffffff for x in pos]
    args.append(len(scenario['phases']))
    for phase in scenario['phases']:
        args.append(len(phase['writes']))
        for w in phase['writes']:
            assert w['state']!='unloaded','Core has no cell/section eviction operation'
            args += [x & 0xffffffff for x in w['position']]
            args.append(properties[w['state']]['state'])
    return list(map(str,args))
def main():
    WORK.mkdir(parents=True,exist_ok=True)
    reference=json.loads((ROOT/'reference/block_light.json').read_text())
    assert reference['pin']=='26.3'
    assert reference['observations_sha256']==hashlib.sha256(json.dumps(
        reference['observations'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
    initial_hash={p:digest(ROOT/p) for p in FILES}
    clang=shutil.which('clang') or '/usr/bin/clang'
    env=os.environ.copy()
    env['PATH']=str(ROOT/'.runtime/toolchains/lean-4.34.0-darwin_aarch64/bin')+os.pathsep+env['PATH']
    processes=subprocess.run(['ps','-axo','pid,ppid,rss,command'],capture_output=True,text=True,check=True)
    occupied=[]
    for line in processes.stdout.splitlines():
        fields=line.split(None,3)
        if len(fields)!=4 or not fields[2].isdigit():continue
        if not re.search(r'(/\.bend/bin/bend|bend2/main\.ts|clang .*minecraft|BlockLightReference\.java)',fields[3]):continue
        if any(x in fields[3] for x in ('ps -axo','/bin/zsh -lc','python3 - <<')):continue
        if int(fields[2])>=512*1024 or ' -o ' in fields[3] or 'clang ' in fields[3]:occupied.append(line)
    (WORK/'launch-processes.txt').write_text('\n'.join(occupied)+'\n')
    assert len(occupied)<2,occupied
    checks=[]
    for kind,args in (
        ('ordinary',[BEND,'tests/block_light_world_receiver.bend','--check-only']),
        ('proof',[BEND,'src/block_light_world_proof.bend','--verdict']),
        ('emit',[BEND,'tests/block_light_world_receiver.bend','-o',WORK/'receiver.c']),
        ('native',[clang,'-std=c11','-O3',WORK/'receiver.c','-lpthread','-lm','-o',WORK/'receiver'])):
        out,row=run(kind,args,60,env)
        if kind=='proof':assert out.strip()=='ALL PROOFS CHECK',row
        checks.append(row)
    scenarios=[s for s in reference['inputs']['scenarios'] if s['id']!='resident_boundary']
    expected={s['id']:s for s in reference['observations']['scenarios']}
    prop={p['id']:p['state'] for p in reference['observations']['properties']}
    rows=[]
    for scenario in scenarios:
        args=request(reference,scenario,64)
        out,row=run(scenario['id'],[WORK/'receiver','--gpu','off','--threads','1','--',*args],45)
        lines=out.splitlines()
        assert len(lines)==len(scenario['phases']),(scenario['id'],out)
        cells={tuple(p):prop['air'] for p in scenario['domain']}
        for phase,want,line in zip(scenario['phases'],expected[scenario['id']]['phases'],lines):
            for w in phase['writes']:cells[tuple(w['position'])]=prop[w['state']]
            status,clock,*samples=line.split()
            assert status=='stable' and clock=='0/0',(scenario['id'],phase['id'],line)
            actual=[tuple(map(int,p.split(':'))) for p in samples]
            desired=[(cells[tuple(p)],level) for p,level in zip(scenario['domain'],want['levels'])]
            assert actual==desired,(scenario['id'],phase['id'],actual,desired)
            rows.append({'scenario':scenario['id'],'phase':phase['id'],'samples':len(actual),
                         'actual_core_ids_and_java_levels_sha256':hashlib.sha256(json.dumps(actual).encode()).hexdigest()})
    out,guards=run('core-owner-and-schedule-guards',[WORK/'receiver','--gpu','off','--threads','1','--','guards'],30)
    assert [line.rstrip() for line in out.splitlines()]==[
        'permission invalid catalog duplicate missing',
        'accepted catalog accepted refused stable 1/1 4926:14 ?:?'],guards
    args=request(reference,scenarios[-1],64)
    out,resource=run('native-resource',['/usr/bin/time','-l',WORK/'receiver','--gpu','off','--threads','1','--',*args],45)
    peak=re.search(r'(\d+)\s+maximum resident set size',resource['stderr'])
    assert peak,resource
    resource_summary={'command':'python3 tools/test_block_light_world.py','fixture':scenarios[-1]['id'],
        'peak_rss_bytes':int(peak.group(1)),'seconds':resource['seconds'],
        'raw_log':'build/block-light-world/native-resource.json',
        'boundary':'Bounded real Core arrays plus joined light native receiver; not world-scale latency or long-session leak evidence.'}
    assert resource_summary['peak_rss_bytes']<256*1024*1024,resource_summary
    evidence={'status':'passed','pin':'26.3','command':'python3 tools/test_block_light_world.py',
      'source_sha256':initial_hash,'core_sha256':digest(ROOT/'src/core.bend'),
      'section_map_read_sha256':digest(ROOT/'src/section_map_read.bend'),
      'reference_sha256':digest(ROOT/'reference/block_light.json'),'checks':checks,
      'java_receiver_rerun':False,'java_phases_reused':len(rows),
      'actual_core_block_and_java_light_sample_pairs':sum(r['samples'] for r in rows),
      'observations':rows,'guards':guards,'native_resource':resource_summary,
      'boundary':'Actual Core.World/Section arrays bootstrap, reads, edit acceptance, permission admission, due-step clock/events and Stable batch reads. General descriptors/directional edges are inputs from unchanged Java26.3 observations. Outside fixture cells are actual opaque nonemitting stone sections, equivalent to oracle bedrock for these light paths. Core has no unload operation: resident_boundary phase excluded explicitly. Nine bridge laws independently kernel checked. Actor/resource-frame entry wiring, sky light, world-scale performance and compact storage remain outside this lane.'}
    assert all(digest(ROOT/p)==h for p,h in initial_hash.items()),'owned sources changed during check'
    (ROOT/'evidence/block-light-world-native.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps({'status':evidence['status'],'phases':len(rows),
                      'actual_core_and_java_samples':evidence['actual_core_block_and_java_light_sample_pairs'],
                      'native_peak_rss':resource_summary['peak_rss_bytes']}))
if __name__=='__main__':main()
