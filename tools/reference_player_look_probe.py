#!/usr/bin/env python3
"""Exact actual pinned Entity.turn observations without a client or window.

Fixture-only Unsafe allocation skips ArmorStand instance construction. The
production turn and production superclass getter/setter bodies execute directly;
an observed subclass is compared to an unmodified ArmorStand for every call.
"""
from __future__ import annotations
import argparse
import collections
import hashlib
import json
import math
import pathlib
import random
import struct
import subprocess
import zipfile

from reference_inventory import ROOT, JAVA, fingerprint
from reference_model_probe import CLIENT, verified_client_classpath

OUTPUT = ROOT / 'reference/player_look.json'
CACHE = ROOT / 'reference/cache/player-look-probe'
LOG_CONFIG = '''<?xml version="1.0" encoding="UTF-8"?>
<Configuration status="ERROR"><Appenders><Console name="ProbeConsole" target="SYSTEM_ERR" follow="true"><PatternLayout pattern="%level|%logger|%message%n"/></Console></Appenders><Loggers><Root level="warn"><AppenderRef ref="ProbeConsole"/></Root></Loggers></Configuration>
'''


def canonical(v):
    return json.dumps(v, ensure_ascii=True, sort_keys=True, separators=(',', ':')).encode('ascii')


def sha(b):
    return hashlib.sha256(b).hexdigest()


def b32(v):
    return f'{struct.unpack(">I", struct.pack(">f", v))[0]:08x}'


def b64(v):
    return f'{struct.unpack(">Q", struct.pack(">d", v))[0]:016x}'


def from32(bits):
    return struct.unpack('>f', struct.pack('>I', bits))[0]


def from64(bits):
    return struct.unpack('>d', struct.pack('>Q', bits))[0]


