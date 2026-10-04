#!/usr/bin/env python3
"""Pinned original web/berry callbacks and actual stationary Entity dispatch."""
from __future__ import annotations
import argparse, copy, hashlib, json, math, re, struct, subprocess, time, zipfile
from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_block_probe import verified_classpath
from reference_movement_probe import SOURCE as MOVEMENT_SOURCE, DIRECT_SOURCE
from reference_travel_probe import SOURCE as TRAVEL_SOURCE

RAW = ROOT / 'build/player-block-inside-stuck/reference'
OUTPUT = ROOT / 'reference/player_block_inside_stuck.json'

SOURCE = r'''
import java.io.*;
import java.nio.file.*;
import java.lang.reflect.*;
import java.util.*;
import com.google.gson.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;
import net.minecraft.core.registries.*;
import net.minecraft.resources.*;
import net.minecraft.data.registries.VanillaRegistries;
import net.minecraft.world.entity.*;
import net.minecraft.world.entity.player.*;
import net.minecraft.world.effect.*;
import net.minecraft.world.item.*;
import net.minecraft.world.item.enchantment.*;
import net.minecraft.world.level.*;
import net.minecraft.world.level.block.*;
import net.minecraft.world.level.block.state.*;
import net.minecraft.world.phys.*;
import net.minecraft.world.phys.shapes.*;
public class ReferencePlayerBlockInsideStuckProbe {
 static final Gson JSON=new Gson();
 static final Field STUCK,GRACE;
 static {try{STUCK=Entity.class.getDeclaredField("stuckSpeedMultiplier");STUCK.setAccessible(true);GRACE=LivingEntity.class.getDeclaredField("currentImpulseContextResetGraceTime");GRACE.setAccessible(true);}catch(Exception e){throw new ExceptionInInitializerError(e);}}
 static Vec3 vec(JsonArray a){return ReferenceMovementProbe.vector(a);}
 static String bits(double v){return ReferenceMovementProbe.bits(v);}
 static Map<String,Object> state(BlockState s){
  Map<String,Object> m=new TreeMap<>();m.put("identifier",BuiltInRegistries.BLOCK.getKey(s.getBlock()).toString());
  if(s.is(Blocks.SWEET_BERRY_BUSH))m.put("age",s.getValue(SweetBerryBushBlock.AGE));return m;
 }
 static Vec3 stuck(Entity e){try{return (Vec3)STUCK.get(e);}catch(Exception x){throw new RuntimeException(x);}}
 static Map<String,Object> insideShape(BlockState s,Level level,BlockPos p,Entity e){VoxelShape shape=s.getEntityInsideCollisionShape(level,p,e);return Map.of("identity_block",shape==Shapes.block(),"boxes",shape.toAabbs().stream().map(ReferenceMovementProbe::boxBits).toList());}
 static Map<String,Object> snapshot(Entity e){
  Map<String,Object> m=new TreeMap<>();m.put("body",ReferenceTravelProbe.body(e));
  m.put("stuck_multiplier",ReferenceMovementProbe.vectorBits(stuck(e)));m.put("fall_distance",bits(e.fallDistance));
  m.put("removed",e.isRemoved());m.put("no_physics",e.noPhysics);m.put("living",e instanceof LivingEntity);
  m.put("entity_type",EntityType.getKey(e.getType()).toString());
  if(e instanceof LivingEntity living){m.put("weaving",living.hasEffect(MobEffects.WEAVING));
   ItemStack boots=living.getItemBySlot(EquipmentSlot.FEET);m.put("boots_item",BuiltInRegistries.ITEM.getKey(boots.getItem()).toString());
   m.put("boots_enchantment_count",boots.getEnchantments().entrySet().size());
   try{m.put("impulse_grace",GRACE.getInt(living));}catch(Exception x){throw new RuntimeException(x);}
   m.put("impulse_position",living.currentImpulseImpactPos==null?List.of():ReferenceMovementProbe.vectorBits(living.currentImpulseImpactPos));}
  if(e instanceof Player p)m.put("flying",p.getAbilities().flying);return m;
 }
 static class FixtureLevel extends ReferenceTravelProbe.FixtureLevel {
  final List<Map<String,Object>> insideReads=new ArrayList<>();
  public BlockState getBlockState(BlockPos p){BlockState s=super.getBlockState(p);
   boolean inside=StackWalker.getInstance().walk(st->st.anyMatch(f->f.getClassName().equals(Entity.class.getName())&&f.getMethodName().startsWith("lambda$checkInsideBlocks$")));
   if(inside)insideReads.add(Map.of("position",List.of(p.getX(),p.getY(),p.getZ()),"state",state(s)));return s;}
 }
 static class FixturePlayer extends ReferenceTravelProbe.FixturePlayer {
  final List<Map<String,Object>> setters=new ArrayList<>();final List<Map<String,Object>> callbacks=new ArrayList<>();
  int impulseTryCalls,impulseResetCalls;
  FixturePlayer(Level l){super(l);}
  public void tryResetCurrentImpulseContext(){impulseTryCalls++;super.tryResetCurrentImpulseContext();}
  public void resetCurrentImpulseContext(){impulseResetCalls++;super.resetCurrentImpulseContext();}
  public void makeStuckInBlock(BlockState s,Vec3 v){Map<String,Object> m=new TreeMap<>();m.put("state",state(s));m.put("argument",ReferenceMovementProbe.vectorBits(v));m.put("before",snapshot(this));super.makeStuckInBlock(s,v);m.put("after",snapshot(this));setters.add(m);}
  protected void onInsideBlock(BlockState s){callbacks.add(state(s));super.onInsideBlock(s);}
 }
 static class FixtureEntity extends ReferenceDirectMovementProbe.FixtureEntity {
  final List<Map<String,Object>> setters=new ArrayList<>();final List<Map<String,Object>> callbacks=new ArrayList<>();
  FixtureEntity(FixtureLevel l){super(l,EntityTypes.ARMOR_STAND,.6f);}
  public void makeStuckInBlock(BlockState s,Vec3 v){Map<String,Object> m=new TreeMap<>();m.put("state",state(s));m.put("argument",ReferenceMovementProbe.vectorBits(v));m.put("before",snapshot(this));super.makeStuckInBlock(s,v);m.put("after",snapshot(this));setters.add(m);}
  protected void onInsideBlock(BlockState s){callbacks.add(state(s));super.onInsideBlock(s);}
 }
 static BlockState block(JsonObject b){String id=b.get("identifier").getAsString();Block value=BuiltInRegistries.BLOCK.getValue(Identifier.parse(id));
  if(value!=Blocks.COBWEB&&value!=Blocks.SWEET_BERRY_BUSH&&value!=Blocks.AIR&&value!=Blocks.STONE)throw new IllegalArgumentException("Unsupported callback block: "+id);
  BlockState s=value.defaultBlockState();return value==Blocks.SWEET_BERRY_BUSH?s.setValue(SweetBerryBushBlock.AGE,b.get("age").getAsInt()):s;}
 static Map<String,Object> observe(JsonObject c)throws Exception{
  ReferenceDirectMovementProbe.initialize();JsonObject in=c.getAsJsonObject("input");FixtureLevel level=new FixtureLevel();
  Entity e=switch(in.get("receiver").getAsString()){
   case "player"->new FixturePlayer(level);case "nonliving"->new FixtureEntity(level);
   case "fox"->new net.minecraft.world.entity.animal.fox.Fox(EntityTypes.FOX,level);
   case "bee"->new net.minecraft.world.entity.animal.bee.Bee(EntityTypes.BEE,level);
   default->throw new IllegalArgumentException("Unknown receiver");};
  if(e==null)throw new AssertionError("Original entity factory returned null");
  e.setPos(vec(in.getAsJsonArray("position")));e.setOnGround(false);e.setDeltaMovement(vec(in.getAsJsonArray("velocity")));
  e.makeStuckInBlock(Blocks.AIR.defaultBlockState(),vec(in.getAsJsonArray("initial_multiplier")));
  e.fallDistance=ReferenceMovementProbe.d(in.get("fall_distance"));
  if(e instanceof LivingEntity living){
   String impulse=in.get("impulse").getAsString();
   if(!impulse.equals("empty")){living.setIgnoreFallDamageFromCurrentImpulse(true,new Vec3(2.,3.,4.));if(impulse.equals("ready"))living.setIgnoreFallDamageFromCurrentImpulse(false,null);}
   if(in.get("weaving").getAsBoolean())living.addEffect(new MobEffectInstance(MobEffects.WEAVING,200,0));
   String boots=in.get("boots").getAsString();if(!boots.equals("none")){
    ItemStack stack=new ItemStack(Items.LEATHER_BOOTS);
    if(boots.equals("frost_walker")){var enchantment=VanillaRegistries.createWorldLookup().lookupOrThrow(Registries.ENCHANTMENT).getOrThrow(Enchantments.FROST_WALKER);stack.enchant(enchantment,2);}
    living.setItemSlot(EquipmentSlot.FEET,stack);
   }
  }
  if(e instanceof Player p)p.getAbilities().flying=in.get("flying").getAsBoolean();
  e.noPhysics=in.get("no_physics").getAsBoolean();if(in.get("removed").getAsBoolean())e.setRemoved(Entity.RemovalReason.DISCARDED);
  if(e instanceof FixturePlayer p){p.setters.clear();p.callbacks.clear();p.impulseTryCalls=0;p.impulseResetCalls=0;}if(e instanceof FixtureEntity p){p.setters.clear();p.callbacks.clear();}
  Map<String,Object> initial=snapshot(e);List<Map<String,Object>> observations=new ArrayList<>();
  for(JsonElement stepValue:in.getAsJsonArray("steps")){
   JsonObject step=stepValue.getAsJsonObject();Map<String,Object> m=new TreeMap<>();m.put("before",snapshot(e));level.insideReads.clear();
   if(e instanceof FixturePlayer p){p.setters.clear();p.callbacks.clear();p.impulseTryCalls=0;p.impulseResetCalls=0;}if(e instanceof FixtureEntity p){p.setters.clear();p.callbacks.clear();}
   if(step.get("operation").getAsString().equals("callback")){
    JsonObject b=step.getAsJsonObject("block");JsonArray pos=b.getAsJsonArray("position");
    BlockState value=block(b);BlockPos p=new BlockPos(pos.get(0).getAsInt(),pos.get(1).getAsInt(),pos.get(2).getAsInt());m.put("entity_inside_shape",insideShape(value,level,p,e));
    value.entityInside(level,p,e,new InsideBlockEffectApplier.StepBasedCollector(),step.get("inside").getAsBoolean());
   }else if(step.get("operation").getAsString().equals("stationary_dispatch")){
    level.blocks.clear();for(JsonElement bValue:step.getAsJsonArray("world_blocks")){JsonObject b=bValue.getAsJsonObject();JsonArray p=b.getAsJsonArray("position");level.blocks.put(new BlockPos(p.get(0).getAsInt(),p.get(1).getAsInt(),p.get(2).getAsInt()),block(b));}
    e.applyEffectsFromBlocks(e.position(),e.position());
    m.put("entity_inside_shapes",level.insideReads.stream().filter(r->!((Map<?,?>)r.get("state")).get("identifier").equals("minecraft:air")).map(r->{List<?> p=(List<?>)r.get("position");BlockPos pos=new BlockPos((int)p.get(0),(int)p.get(1),(int)p.get(2));return Map.of("position",r.get("position"),"shape",insideShape(level.blocks.get(pos),level,pos,e));}).toList());
   }else throw new IllegalArgumentException("Unknown operation");
   m.put("after",snapshot(e));m.put("inside_reads",List.copyOf(level.insideReads));
   if(e instanceof FixturePlayer p){m.put("setters",List.copyOf(p.setters));m.put("callbacks",List.copyOf(p.callbacks));m.put("impulse_try_calls",p.impulseTryCalls);m.put("impulse_reset_calls",p.impulseResetCalls);}
   if(e instanceof FixtureEntity p){m.put("setters",List.copyOf(p.setters));m.put("callbacks",List.copyOf(p.callbacks));}
   observations.add(m);
  }
  return Map.of("id",c.get("id").getAsString(),"expected",Map.of("initial",initial,"steps",observations,"final",snapshot(e)),"observation",Map.of("original_callbacks_executed",true,"receiver_class",e.getClass().getName(),"normal_constructor",true,"level_is_serverlevel",false));
 }
 public static void main(String[]args)throws Exception{SharedConstants.tryDetectVersion();Bootstrap.bootStrap();var lookup=VanillaRegistries.createWorldLookup();for(var pending:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup))pending.forEach((holder,components)->holder.bindComponents(components));try(BufferedReader r=Files.newBufferedReader(Path.of(args[0]));PrintWriter w=new PrintWriter(Files.newBufferedWriter(Path.of(args[1])))){for(String line;(line=r.readLine())!=null;)w.println(JSON.toJson(observe(JsonParser.parseString(line).getAsJsonObject())));if(w.checkError())throw new IOException("Observation write failed");}}
}
'''

