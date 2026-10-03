#!/usr/bin/env python3
"""Extract exact 26.3 AABB/voxel-axis observations; no game implementation."""
from __future__ import annotations

import argparse
import collections
import copy
import hashlib
import json
import math
import pathlib
import random
import re
import struct
import subprocess
import zipfile

from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_block_probe import verified_classpath

SEED = 263_777_5023
OUTPUT = ROOT / "reference/geometry.json"
SOURCE = r'''
import java.io.*;
import java.nio.file.*;
import java.lang.reflect.*;
import java.util.*;
import com.google.gson.*;
import net.minecraft.SharedConstants;
import net.minecraft.core.Direction.Axis;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.shapes.*;

public class ReferenceGeometryProbe {
    static final Gson JSON = new Gson();
    static final Constructor<ArrayVoxelShape> ARRAY;
    static final Method FIND_INDEX;
    static {
        try {
            ARRAY=ArrayVoxelShape.class.getDeclaredConstructor(DiscreteVoxelShape.class,double[].class,double[].class,double[].class); ARRAY.setAccessible(true);
            FIND_INDEX=VoxelShape.class.getDeclaredMethod("findIndex",Axis.class,double.class); FIND_INDEX.setAccessible(true);
        } catch(ReflectiveOperationException e) { throw new ExceptionInInitializerError(e); }
    }
    static double number(JsonElement e) { return Double.longBitsToDouble(Long.parseUnsignedLong(e.getAsString(), 16)); }
    static String bits(double d) { return String.format(Locale.ROOT, "%016x", Double.doubleToRawLongBits(d)); }
    static double[] vector(JsonArray a) { double[] v=new double[a.size()]; for(int i=0;i<v.length;i++) v[i]=number(a.get(i)); return v; }
    static AABB aabb(JsonArray a) { double[] v=vector(a); return new AABB(v[0],v[1],v[2],v[3],v[4],v[5]); }
    static List<String> box(AABB b) { return List.of(bits(b.minX),bits(b.minY),bits(b.minZ),bits(b.maxX),bits(b.maxY),bits(b.maxZ)); }
    static VoxelShape shape(JsonObject s) {
        switch(s.get("kind").getAsString()) {
            case "empty": return Shapes.empty();
            case "raw_array_box": {
                double[] v=vector(s.getAsJsonArray("box"));
                BitSetDiscreteVoxelShape grid=new BitSetDiscreteVoxelShape(1,1,1);
                grid.fill(0,0,0);
                try { return ARRAY.newInstance(grid,new double[]{v[0],v[3]},new double[]{v[1],v[4]},new double[]{v[2],v[5]}); }
                catch(ReflectiveOperationException e) { throw new IllegalStateException(e); }
            }
            case "box": { double[] v=vector(s.getAsJsonArray("box")); return Shapes.box(v[0],v[1],v[2],v[3],v[4],v[5]); }
            case "union": {
                VoxelShape result=Shapes.empty();
                for(JsonElement b:s.getAsJsonArray("boxes")) {
                    double[] v=vector(b.getAsJsonArray());
                    result=Shapes.joinUnoptimized(result,Shapes.box(v[0],v[1],v[2],v[3],v[4],v[5]),BooleanOp.OR);
                }
                return result;
            }
            default: throw new IllegalArgumentException("Unknown shape kind");
        }
    }
    static Map<String,Object> describe(VoxelShape s) {
        Map<String,Object> r=new TreeMap<>(); r.put("class",s.getClass().getName()); r.put("is_empty",s.isEmpty());
        Map<String,Object> coords=new TreeMap<>();
        for(Axis axis:Axis.values()) { List<String> values=new ArrayList<>(); for(double d:s.getCoords(axis)) values.add(bits(d)); coords.put(axis.name(),values); }
        r.put("coordinate_f64_bits",coords);
        List<List<String>> boxes=new ArrayList<>(); for(AABB b:s.toAabbs()) boxes.add(box(b)); r.put("aabbs_f64_bits",boxes);
        return r;
    }
    static Map<String,Object> observe(JsonObject c) {
        String operation=c.get("operation").getAsString(); JsonObject in=c.getAsJsonObject("input");
        Map<String,Object> r=new TreeMap<>(); r.put("id",c.get("id").getAsString());
        Map<String,Object> expected=new TreeMap<>(), observation=new TreeMap<>(); r.put("expected",expected); r.put("observation",observation);
        try {
            if(operation.startsWith("aabb_")) {
                AABB b=aabb(in.getAsJsonArray("box")); observation.put("normalized_input_box",box(b));
                switch(operation) {
                    case "aabb_construct": expected.put("box",box(b)); break;
                    case "aabb_move": { double[] v=vector(in.getAsJsonArray("vector")); expected.put("box",box(b.move(v[0],v[1],v[2]))); break; }
                    case "aabb_inflate": { double[] v=vector(in.getAsJsonArray("vector")); expected.put("box",box(b.inflate(v[0],v[1],v[2]))); break; }
                    case "aabb_deflate": { double[] v=vector(in.getAsJsonArray("vector")); expected.put("box",box(b.deflate(v[0],v[1],v[2]))); break; }
                    case "aabb_inflate_scalar": expected.put("box",box(b.inflate(number(in.get("scalar"))))); break;
                    case "aabb_deflate_scalar": expected.put("box",box(b.deflate(number(in.get("scalar"))))); break;
                    case "aabb_contains": { double[] v=vector(in.getAsJsonArray("point")); expected.put("boolean",b.contains(v[0],v[1],v[2])); break; }
                    case "aabb_intersects": { AABB other=aabb(in.getAsJsonArray("other")); observation.put("normalized_other_box",box(other)); expected.put("boolean",b.intersects(other)); break; }
                    default: throw new IllegalArgumentException("Unknown AABB operation");
                }
            } else if(operation.equals("java_f64_compare")) {
                double a=number(in.get("a")),b=number(in.get("b"));
                expected.put("equal",a==b); expected.put("less",a<b); expected.put("less_equal",a<=b); expected.put("greater",a>b); expected.put("greater_equal",a>=b);
                expected.put("math_min_bits",bits(Math.min(a,b))); expected.put("math_max_bits",bits(Math.max(a,b)));
            } else if(operation.equals("raw_array_find_index")) {
                VoxelShape s=shape(in.getAsJsonObject("shape")); observation.put("shape",describe(s));
                try { expected.put("integer",FIND_INDEX.invoke(s,Axis.valueOf(in.get("axis").getAsString()),number(in.get("value")))); }
                catch(ReflectiveOperationException e) { throw new IllegalStateException(e); }
            } else if(operation.equals("shape_construct")) {
                expected.put("shape",describe(shape(in.getAsJsonObject("shape"))));
            } else {
                AABB moving=aabb(in.getAsJsonArray("moving_box")); observation.put("normalized_moving_box",box(moving));
                Axis axis=Axis.valueOf(in.get("axis").getAsString()); double delta=number(in.get("delta"));
                if(operation.equals("raw_array_box_collide")||operation.equals("shape_collide")) {
                    VoxelShape s=shape(in.getAsJsonObject("shape")); observation.put("shape",describe(s)); expected.put("f64_bits",bits(s.collide(axis,moving,delta)));
                } else if(operation.equals("raw_array_boxes_collide")||operation.equals("shapes_collide")) {
                    List<VoxelShape> shapes=new ArrayList<>(); List<Object> descriptions=new ArrayList<>();
                    for(JsonElement e:in.getAsJsonArray("shapes")) { VoxelShape s=shape(e.getAsJsonObject()); shapes.add(s); descriptions.add(describe(s)); }
                    observation.put("shapes",descriptions); expected.put("f64_bits",bits(Shapes.collide(axis,moving,shapes,delta)));
                } else throw new IllegalArgumentException("Unknown geometry operation");
            }
        } catch(RuntimeException e) {
            expected.clear(); expected.put("error_class",e.getClass().getName()); expected.put("error_message",String.valueOf(e.getMessage()));
        }
        return r;
    }
    public static void main(String[] args) throws Exception {
        SharedConstants.tryDetectVersion();
        try(BufferedReader in=Files.newBufferedReader(Path.of(args[0])); PrintWriter out=new PrintWriter(Files.newBufferedWriter(Path.of(args[1])))) {
            String line; while((line=in.readLine())!=null) out.println(JSON.toJson(observe(JsonParser.parseString(line).getAsJsonObject())));
            if(out.checkError()) throw new IOException("Geometry observation write failed");
        }
    }
}
'''


