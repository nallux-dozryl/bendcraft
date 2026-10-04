#!/usr/bin/env python3
"""Pinned Java ray clipping, nearest direction, view vector, and reach observations.

Reference extraction only, with actual untouched production Java calls.
--prepare writes source/inputs without executing Java, javac, or javap.
"""
from __future__ import annotations
import argparse
import collections
import hashlib
import itertools
import json
import math
from pathlib import Path
import random
import struct
import subprocess
import zipfile

from reference_block_probe import verified_classpath
from reference_inventory import INSTALL, JAVA, ROOT, canonical, fingerprint, write_json

WORK = ROOT / "build/player-block-interaction-reference"
OUTPUT = ROOT / "reference/player_block_interaction.json"
EVIDENCE = ROOT / "evidence/player-block-interaction-reference.json"
SEED = 263_901_701
OWNERS = ["net.minecraft.core.Direction", "net.minecraft.world.phys.AABB",
          "net.minecraft.world.phys.shapes.VoxelShape", "net.minecraft.world.entity.Entity",
          "net.minecraft.world.entity.player.Player", "net.minecraft.server.level.ServerPlayer",
          "net.minecraft.world.entity.ai.attributes.Attributes"]
SOURCE = r'''import java.io.*;
import java.nio.file.*;
import java.lang.reflect.*;
import java.util.*;
import com.google.gson.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.entity.ai.attributes.*;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.phys.*;
import net.minecraft.world.phys.shapes.*;

public class ReferencePlayerBlockInteractionProbe {
  static final Gson JSON=new Gson();
  static double d(JsonElement x){return Double.longBitsToDouble(Long.parseUnsignedLong(x.getAsString(),16));}
  static float f(JsonElement x){return Float.intBitsToFloat((int)Long.parseLong(x.getAsString(),16));}
  static String db(double x){return String.format(Locale.ROOT,"%016x",Double.doubleToRawLongBits(x));}
  static String fb(float x){return String.format(Locale.ROOT,"%08x",Float.floatToRawIntBits(x));}
  static Vec3 vec(JsonArray a){return new Vec3(d(a.get(0)),d(a.get(1)),d(a.get(2)));}
  static List<String> vbits(Vec3 v){return List.of(db(v.x),db(v.y),db(v.z));}
  static AABB box(JsonArray a){return new AABB(d(a.get(0)),d(a.get(1)),d(a.get(2)),d(a.get(3)),d(a.get(4)),d(a.get(5)));}
  static List<String> bbits(AABB b){return List.of(db(b.minX),db(b.minY),db(b.minZ),db(b.maxX),db(b.maxY),db(b.maxZ));}
  static BlockPos pos(JsonArray a){return new BlockPos(a.get(0).getAsInt(),a.get(1).getAsInt(),a.get(2).getAsInt());}
  static List<AABB> boxes(JsonArray a){List<AABB> r=new ArrayList<>();for(JsonElement e:a)r.add(box(e.getAsJsonArray()));return r;}
  static VoxelShape shape(JsonArray a){
    VoxelShape r=Shapes.empty();
    for(AABB b:boxes(a))r=Shapes.joinUnoptimized(r,Shapes.box(b.minX,b.minY,b.minZ,b.maxX,b.maxY,b.maxZ),BooleanOp.OR);
    return r;
  }
  static Map<String,Object> hit(BlockHitResult h){
    Map<String,Object> r=new TreeMap<>();r.put("hit",h!=null);
    if(h!=null){r.put("face",h.getDirection().name());r.put("location_f64_bits",vbits(h.getLocation()));r.put("inside",h.isInside());r.put("type",h.getType().name());BlockPos p=h.getBlockPos();r.put("position",List.of(p.getX(),p.getY(),p.getZ()));}
    return r;
  }
  static Map<String,Object> reach()throws Exception{
    Map<String,Object> r=new TreeMap<>();
    r.put("attribute_default_f64_bits",db(Attributes.BLOCK_INTERACTION_RANGE.value().getDefaultValue()));
    Field field=ServerPlayer.class.getDeclaredField("CREATIVE_BLOCK_INTERACTION_RANGE_MODIFIER");field.setAccessible(true);
    AttributeModifier m=(AttributeModifier)field.get(null);
    r.put("modifier_amount_f64_bits",db(m.amount()));r.put("modifier_operation",m.operation().name());r.put("modifier_id",m.id().toString());
    AttributeMap attributes=new AttributeMap(Player.createAttributes().build());
    AttributeInstance a=attributes.getInstance(Attributes.BLOCK_INTERACTION_RANGE);
    r.put("actual_player_attribute_base_f64_bits",db(a.getValue()));
    a.addOrUpdateTransientModifier(m);r.put("actual_attribute_with_creative_modifier_f64_bits",db(a.getValue()));
    a.removeModifier(m);r.put("actual_attribute_after_modifier_removal_f64_bits",db(a.getValue()));
    return r;
  }
  static Map<String,Object> observe(JsonObject c)throws Exception{
    JsonObject a=c.getAsJsonObject("input");String op=c.get("operation").getAsString();
    Map<String,Object> r=new TreeMap<>(),expected=new TreeMap<>(),observation=new TreeMap<>();
    r.put("id",c.get("id").getAsString());r.put("expected",expected);r.put("observation",observation);
    switch(op){
      case "direction_nearest":{
        Vec3 v=vec(a.getAsJsonArray("vector_f64_bits"));
        expected.put("face",Direction.getApproximateNearest(v.x,v.y,v.z).name());
        expected.put("float_overload_face",Direction.getApproximateNearest((float)v.x,(float)v.y,(float)v.z).name());
        expected.put("opposite",Direction.getApproximateNearest(v).getOpposite().name());
        observation.put("narrowed_f32_bits",List.of(fb((float)v.x),fb((float)v.y),fb((float)v.z)));
        observation.put("enum_order",Arrays.stream(Direction.values()).map(Enum::name).toList());break;
      }
      case "view_vector":{
        float p=f(a.get("pitch_f32_bits")),y=f(a.get("yaw_f32_bits"));
        expected.put("vector_f64_bits",vbits(Entity.calculateViewVector(p,y)));break;
      }
      case "shape_clip":{
        Vec3 start=vec(a.getAsJsonArray("from_f64_bits")),end=vec(a.getAsJsonArray("to_f64_bits"));
        Vec3 delta=end.subtract(start);VoxelShape s=shape(a.getAsJsonArray("boxes"));
        expected.putAll(hit(s.clip(start,end,pos(a.getAsJsonArray("position")))));
        observation.put("delta_f64_bits",vbits(delta));observation.put("delta_length_squared_f64_bits",db(delta.lengthSqr()));
        observation.put("inside_sample_f64_bits",vbits(start.add(delta.scale(0.001))));
        observation.put("realized_boxes_f64_bits",s.toAabbs().stream().map(ReferencePlayerBlockInteractionProbe::bbits).toList());break;
      }
      case "aabb_clip":{
        expected.putAll(hit(AABB.clip(boxes(a.getAsJsonArray("boxes")),vec(a.getAsJsonArray("from_f64_bits")),vec(a.getAsJsonArray("to_f64_bits")),pos(a.getAsJsonArray("position")))));break;
      }
      case "reach_constants":expected.putAll(reach());break;
      default:throw new IllegalArgumentException(op);
    }
    return r;
  }
  public static void main(String[]args)throws Exception{
    SharedConstants.tryDetectVersion();Bootstrap.bootStrap();
    if(!SharedConstants.getCurrentVersion().id().equals("26.3"))throw new AssertionError("Wrong pin");
    try(BufferedReader in=Files.newBufferedReader(Path.of(args[0]));PrintWriter out=new PrintWriter(Files.newBufferedWriter(Path.of(args[1])))){
      String line;while((line=in.readLine())!=null)out.println(JSON.toJson(observe(JsonParser.parseString(line).getAsJsonObject())));
      if(out.checkError())throw new IOException("Reference write failed");
    }
  }
}
'''

