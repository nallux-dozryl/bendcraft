#!/usr/bin/env python3
"""Actual pinned registered SlabBlock collision receivers and context matrix."""
from __future__ import annotations
import argparse
import collections
import csv
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile

from reference_inventory import ROOT,JAVA,canonical,fingerprint,write_json
from reference_block_probe import verified_classpath
from reference_movement_probe import SOURCE as MOVE_SOURCE,DIRECT_SOURCE
from test_persistence import registry_identity,OFFICIAL

WORK=ROOT/'build/slab-collision/reference'
TABLE=ROOT/'generated/reference_slab_collision.tsv'
REFERENCE=ROOT/'reference/slab_collision.json'

SOURCE=r'''import java.io.*;
import java.nio.file.*;
import java.lang.reflect.*;
import java.util.*;
import com.google.gson.Gson;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.CollisionGetter;
import net.minecraft.world.level.EmptyBlockGetter;
import net.minecraft.world.level.block.*;
import net.minecraft.world.level.block.state.*;
import net.minecraft.world.level.block.state.properties.*;
import net.minecraft.world.level.material.*;
import net.minecraft.world.entity.*;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.entity.decoration.ArmorStand;
import net.minecraft.world.item.*;
import net.minecraft.world.phys.*;
import net.minecraft.world.phys.shapes.*;

class ReferenceSlabCollisionProbe {
  static final Gson JSON=new Gson();
  static final BlockPos[] POSITIONS={BlockPos.ZERO,new BlockPos(7,11,-13),new BlockPos(Integer.MIN_VALUE,Integer.MAX_VALUE,-17)};
  static final String[] WORLDS={"empty","stone-neighbors","water-neighbors","throw-on-read"};
  static final String[] CONTEXTS={"empty","position-low","position-high","fluid","item","armor-standing","armor-descending","placement-null"};
  static String bits(double x){return String.format(Locale.ROOT,"%016x",Double.doubleToRawLongBits(x));}
  static String boxes(VoxelShape shape){
    var result=new ArrayList<List<String>>();
    for(AABB b:shape.toAabbs())result.add(List.of(bits(b.minX),bits(b.minY),bits(b.minZ),bits(b.maxX),bits(b.maxY),bits(b.maxZ)));
    return JSON.toJson(result);
  }
  static Method method(Class<?> c,String name,Class<?>...args) throws Exception {
    while(c!=null){try{return c.getDeclaredMethod(name,args);}catch(NoSuchMethodException absent){c=c.getSuperclass();}}
    throw new NoSuchMethodException(name);
  }
  static Field field(Class<?> c,String name) throws Exception {
    while(c!=null){try{Field f=c.getDeclaredField(name);f.setAccessible(true);return f;}catch(NoSuchFieldException absent){c=c.getSuperclass();}}
    throw new NoSuchFieldException(name);
  }
  static class TraceLevel extends ReferenceDirectMovementProbe.FixtureLevel {
    int mode;BlockPos target;BlockState center;
    public BlockState getBlockState(BlockPos p){hit("getBlockState");if(mode==3)throw new IllegalStateException("Unexpected collision world read");return p.equals(target)?center:(mode==1?Blocks.STONE:mode==2?Blocks.WATER:Blocks.AIR).defaultBlockState();}
    public FluidState getFluidState(BlockPos p){hit("getFluidState");if(mode==3)throw new IllegalStateException("Unexpected collision fluid read");return getBlockState(p).getFluidState();}
    public net.minecraft.world.level.block.entity.BlockEntity getBlockEntity(BlockPos p){hit("getBlockEntity");if(mode==3)throw new IllegalStateException("Unexpected collision block-entity read");return null;}
    public int getMinY(){hit("getMinY");if(mode==3)throw new IllegalStateException("Unexpected collision minY read");return -64;}
    public int getHeight(){hit("getHeight");if(mode==3)throw new IllegalStateException("Unexpected collision height read");return 384;}
    public net.minecraft.world.flag.FeatureFlagSet enabledFeatures(){return net.minecraft.world.flag.FeatureFlags.DEFAULT_FLAGS;}
  }
  static class Spy implements CollisionContext {
    final CollisionContext target;final Map<String,Integer> reads=new TreeMap<>();
    Spy(CollisionContext c){target=c;}
    void hit(String s){reads.merge(s,1,Integer::sum);}
    public boolean isDescending(){hit("isDescending");return target.isDescending();}
    public boolean isAbove(VoxelShape s,BlockPos p,boolean b){hit("isAbove");return target.isAbove(s,p,b);}
    public boolean isHoldingItem(Item i){hit("isHoldingItem");return target.isHoldingItem(i);}
    public boolean alwaysCollideWithFluid(){hit("alwaysCollideWithFluid");return target.alwaysCollideWithFluid();}
    public boolean canStandOnFluid(FluidState a,FluidState b){hit("canStandOnFluid");return target.canStandOnFluid(a,b);}
    public boolean isPlacement(){hit("isPlacement");return target.isPlacement();}
    public VoxelShape getCollisionShape(BlockState s,CollisionGetter w,BlockPos p){hit("getCollisionShape");return target.getCollisionShape(s,w,p);}
  }
  static CollisionContext context(int n,ItemEntity item,ArmorStand armor){
    return switch(n){
      case 0->CollisionContext.empty();case 1->CollisionContext.positionContext(-64.0);case 2->CollisionContext.positionContext(256.0);
      case 3->CollisionContext.emptyWithFluidCollisions();case 4->CollisionContext.of(item);
      case 5->{armor.setShiftKeyDown(false);armor.setPos(0.5,2.0,0.5);yield CollisionContext.of(armor);}
      case 6->{armor.setShiftKeyDown(true);armor.setPos(-0.5,-2.0,-0.5);yield CollisionContext.of(armor,true);}
      case 7->CollisionContext.placementContext(null);default->throw new AssertionError();};
  }
  public static void main(String[] args) throws Exception {
    SharedConstants.tryDetectVersion();Bootstrap.bootStrap();
    var lookup=net.minecraft.data.registries.VanillaRegistries.createWorldLookup();
    for(var pending:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup))pending.forEach((holder,components)->holder.bindComponents(components));
    ReferenceDirectMovementProbe.initialize();
    TraceLevel level=new TraceLevel();level.center=Blocks.AIR.defaultBlockState();level.target=BlockPos.ZERO;
    ItemEntity item=new ItemEntity(level,0.5,2.0,0.5,new ItemStack(Items.STONE));
    ArmorStand armor=new ArmorStand(level,0.5,2.0,0.5);
    var constructorReads=new TreeMap<>(level.calls);level.clearTrace();
    Field collision=field(Block.class,"hasCollision"),cache=field(BlockState.class,"cache");
    var receivers=new TreeMap<String,Object>();var records=new ArrayList<Map<String,Object>>();long calls=0;
    var contextReceivers=new TreeMap<String,Object>();
    for(int c=0;c<CONTEXTS.length;c++){CollisionContext ctx=context(c,item,armor);var cr=new TreeMap<String,String>();cr.put("class",ctx.getClass().getName());cr.put("shape_owner",method(ctx.getClass(),"getCollisionShape",BlockState.class,CollisionGetter.class,BlockPos.class).getDeclaringClass().getName());contextReceivers.put(CONTEXTS[c],cr);}
    try(var out=new PrintWriter(Files.newBufferedWriter(Path.of(args[0])))){
      out.println("state_id\tblock_identifier\tslab_type\twaterlogged\tworld\tposition\troute\tcontext\taabbs_f64_bits\tworld_reads\tcontext_reads");
      for(int id=0;id<Block.BLOCK_STATE_REGISTRY.size();id++){
        BlockState state=Block.stateById(id);Block b=state.getBlock();if(!(b instanceof SlabBlock))continue;
        String name=BuiltInRegistries.BLOCK.getKey(b).toString();String type=state.getValue(SlabBlock.TYPE).getSerializedName();boolean waterlogged=state.getValue(SlabBlock.WATERLOGGED);
        String baseline=boxes(state.getCollisionShape(EmptyBlockGetter.INSTANCE,BlockPos.ZERO,CollisionContext.empty()));
        if(!receivers.containsKey(name)){
          var r=new TreeMap<String,Object>();r.put("class",b.getClass().getName());r.put("protocol",BuiltInRegistries.BLOCK.getId(b));r.put("default_state_id",Block.getId(b.defaultBlockState()));
          var owners=new TreeMap<String,String>();
          for(String m:List.of("getCollisionShape","getShape"))owners.put(m,method(b.getClass(),m,BlockState.class,BlockGetter.class,BlockPos.class,CollisionContext.class).getDeclaringClass().getName());
          r.put("method_owners",owners);r.put("state_collision_context_owner",method(state.getClass(),"getCollisionShape",BlockGetter.class,BlockPos.class,CollisionContext.class).getDeclaringClass().getName());
          r.put("state_collision_cached_owner",method(state.getClass(),"getCollisionShape",BlockGetter.class,BlockPos.class).getDeclaringClass().getName());
          r.put("has_collision",collision.getBoolean(b));r.put("has_collision_owner",collision.getDeclaringClass().getName());r.put("has_collision_modifiers",Modifier.toString(collision.getModifiers()));r.put("dynamic_shape",b.hasDynamicShape());receivers.put(name,r);
        }
        var record=new TreeMap<String,Object>();record.put("state_id",id);record.put("identifier",name);record.put("slab_type",type);record.put("waterlogged",waterlogged);record.put("cache_present",cache.get(state)!=null);record.put("offset",state.hasOffsetFunction());record.put("aabbs_f64_bits",JSON.fromJson(baseline,List.class));records.add(record);
        for(int w=0;w<WORLDS.length;w++)for(int p=0;p<POSITIONS.length;p++){
          BlockPos pos=POSITIONS[p];level.mode=w;level.target=pos;level.center=state;
          level.clearTrace();String cached=boxes(state.getCollisionShape(level,pos));
          out.println(id+"\t"+name+"\t"+type+"\t"+waterlogged+"\t"+WORLDS[w]+"\t"+p+"\tcached-two-arg\tnone\t"+cached+"\t"+JSON.toJson(level.calls)+"\t{}");calls++;
          if(!cached.equals(baseline)||!level.calls.isEmpty())throw new AssertionError("Cached shape/context disagreement:"+id);
          for(int c=0;c<CONTEXTS.length;c++)for(int route=0;route<2;route++){
            CollisionContext actual=context(c,item,armor);Spy spy=new Spy(actual);level.clearTrace();
            String observed=boxes(route==0?state.getCollisionShape(level,pos,spy):spy.getCollisionShape(state,level,pos));
            out.println(id+"\t"+name+"\t"+type+"\t"+waterlogged+"\t"+WORLDS[w]+"\t"+p+"\t"+(route==0?"explicit-state":"context-dispatch")+"\t"+CONTEXTS[c]+"\t"+observed+"\t"+JSON.toJson(level.calls)+"\t"+JSON.toJson(spy.reads));calls++;
            Map<String,Integer> expected=route==0?Map.of():Map.of("getCollisionShape",1);
            if(!observed.equals(baseline)||!level.calls.isEmpty()||!spy.reads.equals(expected))throw new AssertionError("Actual shape/context disagreement:"+id+":"+CONTEXTS[c]+":"+route);
          }
        }
      }
      if(out.checkError())throw new IOException("Reference output failed");
    }
    var meta=new TreeMap<String,Object>();meta.put("version",SharedConstants.getCurrentVersion().id());meta.put("registered_states",Block.BLOCK_STATE_REGISTRY.size());meta.put("receivers",receivers);meta.put("states",records);meta.put("collision_calls",calls);
    meta.put("worlds",Arrays.asList(WORLDS));meta.put("contexts",Arrays.asList(CONTEXTS));meta.put("positions",Arrays.stream(POSITIONS).map(p->List.of(p.getX(),p.getY(),p.getZ())).toList());
    meta.put("context_receivers",contextReceivers);meta.put("baseline_calls",records.size());meta.put("normally_constructed_entities",List.of(item.getClass().getName(),armor.getClass().getName()));meta.put("entity_constructor_world_calls",constructorReads);
    Files.writeString(Path.of(args[1]),JSON.toJson(meta));
  }
}
'''

