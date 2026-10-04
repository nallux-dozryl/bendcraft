#!/usr/bin/env python3
"""Targeted actual Java component-patched recipe/stack observations."""
from __future__ import annotations
import json,subprocess,time,zipfile
from pathlib import Path
import reference_crafting_recipe_probe as P
from reference_inventory import ROOT,JAVA,canonical,fingerprint,write_json
from reference_player_inventory_probe import verified_classpath

CACHE=ROOT/'build/crafting-recipe-components'
OUTPUT=ROOT/'reference/crafting_recipe_components.json'
SOURCE=r'''import java.nio.file.*;import java.io.*;import java.util.*;
import com.google.gson.*;import com.mojang.serialization.*;
import net.minecraft.SharedConstants;import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;import net.minecraft.core.registries.*;
import net.minecraft.data.registries.VanillaRegistries;import net.minecraft.resources.*;
import net.minecraft.world.item.*;import net.minecraft.world.item.crafting.*;
import net.minecraft.core.component.*;
import net.minecraft.tags.*;
class CraftingRecipeComponentsProbe {
 static final Gson JSON=new GsonBuilder().serializeNulls().create();static RegistryOps<JsonElement> OPS;
 static Object encode(DataResult<JsonElement> result){return result.result().isPresent()?result.result().get():Map.of("error",result.error().orElseThrow().message());}
 static Map<String,Object> stack(ItemStack value){Map<String,Object> out=new TreeMap<>();out.put("empty",value.isEmpty());out.put("id",BuiltInRegistries.ITEM.getKey(value.getItem()).toString());out.put("count",value.getCount());out.put("limit",value.getMaxStackSize());out.put("components",encode(DataComponentMap.CODEC.encodeStart(OPS,value.getComponents())));out.put("patch",encode(DataComponentPatch.CODEC.encodeStart(OPS,value.getComponentsPatch())));return out;}
 public static void main(String[] args)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();var lookup=VanillaRegistries.createWorldLookup();for(var pending:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup))pending.forEach((holder,components)->holder.bindComponents(components));
  var catalog=JsonParser.parseString(Files.readString(Path.of(args[2]))).getAsJsonObject();Map<TagKey<Item>,List<Holder<Item>>> tags=new LinkedHashMap<>();for(var value:catalog.getAsJsonArray("tags")){var tag=value.getAsJsonObject();List<Holder<Item>> members=new ArrayList<>();for(var id:tag.getAsJsonArray("items"))members.add(BuiltInRegistries.ITEM.get(Identifier.parse(id.getAsString())).orElseThrow());tags.put(TagKey.create(Registries.ITEM,Identifier.parse(tag.get("id").getAsString())),members);}BuiltInRegistries.ITEM.prepareTagReload(new TagLoader.LoadResult<Item>(Registries.ITEM,tags)).apply();
  OPS=RegistryOps.create(JsonOps.INSTANCE,RegistryAccess.fromRegistryOfRegistries(BuiltInRegistries.REGISTRY));
  var input=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonArray();Map<String,ItemStack> outputs=new LinkedHashMap<>();Map<String,Object> records=new TreeMap<>();List<Object> cases=new ArrayList<>();
  for(var element:input){var row=element.getAsJsonObject();String id=row.get("id").getAsString();Map<String,Object> result=new TreeMap<>();result.put("id",id);
   try{var decoded=Recipe.DIRECT_CODEC.parse(OPS,row.get("source"));result.put("accepted",decoded.result().isPresent());if(decoded.result().isPresent()){
    CraftingRecipe recipe=(CraftingRecipe)decoded.result().get();var raw=row.getAsJsonObject("grid");List<ItemStack> slots=new ArrayList<>();for(var item:raw.getAsJsonArray("slots")){if(item.isJsonNull())slots.add(ItemStack.EMPTY);else {var s=item.getAsJsonObject();slots.add(new ItemStack(BuiltInRegistries.ITEM.getValue(Identifier.parse(s.get("id").getAsString())),s.get("count").getAsInt()));}}var grid=CraftingInput.of(raw.get("width").getAsInt(),raw.get("height").getAsInt(),slots);result.put("matches",recipe.matches(grid,null));var value=recipe.assemble(grid);outputs.put(id,value);result.put("output",stack(value));
   }else result.put("error",decoded.error().orElseThrow().message());}catch(RuntimeException e){result.put("accepted",false);result.put("exception",e.getClass().getName());result.put("error",String.valueOf(e.getMessage()));}cases.add(result);
  }
  records.put("cases",cases);List<Object> defaults=new ArrayList<>();for(Item item:BuiltInRegistries.ITEM){defaults.add(Map.of("id",BuiltInRegistries.ITEM.getKey(item).toString(),"components",encode(DataComponentMap.CODEC.encodeStart(OPS,item.components()))));}records.put("defaults",defaults);
  records.put("component_types",BuiltInRegistries.DATA_COMPONENT_TYPE.keySet().stream().map(Object::toString).sorted().toList());records.put("effects",BuiltInRegistries.MOB_EFFECT.keySet().stream().map(Object::toString).sorted().toList());
  List<Object> comparisons=new ArrayList<>();for(String a:outputs.keySet())for(String b:outputs.keySet()){boolean registry=a.contains("remove_registered_")||b.contains("remove_registered_");if(a.compareTo(b)<=0&&(!registry||a.equals(b)||a.equals("bendcraft:default_stack_size")||b.equals("bendcraft:default_stack_size")))comparisons.add(Map.of("a",a,"b",b,"same",ItemStack.isSameItemSameComponents(outputs.get(a),outputs.get(b))));}records.put("comparisons",comparisons);
  Files.writeString(Path.of(args[1]),JSON.toJson(records));
 }
}'''

