#!/usr/bin/env python3
"""Pure Bend archive/model/PNG integration; Python supplies independent oracles."""
from __future__ import annotations
import datetime,hashlib,io,json,os,re,struct,subprocess,sys,time,zipfile,zlib
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
PYTHON=Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
if Path(sys.executable).resolve()!=PYTHON.resolve():
    os.execv(str(PYTHON),[str(PYTHON),__file__,*sys.argv[1:]])
from PIL import Image
import test_block_model as MODEL

BEND=Path.home()/'.bend/bin/bend'
JAR=Path.home()/'Library/Application Support/minecraft/versions/26.3/26.3.jar'
REFERENCE=ROOT/'reference/model_semantics.json'
BUILD=ROOT/'build/block-resources'
BIN=ROOT/'build/block-resources-tests'
ENV={**os.environ,'BEND_MINECRAFT_LAUNCH_MODE':'hidden'}

def sha(data): return hashlib.sha256(data).hexdigest()
def fingerprint():
    pending=[ROOT/'tests/block_resources.bend'];seen={}
    while pending:
        path=pending.pop().resolve()
        if str(path) in seen:continue
        source=path.read_bytes();seen[str(path)]=sha(source)
        for name in re.findall(r'^import\s+(\.\.?/\S+\.bend)',source.decode(),re.M):
            pending.append(path.parent/name)
    return {**{str(Path(p).relative_to(ROOT)):digest for p,digest in seen.items()},'pinned_compiler_sha256':sha(BEND.read_bytes())}
def run(args,timeout=900):
    p=subprocess.run(list(map(str,args)),cwd=ROOT,env=ENV,capture_output=True,text=True,timeout=timeout)
    assert p.returncode==0,(args,p.returncode,p.stdout[-4000:],p.stderr[-4000:])
    return p
def native(configs):
    output=[]
    for i in range(0,len(configs),12):
        p=run([BIN,'--threads','1',*[json.dumps(c,separators=(',',':')) for c in configs[i:i+12]]])
        lines=p.stdout.splitlines()
        assert len(lines)==len(configs[i:i+12]),('line count',p.stdout[:1000])
        output.extend(json.loads(line) for line in lines)
    return output
def png(width,height):
    rgba=bytes((x*17+y*29+k*73)%256 for y in range(height) for x in range(width) for k in range(4))
    raw=b''.join(b'\0'+rgba[y*width*4:(y+1)*width*4] for y in range(height))
    def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')
def archive(name,entries,compression=zipfile.ZIP_DEFLATED):
    path=BUILD/(name+'.zip')
    with zipfile.ZipFile(path,'w',compression=compression) as z:
        for key,value in entries.items():z.writestr(key,value.encode() if isinstance(value,str) else value)
    return path
def path_model(id):
    ns,path=id.split(':',1)
    return f'assets/{ns}/models/{path}.json'
def path_sprite(id):
    ns,path=id.split(':',1)
    return f'assets/{ns}/textures/{path}.png'
def arg(path,roots=['test:block/a'],layers={'test:block/tex':'Solid'},limits=None):
    config={'path':str(path),'roots':roots,'layers':layers}
    if limits is not None:config['limits']=limits
    return config
def rgba_pixels(data):
    with Image.open(io.BytesIO(data)) as image:
        rgba=image.convert('RGBA').tobytes();w,h=image.size
    pixels=[(a<<24)|(r<<16)|(g<<8)|b for r,g,b,a in zip(rgba[0::4],rgba[1::4],rgba[2::4],rgba[3::4])]
    return w,h,pixels,sha(rgba)
def verify_pixels(report,path):
    hashes={}
    with zipfile.ZipFile(path) as z:
        for slot,item in enumerate(report['sprites']):
            w,h,pixels,digest=rgba_pixels(z.read(path_sprite(item['id'])))
            assert (item['width'],item['height'],item['pixels'])==(w,h,pixels),(item['id'],'pixels')
            assert item['slot']==slot and item['side']==1<<(max(w,h)-1).bit_length()
            assert item['context']=={'slot':slot,'uv':['00000000','00000000','3f800000','3f800000'],'layer':item['layer'],'animated':False}
            hashes[item['id']]=digest
    return hashes
