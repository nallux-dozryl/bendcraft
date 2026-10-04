#!/usr/bin/env python3
"""Exact Bend atlas UV words vs actual pinned sprite receivers, no window."""
from __future__ import annotations
import argparse,copy,hashlib,json,os,re,subprocess,time
from pathlib import Path
import reference_sprite_uv_probe as REF
ROOT=REF.ROOT;BEND=Path.home()/'.bend/bin/bend';BUILD=ROOT/'build/sprite-uv';BIN=ROOT/'build/sprite-uv-tests'
ENV={**os.environ,'BEND_MINECRAFT_LAUNCH_MODE':'hidden'}
FIELDS=['atlas_width','atlas_height','width','height','x','y','padding'];FLOATS=['u0','v0','u1','v1']
def sha(b):return hashlib.sha256(b).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')
def u32(x):return x&0xffffffff
def fp(s):return int(s,16)
def fingerprint():
    pending=[ROOT/'tests/sprite_uv.bend'];seen={}
    while pending:
        p=pending.pop().resolve()
        if p in seen:continue
        b=p.read_bytes();seen[p]=sha(b);pending.extend(p.parent/x for x in re.findall(r'^import\s+(\.\.?/\S+\.bend)',b.decode(),re.M))
    return {**{str(p.relative_to(ROOT)):s for p,s in seen.items()},'compiler_sha256':sha(BEND.read_bytes())}
def cases(ref):
    cs=[];expected={}
    for c,r in zip(ref['inputs']['cases'],ref['observations']['cases']):
        n={'id':c['id'],**{k:u32(c[k])for k in FIELDS},'queries':[fp(q)for q in c['queries']]};cs.append(n);expected[n['id']]=r['result']
    for c,r in zip(ref['inputs']['stitch_cases'],ref['observations']['stitch_cases']):
        for s in r['result']['sprites']:
            n={'id':c['id']+':'+str(s['tag']),'atlas_width':r['result']['atlas_width'],'atlas_height':r['result']['atlas_height'],**{k:s[k]for k in FIELDS[2:]},'queries':[fp(q)for q in c['queries']]};cs.append(n);expected[n['id']]=s
    base=copy.deepcopy(cs[0]);policy={}
    def add(name,change,code):
        n=copy.deepcopy(base);n.update(id=name,**change);cs.append(n);policy[name]=code
    add('policy_atlas_zero',{'atlas_width':0},'AtlasRange');add('policy_atlas_upper',{'atlas_width':536870913},'AtlasRange');add('policy_atlas_negative',{'atlas_height':0xffffffff},'AtlasRange')
    add('policy_frame_zero',{'width':0},'FrameRange');add('policy_frame_upper',{'height':536870913},'FrameRange');add('policy_frame_negative',{'width':0xffffffff},'FrameRange')
    add('policy_x_negative',{'x':0xffffffff},'OriginRange');add('policy_y_upper',{'y':536870913},'OriginRange');add('policy_padding_negative',{'padding':0xffffffff},'OriginRange')
    add('policy_padding_upper',{'padding':536870913},'OriginRange');add('policy_padding_bounds',{'padding':1},'PaddedBounds');add('policy_x_bounds',{'x':1},'PaddedBounds');add('policy_y_bounds',{'y':1},'PaddedBounds')
    add('policy_exact_upper',{},None)
    return cs,expected,policy
def generation(ref,cs):
    return {'native_sources':fingerprint(),'runner_sha256':sha(Path(__file__).read_bytes()),'reference_sha256':sha(REF.OUT.read_bytes()),'observation_sha256':ref['observation_sha256'],'semantic_inputs_sha256':sha(REF.canonical(cs))}
def prepared(ref,cs,create=False):
    manifest=BUILD/'preparation.json';data=BUILD/'cases.json';pins=generation(ref,cs)
    if create:
        write(data,cs);v={'schema':1,**pins,'case_path':str(data.relative_to(ROOT)),'case_sha256':sha(data.read_bytes())};v['seal_sha256']=sha(REF.canonical(v));write(manifest,v);return v
    if not manifest.is_file()or not data.is_file():raise RuntimeError('Missing prepared inputs; run explicit --prepare-only')
    v=json.loads(manifest.read_text());unsigned=copy.deepcopy(v);seal=unsigned.pop('seal_sha256')
    if sha(REF.canonical(unsigned))!=seal:raise RuntimeError('Prepared manifest seal mismatch')
    if any(v[k]!=x for k,x in pins.items()):raise RuntimeError('Stale prepared source/runner/reference/input generation; run explicit --prepare-only')
    if sha(data.read_bytes())!=v['case_sha256']or json.loads(data.read_text())!=cs:raise RuntimeError('Prepared case bytes/semantics differ')
    return v
