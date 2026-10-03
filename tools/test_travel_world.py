#!/usr/bin/env python3
"""Bounded owned-world travel against untouched pinned Player.travel."""
from __future__ import annotations
import argparse, copy, hashlib, json, os, pathlib, re, struct
from reference_inventory import ROOT, JAVA, canonical, fingerprint
from reference_block_probe import verified_classpath
from reference_movement_probe import SOURCE as MOVE_SOURCE, DIRECT_SOURCE
from reference_travel_probe import SOURCE as TRAVEL_SOURCE, bits, fbits
from test_geometry import run, sha
from test_travel import request as travel_request, parse as parse_travel, values
from test_client_world import scalars, movement, run as run_with_env

BEND=pathlib.Path.home()/'.bend/bin/bend';BINARY=ROOT/'build/travel-world-tests';TABLE=ROOT/'generated/reference_mth_sin.f32'
DEPENDENCIES=['src/travel.bend','src/locomotion.bend','src/movement.bend','src/client_world.bend','src/f64.bend','src/core.bend','src/game.bend','src/registry.bend','src/client_render.bend']

def world_blocks():
    return [{'position':[x,0,z],'identifier':'minecraft:dirt' if x==2 else 'minecraft:stone'} for z in range(-3,3) for x in range(-3,3)]+[{'position':[1,1,1],'identifier':'minecraft:dirt'},{'position':[2,1,2],'identifier':'minecraft:oak_planks'},{'position':[2,2,2],'identifier':'minecraft:oak_planks'}]

def inputs():
    cases=[]
    def add(label,**changes):
        v={'position':list(map(bits,[.5,1.,.5])),'velocity':list(map(bits,[0.,0.,0.])),'input':list(map(bits,[0.,0.,1.])),'grounded':True,'sprinting':False,'no_gravity':False,'discard_friction':False,'yaw_f32_bits':fbits(0.),'movement_speed':bits(.1),'gravity':bits(.08),'friction_modifier':bits(1.),'air_drag_modifier':bits(1.),'step_height':bits(.6),'world_blocks':world_blocks()}
        v.update(changes);cases.append({'id':'world-'+label,'operation':'player_travel','input':v})
    add('basic')
    for ground in [False,True]:
        for sprint in [False,True]:
            for modifier,drag in [(0.,0.),(1.,1.),(2.5,50.)]:
                add(f'attributes-{ground}-{sprint}-{modifier}',grounded=ground,sprinting=sprint,position=list(map(bits,[.5,1. if ground else 2.5,-.5])),velocity=list(map(bits,[.15,-.05,-.2])),input=list(map(bits,[1.,.25,1.])),yaw_f32_bits=fbits(45.),friction_modifier=bits(modifier),air_drag_modifier=bits(drag))
    for height in [0.,.6,1.,1.5]:
        add('dirt-step-'+str(height),position=list(map(bits,[.5,1.,1.5])),velocity=list(map(bits,[.8,-.1,0.])),input=list(map(bits,[0.,0.,0.])),step_height=bits(height))
        add('planks-step-'+str(height),position=list(map(bits,[1.5,1.,2.5])),velocity=list(map(bits,[.8,-.1,0.])),input=list(map(bits,[0.,0.,0.])),step_height=bits(height))
    for i,(position,velocity,yaw) in enumerate([([-.5,1.,-.5],[-.5,-.1,.2],-90.),([-.0,1.,-.0],[-0.,-0.,-0.],0.),([.5,1.,-2.5],[1e-7,-1e-7,0.],1e30),([.5,1.,.5],[0.,.5,0.],180.),([2.5,1.,-.5],[.2,-.05,.1],-1e30)]):
        add('boundary-'+str(i),position=list(map(bits,position)),velocity=list(map(bits,velocity)),yaw_f32_bits=fbits(yaw),input=list(map(bits,[0.,0.,0.])))
    for gravity,no_gravity,discard in [(-1.,False,False),(.08,True,False),(.08,False,True),(1.,False,True)]:
        add('gravity-'+str(len(cases)),grounded=False,position=list(map(bits,[.5,3.,-.5])),velocity=list(map(bits,[.2,-.1,.3])),gravity=bits(gravity),no_gravity=no_gravity,discard_friction=discard)
    width=struct.unpack('>f',bytes.fromhex('3f19999a'))[0]
    add('fully-blocked-application-gate',position=list(map(bits,[1.-width/2,1.,1.5])),velocity=list(map(bits,[.8,0.,0.])),input=list(map(bits,[0.,0.,0.])),step_height=bits(0.))
    assert len(cases)==31
    return cases

