#!/usr/bin/env python3
"""Direct pinned keyboard, LocalPlayer input helpers and neutral aiStep oracle.

Java constructs untouched official gameplay receivers normally. Four declared
external client services supply deterministic headless context; Python chooses
inputs and verifies provenance, never calculates gameplay expected values.
"""
from __future__ import annotations

import argparse
import base64
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import random
import re
import struct
import subprocess
import time
import zipfile

from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_model_probe import CLIENT, verified_client_classpath

SOURCE = r'''
import java.io.*;
import java.util.*;
import java.lang.reflect.*;
import com.google.gson.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.client.Options;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.player.*;
import net.minecraft.world.phys.Vec2;

class ReferenceLocalInputProbe {
 static final Gson JSON=new GsonBuilder().serializeNulls().create();
 static String bits(float v){return String.format(Locale.ROOT,"%08x",Float.floatToRawIntBits(v));}
 static List<String> vector(Vec2 v){return List.of(bits(v.x),bits(v.y));}
 static float value(String bits){return Float.intBitsToFloat(Integer.parseUnsignedInt(bits,16));}
 static Map<String,Object> input(ClientInput in){var p=in.keyPresses;return Map.of("key_presses",List.of(p.forward(),p.backward(),p.left(),p.right(),p.jump(),p.shift(),p.sprint()),"move_vector_f32_bits",vector(in.getMoveVector()),"has_forward_impulse",in.hasForwardImpulse());}
 public static void main(String[] args)throws Exception{
  PrintStream output=System.out;SharedConstants.tryDetectVersion();Bootstrap.bootStrap();
  // This path is an explicitly nonexistent fixture child of /dev/null. No
  // launcher options, account data, profile or installed settings are read.
  File directory=new File("/dev/null/reference-local-input-fixture");
  if(new File(directory,"options.txt").exists())throw new AssertionError("Fixture options path unexpectedly exists");
  Options options=new Options(null,directory);KeyboardInput keyboard=new KeyboardInput(options);
  KeyMapping[] keys={options.keyUp,options.keyDown,options.keyLeft,options.keyRight,options.keyJump,options.keyShift,options.keySprint};
  for(int mask=0;mask<128;mask++){
   for(int k=0;k<keys.length;k++)keys[k].setDown((mask&(1<<k))!=0);
   keyboard.tick();output.println("LOCAL_INPUT_JSON:"+JSON.toJson(Map.of("id","keyboard:"+mask,"expected",input(keyboard))));
  }
  Method square=LocalPlayer.class.getDeclaredMethod("modifyInputSpeedForSquareMovement",Vec2.class);square.setAccessible(true);
  Method distance=LocalPlayer.class.getDeclaredMethod("distanceToUnitSquare",Vec2.class);distance.setAccessible(true);
  String[][] vectors={{"00000000","00000000"},{"80000000","80000000"},{"3f800000","00000000"},{"00000000","3f800000"},{"3f3504f3","3f3504f3"},{"3f3167a1","3f3167a1"},{"3ecccccd","3e99999a"},{"3f800000","3f800000"},{"bf800000","3f800000"}};
  for(int i=0;i<vectors.length;i++){
   Vec2 v=new Vec2(value(vectors[i][0]),value(vectors[i][1]));Map<String,Object> result=new TreeMap<>();result.put("id","vector:"+i);result.put("input_f32_bits",vector(v));result.put("expected",Map.of("normalized_f32_bits",vector(v.normalized()),"square_f32_bits",vector((Vec2)square.invoke(null,v)),"distance_to_unit_square_f32_bits",bits((float)distance.invoke(null,v)),"length_f32_bits",bits(v.length()),"length_squared_f32_bits",bits(v.lengthSquared())));output.println("LOCAL_INPUT_JSON:"+JSON.toJson(result));
  }
 }
}
'''

RECEIVER_LAUNCHER = r'''
import java.io.*;
import java.net.*;
import java.util.*;
import java.util.zip.*;
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import javax.tools.*;
import com.google.gson.*;
class LocalInputReceiverLauncher {
 static class Source extends SimpleJavaFileObject {
  final String source;
  Source(String name,String source){super(URI.create("string:///"+name.replace('.','/')+".java"),Kind.SOURCE);this.source=source;}
  public CharSequence getCharContent(boolean ignored){return source;}
 }
 static class Compiled extends SimpleJavaFileObject {
  final ByteArrayOutputStream bytes=new ByteArrayOutputStream();
  Compiled(String name){super(URI.create("memory:///"+name.replace('.','/')+".class"),Kind.CLASS);}
  public OutputStream openOutputStream(){return bytes;}
 }
 static class Manager extends ForwardingJavaFileManager<StandardJavaFileManager> {
  final Map<String,Compiled> compiled=new TreeMap<>();
  Manager(StandardJavaFileManager fileManager){super(fileManager);}
  public JavaFileObject getJavaFileForOutput(Location location,String name,JavaFileObject.Kind kind,FileObject sibling){Compiled c=new Compiled(name);compiled.put(name,c);return c;}
 }
 static class Loader extends ClassLoader {
  final Map<String,Compiled> compiled;final ZipFile jar;final Map<String,String> loadedOfficial=new TreeMap<>();
  Loader(Map<String,Compiled> compiled,String jar)throws IOException{super(LocalInputReceiverLauncher.class.getClassLoader());this.compiled=compiled;this.jar=new ZipFile(jar);}
  protected Class<?> loadClass(String name,boolean resolve)throws ClassNotFoundException{
   synchronized(getClassLoadingLock(name)){
    Class<?> c=findLoadedClass(name);if(c==null){ZipEntry e=jar.getEntry(name.replace('.','/')+".class");if(compiled.containsKey(name)||e!=null){try{byte[] bytes=compiled.containsKey(name)?compiled.get(name).bytes.toByteArray():jar.getInputStream(e).readAllBytes();if(!compiled.containsKey(name))loadedOfficial.put(name,HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)));c=defineClass(name,bytes,0,bytes.length);}catch(Exception failure){throw new ClassNotFoundException(name,failure);}}else c=super.loadClass(name,false);}if(resolve)resolveClass(c);return c;
   }
  }
 }
 public static void main(String[] args)throws Exception{
  JsonObject in=JsonParser.parseString(new String(Base64.getDecoder().decode(args[0]),StandardCharsets.UTF_8)).getAsJsonObject();List<JavaFileObject> sources=new ArrayList<>();for(var e:in.getAsJsonObject("sources").entrySet())sources.add(new Source(e.getKey(),e.getValue().getAsString()));JavaCompiler compiler=ToolProvider.getSystemJavaCompiler();DiagnosticCollector<JavaFileObject> diagnostics=new DiagnosticCollector<>();Manager manager=new Manager(compiler.getStandardFileManager(diagnostics,null,StandardCharsets.UTF_8));boolean ok=compiler.getTask(null,manager,diagnostics,List.of("--release","25","--class-path",System.getProperty("java.class.path")),null,sources).call();if(!ok)throw new IllegalStateException("Fixture compilation: "+diagnostics.getDiagnostics());Loader loader=new Loader(manager.compiled,in.get("client_jar").getAsString());PrintStream output=System.out;try{loader.loadClass("net.minecraft.fixture.LocalInputReceiverFixture").getMethod("run",String.class).invoke(null,in.get("mode").getAsString());}catch(InvocationTargetException e){throw new RuntimeException("Actual receiver fixture failed",e.getCause());}finally{output.println("LOCAL_INPUT_CLASSES:"+new Gson().toJson(loader.loadedOfficial));}
 }
}
'''

