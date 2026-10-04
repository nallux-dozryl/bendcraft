#!/usr/bin/env python3
"""Direct actual reset-ray comparison; host code computes no DDA or game result."""
from __future__ import annotations
import argparse,copy,hashlib,json,os,signal,struct,subprocess,sys,time
from pathlib import Path
from build_native import Snapshot,source_graph
from reference_inventory import ROOT,canonical,fingerprint,write_json
BEND=Path('/Users/chuah/.bend/bin/bend')
SOURCE=ROOT/'src/fall_reset_world.bend'
HARNESS=ROOT/'tests/fall_reset_world.bend'
BINARY=ROOT/'build/fall-reset-world-tests'
WORK=ROOT/'build/fall-reset-world-verification'
FIXTURE=ROOT/'reference/fall_reset_world.json'
# No Tables owner is needed by the adapter; TABLE is only a pinned dependency
# inherited by the closed module graph, not a native argument or physics input.
TABLE=ROOT/'generated/reference_mth_sin.f32'
NAMES=['minecraft:air','minecraft:stone','minecraft:dirt','minecraft:oak_planks','minecraft:glass','minecraft:water','minecraft:cobweb','minecraft:sweet_berry_bush','minecraft:ladder','minecraft:end_portal','minecraft:end_gateway','minecraft:nether_portal','minecraft:lava']
INTERIOR=[-64.,-64.,-64.,64.,64.,64.]
def digest(value):return hashlib.sha256(canonical(value)).hexdigest()
def pin(path):return {'path':str(path.relative_to(ROOT)),**fingerprint(path)}
def generation():
 snapshot=Snapshot();source_graph(HARNESS,(BEND.resolve().parent.parent/'bend2/base.bend').resolve(),dict(os.environ),snapshot);return {p['path']:p['sha256']for p in snapshot.manifest()}
def tools():
 names=['test_fall_reset_world.py','reference_fall_reset_world_probe.py','reference_local_travel_history_probe.py','reference_local_move_history_probe.py','reference_local_move_world_probe.py','reference_local_collision_world_probe.py','reference_local_collision_probe.py','reference_local_input_probe.py','reference_inventory.py','reference_model_probe.py','test_geometry.py','build_native.py']
 return {'tools/'+n:pin(ROOT/'tools'/n)for n in names}
ADOPTION=ROOT/'evidence/fall-reset-world-host-adoption.json'
ADOPTION_WORK=ROOT/'build/fall-reset-world-host-adoption'
ATTEMPT=None
SEALED=None
LAST_EXECUTION=None

class DriverFailure(RuntimeError):
    pass

