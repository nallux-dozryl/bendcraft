#!/usr/bin/env python3
"""Owned direct-travel comparison. Python supplies no gameplay transition."""
from __future__ import annotations
import argparse,copy,hashlib,json,os,signal,subprocess,sys,time
from pathlib import Path
import reference_local_travel_history_probe as P
import test_local_move_world as D
from build_native import Snapshot,source_graph
from reference_inventory import ROOT,canonical,fingerprint,write_json

BEND=Path('/Users/chuah/.bend/bin/bend')
SOURCE=ROOT/'src/local_travel_history.bend'
HARNESS=ROOT/'tests/local_travel_history.bend'
BINARY=ROOT/'build/local-travel-history-tests'
WORK=ROOT/'build/local-travel-history-verification'
TABLE=ROOT/'generated/reference_mth_sin.f32'
FIXTURE=P.OUTPUT

def digest(value):return hashlib.sha256(canonical(value)).hexdigest()
def pin(path):return {'path':str(path.relative_to(ROOT)),**fingerprint(path)}
def generation():
    snapshot=Snapshot();source_graph(HARNESS,(BEND.resolve().parent.parent/'bend2/base.bend').resolve(),dict(os.environ),snapshot)
    return {p['path']:p['sha256']for p in snapshot.manifest()}
def tools():
    paths=['tools/test_local_travel_history.py','tools/reference_local_travel_history_probe.py','tools/reference_local_move_history_probe.py','tools/test_local_move_world.py','tools/reference_local_move_world_probe.py','tools/reference_local_collision_world_probe.py','tools/reference_local_collision_probe.py','tools/reference_local_input_probe.py','tools/reference_inventory.py','tools/reference_model_probe.py','tools/test_geometry.py','tools/build_native.py']
    return {path:pin(ROOT/path)for path in paths}

def bound(kind,cap):
    WORK.mkdir(parents=True,exist_ok=True);before=generation();tp=tools();ref=pin(FIXTURE);table=pin(TABLE)
    full=WORK/'native-build-full.json'
    command=([sys.executable,str(ROOT/'tools/build_native.py'),str(HARNESS),'-o',str(BINARY),'--cache-dir',str(ROOT/'build/local-travel-history-cache'),'--report',str(full)]if kind=='build'else[str(BEND),str(SOURCE if kind.endswith('source')else HARNESS),'--check-only'if kind.startswith('ordinary')else'--verdict'])
    started=time.monotonic();process=subprocess.Popen(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
    print(json.dumps({'phase':kind,'pid':process.pid,'cap_seconds':cap}),flush=True)
    expired=False;samples=[]
    while True:
        remaining=cap-(time.monotonic()-started)
        if remaining<=0:
            expired=True
            try:os.killpg(process.pid,signal.SIGTERM)
            except ProcessLookupError:pass
            try:out,err=process.communicate(timeout=5)
            except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);out,err=process.communicate()
            break
        try:out,err=process.communicate(timeout=min(remaining,5));break
        except subprocess.TimeoutExpired:
            listing=subprocess.run(['ps','-ax','-o','pid=,pgid=,rss=,vsz=,etime='],capture_output=True,text=True,check=True).stdout
            group=[]
            for line in listing.splitlines():
                fields=line.split()
                if len(fields)==5 and int(fields[1])==process.pid:group.append({'pid':int(fields[0]),'rss_kib':int(fields[2]),'virtual_kib':int(fields[3]),'elapsed':fields[4]})
            samples.append({'seconds':round(time.monotonic()-started,6),'processes':group})
    stdout=WORK/(kind+'.stdout');stderr=WORK/(kind+'.stderr');stdout.write_text(out);stderr.write_text(err)
    report={'status':'inconclusive'if expired else'passed'if process.returncode==0 else'failed','kind':kind,'command':command,'pid':process.pid,'seconds':round(time.monotonic()-started,6),'cap_seconds':cap,'exit_code':process.returncode,'timed_out':expired,'stdout':pin(stdout),'stderr':pin(stderr),'generation':before,'generation_sha256':digest(before),'generation_unchanged':before==generation(),'tools':tp,'tools_unchanged':tp==tools(),'reference':ref,'reference_unchanged':ref==pin(FIXTURE),'table':table,'table_unchanged':table==pin(TABLE),'compiler':fingerprint(BEND),'memory_samples':samples,'memory_scope':'5-second process-group RSS/virtual sampling; no physical-footprint or gameplay benchmark claim'}
    if kind=='build'and report['status']=='passed':
        build=json.loads(full.read_text());assert build['binary_sha256']==fingerprint(BINARY)['sha256']
        report.update(binary=pin(BINARY),native_build={'full_receipt':pin(full),'dependency_count':len(build['dependencies']),'dependencies_sha256':digest(build['dependencies']),'artifact':build['artifact'],'cache_key':build['cache_key'],'cache_hit':build['cache_hit'],'timings':build['timings'],'identity':build['identity'],'compiler':{k:v for k,v in build['compiler'].items()if k!='driver_probe'},'associated_preflight_c_sha256':build['emitted_c_sha256'],'c_scope':'Content-keyed preflight C; installed CLI temporary native-internal C is not retained or asserted identical.'})
    write_json(ROOT/f'evidence/local-travel-history-{kind}.json',report)
    assert report['generation_unchanged']and report['tools_unchanged']and report['reference_unchanged']and report['table_unchanged'],report
    return report

