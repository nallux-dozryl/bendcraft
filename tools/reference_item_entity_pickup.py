#!/usr/bin/env python3
"""Observe pinned ItemEntity.playerTouch and Inventory.add, without reimplementing them."""
from __future__ import annotations
import json,os,subprocess,hashlib,time
from pathlib import Path
from reference_model_probe import verified_client_classpath,JAVA
ROOT=Path(__file__).resolve().parents[1];WORK=ROOT/'build/item-entity-pickup-reference'
SOURCE=r'''import java.util.*;import java.nio.file.*;import java.lang.reflect.*;import com.google.gson.*;import com.mojang.serialization.*;import sun.misc.Unsafe;
import net.minecraft.SharedConstants;import net.minecraft.server.Bootstrap;import net.minecraft.core.*;import net.minecraft.core.registries.*;import net.minecraft.core.component.*;import net.minecraft.data.registries.VanillaRegistries;import net.minecraft.resources.*;import net.minecraft.server.level.*;import net.minecraft.world.level.*;import net.minecraft.world.item.*;import net.minecraft.world.entity.*;import net.minecraft.world.entity.item.*;import net.minecraft.world.entity.player.*;import net.minecraft.stats.*;import net.minecraft.util.*;
class ItemEntityPickupReference {
 static Gson JSON=new GsonBuilder().serializeNulls().create();static RegistryOps<JsonElement> OPS;static Unsafe U;static UUID PLAYER=UUID.fromString("11112222-3333-4444-5555-666677778888");
 static void set(Object o,String name,Object value)throws Exception{Class<?> c=o.getClass();while(c!=null){try{Field f=c.getDeclaredField(name);f.setAccessible(true);f.set(o,value);return;}catch(NoSuchFieldException e){c=c.getSuperclass();}}throw new NoSuchFieldException(name);}
 static Object get(Object o,String name)throws Exception{Class<?> c=o.getClass();while(c!=null){try{Field f=c.getDeclaredField(name);f.setAccessible(true);return f.get(o);}catch(NoSuchFieldException e){c=c.getSuperclass();}}throw new NoSuchFieldException(name);}
 static class World extends ServerLevel {RandomSource rng;boolean client;int cursor;private World(){super(null,null,null,null,Level.OVERWORLD,null,false,0,List.of(),false);}public boolean isClientSide(){return client;}public RandomSource getRandom(){return rng;}public int getNextEntityId(){return ++cursor;}}
 static class ObservedPlayer extends Player {List<Object> events;private ObservedPlayer(){super(null,null);}public GameType gameMode(){return getAbilities().instabuild?GameType.CREATIVE:GameType.SURVIVAL;}
  public void take(Entity e,int count){events.add(Map.of("kind","take","count",count,"removed_at_take",e.isRemoved()));}
  public void awardStat(Stat<?> stat,int count){events.add(Map.of("kind","stat","count",count,"id",BuiltInRegistries.ITEM.getKey((Item)stat.getValue()).toString()));}
  public void onItemPickup(ItemEntity e){events.add(Map.of("kind","on_item_pickup","item",stack(e.getItem())));}
 }
 static ItemStack item(JsonElement raw){if(raw==null||raw.isJsonNull())return ItemStack.EMPTY;var v=raw.getAsJsonObject();var s=new ItemStack(BuiltInRegistries.ITEM.getValue(Identifier.parse(v.get("id").getAsString())),1);if(v.has("components"))s.applyComponents(DataComponentPatch.CODEC.parse(OPS,v.get("components")).result().orElseThrow());s.setCount(v.get("count").getAsInt());return s;}
 static Object stack(ItemStack s){if(s.isEmpty())return null;return Map.of("id",BuiltInRegistries.ITEM.getKey(s.getItem()).toString(),"count",Integer.toUnsignedLong(s.getCount()),"components",DataComponentMap.CODEC.encodeStart(OPS,s.getComponents()).result().orElseThrow());}
 static Object inventory(Inventory inv){List<Object> out=new ArrayList<>();for(int i=0;i<43;i++)out.add(stack(inv.getItem(i)));return out;}
 static Object poptimes(Inventory inv){List<Integer> out=new ArrayList<>();for(int i=0;i<43;i++)out.add(inv.getItem(i).getPopTime());return out;}
 public static void main(String[] args){try{run(args);}catch(Throwable t){t.printStackTrace(new java.io.PrintStream(new java.io.FileOutputStream(java.io.FileDescriptor.err)));System.exit(1);}}
 static void run(String[] args)throws Exception{SharedConstants.tryDetectVersion();Bootstrap.bootStrap();var lookup=VanillaRegistries.createWorldLookup();for(var pending:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup))pending.forEach((holder,components)->holder.bindComponents(components));OPS=RegistryOps.create(JsonOps.INSTANCE,lookup);Field f=Unsafe.class.getDeclaredField("theUnsafe");f.setAccessible(true);U=(Unsafe)f.get(null);
  var inputs=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonArray();List<Object> output=new ArrayList<>();for(var raw:inputs){var c=raw.getAsJsonObject();World w=(World)U.allocateInstance(World.class);w.rng=RandomSource.create(17);w.client=c.get("client").getAsBoolean();set(w,"random",w.rng);
   ObservedPlayer p=(ObservedPlayer)U.allocateInstance(ObservedPlayer.class);p.events=new ArrayList<>();Abilities abilities=new Abilities();abilities.instabuild=c.get("creative").getAsBoolean();set(p,"abilities",abilities);set(p,"uuid",PLAYER);set(p,"level",w);Inventory inv=new Inventory(p,new EntityEquipment());set(p,"inventory",inv);inv.setSelectedSlot(c.get("selected").getAsInt());
   var init=c.getAsJsonArray("slots");for(int i=0;i<43;i++)inv.setItem(i,item(init.get(i)));ItemStack in=item(c.get("item"));ItemEntity e=new ItemEntity(w,0,0,0,in);set(e,"pickupDelay",c.get("delay").getAsInt());if(!c.get("target").isJsonNull())set(e,"target",UUID.fromString(c.get("target").getAsString()));if(!c.get("thrower").isJsonNull())set(e,"thrower",EntityReference.<Entity>of(UUID.fromString(c.get("thrower").getAsString())));
   Object before=inventory(inv);int changed=inv.getTimesChanged();boolean damaged=in.isDamaged();e.playerTouch(p);var result=new LinkedHashMap<String,Object>();result.put("id",c.get("id").getAsString());result.put("before",before);result.put("slots",inventory(inv));result.put("pop_times",poptimes(inv));result.put("entity_item",stack(e.getItem()));result.put("removed",e.isRemoved());result.put("events",p.events);result.put("times_changed_delta",inv.getTimesChanged()-changed);result.put("damaged",damaged);output.add(result);
  }Files.writeString(Path.of(args[1]),JSON.toJson(Map.of("version",SharedConstants.getCurrentVersion().id(),"cases",output)));
 }
}'''
def inputs():
    def s(id='stone',count=64,patch=None):
        result={'id':'minecraft:'+id,'count':count}
        if patch is not None:result['components']=patch
        return result
    cases=[]
    def case(label,item=None,slots=None,**kw):
        row={'id':label,'creative':False,'client':False,'selected':0,'delay':0,'target':None,'thrower':None,'slots':slots or [None]*43,'item':s(count=1) if item is None else item};row.update(kw);cases.append(row)
    full=[s() for _ in range(36)]+[None]*7
    case('empty-main')
    case('full-survival',slots=full,item=s('dirt',5))
    case('full-creative',slots=full,item=s('dirt',5),creative=True)
    partial=full.copy();partial[0]=s(count=62)
    case('partial-survival',slots=partial,item=s(count=5))
    case('partial-creative',slots=partial,item=s(count=5),creative=True)
    priority=full.copy();priority[4]=s(count=63);priority[0]=s(count=62);priority[40]=s(count=63);priority[8]=None
    case('selected-offhand-main-empty-order',slots=priority,item=s(count=9),selected=4)
    case('components-do-not-merge',slots=partial,item=s(count=5,patch={'minecraft:enchantment_glint_override':True}))
    roomy=full.copy();roomy[4]=None
    case('components-full-identity',slots=roomy,item=s(count=7,patch={'minecraft:enchantment_glint_override':True}))
    case('component-size99',item=s(count=99,patch={'minecraft:max_stack_size':99}))
    case('size16-split',item=s('ender_pearl',20))
    case('size1-split',item=s('wooden_sword',3))
    case('damaged-empty',item=s('wooden_sword',1,{'minecraft:damage':3}))
    case('damaged-full-survival',slots=full,item=s('wooden_sword',1,{'minecraft:damage':3}))
    case('damaged-full-creative',slots=full,item=s('wooden_sword',1,{'minecraft:damage':3}),creative=True)
    case('damaged-whole-copy-oversize-boundary',item=s('wooden_sword',3,{'minecraft:damage':3}))
    case('damage-zero',item=s('wooden_sword',2,{'minecraft:damage':0}))
    case('unbreakable-damage-not-damaged',item=s('wooden_sword',2,{'minecraft:damage':3,'minecraft:unbreakable':{}}))
    for delay in [1,-1,32767]:case('delay-'+str(delay),delay=delay)
    player='11112222-3333-4444-5555-666677778888';other='99992222-3333-4444-5555-666677778888'
    case('target-same',target=player);case('target-other',target=other)
    case('thrower-other-does-not-gate',thrower=other)
    case('client-side-noop',client=True)
    case('equipment-empty-not-main-capacity',slots=full,item=s('dirt',1))
    stew=[{'id':'minecraft:poison','duration':5}]
    case('full-stew-component-identity',item=s('suspicious_stew',1,{'minecraft:suspicious_stew_effects':stew}))
    return cases

