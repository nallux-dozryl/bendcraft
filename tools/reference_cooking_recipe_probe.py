#!/usr/bin/env python3
"""Pinned cooking codec and real furnace receivers; no game logic in Python."""
from __future__ import annotations
import collections,copy,json,struct,subprocess,time
import reference_crafting_recipe_probe as P
from reference_inventory import ROOT,JAVA,canonical,fingerprint,write_json
from reference_player_inventory_probe import verified_classpath

CACHE=ROOT/'build/cooking-recipe-reference'
OUTPUT=ROOT/'reference/cooking_recipe.json'
KINDS=('minecraft:smelting','minecraft:blasting','minecraft:smoking','minecraft:campfire_cooking')
SOURCE=r'''import java.nio.file.*;import java.util.*;import java.lang.reflect.*;
import com.google.gson.*;import com.mojang.serialization.*;
import net.minecraft.SharedConstants;import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;import net.minecraft.core.registries.*;
import net.minecraft.core.component.*;import net.minecraft.data.registries.VanillaRegistries;
import net.minecraft.resources.*;import net.minecraft.tags.*;
import net.minecraft.world.item.*;import net.minecraft.world.item.crafting.*;
import net.minecraft.world.level.block.*;import net.minecraft.world.level.block.entity.*;
import net.minecraft.util.Mth;
class CookingRecipeProbe {
 static RegistryOps<JsonElement> OPS;static final Gson JSON=new GsonBuilder().serializeNulls().create();
 static long bits(float f){return Integer.toUnsignedLong(Float.floatToRawIntBits(f));}
 static Map<String,Object> stack(ItemStack value){var out=new TreeMap<String,Object>();out.put("empty",value.isEmpty());out.put("id",BuiltInRegistries.ITEM.getKey(value.getItem()).toString());out.put("count",value.getCount());out.put("limit",value.getMaxStackSize());out.put("components",DataComponentMap.CODEC.encodeStart(OPS,value.getComponents()).result().orElseThrow());return out;}
 static ItemStack item(JsonElement raw){if(raw.isJsonNull())return ItemStack.EMPTY;var value=raw.getAsJsonObject();var id=Identifier.parse(value.get("id").getAsString());ItemStack result=new ItemStack(BuiltInRegistries.ITEM.getValue(id),1);if(value.has("components"))result.applyComponents(DataComponentPatch.CODEC.parse(OPS,value.get("components")).result().orElseThrow());result.setCount(value.get("count").getAsInt());return result;}
 static Object signed(int value){return Integer.toUnsignedLong(value);}
 static void referenced(JsonElement value,Set<String> ids){if(value.isJsonObject())for(var pair:value.getAsJsonObject().entrySet())referenced(pair.getValue(),ids);else if(value.isJsonArray())for(var child:value.getAsJsonArray())referenced(child,ids);else if(value.isJsonPrimitive()&&value.getAsJsonPrimitive().isString()){String raw=value.getAsString();if(raw.matches("[a-z0-9_.-]+:[a-z0-9_./-]+")&&BuiltInRegistries.ITEM.containsKey(Identifier.parse(raw)))ids.add(raw);}}
 public static void main(String[] args)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();var lookup=VanillaRegistries.createWorldLookup();for(var pending:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup))pending.forEach((holder,components)->holder.bindComponents(components));
  var catalog=JsonParser.parseString(Files.readString(Path.of(args[2]))).getAsJsonObject();Map<TagKey<Item>,List<Holder<Item>>> tags=new LinkedHashMap<>();for(var value:catalog.getAsJsonArray("tags")){var tag=value.getAsJsonObject();List<Holder<Item>> members=new ArrayList<>();for(var id:tag.getAsJsonArray("items"))members.add(BuiltInRegistries.ITEM.get(Identifier.parse(id.getAsString())).orElseThrow());tags.put(TagKey.create(Registries.ITEM,Identifier.parse(tag.get("id").getAsString())),members);}BuiltInRegistries.ITEM.prepareTagReload(new TagLoader.LoadResult<Item>(Registries.ITEM,tags)).apply();
  OPS=RegistryOps.create(JsonOps.INSTANCE,lookup);
  var input=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonObject();Map<String,AbstractCookingRecipe> recipes=new LinkedHashMap<>();List<Object> records=new ArrayList<>();
  for(var element:input.getAsJsonArray("recipes")){var row=element.getAsJsonObject();String id=row.get("id").getAsString();var record=new TreeMap<String,Object>();record.put("id",id);
   try{var decoded=Recipe.DIRECT_CODEC.parse(OPS,row.get("source"));record.put("accepted",decoded.result().isPresent());if(decoded.result().isPresent()){
    var raw=decoded.result().get();record.put("class",raw.getClass().getName());if(raw instanceof AbstractCookingRecipe recipe){recipes.put(id,recipe);record.put("cooking_time",signed(recipe.cookingTime()));record.put("experience_bits",bits(recipe.experience()));var query=item(row.get("input"));record.put("output",stack(recipe.assemble(new SingleRecipeInput(query))));List<Object> matches=new ArrayList<>();for(var s:row.getAsJsonArray("matches")){var slot=item(s);matches.add(Map.of("matches",recipe.matches(new SingleRecipeInput(slot),null),"empty",slot.isEmpty(),"count",slot.getCount()));}record.put("matches",matches);}}
    else record.put("error",decoded.error().orElseThrow().message());
   }catch(RuntimeException e){record.putIfAbsent("accepted",false);record.put("observation_error",e.getClass().getName()+": "+String.valueOf(e.getMessage()));}records.add(record);
  }
  List<Object> queries=new ArrayList<>();for(var element:input.getAsJsonArray("queries")){var row=element.getAsJsonObject();var registry=new MappedRegistry<Recipe<?>>(Registries.RECIPE,Lifecycle.stable());for(var candidate:row.getAsJsonArray("recipes")){String id=candidate.getAsString();if(recipes.containsKey(id))registry.register(ResourceKey.create(Registries.RECIPE,Identifier.parse(id)),recipes.get(id),RegistrationInfo.BUILT_IN);}registry.freeze();var map=RecipeMap.create(registry);RecipeType type=switch(row.get("kind").getAsString()){case "minecraft:smelting"->RecipeType.SMELTING;case "minecraft:blasting"->RecipeType.BLASTING;case "minecraft:smoking"->RecipeType.SMOKING;case "minecraft:campfire_cooking"->RecipeType.CAMPFIRE_COOKING;default->throw new IllegalArgumentException();};var single=new SingleRecipeInput(item(row.get("input")));var found=map.getRecipesFor(type,single,null).findFirst();var record=new TreeMap<String,Object>();record.put("id",row.get("id").getAsString());if(found.isPresent()){RecipeHolder holder=(RecipeHolder)found.get();record.put("recipe",holder.id().identifier().toString());record.put("output",stack((ItemStack)holder.value().assemble(single)));}else{record.put("recipe",null);record.put("output",null);}queries.add(record);}
  var can=AbstractFurnaceBlockEntity.class.getDeclaredMethod("canBurn",NonNullList.class,int.class,ItemStack.class);can.setAccessible(true);var burn=AbstractFurnaceBlockEntity.class.getDeclaredMethod("burn",NonNullList.class,ItemStack.class,ItemStack.class);burn.setAccessible(true);
  List<Object> transitions=new ArrayList<>();for(var element:input.getAsJsonArray("transitions")){var row=element.getAsJsonObject();var recipe=recipes.get(row.get("recipe").getAsString());var slots=NonNullList.withSize(3,ItemStack.EMPTY);slots.set(0,item(row.get("input")));slots.set(1,item(row.get("fuel")));slots.set(2,item(row.get("output")));var result=recipe.assemble(new SingleRecipeInput(slots.get(0)));boolean matched=recipe.matches(new SingleRecipeInput(slots.get(0)),null),capacity=(boolean)can.invoke(null,slots,row.get("limit").getAsInt(),result);boolean accepted=matched&&!result.isEmpty()&&capacity;var record=new TreeMap<String,Object>();record.put("id",row.get("id").getAsString());record.put("can_burn",capacity);record.put("matched",matched);record.put("accepted",accepted);record.put("assembled",stack(result));if(accepted)burn.invoke(null,slots,slots.get(0),result);record.put("after",slots.stream().map(CookingRecipeProbe::stack).toList());transitions.add(record);}
  var timing=AbstractFurnaceBlockEntity.class.getDeclaredMethod("getTotalCookTime",RecipeHolder.class,AbstractFurnaceBlockEntity.class);timing.setAccessible(true);var speed=AbstractFurnaceBlockEntity.class.getDeclaredField("speedMultiplier");speed.setAccessible(true);var furnace=new FurnaceBlockEntity(BlockPos.ZERO,Blocks.FURNACE.defaultBlockState());List<Object> times=new ArrayList<>();for(var element:input.getAsJsonArray("times")){var row=element.getAsJsonObject();var recipe=recipes.get(row.get("recipe").getAsString());speed.setFloat(furnace,Float.intBitsToFloat((int)row.get("speed_bits").getAsLong()));var holder=new RecipeHolder<AbstractCookingRecipe>(ResourceKey.create(Registries.RECIPE,Identifier.parse(row.get("recipe").getAsString())),recipe);int value=(int)timing.invoke(null,holder,furnace);times.add(Map.of("id",row.get("id").getAsString(),"time",signed(value)));}
  List<Object> xp=new ArrayList<>();for(var element:input.getAsJsonArray("xp")){var row=element.getAsJsonObject();int uses=(int)row.get("uses").getAsLong();float rate=Float.intBitsToFloat((int)row.get("rate_bits").getAsLong()),ticket=Float.intBitsToFloat((int)row.get("ticket_bits").getAsLong()),product=(float)uses*rate;int whole=Mth.floor(product);float fraction=Mth.frac(product);boolean advance=fraction!=0.0f;if(advance&&ticket<fraction)whole++;xp.add(Map.of("id",row.get("id").getAsString(),"award",signed(whole),"fraction_bits",bits(fraction),"advances_rng",advance));}
  Set<String> needed=new TreeSet<>();referenced(input,needed);needed.add("minecraft:water_bucket");List<Object> defaults=new ArrayList<>();for(String id:needed){Item value=BuiltInRegistries.ITEM.getValue(Identifier.parse(id));defaults.add(Map.of("id",id,"components",DataComponentMap.CODEC.encodeStart(OPS,value.components()).result().orElseThrow()));}
  List<Object> items=new ArrayList<>();for(Item value:BuiltInRegistries.ITEM){var record=new TreeMap<String,Object>();record.put("id",BuiltInRegistries.ITEM.getKey(value).toString());record.put("limit",value.getDefaultInstance().getMaxStackSize());var remainder=value.getCraftingRemainder();Object rest=null;if(remainder!=null){var stack=remainder.create();if(!ItemStack.isSameItemSameComponents(stack,stack.getItem().getDefaultInstance()))throw new IllegalStateException("nondefault crafting remainder outside shared item contract");if(!stack.isEmpty())rest=Map.of("id",BuiltInRegistries.ITEM.getKey(stack.getItem()).toString(),"count",stack.getCount());}record.put("remainder",rest);items.add(record);}
  Files.writeString(Path.of(args[1]),JSON.toJson(Map.of("recipes",records,"queries",queries,"transitions",transitions,"times",times,"xp",xp,"defaults",defaults,"items",items)));
 }
}'''

