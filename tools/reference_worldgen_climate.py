#!/usr/bin/env python3
"""Observe pinned Java Climate.ParameterList construction and cold/warm search.

No host climate/search implementation: all points, trees and answers are emitted
by actual official 26.3 production classes. Python pins bytes and stores data.
"""
from __future__ import annotations
import argparse, hashlib, json, time, zipfile
from pathlib import Path
from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_superflat_probe import WORK, run
OUTPUT=ROOT/'reference/worldgen_climate.json'
SOURCE=r'''import java.util.*;
import java.nio.file.*;
import java.security.MessageDigest;
import java.lang.reflect.*;
import com.google.gson.*;
import com.mojang.datafixers.util.Pair;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.data.registries.VanillaRegistries;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.*;
import net.minecraft.world.level.biome.*;

class ReferenceWorldgenClimate {
  static Object field(Object object,String name) throws Exception {
    for(Class<?> type=object.getClass();type!=null;type=type.getSuperclass()) {
      try { var f=type.getDeclaredField(name); f.setAccessible(true); return f.get(object); }
      catch(NoSuchFieldException e) {}
    }
    throw new NoSuchFieldException(name);
  }
  static List<Long> words(long value) {return List.of(value>>>32,value&0xffffffffL);}
  static List<Long> interval(Climate.Parameter p) {return List.of(p.min()>>>32,p.min()&0xffffffffL,p.max()>>>32,p.max()&0xffffffffL);}
  static List<Object> space(Climate.ParameterPoint p) {return List.of(interval(p.temperature()),interval(p.humidity()),interval(p.continentalness()),interval(p.erosion()),interval(p.depth()),interval(p.weirdness()),interval(new Climate.Parameter(p.offset(),p.offset())));}
  static Map<String,Object> loadedClass(Class<?> type) throws Exception {
    var member=type.getName().replace('.','/')+".class";
    try(var input=type.getResourceAsStream("/"+member)) {
      var data=input.readAllBytes(); return Map.of("member",member,"bytes",data.length,"sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data)));
    }
  }
  static void tree(Object node,List<Object> rows) throws Exception {
    var bounds=(Climate.Parameter[])field(node,"parameterSpace"); var s=new ArrayList<Object>();for(var p:bounds)s.add(interval(p));
    if(node.getClass().getSimpleName().equals("Leaf")) rows.add(List.of("leaf",(int)field(node,"value"),s));
    else {var children=(Object[])field(node,"children");rows.add(List.of("branch",children.length,s));for(var child:children)tree(child,rows);}
  }
  static Climate.TargetPoint target(long[] p) {return new Climate.TargetPoint(p[0],p[1],p[2],p[3],p[4],p[5]);}
  static Object query(Climate.ParameterList<Integer> list,long[] coords) throws Exception {
    var p=target(coords);var input=new ArrayList<Object>();for(long x:coords)input.add(words(x));
    try {int index=list.findValue(p);return Map.of("target",input,"index",index,"fitness",words(list.values().get(index).getFirst().fitness(p)));}
    catch(Exception e) {return Map.of("target",input,"exception",e.getClass().getName());}
  }
  public static void main(String[] args) throws Exception {
    var output=System.out;SharedConstants.tryDetectVersion();Bootstrap.bootStrap();var lookup=VanillaRegistries.createWorldLookup();
    var holder=lookup.lookupOrThrow(Registries.MULTI_NOISE_BIOME_SOURCE_PARAMETER_LIST).getOrThrow(ResourceKey.create(Registries.MULTI_NOISE_BIOME_SOURCE_PARAMETER_LIST,Identifier.parse("minecraft:overworld")));
    var original=holder.value().parameters().values();var entries=new ArrayList<Object>();var points=new ArrayList<Pair<Climate.ParameterPoint,Integer>>();
    int index=0;for(var pair:original) {entries.add(Map.of("index",index,"space",space(pair.getFirst()),"biome",pair.getSecond().unwrapKey().orElseThrow().identifier().toString()));points.add(Pair.of(pair.getFirst(),index++));}
    var list=new Climate.ParameterList<Integer>(points);var rows=new ArrayList<Object>();tree(field(field(list,"index"),"root"),rows);
    var inputs=new ArrayList<long[]>();inputs.add(new long[]{0,0,0,0,0,0});
    var old=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonObject().getAsJsonObject("observations").getAsJsonArray("climate");
    for(var item:old) {var quant=item.getAsJsonObject().getAsJsonArray("quantized");long[] p=new long[6];for(int i=0;i<6;i++){var w=quant.get(i).getAsJsonArray();p[i]=(w.get(0).getAsLong()<<32)|w.get(1).getAsLong();}inputs.add(p);}
    // Actual parameter endpoints, their immediate neighbours, and a fixed Java
    // random stream provide interval/ordering boundaries without host answers.
    for(int j=0;j<points.size();j+=113) {var p=points.get(j).getFirst();Climate.Parameter[] a={p.temperature(),p.humidity(),p.continentalness(),p.erosion(),p.depth(),p.weirdness()};
      long[] c=new long[6];for(int i=0;i<6;i++)c[i]=(a[i].min()+a[i].max())/2;
      inputs.add(c.clone());for(int i=0;i<6;i++)for(long v:new long[]{a[i].min()-1,a[i].min(),a[i].max(),a[i].max()+1}){var q=c.clone();q[i]=v;inputs.add(q);}}
    var random=new Random(263);for(int j=0;j<256;j++){long[] c=new long[6];for(int i=0;i<6;i++)c[i]=random.nextInt(60001)-30000;inputs.add(c);}
    for(long v:new long[]{Long.MIN_VALUE,Long.MAX_VALUE,0x4000000000000000L,-0x4000000000000000L}){long[] c=new long[6];Arrays.fill(c,v);inputs.add(c);for(int i=0;i<6;i++){var p=new long[6];p[i]=v;inputs.add(p);}}
    var warm=new ArrayList<Object>();var cold=new ArrayList<Object>();
    for(long[] p:inputs) warm.add(query(list,p));
    var cache=(ThreadLocal<?>)field(field(list,"index"),"lastResult");
    for(long[] p:inputs) {cache.remove();cold.add(query(list,p));}
    // Distinct tied leaves show the production cache behaviour independently of
    // the Overworld table's many overlapping points.
    var customPoints=List.of(Pair.of(Climate.parameters(-1,0,0,0,0,0,0),0),Pair.of(Climate.parameters(1,0,0,0,0,0,0),1));
    var custom=new Climate.ParameterList<Integer>(customPoints);var customQueries=new ArrayList<Object>();for(long[] p:new long[][]{{0,0,0,0,0,0},{10000,0,0,0,0,0},{0,0,0,0,0,0},{-10000,0,0,0,0,0},{0,0,0,0,0,0}})customQueries.add(query(custom,p));
    var customEntries=new ArrayList<Object>();for(var pair:customPoints)customEntries.add(Map.of("index",pair.getSecond(),"space",space(pair.getFirst()),"biome","test:"+pair.getSecond()));var customTree=new ArrayList<Object>();tree(field(field(custom,"index"),"root"),customTree);
    var pins=new ArrayList<Object>();for(var name:new String[]{"Climate","Climate$Parameter","Climate$ParameterPoint","Climate$ParameterList","Climate$RTree","Climate$RTree$Node","Climate$RTree$Leaf","Climate$RTree$SubTree","MultiNoiseBiomeSourceParameterList","MultiNoiseBiomeSourceParameterList$Preset","OverworldBiomeBuilder"})pins.add(loadedClass(Class.forName("net.minecraft.world.level.biome."+name)));
    var result=new TreeMap<String,Object>();result.put("key","minecraft:overworld");result.put("definition",Map.of("preset","minecraft:overworld"));result.put("entries",entries);result.put("tree",rows);result.put("warm",warm);result.put("cold",cold);result.put("custom",Map.of("entries",customEntries,"tree",customTree,"queries",customQueries));result.put("loaded_classes",pins);
    output.println("WORLDGEN_CLIMATE_JSON:"+new Gson().toJson(result));
  }
}
'''
def observe():
    facts=json.loads((WORK/'classpath.json').read_text())
    for item in facts['checkpoint']:
        stat=Path(item['path']).stat()
        if stat.st_size!=item['size'] or stat.st_mtime_ns!=item['mtime_ns']:raise RuntimeError('Verified official classpath checkpoint changed')
    token=str(time.time_ns());source=WORK/('ReferenceWorldgenClimate-'+token+'.java');source.write_text(SOURCE)
    stdout,receipt=run('worldgen-climate-java-'+token,[JAVA,'--source','25','--class-path',':'.join(facts['classpath']),source,ROOT/'reference/normal_overworld_noise.json'],30)
    lines=[s[len('WORLDGEN_CLIMATE_JSON:'):] for s in stdout.splitlines() if s.startswith('WORLDGEN_CLIMATE_JSON:')]
    if len(lines)!=1:raise RuntimeError('Actual climate observation missing or duplicated')
    observed=json.loads(lines[0])
    with zipfile.ZipFile(facts['classpath'][0]) as jar:
        for pin in observed['loaded_classes']:
            if hashlib.sha256(jar.read(pin['member'])).hexdigest()!=pin['sha256']:raise RuntimeError('Loaded climate class differs from official verified jar')
    result={'schema':1,'pin':'26.3','status':'observed','observations':observed,'source':fingerprint(source),'execution':receipt,
      'official_classpath':facts,'observations_sha256':hashlib.sha256(canonical(observed)).hexdigest(),
      'scope':'Actual generated Overworld parameter table, default19-child tree and cold/warm ParameterList.findValue queries; no Bend parity or compiled climate graph claim'}
    OUTPUT.write_bytes(canonical(result)+b'\n')
    write_json(ROOT/'evidence/worldgen-climate-reference.json',{'status':'observed','pin':'26.3','reference':fingerprint(OUTPUT),'execution':receipt,
      'entries':len(observed['entries']),'tree_nodes':len(observed['tree']),'cold_queries':len(observed['cold']),'warm_queries':len(observed['warm']),
      'custom_tie_queries':len(observed['custom']['queries']),'scope':result['scope']})
    return {'status':'observed','entries':len(observed['entries']),'tree_nodes':len(observed['tree']),'queries':len(observed['warm']),'seconds':receipt['seconds']}

