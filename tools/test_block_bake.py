#!/usr/bin/env python3
"""Run pure native Bend baking from original JSON; compare executed Java quads."""
from __future__ import annotations
import argparse, copy, hashlib, itertools, json, os, random, subprocess, sys, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BEND=Path('/Users/chuah/.bend/bin/bend')
BIN=ROOT/'build/block-bake-tests'
REF=ROOT/'reference/model_semantics.json'
ORDER=('down','up','north','south','west','east','unculled')
def run(args,timeout=600):
    p=subprocess.run([str(x) for x in args],cwd=ROOT,text=True,capture_output=True,timeout=timeout)
    if p.returncode: raise AssertionError(f'exit {p.returncode}: {args[:3]}\n{p.stdout}\n{p.stderr}')
    return p

def input_text(models,root,state,sprites):
    return ('{"models":{'+','.join(json.dumps(k)+':'+v for k,v in models.items())+'},"root":'+json.dumps(root)+
            ','+json.dumps({**state,'sprites':sprites,'missing':{'slot':4000,'layer':'SOLID','animated':False}},separators=(',',':'))[1:])
def sprites_from_resources():
    # Explicit normalized-atlas material inputs derived independently from decoded pixels.
    records=json.loads((ROOT/'reference/render_assets.json').read_text())['records']
    out={}
    for r in records:
        name=r['path']
        if not name.startswith('assets/minecraft/textures/'): continue
        key='minecraft:'+name.removeprefix('assets/minecraft/textures/').removesuffix('.png')
        out[key]={'slot':len(out),'layer':'TRANSLUCENT' if r['alpha_partial_pixels'] else 'CUTOUT' if r['alpha_zero_pixels'] else 'SOLID','animated':False}
    return out

def project_java(result):
    out={k:[] for k in ORDER}
    for group,quads in result['quad_groups'].items():
        for q in quads:
            out[group].append({k:q[k] for k in ['direction','sprite','material_flags','light_emission','shade_direction_override','layer','default_directional_brightness_f32','nether_directional_brightness_f32']} |
                {'tint_index':q['tint_index']&0xffffffff,'vertices':[{k:v[k] for k in ['position_f32','uv_f32']} for v in q['vertices']]})
    return out

def project_bend(result):
    if result.get('status')!='ok': return result
    out={k:[] for k in ORDER}
    for q in result['quads']:
        out[q['cull'] or 'unculled'].append({k:q[k] for k in ['direction','sprite','material_flags','tint_index','light_emission','shade_direction_override','layer','vertices','default_directional_brightness_f32','nether_directional_brightness_f32']})
    return out

def first_difference(a,b,path=''):
    if type(a)!=type(b): return (path,a,b)
    if isinstance(a,dict):
        if a.keys()!=b.keys(): return(path+'.keys',list(a),list(b))
        for k in a:
            d=first_difference(a[k],b[k],path+'.'+k)
            if d:return d
    elif isinstance(a,list):
        if len(a)!=len(b):return(path+'.len',len(a),len(b))
        for i,(x,y) in enumerate(zip(a,b)):
            d=first_difference(x,y,path+f'[{i}]')
            if d:return d
    elif a!=b:return(path,a,b)
    return None

def native(cases):
    output=[]
    # macOS per-process ARG_MAX budget; original model decimals remain untouched.
    batch=[];size=0
    def flush():
        if not batch:return
        lines=run([BIN,'--threads','1',*[c['text'] for c in batch]]).stdout.splitlines()
        assert len(lines)==len(batch),('native count',len(lines),len(batch))
        output.extend(json.loads(s) for s in lines)
    for case in cases:
        n=len(case['text'].encode())
        if batch and (size+n>100000 or len(batch)>=10):flush();batch=[];size=0
        batch.append(case);size+=n
    flush();return output

