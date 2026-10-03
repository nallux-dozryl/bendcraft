#!/usr/bin/env python3
"""Run pinned production client model parsing, selection and CPU geometry baking.

Python chooses inputs and checks provenance. Java invokes the official classes;
the controlled atlas is deliberately not the production atlas stitcher.
"""
from __future__ import annotations
import argparse, collections, copy, hashlib, json, pathlib, subprocess, zipfile
from reference_inventory import ROOT, INSTALL, JAVA, canonical, fingerprint, write_json

OUTPUT=ROOT/'reference/model_semantics.json'
CLIENT=INSTALL/'versions/26.3/26.3.jar'
META=INSTALL/'versions/26.3/26.3.json'
CACHE=ROOT/'reference/cache/model-probe'
BLOCKS=['stone','dirt','oak_planks','grass_block','glass','oak_stairs','oak_slab','oak_fence']

def sha(b):return hashlib.sha256(b).hexdigest()

def verified_client_classpath():
    release=json.loads((ROOT/'reference/release.json').read_text())
    if release['pin']!='26.3' or fingerprint(CLIENT)['sha256']!=release['client']['sha256']:raise ValueError('Pinned client mismatch')
    if sha(META.read_bytes())!='9a7b39dae3b9c8d30006b650e357aae220629b7852fa0fc7221db7a8646bd5e4':raise ValueError('Pinned metadata mismatch')
    version=json.loads(META.read_text());paths=[CLIENT];libraries=[];missing=[]
    for lib in version['libraries']:
        a=lib['downloads']['artifact'];p=INSTALL/'libraries'/a['path']
        if not p.is_file():
            if not any(s in a['path']for s in ['natives-linux','natives-windows','-linux-aarch_64.jar','-linux-x86_64.jar']):raise ValueError('Required client library missing: '+a['path'])
            missing.append(a['path']);continue
        f=fingerprint(p)
        if f['sha1']!=a['sha1']or f['bytes']!=a['size']:raise ValueError('Official library mismatch: '+a['path'])
        paths.append(p);libraries.append({'path':a['path'],'sha1':f['sha1'],'sha256':f['sha256'],'bytes':f['bytes']})
    return paths,{'client':fingerprint(CLIENT),'metadata':fingerprint(META),'libraries':libraries,'missing_other_platform_natives':missing,'java':fingerprint(JAVA),'java_version':subprocess.run([str(JAVA),'-version'],capture_output=True,text=True,check=True).stderr.strip()}

def rid(v):return v if ':'in v else'minecraft:'+v
def model_path(v):n,p=rid(v).split(':',1);return f'assets/{n}/models/{p}.json'

