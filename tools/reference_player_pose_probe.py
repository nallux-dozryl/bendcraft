#!/usr/bin/env python3
"""Actual pinned Player.updatePlayerPose, metadata and noCollision observations.

Normal LocalPlayer/ClientLevel constructors and untouched official gameplay
bytes. Context flags are explicitly seeded fixture state, not lifecycle work.
Raw query/read/observer dumps stay in ignored build/player-pose-reference.
"""
from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import time
import zipfile

from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_model_probe import CLIENT, verified_client_classpath
import reference_local_input_probe as LI

RAW = ROOT / 'build/player-pose-reference'
FIXTURE = 'net.minecraft.fixture.PlayerPoseReceiverFixture'
POSES = ['STANDING', 'FALL_FLYING', 'SLEEPING', 'SWIMMING', 'SPIN_ATTACK', 'CROUCHING', 'DYING']
SOURCE = r'''
package net.minecraft.fixture;
import java.io.*;
import java.util.*;
import java.lang.reflect.*;
import com.google.gson.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.data.registries.VanillaRegistries;
import net.minecraft.core.*;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.client.*;
import net.minecraft.client.player.*;
import net.minecraft.client.multiplayer.*;
import net.minecraft.client.multiplayer.chat.ChatAbilities;
import net.minecraft.stats.StatsCounter;
import net.minecraft.world.entity.*;
import net.minecraft.world.entity.decoration.ArmorStand;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.player.Input;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.GameType;
import net.minecraft.world.level.block.*;
import net.minecraft.world.level.block.state.*;
import net.minecraft.world.phys.*;
import net.minecraft.world.phys.shapes.VoxelShape;
import net.minecraft.network.syncher.*;
public class PlayerPoseReceiverFixture {
 static final Gson JSON=new GsonBuilder().serializeNulls().create();
 static final PrintStream OUTPUT=System.out;
 static String bits(float v){return LocalInputReceiverFixture.bits(v);}
 static String bits(double v){return LocalInputReceiverFixture.bits(v);}
 static List<String> vector(Vec3 v){return LocalInputReceiverFixture.vector(v);}
 static List<String> box(AABB b){return List.of(bits(b.minX),bits(b.minY),bits(b.minZ),bits(b.maxX),bits(b.maxY),bits(b.maxZ));}
 static double d(JsonElement v){return Double.longBitsToDouble(Long.parseUnsignedLong(v.getAsString(),16));}
 static Vec3 vec(JsonArray a){return new Vec3(d(a.get(0)),d(a.get(1)),d(a.get(2)));}
 static Object invoke(Object p,Class<?> c,String n,Class<?>[] types,Object...args)throws Exception{Method m=c.getDeclaredMethod(n,types);m.setAccessible(true);return m.invoke(p,args);}
 static Object read(Object p,String n)throws Exception{return LocalInputReceiverFixture.read(p,n);}
 static void seed(Object p,String n,Object v)throws Exception{LocalInputReceiverFixture.seed(p,n,v);}
 // This seeds existing actual DataItems without lifecycle/audio notifications.
 // Actual getters, conditional algorithm, setPose, refresh and world queries
 // remain untouched. It is not evidence for activating these lifecycle modes.
 @SuppressWarnings({"rawtypes","unchecked"}) static void dataSeed(LocalPlayer p,Class<?> owner,String n,Object value)throws Exception{
  Field f=owner.getDeclaredField(n);f.setAccessible(true);EntityDataAccessor a=(EntityDataAccessor)f.get(null);
  Object item=invoke(p.getEntityData(),SynchedEntityData.class,"getItem",new Class<?>[]{EntityDataAccessor.class},a);
  ((SynchedEntityData.DataItem)item).setValue(value);
 }
 static Map<String,Object> context(LocalPlayer p){return Map.of("sleeping",p.isSleeping(),"swimming",p.isSwimming(),"fall_flying",p.isFallFlying(),"auto_spin_attack",p.isAutoSpinAttack(),"shift",p.isShiftKeyDown(),"flying",p.getAbilities().flying,"spectator",p.isSpectator(),"passenger",p.isPassenger());}
 static Map<String,Object> state(LocalPlayer p){try{
  Map<String,Object> m=new TreeMap<>();m.put("pose",p.getPose().name());m.put("position",vector(p.position()));m.put("velocity",vector(p.getDeltaMovement()));m.put("box",box(p.getBoundingBox()));m.put("width_f32_bits",bits(p.getBbWidth()));m.put("height_f32_bits",bits(p.getBbHeight()));m.put("cached_eye_f32_bits",bits((float)read(p,"eyeHeight")));m.put("getter_eye_f32_bits",bits(p.getEyeHeight()));m.put("eye_position",vector(p.getEyePosition()));m.put("body_flags",List.of(p.onGround(),p.horizontalCollision,p.verticalCollision,p.verticalCollisionBelow));m.put("scale_f32_bits",bits(p.getScale()));m.put("baby",p.isBaby());m.put("context",context(p));m.put("cached_crouching",p.isCrouching());return m;
 }catch(Exception e){throw new RuntimeException(e);}}
 static class TraceLevel extends LocalInputReceiverFixture.FixtureLevel {
  final List<Map<String,Object>> events=new ArrayList<>();boolean capture=false;int query=-1,nextQuery=0;
  TraceLevel(ClientPacketListener c,Holder<net.minecraft.world.level.dimension.DimensionType> d){super(c,d);}
  public BlockState getBlockState(BlockPos p){BlockState v=super.getBlockState(p);if(capture&&events!=null)events.add(Map.of("method","block_read","query",query,"position",List.of(p.getX(),p.getY(),p.getZ()),"identifier",BuiltInRegistries.BLOCK.getKey(v.getBlock()).toString()));return v;}
  public boolean noCollision(Entity e,AABB b){int old=query;query=nextQuery++;if(capture)events.add(Map.of("method","noCollision_entry","query",query,"box",box(b)));boolean v=super.noCollision(e,b);if(capture)events.add(Map.of("method","noCollision_exit","query",query,"clear",v));query=old;return v;}
  public boolean noBlockCollision(Entity e,AABB b,boolean suffocating){boolean v=super.noBlockCollision(e,b,suffocating);if(capture)events.add(Map.of("method","no_block_collision","query",query,"clear",v,"only_suffocating",suffocating));return v;}
  public boolean noEntityCollision(Entity e,AABB b){boolean v=super.noEntityCollision(e,b);if(capture)events.add(Map.of("method","no_entity_collision","query",query,"clear",v));return v;}
  public boolean noBorderCollision(Entity e,AABB b){boolean v=super.noBorderCollision(e,b);if(capture)events.add(Map.of("method","no_border_collision","query",query,"clear",v));return v;}
  public List<VoxelShape> getEntityCollisions(Entity e,AABB b){List<VoxelShape> v=super.getEntityCollisions(e,b);if(capture)events.add(Map.of("method","entity_collisions","query",query,"box",box(b),"count",v.size()));return v;}
  public Iterable<VoxelShape> getBlockCollisions(Entity e,AABB b){Iterable<VoxelShape> v=super.getBlockCollisions(e,b);int q=query;return ()->{Iterator<VoxelShape> it=v.iterator();return new Iterator<VoxelShape>(){public boolean hasNext(){return it.hasNext();}public VoxelShape next(){VoxelShape s=it.next();if(capture){List<List<String>> boxes=new ArrayList<>();for(AABB a:s.toAabbs())boxes.add(box(a));events.add(Map.of("method","block_yield","query",q,"boxes",boxes));}return s;}};};}
 }
 static class ObservedPlayer extends LocalPlayer {
  final List<Map<String,Object>> calls=new ArrayList<>();boolean capture=false;
  ObservedPlayer(Minecraft m,ClientLevel l,ClientPacketListener c){super(m,l,c,new StatsCounter(),new ClientRecipeBook(),Input.EMPTY,false,ChatAbilities.NO_RESTRICTIONS,new ItemActivation());}
  void event(String n){if(capture&&calls!=null)calls.add(Map.of("method",n,"state",state(this)));}
  protected boolean canPlayerFitWithinBlocksAndEntitiesWhen(Pose pose){boolean v=super.canPlayerFitWithinBlocksAndEntitiesWhen(pose);if(capture&&calls!=null)calls.add(Map.of("method","fit","pose",pose.name(),"clear",v));return v;}
  public void setPose(Pose p){if(capture&&calls!=null)calls.add(Map.of("method","setPose","requested",p.name()));super.setPose(p);}
  public void refreshDimensions(){event("refresh_entry");super.refreshDimensions();event("refresh_exit");}
  protected void reapplyPosition(){event("reapply_entry");super.reapplyPosition();event("reapply_exit");}
 }
 static class Context {
  final Minecraft mc;final ClientPacketListener connection;final LocalInputReceiverFixture.FixtureLevel level;final LocalPlayer p;
  Context(HolderLookup.Provider lookup,boolean observed)throws Exception{mc=new Minecraft();mc.options=new Options(mc,new File("/dev/null/player-pose-reference"));connection=new ClientPacketListener(LocalInputReceiverFixture.access(lookup));mc.connection=connection;level=observed?new TraceLevel(connection,LocalInputReceiverFixture.dimension(lookup)):new LocalInputReceiverFixture.FixtureLevel(connection,LocalInputReceiverFixture.dimension(lookup));p=observed?new ObservedPlayer(mc,level,connection):new LocalPlayer(mc,level,connection,new StatsCounter(),new ClientRecipeBook(),Input.EMPTY,false,ChatAbilities.NO_RESTRICTIONS,new ItemActivation());mc.player=p;mc.camera=p;p.input=new KeyboardInput(mc.options);}
 }
 static void configure(Context c,JsonObject in)throws Exception{
  LocalPlayer p=c.p;JsonObject flags=in.getAsJsonObject("context");
  byte shared=(byte)((flags.get("swimming").getAsBoolean()?16:0)|(flags.get("fall_flying").getAsBoolean()?128:0));dataSeed(p,Entity.class,"DATA_SHARED_FLAGS_ID",shared);
  dataSeed(p,LivingEntity.class,"DATA_LIVING_ENTITY_FLAGS",(byte)(flags.get("auto_spin_attack").getAsBoolean()?4:0));dataSeed(p,LivingEntity.class,"SLEEPING_POS_ID",flags.get("sleeping").getAsBoolean()?Optional.of(new BlockPos(0,1,0)):Optional.empty());
  p.input.keyPresses=new Input(false,false,false,false,false,flags.get("shift").getAsBoolean(),false);p.getAbilities().flying=flags.get("flying").getAsBoolean();
  PlayerInfo info=c.connection.getPlayerInfo(p.getUUID());invoke(info,PlayerInfo.class,"setGameMode",new Class<?>[]{GameType.class},flags.get("spectator").getAsBoolean()?GameType.SPECTATOR:GameType.SURVIVAL);
  if(flags.get("passenger").getAsBoolean())seed(p,"vehicle",new ArmorStand(c.level,.5,1,.5));
  seed(p,"crouching",in.get("cached_crouching").getAsBoolean());p.getAttribute(Attributes.SCALE).setBaseValue(d(in.get("scale")));p.setPose(Pose.valueOf(in.get("pose").getAsString()));p.refreshDimensions();
  p.setPos(vec(in.getAsJsonArray("position")));p.setDeltaMovement(vec(in.getAsJsonArray("velocity")));p.setOnGround(in.get("grounded").getAsBoolean());p.horizontalCollision=true;p.verticalCollision=false;p.verticalCollisionBelow=true;
  for(JsonElement e:in.getAsJsonArray("world_writes")){JsonObject w=e.getAsJsonObject();JsonArray a=w.getAsJsonArray("position");c.level.blocks.put(new BlockPos(a.get(0).getAsInt(),a.get(1).getAsInt(),a.get(2).getAsInt()),w.get("block").getAsString().equals("stone")?Blocks.STONE.defaultBlockState():Blocks.AIR.defaultBlockState());}
  if(c.level instanceof TraceLevel t){t.events.clear();t.nextQuery=0;t.capture=true;}if(p instanceof ObservedPlayer o){o.calls.clear();o.capture=true;}
 }
 public static void run(String ignored)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();HolderLookup.Provider lookup=VanillaRegistries.createWorldLookup();JsonObject inputs=JsonParser.parseString(new String(Base64.getDecoder().decode(__INPUT_BASE64__),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonObject();
  Context metadata=new Context(lookup,false);for(Pose pose:Pose.values())for(double scale:List.of(1d,.5d,2d)){LocalPlayer p=metadata.p;p.getAttribute(Attributes.SCALE).setBaseValue(scale);p.setPose(pose);p.refreshDimensions();p.setPos(new Vec3(-0d,1d,-0d));EntityDimensions v=p.getDimensions(pose);Map<String,Object> row=new TreeMap<>();row.put("group","metadata");row.put("pose",pose.name());row.put("ordinal",pose.ordinal());row.put("scale_input",bits(scale));row.put("dimensions",Map.of("width",bits(v.width()),"height",bits(v.height()),"eye",bits(v.eyeHeight()),"fixed",v.fixed(),"box",box(v.makeBoundingBox(p.position()))));row.put("state",state(p));OUTPUT.println("PLAYER_POSE_JSON:"+JSON.toJson(row));}
  for(JsonElement e:inputs.getAsJsonArray("cases")){JsonObject in=e.getAsJsonObject();for(boolean observed:List.of(false,true)){Context c=new Context(lookup,observed);configure(c,in.getAsJsonObject("initial"));Map<String,Object> before=state(c.p);invoke(c.p,Player.class,"updatePlayerPose",new Class<?>[]{});Map<String,Object> row=new TreeMap<>();row.put("group","update");row.put("id",in.get("id").getAsString());row.put("observed",observed);row.put("before",before);row.put("after",state(c.p));row.put("calls",observed?((ObservedPlayer)c.p).calls:List.of());row.put("query_events",observed?((TraceLevel)c.level).events:List.of());OUTPUT.println("PLAYER_POSE_JSON:"+JSON.toJson(row));}}
 }
}
'''