EXTRA_MAIN=r"""  static Map<String,Object> extra(String key,List<Pair<Climate.ParameterPoint,Integer>> points,List<long[]> targets) throws Exception {
    var list=new Climate.ParameterList<Integer>(points);var entries=new ArrayList<Object>();
    for(var pair:points) entries.add(Map.of("index",pair.getSecond(),"space",space(pair.getFirst()),"biome","test:entry_"+pair.getSecond()));
    var rows=new ArrayList<Object>();tree(field(field(list,"index"),"root"),rows);
    var warm=new ArrayList<Object>();for(var p:targets)warm.add(query(list,p));
    var cold=new ArrayList<Object>();var cache=(ThreadLocal<?>)field(field(list,"index"),"lastResult");
    for(var p:targets){cache.remove();cold.add(query(list,p));}
    return Map.of("key",key,"definition",Map.of("preset","minecraft:overworld"),"entries",entries,"tree",rows,"cold",cold,"warm",warm);
  }
  public static void main(String[] args) throws Exception {
    var targets=new ArrayList<long[]>();
    for(long v:new long[]{-20000,-10000,-5000,-2500,-2001,-2000,-1999,-1,0,1,999,1000,1001,1999,2000,2001,2500,5000,10000,20000,Long.MIN_VALUE,Long.MAX_VALUE})targets.add(new long[]{v,0,0,0,0,0});
    for(long v:new long[]{Long.MIN_VALUE,Long.MAX_VALUE,0x4000000000000000L,-0x4000000000000000L}){var p=new long[6];Arrays.fill(p,v);targets.add(p);}
    var offset=new ArrayList<Pair<Climate.ParameterPoint,Integer>>();
    var zero=Climate.Parameter.point(0);
    offset.add(Pair.of(Climate.parameters(Climate.Parameter.span(-.1f,.1f),zero,zero,zero,zero,zero,.5f),0));
    offset.add(Pair.of(Climate.parameters(.2f,0,0,0,0,0,0),1));
    offset.add(Pair.of(Climate.parameters(Climate.Parameter.span(-1f,1f),zero,zero,zero,zero,zero,1f),2));
    offset.add(Pair.of(Climate.parameters(-.25f,0,0,0,0,0,.25f),3));
    var nineteen=new ArrayList<Pair<Climate.ParameterPoint,Integer>>();var twenty=new ArrayList<Pair<Climate.ParameterPoint,Integer>>();
    for(int j=0;j<20;j++){var p=Climate.parameters((j-10)/32f,(j%3-1)/16f,(j%4-2)/16f,(j%7-3)/32f,0,(j%2-1)/16f,(j%5)/8f);twenty.add(Pair.of(p,j));if(j<19)nineteen.add(Pair.of(p,j));
      targets.add(new long[]{p.temperature().min(),p.humidity().min(),p.continentalness().min(),p.erosion().min(),p.depth().min(),p.weirdness().min()});}
    var singleton=List.of(Pair.of(Climate.parameters(0,0,0,0,0,0,.125f),0));
    var extras=List.of(extra("bendex:offset",offset,targets),extra("bendex:nineteen",nineteen,targets),extra("bendex:twenty",twenty,targets),extra("bendex:singleton",singleton,targets));
    var pins=new ArrayList<Object>();for(var name:new String[]{"Climate","Climate$Parameter","Climate$ParameterPoint","Climate$ParameterList","Climate$RTree","Climate$RTree$Node","Climate$RTree$Leaf","Climate$RTree$SubTree"})pins.add(loadedClass(Class.forName("net.minecraft.world.level.biome."+name)));
    System.out.println("WORLDGEN_CLIMATE_EXTRA_JSON:"+new Gson().toJson(Map.of("extra",extras,"loaded_classes",pins)));
  }
}
"""

