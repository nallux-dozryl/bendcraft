#!/usr/bin/env python3
"""Observe pinned 26.3 item defaults and bounded primitive ItemStack calls."""
from __future__ import annotations

import argparse
import collections
import copy
import csv
import hashlib
import json
import pathlib
import random
import re
import subprocess
import zipfile

from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json, write_tsv
from reference_block_probe import verified_classpath

JSON_PATH=ROOT/"reference/item_stacks.json"
TABLE=ROOT/"generated/reference_item_metadata.tsv"
SEED=26316585023
SOURCE=r'''import java.io.*;
import java.nio.file.*;
import java.lang.reflect.*;
import java.util.*;
import com.google.gson.*;
import com.mojang.serialization.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.core.component.*;
import net.minecraft.data.registries.VanillaRegistries;
import net.minecraft.resources.*;
import net.minecraft.world.item.*;
import net.minecraft.world.flag.FeatureFlags;
import net.minecraft.network.chat.*;
import net.minecraft.util.Unit;

class ReferenceItemProbe {
    static final Gson JSON=new GsonBuilder().serializeNulls().create();
    static RegistryOps<JsonElement> OPS;
    static final Field RAW_COUNT, RAW_ITEM, RAW_COMPONENTS;
    static {
        try { RAW_COUNT=ItemStack.class.getDeclaredField("count"); RAW_ITEM=ItemStack.class.getDeclaredField("item"); RAW_COMPONENTS=ItemStack.class.getDeclaredField("components");
            RAW_COUNT.setAccessible(true);RAW_ITEM.setAccessible(true);RAW_COMPONENTS.setAccessible(true);
        } catch(ReflectiveOperationException e) { throw new ExceptionInInitializerError(e); }
    }
    static String key(Item item) { return BuiltInRegistries.ITEM.getKey(item).toString(); }
    static Object encoded(DataResult<JsonElement> r) { return r.result().isPresent()?r.result().get():Map.of("codec_error",r.error().orElseThrow().message()); }
    static List<Object> components(DataComponentMap map) {
        List<Object> result=new ArrayList<>();
        for(TypedDataComponent<?> c:map) {
            Map<String,Object> v=new TreeMap<>(); v.put("type_id",BuiltInRegistries.DATA_COMPONENT_TYPE.getId(c.type())); v.put("identifier",BuiltInRegistries.DATA_COMPONENT_TYPE.getKey(c.type()).toString());
            v.put("value_class",c.value().getClass().getName());v.put("transient",c.type().isTransient()); v.put("encoded_value",encoded(c.encodeValue(OPS)));
            if(c.value() instanceof Integer||c.value() instanceof Boolean||c.value() instanceof String) v.put("primitive_value",c.value());
            result.add(v);
        }
        result.sort(Comparator.comparingInt(v->((Number)((Map<?,?>)v).get("type_id")).intValue())); return result;
    }
    static Map<String,Object> snapshot(ItemStack s) {
        try {
            Map<String,Object> r=new TreeMap<>();int stored=RAW_COUNT.getInt(s);r.put("stored_count",stored);r.put("stored_count_i32_bits",String.format(Locale.ROOT,"%08x",stored));
            Holder<?> storedItem=(Holder<?>)RAW_ITEM.get(s);r.put("stored_item",storedItem==null?null:key((Item)storedItem.value()));r.put("visible_item",key(s.getItem()));r.put("visible_count",s.getCount());r.put("is_empty",s.isEmpty());r.put("canonical_empty",s==ItemStack.EMPTY);
            r.put("max_stack_size",s.getMaxStackSize());r.put("max_damage",s.getMaxDamage());r.put("damage",s.getDamageValue());r.put("damageable",s.isDamageableItem());r.put("damaged",s.isDamaged());r.put("stackable",s.isStackable());
            r.put("public_components",components(s.getComponents()));r.put("stored_components",components((DataComponentMap)RAW_COMPONENTS.get(s)));r.put("public_patch",encoded(DataComponentPatch.CODEC.encodeStart(OPS,s.getComponentsPatch())));
            return r;
        } catch(IllegalAccessException e) { throw new IllegalStateException(e); }
    }
    static void patch(ItemStack stack,JsonObject p) {
        String id=p.get("component").getAsString(), action=p.get("action").getAsString(); JsonElement v=p.get("value");
        DataComponentType<?> type=BuiltInRegistries.DATA_COMPONENT_TYPE.getValue(Identifier.parse(id));
        if(type==null) throw new IllegalArgumentException("Unknown component "+id);
        if(action.equals("remove")) { stack.remove(type); return; }
        if(!action.equals("set")) throw new IllegalArgumentException("Unknown component action");
        switch(id) {
            case "minecraft:max_stack_size": stack.set(DataComponents.MAX_STACK_SIZE,v.getAsInt());break;
            case "minecraft:max_damage": stack.set(DataComponents.MAX_DAMAGE,v.getAsInt());break;
            case "minecraft:damage": stack.set(DataComponents.DAMAGE,v.getAsInt());break;
            case "minecraft:repair_cost": stack.set(DataComponents.REPAIR_COST,v.getAsInt());break;
            case "minecraft:unbreakable": stack.set(DataComponents.UNBREAKABLE,Unit.INSTANCE);break;
            case "minecraft:enchantment_glint_override": stack.set(DataComponents.ENCHANTMENT_GLINT_OVERRIDE,v.getAsBoolean());break;
            case "minecraft:custom_name": stack.set(DataComponents.CUSTOM_NAME,Component.literal(v.getAsString()));break;
            default: throw new IllegalArgumentException("Unsupported explicitly typed fixture component "+id);
        }
    }
    static ItemStack stack(JsonObject input) {
        if(input.has("canonical_empty")&&input.get("canonical_empty").getAsBoolean()) return ItemStack.EMPTY;
        Item item=BuiltInRegistries.ITEM.getValue(Identifier.parse(input.get("item").getAsString())); if(item==null) throw new IllegalArgumentException("Unknown item");
        ItemStack s=new ItemStack(item,input.get("count").getAsInt());
        if(input.has("components"))for(JsonElement p:input.getAsJsonArray("components"))patch(s,p.getAsJsonObject()); return s;
    }
    static Map<String,Object> observe(JsonObject c) {
        String op=c.get("operation").getAsString();JsonObject in=c.getAsJsonObject("input");Map<String,Object> r=new TreeMap<>();r.put("kind","case");r.put("id",c.get("id").getAsString());Map<String,Object> out=new TreeMap<>();r.put("expected",out);
        // Each fixture receives a clean singleton so EMPTY mutation cannot contaminate later cases.
        ItemStack.EMPTY.setCount(0);
        try { ((PatchedDataComponentMap)RAW_COMPONENTS.get(ItemStack.EMPTY)).clearPatch(); } catch(IllegalAccessException e) { throw new IllegalStateException(e); }
        try {
            ItemStack s=stack(in.getAsJsonObject("stack"));out.put("before",snapshot(s));
            int amount=in.has("amount")?in.get("amount").getAsInt():0;
            ItemStack result=null;
            switch(op) {
                case "construct":break;
                case "copy":result=s.copy();break;
                case "copy_with_count":result=s.copyWithCount(amount);break;
                case "split":result=s.split(amount);break;
                case "grow":s.grow(amount);break;
                case "shrink":s.shrink(amount);break;
                case "set_count":s.setCount(amount);break;
                case "limit_size":s.limitSize(amount);break;
                case "set_damage":s.setDamageValue(amount);break;
                case "same": {
                    ItemStack other=stack(in.getAsJsonObject("other"));out.put("other",snapshot(other));out.put("same_item",ItemStack.isSameItem(s,other));out.put("same_item_same_components",ItemStack.isSameItemSameComponents(s,other));out.put("matches",ItemStack.matches(s,other));break;
                }
                case "copy_then_mutate": {
                    result=s.copy();out.put("copy_before",snapshot(result));out.put("same_component_map_object",s.getComponents()==result.getComponents());
                    for(JsonElement p:in.getAsJsonArray("copy_patches"))patch(result,p.getAsJsonObject());result.grow(amount);
                    out.put("source_after_copy_mutation",snapshot(s));
                    if(in.has("source_patches"))for(JsonElement p:in.getAsJsonArray("source_patches"))patch(s,p.getAsJsonObject());break;
                }
                case "copy_mutable_name_alias": {
                    result=s.copy();out.put("custom_name_value_is_same_object",s.get(DataComponents.CUSTOM_NAME)==result.get(DataComponents.CUSTOM_NAME));
                    ((MutableComponent)result.get(DataComponents.CUSTOM_NAME)).append(in.get("append_text").getAsString());break;
                }
                case "immutable_snapshot_then_mutate": {
                    DataComponentMap immutable=s.immutableComponents();out.put("immutable_before",components(immutable));
                    for(JsonElement p:in.getAsJsonArray("source_patches"))patch(s,p.getAsJsonObject());out.put("immutable_after",components(immutable));break;
                }
                default:throw new IllegalArgumentException("Unknown item fixture operation");
            }
            out.put("after",snapshot(s));if(result!=null){out.put("result",snapshot(result));out.put("result_is_source",result==s);out.put("result_same_item_same_components_as_source",ItemStack.isSameItemSameComponents(s,result));}
        } catch(RuntimeException e) { out.put("error_class",e.getClass().getName());out.put("error_message",String.valueOf(e.getMessage())); }
        return r;
    }
    public static void main(String[] args)throws Exception {
        SharedConstants.tryDetectVersion();Bootstrap.bootStrap();var lookup=VanillaRegistries.createWorldLookup();
        for(var pending:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup))pending.forEach((holder,components)->holder.bindComponents(components));
        OPS=lookup.createSerializationContext(JsonOps.INSTANCE);
        try(PrintWriter out=new PrintWriter(Files.newBufferedWriter(Path.of(args[1])));BufferedReader in=Files.newBufferedReader(Path.of(args[0]))){
            out.println(JSON.toJson(Map.of("kind","item_constants","default_max_stack_size",Item.class.getField("DEFAULT_MAX_STACK_SIZE").get(null),"absolute_max_stack_size",Item.class.getField("ABSOLUTE_MAX_STACK_SIZE").get(null),"max_bar_width",Item.class.getField("MAX_BAR_WIDTH").get(null))));
            for(DataComponentType<?> type:BuiltInRegistries.DATA_COMPONENT_TYPE){Map<String,Object> r=new TreeMap<>();r.put("kind","component_type");r.put("type_id",BuiltInRegistries.DATA_COMPONENT_TYPE.getId(type));r.put("identifier",BuiltInRegistries.DATA_COMPONENT_TYPE.getKey(type).toString());r.put("transient",type.isTransient());r.put("ignore_swap_animation",type.ignoreSwapAnimation());List<String> fields=new ArrayList<>();for(Field f:DataComponents.class.getFields())if(Modifier.isStatic(f.getModifiers())&&f.getType()==DataComponentType.class&&f.get(null)==type)fields.add(f.getName()+":"+f.getGenericType().getTypeName());Collections.sort(fields);r.put("declarations",fields);out.println(JSON.toJson(r));}
            for(Item item:BuiltInRegistries.ITEM){ItemStack stack=item.getDefaultInstance();Map<String,Object> r=new TreeMap<>();r.put("kind","item");r.put("item_id",BuiltInRegistries.ITEM.getId(item));r.put("identifier",key(item));r.put("class",item.getClass().getName());r.put("description_id",item.getDescriptionId());r.put("item_default_max_stack_size",item.getDefaultMaxStackSize());r.put("components",components(item.components()));r.put("components_json",encoded(DataComponentMap.CODEC.encodeStart(OPS,item.components())));r.put("default_stack",snapshot(stack));r.put("fits_inside_container_items",item.canFitInsideContainerItems());r.put("required_features",FeatureFlags.REGISTRY.toNames(item.requiredFeatures()).stream().map(Object::toString).sorted().toList());r.put("enabled_default_flags",stack.isItemEnabled(FeatureFlags.DEFAULT_FLAGS));r.put("rarity",stack.getRarity().name());r.put("use_animation",stack.getUseAnimation().name());r.put("has_foil",stack.hasFoil());r.put("enchantable",stack.isEnchantable());var remainder=item.getCraftingRemainder();r.put("crafting_remainder",remainder==null?Map.of("present",false):Map.of("present",true,"item",key(remainder.item().value()),"count",remainder.count()));out.println(JSON.toJson(r));}
            String line;while((line=in.readLine())!=null)out.println(JSON.toJson(observe(JsonParser.parseString(line).getAsJsonObject())));if(out.checkError())throw new IOException("Item oracle output write failed");
        }
    }
}'''


