#!/usr/bin/env python3
"""Observe pinned Interval, real MinMax/blend graphs, and raw noise coordinates."""
from __future__ import annotations
import argparse,hashlib,json,struct,time,zipfile
from pathlib import Path
from reference_inventory import ROOT,JAVA,fingerprint,write_json
from reference_superflat_probe import WORK,run
from reference_worldgen_density_probe import gradient,binary,POINTS

def fw(x):return struct.unpack('>I',struct.pack('>f',x))[0]
def dw(x):return list(struct.unpack('>II',struct.pack('>d',x)))
def r(a,b):return ['R',fw(a),fw(b)]
def n():return ['N',0,0]

def intervals():
    cases=[]
    pairs=[(r(-2,3),r(-4,1)),(r(-0.0,-0.0),r(0.0,0.0)),(r(0,0),r(float('-inf'),float('inf'))),(r(-1,0),r(0,1)),(r(-2,-1),r(1,2)),(n(),r(-1,1))]
    for op in ['add','sub','mul','div','min','max','lerp']:
        for i,(a,b) in enumerate(pairs):cases.append({'id':op+'-'+str(i),'op':op,'a':a,'b':b,'c':r(-1,2)})
    for op in ['absolute','square','reciprocal']:
        for i,a in enumerate([r(-2,3),r(-2,-1),r(0,1),r(-1,0),r(0,0),r(-0.0,-0.0),r(float('-inf'),float('inf')),n()]):cases.append({'id':op+'-'+str(i),'op':op,'a':a,'b':r(0,1),'c':r(0,1)})
    for i,(a,b) in enumerate([(r(-0.0,-0.0),r(-1,0.0)),(r(0,0),r(-0.0,1)),(n(),['R',2143289344,fw(1)]),(r(2,3),['R',2143289344,fw(1)]),(r(-3,-2),['R',fw(-1),2143289344]),(r(0,1),['R',2143289344,fw(1)]),(n(),r(2,1)),(r(-2,3),r(-1,1))]):cases.append({'id':'clamp-'+str(i),'op':'clamp','a':a,'b':b,'c':r(0,1)})
    for i,(a,b) in enumerate([(r(-0.0,-0.0),r(0.0,0.0)),(r(0,0),r(-0.0,-0.0)),(['R',2143289344,0],r(1,1)),(r(1,1),['R',2143289344,0])]):
        for op in ['float-min','float-max']:cases.append({'id':op+'-'+str(i),'op':op,'a':a,'b':b,'c':r(0,1)})
    return cases

def coordinates():
    cases=[]
    scales=[(0.10000000000000002,-0.3),(0.0,-0.0),(-0.0,0.0),(1.7976931348623157e308,5e-324),(0.25,0.2)]
    points=[[0,0,0],[1,-1,1],[-17,31,127],[16777217,-65,-16777217],[-2147483648,2147483647,2147483647]]
    shifts=[[fw(0.1),fw(-0.0),fw(-0.3)],[fw(-2.5),fw(0.5),fw(4.0)]]
    for mode in ['plain','xyz']:
        for i,(xz,y) in enumerate(scales):
            for j,p in enumerate(points):cases.append({'id':mode+'-'+str(i)+'-'+str(j),'mode':mode,'point':p,'xz':dw(xz),'y':dw(y),'shift':shifts[j%2]})
    return cases