def bits(value: float) -> str:
    return struct.pack(">d", value).hex()


def raw_box(values: list[float]) -> dict:
    return {"kind": "raw_array_box", "box": list(map(bits, values))}


def permute_box(values: list[float], axis: int) -> list[float]:
    if axis == 0:
        return values.copy()
    result = values.copy()
    result[0], result[axis] = result[axis], result[0]
    result[3], result[axis + 3] = result[axis + 3], result[3]
    return result


def generate_inputs() -> list[dict]:
    cases = []
    def add(operation: str, label: str, data: dict, tags: list[str]) -> None:
        cases.append({"id": f"{operation}:{label}", "operation": operation, "tags": tags, "input": data})
    unit = [0., 0., 0., 1., 1., 1.]
    eps = 1e-7
    below, above = math.nextafter(eps, 0.), math.nextafter(eps, math.inf)
    targeted = [unit, [3., 2., 1., -3., -2., -1.], [-0., +0., -0., +0., -0., +0.], [0., 0., 0., 0., 0., 0.],
                [0., 0., 0., 0., 1., 1.], [0., 0., 0., eps, eps, eps], [-1e308]*3+[1e308]*3,
                [math.ulp(0.)]*3+[math.ulp(0.)*2]*3, [2.**53]*3+[2.**53+2]*3]
    vectors = [[0., -0., 0.], [1., -1., 0.5], [2., 2., 2.], [-2., -2., -2.], [eps, below, above], [1e308]*3]
    for i, b in enumerate(targeted):
        add("aabb_construct", f"target-{i}", {"box": list(map(bits, b))}, ["targeted", "signed_zero_or_degenerate_or_extreme"])
        for j, v in enumerate(vectors):
            for op in ["aabb_move", "aabb_inflate", "aabb_deflate"]:
                add(op, f"target-{i}-{j}", {"box": list(map(bits, b)), "vector": list(map(bits, v))}, ["targeted"])
            for op in ["aabb_inflate_scalar", "aabb_deflate_scalar"]:
                add(op, f"target-{i}-{j}", {"box": list(map(bits, b)), "scalar": bits(v[0])}, ["targeted"])
    points = [[0.,0.,0.], [1.,.5,.5], [.5,1.,.5], [.5,.5,1.], [.5,.5,.5], [-0.,-0.,-0.],
              [math.nextafter(0.,-math.inf),.5,.5], [math.nextafter(1.,0.),.5,.5], [math.nextafter(1.,math.inf),.5,.5]]
    for i, b in enumerate(targeted[:6]):
        for j, p in enumerate(points):
            add("aabb_contains", f"target-{i}-{j}", {"box": list(map(bits,b)), "point": list(map(bits,p))}, ["targeted", "boundary"])
        for j, other in enumerate(targeted[:6]+[[1.,0.,0.,2.,1.,1.], [.5,.5,.5,.5,.5,.5]]):
            add("aabb_intersects", f"target-{i}-{j}", {"box": list(map(bits,b)), "other": list(map(bits,other))}, ["targeted", "strict_overlap"])
    # Deliberately nonfinite AABB/comparison lane; never classed as finite geometry.
    special = ["0000000000000000", "8000000000000000", "7ff0000000000000", "fff0000000000000", "7ff8000000000001", "fff8000000000002", "7ff0000000000001"]
    for i, a in enumerate(special):
        add("aabb_construct", f"nonfinite-{i}", {"box": [a,bits(0.),bits(0.),bits(1.),bits(1.),bits(1.)]}, ["targeted", "nonfinite_semantics"])
        add("aabb_contains", f"nonfinite-{i}", {"box": list(map(bits,unit)), "point": [a,bits(.5),bits(.5)]}, ["targeted", "nonfinite_semantics"])
        for j, b in enumerate(special):
            add("java_f64_compare", f"special-{i}-{j}", {"a":a,"b":b}, ["targeted", "java_comparison_semantics"])
    # Full one-cell ArrayVoxelShape preserves source coordinates without Shapes.box snapping.
    deltas = [0., -0., math.ulp(0.), -math.ulp(0.), below, -below, eps, -eps, above, -above, .5, -.5, 2., -2.]
    moving_x = [-1., .25, .25, 0., .75, .75]
    gaps = [-above, -eps, -below, -eps/2, -0., 0., math.ulp(0.), eps/2, below, eps, above, .5, 1.]
    overlap_bounds = [(-1.,0.), (-1.,eps), (-1.,above), (-1.,below), (0.,1.), (1.-eps,2.),
                      (math.nextafter(1.-eps,0.),2.), (math.nextafter(1.-eps,math.inf),2.), (1.,2.), (.5,.5)]
    for axis, name in enumerate("XYZ"):
        moving = permute_box(moving_x, axis)
        for i, delta in enumerate(deltas):
            for kind in ["raw_array_box", "empty"]:
                s = raw_box(permute_box(unit,axis)) if kind == "raw_array_box" else {"kind":"empty"}
                add("raw_array_box_collide", f"gate-{name}-{kind}-{i}", {"moving_box":list(map(bits,moving)),"axis":name,"delta":bits(delta),"shape":s}, ["targeted", "epsilon_gate", "raw_substrate"])
            for shape_list, label in [([],"none"),([{"kind":"empty"}],"empty"),([raw_box(permute_box(unit,axis))],"one")]:
                add("raw_array_boxes_collide", f"gate-{name}-{label}-{i}", {"moving_box":list(map(bits,moving)),"axis":name,"delta":bits(delta),"shapes":shape_list}, ["targeted", "iterable_epsilon_gate", "raw_substrate"])
            disjoint=permute_box([-1.,2.,2.,0.,3.,3.],axis)
            add("raw_array_box_collide", f"gate-free-{name}-{i}", {"moving_box":list(map(bits,disjoint)),"axis":name,"delta":bits(delta),"shape":raw_box(unit)}, ["targeted", "epsilon_gate", "disjoint_obstacle", "raw_substrate"])
        for sign in [-1,1]:
            for i, gap in enumerate(gaps):
                obstacle = [gap,0.,0.,gap+1.,1.,1.] if sign == 1 else [gap-1.,0.,0.,gap,1.,1.]
                gap_moving=moving if sign == 1 else permute_box([0.,.25,.25,1.,.75,.75],axis)
                add("raw_array_box_collide", f"gap-{name}-{sign}-{i}", {"moving_box":list(map(bits,gap_moving)),"axis":name,"delta":bits(float(sign)*2.),"shape":raw_box(permute_box(obstacle,axis))}, ["targeted", "epsilon_gap", "zero_origin_exact_gap", "raw_substrate"])
        for i, (lo,hi) in enumerate(overlap_bounds):
            m=permute_box([-1.,lo,.25,0.,hi,.75],axis)
            add("raw_array_box_collide", f"transverse-{name}-{i}", {"moving_box":list(map(bits,m)),"axis":name,"delta":bits(2.),"shape":raw_box(unit)}, ["targeted", "epsilon_transverse_overlap", "raw_substrate"])
        for i, b in enumerate(targeted[2:6]):
            add("raw_array_box_collide", f"degenerate-{name}-{i}", {"moving_box":list(map(bits,moving)),"axis":name,"delta":bits(2.),"shape":raw_box(b)}, ["targeted", "occupied_degenerate_cell", "raw_substrate"])
        for i, x in enumerate([-.5,-0.,0.,math.nextafter(0.,math.inf),math.nextafter(1.,0.),1.,math.nextafter(1.,math.inf),2.]):
            add("raw_array_find_index", f"boundary-{name}-{i}", {"shape":raw_box(unit),"axis":name,"value":bits(x)}, ["targeted", "strict_coordinate_search"])
        near=raw_box(permute_box([eps/2,0.,0.,1.,1.,1.],axis)); far=raw_box(permute_box([.5,0.,0.,1.5,1.,1.],axis))
        for i, shapes in enumerate([[near], [near,far], [far,near], [near,{"kind":"empty"}], [{"kind":"empty"},near], [far,near,far]]):
            add("raw_array_boxes_collide", f"ordered-{name}-{i}", {"moving_box":list(map(bits,moving)),"axis":name,"delta":bits(2.),"shapes":shapes}, ["targeted", "ordered_multi_shape", "raw_substrate"])
    # Separate shape-construction/union observations carry realized coords and boxes.
    construction = [unit,[0.,0.,0.,0.,1.,1.],[0.,0.,0.,below,1.,1.],[0.,0.,0.,eps,1.,1.],
                    [0.,0.,0.,above,1.,1.],[-eps/2,0.,0.,1.,1.,1.],[-above,0.,0.,1.,1.,1.],
                    [.125+eps/2,0.,0.,.875-eps/2,1.,1.],[-1.,0.,0.,2.,1.,1.],[1.,0.,0.,0.,1.,1.]]
    for i, b in enumerate(construction):
        s={"kind":"box","box":list(map(bits,b))}
        add("shape_construct",f"box-{i}",{"shape":s},["targeted","shape_construction_outside_raw_substrate"])
        for axis,name in enumerate("XYZ"):
            add("shape_collide",f"box-{i}-{name}",{"shape":s,"moving_box":list(map(bits,permute_box(moving_x,axis))),"axis":name,"delta":bits(2.)},["targeted","shape_construction_outside_raw_substrate"])
    unions = [[unit,[1.,0.,0.,2.,1.,1.]], [[0.,0.,0.,.25,1.,1.],[.75,0.,0.,1.,1.,1.]],
              [[0.,0.,0.,1.,.25,1.],[0.,.75,0.,1.,1.,1.]], [unit,[1.+eps/2,0.,0.,2.,1.,1.]],
              [unit,[1.+above,0.,0.,2.,1.,1.]], [unit,[.25,.25,.25,.75,.75,.75]]]
    for i, boxes in enumerate(unions):
        s={"kind":"union","boxes":[list(map(bits,b)) for b in boxes]}
        add("shape_construct",f"union-{i}",{"shape":s},["targeted","shape_merger_outside_raw_substrate"])
        for axis,name in enumerate("XYZ"):
            add("shape_collide",f"union-{i}-{name}",{"shape":s,"moving_box":list(map(bits,permute_box(moving_x,axis))),"axis":name,"delta":bits(2.)},["targeted","shape_merger_outside_raw_substrate"])
    # Inputs are independently generated; all expected results come from actual Java calls.
    rng=random.Random(SEED)
    def coordinate() -> float:
        if rng.random()<.15:
            return math.ldexp(rng.uniform(-1.,1.), rng.choice([-1000,-50,-24,0,24,50,1000]))
        return rng.randint(-256,256)/rng.choice([1,2,4,8,16,32,1024])
    for i in range(300):
        b=[coordinate() for _ in range(6)]; v=[coordinate() for _ in range(3)]
        for op in ["aabb_construct","aabb_move","aabb_inflate","aabb_deflate","aabb_inflate_scalar","aabb_deflate_scalar","aabb_contains","aabb_intersects"]:
            data={"box":list(map(bits,b))}
            if op in ["aabb_move","aabb_inflate","aabb_deflate"]: data["vector"]=list(map(bits,v))
            elif op.endswith("_scalar"): data["scalar"]=bits(v[0])
            elif op=="aabb_contains": data["point"]=list(map(bits,v))
            elif op=="aabb_intersects": data["other"]=[bits(coordinate()) for _ in range(6)]
            add(op,f"random-{i}",data,["seeded_random","finite_inputs"])
    for i in range(600):
        axis=rng.randrange(3); name="XYZ"[axis]; sign=rng.choice([-1.,1.])
        m=[rng.randint(-32,32)/8 for _ in range(3)]; width=[rng.choice([0.,eps/2,eps,.125,.5,1.,2.]) for _ in range(3)]
        moving=m+[m[j]+width[j] for j in range(3)]
        shapes=[]
        for k in range(rng.randrange(1,5)):
            lo=[m[j]+rng.choice([-1.,-.5,0.,.125,.5,1.,2.]) for j in range(3)]
            lo[axis]=(moving[axis+3] if sign>0 else moving[axis])+rng.choice([-above,-eps,-below,0.,below,eps,above,.25,.5,1.])
            hi=[lo[j]+rng.choice([0.,eps/2,.125,.5,1.,2.]) for j in range(3)]
            if sign<0: lo[axis],hi[axis]=lo[axis]-1.,lo[axis]
            shapes.append(raw_box(lo+hi))
        delta=sign*rng.choice([below,eps,above,.25,1.,2.,8.])
        data={"moving_box":list(map(bits,moving)),"axis":name,"delta":bits(delta)}
        add("raw_array_box_collide",f"random-{i}",{**data,"shape":shapes[0]},["seeded_random","finite_inputs","raw_substrate"])
        add("raw_array_boxes_collide",f"random-{i}",{**data,"shapes":shapes},["seeded_random","finite_inputs","raw_substrate"])
    return cases


