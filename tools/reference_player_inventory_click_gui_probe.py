#!/usr/bin/env python3
"""Actual pinned default inventory key producer; recording dispatch only."""
from __future__ import annotations
import argparse,base64,json,os
from pathlib import Path
import reference_player_inventory_probe as P
import reference_player_inventory_click_probe as Swap
import reference_local_input_probe as LI
from reference_inventory import ROOT,canonical,write_json
FIXTURE='net.minecraft.fixture.PlayerInventoryKeyReceiverFixture'
OUTPUT=ROOT/'reference/player_inventory_click_gui.json'
METHODS={**Swap.METHODS,
 'net.minecraft.client.gui.screens.inventory.AbstractContainerScreen':{'<init>','keyPressed','checkHotbarKeyPressed','slotClicked'},
 'net.minecraft.client.gui.screens.inventory.InventoryScreen':{'<init>','keyPressed'},
 'net.minecraft.client.input.KeyEvent':{'<init>','key','keycode','shortcutKey','input','modifiers'},
 'net.minecraft.client.KeyMapping':{'matches','isDown'},
}

def inputs():
 rows=[{'id':'digit-'+str(k),'key':49+k,'mods':0,'hover':10,'carried':False} for k in range(9)]
 rows += [dict(id=name,key=key,mods=mods,hover=hover,carried=carried) for name,key,mods,hover,carried in [
  ('offhand',70,0,10,False),('digit-no-hover',49,0,-1,False),('offhand-no-hover',70,0,-1,False),
  ('digit-carried',49,0,10,True),('offhand-carried',70,0,10,True),
  ('digit-shift',49,1,10,False),('offhand-control',70,2,10,False),
  ('digit-result',49,0,0,False),('offhand-self',70,0,45,False)]]
 #26.3 observed physical defaults: keyboard1..9 =30..38, F=9. The
 # separate shortcut keycode carries printable ASCII, not binding identity.
 for row in rows:
  row['native_ascii']=row['key'];row['keycode']=row['key']
  row['key']=30+row['key']-49 if 49<=row['key']<=57 else 9
 return rows

SOURCE=Swap.SOURCE[:Swap.SOURCE.index(' public static void run(String ignored)')].replace(
 'public class PlayerInventoryClickReceiverFixture','public class PlayerInventoryKeyReceiverFixture')+r'''
 static class ObservedScreen extends net.minecraft.client.gui.screens.inventory.InventoryScreen {
  final List<Object> calls=new ArrayList<>();
  ObservedScreen(net.minecraft.world.entity.player.Player player){super(player);}
  protected void slotClicked(net.minecraft.world.inventory.Slot slot,int index,int button,net.minecraft.world.inventory.ContainerInput action){calls.add(Map.of("slot",index,"button",button,"action",action.name()));}
 }
 public static void run(String ignored)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();HolderLookup.Provider lookup=VanillaRegistries.createWorldLookup();
  java.io.StringWriter code=new java.io.StringWriter();java.io.StringWriter errors=new java.io.StringWriter();int status=java.util.spi.ToolProvider.findFirst("javap").orElseThrow().run(new java.io.PrintWriter(code),new java.io.PrintWriter(errors),"-c","-p","-classpath",System.getProperty("java.class.path"),"net.minecraft.client.KeyMapping","net.minecraft.client.input.KeyEvent","net.minecraft.client.gui.screens.inventory.AbstractContainerScreen");OUT.println("GUI_KEY_JAVAP:"+Base64.getEncoder().encodeToString(code.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8)));if(status!=0)throw new IllegalStateException(errors.toString());
  for(var pending:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup))pending.forEach((holder,components)->holder.bindComponents(components));
  for(String name:List.of("net.minecraft.world.entity.player.Abilities$Packed","net.minecraft.world.ContainerHelper","net.minecraft.world.inventory.Slot"))Class.forName(name,true,PlayerInventoryKeyReceiverFixture.class.getClassLoader());
  JsonArray cases=JsonParser.parseString(new String(Base64.getDecoder().decode(__INPUT__),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonArray();
  for(JsonElement element:cases){JsonObject in=element.getAsJsonObject();var context=new LocalInputReceiverFixture.Context(lookup,false);LocalPlayer player=context.player;
   player.getInventory().setItem(10,stack("minecraft:stone",17));player.inventoryMenu.setCarried(in.get("carried").getAsBoolean()?stack("minecraft:dirt",3):ItemStack.EMPTY);
   ObservedScreen screen=null;Map<String,Object> row=new TreeMap<>();row.put("id",in.get("id").getAsString());row.put("operation","gui-key");row.put("input",in);row.put("before",menuState(player));boolean ok=false;
   try{screen=new ObservedScreen(player);LocalInputReceiverFixture.seed(screen,"minecraft",context.mc);int hover=in.get("hover").getAsInt();LocalInputReceiverFixture.seed(screen,"hoveredSlot",hover<0?null:player.inventoryMenu.getSlot(hover));var key=new net.minecraft.client.input.KeyEvent(in.get("key").getAsInt(),in.get("keycode").getAsInt(),in.get("mods").getAsInt());row.put("hotbar_value",context.mc.options.keyHotbarSlots[0].getDefaultKey().getValue());row.put("offhand_value",context.mc.options.keySwapOffhand.getDefaultKey().getValue());row.put("event_input",key.input());row.put("event_shortcut",key.shortcutKey());row.put("hotbar_default",context.mc.options.keyHotbarSlots[0].getDefaultKey().getName());row.put("offhand_default",context.mc.options.keySwapOffhand.getDefaultKey().getName());row.put("hotbar_bound",context.mc.options.keyHotbarSlots[0].saveString());row.put("offhand_bound",context.mc.options.keySwapOffhand.saveString());row.put("hotbar_first_matches",context.mc.options.keyHotbarSlots[0].matches(key));row.put("offhand_matches",context.mc.options.keySwapOffhand.matches(key));row.put("consumed",screen.keyPressed(key));ok=true;}catch(Throwable error){row.put("error",failure(error));}
   row.put("ok",ok);row.put("calls",screen==null?List.of():screen.calls);row.put("after",menuState(player));output(row);
  }
 }
}
'''

