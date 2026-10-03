#!/usr/bin/env python3
"""Pinned production supporting-cache and position helper observations.

Python organizes inputs and verifies transport only. The decisive cache,
candidate selection, position sampling, comparisons and distances execute
untouched official 26.3 methods. Compilation uses Java's in-memory single-file
source launcher, preserving the assigned-file ownership boundary.
"""
from __future__ import annotations
import argparse, base64, copy, hashlib, json, math, random, re, struct, subprocess, time, zipfile
from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_block_probe import verified_classpath
from reference_player_tick_probe import SOURCE as TICK_SOURCE
from reference_travel_probe import SOURCE as TRAVEL_SOURCE, MOVEMENT_SOURCE, DIRECT_SOURCE, bits, fbits, block

OUTPUT = ROOT / 'reference/support.json'
SEED = 263_104_07
SOURCE = r'''
import java.io.*;
import java.util.*;
import java.lang.reflect.*;
import com.google.gson.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;
import net.minecraft.core.registries.*;
import net.minecraft.resources.*;
import net.minecraft.world.entity.*;
import net.minecraft.world.level.*;
import net.minecraft.world.level.block.*;
import net.minecraft.world.level.block.state.*;
import net.minecraft.world.phys.*;
import net.minecraft.world.phys.shapes.*;

class ReferenceSupportProbe {
 static final Gson JSON = new GsonBuilder().serializeNulls().create();
 static final Method ON_POS;
 static {
  try {ON_POS=Entity.class.getDeclaredMethod("getOnPos",float.class);ON_POS.setAccessible(true);}
  catch(Exception e){throw new ExceptionInInitializerError(e);}
 }
 static List<Integer> pos(BlockPos p){return p==null?null:List.of(p.getX(),p.getY(),p.getZ());}
 static BlockPos pos(JsonArray a){return new BlockPos(a.get(0).getAsInt(),a.get(1).getAsInt(),a.get(2).getAsInt());}
 static Map<String,Object> row(BlockPos p,BlockState s){return Map.of("position",pos(p),"identifier",BuiltInRegistries.BLOCK.getKey(s.getBlock()).toString(),"state_id",Block.getId(s));}
 @SuppressWarnings("unchecked")
 static Map<String,Object> cache(Entity p)throws Exception{
  Optional<BlockPos> main=(Optional<BlockPos>)ReferencePlayerTickProbe.read(p,"mainSupportingBlockPos");
  Map<String,Object> m=new TreeMap<>();m.put("main",main.map(ReferenceSupportProbe::pos).orElse(null));m.put("on_ground_no_blocks",ReferencePlayerTickProbe.read(p,"onGroundNoBlocks"));return m;
 }
 static void seed(Entity p,JsonObject s)throws Exception{
  ReferencePlayerTickProbe.write(p,"mainSupportingBlockPos",s.get("main").isJsonNull()?Optional.empty():Optional.of(pos(s.getAsJsonArray("main"))));
  ReferencePlayerTickProbe.write(p,"onGroundNoBlocks",s.get("on_ground_no_blocks").getAsBoolean());
 }
 static class FixtureLevel extends ReferencePlayerTickProbe.FixtureLevel {
  final List<Map<String,Object>> supporting=new ArrayList<>(),sampleReads=new ArrayList<>();
  boolean sampling;
  public BlockState getBlockState(BlockPos p){BlockState s=super.getBlockState(p);if(sampling)sampleReads.add(row(p,s));return s;}
  public Optional<BlockPos> findSupportingBlock(Entity entity,AABB box){
   if(!Double.isFinite(box.minX)||!Double.isFinite(box.minY)||!Double.isFinite(box.minZ)||!Double.isFinite(box.maxX)||!Double.isFinite(box.maxY)||!Double.isFinite(box.maxZ)||box.maxX-box.minX>2||box.maxY-box.minY>2||box.maxZ-box.minZ>2||Math.abs(box.minX)>256||Math.abs(box.minY)>256||Math.abs(box.minZ)>256||Math.abs(box.maxX)>256||Math.abs(box.maxY)>256||Math.abs(box.maxZ)>256)throw new IllegalArgumentException("Unbounded supporting fixture query");
   Optional<BlockPos> actual=super.findSupportingBlock(entity,box);
   List<Map<String,Object>> candidates=new ArrayList<>();
   BlockCollisions<BlockPos> iterator=new BlockCollisions<>(this,entity,box,false,(mutable,shape)->{
    BlockPos p=mutable.immutable();List<AABB> boxes=shape.toAabbs();
    if(boxes.size()!=1)throw new IllegalStateException("Non-full-cube supporting candidate");
    Map<String,Object> c=new TreeMap<>(row(p,getBlockState(p)));c.put("box",ReferenceMovementProbe.boxBits(boxes.getFirst()));c.put("distance",ReferenceMovementProbe.bits(p.distToCenterSqr(entity.position())));candidates.add(c);return p;
   });
   while(iterator.hasNext())iterator.next();
   Map<String,Object> q=new TreeMap<>();q.put("box",ReferenceMovementProbe.boxBits(box));q.put("entity_position",ReferenceMovementProbe.vectorBits(entity.position()));q.put("candidates",candidates);q.put("selected",actual.map(ReferenceSupportProbe::pos).orElse(null));q.put("selected_distance",actual.map(p->ReferenceMovementProbe.bits(p.distToCenterSqr(entity.position()))).orElse(null));supporting.add(q);return actual;
  }
 }
 static class FixturePlayer extends ReferencePlayerTickProbe.FixturePlayer {
  FixturePlayer(Level l){super(l);}
  float jumpFactor(){return super.getBlockJumpFactor();}
 }
 static void writes(FixtureLevel l,JsonArray blocks){for(JsonElement e:blocks){JsonObject b=e.getAsJsonObject();String id=b.get("identifier").getAsString();if(!Set.of("minecraft:air","minecraft:stone","minecraft:dirt","minecraft:oak_planks").contains(id))throw new IllegalArgumentException("Unsupported supporting fixture block "+id);Block v=BuiltInRegistries.BLOCK.getValue(Identifier.parse(id));l.blocks.put(pos(b.getAsJsonArray("position")),v.defaultBlockState());}}
 static Map<String,Object> samples(FixturePlayer p,JsonArray offsets)throws Exception{
  Map<String,Object> s=new TreeMap<>();s.put("on_pos",pos(p.getOnPos()));s.put("legacy",pos(p.getOnPosLegacy()));s.put("below",pos(p.getBlockPosBelowThatAffectsMyMovement()));s.put("jump_factor_f32_bits",ReferenceTravelProbe.fb(p.jumpFactor()));
  List<Map<String,Object>> observed=new ArrayList<>();for(JsonElement e:offsets)observed.add(Map.of("offset_f32_bits",e.getAsString(),"position",pos((BlockPos)ON_POS.invoke(p,ReferenceMovementProbe.f(e)))));s.put("offsets",observed);return s;
 }
 static Map<String,Object> history(JsonObject c)throws Exception{
  JsonObject in=c.getAsJsonObject("input");FixtureLevel l=new FixtureLevel();writes(l,in.getAsJsonArray("world_blocks"));FixturePlayer p=new FixturePlayer(l);p.setPos(ReferenceMovementProbe.vector(in.getAsJsonArray("position")));seed(p,in.getAsJsonObject("initial"));List<Map<String,Object>> steps=new ArrayList<>();
  for(JsonElement e:in.getAsJsonArray("steps")){
   JsonObject s=e.getAsJsonObject();writes(l,s.getAsJsonArray("writes"));if(s.has("position"))p.setPos(ReferenceMovementProbe.vector(s.getAsJsonArray("position")));Map<String,Object> before=cache(p);l.supporting.clear();l.sampleReads.clear();l.clearTrace();l.sampling=false;
   Vec3 movement=s.get("movement").isJsonNull()?null:ReferenceMovementProbe.vector(s.getAsJsonArray("movement"));p.setOnGroundWithMovement(s.get("grounded").getAsBoolean(),s.get("horizontal").getAsBoolean(),movement);
   Map<String,Object> expected=new TreeMap<>();expected.put("cache",cache(p));expected.put("grounded",p.onGround());expected.put("horizontal",p.horizontalCollision);l.sampling=true;expected.put("samples",samples(p,s.getAsJsonArray("offsets_f32_bits")));l.sampling=false;
   Map<String,Object> o=new TreeMap<>();o.put("position",ReferenceMovementProbe.vectorBits(p.position()));o.put("box",ReferenceMovementProbe.boxBits(p.getBoundingBox()));o.put("initial_cache",before);o.put("queries",List.copyOf(l.supporting));o.put("sample_reads",List.copyOf(l.sampleReads));o.put("current_jump_factor_f32_bits",ReferenceTravelProbe.fb(l.getBlockState(p.blockPosition()).getBlock().getJumpFactor()));o.put("below_jump_factor_f32_bits",ReferenceTravelProbe.fb(l.getBlockState(p.getBlockPosBelowThatAffectsMyMovement()).getBlock().getJumpFactor()));o.put("actual_support_call",true);steps.add(Map.of("expected",expected,"observation",o));
  }return Map.of("id",c.get("id").getAsString(),"steps",steps);
 }
 static Map<String,Object> compare(JsonObject c){JsonObject in=c.getAsJsonObject("input");BlockPos a=pos(in.getAsJsonArray("left")),b=pos(in.getAsJsonArray("right"));int v=new Vec3i(a.getX(),a.getY(),a.getZ()).compareTo(new Vec3i(b.getX(),b.getY(),b.getZ()));return Map.of("id",c.get("id").getAsString(),"expected",Map.of("compare_i32",v,"compare_i32_bits",String.format(Locale.ROOT,"%08x",v)));}
 static Map<String,Object> distance(JsonObject c){JsonObject in=c.getAsJsonObject("input");BlockPos b=pos(in.getAsJsonArray("block"));Vec3 p=ReferenceMovementProbe.vector(in.getAsJsonArray("position"));double d=b.distToCenterSqr(p);double xyz=b.distToCenterSqr(p.x,p.y,p.z);if(Double.doubleToRawLongBits(d)!=Double.doubleToRawLongBits(xyz))throw new AssertionError("Actual distance overload disagreement");return Map.of("id",c.get("id").getAsString(),"expected",Map.of("distance",ReferenceMovementProbe.bits(d)));}
 static Map<String,Object> onPos(JsonObject c)throws Exception{JsonObject in=c.getAsJsonObject("input");FixtureLevel l=new FixtureLevel();writes(l,in.getAsJsonArray("world_blocks"));FixturePlayer p=new FixturePlayer(l);p.setPos(ReferenceMovementProbe.vector(in.getAsJsonArray("position")));seed(p,in.getAsJsonObject("cache"));float offset=ReferenceMovementProbe.f(in.get("offset_f32_bits"));l.sampling=true;BlockPos actual=(BlockPos)ON_POS.invoke(p,offset);return Map.of("id",c.get("id").getAsString(),"expected",Map.of("position",pos(actual)),"observation",Map.of("block_reads",List.copyOf(l.sampleReads),"actual_get_on_pos",true,"finite_offset",Float.isFinite(offset)));}
 static Map<String,Object> jumpFactor(JsonObject c)throws Exception{
  JsonObject in=c.getAsJsonObject("input");FixtureLevel l=new FixtureLevel();for(JsonElement e:in.getAsJsonArray("world_blocks")){JsonObject b=e.getAsJsonObject();String id=b.get("identifier").getAsString();if(!Set.of("minecraft:air","minecraft:stone","minecraft:honey_block","minecraft:slime_block").contains(id))throw new IllegalArgumentException("Unsupported jump-factor helper block");l.blocks.put(pos(b.getAsJsonArray("position")),BuiltInRegistries.BLOCK.getValue(Identifier.parse(id)).defaultBlockState());}
  FixturePlayer p=new FixturePlayer(l);p.setPos(ReferenceMovementProbe.vector(in.getAsJsonArray("position")));seed(p,in.getAsJsonObject("cache"));l.sampling=true;float factor=p.jumpFactor();l.sampling=false;BlockPos current=p.blockPosition(),below=p.getBlockPosBelowThatAffectsMyMovement();Map<String,Object> o=new TreeMap<>();o.put("current",pos(current));o.put("below",pos(below));o.put("current_jump_factor_f32_bits",ReferenceTravelProbe.fb(l.getBlockState(current).getBlock().getJumpFactor()));o.put("below_jump_factor_f32_bits",ReferenceTravelProbe.fb(l.getBlockState(below).getBlock().getJumpFactor()));o.put("sample_reads",List.copyOf(l.sampleReads));o.put("actual_get_block_jump_factor",true);return Map.of("id",c.get("id").getAsString(),"expected",Map.of("jump_factor_f32_bits",ReferenceTravelProbe.fb(factor)),"observation",o);
 }
 public static void main(String[] args)throws Exception{
  PrintStream output=System.out;SharedConstants.tryDetectVersion();Bootstrap.bootStrap();ReferenceDirectMovementProbe.initialize();JsonArray records=JsonParser.parseString(new String(Base64.getDecoder().decode(args[0]),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonArray();
  for(JsonElement e:records){JsonObject c=e.getAsJsonObject();String op=c.get("operation").getAsString();Map<String,Object> result=switch(op){case "support_history"->history(c);case "compare_helper"->compare(c);case "distance_helper"->distance(c);case "on_pos_helper"->onPos(c);case "jump_factor_helper"->jumpFactor(c);default->throw new IllegalArgumentException(op);};output.println("SUPPORT_JSON:"+JSON.toJson(result));}
 }
}
'''

