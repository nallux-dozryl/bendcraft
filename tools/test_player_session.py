#!/usr/bin/env python3
"""Independent custom PlayerSession leased bundle and actual TCP/MCP tests.

Python specifies NBT/protocol fixtures and orchestrates official Java/native
processes. Player ticks, owner transfer, live mutation and persistence run in Bend.
"""
from __future__ import annotations
import argparse
import collections
import copy
import hashlib
import json
import os
from pathlib import Path
import select
import socket
import struct
import subprocess
import sys
import time

import test_nbt as N
import test_world_codec as W
import test_player_codec as PC
import test_player_record as PR
import test_persistence as P
import test_mcp as MCP
import test_support_world as SW
import test_travel_world as TW
from reference_inventory import JAVA, canonical, fingerprint
from reference_block_probe import verified_classpath
from reference_movement_probe import SOURCE as MOVE_SOURCE, DIRECT_SOURCE
from reference_travel_probe import SOURCE as TRAVEL_SOURCE, bits, fbits
from reference_player_tick_probe import SOURCE as TICK_SOURCE
from reference_support_probe import SOURCE as SUPPORT_SOURCE

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'build/player-session'
ENTRY = ROOT / 'tests/player_session.bend'
SERVER = WORK / 'server'
BRIDGE = WORK / 'mcp'
TABLE = ROOT / 'generated/reference_mth_sin.f32'
BEND = Path('/Users/chuah/.bend/bin/bend')
RECEIPT = WORK / 'build.json'
NAMESPACE = 'bendex:player-record'
BUNDLE_FIELDS = ('format','minecraft','registry','peer_highwater','core','extension')
EXTENSION_FIELDS = ('namespace','schema','payload')
TINY_TSV = P.HEADER + '\n' + ''.join(f'{i}\t{name}\t{i}\t1\t{i}\t[]\n' for i,name in enumerate(('minecraft:air','minecraft:stone','minecraft:dirt','minecraft:oak_planks')))


def sha(data): return hashlib.sha256(data).hexdigest()
def require(test,message):
    if not test: raise AssertionError(message)
