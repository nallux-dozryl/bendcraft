#!/usr/bin/env python3
"""Observe actual pinned 26.3 spline codec, range, and compiled sampling."""
from __future__ import annotations
import argparse, hashlib, json, time, zipfile
from pathlib import Path
from reference_inventory import ROOT, JAVA, fingerprint, write_json
from reference_superflat_probe import WORK, run

OUTPUT=ROOT/'reference/worldgen_density_spline.json'
POINTS=[[-8,0,-8],[-4,1,4],[-2,2,-2],[-1,3,1],[0,4,0],[1,5,-1],[2,6,2],[4,7,-4],[8,8,8],
        [16777217,-65,-16777217],[-2147483648,2147483647,2147483647],[0,4,0]]

def gradient(axis='x'):
    return {'type':'minecraft:gradient','axis':axis,'from_coordinate':-4,'to_coordinate':4,'from_value':-2.0,'to_value':2.0}
def point(location,value,derivative=0.0):
    return {'location':location,'value':value,'derivative':derivative}
def multi(coordinate,points):return {'coordinate':coordinate,'points':points}
def spline(tree):return {'type':'minecraft:spline','spline':tree}
def binary(kind,left,right):return {'type':'minecraft:'+kind,'left':left,'right':right}

def input_cases():
    nested=multi(gradient('z'),[point(-1,-3,0.125),point(0,4,-0.0),point(1,8,-0.25)])
    entries=[
      ('constant-negative-zero',spline(-0.0)),
      ('single-zero-derivative',spline(multi(gradient(),[point(0,-0.0,-0.0)]))),
      ('single-positive-derivative',spline(multi(gradient(),[point(0,-2,0.75)]))),
      ('single-negative-derivative',spline(multi(gradient(),[point(0,2,-0.75)]))),
      ('three-points',spline(multi(gradient(),[point(-1,2,0.25),point(0,-0.0,0),point(1,7,-1)]))),
      ('hermite-rounding',spline(multi(gradient(),[point(-1,0.1,0.33333334),point(1,0.3,-0.14285715)]))),
      ('nested-distinct-coordinate',spline(multi(gradient(),[point(-1,nested,0.5),point(0,-0.0,0),point(1,nested,-0.5)]))),
      ('nested-same-coordinate',spline(multi(gradient(),[point(-1,multi(gradient(),[point(-2,1,1),point(2,3,-1)]),0.5),point(1,2,-0.5)]))),
      ('unsorted-codec-accepted',spline(multi(gradient(),[point(1,3,0.5),point(-1,1,0.5),point(0,2,0.5)]))),
      ('duplicate-codec-accepted',spline(multi(gradient(),[point(-1,1,0.5),point(0,2,0.5),point(0,9,-0.5),point(1,3,0.5)]))),
      ('nan-coordinate-last-zero-derivative',spline(multi(binary('div',0,0),[point(-1,1,1),point(1,-0.0,-0.0)]))),
      ('nan-coordinate-last-nonzero-derivative',spline(multi(binary('div',0,0),[point(-1,1,1),point(1,2,1)]))),
      ('infinite-coordinate-zero-derivative',spline(multi(binary('div',1,0),[point(-1,1,1),point(1,-0.0,0)]))),
      ('infinite-coordinate-nonzero-derivative',spline(multi(binary('div',1,0),[point(-1,1,1),point(1,2,1)]))),
      ('range-conservative-overshoot',spline(multi(0,[point(-1,0,8),point(1,0,-8)]))),
    ]
    cases=[{'id':name,'seed':'0','expression_json':json.dumps(expression,separators=(',',':')),'points':POINTS} for name,expression in entries]
    tokens=['0','-0','0.1','1.000000059604644775390625','1.000000059604644775390626',
      '3.4028234663852886e38','3.4028235677973367e38','1e40','-1e40','1e-45','7e-46','8e-46','-1e-50']
    for token in tokens:
        cases.append({'id':'float-token-'+token,'seed':'0','expression_json':'{"type":"minecraft:spline","spline":'+token+'}','points':[[0,0,0]]})
    for seed in ['0','1','9223372036854775808','18446744073709551615']:
        for key in ['overworld/offset','overworld/factor','overworld/jaggedness']:
            cases.append({'id':key,'seed':seed,'expression_json':json.dumps('minecraft:'+key),'points':POINTS})
    return cases