def fixtures():
    cases = []
    def add(name, state, dx, dy, category, chain=()):
        cases.append({'id': name, 'category': category, 'input': {'state_f32_bits': list(state),
                      'dx_f64_bits': dx, 'dy_f64_bits': dy}, 'chain': [{'dx_f64_bits': a, 'dy_f64_bits': b} for a, b in chain]})
    zero = [b32(0.0)] * 4
    for name, state, dx, dy in [
        ('small_turn', list(map(b32, (10, 20, 30, 40))), b64(1), b64(2)),
        ('zero_turn', zero, b64(0), b64(0)),
        ('negative_zero_turn', ['80000000'] * 4, '8000000000000000', '8000000000000000'),
        ('positive_zero_replaces_negative', ['80000000'] * 4, b64(0), b64(0)),
        ('pitch_wrap_positive', list(map(b32, (0, 80, 0, 80))), b64(0), b64(2000)),
        ('pitch_wrap_negative', list(map(b32, (0, -80, 0, -80))), b64(0), b64(-2000)),
        ('huge_dx', list(map(b32, (12, 34, 56, 78))), '7fefffffffffffff', b64(0)),
        ('huge_dy', list(map(b32, (12, 34, 56, 78))), b64(0), '7fefffffffffffff'),
        ('negative_huge_dxdy', list(map(b32, (12, 34, 56, 78))), 'ffefffffffffffff', 'ffefffffffffffff'),
        ('finite_yaw_sum_overflow', ['7f7fffff', b32(0), '7f7fffff', b32(0)], b64(from32(0x7f7fffff)), b64(0)),
    ]:
        add(name, state, dx, dy, 'initial-semantics')
    for pitch in (365, -365, 540, -540, 720, -720):
        add(f'zero_delta_pitch_remainder_{pitch}', list(map(b32, (17, pitch, -29, pitch))),
            b64(0), b64(0), 'current-setter-remainder-versus-previous-clamp')
    for mask in range(64):
        state = ['80000000' if mask & (1 << i) else '00000000' for i in range(4)]
        add(f'signed_zero_{mask}', state, '8000000000000000' if mask & 16 else b64(0),
            '8000000000000000' if mask & 32 else b64(0), 'signed-zero')
    for pitch_bits in (0, 0x80000000, 1, 0x80000001, 0x42b3ffff, 0x42b40000, 0x42b40001,
                       0xc2b3ffff, 0xc2b40000, 0xc2b40001, 0x43b40000, 0xc3b40000,
                       0x7f7fffff, 0xff7fffff):
        for dy in (0, 1, -1, 600, -600, 2400, -2400):
            state = [b32(17.25), f'{pitch_bits:08x}', b32(-29.5), f'{pitch_bits:08x}']
            add(f'pitch_state_{pitch_bits:08x}_{dy}', state, b64(0), b64(dy), 'raw-pitch-state-normalization')
    # Exact d2f midpoint and neighboring double bit patterns; then actual .15f
    # multiplication/setters are invoked by Entity.turn, not computed here.
    narrowed = (0, 1, 2, 3, 0x7fffff, 0x800000, 0x3f000000, 0x3f7fffff, 0x3f800000,
                0x3fffffff, 0x447a0000, 0x7f7ffffe)
    deltas = set()
    for raw in narrowed:
        a, b = from32(raw), from32(raw + 1)
        midpoint = (float(a) + float(b)) / 2
        center = int(b64(midpoint), 16)
        for bits in (center - 1, center, center + 1):
            if bits >= 0:
                deltas.add(bits); deltas.add(bits | (1 << 63))
    # Largest finite float vs infinity RN midpoint, float multiplier underflow,
    # .15f clamp and remainder transitions, extreme finite-double inputs.
    for value in (90 / float(from32(0x3e19999a)), 180 / float(from32(0x3e19999a)),
                  270 / float(from32(0x3e19999a)), 360 / float(from32(0x3e19999a)),
                  math.ldexp(1.0, -150), math.ldexp(1.0, -149), math.ldexp(1.0, -148),
                  math.ldexp(1.0, 128) - math.ldexp(1.0, 103)):
        bits = int(b64(value), 16)
        for nearby in range(bits - 2, bits + 3):
            deltas.add(nearby); deltas.add(nearby | (1 << 63))
    deltas.update((0, 1 << 63, 1, (1 << 63) | 1, 0x0010000000000000,
                   0x7fefffffffffffff, 0xffefffffffffffff))
    for i, bits in enumerate(sorted(deltas)):
        for axis in ('x', 'y'):
            add(f'delta_boundary_{axis}_{i}', list(map(b32, (0, 89.99999, 0, -89.99999))),
                f'{bits:016x}' if axis == 'x' else b64(0), f'{bits:016x}' if axis == 'y' else b64(0), 'narrow-multiply-clamp-boundaries')
    # Current and historical yaw sums can overflow independently.
    for yaw, previous in ((0x7f7fffff, 0), (0, 0x7f7fffff), (0x7f7fffff, 0xff7fffff),
                          (0xff7fffff, 0x7f7fffff), (0x4b800000, 0xcb800000)):
        for sign in (1, -1):
            add(f'yaw_sum_{yaw:08x}_{previous:08x}_{sign}', [f'{yaw:08x}', b32(0), f'{previous:08x}', b32(0)],
                b64(sign * from32(0x7f7fffff)), b64(0), 'independent-current-past-overflow')
    rng = random.Random(0x26_03_4c4f)
    for i in range(1500):
        def finite32():
            while True:
                raw = rng.getrandbits(32)
                if raw & 0x7f800000 != 0x7f800000:
                    return f'{raw:08x}'
        def finite64():
            while True:
                raw = rng.getrandbits(64)
                if raw & 0x7ff0000000000000 != 0x7ff0000000000000:
                    return f'{raw:016x}'
        state = [finite32(), b32(rng.uniform(-90, 90)), finite32(), b32(rng.uniform(-90, 90))]
        add(f'finite_random_{i}', state, finite64(), finite64(), 'seeded-raw-finite')
    # Raw finite pitch states are legal turn preconditions even when their
    # starting magnitude exceeds 90. Exercise setter remainder across exponents
    # without computing an expected quotient or result in Python.
    for exponent in range(10, 128):
        for fraction in (0, 1, 0x7fffff):
            for sign in (0, 1):
                raw = ((exponent + 127) << 23) | fraction | (sign << 31)
                add(f'finite_pitch_exponent_{exponent}_{fraction}_{sign}',
                    [b32(17), f'{raw:08x}', b32(-29), f'{raw:08x}'], b64(0), b64(0),
                    'finite-pitch-remainder-exponents')
    for i in range(512):
        state = [finite32(), finite32(), finite32(), finite32()]
        add(f'finite_pitch_random_{i}', state, b64(rng.choice((-2000, -600, -1, 0, 1, 600, 2000))),
            b64(rng.choice((-2000, -600, -1, 0, 1, 600, 2000))), 'seeded-arbitrary-finite-pitch')
    for i in range(24):
        chain = [(b64(rng.choice((-2000, -600, -1, -0.0, 0, 1, 600, 2000))),
                  b64(rng.choice((-2000, -600, -1, -0.0, 0, 1, 600, 2000)))) for _ in range(15)]
        add(f'chained_turns_{i}', [b32(0), b32(0), b32(123), b32(-45)], b64(1), b64(2), 'chained-turns', chain)
    # These measure the production method's behavior outside the finite-input
    # projection; they are not implied admission for a later Bend API.
    for bits in (0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000000123, 0x7ff0000000000001):
        for axis in ('x', 'y'):
            add(f'nonfinite_delta_{axis}_{bits:016x}', list(map(b32, (12, 34, 56, 78))),
                f'{bits:016x}' if axis == 'x' else b64(0), f'{bits:016x}' if axis == 'y' else b64(0), 'outside-finite-admission')
    assert len({c['id'] for c in cases}) == len(cases)
    return cases