def inputs() -> list[dict]:
    result=[]
    def add(op,label,data,tags):result.append({"id":f"{op}:{label}","operation":op,"input":data,"tags":tags})
    counts=[-2147483648,-1,0,1,2,15,16,63,64,65,2147483647]
    amounts=[-2147483648,-1,0,1,16,65,2147483647]
    items=["air","stone","egg","diamond_sword","potion","shulker_box"]
    for item in items:
        for count in counts:
            initial={"item":"minecraft:"+item,"count":count}
            for op in ["construct","copy"]:add(op,f"{item}-{count}",{"stack":initial},["targeted","count_edge"])
            for amount in amounts:
                for op in ["copy_with_count","split","grow","shrink","set_count","limit_size"]:
                    add(op,f"{item}-{count}-{amount}",{"stack":initial,"amount":amount},["targeted","signed_count_edge"])
    for amount in amounts:
        for op in ["copy_with_count","split","grow","shrink","set_count","limit_size"]:
            add(op,f"canonical-empty-{amount}",{"stack":{"canonical_empty":True},"amount":amount},["targeted","explicit_empty_singleton"])
    def change(component,value=None,action="set"):
        p={"component":"minecraft:"+component,"action":action}
        if action=="set":p["value"]=value
        return p
    base={"item":"minecraft:stone","count":3}
    patches=[[],[change("custom_name","alpha")],[change("damage",0)], [change("damage",1)], [change("max_stack_size",1)],
             [change("enchantment_glint_override",False)],[change("enchantment_glint_override",True)], [change("unbreakable",{})],
             [change("repair_cost",0)], [change("repair_cost",1)], [change("max_stack_size",action="remove")]]
    for i,p in enumerate(patches):
        for j,q in enumerate(patches):
            add("same",f"components-{i}-{j}",{"stack":{**base,"components":p},"other":{**base,"count":1,"components":q}},["targeted","component_presence_type_value_equality"])
    for count in [-1,0,1,2]:
        for other in ["stone","dirt","air"]:
            add("same",f"empty-{count}-{other}",{"stack":{**base,"count":count,"components":[change("custom_name","alpha")]},"other":{"item":"minecraft:"+other,"count":count,"components":[change("custom_name","beta")]}},["targeted","empty_component_hiding"])
    for item in ["stone","diamond_sword"]:
        for count in [0,1,3]:
            add("copy_then_mutate",f"{item}-{count}",{"stack":{"item":"minecraft:"+item,"count":count,"components":[change("custom_name","alpha"),change("damage",1)]},"amount":2,"copy_patches":[change("custom_name","beta"),change("damage",5)],"source_patches":[change("repair_cost",4)]},["targeted","copy_map_isolation"])
    add("copy_mutable_name_alias","literal-name",{"stack":{**base,"components":[change("custom_name","alpha")]},"append_text":"-suffix"},["targeted","observed_mutable_component_alias"])
    add("immutable_snapshot_then_mutate","map",{"stack":{**base,"components":[change("custom_name","alpha"),change("damage",1)]},"source_patches":[change("custom_name","beta"),change("damage",5)]},["targeted","immutable_map_snapshot"])
    for item in ["stone","diamond_sword"]:
        for count in [0,1]:
            for damage in [-2147483648,-1,0,1,1560,1561,1562,2147483647]:
                add("set_damage",f"{item}-{count}-{damage}",{"stack":{"item":"minecraft:"+item,"count":count},"amount":damage},["targeted","damage_clamp_and_component_presence"])
    for i,p in enumerate([[change("max_stack_size",0)],[change("max_stack_size",-1)],[change("max_stack_size",100)],[change("max_damage",-1)],[change("damage",-1)],[change("damage",2147483647)],[change("repair_cost",-1)]]):
        add("construct",f"unchecked-component-{i}",{"stack":{**base,"components":p}},["targeted","unchecked_internal_component_setter"])
    rng=random.Random(SEED)
    for i in range(100):
        item=rng.choice(items[1:]);count=rng.randint(-2147483648,2147483647);amount=rng.randint(-2147483648,2147483647)
        for op in ["copy_with_count","split","grow","shrink","set_count"]:
            add(op,f"random-{i}",{"stack":{"item":"minecraft:"+item,"count":count},"amount":amount},["seeded_random","signed_i32_inputs"])
    return result


