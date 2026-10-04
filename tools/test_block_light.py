#!/usr/bin/env python3
"""Native production block-light parity against installed Java26.3 receiver."""
from __future__ import annotations
import hashlib,json,os,re,shutil,subprocess,time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
BEND=Path.home()/'.bend/bin/bend'
WORK=ROOT/'build/block-light-native'
REFERENCE=ROOT/'reference/block_light.json'
FILES=('src/block_light.bend','src/block_light_laws.bend','src/block_light_proof.bend',
       'tests/block_light_receiver.bend','tools/test_block_light.py')

def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def command(args,kind,timeout=60,env=None):
    started=time.monotonic()
    result=subprocess.run(list(map(str,args)),cwd=ROOT,capture_output=True,text=True,
                          timeout=timeout,env=env)
    row={'kind':kind,'command':list(map(str,args)),'exit':result.returncode,
         'seconds':round(time.monotonic()-started,4),'stdout':result.stdout.strip(),
         'stderr':result.stderr.strip()}
    (WORK/(kind+'.json')).write_text(json.dumps(row,indent=2)+'\n')
    assert result.returncode==0,row
    return result.stdout,row

def request(reference,scenario,budget,dimension='minecraft:overworld'):
    properties={p['id']:p for p in reference['observations']['properties']}
    edges=[e for e in reference['observations']['edges'] if e['closed']]
    args=[budget,dimension,len(edges)]
    for edge in edges:
        args += [properties[edge['from']]['state'],properties[edge['to']]['state'],edge['direction']]
    args.append(len(scenario['domain']))
    for position in scenario['domain']:args += [v & 0xffffffff for v in position]
    args.append(len(scenario['phases']))
    for phase in scenario['phases']:
        args.append(len(phase['writes']))
        for write in phase['writes']:
            args += [v & 0xffffffff for v in write['position']]
            if write['state']=='unloaded':args += [0,0,0,'unload']
            else:
                p=properties[write['state']]
                args += [p['state'],p['emission'],p['dampening'],'publish']
    return list(map(str,args))

def resource_summary(check,args,output):
    return {'kind':check['kind'],'exit':check['exit'],'seconds':check['seconds'],
            'fixture':'six_directions','budget':1,'peak_rss_bytes':check['peak_rss_bytes'],
            'arguments_sha256':hashlib.sha256(json.dumps(args).encode()).hexdigest(),
            'output_sha256':hashlib.sha256(output.encode()).hexdigest(),
            'reproduce':'python3 tools/test_block_light.py',
            'raw_log':'build/block-light-native/native-resource.json',
            'boundary':'Bounded CPU native receiver RSS; not world-scale memory or long-session leak evidence.'}

