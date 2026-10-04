#!/usr/bin/env python3
"""Fresh composite generation after the sole due_wall fixture stamp correction.

Only admission, exclusive receipts and bounded process routing live here. All
Session scenarios, independent expectations and native comparators are imported
unchanged. Preparation/audit do not run Bend, Java, native code or a kernel.
"""
from __future__ import annotations
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import sys
import types
import signal
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'build/local-player-session-continuation-r2'
READY=WORK/'prepared.json'
HISTORY=WORK/'history.json'
SERVER=WORK/'local-player-session-native'
RECEIPT=WORK/'native-build.json'
CONSUMER=WORK/'consumer-manifest.json'
ATTEMPT=WORK/'native-attempt'
OLD_WORK=ROOT/'build/local-player-session'
OLD_HARNESS=OLD_WORK/'phase-fixture-fix/original-tests/local_phase_runtime.bend'
HARNESS=ROOT/'tests/local_phase_runtime.bend'
OLD_H='73015803d85a2008866661d06bf9c5c971ae79de91193ff3055cf6b94e206e8c'
NEW_H='9589c37194a807e01b3ac27eb4e83935ceaec4fba544b6fb05b00b1a9a2aeb22'
OLD_NATIVE='1958e777c0d7ddf96ef9f984484f221acb5a3f6f728e03a1643e9eb6b68fd95d'
FROZEN={
    'tools/test_local_player_session_continuation.py':'7b3f308b5a03b3d199b9e6bae7bb9127ab5e2e6b6277e98fd9f7b9665a684bf0',
    'build/local-player-session-continuation/prepared.json':'fe09251dd9686d68bf02c9eb3385da97f81f90dacf0fa38b47311bb63653f6f4',
    'build/local-player-session-continuation/history.json':'e2c683100fd871ae6b86d4dec9fab0746b10b6b9494c6e70a2b976d9a4b9b52e',
    'build/local-player-session-continuation/host-guards.json':'af4bfaad84ddecf6e0dca1ea4aef34a607874b1d1c74f0c6e8ab6b2328c03c18',
    'evidence/local-player-session-continuation-prepared.json':'bcffd1a3aaf1dca884b6ef2574cfad3ae284b03bfdd526a7d149f3c99dc618fc',
    'evidence/local-player-session-continuation-admission-r1.json':'2a01bea5e2dd67f39fef3a0b3a0e46be83de4d7126e17b0cd43cd83e0ee85bb0',
    'tests/local_player_session.bend':'2081023f80df39c92ebbe11a2b19083b73bfe234cc193866521b1a13a0f198d6',
    'tools/test_local_player_session.py':'ffa2d9d7105b2fd1eb0b1e3bbace195f3dceed75bdbe80e8814349df3545b2c1',
    'tools/test_local_phase_runtime.py':'4c2105a6f6283394bbd794e8db7ef9fd667ab35b85f5968b4dbe21c133bbb69d',
    'tools/test_local_player_record_consumer.py':'ffc83f4f1913d4982bc3a9f87dae4f58e72dbe5cbccc517a3545f60ad6ec33f8',
    'build/local-player-session/native-build.json':'edb3318feec34078b0c5b7e9dd9c12593e2757de79faa43cfffa21126b857ef6',
    'build/local-player-session/phase-fixture-fix/archive-manifest.json':'d811a3ff7a993244f2ff6afe1e3c2d6bbe0a16b1b836271496900b1bba7b2e7b',
}

def digest(data):return hashlib.sha256(data).hexdigest()
def require(condition,message):
    if not condition:raise RuntimeError(message)
def bootstrap():
    require(sys.flags.optimize==0,'Assertions disabled')
    for name,expected in FROZEN.items():require(digest((ROOT/name).read_bytes())==expected,'Frozen input changed: '+name)
bootstrap()
import test_local_player_session as S
import test_local_phase_runtime as Phase
import test_local_player_record_consumer as Record

_LOCAL=(S.SERVER,S.OWNED_GROUPS,S.activation)
_PHASE=Phase.phase_contract
_RECORD=Record.bounded_batch
_IMPORT_PIN=S.pin(Path(__file__))

def unused(*paths):
    require(not any(Path(p).exists() for p in paths),'Existing attempt/output; refuse overwrite')

def stamp_delta(before=None,after=None):
    before=OLD_HARNESS.read_bytes() if before is None else before
    after=HARNESS.read_bytes() if after is None else after
    require(digest(before)==OLD_H and digest(after)==NEW_H,'Unapproved phase harness bytes')
    old=b'Q.Stamp{0n,8,1n}';new=b'Q.Stamp{1n,8,1n}'
    region=before[before.index(b'def due_wall('):before.index(b'def fixture_extra(')]
    require(region.count(old)==1 and before.count(old)==1,'Ambiguous due_wall stamp')
    require(after==before.replace(old,new,1),'Phase delta exceeds sole approved stamp')
    return {'old':S.pin(OLD_HARNESS),'current':S.pin(HARNESS),'old_term':old.decode(),'new_term':new.decode(),
        'changed_bytes':1,'definition':'due_wall','ordinary':S.pin(OLD_WORK/'phase-fixture-fix/ordinary.json')}