def run_java(cases,jars,suffix=""):
    d=ROOT/"reference/extracted/item_probe";d.mkdir(parents=True,exist_ok=True);source=d/"ReferenceItemProbe.java";source.write_text(SOURCE)
    incoming=ROOT/f"reference/cache/item-input{suffix}.jsonl";outgoing=ROOT/f"reference/cache/item-observed{suffix}.jsonl";incoming.write_text("".join(canonical(c).decode()+"\n" for c in cases))
    command=[str(JAVA),"-cp",":".join(map(str,jars)),str(source),str(incoming),str(outgoing)]
    r=subprocess.run(command,capture_output=True,text=True);(ROOT/f"reference/cache/item-java{suffix}.log").write_text(r.stdout+r.stderr);r.check_returncode()
    records=[json.loads(line) for line in outgoing.read_text().splitlines()]
    observed=[r for r in records if r["kind"]=="case"]
    if [c["id"] for c in observed]!=[c["id"] for c in cases]:raise ValueError("Item fixture Java identity mismatch")
    return records,{"command":command,"input_sha256":fingerprint(incoming)["sha256"],"observation_sha256":fingerprint(outgoing)["sha256"],"java_source_sha256":hashlib.sha256(SOURCE.encode()).hexdigest()}


CORE_CLASSES=["net.minecraft.world.item.Item","net.minecraft.world.item.ItemStack","net.minecraft.world.item.ItemInstance","net.minecraft.core.component.DataComponents","net.minecraft.core.component.DataComponentMap","net.minecraft.core.component.PatchedDataComponentMap","net.minecraft.core.component.DataComponentGetter","net.minecraft.core.component.DataComponentType","net.minecraft.core.component.TypedDataComponent","net.minecraft.core.component.DataComponentInitializers","net.minecraft.core.Holder$Reference","net.minecraft.data.registries.VanillaRegistries","net.minecraft.util.Mth"]
METHODS={"Item","ItemStack","components","getDefaultMaxStackSize","getDefaultInstance","getCraftingRemainder","canFitInsideContainerItems","requiredFeatures","isEmpty","getItem","typeHolder","getCount","count","setCount","copy","copyWithCount","split","grow","shrink","limitSize","isSameItem","isSameItemSameComponents","matches","getMaxStackSize","getMaxDamage","getDamageValue","setDamageValue","isDamageableItem","isDamaged","isStackable","getComponents","getPrototype","getComponentsPatch","immutableComponents","get","getOrDefault","set","remove","hasNonDefault","ensureMapOwnership","toImmutableMap","equals","encodeValue","codec","codecOrThrow","isTransient","ignoreSwapAnimation","bindComponents","build","createWorldLookup","clamp"}


