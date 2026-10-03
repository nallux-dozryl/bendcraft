#!/usr/bin/env python3
"""Actual Java camera phases vs pure owned Bend; host code only orchestrates."""
from __future__ import annotations
import argparse, collections, hashlib, json, os, signal, subprocess, sys, time
from pathlib import Path
import reference_player_rotation_tick_probe as P
from reference_inventory import ROOT, canonical, fingerprint, write_json
from build_native import ensure_native

BEND=Path('/Users/chuah/.bend/bin/bend')
SOURCE=ROOT/'src/player_rotation_tick.bend'
HARNESS=ROOT/'tests/player_rotation_tick.bend'
BINARY=ROOT/'build/player-rotation-tick-tests'
RECEIPT=ROOT/'build/player-rotation-tick-build.json'
NATIVE=ROOT/'evidence/player-rotation-tick-native.json'
KERNEL=ROOT/'evidence/player-rotation-tick-kernel.json'

def sha(b):return hashlib.sha256(b).hexdigest()
def run(command,timeout=600,allow_failure=False):
    start=time.monotonic();p=subprocess.Popen(list(map(str,command)),cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
    try:stdout,stderr=p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid,signal.SIGKILL);stdout,stderr=p.communicate();return {'command':list(map(str,command)),'status':'timeout','exit_code':None,'seconds':round(time.monotonic()-start,6),'stdout':stdout,'stderr':stderr}
    result={'command':list(map(str,command)),'status':'passed'if p.returncode==0 else'failed','exit_code':p.returncode,'seconds':round(time.monotonic()-start,6),'stdout':stdout,'stderr':stderr}
    if p.returncode and not allow_failure:raise AssertionError(result)
    return result

def verify_build(record):
    for d in record['dependencies']:
        path=Path(d['lookup']);assert str(path.resolve())==d['path'] and path.is_file() and path.stat().st_size==d['bytes'] and sha(path.read_bytes())==d['sha256'],'Native dependency changed: '+str(path)
    path=Path(record['artifact']);assert fingerprint(path)['sha256']==record['binary_sha256'] and path.stat().st_size==record['binary_bytes'],'Native executable changed'
    return path

def report(camera):return {'ok':True,'state':[int(x,16)for x in camera['rotation_f32_bits']],'count':camera['tick_count_u32']}
def before(f):return {'rotation_f32_bits':f['rotation_f32_bits'],'tick_count_u32':f['tick_count_u32']}
def args(op,fuel,c):return [op,fuel,*[int(x,16)for x in c['rotation_f32_bits']],c['tick_count_u32']]
def rejected(c,error):return {'ok':False,'state':[int(x,16)for x in c['rotation_f32_bits']],'count':c['tick_count_u32'],'error':error}