CLASSES = ["net.minecraft.world.phys.AABB", "net.minecraft.world.phys.shapes.VoxelShape", "net.minecraft.world.phys.shapes.Shapes",
           "net.minecraft.world.phys.shapes.ArrayVoxelShape", "net.minecraft.world.phys.shapes.CubeVoxelShape",
           "net.minecraft.world.phys.shapes.DiscreteVoxelShape", "net.minecraft.world.phys.shapes.BitSetDiscreteVoxelShape",
           "net.minecraft.core.AxisCycle", "net.minecraft.core.Direction$Axis", "net.minecraft.util.Mth"]
METHODS = {"AABB", "ArrayVoxelShape", "BitSetDiscreteVoxelShape", "move", "inflate", "deflate", "contains", "intersects", "min", "max", "collide", "collideX", "findIndex", "lambda$findIndex$0", "getCoords", "get", "box", "create", "findBits", "joinUnoptimized", "createIndexMerger", "binarySearch", "toAabbs", "forAllBoxes", "cycle", "inverse", "between", "isFullWide", "fill", "isEmpty", "choose", "getSize", "firstFull", "lastFull"}


def source_inventory(jars: list[pathlib.Path]) -> dict:
    result=subprocess.run([str(JAVA.parent/"javap"),"-classpath",str(jars[0]),"-c","-p",*CLASSES],check=True,capture_output=True,text=True)
    (ROOT/"reference/cache/geometry-bytecode.txt").write_text(result.stdout)
    chunks=result.stdout.split('Compiled from "')[1:]
    if len(chunks)!=len(CLASSES): raise ValueError("Unexpected geometry javap class topology")
    records={}
    with zipfile.ZipFile(jars[0]) as archive:
        for owner,chunk in zip(CLASSES,chunks):
            if owner not in chunk.splitlines()[1]: raise ValueError("Unexpected geometry javap declaration")
            methods=[]
            # Include package-private constructors/methods without consuming fields.
            for signature,body in re.findall(r"^  ([^\n]*\([^\n]*\);)\n(.*?)(?=^  [^\n]*(?:;|\{)\n|\Z)",chunk,re.M|re.S):
                match=re.search(r"([\w$]+)\([^\n]*\);$",signature)
                if match and match[1] in METHODS:
                    methods.append({"signature":signature,"bytecode_text_sha256":hashlib.sha256(body.encode()).hexdigest(),
                                    "direct_call_references":sorted(set(re.findall(r"// (?:InterfaceMethod|Method) (.+)",body))),
                                    "field_references":sorted(set(re.findall(r"// Field (.+)",body)))})
            entry=owner.replace(".","/")+".class"
            records[owner]={"class_entry":entry,"class_sha256":hashlib.sha256(archive.read(entry)).hexdigest(),"declaration":chunk.splitlines()[1],"methods":methods}
    return {"scope":"Named official class bytes and javap declarations/direct references; no decompiler or unofficial sources", "classes":records,
            "complete_javap_text_sha256":hashlib.sha256(result.stdout.encode()).hexdigest()}


