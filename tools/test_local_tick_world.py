#!/usr/bin/env python3
"""Owned local aiStep motion versus fresh untouched LocalPlayer receivers."""
from __future__ import annotations
import argparse,base64,copy,hashlib,json,os,pathlib,re,runpy,subprocess,time,zipfile
from reference_inventory import ROOT,JAVA,canonical,fingerprint
from reference_model_probe import CLIENT,verified_client_classpath
from reference_local_input_probe import receiver_sources,RECEIVER_SOURCES,RECEIVER_LAUNCHER,corpus_inputs,collect
from test_local_input import project_local,project_player,local_words,player_words,apply_words,local_state,player_state,parse as input_parse
from test_geometry import run,sha,word_vector
from test_travel_world import lines_by_kind,colliders
from test_travel import values
from test_client_world import run as run_env
BEND=pathlib.Path.home()/'.bend/bin/bend';BINARY=ROOT/'build/local-tick-world-motion-tests';FINISH_BINARY=ROOT/'build/local-tick-world-finish-tests';TABLE=ROOT/'generated/reference_mth_sin.f32'
DEPS=['src/local_input.bend','src/player_tick_world.bend','src/player_tick.bend','src/travel_world.bend','src/travel.bend','src/locomotion.bend','src/movement.bend','src/player_input.bend','src/client_world.bend','src/f64.bend','src/geometry.bend','src/core.bend','src/game.bend','src/registry.bend','src/client_render.bend','src/schedule.bend','src/section_map.bend']
LI_SHA='5e3555fdb06258a76478a32d32332455ad186ec956607ce981e198a3c28ca02e'
def db(v):return __import__('struct').pack('>d',v).hex()
def fb(v):return __import__('struct').pack('>f',v).hex()

def source_dependencies():
    pending=[ROOT/'tests/local_tick_world.bend'];seen=set()
    while pending:
        path=pending.pop().resolve()
        if path in seen:continue
        seen.add(path)
        for target in re.findall(r'^import\s+(\S+)',path.read_text(),re.M):
            if target.startswith('.'):pending.append((path.parent/target).resolve())
    return sorted(str(p.relative_to(ROOT)) for p in seen)

def generated_entries(write=True):
    source=(ROOT/'tests/local_tick_world.bend').read_text();begin=source.index('def run_phase(');end=source.index('def phase_before(',begin)
    original=source[begin:end]
    motion=original.replace('    case "finish-injection": finish_injected(id, world, tables, phase)\n','    case "finish-injection": IO.die(Harness, 4, "finish injection requires its separate entry")\n')
    finish='''def run_phase(id: String, op: String, world: W.State, tables: L.Tables, phase: Phase) -> IO(Harness):
  match op:
    case "finish-injection": finish_injected(id, world, tables, phase)
    case _: call_tick(id, world, tables, phase)

'''
    assert motion!=original and 'finish_injected(' not in motion and 'observed_prepared(' not in finish
    result={}
    for lane,body in [('motion',motion),('finish',finish)]:
        text=source[:begin]+body+source[end:]
        old='def main() -> IO(Unit):\n  IO.bind(List<String>, Unit, IO.args(), arguments)\n'
        new=f'def {lane}_arguments(args: List<String>) -> IO(Unit):\n  arguments(args)\n\ndef main() -> IO(Unit):\n  IO.bind(List<String>, Unit, IO.args(), {lane}_arguments)\n'
        assert old in text;text=text.replace(old,new,1);path=ROOT/f'build/local-tick-world-{lane}.bend'
        if write:path.write_text(text)
        else:assert path.read_text()==text,('retained entry changed',lane)
        result[lane]={'path':str(path.relative_to(ROOT)),'sha256':sha(path),'template_sha256':sha(ROOT/'tests/local_tick_world.bend'),'replacement_scope':'only run_phase dispatch and a named main argument adapter','body_sha256':hashlib.sha256(body.encode()).hexdigest()}
    return result