def db(v): return struct.pack(">d", v).hex()
def fb(v): return struct.pack(">f", v).hex()

def generate_inputs():
    result=[]
    def add(op,label,data,*tags):
        result.append({"id":op+":"+label,"operation":op,"input":data,"tags":list(tags)})
    unit=[0.,0.,0.,1.,1.,1.]
    def ray(label,start,end,boxes=None,position=None,tags=()):
        data={"from_f64_bits":list(map(db,start)),"to_f64_bits":list(map(db,end)),
              "position":position or [0,0,0],"boxes":[list(map(db,b)) for b in ([unit] if boxes is None else boxes)]}
        for op in ("shape_clip","aabb_clip"): add(op,label,data,*tags)
    for v in itertools.product((-1.,0.,1.),repeat=3):
        add("direction_nearest","ordinary-"+"-".join(map(str,v)),{"vector_f64_bits":list(map(db,v))},"enum_tie_priority")
    fmin=struct.unpack(">f",bytes.fromhex("00000001"))[0]
    vectors=[[-0.,0.,-0.],[fmin,0.,0.],[2*fmin,0.,0.],[fmin,fmin,fmin],
             [1.,math.nextafter(1.,math.inf),0.],[1.,0.,math.nextafter(1.,math.inf)],
             [1.+2.**-24,1.,0.],[1.+2.**-23,1.,0.],[1e-50,-1e-50,1e-50],[1e300,1e300,0.]]
    for i,v in enumerate(vectors):
        add("direction_nearest","narrow-"+str(i),{"vector_f64_bits":list(map(db,v))},"float_narrowing","minimum_score_gate")
    for p,y in itertools.product([0.,-0.,45.,-45.,90.,-90.,89.99999],[0.,-0.,45.,-45.,90.,-90.,180.,-180.,360.,1e8]):
        add("view_vector",fb(p)+"-"+fb(y),{"pitch_f32_bits":fb(p),"yaw_f32_bits":fb(y)},"actual_entity_view_vector","float_operation_order")
    add("reach_constants","default-and-private-creative-modifier",{},"actual_attribute_calls","private_production_modifier")
    threshold=math.sqrt(1e-7)
    for i,d in enumerate([0.,-0.,1e-7,.0003,math.nextafter(threshold,0.),threshold,math.nextafter(threshold,math.inf),.001,1.]):
        ray("minimum-length-"+str(i),[0.,.5,.5],[d,.5,.5],tags=("squared_length_gate","boundary_start"))
    for axis in range(3):
        for sign in (-1,1):
            for delta in [math.nextafter(1e-7,0.),1e-7,math.nextafter(1e-7,math.inf)]:
                a,b=[.5]*3,[.5]*3;a[axis],b[axis]=-sign*delta/2,sign*delta/2
                a[(axis+1)%3],b[(axis+1)%3]=.25,.75
                bounds=unit.copy()
                if sign<0:bounds[axis],bounds[axis+3]=-1.,0.
                ray("axis-delta-gate-"+str(axis)+"-"+str(sign)+"-"+db(delta),a,b,boxes=[bounds],tags=("component_delta_epsilon","long_transverse_ray"))
            start=[.5]*3;end=[.5]*3
            start[axis]=-1. if sign>0 else 2.;end[axis]=2. if sign>0 else -1.
            ray("ordinary-face-"+str(axis)+"-"+str(sign),start,end,tags=("ordinary_face",))
            for other in [0.,1.,-1e-7,math.nextafter(-1e-7,math.inf),math.nextafter(-1e-7,-math.inf),
                          1.+1e-7,math.nextafter(1.+1e-7,0.),math.nextafter(1.+1e-7,math.inf)]:
                a,b=start.copy(),end.copy();a[(axis+1)%3]=b[(axis+1)%3]=other
                ray("transverse-"+str(axis)+"-"+str(sign)+"-"+db(other),a,b,tags=("strict_transverse_epsilon",))
    for signs in itertools.product((-1,1),repeat=3):
        ray("corner-tie-"+"-".join(map(str,signs)),[-1. if x>0 else 2. for x in signs],
            [2. if x>0 else -1. for x in signs],tags=("exact_face_tie","x_before_y_before_z"))
    for axes in [(0,1),(0,2),(1,2)]:
        a,b=[.5]*3,[.5]*3
        for axis in axes:a[axis],b[axis]=-1.,2.
        ray("edge-tie-"+"-".join(map(str,axes)),a,b,tags=("exact_face_tie",))
    for off in [0.,math.ulp(0.),.000999,.001,math.nextafter(.001,0.),math.nextafter(.001,math.inf),.001001]:
        ray("inside-offset-entry-"+db(off),[-off,.5,.5],[1.-off,.5,.5],tags=("scaled_inside_sample","boundary_half_open"))
        ray("inside-offset-exit-"+db(off),[1.-off,.5,.5],[2.-off,.5,.5],tags=("scaled_inside_sample","boundary_half_open"))
    for delta in [[1.,1.,1.],[-1.,-1.,-1.],[1.,0.,1.],[1.,1.,0.],[1.,1.+2.**-24,0.]]:
        ray("inside-tie-"+"-".join(map(db,delta)),[.5]*3,[.5+x for x in delta],tags=("inside_nearest_float_tie",))
    ray("endpoint-only",[-1.,.5,.5],[0.,.5,.5],tags=("strict_segment_end",))
    ray("empty",[-1.,.5,.5],[2.,.5,.5],boxes=[],tags=("empty_shape",))
    ray("translated",[6.,11.5,-12.5],[9.,11.5,-12.5],position=[7,11,-13],tags=("translated_block_position",))
    ray("bottom-slab",[-1.,.25,.5],[2.,.25,.5],boxes=[[0.,0.,0.,1.,.5,1.]],tags=("shape_reference_only",))
    tied_boxes=[[0.,-1.,0.,1.,1.,1.],[-1.,0.,0.,1.,1.,1.]]
    for i,b in enumerate([tied_boxes,tied_boxes[::-1]]):
        ray("multi-box-equal-distance-"+str(i),[-1.,-1.,.5],[2.,2.,.5],boxes=b,tags=("iterable_order_equal_distance","union_realization"))
    for i,b in enumerate([[[0.,0.,0.,.25,1.,1.],[.75,0.,0.,1.,1.,1.]],
                          [[.75,0.,0.,1.,1.,1.],[0.,0.,0.,.25,1.,1.]]]):
        ray("multi-box-nearest-"+str(i),[-1.,.5,.5],[2.,.5,.5],boxes=b,tags=("iterable_order_nearer_wins","union_realization"))
    rng=random.Random(SEED)
    for i in range(96):
        v=[rng.uniform(-32.,32.) for _ in range(3)]
        add("direction_nearest","random-"+str(i),{"vector_f64_bits":list(map(db,v))},"seeded_random")
        ray("random-"+str(i),[rng.uniform(-2.,2.) for _ in range(3)],[rng.uniform(-2.,2.) for _ in range(3)],tags=("seeded_random",))
    return result

