#!/usr/bin/env python3
"""Pinned normal-receiver player save/load evidence; no save implementation."""
from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import struct
import subprocess
import time
import zipfile

from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_model_probe import CLIENT, verified_client_classpath
import reference_local_input_probe as LI
from reference_travel_probe import verified_classpath as verified_server_classpath

RAW = ROOT / "build/player-save"
OUTPUT = ROOT / "reference/player_save.json"
FIXTURE = "net.minecraft.fixture.PlayerSaveReceiverFixture"
FROZEN_LI = "42ad844c7ee3616286ce99bcea00c6bc0710b20888912b6e98c1b4af6072a56e"
CLASSES = [
    "net.minecraft.world.entity.Entity", "net.minecraft.world.entity.LivingEntity",
    "net.minecraft.world.entity.Avatar", "net.minecraft.world.entity.player.Player",
    "net.minecraft.client.player.AbstractClientPlayer", "net.minecraft.client.player.LocalPlayer",
    "net.minecraft.server.level.ServerPlayer",
    "net.minecraft.world.level.storage.ValueInput", "net.minecraft.world.level.storage.ValueOutput",
    "net.minecraft.world.level.storage.TagValueInput", "net.minecraft.world.level.storage.TagValueOutput",
    "net.minecraft.world.level.storage.PlayerDataStorage", "net.minecraft.nbt.NbtIo",
    "net.minecraft.world.phys.Vec3", "net.minecraft.world.phys.Vec2",
    "net.minecraft.world.entity.player.Abilities", "net.minecraft.world.food.FoodData",
    "net.minecraft.nbt.FloatTag", "net.minecraft.nbt.DoubleTag",
]
METHODS = {
    "save", "saveAsPassenger", "saveWithoutId", "load", "readAdditionalSaveData",
    "addAdditionalSaveData", "repositionEntityAfterLoad", "shouldBeSaved",
    "create", "createWithContext", "createWithoutContext", "buildResult",
    "getBooleanOr", "getDoubleOr", "getFloatOr", "getIntOr", "getShortOr",
    "getNumericTag", "getOptionalTypedTag", "setRot", "setYRot", "setXRot",
    "setOldPosAndRot", "reapplyPosition", "refreshDimensions", "saveParentVehicle",
    "saveEnderPearls", "storeGameTypes", "lambda$addAdditionalSaveData$0",
    "read", "write", "store", "storeNullable", "putDouble", "putFloat", "putBoolean",
    "valueOf", "getWalkingSpeed", "readPlayerMode", "setSleepingPos", "clearSleepingPos",
}
DEPENDENCIES = [
    "src/player_record.bend", "src/player_codec.bend", "src/player_storage.bend",
    "src/player_session.bend", "src/player_fall_history.bend", "src/local_input.bend",
    "src/player_pose.bend", "reference/player_tick_phases.json",
    "reference/player_fall_history.json", "reference/local_input.json",
    "reference/player_pose.json", "tools/reference_local_input_probe.py",
    "tools/reference_player_tick_phases_probe.py",
    "tools/reference_player_fall_history_probe.py", "tools/reference_player_pose_probe.py",
]


def sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def pin(path: Path) -> dict:
    return {"path": str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path),
            **fingerprint(path)}


def db(value: float) -> str:
    return struct.pack(">d", value).hex()


def fb(value: float) -> str:
    return struct.pack(">f", value).hex()


def vector(values: list[float]) -> list[str]:
    return list(map(db, values))


def numeric(kind: int, value) -> dict:
    return {"type": kind, "bits": value} if kind in (5, 6) else {"type": kind, "value": value}


def sequence(kind: int, values) -> dict:
    return {"type": 9, "items": [numeric(kind, v) for v in values]}


