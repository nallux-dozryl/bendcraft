#!/usr/bin/env python3
"""Actual jar -> pure Bend resource/bake/world/BVH frame, independent oracle."""
from __future__ import annotations
import argparse,copy,csv,datetime,hashlib,io,json,math,os,re,struct,subprocess,sys,time,zipfile,zlib
from fractions import Fraction
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
PYTHON=Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
if Path(sys.executable).resolve()!=PYTHON.resolve():os.execv(str(PYTHON),[str(PYTHON),__file__,*sys.argv[1:]])
import numpy as np
from PIL import Image,__version__ as PILLOW
BEND=Path.home()/'.bend/bin/bend';BUILD=ROOT/'build/resource-frame'
PHASES={'draw':('main',ROOT/'build/resource-frame-tests'),'audit':('audit_main',ROOT/'build/resource-frame-audit'),'geometry':('geometry_main',ROOT/'build/resource-frame-geometry')}
JAR=Path.home()/'Library/Application Support/minecraft/versions/26.3/26.3.jar';REF=ROOT/'reference/model_semantics.json'
ENV={**os.environ,'BEND_MINECRAFT_LAUNCH_MODE':'hidden'}
IDS=['minecraft:block/dirt','minecraft:block/oak_planks','minecraft:block/stone'];SLOTS={v:i for i,v in enumerate(IDS)}
DIRECTIONS=['down','up','north','south','west','east','unculled']
def sha(b):return hashlib.sha256(b).hexdigest()
def canonical(v):return json.dumps(v,sort_keys=True,separators=(',',':')).encode()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,sort_keys=True,indent=2)+'\n')
def f(x):return np.float32(x)
def word(x):return struct.unpack('<I',struct.pack('<f',x))[0]
def unw(x):return struct.unpack('<f',struct.pack('<I',x))[0]
def double_words(x):return list(struct.unpack('>II',struct.pack('>d',x)))
def unsigned(x):return x&0xffffffff
def signed(x):return x-2**32 if x>=2**31 else x
def from_double_words(v):return struct.unpack('>d',struct.pack('>II',*v))[0]
def entrypoints(prepare=False):
    entries={}
    for phase,(name,binary)in PHASES.items():
        path=BUILD/(phase+'-entry.bend');source='import Base\nimport ../../tests/resource_frame.bend as T\ndef main() -> IO(Unit):\n  T.'+name+'()\n'
        if prepare:path.write_text(source)
        elif not path.is_file()or path.read_text()!=source:raise RuntimeError('Missing/stale prepared entry '+str(path)+'; run --prepare-only')
        entries[phase]=path
    return entries
def fingerprint():
    pending=[ROOT/'tests/resource_frame.bend'];seen={}
    while pending:
        p=pending.pop().resolve()
        if str(p)in seen:continue
        data=p.read_bytes();seen[str(p)]=sha(data)
        for imp in re.findall(r'^import\s+(\.\.?/\S+\.bend)',data.decode(),re.M):pending.append(p.parent/imp)
    return {**{str(Path(p).relative_to(ROOT)):v for p,v in seen.items()},**{str(p.relative_to(ROOT)):sha(p.read_bytes())for p in entrypoints().values()},'pinned_compiler_sha256':sha(BEND.read_bytes())}
def run(args,timeout=600):
    p=subprocess.run(list(map(str,args)),cwd=ROOT,env=ENV,capture_output=True,text=True,timeout=timeout)
    if p.returncode:raise RuntimeError((args,p.returncode,p.stdout[-4000:],p.stderr[-4000:]))
    return p

