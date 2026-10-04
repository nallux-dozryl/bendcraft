#!/usr/bin/env python3
"""Pinned normal-player inventory observations; no host inventory implementation.

--prepare checks artifacts and emits the exact proposed command without Java.
--mode extract/reproduce each launches exactly one bounded Java source process.
No installed accounts, options, worlds, saves, or foreground UI are accessed.
"""
from __future__ import annotations

import argparse
import base64
import collections
import hashlib
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import time
import zipfile

from reference_inventory import ROOT, INSTALL, JAVA, canonical, fingerprint, write_json
from reference_model_probe import CLIENT, META
import reference_local_input_probe as LI

RAW = ROOT / "build/player-inventory-reference"
OUTPUT = ROOT / "reference/player_inventory.json"
FIXTURE = "net.minecraft.fixture.PlayerInventoryReceiverFixture"
FROZEN_LI = "42ad844c7ee3616286ce99bcea00c6bc0710b20888912b6e98c1b4af6072a56e"
ITEMS = ["minecraft:stone", "minecraft:dirt", "minecraft:oak_planks"]
SELECTED_METHODS = {
    "net.minecraft.world.entity.player.Inventory": {
        "<init>", "getSelectedSlot", "setSelectedSlot", "getSelectedItem", "setSelectedItem",
        "getSelectionSize", "getNonEquipmentItems", "isHotbarSlot", "removeItem", "setItem",
        "getContainerSize", "getItem", "save", "load", "setChanged", "getTimesChanged",
    },
    "net.minecraft.world.inventory.Slot": {
        "<init>", "safeInsert", "safeTake", "tryRemove", "remove", "onTake", "setChanged",
        "getMaxStackSize", "mayPlace", "allowModification",
    },
    "net.minecraft.world.entity.player.Abilities": {
        "<init>", "getFlyingSpeed", "getWalkingSpeed", "pack", "apply",
    },
    "net.minecraft.world.entity.player.Abilities$Packed": {"<init>", "<clinit>"},
    "net.minecraft.world.ContainerHelper": {"removeItem"},
    "net.minecraft.world.level.GameType": {"updatePlayerAbilities"},
    "net.minecraft.world.item.ItemStack": {"split", "grow", "shrink", "getCount", "setCount"},
}
CLOSE_METHODS = {
    **SELECTED_METHODS,
    "net.minecraft.world.entity.player.Inventory": SELECTED_METHODS["net.minecraft.world.entity.player.Inventory"] |
        {"placeItemBackInInventory", "getSlotWithRemainingSpace", "getFreeSlot", "add", "addResource", "hasRemainingSpaceForItem"},
    "net.minecraft.world.inventory.AbstractContainerMenu": {"removed", "clearContainer", "getCarried", "setCarried"},
    "net.minecraft.world.inventory.InventoryMenu": {"<init>", "removed"},
    "net.minecraft.world.inventory.AbstractCraftingMenu": {"<init>"},
    "net.minecraft.world.entity.LivingEntity": {"drop"},
    "net.minecraft.util.Prediction": {"<clinit>", "shouldPredict"},
}


def sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def pin(path: Path) -> dict:
    return {"path": str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path),
            **fingerprint(path)}


def verified_classpath() -> tuple[list[Path], dict]:
    """Same pinned library checks as model probe, deliberately no java -version."""
    release = json.loads((ROOT / "reference/release.json").read_text())
    if release["pin"] != "26.3" or fingerprint(CLIENT)["sha256"] != release["client"]["sha256"]:
        raise ValueError("Pinned client mismatch")
    if sha(META.read_bytes()) != "9a7b39dae3b9c8d30006b650e357aae220629b7852fa0fc7221db7a8646bd5e4":
        raise ValueError("Pinned metadata mismatch")
    version = json.loads(META.read_text())
    paths, libraries, missing = [CLIENT], [], []
    for lib in version["libraries"]:
        artifact = lib["downloads"]["artifact"]
        path = INSTALL / "libraries" / artifact["path"]
        if not path.is_file():
            if not any(s in artifact["path"] for s in
                       ["natives-linux", "natives-windows", "-linux-aarch_64.jar", "-linux-x86_64.jar"]):
                raise ValueError("Required client library missing: " + artifact["path"])
            missing.append(artifact["path"])
            continue
        value = fingerprint(path)
        if value["sha1"] != artifact["sha1"] or value["bytes"] != artifact["size"]:
            raise ValueError("Official library mismatch: " + artifact["path"])
        paths.append(path)
        libraries.append({"path": artifact["path"], **value})
    return paths, {"client": pin(CLIENT), "metadata": pin(META), "libraries": libraries,
                   "missing_other_platform_natives": missing, "java_executable": pin(JAVA),
                   "java_version_command_executed": False}


