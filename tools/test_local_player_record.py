#!/usr/bin/env python3
"""Independent custom LocalPlayer NBT wire fixtures; no host game implementation."""
from __future__ import annotations
import argparse, ast, copy, dataclasses, hashlib, json, math, os, random, signal, struct, subprocess, sys, time
from pathlib import Path
import test_nbt as N
import test_player_codec as P
import test_player_record as PR
import test_player_look as PL

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/local-player-record/generation-1'
BEND = Path('/Users/chuah/.bend/bin/bend')
ENTRY = ROOT / 'tests/local_player_record.bend'
SOURCE = ROOT / 'src/local_player_record.bend'
STORAGE = ROOT / 'src/local_player_storage.bend'
BINARY = BUILD / 'tests'
FIELDS = ('format','motion','local_keys','local_floats','local_trigger','local_crouching','sprinting','pose','eye','minor','fall_distance','old_positions','invulnerable_time','tick_count')
NAME = N.text('bendex:local-player-record')
EYES = {0:1070554153,5:1067618140}
HEIGHTS = {0:1072064102,5:1069547520}

class Invalid(ValueError):
    pass

@dataclasses.dataclass(frozen=True)
class Record:
    motion: bytes
    local_keys: tuple[int,...]
    local_floats: tuple[int,...]
    local_trigger: int
    local_crouching: int
    sprinting: int
    pose: int
    eye: int
    minor: int
    fall_distance: int
    old_positions: tuple[int,...]
    invulnerable_time: int
    tick_count: int

@dataclasses.dataclass(frozen=True)
class Case:
    name: str
    data: bytes
    expected: bytes | None
    error: str | None
    mode: str = 'record'
    category: str = 'constructed'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')


def root(record):
    """Canonical physical NBT tree; deliberately does not validate input."""
    r=record
    return N.RootTag(NAME,P.compound([
        ('format',N.Value(3,1)),('motion',N.Value(7,r.motion)),
        ('local_keys',N.Value(7,bytes(r.local_keys))),('local_floats',P.listing(5,r.local_floats)),
        ('local_trigger',N.Value(3,r.local_trigger)),('local_crouching',N.Value(1,r.local_crouching)),
        ('sprinting',N.Value(1,r.sprinting)),('pose',N.Value(3,r.pose)),('eye',N.Value(5,r.eye)),
        ('minor',N.Value(1,r.minor)),('fall_distance',N.Value(6,r.fall_distance)),
        ('old_positions',P.listing(6,r.old_positions)),('invulnerable_time',N.Value(3,r.invulnerable_time)),
        ('tick_count',N.Value(3,r.tick_count))]))


def validate(record):
    r=record
    try:
        motion,look=PR.decode(r.motion)
        words,dimension=P.parse_snapshot(motion)
    except (ValueError,UnicodeError,struct.error):
        raise Invalid('MotionError') from None
    if dimension!='minecraft:overworld': raise Invalid('UnsupportedDimension')
    if len(r.local_keys)!=7 or any(x not in (0,1) for x in r.local_keys): raise Invalid('SchemaError')
    if len(r.local_floats)!=6 or any(not PL.finite32(x) for x in r.local_floats): raise Invalid('InputError')
    if any(x not in (0,1) for x in (r.local_crouching,r.sprinting,r.minor)): raise Invalid('SchemaError')
    if r.pose not in EYES: raise Invalid('UnsupportedPose')
    if words[24]!=0x3f19999a or words[25]!=HEIGHTS[r.pose] or r.eye!=EYES[r.pose]: raise Invalid('PoseError')
    if P.bits64(words[6:18])!=P.make_box(P.bits64(words[:6]),words[24],words[25]): raise Invalid('PoseError')
    if r.fall_distance & 0x7ff0000000000000 == 0x7ff0000000000000: raise Invalid('HistoryError')
    if len(r.old_positions)!=6 or any(x & 0x7ff0000000000000 == 0x7ff0000000000000 for x in r.old_positions): raise Invalid('EntityError')
    return dataclasses.replace(r,motion=PR.encode(motion,look))