# These four substituted external-service types contain no gameplay decisions.
# LocalPlayer, its inheritance chain, Options/KeyboardInput and ClientLevel are
# loaded directly from untouched pinned jar bytes by the isolated child loader.
RECEIVER_SOURCES = {
    'net.minecraft.client.Minecraft': r'''
package net.minecraft.client;
import net.minecraft.client.multiplayer.ClientPacketListener;
import net.minecraft.client.sounds.SoundManager;
import net.minecraft.world.entity.Entity;
public class Minecraft {
 private static Minecraft instance;
 public Options options;
 public net.minecraft.client.gui.Gui gui=new net.minecraft.client.gui.Gui();
 public net.minecraft.client.multiplayer.MultiPlayerGameMode gameMode;
 public Entity camera;
 public net.minecraft.client.player.LocalPlayer player;
 public ClientPacketListener connection;
 private final net.minecraft.client.tutorial.Tutorial tutorial=new net.minecraft.client.tutorial.Tutorial();
 public Minecraft(){instance=this;}
 public static Minecraft getInstance(){return instance;}
 public SoundManager getSoundManager(){return null;}
 public Entity getCameraEntity(){return camera;}
 public ClientPacketListener getConnection(){return connection;}
 public net.minecraft.client.tutorial.Tutorial getTutorial(){return tutorial;}
 public boolean isRunning(){return false;}
}
''',
    'net.minecraft.client.gui.Gui': r'''
package net.minecraft.client.gui;
public class Gui {
 public net.minecraft.client.gui.screens.Screen screen(){return null;}
}
''',
    'net.minecraft.client.tutorial.Tutorial': r'''
package net.minecraft.client.tutorial;
public class Tutorial {
 public int inputCalls;
 public void onInput(net.minecraft.client.player.ClientInput input){inputCalls++;}
}
''',
    'net.minecraft.client.multiplayer.ClientPacketListener': r'''
package net.minecraft.client.multiplayer;
import java.util.*;
import com.mojang.authlib.GameProfile;
import net.minecraft.core.RegistryAccess;
import net.minecraft.world.flag.*;
import net.minecraft.world.scores.Scoreboard;
public class ClientPacketListener {
 private final RegistryAccess.Frozen access;
 private final GameProfile profile=new GameProfile(new UUID(0,263),"LocalInputFixture");
 private final PlayerInfo info=new PlayerInfo(profile,false);
 private final Scoreboard scoreboard=new Scoreboard();
 private final net.minecraft.client.ClientClockManager clocks=new net.minecraft.client.ClientClockManager();
 public final List<String> sent=new ArrayList<>();
 public ClientPacketListener(RegistryAccess.Frozen access){this.access=access;}
 public GameProfile getLocalGameProfile(){return profile;}
 public RegistryAccess.Frozen registryAccess(){return access;}
 public FeatureFlagSet enabledFeatures(){return FeatureFlags.VANILLA_SET;}
 public PlayerInfo getPlayerInfo(UUID id){return id.equals(profile.id())?info:null;}
 public Scoreboard scoreboard(){return scoreboard;}
 public net.minecraft.client.ClientClockManager clockManager(){return clocks;}
 public void send(net.minecraft.network.protocol.Packet<?> packet){sent.add(packet.getClass().getName());}
 public boolean hasClientLoaded(){return true;}
}
''',
    'net.minecraft.fixture.LocalInputReceiverFixture': r'''
package net.minecraft.fixture;
import java.io.*;
import java.util.*;
import java.lang.reflect.*;
import com.google.gson.*;
import com.mojang.serialization.Lifecycle;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;
import net.minecraft.core.registries.*;
import net.minecraft.data.registries.VanillaRegistries;
import net.minecraft.resources.*;
import net.minecraft.world.entity.*;
import net.minecraft.world.entity.ai.attributes.*;
import net.minecraft.world.entity.player.Input;
import net.minecraft.world.level.*;
import net.minecraft.world.level.block.*;
import net.minecraft.world.level.block.state.*;
import net.minecraft.world.level.material.*;
import net.minecraft.world.level.dimension.DimensionType;
import net.minecraft.world.phys.*;
import net.minecraft.client.*;
import net.minecraft.client.player.*;
import net.minecraft.client.multiplayer.*;
import net.minecraft.client.multiplayer.chat.ChatAbilities;
import net.minecraft.stats.StatsCounter;
public class LocalInputReceiverFixture {
 static final Gson JSON=new GsonBuilder().serializeNulls().create();
 static final PrintStream OUTPUT=System.out;
 static String bits(float v){return String.format(Locale.ROOT,"%08x",Float.floatToRawIntBits(v));}
 static String bits(double v){return String.format(Locale.ROOT,"%016x",Double.doubleToRawLongBits(v));}
 static List<String> vector(Vec2 v){return List.of(bits(v.x),bits(v.y));}
 static List<String> vector(Vec3 v){return List.of(bits(v.x),bits(v.y),bits(v.z));}
 static Field field(Class<?> c,String name)throws Exception{for(Class<?> k=c;k!=null;k=k.getSuperclass()){try{Field f=k.getDeclaredField(name);f.setAccessible(true);return f;}catch(NoSuchFieldException ignored){}}throw new NoSuchFieldException(name);}
 static void seed(Object receiver,String name,Object value)throws Exception{field(receiver.getClass(),name).set(receiver,value);}
 static Object read(Object receiver,String name)throws Exception{return field(receiver.getClass(),name).get(receiver);}
 static Object call(LocalPlayer p,String name,Class<?>[] types,Object...values)throws Exception{Method m=LocalPlayer.class.getDeclaredMethod(name,types);m.setAccessible(true);return m.invoke(p,values);}
 @SuppressWarnings({"unchecked","rawtypes"}) static Registry<?> registry(HolderLookup.RegistryLookup<?> lookup){MappedRegistry r=new MappedRegistry((ResourceKey)lookup.key(),Lifecycle.stable());lookup.listElements().forEach(e->{Holder.Reference h=(Holder.Reference)e;r.register(h.key(),h.value(),RegistrationInfo.BUILT_IN);});r.bindAllTagsToEmpty();return r.freeze();}
 static RegistryAccess.Frozen access(HolderLookup.Provider p){return new RegistryAccess.ImmutableRegistryAccess(List.of(registry(p.lookupOrThrow(Registries.BIOME)),registry(p.lookupOrThrow(Registries.DAMAGE_TYPE)))).freeze();}
 static Holder<DimensionType> dimension(HolderLookup.Provider lookup){DimensionType d=lookup.lookupOrThrow(Registries.DIMENSION_TYPE).getOrThrow(ResourceKey.create(Registries.DIMENSION_TYPE,Identifier.parse("minecraft:overworld"))).value();return Holder.direct(new DimensionType(d.hasFixedTime(),d.hasSkyLight(),d.hasCeiling(),d.hasEnderDragonFight(),d.coordinateScale(),d.minY(),d.height(),d.logicalHeight(),d.infiniburn(),d.ambientLight(),d.monsterSettings(),d.skybox(),d.cardinalLightType(),d.attributes(),HolderSet.empty(),d.defaultClock()));}
 static class FixtureLevel extends ClientLevel {
  final Map<BlockPos,BlockState> blocks=new HashMap<>();
  final Map<String,Integer> observations=new TreeMap<>();
  FixtureLevel(ClientPacketListener connection,Holder<net.minecraft.world.level.dimension.DimensionType> dimension){super(connection,new ClientLevelData(net.minecraft.world.Difficulty.NORMAL,false,false),Level.OVERWORLD,dimension,3,3,null,false,0L,63);for(int x=-2;x<=2;x++)for(int z=-2;z<=2;z++)blocks.put(new BlockPos(x,0,z),Blocks.STONE.defaultBlockState());}
  void hit(String name){observations.merge(name,1,Integer::sum);}
  public BlockState getBlockState(BlockPos p){hit("getBlockState");return blocks.getOrDefault(p,Blocks.AIR.defaultBlockState());}
  public FluidState getFluidState(BlockPos p){hit("getFluidState");return getBlockState(p).getFluidState();}
  public BlockGetter getChunkForCollisions(int x,int z){hit("getChunkForCollisions");return this;}
 }
 static class ObservedPlayer extends LocalPlayer {
  final List<Map<String,Object>> calls=new ArrayList<>();
  ObservedPlayer(Minecraft mc,ClientLevel level,ClientPacketListener connection){super(mc,level,connection,new StatsCounter(),new ClientRecipeBook(),Input.EMPTY,false,ChatAbilities.NO_RESTRICTIONS,new ItemActivation());}
  public void applyInput(){if(calls!=null)calls.add(Map.of("method","applyInput_entry","state",state(this)));super.applyInput();if(calls!=null)calls.add(Map.of("method","applyInput_exit","state",state(this)));}
  public PlayerRideableJumping jumpableVehicle(){PlayerRideableJumping vehicle=super.jumpableVehicle();if(calls!=null){List<Boolean> updates=new ArrayList<>();for(Map<String,Object> call:calls)if(call.get("method").equals("setSprinting"))updates.add((Boolean)call.get("argument"));calls.add(Map.of("method","jumpableVehicle_return_before_super_ai_step","vehicle_null",vehicle==null,"state",state(this),"fits",fits(this),"sprint_updates",updates));}return vehicle;}
  public void travel(Vec3 input){if(calls!=null)calls.add(Map.of("method","travel_entry","input",vector(input),"state",state(this)));super.travel(input);if(calls!=null)calls.add(Map.of("method","travel_exit","state",state(this)));}
  public void jumpFromGround(){Map<String,Object> before=state(this);super.jumpFromGround();if(calls!=null)calls.add(Map.of("method","jumpFromGround","before",before,"after",state(this)));}
  protected float getJumpPower(){float value=super.getJumpPower();if(calls!=null)calls.add(Map.of("method","getJumpPower","value_f32_bits",bits(value)));return value;}
  protected float getBlockJumpFactor(){float value=super.getBlockJumpFactor();if(calls!=null)calls.add(Map.of("method","getBlockJumpFactor","value_f32_bits",bits(value)));return value;}
  public void setSprinting(boolean value){super.setSprinting(value);if(calls!=null)calls.add(Map.of("method","setSprinting","argument",value,"movement_speed",bits(getAttributeValue(Attributes.MOVEMENT_SPEED))));}
 }
 static class Context {
  final Minecraft mc;final ClientPacketListener connection;final FixtureLevel level;final LocalPlayer player;final KeyboardInput input;
  Context(HolderLookup.Provider lookup,boolean observed)throws Exception{mc=new Minecraft();mc.options=new Options(mc,new File("/dev/null/reference-local-input-fixture"));connection=new ClientPacketListener(access(lookup));mc.connection=connection;level=new FixtureLevel(connection,dimension(lookup));player=observed?new ObservedPlayer(mc,level,connection):new LocalPlayer(mc,level,connection,new StatsCounter(),new ClientRecipeBook(),Input.EMPTY,false,ChatAbilities.NO_RESTRICTIONS,new ItemActivation());mc.camera=player;mc.player=player;input=new KeyboardInput(mc.options);player.input=input;player.setPos(.5,1.,.5);player.setOnGround(true);player.setYRot(0f);player.setXRot(0f);player.setOldRot();player.yHeadRot=0f;player.yBodyRot=0f;seed(player,"autoJumpEnabled",false);}
  void keys(int mask){KeyMapping[] keys={mc.options.keyUp,mc.options.keyDown,mc.options.keyLeft,mc.options.keyRight,mc.options.keyJump,mc.options.keyShift,mc.options.keySprint};for(int k=0;k<keys.length;k++)keys[k].setDown((mask&(1<<k))!=0);}
 }
 static Map<String,Object> fits(LocalPlayer p){try{Method method=net.minecraft.world.entity.player.Player.class.getDeclaredMethod("canPlayerFitWithinBlocksAndEntitiesWhen",Pose.class);method.setAccessible(true);return Map.of("standing",method.invoke(p,Pose.STANDING),"crouching",method.invoke(p,Pose.CROUCHING));}catch(Exception e){throw new RuntimeException(e);}}
 static Map<String,Object> state(LocalPlayer p){try{Map<String,Object> m=new TreeMap<>();m.put("input_f32_bits",List.of(bits(p.xxa),bits(p.yya),bits(p.zza)));m.put("jumping",read(p,"jumping"));m.put("jump_delay",read(p,"noJumpDelay"));m.put("jump_trigger",read(p,"jumpTriggerTime"));m.put("needs_sync",p.needsSync);m.put("stored_speed_f32_bits",bits((float)read(p,"speed")));m.put("resolved_speed_f32_bits",bits(p.getSpeed()));m.put("head_yaw_f32_bits",bits(p.yHeadRot));m.put("crouching",p.isCrouching());m.put("pose",p.getPose().name());m.put("visually_crawling",p.isVisuallyCrawling());m.put("moving_slowly",p.isMovingSlowly());m.put("sprinting",p.isSprinting());m.put("movement_speed",bits(p.getAttributeValue(Attributes.MOVEMENT_SPEED)));m.put("gravity",bits(p.getAttributeValue(Attributes.GRAVITY)));m.put("friction_modifier",bits(p.getAttributeValue(Attributes.FRICTION_MODIFIER)));m.put("air_drag_modifier",bits(p.getAttributeValue(Attributes.AIR_DRAG_MODIFIER)));m.put("jump_strength",bits(p.getAttributeValue(Attributes.JUMP_STRENGTH)));m.put("maximum_f32_bits",bits(p.maxUpStep()));m.put("width_f32_bits",bits(p.getBbWidth()));m.put("height_f32_bits",bits(p.getBbHeight()));m.put("pose_dimensions_f32_bits",List.of(bits(p.getDimensions(p.getPose()).width()),bits(p.getDimensions(p.getPose()).height())));m.put("sneaking_speed",bits(p.getAttributeValue(Attributes.SNEAKING_SPEED)));m.put("sneaking_speed_f32_bits",bits((float)p.getAttributeValue(Attributes.SNEAKING_SPEED)));m.put("move_vector_f32_bits",vector(p.input.getMoveVector()));var keys=p.input.keyPresses;m.put("key_presses",List.of(keys.forward(),keys.backward(),keys.left(),keys.right(),keys.jump(),keys.shift(),keys.sprint()));m.put("position",vector(p.position()));AABB b=p.getBoundingBox();m.put("box",List.of(bits(b.minX),bits(b.minY),bits(b.minZ),bits(b.maxX),bits(b.maxY),bits(b.maxZ)));m.put("velocity",vector(p.getDeltaMovement()));m.put("body_flags",List.of(p.onGround(),p.horizontalCollision,p.verticalCollision,p.verticalCollisionBelow));m.put("sprint_trigger_time",read(p,"sprintTriggerTime"));m.put("minor_horizontal_collision",p.minorHorizontalCollision);m.put("rotation_f32_bits",List.of(bits(p.getYRot()),bits(p.getXRot()),bits(p.yRotO),bits(p.xRotO)));m.put("bob_f32_bits",List.of(bits(p.xBob),bits(p.yBob),bits(p.xBobO),bits(p.yBobO)));return m;}catch(Exception e){throw new RuntimeException(e);}}
 static void output(Object value){OUTPUT.println("LOCAL_RECEIVER_JSON:"+JSON.toJson(value));}
 static float f(JsonElement e){return Float.intBitsToFloat(Integer.parseUnsignedInt(e.getAsString(),16));}
 static double d(JsonElement e){return Double.longBitsToDouble(Long.parseUnsignedLong(e.getAsString(),16));}
 static Vec2 v2(JsonArray a){return new Vec2(f(a.get(0)),f(a.get(1)));}
 static Vec3 v3(JsonArray a){return new Vec3(d(a.get(0)),d(a.get(1)),d(a.get(2)));}
 static Input buttons(int mask){return new Input((mask&1)!=0,(mask&2)!=0,(mask&4)!=0,(mask&8)!=0,(mask&16)!=0,(mask&32)!=0,(mask&64)!=0);}
 static void configure(Context c,JsonObject in)throws Exception{
  LocalPlayer p=c.player;c.mc.options.sprintWindow().set(in.get("sprint_window").getAsInt());int mask=in.get("previous_mask").getAsInt();c.keys(mask);c.input.keyPresses=buttons(mask);seed(c.input,"moveVector",v2(in.getAsJsonArray("previous_move_f32_bits")));seed(p,"crouching",in.get("crouching").getAsBoolean());seed(p,"sprintTriggerTime",in.get("sprint_trigger_time").getAsInt());JsonArray bobs=in.getAsJsonArray("bob_f32_bits");p.xBob=f(bobs.get(0));p.yBob=f(bobs.get(1));p.xBobO=f(bobs.get(2));p.yBobO=f(bobs.get(3));JsonArray rotation=in.getAsJsonArray("rotation_f32_bits");p.setYRot(f(rotation.get(0)));p.setXRot(f(rotation.get(1)));p.yRotO=f(rotation.get(2));p.xRotO=f(rotation.get(3));JsonArray inputs=in.getAsJsonArray("input_f32_bits");p.xxa=f(inputs.get(0));p.yya=f(inputs.get(1));p.zza=f(inputs.get(2));seed(p,"jumping",in.get("jumping").getAsBoolean());seed(p,"noJumpDelay",in.get("jump_delay").getAsInt());seed(p,"jumpTriggerTime",in.get("jump_trigger").getAsInt());p.needsSync=in.get("needs_sync").getAsBoolean();seed(p,"speed",f(in.get("stored_speed_f32_bits")));p.yHeadRot=f(in.get("head_yaw_f32_bits"));p.setDeltaMovement(v3(in.getAsJsonArray("velocity")));p.setOnGround(in.get("grounded").getAsBoolean());p.horizontalCollision=in.get("horizontal_collision").getAsBoolean();p.minorHorizontalCollision=in.get("minor_horizontal_collision").getAsBoolean();p.setPose(Pose.valueOf(in.get("pose").getAsString()));p.getFoodData().setFoodLevel(in.get("food").getAsInt());p.getAbilities().mayfly=in.get("mayfly").getAsBoolean();p.getAbilities().flying=in.get("flying").getAsBoolean();p.getAttribute(Attributes.SNEAKING_SPEED).setBaseValue(d(in.get("sneaking_speed")));p.setSprinting(in.get("sprinting").getAsBoolean());if(in.get("blindness").getAsBoolean())p.addEffect(new net.minecraft.world.effect.MobEffectInstance(net.minecraft.world.effect.MobEffects.BLINDNESS,200,0,false,false));if(in.get("ceiling").getAsBoolean())for(int x=-2;x<=2;x++)for(int z=-2;z<=2;z++)c.level.blocks.put(new BlockPos(x,2,z),Blocks.OAK_SLAB.defaultBlockState().setValue(net.minecraft.world.level.block.state.properties.BlockStateProperties.SLAB_TYPE,net.minecraft.world.level.block.state.properties.SlabType.TOP));if(p instanceof ObservedPlayer observed)observed.calls.clear();
 }
 static Map<String,Object> controlContext(Context c)throws Exception{LocalPlayer p=c.player;Map<String,Object> m=new TreeMap<>();m.put("fits",fits(p));m.put("food",p.getFoodData().getFoodLevel());m.put("enough_food",(boolean)invokeInherited(p,"hasEnoughFoodToDoExhaustiveManoeuvres",new Class<?>[]{}));m.put("mobility_restricted",p.isMobilityRestricted());m.put("mayfly",p.getAbilities().mayfly);m.put("flying",p.getAbilities().flying);m.put("sprint_window",c.mc.options.sprintWindow().get());m.put("in_shallow_water",p.isInShallowWater());m.put("underwater",p.isUnderWater());m.put("fall_flying",p.isFallFlying());m.put("using_item",p.isUsingItem());m.put("is_passenger",p.isPassenger());m.put("controlled_camera",c.mc.camera==p);BlockPos ground=(BlockPos)invokeInherited(p,"getBlockPosBelowThatAffectsMyMovement",new Class<?>[]{});BlockState block=c.level.getBlockState(ground);float friction=block.getBlock().getFriction();m.put("ground_sample",Map.of("position",List.of(ground.getX(),ground.getY(),ground.getZ()),"block_id",BuiltInRegistries.BLOCK.getKey(block.getBlock()).toString(),"friction_f32_bits",bits(friction),"friction_f64_bits",bits((double)friction)));m.put("jump_factor_f32_bits",bits((float)invokeInherited(p,"getBlockJumpFactor",new Class<?>[]{})));return m;}
 static Object invokeInherited(Object receiver,String name,Class<?>[] types,Object...values)throws Exception{for(Class<?> owner=receiver.getClass();owner!=null;owner=owner.getSuperclass()){try{Method m=owner.getDeclaredMethod(name,types);m.setAccessible(true);return m.invoke(receiver,values);}catch(NoSuchMethodException ignored){}}throw new NoSuchMethodException(name);}
 static void corpus(HolderLookup.Provider lookup)throws Exception{
  JsonObject inputs=JsonParser.parseString(new String(Base64.getDecoder().decode(__CORPUS_INPUT_BASE64__),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonObject();
  Options options=new Options(Minecraft.getInstance(),new File("/dev/null/reference-local-input-fixture"));KeyboardInput keyboard=new KeyboardInput(options);KeyMapping[] keys={options.keyUp,options.keyDown,options.keyLeft,options.keyRight,options.keyJump,options.keyShift,options.keySprint};
  for(JsonElement e:inputs.getAsJsonArray("keyboard")){JsonObject in=e.getAsJsonObject();int mask=in.get("mask").getAsInt();for(int k=0;k<keys.length;k++)keys[k].setDown((mask&(1<<k))!=0);keyboard.tick();Map<String,Object> expected=new TreeMap<>();expected.put("keys",List.of(keyboard.keyPresses.forward(),keyboard.keyPresses.backward(),keyboard.keyPresses.left(),keyboard.keyPresses.right(),keyboard.keyPresses.jump(),keyboard.keyPresses.shift(),keyboard.keyPresses.sprint()));expected.put("move_f32_bits",vector(keyboard.getMoveVector()));expected.put("has_forward",keyboard.hasForwardImpulse());output(Map.of("id",in.get("id").getAsString(),"group","keyboard","expected",expected));}
  Method square=LocalPlayer.class.getDeclaredMethod("modifyInputSpeedForSquareMovement",Vec2.class);square.setAccessible(true);Method distance=LocalPlayer.class.getDeclaredMethod("distanceToUnitSquare",Vec2.class);distance.setAccessible(true);
  for(JsonElement e:inputs.getAsJsonArray("vectors")){JsonObject in=e.getAsJsonObject();Vec2 v=v2(in.getAsJsonArray("input_f32_bits"));output(Map.of("id",in.get("id").getAsString(),"group","vectors","expected",Map.of("normalized_f32_bits",vector(v.normalized()),"square_f32_bits",vector((Vec2)square.invoke(null,v)),"distance_f32_bits",bits((float)distance.invoke(null,v)),"length_f32_bits",bits(v.length()),"length_squared_f32_bits",bits(v.lengthSquared()))));}
  for(JsonElement e:inputs.getAsJsonArray("receivers")){JsonObject in=e.getAsJsonObject();for(boolean observed:List.of(false,true)){Context c=new Context(lookup,observed);configure(c,in.getAsJsonObject("initial"));seed(c.input,"moveVector",v2(in.getAsJsonArray("move_f32_bits")));c.input.keyPresses=buttons(in.get("mask").getAsInt());Map<String,Object> before=state(c.player);Map<String,Object> context=controlContext(c);if(observed)((ObservedPlayer)c.player).calls.clear();boolean start=(boolean)call(c.player,"canStartSprinting",new Class<?>[]{});boolean possible=(boolean)call(c.player,"isSprintingPossible",new Class<?>[]{boolean.class},c.player.getAbilities().flying);c.player.applyInput();output(Map.of("id",in.get("id").getAsString(),"group","receivers","observed",observed,"before",before,"context",context,"expected",state(c.player),"can_start_sprinting",start,"sprinting_possible",possible,"observer_calls",observed?((ObservedPlayer)c.player).calls:List.of()));}}
  for(JsonElement e:inputs.getAsJsonArray("ai_step")){JsonObject in=e.getAsJsonObject();for(boolean observed:List.of(false,true)){Context c=new Context(lookup,observed);configure(c,in.getAsJsonObject("initial"));List<Map<String,Object>> steps=new ArrayList<>();for(JsonElement se:in.getAsJsonArray("steps")){JsonObject step=se.getAsJsonObject();if(step.has("food"))c.player.getFoodData().setFoodLevel(step.get("food").getAsInt());if(step.has("horizontal_collision"))c.player.horizontalCollision=step.get("horizontal_collision").getAsBoolean();if(step.has("minor_horizontal_collision"))c.player.minorHorizontalCollision=step.get("minor_horizontal_collision").getAsBoolean();if(observed)((ObservedPlayer)c.player).calls.clear();c.keys(step.get("held_mask").getAsInt());Map<String,Object> before=state(c.player);Map<String,Object> context=controlContext(c);if(observed)((ObservedPlayer)c.player).calls.clear();c.player.aiStep();Map<String,Object> row=new TreeMap<>();row.put("before",before);row.put("context",context);row.put("expected",state(c.player));row.put("observer_calls",observed?List.copyOf(((ObservedPlayer)c.player).calls):List.of());steps.add(row);}output(Map.of("id",in.get("id").getAsString(),"group","ai_step","observed",observed,"steps",steps));}}
 }
 public static void run(String mode)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();HolderLookup.Provider lookup=VanillaRegistries.createWorldLookup();
  if(mode.equals("corpus")){corpus(lookup);return;}
  for(boolean observed:List.of(false,true))for(int i=0;i<6;i++){
   Context c=new Context(lookup,observed);LocalPlayer p=c.player;c.keys(i==5?65:i%2==0?1:5);c.input.tick();seed(p,"crouching",i==2||i==3);if(i==4)p.setPose(Pose.SWIMMING);p.getFoodData().setFoodLevel(i==5?6:20);p.getAttribute(Attributes.SNEAKING_SPEED).setBaseValue(i==3?.15:.3);p.setYRot(17f);p.setXRot(-11f);p.xBob=2f;p.yBob=-3f;Map<String,Object> before=state(p);boolean start=(boolean)call(p,"canStartSprinting",new Class<?>[]{});boolean possible=(boolean)call(p,"isSprintingPossible",new Class<?>[]{boolean.class},false);p.applyInput();Map<String,Object> result=new TreeMap<>();result.put("id","receiver:"+observed+":"+i);result.put("observed",observed);result.put("before",before);result.put("expected",state(p));result.put("actual_fits",fits(p));result.put("can_start_sprinting",start);result.put("sprinting_possible",possible);result.put("service_calls",c.level.observations);result.put("observer_calls",observed?((ObservedPlayer)p).calls:List.of());output(result);
  }
  if(mode.equals("ai-step")){
   Context c=new Context(lookup,true);c.keys(65);Map<String,Object> before=state(c.player);c.player.aiStep();output(Map.of("id","ai-step:forward-sprint","before",before,"expected",state(c.player),"tutorial_calls",c.mc.getTutorial().inputCalls,"sent_packets",c.connection.sent,"observer_calls",((ObservedPlayer)c.player).calls,"service_calls",c.level.observations));
  }
 }
}
''',
}