def verify_models(report,reference):
    observed=reference['observations']
    for id,value in report['source'].items():
        assert value==MODEL.parsed(observed['parsed_official_models'][id]),(id,'source model')
    for id,value in report['models'].items():
        expected=MODEL.resolved(observed['resolved_official_models'][id])
        expected['materials']={slot:expected['materials'].get(slot) for slot in value['materials']}
        assert value==expected,(id,'resolved model',value,expected)
def usage_bytes(report,path):
    with zipfile.ZipFile(path) as z:
        text=sum(len(z.read(path_model(id))) for id in report['source'])
        image=sum(len(z.read(path_sprite(item['id']))) for item in report['sprites'])
        text+=sum(len(z.read(path_sprite(item['id'])+'.mcmeta')) for item in report['sprites'] if item['metadata'] is not None)
    return {'models':len(report['source']),'sprites':len(report['sprites']),'text':text,'png':image,'pixels':sum(x['width']*x['height'] for x in report['sprites'])}
def closed_observation(config):
    c={**config,'pause':True}
    p=subprocess.Popen([str(BIN),'--threads','1',json.dumps(c,separators=(',',':'))],cwd=ROOT,env=ENV,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    line=p.stdout.readline();assert line,('no checkpoint',p.stderr.read())
    report=json.loads(line)
    result=subprocess.run(['/usr/sbin/lsof','-a','-p',str(p.pid),'-Fn'],capture_output=True,text=True,timeout=10)
    assert result.returncode in (0,1),result.stderr
    open_names=[s[1:] for s in result.stdout.splitlines() if s.startswith('n')]
    assert str(Path(config['path']).resolve()) not in open_names,('archive leaked',config['path'],open_names)
    out,err=p.communicate(timeout=10);assert p.returncode==0,(out,err)
    return {'status':report['status'],'code':report.get('code'),'archive_open_at_post_load_checkpoint':False,'os_observer':'/usr/sbin/lsof -a -p PID -Fn'}
def main():
    BUILD.mkdir(parents=True,exist_ok=True)
    release=json.loads((ROOT/'reference/release.json').read_text())
    jar_sha=sha(JAR.read_bytes())
    assert jar_sha=='4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d'
    assert sha(REFERENCE.read_bytes())=='3cbe8aa7780f14c1b37159a885710b04680e3b6c4ffa4975b4d8297015f11e7e'
    reference=json.loads(REFERENCE.read_text())
    official_roots=['minecraft:block/stone','minecraft:block/dirt','minecraft:block/oak_planks']
    # This is the default caller mapping for three fixture materials, not an inferred vanilla default.
    official_layers={id:'Solid' for id in official_roots}
    configs=[];cases=[]
    def add(name,config,code=None):
        configs.append(config);cases.append({'name':name,'expected_code':code})
    add('official-palette',arg(JAR,official_roots,official_layers))
    add('official-reordered-duplicate-roots',arg(JAR,['block/oak_planks','block/stone','block/dirt','minecraft:block/stone'],official_layers))
    complex_roots=['minecraft:block/'+s for s in ['grass_block','oak_slab','oak_stairs','oak_stairs_inner','oak_fence_post','oak_fence_side']]
    complex_layers={'minecraft:block/'+s:l for s,l in [('grass_block_top','Solid'),('grass_block_side','Solid'),('grass_block_side_overlay','Cutout'),('dirt','Solid'),('oak_planks','Solid')]}
    add('official-noncube-overlay',arg(JAR,complex_roots,complex_layers))
    add('official-glass-texture-metadata-rejection',arg(JAR,['minecraft:block/glass'],{'minecraft:block/glass':'Translucent'}),'UnsupportedMetadata')
    model='{"textures":{"all":"test:block/tex"}}'
    entries={path_model('test:block/a'):model,path_sprite('test:block/tex'):png(3,5)}
    valid=archive('valid',entries)
    add('rectangular-static',arg(valid))
    add('explicit-cutout',arg(valid,layers={'test:block/tex':'Cutout'}))
    add('explicit-translucent',arg(valid,layers={'test:block/tex':'Translucent'}))
    add('normalized-layer-key',arg(valid,layers={'test:block/tex':'Solid'}))
    stress=archive('stress',{**entries,path_sprite('test:block/tex'):png(32,64)})
    add('indexed-texture-build-32x64',arg(stress))
    empty=archive('empty',{})
    add('empty-request',arg(empty,[],{}))
    add('missing-root',arg(empty),'MissingResource')
    add('missing-parent',arg(archive('missing-parent',{path_model('test:block/a'):'{"parent":"test:block/missing"}'})),'MissingResource')
    add('missing-png',arg(archive('missing-png',{path_model('test:block/a'):model})),'MissingResource')
    add('missing-layer',arg(valid,layers={}), 'MissingLayer')
    add('normalization-layer-collision',arg(valid,layers={'minecraft:block/tex':'Solid','block/tex':'Cutout'}),'LayerCollision')
    add('invalid-layer-id',arg(valid,layers={'UPPER:tex':'Solid'}),'Model:InvalidIdentifier')
    add('self-cycle',arg(archive('self-cycle',{path_model('test:block/a'):'{"parent":"test:block/a"}'})),'ParentCycle')
    cycle=archive('cycle',{path_model('test:block/a'):'{"parent":"test:block/b"}',path_model('test:block/b'):'{"parent":"test:block/a"}'})
    add('two-model-cycle',arg(cycle),'ParentCycle')
    add('texture-alias-cycle',arg(archive('texture-cycle',{path_model('test:block/a'):'{"textures":{"a":"#b","b":"#a"}}'})),'TextureCycle')
    add('unbound-root-slot',arg(archive('unbound',{path_model('test:block/a'):'{"textures":{"a":"#missing"}}'})),'MissingTexture')
    large_slots=json.dumps({'textures':{f's{i}':'test:block/tex' for i in range(1025)}},separators=(',',':'))
    add('referenced-slot-budget',arg(archive('slot-budget',{**entries,path_model('test:block/a'):large_slots})),'ReferencedSlotBudget')
    add('malformed-json',arg(archive('json',{**entries,path_model('test:block/a'):'{"textures": [}'})),'JSON')
    add('non-model-json',arg(archive('non-model',{**entries,path_model('test:block/a'):'[]'})),'Model:ExpectedObject')
    add('parent-id-invalid',arg(archive('parent-id',{**entries,path_model('test:block/a'):'{"parent":"UPPER:bad"}'})),'Model:InvalidIdentifier')
    for name,bad in [('overlong',b'\xc0\xaf'),('surrogate',b'\xed\xa0\x80'),('too-high',b'\xf4\x90\x80\x80'),('truncated',b'\xf0\x9f'),('continuation',b'\x80'),('bad-continuation',b'\xe2x\xac')]:
        add('utf8-'+name,arg(archive('utf8-'+name,{**entries,path_model('test:block/a'):b'{"note":"'+bad+b'"}'})),'UTF8')
    unicode_model='{"note":"漢字😃","textures":{"all":"test:block/tex"}}'
    add('utf8-valid-scalars',arg(archive('unicode',{**entries,path_model('test:block/a'):unicode_model})))
    add('hash-in-slot-key',arg(archive('hash-slot',{**entries,path_model('test:block/a'):'{"textures":{"#all":"test:block/tex","alias":"##all"}}'})))
    add('gson-first-root-and-duplicate-last',arg(archive('gson-profile',{**entries,path_model('test:block/a'):'{"textures":{"all":"test:block/missing","all":"test:block/tex"}} trailing'})))
    add('utf8-bom',arg(archive('bom',{**entries,path_model('test:block/a'):b'\xef\xbb\xbf'+model.encode()})))
    broken=bytearray(entries[path_sprite('test:block/tex')]);broken[29]^=1
    add('png-crc',arg(archive('png-crc',{**entries,path_sprite('test:block/tex'):broken})),'PNG:CRC')
    add('png-signature',arg(archive('png-signature',{**entries,path_sprite('test:block/tex'):b'wrong'})),'PNG:Signature')
    for name,meta,code in [('animation','{"animation":{}}','UnsupportedAnimation'),('texture','{"texture":{"blur":true}}','UnsupportedMetadata'),('unknown','{"unknown":{}}','UnsupportedMetadata'),('array','[]','MetadataObject'),('malformed','{','JSON')]:
        add('metadata-'+name,arg(archive('meta-'+name,{**entries,path_sprite('test:block/tex')+'.mcmeta':meta})),code)
    meta_valid=archive('metadata-empty',{**entries,path_sprite('test:block/tex')+'.mcmeta':'{}'})
    add('metadata-empty',arg(meta_valid))
    add('metadata-invalid-utf8',arg(archive('meta-utf8',{**entries,path_sprite('test:block/tex')+'.mcmeta':b'{"x":"\xff"}'})),'UTF8')
    weird=archive('exact-identifiers',{path_model('test:../a'):'{"textures":{"all":"test:/../tex"}}',path_sprite('test:/../tex'):png(2,2)})
    add('exact-zip-identifiers',arg(weird,['test:../a'],{'test:/../tex':'Solid'}))
    add('namespace-default',arg(archive('namespace',{path_model('minecraft:block/a'):'{"textures":{"all":"block/tex"}}',path_sprite('minecraft:block/tex'):png(2,2)}),[':block/a'],{'block/tex':'Solid'}))
    add('empty-path-identifier',arg(archive('empty-id',{path_model('test:'):'{"textures":{"all":"test:"}}',path_sprite('test:'):png(2,2)}),['test:'],{'test:':'Solid'}))
    add('no-directory-fallback',arg(archive('directory-only',{path_model('test:block/a')+'/':model})),'MissingResource')
    add('root-count-budget',arg(valid,limits={'models':0}),'RootBudget')
    add('closure-model-budget',arg(JAR,official_roots,official_layers,{'models':3}),'ModelBudget')
    add('parent-depth-budget',arg(JAR,official_roots,official_layers,{'depth':0}),'ParentDepth')
    add('text-budget',arg(valid,limits={'text':1}),'EntryBudget')
    add('png-byte-budget',arg(valid,limits={'png':1}),'EntryBudget')
    add('aggregate-byte-budget',arg(valid,limits={'bytes':len(model)}),'ByteBudget')
    add('sprite-count-budget',arg(valid,limits={'sprites':0}),'SpriteBudget')
    add('pixel-budget',arg(valid,limits={'pixels':14}),'PNG:PixelLimit')
    add('padded-image-budget',arg(valid,limits={'pixels':15}),'ImageBudget')
    add('skinny-padded-image-budget',arg(archive('skinny',{**entries,path_sprite('test:block/tex'):png(1,1024)}),limits={'side':1024,'pixels':2048}),'ImageBudget')
    add('side-budget',arg(valid,limits={'side':4}),'PNG:Dimensions')
    add('json-depth-budget',arg(valid,limits={'json':0}),'JSON')
    add('unsupported-limits',arg(valid,limits={'side':1025}),'Limits')
    exact_text=len(model.encode());exact_png=len(entries[path_sprite('test:block/tex')])
    add('exact-budget-boundaries',arg(valid,limits={'models':1,'depth':0,'text':exact_text,'png':exact_png,'bytes':exact_text+exact_png,'sprites':1,'pixels':64,'side':5}))
    bad_zip=archive('archive-crc',{path_model('test:block/a'):model},zipfile.ZIP_STORED)
    data=bytearray(bad_zip.read_bytes());offset=30+len(path_model('test:block/a').encode());data[offset]^=1;bad_zip.write_bytes(data)
    add('archive-entry-crc',arg(bad_zip),'Archive')
    add('archive-open-error',arg(BUILD/'not-present.zip'),'ArchiveOpen')
    if '--prepare-only' in sys.argv:
        (BUILD/'cases.json').write_text(json.dumps({'cases':cases,'configs':configs},indent=2)+'\n')
        print(json.dumps({'status':'prepared-native-unverified','cases':len(cases),'fixture_manifest':str(BUILD/'cases.json')},indent=2))
        return
    check=run([BEND,'tests/block_resources.bend','--check-only'])
    assert 'ALL PROOFS CHECK' in check.stdout,check.stdout
    if '--skip-kernel' in sys.argv:
        kernel={'status':'not-run','reason':'explicit --skip-kernel; native validation does not imply a kernel verdict'}
    else:
        try:
            p=subprocess.run([str(BEND),'src/block_resources.bend','--verdict'],cwd=ROOT,env=ENV,capture_output=True,text=True,timeout=60)
            kernel={'exit_code':p.returncode,'output':(p.stdout+p.stderr).strip(),'timeout_seconds':60,'status':'passed' if p.returncode==0 and 'ALL PROOFS CHECK' in p.stdout else 'failed'}
            assert kernel['status']=='passed',kernel
        except subprocess.TimeoutExpired as error:
            def decoded(v):return v.decode(errors='replace') if isinstance(v,bytes) else (v or '')
            kernel={'status':'inconclusive-timeout','exit_code':None,'timeout_seconds':60,'output':decoded(error.stdout)+decoded(error.stderr)}
    source_fingerprint=fingerprint()
    stamp=BUILD/'native-build.json'
    if '--reuse-build' not in sys.argv:
        run([BEND,'tests/block_resources.bend','-o',BIN])
        assert fingerprint()==source_fingerprint,'native source changed during build'
        stamp.write_text(json.dumps({'sources':source_fingerprint,'binary_sha256':sha(BIN.read_bytes())},indent=2)+'\n')
    else:
        cached=json.loads(stamp.read_text())
        assert cached['sources']==source_fingerprint,'reused native build has different source dependencies'
        assert cached['binary_sha256']==sha(BIN.read_bytes()),'reused native binary differs'
    results=native(configs)
    summaries=[];successes=0
    for case,config,result in zip(cases,configs,results):
        code=case['expected_code']
        if code is not None:
            assert result['status']=='error' and result['code']==code,(case,result)
            summaries.append({'name':case['name'],'code':code,'resource':result['resource']});continue
        assert result['status']=='ok',(case,result)
        assert result['roots']==sorted(set(('minecraft:'+s if ':' not in s else 'minecraft'+s if s.startswith(':') else s) for s in config['roots']))
        assert [s['id'] for s in result['sprites']]==sorted(s['id'] for s in result['sprites'])
        hashes=verify_pixels(result,config['path'])
        assert result['usage']==usage_bytes(result,config['path']),(case,result['usage'])
        if config['path']==str(JAR):
            with zipfile.ZipFile(JAR) as z:
                for id in result['source']:
                    assert z.read(path_model(id)).decode()==reference['inputs']['models'][id],(id,'reference source identity')
            verify_models(result,reference)
        successes+=1;summaries.append({'name':case['name'],'usage':result['usage'],'rgba_sha256':hashes})
    assert results[0]==results[1], 'reordered/duplicated normalized roots changed catalog'
    assert [s['id'] for s in results[0]['sprites']]==['minecraft:block/dirt','minecraft:block/oak_planks','minecraft:block/stone']
    close_configs=[configs[0],*[configs[next(i for i,c in enumerate(cases) if c['name']==name)] for name in ['two-model-cycle','malformed-json','png-crc','metadata-animation','archive-entry-crc']]]
    closed=[closed_observation(c) for c in close_configs]
    # Reproducible whole report, including every resource model field and pixel.
    second=native(configs);assert results==second,'two native runs differ'
    assert fingerprint()==source_fingerprint,'native source dependencies changed during verification'
    canonical=json.dumps(results,sort_keys=True,separators=(',',':')).encode()
    evidence={'schema':1,'time_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'passed','cases':len(cases),'successes':successes,'rejections':len(cases)-successes,'two_native_runs_equal':True,'canonical_report_sha256':sha(canonical),'native_source_fingerprint':source_fingerprint,'native_binary_sha256':sha(BIN.read_bytes()),'jar_sha256':jar_sha,'model_reference_sha256':sha(REFERENCE.read_bytes()),'sources':{p:sha((ROOT/p).read_bytes()) for p in ['src/block_resources.bend','tests/block_resources.bend','tools/test_block_resources.py']},'validation':{'ordinary':check.stdout.strip(),'kernel':kernel,'native_build':'pinned Bend 2.0.35, window-free CPU driver','launch_environment':'BEND_MINECRAFT_LAUNCH_MODE=hidden','model_oracle':'executed official 26.3 CuboidModel/ResolvedModel reference fields; float raw bits','pixel_oracle':'Pillow RGBA every byte, Image tree readback','archive_closed':closed},'cases_detail':summaries,'policy_boundary':'StaticNormalized UV0..1 per image, explicit caller layer; no animation or texture metadata, atlas stitching, resource packs or Java final-frame claim'}
    target=ROOT/'evidence/block-resources-native.json';target.write_text(json.dumps(evidence,indent=2,sort_keys=True)+'\n')
    print(json.dumps({'status':'passed','cases':len(cases),'successes':successes,'evidence':str(target),'report_sha256':sha(canonical)},indent=2))

if __name__=='__main__':main()
