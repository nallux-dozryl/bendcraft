#!/usr/bin/env python3
"""Orchestrate actual Java history fixtures against the owned Bend reducer."""
from __future__ import annotations
import argparse, collections, hashlib, json, os, signal, subprocess, sys, time
from pathlib import Path
import reference_player_fall_history_probe as P
from reference_inventory import ROOT, canonical, fingerprint, write_json
from build_native import ensure_native

BEND=Path('/Users/chuah/.bend/bin/bend')
SOURCE=ROOT/'src/player_fall_history.bend'
HARNESS=ROOT/'tests/player_fall_history.bend'
BINARY=ROOT/'build/player-fall-history-tests'
RECEIPT=ROOT/'build/player-fall-history-build.json'
NATIVE=ROOT/'evidence/player-fall-history-native.json'
KERNEL=ROOT/'evidence/player-fall-history-kernel.json'
PREPARED=ROOT/'evidence/player-fall-history-prepared.json'

def sha(b):return hashlib.sha256(b).hexdigest()
def words(text):value=int(text,16);return [value>>32,value&0xffffffff]
def result(distance,kind=None,**fields):
    r={'ok':kind is None,'distance':words(distance)}
    if kind:r['error']={'kind':kind,**fields}
    return r
def args(op,distance,y='0000000000000000',squared='0000000000000000',mode=0,clip=0,applied=False,ground=False):
    return [op|(mode<<4)|(clip<<8)|(int(applied)<<12)|(int(ground)<<13),*words(distance),*words(y),*words(squared)]

def cases(data):
    rows=[]
    def add(name,argv,expected,category):rows.append({'id':name,'args':argv,'expected':expected,'category':category})
    for fixture in data['fixtures']:
        for i,step in enumerate(fixture['observations']):
            name=fixture['id']+'/'+str(i);before=step['before']['distance_f64_bits'];after=step['expected']['distance_f64_bits'];inp=step['input'];op=inp['operation'];phases=step['phases']
            assert step['before']['safe_fall_distance_f64_bits']=='4008000000000000'
            assert step['before']['fall_damage_multiplier_f64_bits']=='3ff0000000000000'
            assert not step['before']['ignoring_impulse_fall_damage']
            assert step['before']['local_authority'] and not step['before']['in_water'] and not step['expected']['in_water']
            if op=='jump':
                assert step['ok'] and before==after and not phases,'Jump changes history; baseline no longer neutral'
                continue
            if op in ['reset','clamp']:
                assert step['ok'];argv=args(1 if op=='reset'else 2,before,inp.get('velocity_y_f64_bits','0000000000000000'))
                add(name,argv,result(after),'actual_'+op);continue
            if op=='move' and inp.get('no_physics'):
                assert step['ok'] and before==after and not any(p['phase']=='check_entry'for p in phases)
                add(name,args(0,before,inp['requested_f64_bits'][1],mode=1),result(after),'actual_no_physics_early_bypass');continue
            entries=[p for p in phases if p['phase']=='check_entry'];assert len(entries)==1
            entry=entries[0];y=entry['resolved_y_f64_bits'];ground=entry['ground']
            assert entry['block']in ['minecraft:air','minecraft:stone'],'Unadmitted callback block'
            if op=='move':
                assert step['direct_collision_f64_bits'][1]==y,'Actual collide helper differs from move callback Y'
                applied=any(p['phase']=='record_movement'for p in phases)
                assert applied==step['java_gate_diagnostic'],'Actual application gate differs from Java diagnostic'
                squared=step['resolved_length_squared_f64_bits'];clips=step['clip_calls']
                assert len(clips)<=1 and all(c['type']=='MISS'for c in clips),'Unadmitted fall-reset ray hit'
                clip=1 if clips else 0
            else:assert op=='check';applied=False;squared='0000000000000000';clip=0
            argv=args(0,before,y,squared,clip=clip,applied=applied,ground=ground)
            if not step['ok']:
                assert step['error_class']=='java.lang.NoSuchFieldError' and 'gameRenderer'in step['error_message'] and ground
                assert step['expected']['calculated_default_fall_damage']>0 and not any(p['phase']=='reset_exit'for p in phases)
                expected=result(before,'UnsupportedLanding');category='policy_excludes_actual_damaging_callback_failure'
            elif after in ['7ff0000000000000','fff0000000000000']:
                expected=result(before,'NonFiniteResult');category='policy_excludes_actual_f32_overflow'
            else:
                if ground:
                    resets=[p for p in phases if p['phase']=='reset_entry'];assert len(resets)==1 and resets[0]['history']['calculated_default_fall_damage']<=0,'Grounded success is not default no-damage landing'
                expected=result(after);category='actual_move'if op=='move'else'actual_direct_check'
            add(name,argv,expected,category)
            if expected.get('error'):
                recovery={'first':expected,'recovered':result('0000000000000000')}
                add(name+'/recover',[argv[0]|3,*argv[1:]],recovery,'owned_recovery_after_excluded_context')
        if fixture['id']=='chained-two-descents':
            a,b=fixture['observations'];assert a['ok'] and b['ok'] and a['input']==b['input'] and a['expected']==b['before']
            assert a['direct_collision_f64_bits']==b['direct_collision_f64_bits'] and not a['clip_calls'] and not b['clip_calls']
            add(fixture['id']+'/same_owned_history',args(4,fixture['distance_f64_bits'],a['direct_collision_f64_bits'][1],a['resolved_length_squared_f64_bits'],applied=True),{'first_status':{'ok':True},'second':result(b['expected']['distance_f64_bits'])},'actual_chained_owned_history')
    clean='3ff4000000000000';zero='0000000000000000';one='3ff0000000000000';negative='bff0000000000000'
    # These are checked Bend admission/retention policies, not Java rejections.
    for mode in range(2,7):
        bad=result(clean,'UnsupportedMode',mode=mode)
        add('mode:'+str(mode),args(0,clean,mode=mode),bad,'unsupported_mode_retention')
        add('mode-recovery:'+str(mode),args(3,clean,mode=mode),{'first':bad,'recovered':result(zero)},'unsupported_mode_owner_recovery')
    for applied,squared in [(False,zero),(True,one)]:
        for clip in range(4):
            needed=applied
            kind=None if (needed and clip==1)or(not needed and clip==0)else 'UnsupportedResetHit'if clip==2 else'MissingClipObservation'if needed else'UnexpectedClipObservation'
            add(f'clip:{applied}:{clip}',args(0,clean,squared=squared,applied=applied,clip=clip),result(clean,kind),'clip_observation_admission')
    add('negative-square',args(0,clean,squared=negative),result(clean,'InvalidLengthSquared'),'negative_length_square_retention')
    for field in range(4):
        for value in ['7ff0000000000000','fff0000000000000','7ff8000000000000','7ff123456789abcd']:
            d=value if field==0 else clean;y=value if field in [1,3]else zero;s=value if field==2 else zero
            op=2 if field==3 else 0;bad=result(d,'NonFinite',field=field)
            add(f'nonfinite:{field}:{value}',args(op,d,y,s),bad,'nonfinite_field_retention')
            if field==0:
                add(f'nonfinite-reset:{value}',args(1,d),result(d,'NonFinite',field=0),'nonfinite_reset_retention')
                add(f'nonfinite-clamp:{value}',args(2,d),result(d,'NonFinite',field=0),'nonfinite_history_clamp_retention')
            else:
                first=result(d,'NonFinite',field=field)
                if field in [1,2]:add(f'nonfinite-recovery:{field}:{value}',args(3,d,y,s),{'first':first,'recovered':result(zero)},'nonfinite_request_owner_recovery')
    return rows

