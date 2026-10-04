#!/usr/bin/env python3
"""Fresh untouched LocalPlayer.travel with actual preparation/move/history/finish.

Normal constructors, frozen four services and original official class bytes.
Loaded chunk availability is supplied by normal real LevelChunk objects inserted
through actual ClientChunkCache.Storage methods, never a hasChunkAt override.
"""
from __future__ import annotations
import argparse,base64,copy,hashlib,json,math,os,re,signal,subprocess,time,zipfile
from pathlib import Path
from reference_inventory import ROOT,JAVA,canonical,fingerprint
from reference_model_probe import CLIENT,verified_client_classpath
import reference_local_move_history_probe as MH
LM=MH.LM
LC=LM.LC
OUTPUT=ROOT/'reference/local_travel_history.json'
RAW=ROOT/'build/local-travel-history-reference'
CLASS='net.minecraft.fixture.LocalTravelHistoryReceiverFixture'
FROZEN_MH_SOURCE='b92c482b956f95e81704f2f0f3f0ca590a0a64103817ff325f57804024079569'
FROZEN_MH_REFERENCE='2b510ed3c932d830ed0481343ac4508cfea9e9e98dfcb7856dd2d1ce191f2f95'

def sha(v):return hashlib.sha256(canonical(v)).hexdigest()
def save(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(canonical(v)+b'\n')

HOOKS=r'''
  public void travel(Vec3 input){event("travel_entry","input",vector(input),"attributes",attributes(this));super.travel(input);event("travel_exit","attributes",attributes(this));}
  public void moveRelative(float acceleration,Vec3 input){event("moveRelative_entry","acceleration_f32_bits",bits(acceleration),"input",vector(input));super.moveRelative(acceleration,input);event("moveRelative_exit");}
  public float getSpeed(){float result=super.getSpeed();event("getSpeed_exit","result_f32_bits",bits(result),"movement_speed_f64_bits",bits(getAttributeValue(Attributes.MOVEMENT_SPEED)));return result;}
  protected float getFlyingSpeed(){float result=super.getFlyingSpeed();event("getFlyingSpeed_exit","result_f32_bits",bits(result),"sprinting",isSprinting(),"flying",getAbilities().flying);return result;}
  public BlockPos getBlockPosBelowThatAffectsMyMovement(){BlockPos result=super.getBlockPosBelowThatAffectsMyMovement();event("getBlockPosBelowThatAffectsMyMovement_exit","position",LocalTravelHistoryReceiverFixture.position(result));return result;}
  protected double getEffectiveGravity(){double result=super.getEffectiveGravity();event("getEffectiveGravity_exit","result_f64_bits",bits(result));return result;}
  public void setDeltaMovement(double x,double y,double z){event("setDeltaMovementDDD_entry","movement",vector(new Vec3(x,y,z)));super.setDeltaMovement(x,y,z);event("setDeltaMovementDDD_exit");}
'''

EXTRA=r'''
 static void travelSetup(LocalPlayer p,JsonObject in)throws Exception{for(String name:List.of("movement_speed","gravity","friction_modifier","air_drag_modifier"))if(in.has(name+"_f64_bits")){var attribute=switch(name){case "movement_speed"->Attributes.MOVEMENT_SPEED;case "gravity"->Attributes.GRAVITY;case "friction_modifier"->Attributes.FRICTION_MODIFIER;default->Attributes.AIR_DRAG_MODIFIER;};p.getAttribute(attribute).setBaseValue(d(in.get(name+"_f64_bits")));}if(in.has("no_gravity"))p.setNoGravity(in.get("no_gravity").getAsBoolean());if(in.has("discard_friction"))p.setDiscardFriction(in.get("discard_friction").getAsBoolean());if(in.has("input_f32_bits")){JsonArray inputs=in.getAsJsonArray("input_f32_bits");p.xxa=f(inputs.get(0));p.yya=f(inputs.get(1));p.zza=f(inputs.get(2));}if(in.has("yaw_f32_bits"))p.setYRot(f(in.get("yaw_f32_bits")));if(in.has("crouching"))LocalInputReceiverFixture.seed(p,"crouching",in.get("crouching").getAsBoolean());if(in.has("pose"))p.setPose(Pose.valueOf(in.get("pose").getAsString()));}
 static Map<String,Object> snapshot(LocalPlayer p){TraceLevel t=p.level() instanceof TraceLevel trace?trace:null;boolean old=t!=null&&t.capture;if(t!=null)t.capture=false;try{return moveState(p);}catch(Exception e){throw new RuntimeException(e);}finally{if(t!=null)t.capture=old;}}
 static Map<String,Object> attributes(LocalPlayer p){Map<String,Object> m=new TreeMap<>();m.put("movement_speed_f64_bits",bits(p.getAttributeValue(Attributes.MOVEMENT_SPEED)));m.put("gravity_f64_bits",bits(p.getAttributeValue(Attributes.GRAVITY)));m.put("friction_modifier_f64_bits",bits(p.getAttributeValue(Attributes.FRICTION_MODIFIER)));m.put("air_drag_modifier_f64_bits",bits(p.getAttributeValue(Attributes.AIR_DRAG_MODIFIER)));m.put("step_f64_bits",bits(p.getAttributeValue(Attributes.STEP_HEIGHT)));m.put("maximum_f32_bits",bits(p.maxUpStep()));m.put("sprinting",p.isSprinting());m.put("no_gravity",p.isNoGravity());return m;}
 static List<Map<String,Object>> installChunks(Context c,boolean loaded)throws Exception{List<Map<String,Object>> result=new ArrayList<>();if(!loaded)return result;Object cache=c.level.getChunkSource(),storage=LocalInputReceiverFixture.read(cache,"storage");for(int x=-1;x<=1;x++)for(int z=-1;z<=1;z++){net.minecraft.world.level.chunk.LevelChunk chunk=new net.minecraft.world.level.chunk.LevelChunk(c.level,new net.minecraft.world.level.ChunkPos(x,z));int index=(int)invoke(storage,storage.getClass(),"getIndex",new Class<?>[]{int.class,int.class},x,z);invoke(storage,storage.getClass(),"replace",new Class<?>[]{int.class,net.minecraft.world.level.chunk.LevelChunk.class},index,chunk);List<Map<String,Object>> sections=new ArrayList<>();for(var section:chunk.getSections())sections.add(Map.of("has_only_air",section.hasOnlyAir(),"sample_state_id",Block.getId(section.getBlockState(0,0,0)),"sample_fluid_empty",section.getFluidState(0,0,0).isEmpty()));result.add(Map.of("slot",index,"chunk",List.of(chunk.getPos().x(),chunk.getPos().z()),"sections",sections,"actual_cache_identity",c.level.getChunkSource().getChunk(x,z,net.minecraft.world.level.chunk.status.ChunkStatus.FULL,false)==chunk,"actual_has_chunk_at",c.level.hasChunkAt(new BlockPos(x*16,0,z*16))));}return result;}
 static Map<String,Object> travelContext(LocalPlayer p)throws Exception{Map<String,Object> m=new TreeMap<>(context(p));m.put("attributes",attributes(p));m.put("gravity_getter_f64_bits",bits(p.getGravity()));m.put("input_f32_bits",List.of(bits(p.xxa),bits(p.yya),bits(p.zza)));m.put("crouching",p.isCrouching());m.put("pose",p.getPose().name());m.put("in_water",p.isInWater());m.put("in_lava",p.isInLava());m.put("swimming",p.isSwimming());m.put("fall_flying",p.isFallFlying());m.put("on_climbable",p.onClimbable());m.put("discard_friction",invoke(p,LivingEntity.class,"shouldDiscardFriction",new Class<?>[]{}));m.put("omnidirectional_air_mover",invoke(p,Entity.class,"omnidirectionalAirMover",new Class<?>[]{}));m.put("levitation",p.hasEffect(net.minecraft.world.effect.MobEffects.LEVITATION));m.put("slow_falling",p.hasEffect(net.minecraft.world.effect.MobEffects.SLOW_FALLING));BlockPos below=p.getBlockPosBelowThatAffectsMyMovement();BlockState state=p.level().getBlockState(below);m.put("ground_sample",Map.of("position",position(below),"friction_f32_bits",bits(state.getBlock().getFriction()),"block_id",BuiltInRegistries.BLOCK.getKey(state.getBlock()).toString(),"state_id",Block.getId(state)));m.put("modified_ground_friction_helper_f32_bits",bits((float)invoke(null,LivingEntity.class,"computeModifiedFriction",new Class<?>[]{float.class,float.class},state.getBlock().getFriction(),(float)p.getAttributeValue(Attributes.FRICTION_MODIFIER))));m.put("friction_helper_scope","Direct actual computeModifiedFriction supporting helper observation; not a captured production local. Airborne friction is separately the audited travelInAir fconst_1 operand.");m.put("actual_has_chunk_at_ground_sample",p.level().hasChunkAt(below));m.put("current_fluid_empty",p.level().getFluidState(p.blockPosition()).isEmpty());return m;}
 public static void run(String ignored)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();runtime();HolderLookup.Provider lookup=VanillaRegistries.createWorldLookup();JsonObject inputs=JsonParser.parseString(new String(Base64.getDecoder().decode(__INPUT_BASE64__),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonObject();
  for(JsonElement e:inputs.getAsJsonArray("cases")){JsonObject in=e.getAsJsonObject();for(boolean observed:List.of(false,true)){Context c=new Context(lookup,observed);TraceLevel t=observed?(TraceLevel)c.level:null;configure(c,in.getAsJsonObject("initial"));if(observed)t.capture=false;LocalPlayer p=c.p;JsonObject initial=in.getAsJsonObject("initial");travelSetup(p,initial);p.setDeltaMovement(vec(initial.getAsJsonArray("velocity")));p.horizontalCollision=initial.get("horizontal_collision").getAsBoolean();p.verticalCollision=initial.get("vertical_collision").getAsBoolean();p.verticalCollisionBelow=initial.get("vertical_collision_below").getAsBoolean();p.minorHorizontalCollision=initial.get("minor_horizontal_collision").getAsBoolean();p.setSprinting(initial.get("sprinting").getAsBoolean());List<Map<String,Object>> installed=installChunks(c,initial.get("loaded_chunks").getAsBoolean());List<Map<String,Object>> steps=new ArrayList<>();
   for(JsonElement se:in.getAsJsonArray("steps")){JsonObject step=se.getAsJsonObject();if(observed)t.capture=false;writes(c,step.getAsJsonArray("world_writes"));travelSetup(p,step);if(step.has("shift"))p.input.keyPresses=new Input(false,false,false,false,false,step.get("shift").getAsBoolean(),false);if(step.has("velocity"))p.setDeltaMovement(vec(step.getAsJsonArray("velocity")));if(step.has("sprinting"))p.setSprinting(step.get("sprinting").getAsBoolean());Map<String,Object> before=moveState(p),context=travelContext(p);if(observed){t.clear();((ObservedPlayer)p).calls.clear();t.capture=true;}Map<String,Object> row=new TreeMap<>();try{p.travel(vec(step.getAsJsonArray("travel_input")));row.put("actual_returned",true);}catch(Throwable error){Throwable root=error;while(root.getCause()!=null)root=root.getCause();row.put("actual_returned",false);row.put("error_class",root.getClass().getName());row.put("error_message",String.valueOf(root.getMessage()));}if(observed)t.capture=false;row.put("before",before);row.put("context",context);row.put("expected",moveState(p));row.put("events",observed?List.copyOf(t.events):List.of());steps.add(row);
   }emit(Map.of("id",in.get("id").getAsString(),"observed",observed,"installed_chunks",installed,"steps",steps));
  }}
 }
}
'''

def derive_source():
    assert hashlib.sha256(MH.SOURCE.encode()).hexdigest()==FROZEN_MH_SOURCE
    s=MH.SOURCE.replace('LocalMoveHistoryReceiverFixture','LocalTravelHistoryReceiverFixture').replace('LOCAL_MOVE_HISTORY_','LOCAL_TRAVEL_HISTORY_')
    n='  public void resetFallDistance()';assert s.count(n)==1;s=s.replace(n,HOOKS+n,1)
    n='  public boolean noCollision(Entity p,AABB b)';assert s.count(n)==1;s=s.replace(n,'  public boolean hasChunkAt(BlockPos p){boolean result=super.hasChunkAt(p);add(Map.of("method","hasChunkAt","position",position(p),"result",result));return result;}\n'+n,1)
    n='e.put("state_name",b.toString());';assert s.count(n)==1;s=s.replace(n,n+'e.put("friction_f32_bits",bits(b.getBlock().getFriction()));',1)
    n='e.put("body",body(this));';assert s.count(n)==1;s=s.replace(n,n+'if(method.equals("travel_entry")||method.equals("travel_exit")||method.equals("move_entry")||method.equals("move_exit")||method.equals("moveRelative_entry")||method.equals("moveRelative_exit"))e.put("state",snapshot(this));',1)
    a=s.index(' public static void run(String ignored)');s=s[:a]+EXTRA
    return s
SOURCE=derive_source()

def initial(**changes):
    v=LM.initial(sprinting=False,loaded_chunks=True,no_gravity=False,discard_friction=False);v.update(changes);return v

def step(input,**changes):
    v={'travel_input':[LC.db(x) for x in input],'world_writes':[]};v.update(changes);return v

def inputs():
    cases=[]
    def add(name,moves,**changes):cases.append({'id':name,'initial':initial(**changes),'steps':moves})
    def raw(values):return [LC.db(v) for v in values]
    def axes(values):return [LC.fb(v) for v in values]
    def blocks(items):return [{'position':p,'block':b} for p,b in items]
    add('cache_uninstalled_original',[step((0,0,1))],loaded_chunks=False)
    add('cache_installed_match',[step((0,0,1))])
    add('air_miss',[step((0,0,0))],position=raw((.5,10,.5)),grounded=False,fall_distance_f64_bits=LC.db(.3),velocity=raw((0,-1.125,0)))
    add('floor',[step((0,0,1))])
    add('held_floor',[step((0,0,1)) for _ in range(5)],velocity=raw((0,-.08,0)))
    add('held_shift_edge',[step((1,0,0)) for _ in range(5)],position=raw((2.6,1,.5)),velocity=raw((.4,-.08,0)),input_f32_bits=axes((1,0,0)))
    wall=blocks([([1,1,0],'stone'),([1,2,0],'stone')])
    add('held_wall',[step((1,0,.2)) for _ in range(4)],world_writes=wall,velocity=raw((.4,-.08,.01)),input_f32_bits=axes((1,0,.2)))
    add('dynamic_floor',[step((0,0,0),world_writes=blocks([([0,0,0],b)])) for b in ['dirt','oak_planks','air','stone']],main_support=[0,0,0],velocity=raw((0,-.08,0)))
    add('sprint_floor',[step((1,0,1))],sprinting=True)
    add('sprint_air',[step((1,0,1))],sprinting=True,position=raw((.5,4,.5)),grounded=False)
    add('sprint_history',[step((0,0,1),sprinting=s) for s in [False,True,True,False]],velocity=raw((0,-.08,0)))
    add('stored_input_distinct',[step((0,0,1))],input_f32_bits=axes((1,0,0)),yaw_f32_bits=LC.fb(17))
    add('minor_distinct_input',[step((.1,0,1))],world_writes=blocks([([0,1,1],'stone'),([0,2,1],'stone')]),velocity=raw((.17,-.08,.6)),input_f32_bits=axes((1,0,0)),yaw_f32_bits=LC.fb(-8))
    add('minor_forward',[step((0,0,1))],world_writes=blocks([([0,1,1],'stone'),([0,2,1],'stone')]),velocity=raw((.17,-.08,.6)),input_f32_bits=axes((0,0,1)))
    for yaw,travel in [(90,(0,0,1)),(-17,(1,0,-1)),(180,(1,.5,1)),(360,(0,0,1)),(65536,(1,0,0))]:
        add('yaw_'+str(yaw),[step(travel)],yaw_f32_bits=LC.fb(yaw),velocity=raw((0,-.08,0)))
    for crouch,pose in [(True,'STANDING'),(False,'CROUCHING'),(True,'CROUCHING')]:
        add('pose_'+pose+'_'+str(crouch),[step((1,0,0))],crouching=crouch,pose=pose,position=raw((2.8,1,.5)),velocity=raw((.6,-.08,0)),input_f32_bits=axes((1,0,0)))
    for name,velocity in [('zero',(0,0,0)),('negative_zero',(-0.,-0.,-0.)),('subnormal',(5e-324,5e-324,-5e-324)),('gate_skip',(0,-.0004,0)),('gate_tiny',(0,-.0001,0)),('gate_threshold',(0,-math.sqrt(1e-7),0)),('up_tiny',(0,.0004,0))]:
        add(name,[step((-0.,-0.,-0.))],velocity=raw(velocity),main_support=[0,0,0],minor_horizontal_collision=True)
    add('zero_no_gravity',[step((-0.,0,-0.)) for _ in range(2)],velocity=raw((-0.,-0.,-0.)),no_gravity=True,main_support=[0,0,0])
    for axis,pos,velocity in [('x+',(2.8,1,.5),(.7,-.08,0)),('x-',(-1.8,1,.5),(-.7,-.08,0)),('z+',(.5,1,2.8),(0,-.08,.7)),('corner+',(2.8,1,2.8),(.7,-.08,.7)),('corner-',(-1.8,1,-1.8),(-.7,-.08,-.7))]:
        add('edge_'+axis,[step((0,0,0))],position=raw(pos),velocity=raw(velocity))
    add('corner_walls',[step((1,0,1))],world_writes=wall+blocks([([0,1,1],'dirt'),([0,2,1],'oak_planks')]),velocity=raw((.7,-.08,.7)),input_f32_bits=axes((1,0,1)))
    add('support_seam',[step((0,0,0))],position=raw((1,1,1)),velocity=raw((0,-.08,0)),world_writes=blocks([([0,0,0],'dirt'),([1,0,0],'oak_planks'),([0,0,1],'oak_planks')]))
    for prior in [False,True]:
        add('support_fallback_'+str(prior),[step((0,0,0))],position=raw((2.8,2,.5)),grounded=False,velocity=raw((.6,-1.08,0)),on_ground_no_blocks=prior,main_support=[7,0,-3])
    for height in [.6,1.,1.1]:
        add('step_'+str(height),[step((1,0,0))],world_writes=blocks([([1,1,0],'stone')]),velocity=raw((.6,-.08,0)),step_attribute_f64_bits=LC.db(height),input_f32_bits=axes((1,0,0)))
    add('partial_step',[step((0,0,0))],position=raw((.5,1.4,.5)),velocity=raw((.7,0,0)),world_writes=blocks([([1,1,0],'stone')]))
    add('step_ceiling',[step((1,0,0))],velocity=raw((.6,-.08,0)),step_attribute_f64_bits=LC.db(1.1),world_writes=blocks([([1,1,0],'stone'),([0,3,0],'oak_planks'),([1,3,0],'oak_planks')]))
    add('air_miss_history',[step((.1,0,.2)) for _ in range(4)],position=raw((.5,10,.5)),grounded=False,fall_distance_f64_bits=LC.db(.3),velocity=raw((0,-1.125,0)))
    add('air_zero_history',[step((0,0,0))],position=raw((.5,10,.5)),grounded=False,fall_distance_f64_bits=LC.db(0),velocity=raw((0,-1.125,0)))
    add('air_landing',[step((.1,0,.2)) for _ in range(4)],position=raw((.5,2,.5)),grounded=False,velocity=raw((0,-.35,0)))
    for name,changes in [('speed_double',{'movement_speed_f64_bits':LC.db(.2)}),('gravity_half',{'gravity_f64_bits':LC.db(.04)}),('gravity_negative',{'gravity_f64_bits':LC.db(-.04)}),('no_gravity',{'gravity_f64_bits':LC.db(.123),'no_gravity':True}),('discard',{'discard_friction':True}),('friction_zero',{'friction_modifier_f64_bits':LC.db(0)}),('friction_half',{'friction_modifier_f64_bits':LC.db(.5)}),('friction_two',{'friction_modifier_f64_bits':LC.db(2)}),('friction_three',{'friction_modifier_f64_bits':LC.db(3)}),('drag_zero',{'air_drag_modifier_f64_bits':LC.db(0)}),('drag_half',{'air_drag_modifier_f64_bits':LC.db(.5)}),('drag_two',{'air_drag_modifier_f64_bits':LC.db(2)})]:
        add('attribute_'+name,[step((.25,0,1))],**changes)
    add('attribute_history',[step((.25,0,1),friction_modifier_f64_bits=LC.db(f),air_drag_modifier_f64_bits=LC.db(d),no_gravity=ng) for f,d,ng in [(1,1,False),(.5,.5,True),(2,2,False),(0,0,False)]])
    add('unshift_guard',[step((.2,0,.1),shift=False)])
    add('crouch_without_shift_guard',[step((.2,0,.1),shift=False)],crouching=True,pose='CROUCHING')
    add('damaging_landing_guard',[step((0,0,0))],position=raw((.5,1.125,.5)),grounded=False,fall_distance_f64_bits=LC.db(3.874999),velocity=raw((0,-.25,0)))
    return {'cases':cases},[{'scope':'Not run as complete actual neutral cases','reason':'Nonfinite/giant queries, flight/passenger/noPhysics, real fluids/effects/Hit reset contexts and partial/missing synthetic world policies. Actual ClientLevel.hasChunkAt remains true even before chunk installation; there is no observed unloaded-client fallback.'}]

def dependencies():
    assert fingerprint(MH.OUTPUT)['sha256']==FROZEN_MH_REFERENCE
    return {'mh_producer':fingerprint(Path(MH.__file__)),'mh_reference':fingerprint(MH.OUTPUT),'mh_source_sha256':hashlib.sha256(MH.SOURCE.encode()).hexdigest(),'mh_dependencies':MH.dependency()}

def runtime_files():return LM.runtime_files()
def sources(values):
    s=LC.LI.receiver_sources();s[CLASS]=SOURCE.replace('__INPUT_BASE64__',LC.LI.java_string(base64.b64encode(canonical(values)).decode()));return s

def collect(values,rows):
    result=[]
    for case in values['cases']:
        actual=[r for r in rows if r['id']==case['id']];assert len(actual)==2
        plain=next(r for r in actual if not r['observed']);observed=next(r for r in actual if r['observed'])
        assert plain['installed_chunks']==observed['installed_chunks']
        assert [{k:v for k,v in s.items() if k!='events'} for s in plain['steps']]==[{k:v for k,v in s.items() if k!='events'} for s in observed['steps']],case['id']+' observer parity'
        out=copy.deepcopy(case);out['installed_chunks']=observed['installed_chunks'];out['plain_observer_parity']=True;out['steps']=[]
        for request,row in zip(case['steps'],observed['steps'],strict=True):
            events=row['events'];queries=[]
            for entry in [e for e in events if e['method'] in ('noCollision_entry','blockCollisions_entry','entityCollisions_entry','support_entry')]:
                q=entry['query'];same=[e for e in events if e.get('query')==q];method=entry['method'][:-6];exit=next((e for e in same if e['method']==method+'_exit'),None);reads=[{k:e[k] for k in ('ordinal','position','block_id','state_id','state_name','friction_f32_bits')} for e in same if e['method']=='getBlockState'];assert [r['ordinal'] for r in reads]==list(range(len(reads)))
                item={'index':q,'method':method,'parent_query':entry['parent_query'],'entry_sequence':entry['sequence'],'exit_sequence':None if exit is None else exit['sequence'],'box':entry['box'],'reads':reads,'yielded_shapes':[e['boxes'] for e in same if e['method']=='actual_block_collision_shape_yield']}
                if exit:
                    for k in ('result','selected','shapes'):
                        if k in exit:item[k]=exit[k]
                queries.append(item)
            calls=[e for e in events if 'body' in e];one=lambda method:next((e for e in calls if e['method']==method),None)
            move=one('move_entry');backoff=one('maybeBackOffFromEdge_exit');support=one('checkSupportingBlock_entry');support_after=one('checkSupportingBlock_exit');minor=one('isHorizontalCollisionMinor_entry');ground=one('setOnGroundWithMovement_entry');history=one('checkFallDamage_entry');history_after=one('checkFallDamage_exit');clips=[e for e in events if e['method']=='fallClip_exit'];assert len(clips)<=1
            ray='Miss' if clips and clips[0]['type']=='MISS' else 'Hit' if clips else 'Failed' if any(e['method']=='fallClip_entry' for e in events) else 'NotRequired' if history else 'Unobserved'
            c=row['context'];reasons=[]
            if not row['actual_returned']:reasons.append('Actual callback failed: '+row['error_class']+': '+row.get('error_message',''))
            for key in ['can_simulate','local_authoritative','suppressed_bounce','actual_has_chunk_at_ground_sample','current_fluid_empty']:
                if not c[key]:reasons.append('Observed '+key+'=false')
            for key in ['no_physics','passenger','flying','in_water','in_lava','swimming','fall_flying','on_climbable','levitation','slow_falling','omnidirectional_air_mover']:
                if c[key]:reasons.append('Observed '+key+'=true')
            if c['block_speed_factor_f32_bits']!=LC.fb(1.):reasons.append('Observed non-unit block speed')
            if ray not in ('Miss','NotRequired'):reasons.append('Actual ray status '+ray)
            neutral=not reasons
            result_step={**request,**{k:row[k] for k in ('before','context','expected','actual_returned','error_class','error_message') if k in row},'admission':{'neutral_context':neutral},'actual_travel_input':one('travel_entry')['input'],'prepared_after_move_relative':None if one('moveRelative_exit') is None else one('moveRelative_exit')['body'],'movement_before':None if move is None else move['state'],'movement_expected':None if one('move_exit') is None else one('move_exit')['state'],'move_entry':None if move is None else move['body'],'move_requested':None if move is None else move['requested'],'corrected_requested':None if backoff is None else backoff['result'],'resolved':None if ground is None else ground['movement'],'before_support':None if support is None else support['body'],'after_support':None if support_after is None else support_after['body'],'before_minor':None if minor is None else minor['body'],'minor_called':minor is not None,'position_application_gate_entered':one('recordMovement_entry') is not None,'finish_entry':None if one('move_exit') is None else one('move_exit')['body'],'finish_exit':None if one('travel_exit') is None else one('travel_exit')['body'],'queries':queries,'player_calls':calls,'sample_reads':[{k:e[k] for k in ('sequence','ordinal','position','block_id','state_id','state_name','friction_f32_bits')} for e in events if e['method']=='getBlockState' and e['query']==-1],'chunk_checks':[e for e in events if e['method']=='hasChunkAt'],'phase_order':[e['method'] for e in events if e['method']!='getBlockState'],'ray_observation':{'status':ray,'clip_calls':[e for e in events if e['method'] in ('fallClip_entry','fallClip_exit')]},'history_phase':None if history is None else {'resolved_y_f64_bits':history['movement_f64_bits'],'on_ground':history['grounded'],'sampled_block':history['block_id'],'sampled_position':history['position'],'entry':history['body']['fall_distance_f64_bits'],'exit':None if history_after is None else history_after['body']['fall_distance_f64_bits'],'reset_calls':[e for e in events if e['method'] in ('resetFallDistance_entry','resetFallDistance_exit')]}}
            relative=one('moveRelative_entry');move_exit=one('move_exit');gravity=[e for e in calls if e['method']=='getEffectiveGravity_exit' and move_exit is not None and e['sequence']>move_exit['sequence']];finish_setter=[e for e in calls if e['method']=='setDeltaMovementDDD_entry' and move_exit is not None and e['sequence']>move_exit['sequence']]
            if reasons:result_step['admission']['exclusion']='; '.join(reasons)
            if result_step['history_phase'] is not None:result_step['history_phase']['resolved_length_squared_f64_bits']=ground['resolved_length_squared_f64_bits']
            result_step['actual_requested']=result_step['move_requested']
            result_step['travel_context']=row['context']
            result_step['travel_phase']={'moveRelative':relative,'moveRelative_after':one('moveRelative_exit'),'move_entry':move,'move_exit':move_exit,'effective_gravity_calls_after_move':gravity,'finish_velocity_setters':finish_setter,'modified_ground_friction_helper_f32_bits':c['modified_ground_friction_helper_f32_bits'],'friction_f32_bits':c['modified_ground_friction_helper_f32_bits'] if row['before']['body_flags'][0] else LC.fb(1.),'friction_helper_scope':c['friction_helper_scope'],'acceleration_f32_bits':None if relative is None else relative['acceleration_f32_bits'],'prepared_gravity_f64_bits':c['gravity_getter_f64_bits'],'prepared_gravity_scope':'Direct actual public final Entity.getGravity sampled before travel; actual post-move effective gravity calls separately observed.','final_velocity':row['expected']['velocity']}
            if row['actual_returned']:
                assert move is not None and move_exit is not None and relative is not None
                assert relative['input']==result_step['actual_travel_input']==request['travel_input']
                assert move['requested']==move['body']['velocity']
                assert history is not None and history_after is not None
                assert ground['movement'][1]==history['movement_f64_bits']
                assert history_after['body']['fall_distance_f64_bits']==row['expected']['fall_distance_f64_bits']
                assert support_after['sequence']<history['sequence']
                if minor is not None:assert support_after['sequence']<minor['sequence']<history['sequence']
                assert history_after['sequence']<move_exit['sequence']<one('travel_exit')['sequence']
                if neutral:assert len(gravity)==len(finish_setter)==1 and gravity[0]['result_f64_bits']==c['gravity_getter_f64_bits']
            out['steps'].append(result_step)
        result.append(out)
    if len(result)>=2 and result[0]['id']=='cache_uninstalled_original' and result[1]['id']=='cache_installed_match':
        assert result[0]['steps']==result[1]['steps'],'Actual installed/uninstalled whole-travel outputs differ'
        for case in result[:2]:case['cache_installation_relation']={'compared_with':'cache_installed_match' if case is result[0] else 'cache_uninstalled_original','complete_step_projection_equal':True,'actual_has_chunk_at_true':True,'actual_unloaded_fallback_observed':False}
    return result

def boundary():
    return {'decisive':'Untouched normal LocalPlayer.travel invokes original Player/Avatar/LivingEntity travel and whole LocalPlayer.move; every decisive expected field comes from actual calls.','services':'Same four frozen explicit LI client services. No foreground Minecraft, unsafe allocation, gameplay substitution or composition supplies expected results.','chunks':'Normal real LevelChunk(level,ChunkPos) constructors populate actual ClientChunkCache.Storage using original private getIndex/replace methods. Actual slots/chunk coordinates/empty section observations/cache identity/hasChunkAt are recorded. Chunk sections remain all air/no-fluid; separate finite collision block map is the declared external BlockGetter world. Untouched ClientLevel.hasChunk returns literal true, so cache_uninstalled_original is admitted and exactly matches the installed baseline; no unloaded-client fallback is observed.','phases':'Super-calling travel/moveRelative/getSpeed/getFlyingSpeed/below-position/gravity/DDD-velocity observers plus inherited whole-move/history observers expose actual preparation/move/support/minor/ray/reset/finish boundaries. Friction is explicitly a direct official helper observation/airborne literal operand, not a captured private travelInAir local.','inputs':'Travel Vec3, stored xxa/yya/zza, current logical shift keys, crouching/pose and resolved post-sprint attributes are independently supplied/observed. Initial/step attributes use normal AttributeInstance.setBaseValue; noGravity/discard use actual setters.','observer':'Plain/observed final raw states and context/chunk availability agree. Level noCollision/findSupportingBlock/clip/hasChunkAt call super; actual ordered iterator reads/yields preserved.','scope':'Finite bounded neutral air travel with actual Miss or NotRequired histories. Actual damaging-callback failures and unshift contexts are retained separately when observed. Fluids/effects/flight/Hit/nonfinite/giant or incomplete worlds are not claimed; no full-tick parity claim.'}

def counts(cases):
    steps=[s for c in cases for s in c['steps']];queries=[q for s in steps for q in s['queries']]
    return {'cases':len(cases),'steps':len(steps),'neutral_steps':sum(s['admission']['neutral_context'] for s in steps),'actual_returns':sum(s['actual_returned'] for s in steps),'queries':len(queries),'reads':sum(len(q['reads']) for q in queries),'yielded_shapes':sum(len(q['yielded_shapes']) for q in queries),'ray_statuses':{m:sum(s['ray_observation']['status']==m for s in steps) for m in sorted({s['ray_observation']['status'] for s in steps})}}

def source_inventory():
    result=LM.source_inventory()
    wanted={'Cursor3D','advance','getNextType','nextX','nextY','nextZ','intersects','floor','hasLargeCollisionShape','getCollisionShape','getId','travel','travelInAir','travelInFluid','getSpeed','getFlyingSpeed','moveRelative','getInputVector','getBlockPosBelowThatAffectsMyMovement','getEffectiveGravity','getFrictionInfluencedSpeed','handleRelativeFrictionAndCalculateMovement','computeModifiedFriction','shouldTravelInFluid','shouldDiscardFriction','setDiscardFriction','omnidirectionalAirMover','handleOnClimbable','getGravity','getDefaultGravity','setNoGravity','setSprinting','getIndex','replace','LevelChunk','LevelChunkSection','hasOnlyAir','getBlockState','getFluidState','hasChunk','hasChunkAt','getChunk','getSections','findSupportingBlock','computeNext','Vec3','move','recordMovement','checkSupportingBlock','setOnGroundWithMovement','collide','collectCollidersIgnoringWorldBorder','collideBoundingBox','collideWithShapes','collectCandidateStepUpHeights','getBlockSpeedFactor','restituteMovementAfterCollisions','checkFallDamage','setDeltaMovement','updateAutoJump','addWalkedDistance','applyMovementEmissionAndPlaySound'}
    with zipfile.ZipFile(CLIENT) as jar:
        for owner in ['net.minecraft.world.entity.Avatar','net.minecraft.client.multiplayer.ClientLevel','net.minecraft.client.multiplayer.ClientChunkCache','net.minecraft.client.multiplayer.ClientChunkCache$Storage','net.minecraft.world.level.chunk.LevelChunk','net.minecraft.world.level.chunk.LevelChunkSection','net.minecraft.world.level.Level','net.minecraft.world.level.LevelReader','net.minecraft.world.phys.Vec3','net.minecraft.world.entity.Entity','net.minecraft.world.entity.player.Player','net.minecraft.client.player.LocalPlayer','net.minecraft.client.player.AbstractClientPlayer','net.minecraft.world.entity.LivingEntity','net.minecraft.world.level.CollisionGetter','net.minecraft.world.level.BlockCollisions','net.minecraft.core.Cursor3D','net.minecraft.world.phys.AABB','net.minecraft.util.Mth','net.minecraft.world.level.block.state.BlockBehaviour$BlockStateBase','net.minecraft.world.level.block.Block']:
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
    report.update(evidence_format='local-travel-history-summary-v1',raw_report={'path':str(raw.relative_to(ROOT)),**fingerprint(raw)},storage_writer=fingerprint(Path(__file__)),observation_count=len(e['observations']))
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
    assert sha(e['execution']['command'])==s['execution']['command_sha256'];assert {n:hashlib.sha256(v.encode()).hexdigest() for n,v in e['raw_execution']['sources'].items()}==e['expanded_source_sha256'];assert hashlib.sha256(e['raw_execution']['launcher'].encode()).hexdigest()==e['execution']['compiled_launcher_sha256'];return s

def run(cases,label):
    dep=dependencies();classpath,prov=verified_client_classpath();ss=sources(cases);payload={'sources':ss,'client_jar':str(CLIENT),'mode':'move_world'};encoded=base64.b64encode(canonical(payload)).decode()
    launcher=LC.LI.RECEIVER_LAUNCHER.replace('net.minecraft.fixture.LocalInputReceiverFixture',CLASS).replace('Base64.getDecoder().decode(args[0])','Base64.getDecoder().decode('+LC.LI.java_string(encoded)+')',1)
    command=[str(JAVA),'--source','25','--class-path',':'.join(map(str,classpath)),'/dev/stdin'];start=time.monotonic();process=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
    try:stdout,stderr=process.communicate(launcher,timeout=120)
    except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);stdout,stderr=process.communicate();raise RuntimeError('120s whole-travel Java watchdog expired')
    p=subprocess.CompletedProcess(command,process.returncode,stdout,stderr)
    if p.returncode!=0:
        failure=RAW/f'{label}-setup-failure-{time.time_ns()}.json';save(failure,{'status':'failed','command':command,'pid':process.pid,'producer':fingerprint(Path(__file__)),'source_sha256':hashlib.sha256(SOURCE.encode()).hexdigest(),'sources':ss,'launcher':launcher,'stdout':stdout,'stderr':stderr,'returncode':p.returncode})
    def parse(prefix):return [json.loads(s[len(prefix):]) for s in p.stdout.splitlines() if s.startswith(prefix)]
    rows=parse('LOCAL_TRAVEL_HISTORY_JSON:');loaded=parse('LOCAL_INPUT_CLASSES:');runtime=parse('LOCAL_TRAVEL_HISTORY_RUNTIME:')
    assert p.returncode==0,'Actual fixture failure: '+'\n'.join(x for x in p.stdout.splitlines() if not x.startswith('LOCAL_INPUT_CLASSES:'))[-7000:]+p.stderr[-2000:]
    assert len(loaded)==len(runtime)==1
    assert len(rows)==2*len(cases['cases'])
    inventory=source_inventory()
    with zipfile.ZipFile(CLIENT) as jar:
        for n,h in loaded[0].items():assert hashlib.sha256(jar.read(n.replace('.','/')+'.class')).hexdigest()==h,'Loaded official class mismatch: '+n
    for n,h in loaded[0].items():
        if n in inventory and not n.startswith('java.'):assert h==inventory[n]['class_sha256']
    for n,h in runtime[0].items():inventory[n]['class_sha256']=h
    projected=collect(cases,rows)
    e={'schema_version':1,'pin':'26.3','status':'passed','producer_at_execution':fingerprint(Path(__file__)),'dependency':dep,'provenance':prov,'runtime_files':runtime_files(),'source':inventory,'boundary':boundary(),
       'source_sha256':hashlib.sha256(SOURCE.encode()).hexdigest(),'expanded_source_sha256':{n:hashlib.sha256(s.encode()).hexdigest() for n,s in ss.items()},'launcher_sha256':hashlib.sha256(LC.LI.RECEIVER_LAUNCHER.encode()).hexdigest(),
       'substituted_external_types':{n:{'source':s,'source_sha256':hashlib.sha256(s.encode()).hexdigest()} for n,s in LC.LI.RECEIVER_SOURCES.items() if n!='net.minecraft.fixture.LocalInputReceiverFixture'},
       'loaded_official_classes':{n:h for n,h in loaded[0].items() if n in inventory},'loaded_official_class_count':len(loaded[0]),'loaded_official_class_tree_sha256':sha(loaded[0]),'runtime_classes':runtime[0],
       'observations':rows,'observations_sha256':sha(rows),'cases_sha256':sha(projected),'counts':counts(projected),'plain_observer_projected_parity':True,'whole_travel_projection':True,
       'execution':{'command':command,'pid':process.pid,'cap_seconds':120,'reproduce':'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_travel_history_probe.py --'+('rerun' if label=='independent' else 'debug' if label=='debug' else 'extract'),'seconds':round(time.monotonic()-start,6),'returncode':p.returncode,'input_sha256':sha(payload),'compiled_launcher_sha256':hashlib.sha256(launcher.encode()).hexdigest(),'stdout_sha256':hashlib.sha256(p.stdout.encode()).hexdigest(),'stderr_sha256':hashlib.sha256(p.stderr.encode()).hexdigest(),'stderr_tail':p.stderr[-3000:]},
       'raw_execution':{'stdout':p.stdout,'stderr':p.stderr,'loaded_official_classes':loaded[0],'sources':ss,'launcher':launcher}}
    path=ROOT/f'evidence/local-travel-history-reference-{label}.json';compact_report(path,e);return projected,e,path

