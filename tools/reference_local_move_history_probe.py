#!/usr/bin/env python3
"""Fresh whole actual moves with super-calling reset/ray history observations."""
from __future__ import annotations
import argparse,base64,copy,hashlib,json,os,signal,subprocess,time,zipfile
from pathlib import Path
from reference_inventory import ROOT,JAVA,canonical,fingerprint,write_json
from reference_model_probe import CLIENT,verified_client_classpath
import reference_local_move_world_probe as LM

OUTPUT=ROOT/'reference/local_move_history.json'
RAW=ROOT/'build/local-move-history-reference'
CLASS='net.minecraft.fixture.LocalMoveHistoryReceiverFixture'
FROZEN_LM_SOURCE='37b814cb487ede0ba517c0282e3e4e5b2cebb4a54f24888c302a7c49bf1f01bd'
FROZEN_LM_REFERENCE='94afc9b4b47138115207d1d6e5936c9498cea49008f6c86e52d4b1932178a820'

def sha(value):return hashlib.sha256(canonical(value)).hexdigest()

def inputs():
    cases,_=LM.inputs();cases=copy.deepcopy(cases)
    def add(name,moves,**changes):cases['cases'].append({'id':name,'initial':LM.initial(**changes),'steps':moves})
    d=LM.LC.db
    add('history-long-air-miss',[LM.step((0,-1.125,0))],position=[d(.5),d(10),d(.5)],grounded=False,fall_distance_f64_bits=d(.3))
    add('history-long-air-zero-no-ray',[LM.step((0,-1.125,0))],position=[d(.5),d(10),d(.5)],grounded=False,fall_distance_f64_bits=d(0))
    add('history-negative-gate-skip',[LM.step((1,-.0001,0))],position=[d(1.-.6000000238418579/2),d(2),d(.5)],grounded=False,fall_distance_f64_bits=d(.5),step_attribute_f64_bits=d(0),world_writes=[{'position':[1,2,0],'block':'stone'},{'position':[1,3,0],'block':'stone'}])
    for old in [.3,3.8749989999999994,3.874999]:
        add('history-landing:'+str(old),[LM.step((0,-.25,0))],position=[d(.5),d(1.125),d(.5)],grounded=False,fall_distance_f64_bits=d(old))
    add('history-chained',[LM.step((0,-.2,0)),LM.step((0,-1.125,0)),LM.step((0,-.25,0))],position=[d(.5),d(10),d(.5)],grounded=False,fall_distance_f64_bits=d(.3))
    add('history-negative-zero',[LM.step((-0.,-0.,-0.))],fall_distance_f64_bits='8000000000000000',main_support=[0,0,0])
    return cases

def derived_source():
    assert hashlib.sha256(LM.SOURCE.encode()).hexdigest()==FROZEN_LM_SOURCE,'Frozen whole-move receiver changed'
    source=LM.SOURCE.replace(LM.CLASS,CLASS).replace('LocalMoveWorldReceiverFixture','LocalMoveHistoryReceiverFixture').replace('LOCAL_MOVE_WORLD_','LOCAL_MOVE_HISTORY_')
    needle='  public boolean noCollision(Entity p,AABB b)';assert source.count(needle)==1
    source=source.replace(needle,r'''
  public BlockHitResult clip(net.minecraft.world.level.ClipContext context){add(Map.of("method","fallClip_entry","from",vector(context.getFrom()),"to",vector(context.getTo())));BlockHitResult result=super.clip(context);add(Map.of("method","fallClip_exit","type",result.getType().toString(),"position",position(result.getBlockPos())));return result;}
'''+needle)
    source=source.replace('final List<Map<String,Object>> calls=new ArrayList<>();','final List<Map<String,Object>> calls=new ArrayList<>(); boolean historyPositionApplied=false;')
    source=source.replace('public void move(MoverType type,Vec3 movement){event(', 'public void move(MoverType type,Vec3 movement){historyPositionApplied=false;event(')
    source=source.replace('public void recordMovement(MoverType type,Vec3 movement){event(', 'public void recordMovement(MoverType type,Vec3 movement){historyPositionApplied=true;event(')
    source=source.replace('event("setOnGroundWithMovement_entry","grounded",ground,"horizontal",horizontal,"movement",movement==null?null:vector(movement))', 'event("setOnGroundWithMovement_entry","grounded",ground,"horizontal",horizontal,"movement",movement==null?null:vector(movement),"resolved_length_squared_f64_bits",bits(movement.lengthSqr()),"history_ray_required",historyPositionApplied && fallDistance != 0.0 && movement.lengthSqr() >= 1.0)')
    needle='  public void move(MoverType type,Vec3 movement)';assert source.count(needle)==1
    source=source.replace(needle,r'''
  public void resetFallDistance(){event("resetFallDistance_entry");super.resetFallDistance();event("resetFallDistance_exit");}
'''+needle)
    needle='m.put("no_physics",p.noPhysics);';assert source.count(needle)==1
    source=source.replace(needle,needle+'m.put("in_water",p.isInWater());m.put("safe_fall_distance_f64_bits",bits(p.getAttributeValue(Attributes.SAFE_FALL_DISTANCE)));m.put("fall_damage_multiplier_f64_bits",bits(p.getAttributeValue(Attributes.FALL_DAMAGE_MULTIPLIER)));m.put("ignoring_impulse_fall_damage",p.isIgnoringFallDamageFromCurrentImpulse());')
    needle='p.move(MoverType.valueOf(step.get("mover").getAsString()),vec(step.getAsJsonArray("requested")));if(observed)t.capture=false;Map<String,Object> row=new TreeMap<>();';assert source.count(needle)==1
    source=source.replace(needle,'Map<String,Object> row=new TreeMap<>();try{p.move(MoverType.valueOf(step.get("mover").getAsString()),vec(step.getAsJsonArray("requested")));row.put("actual_returned",true);}catch(Throwable error){Throwable root=error;while(root.getCause()!=null)root=root.getCause();row.put("actual_returned",false);row.put("error_class",root.getClass().getName());row.put("error_message",String.valueOf(root.getMessage()));}if(observed)t.capture=false;')
    return source