def observe(cases):
    jars,release=verified_classpath();work=ROOT/'build/travel-world-oracle';work.mkdir(parents=True,exist_ok=True)
    sources=[]
    for name,source in [('ReferenceMovementProbe',MOVE_SOURCE),('ReferenceDirectMovementProbe',DIRECT_SOURCE),('ReferenceTravelProbe',TRAVEL_SOURCE)]:
        p=work/(name+'.java');p.write_text(source);sources.append(p)
    cp=os.pathsep.join(map(str,jars));build=run([JAVA.parent/'javac','-cp',cp,'-d',work,*sources])
    incoming=work/'input.jsonl';outgoing=work/'output.jsonl';incoming.write_text(''.join(canonical(c).decode()+'\n' for c in cases))
    execution=run([JAVA,'-cp',str(work)+os.pathsep+cp,'ReferenceTravelProbe',incoming,outgoing]);observed=list(map(json.loads,outgoing.read_text().splitlines()))
    assert [c['id'] for c in observed]==[c['id'] for c in cases]
    result=[{**c,**o} for c,o in zip(cases,observed,strict=True)]
    assert all(c['observation']['full_player_travel_executed'] for c in result)
    # Observe exact collide/step/application results using the actual Entity
    # movement helper, then require its complete post-move body to equal the
    # untouched Player.travel observer before finishing gravity and drag.
    direct=[]
    for c in result:
        v=c['observation']['actual_input'];direct.append({'id':c['id'],'operation':'entity_move','input':{**v,'entity_type':'minecraft:player','grounded':c['input']['grounded'],'requested':c['observation']['requested'],'velocity':c['observation']['requested'],'world_blocks':c['input']['world_blocks']}})
    direct_in=work/'movement-input.jsonl';direct_out=work/'movement-output.jsonl';direct_in.write_text(''.join(canonical(c).decode()+'\n' for c in direct))
    direct_execution=run([JAVA,'-cp',str(work)+os.pathsep+cp,'ReferenceMovementProbe',direct_in,direct_out]);direct_observed=list(map(json.loads,direct_out.read_text().splitlines()))
    for c,d in zip(result,direct_observed,strict=True):
        assert c['id']==d['id'];post=c['observation']['post_move_body'];expected=d['expected'];actual=c['observation']['actual_input'];di=d['observation']['actual_input']
        assert {k:post[k] for k in ['position','box','velocity']}=={k:expected[k] for k in ['position','box','velocity']}
        assert post['flags']==expected['flags'][:4] and c['observation']['movement_recorded']==expected['flags'][4]
        assert actual['initial']==di['initial'] and actual['step']==di['step']
        assert actual['position']==di['position'] and actual['box']==di['box']
        c['movement_expected']=expected
    provenance={'build':build,'execution':execution,'input_sha256':sha(incoming),'output_sha256':sha(outgoing),'movement_execution':direct_execution,'movement_input_sha256':sha(direct_in),'movement_output_sha256':sha(direct_out),'java_sources_sha256':hashlib.sha256((MOVE_SOURCE+DIRECT_SOURCE+TRAVEL_SOURCE).encode()).hexdigest(),'pinned_classpath':[fingerprint(p) for p in jars],'runtime':fingerprint(JAVA),'release':release}
    return result,provenance

def request(c,op):
    return travel_request(c,op).split(';')[0]

def lines_by_kind(output):
    result={}
    for line in output.splitlines():
        f=line.split('|');key=(f[0],f[1]);assert key not in result,key;result[key]=line
    return result

def body(lines,id):return parse_travel(lines[id,'body'])[1]
def unchanged(lines,id,rollback=False):
    assert lines[id+'-before','clock'].split('|')[2:]==lines[id+'-after','clock'].split('|')[2:]
    assert lines[id+'-before','view'].split('|')[2:]==lines[id+'-after','view'].split('|')[2:]
    if rollback:assert body(lines,id+'-before')==body(lines,id+'-after')

def colliders(text):
    return [{'kind':'raw_array_box','box':scalars(s)} for s in text.split(';') if s]