def inputs():
    all=corpus_inputs()['ai_step'];names=['held_forward','held_diagonal','double_tap_and_sprint','double_start_then_major_stop','new_shift_latency','jump_held','jump_sprint','zero_move_yya','food_collision_changes']
    cases=[c for c in all if c['id'].split(':')[1] in names]
    for name,pos,vel,maximum in [('step',[.5,1.,.5],[.8,-.1,0.],1.),('blocked',[1.-__import__('struct').unpack('>f',bytes.fromhex('3f19999a'))[0]/2,1.,.5],[.8,0.,0.],0.)]:
        c=copy.deepcopy(cases[0]);c['id']='ai:world-'+name;c['initial']['position']=list(map(db,pos));c['initial']['velocity']=list(map(db,vel));c['initial']['step_height']=db(maximum);c['initial']['world_blocks']=[{'position':[1,1,0],'identifier':'minecraft:stone'}];c['initial']['rotation_f32_bits']=[fb(-90),fb(-11),fb(-90),fb(-9)];c['steps']=[{'held_mask':0} for _ in range(3)];cases.append(c)
    return {k:cases if k=='ai_step' else [] for k in ['keyboard','vectors','receivers','ai_step']}

def derive_sources(incoming):
    sources=receiver_sources(incoming);name='net.minecraft.fixture.LocalInputReceiverFixture';s=sources[name]
    s=s.replace('  void hit(String name){observations.merge(name,1,Integer::sum);}',r'''
  boolean recording;
  final List<Map<String,Object>> collisionQueries=new ArrayList<>();
  static String collisionPurpose(){
   List<StackWalker.StackFrame> stack=StackWalker.getInstance().walk(s->s.toList());
   if(stack.stream().anyMatch(f->f.getClassName().equals(Entity.class.getName())&&f.getMethodName().equals("collideBoundingBox")))return "initial";
   if(stack.stream().anyMatch(f->f.getClassName().equals(Entity.class.getName())&&f.getMethodName().equals("collide")))return "step";
   if(stack.stream().anyMatch(f->f.getMethodName().equals("maybeBackOffFromEdge")))return "sneak_edge";
   return "other";
  }
  public Iterable<net.minecraft.world.phys.shapes.VoxelShape> getBlockCollisions(Entity e,AABB box){
   Iterable<net.minecraft.world.phys.shapes.VoxelShape> actual=super.getBlockCollisions(e,box);
   if(!recording)return actual;
   List<net.minecraft.world.phys.shapes.VoxelShape> shapes=new ArrayList<>();List<List<String>> boxes=new ArrayList<>();
   for(var shape:actual){shapes.add(shape);List<AABB> parts=shape.toAabbs();if(parts.size()!=1)throw new AssertionError("Expected actual full-cube shape");AABB b=parts.getFirst();boxes.add(List.of(bits(b.minX),bits(b.minY),bits(b.minZ),bits(b.maxX),bits(b.maxY),bits(b.maxZ)));}
   collisionQueries.add(Map.of("phase",collisionPurpose(),"box",List.of(bits(box.minX),bits(box.minY),bits(box.minZ),bits(box.maxX),bits(box.maxY),bits(box.maxZ)),"shapes",boxes));return shapes;
  }
  void hit(String name){observations.merge(name,1,Integer::sum);}''')
    s=s.replace('  public void applyInput(){',r'''
  public void move(MoverType type,Vec3 requested){
   FixtureLevel level=(FixtureLevel)level();level.collisionQueries.clear();level.recording=true;
   if(calls!=null)calls.add(Map.of("method","move_entry","requested",vector(requested),"state",state(this)));
   super.move(type,requested);level.recording=false;
   if(calls!=null)calls.add(Map.of("method","move_exit","queries",List.copyOf(level.collisionQueries),"state",state(this)));
  }
  public void recordMovement(MoverType type,Vec3 resolved){super.recordMovement(type,resolved);if(calls!=null)calls.add(Map.of("method","recordMovement","resolved",vector(resolved)));}
  public void setOnGroundWithMovement(boolean ground,boolean horizontal,Vec3 resolved){super.setOnGroundWithMovement(ground,horizontal,resolved);if(calls!=null){Map<String,Object> row=new TreeMap<>();row.put("method","support_move");row.put("resolved",resolved==null?null:vector(resolved));calls.add(row);}}
  public void applyInput(){''')
    s=s.replace('LocalPlayer p=c.player;c.mc.options.sprintWindow()',r'''LocalPlayer p=c.player;
  if(in.has("position"))p.setPos(v3(in.getAsJsonArray("position")));
  if(in.has("step_height"))p.getAttribute(Attributes.STEP_HEIGHT).setBaseValue(d(in.get("step_height")));
  if(in.has("world_blocks"))for(JsonElement e:in.getAsJsonArray("world_blocks")){JsonObject b=e.getAsJsonObject();JsonArray pos=b.getAsJsonArray("position");String id=b.get("identifier").getAsString();if(!Set.of("minecraft:stone","minecraft:dirt","minecraft:oak_planks").contains(id))throw new AssertionError("Unsupported declared finite block");c.level.blocks.put(new BlockPos(pos.get(0).getAsInt(),pos.get(1).getAsInt(),pos.get(2).getAsInt()),BuiltInRegistries.BLOCK.getValue(Identifier.parse(id)).defaultBlockState());}
  c.mc.options.sprintWindow()''')
    sources[name]=s;return sources

