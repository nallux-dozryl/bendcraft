#!/usr/bin/env python3
"""Direct pinned neutral Player.aiStep observations, including chained calls."""
from __future__ import annotations
import argparse, copy, hashlib, json, math, random, re, struct, subprocess, time, zipfile
from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_block_probe import verified_classpath
from reference_travel_probe import SOURCE as TRAVEL_SOURCE, MOVEMENT_SOURCE, DIRECT_SOURCE, source_inventory as travel_inventory, bits, fbits, block
OUTPUT=ROOT/'reference/player_tick.json'
SEED=263_104_06
SOURCE=r'''
import java.io.*;
import java.nio.file.*;
import java.lang.reflect.*;
import java.util.*;
import java.util.function.Predicate;
import com.google.gson.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;
import net.minecraft.core.registries.*;
import net.minecraft.resources.*;
import net.minecraft.world.entity.*;
import net.minecraft.world.entity.player.*;
import net.minecraft.world.entity.ai.attributes.*;
import net.minecraft.world.level.*;
import net.minecraft.world.level.block.*;
import net.minecraft.world.phys.*;
public class ReferencePlayerTickProbe {
 static final Gson JSON=new Gson();
 static Field field(Class<?> c,String name)throws Exception{for(Class<?> k=c;k!=null;k=k.getSuperclass()){try{Field f=k.getDeclaredField(name);f.setAccessible(true);return f;}catch(NoSuchFieldException e){}}throw new NoSuchFieldException(name);}
 static Object read(Object o,String name)throws Exception{return field(o.getClass(),name).get(o);}
 static void write(Object o,String name,Object v)throws Exception{field(o.getClass(),name).set(o,v);}
 static class FixtureLevel extends ReferenceTravelProbe.FixtureLevel {
  final net.minecraft.world.scores.Scoreboard scoreboard=new net.minecraft.world.scores.Scoreboard();
  public net.minecraft.world.scores.Scoreboard getScoreboard(){hit("getScoreboard_empty_teams");return scoreboard;}
  public List<Entity> getEntities(Entity except,AABB box,Predicate<? super Entity> predicate){hit("getEntities_empty_actor_world");return List.of();}
 }
 static class FixturePlayer extends ReferenceTravelProbe.FixturePlayer {
  Map<String,Object> cleaned,preTravel,postTravel,afterInput,jumpBefore,jumpAfter;
  Vec3 travelInput;BlockPos travelBelow;float jumpFactor,jumpPower;int travelStage;
  FixturePlayer(Level l){super(l);}
  protected void applyInput(){hit("applyInput_observer");cleaned=ReferenceTravelProbe.body(this);super.applyInput();afterInput=inputState(this);}
  protected float getBlockJumpFactor(){hit("getBlockJumpFactor_observer");return jumpFactor=super.getBlockJumpFactor();}
  protected float getJumpPower(){hit("getJumpPower_observer");return jumpPower=super.getJumpPower();}
  public void jumpFromGround(){hit("jumpFromGround_observer");jumpBefore=ReferenceTravelProbe.body(this);super.jumpFromGround();jumpAfter=ReferenceTravelProbe.body(this);}
  public BlockPos getBlockPosBelowThatAffectsMyMovement(){BlockPos p=super.getBlockPosBelowThatAffectsMyMovement();if(travelStage==1)travelBelow=p;return p;}
  public void travel(Vec3 input){hit("travel_observer");travelStage=1;travelInput=input;preTravel=tickState(this);super.travel(input);postTravel=tickState(this);travelStage=2;}
  public void setSpeed(float speed){super.setSpeed(speed);}
 }
 static Map<String,Object> inputState(FixturePlayer p){return Map.of("input_f32_bits",List.of(ReferenceTravelProbe.fb(p.xxa),ReferenceTravelProbe.fb(p.yya),ReferenceTravelProbe.fb(p.zza)));}
 static Map<String,Object> tickState(FixturePlayer p){try{Map<String,Object> m=new TreeMap<>(ReferenceTravelProbe.body(p));m.putAll(inputState(p));m.put("jumping",read(p,"jumping"));m.put("jump_delay",read(p,"noJumpDelay"));m.put("jump_trigger",read(p,"jumpTriggerTime"));m.put("needs_sync",p.needsSync);m.put("stored_speed_f32_bits",ReferenceTravelProbe.fb((Float)read(p,"speed")));m.put("head_yaw_f32_bits",ReferenceTravelProbe.fb(p.yHeadRot));return m;}catch(Exception e){throw new RuntimeException(e);}}
 static void inputs(FixturePlayer p,JsonObject in)throws Exception{
  if(in.has("input_f32_bits")){JsonArray a=in.getAsJsonArray("input_f32_bits");p.xxa=ReferenceMovementProbe.f(a.get(0));p.yya=ReferenceMovementProbe.f(a.get(1));p.zza=ReferenceMovementProbe.f(a.get(2));}
  if(in.has("jumping"))p.setJumping(in.get("jumping").getAsBoolean());
  if(in.has("sprinting"))p.setSprinting(in.get("sprinting").getAsBoolean());
 }
 static Map<String,Object> observe(JsonObject c)throws Exception{
  ReferenceDirectMovementProbe.initialize();JsonObject in=c.getAsJsonObject("input");FixtureLevel level=new FixtureLevel();
  for(JsonElement e:in.getAsJsonArray("world_blocks")){JsonObject b=e.getAsJsonObject();JsonArray a=b.getAsJsonArray("position");Block v=BuiltInRegistries.BLOCK.getValue(Identifier.parse(b.get("identifier").getAsString()));if(v!=Blocks.STONE&&v!=Blocks.DIRT&&v!=Blocks.OAK_PLANKS&&v!=Blocks.ICE&&v!=Blocks.BLUE_ICE)throw new IllegalArgumentException("Unsupported neutral aiStep world block");level.blocks.put(new BlockPos(a.get(0).getAsInt(),a.get(1).getAsInt(),a.get(2).getAsInt()),v.defaultBlockState());}
  FixturePlayer p=new FixturePlayer(level);p.setPos(ReferenceMovementProbe.vector(in.getAsJsonArray("position")));p.setOnGround(in.get("grounded").getAsBoolean());p.setDeltaMovement(ReferenceMovementProbe.vector(in.getAsJsonArray("velocity")));
  for(String key:List.of("movement_speed","gravity","friction_modifier","air_drag_modifier","step_height","jump_strength")){var attribute=switch(key){case "movement_speed"->Attributes.MOVEMENT_SPEED;case "gravity"->Attributes.GRAVITY;case "friction_modifier"->Attributes.FRICTION_MODIFIER;case "air_drag_modifier"->Attributes.AIR_DRAG_MODIFIER;case "step_height"->Attributes.STEP_HEIGHT;default->Attributes.JUMP_STRENGTH;};ReferenceTravelProbe.attribute(p,attribute,in,key);}
  p.setYRot(ReferenceMovementProbe.f(in.get("yaw_f32_bits")));p.setNoGravity(in.get("no_gravity").getAsBoolean());p.setDiscardFriction(in.get("discard_friction").getAsBoolean());inputs(p,in);write(p,"noJumpDelay",in.get("jump_delay").getAsInt());write(p,"jumpTriggerTime",in.get("jump_trigger").getAsInt());p.needsSync=in.get("needs_sync").getAsBoolean();p.setSpeed(ReferenceMovementProbe.f(in.get("stored_speed_f32_bits")));p.yHeadRot=ReferenceMovementProbe.f(in.get("head_yaw_f32_bits"));
  List<Map<String,Object>> ticks=new ArrayList<>();
  for(JsonElement update:in.getAsJsonArray("ticks")){
   inputs(p,update.getAsJsonObject());if(!p.canSimulateMovement()||!p.isEffectiveAi()||!p.isLocalInstanceAuthoritative()||p.isPassenger()||p.isSwimming()||p.isFallFlying()||p.getAbilities().flying||p.onClimbable()||!p.getActiveEffects().isEmpty()||p.isDeadOrDying()||p.isSleeping()||p.isInterpolating()||!p.getInventory().isEmpty()||p.isInLiquid()||p.wasInPowderSnow||level.isRaining()||((Integer)read(p,"autoSpinAttackTicks"))!=0||((Integer)read(p,"lerpHeadSteps"))!=0)throw new AssertionError("Unsupported neutral tick context");
   Map<String,Object> initial=tickState(p);Map<String,Object> attrs=new TreeMap<>();for(var entry:Map.of("movement_speed",Attributes.MOVEMENT_SPEED,"gravity",Attributes.GRAVITY,"friction_modifier",Attributes.FRICTION_MODIFIER,"air_drag_modifier",Attributes.AIR_DRAG_MODIFIER,"jump_strength",Attributes.JUMP_STRENGTH).entrySet())attrs.put(entry.getKey(),ReferenceMovementProbe.bits(p.getAttributeValue(entry.getValue())));attrs.put("maximum_f32_bits",ReferenceTravelProbe.fb(p.maxUpStep()));attrs.put("jump_factor_f32_bits",ReferenceTravelProbe.fb(p.getBlockJumpFactor()));
   p.cleaned=null;p.preTravel=null;p.postTravel=null;p.jumpBefore=null;p.jumpAfter=null;p.travelInput=null;p.travelBelow=null;p.jumpPower=0;p.jumpFactor=0;p.travelStage=0;p.observations.clear();level.clearTrace();p.aiStep();
   if(p.preTravel==null||p.postTravel==null||p.cleaned==null||p.travelBelow==null)throw new AssertionError("Actual aiStep travel path not executed");
   if(p.isInLiquid()||p.onClimbable()||p.wasInPowderSnow||!p.getActiveEffects().isEmpty())throw new AssertionError("Left neutral tick context");
   var initialShapes=level.initial.isEmpty()?List.<net.minecraft.world.phys.shapes.VoxelShape>of():level.initial.getFirst();var stepShapes=level.step.isEmpty()?List.<net.minecraft.world.phys.shapes.VoxelShape>of():level.step.getFirst();
   Map<String,Object> o=new TreeMap<>();o.put("initial",initial);o.put("attributes",attrs);o.put("cleaned_body",p.cleaned);o.put("after_input",p.afterInput);o.put("pre_travel",p.preTravel);o.put("post_travel",p.postTravel);o.put("travel_input",ReferenceMovementProbe.vectorBits(p.travelInput));o.put("requested",ReferenceMovementProbe.vectorBits(p.requested));o.put("post_move_body",p.postMoveBody);o.put("jump_before",p.jumpBefore);o.put("jump_after",p.jumpAfter);o.put("jump_factor_f32_bits",ReferenceTravelProbe.fb(p.jumpFactor));o.put("jump_power_f32_bits",ReferenceTravelProbe.fb(p.jumpPower));o.put("below_position",List.of(p.travelBelow.getX(),p.travelBelow.getY(),p.travelBelow.getZ()));o.put("block_friction_f32_bits",ReferenceTravelProbe.fb(level.getBlockState(p.travelBelow).getBlock().getFriction()));o.put("initial_shapes",ReferenceDirectMovementProbe.shapeInputs(initialShapes));o.put("step_shapes",ReferenceDirectMovementProbe.shapeInputs(stepShapes));o.put("queries",List.copyOf(level.queries));o.put("observer_calls",new TreeMap<>(p.observations));o.put("fixture_service_calls",new TreeMap<>(level.calls));o.put("full_player_ai_step_executed",true);ticks.add(Map.of("expected",tickState(p),"observation",o));
  }
  return Map.of("id",c.get("id").getAsString(),"ticks",ticks);
 }
 static Map<String,Object> observeJump(JsonObject c)throws Exception{
  ReferenceDirectMovementProbe.initialize();JsonObject in=c.getAsJsonObject("input");FixtureLevel level=new FixtureLevel();
  for(JsonElement e:in.getAsJsonArray("world_blocks")){JsonObject b=e.getAsJsonObject();JsonArray a=b.getAsJsonArray("position");Block v=BuiltInRegistries.BLOCK.getValue(Identifier.parse(b.get("identifier").getAsString()));if(v!=Blocks.STONE&&v!=Blocks.HONEY_BLOCK&&v!=Blocks.SLIME_BLOCK)throw new IllegalArgumentException("Unsupported jump sample block");level.blocks.put(new BlockPos(a.get(0).getAsInt(),a.get(1).getAsInt(),a.get(2).getAsInt()),v.defaultBlockState());}
  FixturePlayer p=new FixturePlayer(level);p.setPos(ReferenceMovementProbe.vector(in.getAsJsonArray("position")));p.setOnGround(true);p.setDeltaMovement(ReferenceMovementProbe.vector(in.getAsJsonArray("velocity")));ReferenceTravelProbe.attribute(p,Attributes.JUMP_STRENGTH,in,"jump_strength");p.setYRot(ReferenceMovementProbe.f(in.get("yaw_f32_bits")));p.setSprinting(in.get("sprinting").getAsBoolean());p.needsSync=in.get("needs_sync").getAsBoolean();Map<String,Object> initial=ReferenceTravelProbe.body(p);
  float factor=p.getBlockJumpFactor(),power=p.getJumpPower();double strength=p.getAttributeValue(Attributes.JUMP_STRENGTH);p.observations.clear();level.clearTrace();p.jumpFromGround();
  return Map.of("id",c.get("id").getAsString(),"expected",Map.of("body",ReferenceTravelProbe.body(p),"needs_sync",p.needsSync,"power_f32_bits",ReferenceTravelProbe.fb(power)),"observation",Map.of("initial",initial,"jump_strength",ReferenceMovementProbe.bits(strength),"jump_factor_f32_bits",ReferenceTravelProbe.fb(factor),"actual_jump_from_ground_executed",true,"observer_calls",new TreeMap<>(p.observations),"fixture_service_calls",new TreeMap<>(level.calls)));
 }
 public static void main(String[]args)throws Exception{SharedConstants.tryDetectVersion();Bootstrap.bootStrap();try(BufferedReader r=Files.newBufferedReader(Path.of(args[0]));PrintWriter w=new PrintWriter(Files.newBufferedWriter(Path.of(args[1])))){for(String line;(line=r.readLine())!=null;){JsonObject c=JsonParser.parseString(line).getAsJsonObject();w.println(JSON.toJson(c.get("operation").getAsString().equals("jump_only")?observeJump(c):observe(c)));}if(w.checkError())throw new IOException("Write failed");}}
}
'''

