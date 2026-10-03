#!/usr/bin/env python3
"""Pinned MouseHandler movement/neutral-turn observations without an OS window.

Only fixture construction uses Unsafe. Actual MouseHandler constructors/onMove/
turnPlayer, OptionInstance constructors/get, inactive Tutorial.onMouse and inherited
Entity.turn execute. This is not a handleAccumulatedMovement or OS-input oracle.
"""
from __future__ import annotations
import argparse
import collections
import hashlib
import json
import math
import random
import struct
import subprocess
import zipfile

from reference_inventory import ROOT, JAVA, fingerprint
from reference_model_probe import CLIENT, verified_client_classpath

OUTPUT = ROOT / 'reference/mouse_input.json'
CACHE = ROOT / 'reference/cache/mouse-input-probe'
HANDLE = '0000000000263001'
LOG_CONFIG = '''<?xml version="1.0" encoding="UTF-8"?>
<Configuration status="ERROR"><Appenders><Console name="ProbeConsole" target="SYSTEM_ERR" follow="true"><PatternLayout pattern="%level|%logger|%message%n"/></Console></Appenders><Loggers><Root level="warn"><AppenderRef ref="ProbeConsole"/></Root></Loggers></Configuration>
'''


def canonical(value):
    return json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(',', ':')).encode('ascii')


def sha(value):
    return hashlib.sha256(value).hexdigest()


def b32(value):
    return f'{struct.unpack(">I", struct.pack(">f", value))[0]:08x}'


def b64(value):
    return f'{struct.unpack(">Q", struct.pack(">d", value))[0]:016x}'


def from64(bits):
    return struct.unpack('>d', struct.pack('>Q', bits))[0]


def from32(bits):
    return struct.unpack('>f', struct.pack('>I', bits))[0]


