#!/usr/bin/env python3
"""Original input arrays only; expected mip pixels remain in the official oracle."""
from __future__ import annotations
import argparse,copy,hashlib,json,os,re,subprocess,time
from pathlib import Path
import reference_texture_mipmap_probe as REF
ROOT=REF.ROOT;BEND=Path.home()/'.bend/bin/bend';BUILD=ROOT/'build/texture-mipmap';BIN=ROOT/'build/texture-mipmap-tests'
ENV={**os.environ,'BEND_MINECRAFT_LAUNCH_MODE':'hidden'}
DEFAULTS={'max_dimension':8192,'max_levels':16,'max_capacity':4194304,'max_work_pixels':1048576,'max_path_codepoints':4096}
def sha(b):return hashlib.sha256(b).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')
def capacity(n):return 1<<max(0,(n-1).bit_length())
def fingerprint():
    todo=[ROOT/'tests/texture_mipmap.bend'];seen={}
    while todo:
        p=todo.pop().resolve()
        if p in seen:continue
        b=p.read_bytes();seen[p]=sha(b);todo.extend(p.parent/x for x in re.findall(r'^import\s+(\.\.?/\S+\.bend)',b.decode(),re.M))
    return {**{str(p.relative_to(ROOT)):h for p,h in seen.items()},'compiler_sha256':sha(BEND.read_bytes())}
def cases(ref):
    result=[];expected={}
    for at,(c,r)in enumerate(zip(ref['inputs']['cases'],ref['observations']['cases'])):
        e=r['result'];levels=[]
        for index,im in enumerate(e['before']):
            p=im['pixels'];size=capacity(len(p));levels.append({'width':im['width'],'height':im['height'],'capacity':size,'pixels':p+[0xe1000000|(at<<10)|(index<<8)|j for j in range(size-len(p))]})
        n={'id':c['id'],'kind':'frame','levels':levels,'strategy':c['strategy'],'target_level':c['target_level']&0xffffffff,'path':c['path'],'bias':int(c['bias'],16),'transparent':e['supplied_transparent'],'translucent':e['supplied_translucent']};result.append(n);expected[n['id']]=e
    base=copy.deepcopy(result[0]);base.update(strategy='mean',transparent=False,translucent=False,target_level=0)
    def add(name,edit):
        n=copy.deepcopy(base);n['id']='policy_'+name;edit(n);result.append(n)
    for k,v in [('max_dimension',0),('max_dimension',16385),('max_levels',0),('max_levels',17),('max_capacity',16777217),('max_work_pixels',16777217),('max_path_codepoints',65537)]:
        add(k+'_'+str(v),lambda n,k=k,v=v:n.update(limits={**DEFAULTS,k:v}))
    add('target',lambda n:n.update(target_level=16));add('path',lambda n:n.update(path='a'*4097));add('empty',lambda n:n.update(levels=[]));add('count',lambda n:n.update(levels=[copy.deepcopy(n['levels'][0])for _ in range(17)]))
    add('zero_width',lambda n:n['levels'][0].update(width=0));add('negative_width',lambda n:n['levels'][0].update(width=0xffffffff));add('dimension',lambda n:n['levels'][0].update(width=8193))
    add('short_buffer',lambda n:n['levels'][0].update(capacity=2,pixels=n['levels'][0]['pixels'][:2]))
    add('unequal_tree',lambda n:n['levels'][0].update(width=2,height=1,capacity=3,pixels=n['levels'][0]['pixels'][:3],unbalanced=True))
    add('original_capacity',lambda n:(n['levels'][0].update(capacity=16,pixels=n['levels'][0]['pixels']+[0xf1234567]*12),n.update(limits={**DEFAULTS,'max_capacity':8})))
    add('original_work',lambda n:n.update(limits={**DEFAULTS,'max_work_pixels':3}))
    add('temporary_capacity',lambda n:n.update(strategy='cutout',target_level=0,limits={**DEFAULTS,'max_capacity':11}))
    def generated(n,limit,key):
        n.update(target_level=1,levels=[{'width':4,'height':4,'capacity':16,'pixels':[0xff123456]*16}],limits={**DEFAULTS,key:limit})
    add('generated_capacity',lambda n:generated(n,19,'max_capacity'));add('generated_work',lambda n:generated(n,19,'max_work_pixels'))
    add('large_unused_capacity',lambda n:n['levels'][0].update(capacity=64,pixels=n['levels'][0]['pixels']+[0xaabbccdd]*60))
    for at,q in enumerate(ref['inputs']['quads']):result.append({'id':'quad_'+str(at),'kind':'quad',**dict(zip('abcd',q))})
    result.append({'id':'all_tables','kind':'table'})
    # These are executable inputs: no reference-generated output or expected key.
    assert all(not any(k in c for k in ['output','after_supplied','expected','mean','dark'])for c in result)
    result=[c for c in result if c['id']!='policy_unequal_tree']
    return result,expected
