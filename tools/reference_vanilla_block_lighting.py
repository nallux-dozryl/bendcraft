#!/usr/bin/env python3
"""Observe installed26.3 BlockModelLighter, QuadInstance and LightCoordsUtil."""
import hashlib,json,os,subprocess,time
from pathlib import Path
from reference_model_probe import verified_client_classpath,JAVA
ROOT=Path(__file__).resolve().parents[1];WORK=ROOT/'build/vanilla-block-lighting-reference'
SOURCE=r'''
import com.google.gson.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.Identifier;
import net.minecraft.world.level.*;
import net.minecraft.world.level.block.*;
import net.minecraft.world.level.block.state.*;
import net.minecraft.client.renderer.block.*;
import net.minecraft.client.resources.model.geometry.BakedQuad;
import net.minecraft.util.LightCoordsUtil;
import com.mojang.blaze3d.vertex.QuadInstance;
import org.joml.*;
import java.lang.reflect.*;
import java.nio.file.*;
import java.util.*;
class VanillaBlockLightingReference {
 static Gson G=new GsonBuilder().serializeNulls().create();
 static int bits(float f){return Float.floatToRawIntBits(f);}
 static Object field(Object value,String name)throws Exception{Field f=value.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(value);}
 static List<Integer> point(BlockPos p){return List.of(p.getX(),p.getY(),p.getZ());}
 static BlockState state(String name){return BuiltInRegistries.BLOCK.getValue(Identifier.parse(name)).defaultBlockState();}
 static class World implements InvocationHandler {
  final JsonObject input;final LinkedHashMap<List<Integer>,BlockState> states=new LinkedHashMap<>();final List<Object> calls=new ArrayList<>();final BlockAndTintGetter getter;
  World(JsonObject c){input=c;getter=(BlockAndTintGetter)Proxy.newProxyInstance(getClass().getClassLoader(),new Class[]{BlockAndTintGetter.class},this);for(var raw:c.getAsJsonArray("cells")){var o=raw.getAsJsonObject();states.put(List.of(o.get("x").getAsInt(),o.get("y").getAsInt(),o.get("z").getAsInt()),state(o.get("state").getAsString()));}}
  BlockState stateAt(BlockPos p){return states.getOrDefault(point(p),state(input.get("default_state").getAsString()));}
  int light(BlockPos p,boolean sky){int salt=sky?7:3;return java.lang.Math.floorMod(p.getX()*3+p.getY()*5+p.getZ()*7+input.get("pattern").getAsInt()+salt,16);}
  public Object invoke(Object proxy,Method m,Object[] a){
   switch(m.getName()){
    case "getBlockState": {BlockPos p=(BlockPos)a[0];calls.add(Map.of("method","state","position",point(p)));return stateAt(p);}
    case "getFluidState":return stateAt((BlockPos)a[0]).getFluidState();
    case "getBlockEntity":return null;
    case "getBrightness":{BlockPos p=(BlockPos)a[1];boolean sky=a[0]==LightLayer.SKY;calls.add(Map.of("method",sky?"sky":"block","position",point(p)));return light(p,sky);}
    case "cardinalLighting": {var v=input.getAsJsonArray("cardinal");return new CardinalLighting(v.get(0).getAsFloat(),v.get(1).getAsFloat(),v.get(2).getAsFloat(),v.get(3).getAsFloat(),v.get(4).getAsFloat(),v.get(5).getAsFloat());}
    case "getHeight":return 384;case "getMinY":return -64;case "getBlockTint":return -1;
    case "toString":return "actual observed block input provider";
    default:throw new AssertionError("unhandled world method "+m);
   }
  }
  Object info(BlockState s,BlockPos p){return Map.of("state",Block.getId(s),"emission",s.getLightEmission(),"emissive",s.emissiveRendering(),"solid",s.isSolidRender(),"full",s.isCollisionShapeFullBlock(getter,p),"permeable",s.isLightPermeable(),"shade",Integer.toUnsignedLong(bits(s.getShadeBrightness(getter,p))));}
 }
 static Object tables()throws Exception{
  var out=new ArrayList<>();Class<?> adj=Class.forName("net.minecraft.client.renderer.block.BlockModelLighter$AdjacencyInfo"),remap=Class.forName("net.minecraft.client.renderer.block.BlockModelLighter$AmbientVertexRemap");
  Method a=adj.getDeclaredMethod("fromFacing",Direction.class),r=remap.getDeclaredMethod("fromFacing",Direction.class);a.setAccessible(true);r.setAccessible(true);
  for(Direction d:Direction.values()){Object av=a.invoke(null,d),rv=r.invoke(null,d);var row=new LinkedHashMap<String,Object>();row.put("direction",d.toString());row.put("corners",Arrays.stream((Direction[])field(av,"corners")).map(Direction::toString).toList());row.put("weighted",field(av,"doNonCubicWeight"));var weights=new ArrayList<>();var maps=new ArrayList<>();for(int i=0;i<4;i++){var one=new ArrayList<>();for(Object s:(Object[])field(av,"vert"+i+"Weights"))one.add(field(s,"index"));weights.add(one);maps.add(field(rv,"vert"+i));}row.put("weights",weights);row.put("remap",maps);out.add(row);}return out;
 }
 static Vector3f vertex(JsonElement value){JsonArray a=value.getAsJsonArray();return new Vector3f(a.get(0).getAsFloat(),a.get(1).getAsFloat(),a.get(2).getAsFloat());}
 public static void main(String[] args)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();var out=new ArrayList<>();
  for(var raw:JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonArray()){
   var c=raw.getAsJsonObject();var w=new World(c);var source=state(c.get("source").getAsString());w.states.put(List.of(0,0,0),source);var vs=c.getAsJsonArray("vertices");Direction d=Direction.byName(c.get("direction").getAsString());Direction sd=c.get("override").isJsonNull()?null:Direction.byName(c.get("override").getAsString());
   int emission=c.get("emission").getAsInt();var q=new BakedQuad(vertex(vs.get(0)),vertex(vs.get(1)),vertex(vs.get(2)),vertex(vs.get(3)),0L,0L,0L,0L,d,new BakedQuad.MaterialInfo(null,null,null,null,null,-1,sd,emission));var instance=new QuadInstance();var lighter=new BlockModelLighter();BlockModelLighter.clearCache();
   if(c.get("smooth").getAsBoolean())lighter.prepareQuadAmbientOcclusion(w.getter,source,BlockPos.ZERO,q,instance);else lighter.prepareQuadFlat(w.getter,source,BlockPos.ZERO,c.get("flat").getAsInt(),q,instance);
   var row=new LinkedHashMap<String,Object>();row.put("id",c.get("id").getAsString());row.put("calls",new ArrayList<>(w.calls));row.put("cubic",field(lighter,"faceCubic"));row.put("partial",field(lighter,"facePartial"));var appearance=new ArrayList<>();for(int i=0;i<4;i++)appearance.add(Map.of("light",Integer.toUnsignedLong(instance.getLightCoordsWithEmission(i,emission)),"raw_light",Integer.toUnsignedLong(instance.getLightCoords(i)),"color",Integer.toUnsignedLong(instance.getColor(i))));row.put("vertices",appearance);
   var points=new LinkedHashSet<List<Integer>>();points.add(List.of(0,0,0));for(Object o:(List<?>)row.get("calls")){points.add((List<Integer>)((Map<?,?>)o).get("position"));}var cells=new ArrayList<>();for(var p:points){var pos=new BlockPos(p.get(0),p.get(1),p.get(2));cells.add(Map.of("position",p,"info",w.info(w.stateAt(pos),pos),"block",w.light(pos,false),"sky",w.light(pos,true)));}row.put("cells",cells);row.put("source",w.info(source,BlockPos.ZERO));row.put("cardinal",c.getAsJsonArray("cardinal").asList().stream().map(v->Integer.toUnsignedLong(bits(v.getAsFloat()))).toList());out.add(row);
  }
  Files.writeString(Path.of(args[1]),G.toJson(Map.of("cases",out,"tables",tables())));
 }
}
'''
def inputs():
    rows=[];directions=['down','up','north','south','west','east']
    def quad(d,lo=0,hi=1,plane=None):
        axis={'down':1,'up':1,'north':2,'south':2,'west':0,'east':0}[d];p=(0 if d in ['down','north','west'] else 1) if plane is None else plane
        result=[]
        for a,b in [(lo,lo),(lo,hi),(hi,hi),(hi,lo)]:
            v=[0,0,0];v[axis]=p;v[(axis+1)%3]=a;v[(axis+2)%3]=b;result.append(v)
        return result
    def add(name,d,**kw):
        c=dict(id=name,direction=d,vertices=quad(d),source='minecraft:stone',default_state='minecraft:air',cells=[],pattern=0,cardinal=[.5,1,.8,.8,.6,.6],smooth=True,flat=-1,override=None,emission=0);c.update(kw);rows.append(c)
    for d in directions:
        add('smooth-full-'+d,d)
        add('smooth-partial-'+d,d,vertices=quad(d,.17,.83))
        add('smooth-inset-'+d,d,vertices=quad(d,.17,.83,.4),source='minecraft:oak_slab')
        add('smooth-blocked-'+d,d,default_state='minecraft:stone',pattern=11)
        add('flat-'+d,d,smooth=False)
    add('mixed-permeability','up',cells=[dict(x=x,y=y,z=z,state='minecraft:stone' if (x+z)%2==0 else 'minecraft:oak_leaves') for x in [-1,0,1] for y in [1,2] for z in [-1,0,1]])
    add('emissive-state','north',source='minecraft:magma_block',smooth=False)
    add('source-emission','north',source='minecraft:glowstone',smooth=False)
    add('element-emission','east',emission=9)
    add('side-override','north',override='up',cardinal=[.31,.91,.71,.61,.51,.41])
    add('flat-known','east',smooth=False,flat=0x00880044)
    add('outside-unit-weight','south',vertices=quad('south',-.5,1.5,.7),source='minecraft:oak_slab')
    add('nonplanar','up',vertices=[[0,.2,0],[0,.3,1],[1,.8,1],[1,.7,0]],source='minecraft:oak_slab')
    for value in [0.0001,0.9999,0.00009999,0.99990004]:add('threshold-'+str(value),'up',vertices=quad('up',0,1,value),source='minecraft:oak_slab')
    return rows