def run(command,timeout=600,allow_failure=False):
    command=list(map(str,command));start=time.monotonic();p=subprocess.Popen(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
    try:stdout,stderr=p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid,signal.SIGKILL);stdout,stderr=p.communicate();return {'command':command,'status':'timeout','exit_code':None,'seconds':round(time.monotonic()-start,6),'stdout':stdout,'stderr':stderr}
    r={'command':command,'status':'passed'if p.returncode==0 else'failed','exit_code':p.returncode,'seconds':round(time.monotonic()-start,6),'stdout':stdout,'stderr':stderr}
    if p.returncode and not allow_failure:raise AssertionError(r)
    return r

def verify_build(record):
    for d in record['dependencies']:
        path=Path(d['lookup']);assert str(path.resolve())==d['path'] and path.is_file() and path.stat().st_size==d['bytes'] and sha(path.read_bytes())==d['sha256'],'Native dependency changed: '+str(path)
    path=Path(record['artifact']);assert fingerprint(path)['sha256']==record['binary_sha256'] and path.stat().st_size==record['binary_bytes'],'Native executable changed';return path

def build_summary(build):
    kept={k:build[k]for k in ['artifact','binary_bytes','binary_sha256','cache_hit','cache_key','compiler','emitted_c_sha256','identity','path','timings']}
    kept.update(full_receipt={'path':str(RECEIPT.relative_to(ROOT)),**fingerprint(RECEIPT)},dependency_count=len(build['dependencies']),dependencies_sha256=sha(canonical(build['dependencies'])),project_dependencies=[d for d in build['dependencies']if d['path'].startswith(str(ROOT)+'/')]);return kept

def native_run(binary,rows):
    results=[];seconds=0.;commands=[]
    for start in range(0,len(rows),24):
        group=rows[start:start+24];command=[binary,'--gpu','off','--threads','1','--',*[str(a)for r in group for a in r['args']]];r=run(command,180);assert r['status']=='passed',r
        observed=[json.loads(s)for s in r['stdout'].splitlines()if s.startswith('{')];assert len(observed)==len(group),(len(observed),len(group),r['stdout'][-500:])
        for expected,actual in zip(group,observed):assert expected['expected']==actual,(expected['id'],expected['expected'],actual)
        results+=observed;seconds+=r['seconds'];commands.append({'case_start':start,'case_count':len(group),'seconds':r['seconds'],'command_prefix':[str(binary),'--gpu','off','--threads','1','--'],'arguments_sha256':sha(canonical([r['args']for r in group]))})
    return {'status':'passed','case_count':len(rows),'observations_sha256':sha(canonical(results)),'seconds':round(seconds,6),'runs':commands}

