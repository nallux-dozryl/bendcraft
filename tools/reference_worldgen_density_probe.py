#!/usr/bin/env python3
"""Observe pinned compiled density expressions and seeded NormalNoise in Java.

Every expected scalar comes from the loaded production codec/compiler/sampler.
No host approximation, density interpreter or new process framework is used.
"""
from __future__ import annotations
import argparse, hashlib, json, time, zipfile
from pathlib import Path
from reference_inventory import ROOT, JAVA, fingerprint, write_json
from reference_superflat_probe import WORK, run

OUTPUT=ROOT/'reference/worldgen_density.json'
NUMBERS=['0','-0','0.1','-0.1','1.00000000000000011102230246251565404236316680908203125',
 '1.00000000000000011102230246251565404236316680908203126',
 '9007199254740991','9007199254740992','9007199254740993','-9007199254740993',
 '1.7976931348623157e308','1.7976931348623159e308','1e309','-1e309',
 '2.2250738585072014e-308','2.225073858507201e-308','5e-324','2e-324','3e-324',
 '1e-384','-1e-384','1.2453007926713473','0.9494731054427978','0.8880832896205223',
 '1.063180125160734','0.9147152149950137','1.0383104856073737','9.999999747378752e-6']
POINTS=[[0,-64,0],[0,-61,0],[0,0,0],[1,1,1],[-1,-1,-1],[-17,31,127],[31,320,-17],
 [16384,80,-16384],[16777217,-65,-16777217],[-2147483648,2147483647,2147483647],
 [0,-64,0],[0,0,0]]

def unary(kind,value):return {'type':'minecraft:'+kind,'input':value}
def binary(kind,left,right):return {'type':'minecraft:'+kind,'left':left,'right':right}
def gradient(axis='y',bottom=-64,top=320,first=1.5,last=-1.5):
    return {'type':'minecraft:gradient','axis':axis,'from_coordinate':bottom,'to_coordinate':top,'from_value':first,'to_value':last}

def input_cases():
    cases=[]
    for seed in ['0','1','9223372036854775808','18446744073709551615']:
        for key in ['shift_x','shift_z','overworld/base_3d_noise','overworld/temperature','overworld/vegetation',
                    'overworld/continents','overworld/erosion','overworld/ridges','overworld/ridges_folded']:
            cases.append({'id':key,'seed':seed,'expression':'minecraft:'+key,'points':POINTS})
    expressions=[('gradient-y',gradient()),('gradient-x',gradient('x')),('gradient-z',gradient('z')),
      ('gradient-reversed',gradient('y',320,-64,-1.5,1.5)),
      ('gradient-int-wrap',gradient('x',-2147483648,2147483647,1.0,-1.0)),
      ('clamp',{'type':'minecraft:clamp','input':gradient('x',-1,1,-3.0,3.0),'min':-0.5,'max':0.5}),
      ('range-choice',{'type':'minecraft:range_choice','input':gradient('x',-1,1,-1.0,1.0),'min_inclusive':0.0,'max_exclusive':1.0,'when_in_range':2.0,'when_out_of_range':-0.0}),
      ('lerp-zero',{'type':'minecraft:lerp','alpha':0.0,'first':-0.0,'second':3.0}),
      ('lerp-one',{'type':'minecraft:lerp','alpha':1.0,'first':3.0,'second':-0.0}),
      ('lerp-gradient',{'type':'minecraft:lerp','alpha':gradient('x',-1,1,0.0,1.0),'first':gradient(),'second':gradient('z')}),
      ('add',binary('add',gradient(),gradient('z'))),('sub',binary('sub',gradient(),gradient('z'))),
      ('mul-generic',binary('mul',gradient('x',0,1,-0.0,1.0),gradient('z',0,1,-1.0,-1.0))),
      ('mul-constant-left-zero',binary('mul',-0.0,gradient('z',0,1,-1.0,-1.0))),
      ('mul-constant-right-zero',binary('mul',gradient('z',0,1,-1.0,-1.0),-0.0)),
      ('sub-right-negative-zero',binary('sub',gradient('x',0,1,-0.0,1.0),-0.0)),
      ('sub-both-zero',binary('sub',-0.0,0.0)),
      ('noise-exact-scale',{'type':'minecraft:noise','noise':'minecraft:ridge','xz_scale':0.10000000000000002,'y_scale':-0.3}),
      ('noise-shifted-xyz',{'type':'minecraft:noise','noise':'minecraft:ridge','xz_scale':0.1,'y_scale':0.2,'shift_x':gradient('x'),'shift_y':gradient('y'),'shift_z':gradient('z')})]
    for kind in ['abs','square','cube','half_negative','quarter_negative','squeeze','negate']:
        expressions.append((kind,unary(kind,gradient('x',-1,1,-3.0,3.0))))
        expressions.append((kind+'-negative-zero',unary(kind,-0.0)))
    for name,expression in expressions:cases.append({'id':name,'seed':'0','expression':expression,'points':POINTS})
    return cases