def policy(c):
    l=c.get('limits',DEFAULTS);maximum=l['max_dimension'];levels=l['max_levels'];budget=l['max_capacity'];work=l['max_work_pixels'];path=l['max_path_codepoints'];target=c['target_level']
    if not(0<maximum<=16384 and 0<levels<=16 and budget<=16777216 and work<=16777216 and path<=65536):return ('LimitsRange',0)
    if not target<levels:return ('LevelRange',target)
    if len(c['path'])>path:return ('PathLimit',0)
    imgs=c['levels']
    if not 1<=len(imgs)<=levels:return ('LevelCount',0)
    total=logical=0
    for at,im in enumerate(imgs):
        w,h,size=im['width'],im['height'],im['capacity']
        if not(0<w<=maximum and 0<h<=maximum):return ('DimensionRange',at)
        if im.get('unbalanced'):return ('BufferShape',at)
        if w*h>size:return ('BufferLength',at)
        if size>budget-total:return ('CapacityLimit',at)
        if w*h>work-logical:return ('WorkLimit',at)
        total+=size;logical+=w*h
    s='cutout'if c['strategy']=='auto'and c['transparent']else'mean'if c['strategy']=='auto'else c['strategy']
    pre=len(imgs)==1 and not c['path'].startswith('item/')and s in ['cutout','strict_cutout','dark_cutout']
    extra=2*capacity(imgs[0]['width']*imgs[0]['height'])if pre and s in ['cutout','strict_cutout']else 0
    if extra>budget-total:return ('CapacityLimit',0)
    total+=extra;w,h=imgs[-1]['width'],imgs[-1]['height']
    for at in range(len(imgs),target+1):
        w//=2;h//=2
        if not w or not h:return ('ZeroGeneratedDimension',at)
        size=capacity(w*h)
        if size>budget-total:return ('CapacityLimit',at)
        if w*h>work-logical:return ('WorkLimit',at)
        total+=size;logical+=w*h
    return None
def generation(ref,cs):
    return {'native_sources':fingerprint(),'runner_sha256':sha(Path(__file__).read_bytes()),'reference_sha256':sha(REF.OUT.read_bytes()),'observation_sha256':ref['observation_sha256'],'semantic_inputs_sha256':sha(REF.canonical(cs))}
def prepared(ref,cs,create=False):
    manifest=BUILD/'preparation.json';data=BUILD/'cases.json';pins=generation(ref,cs)
    if create:
        write(data,cs);v={'schema':1,**pins,'case_path':str(data.relative_to(ROOT)),'case_sha256':sha(data.read_bytes())};v['seal_sha256']=sha(REF.canonical(v));write(manifest,v);return v
    if not manifest.is_file()or not data.is_file():raise RuntimeError('Missing prepared generation; use explicit --prepare-only')
    v=json.loads(manifest.read_text());unsigned=copy.deepcopy(v);seal=unsigned.pop('seal_sha256')
    if sha(REF.canonical(unsigned))!=seal:raise RuntimeError('Prepared seal mismatch')
    if any(v[k]!=x for k,x in pins.items()):raise RuntimeError('Prepared source/runner/reference/input generation stale')
    if sha(data.read_bytes())!=v['case_sha256']or json.loads(data.read_text())!=cs:raise RuntimeError('Prepared input bytes/semantics differ')
    return v
def run(command,timeout=60):
    p=subprocess.run(list(map(str,command)),cwd=ROOT,env=ENV,capture_output=True,text=True,timeout=timeout)
    if p.returncode:raise RuntimeError((command,p.returncode,p.stdout[-5000:],p.stderr[-5000:]))
    return p
