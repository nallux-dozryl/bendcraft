#!/usr/bin/env python3
"""Actual pinned26.3 ordinary recipe assembly and menu result PICKUP receivers."""
from __future__ import annotations
import argparse,base64,copy,json,os,zipfile
from pathlib import Path
import reference_player_inventory_probe as P
import reference_local_input_probe as LI
from reference_inventory import ROOT,canonical,write_json

FIXTURE='net.minecraft.fixture.PlayerCraftingAuthorityReceiverFixture'
OUTPUT=ROOT/'reference/player_crafting_authority.json'
METHODS={**P.CLOSE_METHODS,
 'net.minecraft.world.inventory.AbstractContainerMenu':{'clicked','doClick','getCarried','setCarried'},
 'net.minecraft.world.inventory.ResultSlot':{'remove','onTake','getRemainingItems','checkTakeAchievements'},
 'net.minecraft.world.inventory.CraftingMenu':{'<init>','slotsChanged'},
 'net.minecraft.world.inventory.TransientCraftingContainer':{'removeItem','setItem','asPositionedCraftInput'},
 'net.minecraft.world.item.crafting.CraftingRecipe':{'defaultCraftingReminder'},
 'net.minecraft.world.item.crafting.ShapedRecipe':{'matches','assemble'},
 'net.minecraft.world.item.crafting.ShapelessRecipe':{'matches','assemble'}}

def item(name,count=1):return {'item':'minecraft:'+name,'count':count}

def inputs():
 cases=[]
 with zipfile.ZipFile(P.CLIENT) as jar:
  stick=json.loads(jar.read('data/minecraft/recipe/stick.json'))
  cake=json.loads(jar.read('data/minecraft/recipe/cake.json'))
  bowl=json.loads(jar.read('data/minecraft/recipe/bowl.json'))
 def add(name,source,craft,carried=None,button=0,main=None,offhand=None,mode='SURVIVAL',width=2):
  cases.append({'id':name,'operation':'result_pickup','width':width,'height':width,'source':source,'craft':craft,'carried':carried,'button':button,'main':main or {},'offhand':offhand,'selected':7,'mode':mode})
 grid=[item('oak_planks',2),None,item('oak_planks',2),None]
 for button in (0,1):
  for carried,label in [(None,'empty'),(item('stick',60),'complete-room'),(item('stick',61),'partial-room'),(item('stick',64),'full'),(item('dirt',1),'different')]:
   add(f'stick-button{button}-{label}',stick,grid,carried,button)
 add('stick-offset-right',stick,[None,item('birch_planks',3),None,item('birch_planks',2)])
 add('stick-last-input',stick,[item('oak_planks'),None,item('oak_planks'),None])
 oversized=copy.deepcopy(stick);oversized['result']['count']=99
 add('strict-empty-99',oversized,grid)
 honey={'type':'minecraft:crafting_shapeless','ingredients':['minecraft:honey_bottle'],'result':{'id':'minecraft:stick','count':1}}
 full={str(n):item('dirt',64) for n in range(36)}
 for mode in ('SURVIVAL','CREATIVE'):
  for count in (1,2,16):
   add(f'honey-{count}-empty:{mode}',honey,[item('honey_bottle',count),None,None,None],mode=mode)
   add(f'honey-{count}-full:{mode}',honey,[item('honey_bottle',count),None,None,None],main=full,mode=mode)
  add('honey-selected-offhand-main:'+mode,honey,[None,None,None,item('honey_bottle',2)],main={'7':item('glass_bottle',63),'0':item('glass_bottle',60)},offhand=item('glass_bottle',62),mode=mode)
  add('honey-offhand-main:'+mode,honey,[item('honey_bottle',2),None,None,None],main={'0':item('glass_bottle',60)},offhand=item('glass_bottle',62),mode=mode)
 cake_grid=[item('milk_bucket'),item('milk_bucket'),item('milk_bucket'),item('sugar',2),item('egg',2),item('sugar',2),item('wheat',2),item('wheat',2),item('wheat',2)]
 add('cake-three-bucket-remainders',cake,cake_grid,width=3)
 add('cake-three-bucket-remainders-full',cake,cake_grid,main=full,width=3)
 add('bowl-left',bowl,[item('oak_planks'),None,item('birch_planks'),None,item('spruce_planks'),None,None,None,None],width=3)
 add('bowl-right',bowl,[item('oak_planks'),None,item('birch_planks'),None,item('spruce_planks'),None,None,None,None],button=1,width=3)
 return cases

