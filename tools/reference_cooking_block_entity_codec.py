#!/usr/bin/env python3
"""Pinned physical block-entity NBT receiver observations; no gameplay codec."""
from __future__ import annotations
import json,subprocess,time,hashlib
from pathlib import Path
import test_nbt as T
from reference_inventory import ROOT,JAVA,canonical,fingerprint,write_json
from reference_player_inventory_probe import verified_classpath

CACHE=ROOT/'build/cooking-block-entity-codec'
OUTPUT=ROOT/'reference/cooking_block_entity_codec.json'
SOURCE=r'''import java.io.*;import java.nio.file.*;import java.util.*;import java.lang.reflect.*;
import com.google.gson.*;import com.mojang.serialization.*;
import net.minecraft.SharedConstants;import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;import net.minecraft.core.registries.*;import net.minecraft.core.component.*;
import net.minecraft.data.registries.VanillaRegistries;import net.minecraft.resources.*;
import net.minecraft.nbt.*;import net.minecraft.util.ProblemReporter;
import net.minecraft.world.item.*;import net.minecraft.world.level.block.*;import net.minecraft.world.level.block.entity.*;
import net.minecraft.world.level.storage.*;
class CookingBlockEntityCodecReference {
 static HolderLookup.Provider lookup;static RegistryOps<JsonElement> ops;
 static final Gson JSON=new GsonBuilder().serializeNulls().create();
 static Field field(Class<?> type,String name)throws Exception{var f=type.getDeclaredField(name);f.setAccessible(true);return f;}
 static Object stack(ItemStack s){if(s.isEmpty())return null;return Map.of("id",BuiltInRegistries.ITEM.getKey(s.getItem()).toString(),"count",s.getCount(),"components",DataComponentMap.CODEC.encodeStart(ops,s.getComponents()).result().orElseThrow(),"patch",DataComponentPatch.CODEC.encodeStart(ops,s.getComponentsPatch()).result().orElseThrow());}
 static List<Object> items(BlockEntity e)throws Exception{var type=e instanceof CampfireBlockEntity?CampfireBlockEntity.class:AbstractFurnaceBlockEntity.class;var values=(NonNullList<ItemStack>)field(type,"items").get(e);var result=new ArrayList<Object>();for(var s:values)result.add(stack(s));return result;}
 static Object snapshot(BlockEntity e)throws Exception{var out=new TreeMap<String,Object>();out.put("slots",items(e));if(e instanceof CampfireBlockEntity){out.put("progress",field(CampfireBlockEntity.class,"cookingProgress").get(e));out.put("total",field(CampfireBlockEntity.class,"cookingTime").get(e));}else{for(var name:List.of("litTimeRemaining","litTotalTime","cookingTimer","cookingTotalTime"))out.put(name,Integer.toUnsignedLong(field(AbstractFurnaceBlockEntity.class,name).getInt(e)));out.put("speed_bits",Integer.toUnsignedLong(Float.floatToRawIntBits(field(AbstractFurnaceBlockEntity.class,"speedMultiplier").getFloat(e))));var map=(Map<?,?>)field(AbstractFurnaceBlockEntity.class,"recipesUsed").get(e);var used=new TreeMap<String,Object>();for(var p:map.entrySet())used.put(((ResourceKey<?>)p.getKey()).identifier().toString(),Integer.toUnsignedLong((Integer)p.getValue()));out.put("uses",used);}return out;}
 public static void main(String[] args)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();Thread.currentThread().setUncaughtExceptionHandler((thread,error)->error.printStackTrace(new PrintStream(new FileOutputStream(FileDescriptor.err))));
  lookup=VanillaRegistries.createWorldLookup();for(var pending:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup))pending.forEach((holder,components)->holder.bindComponents(components));ops=RegistryOps.create(JsonOps.INSTANCE,lookup);
  var inputs=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonArray();var result=new ArrayList<Object>();
  for(var raw:inputs){var row=raw.getAsJsonObject();var name=row.get("kind").getAsString();BlockEntity e=switch(name){case "campfire"->new CampfireBlockEntity(BlockPos.ZERO,Blocks.CAMPFIRE.defaultBlockState());case "soul_campfire"->new CampfireBlockEntity(BlockPos.ZERO,Blocks.SOUL_CAMPFIRE.defaultBlockState());case "blasting"->new BlastFurnaceBlockEntity(BlockPos.ZERO,Blocks.BLAST_FURNACE.defaultBlockState());case "smoking"->new SmokerBlockEntity(BlockPos.ZERO,Blocks.SMOKER.defaultBlockState());default->new FurnaceBlockEntity(BlockPos.ZERO,Blocks.FURNACE.defaultBlockState());};
   if(e instanceof CampfireBlockEntity){var a=(int[])field(CampfireBlockEntity.class,"cookingProgress").get(e);var b=(int[])field(CampfireBlockEntity.class,"cookingTime").get(e);for(int i=0;i<4;i++){a[i]=(i+1)*11;b[i]=(i+1)*101;}var slots=(NonNullList<ItemStack>)field(CampfireBlockEntity.class,"items").get(e);slots.set(0,new ItemStack(Items.DIRT));}
   byte[] bytes=Base64.getDecoder().decode(row.get("bytes").getAsString());var out=new TreeMap<String,Object>();out.put("id",row.get("id").getAsString());try{
    var tag=NbtIo.read(new DataInputStream(new ByteArrayInputStream(bytes)),NbtAccounter.create(1048576));e.loadWithComponents(TagValueInput.create(ProblemReporter.DISCARDING,lookup,tag));out.put("state",snapshot(e));var saved=e.saveCustomOnly(lookup);var stream=new ByteArrayOutputStream();NbtIo.write(saved,new DataOutputStream(stream));out.put("saved",Base64.getEncoder().encodeToString(stream.toByteArray()));out.put("saved_snbt",saved.toString());out.put("status","accepted");
   }catch(Exception error){out.put("status","error");out.put("exception",error.getClass().getName());out.put("message",String.valueOf(error.getMessage()));}result.add(out);
  }Files.writeString(Path.of(args[1]),JSON.toJson(result));
 }
}'''