def class_inventory(data: bytes, selected: set[str]) -> dict:
    """Read classfile declarations/code bytes directly, without javap or a JVM."""
    if data[:4] != b"\xca\xfe\xba\xbe":
        raise ValueError("Not a classfile")
    offset = 8

    def take(size: int) -> bytes:
        nonlocal offset
        value = data[offset:offset + size]
        if len(value) != size:
            raise ValueError("Truncated classfile")
        offset += size
        return value

    def u1() -> int:
        return take(1)[0]

    def u2() -> int:
        return struct.unpack(">H", take(2))[0]

    def u4() -> int:
        return struct.unpack(">I", take(4))[0]

    pool, index = [None] * u2(), 1
    while index < len(pool):
        kind = u1()
        if kind == 1:
            # Identifiers/descriptors below use ASCII; arbitrary modified UTF-8
            # strings are retained as bytes and never treated as instructions.
            pool[index] = take(u2())
        elif kind in (3, 4):
            pool[index] = take(4)
        elif kind in (5, 6):
            pool[index] = take(8)
            index += 1
        elif kind in (7, 8, 16, 19, 20):
            pool[index] = u2()
        elif kind in (9, 10, 11, 12, 17, 18):
            pool[index] = (u2(), u2())
        elif kind == 15:
            take(3)
        else:
            raise ValueError(f"Unknown constant pool type {kind}")
        index += 1

    def text(index: int) -> str:
        return pool[index].decode("ascii")

    u2(), u2(), u2()
    take(2 * u2())

    def members(methods: bool) -> list[dict]:
        values = []
        for _ in range(u2()):
            flags, name, descriptor = u2(), text(u2()), text(u2())
            attributes = {}
            for _ in range(u2()):
                key = text(u2())
                attributes[key] = take(u4())
            value = {"name": name, "descriptor": descriptor, "access_flags": flags}
            if methods:
                if name not in selected:
                    continue
                code = attributes.get("Code")
                if code is not None:
                    length = struct.unpack_from(">I", code, 4)[0]
                    bytecode = code[8:8 + length]
                    value.update({"code_attribute_sha256": sha(code), "bytecode_sha256": sha(bytecode),
                                  "bytecode_hex": bytecode.hex()})
            elif "ConstantValue" in attributes:
                constant = pool[struct.unpack(">H", attributes["ConstantValue"])[0]]
                value["constant_bytes_hex"] = constant.hex() if isinstance(constant, bytes) else constant
            values.append(value)
        return values

    fields, methods = members(False), members(True)
    for _ in range(u2()):
        u2()
        take(u4())
    if offset != len(data):
        raise ValueError("Trailing classfile bytes")
    return {"class_sha256": sha(data), "bytes": len(data),
            "major_version": struct.unpack_from(">H", data, 6)[0], "fields": fields, "methods": methods}


def source_inventory(methods=SELECTED_METHODS) -> dict:
    with zipfile.ZipFile(CLIENT) as jar:
        return {name: {"entry": name.replace(".", "/") + ".class",
                       **class_inventory(jar.read(name.replace(".", "/") + ".class"), selected)}
                for name, selected in methods.items()}


def inputs() -> list[dict]:
    cases = [{"id": "default", "operation": "default"}]
    for slot in [-2147483648, -1, 0, 1, 6, 8, 9, 35, 2147483647]:
        cases.append({"id": f"select:{slot}", "operation": "select", "slot": slot})
    for item in ITEMS:
        for amount in [0, 1, 7, 17, 64, 65]:
            cases.append({"id": f"remove:{item}:{amount}", "operation": "remove",
                          "item": item, "count": 17, "amount": amount})
        for amount in [63, 64, 65]:
            cases.append({"id": f"remove-full:{item}:{amount}", "operation": "remove",
                          "item": item, "count": 64, "amount": amount})
        for destination in [None, {"item": item, "count": 1}, {"item": item, "count": 63},
                            {"item": item, "count": 64},
                            {"item": ITEMS[(ITEMS.index(item) + 1) % len(ITEMS)], "count": 5}]:
            label = "empty" if destination is None else destination["item"] + ":" + str(destination["count"])
            for amount in [0, 1, 7, 64, 65]:
                cases.append({"id": f"insert:{item}:{label}:{amount}", "operation": "insert",
                              "item": item, "count": 17, "amount": amount,
                              "destination": destination})
        for destination in [None, {"item": item, "count": 63}]:
            label = "empty" if destination is None else "63"
            cases.append({"id": f"insert-full:{item}:{label}", "operation": "insert",
                          "item": item, "count": 64, "amount": 64, "destination": destination})
    for operation in ["remove_empty", "insert_empty"]:
        cases.append({"id": operation, "operation": operation})
    for mode in ["SURVIVAL", "CREATIVE", "ADVENTURE", "SPECTATOR"]:
        cases.append({"id": "abilities:" + mode, "operation": "abilities", "mode": mode})
    cases.append({"id": "save-load:populated", "operation": "save_load"})
    return cases


