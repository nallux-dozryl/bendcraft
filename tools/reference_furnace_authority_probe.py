#!/usr/bin/env python3
"""Pinned furnace receiver and resource observations; no Python tick logic."""
from __future__ import annotations
import copy,json,subprocess,time,zipfile
import reference_crafting_recipe_probe as P
from reference_inventory import ROOT,JAVA,canonical,fingerprint,write_json
from reference_player_inventory_probe import verified_classpath

CACHE=ROOT/'build/furnace-authority-reference'
OUTPUT=ROOT/'reference/furnace_authority.json'
SOURCE=r'''import java.nio.file.*;import java.util.*;import java.util.stream.*;import java.lang.reflect.*;
import com.google.gson.*;import com.mojang.serialization.*;
import net.minecraft.SharedConstants;import net.minecraft.server.Bootstrap;import net.minecraft.server.level.ServerLevel;
import net.minecraft.core.*;import net.minecraft.core.registries.*;import net.minecraft.core.component.*;
import net.minecraft.data.registries.VanillaRegistries;import net.minecraft.resources.*;
import net.minecraft.world.item.*;import net.minecraft.world.item.component.*;import net.minecraft.world.item.crafting.*;
import net.minecraft.world.level.*;import net.minecraft.world.level.block.*;import net.minecraft.world.level.block.entity.*;
import net.minecraft.world.level.block.state.*;import net.minecraft.world.level.storage.loot.*;
import net.minecraft.world.level.storage.loot.parameters.*;import net.minecraft.world.level.storage.loot.predicates.*;import net.minecraft.world.level.storage.loot.providers.number.ints.*;
import net.minecraft.world.level.storage.loot.providers.number.floats.*;import net.minecraft.world.phys.Vec3;
import net.minecraft.util.RandomSource;import net.minecraft.network.chat.Component;
import net.minecraft.world.inventory.*;import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.entity.*;import net.minecraft.world.entity.item.ItemEntity;import net.minecraft.world.flag.*;
import it.unimi.dsi.fastutil.objects.Reference2IntOpenHashMap;
class FurnaceAuthorityProbe {
 static RegistryOps<JsonElement> OPS;static HolderLookup.Provider LOOKUP;static final Gson JSON=new GsonBuilder().serializeNulls().create();
 static final sun.misc.Unsafe UNSAFE;static{try{var f=sun.misc.Unsafe.class.getDeclaredField("theUnsafe");f.setAccessible(true);UNSAFE=(sun.misc.Unsafe)f.get(null);}catch(Exception e){throw new RuntimeException(e);}}
 static class World extends ServerLevel {
  RecipeManager manager;BlockState state;int dirty,updates,nextId;List<Integer> xp;List<Map<String,Object>> drops;
  World(){super(null,null,null,null,null,null,false,0,List.of(),false);}
  public int getNextEntityId(){return ++nextId;}
  public <T extends Entity> List<T> getEntities(net.minecraft.world.level.entity.EntityTypeTest<Entity,T> test,net.minecraft.world.phys.AABB box,java.util.function.Predicate<? super T> predicate){return List.of();}
  public boolean noCollision(net.minecraft.world.phys.AABB box){return true;}
  public RecipeManager recipeAccess(){return manager;}
  public BlockState getBlockState(BlockPos pos){return state;}
  public boolean setBlock(BlockPos pos,BlockState next,int flags,int recursion){state=next;updates++;return true;}
  public void blockEntityChanged(BlockPos pos){dirty++;}
  public void updateNeighbourForOutputSignal(BlockPos pos,Block block){}
  public boolean addFreshEntity(Entity entity){if(entity instanceof ItemEntity item)drops.add(stack(item.getItem()));if(entity instanceof ExperienceOrb orb)xp.add(orb.getValue());return true;}
  public FeatureFlagSet enabledFeatures(){return FeatureFlags.VANILLA_SET;}
 }
 static class Furnace extends AbstractFurnaceBlockEntity {
  LootContext context;
  Furnace(BlockState state,RecipeType<? extends AbstractCookingRecipe> type){super(state.is(Blocks.BLAST_FURNACE)?BlockEntityTypes.BLAST_FURNACE:state.is(Blocks.SMOKER)?BlockEntityTypes.SMOKER:BlockEntityTypes.FURNACE,BlockPos.ZERO,state,type);}
  protected Component getDefaultName(){return Component.literal("reference fixture");}
  protected AbstractContainerMenu createMenu(int id,Inventory inventory){return null;}
  protected LootContext getLootContext(ServerLevel world){return context;}
  int duration(ItemStack stack,World world){return getBurnDuration(world,stack);}
 }
 static long bits(float value){return Integer.toUnsignedLong(Float.floatToRawIntBits(value));}
 static Map<String,Object> stack(ItemStack value){var r=new TreeMap<String,Object>();r.put("empty",value.isEmpty());r.put("id",BuiltInRegistries.ITEM.getKey(value.getItem()).toString());r.put("count",value.getCount());r.put("components",DataComponentMap.CODEC.encodeStart(OPS,value.getComponents()).result().orElseThrow());return r;}
 static ItemStack item(JsonElement raw){if(raw==null||raw.isJsonNull())return ItemStack.EMPTY;var r=raw.getAsJsonObject();var result=new ItemStack(BuiltInRegistries.ITEM.getValue(Identifier.parse(r.get("id").getAsString())),r.get("count").getAsInt());if(r.has("components"))result.applyComponents(DataComponentPatch.CODEC.parse(OPS,r.get("components")).result().orElseThrow());return result;}
 static Field field(String name)throws Exception{var f=AbstractFurnaceBlockEntity.class.getDeclaredField(name);f.setAccessible(true);return f;}
 static LootContext context(World world,Furnace furnace)throws Exception{var params=new LootParams.Builder(world).withParameter(LootContextParams.BLOCK_STATE,world.state).withParameter(LootContextParams.BLOCK_ENTITY,furnace).withParameter(LootContextParams.ORIGIN,Vec3.ZERO).withParameter(LootContextParams.CONTAINER,furnace).create(LootContextParamSets.CONTAINER_PROCESS);var ctor=LootContext.class.getDeclaredConstructor(LootParams.class,RandomSource.class,HolderGetter.Provider.class);ctor.setAccessible(true);return ctor.newInstance(params,RandomSource.create(17),LOOKUP);}
 static void objectField(Object owner,Class<?> type,String name,Object value)throws Exception{var f=type.getDeclaredField(name);UNSAFE.putObject(owner,UNSAFE.objectFieldOffset(f),value);}
 static World world(RecipeManager manager,BlockState state)throws Exception{var w=(World)UNSAFE.allocateInstance(World.class);w.manager=manager;w.state=state;w.drops=new ArrayList<>();w.xp=new ArrayList<>();objectField(w,Level.class,"random",RandomSource.create(17));return w;}
 static Object snapshot(Furnace furnace)throws Exception{var r=new TreeMap<String,Object>();for(var name:List.of("litTimeRemaining","litTotalTime","cookingTimer","cookingTotalTime"))r.put(name,Integer.toUnsignedLong(field(name).getInt(furnace)));r.put("speed_bits",bits(field("speedMultiplier").getFloat(furnace)));r.put("slots",List.of(stack(furnace.getItem(0)),stack(furnace.getItem(1)),stack(furnace.getItem(2))));var uses=(Reference2IntOpenHashMap<ResourceKey<Recipe<?>>>)field("recipesUsed").get(furnace);var result=new TreeMap<String,Long>();for(var pair:uses.reference2IntEntrySet())result.put(pair.getKey().identifier().toString(),Integer.toUnsignedLong(pair.getIntValue()));r.put("uses",result);var quick=field("quickCheck").get(furnace);var last=quick.getClass().getDeclaredField("lastRecipe");last.setAccessible(true);Object key=last.get(quick);r.put("cached",key==null?null:((ResourceKey<?>)key).identifier().toString());return r;}
 static void providers(JsonObject resources)throws Exception{var ints=new MappedRegistry<ContextIntProvider>(Registries.CONTEXT_INT_PROVIDER,Lifecycle.stable());var floats=new MappedRegistry<ContextFloatProvider>(Registries.CONTEXT_FLOAT_PROVIDER,Lifecycle.stable());var predicates=new MappedRegistry<LootItemCondition>(Registries.PREDICATE,Lifecycle.stable());for(var e:resources.getAsJsonArray("ints"))ints.createRegistrationLookup().get(ResourceKey.create(Registries.CONTEXT_INT_PROVIDER,Identifier.parse(e.getAsJsonObject().get("id").getAsString())));for(var e:resources.getAsJsonArray("floats"))floats.createRegistrationLookup().get(ResourceKey.create(Registries.CONTEXT_FLOAT_PROVIDER,Identifier.parse(e.getAsJsonObject().get("id").getAsString())));for(var e:resources.getAsJsonArray("predicates"))predicates.createRegistrationLookup().get(ResourceKey.create(Registries.PREDICATE,Identifier.parse(e.getAsJsonObject().get("id").getAsString())));LOOKUP=HolderLookup.Provider.create(Stream.concat(LOOKUP.listRegistries(),Stream.<HolderLookup.RegistryLookup<?>>of(ints,floats,predicates)));OPS=RegistryOps.create(JsonOps.INSTANCE,LOOKUP);for(var e:resources.getAsJsonArray("predicates")){var r=e.getAsJsonObject();predicates.register(ResourceKey.create(Registries.PREDICATE,Identifier.parse(r.get("id").getAsString())),LootItemCondition.DIRECT_CODEC.parse(OPS,r.get("source")).result().orElseThrow(),RegistrationInfo.BUILT_IN);}for(var e:resources.getAsJsonArray("ints")){var r=e.getAsJsonObject();ints.register(ResourceKey.create(Registries.CONTEXT_INT_PROVIDER,Identifier.parse(r.get("id").getAsString())),ContextIntProviders.DIRECT_CODEC.parse(OPS,r.get("source")).result().orElseThrow(),RegistrationInfo.BUILT_IN);}for(var e:resources.getAsJsonArray("floats")){var r=e.getAsJsonObject();floats.register(ResourceKey.create(Registries.CONTEXT_FLOAT_PROVIDER,Identifier.parse(r.get("id").getAsString())),ContextFloatProviders.DIRECT_CODEC.parse(OPS,r.get("source")).result().orElseThrow(),RegistrationInfo.BUILT_IN);}ints.freeze();floats.freeze();predicates.freeze();}
 static RecipeManager recipes(JsonArray sources)throws Exception{var registry=new MappedRegistry<Recipe<?>>(Registries.RECIPE,Lifecycle.stable());for(var e:sources){var row=e.getAsJsonObject();registry.register(ResourceKey.create(Registries.RECIPE,Identifier.parse(row.get("id").getAsString())),Recipe.DIRECT_CODEC.parse(OPS,row.get("source")).result().orElseThrow(),RegistrationInfo.BUILT_IN);}registry.freeze();return new RecipeManager(HolderLookup.Provider.create(Stream.of(registry)));}
 public static void main(String[] args)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();Thread.currentThread().setUncaughtExceptionHandler((thread,error)->error.printStackTrace(new java.io.PrintStream(new java.io.FileOutputStream(java.io.FileDescriptor.err))));LOOKUP=VanillaRegistries.createWorldLookup();for(var pending:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(LOOKUP))pending.forEach((holder,components)->holder.bindComponents(components));OPS=RegistryOps.create(JsonOps.INSTANCE,LOOKUP);
  var input=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonObject();providers(input.getAsJsonObject("providers"));var manager=recipes(input.getAsJsonArray("recipes"));
  List<Object> fuels=new ArrayList<>(),defaults=new ArrayList<>();for(Item value:BuiltInRegistries.ITEM){String id=BuiltInRegistries.ITEM.getKey(value).toString();var fuel=value.components().get(DataComponents.COOKING_FUEL);var out=new TreeMap<String,Object>();out.put("id",id);if(fuel!=null)out.put("fuel",CookingFuel.CODEC.encodeStart(OPS,fuel).result().orElseThrow());fuels.add(out);var encoded=DataComponentMap.CODEC.encodeStart(OPS,value.components());if(encoded.result().isPresent())defaults.add(Map.of("id",id,"components",encoded.result().get()));else throw new IllegalStateException(id+": "+encoded.error().orElseThrow().message());}
  Method speed=AbstractFurnaceBlockEntity.class.getDeclaredMethod("getSpeedMultiplier",ServerLevel.class,ItemStack.class);speed.setAccessible(true);List<Object> values=new ArrayList<>();for(String block:List.of("minecraft:furnace","minecraft:blast_furnace","minecraft:smoker")){var state=BuiltInRegistries.BLOCK.getValue(Identifier.parse(block)).defaultBlockState();var w=world(manager,state);var f=new Furnace(state,RecipeType.SMELTING);f.context=context(w,f);for(var raw:fuels){var row=(Map<String,Object>)raw;if(!row.containsKey("fuel"))continue;var s=new ItemStack(BuiltInRegistries.ITEM.getValue(Identifier.parse((String)row.get("id"))));values.add(Map.of("id",row.get("id"),"block",block,"time",Integer.toUnsignedLong(f.duration(s,w)),"speed_bits",bits((float)speed.invoke(f,w,s))));}}
  List<Object> cases=new ArrayList<>();for(var e:input.getAsJsonArray("cases")){var row=e.getAsJsonObject();String kind=row.get("kind").getAsString();var type=switch(kind){case "minecraft:smelting"->RecipeType.SMELTING;case "minecraft:blasting"->RecipeType.BLASTING;case "minecraft:smoking"->RecipeType.SMOKING;default->throw new IllegalArgumentException();};var block=switch(kind){case "minecraft:smelting"->Blocks.FURNACE;case "minecraft:blasting"->Blocks.BLAST_FURNACE;default->Blocks.SMOKER;};var w=world(manager,block.defaultBlockState());var f=new Furnace(w.state,type);f.setLevel(w);f.context=context(w,f);var slots=(NonNullList<ItemStack>)field("items").get(f);for(int i=0;i<3;i++)slots.set(i,item(row.getAsJsonArray("slots").get(i)));for(var name:List.of("litTimeRemaining","litTotalTime","cookingTimer","cookingTotalTime"))field(name).setInt(f,row.get(name).getAsInt());field("speedMultiplier").setFloat(f,Float.intBitsToFloat((int)row.get("speed_bits").getAsLong()));var quick=field("quickCheck").get(f);var last=quick.getClass().getDeclaredField("lastRecipe");last.setAccessible(true);if(row.has("cached")&&!row.get("cached").isJsonNull())last.set(quick,ResourceKey.create(Registries.RECIPE,Identifier.parse(row.get("cached").getAsString())));if(row.has("uses")){var uses=(Reference2IntOpenHashMap<ResourceKey<Recipe<?>>>)field("recipesUsed").get(f);for(var pair:row.getAsJsonObject("uses").entrySet())uses.put(ResourceKey.create(Registries.RECIPE,Identifier.parse(pair.getKey())),pair.getValue().getAsInt());}List<Object> steps=new ArrayList<>();for(var op:row.getAsJsonArray("ops")){w.dirty=w.updates=0;w.drops.clear();var operation=op.getAsJsonObject();if(operation.get("type").getAsString().equals("put"))f.setItem(operation.get("index").getAsInt(),item(operation.get("slot")));else AbstractFurnaceBlockEntity.serverTick(w,BlockPos.ZERO,w.state,f);var r=new TreeMap<String,Object>();r.put("after",snapshot(f));r.put("dirty",w.dirty>0);r.put("lit_change",w.updates>0?w.state.getValue(AbstractFurnaceBlock.LIT):null);r.put("drops",new ArrayList<>(w.drops));steps.add(r);}cases.add(Map.of("id",row.get("id").getAsString(),"steps",steps));}
  List<Object> xpCases=new ArrayList<>();for(var element:input.getAsJsonArray("xp_cases")){var row=element.getAsJsonObject();var current=recipes(row.getAsJsonArray("recipes"));var w=world(current,Blocks.FURNACE.defaultBlockState());var f=new Furnace(w.state,RecipeType.SMELTING);var useMap=(Reference2IntOpenHashMap<ResourceKey<Recipe<?>>>)field("recipesUsed").get(f);for(var pair:row.getAsJsonObject("uses").entrySet())useMap.put(ResourceKey.create(Registries.RECIPE,Identifier.parse(pair.getKey())),pair.getValue().getAsInt());var record=new TreeMap<String,Object>();record.put("id",row.get("id").getAsString());try{var awards=f.getRecipesToAwardAndPopExperience(w,Vec3.ZERO);record.put("awards",awards.stream().map(holder->holder.id().identifier().toString()).toList());record.put("requests",awards.stream().map(holder->Map.of("id",holder.id().identifier().toString(),"uses",Integer.toUnsignedLong(useMap.getInt(holder.id())),"rate_bits",bits(((AbstractCookingRecipe)holder.value()).experience()))).toList());record.put("orbs",new ArrayList<>(w.xp));record.put("status","accepted");w.xp.clear();f.getRecipesToAwardAndPopExperience(w,Vec3.ZERO);record.put("second_orbs",new ArrayList<>(w.xp));}catch(Exception error){record.put("status","error");record.put("exception",error.getClass().getName());record.put("message",String.valueOf(error.getMessage()));if(!(error instanceof ClassCastException))error.printStackTrace(new java.io.PrintStream(new java.io.FileOutputStream(java.io.FileDescriptor.err)));}record.put("after",snapshot(f));xpCases.add(record);}
  Files.writeString(Path.of(args[1]),JSON.toJson(Map.of("items",fuels,"defaults",defaults,"values",values,"cases",cases,"xp_cases",xpCases)));
 }
}'''

