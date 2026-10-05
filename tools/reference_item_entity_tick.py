#!/usr/bin/env python3
"""Execute installed ItemEntity tick/merge/fluid receivers, not a host tick."""
import hashlib,json,os,re,subprocess,time,zipfile
from pathlib import Path
from reference_model_probe import verified_client_classpath,JAVA
import reference_movement_probe as Motion
import reference_cooking_effect_entities as Entities
ROOT=Path(__file__).resolve().parents[1];WORK=ROOT/'build/item-entity-tick-reference'
BODY=r'''
class ItemEntityTickReference {
 static final Gson JSON=new GsonBuilder().serializeNulls().create();static Unsafe U;static RegistryOps<JsonElement> OPS;
 static class World extends ServerLevel {
  Map<BlockPos,BlockState> blocks;Map<Long,LevelChunk> chunks;WorldBorder border;EntitySectionStorage<Entity> sections;List<Object> events;int cursor;net.minecraft.server.MinecraftServer fixtureServer;
  private World(){super(null,null,null,null,Level.OVERWORLD,null,false,0,List.of(),false);}
  public net.minecraft.server.MinecraftServer getServer(){return fixtureServer;}
  public boolean isClientSide(){return false;}public int getNextEntityId(){return ++cursor;}
  public BlockState getBlockState(BlockPos p){return blocks.getOrDefault(p,Blocks.AIR.defaultBlockState());}
  public FluidState getFluidState(BlockPos p){return getBlockState(p).getFluidState();}
  public BlockGetter getChunkForCollisions(int x,int z){return this;}
  public boolean hasChunk(int x,int z){return true;}public WorldBorder getWorldBorder(){return border;}
  public List<VoxelShape> getEntityCollisions(Entity e,AABB b){return List.of();}
  public boolean isRainingAt(BlockPos p){return false;}
  public LevelChunk getChunk(int x,int z){return (LevelChunk)getChunk(x,z,net.minecraft.world.level.chunk.status.ChunkStatus.FULL,false);}
  public ChunkAccess getChunk(int x,int z,net.minecraft.world.level.chunk.status.ChunkStatus status,boolean create){return chunks.computeIfAbsent(ChunkPos.pack(x,z),k->new LevelChunk(this,new ChunkPos(x,z)));}
  public <T extends Entity> List<T> getEntities(EntityTypeTest<Entity,T> test,AABB box,Predicate<? super T> predicate){List<T> out=new ArrayList<>();sections.getEntities(test,box,e->{if(predicate.test(e))out.add(e);return Continuation.CONTINUE;});return out;}
  public void gameEvent(Holder<net.minecraft.world.level.gameevent.GameEvent> event,Vec3 p,net.minecraft.world.level.gameevent.GameEvent.Context c){var row=new LinkedHashMap<String,Object>();row.put("kind","game_event");row.put("id",event.unwrapKey().orElseThrow().identifier().toString());if(event.equals(net.minecraft.world.level.gameevent.GameEvent.HIT_GROUND)){row.put("position",CookingEffectEntitiesReference.vec(p));row.put("state",Integer.toUnsignedLong(Block.getId(c.affectedState())));}events.add(row);}
  public void playSeededSound(Entity e,double x,double y,double z,Holder<net.minecraft.sounds.SoundEvent> sound,net.minecraft.sounds.SoundSource source,float volume,float pitch,long seed){events.add(Map.of("kind","sound","volume",Integer.toUnsignedLong(Float.floatToRawIntBits(volume)),"pitch",Integer.toUnsignedLong(Float.floatToRawIntBits(pitch)),"seed",CookingEffectEntitiesReference.bits(seed)));}
  public void addParticle(net.minecraft.core.particles.ParticleOptions p,double x,double y,double z,double vx,double vy,double vz){events.add(Map.of("kind","particle","type",BuiltInRegistries.PARTICLE_TYPE.getKey(p.getType()).toString(),"position",CookingEffectEntitiesReference.vec(new Vec3(x,y,z)),"velocity",CookingEffectEntitiesReference.vec(new Vec3(vx,vy,vz))));}
 }
 static World world(JsonObject c)throws Exception{
  ReferenceDirectMovementProbe.FixtureLevel template=new ReferenceDirectMovementProbe.FixtureLevel();World w=(World)U.allocateInstance(World.class);
  for(Class<?> k=Level.class;k!=null;k=k.getSuperclass())for(Field f:k.getDeclaredFields())if(!Modifier.isStatic(f.getModifiers())){f.setAccessible(true);f.set(w,f.get(template));}
  w.fixtureServer=(net.minecraft.server.MinecraftServer)U.allocateInstance(net.minecraft.server.dedicated.DedicatedServer.class);CookingEffectEntitiesReference.set(w.fixtureServer,"debugSubscribers",new net.minecraft.util.debug.ServerDebugSubscribers(w.fixtureServer));w.blocks=new HashMap<>();w.chunks=new HashMap<>();w.border=new WorldBorder();w.sections=new EntitySectionStorage<>(Entity.class,k->Visibility.TICKING);w.events=new ArrayList<>();CookingEffectEntitiesReference.set(w,"random",RandomSource.create(73));RandomSource sound=RandomSource.createThreadSafe();sound.setSeed(83);CookingEffectEntitiesReference.set(w,"soundSeedGenerator",sound);
  for(var raw:c.getAsJsonArray("blocks")){var b=raw.getAsJsonObject();BlockPos p=new BlockPos(b.get("x").getAsInt(),b.get("y").getAsInt(),b.get("z").getAsInt());BlockState state=BuiltInRegistries.BLOCK.getValue(Identifier.parse(b.get("id").getAsString())).defaultBlockState();if(b.has("level"))state=state.setValue(net.minecraft.world.level.block.state.properties.BlockStateProperties.LEVEL,b.get("level").getAsInt());if(b.has("slab"))state=state.setValue(net.minecraft.world.level.block.state.properties.BlockStateProperties.SLAB_TYPE,net.minecraft.world.level.block.state.properties.SlabType.valueOf(b.get("slab").getAsString()));w.blocks.put(p,state);var section=w.getChunk(p.getX()>>4,p.getZ()>>4).getSection(w.getSectionIndex(p.getY()));section.setBlockState(p.getX()&15,p.getY()&15,p.getZ()&15,state);}
  return w;
 }
 static ItemEntity entity(World w,JsonObject c,int id)throws Exception{
  ItemStack item=new ItemStack(Items.STONE,c.get("count").getAsInt());if(c.has("components"))item.applyComponents(DataComponentPatch.CODEC.parse(OPS,c.get("components")).result().orElseThrow());
  JsonArray p=c.getAsJsonArray("position"),v=c.getAsJsonArray("velocity");ItemEntity e=new ItemEntity(w,p.get(0).getAsDouble(),p.get(1).getAsDouble(),p.get(2).getAsDouble(),item);e.setId(id);e.setDeltaMovement(v.get(0).getAsDouble(),v.get(1).getAsDouble(),v.get(2).getAsDouble());e.setOnGround(c.get("ground").getAsBoolean());
  CookingEffectEntitiesReference.set(e,"random",RandomSource.create(c.has("seed")?c.get("seed").getAsLong():17));CookingEffectEntitiesReference.set(e,"age",c.get("age").getAsInt());CookingEffectEntitiesReference.set(e,"pickupDelay",c.get("delay").getAsInt());CookingEffectEntitiesReference.set(e,"firstTick",c.get("first").getAsBoolean());e.tickCount=c.get("tick").getAsInt();e.setNoGravity(c.get("no_gravity").getAsBoolean());e.setSilent(c.get("silent").getAsBoolean());if(c.has("target"))CookingEffectEntitiesReference.set(e,"target",UUID.fromString(c.get("target").getAsString()));w.sections.getOrCreateSection(SectionPos.asLong(e.blockPosition())).add(e);return e;
 }
 static Object runtime(ItemEntity e)throws Exception{
  var out=new LinkedHashMap<String,Object>();for(String key:List.of("noPhysics","horizontalCollision","verticalCollision","verticalCollisionBelow","minorHorizontalCollision","boardingCooldown","wasTouchingWater","wasEyeInWater","lastKnownPosition","lastKnownSpeed","invulnerableTime")){Object v=CookingEffectEntitiesReference.get(e,key);out.put(key,v instanceof Vec3 p?CookingEffectEntitiesReference.vec(p):v);}
  out.put("position_old",CookingEffectEntitiesReference.vec(e.oldPosition()));out.put("noGravity",e.isNoGravity());out.put("silent",e.isSilent());out.put("water",CookingEffectEntitiesReference.dbl(e.getFluidHeight(net.minecraft.tags.FluidTags.WATER)));out.put("lava",CookingEffectEntitiesReference.dbl(e.getFluidHeight(net.minecraft.tags.FluidTags.LAVA)));out.put("fall_distance",CookingEffectEntitiesReference.dbl(e.fallDistance));out.put("support",e.mainSupportingBlockPos.map(p->List.of(Integer.toUnsignedLong(p.getX()),Integer.toUnsignedLong(p.getY()),Integer.toUnsignedLong(p.getZ()))).orElse(null));return out;
 }
 static Method declared(Class<?> k,String name,Class<?>...args)throws Exception{for(;k!=null;k=k.getSuperclass())try{return k.getDeclaredMethod(name,args);}catch(NoSuchMethodException ignored){}throw new NoSuchMethodException(name);}
 static Map<String,Object> cell(World w,int x,int y,int z)throws Exception{BlockPos p=new BlockPos(x,y,z);BlockState s=w.getBlockState(p);FluidState f=s.getFluidState();Block b=s.getBlock();List<AABB> boxes=s.getCollisionShape(w,p).move(x,y,z).toAabbs();var row=new LinkedHashMap<String,Object>();row.put("state",Integer.toUnsignedLong(Block.getId(s)));row.put("x",Integer.toUnsignedLong(x));row.put("y",Integer.toUnsignedLong(y));row.put("z",Integer.toUnsignedLong(z));row.put("water",f.is(net.minecraft.tags.FluidTags.WATER));row.put("lava",f.is(net.minecraft.tags.FluidTags.LAVA));row.put("height",Integer.toUnsignedLong(Float.floatToRawIntBits(f.getHeight(w,p))));row.put("camera_height",Integer.toUnsignedLong(Float.floatToRawIntBits(f.getHeightForCamera(w,p))));row.put("flow",CookingEffectEntitiesReference.vec(f.getFlow(w,p)));row.put("fluid",!f.isEmpty());row.put("full",s.isCollisionShapeFullBlock(w,p));row.put("friction",Integer.toUnsignedLong(Float.floatToRawIntBits(b.getFriction())));row.put("speed",Integer.toUnsignedLong(Float.floatToRawIntBits(b.getSpeedFactor())));row.put("restitution",Integer.toUnsignedLong(Float.floatToRawIntBits(b.getBounceRestitution())));row.put("suppresses",s.is(net.minecraft.tags.BlockTags.SUPPRESSES_BOUNCE));row.put("neutral_inside",(f.isEmpty()||f.is(net.minecraft.tags.FluidTags.WATER))&&declared(b.getClass(),"entityInside",BlockState.class,Level.class,BlockPos.class,Entity.class,net.minecraft.world.entity.InsideBlockEffectApplier.class,boolean.class).getDeclaringClass()==BlockBehaviour.class);row.put("neutral_step",b.getClass().getMethod("stepOn",Level.class,BlockPos.class,BlockState.class,Entity.class).getDeclaringClass()==Block.class&&declared(b.getClass(),"fallOn",Level.class,BlockState.class,BlockPos.class,Entity.class,double.class).getDeclaringClass()==Block.class);row.put("boxes",boxes.stream().map(v->List.of(CookingEffectEntitiesReference.dbl(v.minX),CookingEffectEntitiesReference.dbl(v.minY),CookingEffectEntitiesReference.dbl(v.minZ),CookingEffectEntitiesReference.dbl(v.maxX),CookingEffectEntitiesReference.dbl(v.maxY),CookingEffectEntitiesReference.dbl(v.maxZ))).toList());return row;}
 static Object cells(World w)throws Exception{List<Object> out=new ArrayList<>();for(int x=-3;x<=3;x++)for(int y=-3;y<=4;y++)for(int z=-3;z<=3;z++)out.add(cell(w,x,y,z));return out;}
 public static void main(String[] args)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();var lookup=VanillaRegistries.createWorldLookup();for(var pending:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup))pending.forEach((h,c)->h.bindComponents(c));OPS=RegistryOps.create(JsonOps.INSTANCE,lookup);CookingEffectEntitiesReference.OPS=OPS;ReferenceDirectMovementProbe.initialize();Field uf=Unsafe.class.getDeclaredField("theUnsafe");uf.setAccessible(true);U=(Unsafe)uf.get(null);
  JsonObject tags=JsonParser.parseString(Files.readString(Path.of(args[2]))).getAsJsonObject();Method bind=Holder.Reference.class.getDeclaredMethod("bindTags",Collection.class);bind.setAccessible(true);for(var holder:BuiltInRegistries.FLUID.listElements().toList()){String id=holder.key().identifier().toString();bind.invoke(holder,tags.getAsJsonArray("water").asList().contains(new JsonPrimitive(id))?List.of(net.minecraft.tags.FluidTags.WATER):tags.getAsJsonArray("lava").asList().contains(new JsonPrimitive(id))?List.of(net.minecraft.tags.FluidTags.LAVA):List.of());}
  for(var holder:BuiltInRegistries.BLOCK.listElements().toList()){String id=holder.key().identifier().toString();bind.invoke(holder,tags.getAsJsonArray("suppresses").asList().contains(new JsonPrimitive(id))?List.of(net.minecraft.tags.BlockTags.SUPPRESSES_BOUNCE):List.of());}
  List<Object> out=new ArrayList<>();for(var raw:JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonArray()){var c=raw.getAsJsonObject();World w=world(c);ItemEntity e=entity(w,c,71);var row=new LinkedHashMap<String,Object>();row.put("id",c.get("id").getAsString());row.put("before",CookingEffectEntitiesReference.record(e,0));row.put("input_patch",DataComponentPatch.CODEC.encodeStart(OPS,e.getItem().getComponentsPatch()).result().orElseThrow());row.put("level_before",CookingEffectEntitiesReference.random(w.getRandom()));row.put("sound_before",CookingEffectEntitiesReference.random((RandomSource)CookingEffectEntitiesReference.get(w,"soundSeedGenerator")));row.put("runtime_before",runtime(e));row.put("cells",cells(w));
   if(c.has("other")){ItemEntity other=entity(w,c.getAsJsonObject("other"),72);row.put("other_before",CookingEffectEntitiesReference.record(other,1));row.put("other_input_patch",DataComponentPatch.CODEC.encodeStart(OPS,other.getItem().getComponentsPatch()).result().orElseThrow());Method merge=ItemEntity.class.getDeclaredMethod("tryToMerge",ItemEntity.class);merge.setAccessible(true);merge.invoke(e,other);row.put("other_after",CookingEffectEntitiesReference.record(other,1));}
   else {if(c.get("common").getAsBoolean())e.commonTick();e.tick();}row.put("after",CookingEffectEntitiesReference.record(e,0));row.put("runtime_after",runtime(e));row.put("events",w.events);row.put("level_after",CookingEffectEntitiesReference.random(w.getRandom()));row.put("sound_after",CookingEffectEntitiesReference.random((RandomSource)CookingEffectEntitiesReference.get(w,"soundSeedGenerator")));out.add(row);
  }List<Object> profiles=new ArrayList<>();World empty=world(JsonParser.parseString("{\"blocks\":[]}").getAsJsonObject());for(var raw:JsonParser.parseString(Files.readString(Path.of(args[3]))).getAsJsonArray()){int id=raw.getAsInt();BlockState state=Block.stateById(id);empty.blocks.put(BlockPos.ZERO,state);var origin=cell(empty,0,0,0);origin=new LinkedHashMap<>(origin);origin.put("state",id);origin.remove("boxes");profiles.add(origin);}
  Files.writeString(Path.of(args[1]),JSON.toJson(Map.of("version",SharedConstants.getCurrentVersion().id(),"cases",out,"profiles",profiles)));
 }
}
'''
def source():
    parts=[BODY,Entities.SOURCE.replace("r instanceof LegacyRandomSource)","r instanceof LegacyRandomSource || r instanceof ThreadSafeLegacyRandomSource)"),Motion.SOURCE.replace('public class ReferenceMovementProbe','class ReferenceMovementProbe'),Motion.DIRECT_SOURCE]
    imports=set(re.findall(r'import [^;]+;', ''.join(parts)))
    return '\n'.join(sorted(imports))+ '\nimport net.minecraft.world.level.chunk.*;\n'+ '\n'.join(re.sub(r'import [^;]+;','',p) for p in parts)
