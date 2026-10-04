#!/usr/bin/env python3
"""Joined actual LocalPlayer actor/native resource renderer verification.

Python owns process/transport orchestration and independent reference comparisons.
No simulation, resource decoding for the product, model baking or rendered native
inputs are implemented here. Default/read-only audit never emit or launch.
"""
from __future__ import annotations
import argparse, ast, copy, dataclasses, hashlib, json, os, re, secrets, select, signal, socket, subprocess, sys, tempfile, threading, time, zlib
from pathlib import Path
from fractions import Fraction
import test_player_client as PC
import test_player_session as Plain
import test_local_player_session as Local
import test_world_resource_frame as Pixels
import test_resource_player_presented_client as Frozen
import platform_cache as Cache
from unittest import mock

ROOT=PC.ROOT
WORK=ROOT/'build/remote-resource-client'
ENTRY=ROOT/'remote_resource_client.bend'
PRESENTER=ROOT/'src/remote_resource_presenter.bend'
BACKEND=ROOT/'remote_resource_server.bend'
BINARY=WORK/'client'
BUILD=WORK/'build.full.json'
BACKEND_BINARY=WORK/'backend-native'
BACKEND_BUILD=WORK/'backend-build.full.json'
READY=WORK/'ready.full.json'
PREFLIGHT=ROOT/'evidence/remote-resource-client-preflight.json'
NATIVE=ROOT/'evidence/remote-resource-client-native.json'
CAP=600
BOUNDARY=[
 'Actual saved LocalPlayer backend and real JAR/model/PNG/baker/visibility/mesh native renderer in two Bend processes; compiler benefit unknown until measured.',
 'Six paused Local views reuse retained actual Java Local records and independent Java geometry/visibility/Pillow comparison-only pixels. Old plain-Player fixtures remain immutable.',
 'Explicit zero-transform three-model/static normalized solid textures, white tint/light, integer shade, CPU nearest/clamp policy; no production atlas/animation/AO/sRGB/final vanilla frame claim.',
 'Hidden guarded Window launches require explicit grants and measure focus/Spaces; returned Window.frame CPU Image is not drawable readback or physical input evidence.',
 'Private synthetic packets test the real actor protocol but are identified as fixtures, not OS keyboard/mouse input. Timer is the sole actual50ms actor callback; frame queries never step.',
 'Stop is explicit controls release/actor stop/process exit after actual public world.save. No automatic save or SIGTERM-save claim.',
 '5s admission gates cover response/read chunks and decoded records; TCP.connect/send and terminal release/process exit remain unbounded effects. Local Window/assets close before best-effort Release; host whole-group caps are separate.',
 'Initial resource load/render can consume the100pulse lease without renewal, causing a closed next call. No startup renewal, physical-input, strict latepoll-race or stale-disconnect runtime claim is inferred.',
 'Declared affine/unsafe/foreign boundaries and uncaptured full native header/library closure remain separate from independent native comparisons.'
]
GROUPS=WORK/'native-owned-groups.ndjson'
BACKEND_ORDINARY=ROOT/'build/remote-resource-server-ordinary.stop-revoke.full.json'
BACKEND_READY=ROOT/'evidence/remote-resource-backend-ready.json'


def require(ok,message):
 if not ok:raise AssertionError(message)
def canonical(value):return Plain.canonical(value)
def digest(data):return hashlib.sha256(data).hexdigest()
def pin(path):
 path=Path(path).resolve(strict=True);return {'path':str(path),'bytes':path.stat().st_size,'sha256':digest(path.read_bytes())}
def write(path,value,exclusive=False):
 path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
 with path.open('xb' if exclusive else 'wb') as out:out.write(canonical(value)+b'\n')
def groups(group):
 rows=subprocess.run(['/bin/ps','-axo','pid=,pgid=,stat=,args='],capture_output=True,text=True,check=True).stdout.splitlines()
 return [{'pid':int(p[0]),'group':int(p[1]),'state':p[2],'argv':p[3]} for row in rows
         if len(p:=row.strip().split(None,3))==4 and int(p[1])==group]
def live(rows):return [r for r in rows if not r['state'].startswith('Z')]

def cleanup(proc,limit=4):
 """No pipe drain/exception may discard already redirected child streams."""
 start=time.monotonic();errors=[];before=groups(proc.pid)
 for sig,wait in ((signal.SIGTERM,.5),(signal.SIGKILL,2)):
  if not live(groups(proc.pid)) and proc.poll() is not None:break
  try:os.killpg(proc.pid,sig)
  except ProcessLookupError:pass
  except OSError as e:errors.append({'signal':int(sig),'type':type(e).__name__,'errno':e.errno,'message':str(e)})
  try:proc.wait(timeout=min(wait,max(.01,limit-(time.monotonic()-start))))
  except subprocess.TimeoutExpired:pass
  deadline=min(start+limit,time.monotonic()+wait)
  while live(groups(proc.pid)) and time.monotonic()<deadline:time.sleep(.02)
 after=groups(proc.pid)
 return {'before':before,'after':after,'errors':errors,'leader_reaped':proc.poll() is not None,
         'live_group_absent':not live(after),'seconds':time.monotonic()-start}

def bounded(argv,cap,label):
 """One whole process group; unconditional persisted result, even on EPERM."""
 directory=WORK/label;directory.mkdir(parents=True,exist_ok=False)
 argv=list(map(str,argv));started=time.monotonic();proc=None;error=None;timed=False;rc=None;owned=None
 attempt={'argv':argv,'started_monotonic':started,'deadline_monotonic':started+cap,'cap_seconds':cap,'attempts':1}
 write(directory/'attempt.full.json',attempt,True)
 with (directory/'stdout').open('xb') as out,(directory/'stderr').open('xb') as err:
  try:
   proc=subprocess.Popen(argv,cwd=ROOT,stdout=out,stderr=err,start_new_session=True)
   print(json.dumps(dict(attempt,process_group=proc.pid,pid=proc.pid)),flush=True)
   try:rc=proc.wait(timeout=cap)
   except subprocess.TimeoutExpired:timed=True
  except BaseException as e:error={'type':type(e).__name__,'message':str(e)}
  finally:
   if proc is not None:
    try:owned=cleanup(proc)
    except BaseException as e:owned={'error_type':type(e).__name__,'message':str(e),'leader_reaped':proc.poll() is not None,'live_group_absent':False}
    rc=proc.returncode
 result=dict(attempt,pid=proc.pid if proc else None,exit_code=rc,timed_out=timed,error=error,
             cleanup=owned,seconds=time.monotonic()-started,stdout=pin(directory/'stdout'),stderr=pin(directory/'stderr'))
 write(directory/'result.full.json',result,True)
 return result

def process_ok(r,code=0):
 require(not r['timed_out'] and r['error'] is None and r['exit_code']==code and r['cleanup']['leader_reaped']
         and r['cleanup']['live_group_absent'] and not r['cleanup'].get('errors'),'bounded owned process failed:'+str(r))

def register(proc,label):
 with GROUPS.open('ab') as out:
  out.write(canonical({'pid':proc.pid,'label':label,'argv':list(map(str,proc.args))})+b'\n');out.flush();os.fsync(out.fileno())

def registered_cleanup():
 rows=[]
 if not GROUPS.exists():return rows
 for line in GROUPS.read_bytes().splitlines():
  row=json.loads(line);present=groups(row['pid']);errors=[]
  if live(present):
   leader=next((r for r in present if r['pid']==row['pid']),None)
   if leader is not None and row['argv'][0] not in leader['argv']:
    errors.append({'type':'UnverifiedReusedLeader','message':'refuse to signal a changed group leader'})
   else:
    try:os.killpg(row['pid'],signal.SIGKILL)
    except ProcessLookupError:pass
    except OSError as e:errors.append({'type':type(e).__name__,'errno':e.errno,'message':str(e)})
  deadline=time.monotonic()+2
  while live(groups(row['pid'])) and time.monotonic()<deadline:time.sleep(.02)
  rows.append(dict(row,before=present,after=groups(row['pid']),errors=errors))
 return rows

def original_pins():
 names=['resource_player_client.bend','src/resource_player_scene.bend','tools/test_resource_player_client.py',
 'resource_player_boxed_client.bend','src/resource_player_boxed_scene.bend','tools/test_resource_player_boxed_client.py',
 'resource_player_presented_client.bend','src/resource_player_presenter.bend','tools/test_resource_player_presented_client.py',
 'evidence/resource-player-presented-client-native.json','evidence/resource-player-presented-client-result.json',
 'evidence/resource-player-presented-client-ready.json','build/resource-player-presented-client/seal.full.json',
 'build/resource-player-presented-client/pixel-expectations.full.json']
 return {str(ROOT/name):pin(ROOT/name) for name in names}

def initial_view_generation():
 path=WORK/'pre-frustum-generation/manifest.full.json';value=json.loads(path.read_bytes());files=[]
 for row in value['files']:
  archived=pin(row['archive']);require(archived['sha256']==row['sha256'],'archived all-sky candidate changed:'+row['archive'])
  files.append(archived)
 return {'manifest':pin(path),'files':files,'native_executions':0,'scope':'archived initial weak all-sky candidate, never adopted as native acceptance'}

