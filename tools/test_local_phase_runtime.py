#!/usr/bin/env python3
"""Prepare/run bounded phase integration and explicitly separate project policies.

Python serializes independent raw observations and compares returned fields. It
does not implement control, travel, collision, pose, history or clock behavior.
The default action verifies sealed preparation; native/kernel actions are explicit.
"""
from __future__ import annotations
import argparse, hashlib, json, os, signal, subprocess, sys, time
from pathlib import Path
import reference_local_phase_runtime_probe as RP
from reference_inventory import ROOT, canonical, fingerprint, write_json
from build_native import Snapshot, source_graph

BEND=Path('/Users/chuah/.bend/bin/bend')
SOURCE=ROOT/'src/local_phase_runtime.bend'
HARNESS=ROOT/'tests/local_phase_runtime.bend'
REFERENCE=ROOT/'reference/local_phase_runtime.json'
TABLE=ROOT/'generated/reference_mth_sin.f32'
RAW=ROOT/'build/local-phase-runtime/verification'
BINARY=ROOT/'build/local-phase-runtime/tests'
POSES={'STANDING':0,'CROUCHING':5,'SWIMMING':3}

def sha(value):return hashlib.sha256(canonical(value)).hexdigest()
def pin(path):return {'path':str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path),**fingerprint(path)}
def generation():
    snapshot=Snapshot()
    source_graph(HARNESS,(BEND.resolve().parent.parent/'bend2/base.bend').resolve(),dict(os.environ),snapshot)
    return {v['path']:v['sha256'] for v in snapshot.manifest()}
def tool_pins():
    paths=['tools/test_local_phase_runtime.py','tools/reference_local_phase_runtime_probe.py',
        'tools/reference_player_tick_phases_probe.py','tools/reference_local_input_probe.py',
        'tools/reference_inventory.py','tools/reference_model_probe.py','tools/build_native.py']
    return {p:pin(ROOT/p) for p in paths}

PREPARATION=ROOT/'evidence/local-phase-runtime-preparation.json'
HOST_SEAL=ROOT/'evidence/local-phase-runtime-host-adoption.json'
READY_PREPARATION_SHA256='e88ec198cb25a5510c11699b5be305cc86debba212194f9e58421fb46cb333d9'
READY_GENERATION_SHA256='aba739dba0cf69dc1dc6d7dcf4674024ad8670ce512ec71f3e6cff11f2bdc5f6'
HOST_GENERATION=2

class HostError(RuntimeError):pass

def require(condition,message):
    if not condition:raise HostError(message)

def verify_preparation():
    """Read-only verification of the immutable ready proof and host bridge."""
    require(PREPARATION.is_file(),'Sealed ready preparation is missing')
    require(pin(PREPARATION)['sha256']==READY_PREPARATION_SHA256,'Sealed ready preparation changed')
    prepared=json.loads(PREPARATION.read_text())
    require(prepared['status']=='ordinary-prepared-native-kernel-pending','Ready preparation is not successful')
    require(len(prepared['generation'])==80 and sha(prepared['generation'])==READY_GENERATION_SHA256,'Ready 80-entry closure seal changed')
    require(prepared['generation']==generation(),'Frozen Bend/Base/effect closure changed')
    for label,path in [('source',SOURCE),('harness',HARNESS),('reference',REFERENCE),('table',TABLE)]:
        require(prepared[label]==pin(path),'Frozen '+label+' changed')
    require(all(row['status']=='passed' for row in prepared['ordinary']),'Ready ordinary receipts are not successful')
    require(fingerprint(BEND)==prepared['ordinary'][0]['compiler'],'Prepared compiler binary changed')
    current_tools=tool_pins()
    for path,value in prepared['tools'].items():
        if path!='tools/test_local_phase_runtime.py':
            require(current_tools[path]==value,'Frozen producer/helper changed: '+path)
    require(HOST_SEAL.is_file(),'Separate host-adoption seal is missing')
    seal=json.loads(HOST_SEAL.read_text())
    require(seal['host_generation']==HOST_GENERATION and seal['status']=='host-adopted-native-kernel-pending','Host adoption is not sealed')
    require(seal['ready_preparation']==pin(PREPARATION),'Host bridge points at a different ready preparation')
    require(seal['ready_generation_sha256']==READY_GENERATION_SHA256,'Host bridge points at a different closure')
    require(seal['tools']==current_tools,'Host runner/tool generation changed')
    require(seal['docs']==pin(ROOT/'docs/LOCAL_PHASE_RUNTIME.md'),'Host adoption documentation changed')
    return {'prepared':prepared,'preparation':pin(PREPARATION),'host_seal':pin(HOST_SEAL),
        'generation':prepared['generation'],'tools':current_tools,'reference':pin(REFERENCE),
        'table':pin(TABLE),'compiler':fingerprint(BEND)}