MOVE_GATE_SOURCE = r'''
class ReferenceSupportMoveGateProbe {
 static final Gson JSON=new GsonBuilder().serializeNulls().create();
 static class FixturePlayer extends ReferenceSupportProbe.FixturePlayer {
  final List<Map<String,Object>> supportCalls=new ArrayList<>();
  final List<Map<String,Object>> recordMovementCalls=new ArrayList<>();
  final List<List<String>> setPosCalls=new ArrayList<>();
  FixturePlayer(Level l){super(l);}
  public void setPos(double x,double y,double z){if(setPosCalls!=null)setPosCalls.add(ReferenceMovementProbe.vectorBits(new Vec3(x,y,z)));super.setPos(x,y,z);}
  public void recordMovement(MoverType type,Vec3 movement){if(recordMovementCalls!=null){Map<String,Object> call=new TreeMap<>();call.put("type",type.name());call.put("movement",movement==null?null:ReferenceMovementProbe.vectorBits(movement));recordMovementCalls.add(call);}super.recordMovement(type,movement);}
  public void setOnGroundWithMovement(boolean grounded,boolean horizontal,Vec3 movement){
   if(supportCalls!=null){Map<String,Object> call=new TreeMap<>();call.put("grounded",grounded);call.put("horizontal",horizontal);call.put("movement",movement==null?null:ReferenceMovementProbe.vectorBits(movement));supportCalls.add(call);}
   super.setOnGroundWithMovement(grounded,horizontal,movement);
  }
 }
 static Map<String,Object> observe(JsonObject c)throws Exception{
  JsonObject in=c.getAsJsonObject("input");ReferenceSupportProbe.FixtureLevel l=new ReferenceSupportProbe.FixtureLevel();ReferenceSupportProbe.writes(l,in.getAsJsonArray("world_blocks"));FixturePlayer p=new FixturePlayer(l);
  p.setPos(ReferenceMovementProbe.vector(in.getAsJsonArray("position")));p.setOnGround(in.get("grounded").getAsBoolean());p.horizontalCollision=in.get("horizontal").getAsBoolean();p.setDeltaMovement(ReferenceMovementProbe.vector(in.getAsJsonArray("velocity")));p.getAttribute(Attributes.STEP_HEIGHT).setBaseValue(ReferenceMovementProbe.d(in.get("step_height")));ReferenceSupportProbe.seed(p,in.getAsJsonObject("initial"));
  if(!p.isLocalInstanceAuthoritative()||p.isPassenger()||p.getAbilities().flying||p.isShiftKeyDown()||p.noPhysics)throw new AssertionError("Neutral local-authoritative move context not established");
  Map<String,Object> before=Map.of("cache",ReferenceSupportProbe.cache(p),"body",ReferenceTravelProbe.body(p));List<String> initialPosition=ReferenceMovementProbe.vectorBits(p.position());
  p.supportCalls.clear();p.recordMovementCalls.clear();p.setPosCalls.clear();p.observations.clear();p.recorded=null;l.supporting.clear();l.sampleReads.clear();l.clearTrace();l.sampling=false;
  p.move(MoverType.SELF,ReferenceMovementProbe.vector(in.getAsJsonArray("requested")));
  Map<String,Object> expected=Map.of("cache",ReferenceSupportProbe.cache(p),"body",ReferenceTravelProbe.body(p));Map<String,Object> observation=new TreeMap<>();observation.put("support_calls",List.copyOf(p.supportCalls));observation.put("support_queries",List.copyOf(l.supporting));observation.put("set_pos_calls",List.copyOf(p.setPosCalls));observation.put("record_movement_calls",List.copyOf(p.recordMovementCalls));observation.put("position_equal",initialPosition.equals(ReferenceMovementProbe.vectorBits(p.position())));observation.put("movement_recorded",p.recorded!=null);observation.put("recorded_movement",p.recorded==null?null:ReferenceMovementProbe.vectorBits(p.recorded));observation.put("collider_queries",List.copyOf(l.queries));observation.put("fixture_service_calls",new TreeMap<>(l.calls));observation.put("observer_calls",new TreeMap<>(p.observations));observation.put("actual_player_move",true);
  return Map.of("id",c.get("id").getAsString(),"before",before,"expected",expected,"observation",observation);
 }
 public static void main(String[] args)throws Exception{
  PrintStream output=System.out;SharedConstants.tryDetectVersion();Bootstrap.bootStrap();ReferenceDirectMovementProbe.initialize();JsonArray records=JsonParser.parseString(new String(Base64.getDecoder().decode(args[0]),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonArray();for(JsonElement e:records)output.println("SUPPORT_MOVE_GATE_JSON:"+JSON.toJson(observe(e.getAsJsonObject())));
 }
}
'''

