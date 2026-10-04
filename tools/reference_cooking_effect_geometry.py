#!/usr/bin/env python3
"""Actual pinned XP placement collision receivers; no host placement simulation."""
from __future__ import annotations
import hashlib,json,struct,subprocess,time
from reference_inventory import ROOT,JAVA,canonical,fingerprint
from reference_player_inventory_probe import verified_classpath
from reference_movement_probe import SOURCE as MOVE_SOURCE,DIRECT_SOURCE
WORK=ROOT/'build/cooking-effect-geometry-reference'
SOURCE=r'''import java.nio.file.*;import java.lang.reflect.*;import java.util.*;import java.security.*;
import com.google.gson.*;import net.minecraft.SharedConstants;import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;import net.minecraft.world.entity.*;import net.minecraft.world.level.*;
import net.minecraft.world.level.block.*;import net.minecraft.world.level.block.state.*;
import net.minecraft.world.phys.*;import net.minecraft.world.phys.shapes.*;
class ReferenceCookingEffectGeometry {
 static final Gson JSON=new Gson();static Field SHAPE;
 static double value(JsonElement x){return Double.longBitsToDouble(Long.parseUnsignedLong(x.getAsString(),16));}
 static String bits(double x){return String.format(Locale.ROOT,"%016x",Double.doubleToRawLongBits(x));}
 static Object vector(Vec3 v){return List.of(bits(v.x),bits(v.y),bits(v.z));}
 static Object box(AABB b){return List.of(bits(b.minX),bits(b.minY),bits(b.minZ),bits(b.maxX),bits(b.maxY),bits(b.maxZ));}
 static AABB aabb(JsonArray a){return new AABB(value(a.get(0)),value(a.get(1)),value(a.get(2)),value(a.get(3)),value(a.get(4)),value(a.get(5)));}
 static Object grid(VoxelShape s)throws Exception{
  DiscreteVoxelShape d=(DiscreteVoxelShape)SHAPE.get(s);var axes=new ArrayList<Object>();
  for(Direction.Axis axis:Direction.Axis.values()){var c=s.getCoords(axis);var values=new ArrayList<String>();for(double v:c)values.add(bits(v));axes.add(Map.of("coords",values,"cube",c.getClass().getSimpleName().equals("CubePointRange")));}
  var cells=new ArrayList<Object>();for(int y=0;y<d.getYSize();y++)for(int x=0;x<d.getXSize();x++)for(int z=0;z<d.getZSize();z++)if(d.isFull(x,y,z))cells.add(List.of(x,y,z));
  return Map.of("axes",axes,"cells",cells,"boxes",s.toAabbs().stream().map(ReferenceCookingEffectGeometry::box).toList());
 }
 static class World extends ReferenceDirectMovementProbe.FixtureLevel {
  final List<VoxelShape> entityShapes=new ArrayList<>();final List<Object> callsGeometry=new ArrayList<>();
  public Iterable<VoxelShape> getBlockCollisions(Entity e,AABB b){
   var out=new ArrayList<VoxelShape>();var iterator=new BlockCollisions<VoxelShape>(this,e,b,false,(p,s)->s);while(iterator.hasNext())out.add(iterator.next());
   callsGeometry.add(Map.of("box",box(b),"entity_null",e==null,"boxes",out.stream().flatMap(s->s.toAabbs().stream()).map(ReferenceCookingEffectGeometry::box).toList()));return out;
  }
  public List<VoxelShape> getEntityCollisions(Entity e,AABB b){return entityShapes.stream().filter(s->Shapes.joinIsNotEmpty(s,Shapes.create(b),BooleanOp.AND)).toList();}
  public net.minecraft.world.flag.FeatureFlagSet enabledFeatures(){return net.minecraft.world.flag.FeatureFlags.DEFAULT_FLAGS;}
 }
 public static void main(String[] args)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();ReferenceDirectMovementProbe.initialize();
  SHAPE=VoxelShape.class.getDeclaredField("shape");SHAPE.setAccessible(true);
  var input=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonArray();var results=new ArrayList<Object>();
  for(JsonElement e:input){JsonObject in=e.getAsJsonObject();World level=new World();
   if(in.has("border")){level.border.setCenter(0,0);level.border.setSize(in.get("border").getAsDouble());}
   for(JsonElement w:in.getAsJsonArray("writes")){var r=w.getAsJsonObject();var p=r.getAsJsonArray("position");level.blocks.put(new BlockPos(p.get(0).getAsInt(),p.get(1).getAsInt(),p.get(2).getAsInt()),Block.stateById(r.get("state").getAsInt()));}
   for(JsonElement b:in.getAsJsonArray("entities"))level.entityShapes.add(Shapes.create(aabb(b.getAsJsonArray())));
   var p=in.getAsJsonArray("point");Vec3 point=new Vec3(value(p.get(0)),value(p.get(1)),value(p.get(2)));
   #NORMAL#
   AABB body=new AABB(point.x-.25,point.y,point.z-.25,point.x+.25,point.y+.5,point.z+.25);
   boolean clear=level.noCollision(body);Vec3 center=point.add(0,.25,0);VoxelShape search=Shapes.create(AABB.ofSize(center,.5,.5,.5));
   Optional<Vec3> free=level.findFreePosition(orb,search,center,.5,.5,.5);Vec3 finalPosition=clear?point:free.map(v->v.add(0,-.25,0)).orElse(point);
   var obstacles=new ArrayList<Object>();for(JsonElement w:in.getAsJsonArray("writes")){var r=w.getAsJsonObject();var a=r.getAsJsonArray("position");BlockPos pos=new BlockPos(a.get(0).getAsInt(),a.get(1).getAsInt(),a.get(2).getAsInt());BlockState state=level.blocks.get(pos);VoxelShape raw=CollisionContext.of(orb).getCollisionShape(state,level,pos);VoxelShape moved=raw.move(pos);if(!moved.isEmpty())obstacles.add(Map.of("shape",grid(moved),"box",box(moved.bounds()),"full",raw==Shapes.block(),"border_within",level.border.isWithinBounds(moved.bounds())));}
   AABB outer=search.bounds().inflate(.5,.5,.5);VoxelShape union=Shapes.empty();for(VoxelShape block:level.getBlockCollisions(orb,outer)){if(!level.border.isWithinBounds(block.bounds()))continue;for(AABB b:block.toAabbs())union=Shapes.or(union,Shapes.create(b.inflate(.25,.25,.25)));}
   VoxelShape available=Shapes.join(search,union,BooleanOp.ONLY_FIRST);
   var row=new TreeMap<String,Object>();row.put("id",in.get("id").getAsString());row.put("clear",clear);row.put("free",free.map(ReferenceCookingEffectGeometry::vector).orElse(null));row.put("position",vector(finalPosition));row.put("body",box(body));row.put("outer",box(outer));row.put("search",grid(search));row.put("union",grid(union));row.put("available",grid(available));row.put("obstacles",obstacles);row.put("queries",level.callsGeometry);results.add(row);
  }
  var runtime=new TreeMap<String,String>();for(String name:List.of("net.minecraft.world.level.CollisionGetter","net.minecraft.world.level.BlockCollisions","net.minecraft.world.phys.shapes.Shapes","net.minecraft.world.phys.shapes.VoxelShape","net.minecraft.world.phys.shapes.BitSetDiscreteVoxelShape","net.minecraft.world.phys.shapes.IndirectMerger","net.minecraft.world.entity.ExperienceOrb")){Class<?> c=Class.forName(name);try(var s=c.getResourceAsStream("/"+name.replace('.','/')+".class")){runtime.put(name,HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(s.readAllBytes())));}}
  Files.writeString(Path.of(args[1]),JSON.toJson(Map.of("version",SharedConstants.getCurrentVersion().id(),"cases",results,"runtime_classes",runtime)));
 }
}'''.replace('#NORMAL#','ExperienceOrb orb=new ExperienceOrb(level,100,100,100,1);level.callsGeometry.clear();')

