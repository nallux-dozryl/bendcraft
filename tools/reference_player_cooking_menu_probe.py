#!/usr/bin/env python3
"""Pinned actual furnace-menu slot receivers; host code only records observations."""
from __future__ import annotations
import argparse, base64, json, os
from pathlib import Path
import reference_player_inventory_probe as P
import reference_player_inventory_click_probe as Swap
import reference_local_input_probe as LI
from reference_inventory import ROOT, canonical, write_json
FIXTURE='net.minecraft.fixture.PlayerCookingMenuReceiverFixture'
OUTPUT=ROOT/'reference/player_cooking_menu.json'
METHODS={**Swap.METHODS,
 'net.minecraft.world.inventory.AbstractFurnaceMenu':{'<init>','quickMoveStack','canSmelt','isFuel','stillValid'},
 'net.minecraft.world.inventory.FurnaceMenu':{'<init>'},
 'net.minecraft.world.inventory.FurnaceFuelSlot':{'mayPlace','getMaxStackSize'},
 'net.minecraft.world.inventory.FurnaceResultSlot':{'remove','onTake','onQuickCraft','checkTakeAchievements'},
 'net.minecraft.world.Container':{'stillValidBlockEntity'},
 'net.minecraft.world.entity.player.Player':{'isWithinBlockInteractionRange','blockInteractionRange'}}
def item(name,count=1):return dict(item='minecraft:'+name,count=count)
def inputs():
 rows=[]
 def add(id,index,button=0,action='PICKUP',furnace=None,main=None,carried=None):
  rows.append(dict(id=id,index=index,button=button,action=action,furnace=furnace or [None]*3,
   main=main or {},carried=carried,mode='SURVIVAL'))
 add('input-left-take',0,furnace=[item('cobblestone',17),None,None])
 add('input-right-take',0,1,furnace=[item('cobblestone',17),None,None])
 add('input-right-put',0,1,carried=item('cobblestone',17))
 add('input-left-merge',0,furnace=[item('cobblestone',63),None,None],carried=item('cobblestone',17))
 add('input-exchange',0,furnace=[item('cobblestone',17),None,None],carried=item('dirt',4))
 add('fuel-left-take',1,furnace=[None,item('coal',17),None])
 add('fuel-right-take',1,1,furnace=[None,item('coal',17),None])
 add('fuel-right-put',1,1,carried=item('coal',17))
 add('fuel-nonfuel-refuse',1,carried=item('dirt',4))
 add('fuel-empty-bucket-limit',1,carried=item('bucket',16))
 add('output-left-take',2,furnace=[None,None,item('stone',17)])
 add('output-right-take',2,1,furnace=[None,None,item('stone',17)])
 add('output-compatible-carried',2,furnace=[None,None,item('stone',17)],carried=item('stone',63))
 add('output-different-carried',2,furnace=[None,None,item('stone',17)],carried=item('dirt',4))
 add('output-empty-put-refuse',2,carried=item('stone',17))
 add('quick-output-reverse',2,action='QUICK_MOVE',furnace=[None,None,item('stone',17)])
 add('quick-output-merge-before-empty',2,action='QUICK_MOVE',furnace=[None,None,item('stone',17)],main={'0':item('stone',63)})
 add('quick-input-forward',0,action='QUICK_MOVE',furnace=[item('cobblestone',17),None,None])
 add('quick-fuel-forward',1,action='QUICK_MOVE',furnace=[None,item('coal',17),None])
 add('quick-main-smelt',3,action='QUICK_MOVE',main={'9':item('cobblestone',17)})
 add('quick-main-fuel',3,action='QUICK_MOVE',main={'9':item('coal',17)})
 add('quick-main-other-hotbar',3,action='QUICK_MOVE',main={'9':item('dirt',17)})
 add('quick-hotbar-other-main',30,action='QUICK_MOVE',main={'0':item('dirt',17)})
 add('quick-blocked-smelt-retains',3,action='QUICK_MOVE',furnace=[item('cobblestone',64),None,None],main={'9':item('cobblestone',17)})
 for mode in ('CREATIVE','ADVENTURE'):
  add('mode-output-'+mode.lower(),2,1,furnace=[None,None,item('stone',17)]);rows[-1]['mode']=mode
 return rows