def sha(value): return hashlib.sha256(canonical(value)).hexdigest()
def bits(value): return struct.pack('>d',value).hex()
def block(identifier,position=(0,1,0),age=0):
    value={'identifier':'minecraft:'+identifier,'position':list(position)}
    if identifier=='sweet_berry_bush': value['age']=age
    return value
def callback(b,inside=True): return {'operation':'callback','block':b,'inside':inside}
def dispatch(blocks): return {'operation':'stationary_dispatch','world_blocks':blocks}
def generate_inputs():
    cases=[]
    def add(label,steps,tags,**changes):
        value={'receiver':'player','position':list(map(bits,[.5,1.,.5])),'velocity':list(map(bits,[.2,-.1,.3])),
               'initial_multiplier':list(map(bits,[.125,.25,.5])),'fall_distance':bits(3.5),
               'weaving':False,'flying':False,'boots':'none','no_physics':False,'removed':False,'impulse':'empty','steps':steps}
        value.update(changes);cases.append({'id':'block-inside-stuck:'+label,'input':value,'tags':tags})
    blocks=[block('cobweb'),*[block('sweet_berry_bush',age=age) for age in range(4)],block('stone'),block('air')]
    for i,b in enumerate(blocks):
        for weaving in [False,True]:
            for flying in [False,True]:
                for inside in [False,True]:
                    add(f'callback-player-{i}-{weaving}-{flying}-{inside}',[callback(b,inside)],['actual_callback','player','weaving','flying','boolean_argument'],
                        weaving=weaving,flying=flying,boots=['none','leather','frost_walker'][(i+int(inside))%3])
    for i,b in enumerate(blocks):
        for inside in [False,True]:add(f'callback-nonliving-{i}-{inside}',[callback(b,inside)],['actual_callback','nonliving'],receiver='nonliving')
    for receiver in ['fox','bee']:
        for weaving in [False,True]:
            add(f'callback-{receiver}-{weaving}',[callback(block('cobweb')),callback(block('sweet_berry_bush',age=3))],['actual_callback','real_living_immune_type'],receiver=receiver,weaving=weaving)
    for i,sequence in enumerate([[blocks[0],blocks[2],blocks[-1]],[blocks[2],blocks[0],blocks[-1]],[blocks[0],blocks[0],blocks[4]]]):
        for weaving in [False,True]:
            for flying in [False,True]:add(f'ordered-{i}-{weaving}-{flying}',[callback(b) for b in sequence],['repeated_callbacks','last_eligible_overwrites'],weaving=weaving,flying=flying)
    worlds=[[],[block('cobweb')],*[[block('sweet_berry_bush',age=age)] for age in range(4)],
            [block('cobweb',(0,1,0)),block('sweet_berry_bush',(1,1,0),3)],
            [block('sweet_berry_bush',(0,1,0),3),block('cobweb',(1,1,0))],[block('stone')]]
    for i,world in enumerate(worlds):
        for weaving in [False,True]:
            for flying in [False,True]:add(f'dispatch-{i}-{weaving}-{flying}',[dispatch(world),dispatch(world),dispatch([])],['actual_stationary_dispatch','repeated','retention','query_order'],weaving=weaving,flying=flying,position=list(map(bits,[1.,1.,.5])) if i in [6,7] else list(map(bits,[.5,1.,.5])))
    eps=struct.unpack('>f',struct.pack('>f',1e-5))[0]
    width=struct.unpack('>f',struct.pack('>f',.6))[0]
    edge=1.-width/2.+eps
    for i,x in enumerate([math.nextafter(edge,-math.inf),edge,math.nextafter(edge,math.inf),-edge]):
        add(f'boundary-{i}',[dispatch([block('cobweb'),block('sweet_berry_bush',(1,1,0),3)])],['deflated_query_boundary'],position=list(map(bits,[x,1.,.5])))
    for removed in [False,True]:
        for no_physics in [False,True]:add(f'dispatch-gate-{removed}-{no_physics}',[dispatch([block('cobweb')])],['actual_dispatch_gate'],removed=removed,no_physics=no_physics)
    for i,b in enumerate([blocks[0],blocks[2],blocks[-1]]):
        for impulse in ['ready','grace']:
            for flying in [False,True]:add(f'impulse-{i}-{impulse}-{flying}',[callback(b),callback(b)],['impulse_context','repeated_callbacks'],impulse=impulse,flying=flying)
    return cases