def inputs() -> dict:
    persistent = {
        "position": vector([-0., 10.25, -17.5]), "velocity": vector([.125, -.25, -0.]),
        "rotation": [fb(707.5), fb(-123.25), fb(12.5), fb(-9.5)],
        "fall_distance": db(9.125), "ground": True, "health": fb(17.5),
        "hurt_time": 7, "death_time": 3, "absorption": fb(2.25),
        "impulse_grace": 4, "impulse_position": vector([1.25, 2.5, -3.75]),
        "experience_progress": fb(.375), "experience_level": 3, "experience_total": 91,
        "food": 13,
    }
    runtime = {
        "pose": "CROUCHING", "minor_collision": True, "collisions": [True, True, True],
        "support": [-2, 0, 5], "ground_no_blocks": True, "jumping": True,
        "jump_delay": 4294967295, "jump_trigger": 2147483648, "sprint_trigger": 17,
        "input": [fb(.7), fb(-.3), fb(.2)], "keys": 37,
        "crouching_cache": True,
        "input_move": [fb(.8), fb(-.6)], "speed": fb(.3),
        "head_body_rotation": [fb(321), fb(22), fb(-21), fb(33)],
        "bob": [fb(1), fb(-2), fb(3), fb(-4)], "tick_count": 83,
        "needs_sync": False,
        "box": vector([-4., 10., -18., 5., 15., -16.]),
    }
    sentinel = {**copy.deepcopy(runtime), "position": vector([-7., 9., -11.]),
                "velocity": vector([2., -2., -.0]),
                "rotation": [fb(-71.25), fb(13.5), fb(-90), fb(45)],
                "fall_distance": db(17.125), "ground": False, "health": fb(12.5),
                "hurt_time": 99, "death_time": 1, "impulse_grace": 8,
                "impulse_position": vector([-7., 8., -9.]), "tick_count": 123}
    saves = [
        {"id": "default", "initial": {}},
        {"id": "nondefault", "initial": persistent},
        {"id": "runtime-crouching", "initial": {**persistent, **runtime}},
        {"id": "runtime-swimming", "initial": {**persistent, **runtime, "pose": "SWIMMING"}},
        {"id": "signed-zero", "initial": {"position": ["8000000000000000", db(1), "8000000000000000"],
          "velocity": ["8000000000000000"] * 3, "rotation": ["80000000"] * 4,
          "fall_distance": "8000000000000000"}},
        {"id": "short-wrap", "initial": {**persistent, "hurt_time": 65535, "death_time": 32768}},
        {"id": "scale-attribute", "initial": {**persistent, "scale": db(1.5)}},
        {"id": "sleeping-position", "initial": {**persistent, "pose": "SLEEPING", "sleeping": [2, 4, 6]}},
        {"id": "fall-flying-active", "initial": {**persistent, "pose": "FALL_FLYING", "fall_flying": True}},
    ]
    loads = []

    def add(name, source="nondefault", target=None, remove=(), replace=None, empty=False):
        loads.append({"id": name, "source": source,
                      "target": copy.deepcopy(sentinel if target is None else target),
                      "remove": list(remove), "replace": replace or {}, "empty": empty})

    for save in saves:
        add("roundtrip-fresh:" + save["id"], save["id"], target={})
    add("roundtrip-seeded-target")
    for key in ["Pos", "Motion", "Rotation", "fall_distance", "OnGround", "Health", "HurtTime",
                "DeathTime", "XpSeed", "abilities", "attributes"]:
        add("missing:" + key, remove=[key])
    add("empty-tag", empty=True)
    add("historical-FallDistance", remove=["fall_distance"],
        replace={"FallDistance": numeric(5, fb(4.5))})
    for kind, value in [(5, fb(4.5)), (3, 17), (8, "4.5"), (6, "7ff8000000000263")]:
        tag = numeric(kind, value)
        add("fall-type:" + str(kind), replace={"fall_distance": tag})
    for kind, value in [(1, -1), (3, 2), (2, 0), (5, fb(1)), (6, "7ff8000000000263"), (8, "true")]:
        add("ground-type:" + str(kind), replace={"OnGround": numeric(kind, value)})
    for name, values in [
        ("motion-ten", vector([10., -10., -0.])),
        ("motion-above-ten", vector([math.nextafter(10., math.inf), math.nextafter(-10., -math.inf), 1.])),
        ("motion-nonfinite", ["7ff8000000000263", "7ff0000000000000", "fff0000000000000"]),
    ]:
        add(name, replace={"Motion": sequence(6, values)})
    add("motion-float-list", replace={"Motion": sequence(5, [fb(.125), fb(-.25), "80000000"])})
    add("motion-int-list", replace={"Motion": sequence(3, [1, -2, 3])})
    add("motion-short-list", replace={"Motion": sequence(6, vector([1., 2.]))})
    add("motion-long-list", replace={"Motion": sequence(6, vector([1., 2., 3., 4.]))})
    add("position-limits", replace={"Pos": sequence(6, vector([30000513., -20000001., -30000513.]))})
    add("position-infinity", replace={"Pos": sequence(6, ["7ff0000000000000", "fff0000000000000", db(1)])})
    add("position-nan-partial", replace={"Pos": sequence(6, ["7ff8000000000263", db(2), db(3)])})
    add("position-float-list", replace={"Pos": sequence(5, [fb(1.25), fb(2.5), fb(-3.75)])})
    add("position-short-list", replace={"Pos": sequence(6, vector([1., 2.]))})
    add("rotation-multiple-turns", replace={"Rotation": sequence(5, [fb(1087.5), fb(-843.25)])})
    add("rotation-double-list", replace={"Rotation": sequence(6, vector([17.25, -11.5]))})
    add("rotation-nonfinite", replace={"Rotation": sequence(5, ["7fc00263", "7f800000"])})
    add("rotation-short-list", replace={"Rotation": sequence(5, [fb(17)])})
    add("health-int", replace={"Health": numeric(3, 9)})
    add("health-string", replace={"Health": numeric(8, "9")})
    add("UUID-other", replace={"UUID": {"type": 11, "values": [0, 0, 0, 999]}})
    add("dimension-other", replace={"Dimension": numeric(8, "minecraft:the_nether")})
    add("fall-flying-load-service-gap", replace={"FallFlying": numeric(1, 1)})
    add("extra-runtime-tags", replace={"Pose": numeric(8, "SWIMMING"), "Width": numeric(5, fb(2)),
        "Height": numeric(5, fb(9)), "minorHorizontalCollision": numeric(1, 0),
        "noJumpDelay": numeric(3, 123), "mainSupportingBlockPos": {"type": 11, "values": [9, 8, 7]}})
    add("missing:sleeping_pos", "sleeping-position", target={**sentinel, "pose": "SLEEPING", "sleeping": [9, 8, 7]}, remove=["sleeping_pos"])
    add("sleeping-pos-int-array", replace={"sleeping_pos": {"type": 11, "values": [2, 4, 6]}})
    add("sleeping-pos-short-array", target={**sentinel, "pose": "SLEEPING", "sleeping": [9, 8, 7]},
        replace={"sleeping_pos": {"type": 11, "values": [2, 4]}})
    return {"save": saves, "load": loads,
            "fixture_seed": {"uuid": "00000000-0000-0000-0000-000000000107", "xp_seed": 263,
                             "actual_random_source_seed": 263, "account_data": False}}