def encode(record):
    data=N.encode_root(root(validate(record)))
    if len(data)>16384: raise Invalid('NbtError')
    return data


def decode(data):
    try:
        tree=N.Reader(data,max_bytes=16384,max_depth=2,max_elements=8192).root()
    except (ValueError,UnicodeError,struct.error):
        raise Invalid('NbtError') from None
    if tree.name!=NAME: raise Invalid('SchemaError')
    try:
        fs=P.fields(tree.value,FIELDS)
        if P.scalar(fs['format'],3)!=1: raise ValueError('version')
    except (ValueError,UnicodeError,struct.error):
        raise Invalid('SchemaError') from None
    if fs['motion'].kind!=7: raise Invalid('SchemaError')
    # The production decoder checks embedded motion before remaining schema.
    try: PR.decode(fs['motion'].payload)
    except (ValueError,UnicodeError,struct.error): raise Invalid('MotionError') from None
    try:
        if fs['local_keys'].kind!=7 or len(fs['local_keys'].payload)!=7: raise ValueError('keys')
        keys=tuple(fs['local_keys'].payload)
        if any(k not in (0,1) for k in keys): raise ValueError('boolean')
        floats=P.sequence(fs['local_floats'],5,(6,))
        trigger=P.scalar(fs['local_trigger'],3)
        crouch=P.boolean(fs['local_crouching']); sprint=P.boolean(fs['sprinting'])
        pose=P.scalar(fs['pose'],3); eye=P.scalar(fs['eye'],5)
    except (ValueError,UnicodeError,struct.error): raise Invalid('SchemaError') from None
    if pose not in EYES: raise Invalid('UnsupportedPose')
    try:
        minor=P.boolean(fs['minor']); fall=P.scalar(fs['fall_distance'],6)
        inv=P.scalar(fs['invulnerable_time'],3); count=P.scalar(fs['tick_count'],3)
        old=P.sequence(fs['old_positions'],6,(6,))
    except (ValueError,UnicodeError,struct.error): raise Invalid('SchemaError') from None
    return validate(Record(fs['motion'].payload,keys,floats,trigger,crouch,sprint,pose,eye,minor,fall,old,inv,count))


def default_record(*,pose=0):
    words=P.snapshot(position=tuple(map(P.raw64,(0.5,1.0,-2.5))),height=HEIGHTS[pose],speed=0)
    motion=PR.encode(N.encode_root(P.snapshot_root(words,'minecraft:overworld')),PR.look_bytes((0,0,0,0)))
    position=P.bits64(words[:6])
    return Record(motion,(0,)*7,(0,)*6,0,0,0,pose,EYES[pose],0,0,position+position,0,0)