CLASSES = [
    'net.minecraft.client.player.LocalPlayer',
    'net.minecraft.client.player.AbstractClientPlayer',
    'net.minecraft.client.player.KeyboardInput',
    'net.minecraft.client.player.ClientInput',
    'net.minecraft.client.Options',
    'net.minecraft.client.KeyMapping',
    'net.minecraft.client.ToggleKeyMapping',
    'net.minecraft.world.entity.player.Input',
    'net.minecraft.world.entity.player.Player',
    'net.minecraft.world.entity.Entity',
    'net.minecraft.world.entity.LivingEntity',
    'net.minecraft.world.entity.Avatar',
    'net.minecraft.world.food.FoodData',
    'net.minecraft.world.phys.Vec2',
    'net.minecraft.client.Minecraft',
    'net.minecraft.client.multiplayer.ClientPacketListener',
    'net.minecraft.client.multiplayer.ClientLevel',
]
METHODS = {
    'LocalPlayer', 'AbstractClientPlayer', 'KeyboardInput', 'ClientInput',
    'Options', 'KeyMapping', 'ToggleKeyMapping', 'ClientPacketListener',
    'ClientLevel', 'Minecraft', 'tick', 'aiStep', 'applyInput', 'modifyInput',
    'modifyInputSpeedForSquareMovement', 'distanceToUnitSquare', 'normalized',
    'length', 'lengthSquared', 'scale', 'calculateImpulse', 'getMoveVector',
    'hasForwardImpulse', 'makeJump', 'isDown', 'setDown', 'canStartSprinting',
    'isSprintingPossible', 'vehicleCanSprint', 'shouldStopRunSprinting',
    'shouldStopSwimSprinting', 'isMoving', 'isMovingSlowly', 'isCrouching',
    'isShiftKeyDown', 'isControlledCamera', 'isSlowDueToUsingItem',
    'itemUseSpeedMultiplier', 'isMobilityRestricted', 'canSprint',
    'hasEnoughFoodToDoExhaustiveManoeuvres', 'load', 'setSprinting',
    'commonTick', 'baseTick', 'setOldPosAndRot', 'setOldRot', 'rangeChecks',
    'isVisuallySwimming', 'isVisuallyCrawling', 'isInShallowWater',
    'getAttributeValue', 'getSpeed', 'hasEnoughFood', 'getBlockPosBelowThatAffectsMyMovement', 'getBlockJumpFactor', 'getJumpPower',
}