def observe(incoming):
    classpath,provenance=verified_client_classpath();sources=derive_sources(incoming)
    payload={'sources':sources,'client_jar':str(CLIENT),'mode':'corpus'};encoded=base64.b64encode(canonical(payload)).decode();chunks=','.join(json.dumps(encoded[i:i+6144]) for i in range(0,len(encoded),6144));launcher=RECEIVER_LAUNCHER.replace('Base64.getDecoder().decode(args[0])','Base64.getDecoder().decode(String.join("",new String[]{'+chunks+'}))',1)
    command=[str(JAVA),'--source','25','--class-path',os.pathsep.join(map(str,classpath)),'/dev/stdin'];start=time.monotonic();r=subprocess.run(command,input=launcher,capture_output=True,text=True,timeout=180);assert r.returncode==0,r.stderr[-9000:]
    rows=[json.loads(l[len('LOCAL_RECEIVER_JSON:'):]) for l in r.stdout.splitlines() if l.startswith('LOCAL_RECEIVER_JSON:')];classes=[json.loads(l[len('LOCAL_INPUT_CLASSES:'):]) for l in r.stdout.splitlines() if l.startswith('LOCAL_INPUT_CLASSES:')];assert len(classes)==1
    with zipfile.ZipFile(CLIENT) as jar:
        for name,h in classes[0].items():assert hashlib.sha256(jar.read(name.replace('.','/')+'.class')).hexdigest()==h,name
    for name in ['net.minecraft.client.player.LocalPlayer','net.minecraft.client.player.AbstractClientPlayer','net.minecraft.world.entity.player.Player','net.minecraft.world.entity.LivingEntity','net.minecraft.world.entity.Entity','net.minecraft.client.multiplayer.ClientLevel']:assert name in classes[0]
    folded=collect(incoming,{'observations':rows})['ai_step']
    for c in folded:
        for s in c['steps']:
            assert not s['control_velocity_changed'] and not c['initial']['ceiling'] and not c['initial']['blindness']
            events=s['observer_calls']
            def event(method):
                found=[e for e in events if e['method']==method];assert len(found)==1,(c['id'],method,found);return found[0]
            s['actual_move_entry']=event('move_entry');s['actual_move_exit']=event('move_exit');s['actual_support_move']=event('support_move');s['actual_record_movement']=[e for e in events if e['method']=='recordMovement'];assert len(s['actual_record_movement'])<=1
    e={'schema_version':1,'status':'passed','pin':'26.3','cases':folded,'cases_sha256':hashlib.sha256(canonical(folded)).hexdigest(),'execution':{'command':command,'seconds':round(time.monotonic()-start,6),'returncode':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout.encode()).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr.encode()).hexdigest()},'classpath':provenance,'java_runtime':fingerprint(JAVA),'client_jar':fingerprint(CLIENT),'loaded_official_classes':classes[0],'loaded_official_class_tree_sha256':hashlib.sha256(canonical(classes[0])).hexdigest(),'inputs_sha256':hashlib.sha256(canonical(incoming)).hexdigest(),'derived_fixture_sources_sha256':{n:hashlib.sha256(s.encode()).hexdigest() for n,s in sources.items()},'base_templates_sha256':{n:hashlib.sha256(s.encode()).hexdigest() for n,s in RECEIVER_SOURCES.items()},'launcher_sha256':hashlib.sha256(launcher.encode()).hexdigest(),'scope':'Fresh normal-constructed actual LocalPlayer.aiStep and ClientLevel; unchanged official bytes, four explicit external service fixtures, super-calling observers and plain/observed final-state parity; 25-stone floor plus explicit full-cube collision fixtures; no commonTick/pose/full tick claim'}
    (ROOT/'reference/local_tick_world.json').write_text(json.dumps(e,sort_keys=True,indent=2)+'\n');return folded,e

