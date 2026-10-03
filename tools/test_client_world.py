#!/usr/bin/env python3
"""Owned finite-world integration against pinned Java BlockCollisions.

Java is a reference extraction instrument only. Bend executes all world reads,
collision enumeration, movement, dispatch, and render snapshot construction.
"""
from __future__ import annotations
import argparse, copy, csv, hashlib, json, math, os, pathlib, random, statistics, struct, subprocess, time
from reference_inventory import ROOT, JAVA, fingerprint
from reference_block_probe import verified_classpath
from reference_movement_probe import SOURCE as MOVEMENT_SOURCE, DIRECT_SOURCE as DIRECT_MOVEMENT_SOURCE

BEND = pathlib.Path.home()/'.bend/bin/bend'
BINARY = ROOT/'build/client-world-tests'
SEED = 263_1003_47
SOURCE = r'''
import java.io.*;
import java.nio.file.*;
import java.lang.reflect.*;
import java.util.*;
import com.google.gson.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;
import net.minecraft.world.entity.EntityDimensions;
import net.minecraft.world.level.*;
import net.minecraft.world.level.block.*;
import net.minecraft.world.level.block.state.*;
import net.minecraft.world.phys.*;
import net.minecraft.world.phys.shapes.*;
import net.minecraft.util.Mth;

public class ClientWorldProbe {
  static final Gson JSON=new Gson();
  static BlockState state(BlockPos p) {
    int x=p.getX(),y=p.getY(),z=p.getZ();
    if(y==0&&x>=-3&&x<=2&&z>=-3&&z<=2)return (x==2?Blocks.DIRT:Blocks.STONE).defaultBlockState();
    if(x==1&&y==1&&z==1)return Blocks.DIRT.defaultBlockState();
    if(x==2&&z==2&&(y==1||y==2))return Blocks.OAK_PLANKS.defaultBlockState();
    return Blocks.AIR.defaultBlockState();
  }
  static final BlockGetter GETTER=(BlockGetter)Proxy.newProxyInstance(ClientWorldProbe.class.getClassLoader(),new Class[]{BlockGetter.class},(p,m,a)->{
    if(m.getName().equals("getBlockState"))return state((BlockPos)a[0]);
    if(m.getName().equals("getFluidState"))return Blocks.AIR.defaultBlockState().getFluidState();
    if(m.getName().equals("getBlockEntity"))return null;
    if(m.getName().equals("getHeight"))return 384;
    if(m.getName().equals("getMinY"))return -64;
    throw new UnsupportedOperationException(m.toString());
  });
  static final CollisionGetter WORLD=(CollisionGetter)Proxy.newProxyInstance(ClientWorldProbe.class.getClassLoader(),new Class[]{CollisionGetter.class},(p,m,a)->{
    if(m.getName().equals("getChunkForCollisions"))return GETTER;
    if(m.getName().equals("getBlockState"))return state((BlockPos)a[0]);
    if(m.getName().equals("getFluidState"))return Blocks.AIR.defaultBlockState().getFluidState();
    if(m.getName().equals("getBlockEntity"))return null;
    throw new UnsupportedOperationException(m.toString());
  });
  static List<VoxelShape> shapes(AABB b) {
    List<VoxelShape> result=new ArrayList<>();
    BlockCollisions<VoxelShape> it=new BlockCollisions<>(WORLD,CollisionContext.empty(),b,false,(p,s)->s);
    while(it.hasNext())result.add(it.next());
    return result;
  }
  static JsonArray rawShapes(List<VoxelShape> shapes) {
    JsonArray a=new JsonArray();
    for(VoxelShape s:shapes) { AABB b=s.bounds();JsonObject v=new JsonObject();v.addProperty("kind","raw_array_box");v.add("box",JSON.toJsonTree(ReferenceMovementProbe.boxBits(b)));a.add(v); }
    return a;
  }
  static Map<String,Object> query(JsonObject c) {
    AABB b=ReferenceMovementProbe.box(c.getAsJsonArray("box"));
    List<List<String>> points=new ArrayList<>();
    BlockCollisions<List<String>> it=new BlockCollisions<>(WORLD,CollisionContext.empty(),b,false,(p,s)->List.of(ReferenceMovementProbe.bits((double)p.getX()),ReferenceMovementProbe.bits((double)p.getY()),ReferenceMovementProbe.bits((double)p.getZ())));
    while(it.hasNext())points.add(it.next());
    int lx=Mth.floor(b.minX-1e-7)-1,ly=Mth.floor(b.minY-1e-7)-1,lz=Mth.floor(b.minZ-1e-7)-1;
    int hx=Mth.floor(b.maxX+1e-7)+1,hy=Mth.floor(b.maxY+1e-7)+1,hz=Mth.floor(b.maxZ+1e-7)+1;
    return Map.of("id",c.get("id").getAsString(),"points",points,"bounds",List.of(Integer.toUnsignedLong(lx),Integer.toUnsignedLong(ly),Integer.toUnsignedLong(lz),hx-lx+1,hy-ly+1,hz-lz+1));
  }
  static Map<String,Object> move(JsonObject c) throws Exception {
    JsonObject in=c.getAsJsonObject("input");
    Vec3 position=ReferenceMovementProbe.vector(in.getAsJsonArray("position")),request=ReferenceMovementProbe.vector(in.getAsJsonArray("requested"));
    float width=ReferenceMovementProbe.f(in.get("width_f32_bits")),height=ReferenceMovementProbe.f(in.get("height_f32_bits")),maximum=ReferenceMovementProbe.f(in.get("maximum_f32_bits"));
    AABB box=EntityDimensions.fixed(width,height).makeBoundingBox(position);
    List<VoxelShape> initial=request.lengthSqr()==0.0?List.of():shapes(box.expandTowards(request));
    Vec3 baseline=request.lengthSqr()==0.0?request:ReferenceMovementProbe.collide(request,box,initial);
    boolean landed=request.y!=baseline.y&&request.y<0;
    boolean eligible=maximum>0&&(in.get("grounded").getAsBoolean()||landed)&&(request.x!=baseline.x||request.z!=baseline.z);
    AABB adjusted=landed?box.move(0,baseline.y,0):box;
    AABB query=adjusted.expandTowards(request.x,(double)maximum,request.z);
    if(!landed)query=query.expandTowards(0,(double)-1e-5f,0);
    List<VoxelShape> step=eligible?shapes(query):List.of();
    in.add("box",JSON.toJsonTree(ReferenceMovementProbe.boxBits(box)));in.add("initial",rawShapes(initial));in.add("step",rawShapes(step));
    Map<String,Object> observed=new TreeMap<>(ReferenceMovementProbe.observe(c));
    observed.put("initial_count",initial.size());observed.put("step_count",step.size());observed.put("step_query_used",eligible);
    observed.put("initial_shapes",rawShapes(initial));observed.put("step_shapes",rawShapes(step));
    return observed;
  }
  public static void main(String[]args)throws Exception {
    SharedConstants.tryDetectVersion();Bootstrap.bootStrap();
    for(Block b:List.of(Blocks.AIR,Blocks.STONE,Blocks.DIRT,Blocks.OAK_PLANKS))if(b.defaultBlockState().hasLargeCollisionShape())throw new AssertionError("unsupported large shape");
    try(BufferedReader r=Files.newBufferedReader(Path.of(args[0]));PrintWriter w=new PrintWriter(Files.newBufferedWriter(Path.of(args[1])))) {
      for(String line;(line=r.readLine())!=null;) { JsonObject c=JsonParser.parseString(line).getAsJsonObject();String op=c.get("operation").getAsString();w.println(JSON.toJson(op.equals("query")?query(c):op.equals("entity_move")?ReferenceDirectMovementProbe.observe(c):move(c))); }
    }
  }
}
'''

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def bits(v): return struct.pack('>d',v).hex()
def fbits(v): return struct.pack('>f',v).hex()
def words(v):
    n=int(v,16);return [str(n>>32),str(n&0xffffffff)]