def generate_inputs():
 floor=[block([x,0,z]) for x in range(-3,4) for z in range(-3,16)]
 initial={'position':list(map(bits,[.5,1.,.5])),'velocity':[bits(0.)]*3,'grounded':True,'input_f32_bits':[fbits(0.),fbits(0.),fbits(1.)],'jumping':True,'sprinting':False,'no_gravity':False,'discard_friction':False,'yaw_f32_bits':fbits(0.),'movement_speed':bits(.1),'gravity':bits(.08),'friction_modifier':bits(1.),'air_drag_modifier':bits(1.),'step_height':bits(.6),'jump_strength':bits(.42),'jump_delay':0,'jump_trigger':7,'needs_sync':False,'stored_speed_f32_bits':fbits(.7),'head_yaw_f32_bits':fbits(-90.),'world_blocks':floor,'ticks':[{'input_f32_bits':[fbits(0.),fbits(0.),fbits(1.)],'jumping':True} for _ in range(24)]}
 cases=[]
 def add(name,**changes):
  v=copy.deepcopy(initial);v['ticks']=[{}];v.update(changes);cases.append({'id':'player-tick:'+name,'operation':'player_ai_step','input':v,'tags':['actual_player_ai_step','neutral_projection']})
 add('held-input-jump',ticks=initial['ticks'])
 add('decaying-input',jumping=False,ticks=[{} for _ in range(32)])
 add('release-repress',ticks=[{'jumping':i%6<3,'input_f32_bits':[fbits(0.),fbits(0.),fbits(1.)]} for i in range(48)])
 add('sprint-held-jump',sprinting=True,yaw_f32_bits=fbits(45.),ticks=initial['ticks'])
 for i,v in enumerate([0.,-0.,math.nextafter(.003,0.),.003,math.nextafter(.003,math.inf),-.003,.003/math.sqrt(2),math.nextafter(.003/math.sqrt(2),0.),math.nextafter(.003/math.sqrt(2),math.inf)]):
  for z in [0.,v,-v]:add(f'cleanup-{i}-{bits(z)}',velocity=list(map(bits,[v,-v,z])),jumping=False,input_f32_bits=[fbits(0.)]*3)
 for delay in [-2147483648,-1,0,1,2,9,10,11,2147483647]:
  for trigger in [-2147483648,-1,0,1,10,2147483647]:
   for held in [False,True]:add(f'counter-{delay}-{trigger}-{held}',jump_delay=delay,jump_trigger=trigger,jumping=held,ticks=[{},{}])
 threshold=struct.unpack('>f',bytes.fromhex('3727c5ac'))[0]
 strengths=[0.,math.ulp(0.),1e-50,*[struct.unpack('>f',(925353388+k).to_bytes(4,'big'))[0] for k in [-1,0,1]],math.nextafter(threshold,0.),math.nextafter(threshold,math.inf),.42,1.,32.]
 for i,s in enumerate(strengths):
  for sprint in [False,True]:
   for vy in [-.01,0.,.42,.8]:add(f'jump-power-{i}-{sprint}-{bits(vy)}',jump_strength=bits(s),sprinting=sprint,velocity=list(map(bits,[.1,vy,-.1])),input_f32_bits=[fbits(0.)]*3)
 for yaw in [0.,-0.,90.,-90.,180.,360.,1e30,-1e30,3.4028234663852886e38]:
  add('sprint-yaw-'+fbits(yaw),sprinting=True,yaw_f32_bits=fbits(yaw),ticks=[{},{}])
 for i,v in enumerate([0.,-0.,struct.unpack('>f',bytes.fromhex('00000001'))[0],.1,struct.unpack('>f',bytes.fromhex('3dcccccc'))[0],struct.unpack('>f',bytes.fromhex('3dccccce'))[0],1.,-1.,3.4028234663852886e38]):
  add('float-input-'+str(i),input_f32_bits=list(map(fbits,[v,-v,v])),jumping=False,ticks=[{}, {}, {}])
 rng=random.Random(SEED);base=[block([x,0,z]) for x in range(-3,4) for z in range(-3,4)]
 worlds={'free':[],'floor':base,'wall':base+[block([1,1,z]) for z in range(-3,4)],'corner':base+[block([1,1,z]) for z in range(-3,4)]+[block([x,1,1]) for x in range(-3,4)],'ceiling':base+[block([x,3,z]) for x in range(-3,4) for z in range(-3,4)],'step':base+[block([1,1,0])],'step_ceiling':base+[block([1,1,0]),block([1,3,0])]}
 for material in ['minecraft:stone','minecraft:dirt','minecraft:oak_planks','minecraft:ice','minecraft:blue_ice']:
  for sprint in [False,True]:add(material+'-'+str(sprint),world_blocks=[block([x,0,z],material) for x in range(-3,4) for z in range(-3,4)],sprinting=sprint,ticks=[{} for _ in range(20)])
 for i in range(256):
  grounded=rng.choice([False,True]);updates=[]
  for k in range(8):
   u={}
   if rng.randrange(3)==0:u['input_f32_bits']=[fbits(rng.uniform(-1.,1.)) for _ in range(3)]
   if rng.randrange(3)==0:u['jumping']=rng.choice([False,True])
   if rng.randrange(5)==0:u['sprinting']=rng.choice([False,True])
   updates.append(u)
  add('random-'+str(i),position=list(map(bits,[rng.uniform(.35,.65),1. if grounded else rng.choice([1.,1.2,2.5,3.]),rng.uniform(.35,.65)])),velocity=[bits(rng.uniform(-.3,.3)) for _ in range(3)],grounded=grounded,input_f32_bits=[fbits(rng.uniform(-1.,1.)) for _ in range(3)],jumping=rng.choice([False,True]),sprinting=rng.choice([False,True]),no_gravity=rng.choice([False,True]),discard_friction=rng.choice([False,True]),yaw_f32_bits=fbits(rng.uniform(-1e6,1e6)),movement_speed=bits(rng.uniform(0.,.3)),gravity=bits(rng.uniform(-.1,.1)),friction_modifier=bits(rng.uniform(0.,4.)),air_drag_modifier=bits(rng.uniform(0.,5.)),step_height=bits(rng.choice([0.,.6,1.])),jump_strength=bits(rng.choice([0.,threshold,.42,1.])),jump_delay=rng.randrange(12),jump_trigger=rng.randrange(12),needs_sync=rng.choice([False,True]),world_blocks=rng.choice(list(worlds.values())),ticks=updates)
 return cases

