#!/usr/bin/env python3
"""Native Bend baked-quad verification; Python is only an independent oracle.

Actual Java-produced vertex/UV bits are supplied as test inputs. No Java game
code, Python model baker or image decoder is part of the Bend renderer.
"""
from __future__ import annotations
import datetime,hashlib,json,math,os,struct,subprocess,sys,time,zipfile,zlib
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
PYTHON=Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
if Path(sys.executable).resolve()!=PYTHON.resolve():
    os.execv(str(PYTHON),[str(PYTHON),__file__,*sys.argv[1:]])
import numpy as np
from PIL import Image

BEND=Path.home()/'.bend/bin/bend'
JAR=Path.home()/'Library/Application Support/minecraft/versions/26.3/26.3.jar'
REFERENCE=ROOT/'reference/model_semantics.json'
BUILD=ROOT/'build'

def sha(data):return hashlib.sha256(data).hexdigest()
def f(x):return struct.unpack('<f',struct.pack('<f',x))[0]
def bits(x):return struct.unpack('<I',struct.pack('<f',x))[0]
def unbits(x):return struct.unpack('<f',struct.pack('<I',int(x,16) if isinstance(x,str) else x))[0]
def fcode(x):return f'raw({bits(x)})'
def vec(v):return 'M.Vec3{'+','.join(map(fcode,v))+'}'
def vertex(v):return f'M.Vertex{{{vec(v[0])},M.UV{{{fcode(v[1][0])},{fcode(v[1][1])}}}}}'
def material(m):
    mode='M.Cutout{'+str(m['threshold'])+'}' if m['mode']=='Cutout' else 'M.'+m['mode']+'{}'
    return f'M.Material{{{m["texture"]},{m["tint"]},{m["light"]},{fcode(m["shade"])},{mode},M.{m["address"]}{{}}}}'
def quadcode(q):return 'M.Quad{'+','.join([*(vertex(v) for v in q['vertices']),material(q['material']),'M.'+q['cull']+'{}',str(q['order'])])+'}'
def settingscode(s):return 'M.Settings{'+','.join(map(fcode,s[:3]))+','+str(s[3])+'}'
def scenecode(s):return 'M.Scene{R.Camera{'+','.join(map(fcode,s['camera']))+'},['+','.join(map(quadcode,s['quads']))+'],'+settingscode(s['settings'])+'}'

def mat(texture,mode='Opaque',tint=0xffffffff,light=0xffffffff,shade=1,address='Clamp',threshold=128):
    return dict(texture=texture,mode=mode,tint=tint,light=light,shade=f(shade),address=address,threshold=threshold)
def plane(z,material,order=0,cull='Back',uv=(0,0,1,1)):
    u0,v0,u1,v1=uv
    return dict(vertices=[((1,1,z),(u0,v0)),((1,-1,z),(u0,v1)),((-1,-1,z),(u1,v1)),((-1,1,z),(u1,v0))],material=material,order=order,cull=cull)
DEFAULT=(f(.0001),f(64),f(.7002075382),0xff64a0eb)
def scene(quads,camera=(0,0,0,0,0),settings=DEFAULT):return dict(quads=quads,camera=tuple(map(f,camera)),settings=settings)

def production_quad(raw,slots,order):
    return dict(vertices=[(tuple(map(unbits,v['position_f32'])),tuple(map(unbits,v['uv_f32']))) for v in raw['vertices']],
                material=mat(slots[raw['sprite']],{'SOLID':'Opaque','CUTOUT':'Cutout','TRANSLUCENT':'Translucent'}[raw['layer']],
                             tint=0xff78b44a if raw['tint_index']>=0 else 0xffffffff,
                             shade=unbits(raw['default_directional_brightness_f32'])),cull='Back',order=order+(0 if raw['layer']=='CUTOUT' else 1048576))

def transform(q,offset):
    q={**q,'vertices':[(tuple(f(x+y) for x,y in zip(p,offset)),uv) for p,uv in q['vertices']]}
    return q

