#!/usr/bin/env python3
"""Direct pinned Player/LivingEntity dry-air travel instrument."""
from __future__ import annotations
import argparse, collections, copy, hashlib, json, math, random, re, struct, subprocess, time, zipfile
from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_block_probe import verified_classpath
from reference_movement_probe import SOURCE as MOVEMENT_SOURCE, DIRECT_SOURCE
from reference_locomotion_probe import source_inventory as locomotion_inventory
OUTPUT=ROOT/'reference/travel.json'
SEED=263_104_05
SOURCE=r'''
import java.io.*;
import java.nio.file.*;
import java.lang.reflect.*;
import java.util.*;
import com.google.gson.*;
import com.mojang.authlib.GameProfile;
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
import net.minecraft.world.effect.*;
import net.minecraft.world.phys.*;
public class ReferenceTravelProbe {
 static final Gson JSON=new Gson();
 static class FixtureLevel extends ReferenceDirectMovementProbe.FixtureLevel {
  final Map<net.minecraft.world.level.ChunkPos,net.minecraft.world.level.chunk.LevelChunk> chunks=new HashMap<>();
  public net.minecraft.world.level.chunk.ChunkAccess getChunk(int x,int z,net.minecraft.world.level.chunk.status.ChunkStatus status,boolean required){
   boolean fluid=StackWalker.getInstance().walk(s->s.anyMatch(f->f.getClassName().equals("net.minecraft.world.entity.EntityFluidInteraction")&&f.getMethodName().equals("hasFluidAndLoaded")));
   if(!fluid)throw new IllegalStateException("Unexpected non-fluid getChunk use");
   hit("getChunk_dry_sections");return chunks.computeIfAbsent(new net.minecraft.world.level.ChunkPos(x,z),key->new net.minecraft.world.level.chunk.LevelChunk(this,key));
  }
 }
 static class FixturePlayer extends Player {
  Vec3 requested,postMoveVelocity,recorded;Map<String,Object> postMoveBody;BlockPos sampledBelow;float sampledSpeed,sampledFlying,sampledAcceleration;
  final Map<String,Integer> observations=new TreeMap<>();
  FixturePlayer(Level l){super(l,new GameProfile(new UUID(0,263),"TravelFixture"));}
  void hit(String s){observations.merge(s,1,Integer::sum);}
  public GameType gameMode(){return GameType.SURVIVAL;}
  public boolean isClientAuthoritative(){hit("authority_contract");return false;}
  protected MovementEmission getMovementEmission(){return MovementEmission.NONE;}
  public boolean isSuppressingBounce(){hit("isSuppressingBounce");return true;}
  public BlockPos getBlockPosBelowThatAffectsMyMovement(){hit("below_position");return sampledBelow=super.getBlockPosBelowThatAffectsMyMovement();}
  public float getSpeed(){hit("getSpeed");return sampledSpeed=super.getSpeed();}
  protected float getFlyingSpeed(){hit("getFlyingSpeed");return sampledFlying=super.getFlyingSpeed();}
  public void moveRelative(float speed,Vec3 input){hit("moveRelative_observer");sampledAcceleration=speed;super.moveRelative(speed,input);}
  public void recordMovement(MoverType t,Vec3 v){recorded=v;super.recordMovement(t,v);}
  public void move(MoverType t,Vec3 v){hit("move_observer");requested=v;super.move(t,v);postMoveVelocity=getDeltaMovement();postMoveBody=body(this);}
 }
 static String fb(float v){return String.format(Locale.ROOT,"%08x",Float.floatToRawIntBits(v));}
 static Map<String,Object> body(Entity e){return Map.of("position",ReferenceMovementProbe.vectorBits(e.position()),"box",ReferenceMovementProbe.boxBits(e.getBoundingBox()),"velocity",ReferenceMovementProbe.vectorBits(e.getDeltaMovement()),"width_f32_bits",fb(e.getDimensions(e.getPose()).width()),"height_f32_bits",fb(e.getDimensions(e.getPose()).height()),"flags",List.of(e.onGround(),e.horizontalCollision,e.verticalCollision,e.verticalCollisionBelow));}
 static void attribute(FixturePlayer p,Holder<Attribute> a,JsonObject in,String key){p.getAttribute(a).setBaseValue(ReferenceMovementProbe.d(in.get(key)));}
 static Map<String,Object> observe(JsonObject c)throws Exception{
  ReferenceDirectMovementProbe.initialize();JsonObject in=c.getAsJsonObject("input");var level=new FixtureLevel();
  for(JsonElement item:in.getAsJsonArray("world_blocks")){
   JsonObject b=item.getAsJsonObject();JsonArray pos=b.getAsJsonArray("position");var block=BuiltInRegistries.BLOCK.getValue(Identifier.parse(b.get("identifier").getAsString()));
   if(block!=Blocks.STONE&&block!=Blocks.DIRT&&block!=Blocks.OAK_PLANKS&&block!=Blocks.ICE&&block!=Blocks.BLUE_ICE&&block!=Blocks.SLIME_BLOCK)throw new IllegalArgumentException("Unsupported fixture block");
   level.blocks.put(new BlockPos(pos.get(0).getAsInt(),pos.get(1).getAsInt(),pos.get(2).getAsInt()),block.defaultBlockState());
  }
  FixturePlayer p=new FixturePlayer(level);p.setPos(ReferenceMovementProbe.vector(in.getAsJsonArray("position")));p.setOnGround(in.get("grounded").getAsBoolean());
  attribute(p,Attributes.MOVEMENT_SPEED,in,"movement_speed");attribute(p,Attributes.GRAVITY,in,"gravity");attribute(p,Attributes.FRICTION_MODIFIER,in,"friction_modifier");attribute(p,Attributes.AIR_DRAG_MODIFIER,in,"air_drag_modifier");attribute(p,Attributes.STEP_HEIGHT,in,"step_height");
  p.setSprinting(in.get("sprinting").getAsBoolean());p.setNoGravity(in.get("no_gravity").getAsBoolean());p.setDiscardFriction(in.get("discard_friction").getAsBoolean());p.setYRot(ReferenceMovementProbe.f(in.get("yaw_f32_bits")));
  p.setDeltaMovement(ReferenceMovementProbe.vector(in.getAsJsonArray("velocity")));
  if(!p.canSimulateMovement()||!p.isLocalInstanceAuthoritative()||p.isPassenger()||p.isSwimming()||p.isFallFlying()||p.getAbilities().flying||p.onClimbable()||!p.getActiveEffects().isEmpty())throw new AssertionError("Dry-air context not established: "+List.of(p.canSimulateMovement(),p.isLocalInstanceAuthoritative(),p.isPassenger(),p.isSwimming(),p.isFallFlying(),p.getAbilities().flying,p.onClimbable(),!p.getActiveEffects().isEmpty()));
  Map<String,Object> actual=new TreeMap<>(body(p));actual.put("movement_speed",ReferenceMovementProbe.bits(p.getAttributeValue(Attributes.MOVEMENT_SPEED)));actual.put("gravity",ReferenceMovementProbe.bits(p.getAttributeValue(Attributes.GRAVITY)));actual.put("friction_modifier",ReferenceMovementProbe.bits(p.getAttributeValue(Attributes.FRICTION_MODIFIER)));actual.put("air_drag_modifier",ReferenceMovementProbe.bits(p.getAttributeValue(Attributes.AIR_DRAG_MODIFIER)));actual.put("maximum_f32_bits",fb(p.maxUpStep()));
  p.observations.clear();level.clearTrace();p.travel(ReferenceMovementProbe.vector(in.getAsJsonArray("input")));
  if(p.requested==null||p.postMoveVelocity==null||p.sampledBelow==null)throw new AssertionError("Actual dry-air travel path not executed");
  if(p.isInLiquid()||p.onClimbable()||p.wasInPowderSnow)throw new AssertionError("Movement left declared dry-air context");
  var initial=level.initial.isEmpty()?List.<net.minecraft.world.phys.shapes.VoxelShape>of():level.initial.getFirst();var step=level.step.isEmpty()?List.<net.minecraft.world.phys.shapes.VoxelShape>of():level.step.getFirst();
  actual.put("initial",ReferenceDirectMovementProbe.shapeInputs(initial));actual.put("step",ReferenceDirectMovementProbe.shapeInputs(step));
  float blockFriction=level.getBlockState(p.sampledBelow).getBlock().getFriction();actual.put("block_friction_f32_bits",fb(blockFriction));
  Method modified=LivingEntity.class.getDeclaredMethod("computeModifiedFriction",float.class,float.class);modified.setAccessible(true);
  float friction=in.get("grounded").getAsBoolean()?(float)modified.invoke(null,blockFriction,(float)p.getAttributeValue(Attributes.FRICTION_MODIFIER)):1.0f;
  Map<String,Object> observed=new TreeMap<>();observed.put("actual_input",actual);observed.put("requested",ReferenceMovementProbe.vectorBits(p.requested));observed.put("post_move_velocity",ReferenceMovementProbe.vectorBits(p.postMoveVelocity));observed.put("post_move_body",p.postMoveBody);observed.put("below_position",List.of(p.sampledBelow.getX(),p.sampledBelow.getY(),p.sampledBelow.getZ()));observed.put("movement_recorded",p.recorded!=null);observed.put("colliders_queries",List.copyOf(level.queries));observed.put("fixture_service_calls",new TreeMap<>(level.calls));observed.put("observer_calls",new TreeMap<>(p.observations));observed.put("sampled_speed_f32_bits",fb(p.sampledSpeed));observed.put("sampled_flying_f32_bits",fb(p.sampledFlying));observed.put("acceleration_f32_bits",fb(p.sampledAcceleration));observed.put("friction_f32_bits",fb(friction));observed.put("full_player_travel_executed",true);
  return Map.of("id",c.get("id").getAsString(),"expected",body(p),"observation",observed);
 }
 public static void main(String[]args)throws Exception{SharedConstants.tryDetectVersion();Bootstrap.bootStrap();try(BufferedReader r=Files.newBufferedReader(Path.of(args[0]));PrintWriter w=new PrintWriter(Files.newBufferedWriter(Path.of(args[1])))){for(String line;(line=r.readLine())!=null;)w.println(JSON.toJson(observe(JsonParser.parseString(line).getAsJsonObject())));if(w.checkError())throw new IOException("Observation write failed");}}
}
'''