def compound(**values):return T.Value(10,tuple((T.text(k),v) for k,v in values.items()))
def string(value):return T.Value(8,T.text(value))
def item(index,id='minecraft:coal',count=1,components=None,**extra):
    members={'Slot':T.Value(1,index&255),'id':string(id),'count':T.Value(3,count&0xffffffff),**extra}
    if components is not None:members['components']=components
    return compound(**members)
def item_list(*values):return T.Value(9,(10,values))
def inputs():
    import base64
    rows=[]
    def add(id,value,kind='smelting',domain='supported'):
        rows.append({'id':id,'kind':kind,'domain':domain,'bytes':base64.b64encode(T.encode_root(T.RootTag((),value))).decode()})
    for kind in ['smelting','blasting','smoking','campfire','soul_campfire']:add('empty_'+kind,compound(),kind)
    values=[T.Value(1,255),T.Value(2,65535),T.Value(3,0xffffffff),T.Value(4,0x80000001ffffffff),T.Value(5,0xbfa00000),T.Value(6,0xbff4000000000000),T.Value(5,0x7f800000),T.Value(5,0xff800000),T.Value(5,0x7fa12345),T.Value(6,0x7ff8000000000000),T.Value(4,0x4000004000000001),T.Value(4,0x7fffffffffffffff),T.Value(6,0x41dfffffffa00000)]
    for n,v in enumerate(values):add('numeric_'+str(n),compound(cooking_time_spent=v,cooking_total_time=v,lit_time_remaining=v,lit_total_time=v,speed_multiplier=v))
    add('wrong_timers',compound(cooking_time_spent=string('4'),speed_multiplier=compound()))
    add('duplicate_last_timer',T.Value(10,((T.text('cooking_time_spent'),T.Value(3,1)),(T.text('cooking_time_spent'),T.Value(3,7)))))
    add('unknown_root_field',compound(unknown=string('retain separately'),CustomName=string('invalid-component-text')))
    add('slots_basic',compound(Items=item_list(item(0,'minecraft:beef',2),item(1),item(2,'minecraft:stone',3))))
    add('duplicate_slot_last',compound(Items=item_list(item(0,'minecraft:coal'),item(0,'minecraft:stone'))))
    add('out_of_bounds',compound(Items=item_list(item(3),item(255))))
    add('missing_slot',compound(Items=item_list(compound(id=string('minecraft:coal'),count=T.Value(3,1)))))
    add('bad_rows',compound(Items=item_list(item(0,'minecraft:no_such_item'),item(1,count=0),item(2,'minecraft:stone'))))
    add('air_and_negative',compound(Items=item_list(item(0,'minecraft:air'),item(1,count=-1))))
    add('default_count',compound(Items=item_list(compound(Slot=T.Value(1,0),id=string('minecraft:coal')))))
    add('float_count',compound(Items=item_list(compound(Slot=T.Value(1,0),id=string('minecraft:coal'),count=T.Value(5,0x40600000)))))
    add('overstack',compound(Items=item_list(item(0,count=99))),domain='authority_refusal')
    add('wrong_count',compound(Items=item_list(compound(Slot=T.Value(1,0),id=string('minecraft:coal'),count=string('2')))))
    add('wrong_slot_type',compound(Items=item_list(compound(Slot=string('0'),id=string('minecraft:coal'),count=T.Value(3,1)))))
    add('unknown_component',compound(Items=item_list(item(0,components=compound(**{'minecraft:no_such_component':compound()})))))
    add('invalid_component',compound(Items=item_list(item(0,components=compound(**{'minecraft:max_stack_size':T.Value(3,0)})))))
    add('partial_patch',compound(Items=item_list(item(0,components=compound(**{'minecraft:max_stack_size':T.Value(3,0),'minecraft:enchantment_glint_override':T.Value(1,1)})))))
    add('removed_fuel',compound(Items=item_list(item(1,components=compound(**{'!minecraft:cooking_fuel':compound()})))))
    add('glint',compound(Items=item_list(item(0,components=compound(**{'minecraft:enchantment_glint_override':T.Value(1,1)})))))
    add('default_patch',compound(Items=item_list(item(0,components=compound(**{'minecraft:max_stack_size':T.Value(3,64)})))))
    add('unsupported_valid_patch',compound(Items=item_list(item(0,components=compound(**{'minecraft:custom_name':string('"named"')})))),domain='component_refusal')
    add('glint_noncanonical_bool',compound(Items=item_list(item(0,components=compound(**{'minecraft:enchantment_glint_override':T.Value(3,256)})))))
    add('unbreakable_unit_byte',compound(Items=item_list(item(0,components=compound(**{'minecraft:unbreakable':T.Value(1,1)})))),domain='supported')
    add('removal_unit_byte',compound(Items=item_list(item(0,components=compound(**{'!minecraft:cooking_fuel':T.Value(1,1)})))),domain='supported')
    add('stew_effects',compound(Items=item_list(item(0,'minecraft:suspicious_stew',1,compound(**{'minecraft:suspicious_stew_effects':item_list(compound(id=string('minecraft:speed')),compound(id=string('minecraft:poison'),duration=T.Value(3,0xffffffff)))})))))
    add('stew_partial_effects',compound(Items=item_list(item(0,'minecraft:suspicious_stew',1,compound(**{'minecraft:suspicious_stew_effects':item_list(compound(id=string('minecraft:speed')),compound(id=string('minecraft:no_such_effect')))})))),domain='supported')
    add('component_duplicate_last',compound(Items=item_list(item(0,components=T.Value(10,((T.text('minecraft:enchantment_glint_override'),T.Value(1,0)),(T.text('minecraft:enchantment_glint_override'),T.Value(1,1))))))))
    add('recipes_partial',compound(RecipesUsed=compound(**{'minecraft:valid':T.Value(3,3),'INVALID':T.Value(3,7),'minecraft:wrong':string('9'),'plain':T.Value(4,0xffffffffffffffff)})))
    add('recipes_negative',compound(RecipesUsed=compound(**{'probe:recipe':T.Value(3,0x80000000)})))
    add('recipes_wrong',compound(RecipesUsed=string('wrong')))
    add('recipes_float',compound(RecipesUsed=compound(**{'probe:recipe':T.Value(5,0xbfa00000)})))
    for id,progress,total in [('empty',(),()),('short',(7,),(8,9)),('full',(1,2,3,4),(5,6,7,8)),('long',(1,2,3,4,5),(6,7,8,9,10))]:add('campfire_arrays_'+id,compound(CookingTimes=T.Value(11,progress),CookingTotalTimes=T.Value(11,total)),'campfire')
    add('campfire_wrong_arrays',compound(CookingTimes=item_list(),CookingTotalTimes=T.Value(7,b'\x01')),'campfire')
    add('campfire_items_patch',compound(Items=item_list(item(0,'minecraft:beef',2),item(3,'minecraft:coal',1,compound(**{'minecraft:enchantment_glint_override':T.Value(1,1)}))),CookingTimes=T.Value(11,(0xffffffff,2))),'campfire')
    for label,tag in [('float_negative_zero',T.Value(5,0x80000000)),('double_negative_zero',T.Value(6,0x8000000000000000)),('double_negative_underflow',T.Value(6,0x8000000000000001))]:
        add(label,compound(speed_multiplier=tag))
    for label,tag in [('fraction',T.Value(5,0x3f000000)),('nan',T.Value(5,0x7fc12345)),('long',T.Value(4,0x100000000)),('negative_zero',T.Value(6,0x8000000000000000))]:
        add('glint_'+label,compound(Items=item_list(item(0,components=compound(**{'minecraft:enchantment_glint_override':tag})))))
    add('coal_stew_string_list',compound(Items=item_list(item(0,components=compound(**{'minecraft:suspicious_stew_effects':T.Value(9,(8,(string('wrong'),)))})))))
    add('coal_stew_wrapped_list',compound(Items=item_list(item(0,components=compound(**{'minecraft:suspicious_stew_effects':item_list(compound(**{'':compound(id=string('minecraft:speed'))}))})))))
    add('recipes_air',compound(RecipesUsed=compound(**{'minecraft:air':T.Value(3,7)})))
    return rows