JAVA_SOURCE = r'''
import com.google.gson.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.decoration.ArmorStand;
import net.minecraft.world.level.Level;
import java.io.*;
import java.nio.file.*;
import java.nio.charset.*;
import java.lang.reflect.*;
import java.util.*;
import sun.misc.Unsafe;

class ReferencePlayerLookProbe {
 static final Gson G=new GsonBuilder().serializeNulls().disableHtmlEscaping().create();
 static Unsafe U;static Field Y,X,YO,XO,V;static List<Field> OTHER;
 static String f(float v){return String.format("%08x",Float.floatToRawIntBits(v));}
 static float f(JsonElement v){return Float.intBitsToFloat((int)Long.parseUnsignedLong(v.getAsString(),16));}
 static double d(JsonElement v){return Double.longBitsToDouble(Long.parseUnsignedLong(v.getAsString(),16));}
 static Field field(String name)throws Exception{var f=Entity.class.getDeclaredField(name);f.setAccessible(true);return f;}
 static JsonArray state(Entity e){try{var a=new JsonArray();for(var field:List.of(Y,X,YO,XO))a.add(f(field.getFloat(e)));return a;}catch(Exception ex){throw new AssertionError(ex);}}
 static class ObservedStand extends ArmorStand {
  ArrayList<JsonObject> trace;
  ObservedStand(){super((Level)null,0,0,0);throw new AssertionError("constructor must not run");}
  void get(String name,float value){var j=new JsonObject();j.addProperty("method",name);j.addProperty("returned_f32_bits",f(value));trace.add(j);}
  void set(String name,float value,Runnable body){var j=new JsonObject();j.addProperty("method",name);j.addProperty("argument_f32_bits",f(value));j.add("before",state(this));body.run();j.add("after",state(this));trace.add(j);}
  @Override public float getXRot(){float v=super.getXRot();get("getXRot",v);return v;}
  @Override public float getYRot(){float v=super.getYRot();get("getYRot",v);return v;}
  @Override public void setXRot(float v){set("setXRot",v,()->super.setXRot(v));}
  @Override public void setYRot(float v){set("setYRot",v,()->super.setYRot(v));}
 }
 static Entity fresh(JsonArray initial,boolean observed)throws Exception{
  var e=(Entity)U.allocateInstance(observed?ObservedStand.class:ArmorStand.class);
  if(observed)((ObservedStand)e).trace=new ArrayList<>();
  int i=0;for(var field:List.of(Y,X,YO,XO))field.setFloat(e,f(initial.get(i++)));
  V.set(e,null);if(e.getVehicle()!=null)throw new AssertionError("vehicle unexpectedly present");
  if(!state(e).equals(initial))throw new AssertionError("initial raw rotations changed");return e;
 }
 static Map<Field,Object> unrelated(Entity e)throws Exception{var m=new HashMap<Field,Object>();for(var field:OTHER)m.put(field,field.get(e));return m;}
 static JsonObject invoke(Entity e,JsonObject delta)throws Exception{
  var before=unrelated(e);var out=new ByteArrayOutputStream();var err=new ByteArrayOutputStream();var savedOut=System.out;var savedErr=System.err;Throwable failure=null;
  if(e instanceof ObservedStand o)o.trace.clear();
  try{System.setOut(new PrintStream(out,true,StandardCharsets.UTF_8));System.setErr(new PrintStream(err,true,StandardCharsets.UTF_8));e.turn(d(delta.get("dx_f64_bits")),d(delta.get("dy_f64_bits")));}catch(Throwable t){failure=t;}finally{System.setOut(savedOut);System.setErr(savedErr);}
  if(!before.equals(unrelated(e)))throw new AssertionError("turn changed unrelated instance fields");
  var j=new JsonObject();j.add("state_f32_bits",state(e));j.addProperty("exception_class",failure==null?null:failure.getClass().getName());j.addProperty("exception_message",failure==null?null:failure.getMessage());j.addProperty("stdout",out.toString(StandardCharsets.UTF_8));j.addProperty("stderr",err.toString(StandardCharsets.UTF_8));j.addProperty("unrelated_fields_unchanged",true);
  if(e instanceof ObservedStand o)j.add("trace",G.toJsonTree(o.trace));return j;
 }
 public static void main(String[] args)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();if(SharedConstants.IS_RUNNING_IN_IDE)throw new AssertionError("IDE pause mode must be false");
  var unsafe=Unsafe.class.getDeclaredField("theUnsafe");unsafe.setAccessible(true);U=(Unsafe)unsafe.get(null);
  Y=field("yRot");X=field("xRot");YO=field("yRotO");XO=field("xRotO");V=field("vehicle");OTHER=new ArrayList<>();
  for(Class<?> c=ArmorStand.class;c!=null&&c!=Object.class;c=c.getSuperclass())for(var field:c.getDeclaredFields())if(!Modifier.isStatic(field.getModifiers())&&!List.of(Y,X,YO,XO).contains(field)){field.setAccessible(true);OTHER.add(field);}
  var owners=new JsonObject();for(var name:List.of("turn","setXRot","setYRot","getXRot","getYRot","getVehicle")){Class<?>[] params=name.equals("turn")?new Class<?>[]{double.class,double.class}:name.startsWith("set")?new Class<?>[]{float.class}:new Class<?>[]{};var method=ArmorStand.class.getMethod(name,params);owners.addProperty(name,method.getDeclaringClass().getName());if(method.getDeclaringClass()!=Entity.class)throw new AssertionError("unexpected method override "+name);}
  var warm=fresh(JsonParser.parseString("[\"00000000\",\"00000000\",\"00000000\",\"00000000\"]").getAsJsonArray(),false);warm.turn(0,0);
  var in=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonArray();var result=new JsonObject();result.add("production_method_owners",owners);result.addProperty("unrelated_instance_fields_checked",OTHER.size());result.addProperty("is_running_in_ide",SharedConstants.IS_RUNNING_IN_IDE);var cases=new JsonArray();
  for(var fixture:in){var c=fixture.getAsJsonObject();var input=c.getAsJsonObject("input");var plain=fresh(input.getAsJsonArray("state_f32_bits"),false);var observed=fresh(input.getAsJsonArray("state_f32_bits"),true);var turns=new ArrayList<JsonObject>();turns.add(input);for(var delta:c.getAsJsonArray("chain"))turns.add(delta.getAsJsonObject());var steps=new JsonArray();
   for(var delta:turns){var a=invoke(plain,delta);var b=invoke(observed,delta);var trace=b.remove("trace");if(!a.equals(b))throw new AssertionError("observer changed production outcome "+c.get("id"));a.add("trace",trace);a.addProperty("unmodified_receiver_match",true);steps.add(a);}
   var o=new JsonObject();o.addProperty("id",c.get("id").getAsString());o.add("steps",steps);cases.add(o);
  }
  result.add("cases",cases);Files.writeString(Path.of(args[1]),G.toJson(result));
 }
}
'''