def inputs():
    def c(id,**kw):
        r=dict(id=id,count=1,position=[0.5,2,0.5],velocity=[0,0,0],ground=False,age=0,delay=10,first=True,tick=0,no_gravity=False,silent=False,common=True,blocks=[]);r.update(kw);return r
    rows=[c('fall'),c('gravity-free',no_gravity=True),c('delay-infinite',delay=32767),c('age-infinite',age=-32768),c('negative-delay',delay=-1),c('despawn',age=5999),c('empty',count=0),c('floor',position=[.5,1.01,.5],velocity=[.1,-.2,.05],blocks=[dict(id='minecraft:stone',x=0,y=0,z=0)]),c('bottom-slab',position=[.5,.51,.5],velocity=[.1,-.2,.05],blocks=[dict(id='minecraft:oak_slab',x=0,y=0,z=0,slab='BOTTOM')]),c('escape-north',position=[.5,.3,.5],blocks=[dict(id='minecraft:stone',x=0,y=0,z=0)]),c('stationary-ground',position=[.5,1,.5],ground=True,no_gravity=True,tick=0,blocks=[dict(id='minecraft:stone',x=0,y=0,z=0)])]
    rows.extend([c('water-still',position=[.5,.2,.5],blocks=[dict(id='minecraft:water',x=0,y=0,z=0)]),c('water-silent',silent=True,position=[.5,.2,.5],velocity=[.1,-.4,.2],first=False,blocks=[dict(id='minecraft:water',x=0,y=0,z=0)]),c('water-splash',position=[.5,.2,.5],velocity=[.1,-.4,.2],first=False,blocks=[dict(id='minecraft:water',x=0,y=0,z=0)])])
    rows.extend([c('water-flow',position=[.75,.2,.5],blocks=[dict(id='minecraft:water',x=0,y=0,z=0),dict(id='minecraft:water',x=1,y=0,z=0,level=6)]),c('water-diagonal',position=[.75,.2,.75],blocks=[dict(id='minecraft:water',x=0,y=0,z=0),dict(id='minecraft:water',x=1,y=0,z=0,level=2),dict(id='minecraft:water',x=0,y=0,z=1,level=5)])])
    for a,b in [(4,4),(5,4),(20,40),(60,4),(63,2)]:rows.append(c(f'merge-{a}-{b}',count=a,other=c('other',count=b,age=9,delay=3)))
    rows.append(c('merge-max99-cap64',count=40,components={'minecraft:max_stack_size':99},other=c('other',count=40,components={'minecraft:max_stack_size':99})))
    rows.append(c('merge-target-refusal',count=4,target='11111111-1111-1111-1111-111111111111',other=c('other',count=4,target='22222222-2222-2222-2222-222222222222')))
    rows.append(c('merge-components-refusal',count=4,components={'minecraft:enchantment_glint_override':True},other=c('other',count=4)))
    return rows
