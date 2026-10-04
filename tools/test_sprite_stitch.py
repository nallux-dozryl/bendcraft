#!/usr/bin/env python3
"""Bend static packing vs actual pinned official Stitcher, with retained fixtures."""
from __future__ import annotations
import argparse, copy, datetime, hashlib, json, os, re, subprocess, time
from pathlib import Path
import reference_sprite_stitch_probe as REF

ROOT=REF.ROOT;BEND=Path.home()/'.bend/bin/bend';BUILD=ROOT/'build/sprite-stitch';BIN=ROOT/'build/sprite-stitch-tests'
ENV={**os.environ,'BEND_MINECRAFT_LAUNCH_MODE':'hidden'}
def sha(b):return hashlib.sha256(b).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,sort_keys=True,indent=2)+'\n')
def u32(x):return x&0xffffffff
def words(v):
    if isinstance(v,dict):return{k:words(x)for k,x in v.items()}
    if isinstance(v,list):return[words(x)for x in v]
    if type(v)is int:return u32(v)
    return v
def fingerprint():
    pending=[ROOT/'tests/sprite_stitch.bend'];seen={}
    while pending:
        p=pending.pop().resolve()
        if p in seen:continue
        b=p.read_bytes();seen[p]=sha(b)
        pending.extend(p.parent/x for x in re.findall(r'^import\s+(\.\.?/\S+\.bend)',b.decode(),re.M))
    return {**{str(p.relative_to(ROOT)):s for p,s in seen.items()},'compiler_sha256':sha(BEND.read_bytes())}
def extras(base):
    cases=[];expected={}
    def add(name,change,code=None,recover=False):
        c=copy.deepcopy(base);c.update(id=name,**change);c['recover']=recover;cases.append(c);expected[name]=code
    add('policy_entry_limit',{'max_entries':0},'EntryLimit',True)
    add('policy_exact_entry_limit',{'max_entries':1})
    add('policy_identifier_limit',{'max_id_codepoints':4},'IdentifierLimit',True)
    add('policy_exact_identifier_limit',{'max_id_codepoints':11})
    add('policy_atlas_zero',{'max_width':0},'AtlasRange',True)
    add('policy_atlas_upper',{'max_width':536870913},'AtlasRange',True)
    add('policy_atlas_negative',{'max_height':0xffffffff},'AtlasRange',True)
    add('policy_mip_25',{'mip_level':25},'MipRange',True)
    add('policy_mip_negative',{'mip_level':0xffffffff},'MipRange',True)
    add('policy_holder_padding_upper',{'mip_level':24,'padding_setting':5},'HolderRange',True)
    add('policy_entry_zero',{'entries':[dict(base['entries'][0],width=0)]},'EntryRange')
    add('policy_entry_negative',{'entries':[dict(base['entries'][0],width=0xffffffff)]},'EntryRange')
    add('policy_entry_upper',{'entries':[dict(base['entries'][0],height=536870913)]},'EntryRange')
    add('policy_empty_upper_mip',{'entries':[],'mip_level':24,'padding_setting':5})
    return cases,expected
def prepare_data(ref):
    cases=[]
    for c in ref['inputs']['cases']:
        c=words(c);c.update(mode='pack',recover=c['domain']=='admitted');cases.append(c)
    cases.extend(dict(words(c),mode='raw')for c in ref['inputs']['raw_cases'])
    more,expected=extras(next(c for c in cases if c['id']=='one'));cases.extend(more)
    return cases,expected
def generation(ref,cases):
    return {'native_sources':fingerprint(),'runner_sha256':sha(Path(__file__).read_bytes()),'reference_sha256':sha(REF.OUT.read_bytes()),'reference_observation_sha256':ref['observation_sha256'],'inputs_sha256':sha(REF.canonical(cases))}
def prepare(ref,cases):
    BUILD.mkdir(parents=True,exist_ok=True);files=[]
    for i in range(0,len(cases),32):
        p=BUILD/f'cases-{i//32:03d}.json';write(p,cases[i:i+32]);files.append({'path':str(p.relative_to(ROOT)),'sha256':sha(p.read_bytes()),'cases':len(cases[i:i+32])})
    v={'schema':1,**generation(ref,cases),'files':files};v['seal_sha256']=sha(REF.canonical(v));write(BUILD/'preparation.json',v);return v
