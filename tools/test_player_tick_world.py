#!/usr/bin/env python3
"""Owned finite-world ticks versus fresh untouched Player.aiStep observations."""
from __future__ import annotations
import argparse, copy, hashlib, json, os, pathlib, re, struct
from reference_inventory import ROOT, JAVA, canonical, fingerprint
from reference_block_probe import verified_classpath
from reference_movement_probe import SOURCE as MOVE_SOURCE, DIRECT_SOURCE
from reference_travel_probe import SOURCE as TRAVEL_SOURCE, bits, fbits
from reference_player_tick_probe import SOURCE as TICK_SOURCE
from test_geometry import run, sha
from test_player_tick import request as tick_request, parse as tick_parse
from test_travel import parse as body_parse, values
from test_travel_world import world_blocks, colliders, lines_by_kind
from test_client_world import run as run_with_env

BEND=pathlib.Path.home()/'.bend/bin/bend';BINARY=ROOT/'build/player-tick-world-tests';TABLE=ROOT/'generated/reference_mth_sin.f32'
DEPENDENCIES=['src/player_tick.bend','src/travel_world.bend','src/travel.bend','src/locomotion.bend','src/movement.bend','src/client_world.bend','src/f64.bend','src/core.bend','src/game.bend','src/registry.bend','src/client_render.bend','tests/player_tick.bend','tests/travel_world.bend','tests/travel.bend','tests/locomotion.bend','tests/client_world.bend']

def inputs():
    cases=[]
    def add(label,ticks,**changes):
        v={'position':list(map(bits,[.5,1.,-2.5])),'velocity':[bits(0.)]*3,'grounded':True,'input_f32_bits':[fbits(0.),fbits(0.),fbits(1.)],'jumping':True,'sprinting':False,'no_gravity':False,'discard_friction':False,'yaw_f32_bits':fbits(0.),'movement_speed':bits(.1),'gravity':bits(.08),'friction_modifier':bits(1.),'air_drag_modifier':bits(1.),'step_height':bits(.6),'jump_strength':bits(.42),'jump_delay':0,'jump_trigger':3,'needs_sync':False,'stored_speed_f32_bits':fbits(.7),'head_yaw_f32_bits':fbits(-90.),'world_blocks':world_blocks(),'ticks':ticks}
        v.update(changes);cases.append({'id':'tick-world-'+label,'operation':'player_ai_step','input':v})
    add('held-jump',[{'input_f32_bits':[fbits(0.),fbits(0.),fbits(1.)],'jumping':True} for _ in range(24)])
    add('decay-release-sprint',[{'jumping':False},{},{},{'jumping':True,'sprinting':True},{},{'jumping':False},{},{'input_f32_bits':[fbits(.5),fbits(.25),fbits(-.25)],'sprinting':False},{},{'jumping':True},{},{'jumping':False}],position=list(map(bits,[-1.5,1.,-.5])),input_f32_bits=[fbits(.5),fbits(.25),fbits(.5)],jumping=False,yaw_f32_bits=fbits(45.))
    add('dirt-step',[{} for _ in range(6)],position=list(map(bits,[.5,1.,1.5])),velocity=list(map(bits,[.8,-.1,0.])),input_f32_bits=[fbits(0.)]*3,jumping=False,step_height=bits(1.))
    width=struct.unpack('>f',bytes.fromhex('3f19999a'))[0]
    add('fully-blocked',[{} for _ in range(6)],position=list(map(bits,[1.-width/2,1.,1.5])),velocity=list(map(bits,[.8,0.,0.])),input_f32_bits=[fbits(0.)]*3,jumping=False,step_height=bits(0.))
    add('negative-counters',[{}, {'jumping':False}, {'jumping':True}, {}],position=list(map(bits,[.5,1.,.5])),input_f32_bits=[fbits(0.)]*3,jump_delay=-1,jump_trigger=-2)
    assert sum(len(c['input']['ticks']) for c in cases)==52
    return cases

