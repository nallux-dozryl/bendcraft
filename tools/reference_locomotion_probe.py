#!/usr/bin/env python3
"""Extract pinned Mth numerical data and direct locomotion observations."""
from __future__ import annotations
import argparse, collections, copy, hashlib, json, math, random, re, struct, subprocess, time, zipfile
from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_block_probe import verified_classpath

OUTPUT=ROOT/'reference/locomotion.json'
TABLE=ROOT/'generated/reference_mth_sin.f32'
SEED=263_104_04
SOURCE=r'''
import java.io.*;
import java.nio.*;
import java.nio.file.*;
import java.lang.reflect.*;
import java.util.*;
import com.google.gson.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.minecraft.world.entity.Entity;
public class ReferenceLocomotionProbe {
  static final Gson JSON=new Gson();
  static final Method INPUT;
  static {try {INPUT=Entity.class.getDeclaredMethod("getInputVector",Vec3.class,float.class,float.class);INPUT.setAccessible(true);}catch(Exception e){throw new ExceptionInInitializerError(e);}}
  static double d(JsonElement v){return Double.longBitsToDouble(Long.parseUnsignedLong(v.getAsString(),16));}
  static float f(JsonElement v){return Float.intBitsToFloat((int)Long.parseLong(v.getAsString(),16));}
  static String bits(double v){return String.format(Locale.ROOT,"%016x",Double.doubleToRawLongBits(v));}
  static String fbits(float v){return String.format(Locale.ROOT,"%08x",Float.floatToRawIntBits(v));}
  static Vec3 vector(JsonArray a){return new Vec3(d(a.get(0)),d(a.get(1)),d(a.get(2)));}
  static List<String> vectorBits(Vec3 v){return List.of(bits(v.x),bits(v.y),bits(v.z));}
  static Map<String,Object> observe(JsonObject c)throws Exception{
    JsonObject in=c.getAsJsonObject("input");String op=c.get("operation").getAsString();
    Map<String,Object> expected=new TreeMap<>(),observed=new TreeMap<>();
    if(op.equals("sin")||op.equals("cos")){
      double angle=d(in.get("angle")),scaled=angle*10430.378350470453d;
      if(op.equals("cos"))scaled+=16384.0d;
      float answer=op.equals("sin")?Mth.sin(angle):Mth.cos(angle);
      expected.put("f32_bits",fbits(answer));observed.put("index",((long)scaled)&65535L);observed.put("scaled_bits",bits(scaled));
    }else if(op.equals("normalize")){
      Vec3 v=vector(in.getAsJsonArray("vector"));expected.put("vector",vectorBits(v.normalize()));
      observed.put("length_squared",bits(v.lengthSqr()));observed.put("length",bits(v.length()));
    }else if(op.equals("input")){
      Vec3 v=vector(in.getAsJsonArray("vector"));float acceleration=f(in.get("acceleration_f32_bits")),yaw=f(in.get("yaw_f32_bits"));
      Vec3 answer=(Vec3)INPUT.invoke(null,v,acceleration,yaw);expected.put("vector",vectorBits(answer));
      double angle=(double)(yaw*0.017453292f);
      observed.put("length_squared",bits(v.lengthSqr()));observed.put("yaw_radians",bits(angle));
      observed.put("sin_index",((long)(angle*10430.378350470453d))&65535L);observed.put("cos_index",((long)(angle*10430.378350470453d+16384.0d))&65535L);
    }else throw new IllegalArgumentException("Unknown operation");
    return Map.of("id",c.get("id").getAsString(),"expected",expected,"observation",observed);
  }
  public static void main(String[]args)throws Exception{
    SharedConstants.tryDetectVersion();Bootstrap.bootStrap();
    Field field=Mth.class.getDeclaredField("SIN");field.setAccessible(true);float[] table=(float[])field.get(null);
    if(table.length!=65536)throw new AssertionError("Table length");
    ByteBuffer data=ByteBuffer.allocate(262144).order(ByteOrder.LITTLE_ENDIAN);
    for(float value:table)data.putInt(Float.floatToRawIntBits(value));Files.write(Path.of(args[2]),data.array());
    try(BufferedReader r=Files.newBufferedReader(Path.of(args[0]));PrintWriter w=new PrintWriter(Files.newBufferedWriter(Path.of(args[1])))){
      for(String line;(line=r.readLine())!=null;)w.println(JSON.toJson(observe(JsonParser.parseString(line).getAsJsonObject())));
      if(w.checkError())throw new IOException("Observation write failed");
    }
  }
}
'''