SOURCE=derived_source()
def sources(values):
    result=LM.LC.LI.receiver_sources();result[CLASS]=SOURCE.replace('__INPUT_BASE64__',LM.LC.LI.java_string(base64.b64encode(canonical(values)).decode()));return result

def dependency():
    assert fingerprint(LM.OUTPUT)['sha256']==FROZEN_LM_REFERENCE
    return {'whole_move_probe':fingerprint(Path(LM.__file__)),'whole_move_reference':fingerprint(LM.OUTPUT),'whole_move_receiver_sha256':FROZEN_LM_SOURCE,'boundary':LM.dependencies()}

EXTRA_FIELDS={'in_water','safe_fall_distance_f64_bits','fall_damage_multiplier_f64_bits','ignoring_impulse_fall_damage'}
EXTRA_EVENTS={'fallClip_entry','fallClip_exit','resetFallDistance_entry','resetFallDistance_exit'}
def prior_projection(case):
    c=copy.deepcopy(case)
    for step in c['steps']:
        for key in ['before','expected']:
            for extra in EXTRA_FIELDS:step[key].pop(extra,None)
        step['player_calls']=[v for v in step['player_calls']if v['method']not in EXTRA_EVENTS]
        for v in step['player_calls']:
            for extra in ['resolved_length_squared_f64_bits','history_ray_required']:v.pop(extra,None)
        step['phase_order']=[v for v in step['phase_order']if v not in EXTRA_EVENTS]
        # New observer entries shift sequence counters but never query order.
        skipped=step.pop('added_sequences')
        def renumber(value):return value-sum(s<value for s in skipped)
        for q in step['queries']:
            q['entry_sequence']=renumber(q['entry_sequence']);q['exit_sequence']=renumber(q['exit_sequence'])
        for v in step['player_calls']+step['sample_reads']:v['sequence']=renumber(v['sequence'])
        for key in ['actual_returned','error_class','error_message','history_phase','ray_observation']:step.pop(key,None)
    return c