def corrected_phase_contract():
    # Preserve every original admission check. Only the historical harness is
    # resolved to its archived bytes; the actual corrected harness is separate.
    require(sys.flags.optimize==0,'Frozen comparator assertions are disabled')
    require(Phase.pin(Path(Phase.__file__))==Phase._ADAPTER_IMPORT_PIN,'Imported phase adapter changed')
    require(Phase.pin(Phase.PREPARATION)['sha256']==Phase.READY_PREPARATION_SHA256,'Original phase preparation changed')
    prepared=json.loads(Phase.PREPARATION.read_bytes())
    require(prepared['status']=='ordinary-prepared-native-kernel-pending','Original phase preparation failed')
    require(len(prepared['generation'])==80 and Phase.sha(prepared['generation'])==Phase.READY_GENERATION_SHA256,'Original phase80 manifest changed')
    historical={};current={}
    for name,value in prepared['generation'].items():
        path=Path(name);expected=Phase.ADDITIVE_SOURCE_SHA256 if path==Phase.SOURCE else value
        actual=S.pin(OLD_HARNESS if path==HARNESS else path)
        require(actual['sha256']==expected,'Phase dependency changed: '+name)
        historical[name]=actual['sha256'];current[name]=NEW_H if path==HARNESS else actual['sha256']
    require(Phase.pin(Phase.SOURCE)['sha256']==Phase.ADDITIVE_SOURCE_SHA256,'Additive phase source changed')
    for label,path in [('harness',HARNESS),('reference',Phase.REFERENCE),('table',Phase.TABLE)]:
        observed=Phase.pin(OLD_HARNESS if label=='harness' else path)
        if label=='harness':observed=dict(observed,path=prepared[label]['path'])
        require(observed==prepared[label],'Frozen historical phase '+label+' changed')
    require(Phase.fingerprint(Phase.BEND)==prepared['ordinary'][0]['compiler'],'Phase compiler changed')
    producers={}
    for name,value in prepared['tools'].items():
        if name!='tools/test_local_phase_runtime.py':
            require(Phase.pin(ROOT/name)==value,'Frozen phase producer/helper changed: '+name);producers[name]=value
    contents=Path(Phase.__file__).read_text()
    comparison=contents[contents.index('def words(raw):'):contents.index('# Read-only adapter for the final consumer executable')]
    require(digest(comparison.encode())==Phase.FROZEN_COMPARISON_SHA256,'Frozen phase comparator span changed')
    lineage=stamp_delta();ordinary=json.loads((OLD_WORK/'phase-fixture-fix/ordinary.json').read_bytes())
    require(ordinary['status']=='PASS' and ordinary['exit_code']==0 and not ordinary['timed_out'] and ordinary['cleanup']['clean'],
        'Corrected phase ordinary admission failed')
    require(ordinary['harness_after']['sha256']==NEW_H and ordinary['sole_textual_change_verified'],'Corrected phase ordinary lineage differs')
    return {'status':'phase-comparison-contract-verified-corrected-harness','original_preparation':Phase.pin(Phase.PREPARATION),
        'original_generation_sha256':Phase.READY_GENERATION_SHA256,'historical_phase_generation':historical,'phase_generation':current,
        'source':Phase.pin(Phase.SOURCE),'harness':Phase.pin(HARNESS),'reference':Phase.pin(Phase.REFERENCE),'table':Phase.pin(Phase.TABLE),
        'compiler':Phase.fingerprint(Phase.BEND),'producers':producers,'adapter':Phase._ADAPTER_IMPORT_PIN,
        'comparison_sha256':Phase.FROZEN_COMPARISON_SHA256,'corrected_harness_lineage':lineage,
        'scope':'Only due_wall fixture stamp0->1 is admitted; all original complete comparisons remain required.'}

@contextlib.contextmanager
def phase_scope():
    require(Phase.phase_contract is _PHASE,'Phase admission binding drift before scope')
    Phase.phase_contract=corrected_phase_contract
    try:yield
    finally:
        installed=Phase.phase_contract;Phase.phase_contract=_PHASE
        require(Phase.phase_contract is _PHASE and installed is corrected_phase_contract,'Phase admission binding drift inside scope')

@contextlib.contextmanager
def local_scope(journal=None):
    require((S.SERVER,S.OWNED_GROUPS,S.activation)==_LOCAL,'Local routing binding drift before scope')
    S.SERVER,S.OWNED_GROUPS,S.activation=SERVER,journal,audit
    try:yield
    finally:
        installed=(S.SERVER,S.OWNED_GROUPS,S.activation)
        S.SERVER,S.OWNED_GROUPS,S.activation=_LOCAL
        require((S.SERVER,S.OWNED_GROUPS,S.activation)==_LOCAL and installed==(SERVER,journal,audit),'Local routing binding drift inside scope')

class GroupOps:
    """Real owned-group operations; inert tests supply a separate local object."""
    @staticmethod
    def probe(pid):return S.group_absent(pid)
    @staticmethod
    def kill(pid):
        try:os.killpg(pid,signal.SIGKILL);return 'SIGKILL-sent'
        except ProcessLookupError:return 'already-absent'
    @staticmethod
    def term(pid):
        try:os.killpg(pid,signal.SIGTERM);return 'SIGTERM-sent'
        except ProcessLookupError:return 'already-absent'
    @staticmethod
    def wait(pid,deadline):
        reaped=[]
        while True:
            try:
                while True:
                    child,status=os.waitpid(-pid,os.WNOHANG)
                    if not child:break
                    reaped.append({'pid':child,'status':status})
            except ChildProcessError:pass
            if S.group_absent(pid):return {'group_absent':True,'reaped':reaped}
            if time.monotonic()>=deadline:return {'group_absent':False,'reaped':reaped,'deadline_expired':True}
            time.sleep(.02)

def error_text(cause):return type(cause).__name__+': '+str(cause)