SOURCE=Swap.SOURCE[:Swap.SOURCE.index(' public static void run(String ignored)')].replace('public class PlayerInventoryClickReceiverFixture','public class PlayerCookingMenuReceiverFixture')+r'''
 static Object observed(LocalPlayer player,net.minecraft.world.inventory.AbstractContainerMenu menu,net.minecraft.world.Container furnace)throws Exception{
  Map<String,Object> out=new TreeMap<>();out.put("player",menuState(player));out.put("furnace",List.of(stackState(furnace.getItem(0)),stackState(furnace.getItem(1)),stackState(furnace.getItem(2))));out.put("carried",stackState(menu.getCarried()));return out;
 }
 public static void run(String ignored)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();HolderLookup.Provider lookup=VanillaRegistries.createWorldLookup();
  for(var pending:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup))pending.forEach((holder,components)->holder.bindComponents(components));
  for(String name:List.of("net.minecraft.world.entity.player.Abilities$Packed","net.minecraft.world.ContainerHelper","net.minecraft.world.inventory.Slot"))Class.forName(name,true,PlayerCookingMenuReceiverFixture.class.getClassLoader());
  java.io.StringWriter code=new java.io.StringWriter(),errors=new java.io.StringWriter();int status=java.util.spi.ToolProvider.findFirst("javap").orElseThrow().run(new java.io.PrintWriter(code),new java.io.PrintWriter(errors),"-c","-p","-classpath",System.getProperty("java.class.path"),"net.minecraft.world.inventory.AbstractFurnaceMenu","net.minecraft.world.inventory.FurnaceResultSlot","net.minecraft.world.inventory.FurnaceFuelSlot","net.minecraft.world.Container","net.minecraft.world.entity.player.Player");OUT.println("COOKING_MENU_JAVAP:"+Base64.getEncoder().encodeToString(code.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8)));if(status!=0)throw new IllegalStateException(errors.toString());
  JsonArray cases=JsonParser.parseString(new String(Base64.getDecoder().decode(__INPUT__),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonArray();
  for(JsonElement element:cases){JsonObject in=element.getAsJsonObject();var context=new LocalInputReceiverFixture.Context(lookup,false);LocalPlayer player=context.player;GameType.valueOf(in.get("mode").getAsString()).updatePlayerAbilities(player.getAbilities());
   for(var pair:in.getAsJsonObject("main").entrySet())player.getInventory().setItem(Integer.parseInt(pair.getKey()),inputStack(pair.getValue()));
   player.getInventory().setItem(40,stack("minecraft:shield",1));player.getInventory().setItem(41,stack("minecraft:wolf_armor",1));player.getInventory().setItem(42,stack("minecraft:saddle",1));
   var furnace=new net.minecraft.world.SimpleContainer(3);for(int n=0;n<3;n++)furnace.setItem(n,inputStack(in.getAsJsonArray("furnace").get(n)));
   var menu=new net.minecraft.world.inventory.FurnaceMenu(5,player.getInventory(),furnace,new net.minecraft.world.inventory.SimpleContainerData(4));menu.setCarried(inputStack(in.get("carried")));
   Map<String,Object> row=new TreeMap<>();row.put("id",in.get("id").getAsString());row.put("input",in);row.put("before",observed(player,menu,furnace));boolean ok=false;
   try{menu.clicked(in.get("index").getAsInt(),in.get("button").getAsInt(),net.minecraft.world.inventory.ContainerInput.valueOf(in.get("action").getAsString()),player);ok=true;}catch(Throwable error){row.put("error",failure(error));}
   row.put("ok",ok);row.put("after",observed(player,menu,furnace));List<Object> slots=new ArrayList<>();for(var slot:menu.slots)slots.add(Map.of("menu",slot.index,"container",slot.getContainerSlot(),"x",slot.x,"y",slot.y));row.put("topology",slots);
   List<Object> range=new ArrayList<>();for(double x:new double[]{0.5,8.5,9.5,9.499999,9.500001}){player.setPos(x,-0.62,0.5);range.add(Map.of("x",x,"eye",player.getEyeY(),"range",player.blockInteractionRange(),"accepted",player.isWithinBlockInteractionRange(net.minecraft.core.BlockPos.ZERO,4.0)));}row.put("range",range);output(row);
  }
 }
}
'''
def prepared():
 if P.sha(Path(LI.__file__).read_bytes())!=P.FROZEN_LI:raise ValueError('Normal player fixture changed')
 cp,provenance=P.verified_classpath();cases=inputs();sources=LI.receiver_sources({})
 # Only the external recipe-access service is supplied. Actual property-set,
 # menu, slots, click routing and normal player constructors remain official.
 fixture=sources['net.minecraft.fixture.LocalInputReceiverFixture']
 fixture=fixture.replace('void hit(String name){',r'''public net.minecraft.world.item.crafting.RecipeAccess recipeAccess(){return new net.minecraft.world.item.crafting.RecipeAccess(){public net.minecraft.world.item.crafting.RecipePropertySet propertySet(net.minecraft.resources.ResourceKey<net.minecraft.world.item.crafting.RecipePropertySet> key){return net.minecraft.world.item.crafting.RecipePropertySet.create(java.util.List.of(net.minecraft.world.item.crafting.Ingredient.of(net.minecraft.world.item.Items.COBBLESTONE)));}public net.minecraft.world.item.crafting.SelectableRecipe.SingleInputSet<net.minecraft.world.item.crafting.StonecutterRecipe> stonecutterRecipes(){throw new UnsupportedOperationException("fixture has no stonecutter");}};} void hit(String name){''')
 sources['net.minecraft.fixture.LocalInputReceiverFixture']=fixture
 sources['net.minecraft.client.tutorial.Tutorial']=sources['net.minecraft.client.tutorial.Tutorial'].replace('public class Tutorial {','public class Tutorial { public void onInventoryAction(net.minecraft.world.item.ItemStack a,net.minecraft.world.item.ItemStack b,net.minecraft.world.inventory.ClickAction action){}')
 sources[FIXTURE]=SOURCE.replace('__INPUT__',LI.java_string(base64.b64encode(canonical(cases)).decode()))
 payload={'sources':sources,'client_jar':str(P.CLIENT),'mode':'player-cooking-menu'}
 launcher=LI.RECEIVER_LAUNCHER.replace('net.minecraft.fixture.LocalInputReceiverFixture',FIXTURE,1).replace('Base64.getDecoder().decode(args[0])','Base64.getDecoder().decode('+LI.java_string(base64.b64encode(canonical(payload)).decode())+')',1)
 return dict(cases=cases,sources=sources,launcher=launcher,command=[str(P.JAVA),'-Xmx512m','--source','25','--class-path',os.pathsep.join(map(str,cp)),'/dev/stdin'],provenance=provenance,source_inventory=P.source_inventory(METHODS),timeout_seconds=60)
