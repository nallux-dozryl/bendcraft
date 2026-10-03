#!/usr/bin/env python3
"""Pinned direct LocalPlayer minor-collision and Player sneak-edge oracle.

Frozen local-input receivers/services are reused without modifications. Actual
production methods determine decisive results. Supplemental numeric metrics
are explicitly independent instrumentation, not observed production locals.
"""
from __future__ import annotations
import argparse, base64, copy, hashlib, json, math, random, re, struct, subprocess, time, zipfile
from collections import Counter
from pathlib import Path
from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_model_probe import CLIENT, verified_client_classpath
import reference_local_input_probe as LI

OUTPUT=ROOT/'reference/local_collision.json'
SEED=26310405
FROZEN_REFERENCE_SEMANTICS='3a9a8ad9830653089c938baa104f31fb72c045933bd29e25f288a437695b69d8'
GROUPS=('acos','minor','backoff')

def save(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(canonical(value)+b'\n')

def sha(value):
    return hashlib.sha256(canonical(value)).hexdigest()

def projected_observations(rows):
    grouped={}
    for row in rows:grouped.setdefault((row['group'],row['id']),[]).append(row)
    counts={g:sum(group==g for group,_ in grouped) for g in GROUPS}
    counts['no_collision_queries']=sum(sum(e['method']=='noCollision_entry' for e in row.get('query_events',[])) for row in rows if row.get('observed') and row['group']=='backoff')
    pairs=0;complete=True;equal=True;unchanged=True
    for (group,_),items in grouped.items():
        if group=='acos':continue
        plain=[r for r in items if not r['observed']];observed=[r for r in items if r['observed']]
        if len(plain)!=1 or len(observed)!=1:complete=False;continue
        pairs+=1
        keys=['before','after','expected']+(['independent_numeric_instrumentation'] if group=='minor' else [])
        equal=equal and all(plain[0][k]==observed[0][k] for k in keys)
        unchanged=unchanged and plain[0]['before']==plain[0]['after'] and observed[0]['before']==observed[0]['after']
    return {'counts':counts,'receiver_pair_count':pairs,'complete_receiver_pairs':complete,
            'plain_observer_projected_parity':'passed' if equal and complete else 'incomplete_or_failed',
            'projected_helper_state_unchanged':'passed' if unchanged and complete else 'incomplete_or_failed',
            'scope':'Metadata checks over preserved actual observations; no new gameplay values generated'}

def compact_report(path,evidence,original_bytes=None):
    """Preserve complete execution evidence locally; publish sealed summaries.

    Historical evidence retains its original execution metadata. Fresh Java
    runs carry their actual producer fingerprint and complete raw class tree.
    The in-memory evidence passed to collect() remains unchanged.
    """
    assert evidence['observations_sha256']==sha(evidence['observations'])
    raw_path=ROOT/'build/local-collision-reference'/f'{path.stem}.full.json'
    raw_path.parent.mkdir(parents=True,exist_ok=True)
    if original_bytes is not None:
        assert json.loads(original_bytes)==evidence
        raw_path.write_bytes(original_bytes)
    else:save(raw_path,evidence)
    excluded={'observations','source','provenance','substituted_external_types','execution','raw_execution'}
    report={k:v for k,v in evidence.items() if k not in excluded}
    report['evidence_format']='local-collision-summary-v1'
    report['storage_writer']=fingerprint(Path(__file__))
    report['observation_count']=len(evidence['observations'])
    report['observation_groups']=dict(sorted(Counter(row['group'] for row in evidence['observations']).items()))
    report['projected_observations']=projected_observations(evidence['observations'])
    inventory=evidence['source']
    report['source_inventory']={
        'class_count':len(inventory),'method_count':sum(len(c['methods']) for c in inventory.values()),
        'canonical_sha256':sha(inventory),
        'class_bytes_sha256':{n:c['class_sha256'] for n,c in inventory.items()},
        'method_inventories_sha256':{n:sha(c['methods']) for n,c in inventory.items()},
    }
    provenance=evidence['provenance']
    report['provenance']={k:v for k,v in provenance.items() if k not in ('libraries','missing_other_platform_natives')}
    report['provenance_sha256']=sha(provenance)
    for key in ('libraries','missing_other_platform_natives'):
        report['provenance'][key+'_count']=len(provenance[key])
        report['provenance'][key+'_sha256']=sha(provenance[key])
    report['substituted_external_types']={n:{'source_sha256':v['source_sha256']} for n,v in evidence['substituted_external_types'].items()}
    execution=dict(evidence['execution']);command=list(execution['command'])
    execution['command_sha256']=sha(command)
    if '--class-path' in command:
        i=command.index('--class-path')+1
        execution['classpath_entry_count']=len(command[i].split(':'))
        execution['classpath_sha256']=hashlib.sha256(command[i].encode()).hexdigest()
        command[i]='<verified pinned classpath; complete command in raw_report>'
    execution['command']=command
    if execution['returncode']==0:
        execution.pop('stderr_tail',None);execution.pop('failure_stdout',None)
    report['execution']=execution
    report['raw_report']={'path':str(raw_path.relative_to(ROOT)),**fingerprint(raw_path)}
    report['raw_execution_available']='raw_execution' in evidence
    report['storage_scope']='Summary only; exact observations, full original provenance/inventory and available stdout/stderr/official class tree are retained in ignored raw_report. Reference values remain byte-identical in reference/local_collision.json.'
    save(path,report)
    verify_compact_report(path)
    return report

def verify_compact_report(path):
    report=json.loads(path.read_text())
    assert report['evidence_format']=='local-collision-summary-v1'
    raw_path=ROOT/report['raw_report']['path']
    assert fingerprint(raw_path)=={k:v for k,v in report['raw_report'].items() if k!='path'},'Raw report changed'
    full=json.loads(raw_path.read_text());rows=full['observations']
    assert report['observations_sha256']==full['observations_sha256']==sha(rows)
    assert report['observation_count']==len(rows)
    assert report['observation_groups']==dict(sorted(Counter(row['group'] for row in rows).items()))
    assert report['projected_observations']==projected_observations(rows)
    inventory=full['source']
    assert report['source_inventory']=={
        'class_count':len(inventory),'method_count':sum(len(c['methods']) for c in inventory.values()),
        'canonical_sha256':sha(inventory),'class_bytes_sha256':{n:c['class_sha256'] for n,c in inventory.items()},
        'method_inventories_sha256':{n:sha(c['methods']) for n,c in inventory.items()},
    }
    assert report['provenance_sha256']==sha(full['provenance'])
    for key in ('libraries','missing_other_platform_natives'):
        assert report['provenance'][key+'_count']==len(full['provenance'][key])
        assert report['provenance'][key+'_sha256']==sha(full['provenance'][key])
    assert report['execution']['command_sha256']==sha(full['execution']['command'])
    for key in ('status','source_sha256','expanded_source_sha256','launcher_sha256','runtime_classes','loaded_official_classes','loaded_official_class_count','loaded_official_class_tree_sha256','independent_actual_observation_parity','reference_compared','producer_at_execution'):
        if key in full:assert report[key]==full[key],key
    raw=full.get('raw_execution',{})
    if raw.get('loaded_official_classes') is not None:
        assert len(raw['loaded_official_classes'])==report['loaded_official_class_count']
        assert sha(raw['loaded_official_classes'])==report['loaded_official_class_tree_sha256']
    for stream in ('stdout','stderr'):
        if stream in raw:assert hashlib.sha256(raw[stream].encode()).hexdigest()==full['execution'][stream+'_sha256']
    return {'report':fingerprint(path),'raw_report':report['raw_report'],'observation_count':len(rows),'observation_groups':report['observation_groups'],'projected_observations':report['projected_observations'],'observations_sha256':report['observations_sha256'],'status':report['status'],'independent_actual_observation_parity':report.get('independent_actual_observation_parity'),'raw_execution_available':report['raw_execution_available'],'producer_at_execution':report.get('producer_at_execution')}

def compact_existing_reports():
    before=fingerprint(OUTPUT);data=json.loads(OUTPUT.read_text())
    assert before['sha256']=='549a49a0e1b8cfb8e9790023cabb718e1d8f8c2e9ebdd2bb6be57603a93eb1da','Frozen collision reference bytes changed'
    assert data['source_sha256']==hashlib.sha256(SOURCE.encode()).hexdigest()
    assert data['inputs_sha256']==sha(inputs())
    assert data['expanded_source_sha256']=={n:hashlib.sha256(s.encode()).hexdigest() for n,s in sources(inputs()).items()}
    assert data['launcher_sha256']==hashlib.sha256(LI.RECEIVER_LAUNCHER.encode()).hexdigest()
    reports=[]
    for path in sorted((ROOT/'evidence').glob('local-collision-reference-*.json')):
        evidence=json.loads(path.read_text())
        if evidence.get('evidence_format')=='local-collision-summary-v1':
            verify_compact_report(path)
            full=json.loads((ROOT/evidence['raw_report']['path']).read_text())
            compact_report(path,full,(ROOT/evidence['raw_report']['path']).read_bytes())
        elif 'observations' in evidence:compact_report(path,evidence,path.read_bytes())
        else:continue
        reports.append(verify_compact_report(path))
    after=fingerprint(OUTPUT);assert before==after,'Storage migration changed reference bytes'
    certificate={'schema_version':1,'status':'passed','scope':'Storage/provenance only; no reference values or Java SOURCE/corpus/templates/launcher bytes changed. Historical report metadata is retained; fresh rerun claims remain attached only to their actual execution.',
                 'producer':fingerprint(Path(__file__)),'reference_before':before,'reference_after':after,
                 'source_sha256':data['source_sha256'],'inputs_sha256':data['inputs_sha256'],'expanded_source_sha256':data['expanded_source_sha256'],'launcher_sha256':data['launcher_sha256'],
                 'reference_observations_sha256':data['observations_sha256'],'counts':data['counts'],'reports':reports,
                 'raw_output_directory':'build/local-collision-reference','raw_output_ignored':True}
    save(ROOT/'evidence/local-collision-reference-storage.json',certificate)
    return certificate

SOURCE=r'''
package net.minecraft.fixture;
import java.io.*;
import java.util.*;
import java.lang.reflect.*;
import java.security.MessageDigest;
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
import net.minecraft.util.Mth;
import net.minecraft.world.entity.*;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.player.Input;
import net.minecraft.world.level.block.*;
import net.minecraft.world.level.block.state.*;
import net.minecraft.world.level.block.state.properties.*;
import net.minecraft.world.phys.*;
import net.minecraft.world.phys.shapes.VoxelShape;
public class LocalCollisionReceiverFixture {
 static final Gson JSON=new GsonBuilder().serializeNulls().create();
 static final PrintStream OUTPUT=System.out;
 static String bits(double d){return LocalInputReceiverFixture.bits(d);}
 static String bits(float f){return LocalInputReceiverFixture.bits(f);}
 static List<String> vector(Vec3 v){return LocalInputReceiverFixture.vector(v);}
 static List<String> box(AABB b){return List.of(bits(b.minX),bits(b.minY),bits(b.minZ),bits(b.maxX),bits(b.maxY),bits(b.maxZ));}
 static float f(JsonElement e){return Float.intBitsToFloat(Integer.parseUnsignedInt(e.getAsString(),16));}
 static double d(JsonElement e){return Double.longBitsToDouble(Long.parseUnsignedLong(e.getAsString(),16));}
 static Vec3 vec(JsonArray a){return new Vec3(d(a.get(0)),d(a.get(1)),d(a.get(2)));}
 static Object invoke(Object p,Class<?> owner,String name,Class<?>[] types,Object...args)throws Exception{Method m=owner.getDeclaredMethod(name,types);m.setAccessible(true);return m.invoke(p,args);}
 static String classification(double v){return Double.isNaN(v)?"nan":Double.isInfinite(v)?"infinite":"finite";}
 static Map<String,Object> acos(double value){double m=Math.acos(value),s=StrictMath.acos(value);return Map.of("math_f64_bits",bits(m),"strict_math_f64_bits",bits(s),"math_class",classification(m),"strict_math_class",classification(s));}
 static class TraceLevel extends LocalInputReceiverFixture.FixtureLevel {
  final List<Map<String,Object>> events=new ArrayList<>();boolean capture=false;int query=-1;int nextQuery=0;
  TraceLevel(ClientPacketListener connection,Holder<net.minecraft.world.level.dimension.DimensionType> dimension){super(connection,dimension);}
  void clear(){events.clear();nextQuery=0;query=-1;}
  public BlockState getBlockState(BlockPos p){BlockState b=super.getBlockState(p);if(capture&&events!=null)events.add(Map.of("method","getBlockState","query",query,"position",List.of(p.getX(),p.getY(),p.getZ()),"block_id",BuiltInRegistries.BLOCK.getKey(b.getBlock()).toString()));return b;}
  public boolean noCollision(Entity p,AABB b){int old=query;query=nextQuery++;Map<String,Object> e=new TreeMap<>();e.put("method","noCollision_entry");e.put("query",query);e.put("box",box(b));e.put("entity_is_fixture_player",p instanceof LocalPlayer);if(capture)events.add(e);boolean value=super.noCollision(p,b);if(capture)events.add(Map.of("method","noCollision_exit","query",query,"result",value));query=old;return value;}
  public Iterable<VoxelShape> getBlockCollisions(Entity p,AABB b){Iterable<VoxelShape> source=super.getBlockCollisions(p,b);int q=query;return ()->{Iterator<VoxelShape> it=source.iterator();return new Iterator<VoxelShape>(){public boolean hasNext(){return it.hasNext();}public VoxelShape next(){VoxelShape v=it.next();if(capture){List<List<String>> raw=new ArrayList<>();for(AABB a:v.toAabbs())raw.add(box(a));events.add(Map.of("method","actual_block_collision_shape_yield","query",q,"boxes",raw));}return v;}};};}
 }
 static class ObservedPlayer extends LocalPlayer {
  final List<Map<String,Object>> calls=new ArrayList<>();
  ObservedPlayer(Minecraft mc,ClientLevel level,ClientPacketListener connection){super(mc,level,connection,new StatsCounter(),new ClientRecipeBook(),Input.EMPTY,false,ChatAbilities.NO_RESTRICTIONS,new ItemActivation());}
  protected boolean isHorizontalCollisionMinor(Vec3 movement){boolean result=super.isHorizontalCollisionMinor(movement);if(calls!=null)calls.add(Map.of("method","isHorizontalCollisionMinor","movement",vector(movement),"result",result));return result;}
  protected Vec3 maybeBackOffFromEdge(Vec3 movement,MoverType type){Vec3 result=super.maybeBackOffFromEdge(movement,type);if(calls!=null)calls.add(Map.of("method","maybeBackOffFromEdge","movement",vector(movement),"mover",type.name(),"result",vector(result),"same_instance",result==movement));return result;}
 }
 static class Context {
  final Minecraft mc;final ClientPacketListener connection;final LocalInputReceiverFixture.FixtureLevel level;final LocalPlayer p;
  Context(HolderLookup.Provider lookup,boolean observed)throws Exception{mc=new Minecraft();mc.options=new Options(mc,new File("/dev/null/reference-local-input-fixture"));connection=new ClientPacketListener(LocalInputReceiverFixture.access(lookup));mc.connection=connection;level=observed?new TraceLevel(connection,LocalInputReceiverFixture.dimension(lookup)):new LocalInputReceiverFixture.FixtureLevel(connection,LocalInputReceiverFixture.dimension(lookup));p=observed?new ObservedPlayer(mc,level,connection):new LocalPlayer(mc,level,connection,new StatsCounter(),new ClientRecipeBook(),Input.EMPTY,false,ChatAbilities.NO_RESTRICTIONS,new ItemActivation());mc.camera=p;mc.player=p;p.input=new KeyboardInput(mc.options);p.setPos(.5,1,.5);p.setOnGround(true);p.setYRot(0f);p.setXRot(0f);p.setOldRot();p.yHeadRot=0;p.yBodyRot=0;LocalInputReceiverFixture.seed(p,"autoJumpEnabled",false);}
 }
 static Map<String,Object> state(LocalPlayer p)throws Exception{Map<String,Object> m=new TreeMap<>(LocalInputReceiverFixture.state(p));m.put("fall_distance_f64_bits",bits(p.fallDistance));m.put("shift",p.isShiftKeyDown());m.put("flying",p.getAbilities().flying);m.put("step_attribute_f64_bits",bits(p.getAttributeValue(Attributes.STEP_HEIGHT)));Optional<?> support=(Optional<?>)LocalInputReceiverFixture.read(p,"mainSupportingBlockPos");m.put("main_support",support.isPresent()?List.of(((BlockPos)support.get()).getX(),((BlockPos)support.get()).getY(),((BlockPos)support.get()).getZ()):null);m.put("on_ground_no_blocks",LocalInputReceiverFixture.read(p,"onGroundNoBlocks"));return m;}
 static void configure(Context c,JsonObject in)throws Exception{
  LocalPlayer p=c.p;p.setPos(vec(in.getAsJsonArray("position")));JsonArray input=in.getAsJsonArray("input_f32_bits");p.xxa=f(input.get(0));p.yya=f(input.get(1));p.zza=f(input.get(2));p.setYRot(f(in.get("yaw_f32_bits")));p.setXRot(0);p.setOldRot();p.setOnGround(in.get("grounded").getAsBoolean());p.fallDistance=d(in.get("fall_distance_f64_bits"));p.getAbilities().flying=in.get("flying").getAsBoolean();p.input.keyPresses=new Input(false,false,false,false,false,in.get("shift").getAsBoolean(),false);LocalInputReceiverFixture.seed(p,"crouching",in.get("crouching").getAsBoolean());p.setPose(Pose.valueOf(in.get("pose").getAsString()));p.getAttribute(Attributes.STEP_HEIGHT).setBaseValue(d(in.get("step_attribute_f64_bits")));JsonElement support=in.get("main_support");Optional<BlockPos> pos=support.isJsonNull()?Optional.empty():Optional.of(new BlockPos(support.getAsJsonArray().get(0).getAsInt(),support.getAsJsonArray().get(1).getAsInt(),support.getAsJsonArray().get(2).getAsInt()));LocalInputReceiverFixture.seed(p,"mainSupportingBlockPos",pos);LocalInputReceiverFixture.seed(p,"onGroundNoBlocks",in.get("on_ground_no_blocks").getAsBoolean());
  for(JsonElement e:in.getAsJsonArray("world_writes")){JsonObject w=e.getAsJsonObject();JsonArray xyz=w.getAsJsonArray("position");BlockState b=switch(w.get("block").getAsString()){case "air"->Blocks.AIR.defaultBlockState();case "stone"->Blocks.STONE.defaultBlockState();case "slab_bottom"->Blocks.OAK_SLAB.defaultBlockState().setValue(BlockStateProperties.SLAB_TYPE,SlabType.BOTTOM);case "slab_top"->Blocks.OAK_SLAB.defaultBlockState().setValue(BlockStateProperties.SLAB_TYPE,SlabType.TOP);default->throw new IllegalArgumentException("Fixture block");};c.level.blocks.put(new BlockPos(xyz.get(0).getAsInt(),xyz.get(1).getAsInt(),xyz.get(2).getAsInt()),b);}
  for(JsonElement e:in.getAsJsonArray("support_history")){JsonObject h=e.getAsJsonObject();p.setOnGroundWithMovement(h.get("grounded").getAsBoolean(),h.get("horizontal").getAsBoolean(),h.get("movement").isJsonNull()?null:vec(h.getAsJsonArray("movement")));}
  if(c.level instanceof TraceLevel t){t.clear();t.capture=true;}if(p instanceof ObservedPlayer o)o.calls.clear();
 }
 // Supplemental numeric instrumentation reproduces scalar operation order
 // using actual Mth/Math methods. These values are not production locals and
 // never supply the decisive isHorizontalCollisionMinor result.
 static Map<String,Object> metrics(LocalPlayer p,Vec3 movement){float radians=p.getYRot()*0.017453292f;double sine=Mth.sin((double)radians),cosine=Mth.cos((double)radians);double x=(double)p.xxa*cosine-(double)p.zza*sine,z=(double)p.zza*cosine+(double)p.xxa*sine;double inputSquared=Mth.square(x)+Mth.square(z),movementSquared=Mth.square(movement.x)+Mth.square(movement.z),dot=x*movement.x+z*movement.z,ratio=dot/Math.sqrt(inputSquared*movementSquared);Map<String,Object> m=new TreeMap<>();m.put("scope","independent numeric instrumentation; not production-observed locals or decisive expected algorithm");m.put("radians_f32_bits",bits(radians));m.put("sin_f64_bits",bits(sine));m.put("cos_f64_bits",bits(cosine));m.put("rotated_f64_bits",List.of(bits(x),bits(z)));m.put("input_squared_f64_bits",bits(inputSquared));m.put("movement_squared_f64_bits",bits(movementSquared));m.put("dot_f64_bits",bits(dot));m.put("ratio_f64_bits",bits(ratio));m.put("direct_acos",acos(ratio));return m;}
 static void emit(Object v){OUTPUT.println("LOCAL_COLLISION_JSON:"+JSON.toJson(v));}
 static void runtime()throws Exception{Map<String,String> r=new TreeMap<>();for(String name:List.of("java.lang.Math","java.lang.StrictMath","java.lang.FdLibm","java.lang.FdLibm$Acos")){Class<?> c=Class.forName(name);byte[] bytes=c.getResourceAsStream("/"+name.replace('.','/')+".class").readAllBytes();r.put(name,HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)));}OUTPUT.println("LOCAL_COLLISION_RUNTIME:"+JSON.toJson(r));}
 public static void run(String ignored)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();runtime();HolderLookup.Provider lookup=VanillaRegistries.createWorldLookup();JsonObject inputs=JsonParser.parseString(new String(Base64.getDecoder().decode(__INPUT_BASE64__),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonObject();
  for(JsonElement e:inputs.getAsJsonArray("acos")){JsonObject in=e.getAsJsonObject();double v=d(in.get("input_f64_bits"));emit(Map.of("group","acos","id",in.get("id").getAsString(),"expected",acos(v)));}
  for(String group:List.of("minor","backoff"))for(JsonElement e:inputs.getAsJsonArray(group)){JsonObject in=e.getAsJsonObject();for(boolean observed:List.of(false,true)){Context c=new Context(lookup,observed);configure(c,in.getAsJsonObject("initial"));Vec3 movement=vec(in.getAsJsonArray("movement"));Map<String,Object> before=state(c.p);Map<String,Object> row=new TreeMap<>();row.put("id",in.get("id").getAsString());row.put("group",group);row.put("observed",observed);row.put("before",before);
   if(group.equals("minor")){boolean result=(boolean)invoke(c.p,LocalPlayer.class,"isHorizontalCollisionMinor",new Class<?>[]{Vec3.class},movement);row.put("expected",Map.of("minor",result));row.put("independent_numeric_instrumentation",metrics(c.p,movement));}
   else{Vec3 result=(Vec3)invoke(c.p,net.minecraft.world.entity.player.Player.class,"maybeBackOffFromEdge",new Class<?>[]{Vec3.class,MoverType.class},movement,MoverType.valueOf(in.get("mover").getAsString()));row.put("expected",Map.of("movement",vector(result),"same_instance",result==movement));}
   row.put("after",state(c.p));row.put("player_calls",observed?((ObservedPlayer)c.p).calls:List.of());row.put("query_events",observed?((TraceLevel)c.level).events:List.of());emit(row);
  }}
 }
}
'''

def fb(x):return struct.pack('>f',x).hex()
def db(x):return struct.pack('>d',x).hex()
def init(**changes):
    value={'position':[db(.5),db(1),db(.5)],'input_f32_bits':[fb(0),fb(0),fb(1)],'yaw_f32_bits':fb(0),
           'grounded':True,'fall_distance_f64_bits':db(0),'flying':False,'shift':True,'crouching':False,
           'pose':'STANDING','step_attribute_f64_bits':db(.6),'main_support':None,'on_ground_no_blocks':False,
           'world_writes':[],'support_history':[]}
    value.update(changes);return value

def inputs():
    rng=random.Random(SEED)
    ratios=[]
    centers=[0,0x0000000000000001,0x3c60000000000000,0x3c600000ffffffff,0x3c60000100000000,0x3fe0000000000000,0x3ff0000000000000]
    for c in centers:
        for sign in [0,1<<63]:
            for delta in range(-4,5):
                if 0<=c+delta<(1<<63):ratios.append(f'{(c+delta)|sign:016x}')
    ratios += ['7ff0000000000000','fff0000000000000','7ff8000000000000','fff8000000000000','7ff0000000000001','fff0000000000001','7fffffffffffffff']
    ratio_center=int(db(math.cos(0.13962633907794952)),16)
    ratios += [f'{ratio_center+i:016x}' for i in range(-12,13)]
    while len(ratios)<3072:
        ratios.append(db(rng.uniform(-1,1)) if len(ratios)%3 else f'{rng.getrandbits(64):016x}')
    acos=[{'id':f'acos:{i}','input_f64_bits':raw} for i,raw in enumerate(ratios)]
    minor=[]
    def add(name,xxa,zza,yaw,movement,**changes):
        minor.append({'id':'minor:'+name,'initial':init(input_f32_bits=[fb(xxa),fb(0),fb(zza)],yaw_f32_bits=fb(yaw),**changes),'movement':[db(v) for v in movement],'scope':'direct actual minor Bool; current Body is recorded admission data'})
    for i,(xxa,zza) in enumerate([(0,0),(-0.,-0.),(0,1),(1,0),(-1,1),(.98,.98),(1e-20,0),(0,1e-20),(.0031622776,0),(.0031622778,0)]):
        for j,m in enumerate([(0,0,0),(-0.,-0.,-0.),(1,0,0),(0,0,1),(.001,7,.001),(.004,-3,0),(1e308,1,1e308)]):add(f'base:{i}:{j}',xxa,zza,0,m)
    threshold=0.13962633907794952
    center=math.tan(threshold)
    angle_offsets=[-1e-4,-1e-8,-1e-12,0,1e-12,1e-8,1e-4]
    for i,offset in enumerate(angle_offsets):
        add(f'angle:{i}',0,1,0,(math.tan(threshold+offset),0,1))
    raw_center=int(db(center),16)
    for i in range(-16,17):add(f'angle_ratio_ulp:{i}',0,1,0,(struct.unpack('>d',bytes.fromhex(f'{raw_center+i:016x}'))[0],0,1))
    for i in range(224):
        yaw=[-360,-180,-90,-0.,0,45,90,180,360,1e20][i%10]
        add(f'custom:{i}',rng.uniform(-2,2),rng.uniform(-2,2),yaw,(rng.uniform(-3,3),rng.uniform(-1e4,1e4),rng.uniform(-3,3)),grounded=i%2==0)
    # Nonfinite inputs are explicitly helper-only and outside minor_checked.
    for i,raw in enumerate(['7fc00000','7f800000','ff800000']):
        case={'id':f'minor:unsupported_nonfinite:{i}','initial':init(input_f32_bits=[raw,fb(0),fb(1)]),'movement':[db(1),db(0),db(1)],'scope':'helper-only nonfinite current input; outside finite facade admission'};minor.append(case)
    backoff=[]
    def edge(name,pos,movement=(1,0,0),mover='SELF',scope='finite fullcube helper admission',**changes):
        backoff.append({'id':'backoff:'+name,'initial':init(position=[db(v) for v in pos],**changes),'movement':[db(v) for v in movement],'mover':mover,'scope':scope})
    for i,pos in enumerate([(2.5,1,.5),(2.9,1,.5),(3.,1,.5),(3.29,1,.5),(-1.9,1,.5),(.5,1,2.9),(2.9,1,2.9),(-1.9,1,-1.9),(.5,1,.5)]):
        for j,m in enumerate([(1,0,0),(-1,-.1,0),(0,0,1),(1,0,1),(-1,0,-1),(.05,0,.05),(.05000000000000001,0,-.05),(-0.,-0.,0)]):edge(f'edge:{i}:{j}',pos,m)
    for i,(ground,fall,y,step) in enumerate([(False,0,1,.6),(False,.2,1.2,.6),(False,.599999999,1.5,.6),(False,.6,1.5,.6),(False,.7,1.5,.6),(True,4,1,.6),(False,-.2,1,.6),(False,0,1,0),(False,0,1,1),(True,0,1,.1)]):
        edge(f'above:{i}',(2.9,y,.5),grounded=ground,fall_distance_f64_bits=db(fall),step_attribute_f64_bits=db(step))
    for i,(mover,flying,shift,dy) in enumerate([('SELF',True,True,0),('SELF',False,False,0),('PISTON',False,True,0),('SHULKER',False,True,0),('SHULKER_BOX',False,True,0),('PLAYER',False,True,0),('SELF',False,True,.01)]):
        edge(f'guard:{i}',(2.9,1,.5),(1,dy,1),mover=mover,flying=flying,shift=shift,scope='direct gate observation; unsupported mover/flight/positiveY are outside neutral edge admission')
    for i,history in enumerate([[],[{'grounded':False,'horizontal':False,'movement':None}],[{'grounded':True,'horizontal':False,'movement':None}],[{'grounded':True,'horizontal':False,'movement':[db(0),db(0),db(0)]}],[{'grounded':True,'horizontal':True,'movement':[db(.1),db(0),db(.1)]}]]):
        edge(f'support_history:{i}',(2.9,1,2.9),(1,0,1),main_support=[2,0,2],on_ground_no_blocks=i%2==1,support_history=history)
    for i,kind in enumerate(['slab_bottom','slab_top']):
        writes=[{'position':[x,0,z],'block':kind} for x in range(-2,3) for z in range(-2,3)]
        edge(f'real_slab:{kind}',(2.9,.5 if i==0 else 1,2.9),(1,0,1),world_writes=writes,scope='actual slab-shaped query helper only; outside fullcube world resolver admission')
    edge('crouching_without_shift',(2.9,1,.5),crouching=True,shift=False)
    edge('shift_without_crouching',(2.9,1,.5),crouching=False,shift=True)
    edge('nan_vertical',(2.9,1,.5),(1,float('nan'),0),scope='helper-only nonfinite Y; actual dcmpl gate allows it; outside finite facade admission')
    return {'acos':acos,'minor':minor,'backoff':backoff}

def dependency_pin():
    tool=fingerprint(ROOT/'tools/reference_local_input_probe.py');reference=fingerprint(ROOT/'reference/local_input.json')
    data=json.loads((ROOT/'reference/local_input.json').read_text())
    seal={k:data[k] for k in ['pin','inputs_sha256','observations_sha256','fixture_template_sha256','launcher_source_sha256']}
    semantic_sha=hashlib.sha256(canonical(seal)).hexdigest()
    assert semantic_sha==FROZEN_REFERENCE_SEMANTICS,'Frozen local-input gameplay provenance changed'
    assert data['observations_sha256']==hashlib.sha256(canonical({g:data[g] for g in LI.GROUPS})).hexdigest(),'Frozen local-input observations changed'
    templates={n:hashlib.sha256(s.encode()).hexdigest() for n,s in LI.RECEIVER_SOURCES.items()}
    launcher=hashlib.sha256(LI.RECEIVER_LAUNCHER.encode()).hexdigest()
    assert templates==data['fixture_template_sha256'],'Frozen receiver templates changed'
    assert launcher==data['launcher_source_sha256'],'Frozen receiver launcher changed'
    return {'producer_at_execution':tool,'reference_at_execution':reference,'reference_gameplay_seal_sha256':semantic_sha,'receiver_templates':templates,'launcher':launcher}

def stable_dependency(d):
    return {k:d[k] for k in ['reference_gameplay_seal_sha256','receiver_templates','launcher']}

def source_inventory():
    result=LI.source_inventory()
    names=['net.minecraft.client.player.LocalPlayer','net.minecraft.world.entity.player.Player','net.minecraft.world.entity.LivingEntity','net.minecraft.world.level.CollisionGetter','net.minecraft.world.level.BlockCollisions','net.minecraft.world.phys.AABB','net.minecraft.util.Mth','java.lang.Math','java.lang.StrictMath','java.lang.FdLibm','java.lang.FdLibm$Acos']
    wanted={'isHorizontalCollisionMinor','maybeBackOffFromEdge','isAboveGround','isStayingOnGroundSurface','canFallAtLeast','isShiftKeyDown','maxUpStep','noCollision','noBlockCollision','noEntityCollision','noBorderCollision','getBlockCollisions','compute','acos','sin','cos','square','__HI','__LO'}
    with zipfile.ZipFile(CLIENT) as jar:
        for owner in names:
            s=subprocess.run([str(JAVA.parent/'javap'),'-classpath',str(CLIENT),'-c','-p',owner],capture_output=True,text=True,check=True).stdout
            methods=[]
            for sig,body in re.findall(r'^  ((?:public|protected|private|static)[^\n]*?\([^\n]*\);)\n(.*?)(?=^  (?:public|protected|private|static)|\Z)',s,re.M|re.S):
                n=re.search(r'([\w$<>]+)\([^\n]*\);$',sig)
                if n and n[1] in wanted:methods.append({'signature':sig,'bytecode_text_sha256':hashlib.sha256(body.encode()).hexdigest(),'direct_call_references':sorted(set(re.findall(r'// (?:InterfaceMethod|Method) (.+)',body))),'field_references':sorted(set(re.findall(r'// Field (.+)',body)))})
            entry=owner.replace('.','/')+'.class'
            result[owner]={'class_entry':entry,'class_sha256':hashlib.sha256(jar.read(entry)).hexdigest() if not owner.startswith('java.') else None,'complete_bytecode_text_sha256':hashlib.sha256(s.encode()).hexdigest(),'methods':methods}
    return result

def runtime_inventory():
    source='''import java.util.*;import java.security.*;class LocalCollisionRuntimePin {public static void main(String[] a)throws Exception{for(String name:List.of("java.lang.Math","java.lang.StrictMath","java.lang.FdLibm","java.lang.FdLibm$Acos")){Class<?> c=Class.forName(name);byte[] bytes=c.getResourceAsStream("/"+name.replace('.','/')+".class").readAllBytes();System.out.println(name+":"+HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)));}}}'''
    run=subprocess.run([str(JAVA),'--source','25','/dev/stdin'],input=source,capture_output=True,text=True,check=True)
    return dict(line.rsplit(':',1) for line in run.stdout.splitlines())

def sources(cases):
    result=LI.receiver_sources()
    encoded=base64.b64encode(canonical(cases)).decode()
    result['net.minecraft.fixture.LocalCollisionReceiverFixture']=SOURCE.replace('__INPUT_BASE64__',LI.java_string(encoded))
    return result

def collect(cases,rows):
    by_id={}
    for row in rows:by_id.setdefault(row['id'],[]).append(row)
    result={g:[] for g in GROUPS}
    for group in GROUPS:
        for case in cases[group]:
            observations=by_id.pop(case['id'])
            if group=='acos':
                assert len(observations)==1;result[group].append({**case,'expected':observations[0]['expected']});continue
            plain=next(o for o in observations if not o['observed']);observed=next(o for o in observations if o['observed'])
            for key in ['before','after','expected']+(['independent_numeric_instrumentation'] if group=='minor' else []):assert plain[key]==observed[key],f"Observer parity {case['id']} {key}"
            assert plain['before']==plain['after'],f"Pure helper mutated state: {case['id']}"
            item={**case,**{k:v for k,v in observed.items() if k not in ('group','observed')},'plain_observer_parity':True}
            events=item['query_events'];queries=[]
            for e in events:
                if e['method']=='noCollision_entry':
                    exit_event=next(x for x in events if x['method']=='noCollision_exit' and x['query']==e['query'])
                    queries.append({'index':e['query'],'box':e['box'],'no_collision':exit_event['result'],'actual_yielded_boxes':[a for x in events if x['method']=='actual_block_collision_shape_yield' and x['query']==e['query'] for a in x['boxes']]})
            item['no_collision_queries']=queries
            result[group].append(item)
    assert not by_id
    return result

def boundary():
    return {'decisive':'Untouched actual LocalPlayer.isHorizontalCollisionMinor and inherited Player.maybeBackOffFromEdge calls on normal-constructed receivers; no Python gameplay expected algorithm.',
            'numeric_instrumentation':'Minor rotated/squared/dot/ratio/acos metrics are explicitly independent scalar instrumentation using receiver fields and actual Mth/Math. They are not production local-variable observations and never supply decisive Bool expectations.',
            'query_authority':'TraceLevel.noCollision calls super; actual CollisionGetter.noBlockCollision/noEntityCollision/noBorderCollision and actual BlockCollisions determine each result. Wrapped original iterator records only shapes actually yielded, retaining short-circuit and order; getBlockState observes real finite fixture reads.',
            'observer_parity':'Plain actual LocalPlayer/frozen FixtureLevel outputs and before/after projected fields equal observed subclasses whose helpers/noCollision call super.',
            'frozen_external_services':'Exactly the four frozen LI external types Minecraft/Gui/Tutorial/ClientPacketListener, normal gameplay/Level constructors and unchanged official jar class bytes. Existing LI source/reference hashes asserted before execution.',
            'world':'25 actual stone states x,z=-2..2,y=0; explicit actual air/slab writes are case input. Actual empty actor storage and real default WorldBorder; no replaced collision predicate/shape decisions.',
            'support':'Initial Optional<BlockPos>/onGroundNoBlocks are explicitly seeded cache history; optional actual setOnGroundWithMovement calls produce recorded before state. Actual helper does not mutate projected body/cache fields.',
            'admission':'Finite yaw/input/displacement and bounded finite horizontal backoff moves admitted; helper-only nonfinite minor inputs/vertical backoff, flight/non-SELF/PLAYER/positiveY guards and slabs are explicitly labelled outside neutral/fullcube facade admission.',
            'nan':'Acos records full pinned-runtime raw bits and nan/finite/infinite classes. NaN payload equality is a runtime observation, not a portability guarantee.',
            'scope':'Direct minor/edge helper parity and numeric acos only; no full Entity.move/LocalPlayer tick/world-travel/client parity claim.'}

def run(cases,label='actual'):
    dependency=dependency_pin();classpath,provenance=verified_client_classpath();ss=sources(cases)
    payload={'sources':ss,'client_jar':str(CLIENT),'mode':'collision'}
    encoded=base64.b64encode(canonical(payload)).decode()
    launcher=LI.RECEIVER_LAUNCHER.replace('net.minecraft.fixture.LocalInputReceiverFixture','net.minecraft.fixture.LocalCollisionReceiverFixture').replace('Base64.getDecoder().decode(args[0])','Base64.getDecoder().decode('+LI.java_string(encoded)+')',1)
    command=[str(JAVA),'--source','25','--class-path',':'.join(map(str,classpath)),'/dev/stdin'];start=time.monotonic();execution=subprocess.run(command,input=launcher,capture_output=True,text=True)
    def parsed(prefix):return [json.loads(line[len(prefix):]) for line in execution.stdout.splitlines() if line.startswith(prefix)]
    rows=parsed('LOCAL_COLLISION_JSON:');loaded=parsed('LOCAL_INPUT_CLASSES:');runtime=parsed('LOCAL_COLLISION_RUNTIME:');inventory=source_inventory()
    if execution.returncode==0:
        assert len(loaded)==len(runtime)==1
        for name,digest in loaded[0].items():
            if name in inventory and not name.startswith('java.'):assert digest==inventory[name]['class_sha256'],'Changed official class: '+name
        for name,digest in runtime[0].items():inventory[name]['class_sha256']=digest
        observations=collect(cases,rows)
    else:observations=None
    evidence={'schema_version':1,'pin':'26.3','status':'passed' if execution.returncode==0 else 'blocked','dependency':dependency,'provenance':provenance,'source':inventory,'boundary':boundary(),
              'source_sha256':hashlib.sha256(SOURCE.encode()).hexdigest(),'expanded_source_sha256':{n:hashlib.sha256(s.encode()).hexdigest() for n,s in ss.items()},'launcher_sha256':hashlib.sha256(LI.RECEIVER_LAUNCHER.encode()).hexdigest(),
              'substituted_external_types':{n:{'source':s,'source_sha256':hashlib.sha256(s.encode()).hexdigest()} for n,s in LI.RECEIVER_SOURCES.items() if n!='net.minecraft.fixture.LocalInputReceiverFixture'},
              'loaded_official_classes':{n:d for n,d in loaded[0].items() if n in inventory} if loaded else {},'loaded_official_class_count':len(loaded[0]) if loaded else 0,'loaded_official_class_tree_sha256':hashlib.sha256(canonical(loaded[0])).hexdigest() if loaded else None,
              'runtime_classes':runtime[0] if runtime else {},'execution':{'command':command,'seconds':round(time.monotonic()-start,6),'returncode':execution.returncode,'reproduce':'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_collision_probe.py --'+('rerun' if label=='independent' else 'extract'),'stdout_sha256':hashlib.sha256(execution.stdout.encode()).hexdigest(),'stderr_sha256':hashlib.sha256(execution.stderr.encode()).hexdigest(),'stderr_tail':execution.stderr[-5000:],'failure_stdout':'\n'.join(x for x in execution.stdout.splitlines() if not x.startswith('LOCAL_INPUT_CLASSES:'))[-10000:] if execution.returncode else None},
              'observations':rows,'observations_sha256':hashlib.sha256(canonical(rows)).hexdigest()}
    evidence['producer_at_execution']=fingerprint(Path(__file__))
    evidence['raw_execution']={'stdout':execution.stdout,'stderr':execution.stderr,'loaded_official_classes':loaded[0] if loaded else None}
    path=ROOT/f'evidence/local-collision-reference-{label}.json';compact_report(path,evidence)
    return observations,evidence,path

def extract(debug=False):
    cases=inputs()
    if debug:cases={g:c[:2] for g,c in cases.items()}
    obs,evidence,path=run(cases,'debug' if debug else 'actual')
    if obs is None:return {'status':'blocked','evidence':fingerprint(path),'failure':evidence['execution']['failure_stdout'] or evidence['execution']['stderr_tail']}
    if debug:return {'status':'passed','debug':True,'evidence':fingerprint(path)}
    data={k:evidence[k] for k in ['schema_version','pin','dependency','provenance','source','boundary','source_sha256','expanded_source_sha256','launcher_sha256','loaded_official_classes','loaded_official_class_count','loaded_official_class_tree_sha256','runtime_classes']}
    data.update(random_input_seed=SEED,inputs_sha256=hashlib.sha256(canonical(cases)).hexdigest(),**obs)
    data['observations_sha256']=hashlib.sha256(canonical(obs)).hexdigest();data['counts']={g:len(obs[g]) for g in GROUPS};data['counts']['no_collision_queries']=sum(len(c['no_collision_queries']) for c in obs['backoff']);save(OUTPUT,data)
    return {'status':'passed','reference':fingerprint(OUTPUT),'evidence':fingerprint(path),'counts':data['counts']}

def verify_data(data,provenance,inventory):
    cases=inputs();assert data['schema_version']==1 and data['pin']=='26.3';assert stable_dependency(data['dependency'])==stable_dependency(dependency_pin()),'Frozen dependencies changed';assert data['provenance']==provenance,'Pinned client/runtime/libraries changed';assert data['source_sha256']==hashlib.sha256(SOURCE.encode()).hexdigest(),'Observer source changed';assert data['expanded_source_sha256']=={n:hashlib.sha256(s.encode()).hexdigest() for n,s in sources(cases).items()},'Expanded sources changed';assert data['launcher_sha256']==hashlib.sha256(LI.RECEIVER_LAUNCHER.encode()).hexdigest(),'Frozen launcher changed';assert data['boundary']==boundary(),'Scope changed';assert data['inputs_sha256']==hashlib.sha256(canonical(cases)).hexdigest(),'Input corpus changed'
    runtime=runtime_inventory();assert data['runtime_classes']==runtime,'Actual runtime math class bytes changed'
    for name,digest in runtime.items():inventory[name]['class_sha256']=digest
    assert data['source']==inventory,'Class/method inventory changed';assert data['observations_sha256']==hashlib.sha256(canonical({g:data[g] for g in GROUPS})).hexdigest(),'Observations changed'
    for name,digest in data['loaded_official_classes'].items():assert digest==inventory[name]['class_sha256'],'Official receiver bytes changed'
    return True

def verify(selftest=False):
    data=json.loads(OUTPUT.read_text());_,provenance=verified_client_classpath();inventory=source_inventory();verify_data(data,provenance,inventory);result={'status':'passed','reference':fingerprint(OUTPUT),'counts':data['counts'],'scope':'Integrity/provenance only; no new actual helper run'}
    if selftest:
        checks=[]
        for label,path in [('client',['provenance','client','sha256']),('runtime',['provenance','java','sha256']),('library',['provenance','libraries',0,'sha256']),('source',['source_sha256']),('observations',['minor',0,'expected','minor'])]:
            changed=copy.deepcopy(data);obj=changed
            for key in path[:-1]:obj=obj[key]
            obj[path[-1]]=not obj[path[-1]] if isinstance(obj[path[-1]],bool) else 'injected-mismatch'
            try:verify_data(changed,provenance,inventory)
            except AssertionError as e:checks.append({'injection':label,'rejected':True,'reason':str(e)})
            else:raise AssertionError('Injection accepted: '+label)
        result['failure_injections']=checks
    result['producer']=fingerprint(Path(__file__));save(ROOT/'evidence/local-collision-reference-integrity.json',result);return result

def rerun():
    data=json.loads(OUTPUT.read_text());_,provenance=verified_client_classpath();verify_data(data,provenance,source_inventory());obs,evidence,path=run(inputs(),'independent');assert obs is not None,'Independent actual execution failed';assert obs=={g:data[g] for g in GROUPS},'Independent actual outputs changed';assert evidence['loaded_official_class_tree_sha256']==data['loaded_official_class_tree_sha256'],'Actual official class tree changed';assert evidence['runtime_classes']==data['runtime_classes'],'Runtime math classes changed';evidence['independent_actual_observation_parity']=True;evidence['reference_compared']=fingerprint(OUTPUT);compact_report(path,evidence);return {'status':'passed','reference':fingerprint(OUTPUT),'evidence':fingerprint(path),'independent_actual_observation_parity':True}

def main():
    p=argparse.ArgumentParser();p.add_argument('--extract',action='store_true');p.add_argument('--debug',action='store_true');p.add_argument('--verify-existing',action='store_true');p.add_argument('--selftest',action='store_true');p.add_argument('--rerun',action='store_true');p.add_argument('--compact-existing',action='store_true');a=p.parse_args()
    if a.compact_existing:r=compact_existing_reports()
    elif a.verify_existing or a.selftest:r=verify(a.selftest)
    elif a.rerun:r=rerun()
    elif a.extract or a.debug:r=extract(a.debug)
    else:p.error('Select --extract, --verify-existing, --selftest or --rerun.')
    print(json.dumps(r,indent=2))

if __name__=='__main__':main()