def refusal_cases():
    return [
      {'id':'empty-points','expression_json':json.dumps(spline(multi(0,[])))},
      {'id':'missing-derivative','expression_json':'{"type":"minecraft:spline","spline":{"coordinate":0,"points":[{"location":0,"value":0}]}}'},
      {'id':'missing-coordinate','expression_json':'{"type":"minecraft:spline","spline":{"points":[{"location":0,"value":0,"derivative":0}]}}'},
      {'id':'invalid-value-kind','expression_json':'{"type":"minecraft:spline","spline":true}'},
    ]

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
import net.minecraft.world.level.levelgen.densityfunction.op.SplineFunction;
import net.minecraft.util.CubicSpline;
import net.minecraft.util.Interval;
class ReferenceWorldgenDensitySpline {
 static long word(float x){return Integer.toUnsignedLong(Float.floatToRawIntBits(x));}
 static Map<String,Object> pin(Class<?> type) throws Exception {
  var member=type.getName().replace('.','/')+".class";
  try(var stream=type.getResourceAsStream("/"+member)) {
   var bytes=stream.readAllBytes();return Map.of("member",member,"bytes",bytes.length,
    "sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)),
    "code_source",type.getProtectionDomain().getCodeSource().getLocation().toString());
  }
 }
 public static void main(String[] args) throws Exception {
  var output=System.out;var input=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonObject();
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();var lookup=VanillaRegistries.createWorldLookup();
  var ops=RegistryOps.create(JsonOps.INSTANCE,lookup);
  var settings=lookup.lookupOrThrow(Registries.NOISE_SETTINGS).getOrThrow(NoiseGeneratorSettings.OVERWORLD).value();
  var rows=new ArrayList<Object>();
  for(var item:input.getAsJsonArray("cases")) {
   var row=item.getAsJsonObject();var expression=JsonParser.parseString(row.get("expression_json").getAsString());
   var function=DensityFunction.CODEC.parse(ops,expression).getOrThrow();var range=function.range();
   var state=RandomState.create(lookup.lookupOrThrow(Registries.NOISE),Long.parseUnsignedLong(row.get("seed").getAsString()),settings);
   var bits=new ArrayList<Long>();
   for(var entry:row.getAsJsonArray("points")) {var p=entry.getAsJsonArray();
    bits.add(word(state.sampleBlockValueUncached(function,p.get(0).getAsInt(),p.get(1).getAsInt(),p.get(2).getAsInt())));
   }
   rows.add(Map.of("id",row.get("id").getAsString(),"seed",row.get("seed").getAsString(),
    "expression_json",row.get("expression_json").getAsString(),"points",row.get("points"),"bits",bits,
    "range",Map.of("nai",range.isNaI(),"min_bits",word(range.min()),"max_bits",word(range.max()))));
  }
  var refusals=new ArrayList<Object>();
  for(var item:input.getAsJsonArray("refusals")) {var row=item.getAsJsonObject();
   var decoded=DensityFunction.CODEC.parse(ops,JsonParser.parseString(row.get("expression_json").getAsString()));
   refusals.add(Map.of("id",row.get("id").getAsString(),"accepted",decoded.result().isPresent(),"error",decoded.error().map(Object::toString).orElse("")));
  }
  var classes=new ArrayList<Object>();
  for(var name:List.of("net.minecraft.util.CubicSpline","net.minecraft.util.CubicSpline$Multipoint",
    "net.minecraft.util.CubicSpline$Multipoint$Point","net.minecraft.util.CubicSpline$Constant",
    "net.minecraft.world.level.levelgen.densityfunction.op.SplineFunction",
    "net.minecraft.world.level.levelgen.densityfunction.op.SplineFunction$Sampler",
    "net.minecraft.world.level.levelgen.densityfunction.op.SplineFunction$PointSplineInput",
    "net.minecraft.util.Interval"))classes.add(pin(Class.forName(name)));
  output.println("SPLINE_JSON:"+new Gson().toJson(Map.of("cases",rows,"refusals",refusals,"loaded_classes",classes)));
 }
}
'''

def observe():
    facts=json.loads((WORK/'classpath.json').read_text())
    for pin in facts['checkpoint']:
        stat=Path(pin['path']).stat()
        if stat.st_size!=pin['size'] or stat.st_mtime_ns!=pin['mtime_ns']:raise RuntimeError('Official classpath checkpoint changed')
    token=str(time.time_ns());inputs={'cases':input_cases(),'refusals':refusal_cases()}
    path=WORK/('spline-input-'+token+'.json');write_json(path,inputs)
    source=WORK/('ReferenceWorldgenDensitySpline-'+token+'.java');source.write_text(SOURCE)
    out,process=run('density-spline-java-observe-'+token,[JAVA,'-Xmx512m','--source','25','--class-path',':'.join(facts['classpath']),source,path],60)
    lines=[s[len('SPLINE_JSON:'):] for s in out.splitlines() if s.startswith('SPLINE_JSON:')]
    if len(lines)!=1:raise RuntimeError('Missing actual Java spline output')
    observations=json.loads(lines[0])
    if any(row['accepted'] for row in observations['refusals']):raise RuntimeError('Expected actual spline codec refusal was accepted')
    with zipfile.ZipFile(facts['classpath'][0]) as jar:
        for pin in observations['loaded_classes']:
            if hashlib.sha256(jar.read(pin['member'])).hexdigest()!=pin['sha256']:raise RuntimeError('Loaded class identity mismatch')
    result={'schema':1,'pin':'26.3','status':'observed','observations':observations,'classpath_checkpoint':facts,
      'executed_source':{'path':str(source.relative_to(ROOT)),**fingerprint(source)},'executions':[process],
      'helper':fingerprint(Path(__file__).resolve()),
      'scope':'Actual spline FLOAT codec, raw ranges and compiled uncached block values, including nested registry/noise coordinates. No full chunk population or interpolation-volume claim.'}
    write_json(OUTPUT,result)
    write_json(ROOT/'evidence/worldgen-density-spline-reference.json',{
      'schema':1,'pin':'26.3','status':'passed','reference':fingerprint(OUTPUT),'executions':[process],
      'cases':len(observations['cases']),'samples':sum(len(c['bits']) for c in observations['cases']),
      'refusals':len(observations['refusals']),'loaded_classes':observations['loaded_classes'],'scope':result['scope']})
    return {'status':'observed','cases':len(observations['cases']),'samples':sum(len(c['bits']) for c in observations['cases']),'seconds':process['seconds']}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--observe',required=True,action='store_true');parser.parse_args()
    print(json.dumps(observe(),sort_keys=True))
