#!/usr/bin/env python3
"""Observe actual pinned26.3 eight-root and six-axis climate/biome producers.

Every expected float, quantized long and selected biome is emitted by official
production classes. Python selects requests and records resource/class pins.
"""
from __future__ import annotations
import argparse, copy, hashlib, json, time, zipfile
from pathlib import Path
from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_superflat_probe import WORK, run
OUTPUT=ROOT/'reference/worldgen_density_router.json'
NAMES=['chunk_surface_level','continents','depth','erosion','final_density','ridges','temperature','vegetation']
POINTS=[[0,-64,0],[0,0,0],[1,1,1],[-1,-1,-1],[-17,31,127],[31,320,-17],
        [16384,80,-16384],[16777217,-65,-16777217],[-2147483648,2147483647,2147483647],[0,0,0]]
QUARTS=[[0,0,0],[-1,-16,7],[64,16,-64],[4096,80,-4096],[4194305,-17,-4194305],
        [536870912,-536870913,536870911],[0,0,0]]

def input_cases():
    selected=json.loads((ROOT/'reference/normal_overworld_noise.json').read_text())['installed_entries']['data/minecraft/worldgen/noise_settings/overworld.json']['json']['noise_router']
    supported={'chunk_surface_level':{'type':'minecraft:gradient','axis':'y','from_coordinate':-64,'to_coordinate':320,'from_value':1.5,'to_value':-1.5},
      'continents':selected['continents'],'depth':{'type':'minecraft:gradient','axis':'x','from_coordinate':-17,'to_coordinate':31,'from_value':-0.0,'to_value':1.0},
      'erosion':selected['erosion'],'final_density':'minecraft:overworld/base_3d_noise',
      'ridges':selected['ridges'],'temperature':selected['temperature'],'vegetation':selected['vegetation']}
    alias={name:'minecraft:overworld/temperature' for name in NAMES}
    cases=[]
    for seed in ['0','1','9223372036854775808','18446744073709551615']:
        cases.append({'id':'supported-eight-'+seed,'seed':seed,'kind':'eight','router':supported,'points':POINTS})
        predecessor=copy.deepcopy(supported);predecessor['depth']=selected['depth'];predecessor['final_density']='minecraft:overworld/sloped_cheese'
        cases.append({'id':'loaded-sloped-cheese-eight-'+seed,'seed':seed,'kind':'eight-unblended','router':predecessor,'points':POINTS})
        cases.append({'id':'loaded-six-'+seed,'seed':seed,'kind':'climate','router':selected,'quarts':QUARTS})
    cases.append({'id':'all-roots-share-loaded-reference','seed':'0','kind':'eight','router':alias,'points':POINTS})
    return cases