def group_sweep(rows,path,*,ops=None,initial_errors=(),deadline=None):
    """Persist every PID, including errors/unknown states, and visit later rows."""
    ops=GroupOps if ops is None else ops;results=[];errors=list(initial_errors)
    for source in rows:
        row=dict(source,absent_before_parent_cleanup=None,absent_after_parent_cleanup=None,errors=[])
        pid=row.get('pid')
        if type(pid) is not int or pid<=0:
            row['errors'].append({'stage':'pid','error':'Invalid owned PID'});results.append(row);continue
        for stage in ('before','kill','wait','after'):
            if stage in ('kill','wait') and row['absent_before_parent_cleanup'] is True:continue
            try:
                if stage=='before':row['absent_before_parent_cleanup']=ops.probe(pid)
                elif stage=='after':row['absent_after_parent_cleanup']=ops.probe(pid)
                elif stage=='kill':row['kill']=ops.kill(pid)
                else:row['wait']=ops.wait(pid,time.monotonic()+5 if deadline is None else deadline)
            except BaseException as cause:row['errors'].append({'stage':stage,'error':error_text(cause)})
        # None is an unknown observation, never an absence assertion.
        row['status']='PASS' if not row['errors'] and row['absent_after_parent_cleanup'] is True else 'FAIL'
        results.append(row)
    value={'status':'PASS' if not errors and all(r.get('status')=='PASS' for r in results) else 'FAIL',
        'owned_groups':results,'journal_errors':errors,'unknown_is_absent':False}
    S.exclusive_json(path,value);return value

def sweep_directory(directory,label,*,ops=None):
    rows=[];errors=[];seen={}
    for journal in sorted(directory.rglob('*owned-groups.jsonl')):
        try:lines=journal.read_bytes().splitlines()
        except BaseException as cause:errors.append({'path':str(journal),'error':error_text(cause)});continue
        for index,line in enumerate(lines):
            try:
                row=json.loads(line);require(type(row.get('pid')) is int and row['pid']>0,'Malformed PID journal')
                row=dict(row,source=str(journal),line=index);rows.append(row)
            except BaseException as cause:errors.append({'path':str(journal),'line':index,'error':error_text(cause)})
    for path in sorted([*directory.rglob('*.process.json'),*directory.rglob('*.launched.json')]):
        try:
            value=json.loads(path.read_bytes());pid=value.get('pid')
            if pid is not None:
                require(type(pid) is int and pid>0,'Malformed process PID');rows.append({'pid':pid,'label':path.stem,'source':str(path)})
        except BaseException as cause:errors.append({'path':str(path),'error':error_text(cause)})
    for row in rows:
        if row['pid'] in seen:seen[row['pid']]['registrations'].append(row)
        else:seen[row['pid']]={'pid':row['pid'],'registrations':[row]}
    return group_sweep(list(seen.values()),directory/(label+'.json'),ops=ops,initial_errors=errors)

@contextlib.contextmanager
def parent_cleanup(directory,label,*,ops=None):
    # The frozen Record verifier may refuse before creating its directory.
    # An empty directory preserves its admission; receipts are written on exit.
    directory.mkdir(parents=True,exist_ok=True)
    cause=None
    try:yield
    except BaseException as error:cause=error;raise
    finally:
        result=sweep_directory(directory,label,ops=ops)
        if result['status']!='PASS':
            failure(directory/(label+'.first-failure.json'),RuntimeError('Owned group cleanup incomplete'),
                cleanup=S.pin(directory/(label+'.json')),original_error=error_text(cause) if cause else None)
            if cause is None:raise RuntimeError('Owned group cleanup incomplete: '+str(directory/(label+'.json')))

def codec_bounded_batch(argv,timeout,directory,label):
    return codec_batch(argv,timeout,directory,label)

def codec_batch(argv,timeout,directory,label,*,launch=subprocess.Popen,ops=None):
    """Same frozen120/TERM2/KILL5 protocol; retain PID/receipt even on cleanup errors."""
    require(timeout==120,'Frozen codec120s cap changed');ops=GroupOps if ops is None else ops
    stdout=directory/(label+'.stdout');stderr=directory/(label+'.stderr');receipt=directory/(label+'.process.json')
    unused(stdout,stderr,receipt,directory/(label+'.attempt.json'),directory/(label+'.launched.json'))
    argv=list(map(str,argv));start=time.monotonic();timed=False;proc=None;rc=None;launch_error=None;cleanup_errors=[];sweep=None
    Record.persist(directory/(label+'.attempt.json'),{'argv':argv,'timeout_seconds':timeout})
    def attempt(stage,call,*,missing_ok=False):
        try:return call()
        except ProcessLookupError as cause:
            if not missing_ok:cleanup_errors.append({'stage':stage,'error':error_text(cause)})
        except BaseException as cause:cleanup_errors.append({'stage':stage,'error':error_text(cause)})
    with stdout.open('xb') as out,stderr.open('xb') as err:
        try:
            proc=launch(argv,cwd=ROOT,start_new_session=True,stdout=out,stderr=err)
            # Journal is durable immediately after launch, before the first wait.
            with (directory/'codec-owned-groups.jsonl').open('ab') as journal:
                journal.write(S.canonical({'pid':proc.pid,'label':label})+b'\n');journal.flush();os.fsync(journal.fileno())
            Record.persist(directory/(label+'.launched.json'),{'argv':argv,'pid':proc.pid,'pgid':proc.pid,'timeout_seconds':timeout})
            try:rc=proc.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed=True;attempt('TERM',lambda:ops.term(proc.pid),missing_ok=True)
                try:rc=proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    attempt('timeout-KILL',lambda:ops.kill(proc.pid));rc=attempt('timeout-KILL-wait5',lambda:proc.wait(timeout=5))
        except BaseException as cause:launch_error=error_text(cause)
        finally:
            if proc is not None:
                deadline=time.monotonic()+5;attempt('final-KILL',lambda:ops.kill(proc.pid))
                live=attempt('leader-poll',proc.poll)
                if live is None:rc=attempt('final-leader-wait5',lambda:proc.wait(timeout=max(0,deadline-time.monotonic())))
                else:rc=live
                try:sweep=group_sweep([{'pid':proc.pid,'label':label}],directory/(label+'.cleanup.json'),ops=ops,deadline=deadline)
                except BaseException as cause:cleanup_errors.append({'stage':'group-sweep-receipt','error':error_text(cause)})
    result={'argv':argv,'timeout_seconds':timeout,'timed_out':timed,'exit_code':rc,'launch_error':launch_error,
        'seconds':time.monotonic()-start,'pid':proc.pid if proc else None,'stdout':Record.pin(stdout),'stderr':Record.pin(stderr),
        'cleanup_errors':cleanup_errors,'cleanup':Record.pin(directory/(label+'.cleanup.json')) if sweep else None,
        'group_absent':bool(sweep and sweep['status']=='PASS')}
    Record.persist(receipt,result)
    if cleanup_errors or (sweep and sweep['status']!='PASS'):
        raise RuntimeError('Frozen codec supervisor cleanup failed: '+str(receipt))
    return result,stdout.read_text(errors='replace'),stderr.read_text(errors='replace')

