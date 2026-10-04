#!/usr/bin/env python3
"""Owned Bend timelines/crops compared with untouched pinned CPU receivers."""
from __future__ import annotations
import argparse,copy,hashlib,json,os,re,shlex,signal,struct,subprocess,threading,time
from pathlib import Path
import reference_sprite_animation_probe as REF
ROOT=REF.ROOT;BEND=Path.home()/'.bend/bin/bend';BASE=Path.home()/'.bend/bend2/base.bend'
BUILD=ROOT/'build/sprite-animation';BIN=ROOT/'build/sprite-animation-tests'
ENV={**os.environ,'BEND_MINECRAFT_LAUNCH_MODE':'hidden'}
DEFAULTS={'max_dimension':8192,'max_levels':16,'max_frames':4096,'max_entries':65536,'max_capacity':4194304,'max_work_pixels':1048576}
def sha(b):return hashlib.sha256(b).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')
def capacity(n):return 1<<max(0,(n-1).bit_length())
def fingerprint():
    todo=[ROOT/'tests/sprite_animation.bend'];seen={}
    while todo:
        p=todo.pop().resolve()
        if p in seen:continue
        b=p.read_bytes();seen[p]=sha(b);todo.extend(p.parent/x for x in re.findall(r'^import\s+(\.\.?/\S+\.bend)',b.decode(),re.M))
    return {**{str(p.relative_to(ROOT)):h for p,h in seen.items()},'compiler_sha256':sha(BEND.read_bytes()),'installed_base_sha256':sha(BASE.read_bytes())}
def unsigned_metadata(m):
    if m is None:return None
    m=copy.deepcopy(m)
    for k in ['width','height','default_time']:
        if m.get(k)is not None:m[k]&=0xffffffff
    if m['frames']is not None:
        for f in m['frames']:
            f['index']&=0xffffffff
            if f['time']is not None:f['time']&=0xffffffff
    return m

def cases(ref):
    cs=[];expected={};admission={}
    for c,r in zip(ref['inputs']['decode_cases'],ref['observations']['decode_cases']):
        n={'kind':'decode',**copy.deepcopy(c)};cs.append(n);expected[n['id']]=r['result']
    for at,(c,r)in enumerate(zip(ref['inputs']['cpu_cases'],ref['observations']['cpu_cases'])):
        e=r['result'];im=e['original'];pixels=im['pixels'];size=capacity(len(pixels));n={'id':c['id'],'kind':'cpu','json':c['json'],'levels':[{'width':im['width'],'height':im['height'],'capacity':size,'pixels':pixels+[0xe1000000|(at<<12)|j for j in range(size-len(pixels))]}],'generate':e['status']=='ok'and'raw_frame_size'not in c,'mip_level':c['mip_level'],'path':c.get('path','animation'),'ticks':c['ticks'],'queries':[]}
        if'raw_metadata'in c:n['raw_metadata']=unsigned_metadata(e['animation_metadata'])
        if'raw_frame_size'in c:
            n['raw_metadata']=unsigned_metadata(e['animation_metadata']);n['raw_metadata'].update(width=c['raw_frame_size'][0]&0xffffffff,height=c['raw_frame_size'][1]&0xffffffff)
        if e.get('is_animated'):
            n['queries']=[{'index':index,'mip':mip}for index in e['unique_frames']for mip in range(len(e.get('mip_chain',[])))]
            n['queries'] += [{'index':0xffffffff,'mip':0},{'index':e['unique_frames'][0],'mip':16},{'index':e['unique_frames'][0],'mip':0}]
        else:n['queries']=[{'index':1,'mip':0}]
        cs.append(n);expected[n['id']]=e
    base=copy.deepcopy(next(c for c in cs if c['id']=='repeat'));base['ticks']=3
    def add(name,fn,code=None):
        n=copy.deepcopy(base);n['id']='policy_'+name;fn(n);cs.append(n);expected[n['id']]=expected['repeat']
        if code:admission[n['id']]=code
    for k,v in [('max_dimension',0),('max_dimension',16385),('max_levels',0),('max_levels',17),('max_frames',0),('max_frames',65537),('max_entries',65537),('max_capacity',16777217),('max_work_pixels',16777217)]:
        add(k+'_'+str(v),lambda n,k=k,v=v:n.update(limits={**DEFAULTS,k:v}),('LimitsRange','limits',0))
    add('entry_budget',lambda n:n.update(limits={**DEFAULTS,'max_entries':2}),('EntryLimit','frames',0))
    add('frame_budget',lambda n:n.update(limits={**DEFAULTS,'max_frames':5}),('FrameLimit','frame',6))
    add('capacity',lambda n:n.update(limits={**DEFAULTS,'max_capacity':31}),('CapacityLimit','mip',0))
    add('work',lambda n:n.update(limits={**DEFAULTS,'max_work_pixels':23}),('WorkLimit','mip',0))
    add('crop_capacity',lambda n:n.update(limits={**DEFAULTS,'max_capacity':35}))
    add('crop_work',lambda n:n.update(limits={**DEFAULTS,'max_work_pixels':27}))
    for f in ['nested','entry','sub','kind']:add('forged_'+f,lambda n,f=f:n.update(forge=f,ticks=2))
    def direct(n,levels):n.update(generate=False,levels=levels)
    add('empty',lambda n:direct(n,[]),('LevelCount','mip',0))
    add('levels',lambda n:direct(n,[{'width':1,'height':1,'capacity':1,'pixels':[i]}for i in range(17)]),('LevelCount','mip',0))
    add('zero_width',lambda n:(n.update(generate=False),n['levels'][0].update(width=0)),('DimensionRange','mip',0))
    add('negative_width',lambda n:(n.update(generate=False),n['levels'][0].update(width=0xffffffff)),('DimensionRange','mip',0))
    add('short_buffer',lambda n:direct(n,[{'width':4,'height':6,'capacity':2,'pixels':[1,2]}]),('BufferLength','mip',0))
    add('mip_coherence',lambda n:direct(n,[copy.deepcopy(base['levels'][0]),{'width':1,'height':3,'capacity':4,'pixels':[1,2,3,0xabcdef01]}]),('MipCoherence','mip',1))
    add('preserved_extra',lambda n:(direct(n,[copy.deepcopy(base['levels'][0]),{'width':2,'height':3,'capacity':8,'pixels':[11,12,13,14,15,16,0xabcde001,0xabcde002]}]),n['queries'].extend([{'index':2,'mip':1},{'index':0,'mip':1},{'index':0,'mip':0}])))
    add('metadata_error',lambda n:n.update(json='{"animation":null}',generate=False))
    # Only original images/metadata/query arguments are executable inputs.
    assert all(not any(k in c for k in ['expected','timeline','crops','mip_chain','argb_sha256'])for c in cs)
    return cs,expected,admission