def source_records(cp):
    names = ['net.minecraft.world.entity.Entity', 'net.minecraft.world.entity.LivingEntity',
             'net.minecraft.world.entity.decoration.ArmorStand', 'net.minecraft.util.Mth', 'net.minecraft.util.Util',
             'net.minecraft.SharedConstants', 'net.minecraft.server.Bootstrap', 'net.minecraft.client.MouseHandler',
             'net.minecraft.client.player.LocalPlayer']
    with zipfile.ZipFile(CLIENT) as z:
        records = []
        for name in names:
            b = z.read(name.replace('.', '/') + '.class')
            records.append({'class': name, 'bytes': len(b), 'sha256': sha(b)})
    run = subprocess.run([str(JAVA.with_name('javap')), '-p', '-c', '-classpath', ':'.join(map(str, cp)), *names],
                         capture_output=True, text=True, check=True)
    path = CACHE / 'production-javap.txt';path.write_text(run.stdout)
    return {'classes': records, 'javap': fingerprint(path), 'java_harness_sha256': sha(JAVA_SOURCE.encode()),
            'logging_config_sha256': sha(LOG_CONFIG.encode()),
            'authority': 'Actual pinned production Entity.turn and setter calls; bytecode establishes receiver wiring and logging/precondition boundary'}