def source_inventory(jars,item_classes):
    r=subprocess.run([str(JAVA.parent/"javap"),"-c","-p","-classpath",str(jars[0]),*CORE_CLASSES],check=True,capture_output=True,text=True);(ROOT/"reference/cache/item-bytecode.txt").write_text(r.stdout)
    chunks=r.stdout.split('Compiled from "')[1:];records={}
    if len(chunks)!=len(CORE_CLASSES):raise ValueError("Unexpected item javap topology")
    with zipfile.ZipFile(jars[0]) as archive:
        for owner,chunk in zip(CORE_CLASSES,chunks):
            if owner not in chunk.splitlines()[1]:raise ValueError("Unexpected item named declaration")
            methods=[]
            for signature,body in re.findall(r"^  ([^\n]*\([^\n]*\);)\n(.*?)(?=^  [^\n]*(?:;|\{)\n|\Z)",chunk,re.M|re.S):
                name=re.search(r"([\w$]+)\([^\n]*\);$",signature)
                if name and name[1] in METHODS:methods.append({"signature":signature,"bytecode_text_sha256":hashlib.sha256(body.encode()).hexdigest(),"direct_call_references":sorted(set(re.findall(r"// (?:InterfaceMethod|Method) (.+)",body))),"field_references":sorted(set(re.findall(r"// Field (.+)",body)))})
            entry=owner.replace(".","/")+".class";records[owner]={"class_sha256":hashlib.sha256(archive.read(entry)).hexdigest(),"declaration":chunk.splitlines()[1],"methods":methods}
        item_hashes={name:hashlib.sha256(archive.read(name.replace(".","/")+".class")).hexdigest() for name in sorted(item_classes)}
    return {"core_classes":records,"observed_item_class_hashes":item_hashes,"javap_text_sha256":hashlib.sha256(r.stdout.encode()).hexdigest(),"scope":"Core named declarations and direct bytecode references; subtype byte hashes do not establish world/entity independence"}


