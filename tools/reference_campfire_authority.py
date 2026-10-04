#!/usr/bin/env python3
"""Pinned actual CampfireBlockEntity receiver, with declared world I/O capture."""
from __future__ import annotations
import copy,hashlib,json,os,subprocess,time
from pathlib import Path
from reference_model_probe import verified_client_classpath,JAVA
from reference_inventory import ROOT
WORK=ROOT/'build/campfire-authority-reference'
SOURCE=r'''import java.util.*;import java.util.stream.*;import java.nio.file.*;import java.lang.reflect.*;
import com.google.gson.*;import com.mojang.serialization.*;import sun.misc.Unsafe;
import net.minecraft.SharedConstants;import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;import net.minecraft.core.registries.*;import net.minecraft.core.component.*;
import net.minecraft.data.registries.VanillaRegistries;import net.minecraft.resources.*;import net.minecraft.tags.*;
import net.minecraft.server.level.*;import net.minecraft.world.level.*;import net.minecraft.world.level.block.*;
import net.minecraft.world.level.block.entity.*;import net.minecraft.world.level.block.state.*;
import net.minecraft.world.level.gameevent.*;import net.minecraft.world.item.*;import net.minecraft.world.item.crafting.*;
import net.minecraft.world.entity.*;import net.minecraft.world.entity.item.*;import net.minecraft.world.flag.*;
import net.minecraft.world.phys.*;import net.minecraft.util.RandomSource;
class CampfireAuthorityReference {
 static Gson JSON=new GsonBuilder().serializeNulls().create();static RegistryOps<JsonElement> OPS;
 static Unsafe UNSAFE;static Map<String,Recipe<?>> RECIPES=new LinkedHashMap<>();
 static class World extends ServerLevel {
  RecipeManager manager;FeatureFlagSet flags;RandomSource rng;List<ItemStack> drops;
  int dirty,updates,changes,xp,next;
  private World(){super(null,null,null,null,Level.OVERWORLD,null,false,0,List.of(),false);}
  public RecipeManager recipeAccess(){return manager;}
  public FeatureFlagSet enabledFeatures(){return flags;}
  public RandomSource getRandom(){return rng;}
  public int getNextEntityId(){return ++next;}
  public boolean isClientSide(){return false;}
  public void blockEntityChanged(BlockPos p){dirty++;}
  public void updateNeighbourForOutputSignal(BlockPos p,Block b){}
  public void sendBlockUpdated(BlockPos p,BlockState a,BlockState b,int flags){updates++;}
  public void gameEvent(Holder<GameEvent> e,Vec3 p,GameEvent.Context c){changes++;}
  public boolean addFreshEntity(Entity e){if(e instanceof ItemEntity item)drops.add(item.getItem().copy());else if(e instanceof ExperienceOrb)xp++;else throw new AssertionError(e);return true;}
  void reset(){dirty=updates=changes=xp=0;drops.clear();}
 }
 static long word(int i){return Integer.toUnsignedLong(i);}
 static int integer(JsonElement v){return (int)v.getAsLong();}
 static ItemStack item(JsonElement raw){if(raw.isJsonNull())return ItemStack.EMPTY;var v=raw.getAsJsonObject();ItemStack result=new ItemStack(BuiltInRegistries.ITEM.getValue(Identifier.parse(v.get("id").getAsString())),1);if(v.has("components"))result.applyComponents(DataComponentPatch.CODEC.parse(OPS,v.get("components")).result().orElseThrow());result.setCount(integer(v.get("count")));return result;}
 static Object stack(ItemStack value){if(value.isEmpty())return null;var out=new TreeMap<String,Object>();out.put("id",BuiltInRegistries.ITEM.getKey(value.getItem()).toString());out.put("count",value.getCount());out.put("components",DataComponentMap.CODEC.encodeStart(OPS,value.getComponents()).result().orElseThrow());return out;}
 static RecipeManager manager(JsonArray ids){var registry=new MappedRegistry<Recipe<?>>(Registries.RECIPE,Lifecycle.stable());for(var id:ids){String s=id.getAsString();registry.register(ResourceKey.create(Registries.RECIPE,Identifier.parse(s)),RECIPES.get(s),RegistrationInfo.BUILT_IN);}registry.freeze();return new RecipeManager(HolderLookup.Provider.create(Stream.<HolderLookup.RegistryLookup<?>>of(registry)));}
 static int[] times(CampfireBlockEntity e,String name)throws Exception{Field f=CampfireBlockEntity.class.getDeclaredField(name);f.setAccessible(true);return (int[])f.get(e);}
 static Object cache(RecipeManager.CachedCheck<?,?> check)throws Exception{Field f=check.getClass().getDeclaredField("lastRecipe");f.setAccessible(true);var value=(ResourceKey<?>)f.get(check);return value==null?null:value.identifier().toString();}
 static Object snapshot(CampfireBlockEntity e,RecipeManager.CachedCheck<?,?> check)throws Exception{
  var out=new TreeMap<String,Object>();out.put("items",e.getItems().stream().map(CampfireAuthorityReference::stack).toList());out.put("progress",Arrays.stream(times(e,"cookingProgress")).mapToLong(CampfireAuthorityReference::word).toArray());out.put("total",Arrays.stream(times(e,"cookingTime")).mapToLong(CampfireAuthorityReference::word).toArray());out.put("cache",cache(check));return out;}
 public static void main(String[] args){try{run(args);}catch(Throwable t){t.printStackTrace(new java.io.PrintStream(new java.io.FileOutputStream(java.io.FileDescriptor.err)));System.exit(1);}}
 public static void run(String[] args)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();var lookup=VanillaRegistries.createWorldLookup();for(var pending:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup))pending.forEach((holder,components)->holder.bindComponents(components));OPS=RegistryOps.create(JsonOps.INSTANCE,lookup);
  Field u=Unsafe.class.getDeclaredField("theUnsafe");u.setAccessible(true);UNSAFE=(Unsafe)u.get(null);
  var input=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonObject();var book=input.getAsJsonObject("catalog");
  Map<TagKey<Item>,List<Holder<Item>>> tags=new LinkedHashMap<>();for(var raw:book.getAsJsonArray("tags")){var tag=raw.getAsJsonObject();List<Holder<Item>> members=new ArrayList<>();for(var id:tag.getAsJsonArray("items"))members.add(BuiltInRegistries.ITEM.get(Identifier.parse(id.getAsString())).orElseThrow());tags.put(TagKey.create(Registries.ITEM,Identifier.parse(tag.get("id").getAsString())),members);}BuiltInRegistries.ITEM.prepareTagReload(new TagLoader.LoadResult<Item>(Registries.ITEM,tags)).apply();
  for(var raw:book.getAsJsonArray("recipes")){var r=raw.getAsJsonObject();RECIPES.put(r.get("id").getAsString(),Recipe.DIRECT_CODEC.parse(OPS,r.get("source")).result().orElseThrow());}
  List<Object> features=new ArrayList<>();for(Item i:BuiltInRegistries.ITEM)features.add(Map.of("id",BuiltInRegistries.ITEM.getKey(i).toString(),"enabled",i.isEnabled(FeatureFlags.VANILLA_SET)));
  List<Object> cases=new ArrayList<>();for(var raw:input.getAsJsonArray("cases")){
   var scene=raw.getAsJsonObject();var world=(World)UNSAFE.allocateInstance(World.class);world.flags=FeatureFlags.VANILLA_SET;world.rng=RandomSource.create(123);world.drops=new ArrayList<>();Field random=Level.class.getDeclaredField("random");random.setAccessible(true);random.set(world,world.rng);world.manager=manager(scene.getAsJsonArray("recipes"));
   Block block=scene.get("soul").getAsBoolean()?Blocks.SOUL_CAMPFIRE:Blocks.CAMPFIRE;
   BlockState state=block.defaultBlockState().setValue(CampfireBlock.LIT,scene.get("lit").getAsBoolean());var fire=new CampfireBlockEntity(BlockPos.ZERO,state);fire.setLevel(world);
   var check=RecipeManager.createCheck(RecipeType.CAMPFIRE_COOKING);List<Object> observations=new ArrayList<>();
   for(var operation:scene.getAsJsonArray("actions")){
    var action=operation.getAsJsonObject();world.reset();var record=new TreeMap<String,Object>();record.put("op",action.get("op").getAsString());
    switch(action.get("op").getAsString()){
     case "place"->{var held=item(action.get("item"));record.put("accepted",fire.placeFood(world,null,held));record.put("held",stack(held));}
     case "ticks"->{for(int n=0;n<action.get("count").getAsInt();n++){if(state.getValue(CampfireBlock.LIT))CampfireBlockEntity.cookTick(world,BlockPos.ZERO,state,fire,check);else CampfireBlockEntity.cooldownTick(world,BlockPos.ZERO,state,fire);}}
     case "lit"->{boolean lit=action.get("value").getAsBoolean();if(lit!=state.getValue(CampfireBlock.LIT))check=RecipeManager.createCheck(RecipeType.CAMPFIRE_COOKING);state=state.setValue(CampfireBlock.LIT,lit);fire.setBlockState(state);}
     case "catalog"->{world.manager=manager(action.getAsJsonArray("recipes"));}
     case "features"->{world.flags=action.get("enabled").getAsBoolean()?FeatureFlags.VANILLA_SET:FeatureFlagSet.of();}
     case "load"->{var slots=action.getAsJsonArray("items");for(int i=0;i<4;i++)fire.getItems().set(i,item(slots.get(i)));for(int i=0;i<4;i++){times(fire,"cookingProgress")[i]=integer(action.getAsJsonArray("progress").get(i));times(fire,"cookingTime")[i]=integer(action.getAsJsonArray("total").get(i));}check=RecipeManager.createCheck(RecipeType.CAMPFIRE_COOKING);}
     case "remove"->{fire.preRemoveSideEffects(BlockPos.ZERO,state);}
     case "clear"->{fire.clearContent();}
     default->throw new AssertionError(action);
    }
    record.put("state",snapshot(fire,check));record.put("drops",world.drops.stream().map(CampfireAuthorityReference::stack).toList());record.put("dirty",world.dirty);record.put("updates",world.updates);record.put("changes",world.changes);record.put("xp_entities",world.xp);observations.add(record);
   }cases.add(Map.of("id",scene.get("id").getAsString(),"observations",observations));
  }
  Files.writeString(Path.of(args[1]),JSON.toJson(Map.of("version",SharedConstants.getCurrentVersion().id(),"features",features,"cases",cases)));
 }
}'''
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def item(id,count=1,patch=None):
    v={'id':'minecraft:'+id,'count':count}
    if patch is not None:v['components']=patch
    return v