def cache(main=None, flag=False):
    return {'main':main,'on_ground_no_blocks':flag}

def generate_inputs():
    cases=[]
    offsets=['00000000','80000000','3727c5ab','3727c5ac','3727c5ad','3f000000','3f000011','bf000000']
    def step(grounded=True,movement=None,position=None,writes=(),horizontal=False):
        s={'writes':list(writes),'grounded':grounded,'horizontal':horizontal,'movement':None if movement is None else list(map(bits,movement)),'offsets_f32_bits':offsets}
        if position is not None:s['position']=list(map(bits,position))
        return s
    def add(name,position=(.5,1.,.5),world=(),initial=None,steps=None):
        cases.append({'id':'support:'+name,'operation':'support_history','input':{'position':list(map(bits,position)),'world_blocks':list(world),'initial':initial or cache(),'steps':steps or [step()]}})
    tile=[block([0,0,0])]
    for label,x in [('center',.5),('left-overhang',-.29),('right-overhang',1.29),('edge-before',math.nextafter(1.300000011920929,0.)),('edge',1.300000011920929),('edge-after',math.nextafter(1.300000011920929,math.inf))]:
        for motion in [None,(0.,0.,0.),(-0.,-0.,-0.)]:add(label+'-'+str(motion),position=(x,1.,.5),world=tile,steps=[step(movement=motion)])
    four=[block([x,0,z],['minecraft:stone','minecraft:dirt','minecraft:oak_planks','minecraft:stone'][z*2+x]) for z in range(2) for x in range(2)]
    for x,z in [(1.,1.),(math.nextafter(1.,0.),1.),(math.nextafter(1.,math.inf),1.),(1.,math.nextafter(1.,0.)),(1.,math.nextafter(1.,math.inf)),(.999999,1.000001),(-0.,-0.)]:add('seam-corner-'+bits(x)+'-'+bits(z),position=(x,1.,z),world=four)
    for flag in [False,True]:
        for main in [None,[7,0,-3]]:
            for movement in [None,(0.,0.,0.),(1.,7.,0.),(1.,-7.,1.),(-1.,0.,0.)]:
                add('absence-history-'+str(flag)+'-'+str(main)+'-'+str(movement),position=(1.5,1.,.5),world=tile,initial=cache(main,flag),steps=[step(movement=movement),step(movement=(1.,0.,0.)),step(False,movement=None),step(movement=(1.,0.,0.))])
    add('backward-corner',position=(1.5,1.,1.5),world=tile,steps=[step(movement=(1.,1e100,1.))])
    add('primary-before-fallback',world=tile,initial=cache([7,3,-3],True),steps=[step(movement=(2.,0.,2.))])
    for y in [math.nextafter(1.,0.),1.,math.nextafter(1.,math.inf),math.nextafter(1.+1e-6,0.),1.+1e-6,math.nextafter(1.+1e-6,math.inf),1.-1e-6,0.,-0.,-1.]:
        add('slab-y-'+bits(y),position=(.5,y,.5),world=tile,steps=[step(movement=None),step(movement=(0.,0.,0.))])
    add('dynamic-palette',world=tile,steps=[step(),step(writes=[block([0,0,0],'minecraft:dirt')]),step(writes=[block([0,0,0],'minecraft:oak_planks')]),step(writes=[block([0,0,0],'minecraft:air')]),step(movement=(0.,0.,0.)),step(writes=tile),step(False),step()])
    add('dynamic-seam',position=(1.,1.,1.),world=four,steps=[step(),step(writes=[block([1,0,1],'minecraft:air')]),step(writes=[block([0,0,1],'minecraft:air')]),step(writes=[block([1,0,0],'minecraft:air')]),step(writes=[block([0,0,0],'minecraft:air')]),step(writes=four)])
    add('cache-offset-y-change',world=tile,steps=[step(),step(position=(1.5,2.25,.5)),step(False,position=(-.5,2.25,-.5)),step(position=(-.5,0.,-.5),writes=[block([-1,-1,-1],'minecraft:dirt')])])
    rng=random.Random(SEED)
    for i in range(128):
        world=[block([x,0,z],rng.choice(['minecraft:air','minecraft:stone','minecraft:dirt','minecraft:oak_planks'])) for z in range(-2,3) for x in range(-2,3)]
        position=[rng.uniform(-1.9,1.9),rng.choice([1.,1.+1e-6,math.nextafter(1.,math.inf),2.]),rng.uniform(-1.9,1.9)]
        history=[]
        for k in range(3):
            motion=None if rng.randrange(4)==0 else [rng.choice([0.,-0.,rng.uniform(-2.,2.)]),rng.uniform(-1.,1.),rng.choice([0.,-0.,rng.uniform(-2.,2.)])]
            updates=[] if rng.randrange(2)==0 else [block([rng.randrange(-2,3),0,rng.randrange(-2,3)],rng.choice(['minecraft:air','minecraft:stone','minecraft:dirt','minecraft:oak_planks']))]
            history.append(step(rng.choice([True,True,False]),motion,writes=updates,horizontal=rng.choice([True,False])))
        add('random-'+str(i),position,world,cache(None if rng.randrange(2)==0 else [rng.randrange(-2,3),0,rng.randrange(-2,3)],rng.choice([False,True])),history)
    return cases