def slot(id,count=1,components=None):
    value={'id':id,'count':count}
    if components is not None:value['components']=components
    return value

def inputs():
    source={'type':'minecraft:smelting','ingredient':'minecraft:oak_planks','result':{'id':'minecraft:stone'},'cookingtime':200,'experience':0.35}
    recipes=[{'id':'bendcraft:first','source':source},{'id':'bendcraft:second','source':{**source,'result':{'id':'minecraft:iron_ingot'}}},{'id':'bendcraft:blast','source':{**source,'type':'minecraft:blasting'}},{'id':'bendcraft:smoke','source':{**source,'type':'minecraft:smoking'}},{'id':'bendcraft:sponge','source':{**source,'ingredient':'minecraft:wet_sponge','result':{'id':'minecraft:sponge'}}}]
    cases=[]
    def add(id,**changes):
        row={'id':id,'kind':'minecraft:smelting','slots':[slot('minecraft:oak_planks',2),slot('minecraft:coal',2),None],'litTimeRemaining':0,'litTotalTime':0,'cookingTimer':0,'cookingTotalTime':200,'speed_bits':1065353216,'cached':None,'uses':{},'ops':[{'type':'tick'}]};row.update(changes);cases.append(row);return row
    add('ignite');add('lit_progress',litTimeRemaining=10,litTotalTime=10,cookingTimer=40)
    add('complete',litTimeRemaining=10,cookingTimer=199)
    add('cached_collision',litTimeRemaining=10,cookingTimer=199,cached='bendcraft:second')
    add('cached_miss',litTimeRemaining=10,cookingTimer=30,cached='bendcraft:second',slots=[slot('minecraft:diamond'),slot('minecraft:coal'),None])
    add('blocked',litTimeRemaining=10,cookingTimer=199,slots=[slot('minecraft:oak_planks'),slot('minecraft:coal'),slot('minecraft:stone',64)])
    add('empty_input_lit',litTimeRemaining=10,cookingTimer=30,slots=[None,slot('minecraft:coal'),None])
    add('cooldown',cookingTimer=30,slots=[slot('minecraft:oak_planks'),None,None])
    add('cooldown_one',cookingTimer=1,slots=[None,None,None]);add('cooldown_negative_total',cookingTimer=3,cookingTotalTime=-1,slots=[None,None,None])
    add('expires',litTimeRemaining=1,cookingTimer=50,slots=[slot('minecraft:oak_planks'),None,None])
    add('expires_reignite',litTimeRemaining=1,cookingTimer=50)
    add('zero_total',cookingTotalTime=0)
    add('unfuelled',slots=[slot('minecraft:oak_planks'),slot('minecraft:diamond'),None],cookingTimer=60)
    add('blasting_resize',kind='minecraft:blasting',cookingTimer=51)
    add('smoking_resize',kind='minecraft:smoking',cookingTimer=199)
    add('blasting_odd_kelp',kind='minecraft:blasting',slots=[slot('minecraft:oak_planks'),slot('minecraft:dried_kelp_block'),None])
    add('sponge_lava',slots=[slot('minecraft:wet_sponge'),slot('minecraft:lava_bucket'),None],cookingTimer=199)
    add('lava_extra_remainder',slots=[slot('minecraft:oak_planks'),slot('minecraft:lava_bucket',2,{'minecraft:max_stack_size':64}),None])
    add('use_overflow',litTimeRemaining=10,cookingTimer=199,uses={'bendcraft:first':2147483647})
    add('removed_fuel_component',slots=[slot('minecraft:oak_planks'),slot('minecraft:coal',2,{'!minecraft:cooking_fuel':{}}),None],cookingTimer=30)
    add('preserved_fuel_component',slots=[slot('minecraft:oak_planks'),slot('minecraft:coal',2,{'minecraft:enchantment_glint_override':True}),None])
    add('negative_lit',litTimeRemaining=-1,cookingTimer=50,slots=[None,None,None])
    add('count_put_preserves',litTimeRemaining=10,cookingTimer=70,ops=[{'type':'put','index':0,'slot':slot('minecraft:oak_planks',3)}])
    add('different_put_resets',litTimeRemaining=10,cookingTimer=70,ops=[{'type':'put','index':0,'slot':slot('minecraft:wet_sponge')},{'type':'tick'}])
    add('empty_put_resets',litTimeRemaining=10,cookingTimer=70,ops=[{'type':'put','index':0,'slot':None}])
    add('oversize_put_clamps',ops=[{'type':'put','index':0,'slot':slot('minecraft:oak_planks',999)}])
    changed=copy.deepcopy(recipes);changed[0]['source']['experience']=1.0
    stonecut=[{'id':'bendcraft:first','source':{'type':'minecraft:stonecutting','ingredient':'minecraft:stone','result':{'id':'minecraft:stone_slab'}}}]
    xp_cases=[{'id':'current_rate','recipes':changed,'uses':{'bendcraft:first':3}}, {'id':'deleted_skipped','recipes':[],'uses':{'bendcraft:first':3}}, {'id':'current_zero','recipes':[{**recipes[0],'source':{**source,'experience':0}}],'uses':{'bendcraft:first':3}}, {'id':'noncooking_cast_failure','recipes':stonecut,'uses':{'bendcraft:first':3}}, {'id':'negative_uses','recipes':changed,'uses':{'bendcraft:first':-1}}]
    return {'recipes':recipes,'cases':cases,'xp_cases':xp_cases}