def request(c,i,op):
    step=c['steps'][i];before=step['before'];snapshot=step['control_snapshot']['state'];ctx=step['context'];held=step['input']['held_mask']
    control=[held,int(ctx['fits']['standing']),int(ctx['fits']['crouching']),ctx['food'],int(ctx['mayfly']),int(ctx['flying']),int(ctx['mobility_restricted']),int(before['body_flags'][1]),int(before['minor_horizontal_collision']),ctx['sprint_window'],{'STANDING':0,'CROUCHING':1}[before['pose']],0,int('horizontal_collision' in step['input'])]
    groups=[c['id']+':'+str(i)+'|'+op,local_words(project_local(before),before['sprinting']),player_words(project_player(before)),control,apply_words(snapshot,ctx)]
    return ';'.join(g if isinstance(g,str) else '|'.join(str(int(v)&0xffffffff) for v in g) for g in groups)

def unchanged(lines,id,rollback=False):
    for kind in ['clock','view']:assert lines[id+'-before',kind].split('|')[2:]==lines[id+'-after',kind].split('|')[2:],(id,kind)
    if rollback:
        for before_kind,after_kind in [('body','body'),('local','local'),('state','state')]:assert lines[id+'-before',before_kind].split('|')[2:]==lines[id if after_kind!='body' else id+'-after',after_kind].split('|')[2:],(id,after_kind)

def parsed_local(line):return local_state(line.split('|')[2:])
def parsed_player(line):return player_state(line.split('|')[2:])
def expected_collider_line(id,groups):
    assert len(groups)==2
    encoded=[]
    for group in groups:
        records=[]
        for box in group:
            assert len(box)==6 and all(re.fullmatch(r'[0-9a-f]{16}',value) for value in box),box
            words=word_vector(box);assert len(words)==12
            records.append('|'.join(map(str,words))+';')
        encoded.append(''.join(records))
    return id+'|colliders|'+encoded[0]+'|'+encoded[1]