def fixtures():
    cases = []
    def initial(**kwargs):
        result = {'state_f32_bits': [b32(v) for v in (10, 20, 30, 40)],
                  'mouse_f64_bits': [b64(0)] * 4, 'ignore_first_move': False,
                  'mouse_grabbed': True, 'focused': True, 'sensitivity_f64_bits': b64(.5),
                  'invert_x': False, 'invert_y': False,
                  'smooth_x_f64_bits': [b64(0)] * 3, 'smooth_y_f64_bits': [b64(0)] * 3}
        result.update(kwargs)
        return result
    def move(x, y, dx, dy, handle=HANDLE):
        return {'op': 'move', 'window_handle': handle, 'x_f64_bits': b64(x), 'y_f64_bits': b64(y),
                'relative_x_f64_bits': b64(dx), 'relative_y_f64_bits': b64(dy)}
    def rawmove(bits, axis='x'):
        event = move(100, 200, 0, 0)
        event['relative_' + axis + '_f64_bits'] = f'{bits:016x}'
        return event
    def turn(elapsed=1 / 60):
        return {'op': 'turn', 'elapsed_f64_bits': b64(elapsed)}
    def add(name, category, state, events):
        cases.append({'id': name, 'category': category, 'initial': state, 'events': events})
    add('default_unit_scale', 'initial-semantics', initial(mouse_f64_bits=[b64(0), b64(0), b64(1), b64(1)]), [turn()])
    add('captured_relative', 'initial-semantics', initial(), [move(500, -600, 2, -3), turn(), turn()])
    add('uncaptured_absolute', 'initial-semantics', initial(mouse_grabbed=False, mouse_f64_bits=list(map(b64, (10, 20, 0, 0)))), [move(12, 17, 1000, -1000), turn()])
    add('first_move_then_relative', 'initial-semantics', initial(ignore_first_move=True), [move(100, 200, 99, 88), move(101, 202, 3, -4), turn()])
    add('wrong_window_preserves_first', 'initial-semantics', initial(ignore_first_move=True), [move(100, 200, 99, 88, '0000000000000000'), move(100, 200, 99, 88, '0000000000263002'), move(1, 2, 3, 4), turn()])
    add('unfocused_moves_update_position', 'initial-semantics', initial(focused=False, mouse_grabbed=False), [move(100, 200, 3, 4), {'op': 'set_focus', 'value': True}, move(101, 198, 300, 400), turn()])
    add('first_move_while_unfocused', 'initial-semantics', initial(focused=False, ignore_first_move=True), [move(100, 200, 3, 4), turn()])
    for ix in (False, True):
        for iy in (False, True):
            add(f'inversion_{int(ix)}_{int(iy)}', 'tutorial-before-inversion', initial(invert_x=ix, invert_y=iy), [move(100, 200, 2, -3), turn()])
    add('normal_branch_resets_smoothing', 'neutral-filter-reset', initial(smooth_x_f64_bits=list(map(b64, (13, -7, 5))), smooth_y_f64_bits=list(map(b64, (-11, 3, -1)))), [move(100, 200, 1, 2), turn()])
    add('separate_frame_drain', 'explicit-wrapper-drain-fixture', initial(ignore_first_move=True),
        [move(100, 200, 99, 88), move(101, 202, 1, -2), turn(), {'op': 'clear_accumulation'},
         move(103, 204, 3, -4), turn(), {'op': 'clear_accumulation'},
         {'op': 'set_focus', 'value': False}, move(500, 600, 111, 222),
         {'op': 'set_focus', 'value': True}, {'op': 'set_grabbed', 'value': False},
         move(503, 604, 333, 444), turn(), {'op': 'clear_accumulation'},
         {'op': 'set_grabbed', 'value': True}, {'op': 'set_ignore_first'}, move(0, 0, 999, 888),
         move(1, 2, -1, 2), turn(), {'op': 'clear_accumulation'}])
    # All handle/focus/capture/first-event combinations and transitions are
    # passed to the actual methods; no expected movement rule is computed here.
    for handle in ('0000000000000000', HANDLE, '0000000000263002', 'ffffffffffffffff'):
        for focused in (False, True):
            for grabbed in (False, True):
                for first in (False, True):
                    state = initial(focused=focused, mouse_grabbed=grabbed, ignore_first_move=first,
                                    mouse_f64_bits=list(map(b64, (10, 20, 5, -7))))
                    add(f'gates_{handle}_{int(focused)}_{int(grabbed)}_{int(first)}', 'window-focus-capture-first-gates', state,
                        [move(12, 17, 100, -200, handle), turn(0), {'op': 'set_focus', 'value': not focused},
                         {'op': 'set_grabbed', 'value': not grabbed}, {'op': 'set_ignore_first'}, move(40, 50, 8, 9), move(41, 52, -2, 3), turn(100)])
    sensitivities = {0, 1 << 63, 1, 0x0010000000000000, 0x3fd0000000000000,
                     0x3fe0000000000000 - 1, 0x3fe0000000000000, 0x3fe0000000000000 + 1,
                     0x3ff0000000000000 - 1, 0x3ff0000000000000}
    sensitivities.update(int(b64(i / 128), 16) for i in range(129))
    for bits in sorted(sensitivities):
        for ix, iy in ((False, False), (True, True)):
            add(f'sensitivity_{bits:016x}_{int(ix)}', 'sensitivity-range-boundaries',
                initial(sensitivity_f64_bits=f'{bits:016x}', invert_x=ix, invert_y=iy, mouse_f64_bits=list(map(b64, (0, 0, 1, -1)))), [turn()])
    delta_bits = {0, 1 << 63, 1, (1 << 63) | 1, 0x000fffffffffffff, 0x0010000000000000,
                  0x7fefffffffffffff, 0xffefffffffffffff}
    for value in (math.ldexp(1.0, -150), math.ldexp(1.0, -149), math.ldexp(1.0, -148),
                  .5, 1., 600., 2400., math.ldexp(1., 128) - math.ldexp(1., 103)):
        center = int(b64(value), 16)
        for bits in range(center - 2, center + 3):
            delta_bits.add(bits); delta_bits.add(bits | (1 << 63))
    for raw in (0, 1, 2, 3, 0x7fffff, 0x800000, 0x3f000000, 0x3f7fffff,
                0x3f800000, 0x3fffffff, 0x447a0000, 0x7f7ffffe):
        for value in (from32(raw), from32(raw + 1), (from32(raw) + from32(raw + 1)) / 2):
            center = int(b64(value), 16)
            for bits in range(max(0, center - 1), center + 2):
                delta_bits.add(bits); delta_bits.add(bits | (1 << 63))
    for index, bits in enumerate(sorted(delta_bits)):
        for axis in ('x', 'y'):
            add(f'finite_relative_{axis}_{index}', 'finite-relative-float-narrow-boundaries', initial(), [rawmove(bits, axis), turn()])
    for mask in range(256):
        bits = ['8000000000000000' if mask & (1 << i) else b64(0) for i in range(4)]
        event = move(-0.0 if mask & 16 else 0, -0.0 if mask & 32 else 0, -0.0 if mask & 64 else 0, -0.0 if mask & 128 else 0)
        add(f'signed_zero_{mask}', 'signed-zero-accumulation', initial(mouse_f64_bits=bits,
            state_f32_bits=['80000000'] * 4, invert_x=bool(mask & 16), invert_y=bool(mask & 32), mouse_grabbed=bool(mask & 64)), [event, turn()])
    # Repeat turnPlayer without resetting accumulation: the wrapper's reset
    # belongs to unexecuted handleAccumulatedMovement, not to turnPlayer.
    add('turn_does_not_reset_accumulation', 'wrapper-boundary', initial(), [move(99, 88, 1, -1), turn(0), turn(1), turn(1000000)])
    pair_rng = random.Random(0x26_03_5041)
    small = math.ldexp(1.0, -149)
    pairs = [(0.0, -0.0), (-0.0, 0.0), (from64(1), -from64(1)), (small, -small),
             (math.ldexp(1.0, -126), small), (1.0, -1.0), (600.0, -600.0),
             (2400.0, -1800.0), (math.ldexp(1.0, 53), -math.ldexp(1.0, 53)),
             (1.0, math.ldexp(1.0, -53)), (from64(0x3ff0000000000001), -.5),
             (1e-300, -1e-300), (-600.0, 2400.0), (2.0, -3.0),
             (pair_rng.uniform(-1000, 1000), pair_rng.uniform(-1000, 1000)),
             (pair_rng.uniform(-1000, 1000), pair_rng.uniform(-1000, 1000))]
    for i in range(64):
        a, b = pairs[i % 16]
        if i & 16:
            a, b = b, a
        x, y = pair_rng.uniform(-1000, 1000), pair_rng.uniform(-1000, 1000)
        state = initial(ignore_first_move=bool(i & 32), invert_x=bool(i & 4), invert_y=bool(i & 8),
                        mouse_f64_bits=list(map(b64, (x, y, 1 if i % 16 == 8 else 0, -1 if i % 16 == 8 else 0))))
        add(f'two_move_native_pipeline_{i}', 'two-move-native-pipeline', state,
            [move(x + 1, y - 2, a, b), move(x - 3, y + 4, b, a), turn()])
    for i in range(32):
        a, b = pairs[i % 16]
        x, y = pair_rng.uniform(-1000, 1000), pair_rng.uniform(-1000, 1000)
        add(f'two_move_uncaptured_diagnostic_{i}', 'two-move-uncaptured-diagnostic',
            initial(mouse_grabbed=False, ignore_first_move=bool(i & 16), mouse_f64_bits=list(map(b64, (x, y, 0, 0)))),
            [move(x + a, y + b, 111, -222), move(x + b, y + a, -333, 444), turn()])
    rng = random.Random(0x26_03_4d49)
    def finite64():
        while True:
            bits = rng.getrandbits(64)
            if bits & 0x7ff0000000000000 != 0x7ff0000000000000:
                return f'{bits:016x}'
    for i in range(256):
        state = initial(mouse_f64_bits=[finite64() for _ in range(4)], sensitivity_f64_bits=b64(rng.random()),
                        focused=bool(rng.getrandbits(1)), mouse_grabbed=bool(rng.getrandbits(1)),
                        ignore_first_move=bool(rng.getrandbits(1)), invert_x=bool(rng.getrandbits(1)), invert_y=bool(rng.getrandbits(1)))
        events = []
        for j in range(3):
            events.append({'op': 'move', 'window_handle': HANDLE, **dict(zip(
                ('x_f64_bits', 'y_f64_bits', 'relative_x_f64_bits', 'relative_y_f64_bits'), [finite64() for _ in range(4)], strict=True))})
            if j == 0:
                events.extend((turn(), {'op': 'set_focus', 'value': True}, {'op': 'set_grabbed', 'value': not state['mouse_grabbed']}))
        events.extend((turn(), {'op': 'clear_accumulation'}, turn(-1)))
        add(f'finite_sequence_{i}', 'seeded-raw-finite-sequences', state, events)
    for bits in (0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000000123, 0x7ff0000000000001):
        for axis in ('x', 'y'):
            add(f'nonfinite_relative_{axis}_{bits:016x}', 'outside-finite-admission', initial(), [rawmove(bits, axis), turn()])
    assert len(cases) == len({c['id'] for c in cases})
    return cases