def extract(debug=False):
    cases,excluded=inputs()
    if debug:cases['cases']=cases['cases'][:3]
    projected,e,path=run(cases,'debug' if debug else 'actual')
    if debug:return {'status':'passed','evidence':fingerprint(path),'counts':e['counts']}
    d={k:e[k] for k in ('schema_version','pin','dependency','provenance','runtime_files','source','boundary','source_sha256','expanded_source_sha256','launcher_sha256','loaded_official_classes','loaded_official_class_count','loaded_official_class_tree_sha256','runtime_classes')}
    raw=RAW/f'{path.stem}.full.json'
    d.update(inputs_sha256=sha(cases),cases=projected,excluded_cases=excluded,counts=e['counts'],observations_sha256=sha(projected),raw_report={'path':str(raw.relative_to(ROOT)),**fingerprint(raw)});save(OUTPUT,d)
    return {'status':'passed','reference':fingerprint(OUTPUT),'counts':e['counts'],'excluded_cases':excluded,'evidence':fingerprint(path)}

def verify_data(d,prov,inventory):
    cases,excluded=inputs();assert d['pin']=='26.3' and d['schema_version']==1;assert d['inputs_sha256']==sha(cases);assert d['excluded_cases']==excluded;assert d['source_sha256']==hashlib.sha256(SOURCE.encode()).hexdigest();assert d['expanded_source_sha256']=={n:hashlib.sha256(s.encode()).hexdigest() for n,s in sources(cases).items()};assert d['launcher_sha256']==hashlib.sha256(LC.LI.RECEIVER_LAUNCHER.encode()).hexdigest();assert d['dependency']==dependencies();assert d['provenance']==prov;assert d['runtime_files']==runtime_files()
    r=LC.runtime_inventory();assert d['runtime_classes']==r
    for n,h in r.items():inventory[n]['class_sha256']=h
    assert d['source']==inventory;assert d['boundary']==boundary();assert d['observations_sha256']==sha(d['cases']);assert d['counts']==counts(d['cases'])
    for n,h in d['loaded_official_classes'].items():assert inventory[n]['class_sha256']==h
    raw=ROOT/d['raw_report']['path'];assert d['raw_report']=={'path':d['raw_report']['path'],**fingerprint(raw)};e=json.loads(raw.read_text());assert sha(e['observations'])==e['observations_sha256'];assert d['cases']==collect(cases,e['observations']);assert e['cases_sha256']==d['observations_sha256'];assert sha(e['raw_execution']['loaded_official_classes'])==d['loaded_official_class_tree_sha256'];assert len(e['raw_execution']['loaded_official_classes'])==d['loaded_official_class_count'];assert e['source']==d['source'];assert e['provenance']==d['provenance'];assert e['runtime_files']==d['runtime_files'];assert e['expanded_source_sha256']==d['expanded_source_sha256'];assert e['source_sha256']==d['source_sha256'];assert e['runtime_classes']==d['runtime_classes']
    assert {n:hashlib.sha256(v.encode()).hexdigest() for n,v in e['raw_execution']['sources'].items()}==d['expanded_source_sha256'];assert hashlib.sha256(e['raw_execution']['launcher'].encode()).hexdigest()==e['execution']['compiled_launcher_sha256']
    with zipfile.ZipFile(CLIENT) as jar:
        for n,h in e['raw_execution']['loaded_official_classes'].items():assert hashlib.sha256(jar.read(n.replace('.','/')+'.class')).hexdigest()==h