def execute(inputs, cp, tag):
    CACHE.mkdir(parents=True, exist_ok=True)
    src, config = CACHE / 'ReferencePlayerLookProbe.java', CACHE / 'log4j2-probe.xml'
    src.write_text(JAVA_SOURCE);config.write_text(LOG_CONFIG)
    ip, op = CACHE / (tag + '-inputs.json'), CACHE / (tag + '-observations.json')
    ip.write_bytes(canonical(inputs))
    cmd = [str(JAVA), '-Dlog4j.configurationFile=' + str(config), '-cp', ':'.join(map(str, cp)), str(src), str(ip), str(op)]
    run = subprocess.run(cmd, cwd=CACHE, capture_output=True, text=True, timeout=180)
    (CACHE / (tag + '-stdout.log')).write_text(run.stdout);(CACHE / (tag + '-stderr.log')).write_text(run.stderr)
    if run.returncode:
        raise RuntimeError('Java look probe failed: ' + run.stderr[-6000:] + run.stdout[-6000:])
    observations = json.loads(op.read_text())
    return observations, {'exit_code': run.returncode, 'raw_observation_sha256': sha(op.read_bytes()),
                          'stdout': fingerprint(CACHE / (tag + '-stdout.log')), 'stderr': fingerprint(CACHE / (tag + '-stderr.log'))}


def counts(obs):
    steps = [s for c in obs['cases'] for s in c['steps']]
    return {'cases': len(obs['cases']), 'turn_calls_per_receiver': len(steps), 'actual_production_turn_calls': 2 * len(steps),
            'exception_steps': sum(s['exception_class'] is not None for s in steps),
            'logged_steps': sum(bool(s['stdout'] or s['stderr']) for s in steps),
            'unrelated_instance_fields_unchanged_steps': sum(s['unrelated_fields_unchanged'] for s in steps),
            'unmodified_receiver_matches': sum(s['unmodified_receiver_match'] for s in steps)}


