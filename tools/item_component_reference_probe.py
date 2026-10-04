#!/usr/bin/env python3
"""Observe the unchanged pinned ItemStack codec for the seventeen stew outputs."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

from reference_inventory import ROOT,JAVA,canonical,fingerprint,write_json
from reference_player_inventory_probe import verified_classpath

BUILD=ROOT/'build/item_component/reference'
OUTPUT=ROOT/'reference/item_component.json'
EVIDENCE=ROOT/'evidence/item_component_reference.json'
PRIMARY=ROOT/'reference/crafting_recipe_components.json'
SOURCE=r'''import java.nio.file.*;import java.io.*;import java.util.*;
import com.google.gson.*;import com.mojang.serialization.*;
import net.minecraft.SharedConstants;import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;import net.minecraft.core.registries.*;
import net.minecraft.data.registries.VanillaRegistries;import net.minecraft.resources.*;
import net.minecraft.world.item.*;import net.minecraft.core.component.*;import net.minecraft.nbt.*;
class ItemComponentProbe {
 static final Gson JSON=new GsonBuilder().serializeNulls().create();
 static Object typed(Tag t){Map<String,Object> m=new TreeMap<>();m.put("type",t.getId());switch(t.getId()){
  case 1 -> m.put("bits",((NumericTag)t).intValue()&255);case 3 -> m.put("bits",Integer.toUnsignedLong(((NumericTag)t).intValue()));
  case 8 -> m.put("value",t.asString().orElseThrow());case 9 -> {List<Object> a=new ArrayList<>();for(Tag x:(ListTag)t)a.add(typed(x));m.put("items",a);}
  case 10 -> {Map<String,Object> a=new TreeMap<>();((CompoundTag)t).forEach((k,v)->a.put(k,typed(v)));m.put("entries",a);}
  default -> throw new IllegalArgumentException("unexpected observed tag "+t.getId());}return m;}
 public static void main(String[] args)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();var lookup=VanillaRegistries.createWorldLookup();
  for(var pending:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup))pending.forEach((holder,components)->holder.bindComponents(components));
  var provider=RegistryAccess.fromRegistryOfRegistries(BuiltInRegistries.REGISTRY);
  var jsonOps=RegistryOps.create(JsonOps.INSTANCE,provider);var nbtOps=RegistryOps.create(NbtOps.INSTANCE,provider);
  List<Object> rows=new ArrayList<>();var input=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonArray();
  for(var x:input){var row=x.getAsJsonObject();Map<String,Object> out=new TreeMap<>();out.put("id",row.get("id").getAsString());
   var decoded=ItemStack.CODEC.parse(jsonOps,row.get("stack"));out.put("accepted",decoded.result().isPresent());
   if(decoded.result().isPresent()){
    var stack=decoded.result().get();out.put("limit",stack.getMaxStackSize());out.put("count",stack.getCount());
    out.put("components",DataComponentMap.CODEC.encodeStart(jsonOps,stack.getComponents()).getOrThrow());
    var tag=(CompoundTag)ItemStack.CODEC.encodeStart(nbtOps,stack).getOrThrow();out.put("tag",typed(tag));
    var bytes=new ByteArrayOutputStream();NbtIo.write(tag,new DataOutputStream(bytes));byte[] wire=bytes.toByteArray();
    out.put("nbt_base64",Base64.getEncoder().encodeToString(wire));out.put("nbt_bytes",wire.length);
    var read=NbtIo.read(new DataInputStream(new ByteArrayInputStream(wire)),NbtAccounter.create(1048576));out.put("readback_tag",typed(read));
    var restored=ItemStack.CODEC.parse(nbtOps,read).getOrThrow();out.put("same_after_nbt",ItemStack.isSameItemSameComponents(stack,restored));
   }else out.put("error",decoded.error().orElseThrow().message());rows.add(out);
  }
  Map<String,Object> identity=new TreeMap<>();for(Class<?> c:List.of(ItemStack.class,DataComponentMap.class,DataComponentPatch.class)){
   try(var stream=c.getResourceAsStream("/"+c.getName().replace('.','/')+".class")){
    var md=java.security.MessageDigest.getInstance("SHA-256");identity.put(c.getName(),HexFormat.of().formatHex(md.digest(stream.readAllBytes())));}}
  Files.writeString(Path.of(args[1]),JSON.toJson(Map.of("rows",rows,"loaded_class_sha256",identity)));
 }
}'''

def pin(path:Path)->dict:
    return {'path':str(path.resolve()),**fingerprint(path)}

def prepare()->dict:
    BUILD.mkdir(parents=True,exist_ok=True)
    source=json.loads(PRIMARY.read_text())
    assert source['pin']=='26.3'
    rows=[{'id':r['id'],'stack':{'id':r['output']['id'],'count':r['output']['count'],'components':r['output']['patch']}}
        for r in source['cases'] if r['id'].startswith('minecraft:')]
    assert len(rows)==17 and all(r['stack']['id']=='minecraft:suspicious_stew' for r in rows)
    for name,ticks in [('default',160),('zero',0),('negative',-1),('minimum',-2147483648),('maximum',2147483647)]:
        rows.append({'id':'item_component:'+name,'stack':{'id':'minecraft:suspicious_stew','count':1,
            'components':{'minecraft:suspicious_stew_effects':[{'id':'minecraft:speed','duration':ticks}]}}})
    rows.append({'id':'item_component:ordered_duplicates','stack':{'id':'minecraft:suspicious_stew','count':1,
        'components':{'minecraft:suspicious_stew_effects':[{'id':'minecraft:speed','duration':20},{'id':'minecraft:poison','duration':40},{'id':'minecraft:speed','duration':-1}]}}})
    cp,provenance=verified_classpath()
    assert source['provenance']['client']['sha256']==provenance['client']['sha256']
    java=BUILD/'ItemComponentProbe.java';java.write_text(SOURCE)
    write_json(BUILD/'input.json',rows)
    command=[str(JAVA),'-Xmx512m','-Djava.awt.headless=true','--class-path',':'.join(map(str,cp)),str(java),str(BUILD/'input.json'),str(BUILD/'output.json')]
    return {'status':'prepared','pin':'26.3','primary':pin(PRIMARY),'java_source':pin(java),
        'input':pin(BUILD/'input.json'),'command':command,'provenance':provenance,'cases':len(rows)}

def main()->None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run',action='store_true',help='Run one bounded headless Java process after coordinating a heavy slot')
    args=parser.parse_args()
    prepared=prepare()
    if not args.run:
        write_json(ROOT/'evidence/item_component_reference_prepared.json',prepared)
        print(json.dumps({'status':'prepared','cases':prepared['cases'],'java_not_executed':True}));return
    started=time.monotonic()
    try:
        proc=subprocess.run(prepared['command'],cwd=ROOT,capture_output=True,text=True,timeout=90)
    except subprocess.TimeoutExpired as failure:
        text=lambda value:value.decode(errors='replace') if isinstance(value,bytes) else value
        write_json(EVIDENCE,{**prepared,'status':'failed','timeout_seconds':90,
            'stdout':text(failure.stdout),'stderr':text(failure.stderr),'seconds':round(time.monotonic()-started,6)})
        raise
    receipt={**prepared,'status':'failed' if proc.returncode else 'executed','exit_code':proc.returncode,
        'stdout':proc.stdout,'stderr':proc.stderr,'seconds':round(time.monotonic()-started,6)}
    write_json(EVIDENCE,receipt)
    assert proc.returncode==0,receipt
    assert prepared['java_source']==pin(BUILD/'ItemComponentProbe.java') and prepared['input']==pin(BUILD/'input.json'),'Probe source/input changed during Java execution'
    assert prepared['primary']==pin(PRIMARY),'Primary input changed during Java execution'
    observed=json.loads((BUILD/'output.json').read_text())
    assert len(observed['rows'])==prepared['cases'] and all(r['accepted'] and r['same_after_nbt'] and r['tag']==r['readback_tag'] and r['limit']==1 and r['count']==1 for r in observed['rows'])
    import zipfile
    client=Path(prepared['provenance']['client']['path'])
    with zipfile.ZipFile(client) as jar:
        for name,digest in observed['loaded_class_sha256'].items():
            assert hashlib.sha256(jar.read(name.replace('.','/')+'.class')).hexdigest()==digest,name
    source=json.loads(PRIMARY.read_text());base=next(r['components'] for r in source['defaults'] if r['id']=='minecraft:suspicious_stew')
    observed.update(schema_version=1,pin='26.3',default_components=base,default_components_sha256=hashlib.sha256(canonical(base)).hexdigest(),
        primary=pin(PRIMARY),provenance=prepared['provenance'],input=prepared['input'],java_source=prepared['java_source'])
    write_json(OUTPUT,observed)
    receipt.update(status='passed',output=pin(OUTPUT),loaded_classes_verified_against_pinned_jar=True)
    write_json(EVIDENCE,receipt)
    print(json.dumps({'status':'passed','cases':len(observed['rows']),'reference':str(OUTPUT),'seconds':receipt['seconds']}))

if __name__=='__main__':main()