def group(words):return '|'.join(str(v&0xffffffff)for v in words)
def observed_modes(context):
    # These flags are direct receiver observations. This selects explicit admission
    # markers only; it supplies no expected motion/velocity/history arithmetic.
    for field,travel,collision in [('no_physics',0,4),('passenger',8,3),('flying',3,1),('swimming',2,2),('fall_flying',4,6),('on_climbable',5,6),('in_water',1,2),('in_lava',1,2),('levitation',7,5),('slow_falling',7,5)]:
        if context[field]:return travel,collision
    if not context['actual_has_chunk_at_ground_sample']:return 9,6
    return 0,0

def request(step,id,install=False,clip=None,shape=0,context_changes=None,hooks_changes=None,environment_changes=None,input_changes=None,body_changes=None,history=None,interior=D.INTERIOR):
    s=step['before'];c=step['travel_context'];a=c['attributes'];g=c['ground_sample'];travel_mode,collision_mode=observed_modes(c)
    context=[*(v&0xffffffff for v in g['position']),int(g['friction_f32_bits'],16),*D.words([a['movement_speed_f64_bits'],a['gravity_f64_bits'],a['friction_modifier_f64_bits'],a['air_drag_modifier_f64_bits']]),int(s['rotation_f32_bits'][0],16),int(a['maximum_f32_bits'],16),int(a['sprinting']),int(a['no_gravity']),int(c['discard_friction']),travel_mode]
    hooks=[D.mask(s['key_presses']),int(s['input_f32_bits'][0],16),int(s['input_f32_bits'][2],16),int(c['flying']),collision_mode,int(c['can_simulate']),int(c['local_authoritative']),*D.words(s['stuck_speed_multiplier']),0,int(c['auto_jump_enabled']),int(c['block_speed_factor_f32_bits']=='3f800000'),int(c['suppressed_bounce']),len(step['queries'])+1]
    environment=[0,0,*D.words([D.bits(v)for v in interior])];input_words=D.words(step['travel_input']);body_words=D.body_words(s)
    for target,changes in [(context,context_changes),(hooks,hooks_changes),(environment,environment_changes),(input_words,input_changes),(body_words,body_changes)]:
        for index,value in (changes or {}).items():target[index]=value
    clipping={'NotRequired':0,'Miss':1,'Hit':2}.get(step['ray_observation']['status'],3)if clip is None else clip
    seed=D.seed_words(s)+D.words([history if history is not None else s['fall_distance_f64_bits']])
    return ';'.join([id+'|travel|'+str(int(install))+'|'+str(clipping)+'|'+str(shape),group(body_words),group(context),group(input_words),group(hooks),group(environment),group(seed)])

def same_owner(p,id,all_fields=True,child=False):
    fields=['clock','queue','view','canonical']+(['body','support','minor-state','history']if all_fields else[])
    for field in fields:assert p[id+'-before',field]==p[id+'-after',field],(id,'retention',field)
    if child:
        for field in fields:assert p[id+'-before-owned0',field]==p[id+'-after-owned0',field],(id,'child owner',field)