JAVA_SOURCE = r'''
package net.minecraft.fixture;
import java.io.*;
import java.util.*;
import java.lang.reflect.*;
import com.google.gson.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;
import net.minecraft.data.registries.VanillaRegistries;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.world.entity.*;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.player.Input;
import net.minecraft.world.phys.*;
import net.minecraft.nbt.*;
import net.minecraft.util.*;
import net.minecraft.world.level.storage.*;
public class PlayerSaveReceiverFixture {
 static final Gson JSON=new GsonBuilder().serializeNulls().create();
 static final PrintStream OUT=System.out;
 static String bits(float v){return LocalInputReceiverFixture.bits(v);}
 static String bits(double v){return LocalInputReceiverFixture.bits(v);}
 static float f(JsonElement v){return Float.intBitsToFloat(Integer.parseUnsignedInt(v.getAsString(),16));}
 static double d(JsonElement v){return Double.longBitsToDouble(Long.parseUnsignedLong(v.getAsString(),16));}
 static Vec3 vec(JsonArray a){return new Vec3(d(a.get(0)),d(a.get(1)),d(a.get(2)));}
 static Object read(Object p,String name)throws Exception{return LocalInputReceiverFixture.read(p,name);}
 static void seed(Object p,String name,Object v)throws Exception{LocalInputReceiverFixture.seed(p,name,v);}
 static List<String> vector(Vec3 v){return LocalInputReceiverFixture.vector(v);}
 static List<String> box(AABB b){return List.of(bits(b.minX),bits(b.minY),bits(b.minZ),bits(b.maxX),bits(b.maxY),bits(b.maxZ));}
 static void output(Object v){OUT.println("PLAYER_SAVE_JSON:"+JSON.toJson(v));}
 static LocalInputReceiverFixture.Context receiver(HolderLookup.Provider lookup,JsonObject in,List<Map<String,Object>> configurationErrors)throws Exception{
  var c=new LocalInputReceiverFixture.Context(lookup,false);var p=c.player;c.keys(0);
  p.setUUID(new UUID(0,263));seed(p,"enchantmentSeed",263);((RandomSource)read(p,"random")).setSeed(263L);
  if(in.has("position"))p.setPos(vec(in.getAsJsonArray("position")));
  if(in.has("velocity"))p.setDeltaMovement(vec(in.getAsJsonArray("velocity")));
  if(in.has("rotation")){var a=in.getAsJsonArray("rotation");p.setYRot(f(a.get(0)));p.setXRot(f(a.get(1)));p.yRotO=f(a.get(2));p.xRotO=f(a.get(3));}
  if(in.has("fall_distance"))p.fallDistance=d(in.get("fall_distance"));
  if(in.has("ground"))p.setOnGround(in.get("ground").getAsBoolean());
  if(in.has("health"))p.setHealth(f(in.get("health")));
  if(in.has("hurt_time"))p.hurtTime=in.get("hurt_time").getAsInt();
  if(in.has("death_time"))p.deathTime=in.get("death_time").getAsInt();
  if(in.has("absorption"))p.setAbsorptionAmount(f(in.get("absorption")));
  if(in.has("impulse_grace"))seed(p,"currentImpulseContextResetGraceTime",in.get("impulse_grace").getAsInt());
  if(in.has("impulse_position"))seed(p,"currentImpulseImpactPos",vec(in.getAsJsonArray("impulse_position")));
  if(in.has("experience_progress"))p.experienceProgress=f(in.get("experience_progress"));
  if(in.has("experience_level"))p.experienceLevel=in.get("experience_level").getAsInt();
  if(in.has("experience_total"))p.totalExperience=in.get("experience_total").getAsInt();
  if(in.has("food"))p.getFoodData().setFoodLevel(in.get("food").getAsInt());
  if(in.has("input")){var a=in.getAsJsonArray("input");p.xxa=f(a.get(0));p.yya=f(a.get(1));p.zza=f(a.get(2));}
  if(in.has("jumping"))seed(p,"jumping",in.get("jumping").getAsBoolean());
  if(in.has("jump_delay"))seed(p,"noJumpDelay",(int)in.get("jump_delay").getAsLong());
  if(in.has("jump_trigger"))seed(p,"jumpTriggerTime",(int)in.get("jump_trigger").getAsLong());
  if(in.has("sprint_trigger"))seed(p,"sprintTriggerTime",in.get("sprint_trigger").getAsInt());
  if(in.has("speed"))seed(p,"speed",f(in.get("speed")));
  if(in.has("needs_sync"))p.needsSync=in.get("needs_sync").getAsBoolean();
  if(in.has("tick_count"))p.tickCount=in.get("tick_count").getAsInt();
  if(in.has("head_body_rotation")){var a=in.getAsJsonArray("head_body_rotation");p.yHeadRot=f(a.get(0));p.yHeadRotO=f(a.get(1));p.yBodyRot=f(a.get(2));p.yBodyRotO=f(a.get(3));}
  if(in.has("bob")){var a=in.getAsJsonArray("bob");p.xBob=f(a.get(0));p.yBob=f(a.get(1));p.xBobO=f(a.get(2));p.yBobO=f(a.get(3));}
  if(in.has("keys")){int m=in.get("keys").getAsInt();p.input.keyPresses=LocalInputReceiverFixture.buttons(m);}
  if(in.has("crouching_cache"))seed(p,"crouching",in.get("crouching_cache").getAsBoolean());
  if(in.has("input_move")){var a=in.getAsJsonArray("input_move");seed(p.input,"moveVector",new Vec2(f(a.get(0)),f(a.get(1))));}
  if(in.has("minor_collision"))p.minorHorizontalCollision=in.get("minor_collision").getAsBoolean();
  if(in.has("collisions")){var a=in.getAsJsonArray("collisions");p.horizontalCollision=a.get(0).getAsBoolean();p.verticalCollision=a.get(1).getAsBoolean();p.verticalCollisionBelow=a.get(2).getAsBoolean();}
  if(in.has("support")){var a=in.getAsJsonArray("support");seed(p,"mainSupportingBlockPos",Optional.of(new BlockPos(a.get(0).getAsInt(),a.get(1).getAsInt(),a.get(2).getAsInt())));}
  if(in.has("ground_no_blocks"))seed(p,"onGroundNoBlocks",in.get("ground_no_blocks").getAsBoolean());
  if(in.has("scale")){p.getAttribute(Attributes.SCALE).setBaseValue(d(in.get("scale")));p.refreshDimensions();}
  if(in.has("sleeping")){var a=in.getAsJsonArray("sleeping");p.setSleepingPos(new BlockPos(a.get(0).getAsInt(),a.get(1).getAsInt(),a.get(2).getAsInt()));}
  if(in.has("pose"))p.setPose(Pose.valueOf(in.get("pose").getAsString()));
  // Retain and expose an actual post-setter receiver even when its external
  // sound notification fails. Continuing to save that observed partial state
  // does not claim lifecycle activation completed.
  if(in.has("fall_flying"))try{LocalInputReceiverFixture.invokeInherited(p,"setSharedFlag",new Class<?>[]{int.class,boolean.class},7,in.get("fall_flying").getAsBoolean());}catch(Throwable error){configurationErrors.add(failure(error));}
  if(in.has("box")){var a=in.getAsJsonArray("box");p.setBoundingBox(new AABB(d(a.get(0)),d(a.get(1)),d(a.get(2)),d(a.get(3)),d(a.get(4)),d(a.get(5))));}
  return c;
 }
 static Map<String,Object> state(LocalPlayer p)throws Exception{
  Map<String,Object> m=new TreeMap<>(LocalInputReceiverFixture.state(p));
  m.put("old_position_f64_bits",List.of(bits(p.xo),bits(p.yo),bits(p.zo)));
  m.put("fall_distance_f64_bits",bits(p.fallDistance));m.put("health_f32_bits",bits(p.getHealth()));
  m.put("hurt_time",p.hurtTime);m.put("death_time",p.deathTime);
  m.put("absorption_f32_bits",bits(p.getAbsorptionAmount()));
  m.put("impulse_grace",read(p,"currentImpulseContextResetGraceTime"));
  Vec3 impact=(Vec3)read(p,"currentImpulseImpactPos");m.put("impulse_position",impact==null?null:vector(impact));
  m.put("head_body_rotation_f32_bits",List.of(bits(p.yHeadRot),bits(p.yHeadRotO),bits(p.yBodyRot),bits(p.yBodyRotO)));
  Optional<?> supporting=(Optional<?>)read(p,"mainSupportingBlockPos");m.put("support",supporting.map(v->{BlockPos b=(BlockPos)v;return List.of(b.getX(),b.getY(),b.getZ());}).orElse(null));
  m.put("on_ground_no_blocks",read(p,"onGroundNoBlocks"));m.put("tick_count_u32",Integer.toUnsignedLong(p.tickCount));
  m.put("cached_eye_height_f32_bits",bits((float)read(p,"eyeHeight")));m.put("eye_height_f32_bits",bits(p.getEyeHeight()));
  m.put("scale_f64_bits",bits(p.getAttributeValue(Attributes.SCALE)));
  m.put("sleeping_position",p.getSleepingPos().map(v->List.of(v.getX(),v.getY(),v.getZ())).orElse(null));
  m.put("fall_flying",p.isFallFlying());m.put("uuid",p.getUUID().toString());
  m.put("xp_seed",read(p,"enchantmentSeed"));m.put("experience",List.of(bits(p.experienceProgress),p.experienceLevel,p.totalExperience));
  m.put("food",p.getFoodData().getFoodLevel());m.put("dimension",p.level().dimension().identifier().toString());
  Map<String,Object> words=new TreeMap<>();for(String name:List.of("noJumpDelay","jumpTriggerTime","sprintTriggerTime","tickCount","hurtTime","deathTime","enchantmentSeed","currentImpulseContextResetGraceTime"))words.put(name,String.format(Locale.ROOT,"%08x",((Number)read(p,name)).intValue()));m.put("raw_counter_u32",words);
  return m;
 }
 static Object typed(Tag tag){
  if(tag==null)return null;Map<String,Object> m=new TreeMap<>();m.put("type",tag.getId());
  switch(tag.getId()){
   case 1,2,3,4 -> m.put("value",((NumericTag)tag).longValue());
   case 5 -> m.put("bits",bits(((NumericTag)tag).floatValue()));
   case 6 -> m.put("bits",bits(((NumericTag)tag).doubleValue()));
   case 7 -> m.put("bytes_base64",Base64.getEncoder().encodeToString(tag.asByteArray().orElseThrow()));
   case 8 -> m.put("value",tag.asString().orElseThrow());
   case 9 -> {List<Object> items=new ArrayList<>();for(Tag item:(ListTag)tag)items.add(typed(item));m.put("items",items);}
   case 10 -> {Map<String,Object> entries=new TreeMap<>();((CompoundTag)tag).forEach((key,value)->entries.put(key,typed(value)));m.put("entries",entries);}
   case 11 -> {int[] a=tag.asIntArray().orElseThrow();m.put("values",Arrays.stream(a).boxed().toList());m.put("raw_u32_words",Arrays.stream(a).mapToObj(v->String.format(Locale.ROOT,"%08x",v)).toList());}
   case 12 -> m.put("values",Arrays.stream(tag.asLongArray().orElseThrow()).boxed().toList());
  }return m;
 }
 static Tag mutation(JsonObject in){
  int type=in.get("type").getAsInt();return switch(type){
   case 1 -> ByteTag.valueOf(in.get("value").getAsByte());
   case 2 -> ShortTag.valueOf(in.get("value").getAsShort());
   case 3 -> IntTag.valueOf(in.get("value").getAsInt());
   case 4 -> LongTag.valueOf(in.get("value").getAsLong());
   case 5 -> FloatTag.valueOf(f(in.get("bits")));
   case 6 -> DoubleTag.valueOf(d(in.get("bits")));
   case 8 -> StringTag.valueOf(in.get("value").getAsString());
   case 9 -> {ListTag list=new ListTag();for(JsonElement item:in.getAsJsonArray("items"))list.add(mutation(item.getAsJsonObject()));yield list;}
   case 11 -> {var items=in.getAsJsonArray("values");int[] values=new int[items.size()];for(int i=0;i<values.length;i++)values[i]=items.get(i).getAsInt();yield new IntArrayTag(values);}
   default -> throw new IllegalArgumentException("Unsupported explicit fixture mutation type "+type);
  };
 }
 static byte[] nbt(CompoundTag tag)throws Exception{
  ByteArrayOutputStream bytes=new ByteArrayOutputStream();NbtIo.write(tag,new DataOutputStream(bytes));
  if(bytes.size()>65536)throw new AssertionError("Fixture NBT exceeds 64KiB");return bytes.toByteArray();
 }
 static CompoundTag wireRead(byte[] bytes)throws Exception{
  return NbtIo.read(new DataInputStream(new ByteArrayInputStream(bytes)),NbtAccounter.create(1048576));
 }
 static Map<String,Object> wire(CompoundTag tag)throws Exception{
  byte[] bytes=nbt(tag);return Map.of("nbt_base64",Base64.getEncoder().encodeToString(bytes),"nbt_bytes",bytes.length,"tag",typed(tag),"readback_tag",typed(wireRead(bytes)));
 }
 static CompoundTag save(LocalPlayer p,HolderLookup.Provider lookup,List<Map<String,Object>> problems){
  var reporter=new ProblemReporter.Collector();var output=TagValueOutput.createWithContext(reporter,lookup);
  p.saveWithoutId(output);reporter.forEach((path,problem)->problems.add(Map.of("path",path,"problem",problem.toString())));return output.buildResult();
 }
 static Map<String,Object> failure(Throwable error){
  List<Map<String,Object>> chain=new ArrayList<>();Throwable current=error;
  while(current!=null){chain.add(Map.of("class",current.getClass().getName(),"message",String.valueOf(current.getMessage())));current=current.getCause();}
  Throwable root=error;while(root.getCause()!=null)root=root.getCause();return Map.of("chain",chain,"root_class",root.getClass().getName(),"root_message",String.valueOf(root.getMessage()),"stack",Arrays.stream(root.getStackTrace()).map(StackTraceElement::toString).toList());
 }
 public static void run(String mode)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();HolderLookup.Provider lookup=VanillaRegistries.createWorldLookup();
  JsonObject in=JsonParser.parseString(new String(Base64.getDecoder().decode(__INPUT__),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonObject();
  Map<String,CompoundTag> saved=new TreeMap<>();
  for(JsonElement item:in.getAsJsonArray("save")){
   JsonObject c=item.getAsJsonObject();String id=c.get("id").getAsString();Map<String,Object> row=new TreeMap<>();row.put("kind","save");row.put("id",id);List<Map<String,Object>> problems=new ArrayList<>();
   List<Map<String,Object>> configurationErrors=new ArrayList<>();row.put("configuration_errors",configurationErrors);
   try{var context=receiver(lookup,c.getAsJsonObject("initial"),configurationErrors);var p=context.player;row.put("configuration_completed",configurationErrors.isEmpty());row.put("state",state(p));row.put("method_owners",Map.of("saveWithoutId",p.getClass().getMethod("saveWithoutId",ValueOutput.class).getDeclaringClass().getName(),"load",p.getClass().getMethod("load",ValueInput.class).getDeclaringClass().getName()));var tag=save(p,lookup,problems);saved.put(id,tag);row.put("wire",wire(tag));row.put("save_mutated_state",!state(p).equals(row.get("state")));row.put("should_be_saved",p.shouldBeSaved());var ordinary=TagValueOutput.createWithContext(new ProblemReporter.Collector(),lookup);row.put("ordinary_save_result",p.save(ordinary));row.put("ordinary_save_tag",typed(ordinary.buildResult()));row.put("services",new TreeMap<>(context.level.observations));row.put("ok",true);}
   catch(Throwable error){row.put("ok",false);row.put("error",failure(error));}row.put("problems",problems);output(row);
  }
  for(JsonElement item:in.getAsJsonArray("load")){
   JsonObject c=item.getAsJsonObject();Map<String,Object> row=new TreeMap<>();row.put("kind","load");row.put("id",c.get("id").getAsString());List<Map<String,Object>> problems=new ArrayList<>();
   List<Map<String,Object>> configurationErrors=new ArrayList<>();var context=receiver(lookup,c.getAsJsonObject("target"),configurationErrors);row.put("configuration_errors",configurationErrors);LocalPlayer p=context.player;row.put("before",state(p));
   try{CompoundTag tag=c.get("empty").getAsBoolean()?new CompoundTag():saved.get(c.get("source").getAsString()).copy();for(JsonElement key:c.getAsJsonArray("remove"))tag.remove(key.getAsString());for(var member:c.getAsJsonObject("replace").entrySet())tag.put(member.getKey(),mutation(member.getValue().getAsJsonObject()));row.put("input_wire",wire(tag));var actual=wireRead(nbt(tag));var reporter=new ProblemReporter.Collector();
    try{p.load(TagValueInput.create(reporter,lookup,actual));row.put("ok",true);}catch(Throwable error){row.put("ok",false);row.put("error",failure(error));}reporter.forEach((path,problem)->problems.add(Map.of("path",path,"problem",problem.toString())));
   }catch(Throwable error){row.put("ok",false);row.put("error",failure(error));}
   row.put("after",state(p));row.put("services",new TreeMap<>(context.level.observations));row.put("problems",problems);
   if(Boolean.TRUE.equals(row.get("ok"))){List<Map<String,Object>> afterProblems=new ArrayList<>();row.put("resave_wire",wire(save(p,lookup,afterProblems)));row.put("resave_problems",afterProblems);}output(row);
  }
 }
}
'''