def generate_jump_inputs():
 cases=[]
 worlds={'unit':[block([0,0,0])],'below-honey':[block([0,0,0],'minecraft:honey_block')],'current-honey':[block([0,0,0]),block([0,1,0],'minecraft:honey_block')],'both-honey':[block([0,0,0],'minecraft:honey_block'),block([0,1,0],'minecraft:honey_block')],'current-slime-below-honey':[block([0,0,0],'minecraft:honey_block'),block([0,1,0],'minecraft:slime_block')]}
 for name,world in worlds.items():
  for strength in [0.,1e-5,struct.unpack('>f',(925353389).to_bytes(4,'big'))[0],.42,.84000001,32.]:
   for sprint in [False,True]:
    v={'position':list(map(bits,[.5,1.,.5])),'velocity':list(map(bits,[.1,.7,-.2])),'jump_strength':bits(strength),'yaw_f32_bits':fbits(45.),'sprinting':sprint,'needs_sync':False,'world_blocks':world}
    cases.append({'id':f'jump-factor:{name}-{bits(strength)}-{sprint}','operation':'jump_only','input':v,'tags':['actual_jump_from_ground','block_factor_priority','numerical_helper_only']})
 return cases

def run_java(inputs,jars,suffix=''):
 d=ROOT/'reference/extracted/player_tick_probe';d.mkdir(parents=True,exist_ok=True);classes=d/'classes';classes.mkdir(exist_ok=True)
 sources=[]
 for name,source in [('ReferenceMovementProbe',MOVEMENT_SOURCE),('ReferenceDirectMovementProbe',DIRECT_SOURCE),('ReferenceTravelProbe',TRAVEL_SOURCE),('ReferencePlayerTickProbe',SOURCE)]:
  path=d/(name+'.java');path.write_text(source);sources.append(path)
 cp=':'.join(map(str,jars));command=[str(JAVA.parent/'javac'),'-cp',cp,'-d',str(classes),*map(str,sources)]
 start=time.monotonic();r=subprocess.run(command,capture_output=True,text=True);compile_seconds=time.monotonic()-start;(ROOT/f'reference/cache/player-tick-javac{suffix}.log').write_text(r.stdout+r.stderr);r.check_returncode()
 incoming=ROOT/f'reference/cache/player-tick-input{suffix}.jsonl';outgoing=ROOT/f'reference/cache/player-tick-observed{suffix}.jsonl';incoming.write_text(''.join(canonical(c).decode()+'\n' for c in inputs))
 command=[str(JAVA),'-cp',str(classes)+':'+cp,'ReferencePlayerTickProbe',str(incoming),str(outgoing)];start=time.monotonic();r=subprocess.run(command,capture_output=True,text=True);seconds=time.monotonic()-start;log=ROOT/f'reference/cache/player-tick-java{suffix}.log';log.write_text(r.stdout+r.stderr);r.check_returncode()
 return [json.loads(line) for line in outgoing.read_text().splitlines()],{'compile_seconds':round(compile_seconds,6),'java_seconds':round(seconds,6),'command':command,'log':fingerprint(log)}