def inputs():
    recipes,tags,_=P.resources();rows=[]
    for id,r in recipes.items():
        if r['type'] in ('minecraft:crafting_shaped','minecraft:crafting_shapeless') and 'components' in r.get('result',{}):
            items=[P.stack(tags[i[1:]][0] if i.startswith('#') else i) for i in r['ingredients']]
            rows.append({'id':id,'source':r,'grid':{'width':2,'height':2,'slots':items+[None]*(4-len(items))}})
    def add(label,item='minecraft:suspicious_stew',count=1,components=None):
        result={'id':item,'count':count}
        if components is not None:result['components']=components
        rows.append({'id':'bendcraft:'+label,'source':{'type':'minecraft:crafting_shapeless','ingredients':['minecraft:oak_planks'],'result':result},'grid':{'width':1,'height':1,'slots':[P.stack('minecraft:oak_planks')]}})
    add('stew_default');add('empty_patch',components={});add('remove_absent',components={'!minecraft:enchantment_glint_override':{}})
    add('stew_empty_effects',components={'minecraft:suspicious_stew_effects':[]})
    for label,duration in [('missing',None),('default',160),('zero',0),('negative',-1),('minimum',-2147483648),('maximum',2147483647),('bad_string','bad'),('fractional',1.5)]:
        entry={'id':'speed'}
        if duration is not None:entry['duration']=duration
        add('duration_'+label,components={'minecraft:suspicious_stew_effects':[entry]})
    add('duplicate_effects',components={'minecraft:suspicious_stew_effects':[{'id':'speed','duration':20},{'id':'speed','duration':40}]})
    add('ordered_effects',components={'minecraft:suspicious_stew_effects':[{'id':'speed','duration':20},{'id':'poison','duration':40}]})
    add('reversed_effects',components={'minecraft:suspicious_stew_effects':[{'id':'poison','duration':40},{'id':'speed','duration':20}]})
    add('unknown_effect',components={'minecraft:suspicious_stew_effects':[{'id':'bendcraft:missing'}]})
    add('remove_effects',components={'!minecraft:suspicious_stew_effects':{}})
    add('default_stack_size','minecraft:stone',components={'minecraft:max_stack_size':64})
    add('remove_stack_size','minecraft:stone',components={'!minecraft:max_stack_size':{}})
    add('remove_stack_size_count2','minecraft:stone',count=2,components={'!minecraft:max_stack_size':{}})
    add('stack99','minecraft:stone',99,{'minecraft:max_stack_size':99})
    add('bad_stack0','minecraft:stone',components={'minecraft:max_stack_size':0})
    add('damage_and_stack','minecraft:stone',components={'minecraft:max_damage':100})
    add('damage_and_stack1','minecraft:stone',components={'minecraft:max_damage':100,'minecraft:max_stack_size':1})
    add('remove_damage','minecraft:diamond_sword',components={'!minecraft:max_damage':{},'minecraft:max_stack_size':64})
    add('damage_above_max','minecraft:diamond_sword',components={'minecraft:damage':2147483647})
    add('unbreakable','minecraft:stone',components={'minecraft:unbreakable':{}})
    add('glint_false','minecraft:stone',components={'minecraft:enchantment_glint_override':False})
    add('glint_true','minecraft:stone',components={'minecraft:enchantment_glint_override':True})
    add('remove_default_rarity','minecraft:stone',components={'!minecraft:rarity':{}})
    add('unknown_component','minecraft:stone',components={'bendcraft:missing':{}})
    # Every registered removal uses the real patch codec; this supports a
    # registry-defined domain rather than assuming arbitrary removed keys.
    observed=json.loads((ROOT/'reference/item_stacks.json').read_text())['observations']
    for component in sorted(t['identifier'] for t in observed['component_types']):add('remove_registered_'+component.split(':')[1],'minecraft:stone',components={'!'+component:{}})
    return rows