HEADERS=["item_id","identifier","item_class","description_id","item_default_max_stack_size","default_stack_max_stack_size","default_max_damage","default_damage","default_count","default_empty","default_stackable","default_damageable","fits_inside_container_items","enabled_default_flags","required_features_json","rarity","use_animation","has_foil","enchantable","crafting_remainder_json","default_component_set_id","default_components_sha256","report_components_sha256"]


def organize(records,cases):
    types=sorted([r for r in records if r["kind"]=="component_type"],key=lambda r:r["type_id"]);items=sorted([r for r in records if r["kind"]=="item"],key=lambda r:r["item_id"])
    dictionary={};sets={};snapshots={}
    def intern(target,value):
        key=hashlib.sha256(canonical(value)).hexdigest();target.setdefault(key,value);return key
    def component_set(values):
        pairs=[[v["type_id"],intern(dictionary,v)] for v in values];return intern(sets,pairs)
    def snapshot(value):
        v=copy.deepcopy(value);v["public_component_set"]=component_set(v.pop("public_components"));v["stored_component_set"]=component_set(v.pop("stored_components"));return intern(snapshots,v)
    out_cases=[]
    observed={r["id"]:r for r in records if r["kind"]=="case"}
    for c in cases:
        out=copy.deepcopy(observed[c["id"]]["expected"])
        for k,v in list(out.items()):
            if k in {"before","after","other","result","copy_before","source_after_copy_mutation"}:out[k+"_snapshot"]=snapshot(v);del out[k]
            elif k in {"immutable_before","immutable_after"}:out[k+"_component_set"]=component_set(v);del out[k]
        out_cases.append({**c,"expected":out})
    rows=[];report_hashes=[];mismatches=[]
    for item in items:
        identifier=item["identifier"];path=ROOT/"reference/reports/reports"/identifier.split(":")[0]/"components/item"/(identifier.split(":")[1]+".json");report=json.loads(path.read_text())["components"]
        report_sha=hashlib.sha256(canonical(report)).hexdigest();actual_sha=hashlib.sha256(canonical(item["components_json"])).hexdigest()
        if item["components_json"]!=report:mismatches.append(identifier)
        report_hashes.append([identifier,report_sha]);s=item["default_stack"]
        rows.append([item["item_id"],identifier,item["class"],item["description_id"],item["item_default_max_stack_size"],s["max_stack_size"],s["max_damage"],s["damage"],s["visible_count"],s["is_empty"],s["stackable"],s["damageable"],item["fits_inside_container_items"],item["enabled_default_flags"],item["required_features"],item["rarity"],item["use_animation"],item["has_foil"],item["enchantable"],item["crafting_remainder"],component_set(item["components"]),actual_sha,report_sha])
    # Stable sorted hash-derived integer indexes keep repeated snapshots/components compact.
    value_keys=sorted(dictionary);set_keys=sorted(sets);snapshot_keys=sorted(snapshots);v_ids={k:i for i,k in enumerate(value_keys)};s_ids={k:i for i,k in enumerate(set_keys)};p_ids={k:i for i,k in enumerate(snapshot_keys)}
    values=[{"sha256":k,**dictionary[k]} for k in value_keys]
    component_sets=[{"sha256":k,"members":[[type_id,v_ids[v]] for type_id,v in sets[k]]} for k in set_keys]
    snapshot_rows=[]
    for k in snapshot_keys:
        v=copy.deepcopy(snapshots[k]);v["public_component_set_id"]=s_ids[v.pop("public_component_set")];v["stored_component_set_id"]=s_ids[v.pop("stored_component_set")];snapshot_rows.append({"sha256":k,**v})
    for c in out_cases:
        for key,value in c["expected"].items():
            if key.endswith("_snapshot"):c["expected"][key]=p_ids[value]
            elif key.endswith("_component_set"):c["expected"][key]=s_ids[value]
    for row in rows:row[20]=s_ids[row[20]]
    constants=[r for r in records if r["kind"]=="item_constants"]
    if len(constants)!=1:raise ValueError("Item primitive constant observation missing/duplicated")
    return {"item_constants":constants[0],"component_types":types,"component_values":values,"component_sets":component_sets,"stack_snapshots":snapshot_rows,"cases":out_cases,"report_comparison":{"matched":len(items)-len(mismatches),"mismatches":mismatches,"reports_canonical_tree_sha256":hashlib.sha256(canonical(sorted(report_hashes))).hexdigest()}},rows,items


