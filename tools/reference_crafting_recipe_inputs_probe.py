#!/usr/bin/env python3
"""Observe actual ingredient matching on component-bearing input stacks."""
from __future__ import annotations
import json,subprocess,time
import reference_crafting_recipe_components_probe as C
from reference_inventory import ROOT,JAVA,canonical,write_json
from reference_player_inventory_probe import verified_classpath

CACHE=ROOT/'build/crafting-recipe-inputs'
OUTPUT=ROOT/'reference/crafting_recipe_inputs.json'
SOURCE=r'''import java.nio.file.*;import java.util.*;import com.google.gson.*;
import com.mojang.serialization.*;import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;import net.minecraft.core.*;
import net.minecraft.core.registries.*;import net.minecraft.core.component.*;
import net.minecraft.data.registries.VanillaRegistries;import net.minecraft.resources.*;
import net.minecraft.world.item.*;import net.minecraft.world.item.crafting.*;
class CraftingRecipeInputsProbe {
 public static void main(String[] args)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();var lookup=VanillaRegistries.createWorldLookup();for(var pending:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup))pending.forEach((holder,components)->holder.bindComponents(components));
  var ops=RegistryOps.create(JsonOps.INSTANCE,RegistryAccess.fromRegistryOfRegistries(BuiltInRegistries.REGISTRY));var input=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonArray();List<Object> records=new ArrayList<>();
  for(var value:input){var row=value.getAsJsonObject();CraftingRecipe template=(CraftingRecipe)Recipe.DIRECT_CODEC.parse(ops,row.get("template_source")).result().orElseThrow();var stack=template.assemble(CraftingInput.of(1,1,List.of(new ItemStack(Items.OAK_PLANKS))));stack.setCount(row.get("count").getAsInt());CraftingRecipe recipe=(CraftingRecipe)Recipe.DIRECT_CODEC.parse(ops,row.get("recipe_source")).result().orElseThrow();var grid=CraftingInput.of(1,1,List.of(stack));Map<String,Object> record=new LinkedHashMap<>();record.put("id",row.get("id").getAsString());record.put("matches",recipe.matches(grid,null));record.put("empty",stack.isEmpty());record.put("count",stack.getCount());record.put("limit",stack.getMaxStackSize());record.put("components",DataComponentMap.CODEC.encodeStart(ops,stack.getComponents()).result().orElseThrow());var output=recipe.assemble(grid);record.put("output",output.isEmpty()?null:Map.of("id",BuiltInRegistries.ITEM.getKey(output.getItem()).toString(),"count",output.getCount()));List<Object> remainders=new ArrayList<>();for(var rest:recipe.getRemainingItems(grid))remainders.add(rest.isEmpty()?null:Map.of("id",BuiltInRegistries.ITEM.getKey(rest.getItem()).toString(),"count",rest.getCount()));record.put("remainders",remainders);records.add(record);}
  Files.writeString(Path.of(args[1]),new GsonBuilder().create().toJson(records));
 }
}'''

def inputs():
    templates={r['id']:r for r in C.inputs()};rows=[]
    def add(label,template,count=1,metadata='validated',other=None):
        original=templates[template]['source']['result'];item=original['id']
        rows.append({'id':label,'template_id':template,'template_source':{'type':'minecraft:crafting_shapeless','ingredients':['minecraft:oak_planks'],'result':original},'recipe_id':'bendcraft:input_'+item.split(':')[1],'recipe_source':{'type':'minecraft:crafting_shapeless','ingredients':[item],'result':{'id':'minecraft:stone'}},'count':count,'metadata':metadata,'other':other})
    for label,template in [('allium','minecraft:suspicious_stew_from_allium'),('default_duration','bendcraft:duration_missing'),('negative_duration','bendcraft:duration_negative'),('minimum_duration','bendcraft:duration_minimum'),('duplicate_effects','bendcraft:duplicate_effects'),('ordered_effects','bendcraft:ordered_effects'),('reversed_effects','bendcraft:reversed_effects'),('plain_default','bendcraft:stew_default')]:add(label,template)
    add('absent_authority','bendcraft:duration_negative',metadata='none')
    add('different_component_authority','bendcraft:duration_negative',metadata='other',other='bendcraft:duration_missing')
    add('overfull_stew','bendcraft:duration_negative',count=2)
    add('zero_stew','bendcraft:duration_negative',count=0)
    add('zero_metadata_limit','bendcraft:duration_negative',metadata='zero')
    add('overlarge_metadata_limit','bendcraft:duration_negative',metadata='large')
    add('removed_effects_profile','bendcraft:remove_effects')
    add('non_stew_profile','bendcraft:glint_true')
    return rows

def extract():
    CACHE.mkdir(parents=True,exist_ok=True);rows=inputs();write_json(CACHE/'input.json',rows);source=CACHE/'CraftingRecipeInputsProbe.java';source.write_text(SOURCE)
    cp,provenance=verified_classpath();start=time.monotonic();result=subprocess.run([str(JAVA),'-Xmx512m','-Djava.awt.headless=true','--class-path',':'.join(map(str,cp)),str(source),str(CACHE/'input.json'),str(CACHE/'output.json')],capture_output=True,text=True,timeout=60)
    (CACHE/'process.log').write_text(result.stdout+result.stderr)
    if result.returncode:raise AssertionError((result.stdout+result.stderr)[-6000:])
    receipt={'pin':'26.3','source_sha256':C.P.sha(SOURCE.encode()),'inputs_sha256':C.P.sha(canonical(rows)),'cases':json.loads((CACHE/'output.json').read_text()),'provenance':provenance,'seconds':round(time.monotonic()-start,6),'scope':'Actual Recipe.DIRECT_CODEC, ItemStackTemplate assembly, modified input count, CraftingInput.of and ordinary ShapelessRecipe.matches; inventory admission is a separate validated-metadata boundary.'};write_json(OUTPUT,receipt);return receipt

if __name__=='__main__':
    receipt=extract();print(json.dumps({'cases':len(receipt['cases']),'seconds':receipt['seconds']}))