def bits(value):return struct.unpack('>I',struct.pack('>f',value))[0]
def slot(id,count=1,components=None):
    value={'id':id,'count':count}
    if components is not None:value['components']=components
    return value

def inputs():
    recipes,tags,provenance=P.resources();rows=[]
    def first(ingredient):
        if isinstance(ingredient,list):return ingredient[0] if ingredient else 'minecraft:oak_planks'
        if not isinstance(ingredient,str):return 'minecraft:oak_planks'
        return tags[ingredient[1:]][0] if ingredient.startswith('#') else ingredient
    def row(id,source):
        item=first(source['ingredient']);s=slot(item)
        return {'id':id,'source':source,'input':s,'matches':[s,None,slot('minecraft:air'),slot(item,0),slot(item,2),slot(item,1,{'minecraft:enchantment_glint_override':True})]}
    for id,r in recipes.items():
        if r['type'] in KINDS:rows.append(row(id,r))
    def add(label,**changes):
        source={'type':'minecraft:smelting','ingredient':'minecraft:oak_planks','result':{'id':'minecraft:stone'},'cookingtime':200,'experience':0.1};source.update(changes)
        value=row('bendcraft:'+label,source);rows.append(value);return value['id']
    missing_xp=add('missing_xp');rows[-1]['source'].pop('experience')
    add('missing_time');rows[-1]['source'].pop('cookingtime')
    for label,value in [('zero',0),('negative',-1),('minimum',-2147483648),('maximum',2147483647),('fractional',1.9),('overflow',2147483648),('string','200')]:add('time_'+label,cookingtime=value)
    for label,value in [('zero',0),('negative',-0.35),('precise',0.10000000149011612),('tiny',1e-45),('large',1e30),('overflow',1e39),('string','0.35'),('null',None)]:add('xp_'+label,experience=value)
    for label,value in [('category','unknown'),('category_type',3),('group',3),('show_notification',3)]:add('invalid_'+label,**{label.replace('_type',''):value})
    add('book_fields',category='blocks',group='any group',show_notification=False)
    add('tag',ingredient='#minecraft:logs');add('alternatives',ingredient=['minecraft:oak_planks','minecraft:stone'])
    add('empty_alternatives',ingredient=[]);rows[-1]['input']=slot('minecraft:oak_planks');rows[-1]['matches']=[slot('minecraft:oak_planks')]
    add('old_ingredient',ingredient={'item':'minecraft:oak_planks'});rows[-1]['input']=slot('minecraft:oak_planks');rows[-1]['matches']=[slot('minecraft:oak_planks')]
    add('count_two',result={'id':'minecraft:stone','count':2})
    add('strict_count',result={'id':'minecraft:stone','count':65})
    add('patched_result',result={'id':'minecraft:stone','components':{'minecraft:enchantment_glint_override':True}})
    add('removed_limit',result={'id':'minecraft:stone','components':{'!minecraft:max_stack_size':{}}})
    add('removed_limit_count2',result={'id':'minecraft:stone','count':2,'components':{'!minecraft:max_stack_size':{}}})
    add('stack99',result={'id':'minecraft:stone','count':99,'components':{'minecraft:max_stack_size':99}})
    add('unimplemented_setter',result={'id':'minecraft:stone','components':{'minecraft:rarity':'epic'}})
    add('collision_blasting',type='minecraft:blasting',result={'id':'minecraft:iron_ingot'},cookingtime=73)
    add('collision_campfire',type='minecraft:campfire_cooking',result={'id':'minecraft:gold_ingot'},cookingtime=600)
    rows.append({'id':'bendcraft:other_subclass','source':{'type':'minecraft:stonecutting','ingredient':'minecraft:stone','result':{'id':'minecraft:stone_slab','count':2}},'input':slot('minecraft:stone'),'matches':[]})
    transitions=[]
    def transition(label,recipe='bendcraft:count_two',input=None,fuel=None,output=None,limit=64,boundary=None):
        transitions.append({'id':label,'recipe':recipe,'input':slot('minecraft:oak_planks',2) if input is None else input,'fuel':fuel,'output':output,'limit':limit,'boundary':boundary})
    transition('empty');transition('empty_limit_zero',limit=0);transition('empty_limit_one',limit=1)
    transition('fits_exact',output=slot('minecraft:stone',62));transition('one_over',output=slot('minecraft:stone',63));transition('container_lower',output=slot('minecraft:stone',1),limit=2)
    transition('different_item',output=slot('minecraft:cobblestone',1));transition('different_components',output=slot('minecraft:stone',1,{'minecraft:enchantment_glint_override':True}))
    transition('patched_same',recipe='bendcraft:patched_result',output=slot('minecraft:stone',63,{'minecraft:enchantment_glint_override':True}))
    transition('patched_default',recipe='bendcraft:patched_result',output=slot('minecraft:stone',1))
    transition('strict_empty',recipe='bendcraft:strict_count');transition('removed_limit_empty',recipe='bendcraft:removed_limit_count2')
    transition('all99_empty',recipe='bendcraft:stack99');transition('all99_full',recipe='bendcraft:stack99',output=slot('minecraft:stone',1,{'minecraft:max_stack_size':99}),limit=99)
    transition('last_input',input=slot('minecraft:oak_planks',1));transition('wrong_input',input=slot('minecraft:stone',2));transition('zero_input',input=slot('minecraft:oak_planks',0),boundary='invalid_state')
    transition('overfull_input',input=slot('minecraft:oak_planks',65),boundary='invalid_state');transition('component_input',input=slot('minecraft:oak_planks',2,{'minecraft:enchantment_glint_override':True}))
    transition('component_no_authority',input=slot('minecraft:oak_planks',2,{'minecraft:enchantment_glint_override':True}),boundary='missing_metadata')
    sponge=next(id for id,r in recipes.items() if r['type']=='minecraft:smelting' and r['ingredient']=='minecraft:wet_sponge')
    for label,fuel in [('sponge_bucket',slot('minecraft:bucket')),('sponge_bucket16',slot('minecraft:bucket',16)),('sponge_modified_bucket',slot('minecraft:bucket',1,{'minecraft:enchantment_glint_override':True})),('sponge_coal',slot('minecraft:coal')),('sponge_lava_bucket',slot('minecraft:lava_bucket'))]:transition(label,recipe=sponge,input=slot('minecraft:wet_sponge',2),fuel=fuel)
    transition('stale_input',boundary='stale_plan');transition('forged_output',boundary='forged_plan');transition('campfire_guard',recipe='minecraft:baked_potato_from_campfire_cooking',input=slot('minecraft:potato'),boundary='campfire_kind')
    queries=[]
    def query(label,choices=None,input=None,kind='minecraft:smelting',mode='default',boundary=None):
        queries.append({'id':label,'recipes':['bendcraft:count_two','bendcraft:missing_xp'] if choices is None else choices,'input':slot('minecraft:oak_planks') if input is None else input,'kind':kind,'metadata':mode,'boundary':boundary})
    query('first_collision');query('reversed_collision',['bendcraft:missing_xp','bendcraft:count_two'])
    query('type_filter',['bendcraft:collision_blasting','bendcraft:count_two']);query('blast_filter',['bendcraft:count_two','bendcraft:collision_blasting'],kind='minecraft:blasting')
    query('campfire_filter',['bendcraft:count_two','bendcraft:collision_campfire'],kind='minecraft:campfire_cooking')
    query('tag_member',['bendcraft:tag'],input=slot('minecraft:oak_log'));query('alternative_member',['bendcraft:alternatives'],input=slot('minecraft:stone'))
    query('no_match',input=slot('minecraft:diamond'));query('empty_input');queries[-1]['input']=None
    query('zero_input',input=slot('minecraft:oak_planks',0),boundary='invalid_state');query('overfull_input',input=slot('minecraft:oak_planks',65),boundary='invalid_state')
    for label,mode,boundary in [('component_validated','validated',None),('component_absent','none','missing_metadata'),('component_zero_limit','zero','invalid_metadata'),('component_large_limit','large','invalid_metadata'),('component_wrong_key','wrong','invalid_metadata')]:query(label,input=slot('minecraft:oak_planks',1,{'minecraft:enchantment_glint_override':True}),mode=mode,boundary=boundary)
    query('unsupported_skipped',['bendcraft:other_subclass','bendcraft:count_two'])
    query('strict_empty_plan',['bendcraft:strict_count']);query('removed_limit_empty_plan',['bendcraft:removed_limit_count2'])
    times=[]
    speed_bits=[bits(x) for x in [1,2,0.5,1.5,3,0,-1,float('inf')]]+[1,0x7fc00000]
    for recipe in ['bendcraft:count_two','bendcraft:time_negative','bendcraft:time_zero','bendcraft:time_minimum','bendcraft:time_maximum']:
        for b in speed_bits:times.append({'id':f'{recipe}/{b}','recipe':recipe,'speed_bits':b})
    xp=[]
    rates=[bits(x) for x in [0,0.1,0.35,0.7,1,2,-0.35,1e30,float('inf'),-float('inf')]]+[0x7fc00000,1]
    for uses in [0,1,2,3,10,16777217,2147483647,2147483648,4294967295]:
        for rate in rates:
            for ticket in [bits(0),bits(0.35),bits(0.9999999403953552)]:xp.append({'id':f'{uses}/{rate}/{ticket}','uses':uses,'rate_bits':rate,'ticket_bits':ticket})
    return {'recipes':rows,'queries':queries,'transitions':transitions,'times':times,'xp':xp},provenance