def graphs():
    result=[]
    g=gradient('x',-1,1,-2.0,2.0)
    for kind in ['min','max']:
        for name,left,right in [('generic',g,gradient('z',-1,1,-1.0,1.0)),('constant-left',-0.0,g),('constant-right',g,-0.0),('both-zero',-0.0,0.0),('disjoint-left',gradient('x',-1,1,-4.0,-2.0),gradient('z',-1,1,1.0,3.0)),('disjoint-right',gradient('x',-1,1,1.0,3.0),gradient('z',-1,1,-4.0,-2.0)),('blend-bound',{'type':'minecraft:blend_alpha'},g),('offset-bound',{'type':'minecraft:blend_offset'},g)]:
            result.append({'id':kind+'-'+name,'seed':'0','expression':binary(kind,left,right),'points':POINTS})
    for kind in ['blend_alpha','blend_offset']:
        result.append({'id':kind,'seed':'0','expression':{'type':'minecraft:'+kind},'points':POINTS})
    result.append({'id':'blend_density','seed':'0','expression':{'type':'minecraft:blend_density','input':g},'points':POINTS})
    result.append({'id':'loaded-base3d-range','seed':'0','expression':'minecraft:overworld/base_3d_noise','points':POINTS})
    for seed in ['0','1','9223372036854775808','18446744073709551615']:
        result.append({'id':'loaded-sloped-cheese-'+seed,'seed':seed,'expression':'minecraft:overworld/sloped_cheese','points':POINTS,'column':{'x':-17,'z':31,'bottom':-64,'step':16,'count':24}})
    return result

