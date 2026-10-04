#!/usr/bin/env python3
"""Observe actual 26.3 seed, base-density and climate/biome producers.

Python selects inputs and checks provenance. Java's retained production classes
own every expected random word, scalar, density and biome result.
"""
from __future__ import annotations
import argparse, hashlib, json, time, zipfile
from pathlib import Path
from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_superflat_probe import WORK, run

OUTPUT = ROOT / 'reference/normal_overworld_noise.json'
SEEDS = ['0', '1', '9223372036854775808', '18446744073709551615']
NAMES = ['', 'a', 'abc', 'message digest', 'abcdefghijklmnopqrstuvwxyz',
         'minecraft:terrain', 'octave_-7', 'minecraft:temperature']
NAMES += ['a' * n for n in (55, 56, 63, 64, 65, 127, 128, 129, 4097)]
MEMBERS = ('data/minecraft/worldgen/noise_settings/overworld.json',
           'data/minecraft/worldgen/density_function/overworld/base_3d_noise.json',
           'data/minecraft/worldgen/density_function/overworld/sloped_cheese.json',
           'data/minecraft/worldgen/multi_noise_biome_source_parameter_list/overworld.json')

SOURCE = r'''import java.util.*;
import java.nio.file.*;
import java.lang.reflect.*;
import java.util.concurrent.atomic.AtomicLong;
import java.security.MessageDigest;
import com.google.gson.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.data.registries.VanillaRegistries;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.*;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.levelgen.*;
import net.minecraft.world.level.levelgen.synth.*;
import net.minecraft.world.level.levelgen.densityfunction.*;
import net.minecraft.world.level.biome.*;

class ReferenceNormalNoiseProbe {
  static Object field(Object object,String name) throws Exception {
    Class<?> type=object.getClass();
    while(type!=null) {
      try { var f=type.getDeclaredField(name); f.setAccessible(true); return f.get(object); }
      catch(NoSuchFieldException e) { type=type.getSuperclass(); }
    }
    throw new NoSuchFieldException(name);
  }
  static List<Long> words(long value) { return List.of(value>>>32,value&0xffffffffL); }
  static Map<String,Object> randomState(RandomSource random) throws Exception {
    if(random instanceof LegacyRandomSource)
      return Map.of("kind","legacy","words",words(((AtomicLong)field(random,"seed")).get()));
    var generator=field(random,"randomNumberGenerator");
    return Map.of("kind","xoroshiro","words",List.of(words((long)field(generator,"seedLo")),words((long)field(generator,"seedHi"))));
  }
  static List<Long> floatBits(float[] values) {
    var result=new ArrayList<Long>();
    for(float value:values) result.add(Integer.toUnsignedLong(Float.floatToRawIntBits(value)));
    return result;
  }
  static Map<String,Object> loadedClass(Class<?> type) throws Exception {
    var member=type.getName().replace('.','/')+".class";
    try(var input=type.getResourceAsStream("/"+member)) {
      if(input==null) throw new IllegalStateException("missing loaded class "+member);
      var data=input.readAllBytes();
      return Map.of("member",member,"bytes",data.length,"sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data)),
        "code_source",type.getProtectionDomain().getCodeSource().getLocation().toString());
    }
  }
  public static void main(String[] args) throws Exception {
    var output=System.out;
    var input=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonObject();
    SharedConstants.tryDetectVersion(); Bootstrap.bootStrap();
    var lookup=VanillaRegistries.createWorldLookup();
    var settings=lookup.lookupOrThrow(Registries.NOISE_SETTINGS).getOrThrow(NoiseGeneratorSettings.OVERWORLD).value();
    var density=lookup.lookupOrThrow(Registries.DENSITY_FUNCTION).getOrThrow(ResourceKey.create(Registries.DENSITY_FUNCTION,Identifier.parse("minecraft:overworld/base_3d_noise"))).value();
    var preset=lookup.lookupOrThrow(Registries.MULTI_NOISE_BIOME_SOURCE_PARAMETER_LIST).getOrThrow(ResourceKey.create(Registries.MULTI_NOISE_BIOME_SOURCE_PARAMETER_LIST,Identifier.parse("minecraft:overworld")));
    var biomes=MultiNoiseBiomeSource.createFromPreset(preset);
    var result=new TreeMap<String,Object>();
    var named=new ArrayList<Object>(); var columns=new ArrayList<Object>(); var climate=new ArrayList<Object>(); var perlin=new ArrayList<Object>();
    for(var seedValue:input.getAsJsonArray("seeds")) {
      var seedText=seedValue.getAsString(); long seed=Long.parseUnsignedLong(seedText);
      var state=RandomState.create(lookup.lookupOrThrow(Registries.NOISE),seed,settings);
      for(var legacy:List.of(false,true)) {
        RandomSource root=legacy?new LegacyRandomSource(seed):new XoroshiroRandomSource(seed);
        var factory=root.forkPositional();
        for(var nameValue:input.getAsJsonArray("names")) {
          var name=nameValue.getAsString();
          var source=legacy&&name.equals("minecraft:terrain")?new LegacyRandomSource(seed):factory.fromHashOf(name);
          named.add(Map.of("seed",seedText,"legacy",legacy,"name",name,"random",randomState(source)));
        }
      }
      for(int[] pos:new int[][]{{0,0},{-17,31},{16384,-16384}}) {
        var values=new ArrayList<Long>();
        for(int y=-64;y<=320;y+=8) values.add(Integer.toUnsignedLong(Float.floatToRawIntBits(state.sampleBlockValueUncached(density,pos[0],y,pos[1]))));
        columns.add(Map.of("seed",seedText,"x",pos[0],"z",pos[1],"min_y",-64,"step",8,"count",49,"bits",values));
      }
      var sampler=state.createClimateSampler(SamplerContext.EMPTY_UNCACHED);
      for(int[] q:new int[][]{{0,0,0},{-1,-16,7},{64,16,-64},{4096,80,-4096}}) {
        var point=sampler.sample(q[0],q[1],q[2]);
        float[] raw={sampler.temperature().sampleValue(q[0]*4,q[1]*4,q[2]*4),sampler.humidity().sampleValue(q[0]*4,q[1]*4,q[2]*4),
          sampler.continentalness().sampleValue(q[0]*4,q[1]*4,q[2]*4),sampler.erosion().sampleValue(q[0]*4,q[1]*4,q[2]*4),
          sampler.depth().sampleValue(q[0]*4,q[1]*4,q[2]*4),sampler.weirdness().sampleValue(q[0]*4,q[1]*4,q[2]*4)};
        climate.add(Map.of("seed",seedText,"quart",q,"float_bits",floatBits(raw),"quantized",List.of(words(point.temperature()),words(point.humidity()),words(point.continentalness()),words(point.erosion()),words(point.depth()),words(point.weirdness())),
          "biome_resource_key",biomes.getNoiseBiome(point).unwrapKey().orElseThrow().toString()));
      }
      for(var mode:List.of("perlin","smeared")) {
        var source=new XoroshiroRandomSource(seed).forkPositional().fromHashOf("minecraft:terrain");
        var before=randomState(source);
        PerlinNoise noise=mode.equals("perlin")?new PerlinNoise(source):new SmearedPerlinNoise(source,0.5);
        var permutations=new ArrayList<Integer>(); for(byte value:(byte[])field(noise,"perms")) permutations.add(Byte.toUnsignedInt(value));
        var samples=new ArrayList<Object>();
        for(double[] p:new double[][]{{0,0,0},{0.1,-0.1,0.5},{-17.5,-64.25,31.75},{16777216.25,-1,0.125},{-16777216.25,320.5,-16384.75}})
          samples.add(Map.of("coordinate_bits",List.of(words(Double.doubleToRawLongBits(p[0])),words(Double.doubleToRawLongBits(p[1])),words(Double.doubleToRawLongBits(p[2]))),"bits",Integer.toUnsignedLong(Float.floatToRawIntBits(noise.get(p[0],p[1],p[2])))));
        perlin.add(Map.of("seed",seedText,"mode",mode,"fudge_bits",words(Double.doubleToRawLongBits(0.5)),"before",before,"after",randomState(source),"offset_bits",List.of(words(Double.doubleToRawLongBits((double)field(noise,"offsetX"))),words(Double.doubleToRawLongBits((double)field(noise,"offsetY"))),words(Double.doubleToRawLongBits((double)field(noise,"offsetZ")))),"permutation",permutations,"samples",samples));
      }
    }
    var hashes=new ArrayList<Object>();
    for(var nameValue:input.getAsJsonArray("names")) {
      var name=nameValue.getAsString(); var seed=RandomSupport.seedFromHashOf(name);
      hashes.add(Map.of("name",name,"words",List.of(words(seed.seedLo()),words(seed.seedHi()))));
    }
    var pins=new ArrayList<Object>();
    for(var type:new Class<?>[]{RandomState.class,RandomSupport.class,XoroshiroRandomSource.class,Xoroshiro128PlusPlus.class,GradientNoise.class,PerlinNoise.class,SmearedPerlinNoise.class,BlendedNoise.class,NoiseStack.class,Climate.class,MultiNoiseBiomeSource.class,NoiseGeneratorSettings.class,VanillaRegistries.class}) pins.add(loadedClass(type));
    result.put("named",named); result.put("hashes",hashes); result.put("columns",columns); result.put("climate",climate); result.put("perlin",perlin); result.put("loaded_classes",pins);
    result.put("scope","Actual RandomState base_3d_noise scalar columns and actual climate/preset-biome calls; no chunk filling, final-density parity, surface, aquifer, feature, structure or spawn selection claim");
    output.println("NORMAL_NOISE_JSON:"+new Gson().toJson(result));
  }
}
'''