SOURCE=P.JAVA_SOURCE[:P.JAVA_SOURCE.index(' public static void run(String ignored)')].replace('public class PlayerInventoryReceiverFixture','public class PlayerCraftingAuthorityReceiverFixture')+r'''
 static ItemStack inputStack(JsonElement e){return e==null||e.isJsonNull()?ItemStack.EMPTY:stack(e.getAsJsonObject().get("item").getAsString(),e.getAsJsonObject().get("count").getAsInt());}
 static Object snapshot(LocalPlayer p,net.minecraft.world.inventory.AbstractCraftingMenu menu,net.minecraft.world.inventory.CraftingContainer craft)throws Exception{
  Map<String,Object> m=new TreeMap<>();m.put("inventory",state(p));List<Object> equipment=new ArrayList<>();for(int n=36;n<43;n++)equipment.add(stackState(p.getInventory().getItem(n)));m.put("equipment",equipment);
  List<Object> inputs=new ArrayList<>();for(int n=0;n<craft.getContainerSize();n++)inputs.add(stackState(craft.getItem(n)));m.put("craft",inputs);m.put("carried",stackState(menu.getCarried()));m.put("result",stackState(menu.getSlot(0).getItem()));return m;
 }
 public static void run(String ignored)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();HolderLookup.Provider lookup=VanillaRegistries.createWorldLookup();
  for(var pending:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup))pending.forEach((holder,components)->holder.bindComponents(components));
  for(String name:List.of("net.minecraft.world.entity.player.Abilities$Packed","net.minecraft.world.ContainerHelper","net.minecraft.world.inventory.Slot","net.minecraft.util.Prediction"))Class.forName(name,true,PlayerCraftingAuthorityReceiverFixture.class.getClassLoader());
  java.util.Map<net.minecraft.tags.TagKey<Item>,java.util.List<Holder<Item>>> tags=new java.util.LinkedHashMap<>();
  for(var entry:JsonParser.parseString(new String(Base64.getDecoder().decode(__TAGS__),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonArray()){
   var tag=entry.getAsJsonObject();java.util.List<Holder<Item>> values=new java.util.ArrayList<>();for(var item:tag.getAsJsonArray("items"))values.add(BuiltInRegistries.ITEM.get(Identifier.parse(item.getAsString())).orElseThrow());
   tags.put(net.minecraft.tags.TagKey.create(net.minecraft.core.registries.Registries.ITEM,Identifier.parse(tag.get("id").getAsString())),values);
  }
  BuiltInRegistries.ITEM.prepareTagReload(new net.minecraft.tags.TagLoader.LoadResult<Item>(net.minecraft.core.registries.Registries.ITEM,tags)).apply();
  var ops=net.minecraft.resources.RegistryOps.create(com.mojang.serialization.JsonOps.INSTANCE,RegistryAccess.fromRegistryOfRegistries(BuiltInRegistries.REGISTRY));
  JsonArray cases=JsonParser.parseString(new String(Base64.getDecoder().decode(__INPUT__),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonArray();
  for(var entry:cases){var in=entry.getAsJsonObject();var context=new LocalInputReceiverFixture.Context(lookup,false);LocalPlayer p=context.player;var inventory=p.getInventory();
   for(var e:in.getAsJsonObject("main").entrySet())inventory.setItem(Integer.parseInt(e.getKey()),inputStack(e.getValue()));inventory.setItem(40,inputStack(in.get("offhand")));inventory.setSelectedSlot(in.get("selected").getAsInt());GameType.valueOf(in.get("mode").getAsString()).updatePlayerAbilities(p.getAbilities());
   int width=in.get("width").getAsInt();net.minecraft.world.inventory.AbstractCraftingMenu menu=width==2?p.inventoryMenu:new net.minecraft.world.inventory.CraftingMenu(7,inventory);
   var craft=(net.minecraft.world.inventory.CraftingContainer)LocalInputReceiverFixture.read(menu,"craftSlots");
   for(int n=0;n<craft.getContainerSize();n++)craft.setItem(n,inputStack(in.getAsJsonArray("craft").get(n)));menu.setCarried(inputStack(in.get("carried")));
   Map<String,Object> row=new TreeMap<>();row.put("id",in.get("id").getAsString());row.put("input",in);boolean ok=false;
   try{
    var recipe=(net.minecraft.world.item.crafting.CraftingRecipe)net.minecraft.world.item.crafting.Recipe.DIRECT_CODEC.parse(ops,in.get("source")).getOrThrow();
    var grid=craft.asCraftInput();row.put("matches",recipe.matches(grid,p.level()));ItemStack output=recipe.assemble(grid);
    ((net.minecraft.world.Container)LocalInputReceiverFixture.read(menu,"resultSlots")).setItem(0,output);row.put("assembled",stackState(output));row.put("before",snapshot(p,menu,craft));
    menu.clicked(0,in.get("button").getAsInt(),net.minecraft.world.inventory.ContainerInput.PICKUP,p);ok=true;
   }catch(Throwable error){row.put("error",failure(error));}
   row.put("ok",ok);row.put("after",snapshot(p,menu,craft));output(row);
  }
 }
}
'''