JAVA_SOURCE = r'''
package net.minecraft.fixture;
import java.io.*;
import java.util.*;
import com.google.gson.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.data.registries.VanillaRegistries;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.world.entity.player.Abilities;
import net.minecraft.world.inventory.Slot;
import net.minecraft.world.item.*;
import net.minecraft.world.level.GameType;
import net.minecraft.world.level.storage.*;
import net.minecraft.resources.Identifier;
import net.minecraft.nbt.*;
import net.minecraft.util.ProblemReporter;
public class PlayerInventoryReceiverFixture {
 static final Gson JSON=new GsonBuilder().serializeNulls().create();
 static final PrintStream OUT=System.out;
 static String bits(float v){return LocalInputReceiverFixture.bits(v);}
 static void output(Object v){OUT.println("PLAYER_INVENTORY_JSON:"+JSON.toJson(v));}
 static ItemStack stack(String item,int count){return new ItemStack(BuiltInRegistries.ITEM.getValue(Identifier.parse(item)),count);}
 static Map<String,Object> stackState(ItemStack s)throws Exception{
  Map<String,Object> m=new TreeMap<>();Holder<?> item=(Holder<?>)LocalInputReceiverFixture.read(s,"item");
  m.put("stored_item",item==null?null:BuiltInRegistries.ITEM.getKey((Item)item.value()).toString());
  m.put("stored_count",LocalInputReceiverFixture.read(s,"count"));m.put("visible_item",BuiltInRegistries.ITEM.getKey(s.getItem()).toString());
  m.put("visible_count",s.getCount());m.put("empty",s.isEmpty());m.put("canonical_empty",s==ItemStack.EMPTY);
  m.put("max_stack_size",s.getMaxStackSize());return m;
 }
 static Map<String,Object> abilities(Abilities a){
  return Map.of("invulnerable",a.invulnerable,"flying",a.flying,"mayfly",a.mayfly,"instabuild",a.instabuild,
   "maybuild",a.mayBuild,"flying_speed_f32_bits",bits(a.getFlyingSpeed()),"walking_speed_f32_bits",bits(a.getWalkingSpeed()));
 }
 static Map<String,Object> state(LocalPlayer p)throws Exception{
  var i=p.getInventory();List<Object> slots=new ArrayList<>();for(int n=0;n<36;n++){ItemStack s=i.getItem(n);slots.add(s.isEmpty()?null:Map.of("item",BuiltInRegistries.ITEM.getKey(s.getItem()).toString(),"count",s.getCount()));}
  Map<String,Object> m=new TreeMap<>();m.put("selected",i.getSelectedSlot());m.put("selection_size",i.getSelectionSize());m.put("main_length",i.getNonEquipmentItems().size());
  m.put("container_size",i.getContainerSize());m.put("main_slots",slots);m.put("selected_item",stackState(i.getSelectedItem()));m.put("times_changed",i.getTimesChanged());m.put("abilities",abilities(p.getAbilities()));return m;
 }
 static Object typed(Tag tag){
  if(tag==null)return null;Map<String,Object> m=new TreeMap<>();m.put("type",tag.getId());switch(tag.getId()){
   case 1,2,3,4 -> m.put("value",((NumericTag)tag).longValue());case 5 -> m.put("bits",bits(((NumericTag)tag).floatValue()));
   case 8 -> m.put("value",tag.asString().orElseThrow());case 9 -> {List<Object> a=new ArrayList<>();for(Tag t:(ListTag)tag)a.add(typed(t));m.put("items",a);}
   case 10 -> {Map<String,Object> entries=new TreeMap<>();((CompoundTag)tag).forEach((k,v)->entries.put(k,typed(v)));m.put("entries",entries);}
   default -> throw new IllegalArgumentException("Unexpected focused projection tag type "+tag.getId());
  }return m;
 }
 static CompoundTag save(LocalPlayer p,HolderLookup.Provider lookup,List<Object> problems){var reporter=new ProblemReporter.Collector();var output=TagValueOutput.createWithContext(reporter,lookup);p.saveWithoutId(output);reporter.forEach((path,problem)->problems.add(Map.of("path",path,"problem",problem.toString())));return output.buildResult();}
 static Object focusedSave(CompoundTag saved)throws Exception{
  CompoundTag projection=new CompoundTag();for(String key:List.of("Inventory","SelectedItemSlot","abilities"))projection.put(key,saved.get(key).copy());
  var bytes=new ByteArrayOutputStream();NbtIo.write(projection,new DataOutputStream(bytes));byte[] wire=bytes.toByteArray();
  if(wire.length>65536)throw new AssertionError("Fixture projection exceeds 64KiB");CompoundTag readback=NbtIo.read(new DataInputStream(new ByteArrayInputStream(wire)),NbtAccounter.create(1048576));
  return Map.of("typed_tags",typed(projection),"physical_nbt_base64",Base64.getEncoder().encodeToString(wire),"physical_nbt_bytes",wire.length,"readback_typed_tags",typed(readback));
 }
 static Map<String,Object> failure(Throwable e){List<Object> chain=new ArrayList<>();Throwable root=e;while(root!=null){chain.add(Map.of("class",root.getClass().getName(),"message",String.valueOf(root.getMessage())));if(root.getCause()==null)break;root=root.getCause();}return Map.of("chain",chain,"root_class",root.getClass().getName(),"root_message",String.valueOf(root.getMessage()));}
 public static void run(String ignored)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();HolderLookup.Provider lookup=VanillaRegistries.createWorldLookup();
  for(var pending:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup))pending.forEach((holder,components)->holder.bindComponents(components));
  JsonArray cases=JsonParser.parseString(new String(Base64.getDecoder().decode(__INPUT__),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonArray();
  for(JsonElement entry:cases){JsonObject in=entry.getAsJsonObject();String operation=in.get("operation").getAsString();var c=new LocalInputReceiverFixture.Context(lookup,false);LocalPlayer p=c.player;var inventory=p.getInventory();
   Map<String,Object> row=new TreeMap<>();row.put("id",in.get("id").getAsString());row.put("operation",operation);row.put("input",in);boolean ok=false;
   try{
    if(operation.equals("select")){inventory.setItem(0,stack("minecraft:stone",3));inventory.setItem(8,stack("minecraft:dirt",4));inventory.setItem(35,stack("minecraft:oak_planks",5));inventory.setSelectedSlot(6);}
    if(operation.equals("remove")||operation.equals("insert"))inventory.setItem(1,stack(in.get("item").getAsString(),in.get("count").getAsInt()));
    if(operation.equals("insert")&&!in.get("destination").isJsonNull()){var destination=in.getAsJsonObject("destination");inventory.setItem(34,stack(destination.get("item").getAsString(),destination.get("count").getAsInt()));}
    if(operation.equals("save_load")){inventory.setItem(0,stack("minecraft:stone",64));inventory.setItem(8,stack("minecraft:dirt",17));inventory.setItem(9,stack("minecraft:oak_planks",63));inventory.setItem(35,stack("minecraft:stone",1));inventory.setSelectedSlot(8);GameType.CREATIVE.updatePlayerAbilities(p.getAbilities());LocalInputReceiverFixture.seed(p,"enchantmentSeed",263);}
    row.put("before",state(p));
    switch(operation){
     case "default" -> {row.put("fresh_abilities",abilities(new Abilities()));List<Object> problems=new ArrayList<>();row.put("saved",focusedSave(save(p,lookup,problems)));row.put("save_problems",problems);}
     case "select" -> {int selected=in.get("slot").getAsInt();row.put("is_hotbar_slot",inventory.isHotbarSlot(selected));inventory.setSelectedSlot(selected);}
     case "remove","remove_empty" -> {row.put("source_before",stackState(inventory.getItem(1)));ItemStack removed=inventory.removeItem(1,operation.equals("remove")?in.get("amount").getAsInt():1);row.put("result",stackState(removed));row.put("source_after",stackState(inventory.getItem(1)));}
     case "insert","insert_empty" -> {ItemStack source=inventory.getItem(1);row.put("source_before",stackState(source));row.put("destination_before",stackState(inventory.getItem(34)));ItemStack result=new Slot(inventory,34,0,0).safeInsert(source,operation.equals("insert")?in.get("amount").getAsInt():1);row.put("result",stackState(result));row.put("result_is_source",result==source);row.put("source_after",stackState(inventory.getItem(1)));row.put("destination_after",stackState(inventory.getItem(34)));}
     case "abilities" -> {GameType.valueOf(in.get("mode").getAsString()).updatePlayerAbilities(p.getAbilities());List<Object> problems=new ArrayList<>();row.put("saved",focusedSave(save(p,lookup,problems)));row.put("save_problems",problems);}
     case "save_load" -> {List<Object> problems=new ArrayList<>();CompoundTag saved=save(p,lookup,problems);row.put("saved",focusedSave(saved));row.put("save_problems",problems);var target=new LocalInputReceiverFixture.Context(lookup,false).player;row.put("target_before",state(target));var reporter=new ProblemReporter.Collector();target.load(TagValueInput.create(reporter,lookup,saved));List<Object> loadProblems=new ArrayList<>();reporter.forEach((path,problem)->loadProblems.add(Map.of("path",path,"problem",problem.toString())));row.put("load_problems",loadProblems);row.put("target_after",state(target));List<Object> resaveProblems=new ArrayList<>();row.put("resaved",focusedSave(save(target,lookup,resaveProblems)));row.put("resave_problems",resaveProblems);}
     default -> throw new IllegalArgumentException("Unknown fixture operation "+operation);
    }ok=true;
   }catch(Throwable error){row.put("error",failure(error));}
   row.put("ok",ok);row.put("after",state(p));output(row);
  }
 }
}
'''