def build_inputs():
    models={};resources={};states={};variants={}
    with zipfile.ZipFile(CLIENT)as z:
        def load(v):
            v=rid(v)
            if v in models:return
            p=model_path(v);b=z.read(p);models[v]=b.decode();resources[p]={'sha256':sha(b),'bytes':len(b)}
            j=json.loads(b)
            if 'parent'in j:load(j['parent'])
        def scan(j):
            if isinstance(j,list):
                for x in j:scan(x)
            elif isinstance(j,dict):
                if 'model'in j:
                    load(j['model']);v={k:j[k]for k in ['model','x','y','z','uvlock']if k in j};variants[canonical(v).decode()]=v
                else:
                    for x in j.values():scan(x)
        for block in BLOCKS:
            p=f'assets/minecraft/blockstates/{block}.json';b=z.read(p);states[block]=b.decode();resources[p]={'sha256':sha(b),'bytes':len(b)};scan(json.loads(b))
        for text in models.values():
            for texture in json.loads(text).get('textures',{}).values():
                value=texture.get('sprite')if isinstance(texture,dict)else texture
                if isinstance(value,str)and not value.startswith('#'):
                    n,p=rid(value).split(':',1);p=f'assets/{n}/textures/{p}.png';b=z.read(p);resources[p]={'sha256':sha(b),'bytes':len(b)}
    cube={'from':[0,0,0],'to':[16,16,16],'faces':{d:{'texture':'#all','cullface':d}for d in ['down','up','north','south','west','east']}}
    base={'textures':{'all':'minecraft:block/stone'},'elements':[cube]}
    parse=[];graphs=[];conditions=[];selectors=[];dispatch=[]
    def pc(name,j,bake=False,raw=None):parse.append({'id':name,'json':raw if raw is not None else json.dumps(j,separators=(',',':')),'bake':bake})
    pc('defaults',{});pc('unknown_members',{'unexpected':{'nested':[1,2]},'shade':False})
    for parent in ['', 'block/stone','Minecraft:block/stone','minecraft:../block/stone','minecraft:/block/stone','minecraft:block/STONE','bad namespace:path']:
        pc('parent_'+str(len(parse)),{'parent':parent})
    for value in [None,True,1,[],{},'side','front','unknown']:pc('gui_light_'+str(len(parse)),{'gui_light':value})
    for value in [True,False,None,0,'false',{}]:pc('ambient_'+str(len(parse)),{'ambientocclusion':value})
    for value in ['minecraft:block/stone',{'sprite':'minecraft:block/glass','force_translucent':True},{'sprite':'minecraft:block/glass'},{'sprite':'minecraft:block/glass','unknown':123},{'sprite':'minecraft:block/glass','force_translucent':'false'},'#other',{},[],None,1,True]:pc('texture_'+str(len(parse)),{'textures':{'all':value}})
    pc('default_cube',base,True);pc('explicit_empty_elements',{'parent':'block/cube','elements':[]})
    for member,value in [('from',[-16,0,0]),('to',[32,16,16]),('from',[-16.000002,0,0]),('to',[32.000004,16,16]),('from',[0,0]),('to',[0,0,0,0]),('faces',{}),('faces',{'invalid':{'texture':'#all'}}),('light_emission',15),('light_emission',16),('light_emission',-1),('light_emission',1.9),('shade',False),('shade_direction_override','up'),('shade_direction_override','none'),('shade_direction_override','bad')]:
        j=copy.deepcopy(base);j['elements'][0][member]=value;pc('element_'+member+'_'+str(len(parse)),j,True)
    for member in ['from','to','faces']:
        j=copy.deepcopy(base);del j['elements'][0][member];pc('missing_'+member,j)
    for member,value in [('rotation',0),('rotation',90),('rotation',180),('rotation',270),('rotation',360),('rotation',-90),('rotation',45),('uv',[0,0,16,16]),('uv',[16,0,0,16]),('uv',[0,0,16]),('uv',[0,0,16,16,1]),('uv',{'minU':1,'minV':2,'maxU':15,'maxV':14}),('tintindex',0),('tintindex',-2),('cullface','bad'),('texture',1),('texture',None)]:
        j=copy.deepcopy(base);j['elements'][0]['faces']['north'][member]=value;pc('face_'+member+'_'+str(len(parse)),j,True)
    for angle in [-90,-45,-22.5,0,13.5,22.5,45,90]:
        for rescale in [False,True]:
            j=copy.deepcopy(base);j['elements'][0]['rotation']={'origin':[8,8,8],'axis':'y','angle':angle,'rescale':rescale};pc(f'rotation_y_{angle}_{rescale}',j,True)
    for rotation in [{'origin':[8,8,8],'x':12.3,'y':45,'z':-22.5},{'origin':[8,8,8],'x':0,'y':0,'z':0,'rescale':True},{'origin':[8,8,8],'axis':'bad','angle':22.5},{'origin':[8,8,8],'x':0,'y':0},{'axis':'x','angle':22.5},{'origin':[8,8,8]}]:
        j=copy.deepcopy(base);j['elements'][0]['rotation']=rotation;pc('rotation_'+str(len(parse)),j,True)
    for raw in ['{"elements":[{"from":[0.1,-0.0,0.10000000149011612],"to":[16,16,16],"faces":{"north":{"texture":"#all"}}}]}','{"textures":{"all":"minecraft:block/stone"},"elements":[{"from":[0,0,0],"to":[16,16,16],"faces":{"north":{"texture":"#all","uv":[1e-45,1.000000059604644775390625,1.0000000596046449,1e40]}}}]}','{"elements":null}','{"elements":{}}','[]','null','{"parent":"block/stone","parent":"block/dirt"}','{bad}']:
        pc('raw_json_'+str(len(parse)),None,False,raw)
    for display in [{},{'gui':{'translation':[160,-160,0.1],'scale':[9,-9,0.1],'rotation':[30.25,225,0]}},{'thirdperson_righthand':{'rotation':[1,2,3]}},{'firstperson_righthand':{'scale':[1,2]}},{'unknown':{'rotation':[1,2,3]}}]:pc('display_'+str(len(parse)),{'display':display})
    def graph(name,entries,roots):graphs.append({'id':name,'models':{rid(k):json.dumps(v,separators=(',',':'))for k,v in entries.items()},'roots':list(map(rid,roots))})
    graph('inheritance',{'test:p':base,'test:c':{'parent':'test:p','textures':{'all':{'sprite':'minecraft:block/glass','force_translucent':True}},'ambientocclusion':False},'test:e':{'parent':'test:c','elements':[]}},['test:c','test:e'])
    graph('parent_cycle',{'test:a':{'parent':'test:b'},'test:b':{'parent':'test:a'}},['test:a'])
    graph('self_parent',{'test:a':{'parent':'test:a'}},['test:a'])
    graph('missing_parent',{'test:a':{'parent':'test:missing'}},['test:a'])
    graph('texture_alias_cycle',{'test:a':{'textures':{'all':'#other','other':'#all'}}},['test:a'])
    graph('texture_alias_missing',{'test:a':{'textures':{'all':'#missing'}}},['test:a'])
    graph('alias_child_override',{'test:p':{'textures':{'all':'minecraft:block/stone','side':'#all'}},'test:c':{'parent':'test:p','textures':{'all':'minecraft:block/dirt'}}},['test:c'])
    for key in ['', 'facing=north','facing=north|south','facing=north,half=top','facing=north,facing=south','unknown=true','facing=bad','facing','facing=','half=top,',' facing=north','facing=north=bad']:
        selectors.append({'id':'variant_selector_'+str(len(selectors)),'block':'oak_stairs','selector':key})
    for cond in [{},{'north':'true'},{'north':'true|false'},{'north':'!true'},{'north':'!true|false'},{'north':True},{'north':''},{'missing':'true'},{'north':'bad'},{'OR':[{'north':'true'},{'east':'true'}]},{'AND':[{'north':'true'},{'east':'true'}]},{'OR':[]},{'AND':[]},{'OR':[{'north':'true'}],'east':'true'},{'NOT':{'north':'true'}},{'north':['true']},None]:conditions.append({'id':'condition_'+str(len(conditions)),'block':'oak_fence','condition':cond})
    one={'model':'minecraft:block/stone'}
    for j in [{},{'unknown':1},{'variants':{'':one}},{'variants':{'':[one,dict(one,weight=3,y=90)]}},{'variants':{'':dict(one,x=45)}},{'variants':{'':dict(one,y=360)}},{'variants':{'':dict(one,z=90)}},{'variants':{'':dict(one,uvlock='true')}},{'variants':{'':dict(one,weight=0)}},{'variants':{'':dict(one,weight=-1)}},{'variants':{'':dict(one,weight=2147483647)}},{'variants':{'':dict(one,unknown=123)}},{'variants':{'':[]}},{'variants':{'':one,'north=true':one}},{'multipart':[]},{'multipart':[{'apply':one}]},{'multipart':[{'when':{'north':'true'},'apply':one}]},{'variants':{'':one},'multipart':[{'apply':one}]},{'multipart':[{'apply':one,'unknown':1}]},{'variants':{'':{'model':'bad namespace:path'}}}]:dispatch.append({'id':'dispatcher_'+str(len(dispatch)),'block':'oak_fence','json':json.dumps(j,separators=(',',':'))})
    for weights in [(0,3),(-1,3),(0,0),(2147483647,1),(2147483647,2147483647)]:
        j={'variants':{'':[dict(one,weight=weights[0]),dict(one,weight=weights[1],y=90)]}};dispatch.append({'id':'weighted_edges_'+str(weights),'block':'oak_fence','json':json.dumps(j,separators=(',',':'))})
    # The exact production Variant codec supplies both geometric and UV-lock transforms.
    for x in [0,90,180,270]:
        for y in [0,90,180,270]:
            for lock in [False,True]:
                for model in ['minecraft:block/stone','minecraft:block/stone_mirrored']:
                    v={'model':model,'x':x,'y':y,'uvlock':lock};variants[canonical(v).decode()]=v
    return {'models':models,'blockstates':states,'variants':[variants[k]for k in sorted(variants)],'parse_cases':parse,'graph_cases':graphs,'selector_cases':selectors,'condition_cases':conditions,'dispatcher_cases':dispatch,'resources':resources,'blocks':BLOCKS}