def verify(selftest=False):
    d=json.loads(OUTPUT.read_text());_,prov=verified_client_classpath();inv=source_inventory();verify_data(d,prov,inv);result={'status':'passed','producer':fingerprint(Path(__file__)),'reference':fingerprint(OUTPUT),'counts':d['counts'],'scope':'Integrity/provenance only; no new actual full travel run'}
    if selftest:
        checks=[]
        for label,path in [('client',['provenance','client','sha256']),('runtime',['provenance','java','sha256']),('library',['provenance','libraries',0,'sha256']),('runtime_modules',['runtime_files','jrt_modules','sha256']),('source',['source_sha256']),('class_tree',['loaded_official_class_tree_sha256']),('read',['cases',0,'steps',0,'queries',0,'reads',0,'state_id']),('raw_report',['raw_report','sha256']),('phase',['cases',0,'steps',0,'travel_phase','prepared_gravity_f64_bits'])]:
            v=copy.deepcopy(d);o=v
            for k in path[:-1]:o=o[k]
            o[path[-1]]='injected-mismatch'
            try:verify_data(v,prov,inv)
            except AssertionError:checks.append({'injection':label,'rejected':True})
            else:raise AssertionError('Injection accepted: '+label)
        result['failure_injections']=checks
    save(ROOT/'evidence/local-travel-history-reference-integrity.json',result);return result

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