@contextlib.contextmanager
def codec_scope():
    require(Record.bounded_batch is _RECORD,'Record supervisor binding drift before scope')
    Record.bounded_batch=codec_bounded_batch
    try:yield
    finally:
        installed=Record.bounded_batch;Record.bounded_batch=_RECORD
        require(Record.bounded_batch is _RECORD and installed is codec_bounded_batch,'Record supervisor binding drift inside scope')

def original_runner(expected):
    paths=[OLD_WORK/'lineage'/name/'tools/test_local_player_session.py' for name in
        ('original-generation','host-adoption-1','diagnostic-candidate-1','host-adoption-2-r2')]
    paths.append(ROOT/'tools/test_local_player_session.py')
    matches=[p for p in paths if S.pin(p)['sha256']==expected['sha256']]
    require(len(matches)==1,'Historical runner does not resolve uniquely');return matches[0]

def historical_file(name,item):
    path=Path(name)
    if path==HARNESS:
        require(item['sha256']==OLD_H,'Unexpected historical harness pin');path=OLD_HARNESS
    elif path==ROOT/'tools/test_local_player_session.py':path=original_runner(item)
    actual=S.pin(path);require(actual['sha256']==item['sha256'] and actual['bytes']==item['bytes'],'Historical input changed: '+name)
    return path

def historical_manifest(path):
    value=json.loads(path.read_bytes());payload={k:v for k,v in value.items() if k!='seal_sha256'}
    require(value.get('schema')==1 and value.get('seal_sha256')==S.sha(S.canonical(payload)),'Invalid historical manifest: '+str(path))
    for name,item in value['files'].items():historical_file(name,item)
    return value

def history_contract():
    bootstrap();stamp_delta()
    manifests=[]
    for directory in [OLD_WORK,*sorted(p for p in OLD_WORK.glob('host-adoption*') if p.is_dir())]:
        for name in ('prepared.json','consumer-manifest.json'):
            p=directory/name;historical_manifest(p);manifests.append(S.pin(p))
    for archive in sorted((OLD_WORK/'lineage').glob('*/archive.json')):
        value=json.loads(archive.read_bytes());payload={k:v for k,v in value.items() if k!='seal_sha256'}
        require(value['seal_sha256']==S.sha(S.canonical(payload)),'Historical archive seal changed')
        for item in value['files'].values():
            actual=S.pin(item['archive_path']);require(actual['sha256']==item['sha256'] and actual['bytes']==item['bytes'],'Archived bytes changed')
    receipt=json.loads((OLD_WORK/'native-build.json').read_bytes());built=receipt['build']
    require(built['binary_sha256']==OLD_NATIVE and built['retries']==0 and len(built['dependencies'])==1693,'Original native generation differs')
    import build_native as builder
    cache=builder._verified(ROOT/'build/native-cache/entries'/built['cache_key'],built['cache_key'])
    require(cache is not None and cache['key_data']['dependencies']==built['dependencies'],'Original native cache/closure differs')
    for name in ('binary_sha256','binary_bytes','emitted_c_sha256','compiler'):require(built[name]==cache[name],'Original native metadata differs: '+name)
    for item in built['dependencies']:historical_file(item['path'],item)
    binary=S.pin(OLD_WORK/'local-player-session-native');require(binary['sha256']==OLD_NATIVE,'Original native bytes changed')
    emitted=ROOT/'build/native-cache/sources'/cache['key_data']['prekey']/'generated.c'
    require(S.pin(emitted)['sha256']==built['emitted_c_sha256'],'Original emitted C differs')
    current=S.sources();expected=dict(receipt['sources_sha256']);expected['tests/local_phase_runtime.bend']=NEW_H
    require(current==expected,'Composite source delta exceeds corrected phase fixture')
    return {'status':'historical-generation-PASS','original_binary':binary,'original_receipt':S.pin(OLD_WORK/'native-build.json'),
        'original_emitted_C':S.pin(emitted),'original_cache_manifest':S.pin(ROOT/'build/native-cache/entries'/built['cache_key']/'manifest.json'),
        'historical_manifests':manifests,'native_dependencies':built['dependencies'],'source_delta':{'tests/local_phase_runtime.bend':{'old':OLD_H,'new':NEW_H}},
        'redirects':'Historical harness only uses archived730158; each old host runner uses its already immutable matching archive.'}