JAVA_SOURCE=r'''
import com.google.gson.*;
import com.mojang.serialization.*;
import com.mojang.math.*;
import com.mojang.blaze3d.platform.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.resources.Identifier;
import net.minecraft.core.*;
import net.minecraft.core.registries.*;
import net.minecraft.client.resources.model.*;
import net.minecraft.client.resources.model.cuboid.*;
import net.minecraft.client.resources.model.geometry.*;
import net.minecraft.client.resources.model.sprite.*;
import net.minecraft.client.renderer.texture.*;
import net.minecraft.client.resources.metadata.animation.FrameSize;
import net.minecraft.client.renderer.block.dispatch.*;
import net.minecraft.client.renderer.block.dispatch.multipart.*;
import net.minecraft.client.renderer.block.BlockModelLighter;
import net.minecraft.client.model.geom.builders.UVPair;
import net.minecraft.world.level.CardinalLighting;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.*;
import net.minecraft.world.item.ItemDisplayContext;
import net.minecraft.util.random.*;
import org.joml.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.zip.*;
import java.io.*;
import java.nio.file.*;
import java.lang.reflect.*;

class ReferenceModelProbe {
 static Gson G=new GsonBuilder().serializeNulls().disableHtmlEscaping().create();
 static ZipFile JAR; static Map<Identifier,TextureAtlasSprite> SPRITES=new HashMap<>();
 static TextureAtlasSprite MISSING; static Method DEFAULT_UV, DIRECTIONAL;
 static ModelBaker.Interner INTERNER=new ModelBaker.Interner(){public Vector3fc vector(Vector3fc v){return v;}public BakedQuad.MaterialInfo materialInfo(BakedQuad.MaterialInfo v){return v;}};
 static String bits(float f){return String.format("%08x",Float.floatToRawIntBits(f));}
 static JsonElement desc(Object x)throws Exception {
  if(x==null)return JsonNull.INSTANCE;
  if(x==UnbakedGeometry.EMPTY)return new JsonPrimitive("UnbakedGeometry.EMPTY");
  if(x instanceof JsonElement j)return j;
  if(x instanceof Float f)return new JsonPrimitive(bits(f));
  if(x instanceof Number n)return new JsonPrimitive(n);
  if(x instanceof Boolean b)return new JsonPrimitive(b);
  if(x instanceof String s)return new JsonPrimitive(s);
  if(x instanceof Identifier||x instanceof Enum<?>)return new JsonPrimitive(x.toString());
  if(x instanceof Optional<?> o)return desc(o.orElse(null));
  if(x instanceof Vector3fc v)return arr(bits(v.x()),bits(v.y()),bits(v.z()));
  if(x instanceof Matrix4fc m){var a=new JsonArray();for(float f:m.get(new float[16]))a.add(bits(f));return a;}
  if(x instanceof WeightedList<?> w)return desc(w.unwrap());
  if(x instanceof Map<?,?> m){var j=new JsonObject();var entries=new ArrayList<>(m.entrySet());entries.sort(Comparator.comparing(e->e.getKey().toString()));for(var e:entries)j.add(e.getKey().toString(),desc(e.getValue()));return j;}
  if(x instanceof Iterable<?> l){var a=new JsonArray();for(var v:l)a.add(desc(v));return a;}
  if(x.getClass().isRecord()){var j=new JsonObject();j.addProperty("class",x.getClass().getName());for(var r:x.getClass().getRecordComponents()){var method=r.getAccessor();method.setAccessible(true);j.add(r.getName(),desc(method.invoke(x)));}return j;}
  throw new IllegalArgumentException("Unencoded observation class "+x.getClass().getName());
 }
 static JsonArray arr(String...s){var a=new JsonArray();for(var v:s)a.add(v);return a;}
 static JsonObject err(Throwable e){while(e instanceof InvocationTargetException&&e.getCause()!=null)e=e.getCause();var j=new JsonObject();j.addProperty("status","error");j.addProperty("error_class",e.getClass().getName());j.addProperty("message",e.getMessage());return j;}
 static CuboidModel parse(String s){return CuboidModel.fromStream(new StringReader(s));}
 static Block block(String s){return BuiltInRegistries.BLOCK.getValue(Identifier.parse("minecraft:"+s));}
 static JsonArray stateMatches(java.util.function.Predicate<BlockState> p,Block b){var a=new JsonArray();for(var s:b.getStateDefinition().getPossibleStates())if(p.test(s))a.add(Block.getId(s));return a;}
 static Map<Identifier,ResolvedModel> resolve(JsonObject input,List<String> roots)throws Exception{
  Map<Identifier,UnbakedModel> parsed=new HashMap<>();for(var e:input.entrySet())parsed.put(Identifier.parse(e.getKey()),parse(e.getValue().getAsString()));
  var d=new ModelDiscovery(parsed,parse("{}"));d.addRoot(r->{for(var s:roots)r.markDependency(Identifier.parse(s));});return d.resolve();
 }
 static JsonObject resolved(ResolvedModel m)throws Exception {
  var j=new JsonObject();j.addProperty("debug_name",m.debugName());j.addProperty("parent",m.parent()==null?null:m.parent().debugName());
  j.addProperty("ambient_occlusion",m.getTopAmbientOcclusion());j.add("gui_light",desc(m.getTopGuiLight()));j.add("geometry",desc(ResolvedModel.findTopGeometry(m)));j.add("transforms",desc(m.getTopTransforms()));
  var slots=m.getTopTextureSlots();var keys=new TreeSet<String>();
  for(var n=m;n!=null;n=n.parent())keys.addAll(n.wrapped().textureSlots().values().keySet());
  keys.add("#missing");keys.add("minecraft:block/stone");keys.add("particle");var materials=new JsonObject();for(var k:keys){materials.add(k,desc(slots.getMaterial(k)));materials.add("#"+k,desc(slots.getMaterial("#"+k)));}j.add("materials",materials);return j;
 }
 static TextureAtlasSprite sprite(Identifier id)throws Exception {
  if(SPRITES.containsKey(id))return SPRITES.get(id);
  String path="assets/"+id.getNamespace()+"/textures/"+id.getPath()+".png";var entry=JAR.getEntry(path);if(entry==null)return MISSING;
  var img=NativeImage.read(JAR.getInputStream(entry));var contents=new SpriteContents(id,new FrameSize(img.getWidth(),img.getHeight()),img);
  var ctor=TextureAtlasSprite.class.getDeclaredConstructor(Identifier.class,SpriteContents.class,int.class,int.class,int.class,int.class,int.class);ctor.setAccessible(true);
  var sp=(TextureAtlasSprite)ctor.newInstance(TextureAtlas.LOCATION_BLOCKS,contents,img.getWidth(),img.getHeight(),0,0,0);SPRITES.put(id,sp);return sp;
 }
 static ModelBaker baker(Map<Identifier,ResolvedModel> models,ResolvedModel m)throws Exception {
  var slots=m.getTopTextureSlots();var keys=new TreeSet<String>();for(var n=m;n!=null;n=n.parent())keys.addAll(n.wrapped().textureSlots().values().keySet());
  for(var k:keys){var material=slots.getMaterial(k);if(material!=null)sprite(material.sprite());}
  var prep=new SpriteLoader.Preparations(16,16,0,MISSING,new HashMap<>(SPRITES),CompletableFuture.completedFuture(null));
  var empty=new SpriteLoader.Preparations(16,16,0,MISSING,Map.of(),CompletableFuture.completedFuture(null));
  var mb=new MaterialBaker(prep,empty);
  return new ModelBaker(){public ResolvedModel getModel(Identifier id){return models.get(id);}public BlockStateModelPart missingBlockModelPart(){throw new UnsupportedOperationException("Missing block model not baked");}public MaterialBaker materials(){return mb;}public ModelBaker.Interner interner(){return INTERNER;}public<T>T compute(ModelBaker.SharedOperationKey<T> k){return k.compute(this);}};
 }
 static JsonObject quad(BakedQuad q)throws Exception {
  var j=new JsonObject();j.addProperty("direction",q.direction().toString());var v=new JsonArray();for(int i=0;i<4;i++){var p=new JsonObject();p.add("position_f32",desc(q.position(i)));p.addProperty("packed_uv_u64",String.format("%016x",q.packedUV(i)));p.add("uv_f32",arr(bits(UVPair.unpackU(q.packedUV(i))),bits(UVPair.unpackV(q.packedUV(i)))));v.add(p);}j.add("vertices",v);
  var mi=q.materialInfo();j.addProperty("tint_index",mi.tintIndex());j.addProperty("shade_direction_override",mi.shadeDirectionOverride()==null?null:mi.shadeDirectionOverride().toString());j.addProperty("light_emission",mi.lightEmission());j.addProperty("sprite",mi.sprite().contents().name().toString());j.addProperty("layer",mi.layer().toString());j.addProperty("material_flags",mi.flags());
  j.addProperty("default_directional_brightness_f32",bits((float)DIRECTIONAL.invoke(null,CardinalLighting.DEFAULT,q,q.direction())));j.addProperty("nether_directional_brightness_f32",bits((float)DIRECTIONAL.invoke(null,CardinalLighting.NETHER,q,q.direction())));return j;
 }
 static JsonObject bake(Map<Identifier,ResolvedModel> models,String id,Variant.SimpleModelState state)throws Exception {
  var m=models.get(Identifier.parse(id));if(m==null)throw new IllegalArgumentException("Resolved model absent "+id);var b=baker(models,m);var slots=m.getTopTextureSlots();var geometry=ResolvedModel.findTopGeometry(m);var modelstate=state.asModelState();var j=new JsonObject();j.add("model_state",desc(state));j.add("transformation_f32",desc(modelstate.transformation().getMatrix()));
  var transforms=new JsonObject();for(var d:Direction.values()){var t=new JsonObject();t.add("face_f32",desc(modelstate.faceTransformation(d)));t.add("inverse_face_f32",desc(modelstate.inverseFaceTransformation(d)));transforms.add(d.toString(),t);}j.add("face_transforms",transforms);
  var collection=m.bakeTopGeometry(slots,b,modelstate);var faces=new JsonObject();for(var d:Direction.values()){var a=new JsonArray();for(var q:collection.getQuads(d))a.add(quad(q));faces.add(d.toString(),a);}var un=new JsonArray();for(var q:collection.getQuads(null))un.add(quad(q));faces.add("unculled",un);j.add("quad_groups",faces);j.addProperty("quad_count",collection.getAll().size());j.addProperty("material_flags",collection.materialFlags());
  if(geometry instanceof UnbakedCuboidGeometry c){var uv=new JsonArray();for(var e:c.elements()){var f=new JsonObject();for(var d:Direction.values())if(e.faces().containsKey(d)){var face=e.faces().get(d);f.add(d.toString(),desc(face.uvs()==null?DEFAULT_UV.invoke(null,e.from(),e.to(),d):face.uvs()));}uv.add(f);}j.add("effective_face_uv_f32",uv);}return j;
 }
 static JsonObject dispatcher(String s,String blockName)throws Exception {
  var def=BlockStateModelDispatcher.CODEC.parse(JsonOps.INSTANCE,JsonParser.parseString(s)).getOrThrow();var b=block(blockName);var d=b.getStateDefinition();var map=def.instantiate(d,()->"reference:"+blockName);var j=new JsonObject();j.addProperty("status","ok");var selectors=new JsonArray();
  if(def.simpleModels().isPresent())for(var e:new TreeMap<>(def.simpleModels().get().models()).entrySet()){var o=new JsonObject();o.addProperty("kind","simple");o.addProperty("selector",e.getKey());o.add("model",desc(e.getValue()));try{o.add("matches_state_ids",stateMatches(s0->VariantSelector.predicate(d,e.getKey()).test(s0),b));}catch(Throwable ex){o.add("predicate_error",err(ex));}if(e.getValue() instanceof WeightedVariants.Unbaked w){var samples=new JsonObject();for(long seed:new long[]{0,42,-1}){var rng=net.minecraft.util.RandomSource.create(seed);var a=new JsonArray();for(int i=0;i<16;i++)a.add(desc(w.entries().getRandom(rng)));samples.add(Long.toString(seed),a);}o.add("weighted_random_samples",samples);}selectors.add(o);}
  if(def.multiPart().isPresent()){int i=0;for(var s0:def.multiPart().get().selectors()){var o=new JsonObject();o.addProperty("kind","multipart");o.addProperty("index",i++);o.add("condition",desc(s0.condition()));o.add("model",desc(s0.variant()));var pred=s0.instantiate(d);o.add("matches_state_ids",stateMatches(pred,b));selectors.add(o);}}
  j.add("selectors",selectors);var states=new JsonArray();for(var state:d.getPossibleStates()){var o=new JsonObject();o.addProperty("state_id",Block.getId(state));o.addProperty("state",state.toString());var root=map.get(state);o.addProperty("mapped",root!=null);if(root!=null){var dependencies=new TreeSet<String>();root.resolveDependencies(id->dependencies.add(id.toString()));o.add("root_dependencies",desc(dependencies));if(root instanceof MultiPartModel.Unbaked){var key=root.visualEqualityGroup(state);var acc=key.getClass().getDeclaredMethod("selectors");acc.setAccessible(true);o.add("selected_multipart_indices",desc(acc.invoke(key)));}}states.add(o);}j.add("states",states);return j;
 }
 public static void main(String[] args)throws Exception {
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();var in=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonObject();JAR=new ZipFile(args[1]);
  DEFAULT_UV=FaceBakery.class.getDeclaredMethod("defaultFaceUV",Vector3fc.class,Vector3fc.class,Direction.class);DEFAULT_UV.setAccessible(true);DIRECTIONAL=BlockModelLighter.class.getDeclaredMethod("getDirectionalBrightness",CardinalLighting.class,BakedQuad.class,Direction.class);DIRECTIONAL.setAccessible(true);
  var img=new NativeImage(16,16,true);img.fillRect(0,0,16,16,0xffff00ff);var contents=new SpriteContents(Identifier.parse("minecraft:missingno"),new FrameSize(16,16),img);var ctor=TextureAtlasSprite.class.getDeclaredConstructor(Identifier.class,SpriteContents.class,int.class,int.class,int.class,int.class,int.class);ctor.setAccessible(true);MISSING=(TextureAtlasSprite)ctor.newInstance(TextureAtlas.LOCATION_BLOCKS,contents,16,16,0,0,0);
  var out=new JsonObject();var parsed=new JsonObject();for(var e:in.getAsJsonObject("models").entrySet())parsed.add(e.getKey(),desc(parse(e.getValue().getAsString())));out.add("parsed_official_models",parsed);
  var roots=new ArrayList<String>(in.getAsJsonObject("models").keySet());Collections.sort(roots);var models=resolve(in.getAsJsonObject("models"),roots);var resolved=new JsonObject();for(var id:roots)resolved.add(id,resolved(models.get(Identifier.parse(id))));out.add("resolved_official_models",resolved);
  var states=new JsonObject();for(var e:in.getAsJsonObject("blockstates").entrySet())states.add(e.getKey(),dispatcher(e.getValue().getAsString(),e.getKey()));out.add("official_blockstates",states);
  var baked=new JsonArray();for(var input:in.getAsJsonArray("variants")){var j=input.getAsJsonObject();var o=new JsonObject();o.add("input",j);try{var v=Variant.CODEC.parse(JsonOps.INSTANCE,j).getOrThrow();o.add("result",bake(models,v.modelLocation().toString(),v.modelState()));o.addProperty("status","ok");}catch(Throwable e){o.add("result",err(e));o.addProperty("status","error");}baked.add(o);}out.add("baked_variants",baked);
  var cases=new JsonArray();for(var input:in.getAsJsonArray("parse_cases")){var j=input.getAsJsonObject();var o=new JsonObject();o.addProperty("id",j.get("id").getAsString());try{var m=parse(j.get("json").getAsString());o.addProperty("status","ok");o.add("parsed",desc(m));if(j.get("bake").getAsBoolean()){var mm=new JsonObject();mm.addProperty("test:model",j.get("json").getAsString());o.add("baked",bake(resolve(mm,List.of("test:model")),"test:model",Variant.SimpleModelState.DEFAULT));}}catch(Throwable e){o.add("error",err(e));o.addProperty("status","error");}cases.add(o);}out.add("parse_cases",cases);
  var graphs=new JsonArray();for(var input:in.getAsJsonArray("graph_cases")){var j=input.getAsJsonObject();var o=new JsonObject();o.addProperty("id",j.get("id").getAsString());try{var rr=new ArrayList<String>();for(var x:j.getAsJsonArray("roots"))rr.add(x.getAsString());var mm=resolve(j.getAsJsonObject("models"),rr);var r=new JsonObject();for(var e:new TreeMap<>(mm).entrySet())r.add(e.getKey().toString(),resolved(e.getValue()));o.add("resolved",r);o.addProperty("status","ok");}catch(Throwable e){o.add("error",err(e));o.addProperty("status","error");}graphs.add(o);}out.add("graph_cases",graphs);
  var sels=new JsonArray();for(var input:in.getAsJsonArray("selector_cases")){var j=input.getAsJsonObject();var o=new JsonObject();o.addProperty("id",j.get("id").getAsString());try{var b=block(j.get("block").getAsString());var pred=VariantSelector.predicate(b.getStateDefinition(),j.get("selector").getAsString());o.add("matches_state_ids",stateMatches(s->pred.test(s),b));o.addProperty("status","ok");}catch(Throwable e){o.add("error",err(e));o.addProperty("status","error");}sels.add(o);}out.add("selector_cases",sels);
  var cons=new JsonArray();for(var input:in.getAsJsonArray("condition_cases")){var j=input.getAsJsonObject();var o=new JsonObject();o.addProperty("id",j.get("id").getAsString());try{var c=Condition.CODEC.parse(JsonOps.INSTANCE,j.get("condition")).getOrThrow();var b=block(j.get("block").getAsString());o.add("parsed",desc(c));o.add("matches_state_ids",stateMatches(c.instantiate(b.getStateDefinition()),b));o.addProperty("status","ok");}catch(Throwable e){o.add("error",err(e));o.addProperty("status","error");}cons.add(o);}out.add("condition_cases",cons);
  var ds=new JsonArray();for(var input:in.getAsJsonArray("dispatcher_cases")){var j=input.getAsJsonObject();var o=new JsonObject();o.addProperty("id",j.get("id").getAsString());try{o.add("result",dispatcher(j.get("json").getAsString(),j.get("block").getAsString()));o.addProperty("status","ok");}catch(Throwable e){o.add("error",err(e));o.addProperty("status","error");}ds.add(o);}out.add("dispatcher_cases",ds);
  var lighting=new JsonObject();for(var e:Map.of("default",CardinalLighting.DEFAULT,"nether",CardinalLighting.NETHER).entrySet()){var o=new JsonObject();for(var d:Direction.values())o.addProperty(d.toString(),bits(e.getValue().byFace(d)));lighting.add(e.getKey(),o);}out.add("cardinal_lighting_f32",lighting);
  Files.writeString(Path.of(args[2]),G.toJson(out));for(var s:SPRITES.values())s.close();MISSING.close();JAR.close();
 }
}
'''