def attempt_paths(kind):
    return [RAW/(kind+'.stdout'),RAW/(kind+'.stderr'),ROOT/f'evidence/local-phase-runtime-{kind}.json']

def reserve_mode(mode,paths):
    """Reject the entire mode before launch, then exclusively claim its lineage."""
    claim=RAW/'claims'/(mode+'.json')
    occupied=[str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)
        for path in [claim,*paths] if path.exists()]
    require(not occupied,'Refusing old attempt overwrite: '+', '.join(occupied))
    claim.parent.mkdir(parents=True,exist_ok=True)
    with claim.open('x') as output:
        json.dump({'mode':mode,'pid':os.getpid(),'host_generation':HOST_GENERATION,
            'reserved_outputs':[str(p) for p in paths]},output,indent=2,sort_keys=True)
        output.write('\n')
    return pin(claim)

def group_members(pgid):
    result=subprocess.run(['ps','-axo','pid=,pgid=,stat=,ppid='],capture_output=True,text=True,timeout=1)
    require(result.returncode==0,'Unable to enumerate owned process group')
    members=[]
    for line in result.stdout.splitlines():
        fields=line.split()
        if len(fields)==4 and int(fields[1])==pgid:
            members.append({'pid':int(fields[0]),'pgid':pgid,'state':fields[2],'parent':int(fields[3])})
    return sorted(members,key=lambda row:row['pid'])

def reap_group_children(pgid):
    reaped=[]
    while True:
        try:pid,status=os.waitpid(-pgid,os.WNOHANG)
        except ChildProcessError:break
        if pid==0:break
        reaped.append({'pid':pid,'wait_status':status})
    return reaped

def cleanup_group(process,cap=5):
    """Kill even after leader exit; wait our leader and reap reachable children.

    Orphan descendants on macOS are host-reaped. A passed cleanup additionally
    requires observing an empty group, including absence of zombie members.
    """
    record={'pgid':process.pid,'cap_seconds':cap,'leader_reaped':False,
        'members_before':None,'members_after':None,'reaped_children':[],'errors':[]}
    start=time.monotonic();process.poll()
    try:record['members_before']=group_members(process.pid)
    except Exception as error:record['errors'].append(type(error).__name__+': '+str(error))
    try:os.killpg(process.pid,signal.SIGKILL);record['kill_sent']=True
    except ProcessLookupError:record['kill_sent']=False
    except Exception as error:record['errors'].append(type(error).__name__+': '+str(error))
    try:
        process.wait(timeout=max(0.01,cap-(time.monotonic()-start)))
        record['leader_reaped']=True
    except Exception as error:record['errors'].append(type(error).__name__+': '+str(error))
    while time.monotonic()-start<cap:
        try:
            record['reaped_children']+=reap_group_children(process.pid)
            record['members_after']=group_members(process.pid)
        except Exception as error:
            record['errors'].append(type(error).__name__+': '+str(error));break
        if not record['members_after']:break
        try:os.killpg(process.pid,signal.SIGKILL)
        except ProcessLookupError:pass
        except Exception as error:record['errors'].append(type(error).__name__+': '+str(error));break
        time.sleep(0.02)
    record['seconds']=round(time.monotonic()-start,6)
    record['clean']=record['leader_reaped'] and record['members_after']==[] and not record['errors']
    return record

def receipt_exit(receipt):
    return 0 if receipt['status']=='passed' else 2 if receipt['status']=='inconclusive' else 1

def protected_cleanup(process):
    saved={}
    for number in (signal.SIGINT,signal.SIGTERM):
        saved[number]=signal.getsignal(number);signal.signal(number,signal.SIG_IGN)
    try:return cleanup_group(process)
    finally:
        for number,handler in saved.items():signal.signal(number,handler)