def db(x):return struct.pack('>d',x).hex()
def inputs():
    slabs=json.loads((ROOT/'reference/slab_collision.json').read_text())['slab_entries']
    ids={k:next(r['state_id'] for r in slabs if r['slab_type']==k and not r['waterlogged']) for k in ['top','bottom','double']}
    cases=[]
    def add(label,point,writes=(),entities=(),**extra):cases.append({'id':label,'point':[db(v) for v in point],'writes':[{'position':p,'state':s} for p,s in writes],'entities':[[db(v) for v in a] for a in entities],**extra})
    solid=[([0,0,0],1)]
    add('clear',[.5,1.5,.5]);add('enclosed',[.5,.25,.5],solid)
    for label,p in [('west',[-.1,.25,.5]),('east',[1.1,.25,.5]),('below',[.5,-.2,.5]),('above',[.5,.8,.5]),('north',[.5,.25,-.1]),('south',[.5,.25,1.1]),('three-axis-tie',[-.1,-.35,-.1]),('two-axis-tie',[-.1,.25,-.1])]:add(label,p,solid)
    add('bottom-surface',[.5,.45,.5],[([0,0,0],ids['bottom'])]);add('top-edge',[-.1,.6,.5],[([0,0,0],ids['top'])]);add('double-west',[-.1,.25,.5],[([0,0,0],ids['double'])])
    add('multiple-union',[-.1,-.35,-.1],solid+[([-1,0,0],ids['bottom']),([0,-1,0],ids['top'])])
    add('negative-translated',[-7.1,-10.75,-12.5],[([-7,-11,-13],ids['bottom'])])
    add('epsilon-below',[.5,.5-1e-7,.5],[([0,0,0],ids['bottom'])]);add('epsilon-above',[.5,.5+1e-7,.5],[([0,0,0],ids['bottom'])])
    add('entity-only',[-.1,.25,.5],[],[[0,0,0,1,1,1]])
    add('border-filter-outside',[1.1,.25,.5],solid,border=1.0,admitted=False)
    return cases