def bits(x):return struct.pack('>d',x).hex()
def fbits(x):return struct.pack('>f',x).hex()
def generate_inputs():
    rng=random.Random(SEED);cases=[]
    def add(op,label,data,tags):cases.append({'id':op+':'+label,'operation':op,'input':data,'tags':tags})
    special=['0000000000000000','8000000000000000','0000000000000001','8000000000000001','7ff0000000000000','fff0000000000000','7ff8000000000123','fff8000000000456','7ff0000000000001','7fefffffffffffff','ffefffffffffffff']
    angles=[bits(v) for v in [0.,-0.,1.,-1.,math.pi/2,math.pi,-math.pi,math.tau,360.,-360.,1e300,-1e300,2.**63/10430.378350470453,-2.**63/10430.378350470453]]+special
    for index in [0,1,2,16383,16384,32767,32768,49152,65534,65535,-1,-16384,2**53,2**63,-2**63]:
        center=index/10430.378350470453
        angles.extend(bits(v) for v in [math.nextafter(center,-math.inf),center,math.nextafter(center,math.inf)])
    for i,a in enumerate(angles):
        for op in ['sin','cos']:add(op,'target-'+str(i),{'angle':a},['targeted','index_boundary_or_saturation'])
    for i in range(4096):
        a=f'{rng.getrandbits(64):016x}'
        for op in ['sin','cos']:add(op,'raw-'+str(i),{'angle':a},['raw_bits','saturation_nan_signed_zero'])
    threshold=struct.unpack('>f',bytes.fromhex('3727c5ac'))[0]
    targeted=[[0.,-0.,0.],[1.,0.,0.],[-1.,-0.,0.],[1.,1.,1.],[1e308,-1e308,1e308],[math.ulp(0.),-math.ulp(0.),0.],
              [threshold,0.,0.],[math.nextafter(threshold,0.),0.,0.],[math.nextafter(threshold,math.inf),0.,0.],
              [math.sqrt(1e-7),0.,0.],[math.nextafter(math.sqrt(1e-7),0.),0.,0.],[math.nextafter(math.sqrt(1e-7),math.inf),0.,0.],
              [math.nextafter(1.,0.),0.,0.],[math.nextafter(1.,math.inf),0.,0.],[2.**511,2.**511,0.],[2.**512,0.,0.]]
    vectors=[list(map(bits,v)) for v in targeted]
    vectors.extend([[v,bits(1.),bits(-2.)] for v in special])
    vectors.extend([[bits(1.),v,bits(0.)] for v in special])
    accelerations=['00000000','80000000','3f800000','bf800000','3dcccccd','00000001','7f7fffff','7f800000','ff800000','7fc01234']
    yaws=[fbits(v) for v in [0.,-0.,90.,-90.,180.,270.,360.,45.,1e20,-1e20]]+['7f7fffff','ff7fffff','7f800000','ff800000','7fc01234','00000001']
    for i,v in enumerate(vectors):
        add('normalize','target-'+str(i),{'vector':v},['targeted','threshold_or_nonfinite'])
        for j,yaw in enumerate(yaws):
            add('input',f'target-{i}-{j}',{'vector':v,'acceleration_f32_bits':accelerations[j%len(accelerations)],'yaw_f32_bits':yaw},['targeted','threshold_yaw_rounding_or_nonfinite'])
    for i in range(4096):
        # Finite raw vectors cover subnormal, overflowed length, and exponent gaps.
        v=[f'{rng.getrandbits(64)&0xffefffffffffffff:016x}' for _ in range(3)]
        add('normalize','finite-'+str(i),{'vector':v},['finite_raw_bits','extreme'])
        add('input','finite-'+str(i),{'vector':v,'acceleration_f32_bits':f'{rng.getrandbits(32)&0xff7fffff:08x}','yaw_f32_bits':f'{rng.getrandbits(32)&0xff7fffff:08x}'},['finite_raw_bits','extreme_f32'])
    for i in range(4096):
        v=[bits(rng.uniform(-2.,2.)) for _ in range(3)]
        add('input','ordinary-'+str(i),{'vector':v,'acceleration_f32_bits':fbits(rng.uniform(-1.,1.)),'yaw_f32_bits':fbits(rng.uniform(-1e6,1e6))},['ordinary','float_yaw_rounding'])
    return cases

CLASSES=['net.minecraft.util.Mth','net.minecraft.world.phys.Vec3','net.minecraft.world.entity.Entity',
         'net.minecraft.world.entity.LivingEntity','net.minecraft.world.entity.Avatar','net.minecraft.world.entity.player.Player','net.minecraft.world.entity.ai.attributes.Attributes']