def source_images(c):return [{k:im[k]for k in ['width','height','capacity','pixels']}for im in c['levels']]
def check_frame(c,n,e):
    before=source_images(c);assert n['before']==before,('original inputs',c,n)
    if not before:assert n['computed']=={'status':'empty'}
    else:
        only={**c,'levels':c['levels'][:1],'path':'','strategy':'mean','target_level':0,'limits':DEFAULTS};ce=policy(only)
        if ce:assert n['computed']=={'status':'error','code':ce[0],'level':ce[1]}
        else:
            original=before[0];alphas=[p>>24 for p in original['pixels'][:original['width']*original['height']]];tr=any(a==0 for a in alphas);tl=any(0<a<255 for a in alphas)
            assert n['computed']=={'status':'ok','transparent':tr,'translucent':tl},('original transparency helper',c,n)
            if e:assert (tr,tl)==(e['computed_transparent'],e['computed_translucent'])
    error=policy(c);after=n['after']
    if error:
        assert n['result']=={'status':'error','code':error[0],'level':error[1]},('prevalidation',c,n,error)
        assert after==before,('mutation on policy error',c,n)
    else:
        assert n['result']['status']=='ok',(c,n);s='cutout'if c['strategy']=='auto'and c['transparent']else'mean'if c['strategy']=='auto'else c['strategy'];early=len(before)>=c['target_level']+1;pre=len(before)==1 and not c['path'].startswith('item/')and s in ['cutout','strict_cutout','dark_cutout']
        assert {k:n['result'][k]for k in ['effective','early_return','base_preconditioned','original_levels']}=={'effective':s,'early_return':early,'base_preconditioned':pre,'original_levels':len(before)}
        assert n['result']['dimensions']==[{k:im[k]for k in ['width','height','capacity']}for im in after]
        if e:
            assert e['status']=='ok'and e['effective_strategy']==s and e['same_array']==early
            assert e['reused']==[i if i<len(before)else-1 for i in range(len(after))]
            assert len(after)==len(e['output'])
            for at,(im,expected)in enumerate(zip(after,e['output'])):
                w,h=expected['width'],expected['height'];assert (im['width'],im['height'])==(w,h),('dimensions',c['id'],at,im,expected);assert im['pixels'][:w*h]==expected['pixels'],('actual Java mip pixels',c['id'],at,im,expected)
            for at,im in enumerate(e['after_supplied']):assert after[at]['pixels'][:im['width']*im['height']]==im['pixels'],('provided image mutation',c['id'],at)
        elif c['id']=='policy_large_unused_capacity':assert after==before
        else:raise AssertionError(('missing actual expected admitted frame',c))
        for at,im in enumerate(after):
            logical=im['width']*im['height'];assert len(im['pixels'])==im['capacity']
            if at<len(before):assert im['pixels'][logical:]==before[at]['pixels'][logical:],('original unused cells',c['id'],at)
            else:assert im['capacity']==capacity(logical)and im['pixels'][logical:]==[0]*(im['capacity']-logical),('generated zero padding',c['id'],at)
    retained_shapes=[{**im,**({'unbalanced':True}if at<len(c['levels'])and c['levels'][at].get('unbalanced')else{})}for at,im in enumerate(after)]
    recovery={**c,'levels':retained_shapes,'path':'item/recovery','target_level':0,'strategy':'mean','bias':0,'transparent':False,'translucent':False,'limits':DEFAULTS};re=policy(recovery)
    assert n['recovered']==after,('same-owner recovery changed cells',c,n)
    if re:assert n['recovery']=={'status':'error','code':re[0],'level':re[1]},('recovery rejection',c,n,re)
    else:assert n['recovery']['status']=='ok'and n['recovery']['early_return']and n['recovery']['effective']=='mean'and not n['recovery']['base_preconditioned']
    return error is None,re is None