def prepare():
    WORK.mkdir(parents=True,exist_ok=True)
    source,incoming=WORK/"ReferencePlayerBlockInteractionProbe.java",WORK/"inputs.jsonl"
    source.write_text(SOURCE);incoming.write_text("".join(canonical(c).decode()+"\n" for c in generate_inputs()))
    return source,incoming

def inventory(jars):
    classes={};client=INSTALL/"versions/26.3/26.3.jar"
    release=json.loads((ROOT/"reference/release.json").read_text())
    if fingerprint(client)["sha256"]!=release["client"]["sha256"]:raise ValueError("Pinned client checksum mismatch")
    with zipfile.ZipFile(jars[0]) as server,zipfile.ZipFile(client) as local:
        for name in OWNERS:
            entry=name.replace(".","/")+".class";raw=server.read(entry)
            raw_client=local.read(entry)
            if raw!=raw_client:raise ValueError("Installed client/server production class mismatch: "+name)
            text=subprocess.run([str(JAVA.parent/"javap"),"-cp",str(jars[0]),"-c","-p",name],capture_output=True,text=True,check=True,timeout=30).stdout
            (WORK/(name.rsplit(".",1)[-1]+".javap")).write_text(text)
            classes[name]={"server_class_sha256":hashlib.sha256(raw).hexdigest(),
                           "client_class_sha256":hashlib.sha256(raw_client).hexdigest(),
                           "whole_class_identical":raw==raw_client,
                           "complete_bytecode_text_sha256":hashlib.sha256(text.encode()).hexdigest()}
    return classes

