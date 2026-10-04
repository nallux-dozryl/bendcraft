#!/usr/bin/env python3
"""Split, sealed host continuation; all ray/owner expectations stay in frozen F."""
from __future__ import annotations
import argparse, ast, contextlib, hashlib, io, json, os, signal, subprocess, sys, time, traceback
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
FROZEN=ROOT/'tools/test_fall_reset_world.py'
FROZEN_SHA='d304fd0e425d6790f316a99ce88635623584bea637e75d0b143c71318ecf72fc'
SOURCE_SHA='8353ad65484f28b80ae49a3b4191bf98aad5903f6565f6d17f2d64eeec2c7948'
ADOPTION_SHA='c297f08fbfeee055c7264c24cf0351a817a5f6cbe67d5ed49696083579286f0d'
BLOCKER=ROOT/'build/review-fall-reset-world/current-admission/admission.json'
BLOCKER_SHA='d2e637a49ab3231f7f3f731e47dc8724ced8332594232f60b712e8997150532c'
WORK=ROOT/'build/fall-reset-world-continuation'
READY=WORK/'prepared.json'
BINARY=WORK/'fall-reset-world-native'
CACHE=WORK/'native-cache'
BUILD=WORK/'native-build.json'
CONSUMER=WORK/'consumer-manifest.json'
BUILD_RESULT=ROOT/'evidence/fall-reset-world-continuation-build.json'
DOC=ROOT/'docs/FALL_RESET_WORLD_CONTINUATION.md'
RETRY_WITNESS=ROOT/'tools/test_local_player_session.py'
PROTECTED=('bits','words','group','vector','request','edit','edits','parse','retained','raw64',
 'current_palette','compare','native','corpus','policies','interrupted_owned','remap','preparation')
GROUPS=[]
JOURNAL=None
LAST_EXECUTION=None

class Refused(RuntimeError):pass
class UnretriedInputDrift(RuntimeError):pass

def require(value,message):
    if not value:raise Refused(message)