def run(args,required=True,env=None):
    start=time.monotonic();r=subprocess.run(list(map(str,args)),cwd=ROOT,capture_output=True,text=True,env=env)
    result={'command':list(map(str,args[:4])),'exit_code':r.returncode,'seconds':round(time.monotonic()-start,6),'stdout':r.stdout,'stderr':r.stderr}
    if required and r.returncode: raise AssertionError(result)
    return result

def cases():
    rng=random.Random(SEED);queries=[];moves=[]
    for i in range(96):
        low=[rng.uniform(-3,2),rng.uniform(-.5,3),rng.uniform(-3,2)]
        high=[low[0]+rng.uniform(0,2),low[1]+rng.uniform(0,2),low[2]+rng.uniform(0,2)]
        queries.append({'id':f'query-random-{i}','operation':'query','box':list(map(bits,low+high))})
    for coord in [-3.,-2.,-1.,-0.,0.,1.,2.,3.]:
        for delta in [-1e-7,0.,1e-7]:
            b=[coord+delta,-.25,-2.,coord+1+delta,1.25,2.]
            queries.append({'id':f'query-boundary-{len(queries)}','operation':'query','box':list(map(bits,b))})
    for b in [[0.,0.,0.,0.,0.,0.],[-1.,-1.,-1.,0.,0.,0.],[0.,1.,0.,1.,2.,1.],[-3.,-.5,-3.,3.,3.,3.]]:
        queries.append({'id':f'query-special-{len(queries)}','operation':'query','box':list(map(bits,b))})
    def add(position,request,grounded=True,maximum=.6,width=.6,height=1.8,name=None):
        moves.append({'id':name or f'move-{len(moves)}','operation':'move','input':{'position':list(map(bits,position)),'requested':list(map(bits,request)),'velocity':list(map(bits,[0.,0.,0.])), 'grounded':grounded,'maximum_f32_bits':fbits(maximum),'previous_f32_bits':fbits(0.),'width_f32_bits':fbits(width),'height_f32_bits':fbits(height)}})
    for p,r in [([.5,1,-2.5],[0,-.5,0]),([.5,1,-2.5],[0,0,0]),([.5,1,-2.5],[0,0,3]),([1.5,1,-.5],[0,0,2]),([-2.5,1,-2.5],[-.5,-.1,-.5]),([.5,3,.5],[0,-3,0]),([1.5,1,.5],[0,0,1]),([1.5,1,.5],[1,0,1])]:add(p,r)
    for i in range(72):
        add([rng.uniform(-2.4,2.4),rng.uniform(.8,3),rng.uniform(-2.4,2.4)],[rng.uniform(-1,1),rng.uniform(-1,.5),rng.uniform(-1,1)],grounded=bool(i%2),maximum=[0.,.6,1.,1.2][i%4])
    for delta in [0.,5e-8,1e-7,2e-7,-5e-8,-1e-7,-2e-7]:
        add([1.5,1,.5],[0.,0.,delta],name=f'move-tiny-{len(moves)}')
    return queries,moves

