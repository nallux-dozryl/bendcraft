#!/usr/bin/env python3
"""Observe untouched pinned production model receivers with real Java RNGs.

Marker parts identify model/transform choices without baking any geometry.
Python generates inputs; the production receiver chooses/consumes/reseeds.
"""
from __future__ import annotations
import argparse, collections, copy, hashlib, json, pathlib, random, subprocess, zipfile
from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_model_probe import CLIENT, verified_client_classpath

DIR=ROOT/'build/model-choice'
SEED=263_701_19
CLASSES=[
 'net.minecraft.client.renderer.block.dispatch.SingleVariant',
 'net.minecraft.client.renderer.block.dispatch.WeightedVariants',
 'net.minecraft.client.renderer.block.dispatch.WeightedVariants$Unbaked',
 'net.minecraft.client.renderer.block.dispatch.multipart.MultiPartModel',
 'net.minecraft.client.renderer.block.dispatch.multipart.MultiPartModel$SharedBakedState',
 'net.minecraft.client.renderer.block.dispatch.multipart.MultiPartModel$Selector',
 'net.minecraft.client.renderer.block.dispatch.BlockStateModelDispatcher',
 'net.minecraft.client.renderer.block.ModelBlockRenderer',
 'net.minecraft.client.renderer.chunk.SectionCompiler',
 'net.minecraft.client.renderer.feature.MovingBlockFeatureRenderer',
 'net.minecraft.util.random.WeightedList','net.minecraft.util.random.WeightedList$Flat',
 'net.minecraft.util.random.WeightedList$Compact','net.minecraft.util.random.WeightedRandom',
 'net.minecraft.util.RandomSource','net.minecraft.world.level.levelgen.SingleThreadedRandomSource',
 'net.minecraft.world.level.levelgen.LegacyRandomSource','net.minecraft.world.level.levelgen.BitRandomSource',
 'net.minecraft.world.level.levelgen.XoroshiroRandomSource','net.minecraft.world.level.levelgen.Xoroshiro128PlusPlus',
 'net.minecraft.util.Mth','net.minecraft.world.level.block.state.BlockBehaviour',
 'net.minecraft.world.level.block.state.BlockBehaviour$BlockStateBase',
 'net.minecraft.world.level.block.AbstractBedBlock','net.minecraft.world.level.block.DoorBlock',
 'net.minecraft.world.level.block.DoublePlantBlock']