def validate_tick(lines,c,i,diagnostics=True):
    id=c['id']+':'+str(i);s=c['steps'][i];unchanged(lines,id)
    assert parsed_local(lines[id,'local'])==project_local(s['expected']),id
    assert parsed_player(lines[id,'state'])==parsed_player(lines[id,'transition-state'])==project_player(s['expected']),id
    assert parsed_local(lines[id+'-before','local'])==project_local(s['before']),id
    assert parsed_player(lines[id+'-before','state'])==project_player(s['before']),id
    assert lines[id+'-before','body'].split('|')[2:]==list(map(str,player_words(project_player(s['before']))[:30])),(id,'authoritative world before')
    assert lines[id+'-after','body'].split('|')[2:]==list(map(str,player_words(project_player(s['expected']))[:30])),(id,'authoritative world after')
    control=input_parse(lines[id,'controls'])[1];snapshot=s['control_snapshot'];assert control=={**project_local(snapshot['state']),'sprinting':snapshot['state']['sprinting'],'sprint_updates':snapshot['sprint_updates']},(id,control)
    assert lines[id,'context'].split('|')[2:]==[','.join(str(v&0xffffffff) for v in s['context']['ground_sample']['position']),*map(lambda v:str(int(v)&0xffffffff),apply_words(snapshot['state'],s['context'])[3:])],id
    tr=lines[id,'transition'].split('|');assert values(tr[2:8])==s['actual_support_move']['resolved'],id;assert bool(int(tr[-1]))==bool(s['actual_record_movement']),id
    if not diagnostics:return
    prep=input_parse(lines[id,'prepared'])[1];assert prep['local']==project_local(s['after_input']['state']) and prep['player']==project_player(s['pre_travel']['state']) and prep['travel_input']==s['pre_travel']['input'],(id,prep)
    assert values(lines[id,'requested'].split('|')[2:])==s['actual_move_entry']['requested'],id
    actual=s['actual_move_exit']['queries'];groups=[]
    assert all(q['phase'] in ['initial','step','sneak_edge'] for q in actual),(id,actual)
    for j,phase in enumerate(['initial','step']):
        selected=[q for q in actual if q['phase']==phase];assert len(selected)<=1,(id,phase,selected)
        groups.append(selected[0]['shapes'] if selected else [])
        query=lines[id,'query-'+phase].split('|')[2:]
        assert query==(['none'] if not selected else [str(v) for v in word_vector(selected[0]['box'])]),(id,phase,query,selected)
    expected=expected_collider_line(id,groups)
    assert lines[id,'colliders']==expected,(id,lines[id,'colliders'],expected)

def validate_cases(cases):
    batches=[]
    for c in cases:
        cmds=[request(c,i,('start-block' if c['initial'].get('world_blocks') else 'start') if i==0 else 'chain') for i in range(len(c['steps']))];r=run([BINARY,'--gpu','off',TABLE,*cmds]);lines=lines_by_kind(r['stdout'])
        for i in range(len(c['steps'])):validate_tick(lines,c,i)
        batches.append({'id':c['id'],'ticks':len(c['steps']),'seconds':r['seconds'],'ordered_sprint_setters':sum(len(s['control_snapshot']['sprint_updates']) for s in c['steps']),'application_gate_rejections':sum(not s['actual_record_movement'] for s in c['steps']),'native_step_outcomes':sum(bool(int(lines[c['id']+':'+str(i),'transition'].split('|')[-2])) for i in range(len(c['steps']))),'precollision_sneak_queries':sum(q['phase']=='sneak_edge' for s in c['steps'] for q in s['actual_move_exit']['queries'])})
    return batches

def finish_reject_case(base):
    c=copy.deepcopy(base);c['id']='reject-finish-injection';recovery=copy.deepcopy(base);recovery['id']='recovered-finish-injection'
    r=run([FINISH_BINARY,'--gpu','off',TABLE,request(c,1,'start-finish'),request(recovery,1,'chain')]);lines=lines_by_kind(r['stdout']);id=c['id']+':1';unchanged(lines,id,True);assert lines[id,'error'].split('|',2)[2]=='finish';validate_tick(lines,recovery,1,diagnostics=False)
    return {'id':id,'error':'finish','continued_same_owners':True,'entry':'separate checked-finish rollback and actual motion recovery','initial_prior':'fresh actual Java before-state at the rejected frame','recovery_actual_ai_step_index':1}