def reference():
    assert sha(JAR.read_bytes())=='4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d'
    assert sha(REF.read_bytes())=='3cbe8aa7780f14c1b37159a885710b04680e3b6c4ffa4975b4d8297015f11e7e'
    r=json.loads(REF.read_text());quads={};textures=[];entries={}
    with zipfile.ZipFile(JAR)as z:
        def load(id):
            n,p=id.split(':',1);name=f'assets/{n}/models/{p}.json'
            if name in entries:return
            b=z.read(name);assert b.decode()==r['inputs']['models'][id];entries[name]=b
            j=json.loads(b)
            if 'parent'in j:load(j['parent']if ':'in j['parent']else'minecraft:'+j['parent'])
        for id in IDS:
            load(id);bake=next(x for x in r['observations']['baked_variants']if x['input']=={'model':id})
            assert bake['status']=='ok'and bake['result']['quad_count']==6
            quads[id]=[q for d in DIRECTIONS for q in bake['result']['quad_groups'][d]]
            for q in quads[id]:assert q['sprite']==id and q['layer']=='SOLID'and q['tint_index']==-1 and q['material_flags']==0
            n,p=id.split(':',1);name=f'assets/{n}/textures/{p}.png';b=z.read(name);entries[name]=b
            with Image.open(io.BytesIO(b))as im:textures.append(np.array(im.convert('RGBA'),dtype=np.uint8))
    with (ROOT/'generated/reference_blocks.tsv').open()as file:
        states={r['identifier']:int(r['default_state_id'])for r in csv.DictReader(file,delimiter='\t')}
    palette=[states['minecraft:'+id]for id in ['air','stone','dirt','oak_planks']]
    return quads,textures,entries,palette

def baseline(palette,edited=False,shift=(0,0,0),eye_offset=.5):
    cells={(x,0,z):2 if x==2 else 1 for z in range(-3,3)for x in range(-3,3)}
    cells.update({(1,1,1):2,(2,1,2):3,(2,2,2):3})
    if edited:cells[(0,1,0)]=3;cells[(1,1,1)]=1
    origin=[shift[0]+eye_offset,shift[1]+1+unw(0x3fcf5c29),shift[2]-2.5]
    blocks=[[*(unsigned(a+b)for a,b in zip(point,shift)),palette[k],k-1]for point,k in sorted(cells.items(),key=lambda x:(x[0][2],x[0][1],x[0][0]))]
    return {'blocks':blocks,'origin':list(map(double_words,origin)),'camera':[0,0,0,0,0x3e4ccccd],'tick':1,'revision':48 if edited else 47}
def expected_snapshot(v):
    blocks=[]
    for b in v['blocks']:
        if 'origin'in v:
            positions=[word(float(Fraction(signed(cell))-Fraction.from_float(from_double_words(eye))))for cell,eye in zip(b[:3],v['origin'])]
        else:positions=b[:3]
        blocks.append([*positions,*b[3:]])
    return {'tick':v.get('tick',1),'revision':v.get('revision',47),'camera':v.get('camera',[0,0,0,0,0x3e4ccccd]),'blocks':blocks}
def model_states(palette):return {palette[1]:'minecraft:block/stone',palette[2]:'minecraft:block/dirt',palette[3]:'minecraft:block/oak_planks'}
def quad_words(q,origin=(0,0,0),order=0):
    result=[]
    for v in q['vertices']:
        result.extend(word(f(f(unw(int(x,16)))+f(unw(o))))for x,o in zip(v['position_f32'],origin))
        result.extend(int(x,16)for x in v['uv_f32'])
    return [*result,SLOTS[q['sprite']],0xffffffff,0xffffffff,int(q['default_directional_brightness_f32'],16),0,0,0,1,order]
def expected_quads(snapshot,palette,quads):
    output=[];states=model_states(palette)
    for b in snapshot['blocks']:
        for q in quads[states[b[3]]]:output.append(quad_words(q,b[:3],len(output)))
    return output

# Independent NumPy triangle/ray and image oracle, supplied with actual Java
# geometry and independent Pillow texels. No Bend parser/baker executes here.
def cross(a,b):return np.stack([a[...,1]*b[...,2]-a[...,2]*b[...,1],a[...,2]*b[...,0]-a[...,0]*b[...,2],a[...,0]*b[...,1]-a[...,1]*b[...,0]],axis=-1)
def dot(a,b):return a[...,0]*b[...,0]+(a[...,1]*b[...,1]+a[...,2]*b[...,2])
def directions(camera,w,h):
    x,y=np.meshgrid(np.arange(w,dtype=np.float32),np.arange(h,dtype=np.float32));yaw,pitch=map(unw,camera[3:]);sy,cy,sp,cp=map(f,(math.sin(yaw),math.cos(yaw),math.sin(pitch),math.cos(pitch)));scale=f(.7002075382)
    u=((x+f(.5))*f(2)/f(w)-f(1))*(scale*(f(w)/f(h)));v=(f(1)-(y+f(.5))*f(2)/f(h))*scale
    dx=-sy*cp+(cy*u+(-sy*sp)*v);dy=-sp+cp*v;dz=cy*cp+(sy*u+(cy*sp)*v);length=np.sqrt(dx*dx+(dy*dy+dz*dz),dtype=np.float32)
    return np.stack([dx/length,dy/length,dz/length],axis=-1).reshape(-1,3)