def cases(data):
    rows=[]
    def add(name,op,fuel,c,expected,category):rows.append({'id':name,'args':args(op,fuel,c),'expected':expected,'category':category})
    for f in data['fixtures']:
        op=f['operation'];initial=before(f)
        if op in ['set_old_rot','common_tick']:add(f['id'],0 if op=='set_old_rot'else 1,0,initial,report(f['expected']),'actual_'+op)
        elif op=='ai_step':
            assert f['expected']==initial,'Neutral aiStep changes camera; no identity claim permitted'
            add(f['id'],3,0,initial,report(f['expected']),'actual_ai_step_baseline_only')
        elif op in ['tick','common_tick_then_tick','level_tick','huge_equal_tick']:
            after=f['after_ai_step'];expected=report(f['expected'])
            add(f['id']+'/post_ai_step',2,16384,after,expected,'actual_post_ai_step')
            changed=[i for i in [2,3]if after['rotation_f32_bits'][i]!=f['expected']['rotation_f32_bits'][i]]
            zero=rejected(after,{'kind':'FuelExhausted','axis':changed[0]-2})if changed else expected
            add(f['id']+'/zero_fuel',2,0,after,zero,'bounded_zero_fuel')
            if op in ['common_tick_then_tick','level_tick']:
                assert f['before_ai_step']==f['after_ai_step'],'Full neutral tick aiStep changed camera'
                if op=='common_tick_then_tick':assert f['after_common']==f['before_ai_step']
                add(f['id']+'/actual_common',1,0,initial,report(f['before_ai_step']),'actual_common_before_tick')
                add(f['id']+'/both_phases',5,16384,initial,{'snapshot_status':{'ok':True},'normalized':expected},'actual_common_then_normalize')
        elif op=='float_step':
            # Reference values are produced by Java float operators, not a
            # production Minecraft full tick. Conversion changes only encoding.
            numeric={axis:{k:int(v,16) if isinstance(v,str) else v for k,v in measured.items()}
                     for axis,measured in f['numeric'].items()}
            add(f['id']+'/java_numeric',6,0,initial,numeric,'standalone_java_f32_operators')
            if all(not n['negative_needed'] and not n['positive_needed'] for n in numeric.values()):
                add(f['id']+'/no_loop',2,0,initial,report(initial),'huge_equal_zero_fuel')
            n=numeric['yaw'];previous=int(initial['rotation_f32_bits'][2],16)
            update='minus360' if n['negative_needed'] else 'plus360'
            if (n['negative_needed'] or n['positive_needed']) and n[update]==previous:
                for fuel in [0,1,16384]:
                    failed=rejected(initial,{'kind':'FuelExhausted','axis':0})
                    add(f['id']+'/no_progress:'+str(fuel),2,fuel,initial,failed,'huge_no_progress_rollback')
                    recovered={'ok':True,'state':[int(x,16)for x in initial['rotation_f32_bits'][:2]]*2,
                               'count':(initial['tick_count_u32']+1)&0xffffffff}
                    add(f['id']+'/no_progress_recovery:'+str(fuel),4,fuel,initial,
                        {'first':failed,'recovered':recovered},'huge_owner_recovery')
                # The same measured no-progress pitch must fail after yaw
                # already requires no updates, retaining all huge finite fields.
                p=numeric['pitch'];old_pitch=int(initial['rotation_f32_bits'][3],16)
                pitch_update='minus360' if p['negative_needed'] else 'plus360'
                if (p['negative_needed'] or p['positive_needed']) and p[pitch_update]==old_pitch:
                    camera=dict(initial);camera['rotation_f32_bits']=list(initial['rotation_f32_bits'])
                    camera['rotation_f32_bits'][2]=camera['rotation_f32_bits'][0]
                    for fuel in [1,16384]:
                        add(f['id']+'/pitch_no_progress:'+str(fuel),2,fuel,camera,
                            rejected(camera,{'kind':'FuelExhausted','axis':1}),'huge_pitch_no_progress')
            chosen={axis:('minus360' if n['negative_needed'] else 'plus360')
                    for axis,n in numeric.items()}
            if all((n['negative_needed'] or n['positive_needed']) and
                   n['minus_finished' if n['negative_needed'] else 'plus_finished']
                   for n in numeric.values()):
                state=[int(x,16)for x in initial['rotation_f32_bits']]
                state[2]=numeric['yaw'][chosen['yaw']];state[3]=numeric['pitch'][chosen['pitch']]
                add(f['id']+'/two_numeric_steps',2,2,initial,
                    {'ok':True,'state':state,'count':initial['tick_count_u32']},'java_numeric_one_step_per_axis')
                add(f['id']+'/one_numeric_step_rollback',2,1,initial,
                    rejected(initial,{'kind':'FuelExhausted','axis':1}),'numeric_step_partial_rollback')
    # These errors/rollback checks are the bounded Bend policy, not Java rejection.
    valid={'rotation_f32_bits':['00000000','00000000','44340000','c4340000'],'tick_count_u32':4294967295}
    matched=next(f for f in data['fixtures']if f['operation']=='tick'and f['rotation_f32_bits']==valid['rotation_f32_bits'])
    valid['tick_count_u32']=matched['tick_count_u32']
    for fuel,axis in [(0,0),(1,0),(2,1),(3,1)]:
        failed=rejected(valid,{'kind':'FuelExhausted','axis':axis})
        add('shared_fuel:'+str(fuel),2,fuel,valid,failed,'shared_fuel_rollback')
        recovered={'ok':True,'state':[0,0,0,0],'count':(valid['tick_count_u32']+1)&0xffffffff}
        add('recovery:'+str(fuel),4,fuel,valid,{'first':failed,'recovered':recovered},'owned_recovery_after_error')
    add('shared_fuel:exact',2,4,valid,report(matched['expected']),'exact_shared_fuel')
    clean={'rotation_f32_bits':['41880000','c1300000','41400000','c1100000'],'tick_count_u32':4294967295}
    for fuel in [16385,4294967295,281474976710655]:add('fuel_limit:'+str(fuel),2,fuel,clean,rejected(clean,{'kind':'FuelLimit'}),'fuel_limit')
    for field in range(4):
        for value in [0x7f800000,0xff800000,0x7fc00000,0x7fa12345]:
            c={'rotation_f32_bits':list(clean['rotation_f32_bits']),'tick_count_u32':clean['tick_count_u32']};c['rotation_f32_bits'][field]=f'{value:08x}'
            error={'kind':'InvalidState','field':field};failed=rejected(c,error)
            for op in [0,1,2]:add(f'field:{field}:{value:08x}:{op}',op,16384,c,failed,'state_gate_retention')
            add(f'rejected_owner_recovery:{field}:{value:08x}',4,16384,c,{'first':failed,'recovered':failed},'invalid_owner_reusable')
    return rows

