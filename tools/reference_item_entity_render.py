#!/usr/bin/env python3
"""Observe actual pinned CPU item bake/submission and XP billboard receivers."""
from __future__ import annotations
import hashlib,json,os,pathlib,sys,zipfile
import reference_model_probe as R
import test_campfire_authority as T
ROOT=T.ROOT;WORK=ROOT/'build/item-entity-render-reference'
JAVA_SOURCE=r'''
import com.google.gson.*;
import com.mojang.math.*;
import com.mojang.blaze3d.vertex.*;
import net.minecraft.client.renderer.entity.*;
import net.minecraft.client.renderer.entity.state.*;
import net.minecraft.client.renderer.item.*;
import net.minecraft.client.renderer.*;
import net.minecraft.client.renderer.state.level.*;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.item.*;
import net.minecraft.util.Mth;
import sun.misc.Unsafe;
CLASS_PREFIX
 static Unsafe U;
 static class IconOrb extends net.minecraft.world.entity.ExperienceOrb {int observed;IconOrb(){super(null,0,0,0,1);}@Override public int getValue(){return observed;}}
 static class Tracking extends ItemStackRenderState {
  JsonArray draws=new JsonArray(); Matrix4f ground=new Matrix4f();List<BakedQuad> quads;
  Tracking(ResolvedModel m,List<BakedQuad> q)throws Exception{
   quads=q;var dc=ItemStackRenderState.class.getDeclaredField("displayContext");dc.setAccessible(true);dc.set(this,ItemDisplayContext.GROUND);var layer=newLayer();layer.setItemTransform(m.getTopTransforms().ground());
   var extents=new ArrayList<Vector3fc>();for(var quad:q)for(int i=0;i<4;i++)extents.add(quad.position(i));layer.setExtents(()->extents.toArray(Vector3fc[]::new));
   var p=new PoseStack();m.getTopTransforms().ground().apply(false,p.last());ground.set(p.last().pose());
  }
  @Override public boolean isEmpty(){return quads.isEmpty();}
  @Override public void submit(PoseStack p,SubmitNodeCollector c,int light,int overlay,int outline){
   var d=new JsonObject();d.add("pose",descUnchecked(p.last().pose()));var v=new JsonArray();var mat=new Matrix4f(p.last().pose()).mul(ground);
   if(!quads.isEmpty()){var q=quads.get(0);var vs=new JsonArray();for(int i=0;i<4;i++)vs.add(descUnchecked(mat.transformPosition(new Vector3f(q.position(i)))));v.add(vs);}d.add("first_quad",v);draws.add(d);
  }
 }
 static JsonElement descUnchecked(Object o){try{return desc(o);}catch(Exception e){throw new RuntimeException(e);}}
 static Object defaultValue(Class<?> c){if(!c.isPrimitive())return null;if(c==boolean.class)return false;if(c==float.class)return 0f;if(c==double.class)return 0d;return 0;}
 static SubmitNodeCollector collector(JsonArray vertices){return(SubmitNodeCollector)Proxy.newProxyInstance(SubmitNodeCollector.class.getClassLoader(),new Class[]{SubmitNodeCollector.class},(proxy,m,args)->{
  if(m.getName().equals("submitCustomGeometry")){
   var pose=((PoseStack)args[0]).last();var renderer=(SubmitNodeCollector.CustomGeometryRenderer)args[2];
   VertexConsumer v=(VertexConsumer)Proxy.newProxyInstance(VertexConsumer.class.getClassLoader(),new Class[]{VertexConsumer.class},(self,method,a)->{
    if(method.isDefault())return InvocationHandler.invokeDefault(self,method,a);
    if(method.getName().equals("addVertex")){var o=new JsonObject();o.add("position",arr(bits((float)a[0]),bits((float)a[1]),bits((float)a[2])));vertices.add(o);}
    else if(vertices.size()>0){var o=vertices.get(vertices.size()-1).getAsJsonObject();if(method.getName().equals("setColor"))o.add("color",descUnchecked(Arrays.asList(a)));else if(method.getName().equals("setUv"))o.add("uv",arr(bits((float)a[0]),bits((float)a[1])));else if(method.getName().equals("setLight"))o.addProperty("light",(int)a[0]);}
    return method.getReturnType()==VertexConsumer.class?self:defaultValue(method.getReturnType());
   });renderer.render(pose,v);
  }
  return defaultValue(m.getReturnType());
 });}
 public static void main(String[]args)throws Exception{
  try{
   SharedConstants.tryDetectVersion();Bootstrap.bootStrap();var uf=Unsafe.class.getDeclaredField("theUnsafe");uf.setAccessible(true);U=(Unsafe)uf.get(null);JAR=new ZipFile(args[0]);
   var lookup=net.minecraft.data.registries.VanillaRegistries.createWorldLookup();for(var p:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup))p.forEach((h,c)->h.bindComponents(c));
   DEFAULT_UV=FaceBakery.class.getDeclaredMethod("defaultFaceUV",Vector3fc.class,Vector3fc.class,Direction.class);DEFAULT_UV.setAccessible(true);DIRECTIONAL=BlockModelLighter.class.getDeclaredMethod("getDirectionalBrightness",CardinalLighting.class,BakedQuad.class,Direction.class);DIRECTIONAL.setAccessible(true);
   var modelInputs=new HashMap<Identifier,UnbakedModel>();var itemModels=new LinkedHashMap<String,String>();var hashes=new JsonObject();
   for(String id:new String[]{"stone","cooked_beef","iron_ingot","suspicious_stew"}){String path="assets/minecraft/items/"+id+".json";byte[]raw=JAR.getInputStream(JAR.getEntry(path)).readAllBytes();hashes.addProperty(path,sha(raw));var item=JsonParser.parseString(new String(raw,java.nio.charset.StandardCharsets.UTF_8)).getAsJsonObject();String model=item.getAsJsonObject("model").get("model").getAsString();itemModels.put(id,model);load(model,modelInputs,hashes);}
   modelInputs.put(ItemModelGenerator.GENERATED_ITEM_MODEL_ID,new ItemModelGenerator());var discovery=new ModelDiscovery(modelInputs,CuboidModel.fromStream(new StringReader("{}")));discovery.addRoot(x->{for(var id:itemModels.values())x.markDependency(Identifier.parse(id));});var models=discovery.resolve();
   var out=new JsonObject();var cases=new JsonArray();
   for(var entry:itemModels.entrySet()){
    String id=entry.getKey();var m=models.get(Identifier.parse(entry.getValue()));var b=baker(models,m);var qs=m.bakeTopGeometry(m.getTopTextureSlots(),b,Variant.SimpleModelState.DEFAULT.asModelState()).getAll();
    var item=new ItemStack(BuiltInRegistries.ITEM.getValue(Identifier.parse("minecraft:"+id)));var shape=new JsonObject();shape.addProperty("item",id);shape.addProperty("model",entry.getValue());var raw=new JsonArray();for(var q:qs)raw.add(quad(q));shape.add("quads",raw);var track=new Tracking(m,qs);var bb=track.getModelBoundingBox();shape.add("low",arr(bits((float)bb.minX),bits((float)bb.minY),bits((float)bb.minZ)));shape.add("high",arr(bits((float)bb.maxX),bits((float)bb.maxY),bits((float)bb.maxZ)));shape.add("ground_matrix",descUnchecked(track.ground));out.add(id,shape);
    for(int count:new int[]{1,2,16,17,32,33,48,49,64})for(float age:new float[]{0.5f,33.25f}){
     item.setCount(count);var state=new ItemEntityRenderState();var field=ItemClusterRenderState.class.getDeclaredField("item");field.setAccessible(true);var t=new Tracking(m,qs);field.set(state,t);state.count=ItemClusterRenderState.getRenderedAmount(count);state.seed=ItemClusterRenderState.getSeedForItemStack(item);state.ageInTicks=age;state.bobOffset=0.5f;
     var renderer=(ItemEntityRenderer)U.allocateInstance(ItemEntityRenderer.class);var rng=ItemEntityRenderer.class.getDeclaredField("random");rng.setAccessible(true);rng.set(renderer,net.minecraft.util.RandomSource.create(0));
     var pose=new PoseStack();var bounds=t.getModelBoundingBox();float hover=(Mth.sin(age/10f+state.bobOffset)*.1f+.1f)+(-(float)bounds.minY+.0625f);float spin=ItemEntity.getSpin(age,state.bobOffset);
     pose.translate(0,hover,0);pose.rotate(Axis.YP,spin);ItemEntityRenderer.submitMultipleFromCount(pose,collector(new JsonArray()),0,state,net.minecraft.util.RandomSource.create(0),bounds);
     var row=new JsonObject();row.addProperty("item",id);row.addProperty("count",count);row.addProperty("age",bits(age));row.addProperty("hover",bits(hover));row.addProperty("spin",bits(spin));row.addProperty("copies",state.count);row.addProperty("seed",state.seed);row.add("draws",t.draws);cases.add(row);
    }
   }
   var orbs=new JsonArray();for(int value:new int[]{1,3,7,17,37,73,149,307,617,1237,2477})for(float age:new float[]{0.5f,33.25f}){
    var state=new ExperienceOrbRenderState();state.ageInTicks=age;var orb=(IconOrb)U.allocateInstance(IconOrb.class);orb.observed=value;state.icon=orb.getIcon();state.lightCoords=net.minecraft.util.LightCoordsUtil.pack(7,15);
    var renderer=(ExperienceOrbRenderer)U.allocateInstance(ExperienceOrbRenderer.class);var camera=new CameraRenderState();camera.orientation=new Quaternionf();var vertices=new JsonArray();renderer.submit(state,new PoseStack(),collector(vertices),camera);var row=new JsonObject();row.addProperty("value",value);row.addProperty("age",bits(age));row.addProperty("icon",state.icon);row.add("vertices",vertices);orbs.add(row);
   }
   out.add("cases",cases);out.add("orbs",orbs);out.add("resources",hashes);Files.writeString(Path.of(args[1]),G.toJson(out));
  }catch(Throwable e){e.printStackTrace(new PrintStream(new FileOutputStream(FileDescriptor.err)));System.exit(1);}
 }
 static String sha(byte[]b)throws Exception{return java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(b));}
 static void load(String id,Map<Identifier,UnbakedModel>out,JsonObject hashes)throws Exception{
  var rid=Identifier.parse(id);if(out.containsKey(rid)||rid.equals(ItemModelGenerator.GENERATED_ITEM_MODEL_ID))return;String p="assets/"+rid.getNamespace()+"/models/"+rid.getPath()+".json";byte[]raw=JAR.getInputStream(JAR.getEntry(p)).readAllBytes();hashes.addProperty(p,sha(raw));String s=new String(raw,java.nio.charset.StandardCharsets.UTF_8);out.put(rid,CuboidModel.fromStream(new StringReader(s)));var j=JsonParser.parseString(s).getAsJsonObject();if(j.has("parent"))load(j.get("parent").getAsString().contains(":")?j.get("parent").getAsString():"minecraft:"+j.get("parent").getAsString(),out,hashes);
 }
}
'''
def source():
    # Read-only reuse of previously audited controlled-atlas reference helpers.
    j=R.JAVA_SOURCE
    imports=j[:j.index('class ReferenceModelProbe')]
    helpers=j[j.index(' static ZipFile JAR'):j.index(' static JsonObject dispatcher(')]
    # Includes the old graph resolver, unused; no authority rewritten/substituted.
    return JAVA_SOURCE.replace('CLASS_PREFIX',imports+'class ReferenceItemEntityRender {\n static Gson G=new GsonBuilder().serializeNulls().disableHtmlEscaping().create();\n'+helpers)
def main():
    WORK.mkdir(parents=True,exist_ok=True);T.WORK=WORK
    cp,provenance=R.verified_client_classpath();p=WORK/'ReferenceItemEntityRender.java';p.write_text(source())
    result=T.run('java',[R.JAVA,'-Xmx512m','--source','25','--class-path',os.pathsep.join(map(str,cp)),p,R.CLIENT,WORK/'observations.json'],timeout=60,max_rss=900*1024**2)
    obs=json.loads((WORK/'observations.json').read_text());assert len(obs['cases'])==72 and len(obs['orbs'])==22
    value={'schema':1,'pin':'26.3','scope':'Actual ItemModelGenerator/FaceBakery ground geometry, actual item cluster submissions and ExperienceOrbRenderer CPU billboard submissions; controlled normalized sprite UV atlas; no GPU/world lightmap/client activation','java_receiver':result,'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'provenance':provenance,'observations':obs}
    (ROOT/'reference/item_entity_render.json').write_text(json.dumps(value,indent=2)+'\n');print(json.dumps({'items':4,'clusters':72,'orbs':22,'status':'passed'}))
if __name__=='__main__':main()