def triangle(vertices,origin,dirs):
    p=vertices[:,:3];uv=vertices[:,3:];a=p[1]-p[0];b=p[2]-p[0];pv=cross(dirs,b);det=dot(a,pv)
    with np.errstate(divide='ignore',invalid='ignore'):
        inv=f(1)/det;tvec=origin-p[0];u=dot(tvec,pv)*inv;qv=cross(tvec,a);v=dot(dirs,qv)*inv;t=dot(b,qv)*inv
        hit=(det>f(1e-8))&(u>=0)&(u<=1)&(v>=0)&(u+v<=1)&(t>=f(.0001))&(t<=f(64))
        coords=uv[0]+((uv[1]-uv[0])*u[:,None]+(uv[2]-uv[0])*v[:,None])
    return hit,t,coords

def image_oracle(snapshot,quads,textures,w,h):
    dirs=directions(snapshot['camera'],w,h);origin=np.array(list(map(unw,snapshot['camera'][:3])),dtype=np.float32);best=np.full(w*h,f(65),dtype=np.float32);orders=np.full(w*h,0xffffffff,dtype=np.uint32)
    bg=4284784875;out=np.tile([(bg>>shift)&255 for shift in (16,8,0)],(w*h,1)).astype(np.uint32)
    for words in quads:
        vertices=np.array([[unw(x)for x in words[i:i+5]]for i in range(0,20,5)],dtype=np.float32)
        first=triangle(vertices[:3],origin,dirs);second=triangle(vertices[[0,2,3]],origin,dirs);use=first[0]&(~second[0]|(first[1]<=second[1]));valid=first[0]|second[0];depth=np.where(use,first[1],second[1]);uv=np.where(use[:,None],first[2],second[2]);order=words[-1]
        hit=valid&((depth<best)|((depth==best)&(order<orders)))
        tex=textures[words[20]];height,width=tex.shape[:2];uv=np.clip(np.nan_to_num(uv,nan=0,posinf=0,neginf=0),0,1);xy=np.minimum(np.array([width-1,height-1]),(uv*np.array([width,height],dtype=np.float32)).astype(np.uint32));rgba=tex[xy[:,1],xy[:,0]].astype(np.uint32)
        shade=f(unw(words[23]));rgb=np.floor((rgba[:,:3]*np.uint32(65025)).astype(np.float32)/f(65025)*shade).astype(np.uint32)
        best[hit]=depth[hit];orders[hit]=order;out[hit]=rgb[hit]
    return out.astype(np.uint8).reshape(h,w,3).tobytes()

def archive(name,entries,prepare=False):
    p=BUILD/(name+'.zip')
    if prepare:
        with zipfile.ZipFile(p,'w',zipfile.ZIP_DEFLATED)as z:
            for k,v in entries.items():z.writestr(k,v)
    return p