SOURCE=r'''import java.util.*;
import java.nio.file.*;
import java.security.MessageDigest;
import com.google.gson.*;
import com.mojang.serialization.JsonOps;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.data.registries.VanillaRegistries;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.*;
import net.minecraft.world.level.levelgen.*;
import net.minecraft.world.level.levelgen.densityfunction.*;
import net.minecraft.world.level.biome.*;
class ReferenceWorldgenDensityRouter {
 static List<Long> words(long value) {return List.of(value>>>32,value&0xffffffffL);}
 static long bits(float value) {return Integer.toUnsignedLong(Float.floatToRawIntBits(value));}
 static Map<String,Object> loadedClass(Class<?> type) throws Exception {
  var member=type.getName().replace('.','/')+".class";
  try(var input=type.getResourceAsStream("/"+member)) {
   var data=input.readAllBytes();return Map.of("member",member,"bytes",data.length,"sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data)));
  }
 }
 public static void main(String[] args) throws Exception {
  var output=System.out;SharedConstants.tryDetectVersion();Bootstrap.bootStrap();var lookup=VanillaRegistries.createWorldLookup();
  var ops=RegistryOps.create(JsonOps.INSTANCE,lookup);
  var settings=lookup.lookupOrThrow(Registries.NOISE_SETTINGS).getOrThrow(NoiseGeneratorSettings.OVERWORLD).value();
  var parameters=lookup.lookupOrThrow(Registries.MULTI_NOISE_BIOME_SOURCE_PARAMETER_LIST).getOrThrow(ResourceKey.create(Registries.MULTI_NOISE_BIOME_SOURCE_PARAMETER_LIST,Identifier.parse("minecraft:overworld"))).value().parameters();
  var indexed=new ArrayList<com.mojang.datafixers.util.Pair<Climate.ParameterPoint,Integer>>();
  for(int i=0;i<parameters.values().size();i++)indexed.add(com.mojang.datafixers.util.Pair.of(parameters.values().get(i).getFirst(),i));
  var input=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonArray();var cases=new ArrayList<Object>();
  var names=List.of("chunk_surface_level","continents","depth","erosion","final_density","ridges","temperature","vegetation");
  for(var raw:input) {
   var row=raw.getAsJsonObject();long seed=Long.parseUnsignedLong(row.get("seed").getAsString());
   var state=RandomState.create(lookup.lookupOrThrow(Registries.NOISE),seed,settings);
   var tree=new Climate.ParameterList<Integer>(indexed);
   var results=new ArrayList<Object>();
   if(row.get("kind").getAsString().startsWith("eight")) {
    var functions=new ArrayList<DensityFunction>();for(var name:names)functions.add(DensityFunction.CODEC.parse(ops,row.getAsJsonObject("router").get(name)).getOrThrow());
    for(var rawPoint:row.getAsJsonArray("points")) {
     var p=rawPoint.getAsJsonArray();var values=new ArrayList<Long>();
     for(var function:functions)values.add(bits(state.sampleBlockValueUncached(function,p.get(0).getAsInt(),p.get(1).getAsInt(),p.get(2).getAsInt())));
     results.add(Map.of("point",p,"float_bits",values));
    }
   } else {
    var sampler=state.createClimateSampler(SamplerContext.EMPTY_UNCACHED);
    for(var rawPoint:row.getAsJsonArray("quarts")) {
     var q=rawPoint.getAsJsonArray();int x=q.get(0).getAsInt(),y=q.get(1).getAsInt(),z=q.get(2).getAsInt();
     var target=sampler.sample(x,y,z);
     var values=List.of(bits(sampler.temperature().sampleValue(x*4,y*4,z*4)),bits(sampler.humidity().sampleValue(x*4,y*4,z*4)),
       bits(sampler.continentalness().sampleValue(x*4,y*4,z*4)),bits(sampler.erosion().sampleValue(x*4,y*4,z*4)),
       bits(sampler.depth().sampleValue(x*4,y*4,z*4)),bits(sampler.weirdness().sampleValue(x*4,y*4,z*4)));
     int index=tree.findValue(target);var selected=parameters.values().get(index);
     results.add(Map.of("quart",q,"block",List.of(x*4,y*4,z*4),"float_bits",values,
       "quantized",List.of(words(target.temperature()),words(target.humidity()),words(target.continentalness()),words(target.erosion()),words(target.depth()),words(target.weirdness())),
       "index",index,"fitness",words(selected.getFirst().fitness(target)),"biome",selected.getSecond().unwrapKey().orElseThrow().identifier().toString()));
    }
   }
   cases.add(Map.of("id",row.get("id").getAsString(),"results",results));
  }
  var pins=new ArrayList<Object>();for(var type:new Class<?>[]{DensityFunction.class,RandomState.class,Climate.class,Climate.Sampler.class,Climate.ParameterList.class,NoiseGeneratorSettings.class})pins.add(loadedClass(type));
  output.println("DENSITY_ROUTER_JSON:"+new Gson().toJson(Map.of("cases",cases,"loaded_classes",pins)));
 }
}
'''

def observe():
    facts=json.loads((WORK/'classpath.json').read_text())
    for item in facts['checkpoint']:
        stat=Path(item['path']).stat()
        if stat.st_size!=item['size'] or stat.st_mtime_ns!=item['mtime_ns']:raise RuntimeError('Verified official classpath checkpoint changed')
    cases=input_cases();token=str(time.time_ns());directory=WORK/('density-router-reference-'+token);directory.mkdir()
    inputs=directory/'inputs.json';inputs.write_bytes(canonical(cases)+b'\n');source=directory/'ReferenceWorldgenDensityRouter.java';source.write_text(SOURCE)
    stdout,receipt=run('density-router-reference-java-'+token,[JAVA,'-Xmx512m','--source','25','--class-path',':'.join(facts['classpath']),source,inputs],60)
    lines=[s[len('DENSITY_ROUTER_JSON:'):] for s in stdout.splitlines() if s.startswith('DENSITY_ROUTER_JSON:')]
    if len(lines)!=1:raise RuntimeError('Actual Java router observation missing or duplicated')
    observations=json.loads(lines[0])
    with zipfile.ZipFile(facts['classpath'][0]) as jar:
        for pin in observations['loaded_classes']:
            if hashlib.sha256(jar.read(pin['member'])).hexdigest()!=pin['sha256']:raise RuntimeError('Loaded official class bytes differ')
    result={'schema':1,'pin':'26.3','status':'observed','inputs':cases,'observations':observations,
      'official_classpath':facts,'source':fingerprint(source),'executed_source':str(source.relative_to(ROOT)),
      'execution':receipt,'input':fingerprint(inputs),'helper':fingerprint(Path(__file__).resolve()),
      'scope':'Actual pinned compiler/sampler for supported eight-root loaded inputs including original sloped_cheese final-density predecessor and actual unblended Overworld six-axis sampler/quantizer/preset resolver. Eight-root inputs explicitly select base3d or sloped_cheese as final input and a custom supported surface gradient; no shipped final-density or normal population claim.'}
    OUTPUT.write_bytes(canonical(result)+b'\n')
    write_json(ROOT/'evidence/worldgen-density-router-reference.json',{'status':'observed','pin':'26.3','reference':fingerprint(OUTPUT),'source':fingerprint(source),'execution':receipt,'cases':len(cases),'scope':result['scope']})
    return {'status':'observed','cases':len(cases),'seconds':receipt['seconds']}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--observe',required=True,action='store_true');parser.parse_args();print(json.dumps(observe(),sort_keys=True))