def main():
    WORK.mkdir(parents=True,exist_ok=True)
    reference=json.loads(REFERENCE.read_text())
    assert reference['pin']=='26.3' and reference['observations']['state_count']==35723
    assert reference['observations_sha256']==hashlib.sha256(
        json.dumps(reference['observations'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
    sources={name:digest(ROOT/name) for name in FILES}
    # Resolve host clang before adding Lean's bundled toolchain to PATH.
    clang=shutil.which('clang') or '/usr/bin/clang'
    env=os.environ.copy()
    env['PATH']=str(ROOT/'.runtime/toolchains/lean-4.34.0-darwin_aarch64/bin')+os.pathsep+env['PATH']
    snapshot=subprocess.run(['ps','-axo','pid,ppid,rss,command'],capture_output=True,text=True,check=True)
    active=[]
    for line in snapshot.stdout.splitlines():
        if not re.search(r'(/\.bend/bin/bend|bend2/main\.ts|clang .*minecraft|BlockLightReference\.java)',line):continue
        if any(skip in line for skip in ('ps -axo','python3 - <<','/bin/zsh -lc')):continue
        fields=line.split(None,3)
        if len(fields)!=4 or not fields[2].isdigit():continue
        # Brief narrow ordinary/proof checks are not heavy jobs. Count actual
        # large compiler processes plus emitters/native builds/Java receivers.
        if int(fields[2])>=512*1024 or ' -o ' in fields[3] or 'BlockLightReference.java' in fields[3] or 'clang ' in fields[3]:
            active.append(line)
    (WORK/'launch-processes.txt').write_text('\n'.join(active)+'\n')
    assert len(active)<2,('shared two-heavy-job bound occupied',active)
    checks=[]
    for kind,args in (
        ('ordinary',[BEND,'tests/block_light_receiver.bend','--check-only']),
        ('proof',[BEND,'src/block_light_proof.bend','--verdict']),
        ('emit',[BEND,'tests/block_light_receiver.bend','-o',WORK/'receiver.c']),
        ('native',[clang,'-std=c11','-O3',WORK/'receiver.c','-lpthread','-lm','-o',WORK/'receiver'])):
        output,row=command(args,kind,60,env)
        if kind=='proof':assert output.strip()=='ALL PROOFS CHECK',row
        checks.append(row)
    rows=[]
    observed={s['id']:s for s in reference['observations']['scenarios']}
    for scenario in reference['inputs']['scenarios']:
        expected_phases=observed[scenario['id']]['phases']
        for budget in (1,7,64):
            args=request(reference,scenario,budget)
            # This file contains inputs only; Java's expected light levels are
            # confined to the Python comparison, never sent to the executable.
            tag=f'{scenario["id"]}-budget-{budget}'
            (WORK/(tag+'-inputs.json')).write_text(json.dumps(args)+'\n')
            output,row=command([WORK/'receiver','--gpu','off','--threads','1','--',*args],tag,30)
            lines=output.splitlines()
            assert len(lines)==len(expected_phases),(tag,len(lines),len(expected_phases),output)
            resident={tuple(p):True for p in scenario['domain']}
            for input_phase,expected,line in zip(scenario['phases'],expected_phases,lines):
                for write in input_phase['writes']:
                    resident[tuple(write['position'])]=write['state']!='unloaded'
                status,*values=line.split()
                actual=[None if value=='?' else int(value) for value in values]
                want=[value if resident[tuple(position)] else None
                      for position,value in zip(scenario['domain'],expected['levels'])]
                assert status=='stable',(tag,input_phase['id'],status)
                assert len(actual)==len(scenario['domain']),(tag,len(actual))
                assert actual==want,(tag,input_phase['id'],actual,want)
                assert all(value is None or 0<=value<=15 for value in actual)
                rows.append({'scenario':scenario['id'],'phase':input_phase['id'],'budget':budget,
                             'samples':len(actual),'unknown':actual.count(None),
                             'levels_sha256':hashlib.sha256(json.dumps(actual).encode()).hexdigest()})
    output,guard_check=command([WORK/'receiver','--gpu','off','--threads','1','--','guards'],'owner-guards',15)
    assert output.split()==['stable','14','15','13','14','14','0','0'],guard_check
    # The real owner survives all resumptions and rejected edits. Capture the
    # host/native resource check independently of source/kernel claims.
    args=request(reference,reference['inputs']['scenarios'][-1],1)
    output,resource_check=command(['/usr/bin/time','-l',WORK/'receiver','--gpu','off','--threads','1','--',*args],
                                  'native-resource',30)
    peak=re.search(r'(\d+)\s+maximum resident set size',resource_check['stderr'])
    assert peak,resource_check
    resource_check['peak_rss_bytes']=int(peak.group(1))
    assert resource_check['peak_rss_bytes']<128*1024*1024,resource_check
    evidence={'status':'passed','pin':'26.3','command':'python3 tools/test_block_light.py',
              'source_sha256':sources,'reference_sha256':digest(REFERENCE),
              'checks':checks,'scenarios':len(reference['inputs']['scenarios']),
              'java_phases':sum(len(s['phases']) for s in reference['inputs']['scenarios']),
              'budget_variants':[1,7,64],'native_phase_comparisons':len(rows),
              'native_sample_comparisons':sum(r['samples'] for r in rows),
              'native_unknown_samples':sum(r['unknown'] for r in rows),
              'native_owner_guards':guard_check,'native_resource':resource_summary(resource_check,args,output),
              'observations':rows,
              'boundary':'Actual Bend State/publish/unload/advance/sample, CPU native; no Python propagation. Exact Java-observed shape callback inputs for selected arbitrary registry states. Settled fields compared; transient ordering and queue work counts differ. Eight implementation laws independently checked; no universal convergence or whole-world/sky-light/shading claim. No foreign lighting or GUI.'}
    (ROOT/'evidence/block-light-native.json').write_text(json.dumps(evidence,indent=2)+'\n')
    assert all(digest(ROOT/name)==value for name,value in sources.items()),'sources changed during checks'
    print(json.dumps({key:evidence[key] for key in ('status','scenarios','java_phases','native_phase_comparisons','native_sample_comparisons')}))

if __name__=='__main__':main()
