#!/usr/bin/env python3
"""Pinned 26.3 movement probes. Java extraction instrument, not gameplay."""
from __future__ import annotations
import argparse, collections, copy, hashlib, json, math, pathlib, random, re, struct, subprocess, time, zipfile
from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_block_probe import verified_classpath

OUTPUT = ROOT / 'reference/movement.json'
SEED = 263_101_03
SOURCE = r'''
import java.io.*;
import java.nio.file.*;
import java.lang.reflect.*;
import java.util.*;
import com.google.gson.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityDimensions;
import net.minecraft.core.Direction;
import net.minecraft.core.Direction.Axis;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.*;
import net.minecraft.world.phys.shapes.*;

public class ReferenceMovementProbe {
  static final Gson JSON = new Gson();
  static final Constructor<ArrayVoxelShape> ARRAY;
  static final Method COLLIDE, HEIGHTS;
  static {
    try {
      ARRAY=ArrayVoxelShape.class.getDeclaredConstructor(DiscreteVoxelShape.class,double[].class,double[].class,double[].class); ARRAY.setAccessible(true);
      COLLIDE=Entity.class.getDeclaredMethod("collideWithShapes",Vec3.class,AABB.class,List.class); COLLIDE.setAccessible(true);
      HEIGHTS=Entity.class.getDeclaredMethod("collectCandidateStepUpHeights",AABB.class,List.class,float.class,float.class); HEIGHTS.setAccessible(true);
    } catch(ReflectiveOperationException e) { throw new ExceptionInInitializerError(e); }
  }
  static double d(JsonElement v) { return Double.longBitsToDouble(Long.parseUnsignedLong(v.getAsString(),16)); }
  static float f(JsonElement v) { return Float.intBitsToFloat((int)Long.parseLong(v.getAsString(),16)); }
  static String bits(double v) { return String.format(Locale.ROOT,"%016x",Double.doubleToRawLongBits(v)); }
  static double[] values(JsonArray a) { double[] r=new double[a.size()]; for(int i=0;i<r.length;i++)r[i]=d(a.get(i)); return r; }
  static Vec3 vector(JsonArray a) { double[] v=values(a); return new Vec3(v[0],v[1],v[2]); }
  static AABB box(JsonArray a) { double[] v=values(a); return new AABB(v[0],v[1],v[2],v[3],v[4],v[5]); }
  static List<String> vectorBits(Vec3 v) { return List.of(bits(v.x),bits(v.y),bits(v.z)); }
  static List<String> boxBits(AABB v) { return List.of(bits(v.minX),bits(v.minY),bits(v.minZ),bits(v.maxX),bits(v.maxY),bits(v.maxZ)); }
  static List<VoxelShape> shapes(JsonArray values) throws Exception {
    List<VoxelShape> r=new ArrayList<>();
    for(JsonElement e:values) {
      JsonObject s=e.getAsJsonObject();
      if(s.get("kind").getAsString().equals("empty"))r.add(Shapes.empty());
      else {
        double[] v=values(s.getAsJsonArray("box"));
        BitSetDiscreteVoxelShape grid=new BitSetDiscreteVoxelShape(1,1,1);grid.fill(0,0,0);
        r.add(ARRAY.newInstance(grid,new double[]{v[0],v[3]},new double[]{v[1],v[4]},new double[]{v[2],v[5]}));
      }
    }
    return r;
  }
  static Vec3 collide(Vec3 v,AABB b,List<VoxelShape>s) throws Exception { return (Vec3)COLLIDE.invoke(null,v,b,s); }
  static float[] heights(AABB b,List<VoxelShape>s,float maximum,float previous) throws Exception { return (float[])HEIGHTS.invoke(null,b,s,maximum,previous); }
  // This glue follows the pinned Entity.collide branch flow; the clipping and
  // candidate collection are executed by the original private game methods.
  // Collider retrieval is supplied and full Entity.move is not invoked.
  static Object[] resolve(AABB b,boolean grounded,float maximum,Vec3 request,List<VoxelShape> initial,List<VoxelShape> step) throws Exception {
    Vec3 base=request.lengthSqr()==0.0?request:collide(request,b,initial);
    boolean landed=request.y!=base.y&&request.y<0.0;
    if(maximum>0.0f&&(landed||grounded)&&(request.x!=base.x||request.z!=base.z)) {
      AABB adjusted=landed?b.move(0.0,base.y,0.0):b;
      for(float height:heights(adjusted,step,maximum,(float)base.y)) {
        Vec3 attempt=collide(new Vec3(request.x,(double)height,request.z),adjusted,step);
        if(attempt.horizontalDistanceSqr()>base.horizontalDistanceSqr())return new Object[]{attempt.subtract(0.0,b.minY-adjusted.minY,0.0),true};
      }
    }
    return new Object[]{base,false};
  }
  static Map<String,Object> observe(JsonObject c) throws Exception {
    JsonObject in=c.getAsJsonObject("input");String op=c.get("operation").getAsString();
    if(op.equals("entity_move"))return ReferenceDirectMovementProbe.observe(c);
    AABB b=box(in.getAsJsonArray("box"));Vec3 request=vector(in.getAsJsonArray("requested"));
    List<VoxelShape> initial=shapes(in.getAsJsonArray("initial")),step=shapes(in.getAsJsonArray("step"));
    float maximum=f(in.get("maximum_f32_bits")), previous=f(in.get("previous_f32_bits"));
    Map<String,Object> expected=new TreeMap<>(), observed=new TreeMap<>();
    observed.put("axis_order",Direction.axisStepOrder(request).stream().map(Enum::name).toList());
    if(op.equals("make_box"))expected.put("box",boxBits(EntityDimensions.fixed(f(in.get("width_f32_bits")),f(in.get("height_f32_bits"))).makeBoundingBox(vector(in.getAsJsonArray("position")))));
    else if(op.equals("block_query"))expected.put("box",boxBits(b.expandTowards(request)));
    else if(op.equals("entity_query"))expected.put("box",boxBits(b.expandTowards(request).expandTowards(0.0,(double)maximum,0.0)));
    else if(op.equals("step_query")) {
      Vec3 baseline=vector(in.getAsJsonArray("velocity"));boolean landed=request.y!=baseline.y&&request.y<0.0;
      AABB adjusted=landed?b.move(0.0,baseline.y,0.0):b;
      AABB query=adjusted.expandTowards(request.x,(double)maximum,request.z);
      if(!landed)query=query.expandTowards(0.0,(double)-1e-5f,0.0);
      expected.put("box",boxBits(query));
    } else if(op.equals("collide"))expected.put("displacement",vectorBits(collide(request,b,initial)));
    else if(op.equals("heights")) {
      List<String> out=new ArrayList<>();for(float v:heights(b,step,maximum,previous))out.add(bits((double)v));expected.put("heights",out);
      List<String> deltas=new ArrayList<>();for(VoxelShape s:step)for(double y:s.getCoords(Axis.Y))deltas.add(bits(y-b.minY));observed.put("candidate_deltas",deltas);
    } else {
      Object[] result=resolve(b,in.get("grounded").getAsBoolean(),maximum,request,initial,step);
      Vec3 delta=(Vec3)result[0];expected.put("displacement",vectorBits(delta));expected.put("stepped",result[1]);
      if(op.equals("move")) {
        Vec3 position=vector(in.getAsJsonArray("position")),velocity=vector(in.getAsJsonArray("velocity"));
        float width=f(in.get("width_f32_bits")),height=f(in.get("height_f32_bits"));
        double d2=delta.lengthSqr();boolean changed=d2>1e-7||request.lengthSqr()-d2<1e-7;
        if(changed) {
          Vec3 proposed=position.add(delta);
          if(position.x!=proposed.x||position.y!=proposed.y||position.z!=proposed.z)position=proposed;
          b=EntityDimensions.fixed(width,height).makeBoundingBox(position);
        }
        boolean xb=!Mth.equal(request.x,delta.x),zb=!Mth.equal(request.z,delta.z),vc=request.y!=delta.y,below=vc&&request.y<0.0;
        boolean active=(Math.abs(request.y)>0.0&&vc)||xb||zb;
        if(active)velocity=new Vec3(xb?-velocity.x*0.0:velocity.x,vc?(0.0-velocity.y)*1.0*0.0:velocity.y,zb?-velocity.z*0.0:velocity.z);
        velocity=velocity.multiply(1.0,1.0,1.0);
        expected.put("position",vectorBits(position));expected.put("box",boxBits(b));expected.put("velocity",vectorBits(velocity));
        expected.put("flags",List.of(below,xb||zb,vc,below,changed));
      }
    }
    return Map.of("id",c.get("id").getAsString(),"expected",expected,"observation",observed);
  }
  public static void main(String[] args) throws Exception {
    SharedConstants.tryDetectVersion();Bootstrap.bootStrap();
    try(BufferedReader r=Files.newBufferedReader(Path.of(args[0]));PrintWriter w=new PrintWriter(Files.newBufferedWriter(Path.of(args[1])))) {
      for(String line;(line=r.readLine())!=null;)w.println(JSON.toJson(observe(JsonParser.parseString(line).getAsJsonObject())));
    }
  }
}
'''