def observe():
    facts=json.loads((WORK/'classpath.json').read_text())
    for item in facts['checkpoint']:
        path=Path(item['path']); stat=path.stat()
        if stat.st_size != item['size'] or stat.st_mtime_ns != item['mtime_ns']:
            raise RuntimeError('Verified official classpath checkpoint changed')
    token=str(time.time_ns())
    source=WORK/('ReferenceNormalNoiseProbe-'+token+'.java'); source.write_text(SOURCE)
    input_file=WORK/('normal-noise-input-'+token+'.json')
    write_json(input_file,{'seeds':SEEDS,'names':NAMES})
    stdout,receipt=run('normal-noise-observe-'+token,[JAVA,'--source','25','--class-path',':'.join(facts['classpath']),source,input_file],30)
    matches=[line[len('NORMAL_NOISE_JSON:'):] for line in stdout.splitlines() if line.startswith('NORMAL_NOISE_JSON:')]
    if len(matches)!=1: raise RuntimeError('Actual normal-noise output missing or duplicated')
    observations=json.loads(matches[0])
    if len(observations['columns']) != 12 or any(len(c['bits'])!=49 for c in observations['columns']):
        raise RuntimeError('Actual production column count differs')
    if len(observations['named']) != len(SEEDS)*2*len(NAMES): raise RuntimeError('Named stream count differs')
    with zipfile.ZipFile(facts['classpath'][0]) as jar:
        for pin in observations['loaded_classes']:
            if hashlib.sha256(jar.read(pin['member'])).hexdigest()!=pin['sha256']:
                raise RuntimeError('Loaded class bytes differ from verified official jar')
    entries={}
    install=Path.home()/'Library/Application Support/minecraft/versions/26.3/26.3.jar'
    with zipfile.ZipFile(install) as jar:
        for member in MEMBERS:
            data=jar.read(member)
            entries[member]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'json':json.loads(data)}
    result={'schema':1,'pin':'26.3','status':'observed','scope':observations.pop('scope'),
        'input':{'seeds':SEEDS,'names':NAMES},'observations':observations,
        'observations_sha256':hashlib.sha256(canonical(observations)).hexdigest(),
        'installed_entries':entries,'source':fingerprint(source),'execution':receipt,
        'official_classpath':facts,'bend_parity_executed':False}
    write_json(OUTPUT,result)
    write_json(ROOT/'evidence/normal-overworld-noise-reference.json',{
        'status':'observed','pin':'26.3','reference':fingerprint(OUTPUT),'execution':receipt,
        'actual_columns':len(observations['columns']),'column_samples':588,
        'actual_climate_biomes':len(observations['climate']),
        'actual_perlin_constructors':len(observations['perlin']),
        'scope':result['scope'],'bend_parity_executed':False})
    return {'status':'observed','reference':str(OUTPUT),'seconds':receipt['seconds']}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--observe',action='store_true',required=True)
    parser.parse_args()
    print(json.dumps(observe(),sort_keys=True))