def close_inputs() -> list[dict]:
    def case(name, main=None, carried=None, craft=None, offhand=None, creative=False, operation="return"):
        return {"id": name, "operation": operation, "main": main or {}, "selected": 7,
                "carried": carried, "craft": craft or [None] * 4, "offhand": offhand,
                "creative": creative}
    stack = lambda item, count: {"item": "minecraft:" + item, "count": count}
    full = {str(n): stack("dirt", 64) for n in range(36)}
    cases = []
    for creative in [False, True]:
        suffix = ":creative" if creative else ":survival"
        cases.extend([
            case("empty" + suffix, creative=creative),
            case("first-empty" + suffix, {"0": stack("dirt", 64)}, stack("stone", 17), creative=creative),
            case("merge-before-empty" + suffix, {"5": stack("stone", 61)}, stack("stone", 7), creative=creative),
            case("selected-offhand-main" + suffix, {"0": stack("stone", 61), "7": stack("stone", 63)},
                 stack("stone", 10), offhand=stack("stone", 60), creative=creative),
            case("offhand-before-main" + suffix, {"0": stack("stone", 60)}, stack("stone", 8),
                 offhand=stack("stone", 62), creative=creative),
            case("full" + suffix, full, stack("stone", 17), creative=creative),
            case("partial-only-room" + suffix, {**full, "12": stack("stone", 63)}, stack("stone", 17), creative=creative),
            case("stack-limit16" + suffix, {"5": stack("ender_pearl", 15)}, stack("ender_pearl", 16), creative=creative),
            case("stack-limit1" + suffix, {"5": stack("shield", 1)}, stack("shield", 1), creative=creative),
            case("menu-order" + suffix, carried=stack("dirt", 1),
                 craft=[stack("stone", 2), stack("stone", 3), stack("dirt", 4), stack("oak_planks", 5)],
                 creative=creative, operation="removed"),
            case("menu-full" + suffix, full, stack("stone", 17),
                 [stack("stone", 2), stack("dirt", 3), stack("oak_planks", 4), None],
                 creative=creative, operation="removed"),
            case("return-order" + suffix, carried=stack("dirt", 1),
                 craft=[stack("stone", 2), stack("stone", 3), stack("dirt", 4), stack("oak_planks", 5)],
                 creative=creative, operation="return_sequence"),
            case("return-full" + suffix, {**full, "12": stack("stone", 63)}, stack("stone", 17),
                 [stack("stone", 2), stack("dirt", 3), stack("oak_planks", 4), None],
                 creative=creative, operation="return_sequence"),
        ])
    return cases