def main():
    WORK.mkdir(parents=True,exist_ok=True);(WORK/'ItemEntityPickupReference.java').write_text(SOURCE);cases=inputs();(WORK/'input.json').write_text(json.dumps(cases,separators=(',',':')))
    paths,provenance=verified_client_classpath();cmd=[JAVA,'-Xmx512m','--source','25','--class-path',os.pathsep.join(map(str,paths)),WORK/'ItemEntityPickupReference.java',WORK/'input.json',WORK/'output.json']
    started=time.monotonic();p=subprocess.run(list(map(str,cmd)),cwd=WORK,capture_output=True,text=True,timeout=60);(WORK/'java.stdout').write_text(p.stdout);(WORK/'java.stderr').write_text(p.stderr);assert p.returncode==0,p.stderr
    output=json.loads((WORK/'output.json').read_text());assert output['version']=='26.3'
    result={'pin':'26.3','inputs':cases,'observations':output,'provenance':provenance,'command':'python3 tools/reference_item_entity_pickup.py','seconds':round(time.monotonic()-started,3),'source_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'receiver':'Actual installed ItemEntity.playerTouch and unchanged Inventory.add against real Inventory/EntityEquipment/full initialized item components. Unsafe world/player fixture supplies level, abilities, UUID; overrides take/awardStat/onItemPickup only to capture their call boundary. ServerPlayer networking/menu/advancement effects additionally derived from installed bytecode, not claimed executed by these overridden callbacks.'}
    (ROOT/'reference/item_entity_pickup.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'cases':len(cases),'seconds':result['seconds']}))
if __name__=='__main__':main()