def source_records(cp):
    with zipfile.ZipFile(CLIENT)as z:
        prefixes=['net/minecraft/client/resources/model/cuboid/','net/minecraft/client/resources/model/sprite/TextureSlots','net/minecraft/client/resources/model/ModelDiscovery','net/minecraft/client/resources/model/ResolvedModel','net/minecraft/client/renderer/block/dispatch/Variant','net/minecraft/client/renderer/block/dispatch/BlockStateModel','net/minecraft/client/renderer/block/dispatch/SingleVariant','net/minecraft/client/renderer/block/dispatch/WeightedVariants','net/minecraft/client/renderer/block/dispatch/multipart/','net/minecraft/client/resources/model/geometry/BakedQuad','net/minecraft/client/resources/model/geometry/QuadCollection','net/minecraft/client/renderer/texture/TextureAtlasSprite','net/minecraft/client/renderer/texture/SpriteContents','net/minecraft/client/resources/model/sprite/Material','net/minecraft/client/renderer/block/BlockModelLighter','net/minecraft/client/renderer/FaceInfo','net/minecraft/world/level/CardinalLighting','net/minecraft/client/model/geom/builders/UVPair','com/mojang/math/Quadrant','com/mojang/math/BlockMath']
        prefixes+=['net/minecraft/client/resources/model/geometry/UnbakedGeometry','net/minecraft/client/resources/model/UnbakedModel','net/minecraft/client/resources/model/ResolvableModel','net/minecraft/client/resources/model/ModelBaker','net/minecraft/client/resources/model/ModelDebugName','net/minecraft/client/renderer/texture/SpriteLoader','net/minecraft/client/renderer/texture/TextureAtlas','net/minecraft/client/renderer/texture/MissingTextureAtlasSprite','net/minecraft/client/resources/metadata/animation/FrameSize','com/mojang/blaze3d/platform/NativeImage','com/mojang/blaze3d/platform/Transparency','net/minecraft/resources/Identifier','net/minecraft/util/GsonHelper','net/minecraft/util/random/WeightedList','net/minecraft/util/random/Weighted','net/minecraft/util/RandomSource']
        names=sorted(n for n in z.namelist()if n.endswith('.class')and any(n.startswith(p)for p in prefixes));records=[{'class':n[:-6].replace('/','.'),'bytes':len(z.read(n)),'sha256':sha(z.read(n))}for n in names]
    targets=[r['class']for r in records]
    run=subprocess.run([str(JAVA.with_name('javap')),'-p','-c','-classpath',':'.join(map(str,cp)),*targets],capture_output=True,text=True,check=True)
    p=CACHE/'official-javap.txt';p.write_text(run.stdout)
    return {'classes':records,'javap':fingerprint(p),'java_harness_sha256':sha(JAVA_SOURCE.encode()),'method_authority':'Production declarations/bytecode plus actual execution; no downloaded decompiler'}