CLOSE_JAVA_SOURCE = JAVA_SOURCE[:JAVA_SOURCE.index(" public static void run(String ignored)")] + r'''
 static Object closeState(LocalPlayer p)throws Exception{
  Map<String,Object> m=new TreeMap<>();m.put("inventory",state(p));
  List<Object> equipment=new ArrayList<>();for(int n=36;n<43;n++)equipment.add(stackState(p.getInventory().getItem(n)));
  List<Object> craft=new ArrayList<>();for(int n=1;n<=4;n++)craft.add(stackState(p.inventoryMenu.getSlot(n).getItem()));
  m.put("equipment",equipment);m.put("craft",craft);m.put("carried",stackState(p.inventoryMenu.getCarried()));return m;
 }
 static ItemStack inputStack(JsonElement element){return element==null||element.isJsonNull()?ItemStack.EMPTY:stack(element.getAsJsonObject().get("item").getAsString(),element.getAsJsonObject().get("count").getAsInt());}
 public static void run(String ignored)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();HolderLookup.Provider lookup=VanillaRegistries.createWorldLookup();
  for(var pending:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup))pending.forEach((holder,components)->holder.bindComponents(components));
  var disassembly=new StringWriter();var diagnostics=new StringWriter();
  int disassemblyStatus=java.util.spi.ToolProvider.findFirst("javap").orElseThrow().run(new PrintWriter(disassembly),new PrintWriter(diagnostics),"-c","-p","-classpath",System.getProperty("java.class.path"),"net.minecraft.world.entity.player.Inventory","net.minecraft.world.inventory.AbstractContainerMenu","net.minecraft.world.inventory.InventoryMenu");
  OUT.println("PLAYER_INVENTORY_CLOSE_BYTECODE:"+JSON.toJson(Map.of("status",disassemblyStatus,"stdout",disassembly.toString(),"stderr",diagnostics.toString())));
  JsonArray cases=JsonParser.parseString(new String(Base64.getDecoder().decode(__INPUT__),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonArray();
  for(JsonElement entry:cases){JsonObject in=entry.getAsJsonObject();String operation=in.get("operation").getAsString();var c=new LocalInputReceiverFixture.Context(lookup,false);LocalPlayer p=c.player;var inventory=p.getInventory();
   for(var item:in.getAsJsonObject("main").entrySet())inventory.setItem(Integer.parseInt(item.getKey()),inputStack(item.getValue()));
   inventory.setItem(40,inputStack(in.get("offhand")));inventory.setSelectedSlot(in.get("selected").getAsInt());
   p.getAbilities().instabuild=in.get("creative").getAsBoolean();p.inventoryMenu.setCarried(inputStack(in.get("carried")));
   net.minecraft.world.Container crafting=(net.minecraft.world.Container)LocalInputReceiverFixture.read(p.inventoryMenu,"craftSlots");
   for(int n=0;n<4;n++)crafting.setItem(n,inputStack(in.getAsJsonArray("craft").get(n)));
   Map<String,Object> row=new TreeMap<>();row.put("id",in.get("id").getAsString());row.put("operation",operation);row.put("input",in);row.put("before",closeState(p));boolean ok=false;
   try{
    if(operation.equals("return"))inventory.placeItemBackInInventory(p.inventoryMenu.getCarried(),false,net.minecraft.util.Prediction.SERVER_ONLY);
    else if(operation.equals("return_sequence")){
     List<Object> steps=new ArrayList<>();inventory.placeItemBackInInventory(p.inventoryMenu.getCarried(),false,net.minecraft.util.Prediction.SERVER_ONLY);steps.add(closeState(p));
     for(int n=0;n<4;n++){inventory.placeItemBackInInventory(crafting.getItem(n),false,net.minecraft.util.Prediction.SERVER_ONLY);steps.add(closeState(p));}row.put("returned_steps",steps);
    }
    else if(operation.equals("removed"))p.inventoryMenu.removed(p);
    else throw new IllegalArgumentException(operation);
    ok=true;
   }catch(Throwable error){row.put("error",failure(error));}
   row.put("ok",ok);row.put("after",closeState(p));output(row);
  }
 }
}
'''