def native_run(binary,rows):
    results=[];seconds=0.;commands=[]
    for start in range(0,len(rows),24):
        group=rows[start:start+24];command=[binary,'--gpu','off','--threads','1','--',*[str(a)for r in group for a in r['args']]]
        r=run(command,timeout=180);assert r['status']=='passed',r
        actual=[json.loads(s)for s in r['stdout'].splitlines()if s.startswith('{')];assert len(actual)==len(group),(len(actual),len(group),r['stdout'][-500:])
        for expected,observed in zip(group,actual):assert expected['expected']==observed,(expected['id'],expected['expected'],observed)
        results+=actual;seconds+=r['seconds'];commands.append({'case_start':start,'case_count':len(group),'seconds':r['seconds'],'command_prefix':[str(binary),'--gpu','off','--threads','1','--'],'arguments_sha256':sha(canonical([r['args']for r in group]))})
    return {'status':'passed','case_count':len(rows),'observations_sha256':sha(canonical(results)),'seconds':round(seconds,6),'runs':commands}

def build_summary(build):
    kept = {k: build[k] for k in ['artifact', 'binary_bytes', 'binary_sha256',
            'cache_hit', 'cache_key', 'compiler', 'emitted_c_sha256', 'identity',
            'path', 'timings']}
    kept.update(full_receipt={'path': str(RECEIPT.relative_to(ROOT)), **fingerprint(RECEIPT)},
                dependency_count=len(build['dependencies']),
                dependencies_sha256=sha(canonical(build['dependencies'])),
                project_dependencies=[d for d in build['dependencies']
                    if d['path'].startswith(str(ROOT) + '/')])
    return kept


def compact_native(evidence):
    # Preserve the original execution receipt. Formatting adds no new execution.
    verify_build(evidence['build'])
    assert evidence['build'] == json.loads(RECEIPT.read_text()), 'Original build receipt differs'
    assert evidence['expected_cases_sha256'] == sha(canonical(cases(json.loads(P.OUTPUT.read_text())))), 'Actual expected cases changed'
    raw = ROOT / 'build/player-rotation-tick-native.full.json'
    write_json(raw, evidence)
    compact = dict(evidence)
    compact['schema'] = 'player-rotation-tick-native-summary-v1'
    compact['build'] = build_summary(evidence['build'])
    compact['runner_at_execution'] = compact.pop('runner')
    compact['report_formatter'] = fingerprint(Path(__file__))
    compact['full_execution_record'] = {'path': str(raw.relative_to(ROOT)), **fingerprint(raw)}
    write_json(NATIVE, compact)
    return compact


def compact_existing():
    current = json.loads(NATIVE.read_text())
    if 'full_execution_record' in current:
        receipt = current['full_execution_record']
        path = ROOT / receipt['path']
        assert receipt == {'path': receipt['path'], **fingerprint(path)}, 'Full execution record changed'
        current = json.loads(path.read_text())
    result = compact_native(current)
    print(json.dumps({'status': 'compacted_existing_execution', 'scope': 'Formatting/integrity only; no native or Java execution', 'evidence': fingerprint(NATIVE), 'full_execution_record': result['full_execution_record']}))


