#!/usr/bin/env python3
"""Pinned recipe facts and actual Java receivers; no host crafting simulation.

Source recipe JSON stays in ignored build storage. Committed output records
observations/hashes, not the jar or its original data-pack resources.
"""
from __future__ import annotations
import argparse, collections, csv, hashlib, json, subprocess, zipfile
from pathlib import Path
from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_model_probe import CLIENT
from reference_player_inventory_probe import verified_classpath

CACHE = ROOT / 'build/crafting-recipe-reference'
OUTPUT = ROOT / 'reference/crafting_recipe_observations.json'
SOURCE = r'''import java.nio.file.*;
import java.io.*;
import java.util.*;
import com.google.gson.*;
import com.mojang.serialization.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;
import net.minecraft.core.registries.*;
import net.minecraft.data.registries.VanillaRegistries;
import net.minecraft.resources.*;
import net.minecraft.tags.TagKey;
import net.minecraft.tags.TagLoader;
import net.minecraft.world.item.*;
import net.minecraft.world.item.crafting.*;

class CraftingRecipeProbe {
  static final Gson JSON = new GsonBuilder().serializeNulls().create();
  static String id(Item item) { return BuiltInRegistries.ITEM.getKey(item).toString(); }
  static Object stack(ItemStack stack) {
    return stack.isEmpty()?null:Map.of("id",id(stack.getItem()),"count",stack.getCount());
  }
  static ItemStack stack(JsonElement value) {
    if(value.isJsonNull())return ItemStack.EMPTY;
    var object=value.getAsJsonObject();
    return new ItemStack(BuiltInRegistries.ITEM.getValue(Identifier.parse(object.get("id").getAsString())),object.get("count").getAsInt());
  }
  public static void main(String[] args)throws Exception {
    SharedConstants.tryDetectVersion();Bootstrap.bootStrap();
    var lookup=VanillaRegistries.createWorldLookup();
    for(var pending:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup))pending.forEach((holder,components)->holder.bindComponents(components));
    var input=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonObject();
    Map<TagKey<Item>,List<Holder<Item>>> tags=new LinkedHashMap<>();
    for(var entry:input.getAsJsonArray("tags")) {
      var tag=entry.getAsJsonObject();List<Holder<Item>> values=new ArrayList<>();
      for(var value:tag.getAsJsonArray("items"))values.add(BuiltInRegistries.ITEM.get(Identifier.parse(value.getAsString())).orElseThrow());
      tags.put(TagKey.create(Registries.ITEM,Identifier.parse(tag.get("id").getAsString())),values);
    }
    BuiltInRegistries.ITEM.prepareTagReload(new TagLoader.LoadResult<Item>(Registries.ITEM,tags)).apply();
    var ops=RegistryOps.create(JsonOps.INSTANCE,RegistryAccess.fromRegistryOfRegistries(BuiltInRegistries.REGISTRY));
    Map<String,CraftingRecipe> recipes=new LinkedHashMap<>();
    try(var out=new PrintWriter(Files.newBufferedWriter(Path.of(args[1])))) {
      for(Item item:BuiltInRegistries.ITEM) {
        var remainder=item.getCraftingRemainder();
        Map<String,Object> row=new TreeMap<>();row.put("kind","item");row.put("id",id(item));row.put("limit",item.getDefaultInstance().getMaxStackSize());row.put("remainder",remainder==null?null:stack(remainder.create()));
        out.println(JSON.toJson(row));
      }
      for(var entry:input.getAsJsonArray("recipes")) {
        var row=entry.getAsJsonObject();String id=row.get("id").getAsString();
        var decoded=Recipe.DIRECT_CODEC.parse(ops,row.get("source"));
        Map<String,Object> result=new TreeMap<>();result.put("kind","decode");result.put("id",id);
        if(decoded.result().isEmpty())result.put("error",decoded.error().orElseThrow().message());
        else {
          var recipe=decoded.result().orElseThrow();result.put("class",recipe.getClass().getName());
          if(recipe instanceof CraftingRecipe crafting)recipes.put(id,crafting);
          if(recipe instanceof ShapedRecipe shaped){result.put("width",shaped.getWidth());result.put("height",shaped.getHeight());}
        }
        out.println(JSON.toJson(result));
      }
      for(var entry:input.getAsJsonArray("decoder_queries")) {
        var row=entry.getAsJsonObject();Map<String,Object> result=new TreeMap<>();result.put("kind","decoder_query");result.put("id",row.get("id").getAsString());
        try {var decoded=Recipe.DIRECT_CODEC.parse(ops,row.get("source"));result.put("accepted",decoded.result().isPresent());
          if(decoded.error().isPresent())result.put("error",decoded.error().orElseThrow().message());
        }catch(RuntimeException exception){result.put("accepted",false);result.put("exception",exception.getClass().getName());result.put("error",String.valueOf(exception.getMessage()));}
        out.println(JSON.toJson(result));
      }
      for(var element:input.getAsJsonArray("queries")) {
        var query=element.getAsJsonObject();var raw=query.getAsJsonObject("grid");int width=raw.get("width").getAsInt(),height=raw.get("height").getAsInt();
        List<ItemStack> values=new ArrayList<>();for(var value:raw.getAsJsonArray("slots"))values.add(stack(value));
        var positioned=CraftingInput.ofPositioned(width,height,values);var grid=positioned.input();
        Map<String,Object> result=new TreeMap<>();result.put("kind","query");result.put("id",query.get("id").getAsString());
        result.put("trimmed",Map.of("width",grid.width(),"height",grid.height(),"left",positioned.left(),"top",positioned.top(),"ingredient_count",grid.ingredientCount()));
        List<String> matches=new ArrayList<>();Object output=null;List<Object> consumption=new ArrayList<>();
        // The production RecipeMap receiver validates order/collisions.
        var registry=new MappedRegistry<Recipe<?>>(Registries.RECIPE,Lifecycle.stable());
        for(var candidate:query.getAsJsonArray("recipes")) {
          String id=candidate.getAsString();registry.register(ResourceKey.create(Registries.RECIPE,Identifier.parse(id)),recipes.get(id),RegistrationInfo.BUILT_IN);
        }
        registry.freeze();var map=RecipeMap.create(registry);
        for(var holder:map.getRecipesFor(RecipeType.CRAFTING,grid,null).toList())matches.add(holder.id().identifier().toString());
        if(!matches.isEmpty()) {
          var recipe=recipes.get(matches.getFirst());output=stack(recipe.assemble(grid));
          var remainders=recipe.getRemainingItems(grid);
          for(int n=0;n<grid.size();n++)if(!grid.getItem(n).isEmpty()) {
            int original=(n/grid.width()+positioned.top())*width+n%grid.width()+positioned.left();
            Map<String,Object> step=new TreeMap<>();step.put("slot",original);step.put("count",1);step.put("remainder",stack(remainders.get(n)));consumption.add(step);
          }
        }
        result.put("matches",matches);result.put("output",output);result.put("consumption",consumption);out.println(JSON.toJson(result));
      }
      if(out.checkError())throw new IOException("oracle output failed");
    }
  }
}'''