def sha(data):return hashlib.sha256(data).hexdigest()

def measure():
    WORK.mkdir(parents=True,exist_ok=True);jars,release=verified_classpath();cp=':'.join(map(str,jars))
    files=[]
    for name,source in [('ReferenceMovementProbe',MOVE_SOURCE),('ReferenceDirectMovementProbe',DIRECT_SOURCE),('ReferenceSlabCollisionProbe',SOURCE)]:
        p=WORK/(name+'.java');p.write_text(source);files.append(p)
    compile_result=subprocess.run([str(JAVA.parent/'javac'),'-cp',cp,'-d',str(WORK),*map(str,files)],capture_output=True,timeout=60)
    if compile_result.returncode:raise RuntimeError('Slab Java compilation failed:'+compile_(result.stdout+result.stderr).decode()[-3000:])
    runs=[]
    for i in range(2):
        out=WORK/f'actual-{i}.tsv';meta=WORK/f'receivers-{i}.json'
        result=subprocess.run([str(JAVA),'-cp',str(WORK)+':'+cp,'ReferenceSlabCollisionProbe',str(out),str(meta)],capture_output=True,timeout=120)
        (WORK/f'run-{i}.log').write_bytes(result.stdout+result.stderr)
        if result.returncode:raise RuntimeError('Slab Java receiver failed:'+(result.stdout+result.stderr).decode()[-3000:])
        runs.append({'table':fingerprint(out),'receivers':fingerprint(meta)})
    if (WORK/'actual-0.tsv').read_bytes()!=(WORK/'actual-1.tsv').read_bytes() or (WORK/'receivers-0.json').read_bytes()!=(WORK/'receivers-1.json').read_bytes():raise ValueError('Actual Java repeated observations differ')
    return json.loads((WORK/'receivers-0.json').read_text()),runs,jars,release