def cancelled_signal(number,frame):
    raise KeyboardInterrupt('Signal '+str(number))

def bounded(kind,command,cap,expected,claim):
    """Persist execution first, then annotate drift without losing the attempt."""
    stdout,stderr,path=attempt_paths(kind)
    require(not any(p.exists() for p in (stdout,stderr,path)),'Attempt outputs already exist: '+kind)
    RAW.mkdir(parents=True,exist_ok=True)
    receipt={'kind':kind,'status':'running','command':list(command),'argv':list(command),
        'cap_seconds':cap,'host_generation':HOST_GENERATION,'claim':claim,
        'sealed_preparation':expected['preparation'],'sealed_host_adoption':expected['host_seal'],
        'generation':expected['generation'],'generation_sha256':sha(expected['generation']),
        'tools':expected['tools'],'reference':expected['reference'],'table':expected['table'],
        'compiler':expected['compiler'],'exit_code':None,'timed_out':False,'interrupted':False}
    # Exclusive stream creation plus the mode claim forbids old-attempt reuse.
    start=time.monotonic();process=None;execution_error=None;cleanup=None
    with stdout.open('xb') as out,stderr.open('xb') as err:
        receipt['stdout']=pin(stdout);receipt['stderr']=pin(stderr)
        with path.open('x') as output:
            json.dump(receipt,output,indent=2,sort_keys=True);output.write('\n')
        try:
            previous=signal.pthread_sigmask(signal.SIG_BLOCK,{signal.SIGINT,signal.SIGTERM})
            try:
                process=subprocess.Popen(command,cwd=ROOT,stdout=out,stderr=err,start_new_session=True)
                receipt['pid']=process.pid
            finally:signal.pthread_sigmask(signal.SIG_SETMASK,previous)
            process.wait(timeout=cap)
        except subprocess.TimeoutExpired:receipt['timed_out']=True
        except BaseException as error:
            execution_error=type(error).__name__+': '+str(error)
            receipt['interrupted']=isinstance(error,(KeyboardInterrupt,SystemExit))
        finally:
            if process is not None:
                cleanup=protected_cleanup(process)
                receipt['exit_code']=process.returncode
            out.flush();err.flush()
    receipt['seconds']=round(time.monotonic()-start,6)
    receipt['stdout']=pin(stdout);receipt['stderr']=pin(stderr)
    receipt['cleanup']=cleanup;receipt['execution_error']=execution_error
    unexpected_children=bool(cleanup and cleanup['members_before'] and not receipt['timed_out'] and not execution_error)
    receipt['unexpected_surviving_group_members']=unexpected_children
    receipt['status']=('inconclusive' if receipt['timed_out'] or receipt['interrupted'] or unexpected_children
        or (cleanup is not None and not cleanup['clean']) else
        'failed' if execution_error or receipt['exit_code']!=0 else 'passed')
    receipt['execution_status']=receipt['status']
    receipt['validation_status']='pending'
    # Persist complete argv/streams/execution BEFORE any post-run drift reads.
    write_json(path,receipt)
    try:
        current_generation=generation();current_tools=tool_pins()
        checks={'generation_unchanged':expected['generation']==current_generation,
            'tools_unchanged':expected['tools']==current_tools,'reference_unchanged':expected['reference']==pin(REFERENCE),
            'table_unchanged':expected['table']==pin(TABLE),'compiler_unchanged':expected['compiler']==fingerprint(BEND),
            'preparation_unchanged':expected['preparation']==pin(PREPARATION),
            'host_seal_unchanged':expected['host_seal']==pin(HOST_SEAL)}
        receipt.update(checks)
        receipt['validation_status']='passed' if all(checks.values()) else 'failed'
        if receipt['validation_status']=='failed':
            receipt['status']='failed';receipt['drift']=[key for key,value in checks.items() if not value]
    except BaseException as error:
        receipt['status']='failed';receipt['validation_status']='failed'
        receipt['validation_error']=type(error).__name__+': '+str(error)
    write_json(path,receipt)
    if receipt['status']!='passed':
        print('Attempt '+kind+': '+receipt['status']+'; receipt '+str(path.relative_to(ROOT)),file=sys.stderr)
    return receipt