def request(c):
    if c['operation']=='query':return '|'.join(['query',c['id'],*[p for v in c['box'] for p in words(v)]])
    x=c['input'];return '|'.join(['move',c['id'],*[p for v in x['position']+x['requested'] for p in words(v)],str(int(x['maximum_f32_bits'],16)),str(int(x['grounded'])),str(int(x['width_f32_bits'],16)),str(int(x['height_f32_bits'],16))])
def scalars(text):
    values=list(map(int,text.split(','))) if text else []
    assert len(values)%2==0
    return [f'{values[i]:08x}{values[i+1]:08x}' for i in range(0,len(values),2)]
def movement(line):
    f=line.split('|');assert f[1]=='movement',line
    flag=list(map(int,f[6].split(',')))
    return {'id':f[0],'expected':{'displacement':scalars(f[2]),'position':scalars(f[3]),'box':scalars(f[4]),'velocity':scalars(f[5]),'flags':list(map(bool,flag[:4]+flag[5:])),'stepped':bool(flag[4])}}
def snapshot(line):
    f=line.split('|');assert f[1]=='snapshot',line
    return {'tick':int(f[2]),'revision':int(f[3]),'count':int(f[4]),'camera':list(map(int,f[5].split(','))),'blocks':[list(map(int,x.split(','))) for x in f[6].split(';') if x]}