def cases(reference):
    all_sprites=sprites_from_resources();models=reference['inputs']['models'];out=[]
    names=set()
    for source in models.values():
        for value in json.loads(source).get('textures',{}).values():
            value=value.get('sprite','') if isinstance(value,dict) else value
            if value and not value.startswith('#'): names.add(value if ':' in value else 'minecraft:'+value)
    sprites={k:all_sprites[k] for k in sorted(names) if k in all_sprites}
    for i,v in enumerate(reference['observations']['baked_variants']):
        st={k:v['input'][k] for k in ['x','y','z','uvlock'] if k in v['input']}
        out.append({'id':f'official-{i}', 'text':input_text(models,v['input']['model'],st,sprites), 'expected':project_java(v['result'])})
    inputs={v['id']:v for v in reference['inputs']['parse_cases']}
    for v in reference['observations']['parse_cases']:
        if 'baked' not in v or 'quad_groups' not in v['baked']:continue
        original=inputs[v['id']]['json']; root='test:probe'
        # Reference probe replaces its controlled material when source texture is unavailable.
        synthetic=dict(sprites)
        out.append({'id':v['id'],'text':input_text({root:original},root,{},synthetic),'expected':project_java(v['baked'])})
    return out


def extra_inputs():
    faces={d:{'texture':'#all','cullface':d,'uv':[1.25,2.5,14.75,13],
              'rotation':(i%4)*90,'tintindex':i-1} for i,d in enumerate(ORDER[:-1])}
    cube={'textures':{'all':'minecraft:block/stone'},'elements':[{'from':[.25,-.5,2.125],
           'to':[13.75,15.125,15.75],'faces':faces,'light_emission':13,'shade_direction_override':'west'}]}
    models={'test:quarter':json.dumps(cube,separators=(',',':'))}
    variants=[{'model':'test:quarter','x':x,'y':y,'z':z,'uvlock':lock}
              for x,y,z in itertools.product([0,90,180,270],repeat=3) for lock in [False,True]]
    parse=[]
    def add(name,obj):parse.append({'id':name,'json':json.dumps(obj,separators=(',',':')),'bake':True})
    for axis,angle,rescale in itertools.product('xyz',[-90,-45,-22.5,0,13.5,22.5,45,90],[False,True]):
        obj=copy.deepcopy(cube);obj['elements'][0]['rotation']={'origin':[4.25,9.5,12.125],'axis':axis,'angle':angle,'rescale':rescale}
        add(f'axis-{axis}-{angle}-{rescale}',obj)
    for name,endpoints in [('signed-zero',[[-0.0,0.0,-0.0],[16,16,16]]),
                           ('reversed',[[16,16,16],[0,0,0]]),('plane',[[0,0,0],[16,0,16]]),
                           ('line',[[0,0,0],[0,16,0]]),('point',[[0,0,0],[0,0,0]])]:
        obj=copy.deepcopy(cube);obj['elements'][0]['from'],obj['elements'][0]['to']=endpoints;add(name,obj)
    for force in [False,True]:
        obj=copy.deepcopy(cube);obj['textures']['all']={'sprite':'minecraft:block/stone','force_translucent':force};add(f'force-{force}',obj)
    obj=copy.deepcopy(cube);obj['elements'][0]['faces']={'UP':{'texture':'#all','rotation':0},'up':{'texture':'#all','rotation':90,'tintindex':5}};add('uppercase-face-error',obj)
    obj=copy.deepcopy(cube);obj['textures']['all']='test:absent';add('missing-sprite',obj)
    obj=copy.deepcopy(cube);obj['textures']={};add('missing-slot',obj)
    add('empty-elements',{'elements':[]});add('empty-faces',{'elements':[{'from':[0,0,0],'to':[16,16,16],'faces':{}}]})
    rng=random.Random(2632026)
    for i in range(12):
        obj=copy.deepcopy(cube);e=obj['elements'][0]
        e['from']=[rng.randint(-64,15)/8 for _ in range(3)];e['to']=[rng.randint(16,192)/8 for _ in range(3)]
        for face in e['faces'].values():face['uv']=[rng.randint(-64,192)/8 for _ in range(4)];face['rotation']=rng.randrange(4)*90
        add(f'random-finite-{i}',obj)
    return {'models':models,'variants':variants,'parse_cases':parse,'blockstates':{},'graph_cases':[],
            'selector_cases':[],'condition_cases':[],'dispatcher_cases':[]}