def run(cmd,timeout=60):
    p=subprocess.run(list(map(str,cmd)),cwd=ROOT,env=ENV,capture_output=True,text=True,timeout=timeout)
    if p.returncode:raise RuntimeError((cmd,p.returncode,p.stdout[-5000:],p.stderr[-5000:]))
    return p
def policy_code(c):
    valid=lambda x:0<x<=536870912
    if not valid(c['atlas_width'])or not valid(c['atlas_height']):return 'AtlasRange'
    if not valid(c['width'])or not valid(c['height']):return 'FrameRange'
    if any(c[k]>536870912 for k in ['x','y','padding']):return 'OriginRange'
    if c['x']+2*c['padding']+c['width']>c['atlas_width']or c['y']+2*c['padding']+c['height']>c['atlas_height']:return 'PaddedBounds'
    return None
def check(c,n,e,code):
    raw=n['raw'];assert raw['input']=={k:c[k]for k in FIELDS},('input preservation',c,n)
    assert raw['content_x']==u32(c['x']+c['padding'])and raw['content_y']==u32(c['y']+c['padding']),('origin',c,n)
    if e is not None:
        for k in ['x','y','width','height','padding']:assert u32(e[k])==c[k],('actual getters',c,e)
        for k in FLOATS:assert raw[k]==fp(e[k]),(c['id'],k,raw[k],e[k])
        assert raw['corners']==[[fp(e['u0']),fp(e['v0'])],[fp(e['u0']),fp(e['v1'])],[fp(e['u1']),fp(e['v1'])],[fp(e['u1']),fp(e['v0'])]],('getter corners',c,n,e)
        assert raw['mapped_corners']==[[fp(v['u']),fp(v['v'])]for v in e['mapped_corners']],('actual cuboid corner order/mapping',c,n,e)
        assert [[v['normalized_u'],v['normalized_v']]for v in e['mapped_corners']]==[['00000000','00000000'],['00000000','3f800000'],['3f800000','3f800000'],['3f800000','00000000']]
        assert len(raw['queries'])==len(e['queries'])
        for a,b in zip(raw['queries'],e['queries']):assert a=={'query':fp(b['query']),'u':fp(b['u']),'v':fp(b['v']),'map':[fp(b['u']),fp(b['v'])]},('getU/getV exact raw F32',c['id'],a,b)
    if code is None:
        assert n['derive']['status']=='ok',(c,n)
        assert {k:n['derive'][k]for k in FLOATS}=={k:raw[k]for k in FLOATS},('derive/raw mismatch',c,n)
    else:assert n['derive']=={'status':'error','code':code},('admission',c,n,code)
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--prepare-only',action='store_true');ap.add_argument('--skip-kernel',action='store_true');ap.add_argument('--build-only',action='store_true');ap.add_argument('--reuse-build',action='store_true');a=ap.parse_args()
    ref=json.loads(REF.OUT.read_text());summary=REF.validate(ref);cs,expected,policy=cases(ref)
    if a.prepare_only:
        p=prepared(ref,cs,True);write(ROOT/'evidence/sprite-uv-preflight.json',{'status':'prepared-native-unverified','summary':summary,'native_cases':len(cs),'policy_boundaries':len(policy),'generation':p,'command':'python3 tools/test_sprite_uv.py --prepare-only'});print({'status':'prepared-native-unverified','native_cases':len(cs)});return
    p=prepared(ref,cs);start=time.monotonic();ordinary=run([BEND,'tests/sprite_uv.bend','--check-only']);ordinary_seconds=time.monotonic()-start;assert 'ALL PROOFS CHECK'in ordinary.stdout
    kernel={'status':'not-run','reason':'explicit --skip-kernel; native evidence is independent of mathematical verdict'}
    if not a.skip_kernel:
        start=time.monotonic()
        try:
            k=subprocess.run([str(BEND),'src/sprite_uv.bend','--verdict'],cwd=ROOT,env=ENV,capture_output=True,text=True,timeout=60);output=k.stdout+k.stderr;kernel={'status':'passed'if k.returncode==0 and 'ALL PROOFS CHECK'in output else'compiler-kernel-mismatch'if 'mismatch between the TypeScript implementation'in output else'failed','seconds':time.monotonic()-start,'output':output.strip(),'exit_code':k.returncode};assert kernel['status']!='failed',kernel
        except subprocess.TimeoutExpired:kernel={'status':'inconclusive-timeout','timeout_seconds':60}
        write(ROOT/'evidence/sprite-uv-kernel.json',kernel)
    receipt=BUILD/'native-build.json';pins=generation(ref,cs)
    if a.reuse_build:
        b=json.loads(receipt.read_text());assert b['generation']==pins;assert b['binary_sha256']==sha(BIN.read_bytes())
    else:
        start=time.monotonic();cmd=[str(BEND),'tests/sprite_uv.bend','-o',str(BIN)];process=subprocess.Popen(cmd,cwd=ROOT,env=ENV,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True);print({'native_compiler_pid':process.pid,'command':cmd,'cap_seconds':600},flush=True)
        try:out,err=process.communicate(timeout=600)
        except subprocess.TimeoutExpired:process.kill();out,err=process.communicate();write(ROOT/'evidence/sprite-uv-build-profile.json',{'status':'inconclusive-timeout','generation':pins,'pid':process.pid,'timeout_seconds':600,'output':(out+err)[-5000:]});raise
        if process.returncode:raise RuntimeError((process.returncode,out[-5000:],err[-5000:]))
        assert pins==generation(ref,cs),'Generation changed during emission'
        b={'schema':1,'generation':pins,'preparation_sha256':sha((BUILD/'preparation.json').read_bytes()),'binary_sha256':sha(BIN.read_bytes()),'binary_bytes':BIN.stat().st_size,'build_seconds':time.monotonic()-start,'compiler_pid':process.pid,'command':cmd};write(receipt,b)
    if a.build_only:print({'status':'native-build-retained','artifact':b});return
    results=[];times=[]
    for i in range(2):
        start=time.monotonic();r=run([BIN,'--threads','1',BUILD/'cases.json'],90);times.append(time.monotonic()-start);(BUILD/f'native-run-{i+1}-stdout.txt').write_text(r.stdout);rows=[json.loads(x)for x in r.stdout.splitlines()];write(BUILD/f'native-run-{i+1}.json',rows);results.append(rows)
    assert results[0]==results[1],'Two native runs differ';rows=results[0];assert [r['id']for r in rows]==[c['id']for c in cs]
    success=reject=queries=0
    try:
        for c,n in zip(cs,rows):
            code=policy[c['id']]if c['id']in policy else policy_code(c);e=expected.get(c['id']);check(c,n,e,code)
            success+=code is None;reject+=code is not None;queries+=len(e['queries'])if e is not None else 0
    except AssertionError as error:
        write(ROOT/'evidence/sprite-uv-native-diagnostic-mismatch.json',{'status':'failed-native-comparison','detail':str(error),'case':c,'actual':n,'expected':e,'generation':pins,'artifact':b,'prepared_inputs_unchanged':prepared(ref,cs)==p,'boundary':'First mismatch preserved; no automatic expectation/source/compiler retry'});raise
    assert pins==generation(ref,cs);assert prepared(ref,cs)==p
    report={'schema':1,'status':'passed_bounded_domain','native_cases':len(cs),'actual_direct_cases':len(ref['inputs']['cases']),'actual_stitch_sprites':25,'query_pairs':queries,'admitted':success,'policy_rejections':reject,'two_native_runs_equal':True,'canonical_report_sha256':sha(REF.canonical(rows)),'native_run_seconds':times,'native_artifact':b,'ordinary':{'output':ordinary.stdout.strip(),'seconds':ordinary_seconds},'kernel':kernel,'preparation_sha256':sha((BUILD/'preparation.json').read_bytes()),'reference_sha256':sha(REF.OUT.read_bytes()),'command':'python3 tools/test_sprite_uv.py --skip-kernel --reuse-build','boundary':'Exact raw Java int/F32 constructor endpoints, actual getters and CuboidFace R0 mapped corners, getU/getV ordered operations incl recorded nonfinite bits on pinned target. Explicit usable-layout admission. No pixel atlas/mipmap/animation/GPU/UBO/frame execution.'};write(ROOT/'evidence/sprite-uv-native.json',report);print({k:report[k]for k in ['status','native_cases','query_pairs','admitted','policy_rejections','canonical_report_sha256']})
if __name__=='__main__':main()