def validate(cases):
    by_id={c["id"]:c for c in cases}
    if len(by_id)!=len(cases):raise ValueError("Duplicate fixture ID")
    for c in cases:
        if c["operation"]=="direction_nearest":
            if c["expected"]["face"]!=c["expected"]["float_overload_face"]:raise ValueError("Nearest overload mismatch")
            if c["observation"]["enum_order"]!=["DOWN","UP","NORTH","SOUTH","WEST","EAST"]:raise ValueError("Direction enum changed")
    expected_faces={"ordinary-0.0-0.0-0.0":"NORTH","ordinary-1.0-1.0-1.0":"UP",
                    "ordinary-1.0-0.0-1.0":"SOUTH","ordinary-1.0-1.0-0.0":"UP",
                    "narrow-1":"NORTH","narrow-2":"EAST","narrow-4":"UP","narrow-5":"SOUTH"}
    for label,face in expected_faces.items():
        if by_id["direction_nearest:"+label]["expected"]["face"]!=face:raise ValueError("Nearest targeted observation changed: "+label)
    for c in cases:
        if c["operation"]=="shape_clip" and "squared_length_gate" in c["tags"]:
            length=struct.unpack(">d",bytes.fromhex(c["observation"]["delta_length_squared_f64_bits"]))[0]
            if c["expected"]["hit"]!=(length>=1e-7):raise ValueError("Actual squared-length gate mismatch")
    for op in ("aabb_clip","shape_clip"):
        if by_id[op+":corner-tie-1-1-1"]["expected"]["face"]!="WEST":raise ValueError("AABB tie order changed")
        if by_id[op+":endpoint-only"]["expected"]["hit"]:raise ValueError("Strict segment endpoint changed")
    reach=by_id["reach_constants:default-and-private-creative-modifier"]["expected"]
    if reach["actual_player_attribute_base_f64_bits"]!=db(4.5) or reach["actual_attribute_with_creative_modifier_f64_bits"]!=db(5.) or reach["actual_attribute_after_modifier_removal_f64_bits"]!=db(4.5) or reach["modifier_operation"]!="ADD_VALUE" or reach["modifier_amount_f64_bits"]!=db(.5):
        raise ValueError("Actual default/creative reach changed")
    return {"cases":len(cases),"directed_semantic_assertions":True,"unique_fixture_ids":True}