def execute(inputs,cp,tag):
    CACHE.mkdir(parents=True,exist_ok=True);(CACHE/'ReferenceModelProbe.java').write_text(JAVA_SOURCE);ip=CACHE/(tag+'-inputs.json');op=CACHE/(tag+'-observations.json');ip.write_bytes(canonical(inputs));cmd=[str(JAVA),'--enable-native-access=ALL-UNNAMED','-cp',':'.join(map(str,cp)),str(CACHE/'ReferenceModelProbe.java'),str(ip),str(CLIENT),str(op)]
    run=subprocess.run(cmd,cwd=CACHE,capture_output=True,text=True,timeout=180);(CACHE/(tag+'-stdout.log')).write_text(run.stdout);(CACHE/(tag+'-stderr.log')).write_text(run.stderr)
    if run.returncode:raise RuntimeError('Java model probe failed: '+run.stderr[-6000:]+run.stdout[-6000:])
    observations=json.loads(op.read_text());return observations,{'exit_code':run.returncode,'raw_observation_sha256':sha(op.read_bytes()),'canonical_observation_sha256':sha(canonical(observations)),'stdout_log':fingerprint(CACHE/(tag+'-stdout.log')),'stderr_log':fingerprint(CACHE/(tag+'-stderr.log'))}

def counts(obs):
    return {'official_models':len(obs['parsed_official_models']),'official_blocks':len(obs['official_blockstates']),'official_states':sum(len(b['states'])for b in obs['official_blockstates'].values()),'baked_variants':len(obs['baked_variants']),'baked_quads':sum(b.get('result',{}).get('quad_count',0)for b in obs['baked_variants']),'bake_errors':sum(b['status']!='ok'for b in obs['baked_variants']),'parse_cases':len(obs['parse_cases']),'parse_errors':sum(c['status']!='ok'for c in obs['parse_cases']),'graph_cases':len(obs['graph_cases']),'selector_cases':len(obs['selector_cases']),'condition_cases':len(obs['condition_cases']),'dispatcher_cases':len(obs['dispatcher_cases'])}