def observe(cases):
    jars,release=verified_classpath();work=ROOT/'build/player-tick-world-oracle';work.mkdir(parents=True,exist_ok=True)
    sources=[]
    for name,source in [('ReferenceMovementProbe',MOVE_SOURCE),('ReferenceDirectMovementProbe',DIRECT_SOURCE),('ReferenceTravelProbe',TRAVEL_SOURCE),('ReferencePlayerTickProbe',TICK_SOURCE)]:
        p=work/(name+'.java');p.write_text(source);sources.append(p)
    cp=os.pathsep.join(map(str,jars));build=run([JAVA.parent/'javac','-cp',cp,'-d',work,*sources])
    incoming=work/'input.jsonl';outgoing=work/'output.jsonl';incoming.write_text(''.join(canonical(c).decode()+'\n' for c in cases))
    execution=run([JAVA,'-cp',str(work)+os.pathsep+cp,'ReferencePlayerTickProbe',incoming,outgoing]);observed=list(map(json.loads,outgoing.read_text().splitlines()))
    assert [c['id'] for c in observed]==[c['id'] for c in cases]
    result=[{**c,**o} for c,o in zip(cases,observed,strict=True)]
    direct=[]
    for c in result:
        assert len(c['ticks'])==len(c['input']['ticks'])
        for i,t in enumerate(c['ticks']):
            o=t['observation'];assert o['full_player_ai_step_executed']
            pre=o['pre_travel'];direct.append({'id':c['id']+':'+str(i),'operation':'entity_move','input':{'entity_type':'minecraft:player','position':pre['position'],'velocity':o['requested'],'requested':o['requested'],'grounded':pre['flags'][0],'maximum_f32_bits':o['attributes']['maximum_f32_bits'],'world_blocks':c['input']['world_blocks']}})
    direct_in=work/'movement-input.jsonl';direct_out=work/'movement-output.jsonl';direct_in.write_text(''.join(canonical(c).decode()+'\n' for c in direct))
    direct_execution=run([JAVA,'-cp',str(work)+os.pathsep+cp,'ReferenceMovementProbe',direct_in,direct_out]);direct_observed=list(map(json.loads,direct_out.read_text().splitlines()))
    k=0
    for c in result:
        for i,t in enumerate(c['ticks']):
            d=direct_observed[k];k+=1;o=t['observation'];assert d['id']==c['id']+':'+str(i)
            post=o['post_move_body'];e=d['expected'];di=d['observation']['actual_input']
            assert {key:post[key] for key in ['position','box','velocity']}=={key:e[key] for key in ['position','box','velocity']}
            assert post['flags']==e['flags'][:4]
            assert o['initial_shapes']==di['initial'] and o['step_shapes']==di['step']
            assert o['pre_travel']['position']==di['position'] and o['pre_travel']['box']==di['box']
            t['movement_expected']=e
    provenance={'build':build,'execution':execution,'input_sha256':sha(incoming),'output_sha256':sha(outgoing),'movement_execution':direct_execution,'movement_input_sha256':sha(direct_in),'movement_output_sha256':sha(direct_out),'java_sources_sha256':hashlib.sha256((MOVE_SOURCE+DIRECT_SOURCE+TRAVEL_SOURCE+TICK_SOURCE).encode()).hexdigest(),'pinned_classpath':[fingerprint(p) for p in jars],'runtime':fingerprint(JAVA),'release':release}
    return result,provenance

def request(c,i,op):return tick_request(c,c['ticks'][i],i,op).split(';')[0]
def state(lines,id,kind='state'):return tick_parse(lines[id,kind].replace('|transition-state|','|state|',1))[1]
def body(lines,id):return body_parse(lines[id,'body'])[1]
def unchanged(lines,id,rollback=False):
    for kind in ['clock','view']:assert lines[id+'-before',kind].split('|')[2:]==lines[id+'-after',kind].split('|')[2:],(id,kind)
    if rollback:
        assert body(lines,id+'-before')==body(lines,id+'-after'),id
        assert state(lines,id+'-before')==state(lines,id),id

def validate_tick(lines,c,i):
    id=c['id']+':'+str(i);t=c['ticks'][i];o=t['observation'];e=t['expected'];m=t['movement_expected'];unchanged(lines,id)
    assert state(lines,id)==state(lines,id,'transition-state')==e,(id,e,state(lines,id))
    assert body(lines,id+'-after')=={k:e[k] for k in ['position','box','velocity','width_f32_bits','height_f32_bits','flags']},id
    assert state(lines,id+'-before')==o['initial'],id
    assert tick_parse(lines[id,'prepared'])[1]=={'state':o['pre_travel'],'travel_input':o['travel_input']},id
    assert values(lines[id,'accelerated'].split('|')[2:])==o['requested'],id
    _,_,initial,step=lines[id,'colliders'].split('|');assert colliders(initial)==o['initial_shapes'] and colliders(step)==o['step_shapes'],id
    transition=lines[id,'transition'].split('|');assert len(transition)==10
    assert values(transition[2:8])==m['displacement'] and bool(int(transition[8]))==m['stepped'] and bool(int(transition[9]))==m['flags'][4],id
    attempted=o['observer_calls'].get('jumpFromGround_observer',0)>0
    jumped=attempted and int(o['jump_power_f32_bits'],16)>int(fbits(1e-5),16)
    assert list(map(lambda x:bool(int(x)),lines[id,'jumps'].split('|')[2:]))==[attempted,jumped],id