def rows(path):
    with path.open() as stream:return list(csv.DictReader(stream,delimiter='\t'))

ZERO='0000000000000000';HALF='3fe0000000000000';ONE='3ff0000000000000'
SHAPES={'top':[[ZERO,HALF,ZERO,ONE,ONE,ONE]],'bottom':[[ZERO,ZERO,ZERO,ONE,HALF,ONE]],'double':[[ZERO,ZERO,ZERO,ONE,ONE,ONE]]}
BEHAVIOUR='net.minecraft.world.level.block.state.BlockBehaviour'
STATE=BEHAVIOUR+'$BlockStateBase'
SLAB='net.minecraft.world.level.block.SlabBlock'


def validate(meta,observations,identity):
    if meta['version']!='26.3' or meta['registered_states']!=35723 or len(meta['states'])!=606 or len(meta['receivers'])!=101:raise ValueError('Fresh actual registry/slab count mismatch')
    if identity!=registry_identity(OFFICIAL)[0]:raise ValueError('Registry identity mismatch')
    official=rows(OFFICIAL);byname={r['identifier']:r for r in official};expected={};entries=[];byid={}
    for name,receiver in meta['receivers'].items():
        block=byname[name]
        if receiver['class'] not in (SLAB,'net.minecraft.world.level.block.WeatheringCopperSlabBlock'):raise ValueError('Unexpected registered subclass')
        if receiver['method_owners']!={'getCollisionShape':BEHAVIOUR,'getShape':SLAB} or receiver['state_collision_context_owner']!=STATE or receiver['state_collision_cached_owner']!=STATE:raise ValueError('Actual receiver method override')
        if receiver['has_collision'] is not True or receiver['dynamic_shape'] is not False or receiver['has_collision_owner']!=BEHAVIOUR or receiver['has_collision_modifiers']!='protected final':raise ValueError('Stored guard mismatch')
        if receiver['protocol']!=int(block['block_protocol_id']) or receiver['default_state_id']!=int(block['default_state_id']) or int(block['state_count'])!=6:raise ValueError('Official block identity mismatch')
        properties=json.loads(block['ordered_properties_json'])
        if properties!=[{'name':'type','values':['top','bottom','double']},{'name':'waterlogged','values':['true','false']}]:raise ValueError('Official property schema/order mismatch')
        first=int(block['first_state_id'])
        for index,(kind,water) in enumerate((k,w) for k in ('top','bottom','double') for w in (True,False)):
            expected[first+index]=(name,kind,water)
    for record in meta['states']:
        sid=record['state_id']
        if type(sid) is not int or sid in byid or sid not in expected:raise ValueError('Slab state identity/duplication mismatch')
        if (record['identifier'],record['slab_type'],record['waterlogged'])!=expected[sid] or type(record['waterlogged']) is not bool:raise ValueError('Actual property disagreement')
        if record['cache_present'] is not True or record['offset'] is not False:raise ValueError('Cache/offset guard mismatch')
        if record['aabbs_f64_bits']!=SHAPES[record['slab_type']]:raise ValueError('Actual slab primitive box differs')
        byid[sid]=record;entries.append({'state_id':sid,'slab_type':record['slab_type'],'waterlogged':record['waterlogged']})
    if set(byid)!=set(expected) or [e['state_id'] for e in entries]!=sorted(byid):raise ValueError('Incomplete or unordered actual slab states')
    expected_contexts={'empty','position-low','position-high','fluid','item','armor-standing','armor-descending','placement-null'}
    if set(meta['contexts'])!=expected_contexts or meta['worlds']!=['empty','stone-neighbors','water-neighbors','throw-on-read'] or meta['positions']!=[[0,0,0],[7,11,-13],[-2147483648,2147483647,-17]]:raise ValueError('Actual context matrix changed')
    expected_receivers={c:{'class':('net.minecraft.world.phys.shapes.PositionCollisionContext' if c.startswith('position-') else 'net.minecraft.world.phys.shapes.EntityCollisionContext$Empty' if c in ('empty','fluid') else 'net.minecraft.world.phys.shapes.EntityCollisionContext'),'shape_owner':('net.minecraft.world.phys.shapes.PositionCollisionContext' if c.startswith('position-') else 'net.minecraft.world.phys.shapes.EntityCollisionContext')} for c in expected_contexts}
    if meta['context_receivers']!=expected_receivers:raise ValueError('Context collision dispatch receiver/owner mismatch')
    if meta['normally_constructed_entities']!=['net.minecraft.world.entity.item.ItemEntity','net.minecraft.world.entity.decoration.ArmorStand'] or meta['entity_constructor_world_calls']!={}:raise ValueError('Normal entity construction mismatch')
    if meta['collision_calls']!=123624 or meta['baseline_calls']!=606 or len(observations)!=123624:raise ValueError('Actual context collision count mismatch')
    seen=set();route_counts=collections.Counter()
    for r in observations:
        sid=int(r['state_id']);record=byid[sid]
        if (r['block_identifier'],r['slab_type'],r['waterlogged'])!=(record['identifier'],record['slab_type'],str(record['waterlogged']).lower()):raise ValueError('Matrix state/property identity mismatch')
        route=r['route'];ctx=r['context'];world=r['world'];pos=int(r['position'])
        if world not in meta['worlds'] or pos not in range(3):raise ValueError('Matrix world/position out of scope')
        if route=='cached-two-arg':
            if ctx!='none':raise ValueError('Cached route has artificial context')
            expected_reads={}
        elif route in ('explicit-state','context-dispatch'):
            if ctx not in expected_contexts:raise ValueError('Matrix missing actual context')
            expected_reads={} if route=='explicit-state' else {'getCollisionShape':1}
        else:raise ValueError('Unknown measured route')
        key=(sid,world,pos,route,ctx)
        if key in seen:raise ValueError('Duplicate receiver query')
        seen.add(key);route_counts[route]+=1
        if json.loads(r['aabbs_f64_bits'])!=record['aabbs_f64_bits'] or json.loads(r['world_reads'])!={} or json.loads(r['context_reads'])!=expected_reads:raise ValueError('Actual collision/context read disagreement')
    if dict(route_counts)!={'cached-two-arg':7272,'explicit-state':58176,'context-dispatch':58176}:raise ValueError('Incomplete actual route coverage')
    prior=json.loads((ROOT/'reference/block_physics.json').read_text())
    if fingerprint(ROOT/'generated/reference_block_physics.tsv')['sha256']!=prior['table']['sha256']:raise ValueError('Existing independent observations corrupted')
    old=rows(ROOT/'generated/reference_block_physics.tsv')
    for sid,record in byid.items():
        r=old[sid]
        if int(r['state_id'])!=sid or r['block_identifier']!=record['identifier'] or prior['shape_dictionary'][r['collision_empty_origin_shape_id']]['aabbs_f64_bits']!=record['aabbs_f64_bits']:raise ValueError('Existing empty-context collision shape disagreement')
    table=('BendSlabCollision\t1\t26.3\t'+identity+'\t35723\t606\nstate_id\tslab_type\twaterlogged\n'+''.join(str(e['state_id'])+'\t'+e['slab_type']+'\t'+('1' if e['waterlogged'] else '0')+'\n' for e in entries)).encode()
    return entries,table,dict(route_counts)