# This class supplies storage and unrelated services to the actual Level. It
# never overrides Entity.move/collide, collision flags, restitution or position.
DIRECT_SOURCE = r'''
import java.util.*;
import java.lang.reflect.*;
import com.google.gson.*;
import com.mojang.serialization.Lifecycle;
import net.minecraft.core.*;
import net.minecraft.core.registries.*;
import net.minecraft.resources.*;
import net.minecraft.data.registries.VanillaRegistries;
import net.minecraft.world.level.*;
import net.minecraft.world.level.storage.*;
import net.minecraft.world.level.dimension.*;
import net.minecraft.world.level.block.*;
import net.minecraft.world.level.block.state.*;
import net.minecraft.world.level.material.*;
import net.minecraft.world.level.border.*;
import net.minecraft.world.entity.*;
import net.minecraft.world.phys.*;
import net.minecraft.world.phys.shapes.*;

class ReferenceDirectMovementProbe {
  static RegistryAccess ACCESS;
  static Holder<DimensionType> DIMENSION;
  static final Method FULL_COLLIDE;
  static {
    try { FULL_COLLIDE=Entity.class.getDeclaredMethod("collide",Vec3.class);FULL_COLLIDE.setAccessible(true); }
    catch(ReflectiveOperationException e) { throw new ExceptionInInitializerError(e); }
  }
  @SuppressWarnings("unchecked")
  static <T> Registry<T> registry(HolderLookup.RegistryLookup<T> source) {
    // RegistryLookup's covariant key has the same T as its element stream.
    MappedRegistry<T> r=new MappedRegistry<>((ResourceKey<? extends Registry<T>>)(ResourceKey<?>)source.key(),Lifecycle.stable());
    source.listElements().forEach(h->r.register(h.key(),h.value(),RegistrationInfo.BUILT_IN));
    r.bindAllTagsToEmpty();return r.freeze();
  }
  static void initialize() {
    if(ACCESS!=null)return;
    HolderLookup.Provider p=VanillaRegistries.createWorldLookup();
    ACCESS=new RegistryAccess.ImmutableRegistryAccess(List.of(registry(p.lookupOrThrow(Registries.BIOME)),registry(p.lookupOrThrow(Registries.DAMAGE_TYPE))));
    DIMENSION=p.lookupOrThrow(Registries.DIMENSION_TYPE).getOrThrow(ResourceKey.create(Registries.DIMENSION_TYPE,Identifier.parse("minecraft:overworld")));
  }
  static class Data implements WritableLevelData {
    public void setSpawn(LevelData.RespawnData d){}
    public LevelData.RespawnData getRespawnData(){return LevelData.RespawnData.DEFAULT;}
    public long getGameTime(){return 0L;}
    public boolean isHardcore(){return false;}
    public net.minecraft.world.Difficulty getDifficulty(){return net.minecraft.world.Difficulty.NORMAL;}
    public boolean isDifficultyLocked(){return false;}
  }
  static String purpose() {
    List<StackWalker.StackFrame> stack=StackWalker.getInstance().walk(s->s.toList());
    if(stack.stream().anyMatch(f->f.getClassName().equals(Entity.class.getName())&&f.getMethodName().equals("collideBoundingBox")))return "initial";
    if(stack.stream().anyMatch(f->f.getClassName().equals(Entity.class.getName())&&f.getMethodName().equals("collide")))return "step";
    return "support_or_other";
  }
  static List<Map<String,Object>> shapeInputs(List<VoxelShape> shapes) {
    List<Map<String,Object>> out=new ArrayList<>();
    for(VoxelShape s:shapes) {
      List<AABB> boxes=s.toAabbs();
      if(s.isEmpty()||boxes.size()!=1||s.getCoords(net.minecraft.core.Direction.Axis.X).size()!=2||s.getCoords(net.minecraft.core.Direction.Axis.Y).size()!=2||s.getCoords(net.minecraft.core.Direction.Axis.Z).size()!=2)
        throw new IllegalArgumentException("Direct fixture exceeded independent one-cell shape contract: "+s);
      out.add(Map.of("kind","raw_array_box","box",ReferenceMovementProbe.boxBits(boxes.getFirst())));
    }
    return out;
  }
  static class FixtureLevel extends Level {
    final Map<BlockPos,BlockState> blocks=new HashMap<>();
    final WorldBorder border=new WorldBorder();
    final List<Map<String,Object>> queries=new ArrayList<>();
    final Map<String,Integer> calls=new TreeMap<>();
    final List<List<VoxelShape>> initial=new ArrayList<>(),step=new ArrayList<>();
    FixtureLevel(){super(new Data(),Level.OVERWORLD,ACCESS,DIMENSION,false,false,0L,1000);}
    void hit(String s){calls.merge(s,1,Integer::sum);}
    void clearTrace(){queries.clear();calls.clear();initial.clear();step.clear();}
    public BlockState getBlockState(BlockPos p){hit("getBlockState");return blocks.getOrDefault(p,Blocks.AIR.defaultBlockState());}
    public FluidState getFluidState(BlockPos p){hit("getFluidState");return getBlockState(p).getFluidState();}
    public net.minecraft.world.level.block.entity.BlockEntity getBlockEntity(BlockPos p){hit("getBlockEntity");return null;}
    public BlockGetter getChunkForCollisions(int x,int z){hit("getChunkForCollisions");return this;}
    public boolean hasChunk(int x,int z){hit("hasChunk");return true;}
    public WorldBorder getWorldBorder(){hit("getWorldBorder");return border;}
    public List<VoxelShape> getEntityCollisions(Entity e,AABB b){hit("getEntityCollisions");queries.add(Map.of("kind","entity","box",ReferenceMovementProbe.boxBits(b),"purpose","initial_entity","shapes",List.of()));return List.of();}
    public Iterable<VoxelShape> getBlockCollisions(Entity e,AABB b){
      hit("getBlockCollisions");List<VoxelShape> shapes=new ArrayList<>();super.getBlockCollisions(e,b).forEach(shapes::add);
      String purpose=purpose();queries.add(Map.of("kind","block","box",ReferenceMovementProbe.boxBits(b),"purpose",purpose,"shapes",shapeInputs(shapes)));
      if(purpose.equals("initial"))initial.add(shapes);if(purpose.equals("step"))step.add(shapes);return shapes;
    }
    protected net.minecraft.world.level.entity.LevelEntityGetter<Entity> getEntities(){throw new IllegalStateException("Unexpected fixture service: getEntities");}
    public void gameEvent(Holder<net.minecraft.world.level.gameevent.GameEvent> event,Vec3 v,net.minecraft.world.level.gameevent.GameEvent.Context c){hit("gameEvent_sink");}
    public int getSeaLevel(){throw new IllegalStateException("Unexpected fixture service: getSeaLevel");}
    public String gatherChunkSourceStats(){throw new IllegalStateException("Unexpected fixture service: gatherChunkSourceStats");}
    public Collection<net.minecraft.world.entity.boss.enderdragon.EnderDragonPart> dragonParts(){throw new IllegalStateException("Unexpected fixture service: dragonParts");}
    public List<? extends net.minecraft.world.entity.player.Player> players(){throw new IllegalStateException("Unexpected fixture service: players");}
    public Holder<net.minecraft.world.level.biome.Biome> getUncachedNoiseBiome(int x,int y,int z){throw new IllegalStateException("Unexpected fixture service: getUncachedNoiseBiome");}
    public net.minecraft.world.TickRateManager tickRateManager(){throw new IllegalStateException("Unexpected fixture service: tickRateManager");}
    public net.minecraft.world.attribute.EnvironmentAttributeSystem environmentAttributes(){throw new IllegalStateException("Unexpected fixture service: environmentAttributes");}
    public net.minecraft.world.clock.ClockManager clockManager(){throw new IllegalStateException("Unexpected fixture service: clockManager");}
    public Entity getEntity(int id){throw new IllegalStateException("Unexpected fixture service: getEntity");}
    public net.minecraft.world.flag.FeatureFlagSet enabledFeatures(){throw new IllegalStateException("Unexpected fixture service: enabledFeatures");}
    public net.minecraft.world.item.crafting.RecipeAccess recipeAccess(){throw new IllegalStateException("Unexpected fixture service: recipeAccess");}
    public net.minecraft.world.level.chunk.ChunkSource getChunkSource(){throw new IllegalStateException("Unexpected fixture service: getChunkSource");}
    public net.minecraft.world.level.saveddata.maps.MapItemSavedData getMapData(net.minecraft.world.level.saveddata.maps.MapId id){throw new IllegalStateException("Unexpected fixture service: getMapData");}
    public LevelData.RespawnData getRespawnData(){throw new IllegalStateException("Unexpected fixture service: getRespawnData");}
    public net.minecraft.world.scores.Scoreboard getScoreboard(){throw new IllegalStateException("Unexpected fixture service: getScoreboard");}
    public net.minecraft.world.ticks.LevelTickAccess<Block> getBlockTicks(){throw new IllegalStateException("Unexpected fixture service: getBlockTicks");}
    public net.minecraft.world.ticks.LevelTickAccess<Fluid> getFluidTicks(){throw new IllegalStateException("Unexpected fixture service: getFluidTicks");}
    public void destroyBlockProgress(int id,BlockPos p,int stage){throw new IllegalStateException("Unexpected fixture service: destroyBlockProgress");}
    public void explode(Entity e,net.minecraft.world.damagesource.DamageSource d,net.minecraft.world.level.ExplosionDamageCalculator c,double x,double y,double z,float r,boolean fire,Level.ExplosionInteraction interaction,net.minecraft.core.particles.ParticleOptions small,net.minecraft.core.particles.ParticleOptions large,net.minecraft.util.random.WeightedList<net.minecraft.core.particles.ExplosionParticleInfo> particles,Holder<net.minecraft.sounds.SoundEvent> sound){throw new IllegalStateException("Unexpected fixture service: explode");}
    public void levelEvent(Entity e,int id,BlockPos p,int data){throw new IllegalStateException("Unexpected fixture service: levelEvent");}
    public void playSeededSound(Entity e,double x,double y,double z,Holder<net.minecraft.sounds.SoundEvent> sound,net.minecraft.sounds.SoundSource source,float volume,float pitch,long seed){throw new IllegalStateException("Unexpected fixture service: playSeededSound");}
    public void playSeededSound(Entity e,Entity target,Holder<net.minecraft.sounds.SoundEvent> sound,net.minecraft.sounds.SoundSource source,float volume,float pitch,long seed){throw new IllegalStateException("Unexpected fixture service: playSeededSound");}
    public void sendBlockUpdated(BlockPos p,BlockState old,BlockState next,int flags){throw new IllegalStateException("Unexpected fixture service: sendBlockUpdated");}
    public void setRespawnData(LevelData.RespawnData d){throw new IllegalStateException("Unexpected fixture service: setRespawnData");}
  }
  static class FixtureEntity extends Entity {
    float step;Vec3 recorded;
    FixtureEntity(FixtureLevel level,EntityType<?> type,float maximum){super(type,level);step=maximum;setShiftKeyDown(true);}
    protected void defineSynchedData(net.minecraft.network.syncher.SynchedEntityData.Builder b){}
    protected void readAdditionalSaveData(ValueInput i){}
    protected void addAdditionalSaveData(ValueOutput o){}
    public boolean hurtServer(net.minecraft.server.level.ServerLevel l,net.minecraft.world.damagesource.DamageSource s,float a){return false;}
    public float maxUpStep(){return step;}
    protected MovementEmission getMovementEmission(){return MovementEmission.NONE;}
    public void recordMovement(MoverType type,Vec3 v){recorded=v;super.recordMovement(type,v);}
  }
  static Map<String,Object> observe(JsonObject c) throws Exception {
    initialize();JsonObject in=c.getAsJsonObject("input");FixtureLevel level=new FixtureLevel();
    for(JsonElement item:in.getAsJsonArray("world_blocks")) {
      JsonObject block=item.getAsJsonObject();JsonArray p=block.getAsJsonArray("position");
      Block value=BuiltInRegistries.BLOCK.getValue(Identifier.parse(block.get("identifier").getAsString()));
      if(value!=Blocks.STONE&&value!=Blocks.DIRT&&value!=Blocks.OAK_PLANKS)throw new IllegalArgumentException("Unsupported direct world fixture block");
      level.blocks.put(new BlockPos(p.get(0).getAsInt(),p.get(1).getAsInt(),p.get(2).getAsInt()),value.defaultBlockState());
    }
    EntityType<?> type=BuiltInRegistries.ENTITY_TYPE.getValue(Identifier.parse(in.get("entity_type").getAsString()));
    FixtureEntity entity=new FixtureEntity(level,type,ReferenceMovementProbe.f(in.get("maximum_f32_bits")));
    entity.setPos(ReferenceMovementProbe.vector(in.getAsJsonArray("position")));
    entity.setOnGround(in.get("grounded").getAsBoolean());entity.setDeltaMovement(ReferenceMovementProbe.vector(in.getAsJsonArray("velocity")));
    if(!entity.canSimulateMovement()||!entity.isLocalInstanceAuthoritative()||!entity.isSuppressingBounce())throw new AssertionError("Neutral entity contract failed");
    AABB initialBox=entity.getBoundingBox();Vec3 initialPosition=entity.position(),request=ReferenceMovementProbe.vector(in.getAsJsonArray("requested"));
    level.clearTrace();Vec3 resolved=(Vec3)FULL_COLLIDE.invoke(entity,request);
    List<VoxelShape> initial=level.initial.isEmpty()?List.of():level.initial.getFirst();
    List<VoxelShape> step=level.step.isEmpty()?List.of():level.step.getFirst();
    Vec3 baseline=request.lengthSqr()==0.0?request:ReferenceMovementProbe.collide(request,initialBox,initial);
    boolean stepped=resolved.horizontalDistanceSqr()>baseline.horizontalDistanceSqr();
    List<Map<String,Object>> collideQueries=List.copyOf(level.queries);
    Map<String,Object> actualInput=new TreeMap<>();
    actualInput.put("box",ReferenceMovementProbe.boxBits(initialBox));actualInput.put("position",ReferenceMovementProbe.vectorBits(initialPosition));
    actualInput.put("initial",shapeInputs(initial));actualInput.put("step",shapeInputs(step));
    actualInput.put("width_f32_bits",String.format(Locale.ROOT,"%08x",Float.floatToRawIntBits(type.getDimensions().width())));
    actualInput.put("height_f32_bits",String.format(Locale.ROOT,"%08x",Float.floatToRawIntBits(type.getDimensions().height())));
    level.clearTrace();entity.recorded=null;
    // The authoritative expected transition is the untouched production method.
    entity.move(MoverType.SELF,request);
    if(entity.recorded!=null&&!ReferenceMovementProbe.vectorBits(entity.recorded).equals(ReferenceMovementProbe.vectorBits(resolved)))throw new AssertionError("move versus actual collide mismatch");
    List<Map<String,Object>> moveCollisionQueries=level.queries.stream().filter(q->!q.get("purpose").equals("support_or_other")).toList();
    if(!moveCollisionQueries.equals(collideQueries))throw new AssertionError("move versus actual collide query mismatch");
    if(entity.minorHorizontalCollision)throw new AssertionError("Generic entity minor collision exceeded scope");
    Map<String,Object> expected=new TreeMap<>();
    expected.put("displacement",ReferenceMovementProbe.vectorBits(resolved));expected.put("stepped",stepped);
    expected.put("position",ReferenceMovementProbe.vectorBits(entity.position()));expected.put("box",ReferenceMovementProbe.boxBits(entity.getBoundingBox()));
    expected.put("velocity",ReferenceMovementProbe.vectorBits(entity.getDeltaMovement()));
    expected.put("flags",List.of(entity.onGround(),entity.horizontalCollision,entity.verticalCollision,entity.verticalCollisionBelow,entity.recorded!=null));
    Map<String,Object> observed=new TreeMap<>();observed.put("actual_input",actualInput);observed.put("full_entity_move_executed",true);
    observed.put("collision_queries",collideQueries);observed.put("move_queries",List.copyOf(level.queries));observed.put("fixture_service_calls",new TreeMap<>(level.calls));
    observed.put("baseline",ReferenceMovementProbe.vectorBits(baseline));
    observed.put("source_entity_type",EntityType.getKey(type).toString());observed.put("source_entity_class",entity.getClass().getName());
    observed.put("fall_distance_bits",ReferenceMovementProbe.bits(entity.fallDistance));observed.put("minor_horizontal_collision",entity.minorHorizontalCollision);
    return Map.of("id",c.get("id").getAsString(),"expected",expected,"observation",observed);
  }
}
'''