def guards(directory):
    directory.mkdir(parents=True,exist_ok=False)
    results=[]
    class Sentinel(Exception):pass
    for context,bindings in ((phase_scope,lambda:Phase.phase_contract is _PHASE),(local_scope,lambda:(S.SERVER,S.OWNED_GROUPS,S.activation)==_LOCAL)):
        for fail in (False,True):
            try:
                with context():
                    if fail:raise Sentinel('inert scope exception')
            except Sentinel:require(fail,'Unexpected sentinel')
            require(bindings(),'Admission/routing not restored');results.append({'case':context.__name__+('-exception' if fail else '-normal'),'passed':True})
    before=OLD_HARNESS.read_bytes();after=HARNESS.read_bytes();stamp_delta(before,after)
    for name,bad in [('uncorrected',before),('other-stamp',after.replace(b'Q.Stamp{1n,8,1n}',b'Q.Stamp{2n,8,1n}',1)),
                     ('peer-change',after.replace(b'Q.Stamp{1n,8,1n}',b'Q.Stamp{1n,9,1n}',1)),('additional-byte',after+b'\n')]:
        try:stamp_delta(before,bad)
        except RuntimeError:results.append({'case':name,'refused':True})
        else:raise RuntimeError('Delta guard accepted '+name)
    try:unused(OLD_WORK/'native-build.json')
    except RuntimeError:results.append({'case':'existing-output-refused','refused':True})
    else:raise RuntimeError('Existing output guard failed')
    fake=types.SimpleNamespace(InputsChanged=type('InputsChanged',(RuntimeError,),{}));old=fake.InputsChanged;retried=False
    try:
        S.forbid_builder_retry(fake)
        try:
            try:raise fake.InputsChanged('inert drift')
            except old:retried=True
        except S.UnretriedInputDrift:pass
        require(not retried,'InputsChanged retry catch reached');results.append({'case':'input-drift-aborts-before-retry','passed':True})
    finally:fake.InputsChanged=old
    calls=[]
    class InertGroups:
        def __init__(self,bad=None,mode='probe'):self.bad=bad;self.mode=mode
        def probe(self,pid):
            calls.append(('probe',pid))
            if pid==self.bad and self.mode=='probe':raise PermissionError('inert probe EPERM')
            return False if pid==self.bad and self.mode=='kill' else True
        def kill(self,pid):
            calls.append(('kill',pid))
            if pid==self.bad:raise PermissionError('inert kill EPERM')
            return 'inert-KILL'
        def term(self,pid):calls.append(('TERM',pid));return 'inert-TERM'
        def wait(self,pid,deadline):
            calls.append(('group-wait',pid))
            if pid==self.bad:raise PermissionError('inert wait EPERM')
            return {'group_absent':True}
    for mode in ('probe','kill'):
        calls.clear();path=directory/(mode+'-EPERM.json')
        value=group_sweep([{'pid':900001},{'pid':900002}],path,ops=InertGroups(900001,mode))
        require(value['status']=='FAIL' and len(value['owned_groups'])==2,'Inert EPERM sweep failed closed/continued')
        require(value['owned_groups'][1]['status']=='PASS' and ('probe',900002) in calls,'Later PID was skipped')
        if mode=='probe':require(value['owned_groups'][0]['absent_after_parent_cleanup'] is None,'Unknown probe became absent')
        results.append({'case':'first-PID-'+mode+'-EPERM-later-PID-visited','refused':True,'receipt':S.pin(path)})
    class InertProcess:
        pid=900003
        def __init__(self,folder,timeout=False):self.folder=folder;self.returncode=None;self.timeout=timeout;self.waits=[]
        def wait(self,timeout):
            rows=[json.loads(x) for x in (self.folder/'codec-owned-groups.jsonl').read_bytes().splitlines()]
            require(rows[-1]['pid']==self.pid,'PID not journaled before first wait');self.waits.append(timeout)
            if self.timeout and len(self.waits)<3:raise subprocess.TimeoutExpired('inert',timeout)
            self.returncode=0;return 0
        def poll(self):return self.returncode
    for kind in ('normal','timeout','cleanup-EPERM','launch-failure'):
        folder=directory/('codec-'+kind);folder.mkdir();created=[]
        def launch(argv,**kwargs):
            if kind=='launch-failure':raise OSError('inert launch refusal')
            kwargs['stdout'].write(b'host-only\n');kwargs['stderr'].write(b'host-stderr\n')
            proc=InertProcess(folder,kind=='timeout');created.append(proc);return proc
        ops=InertGroups(900003 if kind=='cleanup-EPERM' else None)
        try:
            with codec_scope():value,out,err=codec_batch(['inert-not-executable'],120,folder,'batch',launch=launch,ops=ops)
            require(kind!='cleanup-EPERM','Codec cleanup EPERM was accepted')
            if kind!='launch-failure':require(out=='host-only\n' and err=='host-stderr\n','Raw codec capture/decoding changed')
        except RuntimeError:
            require(kind=='cleanup-EPERM','Unexpected inert codec failure')
        require(Record.bounded_batch is _RECORD,'Codec supervisor failure did not restore frozen binding')
        value=json.loads((folder/'batch.process.json').read_bytes())
        require(value['pid']==(None if kind=='launch-failure' else 900003),'Codec failed to retain launched PID')
        require((folder/'batch.stdout').is_file() and (folder/'batch.stderr').is_file(),'Missing unconditional raw streams')
        if kind=='cleanup-EPERM':require(value['cleanup_errors'] and not value['group_absent'],'Unknown cleanup became absence')
        if kind=='timeout':require(created[0].waits==[120,2,5] and value['timed_out'],'Frozen120/TERM2/KILL5 changed')
        results.append({'case':'codec-'+kind+'-PID-raw-process-retained','passed':True,'receipt':S.pin(folder/'batch.process.json')})
    for fail in (False,True):
        try:
            with codec_scope():
                require(Record.bounded_batch is codec_bounded_batch,'Codec scope not installed')
                if fail:raise Sentinel('inert codec scope exception')
        except Sentinel:require(fail,'Unexpected codec sentinel')
        require(Record.bounded_batch is _RECORD,'Codec binding not restored');results.append({'case':'codec-scope-'+('exception' if fail else 'normal'),'passed':True})
    folder=directory/'parent-failure';folder.mkdir()
    (folder/'owned-groups.jsonl').write_bytes(S.canonical({'pid':900001})+b'\n'+S.canonical({'pid':900002})+b'\n')
    try:
        with parent_cleanup(folder,'final-cleanup',ops=InertGroups(900001)):raise Sentinel('inert semantic failure')
    except Sentinel:pass
    value=json.loads((folder/'final-cleanup.json').read_bytes())
    require(value['status']=='FAIL' and len(value['owned_groups'])==2 and (folder/'final-cleanup.first-failure.json').is_file(),'Parent-finally lost cleanup failure')
    results.append({'case':'semantic-failure-unconditional-parent-sweep','passed':True,'receipt':S.pin(folder/'final-cleanup.json')})
    folder=directory/'parent-success-blocked';folder.mkdir()
    (folder/'owned-groups.jsonl').write_bytes(S.canonical({'pid':900001})+b'\n');published=False
    try:
        with parent_cleanup(folder,'final-cleanup',ops=InertGroups(900001)):pass
        published=True
    except RuntimeError:pass
    require(not published,'Cleanup failure published overall success');results.append({'case':'cleanup-failure-prevents-success-publication','passed':True})
    folder=directory/'parent-before-child-directory'
    try:
        with parent_cleanup(folder,'final-cleanup',ops=InertGroups()):raise Sentinel('inert early verifier refusal')
    except Sentinel as cause:failure(folder/'original-first-failure.json',cause)
    require((folder/'original-first-failure.json').is_file() and json.loads((folder/'final-cleanup.json').read_bytes())['status']=='PASS',
        'Early semantic failure lost original or unconditional cleanup receipt')
    results.append({'case':'early-refusal-before-child-directory-retains-both-receipts','passed':True})
    return {'status':'PASS','controls':results,'builds':0,'native_executions':0,'Java_executions':0,'kernel_executions':0}