def native(commands,label,env=None):
    command=[str(BINARY),'--gpu','off','--threads','1',str(TABLE),*commands];started=time.monotonic();process=subprocess.run(command,cwd=ROOT,env=env,capture_output=True,text=True,timeout=120)
    WORK.mkdir(parents=True,exist_ok=True);stdout=WORK/(label+'.stdout');stderr=WORK/(label+'.stderr');stdout.write_text(process.stdout);stderr.write_text(process.stderr)
    receipt={'label':label,'exit_code':process.returncode,'seconds':round(time.monotonic()-started,6),'stdout':pin(stdout),'stderr':pin(stderr),'command_prefix':command[:5],'command_inputs_sha256':digest(commands)}
    assert process.returncode==0,(receipt,process.stderr[-3000:]);return *D.lines(process.stdout),receipt

def raw_fields(raw):return list(map(str,D.words([raw])))
def compare(step,id,p,q,colliders,support):
    assert p[id+'-before','body']==D.body_fields(step['before']),(id,'whole travel before body')
    assert p[id+'-after','body']==D.body_fields(step['expected']),(id,'whole actual travel body',p.get((id+'-after','body')),D.body_fields(step['expected']))
    assert p[id,'prepared-body']==D.body_fields(step['movement_before']),(id,'actual prepared Body')
    assert D.raw64(p[id,'prepared-request'])==step['actual_requested'],(id,'actual prepared request')
    modified=copy.deepcopy(p);modified[id+'-before','body']=p[id,'prepared-body'];modified[id+'-after','body']=p[id,'move-body']
    move=copy.deepcopy(step);move['before']=step['movement_before'];move['expected']=step['movement_expected'];move['requested']=step['actual_requested'];move['mover']='SELF'
    result=D.compare(move,id,modified,q,colliders,support);same_owner(p,id,False)
    assert p[id+'-before','history']==raw_fields(step['before']['fall_distance_f64_bits'])
    assert p[id+'-after','history']==p[id,'result-history']==raw_fields(step['expected']['fall_distance_f64_bits']),(id,'actual final history')
    phase=step['history_phase'];expected=[str(int(step['position_application_gate_entered'])),*raw_fields(phase['resolved_y_f64_bits']),*raw_fields(phase['resolved_length_squared_f64_bits']),str(int(phase['on_ground']))]
    assert p[id,'history-input']==expected,(id,'actual history callback args')
    assert phase['entry']==step['before']['fall_distance_f64_bits']and phase['exit']==step['movement_expected']['fall_distance_f64_bits']==step['expected']['fall_distance_f64_bits']
    t=step['travel_phase'];context=step['travel_context'];attributes=context['attributes']
    gravity=t['prepared_gravity_f64_bits']
    expected_context=[str(int(t['friction_f32_bits'],16)),str(int(t['acceleration_f32_bits'],16)),str(int(attributes['maximum_f32_bits'],16)),*raw_fields(gravity),*raw_fields(attributes['air_drag_modifier_f64_bits']),str(int(context['discard_friction']))]
    assert p[id,'prepared-context']==expected_context,(id,'actual preparation operands',p.get((id,'prepared-context')),expected_context)
    result.update(whole_travel_body_raw_match=True,prepared_velocity_raw_match=True,gravity_drag_raw_match=True,history_raw_match=True,history_before_gravity_drag=True,clip_status=step['ray_observation']['status'],canonical_world_cells_exactly_retained=True)
    return result

def corpus(data,prefix,env=None):
    rows=[];excluded=[];receipts=[]
    for ci,case in enumerate(data['cases']):
        commands=D.edits(case['initial']['world_writes'],'initial-edit')
        for si,step in enumerate(case['steps']):commands+=D.edits(step['world_writes'],'step-edit:'+str(si))+[request(step,case['id']+':'+str(si),si==0 or step.get('reseed',False))]
        commands.append('final|table-probe');p,q,c,s,receipt=native(commands,prefix+str(ci),env);receipts.append(receipt);assert p['final','table-owner']==['0']
        for si,step in enumerate(case['steps']):
            id=case['id']+':'+str(si)
            if not step['admission']['neutral_context']:
                same_owner(p,id);assert (id,'error')in p,(id,'unadmitted context published')
                assert not q.get(id)and not c.get(id)and not s.get(id)
                excluded.append({'id':id,'error':p[id,'error'][0],'actual_returned':step['actual_returned'],'category':step['admission']['exclusion']})
            else:rows.append(compare(step,id,p,q,c,s))
    return rows,excluded,receipts