def validate_cases(cases):
    batches=[]
    for c in cases:
        args=[request(c,i,'start' if i==0 else 'chain') for i in range(len(c['ticks']))]
        r=run([BINARY,'--gpu','off',TABLE,*args]);lines=lines_by_kind(r['stdout'])
        for i in range(len(c['ticks'])):validate_tick(lines,c,i)
        batches.append({'case':c['id'],'ticks':len(c['ticks']),'seconds':r['seconds']})
    return batches

def rejection_cases(base):
    cases=[]
    def add(label,op,change,error):
        c=copy.deepcopy(base);c['id']='reject-'+label;change(c);cases.append((c,op,error))
    for mode in range(1,8):add('mode-'+str(mode),'reject',lambda c,mode=mode:c['input'].__setitem__('tick_mode',mode),'prepare|mode|'+str(mode))
    add('travel-mode','reject',lambda c:c['input'].__setitem__('travel_mode',1),'prepare|travel|mode|1')
    add('invalid-jump','reject',lambda c:c['ticks'][1]['observation']['attributes'].__setitem__('jump_factor_f32_bits','40000000'),'prepare|jump|1')
    add('body-mismatch','mismatch',lambda c:None,'body-mismatch')
    add('finish-injection','finish-injection',lambda c:None,'finish|mode|6')
    return cases

def validate_rejections(base,zero_base,support_base):
    rejected=[]
    for c,op,error in rejection_cases(base):
        recover=copy.deepcopy(base);recover['id']=c['id']+'-recovered'
        args=[request(base,0,'start'),request(c,1,op),request(recover,1,'chain')]
        r=run([BINARY,'--gpu','off',TABLE,*args]);lines=lines_by_kind(r['stdout']);id=c['id']+':1';unchanged(lines,id,rollback=True)
        assert lines[id,'error'].split('|',2)[2].startswith(error),(id,error,lines[id,'error'])
        # Mismatch leaves world authority untouched; aligning restores equality
        # explicitly before the next tick. All other rejections resume directly.
        if op=='mismatch':
            args[-1]=request(recover,1,'align');r=run([BINARY,'--gpu','off',TABLE,*args]);lines=lines_by_kind(r['stdout'])
        validate_tick(lines,recover,1);rejected.append({'case':id,'error':lines[id,'error'].split('|',2)[2],'recovered':True})
    # Raw signed-zero mismatch, even though both velocities compare numerically equal.
    c=copy.deepcopy(zero_base);c['id']='reject-zero-mismatch';recovery=copy.deepcopy(zero_base);recovery['id']='zero-recovered'
    r=run([BINARY,'--gpu','off',TABLE,request(zero_base,0,'start'),request(c,1,'zero-mismatch'),request(recovery,1,'align')]);lines=lines_by_kind(r['stdout']);id=c['id']+':1';unchanged(lines,id,rollback=True);assert lines[id,'error'].endswith('|body-mismatch');validate_tick(lines,recovery,1);rejected.append({'case':id,'error':'body-mismatch','recovered':True,'signed_zero':True})
    for label,op,repair,error in [('missing','missing','fixture-recovery','travel|world|missing-section:'),('unsupported','unsupported','repair-air','travel|world|unsupported-block-state:')]:
        selected=support_base if op=='unsupported' else base
        index=2 if op=='unsupported' else 0
        c=copy.deepcopy(selected);c['id']='reject-'+label;recovery=copy.deepcopy(selected);recovery['id']=label+'-recovered'
        r=run([BINARY,'--gpu','off',TABLE,request(c,index,op),request(recovery,index,repair)]);lines=lines_by_kind(r['stdout']);id=c['id']+':'+str(index);unchanged(lines,id,rollback=True);assert lines[id,'error'].split('|',2)[2].startswith(error);validate_tick(lines,recovery,index);rejected.append({'case':id,'error':lines[id,'error'].split('|',2)[2],'recovered':True,'repair_outside_operator':True})
    return rejected