def generate_comparisons():
    cases=[];values=[-2147483648,-2147483647,-1,0,1,2147483647]
    for axis in range(3):
        for a in values:
            for b in values:
                left=[7,11,-13];right=list(left);left[axis]=a;right[axis]=b
                cases.append({'id':f'compare:{axis}-{a}-{b}','operation':'compare_helper','input':{'left':left,'right':right}})
    rng=random.Random(SEED+1)
    for i in range(128):cases.append({'id':'compare:random-'+str(i),'operation':'compare_helper','input':{'left':[rng.randrange(-2**31,2**31) for _ in range(3)],'right':[rng.randrange(-2**31,2**31) for _ in range(3)]}})
    return cases

def generate_distances():
    cases=[]
    coords=[[0,0,0],[-1,-1,-1],[-2147483648,2147483647,-2147483648],[2147483647,-2147483648,2147483647]]
    positions=[[0.,0.,0.],[-0.,-0.,-0.],[.5,.5,.5],[1.,1.,1.],[1e154,0.,0.],[0.,-1e154,1e154],[math.nextafter(math.sqrt(float.fromhex('0x1.fffffffffffffp+1023')),0.),0.,0.],[math.sqrt(float.fromhex('0x1.fffffffffffffp+1023')),0.,0.],[math.nextafter(math.sqrt(float.fromhex('0x1.fffffffffffffp+1023')),math.inf),0.,0.],[1e200,-1e200,1e200],[float.fromhex('0x1.fffffffffffffp+1023'),0.,0.],[-float.fromhex('0x1.fffffffffffffp+1023'),0.,0.]]
    for b in coords:
        for p in positions:cases.append({'id':'distance:'+str(b)+'-'+str(len(cases)),'operation':'distance_helper','input':{'block':b,'position':list(map(bits,p))}})
    rng=random.Random(SEED+2)
    for i in range(128):
        b=[rng.randrange(-2**31,2**31) for _ in range(3)];p=[rng.uniform(-1e10,1e10) for _ in range(3)]
        cases.append({'id':'distance:random-'+str(i),'operation':'distance_helper','input':{'block':b,'position':list(map(bits,p))}})
    return cases