CLASS_NAMES=[SLAB,SLAB+'$1','net.minecraft.world.level.block.WeatheringCopperSlabBlock',BEHAVIOUR,STATE,STATE+'$Cache','net.minecraft.world.level.block.state.BlockState','net.minecraft.world.level.block.state.properties.SlabType','net.minecraft.world.level.block.Block','net.minecraft.world.phys.shapes.Shapes','net.minecraft.world.phys.shapes.VoxelShape','net.minecraft.world.phys.shapes.CollisionContext','net.minecraft.world.phys.shapes.EntityCollisionContext','net.minecraft.world.phys.shapes.EntityCollisionContext$Empty','net.minecraft.world.phys.shapes.PositionCollisionContext','net.minecraft.world.entity.item.ItemEntity','net.minecraft.world.entity.decoration.ArmorStand']


def inspect_classes(jars):
    classes={};bytecode={}
    with zipfile.ZipFile(jars[0]) as archive:
        for name in CLASS_NAMES:
            classes[name]=sha(archive.read(name.replace('.','/')+'.class'))
            result=subprocess.run([str(JAVA.parent/'javap'),'-cp',':'.join(map(str,jars)),'-c','-p',name],check=True,capture_output=True,text=True,timeout=30)
            text=result.stdout;(WORK/(name.rsplit('.',1)[-1]+'.javap')).write_text(text);bytecode[name]=text
    def body(owner,declaration):
        text=bytecode[owner];start=text.index('  '+declaration+';')
        end=re.search(r'\n  (?:(?:public|protected|private|static) |\})',text[start+3:])
        return text[start:] if not end else text[start:start+3+end.start()]
    specs=[(SLAB,'protected net.minecraft.world.phys.shapes.VoxelShape getShape(net.minecraft.world.level.block.state.BlockState, net.minecraft.world.level.BlockGetter, net.minecraft.core.BlockPos, net.minecraft.world.phys.shapes.CollisionContext)'),
           (BEHAVIOUR,'protected net.minecraft.world.phys.shapes.VoxelShape getCollisionShape(net.minecraft.world.level.block.state.BlockState, net.minecraft.world.level.BlockGetter, net.minecraft.core.BlockPos, net.minecraft.world.phys.shapes.CollisionContext)'),
           (STATE,'public net.minecraft.world.phys.shapes.VoxelShape getShape(net.minecraft.world.level.BlockGetter, net.minecraft.core.BlockPos)'),
           (STATE,'public net.minecraft.world.phys.shapes.VoxelShape getShape(net.minecraft.world.level.BlockGetter, net.minecraft.core.BlockPos, net.minecraft.world.phys.shapes.CollisionContext)'),
           (STATE,'public net.minecraft.world.phys.shapes.VoxelShape getCollisionShape(net.minecraft.world.level.BlockGetter, net.minecraft.core.BlockPos)'),
           (STATE,'public net.minecraft.world.phys.shapes.VoxelShape getCollisionShape(net.minecraft.world.level.BlockGetter, net.minecraft.core.BlockPos, net.minecraft.world.phys.shapes.CollisionContext)'),
           (STATE,'public void initCache()'),
           (STATE+'$Cache','private net.minecraft.world.level.block.state.BlockBehaviour$BlockStateBase$Cache(net.minecraft.world.level.block.state.BlockState)'),
           ('net.minecraft.world.phys.shapes.EntityCollisionContext','public net.minecraft.world.phys.shapes.VoxelShape getCollisionShape(net.minecraft.world.level.block.state.BlockState, net.minecraft.world.level.CollisionGetter, net.minecraft.core.BlockPos)'),
           ('net.minecraft.world.phys.shapes.PositionCollisionContext','public net.minecraft.world.phys.shapes.VoxelShape getCollisionShape(net.minecraft.world.level.block.state.BlockState, net.minecraft.world.level.CollisionGetter, net.minecraft.core.BlockPos)')]
    methods={}
    for owner,decl in specs:
        text=body(owner,decl);methods[owner+'#'+decl]={'owner':owner,'declaration':decl,'bytecode_text_sha256':sha(text.encode()),'operations':re.findall(r'^\s+\d+: (\w+)',text,re.M)}
    slab=body(*specs[0]);collision=body(*specs[1]);cached=body(*specs[4]);cache=body(*specs[7])
    if re.findall(r'// Method ([^\n]+)',slab)!=['net/minecraft/world/level/block/state/BlockState.getValue:(Lnet/minecraft/world/level/block/state/properties/Property;)Ljava/lang/Comparable;','net/minecraft/world/level/block/state/properties/SlabType.ordinal:()I','java/lang/MatchException."<init>":(Ljava/lang/String;Ljava/lang/Throwable;)V','net/minecraft/world/phys/shapes/Shapes.block:()Lnet/minecraft/world/phys/shapes/VoxelShape;'] or any('aload_'+str(i) in slab for i in (0,2,3,4)):raise ValueError('Slab shape unexpectedly reads world/context or invokes another method')
    if 'Field hasCollision:Z' not in collision or '10: invokevirtual' not in collision or 'aload         4' in collision or 'Shapes.empty' not in collision:raise ValueError('Collision guard/context chain changed')
    if 'Field cache:' not in cached or 'Field net/minecraft/world/level/block/state/BlockBehaviour$BlockStateBase$Cache.collisionShape:' not in cached or 'CollisionContext.empty' not in cached:raise ValueError('Cached collision path changed')
    if 'EmptyBlockGetter.INSTANCE' not in cache or 'BlockPos.ZERO' not in cache or 'CollisionContext.empty' not in cache or 'Block.getCollisionShape:' not in cache:raise ValueError('Cache construction collision path changed')
    return classes,{k:sha(v.encode()) for k,v in bytecode.items()},methods