def validate(metadata,rows,records=None):
    if metadata["schema_version"]!=1 or metadata["pin"]!="26.3":raise ValueError("Item fixture pin/schema mismatch")
    if hashlib.sha256(canonical(metadata["observations"])).hexdigest()!=metadata["observations_sha256"]:raise ValueError("Item observation checksum mismatch")
    o=metadata["observations"];types=o["component_types"];values=o["component_values"];sets=o["component_sets"];snapshots=o["stack_snapshots"];cases=o["cases"]
    if [{k:c[k] for k in ["id","operation","input","tags"]} for c in cases]!=inputs():raise ValueError("Item independent input generation mismatch")
    registry=json.loads((ROOT/"reference/reports/reports/registries.json").read_text())
    expected=registry["minecraft:item"]["entries"]
    expected_types=registry["minecraft:data_component_type"]["entries"]
    if len(types)!=len(expected_types) or [t["type_id"]for t in types]!=list(range(len(types))):raise ValueError("Item component type registry count/order mismatch")
    for t in types:
        if expected_types.get(t["identifier"],{}).get("protocol_id")!=t["type_id"]:raise ValueError("Item component type registry identity mismatch")
    if len(rows)!=len(expected) or len({row[1] for row in rows})!=len(rows):raise ValueError("Item registry row count mismatch")
    for row in rows:
        if row[1] not in expected or row[0]!=expected[row[1]]["protocol_id"]:raise ValueError("Item registry protocol identity mismatch")
        if row[11] and row[6]<=0:raise ValueError("Default damageable item without positive max damage")
        if not 0<=row[20]<len(sets):raise ValueError("Item component set index out of range")
    for i,v in enumerate(values):
        payload={k:x for k,x in v.items() if k!="sha256"}
        if hashlib.sha256(canonical(payload)).hexdigest()!=v["sha256"]:raise ValueError("Item typed component value checksum mismatch")
        if not 0<=v["type_id"]<len(types) or types[v["type_id"]]["identifier"]!=v["identifier"]:raise ValueError("Item component type/value identity mismatch")
    for component_set in sets:
        members=component_set["members"]
        if [m[0]for m in members]!=sorted({m[0]for m in members}):raise ValueError("Item component set type order/uniqueness mismatch")
        if any(not 0<=v<len(values) or values[v]["type_id"]!=t for t,v in members):raise ValueError("Item component set typed value reference mismatch")
        payload=[[t,values[v]["sha256"]]for t,v in members]
        if hashlib.sha256(canonical(payload)).hexdigest()!=component_set["sha256"]:raise ValueError("Item component set checksum mismatch")
    for s in snapshots:
        if not -2147483648<=s["stored_count"]<=2147483647 or s["stored_count_i32_bits"]!=f'{s["stored_count"] & 0xffffffff:08x}':raise ValueError("Item raw signed count encoding mismatch")
        payload={k:v for k,v in s.items()if k!="sha256"}
        for name in ["public","stored"]:
            index=payload.pop(name+"_component_set_id")
            if not 0<=index<len(sets):raise ValueError("Item snapshot component set out of range")
            payload[name+"_component_set"]=sets[index]["sha256"]
        if hashlib.sha256(canonical(payload)).hexdigest()!=s["sha256"]:raise ValueError("Item snapshot checksum mismatch")
    for c in cases:
        for k,v in c["expected"].items():
            if k.endswith("_snapshot")and not 0<=v<len(snapshots):raise ValueError("Item fixture snapshot index out of range")
            if k.endswith("_component_set")and not 0<=v<len(sets):raise ValueError("Item fixture component set index out of range")
    if records is not None:
        actual,actual_rows,_=organize(records,inputs())
        if o!=actual or rows!=actual_rows:raise ValueError("Item fixture differs from independent Java/official report observations")
    if o["report_comparison"]["mismatches"]:raise ValueError("Item initialized Java components differ from generator reports")
    return {"items":len(rows),"component_types":len(types),"component_values":len(values),"component_sets":len(sets),"stack_snapshots":len(snapshots),"cases":len(cases),"operations":dict(sorted(collections.Counter(c["operation"] for c in cases).items())),"official_report_component_matches":o["report_comparison"]["matched"],"oracle_compared":records is not None}


