#!/usr/bin/env python3
"""Independent pinned local-phase observations; no Bend gameplay implementation.

The unchanged tick-phase receiver services remain explicit fixture boundaries.
All raw writes are confined to this task's ignored directory. Extra getters at
declared boundaries are labelled observations, never replacement algorithms.
"""
from __future__ import annotations
import argparse, copy, hashlib, json
from pathlib import Path
import reference_player_tick_phases_probe as PH
import reference_local_input_probe as LI
from reference_inventory import ROOT, canonical, fingerprint, write_json
from reference_model_probe import CLIENT

RAW = ROOT / 'build/local-phase-runtime/reference'
REFERENCE = ROOT / 'reference/local_phase_runtime.json'
EVIDENCE = ROOT / 'evidence/local-phase-runtime-reference.json'

def sha(value):
    return hashlib.sha256(canonical(value)).hexdigest()

def pin(path):
    return {'path': str(path.relative_to(ROOT)), **fingerprint(path)}

EXTRA = r'''
 static boolean suppressFitObservation;
 static Map<String,Object> controlFacts(LocalPlayer p){
  return Map.of("food",p.getFoodData().getFoodLevel(),"mayfly",p.getAbilities().mayfly,
    "flying",p.getAbilities().flying,"mobility_restricted",p.isMobilityRestricted());
 }
 static Map<String,Object> phaseFacts(LocalPlayer p)throws Exception{
  Map<String,Object> m=new TreeMap<>();
  m.put("food",p.getFoodData().getFoodLevel());m.put("mayfly",p.getAbilities().mayfly);m.put("flying",p.getAbilities().flying);
  m.put("mobility_restricted",p.isMobilityRestricted());
  BlockPos ground=(BlockPos)invokeInherited(p,"getBlockPosBelowThatAffectsMyMovement",new Class<?>[]{});
  BlockState block=p.level().getBlockState(ground);
  m.put("ground_sample",Map.of("position",List.of(ground.getX(),ground.getY(),ground.getZ()),"block_id",BuiltInRegistries.BLOCK.getKey(block.getBlock()).toString(),"friction_f32_bits",bits(block.getBlock().getFriction())));
  m.put("jump_factor_f32_bits",bits((float)invokeInherited(p,"getBlockJumpFactor",new Class<?>[]{})));
  return m;
 }
'''

FIT = r'''
  protected boolean canPlayerFitWithinBlocksAndEntitiesWhen(Pose requested){
   boolean clear=super.canPlayerFitWithinBlocksAndEntitiesWhen(requested);
   if(phaseRecording&&!suppressFitObservation){AABB b=getDimensions(requested).makeBoundingBox(position()).deflate(1.0E-7);
    phase("fit",Map.of("pose",requested.name(),"box",List.of(bits(b.minX),bits(b.minY),bits(b.minZ),bits(b.maxX),bits(b.maxY),bits(b.maxZ)),"clear",clear));}
   return clear;
  }
'''

