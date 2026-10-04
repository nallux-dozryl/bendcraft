#!/usr/bin/env python3
"""Direct whole LocalPlayer.move with exact finite-world query and phase traces.

Only new receiver observers and external finite world setup are derived from the
frozen LCW/LC/LI templates. Every decisive move result is an untouched Java call.
"""
from __future__ import annotations
import argparse,base64,copy,hashlib,json,math,re,struct,subprocess,time,zipfile
from pathlib import Path
from reference_inventory import ROOT,JAVA,canonical,fingerprint
from reference_model_probe import CLIENT,verified_client_classpath
import reference_local_collision_world_probe as LCW
LC=LCW.LC
OUTPUT=ROOT/'reference/local_move_world.json'
CLASS='net.minecraft.fixture.LocalMoveWorldReceiverFixture'
RAW=ROOT/'build/local-move-world-reference'
FROZEN_LCW_REFERENCE='a72c5f81863fc1af689e1050a00e4aac5f1f8d2e646efbc005891921a1474e05'
FROZEN_LCW_SOURCE='9a0618d6c526096862878dbec4295c357e9bb96a6613b51f5b2118bc60338a57'

def sha(v):return hashlib.sha256(canonical(v)).hexdigest()
def save(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(canonical(v)+b'\n')

OBSERVERS=r'''
 static Map<String,Object> body(LocalPlayer p){try{Map<String,Object> m=new TreeMap<>();m.put("position",vector(p.position()));m.put("box",box(p.getBoundingBox()));m.put("velocity",vector(p.getDeltaMovement()));m.put("body_flags",List.of(p.onGround(),p.horizontalCollision,p.verticalCollision,p.verticalCollisionBelow));m.put("minor_horizontal_collision",p.minorHorizontalCollision);m.put("width_f32_bits",bits(p.getBbWidth()));m.put("height_f32_bits",bits(p.getBbHeight()));m.put("fall_distance_f64_bits",bits(p.fallDistance));Optional<?> support=(Optional<?>)LocalInputReceiverFixture.read(p,"mainSupportingBlockPos");m.put("main_support",support.isPresent()?position((BlockPos)support.get()):null);m.put("on_ground_no_blocks",LocalInputReceiverFixture.read(p,"onGroundNoBlocks"));return m;}catch(Exception e){throw new RuntimeException(e);}}
 static List<Integer> position(BlockPos p){return List.of(p.getX(),p.getY(),p.getZ());}
 static List<List<String>> boxes(VoxelShape shape){List<List<String>> a=new ArrayList<>();for(AABB b:shape.toAabbs())a.add(box(b));return a;}
 static class TraceLevel extends LocalInputReceiverFixture.FixtureLevel {
  final List<Map<String,Object>> events=new ArrayList<>();boolean capture=false;int query=-1,nextQuery=0;
  TraceLevel(ClientPacketListener connection,Holder<net.minecraft.world.level.dimension.DimensionType> dimension){super(connection,dimension);}
  void clear(){events.clear();nextQuery=0;query=-1;}
  void add(Map<String,Object> original){if(capture&&events!=null){Map<String,Object> e=new TreeMap<>(original);e.put("sequence",events.size());events.add(e);}}
  int enter(String method,AABB b){int q=nextQuery++;add(Map.of("method",method+"_entry","query",q,"parent_query",query,"box",box(b)));return q;}
  public BlockState getBlockState(BlockPos p){BlockState b=super.getBlockState(p);if(capture&&events!=null){int ordinal=0;for(Map<String,Object> old:events)if(old.get("method").equals("getBlockState")&&old.get("query").equals(query))ordinal++;Map<String,Object> e=new TreeMap<>();e.put("method","getBlockState");e.put("query",query);e.put("ordinal",ordinal);e.put("position",position(p));e.put("block_id",BuiltInRegistries.BLOCK.getKey(b.getBlock()).toString());e.put("state_id",Block.getId(b));e.put("state_name",b.toString());add(e);}return b;}
  public boolean noCollision(Entity p,AABB b){int old=query,q=enter("noCollision",b);query=q;try{boolean result=super.noCollision(p,b);add(Map.of("method","noCollision_exit","query",q,"result",result));return result;}finally{query=old;}}
  public List<VoxelShape> getEntityCollisions(Entity p,AABB b){int q=enter("entityCollisions",b);List<VoxelShape> result=super.getEntityCollisions(p,b);List<List<List<String>>> shapes=new ArrayList<>();for(VoxelShape s:result)shapes.add(boxes(s));add(Map.of("method","entityCollisions_exit","query",q,"shapes",shapes));return result;}
  public Iterable<VoxelShape> getBlockCollisions(Entity p,AABB b){Iterable<VoxelShape> source=super.getBlockCollisions(p,b);boolean owns=query<0;int q=owns?enter("blockCollisions",b):query;return ()->{Iterator<VoxelShape> it=source.iterator();return new Iterator<VoxelShape>(){boolean exited=false;public boolean hasNext(){int old=query;query=q;try{boolean value=it.hasNext();if(!value&&owns&&!exited){add(Map.of("method","blockCollisions_exit","query",q));exited=true;}return value;}finally{query=old;}}public VoxelShape next(){int old=query;query=q;try{VoxelShape v=it.next();add(Map.of("method","actual_block_collision_shape_yield","query",q,"boxes",boxes(v)));return v;}finally{query=old;}}};};}
  public Optional<BlockPos> findSupportingBlock(Entity p,AABB b){int old=query,q=enter("support",b);query=q;try{Optional<BlockPos> result=super.findSupportingBlock(p,b);Map<String,Object> e=new TreeMap<>();e.put("method","support_exit");e.put("query",q);e.put("selected",result.isPresent()?position(result.get()):null);add(e);return result;}finally{query=old;}}
 }
 static class ObservedPlayer extends LocalPlayer {
  final List<Map<String,Object>> calls=new ArrayList<>();
  ObservedPlayer(Minecraft mc,ClientLevel level,ClientPacketListener connection){super(mc,level,connection,new StatsCounter(),new ClientRecipeBook(),Input.EMPTY,false,ChatAbilities.NO_RESTRICTIONS,new ItemActivation());}
  void event(String method,Object...values){if(calls==null||!(level() instanceof TraceLevel t)||!t.capture)return;Map<String,Object> e=new TreeMap<>();e.put("method",method);e.put("body",body(this));for(int i=0;i<values.length;i+=2)e.put((String)values[i],values[i+1]);calls.add(e);t.add(e);}
  public void move(MoverType type,Vec3 movement){event("move_entry","mover",type.name(),"requested",movement==null?null:vector(movement));super.move(type,movement);event("move_exit");}
  protected Vec3 maybeBackOffFromEdge(Vec3 movement,MoverType type){event("maybeBackOffFromEdge_entry","movement",vector(movement),"mover",type.name());Vec3 result=super.maybeBackOffFromEdge(movement,type);event("maybeBackOffFromEdge_exit","movement",vector(movement),"result",vector(result),"same_instance",result==movement);return result;}
  public void recordMovement(MoverType type,Vec3 movement){event("recordMovement_entry","mover",type.name(),"movement",movement==null?null:vector(movement));super.recordMovement(type,movement);event("recordMovement_exit");}
  public void setOnGroundWithMovement(boolean ground,boolean horizontal,Vec3 movement){event("setOnGroundWithMovement_entry","grounded",ground,"horizontal",horizontal,"movement",movement==null?null:vector(movement));super.setOnGroundWithMovement(ground,horizontal,movement);event("setOnGroundWithMovement_exit");}
  protected void checkSupportingBlock(boolean ground,Vec3 movement){event("checkSupportingBlock_entry","grounded",ground,"movement",movement==null?null:vector(movement));super.checkSupportingBlock(ground,movement);event("checkSupportingBlock_exit");}
  protected boolean isHorizontalCollisionMinor(Vec3 movement){event("isHorizontalCollisionMinor_entry","movement",vector(movement),"yaw_f32_bits",bits(getYRot()),"input_f32_bits",List.of(bits(xxa),bits(yya),bits(zza)));boolean result=super.isHorizontalCollisionMinor(movement);event("isHorizontalCollisionMinor_exit","result",result);return result;}
  public void setDeltaMovement(Vec3 movement){event("setDeltaMovement_entry","movement",movement==null?null:vector(movement));super.setDeltaMovement(movement);event("setDeltaMovement_exit");}
  protected void checkFallDamage(double movement,boolean ground,BlockState block,BlockPos pos){event("checkFallDamage_entry","movement_f64_bits",bits(movement),"grounded",ground,"block_id",BuiltInRegistries.BLOCK.getKey(block.getBlock()).toString(),"position",LocalMoveWorldReceiverFixture.position(pos));super.checkFallDamage(movement,ground,block,pos);event("checkFallDamage_exit");}
  protected float getBlockSpeedFactor(){event("getBlockSpeedFactor_entry");float result=super.getBlockSpeedFactor();event("getBlockSpeedFactor_exit","result_f32_bits",bits(result));return result;}
  protected void addWalkedDistance(float movement){event("addWalkedDistance_entry","movement_f32_bits",bits(movement));super.addWalkedDistance(movement);event("addWalkedDistance_exit");}
 }
'''

RUN=r'''
 static Map<String,Object> moveState(LocalPlayer p)throws Exception{Map<String,Object> m=new TreeMap<>(state(p));m.put("no_physics",p.noPhysics);m.put("can_simulate",p.canSimulateMovement());m.put("local_authoritative",p.isLocalInstanceAuthoritative());m.put("suppressed_bounce",p.isSuppressingBounce());m.put("passenger",p.isPassenger());m.put("stuck_speed_multiplier",vector((Vec3)LocalInputReceiverFixture.read(p,"stuckSpeedMultiplier")));m.put("auto_jump_enabled",LocalInputReceiverFixture.read(p,"autoJumpEnabled"));m.put("move_dist_f32_bits",bits(p.moveDist));m.put("fly_dist_f32_bits",bits(p.flyDist));List<Map<String,Object>> movements=new ArrayList<>();for(Object movement:(Iterable<?>)LocalInputReceiverFixture.read(p,"movementThisTick")){Map<String,Object> r=new TreeMap<>();r.put("from",vector((Vec3)invoke(movement,movement.getClass(),"from",new Class<?>[]{})));r.put("to",vector((Vec3)invoke(movement,movement.getClass(),"to",new Class<?>[]{})));Optional<?> original=(Optional<?>)invoke(movement,movement.getClass(),"axisDependentOriginalMovement",new Class<?>[]{});r.put("axis_dependent_original_movement",original.isPresent()?vector((Vec3)original.get()):null);movements.add(r);}m.put("movement_this_tick",movements);return m;}
 static void writes(Context c,JsonArray changes){for(JsonElement e:changes){JsonObject w=e.getAsJsonObject();JsonArray p=w.getAsJsonArray("position");BlockState s=switch(w.get("block").getAsString()){case "air"->Blocks.AIR.defaultBlockState();case "stone"->Blocks.STONE.defaultBlockState();case "dirt"->Blocks.DIRT.defaultBlockState();case "oak_planks"->Blocks.OAK_PLANKS.defaultBlockState();default->throw new IllegalArgumentException("Non-fullcube move fixture block");};c.level.blocks.put(new BlockPos(p.get(0).getAsInt(),p.get(1).getAsInt(),p.get(2).getAsInt()),s);}}
 static Map<String,Object> context(LocalPlayer p)throws Exception{return Map.of("can_simulate",p.canSimulateMovement(),"local_authoritative",p.isLocalInstanceAuthoritative(),"no_physics",p.noPhysics,"passenger",p.isPassenger(),"flying",p.getAbilities().flying,"suppressed_bounce",p.isSuppressingBounce(),"block_speed_factor_f32_bits",bits((float)invoke(p,Entity.class,"getBlockSpeedFactor",new Class<?>[]{})),"maximum_f32_bits",bits(p.maxUpStep()),"shift",p.isShiftKeyDown(),"auto_jump_enabled",LocalInputReceiverFixture.read(p,"autoJumpEnabled"));}
 public static void run(String ignored)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();runtime();HolderLookup.Provider lookup=VanillaRegistries.createWorldLookup();JsonObject inputs=JsonParser.parseString(new String(Base64.getDecoder().decode(__INPUT_BASE64__),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonObject();
  for(JsonElement e:inputs.getAsJsonArray("cases")){JsonObject in=e.getAsJsonObject();for(boolean observed:List.of(false,true)){Context c=new Context(lookup,observed);configure(c,in.getAsJsonObject("initial"));LocalPlayer p=c.p;JsonObject initial=in.getAsJsonObject("initial");p.setDeltaMovement(vec(initial.getAsJsonArray("velocity")));p.horizontalCollision=initial.get("horizontal_collision").getAsBoolean();p.verticalCollision=initial.get("vertical_collision").getAsBoolean();p.verticalCollisionBelow=initial.get("vertical_collision_below").getAsBoolean();p.minorHorizontalCollision=initial.get("minor_horizontal_collision").getAsBoolean();List<Map<String,Object>> steps=new ArrayList<>();
   for(JsonElement se:in.getAsJsonArray("steps")){JsonObject step=se.getAsJsonObject();TraceLevel t=observed?(TraceLevel)c.level:null;if(observed)t.capture=false;writes(c,step.getAsJsonArray("world_writes"));if(step.has("shift"))p.input.keyPresses=new Input(false,false,false,false,false,step.get("shift").getAsBoolean(),false);if(step.has("velocity"))p.setDeltaMovement(vec(step.getAsJsonArray("velocity")));Map<String,Object> before=moveState(p),context=context(p);if(observed){t.clear();((ObservedPlayer)p).calls.clear();t.capture=true;}p.move(MoverType.valueOf(step.get("mover").getAsString()),vec(step.getAsJsonArray("requested")));if(observed)t.capture=false;Map<String,Object> row=new TreeMap<>();row.put("before",before);row.put("context",context);row.put("expected",moveState(p));row.put("events",observed?List.copyOf(t.events):List.of());steps.add(row);
   }emit(Map.of("id",in.get("id").getAsString(),"observed",observed,"steps",steps));
  }}
 }
}
'''

def derive_source():
    assert hashlib.sha256(LCW.SOURCE.encode()).hexdigest()==FROZEN_LCW_SOURCE
    s=LCW.SOURCE.replace('LocalCollisionWorldReceiverFixture','LocalMoveWorldReceiverFixture')
    a=s.index(' static class TraceLevel');b=s.index(' static class Context',a);s=s[:a]+OBSERVERS+s[b:]
    a=s.index(' public static void run(String ignored)');s=s[:a]+RUN
    return s.replace('LOCAL_COLLISION_WORLD_JSON:','LOCAL_MOVE_WORLD_JSON:').replace('LOCAL_COLLISION_WORLD_RUNTIME:','LOCAL_MOVE_WORLD_RUNTIME:')
SOURCE=derive_source()

def initial(**changes):
    v=LC.init(shift=True);v.update(velocity=[LC.db(.17),LC.db(-.08),LC.db(-.23)],horizontal_collision=False,vertical_collision=False,vertical_collision_below=False,minor_horizontal_collision=False);v.update(changes);return v

def step(requested,mover='SELF',writes=(),**changes):
    v={'requested':[LC.db(x) for x in requested],'mover':mover,'world_writes':list(writes)};v.update(changes);return v

def inputs():
    cases=[]
    def add(name,moves,**changes):
        cases.append({'id':name,'initial':initial(**changes),'steps':moves})
    def blocks(items):return [{'position':p,'block':b} for p,b in items]
    add('floor',[step((.2,-.08,.1))])
    add('held_shift_edge',[step((.5,-.08,0)) for _ in range(3)],position=[LC.db(2.6),LC.db(1),LC.db(.5)])
    add('airborne',[step((.2,-.08,.1))],position=[LC.db(.5),LC.db(3),LC.db(.5)],grounded=False)
    wall=blocks([([1,1,0],'stone'),([1,2,0],'stone')])
    add('wall',[step((.7,-.08,.2))],world_writes=wall)
    for name,motion in [('zero',(0.,0.,0.)),('signed_zero',(-0.,-0.,-0.)),('floor_tiny',(.0,-.0001,.0)),('floor_gate_skip',(.0,-.0004,.0)),('floor_threshold',(.0,-math.sqrt(1e-7),.0)),('floor_up',(.0,.0004,.0))]:
        add(name,[step(motion)],main_support=[0,0,0],minor_horizontal_collision=True)
    for name,motion in [('x_tiny',(.0001,0,0)),('x_gate_skip',(.0004,0,0)),('xz',(.7,-.08,.7)),('dominant_z',(.2,-.08,.7))]:
        writes=wall+blocks([([0,1,1],'dirt'),([0,2,1],'oak_planks')])
        add('wall_'+name,[step(motion)],position=[LC.db(.7),LC.db(1),LC.db(.5)],world_writes=writes)
    for yaw,input in [(0,(0,0,1)),(90,(0,0,1)),(45,(1,0,1)),(17,(.1,0,1)),(-8,(0,0,1)),(0,(0,0,0))]:
        add('minor_'+str(yaw)+'_'+str(input),[step((.2,-.08,.7))],world_writes=blocks([([0,1,1],'stone'),([0,2,1],'stone')]),yaw_f32_bits=LC.fb(yaw),input_f32_bits=[LC.fb(v) for v in input])
    for flag in [False,True]:
        for main in [None,[7,0,-3]]:
            add('fallback_'+str(flag)+'_'+str(main),[step((.6,-1.08,0))],position=[LC.db(2.8),LC.db(2),LC.db(.5)],grounded=False,on_ground_no_blocks=flag,main_support=main)
    add('seam_corner',[step((.0,-.08,.0))],position=[LC.db(1),LC.db(1),LC.db(1)],world_writes=blocks([([0,0,0],'dirt'),([1,0,0],'oak_planks'),([0,0,1],'oak_planks')]))
    for axis,pos,motion in [('x+',(2.8,1,.5),(.7,-.08,0)),('x-',(-1.8,1,.5),(-.7,-.08,0)),('z+',(.5,1,2.8),(0,-.08,.7)),('z-',(.5,1,-1.8),(0,-.08,-.7)),('corner+',(2.8,1,2.8),(.7,-.08,.7)),('corner-',(-1.8,1,-1.8),(-.7,-.08,-.7))]:
        add('edge_'+axis,[step(motion)],position=[LC.db(v) for v in pos])
    for block in ['stone','dirt','oak_planks']:
        cube=blocks([([1,1,0],block)])
        for height in [.6,1.,1.1]:
            add('step_'+block+'_'+str(height),[step((.7,-.08,0))],world_writes=cube,step_attribute_f64_bits=LC.db(height))
    add('partial_step',[step((.7,0,0))],position=[LC.db(.5),LC.db(1.4),LC.db(.5)],world_writes=blocks([([1,1,0],'stone')]))
    add('step_low_ceiling',[step((.7,-.08,0))],world_writes=blocks([([1,1,0],'stone'),([0,3,0],'oak_planks'),([1,3,0],'oak_planks')]),step_attribute_f64_bits=LC.db(1.1))
    add('air_landing',[step((.2,-.35,.1)) for _ in range(3)],position=[LC.db(.5),LC.db(2),LC.db(.5)],grounded=False)
    add('air_edge_landing',[step((.3,-.4,0)) for _ in range(3)],position=[LC.db(2.6),LC.db(2),LC.db(.5)],grounded=False)
    for palette in ['stone','dirt','oak_planks','air']:
        writes=blocks([([x,0,z],palette) for x in range(-2,3) for z in range(-2,3)])
        add('palette_'+palette,[step((.2,-.08,.1))],world_writes=writes)
    add('dynamic_floor',[step((0,-.08,0),writes=blocks([([0,0,0],b)])) for b in ['dirt','oak_planks','air','stone']],main_support=[0,0,0])
    add('held_floor',[step((.12,-.08,.07)) for _ in range(4)])
    add('held_wall',[step((.3,-.08,.1)) for _ in range(3)],world_writes=wall)
    for name,velocity in [('positive_zero',(0.,0.,0.)),('negative_zero',(-0.,-0.,-0.)),('positive_vertical',(-.17,.08,.23)),('subnormal',(5e-324,5e-324,-5e-324))]:
        raw=[LC.db(v) for v in velocity]
        add('velocity_floor_'+name,[step((.2,-.08,.1))],velocity=raw)
        add('velocity_wall_'+name,[step((.7,-.08,.2))],velocity=raw,world_writes=wall)
    add('player_mover',[step((.2,-.08,.1),mover='PLAYER')])
    add('unshift_guard',[step((.2,-.08,.1),shift=False)])
    return {'cases':cases},[{'scope':'Excluded by corpus policy','reason':'Nonfinite/giant queries, noPhysics/passenger/flying, arbitrary missing/partial query policies and slab shapes are not represented as complete neutral actual oracle cases.'}]

def dependencies():
    assert fingerprint(LCW.OUTPUT)['sha256']==FROZEN_LCW_REFERENCE
    return {'lcw_producer':fingerprint(Path(LCW.__file__)),'lcw_reference':fingerprint(LCW.OUTPUT),'lcw_source_sha256':hashlib.sha256(LCW.SOURCE.encode()).hexdigest(),'frozen_lc_li_dependencies':LCW.dependencies()}

def runtime_files():
    result={}
    for name,relative in [('jrt_modules','lib/modules'),('jvm_library','lib/server/libjvm.dylib'),('release','release')]:
        p=JAVA.parent.parent/relative;one=hashlib.sha1();two=hashlib.sha256()
        with p.open('rb') as stream:
            for chunk in iter(lambda:stream.read(1024*1024),b''):one.update(chunk);two.update(chunk)
        result[name]={'file':p.name,'bytes':p.stat().st_size,'sha1':one.hexdigest(),'sha256':two.hexdigest()}
    return result

def sources(cases):
    s=LC.LI.receiver_sources();s[CLASS]=SOURCE.replace('__INPUT_BASE64__',LC.LI.java_string(base64.b64encode(canonical(cases)).decode()));return s

def collect(cases,rows):
    result=[]
    for case in cases['cases']:
        actual=[r for r in rows if r['id']==case['id']];assert len(actual)==2
        plain=next(r for r in actual if not r['observed']);observed=next(r for r in actual if r['observed'])
        assert [{k:v for k,v in s.items() if k!='events'} for s in plain['steps']]==[{k:v for k,v in s.items() if k!='events'} for s in observed['steps']],case['id']+' observer parity'
        out=copy.deepcopy(case);out['plain_observer_parity']=True;out['steps']=[]
        for request,row in zip(case['steps'],observed['steps']):
            events=row['events'];queries=[]
            for entry in [e for e in events if e['method'] in ('noCollision_entry','blockCollisions_entry','entityCollisions_entry','support_entry')]:
                q=entry['query'];same=[e for e in events if e.get('query')==q];method=entry['method'][:-6];exit=next(e for e in same if e['method']==method+'_exit');reads=[{k:e[k] for k in ('ordinal','position','block_id','state_id','state_name')} for e in same if e['method']=='getBlockState'];assert [r['ordinal'] for r in reads]==list(range(len(reads)))
                item={'index':q,'method':method,'parent_query':entry['parent_query'],'entry_sequence':entry['sequence'],'exit_sequence':exit['sequence'],'box':entry['box'],'reads':reads,'yielded_shapes':[e['boxes'] for e in same if e['method']=='actual_block_collision_shape_yield']}
                for k in ('result','selected','shapes'):
                    if k in exit:item[k]=exit[k]
                queries.append(item)
            calls=[e for e in events if 'body' in e];one=lambda method:next((e for e in calls if e['method']==method),None)
            backoff=one('maybeBackOffFromEdge_exit');support=one('checkSupportingBlock_entry');support_after=one('checkSupportingBlock_exit');minor=one('isHorizontalCollisionMinor_entry');ground=one('setOnGroundWithMovement_entry')
            assert backoff and support and support_after and ground
            neutral=row['context']['can_simulate'] and row['context']['local_authoritative'] and not row['context']['no_physics'] and not row['context']['passenger'] and not row['context']['flying'] and row['context']['suppressed_bounce'] and row['context']['block_speed_factor_f32_bits']==LC.fb(1.)
            out['steps'].append({**request,'before':row['before'],'context':row['context'],'expected':row['expected'],'admission':{'neutral_context':neutral,'finite_complete_actual':True},'actual_requested':one('move_entry')['requested'],'corrected_requested':backoff['result'],'resolved':ground['movement'],'before_support':support['body'],'after_support':support_after['body'],'before_minor':None if minor is None else minor['body'],'minor_called':minor is not None,'position_application_gate_entered':one('recordMovement_entry') is not None,'queries':queries,'player_calls':calls,'sample_reads':[{k:e[k] for k in ('sequence','ordinal','position','block_id','state_id','state_name')} for e in events if e['method']=='getBlockState' and e['query']==-1],'phase_order':[e['method'] for e in events if e['method']!='getBlockState']})
        result.append(out)
    return result

def boundary():
    return {'decisive':'Untouched full actual LocalPlayer.move dispatches inherited movement, backoff, private collide, position gate, flags, actual support, actual minor, fall, restitution and speed factor; whole actual return determines final state.','observer':'All movement/player/Level observers call super. Plain normal LocalPlayer/frozen finite ClientLevel projected state/context match observed receiver. Block iterator hasNext/next order preserved; every state read and shape is observed from the actual iterator.','fixture':'Frozen four explicit LI external services and normal real ClientLevel/LocalPlayer constructors. Finite 25-stone floor otherwise air plus sequential AIR/STONE/DIRT/OAK_PLANKS writes. Empty actors/default real border.','neutral':'Actual canSimulate/local authority/noPhysics/passenger/flying/shift/suppressed bounce/block speed/maxStep sampled. Neutral requires shift=true actual suppression and speed1; no arbitrary suppression or simulation override.','outside_projection':'Actual autoJumpEnabled=false context remains in state; actual LocalPlayer.updateAutoJump and addWalkedDistance execute. Actual fallDistance/Entity.Movement/emission changes are observed; this oracle does not supply the separate fall-history Bend projection.','scope':'Bounded finite complete fullcube movement observations only; no missing synthetic collision list or general world/tick parity claim.'}

def counts(cases):
    steps=[s for c in cases for s in c['steps']];queries=[q for s in steps for q in s['queries']]
    return {'cases':len(cases),'steps':len(steps),'neutral_steps':sum(s['admission']['neutral_context'] for s in steps),'queries':len(queries),'reads':sum(len(q['reads']) for q in queries),'yielded_shapes':sum(len(q['yielded_shapes']) for q in queries),'query_methods':{m:sum(q['method']==m for q in queries) for m in sorted({q['method'] for q in queries})}}

def source_inventory():
    result=LCW.source_inventory()
    wanted={'Cursor3D','advance','getNextType','nextX','nextY','nextZ','intersects','floor','hasLargeCollisionShape','getCollisionShape','getId','findSupportingBlock','computeNext','Vec3','move','recordMovement','checkSupportingBlock','setOnGroundWithMovement','collide','collectCollidersIgnoringWorldBorder','collideBoundingBox','collideWithShapes','collectCandidateStepUpHeights','getBlockSpeedFactor','restituteMovementAfterCollisions','checkFallDamage','setDeltaMovement','updateAutoJump','addWalkedDistance','applyMovementEmissionAndPlaySound'}
    with zipfile.ZipFile(CLIENT) as jar:
        for owner in ['net.minecraft.world.phys.Vec3','net.minecraft.world.entity.Entity','net.minecraft.world.entity.player.Player','net.minecraft.client.player.LocalPlayer','net.minecraft.client.player.AbstractClientPlayer','net.minecraft.world.entity.LivingEntity','net.minecraft.world.level.CollisionGetter','net.minecraft.world.level.BlockCollisions','net.minecraft.core.Cursor3D','net.minecraft.world.phys.AABB','net.minecraft.util.Mth','net.minecraft.world.level.block.state.BlockBehaviour$BlockStateBase','net.minecraft.world.level.block.Block']:
            s=subprocess.run([str(JAVA.parent/'javap'),'-classpath',str(CLIENT),'-c','-p',owner],capture_output=True,text=True,check=True).stdout
            methods=[]
            for sig,body in re.findall(r'^  ((?:public|protected|private|static)[^\n]*?\([^\n]*\);)\n(.*?)(?=^  (?:public|protected|private|static)|\Z)',s,re.M|re.S):
                name=re.search(r'([\w$<>]+)\([^\n]*\);$',sig)
                if name and name[1] in wanted:methods.append({'signature':sig,'bytecode_text_sha256':hashlib.sha256(body.encode()).hexdigest(),'direct_call_references':sorted(set(re.findall(r'// (?:InterfaceMethod|Method) (.+)',body))),'field_references':sorted(set(re.findall(r'// Field (.+)',body)))})
            entry=owner.replace('.','/')+'.class';prior=result.get(owner,{}).get('methods',[])
            existing={m['signature'] for m in methods};methods+= [m for m in prior if m['signature'] not in existing]
            result[owner]={'class_entry':entry,'class_sha256':hashlib.sha256(jar.read(entry)).hexdigest(),'complete_bytecode_text_sha256':hashlib.sha256(s.encode()).hexdigest(),'methods':methods}
    return result

def compact_report(path,e):
    assert sha(e['observations'])==e['observations_sha256']
    raw=RAW/f'{path.stem}.full.json';save(raw,e)
    report={k:v for k,v in e.items() if k not in ('observations','raw_execution','source','provenance','execution','substituted_external_types')}
    report.update(evidence_format='local-move-world-summary-v1',raw_report={'path':str(raw.relative_to(ROOT)),**fingerprint(raw)},storage_writer=fingerprint(Path(__file__)),observation_count=len(e['observations']))
    report['source_inventory']={'canonical_sha256':sha(e['source']),'classes':{n:v['class_sha256'] for n,v in e['source'].items()},'methods_sha256':{n:sha(v['methods']) for n,v in e['source'].items()}}
    p=e['provenance'];report['provenance']={k:v for k,v in p.items() if k not in ('libraries','missing_other_platform_natives')};report['provenance_sha256']=sha(p)
    for key in ('libraries','missing_other_platform_natives'):report['provenance'][key+'_count']=len(p[key]);report['provenance'][key+'_sha256']=sha(p[key])
    report['substituted_external_types']={n:{'source_sha256':v['source_sha256']} for n,v in e['substituted_external_types'].items()}
    execution=copy.deepcopy(e['execution']);execution['command_sha256']=sha(execution['command']);i=execution['command'].index('--class-path')+1;execution['classpath_sha256']=hashlib.sha256(execution['command'][i].encode()).hexdigest();execution['command'][i]='<verified pinned classpath; complete command in raw_report>'
    if execution['returncode']==0:execution.pop('failure',None);execution.pop('stderr_tail',None)
    report['execution']=execution;save(path,report);verify_report(path);return report

def verify_report(path):
    s=json.loads(path.read_text());raw=ROOT/s['raw_report']['path'];assert fingerprint(raw)=={k:v for k,v in s['raw_report'].items() if k!='path'};e=json.loads(raw.read_text())
    assert sha(e['observations'])==e['observations_sha256']==s['observations_sha256'];assert len(e['observations'])==s['observation_count'];assert sha(e['source'])==s['source_inventory']['canonical_sha256'];assert sha(e['provenance'])==s['provenance_sha256']
    actual=e['raw_execution']['loaded_official_classes'];assert sha(actual)==s['loaded_official_class_tree_sha256'];assert len(actual)==s['loaded_official_class_count']
    for stream in ('stdout','stderr'):assert hashlib.sha256(e['raw_execution'][stream].encode()).hexdigest()==s['execution'][stream+'_sha256']
    assert sha(e['execution']['command'])==s['execution']['command_sha256'];return s

def run(cases,label):
    dep=dependencies();classpath,prov=verified_client_classpath();ss=sources(cases);payload={'sources':ss,'client_jar':str(CLIENT),'mode':'move_world'};encoded=base64.b64encode(canonical(payload)).decode()
    launcher=LC.LI.RECEIVER_LAUNCHER.replace('net.minecraft.fixture.LocalInputReceiverFixture',CLASS).replace('Base64.getDecoder().decode(args[0])','Base64.getDecoder().decode('+LC.LI.java_string(encoded)+')',1)
    command=[str(JAVA),'--source','25','--class-path',':'.join(map(str,classpath)),'/dev/stdin'];start=time.monotonic();p=subprocess.run(command,input=launcher,capture_output=True,text=True)
    def parse(prefix):return [json.loads(s[len(prefix):]) for s in p.stdout.splitlines() if s.startswith(prefix)]
    rows=parse('LOCAL_MOVE_WORLD_JSON:');loaded=parse('LOCAL_INPUT_CLASSES:');runtime=parse('LOCAL_MOVE_WORLD_RUNTIME:');inventory=source_inventory()
    assert p.returncode==0,'Actual fixture failure: '+'\n'.join(x for x in p.stdout.splitlines() if not x.startswith('LOCAL_INPUT_CLASSES:'))[-7000:]+p.stderr[-2000:]
    assert len(loaded)==len(runtime)==1
    for n,h in loaded[0].items():
        if n in inventory and not n.startswith('java.'):assert h==inventory[n]['class_sha256']
    for n,h in runtime[0].items():inventory[n]['class_sha256']=h
    projected=collect(cases,rows)
    e={'schema_version':1,'pin':'26.3','status':'passed','producer_at_execution':fingerprint(Path(__file__)),'dependency':dep,'provenance':prov,'runtime_files':runtime_files(),'source':inventory,'boundary':boundary(),
       'source_sha256':hashlib.sha256(SOURCE.encode()).hexdigest(),'expanded_source_sha256':{n:hashlib.sha256(s.encode()).hexdigest() for n,s in ss.items()},'launcher_sha256':hashlib.sha256(LC.LI.RECEIVER_LAUNCHER.encode()).hexdigest(),
       'substituted_external_types':{n:{'source':s,'source_sha256':hashlib.sha256(s.encode()).hexdigest()} for n,s in LC.LI.RECEIVER_SOURCES.items() if n!='net.minecraft.fixture.LocalInputReceiverFixture'},
       'loaded_official_classes':{n:h for n,h in loaded[0].items() if n in inventory},'loaded_official_class_count':len(loaded[0]),'loaded_official_class_tree_sha256':sha(loaded[0]),'runtime_classes':runtime[0],
       'observations':rows,'observations_sha256':sha(rows),'counts':counts(projected),'plain_observer_projected_parity':True,'whole_move_projection':True,
       'execution':{'command':command,'reproduce':'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_move_world_probe.py --'+('rerun' if label=='independent' else 'debug' if label=='debug' else 'extract'),'seconds':round(time.monotonic()-start,6),'returncode':p.returncode,'input_sha256':sha(payload),'compiled_launcher_sha256':hashlib.sha256(launcher.encode()).hexdigest(),'stdout_sha256':hashlib.sha256(p.stdout.encode()).hexdigest(),'stderr_sha256':hashlib.sha256(p.stderr.encode()).hexdigest(),'stderr_tail':p.stderr[-3000:]},
       'raw_execution':{'stdout':p.stdout,'stderr':p.stderr,'loaded_official_classes':loaded[0]}}
    path=ROOT/f'evidence/local-move-world-reference-{label}.json';compact_report(path,e);return projected,e,path

def extract(debug=False):
    cases,excluded=inputs()
    if debug:cases['cases']=cases['cases'][:2]
    projected,e,path=run(cases,'debug' if debug else 'actual')
    if debug:return {'status':'passed','evidence':fingerprint(path),'counts':e['counts']}
    d={k:e[k] for k in ('schema_version','pin','dependency','provenance','runtime_files','source','boundary','source_sha256','expanded_source_sha256','launcher_sha256','loaded_official_classes','loaded_official_class_count','loaded_official_class_tree_sha256','runtime_classes')}
    d.update(inputs_sha256=sha(cases),cases=projected,excluded_cases=excluded,counts=e['counts'],observations_sha256=sha(projected));save(OUTPUT,d)
    return {'status':'passed','reference':fingerprint(OUTPUT),'counts':e['counts'],'excluded_cases':excluded,'evidence':fingerprint(path)}

def verify_data(d,prov,inventory):
    cases,excluded=inputs();assert d['pin']=='26.3' and d['schema_version']==1;assert d['inputs_sha256']==sha(cases);assert d['excluded_cases']==excluded;assert d['source_sha256']==hashlib.sha256(SOURCE.encode()).hexdigest();assert d['expanded_source_sha256']=={n:hashlib.sha256(s.encode()).hexdigest() for n,s in sources(cases).items()};assert d['launcher_sha256']==hashlib.sha256(LC.LI.RECEIVER_LAUNCHER.encode()).hexdigest();assert d['dependency']==dependencies();assert d['provenance']==prov;assert d['runtime_files']==runtime_files()
    r=LC.runtime_inventory();assert d['runtime_classes']==r
    for n,h in r.items():inventory[n]['class_sha256']=h
    assert d['source']==inventory;assert d['boundary']==boundary();assert d['observations_sha256']==sha(d['cases']);assert d['counts']==counts(d['cases'])
    for n,h in d['loaded_official_classes'].items():assert inventory[n]['class_sha256']==h

def verify(selftest=False):
    d=json.loads(OUTPUT.read_text());_,prov=verified_client_classpath();inv=source_inventory();verify_data(d,prov,inv);result={'status':'passed','producer':fingerprint(Path(__file__)),'reference':fingerprint(OUTPUT),'counts':d['counts'],'scope':'Integrity/provenance only; no new actual full move run'}
    if selftest:
        checks=[]
        for label,path in [('client',['provenance','client','sha256']),('runtime',['provenance','java','sha256']),('library',['provenance','libraries',0,'sha256']),('runtime_modules',['runtime_files','jrt_modules','sha256']),('source',['source_sha256']),('read',['cases',0,'steps',0,'queries',0,'reads',0,'state_id'])]:
            v=copy.deepcopy(d);o=v
            for k in path[:-1]:o=o[k]
            o[path[-1]]='injected-mismatch'
            try:verify_data(v,prov,inv)
            except AssertionError:checks.append({'injection':label,'rejected':True})
            else:raise AssertionError('Injection accepted: '+label)
        result['failure_injections']=checks
    save(ROOT/'evidence/local-move-world-reference-integrity.json',result);return result

def rerun():
    d=json.loads(OUTPUT.read_text());_,p=verified_client_classpath();verify_data(d,p,source_inventory());cases,_=inputs();projected,e,path=run(cases,'independent');assert projected==d['cases'];assert e['loaded_official_class_tree_sha256']==d['loaded_official_class_tree_sha256'];assert e['runtime_classes']==d['runtime_classes'];assert e['runtime_files']==d['runtime_files'];e['independent_actual_observation_parity']=True;e['reference_compared']=fingerprint(OUTPUT);compact_report(path,e);return {'status':'passed','reference':fingerprint(OUTPUT),'evidence':fingerprint(path),'independent_actual_observation_parity':True}

def main():
    p=argparse.ArgumentParser();p.add_argument('--extract',action='store_true');p.add_argument('--debug',action='store_true');p.add_argument('--verify-existing',action='store_true');p.add_argument('--selftest',action='store_true');p.add_argument('--rerun',action='store_true');a=p.parse_args()
    if a.verify_existing or a.selftest:r=verify(a.selftest)
    elif a.rerun:r=rerun()
    elif a.extract or a.debug:r=extract(a.debug)
    else:p.error('Select --extract, --verify-existing, --selftest or --rerun')
    print(json.dumps(r,indent=2))
if __name__=='__main__':main()