def read_rows():
    with TABLE.open()as stream:table=list(csv.reader(stream,delimiter="\t"))
    if table[0]!=HEADERS:raise ValueError("Item metadata table schema mismatch")
    result=[]
    for row in table[1:]:
        for i in [0,4,5,6,7,8,20]:row[i]=int(row[i])
        for i in [9,10,11,12,13,17,18]:
            if row[i] not in ["True","False"]:raise ValueError("Item metadata Boolean encoding mismatch")
            row[i]=row[i]=="True"
        for i in [14,19]:row[i]=json.loads(row[i])
        result.append(row)
    return result


def extract():
    jars,release=verified_classpath();cases=inputs();records,execution=run_java(cases,jars);organized,rows,items=organize(records,cases)
    runtime=subprocess.run([str(JAVA),"-version"],check=True,capture_output=True,text=True)
    metadata={"schema_version":1,"pin":"26.3","purpose":"Official Java defaults and bounded primitive stack observations; no inventory-click/UI or gameplay parity claim", "confidence":"high for observed pinned calls; world/entity/codec coverage remains bounded", "server_bundle_sha256":release["server_bundle"]["sha256"],"server_class_jar_sha256":release["server_bundle"]["nested_server_sha256"],"runtime_version":(runtime.stdout+runtime.stderr).strip().splitlines(),"runtime_executable":fingerprint(JAVA),"source":source_inventory(jars,{item["class"]for item in items}),"java_source_sha256":hashlib.sha256(SOURCE.encode()).hexdigest(),"random_seed":SEED,"observations":organized,"observations_sha256":hashlib.sha256(canonical(organized)).hexdigest(),"metadata_table_headers":HEADERS,"singleton_fixture_isolation":"ItemStack.EMPTY raw count reset to zero and raw component patch cleared before each fixture; every other stack constructed fresh", "component_scope":"Actual initialized item defaults plus explicit typed primitive/unit/Boolean/literal-name patches; map-copy observations do not assert deep immutability of component value objects"}
    checks=validate(metadata,rows,records);write_tsv(TABLE,HEADERS,rows);metadata["table"]=fingerprint(TABLE);write_json(JSON_PATH,metadata)
    evidence={"status":"passed","reference":fingerprint(JSON_PATH),"table":fingerprint(TABLE),"execution":execution,"validation":checks,"commands":["python3 tools/reference_item_probe.py","python3 tools/reference_item_probe.py --verify-existing","python3 tools/reference_item_probe.py --selftest"]};write_json(ROOT/"evidence/reference_item_probe.json",evidence);return evidence