def generate_on_pos():
    cases=[]
    offsets=['00000000','80000000','00000001','80000001','3727c5ab','3727c5ac','3727c5ad','3effffff','3f000000','3f000001','3f000010','3f000011','3f000012','be4ccccd','3f800000','bf800000','7f7fffff','ff7fffff','7f800000','ff800000','7fc00001','ffc00001']
    positions=[[.5,1.,.5],[-.5,-0.,-.5],[1.,math.nextafter(1.,0.),1.],[1.,math.nextafter(1.,math.inf),1.],[-2147483648.,2147483647.,2147483647.],[1e200,-1e200,1e200]]
    for main in [None,[7,11,-13],[-2147483648,2147483647,2147483647]]:
        for p in positions:
            for offset in offsets:
                world=[] if main is None else [block(main,'minecraft:dirt')]
                cases.append({'id':'on-pos:'+str(len(cases)),'operation':'on_pos_helper','input':{'position':list(map(bits,p)),'cache':cache(main,True),'world_blocks':world,'offset_f32_bits':offset}})
    return cases

def generate_jump_factors():
    cases=[]
    for cached in [False,True]:
        for current in ['minecraft:air','minecraft:stone','minecraft:honey_block','minecraft:slime_block']:
            for below in ['minecraft:air','minecraft:stone','minecraft:honey_block']:
                lower=[1,0,1] if cached else [0,0,0]
                cases.append({'id':f'jump-factor:{cached}-{current}-{below}','operation':'jump_factor_helper','input':{'position':list(map(bits,[.5,1.,.5])),'cache':cache(lower if cached else None),'world_blocks':[block([0,1,0],current),block(lower,below)]}})
    return cases

def generate_move_gate():
    cases=[]
    tile=[block([0,0,0])]
    half_width=struct.unpack('>f',struct.pack('>f',.6))[0]/2
    wall_position=(1.-half_width,1.,.5)
    wall_world=tile+[block([1,1,0],'minecraft:dirt')]
    def add(name,requested,position=(.5,1.,.5),world=None,initial=None,grounded=True):
        cases.append({'id':'move-support:'+name,'operation':'move_support','input':{'position':list(map(bits,position)),'velocity':list(map(bits,requested)),'requested':list(map(bits,requested)),'world_blocks':tile if world is None else list(world),'initial':cache() if initial is None else initial,'grounded':grounded,'horizontal':False,'step_height':bits(0.)}})
    add('zero-floor-cached',(0.,0.,0.),initial=cache([0,0,0]))
    add('signed-zero-air-stale-no-blocks',(-0.,-0.,-0.),world=[],initial=cache([7,0,-3],True),grounded=False)
    add('floor-dy-minus-0004-stale',(0.,-.0004,0.),initial=cache([7,0,-3]))
    add('floor-dy-minus-001-no-blocks',(0.,-.001,0.),initial=cache(None,True))
    add('wall-dx-plus-0004-cached',(.0004,0.,0.),wall_position,wall_world,cache([0,0,0]))
    add('wall-dx-plus-001-no-blocks',(.001,0.,0.),wall_position,wall_world,cache([7,0,-3],True))
    add('floor-wall-dxy-stale',(.0004,-.0004,0.),wall_position,wall_world,cache([7,0,-3]))
    threshold=math.sqrt(1e-7)
    add('floor-dy-gate-before',(0.,-math.nextafter(threshold,0.),0.),initial=cache([7,0,-3]))
    add('floor-dy-gate-after',(0.,-math.nextafter(threshold,math.inf),0.),initial=cache([7,0,-3]))
    add('floor-dy-minus-0001-empty',(0.,-.0001,0.))
    return cases

def launcher_source():
    originals=[SOURCE,MOVEMENT_SOURCE,DIRECT_SOURCE,TRAVEL_SOURCE,TICK_SOURCE]
    imports=[];bodies=[]
    for source in originals:
        found=re.findall(r'^import[^\n]+;\s*$',source,re.M)
        for item in found:
            if item.strip() not in imports:imports.append(item.strip())
        body=re.sub(r'^import[^\n]+;\s*$','',source,flags=re.M)
        body=re.sub(r'^public class (Reference(?:Movement|Travel|PlayerTick)Probe)\b',r'class \1',body,flags=re.M)
        bodies.append(body)
    return '\n'.join(imports)+'\n'+'\n'.join(bodies)

def move_gate_launcher_source():
    # The established supporting probe and its compilation unit stay unchanged.
    # This separate entry class contains only observers and the direct move call.
    source=MOVE_GATE_SOURCE+'\n'+launcher_source()
    imports=re.findall(r'^import[^\n]+;\s*$',source,re.M)
    return '\n'.join(dict.fromkeys(item.strip() for item in imports))+'\n'+re.sub(r'^import[^\n]+;\s*$','',source,flags=re.M)