def run_java(inputs: list[dict], jars: list[pathlib.Path], suffix: str="") -> tuple[list[dict],dict]:
    directory=ROOT/"reference/extracted/geometry_probe"; directory.mkdir(parents=True,exist_ok=True)
    source=directory/"ReferenceGeometryProbe.java"; source.write_text(SOURCE)
    classes=directory/"classes"; classes.mkdir(exist_ok=True)
    cp=":".join(map(str,jars)); compile_command=[str(JAVA.parent/"javac"),"-cp",cp,"-d",str(classes),str(source)]
    compilation=subprocess.run(compile_command,capture_output=True,text=True)
    (ROOT/"reference/cache/geometry-javac.log").write_text(compilation.stdout+compilation.stderr)
    compilation.check_returncode()
    incoming=ROOT/f"reference/cache/geometry-input{suffix}.jsonl"; outgoing=ROOT/f"reference/cache/geometry-observed{suffix}.jsonl"
    incoming.write_text("".join(canonical(c).decode()+"\n" for c in inputs))
    command=[str(JAVA),"-cp",str(classes)+":"+cp,"ReferenceGeometryProbe",str(incoming),str(outgoing)]
    result=subprocess.run(command,capture_output=True,text=True)
    (ROOT/f"reference/cache/geometry-java{suffix}.log").write_text(result.stdout+result.stderr); result.check_returncode()
    observations=[json.loads(line) for line in outgoing.read_text().splitlines()]
    if len(observations)!=len(inputs) or [o["id"] for o in observations]!=[c["id"] for c in inputs]: raise ValueError("Geometry Java observation identity mismatch")
    return observations,{"source_sha256":hashlib.sha256(SOURCE.encode()).hexdigest(),"compile_command":compile_command,"run_command":command,
                         "input_jsonl_sha256":fingerprint(incoming)["sha256"],"observation_jsonl_sha256":fingerprint(outgoing)["sha256"]}