def generation(ref,cs):
    return {'native_sources':fingerprint(),'runner_sha256':sha(Path(__file__).read_bytes()),'probe_sha256':sha(Path(REF.__file__).read_bytes()),'reference_sha256':sha(REF.OUT.read_bytes()),'observation_sha256':ref['observation_sha256'],'semantic_inputs_sha256':sha(REF.canonical(cs))}
def prepared(ref,cs,create=False):
    manifest=BUILD/'preparation.json';data=BUILD/'cases.json';pins=generation(ref,cs)
    if create:
        write(data,cs);v={'schema':1,**pins,'case_path':str(data.relative_to(ROOT)),'case_sha256':sha(data.read_bytes())};v['seal_sha256']=sha(REF.canonical(v));write(manifest,v);return v
    if not manifest.is_file()or not data.is_file():raise RuntimeError('Missing preparation; use explicit --prepare-only')
    v=json.loads(manifest.read_text());unsigned=copy.deepcopy(v);seal=unsigned.pop('seal_sha256')
    if sha(REF.canonical(unsigned))!=seal:raise RuntimeError('Prepared seal mismatch')
    if any(v[k]!=x for k,x in pins.items()):raise RuntimeError('Prepared generation stale')
    if sha(data.read_bytes())!=v['case_sha256']or json.loads(data.read_text())!=cs:raise RuntimeError('Prepared executable inputs changed')
    return v