def run_move_gate_java(inputs,jars):
    encoded=base64.b64encode(canonical(inputs)).decode()
    embedded='String.join("",new String[]{'+','.join(json.dumps(encoded[i:i+6144]) for i in range(0,len(encoded),6144))+'})'
    source=move_gate_launcher_source().replace('Base64.getDecoder().decode(args[0])','Base64.getDecoder().decode('+embedded+')',1)
    command=[str(JAVA),'--source','25','--class-path',':'.join(map(str,jars)),'/dev/stdin']
    start=time.monotonic();r=subprocess.run(command,input=source,text=True,capture_output=True);seconds=time.monotonic()-start
    if r.returncode:raise RuntimeError('Move-gate Java source launch failed:\n'+r.stdout[-8000:]+r.stderr[-8000:])
    observed=[json.loads(line[len('SUPPORT_MOVE_GATE_JSON:'):]) for line in r.stdout.splitlines() if line.startswith('SUPPORT_MOVE_GATE_JSON:')]
    assert [c['id'] for c in observed]==[c['id'] for c in inputs],'move-gate output topology'
    execution={'command':command,'reproduce':'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_support_probe.py --move-gate','case_count':len(inputs),'input_sha256':hashlib.sha256(canonical(inputs)).hexdigest(),'output_sha256':hashlib.sha256(canonical(observed)).hexdigest(),'stdout_sha256':hashlib.sha256(r.stdout.encode()).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr.encode()).hexdigest(),'source_sha256':hashlib.sha256(source.encode()).hexdigest(),'seconds':round(seconds,6)}
    return observed,execution

def run_java(inputs,jars):
    encoded=base64.b64encode(canonical(inputs)).decode()
    # Runtime String.join prevents javac folding the complete input into a
    # single constant exceeding the JVM's 65,535-byte constant-pool limit.
    chunks=[json.dumps(encoded[i:i+6144]) for i in range(0,len(encoded),6144)]
    embedded='String.join("",new String[]{'+','.join(chunks)+'})'
    source=launcher_source().replace('Base64.getDecoder().decode(args[0])','Base64.getDecoder().decode('+embedded+')',1)
    cp=':'.join(map(str,jars));command=[str(JAVA),'--source','25','--class-path',cp,'/dev/stdin']
    start=time.monotonic();r=subprocess.run(command,input=source,text=True,capture_output=True);seconds=time.monotonic()-start
    if r.returncode:raise RuntimeError('Support Java source launch failed:\n'+r.stdout[-8000:]+r.stderr[-8000:])
    observed=[json.loads(line[len('SUPPORT_JSON:'):]) for line in r.stdout.splitlines() if line.startswith('SUPPORT_JSON:')]
    if [c['id'] for c in observed]!=[c['id'] for c in inputs]:raise ValueError('Support output topology')
    execution={'case_count':len(inputs),'input_sha256':hashlib.sha256(canonical(inputs)).hexdigest(),'output_sha256':hashlib.sha256(canonical(observed)).hexdigest(),'stdout_sha256':hashlib.sha256(r.stdout.encode()).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr.encode()).hexdigest(),'source_sha256':hashlib.sha256(source.encode()).hexdigest(),'seconds':round(seconds,6)}
    return observed,{'launcher':'installed Java single-file in-memory compilation; main plus original fixture classes in one source compilation unit; canonical input Base64 is embedded as joined string chunks','command':command,'reproduce':'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_support_probe.py --selftest','batches':[execution]}

CLASSES=['net.minecraft.world.entity.Entity','net.minecraft.world.entity.LivingEntity','net.minecraft.world.entity.player.Player','net.minecraft.world.level.CollisionGetter','net.minecraft.world.level.BlockCollisions','net.minecraft.core.Cursor3D','net.minecraft.core.Vec3i','net.minecraft.core.BlockPos','net.minecraft.world.phys.AABB','net.minecraft.util.Mth','net.minecraft.world.level.block.Block','net.minecraft.world.level.block.state.BlockBehaviour$BlockStateBase']
METHODS={'setOnGroundWithMovement','checkSupportingBlock','findSupportingBlock','computeNext','advance','nextX','nextY','nextZ','getNextType','compareTo','distToCenterSqr','getOnPos','getOnPosLegacy','getBlockPosBelowThatAffectsMyMovement','getBlockJumpFactor','atY','floor','move','getCollisionShape','getJumpFactor'}
def source_inventory(jars):
    result={}
    with zipfile.ZipFile(jars[0]) as z:
        for owner in CLASSES:
            s=subprocess.run([str(JAVA.parent/'javap'),'-classpath',str(jars[0]),'-c','-p',owner],capture_output=True,text=True,check=True).stdout
            methods=[]
            for sig,body in re.findall(r'^  ((?:public|protected|private)[^\n]*?\([^\n]*\);)\n(.*?)(?=^  (?:public|protected|private|static)|\Z)',s,re.M|re.S):
                m=re.search(r'([\w$<>]+)\([^\n]*\);$',sig)
                if m and (m[1] in METHODS or owner.endswith('BlockCollisions') and 'BlockCollisions(' in sig):methods.append({'signature':sig,'bytecode_text_sha256':hashlib.sha256(body.encode()).hexdigest(),'direct_call_references':sorted(set(re.findall(r'// (?:InterfaceMethod|Method) (.+)',body))),'field_references':sorted(set(re.findall(r'// Field (.+)',body)))})
            entry=owner.replace('.','/')+'.class';result[owner]={'class_entry':entry,'class_sha256':hashlib.sha256(z.read(entry)).hexdigest(),'complete_bytecode_text_sha256':hashlib.sha256(s.encode()).hexdigest(),'methods':methods}
    return result

def all_inputs():
    return generate_inputs()+generate_comparisons()+generate_distances()+generate_on_pos()+generate_jump_factors()

