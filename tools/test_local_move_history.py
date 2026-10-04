#!/usr/bin/env python3
"""Actual whole-move/history comparison; Python supplies no movement/history math."""
from __future__ import annotations
import argparse,copy,hashlib,json,os,signal,subprocess,sys,time
from pathlib import Path
import reference_local_move_history_probe as P
import test_local_move_world as D
from build_native import Snapshot,source_graph
from reference_inventory import ROOT,canonical,fingerprint,write_json

BEND=Path('/Users/chuah/.bend/bin/bend')
SOURCE=ROOT/'src/local_move_history.bend'
HARNESS=ROOT/'tests/local_move_history.bend'
BINARY=ROOT/'build/local-move-history-tests'
WORK=ROOT/'build/local-move-history-verification'
TABLE=ROOT/'generated/reference_mth_sin.f32'
FIXTURE=P.OUTPUT

def digest(v):return hashlib.sha256(canonical(v)).hexdigest()
def pin(path):return {'path':str(path.relative_to(ROOT)),**fingerprint(path)}
def generation():
    snapshot=Snapshot();source_graph(HARNESS,(BEND.resolve().parent.parent/'bend2/base.bend').resolve(),dict(os.environ),snapshot)
    return {p['path']:p['sha256']for p in snapshot.manifest()}
def tools():
    return {p:pin(ROOT/p)for p in ['tools/test_local_move_history.py','tools/reference_local_move_history_probe.py','tools/test_local_move_world.py','tools/reference_local_move_world_probe.py','tools/reference_local_collision_world_probe.py','tools/reference_local_collision_probe.py','tools/reference_local_input_probe.py','tools/reference_inventory.py','tools/reference_model_probe.py','tools/test_geometry.py','tools/build_native.py']}