def validate(data,inputs=None,observations=None,provenance=None,source=None):
    if data.get('schema')!=1 or data.get('pin')!='26.3':raise ValueError('Model reference schema/pin mismatch')
    if sha(canonical(data['inputs']))!=data['inputs_sha256']:raise ValueError('Model input checksum mismatch')
    if sha(canonical(data['observations']))!=data['observations_sha256']:raise ValueError('Model observation checksum mismatch')
    if inputs is not None and data['inputs']!=inputs:raise ValueError('Model fixtures differ from pinned resources and generated inputs')
    if observations is not None and data['observations']!=observations:raise ValueError('Model observations differ from fresh Java execution')
    if provenance is not None and data['provenance']!=provenance:raise ValueError('Model provenance differs from verified artifacts')
    if source is not None and data['source']!=source:raise ValueError('Model class/declaration/harness fingerprints differ from pinned bytes')
    if data['counts']!=counts(data['observations']):raise ValueError('Model counts mismatch')
    if data['counts']['bake_errors']:raise ValueError('Official fixture geometry bake error')
    for b in data['observations']['baked_variants']:
        r=b['result'];quads=[q for group in r['quad_groups'].values()for q in group]
        if len(quads)!=r['quad_count']:raise ValueError('Quad group count mismatch')
        for q in quads:
            if len(q['vertices'])!=4:raise ValueError('Invalid vertex arity')
            for v in q['vertices']:
                if len(v['position_f32'])!=3 or len(v['uv_f32'])!=2 or len(v['packed_uv_u64'])!=16:raise ValueError('Invalid bit fixture encoding')
                if any(len(s)!=8 or any(c not in '0123456789abcdef'for c in s)for s in v['position_f32']+v['uv_f32']):raise ValueError('Invalid raw F32 bits')
                if v['packed_uv_u64']!=v['uv_f32'][0]+v['uv_f32'][1]:raise ValueError('Production UVPair packing mismatch')
    return {'status':'pass','counts':data['counts'],'observations_sha256':data['observations_sha256']}