def bits(v):return struct.pack('>d',v).hex()
def fbits(v):return struct.pack('>f',v).hex()
def block(position,identifier='minecraft:stone'):return {'position':position,'identifier':identifier}
def generate_inputs():
 cases=[];rng=random.Random(SEED)
 def add(label,**changes):
  v={'position':[bits(x) for x in [.5,1.,.5]],'velocity':[bits(0.)]*3,'input':[bits(0.),bits(0.),bits(1.)],'grounded':True,'sprinting':False,'no_gravity':False,'discard_friction':False,'yaw_f32_bits':fbits(0.),'movement_speed':bits(.1),'gravity':bits(.08),'friction_modifier':bits(1.),'air_drag_modifier':bits(1.),'step_height':bits(.6),'world_blocks':[block([x,0,z]) for x in range(-3,4) for z in range(-3,4)]}
  v.update(changes);cases.append({'id':'travel:'+label,'operation':'player_travel','input':v,'tags':['actual_player_travel','dry_air']})
 add('first')
 materials=['minecraft:stone','minecraft:dirt','minecraft:oak_planks','minecraft:ice','minecraft:blue_ice','minecraft:slime_block']
 for m in materials:
  floor=[block([x,0,z],m) for x in range(-3,4) for z in range(-3,4)]
  for grounded in [False,True]:
   for modifier in [0.,.5,1.,2.5,2048.]:
    for drag in [0.,1.,50.]:
     add(f'{m}-{grounded}-{modifier}-{drag}',world_blocks=floor,grounded=grounded,friction_modifier=bits(modifier),air_drag_modifier=bits(drag),velocity=list(map(bits,[.15,-.05,-.2])),input=list(map(bits,[1.,.25,1.])),yaw_f32_bits=fbits(45.))
 base=[block([x,0,z]) for x in range(-3,4) for z in range(-3,4)]
 worlds={'free':[],'floor':base,'wall':base+[block([1,1,z]) for z in range(-3,4)],'corner':base+[block([1,1,z]) for z in range(-3,4)]+[block([x,1,1]) for x in range(-3,4)],'ceiling':base+[block([x,3,z]) for x in range(-3,4) for z in range(-3,4)],'step':base+[block([1,1,0])],'step_ceiling':base+[block([1,1,0]),block([1,3,0])]}
 for w,blocks in worlds.items():
  for i,(vx,vy,vz) in enumerate([(0.,0.,0.),(.5,-.1,0.),(.5,-.1,.4),(0.,.5,0.),(-.8,-.5,.2),(-0.,-0.,-0.),(1e-7,-1e-7,0.)]):
   for maximum in [0.,.6,1.]:
    add(f'{w}-{i}-{maximum}',world_blocks=blocks,velocity=list(map(bits,[vx,vy,vz])),input=list(map(bits,[0.,0.,0.])),step_height=bits(maximum))
 for gravity in [-1.,-.08,-0.,0.,.08,1.]:
  for discard in [False,True]:
   for no_gravity in [False,True]:
    for sprinting in [False,True]:
     add(f'gravity-{gravity}-{discard}-{no_gravity}-{sprinting}',gravity=bits(gravity),discard_friction=discard,no_gravity=no_gravity,sprinting=sprinting,grounded=False,position=list(map(bits,[.5,3.,.5])),velocity=list(map(bits,[.2,-.1,.3])))
 for i,y in enumerate([math.nextafter(1.,0.),1.,math.nextafter(1.,math.inf),2.**24,-2.**24]):
  add('position-'+str(i),position=list(map(bits,[-0.,y,-0.])),world_blocks=base if abs(y)<2. else [],grounded=abs(y)<2.,input=list(map(bits,[0.,0.,0.])),velocity=list(map(bits,[-0.,-0.,-0.])))
 for i,speed in enumerate([0.,math.ulp(0.),1e-50,math.nextafter(.1,0.),.1,math.nextafter(.1,math.inf),1.,1024.]):
  for yaw in [0.,-0.,90.,-90.,360.,1e30,-1e30]:add(f'speed-yaw-{i}-{yaw}',movement_speed=bits(speed),yaw_f32_bits=fbits(yaw))
 for i in range(768):
  w=rng.choice(list(worlds));grounded=rng.choice([True,False]);y=1. if grounded else rng.choice([1.,1.2,2.5,3.])
  add('random-'+str(i),world_blocks=worlds[w],grounded=grounded,position=list(map(bits,[rng.uniform(.35,.65),y,rng.uniform(.35,.65)])),velocity=[bits(rng.uniform(-.8,.8)) for _ in range(3)],input=[bits(rng.uniform(-2.,2.)) for _ in range(3)],yaw_f32_bits=fbits(rng.uniform(-1e6,1e6)),movement_speed=bits(rng.uniform(0.,1.)),gravity=bits(rng.uniform(-.1,.1)),friction_modifier=bits(rng.uniform(0.,4.)),air_drag_modifier=bits(rng.uniform(0.,5.)),step_height=bits(rng.choice([0.,.6,1.])),sprinting=rng.choice([True,False]),no_gravity=rng.choice([True,False]),discard_friction=rng.choice([True,False]))
 return cases