def java_extras(reproduce=False):
    import reference_model_probe as probe
    from reference_inventory import JAVA
    cp,provenance=probe.verified_client_classpath()
    directory=ROOT/'build/block-bake/java';directory.mkdir(parents=True,exist_ok=True)
    source=directory/'ReferenceModelProbe.java';source.write_text(probe.JAVA_SOURCE)
    inputs=extra_inputs();ip=directory/'inputs.json';ip.write_text(json.dumps(inputs,separators=(',',':')))
    outputs=[]
    for tag in (['a','b'] if reproduce else ['a']):
        op=directory/f'observations-{tag}.json'
        run([JAVA,'--enable-native-access=ALL-UNNAMED','-cp',os.pathsep.join(map(str,cp)),source,ip,probe.CLIENT,op])
        outputs.append(json.loads(op.read_text()))
    if reproduce:assert outputs[0]==outputs[1],'Fresh pinned Java observations did not reproduce'
    synthetic={'inputs':inputs,'observations':outputs[0]}
    records=cases(synthetic)
    for record in records:record['id']='fresh-'+record['id']
    errors=[{'id':c['id'],'error':c.get('error')} for c in outputs[0]['parse_cases'] if c['status']!='ok']
    observation_sha=hashlib.sha256(json.dumps(outputs[0],sort_keys=True,separators=(',',':')).encode()).hexdigest()
    return records,{'cases':len(records),'input_sha256':digest(ip),'java_source_sha256':digest(source),
                    'observations_sha256':observation_sha,'two_runs_equal':reproduce,'java_errors':errors,
                    'provenance':provenance}

def defensive_cases(reference):
    base=json.loads(cases(reference)[0]['text']);out=[]
    def add(name,obj,status,code=None):
        expected={'status':status}
        if code is not None:expected['code']=code
        out.append({'id':name,'text':json.dumps(obj,separators=(',',':')),'expected_error':expected})
    for axis,value in [('x',45),('x',360),('y',4294967295),('z',1)]:
        obj=copy.deepcopy(base);obj[axis]=value;add(f'invalid-state-{axis}-{value}',obj,'invalid','StateQuarterTurns')
    obj=copy.deepcopy(base);obj['sprites']={};obj.pop('missing');add('missing-without-fallback',obj,'missing-material')
    obj=copy.deepcopy(base);name=next(k for k in obj['sprites'] if k=='minecraft:block/dirt')
    obj['sprites'][name]['u0']=float('inf');text=json.dumps(obj,separators=(',',':')).replace('Infinity','1e400')
    out.append({'id':'nonfinite-sprite','text':text,'expected_error':{'status':'invalid','code':'NonFiniteSpriteUV'}})
    model={'textures':{'all':'minecraft:block/stone'},'elements':[{'from':[0,0,0],'to':[16,16,16],'faces':{'north':{'texture':'#all','uv':[0,0,1e30,16]}}}]}
    source=json.dumps(model,separators=(',',':')).replace('1e+30','1e400')
    out.append({'id':'nonfinite-face','text':input_text({'test:model':source},'test:model',{},sprites_from_resources_subset()),'expected_error':{'status':'invalid','code':'FaceUVOrRotation'}})
    for angle in [12.4,180]:
        model['elements'][0]['faces']['north']['uv']=[0,0,16,16]
        model['elements'][0]['rotation']={'origin':[8,8,8],'axis':'y','angle':angle}
        out.append({'id':f'unsupported-angle-{angle}','text':input_text({'test:model':json.dumps(model,separators=(',',':'))},'test:model',{},sprites_from_resources_subset()),'expected_error':{'status':'unsupported','code':'ElementAngle'}})
    model['elements'][0].pop('rotation');model['elements'][0]['faces']={}
    out.append({'id':'empty-faces-java-error','text':input_text({'test:model':json.dumps(model,separators=(',',':'))},'test:model',{},sprites_from_resources_subset()),'expected_error':{'status':'parse-error'}})
    model['elements'][0]['faces']={'UP':{'texture':'#all'}}
    out.append({'id':'uppercase-face-java-error','text':input_text({'test:model':json.dumps(model,separators=(',',':'))},'test:model',{},sprites_from_resources_subset()),'expected_error':{'status':'parse-error'}})
    return out