def sha(data): return hashlib.sha256(data).hexdigest()

def resources():
    release=json.loads((ROOT/'reference/release.json').read_text())
    assert fingerprint(CLIENT)['sha256']==release['client']['sha256']
    recipes, raw_tags, hashes={}, {}, {}
    with zipfile.ZipFile(CLIENT) as jar:
        for name in sorted(jar.namelist()):
            if name.startswith('data/minecraft/recipe/') and name.endswith('.json'):
                raw=jar.read(name);recipes['minecraft:'+name[len('data/minecraft/recipe/'):-5]]=json.loads(raw);hashes[name]=sha(raw)
            elif name.startswith('data/minecraft/tags/item/') and name.endswith('.json'):
                raw=jar.read(name);raw_tags['minecraft:'+name[len('data/minecraft/tags/item/'):-5]]=json.loads(raw);hashes[name]=sha(raw)
    resolved={}
    def resolve(name,active=()):
        if name in resolved:return resolved[name]
        if name in active:raise ValueError('cyclic item tag')
        values=set()
        for value in raw_tags[name]['values']:
            if isinstance(value,dict):value=value['id']
            if value.startswith('#'):values.update(resolve(value[1:],active+(name,)))
            else:values.add(value if ':' in value else 'minecraft:'+value)
        resolved[name]=sorted(values);return resolved[name]
    for name in raw_tags:resolve(name)
    return recipes,resolved,hashes