def run_java(inputs,jars,suffix=''):
 d=ROOT/'reference/extracted/travel_probe';d.mkdir(parents=True,exist_ok=True);classes=d/'classes';classes.mkdir(exist_ok=True)
 sources=[]
 for name,text in [('ReferenceMovementProbe',MOVEMENT_SOURCE),('ReferenceDirectMovementProbe',DIRECT_SOURCE),('ReferenceTravelProbe',SOURCE)]:
  p=d/(name+'.java');p.write_text(text);sources.append(p)
 cp=':'.join(map(str,jars));compile_command=[str(JAVA.parent/'javac'),'-cp',cp,'-d',str(classes),*map(str,sources)]
 start=time.monotonic();r=subprocess.run(compile_command,capture_output=True,text=True);compile_seconds=time.monotonic()-start;(ROOT/f'reference/cache/travel-javac{suffix}.log').write_text(r.stdout+r.stderr);r.check_returncode()
 incoming=ROOT/f'reference/cache/travel-input{suffix}.jsonl';outgoing=ROOT/f'reference/cache/travel-observed{suffix}.jsonl';incoming.write_text(''.join(canonical(c).decode()+'\n' for c in inputs))
 command=[str(JAVA),'-cp',str(classes)+':'+cp,'ReferenceTravelProbe',str(incoming),str(outgoing)]
 start=time.monotonic();r=subprocess.run(command,capture_output=True,text=True);seconds=time.monotonic()-start;log=ROOT/f'reference/cache/travel-java{suffix}.log';log.write_text(r.stdout+r.stderr);r.check_returncode()
 observed=[json.loads(line) for line in outgoing.read_text().splitlines()];assert [c['id'] for c in observed]==[c['id'] for c in inputs]
 return observed,{'compile_command':compile_command,'run_command':command,'compile_seconds':round(compile_seconds,6),'java_seconds':round(seconds,6),'java_log_sha256':fingerprint(log)['sha256'],'observation_jsonl_sha256':fingerprint(outgoing)['sha256']}