def cooking(id,ingredient,result,time=1):return {'id':'bendcraft:'+id,'source':{'type':'minecraft:campfire_cooking','ingredient':ingredient,'result':result,'cookingtime':time,'experience':1000}}
def inputs():
    catalog=json.loads((ROOT/'build/cooking-recipe-reference/production-catalog.json').read_text())
    initialized=json.loads((ROOT/'reference/furnace_authority.json').read_text());assert initialized['pin']=='26.3'
    defaults={r['id']:r['components'] for r in initialized['defaults']}
    for row in catalog['items']:row['components']=defaults[row['id']]
    diagnostic=[cooking('fast','minecraft:potato',{'id':'minecraft:baked_potato','count':2},3),
      cooking('replacement','minecraft:potato',{'id':'minecraft:gold_ingot','count':3},1),
      cooking('zero','minecraft:potato',{'id':'minecraft:stone'},0),
      cooking('negative','minecraft:potato',{'id':'minecraft:stone'},-1),
      cooking('minimum','minecraft:potato',{'id':'minecraft:stone'},-2147483648),
      cooking('strict_empty','minecraft:potato',{'id':'minecraft:stone','count':65},1),
      cooking('patched','minecraft:potato',{'id':'minecraft:stone','components':{'minecraft:enchantment_glint_override':True}},1),
      cooking('collision_a','minecraft:oak_planks',{'id':'minecraft:stone'},1),
      cooking('collision_b',['minecraft:oak_planks','minecraft:stone'],{'id':'minecraft:gold_ingot'},1)]
    catalog['recipes'] += diagnostic
    cases=[]
    def scene(id,recipes,actions,lit=True,soul=False):cases.append({'id':id,'recipes':recipes,'lit':lit,'soul':soul,'actions':actions})
    def place(v):return {'op':'place','item':v}
    def ticks(n):return {'op':'ticks','count':n}
    def load(items,p=[0,0,0,0],t=[1,1,1,1]):return {'op':'load','items':items,'progress':p,'total':t}
    vanilla='minecraft:baked_potato_from_campfire_cooking'
    for soul in (False,True):scene('vanilla_four_'+str(soul),[vanilla],[*[place(item('potato',5-i)) for i in range(5)],ticks(599),ticks(1),ticks(1),{'op':'remove'}],soul=soul)
    scene('unlit_place',['bendcraft:fast'],[place(item('potato',2)),ticks(5),{'op':'lit','value':True},ticks(2),{'op':'lit','value':False},ticks(1),{'op':'lit','value':True},ticks(3)],lit=False)
    scene('cooldown_empty_signed',[],[load([None]*4,[5,1,4294967295,7],[10,10,10,4294967295]),ticks(1),ticks(2)],lit=False)
    for name,time in [('zero',0),('negative',4294967295),('minimum',2147483648)]:scene('time_'+name,['bendcraft:'+name],[place(item('potato')),ticks(1)])
    scene('signed_overflow',['bendcraft:fast'],[load([item('potato'),None,None,None],[2147483647,0,0,0],[2147483647,0,0,0]),ticks(1)])
    scene('fallback_components',['bendcraft:fast'],[place(item('potato',2,{'minecraft:enchantment_glint_override':True})),{'op':'catalog','recipes':[]},ticks(3),{'op':'remove'}])
    scene('recipe_replacement',[vanilla],[place(item('potato')),ticks(599),{'op':'catalog','recipes':['bendcraft:replacement']},ticks(1)])
    scene('feature_retry',['bendcraft:fast'],[place(item('potato')),{'op':'features','enabled':False},ticks(3),ticks(1),{'op':'features','enabled':True},ticks(1)])
    for name in ('strict_empty','patched'):scene('result_'+name,['bendcraft:'+name],[place(item('potato')),ticks(1)])
    scene('cached_registry_order',['bendcraft:collision_a','bendcraft:collision_b'],[load([item('stone'),item('oak_planks'),None,None]),ticks(1)])
    scene('remove_owned_items',[],[load([item('potato',37),item('stone',2,{'minecraft:enchantment_glint_override':True}),None,item('oak_planks')],[11,2,5,0],[600,1,0,0]),{'op':'remove'},{'op':'remove'},ticks(1)])
    scene('wrong_input',['bendcraft:fast'],[place(item('diamond')),place(None),ticks(1)])
    return {'catalog':catalog,'cases':cases}