def main():
    WORK.mkdir(parents=True,exist_ok=True);paths,pin=verified_client_classpath();rows=inputs();(WORK/'inputs.json').write_text(json.dumps(rows));(WORK/'VanillaBlockLightingReference.java').write_text(SOURCE);start=time.monotonic();p=subprocess.run([str(JAVA),'-Xmx512m','--source','25','--class-path',os.pathsep.join(map(str,paths)),WORK/'VanillaBlockLightingReference.java',WORK/'inputs.json',WORK/'output.json'],capture_output=True,text=True,timeout=60);(WORK/'java.stdout').write_text(p.stdout);(WORK/'java.stderr').write_text(p.stderr);assert p.returncode==0,p.stderr
    observed=json.loads((WORK/'output.json').read_text());out=dict(pin='26.3',inputs=rows,observations=observed,provenance=pin,source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),java_source_sha256=hashlib.sha256(SOURCE.encode()).hexdigest(),seconds=round(time.monotonic()-start,4),boundary='Actual installed BlockModelLighter prepareQuadAmbientOcclusion/Flat and QuadInstance emission. Proxy supplies explicit world states/raw brightness/CardinalLighting; all state flags/shade/collision-full are actual Java observations. Reference geometry/brightness are controlled test inputs, not product defaults.')
    (ROOT/'reference/vanilla_block_lighting.json').write_text(json.dumps(out,separators=(',',':'))+'\n');print(json.dumps(dict(status='passed',cases=len(rows))))
if __name__=='__main__':main()