def words(raw):
    n=int(raw,16);return [n>>32,n&0xffffffff]
def wide(values):return [v for raw in values for v in words(raw)]
def text(values):return '|'.join(str(v&0xffffffff) for v in values)
def mask(keys):return sum(1<<i for i,b in enumerate(keys) if b)
def body(state):
    return text(wide(state['position']+state['box']+state['velocity'])+
        [int(state['width_f32_bits'],16),int(state['height_f32_bits'],16),*map(int,state['body_flags'])])
def support(state):
    value=state['support'];main='none' if value is None else ','.join(str(v&0xffffffff) for v in value)
    return main+'|'+str(int(state['on_ground_no_blocks']))
def parse_metadata(value):
    local,player,sprint,pose,controller,entity,remaining=value.split(';',6)
    assert remaining.endswith('}/'),remaining
    return {'local':list(map(int,local.split('|'))),'player':list(map(int,player.split('|'))),
        'sprinting':int(sprint),'pose':pose,'controller':list(map(int,controller.split('|'))),
        'entity':list(map(int,entity.split('|'))),'rest':remaining}
def observed_local(state):
    return [mask(state['key_presses']),*map(lambda v:int(v,16),state['move_vector_f32_bits']),
        state['sprint_trigger_time']&0xffffffff,int(state['crouching']),*map(lambda v:int(v,16),state['bob_f32_bits'])]
def observed_player(state):
    return [*map(lambda v:int(v,16),state['input_f32_bits']),int(state['jumping']),state['jump_delay']&0xffffffff,
        state['jump_trigger']&0xffffffff,int(state['needs_sync']),int(state['stored_speed_f32_bits'],16),int(state['head_yaw_f32_bits'],16)]
def observed_entity(state):
    return wide(state['old_position']+state['position_old'])+[state['invulnerable_time_u32'],state['tick_count_u32']]

def lines(output):
    rows={};queries={}
    for row in output.splitlines():
        id,kind,value=row.split('|',2)
        if kind in ('early','late'):queries.setdefault((id,kind),[]).append(value)
        else:
            assert (id,kind) not in rows,(id,kind)
            rows[id,kind]=value
    assert rows['local-phase-runtime','complete']=='true'
    return rows,queries

def compare_actual(case,index,step,rows,queries):
    id=f'{case["id"]}:{index}';after=step['after'];before=step['before']
    assert (id,'error') not in rows,(id,rows.get((id,'error')))
    assert rows[id+'-before','body']==body(before),id
    assert rows[id+'-after','body']==body(after),id
    assert rows[id+'-after','support']==support(after),id
    assert rows[id+'-after','minor']==str(int(after['minor_horizontal_collision'])),id
    assert rows[id+'-after','history']==text(words(after['fall_distance_f64_bits'])),id
    metadata=parse_metadata(rows[id+'-after','metadata'])
    assert metadata['local']==observed_local(after),(id,'LI',metadata['local'],observed_local(after))
    assert metadata['player']==observed_player(after),(id,'player',metadata['player'],observed_player(after))
    assert metadata['sprinting']==int(after['sprinting']),id
    assert metadata['pose']==f'{POSES[after["pose"]]},{int(after["cached_eye_height_f32_bits"],16)}[]/',id
    assert metadata['controller'][:5]==[step['input']['held_mask'],*map(lambda v:int(v,16),after['rotation_f32_bits'])],id
    assert metadata['controller'][5:]==[0]*8+[1,0x3fe00000,0,0,0,0,0],(id,'complete controller')
    assert metadata['entity']==observed_entity(after),(id,'ECT')
    assert metadata['rest']=='none{}/',id
    assert rows[id,'eye']==text(wide(after['eye_position_f64_bits'])),id
    update=''.join(str(int(v))+',' for v in step['projection']['sprint_updates'])
    flags=rows[id,'ok'].split('|')
    assert flags[0]==update,(id,'ordered setters')
    observed_jump=int(any(p['phase']=='jump_entry' for p in step['phases']))
    assert flags[1:]==[str(observed_jump)]*2,(id,'actual neutral jump entry/result')
    for phase in ('early','late'):
        expected=[text([i,POSES[q['pose']],*wide(q['box']),int(q['clear'])])
            for i,q in enumerate(step['projection'][phase+'_fits'])]
        assert queries.get((id,phase),[])==expected,(id,phase)
    a=rows[id+'-before','clock'].split('|');b=rows[id+'-after','clock'].split('|')
    assert int(b[0])==int(a[0])+int(case['operation']=='level_tick') and b[1:]==a[1:],(id,'separate Core clock',a,b)
    for kind in ('sections','queue','view','state-tail','motion-tail','table-sample'):
        assert rows[id+'-before',kind]==rows[id+'-after',kind],(id,kind)
    return {'id':id,'early_queries':len(step['projection']['early_fits']),'late_queries':len(step['projection']['late_fits'])}