def reject_cases(base,lane='all'):
    results=[]
    ordinary=[('sprint-mismatch','prepare|sprint'),('invalid-sneak','prepare|attribute'),('invalid-pitch','prepare|pitch'),('invalid-jump','prepare|player'),('mismatch','body-mismatch')] if lane!='finish' else []
    for op,error in ordinary:
        c=copy.deepcopy(base);c['id']='reject-'+op;recovery=copy.deepcopy(base);recovery['id']='recovered-'+op;cmds=[request(base,0,'start'),request(c,1,op),request(recovery,1,'chain')]
        if op=='mismatch':cmds[-1]=request(recovery,1,'start')
        r=run([BINARY,'--gpu','off',TABLE,*cmds]);lines=lines_by_kind(r['stdout']);id=c['id']+':1';unchanged(lines,id,True);assert lines[id,'error'].split('|',2)[2].startswith(error),(id,lines[id,'error']);validate_tick(lines,recovery,1);results.append({'id':id,'error':error,'continued_same_owners':True})
    if lane!='motion':results.append(finish_reject_case(base))
    world_errors=[('missing','fixture-recovery','travel|world|missing-section:'),('unsupported','repair','travel|world|unsupported-block-state:')] if lane!='finish' else []
    for op,repair,error in world_errors:
        c=copy.deepcopy(base);c['id']='reject-'+op;recovery=copy.deepcopy(base);recovery['id']='recovered-'+op;r=run([BINARY,'--gpu','off',TABLE,request(c,0,op),request(recovery,0,repair)]);lines=lines_by_kind(r['stdout']);id=c['id']+':0';unchanged(lines,id,True);assert lines[id,'error'].split('|',2)[2].startswith(error);validate_tick(lines,recovery,0);results.append({'id':id,'error':error,'continued_same_owners':True,'checked_fixture_repair_outside_facade':True})
    return results

def retained_reference(expected_sha256):
    path=ROOT/'reference/local_tick_world.json';assert expected_sha256 and sha(path)==expected_sha256,'retained reference changed'
    provenance=json.loads(path.read_text());cases=provenance['cases'];incoming=inputs()
    assert provenance['status']=='passed' and provenance['pin']=='26.3'
    assert hashlib.sha256(canonical(cases)).hexdigest()==provenance['cases_sha256']
    assert hashlib.sha256(canonical(incoming)).hexdigest()==provenance['inputs_sha256']
    assert {n:hashlib.sha256(s.encode()).hexdigest() for n,s in derive_sources(incoming).items()}==provenance['derived_fixture_sources_sha256'],'actual Java fixture changed'
    assert {n:hashlib.sha256(s.encode()).hexdigest() for n,s in RECEIVER_SOURCES.items()}==provenance['base_templates_sha256'],'base Java templates changed'
    assert fingerprint(CLIENT)==provenance['client_jar'],'pinned client JAR changed'
    return cases,provenance