def validate(data, inputs=None, observations=None, provenance=None, source=None):
    if data.get('schema') != 1 or data.get('pin') != '26.3':
        raise ValueError('look reference schema/pin mismatch')
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
    for c, o in zip(data['inputs'], data['observations']['cases'], strict=True):
        if len(o['steps']) != 1 + len(c['chain']):
            raise ValueError('chain observation mismatch')
        for s in o['steps']:
            if len(s['state_f32_bits']) != 4 or not all(len(b) == 8 and all(ch in '0123456789abcdef' for ch in b) for b in s['state_f32_bits']):
                raise ValueError('invalid raw F32 state encoding')
            if not s['unrelated_fields_unchanged'] or not s['unmodified_receiver_match']:
                raise ValueError('receiver/observer boundary violated')
    return {'status': 'pass', 'counts': data['counts'], 'observations_sha256': data['observations_sha256']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['extract', 'selftest', 'validate', 'early'], nargs='?', default='extract')
    args = parser.parse_args()
    if args.action == 'validate':
        print(json.dumps(validate(json.loads(OUTPUT.read_text()))));return
    cp, provenance = verified_client_classpath();inputs = fixtures()
    if args.action == 'early':
        obs, run = execute(inputs[:10], cp, 'early')
        print(json.dumps(obs, sort_keys=True));return
    obs, run = execute(inputs, cp, args.action + '-a');source = source_records(cp)
    if args.action == 'selftest':
        data = json.loads(OUTPUT.read_text());check = validate(data, inputs, obs, provenance, source)
        other, other_run = execute(inputs, cp, 'selftest-b');validate(data, inputs, other, provenance, source)
        check['fresh_executions'] = [run, other_run];print(json.dumps(check));return
    data = {'schema': 1, 'pin': '26.3', 'oracle_version': 'java26.3-entity-turn-v1',
            'scope': 'Direct production Entity.turn(double,double), getters/setters and Mth/Math clamp, null vehicle, instance construction skipped; no client, GLFW, window, cursor, mouse handler, rendering or gameplay tick',
            'float_encoding': 'state_f32_bits order yaw,pitch,previous_yaw,previous_pitch; lowercase8digit Float.floatToRawIntBits; input deltas lowercase16digit Double.doubleToRawLongBits; no decimal tolerance',
            'receiver_boundary': {'actual_receiver': 'Unsafe.allocateInstance(ArmorStand.class), production method/getter/setter owners asserted Entity',
                                  'observer': 'Unsafe.allocateInstance(ObservedStand.class), inherited production Entity.turn, getter/setter observers delegate super and are compared bit-for-bit/log-for-log with unmodified ArmorStand after each call',
                                  'initialization': 'SharedConstants.tryDetectVersion and Bootstrap.bootStrap only; no entity constructor, level, client or window; four raw rotation fields initialized by reflection, vehicle null',
                                  'unrelated_fields': 'Every inherited nonstatic instance field outside four rotations compared before/after; observer trace fields excluded',
                                  'IDE': 'actual SharedConstants.IS_RUNNING_IN_IDE asserted false, so setter logging cannot invoke IDE pause hook'},
            'logging_boundary': 'Actual production Util logger writes are captured as stdout/stderr for every call; test-only Log4j console targetstderr/followtrue and deterministic level|logger|message formatting preserve message/count/order while avoiding timestamps; standard release logger layout is not reproduced',
            'mouse_boundary': 'No static neutral sensitivity helper exists in pinned MouseHandler; private turnPlayer dereferences Minecraft.options/player/tutorial plus SmoothDouble/camera/scoping state. Bytecode wiring recorded only; no MouseHandler scaling behavior is claimed here.',
            'provenance': provenance, 'source': source, 'inputs': inputs, 'inputs_sha256': sha(canonical(inputs)),
            'observations': obs, 'observations_sha256': sha(canonical(obs)), 'counts': counts(obs), 'extract_run': run,
            'reproduce': 'python3 tools/reference_player_look_probe.py selftest'}
    validate(data, inputs, obs, provenance, source)
    OUTPUT.write_text(json.dumps(data, ensure_ascii=True, sort_keys=True, indent=2) + '\n')
    print(json.dumps(validate(data)))


if __name__ == '__main__':
    main()