def source_inventory():
    result = {}
    with zipfile.ZipFile(CLIENT) as jar:
        for owner in CLASSES:
            text = subprocess.run(
                [str(JAVA.parent / 'javap'), '-classpath', str(CLIENT), '-c', '-p', owner],
                capture_output=True, text=True, check=True,
            ).stdout
            methods = []
            for signature, body in re.findall(
                r'^  ((?:public|protected|private)[^\n]*?\([^\n]*\);)\n(.*?)(?=^  (?:public|protected|private|static)|\Z)',
                text, re.M | re.S,
            ):
                name = re.search(r'([\w$<>]+)\([^\n]*\);$', signature)
                if name and name[1] in METHODS:
                    methods.append({
                        'signature': signature,
                        'bytecode_text_sha256': hashlib.sha256(body.encode()).hexdigest(),
                        'direct_call_references': sorted(set(re.findall(r'// (?:InterfaceMethod|Method) (.+)', body))),
                        'field_references': sorted(set(re.findall(r'// Field (.+)', body))),
                    })
            entry = owner.replace('.', '/') + '.class'
            result[owner] = {
                'class_entry': entry,
                'class_sha256': hashlib.sha256(jar.read(entry)).hexdigest(),
                'complete_bytecode_text_sha256': hashlib.sha256(text.encode()).hexdigest(),
                'methods': methods,
            }
    return result