def stack(id,count=1): return {'id':id,'count':count}

def inputs():
    recipes,tags,hashes=resources()
    ordinary={id:r for id,r in recipes.items() if r['type'] in ('minecraft:crafting_shaped','minecraft:crafting_shapeless')}
    custom={
      'bendcraft:overlap':{'type':'minecraft:crafting_shapeless','ingredients':[['minecraft:oak_planks','minecraft:birch_planks'],'minecraft:oak_planks'],'result':{'id':'minecraft:stick','count':2}},
      'bendcraft:collision_z':{'type':'minecraft:crafting_shapeless','ingredients':['minecraft:oak_planks'],'result':{'id':'minecraft:stick'}},
      'bendcraft:collision_a':{'type':'minecraft:crafting_shapeless','ingredients':['minecraft:oak_planks'],'result':{'id':'minecraft:crafting_table'}},
      'bendcraft:padded':{'type':'minecraft:crafting_shaped','key':{'X':'minecraft:oak_planks'},'pattern':['   ',' X ','   '],'result':{'id':'minecraft:stick'}},
      'bendcraft:large_result':{'type':'minecraft:crafting_shapeless','ingredients':['minecraft:oak_planks'],'result':{'id':'minecraft:stick','count':99}},
    }
    selected={**recipes,**custom};queries=[]
    def add(id,ids,width,height,values,category):queries.append({'id':id,'recipes':ids,'grid':{'width':width,'height':height,'slots':values},'category':category})
    def select(ingredient):
        if isinstance(ingredient,list):return ingredient[0]
        return tags[ingredient[1:]][0] if ingredient.startswith('#') else ingredient
    for id,recipe in ordinary.items():
        if 'components' in recipe['result']:continue
        if recipe['type']=='minecraft:crafting_shaped':
            rows=recipe['pattern'];width=len(rows[0]);height=len(rows)
            values=[None if char==' ' else stack(select(recipe['key'][char])) for row in rows for char in row]
        else:
            width=3;height=3;values=[stack(select(ingredient)) for ingredient in recipe['ingredients']];values += [None]*(9-len(values))
        add(id+':ordinary',[id],width,height,values,'all_plain_ordinary')
        missing=list(values);missing[next(n for n,v in enumerate(missing) if v)]=None
        add(id+':missing',[id],width,height,missing,'missing_occupied_slot')
    add('overlap-forward',['bendcraft:overlap'],2,2,[stack('minecraft:oak_planks'),stack('minecraft:birch_planks'),None,None],'non_greedy')
    add('overlap-reversed',['bendcraft:overlap'],2,2,[stack('minecraft:birch_planks'),None,None,stack('minecraft:oak_planks')],'non_greedy')
    add('overlap-single-stack',['bendcraft:overlap'],2,2,[stack('minecraft:oak_planks',2),None,None,None],'one_unit_per_slot')
    for ids in [['bendcraft:collision_z','bendcraft:collision_a'],['bendcraft:collision_a','bendcraft:collision_z']]:
        add('collision-'+ids[0],ids,2,2,[None,None,None,stack('minecraft:oak_planks')],'registry_order_collision')
    for slot in range(4):
        values=[None]*4;values[slot]=stack('minecraft:oak_planks',64)
        add('padding-offset-'+str(slot),['bendcraft:padded'],2,2,values,'source_padding_trim_grid_offset')
    add('empty-grid',['bendcraft:padded','bendcraft:collision_z'],2,2,[None]*4,'empty_grid')
    add('extra-occupied',['bendcraft:padded'],2,2,[stack('minecraft:oak_planks'),stack('minecraft:dirt'),None,None],'outside_pattern_occupied')
    axe=[stack('minecraft:oak_planks'),stack('minecraft:oak_planks'),None,stack('minecraft:oak_planks'),stack('minecraft:stick'),None,None,stack('minecraft:stick'),None]
    add('axe-unmirrored',['minecraft:wooden_axe'],3,3,axe,'asymmetric_shape')
    mirror=[axe[row*3+col] for row in range(3) for col in [2,1,0]]
    add('axe-mirrored',['minecraft:wooden_axe'],3,3,mirror,'asymmetric_shape_mirrored')
    add('sticks-offset',['minecraft:stick'],2,2,[None,stack('minecraft:birch_planks',64),None,stack('minecraft:oak_planks',7)],'mixed_tag_stacks_count')
    add('honey-remainders',['minecraft:honey_block'],2,2,[stack('minecraft:honey_bottle')]*4,'crafting_remainders')
    add('large-result-count',['bendcraft:large_result'],2,2,[stack('minecraft:oak_planks'),None,None,None],'result_count_above_item_stack_limit')
    # These own-created inputs exercise the actual version's ingredient/pattern
    # codec. Acceptance is observed in Java rather than inferred by Python.
    base={'type':'minecraft:crafting_shaped','key':{'X':'minecraft:oak_planks'},'pattern':['X'],'result':{'id':'minecraft:stick'}}
    decoder=[]
    import copy
    def altered(label,**changes):
        source=copy.deepcopy(base);source.update(changes);decoder.append({'id':'bendcraft:'+label,'source':source})
    altered('zero_count',result={'id':'minecraft:stick','count':0})
    altered('hundred_count',result={'id':'minecraft:stick','count':100})
    altered('air_result',result={'id':'minecraft:air'})
    altered('empty_pattern',pattern=[' '])
    altered('unequal_rows',pattern=['X','XX'])
    altered('wide_pattern',pattern=['XXXX'])
    altered('tall_pattern',pattern=['X']*4)
    altered('undefined_key',pattern=['Y'])
    altered('unused_key',key={'X':'minecraft:oak_planks','Y':'minecraft:birch_planks'})
    altered('space_key',key={' ':'minecraft:oak_planks'},pattern=[' '])
    altered('empty_alternatives',key={'X':[]})
    altered('air_ingredient',key={'X':'minecraft:air'})
    altered('tag_in_alternatives',key={'X':['#minecraft:planks','minecraft:stone']})
    altered('old_ingredient_object',key={'X':{'item':'minecraft:oak_planks'}})
    altered('empty_shapeless',type='minecraft:crafting_shapeless',ingredients=[])
    altered('ten_shapeless',type='minecraft:crafting_shapeless',ingredients=['minecraft:oak_planks']*10)
    altered('valid_alternatives',key={'X':['minecraft:oak_planks','minecraft:birch_planks']})
    altered('unqualified_ids',key={'X':'oak_planks'},result={'id':'stick'})
    altered('valid_large_result',result={'id':'minecraft:stick','count':99})
    return {'recipes':[{'id':id,'source':r} for id,r in selected.items()], 'tags':[{'id':id,'items':values} for id,values in tags.items()], 'queries':queries,'decoder_queries':decoder},hashes