def directions(camera,w,h,scale):
    x,y=np.meshgrid(np.arange(w,dtype=np.float32),np.arange(h,dtype=np.float32))
    yaw,pitch=camera[3:];sy,cy,sp,cp=map(np.float32,(math.sin(yaw),math.cos(yaw),math.sin(pitch),math.cos(pitch)))
    u=((x+np.float32(.5))*np.float32(2)/np.float32(w)-np.float32(1))*(np.float32(scale)*(np.float32(w)/np.float32(h)))
    v=(np.float32(1)-(y+np.float32(.5))*np.float32(2)/np.float32(h))*np.float32(scale)
    dx=-sy*cp+(cy*u+(-sy*sp)*v);dy=-sp+cp*v;dz=cy*cp+(sy*u+(cy*sp)*v)
    length=np.sqrt(dx*dx+(dy*dy+dz*dz),dtype=np.float32)
    return np.stack([dx/length,dy/length,dz/length],axis=-1).reshape(-1,3)

def cross(a,b):
    return np.stack([a[...,1]*b[...,2]-a[...,2]*b[...,1],a[...,2]*b[...,0]-a[...,0]*b[...,2],a[...,0]*b[...,1]-a[...,1]*b[...,0]],axis=-1)
def dot(a,b):return a[...,0]*b[...,0]+(a[...,1]*b[...,1]+a[...,2]*b[...,2])
def triangle_hits(vertices,origin,direction,cull,settings):
    p=np.array([v[0] for v in vertices],dtype=np.float32);uv=np.array([v[1] for v in vertices],dtype=np.float32)
    e1=p[1]-p[0];e2=p[2]-p[0];pv=cross(direction,e2);det=dot(e1,pv)
    valid=det>np.float32(1e-8) if cull=='Back' else np.abs(det)>np.float32(1e-8)
    with np.errstate(divide='ignore',invalid='ignore'):
        inv=np.float32(1)/det;tvec=origin-p[0];u=dot(tvec,pv)*inv;qv=cross(tvec,e1);v=dot(direction,qv)*inv;t=dot(e2,qv)*inv
        valid&=(u>=0)&(u<=1)&(v>=0)&(u+v<=1)&(t>=settings[0])&(t<=settings[1])
        coords=uv[0]+((uv[1]-uv[0])*u[:,None]+(uv[2]-uv[0])*v[:,None])
    return valid,t,coords
def quad_hits(q,origin,direction,settings):
    v=q['vertices'];a=triangle_hits(v[:3],origin,direction,q['cull'],settings);b=triangle_hits([v[0],v[2],v[3]],origin,direction,q['cull'],settings)
    use=a[0]&(~b[0]|(a[1]<=b[1]))
    return a[0]|b[0],np.where(use,a[1],b[1]),np.where(use[:,None],a[2],b[2])

def color_sample(m,coords,textures):
    image=textures[m['texture']];h,w=image.shape[:2]
    coords=np.nan_to_num(coords,nan=0,posinf=0,neginf=0)
    coords=np.clip(coords,0,1) if m['address']=='Clamp' else coords-np.floor(coords)
    xy=np.minimum(np.array([w-1,h-1]),(coords*np.array([w,h],dtype=np.float32)).astype(np.uint32))
    rgba=image[xy[:,1],xy[:,0]].astype(np.uint32)
    tint=np.array([(m['tint']>>s)&255 for s in (16,8,0,24)],dtype=np.uint32)
    light=np.array([(m['light']>>s)&255 for s in (16,8,0)],dtype=np.uint32)
    rgb=np.floor((rgba[:,:3]*tint[:3]*light).astype(np.float32)/np.float32(65025)*np.float32(m['shade'])).astype(np.uint32)
    alpha=rgba[:,3]*tint[3]//255
    return np.column_stack([rgb,alpha])