SOURCE=r'''import java.util.*;import java.lang.reflect.*;import java.nio.file.*;import java.security.MessageDigest;
import com.google.gson.*;import com.mojang.serialization.JsonOps;
import net.minecraft.SharedConstants;import net.minecraft.server.Bootstrap;import net.minecraft.data.registries.VanillaRegistries;
import net.minecraft.core.registries.Registries;import net.minecraft.resources.*;import net.minecraft.world.level.levelgen.*;
import net.minecraft.world.level.levelgen.densityfunction.*;import net.minecraft.world.level.levelgen.densityfunction.generator.NoiseFunction;
import net.minecraft.world.level.levelgen.synth.*;import net.minecraft.util.Interval;
class ReferenceWorldgenDensityIntervals {
 static float f(JsonElement x){return Float.intBitsToFloat((int)x.getAsLong());}
 static long w(float x){return Integer.toUnsignedLong(Float.floatToRawIntBits(x));}
 static List<Long> d(double x){long v=Double.doubleToRawLongBits(x);return List.of(v>>>32,v&0xffffffffL);}
 static double d(JsonArray x){return Double.longBitsToDouble((x.get(0).getAsLong()<<32)|x.get(1).getAsLong());}
 static Interval interval(JsonArray x){return x.get(0).getAsString().equals("N")?Interval.NaI:Interval.of(f(x.get(1)),f(x.get(2)));}
 static Object range(Interval x){return Map.of("nai",x.isNaI(),"min_bits",w(x.min()),"max_bits",w(x.max()));}
 static Object observe(JsonObject row){
  var a=row.getAsJsonArray("a");var b=row.getAsJsonArray("b");var c=row.getAsJsonArray("c");var op=row.get("op").getAsString();
  try {if(op.equals("float-min"))return Map.of("bits",w(Math.min(f(a.get(1)),f(b.get(1)))));
   if(op.equals("float-max"))return Map.of("bits",w(Math.max(f(a.get(1)),f(b.get(1)))));
   var x=interval(a);Interval result=switch(op){
    case "add"->Interval.add(x,interval(b));case "sub"->Interval.sub(x,interval(b));case "mul"->Interval.mul(x,interval(b));case "div"->Interval.div(x,interval(b));
    case "min"->Interval.min(x,interval(b));case "max"->Interval.max(x,interval(b));case "absolute"->Interval.abs(x);case "square"->Interval.square(x);
    case "reciprocal"->Interval.reciprocal(x);case "clamp"->Interval.clamp(x,f(b.get(1)),f(b.get(2)));case "lerp"->Interval.lerp(x,interval(b),interval(c));default->throw new IllegalArgumentException(op);};
   return range(result);
  }catch(Exception e){return Map.of("refused",true,"exception",e.getClass().getName());}
 }
 static Map<String,Object> pin(Class<?> type)throws Exception{var m=type.getName().replace('.','/')+".class";try(var in=type.getResourceAsStream("/"+m)){var bytes=in.readAllBytes();return Map.of("member",m,"bytes",bytes.length,"sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)),"code_source",type.getProtectionDomain().getCodeSource().getLocation().toString());}}
 public static void main(String[] args)throws Exception{
  var output=System.out;var input=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonObject();SharedConstants.tryDetectVersion();Bootstrap.bootStrap();var lookup=VanillaRegistries.createWorldLookup();var ops=RegistryOps.create(JsonOps.INSTANCE,lookup);var settings=lookup.lookupOrThrow(Registries.NOISE_SETTINGS).getOrThrow(NoiseGeneratorSettings.OVERWORLD).value();
  var intervals=new ArrayList<Object>();for(var entry:input.getAsJsonArray("intervals")){var row=entry.getAsJsonObject();intervals.add(Map.of("id",row.get("id").getAsString(),"observed",observe(row)));}
  var coordinates=new ArrayList<Object>();var definition=lookup.lookupOrThrow(Registries.NOISE).getOrThrow(ResourceKey.create(Registries.NOISE,Identifier.parse("minecraft:ridge"))).value();Noise real=definition.create(new XoroshiroRandomSource(0));
  for(var entry:input.getAsJsonArray("coordinates")){var row=entry.getAsJsonObject();var received=new ArrayList<Object>();Noise recorder=(Noise)Proxy.newProxyInstance(Noise.class.getClassLoader(),new Class[]{Noise.class},(proxy,method,values)->{
    if(method.getName().equals("get")){received.add(List.of(d((double)values[0]),d((double)values[1]),d((double)values[2])));}
    try{return method.invoke(real,values);}catch(InvocationTargetException e){throw e.getCause();}});
   DensitySampler sampler;if(row.get("mode").getAsString().equals("plain"))sampler=new NoiseFunction.Sampler(recorder,d(row.getAsJsonArray("xz")),d(row.getAsJsonArray("y")));
   else{var shifts=row.getAsJsonArray("shift");var reads=new ArrayList<DensitySampler>();for(var v:shifts){float value=f(v);reads.add((DensitySampler)Proxy.newProxyInstance(DensitySampler.class.getClassLoader(),new Class[]{DensitySampler.class},(proxy,method,values)->{if(method.getName().equals("sampleValue"))return value;throw new UnsupportedOperationException(method.getName());}));}sampler=new NoiseFunction.ShiftedXyzSampler(reads.get(0),reads.get(1),reads.get(2),recorder,d(row.getAsJsonArray("xz")),d(row.getAsJsonArray("y")));}
   var p=row.getAsJsonArray("point");float value=sampler.sampleValue(null,p.get(0).getAsInt(),p.get(1).getAsInt(),p.get(2).getAsInt());if(received.size()!=1)throw new IllegalStateException("actual Noise.get call count");coordinates.add(Map.of("id",row.get("id").getAsString(),"coordinates",received.get(0),"noise_bits",w(value)));
  }
  var graphs=new ArrayList<Object>();for(var entry:input.getAsJsonArray("graphs")){var row=entry.getAsJsonObject();var function=DensityFunction.CODEC.parse(ops,row.get("expression")).getOrThrow();var state=RandomState.create(lookup.lookupOrThrow(Registries.NOISE),Long.parseUnsignedLong(row.get("seed").getAsString()),settings);var values=new ArrayList<Long>();for(var entrypoint:row.getAsJsonArray("points")){var p=entrypoint.getAsJsonArray();values.add(w(state.sampleBlockValueUncached(function,p.get(0).getAsInt(),p.get(1).getAsInt(),p.get(2).getAsInt())));}var observed=new LinkedHashMap<String,Object>();observed.put("id",row.get("id").getAsString());observed.put("bits",values);observed.put("range",range(function.range()));if(row.has("column")){var request=row.getAsJsonObject("column");var column=new ArrayList<Long>();for(int i=0;i<request.get("count").getAsInt();i++)column.add(w(state.sampleBlockValueUncached(function,request.get("x").getAsInt(),request.get("bottom").getAsInt()+i*request.get("step").getAsInt(),request.get("z").getAsInt())));observed.put("column_bits",column);}graphs.add(observed);}
  var pins=new ArrayList<Object>();for(var name:List.of("net.minecraft.util.Interval","net.minecraft.world.level.levelgen.densityfunction.generator.NoiseFunction$Sampler","net.minecraft.world.level.levelgen.densityfunction.generator.NoiseFunction$ShiftedXyzSampler","net.minecraft.world.level.levelgen.densityfunction.op.BinaryFunction","net.minecraft.world.level.levelgen.densityfunction.op.BinaryFunction$MinSampler","net.minecraft.world.level.levelgen.densityfunction.op.BinaryFunction$MaxSampler","net.minecraft.world.level.levelgen.densityfunction.generator.SimpleDensityFunction","net.minecraft.world.level.levelgen.densityfunction.op.BlendDensityFunction$Sampler"))pins.add(pin(Class.forName(name)));
  output.println("INTERVAL_JSON:"+new Gson().toJson(Map.of("intervals",intervals,"coordinates",coordinates,"graphs",graphs,"loaded_classes",pins)));
 }
}'''