def source_inventory(jars):
 result=travel_inventory(jars);extra=['net.minecraft.world.entity.player.Inventory','net.minecraft.world.entity.EntityEquipment','net.minecraft.world.scores.Scoreboard','net.minecraft.world.entity.EntitySelector','net.minecraft.world.level.block.state.BlockBehaviour','net.minecraft.world.entity.InsideBlockEffectApplier$StepBasedCollector']
 owners=['net.minecraft.world.entity.Entity','net.minecraft.world.entity.LivingEntity','net.minecraft.world.entity.player.Player',*extra]
 wanted={'aiStep','applyInput','jumpFromGround','getJumpPower','getJumpBoostPower','getBlockJumpFactor','isImmobile','serverAiStep','pushEntities','applyEffectsFromBlocks','checkInsideBlocks','tickRegeneration','handleShoulderEntities','tick','setSpeed'}
 with zipfile.ZipFile(jars[0]) as archive:
  for owner in owners:
   entry=owner.replace('.','/')+'.class';text=subprocess.run([str(JAVA.parent/'javap'),'-classpath',str(jars[0]),'-c','-p',owner],capture_output=True,text=True,check=True).stdout
   value=result['classes'].setdefault(owner,{'class_entry':entry,'class_sha256':hashlib.sha256(archive.read(entry)).hexdigest(),'methods':[]})
   value['complete_bytecode_text_sha256']=hashlib.sha256(text.encode()).hexdigest();existing={m['signature'] for m in value['methods']}
   for part in re.split(r'(?=^  (?:public|private|protected|static).*(?:;|\{)$)',text,flags=re.M):
    signature=part.splitlines()[0].strip()
    if signature not in existing and any(re.search(r'\b'+re.escape(m)+r'\(',signature) for m in wanted):value['methods'].append({'signature':signature,'bytecode_text_sha256':hashlib.sha256(part.encode()).hexdigest(),'direct_call_references':sorted(set(re.findall(r'// (?:InterfaceMethod|Method) (.+)',part)))})
 return result