SOURCES={'ReferenceMovementProbe':MOVEMENT_SOURCE,'ReferenceDirectMovementProbe':DIRECT_SOURCE,'ReferenceTravelProbe':TRAVEL_SOURCE,'ReferencePlayerBlockInsideStuckProbe':SOURCE}
def source_inventory(jars):
    owners=['net.minecraft.world.level.block.WebBlock','net.minecraft.world.level.block.SweetBerryBushBlock','net.minecraft.world.entity.Entity','net.minecraft.world.entity.player.Player','net.minecraft.world.entity.LivingEntity','net.minecraft.world.level.block.state.BlockBehaviour$BlockStateBase','net.minecraft.world.level.BlockGetter','net.minecraft.core.BlockPos$4','net.minecraft.world.entity.InsideBlockEffectApplier$StepBasedCollector']
    result={}
    with zipfile.ZipFile(jars[0]) as archive:
        for owner in owners:
            s=subprocess.run([str(JAVA.parent/'javap'),'-classpath',str(jars[0]),'-c','-p',owner],capture_output=True,text=True,check=True).stdout
            entry=owner.replace('.','/')+'.class';result[owner]={'class_sha256':hashlib.sha256(archive.read(entry)).hexdigest(),'complete_bytecode_text_sha256':hashlib.sha256(s.encode()).hexdigest()}
    return result