def prepare():
    unused(WORK);historical=history_contract();phase=corrected_phase_contract()
    r1=S.audit_manifest(ROOT/'build/local-player-session-continuation/prepared.json')
    S.audit_manifest(ROOT/'build/local-player-session-continuation/history.json')
    WORK.mkdir(exist_ok=False);control=guards(WORK/'inert-controls')
    with phase_scope():paths,closure,class_tree=S.generation_files()
    paths.update(S.tool_closure([Path(__file__)]));paths.add(OLD_HARNESS)
    paths.update(ROOT/name for name in FROZEN);paths.update(Path(name) for name in r1['files'])
    # Preserve the entire existing evidence tree by pinned immutable paths, not
    # another copy of native/C/resource/class payloads.
    preserved={p.resolve() for p in OLD_WORK.rglob('*') if p.is_file()}
    preserved.update(p.resolve() for p in (ROOT/'evidence').glob('local-player-session-*.json'))
    preserved.update((ROOT/'docs/LOCAL_PLAYER_SESSION_TESTS.md',ROOT/'tools/test_local_player_session.py'))
    preserved.update(Path(p['path']) for p in historical['native_dependencies'])
    preserved.discard(HARNESS);preserved.add(OLD_HARNESS)
    history_files={str(p):{k:v for k,v in S.pin(p).items() if k!='path'} for p in sorted(preserved)}
    S.exclusive_json(HISTORY,S.sealed({'schema':1,'files':history_files,'contract':historical,'payload_copy_count':0}))
    S.exclusive_json(WORK/'host-guards.json',control)
    paths.update(preserved);paths.update((HISTORY,WORK/'host-guards.json'))
    paths.update(p for p in (WORK/'inert-controls').rglob('*') if p.is_file())
    paths.update(Path(historical[k]['path']) for k in ('original_binary','original_receipt','original_emitted_C','original_cache_manifest'))
    bridge,bridge_info=S.retained_bridge();paths.update((bridge,S.BASE.RECEIPT))
    paths.update(Path(x['path']) for x in bridge_info['build']['dependencies'])
    # Historical dependency paths include730158; current admission explicitly
    # pins9589 at the actual path and730158 at its archive path.
    paths.add(HARNESS)
    files={str(p.resolve()):{k:v for k,v in S.pin(p).items() if k!='path'} for p in sorted(paths)}
    value=S.sealed({'schema':1,'status':'prepared-new-composite-native-unverified','files':files,'sources_sha256':S.sources(),
        'environment_sha256':S.environment_pin(),'full_Bend_imports':closure,'official_class_tree_sha256':class_tree,
        'phase_contract':phase,'historical_generation':S.pin(HISTORY),'retained_MCP':bridge_info,'entry':S.pin(S.ENTRY),
        'frozen_Local':S.pin(Path(S.__file__)),'runner':_IMPORT_PIN,'host_controls':S.pin(WORK/'host-guards.json'),
        'routing':['S.SERVER','S.OWNED_GROUPS','S.activation','Phase.phase_contract','Record.bounded_batch'],
        'R1':{'ready':S.pin(ROOT/'build/local-player-session-continuation/prepared.json'),
              'blocker':S.pin(ROOT/'evidence/local-player-session-continuation-admission-r1.json'),'payload_copies':0},
        'sequence':['Primary-0','Record755x2','Phase15actual+28policyx2','Facade3guardsx2','Primary-1'],
        'caps_seconds':{'build':600,'native_group':120},'builds':0,'native_executions':0,'Java_executions':0,'kernel_executions':0})
    S.exclusive_json(READY,value);audit()
    summary={'status':value['status'],'ready':S.pin(READY),'seal_sha256':value['seal_sha256'],'runner':_IMPORT_PIN,
        'history':S.pin(HISTORY),'host_controls':S.pin(WORK/'host-guards.json'),'files':len(files),'source_imports':len(closure),
        'phase_harness':S.pin(HARNESS),'composite_entry':S.pin(S.ENTRY),'original_binary':historical['original_binary'],
        'builds':0,'native_executions':0,'Java_executions':0,'kernel_executions':0,
        'commands':['PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_player_session_continuation_r2.py --audit',
                    'PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_player_session_continuation_r2.py --build-only',
                    'PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_player_session_continuation_r2.py --skip-build']}
    S.exclusive_json(ROOT/'evidence/local-player-session-continuation-r2-prepared.json',summary);print(json.dumps(summary),flush=True)