def prepared(profile="inventory") -> dict:
    if sha(Path(LI.__file__).read_bytes()) != FROZEN_LI:
        raise ValueError("Frozen normal-receiver fixture changed")
    paths, provenance = verified_classpath()
    close = profile == "menu-close"
    cases = close_inputs() if close else inputs()
    sources = LI.receiver_sources({})
    sources[FIXTURE] = (CLOSE_JAVA_SOURCE if close else JAVA_SOURCE).replace("__INPUT__", LI.java_string(base64.b64encode(canonical(cases)).decode()))
    if "Unsafe" in "\n".join(sources.values()):
        raise ValueError("Unexpected unsafe fixture allocation")
    payload = {"sources": sources, "client_jar": str(CLIENT), "mode": "player-inventory"}
    launcher = LI.RECEIVER_LAUNCHER.replace("net.minecraft.fixture.LocalInputReceiverFixture", FIXTURE, 1)
    launcher = launcher.replace("Base64.getDecoder().decode(args[0])",
        "Base64.getDecoder().decode(" + LI.java_string(base64.b64encode(canonical(payload)).decode()) + ")", 1)
    command = [str(JAVA), "-Xmx512m", "--source", "25", "--class-path",
               os.pathsep.join(map(str, paths)), "/dev/stdin"]
    return {"cases": cases, "sources": sources, "launcher": launcher, "command": command,
            "provenance": provenance, "source_inventory": source_inventory(CLOSE_METHODS if close else SELECTED_METHODS),
            "profile": profile, "timeout_seconds": 60 if close else 120}