def db(x): return struct.pack('>d', x).hex()

def inputs():
    base = {'pose': 'STANDING', 'position': [db(.5), db(1), db(.5)],
            'velocity': [db(-0.0), db(.125), db(-.25)], 'grounded': True,
            'scale': db(1), 'cached_crouching': False, 'world_writes': [],
            'context': dict.fromkeys(['sleeping','swimming','fall_flying','auto_spin_attack','shift','flying','spectator','passenger'], False)}
    cases = []
    def add(name, **changes):
        value=copy.deepcopy(base)
        flags=changes.pop('flags', {})
        value.update(changes);value['context'].update(flags)
        cases.append({'id':name,'initial':value})
    for pose in POSES:
        add('initial:'+pose, pose=pose)
    for flag in ['sleeping','swimming','fall_flying','auto_spin_attack','shift','spectator','passenger']:
        add('flag:'+flag, flags={flag:True})
    for pose,flag in [('SLEEPING','sleeping'),('SWIMMING','swimming'),('FALL_FLYING','fall_flying'),('SPIN_ATTACK','auto_spin_attack'),('CROUCHING','shift')]:
        add('unchanged:'+pose,pose=pose,flags={flag:True})
    add('shift_while_flying', flags={'shift':True,'flying':True})
    add('cached_crouch_without_shift', cached_crouching=True)
    add('new_shift_with_old_standing_cache',flags={'shift':True},cached_crouching=False)
    add('priority_all',flags={'sleeping':True,'swimming':True,'fall_flying':True,'auto_spin_attack':True,'shift':True})
    add('priority_swim',flags={'swimming':True,'fall_flying':True,'auto_spin_attack':True,'shift':True})
    add('priority_glide',flags={'fall_flying':True,'auto_spin_attack':True,'shift':True})
    add('priority_spin',flags={'auto_spin_attack':True,'shift':True})
    for height,y in [(3,1.4),(2,1)]:
        writes=[{'position':[x,height,z],'block':'stone'} for x in range(-1,2) for z in range(-1,2)]
        for flag in [None,'shift','swimming','spectator','passenger']:
            add(f'ceiling:{height}:{flag}',position=[db(.5),db(y),db(.5)],world_writes=writes,flags={} if flag is None else {flag:True})
    blocked=[{'position':[0,1,0],'block':'stone'}]
    for pose in ['STANDING','CROUCHING','SWIMMING']:
        add('initial_swim_blocked:'+pose,pose=pose,world_writes=blocked,flags={'shift':True})
    add('signed_zero',position=[db(-0.0),db(1),db(-0.0)],pose='CROUCHING')
    add('signed_zero_numeric_no_change',position=[db(-0.0),db(-0.0),db(-0.0)],pose='CROUCHING',world_writes=[{'position':[x,0,z],'block':'air'} for x in range(-2,3) for z in range(-2,3)])
    add('deflated_positive_zero',position=[db(.5),db(-1e-7),db(.5)],world_writes=[{'position':[x,0,z],'block':'air'} for x in range(-2,3) for z in range(-2,3)])
    for x in [-30000000.125,30000000.125]:
        add('far:'+str(x),position=[db(x),db(1.125),db(-x)],flags={'shift':True})
    for scale in [.5,2]:add('unadmitted_scale:'+str(scale),scale=db(scale),flags={'shift':True})
    return {'cases':cases}