JAVA_SOURCE = r'''
import com.google.gson.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.client.*;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.client.tutorial.Tutorial;
import net.minecraft.world.entity.Entity;
import net.minecraft.network.chat.Component;
import com.mojang.blaze3d.platform.Window;
import java.io.*;
import java.nio.file.*;
import java.nio.charset.*;
import java.lang.reflect.*;
import java.util.*;
import sun.misc.Unsafe;

class ReferenceMouseInputProbe {
 static final Gson G=new GsonBuilder().serializeNulls().disableHtmlEscaping().create();
 static Unsafe U;static Method TURN;static Field Y,X,YO,XO;static ArrayList<JsonObject> TRACE;static JsonObject CONSTRUCTOR_STATE;
 static final long HANDLE=0x263001L;
 static String f(float v){return String.format("%08x",Float.floatToRawIntBits(v));}
 static String d(double v){return String.format("%016x",Double.doubleToRawLongBits(v));}
 static double d(JsonElement v){return Double.longBitsToDouble(Long.parseUnsignedLong(v.getAsString(),16));}
 static float f(JsonElement v){return Float.intBitsToFloat((int)Long.parseUnsignedLong(v.getAsString(),16));}
 static Field field(Class<?> c,String name)throws Exception{var f=c.getDeclaredField(name);f.setAccessible(true);return f;}
 static void put(Object object,String name,Object value)throws Exception{field(object.getClass(),name).set(object,value);}
 static JsonArray floats(Entity e)throws Exception{var a=new JsonArray();for(var field:List.of(Y,X,YO,XO))a.add(f(field.getFloat(e)));return a;}
 static JsonArray doubles(Object o,Class<?> c,String...names)throws Exception{var a=new JsonArray();for(var name:names)a.add(d(field(c,name).getDouble(o)));return a;}
 static void setDoubles(Object o,Class<?> c,JsonArray values,String...names)throws Exception{for(int i=0;i<names.length;i++)field(c,names[i]).setDouble(o,d(values.get(i)));}
 static class ObservedPlayer extends LocalPlayer {
  ObservedPlayer(){super(null,null,null,null,null,null,false,null,null);throw new AssertionError("player constructor must not run");}
  @Override public void turn(double dx,double dy){try{var j=new JsonObject();j.addProperty("method","LocalPlayer.turn");j.addProperty("dx_f64_bits",d(dx));j.addProperty("dy_f64_bits",d(dy));j.add("before_state_f32_bits",floats(this));super.turn(dx,dy);j.add("after_state_f32_bits",floats(this));TRACE.add(j);}catch(Exception e){throw new AssertionError(e);}}
 }
 static class ObservedTutorial extends Tutorial {
  ObservedTutorial(Minecraft mc,Options options){super(mc,options);}
  @Override public void onMouse(double dx,double dy){var j=new JsonObject();j.addProperty("method","Tutorial.onMouse");j.addProperty("dx_f64_bits",d(dx));j.addProperty("dy_f64_bits",d(dy));TRACE.add(j);super.onMouse(dx,dy);}
 }
 static Map<Field,Object> fields(Object o,Class<?> start,Set<String> excluded)throws Exception{var map=new HashMap<Field,Object>();for(Class<?> c=start;c!=Object.class;c=c.getSuperclass())for(var f:c.getDeclaredFields())if(!Modifier.isStatic(f.getModifiers())&&!excluded.contains(c.getName()+"."+f.getName())){f.setAccessible(true);Object value=f.get(o);if(f.getType()==float.class)value=Float.floatToRawIntBits((Float)value);if(f.getType()==double.class)value=Double.doubleToRawLongBits((Double)value);map.put(f,value);}return map;}
 static boolean sameFields(List<Map<Field,Object>> before,List<Map<Field,Object>> after){if(before.size()!=after.size())return false;for(int i=0;i<before.size();i++){var a=before.get(i);var b=after.get(i);if(!a.keySet().equals(b.keySet()))return false;for(var f:a.keySet())if(f.getType().isPrimitive()?!Objects.equals(a.get(f),b.get(f)):a.get(f)!=b.get(f))return false;}return true;}
 static class Fixture {
  Minecraft mc;Options options;LocalPlayer player;Tutorial tutorial;Window window;MouseHandler mouse;
  Object sx,sy;
  Fixture(JsonObject initial,boolean observed)throws Exception{
   mc=(Minecraft)U.allocateInstance(Minecraft.class);options=(Options)U.allocateInstance(Options.class);
   window=(Window)U.allocateInstance(Window.class);field(Window.class,"handle").setLong(window,HANDLE);field(Window.class,"focused").setBoolean(window,initial.get("focused").getAsBoolean());
   player=(LocalPlayer)U.allocateInstance(observed?ObservedPlayer.class:LocalPlayer.class);
   field(LocalPlayer.class,"startedUsingItem").setBoolean(player,false);field(Entity.class,"vehicle").set(player,null);
   int i=0;for(var f:List.of(Y,X,YO,XO))f.setFloat(player,f(initial.getAsJsonArray("state_f32_bits").get(i++)));
   field(Options.class,"sensitivity").set(options,new OptionInstance<Double>("options.sensitivity",OptionInstance.noTooltip(),(caption,value)->Component.literal("fixture"),OptionInstance.UnitDouble.INSTANCE,d(initial.get("sensitivity_f64_bits")),OptionInstance.NO_ACTION));
   field(Options.class,"invertXMouse").set(options,OptionInstance.createBoolean("options.invertMouseX",initial.get("invert_x").getAsBoolean()));
   field(Options.class,"invertYMouse").set(options,OptionInstance.createBoolean("options.invertMouseY",initial.get("invert_y").getAsBoolean()));
   options.smoothCamera=false;field(Options.class,"cameraType").set(options,CameraType.FIRST_PERSON);
   tutorial=observed?new ObservedTutorial(mc,options):new Tutorial(mc,options);
   field(Minecraft.class,"options").set(mc,options);field(Minecraft.class,"player").set(mc,player);field(Minecraft.class,"tutorial").set(mc,tutorial);field(Minecraft.class,"window").set(mc,window);
   mouse=new MouseHandler(mc);var constructed=new JsonObject();constructed.add("mouse_f64_bits",doubles(mouse,MouseHandler.class,"xpos","ypos","accumulatedDX","accumulatedDY"));constructed.addProperty("ignore_first_move",field(MouseHandler.class,"ignoreFirstMove").getBoolean(mouse));constructed.addProperty("mouse_grabbed",field(MouseHandler.class,"mouseGrabbed").getBoolean(mouse));constructed.addProperty("last_handle_movement_time_f64_bits",d(field(MouseHandler.class,"lastHandleMovementTime").getDouble(mouse)));if(CONSTRUCTOR_STATE==null)CONSTRUCTOR_STATE=constructed;else if(!CONSTRUCTOR_STATE.equals(constructed))throw new AssertionError("constructor defaults vary");field(MouseHandler.class,"ignoreFirstMove").setBoolean(mouse,initial.get("ignore_first_move").getAsBoolean());field(MouseHandler.class,"mouseGrabbed").setBoolean(mouse,initial.get("mouse_grabbed").getAsBoolean());
   setDoubles(mouse,MouseHandler.class,initial.getAsJsonArray("mouse_f64_bits"),"xpos","ypos","accumulatedDX","accumulatedDY");
   sx=field(MouseHandler.class,"smoothTurnX").get(mouse);sy=field(MouseHandler.class,"smoothTurnY").get(mouse);
   setDoubles(sx,sx.getClass(),initial.getAsJsonArray("smooth_x_f64_bits"),"targetValue","remainingValue","lastAmount");setDoubles(sy,sy.getClass(),initial.getAsJsonArray("smooth_y_f64_bits"),"targetValue","remainingValue","lastAmount");
   if(player.getVehicle()!=null||player.isUsingItem()||player.isScoping()||options.smoothCamera||options.getCameraType()!=CameraType.FIRST_PERSON||field(Tutorial.class,"instance").get(tutorial)!=null)throw new AssertionError("neutral branch fixture invalid");
   if(!d(options.sensitivity().get()).equals(initial.get("sensitivity_f64_bits").getAsString())||!floats(player).equals(initial.getAsJsonArray("state_f32_bits")))throw new AssertionError("fixture raw bits changed");
  }
  List<Map<Field,Object>> unchanged()throws Exception{
   return List.of(fields(mc,Minecraft.class,Set.of()),fields(options,Options.class,Set.of()),fields(window,Window.class,Set.of()),fields(tutorial,Tutorial.class,Set.of()),fields(player,LocalPlayer.class,Set.of(Entity.class.getName()+".yRot",Entity.class.getName()+".xRot",Entity.class.getName()+".yRotO",Entity.class.getName()+".xRotO")),fields(mouse,MouseHandler.class,Set.of(MouseHandler.class.getName()+".xpos",MouseHandler.class.getName()+".ypos",MouseHandler.class.getName()+".accumulatedDX",MouseHandler.class.getName()+".accumulatedDY",MouseHandler.class.getName()+".ignoreFirstMove")));
  }
  JsonObject state()throws Exception{var o=new JsonObject();o.add("state_f32_bits",floats(player));o.add("mouse_f64_bits",doubles(mouse,MouseHandler.class,"xpos","ypos","accumulatedDX","accumulatedDY"));o.addProperty("ignore_first_move",field(MouseHandler.class,"ignoreFirstMove").getBoolean(mouse));o.addProperty("mouse_grabbed",field(MouseHandler.class,"mouseGrabbed").getBoolean(mouse));o.addProperty("focused",window.isFocused());o.add("smooth_x_f64_bits",doubles(sx,sx.getClass(),"targetValue","remainingValue","lastAmount"));o.add("smooth_y_f64_bits",doubles(sy,sy.getClass(),"targetValue","remainingValue","lastAmount"));return o;}
  JsonObject invoke(JsonObject event,boolean observed)throws Exception{
   String op=event.get("op").getAsString();boolean production=op.equals("move")||op.equals("turn")||op.equals("set_ignore_first");
   var before=unchanged();var out=new ByteArrayOutputStream();var err=new ByteArrayOutputStream();var savedOut=System.out;var savedErr=System.err;Throwable failure=null;TRACE=new ArrayList<>();
   try{System.setOut(new PrintStream(out,true,StandardCharsets.UTF_8));System.setErr(new PrintStream(err,true,StandardCharsets.UTF_8));
    switch(op){case "move"->mouse.onMove(Long.parseUnsignedLong(event.get("window_handle").getAsString(),16),d(event.get("x_f64_bits")),d(event.get("y_f64_bits")),d(event.get("relative_x_f64_bits")),d(event.get("relative_y_f64_bits")));case "turn"->TURN.invoke(mouse,d(event.get("elapsed_f64_bits")));case "set_ignore_first"->mouse.setIgnoreFirstMove();case "set_focus"->field(Window.class,"focused").setBoolean(window,event.get("value").getAsBoolean());case "set_grabbed"->field(MouseHandler.class,"mouseGrabbed").setBoolean(mouse,event.get("value").getAsBoolean());case "clear_accumulation"->{field(MouseHandler.class,"accumulatedDX").setDouble(mouse,0.0);field(MouseHandler.class,"accumulatedDY").setDouble(mouse,0.0);}default->throw new AssertionError("unknown event");}
   }catch(Throwable t){failure=t instanceof InvocationTargetException?((InvocationTargetException)t).getCause():t;}finally{System.setOut(savedOut);System.setErr(savedErr);}
   if(production&&!sameFields(before,unchanged()))throw new AssertionError("unexpected unrelated fixture field mutation for "+op);
   var o=state();o.addProperty("exception_class",failure==null?null:failure.getClass().getName());o.addProperty("exception_message",failure==null?null:failure.getMessage());o.addProperty("stdout",out.toString(StandardCharsets.UTF_8));o.addProperty("stderr",err.toString(StandardCharsets.UTF_8));o.addProperty("unrelated_fields_unchanged",production?Boolean.TRUE:null);o.addProperty("event_boundary",production?"actual-production-call":"explicit-fixture-field-mutation");if(observed)o.add("trace",G.toJsonTree(TRACE));return o;
  }
 }
 public static void main(String[] args)throws Exception{try{run(args);}catch(Throwable failure){var text=new StringWriter();failure.printStackTrace(new PrintWriter(text));Files.writeString(Path.of(args[1]+".failure"),text.toString());throw failure;}}
 static void run(String[] args)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();if(SharedConstants.IS_RUNNING_IN_IDE)throw new AssertionError("IDE pause enabled");
  var unsafe=Unsafe.class.getDeclaredField("theUnsafe");unsafe.setAccessible(true);U=(Unsafe)unsafe.get(null);Y=field(Entity.class,"yRot");X=field(Entity.class,"xRot");YO=field(Entity.class,"yRotO");XO=field(Entity.class,"xRotO");TURN=MouseHandler.class.getDeclaredMethod("turnPlayer",double.class);TURN.setAccessible(true);
  var owners=new JsonObject();for(var name:List.of("turn","getXRot","getYRot","setXRot","setYRot","getVehicle")){Class<?>[] params=name.equals("turn")?new Class<?>[]{double.class,double.class}:name.startsWith("set")?new Class<?>[]{float.class}:new Class<?>[]{};var method=LocalPlayer.class.getMethod(name,params);owners.addProperty(name,method.getDeclaringClass().getName());if(method.getDeclaringClass()!=Entity.class)throw new AssertionError("unexpected LocalPlayer rotation override "+name);}
  var in=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonArray();var cases=new JsonArray();boolean first=true;
  for(var item:in){var input=item.getAsJsonObject();var plain=new Fixture(input.getAsJsonObject("initial"),false);var observed=new Fixture(input.getAsJsonObject("initial"),true);if(first){TURN.invoke(plain.mouse,0.0);plain=new Fixture(input.getAsJsonObject("initial"),false);first=false;}var steps=new JsonArray();
   for(var event:input.getAsJsonArray("events")){var a=plain.invoke(event.getAsJsonObject(),false);var b=observed.invoke(event.getAsJsonObject(),true);var trace=b.remove("trace");if(!a.equals(b))throw new AssertionError("observer changed raw production result "+input.get("id")+" "+event);a.add("trace",trace);a.addProperty("unmodified_receiver_match",true);steps.add(a);}
   var result=new JsonObject();result.addProperty("id",input.get("id").getAsString());result.add("steps",steps);cases.add(result);
  }
  var result=new JsonObject();result.add("production_rotation_method_owners",owners);result.addProperty("is_running_in_ide",false);result.addProperty("actual_window_created",false);result.addProperty("actual_mouse_handler_constructor",true);result.add("actual_mouse_handler_constructor_state",CONSTRUCTOR_STATE);result.addProperty("actual_option_instance_constructors",true);result.addProperty("actual_inactive_tutorial_constructor",true);result.addProperty("mouse_handle_accumulated_movement_invoked",false);result.add("cases",cases);Files.writeString(Path.of(args[1]),G.toJson(result));
 }
}
'''