def write_json(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')


def record_bytes(words, look=(0,0,0,0), dimension='minecraft:overworld'):
    motion = N.encode_root(PC.snapshot_root(words,dimension))
    data = N.encode_root(PR.root(motion,look))
    require(PR.decode(data)==(motion,PR.look_bytes(look)),'independent player record did not validate')
    return data


def initial_record():
    words = PC.snapshot(position=tuple(PC.raw64(v) for v in (.5,1.,-2.5)),speed=0)
    return record_bytes(words)


def bundle_root(model,highwater,player):
    return N.RootTag(N.text('bendex:bundle'),W.compound([
        ('format',W.integer(1)),('minecraft',W.txt('26.3')),('registry',W.txt(model['registry'])),
        ('peer_highwater',W.integer(highwater)),('core',N.Value(7,P.canonical_expected(model))),
        ('extension',W.compound([('namespace',W.txt(NAMESPACE)),('schema',W.integer(1)),('payload',N.Value(7,player))]))]))


def bundle_bytes(model,highwater,player): return N.encode_root(bundle_root(model,highwater,player))


def parse_bundle(data,count,identity):
    # The extension-aware reader applies field-specific ByteArray limits.
    root = N.Reader(data,max_bytes=16846848,max_depth=6,max_elements=16846848).root()
    if root.name != N.text('bendex:bundle'): raise ValueError('wrong named bundle root')
    fs = W.fields(root.value,BUNDLE_FIELDS)
    if W.uint(fs['format'])!=1 or W.scalar_text(fs['minecraft'])!='26.3' or W.scalar_text(fs['registry'])!=identity:
        raise ValueError('wrong bundle format/version/registry')
    highwater = W.uint(fs['peer_highwater'])
    if fs['core'].kind!=7 or len(fs['core'].payload)>N.DEFAULT_BYTES: raise ValueError('Core ByteArray limit/type')
    model = W.validate(N.parse(fs['core'].payload),count,identity)
    ext=W.fields(fs['extension'],EXTENSION_FIELDS)
    if W.scalar_text(ext['namespace'])!=NAMESPACE or W.uint(ext['schema'])!=1 or ext['payload'].kind!=7 or len(ext['payload'].payload)>8192:
        raise ValueError('extension namespace/schema/payload limit/type')
    motion,rawlook=PR.decode(ext['payload'].payload)
    words,dimension=PC.parse_snapshot(motion)
    if dimension!='minecraft:overworld': raise ValueError('known dimension is outside current player runtime')
    highwater=max(highwater,model['max_peer'] or 0)
    if highwater==0xffffffff: raise ValueError('peer range exhausted')
    canonical_player=N.encode_root(PR.root(motion,PR.look_words(rawlook)))
    return model,canonical_player,highwater+1


def section_key(x,y,z):
    return 'minecraft:overworld/'+'/'.join(str((v//16)&0xffffffff) for v in (x,y,z))


def scene_world(count,identity):
    model=W.empty_world(count,identity)
    coords=[(-16,-16,-16),(0,-16,-16),(-16,0,-16),(0,0,-16),(-16,-16,0),(0,-16,0),(-16,0,0),(0,0,0)]
    model['sections']=[W.section(section_key(*p)) for p in coords]
    blocks=TW.world_blocks()
    names={'minecraft:air':0,'minecraft:stone':1,'minecraft:dirt':2,'minecraft:oak_planks':3}
    for b in blocks: set_block(model,*b['position'],names[b['identifier']])
    model.update(tick=1,day_time=1,revision=47)
    model['events']=[{'stamp':(1,0,i),'kind':0,'revision':i+1} for i in reversed(range(47))]
    model['sections'].sort(key=lambda s:s['key'])
    P.canonical_expected(model)
    return model


def set_block(model,x,y,z,state):
    target=section_key(x,y,z)
    section=next(s for s in model['sections'] if s['key']==target)
    cells=list(section['cells']);cells[(x&15)+((z&15)<<4)+((y&15)<<8)]=state
    section['cells']=tuple(cells)


def apply_tick(model):
    model['tick']+=1
    model['day_time']+=int(model['daylight'])
    due=[p for p in model['pending'] if p['stamp'][0]<=model['tick']]
    model['pending']=[p for p in model['pending'] if p['stamp'][0]>model['tick']]
    for pending in due:
        mutation=pending['mutation']
        if mutation['kind']==1: set_block(model,*(v if v<0x80000000 else v-0x100000000 for v in (mutation['x'],mutation['y'],mutation['z'])),mutation['state'])
        elif mutation['kind']==2: model['day_time']=mutation['day_time']
        elif mutation['kind']==3: model['daylight']=mutation['enabled']
        else: raise AssertionError('fixture mutation outside independent tick oracle')
        model['revision']+=1
        model['events'].insert(0,{'stamp':pending['stamp'],'kind':0,'revision':model['revision']})


def java_input(identity,words=None,cache=None,blocks=None,ticks=3,held=True):
    words=PC.snapshot(position=tuple(PC.raw64(v) for v in (.5,1.,-2.5)),speed=0) if words is None else words
    return {'id':identity,'operation':'player_ai_step','input':{
        'position':[f'{v:016x}' for v in PC.bits64(words[:6])], 'velocity':[f'{v:016x}' for v in PC.bits64(words[18:24])],
        'grounded':bool(words[26]),'flags':[bool(v) for v in words[26:30]],'input_f32_bits':[f'{v:08x}' for v in words[30:33]],
        'jumping':bool(words[33]),'jump_delay':words[34] if words[34]<0x80000000 else words[34]-0x100000000,
        'jump_trigger':words[35] if words[35]<0x80000000 else words[35]-0x100000000,'needs_sync':bool(words[36]),
        'stored_speed_f32_bits':f'{words[37]:08x}','head_yaw_f32_bits':f'{words[38]:08x}','sprinting':False,
        'no_gravity':False,'discard_friction':False,'yaw_f32_bits':fbits(0.),'movement_speed':bits(.1),'gravity':bits(.08),
        'friction_modifier':bits(1.),'air_drag_modifier':bits(1.),'step_height':bits(.6),'jump_strength':bits(.42),
        'world_blocks':TW.world_blocks() if blocks is None else blocks,'initial_cache':{'main':None,'on_ground_no_blocks':False} if cache is None else cache,
        'ticks':[{'input_f32_bits':[fbits(0.),fbits(0.),fbits(1. if held else 0.)],'jumping':False} for _ in range(ticks)]}}


def java_record(tick):
    expected=tick['expected'];cache=tick['observation']['support_cache']
    fields=[*PC.words64(tuple(int(v,16) for v in expected['position'])),*PC.words64(tuple(int(v,16) for v in expected['box'])),
            *PC.words64(tuple(int(v,16) for v in expected['velocity'])),int(expected['width_f32_bits'],16),int(expected['height_f32_bits'],16),
            *map(int,expected['flags']),*(int(v,16) for v in expected['input_f32_bits']),int(expected['jumping']),
            expected['jump_delay']&0xffffffff,expected['jump_trigger']&0xffffffff,int(expected['needs_sync']),
            int(expected['stored_speed_f32_bits'],16),int(expected['head_yaw_f32_bits'],16),0,0,
            int(cache['main'] is not None),*((v&0xffffffff for v in cache['main']) if cache['main'] is not None else (0,0,0)),int(cache['on_ground_no_blocks'])]
    require(len(fields)==46,'production aiStep word projection count')
    return record_bytes(tuple(fields))


def java_source():
    source=SW.java_source().replace('ReferenceSupportWorldProbe','ReferencePlayerSessionProbe')
    source=source.replace('inputs(p,update.getAsJsonObject());', 'JsonObject updateObject=update.getAsJsonObject();if(updateObject.has("writes"))ReferenceSupportProbe.writes(level,updateObject.getAsJsonArray("writes"));inputs(p,updateObject);')
    marker='p.setOnGround(in.get("grounded").getAsBoolean());'
    source=source.replace(marker,marker+'if(in.has("flags")){JsonArray flags=in.getAsJsonArray("flags");p.horizontalCollision=flags.get(1).getAsBoolean();p.verticalCollision=flags.get(2).getAsBoolean();p.verticalCollisionBelow=flags.get(3).getAsBoolean();}')
    require(source.count('ReferenceSupportProbe.writes(level,updateObject')==1,'actual Java per-tick writes instrumentation missing')
    return source


def observe_java(cases):
    jars,release=verified_classpath(); directory=WORK/'java';directory.mkdir(parents=True,exist_ok=True)
    names=[('ReferenceMovementProbe',MOVE_SOURCE),('ReferenceDirectMovementProbe',DIRECT_SOURCE),('ReferenceTravelProbe',TRAVEL_SOURCE),
           ('ReferencePlayerTickProbe',TICK_SOURCE),('ReferenceSupportProbe',SUPPORT_SOURCE),('ReferencePlayerSessionProbe',java_source())]
    paths=[]
    for name,source in names:
        path=directory/(name+'.java');path.write_text(source);paths.append(path)
    cp=os.pathsep.join(map(str,jars))
    compilation=PR.bounded_run([JAVA.parent/'javac','-cp',cp,'-d',directory,*paths],timeout=60)
    require(compilation['exit_code']==0,'official Java fixture compilation failed: '+compilation['stderr'][-1000:])
    input_path=directory/'input.jsonl';input_path.write_text(''.join(canonical(c).decode()+'\n' for c in cases))
    outputs=[];runs=[]
    for i in range(2):
        path=directory/f'output-{i}.jsonl'
        result=PR.bounded_run([JAVA,'-cp',str(directory)+os.pathsep+cp,'ReferencePlayerSessionProbe',input_path,path],timeout=60)
        require(result['exit_code']==0,'official Java tick observation failed: '+result['stderr'][-1000:])
        outputs.append([json.loads(line) for line in path.read_text().splitlines()]);runs.append(result)
    require(outputs[0]==outputs[1],'two fresh Java observations differ')
    require([o['id'] for o in outputs[0]]==[c['id'] for c in cases],'Java observation receiver order changed')
    for output in outputs[0]:
        require(all(t['observation']['full_player_ai_step_executed'] for t in output['ticks']),'production aiStep did not execute')
    provenance={'pin':'26.3','release':release,'classpath':[fingerprint(p) for p in jars], 'runtime':fingerprint(JAVA),
                'sources_sha256':{name:sha(source.encode()) for name,source in names},'compilation':compilation,
                'runs':runs,'input_sha256':sha(input_path.read_bytes()),'output_sha256':sha(canonical(outputs[0]))}
    return outputs[0],provenance


def reference_fixtures():
    first,provenance=observe_java([java_input('held-three',ticks=3)])
    initial=first[0];records=[java_record(t) for t in initial['ticks']]
    words,_=PC.parse_snapshot(PR.decode(records[1])[0])
    restart=java_input('restart-released-two',words=words,cache=initial['ticks'][1]['observation']['support_cache'],ticks=2,held=False)
    positions=[[0,0,z] for z in (-3,-2,-1)]
    restart['input']['ticks'][0]['writes']=[{'position':p,'identifier':'minecraft:air'} for p in positions]
    restart['input']['ticks'][1]['writes']=[{'position':p,'identifier':'minecraft:stone'} for p in positions]
    unsaved=copy.deepcopy(restart);unsaved['id']='unsaved-held-removal';unsaved['input']['ticks']=unsaved['input']['ticks'][:1];unsaved['input']['ticks'][0]['input_f32_bits']=[fbits(0.),fbits(0.),fbits(1.)]
    resumed,resume_provenance=observe_java([restart,unsaved])
    data={'first':initial,'first_record_sha256':[sha(v) for v in records],'restart':resumed[0],
          'restart_record_sha256':[sha(java_record(t)) for t in resumed[0]['ticks']],
          'unsaved':resumed[1], 'unsaved_record_sha256':sha(java_record(resumed[1]['ticks'][0])),
          'provenance':[provenance,resume_provenance], 'scope':'Untouched actual Java Player.aiStep/movement/support under declared neutral fixture services; controlled per-tick world writes precede actual aiStep; custom bundle format is independently specified, not Java serialization.'}
    write_json(WORK/'reference.json',data)
    return data


def corruption_fixtures(model):
    baseline=bundle_root(model,17,initial_record());cases=[]
    def add(name,root):
        data=N.encode_root(root) if isinstance(root,N.RootTag) else root
        try: parse_bundle(data,model['state_count'],model['registry'])
        except (ValueError,UnicodeError,struct.error): pass
        else: raise AssertionError('independent oracle admitted malformed startup '+name)
        cases.append((name,data))
    def outer(name,value):return N.RootTag(baseline.name,W.replace_field(baseline.value,name,value))
    ext=dict(baseline.value.payload)[N.text('extension')]
    def extension(name,value):return outer('extension',W.replace_field(ext,name,value))
    add('core-only-refused',P.envelope(P.canonical_expected(model),model['registry'],17))
    for name,value in [('format',W.integer(2)),('minecraft',W.txt('26.4')),('registry',W.txt('f'*64)),('peer_highwater',W.integer(0xffffffff)),('core',N.Value(7,b''))]:add('outer-'+name,outer(name,value))
    for field in BUNDLE_FIELDS:
        target=N.text(field);members=baseline.value.payload
        add('outer-missing-'+field,N.RootTag(baseline.name,N.Value(10,tuple(m for m in members if m[0]!=target))))
        add('outer-duplicate-'+field,N.RootTag(baseline.name,N.Value(10,members+tuple(m for m in members if m[0]==target))))
        add('outer-type-'+field,outer(field,W.byte(0)))
    for namespace in ('','other:player','Bendex:player-record'):add('namespace-'+repr(namespace),extension('namespace',W.txt(namespace)))
    for schema in (0,2,0xffffffff):add('extension-schema-'+str(schema),extension('schema',W.integer(schema)))
    for dimension in PC.DIMENSIONS[1:]:
        player=record_bytes(PC.snapshot(position=tuple(PC.raw64(v) for v in (.5,1.,-2.5)),speed=0),dimension=dimension)
        add('known-unsupported-dimension-'+dimension,extension('payload',N.Value(7,player)))
    corpus,_,_,_=PR.corpus();selected=[];categories=set()
    for c in corpus:
        if c.mode=='decode' and c.error and (c.category not in categories or c.category in ('raw-projection-mismatch','look-nonfinite') and len(selected)<60):
            selected.append(c);categories.add(c.category)
    for c in selected:add('record-'+c.name,extension('payload',N.Value(7,c.data)))
    for size in (8192,8193):add('extension-byte-limit-'+str(size),extension('payload',N.Value(7,b'\0'*size)))
    raw=N.encode_root(baseline)
    for cut in (0,1,2,8,len(raw)//2,len(raw)-2,len(raw)-1):add('bundle-truncation-'+str(cut),raw[:cut])
    add('bundle-trailing',raw+b'\0')
    return cases


def environment(path,port,registry,missing=None):
    return P.clean_env(path,port,registry,missing)


class RawTCP:
    def __init__(self,port):
        self.socket=socket.create_connection(('127.0.0.1',port),timeout=5);self.reader=self.socket.makefile('rb');self.count=0
    def raw(self,data):
        self.socket.sendall(data);line=self.reader.readline(2*1024*1024)
        require(line.endswith(b'\n'),'raw TCP response missing frame')
        require(MCP.TOKEN.encode() not in line,'raw TCP disclosed authentication token')
        self.count+=1;return json.loads(line)
    def call(self,op,args=None,fault=None,**extra):
        request={'id':'raw-'+str(self.count),'op':op,'args':{} if args is None else args};request.update(extra)
        answer=self.raw(MCP.encode(request))
        require(answer['id']==request['id'],'raw request id mismatch')
        if fault is not None:require(answer.get('ok') is False and answer['error']['code']==fault,'raw fault mismatch '+str(answer));return answer
        require(answer.get('ok') is True,'raw request failed '+str(answer));return answer['result']
    def close(self):self.reader.close();self.socket.close()


class Runtime:
    observed=[]
    def __init__(self,path,registry,mode='normal',missing=None):
        self.path,self.port=path,MCP.free_port();self.clients=[];self.raw_clients=[]
        self.process=subprocess.Popen([str(SERVER),'--gpu','off','--threads','2','--',str(TABLE),mode],cwd=ROOT,
                                      env=environment(path,self.port,registry,missing),stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        try:
            require(select.select([self.process.stdout],[],[],15)[0],'PlayerSession readiness timeout')
            line=self.process.stdout.readline()
            if not line:raise AssertionError('PlayerSession refused startup: '+self.process.stderr.read().decode()[-1000:])
            self.ready=json.loads(line);require(self.ready['port']==self.port,'PlayerSession readiness port differs')
        except Exception:
            if self.process.poll() is None:self.process.kill()
            self.process.communicate(timeout=5);raise
        Runtime.observed.append(self)
    def mcp(self,developer=True):
        client=MCP.MCP(BRIDGE,self.port,MCP.TOKEN if developer else None);self.clients.append(client);client.initialize();ping=client.call('ping')
        require(ping['mode']==('developer' if developer else 'observer'),'MCP capability differs')
        require(ping['sequence']==(3 if developer else 2),'MCP startup sequence differs')
        return client,ping
    def tcp(self):
        client=RawTCP(self.port);self.raw_clients.append(client);return client
    def stop(self,kill=False):
        for c in self.clients:c.cleanup()
        for c in self.raw_clients:c.close()
        if self.process.poll() is None:self.process.kill() if kill else self.process.terminate()
        stdout,stderr=self.process.communicate(timeout=5)
        require(not stdout and not stderr,'unexpected PlayerSession lifetime output '+repr((stdout,stderr)))
        if kill:require(self.process.returncode==-9,'actual SIGKILL was not observed')


def inspect(client,expected):
    value=client.call('player.inspect',{})
    require(value=={'format':NAMESPACE,'nbt_bytes':list(expected)},'actual API player bytes differ from independent expectation')
    return value


def save(client,path,model,highwater,player,records,label):
    value=client.call('world.save',{})
    data=path.read_bytes();expected=bundle_bytes(model,highwater,player)
    require(data==expected,'actual saved bundle differs from independent Core+Record bytes '+label)
    require(value=={'status':'durable','published':True,'durable':True,'bytes':len(data),'peer_highwater':highwater},'save publication/durability response differs')
    actual,record,next_peer=parse_bundle(data,model['state_count'],model['registry'])
    require(record==player and P.canonical_expected(actual)==P.canonical_expected(model) and next_peer==highwater+1,'independent saved bundle readback differs')
    records.append({'scenario':label,'bytes':len(data),'bundle_sha256':sha(data),'core_sha256':sha(P.canonical_expected(model)),
                    'record_sha256':sha(player),'highwater':highwater,'clock':P.clock(model),'response':value})
    return data


def reject_startup(name,path,registry,records,missing=None,mode='normal'):
    port=MCP.free_port();started=time.monotonic()
    p=subprocess.Popen([str(SERVER),'--gpu','off','--threads','1','--',str(TABLE),mode],cwd=ROOT,env=environment(path,port,registry,missing),stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    try:stdout,stderr=p.communicate(timeout=15)
    except subprocess.TimeoutExpired:p.kill();p.communicate(timeout=5);raise AssertionError('startup failure did not terminate '+name)
    require(p.returncode!=0 and not stdout and stderr,'startup failure emitted readiness or no diagnostic '+name)
    require(MCP.TOKEN.encode() not in stderr,'startup diagnostic disclosed token')
    with socket.socket() as probe:probe.settimeout(1);require(probe.connect_ex(('127.0.0.1',port))!=0,'startup failure left listener '+name)
    records.append({'case':name,'exit_code':p.returncode,'no_listener':True,'seconds':round(time.monotonic()-started,6),
                    'diagnostic':stderr.decode().strip()[:350],'input_sha256':sha(path.read_bytes()) if path.is_file() else None})


def live_tests(registry,count,identity,reference,saves,rejections,checks,metrics):
    path=WORK/'live.nbt';path.unlink(missing_ok=True);model=scene_world(count,identity);player=initial_record()
    runtime=None
    try:
        runtime=Runtime(path,registry,'scene','create');actor,actor_ping=runtime.mcp();observer,observer_ping=runtime.mcp(False)
        raw=runtime.tcp();raw_ping=raw.call('ping');require(raw_ping['sequence']==1,'fresh raw TCP sequence')
        highwater=raw_ping['peer']
        names=[t['name'] for t in actor.request('tools/list')['result']['tools']]
        require(len(names)==len(set(names)) and {'player.inspect','simulation.step','world.save'}<=set(names) and 'fixture.transient' not in names,'actual production MCP discovery differs')
        inspect(observer,player);require(actor.call('world.clock')==P.clock(model),'fixture Core47 state differs')
        transient=raw.call('fixture.transient')
        require(transient['buttons']==1 and transient['mouse_position']==[[1076101120,0],[1077149696,0]] and transient['mouse_accumulated']==[[1074266112,0],[3222274048,0]] and transient['ignore_first_move'] is False,'fresh explicit physical-state fixture differs')
        for op,args in [('simulation.step',{'ticks':1}),('world.save',{})]:observer.call(op,args,fault='PermissionDenied')
        observer.call('session.open',{'mode':'player'},fault='PlayerUnavailable')
        observer.call('player.inspect',{'unknown':True},fault='InvalidArguments')
        observer.call('player.inspect',{},at=2,fault='InvalidArguments')
        require(raw.call('fixture.transient')==transient,'delegated inspect/discovery/auth failure lost transient owners')
        # Strict schema failures and rejected requests leave both Core and Record unchanged.
        for args in ({},{'ticks':0},{'ticks':1001},{'ticks':-1},{'ticks':1.5},{'ticks':1.0},{'ticks':True},{'ticks':'1'},{'ticks':None},{'ticks':1,'extra':0}):
            before=raw.call('ping')['sequence'];raw.call('simulation.step',args,fault='InvalidArguments');after=raw.call('ping')['sequence']
            require(after==before+2,'valid-envelope failure increments sequence more or less than once')
            inspect(raw,player);require(actor.call('world.clock')==P.clock(model),'malformed step mutated Core or player')
        for at in (0,2,None):raw.call('simulation.step',{'ticks':1},at=at,fault='InvalidArguments' if at is not None else 'InvalidRequest')
        raw.call('simulation.step',{'ticks':1},fault='PermissionDenied')
        # Actual malformed envelope/JSON is not an intercepted step envelope.
        for request in ({'op':'simulation.step','args':{'ticks':1}}, {'id':'bad','op':2,'args':{}}, {'id':'bad','op':'simulation.step','args':[]}):
            before=raw.call('ping')['sequence'];reply=raw.raw(MCP.encode(request));require(reply['ok'] is False,'malformed envelope admitted')
            after=raw.call('ping')['sequence'];require(after==before+2,'invalid envelope did not consume exactly one dispatched operation sequence')
        before=raw.call('ping')['sequence'];reply=raw.raw(b'{"id":"exponent","op":"simulation.step","args":{"ticks":1e0}}\n')
        require(reply['ok'] is False and reply['error']['code']=='InvalidArguments','non-integer unsigned lexeme admitted')
        require(raw.call('ping')['sequence']==before+2,'valid exponent envelope did not consume one rejected operation sequence')
        before=raw.call('ping')['sequence'];reply=raw.raw(b'{"id":"duplicate","op":"simulation.step","args":{"ticks":1},"args":{"ticks":2}}\n')
        require(reply['ok'] is False and reply['error']['code']=='invalid_json','duplicate physical JSON object member admitted')
        require(raw.call('ping')['sequence']==before+1,'duplicate physical JSON member consumed operation sequence')
        before=raw.call('ping')['sequence'];reply=raw.raw(b'{broken\n');require(reply['ok'] is False and reply['error']['code']=='invalid_json','malformed physical JSON admitted')
        require(raw.call('ping')['sequence']==before+1,'transport JSON failure changed sequence')
        raw.call('session.open',{'mode':'developer','token':'wrong'},fault='AuthenticationFailed')
        raw.call('session.open',{'mode':'developer','token':MCP.TOKEN})
        require(raw.call('fixture.transient')==transient,'step/auth rejection changed controls')
        # Two actual player ticks, each after its corresponding Core advance.
        before=raw.call('ping')['sequence'];require(raw.call('simulation.step',{'ticks':2})['tick']==3,'two-tick actual runtime dispatch')
        require(raw.call('ping')['sequence']==before+2,'successful multi-tick step did not consume exactly one sequence')
        for _ in range(2):apply_tick(model)
        player=java_record(reference['first']['ticks'][1]);inspect(actor,player)
        require(raw.call('fixture.transient')==transient,'runtime advance lost held input/mouse owners')
        # Queue removal/restoration at different ticks; applying the entire batch
        # before physics would observe a different collider world on the first tick.
        for target,state in ((4,0),(5,1)):
            for z in (-3,-2,-1):
                pos={'dimension':'minecraft:overworld','x':0,'y':0,'z':z}
                stamp=P.stamp(raw.call('world.block.set',pos|{'state':state},at=target))
                model['pending'].append({'stamp':stamp,'mutation':{'kind':1,'dimension':pos['dimension'],'x':0,'y':0,'z':z&0xffffffff,'state':state}})
        model['pending'].sort(key=lambda p:p['stamp'])
        old=save(actor,path,model,highwater,player,saves,'paused-rich-Core-and-two-tick-player')
        lock=Path(str(path)+'.lock');inode=lock.stat().st_ino
        reject_startup('concurrent-lease',path,registry,rejections)
        require(path.read_bytes()==old,'concurrent lease contender changed save')
        raw.call('simulation.step',{'ticks':1});inspect(raw,java_record(reference['unsaved']['ticks'][0]))
        require(path.read_bytes()==old,'unsaved runtime mutation changed durable bundle')
        runtime.stop(kill=True);runtime=None
        runtime=Runtime(path,registry,'scene');restored,restored_ping=runtime.mcp();restored_raw=runtime.tcp();restored_raw_ping=restored_raw.call('ping')
        require(restored_ping['peer']==highwater+1 and lock.stat().st_ino==inode,'restart peer or lock-file identity differs')
        highwater=restored_raw_ping['peer']
        inspect(restored,player);require(restored.call('world.clock')==P.clock(model),'restart did not restore exact Core clock and pending queue')
        reset=restored_raw.call('fixture.transient');require(reset=={'buttons':0,'mouse_position':[[0,0],[0,0]],'mouse_accumulated':[[0,0],[0,0]],'ignore_first_move':True,'last_error':None},'startup did not clear all ephemeral physical fields')
        require(restored.call('simulation.step',{'ticks':2})['tick']==5,'restored queued Core/player advance differs')
        for _ in range(2):apply_tick(model)
        player=java_record(reference['restart']['ticks'][1]);inspect(restored,player)
        require(restored.call('world.clock')==P.clock(model),'per-tick queued edit application differs')
        old=save(restored,path,model,highwater,player,saves,'restart-controls-cleared-and-interleaved-Core-edits')
        require(restored_raw.call('fixture.transient')==reset,'delegate save reset altered already-reset controls')
        latest=restored.call('ping');collision=Path(str(path)+f'.pending-save-{latest["peer"]}-{latest["sequence"]+2}')
        collision.write_bytes(b'unowned-player-session-collision')
        restored.call('world.save',{},fault='SaveNotPublished')
        require(path.read_bytes()==old and collision.read_bytes()==b'unowned-player-session-collision','failed exclusive publication modified old/unowned file')
        inspect(restored,player);require(restored.call('world.clock')==P.clock(model),'failed save lost live Core/player owner')
        collision.unlink();save(restored,path,model,highwater,player,saves,'failed-publication-owner-reused')
        runtime.stop(kill=True);runtime=None
        runtime=Runtime(path,registry);last,last_ping=runtime.mcp(False)
        require(last_ping['peer']==highwater+1,'second restart peer allocation differs');inspect(last,player)
        last.call('world.clock',fault='PermissionDenied')
        final_actor,final_actor_ping=runtime.mcp();require(final_actor_ping['peer']==highwater+2,'second restart developer peer allocation differs')
        require(final_actor.call('world.clock')==P.clock(model),'second restart lost recovered save')
        checks.extend(['actual MCP dynamic discovery and observer/developer boundaries','strict step schema, at prohibition, exactly-once dispatched JSON sequence including invalid envelopes; malformed physical JSON retains sequence',
                       'actual paused Core47 scene with measured Java player ticks and held physical owners','acknowledged durable Core+Record bytes then unsaved mutation SIGKILL restores previous whole bundle',
                       'restart clears keys/mouse and preserves body/support/raw degree fields/pending Core queue','queued collider edits precede each individual resumed physics tick','exclusive temporary collision preserves old save/unowned temporary and complete live owner'])
        metrics['scene_mutations']=47;metrics['raw_tcp_requests']=sum(c.count for r in Runtime.observed for c in r.raw_clients)
    finally:
        if runtime is not None:runtime.stop()


def fixture_restarts(registry,count,identity,saves,rejections,checks):
    official_identity,official_count,_=P.registry_identity(P.OFFICIAL)
    official=WORK/'official-empty.nbt';official.unlink(missing_ok=True);runtime=Runtime(official,P.OFFICIAL,'normal','create')
    try:
        actor,ping=runtime.mcp();model=W.empty_world(official_count,official_identity);player=initial_record();inspect(actor,player)
        require(actor.call('registry.block',{'name':'minecraft:stone'})['name']=='minecraft:stone','official registry API material lookup differs')
        save(actor,official,model,ping['peer'],player,saves,'official35723-state-registry-default-create')
    finally:runtime.stop()
    fresh=WORK/'fresh-empty.nbt';fresh.unlink(missing_ok=True);runtime=Runtime(fresh,registry,'normal','create')
    try:
        actor,ping=runtime.mcp();model=W.empty_world(count,identity);player=initial_record();inspect(actor,player)
        require(actor.call('world.clock')==P.clock(model),'production fresh initializer did not retain empty Core')
        save(actor,fresh,model,ping['peer'],player,saves,'default-create-empty-Core-player')
    finally:runtime.stop()
    model=W.empty_world(count,identity);model.update(tick=29,day_time=400,revision=0)
    # No motion occurs while paused; these are exact admission/restore records,
    # not a claim that the runtime can move at every finite coordinate/dimension.
    looks=[(0x80000000,0,PC.raw32(365),0xff7fffff),(PC.raw32(45),PC.raw32(-30),PC.raw32(-720),0x7f7fffff)]
    for i,look in enumerate(looks):
        words=list(PC.snapshot(position=tuple(PC.raw64(v) for v in (-.5,64.,-.5)),support=(0xffffffff,0,0x80000000),support_flag=1,
                               velocity=(0x8000000000000000,1,0x8000000000000001),inputs=(1,0x80000000,0x007fffff),delay=0x80000000,trigger=0xffffffff,
                               sync=1,speed=0x80000000,head=0x7f7fffff))
        words[39:41]=(PR.projection(look[0]),PR.projection(look[1]));player=record_bytes(tuple(words),look)
        path=WORK/f'exact-restore-{i}.nbt';path.write_bytes(bundle_bytes(model,120+i,player));runtime=Runtime(path,registry,'scene')
        try:
            actor,ping=runtime.mcp();inspect(actor,player);require(actor.call('world.clock')==P.clock(model),'nonpristine fixture initialization altered loaded Core')
            raw=runtime.tcp();peer=raw.call('ping')['peer'];require(raw.call('fixture.transient')['buttons']==0,'saved raw-degree restore reintroduced held keys')
            save(actor,path,model,peer,player,saves,'exact-body-support-look-restoration-'+str(i))
        finally:runtime.stop()
    # Explicit injected driver rejection exercises the real runtime rollback
    # while Core still advances, and accepts both tick-boundary values 1/1000.
    path=WORK/'driver-failure.nbt';path.unlink(missing_ok=True);runtime=Runtime(path,registry,'fail-context','create')
    try:
        actor,ping=runtime.mcp();raw=runtime.tcp();peer=raw.call('ping')['peer'];player=initial_record();model=scene_world(count,identity)
        for ticks in (1,1000):
            result=actor.call('simulation.step',{'ticks':ticks});model['tick']+=ticks;model['day_time']+=ticks
            require(result==P.clock(model),'admitted step boundary clock differs');inspect(actor,player)
        status=raw.call('fixture.transient');require(status['buttons']==1 and status['last_error']=='player-context: explicit-session-fixture-context-failure','runtime rejection failed to retain controller/error state')
        save(actor,path,model,peer,player,saves,'context-rejection-Core-advance-player-rollback')
    finally:runtime.stop()
    checks.extend(['paused loaded finite body/support/metadata/signed-zero/raw current/past degree records roundtrip without fixture replacement',
                   'actual injected driver context rejection retains player/control owner while Core advances; ticks1 and1000 admitted'])


def startup_tests(registry,count,identity,cases,rejections,checks):
    path=WORK/'malformed.nbt';valid=bundle_bytes(W.empty_world(count,identity),3,initial_record())
    for name,data in cases:
        path.write_bytes(data);reject_startup(name,path,registry,rejections,'create');require(path.read_bytes()==data,'failed startup modified original bytes '+name)
    # Palette failure occurs after the closed codec successfully decodes, in
    # Session.new; the next process then acquires the same lock after repair.
    missing_palette=WORK/'missing-palette.tsv';missing_palette.write_text(P.TINY_TSV)
    small_identity,small_count,_=P.registry_identity(missing_palette)
    path.write_bytes(bundle_bytes(W.empty_world(small_count,small_identity),3,initial_record()))
    reject_startup('post-codec-palette-failure',path,missing_palette,rejections)
    path.write_bytes(valid);runtime=Runtime(path,registry)
    try:
        actor,ping=runtime.mcp(False);require(ping['peer']==4,'startup refusal did not release process lease for later acquisition');inspect(actor,initial_record())
    finally:runtime.stop()
    missing=WORK/'absent.nbt';missing.unlink(missing_ok=True)
    reject_startup('missing-policy-default-refuse',missing,registry,rejections)
    reject_startup('invalid-missing-policy',missing,registry,rejections,'invalid')
    checks.extend(['malformed closed Core+Record/schema/dimension/projection bundles refuse before listener and preserve source bytes',
                   'post-codec palette startup failure then repaired process acquires unchanged lease path','missing-save default refusal and strict create policy'])


def atomic_interruption_tests(registry,count,identity,saves,rejections,checks,metrics):
    old_model=W.empty_world(count,identity);new_model=W.empty_world(count,identity);new_model.update(tick=9,day_time=400)
    old_player=initial_record();words=list(PC.snapshot(position=tuple(PC.raw64(v) for v in (1.5,2.,-.5)),speed=0))
    look=(PC.raw32(45),PC.raw32(-30),PC.raw32(365),0x80000000);words[39:41]=(PR.projection(look[0]),PR.projection(look[1]));new_player=record_bytes(tuple(words),look)
    old=bundle_bytes(old_model,31,old_player);new=bundle_bytes(new_model,32,new_player)
    for data in (old,new):parse_bundle(data,count,identity)
    payload=WORK/'atomic-new.bin';payload.write_bytes(new);observations=[]
    for stage in ('created','written','synced','published','directory_synced'):
        path=WORK/('atomic-'+stage+'.nbt');path.write_bytes(old);suffix='stage-'+stage.replace('_','-')
        temporary=Path(str(path)+'.pending-'+suffix);temporary.unlink(missing_ok=True)
        env=environment(path,MCP.free_port(),registry);env['MC_ATOMIC_PAUSE']=stage
        process=subprocess.Popen([str(SERVER),'--gpu','off','--threads','1','--','atomic',str(path),suffix,str(payload)],cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        seen=[]
        try:
            while True:
                require(select.select([process.stdout],[],[],15)[0],'atomic publication stage timeout')
                line=process.stdout.readline().decode().strip();require(bool(line),'atomic publisher exited before selected stage')
                seen.append(line)
                if line==stage:break
            published=stage in ('published','directory_synced');expected=new if published else old
            require(path.read_bytes()==expected,'selected stage exposed partial/cross-generation bundle')
            lock=Path(str(path)+'.lock');inode=lock.stat().st_ino
            reject_startup('atomic-publisher-held-lease-'+stage,path,registry,rejections)
            process.kill();stdout,stderr=process.communicate(timeout=5)
            require(process.returncode==-9 and not stdout and not stderr,'stage publisher did not die by actual SIGKILL cleanly')
            require(path.read_bytes()==expected,'process interruption changed complete publication generation')
            if not published:require(temporary.is_file() and temporary.read_bytes()==(b'' if stage=='created' else new),'orphan temporary differs from stage write status')
            else:require(not temporary.exists(),'published rename left its owned temporary')
            runtime=Runtime(path,registry)
            try:
                actor,ping=runtime.mcp();expected_model=new_model if published else old_model;expected_player=new_player if published else old_player
                require(lock.stat().st_ino==inode,'stage-killed lease restart changed lock-file inode')
                inspect(actor,expected_player);require(actor.call('world.clock')==P.clock(expected_model),'stage restart cross-generation Core/player')
                save(actor,path,expected_model,ping['peer'],expected_player,saves,'stage-restart-'+stage)
            finally:runtime.stop()
            observations.append({'stage':stage,'observed_stages':seen,'exit_code':process.returncode,'published_generation':'new' if published else 'old',
                                 'bundle_sha256':sha(expected),'complete_bundle_bytes':len(expected),'orphan_temporary':not published,
                                 'lock_inode_preserved':True,'restart_Core_and_Record_exact':True})
        finally:
            if process.poll() is None:process.kill();process.communicate(timeout=5)
    metrics['publication_stage_interruptions']=observations
    checks.append('separate leased Atomic.publish_with primitive lane: actual SIGKILL at all five returned stages exposes complete old/new Core+Record pair; orphan temporaries ignored on actual Session restart')


def source_hashes():
    return PC.imports([ENTRY,ROOT/'src/player_session.bend',ROOT/'src/player_storage.bend',ROOT/'mcp.bend'])


def verify_receipt(sources):
    receipt=json.loads(RECEIPT.read_text());require(receipt['sources_sha256']==sources,'PlayerSession frozen native closure changed')
    for built in receipt['builds']:PR.check_receipt(sources,{'sources_sha256':sources,'build':built})
    require(sha(SERVER.read_bytes())==receipt['builds'][0]['binary_sha256'] and sha(BRIDGE.read_bytes())==receipt['builds'][1]['binary_sha256'],'native convenience copies changed')
    return receipt


def build_native(sources):
    reports=[]
    for entry,binary in ((ENTRY,SERVER),(ROOT/'mcp.bend',BRIDGE)):
        path=WORK/(binary.name+'-build.json');command=[sys.executable,ROOT/'tools/build_native.py',entry,'-o',binary,'--bend',BEND,'--report',path]
        process=subprocess.Popen([str(v) for v in command],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
        print(json.dumps({'status':'native-build-started','entry':str(entry.relative_to(ROOT)),'pid':process.pid,'sources_sha256':sources}),flush=True)
        try:stdout,stderr=process.communicate(timeout=600)
        except subprocess.TimeoutExpired:
            import signal
            os.killpg(process.pid,signal.SIGKILL);process.communicate();raise AssertionError('PlayerSession native build600s timeout')
        require(process.returncode==0,'native build failed '+stderr.decode()[-2000:]);reports.append(json.loads(path.read_text()))
    require(source_hashes()==sources,'production or harness changed during build')
    write_json(RECEIPT,{'sources_sha256':sources,'builds':reports})
    return verify_receipt(sources)


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--preflight',action='store_true');parser.add_argument('--build-only',action='store_true');parser.add_argument('--skip-build',action='store_true');parser.add_argument('--reuse-reference',action='store_true',help='require unchanged pinned Java/source/output provenance, then reuse ignored observations');args=parser.parse_args()
    WORK.mkdir(parents=True,exist_ok=True);registry=WORK/'registry.tsv';registry.write_text(TINY_TSV)
    identity,count,registry_info=P.registry_identity(registry);sources=source_hashes();model=W.empty_world(count,identity);cases=corruption_fixtures(model)
    # Java probes and small ordinary checks are allowed before the heavy build slot.
    reference=json.loads((WORK/'reference.json').read_text()) if args.skip_build or args.build_only or args.reuse_reference else reference_fixtures()
    jars,release=verified_classpath()
    java_sources={'ReferenceMovementProbe':sha(MOVE_SOURCE.encode()),'ReferenceDirectMovementProbe':sha(DIRECT_SOURCE.encode()),'ReferenceTravelProbe':sha(TRAVEL_SOURCE.encode()),
                  'ReferencePlayerTickProbe':sha(TICK_SOURCE.encode()),'ReferenceSupportProbe':sha(SUPPORT_SOURCE.encode()),'ReferencePlayerSessionProbe':sha(java_source().encode())}
    for provenance in reference['provenance']:
        require(provenance['sources_sha256']==java_sources and provenance['classpath']==[fingerprint(p) for p in jars] and provenance['runtime']==fingerprint(JAVA),'pinned Java source/artifact provenance changed')
    require(reference['provenance'][0]['output_sha256']==sha(canonical([reference['first']])) and reference['provenance'][1]['output_sha256']==sha(canonical([reference['restart'],reference['unsaved']])),'actual Java output integrity changed')
    require(reference['first_record_sha256']==[sha(java_record(t)) for t in reference['first']['ticks']],'Java observation bytes/projection changed')
    require(reference['restart_record_sha256']==[sha(java_record(t)) for t in reference['restart']['ticks']],'Java restart observation bytes/projection changed')
    fixture_manifest=[{'name':n,'bytes':len(b),'sha256':sha(b)} for n,b in cases]
    preflight={'status':'prepared-native-unverified','corrupt_startup_cases':len(cases),'fixture_manifest_sha256':sha(canonical(fixture_manifest)),
               'sources_sha256':sources,'registry':registry_info,'official_registry':P.registry_identity(P.OFFICIAL)[2],'reference_sha256':sha(canonical(reference)),
               'actual_Java_ticks':len(reference['first']['ticks'])+len(reference['restart']['ticks'])+len(reference['unsaved']['ticks']),
               'reference_provenance':reference['provenance'],'sine_table':fingerprint(TABLE),
               'oracle_tools_sha256':{str(Path(m.__file__).relative_to(ROOT)):sha(Path(m.__file__).read_bytes()) for m in (N,W,PC,PR,P,MCP,SW,TW)},
               'runner_sha256':sha(Path(__file__).read_bytes())}
    write_json(ROOT/'evidence/player-session-preflight.json',preflight);write_json(WORK/'startup-fixtures.json',fixture_manifest)
    if args.preflight:
        print(json.dumps({'status':'prepared','corrupt_startup_cases':len(cases),'Java_ticks':preflight['actual_Java_ticks'],'sources':len(sources),'fixture_manifest_sha256':preflight['fixture_manifest_sha256']}));return
    receipt=verify_receipt(sources) if args.skip_build else build_native(sources)
    if args.build_only:print(json.dumps({'status':'built','server_sha256':receipt['builds'][0]['binary_sha256']}));return
    ordinary=PR.bounded_run([BEND,ENTRY,'--check-only'])
    require(ordinary['exit_code']==1 and '79 defs rely on unsafe or foreign code' in ordinary['stdout']+ordinary['stderr'] and 'Location:' not in ordinary['stdout']+ordinary['stderr'],'unexpected ordinary checker error beyond recorded foreign boundary')
    defensive=[PR.receipt_selftests(sources,{'sources_sha256':sources,'build':b}) for b in receipt['builds']]
    started=time.monotonic();saves=[];rejections=[];checks=[];metrics={}
    live_tests(registry,count,identity,reference,saves,rejections,checks,metrics)
    fixture_restarts(registry,count,identity,saves,rejections,checks)
    startup_tests(registry,count,identity,cases,rejections,checks)
    atomic_interruption_tests(registry,count,identity,saves,rejections,checks,metrics)
    verify_receipt(sources);require(sources==source_hashes(),'source changed during actual integration')
    clients=[c for r in Runtime.observed for c in r.clients]
    metrics.update(native_ready_servers=len(Runtime.observed),native_MCP_processes=len(clients),MCP_requests=sum(c.requests for c in clients),MCP_responses=sum(c.responses for c in clients))
    build_summary={'ignored_receipt_path':str(RECEIPT.relative_to(ROOT)),'receipt_sha256':sha(RECEIPT.read_bytes()),
                   'builds':[{**{k:b[k] for k in ('artifact','cache_key','binary_sha256','binary_bytes','emitted_c_sha256','compiler','timings')},
                              'dependency_count':len(b['dependencies']),'dependencies_manifest_sha256':sha(canonical(b['dependencies']))} for b in receipt['builds']]}
    evidence=dict(preflight,status='passed',confidence='high for recorded custom-bundle/neutral-session scenarios',native_build=build_summary,
                  saves=saves,startup_rejections=rejections,checks=checks,metrics=metrics,ordinary_check=ordinary,receipt_corruption_checks=defensive,seconds=round(time.monotonic()-started,6),
                  scope=['Custom project Core+player bundle; no vanilla player.dat/world-save equivalence.',
                         'Declared plain Player neutral context, four admitted block materials; no LocalPlayer/environment/equipment/ability generalization.',
                         'Actual Session acknowledged durable publication, exclusive temporary creation failure and process SIGKILL/restart; separate leased Atomic.publish_with stage-hook lane, no modified production quiet-save hook or simulated power loss.',
                         'Read-only fixture.transient raw TCP probe is harness instrumentation absent from production discovery; no external production player mutation API claim.',
                         'No native window, OS keyboard/mouse input, visual fidelity or whole-game acceptance is established.'],
                  commands=['python3 tools/test_player_session.py --preflight','python3 tools/test_player_session.py --build-only','python3 tools/test_player_session.py --skip-build'])
    write_json(ROOT/'evidence/player-session-native.json',evidence)
    print(json.dumps({'status':'passed','saves':len(saves),'startup_rejections':len(rejections),'metrics':metrics,'seconds':evidence['seconds']}))


if __name__=='__main__':main()