def main():
    p=argparse.ArgumentParser();p.add_argument('--compact-existing',action='store_true');p.add_argument('--prepare',action='store_true');p.add_argument('--build-only',action='store_true');p.add_argument('--skip-build',action='store_true');p.add_argument('--skip-checks',action='store_true');p.add_argument('--kernel',action='store_true');p.add_argument('--skip-reference-selftest',action='store_true');a=p.parse_args()
    if a.compact_existing:
        compact_existing();return
    if a.build_only:
        b=ensure_native(HARNESS,BINARY,bend=BEND);write_json(RECEIPT,b);print(json.dumps({'status':'built','artifact':b['artifact'],'binary_sha256':b['binary_sha256'],'cache_hit':b['cache_hit']}));return
    checks=[]
    if not a.skip_checks:
        for path in [SOURCE,HARNESS]:checks.append(run([BEND,path,'--check-only'],30));assert checks[-1]['status']=='passed',checks[-1]
    integrity=P.verify_existing(not a.skip_reference_selftest);data=json.loads(P.OUTPUT.read_text());rows=cases(data)
    if a.prepare:
        print(json.dumps({'status':'prepared','source':fingerprint(SOURCE),'harness':fingerprint(HARNESS),'actual_fixture_count':len(data['fixtures']),'native_case_count':len(rows),'case_categories':dict(collections.Counter(r['category']for r in rows)),'ordinary':checks,'reference_integrity':integrity},sort_keys=True));return
    if a.kernel:
        results=[]
        for path in [SOURCE,HARNESS]:results.append(run([BEND,path,'--verdict'],60,True))
        record={'status':'passed'if all(r['status']=='passed'for r in results)else'incomplete','scope':'Full imported production source and eleven stated helper laws; not universal Minecraft tick parity','source':fingerprint(SOURCE),'harness':fingerprint(HARNESS),'compiler':fingerprint(BEND),'attempts':results};record['project_bend_dependencies']=[d for d in json.loads(RECEIPT.read_text())['dependencies'] if d['kind']=='bend' and d['path'].startswith(str(ROOT)+'/')] if RECEIPT.is_file() else [];write_json(KERNEL,record);print(json.dumps({'kernel_status':record['status'],'attempts':[{'status':r['status'],'seconds':r['seconds']}for r in results]}));return
    if not a.skip_build:
        b=run([sys.executable,Path(__file__),'--build-only'],600);assert b['status']=='passed',b
    build=json.loads(RECEIPT.read_text());binary=verify_build(build)
    first=native_run(binary,rows);second=native_run(binary,rows);assert first['observations_sha256']==second['observations_sha256'],'Repeated native outputs differ';verify_build(build)
    evidence={'schema':1,'status':'passed_fuel_bounded_finite_camera_projection','pin':'26.3','scope':'All finite F32 camera fields; snapshots/count and fuel-bounded ordered post-aiStep previous-angle updates only. Actual Java commonTick/LocalPlayer.tick/ClientLevel.tickNonPassenger ran; separate huge numerical diagnostics invoke only Java F32 operators. No complete lifecycle implementation claim.','source':fingerprint(SOURCE),'harness':fingerprint(HARNESS),'runner':fingerprint(Path(__file__)),'probe':fingerprint(Path(P.__file__)),'reference':fingerprint(P.OUTPUT),'build':build,'ordinary_checks':checks,'reference_integrity':integrity,'actual_fixture_count':len(data['fixtures']),'actual_operation_counts':dict(collections.Counter(f['operation']for f in data['fixtures'])),'case_categories':dict(collections.Counter(r['category']for r in rows)),'expected_cases_sha256':sha(canonical(rows)),'native':[first,second],'policy':{'admitted_angles':'All finite F32 words; no magnitude restriction','shared_max_fuel':16384,'zero_fuel':'Allowed if no angle update is needed','failure':'Entire original owned state returned; no partial angle/count update'},'reproduce':['PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_rotation_tick_probe.py --extract','PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_rotation_tick_probe.py --rerun','PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_rotation_tick.py','PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_rotation_tick.py --kernel'],'limits':'No Entity position/interpolation/invulnerability, body/head angles, passengers, sleeping/vehicle/death states or runtime integration claim. Direct native identity checks for aiStep are baseline only. Full-tick huge unequal-angle probes are forbidden; no-progress/overflow cases use separately labeled Java numeric observations and Bend fuel-policy assertions.'}
    compact_native(evidence);print(json.dumps({'status':evidence['status'],'case_count':len(rows),'native_seconds':[r['seconds']for r in [first,second]],'binary_sha256':build['binary_sha256'],'evidence':fingerprint(NATIVE)}))
if __name__=='__main__':main()