def observe(preparation: dict, label: str) -> dict:
    RAW.mkdir(parents=True, exist_ok=True)
    launcher = preparation["launcher"]
    started = time.monotonic()
    run_id = f"{label}-{time.time_ns()}"
    process = subprocess.Popen(preparation["command"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, start_new_session=True, cwd=RAW)
    timeout = preparation.get("timeout_seconds", 120)
    print(json.dumps({"java_pid": process.pid, "label": label, "timeout_seconds": timeout,
                      "java_processes_this_invocation": 1}), flush=True)
    try:
        stdout, stderr = process.communicate(launcher, timeout=timeout)
    except BaseException as error:
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        stdout, stderr = process.communicate(timeout=10)
        write_json(RAW / (run_id + ".interrupted.json"), {**preparation, "stdout": stdout,
                   "stderr": stderr, "pid": process.pid, "returncode": process.returncode,
                   "interruption_class": type(error).__name__,
                   "elapsed_seconds": round(time.monotonic() - started, 6)})
        if isinstance(error, subprocess.TimeoutExpired):
            raise RuntimeError(f"{timeout}-second inventory reference bound expired") from error
        raise
    raw = RAW / (run_id + ".full.json")
    artifact = {**preparation, "stdout": stdout, "stderr": stderr, "returncode": process.returncode,
                "pid": process.pid, "elapsed_seconds": round(time.monotonic() - started, 6)}
    # Capture diagnostics before parsing any sentinels. A malformed output must
    # retain its sources/command/stdout/stderr instead of disappearing.
    write_json(raw, artifact)
    rows = [json.loads(line.removeprefix("PLAYER_INVENTORY_JSON:")) for line in stdout.splitlines()
            if line.startswith("PLAYER_INVENTORY_JSON:")]
    loaded = [json.loads(line.removeprefix("LOCAL_INPUT_CLASSES:")) for line in stdout.splitlines()
              if line.startswith("LOCAL_INPUT_CLASSES:")]
    write_json(raw, {**artifact, "observations": rows, "loaded_official": loaded})
    if process.returncode != 0:
        raise RuntimeError(f"Official receiver fixture failed ({process.returncode}); see {raw}: {stderr[-5000:]}")
    if len(loaded) != 1 or len(rows) != len(preparation["cases"]):
        raise ValueError(f"Incomplete oracle records: {raw}")
    with zipfile.ZipFile(CLIENT) as jar:
        for name, digest in loaded[0].items():
            if digest != sha(jar.read(name.replace(".", "/") + ".class")):
                raise ValueError("Loaded official class mismatch: " + name)
    required = [*SELECTED_METHODS, "net.minecraft.client.player.LocalPlayer",
                "net.minecraft.world.entity.player.Player", "net.minecraft.client.multiplayer.ClientLevel"]
    if preparation.get("profile") == "menu-close":
        required = ["net.minecraft.world.entity.player.Inventory", "net.minecraft.world.inventory.InventoryMenu",
                    "net.minecraft.world.inventory.AbstractContainerMenu", "net.minecraft.world.item.ItemStack",
                    "net.minecraft.client.player.LocalPlayer", "net.minecraft.world.entity.player.Player",
                    "net.minecraft.client.multiplayer.ClientLevel", "net.minecraft.util.Prediction"]
    for name in required:
        if name not in loaded[0]:
            raise ValueError("Critical official class not loaded: " + name)
    return {"observations": rows, "loaded_official_classes": loaded[0], "raw_artifact": pin(raw),
            "execution": {"command": preparation["command"], "pid": process.pid,
                "returncode": process.returncode, "elapsed_seconds": round(time.monotonic() - started, 6),
                "stdout_sha256": sha(stdout.encode()), "stderr_sha256": sha(stderr.encode())}}


def collect_close(mode: str) -> None:
    preparation = prepared("menu-close")
    run = observe(preparation, "menu-close-" + mode)
    rows, loaded = run["observations"], run["loaded_official_classes"]
    for row, case in zip(rows, preparation["cases"], strict=True):
        if row["input"] != case or row["id"] != case["id"] or row["operation"] != case["operation"]:
            raise ValueError("Menu-close receiver input/order differs")
    raw = json.loads((ROOT / run["raw_artifact"]["path"]).read_text())
    disassembly = [json.loads(line.removeprefix("PLAYER_INVENTORY_CLOSE_BYTECODE:"))
                   for line in raw["stdout"].splitlines() if line.startswith("PLAYER_INVENTORY_CLOSE_BYTECODE:")]
    if len(disassembly) != 1 or disassembly[0]["status"] != 0:
        raise ValueError("Pinned in-process menu-close disassembly unavailable")
    stable = {"pin": "26.3", "evidence_format": "normal-player-menu-close-v1",
              "producer": pin(Path(__file__)), "inputs": preparation["cases"],
              "inputs_sha256": sha(canonical(preparation["cases"])), "observations": rows,
              "observations_sha256": sha(canonical(rows)), "source_inventory": preparation["source_inventory"],
              "provenance": preparation["provenance"], "fixture_sources_sha256":
                  {name: sha(source.encode()) for name, source in preparation["sources"].items()},
              "launcher_source_sha256": sha(preparation["launcher"].encode()),
              "loaded_official_classes": {"count": len(loaded), "all_verified_against_client_jar": True,
                  "complete_map_sha256": sha(canonical(loaded)),
                  "selected": {name: loaded[name] for name in CLOSE_METHODS if name in loaded}},
              "disassembly": disassembly[0],
              "boundary": {"receivers": "Untouched official Inventory.placeItemBackInInventory and InventoryMenu.removed on normally constructed LocalPlayer",
                  "prediction": "Direct return uses SERVER_ONLY and sendPacket=False; actual removed chooses its own behavior",
                  "return_sequence": "Calls untouched Inventory return receiver carried then craft0..3, as verified in exact server removal bytecode; source references retained because no ServerPlayer/drop ownership receiver executes here",
                  "world_context": "Frozen normal LocalInput air/stone ClientLevel fixture, no ServerPlayer/server-world lifecycle",
                  "inventory": "All43 durable slots plus actual four craft inputs and carried receiver state",
                  "drop": "Actual Java receiver branch only; no Bend entity/drop consumer is inferred",
                  "disassembly": "JDK javap ToolProvider runs inside the same JVM against the pinned official classpath",
                  "ui": "No game window, audio, account, installed save or session access"}}
    output = ROOT / "reference/player_inventory_close.json"
    if mode == "extract":
        write_json(output, {**stable, "raw_artifacts": [run["raw_artifact"]], "execution": run["execution"]})
    else:
        existing = json.loads(output.read_text())
        for key, value in stable.items():
            if existing[key] != value:
                raise ValueError("Menu-close fresh-process reproduction differs: " + key)
    try:
        os.killpg(run["execution"]["pid"], 0)
        absent = False
    except ProcessLookupError:
        absent = True
    receipt = {"status": "observed" if mode == "extract" else "exact fresh-process reproduction",
               "mode": mode, "reference": pin(output), "raw_artifact": run["raw_artifact"],
               "case_count": len(rows), "errors": [{"id": row["id"], "error": row["error"]} for row in rows if not row["ok"]],
               "observations_sha256": stable["observations_sha256"], "all_loaded_official_classes_verified": True,
               "loaded_official_classes": len(loaded), "execution": run["execution"], "process_group_absent": absent,
               "bounds": {"heap_mib": 512, "process_group_seconds": 60}, "java_processes": 1}
    write_json(ROOT / f"evidence/player-inventory-close-reference-{mode}.json", receipt)
    print(json.dumps(receipt, indent=2))


def collect(mode: str) -> None:
    preparation = prepared()
    run = observe(preparation, mode)
    rows, loaded = run["observations"], run["loaded_official_classes"]
    for row, case in zip(rows, preparation["cases"], strict=True):
        if row["id"] != case["id"] or row["operation"] != case["operation"] or row["input"] != case:
            raise ValueError("Oracle input/order mismatch: " + case["id"])
        expected_success = row["operation"] != "select" or 0 <= row["input"]["slot"] < 9
        if row["ok"] != expected_success:
            raise ValueError("Unexpected actual receiver success/failure: " + row["id"])
        if not expected_success and (row["error"]["root_class"] != "java.lang.IllegalArgumentException"
                                     or row["error"]["root_message"] != "Invalid selected slot"):
            raise ValueError("Unexpected selected-slot failure: " + row["id"])
        if not expected_success and (row["is_hotbar_slot"] or row["before"] != row["after"]):
            raise ValueError("Invalid selection mutated actual inventory receiver: " + row["id"])
        for key in ["save_problems", "load_problems", "resave_problems"]:
            if row.get(key):
                raise ValueError("Unexpected clean-fixture codec diagnostics: " + row["id"] + ":" + key)
    fixtures = {name: sha(value.encode()) for name, value in preparation["sources"].items()}
    stable = {"pin": "26.3", "evidence_format": "normal-player-inventory-v1", "producer": pin(Path(__file__)),
        "inputs": preparation["cases"], "inputs_sha256": sha(canonical(preparation["cases"])),
        "observations": rows, "observations_sha256": sha(canonical(rows)),
        "source_inventory": preparation["source_inventory"], "provenance": preparation["provenance"],
        "fixture_sources_sha256": fixtures, "launcher_source_sha256": sha(preparation["launcher"].encode()),
        "loaded_official_classes": {"count": len(loaded), "all_verified_against_client_jar": True,
            "complete_map_sha256": sha(canonical(loaded)),
            "selected": {name: loaded[name] for name in SELECTED_METHODS}},
        "boundary": {"normal_constructors": "Untouched official LocalPlayer, Inventory, Slot, Abilities, ClientLevel base constructor",
            "world_context": "Frozen LocalInput fixture ClientLevel subclass with declared synthetic air/stone queries",
            "external_service_substitutions": sorted(name for name in LI.RECEIVER_SOURCES
                if name != "net.minecraft.fixture.LocalInputReceiverFixture"),
            "transfer": "Direct official Slot.safeInsert(source stack, requested); no custom split/merge admission or click protocol inferred",
            "removal": "Direct official Inventory.removeItem(index 1, requested); result observed separately",
            "abilities": "Fresh default and direct actual GameType.updatePlayerAbilities; no network/server game-mode lifecycle",
            "persistence": "Actual saveWithoutId/load in memory; focused official tag projection written/read with NbtIo; no save-file operation",
            "scope": "Only 36 main slots, selected 0..8, unmodified stone/dirt/oak_planks max-stack-64 items",
            "ui": "No game client/window/audio/input/session launch", "accounts": "Fixed synthetic profile; nonexistent /dev/null options path"}}
    if mode == "extract":
        write_json(OUTPUT, {**stable, "raw_artifacts": [run["raw_artifact"]], "execution": run["execution"]})
    else:
        existing = json.loads(OUTPUT.read_text())
        for key, value in stable.items():
            if existing[key] != value:
                raise ValueError("Fresh-process reproduction mismatch: " + key)
    groups = dict(sorted(collections.Counter(row["operation"] for row in rows).items()))
    errors = [{"id": row["id"], "error": row["error"]} for row in rows if not row["ok"]]
    receipt = {"mode": mode, "status": "observed" if mode == "extract" else "exact fresh-process reproduction",
        "reference": pin(OUTPUT), "case_count": len(rows), "operation_counts": groups, "errors": errors,
        "observations_sha256": stable["observations_sha256"], "loaded_official_classes": len(loaded),
        "all_loaded_official_classes_verified": True, "raw_artifact": run["raw_artifact"],
        "execution": run["execution"], "java_processes": 1, "bounds": {"heap_mib": 512, "process_group_seconds": 120}}
    write_json(ROOT / f"evidence/player-inventory-reference-{mode}.json", receipt)
    print(json.dumps({key: receipt[key] for key in ["mode", "status", "case_count", "operation_counts",
                     "errors", "observations_sha256", "loaded_official_classes"]}, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare", action="store_true", help="Read-only preparation; launches no Java")
    parser.add_argument("--mode", choices=["extract", "reproduce"], default="extract")
    parser.add_argument("--profile", choices=["inventory", "menu-close"], default="inventory")
    args = parser.parse_args()
    if args.prepare:
        value = prepared(args.profile)
        receipt = {"status": "prepared; Java execution not performed", "producer": pin(Path(__file__)),
            "case_count": len(value["cases"]), "inputs_sha256": sha(canonical(value["cases"])),
            "fixture_sources_sha256": {name: sha(source.encode()) for name, source in value["sources"].items()},
            "launcher_source_sha256": sha(value["launcher"].encode()), "command": value["command"],
            "client": value["provenance"]["client"], "java_executable": value["provenance"]["java_executable"],
            "source_inventory": value["source_inventory"], "java_processes": 0,
            "launch_request": f"Each --mode extract/reproduce uses one allocated Java job slot for one512MiB,{value['timeout_seconds']}-second process"}
        prefix = "player-inventory-close-reference" if args.profile == "menu-close" else "player-inventory-reference"
        write_json(ROOT / f"evidence/{prefix}-preparation.json", receipt)
        print(json.dumps({key: receipt[key] for key in ["status", "case_count", "inputs_sha256", "java_processes", "launch_request"]}, indent=2))
    else:
        collect_close(args.mode) if args.profile == "menu-close" else collect(args.mode)


if __name__ == "__main__":
    main()