def cases(entries,palette,prepare=False):
    configs=[];plans={}
    def planned_archive(name,source):
        path=archive(name,source,prepare);plans[str(path)]={k:sha(v)for k,v in source.items()};return path
    def view(id,v,**options):return {'id':id,'output':str(BUILD/(id+'.ppm')),**v,**options}
    def good(name,pal,views,path=JAR):configs.append({'id':name,'path':str(path),'palette':pal,'views':views})
    base=baseline(palette);views=[view('base',base),view('edited',baseline(palette,True)),view('tick_only',base,tick=12,revision=47),view('moved',baseline(palette,eye_offset=.25)),view('look',base,camera=[0,0,0,word(.35),word(.3)]),view('large64',base,width=64,height=48),view('large128',base,width=128,height=96)]
    for name,shift in [('far_positive',(29999990,255,29999990)),('far_negative',(-29999990,-64,-29999990)),('far_mixed',(29999990,0,-29999990))]:views.append(view(name,baseline(palette,shift=shift)))
    empty={'blocks':[],'camera':base['camera']};views.append(view('empty',empty))
    bad=[]
    def reject(id,v,error,**opts):bad.append(view(id,v,expected_error=error,**opts));bad.append(view(id+'_recovery',base))
    for id,state in [('unknown_state',0xfffffffe),('air_state',palette[0])]:reject(id,{'blocks':[[0,0,0,state,0]],'camera':base['camera']},'WorldMesh:MissingState:'+str(state))
    reject('absolute_camera',base,'WorldMesh:RelativeCamera:0',camera=[word(1),0,0,0,word(.2)])
    reject('nan_camera',base,'WorldMesh:RelativeCamera:0',camera=[0,0,0,0x7fc00000,word(.2)])
    reject('low_dimensions',base,'WorldMesh:Frame:0',width=3)
    reject('high_dimensions',base,'WorldMesh:Frame:0',height=1025)
    reject('nan_origin',{'blocks':[[0x7fc00000,0,0,palette[1],0]],'camera':base['camera']},'WorldMesh:BlockOrigin:0')
    reject('translated_bound',{'blocks':[[word(4096),0,0,palette[1],0]],'camera':base['camera']},'WorldMesh:TranslatedQuad:'+str(palette[1]))
    reject('quad_budget',{'blocks':[[0,0,0,palette[1],0]]*683,'camera':base['camera']},'WorldMesh:QuadLimit:'+str(palette[1]))
    reject('texture_validation',base,'Render:Textures',mode='bad-texture')
    good('official',palette,views+bad)
    for name,pal in [('remapped',[300,0xfffffffc,18,901]),('remapped_extremes',[0xffffffff,0,0x80000000,0xfffffffe])]:good(name,pal,[view(name,baseline(pal)),view(name+'_edited',baseline(pal,True))])
    valid=planned_archive('official-subset',entries);good('subset',palette,[view('subset',base)],valid)
    def failure(name,modified,error):configs.append({'id':name,'path':str(planned_archive(name,modified)),'palette':palette,'views':[],'expected_load_error':error})
    stone='assets/minecraft/models/block/stone.json';dirt='assets/minecraft/textures/block/dirt.png';stone_png='assets/minecraft/textures/block/stone.png'
    e=dict(entries);del e[stone];failure('missing_model',e,'Resource:MissingResource:')
    e=dict(entries);del e[dirt];failure('missing_texture',e,'Resource:MissingResource:')
    e=dict(entries);e[stone]=b'{bad}';failure('malformed_model',e,'Resource:JSON:')
    e=dict(entries);e[stone]=b'{"parent":"minecraft:block/stone"}';failure('parent_cycle',e,'Resource:ParentCycle:')
    e=dict(entries);e[stone_png+'.mcmeta']=b'{"texture":{"mipmap_strategy":"mean"}}';failure('frozen_metadata',e,'Resource:UnsupportedMetadata:')
    e=dict(entries);b=bytearray(e[stone_png]);b[-1]^=1;e[stone_png]=bytes(b);failure('png_crc',e,'Resource:PNG:')
    e=dict(entries);e[stone]=json.dumps({'textures':{'all':'minecraft:block/stone'},'elements':[{'from':[0,0,0],'to':[16,16,16],'rotation':{'origin':[8,8,8],'x':0,'y':13.5,'z':0},'faces':{d:{'texture':'#all','cullface':d}for d in DIRECTIONS[:-1]}}]}).encode();failure('unsupported_bake',e,'Bake:Unsupported:ElementEuler')
    configs.append({'id':'missing_archive','path':str(BUILD/'absent.zip'),'palette':palette,'views':[],'expected_load_error':'Resource:ArchiveOpen:'})
    for i,a in enumerate(range(4)):
        for b in range(a+1,4):
            pal=palette.copy();pal[b]=pal[a];configs.append({'id':'duplicate_palette_'+str(a)+str(b),'path':str(BUILD/'absent.zip'),'palette':pal,'views':[],'expected_load_error':'Palette:DuplicateState'})
    return configs,plans