def reference(scene,w,h,textures):
    n=w*h;dirs=directions(scene['camera'],w,h,scene['settings'][2]);origin=np.array(scene['camera'][:3],dtype=np.float32)
    background=scene['settings'][3];out=np.tile([(background>>s)&255 for s in (16,8,0)],(n,1)).astype(np.uint32)
    best=np.full(n,np.float32(scene['settings'][1])+np.float32(1),dtype=np.float32)
    order=np.full(n,0xffffffff,dtype=np.uint32);index=np.full(n,0xffffffff,dtype=np.uint32)
    translucent=[]
    for i,q in enumerate(scene['quads']):
        valid,depth,coords=quad_hits(q,origin,dirs,scene['settings']);color=color_sample(q['material'],coords,textures);o=q['order'];m=q['material']
        before=(depth<best)|((depth==best)&((o<order)|((o==order)&(i<index))))
        if m['mode']=='Translucent':translucent.append((valid,depth,o,i,color));continue
        coverage=np.ones(n,dtype=bool) if m['mode']=='Opaque' else color[:,3]>=m['threshold']
        hit=valid&before&coverage;best[hit]=depth[hit];order[hit]=o;index[hit]=i;out[hit]=color[hit,:3]
    # Independent host sorting oracle. Runtime Bend sorts only bounded trans hits.
    for pixel in range(n):
        hits=[]
        for valid,depth,o,i,color in translucent:
            key=(float(depth[pixel]),o,i)
            if valid[pixel] and color[pixel,3] and key<(float(best[pixel]),int(order[pixel]),int(index[pixel])):hits.append((key,color[pixel]))
        for key,color in sorted(hits,key=lambda x:x[0],reverse=True):
            alpha=int(color[3]);out[pixel]=(color[:3]*alpha+out[pixel]*(255-alpha))//255
    return out.astype(np.uint8).reshape(h,w,3).tobytes()

def plane_oracle(q,origin,direction,settings):
    """Alternative double precision plane intersection + Gram barycentrics."""
    hits=[];p=np.array([v[0] for v in q['vertices']],dtype=np.float64);uv=np.array([v[1] for v in q['vertices']],dtype=np.float64)
    for ids in ((0,1,2),(0,2,3)):
        a,b,c=p[list(ids)];e1=b-a;e2=c-a;normal=np.cross(e1,e2);den=float(np.dot(normal,direction))
        if (q['cull']=='Back' and den>=-1e-8) or abs(den)<=1e-8:continue
        t=float(np.dot(normal,a-origin))/den
        if not settings[0]<=t<=settings[1]:continue
        rel=origin+direction*t-a
        g11=np.dot(e1,e1);g22=np.dot(e2,e2);g12=np.dot(e1,e2);d1=np.dot(rel,e1);d2=np.dot(rel,e2);disc=g11*g22-g12*g12
        if not disc:continue
        u=(d1*g22-d2*g12)/disc;v=(d2*g11-d1*g12)/disc
        if u>=-1e-10 and v>=-1e-10 and u+v<=1+1e-10:
            coords=uv[ids[0]]+(uv[ids[1]]-uv[ids[0]])*u+(uv[ids[2]]-uv[ids[0]])*v;hits.append((t,*coords))
    return min(hits,key=lambda x:x[0]) if hits else None

def run(args,timeout=240):
    started=time.monotonic();env={**os.environ,'BEND_MINECRAFT_LAUNCH_MODE':'hidden'}
    p=subprocess.run(list(map(str,args)),cwd=ROOT,text=True,capture_output=True,env=env,timeout=timeout)
    if p.returncode:raise RuntimeError(f'{args}\n{p.stdout[-5000:]}\n{p.stderr[-5000:]}')
    return p.stdout,p.stderr,time.monotonic()-started