def bits(v): return struct.pack('>d',v).hex()
def fbits(v): return struct.pack('>f',v).hex()
def raw(v): return {'kind':'raw_array_box','box':list(map(bits,v))}

def generate_inputs():
    cases=[]
    def add(name,box,requested,initial,step=None,grounded=True,maximum=.6,previous=0.,position=None,velocity=None,width=1.,height=1.,tags=()):
        value={'box':list(map(bits,box)),'requested':list(map(bits,requested)), 'initial':initial,'step':initial if step is None else step,
               'grounded':grounded,'maximum_f32_bits':fbits(maximum),'previous_f32_bits':fbits(previous),
               'position':list(map(bits,position or [0.5,0.,0.5])),'velocity':list(map(bits,velocity or requested)),
               'width_f32_bits':fbits(width),'height_f32_bits':fbits(height)}
        for op in ['collide','heights','resolve','move']:
            cases.append({'id':f'{name}-{op}','operation':op,'input':value,'tags':list(tags)})
    unit=[0.,0.,0.,1.,1.,1.];floor=raw([-20.,-1.,-20.,20.,0.,20.]);wall=raw([1.5,-1.,-3.,2.5,4.,3.])
    for i,v in enumerate([[0.,0.,0.],[-0.,-0.,-0.],[1.,0.,0.],[0.,-1.,0.],[0.,1.,0.],[1.,-.5,1.],[-1.,0.,-1.]]):
        for label,shapes in [('free',[]),('empty',[{'kind':'empty'}]),('floor',[floor]),('wall',[wall]),('corner',[wall,raw([-3.,-1.,1.5,3.,4.,2.5])])]:
            add(f'basic-{label}-{i}',unit,v,shapes,tags=['targeted',label,'signed_zero'])
    eps=1e-7; meps=struct.unpack('>f',struct.pack('>f',1e-5))[0]
    for i,d in enumerate([math.nextafter(eps,0.),eps,math.nextafter(eps,math.inf),-eps,eps/2,-eps/2,math.nextafter(meps,0.),meps,math.nextafter(meps,math.inf),.0001,.0004]):
        for j,obs in enumerate([[raw([1.,0.,0.,2.,1.,1.])],[{'kind':'empty'}],[]]):
            add(f'epsilon-{i}-{j}',unit,[d,-d,d],obs,tags=['targeted','epsilon','collision_flags','position_threshold'])
    floatstep=struct.unpack('>f',struct.pack('>f',.6))[0]
    for i,h in enumerate([0.,.125,.5,math.nextafter(.5,0.),math.nextafter(.5,math.inf),.6,floatstep,math.nextafter(floatstep,0.),math.nextafter(floatstep,math.inf),.625,1.]):
        for grounded in [False,True]:
            for dy in [0.,-.25,.25]:
                step=raw([1.25,0.,0.,2.5,h,1.]);shapes=[floor,step]
                add(f'step-{i}-{grounded}-{dy}',unit,[1.,dy,0.],shapes,grounded=grounded,tags=['targeted','step_height','candidate_cast','grounded'])
                add(f'step-ceiling-{i}-{grounded}-{dy}',unit,[1.,dy,0.],shapes+[raw([-.5,1.3,-.5,3.,2.,2.])],grounded=grounded,tags=['targeted','step_ceiling'])
    for i,pair in enumerate([[1.,1.],[1.,math.nextafter(1.,math.inf)],[math.nextafter(1.,math.inf),1.],[-1.,1.],[1.,-1.],[-1.,-1.]]):
        obstacles=[raw([1.25,0.,.8,2.,2.,1.5]),raw([.8,0.,1.25,1.5,2.,2.])]
        for j,s in enumerate([obstacles,list(reversed(obstacles)),[{'kind':'empty'},*obstacles]]):
            add(f'ordering-{i}-{j}',unit,[pair[0],0.,pair[1]],s,maximum=0.,tags=['targeted','corner','axis_order','obstacle_order'])
    for i,low in enumerate([-0.,0.,-.25,2**24,math.nextafter(.5,math.inf)]):
        highs=[low-.25,low,math.nextafter(low,math.inf),low+.5,low+floatstep]
        s=[raw([1.,v,0.,2.,v+.125,1.]) for v in highs]+[{'kind':'empty'}]
        add(f'height-list-{i}',[0.,low,0.,1.,low+1.,1.],[1.,-.125,1.],s,previous=-.125,tags=['targeted','candidate_order','candidate_cast'])
    rng=random.Random(SEED)
    for i in range(600):
        x,y,z=[rng.randint(-20,20)/4 for _ in range(3)]
        width=rng.choice([.6,1.,1.5]);height=rng.choice([1.,1.8,2.]);w=struct.unpack('>f',struct.pack('>f',width))[0]/2;h=struct.unpack('>f',struct.pack('>f',height))[0]
        b=[x-w,y,z-w,x+w,y+h,z+w]
        requested=[rng.choice([-2.,-.5,-eps,0.,eps/2,eps,.5,2.]) for _ in range(3)]
        s=[]
        for _ in range(rng.randrange(7)):
            if rng.randrange(9)==0:s.append({'kind':'empty'});continue
            a=[x+rng.randint(-8,8)/4,y+rng.randint(-4,8)/4,z+rng.randint(-8,8)/4]
            extent=[rng.choice([0.,.125,.5,1.,2.]) for _ in range(3)]
            s.append(raw(a+[a[k]+extent[k] for k in range(3)]))
        add(f'random-{i}',b,requested,s,grounded=bool(rng.randrange(2)),maximum=rng.choice([0.,.5,.6,1.]),previous=rng.choice([0.,-.25,.25]),position=[x,y,z],velocity=[rng.choice([-2.,-0.,0.,.25,2.]) for _ in range(3)],width=width,height=height,tags=['seeded_random','finite_inputs'])
    queries=[]
    for c in cases:
        if c['operation']=='move' and (c['id'].startswith(('basic-','epsilon-','height-list-')) or c['id'].startswith('random-') and int(c['id'].split('-')[1])<100):
            for operation in ['block_query','entity_query','step_query','make_box']:
                queries.append({**c,'id':c['id'].removesuffix('move')+operation,'operation':operation,'tags':c['tags']+['query_bounds' if operation!='make_box' else 'entity_dimensions']})
    return cases+queries+generate_direct_inputs()