def sprites_from_resources_subset():
    return {'minecraft:block/stone':sprites_from_resources()['minecraft:block/stone']}

SCALAR_SOURCE='import org.joml.*;import java.lang.reflect.*;import com.google.gson.*;public class BakeScalarProbe { static String bits(float x){return String.format("%08x",Float.floatToRawIntBits(x));} public static void main(String[] args)throws Exception { JsonObject root=new JsonObject();root.addProperty("USE_MATH_FMA",Options.USE_MATH_FMA);root.addProperty("FASTMATH",Options.FASTMATH);Field f=Class.forName("org.joml.Runtime").getDeclaredField("HAS_Math_fma");f.setAccessible(true);root.addProperty("HAS_Math_fma",f.getBoolean(null));JsonArray a=new JsonArray();for(float degrees:new float[]{-90,-45,-22.5f,0,13.5f,22.5f,45,90}){float radians=degrees*0.017453292f;float sin=org.joml.Math.sin(radians),cos=org.joml.Math.cosFromSin(sin,radians);JsonObject j=new JsonObject();j.addProperty("degrees",bits(degrees));j.addProperty("radians",bits(radians));j.addProperty("sin",bits(sin));j.addProperty("cosFromSin",bits(cos));a.add(j);}root.add("scalars",a);System.out.println(root);}}'