def sources(values: dict) -> dict[str, str]:
    assert sha(Path(LI.__file__).read_bytes()) == FROZEN_LI, "Frozen normal fixture changed"
    result = LI.receiver_sources({})
    result[FIXTURE] = JAVA_SOURCE.replace("__INPUT__", LI.java_string(base64.b64encode(canonical(values)).decode()))
    assert "Unsafe" not in "\n".join(result.values())
    return result


def source_inventory() -> dict:
    result = {}
    RAW.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(CLIENT) as jar:
        for owner in CLASSES:
            command = [str(JAVA.parent / "javap"), "-p", "-c", "-s", "-classpath", str(CLIENT), owner]
            text = subprocess.check_output(command, text=True)
            raw = RAW / (owner.rsplit(".", 1)[-1] + ".javap.txt")
            raw.write_text(text)
            methods = []
            for signature, body in re.findall(
                r"^  ((?:public|protected|private)[^\n]*?\([^\n]*\);)\n(.*?)(?=^  (?:public|protected|private|static)|\Z)",
                text, re.M | re.S):
                name = re.search(r"([\w$<>]+)\([^\n]*\);$", signature)
                if name and (name[1] in METHODS or name[1].startswith(("lambda$readAdditionalSaveData$", "lambda$addAdditionalSaveData$", "lambda$load$", "lambda$save$"))):
                    methods.append({"signature": signature, "bytecode_text_sha256": sha(body.encode()),
                        "strings": re.findall(r"// String (.+)", body),
                        "field_references": sorted(set(re.findall(r"// Field (.+)", body))),
                        "direct_call_references": sorted(set(re.findall(r"// (?:InterfaceMethod|Method) (.+)", body)))})
            entry = owner.replace(".", "/") + ".class"
            result[owner] = {"entry": entry, "class_sha256": sha(jar.read(entry)),
                             "complete_bytecode_text_sha256": sha(text.encode()),
                             "methods": methods, "raw": pin(raw)}
    return result