def validate_cases(cases):
    native=[]
    for off in range(0,len(cases),6):
        chunk=cases[off:off+6];requests=[];expanded=[]
        for c in chunk:
            for op in ['prepare','trace','movement','travel']:
                v=copy.deepcopy(c);v['id']+='-'+op;expanded.append((v,op));requests.append(request(v,op))
        r=run([BINARY,'--gpu','off',TABLE,*requests]);native.append({'offset':off,'cases':len(chunk),'seconds':r['seconds']});lines=lines_by_kind(r['stdout'])
        for c,op in expanded:
            id=c['id'];unchanged(lines,id)
            if op=='prepare':
                assert parse_travel(lines[id,'prepared'])[1]=={k:c['observation'][k] for k in ['requested','friction_f32_bits','acceleration_f32_bits']}
                assert body(lines,id+'-after')==body(lines,id+'-before')
            elif op=='trace':
                _,_,initial,step=lines[id,'colliders'].split('|');actual=c['observation']['actual_input']
                assert colliders(initial)==actual['initial'] and colliders(step)==actual['step'],(id,initial,step,actual)
                assert body(lines,id+'-after')==body(lines,id+'-before')
            elif op=='movement':
                assert body(lines,id+'-after')==c['observation']['post_move_body'],id
                assert movement(lines[id+'-raw','movement'])['expected']==c['movement_expected'],id
            else:
                assert body(lines,id)==body(lines,id+'-after')==c['expected'],(id,body(lines,id),c['expected'])
                transition=lines[id,'transition'].split('|');assert len(transition)==10
                assert values(transition[2:8])==c['movement_expected']['displacement']
                assert bool(int(transition[8]))==c['movement_expected']['stepped']
                assert bool(int(transition[9]))==c['movement_expected']['flags'][4]==c['observation']['movement_recorded']
            assert lines[id,'continued'].endswith('|done')
    return native

def rejections(base):
    cases=[]
    def add(label,op,change,error):
        c=copy.deepcopy(base);c['id']='reject-'+label;change(c['observation']['actual_input']);cases.append((c,op,error))
    for mode in range(1,13):add('mode-'+str(mode),'retry',lambda v,mode=mode:v.__setitem__('mode',mode),'prepare|mode|'+str(mode))
    add('invalid-input','travel',lambda v:v.__setitem__('input',['7ff8000000000123']+base['input']['input'][1:]),'prepare|input|0')
    add('invalid-friction','travel',lambda v:v.__setitem__('block_friction_f32_bits','40000000'),'prepare|context|1')
    add('missing','missing',lambda v:None,'world|missing-section:')
    add('unsupported','unsupported',lambda v:None,'world|unsupported-block-state:')
    add('large-query','travel',lambda v:v.__setitem__('velocity',[bits(100.)]+v['velocity'][1:]),'world|collision-query-limit')
    add('finish-injection','finish-injection',lambda v:None,'finish|movement|result|')
    return cases

def validate_rejections(base):
    cases=rejections(base);requests=[request(c,op) for c,op,_ in cases]
    # These requests share the same affine Tables owner in one native process.
    r=run([BINARY,'--gpu','off',TABLE,*requests]);lines=lines_by_kind(r['stdout'])
    for c,op,error in cases:
        id=c['id'];unchanged(lines,id,rollback=True);assert lines[id,'error'].split('|',2)[2].startswith(error),(id,lines[id,'error'],error)
        if op=='retry':
            rid=id+'-retry';assert body(lines,rid)==body(lines,rid+'-after')==base['expected'];assert lines[rid,'continued'].endswith('|done')
            assert lines[id+'-after','clock'].split('|')[2:]==lines[rid+'-after','clock'].split('|')[2:]
            assert lines[id+'-after','view'].split('|')[2:]==lines[rid+'-after','view'].split('|')[2:]
        elif op in ['missing','unsupported']:assert '|error|' in lines[id,'continued']
        else:assert lines[id,'continued'].endswith('|done')
    return {'cases':len(cases),'same_world_successful_mode_retries':12,'finish_failure_injection':True,'seconds':r['seconds'],'errors':{c['id']:lines[c['id'],'error'] for c,_,_ in cases}}

