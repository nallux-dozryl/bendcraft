#!/usr/bin/env python3
"""Actual resource-backed production renderer boundary; no simulation host."""
from __future__ import annotations
import collections,copy,json,math,shutil,struct,sys,io,zipfile
from PIL import Image
import test_campfire_authority as T
import reference_model_probe as R
ROOT=T.ROOT;WORK=ROOT/'build/item-entity-render-native'
def word(h):return int(h,16)
def f32(v):return struct.unpack('>f',struct.pack('>f',v))[0]
def float_word(v):return struct.unpack('>I',struct.pack('>f',v))[0]
def value(w):return struct.unpack('>f',struct.pack('>I',w))[0]
def add(a,b):return f32(a+b)
def mul(a,b):return f32(a*b)
def transformed(matrix,p):
    m=list(map(lambda h:value(word(h)),matrix));p=list(map(lambda h:value(word(h)),p))
    return [float_word(add(mul(m[c],p[0]),add(mul(m[c+4],p[1]),add(mul(m[c+8],p[2]),m[c+12]))))for c in range(3)]
def quad_key(vertices):
    vs=tuple(tuple(v['position']+v['uv'])for v in vertices)
    return min(vs[i:]+vs[:i]for i in range(4))
def actual_ground(shape):
    return [[{'position':transformed(shape['ground_matrix'],v['position_f32']),'uv':list(map(word,v['uv_f32']))}for v in q['vertices']]for q in shape['quads']]
def case(kind,name,count,xp,age):
    return dict(kind=kind,item=name,count=count,xp=xp,ticks=int(age),partial=float_word(age-int(age)),scan=100,budget=4096,removed=False,dimension='minecraft:overworld')
def inputs(reference):
    rows=[case('item','minecraft:'+r['item'],r['count'],1,value(word(r['age'])))for r in reference['cases']]
    rows += [case('orb','minecraft:stone',1,r['value'],value(word(r['age'])))for r in reference['orbs']]
    ordinary=copy.deepcopy(rows[0]);guards=[]
    for name,delta in [('removed',{'removed':True}),('dimension',{'dimension':'minecraft:the_nether'}),('scan',{'scan':0}),('quads',{'budget':0}),('unknown-model',{'item':'minecraft:dirt'}),('zero-stack',{'count':0}),('negative-stack',{'count':4294967295}),('air-stack',{'item':'minecraft:air'})]:
        x=copy.deepcopy(ordinary);x.update(delta);x['guard']=name;guards.append(x)
    return rows+guards

def compare(got,obs):
    assert 'error' not in got,got
    assert got['retained_authority']==[{'retained':True,'result':'done'},{'retained':True,'result':'scan budget'}]
    with zipfile.ZipFile(R.CLIENT) as jar:
        for row in got['texture_samples']:
            name=row['item'].split(':',1)[1];sprite=obs[name]['quads'][0]['sprite'];namespace,path=sprite.split(':',1)
            im=Image.open(io.BytesIO(jar.read('assets/'+namespace+'/textures/'+path+'.png'))).convert('RGBA');w,h=im.size
            wanted=[]
            for u,v in [(0,0),(.5,.5),(1,1),(.25,.75)]:
                red,green,blue,alpha=im.getpixel((min(w-1,int(w*u)),min(h-1,int(h*v))));wanted.append((alpha<<24)|(red<<16)|(green<<8)|blue)
            assert row['pixels']==wanted,(name,row['pixels'],wanted)
    grounds={r['item'].split(':',1)[1]:r for r in got['grounds']};first={}
    for name in ['stone','cooked_beef','iron_ingot','suspicious_stew']:
        expected=actual_ground(obs[name]);actual=grounds[name]
        assert actual['low']==list(map(word,obs[name]['low'])),(name,'low',actual['low'],obs[name]['low'])
        assert actual['high']==list(map(word,obs[name]['high'])),(name,'high')
        assert collections.Counter(quad_key(q['vertices'])for q in actual['quads'])==collections.Counter(quad_key(q)for q in expected),(name,'ground geometry')
        key=quad_key(expected[0]);first[name]=next(i for i,q in enumerate(actual['quads'])if quad_key(q['vertices'])==key)
    checked=0;max_abs=0.0;exact=0;diffs=0
    for row,want in zip(got['cases'],obs['cases']):
        assert 'error' not in row,row
        draw,=row['draws'];name=want['item'];n=len(grounds[name]['quads'])
        assert draw['age']==word(want['age']) and draw['hover']==word(want['hover']) and draw['spin']==word(want['spin']),(name,'scalar',draw,want)
        assert len(draw['copies'])==want['copies'] and len(draw['quads'])==n*want['copies']
        assert grounds[name]['seed']==want['seed'] and draw['packed_light']==15<<20
        for i,copyrow in enumerate(want['draws']):
            q=draw['quads'][n*i+first[name]]
            # Compare in resource vertex order, not Java's unstable side-set order.
            native_by_uv={tuple(v['uv']):v['position']for v in q['vertices']}
            uv=obs[name]['quads'][0]['vertices']
            for v,p in zip(uv,copyrow['first_quad'][0]):
                native=native_by_uv[tuple(map(word,v['uv_f32']))]
                for a,b in zip(native,map(word,p)):
                    error=abs(value(a)-value(b));max_abs=max(max_abs,error);checked+=1
                    if a==b:exact+=1
                    else:diffs+=1
                    # Native single-precision sin and pre-applied ground display
                    # are declared numerical boundaries, not raw-bit parity.
                    assert error<=2e-7,(name,i,native,p,error)
    start=len(obs['cases'])
    for row,want in zip(got['cases'][start:],obs['orbs']):
        draw,=row['draws'];assert draw['icon']==want['icon'] and draw['age']==word(want['age'])
        assert draw['packed_light']==((7<<4)|(15<<20))
        q,=draw['quads'];red,green,blue,alpha=want['vertices'][0]['color'];assert draw['color']==(alpha<<24)|(red<<16)|(green<<8)|blue
        for a,b in zip(q['vertices'],want['vertices']):
            assert a['position']==list(map(word,b['position'])) and a['uv']==list(map(word,b['uv'])),(a,b)
    guards=got['cases'][start+len(obs['orbs']):]
    for r in guards[:2]:assert r=={'draws':[],'quad_count':0},r
    assert [r.get('error')for r in guards[2:5]]==['scan budget','quad budget','render:exact initialized item ground model not loaded']
    for r in guards[5:]:assert r=={'draws':[],'quad_count':0},r
    return {'ground_geometry_raw_bit_exact_items':len(grounds),'item_transform_components':checked,'item_transform_raw_bit_exact_components':exact,'item_transform_nonexact_components':diffs,'item_transform_max_abs_error':max_abs,'orb_raw_bit_exact_billboards':len(obs['orbs']),'guards':len(guards),'real_png_clamped_texel_samples':16,'actual_entity_owner_success_and_refusal_checks':2}