def corpus():
    cases=[]
    def wire(name,data,category='adversarial',mode='record'):
        try:
            expected=encode(decode(data));error=None
            if mode=='pose-tail': expected=None;error='PoseError'
        except Invalid as e: expected=None;error=str(e)
        cases.append(Case(name,data,expected,error,mode,category))
    def record(name,r,category='constructed'):
        wire(name,N.encode_root(root(r)),category)
    base=default_record()
    record('fresh-standing',base)
    record('fresh-crouching',default_record(pose=5))
    rich=dataclasses.replace(base,local_keys=(1,0,1,0,1,1,1),local_floats=(0x80000000,1,0x3f123456,0xbf123456,0x7f7fffff,0xff7fffff),local_trigger=0x80000000,local_crouching=1,sprinting=1,minor=1,fall_distance=0x8000000000000000,old_positions=(0x8000000000000000,1,0x7fefffffffffffff,0xffefffffffffffff,0x3ff123456789abcd,0xbff123456789abcd),invulnerable_time=0xffffffff,tick_count=0xffffffff)
    record('rich-independent-state',rich)
    record('negative-finite-history',dataclasses.replace(rich,fall_distance=P.raw64(-17.25)))
    for i,position in enumerate(((0,0,0),(0x8000000000000000,)*3,(1,0x8000000000000001,1),(0x7fefffffffffffff,0x7fefffffffffffff,0xffefffffffffffff))):
        words=P.snapshot(position=position,velocity=(0x8000000000000000,1,0xffefffffffffffff),speed=0)
        motion=PR.encode(N.encode_root(P.snapshot_root(words,'minecraft:overworld')),PR.look_bytes((0,0,0x7f7fffff,0xff7fffff)))
        record('body-raw-boundary-'+str(i),dataclasses.replace(base,motion=motion))
    words=list(P.snapshot(position=(0,0,0),speed=0))
    words[8]=0x80000000  # minY numeric zero with a different raw sign.
    motion=PR.encode(N.encode_root(P.snapshot_root(words,'minecraft:overworld')),PR.look_bytes((0,0,0,0)))
    record('numeric-equal-box-wrong-zero-sign',dataclasses.replace(base,motion=motion))
    for broken in (b'',base.motion[:-1],base.motion+b'\0'):
        record('broken-embedded-motion-'+str(len(broken)),dataclasses.replace(base,motion=broken))
    for i in range(7): record('sampled-key-'+str(i),dataclasses.replace(base,local_keys=tuple(int(j==i) for j in range(7))))
    for word in (0,1,0x7fffffff,0x80000000,0xffffffff):
        record('signed-counters-'+str(word),dataclasses.replace(base,local_trigger=word,invulnerable_time=word,tick_count=word))
    rng=random.Random(0x10ca1263)
    def finite32():
        while True:
            w=rng.getrandbits(32)
            if PL.finite32(w): return w
    def finite64():
        while True:
            w=rng.getrandbits(64)
            if w&0x7ff0000000000000!=0x7ff0000000000000: return w
    for i in range(220):
        pose=rng.choice((0,5))
        r=default_record(pose=pose)
        # Independently canonical finite Body includes ordinary position, arbitrary
        # finite velocity, signed counters/support and four look words.
        look=(P.raw32(rng.uniform(-1e5,1e5)),P.raw32(rng.uniform(-90,90)),finite32(),finite32())
        words=P.snapshot(position=tuple(P.raw64(rng.uniform(-1e4,1e4)) for _ in range(3)),velocity=tuple(finite64() for _ in range(3)),height=HEIGHTS[pose],flags=tuple(rng.randrange(2) for _ in range(4)),inputs=tuple(finite32() for _ in range(3)),jumping=rng.randrange(2),delay=rng.getrandbits(32),trigger=rng.getrandbits(32),sync=rng.randrange(2),speed=finite32(),head=finite32(),yaw=PR.projection(look[0]),pitch=PR.projection(look[1]),support=tuple(rng.getrandbits(32) for _ in range(3)) if rng.randrange(2) else None,support_flag=rng.randrange(2))
        motion=PR.encode(N.encode_root(P.snapshot_root(words,'minecraft:overworld')),PR.look_bytes(look))
        record('random-'+str(i),dataclasses.replace(r,motion=motion,local_keys=tuple(rng.randrange(2) for _ in range(7)),local_floats=tuple(finite32() for _ in range(6)),local_trigger=rng.getrandbits(32),local_crouching=rng.randrange(2),sprinting=rng.randrange(2),minor=rng.randrange(2),fall_distance=finite64(),old_positions=tuple(finite64() for _ in range(6)),invulnerable_time=rng.getrandbits(32),tick_count=rng.getrandbits(32)),'independent-random')
    for i in range(6):
        for w in (0x7f800000,0xff800000,0x7fc00001):
            fs=list(base.local_floats);fs[i]=w
            record(f'nonfinite-local-{i}-{w}',dataclasses.replace(base,local_floats=tuple(fs)))
    for w in (0x7ff0000000000000,0xfff0000000000000,0x7ff8000000000001):
        record(f'nonfinite-fall-{w}',dataclasses.replace(base,fall_distance=w))
        for i in range(6):
            old=list(base.old_positions);old[i]=w
            record(f'nonfinite-old-{i}-{w}',dataclasses.replace(base,old_positions=tuple(old)))
    for pose in (1,2,3,4,6,7,0xffffffff): record('unsupported-pose-'+str(pose),dataclasses.replace(base,pose=pose))
    for eye in (0,0x80000000,0x7f800000,EYES[5],EYES[0]+1): record('wrong-eye-'+str(eye),dataclasses.replace(base,eye=eye))
    record('crouch-standing-body',dataclasses.replace(base,pose=5,eye=EYES[5]))
    record('standing-crouch-body',dataclasses.replace(default_record(pose=5),pose=0,eye=EYES[0]))
    for dim in ('minecraft:the_nether','minecraft:the_end'):
        words=P.snapshot()
        motion=PR.encode(N.encode_root(P.snapshot_root(words,dim)),PR.look_bytes((0,0,0,0)))
        record(dim,dataclasses.replace(base,motion=motion))
    tree=root(base)
    for name in FIELDS:
        v=copy.deepcopy(tree.value)
        v=N.Value(10,tuple((n,x) for n,x in v.payload if n!=N.text(name)))
        wire('missing-'+name,N.encode_root(N.RootTag(NAME,v)))
        wire('duplicate-'+name,N.encode_root(N.RootTag(NAME,N.Value(10,tree.value.payload+tuple((n,x) for n,x in tree.value.payload if n==N.text(name))))))
        for kind,value in ((3,123),(5,0),(8,N.text('x'))):
            if P.fields(tree.value,FIELDS)[name].kind==kind: continue
            v=P.replace_field(tree.value,name,N.Value(kind,value))
            wire(f'type-{name}-{kind}',N.encode_root(N.RootTag(NAME,v)))
    wire('unexpected',N.encode_root(N.RootTag(NAME,N.Value(10,tree.value.payload+((N.text('extra'),N.Value(1,0)),)))))
    wire('version2',N.encode_root(N.RootTag(NAME,P.replace_field(tree.value,'format',N.Value(3,2)))))
    wire('wrong-root',N.encode_root(N.RootTag(N.text('bendex:player-record'),tree.value)))
    wire('wrong-root-kind',N.encode_root(N.RootTag(NAME,N.Value(3,1))))
    for n in (0,6,8): wire('key-count-'+str(n),N.encode_root(N.RootTag(NAME,P.replace_field(tree.value,'local_keys',N.Value(7,bytes(n))))))
    for bad in (2,255): record('bad-key-'+str(bad),dataclasses.replace(base,local_keys=(bad,0,0,0,0,0,0)))
    for field in ('local_crouching','sprinting','minor'):
        wire('bad-bool-'+field,N.encode_root(N.RootTag(NAME,P.replace_field(tree.value,field,N.Value(1,2)))))
    for field,kind,size in (('local_floats',5,6),('old_positions',6,6)):
        for n in (0,5,7): wire(f'list-count-{field}-{n}',N.encode_root(N.RootTag(NAME,P.replace_field(tree.value,field,P.listing(kind,(0,)*n)))))
        wire('list-kind-'+field,N.encode_root(N.RootTag(NAME,P.replace_field(tree.value,field,P.listing(3,(0,)*size)))))
    reversed_root=N.RootTag(NAME,N.Value(10,tuple(reversed(tree.value.payload))))
    wire('reordered-members',N.encode_root(reversed_root),'canonical-order')
    data=N.encode_root(tree)
    for end in sorted(set(range(40))|set(range(len(data)-40,len(data)))|set(range(0,len(data),29))):
        wire('truncated-'+str(end),data[:end],'physical')
    wire('trailing-byte',data+b'\0','physical')
    wire('oversize',data+bytes(16385),'limits')
    wire('huge-bytearray-count',b'\x0a\x00\x00\x07\x00\x01x\x7f\xff\xff\xff','limits')
    wire('excess-depth',N.encode_root(N.RootTag(NAME,P.compound([('x',P.compound([('y',P.compound([]))]))]))),'limits')
    wire('direct-pose-tail',data,'in-memory-admission','pose-tail')
    # Accepted record immediately after each rejection proves same-process recovery.
    recovery=[]
    for c in cases:
        recovery.append(c)
        if c.error: recovery.append(Case('recover-after-'+c.name,data,encode(base),None,'record','recovery'))
    return recovery