def dependencies() -> dict:
    return {p: pin(ROOT / p) for p in DEPENDENCIES}


def shared_class_identity() -> dict:
    paths, release = verified_server_classpath()
    records = {}
    with zipfile.ZipFile(paths[0]) as server, zipfile.ZipFile(CLIENT) as client:
        for owner in CLASSES:
            entry = owner.replace(".", "/") + ".class"
            if entry not in server.namelist():
                continue
            a, b = server.read(entry), client.read(entry)
            records[owner] = {"server_sha256": sha(a), "client_sha256": sha(b),
                              "byte_identical": a == b}
    return {"server_class_jar": pin(paths[0]),
            "server_bundle_release": release["server_bundle"], "classes": records,
            "boundary": "Actual artifact byte equality; no normal ServerPlayer receiver or server services executed."}


def observe(values: dict, label: str) -> dict:
    paths, provenance = verified_client_classpath()
    derived = sources(values)
    payload = {"sources": derived, "client_jar": str(CLIENT), "mode": "player-save"}
    encoded = base64.b64encode(canonical(payload)).decode()
    launcher = LI.RECEIVER_LAUNCHER.replace("net.minecraft.fixture.LocalInputReceiverFixture", FIXTURE, 1)
    assert launcher != LI.RECEIVER_LAUNCHER
    launcher = launcher.replace("Base64.getDecoder().decode(args[0])",
        "Base64.getDecoder().decode(" + LI.java_string(encoded) + ")", 1)
    command = [str(JAVA), "-Xmx512m", "--source", "25", "--class-path", os.pathsep.join(map(str, paths)), "/dev/stdin"]
    start = time.monotonic()
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, start_new_session=True, cwd=RAW)
    print(json.dumps({"java_pid": process.pid, "timeout_seconds": 120, "label": label}), flush=True)
    try:
        stdout, stderr = process.communicate(launcher, timeout=120)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
        raise RuntimeError("120-second Java save probe bound expired")
    rows = [json.loads(line[len("PLAYER_SAVE_JSON:"):]) for line in stdout.splitlines()
            if line.startswith("PLAYER_SAVE_JSON:")]
    loaded = [json.loads(line[len("LOCAL_INPUT_CLASSES:"):]) for line in stdout.splitlines()
              if line.startswith("LOCAL_INPUT_CLASSES:")]
    raw = RAW / (label + ".full.json")
    write_json(raw, {"observations": rows, "loaded_official": loaded, "sources": derived,
                    "launcher": launcher, "command": command, "stdout": stdout, "stderr": stderr,
                    "returncode": process.returncode, "classpath": provenance})
    assert process.returncode == 0, (process.returncode, stderr[-6000:], stdout[-1000:], str(raw))
    assert len(loaded) == 1 and len(rows) == len(values["save"]) + len(values["load"]), (len(rows), str(raw))
    with zipfile.ZipFile(CLIENT) as jar:
        for name, digest in loaded[0].items():
            assert digest == sha(jar.read(name.replace(".", "/") + ".class")), name
    for name in ["net.minecraft.client.player.LocalPlayer", "net.minecraft.world.entity.Entity",
                 "net.minecraft.world.entity.LivingEntity", "net.minecraft.world.entity.Avatar",
                 "net.minecraft.world.entity.player.Player", "net.minecraft.world.level.storage.TagValueInput",
                 "net.minecraft.world.level.storage.TagValueOutput", "net.minecraft.nbt.NbtIo"]:
        assert name in loaded[0], name
    return {"observations": rows, "loaded_official_classes": loaded[0],
            "raw": pin(raw), "provenance": provenance,
            "execution": {"command": command, "pid": process.pid, "returncode": process.returncode,
                          "seconds": round(time.monotonic() - start, 6), "stdout_sha256": sha(stdout.encode()),
                          "stderr_sha256": sha(stderr.encode())},
            "fixture_sources_sha256": {name: sha(text.encode()) for name, text in derived.items()},
            "launcher_source_sha256": sha(launcher.encode())}