def retained(ref,cases):
    p=BUILD/'preparation.json'
    if not p.is_file():raise RuntimeError('Missing preparation; run explicit --prepare-only')
    v=json.loads(p.read_text());check=copy.deepcopy(v);seal=check.pop('seal_sha256')
    if sha(REF.canonical(check))!=seal:raise RuntimeError('Preparation seal differs')
    if any(v[k]!=x for k,x in generation(ref,cases).items()):raise RuntimeError('Stale preparation; run explicit --prepare-only')
    loaded=[]
    for item in v['files']:
        path=ROOT/item['path']
        if not path.is_file()or sha(path.read_bytes())!=item['sha256']:raise RuntimeError('Prepared case file missing/changed: '+str(path))
        loaded.extend(json.loads(path.read_text()))
    if loaded!=cases:raise RuntimeError('Prepared semantic cases differ')
    return v
def run(cmd,timeout=60):
    p=subprocess.run(list(map(str,cmd)),cwd=ROOT,env=ENV,capture_output=True,text=True,timeout=timeout)
    if p.returncode:raise RuntimeError((cmd,p.returncode,p.stdout[-5000:],p.stderr[-5000:]))
    return p
def observed(ref):return{x['id']:x['result']for x in ref['observations']['cases']}
def check_layout(actual,expected,config):
    for k in ['width','height','padding','sorted','placements']:assert actual[k]==words(expected[k]),(k,actual[k],words(expected[k]))
    hs={x['tag']:x for x in expected['sorted']};ps=expected['placements']
    complete=len(ps)==len(expected['sorted'])and 0<=expected['width']<=config['max_width']and 0<=expected['height']<=config['max_height']
    for p in ps:
        h=hs[p['tag']];complete=complete and 0<=p['x']and 0<=p['y']and p['x']+h['padded_width']<=expected['width']and p['y']+h['padded_height']<=expected['height']
    assert actual['complete_within']==complete,('complete_within',actual['complete_within'],complete)
    # Independent rectangle laws do not choose placements; official callback
    # placements remain the only oracle. Test padded extents, not content only.
    for i,a in enumerate(ps):
        ah=hs[a['tag']]
        for b in ps[i+1:]:
            bh=hs[b['tag']]
            assert a['x']+ah['padded_width']<=b['x']or b['x']+bh['padded_width']<=a['x']or a['y']+ah['padded_height']<=b['y']or b['y']+bh['padded_height']<=a['y'],('overlap',a,b)
    for h in expected['sorted']:
        assert h['padded_width']%(1<<config['mip_level'])==0 and h['padded_height']%(1<<config['mip_level'])==0
    return complete
def policy_code(c):
    if not 0<c['max_width']<=536870912 or not 0<c['max_height']<=536870912:return 'AtlasRange'
    if not 0<=c['mip_level']<=24:return 'MipRange'
    for e in c['entries']:
        if not 0<e['width']<=536870912 or not 0<e['height']<=536870912:return 'EntryRange'
        # Outside rows are deliberately rejected before using Java's corrupted
        # signed rectangle geometry; holder overflow is separate from EntryRange.
        if e['width']+2*(1<<c['mip_level'])>536870912 or e['height']+2*(1<<c['mip_level'])>536870912:return 'HolderRange'
    raise AssertionError('No declared policy rejection for '+c['id'])
def check_status(a,e,c):
    if e['status']=='ok':
        assert a['status']=='ok',(c['id'],a,e)
        return check_layout(a['packed'],e,c)
    assert e['exception']=='net.minecraft.client.renderer.texture.StitcherException',e
    assert a['status']=='error'and a['code']=='NoSpace',(c['id'],a,e)
    check_layout(a['partial'],e,c)
    assert [x['tag']for x in e['sorted']]==e['exception_sorted_tags']
    candidates=[x for x in e['sorted']if f"{x['namespace']}:{x['path']} - size: {x['width']}x{x['height']}"in e['message']]
    assert candidates,'Cannot identify actual failure diagnostic'
    assert a['tag']in[x['tag']for x in candidates],('failure tag',a,e)
    return False