def output(meta,runs,jars,release,write=True):
    for name,source in [('ReferenceMovementProbe',MOVE_SOURCE),('ReferenceDirectMovementProbe',DIRECT_SOURCE),('ReferenceSlabCollisionProbe',SOURCE)]:
        if (WORK/(name+'.java')).read_text()!=source:raise ValueError('Executed Java source generation changed')
    if len(runs)!=2 or (WORK/'actual-0.tsv').read_bytes()!=(WORK/'actual-1.tsv').read_bytes() or (WORK/'receivers-0.json').read_bytes()!=(WORK/'receivers-1.json').read_bytes():raise ValueError('Actual repeated receiver mismatch')
    identity,count,registry=registry_identity(OFFICIAL)
    entries,data,route_counts=validate(meta,rows(WORK/'actual-0.tsv'),identity)
    classes,javap,methods=inspect_classes(jars)
    if write:TABLE.write_bytes(data)
    elif TABLE.read_bytes()!=data:raise ValueError('Derived table changed')
    receivers={name:{**r,'first_state_id':int(next(x['first_state_id'] for x in rows(OFFICIAL) if x['identifier']==name)),'state_count':6} for name,r in meta['receivers'].items()}
    info={'pin':'26.3','reference_only':True,'registry_identity':identity,'registry':registry,'registered_states':35723,'registered_slab_blocks':101,'slab_states':606,'class_counts':dict(collections.Counter(r['class'] for r in receivers.values())),'slab_entries':entries,'shapes_by_type':SHAPES,'receivers':receivers,'source_sha256':sha(SOURCE.encode()),'helper_sources':{'ReferenceMovementProbe':sha(MOVE_SOURCE.encode()),'ReferenceDirectMovementProbe':sha(DIRECT_SOURCE.encode())},'tool_sha256':sha(Path(__file__).read_bytes()),'java_runtime':fingerprint(JAVA),'java_compiler':fingerprint(JAVA.parent/'javac'),'server_sha256':fingerprint(jars[0])['sha256'],'classpath_count':len(jars),'classpath_manifest_sha256':sha(canonical([fingerprint(p) for p in jars])),'class_sha256':classes,'javap_text_sha256':javap,'methods':methods,'two_byte_identical_java_runs':runs,'derived_table':fingerprint(TABLE),'receiver_manifest_sha256':sha(canonical(meta['receivers'])),'context_matrix':{'worlds':meta['worlds'],'positions':meta['positions'],'contexts':meta['contexts'],'context_receivers':meta['context_receivers'],'normally_constructed_entities':meta['normally_constructed_entities'],'constructor_world_calls':meta['entity_constructor_world_calls'],'calls_per_run':123624,'baseline_calls_per_run':606,'route_counts':route_counts,'zero_world_reads':True,'explicit_context_property_reads':0,'dispatch_wrapper_calls_per_invocation':1},'guards':{'all_hasCollision_true':True,'stored_hasCollision':'protected final','all_dynamicShape_false':True,'all_cache_present':True,'all_offset_false':True,'registered_shape_owner':SLAB,'registered_collision_owner':BEHAVIOUR,'shape_input_read':'TYPE only','shape_return':'static SHAPE_TOP/SHAPE_BOTTOM or Shapes.block','cached_two_arg':'actual initialized cache.collisionShape; fallback explicit empty context if cache absent','explicit_context':'BlockBehaviour hasCollision guard then two-arg BlockState.getShape discards caller context and supplies CollisionContext.empty; SlabBlock.getShape reads TYPE only'},'existing_empty_context_observations_equal':True,'scope':['Registered SlabBlock instances, including actual WeatheringCopperSlabBlock subclass receivers, for these collision getter routes only.','One exact unshifted collision AABB by actual TYPE. WATERLOGGED is retained metadata and does not affect this getter.','Method-body and actual-receiver guard evidence establishes static collision values for these pinned receivers; context sampling alone is not generalized.','No fluid-union, ray outline, step, support, friction, Entity movement, block updates, placement or world collision iteration claim.']}
    if write:
        write_json(REFERENCE,info)
        write_json(ROOT/'evidence/slab-collision-reference.json',{k:v for k,v in info.items() if k not in ('slab_entries','receivers')})
    return info