def validate(data,observed=None):
    assert data['pin']=='26.3'
    groups=['cases','comparisons','distances','on_pos','jump_factors']
    assert data['observations_sha256']==hashlib.sha256(canonical({k:data[k] for k in groups})).hexdigest(),'observation checksum'
    actual=[c for k in groups for c in data[k]]
    assert [{k:c[k] for k in ['id','operation','input']} for c in actual]==all_inputs(),'input regeneration'
    if observed is not None:assert [{k:v for k,v in c.items() if k not in ['operation','input']} for c in actual]==observed,'actual independent Java outputs'
    assert all(step['observation']['actual_support_call'] for c in data['cases'] for step in c['steps'])
    assert all(c['observation']['actual_get_on_pos'] for c in data['on_pos'])
    assert all(c['observation']['actual_get_block_jump_factor'] for c in data['jump_factors'])
    queries=[q for c in data['cases'] for s in c['steps'] for q in s['observation']['queries']]
    assert any(len(s['observation']['queries'])==2 for c in data['cases'] for s in c['steps']),'fallback not exercised'
    assert any(len(q['candidates'])==4 for q in queries),'corner candidates not exercised'
    assert any(c['expected']['distance']=='7ff0000000000000' for c in data['distances']),'overflow helper not exercised'
    assert any(c['expected']['compare_i32']>0 and c['input']['left'][1]<c['input']['right'][1] for c in data['comparisons']),'wrapping compare helper not exercised'
    return {'case_histories':len(data['cases']),'cache_transitions':sum(len(c['steps']) for c in data['cases']),'actual_support_queries':len(queries),'compare_helpers':len(data['comparisons']),'distance_helpers':len(data['distances']),'on_pos_helpers':len(data['on_pos']),'jump_factor_helpers':len(data['jump_factors']),'actual_outputs_compared':observed is not None}

def extract():
    jars,release=verified_classpath();inputs=all_inputs();observed,execution=run_java(inputs,jars);records=[{**i,**o} for i,o in zip(inputs,observed,strict=True)]
    groups={key:[c for c in records if c['operation']==op] for key,op in [('cases','support_history'),('comparisons','compare_helper'),('distances','distance_helper'),('on_pos','on_pos_helper'),('jump_factors','jump_factor_helper')]}
    runtime=subprocess.run([str(JAVA),'-version'],capture_output=True,text=True,check=True)
    data={'schema_version':1,'pin':'26.3','random_input_seed':SEED,**groups,'observations_sha256':hashlib.sha256(canonical(groups)).hexdigest(),'server_bundle_sha256':release['server_bundle']['sha256'],'server_class_jar_sha256':release['server_bundle']['nested_server_sha256'],'runtime_executable':fingerprint(JAVA),'runtime_version':(runtime.stdout+runtime.stderr).strip().splitlines(),'classpath_libraries':[fingerprint(p) for p in jars[1:]],'source':source_inventory(jars),'fixture_source_sha256':{key:hashlib.sha256(value.encode()).hexdigest() for key,value in [('support',SOURCE),('movement',MOVEMENT_SOURCE),('direct_movement',DIRECT_SOURCE),('travel',TRAVEL_SOURCE),('player_tick',TICK_SOURCE),('launcher_compilation_unit',launcher_source())]},'scope':'Untouched actual Entity supporting cache updates, actual CollisionGetter.findSupportingBlock and actual BlockCollisions in finite sparse Level; direct standalone actual numeric/position helper observations are separate and do not imply giant collision query support','confidence':'high for recorded bounded full-cube contexts and separately recorded helper inputs; complete world/contextual shape and entity travel parity unknown','fixture_boundary':{'cache_storage':'Reflection seeds/reads private Optional<BlockPos> and onGroundNoBlocks only; decisive updates call original public Entity.setOnGroundWithMovement(boolean,boolean,Vec3). Null movement remains Java null.','world':'Existing original Player tick/travel fixture sources; admitted AIR/STONE/DIRT/OAK_PLANKS sparse state writes; no actors; bounded real full-cube BlockCollisions queries','query_observer':'FixtureLevel.findSupportingBlock calls super production method first, then independently enumerates the actual production BlockCollisions iterator to expose ordered shape/position/distance candidates. Original selected Optional is returned unchanged.','position_sampling':'Original getOnPos(float), getOnPos(), getOnPosLegacy(), getBlockPosBelowThatAffectsMyMovement(), Entity.getBlockJumpFactor(); observer wrappers call super','helper_separation':'Signed-int wrapping compareTo and huge finite distToCenterSqr overflow execute directly without collision queries. Nonfinite/huge offsets also execute getOnPos directly, without a slab query.','source_compilation':'Java single-file source compilation combines unchanged source bodies with import consolidation and public top-level class access removed solely to fit one compilation unit. No fixture dependency file is edited.'}}
    validation=validate(data,observed);write_json(OUTPUT,data);e={'status':'passed','reference':fingerprint(OUTPUT),'execution':execution,'validation':validation};write_json(ROOT/'evidence/support-reference.json',e);return e

def verify():
    jars,release=verified_classpath();data=json.loads(OUTPUT.read_text());assert data['server_bundle_sha256']==release['server_bundle']['sha256'],'server bundle provenance';assert data['server_class_jar_sha256']==release['server_bundle']['nested_server_sha256'];assert data['classpath_libraries']==[fingerprint(p) for p in jars[1:]],'classpath library provenance';assert data['source']==source_inventory(jars);assert data['runtime_executable']==fingerprint(JAVA)
    sources={'support':SOURCE,'movement':MOVEMENT_SOURCE,'direct_movement':DIRECT_SOURCE,'travel':TRAVEL_SOURCE,'player_tick':TICK_SOURCE,'launcher_compilation_unit':launcher_source()};assert data['fixture_source_sha256']=={k:hashlib.sha256(v.encode()).hexdigest() for k,v in sources.items()}
    e={'status':'passed','validation':validate(data),'pinned_sources_runtime_and_classes_checked':True};write_json(ROOT/'evidence/support-reference-validation.json',e);return e

def selftest():
    jars,_=verified_classpath();data=json.loads(OUTPUT.read_text());one,a=run_java(all_inputs(),jars);two,b=run_java(all_inputs(),jars);assert one==two;validate(data,one);validate(data,two);failures=[]
    for reseal in [False,True]:
        bad=copy.deepcopy(data);bad['cases'][0]['steps'][0]['expected']['cache']['main']=[123,456,789]
        if reseal:bad['observations_sha256']=hashlib.sha256(canonical({k:bad[k] for k in ['cases','comparisons','distances','on_pos','jump_factors']})).hexdigest()
        try:validate(bad,one)
        except AssertionError as err:failures.append({'resealed':reseal,'rejected':True,'reason':str(err)})
        else:raise AssertionError('Corruption accepted')
    e={'status':'passed','independent_java_runs':2,'validation':validate(data,one),'failure_injections':failures,'executions':[a,b]};write_json(ROOT/'evidence/support-reference-selftest.json',e);return e