def prepared():
 if P.sha(Path(LI.__file__).read_bytes())!=P.FROZEN_LI:raise ValueError('Normal player fixture changed')
 paths,provenance=P.verified_classpath();cases=inputs();sources=LI.receiver_sources({})
 # Constructor plumbing only: actual Screen retains Minecraft.font. No font
 # layout/render method or native window is invoked by these key producers.
 sources['net.minecraft.client.Minecraft']=sources['net.minecraft.client.Minecraft'].replace(
  'public Options options;','public Options options; public net.minecraft.client.gui.Font font;')
 sources[FIXTURE]=SOURCE.replace('__INPUT__',LI.java_string(base64.b64encode(canonical(cases)).decode()))
 payload={'sources':sources,'client_jar':str(P.CLIENT),'mode':'inventory-gui-key'}
 launcher=LI.RECEIVER_LAUNCHER.replace('net.minecraft.fixture.LocalInputReceiverFixture',FIXTURE,1)
 launcher=launcher.replace('Base64.getDecoder().decode(args[0])','Base64.getDecoder().decode('+LI.java_string(base64.b64encode(canonical(payload)).decode())+')',1)
 return {'cases':cases,'sources':sources,'launcher':launcher,'command':[str(P.JAVA),'-Xmx512m','--source','25','--class-path',os.pathsep.join(map(str,paths)),'/dev/stdin'],'provenance':provenance,'source_inventory':P.source_inventory(METHODS),'profile':'menu-click-gui-key','timeout_seconds':60}

def collect(mode):
 prep=prepared();run=P.observe(prep,'menu-click-gui-key-'+mode);rows=run['observations'];loaded=run['loaded_official_classes']
 for case,row in zip(prep['cases'],rows,strict=True):
  if row['input']!=case or not row['ok']:raise ValueError('GUI actual receiver failed; raw retained: '+row['id'])
 stable={'pin':'26.3','producer':P.pin(Path(__file__)),'observations':rows,'observations_sha256':P.sha(canonical(rows)),'inputs':prep['cases'],'source_inventory':prep['source_inventory'],'provenance':prep['provenance'],'loaded_official_classes':{'count':len(loaded),'all_verified_against_client_jar':True,'complete_map_sha256':P.sha(canonical(loaded)),'selected':{n:loaded[n] for n in METHODS if n in loaded}},'fixture_sources_sha256':{n:P.sha(s.encode()) for n,s in prep['sources'].items()},'boundary':'Actual InventoryScreen/AbstractContainerScreen keyPressed with default Options and actual hover Slot; overridden slotClicked records producer requests without inventory mutation, native rendering, OS input or server transport'}
 if mode=='extract':write_json(OUTPUT,{**stable,'raw_artifacts':[run['raw_artifact']],'execution':run['execution']})
 else:
  old=json.loads(OUTPUT.read_text())
  for k,v in stable.items():
   if old[k]!=v:raise ValueError('Fresh GUI key reproduction differs: '+k)
 try:os.killpg(run['execution']['pid'],0);absent=False
 except ProcessLookupError:absent=True
 receipt={'status':'actual-GUI-producer-observed' if mode=='extract' else 'exact-fresh-GUI-producer-reproduction','case_count':len(rows),'observations_sha256':stable['observations_sha256'],'loaded_official_classes':len(loaded),'all_official_hashes_verified':True,'process_group_absent':absent,'execution':run['execution'],'reference':P.pin(OUTPUT),'raw_artifact':run['raw_artifact']}
 write_json(ROOT/('evidence/player-inventory-click-gui-reference-'+mode+'.json'),receipt)
 print(json.dumps({k:receipt[k] for k in ['status','case_count','observations_sha256','loaded_official_classes','process_group_absent']}))

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--prepare',action='store_true');p.add_argument('--mode',choices=('extract','reproduce'),default='extract');a=p.parse_args()
 if a.prepare:
  x=prepared();print(json.dumps({'status':'prepared-not-executed','cases':len(x['cases']),'inputs_sha256':P.sha(canonical(x['cases'])),'bounds':{'jvm_mib':512,'seconds':60}}))
 else:collect(a.mode)
if __name__=='__main__':main()