SOURCE=r'''
import com.google.gson.*;
import com.mojang.serialization.JsonOps;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.resources.Identifier;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.*;
import net.minecraft.util.RandomSource;
import net.minecraft.util.Mth;
import net.minecraft.util.random.*;
import net.minecraft.client.renderer.block.dispatch.*;
import net.minecraft.client.renderer.block.dispatch.multipart.MultiPartModel;
import net.minecraft.client.resources.model.sprite.Material;
import net.minecraft.client.resources.model.geometry.BakedQuad;
import net.minecraft.core.Direction;
import java.util.*;
import java.util.concurrent.atomic.AtomicLong;
import java.lang.reflect.*;
import java.nio.file.*;
import java.io.*;

class ReferenceModelChoiceProbe {
 static Gson G=new GsonBuilder().serializeNulls().disableHtmlEscaping().create();
 static long word(JsonArray a){return (a.get(0).getAsLong()<<32)|a.get(1).getAsLong();}
 static JsonArray bits(long x){var a=new JsonArray();a.add(x>>>32);a.add(x&0xffffffffL);return a;}
 static Object field(Object x,String name)throws Exception{var f=x.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(x);}
 static JsonArray state(RandomSource r)throws Exception{
  var a=new JsonArray();
  if(r instanceof XoroshiroRandomSource){a.add("x");var v=field(r,"randomNumberGenerator");a.add(bits((long)field(v,"seedLo")));a.add(bits((long)field(v,"seedHi")));}
  else {a.add("l");Object v=field(r,"seed");a.add(bits(v instanceof AtomicLong s?s.get():(Long)v));a.add(bits(0));}
  return a;
 }
 static RandomSource source(JsonObject in)throws Exception{
  String kind=in.get("kind").getAsString();long seed=word(in.getAsJsonArray("seed"));
  RandomSource r=switch(kind){case "l"->new LegacyRandomSource(seed);case "t"->RandomSource.createThreadLocalInstance(seed);case "x"->new XoroshiroRandomSource(seed);case "r"->new XoroshiroRandomSource(seed,word(in.getAsJsonArray("high")));default->throw new IllegalArgumentException("kind");};
  for(int i=0;i<in.get("advance").getAsInt();i++)r.nextInt();return r;
 }
 static int draws(JsonArray before,JsonArray after)throws Exception{
  RandomSource cursor;
  if(before.get(0).getAsString().equals("x"))cursor=new XoroshiroRandomSource(word(before.get(1).getAsJsonArray()),word(before.get(2).getAsJsonArray()));
  else {cursor=new LegacyRandomSource(0);((AtomicLong)field(cursor,"seed")).set(word(before.get(1).getAsJsonArray()));}
  for(int n=0;n<=16384;n++){if(state(cursor).equals(after))return n;if(cursor instanceof XoroshiroRandomSource)cursor.nextLong();else cursor.nextInt();}
  throw new IllegalStateException("Primitive advancement not found");
 }
 static class Marker implements BlockStateModelPart {
  final JsonObject selected;
  Marker(JsonObject v,Integer index){selected=new JsonObject();selected.add("part_index",index==null?JsonNull.INSTANCE:new JsonPrimitive(index));selected.add("variant",v.deepCopy());}
  public List<BakedQuad>getQuads(Direction d){throw new UnsupportedOperationException("Marker geometry is unavailable");}
  public boolean useAmbientOcclusion(){return false;}
  public Material.Baked particleMaterial(){return null;}
  public int materialFlags(){return 0;}
 }
 static BlockStateModel choice(JsonObject c,Integer index){
  if(c.get("kind").getAsString().equals("single"))return new SingleVariant(new Marker(c.getAsJsonObject("variant"),index));
  List<Weighted<BlockStateModel>> entries=new ArrayList<>();for(var e:c.getAsJsonArray("entries")){var w=e.getAsJsonObject();entries.add(new Weighted<>(new SingleVariant(new Marker(w.getAsJsonObject("variant"),index)),w.get("weight").getAsInt()));}
  return new WeightedVariants(WeightedList.of(entries));
 }
 static JsonObject variant(Variant v){var j=new JsonObject();j.addProperty("model",v.modelLocation().toString());var s=v.modelState();j.addProperty("x",s.x().shift*90);j.addProperty("y",s.y().shift*90);j.addProperty("z",s.z().shift*90);j.addProperty("uvlock",s.uvLock());return j;}
 static JsonObject unbakedChoice(BlockStateModel.Unbaked u){
  var j=new JsonObject();if(u instanceof SingleVariant.Unbaked s){j.addProperty("kind","single");j.add("variant",variant(s.variant()));}
  else if(u instanceof WeightedVariants.Unbaked w){j.addProperty("kind","weighted");var a=new JsonArray();int total=0;for(var e:w.entries().unwrap()){var t=new JsonObject();t.addProperty("weight",e.weight());total+=e.weight();t.add("variant",variant(((SingleVariant.Unbaked)e.value()).variant()));a.add(t);}j.add("entries",a);j.addProperty("total",total);}
  else throw new IllegalArgumentException("Unsupported unbaked receiver "+u.getClass());return j;
 }
 static JsonObject activeRoot(Object u,BlockState state)throws Exception{
  var j=new JsonObject();if(u instanceof MultiPartModel.Unbaked){j.addProperty("kind","multipart");var a=new JsonArray();int index=0;for(var item:(List<?>)field(u,"selectors")){var s=(MultiPartModel.Selector<?>)item;if(s.condition().test(state)){var p=new JsonObject();p.addProperty("index",index);p.add("choice",unbakedChoice((BlockStateModel.Unbaked)s.model()));a.add(p);}index++;}j.add("parts",a);}
  else{j.addProperty("kind","variant");j.add("choice",unbakedChoice((BlockStateModel.Unbaked)field(u,"contents")));}return j;
 }
 static BlockStateModel receiver(JsonObject root)throws Exception{
  if(root.get("kind").getAsString().equals("variant"))return choice(root.getAsJsonObject("choice"),null);
  var selectors=new ArrayList<MultiPartModel.Selector<BlockStateModel>>();
  for(var item:root.getAsJsonArray("parts")){var p=item.getAsJsonObject();selectors.add(new MultiPartModel.Selector<>(s->true,choice(p.getAsJsonObject("choice"),p.get("index").getAsInt())));}
  // A real multipart definition may contain selectors but match no parts.
  // Keep one false marker so SharedBakedState retains its constructor contract.
  if(selectors.isEmpty()){var c=new JsonObject();c.addProperty("kind","single");c.add("variant",variant(new Variant(Identifier.parse("test:inactive"))));selectors.add(new MultiPartModel.Selector<>(s->false,choice(c,0)));}
  Class<?> shared=Class.forName("net.minecraft.client.renderer.block.dispatch.multipart.MultiPartModel$SharedBakedState");var sc=shared.getDeclaredConstructor(List.class);sc.setAccessible(true);var mc=MultiPartModel.class.getDeclaredConstructor(shared,BlockState.class);mc.setAccessible(true);return (BlockStateModel)mc.newInstance(sc.newInstance(selectors),BuiltInRegistries.BLOCK.getValue(Identifier.parse("minecraft:stone")).defaultBlockState());
 }
 static JsonObject observe(JsonObject in)throws Exception{
  var o=new JsonObject();o.addProperty("id",in.get("id").getAsString());var root=in.getAsJsonObject("root");var model=receiver(root);o.addProperty("receiver",model.getClass().getName());RandomSource r=source(in);o.addProperty("rng_receiver",r.getClass().getName());var initial=state(r);o.add("initial_state",initial);
  final RandomSource real=r;
  var outcomes=new JsonArray();
  for(int i=0;i<in.get("repeats").getAsInt();i++){
   var one=new JsonObject();one.add("before",state(r));var selected=new ArrayList<BlockStateModelPart>();var localCalls=new JsonArray();
   RandomSource trace=(RandomSource)Proxy.newProxyInstance(RandomSource.class.getClassLoader(),new Class<?>[]{RandomSource.class},(p,m,args)->{var c=new JsonObject();c.addProperty("method",m.getName());c.add("before",state(real));var ar=new JsonArray();if(args!=null)for(var v:args)ar.add(v instanceof Long b?bits(b):G.toJsonTree(v));c.add("args",ar);Object out;try{out=m.invoke(real,args);}catch(InvocationTargetException e){throw e.getCause();}c.add("value",out instanceof Long b?bits(b):G.toJsonTree(out));c.add("after",state(real));if(m.getName().equals("nextInt"))c.addProperty("primitive_draws",draws(c.getAsJsonArray("before"),c.getAsJsonArray("after")));localCalls.add(c);return out;});
   if(in.has("reseed"))trace.setSeed(word(in.getAsJsonArray("reseed")));
   model.collectParts(trace,selected);var a=new JsonArray();for(var part:selected)a.add(((Marker)part).selected);one.add("selected",a);one.add("after",state(r));one.add("calls",localCalls);outcomes.add(one);
  }o.add("outcomes",outcomes);return o;
 }
 static JsonObject schema(Block b){var j=new JsonObject();var ps=new JsonObject();for(var pp:b.getStateDefinition().getProperties()){net.minecraft.world.level.block.state.properties.Property p=pp;var v=new JsonObject();v.addProperty("integer",p.getValueClass()==Integer.class);var a=new JsonArray();for(var x:p.getPossibleValues())a.add(p.getName((Comparable)x));v.add("values",a);ps.add(p.getName(),v);}j.addProperty("owner",b.toString());j.add("properties",ps);return j;}
 static JsonObject receiverError(JsonObject in)throws Exception{
  var o=new JsonObject();o.addProperty("id",in.get("id").getAsString());var r=source(in);o.add("before",state(r));String phase="construction";
  try{var model=receiver(in.getAsJsonObject("root"));phase="collectParts";model.collectParts(r,new ArrayList<>());o.addProperty("status","ok");}
  catch(Throwable e){while(e instanceof InvocationTargetException&&e.getCause()!=null)e=e.getCause();o.addProperty("status","error");o.addProperty("phase",phase);o.addProperty("error_class",e.getClass().getName());o.addProperty("message",e.getMessage());}
  o.add("after",state(r));return o;
 }
 public static void main(String[] args)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();var in=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonObject();var out=new JsonObject();var official=new JsonArray();
  for(var item:in.getAsJsonArray("definitions")){var d=item.getAsJsonObject();var b=BuiltInRegistries.BLOCK.getValue(Identifier.parse("minecraft:"+d.get("block").getAsString()));var parsed=BlockStateModelDispatcher.CODEC.parse(JsonOps.INSTANCE,JsonParser.parseString(d.get("json").getAsString())).getOrThrow();var roots=parsed.instantiate(b.getStateDefinition(),()->"reference");var result=new JsonObject();result.addProperty("block",d.get("block").getAsString());result.add("schema",schema(b));var states=new JsonArray();for(var s:b.getStateDefinition().getPossibleStates()){var j=new JsonObject();j.addProperty("id",Block.getId(s));var props=new JsonObject();for(var pp:b.getStateDefinition().getProperties()){net.minecraft.world.level.block.state.properties.Property p=pp;props.addProperty(p.getName(),p.getName(s.getValue(p)));}j.add("properties",props);var u=roots.get(s);if(u!=null)j.add("root",activeRoot(u,s));states.add(j);}result.add("states",states);official.add(result);}out.add("official",official);
  var observations=new JsonArray();for(var item:in.getAsJsonArray("cases"))observations.add(observe(item.getAsJsonObject()));out.add("cases",observations);
  var errors=new JsonArray();for(var item:in.getAsJsonArray("errors"))errors.add(receiverError(item.getAsJsonObject()));out.add("errors",errors);
  var positions=new JsonArray();for(var item:in.getAsJsonArray("positions")){var p=item.getAsJsonObject();int x=p.get("x").getAsInt(),y=p.get("y").getAsInt(),z=p.get("z").getAsInt();var j=p.deepCopy();j.add("default_seed",bits(Mth.getSeed(x,y,z)));var states=new JsonArray();for(String id:new String[]{"stone","oak_door","sunflower","red_bed"}){var b=BuiltInRegistries.BLOCK.getValue(Identifier.parse("minecraft:"+id));var ss=b.getStateDefinition().getPossibleStates();for(int n:new int[]{0,ss.size()-1}){var s=ss.get(n);var t=new JsonObject();t.addProperty("block",id);t.addProperty("state",s.toString());t.add("seed",bits(s.getSeed(new BlockPos(x,y,z))));states.add(t);}}j.add("block_seeds",states);positions.add(j);}out.add("positions",positions);Files.writeString(Path.of(args[1]),G.toJson(out));
 }
}
'''