def probe():
    jars,release=verified_classpath();source,incoming=prepare();cp=":".join(map(str,jars))
    command=[str(JAVA.parent/"javac"),"-cp",cp,"-d",str(WORK),str(source)]
    r=subprocess.run(command,capture_output=True,text=True,timeout=60)
    (WORK/"javac.log").write_text(r.stdout+r.stderr);r.check_returncode()
    runs=[]
    for i in range(2):
        out=WORK/f"actual-{i}.jsonl"
        command=[str(JAVA),"-cp",str(WORK)+":"+cp,"ReferencePlayerBlockInteractionProbe",str(incoming),str(out)]
        r=subprocess.run(command,capture_output=True,text=True,timeout=60)
        (WORK/f"run-{i}.log").write_text(r.stdout+r.stderr);r.check_returncode()
        runs.append({"observations":fingerprint(out),"log":fingerprint(WORK/f"run-{i}.log")})
    if (WORK/"actual-0.jsonl").read_bytes()!=(WORK/"actual-1.jsonl").read_bytes():raise ValueError("Java reruns differ")
    inputs=generate_inputs();observed=[json.loads(l) for l in (WORK/"actual-0.jsonl").read_text().splitlines()]
    if [i["id"] for i in inputs]!=[o["id"] for o in observed]:raise ValueError("Observation order mismatch")
    if any(set(o)!={"id","expected","observation"} for o in observed):raise ValueError("Unexpected observation keys")
    cases=[{**i,**o} for i,o in zip(inputs,observed,strict=True)]
    validation=validate(cases)
    result={"schema_version":1,"pin":"26.3","reference_only":True,"cases":cases,
            "cases_sha256":hashlib.sha256(canonical(cases)).hexdigest(),
            "probe_source_sha256":hashlib.sha256(SOURCE.encode()).hexdigest(),
            "probe_tool_sha256":hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "runtime_executable":fingerprint(JAVA),"server_class_jar_sha256":release["server_bundle"]["nested_server_sha256"],
            "classpath_manifest_sha256":hashlib.sha256(canonical([fingerprint(p) for p in jars])).hexdigest(),
            "classes":inventory(jars),"two_byte_identical_java_runs":runs,"seed":SEED,
            "confidence":"high for recorded actual method calls",
            "scope":["Actual VoxelShape.clip, AABB.clip, Direction.getApproximateNearest, Entity.calculateViewVector.",
                     "Actual Player attribute base and AttributeInstance add/remove calls using reflected production creative modifier.",
                     "No full player pick traversal, interaction packet, digging, placement, or contextual shape behavior inferred."]}
    write_json(OUTPUT,result)
    evidence={"status":"passed","reference":fingerprint(OUTPUT),
              "operation_counts":dict(collections.Counter(c["operation"] for c in cases)),
              "two_byte_identical_java_runs":runs,"java_source":fingerprint(source),"validation":validation}
    write_json(EVIDENCE,evidence);return evidence