def compact(rows: list[dict]) -> list[dict]:
    result = []
    for row in rows:
        item = copy.deepcopy(row)
        if item["kind"] == "load":
            for key in ["input_wire", "resave_wire"]:
                if key in item:
                    value = item[key]
                    value["nbt_sha256"] = sha(base64.b64decode(value.pop("nbt_base64")))
                    entries = value["tag"]["entries"]
                    value["all_top_level_keys"] = sorted(entries)
                    value["tag"] = {k: entries[k] for k in ["Pos", "Motion", "Rotation", "fall_distance", "OnGround",
                        "Health", "HurtTime", "DeathTime", "current_impulse_context_reset_grace_time",
                        "current_explosion_impact_pos", "UUID", "FallFlying", "Dimension"] if k in entries}
                    readback = value.pop("readback_tag")
                    value["wire_changed_typed_tree"] = readback != row[key]["tag"]
        result.append(item)
    return result


def semantic(rows: list[dict]) -> list[dict]:
    """Only remove process identity suffixes in actual problem diagnostics.

    NBT trees, input/output bytes, raw numeric words, exceptions and partial
    receiver states remain untouched. Full raw artifacts retain these suffixes.
    """
    result = copy.deepcopy(rows)
    for row in result:
        for key in ["problems", "resave_problems"]:
            for report in row.get(key, []):
                report["problem"] = re.sub(
                    r"(net\.minecraft\.nbt\.[A-Za-z0-9_$]+)@[0-9a-f]+(?=\])",
                    r"\1@<process-identity>", report["problem"])
    return result