def compact_observations(observed):
    """Deduplicate verbatim actual receiver rows; no cell is synthesized."""
    metadata=[];shapes=[];sets=[];meta_keys={};shape_keys={};set_keys={}
    def intern(value,rows,keys):
        key=json.dumps(value,sort_keys=True,separators=(',',':'))
        if key not in keys:keys[key]=len(rows);rows.append(value)
        return keys[key]
    for case in observed['cases']:
        cells=case.pop('cells');rows=[]
        for cell in cells:
            values={k:v for k,v in cell.items() if k not in ['x','y','z','boxes']}
            rows.append([cell['x'],cell['y'],cell['z'],intern(values,metadata,meta_keys),intern(cell['boxes'],shapes,shape_keys)])
        case['cell_set']=intern(rows,sets,set_keys)
    observed.update(cell_metadata=metadata,cell_shapes=shapes,cell_sets=sets)
    return observed
def main():
    WORK.mkdir(parents=True,exist_ok=True);(WORK/'ItemEntityTickReference.java').write_text(source());rows=inputs();(WORK/'input.json').write_text(json.dumps(rows));paths,pin=verified_client_classpath();tags={}
    for path in paths:
        with zipfile.ZipFile(path) as jar:
            for name in ["water","lava"]:
                entry="data/minecraft/tags/fluid/"+name+".json"
                if entry in jar.namelist():tags[name]=json.loads(jar.read(entry))["values"]
    assert set(tags)=={"water","lava"}
    with zipfile.ZipFile(paths[0]) as jar:
        def block_tag(name):
            values=json.loads(jar.read('data/minecraft/tags/block/'+name.split(':')[-1]+'.json'))['values'];out=[]
            for value in values:
                if isinstance(value,dict):value=value['id']
                out.extend(block_tag(value[1:]) if value.startswith('#') else [value])
            return out
        tags['suppresses']=block_tag('minecraft:suppresses_bounce')
    profiles=[0,1,10,15]+[int(line.split('\t')[0]) for line in (ROOT/'generated/reference_slab_collision.tsv').read_text().splitlines()[2:] if line.split('\t')[2]=='0']
    assert len(profiles)==307;(WORK/'profile-states.json').write_text(json.dumps(profiles));(WORK/"tags.json").write_text(json.dumps(tags));started=time.monotonic()
    p=subprocess.run([str(JAVA),'-Xmx512m','--source','25','--class-path',os.pathsep.join(map(str,paths)),str(WORK/'ItemEntityTickReference.java'),str(WORK/'input.json'),str(WORK/'output.json'),str(WORK/'tags.json'),str(WORK/'profile-states.json')],cwd=WORK,capture_output=True,text=True,timeout=90);(WORK/'java.stdout').write_text(p.stdout);(WORK/'java.stderr').write_text(p.stderr);assert p.returncode==0,p.stderr
    observed=json.loads((WORK/'output.json').read_text());assert observed['version']=='26.3';profile_data={'pin':'26.3','registry_identity':'4f75fa335a12e34cf74be71ff6a0ee530b13233212423f5463bb26a2fe4f3cfc','profiles':observed.pop('profiles')};(ROOT/'reference/item_entity_tick_profiles.json').write_text(json.dumps(profile_data,separators=(',',':'))+'\n');canonical=hashlib.sha256(json.dumps(observed,sort_keys=True,separators=(',',':')).encode()).hexdigest();observed=compact_observations(observed);result={'canonical_observations_sha256':canonical,'java_source_sha256':hashlib.sha256((WORK/'ItemEntityTickReference.java').read_bytes()).hexdigest(),'pin':'26.3','inputs':rows,'observations':observed,'provenance':pin,'fluid_tags':tags,'command':'python3 tools/reference_item_entity_tick.py','seconds':round(time.monotonic()-started,3),'source_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'receiver':'Actual ItemEntity.tick, commonTick and private tryToMerge on a ServerLevel subclass. Actual initialized Level fields, chunks, states, BlockCollisions and EntitySectionStorage. Only unrelated I/O sinks are overridden. No host motion/timer/merge implementation.'};(ROOT/'reference/item_entity_tick.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'cases':len(rows),'seconds':result['seconds']}))
if __name__=='__main__':main()