def source_inventory(jars):
 result=locomotion_inventory(jars)
 extras=['net.minecraft.world.entity.ai.attributes.AttributeMap','net.minecraft.world.entity.ai.attributes.AttributeInstance','net.minecraft.world.entity.ai.attributes.DefaultAttributes','net.minecraft.world.level.block.Block','net.minecraft.world.entity.player.Abilities',
         'net.minecraft.world.entity.EntityFluidInteraction','net.minecraft.world.level.chunk.LevelChunk','net.minecraft.world.level.chunk.LevelChunkSection','net.minecraft.world.level.chunk.ChunkAccess','net.minecraft.world.level.Level','net.minecraft.world.level.BlockCollisions','net.minecraft.world.level.CollisionGetter']
 with zipfile.ZipFile(jars[0]) as archive:
  for owner in extras:
   entry=owner.replace('.','/')+'.class';s=subprocess.run([str(JAVA.parent/'javap'),'-classpath',str(jars[0]),'-c','-p',owner],capture_output=True,text=True,check=True).stdout
   result['classes'][owner]={'class_entry':entry,'class_sha256':hashlib.sha256(archive.read(entry)).hexdigest(),'complete_bytecode_text_sha256':hashlib.sha256(s.encode()).hexdigest(),'methods':[]}
 return result