def observe_extra():
    existing=json.loads(OUTPUT.read_text());facts=existing['official_classpath']
    for item in facts['checkpoint']:
        stat=Path(item['path']).stat()
        if stat.st_size!=item['size'] or stat.st_mtime_ns!=item['mtime_ns']:raise RuntimeError('Verified classpath changed')
    token=str(time.time_ns());source=WORK/('ReferenceWorldgenClimateExtra-'+token+'.java')
    source.write_text(SOURCE[:SOURCE.index('  public static void main')].replace('class ReferenceWorldgenClimate {','class ReferenceWorldgenClimateExtra {')+EXTRA_MAIN)
    stdout,receipt=run('worldgen-climate-extra-java-'+token,[JAVA,'--source','25','--class-path',':'.join(facts['classpath']),source],15)
    lines=[s[len('WORLDGEN_CLIMATE_EXTRA_JSON:'):] for s in stdout.splitlines() if s.startswith('WORLDGEN_CLIMATE_EXTRA_JSON:')]
    if len(lines)!=1:raise RuntimeError('Actual extra climate output missing or duplicated')
    observed=json.loads(lines[0])
    with zipfile.ZipFile(facts['classpath'][0]) as jar:
        for pin in observed['loaded_classes']:
            if hashlib.sha256(jar.read(pin['member'])).hexdigest()!=pin['sha256']:raise RuntimeError('Loaded climate primitive class differs')
    raw=WORK/('worldgen-climate-extra-observation-'+token+'.json');write_json(raw,{'observations':observed,'source':fingerprint(source),'execution':receipt})
    existing['observations']['extra']=observed['extra'];existing['observations_sha256']=hashlib.sha256(canonical(existing['observations'])).hexdigest()
    existing['additional_observation']={'scope':'Nonzero offsets, singleton and19/20-child construction boundaries from actual Java Climate.ParameterList; original Overworld observation reused unchanged',
      'source':fingerprint(source),'execution':receipt,'raw_receipt':fingerprint(raw),'loaded_classes':observed['loaded_classes']}
    OUTPUT.write_bytes(canonical(existing)+b'\n')
    initial=json.loads((ROOT/'evidence/worldgen-climate-reference.json').read_text());initial['reference']=fingerprint(OUTPUT);write_json(ROOT/'evidence/worldgen-climate-reference.json',initial)
    write_json(ROOT/'evidence/worldgen-climate-extra-reference.json',{'status':'observed','pin':'26.3','reference':fingerprint(OUTPUT),'source':fingerprint(source),
      'execution':receipt,'scenarios':[{'key':x['key'],'entries':len(x['entries']),'tree_nodes':len(x['tree']),'cold_queries':len(x['cold']),'warm_queries':len(x['warm'])} for x in observed['extra']],
      'scope':existing['additional_observation']['scope']})
    return {'status':'observed','scenarios':len(observed['extra']),'queries':sum(len(x['cold'])+len(x['warm']) for x in observed['extra']),'seconds':receipt['seconds']}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);group=parser.add_mutually_exclusive_group(required=True);group.add_argument('--observe',action='store_true');group.add_argument('--observe-extra',action='store_true');args=parser.parse_args();print(json.dumps(observe_extra() if args.observe_extra else observe(),sort_keys=True))