def audit():
    bootstrap();require(S.pin(Path(__file__))==_IMPORT_PIN,'Imported continuation runner changed')
    value=S.audit_manifest(READY)
    require(value['runner']==_IMPORT_PIN and value['sources_sha256']==S.sources(),'Current source/runner generation changed')
    require(value['environment_sha256']==S.environment_pin(),'Current environment generation changed')
    require(value['phase_contract']==corrected_phase_contract(),'Corrected phase admission changed')
    S.audit_manifest(HISTORY)
    require((S.SERVER,S.OWNED_GROUPS,S.activation)==_LOCAL or (S.SERVER==SERVER and S.activation is audit),'Unexpected Local routing state')
    return value

def failure(path,cause,**fields):
    if not path.exists():S.exclusive_json(path,{'status':'FAIL','error':type(cause).__name__+': '+str(cause),**fields})

def execute(argv,cap,directory,label):
    with local_scope():return S.bounded(argv,cap,directory,label)

def build_once(report_path):
    value=audit();require(report_path==WORK/'build-attempt/builder.json','Unexpected builder report path');unused(report_path,SERVER)
    pending=json.loads((WORK/'build-attempt/native-build.attempt.json').read_bytes())
    require(pending['cap_seconds']==600 and pending['argv']==list(map(str,[sys.executable,Path(__file__),'--_build-once',report_path])),
        'Missing bounded parent build reservation')
    unused(WORK/'build-attempt/first-failure.json',WORK/'build-attempt/builder-claim.json')
    S.exclusive_json(WORK/'build-attempt/builder-claim.json',{'pid':os.getpid(),'pgid':os.getpgrp(),'prepared_seal':value['seal_sha256'],'retries_allowed':0})
    import build_native as builder
    original=S.forbid_builder_retry(builder)
    try:report=builder.ensure_native(S.ENTRY,SERVER,bend=S.BEND)
    finally:builder.InputsChanged=original;require(builder.InputsChanged is original,'Builder retry binding not restored')
    require(report['retries']==0,'Builder retry forbidden');audit();S.exclusive_json(report_path,report)
    print(json.dumps({'status':'built','binary_sha256':report['binary_sha256'],'retries':0,'prepared_seal':value['seal_sha256']}),flush=True)

def build():
    value=audit();unused(WORK/'build-attempt',SERVER,RECEIPT,CONSUMER)
    directory=WORK/'build-attempt';directory.mkdir(exist_ok=False);process=None;report=directory/'builder.json'
    try:
        with parent_cleanup(directory,'final-cleanup'):
            process,out,err=execute([sys.executable,Path(__file__),'--_build-once',report],600,directory,'native-build')
            S.process_ok(process);audit();built=json.loads(report.read_bytes());require(built['retries']==0,'Native build retried')
            S.PR.check_receipt(value['sources_sha256'],{'sources_sha256':value['sources_sha256'],'build':built})
            require(S.pin(SERVER)['sha256']==built['binary_sha256'] and built['binary_sha256']!=OLD_NATIVE,'New native artifact identity differs')
            S.exclusive_json(RECEIPT,{'schema':1,'prepared_seal_sha256':value['seal_sha256'],'sources_sha256':value['sources_sha256'],
                'build':built,'process':process,'producer':S.pin(Path(__file__)),'input_ready':S.pin(READY)})
            import build_native as builder
            cached=builder._verified(ROOT/'build/native-cache/entries'/built['cache_key'],built['cache_key']);require(cached is not None,'New native cache invalid')
            emitted=ROOT/'build/native-cache/sources'/cached['key_data']['prekey']/'generated.c'
            files=dict(value['files'])
            paths=[SERVER,RECEIPT,READY,emitted,Path(built['artifact']),ROOT/'build/native-cache/entries'/built['cache_key']/'manifest.json']
            paths.extend(Path(x['path']) for x in built['dependencies'])
            for p in paths:files[str(p.resolve())]={k:v for k,v in S.pin(p).items() if k!='path'}
            S.exclusive_json(CONSUMER,S.sealed({'schema':1,'files':files,'prepared_seal_sha256':value['seal_sha256'],
                'native_build_receipt':S.pin(RECEIPT),'source_generation':value['sources_sha256'],'emitted_C':S.pin(emitted),'compiler':built['compiler']}))
            verify_build();summary={'status':'built-native-unverified','binary':S.pin(SERVER),'receipt':S.pin(RECEIPT),'consumer_manifest':S.pin(CONSUMER),
                'emitted_C':S.pin(emitted),'native_dependencies':len(built['dependencies']),'process':process,'retries':0}
        S.exclusive_json(ROOT/'evidence/local-player-session-continuation-r2-build.json',summary);print(json.dumps(summary),flush=True)
    except BaseException as cause:
        failure(directory/'first-failure.json',cause,process=process,prepared_seal=value['seal_sha256'],
            raw_streams=[S.pin(p) for p in (directory/'native-build.stdout',directory/'native-build.stderr') if p.exists()]);raise