def source_records(classpath):
    names = ['net.minecraft.client.MouseHandler', 'net.minecraft.client.Minecraft', 'net.minecraft.client.Options',
             'net.minecraft.client.OptionInstance', 'net.minecraft.client.OptionInstance$UnitDouble',
             'net.minecraft.client.tutorial.Tutorial', 'net.minecraft.client.player.LocalPlayer',
             'net.minecraft.world.entity.player.Player', 'net.minecraft.world.entity.Entity',
             'net.minecraft.client.CameraType', 'net.minecraft.util.SmoothDouble', 'net.minecraft.util.Mth',
             'net.minecraft.util.Util', 'com.mojang.blaze3d.platform.Window', 'com.mojang.blaze3d.Blaze3D',
             'net.minecraft.SharedConstants', 'net.minecraft.server.Bootstrap', 'net.minecraft.client.ScrollWheelHandler']
    with zipfile.ZipFile(CLIENT) as archive:
        records = []
        for name in names:
            raw = archive.read(name.replace('.', '/') + '.class')
            records.append({'class': name, 'bytes': len(raw), 'sha256': sha(raw)})
    run = subprocess.run([str(JAVA.with_name('javap')), '-p', '-c', '-classpath', ':'.join(map(str, classpath)), *names], capture_output=True, text=True, check=True)
    path = CACHE / 'production-javap.txt'
    path.write_text(run.stdout)
    return {'classes': records, 'javap': fingerprint(path), 'java_harness_sha256': sha(JAVA_SOURCE.encode()),
            'logging_config_sha256': sha(LOG_CONFIG.encode()),
            'python_probe': fingerprint(ROOT / 'tools/reference_mouse_input_probe.py'),
            'classpath_verifier': fingerprint(ROOT / 'tools/reference_model_probe.py'),
            'authority': 'Direct pinned MouseHandler.onMove/turnPlayer calls; bytecode inspected only to establish safe neutral fixture construction, method ownership and unexecuted wrapper boundary'}