def private_sources(values):
    sources=dict(LI.receiver_sources({'keyboard':[],'vectors':[],'receivers':[],'ai_step':[]}))
    sources[FIXTURE]=SOURCE.replace('__INPUT_BASE64__',json.dumps(base64.b64encode(canonical(values)).decode()))
    return sources

def run_java(values,label):
    classpath,provenance=verified_client_classpath()
    sources=private_sources(values)
    payload={'sources':sources,'client_jar':str(CLIENT),'mode':'poses'}
    encoded=base64.b64encode(canonical(payload)).decode()
    launcher=LI.RECEIVER_LAUNCHER.replace('loader.loadClass("net.minecraft.fixture.LocalInputReceiverFixture")',f'loader.loadClass("{FIXTURE}")',1)
    launcher=launcher.replace('Base64.getDecoder().decode(args[0])','Base64.getDecoder().decode(String.join("",new String[]{'+','.join(json.dumps(encoded[i:i+6144]) for i in range(0,len(encoded),6144))+'}))',1)
    command=[str(JAVA),'--source','25','--class-path',':'.join(map(str,classpath)),'/dev/stdin']
    RAW.mkdir(parents=True,exist_ok=True)
    (RAW/f'{label}-sources.json').write_bytes(canonical(sources))
    (RAW/f'{label}-launcher.java').write_text(launcher)
    start=time.monotonic()
    p=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
    try:out,err=p.communicate(launcher,timeout=120)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid,signal.SIGKILL);out,err=p.communicate();raise RuntimeError('120s Java cap')
    (RAW/f'{label}-stdout.txt').write_text(out);(RAW/f'{label}-stderr.txt').write_text(err)
    if p.returncode:raise RuntimeError(err[-8000:])
    rows=[json.loads(line[len('PLAYER_POSE_JSON:'):]) for line in out.splitlines() if line.startswith('PLAYER_POSE_JSON:')]
    classes=[json.loads(line[len('LOCAL_INPUT_CLASSES:'):]) for line in out.splitlines() if line.startswith('LOCAL_INPUT_CLASSES:')]
    assert len(classes)==1
    with zipfile.ZipFile(CLIENT) as jar:
        for name,h in classes[0].items():assert hashlib.sha256(jar.read(name.replace('.','/')+'.class')).hexdigest()==h,name
    critical=['net.minecraft.client.player.LocalPlayer','net.minecraft.world.entity.player.Player','net.minecraft.world.entity.Avatar','net.minecraft.world.entity.LivingEntity','net.minecraft.world.entity.Entity','net.minecraft.world.entity.EntityDimensions','net.minecraft.client.multiplayer.ClientLevel','net.minecraft.world.level.BlockCollisions','net.minecraft.network.syncher.SynchedEntityData']
    assert all(name in classes[0] for name in critical)
    raw={'rows':rows,'classes':classes[0],'sources':sources,'provenance':provenance}
    write_json(RAW/f'{label}-raw.json',raw)
    receipt={'seconds':round(time.monotonic()-start,6),'returncode':p.returncode,'command':command,
             'loaded_official_class_count':len(classes[0]),'loaded_official_class_tree_sha256':hashlib.sha256(canonical(classes[0])).hexdigest(),
             'critical_classes':{name:classes[0][name] for name in critical},
             'expanded_sources_sha256':hashlib.sha256(canonical(sources)).hexdigest(),
             'launcher_sha256':hashlib.sha256(launcher.encode()).hexdigest(),
             'raw_artifact':fingerprint(RAW/f'{label}-raw.json'),'stdout':fingerprint(RAW/f'{label}-stdout.txt'),
             'stderr':fingerprint(RAW/f'{label}-stderr.txt')}
    return rows,receipt

