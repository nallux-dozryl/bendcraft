#!/usr/bin/env python3
"""Actual Tile/Mesh CPU parity, retained Java quad inputs and existing pixel oracle."""
from __future__ import annotations
import argparse,io,json,os,sys,zipfile
from pathlib import Path
PYTHON=Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
if Path(sys.executable).resolve()!=PYTHON.resolve():
    os.execv(str(PYTHON),[str(PYTHON),__file__,*sys.argv[1:]])
import test_mesh_render as Old
import test_local_player_session as S
from build_native import Snapshot,source_graph
ROOT=Old.ROOT
ENTRY=ROOT/'tests/mesh_tile_render.bend'
FIXTURE=ROOT/'build/mesh-tile-render/fixture-001/fixtures.bend'
BEND=Path('/Users/chuah/.bend/bin/bend')

def generation():
    snapshot=Snapshot();source_graph(ENTRY,BEND.resolve().parent.parent/'bend2/base.bend',{},snapshot)
    return snapshot.manifest()

def prepare(directory):
    variants=json.loads(Old.REFERENCE.read_text())['observations']['baked_variants']
    chosen=[next(v for v in variants if v['input'].get('model')=='minecraft:block/'+model and not v['input'].get('x',0) and not v['input'].get('y',0) and not v['input'].get('uvlock',False)) for model in ['stone','glass']]
    sprites=sorted({q['sprite'] for v in chosen for group in v['result']['quad_groups'].values() for q in group})
    slots={s:i for i,s in enumerate(sprites)};textures=[]
    assert Old.sha(Old.JAR.read_bytes())=='4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d'
    with zipfile.ZipFile(Old.JAR) as jar:
        for sprite in sprites:
            name='assets/'+sprite.split(':')[0]+'/textures/'+sprite.split(':')[1]+'.png'
            textures.append(Old.np.array(Old.Image.open(io.BytesIO(jar.read(name))).convert('RGBA'),dtype=Old.np.uint8))
    base=len(textures)
    textures.extend([Old.np.array([[[255,0,0,255],[0,255,0,0]],[[0,0,255,128],[255,255,255,255]]],dtype=Old.np.uint8),Old.np.array([[[255,0,0,128]]],dtype=Old.np.uint8),Old.np.array([[[0,255,0,64]]],dtype=Old.np.uint8),Old.np.array([[[255,255,0,255]]],dtype=Old.np.uint8)])
    models=[[Old.production_quad(q,slots,i) for i,q in enumerate(q for group in v['result']['quad_groups'].values() for q in group)] for v in chosen]
    rows=[('empty',Old.scene([]),31,17),('java-stone',Old.scene(models[0],(.5,1.4,-2.5,0,.22)),31,17),('java-glass',Old.scene(models[1],(.5,1.4,-2.5,0,.22)),31,17)]
    rows.extend([('opaque',Old.scene([Old.plane(2,Old.mat(base))]),31,17),('cutout',Old.scene([Old.plane(2,Old.mat(base,'Cutout',threshold=129)),Old.plane(3,Old.mat(base+3))]),31,17),('translucent',Old.scene([Old.plane(2,Old.mat(base,'Translucent')),Old.plane(3,Old.mat(base+3))]),31,17),('alpha-order',Old.scene([Old.plane(2,Old.mat(base+1,'Translucent'),order=7),Old.plane(2,Old.mat(base+2,'Translucent'),order=3)]),31,17),('alpha-source-index',Old.scene([Old.plane(2,Old.mat(base+1,'Translucent'),order=5),Old.plane(2,Old.mat(base+2,'Translucent'),order=5)]),31,17),('occluded-alpha',Old.scene([Old.plane(2,Old.mat(base+3)),Old.plane(3,Old.mat(base+1,'Translucent'))]),31,17)])
    crossing=Old.plane(2,Old.mat(base+3),cull='NoCull')
    crossing['vertices']=[((.5,.5,2),(0,0)),((.5,-.5,2),(0,1)),((-.5,-.5,-.1),(1,1)),((-.5,.5,-.1),(1,0))]
    rows.extend([('near-plane-crossing',Old.scene([crossing]),31,17),('near-rejected',Old.scene([Old.plane(Old.f(.00001),Old.mat(base+3))]),31,17),('far-rejected',Old.scene([Old.plane(65,Old.mat(base+3))]),31,17),('offscreen-exact-miss',Old.scene([Old.transform(Old.plane(2,Old.mat(base+3)),(100,0,0))]),31,17),('minimal-rectangular',Old.scene([Old.plane(2,Old.mat(base+3))]),4,7)])
    practical=[]
    for z in range(6):
        for x in range(6):
            practical.extend(Old.transform(q,(x-3,-1,z)) for q in models[0])
    for i,q in enumerate(practical):q['order']=1048576+i
    rows.append(('java-stone-grid-total-cost',Old.scene(practical,(.5,2.25,-3,0,.30)),64,64))
    texture_code=[]
    for image in textures:
        h,w=image.shape[:2];pixels=[int(a)<<24|int(r)<<16|int(g)<<8|int(b) for r,g,b,a in image.reshape(-1,4)]
        texture_code.append('R.texture(P.Decoded{'+str(w)+','+str(h)+','+json.dumps(pixels,separators=(',',':'))+'})')
    code='\n'.join(['import Base','import ../../../src/client_render.bend as R','import ../../../src/mesh_render.bend as M','import ../../../src/png.bend as P','type Case is Data:\n  Case{id:U32,scene:M.Scene,width:U32,height:U32}','def raw(value:U32) -> F32:\n  match value:\n    case U32{word}: F32{word}','def assets() -> R.Assets:\n  R.Assets{['+','.join(texture_code)+']}','def cases() -> List<&2,Case>:\n  ['+','.join('Case{'+str(i)+','+Old.scenecode(scene)+','+str(w)+','+str(h)+'}' for i,(_,scene,w,h) in enumerate(rows))+']'])+'\n'
    if FIXTURE.exists():assert FIXTURE.read_text()==code
    else:FIXTURE.parent.mkdir(parents=True,exist_ok=False);FIXTURE.write_text(code)
    cases=[]
    for index,(name,scene,width,height) in enumerate(rows):
        rgb=Old.reference(scene,width,height,textures)
        expected=[4278190080|int(r)<<16|int(g)<<8|int(b) for r,g,b in zip(rgb[::3],rgb[1::3],rgb[2::3])]
        selector=None
        if scene['quads']:
            support=Old.quad_hits(scene['quads'][0],Old.np.array(scene['camera'][:3],dtype=Old.np.float32),Old.directions(scene['camera'],width,height,scene['settings'][2]),scene['settings'])[0].reshape(height,width)
            selector=bool(support[:16,:16].any())
        cases.append({'id':index,'name':name,'width':width,'height':height,'quads':len(scene['quads']),'expected_pixels':expected,'expected_forced_proposal_admission':selector})
    prep={'entry':S.pin(ENTRY),'fixture':S.pin(FIXTURE),'source_generation':generation(),'reference':S.pin(Old.REFERENCE),'jar':S.pin(Old.JAR),'cases':cases,'expected_final_pixels_in_native_input':False,'scope':'Exact Tile vs current M.render_flat and M.render pixels, retained actual Java quad vertex/UV/material words + official PNG texture inputs; independent existing Python binary32/Pillow oracle. Timing includes Tile.prepare+draw+forced pixel serialization. No Java final raster/GPU/window parity.'}
    S.exclusive_json(directory/'preparation.json',prep)
    print(json.dumps({'cases':len(cases),'pixels':sum(c['width']*c['height'] for c in cases),'preparation':str(directory/'preparation.json')}))