def extract():
    cp,provenance=verified_client_classpath();inputs=build_inputs();obs,run=execute(inputs,cp,'extract');source=source_records(cp)
    data={'schema':1,'pin':'26.3','scope':'Actual production CuboidModel/TextureSlots/ModelDiscovery/Variant/property codecs and predicates, ResolvedModel inheritance, UnbakedCuboidGeometry.bake, FaceBakery and material classification using actual resource PNGs in a controlled normalized atlas; no client activation, production atlas stitching, GPU upload, frame, biome tint, world lighting or AO oracle','float_encoding':'lowercase 8-digit Float.floatToRawIntBits; vector and matrix coordinates F32; matrix arrays JOML column-major; packedUV unsigned64 hex, production UVPair unpacked U/V F32','atlas_boundary':{'sprite_inputs':'Actual pinned PNGs decoded by production NativeImage.read and SpriteContents; no animation metadata/mipmap generation','atlas':'Each sprite uses atlas width/height equal to its image width/height, placement0,0 and padding0; all regions intentionally overlap as controlled normalized UV inputs, not a valid production atlas layout','model_baker':'Identity production interner, actual MaterialBaker with controlled SpriteLoader.Preparations; no GPU calls or client instance','missing_sprite':'CPU16x16opaque magenta synthetic image, only missing-material replacement; does not copy production missingno asset'},'provenance':provenance,'source':source,'inputs':inputs,'inputs_sha256':sha(canonical(inputs)),'observations':obs,'observations_sha256':sha(canonical(obs)),'counts':counts(obs)}
    data['oracle_version']='java26.3-client-model-probe-v1';data['atlas_boundary']['missing_parent_model']='ModelDiscovery fallback is explicit CuboidModel.fromStream({}); parent cycles/filtering/fallback behavior measured, production missing-model geometry is not substituted'
    check=validate(data,inputs,obs,provenance,source);write_json(OUTPUT,data);write_json(ROOT/'evidence/model-reference-probe.json',{'pin':'26.3','status':'pass','run':run,'output':fingerprint(OUTPUT),'counts':data['counts'],'java_harness_sha256':source['java_harness_sha256']});write_json(ROOT/'evidence/model-reference-validation.json',check);print(json.dumps(check))