def compile_java(jars):
    RAW.mkdir(parents=True,exist_ok=True);classes=RAW/'classes';classes.mkdir(exist_ok=True)
    paths=[]
    for name,source in SOURCES.items():p=RAW/(name+'.java');p.write_text(source);paths.append(p)
    command=[str(JAVA.parent/'javac'),'-cp',':'.join(map(str,jars)),'-d',str(classes),*map(str,paths)]
    start=time.monotonic();r=subprocess.run(command,capture_output=True,text=True);log=RAW/'javac.log';log.write_text(r.stdout+r.stderr)
    if r.returncode:raise RuntimeError('javac failed; diagnostics: '+str(log))
    return {'command':command,'seconds':round(time.monotonic()-start,6),'log':fingerprint(log)}
def run_java(inputs,jars,label):
    incoming=RAW/(label+'-input.jsonl');outgoing=RAW/(label+'-observed.jsonl');incoming.write_text(''.join(canonical(c).decode()+'\n' for c in inputs))
    command=[str(JAVA),'-cp',str(RAW/'classes')+':'+':'.join(map(str,jars)),'ReferencePlayerBlockInsideStuckProbe',str(incoming),str(outgoing)]
    start=time.monotonic();r=subprocess.run(command,capture_output=True,text=True);log=RAW/(label+'.log');log.write_text(r.stdout+r.stderr)
    if r.returncode:raise RuntimeError('Actual Java oracle failed; diagnostics: '+str(log))
    observations=[json.loads(line) for line in outgoing.read_text().splitlines()];assert [c['id'] for c in observations]==[c['id'] for c in inputs]
    return observations,{'command':command,'seconds':round(time.monotonic()-start,6),'log':fingerprint(log),'input':fingerprint(incoming),'observations':fingerprint(outgoing)}