def digest(value):
    return hashlib.sha256(json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()

def pin(path):
    path=Path(path).absolute();before=path.stat();raw=path.read_bytes();after=path.stat()
    require((before.st_dev,before.st_ino,before.st_size,before.st_mtime_ns)==
        (after.st_dev,after.st_ino,after.st_size,after.st_mtime_ns),'File changed while hashing: '+str(path))
    return {'lookup':str(path),'resolved':str(path.resolve()),'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}

def exclusive(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('x',encoding='utf-8')as stream:
        stream.write(json.dumps(value,ensure_ascii=False,sort_keys=True,indent=2)+'\n');stream.flush();os.fsync(stream.fileno())

def unused(*paths):
    for path in paths:require(not Path(path).exists()and not Path(path).is_symlink(),'Refuse existing path: '+str(path))

def sealed(value):return {**value,'seal_sha256':digest(value)}

def load_seal(path):
    value=json.loads(Path(path).read_bytes());require(value['seal_sha256']==digest({k:v for k,v in value.items()if k!='seal_sha256'}),'Invalid seal: '+str(path));return value

def check_files(rows):
    for key,row in rows.items():require(pin(key)==row,'Pinned file drift: '+key)

def failure(path,cause,**extra):
    exclusive(path,{'status':'failed','type':type(cause).__name__,'error':str(cause),
        'traceback':traceback.format_exc(),**extra})

require(sys.flags.optimize==0,'Assertions must be enabled')
require(pin(FROZEN)['sha256']==FROZEN_SHA,'Frozen comparator runner changed before import')
import test_fall_reset_world as F

@contextlib.contextmanager
def bindings(module,changes):
    original={name:getattr(module,name)for name in changes}
    try:
        for name,value in changes.items():setattr(module,name,value)
        yield
    finally:
        for name,value in original.items():setattr(module,name,value)
        require(all(getattr(module,k)is v for k,v in original.items()),'Scoped bindings not restored')

def ast_contract():
    tree=ast.parse(FROZEN.read_text());functions={node.name:ast.dump(node,include_attributes=False)
        for node in tree.body if isinstance(node,(ast.FunctionDef,ast.ClassDef))}
    require(all(name in functions for name in PROTECTED),'Missing frozen producer/comparator')
    return {'runner':pin(FROZEN),'protected_functions':{n:hashlib.sha256(functions[n].encode()).hexdigest()for n in PROTECTED},
        'preservation':'Frozen file is byte-identical; no parser, comparison, expectation, corpus, policy or remap body is replaced.'}

def retry_contract():
    def body(path):
        return ast.dump(next(node for node in ast.parse(path.read_text()).body
            if isinstance(node,ast.FunctionDef)and node.name=='forbid_builder_retry'),include_attributes=False)
    actual=body(Path(__file__));require(actual==body(RETRY_WITNESS),'Constructor-abort strategy differs from retained Local witness')
    return {'witness':pin(RETRY_WITNESS),'function_AST_sha256':hashlib.sha256(actual.encode()).hexdigest()}

def frozen_admission(full=True):
    require(pin(F.SOURCE)['sha256']==SOURCE_SHA and pin(F.ADOPTION)['sha256']==ADOPTION_SHA,'Frozen source/adoption identity changed')
    adoption=json.loads(F.ADOPTION.read_bytes())
    with bindings(F,{'SEALED':adoption}):report=F.sealed_check(full)
    require(report['status']=='passed','Frozen adoption refused: '+str(report))
    return adoption

def audit(full=True):
    value=load_seal(READY);check_files(value['files']if full else value['quick_files'])
    frozen_admission(full)
    require(value['ast']==ast_contract(),'Frozen AST contract changed')
    require(value['retry_strategy']==retry_contract(),'No-retry strategy changed')
    return value

def admission(label,full=False):
    value=audit(full);path=F.ATTEMPT/'admission'/(label+'.json')
    exclusive(path,{'status':'passed','ready_seal':value['seal_sha256'],'full':full})
    return F.pin(path)

def append_group(path,row):
    with Path(path).open('a',encoding='utf-8')as stream:
        stream.write(json.dumps(row,sort_keys=True)+'\n');stream.flush();os.fsync(stream.fileno())

def register_discovered(known,label):
    recorded={row['pgid']for row in GROUPS}
    for pid,pgid in known.items():
        if pgid not in recorded:
            row={'pid':pid,'pgid':pgid,'label':label,'discovered':True};GROUPS.append(row)
            append_group(JOURNAL,row);recorded.add(pgid)

class GroupOps:
    def __init__(self,leaders=None):self.leaders=leaders or {}
    def probe(self,pgid):
        require(isinstance(pgid,int)and pgid>0 and pgid!=os.getpgrp(),'Refuse nonpositive/own process group')
        try:os.killpg(pgid,0);return False
        except ProcessLookupError:return True
    def term(self,pgid):
        require(isinstance(pgid,int)and pgid>0 and pgid!=os.getpgrp(),'Refuse nonpositive/own process group')
        try:os.killpg(pgid,signal.SIGTERM)
        except ProcessLookupError:pass
    def kill(self,pgid):
        require(isinstance(pgid,int)and pgid>0 and pgid!=os.getpgrp(),'Refuse nonpositive/own process group')
        try:os.killpg(pgid,signal.SIGKILL)
        except ProcessLookupError:pass
    def wait(self,pgid,deadline):
        process=self.leaders.get(pgid)
        if process is not None:process.wait(timeout=max(.001,deadline-time.monotonic()))
        while not self.probe(pgid):
            if time.monotonic()>=deadline:raise TimeoutError('Group remains at cleanup deadline: '+str(pgid))
            time.sleep(min(.02,max(0,deadline-time.monotonic())))

def sweep(groups,path,*,ops=None,deadline=None,initial_errors=()):
    """Visit every discovered PG even after EPERM; unknown is never absent."""
    ops=ops or GroupOps();deadline=deadline if deadline is not None else time.monotonic()+5
    rows=[];errors=list(initial_errors)
    for pgid in sorted(set(groups)):
        row={'pgid':pgid,'before_absent':None,'after_absent':None,'errors':[]}
        def attempt(name,call):
            try:return call()
            except BaseException as cause:
                detail={'stage':name,'type':type(cause).__name__,'error':str(cause)}
                row['errors'].append(detail);errors.append({'pgid':pgid,**detail});return None
        row['before_absent']=attempt('probe-before',lambda:ops.probe(pgid))
        if row['before_absent']is not True:
            attempt('TERM',lambda:ops.term(pgid));attempt('KILL',lambda:ops.kill(pgid));attempt('wait',lambda:ops.wait(pgid,deadline))
        row['after_absent']=attempt('probe-after',lambda:ops.probe(pgid));rows.append(row)
    result={'status':'passed'if not errors and all(r['after_absent']is True for r in rows)else'failed',
        'deadline_monotonic':deadline,'rows':rows,'errors':errors,'unknown_groups':[r['pgid']for r in rows if r['after_absent']is None],
        'scope':'Observed managed groups only. Unobserved descendants that escape/reparent between snapshots are not authenticated.'}
    exclusive(path,result);return result

@contextlib.contextmanager
def parent_cleanup(directory,*,ops=None):
    directory.mkdir(parents=True,exist_ok=True);cause=None
    try:yield
    except BaseException as error:cause=error;raise
    finally:
        report=sweep([row['pgid']for row in GROUPS],directory/'final-cleanup.json',ops=ops)
        if report['status']!='passed'and cause is None:raise Refused('Parent cleanup failed; unknown/living groups retained')

def execute_process(command,label,cap,env=None,*,_popen=None,_snapshot=None,_ops=None,_admit=None,_clock=None):
    """Raw files preopened; PID journal immediate; receipts unconditional before decode."""
    global LAST_EXECUTION
    require(cap in(600,120,60),'Unexpected execution cap')
    path=F.ATTEMPT/'processes'/label;path.mkdir(parents=True,exist_ok=False)
    planned={'argv':list(map(str,command)),'cwd':str(ROOT),'cap_seconds':cap,'cleanup_seconds':5,
        'registry_environment':(env or os.environ).get('MC_BLOCK_REGISTRY')}
    exclusive(path/'planned.json',planned)
    out_file=(path/'stdout.live').open('xb',buffering=0);err_file=(path/'stderr.live').open('xb',buffering=0)
    process=None;known={};samples=[];error=None;timed_out=False;cleanup=None;cleanup_errors=[];lingering=False
    clock=_clock or time.monotonic
    start=clock();deadline=start+cap;admit=_admit or admission;snapshot=_snapshot or F.owned_snapshot
    try:
        admit('before-'+label)
        process=(_popen or subprocess.Popen)(list(map(str,command)),cwd=ROOT,env=env,stdout=out_file,stderr=err_file,start_new_session=True)
        row={'pid':process.pid,'pgid':process.pid,'label':label,'argv':planned['argv']}
        GROUPS.append(row);known[process.pid]=process.pid
        require(JOURNAL is not None,'Missing durable group journal');append_group(JOURNAL,row)
        exclusive(path/'started.json',{**row,'start_monotonic':start,'deadline_monotonic':deadline})
        print(json.dumps({'phase':label,'pid':process.pid,'pgid':process.pid,'cap_seconds':cap,
            'start_monotonic':start,'deadline_monotonic':deadline,'inert_object':_popen is not None}),flush=True)
        while True:
            left=deadline-clock()
            if left<=0:timed_out=True;break
            try:process.wait(timeout=min(left,1));break
            except subprocess.TimeoutExpired:
                samples.append({'seconds':clock()-start,'owned':snapshot(process.pid,known)})
                register_discovered(known,label)
    except BaseException as cause:error={'type':type(cause).__name__,'message':str(cause)}
    finally:
        cleanup_start=clock()
        try:
            if process is not None:
                try:
                    remaining=snapshot(process.pid,known);register_discovered(known,label)
                    lingering=process.returncode is not None and bool(remaining)
                except BaseException as cause:cleanup_errors.append({'stage':'owned-snapshot','type':type(cause).__name__,'error':str(cause)})
                cleanup=sweep({process.pid,*known.values()},path/'cleanup.json',
                    ops=_ops or GroupOps({process.pid:process}),deadline=cleanup_start+5,initial_errors=cleanup_errors)
            else:cleanup={'status':'failed','rows':[],'errors':[{'stage':'launch','error':'No launched process; empty journal is not execution evidence'}],'unknown_groups':[]}
        except BaseException as cause:
            cleanup={'status':'failed','rows':[],'errors':[{'stage':'cleanup-supervisor','type':type(cause).__name__,'error':str(cause)}],'unknown_groups':list(set(known.values()))}
        finally:
            out_file.close();err_file.close()
            # Freeze the captured prefix even if a denied cleanup leaves a writer alive.
            # Live files remain separately retained; an unknown group never yields PASS.
            with (path/'stdout').open('xb')as stream:stream.write((path/'stdout.live').read_bytes())
            with (path/'stderr').open('xb')as stream:stream.write((path/'stderr.live').read_bytes())
            exit_code=None if process is None else process.returncode
            verified=process is not None and exit_code is not None and cleanup['status']=='passed'
            receipt={'status':'passed'if verified and exit_code==0 and not timed_out and not error and not lingering else'failed',
                'label':label,'argv':planned['argv'],'cwd':str(ROOT),'pid':None if process is None else process.pid,
                'pgid':None if process is None else process.pid,'exit_code':exit_code,'timed_out':timed_out,
                'seconds':clock()-start,'cap_seconds':cap,'cleanup_grace_seconds':5,
                'cleanup':{**cleanup,'verified':verified,'leader_reaped':exit_code is not None,
                    'had_lingering_after_leader_exit':lingering,'seconds':clock()-cleanup_start},
                'orchestration_error':error,'stdout':F.pin(path/'stdout'),'stderr':F.pin(path/'stderr'),
                'observed_groups':sorted(set(known.values())),'samples':samples,'inert_object':_popen is not None}
            receipt['raw_capture_scope']='Immutable captured bytes after the bounded cleanup; live descriptor files retained separately. Failed/unknown cleanup does not claim future stream completeness.'
            exclusive(path/'execution.json',receipt);F.LAST_EXECUTION=F.pin(path/'execution.json');LAST_EXECUTION=F.LAST_EXECUTION
    # Frozen native() keeps its original require_execution, parse and comparator.
    return (path/'stdout').read_bytes().decode('utf-8'),(path/'stderr').read_bytes().decode('utf-8'),receipt,F.pin(path/'execution.json')

def forbid_builder_retry(builder):
    original=builder.InputsChanged
    class RefusedInputsChanged(original):
        def __new__(cls,*args,**kwargs):raise UnretriedInputDrift(*args)
    builder.InputsChanged=RefusedInputsChanged
    return original

@contextlib.contextmanager
def retry_scope(builder):
    original=forbid_builder_retry(builder)
    try:yield
    finally:
        builder.InputsChanged=original;require(builder.InputsChanged is original,'Builder retry binding not restored')

@contextlib.contextmanager
def execution_scope(directory,*,binary=BINARY):
    global JOURNAL,GROUPS
    original_journal,original_groups=JOURNAL,GROUPS;JOURNAL=directory/'owned-groups.jsonl';GROUPS=[]
    JOURNAL.touch(exist_ok=False)
    adoption=json.loads(F.ADOPTION.read_bytes())
    try:
        with bindings(F,{'BINARY':binary,'WORK':directory,'ATTEMPT':directory,'SEALED':adoption,
            'execute_process':execute_process,'checked_seal':admission,'LAST_EXECUTION':None}):yield
    finally:
        JOURNAL,GROUPS=original_journal,original_groups
        require(JOURNAL is original_journal and GROUPS is original_groups,'Journal routing not restored')

def build_child(report_path):
    value=audit();require(report_path==WORK/'build-attempt/builder.json','Unrecognized child report path')
    pending=json.loads((WORK/'build-attempt/request.json').read_bytes())
    require(pending['argv']==[sys.executable,str(Path(__file__)), '--_build-child',str(report_path)]and pending['cap_seconds']==600,'No bounded parent reservation')
    unused(report_path,BINARY,CACHE,WORK/'build-attempt/child-claim.json')
    exclusive(WORK/'build-attempt/child-claim.json',{'pid':os.getpid(),'pgid':os.getpgrp(),'seal':value['seal_sha256'],'retries_allowed':0})
    import build_native as builder
    with retry_scope(builder):report=builder.ensure_native(F.HARNESS,BINARY,bend=F.BEND,cache_dir=CACHE,force=True)
    require(report['retries']==0 and report['cache_hit']is False,'Retry or implicit cache reuse forbidden')
    audit();exclusive(report_path,report);print(json.dumps({'status':'built-behavior-unverified','binary_sha256':report['binary_sha256'],'retries':0}),flush=True)

def verify_build(*,require_completion=True):
    value=audit();manifest=load_seal(CONSUMER);check_files(manifest['files']);receipt=json.loads(BUILD.read_bytes())
    require(manifest['ready_seal']==value['seal_sha256']and receipt['ready_seal']==value['seal_sha256'],'Artifact generation differs')
    built=receipt['build'];require(built['retries']==0 and built['cache_hit']is False,'Non-single build receipt')
    require(pin(BINARY)['sha256']==built['binary_sha256'],'Native bytes differ')
    if require_completion:
        require(not(WORK/'build-attempt/first-failure.json').exists(),'Failed build cannot admit native execution')
        completed=json.loads(BUILD_RESULT.read_bytes());cleanup=json.loads((WORK/'build-attempt/final-cleanup.json').read_bytes())
        require(cleanup['status']=='passed'and completed['status']=='built-behavior-unverified'and completed['receipt']==pin(BUILD)
            and completed['binary']==pin(BINARY)and completed['consumer']==pin(CONSUMER),'Build completion/cleanup not admitted')
    for row in built['dependencies']:require(pin(row['path'])['sha256']==row['sha256']and pin(row['path'])['bytes']==row['bytes'],'Native dependency drift: '+row['path'])
    return receipt,manifest

def build():
    value=audit();unused(WORK/'build-attempt',BINARY,CACHE,BUILD,CONSUMER,BUILD_RESULT)
    directory=WORK/'build-attempt';directory.mkdir();process=None
    command=[sys.executable,str(Path(__file__)),'--_build-child',str(directory/'builder.json')]
    exclusive(directory/'request.json',{'argv':command,'cap_seconds':600,'ready_seal':value['seal_sha256']})
    try:
        with execution_scope(directory),parent_cleanup(directory):
            out,err,process,process_pin=execute_process(command,'build',600);F.require_execution(process)
            audit();built=json.loads((directory/'builder.json').read_bytes())
            require(built['retries']==0 and built['cache_hit']is False,'Build retried/reused cache')
            require(pin(BINARY)['sha256']==built['binary_sha256'],'Build artifact differs')
            exclusive(BUILD,{'status':'built-behavior-unverified','ready_seal':value['seal_sha256'],'producer':pin(Path(__file__)),
                'build':built,'execution':process_pin})
            import build_native as builder
            cached=builder._verified(CACHE/'entries'/built['cache_key'],built['cache_key']);require(cached is not None,'Native cache invalid')
            emitted=CACHE/'sources'/cached['key_data']['prekey']/'generated.c'
            files=dict(value['files'])
            for path in [BINARY,BUILD,READY,emitted,Path(built['artifact']),CACHE/'entries'/built['cache_key']/'manifest.json',*[Path(r['path'])for r in built['dependencies']]]:files[str(path.absolute())]=pin(path)
            exclusive(CONSUMER,sealed({'schema':1,'files':files,'ready_seal':value['seal_sha256'],'build_receipt':pin(BUILD),'emitted_C':pin(emitted)}))
            verify_build(require_completion=False);summary={'status':'built-behavior-unverified','binary':pin(BINARY),'receipt':pin(BUILD),'consumer':pin(CONSUMER),
                'native_dependencies':len(built['dependencies']),'emitted_C':pin(emitted),'timings':built['timings'],'retries':0}
        exclusive(BUILD_RESULT,summary);print(json.dumps(summary),flush=True)
    except BaseException as cause:failure(directory/'first-failure.json',cause,last_execution=LAST_EXECUTION,process=process);raise

def native():
    value=audit();receipt,manifest=verify_build();unused(WORK/'native-attempt');directory=WORK/'native-attempt';directory.mkdir()
    data=json.loads(F.FIXTURE.read_bytes());runs=[]
    try:
        with execution_scope(directory),parent_cleanup(directory):
            for index in range(2):
                rows,excluded,actual_receipts=F.corpus(data,'run'+str(index)+'-case')
                policies,policy_receipts=F.policies(data,'run'+str(index)+'-policy-')
                remap_path=directory/('run'+str(index)+'-remap');unused(remap_path);remap_path.mkdir()
                with bindings(F,{'WORK':remap_path}):remap,remap_receipts=F.remap(data,'run'+str(index)+'-remap-')
                # Fresh per-run directories prevent frozen remap's write_text from overwriting.
                # Compare every registry content fingerprint; only its private run path differs.
                result={'rows':rows,'excluded':excluded,'policies':policies,
                    'remap':{**remap,'registry':{k:v for k,v in remap['registry'].items()if k!='path'}}}
                require(len(rows)==107 and len(policies)==29 and len(remap['rows'])==14,'Incomplete native corpus')
                process_receipts=actual_receipts+policy_receipts+remap_receipts;require(len(process_receipts)==150,'Missing native process receipts')
                exclusive(directory/('run'+str(index)+'.json'),{'status':'passed','result':result,'result_sha256':F.digest(result),'processes':process_receipts,'remap_registry':remap['registry']})
                runs.append(result);print(json.dumps({'phase':'native-run-complete','run':index,'actual':107,'policies':29,'remap':14,'processes':150}),flush=True)
            require(runs[0]==runs[1],'Native rerun differs');audit();verify_build()
            summary={'status':'passed','ready_seal':value['seal_sha256'],'binary':pin(BINARY),'native_runs':2,
                'actual_cases_per_run':107,'policies_per_run':29,'remap_per_run':14,'native_processes':300,
                'result_sha256':F.digest(runs[0]),'runs':[pin(directory/('run'+str(i)+'.json'))for i in range(2)],'proof_attempted':False}
        exclusive(ROOT/'evidence/fall-reset-world-continuation-native.json',summary);print(json.dumps(summary),flush=True)
    except BaseException as cause:failure(directory/'first-failure.json',cause,last_execution=LAST_EXECUTION);raise

def proof():
    value=audit();unused(WORK/'proof-attempt');directory=WORK/'proof-attempt';directory.mkdir();process=None
    try:
        with execution_scope(directory),parent_cleanup(directory):
            out,err,process,process_pin=execute_process([str(F.BEND),str(F.HARNESS),'--verdict'],'full-harness-verdict',60)
            F.require_execution(process)
            audit();summary={'status':'passed','ready_seal':value['seal_sha256'],'process':process_pin,'scope':'One full unchanged harness --verdict; no unsafe/foreign refusal is reclassified as proof.'}
        exclusive(ROOT/'evidence/fall-reset-world-continuation-proof.json',summary);print(json.dumps(summary),flush=True)
    except BaseException as cause:failure(directory/'first-failure.json',cause,process=process,last_execution=LAST_EXECUTION);raise

def inert_controls(directory):
    """File-only/fake objects; no actual child, signal, compiler or game oracle."""
    directory.mkdir(exist_ok=False);results=[]
    def passed(name):results.append({'id':name,'status':'passed'})
    class Ops:
        def __init__(self,errors=()):self.errors=set(errors);self.calls=[]
        def action(self,pgid,stage):
            self.calls.append((pgid,stage))
            if(pgid,stage)in self.errors:raise PermissionError('inert EPERM')
        def probe(self,p):self.action(p,'probe');return True
        def term(self,p):self.action(p,'TERM')
        def kill(self,p):self.action(p,'KILL')
        def wait(self,p,d):self.action(p,'wait')
    ops=Ops({(100,'probe'),(100,'TERM'),(100,'KILL'),(100,'wait')})
    report=sweep([100,200],directory/'eperm.json',ops=ops)
    require(report['status']=='failed'and(200,'probe')in ops.calls and report['unknown_groups']==[100],'EPERM skipped/unknown accepted');passed('EPERM-continues-all-groups-unknown-rejects')
    original=F.WORK
    with bindings(F,{'WORK':directory}):require(F.WORK==directory,'Scope not active')
    require(F.WORK is original,'Normal scope not restored');passed('binding-normal-restoration')
    try:
        with bindings(F,{'WORK':directory}):raise Refused('inert semantic error')
    except Refused:pass
    require(F.WORK is original,'Exceptional scope not restored');passed('binding-exception-restoration')
    class Builder:
        class InputsChanged(RuntimeError):pass
    builder=Builder();original_retry=builder.InputsChanged;calls=[]
    try:
        with retry_scope(builder):
            for _ in range(3):
                calls.append('prepare')
                try:raise builder.InputsChanged('inert input drift')
                except builder.InputsChanged:continue
    except UnretriedInputDrift:pass
    require(calls==['prepare']and builder.InputsChanged is original_retry,'Builder internally retried/not restored');passed('constructor-abort-one-call-no-retry-restored')
    import build_native as actual_builder
    calls=[];original_prepare=actual_builder._prepare;original_exception=actual_builder.InputsChanged
    def inert_drift(*args,**kwargs):calls.append('prepare');raise actual_builder.InputsChanged('inert actual-builder drift')
    try:
        with bindings(actual_builder,{'_prepare':inert_drift}),retry_scope(actual_builder):
            actual_builder.ensure_native(F.HARNESS,directory/'never-produced',bend=F.BEND,cache_dir=directory/'inert-cache',force=True)
    except UnretriedInputDrift:pass
    else:raise Refused('Actual builder swallowed input-drift refusal')
    require(calls==['prepare']and actual_builder._prepare is original_prepare and actual_builder.InputsChanged is original_exception,
        'Actual builder retry/scoped bindings changed');passed('actual-ensure-native-inert-prepare-one-call-no-emission')
    owned=directory/'semantic';owned.mkdir();original_groups=list(GROUPS);GROUPS.clear();GROUPS.extend([{'pgid':100},{'pgid':200}])
    try:
        try:
            with parent_cleanup(owned,ops=Ops({(100,'probe')})):raise Refused('first semantic failure')
        except Refused as error:require(str(error)=='first semantic failure','Cleanup masked semantic failure')
        require(json.loads((owned/'final-cleanup.json').read_bytes())['status']=='failed','Cleanup error not retained');passed('semantic-first-failure-and-unconditional-cleanup')
    finally:GROUPS[:]=original_groups
    class Process:
        pid=300
        returncode=0
        def wait(self,timeout):return self.returncode
    def factory(*args,**kw):
        kw['stdout'].write(b'raw\x00\r\n');kw['stderr'].write(b'err\r\n');return Process()
    def noop(*args,**kw):return None
    with execution_scope(directory):
        out,err,execution,_=execute_process(['inert-not-executed'],'capture',120,_popen=factory,_snapshot=lambda p,k:[],_ops=Ops(),_admit=noop)
        require(out=='raw\x00\r\n'and err=='err\r\n'and execution['status']=='passed','Raw capture differs')
        require(json.loads((directory/'owned-groups.jsonl').read_text().splitlines()[0])['pid']==300,'PID not durable');passed('PID-journal-and-raw-CRLF-NUL')
        _,_,execution,_=execute_process(['inert-not-executed'],'cleanup-failure',120,_popen=factory,_snapshot=lambda p,k:[],_ops=Ops({(300,'probe')}),_admit=noop)
        require(execution['status']=='failed'and execution['cleanup']['unknown_groups']==[300]and (directory/'processes/cleanup-failure/execution.json').exists(),'Cleanup failure lost PID/process receipt');passed('cleanup-EPERM-retains-process-raw-and-rejects')
        def launch_error(*args,**kw):raise OSError('inert launch refusal')
        _,_,execution,_=execute_process(['inert-not-executed'],'launch-failure',120,_popen=launch_error,_snapshot=lambda p,k:[],_ops=Ops(),_admit=noop)
        require(execution['status']=='failed'and execution['pid']is None,'Empty journal accepted');passed('launch-failure-empty-journal-never-pass')
        def discovered(p,k):k[400]=400;return []
        _,_,execution,_=execute_process(['inert-not-executed'],'secondary-group',120,_popen=factory,_snapshot=discovered,_ops=Ops({(300,'probe')}),_admit=noop)
        require(execution['observed_groups']==[300,400]and any(r['pgid']==400 for r in GROUPS),
            'Observed secondary group not registered')
        rows=[json.loads(line)for line in JOURNAL.read_text().splitlines()]
        require(any(r['pgid']==400 for r in rows),'Secondary group missing durable journal');passed('discovered-secondary-group-durable-and-visited')
        class BadProcess(Process):
            returncode=7
        _,_,execution,_=execute_process(['inert-not-executed'],'nonzero',120,_popen=lambda *a,**kw:BadProcess(),_snapshot=lambda p,k:[],_ops=Ops(),_admit=noop)
        require(execution['status']=='failed'and execution['exit_code']==7,'Nonzero accepted');passed('nonzero-receipt-before-comparison')
        class TimedProcess(Process):
            returncode=None
            def wait(self,timeout):raise subprocess.TimeoutExpired('inert-not-executed',timeout)
        class Clock:
            def __init__(self):self.calls=0
            def __call__(self):self.calls+=1;return 0. if self.calls<=2 else 121.
        _,_,execution,_=execute_process(['inert-not-executed'],'timeout',120,_popen=lambda *a,**kw:TimedProcess(),
            _snapshot=lambda p,k:[],_ops=Ops(),_admit=noop,_clock=Clock())
        require(execution['timed_out']and execution['status']=='failed'and execution['cap_seconds']==120,'Deadline failure accepted');passed('fixed-cap-timeout-unconditional-process-receipt')
        def invalid_utf8(*args,**kw):kw['stdout'].write(b'\xff');return Process()
        try:execute_process(['inert-not-executed'],'invalid-utf8',120,_popen=invalid_utf8,_snapshot=lambda p,k:[],_ops=Ops(),_admit=noop)
        except UnicodeDecodeError:pass
        else:raise Refused('UTF8 corruption accepted')
        require((directory/'processes/invalid-utf8/execution.json').exists()and(directory/'processes/invalid-utf8/stdout').read_bytes()==b'\xff','Decode failure lost raw/process');passed('decode-failure-receipt-before-assertion')
        try:execute_process(['inert-not-executed'],'capture',120,_popen=factory,_admit=noop)
        except FileExistsError:pass
        else:raise Refused('Existing attempt overwritten')
        passed('exclusive-attempt-refuses-overwrite')
    require(F.WORK is original,'Frozen route drift')
    sample=directory/'seal.json';exclusive(sample,sealed({'files':{},'value':1}));load_seal(sample)
    broken=directory/'broken-seal.json';exclusive(broken,{'files':{},'value':2,'seal_sha256':load_seal(sample)['seal_sha256']})
    try:load_seal(broken)
    except Refused:pass
    else:raise Refused('Corrupt seal accepted')
    passed('corrupt-seal-refuses-read-only')
    called=[];module=sys.modules[__name__]
    routes={'prepare':lambda:called.append('prepare'),'build':lambda:called.append('build'),
        'native':lambda:called.append('native'),'proof':lambda:called.append('proof')}
    with bindings(module,routes):
        for option,expected in [('prepare','prepare'),('build-only','build'),('native-only','native'),('proof-only','proof')]:
            called.clear();main(['--'+option]);require(called==[expected],'Implicit mode/fallback route: '+option)
        called.clear()
        with contextlib.redirect_stderr(io.StringIO()):
            try:main(['--build-only','--native-only'])
            except SystemExit as error:require(error.code==2,'Invalid mutual exclusion status')
            else:raise Refused('Multiple execution modes accepted')
        require(not called,'Execution happened before mutual-exclusion rejection')
    passed('separate-mode-routing-no-implicit-fallback')
    require(all(getattr(module,name)is not fn for name,fn in routes.items()),'Mode scopes not restored');passed('mode-route-exception-normal-restoration')
    functions={n.name:n for n in ast.parse(Path(__file__).read_text()).body if isinstance(n,ast.FunctionDef)}
    for name in ['build','native','proof']:
        block=next(node for node in functions[name].body if isinstance(node,ast.Try))
        scoped=next(node for node in block.body if isinstance(node,ast.With))
        publish=[node for node in block.body if isinstance(node,ast.Expr)and isinstance(node.value,ast.Call)
            and isinstance(node.value.func,ast.Name)and node.value.func.id=='exclusive']
        require(publish and all(node.lineno>scoped.end_lineno for node in publish),'Success publication precedes final cleanup: '+name)
    passed('build-native-proof-success-only-after-parent-cleanup')
    result={'status':'passed','controls':results,'count':len(results),'scope':'Inert objects/files only; no process launch, OS signal or production outcome acceptance.'}
    exclusive(directory/'controls.json',result);return result

def prepare():
    unused(WORK,ROOT/'evidence/fall-reset-world-continuation-preparation.json');adoption=frozen_admission()
    require(pin(BLOCKER)['sha256']==BLOCKER_SHA,'Independent blocker receipt differs')
    WORK.mkdir();controls=inert_controls(WORK/'inert-controls')
    paths={Path(row['lookup'])for row in adoption['sealed_files']}
    paths.update(Path(path)for path in adoption['generation']);paths.update(ROOT/path for path in adoption['tools'])
    paths.update([FROZEN,F.SOURCE,F.HARNESS,F.FIXTURE,F.TABLE,F.ADOPTION,F.BEND,DOC,Path(__file__),Path(sys.executable),BLOCKER,RETRY_WITNESS])
    for parent in [F.ADOPTION_WORK,F.WORK]:
        paths.update(path for path in parent.rglob('*')if path.is_file())
    paths.update(ROOT.glob('evidence/fall-reset-world-*.json'))
    history={'schema':1,'files':{str(p.absolute()):pin(p)for p in sorted(paths,key=str)if p!=Path(__file__)and p!=DOC},
        'scope':'Original paths are preserved and hashed; no duplicate native/resource/class payload trees.'}
    exclusive(WORK/'history.json',sealed(history));paths.update([WORK/'history.json',WORK/'inert-controls/controls.json'])
    files={str(p.absolute()):pin(p)for p in sorted(paths,key=str)}
    quick=[Path(__file__),FROZEN,ROOT/'tools/build_native.py',F.SOURCE,F.HARNESS,F.FIXTURE,F.TABLE,F.BEND]
    value=sealed({'schema':1,'status':'prepared-audit-only','files':files,'quick_files':{str(p.absolute()):pin(p)for p in quick},
        'ast':ast_contract(),'retry_strategy':retry_contract(),'generation':adoption['generation'],'adoption':pin(F.ADOPTION),'blocker':pin(BLOCKER),
        'controls':pin(WORK/'inert-controls/controls.json'),'future':{'one_build_seconds':600,'per_native_seconds':120,'one_full_harness_verdict_seconds':60,
            'cleanup_seconds':5,'actual_cases_per_run':107,'policies_per_run':29,'remap_per_run':14,'native_runs':2,'native_processes':300},
        'execution_attempted':False,'scopes':['F.BINARY','F.WORK','F.ATTEMPT','F.SEALED','F.execute_process','F.checked_seal','F.LAST_EXECUTION','builder.InputsChanged'],
        'commands':{mode:'PYTHONDONTWRITEBYTECODE=1 python3 tools/test_fall_reset_world_continuation.py --'+mode for mode in ['audit','build-only','native-only','proof-only']}})
    exclusive(READY,value);audit()
    summary={'status':'prepared-not-executed','runner':pin(Path(__file__)),'ready':pin(READY),'payload_seal':value['seal_sha256'],
        'file_count':len(files),'source_count':len(adoption['generation']),'protected_functions':len(PROTECTED),'controls':controls,
        'blocker':pin(BLOCKER),'future':value['future'],'scope':'No Bend compiler, native, kernel, JVM/Java or UI invocation. Split execution needs separate lead grants.'}
    exclusive(ROOT/'evidence/fall-reset-world-continuation-preparation.json',summary);print(json.dumps(summary),flush=True)

def main(argv=None):
    argv=sys.argv[1:]if argv is None else argv
    if len(argv)==2 and argv[0]=='--_build-child':build_child(Path(argv[1]));return
    parser=argparse.ArgumentParser(description=__doc__);modes=parser.add_mutually_exclusive_group(required=True)
    for mode in ['prepare','audit','build-only','native-only','proof-only']:modes.add_argument('--'+mode,action='store_true')
    args=parser.parse_args(argv)
    if args.prepare:prepare()
    elif args.audit:
        value=audit();print(json.dumps({'status':'passed','file_count':len(value['files']),'source_count':len(value['generation']),'ready':pin(READY),'payload_seal':value['seal_sha256'],'scope':'Read-only file admission; no execution/regeneration.'}),flush=True)
    elif args.build_only:build()
    elif args.native_only:native()
    else:proof()

if __name__=='__main__':
    try:main()
    except BaseException as cause:
        if isinstance(cause,SystemExit):raise
        print(json.dumps({'status':'failed','type':type(cause).__name__,'error':str(cause)}),file=sys.stderr,flush=True);raise SystemExit(1)