def extract(timeout=90):
    CACHE.mkdir(parents=True,exist_ok=True)
    data,hashes=inputs();write_json(CACHE/'input.json',data)
    source=CACHE/'CraftingRecipeProbe.java';source.write_text(SOURCE)
    cp,provenance=verified_classpath();output=CACHE/'output.jsonl'
    started=__import__('time').monotonic()
    command=[str(JAVA),'-Xmx768m','-Djava.awt.headless=true','--class-path',':'.join(map(str,cp)),str(source),str(CACHE/'input.json'),str(output)]
    result=subprocess.run(command,capture_output=True,text=True,timeout=timeout)
    (CACHE/'process.log').write_text(result.stdout+result.stderr)
    if result.returncode:raise RuntimeError((result.stdout+result.stderr)[-6000:])
    rows=[json.loads(line) for line in output.read_text().splitlines()]
    items=[{k:v for k,v in row.items() if k!='kind'} for row in rows if row['kind']=='item']
    decoded=[row for row in rows if row['kind']=='decode'];observations=[row for row in rows if row['kind']=='query'];decoder_observations=[row for row in rows if row['kind']=='decoder_query']
    by_id={row['id']:row['source'] for row in data['recipes']}
    errors=[row for row in decoded if 'error' in row and by_id[row['id']]['type'] in ('minecraft:crafting_shaped','minecraft:crafting_shapeless')]
    if errors:raise ValueError('actual Java ordinary recipe decoding failures: '+str(errors[:3]))
    bundle={'items':items,'tags':data['tags'],'recipes':data['recipes']};write_json(CACHE/'catalog.json',bundle)
    ordinary=[row for row in data['recipes'] if row['source']['type'] in ('minecraft:crafting_shaped','minecraft:crafting_shapeless') and not row['id'].startswith('bendcraft:')]
    plain=sum('components' not in row['source']['result'] for row in ordinary)
    reference={'schema_version':1,'pin':'26.3','status':'actual-java-receivers-observed','source_sha256':sha(SOURCE.encode()),'input_sha256':sha(canonical(data)),
      'resource_hashes_sha256':sha(canonical(hashes)),'provenance':provenance,'ordinary_recipe_count':len(ordinary),'plain_ordinary_recipe_count':plain,
      'decoded':decoded,'queries':data['queries'],'observations':observations,'observations_sha256':sha(canonical(observations)),
      'unsupported_java_decoder_errors':[row for row in decoded if 'error' in row],
      'decoder_queries':data['decoder_queries'],'decoder_observations':decoder_observations,'decoder_observations_sha256':sha(canonical(decoder_observations)),
      'items_sha256':sha(canonical(items)),'tags_sha256':sha(canonical(data['tags'])),'catalog_sha256':fingerprint(CACHE/'catalog.json')['sha256'],
      'seconds':round(__import__('time').monotonic()-started,6),'classes':['Recipe.DIRECT_CODEC','CraftingInput.ofPositioned','ShapedRecipe.matches','ShapelessRecipe.matches','RecipeMap.create/getRecipesFor','Recipe.assemble','CraftingRecipe.getRemainingItems'],
      'boundary':'Ordinary shaped/shapeless and supplied registry ordering. Full datapack loading, special subclasses, patched outputs/components, player consumption/award and recipe-book logic remain separate.'}
    write_json(OUTPUT,reference)
    inventory={'schema_version':1,'pin':'26.3','client_sha256':fingerprint(CLIENT)['sha256'],'recipe_count':2042,'types':dict(collections.Counter(r['type'] for r in resources()[0].values())),
      'resource_hashes_sha256':reference['resource_hashes_sha256'],'plain_ordinary_recipes':plain,'patched_ordinary_results':[r['id'] for r in ordinary if 'components' in r['source']['result']],
      'tag_count':len(data['tags']),'item_count':len(items),'source_resources_committed':False}
    write_json(ROOT/'reference/crafting_recipe_inventory.json',inventory)
    return reference

def verify():
    value=json.loads(OUTPUT.read_text());data,hashes=inputs()
    assert value['pin']=='26.3' and value['source_sha256']==sha(SOURCE.encode())
    assert value['input_sha256']==sha(canonical(data)) and value['resource_hashes_sha256']==sha(canonical(hashes))
    assert value['observations_sha256']==sha(canonical(value['observations']))
    assert fingerprint(CACHE/'catalog.json')['sha256']==value['catalog_sha256']
    return value

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--extract',action='store_true');parser.add_argument('--verify',action='store_true');args=parser.parse_args()
    value=extract() if args.extract else verify()
    print(json.dumps({'status':value['status'],'recipes':len(value['decoded']),'queries':len(value['observations']),'seconds':value['seconds']}))