ERRORS={
 'policy:direct-control':'control-budget','policy:scheduled-control':'control-budget',
 'policy:direct-sprint-context':'input-sprint-context','policy:scheduled-sprint-context':'input-sprint-context',
 'policy:direct-rotation':'rotation','policy:direct-late':'late-pose','policy:scheduled-late':'late-pose',
 'policy:lifecycle':'lifecycle:77','policy:common':'entity','policy:request-tail':'request-tail',
 'policy:control-mode':'input','policy:abilities':'input','policy:entities':'control-world:edge-entities-unresolved',
 'policy:move-budget':'travel','policy:metadata-tail':'state-tail:2','policy:pose-tail':'state-tail:3',
 'policy:required-ray':'travel','policy:crawl':'unsupported-stable-pose','policy:due-crawl':'unsupported-stable-pose',
 'policy:missing-section':'control-world:',
 'policy:owned-tail':'state-tail:0','policy:motion-owned-tail':'state-tail:1'}
DIRECT={'policy:direct-control','policy:direct-sprint-context','policy:direct-rotation','policy:direct-late'}
STRUCTURAL={'policy:request-tail','policy:metadata-tail','policy:pose-tail','policy:owned-tail','policy:motion-owned-tail'}

def child_reports(rows,prefix):
    return {(id[len(prefix):],kind):value for (id,kind),value in rows.items()
        if id.startswith(prefix+':owned:') or id.startswith(prefix+':motion-owned:')}