def main():
    BUILD.mkdir(exist_ok=True)
    fixture=json.loads(REFERENCE.read_text());variants=fixture['observations']['baked_variants']
    sprites=sorted({q['sprite'] for b in variants for group in b['result']['quad_groups'].values() for q in group})
    slots={s:i for i,s in enumerate(sprites)};names=['assets/'+s.split(':')[0]+'/textures/'+s.split(':')[1]+'.png' for s in sprites]
    textures=[]
    with zipfile.ZipFile(JAR) as jar:
        assert sha(JAR.read_bytes())=='4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d'
        for name in names:
            import io
            textures.append(np.array(Image.open(io.BytesIO(jar.read(name))).convert('RGBA'),dtype=np.uint8))
    extras=[np.array([[[255,0,0,255],[0,255,0,0]],[[0,0,255,128],[255,255,255,255]]],dtype=np.uint8),np.array([[[255,0,0,128]]],dtype=np.uint8),np.array([[[0,255,0,64]]],dtype=np.uint8),np.array([[[255,255,0,255]]],dtype=np.uint8)]
    base=len(textures);textures+=extras
    models=[];rays=[];frames=[]
    for i,b in enumerate(variants):
        qs=[production_quad(q,slots,j) for j,q in enumerate(q for group in b['result']['quad_groups'].values() for q in group)]
        models.append((b['input'],qs))
        frames.append((f'model-{i}',scene(qs,(.5,1.4,-2.5,0,.22)),24,24,None))
        for j,q in enumerate(qs):
            p=np.array([v[0] for v in q['vertices']],dtype=np.float64);normal=np.cross(p[1]-p[0],p[2]-p[0]);normal/=np.linalg.norm(normal)
            point=p[0]+.2*(p[1]-p[0])+.3*(p[2]-p[0])
            for kind in ('front','front2','diagonal','back','outside'):
                target=p[0]+.2*(p[2]-p[0])+.3*(p[3]-p[0]) if kind=='front2' else p[0]+.5*(p[2]-p[0]) if kind=='diagonal' else point if kind!='outside' else p[0]+2*(p[1]-p[0])+2*(p[2]-p[0])
                origin=np.array([f(x) for x in target+normal*(2 if kind!='back' else -2)],dtype=np.float64)
                direction=np.array([f(x) for x in normal*(-1 if kind!='back' else 1)],dtype=np.float64)
                rays.append((f'{i}-{j}-{kind}',q,origin,direction,plane_oracle(q,origin,direction,DEFAULT)))
    syn=[]
    syn.append(('alpha-opaque',scene([plane(2,mat(base))])))
    syn.append(('alpha-cutout',scene([plane(2,mat(base,'Cutout',threshold=129)),plane(3,mat(base+3))])))
    syn.append(('alpha-translucent',scene([plane(2,mat(base,'Translucent')),plane(3,mat(base+3))])))
    syn.append(('wrap-repeat',scene([plane(2,mat(base,address='Repeat'),uv=(-.5,-.5,1.5,1.5))])))
    syn.append(('wrap-clamp',scene([plane(2,mat(base,address='Clamp'),uv=(-.5,-.5,1.5,1.5))])))
    syn.append(('tint-light',scene([plane(2,mat(base+3,tint=0xff80ff40,light=0xfff09070,shade=.6))])))
    a=plane(2,mat(base+1,'Translucent'),order=7);b=plane(2,mat(base+2,'Translucent'),order=3)
    syn.extend([('tie-trans-a',scene([a,b])),('tie-trans-b',scene([b,a])),('tie-solid-a',scene([plane(2,mat(base+1),order=7),plane(2,mat(base+2),order=3)])),('tie-solid-b',scene([plane(2,mat(base+2),order=3),plane(2,mat(base+1),order=7)])),('occluded-trans',scene([plane(2,mat(base+3)),plane(3,mat(base+1,'Translucent'))])),('two-layers',scene([plane(2,mat(base+1,'Translucent')),plane(3,mat(base+2,'Translucent'))])),('near-clip',scene([plane(f(.00001),mat(base+3))])),('far-clip',scene([plane(65,mat(base+3))])),('back-cull',scene([plane(2,mat(base+3),cull='Back')],(0,0,4,math.pi,0))),('no-cull',scene([plane(2,mat(base+3),cull='NoCull')],(0,0,4,math.pi,0)))])
    syn.append(('degenerate',scene([{**plane(2,mat(base+3)), 'vertices':[((0,0,2),(0,0))]*4}])))
    syn.append(('duplicate-order',scene([plane(2,mat(base+1,'Translucent'),order=5),plane(2,mat(base+2,'Translucent'),order=5)])))
    for name,s in syn:frames.append((name,s,32,32,None))
    frames.append(('rectangular',scene([plane(2,mat(base,'Translucent')),plane(3,mat(base+3))],(.25,.15,0,.12,.08)),31,17,None))
    frames.append(('minimal-rectangular',scene([plane(2,mat(base+3))]),4,7,None))
    def find(model,**kw):return next(q for raw,q in models if raw.get('model')=='minecraft:block/'+model and all(raw.get(k,0 if k in ('x','y','z') else False)==v for k,v in kw.items()))
    practical=[]
    for z in range(6):
        for x in range(6):practical.extend(transform(q,(x-3,-1,z)) for q in find('stone',x=0,y=0,uvlock=False))
    for model,offset,kw in [('oak_slab',(-2,0,2),{}),('oak_stairs',(-1,0,3),{'y':90,'uvlock':True}),('oak_stairs_inner',(0,0,4),{'y':180,'uvlock':True}),('oak_fence_post',(1,0,3),{}),('oak_fence_side',(1,0,3),{'y':90,'uvlock':True}),('grass_block',(-1,0,1),{}),('glass',(1,0,1),{})]:practical.extend(transform(q,offset) for q in find(model,**kw))
    for i,q in enumerate(practical):q['order']=i+(0 if q['material']['mode']=='Cutout' else 1048576)
    ps=scene(practical,(.5,2.25,-3,0,.30))
    for size in (64,128):
        for sample in range(4):frames.append((f'practical-{size}-{sample}',ps,size,size,None))
    for size in (64,128):
        for sample in range(3):frames.append((f'empty-{size}-{sample}',scene([]),size,size,None))
    invalid=[]
    def bad(name,s,w=4,h=4,code='Vertex'):invalid.append((name,s,w,h,code))
    q=plane(2,mat(base+3));bad('nan-vertex',scene([{**q,'vertices':[((float('nan'),1,2),(0,0)),*q['vertices'][1:]]}]))
    bad('inf-uv',scene([{**q,'vertices':[(q['vertices'][0][0],(float('inf'),0)),*q['vertices'][1:]]}]))
    bad('position-bound',scene([transform(q,(4096,0,0))]))
    bad('texture-slot',scene([plane(2,mat(len(textures)))]),code='Material')
    bad('invalid-cutout',scene([plane(2,mat(base,'Cutout',threshold=256))]),code='Material')
    bad('invalid-light',scene([plane(2,mat(base,light=0x00808080))]),code='Material')
    bad('negative-shade',scene([plane(2,mat(base,shade=-.1))]),code='Material')
    bad('nan-camera',scene([q],(float('nan'),0,0,0,0)),code='Camera')
    bad('bad-settings',scene([q],settings=(0,64,DEFAULT[2],DEFAULT[3])),code='Settings')
    bad('bad-size',scene([q]),0,4,'Dimensions')
    bad('too-many-layers',scene([plane(2+i*.1,mat(base+1,'Translucent')) for i in range(65)]),code='Limits')
    bad('too-many-quads',scene([q]*4097),code='Limits')
    bad('uv-bound',scene([{**q,'vertices':[(q['vertices'][0][0],(65537,0)),*q['vertices'][1:]]}]))
    bad('nan-shade',scene([plane(2,mat(base,shade=float('nan')))]),code='Material')
    frames+=invalid
    recovery=[('recovery',scene([q]),8,8,None)]
    defs=['import Base','import ../src/client_render.bend as R','import ../src/mesh_render.bend as M','import ../src/png.bend as P',
          'def jar() -> String:\n  '+json.dumps(str(JAR)),
          'def names() -> List<&2,String>:\n  '+json.dumps(names,separators=(',',':'))]
    defs.append('def draw(scene:M.Scene,assets:R.Assets,width:U32,height:U32) -> R.Assets & Result<&2,&2,M.Error,Image>:\n  M.'+('render_flat' if '--flat' in sys.argv else 'render')+'(scene,assets,width,height)')
    extra_codes=[]
    for image in extras:
        h,w=image.shape[:2];pixels=[int(a)<<24|int(r)<<16|int(g)<<8|int(b) for r,g,b,a in image.reshape(-1,4)]
        extra_codes.append(f'R.texture(P.Decoded{{{w},{h},{json.dumps(pixels,separators=(",",":"))}}})')
    defs.append('def augment(assets:R.Assets) -> R.Assets:\n  R.Assets{textures} = assets\n  R.Assets{List.append(&2,R.Texture,textures,['+','.join(extra_codes)+'])}')
    defs.append('def frame_name(index:U32) -> String:\n  match index:\n'+''.join(f'    case {i}: '+json.dumps(fr[0])+'\n' for i,fr in enumerate(frames+recovery))+'    case _: "invalid"')
    generated=BUILD/'mesh-render-fixtures.bend';generated.write_text('\n\n'.join(defs)+'\n')
    words=[]
    def qwords(q):
        out=[bits(x) for p,uv in q['vertices'] for x in (*p,*uv)];m=q['material']
        return out+[m['texture'],m['tint'],m['light'],bits(m['shade']),{'Opaque':0,'Cutout':1,'Translucent':2}[m['mode']],m['threshold'],0 if m['address']=='Clamp' else 1,0 if q['cull']=='Back' else 1,q['order']]
    words.append(len(rays))
    for name,q,o,d,e in rays:words+=qwords(q)+[bits(x) for x in (*o,*d)]
    words.append(len(frames+recovery))
    for name,s,w,h,error in frames+recovery:
        words += [w,h]+[bits(x) for x in s['camera']]+[bits(x) for x in s['settings'][:3]]+[s['settings'][3],len(s['quads'])]
        for q in s['quads']:words+=qwords(q)
    binary_fixture=BUILD/'mesh-render-fixtures.bin';binary_fixture.write_bytes(struct.pack('<'+'I'*len(words),*words))
    check=run([BEND,'src/mesh_render.bend','--verdict']);driver=run([BEND,'tests/mesh_render.bend','--check-only'])
    native=BUILD/'mesh-render-test';build=run([BEND,'tests/mesh_render.bend','-o',native],timeout=360)
    output,errors,elapsed=run([native,'--gpuoff'],timeout=360)
    (BUILD/'mesh-render-output.txt').write_text(output)
    reports={};ray_reports={}
    for line in output.splitlines():
        a=line.split('|')
        if a[0]=='ray':ray_reports[a[1]]=None if a[2]=='none' else tuple(unbits(int(x)) for x in a[2].split(','))
        if a[0]=='frame':reports.setdefault(a[1],{})[a[2]]=a[3]
    assert len(ray_reports)==len(rays),(len(ray_reports),len(rays))
    max_error=0
    for ray_index,(name,q,o,d,e) in enumerate(rays):
        got=ray_reports[str(ray_index)];assert (got is None)==(e is None),(name,got,e)
        if got is not None:
            error=max(abs(a-b) for a,b in zip(got,e));max_error=max(max_error,error);assert error<=2e-5,(name,got,e,error)
    analytical={'alpha-opaque':(0,0,255),'alpha-cutout':(255,255,0),'alpha-translucent':(127,127,128),'tint-light':(72,86,0),'tie-solid-a':(0,255,0),'tie-solid-b':(0,255,0),'tie-trans-a':(132,123,87),'tie-trans-b':(132,123,87),'duplicate-order':(164,91,87),'two-layers':(164,91,87)}
    verified=[];pixel_count=0
    for name,s,w,h,error in frames+recovery:
        result=reports[name]
        if error:assert result.get('error')==error,(name,result,error);continue
        assert 'error' not in result,(name,result)
        image=Image.open(BUILD/f'mesh-render-{name}.ppm');got=image.convert('RGB').tobytes();expected=reference(s,w,h,textures)
        if got!=expected:
            mismatches=np.flatnonzero(np.frombuffer(got,dtype=np.uint8)!=np.frombuffer(expected,dtype=np.uint8))
            raise AssertionError((name,len(mismatches),int(mismatches[0]),got[int(mismatches[0])],expected[int(mismatches[0])]))
        rgba=np.column_stack([np.frombuffer(expected,dtype=np.uint8).reshape(-1,3),np.full(w*h,255,dtype=np.uint8)]).astype(np.uint8).tobytes()
        assert int(result['crc'])==zlib.crc32(rgba),(name,result['crc'],zlib.crc32(rgba))
        if name in analytical:
            at=((h//2)*w+w//2)*3;assert tuple(got[at:at+3])==analytical[name],(name,tuple(got[at:at+3]),analytical[name])
        pixel_count+=w*h;verified.append(dict(name=name,width=w,height=h,quads=len(s['quads']),rgb_sha256=sha(got),render_ms=int(result['ms'])))
        if name=='practical-128-3':image.save(BUILD/'mesh-render-practical.png')
    hashes={p:sha((ROOT/p).read_bytes()) for p in ('src/mesh_render.bend','tests/mesh_render.bend','tools/test_mesh_render.py','src/client_render.bend','src/png.bend','reference/model_semantics.json')}
    evidence=dict(date=datetime.datetime.now().astimezone().date().isoformat(),status='pass',algorithm='flat' if '--flat' in sys.argv else 'spatial hierarchy',confidence='high for supplied baked geometry and this explicit CPU algorithm',
                  source_sha256=hashes,jar_sha256=sha(JAR.read_bytes()),fixture_sha256=sha(generated.read_bytes()),raw_bit_fixture_sha256=sha(binary_fixture.read_bytes()),
                  geometry=dict(actual_java_variants=len(variants),actual_java_quads=sum(len(q) for _,q in models),ray_cases=len(rays),alternative_plane_oracle_max_absolute_error=max_error),
                  pixels=dict(exact_rgb_pixels=pixel_count,cases=verified,analytical_center_rgb=analytical),invalid_scene_cases=[dict(name=a[0],code=a[4]) for a in invalid],assets_recovered_after_errors=True,
                  timings=dict(build_seconds=build[2],native_seconds=elapsed),no_window_opened=True,
                  material_policy=dict(cutout_threshold=128,grass_tint_argb='ff78b44a',light_argb='ffffffff',coplanar_cutout_order='lower supplied order than opaque base; explicit fixture policy, not measured Java draw ordering'),
                  boundaries=['Java model baking supplies test inputs only; no Bend baker/runtime model load integration claimed','CPU binary32 triangle rays, integer color and alpha composition are defined here; Java raster/sRGB/lightmap/AO/frame equivalence unmeasured','Tint/light are explicit fixture inputs, not biome/world measurements','Coordinates are supplied in one finite frame; authoritative world-to-camera subtraction remains integration responsibility'])
    (ROOT/('evidence/mesh-render-flat.json' if '--flat' in sys.argv else 'evidence/mesh-render-native.json')).write_text(json.dumps(evidence,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(status='pass',rays=len(rays),pixels=pixel_count,practical_quads=len(practical),profile=[v for v in verified if v['name'].startswith('practical')]),indent=2))

if __name__=='__main__':main()