def bound(kind,cap):
    WORK.mkdir(parents=True,exist_ok=True);before=generation();tp=tools();ref=pin(FIXTURE);table=pin(TABLE)
    receipt=WORK/'native-build-full.json'
    command=([sys.executable,str(ROOT/'tools/build_native.py'),str(HARNESS),'-o',str(BINARY),'--cache-dir',str(ROOT/'build/local-move-history-cache'),'--report',str(receipt)]if kind=='build'else[str(BEND),str(SOURCE if kind.endswith('source')else HARNESS),'--check-only'if kind.startswith('ordinary')else'--verdict'])
    start=time.monotonic();p=subprocess.Popen(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
    print(json.dumps({'phase':kind,'pid':p.pid,'cap_seconds':cap}),flush=True)
    expired=False
    try:out,err=p.communicate(timeout=cap)
    except subprocess.TimeoutExpired:
        expired=True;os.killpg(p.pid,signal.SIGKILL);out,err=p.communicate()
    stdout=WORK/(kind+'.stdout');stderr=WORK/(kind+'.stderr');stdout.write_text(out);stderr.write_text(err)
    report={'status':'inconclusive'if expired else'passed'if p.returncode==0 else'failed','kind':kind,'command':command,'pid':p.pid,'seconds':round(time.monotonic()-start,6),'cap_seconds':cap,'exit_code':p.returncode,'timed_out':expired,'stdout':pin(stdout),'stderr':pin(stderr),'generation':before,'generation_sha256':digest(before),'generation_unchanged':before==generation(),'tools':tp,'tools_unchanged':tp==tools(),'reference':ref,'reference_unchanged':ref==pin(FIXTURE),'table':table,'table_unchanged':table==pin(TABLE),'compiler':fingerprint(BEND)}
    if kind=='build'and report['status']=='passed':
        build=json.loads(receipt.read_text());assert build['binary_sha256']==fingerprint(BINARY)['sha256']
        report['binary']=pin(BINARY);report['native_build']={'full_receipt':pin(receipt),'dependency_count':len(build['dependencies']),'dependencies_sha256':digest(build['dependencies']),'project_dependencies':[d for d in build['dependencies']if d['path'].startswith(str(ROOT)+'/')],'artifact':build['artifact'],'cache_key':build['cache_key'],'cache_hit':build['cache_hit'],'timings':build['timings'],'identity':build['identity'],'compiler':{k:v for k,v in build['compiler'].items()if k!='driver_probe'},'associated_preflight_c_sha256':build['emitted_c_sha256'],'c_scope':'Content-keyed preflight C; installed CLI internal temporary C is not asserted identical.'}
    write_json(ROOT/f'evidence/local-move-history-{kind}.json',report)
    assert report['generation_unchanged']and report['tools_unchanged']and report['reference_unchanged']and report['table_unchanged'],report
    return report

def request(step,id,install=False,clip=None,shape=0,history=None,**changes):
    groups=D.request(step,id,install,**changes).split(';')
    clip={'NotRequired':0,'Miss':1,'Hit':2}[step['ray_observation']['status']]if clip is None else clip
    groups[0]+='|'+str(clip)+'|'+str(shape)
    groups[-1]+='|'+'|'.join(map(str,D.words([history or step['before']['fall_distance_f64_bits']])))
    return ';'.join(groups)

def same_owner(p,id,all_fields=True,child=False):
    kinds=['clock','queue','view','canonical']+(['body','support','minor-state','history']if all_fields else[])
    for k in kinds:assert p[id+'-before',k]==p[id+'-after',k],(id,'retention',k)
    if child:
        for k in kinds:assert p[id+'-before-owned0',k]==p[id+'-after-owned0',k],(id,'child owner retention',k)

def history_fields(raw):return list(map(str,D.words([raw])))
def compare(step,id,p,q,c,s):
    result=D.compare(step,id,p,q,c,s);same_owner(p,id,False)
    assert p[id+'-before','history']==history_fields(step['before']['fall_distance_f64_bits']),(id,'authoritative before history')
    assert p[id+'-after','history']==p[id,'result-history']==history_fields(step['expected']['fall_distance_f64_bits']),(id,'actual final history')
    phase=step['history_phase'];expected=[str(int(step['position_application_gate_entered'])),*history_fields(phase['resolved_y_f64_bits']),*history_fields(phase['resolved_length_squared_f64_bits']),str(int(phase['on_ground']))]
    assert p[id,'history-input']==expected,(id,'derived actual callback arguments')
    assert phase['entry']==step['before']['fall_distance_f64_bits']and phase['exit']==step['expected']['fall_distance_f64_bits']
    result.update(history_raw_match=True,callback_fields_raw_match=True,clip_status=step['ray_observation']['status'],canonical_world_cells_exactly_retained=True)
    return result

def native(commands,label,env=None):
    argv=[str(BINARY),'--gpu','off','--threads','1',str(TABLE),*commands];start=time.monotonic();p=subprocess.run(argv,cwd=ROOT,env=env,capture_output=True,text=True,timeout=120)
    WORK.mkdir(parents=True,exist_ok=True);out=WORK/(label+'.stdout');err=WORK/(label+'.stderr');out.write_text(p.stdout);err.write_text(p.stderr)
    receipt={'label':label,'exit_code':p.returncode,'seconds':round(time.monotonic()-start,6),'stdout':pin(out),'stderr':pin(err),'command_prefix':argv[:5],'command_inputs_sha256':digest(commands)}
    assert p.returncode==0,(receipt,p.stderr[-3000:]);return *D.lines(p.stdout),receipt

def corpus(data,prefix,env=None):
    rows=[];excluded=[];receipts=[]
    for ci,case in enumerate(data['cases']):
        commands=D.edits(case['initial']['world_writes'],'initial-edit')
        for si,step in enumerate(case['steps']):commands+=D.edits(step['world_writes'],'step-edit:'+str(si))+[request(step,case['id']+':'+str(si),si==0)]
        commands.append('final|table-probe');p,q,c,s,receipt=native(commands,prefix+str(ci),env);receipts.append(receipt);assert p['final','table-owner']==['0']
        for si,step in enumerate(case['steps']):
            id=case['id']+':'+str(si)
            if not step['admission']['neutral_context']:
                same_owner(p,id);assert p[id,'error']==['move:local-move-context:6'];assert not q.get(id)and not c.get(id)and not s.get(id)
                excluded.append({'id':id,'error':p[id,'error'][0],'category':'actual nonsuppressed-bounce context excluded'})
            elif not step['actual_returned']:
                assert step['error_class']=='java.lang.NoSuchFieldError'and'gameRenderer'in step['error_message']
                same_owner(p,id);assert p[id,'error']==['history:landing'];assert not q.get(id)and not c.get(id)and not s.get(id)
                excluded.append({'id':id,'error':p[id,'error'][0],'category':'Bend excludes actual damaging callback service failure'})
            else:rows.append(compare(step,id,p,q,c,s))
    return rows,excluded,receipts

def policy_specs(data):
    base=data['cases'][0]['steps'][0];find=lambda name:next(c['steps'][0]for c in data['cases']if c['id']==name)
    long=find('history-long-air-miss');minus=find('history-negative-zero');landing=find('history-landing:3.874999')
    specs=[]
    def add(id,step=base,error=None,**options):specs.append({'id':id,'step':step,'error':error,**options})
    add('history-distance-mismatch',error='history-mismatch',changes={'context_changes':{1:0x3fe00000,2:0}})
    add('history-signed-zero-mismatch',step=minus,error='history-mismatch',changes={'context_changes':{1:0,2:0}})
    add('request-outer-tail',error='noncanonical-request:0',shape=1)
    add('request-inner-tail',error='noncanonical-request:1',shape=2)
    add('owned-state-tail',error='noncanonical-state',nested=True)
    for clip,error in [(0,'history:missing-clip'),(2,'history:reset-hit'),(3,'history:missing-clip')]:add('required-ray:'+str(clip),step=long,error=error,clip=clip,recover_same=True)
    for clip,error in [(1,'history:unexpected-clip'),(2,'history:reset-hit'),(3,'history:unexpected-clip')]:add('unneeded-ray:'+str(clip),error=error,clip=clip,recover_same=True)
    add('actual-damaging-landing',step=landing,error='history:landing')
    add('no-physics-cannot-bypass',error='move:local-move-hook-admission',changes={'context_changes':{6:4}})
    for index,label,word in [(11,'cannot-simulate',0),(12,'nonlocal-authority',0),(13,'stuck-multiplier',0x3ff00000),(19,'removed',1),(20,'auto-jump',1),(21,'block-speed',0),(22,'bounce',0)]:add(label,error='move:local-move-context:',changes={'context_changes':{index:word}})
    for index,label in [(0,'unknown-entities'),(1,'unknown-border')]:add(label,error='move:edge-',changes={'environment_changes':{index:1}})
    add('fuel',error='move:edge-query-budget',changes={'context_changes':{7:0}})
    add('interior',error='move:local-move-sweep-outside-interior',changes={'interior':[0.,0.,0.,1.,1.,1.]})
    add('pending-history-failure',step=long,error='history:missing-clip',clip=0,recover_same=True,setup=['clock|clock','running|running','pending|pending'])
    prior_reads={tuple(r['position'])for q in base['queries']if q['method']=='noCollision'for r in q['reads']}
    late=next(r for q in base['queries']if q['method']=='blockCollisions'for r in q['reads']if tuple(r['position'])not in prior_reads)
    edit=lambda name,point,kind:'|'.join(map(str,[name,'edit',*(v&0xffffffff for v in point),kind]))
    add('after-backoff-move-failure',error='move:unsupported-block-state:',setup=[edit('inject-late-state',late['position'],4)],cleanup=[edit('repair-late-state',late['position'],D.NAMES.index(late['block_id']))])
    for label,op,error in [('absent-palette','no-palette','move:edge-palette-unavailable'),('stale-palette','stale-palette','move:edge-palette-stale')]:
        add(label,error=error,setup=[label+'-setup|'+op],cleanup=['restore|palette-refresh'])
    return specs

def policies(data,prefix):
    rows=[];receipts=[];base=data['cases'][0]['steps'][0]
    for spec in policy_specs(data):
        id=spec['id'];step=spec['step'];commands=D.edits(step.get('world_writes',[]),'write')+spec.get('setup',[])
        if spec.get('nested'):
            commands += [request(step,'initialize',True),'nested|nest',request(step,id,False),'child|select-child',request(base,'recovery',True)]
            recovery=base
        else:
            commands.append(request(step,id,True,clip=spec.get('clip'),shape=spec.get('shape',0),**spec.get('changes',{})))
            recovery=step if spec.get('recover_same')else base
            commands+=spec.get('cleanup',[])
            commands.append(request(recovery,'recovery',not spec.get('recover_same',False)))
        commands.append('final|table-probe');p,q,c,s,receipt=native(commands,prefix+id);receipts.append(receipt)
        same_owner(p,id,child=spec.get('nested',False));assert p[id,'error'][0].startswith(spec['error']),(id,spec['error'],p.get((id,'error')))
        assert not q.get(id)and not c.get(id)and not s.get(id),(id,'failure output is partial')
        compare(recovery,'recovery',p,q,c,s);assert p['final','table-owner']==['0']
        if spec.get('nested'):
            for kind in ['clock','queue','canonical']:assert p['child',kind]==p[id+'-after-owned0',kind],(id,'returned child world reused',kind)
            assert p['child','history']==history_fields('4031000000000000')
        if id=='pending-history-failure':
            assert p[id+'-before','clock'][1:4]==['777','0','0'];assert p[id+'-before','queue'][0]=='100,9,0,time,999;'
        rows.append({'id':id,'error':p[id,'error'][0],'full_prior_state_and_canonical_cells_retained':True,'table_owner_recovered':True,'same_history_owner_reused_without_reseeding':bool(spec.get('recover_same')),'nested_distinct_world_owner_retained_and_reused':bool(spec.get('nested'))})
    return rows,receipts

def remap(data,prefix):
    path=WORK/'remapped.tsv';path.parent.mkdir(parents=True,exist_ok=True);order=['minecraft:oak_planks','minecraft:stone','minecraft:air','minecraft:dirt']
    path.write_text('block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json\n'+''.join(f'{i}\t{name}\t{i}\t1\t{i}\t[]\n'for i,name in enumerate(order)))
    env=dict(os.environ);env['MC_BLOCK_REGISTRY']=str(path);selected=[c for c in data['cases']if c['id']in ['dynamic_floor','held_floor','held_wall','held_shift_edge']];assert len(selected)==4
    rows,excluded,receipts=corpus({'cases':selected},prefix,env);return {'registry':pin(path),'native_moves':len(rows),'case_ids':[c['id']for c in selected],'rows':rows,'excluded':excluded},receipts

def prepare(data,ordinary):
    g=generation();specs=policy_specs(data);report={'status':'ordinary-prepared-native-and-kernel-pending','source':pin(SOURCE),'harness':pin(HARNESS),'tools':tools(),'reference':pin(FIXTURE),'table':pin(TABLE),'generation':g,'generation_sha256':digest(g),'generation_count':len(g),'ordinary':ordinary,'actual_case_count':len(data['cases']),'actual_move_attempts':sum(len(c['steps'])for c in data['cases']),'actual_successful_admitted_moves':sum(s['actual_returned']and s['admission']['neutral_context']for c in data['cases']for s in c['steps']),'actual_miss_contexts':sum(s['ray_observation']['status']=='Miss'for c in data['cases']for s in c['steps']),'policy_recovery_count':len(specs),'policies_sha256':digest(specs),'native_runs_planned':2,'kernel_law_count':HARNESS.read_text().count('\nlaw '),'queued_native_command':'PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_move_history.py --skip-ordinary --skip-kernel','queued_kernel_command':'PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_move_history.py --skip-build --skip-ordinary --kernel-only','caps_seconds':{'native_build':600,'native_each_process':120,'source_kernel':60,'harness_kernel':60},'scope':'Pure atomic neutral dry no-damage adapter only. Actual clip observations mandatory; no fall reset hits, damage, effects, lifecycle, emission or automatic integration claim.'}
    write_json(ROOT/'evidence/local-move-history-preparation.json',report);return report

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--prepare',action='store_true');parser.add_argument('--skip-build',action='store_true');parser.add_argument('--skip-ordinary',action='store_true');parser.add_argument('--skip-kernel',action='store_true');parser.add_argument('--kernel-only',action='store_true');a=parser.parse_args()
    integrity=P.verify(True);data=json.loads(FIXTURE.read_text());ordinary=[]
    if not a.skip_ordinary:
        ordinary=[bound('ordinary-source',60),bound('ordinary-harness',60)];assert all(r['status']=='passed'for r in ordinary)
    if a.prepare:
        report=prepare(data,ordinary);print(json.dumps({k:report[k]for k in ['status','actual_case_count','actual_move_attempts','actual_successful_admitted_moves','policy_recovery_count','generation_count','kernel_law_count']}));return
    initial=generation();tp=tools();ref=pin(FIXTURE);table=pin(TABLE)
    if a.kernel_only:
        attempts=[bound('kernel-source',60),bound('kernel-harness',60)];write_json(ROOT/'evidence/local-move-history-kernel.json',{'status':'passed'if all(r['status']=='passed'for r in attempts)else'unverified','attempts':[pin(ROOT/f'evidence/local-move-history-{r["kind"]}.json')for r in attempts],'generation':initial,'source':pin(SOURCE),'harness':pin(HARNESS),'law_count':HARNESS.read_text().count('\nlaw '),'scope':'Full imported production and harness attempted once each; no source substitution/projection/retry.'});print(json.dumps({'kernel_status':[r['status']for r in attempts]}));return
    build=json.loads((ROOT/'evidence/local-move-history-build.json').read_text())if a.skip_build else bound('build',600)
    assert build['status']=='passed'and build['generation']==initial and build['binary']==pin(BINARY)
    full=json.loads((WORK/'native-build-full.json').read_text())
    for dep in full['dependencies']:
        path=Path(dep['lookup']);assert path.resolve()==Path(dep['path'])and fingerprint(path)['sha256']==dep['sha256']and path.stat().st_size==dep['bytes'],'Native dependency changed: '+str(path)
    runs=[]
    for run in range(2):
        rows,excluded,receipts=corpus(data,f'run{run}-case');policy,extra=policies(data,f'run{run}-policy-');mapped,more=remap(data,f'run{run}-remap');receipts+=extra+more
        raw=WORK/f'run{run}-full.json';write_json(raw,{'rows':rows,'excluded':excluded,'policies':policy,'remap':mapped,'receipts':receipts})
        runs.append({'admitted_moves':len(rows),'excluded':excluded,'policy_recoveries':len(policy),'remapped_moves':mapped['native_moves'],'result_sha256':digest({'rows':rows,'excluded':excluded,'policies':policy,'remap':mapped}),'seconds':round(sum(r['seconds']for r in receipts),6),'raw':pin(raw),'native_process_count':len(receipts),'observed_miss_moves':sum(r['clip_status']=='Miss'for r in rows),'skipped_position_history_updates':sum(not r['position_gate']for r in rows)})
    assert runs[0]['result_sha256']==runs[1]['result_sha256'],'Repeated actual comparison differs'
    report={'status':'passed','generation':initial,'generation_sha256':digest(initial),'generation_unchanged':initial==generation(),'tools':tp,'tools_unchanged':tp==tools(),'reference':ref,'reference_unchanged':ref==pin(FIXTURE),'table':table,'table_unchanged':table==pin(TABLE),'build':pin(ROOT/'evidence/local-move-history-build.json'),'binary':pin(BINARY),'reference_integrity':integrity,'runs':runs,'same_original_motion_history_owners_on_all_errors':True,'canonical_cells_and_trie_exact_lossless_comparison':True,'historical_build_tools':build['tools'],'immutable_native_reused':a.skip_build,'scope':'Bounded neutral motion/support/minor/history projection; actual ray MISS contexts, exact callback fields, default no-damage landings. Does not execute or reorder callbacks/emission or certify whole LocalPlayer.move/tick.'}
    assert report['generation_unchanged']and report['tools_unchanged']and report['reference_unchanged']and report['table_unchanged'];write_json(ROOT/'evidence/local-move-history-native.json',report);print(json.dumps({'native_status':'passed','runs':[{k:r[k]for k in ['admitted_moves','policy_recoveries','remapped_moves','seconds']}for r in runs]}),flush=True)
    if not a.skip_kernel:
        attempts=[bound('kernel-source',60),bound('kernel-harness',60)];write_json(ROOT/'evidence/local-move-history-kernel.json',{'status':'passed'if all(r['status']=='passed'for r in attempts)else'unverified','attempts':[pin(ROOT/f'evidence/local-move-history-{r["kind"]}.json')for r in attempts],'generation':initial,'source':pin(SOURCE),'harness':pin(HARNESS),'law_count':HARNESS.read_text().count('\nlaw '),'scope':'Full imported source/harness attempts only; no source substitution/projection/retry.'})
if __name__=='__main__':main()