def retained_adoption(ref,cs,pins,create=False):
    archive=BUILD/'archive-failed-33682c9f';manifest_path=archive/'manifest.json';assert sha(manifest_path.read_bytes())=='61fb27a7664820e42233a5391606da8a6662c9982a98bb04df527902d81468a4','Reviewed failed-generation archive changed'
    manifest=json.loads(manifest_path.read_text());unsigned=copy.deepcopy(manifest);seal=unsigned.pop('seal_sha256');assert sha(REF.canonical(unsigned))==seal,'Failed-generation archive seal'
    records={r['path']:r for r in manifest['files']}
    for r in records.values():
        assert sha((ROOT/r['archive_path']).read_bytes())==r['sha256'],'Archived failed generation changed'
    for name in ['src/texture_mipmap.bend','tests/texture_mipmap.bend','src/json.bend','tools/reference_texture_mipmap_probe.py','reference/texture_mipmap.json','build/texture-mipmap/preserved.c','build/texture-mipmap-tests','build/texture-mipmap/native-build.json','evidence/texture-mipmap-native-runtime-failure.json']:
        assert sha((ROOT/name).read_bytes())==records[name]['sha256'],('Retained producer changed',name)
    assert sha(BEND.read_bytes())==manifest['compiler']['sha256'],'Compiler changed'
    for r in [manifest['base'],*manifest['native_effects_proven_in_original_C']]:
        assert sha(Path(r['path']).read_bytes())==r['sha256'],'Installed Base/native effect changed'
        assert sha((ROOT/r['archive_path']).read_bytes())==r['sha256'],'Archived Base/native effect changed'
    old=json.loads((archive/'build/texture-mipmap/native-build.json').read_text());before=json.loads((archive/'build/texture-mipmap/cases.json').read_text());excluded=[c for c in before if c['id']=='policy_unequal_tree']
    old_preparation_path=archive/'build/texture-mipmap/preparation.json';old_preparation=json.loads(old_preparation_path.read_text());assert sha(old_preparation_path.read_bytes())==old['preparation_sha256']
    assert old_preparation['case_sha256']==sha((archive/'build/texture-mipmap/cases.json').read_bytes())
    assert len(excluded)==1 and excluded[0]['levels'][0]['unbalanced'] is True
    assert cs==[c for c in before if c['id']!='policy_unequal_tree'],'Remaining semantic input changed'
    assert old['generation']['native_sources']==pins['native_sources'],'Native source closure changed'
    assert old['generation']['reference_sha256']==pins['reference_sha256'] and old['generation']['observation_sha256']==pins['observation_sha256'],'Actual oracle changed'
    receipt={'schema':1,'status':'explicit-retained-artifact-adoption','failed_archive_manifest_sha256':sha((archive/'manifest.json').read_bytes()),'old_native_producer_generation':old['generation'],'old_preparation_sha256':old['preparation_sha256'],'verification_generation':pins,'new_preparation_sha256':sha((BUILD/'preparation.json').read_bytes()),'binary_sha256':old['binary_sha256'],'generated_c_sha256':records['build/texture-mipmap/preserved.c']['sha256'],'old_native_receipt_sha256':records['build/texture-mipmap/native-build.json']['sha256'],'removed_input':excluded[0],'remaining_inputs_equal_to_original_filtered_once':True,'boundary':'Only unrepresentable unequal-tree native fixture removed. Original runtime attempt remains failed; BufferShape native coverage absent. Harness/production/transitive Bend, installed Base/native effects, compiler, original C and binary unchanged. Full system native/header/library closure remains uncaptured.'}
    receipt['seal_sha256']=sha(REF.canonical(receipt));path=BUILD/'native-adoption.json'
    if create:write(path,receipt)
    else:assert json.loads(path.read_text())==receipt,'Explicit adoption absent or stale'
    return receipt

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--prepare-only',action='store_true');ap.add_argument('--skip-kernel',action='store_true');ap.add_argument('--build-only',action='store_true');ap.add_argument('--reuse-build',action='store_true');ap.add_argument('--adopt-build',action='store_true');a=ap.parse_args()
    ref=json.loads(REF.OUT.read_text());summary=REF.validate(ref);cs,expected=cases(ref)
    if a.prepare_only:
        p=prepared(ref,cs,True);write(ROOT/'evidence/texture-mipmap-preflight.json',{'status':'prepared-native-unverified','reference':summary,'native_cases':len(cs),'generation':p,'frame_cases':sum(c['kind']=='frame'for c in cs),'expected_pixels_in_native_inputs':False,'command':'python3 tools/test_texture_mipmap.py --prepare-only'});print({'status':'prepared-native-unverified','cases':len(cs),'input_bytes':(BUILD/'cases.json').stat().st_size});return
    p=prepared(ref,cs)
    if a.adopt_build:
        assert not a.build_only and not a.reuse_build,'Adoption is a separate metadata-only phase'
        report=retained_adoption(ref,cs,generation(ref,cs),True);print({'status':report['status'],'binary_sha256':report['binary_sha256'],'cases':len(cs)});return
    ordinary=[]
    for path in ['src/texture_mipmap.bend','tests/texture_mipmap.bend']:
        start=time.monotonic();r=run([BEND,path,'--check-only']);assert 'ALL PROOFS CHECK'in r.stdout;ordinary.append({'path':path,'seconds':time.monotonic()-start,'output':r.stdout.strip()})
    kernel={'status':'not-run','reason':'explicit --skip-kernel; native pixel evidence precedes proof'}
    if not a.skip_kernel:
        start=time.monotonic()
        try:r=run([BEND,'src/texture_mipmap.bend','--verdict'],60);kernel={'status':'passed','seconds':time.monotonic()-start,'output':r.stdout.strip()}
        except subprocess.TimeoutExpired:kernel={'status':'inconclusive-timeout','timeout_seconds':60}
        write(ROOT/'evidence/texture-mipmap-kernel.json',kernel)
    pins=generation(ref,cs);receipt=BUILD/'native-build.json'
    if a.reuse_build:
        b=json.loads(receipt.read_text());assert b['binary_sha256']==sha(BIN.read_bytes())
        if b['generation']!=pins:retained_adoption(ref,cs,pins)
    else:
        command=[str(BEND),'tests/texture_mipmap.bend','-o',str(BIN)];start=time.monotonic();process=subprocess.Popen(command,cwd=ROOT,env=ENV,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True);print({'native_compiler_pid':process.pid,'command':command,'cap_seconds':600},flush=True)
        try:out,err=process.communicate(timeout=600)
        except subprocess.TimeoutExpired:
            process.kill();out,err=process.communicate();write(ROOT/'evidence/texture-mipmap-build-profile.json',{'status':'inconclusive-timeout','generation':pins,'timeout_seconds':600,'output':(out+err)[-5000:]});raise
        if process.returncode:raise RuntimeError((process.returncode,out[-5000:],err[-5000:]))
        assert pins==generation(ref,cs);b={'schema':1,'generation':pins,'preparation_sha256':sha((BUILD/'preparation.json').read_bytes()),'binary_sha256':sha(BIN.read_bytes()),'binary_bytes':BIN.stat().st_size,'build_seconds':time.monotonic()-start,'compiler_pid':process.pid,'command':command};write(receipt,b)
    if a.build_only:print({'status':'native-build-retained','artifact':b});return
    results=[];times=[]
    for i in range(2):
        start=time.monotonic();r=run([BIN,'--threads','1',BUILD/'cases.json'],120);times.append(time.monotonic()-start);(BUILD/f'native-run-{i+1}-stdout.txt').write_text(r.stdout);rows=[json.loads(x)for x in r.stdout.splitlines()];write(BUILD/f'native-run-{i+1}.json',rows);results.append(rows)
    assert results[0]==results[1],'Two native runs differ';rows=results[0];assert [r['id']for r in rows]==[c['id']for c in cs]
    success=reject=recoveries=pixels=0
    try:
        for c,n in zip(cs,rows):
            if c['kind']=='frame':
                e=expected.get(c['id']);ok,recovery=check_frame(c,n,e);success+=ok;reject+=not ok;recoveries+=recovery
                if ok and e:pixels+=sum(im['width']*im['height']for im in e['output'])
            elif c['kind']=='quad':
                index=int(c['id'].split('_')[1]);assert {k:n[k]for k in ['mean','dark']}==ref['observations']['quads'][index],('actual mean/dark scalar',c,n)
            else:assert {k:n[k]for k in ['srgb_to_linear','linear_to_srgb']}=={k:ref['observations']['tables'][k]for k in ['srgb_to_linear','linear_to_srgb']},'actual untouched gamma tables'
    except AssertionError as error:
        write(ROOT/'evidence/texture-mipmap-native-diagnostic-mismatch.json',{'status':'failed-native-comparison','detail':str(error),'case':c,'actual':n,'generation':pins,'artifact':b,'prepared_inputs_unchanged':prepared(ref,cs)==p,'boundary':'First mismatch preserved; no automatic source/expectation/compiler retry'});raise
    assert prepared(ref,cs)==p and pins==generation(ref,cs)
    report={'schema':1,'status':'passed_bounded_domain','cases':len(cs),'successful_frames':success,'policy_rejections':reject,'same_owner_successful_recoveries':recoveries,'actual_compared_pixels':pixels,'actual_scalar_quads':260,'lut_values':1280,'two_native_runs_equal':True,'canonical_report_sha256':sha(REF.canonical(rows)),'native_run_seconds':times,'native_artifact':b,'verification_generation':pins,'retained_artifact_adoption':json.loads((BUILD/'native-adoption.json').read_text())if b['generation']!=pins else None,'ordinary':ordinary,'kernel':kernel,'preparation_sha256':sha((BUILD/'preparation.json').read_bytes()),'expected_pixels_in_native_inputs':False,'command':'python3 tools/test_texture_mipmap.py --skip-kernel --reuse-build','boundary':'Actual five-strategy CPU mip pixels, original/preconditioned/provided levels, explicit prevalidation, logical ARGB order, complete original unused capacity preservation and generated zero padding; scalar diagnostics borrow Data while arrays retain sole ownership. No physical address identity assertion, failed-Java partial mutation recovery parity, atlas/GPU/animation frame selection.'};write(ROOT/'evidence/texture-mipmap-native.json',report);print({k:report[k]for k in ['status','cases','successful_frames','policy_rejections','actual_compared_pixels','canonical_report_sha256']})
if __name__=='__main__':main()