def verify_existing():
    jars,release=verified_classpath();metadata=json.loads(JSON_PATH.read_text());rows=read_rows()
    if metadata["table"]!=fingerprint(TABLE):raise ValueError("Item metadata table checksum mismatch")
    if metadata["server_class_jar_sha256"]!=release["server_bundle"]["nested_server_sha256"] or metadata["runtime_executable"]!=fingerprint(JAVA):raise ValueError("Item source/runtime artifact mismatch")
    if metadata["java_source_sha256"]!=hashlib.sha256(SOURCE.encode()).hexdigest():raise ValueError("Item Java helper source mismatch")
    if metadata["source"]!=source_inventory(jars,{row[2]for row in rows}):raise ValueError("Item named class/declaration hash mismatch")
    records=[json.loads(line) for line in (ROOT/"reference/cache/item-observed.jsonl").read_text().splitlines()];checks=validate(metadata,rows,records)
    evidence={"status":"passed","reference":fingerprint(JSON_PATH),"table":fingerprint(TABLE),"validation":checks,"official_artifact_and_library_hashes_checked":True};write_json(ROOT/"evidence/reference_item_validation.json",evidence);return evidence


def selftest():
    jars,_=verified_classpath();metadata=json.loads(JSON_PATH.read_text());rows=read_rows();first,_=run_java(inputs(),jars,"-selftest1");second,_=run_java(inputs(),jars,"-selftest2")
    validate(metadata,rows,first);validate(metadata,rows,second)
    if organize(first,inputs())[:2]!=organize(second,inputs())[:2]:raise ValueError("Item Java observations not reproducible")
    failures=[]
    def reject(label,m,r,reseal):
        if reseal:m["observations_sha256"]=hashlib.sha256(canonical(m["observations"])).hexdigest()
        try:validate(m,r,first)
        except(ValueError,IndexError)as e:failures.append({"case":label,"resealed_observation_checksum":reseal,"rejected":True,"reason":str(e)})
        else:raise ValueError("Malformed item evidence accepted")
    changed=copy.deepcopy(metadata);s=next(s for s in changed["observations"]["stack_snapshots"]if s["stored_count_i32_bits"]!="ffffffff");s["stored_count_i32_bits"]="ffffffff";reject("wrong_signed_count_bits",changed,rows,False);reject("wrong_signed_count_bits",changed,rows,True)
    changed_rows=copy.deepcopy(rows);changed_rows[1][4]=63;reject("wrong_default_stack_limit",copy.deepcopy(metadata),changed_rows,True)
    changed=copy.deepcopy(metadata);changed["observations"]["component_values"][0]["type_id"]=121;v=changed["observations"]["component_values"][0];v["sha256"]=hashlib.sha256(canonical({k:x for k,x in v.items()if k!="sha256"})).hexdigest();reject("wrong_component_type_with_resealed_value",changed,rows,True)
    evidence={"status":"passed","reference":fingerprint(JSON_PATH),"table":fingerprint(TABLE),"independent_java_runs":2,"items_per_run":len(rows),"cases_per_run":len(inputs()),"organized_observations_reproduced_exactly":True,"failure_injection":failures,"scope":"Reference generation/integrity; no Bend comparison"};write_json(ROOT/"evidence/reference_item_selftest.json",evidence);return evidence


def main():
    p=argparse.ArgumentParser(description=__doc__);g=p.add_mutually_exclusive_group();g.add_argument("--verify-existing",action="store_true");g.add_argument("--selftest",action="store_true");a=p.parse_args();r=selftest()if a.selftest else verify_existing()if a.verify_existing else extract();print(json.dumps({"status":r["status"],"items":r.get("items_per_run",r.get("validation",{}).get("items")),"cases":r.get("cases_per_run",r.get("validation",{}).get("cases"))},sort_keys=True))


if __name__=="__main__":main()