def observe():
    facts=json.loads((WORK/'classpath.json').read_text())
    for pin in facts['checkpoint']:
        stat=Path(pin['path']).stat()
        if stat.st_size!=pin['size'] or stat.st_mtime_ns!=pin['mtime_ns']:raise RuntimeError('Official classpath checkpoint changed')
    token=str(time.time_ns());inputs={'intervals':intervals(),'coordinates':coordinates(),'graphs':graphs()}
    path=WORK/('interval-input-'+token+'.json');write_json(path,inputs)
    source=WORK/('ReferenceWorldgenDensityIntervals-'+token+'.java');source.write_text(SOURCE)
    output,process=run('density-interval-java-'+token,[JAVA,'-Xmx512m','--source','25','--class-path',':'.join(facts['classpath']),source,path],60)
    lines=[line[len('INTERVAL_JSON:'):] for line in output.splitlines() if line.startswith('INTERVAL_JSON:')]
    if len(lines)!=1:raise RuntimeError('Actual interval observation absent')
    observations=json.loads(lines[0])
    with zipfile.ZipFile(facts['classpath'][0]) as jar:
        for pin in observations['loaded_classes']:
            if hashlib.sha256(jar.read(pin['member'])).hexdigest()!=pin['sha256']:raise RuntimeError('Loaded actual class pin mismatch')
    result={'schema':1,'pin':'26.3','status':'observed','inputs':inputs,'observations':observations,'classpath_checkpoint':facts,'execution':process,'executed_source':{'path':str(source.relative_to(ROOT)),**fingerprint(source)},'helper':fingerprint(Path(__file__).resolve()),'scope':'Actual Interval methods, actual compiled MinMax/no-blending functions, and raw binary64 inputs recorded at actual Noise.get from real NoiseFunction samplers. Density values and spline arithmetic in26.3 are float; scales/coordinate arithmetic are double. Full chunk population remains unsupported.'}
    target=ROOT/'reference/worldgen_density_intervals.json';write_json(target,result)
    write_json(ROOT/'evidence/worldgen-density-interval-reference.json',{'schema':1,'status':'passed','pin':'26.3','reference':fingerprint(target),'execution':process,'interval_cases':len(inputs['intervals']),'coordinate_cases':len(inputs['coordinates']),'graph_cases':len(inputs['graphs']),'loaded_classes':observations['loaded_classes'],'scope':result['scope']})
    return {'status':'observed','interval_cases':len(inputs['intervals']),'coordinate_cases':len(inputs['coordinates']),'graph_cases':len(inputs['graphs']),'seconds':process['seconds']}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--observe',action='store_true',required=True);parser.parse_args();print(json.dumps(observe(),sort_keys=True))