def verify():
    jars,release=verified_classpath();r=json.loads(OUTPUT.read_text())
    checks=[r["probe_source_sha256"]==hashlib.sha256(SOURCE.encode()).hexdigest(),
            r["probe_tool_sha256"]==hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            r["schema_version"]==1,r["pin"]=="26.3",r["reference_only"] is True,r["seed"]==SEED,
            set(r["classes"])==set(OWNERS),len(r["two_byte_identical_java_runs"])==2,
            (WORK/"ReferencePlayerBlockInteractionProbe.java").read_text()==SOURCE,
            r["cases_sha256"]==hashlib.sha256(canonical(r["cases"])).hexdigest(),
            [{k:c[k] for k in ("id","operation","input","tags")} for c in r["cases"]]==generate_inputs(),
            r["runtime_executable"]==fingerprint(JAVA),r["server_class_jar_sha256"]==release["server_bundle"]["nested_server_sha256"],
            r["classpath_manifest_sha256"]==hashlib.sha256(canonical([fingerprint(p) for p in jars])).hexdigest(),
            all(run=={"observations":fingerprint(WORK/f"actual-{i}.jsonl"),"log":fingerprint(WORK/f"run-{i}.log")} for i,run in enumerate(r["two_byte_identical_java_runs"]))]
    if not all(checks):raise ValueError("Reference, inputs, source, or pinned artifact changed")
    with zipfile.ZipFile(jars[0]) as server,zipfile.ZipFile(INSTALL/"versions/26.3/26.3.jar") as client:
        for owner,info in r["classes"].items():
            entry=owner.replace(".","/")+".class"
            if hashlib.sha256(server.read(entry)).hexdigest()!=info["server_class_sha256"] or hashlib.sha256(client.read(entry)).hexdigest()!=info["client_class_sha256"]:raise ValueError("Pinned production class changed")
            if server.read(entry)!=client.read(entry) or info["whole_class_identical"] is not True:raise ValueError("Client/server class mismatch")
            if hashlib.sha256((WORK/(owner.rsplit(".",1)[-1]+".javap")).read_bytes()).hexdigest()!=info["complete_bytecode_text_sha256"]:raise ValueError("Retained bytecode inventory changed")
    if (WORK/"actual-0.jsonl").read_bytes()!=(WORK/"actual-1.jsonl").read_bytes():raise ValueError("Java rerun files differ")
    actual=[json.loads(l) for l in (WORK/"actual-0.jsonl").read_text().splitlines()]
    if [{k:c[k] for k in ("id","expected","observation")} for c in r["cases"]]!=actual:raise ValueError("Fixture differs from actual production observations")
    if json.loads(EVIDENCE.read_text())["reference"]!=fingerprint(OUTPUT):raise ValueError("Evidence reference fingerprint mismatch")
    return {"status":"passed","validation":validate(r["cases"]),"pinned_artifacts_verified":True,"inputs_regenerated":True}

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--prepare",action="store_true")
    parser.add_argument("--verify-existing",action="store_true");args=parser.parse_args()
    if args.prepare:
        source,incoming=prepare();print(json.dumps({"status":"prepared","source":str(source),"inputs":str(incoming),
                                                  "cases":len(generate_inputs()),"java_executed":False}))
    else:print(json.dumps(verify() if args.verify_existing else probe(),sort_keys=True))

if __name__=="__main__":main()