METHODS={'sin','cos','normalize','length','lengthSqr','scale','getInputVector','lambda$static$0',
         'moveRelative','getBlockPosBelowThatAffectsMyMovement','getOnPos','getGravity','getDefaultGravity','getBlockSpeedFactor','omnidirectionalAirMover',
         'travel','travelInAir','travelInFluid','handleRelativeFrictionAndCalculateMovement','computeModifiedFriction','getFrictionInfluencedSpeed','getEffectiveGravity','getFlyingSpeed','getSpeed','handleOnClimbable','shouldDiscardFriction','shouldTravelInFluid','isAffectedByFluids','getEntityBounciness','tick','aiStep','applyInput','getMoveSimulationType','isEffectiveAi','createAttributes'}
def source_inventory(jars):
    r=subprocess.run([str(JAVA.parent/'javap'),'-classpath',str(jars[0]),'-c','-p',*CLASSES],capture_output=True,text=True,check=True)
    (ROOT/'reference/cache/locomotion-bytecode.txt').write_text(r.stdout);records={}
    with zipfile.ZipFile(jars[0]) as archive:
        for owner,chunk in zip(CLASSES,r.stdout.split('Compiled from "')[1:],strict=True):
            entry=owner.replace('.','/')+'.class';methods=[]
            for part in re.split(r'(?=^  (?:public|private|protected|static).*(?:;|\{)$)',chunk,flags=re.M):
                sig=part.splitlines()[0]
                if any(re.search(r'\b'+re.escape(m)+r'\(',sig) for m in METHODS) or sig.strip()=='static {};':
                    methods.append({'signature':sig.strip(),'bytecode_text_sha256':hashlib.sha256(part.encode()).hexdigest(),'direct_call_references':sorted(set(re.findall(r'// (?:InterfaceMethod|Method) (.+)',part)))})
            records[owner]={'class_entry':entry,'class_sha256':hashlib.sha256(archive.read(entry)).hexdigest(),'methods':methods}
    return {'classes':records,'complete_javap_text_sha256':hashlib.sha256(r.stdout.encode()).hexdigest()}

def run_java(inputs,jars,suffix=''):
    directory=ROOT/'reference/extracted/locomotion_probe';directory.mkdir(parents=True,exist_ok=True)
    source=directory/'ReferenceLocomotionProbe.java';source.write_text(SOURCE);classes=directory/'classes';classes.mkdir(exist_ok=True)
    cp=':'.join(map(str,jars));compile_command=[str(JAVA.parent/'javac'),'-cp',cp,'-d',str(classes),str(source)]
    start=time.monotonic();r=subprocess.run(compile_command,capture_output=True,text=True,check=True);compile_seconds=time.monotonic()-start
    compile_log=ROOT/f'reference/cache/locomotion-javac{suffix}.log';compile_log.write_text(r.stdout+r.stderr)
    incoming=ROOT/f'reference/cache/locomotion-input{suffix}.jsonl';outgoing=ROOT/f'reference/cache/locomotion-observed{suffix}.jsonl';table=ROOT/f'reference/cache/locomotion-sin{suffix}.f32'
    incoming.write_text(''.join(canonical(c).decode()+'\n' for c in inputs))
    command=[str(JAVA),'-cp',str(classes)+':'+cp,'ReferenceLocomotionProbe',str(incoming),str(outgoing),str(table)]
    start=time.monotonic();r=subprocess.run(command,capture_output=True,text=True);java_seconds=time.monotonic()-start
    java_log=ROOT/f'reference/cache/locomotion-java{suffix}.log';java_log.write_text(r.stdout+r.stderr);r.check_returncode()
    observed=[json.loads(line) for line in outgoing.read_text().splitlines()];assert [c['id'] for c in observed]==[c['id'] for c in inputs]
    data=table.read_bytes();assert len(data)==262144
    return observed,data,{'compile_command':compile_command,'run_command':command,'compile_seconds':round(compile_seconds,6),'java_seconds':round(java_seconds,6),'compile_log_sha256':fingerprint(compile_log)['sha256'],'java_log_sha256':fingerprint(java_log)['sha256'],'input_jsonl_sha256':fingerprint(incoming)['sha256'],'observation_jsonl_sha256':fingerprint(outgoing)['sha256'],'table_sha256':hashlib.sha256(data).hexdigest()}