def verify_build():
    value=audit();S.audit_manifest(CONSUMER);receipt=json.loads(RECEIPT.read_bytes())
    require(receipt['prepared_seal_sha256']==value['seal_sha256'] and receipt['sources_sha256']==value['sources_sha256'],'New artifact generation drift')
    S.PR.check_receipt(value['sources_sha256'],receipt)
    require(S.pin(SERVER)['sha256']==receipt['build']['binary_sha256'],'New artifact bytes changed');return receipt

def integration_child(index):
    value=audit();verify_build();require(index in (0,1),'Unknown Primary run')
    pending=json.loads((ATTEMPT/('integration-'+str(index)+'.attempt.json')).read_bytes())
    require(pending['cap_seconds']==120 and pending['argv']==list(map(str,[sys.executable,Path(__file__),'--_integration-run',index])),
        'Missing bounded parent integration reservation')
    directory=ATTEMPT/('integration-'+str(index));directory.mkdir(parents=True,exist_ok=False)
    journal=directory/'owned-groups.jsonl';journal.touch(exist_ok=False);bridge,_=S.retained_bridge()
    with local_scope(journal):S.integration_run(value,bridge,directory)


def native():
    value=audit();receipt=verify_build();unused(ATTEMPT);ATTEMPT.mkdir(exist_ok=False)
    primary=[];lanes=[];codec=None
    try:
        with parent_cleanup(ATTEMPT,'final-cleanup'):
            for index in range(2):
                verify_build();process,out,err=execute([sys.executable,Path(__file__),'--_integration-run',index],120,ATTEMPT,'integration-'+str(index))
                cleanup=sweep_directory(ATTEMPT/('integration-'+str(index)),"lane-cleanup");groups=cleanup['owned_groups']
                summary_path=ATTEMPT/('integration-'+str(index))/'summary.json'
                summary=json.loads(summary_path.read_bytes()) if summary_path.exists() else None
                comparison={'process':process,'owned_groups':groups,'summary':summary};S.exclusive_json(ATTEMPT/('integration-'+str(index)+'.comparison.json'),comparison)
                S.process_ok(process);require(cleanup['status']=='PASS' and all(x['absent_before_parent_cleanup'] is True and x['absent_after_parent_cleanup'] is True for x in groups),'Primary left an unknown/error/process group')
                require(not err and summary and summary['status']=='PASS','Primary integration failed');primary.append(comparison);verify_build()
                if index==0:
                    with codec_scope(),parent_cleanup(ATTEMPT/'record-cases','final-cleanup'):
                        codec=Record.verify_existing_binary(SERVER,['record-cases'],receipt['build']['binary_sha256'],CONSUMER,ATTEMPT/'record-cases')
                    S.exclusive_json(ATTEMPT/'record-result.json',{'comparison':codec,'cleanup':S.pin(ATTEMPT/'record-cases/final-cleanup.json')})
                    for lane in ('phase-cases','facade-cases'):
                        previous=None
                        for run in range(2):
                            verify_build();process,out,err=execute([SERVER,'--gpu','off','--threads','1',lane,S.TABLE],120,ATTEMPT,lane+'-'+str(run))
                            S.process_ok(process);require(not err,'Native fixture stderr: '+lane)
                            if lane=='phase-cases':
                                with phase_scope():compared=Phase.compare_output(out.decode())
                            else:compared=S.stage_comparison(out.decode())
                            equal=previous is None or previous==out
                            row={'process':process,'comparison':compared,'exact_rerun_equal':equal}
                            S.exclusive_json(ATTEMPT/(lane+'-'+str(run)+'.comparison.json'),row)
                            require(equal,'Fresh fixture rerun differs: '+lane);previous=out;lanes.append(row);verify_build()
            summary={'status':'PASS','binary':S.pin(SERVER),'native_build_receipt':S.pin(RECEIPT),'consumer_manifest':S.pin(CONSUMER),
                'codec_executions':codec['completed_executions'],'fixture_lanes':lanes,'primary':primary,
                'scope':'Declared neutral LocalPlayer/TCP/MCP/custom bundle and unchanged complete Java phase/policy fixtures; no OS input/presentation or general gameplay parity.'}
        S.exclusive_json(ATTEMPT/'summary.json',summary);S.exclusive_json(ROOT/'evidence/local-player-session-continuation-r2-native.json',summary);print(json.dumps(summary),flush=True)
    except BaseException as cause:
        failure(ATTEMPT/'first-failure.json',cause,completed_primary=len(primary),completed_fixture_lanes=len(lanes),
            codec_executions=codec['completed_executions'] if codec else 0,prepared_seal=value['seal_sha256'],binary=S.pin(SERVER));raise

def main():
    parser=argparse.ArgumentParser(description=__doc__);mode=parser.add_mutually_exclusive_group(required=True)
    for name in ('prepare','audit','build-only','skip-build'):mode.add_argument('--'+name,action='store_true')
    mode.add_argument('--_build-once',type=Path);mode.add_argument('--_integration-run',type=int);args=parser.parse_args()
    if args.prepare:prepare();return
    value=audit()
    if args.audit:print(json.dumps({'status':'read-only-audit-PASS','ready':S.pin(READY),'files':len(value['files']),'source_imports':len(value['full_Bend_imports'])}));return
    if args._build_once is not None:build_once(args._build_once);return
    if args.build_only:build();return
    if args._integration_run is not None:integration_child(args._integration_run);return
    if args.skip_build:native();return
    raise RuntimeError('Unselected mode')

if __name__=='__main__':main()