def policy_specs(data):
    base=next(s for c in data['cases']for s in c['steps']if s['admission']['neutral_context'])
    miss=next(s for c in data['cases']for s in c['steps']if s['admission']['neutral_context']and s['ray_observation']['status']=='Miss')
    specs=[]
    def add(id,step=base,error=None,**options):specs.append({'id':id,'step':step,'error':error,**options})
    add('input-nan',error='prepare:invalid-input:0',changes={'input_changes':{0:0x7ff80000}})
    add('authoritative-body-nan',error='prepare:invalid-body',changes={'body_changes':{18:0x7ff80000}})
    for name,raw in [('history-nan','7ff8000000000001'),('history-positive-infinity','7ff0000000000000'),('history-negative-infinity','fff0000000000000')]:add(name,error='movement:move:local-move-hook-admission',changes={'history':raw})
    add('outer-tail',error='noncanonical-request:0',shape=1)
    add('hooks-tail',error='noncanonical-request:1',shape=2)
    add('owned-tail',error='noncanonical-state',nested=True)
    for index,name,value,error in [(17,'unsupported-travel',1,'prepare:unsupported-context'),(12,'yaw-nan',0x7fc00000,'prepare:invalid-context:0'),(3,'friction-nan',0x7fc00000,'prepare:invalid-context:1'),(13,'step-negative',0xbf800000,'prepare:invalid-context:2'),(4,'speed-nan',0x7ff80000,'prepare:invalid-attribute:0'),(6,'gravity-nan',0x7ff80000,'prepare:invalid-attribute:1'),(8,'friction-modifier-negative',0xbff00000,'prepare:invalid-attribute:2'),(10,'drag-negative',0xbff00000,'prepare:invalid-attribute:3')]:add(name,error=error,changes={'context_changes':{index:value}})
    for index,name,value,error in [(4,'no-physics',4,'movement:move:local-move-hook-admission'),(5,'simulation',0,'movement:move:local-move-context:0'),(6,'authority',0,'movement:move:local-move-context:1'),(7,'stuck',0x3ff00000,'movement:move:local-move-context:2'),(13,'removed',1,'movement:move:local-move-context:3'),(14,'auto-jump',1,'movement:move:local-move-context:4'),(15,'block-speed',0,'movement:move:local-move-context:5'),(16,'bounce',0,'movement:move:local-move-context:6'),(17,'fuel',0,'movement:move:edge-query-budget'),(1,'minor-input-nan',0x7fc00000,'movement:move:local-move-hook-admission')]:add(name,error=error,changes={'hooks_changes':{index:value}})
    for index,name,error in [(0,'unknown-entities','movement:move:edge-entities-unresolved'),(1,'unknown-border','movement:move:edge-border-unresolved')]:add(name,error=error,changes={'environment_changes':{index:1}})
    for clipping,error in [(0,'history:missing-clip'),(2,'history:reset-hit'),(3,'history:missing-clip')]:add('required-clip:'+str(clipping),step=miss,error='movement:'+error,clip=clipping,recover_same=True)
    for clipping,error in [(1,'history:unexpected-clip'),(2,'history:reset-hit'),(3,'history:unexpected-clip')]:add('unneeded-clip:'+str(clipping),error='movement:'+error,clip=clipping,recover_same=True)
    for name,op,error in [('absent-palette','no-palette','movement:move:edge-palette-unavailable'),('stale-palette','stale-palette','movement:move:edge-palette-stale')]:add(name,error=error,setup=[name+'-setup|'+op],cleanup=['restore|palette-refresh'])
    add('pending-history-failure',step=miss,error='movement:history:missing-clip',clip=0,recover_same=True,setup=['clock|clock','running|running','pending|pending'])
    add('interior',error='movement:move:local-move-sweep-outside-interior',changes={'interior':[0.,0.,0.,1.,3.,1.]})
    phase_starts=[v['sequence']for v in base['player_calls']if v['method']=='maybeBackOffFromEdge_entry'];phase_ends=[v['sequence']for v in base['player_calls']if v['method']=='maybeBackOffFromEdge_exit']
    assert len(phase_starts)==len(phase_ends)==1
    prior={tuple(r['position'])for q in base['queries']if q['method']=='noCollision'and phase_starts[0]<q['entry_sequence']<q['exit_sequence']<phase_ends[0]for r in q['reads']}
    late=[r for q in base['queries']if q['method']=='blockCollisions'for r in q['reads']if tuple(r['position'])not in prior]
    if late:
        point=late[0];edit=lambda name,kind:'|'.join(map(str,[name,'edit',*(v&0xffffffff for v in point['position']),kind]))
        add('after-backoff-world-failure',error='movement:move:unsupported-block-state:',setup=[edit('inject-unknown',4)],cleanup=[edit('repair-unknown',D.NAMES.index(point['block_id']))])
    add('late-finish-injection',error='finish:invalid-context:99',injected=True)
    return specs