def generate_direct_inputs():
    cases=[]
    floor=[{'position':[x,-1,z],'identifier':['minecraft:stone','minecraft:dirt','minecraft:oak_planks'][(x+z)%3]} for z in range(-3,4) for x in range(-3,4)]
    def block(x,y,z,identifier='minecraft:stone'):return {'position':[x,y,z],'identifier':identifier}
    worlds={'free':[], 'floor':floor,
            'wall':floor+[block(1,y,0) for y in range(3)],
            'negative_wall':floor+[block(-1,y,0) for y in range(3)],
            'ceiling':floor+[block(x,2,z) for z in range(-1,2) for x in range(-1,3)],
            'corner':floor+[block(1,y,0) for y in range(3)]+[block(0,y,1,'minecraft:oak_planks') for y in range(3)],
            'step':floor+[block(1,0,0,'minecraft:dirt')],
            'step_ceiling':floor+[block(1,0,0),block(0,2,0),block(1,2,0)]}
    half=struct.unpack('>f',struct.pack('>f',.6))[0]/2
    height=struct.unpack('>f',struct.pack('>f',1.8))[0]
    def add(name,world,requested,grounded=True,maximum=.6,position=None,velocity=None,tags=()):
        p=position if position is not None else [.5,0.,.5]
        v=velocity if velocity is not None else [1.25,-.25,-2.]
        b=[p[0]-half,p[1],p[2]-half,p[0]+half,p[1]+height,p[2]+half]
        value={'box':list(map(bits,b)),'position':list(map(bits,p)),'velocity':list(map(bits,v)),'requested':list(map(bits,requested)),
               'grounded':grounded,'maximum_f32_bits':fbits(maximum),'previous_f32_bits':fbits(0.),'width_f32_bits':fbits(.6),'height_f32_bits':fbits(1.8),
               'initial':[],'step':[],'world_blocks':world,'entity_type':'minecraft:player'}
        cases.append({'id':'actual-entity-'+name,'operation':'entity_move','input':value,'tags':['actual_entity_move','actual_level','actual_block_queries',*tags]})
    requests=[[0.,0.,0.],[-0.,-0.,-0.],[1.,0.,0.],[-1.,0.,0.],[0.,-1.,0.],[0.,1.,0.],[1.,-.25,1.],[1.,0.,math.nextafter(1.,math.inf)],[-1.,-.25,-1.]]
    for name,world in worlds.items():
        for i,requested in enumerate(requests):
            add(f'{name}-{i}',world,requested,tags=[name,'signed_zero','axis_order'])
    for name in ['step','step_ceiling']:
        for maximum in [0.,.6,struct.unpack('>f',bytes.fromhex('3f7fffff'))[0],1.,struct.unpack('>f',bytes.fromhex('3f800001'))[0]]:
            for grounded in [False,True]:
                for dy in [-.25,0.,.25]:
                    add(f'{name}-limit-{fbits(maximum)}-{grounded}-{bits(dy)}',worlds[name],[1.,dy,0.],grounded,maximum,tags=['step','step_threshold','grounded'])
    collision_eps=1e-7;flag_eps=struct.unpack('>f',struct.pack('>f',1e-5))[0]
    for i,delta in enumerate([math.nextafter(collision_eps,0.),collision_eps,math.nextafter(collision_eps,math.inf),collision_eps/2,
                               math.nextafter(flag_eps,0.),flag_eps,math.nextafter(flag_eps,math.inf),.0001,.0004]):
        for sign in [-1.,1.]:
            add(f'touching-epsilon-{i}-{sign}',worlds['wall'],[sign*delta,0.,0.],position=[1.-half,0.,.5],tags=['epsilon','touching_wall','position_gate'])
    for i,p in enumerate([[-0.,1.,-0.],[.5,-0.,.5],[0.,0.,0.]]):
        for j,requested in enumerate([[0.,0.,0.],[-0.,-0.,-0.],[1e-7,-0.,0.]]):
            add(f'signed-position-{i}-{j}',worlds['free'],requested,position=p,velocity=[-0.,0.,-0.],tags=['signed_zero','position_payload'])
    return cases