def compare_policy(id,rows):
    before=id+'-before';after=id+'-after'
    if id in ERRORS:
        assert rows[id,'error'].startswith(ERRORS[id]),(id,rows.get((id,'error')))
        for kind in ('body','support','minor','history','view','state-tail','motion-tail','table-sample'):
            assert rows[before,kind]==rows[after,kind],(id,'complete anchor',kind)
        original=parse_metadata(rows[before,'metadata']);returned=parse_metadata(rows[after,'metadata'])
        no_common=id in DIRECT|STRUCTURAL|{'policy:common'}
        if no_common:
            assert rows[before,'metadata']==rows[after,'metadata'],(id,'original complete metadata')
        else:
            for key in ('local','player','sprinting','pose','rest'):
                assert original[key]==returned[key],(id,'post-common metadata',key)
            assert original['controller'][:3]==returned['controller'][:3] and original['controller'][5:]==returned['controller'][5:],id
            assert returned['controller'][3:5]==original['controller'][1:3],(id,'retained common angle snapshot')
            feet=list(map(int,rows[before,'body'].split('|')[:6]))
            assert returned['entity']==feet+feet+[2,0],(id,'both old triples signed countdown count wrap')
        a=rows[before,'clock'].split('|');b=rows[after,'clock'].split('|')
        increment=0 if id in DIRECT|STRUCTURAL else 1
        assert int(b[0])==int(a[0])+increment and b[1:4]==a[1:4],(id,'Core transaction anchor')
        if id=='policy:due-crawl':
            assert rows[before,'sections']!=rows[after,'sections'],id
            assert int(b[4])==int(a[4])+1 and int(b[5])==int(a[5])-1 and int(b[6])==int(a[6])+1,id
        else:
            assert b[4:]==a[4:] and rows[before,'sections']==rows[after,'sections'] and rows[before,'queue']==rows[after,'queue'],id
    elif id in ('policy:paused','policy:packet-failure','policy:query','policy:eye'):
        for kind in ('body','support','minor','history','metadata','clock','queue','sections','view','state-tail','motion-tail','table-sample'):
            assert rows[before,kind]==rows[after,kind],(id,'read/input/pause retention',kind)
        if id=='policy:paused':assert rows[id,'paused']=='true'
        if id=='policy:packet-failure':assert rows[id,'packet-error']=='controller'
    else:
        unchanged=('body','support','minor','history','clock','queue','sections','state-tail','motion-tail','table-sample')
        if id=='policy:release':unchanged+=('view',)
        for kind in unchanged:
            assert rows[before,kind]==rows[after,kind],(id,'packet/release cadence',kind)
        a=parse_metadata(rows[before,'metadata']);b=parse_metadata(rows[after,'metadata'])
        for key in ('local','player','sprinting','pose','entity','rest'):assert a[key]==b[key],(id,key)
        assert a['controller'][-6:]==b['controller'][-6:],(id,'controller options')
        if id=='policy:release':
            assert b['controller'][0]==0 and b['controller'][1:9]==a['controller'][1:9] and b['controller'][9:14]==[0,0,0,0,1],id
        else:assert rows[id,'packet-done']=='true' and b['controller'][0]&1,id
    # Reuse the exact returned owner in a read-cache query without clock/sample.
    reused=id+':query-reuse'
    for kind in ('body','support','minor','history','metadata','clock','queue','sections','state-tail','motion-tail','table-sample'):
        assert rows[after,kind]==rows[reused+'-before',kind],(id,'exact returned owner passed to query',kind)
        assert rows[reused+'-before',kind]==rows[reused+'-after',kind],(id,'returned owner reuse',kind)
    assert rows[reused,'queried']=='true',id
    child_before=child_reports(rows,before);child_after=child_reports(rows,after)
    assert child_before==child_after,(id,'complete owned child reports')
    assert child_reports(rows,reused+'-before')==child_reports(rows,reused+'-after')==child_after,(id,'owned children reused')
    if id in ('policy:owned-tail','policy:motion-owned-tail'):
        suffix=':owned:' if id=='policy:owned-tail' else ':motion-owned:'
        assert child_before[suffix+'0','clock'].split('|')[1]=='321',id
        assert child_before[suffix+'1','clock'].split('|')[1]=='654',id
        required=('body','support','minor','history','clock','queue','sections','view')
        if id=='policy:owned-tail':required+=('metadata','table-sample','state-tail','motion-tail')
        for index in (0,1):assert all((suffix+str(index),kind) in child_before for kind in required),id
    return {'id':id,'entry_clock_policy':'direct' if id in DIRECT else 'structural' if id in STRUCTURAL else 'scheduled/read',
        'returned_owner_reused':True}

# Read-only adapter for the final consumer executable's explicit phase-cases
# branch. It reuses every frozen comparator above; it never launches/emits code
# or grants admission to an executable. The consumer runner owns its full seal,
# bounded execution, stdout/stderr receipts and immediate failure propagation.
ADDITIVE_SOURCE_SHA256='8daf7e2f2fdc32d07f9250c4815883568ffd6d020bbbc8c5f94e18d198c481f3'
FROZEN_COMPARISON_SHA256='1b03890f13a59c6e098bb931fff6b7b7c6fb0259e1f4878f4f4d1d61cc1183e7'
_ADAPTER_IMPORT_PIN=pin(Path(__file__))