def validate(data,observed=None):
    assert data['pin']=='26.3' and data['cases_sha256']==sha(data['cases'])
    assert [{k:c[k] for k in ['id','input','tags']} for c in data['cases']]==generate_inputs()
    if observed is not None:assert [{k:c[k] for k in ['id','expected','observation']} for c in data['cases']]==observed
    assert all(c['observation']['original_callbacks_executed'] and c['observation']['normal_constructor'] for c in data['cases'])
    shapes=[]
    resets=0
    for case in data['cases']:
        for request,step in zip(case['input']['steps'],case['expected']['steps'],strict=True):
            if request['operation']=='callback':shapes.append(step['entity_inside_shape'])
            else:
                shapes.extend(item['shape'] for item in step['entity_inside_shapes'])
                if case['input']['removed'] or case['input']['no_physics']:assert step['inside_reads']==[]
            resets+=step.get('impulse_reset_calls',0)
    assert shapes and all(shape['identity_block'] for shape in shapes),'Declared stationary full-block inside-shape admission failed'
    return {'case_count':len(data['cases']),'step_count':sum(len(c['input']['steps']) for c in data['cases']),
            'receiver_counts':{receiver:sum(c['input']['receiver']==receiver for c in data['cases']) for receiver in ['player','nonliving','fox','bee']},
            'actual_inside_shapes_checked':len(shapes),'actual_impulse_reset_calls_observed':resets,'oracle_compared':observed is not None}