def write_new_json(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('x',encoding='utf-8')as stream:
        stream.write(json.dumps(value,ensure_ascii=False,sort_keys=True,indent=2)+'\n')

def write_new_stream(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('xb')as stream:
        stream.write(value if isinstance(value,bytes)else value.encode('utf-8'))

def evidence_path(kind):
    suffix=''if ATTEMPT.name=='first'else ATTEMPT.name+'-'
    return ROOT/('evidence/fall-reset-world-'+suffix+kind+'.json')

def sealed_check(full=False):
    """File-only sealed admission: no generator, JVM/javap or version process."""
    if SEALED is None:raise DriverFailure('No frozen host adoption loaded')
    mismatches=[]
    for key,actual in [('generation',generation()),('tools',tools()),('reference',pin(FIXTURE)),('table',pin(TABLE)),('compiler',fingerprint(BEND))]:
        if actual!=SEALED[key]:mismatches.append(key)
    if full:
        for row in SEALED['sealed_files']:
            path=Path(row['lookup'])
            if not path.is_file()or str(path.resolve())!=row['resolved']:
                mismatches.append('lookup:'+row['lookup']);continue
            current=fingerprint(path)
            if current['bytes']!=row['bytes']or current['sha256']!=row['sha256']:mismatches.append('file:'+row['lookup'])
    return {'status':'failed'if mismatches else'passed','mismatches':mismatches,'scope':'Sealed file hashes/resolved lookup paths only; no source regeneration, Java/JVM/javap or version probes.'}

def checked_seal(label,full=False):
    try:report=sealed_check(full)
    except BaseException as error:report={'status':'failed','error_type':type(error).__name__,'error':str(error)}
    path=ATTEMPT/'admission'/(label+'.json');write_new_json(path,report)
    if report['status']!='passed':raise DriverFailure('Sealed generation drift: '+label)
    return pin(path)

def process_inventory():
    result=subprocess.run(['ps','-ax','-o','pid=,ppid=,pgid=,stat=,rss=,vsz=,etime='],capture_output=True,text=True,check=True,timeout=2)
    rows=[]
    for line in result.stdout.splitlines():
        fields=line.split()
        if len(fields)==7:rows.append({'pid':int(fields[0]),'ppid':int(fields[1]),'pgid':int(fields[2]),'state':fields[3],'rss_kib':int(fields[4]),'virtual_kib':int(fields[5]),'elapsed':fields[6]})
    return rows

def owned_snapshot(leader,known):
    rows=process_inventory();owned={leader,*known}
    changed=True
    while changed:
        changed=False
        for row in rows:
            if row['ppid']in owned and row['pid']not in owned:owned.add(row['pid']);changed=True
    members=[row for row in rows if row['pgid']==leader or row['pid']in owned]
    for row in members:known[row['pid']]=row['pgid']
    return members

def signal_owned(leader,known,sig):
    groups={leader,*known.values()};events=[]
    for group in sorted(groups):
        if group==os.getpgrp():raise DriverFailure('Refused signal to driver group')
        try:os.killpg(group,sig);events.append({'pgid':group,'signal':sig.name,'sent':True})
        except ProcessLookupError:events.append({'pgid':group,'signal':sig.name,'sent':False,'already_absent':True})
    return events

def partial_bytes(value):
    return value if isinstance(value,bytes)else (value or'').encode('utf-8')

def execute_process(command,label,cap,env=None):
    """Own a new process group; persist argv/streams/status before any assertion."""
    global LAST_EXECUTION
    path=ATTEMPT/'processes'/label;path.mkdir(parents=True,exist_ok=False)
    planned={'status':'planned','argv':command,'cwd':str(ROOT),'timeout_trigger_seconds':cap,'cleanup_grace_seconds':5,'registry_environment':(env or os.environ).get('MC_BLOCK_REGISTRY'),'scope':'Explicit full task argv; no unrelated environment or credentials are stored.'}
    write_new_json(path/'planned.json',planned)
    start=time.monotonic();process=None;known={};samples=[];signals=[];out=err=b'';expired=False;failure=None;remaining=[];cleanup_error=None;had_lingering=False
    try:
        checked_seal('before-'+label)
        process=subprocess.Popen(command,cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
        write_new_json(path/'started.json',{'pid':process.pid,'pgid':process.pid,'argv':command})
        print(json.dumps({'phase':label,'pid':process.pid,'cap_seconds':cap,'cleanup_grace_seconds':5}),flush=True)
        while True:
            left=cap-(time.monotonic()-start)
            if left<=0:expired=True;break
            try:out,err=process.communicate(timeout=min(left,5));break
            except subprocess.TimeoutExpired as wait:
                out,err=partial_bytes(wait.stdout),partial_bytes(wait.stderr)
                samples.append({'seconds':round(time.monotonic()-start,6),'processes':owned_snapshot(process.pid,known)})
    except BaseException as error:
        failure={'type':type(error).__name__,'message':str(error)}
    finally:
        cleanup_start=time.monotonic();deadline=cleanup_start+5
        if process is not None:
            try:
                remaining=owned_snapshot(process.pid,known)
                had_lingering=process.returncode is not None and bool(remaining)
                if expired or failure or remaining:
                    signals+=signal_owned(process.pid,known,signal.SIGTERM)
                    try:out,err=process.communicate(timeout=min(1,max(.01,deadline-time.monotonic())))
                    except subprocess.TimeoutExpired as wait:out,err=partial_bytes(wait.stdout),partial_bytes(wait.stderr)
                    remaining=owned_snapshot(process.pid,known)
                    if remaining or process.poll()is None:
                        signals+=signal_owned(process.pid,known,signal.SIGKILL)
                    try:out,err=process.communicate(timeout=max(.01,deadline-time.monotonic()))
                    except subprocess.TimeoutExpired as wait:
                        out,err=partial_bytes(wait.stdout),partial_bytes(wait.stderr);cleanup_error='Pipe/leader reaping exceeded cleanup grace'
                while True:
                    process.poll();remaining=owned_snapshot(process.pid,known)
                    if not remaining or time.monotonic()>=deadline:break
                    time.sleep(min(.05,max(0,deadline-time.monotonic())))
                if process.poll()is None or remaining:cleanup_error=cleanup_error or'Owned process group/observed descendants remain after cleanup grace'
            except BaseException as error:
                cleanup_error=type(error).__name__+': '+str(error)
                try:signals+=signal_owned(process.pid,known,signal.SIGKILL)
                except BaseException:pass
                try:
                    process.kill();process.wait(timeout=max(.01,deadline-time.monotonic()))
                except BaseException:pass
            if process.stdout:process.stdout.close()
            if process.stderr:process.stderr.close()
        stdout=path/'stdout';stderr=path/'stderr';write_new_stream(stdout,out);write_new_stream(stderr,err)
        exit_code=None if process is None else process.returncode
        status='failed'if failure or exit_code not in(None,0)else'passed'
        if expired or cleanup_error or had_lingering or exit_code is None:status='inconclusive'
        receipt={'status':status,'label':label,'argv':command,'cwd':str(ROOT),'pid':None if process is None else process.pid,'pgid':None if process is None else process.pid,'exit_code':exit_code,'timed_out':expired,'seconds':round(time.monotonic()-start,6),'timeout_trigger_seconds':cap,'cleanup_grace_seconds':5,'cleanup_seconds':round(time.monotonic()-cleanup_start,6),'cleanup':{'verified':process is not None and exit_code is not None and not remaining and cleanup_error is None,'leader_reaped':exit_code is not None,'remaining':remaining,'observed_descendant_pids':sorted(p for p in known if process is not None and p!=process.pid),'had_lingering_after_leader_exit':had_lingering,'error':cleanup_error,'signals':signals,'scope':'Managed PGID and descendants observed by PID/PPID snapshots, including observed additional groups; no claim about unobserved processes which escape and reparent between snapshots.'},'orchestration_error':failure,'stdout':pin(stdout),'stderr':pin(stderr),'planned':pin(path/'planned.json'),'memory_samples':samples,'memory_scope':'5-second process-group RSS/virtual sampling; no physical-footprint or gameplay benchmark claim'}
        write_new_json(path/'execution.json',receipt)
        LAST_EXECUTION=pin(path/'execution.json')
    return out.decode('utf-8'),err.decode('utf-8'),receipt,pin(path/'execution.json')

def require_execution(receipt):
    if receipt['status']!='passed' or not receipt['cleanup']['verified']:raise DriverFailure('Execution failed/inconclusive: '+receipt['label'])

def bound(kind,cap):
    before=generation();tp=tools();ref=pin(FIXTURE);table=pin(TABLE)
    full=WORK/'native-build-full.json'
    if kind=='build'and(full.exists()or BINARY.exists()):raise DriverFailure('Refused existing native build receipt/artifact')
    command=([sys.executable,str(ROOT/'tools/build_native.py'),str(HARNESS),'-o',str(BINARY),'--cache-dir',str(ROOT/'build/fall-reset-world-cache'),'--report',str(full)]if kind=='build'else[str(BEND),str(SOURCE if kind.endswith('source')else HARNESS),'--check-only'if kind.startswith('ordinary')else'--verdict'])
    out,err,execution,execution_pin=execute_process(command,kind,cap)
    report={**execution,'kind':kind,'command':command,'execution_receipt':execution_pin,'generation':before,'generation_sha256':digest(before),'generation_unchanged':before==generation(),'tools':tp,'tools_unchanged':tp==tools(),'reference':ref,'reference_unchanged':ref==pin(FIXTURE),'table':table,'table_unchanged':table==pin(TABLE),'compiler':fingerprint(BEND)}
    path=evidence_path(kind);write_new_json(path,report)
    require_execution(execution)
    if not(report['generation_unchanged']and report['tools_unchanged']and report['reference_unchanged']and report['table_unchanged']):raise DriverFailure('Post-execution generation drift: '+kind)
    checked_seal('after-'+kind,True)
    if kind=='build':
        build=json.loads(full.read_text())
        audit={'binary_match':build['binary_sha256']==fingerprint(BINARY)['sha256'],'dependency_count':len(build['dependencies'])}
        write_new_json(ATTEMPT/'build-artifact-audit.json',audit)
        if not audit['binary_match']:raise DriverFailure('Native artifact receipt mismatch')
        details={'status':'passed','execution_report':pin(path),'execution_receipt':execution_pin,'binary':pin(BINARY),'native_build':{'full_receipt':pin(full),'dependency_count':len(build['dependencies']),'dependencies_sha256':digest(build['dependencies']),'artifact':build['artifact'],'cache_key':build['cache_key'],'cache_hit':build['cache_hit'],'timings':build['timings'],'identity':build['identity'],'compiler':{k:v for k,v in build['compiler'].items()if k!='driver_probe'},'associated_preflight_c_sha256':build['emitted_c_sha256'],'c_scope':'Content-keyed preflight C; installed CLI temporary native-internal C is not retained or asserted identical.'}}
        write_new_json(evidence_path('build-final'),details)
        return {**report,**details}
    return report


def bits(value):return struct.pack('>d',value).hex()
def words(raw):return [int(raw[:8],16),int(raw[8:],16)]
def group(values):return '|'.join(str(v&0xffffffff)for v in values)
def vector(values):return group([word for value in values for word in words(value)])
def request(case,id=None,work=None,profile=0,malformed=0,from_=None,to=None,interior=INTERIOR):
 return ';'.join([(id or case['id'])+'|clip',vector(from_ or case['from']),vector(to or case['to']),vector([bits(v)for v in interior]),group([len(case['reads'])if work is None else work,profile,malformed])])
def edit(id,position,name):return '|'.join(map(str,[id,'edit',*(v&0xffffffff for v in position),NAMES.index(name if name.startswith('minecraft:')else'minecraft:'+name)]))
def edits(case):return [edit('edit:'+str(i),w['position'],w['block'])for i,w in enumerate(case['world_writes'])]
def parse(stdout):
 values={};reads={}
 for line in stdout.splitlines():
  row=line.split('|');assert len(row)>=3,row;id,key,*fields=row
  if key=='read':reads.setdefault(id,[]).append(fields)
  else:assert(id,key)not in values,(id,key);values[id,key]=fields
 return values,reads

def retained(values,id):
 for field in ['body','clock','queue','view','canonical']:assert values[id+'-before',field]==values[id+'-after',field],(id,'owner retention',field)
def raw64(values):
 assert len(values)%2==0;return ['%08x%08x'%(int(values[i]),int(values[i+1]))for i in range(0,len(values),2)]
def current_palette(values,id):
 fields=values[id+'-before','view'];assert fields[2]!='none';return dict(zip(NAMES[:4],map(int,fields[2].split(',')),strict=True))
def compare(case,values,reads,id=None):
 id=id or case['id'];retained(values,id);assert case['admission']['supported']and case['result']['type']=='MISS'
 assert values[id,'clip']==['miss']and raw64(values[id,'from'])==case['from']and raw64(values[id,'to'])==case['to']
 assert raw64(values[id,'expanded-from'])==case['expanded']['start']and raw64(values[id,'expanded-to'])==case['expanded']['end']
 palette=current_palette(values,id);expected=[]
 for i,event in enumerate(case['reads']):
  expected.append([str(i),'block'if event['phase']=='BlockSample'else'fluid-source',','.join(str(v&0xffffffff)for v in event['position']),str(palette[event['block_id']])])
 assert reads.get(id,[])==expected,(id,'actual ordered two-read DDA trace',reads.get(id,[]),expected)
 assert len(expected)==2*len(case['visited_cells'])and not any(event['boxes']for event in case['shape_events'])
 return {'id':id,'reads':len(expected),'visits':len(case['visited_cells']),'actual_miss':True,'expanded_raw_match':True,'exact_order_and_duplicates_match':True,'complete_owner_retained':True,'minimum_work':len(expected)}

def native(commands,label,env=None):
 command=[str(BINARY),'--gpu','off','--threads','1',*commands]
 out,err,execution,execution_pin=execute_process(command,'native-'+label,120,env)
 receipt={'label':label,'pid':execution['pid'],'exit_code':execution['exit_code'],'timed_out':execution['timed_out'],'seconds':execution['seconds'],'stdout':execution['stdout'],'stderr':execution['stderr'],'command_prefix':command[:5],'command_inputs_sha256':digest(commands),'cap_seconds':120,'cleanup_grace_seconds':5,'execution_receipt':execution_pin,'cleanup':execution['cleanup'],'status':execution['status']}
 require_execution(execution)
 checked_seal('after-native-'+label)
 return *parse(out),receipt

def corpus(data,prefix,env=None,cases=None):
 rows=[];guards=[];receipts=[]
 for i,case in enumerate(cases or data['cases']):
  if not case['admission']['supported']:
   # Source policy guards are covered below; actual unsupported reference
   # observations, hits/watchdog failures remain intact and explicitly excluded.
   guards.append({'id':case['id'],'actual_returned':case['actual_returned'],'actual_type':case.get('result',{}).get('type'),'exclusion':case['admission']['exclusion']});continue
  p,r,receipt=native(edits(case)+[request(case)],prefix+str(i),env);receipts.append(receipt);rows.append(compare(case,p,r))
 return rows,guards,receipts

def policies(data,prefix):
 good=next(c for c in data['cases']if c['admission']['supported']and len(c['reads'])>2)
 point=good['reads'][0]['position'];original=good['reads'][0]['block_id'];specs=[('profile',{'profile':1},'fall-reset-tags-unresolved'),('tail',{'malformed':1},'fall-reset-noncanonical-request'),('zero-work',{'work':0},'fall-reset-work-budget'),('one-work',{'work':1},'fall-reset-work-budget'),('short-work',{'work':len(good['reads'])-1},'fall-reset-work-budget'),('from-nan',{'from_':['7ff8000000000001',*good['from'][1:]]},'fall-reset-invalid-endpoint:0'),('to-infinity',{'to':['7ff0000000000000',*good['to'][1:]]},'fall-reset-invalid-endpoint:3'),('expanded-range',{'from_':[bits(2147483647.5),*good['from'][1:]],'to':[bits(2147483648.5),*good['to'][1:]]},'fall-reset-expanded-coordinate-range'),('invalid-interior',{'interior':[1.,1.,1.,0.,0.,0.]},'fall-reset-invalid-interior'),('outside-interior',{'interior':[.25,.25,.25,.75,.75,.75]},'fall-reset-outside-interior'),('missing-section',{'from_':[bits(32.5),bits(1.5),bits(.5)],'to':[bits(33.5),bits(1.5),bits(.5)],'work':32},'missing-section:')]
 rows=[];receipts=[]
 for i,(name,changes,error)in enumerate(specs):
  p,r,receipt=native(edits(good)+[request(good,name,**changes),request(good,'recovery')],prefix+name);receipts.append(receipt);retained(p,name);assert p[name,'error'][0].startswith(error),(name,error,p.get((name,'error')));assert name not in r;compare(good,p,r,'recovery');rows.append({'id':name,'error':p[name,'error'][0],'same_owner_recovered':True})
 extra=[('absent-palette',['no|no-palette'],['fix|palette-refresh'],'fall-reset:edge-palette-unavailable'),('stale-palette',['stale|stale-palette'],['fix|palette-refresh'],'fall-reset:edge-palette-stale')]
 for name,setup,cleanup,error in extra:
  p,r,receipt=native(edits(good)+setup+[request(good,name)]+cleanup+[request(good,'recovery')],prefix+name);receipts.append(receipt);retained(p,name);assert p[name,'error']==[error];compare(good,p,r,'recovery');rows.append({'id':name,'error':error,'same_owner_recovered':True})
 for name in NAMES[4:]:
  id=name.split(':')[1];p,r,receipt=native(edits(good)+[edit('unsupported',point,name),request(good,id),edit('repair',point,original),request(good,'recovery')],prefix+id);receipts.append(receipt);retained(p,id);assert p[id,'error'][0].startswith('unsupported-block-state:'),(id,p.get((id,'error')));compare(good,p,r,'recovery');rows.append({'id':id,'error':p[id,'error'][0],'same_owner_recovered':True,'actual_registry_state_lookup':True})
 p,r,receipt=native(edits(good)+['clock|clock','running|running','pending|pending',request(good,'queued')],prefix+'pending');receipts.append(receipt);compare(good,p,r,'queued');rows.append({'id':'pending','all_clocks_queues_retained':True})
 equal=next(c for c in data['cases']if c['admission']['supported']and not c['reads']);p,r,receipt=native(edits(equal)+[request(equal,'equal-zero-budget',work=0)],prefix+'equal-zero-budget');receipts.append(receipt);compare(equal,p,r,'equal-zero-budget');rows.append({'id':'equal-zero-budget','no_core_reads':True})
 # Actual interrupted traces are not MISS expectations. For repeated owned
 # cells, replay only the measured budget and verify complete refusal.
 for case in interrupted_owned(data):
  id='observed-work:'+case['id'];p,r,receipt=native(edits(case)+[request(case,id,work=case['read_limit']),*edits(good),request(good,'recovery')],prefix+id.replace(':','_'));receipts.append(receipt);retained(p,id);assert p[id,'error']==['fall-reset-work-budget'];assert id not in r;compare(good,p,r,'recovery');rows.append({'id':id,'error':'fall-reset-work-budget','same_owner_recovered':True,'actual_clip_interrupted':True,'actual_partial_reads':len(case['reads']),'actual_complete_miss_claim':False})
 return rows,receipts

def interrupted_owned(data):
 return [c for c in data['cases']if not c['actual_returned']and c['reads']and all(e['block_id']in NAMES[:4]for e in c['reads'])and all(all(-16<=v<16 for v in p)for p in c['visited_cells'])]

def remap(data,prefix):
 path=WORK/'remapped.tsv';order=['minecraft:oak_planks','minecraft:stone','minecraft:air','minecraft:dirt'];path.write_text('block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json\n'+''.join(f'{i}\t{name}\t{i}\t1\t{i}\t[]\n'for i,name in enumerate(order)))
 env=dict(os.environ);env['MC_BLOCK_REGISTRY']=str(path);supported=[c for c in data['cases']if c['admission']['supported']];selected=supported[:12]
 for name in NAMES[:4]:
  case=next(c for c in supported if any(e['block_id']==name for e in c['reads']))
  if case not in selected:selected.append(case)
 rows,excluded,receipts=corpus(data,prefix,env,selected);assert not excluded
 return {'registry':pin(path),'case_count':len(rows),'rows':rows},receipts

def preparation(data,ordinary):
 g=generation();supported=[c for c in data['cases']if c['admission']['supported']];assert supported and any(not c['reads']for c in supported)
 protocol=[]
 for c in supported:
  widths=[len(p.split('|'))for p in request(c).split(';')];assert widths==[2,6,6,12,3];protocol.append(widths)
 report={'status':'ordinary-prepared-native-kernel-not-attempted','source':pin(SOURCE),'harness':pin(HARNESS),'runner':pin(Path(__file__)),'reference':pin(FIXTURE),'tools':tools(),'generation':g,'generation_sha256':digest(g),'generation_count':len(g),'ordinary':ordinary,'actual_cases':len(data['cases']),'admitted_cases':len(supported),'admitted_visits':sum(len(c['visited_cells'])for c in supported),'admitted_ordered_reads':sum(len(c['reads'])for c in supported),'protocol_widths':[2,6,6,12,3],'policy_cases':24+len(interrupted_owned(data)),'observed_budget_interruptions':len(interrupted_owned(data)),'production_laws':SOURCE.read_text().count('\nlaw '),'harness_laws':HARNESS.read_text().count('\nlaw '),'source_effect':'Read-only Core/Registry; complete View always retained, no Body/history/tick mutation.','caps_seconds':{'build':600,'native_process':120,'kernel':60},'planned_command':'PYTHONDONTWRITEBYTECODE=1 python3 tools/test_fall_reset_world.py --skip-ordinary'}
 write_json(ROOT/'evidence/fall-reset-world-preparation.json',report);return report

def audit_native_dependencies(full,label):
    rows=[]
    for dep in full['dependencies']:
        try:
            path=Path(dep['lookup']);got=fingerprint(path)
            matched=path.resolve()==Path(dep['path'])and got['sha256']==dep['sha256']and got['bytes']==dep['bytes']
            if not matched:rows.append({'lookup':dep['lookup'],'matched':False})
        except BaseException as error:rows.append({'lookup':dep['lookup'],'error_type':type(error).__name__,'error':str(error)})
    report={'status':'failed'if rows else'passed','dependency_count':len(full['dependencies']),'dependencies_sha256':digest(full['dependencies']),'mismatches':rows}
    path=ATTEMPT/(label+'.json');write_new_json(path,report)
    if rows:raise DriverFailure('Native dependency drift: '+label)
    return pin(path)

def main():
    global ATTEMPT,SEALED
    parser=argparse.ArgumentParser()
    parser.add_argument('--prepare',action='store_true');parser.add_argument('--skip-ordinary',action='store_true');parser.add_argument('--skip-build',action='store_true');parser.add_argument('--skip-kernel',action='store_true');parser.add_argument('--attempt-id',default='first')
    args=parser.parse_args()
    if args.prepare:raise DriverFailure('Original preparation is sealed; regeneration/overwrite is refused. Use the archived preparation and host-adoption receipt.')
    if not args.skip_ordinary:raise DriverFailure('Original ordinary checks are sealed; execution requires --skip-ordinary.')
    if not args.attempt_id or any(c not in'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_'for c in args.attempt_id):raise DriverFailure('Invalid disjoint attempt ID')
    if not ADOPTION.is_file():raise DriverFailure('Frozen host adoption is required before execution')
    SEALED=json.loads(ADOPTION.read_text())
    path=WORK/'attempts'/args.attempt_id
    try:path.mkdir(parents=True,exist_ok=False)
    except FileExistsError:raise DriverFailure('Prior attempt exists; no receipt or stream will be overwritten: '+args.attempt_id)
    ATTEMPT=path
    write_new_json(ATTEMPT/'request.json',{'status':'reserved','argv':[sys.executable,*sys.argv],'adoption':pin(ADOPTION),'planned_caps_seconds':{'build':600,'native':120,'kernel':60},'cleanup_grace_seconds':5,'skip_build':args.skip_build,'skip_kernel':args.skip_kernel,'scope':'One disjoint attempt; no preflight/reference generation or Java/version probes.'})
    if SEALED['status']!='frozen-host-adoption-ready':raise DriverFailure('Host adoption is not frozen-ready')
    checked_seal('execution-start',True)
    data=json.loads(FIXTURE.read_text());initial=generation();tp=tools();ref=pin(FIXTURE)
    integrity={'status':'retained-sealed-reference-integrity','receipt':SEALED['reference_integrity'],'failure_injections':11,'scope':'Exact previously executed integrity receipt retained; no mutation/producer re-execution.'}
    if args.skip_build:
        final=json.loads((ROOT/'evidence/fall-reset-world-build-final.json').read_text());execution=json.loads((ROOT/final['execution_report']['path']).read_text());build={**execution,**final}
    else:build=bound('build',600)
    artifact_audit={'status':'passed'if build['status']=='passed'and build['generation']==initial and build['binary']==pin(BINARY)else'failed','build_status':build['status'],'generation_match':build['generation']==initial,'binary_match':build['binary']==pin(BINARY)}
    write_new_json(ATTEMPT/'artifact-admission.json',artifact_audit)
    if artifact_audit['status']!='passed':raise DriverFailure('Retained build/artifact admission failed')
    full=json.loads((WORK/'native-build-full.json').read_text());before_deps=audit_native_dependencies(full,'dependencies-before')
    runs=[]
    for i in range(2):
        rows,excluded,receipts=corpus(data,f'run{i}-case');policy,more=policies(data,f'run{i}-policy-');mapped,extra=remap(data,f'run{i}-remap-');receipts+=more+extra
        results={'rows':rows,'excluded':excluded,'policies':policy,'remap':mapped};raw=ATTEMPT/f'run{i}-full.json';write_new_json(raw,{**results,'receipts':receipts})
        runs.append({'admitted_cases':len(rows),'visits':sum(r['visits']for r in rows),'ordered_reads':sum(r['reads']for r in rows),'exclusions':excluded,'policy_cases':len(policy),'remap_cases':mapped['case_count'],'result_sha256':digest(results),'native_processes':len(receipts),'seconds':round(sum(r['seconds']for r in receipts),6),'raw':pin(raw)})
        write_new_json(ATTEMPT/f'run{i}-summary.json',runs[-1])
    audit={'status':'passed'if runs[0]['result_sha256']==runs[1]['result_sha256']and initial==generation()and tp==tools()and ref==pin(FIXTURE)else'failed','suite_digest_match':runs[0]['result_sha256']==runs[1]['result_sha256'],'generation_unchanged':initial==generation(),'tools_unchanged':tp==tools(),'reference_unchanged':ref==pin(FIXTURE)}
    write_new_json(ATTEMPT/'comparison-final.json',audit)
    if audit['status']!='passed':raise DriverFailure('Final comparison/generation drift')
    checked_seal('native-final',True);after_deps=audit_native_dependencies(full,'dependencies-after')
    report={'status':'passed','source':pin(SOURCE),'harness':pin(HARNESS),'generation':initial,'generation_sha256':digest(initial),'generation_unchanged':audit['generation_unchanged'],'tools':tp,'tools_unchanged':audit['tools_unchanged'],'reference':ref,'reference_unchanged':audit['reference_unchanged'],'binary':pin(BINARY),'build':build['execution_report'],'reference_integrity':integrity,'runs':runs,'dependency_audits':[before_deps,after_deps],'adoption':pin(ADOPTION),'scope':'Actual checked two-block-read DDA MISS supplier in explicit default tagged four-state ClientLevel/overworld; no movement mutation or inferred clip.'}
    write_new_json(evidence_path('native'),report)
    print(json.dumps({'native_status':'passed','runs':runs}),flush=True)
    if not args.skip_kernel:
        proof=bound('kernel',60)
        if proof['status']!='passed':raise DriverFailure('Independent proof failed/inconclusive')
    checked_seal('execution-finish',True)
    write_new_json(evidence_path('driver'),{'status':'native-passed-proof-skipped'if args.skip_kernel else'passed','native':pin(evidence_path('native')),'kernel':None if args.skip_kernel else pin(evidence_path('kernel')),'attempt':pin(ATTEMPT/'request.json'),'adoption':pin(ADOPTION),'scope':'Explicit process/comparison status only; proof failure/inconclusive raises and exits nonzero while prior native verdict remains immutable.'})

if __name__=='__main__':
    try:main()
    except BaseException as error:
        if isinstance(error,SystemExit):raise
        failure={'status':'inconclusive'if isinstance(error,KeyboardInterrupt)else'failed','error_type':type(error).__name__,'error':str(error),'adoption':pin(ADOPTION)if ADOPTION.is_file()else None,'scope':'First failure retained; no implicit retry, no overwriting earlier process/native/proof receipts.'}
        if ATTEMPT is not None:
            raw=ATTEMPT/'failure.full.json';write_new_json(raw,{**failure,'traceback':__import__('traceback').format_exc()})
            summary={**failure,'error':str(error)[:1500],'raw':pin(raw),'last_execution':LAST_EXECUTION}
            write_new_json(evidence_path('failure'),summary)
        print(json.dumps({'status':failure['status'],'error_type':type(error).__name__,'error':str(error)[:1500]}),file=sys.stderr,flush=True)
        raise SystemExit(1)