def main():
    WORK.mkdir(parents=True,exist_ok=True);value=inputs();(WORK/'inputs.json').write_text(json.dumps(value,separators=(',',':'))+'\n');(WORK/'CampfireAuthorityReference.java').write_text(SOURCE)
    paths,provenance=verified_client_classpath();cmd=[JAVA,'-Xmx512m','--source','25','--class-path',os.pathsep.join(map(str,paths)),WORK/'CampfireAuthorityReference.java',WORK/'inputs.json',WORK/'output.json']
    start=time.monotonic();p=subprocess.run(list(map(str,cmd)),cwd=WORK,capture_output=True,text=True,timeout=120);(WORK/'java.stdout').write_text(p.stdout);(WORK/'java.stderr').write_text(p.stderr);assert p.returncode==0,p.stderr
    observed=json.loads((WORK/'output.json').read_text());assert observed['version']=='26.3';assert all(o['xp_entities']==0 for c in observed['cases'] for o in c['observations'])
    value['catalog']['campfire_features']=observed['features']
    (WORK/'native-input.json').write_text(json.dumps(value,separators=(',',':'))+'\n')
    result={'pin':'26.3','inputs':value,'observations':observed,'source_sha256':hashlib.sha256(SOURCE.encode()).hexdigest(),'input_sha256':digest(WORK/'inputs.json'),'output_sha256':digest(WORK/'output.json'),'provenance':provenance,'command':list(map(str,cmd)),'seconds':round(time.monotonic()-start,4),'scope':'Actual unmodified CampfireBlockEntity placeFood/cookTick/cooldownTick/preRemoveSideEffects/clearContent and real RecipeManager/CachedCheck/template/component codecs. Reference-only Unsafe allocates the ServerLevel I/O fixture; it overrides world notifications/features/RNG/item-entity admission, not campfire/recipe/timer algorithms. Actual ItemEntity constructors/dropItemStack run. Snapshots load diagnostic arrays reflectively; persistence storage codec is not claimed by those loads. No Python runtime cooking and no unchanged recipe-corpus replay.'}
    (ROOT/'reference/campfire_authority.json').write_text(json.dumps(result,separators=(',',':'))+'\n')
    summary={'status':'passed','pin':'26.3','command':'python3 tools/reference_campfire_authority.py','cases':len(observed['cases']),'observations':sum(len(c['observations']) for c in observed['cases']),'xp_entities_observed':0,'input_sha256':result['input_sha256'],'output_sha256':result['output_sha256'],'seconds':result['seconds'],'scope':result['scope']}
    (ROOT/'evidence/campfire-authority-reference.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary))
if __name__=='__main__':main()