def validate(data,observed=None):
 assert data['pin']=='26.3';assert data['cases_sha256']==hashlib.sha256(canonical(data['cases'])).hexdigest(),'case checksum'
 assert [{k:c[k] for k in ['id','operation','input','tags']} for c in data['cases']]==generate_inputs(),'input regeneration'
 assert all(c['observation']['full_player_travel_executed'] for c in data['cases'])
 if observed is not None:assert [{k:c[k] for k in ['id','expected','observation']} for c in data['cases']]==observed,'independent actual travel outputs'
 return {'case_count':len(data['cases']),'full_player_travel_cases':len(data['cases']),'oracle_compared':observed is not None}
def extract():
 jars,release=verified_classpath();inputs=generate_inputs();observed,execution=run_java(inputs,jars);cases=[{**i,**o} for i,o in zip(inputs,observed,strict=True)]
 runtime=subprocess.run([str(JAVA),'-version'],capture_output=True,text=True,check=True)
 data={'schema_version':1,'pin':'26.3','random_input_seed':SEED,'cases':cases,'cases_sha256':hashlib.sha256(canonical(cases)).hexdigest(),'server_bundle_sha256':release['server_bundle']['sha256'],'server_class_jar_sha256':release['server_bundle']['nested_server_sha256'],'runtime_executable':fingerprint(JAVA),'runtime_version':(runtime.stdout+runtime.stderr).strip().splitlines(),'classpath_libraries':[fingerprint(p) for p in jars[1:]],'probe_java_source_sha256':hashlib.sha256((MOVEMENT_SOURCE+DIRECT_SOURCE+SOURCE).encode()).hexdigest(),'source':source_inventory(jars),'scope':'Direct untouched actual Player.travel and inherited LivingEntity.travel/travelInAir, actual attributes and actual Entity.move in finite real Level; no composed travel oracle','confidence':'high for recorded neutral dry-air Player cases; full Player tick/server-world/fluid/hazard travel incomplete',
 'fixture_boundary':{'entity_class':'FixturePlayer extends actual Player; actual Player/Avatar/LivingEntity constructors, equipment, abilities, and AttributeMap use original built-in player attribute supplier','untouched':['Player.travel','LivingEntity.travel','LivingEntity.travelInAir','LivingEntity.handleRelativeFrictionAndCalculateMovement','Entity.move','Entity.collide','LivingEntity.checkFallDamage','EntityFluidInteraction.update/hasFluidAndLoaded','Player.getSpeed','Player.getFlyingSpeed','AttributeInstance.getValue'],
 'constant_return_overrides':{'gameMode':'SURVIVAL, required abstract Player implementation','isClientAuthoritative':'false, selects locally authoritative server-side fixture; final Entity authority calculation executes','isSuppressingBounce':'true, neutral restitution context','getMovementEmission':'NONE, no sounds/events'},
 'observers_call_super':['getBlockPosBelowThatAffectsMyMovement','getSpeed','getFlyingSpeed','moveRelative','move','recordMovement'],
 'level_storage':'Reuses real Level superclass sparse map with actual default non-fluid full-cube block states and real BlockCollisions; otherwise AIR, no actors, distant WorldBorder',
 'chunk_boundary':'getChunk returns actual loaded LevelChunk objects with all-air/no-fluid sections solely for the executed fluid-presence checks. Sparse collision/friction map contains admitted non-fluid solids; the section no-fluid answer is therefore correct. No saved chunks or real ServerLevel.',
 'registry_boundary':'Original blocks/entities/attributes; official copied BIOME and DAMAGE_TYPE constructor registries bind tags empty, inherited movement fixture dimension data',
 'neutral_guards':['simulation allowed and locally authoritative','no passenger','no swimming/ability flight/fall flying','no liquids/climbable/powder snow','no MobEffects','unit block speed factor','finite current attributes','no edge sneak backoff'],
 'observations':'Expected Body read after complete actual travel; requested acceleration displacement captured before super.move; post-move Body captured immediately after super.move and before gravity/drag. Sampled friction independently observes actual private computeModifiedFriction; it does not determine expected final Body.'}}
 write_json(OUTPUT,data);e={'status':'passed','reference':fingerprint(OUTPUT),'execution':execution,'validation':validate(data,observed)};write_json(ROOT/'evidence/travel-reference.json',e);return e