def validate(data,observed=None,table=None):
    assert data['pin']=='26.3' and data['schema_version']==1
    assert data['cases_sha256']==hashlib.sha256(canonical(data['cases'])).hexdigest(),'case checksum'
    assert [{k:c[k] for k in ['id','operation','input','tags']} for c in data['cases']]==generate_inputs(),'input regeneration'
    assert data['table']['format']=='65536 IEEE754 binary32 raw words, little-endian, no header'
    assert fingerprint(TABLE)==data['table']['file'],'table checksum'
    if observed is not None:assert [{k:c[k] for k in ['id','expected','observation']} for c in data['cases']]==observed,'independent Java outputs'
    if table is not None:assert TABLE.read_bytes()==table,'independent table bytes'
    return {'case_count':len(data['cases']),'operation_counts':dict(collections.Counter(c['operation'] for c in data['cases'])),'oracle_compared':observed is not None,'table_bytes':TABLE.stat().st_size}

def extract():
    jars,release=verified_classpath();inputs=generate_inputs();observed,table,execution=run_java(inputs,jars)
    TABLE.write_bytes(table);cases=[{**i,**o} for i,o in zip(inputs,observed,strict=True)]
    runtime=subprocess.run([str(JAVA),'-version'],capture_output=True,text=True,check=True)
    data={'schema_version':1,'pin':'26.3','random_input_seed':SEED,'cases':cases,'cases_sha256':hashlib.sha256(canonical(cases)).hexdigest(),
          'server_bundle_sha256':release['server_bundle']['sha256'],'server_class_jar_sha256':release['server_bundle']['nested_server_sha256'],
          'runtime_executable':fingerprint(JAVA),'runtime_version':(runtime.stdout+runtime.stderr).strip().splitlines(),'source':source_inventory(jars),'probe_java_source_sha256':hashlib.sha256(SOURCE.encode()).hexdigest(),
          'classpath_libraries':[fingerprint(p) for p in jars[1:]],'table':{'source_field':'net.minecraft.util.Mth.SIN','format':'65536 IEEE754 binary32 raw words, little-endian, no header','file':fingerprint(TABLE)},
          'scope':'Direct pinned Mth.sin/cos, Vec3.normalize, reflected protected static Entity.getInputVector; no composed locomotion oracle','confidence':'high for recorded numerical cases; no LivingEntity.travel or Player tick implementation claim'}
    write_json(OUTPUT,data);evidence={'status':'passed','reference':fingerprint(OUTPUT),'execution':execution,'validation':validate(data,observed,table)};write_json(ROOT/'evidence/locomotion-reference.json',evidence);return evidence

def verify():
    jars,release=verified_classpath();data=json.loads(OUTPUT.read_text())
    assert data['server_class_jar_sha256']==release['server_bundle']['nested_server_sha256']
    assert data['runtime_executable']==fingerprint(JAVA) and data['source']==source_inventory(jars)
    assert data['probe_java_source_sha256']==hashlib.sha256(SOURCE.encode()).hexdigest()
    observed=[json.loads(line) for line in (ROOT/'reference/cache/locomotion-observed.jsonl').read_text().splitlines()]
    e={'status':'passed','validation':validate(data,observed),'official_class_and_runtime_hashes_checked':True};write_json(ROOT/'evidence/locomotion-reference-validation.json',e);return e

def selftest():
    jars,_=verified_classpath();data=json.loads(OUTPUT.read_text());inputs=generate_inputs()
    one,table1,run1=run_java(inputs,jars,'-selftest1');two,table2,run2=run_java(inputs,jars,'-selftest2');assert one==two and table1==table2
    validate(data,one,table1);validate(data,two,table2);failures=[]
    for label in ['unsealed_result','resealed_result','resealed_table_hash']:
        bad=copy.deepcopy(data)
        if label=='resealed_table_hash':bad['table']['file']['sha256']='0'*64
        else:
            bad['cases'][0]['expected']['f32_bits']='deadbeef'
            if label=='resealed_result':bad['cases_sha256']=hashlib.sha256(canonical(bad['cases'])).hexdigest()
        try:validate(bad,one,table1)
        except AssertionError as err:failures.append({'case':label,'rejected':True,'reason':str(err)})
        else:raise AssertionError('Corruption accepted')
    e={'status':'passed','independent_java_runs':2,'case_count_per_run':len(one),'table_byte_identical':True,'table_sha256':hashlib.sha256(table1).hexdigest(),'failure_injections':failures,'executions':[run1,run2]};write_json(ROOT/'evidence/locomotion-reference-selftest.json',e);return e

def main():
    p=argparse.ArgumentParser();p.add_argument('--verify-existing',action='store_true');p.add_argument('--selftest',action='store_true');a=p.parse_args()
    e=selftest() if a.selftest else verify() if a.verify_existing else extract()
    print(json.dumps({k:v for k,v in e.items() if k not in {'execution','executions'}},indent=2))
if __name__=='__main__':main()