def validate(data,observed=None):
 assert data['pin']=='26.3' and data['schema_version']==1
 assert data['cases_sha256']==hashlib.sha256(canonical(data['cases'])).hexdigest(),'case checksum'
 assert [{k:c[k] for k in ['id','operation','input','tags']} for c in data['cases']]==generate_inputs(),'input regeneration'
 assert [{k:c[k] for k in ['id','operation','input','tags']} for c in data['jump_cases']]==generate_jump_inputs(),'jump input regeneration'
 assert data['jump_cases_sha256']==hashlib.sha256(canonical(data['jump_cases'])).hexdigest(),'jump case checksum'
 assert all(t['observation']['full_player_ai_step_executed'] for c in data['cases'] for t in c['ticks'])
 if observed is not None:assert ([{k:c[k] for k in ['id','ticks']} for c in data['cases']]+[{k:c[k] for k in ['id','expected','observation']} for c in data['jump_cases']])==observed,'independent actual aiStep/jump outputs'
 return {'sequences':len(data['cases']),'actual_player_ai_step_calls':sum(len(c['ticks']) for c in data['cases']),'direct_jump_factor_cases':len(data['jump_cases']),'oracle_compared':observed is not None}

def extract():
 jars,release=verified_classpath();inputs=generate_inputs();jump_inputs=generate_jump_inputs();observed,execution=run_java(inputs+jump_inputs,jars);cases=[{**i,**o} for i,o in zip(inputs,observed[:len(inputs)],strict=True)];jump_cases=[{**i,**o} for i,o in zip(jump_inputs,observed[len(inputs):],strict=True)]
 runtime=subprocess.run([str(JAVA),'-version'],capture_output=True,text=True,check=True)
 data={'schema_version':1,'pin':'26.3','random_input_seed':SEED,'cases':cases,'cases_sha256':hashlib.sha256(canonical(cases)).hexdigest(),'server_bundle_sha256':release['server_bundle']['sha256'],'server_class_jar_sha256':release['server_bundle']['nested_server_sha256'],'runtime_executable':fingerprint(JAVA),'runtime_version':(runtime.stdout+runtime.stderr).strip().splitlines(),'classpath_libraries':[fingerprint(p) for p in jars[1:]],'probe_java_source_sha256':hashlib.sha256((MOVEMENT_SOURCE+DIRECT_SOURCE+TRAVEL_SOURCE+SOURCE).encode()).hexdigest(),'source':source_inventory(jars),'scope':'Direct untouched actual Player.aiStep/LivingEntity.aiStep, jumpFromGround, Player.travel and Entity.move, in a finite real Level; motion/input/counter/sync/head-yaw/stored-speed projection only','confidence':'high for recorded neutral projected aiStep cases; full Player tick/LocalPlayer control and other mutated entity fields remain incomplete',
 'fixture_boundary':{'base':'ReferenceTravelProbe real Player/Level fixture and exact declared authority, suppressed bounce, no-emission, no-fluid LevelChunk boundaries retained',
 'additional_level_services':{'getScoreboard':'Actual empty Scoreboard, no teams; production EntitySelector.pushableBy and Level.getPushableEntities execute','getEntities(Entity,AABB,Predicate)':'Empty list in actor-free finite world, so production push/touch loops are empty'},
 'additional_entity_return_or_algorithm_overrides':[],
 'observers_call_super':['applyInput','getBlockJumpFactor','getJumpPower','jumpFromGround','getBlockPosBelowThatAffectsMyMovement','travel','setSpeed'],
 'untouched':['Player.aiStep','LivingEntity.aiStep','LivingEntity.applyInput','LivingEntity.jumpFromGround','LivingEntity.getJumpPower','Entity.getBlockJumpFactor','Entity.applyEffectsFromBlocks/checkInsideBlocks','LivingEntity.pushEntities','Level.getPushableEntities','Player inventory/equipment ticks','Player travel and actual Entity.move'],
 'neutral_guards':['simulation and effective AI and local authority','no interpolation or head interpolation','alive and awake','empty inventory/equipment','no active effects, fluid, powder snow, climb, flight/glide, passenger, auto-spin','dry weather','empty nearby actors/teams','only stone/dirt/oak_planks/ice/blue_ice; no slime/honey/hazard step/inside effects'],
 'projection':'Body position/AABB/velocity/dimensions/major flags, float xxa/yya/zza, jumping, signed noJumpDelay/jumpTriggerTime, needsSync, stored speed, head yaw. Excludes fall/fire/health/effect/animation bookkeeping and full tick state.'}}
 data['jump_cases']=jump_cases;data['jump_cases_sha256']=hashlib.sha256(canonical(jump_cases)).hexdigest();data['fixture_boundary']['jump_only_boundary']='Additional standalone untouched actual jumpFromGround/getJumpPower/getBlockJumpFactor calls cover honey/slime factor priority and float power; these do not execute travel/block effects and establish no honey/slime aiStep admission.'
 write_json(OUTPUT,data);e={'status':'passed','reference':fingerprint(OUTPUT),'execution':execution,'validation':validate(data,observed)};write_json(ROOT/'evidence/player-tick-reference.json',e)
 first=cases[0];write_json(ROOT/'evidence/player-tick-first-reference.json',{'status':'passed','sequence':first['id'],'actual_player_ai_step_calls':len(first['ticks']),'case_sha256':hashlib.sha256(canonical(first)).hexdigest(),'tick_summaries':[{'tick':i+1,'position':t['expected']['position'],'jump_delay':t['expected']['jump_delay'],'grounded':t['expected']['flags'][0],'jump_called':'jump_after' in t['observation']} for i,t in enumerate(first['ticks'])],'reference':fingerprint(OUTPUT)})
 return e