CLASSES=['net.minecraft.world.entity.Entity','net.minecraft.world.entity.EntityDimensions','net.minecraft.core.Direction','net.minecraft.world.phys.Vec3','net.minecraft.util.Mth','net.minecraft.world.phys.AABB',
         'net.minecraft.world.level.Level','net.minecraft.world.level.BlockCollisions','net.minecraft.world.level.CollisionGetter','net.minecraft.world.level.CommonLevelAccessor',
         'net.minecraft.world.entity.EntityType','net.minecraft.world.entity.EntityTypes','net.minecraft.data.registries.VanillaRegistries','net.minecraft.world.level.dimension.DimensionType',
         'net.minecraft.world.level.chunk.PalettedContainerFactory','net.minecraft.world.damagesource.DamageSources']
METHODS={'collide','collideWithShapes','collectCandidateStepUpHeights','collectCollidersIgnoringWorldBorder','collideBoundingBox','move','expandTowards','makeBoundingBox','fixed','axisStepOrder','lengthSqr','horizontalDistanceSqr','equal','restituteMovementAfterCollisions','getInputVector','sin','cos','add','subtract','multiply',
         'Level','BlockCollisions','DamageSources','getBlockState','getFluidState','getChunkForCollisions','getEntityCollisions','getBlockCollisions','findSupportingBlock','checkSupportingBlock','setPosRaw','setPos','getOnPosLegacy','getBlockSpeedFactor','isSuppressingBounce','isLocalInstanceAuthoritative','canSimulateMovement','recordMovement','getMovementEmission','checkFallDamage','getDimensions','maxUpStep','createWorldLookup','create','computeNext'}