def bounded_run(argv,timeout,label):
    """Bound/reap the full process group and retain raw streams before asserting."""
    argv=list(map(str,argv));out=BUILD/(label+'.stdout');err=BUILD/(label+'.stderr');receipt=BUILD/(label+'.json')
    if any(p.exists() for p in (out,err,receipt)): raise RuntimeError('existing attempt artifacts: '+label)
    BUILD.mkdir(parents=True,exist_ok=True)
    started=time.monotonic();timed=False
    with out.open('xb') as of,err.open('xb') as ef:
        proc=subprocess.Popen(argv,cwd=ROOT,start_new_session=True,stdout=of,stderr=ef)
        try: rc=proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed=True;os.killpg(proc.pid,signal.SIGTERM)
            try: rc=proc.wait(timeout=2)
            except subprocess.TimeoutExpired: os.killpg(proc.pid,signal.SIGKILL);rc=proc.wait(timeout=5)
        finally:
            try: os.killpg(proc.pid,signal.SIGKILL)
            except ProcessLookupError: pass
    result={'argv':argv,'timeout_seconds':timeout,'timed_out':timed,'exit_code':rc,'seconds':time.monotonic()-started,'pid':proc.pid,'stdout':str(out.relative_to(ROOT)),'stderr':str(err.relative_to(ROOT)),'stdout_sha256':sha(out.read_bytes()),'stderr_sha256':sha(err.read_bytes())}
    write_json(receipt,result)
    return result,out.read_text(errors='replace'),err.read_text(errors='replace')