def move_gate():
    frozen=fingerprint(OUTPUT);jars,release=verified_classpath();data=json.loads(OUTPUT.read_text());validate(data)
    assert data['server_bundle_sha256']==release['server_bundle']['sha256'],'server bundle provenance'
    assert data['server_class_jar_sha256']==release['server_bundle']['nested_server_sha256'],'server class jar provenance'
    assert data['classpath_libraries']==[fingerprint(p) for p in jars[1:]],'classpath library provenance'
    assert data['runtime_executable']==fingerprint(JAVA),'runtime provenance'
    established={'support':SOURCE,'movement':MOVEMENT_SOURCE,'direct_movement':DIRECT_SOURCE,'travel':TRAVEL_SOURCE,'player_tick':TICK_SOURCE,'launcher_compilation_unit':launcher_source()}
    assert data['fixture_source_sha256']=={k:hashlib.sha256(v.encode()).hexdigest() for k,v in established.items()},'frozen fixture source provenance'
    assert data['source']==source_inventory(jars),'production class/method provenance'
    inputs=generate_move_gate();observed,execution=run_move_gate_java(inputs,jars);records=[{**i,**o} for i,o in zip(inputs,observed,strict=True)]
    for c in records:
        o=c['observation'];assert o['actual_player_move'];assert len(o['support_calls'])==1,'admitted actual move support-call count';assert o['position_equal'],'admitted move changed raw position';assert c['before']['body']['box']==c['expected']['body']['box'],'admitted move changed raw box';assert bool(o['record_movement_calls'])==o['movement_recorded'],'actual gate witness disagreement';assert len(o['record_movement_calls'])==len(o['set_pos_calls']),'admitted actual gate witness count'
    without_set_pos=[c for c in records if not c['observation']['set_pos_calls']]
    assert any(c['expected']['cache']['main'] is not None and c['observation']['support_queries'] for c in without_set_pos),'skipped position application with actual support selection not observed'
    assert any(c['before']['cache']['main'] is not None and c['expected']['cache']['main'] is None for c in without_set_pos),'skipped position application with actual cache clearing not observed'
    assert any(c['observation']['set_pos_calls'] and c['expected']['cache']['main'] is None for c in records),'zero displacement cache clear not observed'
    assert fingerprint(OUTPUT)==frozen,'frozen support reference changed'
    runtime=subprocess.run([str(JAVA),'-version'],capture_output=True,text=True,check=True)
    entity_bytecode=subprocess.run([str(JAVA.parent/'javap'),'-classpath',str(jars[0]),'-c','-p','net.minecraft.world.entity.Entity'],capture_output=True,text=True,check=True).stdout
    position_methods=[]
    for sig,body in re.findall(r'^  ((?:public|protected|private)[^\n]*?\([^\n]*\);)\n(.*?)(?=^  (?:public|protected|private|static)|\Z)',entity_bytecode,re.M|re.S):
        if ' setPos(' in sig:position_methods.append({'signature':sig,'bytecode_text_sha256':hashlib.sha256(body.encode()).hexdigest(),'direct_call_references':sorted(set(re.findall(r'// (?:InterfaceMethod|Method) (.+)',body)))})
    e={'schema_version':1,'status':'passed','pin':'26.3','scope':'Ten direct untouched locally authoritative Player.move calls with observer-only setPos(double,double,double) and setOnGroundWithMovement overrides; finite neutral full-cube Level; exact raw position equality is recorded separately from actual position-application calls','confidence':'high for these bounded neutral moves; no complete move/world/tick parity claim','cases':records,'cases_sha256':hashlib.sha256(canonical(records)).hexdigest(),'execution':execution,'server_bundle_sha256':data['server_bundle_sha256'],'server_class_jar_sha256':data['server_class_jar_sha256'],'runtime_executable':fingerprint(JAVA),'runtime_version':(runtime.stdout+runtime.stderr).strip().splitlines(),'classpath_libraries':data['classpath_libraries'],'source':data['source'],'position_setter_methods':position_methods,'fixture_source_sha256':{**data['fixture_source_sha256'],'move_gate':hashlib.sha256(MOVE_GATE_SOURCE.encode()).hexdigest(),'move_gate_compilation_unit':hashlib.sha256(move_gate_launcher_source().encode()).hexdigest()},'frozen_reference':frozen,'validation':{'case_count':len(records),'actual_support_call_count':sum(len(c['observation']['support_calls']) for c in records),'actual_support_query_count':sum(len(c['observation']['support_queries']) for c in records),'unchanged_position_count':sum(c['observation']['position_equal'] for c in records),'without_set_pos_count':len(without_set_pos),'frozen_reference_unchanged':True,'frozen_support_and_launcher_sources_verified':True},'fixture_boundary':{'move':'FixturePlayer.move delegates to super through the unchanged existing observer; original Player/Entity move implementation supplies every expected value. No collision or gate algorithm is recreated.','support_calls':'Observer records actual nullable Vec3 and both flags before calling unchanged super implementation; signed-zero values are preserved as raw binary64.','position_application':'Entity.setPos(Vec3) is final and calls virtual setPos(double,double,double); the observer records that delegated invocation before calling super. Constructor/setup observations are cleared before move. Raw before/after position equality is a separate recorded comparison.','world_and_queries':data['fixture_boundary']['world']+'; '+data['fixture_boundary']['query_observer'],'state_setup':'Actual setPos, setOnGround, setDeltaMovement, and STEP_HEIGHT attribute setters establish the neutral body; reflection seeds only the existing two private cache fields afterward.'}}
    write_json(ROOT/'evidence/support-move-gate-reference.json',e);return {'status':e['status'],'evidence':fingerprint(ROOT/'evidence/support-move-gate-reference.json'),'validation':e['validation']}

def main():
    p=argparse.ArgumentParser();p.add_argument('--verify-existing',action='store_true');p.add_argument('--selftest',action='store_true');p.add_argument('--move-gate',action='store_true');args=p.parse_args();e=move_gate() if args.move_gate else selftest() if args.selftest else verify() if args.verify_existing else extract();print(json.dumps({k:v for k,v in e.items() if k not in ['execution','executions']},indent=2))
if __name__=='__main__':main()