def collect(values,rows):
    # Existing collector projects independently observed actual query/field data;
    # it never calculates the move, ray result or fall expected value in Python.
    projected=LM.collect(values,rows)
    for case in projected:
        observed=next(r for r in rows if r['id']==case['id']and r['observed'])
        for step,raw in zip(case['steps'],observed['steps'],strict=True):
            step.update({k:raw[k]for k in ['actual_returned','error_class','error_message']if k in raw})
            events=raw['events'];clips=[e for e in events if e['method']=='fallClip_exit'];assert len(clips)<=1
            entry=next(e for e in events if e['method']=='checkFallDamage_entry');exit=next((e for e in events if e['method']=='checkFallDamage_exit'),None)
            ground=next(e for e in events if e['method']=='setOnGroundWithMovement_entry')
            step['history_phase']={'resolved_length_squared_f64_bits':ground['resolved_length_squared_f64_bits'],'actual_ray_required':ground['history_ray_required'],'resolved_y_f64_bits':entry['movement_f64_bits'],'on_ground':entry['grounded'],'sampled_block':entry['block_id'],'sampled_position':entry['position'],'entry':entry['body']['fall_distance_f64_bits'],'exit':None if exit is None else exit['body']['fall_distance_f64_bits'],'reset_calls':[e for e in events if e['method']in ['resetFallDistance_entry','resetFallDistance_exit']]}
            step['ray_observation']={'clip_calls':[e for e in events if e['method']in ['fallClip_entry','fallClip_exit']],'status':'Miss'if clips and clips[0]['type']=='MISS'else'Hit'if clips else'NotRequired'}
            step['added_sequences']=[e['sequence']for e in events if e['method']in EXTRA_EVENTS]
            assert ground['history_ray_required']==bool(clips),'Actual ray call/precondition disagree'
            assert entry['movement_f64_bits']==step['resolved'][1] and entry['grounded']==step['expected']['body_flags'][0]
            assert not step['before']['in_water']and not step['expected']['in_water'];assert step['before']['safe_fall_distance_f64_bits']=='4008000000000000'and step['before']['fall_damage_multiplier_f64_bits']=='3ff0000000000000'and not step['before']['ignoring_impulse_fall_damage']
            names=step['phase_order'];assert names.index('checkSupportingBlock_exit')<names.index('checkFallDamage_entry')
            if step['minor_called']:assert names.index('isHorizontalCollisionMinor_exit')<names.index('checkFallDamage_entry')
            if raw['actual_returned']:assert names.index('checkFallDamage_exit')<names.index('getBlockSpeedFactor_entry')
            else:assert raw['error_class']=='java.lang.NoSuchFieldError'and'gameRenderer'in raw['error_message']
    old=json.loads(LM.OUTPUT.read_text())['cases'];assert [prior_projection(c)for c in projected[:len(old)]]==old,'Additional super-calling observers changed the prior complete actual projection'
    return projected

def run(values,label):
    dep=dependency();paths,provenance=verified_client_classpath();ss=sources(values);payload={'sources':ss,'client_jar':str(CLIENT),'mode':'move_history'};encoded=base64.b64encode(canonical(payload)).decode();launcher=LM.LC.LI.RECEIVER_LAUNCHER.replace('net.minecraft.fixture.LocalInputReceiverFixture',CLASS).replace('Base64.getDecoder().decode(args[0])','Base64.getDecoder().decode('+LM.LC.LI.java_string(encoded)+')',1)
    command=[str(JAVA),'--source','25','--class-path',':'.join(map(str,paths)),'/dev/stdin'];start=time.monotonic();p=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
    try:stdout,stderr=p.communicate(launcher,timeout=120)
    except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);stdout,stderr=p.communicate();raise RuntimeError('120s whole-move history watchdog expired')
    parse=lambda prefix:[json.loads(s[len(prefix):])for s in stdout.splitlines()if s.startswith(prefix)]
    rows=parse('LOCAL_MOVE_HISTORY_JSON:');loaded=parse('LOCAL_INPUT_CLASSES:');runtime=parse('LOCAL_MOVE_HISTORY_RUNTIME:');RAW.mkdir(parents=True,exist_ok=True);rawpath=RAW/(label+'.full.json');write_json(rawpath,{'rows':rows,'loaded_official_classes':loaded,'runtime':runtime,'sources':ss,'launcher':launcher,'stdout':stdout,'stderr':stderr,'returncode':p.returncode,'command':command})
    assert p.returncode==0,('Actual Java failure',p.returncode,str(rawpath));assert len(loaded)==len(runtime)==1 and len(rows)==2*len(values['cases'])
    with zipfile.ZipFile(CLIENT)as jar:
        for name,h in loaded[0].items():assert hashlib.sha256(jar.read(name.replace('.','/')+'.class')).hexdigest()==h,'Loaded official class mismatch: '+name
    projected=collect(values,rows)
    report={'schema':'local-move-history-reference-summary-v1','status':'passed','scope':'Fresh actual whole moves; additional observers call super; exact original whole-move projection preserved. Damaging callback failures retained separately.','producer':fingerprint(Path(__file__)),'dependency':dep,'provenance':provenance,'runtime_files':LM.runtime_files(),'source_sha256':hashlib.sha256(SOURCE.encode()).hexdigest(),'expanded_source_sha256':{n:hashlib.sha256(s.encode()).hexdigest()for n,s in ss.items()},'launcher_sha256':hashlib.sha256(LM.LC.LI.RECEIVER_LAUNCHER.encode()).hexdigest(),'raw_report':{'path':str(rawpath.relative_to(ROOT)),**fingerprint(rawpath)},'inputs_sha256':sha(values),'observations_sha256':sha(rows),'cases_sha256':sha(projected),'observation_count':len(rows),'case_count':len(projected),'step_count':sum(len(c['steps'])for c in projected),'loaded_official_class_count':len(loaded[0]),'loaded_official_class_tree_sha256':sha(loaded[0]),'runtime_classes':runtime[0],'prior_cases_exact':True,'execution':{'command':command,'seconds':round(time.monotonic()-start,6),'returncode':p.returncode,'launcher_sha256':hashlib.sha256(launcher.encode()).hexdigest(),'stdout_sha256':hashlib.sha256(stdout.encode()).hexdigest(),'stderr_sha256':hashlib.sha256(stderr.encode()).hexdigest(),'reproduce':'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_move_history_probe.py --'+label}}
    write_json(ROOT/f'evidence/local-move-history-reference-{label}.json',report);return projected,report