def verify():
 jars,release=verified_classpath();data=json.loads(OUTPUT.read_text());assert data['server_class_jar_sha256']==release['server_bundle']['nested_server_sha256'];assert data['source']==source_inventory(jars);assert data['runtime_executable']==fingerprint(JAVA);assert data['classpath_libraries']==[fingerprint(p) for p in jars[1:]];assert data['probe_java_source_sha256']==hashlib.sha256((MOVEMENT_SOURCE+DIRECT_SOURCE+TRAVEL_SOURCE+SOURCE).encode()).hexdigest()
 observed=[json.loads(line) for line in (ROOT/'reference/cache/player-tick-observed.jsonl').read_text().splitlines()];e={'status':'passed','validation':validate(data,observed),'official_class_runtime_library_hashes_checked':True};write_json(ROOT/'evidence/player-tick-reference-validation.json',e);return e

def selftest():
 jars,_=verified_classpath();data=json.loads(OUTPUT.read_text());inputs=generate_inputs()+generate_jump_inputs();one,r1=run_java(inputs,jars,'-selftest1');two,r2=run_java(inputs,jars,'-selftest2');assert one==two;validate(data,one);validate(data,two);failures=[]
 for component,reseal in [('tick',False),('tick',True),('jump',False),('jump',True)]:
  bad=copy.deepcopy(data)
  if component=='tick':bad['cases'][0]['ticks'][1]['expected']['jump_delay']=123
  else:bad['jump_cases'][0]['expected']['power_f32_bits']='3f800000'
  if reseal:
   key='cases' if component=='tick' else 'jump_cases';bad[key+'_sha256']=hashlib.sha256(canonical(bad[key])).hexdigest()
  try:validate(bad,one)
  except AssertionError as error:failures.append({'component':component,'resealed':reseal,'rejected':True,'reason':str(error)})
  else:raise AssertionError('Corrupt tick accepted')
 e={'status':'passed','independent_java_runs':2,'validation':validate(data,one),'failure_injections':failures,'executions':[r1,r2]};write_json(ROOT/'evidence/player-tick-reference-selftest.json',e);return e

def main():
 p=argparse.ArgumentParser();p.add_argument('--verify-existing',action='store_true');p.add_argument('--selftest',action='store_true');a=p.parse_args();e=selftest() if a.selftest else verify() if a.verify_existing else extract();print(json.dumps({k:v for k,v in e.items() if k not in ['execution','executions']},indent=2))
if __name__=='__main__':main()