def extract():
    CACHE.mkdir(parents=True,exist_ok=True);rows=inputs();write_json(CACHE/'input.json',rows);source=CACHE/'CraftingRecipeComponentsProbe.java';source.write_text(SOURCE)
    cp,provenance=verified_classpath();start=time.monotonic()
    result=subprocess.run([str(JAVA),'-Xmx768m','-Djava.awt.headless=true','--class-path',':'.join(map(str,cp)),str(source),str(CACHE/'input.json'),str(CACHE/'output.json'),str(P.CACHE/'catalog.json')],capture_output=True,text=True,timeout=90)
    (CACHE/'process.log').write_text(result.stdout+result.stderr)
    if result.returncode:raise RuntimeError((result.stdout+result.stderr)[-6000:])
    data=json.loads((CACHE/'output.json').read_text());data.update(schema_version=1,pin='26.3',source_sha256=P.sha(SOURCE.encode()),inputs_sha256=P.sha(canonical(rows)),provenance=provenance,seconds=round(time.monotonic()-start,6))
    write_json(OUTPUT,data)
    materialize(data,rows)
    return data

def materialize(data,rows=None):
    # Fixture and production catalogs are separate: diagnostics must not become
    # recipes in the game registry. Source recipes and jars remain ignored.
    rows=inputs() if rows is None else rows
    catalog=json.loads((P.CACHE/'catalog.json').read_text());defaults={d['id']:d['components'] for d in data['defaults']}
    for item in catalog['items']:item['components']=defaults[item['id']]
    originals,_,_=P.resources()
    production={**catalog,'recipes':[r for r in catalog['recipes'] if r['id'] in originals]}
    assert len(production['recipes'])==2042
    for row in production['recipes']:assert row['source']==originals[row['id']]
    write_json(CACHE/'production-catalog.json',production)
    catalog['recipes']=rows;write_json(CACHE/'catalog.json',catalog)
    return production

if __name__=='__main__':
    data=extract();print(json.dumps({'cases':len(data['cases']),'comparisons':len(data['comparisons']),'effects':len(data['effects']),'component_types':len(data['component_types']),'seconds':data['seconds']}))