def parse(stdout):
    data={'textures':{},'baked':{},'snapshots':{},'quads':{},'frames':{},'errors':{},'checksums':{},'times':{}}
    for line in stdout.splitlines():
        if not line:continue
        f=line.split('|');kind=f[0]
        if kind=='load-error':data['load_error']='|'.join(f[1:])
        elif kind=='assets':data['texture_count']=int(f[1]);data['palette']=list(map(int,f[2].split(',')))
        elif kind=='texture':data['textures'][f[1]]={'slot':int(f[2]),'dimensions':list(map(int,f[3].split(','))),'pixels':list(map(int,f[4].split(',')))}
        elif kind=='baked':data['baked'].setdefault(int(f[1]),[]).append({'index':int(f[2]),'sprite':f[3],'words':list(map(int,f[4].split(',')))})
        elif kind=='snapshot':data['snapshots'][f[1]]={'tick':int(f[2]),'revision':int(f[3]),'camera':list(map(int,f[4].split(','))),'blocks':[list(map(int,b.split(',')))for b in f[5].split(';')if b]}
        elif kind=='quad':data['quads'].setdefault(f[1],[]).append(list(map(int,f[3].split(','))))
        elif kind=='frame':data['frames'][f[1]]={'width':int(f[2]),'height':int(f[3]),'path':f[4]}
        elif kind=='error':data['errors'][f[1]]='|'.join(f[2:])
        elif kind=='checksum':data['checksums'][f[1]]=int(f[2])
        elif kind=='time':data['times'][f[1]]=int(f[2])
        else:raise AssertionError(('unexpected native record',line[:200]))
    return data

def verify(config,data,quads,textures):
    if 'expected_load_error'in config:
        assert data.get('load_error','').startswith(config['expected_load_error']),(config['id'],data.get('load_error'));return {'load_rejection':data['load_error']}
    assert 'load_error'not in data,(config['id'],data)
    assert data['palette']==config['palette']and data['texture_count']==3
    for name,tex in zip(IDS,textures):
        observed=data['textures'][name];h,w=tex.shape[:2];assert observed['slot']==SLOTS[name]and observed['dimensions']==[w,h,16]
        rgba=np.array(observed['pixels'],dtype=np.uint32);packed=(tex[:,:,3].astype(np.uint32)<<24)|(tex[:,:,0].astype(np.uint32)<<16)|(tex[:,:,1].astype(np.uint32)<<8)|tex[:,:,2].astype(np.uint32);assert np.array_equal(rgba,packed.reshape(-1)),(name,'decoded pixels')
    for state,model in model_states(config['palette']).items():
        actual=data['baked'][state];expected=[{'index':i,'sprite':q['sprite'],'words':quad_words(q)}for i,q in enumerate(quads[model])];assert actual==expected,(config['id'],state,'actual Java baked geometry differs')
    frames=[];translated=0;pixels=0;rejections=0
    for view in config['views']:
        id=view['id'];snap=expected_snapshot(view);assert data['snapshots'][id]==snap,(id,'relative snapshot differs')
        if 'expected_error'in view:
            assert data['errors'].get(id)==view['expected_error'],(id,data['errors'].get(id),view['expected_error']);assert id not in data['frames'];rejections+=1;continue
        assert id not in data['errors'];expected=expected_quads(snap,config['palette'],quads);assert data['quads'].get(id,[])==expected,(id,'translated Java quads differ');translated+=len(expected)
        w,h=view.get('width',32),view.get('height',24);frame=data['frames'][id];assert [frame['width'],frame['height']]==[w,h];image=image_oracle(snap,expected,textures,w,h)
        with Image.open(frame['path'])as im:assert im.format=='PPM'and im.size==(w,h);actual=im.convert('RGB').tobytes()
        assert actual==image,(id,'independent pixel oracle differs',sum(a!=b for a,b in zip(actual,image)))
        rgba=np.column_stack([np.frombuffer(actual,dtype=np.uint8).reshape(-1,3),np.full(w*h,255,dtype=np.uint8)]).tobytes();assert data['checksums'][id]==zlib.crc32(rgba),(id,'RGBA readback checksum');pixels+=w*h
        frames.append({'id':id,'width':w,'height':h,'rgb_sha256':sha(actual),'draw_readback_crc_ms':data['times'][id]})
    if config['id']=='official':
        hashes={x['id']:x['rgb_sha256']for x in frames}
        assert hashes['base']==hashes['tick_only']==hashes['far_positive']==hashes['far_negative']==hashes['far_mixed']
        assert hashes['edited']!=hashes['base']and hashes['moved']!=hashes['base']and hashes['look']!=hashes['base']
        for id in data['errors']:assert hashes[id+'_recovery']==hashes['base'],(id,'same-assets recovery differs')
    return {'frames':frames,'rendered_pixels':pixels,'translated_quads':translated,'draw_rejections':rejections,'texels':768,'actual_java_baked_quads':18}