def build(directory):
    prep=json.loads((directory/'preparation.json').read_text());assert prep['source_generation']==generation()
    argv=[sys.executable,str(ROOT/'tools/build_native.py'),str(ENTRY),'-o',str(directory/'test'),'--report',str(directory/'native-build.json')]
    r,out,err=S.bounded(argv,120,directory,'native-build')
    S.exclusive_json(directory/'build-result.json',{'process':r,'unchanged':prep['source_generation']==generation()})
    assert r['exit_code']==0 and not r['timed_out'] and r['group_absent'],err.decode()[-5000:]

def run(directory):
    prep=json.loads((directory/'preparation.json').read_text());assert prep['source_generation']==generation()
    r,out,err=S.bounded([str(directory/'test'),'--gpu','off','--threads','1'],60,directory,'native-run')
    observed={};timings={};selectors={};released={}
    for line in out.decode().splitlines():
        parts=line.split('|');kind,ident=parts[:2]
        if kind=='selector':selectors[int(ident)]=bool(int(parts[2]));continue
        if kind=='release':released[int(ident)]=int(parts[2]);continue
        mode,value=parts[2:];key=(int(ident),mode)
        if kind=='pixels':observed[key]=list(map(int,value.split(',')))
        elif kind=='time':timings[key]=int(value)
        else:raise AssertionError(line)
    results=[]
    for case in prep['cases']:
        index=case['id'];expected=case['expected_pixels']
        exact={mode:observed.get((index,mode))==expected for mode in ['tile','flat','bvh']}
        results.append({k:case[k] for k in ['id','name','width','height','quads']}|{'exact':exact,'forced_proposal_admission_exact':case['expected_forced_proposal_admission'] is None or selectors.get(index)==case['expected_forced_proposal_admission'],'original_scene_quad_count_retained':released.get(index)==case['quads'],'milliseconds_including_forced_output':{mode:timings.get((index,mode)) for mode in exact}})
    unchanged=prep['source_generation']==generation()
    ok=r['exit_code']==0 and r['group_absent'] and not r['timed_out'] and unchanged and len(observed)==3*len(results) and all(all(c['exact'].values()) and c['forced_proposal_admission_exact'] and c['original_scene_quad_count_retained'] for c in results)
    S.exclusive_json(directory/'result.json',{'status':'PASS' if ok else 'FAIL','process':r,'results':results,'binary':S.pin(directory/'test'),'preparation':S.pin(directory/'preparation.json'),'unchanged':unchanged,'scope':prep['scope']})
    print(json.dumps({'status':'PASS' if ok else 'FAIL','cases':len(results),'results':results}));assert ok,err.decode()[-5000:]

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('mode',choices=['prepare','build','run']);p.add_argument('directory',type=Path);a=p.parse_args()
    if a.mode=='prepare':prepare(a.directory)
    elif a.mode=='build':build(a.directory)
    else:run(a.directory)