def main():
    WORK.mkdir(parents=True,exist_ok=True);T.WORK=WORK
    ref=json.loads((ROOT/'reference/item_entity_render.json').read_text());assert ref['pin']=='26.3'
    # Rendering receives initialized defaults, not cooking recipe/feature authority.
    # Keep every actual initialized item row and the complete registry table,
    # while avoiding an unrelated quadratic full cooking-catalog replay.
    catalog={'items':copy.deepcopy(json.loads((ROOT/'reference/campfire_authority.json').read_text())['inputs']['catalog']['items'])}
    payload={'catalog':catalog,'item_table':(ROOT/'generated/reference_item_metadata.tsv').read_text(),'jar':str(R.CLIENT),'sine':str(ROOT/'generated/reference_mth_sin.f32'),'cases':inputs(ref['observations'])}
    (WORK/'input.json').write_text(json.dumps(payload,separators=(',',':'))+'\n')
    checks=[T.run('emit',[T.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=2048','tools/item_entity_render_emit.mjs','tests/item_entity_render.bend',WORK/'receiver.c'],timeout=60,max_rss=2560*1024**2)]
    checks.append(T.run('clang',[shutil.which('clang'),'-std=c11','-O0','-fomit-frame-pointer','-ffp-contract=off',WORK/'receiver.c','-lpthread','-lm','-o',WORK/'receiver'],timeout=120))
    outputs=[];compares=[]
    for threads in [1,4]:
        checks.append(T.run('native-'+str(threads),['/usr/bin/time','-l',WORK/'receiver','--gpu','off','--threads',str(threads),WORK/'input.json'],timeout=60,max_rss=1024**3))
        got=json.loads((WORK/('native-'+str(threads)+'.stdout')).read_text());outputs.append(got);compares.append(compare(got,ref['observations']))
    assert outputs[0]==outputs[1]
    evidence={'status':'passed','pin':'26.3','command':'python3 tools/test_item_entity_render.py','checks':checks,'source':json.loads((WORK/'receiver.c.sources.json').read_text()),'reference_sha256':T.digest(ROOT/'reference/item_entity_render.json'),'input_sha256':T.digest(WORK/'input.json'),'initialized_default_source_sha256':T.digest(ROOT/'reference/campfire_authority.json'),'item_table_sha256':T.digest(ROOT/'generated/reference_item_metadata.tsv'),'mth_table_sha256':T.digest(ROOT/'generated/reference_mth_sin.f32'),'installed_client_sha256':T.digest(R.CLIENT),'native_emitted_c_sha256':T.digest(WORK/'receiver.c'),'native_binary_sha256':T.digest(WORK/'receiver'),'comparisons':compares[0],'threads':[1,4],'source_api_basis':'Original ../bend/bend2/bend.ts book_load/book_valid and comp.ts compile_book; no observational/private compiler C and no installed-CLI build claim.','boundary':'Actual initialized full item keys, installed jar model/PNG loading, production generated geometry, affine Mth table and immutable render Snapshot; no entity simulation RNG/tick. Item cluster numerical portability is measured separately from exact resource geometry/billboard parity. No GPU shader, actual world lightmap, full item selectors, wire or OS presentation acceptance.'}
    (ROOT/'evidence/item-entity-render-native.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps(evidence['comparisons']))
if __name__=='__main__':main()