def source_inventory(jars):
    r=subprocess.run([str(JAVA.parent/'javap'),'-classpath',str(jars[0]),'-c','-p',*CLASSES],capture_output=True,text=True,check=True)
    (ROOT/'reference/cache/movement-bytecode.txt').write_text(r.stdout)
    records={}
    with zipfile.ZipFile(jars[0]) as archive:
        for owner,chunk in zip(CLASSES,r.stdout.split('Compiled from "')[1:],strict=True):
            entry=owner.replace('.','/')+'.class';methods=[]
            for part in re.split(r'(?=^  (?:public|private|protected|static).*(?:;|\{)$)',chunk,flags=re.M):
                sig=part.splitlines()[0]
                if any(re.search(r'\b'+re.escape(m)+r'\(',sig) for m in METHODS):
                    methods.append({'signature':sig.strip(),'bytecode_text_sha256':hashlib.sha256(part.encode()).hexdigest(),
                                    'direct_call_references':sorted(set(re.findall(r'// (?:InterfaceMethod|Method) (.+)',part)))})
            records[owner]={'class_entry':entry,'class_sha256':hashlib.sha256(archive.read(entry)).hexdigest(),'methods':methods}
    return {'classes':records,'complete_javap_text_sha256':hashlib.sha256(r.stdout.encode()).hexdigest()}

