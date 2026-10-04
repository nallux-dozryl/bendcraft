#!/usr/bin/env python3
"""Sealed ordinary/native verification for the owned LocalPlayer facade.

The actual motion expectations are unchanged official receiver observations.
Python compares raw words and orchestrates bounded jobs; it implements no tick,
controls, collision, support, pose, or world behavior. Heavy actions are explicit.
"""
from __future__ import annotations
import argparse, hashlib, json, os, signal, struct, subprocess, sys, time
from pathlib import Path
import reference_local_phase_runtime_probe as RP
import test_local_phase_runtime as OLD
from reference_inventory import ROOT, canonical, fingerprint, write_json
from build_native import Snapshot, source_graph

BEND=Path('/Users/chuah/.bend/bin/bend')
SOURCE=ROOT/'src/local_player_runtime.bend'
HARNESS=ROOT/'tests/local_player_runtime.bend'
REFERENCE=ROOT/'reference/local_phase_runtime.json'
TABLE=ROOT/'generated/reference_mth_sin.f32'
RAW=ROOT/'build/local-player-runtime/generation-1'
BINARY=RAW/'tests'
PREP=ROOT/'evidence/local-player-runtime-preparation.json'
NATIVE=ROOT/'evidence/local-player-runtime-native.json'
CASES={'scheduled_shift','scheduled_jump','scheduled_sprint_jump','scheduled_zero'}

def require(valid,message):
    if not valid:raise AssertionError(message)
def pin(path):
    return {'path':str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path),**fingerprint(path)}
def sha(value):return hashlib.sha256(canonical(value)).hexdigest()
def generation():
    snap=Snapshot()
    source_graph(HARNESS,(BEND.resolve().parent.parent/'bend2/base.bend').resolve(),dict(os.environ),snap)
    return {v['path']:v['sha256'] for v in snap.manifest()}
def tools():
    return {p:pin(ROOT/p) for p in ('tools/test_local_player_runtime.py','tools/test_local_phase_runtime.py',
        'tools/reference_local_phase_runtime_probe.py','tools/reference_player_tick_phases_probe.py',
        'tools/reference_local_input_probe.py','tools/reference_inventory.py','tools/reference_model_probe.py','tools/build_native.py')}
def current():
    return {'generation':generation(),'tools':tools(),'reference':pin(REFERENCE),
        'table':pin(TABLE),'compiler':pin(BEND),'source':pin(SOURCE),'harness':pin(HARNESS)}
def load_actual():
    data=json.loads(REFERENCE.read_text());RP.integrity(data)
    result=[RP.decode(c) for c in data['cases'] if c['id'] in CASES]
    require({c['id'] for c in result}==CASES,'Selected actual cases missing')
    require(sum(sum(bool(s['ok']) for s in c['steps']) for c in result)==8,'Actual success count changed')
    return result