def main():
    p=argparse.ArgumentParser();p.add_argument('--prepare',action='store_true');p.add_argument('--build-only',action='store_true');p.add_argument('--skip-build',action='store_true');p.add_argument('--skip-checks',action='store_true');p.add_argument('--kernel',action='store_true');a=p.parse_args()
    if a.build_only:
        b=ensure_native(HARNESS,BINARY,bend=BEND);write_json(RECEIPT,b);print(json.dumps({'status':'built','artifact':b['artifact'],'binary_sha256':b['binary_sha256'],'cache_hit':b['cache_hit']}));return
    checks=[]
    if not a.skip_checks:
        for path in [SOURCE,HARNESS]:checks.append(run([BEND,path,'--check-only'],30));assert checks[-1]['status']=='passed',checks[-1]
    integrity=P.verify_existing(True);data=json.loads(P.OUTPUT.read_text());rows=cases(data)
    if a.prepare:
        record={'status':'prepared_not_native_or_kernel_verified','source':fingerprint(SOURCE),'harness':fingerprint(HARNESS),'runner':fingerprint(Path(__file__)),'probe':fingerprint(Path(P.__file__)),'reference':fingerprint(P.OUTPUT),'actual_fixture_count':len(data['fixtures']),'actual_step_count':sum(len(f['observations'])for f in data['fixtures']),'native_case_count':len(rows),'expected_cases_sha256':sha(canonical(rows)),'case_categories':dict(collections.Counter(r['category']for r in rows)),'ordinary':checks,'reference_integrity':integrity,'queued_commands':['PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_fall_history.py','PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_fall_history.py --kernel'],'limits':'No heavy attempt has been made by --prepare. No body/world mutation, damaging callbacks, reset-ray hits, water/flight/climbing/effect lifecycle, or full tick parity claim.'};write_json(PREPARED,record);print(json.dumps(record,sort_keys=True));return
    if a.kernel:
        attempts=[run([BEND,path,'--verdict'],60,True)for path in [SOURCE,HARNESS]]
        record={'status':'passed'if all(r['status']=='passed'for r in attempts)else'incomplete','scope':'Full imported production source plus twelve stated helper laws; not universal Minecraft lifecycle parity','source':fingerprint(SOURCE),'harness':fingerprint(HARNESS),'compiler':fingerprint(BEND),'attempts':attempts};write_json(KERNEL,record);print(json.dumps({'kernel_status':record['status'],'attempts':[{'status':r['status'],'seconds':r['seconds']}for r in attempts]}));return
    if not a.skip_build:
        b=run([sys.executable,Path(__file__),'--build-only'],600);assert b['status']=='passed',b
    build=json.loads(RECEIPT.read_text());binary=verify_build(build);first=native_run(binary,rows);second=native_run(binary,rows);assert first['observations_sha256']==second['observations_sha256'],'Native repeat differs';verify_build(build)
    evidence={'schema':'player-fall-history-native-summary-v1','status':'passed_neutral_history_projection','pin':'26.3','scope':'Owned fall-distance field only. Actual normal-constructor movement/checkFallDamage/reset/accumulation-clamp observations, narrow no-damage/clip-miss admission and atomic policy errors.','source':fingerprint(SOURCE),'harness':fingerprint(HARNESS),'runner':fingerprint(Path(__file__)),'probe':fingerprint(Path(P.__file__)),'reference':fingerprint(P.OUTPUT),'build':build_summary(build),'ordinary_checks':checks,'reference_integrity':integrity,'actual_fixture_count':len(data['fixtures']),'actual_step_count':sum(len(f['observations'])for f in data['fixtures']),'case_categories':dict(collections.Counter(r['category']for r in rows)),'expected_cases_sha256':sha(canonical(rows)),'native':[first,second],'limits':'No damage/health/callback implementation or body mutation. Actual large damaging landing fails at missing gameRenderer service; source deliberately rejects before publishing history. Actual float-overflow diagnostics are excluded with original-state return. Reset hits and water/flight/passenger/climb/effect/unsupported world/nonlocal authority remain explicit unsupported contexts. Movement consumes authoritative resolved/gate/onGround/clip inputs; it does not derive these from support or simulate collision.','reproduce':['PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_fall_history_probe.py --extract','PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_fall_history_probe.py --rerun','PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_fall_history.py','PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_fall_history.py --kernel']};write_json(NATIVE,evidence);print(json.dumps({'status':evidence['status'],'case_count':len(rows),'native_seconds':[r['seconds']for r in [first,second]],'binary_sha256':build['binary_sha256'],'evidence':fingerprint(NATIVE)}))
if __name__=='__main__':main()