def sources(values):
    result = PH.sources(values)
    source = result[PH.FIXTURE]
    needle = ' static Map<String,Object> phaseState(LocalPlayer p)throws Exception{'
    assert source.count(needle) == 1
    source = source.replace(needle, EXTRA + needle)
    needle = 'm.put("body_head_rotation_f32_bits",'
    assert source.count(needle) == 1
    extra = '''m.put("position_old",List.of(bits((double)read(p,"xOld")),bits((double)read(p,"yOld")),bits((double)read(p,"zOld"))));
  m.put("invulnerable_time_u32",Integer.toUnsignedLong((int)read(p,"invulnerableTime")));
  for(String k:List.of("move_vector_f32_bits","needs_sync","stored_speed_f32_bits","head_yaw_f32_bits","jump_trigger","gravity","friction_modifier","air_drag_modifier","jump_strength","maximum_f32_bits","sneaking_speed"))m.put(k,all.get(k));
  '''
    source = source.replace(needle, extra + needle)
    needle = '  boolean phaseRecording;'
    assert source.count(needle) == 1
    source = source.replace(needle, needle + FIT)
    # The inherited LI observer deliberately invokes fits(this) for observation.
    # Suppress only those extra calls so recorded fit order is actual gameplay.
    needle = 'static Map<String,Object> fits(LocalPlayer p){try{'
    assert source.count(needle) == 1
    source = source.replace(needle, 'static Map<String,Object> fits(LocalPlayer p){suppressFitObservation=true;try{')
    needle = '"crouching",method.invoke(p,Pose.CROUCHING));}catch(Exception e){throw new RuntimeException(e);}}'
    assert source.count(needle) == 1
    source = source.replace(needle, '"crouching",method.invoke(p,Pose.CROUCHING));}catch(Exception e){throw new RuntimeException(e);}finally{suppressFitObservation=false;}}')
    # At the real applyInput/travel entry the ordered setters have completed.
    # Read source facts in that exact receiver state; those reads are conditional
    # provenance, not owned attribute-modifier or ground-resolution machinery.
    needle = 'phase("travel_entry");'
    assert source.count(needle) == 1
    source = source.replace(needle, 'try{phase("travel_entry",Map.of("conditional_facts",phaseFacts(this)));}catch(Exception e){throw new RuntimeException(e);}')
    needle = 'phase("ai_step_entry");'
    assert source.count(needle) == 1
    source = source.replace(needle, 'phase("ai_step_entry",Map.of("conditional_control_facts",controlFacts(this)));')
    result[PH.FIXTURE] = source
    return result

def decode(case):
    result = copy.deepcopy(case)
    for step in result['steps']:
        previous = copy.deepcopy(step['before'])
        for phase in step['phases']:
            if 'state' in phase:
                previous = copy.deepcopy(phase['state'])
            else:
                previous.update(phase.get('state_changes', {}))
            phase['state'] = copy.deepcopy(previous)
    return result

def integrity(data, enrich=False):
    assert data['pin'] == '26.3' and data['ray_domain'] == 'CheckedNotRequired'
    assert sha(data['cases']) == data['cases_sha256']
    baseline = json.loads((ROOT / 'reference/player_tick_phases.json').read_text())
    assert len(data['cases']) == len(baseline['cases']) == 7
    summaries = []
    for supplied, prior in zip(data['cases'], baseline['cases'], strict=True):
        current = supplied if enrich else decode(supplied)
        prior = decode(prior)
        assert current['id'] == prior['id']
        for index, (a, b) in enumerate(zip(current['steps'], prior['steps'], strict=True)):
            assert a['ok'] == b['ok']
            for key in ('before', 'after'):
                assert {k:a[key][k] for k in b[key]} == b[key], (current['id'], index, key)
            old_shift = a['before']['key_presses'][5]
            names = [p['phase'] for p in a['phases']]
            if a['ok']:
                first = names.index('keyboard_entry')
                early = [p['details'] for p in a['phases'][:first] if p['phase']=='fit']
                assert [p['pose'] for p in early] == (['CROUCHING'] if old_shift else ['CROUCHING','STANDING'])
                late = [p['details'] for p in a['phases'][names.index('pose_update_entry'):] if p['phase']=='fit']
                assert [p['pose'] for p in late] == ['SWIMMING',a['after']['pose']]
                facts = next(p['details']['conditional_facts'] for p in a['phases'] if p['phase']=='travel_entry')
                control = next(p['details']['conditional_control_facts'] for p in a['phases'] if p['phase']=='ai_step_entry')
                assert control == {k:facts[k] for k in control},(current['id'],index,'fixture facts remain neutral between declared boundaries')
                a['projection'] = {'early_fits':early,'late_fits':late,'apply_facts':facts,
                    'control_facts':control,
                    'sprint_updates':([c['argument'] for c in a['local_input_observers'] if c['method']=='setSprinting']
                        if 'local_input_observers' in a else a['projection']['sprint_updates']),
                    'reference_entry':current['operation'],'admitted':True}
            else:
                assert current['id']=='scheduled_sprint_jump' and index==1
                assert a['error_class']==b['error_class']=='java.lang.NoSuchFieldError'
                assert 'gameRenderer' in a['error_message']
                a['projection'] = {'admitted':False,'exclusion':'unchanged sprint-particle fixture service gap'}
            summaries.append({'id':current['id'],'step':index,'ok':a['ok'],
                'early_fit_count':len(a['projection'].get('early_fits',[])),
                'late_fit_count':len(a['projection'].get('late_fits',[]))})
    return summaries