def validate(metadata: dict, observations: list[dict] | None=None) -> dict:
    if metadata["schema_version"]!=1 or metadata["pin"]!="26.3": raise ValueError("Geometry schema/pin mismatch")
    cases=metadata["cases"]
    if len({c["id"] for c in cases})!=len(cases): raise ValueError("Duplicate geometry case ID")
    if hashlib.sha256(canonical(cases)).hexdigest()!=metadata["cases_sha256"]: raise ValueError("Geometry fixture checksum mismatch")
    inputs=[{k:c[k] for k in ["id","operation","tags","input"]} for c in cases]
    if inputs!=generate_inputs(): raise ValueError("Geometry fixture input generation mismatch")
    count=0
    def walk(value):
        nonlocal count
        if isinstance(value,dict):
            for k,v in value.items():
                if k in {"box","moving_box","other","point","vector","aabbs_f64_bits"}:
                    flat=v if k!="aabbs_f64_bits" else [x for b in v for x in b]
                    if any(not isinstance(x,str) or re.fullmatch("[0-9a-f]{16}",x) is None for x in flat): raise ValueError("Invalid geometry raw-bit vector")
                    count+=len(flat)
                if k in {"a","b","delta","scalar","value","f64_bits","math_min_bits","math_max_bits"} and (not isinstance(v,str) or re.fullmatch("[0-9a-f]{16}",v) is None): raise ValueError("Invalid geometry raw-bit scalar")
                if k=="coordinate_f64_bits" and any(re.fullmatch("[0-9a-f]{16}",x) is None for a in v.values() for x in a): raise ValueError("Invalid geometry raw-bit coordinate list")
                walk(v)
        elif isinstance(value,list):
            for v in value: walk(v)
    walk(cases)
    if observations is not None:
        if len(observations)!=len(cases): raise ValueError("Geometry oracle observation count mismatch")
        for case,observed in zip(cases,observations):
            if case["id"]!=observed["id"] or case["expected"]!=observed["expected"] or case["observation"]!=observed["observation"]:
                raise ValueError("Geometry fixture differs from independent Java oracle observation")
    return {"case_count":len(cases),"operations":dict(sorted(collections.Counter(c["operation"] for c in cases).items())),"validated_vector_endpoint_bits":count,
            "oracle_comparison":observations is not None,"case_checksums":True,"independent_seeded_input_reconstruction":True}