def exclusive_json(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('xb') as target:target.write(canonical(value)+b'\n')

def bounded(label,argv,cap,sealed=None):
    """Persist streams and group cleanup before assertions; never retry a lane."""
    receipt=RAW/(label+'.json');out=RAW/(label+'.stdout');err=RAW/(label+'.stderr')
    require(not any(p.exists() for p in (receipt,out,err)),'Attempt already exists: '+label)
    RAW.mkdir(parents=True,exist_ok=True)
    record={'label':label,'argv':list(map(str,argv)),'cap_seconds':cap,'cwd':str(ROOT),
        'before':current(),'status':'running'}
    require(sealed is None or record['before']==sealed,'Sealed generation changed before launch')
    exclusive_json(receipt,record)
    started=time.monotonic();process=None
    try:
        process=subprocess.Popen(argv,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
        record['pid']=record['pgid']=process.pid
        try:stdout,stderr=process.communicate(timeout=cap);record['timed_out']=False
        except subprocess.TimeoutExpired:
            record['timed_out']=True
            os.killpg(process.pid,signal.SIGKILL);stdout,stderr=process.communicate(timeout=5)
        record['exit_code']=process.returncode
        out.write_bytes(stdout);err.write_bytes(stderr)
    except BaseException as error:
        record['execution_error']=type(error).__name__+': '+str(error)
        if not out.exists():out.write_bytes(b'')
        if not err.exists():err.write_bytes(b'')
    finally:
        if process is not None:record['cleanup']=OLD.cleanup_group(process)
        record['duration_seconds']=time.monotonic()-started
        record['stdout']=pin(out);record['stderr']=pin(err)
        record['after']=current()
        record['unchanged']=record['before']==record['after']
        record['status']='passed' if record.get('exit_code')==0 and not record.get('timed_out') and not record.get('execution_error') and record['unchanged'] and record.get('cleanup',{}).get('clean') else 'failed'
        write_json(receipt,record)
    require(record['status']=='passed','Attempt failed: '+str(receipt))
    return record

def rows(output):
    result={}
    for line in output.splitlines():
        id,kind,value=line.split('|',2)
        require((id,kind) not in result,'Duplicate row: '+line)
        result[id,kind]=value
    require(result['local-player-runtime','complete']=='true','No completed harness marker')
    return result
def projection(rows,prefix):
    return {(id[len(prefix):],kind):value for (id,kind),value in rows.items()
        if id==prefix or id.startswith(prefix+':')}
def exact_headers(data,before,after,skip=()):
    a=projection(data,before);b=projection(data,after)
    require(a and {k:v for k,v in a.items() if k[1] not in skip}==
        {k:v for k,v in b.items() if k[1] not in skip},'Changed retained header: '+before)

def compare_motion(data,cases):
    checked=[]
    for case in cases:
        for index,step in enumerate(case['steps']):
            if not step['ok']:continue
            id=f'{case["id"]}:{index}';before=step['before'];after=step['after']
            require(data[id+'-before','body']==OLD.body(before),(id,'actual before Body'))
            require(data[id+'-after','body']==OLD.body(after),(id,'actual after Body'))
            require(data[id+'-after','support']==OLD.support(after),(id,'actual support'))
            require(data[id+'-after','minor']==str(int(after['minor_horizontal_collision'])),(id,'actual minor'))
            require(data[id+'-after','history']==OLD.text(OLD.words(after['fall_distance_f64_bits'])),(id,'actual history'))
            fields=OLD.parse_metadata(data[id+'-after','metadata'])
            require(fields['local']==OLD.observed_local(after),(id,'actual LI cache'))
            require(fields['player']==OLD.observed_player(after),(id,'actual PT metadata'))
            require(fields['entity']==OLD.observed_entity(after),(id,'actual commonTick'))
            require(fields['sprinting']==int(after['sprinting']),(id,'actual sprint'))
            require(fields['pose']==f'{OLD.POSES[after["pose"]]},{int(after["cached_eye_height_f32_bits"],16)}[]/',(id,'actual pose/eye'))
            require(fields['controller'][:5]==[step['input']['held_mask'],*map(lambda x:int(x,16),after['rotation_f32_bits'])],(id,'held and degree state'))
            require(fields['rest']=='none{}/',(id,'unexpected facade error/tail'))
            require(data[id,'eye']==OLD.text(OLD.wide(after['eye_position_f64_bits'])),(id,'actual eye position'))
            a=data[id+'-before','clock'].split('|');b=data[id+'-after','clock'].split('|')
            require(int(b[0])==int(a[0])+1 and b[1:]==a[1:],(id,'single Core step'))
            exact_headers(data,id+'-before',id+'-after',('body','metadata','support','minor','history','clock'))
            checked.append(id)
    require(len(checked)==8,'Not all actual motions compared')
    return checked

def f32(value):return struct.unpack('>I',struct.pack('>f',value))[0]
def compare_cameras(data):
    result=[]
    for id,cell,eye in (('camera-standing',0,0x3fcf5c29),('camera-crouching',0,0x3fa28f5c),
        ('camera-positive',30000000,0x3fcf5c29),('camera-negative',-30000000,0x3fa28f5c)):
        eye64=struct.unpack('>f',struct.pack('>I',eye))[0]
        # Independently exact binary64 cell-origin subtraction, then IEEE F32.
        origin=(cell+0.25,1+eye64,0.5)
        palette=list(map(int,data[id+'-after','view'].split('|')[2].split(',')))
        expected=''.join(','.join(map(str,[f32(float(x)-origin[0]),f32(1.0-origin[1]),f32(0.0-origin[2]),state,material]))+';'
            for x,state,material in ((cell,palette[1],0),(cell+1,palette[2],1)))
        require(data[id,'snapshot'].split('|',2)[2]==expected,(id,'exact cells minus pose eye'))
        require(data[id,'snapshot']==data[id+'-cache','snapshot'],(id,'raw-cache hit'))
        require(data[id,'camera'].split('|')[:3]==['0','0','0'],(id,'zero camera origin'))
        exact_headers(data,id+'-after',id+'-cache-after')
        require(data[id+'-missing','snapshot-error'].startswith('missing-section:'),(id,'missing section refusal'))
        exact_headers(data,id+'-missing-before',id+'-missing-after')
        result.append({'id':id,'eye_f32_bits':f'{eye:08x}','expected_blocks_sha256':hashlib.sha256(expected.encode()).hexdigest()})
    return result

def compare_policies(data):
    exact_headers(data,'detour-before','detour-after')
    exact_headers(data,'detour-after','detour-checked-after')
    require(data['detour','record-admitted']=='0','Metadata tail admitted')
    exact_headers(data,'owned-before','owned-after')
    exact_headers(data,'owned-after','owned-checked-after')
    require(data['owned','record-admitted']=='0','Owning tails admitted')
    for suffix,times in ((':owned:',('321','654')),(':motion-owned:',('123','456'))):
        for i,time_word in enumerate(times):
            require(data['owned-after'+suffix+str(i),'clock'].split('|')[1]==time_word,'Child owner lost')
    exact_headers(data,'owned-tick-before','owned-tick-after',('metadata',))
    require(data['owned-tick-after','metadata']==data['owned-tick-before','metadata'].replace('retained-diagnostic','local-player-tail:0'),'Structural tick changed saved fields')
    for i in (0,1):
        require(data['owned-tick-before:owned:'+str(i),'metadata']==data['owned-tick-after:owned:'+str(i),'metadata'],'Structural tick changed child metadata')
    require(data['packet','packet-admitted']=='0','Nonfinite packet admitted')
    exact_headers(data,'packet-before','packet-after')
    exact_headers(data,'paused-before','paused-after')
    a=data['paused-after','clock'].split('|');b=data['paused-explicit-after','clock'].split('|')
    require(int(b[0])==int(a[0])+1 and b[1:]==a[1:],'Explicit paused step cadence')
    require(data['restore','packet-admitted']=='1','Canonical current record refused')
    exact_headers(data,'restore-before','restore-after',('metadata',))
    before=OLD.parse_metadata(data['restore-before','metadata']);after=OLD.parse_metadata(data['restore-after','metadata'])
    require(before['controller'][0]==1 and after['controller'][0]==0,'Physical buttons not reset')
    require({k:v for k,v in before.items() if k!='controller'}=={k:v for k,v in after.items() if k!='controller'},'Durable restore metadata changed')
    require(before['controller'][1:]==after['controller'][1:],'Restore changed caller options/degree fields')
    for id in ('stage-header','stage-body','stage-clock'):
        require(data[id,'guard-error']=='apply-provider-authority-drift',(id,'guard failure'))
        exact_headers(data,id+'-before',id+'-after')
    return {'metadata_tail_refused':True,'four_owned_children_retained':True,'atomic_packet':True,
        'paused_realtime_noop':True,'explicit_paused_step':True,'restore_device_reset_only':True,
        'pre_provider_guard_refusals':3}

def verify_preparation():
    value=json.loads(PREP.read_text());require(value['status']=='ordinary-prepared-native-kernel-pending','Unprepared generation')
    require(value['pins']==current(),'Prepared source/tool/reference changed')
    require(value['selected_cases_sha256']==sha(load_actual()),'Actual observations changed')
    return value

def prepare():
    require(not PREP.exists(),'Preparation already exists; preserve the old generation')
    sealed=current();actual=load_actual()
    receipts=[bounded('ordinary-'+name,[str(BEND),str(path),'--check-only'],30,sealed)
        for name,path in (('source',SOURCE),('harness',HARNESS))]
    value={'status':'ordinary-prepared-native-kernel-pending','pins':sealed,
        'selected_cases_sha256':sha(actual),'actual_motion_rows':8,'camera_origins':4,'camera_missing_owner_cases':4,
        'stage_guard_cases':3,'source_laws':2,'ordinary':[pin(RAW/(r['label']+'.json')) for r in receipts],
        'native_build_cap_seconds':600,'native_runtime_cap_seconds':120,'kernel_cap_seconds':60,
        'scope':'Saved-client facade; declared default attributes, finite checked full cubes, neutral lifecycle and CheckedNotRequired only.'}
    exclusive_json(PREP,value);print(json.dumps({'status':value['status'],'closure_entries':len(sealed['generation'])}))

def native():
    prep=verify_preparation();require(not NATIVE.exists(),'Native attempt already exists')
    report=RAW/'native-build-full.json'
    built=bounded('native-build',[sys.executable,str(ROOT/'tools/build_native.py'),str(HARNESS),'-o',str(BINARY),
        '--cache-dir',str(RAW/'cache'),'--report',str(report)],600,prep['pins'])
    run=bounded('native-run',[str(BINARY),'--gpu','off','--threads','1',str(TABLE)],120,prep['pins'])
    evidence={'status':'comparison-pending','preparation':pin(PREP),'build_receipt':pin(RAW/'native-build.json'),
        'run_receipt':pin(RAW/'native-run.json'),'build_manifest':pin(report),'binary':pin(BINARY)}
    exclusive_json(NATIVE,evidence)
    try:
        data=rows((RAW/'native-run.stdout').read_text())
        evidence.update(actual=compare_motion(data,load_actual()),camera=compare_cameras(data),policies=compare_policies(data),status='passed')
    except BaseException as error:
        evidence.update(status='failed',comparison_error=type(error).__name__+': '+str(error));write_json(NATIVE,evidence);raise
    write_json(NATIVE,evidence);print(json.dumps({'status':'passed','actual_motion_rows':8}))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    action=parser.add_mutually_exclusive_group()
    action.add_argument('--prepare',action='store_true');action.add_argument('--native',action='store_true');action.add_argument('--kernel',action='store_true')
    args=parser.parse_args()
    if args.prepare:return prepare()
    if args.native:return native()
    prep=verify_preparation()
    if args.kernel:
        require(NATIVE.exists() and json.loads(NATIVE.read_text())['status']=='passed','Native comparison must pass first')
        receipt=bounded('kernel',[str(BEND),str(HARNESS),'--verdict'],60,prep['pins'])
        exclusive_json(ROOT/'evidence/local-player-runtime-kernel.json',{'status':receipt['status'],'raw_receipt':pin(RAW/'kernel.json')})
    else:print(json.dumps({'status':prep['status'],'actual_motion_rows':8,'heavy_execution':'not requested'}))

if __name__=='__main__':
    try:main()
    except (Exception,KeyboardInterrupt) as error:
        print(type(error).__name__+': '+str(error),file=sys.stderr);raise SystemExit(1)