def prepared(cases,emit=False):
    files=[];arguments=[]
    for i,c in enumerate(cases):
        inp=BUILD/f'{i:04}.nbt';output=BUILD/f'{i:04}.out'
        if emit:
            if inp.exists() and inp.read_bytes()!=c.data: raise RuntimeError('existing fixture differs')
            inp.parent.mkdir(parents=True,exist_ok=True)
            if not inp.exists(): inp.write_bytes(c.data)
        if not inp.exists() or inp.read_bytes()!=c.data: raise RuntimeError('missing/changed fixture: '+str(inp))
        files.append({'path':str(inp.relative_to(ROOT)),'sha256':sha(c.data),'bytes':len(c.data),'case':c.name,'expected_sha256':sha(c.expected) if c.expected else None,'expected_error':c.error,'mode':c.mode,'category':c.category})
        arguments.append((c.mode,str(inp),str(output)))
    return files,arguments


def filepin(path):
    path=Path(path).absolute()
    return {'path':str(path),'realpath':str(path.resolve()),'bytes':path.stat().st_size,'sha256':sha(path.read_bytes())}


def provenance():
    import build_native as B
    snapshot=B.Snapshot();snapshot.add(BEND,'bend-compiler')
    if sha(BEND.read_bytes())!=B.PINNED_BEND_SHA256: raise RuntimeError('compiler changed')
    base=(BEND.resolve().parent.parent/'bend2/base.bend').resolve()
    for entry in (ENTRY,STORAGE): B.source_graph(entry,base,dict(os.environ),snapshot)
    pending=[Path(__file__),ROOT/'tools/build_native.py'];python={}
    while pending:
        p=pending.pop().resolve()
        if str(p) in python: continue
        python[str(p)]=filepin(p)
        for node in ast.walk(ast.parse(p.read_text())):
            names=[alias.name for alias in node.names] if isinstance(node,ast.Import) else [node.module] if isinstance(node,ast.ImportFrom) and node.module else []
            for name in names:
                target=ROOT/'tools'/(name.split('.')[0]+'.py')
                if target.is_file(): pending.append(target)
    for module in tuple(sys.modules.values()):
        path=getattr(module,'__file__',None)
        if path and Path(path).is_file() and str(Path(path).resolve()).startswith(str(Path(sys.base_prefix).resolve())):
            python[str(Path(path).resolve())]=filepin(path)
    return {'bend_imports':snapshot.manifest(),'python_imports':[python[k] for k in sorted(python)],'python_interpreter':filepin(sys.executable),'compiler':filepin(BEND),'build_environment_sha256':sha(json.dumps({k:os.environ.get(k) for k in ('PATH','CC','BEND_LIB','CPATH','C_INCLUDE_PATH','LIBRARY_PATH','SDKROOT','MACOSX_DEPLOYMENT_TARGET','DYLD_INSERT_LIBRARIES','DYLD_LIBRARY_PATH','DYLD_FRAMEWORK_PATH','LD_PRELOAD')},sort_keys=True).encode())}