def extract():
    CACHE.mkdir(parents=True,exist_ok=True);rows=inputs();write_json(CACHE/'codec-inputs.json',rows)
    cp,provenance=verified_classpath();path=CACHE/'CookingBlockEntityCodecReference.java';path.write_text(SOURCE);start=time.monotonic()
    result=subprocess.run([str(JAVA),'-Xmx512m','-Djava.awt.headless=true','--class-path',':'.join(map(str,cp)),str(path),str(CACHE/'codec-inputs.json'),str(CACHE/'codec-output.json')],capture_output=True,text=True,timeout=60,cwd=CACHE)
    (CACHE/'codec-process.log').write_text(result.stdout+result.stderr)
    if result.returncode:raise AssertionError((result.stdout+result.stderr)[-6000:])
    observed=json.loads((CACHE/'codec-output.json').read_text());assert all(r['status']=='accepted' for r in observed),observed
    receipt={'pin':'26.3','source_sha256':hashlib.sha256(SOURCE.encode()).hexdigest(),'inputs_sha256':hashlib.sha256(canonical(rows)).hexdigest(),'provenance':provenance,'observations':observed,'seconds':round(time.monotonic()-start,6),'receiver_scope':'Physical NbtIo.read + actual normal furnace/blast/smoker/campfire loadWithComponents and saveCustomOnly; no world, gameplay, GUI or account state.'}
    write_json(OUTPUT,receipt);return receipt
if __name__=='__main__':print(json.dumps({'observations':len(extract()['observations'])}))