def extract() -> dict:
    jars,release=verified_classpath(); inputs=generate_inputs(); observations,execution=run_java(inputs,jars)
    runtime=subprocess.run([str(JAVA),"-version"],check=True,capture_output=True,text=True)
    compiler=subprocess.run([str(JAVA.parent/"javac"),"-version"],check=True,capture_output=True,text=True)
    cases=[{**c,"expected":o["expected"],"observation":o["observation"]} for c,o in zip(inputs,observations)]
    metadata={"schema_version":1,"pin":"26.3","confidence":"high for observed exact class/runtime calls; fixture coverage is bounded",
              "purpose":"Independent Java geometry observations only; no implementation or gameplay parity claim",
              "runtime_version":(runtime.stdout+runtime.stderr).strip().splitlines(),"runtime_executable":fingerprint(JAVA),"compiler_version":(compiler.stdout+compiler.stderr).strip(),
              "server_bundle_sha256":release["server_bundle"]["sha256"],"server_class_jar_sha256":release["server_bundle"]["nested_server_sha256"],
              "input_encoding":"IEEE754 binary64 raw bits, lowercase 16 hexadecimal digits; box order minX,minY,minZ,maxX,maxY,maxZ; all AABB box inputs call its six-double constructor",
              "raw_array_shape_encoding":"Filled 1x1x1 discrete voxel grid, exact two-element axis coordinate lists; no Shapes.box/create normalization or snapping; empty is an explicit zero-occupancy shape",
              "random_input_seed":SEED,"random_input_generator":"Python random.Random, mixed dyadic and ldexp finite inputs; expected values produced exclusively by named Java methods",
              "collision_scope":"Ordered raw one-cell shapes are the box substrate oracle; Shapes.box/create/union lanes additionally observe construction/merging and must not be advertised as box-substrate parity",
              "epsilon":{"decimal_source_literal":"1.0E-7d","f64_bits":bits(1e-7),"comparison":"strict Math.abs(delta) < epsilon; one-shape emptiness gate occurs first; iterable gate before every visited shape"},
              "source":source_inventory(jars),"probe_java_source_sha256":execution["source_sha256"],"cases_sha256":hashlib.sha256(canonical(cases)).hexdigest(),"cases":cases}
    validation=validate(metadata,observations); write_json(OUTPUT,metadata)
    evidence={"status":"passed","scope":"Pinned Java reference extraction, not Bend comparison","reference_file":fingerprint(OUTPUT),"execution":execution,"validation":validation,
              "expected_errors":dict(collections.Counter(c["expected"].get("error_class") for c in cases if "error_class" in c["expected"])),
              "commands":["python3 tools/reference_geometry_probe.py","python3 tools/reference_geometry_probe.py --verify-existing","python3 tools/reference_geometry_probe.py --selftest"]}
    write_json(ROOT/"evidence/reference_geometry_probe.json",evidence); return evidence