def execute(command,cap,tag,pins):
    start=time.monotonic();p=subprocess.Popen(list(map(str,command)),cwd=ROOT,env=ENV,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True);print({'pid':p.pid,'process_group':p.pid,'command':list(map(str,command)),'cap_seconds':cap},flush=True)
    observations=[];stop=threading.Event()
    def watch():
        while not stop.wait(.1):
            listing=subprocess.run(['ps','-axo','pid=,ppid=,comm='],capture_output=True,text=True).stdout;rows=[]
            for line in listing.splitlines():
                fields=line.strip().split(None,2)
                if len(fields)==3:rows.append((int(fields[0]),int(fields[1]),fields[2]))
            descendants={p.pid}
            for _ in range(8):descendants.update(pid for pid,parent,name in rows if parent in descendants)
            for pid,parent,name in rows:
                if pid not in descendants or not any(s in name for s in ['bend','clang']):continue
                if any(o['pid']==pid for o in observations):continue
                args=subprocess.run(['ps','-p',str(pid),'-o','args='],capture_output=True,text=True).stdout.strip();record={'pid':pid,'ppid':parent,'command':args,'observed_seconds':time.monotonic()-start};observations.append(record)
                if 'clang'in name:
                    for token in shlex.split(args):
                        candidate=Path(token)
                        if token.endswith('.c')and candidate.is_file():
                            b=candidate.read_bytes();dest=BUILD/'preserved.c';dest.write_bytes(b);record['original_c']={'source_path':str(candidate),'preserved_path':str(dest.relative_to(ROOT)),'sha256':sha(b),'bytes':len(b)}
    t=threading.Thread(target=watch,daemon=True);t.start();timed_out=False
    try:out,err=p.communicate(timeout=cap)
    except subprocess.TimeoutExpired:
        timed_out=True
        try:os.killpg(p.pid,signal.SIGKILL)
        except ProcessLookupError:pass
        out,err=p.communicate()
    finally:stop.set();t.join(timeout=5)
    (BUILD/(tag+'-stdout.txt')).write_text(out);(BUILD/(tag+'-stderr.txt')).write_text(err)
    if timed_out or p.returncode:
        try:os.killpg(p.pid,signal.SIGKILL)
        except ProcessLookupError:pass
        p.wait()
    members=subprocess.run(['ps','-axo','pid=,pgid='],capture_output=True,text=True).stdout
    remaining=[int(a[0])for line in members.splitlines()if len(a:=line.split())==2 and int(a[1])==p.pid]
    receipt={'status':'inconclusive-timeout'if timed_out else'passed'if p.returncode==0 else'failed-runtime-or-build','pid':p.pid,'process_group':p.pid,'command':list(map(str,command)),'cap_seconds':cap,'exit_code':p.returncode,'seconds':time.monotonic()-start,'observed_processes':observations,'stdout_sha256':sha(out.encode()),'stderr_sha256':sha(err.encode()),'generation':pins,'whole_group_killed_on_timeout':timed_out,'group_members_after_cleanup':remaining,'full_native_header_library_closure':'uncaptured'};write(BUILD/(tag+'-execution.json'),receipt)
    if timed_out or p.returncode:
        lines=out.splitlines();write(ROOT/('evidence/sprite-animation-'+tag+'-failure.json'),{**receipt,'last_stdout_line':lines[-1]if lines else None,'retained_binary_sha256':sha(BIN.read_bytes())if BIN.is_file()else None,'boundary':'First failure retained. No automatic second run/verdict/source/oracle/compiler retry.'});raise RuntimeError((tag,receipt['status'],p.returncode,err[-3000:]))
    return out,receipt

def check_image(im,expected=None,original_padding=None):
    w,h,size=im['width'],im['height'],im['capacity'];logical=w*h
    assert len(im['pixels'])==size
    if expected:
        assert (w,h)==(expected['width'],expected['height'])
        assert sha(b''.join(struct.pack('>I',v)for v in im['pixels'][:logical]))==expected['argb_sha256'],('actual NativeImage pixels',w,h,expected)
    padding=[0]*(size-logical)if original_padding is None else original_padding
    assert im['pixels'][logical:]==padding,('unused capacity cells',im)
    return logical

def owner_chain(c,n,e):
    result=n['result'];owners=result['owners'];chain=owners if isinstance(owners,list)else owners['tail']['chain']if c.get('forge')=='nested'else owners['chain']
    if c.get('forge')=='nested':assert owners['chain']==[{'width':1,'height':1,'capacity':1,'pixels':[305419896]}]and owners['tail']['tail']is None
    elif isinstance(owners,dict):assert owners['tail']is None
    assert n['before']==c['levels'],('original executable pixels',c['id'])
    if c['generate']:
        assert n['mip_status']['status']=='ok',(c['id'],n['mip_status'])
        assert len(chain)==len(e['mip_chain'])
        total=0
        for i,(im,ex)in enumerate(zip(chain,e['mip_chain'])):
            total+=check_image(im,ex,c['levels'][i]['pixels'][im['width']*im['height']:]if i<len(c['levels'])else None)
        return chain,total
    assert chain==c['levels'],('no requested mip mutation',c['id'],chain,c['levels'])
    return chain,0