def selftest():
    cp,provenance=verified_client_classpath();source=source_records(cp);data=json.loads(OUTPUT.read_text());inputs=build_inputs();a,ra=execute(inputs,cp,'reproduce-a');b,rb=execute(inputs,cp,'reproduce-b')
    if a!=b:raise ValueError('Fresh Java model runs differ')
    validate(data,inputs,a,provenance,source);faults=[]
    def reject(name,d,obs=a):
        try:validate(d,inputs,obs,provenance,source)
        except(ValueError,KeyError,TypeError)as e:faults.append({'fault':name,'status':'rejected','reason':str(e)});return
        raise ValueError('Malformed model reference accepted: '+name)
    bad=copy.deepcopy(data);bad['observations']['baked_variants'][0]['result']['quad_groups']['down'][0]['vertices'][0]['uv_f32'][0]='3f000000';reject('changed_raw_uv_unsealed',bad)
    bad['observations_sha256']=sha(canonical(bad['observations']));reject('changed_raw_uv_resealed_vs_fresh_java',bad)
    bad=copy.deepcopy(data);bad['inputs']['models']['minecraft:block/stone']=bad['inputs']['models']['minecraft:block/stone'].replace('stone','dirt');bad['inputs_sha256']=sha(canonical(bad['inputs']));reject('changed_official_model_resealed_vs_pinned_inputs',bad)
    bad=copy.deepcopy(data);bad['observations']['cardinal_lighting_f32']['default']['down']='3f4ccccd';bad['observations_sha256']=sha(canonical(bad['observations']));reject('changed_lighting_resealed_vs_java',bad)
    bad=copy.deepcopy(data);bad['source']['java_harness_sha256']='0'*64;reject('changed_harness_hash',bad)
    bad=copy.deepcopy(data);bad['source']['classes'][0]['sha256']='0'*64;reject('changed_official_class_hash',bad)
    bad=copy.deepcopy(data);bad['provenance']['libraries'][0]['sha256']='0'*64;reject('changed_library_hash',bad)
    evidence={'pin':'26.3','status':'pass','fresh_java_runs':[ra,rb],'canonical_results_equal':a==b,'fresh_inputs_equal':data['inputs']==inputs,'fresh_java_equals_committed':data['observations']==a,'failure_injections':faults,'counts':data['counts'],'output':fingerprint(OUTPUT)};write_json(ROOT/'evidence/model-reference-selftest.json',evidence);print(json.dumps({'status':'pass','counts':data['counts'],'faults_rejected':len(faults)}))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action',choices=['extract','validate','selftest']);args=p.parse_args()
    if args.action=='extract':extract()
    elif args.action=='selftest':selftest()
    else:
        cp,provenance=verified_client_classpath();data=json.loads(OUTPUT.read_text());inputs=build_inputs();obs,_=execute(inputs,cp,'validate');check=validate(data,inputs,obs,provenance,source_records(cp));write_json(ROOT/'evidence/model-reference-validation.json',check);print(json.dumps(check))