def extract():
    original_sources, original_raw = PH.sources, PH.RAW
    original = PH.sources
    def derived(values):
        # sources() must call the original producer, avoiding recursive wrapping.
        PH.sources = original
        try:
            return sources(values)
        finally:
            PH.sources = derived
    PH.sources, PH.RAW = derived, RAW
    before = {p:pin(ROOT/p) for p in ['tools/reference_local_phase_runtime_probe.py','tools/reference_player_tick_phases_probe.py','tools/reference_local_input_probe.py']}
    client = fingerprint(CLIENT)
    values = PH.phase_inputs()
    try:
        first, second = PH.observe(values,'first'), PH.observe(values,'rerun')
    finally:
        PH.sources, PH.RAW = original_sources, original_raw
    assert first['cases'] == second['cases']
    assert first['loaded_official_class_tree_sha256'] == second['loaded_official_class_tree_sha256']
    assert before == {p:pin(ROOT/p) for p in before} and client == fingerprint(CLIENT)
    data = {'schema_version':1,'pin':'26.3','kind':'actual paired local tick phase observations',
        'ray_domain':'CheckedNotRequired','inputs':values,'cases':first['cases'],
        'cases_sha256':sha(first['cases']),'raw_artifacts':[first['raw_artifact'],second['raw_artifact']]}
    # integrity enriches explicit source-fact rows, then seal the final payload.
    summaries = integrity(data, enrich=True)
    data['cases_full_sha256'] = sha(data['cases'])
    compact = copy.deepcopy(data['cases'])
    for case in compact:
        for step in case['steps']:
            previous = step['before']
            for phase in step['phases']:
                current = phase.pop('state')
                assert current.keys() == previous.keys()
                phase['state_changes'] = {k:v for k,v in current.items() if v != previous[k]}
                previous = current
            step['local_input_observer_methods'] = [c['method'] for c in step.pop('local_input_observers')]
    for full, packed in zip(data['cases'],compact,strict=True):
        decoded=decode(packed)
        for a,b in zip(full['steps'],decoded['steps'],strict=True):
            assert [p['state'] for p in a['phases']] == [p['state'] for p in b['phases']]
    data['cases'] = compact
    data['snapshot_encoding'] = 'Each step starts at before; apply ordered phase.state_changes. Full LI observer records stay in pinned ignored raw artifacts.'
    data['cases_sha256'] = sha(data['cases'])
    write_json(REFERENCE,data)
    receipt = {k:v for k,v in first.items() if k not in ('cases','inputs')}
    receipt.update(status='observed-no-Bend-native-verdict',pin='26.3',producers=before,client=client,
        exact_rerun_equal=True,plain_super_observer_parity=True,reference=pin(REFERENCE),
        independent_rerun={k:v for k,v in second.items() if k not in ('cases','inputs')},steps=summaries,
        early_order='CROUCHING; STANDING only if crouching fits and prior sampled shift is false',
        scope='Bounded existing seven histories; conditional getters at actual travel entry; unchanged four external services, normal constructed real receivers, actual world queries; full tick sprint-particle service failure remains excluded.')
    write_json(EVIDENCE,receipt)
    print(json.dumps({'status':receipt['status'],'steps':len(summaries),'successful':sum(s['ok'] for s in summaries),'reference':str(REFERENCE)},indent=2))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--extract',action='store_true')
    args=parser.parse_args()
    if args.extract:
        extract()
    else:
        data=json.loads(REFERENCE.read_text()); summaries=integrity(data)
        print(json.dumps({'status':'integrity-passed','steps':len(summaries)},indent=2))

if __name__=='__main__':
    main()