def verify_existing():
    info=json.loads(REFERENCE.read_text());jars,_=verified_classpath();meta=json.loads((WORK/'receivers-0.json').read_text())
    if info['source_sha256']!=sha(SOURCE.encode()) or info['helper_sources']!={'ReferenceMovementProbe':sha(MOVE_SOURCE.encode()),'ReferenceDirectMovementProbe':sha(DIRECT_SOURCE.encode())} or info['tool_sha256']!=sha(Path(__file__).read_bytes()) or info['java_runtime']!=fingerprint(JAVA) or info['java_compiler']!=fingerprint(JAVA.parent/'javac'):raise ValueError('Reference extraction generation changed')
    if info['classpath_manifest_sha256']!=sha(canonical([fingerprint(p) for p in jars])):raise ValueError('Official artifacts changed')
    classes,javap,methods=inspect_classes(jars)
    if (info['class_sha256'],info['javap_text_sha256'],info['methods'])!=(classes,javap,methods):raise ValueError('Actual method/class evidence changed')
    identity,count,_=registry_identity(OFFICIAL);entries,data,routes=validate(meta,rows(WORK/'actual-0.tsv'),identity)
    if info['registry_identity']!=identity or info['slab_entries']!=entries or info['shapes_by_type']!=SHAPES or info['receiver_manifest_sha256']!=sha(canonical(meta['receivers'])) or info['derived_table']!=fingerprint(TABLE) or TABLE.read_bytes()!=data or info['context_matrix']['route_counts']!=routes:raise ValueError('Reference catalog/table corrupted')
    for i,run in enumerate(info['two_byte_identical_java_runs']):
        if run!={'table':fingerprint(WORK/f'actual-{i}.tsv'),'receivers':fingerprint(WORK/f'receivers-{i}.json')}:raise ValueError('Actual raw observation corrupted')
    if (WORK/'actual-0.tsv').read_bytes()!=(WORK/'actual-1.tsv').read_bytes() or (WORK/'receivers-0.json').read_bytes()!=(WORK/'receivers-1.json').read_bytes():raise ValueError('Actual repeated receiver mismatch')
    rebuilt=output(meta,info['two_byte_identical_java_runs'],jars,None,write=False)
    if info!=rebuilt:raise ValueError('Reference summary/provenance corrupted')
    return info


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--measure-only',action='store_true');parser.add_argument('--verify-existing',action='store_true');parser.add_argument('--finish-measurement',action='store_true');args=parser.parse_args()
    if args.verify_existing:info=verify_existing()
    else:
        if args.finish_measurement:
            jars,release=verified_classpath();meta=json.loads((WORK/'receivers-0.json').read_text());runs=[{'table':fingerprint(WORK/f'actual-{i}.tsv'),'receivers':fingerprint(WORK/f'receivers-{i}.json')} for i in range(2)]
        else:meta,runs,jars,release=measure()
        if args.measure_only:
            print(json.dumps({'status':'actual-java-measured','registered_slab_blocks':len(meta['receivers']),'slab_states':len(meta['states']),'calls':meta['collision_calls'],'runs':runs}));return
        info=output(meta,runs,jars,release)
    print(json.dumps({'status':'passed','blocks':info['registered_slab_blocks'],'states':info['slab_states'],'calls':info['context_matrix']['calls_per_run'],'table':info['derived_table']}))

if __name__=='__main__':main()
