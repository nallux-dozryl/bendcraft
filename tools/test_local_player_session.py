#!/usr/bin/env python3
"""Actual LocalPlayer session transport/persistence integration verification.

Python specifies independent full local-record/Core wire expectations and owns
bounded host orchestration. Simulation, input, save and native protocols run in
unchanged production Bend. Test packets are explicit verification instrumentation,
not OS keyboard/mouse observations. Build/native phases require a lead grant.
"""
from __future__ import annotations
import argparse, copy, dataclasses, hashlib, json, math, os, signal, struct, subprocess, sys, time, select, socket, importlib, ast
from pathlib import Path
import test_nbt as N
import test_world_codec as WC
import test_player_codec as PC
import test_player_record as PR
import test_player_session as BASE
import test_persistence as P
import test_mcp as MCP
import reference_local_phase_runtime_probe as PH
from reference_inventory import canonical, fingerprint

ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'build/local-player-session'
ENTRY=ROOT/'tests/local_player_session.bend'
SOURCE=ROOT/'src/local_player_session.bend'
BEND=Path('/Users/chuah/.bend/bin/bend')
TABLE=ROOT/'generated/reference_mth_sin.f32'
REFERENCE=ROOT/'reference/local_phase_runtime.json'
NAMESPACE='bendex:local-player-record'
LOCAL_FIELDS=('format','motion','local_keys','local_floats','local_trigger','local_crouching',
              'sprinting','pose','eye','minor','fall_distance','old_positions','invulnerable_time','tick_count')
BUNDLE_FIELDS=BASE.BUNDLE_FIELDS
EXTENSION_FIELDS=BASE.EXTENSION_FIELDS
POSES={'STANDING':0,'CROUCHING':5}
EYES={0:0x3fcf5c29,5:0x3fa28f5c}
HEIGHTS={0:0x3fe66666,5:0x3fc00000}


def require(condition,message):
    if not condition:raise AssertionError(message)