def main():
    p=argparse.ArgumentParser();p.add_argument('--skip-build',action='store_true');args=p.parse_args()
    generations={p:sha(ROOT/p) for p in ['src/travel_world.bend','tests/travel_world.bend',*DEPENDENCIES]}
    checks=[run([BEND,p,'--check-only']) for p in ['src/travel_world.bend','tests/travel_world.bend']]
    if args.skip_build:
        previous=json.loads((ROOT/'evidence/travel-world-verification.json').read_text())
        assert previous['binary_sha256']==sha(BINARY)
        assert all(previous['sources_sha256'][p]==h for p,h in generations.items())
        builds=previous['builds']
    else:builds=[run([BEND,'tests/travel_world.bend','-o',BINARY])]
    cases,provenance=observe(inputs());native=validate_cases(cases);rejected=validate_rejections(cases[0])
    running=copy.deepcopy(cases[0]);running['id']='running';r=run([BINARY,'--gpu','off',TABLE,request(running,'running')]);lines=lines_by_kind(r['stdout']);unchanged(lines,'running');assert body(lines,'running')==cases[0]['expected'];assert lines['running-before','clock'].split('|')[4]=='0'
    # Reordering actual registry IDs must not change physical world travel.
    custom=ROOT/'build/travel-world-oracle/palette.tsv';names=['minecraft:oak_planks','minecraft:stone','minecraft:air','minecraft:dirt'];custom.write_text('block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json\n'+''.join(f'{i}\t{name}\t{i}\t1\t{i}\t[]\n' for i,name in enumerate(names)))
    env=os.environ.copy();env['MC_BLOCK_REGISTRY']=str(custom);remap=copy.deepcopy(cases[0]);remap['id']='remapped';r=run_with_env([BINARY,'--gpu','off',TABLE,request(remap,'travel')],env=env);lines=lines_by_kind(r['stdout']);unchanged(lines,'remapped');assert body(lines,'remapped')==cases[0]['expected'];assert lines['remapped-before','view'].split('|')[4]=='2,1,3,0'
    for p,h in generations.items():assert sha(ROOT/p)==h,('dependency generation changed',p)
    sources=[*generations,'tools/test_travel_world.py','docs/TRAVEL_WORLD.md','tools/reference_travel_probe.py','tools/reference_movement_probe.py']
    e={'schema_version':1,'status':'passed','pin':'26.3','actual_player_travel_cases':len(cases),'prepared_requests_compared':len(cases),'post_move_bodies_compared':len(cases),'ordered_collision_lists_compared':len(cases)*2,'final_installed_bodies_compared':len(cases),'fixture_blocks':39,'checked_fixture_mutations':47,'rejections':rejected,'running_clock_unchanged':True,'dynamic_registry_remap':True,'checks':checks,'builds':builds,'native_batches':native,'direct_java_provenance':provenance,'sources_sha256':{p:sha(ROOT/p) for p in sources if (ROOT/p).exists()},'binary_sha256':sha(BINARY),'table':fingerprint(TABLE),'stable_dependency_generation':True,'laws':re.findall(r'^law (\w+):',(ROOT/'src/travel_world.bend').read_text(),re.M),'whole_module_kernel_verified':False,'confidence':'high for the observed finite neutral cases; complete Player tick and general travel remain incomplete','scope':['sole owned World Engine and sine Tables retained','exact prepare then checked world block movement then finish once','caller-supplied actual supporting-aware ground sample and resolved attributes','terrain-free production operator; explicit checked fixture only','paused and running clock unchanged; no world mutation by operator'],'unsupported':['automatic supporting-block/friction/attribute resolution','full Player input tick/aiStep','fluid/flight/glide/climb','effects, hazards, entity collisions, world border','complete Minecraft client']}
    e.update(actual_entity_move_supplemental_cases=len(cases),returned_transition_scalars_compared=len(cases),actual_step_outcomes=sum(c['movement_expected']['stepped'] for c in cases),position_application_gate_rejections=sum(not c['observation']['movement_recorded'] for c in cases),nonempty_initial_collision_lists=sum(bool(c['observation']['actual_input']['initial']) for c in cases),nonempty_step_collision_lists=sum(bool(c['observation']['actual_input']['step']) for c in cases),remapped_registry_sha256=sha(custom),verified_build_reused=args.skip_build)
    assert e['actual_step_outcomes']>0 and e['position_application_gate_rejections']>0
    (ROOT/'evidence/travel-world-verification.json').write_text(json.dumps(e,indent=2,sort_keys=True)+'\n');print(json.dumps({k:e[k] for k in ['status','actual_player_travel_cases','ordered_collision_lists_compared','position_application_gate_rejections','dynamic_registry_remap','running_clock_unchanged','confidence']},indent=2))

if __name__=='__main__':main()