def verify_existing() -> dict:
    jars,release=verified_classpath(); metadata=json.loads(OUTPUT.read_text())
    if metadata["server_class_jar_sha256"]!=release["server_bundle"]["nested_server_sha256"]: raise ValueError("Geometry official source jar mismatch")
    if metadata["probe_java_source_sha256"]!=hashlib.sha256(SOURCE.encode()).hexdigest(): raise ValueError("Geometry Java source mismatch")
    if metadata["runtime_executable"]!=fingerprint(JAVA): raise ValueError("Geometry Java runtime executable mismatch")
    if metadata["source"]!=source_inventory(jars): raise ValueError("Geometry named class/declaration hash mismatch")
    observations=[json.loads(line) for line in (ROOT/"reference/cache/geometry-observed.jsonl").read_text().splitlines()]
    validation=validate(metadata,observations)
    evidence={"status":"passed","reference_file":fingerprint(OUTPUT),"validation":validation,"official_artifact_and_library_hashes_checked":True,"named_class_and_method_hashes_checked":True}
    write_json(ROOT/"evidence/reference_geometry_validation.json",evidence); return evidence


def selftest() -> dict:
    jars,_=verified_classpath(); metadata=json.loads(OUTPUT.read_text()); inputs=generate_inputs()
    first,_=run_java(inputs,jars,"-selftest1"); second,_=run_java(inputs,jars,"-selftest2")
    if first!=second: raise ValueError("Geometry Java reruns not reproducible")
    validate(metadata,first); validate(metadata,second)
    failures=[]
    changed=copy.deepcopy(metadata); case=next(c for c in changed["cases"] if c["operation"]=="raw_array_box_collide" and c["input"]["delta"]==bits(1e-7) and c["expected"].get("f64_bits")!=bits(0.))
    case["expected"]["f64_bits"]=bits(0.)
    for reseal in [False,True]:
        if reseal: changed["cases_sha256"]=hashlib.sha256(canonical(changed["cases"])).hexdigest()
        try: validate(changed,first)
        except ValueError as e: failures.append({"case":"changed_exact_epsilon_expected_result","resealed_fixture_checksum":reseal,"rejected":True,"reason":str(e)})
        else: raise ValueError("Corrupted geometry result accepted")
    changed=copy.deepcopy(metadata); case=next(c for c in changed["cases"] if c["operation"]=="aabb_construct" and "random" in c["id"]); case["input"]["box"][0]=bits(123.)
    changed["cases_sha256"]=hashlib.sha256(canonical(changed["cases"])).hexdigest()
    try: validate(changed,first)
    except ValueError as e: failures.append({"case":"changed_random_input","resealed_fixture_checksum":True,"rejected":True,"reason":str(e)})
    else: raise ValueError("Corrupted geometry input accepted")
    evidence={"status":"passed","fixture_file":fingerprint(OUTPUT),"independent_java_runs":2,"case_count_per_run":len(first),"byte_exact_observations_reproduced":True,"failure_injection":failures,
              "scope":"Reference oracle generation/integrity, no Bend implementation comparison"}
    write_json(ROOT/"evidence/reference_geometry_selftest.json",evidence); return evidence


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__); group=parser.add_mutually_exclusive_group(); group.add_argument("--verify-existing",action="store_true"); group.add_argument("--selftest",action="store_true"); args=parser.parse_args()
    result=selftest() if args.selftest else verify_existing() if args.verify_existing else extract()
    print(json.dumps({"status":result["status"],"cases":result.get("case_count_per_run",result.get("validation",{}).get("case_count")),"reference":str(OUTPUT)},sort_keys=True))


if __name__=="__main__": main()