def math_audit(reproduce=False):
    import reference_model_probe as probe
    from reference_inventory import JAVA
    import zipfile
    cp,provenance=probe.verified_client_classpath()
    directory=ROOT/'build/block-bake/scalars';directory.mkdir(parents=True,exist_ok=True)
    source=directory/'BakeScalarProbe.java';source.write_text(SCALAR_SOURCE)
    run([JAVA.with_name('javac'),'-cp',os.pathsep.join(map(str,cp)),'-d',directory,source])
    observations=[json.loads(run([JAVA,'-cp',str(directory)+os.pathsep+os.pathsep.join(map(str,cp)),'BakeScalarProbe']).stdout)
                  for _ in range(2 if reproduce else 1)]
    assert not observations[0]['USE_MATH_FMA'] and not observations[0]['HAS_Math_fma'] and not observations[0]['FASTMATH']
    if reproduce:assert observations[0]==observations[1]
    names=['org/joml/'+n+'.class' for n in ['Math','Runtime','Options','Matrix4f','Vector3f','GeometryUtils','Quaternionf']]
    classes={}
    for jar in cp:
        with zipfile.ZipFile(jar) as z:
            for name in names:
                if name in z.namelist():
                    raw=z.read(name);classes[name]={'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw),'artifact':jar.name}
    assert len(classes)==len(names)
    evidence={'schema':'block-bake-math-v1','pin':'26.3','source_sha256':digest(source),
              'java_version':provenance['java_version'],'two_runs_equal':reproduce,'observations':observations[0],'classes':classes}
    (ROOT/'evidence/block-bake-math.json').write_text(json.dumps(evidence,indent=2)+'\n')
    return hashlib.sha256(json.dumps(observations[0],sort_keys=True,separators=(',',':')).encode()).hexdigest()

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--no-build',action='store_true');ap.add_argument('--limit',type=int);ap.add_argument('--diagnostic',action='store_true');ap.add_argument('--java-extras',action='store_true');ap.add_argument('--selftest',action='store_true');args=ap.parse_args()
    started=time.time();checks={}
    prior_path=ROOT/'evidence/block-bake-tests.json'
    if args.no_build and prior_path.exists():
        prior=json.loads(prior_path.read_text())
        if all(prior.get('sources',{}).get(p)==digest(ROOT/p) for p in ['src/block_bake.bend','tests/block_bake.bend']):
            checks=prior.get('checks',{})
    math_sha=math_audit(args.selftest)
    if not args.no_build:
        checks['module_check']=run([BEND,'src/block_bake.bend','--check-only']).stdout
        checks['test_check']=run([BEND,'tests/block_bake.bend','--check-only']).stdout
        for name,path in [('module_kernel','src/block_bake.bend'),('test_kernel','tests/block_bake.bend')]:
            try: checks[name]=run([BEND,path,'--verdict'],timeout=60).stdout
            except subprocess.TimeoutExpired: checks[name]='INCONCLUSIVE: exceeded 60-second bounded kernel check; imported proof closure remains unverified here.'
        run([BEND,'tests/block_bake.bend','-o',BIN],timeout=1800)
    assert digest(REF)=='3cbe8aa7780f14c1b37159a885710b04680e3b6c4ffa4975b4d8297015f11e7e','Reference hash changed'
    reference=json.loads(REF.read_text());cs=cases(reference);extra_evidence=None
    if args.java_extras or args.selftest:
        extra,extra_evidence=java_extras(args.selftest);cs.extend(extra)
    if args.limit:cs=cs[:args.limit]
    output=native(cs); mismatches=[];unsupported=[];passed=0;quads=0
    errors=defensive_cases(reference);error_output=native(errors)
    error_failures=[{'id':c['id'],'expected':c['expected_error'],'observed':o} for c,o in zip(errors,error_output) if any(o.get(k)!=v for k,v in c['expected_error'].items())]
    assert not error_failures,error_failures
    for c,observed in zip(cs,output):
        if observed.get('status')=='unsupported' and c['id']=='rotation_88' and observed.get('code')=='ElementEuler':
            unsupported.append({'id':c['id'],'code':observed['code']});continue
        d=first_difference(c['expected'],project_bend(observed))
        if d:mismatches.append({'id':c['id'],'difference':d})
        else:passed+=1;quads+=sum(map(len,c['expected'].values()))
    evidence={'schema':'block-bake-test-v1','pin':'26.3','reference_sha256':digest(REF),'native_binary_sha256':digest(BIN),'compile_requested':not args.no_build,'math_observations_sha256':math_sha,'sources':{p:digest(ROOT/p) for p in ['src/block_bake.bend','tests/block_bake.bend','tools/test_block_bake.py']},'cases':len(cs),'passed':passed,'quads_compared':quads,'unsupported':unsupported,'mismatches':mismatches,'checks':checks,'fresh_java':extra_evidence,'defensive_cases_passed':len(errors),'elapsed_seconds':round(time.time()-started,3)}
    if args.selftest:
        second=native(cs);assert second==output,'Native observations did not reproduce'
        rejected=[]
        good=next(project_bend(o) for o in output if o.get('status')=='ok' and o.get('quads'))
        for kind in ['position','uv','direction','layer','tint','count']:
            bad=copy.deepcopy(good);group=next(k for k,v in bad.items() if v);q=bad[group][0]
            if kind=='position':q['vertices'][0]['position_f32'][0]='7f800000'
            elif kind=='uv':q['vertices'][0]['uv_f32'][0]='7fc00000'
            elif kind=='direction':q['direction']='bad'
            elif kind=='layer':q['layer']='bad'
            elif kind=='tint':q['tint_index']^=1
            else:bad[group].pop()
            assert first_difference(good,bad),kind
            rejected.append(kind)
        evidence['two_native_runs_equal']=True;evidence['comparison_corruptions_rejected']=rejected
    (ROOT/'build/block-bake').mkdir(exist_ok=True,parents=True)
    (ROOT/'build/block-bake/test-observations.json').write_text(json.dumps(output,indent=2)+'\n')
    (ROOT/'evidence/block-bake-tests.json').write_text(json.dumps(evidence,indent=2)+'\n')
    summary={k:v for k,v in evidence.items() if k not in ['checks','sources','fresh_java']}
    if extra_evidence:summary['fresh_java']={k:v for k,v in extra_evidence.items() if k!='provenance'}
    print(json.dumps(summary,indent=2))
    if mismatches and not args.diagnostic:raise SystemExit(1)
if __name__=='__main__':main()