def extract():
    jars,release=verified_classpath();inputs=generate_inputs();compiled=compile_java(jars)
    first,one=run_java(inputs,jars,'independent-1');second,two=run_java(inputs,jars,'independent-2');assert first==second
    data={'schema_version':1,'pin':'26.3','cases':[{**i,**o} for i,o in zip(inputs,first,strict=True)],
          'server_bundle_sha256':release['server_bundle']['sha256'],'server_class_jar_sha256':release['server_bundle']['nested_server_sha256'],
          'runtime_executable':fingerprint(JAVA),'classpath_libraries':[fingerprint(p) for p in jars[1:]],
          'probe_java_sources_sha256':{name:hashlib.sha256(source.encode()).hexdigest() for name,source in SOURCES.items()},'source':source_inventory(jars),
          'scope':'Original WebBlock/SweetBerryBushBlock callbacks, original Player/Entity stuck setter, and original stationary Entity.applyEffectsFromBlocks dispatch.',
          'confidence':'high for recorded callback and stationary overlap branches; arbitrary swept histories and real ServerLevel berry damage are outside this fixture',
          'fixture_boundary':{'normal_receivers':'Normal Player/Entity subclass constructors; original FOX/BEE constructors with their real EntityTypes. No Unsafe or replacement callback algorithm.',
            'observers_call_super':['Player.makeStuckInBlock','Entity.makeStuckInBlock','onInsideBlock','FixtureLevel.getBlockState','LivingEntity.tryResetCurrentImpulseContext','LivingEntity.resetCurrentImpulseContext'],
            'actual_state':'Original effects storage, WEAVING MobEffectInstance, actual leather boots and FROST_WALKER level 2 enchanted ItemStack; source holders and actual component initializer from original VanillaRegistries. Impulse context seeded through original setIgnoreFallDamageFromCurrentImpulse(true/false) methods.',
            'world':'Existing real sparse Level superclass with real block states and registries; plain Level is not ServerLevel, so actual berry server-damage instanceof guard returns after producing slowdown.',
            'dispatch':'Original public applyEffectsFromBlocks(position,position) constructs actual Movement and executes private query, original callbacks and actual per-Entity collector.',
            'direct_callback':'Original BlockState.entityInside with normally constructed StepBasedCollector; boolean argument varied; no replacement collector behavior.',
            'seed':'Original makeStuckInBlock(AIR, initial_multiplier) before flying/removal/noPhysics setup; initial snapshot follows setup; fallDistance assigned as test input.',
            'expected':'Fresh snapshot after each actual callback/dispatch, including raw multiplier/fall distance/body, immediate setter before/after and ordered real dispatch reads. No Python/Bend gameplay calculation creates expected values.',
            'unmeasured':['ServerLevel berry damage','moving swept traversal','whole player tick','hazard effects beyond declared blocks']}}
    data['cases_sha256']=sha(data['cases']);validation=validate(data,first);validate(data,second)
    failures=[]
    for reseal in [False,True]:
        bad=copy.deepcopy(data);bad['cases'][0]['expected']['final']['stuck_multiplier'][0]=bits(123.)
        if reseal:bad['cases_sha256']=sha(bad['cases'])
        try:validate(bad,first)
        except AssertionError:failures.append({'resealed':reseal,'rejected':True})
        else:raise AssertionError('Corruption accepted')
    write_json(OUTPUT,data);e={'schema_version':1,'status':'passed','pin':'26.3','reference':fingerprint(OUTPUT),'validation':validation,'independent_java_runs':2,'compile':compiled,'runs':[one,two],'failure_injections':failures,'generator':fingerprint(ROOT/'tools/reference_player_block_inside_stuck_probe.py'),'reproduce':'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_block_inside_stuck_probe.py'}
    write_json(ROOT/'evidence/player-block-inside-stuck-reference.json',e);return {k:e[k] for k in ['status','validation','independent_java_runs','failure_injections']}