def semantic_inputs(configs):
    values=copy.deepcopy(configs)
    for config in values:
        config.pop('expected_load_error',None)
        for view in config['views']:view.pop('expected_error',None)
    return values

def expected_labels(configs):
    return [{'id':c['id'],'load':c.get('expected_load_error'),
             'views':[{ 'id':v['id'],'error':v.get('expected_error') }for v in c['views']]}
            for c in configs]

def prepared_inputs(configs,plans,entries,case_path=None):
    case_path=case_path or BUILD/'cases.json'
    if not case_path.is_file():raise RuntimeError('Missing prepared cases; run --prepare-only')
    case_bytes=case_path.read_bytes()
    try:actual=json.loads(case_bytes)
    except (ValueError,UnicodeError)as error:raise RuntimeError('Invalid prepared cases; run --prepare-only')from error
    if actual!=configs:raise RuntimeError('Stale prepared semantic/expected-label generation; run --prepare-only')
    archives={}
    for name in sorted(set(c['path']for c in configs)):
        path=Path(name)
        if path==JAR:
            wanted={key:sha(value)for key,value in entries.items()};whole=True
        elif name in plans:wanted=plans[name];whole=False
        else:
            if path.exists():raise RuntimeError('Expected missing archive now exists: '+name)
            archives[name]={'absent':True};continue
        if not path.is_file():raise RuntimeError('Missing prepared archive '+name+'; run --prepare-only')
        try:
            with zipfile.ZipFile(path)as archive_file:
                names=archive_file.namelist()
                if not whole and (len(names)!=len(wanted)or set(names)!=set(wanted)):
                    raise RuntimeError('Prepared archive member generation differs: '+name)
                contents={key:sha(archive_file.read(key))for key in sorted(wanted)}
        except (OSError,KeyError,zipfile.BadZipFile)as error:
            raise RuntimeError('Invalid prepared archive '+name+'; run --prepare-only')from error
        if contents!=wanted:raise RuntimeError('Prepared archive content differs: '+name+'; run --prepare-only')
        archives[name]={'sha256':sha(path.read_bytes()),'bytes':path.stat().st_size,'selected_contents':contents}
    return {'case_file_sha256':sha(case_bytes),'canonical_cases_sha256':sha(canonical(actual)),
            'semantic_inputs_sha256':sha(canonical(semantic_inputs(actual))),
            'expected_labels_sha256':sha(canonical(expected_labels(actual))),'archives':archives}

def frame_expectations(configs,quads,textures):
    outputs=[]
    for config in configs:
        for v in config['views']:
            if 'expected_error'in v:continue
            snap=expected_snapshot(v);expected=expected_quads(snap,config['palette'],quads)
            pixels=image_oracle(snap,expected,textures,v.get('width',32),v.get('height',24))
            outputs.append({'id':v['id'],'rgb_sha256':sha(pixels),'quads':len(expected),
                            'quad_words_sha256':sha(canonical(expected))})
    return outputs

def preparation_record(configs,plans,entries,quads,textures,generation):
    return {'schema':'resource-frame-preparation-v1','runner_sha256':sha(Path(__file__).read_bytes()),
            'client_sha256':sha(JAR.read_bytes()),'reference_sha256':sha(REF.read_bytes()),
            'registry_inventory_sha256':sha((ROOT/'generated/reference_blocks.tsv').read_bytes()),
            'pillow':PILLOW,'native_source_fingerprint':generation,
            'inputs':prepared_inputs(configs,plans,entries),
            'expected_frames':frame_expectations(configs,quads,textures)}