def main():
    p=argparse.ArgumentParser();p.add_argument('--skip-build',action='store_true');args=p.parse_args()
    generations={p:sha(ROOT/p) for p in ['src/player_tick_world.bend','tests/player_tick_world.bend',*DEPENDENCIES]}
    checks=[run([BEND,p,'--check-only']) for p in ['src/player_tick_world.bend','tests/player_tick_world.bend']]
    if args.skip_build:
        path=ROOT/'evidence/player-tick-world-verification.json'
        prior=json.loads(path.read_text() if path.exists() else (ROOT/'build/player-tick-world-build.json').read_text())
        assert prior['binary_sha256']==sha(BINARY) and all(prior['sources_sha256'][p]==h for p,h in generations.items())
        builds=prior['builds']
    else:
        builds=[run([BEND,'tests/player_tick_world.bend','-o',BINARY],timeout=1800)]
        (ROOT/'build/player-tick-world-build.json').write_text(json.dumps({'binary_sha256':sha(BINARY),'sources_sha256':generations,'builds':builds},indent=2)+'\n')
    cases,provenance=observe(inputs());native=validate_cases(cases);rejected=validate_rejections(cases[0],cases[3],cases[4])
    running=copy.deepcopy(cases[0]);running['id']='running';r=run([BINARY,'--gpu','off',TABLE,request(running,0,'running-start')]);lines=lines_by_kind(r['stdout']);validate_tick(lines,running,0);assert lines['running:0-before','clock'].split('|')[4]=='0'
    custom=ROOT/'build/player-tick-world-oracle/palette.tsv';names=['minecraft:oak_planks','minecraft:stone','minecraft:air','minecraft:dirt'];custom.write_text('block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json\n'+''.join(f'{i}\t{name}\t{i}\t1\t{i}\t[]\n' for i,name in enumerate(names)))
    env=os.environ.copy();env['MC_BLOCK_REGISTRY']=str(custom);remap=copy.deepcopy(cases[0]);remap['id']='remapped';r=run_with_env([BINARY,'--gpu','off',TABLE,request(remap,0,'start')],env=env);lines=lines_by_kind(r['stdout']);validate_tick(lines,remap,0);assert lines['remapped:0-before','view'].split('|')[4]=='2,1,3,0'
    for p,h in generations.items():assert sha(ROOT/p)==h,('dependency generation changed',p)
    source=(ROOT/'src/player_tick_world.bend').read_text();assert not re.search(r'@unsafe|\bimport\s+["\']|\w!\(',source)
    ticks=[t for c in cases for t in c['ticks']];sources=[*generations,'tools/test_player_tick_world.py','docs/PLAYER_TICK_WORLD.md','tools/reference_player_tick_probe.py','tools/reference_travel_probe.py','tools/reference_movement_probe.py']
    e={'schema_version':1,'status':'passed','pin':'26.3','actual_player_ai_step_calls':len(ticks),'chained_native_ticks':len(ticks),'carried_native_ticks':len(ticks)-len(cases),'pre_travel_comparisons':len(ticks),'requested_vectors_compared':len(ticks),'actual_entity_move_supplemental_cases':len(ticks),'ordered_collision_lists_compared':len(ticks)*2,'final_player_states_compared':len(ticks),'final_world_bodies_compared':len(ticks),'fixture_blocks':39,'checked_fixture_mutations':47,'rejections':rejected,'successful_same_owner_recovery_cases':len(rejected),'dynamic_registry_remap':True,'clock_and_view_unchanged':True,'running_clock_unchanged':True,'checks':checks,'builds':builds,'native_sequences':native,'direct_java_provenance':provenance,'sources_sha256':{p:sha(ROOT/p) for p in sources if (ROOT/p).exists()},'binary_sha256':sha(BINARY),'table':fingerprint(TABLE),'stable_dependency_generation':True,'laws':re.findall(r'^law (\w+):',source,re.M),'whole_module_kernel_verified':False,'confidence':'high for the observed finite neutral Player.aiStep projection; complete player/server ticks remain incomplete','verified_build_reused':args.skip_build,'scope':['sole owned World and sine Tables retained','raw-equal single body authority before preparation','caller-supplied supporting-aware friction/jump sample and resolved attributes','all Player metadata and original view/cache restored on rejection','operator reads existing checked sections only; clocks and queues untouched'],'unsupported':['automatic supporting-block/friction/jump/attribute resolution','complete Player.tick and ServerPlayer tick','nonneutral blocks/effects/actors/fluid/flight/glide/climb/equipment','complete Minecraft client']}
    e.update(actual_step_outcomes=sum(t['movement_expected']['stepped'] for t in ticks),position_application_gate_rejections=sum(not t['movement_expected']['flags'][4] for t in ticks),jump_attempts=sum(t['observation']['observer_calls'].get('jumpFromGround_observer',0)>0 for t in ticks),nonempty_initial_collision_lists=sum(bool(t['observation']['initial_shapes']) for t in ticks),nonempty_step_collision_lists=sum(bool(t['observation']['step_shapes']) for t in ticks),remapped_registry_sha256=sha(custom))
    assert e['actual_step_outcomes']>0 and e['position_application_gate_rejections']>0 and e['jump_attempts']>1
    (ROOT/'evidence/player-tick-world-verification.json').write_text(json.dumps(e,indent=2,sort_keys=True)+'\n');print(json.dumps({k:e[k] for k in ['status','actual_player_ai_step_calls','ordered_collision_lists_compared','successful_same_owner_recovery_cases','actual_step_outcomes','jump_attempts','confidence']},indent=2))
if __name__=='__main__':main()