def phase_contract():
    """Pin the unchanged phase corpus and its additive source, without running."""
    require(sys.flags.optimize==0,'Frozen comparator assertions are disabled')
    require(pin(Path(__file__))==_ADAPTER_IMPORT_PIN,'Imported phase adapter changed')
    require(pin(PREPARATION)['sha256']==READY_PREPARATION_SHA256,'Original phase preparation changed')
    prepared=json.loads(PREPARATION.read_text())
    require(prepared['status']=='ordinary-prepared-native-kernel-pending','Original phase preparation failed')
    require(len(prepared['generation'])==80 and sha(prepared['generation'])==READY_GENERATION_SHA256,
        'Original phase 80-entry manifest changed')
    current={}
    for name,value in prepared['generation'].items():
        expected=ADDITIVE_SOURCE_SHA256 if Path(name)==SOURCE else value
        observed=fingerprint(Path(name))['sha256']
        require(observed==expected,'Phase dependency changed: '+name)
        current[name]=observed
    require(pin(SOURCE)['sha256']==ADDITIVE_SOURCE_SHA256,'Additive phase source changed')
    for label,path in [('harness',HARNESS),('reference',REFERENCE),('table',TABLE)]:
        require(pin(path)==prepared[label],'Frozen phase '+label+' changed')
    require(fingerprint(BEND)==prepared['ordinary'][0]['compiler'],'Phase compiler changed')
    producers={}
    for name,value in prepared['tools'].items():
        if name!='tools/test_local_phase_runtime.py':
            require(pin(ROOT/name)==value,'Frozen phase producer/helper changed: '+name)
            producers[name]=value
    contents=Path(__file__).read_text()
    comparison=contents[contents.index('def words(raw):'):contents.index('# Read-only adapter for the final consumer executable')]
    require(hashlib.sha256(comparison.encode()).hexdigest()==FROZEN_COMPARISON_SHA256,
        'Frozen phase comparator span changed')
    return {'status':'phase-comparison-contract-verified','original_preparation':pin(PREPARATION),
        'original_generation_sha256':READY_GENERATION_SHA256,'phase_generation':current,
        'source':pin(SOURCE),'harness':pin(HARNESS),'reference':pin(REFERENCE),'table':pin(TABLE),
        'compiler':fingerprint(BEND),'producers':producers,'adapter':_ADAPTER_IMPORT_PIN,
        'comparison_sha256':FROZEN_COMPARISON_SHA256,
        'scope':'Read-only frozen corpus adapter; executable admission belongs to the sealed consumer runner.'}

def compare_output(output):
    """Immediately compare captured phase-cases stdout; raise on any mismatch."""
    contract=phase_contract()
    data=json.loads(REFERENCE.read_text());RP.integrity(data)
    rows,queries=lines(output)
    actual=[compare_actual(case,index,step,rows,queries) for supplied in data['cases']
        for case in [RP.decode(supplied)] for index,step in enumerate(case['steps']) if step['ok']]
    policies=[compare_policy(id,rows) for id in [*ERRORS,'policy:paused','policy:release',
        'policy:packet-failure','policy:packet-success','policy:query','policy:eye']]
    require(phase_contract()==contract,'Phase comparison inputs changed during comparison')
    return {'status':'passed','contract':contract,'actual':actual,'policies':policies,
        'stdout_sha256':hashlib.sha256(output.encode()).hexdigest(),
        'scope':'Unchanged raw Java phase observations and declared project-policy comparisons; no executable launch.'}

def frozen_summary(expected):
    prepared=expected['prepared']
    return {'status':'sealed-preparation-verified-native-kernel-pending','host_generation':HOST_GENERATION,
        'actual_successful_steps':prepared['actual_successful_steps'],
        'actual_fixture_service_failures':prepared['actual_fixture_service_failures'],
        'policy_scenarios':prepared['policy_scenarios'],'generation_count':prepared['generation_count'],
        'production_laws':prepared['production_laws'],'sealed_preparation':expected['preparation'],
        'sealed_host_adoption':expected['host_seal']}

def build_native(expected):
    full=RAW/'native-build-full.json';cache=ROOT/'build/local-phase-runtime/cache'
    claim=reserve_mode('build',[*attempt_paths('build'),BINARY,cache,full])
    receipt=bounded('build',[sys.executable,str(ROOT/'tools/build_native.py'),str(HARNESS),'-o',str(BINARY),
        '--cache-dir',str(cache),'--report',str(full)],600,expected,claim)
    if receipt['status']=='passed':
        try:
            receipt['binary']=pin(BINARY);receipt['full_build_receipt']=pin(full)
        except BaseException as error:
            receipt['status']='failed';receipt['artifact_error']=type(error).__name__+': '+str(error)
        write_json(ROOT/'evidence/local-phase-runtime-build.json',receipt)
    print(json.dumps({'status':receipt['status'],'kind':'native build'}))
    return receipt_exit(receipt)