def main():
    p=argparse.ArgumentParser();p.add_argument('--oracle-only',action='store_true');p.add_argument('--check-entries-only',action='store_true');p.add_argument('--skip-build',action='store_true');p.add_argument('--reuse-reference',action='store_true');p.add_argument('--reference-sha256');p.add_argument('--entry',choices=['all','motion','finish'],default='all');a=p.parse_args();assert sha(ROOT/'src/local_input.bend')==LI_SHA
    assert not a.reuse_reference or (a.skip_build and a.reference_sha256 and not a.oracle_only and not a.check_entries_only),'reference reuse requires a pinned artifact and skip-build'
    entries=generated_entries(write=not a.skip_build)
    if a.check_entries_only:
        checks=[run([BEND,entries[lane]['path'],'--check-only']) for lane in ['motion','finish']];(ROOT/'evidence/local-tick-world-split-entries.json').write_text(json.dumps({'status':'ordinary-checked; native unverified','entries':entries,'checks':checks,'source_dependencies_sha256':{p:sha(ROOT/p) for p in source_dependencies()}},indent=2,sort_keys=True)+'\n');print(json.dumps({'entries':entries,'checks_seconds':[c['seconds'] for c in checks]},indent=2));return
    producers={p:sha(ROOT/p) for p in ['tools/test_local_tick_world.py','tools/reference_local_input_probe.py','tools/test_local_input.py','tools/test_travel_world.py','tools/test_travel.py','tools/test_geometry.py','tools/test_client_world.py']}
    cases,provenance=retained_reference(a.reference_sha256) if a.reuse_reference else observe(inputs())
    if a.oracle_only:return
    generations={p:sha(ROOT/p) for p in source_dependencies()};checks=[run([BEND,p,'--check-only']) for p in ['src/local_tick_world.bend','tests/local_tick_world.bend']]
    wanted=['motion','finish'] if a.entry=='all' else [a.entry];binaries={'motion':BINARY,'finish':FINISH_BINARY};builds=[]
    for lane in wanted:
        binary=binaries[lane];manifest=ROOT/f'build/local-tick-world-{lane}-build.json'
        if a.skip_build:
            prior=json.loads(manifest.read_text());assert prior['sources_sha256']==generations and prior['entry']==entries[lane] and prior['binary_sha256']==sha(binary);build=prior['build']
        else:
            print(json.dumps({'phase':'native-build','entry':lane,'pid':os.getpid(),'timeout_seconds':600}),flush=True)
            receipt=ROOT/f'evidence/local-tick-world-{lane}-build-attempt.json';attempt={'status':'running','timeout_seconds':600,'sources_sha256':generations,'entry':entries[lane],'producers_before_sha256':producers,'producer_pid':os.getpid(),'compiler':fingerprint(BEND)};receipt.write_text(json.dumps(attempt,indent=2,sort_keys=True)+'\n')
            try:build=run([BEND,entries[lane]['path'],'-o',binary],timeout=600)
            except RuntimeError as error:
                attempt.update(status='failed',build=json.loads(str(error)));receipt.write_text(json.dumps(attempt,indent=2,sort_keys=True)+'\n');raise
            except subprocess.TimeoutExpired as error:
                attempt.update(status='timed_out',build={'command':list(map(str,error.cmd)),'seconds':600,'stdout':error.stdout.decode() if isinstance(error.stdout,bytes) else error.stdout or '', 'stderr':error.stderr.decode() if isinstance(error.stderr,bytes) else error.stderr or ''});receipt.write_text(json.dumps(attempt,indent=2,sort_keys=True)+'\n');raise
            attempt.update(status='compiled; native comparison pending',build=build,binary_sha256=sha(binary));receipt.write_text(json.dumps(attempt,indent=2,sort_keys=True)+'\n');manifest.write_text(json.dumps({'build':build,'sources_sha256':generations,'entry':entries[lane],'binary_sha256':sha(binary)},indent=2)+'\n')
        builds.append(build)
    print(json.dumps({'phase':'native-compare','build_seconds':builds[0]['seconds']}),flush=True)
    batches=validate_cases(cases) if a.entry!='finish' else [];rejections=reject_cases(cases[0],a.entry);custom=ROOT/'build/local-tick-world-palette.tsv';names=['minecraft:oak_planks','minecraft:stone','minecraft:air','minecraft:dirt'];custom.write_text('block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json\n'+''.join(f'{i}\t{n}\t{i}\t1\t{i}\t[]\n' for i,n in enumerate(names)));env=os.environ.copy();env['MC_BLOCK_REGISTRY']=str(custom);c=cases[0];selected='finish' if a.entry=='finish' else 'motion';r=run_env([binaries[selected],'--gpu','off',TABLE,request(c,0,'start')],env=env);validate_tick(lines_by_kind(r['stdout']),c,0,diagnostics=selected=='motion')
    for p,h in generations.items():assert sha(ROOT/p)==h,('source changed during native verification',p)
    producer_after={p:sha(ROOT/p) for p in producers}
    for p,h in producers.items():
        if p!='tools/reference_local_input_probe.py':assert producer_after[p]==h,('test producer changed during native verification',p)
    fresh=runpy.run_path(str(ROOT/'tools/reference_local_input_probe.py'));assert fresh['RECEIVER_SOURCES']==RECEIVER_SOURCES and fresh['RECEIVER_LAUNCHER']==RECEIVER_LAUNCHER,'actual Java templates changed during verification'
    source=(ROOT/'src/local_tick_world.bend').read_text();assert 'P.prepare_checked' not in source and 'PW.tick_checked' not in source and not re.search(r'@unsafe|\bimport\s+["\']|\w!\(',source)
    e={'schema_version':1,'status':'passed','pin':'26.3','actual_local_ai_step_calls':sum(b['ticks'] for b in batches),'native_sequences':batches,'carried_native_ticks':sum(b['ticks']-1 for b in batches),'ordered_collision_lists_compared':2*sum(b['ticks'] for b in batches),'ordered_sprint_setters_compared':sum(b['ordered_sprint_setters'] for b in batches),'successful_moves_without_position_application':sum(b['application_gate_rejections'] for b in batches),'native_step_outcomes':sum(b['native_step_outcomes'] for b in batches),'rejections':rejections,'same_owner_recovery_cases':len(rejections),'clock_view_cache_unchanged':True,'dynamic_registry_remap':True,'fixture_floor_blocks':25,'base_checked_fixture_mutations':66,'caller_support_context':'fresh actual supporting-aware ground/friction/jump observations, not fabricated support','builds':builds,'checks':checks,'compiler':fingerprint(BEND),'compiler_version':run([BEND,'version']),'provenance':provenance,'binary_sha256':{lane:sha(binaries[lane]) for lane in wanted},'table':fingerprint(TABLE),'sources_sha256':{**generations,'tools/test_local_tick_world.py':sha(ROOT/'tools/test_local_tick_world.py'),'tools/reference_local_input_probe.py':sha(ROOT/'tools/reference_local_input_probe.py')},'ordinary_laws':re.findall(r'^law (\w+):',source,re.M),'whole_module_kernel_verified':False,'confidence':'high within explicit neutral LocalPlayer input/aiStep motion projection; commonTick, rotations, pose update, push-out, lifecycle and complete tick remain outside the facade'}
    e.update({'producer_sources_before_sha256':producers,'producer_sources_after_sha256':producer_after,'actual_java_templates_unchanged':True,'precollision_sneak_queries_observed':sum(b['precollision_sneak_queries'] for b in batches),'precollision_sneak_scope':'Measured actual noCollision probes recorded separately; these admitted interior fixtures preserve the incoming request, demonstrated by exact collision query boxes and movement state parity. General sneak-edge correction is outside this facade.','native_build_timeout_seconds':600})
    e.update({'generated_entries':entries,'verified_entries':wanted,'entry_binary_sha256':{lane:sha(binaries[lane]) for lane in wanted},'separate_finish_lane':True,'authoritative_world_body_before_after_compared':True,'checked_finish_motion_recovery_calls':int(a.entry!='motion'),'native_build_reused':a.skip_build,'java_reference_reused':a.reuse_reference,'reference_artifact':{'path':'reference/local_tick_world.json','sha256':sha(ROOT/'reference/local_tick_world.json')},'collider_comparison':'entire independently encoded exact row, including all raw words, record order, semicolons and empty groups'})
    target=ROOT/('evidence/local-tick-world-verification.json' if a.entry=='all' else f'evidence/local-tick-world-{a.entry}-verification.json');target.write_text(json.dumps(e,indent=2,sort_keys=True)+'\n');print(json.dumps({k:e[k] for k in ['status','actual_local_ai_step_calls','ordered_sprint_setters_compared','same_owner_recovery_cases','native_step_outcomes','confidence']},indent=2))
if __name__=='__main__':main()