def source_generation():
 snapshot=Cache.native.Snapshot();base=(PC.BEND.resolve().parent.parent/'bend2/base.bend').resolve()
 Cache.native.source_graph(ENTRY,base,os.environ,snapshot)
 backend_snapshot=Cache.native.Snapshot();Cache.native.source_graph(BACKEND,base,os.environ,backend_snapshot)
 source=snapshot.manifest();backend_source=backend_snapshot.manifest();helpers=Local.tool_closure([Path(__file__)])
 return {'entry':pin(ENTRY),'presenter':pin(PRESENTER),'compiler':pin(PC.BEND),
         'source_manifest':source,'source_manifest_sha256':Cache.native.digest(Cache.native.encoded(source)),
         'backend_source_manifest':backend_source,'backend_source_manifest_sha256':Cache.native.digest(Cache.native.encoded(backend_source)),
         'backend_ordinary':pin(BACKEND_ORDINARY),'backend_ready':pin(BACKEND_READY),
         'documentation':pin(ROOT/'docs/REMOTE_RESOURCE_CLIENT.md'),
         'tools':{str(p):pin(p) for p in helpers},'original_generations':original_pins(),
         'initial_view_generation':initial_view_generation(),
         'resources':{'jar':pin(PC.JAR),'registry':pin(Plain.P.OFFICIAL),'sine':pin(PC.TABLE)},
         'runtime':{str(p):pin(p) for p in (Path(sys.executable),Path(Pixels.np.__file__),Path(Pixels.np._core._multiarray_umath.__file__),Path(Pixels.Image.__file__),Path(Pixels.Image.core.__file__))}}

def local_sample(model,record,visibility):
 """Expected cells/eye/visibility from supplied canonical world and actual record."""
 words,_=Local.PC.parse_snapshot(Local.PR.decode(record.motion)[0]);_,palette,_=PC.official_scene()
 ids=[palette[n] for n in Pixels.STATE_NAMES];names=dict(zip(ids,Pixels.STATE_NAMES))
 position=[Local.PC.f64(v) for v in Local.PC.bits64(words[:6])]
 position[1]+=Local.PC.f32(record.eye)
 table={}
 for row in visibility['observations']['state_pair_matrix']:
  key=(row['current'],row['adjacent'],row['direction_ordinal'])
  require(key not in table or table[key]==row['should_render_face'],'actual Java face observations disagree')
  table[key]=row['should_render_face']
 raw=[];blocks=[];masks=[];directions=[(0,-1,0),(0,1,0),(0,0,-1),(0,0,1),(-1,0,0),(1,0,0)]
 for z in range(-4,4):
  for y in range(-1,5):
   for x in range(-4,4):
    state=Frozen.model_cell(model,x,y,z)
    if state==ids[0]:continue
    require(state in ids[1:],'unsupported independently supplied pixel material')
    material=ids.index(state)-1;boundary=int(x in(-4,3))+int(y in(-1,4))+int(z in(-4,3))
    cell=[x&0xffffffff,y&0xffffffff,z&0xffffffff,boundary,state]
    raw.append([*cell,material]);blocks.append([*[Pixels.word(float(Fraction(c)-Fraction.from_float(eye))) for c,eye in zip((x,y,z),position)],state,material])
    mask=0
    for ordinal,step in enumerate(directions):
     adjacent=Frozen.model_cell(model,*(c+d for c,d in zip((x,y,z),step)))
     require(adjacent in names,'unsupported independent neighbor')
     if table[names[state],names[adjacent],ordinal]:mask|=1<<ordinal
    masks.append([*cell,mask])
 value={'tick':model['tick'],'revision':model['revision'],'blocks':blocks,'raw':raw,'masks':masks,
        'origin':list(Local.PC.words64(tuple(Local.PC.raw64(v) for v in position))),
        'camera':[0,0,0,*words[39:41]],'palette':ids,'reads':6*len(raw)}
 Pixels.validate_sample(value);return value

def fixture_relocation(world,palette):
 """Explicit finite-world input change, preserving actual LocalRecord receivers."""
 changes=[]
 for old,new in [((1,1,1),(-1,2,1)),((2,1,2),(-1,2,2)),((2,2,2),(-1,3,2))]:
  state=Frozen.model_cell(world,*old)
  require(state in(palette['minecraft:dirt'],palette['minecraft:oak_planks']),'relocation source is not an original raised fixture block')
  require(Frozen.model_cell(world,*new)==palette['minecraft:air'],'relocation target is not original air')
  Plain.set_block(world,*old,palette['minecraft:air']);Plain.set_block(world,*new,state)
  changes.append({'from':list(old),'to':list(new),'state':state})
 return changes

def prepare_views():
 cases,reference,_=Local.reference_cases();by={c['id']:c for c in cases};initial,palette,_=PC.official_scene()
 choices=[('standing',by['scheduled_zero']['steps'][0]['before']),('crouched',by['scheduled_shift']['steps'][0]['after']),
 ('sprint',by['scheduled_sprint_jump']['steps'][0]['after']),('jump-edited',by['scheduled_jump']['steps'][0]['after']),
 ('jump-restored',by['scheduled_jump']['steps'][1]['after']),('standing-restored',by['scheduled_shift']['steps'][2]['after'])]
 _,_,visibility,quads,textures,entries=Pixels.references();result=[]
 for index,(name,record) in enumerate(choices):
  world=copy.deepcopy(initial);world.update(tick=min(index+1,5),day_time=min(index+1,5),paused=True,revision=50 if index==3 else 53 if index>=4 else 47)
  relocation=fixture_relocation(world,palette)
  if index==3:
   for z in(-3,-2,-1):Plain.set_block(world,0,0,z,palette['minecraft:air'])
  sample=local_sample(world,record,visibility);baked=Pixels.expected_quads(sample,quads);rgb=Pixels.image_oracle(sample,baked,textures,128,128)
  path=WORK/('view-'+name+'.nbt');write_bytes=Local.bundle_bytes(world,31,record)
  path.write_bytes(write_bytes);decoded,actual,_=Local.parse_bundle(write_bytes,world['state_count'],world['registry'])
  require(actual==record,'paused actual LocalRecord fixture roundtrip')
  expected=WORK/('expected-'+name+'.rgb');expected.write_bytes(rgb)
  rgba=b''.join(rgb[i:i+3]+b'\xff' for i in range(0,len(rgb),3))
  result.append({'name':name,'fixture':pin(path),'record_sha256':digest(Local.local_bytes(record)),
   'sample':sample,'sample_sha256':digest(canonical(sample)),'quad_sha256':digest(canonical(baked)),
   'quads':len(baked),'rgb':pin(expected),'rgba_crc32':zlib.crc32(rgba),
   'finite_fixture_relocation':relocation,'world_sha256':digest(canonical(world)),
   'rgb_unique_colors':len({rgb[i:i+3] for i in range(0,len(rgb),3)}),
   'nonbackground_pixels':sum(rgb[i:i+3]!=bytes((100,160,235)) for i in range(0,len(rgb),3)),
   'receiver':'actual retained LocalPlayer phase record; paused snapshot, not physics on this39-cell world'})
 write(WORK/'views.full.json',result,True)
 return {'file':pin(WORK/'views.full.json'),'views':6,'references':{'local':pin(Local.REFERENCE),
  'models':pin(Pixels.MODEL_REFERENCE),'visibility':pin(Pixels.VISIBILITY_REFERENCE),'entries':entries},
  'oracle':pin(Path(Pixels.__file__)),'all_expected_pixels_quads_samples_outside_executable_inputs':True}

def audit_views(prepared):
 require(pin(prepared['file']['path'])==prepared['file'],'prepared six Local views changed')
 values=json.loads(Path(prepared['file']['path']).read_bytes());require(len(values)==6,'view count changed')
 for row in values:
  require(pin(row['fixture']['path'])==row['fixture'] and pin(row['rgb']['path'])==row['rgb'],'fixture/pixel bytes changed')
  require(digest(canonical(row['sample']))==row['sample_sha256'],'sample changed');Pixels.validate_sample(row['sample'])
 return values

def backend_ordinary_admission():
 value=json.loads(BACKEND_ORDINARY.read_bytes())
 text=value.get('stdout','')+value.get('stderr','')
 m=re.fullmatch(r'SOME PROOFS FAIL\nError: 97 defs rely on unsafe or foreign code:\n((?:- [^\n]+\n)+)',text)
 require(value['returncode']==1 and not value['timed_out'] and m is not None and len(m[1].splitlines())==97,
         'backend final ordinary boundary receipt differs')
 require(value['before']==value['after'],'backend ordinary sources changed during checking')
 for path,item in value['before'].items():
  current=pin(ROOT/path);require({k:current[k] for k in('sha256','bytes')}==item,'backend ordinary source changed:'+path)
 return {'receipt':pin(BACKEND_ORDINARY),'ready':pin(BACKEND_READY),'boundary_count':97,
         'scope':'root whole backend ordinary check; only inherited unsafe/foreign declarations, no native acceptance'}