def run_java(inputs,jars,suffix=''):
    directory=ROOT/'reference/extracted/movement_probe';directory.mkdir(parents=True,exist_ok=True)
    source=directory/'ReferenceMovementProbe.java';source.write_text(SOURCE)
    direct_source=directory/'ReferenceDirectMovementProbe.java';direct_source.write_text(DIRECT_SOURCE)
    classes=directory/'classes';classes.mkdir(exist_ok=True)
    cp=':'.join(map(str,jars));compile_command=[str(JAVA.parent/'javac'),'-cp',cp,'-d',str(classes),str(source),str(direct_source)]
    start=time.monotonic();compiled=subprocess.run(compile_command,check=True,capture_output=True,text=True)
    compile_seconds=time.monotonic()-start
    compile_log=ROOT/f'reference/cache/movement-javac{suffix}.log';compile_log.write_text(compiled.stdout+compiled.stderr)
    incoming=ROOT/f'reference/cache/movement-input{suffix}.jsonl';outgoing=ROOT/f'reference/cache/movement-observed{suffix}.jsonl'
    incoming.write_text(''.join(canonical(c).decode()+'\n' for c in inputs))
    command=[str(JAVA),'-cp',str(classes)+':'+cp,'ReferenceMovementProbe',str(incoming),str(outgoing)]
    start=time.monotonic();r=subprocess.run(command,capture_output=True,text=True);java_seconds=time.monotonic()-start
    java_log=ROOT/f'reference/cache/movement-java{suffix}.log';java_log.write_text(r.stdout+r.stderr);r.check_returncode()
    observed=[json.loads(v) for v in outgoing.read_text().splitlines()]
    assert [c['id'] for c in observed]==[c['id'] for c in inputs]
    return observed,{'compile_command':compile_command,'run_command':command,'source_sha256':hashlib.sha256((SOURCE+DIRECT_SOURCE).encode()).hexdigest(),
                     'compile_seconds':round(compile_seconds,6),'java_seconds':round(java_seconds,6),
                     'compile_log_sha256':fingerprint(compile_log)['sha256'],'java_log_sha256':fingerprint(java_log)['sha256'],
                     'input_jsonl_sha256':fingerprint(incoming)['sha256'],'observation_jsonl_sha256':fingerprint(outgoing)['sha256']}

def validate(data,observed=None):
    assert data['pin']=='26.3' and data['schema_version']==1
    assert hashlib.sha256(canonical(data['cases'])).hexdigest()==data['cases_sha256'],'case checksum'
    assert [{k:c[k] for k in ['id','operation','input','tags']} for c in data['cases']]==generate_inputs(),'input regeneration'
    direct=[c for c in data['cases'] if c['operation']=='entity_move']
    assert data['direct_entity_move']['case_count']==len(direct)
    assert direct and all(c['observation']['full_entity_move_executed'] for c in direct)
    if observed is not None:
        assert [{k:c[k] for k in ['id','expected','observation']} for c in data['cases']]==observed,'independent Java outputs'
    return {'case_count':len(data['cases']),'operation_counts':dict(collections.Counter(c['operation'] for c in data['cases'])),'oracle_compared':observed is not None,
            'full_entity_move_cases':len(direct),'full_entity_step_outcomes':sum(c['expected']['stepped'] for c in direct),
            'actual_collision_query_count':sum(len(c['observation']['collision_queries']) for c in direct)}