def collect(values,rows):
    metadata=[r for r in rows if r['group']=='metadata']
    cases=[]
    for source in values['cases']:
        plain=next(r for r in rows if r.get('id')==source['id'] and not r['observed'])
        observed=next(r for r in rows if r.get('id')==source['id'] and r['observed'])
        for key in ['before','after']:assert plain[key]==observed[key],(source['id'],key)
        assert observed['before']['context']==source['initial']['context']
        fits=[e for e in observed['calls'] if e['method']=='fit']
        queries=[]
        for i,fit in enumerate(fits):
            entries=[e for e in observed['query_events'] if e['method']=='noCollision_entry' and e['query']==i]
            exits=[e for e in observed['query_events'] if e['method']=='noCollision_exit' and e['query']==i]
            assert len(entries)==len(exits)==1 and fit['clear']==exits[0]['clear']
            stages={e['method']:e['clear'] for e in observed['query_events'] if e['query']==i and e['method'] in ['no_block_collision','no_entity_collision','no_border_collision']}
            assert 'no_block_collision' in stages
            if stages['no_block_collision']:assert 'no_entity_collision' in stages
            if stages.get('no_entity_collision'):assert 'no_border_collision' in stages
            queries.append({'pose':fit['pose'],'box':entries[0]['box'],'clear':fit['clear'],'actual_stages':stages})
        refreshes=sum(e['method']=='refresh_entry' for e in observed['calls'])
        set_poses=[e['requested'] for e in observed['calls'] if e['method']=='setPose']
        assert refreshes==int(observed['before']['pose']!=observed['after']['pose'])
        for key in ['position','velocity','body_flags']:assert observed['before'][key]==observed['after'][key],(source['id'],key)
        cases.append({'id':source['id'],'initial':source['initial'],'before':plain['before'],'expected':plain['after'],'queries':queries,'set_pose_requests':set_poses,'refresh_count':refreshes,
                      'admitted':source['initial']['scale']==db(1)})
    return {'metadata':metadata,'cases':cases}