def retained_helpers():
 observer=Frozen.retained_helpers();require(observer['observer']['artifact'],'missing actual desktop observer')
 return observer

def decoder_admission():
 # Actual installed-emitter output from the accepted plain client, pinned to
 # this identical compiler binary, establishes the decoder body observation.
 report_path=ROOT/'build/player-client/build.full.json';report=json.loads(report_path.read_bytes())
 manifest_path=ROOT/'build/platform-cache/entries'/report['cache_key']/'manifest.json';manifest=json.loads(manifest_path.read_bytes())
 original=ROOT/'build/platform-cache/sources'/manifest['key_data']['prekey']/'original.c'
 require(pin(original)['sha256']==report['original_c_sha256'] and manifest['adapter']['compiler_sha256']==pin(PC.BEND)['sha256'],
         'accepted actual installed decoder C/compiler changed')
 text=original.read_text();start=text.index('static Term io_str(');end=text.index('\n}',start)+2;body=text[start:end]
 require('c    = 0xFFFD' in body and 'b < 0xC2 || b > 0xF4' in body and 'b == 0xED ? 0x9F' in body,
         'actual native UTF8 replacement/overlong/surrogate observations changed')
 template=ROOT.parent/'bend/bend2/comp.ts';require(template.is_file(),'baseline source template absent')
 return {'accepted_build_report':pin(report_path),'actual_original_C':pin(original),'io_str_sha256':digest(body.encode()),
         'baseline_source_template':pin(template),'poll_native':pin(PC.BEND.parent.parent/'bend2/effs/tcp_poll.c'),
         'poll_js':pin(PC.BEND.parent.parent/'bend2/effs/tcp_poll.js'),
         'scope':'structural ASCII rejection; no fresh malformed-byte runtime or generalUTF8 claim'}

def ordinary():
 rows=[]
 for source in(ENTRY,PRESENTER):
  label='joined-final-ordinary-'+source.stem
  r=bounded([PC.BEND,source,'--check-only'],60,label)
  text=Path(r['stdout']['path']).read_text()+Path(r['stderr']['path']).read_text()
  m=re.fullmatch(r'SOME PROOFS FAIL\nError: ([0-9]+) defs rely on unsafe or foreign code:\n((?:- [^\n]+\n)+)',text)
  process_ok(r,1);require(m is not None and int(m[1])==len(m[2].splitlines()),'source has a diagnostic beyond declared unsafe/foreign boundaries')
  rows.append({'source':pin(source),'boundary_count':int(m[1]),'receipt':pin(WORK/label/'result.full.json'),'output_sha256':digest(text.encode())})
 return rows

def scenario():
 return {'renderer':str(ENTRY),'backend':str(BACKEND),'public_catalog':sorted(PC.EXPECTED_OPERATIONS),
 'actual_pipeline':'one LocalSession actor query -> exact Pose F64 origin/palette/visibility -> private ASCII DTO -> RF.load/WRF.draw/Mesh.render -> same returned Window.frame Image',
 'paired_lanes':['six paused actual Local record/world views','actual39block view plus live queued block edits and save/reload','private capability/exclusive lease/strict sequence/epoch/EOF release','actual unpaused50ms actor cadence; atomic frame identities','resource/visibility/readback errors preserve saved bundle and later reload'],
 'local_receiver_lane':'retained actual8Local phases through private fixture packets+publicsimulation.step and complete NBT/Core comparisons, separately labeled syntheticinput',
 'bounds':{'renderer_build':600,'backend_build':600,'ordinary':60,'native_suite':120,'native_renderer_observer':60,'backend_startup':20,'backend_stop':5,'exchange_read':5},
 'no_foreground_launch':True,'no_python_render_inputs':True,'build_attempts':1,'frame_dimensions':[128,128],'window_dimensions':[512,512]}

def prepare():
 require(not READY.exists(),'preparation exists; audit or explicitly archive a superseded generation')
 WORK.mkdir(parents=True,exist_ok=True);before=source_generation();rows=ordinary();views=prepare_views();helpers=retained_helpers()
 # Decoder source admission is structural; actual malformed-byte cases belong
 # to the retained native suite, not this host/source preparation receipt.
 decoder=decoder_admission()
 require(source_generation()==before,'source generation changed during ordinary/reference preparation')
 value={'schema':1,'generation':before,'ordinary':rows,'views':views,'helpers':helpers,'scenario':scenario(),
        'backend_ordinary':backend_ordinary_admission(),'decoder_source':decoder,'boundaries':BOUNDARY,'native_executions':0,'fresh_java_executions':0,'window_executions':0}
 value['seal_sha256']=digest(canonical(value));write(READY,value,True)
 write(PREFLIGHT,{'schema':1,'status':'ordinary_and_independent_paused_local_pixels_prepared','ready':pin(READY),
                  'seal_sha256':value['seal_sha256'],'ordinary':rows,'views':views,'scenario':scenario(),'boundaries':BOUNDARY},True)
 return value

def audit():
 value=json.loads(READY.read_bytes());body={k:v for k,v in value.items() if k!='seal_sha256'}
 require(value['seal_sha256']==digest(canonical(body)),'invalid preparation seal')
 require(source_generation()==value['generation'],'prepared source/compiler/effect/tool/original generation changed')
 require(decoder_admission()==value['decoder_source'],'decoder admission generation changed')
 require(backend_ordinary_admission()==value['backend_ordinary'],'backend ordinary admission changed')
 audit_views(value['views'])
 for r in value['ordinary']:require(pin(r['receipt']['path'])==r['receipt'],'ordinary receipt changed')
 return value


class UnretriedInputDrift(RuntimeError):pass

def emit(args):
 require(args.lead_slot_granted,'native emission requires explicit lead slot');audit()
 require((WORK/'native-build/attempt.full.json').is_file() and not BUILD.exists() and not BINARY.exists(),'no active single build reservation, or artifact exists')
 original=Cache.InputsChanged
 class Refused(original):
  def __new__(cls,*a,**kw):raise UnretriedInputDrift(*a)
 Cache.InputsChanged=Refused
 try:
  result=Cache.ensure_platform(ENTRY,BINARY,bend=PC.BEND)
  require(result['retries']==0 and result['route']=='guarded-macos-cpu-window','guarded build route/retry changed')
  audit();write(BUILD,result,True);print(json.dumps({'status':'built','binary':pin(BINARY),'timings':result['timings']}),flush=True)
 finally:Cache.InputsChanged=original

def build(args):
 require(args.lead_slot_granted,'native emission requires explicit lead slot');ready=audit()
 r=bounded([sys.executable,Path(__file__),'--_emit','--lead-slot-granted'],CAP,'native-build')
 result={'schema':1,'ready':pin(READY),'seal_sha256':ready['seal_sha256'],'process':r,'phase':'build-only','native_client_executions':0}
 result['status']='build_failed_first_attempt' if r['timed_out'] or r['error'] or r['exit_code']!=0 else 'build_complete'
 if BUILD.exists():result['build']=pin(BUILD)
 if BINARY.exists():result['binary']=pin(BINARY)
 write(ROOT/'evidence/remote-resource-client-build.json',result,True)
 process_ok(r);audit();require(pin(BINARY)['sha256']==json.loads(BUILD.read_bytes())['binary_sha256'],'retained artifact differs')
 return result

def backend_emit(args):
 require(args.lead_slot_granted,'backend emission requires explicit lead slot');audit()
 require((WORK/'backend-build/attempt.full.json').is_file() and not BACKEND_BUILD.exists() and not BACKEND_BINARY.exists(),
         'no active single backend build reservation, or artifact exists')
 original=Cache.native.InputsChanged
 class Refused(original):
  def __new__(cls,*a,**kw):raise UnretriedInputDrift(*a)
 Cache.native.InputsChanged=Refused
 try:
  result=Cache.native.ensure_native(BACKEND,BACKEND_BINARY,bend=PC.BEND)
  require(result['retries']==0,'backend source-drift retry changed')
  audit();write(BACKEND_BUILD,result,True)
  print(json.dumps({'status':'backend-built','binary':pin(BACKEND_BINARY),'timings':result['timings']}),flush=True)
 finally:Cache.native.InputsChanged=original

def backend_build(args):
 require(args.lead_slot_granted,'backend emission requires explicit lead slot');ready=audit()
 r=bounded([sys.executable,Path(__file__),'--_backend-emit','--lead-slot-granted'],CAP,'backend-build')
 result={'schema':1,'ready':pin(READY),'seal_sha256':ready['seal_sha256'],'process':r,'phase':'backend-build-only',
         'native_client_executions':0,'backend_executions':0}
 result['status']='backend_build_failed_first_attempt' if r['timed_out'] or r['error'] or r['exit_code']!=0 else 'backend_build_complete'
 if BACKEND_BUILD.exists():result['build']=pin(BACKEND_BUILD)
 if BACKEND_BINARY.exists():result['binary']=pin(BACKEND_BINARY)
 write(ROOT/'evidence/remote-resource-client-backend-build.json',result,True)
 process_ok(r);audit()
 require(pin(BACKEND_BINARY)['sha256']==json.loads(BACKEND_BUILD.read_bytes())['binary_sha256'],'backend retained artifact differs')
 return result