def execute(inputs, classpath, tag):
    CACHE.mkdir(parents=True, exist_ok=True)
    source, config = CACHE / 'ReferenceMouseInputProbe.java', CACHE / 'log4j2-probe.xml'
    source.write_text(JAVA_SOURCE)
    config.write_text(LOG_CONFIG)
    input_path, output_path = CACHE / (tag + '-inputs.json'), CACHE / (tag + '-observations.json')
    input_path.write_bytes(canonical(inputs))
    command = [str(JAVA), '-Dlog4j.configurationFile=' + str(config), '-cp', ':'.join(map(str, classpath)), str(source), str(input_path), str(output_path)]
    run = subprocess.run(command, cwd=CACHE, capture_output=True, text=True, timeout=180)
    (CACHE / (tag + '-stdout.log')).write_text(run.stdout)
    (CACHE / (tag + '-stderr.log')).write_text(run.stderr)
    if run.returncode:
        failure_path = output_path.with_name(output_path.name + '.failure')
        failure = failure_path.read_text() if failure_path.exists() else ''
        raise RuntimeError('Java mouse input probe failed: ' + failure[-9000:] + run.stderr[-9000:] + run.stdout[-2000:])
    observations = json.loads(output_path.read_text())
    return observations, {'exit_code': run.returncode, 'raw_observation_sha256': sha(output_path.read_bytes()),
                          'stdout': fingerprint(CACHE / (tag + '-stdout.log')), 'stderr': fingerprint(CACHE / (tag + '-stderr.log'))}