def verify_data(data,provenance):
    assert data['pin']=='26.3'and data['schema']==1;assert data['inputs_sha256']==sha(inputs());assert data['provenance']==provenance;assert data['dependency']==dependency();assert data['source_sha256']==hashlib.sha256(SOURCE.encode()).hexdigest();assert data['expanded_source_sha256']=={n:hashlib.sha256(s.encode()).hexdigest()for n,s in sources(inputs()).items()};assert data['launcher_sha256']==hashlib.sha256(LM.LC.LI.RECEIVER_LAUNCHER.encode()).hexdigest();assert data['runtime_files']==LM.runtime_files();assert data['cases_sha256']==sha(data['cases'])
    path=ROOT/data['raw_report']['path'];assert data['raw_report']=={'path':data['raw_report']['path'],**fingerprint(path)};raw=json.loads(path.read_text());assert data['observations_sha256']==sha(raw['rows']);assert data['loaded_official_class_tree_sha256']==sha(raw['loaded_official_classes'][0]);assert data['cases']==collect(inputs(),raw['rows']);return data

def verify(selftest=False):
    _,provenance=verified_client_classpath();data=verify_data(json.loads(OUTPUT.read_text()),provenance);report={'status':'passed','scope':'Stored reference/provenance integrity; no fresh Java run','reference':fingerprint(OUTPUT),'case_count':len(data['cases'])}
    if selftest:
        report['failure_injections']=[]
        for name,path in [('client',['provenance','client','sha256']),('runtime',['provenance','java','sha256']),('library',['provenance','libraries',0,'sha256']),('source',['source_sha256']),('class_tree',['loaded_official_class_tree_sha256']),('observation',['cases',0,'steps',0,'history_phase','exit'])]:
            altered=copy.deepcopy(data);target=altered
            for k in path[:-1]:target=target[k]
            target[path[-1]]='injected-mismatch'
            try:verify_data(altered,provenance)
            except AssertionError:report['failure_injections'].append({'injection':name,'rejected':True})
            else:raise AssertionError('Corrupt reference accepted: '+name)
    write_json(ROOT/'evidence/local-move-history-reference-integrity.json',report);return report

def main():
    parser=argparse.ArgumentParser();group=parser.add_mutually_exclusive_group(required=True)
    for flag in ['extract','rerun','selftest','verify']:group.add_argument('--'+flag,action='store_true')
    a=parser.parse_args()
    if a.extract:
        cases,r=run(inputs(),'extract');data={k:r[k]for k in ['provenance','dependency','runtime_files','source_sha256','expanded_source_sha256','launcher_sha256','inputs_sha256','observations_sha256','loaded_official_class_count','loaded_official_class_tree_sha256','runtime_classes','raw_report','cases_sha256']};data.update(schema=1,pin='26.3',cases=cases);write_json(OUTPUT,data);r['reference']=fingerprint(OUTPUT);write_json(ROOT/'evidence/local-move-history-reference-extract.json',r)
    elif a.rerun:
        verify();old=json.loads(OUTPUT.read_text());cases,r=run(inputs(),'rerun');assert cases==old['cases'];assert r['loaded_official_class_tree_sha256']==old['loaded_official_class_tree_sha256'];r['independent_parity']=True;write_json(ROOT/'evidence/local-move-history-reference-rerun.json',r)
    else:r=verify(a.selftest)
    print(json.dumps({k:r[k]for k in ['status','case_count','step_count','prior_cases_exact','independent_parity','failure_injections']if k in r},sort_keys=True))
if __name__=='__main__':main()