def verify():
    jars,release=verified_classpath();data=json.loads(OUTPUT.read_text())
    assert data['server_bundle_sha256']==release['server_bundle']['sha256'] and data['server_class_jar_sha256']==release['server_bundle']['nested_server_sha256']
    assert data['runtime_executable']==fingerprint(JAVA) and data['classpath_libraries']==[fingerprint(p) for p in jars[1:]]
    assert data['source']==source_inventory(jars) and data['probe_java_sources_sha256']=={name:hashlib.sha256(source.encode()).hexdigest() for name,source in SOURCES.items()}
    observations=[[json.loads(l) for l in (RAW/(label+'-observed.jsonl')).read_text().splitlines()] for label in ['independent-1','independent-2']];assert observations[0]==observations[1]
    e={'schema_version':1,'status':'passed','pin':'26.3','reference':fingerprint(OUTPUT),'validation':validate(data,observations[0]),'official_source_runtime_libraries_checked':True,'independent_observations_checked':2,'generator':fingerprint(ROOT/'tools/reference_player_block_inside_stuck_probe.py'),'reproduce':'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_block_inside_stuck_probe.py --verify-existing'}
    write_json(ROOT/'evidence/player-block-inside-stuck-reference-validation.json',e);return e
def main():
    p=argparse.ArgumentParser();p.add_argument('--verify-existing',action='store_true');a=p.parse_args();print(json.dumps(verify() if a.verify_existing else extract(),indent=2))
if __name__=='__main__':main()