def prepared():
 paths,provenance=P.verified_classpath();cases=inputs();sources=LI.receiver_sources({})
 tags=json.loads((ROOT/'build/crafting-recipe-reference/catalog.json').read_text())['tags']
 sources['net.minecraft.client.tutorial.Tutorial']=sources['net.minecraft.client.tutorial.Tutorial'].replace(' public void onInput',' public void onInventoryAction(net.minecraft.world.item.ItemStack slot,net.minecraft.world.item.ItemStack carried,net.minecraft.world.inventory.ClickAction action){}\n public void onInput')
 sources[FIXTURE]=SOURCE.replace('__INPUT__',LI.java_string(base64.b64encode(canonical(cases)).decode())).replace('__TAGS__',LI.java_string(base64.b64encode(canonical(tags)).decode()))
 payload={'sources':sources,'client_jar':str(P.CLIENT),'mode':'player-crafting-authority'}
 launcher=LI.RECEIVER_LAUNCHER.replace('net.minecraft.fixture.LocalInputReceiverFixture',FIXTURE,1).replace('Base64.getDecoder().decode(args[0])','Base64.getDecoder().decode('+LI.java_string(base64.b64encode(canonical(payload)).decode())+')',1)
 return {'sources':sources,'cases':cases,'launcher':launcher,'command':[str(P.JAVA),'-Xmx512m','--source','25','--class-path',os.pathsep.join(map(str,paths)),'/dev/stdin'],'provenance':provenance,'source_inventory':P.source_inventory(METHODS),'profile':'menu-close','timeout_seconds':60}

def compact_input(value):
 result={key:item for key,item in value.items() if key!='source'}
 result['source_sha256']=P.sha(canonical(value['source']))
 return result

def collect(mode,raw_path=None):
 preparation=prepared()
 if raw_path:
  raw=json.loads(Path(raw_path).read_text())
  for key in ('sources','cases','command','source_inventory'):
   if raw[key]!=preparation[key]:raise ValueError('Raw observation source differs: '+key)
  if raw['returncode']!=0:raise ValueError('Raw JVM did not succeed')
  loaded=raw['loaded_official'][0]
  with zipfile.ZipFile(P.CLIENT) as jar:
   for name,digest in loaded.items():
    if digest!=P.sha(jar.read(name.replace('.','/')+'.class')):raise ValueError('Raw official class differs')
  run={'observations':raw['observations'],'loaded_official_classes':loaded,'raw_artifact':P.pin(Path(raw_path)),'execution':{'command':raw['command'],'pid':raw['pid'],'returncode':raw['returncode'],'elapsed_seconds':raw['elapsed_seconds'],'stdout_sha256':P.sha(raw['stdout'].encode()),'stderr_sha256':P.sha(raw['stderr'].encode())}}
 else:run=P.observe(preparation,'player-crafting-authority-'+mode)
 rows=copy.deepcopy(run['observations']);loaded=run['loaded_official_classes']
 for row in rows:row['input']=compact_input(row['input'])
 if any(not row['ok'] for row in rows):raise ValueError('Result receiver failure; raw retained')
 stable={'pin':'26.3','producer':P.pin(Path(__file__)),'inputs':[compact_input(value) for value in preparation['cases']],'observations':rows,'observations_sha256':P.sha(canonical(rows)),'source_inventory':preparation['source_inventory'],'provenance':preparation['provenance'],'fixture_sources_sha256':{name:P.sha(value.encode()) for name,value in preparation['sources'].items()},'launcher_sha256':P.sha(preparation['launcher'].encode()),'loaded_official_classes':{'count':len(loaded),'all_verified_against_client_jar':True,'complete_map_sha256':P.sha(canonical(loaded)),'selected':{name:loaded[name] for name in METHODS if name in loaded}},'boundary':'Official ordinary codec+assemble, actual InventoryMenu/CraftingMenu clicked PICKUP and ResultSlot.onTake; selected result manually installed because client prediction fixture has no server recipe synchronization. Actual ClientLevel remainder fallback; no server award or item-entity ownership parity.'}
 if mode=='extract':write_json(OUTPUT,{**stable,'execution':run['execution'],'raw_artifact':run['raw_artifact']})
 else:
  old=json.loads(OUTPUT.read_text())
  for key,value in stable.items():
   if old[key]!=value:raise ValueError('Fresh crafting authority receiver differs: '+key)
 write_json(ROOT/('evidence/player-crafting-authority-reference-'+mode+'.json'),{'status':'passed','cases':len(rows),'observations_sha256':stable['observations_sha256'],'execution':run['execution'],'reference':P.pin(OUTPUT),'raw_artifact':run['raw_artifact']})
 print(json.dumps({'status':'passed','cases':len(rows),'seconds':run['execution']['elapsed_seconds']}))

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--prepare',action='store_true');parser.add_argument('--mode',choices=('extract','reproduce'),default='extract');parser.add_argument('--from-raw');args=parser.parse_args()
 if args.prepare:
  p=prepared();print(json.dumps({'status':'prepared','cases':len(p['cases']),'inputs_sha256':P.sha(canonical(p['cases']))}))
 else:collect(args.mode,args.from_raw)
if __name__=='__main__':main()