def policies(data,prefix):
    rows=[];receipts=[];base=next(s for c in data['cases']for s in c['steps']if s['admission']['neutral_context'])
    for spec in policy_specs(data):
        id=spec['id'];step=spec['step'];commands=D.edits(step['world_writes'],'write')+spec.get('setup',[])
        if spec.get('nested'):
            commands += [request(step,'initialize',True),'nested|nest',request(step,id),'child|select-child',request(base,'recovery',True)];recovery=base
        elif spec.get('injected'):
            commands += [request(step,'initialize',True),id+'|finish-fail',request(base,'recovery',True)];recovery=base
        else:
            commands.append(request(step,id,True,clip=spec.get('clip'),shape=spec.get('shape',0),**spec.get('changes',{})))
            recovery=step if spec.get('recover_same')else base
            commands+=spec.get('cleanup',[])+[request(recovery,'recovery',not spec.get('recover_same',False))]
        commands.append('final|table-probe');p,q,c,s,receipt=native(commands,prefix+id);receipts.append(receipt)
        same_owner(p,id,child=spec.get('nested',False));assert p[id,'error'][0].startswith(spec['error']),(id,spec['error'],p.get((id,'error')))
        assert not q.get(id)and not c.get(id)and not s.get(id)
        compare(recovery,'recovery',p,q,c,s);assert p['final','table-owner']==['0']
        rows.append({'id':id,'error':p[id,'error'][0],'all_prior_view_support_minor_history_cells_clocks_queues_retained':True,'tables_recovered':True,'same_owner_reused_without_reseeding':bool(spec.get('recover_same')),'returned_child_owner_reused':bool(spec.get('nested')),'synthetic_finish_branch_injection':bool(spec.get('injected'))})
    return rows,receipts

def remap(data,prefix):
    path=WORK/'remapped.tsv';path.parent.mkdir(parents=True,exist_ok=True);order=['minecraft:oak_planks','minecraft:stone','minecraft:air','minecraft:dirt']
    path.write_text('block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json\n'+''.join(f'{i}\t{name}\t{i}\t1\t{i}\t[]\n'for i,name in enumerate(order)))
    env=dict(os.environ);env['MC_BLOCK_REGISTRY']=str(path);selected=[c for c in data['cases']if c['id']in ['dynamic_floor','held_floor','held_wall','held_shift_edge']];assert len(selected)==4
    rows,excluded,receipts=corpus({'cases':selected},prefix,env);return {'registry':pin(path),'native_travel_calls':len(rows),'case_ids':[c['id']for c in selected],'rows':rows,'excluded':excluded},receipts

def protocol(data):
    observed=0
    for case in data['cases']:
        for index,step in enumerate(case['steps']):
            widths=[len(part.split('|'))for part in request(step,case['id']+':'+str(index),index==0).split(';')]
            assert widths==[5,30,18,6,18,14,8],(case['id'],widths)
            observed+=1
    return {'actual_requests':observed,'word_widths':[5,30,18,6,18,14,8],'scope':'Input protocol arities/ranges only; no native gameplay comparison.'}