def seal_preparation(record):
    payload={**record,'prepared_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
    write(BUILD/'preparation.json',{'payload':payload,'payload_sha256':sha(canonical(payload))})

def validate_preparation(configs,plans,entries,quads,textures,generation,manifest_path=None):
    manifest_path=manifest_path or BUILD/'preparation.json'
    if not manifest_path.is_file():raise RuntimeError('Missing prepared manifest; run --prepare-only')
    try:sealed=json.loads(manifest_path.read_text());payload=sealed['payload'];digest=sealed['payload_sha256']
    except (ValueError,UnicodeError,KeyError,TypeError)as error:
        raise RuntimeError('Invalid prepared manifest; run --prepare-only')from error
    if not isinstance(payload,dict)or not isinstance(digest,str):raise RuntimeError('Invalid prepared manifest; run --prepare-only')
    if digest!=sha(canonical(payload)):raise RuntimeError('Prepared manifest seal differs; run --prepare-only')
    expected=preparation_record(configs,plans,entries,quads,textures,generation)
    recorded={key:value for key,value in payload.items()if key!='prepared_at_utc'}
    if recorded!=expected:
        fields=[key for key in set(recorded)|set(expected)if recorded.get(key)!=expected.get(key)]
        raise RuntimeError('Stale prepared provenance/generation '+','.join(sorted(fields))+'; run --prepare-only')
    return sealed

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--prepare-only',action='store_true');ap.add_argument('--reuse-build',action='store_true');ap.add_argument('--skip-kernel',action='store_true');ap.add_argument('--build-only',action='store_true');ap.add_argument('--phase',choices=['all',*PHASES],default='all');args=ap.parse_args();BUILD.mkdir(parents=True,exist_ok=True)
    quads,textures,entries,palette=reference()
    if args.prepare_only:entrypoints(True)
    configs,plans=cases(entries,palette,args.prepare_only);generation=fingerprint()
    if args.prepare_only:
        write(BUILD/'cases.json',configs)
        prepared=preparation_record(configs,plans,entries,quads,textures,generation)
        seal_preparation(prepared)
        outputs=[{key:value for key,value in frame.items()if key!='quad_words_sha256'}for frame in prepared['expected_frames']]
        write(ROOT/'evidence/resource-frame-preflight.json',{'status':'prepared-native-unverified','configs':len(configs),'expected_frames':outputs,'native_source_fingerprint':generation,'reference_sha256':sha(REF.read_bytes()),'command':'python3 tools/test_resource_frame.py --prepare-only','native_entries':{k:str(v.relative_to(ROOT))for k,v in entrypoints().items()},'prepared_manifest_sha256':sha((BUILD/'preparation.json').read_bytes())})
        print({'configs':len(configs),'expected_frames':len(outputs),'status':'prepared-native-unverified'});return
    prepared=validate_preparation(configs,plans,entries,quads,textures,generation)
    prepared_manifest_sha256=sha((BUILD/'preparation.json').read_bytes())
    check=run([BEND,'tests/resource_frame.bend','--check-only'],60);assert 'ALL PROOFS CHECK'in check.stdout
    kernel={'status':'not-run','reason':'explicit --skip-kernel'}
    if not args.skip_kernel:
        try:
            p=subprocess.run([str(BEND),'src/resource_frame.bend','--verdict'],cwd=ROOT,env=ENV,capture_output=True,text=True,timeout=60);out=p.stdout+p.stderr;kernel={'status':'passed'if p.returncode==0 and 'ALL PROOFS CHECK'in out else 'compiler-kernel-mismatch'if 'mismatch between the TypeScript implementation'in out else 'failed','exit_code':p.returncode,'output':out};assert kernel['status']!='failed',kernel
        except subprocess.TimeoutExpired:kernel={'status':'inconclusive-timeout','timeout_seconds':60}
    selected=list(PHASES)if args.phase=='all'else[args.phase]
    entries=entrypoints();builds={}
    for phase in selected:
        name,binary=PHASES[phase];stamp=BUILD/(phase+'-native-build.json')
        if args.reuse_build:
            saved=json.loads(stamp.read_text());assert saved['sources']==generation and saved['binary_sha256']==sha(binary.read_bytes())
            if 'prepared_manifest_sha256'in saved:assert saved['prepared_manifest_sha256']==prepared_manifest_sha256,'Prepared generation differs from native build receipt'
            builds[phase]=saved;print({'phase':phase,'status':'exact-native-artifact-reused','binary_sha256':saved['binary_sha256']},flush=True)
        else:
            started=time.monotonic();run([BEND,entries[phase],'-o',binary]);duration=time.monotonic()-started;assert fingerprint()==generation
            builds[phase]={'sources':generation,'binary_sha256':sha(binary.read_bytes()),'binary_bytes':binary.stat().st_size,'build_seconds':duration,'entry':str(entries[phase].relative_to(ROOT)),'prepared_manifest_sha256':prepared_manifest_sha256,'runner_sha256':sha(Path(__file__).read_bytes())}
            write(stamp,builds[phase]);print({'phase':phase,'status':'native-built-unverified','build_seconds':duration,'binary_sha256':builds[phase]['binary_sha256']},flush=True)
    if args.build_only:return
    assert args.phase=='all','Full verification requires all three entries'
    build_seconds=sum(v['build_seconds']for v in builds.values())
    all_rows=[];details=[];elapsed=[]
    for pass_index in range(2):
        rows=[];summaries=[];started=time.monotonic()
        for config in configs:
            encoded=json.dumps(config,separators=(',',':'));data=parse(run([PHASES['audit'][1],'--threads','1',encoded],120).stdout)
            if 'expected_load_error'not in config:
                draw=parse(run([PHASES['draw'][1],'--threads','1',encoded],120).stdout);geometry=parse(run([PHASES['geometry'][1],'--threads','1',encoded],120).stdout)
                assert 'load_error'not in draw and 'load_error'not in geometry,(config['id'],'entry load disagreement')
                for key in ['snapshots','frames','errors','checksums','times']:data[key]=draw[key]
                data['quads']=geometry['quads']
            summaries.append({'id':config['id'],**verify(config,data,quads,textures)});data.pop('times');rows.append(data)
        elapsed.append(time.monotonic()-started);all_rows.append(rows);details.append(summaries)
    assert all_rows[0]==all_rows[1],'Native values differ between runs';assert fingerprint()==generation,'Source changed during verification'
    evidence={'status':'passed_bounded_domain','configs':len(configs),'two_native_runs_equal':True,'canonical_report_sha256':sha(canonical(all_rows[0])),'build_seconds':build_seconds,'native_run_seconds':elapsed,'native_artifacts':builds,'prepared_manifest_sha256':prepared_manifest_sha256,'prepared_input_generation':prepared['payload']['inputs'],'native_source_fingerprint':generation,'reference_sha256':sha(REF.read_bytes()),'client_sha256':sha(JAR.read_bytes()),'pillow':PILLOW,'ordinary':check.stdout.strip(),'kernel':kernel,'passes':details,'source_sha256':{p:sha((ROOT/p).read_bytes())for p in ['src/resource_frame.bend','tests/resource_frame.bend','tools/test_resource_frame.py']},'boundary':'Real official ZIP/JSON/PNG parsing and Bend baking, explicit zero-transform three-material fixture selection. Controlled normalized textures, white tint/light, cardinal shade, current CPU RGB arithmetic. Java geometry fixture + Pillow pixel inputs + independent CPU ray oracle; not production atlas/GPU/final vanilla frame. No Window launch.','command':'python3 tools/test_resource_frame.py'+(' --skip-kernel'if args.skip_kernel else '')+(' --reuse-build'if args.reuse_build else '')}
    write(ROOT/'evidence/resource-frame-native.json',evidence);print({'status':evidence['status'],'configs':len(configs),'build_seconds':build_seconds,'native_run_seconds':elapsed,'report_sha256':evidence['canonical_report_sha256']})
if __name__=='__main__':main()