JAVA_SOURCE=r'''import java.util.*;
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
EXTRA_IMPORTS
class ReferenceWorldgenDensityProbe {
 EXTRA_HELPERS
 static List<Long> densityWords(long value) { return List.of(value>>>32,value&0xffffffffL); }
 static Map<String,Object> densityLoadedClass(Class<?> type) throws Exception {
  var member=type.getName().replace('.','/')+".class";
  try(var input=type.getResourceAsStream("/"+member)) {
   if(input==null)throw new IllegalStateException("Missing loaded class "+member);
   var data=input.readAllBytes();return Map.of("member",member,"bytes",data.length,
    "sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data)),
    "code_source",type.getProtectionDomain().getCodeSource().getLocation().toString());
  }
 }
 public static void main(String[] args) throws Exception {
  var output=System.out;var input=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonObject();
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();var lookup=VanillaRegistries.createWorldLookup();
  var ops=RegistryOps.create(JsonOps.INSTANCE,lookup);
  var settings=lookup.lookupOrThrow(Registries.NOISE_SETTINGS).getOrThrow(NoiseGeneratorSettings.OVERWORLD).value();
  var numbers=new ArrayList<Object>();
  for(var token:input.getAsJsonArray("numbers"))numbers.add(Map.of("token",token.getAsString(),"bits",densityWords(Double.doubleToRawLongBits(Double.parseDouble(token.getAsString())))));
  var densities=new ArrayList<Object>();
  for(var item:input.getAsJsonArray("densities")) {
   var row=item.getAsJsonObject();var expression=row.get("expression");
   var function=DensityFunction.CODEC.parse(ops,expression).getOrThrow();
   long seed=Long.parseUnsignedLong(row.get("seed").getAsString());
   var state=RandomState.create(lookup.lookupOrThrow(Registries.NOISE),seed,settings);
   var values=new ArrayList<Long>();
   for(var p:row.getAsJsonArray("points")) {
    var point=p.getAsJsonArray();values.add(Integer.toUnsignedLong(Float.floatToRawIntBits(
     state.sampleBlockValueUncached(function,point.get(0).getAsInt(),point.get(1).getAsInt(),point.get(2).getAsInt()))));
   }
   densities.add(Map.of("id",row.get("id").getAsString(),"seed",row.get("seed").getAsString(),"expression",expression,"points",row.get("points"),"bits",values));
  }
  var classes=new ArrayList<Object>();
  for(var type:new Class<?>[]{DensityFunction.class,DensityFunctions.class,RandomState.class,
    net.minecraft.world.level.levelgen.densityfunction.generator.NoiseFunction.class,
    net.minecraft.world.level.levelgen.densityfunction.generator.GradientFunction.class,
    net.minecraft.world.level.levelgen.densityfunction.op.BinaryFunction.class,
    net.minecraft.world.level.levelgen.densityfunction.op.UnaryFunction.class})classes.add(densityLoadedClass(type));
  output.println("DENSITY_JSON:"+new Gson().toJson(Map.of("numbers",numbers,"densities",densities,
    "density_noise",densityNoiseObserve(input.getAsJsonArray("density_noise")),"loaded_classes",classes)));
 }
}
'''