def main():
    import sys
    delta="--tie-delta" in sys.argv
    WORK.mkdir(parents=True,exist_ok=True);jars,release=verified_classpath();request=inputs();
    if delta:request=[{**request[0],"id":"exact-three-axis-tie","point":[db(v) for v in [-.125,-.375,-.125]],"writes":[{"position":[0,0,0],"state":1}]}]
    (WORK/'input.json').write_bytes(canonical(request))
    files=[]
    for name,s in [('ReferenceMovementProbe',MOVE_SOURCE),('ReferenceDirectMovementProbe',DIRECT_SOURCE),('ReferenceCookingEffectGeometry',SOURCE)]:
        path=WORK/(name+'.java');path.write_text(s);files.append(path)
    cp=':'.join(map(str,jars));started=time.monotonic()
    compile=subprocess.run([str(JAVA.parent/'javac'),'-cp',cp,'-d',str(WORK),*map(str,files)],capture_output=True,timeout=60);(WORK/'compile.log').write_bytes(compile.stdout+compile.stderr)
    if compile.returncode:raise RuntimeError(compile.stderr.decode()[-5000:])
    command=[str(JAVA),'-Xmx768m','-cp',str(WORK)+':'+cp,'ReferenceCookingEffectGeometry',str(WORK/'input.json'),str(WORK/'actual.json')]
    run=subprocess.run(command,capture_output=True,timeout=90);(WORK/'run.log').write_bytes(run.stdout+run.stderr)
    if run.returncode:raise RuntimeError(run.stderr.decode()[-5000:])
    actual=json.loads((WORK/'actual.json').read_text());assert actual['version']=='26.3' and len(actual['cases'])==len(request)
    deps={str(p):fingerprint(p) for p in [JAVA,JAVA.parent/'javac',ROOT/'tools/reference_movement_probe.py',ROOT/'reference/slab_collision.json',*jars]}
    result={'pin':'26.3','inputs':request,'observations':actual,'dependencies':deps,'source_sha256':hashlib.sha256(SOURCE.encode()).hexdigest(),'boundary':'Actual normally constructed Level/ExperienceOrb; actual BlockCollisions, noCollision, findFreePosition, shape boolean merge/optimization and closestPointTo. Finite map/declared entity collision fixture; no host gameplay.'}
    target=ROOT/('reference/cooking_effect_geometry_tie.json' if delta else 'reference/cooking_effect_geometry.json')
    target.write_bytes(canonical(result)+b'\n')
    (ROOT/('evidence/cooking-effect-geometry-reference-tie.json' if delta else 'evidence/cooking-effect-geometry-reference.json')).write_text(json.dumps({'status':'passed','cases':len(request),'seconds':round(time.monotonic()-started,3),'command':'python3 tools/reference_cooking_effect_geometry.py','source_sha256':result['source_sha256'],'reference':fingerprint(target),'runtime_classes':actual['runtime_classes']},indent=2)+'\n')
    print(json.dumps({'status':'passed','cases':len(request)}))
if __name__=='__main__':main()