def verify():
 jars,release=verified_classpath();data=json.loads(OUTPUT.read_text());assert data['server_class_jar_sha256']==release['server_bundle']['nested_server_sha256'];assert data['source']==source_inventory(jars);assert data['probe_java_source_sha256']==hashlib.sha256((MOVEMENT_SOURCE+DIRECT_SOURCE+SOURCE).encode()).hexdigest();assert data['runtime_executable']==fingerprint(JAVA)
 observed=[json.loads(line) for line in (ROOT/'reference/cache/travel-observed.jsonl').read_text().splitlines()];e={'status':'passed','validation':validate(data,observed),'official_class_and_runtime_hashes_checked':True};write_json(ROOT/'evidence/travel-reference-validation.json',e);return e
def selftest():
 jars,_=verified_classpath();data=json.loads(OUTPUT.read_text());one,r1=run_java(generate_inputs(),jars,'-selftest1');two,r2=run_java(generate_inputs(),jars,'-selftest2');assert one==two;validate(data,one);validate(data,two);failures=[]
 for reseal in [False,True]:
  bad=copy.deepcopy(data);bad['cases'][0]['expected']['velocity'][1]=bits(123.)
  if reseal:bad['cases_sha256']=hashlib.sha256(canonical(bad['cases'])).hexdigest()
  try:validate(bad,one)
  except AssertionError as err:failures.append({'resealed':reseal,'rejected':True,'reason':str(err)})
  else:raise AssertionError('Corruption accepted')
 e={'status':'passed','independent_java_runs':2,'case_count_per_run':len(one),'failure_injections':failures,'executions':[r1,r2]};write_json(ROOT/'evidence/travel-reference-selftest.json',e);return e
def main():
 p=argparse.ArgumentParser();p.add_argument('--verify-existing',action='store_true');p.add_argument('--selftest',action='store_true');a=p.parse_args();e=selftest() if a.selftest else verify() if a.verify_existing else extract();print(json.dumps({k:v for k,v in e.items() if k not in {'execution','executions'}},indent=2))
if __name__=='__main__':main()