def prepare(data,ordinary):
    g=generation();specs=policy_specs(data);steps=[s for c in data['cases']for s in c['steps']]
    report={'status':'ordinary-prepared-native-kernel-pending','source':pin(SOURCE),'harness':pin(HARNESS),'tools':tools(),'reference':pin(FIXTURE),'table':pin(TABLE),'generation':g,'generation_sha256':digest(g),'generation_count':len(g),'ordinary':ordinary,'actual_cases':len(data['cases']),'actual_travel_attempts':len(steps),'admitted_actual_travel_calls':sum(s['admission']['neutral_context']for s in steps),'actual_miss_calls':sum(s['ray_observation']['status']=='Miss'for s in steps),'protocol':protocol(data),'policy_recoveries':len(specs),'policies_sha256':digest(specs),'production_laws':SOURCE.read_text().count('\nlaw '),'queued_command':'PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_travel_history.py --skip-ordinary','caps_seconds':{'native_build':600,'native_process':120,'full_kernel':60},'scope':'Conditional neutral loaded-client travel field projection; no full tick or inferred ground/attribute/ray provenance.'}
    write_json(ROOT/'evidence/local-travel-history-preparation.json',report);return report

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--prepare',action='store_true');parser.add_argument('--skip-build',action='store_true');parser.add_argument('--skip-ordinary',action='store_true');parser.add_argument('--skip-kernel',action='store_true');parser.add_argument('--kernel-only',action='store_true');a=parser.parse_args()
    integrity=P.verify(True);data=json.loads(FIXTURE.read_text());ordinary=[]
    if not a.skip_ordinary:
        ordinary=[bound('ordinary-source',60),bound('ordinary-harness',60)];assert all(r['status']=='passed'for r in ordinary)
    if a.prepare:
        report=prepare(data,ordinary);print(json.dumps({k:report[k]for k in ['status','actual_cases','actual_travel_attempts','admitted_actual_travel_calls','policy_recoveries','generation_count','production_laws']}));return
    initial=generation();tp=tools();ref=pin(FIXTURE);table=pin(TABLE)
    if a.kernel_only:
        verdict=bound('kernel',60);write_json(ROOT/'evidence/local-travel-history-proof-status.json',{'status':'passed'if verdict['status']=='passed'else'unverified','attempt':pin(ROOT/'evidence/local-travel-history-kernel.json'),'scope':'One full unchanged imported harness attempt includes exact source laws; no projected source or retry.'});return
    build=json.loads((ROOT/'evidence/local-travel-history-build.json').read_text())if a.skip_build else bound('build',600)
    assert build['status']=='passed'and build['generation']==initial and build['binary']==pin(BINARY)
    full=json.loads((WORK/'native-build-full.json').read_text())
    for dep in full['dependencies']:
        path=Path(dep['lookup']);assert path.resolve()==Path(dep['path'])and fingerprint(path)['sha256']==dep['sha256']and path.stat().st_size==dep['bytes'],'Native dependency changed: '+str(path)
    runs=[]
    for run in range(2):
        rows,excluded,receipts=corpus(data,f'run{run}-case');policy,extra=policies(data,f'run{run}-policy-');mapped,more=remap(data,f'run{run}-remap');receipts+=extra+more
        raw=WORK/f'run{run}-full.json';results={'rows':rows,'excluded':excluded,'policies':policy,'remap':mapped};write_json(raw,{**results,'receipts':receipts})
        runs.append({'admitted_travel_calls':len(rows),'excluded':excluded,'policy_recoveries':len(policy),'remapped_calls':mapped['native_travel_calls'],'result_sha256':digest(results),'seconds':round(sum(r['seconds']for r in receipts),6),'raw':pin(raw),'native_processes':len(receipts),'actual_miss_calls':sum(r['clip_status']=='Miss'for r in rows),'skipped_position_calls':sum(not r['position_gate']for r in rows)})
    assert runs[0]['result_sha256']==runs[1]['result_sha256']
    report={'status':'passed','generation':initial,'generation_sha256':digest(initial),'generation_unchanged':initial==generation(),'tools':tp,'tools_unchanged':tp==tools(),'reference':ref,'reference_unchanged':ref==pin(FIXTURE),'table':table,'table_unchanged':table==pin(TABLE),'build':pin(ROOT/'evidence/local-travel-history-build.json'),'binary':pin(BINARY),'reference_integrity':integrity,'runs':runs,'historical_build_tools':build['tools'],'immutable_native_reused':a.skip_build,'scope':'Bounded direct LocalPlayer.travel preparation/movement/support/minor/no-damage history/gravity-drag field projection; actual rays and conditional current attributes/ground only.'}
    assert report['generation_unchanged']and report['tools_unchanged']and report['reference_unchanged']and report['table_unchanged'];write_json(ROOT/'evidence/local-travel-history-native.json',report);print(json.dumps({'native_status':'passed','runs':[{k:r[k]for k in ['admitted_travel_calls','policy_recoveries','remapped_calls','seconds']}for r in runs]}),flush=True)
    if not a.skip_kernel:bound('kernel',60)
if __name__=='__main__':main()