def main():
    ap=argparse.ArgumentParser();ap.add_argument('mode',choices=('prepare','audit','ordinary','build','native','kernel'));a=ap.parse_args()
    BUILD.mkdir(parents=True,exist_ok=True);cases=corpus()
    files,arguments=prepared(cases,emit=a.mode=='prepare')
    seal={'source_sha256':sha(SOURCE.read_bytes()),'storage_sha256':sha(STORAGE.read_bytes()),'harness_sha256':sha(ENTRY.read_bytes()),'runner_sha256':sha(Path(__file__).read_bytes()),'oracle_imports':{str(Path(m.__file__).relative_to(ROOT)):sha(Path(m.__file__).read_bytes()) for m in (N,P,PR,PL)},'fixtures':files,'cases':len(cases),'bytes':sum(len(c.data) for c in cases),'native_status':'not executed','kernel_status':'not executed','closure':provenance(),'arguments':[list(x) for x in arguments],'corpus_sha256':sha(json.dumps(files,sort_keys=True).encode())}
    sealpath=BUILD/'prepared.json'
    if a.mode=='prepare':
        if sealpath.exists() and json.loads(sealpath.read_text())!=seal: raise RuntimeError('sealed preparation differs')
        write_json(sealpath,seal)
        summary={'cases':len(cases),'accepted':sum(c.error is None for c in cases),'rejected':sum(c.error is not None for c in cases),'recovery':sum(c.category=='recovery' for c in cases),'corpus_sha256':seal['corpus_sha256'],'full_seal':filepin(sealpath),'source':filepin(SOURCE),'storage':filepin(STORAGE),'harness':filepin(ENTRY),'runner':filepin(Path(__file__)),'bend_imports':len(seal['closure']['bend_imports']),'python_imports':len(seal['closure']['python_imports']),'native_status':'not executed','kernel_status':'not executed','commands':['python3 tools/test_local_player_record.py '+m for m in ('prepare','audit','ordinary','build','native','kernel')]}
        write_json(ROOT/'evidence/local-player-record-prepared.json',summary);print(json.dumps({'prepared':len(cases),'seal_sha256':sha(sealpath.read_bytes())}));return
    if not sealpath.exists() or json.loads(sealpath.read_text())!=seal: raise RuntimeError('changed generation')
    if a.mode=='audit': print(json.dumps({'read_only':True,'cases':len(cases),'seal_sha256':sha(sealpath.read_bytes())}));return
    if a.mode=='ordinary':
        results=[]
        for name,path in (('source',SOURCE),('harness',ENTRY),('storage',STORAGE)):
            r,out,err=bounded_run([BEND,path,'--check-only'],60,'ordinary-'+name);results.append(r)
            if name=='storage':
                if r['exit_code']!=1 or r['timed_out'] or '42 defs rely on unsafe or foreign code' not in out+err or 'Location:' in out+err: raise RuntimeError(out+err)
            elif r['exit_code'] or r['timed_out'] or 'ALL PROOFS CHECK' not in out: raise RuntimeError(out+err)
        write_json(ROOT/'evidence/local-player-record-ordinary.json',{'results':results});return
    if a.mode=='build':
        (BUILD/'build.reserve').open('x').close()
        if BINARY.exists() or (BUILD/'binary.json').exists(): raise RuntimeError('existing build artifact')
        r,out,err=bounded_run([BEND,ENTRY,'-o',BINARY],600,'build')
        if r['exit_code'] or r['timed_out'] or not BINARY.exists(): raise RuntimeError(out+err)
        write_json(BUILD/'binary.json',{'sha256':sha(BINARY.read_bytes()),'build':r});return
    if a.mode=='native':
        pin=json.loads((BUILD/'binary.json').read_text())
        if sha(BINARY.read_bytes())!=pin['sha256']: raise RuntimeError('binary changed')
        reservation=BUILD/'native.reserve';reservation.open('x').close()
        runs=[]
        for run in range(2):
            for start in range(0,len(cases),48):
                batch=cases[start:start+48];argv=[BINARY]
                paths=[]
                for mode,inp,output in arguments[start:start+48]:
                    path=output+'.run'+str(run)
                    if Path(path).exists(): raise RuntimeError('existing native output')
                    paths.append(Path(path));argv.extend((mode,inp,path))
                r,out,err=bounded_run(argv,120,f'native-{run}-{start:04}');runs.append(r)
                lines=out.splitlines();expected=['error='+c.error if c.error else 'ok=record' for c in batch]
                comparison={'case_names':[c.name for c in batch],'expected':expected,'actual':lines,'bytes_match':[not paths[i].exists() if c.expected is None else paths[i].exists() and paths[i].read_bytes()==c.expected for i,c in enumerate(batch)]}
                write_json(BUILD/f'comparison-{run}-{start:04}.json',comparison)
                if r['exit_code'] or r['timed_out'] or lines!=expected or not all(comparison['bytes_match']): raise RuntimeError('native mismatch '+str(start)+' '+err)
        result={'status':'PASS','cases':len(cases),'executions':len(cases)*2,'runs':runs,'source_sha256':seal['source_sha256'],'binary_sha256':pin['sha256'],'scope':'pure custom record; no filesystem transaction/client/vanilla persistence claim'}
        write_json(BUILD/'native.json',result);write_json(ROOT/'evidence/local-player-record-native.json',result);return
    if a.mode=='kernel':
        (BUILD/'kernel.reserve').open('x').close()
        native=json.loads((BUILD/'native.json').read_text())
        if native['status']!='PASS' or native['source_sha256']!=seal['source_sha256']: raise RuntimeError('native comparison required')
        results=[]
        for name,path in (('source',SOURCE),('harness',ENTRY)):
            r,out,err=bounded_run([BEND,path,'--verdict'],60,'kernel-'+name);results.append(r)
            if r['exit_code'] or r['timed_out'] or 'ALL PROOFS CHECK' not in out: break
        result={'results':results,'scope':'only explicit source/harness laws; no universal codec-roundtrip theorem'}
        write_json(ROOT/'evidence/local-player-record-kernel.json',result)
        if len(results)!=2 or any(r['exit_code'] or r['timed_out'] for r in results): raise RuntimeError('kernel did not finish successfully')

if __name__=='__main__': main()