def native(data,expected):
    build_path=ROOT/'evidence/local-phase-runtime-build.json'
    build=json.loads(build_path.read_text())
    require(build['status']=='passed','Retained build is not passed')
    for label in ('generation','tools','reference','table','compiler'):
        require(build[label]==expected[label],'Retained build '+label+' differs from sealed preparation')
    require(build['sealed_preparation']==expected['preparation'] and build['sealed_host_adoption']==expected['host_seal'],
        'Retained build belongs to a different sealed generation')
    require(build['binary']==pin(BINARY),'Retained binary changed')
    require(build['full_build_receipt']==pin(RAW/'native-build-full.json'),'Retained full build receipt changed')
    aggregate=ROOT/'evidence/local-phase-runtime-native.json'
    claim=reserve_mode('native',[*attempt_paths('native-first'),*attempt_paths('native-rerun'),aggregate])
    summary={'status':'running','generation':expected['generation'],'tools':expected['tools'],
        'reference':expected['reference'],'table':expected['table'],'binary':pin(BINARY),
        'sealed_preparation':expected['preparation'],'sealed_host_adoption':expected['host_seal'],
        'build_receipt':pin(build_path),'host_generation':HOST_GENERATION,'claim':claim,'runs':[]}
    with aggregate.open('x') as output:
        json.dump(summary,output,indent=2,sort_keys=True);output.write('\n')
    prior=None
    for label in ('first','rerun'):
        receipt=bounded('native-'+label,[str(BINARY),'--gpu','off','--threads','1',str(TABLE)],120,expected,claim)
        summary['runs'].append({'execution_receipt':pin(ROOT/f'evidence/local-phase-runtime-native-{label}.json')})
        if receipt['status']!='passed':
            summary['status']=receipt['status'];write_json(aggregate,summary)
            print(json.dumps({'status':summary['status'],'runs':len(summary['runs'])}));return receipt_exit(summary)
        try:
            output=(ROOT/receipt['stdout']['path']).read_text();rows,queries=lines(output)
            actual=[compare_actual(case,i,step,rows,queries) for supplied in data['cases']
                for case in [RP.decode(supplied)] for i,step in enumerate(case['steps']) if step['ok']]
            policies=[compare_policy(id,rows) for id in [*ERRORS,'policy:paused','policy:release',
                'policy:packet-failure','policy:packet-success','policy:query','policy:eye']]
            require(prior is None or output==prior,'Fresh native rerun differs')
            prior=output;summary['runs'][-1].update(actual=actual,policies=policies,comparison_status='passed')
        except BaseException as error:
            summary['status']='failed';summary['runs'][-1].update(comparison_status='failed',
                comparison_error=type(error).__name__+': '+str(error))
            write_json(aggregate,summary)
            print(json.dumps({'status':summary['status'],'runs':len(summary['runs'])}));return 1
        write_json(aggregate,summary)
    summary.update(status='passed',exact_rerun_equal=True,
        scope='Frozen bounded field/query projection and separately declared project transaction/cadence policies.')
    write_json(aggregate,summary)
    print(json.dumps({'status':summary['status'],'runs':len(summary['runs'])}));return 0

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    action=parser.add_mutually_exclusive_group()
    action.add_argument('--prepare',action='store_true');action.add_argument('--build',action='store_true')
    action.add_argument('--native-only',action='store_true');action.add_argument('--kernel',action='store_true')
    args=parser.parse_args();expected=verify_preparation()
    data=json.loads(REFERENCE.read_text());RP.integrity(data)
    if args.native_only:return native(data,expected)
    if args.kernel:
        claim=reserve_mode('kernel',attempt_paths('kernel'))
        receipt=bounded('kernel',[str(BEND),str(HARNESS),'--verdict'],60,expected,claim)
        print(json.dumps({'status':receipt['status'],'kind':'full-import kernel'}));return receipt_exit(receipt)
    if args.build:return build_native(expected)
    # The ordinary proofs are already sealed. Host adoption never regenerates
    # them, mutates the ready proof, or overwrites its original attempt receipts.
    print(json.dumps(frozen_summary(expected),indent=2));return 0

if __name__=='__main__':
    signal.signal(signal.SIGTERM,cancelled_signal)
    try:code=main()
    except (Exception,KeyboardInterrupt) as error:
        print(type(error).__name__+': '+str(error),file=sys.stderr);code=1
    raise SystemExit(code)