def collect(mode):
 prep=prepared();run=P.observe(prep,'player-cooking-menu-'+mode);rows=run['observations'];loaded=run['loaded_official_classes']
 for case,row in zip(prep['cases'],rows,strict=True):
  if row['input']!=case or not row['ok']:raise ValueError('Actual menu receiver failed: '+row['id'])
 stable=dict(pin='26.3',inputs=prep['cases'],observations=rows,observations_sha256=P.sha(canonical(rows)),source_inventory=prep['source_inventory'],provenance=prep['provenance'],fixture_sources_sha256={n:P.sha(s.encode()) for n,s in prep['sources'].items()},loaded_official_classes=dict(count=len(loaded),all_verified_against_client_jar=True,complete_map_sha256=P.sha(canonical(loaded)),selected={n:loaded[n] for n in METHODS if n in loaded}),boundary='Untouched FurnaceMenu/AbstractContainerMenu/FuelSlot/ResultSlot on normally constructed LocalPlayer; three-slot SimpleContainer and one explicit cobblestone recipe property set are fixture services. ServerPlayer recipe/XP award, real furnace clocks, native window and OS input are not inferred.')
 if mode=='extract':write_json(OUTPUT,{**stable,'raw_artifact':run['raw_artifact'],'execution':run['execution']})
 else:
  old=json.loads(OUTPUT.read_text())
  for k,v in stable.items():
   if old[k]!=v:raise ValueError('Fresh menu receiver differs: '+k)
 try:os.killpg(run['execution']['pid'],0);absent=False
 except ProcessLookupError:absent=True
 receipt=dict(status='actual-menu-receiver-pass',cases=len(rows),reference=P.pin(OUTPUT),raw_artifact=run['raw_artifact'],execution=run['execution'],process_group_absent=absent)
 write_json(ROOT/('evidence/player-cooking-menu-reference-'+mode+'.json'),receipt);print(json.dumps(receipt))
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--prepare',action='store_true');p.add_argument('--mode',choices=('extract','reproduce'),default='extract');a=p.parse_args()
 if a.prepare:
  x=prepared();print(json.dumps(dict(status='prepared',cases=len(x['cases']),heap_mib=512,seconds=60)))
 else:collect(a.mode)
if __name__=='__main__':main()