def actual_run(facts,inputs,source,token):
    input_file=WORK/('density-input-'+token+'.json');write_json(input_file,inputs)
    source_file=WORK/('ReferenceWorldgenDensityProbe-'+token+'.java');source_file.write_text(source)
    output,process=run('density-java-observe-'+token,[JAVA,'-Xmx512m','--source','25','--class-path',':'.join(facts['classpath']),source_file,input_file],60)
    lines=[s[len('DENSITY_JSON:'):] for s in output.splitlines() if s.startswith('DENSITY_JSON:')]
    if len(lines)!=1:raise RuntimeError('Actual Java density output missing or duplicated')
    return json.loads(lines[0]),process,{'path':str(source_file.relative_to(ROOT)),**fingerprint(source_file)}

def observe(retained=None):
    import reference_worldgen_density_noise as DN
    facts=json.loads((WORK/'classpath.json').read_text())
    for item in facts['checkpoint']:
        path=Path(item['path']);s=path.stat()
        if s.st_size!=item['size'] or s.st_mtime_ns!=item['mtime_ns']:raise RuntimeError('Official classpath checkpoint changed')
    noise_batch=DN.input_cases();noise_cases=noise_batch['cases'];noise_members=noise_batch['installed_entries']
    inputs={'numbers':NUMBERS,'densities':input_cases(),'density_noise':noise_cases}
    token=str(time.time_ns())
    source=JAVA_SOURCE.replace('EXTRA_IMPORTS',DN.JAVA_IMPORTS).replace('EXTRA_HELPERS',DN.JAVA_HELPERS)
    if retained is None:
        observations,process,executed=actual_run(facts,inputs,source,token)
        processes=[process];executed_sources=[executed]
    else:
        retained=Path(retained);prior_process=json.loads((retained/'process.json').read_text())
        if prior_process['status']!='passed' or not prior_process['group_absent'] or not prior_process['leader_reaped']:
            raise RuntimeError('Retained Java execution was not complete')
        prior_input=json.loads(Path(prior_process['argv'][-1]).read_text())
        if prior_input['numbers']!=NUMBERS or prior_input['densities']!=inputs['densities']:
            raise RuntimeError('Retained scalar input generation differs')
        original_lines=[s[len('DENSITY_JSON:'):] for s in (retained/'stdout').read_text().splitlines() if s.startswith('DENSITY_JSON:')]
        if len(original_lines)!=1:raise RuntimeError('Retained actual output missing')
        observations=json.loads(original_lines[0])
        old_inputs={row['id']:row for row in prior_input['density_noise']}
        changed=[c for c in noise_cases if old_inputs.get(c['id'])!=c]
        if not changed:raise RuntimeError('No changed reference inputs require a supplement')
        extra,process,executed=actual_run(facts,{'numbers':[],'densities':[],'density_noise':changed},source,token)
        before={p['member']:p for p in observations['density_noise']['loaded_classes']}
        after={p['member']:p for p in extra['density_noise']['loaded_classes']}
        if before!=after:raise RuntimeError('Loaded reference class generation changed between batches')
        rows={r['id']:r for r in observations['density_noise']['cases']}
        rows.update({r['id']:r for r in extra['density_noise']['cases']})
        observations['density_noise']['cases']=[rows[c['id']] for c in noise_cases]
        processes=[prior_process,process]
        prior_source=Path(prior_process['argv'][-2]);executed_sources=[{'path':str(prior_source.relative_to(ROOT)),**fingerprint(prior_source)},executed]
    DN.validate_observations(noise_batch,observations['density_noise'])
    resource_pins={};registry={'densities':{},'noises':{}}
    install=Path.home()/'Library/Application Support/minecraft/versions/26.3/26.3.jar'
    with zipfile.ZipFile(install) as jar:
        for directory,target in [('density_function','densities'),('noise','noises')]:
            prefix='data/minecraft/worldgen/'+directory+'/'
            for member in sorted(n for n in jar.namelist() if n.startswith(prefix) and n.endswith('.json')):
                raw=jar.read(member);key='minecraft:'+member[len(prefix):-5]
                registry[target][key]=json.loads(raw);resource_pins[member]={'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
        member='data/minecraft/worldgen/noise_settings/overworld.json';raw=jar.read(member);settings=json.loads(raw)
        resource_pins[member]={'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
    with zipfile.ZipFile(facts['classpath'][0]) as jar:
        for pin in observations['loaded_classes']:
            if hashlib.sha256(jar.read(pin['member'])).hexdigest()!=pin['sha256']:raise RuntimeError('Loaded official class mismatch')
    refusals=[
      {'id':'missing-density','seed':'0','expression':'bendex:missing','points':[[0,0,0]],'prefix':'fail|missing loaded density definition:'},
      {'id':'cycle','seed':'0','expression':'bendex:a','points':[[0,0,0]],'registry':{'densities':{'bendex:a':'bendex:b','bendex:b':'bendex:a'},'noises':{}},'prefix':'fail|density registry reference cycle at '},
      {'id':'unsupported-final','seed':'0','expression':'minecraft:overworld/final_density','points':[[0,0,0]],'prefix':'fail|density divide/min/max require'},
      {'id':'unsupported-spline','seed':'0','expression':registry['densities']['minecraft:overworld/offset']['input']['second']['right'],
       'points':[[0,0,0]],'prefix':'fail|unsupported density function: minecraft:spline'},
      {'id':'zero-node-budget','seed':'0','expression':0,'points':[[0,0,0]],'limits':{'nodes':0},'prefix':'fail|density DAG exceeds'},
      {'id':'zero-depth','seed':'0','expression':0,'points':[[0,0,0]],'limits':{'compile_depth':0},'prefix':'fail|density expression exceeds'},
      {'id':'sampler-fuel','seed':'0','expression':'minecraft:overworld/ridges','points':[[0,0,0]],'limits':{'sampler_fuel':0},'prefix':'fail|noise permutation random rejection fuel exhausted'},
      {'id':'evaluation-depth','seed':'0','expression':0,'points':[[0,0,0]],'limits':{'depth':0},'prefix':'density|fail:density evaluation exceeds caller depth budget;'}]
    result={'schema':1,'pin':'26.3','status':'observed','observations':observations,'settings':settings,'registry':registry,
      'density_noise_input':noise_cases,'refusals':refusals,'installed_resource_pins':resource_pins,
      'normal_noise_case_resources':noise_members,'classpath_checkpoint':facts,'executions':processes,
      'executed_sources':executed_sources,'helper':fingerprint(Path(__file__).resolve()),
      'scope':'Actual compiled supported scalar density graphs and seeded NormalNoise constructors; does not observe full chunk population, final density, spline/interpolation, aquifers, surfaces, structures or features.'}
    # Complete permutation fixtures belong in the reference; keep their JSON
    # compact while leaving human-readable receipts in evidence.
    OUTPUT.parent.mkdir(parents=True,exist_ok=True)
    OUTPUT.write_text(json.dumps(result,ensure_ascii=False,separators=(',',':'))+'\n')
    write_json(ROOT/'evidence/worldgen-density-reference.json',
      {'status':'passed','pin':'26.3','reference':fingerprint(OUTPUT),'executions':processes,
       'numbers':len(observations['numbers']),'density_graphs':len(observations['densities']),
       'density_samples':sum(len(c['bits']) for c in observations['densities']),
       'normal_noise_cases':len(noise_cases),'scope':result['scope']})
    return {'status':'observed','graphs':len(observations['densities']),'samples':sum(len(c['bits']) for c in observations['densities']),'new_noise_inputs':len(changed) if retained is not None else len(noise_cases),'seconds':process['seconds']}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);mode=parser.add_mutually_exclusive_group(required=True);mode.add_argument('--observe',action='store_true');mode.add_argument('--complete-retained',type=Path);args=parser.parse_args();print(json.dumps(observe(args.complete_retained),sort_keys=True))