class LeaseBusy(RuntimeError):pass

class Private:
 """Test-only real socket client. Never supplies assets/quads/rendered pixels."""
 def __init__(self,backend):
  self.socket=socket.create_connection(('127.0.0.1',backend.private_port),timeout=5);self.buffer=b'';self.sequence=1;self.epoch=None;self.log=[]
  try:
   self.send([1,0,backend.token]);reply=self.receive()
   if reply==[1,3,'',0,'RendererLeaseBusy']:raise LeaseBusy('RendererLeaseBusy')
   require(reply[:2]==[1,0] and len(reply)==4 and reply[3]==0,'private HelloAck differs')
   self.epoch=reply[2];require(isinstance(self.epoch,str) and self.epoch,'private epoch missing')
  except BaseException:self.socket.close();raise
 def send(self,value):
  data=json.dumps(value,ensure_ascii=True,separators=(',',':')).encode('ascii')+b'\n'
  require(len(data)-1<=16384,'test request exceeds frozen wire budget');self.socket.sendall(data)
 def receive(self):
  deadline=time.monotonic()+5
  while b'\n' not in self.buffer:
   self.socket.settimeout(max(.001,deadline-time.monotonic()));data=self.socket.recv(8192)
   require(data,'private EOF before response');self.buffer+=data;require(len(self.buffer)<=65537,'private response byte limit')
  line,self.buffer=self.buffer.split(b'\n',1);require(not self.buffer,'private unsolicited response/tail')
  require(len(line)<=16384 and all(v<128 for v in line),'private ASCII/parser budget')
  return json.loads(line)
 def call(self,command,kind=2):
  sequence=self.sequence;self.send([1,1,self.epoch,sequence,command]);reply=self.receive();self.sequence+=1
  require(len(reply)>=4 and reply[:4]==[1,kind,self.epoch,sequence],'private response identity/tag differs:'+str(reply[:4]))
  self.log.append({'sequence':sequence,'command_tag':command[0],'reply_tag':reply[1]});return reply
 def sample(self):return decode_sample(self.call([0,128,128],1)[4])
 def packet(self,held):
  codes=(119,115,97,100,32,65592,65595)
  actions=[[1,True,[0,code,bool(held&(1<<index))]] for index,code in enumerate(codes)]
  return self.call([1,[True,True,actions]])
 def close(self):self.socket.close()

def acquire(backend):
 """Observe only the declared asynchronous Busy state, retaining every reply."""
 started=time.monotonic();deadline=started+5;rows=[];control=None;failure=None
 ordinal=getattr(backend,'acquisition_count',0);backend.acquisition_count=ordinal+1
 try:
  while time.monotonic()<deadline:
   try:control=Private(backend);return control
   except LeaseBusy:
    rows.append({'at_monotonic':time.monotonic(),'reply':[1,3,'',0,'RendererLeaseBusy']});time.sleep(.02)
  raise AssertionError('expected RendererLeaseBusy did not clear before acquisition deadline')
 except BaseException as e:failure={'type':type(e).__name__,'message':str(e)};raise
 finally:
  write(backend.directory/('lease-acquisition-'+str(ordinal)+'.full.json'),
        {'started_monotonic':started,'deadline_monotonic':deadline,'busy_observations':rows,
         'epoch':control.epoch if control else None,'error':failure},True)


def decode_sample(value):
 require(isinstance(value,list) and len(value)==7,'Frame Sample shape')
 tick,revision,origin,camera,palette,reads,rows=value
 require(all(isinstance(r,list) and len(r)==10 for r in rows),'Frame rows shape')
 sample={'tick':tick,'revision':revision,'origin':origin,'camera':camera,'palette':palette,'reads':reads,
         'raw':[r[:6] for r in rows],'blocks':[r[7:10]+r[4:6] for r in rows],
         'masks':[r[:5]+[r[6]] for r in rows]}
 Pixels.validate_sample(sample);return sample


class Backend:
 def __init__(self,binary,label,path,create=False,unpaused=False):
  self.label=label;self.path=Path(path);self.port=Plain.MCP.free_port();self.private_port=Plain.MCP.free_port()
  while self.private_port==self.port:self.private_port=Plain.MCP.free_port()
  self.token=secrets.token_hex(32);self.boot=secrets.token_hex(16);self.clients=[];self.directory=WORK/label
  self.directory.mkdir(exist_ok=False);self.out=self.directory/'stdout';self.err=self.directory/'stderr'
  env=Plain.environment(self.path,self.port,Plain.P.OFFICIAL,'create' if create else None)
  env.update(MC_RENDER_PORT=str(self.private_port),MC_RENDER_TOKEN=self.token,MC_RENDER_EPOCH=self.boot)
  args=[str(binary),'--threads','2','--gpu','off','--','--verification-fixture','--stdin-control','--sine',str(PC.TABLE)]
  if unpaused:args.append('--unpaused')
  self.handles=[self.out.open('xb'),self.err.open('xb')]
  self.proc=subprocess.Popen(args,cwd=ROOT,env=env,stdin=subprocess.PIPE,stdout=self.handles[0],stderr=self.handles[1],start_new_session=True)
  register(self.proc,label)
  self.started=time.monotonic();self.deadline=self.started+120;self.stopped=False
  write(self.directory/'attempt.full.json',{'argv':args,'pid':self.proc.pid,'cap_seconds':120,'started_monotonic':self.started,
        'deadline_monotonic':self.deadline,'public_port':self.port,'private_port':self.private_port,'capability_not_logged':True},True)
  try:
   deadline=time.monotonic()+20
   while time.monotonic()<deadline:
    events=PC.events(self.out);public=[r for r in events if r.get('event')=='server.ready'];private=[r for r in events if r.get('event')=='renderer.ready']
    if public and private:
     require(public[0]['port']==self.port and public[0]['host']=='127.0.0.1' and private[0]['port']==self.private_port,'backend listener identity differs');break
    require(self.proc.poll() is None,'backend startup refused:'+self.err.read_text()[-800:]);time.sleep(.02)
   else:raise AssertionError('paired backend readiness timeout')
  except BaseException:finish_backend(self);raise
 def tcp(self,developer=False):
  client=Plain.RawTCP(self.port);self.clients.append(client);ping=client.call('ping')
  if developer:client.call('session.open',{'mode':'developer','token':Plain.MCP.TOKEN})
  return client,ping
 def mcp(self,bridge,developer=True):
  client=Plain.MCP.MCP(bridge,self.port,Plain.MCP.TOKEN if developer else None);self.clients.append(client);client.initialize();ping=client.call('ping');return client,ping
 def stop(self,failed=False):
  if self.stopped:return
  self.stopped=True;errors=[]
  for c in self.clients:
   try:c.cleanup() if hasattr(c,'cleanup') else c.close()
   except BaseException as e:errors.append(str(e))
  try:
   if self.proc.poll() is None:
    self.proc.stdin.write(b'stop\n');self.proc.stdin.flush();self.proc.stdin.close();self.proc.wait(timeout=5)
  except BaseException as e:errors.append(type(e).__name__+':'+str(e))
  result=cleanup(self.proc)
  for h in self.handles:h.close()
  value={'exit_code':self.proc.returncode,'cleanup':result,'errors':errors,'seconds':time.monotonic()-self.started,
         'stdout':pin(self.out),'stderr':pin(self.err),'explicit_stdin_stop':True,'save_automatic_claim':False}
  write(self.directory/'process.full.json',value,True)
  if not failed:
   require(self.proc.returncode==0 and result['leader_reaped'] and result['live_group_absent'] and not errors,'backend explicit stop failed')
   require(not self.err.read_bytes(),'backend emitted unexpected error')
  for port in(self.port,self.private_port):
   with socket.socket() as probe:probe.settimeout(.5);require(probe.connect_ex(('127.0.0.1',port))!=0,'backend left listener after exit')

def finish_backend(actor):
 """Persist cleanup failures without replacing the first semantic failure."""
 primary=sys.exc_info()[1]
 try:actor.stop(failed=primary is not None)
 except BaseException as e:
  write(actor.directory/'cleanup-secondary-error.full.json',{'type':type(e).__name__,'message':str(e),
        'primary_error':{'type':type(primary).__name__,'message':str(primary)} if primary is not None else None},True)
  if primary is None:raise