def canonical_sha256(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def compact_report(destination, evidence, raw_execution=None):
    """Store full observations locally; publish checked provenance summaries.

    The in-memory evidence passed to collect() is never changed. Historical
    records keep their original execution/provenance, not a fresh-Java claim.
    """
    assert evidence['observations_sha256'] == canonical_sha256(evidence['observations'])
    full = dict(evidence)
    if raw_execution is not None:
        full['raw_execution'] = raw_execution
    raw_path = ROOT/'build/local-input-reference'/f'{destination.stem}.full.json'
    write_json(raw_path, full)
    report = {key: value for key, value in evidence.items()
              if key not in ('observations', 'source', 'provenance', 'substituted_external_types', 'execution')}
    report['evidence_format'] = 'local-input-summary-v1'
    report['storage_writer'] = fingerprint(Path(__file__))
    report['observation_count'] = len(evidence['observations'])
    report['observation_groups'] = dict(sorted(Counter(row['id'].split(':', 1)[0] for row in evidence['observations']).items()))
    inventory = evidence['source']
    report['source_inventory'] = {
        'class_count': len(inventory),
        'method_count': sum(len(owner['methods']) for owner in inventory.values()),
        'canonical_sha256': canonical_sha256(inventory),
        'class_bytes_sha256': {name: owner['class_sha256'] for name, owner in inventory.items()},
    }
    if 'loaded_official_classes' in evidence:
        classes = evidence['loaded_official_classes']
        report['loaded_official_classes'] = {name: digest for name, digest in classes.items() if name in inventory}
        report['loaded_official_class_count'] = evidence.get('loaded_official_class_count', len(classes))
        report['loaded_official_class_tree_sha256'] = evidence.get('loaded_official_class_tree_sha256', canonical_sha256(classes))
    provenance = evidence['provenance']
    report['provenance'] = {key: value for key, value in provenance.items()
                            if key not in ('libraries', 'missing_other_platform_natives')}
    for key in ('libraries', 'missing_other_platform_natives'):
        report['provenance'][key+'_count'] = len(provenance[key])
        report['provenance'][key+'_sha256'] = canonical_sha256(provenance[key])
    report['provenance_sha256'] = canonical_sha256(provenance)
    report['substituted_external_types'] = {
        name: {'source_sha256': value['source_sha256']}
        for name, value in evidence.get('substituted_external_types', {}).items()}
    execution = dict(evidence['execution'])
    command = list(execution['command'])
    execution['command_sha256'] = canonical_sha256(command)
    if '--class-path' in command:
        index = command.index('--class-path')+1
        execution['classpath_entry_count'] = len(command[index].split(':'))
        execution['classpath_sha256'] = hashlib.sha256(command[index].encode()).hexdigest()
        command[index] = '<verified pinned classpath; complete command in raw_report>'
    execution['command'] = command
    if execution['returncode'] == 0:
        execution.pop('stderr_tail', None)
        execution.pop('stdout_tail_on_failure', None)
    report['execution'] = execution
    report['raw_report'] = {'path': str(raw_path.relative_to(ROOT)), **fingerprint(raw_path)}
    report['storage_scope'] = 'Summary only; full observations, original inventories/provenance and available raw execution retained in ignored raw_report. All checked fixture values remain in reference/local_input.json.'
    write_json(destination, report)
    verify_compact_report(destination)
    return report


def verify_compact_report(path):
    report = json.loads(path.read_text())
    assert report['evidence_format'] == 'local-input-summary-v1'
    raw_path = ROOT/report['raw_report']['path']
    assert fingerprint(raw_path) == {key: value for key, value in report['raw_report'].items() if key != 'path'}
    full = json.loads(raw_path.read_text())
    rows = full['observations']
    assert report['observations_sha256'] == full['observations_sha256'] == canonical_sha256(rows)
    assert report['observation_count'] == len(rows)
    assert report['observation_groups'] == dict(sorted(Counter(row['id'].split(':', 1)[0] for row in rows).items()))
    inventory = full['source']
    assert report['source_inventory'] == {
        'class_count': len(inventory), 'method_count': sum(len(owner['methods']) for owner in inventory.values()),
        'canonical_sha256': canonical_sha256(inventory),
        'class_bytes_sha256': {name: owner['class_sha256'] for name, owner in inventory.items()}}
    assert report['provenance_sha256'] == canonical_sha256(full['provenance'])
    for key in ('libraries', 'missing_other_platform_natives'):
        assert report['provenance'][key+'_count'] == len(full['provenance'][key])
        assert report['provenance'][key+'_sha256'] == canonical_sha256(full['provenance'][key])
    assert report['execution']['command_sha256'] == canonical_sha256(full['execution']['command'])
    if 'loaded_official_classes' in full:
        original = full['loaded_official_classes']
        assert report['loaded_official_classes'] == {name: digest for name, digest in original.items() if name in inventory}
        assert report['loaded_official_class_count'] == full.get('loaded_official_class_count', len(original))
        assert report['loaded_official_class_tree_sha256'] == full.get('loaded_official_class_tree_sha256', canonical_sha256(original))
    raw = full.get('raw_execution', {})
    if raw.get('loaded_official_classes') is not None:
        classes = raw['loaded_official_classes']
        assert report['loaded_official_class_count'] == len(classes)
        assert report['loaded_official_class_tree_sha256'] == canonical_sha256(classes)
    return {'report': fingerprint(path), 'observation_count': len(rows),
            'observations_sha256': report['observations_sha256'], 'raw_report': report['raw_report']}


def compact_existing_reports():
    summaries = []
    for path in sorted((ROOT/'evidence').glob('local-input-reference*.json')):
        evidence = json.loads(path.read_text())
        if evidence.get('evidence_format') == 'local-input-summary-v1':
            verify_compact_report(path)
            full = json.loads((ROOT/evidence['raw_report']['path']).read_text())
            raw = full.pop('raw_execution', None)
            compact_report(path, full, raw)
            summaries.append(verify_compact_report(path))
        elif 'observations' in evidence:
            compact_report(path, evidence)
            summaries.append(verify_compact_report(path))
    result = {'status': 'passed', 'scope': 'Formatting/integrity only; no new Java execution or reference values changed',
              'command': 'python3 tools/reference_local_input_probe.py --compact-existing', 'reports': summaries}
    write_json(ROOT/'evidence/local-input-reference-storage.json', result)
    return result


def prototype():
    classpath, provenance = verified_client_classpath()
    command = [str(JAVA), '--source', '25', '--class-path', ':'.join(map(str, classpath)), '/dev/stdin']
    start = time.monotonic()
    run = subprocess.run(command, input=SOURCE, capture_output=True, text=True)
    rows = [json.loads(line[len('LOCAL_INPUT_JSON:'):]) for line in run.stdout.splitlines()
            if line.startswith('LOCAL_INPUT_JSON:')]
    evidence = {
        'schema_version': 1,
        'status': 'passed' if run.returncode == 0 else 'blocked',
        'pin': '26.3',
        'scope': 'Prototype normal Options/KeyboardInput constructors and direct actual keyboard, ClientInput, Vec2 and static LocalPlayer helper calls; no Minecraft or LocalPlayer receiver, window, UI, rendering or aiStep',
        'provenance': provenance,
        'source': source_inventory(),
        'probe_source_sha256': hashlib.sha256(SOURCE.encode()).hexdigest(),
        'execution': {
            'command': command,
            'reproduce': 'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_input_probe.py --prototype',
            'returncode': run.returncode,
            'seconds': round(time.monotonic() - start, 6),
            'stdout_sha256': hashlib.sha256(run.stdout.encode()).hexdigest(),
            'stderr_sha256': hashlib.sha256(run.stderr.encode()).hexdigest(),
            'stderr_tail': run.stderr[-6000:],
            'stdout_tail_on_failure': run.stdout[-3000:] if run.returncode else None,
        },
        'observations': rows,
        'observations_sha256': hashlib.sha256(canonical(rows)).hexdigest(),
        'constructor_boundaries': {
            'options': 'Actual Options(null, new File("/dev/null/reference-local-input-fixture")); actual load returns when its options.txt is absent. No Options.load/save overrides.',
            'keyboard': 'Actual KeyboardInput(options); actual Options key mappings receive actual setDown calls before actual tick.',
            'local_player': 'Not constructed or simulated. Direct private static LocalPlayer methods receive actual Vec2 instances by reflection.',
        },
    }
    compact_report(ROOT / 'evidence/local-input-reference-prototype.json', evidence,
                   {'stdout': run.stdout, 'stderr': run.stderr, 'probe_source': SOURCE})
    return {
        'status': evidence['status'],
        'observation_count': len(rows),
        'returncode': run.returncode,
        'evidence': fingerprint(ROOT / 'evidence/local-input-reference-prototype.json'),
        'failure': run.stderr[-4000:] if run.returncode else None,
    }


SEED = 26310404
OUTPUT = ROOT / 'reference/local_input.json'
GROUPS = ('keyboard', 'vectors', 'receivers', 'ai_step')


def fb(value):
    return struct.pack('>f', value).hex()


def db(value):
    return struct.pack('>d', value).hex()


def initial(**changes):
    value = {
        'previous_mask': 0, 'previous_move_f32_bits': [fb(0),fb(0)],
        'crouching': False, 'sprint_trigger_time': 0,
        'bob_f32_bits': [fb(0)]*4,
        'rotation_f32_bits': [fb(0)]*4,
        'input_f32_bits': [fb(0)]*3, 'jumping': False,
        'jump_delay': 0, 'jump_trigger': 0, 'needs_sync': False,
        'stored_speed_f32_bits': fb(.125), 'head_yaw_f32_bits': fb(0),
        'velocity': [db(0)]*3, 'grounded': True,
        'horizontal_collision': False, 'minor_horizontal_collision': False,
        'pose': 'STANDING', 'food': 20, 'mayfly': False, 'flying': False,
        'sneaking_speed': db(.3), 'sprinting': False, 'blindness': False,
        'ceiling': False, 'sprint_window': 7,
    }
    value.update(changes)
    return value


def corpus_inputs():
    """Choose raw inputs only. Every expected numerical value is actual Java."""
    rng = random.Random(SEED)
    keyboard = [{'id': f'keyboard:{mask}', 'mask': mask} for mask in range(128)]
    edge = ['00000000','80000000','00000001','80000001','007fffff','00800000',
            '3727c5ab','3727c5ac','3727c5ad','3e99999a','3f3167a1','3f3504f3',
            '3f3504f4','3f7fffff','3f800000','3f800001','bf800000','5f800000',
            '7f7fffff','ff7fffff','7f800000','ff800000','7fc00000','ffc00000']
    pairs = [[a,b] for a in edge for b in edge]
    while len(pairs) < 2048:
        pairs.append([f'{rng.getrandbits(32):08x}', f'{rng.getrandbits(32):08x}'])
    vectors = [{'id': f'vector:{i}', 'input_f32_bits': pair,
                'scope': 'direct helpers; nonfinite results are recorded pinned-runtime observations'}
               for i,pair in enumerate(pairs)]
    finite_moves = [[fb(x),fb(z)] for x,z in [(0,0),(-0.,-0.),(0,1),(1,0),(-1,1),
                   (.70710677,.70710677),(.69,.69),(.4,.3),(1,1),(2,-3),
                   (1e-5,1e-5),(1e-20,-1e-20),(.98,0),(.98,.98)]]
    receivers = []
    for i in range(112):
        seed = initial(
            previous_mask=rng.randrange(128), previous_move_f32_bits=finite_moves[i%len(finite_moves)],
            crouching=i%4==1, pose='SWIMMING' if i%7==2 else ('CROUCHING' if i%7==3 else 'STANDING'),
            sprint_trigger_time=[-2147483648,-1,0,1,7,2147483647][i%6],
            sprinting=i%6==4, food=[6,7,20][i%3], blindness=i%11==3,
            mayfly=i%17==5, flying=i%17==5,
            sneaking_speed=db([-.1,0,.15,.3,.7,1,1.5][i%7]),
            bob_f32_bits=[fb(rng.uniform(-100,100)) for _ in range(4)],
            rotation_f32_bits=[fb(v) for v in [rng.uniform(-360,360),rng.uniform(-90,90),13,-9]],
            input_f32_bits=[fb(v) for v in [.25,-.375,.5]],
            jumping=i%2==0, jump_delay=i%12-2, jump_trigger=i%10-3,
            stored_speed_f32_bits=fb(i/100), head_yaw_f32_bits=fb(31),
            ceiling=i%13==8,
        )
        receivers.append({'id': f'apply:{i}', 'initial':seed,
                          'move_f32_bits':finite_moves[i%len(finite_moves)], 'mask':rng.randrange(128),
                          'scope':'actual applyInput/private sprint helpers only; no inherited travel'})
    scenarios = [
        ('held_forward',[1]*5,{}), ('held_diagonal',[5]*5,{}),
        ('held_sprint',[65]*5,{}), ('double_tap',[1,0,1,1,1],{}),
        ('double_tap_and_sprint',[65]*5,{'sprint_trigger_time':3}),
        ('double_start_then_major_stop',[65]*5,{'sprint_trigger_time':3,'horizontal_collision':True}),
        ('minor_allows_sprint',[65]*5,{'sprinting':True,'horizontal_collision':True,'minor_horizontal_collision':True}),
        ('major_stops_sprint',[65]*5,{'sprinting':True,'horizontal_collision':True}),
        ('old_shift_latency',[1,33,1,1,1],{'previous_mask':32}),
        ('new_shift_latency',[33,33,1,1,1],{}),
        ('old_shift_clears_window',[65]*5,{'previous_mask':32,'sprint_trigger_time':3}),
        ('new_backward_clears_window',[3,65,3,65,0],{'sprint_trigger_time':3}),
        ('opposing_all',[15,79,15,79,0],{}),
        ('food_six',[65]*5,{'food':6}), ('food_seven',[65]*5,{'food':7}),
        ('blindness',[65]*5,{'blindness':True}),
        ('negative_timer',[1,1,0,1,65],{'sprint_trigger_time':-2147483648}),
        ('maximum_timer',[65,0,65,1,1],{'sprint_trigger_time':2147483647}),
        ('jump_held',[17]*5,{}), ('jump_sprint',[81]*5,{}),
        ('jump_delay',[17]*5,{'jump_delay':3,'jump_trigger':-1,'needs_sync':True}),
        ('zero_move_yya',[0]*5,{'input_f32_bits':[fb(.3),fb(-.5),fb(.3)],'jump_delay':-1}),
        ('ceiling_pose_fit',[33,33,1,1,0],{'ceiling':True}),
        ('visual_crawl',[65,65,33,1,0],{'pose':'SWIMMING'}),
        ('food_collision_changes',[65,65,65,65,65],{'sprinting':True}),
        ('independent_old_move',[65,65,0,65,1],{'previous_mask':0,'previous_move_f32_bits':[fb(.2),fb(.9)]}),
        ('window_zero',[1,0,1,65,1],{'sprint_window':0}),
        ('window_two',[1,0,1,65,1],{'sprint_window':2}),
    ]
    ai_step=[]
    for i,(name,masks,changes) in enumerate(scenarios):
        seed=initial(bob_f32_bits=[fb(v) for v in [2,-3,4,-5]],
                     rotation_f32_bits=[fb(v) for v in [17,-11,12,-9]],
                     head_yaw_f32_bits=fb(29), stored_speed_f32_bits=fb(.123), **changes)
        steps=[{'held_mask':mask} for mask in masks]
        if name=='food_collision_changes':
            for step,food,major,minor in zip(steps,[7,6,7,7,7],[False,False,False,True,True],[False,False,False,True,False]):
                step.update(food=food,horizontal_collision=major,minor_horizontal_collision=minor)
        ai_step.append({'id':'ai:'+name,'initial':seed,'steps':steps,
                        'scope':'pose/control and post-control preparation only; actual slab ceiling outside fullcube resolver admission' if seed['ceiling'] else 'neutral bounded actual aiStep; authoritative control and post-control preparation projections'})
    return {'keyboard':keyboard,'vectors':vectors,'receivers':receivers,'ai_step':ai_step}


def java_string(value):
    return 'String.join("",new String[]{'+','.join(json.dumps(value[i:i+6144]) for i in range(0,len(value),6144))+'})'


def receiver_sources(inputs=None):
    encoded=base64.b64encode(canonical(inputs or {})).decode()
    return {name:source.replace('__CORPUS_INPUT_BASE64__',java_string(encoded))
            for name,source in RECEIVER_SOURCES.items()}


ROTATION_EXPERIMENT = r'''
  if(mode.equals("rotation")){
   for(boolean observed:List.of(false,true))for(int i=0;i<4;i++){
    Context c=new Context(lookup,observed);LocalPlayer p=c.player;c.keys(1);
    p.setYRot(17f);p.setXRot(-11f);p.yRotO=i==3?737f:12f;p.xRotO=i==3?349f:-9f;
    p.yHeadRot=17f;p.yHeadRotO=17f;p.yBodyRot=17f;p.yBodyRotO=17f;
    Map<String,Object> before=state(p);int oldCount=p.tickCount;
    if(i==1||i==2)p.commonTick();Map<String,Object> afterCommon=state(p);int afterCount=p.tickCount;
    if(i<2)p.aiStep();else p.tick();
    output(Map.of("id","rotation:"+i,"observed",observed,"operation",i==0?"aiStep":i==1?"commonTick then aiStep":i==2?"commonTick then actual LocalPlayer.tick":"actual LocalPlayer.tick without commonTick","before",before,"after_common",afterCommon,"expected",state(p),"tick_counts",List.of(oldCount,afterCount,p.tickCount),"observer_calls",observed?((ObservedPlayer)p).calls:List.of()));
   }
   return;
  }
'''


def receiver_prototype(mode, inputs=None, label=None):
    classpath, provenance = verified_client_classpath()
    sources=receiver_sources(inputs)
    if mode=='rotation':
        name='net.minecraft.fixture.LocalInputReceiverFixture'
        sources[name]=sources[name].replace('  if(mode.equals("corpus"))',ROTATION_EXPERIMENT+'  if(mode.equals("corpus"))',1)
    payload = {'sources': sources, 'client_jar': str(CLIENT), 'mode': mode}
    encoded = base64.b64encode(canonical(payload)).decode()
    launcher = RECEIVER_LAUNCHER.replace('Base64.getDecoder().decode(args[0])',
        'Base64.getDecoder().decode(String.join("",new String[]{'+
        ','.join(json.dumps(encoded[i:i+6144]) for i in range(0,len(encoded),6144))+'}))', 1)
    command = [str(JAVA), '--source', '25', '--class-path', ':'.join(map(str, classpath)), '/dev/stdin']
    start = time.monotonic()
    run = subprocess.run(command, input=launcher, capture_output=True, text=True)
    rows = [json.loads(line[len('LOCAL_RECEIVER_JSON:'):]) for line in run.stdout.splitlines()
            if line.startswith('LOCAL_RECEIVER_JSON:')]
    classes = [json.loads(line[len('LOCAL_INPUT_CLASSES:'):]) for line in run.stdout.splitlines()
               if line.startswith('LOCAL_INPUT_CLASSES:')]
    inventory = source_inventory()
    critical = [n for n in CLASSES if n not in RECEIVER_SOURCES]
    if run.returncode == 0:
        assert len(classes) == 1, 'Actual loaded official-class provenance missing'
        for name in critical:
            if name in classes[0]:
                assert classes[0][name] == inventory[name]['class_sha256'], 'Loaded official class bytes changed: '+name
        for name in ['net.minecraft.client.player.LocalPlayer','net.minecraft.client.player.AbstractClientPlayer','net.minecraft.world.entity.player.Player','net.minecraft.world.entity.Avatar','net.minecraft.world.entity.LivingEntity','net.minecraft.world.entity.Entity','net.minecraft.client.multiplayer.ClientLevel']:
            assert classes[0][name] == inventory[name]['class_sha256'], 'Normal receiver inheritance/world bytes not pinned'
        if mode in ('helpers','ai-step'):
            for i in range(6):
                plain = next(c for c in rows if c['id'] == f'receiver:false:{i}')
                observed = next(c for c in rows if c['id'] == f'receiver:true:{i}')
                for key in ['before','expected','can_start_sprinting','sprinting_possible']:
                    assert plain[key] == observed[key], 'Observer parity: '+key
        if mode=='rotation':
            for i in range(4):
                plain=next(c for c in rows if c['id']==f'rotation:{i}' and not c['observed'])
                observed=next(c for c in rows if c['id']==f'rotation:{i}' and c['observed'])
                for key in ('before','after_common','expected','tick_counts'):
                    assert plain[key]==observed[key],f'Actual rotation observer parity {i}: {key}'
    evidence = {
        'schema_version': 1,
        'status': 'passed' if run.returncode == 0 else 'blocked',
        'pin': '26.3',
        'scope': 'Bounded actual normal-constructed LocalPlayer input helpers and neutral aiStep with explicitly substituted external client services; real ClientLevel/collisions/attributes. The separate rotation mode calls actual commonTick and LocalPlayer.tick to observe camera snapshots/normalization only; no full Minecraft/client lifecycle parity claim.',
        'mode': mode,
        'provenance': provenance,
        'source': inventory,
        'substituted_external_types': {name: {'source_sha256':hashlib.sha256(source.encode()).hexdigest(), 'source':source}
            for name,source in RECEIVER_SOURCES.items() if name != 'net.minecraft.fixture.LocalInputReceiverFixture'},
        'fixture_source_sha256': {name:hashlib.sha256(source.encode()).hexdigest() for name,source in sources.items()},
        'fixture_template_sha256': {name:hashlib.sha256(source.encode()).hexdigest() for name,source in RECEIVER_SOURCES.items()},
        'launcher_source_sha256': hashlib.sha256(RECEIVER_LAUNCHER.encode()).hexdigest(),
        'loaded_official_classes': {name:classes[0][name] for name in critical if classes and name in classes[0]},
        'loaded_official_class_count': len(classes[0]) if classes else 0,
        'loaded_official_class_tree_sha256': hashlib.sha256(canonical(classes[0])).hexdigest() if classes else None,
        'execution': {
            'command': command,
            'reproduce': 'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_input_probe.py --extract' if mode=='corpus' else 'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_input_probe.py --rotation-experiment' if mode=='rotation' else f'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_input_probe.py --receiver {mode}',
            'returncode': run.returncode,
            'seconds': round(time.monotonic()-start,6),
            'input_sha256':hashlib.sha256(canonical(payload)).hexdigest(),
            'compiled_launcher_sha256':hashlib.sha256(launcher.encode()).hexdigest(),
            'stdout_sha256':hashlib.sha256(run.stdout.encode()).hexdigest(),
            'stderr_sha256':hashlib.sha256(run.stderr.encode()).hexdigest(),
            'stderr_tail':run.stderr[-9000:],
            'stdout_tail_on_failure':'\n'.join(line for line in run.stdout.splitlines() if not line.startswith('LOCAL_INPUT_CLASSES:'))[-9000:] if run.returncode else None,
        },
        'observations': rows,
        'observations_sha256':hashlib.sha256(canonical(rows)).hexdigest(),
        'constructor_boundary': 'All gameplay receivers use their normal constructors. Four exact external-service class names are defined from declared in-memory source; every official class is defined directly from unchanged installed jar bytes. No unsafe allocation, skipped constructor, gameplay replacement, UI or window is used. Observer methods call super and are compared against plain LocalPlayer receivers.',
    }
    destination = ROOT / f'evidence/local-input-reference-{label or "receiver-"+mode}.json'
    compact_report(destination,evidence,{'stdout':run.stdout,'stderr':run.stderr,
        'fixture_sources':sources,'compiled_launcher':launcher,
        'loaded_official_classes':classes[0] if classes else None})
    summary={'status':evidence['status'],'mode':mode,'returncode':run.returncode,'observation_count':len(rows),
            'evidence':fingerprint(destination),'failure':evidence['execution']['stdout_tail_on_failure'] or run.stderr[-6500:] if run.returncode else None}
    return (summary,evidence) if mode=='corpus' else summary


def collect(inputs, evidence):
    rows=evidence['observations']
    result={group:[] for group in GROUPS}
    by_id={}
    for row in rows:
        by_id.setdefault(row['id'],[]).append(row)
    for group in GROUPS:
        for case in inputs[group]:
            observations=by_id.pop(case['id'])
            if group in ('keyboard','vectors'):
                assert len(observations)==1
                result[group].append({**case,'expected':observations[0]['expected']})
                continue
            assert len(observations)==2
            plain=next(row for row in observations if not row['observed'])
            observed=next(row for row in observations if row['observed'])
            item={**case,'plain_observer_parity':True}
            if group=='receivers':
                for key in ('before','context','expected','can_start_sprinting','sprinting_possible'):
                    assert plain[key]==observed[key], f"Observer parity {case['id']} {key}"
                    item[key]=observed[key]
                item['observer_calls']=observed['observer_calls']
            else:
                assert len(plain['steps'])==len(observed['steps'])==len(case['steps'])
                item['input_steps']=item.pop('steps')
                item['steps']=[]
                for i,(plain_step,observed_step) in enumerate(zip(plain['steps'],observed['steps'])):
                    for key in ('before','context','expected'):
                        assert plain_step[key]==observed_step[key],f"Observer parity {case['id']}:{i} {key}"
                    step={**observed_step,'input':case['steps'][i]}
                    events=observed_step['observer_calls']
                    for method,key in [('jumpableVehicle_return_before_super_ai_step','control_snapshot'),
                                       ('applyInput_entry','before_apply_input'),('applyInput_exit','after_input'),
                                       ('travel_entry','pre_travel'),('travel_exit','post_travel')]:
                        matches=[event for event in events if event['method']==method]
                        assert len(matches)==1, f"Expected one actual {method}: {case['id']}:{i}"
                        step[key]=matches[0]
                    step['jump_calls']=[event for event in events if event['method'] in ('jumpFromGround','getJumpPower','getBlockJumpFactor')]
                    step['control_velocity_changed']=step['before']['velocity']!=step['control_snapshot']['state']['velocity']
                    item['steps'].append(step)
            result[group].append(item)
    assert not by_id, 'Unexpected actual observations'
    return result


def fixture_boundary():
    return {
        'constructor': 'Normal LocalPlayer, AbstractClientPlayer, Player, LivingEntity, Entity, ClientLevel and Options constructors; official bytes untouched. No Minecraft production constructor, UI, window or unsafe receiver allocation.',
        'external_service_types': sorted(name for name in RECEIVER_SOURCES if name!='net.minecraft.fixture.LocalInputReceiverFixture'),
        'external_context': [
            'Minecraft: identity getInstance/getCameraEntity/player/connection; options from real Options; isRunning false; getSoundManager null unused in admitted aiStep; gameMode null, unsupported flight branch.',
            'Gui.screen null; Tutorial.onInput records a sink call; ClientPacketListener deterministic profile, real PlayerInfo/Scoreboard/ClientClockManager/registry/features, outgoing send sink, hasClientLoaded true.',
            'Real ClientLevel constructor: finite stone floor x,z -2..2 at y=0, all other blocks air except explicitly labelled real oak top-slab ceiling cases; external getBlockState/getFluidState/getChunkForCollisions return actual states/this.',
            'Actual pinned overworld DimensionType copied unchanged except empty environment timelines; actual biome/damage registries cloned into real immutable registries, tags bound empty for this no-environment-effects context.',
            'Actual Options load reads the intentionally nonexistent /dev/null/reference-local-input-fixture/options.txt path; no installed user options are read or modified.',
            'AutoJump enabled field false; no portal, item use, rider/vehicle, swimming/fluid, fall flight, world effects, mayfly/flying aiStep or whole-client lifecycle admission.',
        ],
        'observers_call_super': ['applyInput','jumpableVehicle','setSprinting','travel','jumpFromGround','getJumpPower','getBlockJumpFactor'],
        'control_boundary': 'Snapshot is inside actual jumpableVehicle after super returns, before inherited AbstractClientPlayer.aiStep. Admitted null-vehicle branch subsequently only resets jumpRidingScale before super; no gameplay control substitution.',
        'sprint_updates': 'Only actual setSprinting calls observed before this control boundary; fixture initialization calls cleared. List order and duplicate calls preserved.',
        'preparation': 'Actual LocalPlayer.modifyInput performs .98 decay once. after_input and pre_travel project untouched inherited LivingEntity.aiStep cleanup/counters/jump using post-control body. No synthesized expected algorithm.',
        'jump_labels': 'jump_calls records actual Java calls, power/factor outputs and before/after jump state; project jump_attempted/jumped booleans are not vanilla fields and are not oracle observations.',
        'body': 'Cached speed field and resolved Player.getSpeed are separate; width/height use actual cached dimension getters, pose dimensions recorded separately.',
        'nonfinite': 'Direct static/Vec2 helper observations include nonfinite results with this pinned Java raw bits. NaN payload equality is a platform observation, not a general portability claim; aiStep inputs remain finite.',
        'scope': 'High confidence for recorded actual neutral input/control and preparation phases. Full Minecraft lifecycle, all LocalPlayer branches, networking, rendering, block-effects/world-travel breadth and full client parity are not established.',
    }


def extract(debug=False):
    inputs=corpus_inputs()
    if debug:
        inputs={g:cases[:2] for g,cases in inputs.items()}
    summary,evidence=receiver_prototype('corpus',inputs)
    if summary['status']!='passed':
        return summary
    observations=collect(inputs,evidence)
    if debug:
        return {**summary,'parity':'passed','debug':True}
    data={'schema_version':1,'pin':'26.3','random_input_seed':SEED,
          'inputs_sha256':hashlib.sha256(canonical(inputs)).hexdigest(),
          'observations_sha256':hashlib.sha256(canonical(observations)).hexdigest(),
          'provenance':evidence['provenance'],'source':evidence['source'],
          'fixture_template_sha256':evidence['fixture_template_sha256'],
          'fixture_source_sha256':evidence['fixture_source_sha256'],
          'launcher_source_sha256':evidence['launcher_source_sha256'],
          'loaded_official_classes':evidence['loaded_official_classes'],
          'loaded_official_class_count':evidence['loaded_official_class_count'],
          'loaded_official_class_tree_sha256':evidence['loaded_official_class_tree_sha256'],
          'fixture_boundary':fixture_boundary(),'confidence':'high for recorded bounded direct actual phases',
          **observations}
    data['counts']={g:len(observations[g]) for g in GROUPS}
    data['counts']['ai_step_ticks']=sum(len(case['steps']) for case in observations['ai_step'])
    write_json(OUTPUT,data)
    summary.update(reference=fingerprint(OUTPUT),counts=data['counts'],parity='passed')
    return summary


def verify_data(data,provenance,inventory):
    inputs=corpus_inputs()
    assert data['schema_version']==1 and data['pin']=='26.3'
    assert data['provenance']==provenance,'Installed client/metadata/runtime/libraries changed'
    assert data['source']==inventory,'Actual classes/method fingerprints changed'
    assert data['inputs_sha256']==hashlib.sha256(canonical(inputs)).hexdigest(),'Input corpus changed'
    assert data['fixture_template_sha256']=={n:hashlib.sha256(s.encode()).hexdigest() for n,s in RECEIVER_SOURCES.items()},'Receiver template changed'
    assert data['fixture_source_sha256']=={n:hashlib.sha256(s.encode()).hexdigest() for n,s in receiver_sources(inputs).items()},'Expanded receiver source changed'
    assert data['launcher_source_sha256']==hashlib.sha256(RECEIVER_LAUNCHER.encode()).hexdigest(),'Launcher source changed'
    assert data['fixture_boundary']==fixture_boundary(),'Fixture boundary changed'
    observations={g:data[g] for g in GROUPS}
    assert data['observations_sha256']==hashlib.sha256(canonical(observations)).hexdigest(),'Stored observations changed'
    assert data['counts']=={**{g:len(observations[g]) for g in GROUPS},'ai_step_ticks':sum(len(c['steps']) for c in observations['ai_step'])}
    required={name for name in CLASSES if name not in RECEIVER_SOURCES}
    assert set(data['loaded_official_classes'])==required,'Loaded official provenance missing'
    for name,digest in data['loaded_official_classes'].items():
        assert digest==inventory[name]['class_sha256'],'Loaded gameplay bytes changed'
    return True


def verify_existing(selftest=False):
    _,provenance=verified_client_classpath()
    inventory=source_inventory()
    data=json.loads(OUTPUT.read_text())
    verify_data(data,provenance,inventory)
    result={'status':'passed','reference':fingerprint(OUTPUT),'counts':data['counts'],
            'scope':'Integrity/provenance only; no new Java execution'}
    if selftest:
        import copy
        checks=[]
        for label,path in [('client',['provenance','client','sha256']),
                           ('runtime',['provenance','java','sha256']),
                           ('library',['provenance','libraries',0,'sha256']),
                           ('class',['source','net.minecraft.client.player.LocalPlayer','class_sha256']),
                           ('source',['launcher_source_sha256']),
                           ('observation',['keyboard',0,'expected','has_forward'])]:
            changed=copy.deepcopy(data);target=changed
            for key in path[:-1]:target=target[key]
            target[path[-1]]=not target[path[-1]] if isinstance(target[path[-1]],bool) else 'injected-mismatch'
            try:verify_data(changed,provenance,inventory)
            except AssertionError as rejected:checks.append({'injection':label,'rejected':True,'reason':str(rejected)})
            else:raise AssertionError('Integrity injection accepted: '+label)
        result['failure_injections']=checks
    write_json(ROOT/'evidence/local-input-reference-integrity.json',result)
    return result


def independent_rerun():
    data=json.loads(OUTPUT.read_text())
    _,provenance=verified_client_classpath()
    verify_data(data,provenance,source_inventory())
    summary,evidence=receiver_prototype('corpus',corpus_inputs(),label='independent')
    if summary['status']!='passed':return summary
    observations=collect(corpus_inputs(),evidence)
    assert observations=={g:data[g] for g in GROUPS},'Independent actual outputs differ'
    assert evidence['loaded_official_classes']==data['loaded_official_classes'],'Independent official gameplay classes differ'
    assert evidence['loaded_official_class_count']==data['loaded_official_class_count'],'Independent actual class count differs'
    assert evidence['loaded_official_class_tree_sha256']==data['loaded_official_class_tree_sha256'],'Independent actual official class tree differs'
    evidence['independent_actual_observation_parity']=True
    evidence['independent_actual_class_tree_parity']=True
    evidence['reference_compared']=fingerprint(OUTPUT)
    evidence['execution']['reproduce']='PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_input_probe.py --rerun'
    destination=ROOT/'evidence/local-input-reference-independent.json'
    raw=json.loads((ROOT/'build/local-input-reference'/f'{destination.stem}.full.json').read_text())['raw_execution']
    compact_report(destination,evidence,raw)
    summary.update(independent_actual_observation_parity=True,evidence=fingerprint(ROOT/'evidence/local-input-reference-independent.json'))
    return summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prototype', action='store_true')
    parser.add_argument('--receiver', choices=['helpers','ai-step'])
    parser.add_argument('--extract',action='store_true')
    parser.add_argument('--debug-corpus',action='store_true')
    parser.add_argument('--verify-existing',action='store_true')
    parser.add_argument('--selftest',action='store_true')
    parser.add_argument('--rerun',action='store_true')
    parser.add_argument('--rotation-experiment',action='store_true')
    parser.add_argument('--compact-existing',action='store_true',help='Compact/validate historical evidence without new Java execution')
    args = parser.parse_args()
    if args.compact_existing:
        print(json.dumps(compact_existing_reports(),indent=2));return
    if args.rerun:
        print(json.dumps(independent_rerun(),indent=2));return
    if args.rotation_experiment:
        print(json.dumps(receiver_prototype('rotation'),indent=2));return
    if args.verify_existing or args.selftest:
        print(json.dumps(verify_existing(args.selftest),indent=2));return
    if args.extract or args.debug_corpus:
        print(json.dumps(extract(args.debug_corpus),indent=2));return
    if args.receiver:
        print(json.dumps(receiver_prototype(args.receiver),indent=2))
        return
    if not args.prototype:
        parser.error('Select --extract, --verify-existing, --selftest, --prototype or --receiver.')
    print(json.dumps(prototype(), indent=2))


if __name__ == '__main__':
    main()