def roundtrip_summary(rows: list[dict]) -> dict:
    saves = {row["id"]: row for row in rows if row["kind"] == "save"}
    result = {}
    for row in rows:
        if row["kind"] != "load" or not row["id"].startswith("roundtrip-fresh:"):
            continue
        name = row["id"].split(":", 1)[1]
        before = saves[name]["wire"]["readback_tag"]["entries"]
        record = {"official_load_ok": row["ok"]}
        if row["ok"]:
            after = row["resave_wire"]["readback_tag"]["entries"]
            keys = sorted(set(before) | set(after))
            record.update({"stable_top_level_keys": [k for k in keys if before.get(k) == after.get(k)],
                "changed_top_level_tags": {k: {"before": before.get(k), "after": after.get(k)}
                    for k in keys if before.get(k) != after.get(k)},
                "exact_wire_equal": saves[name]["wire"]["nbt_base64"] == row["resave_wire"]["nbt_base64"]})
        else:
            record["actual_error"] = row["error"]["root_class"]
        result[name] = record
    return result


def collect(mode: str) -> None:
    RAW.mkdir(parents=True, exist_ok=True)
    values = inputs()
    before = dependencies()
    source = source_inventory()
    shared = shared_class_identity()
    run = observe(values, mode)
    assert before == dependencies(), "Consumer/dependency generation changed during Java extraction"
    assert all(row["ok"] for row in run["observations"] if row["kind"] == "save"), "Save service gap; inspect raw artifact"
    rows = semantic(compact(run["observations"]))
    loaded = run["loaded_official_classes"]
    record = {"schema": "pinned-player-save-reference-v1", "pin": "26.3", "inputs": values,
        "inputs_sha256": sha(canonical(values)), "observations": rows,
        "observations_sha256": sha(canonical(rows)), "full_observations_semantic_sha256": sha(canonical(semantic(run["observations"]))),
        "roundtrips": roundtrip_summary(run["observations"]),
        "producer": pin(Path(__file__)), "read_only_consumer_context_and_fixture_generation": before,
        "source": source, "java_runtime": pin(JAVA), "client_jar": pin(CLIENT),
        "server_client_class_identity": shared,
        "fixture_sources_sha256": run["fixture_sources_sha256"],
        "launcher_source_sha256": run["launcher_source_sha256"],
        "loaded_official_classes": {"count": len(loaded), "all_verified_against_client_jar": True,
            "complete_name_digest_map_sha256": sha(canonical(loaded)),
            "selected_classes": {name: loaded[name] for name in CLASSES if name in loaded},
            "complete_map_location": "raw_artifacts[0]#/loaded_official/0"},
        "provenance": run["provenance"],
        "raw_artifacts": [run["raw"]], "execution": run["execution"],
        "scope": "Actual normal LocalPlayer Entity/LivingEntity/Player save/load and official TagValue/NbtIo. ServerPlayer additions are bytecode-only.",
        "boundary": {"normal_constructors": "Frozen LI normal LocalPlayer/ClientLevel/Options/KeyboardInput fixture",
          "external_substitutions": sorted(name for name in LI.RECEIVER_SOURCES if name != "net.minecraft.fixture.LocalInputReceiverFixture"),
          "registry": "Actual VanillaRegistries.createWorldLookup; actual TagValue context lookup",
          "accounts": "Fixed synthetic profile and nonexistent /dev/null fixture options path only",
          "algorithms": "No Unsafe allocation, save/load override, replacement tag codec or save decision implementation",
          "load_error_policy": "Observe official exception plus actual partial state; no custom-codec rejection/atomicity assumed",
          "reproduction_normalization": "Only TagType object identity suffixes in ProblemReporter diagnostic strings are replaced with <process-identity>. Exact raw diagnostics retained in each full artifact; all tags/bytes/raw words/states/errors are compared unchanged.",
          "lifecycle_service_gap": "Official FallFlying setter mutates receiver then fails its sound notification; configuration error is retained before serializing actual partial state. Actual load also reaches this undeclared audio service. No activation success is claimed.",
          "full_server_receiver": False, "filesystem_player_dat_write": False, "window_or_foreground": False}}
    if mode == "extract":
        write_json(OUTPUT, record)
    else:
        prior = json.loads(OUTPUT.read_text())
        for key in ["inputs_sha256", "observations_sha256", "full_observations_semantic_sha256", "source", "roundtrips",
                    "read_only_consumer_context_and_fixture_generation", "fixture_sources_sha256", "launcher_source_sha256",
                    "loaded_official_classes", "java_runtime", "client_jar", "server_client_class_identity"]:
            assert prior[key] == record[key], "Fresh reproduction mismatch: " + key
    summary = {"status": "passed", "mode": mode, "producer": pin(Path(__file__)),
               "reference": pin(OUTPUT), "raw": run["raw"], "execution": run["execution"],
               "save_cases": len(values["save"]), "load_cases": len(values["load"]),
               "save_configuration_service_gaps": [{"id": row["id"], "error": error["root_class"]}
                   for row in rows if row["kind"] == "save" for error in row["configuration_errors"]],
               "official_load_successes": sum(row["ok"] for row in rows if row["kind"] == "load"),
               "official_load_errors": [{"id": row["id"], "error": row["error"]["root_class"]}
                                       for row in rows if row["kind"] == "load" and not row["ok"]],
               "loaded_official_classes": len(run["loaded_official_classes"]),
               "observations_sha256": record["observations_sha256"],
               "full_observations_semantic_sha256": record["full_observations_semantic_sha256"],
               "reproduction_normalization": record["boundary"]["reproduction_normalization"],
               "roundtrips": record["roundtrips"],
               "scope": record["scope"], "confidence": "high for recorded bounded normal receiver cases"}
    write_json(ROOT / "evidence" / ("player-save-" + mode + ".json"), summary)
    print(json.dumps({k: summary[k] for k in ["status", "mode", "reference", "save_cases", "load_cases",
        "official_load_successes", "official_load_errors", "loaded_official_classes", "observations_sha256"]}, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["extract", "reproduce"], default="extract")
    args = parser.parse_args()
    collect(args.mode)


if __name__ == "__main__":
    main()