def counts(observations):
    steps = [step for case in observations['cases'] for step in case['steps']]
    traces = [record for step in steps for record in step['trace']]
    return {'cases': len(observations['cases']), 'steps_per_receiver': len(steps),
            'production_events_per_receiver': sum(s['event_boundary'] == 'actual-production-call' for s in steps),
            'fixture_mutations_per_receiver': sum(s['event_boundary'] == 'explicit-fixture-field-mutation' for s in steps),
            'exception_steps': sum(s['exception_class'] is not None for s in steps),
            'logged_steps': sum(bool(s['stdout'] or s['stderr']) for s in steps),
            'unmodified_receiver_matches': sum(s['unmodified_receiver_match'] for s in steps),
            'tutorial_calls_traced': sum(t['method'] == 'Tutorial.onMouse' for t in traces),
            'player_turn_calls_traced': sum(t['method'] == 'LocalPlayer.turn' for t in traces)}


def validate(data, inputs=None, observations=None, provenance=None, source=None):
    if data.get('schema') != 1 or data.get('pin') != '26.3':
        raise ValueError('mouse reference schema/pin mismatch')
    for name in ('inputs', 'observations'):
        if sha(canonical(data[name])) != data[name + '_sha256']:
            raise ValueError(name + ' checksum mismatch')
    for name, actual in (('inputs', inputs), ('observations', observations), ('provenance', provenance), ('source', source)):
        if actual is not None and data[name] != actual:
            raise ValueError(name + ' differs from fresh production observation')
    if data['counts'] != counts(data['observations']):
        raise ValueError('counts mismatch')
    if [c['id'] for c in data['inputs']] != [c['id'] for c in data['observations']['cases']]:
        raise ValueError('fixture identities/order mismatch')
    for case, result in zip(data['inputs'], data['observations']['cases'], strict=True):
        if len(case['events']) != len(result['steps']):
            raise ValueError('event observation mismatch')
        for event, step in zip(case['events'], result['steps'], strict=True):
            if not step['unmodified_receiver_match'] or (event['op'] in ('move', 'turn', 'set_ignore_first') and not step['unrelated_fields_unchanged']):
                raise ValueError('observer/unrelated field boundary violated')
            for field, length, width in (('state_f32_bits', 4, 8), ('mouse_f64_bits', 4, 16), ('smooth_x_f64_bits', 3, 16), ('smooth_y_f64_bits', 3, 16)):
                if len(step[field]) != length or not all(len(bits) == width and all(c in '0123456789abcdef' for c in bits) for bits in step[field]):
                    raise ValueError('invalid raw floating encoding')
    return {'status': 'pass', 'counts': data['counts'], 'observations_sha256': data['observations_sha256']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['extract', 'selftest', 'validate', 'early'], nargs='?', default='extract')
    args = parser.parse_args()
    if args.action == 'validate':
        print(json.dumps(validate(json.loads(OUTPUT.read_text()))))
        return
    classpath, provenance = verified_client_classpath()
    inputs = fixtures()
    if args.action == 'early':
        observations, run = execute(inputs[:12], classpath, 'early')
        print(json.dumps(observations, sort_keys=True))
        return
    observations, run = execute(inputs, classpath, args.action + '-a')
    source = source_records(classpath)
    if args.action == 'selftest':
        data = json.loads(OUTPUT.read_text())
        check = validate(data, inputs, observations, provenance, source)
        other, other_run = execute(inputs, classpath, 'selftest-b')
        validate(data, inputs, other, provenance, source)
        check['fresh_executions'] = [run, other_run]
        print(json.dumps(check))
        return
    data = {'schema': 1, 'pin': '26.3', 'oracle_version': 'java26.3-mouse-input-neutral-v1',
            'scope': 'Actual MouseHandler.onMove and private turnPlayer with explicit elapsed parameter; neutral smoothCamera=false/FIRST_PERSON/non-scoping/inactive tutorial/null vehicle; no OS window or input, timer, handleAccumulatedMovement, grabMouse or releaseMouse invocation',
            'float_encoding': {'state_f32_bits': 'yaw,pitch,previous_yaw,previous_pitch; raw8digit lowercase hex',
                               'mouse_f64_bits': 'xpos,ypos,accumulatedDX,accumulatedDY; raw16digit lowercase hex',
                               'smooth_x_f64_bits_and_smooth_y_f64_bits': 'targetValue,remainingValue,lastAmount; raw16digit lowercase hex',
                               'events': 'move has raw double absolute x/y and relative x/y; turn has explicit raw double elapsed; window_handle is raw16digit lowercase long hex'},
            'receiver_boundary': {'unsafe_fixture_only': 'Constructor-skipped Minecraft, Options, LocalPlayer and Window; reflection initializes only relevant fixture fields; no client singleton or session, level, entity/world constructor or window constructor',
                                  'actual_constructors': 'new MouseHandler(mc), OptionInstance<UnitDouble> sensitivity and createBoolean inversion options, new inactive Tutorial(mc,options)',
                                  'observer': 'Observed LocalPlayer.turn and Tutorial.onMouse delegate actual super bodies; all projected fields, logs and exceptions compared against separate unmodified LocalPlayer/Tutorial receivers for every event',
                                  'unrelated_fields': 'All inherited nonstatic fields of Minecraft/Options/Window/Tutorial/LocalPlayer/MouseHandler compared around production events by raw primitive value or reference identity, except documented rotation and mouse accumulation/position/first-event fields; no entity equality/getId callback; SmoothDouble mutable fields projected separately',
                                  'window_handle': HANDLE,
                                  'neutral_preconditions': 'LocalPlayer.startedUsingItem=false makes actual Player.isScoping short-circuit false; vehicle=null; inactive Tutorial.instance=null; options.smoothCamera=false; cameraType=FIRST_PERSON; rotation method owners asserted Entity; IDE pause flag asserted false'},
            'wrapper_boundary': 'turnPlayer does not itself reset accumulatedDX/DY. handleAccumulatedMovement calls native Blaze3D.getTime, checks GUI/overlay/capture/focus/player state, invokes turnPlayer and resets accumulation in bytecode; not executed here. Explicit set_focus/set_grabbed/clear_accumulation events mutate fixture fields and do not represent OS capture/focus actions or observed wrapper execution.',
            'logging_boundary': 'Production setter logger messages captured per call with test-only targetstderr/followtrue deterministic level|logger|message Log4j layout; standard launcher timestamps/layout not reproduced; startup stderr fingerprinted separately',
            'excluded_branches': 'Smooth-camera and scoping branches, GUI/screens/overlay routing, native timer/input/capture/focus/window session, SDL/GLFW and complete handleAccumulatedMovement lifecycle',
            'provenance': provenance, 'source': source, 'inputs': inputs, 'inputs_sha256': sha(canonical(inputs)),
            'observations': observations, 'observations_sha256': sha(canonical(observations)), 'counts': counts(observations),
            'extract_run': run, 'reproduce': 'python3 tools/reference_mouse_input_probe.py selftest'}
    validate(data, inputs, observations, provenance, source)
    OUTPUT.write_text(json.dumps(data, ensure_ascii=True, sort_keys=True, indent=2) + '\n')
    print(json.dumps(validate(data)))


if __name__ == '__main__':
    main()