def materialize(inputs,items,defaults):
    _,tags,_=P.resources()
    source={'items':copy.deepcopy(items),'tags':[{'id':id,'items':members} for id,members in tags.items()]}
    prior={r['id']:r['components'] for r in json.loads((ROOT/'reference/crafting_recipe_components.json').read_text())['defaults'] if 'error' not in r['components']}
    replacements={r['id']:r['components'] for r in (defaults or [])}
    for item in source['items']:
        if item['id'] in replacements:item['components']=replacements[item['id']]
        elif item['id'] in prior:item['components']=prior[item['id']]
    # Installed source-only production catalog is never populated with diagnostics.
    source['recipes']=[{'id':r['id'],'source':r['source']} for r in inputs['recipes'] if r['id'].startswith('minecraft:')]
    assert len(source['recipes'])==116
    write_json(CACHE/'production-catalog.json',source)
    diagnostic={**source,'recipes':[{'id':r['id'],'source':r['source']} for r in inputs['recipes']]}
    write_json(CACHE/'catalog.json',diagnostic)
    return source

def extract():
    CACHE.mkdir(parents=True,exist_ok=True);data,resource_pin=inputs();write_json(CACHE/'input.json',data)
    _,tags,_=P.resources();write_json(CACHE/'tag-input.json',{'tags':[{'id':id,'items':members} for id,members in sorted(tags.items())]})
    java=CACHE/'CookingRecipeProbe.java';java.write_text(SOURCE);cp,provenance=verified_classpath();start=time.monotonic()
    owners={
        'javap.txt':['net.minecraft.world.item.crafting.'+name for name in ['AbstractCookingRecipe','SmeltingRecipe','BlastingRecipe','SmokingRecipe','CampfireCookingRecipe']]+['net.minecraft.world.level.block.entity.AbstractFurnaceBlockEntity','net.minecraft.world.level.block.entity.CampfireBlockEntity'],
        'single-xp-javap.txt':['net.minecraft.world.item.crafting.SingleItemRecipe','net.minecraft.world.item.crafting.AbstractCookingRecipe$CookingBookInfo','net.minecraft.world.item.crafting.CookingBookCategory','net.minecraft.util.Mth','net.minecraft.world.level.block.entity.FurnaceBlockEntity','net.minecraft.world.level.block.entity.BlastFurnaceBlockEntity','net.minecraft.world.level.block.entity.SmokerBlockEntity'],
        'book-javap.txt':['net.minecraft.world.item.crafting.Recipe$CommonInfo','net.minecraft.world.item.crafting.Recipe$BookInfo','net.minecraft.world.item.ItemStack'],
        'map-javap.txt':['net.minecraft.world.item.crafting.RecipeMap','net.minecraft.world.item.crafting.RecipeManager']}
    for name,classes in owners.items():
        dump=subprocess.run([str(JAVA.parent/'javap'),'-p','-c','-s','--class-path',':'.join(map(str,cp)),*classes],capture_output=True,text=True,check=True,timeout=20)
        (CACHE/name).write_text(dump.stdout)
    result=subprocess.run([str(JAVA),'-Xmx768m','-Djava.awt.headless=true','--class-path',':'.join(map(str,cp)),str(java),str(CACHE/'input.json'),str(CACHE/'output.json'),str(CACHE/'tag-input.json')],capture_output=True,text=True,timeout=90)
    (CACHE/'process.log').write_text(result.stdout+result.stderr)
    if result.returncode:raise AssertionError((result.stdout+result.stderr)[-6000:])
    observed=json.loads((CACHE/'output.json').read_text());observed.update(pin='26.3',schema_version=1,source_sha256=P.sha(SOURCE.encode()),inputs_sha256=P.sha(canonical(data)),provenance=provenance,resources={k:v for k,v in resource_pin.items() if '/tags/item/' in k or any(k.endswith('/'+r['id'].split(':')[1]+'.json') for r in data['recipes'] if r['id'].startswith('minecraft:'))},seconds=round(time.monotonic()-start,6),installed_types=dict(collections.Counter(r['source']['type'] for r in data['recipes'] if r['id'].startswith('minecraft:'))))
    materialize(data,observed['items'],observed['defaults'])
    observed['receiver_scope']={'actual_calls':['Recipe.DIRECT_CODEC.parse','SingleItemRecipe.matches/assemble','AbstractCookingRecipe.cookingTime/experience','AbstractFurnaceBlockEntity.canBurn/burn/getTotalCookTime via reflection','Mth.floor(float)/frac(float)'],'xp_boundary':'XP arithmetic invokes actual Mth receivers; nextFloat threshold is supplied from the fixture. The world-dependent createExperience receiver is inspected bytecode, not invoked; orb spawning/RNG integration is unimplemented.'}
    methods=['javap.txt','single-xp-javap.txt','book-javap.txt','map-javap.txt'];observed['javap']={name:fingerprint(CACHE/name) for name in methods}
    write_json(OUTPUT,observed);return observed

if __name__=='__main__':
    data=extract();print(json.dumps({'recipes':len(data['recipes']),'transitions':len(data['transitions']),'times':len(data['times']),'xp':len(data['xp']),'seconds':data['seconds']}))