def bits(x):return [(x&((1<<64)-1))>>32,x&0xffffffff]
def variant(i):return {'model':f'test:m{i}','x':(i%4)*90,'y':((i//4)%4)*90,'z':((i//16)%4)*90,'uvlock':bool(i%2)}
def choice(weights=None,i=0):
    if weights is None:return {'kind':'single','variant':variant(i)}
    return {'kind':'weighted','entries':[{'variant':variant(i+n),'weight':w}for n,w in enumerate(weights)],'total':sum(weights)}
def inputs(random_count=100):
    rng=random.Random(SEED);cases=[]
    def add(root,kind='t',seed=0,high=0,advance=0,reseed=None,tags=()):
        c={'id':f'mc{len(cases):04d}','root':root,'kind':kind,'seed':bits(seed),'high':bits(high),'advance':advance,'repeats':3,'fuel':64,'tags':list(tags)}
        if reseed is not None:c['reseed']=bits(reseed)
        cases.append(c)
    roots=[{'kind':'variant','choice':choice(w)}for w in [None,[1],[3],[1,1],[1,2,4],[31,32],[32,32],[1073741824,1],[2147483647]]]
    roots+=[{'kind':'multipart','parts':[]},{'kind':'multipart','parts':[{'index':7,'choice':choice()}]},
            {'kind':'multipart','parts':[{'index':i*3,'choice':choice(w,i*8)}for i,w in enumerate([[1,3],None,[3,1]])]},
            {'kind':'multipart','parts':[{'index':i,'choice':choice([1,1],i*2)}for i in range(4)]}]
    for kind in ['t','l','x','r']:
        for seed in [0,-1,-(1<<63),(1<<63)-1,0x5deece66d]:
            for root in roots:add(root,kind,seed,0xfedcba9876543210,tags=['targeted'])
    for n in range(random_count):
        def rc():return choice(None if rng.randrange(4)==0 else [rng.randrange(1,500000000)for _ in range(rng.randrange(1,5))],rng.randrange(128))
        root={'kind':'variant','choice':rc()}if n%2 else {'kind':'multipart','parts':[{'index':2*i,'choice':rc()}for i in range(rng.randrange(9))]}
        add(root,['t','l','x','r'][n%4],rng.getrandbits(64),rng.getrandbits(64),rng.randrange(12),rng.getrandbits(64)if n%3==0 else None,['independent_random_inputs'])
    definitions=[];resources={}
    with zipfile.ZipFile(CLIENT)as jar:
        for block in ['stone','dirt','oak_planks','grass_block','glass','oak_stairs','oak_slab','oak_fence']:
            path=f'assets/minecraft/blockstates/{block}.json';raw=jar.read(path);definitions.append({'block':block,'json':raw.decode()});resources[path]={'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw)}
    positions=[{'id':f'position{i}','x':x,'y':y,'z':z}for i,(x,y,z)in enumerate([(0,0,0),(1,-1,1),(-30000000,-64,30000000),(-(1<<31),(1<<31)-1,-(1<<31)),((1<<31)-1,-(1<<31),(1<<31)-1)]+[tuple(rng.randrange(-(1<<31),1<<31)for _ in range(3))for _ in range(64)])]
    errors=[]
    for w in [[],[0],[0,0],[-1],[2,-1],[2147483647,1],[2147483647,2147483647]]:
        errors.append({'id':f'error{len(errors)}','root':{'kind':'variant','choice':choice(w)},'kind':'t','seed':bits(42),'high':bits(0),'advance':0})
    return {'cases':cases,'definitions':definitions,'positions':positions,'resources':resources,'errors':errors}

def run_java(data,cp,tag):
    DIR.mkdir(parents=True,exist_ok=True);src=DIR/'ReferenceModelChoiceProbe.java';src.write_text(SOURCE)
    ip=DIR/(tag+'-input.json');op=DIR/(tag+'-output.json');ip.write_bytes(canonical(data))
    cmd=[str(JAVA),'-cp',':'.join(map(str,cp)),str(src),str(ip),str(op)]
    result=subprocess.run(cmd,cwd=DIR,capture_output=True,text=True,timeout=120)
    (DIR/(tag+'.log')).write_text(result.stdout+result.stderr)
    if result.returncode:raise RuntimeError((result.stdout+result.stderr)[-6000:])
    return json.loads(op.read_text()),{'command':cmd,'input_sha256':fingerprint(ip)['sha256'],'output_sha256':fingerprint(op)['sha256']}

def inventory(cp):
    records={}
    with zipfile.ZipFile(CLIENT)as jar:
        for name in CLASSES:
            entry=name.replace('.','/')+'.class';cmd=[str(JAVA.parent/'javap'),'-classpath',str(CLIENT),'-c','-p',name]
            raw=subprocess.run(cmd,capture_output=True,text=True,check=True).stdout;(DIR/(name+'.javap')).write_text(raw)
            records[name]={'class_sha256':hashlib.sha256(jar.read(entry)).hexdigest(),'javap_sha256':hashlib.sha256(raw.encode()).hexdigest()}
    return records

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--random',type=int,default=100);args=ap.parse_args()
    cp,release=verified_client_classpath();data=inputs(args.random);first,m1=run_java(data,cp,'first')
    # The official Root objects come from actual production instantiate, then
    # marker receivers preserve their selected variants/source part indices.
    for block in first['official']:
        for state in block['states']:
            if 'root'not in state:continue
            data['cases'].append({'id':f'official_{block["block"]}_{state["id"]}','root':state['root'],'kind':'t','seed':bits(42),'high':bits(0),'advance':0,'repeats':3,'fuel':64,'tags':['official_instantiated_root']})
    one,m1=run_java(data,cp,'run1');two,m2=run_java(data,cp,'run2');assert one==two,'Java reproduction mismatch'
    ref={'schema':1,'pin':'26.3','input_seed':SEED,'random_cases':args.random,'authority':'Untouched production SingleVariant/WeightedVariants/MultiPartModel.collectParts receivers, real official RandomSources and reflected raw state; marker parts contain identity metadata only, not geometry','release':release,'source_sha256':hashlib.sha256(SOURCE.encode()).hexdigest(),'class_inventory':inventory(cp),'java_runs':[m1,m2],'resources':data['resources'],'official':one['official'],'positions':one['positions'],'receiver_errors':one['errors'],'cases':[]}
    for c,o in zip(data['cases'],one['cases']):
        assert c['id']==o['id'];ref['cases'].append({'input':c,'observed':o})
    ref['cases_sha256']=hashlib.sha256(canonical(ref['cases'])).hexdigest();ref['summary']={'cases':len(ref['cases']),'selection_observations':sum(len(c['observed']['outcomes'])for c in ref['cases']),'position_cases':len(ref['positions']),'official_states':sum(len(b['states'])for b in ref['official']),'receiver_errors':len(ref['receiver_errors']),'method_counts':dict(collections.Counter(call['method']for c in ref['cases']for o in c['observed']['outcomes']for call in o['calls']))}
    # Compact fixture table keeps exact per-method raw states without pretty-print inflation.
    (ROOT/'reference/model_choice.json').write_bytes(canonical(ref)+b'\n');write_json(ROOT/'evidence/model-choice-reference.json',{k:v for k,v in ref.items()if k not in ['cases','official','positions','release']}|{'client':release['client'],'runtime':release['java'],'java_version':release['java_version'],'libraries_sha256':hashlib.sha256(canonical(release['libraries'])).hexdigest()});print(json.dumps(ref['summary'],sort_keys=True))

if __name__=='__main__':main()