def sha(data):return hashlib.sha256(data).hexdigest()
def exclusive_json(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('xb') as output:output.write(canonical(value)+b'\n')
def unsigned(value):return value&0xffffffff
def finite32(raw):return (raw&0x7f800000)!=0x7f800000
def finite64(raw):return (raw&0x7ff0000000000000)!=0x7ff0000000000000


@dataclasses.dataclass(frozen=True)
class LocalRecord:
    motion:bytes
    keys:tuple[int,...]
    floats:tuple[int,...]
    trigger:int
    crouching:int
    sprinting:int
    pose:int
    eye:int
    minor:int
    distance:int
    old_positions:tuple[int,...]
    invulnerable:int
    count:int


def local_root(record):
    return N.RootTag(N.text(NAMESPACE),WC.compound([
        ('format',WC.integer(1)),('motion',N.Value(7,record.motion)),
        ('local_keys',N.Value(7,bytes(record.keys))),('local_floats',PC.listing(5,record.floats)),
        ('local_trigger',WC.integer(record.trigger)),('local_crouching',WC.byte(record.crouching)),
        ('sprinting',WC.byte(record.sprinting)),('pose',WC.integer(record.pose)),('eye',N.Value(5,record.eye)),
        ('minor',WC.byte(record.minor)),('fall_distance',N.Value(6,record.distance)),
        ('old_positions',PC.listing(6,record.old_positions)),('invulnerable_time',WC.integer(record.invulnerable)),
        ('tick_count',WC.integer(record.count))]))


def validate_local(record):
    motion,look=PR.decode(record.motion);words,dimension=PC.parse_snapshot(motion)
    require(dimension=='minecraft:overworld','Unsupported local runtime dimension')
    require(record.motion==N.encode_root(PR.root(motion,PR.look_words(look))),'Noncanonical nested motion record')
    require(len(record.keys)==7 and all(v in (0,1) for v in record.keys),'Local keys shape/bool')
    require(len(record.floats)==6 and all(finite32(v) for v in record.floats),'Local floats shape/finite')
    require(record.crouching in (0,1) and record.sprinting in (0,1) and record.minor in (0,1),'Local Bool payload')
    require(record.pose in POSES.values() and record.eye==EYES[record.pose],'Stable pose/cached eye')
    require(words[24]==0x3f19999a and words[25]==HEIGHTS[record.pose],'Stable body/pose dimensions')
    require(finite64(record.distance),'Nonfinite fall history')
    require(len(record.old_positions)==6 and all(finite64(v) for v in record.old_positions),'Old-position metadata')
    require(all(0<=v<=0xffffffff for v in (record.trigger,record.invulnerable,record.count)),'Signed Java words')
    return record


def local_bytes(record):
    validate_local(record);data=N.encode_root(local_root(record));require(len(data)<=16384,'Local record limit')
    return data


def decode_local(data):
    root=N.Reader(data,max_bytes=16384,max_depth=2,max_elements=8192).root()
    require(root.name==N.text(NAMESPACE),'Wrong local record root')
    fs=WC.fields(root.value,LOCAL_FIELDS)
    require(fs['format']==WC.integer(1),'Local format')
    require(fs['motion'].kind==7 and fs['local_keys'].kind==7,'Local byte-array types')
    def raw(name,kind):
        require(fs[name].kind==kind,'Local scalar type:'+name);return fs[name].payload
    def listing(name,kind,count):
        value=fs[name];require(value.kind==9 and value.payload[0]==kind and len(value.payload[1])==count,'Local list type/length:'+name)
        require(all(v.kind==kind for v in value.payload[1]),'Local element type:'+name)
        return tuple(v.payload for v in value.payload[1])
    record=LocalRecord(bytes(fs['motion'].payload),tuple(fs['local_keys'].payload),listing('local_floats',5,6),
        raw('local_trigger',3),raw('local_crouching',1),raw('sprinting',1),raw('pose',3),raw('eye',5),raw('minor',1),
        raw('fall_distance',6),listing('old_positions',6,6),raw('invulnerable_time',3),raw('tick_count',3))
    # Decoder accepts arbitrary field order; encoder independently canonicalizes.
    nested_motion,nested_look=PR.decode(record.motion)
    record=dataclasses.replace(record,motion=N.encode_root(PR.root(nested_motion,PR.look_words(nested_look))))
    return validate_local(record)


def observed_record(state):
    """Wire projection of raw actually observed Java fields, no gameplay math."""
    look=tuple(int(v,16) for v in state['rotation_f32_bits']);support=state['support']
    words=(*PC.words64(tuple(int(v,16) for v in state['position']+state['box']+state['velocity'])),
        int(state['width_f32_bits'],16),int(state['height_f32_bits'],16),*map(int,state['body_flags']),
        *(int(v,16) for v in state['input_f32_bits']),int(state['jumping']),unsigned(state['jump_delay']),
        unsigned(state['jump_trigger']),int(state['needs_sync']),int(state['stored_speed_f32_bits'],16),
        int(state['head_yaw_f32_bits'],16),PR.projection(look[0]),PR.projection(look[1]),int(support is not None),
        *((unsigned(v) for v in support) if support is not None else (0,0,0)),int(state['on_ground_no_blocks']))
    require(len(words)==46,'Observed motion word count')
    motion=N.encode_root(PR.root(N.encode_root(PC.snapshot_root(words,'minecraft:overworld')),look))
    record=LocalRecord(motion,tuple(map(int,state['key_presses'])),
        tuple(int(v,16) for v in state['move_vector_f32_bits']+state['bob_f32_bits']),
        unsigned(state['sprint_trigger_time']),int(state['crouching']),int(state['sprinting']),POSES[state['pose']],
        int(state['cached_eye_height_f32_bits'],16),int(state['minor_horizontal_collision']),
        int(state['fall_distance_f64_bits'],16),tuple(int(v,16) for v in state['old_position']+state['position_old']),
        unsigned(state['invulnerable_time_u32']),unsigned(state['tick_count_u32']))
    return validate_local(record)


def bundle_root(model,highwater,record):
    return N.RootTag(N.text('bendex:bundle'),WC.compound([
        ('format',WC.integer(1)),('minecraft',WC.txt('26.3')),('registry',WC.txt(model['registry'])),
        ('peer_highwater',WC.integer(highwater)),('core',N.Value(7,P.canonical_expected(model))),
        ('extension',WC.compound([('namespace',WC.txt(NAMESPACE)),('schema',WC.integer(1)),
                                 ('payload',N.Value(7,local_bytes(record)))]))]))


def bundle_bytes(model,highwater,record):return N.encode_root(bundle_root(model,highwater,record))


def parse_bundle(data,count,identity):
    root=N.Reader(data,max_bytes=16846848,max_depth=6,max_elements=16846848).root()
    require(root.name==N.text('bendex:bundle'),'Bundle root')
    fs=WC.fields(root.value,BUNDLE_FIELDS)
    require(WC.uint(fs['format'])==1 and WC.scalar_text(fs['minecraft'])=='26.3' and WC.scalar_text(fs['registry'])==identity,'Bundle identity/version')
    highwater=WC.uint(fs['peer_highwater']);require(fs['core'].kind==7 and len(fs['core'].payload)<=N.DEFAULT_BYTES,'Core byte-array type/limit')
    world=WC.validate(N.parse(fs['core'].payload),count,identity);ext=WC.fields(fs['extension'],EXTENSION_FIELDS)
    require(WC.scalar_text(ext['namespace'])==NAMESPACE and WC.uint(ext['schema'])==1,'Closed local codec')
    require(ext['payload'].kind==7 and len(ext['payload'].payload)<=16384,'Local byte-array type/limit')
    record=decode_local(ext['payload'].payload);highwater=max(highwater,world['max_peer'] or 0)
    require(highwater<0xffffffff,'Peer range exhausted')
    return world,record,highwater+1


def scene_world(count,identity):
    world=WC.empty_world(count,identity)
    world['sections']=[WC.section(BASE.section_key(x,y,z)) for x in (-16,0) for y in (-16,0) for z in (-16,0)]
    # Exact finite official reference floor. All other loaded cells are explicit air.
    for x in range(-2,3):
        for z in range(-2,3):BASE.set_block(world,x,0,z,1)
    world.update(tick=41,day_time=1200,paused=True,daylight=True,revision=33)
    world['sections'].sort(key=lambda v:v['key']);P.canonical_expected(world)
    return world


def reference_cases():
    data=json.loads(REFERENCE.read_text());summaries=PH.integrity(data)
    # Full raw observer fields are deliberately omitted by compact encoding.
    # integrity validates compact cases and decoded phase snapshots; do not
    # pretend the compact reconstruction has the full raw-case byte hash.
    require(len(data['cases_full_sha256'])==64,'Missing full raw-case reference pin')
    chosen=[]
    for case in data['cases']:
        if case['id'] not in ('scheduled_shift','scheduled_jump','scheduled_sprint_jump','scheduled_zero'):continue
        successful=[]
        for index,step in enumerate(case['steps']):
            if not step['ok']:break
            successful.append({'index':index,'held_mask':step['input']['held_mask'],
                'before':observed_record(step['before']),'after':observed_record(step['after']),
                'projection':step['projection'],'raw':step})
        chosen.append({'id':case['id'],'steps':successful})
    require(sum(len(c['steps']) for c in chosen)==8,'Compatible actual receiver count')
    for case in chosen:
        for step in case['steps']:
            record=step['after'];require(decode_local(local_bytes(record))==record,'Independent Local record wire roundtrip')
    return chosen,data,summaries


SERVER=WORK/'local-player-session-native'
RECEIPT=WORK/'native-build.json'
READY=WORK/'prepared.json'
HOST=WORK/'host-adoption-3'
ARCHIVE=WORK/'lineage/original-generation'
PREVIOUS=WORK/'host-adoption'
PREVIOUS_ARCHIVE=WORK/'lineage/host-adoption-1'
DIAGNOSTIC=WORK/'host-adoption-2-r2'
DIAGNOSTIC_ARCHIVE=WORK/'lineage/host-adoption-2-r2'


def pin(path):
    path=Path(path).resolve(strict=True)
    return {'path':str(path),'bytes':path.stat().st_size,'sha256':sha(path.read_bytes())}


def sealed(value):
    return dict(value,seal_sha256=sha(canonical(value)))


def audit_manifest(path):
    value=json.loads(Path(path).read_bytes());payload={k:v for k,v in value.items() if k!='seal_sha256'}
    require(value.get('schema')==1 and value.get('seal_sha256')==sha(canonical(payload)),'Invalid generation seal')
    for name,item in value['files'].items():
        actual=pin(name);require(actual['sha256']==item['sha256'] and actual['bytes']==item['bytes'],'Changed sealed input '+name)
    return value


def tool_closure(paths):
    pending=list(map(Path,paths));found=set()
    while pending:
        path=pending.pop().resolve()
        if path in found:continue
        require(path.is_file(),'Missing Python helper '+str(path));found.add(path)
        for node in ast.walk(ast.parse(path.read_text())):
            names=([a.name for a in node.names] if isinstance(node,ast.Import) else
                   [node.module] if isinstance(node,ast.ImportFrom) and node.module else [])
            for name in names:
                candidate=ROOT/'tools'/(name.split('.')[0]+'.py')
                if candidate.is_file():pending.append(candidate)
    return sorted(found)


OWNED_GROUPS=None

def register_group(pid,label):
    if OWNED_GROUPS is not None:
        with OWNED_GROUPS.open('ab') as out:out.write(canonical({'pid':pid,'label':label})+b'\n');out.flush();os.fsync(out.fileno())

def group_absent(pid):
    try:os.killpg(pid,0)
    except ProcessLookupError:return True
    return False


def reap(proc):
    # Leader exit alone does not release the owned process group.
    try:os.killpg(proc.pid,signal.SIGKILL)
    except ProcessLookupError:pass
    if proc.poll() is None:proc.wait(timeout=5)
    for _ in range(50):
        if group_absent(proc.pid):return True
        time.sleep(.02)
    return group_absent(proc.pid)


def bounded(argv,timeout,directory,label):
    directory.mkdir(parents=True,exist_ok=True);attempt=directory/(label+'.attempt.json')
    exclusive_json(attempt,{'argv':list(map(str,argv)),'cap_seconds':timeout,'status':'reserved'})
    stdout=directory/(label+'.stdout');stderr=directory/(label+'.stderr');start=time.monotonic();proc=None;error=None;timed=False;rc=None;absent=False;cleanup_error=None
    with stdout.open('xb') as out,stderr.open('xb') as err:
        try:
            proc=subprocess.Popen(list(map(str,argv)),cwd=ROOT,start_new_session=True,stdout=out,stderr=err)
            print(json.dumps({'status':'owned-process-started','phase':label,'pid':proc.pid,'cap_seconds':timeout}),flush=True)
            try:rc=proc.wait(timeout=timeout)
            except subprocess.TimeoutExpired:timed=True
        except BaseException as cause:error=type(cause).__name__+': '+str(cause)
        finally:
            if proc is not None:
                try:absent=reap(proc)
                except BaseException as cause:cleanup_error=type(cause).__name__+': '+str(cause)
                rc=proc.returncode
    receipt={'argv':list(map(str,argv)),'pid':proc.pid if proc else None,'cap_seconds':timeout,'seconds':time.monotonic()-start,
             'timed_out':timed,'exit_code':rc,'launch_error':error,'cleanup_error':cleanup_error,'group_absent':absent,'stdout':pin(stdout),'stderr':pin(stderr)}
    exclusive_json(directory/(label+'.process.json'),receipt)
    return receipt,stdout.read_bytes(),stderr.read_bytes()


def process_ok(receipt):
    require(not receipt['timed_out'] and not receipt['launch_error'] and not receipt['cleanup_error'] and receipt['exit_code']==0 and receipt['group_absent'],'Owned process failed: '+str(receipt))


def sources():return PC.imports([ENTRY,ROOT/'local_player_client.bend',ROOT/'mcp.bend'])


def retained_bridge():
    receipt=BASE.verify_receipt(BASE.source_hashes());build=receipt['builds'][1]
    require(build.get('retries',0)==0,'Retained MCP build retried source generation')
    return BASE.BRIDGE,{'receipt':pin(BASE.RECEIPT),'build':build,'binary':pin(BASE.BRIDGE),'source_generation':receipt['sources_sha256']}


def default_record():
    import test_local_player_record as codec
    value=codec.default_record()
    return LocalRecord(value.motion,value.local_keys,value.local_floats,value.local_trigger,value.local_crouching,value.sprinting,
        value.pose,value.eye,value.minor,value.fall_distance,value.old_positions,value.invulnerable_time,value.tick_count)


def corrupt_fixtures(model,record):
    baseline=bundle_root(model,31,record);members=baseline.value.payload;cases=[]
    def add(name,value):
        data=N.encode_root(value) if isinstance(value,N.RootTag) else value
        try:parse_bundle(data,model['state_count'],model['registry'])
        except (AssertionError,ValueError,OverflowError,IndexError,KeyError):cases.append((name,data));return
        raise AssertionError('Malformed startup fixture accepted independently '+name)
    def outer(name,value):return N.RootTag(baseline.name,N.Value(10,tuple((k,value if k==N.text(name) else v) for k,v in members)))
    def ext(name,value):
        fs=WC.fields(baseline.value,BUNDLE_FIELDS);x=fs['extension']
        return outer('extension',N.Value(10,tuple((k,value if k==N.text(name) else v) for k,v in x.payload)))
    for name,value in [('format',WC.integer(2)),('minecraft',WC.txt('26.4')),('registry',WC.txt('f'*64)),('peer_highwater',WC.integer(0xffffffff)),('core',N.Value(7,b''))]:add('outer-'+name,outer(name,value))
    for field in BUNDLE_FIELDS:
        target=N.text(field)
        add('missing-'+field,N.RootTag(baseline.name,N.Value(10,tuple(m for m in members if m[0]!=target))))
        add('duplicate-'+field,N.RootTag(baseline.name,N.Value(10,members+tuple(m for m in members if m[0]==target))))
        add('type-'+field,outer(field,WC.byte(0)))
    for name in ('bendex:player-record','other:local',''):add('namespace-'+name,ext('namespace',WC.txt(name)))
    for version in (0,2):add('schema-'+str(version),ext('schema',WC.integer(version)))
    for name,replacement in [('keys',dataclasses.replace(record,keys=(2,*record.keys[1:]))),('sample-nan',dataclasses.replace(record,floats=(0x7fc00000,*record.floats[1:]))),
        ('eye',dataclasses.replace(record,eye=0)),('history-inf',dataclasses.replace(record,distance=0x7ff0000000000000)),('pose',dataclasses.replace(record,pose=4))]:
        add('record-'+name,ext('payload',N.Value(7,N.encode_root(local_root(replacement)))))
    for dimension in PC.DIMENSIONS[1:]:
        motion,look=PR.decode(record.motion);words,_=PC.parse_snapshot(motion)
        other=N.encode_root(PR.root(N.encode_root(PC.snapshot_root(words,dimension)),PR.look_words(look)))
        add('dimension-'+dimension,ext('payload',N.Value(7,N.encode_root(local_root(dataclasses.replace(record,motion=other))))))
    for n in (16384,16385):add('record-size-'+str(n),ext('payload',N.Value(7,b'\0'*n)))
    raw=N.encode_root(baseline)
    for n in (0,1,2,8,len(raw)//2,len(raw)-1):add('truncated-'+str(n),raw[:n])
    add('trailing',raw+b'\0')
    return cases


class Runtime:
    observed=[]
    def __init__(self,path,registry,bridge,directory,mode='normal',missing=None):
        self.path,self.registry,self.bridge=Path(path),registry,bridge;self.port=MCP.free_port();self.clients=[];self.raw_clients=[]
        self.directory=directory;directory.mkdir(parents=True,exist_ok=False)
        self.argv=[str(SERVER),'--gpu','off','--threads','2','--',str(TABLE),mode]
        exclusive_json(directory/'attempt.json',{'argv':self.argv,'save':str(path),'mode':mode,'port':self.port,'cap_startup_seconds':20})
        self.stdout=(directory/'stdout').open('xb');self.stderr=(directory/'stderr').open('xb')
        self.process=subprocess.Popen(self.argv,cwd=ROOT,env=BASE.environment(path,self.port,registry,missing),start_new_session=True,
            stdout=subprocess.PIPE,stderr=self.stderr)
        register_group(self.process.pid,'session');self.started=time.monotonic();self.request_log=[];self.failed=None
        try:
            require(select.select([self.process.stdout],[],[],20)[0],'LocalPlayer session readiness timeout')
            line=self.process.stdout.readline();self.stdout.write(line);self.stdout.flush()
            require(line,'LocalPlayer refused startup')
            self.ready=json.loads(line);require(self.ready['port']==self.port,'Readiness port differs')
        except BaseException as cause:self.failed=type(cause).__name__+': '+str(cause);self.stop();raise
        Runtime.observed.append(self)
    def tcp(self,developer=False):
        client=WireTCP(self.port,self.directory/('tcp-'+str(len(self.raw_clients))));self.raw_clients.append(client)
        ping=client.call('ping');require(ping['sequence']==1,'New raw peer sequence')
        if developer:client.call('session.open',{'mode':'developer','token':MCP.TOKEN})
        return client,ping
    def mcp(self,developer=True):
        client=WireMCP(self.bridge,self.port,MCP.TOKEN if developer else None,self.directory/('mcp-'+str(len(self.clients))));self.clients.append(client);client.initialize();ping=client.call('ping')
        require(ping['mode']==('developer' if developer else 'observer'),'MCP capability differs')
        require(ping['sequence']==(3 if developer else 2),'MCP startup sequence differs')
        return client,ping
    def stop(self,kill=False):
        teardown_errors=[]
        for c in self.clients:
            try:c.cleanup()
            except BaseException as cause:teardown_errors.append(type(cause).__name__+': '+str(cause))
        for c in self.raw_clients:
            try:c.close()
            except BaseException as cause:teardown_errors.append(type(cause).__name__+': '+str(cause))
        if self.process.poll() is None:
            try:os.killpg(self.process.pid,signal.SIGKILL if kill else signal.SIGTERM)
            except ProcessLookupError:pass
        try:self.process.wait(timeout=2)
        except subprocess.TimeoutExpired:pass
        absent=reap(self.process)
        rest=self.process.communicate(timeout=5)[0];self.stdout.write(rest);self.stdout.close();self.stderr.close()
        receipt={'argv':self.argv,'pid':self.process.pid,'exit_code':self.process.returncode,'group_absent':absent,
            'seconds':time.monotonic()-self.started,'failure':self.failed,'teardown_errors':teardown_errors,'stdout':pin(self.directory/'stdout'),'stderr':pin(self.directory/'stderr'),
            'tcp_frames':sum(c.count for c in self.raw_clients),'mcp_requests':sum(c.requests for c in self.clients),'mcp_responses':sum(c.responses for c in self.clients)}
        exclusive_json(self.directory/'process.json',receipt)
        require(absent and not teardown_errors,'Session group/transport teardown failed '+str(teardown_errors))
        if self.failed is None:require(not rest and not (self.directory/'stderr').read_bytes(),'Unexpected session lifetime diagnostic')
        if kill:require(self.process.returncode==-9,'Session actual SIGKILL not observed')


def inspect(client,record):
    value=client.call('player.inspect',{})
    expected={'format':NAMESPACE,'nbt_bytes':list(local_bytes(record))}
    require(value==expected,'Actual API full LocalPlayer bytes differ')
    return value


def save(client,path,world,highwater,record,receipts,label):
    value=client.call('world.save',{});data=path.read_bytes();expected=bundle_bytes(world,highwater,record)
    comparison={'label':label,'actual':{'sha256':sha(data),'bytes':len(data)},'expected':{'sha256':sha(expected),'bytes':len(expected)},'response':value}
    receipts.append(comparison)
    require(data==expected,'Actual saved complete Core+local bytes differ '+label)
    require(value=={'status':'durable','published':True,'durable':True,'bytes':len(data),'peer_highwater':highwater},'Save durable response differs')
    actual,local,nextpeer=parse_bundle(data,world['state_count'],world['registry'])
    require(P.canonical_expected(actual)==P.canonical_expected(world) and local==record and nextpeer==highwater+1,'Independent complete saved bundle differs')
    return data


def reject_startup(path,registry,directory,label,missing=None):
    port=MCP.free_port();directory.mkdir(parents=True,exist_ok=False)
    argv=[str(SERVER),'--gpu','off','--threads','1','--',str(TABLE),'normal']
    exclusive_json(directory/'attempt.json',{'argv':argv,'port':port,'input':pin(path) if path.is_file() else None})
    start=time.monotonic();proc=subprocess.Popen(argv,cwd=ROOT,env=BASE.environment(path,port,registry,missing),start_new_session=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    register_group(proc.pid,'startup-refusal');timed=False
    try:out,err=proc.communicate(timeout=20)
    except subprocess.TimeoutExpired:timed=True;reap(proc);out,err=proc.communicate(timeout=5)
    finally:absent=reap(proc)
    (directory/'stdout').write_bytes(out);(directory/'stderr').write_bytes(err)
    receipt={'label':label,'argv':argv,'pid':proc.pid,'exit_code':proc.returncode,'timed_out':timed,'group_absent':absent,
        'seconds':time.monotonic()-start,'stdout':pin(directory/'stdout'),'stderr':pin(directory/'stderr')}
    exclusive_json(directory/'process.json',receipt)
    require(not timed and absent and proc.returncode!=0 and not out and err,'Startup refusal failed '+label)
    require(MCP.TOKEN.encode() not in err,'Startup diagnostic exposed test authentication token')
    with socket.socket() as sock:sock.settimeout(1);require(sock.connect_ex(('127.0.0.1',port))!=0,'Rejected startup retained listener')
    return receipt


def record_with_common(record):
    motion,lookbytes=PR.decode(record.motion);words,_=PC.parse_snapshot(motion);look=PR.look_words(lookbytes)
    inv=record.invulnerable-1 if 0<record.invulnerable<0x80000000 else record.invulnerable
    position=tuple(PC.bits64(words[:6]));updated_look=(look[0],look[1],look[0],look[1])
    return dataclasses.replace(record,motion=N.encode_root(PR.root(motion,updated_look)),old_positions=position+position,
        invulnerable=inv,count=unsigned(record.count+1))


def snapshot_expected(world,record):
    motion,look=PR.decode(record.motion);words,_=PC.parse_snapshot(motion);position=tuple(PC.f64(v) for v in PC.bits64(words[:6]))
    origin=(position[0],position[1]+PC.f32(record.eye),position[2]);blocks=[]
    for z in range(-16,16):
        for y in range(-16,16):
            for x in range(-16,16):
                section=next(v for v in world['sections'] if v['key']==BASE.section_key(x,y,z));state=section['cells'][(x&15)+((z&15)<<4)+((y&15)<<8)]
                if state:
                    require(state in (1,10,15),'Reference snapshot includes unsupported material')
                    blocks.append([PC.raw32(x-origin[0]),PC.raw32(y-origin[1]),PC.raw32(z-origin[2]),state,{1:0,10:1,15:2}[state]])
    return {'tick':world['tick'],'revision':world['revision'],'camera':[0,0,0,words[39],words[40]],'blocks':blocks}

def queue_set(client,world,point,state,at):
    dim,x,y,z=point;stamp=P.stamp(client.call('world.block.set',{'dimension':dim,'x':x,'y':y,'z':z,'state':state},at=at))
    world['pending'].append({'stamp':stamp,'mutation':{'kind':1,'dimension':dim,'x':unsigned(x),'y':unsigned(y),'z':unsigned(z),'state':state}})
    world['pending'].sort(key=lambda p:p['stamp']);return stamp


def actual_cases(registry,count,identity,bridge,directory,cases,saves,checks):
    for case in cases:
        path=directory/(case['id']+'.nbt');world=scene_world(count,identity);record=case['steps'][0]['before'];path.write_bytes(bundle_bytes(world,11,record))
        runtime=Runtime(path,registry,bridge,directory/(case['id']+'-server'))
        try:
            raw,ping=runtime.tcp(True);actor,mping=runtime.mcp();highwater=mping['peer']
            require(ping['peer']==12 and highwater==13,'Restored peer highwater differs')
            inspect(raw,record);inspect(actor,record)
            clock=raw.call('world.clock');require(clock==P.clock(world),'Restored actual reference Core differs')
            for step in case['steps']:
                before_record=record;raw.call('fixture.input',{'held_mask':step['held_mask']});inspect(raw,record)
                transient=raw.call('fixture.transient');require(transient['buttons']==step['held_mask'],'Actual Session.input physical buttons differ')
                before=raw.call('ping')['sequence'];clock=raw.call('simulation.step',{'ticks':1});BASE.apply_tick(world)
                require(raw.call('ping')['sequence']==before+2,'Actual one-tick step sequence differs')
                record=step['after'];require(clock==P.clock(world),'Actual reference Core tick order differs');inspect(raw,record);inspect(actor,record)
                snapshot=raw.call('fixture.snapshot');motion,look=PR.decode(record.motion);words,_=PC.parse_snapshot(motion)
                require(snapshot==snapshot_expected(world,record),'Read-only actual cached-eye snapshot positions/rotation differ')
                inspect(raw,record);require(raw.call('world.clock')==P.clock(world),'Read-only snapshot advanced simulation')
                save(actor,path,world,highwater,record,saves,case['id']+'-'+str(step['index']))
                checks.append({'case':case['id'],'step':step['index'],'record_sha256':sha(local_bytes(record)),
                    'before_sha256':sha(local_bytes(before_record)),'full_fields_exact':True,'core_tick_before_local':True})
            # A held physical key survives delegation but is released explicitly;
            # sampled KeyPresses and all durable fields remain unchanged.
            raw.call('fixture.release');require(raw.call('fixture.transient')['buttons']==0,'Explicit Session.release did not clear physical buttons')
            inspect(raw,record);require(raw.call('world.clock')==P.clock(world),'Release changed Core clock')
            save(actor,path,world,highwater,record,saves,case['id']+'-released')
        except BaseException as cause:runtime.failed=type(cause).__name__+': '+str(cause);raise
        finally:runtime.stop()
        runtime=Runtime(path,registry,bridge,directory/(case['id']+'-restart'))
        try:
            raw,ping=runtime.tcp(True);require(ping['peer']==highwater+1,'Restart peer allocation differs')
            inspect(raw,record);require(raw.call('fixture.transient')['buttons']==0,'Cold startup restored held physical keys')
            require(raw.call('world.clock')==P.clock(world),'Cold startup replaced saved clock')
            save(raw,path,world,ping['peer'],record,saves,case['id']+'-cold-restart')
        except BaseException as cause:runtime.failed=type(cause).__name__+': '+str(cause);raise
        finally:runtime.stop()

def due_tests(registry,count,identity,bridge,directory,cases,saves,checks):
    case=next(c for c in cases if c['id']=='scheduled_shift');first=case['steps'][0]
    for fail in (False,True):
        label='due-unsupported-control-fit' if fail else 'due-equivalent-fullcube'
        path=directory/(label+'.nbt');world=scene_world(count,identity);record=first['before'];path.write_bytes(bundle_bytes(world,20,record))
        runtime=Runtime(path,registry,bridge,directory/(label+'-server'))
        try:
            raw,ping=runtime.tcp(True);actor,mping=runtime.mcp();highwater=mping['peer']
            raw.call('fixture.input',{'held_mask':first['held_mask']})
            point=('minecraft:overworld',0,1,0) if fail else ('minecraft:overworld',2,0,2)
            queue_set(raw,world,point,2 if fail else 10,world['tick']+1)
            inspect(raw,record);require(raw.call('world.clock')==P.clock(world),'Scheduling advanced runtime')
            require(raw.call('simulation.step',{'ticks':1})['tick']==world['tick']+1,'Due-step clock')
            BASE.apply_tick(world);record=record_with_common(record) if fail else first['after']
            inspect(raw,record);require(raw.call('world.clock')==P.clock(world),'Due edit did not precede local/common tick')
            error=raw.call('fixture.transient')['last_error']
            require((error!='none')==fail,'Checked unsupported state did not produce separate runtime policy error')
            save(actor,path,world,highwater,record,saves,label)
            if fail:
                # The checked local anchor is retained after common state commits;
                # repair the same real Core cell before the next actual local tick.
                queue_set(raw,world,point,0,world['tick']+1)
                raw.call('simulation.step',{'ticks':1});BASE.apply_tick(world)
                record=dataclasses.replace(first['after'],count=unsigned(first['after'].count+1))
                inspect(raw,record);require(raw.call('fixture.transient')['last_error']=='none','Successful recovery retained prior local error')
                save(actor,path,world,highwater,record,saves,label+'-recovered')
            checks.append({'case':label,'policy_not_Java_exception_atomicity':fail,'full_record_sha256':sha(local_bytes(record)),
                'core_sha256':sha(P.canonical_expected(world)),'scheduled_edit_before_local':True})
        except BaseException as cause:runtime.failed=type(cause).__name__+': '+str(cause);raise
        finally:runtime.stop()


def protocol_tests(registry,count,identity,bridge,directory,record,saves,checks):
    world=scene_world(count,identity);path=directory/'protocol.nbt';path.write_bytes(bundle_bytes(world,40,record))
    runtime=Runtime(path,registry,bridge,directory/'protocol-server')
    try:
        raw,ping=runtime.tcp();actor,dping=runtime.mcp();observer,oping=runtime.mcp(False);highwater=oping['peer']
        names={item['name']:item for item in actor.request('tools/list')['result']['tools']}
        require('player.inspect' in names and 'simulation.step' in names and 'world.save' in names,'Actual MCP discovery lacks consumer operations')
        require(not any(name.startswith('fixture.') for name in names),'Synthetic fixture operations leaked into production MCP discovery')
        inspect(observer,record);observer.call('simulation.step',{'ticks':1},fault='PermissionDenied');observer.call('world.save',{},fault='PermissionDenied')
        observer.call('world.save',{'unknown':True},fault='InvalidArguments');observer.call('player.inspect',{},at=0,fault='InvalidArguments')
        before_owner=raw.call('session.open',{'mode':'developer','token':MCP.TOKEN});raw.call('fixture.input',{'held_mask':127})
        transient=raw.call('fixture.transient');raw.call('fixture.release');require(raw.call('fixture.transient')['buttons']==0,'Release all held keys')
        # Strict field/lexeme checks and exact dispatched sequence counting.
        for args in ({},{'ticks':0},{'ticks':1001},{'ticks':-1},{'ticks':1.5},{'ticks':1.0},{'ticks':True},{'ticks':'1'},{'ticks':None},{'ticks':1,'extra':0}):
            before=raw.call('ping')['sequence'];raw.call('simulation.step',args,fault='InvalidArguments')
            require(raw.call('ping')['sequence']==before+2,'Rejected valid envelope sequence count')
            inspect(raw,record);require(raw.call('world.clock')==P.clock(world),'Rejected step changed Core/local record')
        for at in (0,2,None):raw.call('simulation.step',{'ticks':1},at=at,fault='InvalidArguments' if at is not None else 'InvalidRequest')
        for request in ({'op':'simulation.step','args':{'ticks':1}},{'id':'bad','op':2,'args':{}},{'id':'bad','op':'simulation.step','args':[]}):
            before=raw.call('ping')['sequence'];answer=raw.raw(MCP.encode(request));require(answer['ok'] is False,'Malformed envelope admitted')
            require(raw.call('ping')['sequence']==before+2,'Malformed envelope dispatch sequence')
        for raw_json in (b'{broken\n',b'{"id":"duplicate","op":"simulation.step","args":{"ticks":1},"args":{"ticks":2}}\n'):
            before=raw.call('ping')['sequence'];answer=raw.raw(raw_json);require(answer.get('ok') is False and answer['error']['code']=='invalid_json','Physical JSON failure')
            require(raw.call('ping')['sequence']==before+1,'Physical JSON failure consumed operation sequence')
        answer=raw.raw(b'{"id":"exponent","op":"simulation.step","args":{"ticks":1e0}}\n')
        require(answer.get('ok') is False and answer['error']['code']=='InvalidArguments','Exponent lexeme admitted')
        raw.call('session.open',{'mode':'developer','token':'wrong'},fault='AuthenticationFailed');inspect(raw,record)
        saved=save(actor,path,world,highwater,record,saves,'strict-protocol-recovery')
        latest=actor.call('ping');collision=Path(str(path)+f'.pending-save-{latest["peer"]}-{latest["sequence"]+2}')
        collision.write_bytes(b'unowned-local-session-publication-collision');actor.call('world.save',{},fault='SaveNotPublished')
        require(path.read_bytes()==saved and collision.read_bytes()==b'unowned-local-session-publication-collision','Exclusive save collision lost old/unowned bytes')
        inspect(raw,record);require(raw.call('world.clock')==P.clock(world),'Publication failure lost owned runtime')
        collision.unlink();save(actor,path,world,highwater,record,saves,'publication-refusal-owner-recovered')
        # Paused read/poll waits never schedule ticks. The real session background
        # loop runs, but its paused path must preserve all durable fields.
        clock=actor.call('world.clock');time.sleep(.12);require(actor.call('world.clock')==clock,'Paused actor polling advanced Core')
        inspect(raw,record);raw.call('fixture.snapshot');inspect(raw,record)
        checks.append({'case':'TCP-MCP-protocol','discovery':sorted(names),'strict_rejections':20,'physical_JSON_sequence_separate':True,
            'observer_public_inspect':True,'save_publication_collision_recovery':True,'paused_polling_preserved':True})
        # Actual SIGKILL after an unsaved Core mutation: restart restores the last
        # acknowledged bundle rather than unsaved state or held physical input.
        raw.call('fixture.input',{'held_mask':1});actor.call('world.time.set',{'day_time':999});require(path.read_bytes()==saved,'Unsaved mutation modified durable bytes')
        runtime.stop(kill=True);runtime=None
        restored=Runtime(path,registry,bridge,directory/'protocol-restart');runtime=restored
        raw,rping=runtime.tcp(True);inspect(raw,record);require(raw.call('world.clock')==P.clock(world),'SIGKILL restart lost acknowledged Core')
        require(rping['peer']==highwater+1 and raw.call('fixture.transient')['buttons']==0,'SIGKILL restart physical reset/highwater')
        save(raw,path,world,rping['peer'],record,saves,'SIGKILL-acknowledged-bundle-restart')
    except BaseException as cause:
        if runtime:runtime.failed=type(cause).__name__+': '+str(cause)
        raise
    finally:
        if runtime:runtime.stop()


def prime_owner_request(client,deadline,operation):
    remaining=deadline-time.monotonic();require(remaining>0,'Actual paused timer diagnostic prime timed out')
    timeout=client.socket.gettimeout();client.socket.settimeout(remaining)
    try:return client.call(operation)
    finally:client.socket.settimeout(timeout)


def prime_owner_diagnostic(client,mode):
    # The real 50ms Pulse validates State/Motion ownership before checking pause.
    # Every observed projection must be one of two explicit complete copies.
    diagnosed=mode in ('state-owners','motion-owners');start=time.monotonic();deadline=start+1.0
    owner=prime_owner_request(client,deadline,'fixture.owners');transient=prime_owner_request(client,deadline,'fixture.transient');initial_owner=copy.deepcopy(owner);initial_transient=copy.deepcopy(transient)
    clear=copy.deepcopy(owner);changed=copy.deepcopy(owner);clear_transient=copy.deepcopy(transient);changed_transient=copy.deepcopy(transient)
    diagnostic='some:local-player-tail:0';samples=[];seen_owner=0;seen_transient=0
    if diagnosed:
        text=owner['root']['metadata'];none_suffix=';none{}/';error_suffix=';'+diagnostic+'{}/'
        require(text.endswith(none_suffix) or text.endswith(error_suffix),'Unexpected initial root diagnostic')
        prefix=text[:-len(none_suffix)] if text.endswith(none_suffix) else text[:-len(error_suffix)]
        clear['root']['metadata']=prefix+none_suffix;changed['root']['metadata']=prefix+error_suffix
        require(transient['last_error'] in ('none',diagnostic),'Unexpected initial transient diagnostic')
        clear_transient['last_error']='none';changed_transient['last_error']=diagnostic
    else:
        require(transient['last_error']=='none' and owner['root']['metadata'].split(';',6)[6].startswith('none{'),'Paused Metadata/Pose diagnostic must remain none')
    for index in range(256):
        owner_state=0 if owner==clear else 1 if diagnosed and owner==changed else -1
        transient_state=0 if transient==clear_transient else 1 if diagnosed and transient==changed_transient else -1
        require(owner_state>=0 and transient_state>=0,'Diagnostic prime changed another complete owner or physical field')
        require(owner_state>=seen_owner and owner_state>=seen_transient and transient_state>=seen_transient and transient_state>=owner_state,'Diagnostic prime was not monotonic')
        seen_owner=owner_state;seen_transient=transient_state;elapsed=time.monotonic()-start;require(elapsed<=1.0,'Actual paused timer diagnostic prime timed out')
        samples.append({'index':index,'seconds':elapsed,'owner_state':owner_state,'transient_state':transient_state,
            'owner_sha256':sha(canonical(owner)),'transient_sha256':sha(canonical(transient))})
        if (diagnosed and owner_state==1 and transient_state==1) or (not diagnosed and elapsed>=.06):
            prime={'mode':mode,'cap_seconds':1.0,'max_samples':256,'samples':samples,
                'initial_owner_sha256':sha(canonical(initial_owner)),'initial_transient_sha256':sha(canonical(initial_transient)),
                'initial_already_diagnosed':diagnosed and initial_owner==changed,
                'owner_none_to_error_observed':diagnosed and initial_owner==clear,
                'expected_none_sha256':sha(canonical(clear)),'expected_error_sha256':sha(canonical(changed)) if diagnosed else None,
                'physical_and_all_other_owner_fields_exact':True,'scheduled_step_calls':0}
            return owner,transient,prime
        require(time.monotonic()<deadline,'Actual paused timer diagnostic prime timed out')
        time.sleep(.002);owner=prime_owner_request(client,deadline,'fixture.owners');transient=prime_owner_request(client,deadline,'fixture.transient')
    raise AssertionError('Actual paused timer diagnostic prime exceeded bounded sample count')


def owner_tests(registry,count,identity,bridge,directory,record,checks):
    for mode in ('state-owners','motion-owners','metadata-owners','pose-owners'):
        path=directory/(mode+'.nbt');world=scene_world(count,identity);initial=bundle_bytes(world,60,record);path.write_bytes(initial)
        runtime=Runtime(path,registry,bridge,directory/(mode+'-server'),mode)
        try:
            raw,ping=runtime.tcp(True);actor,ap=runtime.mcp();observer,op=runtime.mcp(False)
            before,transient,prime=prime_owner_diagnostic(raw,mode)
            if mode=='state-owners':
                children=before['state_children'];require(len(children)==2 and children[0]['table_digest']!=children[1]['table_digest'],'Distinct owned tables not witnessed')
                require(children[0]['motion']['world']['clock']!=children[1]['motion']['world']['clock'],'Distinct child clocks not witnessed')
                require(children[0]['motion']['world']['pending']!=children[1]['motion']['world']['pending'],'Distinct child queues not witnessed')
            if mode=='motion-owners':require(len(before['motion_children'])==2 and before['motion_children'][0]['world']['pending']!=before['motion_children'][1]['world']['pending'],'Distinct MH owned queues not witnessed')
            # Eligibility priority precedes complete-state validation.
            raw.call('world.save',{'unexpected':1},fault='InvalidArguments');observer.call('world.save',{},fault='PermissionDenied')
            observer.call('world.save',{'unexpected':1},fault='InvalidArguments');observer.call('player.inspect',{'unexpected':1},fault='InvalidArguments')
            raw.call('world.save',{},fault='SaveEncodingFailed');raw.call('player.inspect',{},fault='InvalidPlayerState')
            require(path.read_bytes()==initial,'Rejected noncanonical save wrote durable bytes')
            require(raw.call('world.clock')==P.clock(world),'Valid delegate read lost root clock')
            require(raw.call('fixture.owners')==before,'Refusal/delegate detachment lost owned child/View/cache/queue/table/metadata tail')
            require(raw.call('fixture.transient')==transient,'Refusal/delegate detachment lost physical controls')
            sequence=raw.call('ping')['sequence'];raw.call('world.save',{},fault='SaveEncodingFailed');require(raw.call('ping')['sequence']==sequence+2,'Guard refusal dispatched sequence')
            checks.append({'case':mode,'owner_projection_sha256':sha(canonical(before)),'full_projection_retained':True,
                'save_and_inspect_refused':True,'eligibility_error_priority':True,'valid_delegate_read_after_refusal':True,
                'table_witness':'all65536-word FNV32 projection plus distinct marker at1234; no cryptographic table-equality theorem','diagnostic_prime':prime})
        except BaseException as cause:runtime.failed=type(cause).__name__+': '+str(cause);raise
        finally:runtime.stop()


def startup_tests(registry,count,identity,bridge,directory,record,corrupt,rejections,saves,checks):
    path=directory/'malformed.nbt';valid=bundle_bytes(scene_world(count,identity),31,record)
    for index,(name,data) in enumerate(corrupt):
        path.write_bytes(data);rejections.append(reject_startup(path,registry,directory/('reject-'+str(index)),name,'create'))
        require(path.read_bytes()==data,'Startup refusal changed original corrupted bundle')
    path.write_bytes(valid);runtime=Runtime(path,registry,bridge,directory/'repaired-startup')
    try:
        actor,ping=runtime.mcp();require(ping['peer']==32,'Repeated corruption refusal did not release lease');inspect(actor,record)
        save(actor,path,scene_world(count,identity),32,record,saves,'corruption-repaired-same-lease-path')
        rejections.append(reject_startup(path,registry,directory/'concurrent-lease','concurrent-lease'))
    except BaseException as cause:runtime.failed=type(cause).__name__+': '+str(cause);raise
    finally:runtime.stop()
    # Root client initial record is independent and contains no scene mutation.
    fresh=directory/'fresh.nbt';runtime=Runtime(fresh,registry,bridge,directory/'fresh-create',missing='create')
    try:
        actor,ping=runtime.mcp();initial=default_record();inspect(actor,initial);world=WC.empty_world(count,identity)
        require(actor.call('world.clock')==P.clock(world),'Fresh production world is not empty canonical Core')
        save(actor,fresh,world,ping['peer'],initial,saves,'official-empty-production-create')
    except BaseException as cause:runtime.failed=type(cause).__name__+': '+str(cause);raise
    finally:runtime.stop()
    checks.append({'case':'closed-local-startup','rejected':len(corrupt),'same_lease_path_recovery':True,'fresh_empty_no_fixture_replacement':True})


def atomic_stage_wait(stream,stage,capture):
    stages=('created','written','synced','published','directory_synced');require(stage in stages,'Unknown selected Atomic stage')
    expected=stages[:stages.index(stage)+1];deadline=time.monotonic()+20;pending=b'';index=0
    while True:
        remaining=deadline-time.monotonic();require(remaining>0,'Atomic stage wait timeout')
        require(select.select([stream.fileno()],[],[],remaining)[0],'Atomic stage wait timeout')
        chunk=os.read(stream.fileno(),4096)
        # Retain raw chunks before framing, validation, EOF or deadline checks.
        capture.append(chunk);require(chunk,'Atomic publisher exited before selected stage')
        pending+=chunk;require(len(pending)<=4096,'Atomic stage line buffer exceeds limit')
        require(time.monotonic()<=deadline,'Atomic stage wait timeout')
        while b'\n' in pending:
            line,pending=pending.split(b'\n',1);line+=b'\n'
            require(index<len(expected) and line==expected[index].encode()+b'\n','Unexpected Atomic stage line')
            index+=1
            if line.decode().strip()==stage:
                require(not pending,'Unexpected bytes after selected Atomic stage')
                return


def atomic_tests(registry,count,identity,bridge,directory,record,saves,rejections,checks):
    old_world=scene_world(count,identity);new_world=copy.deepcopy(old_world);new_world.update(tick=99,day_time=2000)
    new_record=dataclasses.replace(record,trigger=0xffffffff,invulnerable=0x80000000,count=0xffffffff,distance=0xbff0000000000000)
    old=bundle_bytes(old_world,90,record);new=bundle_bytes(new_world,91,new_record);payload=directory/'atomic-new.bin';payload.write_bytes(new)
    for stage in ('created','written','synced','published','directory_synced'):
        path=directory/('atomic-'+stage+'.nbt');path.write_bytes(old);suffix='stage-'+stage.replace('_','-');temporary=Path(str(path)+'.pending-'+suffix)
        folder=directory/('atomic-'+stage);folder.mkdir();env=BASE.environment(path,MCP.free_port(),registry);env['MC_ATOMIC_PAUSE']=stage
        argv=[str(SERVER),'--gpu','off','--threads','1','--','atomic',str(path),suffix,str(payload)]
        exclusive_json(folder/'attempt.json',{'argv':argv,'pause_stage':stage,'payload':pin(payload)})
        proc=subprocess.Popen(argv,cwd=ROOT,env=env,start_new_session=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE);register_group(proc.pid,'atomic');seen=[];start=time.monotonic()
        try:
            atomic_stage_wait(proc.stdout,stage,seen)
            published=stage in ('published','directory_synced');expected=new if published else old
            require(path.read_bytes()==expected,'Publication stage exposed mixed/partial bundle')
            lock=Path(str(path)+'.lock');inode=lock.stat().st_ino
            rejections.append(reject_startup(path,registry,folder/'held-lease','stage-held-lease-'+stage))
            os.killpg(proc.pid,signal.SIGKILL);out,err=proc.communicate(timeout=5);absent=reap(proc)
            (folder/'stdout').write_bytes(b''.join(seen)+out);(folder/'stderr').write_bytes(err)
            exclusive_json(folder/'process.json',{'argv':argv,'pid':proc.pid,'exit_code':proc.returncode,'group_absent':absent,'seconds':time.monotonic()-start,
                'stdout':pin(folder/'stdout'),'stderr':pin(folder/'stderr'),'selected_stage':stage})
            require(proc.returncode==-9 and absent and not out and not err,'Actual stage SIGKILL failed')
            require(path.read_bytes()==expected,'Interruption changed complete generation')
            require((temporary.exists() and temporary.read_bytes()==(b'' if stage=='created' else new)) if not published else not temporary.exists(),'Stage orphan bytes differ')
            runtime=Runtime(path,registry,bridge,folder/'restart')
            try:
                actor,ping=runtime.mcp();world=new_world if published else old_world;current=new_record if published else record
                inspect(actor,current);require(actor.call('world.clock')==P.clock(world),'Interrupted restart crossed Core/record generations')
                require(lock.stat().st_ino==inode,'Interrupted restart replaced held lock inode')
                save(actor,path,world,ping['peer'],current,saves,'separate-stage-restart-'+stage)
            except BaseException as cause:runtime.failed=type(cause).__name__+': '+str(cause);raise
            finally:runtime.stop()
            checks.append({'case':'separate-Atomic-stage-'+stage,'actual_SIGKILL':True,'generation':'new' if published else 'old',
                'complete_bundle_sha256':sha(expected),'scope':'leased Atomic.publish_with primitive; quiet Session.save tested separately'})
        finally:
            absent=reap(proc)
            if not (folder/'process.json').exists():
                out,err=proc.communicate(timeout=5)
                (folder/'stdout').write_bytes(b''.join(seen)+out);(folder/'stderr').write_bytes(err)
                exclusive_json(folder/'process.json',{'argv':argv,'pid':proc.pid,'exit_code':proc.returncode,'group_absent':absent,'status':'interrupted-first-failure',
                    'stdout':pin(folder/'stdout'),'stderr':pin(folder/'stderr')})


def integration_run(seal,bridge,directory):
    directory.mkdir(parents=True,exist_ok=True);exclusive_json(directory/'reservation.json',{'prepared_seal':seal['seal_sha256'],'binary':pin(SERVER),'status':'reserved'})
    registry=P.OFFICIAL;identity,count,_=P.registry_identity(registry);cases,reference,_=reference_cases();record=cases[0]['steps'][0]['before']
    corrupt=corrupt_fixtures(scene_world(count,identity),record);saves=[];rejections=[];checks=[];start=time.monotonic()
    summary={'status':'running','prepared_seal':seal['seal_sha256'],'saves':saves,'rejections':rejections,'checks':checks}
    try:
        actual_cases(registry,count,identity,bridge,directory,cases,saves,checks)
        due_tests(registry,count,identity,bridge,directory,cases,saves,checks)
        continuation_tests(registry,count,identity,bridge,directory,cases,saves,checks)
        rich_restore_tests(registry,count,identity,bridge,directory,saves,checks)
        protocol_tests(registry,count,identity,bridge,directory,record,saves,checks)
        owner_tests(registry,count,identity,bridge,directory,record,checks)
        startup_tests(registry,count,identity,bridge,directory,record,corrupt,rejections,saves,checks)
        atomic_tests(registry,count,identity,bridge,directory,record,saves,rejections,checks)
        activation()
        summary.update(status='PASS',seconds=time.monotonic()-start,binary=pin(SERVER),servers=len(Runtime.observed),
            scope='Actual declared neutral LocalPlayer consumer/TCP/MCP/custom bundled persistence; no OS input/presentation or general gameplay parity')
        exclusive_json(directory/'summary.json',summary);return summary
    except BaseException as cause:
        summary.update(status='FAIL',seconds=time.monotonic()-start,error=type(cause).__name__+': '+str(cause))
        exclusive_json(directory/'summary.json',summary);raise
class WireTCP(BASE.RawTCP):
    def __init__(self,port,prefix):
        super().__init__(port);self.wire_in=Path(str(prefix)+'.requests').open('xb');self.wire_out=Path(str(prefix)+'.responses').open('xb')
    def raw(self,data):
        self.wire_in.write(data);self.wire_in.flush();self.socket.sendall(data)
        line=self.reader.readline(2*1024*1024);self.wire_out.write(line);self.wire_out.flush()
        require(line.endswith(b'\n'),'Actual raw TCP response missing frame');require(MCP.TOKEN.encode() not in line,'Actual raw TCP exposed test token')
        self.count+=1;return json.loads(line)
    def close(self):
        super().close();self.wire_in.close();self.wire_out.close()


class WireMCP(MCP.MCP):
    def __init__(self,binary,port,token,prefix):
        self.prefix=prefix;environment=os.environ.copy();environment['MC_LIVE_PORT']=str(port);environment.pop('MC_DEV_TOKEN',None)
        if token is not None:environment['MC_DEV_TOKEN']=token
        argv=[str(binary),'--threads','1','--gpu','off'];exclusive_json(Path(str(prefix)+'.attempt.json'),{'argv':argv,'port':port,'developer':token is not None})
        self.process=subprocess.Popen(argv,cwd=ROOT,env=environment,start_new_session=True,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        register_group(self.process.pid,'MCP');self.buffer=b'';self.sequence=0;self.live_sequence=0;self.requests=0;self.responses=0;self.notifications=0
        self.wire_in=Path(str(prefix)+'.requests').open('xb');self.wire_out=Path(str(prefix)+'.responses').open('xb')
    def raw(self,data,fragment=False):
        self.wire_in.write(data);self.wire_in.flush();super().raw(data,fragment)
    def receive(self,timeout=5):
        # Persist actual framed stdout before JSON/protocol assertions. The base
        # transport parser is then fed the same bytes without another native read.
        deadline=time.monotonic()+timeout
        while b'\n' not in self.buffer:
            remaining=deadline-time.monotonic();require(remaining>0 and select.select([self.process.stdout],[],[],remaining)[0],'Actual MCP response timeout')
            chunk=os.read(self.process.stdout.fileno(),8192);self.wire_out.write(chunk);self.wire_out.flush();require(chunk,'MCP closed stdout');self.buffer+=chunk
        return super().receive(timeout)
    def cleanup(self):
        failure=None;out=b'';err=b''
        try:
            if self.process.stdin is not None and not self.process.stdin.closed:self.process.stdin.close()
            self.process.wait(timeout=5)
        except BaseException as cause:failure=type(cause).__name__+': '+str(cause)
        finally:
            absent=reap(self.process)
            if self.process.stdout is not None:out=self.process.stdout.read();self.wire_out.write(out)
            if self.process.stderr is not None:err=self.process.stderr.read()
            self.wire_in.close();self.wire_out.close();Path(str(self.prefix)+'.stderr').write_bytes(err)
            exclusive_json(Path(str(self.prefix)+'.process.json'),{'pid':self.process.pid,'exit_code':self.process.returncode,'group_absent':absent,
                'failure':failure,'requests':self.requests,'responses':self.responses,'notifications':self.notifications,
                'stdout':pin(Path(str(self.prefix)+'.responses')),'stderr':pin(Path(str(self.prefix)+'.stderr'))})
        require(absent and self.process.returncode==0 and not err and not out and not self.buffer and failure is None,'MCP teardown error')


def continuation_tests(registry,count,identity,bridge,directory,cases,saves,checks):
    case=next(c for c in cases if c['id']=='scheduled_shift');world=scene_world(count,identity);record=case['steps'][0]['before'];path=directory/'continuation.nbt'
    path.write_bytes(bundle_bytes(world,110,record));runtime=Runtime(path,registry,bridge,directory/'continuation-before')
    try:
        raw,ping=runtime.tcp(True);raw.call('fixture.input',{'held_mask':case['steps'][0]['held_mask']});raw.call('simulation.step',{'ticks':1});BASE.apply_tick(world)
        record=case['steps'][0]['after'];inspect(raw,record);save(raw,path,world,ping['peer'],record,saves,'durable-continuation-before')
    except BaseException as cause:runtime.failed=type(cause).__name__+': '+str(cause);raise
    finally:runtime.stop()
    runtime=Runtime(path,registry,bridge,directory/'continuation-after')
    try:
        raw,ping=runtime.tcp(True);inspect(raw,record);require(raw.call('fixture.transient')['buttons']==0,'Continuation restart did not release physical keys')
        for step in case['steps'][1:]:
            raw.call('fixture.input',{'held_mask':step['held_mask']});raw.call('simulation.step',{'ticks':1});BASE.apply_tick(world)
            record=step['after'];inspect(raw,record);require(raw.call('world.clock')==P.clock(world),'Durable continuation Core mismatch')
            save(raw,path,world,ping['peer'],record,saves,'durable-continuation-after-'+str(step['index']))
        checks.append({'case':'durable-shift-continuation','actual_Java_after_restart_steps':3,'full_sampled_input_pose_history_entity_record_retained':True})
    except BaseException as cause:runtime.failed=type(cause).__name__+': '+str(cause);raise
    finally:runtime.stop()


def rich_restore_tests(registry,count,identity,bridge,directory,saves,checks):
    import test_local_player_record as codec
    selected=[case for case in codec.corpus() if case.error is None and case.category=='independent-random'][:4]
    # Keep representative extreme timer/history/degree records from the original
    # independently constructed corpus; paused restoration makes no move claim.
    if not selected:selected=[case for case in codec.corpus() if case.error is None and case.category.startswith('rich')][:4]
    require(selected,'Frozen record corpus lacks rich admitted records')
    for index,case in enumerate(selected):
        record=decode_local(case.expected);world=scene_world(count,identity);world.update(tick=72,day_time=444,daylight=False)
        world['pending']=[{'stamp':(99,3,5),'mutation':{'kind':2,'day_time':888}}]
        path=directory/('rich-'+str(index)+'.nbt');path.write_bytes(bundle_bytes(world,150+index,record))
        runtime=Runtime(path,registry,bridge,directory/('rich-'+str(index)+'-server'))
        try:
            raw,ping=runtime.tcp(True);inspect(raw,record);require(raw.call('world.clock')==P.clock(world),'Rich restore changed Core clocks/queue')
            require(raw.call('fixture.transient')['buttons']==0,'Rich restore invented held keys')
            time.sleep(.04);inspect(raw,record);save(raw,path,world,ping['peer'],record,saves,'rich-paused-full-record-'+str(index))
            checks.append({'case':'rich-paused-restore','corpus_case':case.name,'record_sha256':sha(local_bytes(record)),'no_movement_at_arbitrary_coordinates_claim':True})
        except BaseException as cause:runtime.failed=type(cause).__name__+': '+str(cause);raise
        finally:runtime.stop()
def environment_pin():
    keys=('PATH','CC','BEND_LIB','CPATH','C_INCLUDE_PATH','LIBRARY_PATH','SDKROOT','MACOSX_DEPLOYMENT_TARGET',
          'DYLD_INSERT_LIBRARIES','DYLD_LIBRARY_PATH','DYLD_FRAMEWORK_PATH','LD_PRELOAD')
    return sha(canonical({name:os.environ.get(name) for name in keys}))


def generation_files():
    import build_native as builder
    snapshot=builder.Snapshot();snapshot.add(BEND,'bend-compiler')
    base=(BEND.resolve().parent.parent/'bend2/base.bend').resolve()
    for entry in (ENTRY,ROOT/'local_player_client.bend',ROOT/'mcp.bend'):builder.source_graph(entry,base,dict(os.environ),snapshot)
    paths={Path(item['path']) for item in snapshot.manifest()}
    paths.update(tool_closure([Path(__file__),ROOT/'tools/build_native.py',ROOT/'tools/test_local_player_record_consumer.py',ROOT/'tools/test_local_phase_runtime.py']))
    from test_local_phase_runtime import phase_contract
    phase=phase_contract();paths.update(Path(name) for name in phase['phase_generation']);paths.add(ROOT/phase['original_preparation']['path'])
    paths.update((ROOT/'docs/LOCAL_PLAYER_SESSION_TESTS.md',TABLE,P.OFFICIAL,REFERENCE,ROOT/'reference/player_tick_phases.json',ROOT/'evidence/local-phase-runtime-reference.json',
                  ROOT/'build/local-player-record/generation-1/prepared.json'))
    data=json.loads(REFERENCE.read_text())
    for item in data['raw_artifacts']:
        path=ROOT/item['path'];require(pin(path)['sha256']==item['sha256'],'Pinned original Java observation artifact changed');paths.add(path)
    # Verify production-class byte tree and artifact pins by reading the original
    # jar/classpath, without invoking Java, javap or any reference metadata probe.
    raw=json.loads((ROOT/data['raw_artifacts'][0]['path']).read_text());command=raw['command'];paths.add(Path(command[0]))
    cp_index=next(command.index(option) for option in ('-cp','-classpath','--class-path') if option in command)
    classpath=[Path(p) for p in command[cp_index+1].split(os.pathsep)]
    paths.update(p for p in classpath if p.is_file())
    require(pin(Path(command[0]))['sha256']==raw['classpath']['java']['sha256'],'Original Java launcher changed')
    for item in raw['classpath']['libraries']:
        matches=[p for p in classpath if p.as_posix().endswith('/libraries/'+item['path'])]
        require(len(matches)==1 and pin(matches[0])['sha256']==item['sha256'],'Original Java oracle library changed '+item['path'])
    from reference_model_probe import CLIENT
    require(pin(CLIENT)['sha256']==raw['classpath']['client']['sha256'],'Original official client jar changed');paths.add(CLIENT)
    import zipfile
    with zipfile.ZipFile(CLIENT) as archive:
        for tree in raw['official_classes']:
            for name,expected in tree.items():
                require(sha(archive.read(name.replace('.','/')+'.class'))==expected,'Untouched Java oracle class changed '+name)
    frozen=json.loads((ROOT/'build/local-player-record/generation-1/prepared.json').read_bytes())
    for row in frozen['fixtures']:paths.add(ROOT/row['path'])
    for items in (frozen['closure']['bend_imports'],frozen['closure']['python_imports']):
        for item in items:paths.add(Path(item['path']))
    # Python standard-library modules actually loaded by this verifier also enter
    # the seal. No account/user application state is read.
    for module in tuple(sys.modules.values()):
        path=getattr(module,'__file__',None)
        if path and Path(path).is_file() and str(Path(path).resolve()).startswith(str(Path(sys.base_prefix).resolve())):paths.add(Path(path).resolve())
    paths.add(Path(sys.executable).resolve())
    return paths,snapshot.manifest(),sha(canonical(raw['official_classes']))


def prepare():
    require(not READY.exists(),'Existing prepared generation; refuse overwrite')
    WORK.mkdir(parents=True,exist_ok=True);fixtures=WORK/'fixtures';fixtures.mkdir(exist_ok=False)
    cases,reference,summaries=reference_cases();identity,count,info=P.registry_identity(P.OFFICIAL);world=scene_world(count,identity)
    record=cases[0]['steps'][0]['before'];corrupt=corrupt_fixtures(world,record);inputs=[]
    for case in cases:
        for step in case['steps']:
            for side in ('before','after'):
                path=fixtures/(case['id']+'-'+str(step['index'])+'-'+side+'.nbt');path.write_bytes(local_bytes(step[side]));inputs.append(path)
        path=fixtures/(case['id']+'-bundle.nbt');path.write_bytes(bundle_bytes(world,11,case['steps'][0]['before']));inputs.append(path)
    for index,(name,data) in enumerate(corrupt):
        path=fixtures/('corrupt-'+str(index)+'.nbt');path.write_bytes(data);inputs.append(path)
    bridge,bridge_receipt=retained_bridge();paths,closure,class_tree=generation_files();paths.update(inputs);paths.add(bridge)
    paths.add(BASE.RECEIPT)
    for item in bridge_receipt['build']['dependencies']:paths.add(Path(item['path']))
    ordinary=[]
    for label,entry in (('harness',ENTRY),('session',SOURCE)):
        receipt,out,err=bounded([BEND,entry,'--check-only'],60,WORK/'ordinary',label)
        text=(out+err).decode();valid=(receipt['exit_code']==1 and 'defs rely on unsafe or foreign code' in text and 'Location:' not in text and not receipt['timed_out']) or receipt['exit_code']==0
        exclusive_json(WORK/'ordinary'/(label+'.comparison.json'),{'ordinary_only':True,'accepted_documented_foreign_boundary':valid,'process':receipt})
        require(valid,'Ordinary source/harness type/law error')
        ordinary.append(receipt)
    files={str(p.resolve()):{k:v for k,v in pin(p).items() if k!='path'} for p in sorted(paths)}
    seal=sealed({'schema':1,'status':'prepared-native-unverified','files':files,'sources_sha256':sources(),
        'environment_sha256':environment_pin(),'registry':info,'reference':pin(REFERENCE),'official_class_tree_sha256':class_tree,
        'actual_compatible_steps':8,'record_cases':755,'startup_rejections':len(corrupt),'ordinary':ordinary,
        'phase_contract':__import__('test_local_phase_runtime').phase_contract(),'facade_stage_guards':3,
        'retained_MCP':bridge_receipt,'corrupt_fixture_names':[name for name,_ in corrupt],
        'frozen_codec_seal_sha256':'14442c45e5eaffb36e8be6413866e3573481724cbcbff6027de359d7fd95bdc9',
        'fixture_files':[pin(p) for p in inputs],'full_Bend_imports':closure})
    exclusive_json(READY,seal);audit_manifest(READY)
    compact={'status':seal['status'],'ready':pin(READY),'seal_sha256':seal['seal_sha256'],'files':len(files),'source_imports':len(closure),
        'source':pin(SOURCE),'runtime':pin(ROOT/'src/local_player_runtime.bend'),'harness':pin(ENTRY),'runner':pin(Path(__file__)),
        'actual_compatible_steps':8,'record_cases':755,'startup_rejections':len(corrupt),'ordinary':ordinary,
        'phase_contract':__import__('test_local_phase_runtime').phase_contract(),'facade_stage_guards':3,
        'retained_MCP_binary':pin(bridge),'native_status':'not executed','commands':['python3 tools/test_local_player_session.py --audit',
            'python3 tools/test_local_player_session.py --build-only','python3 tools/test_local_player_session.py --skip-build']}
    exclusive_json(ROOT/'evidence/local-player-session-prepared.json',compact)
    print(json.dumps(compact),flush=True)


def active_ready():return HOST/'prepared.json' if (HOST/'prepared.json').exists() else READY


def active_consumer_manifest():return HOST/'consumer-manifest.json' if (HOST/'prepared.json').exists() else WORK/'consumer-manifest.json'


def native_attempt():return HOST/'native-attempt' if (HOST/'prepared.json').exists() else WORK/'native-attempt'


def audit_producer_manifest(path):
    # The original native producer remains immutable in the archive. Only its
    # now-adopted host runner path is resolved to those original bytes.
    value=json.loads(Path(path).read_bytes());payload={k:v for k,v in value.items() if k!='seal_sha256'}
    require(value.get('schema')==1 and value.get('seal_sha256')==sha(canonical(payload)),'Invalid original producer seal')
    runner=str(Path(__file__).resolve());old=ARCHIVE/'tools/test_local_player_session.py'
    for name,item in value['files'].items():
        actual=pin(old if name==runner else name)
        require(actual['sha256']==item['sha256'] and actual['bytes']==item['bytes'],'Changed original producer input '+name)
    return value


def audit_preceding_host_manifest(path):
    value=json.loads(Path(path).read_bytes());payload={k:v for k,v in value.items() if k!='seal_sha256'}
    require(value.get('schema')==1 and value.get('seal_sha256')==sha(canonical(payload)),'Invalid preceding host seal')
    runner=str(Path(__file__).resolve());old=PREVIOUS_ARCHIVE/'tools/test_local_player_session.py'
    for name,item in value['files'].items():
        actual=pin(old if name==runner else name)
        require(actual['sha256']==item['sha256'] and actual['bytes']==item['bytes'],'Changed preceding host input '+name)
    return value


def audit_diagnostic_host_manifest(path):
    value=json.loads(Path(path).read_bytes());payload={k:v for k,v in value.items() if k!='seal_sha256'}
    require(value.get('schema')==1 and value.get('seal_sha256')==sha(canonical(payload)),'Invalid diagnostic host seal')
    runner=str(Path(__file__).resolve());old=DIAGNOSTIC_ARCHIVE/'tools/test_local_player_session.py'
    for name,item in value['files'].items():
        actual=pin(old if name==runner else name)
        require(actual['sha256']==item['sha256'] and actual['bytes']==item['bytes'],'Changed diagnostic host input '+name)
    return value


def adopt_host():
    require(not HOST.exists(),'Existing host adoption; refuse overwrite')
    archive=json.loads((ARCHIVE/'archive.json').read_bytes());payload={k:v for k,v in archive.items() if k!='seal_sha256'}
    require(archive['seal_sha256']==sha(canonical(payload)),'Original archive seal changed')
    for name,item in archive['files'].items():
        original=pin(item['archive_path']);require(original['sha256']==item['sha256'] and original['bytes']==item['bytes'],'Archived original changed '+name)
        if name!='tools/test_local_player_session.py':
            current=pin(ROOT/name);require(current['sha256']==item['sha256'] and current['bytes']==item['bytes'],'Retained original changed '+name)
    original=audit_producer_manifest(READY);consumer=audit_producer_manifest(WORK/'consumer-manifest.json')
    previous_archive=json.loads((PREVIOUS_ARCHIVE/'archive.json').read_bytes());previous_payload={k:v for k,v in previous_archive.items() if k!='seal_sha256'}
    require(previous_archive['seal_sha256']==sha(canonical(previous_payload)),'Preceding host archive seal changed')
    for name,item in previous_archive['files'].items():
        archived=pin(item['archive_path']);require(archived['sha256']==item['sha256'] and archived['bytes']==item['bytes'],'Preceding archived bytes changed '+name)
        if name!='tools/test_local_player_session.py':
            current=pin(ROOT/name);require(current['sha256']==item['sha256'] and current['bytes']==item['bytes'],'Retained preceding host changed '+name)
    previous=audit_preceding_host_manifest(PREVIOUS/'prepared.json');audit_preceding_host_manifest(PREVIOUS/'consumer-manifest.json')
    candidate_archive=WORK/'lineage/diagnostic-candidate-1/archive.json';candidate=json.loads(candidate_archive.read_bytes())
    candidate_payload={k:v for k,v in candidate.items() if k!='seal_sha256'};require(candidate['seal_sha256']==sha(canonical(candidate_payload)),'Unexecuted candidate archive seal changed')
    require(not (WORK/'host-adoption-2/native-attempt').exists(),'Superseded diagnostic candidate was executed')
    for name,item in candidate['files'].items():
        archived=pin(item['archive_path']);require(archived['sha256']==item['sha256'] and archived['bytes']==item['bytes'],'Unexecuted archived candidate changed '+name)
        if name!='tools/test_local_player_session.py':
            current=pin(ROOT/name);require(current['sha256']==item['sha256'] and current['bytes']==item['bytes'],'Retained unexecuted candidate changed '+name)
    require(pin(PREVIOUS/'prepared.json')['sha256']=='5b8b9a070318c4798b0ce80f05886975ae04597229e0720eaefc5ba1c8fd6446','Unexpected preceding host ready')
    require(pin(PREVIOUS/'consumer-manifest.json')['sha256']=='5fc0a60fed19f13b75738a2988bc3f99c34f9031b811086209d6689d781f5037','Unexpected preceding host consumer')
    diagnostic_archive=json.loads((DIAGNOSTIC_ARCHIVE/'archive.json').read_bytes());diagnostic_payload={k:v for k,v in diagnostic_archive.items() if k!='seal_sha256'}
    require(diagnostic_archive['seal_sha256']==sha(canonical(diagnostic_payload)),'Diagnostic host archive seal changed')
    for name,item in diagnostic_archive['files'].items():
        archived=pin(item['archive_path']);require(archived['sha256']==item['sha256'] and archived['bytes']==item['bytes'],'Diagnostic archived bytes changed '+name)
        if name!='tools/test_local_player_session.py':
            current=pin(ROOT/name);require(current['sha256']==item['sha256'] and current['bytes']==item['bytes'],'Retained diagnostic host changed '+name)
    diagnostic=audit_diagnostic_host_manifest(DIAGNOSTIC/'prepared.json');audit_diagnostic_host_manifest(DIAGNOSTIC/'consumer-manifest.json')
    require(pin(DIAGNOSTIC/'prepared.json')['sha256']=='9ddbf6c395a9d6b750f940737e5d62cc614d40caf762d14426bc60e4f51190c9','Unexpected diagnostic host ready')
    require(pin(DIAGNOSTIC/'consumer-manifest.json')['sha256']=='f08ef1e632b794415ff11a2e8a1a289db8908d12c9a04134dece66d5a64256bf','Unexpected diagnostic host consumer')
    receipt=json.loads(RECEIPT.read_bytes());PR.check_receipt(original['sources_sha256'],receipt)
    require(pin(READY)['sha256']=='167474adcfee1f58c1314db992ebe6c4f99213227f855ace2c1ec7c32680f9d4','Unexpected original ready')
    require(pin(RECEIPT)['sha256']=='edb3318feec34078b0c5b7e9dd9c12593e2757de79faa43cfffa21126b857ef6','Unexpected original build receipt')
    require(pin(WORK/'consumer-manifest.json')['sha256']=='a81c85285b4b5b800b6e138b8bfa10de15dabebfe78622012a917729f06dd551','Unexpected original consumer manifest')
    require(pin(SERVER)['sha256']=='1958e777c0d7ddf96ef9f984484f221acb5a3f6f728e03a1643e9eb6b68fd95d','Unexpected retained executable')
    decision=ROOT/'build/review-local-phase-runtime/local-session-atomic-wait-decision.json'
    require(pin(decision)['sha256']=='25fba12b4a7fba6410bb0b71ab91a642d6257565429c24a70f14a968f307b0d0','Independent atomic wait review changed')
    require(environment_pin()==original['environment_sha256'] and sources()==original['sources_sha256'],'Original runtime/source generation changed')
    failure=WORK/'native-attempt/first-failure.json';require(json.loads(failure.read_bytes())['status']=='FAIL','Missing original failure')
    files=dict(diagnostic['files']);runner=str(Path(__file__).resolve());files[runner]={k:v for k,v in pin(runner).items() if k!='path'}
    paths=[ARCHIVE/'archive.json',PREVIOUS_ARCHIVE/'archive.json',READY,WORK/'consumer-manifest.json',RECEIPT,SERVER,decision,
        WORK/'lineage/host-atomic-delta-guards.json',candidate_archive,PREVIOUS/'prepared.json',PREVIOUS/'consumer-manifest.json',
        DIAGNOSTIC_ARCHIVE/'archive.json',DIAGNOSTIC/'prepared.json',DIAGNOSTIC/'consumer-manifest.json']
    paths.extend(Path(item['archive_path']) for item in archive['files'].values())
    paths.extend(ROOT/name for name in archive['files'] if name!='tools/test_local_player_session.py')
    paths.extend(Path(item['archive_path']) for item in previous_archive['files'].values())
    paths.extend(ROOT/name for name in previous_archive['files'] if name!='tools/test_local_player_session.py')
    paths.extend(Path(item['archive_path']) for item in candidate['files'].values())
    paths.extend(ROOT/name for name in candidate['files'] if name!='tools/test_local_player_session.py')
    paths.extend(Path(item['archive_path']) for item in diagnostic_archive['files'].values())
    paths.extend(ROOT/name for name in diagnostic_archive['files'] if name!='tools/test_local_player_session.py')
    for path in paths:files[str(path.resolve())]={k:v for k,v in pin(path).items() if k!='path'}
    lineage={'kind':'retained-native-artifact-host-atomic-reader-adoption','original_prepared':pin(READY),'original_prepared_seal_sha256':original['seal_sha256'],
        'original_producer':pin(ARCHIVE/'tools/test_local_player_session.py'),'original_consumer_manifest':pin(WORK/'consumer-manifest.json'),
        'original_build_receipt':pin(RECEIPT),'retained_binary':pin(SERVER),'original_failure':pin(failure),'archive':pin(ARCHIVE/'archive.json'),
        'preceding_host_prepared':pin(PREVIOUS/'prepared.json'),'preceding_host_archive':pin(PREVIOUS_ARCHIVE/'archive.json'),
        'preceding_host_runner':pin(PREVIOUS_ARCHIVE/'tools/test_local_player_session.py'),'preceding_host_failure':pin(PREVIOUS/'native-attempt/first-failure.json'),
        'superseded_unexecuted_candidate_archive':pin(candidate_archive),
        'diagnostic_host_prepared':pin(DIAGNOSTIC/'prepared.json'),'diagnostic_host_archive':pin(DIAGNOSTIC_ARCHIVE/'archive.json'),
        'diagnostic_host_runner':pin(DIAGNOSTIC_ARCHIVE/'tools/test_local_player_session.py'),'diagnostic_host_failure':pin(DIAGNOSTIC/'native-attempt/first-failure.json'),
        'independent_decision':pin(decision),'fixture_delta':'Atomic wait uses raw-fd complete-line framing with fixed20s deadline and complete consumed-byte capture; durable/stage/restart expectations unchanged',
        'actual_previous_failure_cause':'source/trace buffering inference; no retained written signal',
        'emission_allowed':False,'original_attempt_count':1,'preceding_host_attempt_count':1,'diagnostic_host_attempt_count':1,'adopted_attempt_count':0}
    adopted={k:v for k,v in original.items() if k not in ('seal_sha256','files','status')}
    adopted.update(files=files,status='host-adopted-native-unverified',host_adoption=lineage)
    adopted=sealed(adopted);HOST.mkdir(exist_ok=False);exclusive_json(HOST/'prepared.json',adopted)
    consumer_files=dict(consumer['files']);consumer_files[runner]={k:v for k,v in pin(runner).items() if k!='path'}
    consumer_files.update(files);consumer_files[str((HOST/'prepared.json').resolve())]={k:v for k,v in pin(HOST/'prepared.json').items() if k!='path'}
    adopted_consumer={k:v for k,v in consumer.items() if k not in ('seal_sha256','files','prepared_seal_sha256')}
    adopted_consumer.update(files=consumer_files,prepared_seal_sha256=adopted['seal_sha256'],host_adoption=lineage)
    exclusive_json(HOST/'consumer-manifest.json',sealed(adopted_consumer));activation();verify_build(adopted)
    summary={'status':'host-adoption-audit-PASS','ready':pin(HOST/'prepared.json'),'consumer_manifest':pin(HOST/'consumer-manifest.json'),
        'seal_sha256':adopted['seal_sha256'],'runner':pin(Path(__file__)),'lineage':lineage,'files':len(files),'source_imports':len(adopted['full_Bend_imports']),
        'native_executions':0,'builds':0,'next_command':'PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_player_session.py --skip-build'}
    exclusive_json(HOST/'adoption.json',summary);exclusive_json(ROOT/'evidence/local-player-session-host-adoption-3.json',summary);print(json.dumps(summary),flush=True)


def activation():
    seal=audit_manifest(active_ready());require(environment_pin()==seal['environment_sha256'],'Build/runtime environment generation changed')
    require(sources()==seal['sources_sha256'],'Production consumer/source import closure changed')
    if 'host_adoption' in seal:
        original=audit_producer_manifest(READY);require(original['seal_sha256']==seal['host_adoption']['original_prepared_seal_sha256'],'Original producer lineage changed')
        audit_producer_manifest(WORK/'consumer-manifest.json')
        audit_preceding_host_manifest(PREVIOUS/'prepared.json');audit_preceding_host_manifest(PREVIOUS/'consumer-manifest.json')
        audit_diagnostic_host_manifest(DIAGNOSTIC/'prepared.json');audit_diagnostic_host_manifest(DIAGNOSTIC/'consumer-manifest.json')
    return seal


class UnretriedInputDrift(RuntimeError):pass


def forbid_builder_retry(builder):
    original=builder.InputsChanged
    class RefusedInputsChanged(original):
        def __new__(cls,*args,**kwargs):
            # This separate exception bypasses ensure_native's InputsChanged
            # catch before its retry counter/next _prepare can execute.
            raise UnretriedInputDrift(*args)
    builder.InputsChanged=RefusedInputsChanged
    return original


def build_once(seal,report_path):
    require(not report_path.exists() and not SERVER.exists(),'Existing build output/report; refuse overwrite')
    require(report_path==WORK/'build-attempt/builder.json','Unexpected build report path')
    import build_native as builder
    forbid_builder_retry(builder)
    report=builder.ensure_native(ENTRY,SERVER,bend=BEND)
    require(report['retries']==0,'Builder retry forbidden');activation()
    exclusive_json(report_path,report)
    print(json.dumps({'status':'built','binary_sha256':report['binary_sha256'],'retries':report['retries']}),flush=True)


def build(seal):
    directory=WORK/'build-attempt';directory.mkdir(exist_ok=False)
    raw_report=directory/'builder.json';argv=[sys.executable,Path(__file__),'--_build-once',raw_report];receipt=None
    # Persist terminal process evidence before checking status or report JSON.
    try:
        receipt,out,err=bounded(argv,600,directory,'native-build')
        process_ok(receipt);activation();built=json.loads(raw_report.read_bytes());require(built.get('retries',0)==0,'Native builder retried a changed source generation')
        PR.check_receipt(seal['sources_sha256'],{'sources_sha256':seal['sources_sha256'],'build':built})
        require(pin(SERVER)['sha256']==built['binary_sha256'],'Published native binary differs')
        value={'schema':1,'prepared_seal_sha256':seal['seal_sha256'],'sources_sha256':seal['sources_sha256'],'build':built,'process':receipt,
            'input_ready':pin(READY),'producer':pin(Path(__file__))};exclusive_json(RECEIPT,value)
        consumer_files=dict(seal['files']);consumer_files[str(SERVER.resolve())]={k:v for k,v in pin(SERVER).items() if k!='path'}
        consumer_files[str(RECEIPT.resolve())]={k:v for k,v in pin(RECEIPT).items() if k!='path'}
        consumer_files[str(READY.resolve())]={k:v for k,v in pin(READY).items() if k!='path'}
        for item in built['dependencies']:
            consumer_files[str(Path(item['path']).resolve())]={k:v for k,v in pin(item['path']).items() if k!='path'}
        # Original generated C and immutable native-cache manifest are pinned.
        import build_native as builder
        cache_record=builder._verified(ROOT/'build/native-cache/entries'/built['cache_key'],built['cache_key'])
        require(cache_record is not None,'Original native cache failed content validation')
        emitted=ROOT/'build/native-cache/sources'/cache_record['key_data']['prekey']/'generated.c'
        for path in (emitted,Path(built['artifact']),ROOT/'build/native-cache/entries'/built['cache_key']/'manifest.json'):
            consumer_files[str(path.resolve())]={k:v for k,v in pin(path).items() if k!='path'}
        manifest=sealed({'schema':1,'files':consumer_files,'prepared_seal_sha256':seal['seal_sha256'],'native_build_receipt':pin(RECEIPT),
            'source_generation':seal['sources_sha256'],'emitted_C':pin(emitted),'compiler':built['compiler']})
        exclusive_json(WORK/'consumer-manifest.json',manifest);audit_manifest(WORK/'consumer-manifest.json')
        summary={'status':'built-not-native-compared','prepared_seal_sha256':seal['seal_sha256'],'build_receipt':pin(RECEIPT),'binary':pin(SERVER),
            'consumer_manifest':pin(WORK/'consumer-manifest.json'),'native_dependencies':len(built['dependencies']),'emitted_C':pin(emitted),'retries':built['retries']}
        exclusive_json(ROOT/'evidence/local-player-session-build.json',summary);print(json.dumps(summary),flush=True)
    except BaseException as cause:
        exclusive_json(directory/'first-failure.json',{'status':'FAIL','process':receipt,'error':type(cause).__name__+': '+str(cause),
            'prepared_seal_sha256':seal['seal_sha256'],'report':pin(raw_report) if raw_report.exists() else None});raise


def verify_build(seal):
    audit_manifest(active_consumer_manifest());receipt=json.loads(RECEIPT.read_bytes())
    producer_seal=seal.get('host_adoption',{}).get('original_prepared_seal_sha256',seal['seal_sha256'])
    require(receipt['prepared_seal_sha256']==producer_seal and receipt['sources_sha256']==seal['sources_sha256'],'Native artifact generation changed')
    PR.check_receipt(seal['sources_sha256'],receipt);require(pin(SERVER)['sha256']==receipt['build']['binary_sha256'],'Native artifact changed')
    return receipt


def cleanup_registered(path):
    rows=[json.loads(line) for line in path.read_bytes().splitlines()] if path.exists() else []
    result=[]
    for row in rows:
        pid=row['pid'];before=group_absent(pid)
        if not before:
            try:os.killpg(pid,signal.SIGKILL)
            except ProcessLookupError:pass
        result.append(dict(row,absent_before_parent_cleanup=before,absent_after_parent_cleanup=group_absent(pid)))
    return result


def stage_comparison(output):
    lines=output.splitlines();require(lines[-1:] == ['local-session-stage-guards|complete|true'],'Missing stage completion marker')
    result=[]
    for name in ('stage-header','stage-body','stage-clock'):
        before=[line.replace(name+'-before',name+'-same',1) for line in lines if line.startswith(name+'-before|') or line.startswith(name+'-before:')]
        after=[line.replace(name+'-after',name+'-same',1) for line in lines if line.startswith(name+'-after|') or line.startswith(name+'-after:')]
        errors=[line for line in lines if line.startswith(name+'|guard-error|')]
        require(before and before==after,'Forged stage callback changed complete owned projection '+name)
        require(errors==[name+'|guard-error|apply-provider-authority-drift'],'Forged stage admission did not reject before provider '+name)
        result.append({'case':name,'before_after_projection_sha256':sha(canonical(before)),'projection_lines':len(before),'callback_not_invoked':True})
    return {'status':'PASS','cases':result,'stdout_sha256':sha(output.encode())}


def native(seal):
    receipt=verify_build(seal);directory=native_attempt();directory.mkdir(exist_ok=False);results=[];lanes=[];codec=None
    try:
        for index in range(2):
            verify_build(seal)
            process,out,err=bounded([sys.executable,Path(__file__),'--_integration-run',str(index)],120,directory,'integration-'+str(index))
            groups=cleanup_registered(directory/('integration-'+str(index))/'owned-groups.jsonl')
            comparison={'process':process,'owned_groups':groups,'summary':None}
            summary_path=directory/('integration-'+str(index))/'summary.json'
            if summary_path.exists():comparison['summary']=json.loads(summary_path.read_bytes())
            exclusive_json(directory/('integration-'+str(index)+'.comparison.json'),comparison)
            process_ok(process);require(all(r['absent_after_parent_cleanup'] and r['absent_before_parent_cleanup'] for r in groups),'Integration left an owned process group')
            require(not err and comparison['summary'] and comparison['summary']['status']=='PASS','Actual integrated suite failed')
            results.append(comparison);verify_build(seal)
            if index==0:
                from test_local_player_record_consumer import verify_existing_binary
                codec=verify_existing_binary(SERVER,['record-cases'],receipt['build']['binary_sha256'],active_consumer_manifest(),directory/'record-cases')
                exclusive_json(directory/'record-result.json',codec)
                import test_local_phase_runtime as phase
                for lane,compare in (('phase-cases',phase.compare_output),('facade-cases',stage_comparison)):
                    previous=None
                    for run in range(2):
                        verify_build(seal);process,out,err=bounded([SERVER,'--gpu','off','--threads','1',lane,TABLE],120,directory,lane+'-'+str(run))
                        # Complete process outputs/receipt exist before any parser,
                        # comparator or return-code assertion is evaluated.
                        process_ok(process);require(not err,'Native fixture lane emitted stderr '+lane)
                        compared=compare(out.decode());same=previous is None or previous==out
                        exclusive_json(directory/(lane+'-'+str(run)+'.comparison.json'),{'process':process,'comparison':compared,'exact_rerun_equal':same})
                        require(same,'Fresh same-artifact fixture rerun differs '+lane);previous=out
                        lanes.append({'lane':lane,'run':run,'process':process,'comparison':compared});verify_build(seal)
        summary={'status':'PASS','prepared_seal_sha256':seal['seal_sha256'],'binary':pin(SERVER),'build_receipt':pin(RECEIPT),
            'codec_executions':codec['completed_executions'],'codec_receipt':pin(directory/'record-cases/summary.json'),'shared_fixture_lanes':lanes,
            'integration_runs':[{'summary':pin(directory/('integration-'+str(i))/'summary.json'),'process':r['process'],
                'checks':len(r['summary']['checks']),'saves':len(r['summary']['saves']),'startup_rejections':len(r['summary']['rejections'])} for i,r in enumerate(results)],
            'scope':'Actual declared neutral consumer, custom complete local record/Core bundle, synthetic test inputs, actual TCP/MCP; no foreground/native presentation or general LocalPlayer/vanilla save acceptance'}
        exclusive_json(ROOT/'evidence/local-player-session-native.json',summary);print(json.dumps(summary),flush=True)
    except BaseException as cause:
        exclusive_json(directory/'first-failure.json',{'status':'FAIL','completed_runs':len(results),'completed_fixture_lanes':len(lanes),
            'error':type(cause).__name__+': '+str(cause),'prepared_seal_sha256':seal['seal_sha256'],'binary':pin(SERVER)});raise


def main():
    parser=argparse.ArgumentParser(description=__doc__);mode=parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--oracle-check',action='store_true');mode.add_argument('--prepare',action='store_true');mode.add_argument('--audit',action='store_true')
    mode.add_argument('--adopt-host',action='store_true');mode.add_argument('--build-only',action='store_true');mode.add_argument('--skip-build',action='store_true');mode.add_argument('--_integration-run',type=int);mode.add_argument('--_build-once',type=Path)
    args=parser.parse_args()
    if args.oracle_check:
        cases,reference,_=reference_cases();print(json.dumps({'status':'independent-oracle-check-passed','actual_cases':len(cases),'actual_steps':8,'reference':pin(REFERENCE),'heavy_execution':False}));return
    if args.prepare:prepare();return
    if args.adopt_host:adopt_host();return
    seal=activation()
    if args.audit:print(json.dumps({'status':'read-only-audit-PASS','ready':pin(active_ready()),'files':len(seal['files']),'source_imports':len(seal['full_Bend_imports'])}));return
    require('host_adoption' not in seal or not (args.build_only or args._build_once is not None),'Host adoption forbids further emission/build')
    if args._build_once is not None:build_once(seal,args._build_once);return
    if args.build_only:build(seal);return
    if args.skip_build:native(seal);return
    if args._integration_run is not None:
        verify_build(seal);bridge,_=retained_bridge();directory=native_attempt()/('integration-'+str(args._integration_run))
        global OWNED_GROUPS
        # Reserve the directory and ownership ledger before the first native child.
        directory.mkdir(parents=True,exist_ok=False);OWNED_GROUPS=directory/'owned-groups.jsonl';OWNED_GROUPS.touch(exist_ok=False)
        integration_run(seal,bridge,directory)

if __name__=='__main__':main()