def metadata_of(c,e):
    if'raw_metadata'in c:return c['raw_metadata']
    return unsigned_metadata(e.get('animation_metadata'))
def policy(c,e):
    l=c.get('limits',DEFAULTS);d=l['max_dimension'];levels=l['max_levels'];frames=l['max_frames'];entries=l['max_entries'];capacity_limit=l['max_capacity'];work_limit=l['max_work_pixels']
    if not(0<d<=16384 and 0<levels<=16 and 0<frames<=65536 and entries<=65536 and capacity_limit<=16777216 and work_limit<=16777216):return('LimitsRange','limits',0)
    dims=e['mip_chain']if c['generate']else c['levels']
    if not 1<=len(dims)<=levels:return('LevelCount','mip',0)
    m=metadata_of(c,e)
    if m is not None:
        if not 0<m['default_time']<2147483648:return('DefaultTimeRange','frametime',0)
        if m['frames']is not None and len(m['frames'])>entries:return('EntryLimit','frames',0)
    w,h=dims[0]['width'],dims[0]['height']
    if not(0<w<=d and 0<h<=d):return('DimensionRange','mip',0)
    if m is None:fw,fh=w,h
    elif m['width']is None and m['height']is None:fw=fh=min(w,h)
    else:fw=m['width']if m['width']is not None else w;fh=m['height']if m['height']is not None else h
    if not(0<fw<2147483648 and 0<fh<2147483648 and fw<=w and fh<=h):return('FrameDimension','frame',0)
    if w%fw or h%fh:return('NonDivisible','frame',0)
    count=(w//fw)*(h//fh)
    if count>frames:return('FrameLimit','frame',count)
    total=work=0;ew,eh=w,h;efw,efh=fw,fh
    for i,im in enumerate(dims):
        iw,ih=im['width'],im['height'];size=c['levels'][i]['capacity']if i<len(c['levels'])else capacity(iw*ih)
        if not(0<iw<=d and 0<ih<=d):return('DimensionRange','mip',i)
        if iw*ih>size:return('BufferLength','mip',i)
        if(iw,ih)!=(ew,eh):return('MipCoherence','mip',i)
        if not efw or not efh:return('ZeroFrameMip','mip',i)
        if size>capacity_limit-total:return('CapacityLimit','mip',i)
        if iw*ih>work_limit-work:return('WorkLimit','mip',i)
        total+=size;work+=iw*ih;ew//=2;eh//=2;efw//=2;efh//=2
    return None

def check(c,n,e,declared):
    assert c['id']==n['id']
    if c['kind']=='decode':
        found=n['result'];actual=e['status'];assert found['status']==actual,('actual animation CODEC status',c,n,e)
        if actual=='ok':assert found=={**unsigned_metadata(e),'status':'ok'}
        return {'decode':1}
    assert n['result']['status']in ['ok','error','metadata-error']
    if c['id']=='policy_metadata_error':
        assert n['result']['status']=='metadata-error'and n['result']['owners']==c['levels'];return {'reject':1}
    chain,pixels=owner_chain(c,n,e);error=policy(c,e)
    if c['id']in declared:assert error==declared[c['id']],('declared policy expectation',c,error,declared[c['id']])
    result=n['result']
    if error:
        assert result['status']=='error'and result['error']=={'status':'error','code':error[0],'field':error[1],'index':error[2]},('admission rejection',c,result,error)
        recovery=result['recovery'];owners=recovery['owners']['chain']if isinstance(recovery['owners'],dict)else recovery['owners'];assert owners==chain,('same rejected owner recovery',c,recovery,chain)
        rc={**c,'generate':False,'levels':chain,'limits':DEFAULTS,'raw_metadata':None};re=policy(rc,e)
        if re:assert recovery['result']=={'status':'error','code':re[0],'field':re[1],'index':re[2]},('same owner recovery rejection',c,recovery,re)
        else:assert recovery['result']['status']=='ok'and not recovery['result']['plan']['animated']and recovery['result']['plan']['unique_frames']==[1],('same owner recovered static interpretation',c,recovery)
        return {'reject':1,'pixels':pixels,'recover':re is None}
    assert result['status']=='ok'
    forged={'nested':('NestedOwner','contents',0),'entry':('TimelineEntry','timeline',0xffffffff),'sub':('TimelineSubFrame','timeline',0xffffffff),'kind':('TimelineKind','timeline',0)}.get(c.get('forge'))
    if forged:
        expected={'status':'error','code':forged[0],'field':forged[1],'index':forged[2]};assert result['initial']==expected
        assert all(v==expected for v in result['timeline'])and all(q['result']==expected for q in result['crops']);return {'forged':1,'pixels':pixels}
    p=result['initial']['plan'];assert result['initial']['status']=='ok'
    assert p['dimensions']==[{k:im[k]for k in ['width','height','capacity']}for im in chain]
    assert p['capacity']==sum(im['capacity']for im in chain)and p['work']==sum(im['width']*im['height']for im in chain)
    if c['id']=='policy_preserved_extra':
        # An explicit caller-owned extra level is preserved; this test's expected
        # crop cells follow its original supplied input, not a Java-generated mip.
        assert chain==c['levels']
    else:
        assert p['animated']==e['is_animated']and(p['width'],p['height'])==(e['frame_width'],e['frame_height'])and p['unique_frames']==e['unique_frames'],('actual plan',c,p,e)
        if p['animated']:assert p['frames']==e['frames']and p['row_size']==e['row_size']and p['interpolate']==e['interpolate']
    samples=[result['initial']['selection'],*result['timeline']];timeline_count=0
    for at,s in enumerate(samples):
        if not p['animated']:
            assert s=={'status':'static','width':p['width'],'height':p['height']};continue
        t=e['timeline'][at];assert {k:s[k]for k in t}==t,('untouched actual timeline',c['id'],at,s,t)
        timeline_count+=1
        for label,index in [('current_rects',s['current']),('next_rects',s['next'])]:
            x=(index%p['row_size'])*p['width'];y=(index//p['row_size'])*p['height'];assert s[label]==[{'mip':m,'x':x>>m,'y':y>>m,'width':p['width']>>m,'height':p['height']>>m}for m in range(len(chain))]
    crop_expected={(q['index'],q['mip']):q for q in e.get('crops',[])};crops=read_errors=0
    assert len(result['crops'])==len(c['queries'])
    for q,nq in zip(c['queries'],result['crops']):
        index,mip=q['index'],q['mip'];found=nq['result'];assert (nq['index'],nq['mip'])==(index,mip)
        code='StaticSelection'if not p['animated']else'UnreferencedFrame'if index not in p['unique_frames']else'MipRange'if mip>=len(chain)else None
        if code is None:
            w,h=p['width']>>mip,p['height']>>mip;l=c.get('limits',DEFAULTS)
            if capacity(w*h)>l['max_capacity']-p['capacity']:code='CropCapacity'
            elif w*h>l['max_work_pixels']-p['work']:code='CropWork'
        if code:
            assert found=={'status':'error','code':code,'field':'mip'if code=='MipRange'else'frame','index':mip if code=='MipRange'else index},('read rejection',c,q,found,code);read_errors+=1
        else:
            assert found['status']=='ok';image=found['image'];crops+=1
            if c['id']=='policy_preserved_extra':
                src=chain[mip];x=(index%p['row_size'])*p['width']>>mip;y=(index//p['row_size'])*p['height']>>mip;words=[src['pixels'][x+dx+(y+dy)*src['width']]for dy in range(h)for dx in range(w)];assert image['pixels'][:w*h]==words;check_image(image)
            else:
                ex=crop_expected[(index,mip)];assert ex['status']=='ok';pixels+=check_image(image,ex['image'])
    return {'admit':1,'pixels':pixels,'timeline':timeline_count,'crops':crops,'read_reject':read_errors}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--prepare-only',action='store_true');ap.add_argument('--skip-kernel',action='store_true');ap.add_argument('--build-only',action='store_true');ap.add_argument('--reuse-build',action='store_true');ap.add_argument('--kernel-only',action='store_true');a=ap.parse_args();BUILD.mkdir(parents=True,exist_ok=True)
    ref=json.loads(REF.OUT.read_text());summary=REF.validate(ref);cs,expected,declared=cases(ref);pins=generation(ref,cs);ordinary=[]
    for name in ['src/sprite_animation.bend','tests/sprite_animation.bend']:
        out,receipt=execute([BEND,name,'--check-only'],60,'ordinary-'+Path(name).stem,pins);assert'ALL PROOFS CHECK'in out;ordinary.append(receipt)
    if a.prepare_only:
        preparation=prepared(ref,cs,True);report={'status':'prepared-native-unverified','cases':len(cs),'decode_cases':sum(c['kind']=='decode'for c in cs),'cpu_cases':sum(c['kind']=='cpu'for c in cs),'reference':summary,'generation':preparation,'ordinary':ordinary,'expected_pixels_in_native_inputs':False,'BufferShape_native_coverage':'absent: installed Base ANode prevents unequal-depth native construction; source inspection retained','commands':{'native':'python3 tools/test_sprite_animation.py --skip-kernel --build-only','runtime':'python3 tools/test_sprite_animation.py --skip-kernel --reuse-build','kernel':'python3 tools/test_sprite_animation.py --kernel-only'},'caps_seconds':{'whole_build_group':600,'each_runtime_group':120,'full_source_verdict_group':60}};write(ROOT/'evidence/sprite-animation-preflight.json',report);print({k:report[k]for k in ['status','cases','decode_cases','cpu_cases']});return
    preparation=prepared(ref,cs)
    if a.kernel_only:
        out,k=execute([BEND,'src/sprite_animation.bend','--verdict'],60,'kernel',pins);assert'ALL PROOFS CHECK'in out;write(ROOT/'evidence/sprite-animation-kernel.json',{**k,'boundary':'Only stated scalar size/static-kind laws, no pixel/timeline parity proof'});return
    receipt=BUILD/'native-build.json'
    if a.reuse_build:
        built=json.loads(receipt.read_text());assert built['generation']==pins and built['binary_sha256']==sha(BIN.read_bytes())and built['preparation_sha256']==sha((BUILD/'preparation.json').read_bytes())
    else:
        _,execution=execute([BEND,'tests/sprite_animation.bend','-o',BIN],600,'native-build',pins);assert generation(ref,cs)==pins and prepared(ref,cs)==preparation;built={'schema':1,'generation':pins,'preparation_sha256':sha((BUILD/'preparation.json').read_bytes()),'binary_sha256':sha(BIN.read_bytes()),'binary_bytes':BIN.stat().st_size,'execution':execution};write(receipt,built)
    if a.build_only:print({'status':'native-build-retained','binary_sha256':built['binary_sha256']});return
    outputs=[];receipts=[];totals={}
    for i in range(2):
        out,execution=execute([BIN,'--threads','1',BUILD/'cases.json'],120,'native-run-'+str(i+1),pins);c=n=None
        try:
            rows=[json.loads(line)for line in out.splitlines()];write(BUILD/f'native-run-{i+1}.json',rows)
            assert [r['id']for r in rows]==[c['id']for c in cs],('native row order/coverage',len(rows),len(cs));counts={}
            for c,n in zip(cs,rows):
                for k,v in check(c,n,expected.get(c['id']),declared).items():counts[k]=counts.get(k,0)+v
            if outputs:assert rows==outputs[0]and counts==totals,'Two native runs differ'
        except (AssertionError,ValueError,KeyError,TypeError)as error:
            write(ROOT/'evidence/sprite-animation-native-diagnostic-mismatch.json',{'status':'failed-first-native-comparison','detail':str(error),'case':c,'actual':n,'expected':expected.get(c['id'])if c else None,'generation':pins,'artifact':built,'execution':execution,'inputs_retained':prepared(ref,cs)==preparation,'boundary':'Stop before second native run/verdict; no automatic expectation/source/compiler changes.'});raise
        outputs.append(rows);receipts.append(execution);totals=counts
    assert generation(ref,cs)==pins and prepared(ref,cs)==preparation
    report={'schema':1,'status':'passed_bounded_domain','cases':len(cs),'counts':totals,'two_native_runs_equal':True,'canonical_native_sha256':sha(REF.canonical(outputs[0])),'generation':pins,'native_artifact':built,'runtime':receipts,'ordinary':ordinary,'preparation_sha256':sha((BUILD/'preparation.json').read_bytes()),'expected_pixels_in_native_inputs':False,'boundary':'Actual animation CODEC/default/filter/order, bounded loader admission, owned whole-sheet mip chain, actual CPU timeline and copyRect crop hashes. Static [1] sentinel remains observation, no implicit crop. Nested ownership retained and closed. No actual createAnimationState/draw/upload/shader interpolation execution, atlas allocation or GPU parity.'};write(ROOT/'evidence/sprite-animation-native.json',report);print({k:report[k]for k in ['status','cases','counts','canonical_native_sha256']})
    if not a.skip_kernel:
        out,k=execute([BEND,'src/sprite_animation.bend','--verdict'],60,'kernel',pins);assert'ALL PROOFS CHECK'in out;write(ROOT/'evidence/sprite-animation-kernel.json',k)
if __name__=='__main__':main()