def extract():
    jars,release=verified_classpath();inputs=generate_inputs();observed,execution=run_java(inputs,jars)
    cases=[{**i,**o} for i,o in zip(inputs,observed,strict=True)]
    runtime=subprocess.run([str(JAVA),'-version'],capture_output=True,text=True,check=True)
    data={'schema_version':1,'pin':'26.3','random_input_seed':SEED,'cases_sha256':hashlib.sha256(canonical(cases)).hexdigest(),'cases':cases,
          'server_bundle_sha256':release['server_bundle']['sha256'],'server_class_jar_sha256':release['server_bundle']['nested_server_sha256'],
          'runtime_executable':fingerprint(JAVA),'runtime_version':(runtime.stdout+runtime.stderr).strip().splitlines(),
          'source':source_inventory(jars),'probe_java_source_sha256':hashlib.sha256((SOURCE+DIRECT_SOURCE).encode()).hexdigest(),
          'scope':'Direct actual Entity.collideWithShapes/candidate collector plus actual Entity.move and private Entity.collide in a narrow real Level using real full-cube block states and production BlockCollisions. Earlier resolve/move lanes retain a separately labelled composed instrument.',
          'confidence':'high for recorded direct game-method and neutral Entity.move cases; moderate for older composed-only cases; no complete player/world movement parity claim',
          'classpath_libraries':[fingerprint(p) for p in jars[1:]],
          'direct_entity_move':{'case_count':sum(c['operation']=='entity_move' for c in cases),'full_production_method_executed':True,
             'world':'Real Level superclass initialized with official vanilla biome/damage/dimension bootstrap values; sparse finite full-cube map; all collision chunks available; no other actors; default distant world border',
             'entity':'FixtureEntity extends actual Entity, uses registered minecraft:player type and its actual default dimensions; not ServerPlayer or LivingEntity',
             'preserved_implementations':['Entity.move','Entity.collide','Entity.collideWithShapes','Entity.restituteMovementAfterCollisions','Entity.setPos/setPosRaw','Entity.checkSupportingBlock','Entity.checkFallDamage','CollisionGetter.getBlockCollisions','BlockCollisions.computeNext','BlockState.getCollisionShape'],
             'entity_overrides':{'maxUpStep':'input float value','getMovementEmission':'NONE; excludes movement sounds/events','recordMovement':'records displacement and calls super','defineSynchedData/readAdditionalSaveData/addAdditionalSaveData':'required abstract fixture methods; no additional state','hurtServer':'false; health/damage result outside compared scope'},
             'level_overrides':{'getBlockState':'real default state from finite map, otherwise AIR','getFluidState':'state fluid','getBlockEntity':'null; fixture has no block entities','getChunkForCollisions':'this finite BlockGetter','hasChunk':'true; loaded fixture','getEntityCollisions':'empty; no other entities; records actual query','getWorldBorder':'actual default WorldBorder','getBlockCollisions':'materializes and records super iterable, preserves order/results','gameEvent':'inert sink with call count','unrelated abstract services':'throw if unexpectedly reached'},
             'level_data_contract':'game time0, NORMAL difficulty, non-hardcore, unlocked; required respawn getter default; no saved world',
             'registry_boundary':'Official VanillaRegistries values materialized for BIOME/DAMAGE_TYPE; tags bound empty in these copied constructor-only registries. Blocks/entities use original built-in registries.',
             'compared_outputs':['position raw bits','AABB raw bits','velocity raw bits','onGround/horizontalCollision/verticalCollision/verticalCollisionBelow','position application via observed recordMovement callback','displacement from actual private collide with agreement when move records','step outcome from strict improvement over actual initial collision','actual initial/entity/step query bounds and ordered collider shapes']}}
    write_json(OUTPUT,data);evidence={'status':'passed','reference':fingerprint(OUTPUT),'execution':execution,'validation':validate(data,observed)}
    write_json(ROOT/'evidence/movement-reference.json',evidence);return evidence

def verify():
    jars,release=verified_classpath();data=json.loads(OUTPUT.read_text())
    assert data['server_class_jar_sha256']==release['server_bundle']['nested_server_sha256']
    assert data['runtime_executable']==fingerprint(JAVA) and data['source']==source_inventory(jars)
    assert data['probe_java_source_sha256']==hashlib.sha256((SOURCE+DIRECT_SOURCE).encode()).hexdigest()
    observed=[json.loads(v) for v in (ROOT/'reference/cache/movement-observed.jsonl').read_text().splitlines()]
    evidence={'status':'passed','validation':validate(data,observed),'official_class_and_runtime_hashes_checked':True}
    write_json(ROOT/'evidence/movement-reference-validation.json',evidence);return evidence

def selftest():
    jars,_=verified_classpath();data=json.loads(OUTPUT.read_text());inputs=generate_inputs()
    one,first_execution=run_java(inputs,jars,'-selftest1');two,second_execution=run_java(inputs,jars,'-selftest2');assert one==two
    validate(data,one);validate(data,two);failures=[]
    for reseal in [False,True]:
        bad=copy.deepcopy(data);c=next(c for c in bad['cases'] if c['operation']=='collide');c['expected']['displacement'][0]=bits(123.)
        if reseal:bad['cases_sha256']=hashlib.sha256(canonical(bad['cases'])).hexdigest()
        try:validate(bad,one)
        except AssertionError as e:failures.append({'changed_result':True,'resealed':reseal,'rejected':True,'reason':str(e)})
        else:raise AssertionError('oracle mutation was accepted')
    bad=copy.deepcopy(data);c=next(c for c in bad['cases'] if c['id']=='actual-entity-signed-position-0-0')
    c['expected']['position'][0]=bits(0.);bad['cases_sha256']=hashlib.sha256(canonical(bad['cases'])).hexdigest()
    try:validate(bad,one)
    except AssertionError as e:failures.append({'case':'signed_zero_position_regression','resealed':True,'rejected':True,'reason':str(e)})
    else:raise AssertionError('direct Entity.move signed-zero mutation accepted')
    evidence={'status':'passed','independent_java_runs':2,'case_count_per_run':len(one),'actual_entity_move_cases_per_run':data['direct_entity_move']['case_count'],
              'execution':[first_execution,second_execution],'failure_injection':failures}
    write_json(ROOT/'evidence/movement-reference-selftest.json',evidence);return evidence

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);g=parser.add_mutually_exclusive_group();g.add_argument('--verify-existing',action='store_true');g.add_argument('--selftest',action='store_true');a=parser.parse_args()
    result=selftest() if a.selftest else verify() if a.verify_existing else extract();print(json.dumps(result,sort_keys=True))