def extract():
    before={str(p.relative_to(ROOT)):fingerprint(p) for p in [Path(__file__),ROOT/'tools/reference_local_input_probe.py',CLIENT] if p.is_relative_to(ROOT)}
    jar_before=fingerprint(CLIENT);values=inputs()
    first,a=run_java(values,'first');second,b=run_java(values,'second')
    assert first==second,'Actual observation rerun changed'
    corpus=collect(values,first)
    data={'version':'26.3','scope':'Actual adult LocalPlayer conditional pose update and all enum metadata; lifecycle flags are pre-seeded fixture context. Bend admits seven unit-scale coherent poses only.',
          'inputs_sha256':hashlib.sha256(canonical(values)).hexdigest(),'observations_sha256':hashlib.sha256(canonical(corpus)).hexdigest(),**corpus}
    write_json(ROOT/'reference/player_pose.json',data)
    assert jar_before==fingerprint(CLIENT)
    for name,pin in before.items():assert fingerprint(ROOT/name)==pin,name
    counts={'metadata_rows':len(corpus['metadata']),'actual_update_cases':len(corpus['cases']),'admitted_cases':sum(c['admitted'] for c in corpus['cases']),
            'actual_fit_queries':sum(len(c['queries']) for c in corpus['cases']),'refreshes':sum(c['refresh_count'] for c in corpus['cases']),
            'plain_observer_compared_updates':2*len(corpus['cases'])}
    evidence={'status':'actual Java observed; Bend native/kernel not run','producer':fingerprint(Path(__file__)),'source_sha256':hashlib.sha256(SOURCE.encode()).hexdigest(),
              'inherited_launcher_sha256':hashlib.sha256(LI.RECEIVER_LAUNCHER.encode()).hexdigest(),
              'fixture_boundary':'Normal constructors; four frozen external service mocks; actual official update/getters/noCollision/block iterator/setPose/dimension refresh. Shared/living/sleeping DataItem values and passenger relationship are preseeded without lifecycle notifications. No lifecycle activation, actor population, scale lifecycle or full tick claim.',
              'world_boundary':'Actual ClientLevel default entity store and border, declared finite 25-stone floor with explicit writes; getBlockState/fluid/chunk lookup supplied fixture data. Actual noCollision returned booleans and short-circuited lazy block iterator are separately recorded in ignored raw events.',
              'counts':counts,'reference':fingerprint(ROOT/'reference/player_pose.json'),'input_sha256':data['inputs_sha256'],'observations_sha256':data['observations_sha256'],
              'fresh_rerun_exact':True,'plain_observer_final_exact':True,'jar_before':jar_before,'jar_after':fingerprint(CLIENT),'runs':[a,b],'dependency_pins':before}
    write_json(ROOT/'evidence/player-pose-reference.json',evidence)
    print(json.dumps({'status':evidence['status'],'counts':counts,'evidence':fingerprint(ROOT/'evidence/player-pose-reference.json')},indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--extract',action='store_true',required=True);parser.parse_args();extract()