def main():
    p=argparse.ArgumentParser();p.add_argument('--skip-build',action='store_true');a=p.parse_args()
    checks=[run([BEND,source,'--check-only']) for source in ['src/client_world.bend','tests/client_world.bend']]
    builds=[]
    if not a.skip_build:builds=[run([BEND,'tests/client_world.bend','-o',BINARY])]
    jars,release=verified_classpath();cp=os.pathsep.join(map(str,jars));work=ROOT/'build/client-world-oracle';work.mkdir(parents=True,exist_ok=True)
    (work/'ClientWorldProbe.java').write_text(SOURCE);(work/'ReferenceMovementProbe.java').write_text(MOVEMENT_SOURCE);(work/'ReferenceDirectMovementProbe.java').write_text(DIRECT_MOVEMENT_SOURCE)
    java=[run([JAVA.parent/'javac','-cp',cp,'-d',work,work/'ClientWorldProbe.java',work/'ReferenceMovementProbe.java',work/'ReferenceDirectMovementProbe.java'])]
    queries,moves=cases();allcases=queries+moves
    blocks=[{'position':[x,0,z],'identifier':'minecraft:dirt' if x==2 else 'minecraft:stone'} for z in range(-3,3) for x in range(-3,3)]+[{'position':[1,1,1],'identifier':'minecraft:dirt'},{'position':[2,1,2],'identifier':'minecraft:oak_planks'},{'position':[2,2,2],'identifier':'minecraft:oak_planks'}]
    direct=[]
    for c in moves:
        d=copy.deepcopy(c);d['id']+='-direct';d['operation']='entity_move';d['input'].update(entity_type='minecraft:player',world_blocks=blocks);direct.append(d)
    inp=work/'input.jsonl';out=work/'output.jsonl';inp.write_text(''.join(json.dumps(c,separators=(',',':'))+'\n' for c in allcases+direct))
    java.append(run([JAVA,'-cp',str(work)+os.pathsep+cp,'ClientWorldProbe',inp,out]))
    expected={c['id']:c for c in map(json.loads,out.read_text().splitlines())};assert len(expected)==len(allcases)+len(direct)
    for c in moves:
        composed=expected[c['id']];actual=expected[c['id']+'-direct'];observed=actual['observation']['actual_input']
        assert composed['expected']==actual['expected'],(c,composed,actual)
        assert composed['initial_shapes']==observed['initial'] and composed['step_shapes']==observed['step'],(c,composed,actual)
        assert observed['position']==c['input']['position'] and observed['width_f32_bits']==c['input']['width_f32_bits'] and observed['height_f32_bits']==c['input']['height_f32_bits']
    batches=[];start=time.monotonic()
    for off in range(0,len(allcases),16):
        chunk=allcases[off:off+16];r=run([BINARY,'--gpu','off',*map(request,chunk)]);lines=r['stdout'].splitlines();assert len(lines)==len(chunk)
        batches.append({'offset':off,'count':len(chunk),'seconds':r['seconds']})
        for c,line in zip(chunk,lines,strict=True):
            f=line.split('|');assert f[0]==c['id']
            if c['operation']=='query':
                assert f[1]=='query',line
                points=[scalars(x) for x in f[2].split(';') if x]
                assert points==expected[c['id']]['points'],(c,line,expected[c['id']])
            else:
                got=movement(line);assert got['expected']==expected[c['id']]['expected'],(c,got,expected[c['id']])
    bounds_req=['|'.join(['bounds',c['id'],*[p for v in c['box'] for p in words(v)]]) for c in queries]
    for off in range(0,len(bounds_req),32):
        r=run([BINARY,'--gpu','off',*bounds_req[off:off+32]])
        for line in r['stdout'].splitlines():
            f=line.split('|');assert f[1]=='bounds' and list(map(int,f[2].split(',')))==expected[f[0]]['bounds'],line
    r=run([BINARY,'--gpu','off','snapshot|basic','new|empty','edit|changed','unsupported|bad','invalid-look|angle','invalid-region|region','invalid-move|move','move-camera|position','pulse|clock','fixture-again|duplicate','look|look','region|area','raw-edit|raw','palette|colors'])
    lines={line.split('|')[0]:line for line in r['stdout'].splitlines()}
    basic=snapshot(lines['basic-first']);assert basic==snapshot(lines['basic-second'])==snapshot(lines['basic-uncached'])
    assert (basic['tick'],basic['revision'],basic['count'])==(1,47,39)
    assert len({tuple(b[:3]) for b in basic['blocks']})==39
    for name in ['angle-kept','region-kept','move-kept']:assert snapshot(lines[name])==basic
    assert 'invalid-camera-angles' in lines['angle-look'] and 'invalid-region-bounds' in lines['region-region'] and 'invalid-movement' in lines['move-move']
    assert lines['empty-new'].endswith('|done') and '|error|missing-section:' in lines['empty-missing'] and '|movement|' in lines['empty-stationary'] and '|error|missing-section:' in lines['empty-nonzero']
    before=snapshot(lines['changed-before']);after=snapshot(lines['changed-after']);assert before==basic
    assert (after['tick'],after['revision'],after['count'])==(2,48,40) and [0,0x3f800000,0,15,2] in after['blocks']
    assert '|error|unsupported-block-state:' in lines['bad-bad'];repaired=snapshot(lines['bad-repaired']);assert (repaired['tick'],repaired['revision'],repaired['count'])==(3,49,40)
    moved=snapshot(lines['position-camera']);assert moved['blocks']==basic['blocks'] and moved['tick']==1 and moved['revision']==47
    assert moved['camera']==[0x3f400000,*basic['camera'][1:]]
    assert snapshot(lines['clock-paused'])==basic
    running=snapshot(lines['clock-running']);assert running==dict(basic,tick=2)
    assert '|error|fixture-requires-fresh-empty-world' in lines['duplicate-reject'] and snapshot(lines['duplicate-kept'])==basic
    for a,b in [('changed-after','changed-uncached'),('bad-repaired','bad-uncached'),('position-camera','position-uncached'),('clock-running','clock-uncached'),('look-after','look-uncached'),('area-after','area-uncached'),('raw-after','raw-uncached'),('colors-after','colors-uncached')]:assert snapshot(lines[a])==snapshot(lines[b]),(a,b)
    looked=snapshot(lines['look-after']);assert looked['blocks']==basic['blocks'] and looked['camera']==[*basic['camera'][:3],0x3f800000,0xbe99999a]
    area=snapshot(lines['area-after']);assert area['count']==17 and area['tick']==1 and area['revision']==47 and snapshot(lines['area-restored'])==basic
    raw=snapshot(lines['raw-after']);assert raw['count']==40 and raw['revision']==47 and raw['tick']==1 and [0,0x3f800000,0,15,2] in raw['blocks']
    colors=snapshot(lines['colors-after']);assert colors['count']==39 and colors['revision']==47 and {(b[3],b[4]) for b in colors['blocks']}=={(1,1),(10,0),(15,2)}
    # Resolve palette names from a valid different registry order. No state ID is
    # hardcoded by the bridge; the fixture material mapping remains unchanged.
    custom=work/'palette.tsv';names=['minecraft:oak_planks','minecraft:stone','minecraft:air','minecraft:dirt']
    custom.write_text('block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json\n'+''.join(f'{i}\t{name}\t{i}\t1\t{i}\t[]\n' for i,name in enumerate(names)))
    env=os.environ.copy();env['MC_BLOCK_REGISTRY']=str(custom)
    rr=run([BINARY,'--gpu','off','snapshot|remapped'],env=env);remap=snapshot(rr['stdout'].splitlines()[0])
    assert (remap['tick'],remap['revision'],remap['count'])==(1,47,39)
    assert {tuple(b[3:]) for b in remap['blocks']}=={(1,0),(3,1),(0,2)}
    # Bounds reject NaN, reversed/huge extents, and ±I32 padding overflow.
    invalid=[[math.nan,0,0,1,1,1],[2,0,0,1,1,1],[-20,0,0,20,1,1],[-2147483648.,0,0,-2147483647.,1,1],[2147483646.,0,0,2147483647.,1,1]]
    req=['|'.join(['bounds',f'invalid-{i}',*[p for v in map(bits,b) for p in words(v)]]) for i,b in enumerate(invalid)]
    rbad=run([BINARY,'--gpu','off',*req]);assert all('|error|' in line for line in rbad['stdout'].splitlines()) and len(rbad['stdout'].splitlines())==len(invalid)
    sources=['src/client_world.bend','tests/client_world.bend','tools/test_client_world.py','src/movement.bend','src/f64.bend','src/core.bend','src/game.bend','src/registry.bend','src/client_render.bend','docs/CLIENT_WORLD.md']
    noop=[];bench=[]
    for i in range(3):
        noop.append(run([BINARY,'--gpu','off',f'noop|noop-{i}'])['seconds'])
        rb=run([BINARY,'--gpu','off',f'benchmark|benchmark-{i}']);assert rb['stdout'].strip()==f'benchmark-{i}|count|390000';bench.append(rb['seconds'])
    performance={'repetitions_per_process':10000,'processes':3,'noop_seconds':noop,'snapshot_loop_seconds':bench,'estimated_snapshot_seconds':max(0,statistics.median(bench)-statistics.median(noop))/10000,'unisolated_concurrent_host':True,'scope':'384 checked world cells,39 render blocks; startup/registry/fixture median subtracted; not a Minecraft benchmark'}
    evidence={'schema_version':1,'status':'passed','pin':'26.3','seed':SEED,'query_oracle_cases':len(queries),'movement_oracle_cases':len(moves),'actual_entity_move_cases':len(direct),'query_bounds_cases':len(queries),'bounds_rejections':len(invalid),'integration_groups':14,'dynamic_palette_registry':True,'checked_fixture_mutations':47,'fixture_blocks':39,'checks':checks,'builds':builds,'java_build_and_run':java,'native_batches':batches,'native_seconds':round(time.monotonic()-start,6),'snapshot_benchmark':performance,'snapshot_cache':{'key':['revision','full-region-bounds','palette'],'cached_uncached_comparison_groups':9,'raw_write_invalidation_tested':True,'baseline_evidence':'client-world-snapshot-baseline.json','baseline_estimated_snapshot_seconds':json.loads((ROOT/'evidence/client-world-snapshot-baseline.json').read_text())['snapshot_benchmark']['estimated_snapshot_seconds'],'laws':['cache_hit_returns_exact_blocks','cache_miss_rejects_cached_blocks'],'ordinary_laws_checked':True,'whole_module_kernel_verified':False},'sources_sha256':{x:sha(ROOT/x) for x in sources if (ROOT/x).exists()},'binary_sha256':sha(BINARY),'java_source_sha256':hashlib.sha256(SOURCE.encode()).hexdigest(),'movement_reference_source_sha256':hashlib.sha256((MOVEMENT_SOURCE+DIRECT_MOVEMENT_SOURCE).encode()).hexdigest(),'java_input_sha256':sha(inp),'java_output_sha256':sha(out),'pinned_java_inputs':[fingerprint(x) for x in jars],'release':release,'actual_java_block_collisions_executed':True,'actual_full_entity_move_executed':True,'confidence':{'block_query_and_order':'high','observed_bounded_transition':'high','general_full_entity_move_parity':'unknown'},'scope':['sole owned Game.Engine retained through snapshots, dispatch, and movement','air/stone/dirt/oak_planks finite static full-cube scene','actual Java BlockCollisions traversal and full-cube intersection','actual untouched Entity.move on the same finite scene and narrow generic entity context','binary64 collision and render-only binary32 narrowing'],'unsupported':['terrain generation','complete player travel and input ticks','entity collisions and world border','context-dependent or multi-cell shapes','all block models/materials','general full Entity.move runtime parity','complete Minecraft client']}
    (ROOT/'evidence/client-world-verification.json').write_text(json.dumps(evidence,indent=2,sort_keys=True)+'\n')
    print(json.dumps({k:evidence[k] for k in ['status','query_oracle_cases','movement_oracle_cases','integration_groups','confidence']},indent=2))

if __name__=='__main__':main()