def resources():
    result={'ints':[],'floats':[],'predicates':[],'tags':[]};pins={}
    with zipfile.ZipFile(P.CLIENT) as jar:
        for name in sorted(jar.namelist()):
            target=None;prefix=None
            for folder,key in [('context_int_provider','ints'),('context_float_provider','floats'),('predicate','predicates')]:
                candidate=f'data/minecraft/{folder}/'
                if name.startswith(candidate+'cooking/') and name.endswith('.json'):target=key;prefix=candidate
            if name=='data/minecraft/predicate/block/fast_cooking.json':target='predicates';prefix='data/minecraft/predicate/'
            if target:
                raw=jar.read(name);result[target].append({'id':'minecraft:'+name[len(prefix):-5],'source':json.loads(raw)});pins[name]=P.sha(raw)
    return result,pins

def extract():
    CACHE.mkdir(parents=True,exist_ok=True);data=inputs();provider_data,resource_pins=resources();data["providers"]=provider_data;write_json(CACHE/'input.json',data)
    cp,provenance=verified_classpath();java=CACHE/'FurnaceAuthorityProbe.java';java.write_text(SOURCE);start=time.monotonic()
    run=subprocess.run([str(JAVA),'-Xmx768m','-Djava.awt.headless=true','--class-path',':'.join(map(str,cp)),str(java),str(CACHE/'input.json'),str(CACHE/'output.json')],capture_output=True,text=True,timeout=90,cwd=CACHE)
    (CACHE/'process.log').write_text(run.stdout+run.stderr)
    if run.returncode:raise AssertionError((run.stdout+run.stderr)[-7000:])
    observed=json.loads((CACHE/'output.json').read_text());assert all(r['status']=='accepted' or r['id']=='noncooking_cast_failure' and r['exception']=='java.lang.ClassCastException' for r in observed['xp_cases']),observed['xp_cases'];catalog,pins=resources();catalog.update(items=observed['items'],defaults=observed['defaults']);write_json(CACHE/'fuel-catalog.json',catalog)
    observed.update(pin='26.3',schema_version=1,source_sha256=P.sha(SOURCE.encode()),inputs_sha256=P.sha(canonical(data)),provenance=provenance,resources=pins,seconds=round(time.monotonic()-start,6),receiver_scope={'actual':'AbstractFurnaceBlockEntity.serverTick/setItem/getBurnDuration/getSpeedMultiplier/getRecipesToAwardAndPopExperience, real cached RecipeManager, provider resolution and predicate evaluation','fixture':'Unsafe-allocated ServerLevel overrides world I/O and supplies empty XP collision/entity queries. Normal ItemEntity/ExperienceOrb constructors run. Actual LootContext uses initialized VanillaRegistries plus source-decoded frozen context-provider/predicate registries. This is reference-only.'})
    write_json(OUTPUT,observed);return observed
if __name__=='__main__':
    result=extract();print(json.dumps({'fuels':sum('fuel' in r for r in result['items']),'fuel_receivers':len(result['values']),'cases':len(result['cases']),'seconds':result['seconds']}))