class Renderer:
 def __init__(self,binary,backend,label,helpers,frames=4,trace=True,jar=None,trace_path=None):
  self.label=label;self.directory=WORK/label;self.directory.mkdir(exist_ok=False)
  self.out=self.directory/'stdout';self.err=self.directory/'stderr';self.images=self.directory/'images'
  if trace:self.images.mkdir()
  env=dict(os.environ,MC_RENDER_PORT=str(backend.private_port),MC_RENDER_TOKEN=backend.token,BEND_MINECRAFT_LAUNCH_MODE='hidden')
  env.pop('BEND_MINECRAFT_FRAME_DIR',None)
  if trace:env['BEND_MINECRAFT_FRAME_DIR']=str(trace_path or self.images)
  args=['--threads','2','--gpu','off','--','--frames',str(frames)]
  if jar:args+=['--jar',str(jar)]
  observer=helpers['observer']['artifact']
  self.proc=subprocess.Popen([observer,str(binary),str(self.out),str(self.err),*args],cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
  register(self.proc,label)
  self.started=time.monotonic();self.trace=trace
  try:
   require(select.select([self.proc.stdout],[],[],10)[0],'desktop observer startup timeout')
   line=self.proc.stdout.readline();row=json.loads(line);require(row['event']=='observer.child','desktop child announcement missing');self.pid=row['pid']
   write(self.directory/'attempt.full.json',{'argv':[observer,str(binary),*args],'pid':self.proc.pid,'child_pid':self.pid,'started_monotonic':self.started,
    'deadline_monotonic':self.started+60,'launch_mode':'hidden','private_port':backend.private_port,'capability_not_logged':True},True)
  except BaseException:
   write(self.directory/'startup-cleanup.full.json',cleanup(self.proc),True);raise
 def frames(self):return [r for r in PC.events(self.out) if r.get('event')=='client.frame']
 def wait_frame(self,tick,revision,blocks,timeout=5):
  deadline=time.monotonic()+timeout
  while time.monotonic()<deadline:
   rows=[r for r in self.frames() if(r['tick'],r['revision'],r['blocks'])==(tick,revision,blocks)]
   if rows:return rows[-1]
   require(self.proc.poll() is None,'renderer ended before view');time.sleep(.02)
  raise AssertionError('renderer did not observe intended live actor view')
 def finish(self,status=0,frames=None):
  try:out,err=self.proc.communicate(timeout=max(.01,60-(time.monotonic()-self.started)))
  finally:
   result=cleanup(self.proc)
   write(self.directory/'cleanup.full.json',result,True)
  require(self.proc.returncode==0 and not err,'desktop observer failed')
  report=json.loads(out.strip());require(not report['timed_out'] and report['child_status']==status,'native renderer exit differs')
  require(report['before_frontmost_pid']>0 and report['before_frontmost_pid']==report['after_frontmost_pid'] and report['sampled_frontmost_pids']==[report['before_frontmost_pid']],'frontmost application changed')
  require(report['space_change_notifications']==0 and self.pid not in report['activation_notification_pids'],'Window activation/Spaces change observed')
  require(result['leader_reaped'] and result['live_group_absent'],'renderer group remains live')
  if frames is not None:require(len(self.frames())==frames,'actual frame descriptions differ')
  require(all(r['renderer']=='remote-local-resource-instrument' for r in self.frames()),'actual renderer identity differs')
  report.update(stdout=pin(self.out),stderr=pin(self.err),cleanup=result,frame_descriptions=len(self.frames()),same_returned_cpu_image=True,drawable_readback=False)
  write(self.directory/'process.full.json',report,True);return report
 def cleanup(self):
  if self.proc.poll() is None:cleanup(self.proc)


def pixels(renderer,expected=None):
 samples,images=Frozen.parse_readbacks(renderer.out);require(set(samples)==set(images)==set(range(len(renderer.frames()))),'actual frame/sample/image serials differ')
 _,_,_,quads,textures,_=Pixels.references();rows=[];computed={}
 for serial,sample in sorted(samples.items()):
  if expected is not None:require(sample==expected,'actual atomic Local sample differs from independent paused Java-record/world view')
  key=digest(canonical(sample))
  if key not in computed:
   baked=Pixels.expected_quads(sample,quads);rgb=Pixels.image_oracle(sample,baked,textures,128,128)
   computed[key]=(rgb,digest(canonical(baked)))
  rgb,quad_digest=computed[key]
  path=renderer.images/(str(serial)+'.ppm');actual=path.read_bytes();header=b'P6\n128 128\n255\n'
  require(actual.startswith(header) and actual[len(header):]==rgb,'actual returned Window.frame Image differs from independent CPU reference')
  rgba=b''.join(rgb[i:i+3]+b'\xff' for i in range(0,len(rgb),3));require(images[serial]==[128,128,zlib.crc32(rgba)],'readback CRC/shape differs')
  rows.append({'serial':serial,'sample_sha256':key,'ppm':pin(path),'quads_sha256':quad_digest,'rgb_sha256':digest(rgb)})
 write(renderer.directory/'pixels.full.json',rows,True);return {'frames':len(rows),'rgb_pixels':16384*len(rows),'receipt':pin(renderer.directory/'pixels.full.json')}

class FaultPeer:
 """Malformed-handshake socket fixtures only; never serves a frame or assets."""
 def __init__(self,label,payload,delay=0):
  self.label=label;self.payload=payload;self.delay=delay;self.token=secrets.token_hex(32)
  self.listener=socket.socket();self.listener.bind(('127.0.0.1',0));self.listener.listen(1)
  self.private_port=self.listener.getsockname()[1];self.listener.settimeout(10)
  self.record={'label':label,'payload_sha256':digest(payload),'payload_bytes':len(payload),'delay':delay,
               'no_frame_sample_asset_or_pixel_reply':True}
  self.thread=threading.Thread(target=self.serve,name='private-wire-fault-'+label,daemon=True);self.thread.start()
 def serve(self):
  try:
   connection,_=self.listener.accept()
   with connection:
    connection.settimeout(5);data=b''
    while b'\n' not in data:
     part=connection.recv(8192);require(part,'fault fixture did not receive real renderer Hello');data+=part
     require(len(data)<=16385,'fault fixture received oversized Hello')
    line,tail=data.split(b'\n',1);require(not tail and json.loads(line)==[1,0,self.token],'real renderer Hello differs')
    self.record['actual_hello_observed']=True
    if self.delay:time.sleep(self.delay)
    try:connection.sendall(self.payload);connection.shutdown(socket.SHUT_WR)
    except (BrokenPipeError,ConnectionResetError):self.record['peer_closed_before_fixture_send']=True
  except BaseException as e:self.record['error']={'type':type(e).__name__,'message':str(e)}
  finally:self.listener.close()
 def finish(self):
  self.thread.join(11)
  require(not self.thread.is_alive(),'fault fixture thread not finished')
  require(self.record.get('actual_hello_observed') and 'error' not in self.record,'fault fixture failed before malformed reply:'+str(self.record))
  return self.record

def renderer_protocol_faults(ready):
 hello=b'[1,0,"fault-epoch",0]\n';rows=[]
 for label,payload,delay,diagnostic in [
   ('overlong-ASCII',b'\xc0\xaf\n',0,'Wire:RawNonASCII'),
   ('surrogate-UTF8',b'\xed\xa0\x80\n',0,'Wire:RawNonASCII'),
   ('raw-nonASCII',b'\xc3\xa9\n',0,'Wire:RawNonASCII'),
   ('wrong-Hello-sequence',b'[1,0,"fault-epoch",1]\n',0,'Wire:'),
   ('wrong-Hello-kind',b'[1,2,"fault-epoch",1]\n',0,'Wire:Correlation'),
   ('unsolicited-reply',hello+hello,0,'Wire:'),
   ('partial-extra-tail',hello+b'X',0,'Wire:'),
   ('missing-LF',hello[:-1],0,'Wire:'),
   ('response-deadline',hello,5.25,'Wire:')]:
  peer=FaultPeer(label,payload,delay);renderer=None
  try:
   renderer=Renderer(BINARY,peer,'renderer-wire-'+label,ready['helpers'],frames=0,trace=False)
   report=renderer.finish(status=1,frames=0)
   require(diagnostic in renderer.err.read_text(),'actual renderer admitted or failed before the malformed reply:'+label)
   rows.append({'case':label,'peer':peer.finish(),'report':report})
  finally:
   if renderer:renderer.cleanup()
   peer.listener.close();peer.thread.join(11)
 return {'cases':rows,'actual_renderer_TCP_poll_and_decode':True,'no_world_actor_or_frame_reply_substitute':True}


def backend_artifact(path):
 report=json.loads(Path(path).read_bytes())
 while 'build' in report:report=report['build']
 require(report.get('retries',0)==0,'backend source drift build retry')
 artifact=Path(report['path'] if 'path' in report else report['artifact'])
 require(pin(artifact)['sha256']==report['binary_sha256'],'backend artifact changed')
 require(any(Path(r['path']).resolve()==BACKEND.resolve() for r in report['dependencies']),'backend artifact is not actual normal remote_resource_server entry')
 for row in report['dependencies']:
  require(pin(row['path'])['sha256']==row['sha256'],'backend retained source/effect/tool dependency changed:'+row['path'])
 return artifact,{'report':pin(path),'binary':pin(artifact),'entry':pin(BACKEND),'cache_key':report['cache_key']}


def actual_local_receivers(backend_binary,bridge):
 cases,_,_=Local.reference_cases();registry=Plain.P.OFFICIAL;identity,count,_=Plain.P.registry_identity(registry);results=[]
 for case in cases:
  world=Local.scene_world(count,identity);record=case['steps'][0]['before'];path=WORK/('local-'+case['id']+'.nbt');path.write_bytes(Local.bundle_bytes(world,31,record))
  actor=Backend(backend_binary,'backend-local-'+case['id'],path)
  control=None
  try:
   raw,ping=actor.tcp(True);control=acquire(actor);Local.inspect(raw,record);highwater=ping['peer'];steps=[]
   for step in case['steps']:
    control.packet(step['held_mask'])
    raw.call('simulation.step',{'ticks':1});Plain.apply_tick(world);record=step['after'];Local.inspect(raw,record)
    require(raw.call('world.clock')==Plain.P.clock(world),'real Local receiver Core tick differs')
    sample=control.sample();_,_,vis,_,_,_=Pixels.references();require(sample==local_sample(world,record,vis),'atomic frame and actual Java Local record differ')
    saved=raw.call('world.save');data=path.read_bytes();require(data==Local.bundle_bytes(world,highwater,record),'actual Local public save differs from independent full NBT/Core bytes')
    steps.append({'actual_java_step':step['index'],'record_sha256':digest(Local.local_bytes(record)),'bundle_sha256':digest(data),'sample_sha256':digest(canonical(sample))})
   control.call([2]);control.close();control=None
   results.append({'id':case['id'],'steps':steps,'synthetic_private_packet_fixture':True,'actual_os_input_claim':False})
  finally:
   if control:control.close()
   finish_backend(actor)
 return results


def native_once(args):
 require(args.lead_slot_granted and args.backend_build_report,'paired native run needs explicit grant and retained actual backend artifact')
 ready=audit();require(not NATIVE.exists(),'native attempt already exists; no automatic rerun')
 require(pin(BINARY)['sha256']==json.loads(BUILD.read_bytes())['binary_sha256'],'renderer artifact differs')
 backend,backend_pin=backend_artifact(args.backend_build_report)
 run=WORK/'native-attempt';run.mkdir(exist_ok=False);write(run/'reservation.full.json',{'ready':pin(READY),'backend':backend_pin,'renderer':pin(BINARY),'attempts':1},True)
 summary={'schema':1,'ready':pin(READY),'backend':backend_pin,'renderer':pin(BINARY),'boundaries':BOUNDARY,'paired_views':[]};owned=[]
 try:
  for view in audit_views(ready['views']):
   path=WORK/('native-'+view['name']+'.nbt');path.write_bytes(Path(view['fixture']['path']).read_bytes())
   actor=Backend(backend,'backend-'+view['name'],path);owned.append(actor);renderer=None
   try:
    renderer=Renderer(BINARY,actor,'renderer-'+view['name'],ready['helpers'],frames=3);owned.append(renderer)
    renderer.finish(frames=3);pixel=pixels(renderer,view['sample'])
    raw,ping=actor.tcp(True);world,record,_=Local.parse_bundle(path.read_bytes(),PC.official_scene()[0]['state_count'],PC.official_scene()[0]['registry']);Local.inspect(raw,record)
    require(raw.call('world.clock')==Plain.P.clock(world),'paused resource polls stepped Local owner')
    raw.call('world.save');require(path.read_bytes()==Local.bundle_bytes(world,ping['peer'],record),'paused full Local saved bundle differs')
    summary['paired_views'].append({'name':view['name'],'pixels':pixel,'saved_bundle':pin(path),'record_sha256':digest(Local.local_bytes(record))})
   finally:
    if renderer:renderer.cleanup()
    finish_backend(actor)
  summary['actual_local_receivers']=actual_local_receivers(backend,ready['helpers']['mcp']['artifact'])
  summary['renderer_protocol_faults']=renderer_protocol_faults(ready)
  # Additional joined lifecycle/protocol lanes are prepared explicitly below.
  summary['joined']=joined_lanes(backend,ready)
  summary['status']='passed_bounded_joined_domain';summary['generation_unchanged']=audit()['generation']==ready['generation'];write(NATIVE,summary,True)
 except BaseException as e:
  summary.update(status='first_native_failure',error_type=type(e).__name__,error=str(e));write(NATIVE,summary,True);raise
 finally:
  cleanup_errors=[]
  for owner in reversed(owned):
   try:owner.stop(failed=True) if isinstance(owner,Backend) else owner.cleanup()
   except BaseException as e:cleanup_errors.append(type(e).__name__+':'+str(e))
  write(run/'outer-cleanup.full.json',{'errors':cleanup_errors,'owners':len(owned)},True)
 return summary

def native(args):
 require(args.lead_slot_granted and args.backend_build_report,'paired native run needs explicit slot and backend artifact')
 audit();require(not GROUPS.exists(),'paired native ownership registry already exists')
 result=None
 try:
  result=bounded([sys.executable,Path(__file__),'--_native-once','--lead-slot-granted',
                  '--backend-build-report',args.backend_build_report],120,'native-supervisor')
 finally:
  rows=registered_cleanup();write(WORK/'native-supervisor-groups.full.json',rows,True)
  write(ROOT/'evidence/remote-resource-client-lifecycle.json',{'process':result,'registered_group_cleanup':rows,
         'native_worker_result':pin(NATIVE) if NATIVE.exists() else None},True)
 require(all(not live(r['after']) and not r['errors'] for r in rows),'paired registered group cleanup failed')
 process_ok(result);require(json.loads(NATIVE.read_bytes())['status']=='passed_bounded_joined_domain','native worker first failure')
 return json.loads(NATIVE.read_bytes())


def joined_lanes(backend_binary,ready):
 bridge=ready['helpers']['mcp']['artifact'];world,palette,_=PC.official_scene();record=Local.default_record()
 path=WORK/'joined.nbt';path.write_bytes(Local.bundle_bytes(world,31,record));actor=Backend(backend_binary,'backend-joined',path)
 render=None;result={'queued_edits':0,'public_catalog':18,'atomic_paused_views':[]};expected=[]
 try:
  developer,ping=actor.mcp(bridge);observer,_=actor.mcp(bridge,False);raw,rawping=actor.tcp(True)
  highwater=max(ping['peer'],rawping['peer'],observer.call('ping')['peer'])
  names=[r['name'] for r in developer.request('tools/list')['result']['tools']]
  require(set(names)==PC.EXPECTED_OPERATIONS and len(names)==18,'actual Local public catalog changed by private renderer transport')
  observer.call('world.save',fault='PermissionDenied')
  render=Renderer(BINARY,actor,'renderer-joined',ready['helpers'],frames=250);render.wait_frame(1,47,39)
  _,_,visibility,_,_,_=Pixels.references();expected.append(local_sample(world,record,visibility));Local.inspect(raw,record)
  for target,name in((2,'minecraft:air'),(3,'minecraft:stone')):
   for z in(-3,-2,-1):Local.queue_set(raw,world,('minecraft:overworld',0,0,z),palette[name],target);result['queued_edits']+=1
  raw.call('world.save');queued=path.read_bytes();require(queued==Local.bundle_bytes(world,highwater,record),'queued real Local bundle differs')
  for tick,revision,count in((2,50,36),(3,53,39)):
   raw.call('simulation.step',{'ticks':1});Plain.apply_tick(world)
   # Complete public LocalRecord is a conditional camera authority here. Its
   # physics is independently tested against actual8receivers in another lane;
   # do not claim a new Java reference for this edited39-block world.
   record=Local.decode_local(bytes(raw.call('player.inspect')['nbt_bytes']))
   sample=local_sample(world,record,visibility);expected.append(sample);render.wait_frame(tick,revision,count)
   require(raw.call('world.clock')==Plain.P.clock(world),'live edit owner clock differs')
   result['atomic_paused_views'].append(digest(canonical(sample)))
  raw.call('world.save');saved=path.read_bytes();require(saved==Local.bundle_bytes(world,highwater,record),'edited full Local save differs')
  render.finish(frames=250);samples,images=Frozen.parse_readbacks(render.out)
  permitted={digest(canonical(r)) for r in expected};require(all(digest(canonical(r)) in permitted for r in samples.values()),'paused atomic sample mixed world/pose generations')
  result['pixels']=pixels(render);result['bundle_sha256']=digest(saved);result['queued_bundle_sha256']=digest(queued)
 finally:
  if render:render.cleanup()
  finish_backend(actor)
 # Actual lease reacquisition and Local record/pending/Core restore, with a
 # separately running saved actor; the rendering process never loads a save.
 reloaded=Backend(backend_binary,'backend-joined-reload',path);render=None
 try:
  raw,ping=reloaded.tcp(True);require(ping['peer']==highwater+1,'public peer highwater not restored')
  Local.inspect(raw,record);require(raw.call('world.clock')==Plain.P.clock(world),'reload Core changed')
  render=Renderer(BINARY,reloaded,'renderer-joined-reload',ready['helpers'],frames=3);render.finish(frames=3)
  result['reload_pixels']=pixels(render,local_sample(world,record,visibility));require(path.read_bytes()==saved,'renderer/load/close changed saved bytes')
 finally:
  if render:render.cleanup()
  finish_backend(reloaded)
 result['protocol']=protocol_lanes(backend_binary,ready,saved)
 result['idle_release']=idle_release_lanes(backend_binary)
 result['failures']=resource_failure_lanes(backend_binary,ready,saved)
 result['cadence']=cadence_lane(backend_binary,ready,saved)
 return result


def protocol_lanes(binary,ready,saved):
 path=WORK/'protocol.nbt';path.write_bytes(saved);actor=Backend(binary,'backend-protocol',path);control=None;rows=[]
 try:
  raw,_=actor.tcp(True);before=raw.call('world.clock');control=acquire(actor)
  expected_epoch=control.epoch;expected_sample=control.sample()
  # A second valid capability cannot acquire the sole controlling lease.
  second=socket.create_connection(('127.0.0.1',actor.private_port),timeout=5)
  try:
   second.sendall(json.dumps([1,0,actor.token],separators=(',',':')).encode()+b'\n');reply=json.loads(second.makefile('rb').readline())
   require(reply[:2]==[1,3] and reply[2:4]==['',0],'controlling renderer lease was not exclusive')
  finally:second.close()
  control.call([2]);control.close();control=None
  # Exact bad epoch/sequence records and actual malformed bytes are injected
  # only into the real private transport; none are render/pixel substitutes.
  for label,body in [('stale-epoch',lambda e:[1,1,expected_epoch,1,[0,128,128]]),
                     ('repeated-sequence',lambda e:[1,1,e,1,[2]]),
                     ('wrong-version',lambda e:[2,1,e,1,[2]])]:
   control=acquire(actor);epoch=control.epoch
   if label=='repeated-sequence':control.call([2])
   control.send(body(epoch));answer=control.receive();require(answer[1]==3,'bad private identity/version accepted')
   rows.append({'case':label,'reply_tag':answer[1]});control.close();control=None
  for label,bad in [('overlong-ASCII',b'\xc0\xaf\n'),('surrogate-UTF8',b'\xed\xa0\x80\n'),('raw-nonASCII',b'\xc3\xa9\n'),
                    ('missing-LF',b'[1,1,"invalid",1,[2]]')]:
   control=acquire(actor);control.socket.sendall(bad)
   if label=='missing-LF':control.socket.shutdown(socket.SHUT_WR)
   try:answer=control.receive()
   except (OSError,ValueError):answer=None
   except AssertionError as error:
    require(str(error)=='private EOF before response','malformed test encountered an unexpected parser failure:'+str(error));answer=None
   if answer is not None:require(answer[1]==3,'malformed byte record accepted')
   rows.append({'case':label,'closed_or_faulted':True});control.close();control=None
  # max48 is syntactically valid but the actor excludes its sentinel. This
  # does not forge next==max; that exact terminal branch stays source-reviewed.
  control=acquire(actor);control.send([1,1,control.epoch,(1<<48)-1,[2]])
  answer=control.receive();require(answer[:4]==[1,3,control.epoch,(1<<48)-1] and answer[4]=='RendererLeaseOrSequence','terminal Nat48 request was not refused by actor')
  rows.append({'case':'terminal-Nat48','valid_codec_integer':True,'actor_refused':True,'exhausted_next_receiver_claim':False});control.close();control=None
  # One send carries a complete valid prefix and a malformed later record.
  for tag in(0,2):
   for bad_kind in('ASCII','version'):
    control=acquire(actor);epoch=control.epoch;command=[0,128,128] if tag==0 else [2]
    prefix=json.dumps([1,1,epoch,1,command],separators=(',',':')).encode('ascii')+b'\n'
    suffix=b'\xc0\xaf\n' if bad_kind=='ASCII' else json.dumps([2,1,epoch,2,[2]],separators=(',',':')).encode('ascii')+b'\n'
    control.socket.sendall(prefix+suffix)
    with control.socket.makefile('rb') as stream:
     first=json.loads(stream.readline(16385));kind=1 if tag==0 else 2
     require(first[:4]==[1,kind,epoch,1],'valid coalesced prefix erased by malformed later record')
     if tag==0:require(decode_sample(first[4])==expected_sample,'coalesced valid Frame atomic sample changed')
     second=stream.readline(16385)
     if bad_kind=='version':require(json.loads(second)==[1,3,'',0,'Wire:MalformedRequest'],'invalid coalesced version reply differs')
     else:require(second==b'','bad rawASCII suffix did not close connection')
    rows.append({'case':('Frame' if tag==0 else 'Release')+'-prefix-'+bad_kind,'single_send_bytes':len(prefix+suffix),'valid_prefix_acknowledged':True})
    control.close();control=None
  control=acquire(actor);control.call([1,[True,True,[[1,True,[0,119,True]]]]]);control.close();control=None
  # EOF release must allow a fresh epoch, not preserve a stale held forward
  # packet. Paused actor state is observed before any subsequent tick.
  control=acquire(actor);require(control.epoch!=expected_epoch,'renderer epoch reused');control.call([2])
  require(raw.call('world.clock')==before,'private polls/failures/release ticked paused owner')
  require(path.read_bytes()==saved,'private malformed/EOF changed durable bytes')
  return {'cases':rows,'epoch_reacquired':True,'clock_unchanged':True,'bundle_unchanged':True,
          'release_input_behavior_coverage':'real protocol/epoch cleanup plus actual Local receiver lane; no physical keys'}
 finally:
  if control:control.close()
  finish_backend(actor)


def idle_release_lanes(binary):
 cases,_,_=Local.reference_cases();case=next(c for c in cases if c['id']=='scheduled_zero');step=case['steps'][0]
 identity,count,_=Plain.P.registry_identity(Plain.P.OFFICIAL);rows=[]
 for label in('silent','partial'):
  world=Local.scene_world(count,identity);record=step['before'];path=WORK/('idle-'+label+'.nbt')
  path.write_bytes(Local.bundle_bytes(world,31,record));actor=Backend(binary,'backend-idle-'+label,path);control=None
  try:
   raw,ping=actor.tcp(True);control=acquire(actor);old_epoch=control.epoch;control.packet(1)
   started=time.monotonic();parts=[]
   if label=='partial':
    for index in range(1,6):
     target=started+index*.8;time.sleep(max(0,target-time.monotonic()))
     control.socket.sendall(b'[' if index==1 else b' ');parts.append(time.monotonic())
   control.socket.settimeout(max(.001,started+6-time.monotonic()))
   closed=control.socket.recv(1);observed=time.monotonic();require(closed==b'','silent/partial record replied or renewed deadline')
   require(observed-started<6,'fixed5s read admission did not close within measured margin')
   control.close();control=None
   # Step before a new hello (which itself releases) to test idle cleanup.
   raw.call('simulation.step',{'ticks':1});Plain.apply_tick(world);Local.inspect(raw,step['after'])
   require(raw.call('world.clock')==Plain.P.clock(world),'idle cleanup changed Core beyond the explicit step')
   control=acquire(actor);require(control.epoch!=old_epoch,'idle expiry reused renderer epoch')
   raw.call('world.save');require(path.read_bytes()==Local.bundle_bytes(world,ping['peer'],step['after']),'idle cleanup/neutral phase full save differs')
   control.call([2]);control.close();control=None
   rows.append({'case':label,'elapsed_until_peer_close':observed-started,'partial_send_times':parts,
    'fresh_epoch':True,'actual_neutral_Java_phase_after_idle_cleanup':step['index'],
    'idle_EOF_and100pulse_TTL_order_not_independently_attributed':True})
  finally:
   if control:control.close()
   finish_backend(actor)
 return rows

def resource_failure_lanes(binary,ready,saved):
 old=json.loads((ROOT/'build/resource-player-presented-client/seal.full.json').read_bytes())['asset_fixtures']
 path=WORK/'failures.nbt';path.write_bytes(saved);actor=Backend(binary,'backend-resource-failures',path);rows=[]
 try:
  for label,jar,diagnostic in [('missing-jar',WORK/'absent.jar','resource scene:'),
       ('invalid-zip',old['invalid_zip']['path'],'resource scene:'),('broken-png',old['broken_png']['path'],'PNG:')]:
   if label!='missing-jar':require(pin(jar)['sha256']==old['invalid_zip' if label=='invalid-zip' else 'broken_png']['sha256'],'frozen failure resource changed')
   renderer=Renderer(BINARY,actor,'renderer-'+label,ready['helpers'],frames=0,trace=False,jar=jar)
   try:
    report=renderer.finish(status=1,frames=0);require(diagnostic in renderer.err.read_text(),'resource failure stopped before expected decoder')
    require(path.read_bytes()==saved,'failed renderer changed saved owner');rows.append({'case':label,'report':report})
   finally:renderer.cleanup()
  renderer=Renderer(BINARY,actor,'renderer-readback-failure',ready['helpers'],frames=3,trace_path=WORK/'absent-images')
  try:
   report=renderer.finish(status=1,frames=1);samples,images=Frozen.parse_readbacks(renderer.out)
   require(len(samples)==1 and not images and 'frame readback:' in renderer.err.read_text(),'readback failure did not follow actual Window.frame')
   require(path.read_bytes()==saved,'readback failure changed durable owner');rows.append({'case':'readback-file-failure','report':report})
  finally:renderer.cleanup()
  renderer=Renderer(BINARY,actor,'renderer-frames0-recovery',ready['helpers'],frames=0,trace=False)
  try:renderer.finish(frames=0);require(path.read_bytes()==saved,'valid later renderer altered save')
  finally:renderer.cleanup()
  return {'rows':rows,'same_backend_owner_recovered':True,'saved_bundle_unchanged':True}
 finally:finish_backend(actor)


def cadence_lane(binary,ready,saved):
 path=WORK/'cadence.nbt';path.write_bytes(saved);actor=Backend(binary,'backend-cadence',path,unpaused=True);renderer=None
 try:
  raw,_=actor.tcp(True);renderer=Renderer(BINARY,actor,'renderer-cadence',ready['helpers'],frames=100,trace=False)
  measured=[]
  for _ in range(8):
   measured.append({'time':time.monotonic(),'clock':raw.call('world.clock')});time.sleep(.075)
  renderer.finish(frames=100);require(measured[-1]['clock']['tick']>measured[0]['clock']['tick'],'actual50ms actor timer did not advance')
  frames=renderer.frames();require(frames and all(r['revision']==frames[0]['revision'] for r in frames),'unpaused fixture world revision changed without edits')
  require(path.read_bytes()==saved,'unpaused renderer implicitly saved')
  return {'clock_observations':measured,'frame_ticks':sorted({r['tick'] for r in frames}),
          'actual_timer_without_simulation_step':True,'held_OS_inputs':False,'gameplay_performance_claim':False}
 finally:
  if renderer:renderer.cleanup()
  finish_backend(actor)


def host_guards():
 # Parser/comparison-only controls run without Bend/native/Java/Window.
 values=audit_views(json.loads(READY.read_bytes())['views']) if READY.exists() else (json.loads((WORK/'views.full.json').read_bytes()) if (WORK/'views.full.json').exists() else [])
 count=0
 for row in values:
  sample=row['sample'];rows=[]
  for raw,block,mask in zip(sample['raw'],sample['blocks'],sample['masks']):rows.append(raw+[mask[-1]]+block[:3])
  wire=[sample['tick'],sample['revision'],sample['origin'],sample['camera'],sample['palette'],sample['reads'],rows]
  require(decode_sample(wire)==sample,'host independent row projection changed');count+=1
 source=ast.parse(Path(__file__).read_text());require(any(isinstance(n,ast.FunctionDef) and n.name=='bounded' for n in source.body),'missing bounded lifecycle')
 class Fake:
  pid=2147483646;returncode=None
  def wait(self,timeout):self.returncode=-9;return -9
  def poll(self):return self.returncode
 fake=Fake();row={'pid':fake.pid,'group':fake.pid,'state':'R','argv':'host fake only'}
 calls=iter(([row],[row],[],[],[]))
 def observed(group):return next(calls,[])
 with mock.patch(__name__+'.groups',observed),mock.patch(__name__+'.os.killpg',side_effect=PermissionError(1,'injected permission refusal')):
  result=cleanup(fake,.1)
 require(result['leader_reaped'] and result['live_group_absent'] and result['errors'][0]['errno']==1,'cleanup PermissionError lost diagnostic or reaped status')
 # Exercise the actual child no-retry route with a fake native-cache call.
 # The fake raises the real InputsChanged constructor at its dynamic boundary;
 # no compiler, source loader, cache build or artifact is invoked.
 args=argparse.Namespace(lead_slot_granted=False)
 with mock.patch(__name__+'.audit',side_effect=AssertionError('must refuse before audit')),mock.patch(__name__+'.bounded',side_effect=AssertionError('must refuse before launch')):
  try:backend_build(args)
  except AssertionError as e:require(str(e)=='backend emission requires explicit lead slot','missing backend grant reached another operation')
  else:raise AssertionError('missing backend grant accepted')
 original=Cache.native.InputsChanged
 calls=[]
 def drift(*a,**kw):
  calls.append((a,kw));raise Cache.native.InputsChanged('injected pre-artifact source drift')
 with tempfile.TemporaryDirectory(prefix='remote-resource-host-guard-') as directory:
  work=Path(directory);(work/'backend-build').mkdir();(work/'backend-build/attempt.full.json').write_bytes(b'{}\n')
  with mock.patch(__name__+'.WORK',work),mock.patch(__name__+'.BACKEND_BUILD',work/'backend-build.full.json'),mock.patch(__name__+'.BACKEND_BINARY',work/'backend-native'),mock.patch(__name__+'.audit',return_value={}),mock.patch.object(Cache.native,'ensure_native',side_effect=drift):
   try:backend_emit(argparse.Namespace(lead_slot_granted=True))
   except UnretriedInputDrift as e:require(str(e)=='injected pre-artifact source drift','source drift diagnostic changed')
   else:raise AssertionError('backend source drift did not escape cache retry path')
   require(len(calls)==1 and not (work/'backend-build.full.json').exists() and not (work/'backend-native').exists(),'backend drift retried or wrote an artifact')
 require(Cache.native.InputsChanged is original,'backend drift guard did not restore cache exception class')
 with tempfile.TemporaryDirectory(prefix='remote-resource-stream-guard-') as directory:
  work=Path(directory)
  class Parked:
   pid=2147483646;returncode=None
   def wait(self,timeout):raise subprocess.TimeoutExpired(['inert-fake'],timeout)
   def poll(self):return self.returncode
  def preopened(*a,**kw):
   kw['stdout'].write(b'retained child stdout\n');kw['stderr'].write(b'retained child stderr\n');return Parked()
  with mock.patch(__name__+'.WORK',work),mock.patch(__name__+'.subprocess.Popen',side_effect=preopened),mock.patch(__name__+'.cleanup',side_effect=PermissionError(1,'inert cleanup refusal')):
   result=bounded(['inert-no-process'],.001,'receipt-guard')
  require(result['timed_out'] and result['cleanup']['error_type']=='PermissionError','bounded cleanup exception was lost')
  require(Path(result['stdout']['path']).read_bytes()==b'retained child stdout\n' and Path(result['stderr']['path']).read_bytes()==b'retained child stderr\n','preopened child streams were lost')
  require(json.loads((work/'receipt-guard/result.full.json').read_bytes())==result,'unconditional failed receipt differs')
 with tempfile.TemporaryDirectory(prefix='remote-resource-primary-guard-') as directory:
  class FailedStop:
   def __init__(self,path):self.directory=Path(path)
   def stop(self,failed):raise PermissionError(1,'inert secondary cleanup refusal')
  try:
   try:raise AssertionError('inert primary semantic failure')
   finally:finish_backend(FailedStop(directory))
  except AssertionError as e:require(str(e)=='inert primary semantic failure','cleanup replaced primary semantic failure')
  else:raise AssertionError('primary semantic failure was swallowed')
  receipt=json.loads((Path(directory)/'cleanup-secondary-error.full.json').read_bytes())
  require(receipt['primary_error']['message']=='inert primary semantic failure' and receipt['type']=='PermissionError','primary/secondary cleanup diagnostic lost')
 return {'wire_projection_controls':count,'cleanup_permission_error_controls':1,'compiler_native_java_window_executions':0,
         'backend_missing_grant_controls':1,'backend_no_retry_route_controls':1,
         'preopened_stream_and_unconditional_receipt_controls':1,'first_failure_cleanup_retention_controls':1,
         'scope':'inert host schema and ownership bookkeeping only; no native correctness proof'}


def main():
 p=argparse.ArgumentParser(description=__doc__);g=p.add_mutually_exclusive_group()
 for name in('prepare','audit','host-guards','build-only','backend-build-only','native','_emit','_backend-emit','_native-once'):g.add_argument('--'+name,action='store_true',dest=name.replace('-','_'))
 p.add_argument('--lead-slot-granted',action='store_true');p.add_argument('--backend-build-report',type=Path)
 args=p.parse_args()
 if args._emit:return emit(args)
 if args._backend_emit:return backend_emit(args)
 if args._native_once:return native_once(args)
 if args.prepare:value=prepare()
 elif args.build_only:value=build(args)
 elif args.backend_build_only:value=backend_build(args)
 elif args.native:value=native(args)
 elif args.host_guards:value=host_guards()
 else:value={'status':'prepared-generation-read-only-audit-passed','ready':pin(READY),'seal_sha256':audit()['seal_sha256']}
 print(json.dumps(value if args.host_guards else {k:v for k,v in value.items() if k in('schema','status','seal_sha256','ready','process','binary')},indent=2),flush=True)

if __name__=='__main__':main()