def native(manifest):
    rows=[];timings={};forced={}
    for f in manifest['files']:
        p=run([BIN,'--threads','1',ROOT/f['path']],90)
        for line in p.stdout.splitlines():
            if line.startswith('time|'):
                _,key,v=line.split('|');timings[key]=int(v)
            elif line.startswith('force|'):
                _,key,v=line.split('|');forced[key]=int(v)
            else:
                row=json.loads(line);assert forced[row['id']]==len(line),('forced serialized length',row['id']);rows.append(row)
    return rows,timings
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--prepare-only',action='store_true');ap.add_argument('--skip-kernel',action='store_true');ap.add_argument('--build-only',action='store_true');ap.add_argument('--reuse-build',action='store_true');a=ap.parse_args()
    ref=json.loads(REF.OUT.read_text());summary=REF.validate(ref);cases,extra=prepare_data(ref)
    if a.prepare_only:
        manifest=prepare(ref,cases);write(ROOT/'evidence/sprite-stitch-preflight.json',{'status':'prepared-native-unverified','summary':summary,'native_cases':len(cases),'policy_cases':len(extra),'generation':manifest,'command':'python3 tools/test_sprite_stitch.py --prepare-only'});print({'status':'prepared-native-unverified','native_cases':len(cases)});return
    manifest=retained(ref,cases);start=time.monotonic();ordinary=run([BEND,'tests/sprite_stitch.bend','--check-only']);ordinary_seconds=time.monotonic()-start;assert 'ALL PROOFS CHECK'in ordinary.stdout
    kernel={'status':'not-run','reason':'explicit --skip-kernel; ordinary/native evidence does not establish kernel validity'}
    if not a.skip_kernel:
        start=time.monotonic()
        try:
            p=subprocess.run([str(BEND),'src/sprite_stitch.bend','--verdict'],cwd=ROOT,env=ENV,capture_output=True,text=True,timeout=60);output=p.stdout+p.stderr
            kernel={'status':'passed'if p.returncode==0 and 'ALL PROOFS CHECK'in output else'compiler-kernel-mismatch'if 'mismatch between the TypeScript implementation'in output else'failed','seconds':time.monotonic()-start,'exit_code':p.returncode,'output':output.strip()};assert kernel['status']!='failed',kernel
        except subprocess.TimeoutExpired:kernel={'status':'inconclusive-timeout','timeout_seconds':60}
        write(ROOT/'evidence/sprite-stitch-kernel.json',kernel)
    receipt=BUILD/'native-build.json';pins=generation(ref,cases)
    if a.reuse_build:
        build=json.loads(receipt.read_text());assert build['generation']==pins;assert build['binary_sha256']==sha(BIN.read_bytes())
    else:
        cmd=[str(BEND),'tests/sprite_stitch.bend','-o',str(BIN)];start=time.monotonic()
        process=subprocess.Popen(cmd,cwd=ROOT,env=ENV,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        print({'native_compiler_pid':process.pid,'command':cmd,'timeout_seconds':600},flush=True)
        try:out,err=process.communicate(timeout=600)
        except subprocess.TimeoutExpired:
            process.kill();out,err=process.communicate();write(ROOT/'evidence/sprite-stitch-build-profile.json',{'status':'inconclusive-timeout','pid':process.pid,'timeout_seconds':600,'generation':pins,'stdout':out[-3000:],'stderr':err[-3000:]});raise
        if process.returncode:raise RuntimeError((process.returncode,out[-5000:],err[-5000:]))
        assert pins==generation(ref,cases),'Source/reference generation changed during emission'
        build={'schema':1,'generation':pins,'preparation_sha256':sha((BUILD/'preparation.json').read_bytes()),'binary_sha256':sha(BIN.read_bytes()),'binary_bytes':BIN.stat().st_size,'build_seconds':time.monotonic()-start,'compiler_pid':process.pid,'command':cmd};write(receipt,build)
    if a.build_only:print({'status':'native-build-retained','build':build});return
    start=time.monotonic();rows,timings=native(manifest);seconds1=time.monotonic()-start;start=time.monotonic();second,timings2=native(manifest);seconds2=time.monotonic()-start
    assert rows==second,'Two native runs differ';assert [r['id']for r in rows]==[c['id']for c in cases],'Native case order/count differs'
    assert pins==generation(ref,cases);retained(ref,cases)
    actual={r['id']:r['value']for r in rows};obs=observed(ref);recoveries={r['id']:r['result']for r in ref['observations']['recovery_cases']};raw={r['id']:r['result']for r in ref['observations']['raw_cases']}
    success=no_space=policy=recovery_count=placements=0;incomplete=[]
    for c in cases:
        v=actual[c['id']]
        if c['mode']=='raw':assert v==words(raw[c['id']]),(c['id'],v,raw[c['id']]);continue
        assert v['owner']=={'config':{k:c[k]for k in ['max_width','max_height','mip_level','padding_setting']},'entries':c['entries']},('owner changed',c,v)
        aresult=v['result'];e=obs.get(c['id'])
        if c['id']in extra:
            code=extra[c['id']]
            if code is not None:assert aresult['status']=='error'and aresult['code']==code,(c,aresult,code);policy+=1
            elif c['entries']:check_status(aresult,obs['one'],c);success+=1
            else:
                assert aresult['status']=='ok'and aresult['packed']['width']==0 and aresult['packed']['height']==0 and aresult['packed']['placements']==[];success+=1
            if c['recover']:
                check_status(v['recovery'],recoveries['one_recovery'],dict(c,max_width=16384,max_height=16384,mip_level=0,padding_setting=0));recovery_count+=1
        elif c['domain']=='invalid-id':assert aresult['status']=='error'and aresult['code']=='InvalidIdentifier';policy+=1
        elif c['domain']=='outside':assert aresult['status']=='error'and aresult['code']==policy_code(c),(c,aresult);policy+=1
        else:
            complete=check_status(aresult,e,c)
            if e['status']=='ok':success+=1;placements+=len(e['placements']);incomplete.extend([c['id']]if not complete else[])
            else:no_space+=1
            check_status(v['recovery'],recoveries[c['id']+'_recovery'],dict(c,max_width=16384,max_height=16384,mip_level=0,padding_setting=0));recovery_count+=1
    report={'schema':1,'status':'passed_bounded_domain','time_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'native_cases':len(cases),'successful_cases':success,'no_space_cases':no_space,'policy_rejections':policy,'raw_integer_cases':len(raw),'retained_owner_recoveries':recovery_count,'successful_callback_placements':placements,'java_success_incomplete':incomplete,'two_native_runs_equal':True,'canonical_report_sha256':sha(REF.canonical(rows)),'native_run_seconds':[seconds1,seconds2],'timings_ms_first':timings,'timings_ms_second':timings2,'timing_boundary':'packing + complete/owner/recovery serialization + forced encoded String.length + short stdout marker, excluding full report stdout; parsing before per-case timer','ordinary':{'output':ordinary.stdout.strip(),'seconds':ordinary_seconds},'kernel':kernel,'native_artifact':build,'preparation_sha256':sha((BUILD/'preparation.json').read_bytes()),'reference_sha256':sha(REF.OUT.read_bytes()),'command':'python3 tools/test_sprite_stitch.py --skip-kernel --reuse-build','boundary':'Exact observed static rectangle semantics within explicit positive int/budget admission. Java pathological pack outcomes recorded separately; raw arithmetic checked across wrap/masked shifts. No PNG/animation selection/mipmap pixels/atlas GPU execution.'}
    write(ROOT/'evidence/sprite-stitch-native.json',report);print({k:report[k]for k in ['status','native_cases','successful_cases','no_space_cases','policy_rejections','retained_owner_recoveries','canonical_report_sha256']})
if __name__=='__main__':main()
