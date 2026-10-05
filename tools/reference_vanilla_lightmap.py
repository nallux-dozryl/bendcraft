#!/usr/bin/env python3
"""Pinned real lightmap helpers and installed fragment shader, no client/window."""
import hashlib,json,os,random,struct,zipfile
import reference_model_probe as R
import test_campfire_authority as T
ROOT=T.ROOT;WORK=ROOT/'build/vanilla-lightmap-reference'
def bits(x):return struct.unpack('<I',struct.pack('<f',x))[0]
def f(w):return struct.unpack('<f',struct.pack('<I',w))[0]
JAVA=r'''
import java.nio.file.*;import java.lang.reflect.*;import java.util.*;import com.google.gson.*;import org.joml.Vector3fc;import sun.misc.Unsafe;
import net.minecraft.SharedConstants;import net.minecraft.server.Bootstrap;
import net.minecraft.client.renderer.*;import net.minecraft.client.renderer.state.*;import net.minecraft.client.player.LocalPlayer;
import net.minecraft.world.entity.LivingEntity;import net.minecraft.world.effect.*;import net.minecraft.util.RandomSource;
import net.minecraft.world.attribute.EnvironmentAttributes;
class ReferenceVanillaLightmap {
 static Unsafe U;static Field field(Class<?>c,String n)throws Exception{var f=c.getDeclaredField(n);f.setAccessible(true);return f;}
 static long b(float f){return Integer.toUnsignedLong(Float.floatToRawIntBits(f));}
 static JsonArray a(float...xs){var a=new JsonArray();for(float x:xs)a.add(b(x));return a;}
 static float ff(JsonElement e){return Float.intBitsToFloat(e.getAsInt());}
 static JsonArray words(Object o){var v=(Vector3fc)o;return a(v.x(),v.y(),v.z());}
 public static void main(String[]args)throws Exception{try{
  U=(Unsafe)field(Unsafe.class,"theUnsafe").get(null);SharedConstants.tryDetectVersion();Bootstrap.bootStrap();
  var input=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonObject();var out=new JsonObject();var ticks=new JsonArray();
  for(var row:input.getAsJsonArray("ticks")){
   var r=row.getAsJsonObject();var ex=new LightmapRenderStateExtractor(null,null);var rng=(RandomSource)field(LightmapRenderStateExtractor.class,"randomSource").get(ex);
   var seed=r.getAsJsonArray("seed");rng.setSeed((seed.get(0).getAsLong()<<32)|seed.get(1).getAsLong());
   var vals=new JsonArray();for(int i=0;i<r.get("count").getAsInt();i++){
    ex.tick();var v=new JsonObject();v.addProperty("flicker",b(field(LightmapRenderStateExtractor.class,"blockLightFlicker").getFloat(ex)));v.addProperty("dirty",field(LightmapRenderStateExtractor.class,"needsUpdate").getBoolean(ex));
    var rngseed=field(rng.getClass(),"seed").get(rng);long state=((java.util.concurrent.atomic.AtomicLong)rngseed).get();v.add("seed",aWords(state));vals.add(v);
   }ticks.add(vals);
  }out.add("ticks",ticks);
  var living=(LocalPlayer)U.allocateInstance(LocalPlayer.class);var extractor=(LightmapRenderStateExtractor)U.allocateInstance(LightmapRenderStateExtractor.class);
  var method=LightmapRenderStateExtractor.class.getDeclaredMethod("calculateDarknessScale",LivingEntity.class,float.class,float.class);method.setAccessible(true);
  var prepared=new JsonArray();for(var row:input.getAsJsonArray("prepares")){
   var r=row.getAsJsonObject();float p=ff(r.get("partial")),setting=(float)r.get("darkness_scale").getAsDouble(),blend=ff(r.get("blend"))*setting;
   living.tickCount=r.get("tick_count").getAsInt();float darkness=((Float)method.invoke(extractor,living,blend,p))*setting;
   float nv;if(r.get("night_duration").isJsonNull()){nv=ff(r.get("water"))>0&&r.get("conduit").getAsBoolean()?ff(r.get("water")):0;}else{
    var effects=new HashMap<>();effects.put(MobEffects.NIGHT_VISION,new MobEffectInstance(MobEffects.NIGHT_VISION,r.get("night_duration").getAsInt()));field(LivingEntity.class,"activeEffects").set(living,effects);nv=GameRenderer.nightVisionScale(living,p);
   }
   float flash=0;var fs=r.get("flash");if(!fs.isJsonNull()&&!r.get("hide_flash").getAsBoolean()){
    var state=new EndFlashState();field(EndFlashState.class,"oldIntensity").setFloat(state,ff(fs.getAsJsonArray().get(0)));field(EndFlashState.class,"intensity").setFloat(state,ff(fs.getAsJsonArray().get(1)));flash=state.getIntensity(p);if(r.get("boss_fog").getAsBoolean())flash/=3f;
   }
   var renderer=(GameRenderer)U.allocateInstance(GameRenderer.class);var boss=r.getAsJsonArray("boss");field(GameRenderer.class,"bossOverlayWorldDarkeningO").setFloat(renderer,ff(boss.get(0)));field(GameRenderer.class,"bossOverlayWorldDarkening").setFloat(renderer,ff(boss.get(1)));
   var env=r.getAsJsonArray("environment");var values=a(ff(env.get(3))+flash,ff(r.get("flicker"))+1.4f,nv,darkness,renderer.bossOverlayWorldDarkening(p),Math.max(0f,(float)r.get("gamma").getAsDouble()-blend));
   for(int i:new int[]{0,1,2,4,5,6,7,8,9,10,11,12})values.add(env.get(i));prepared.add(values);
  }out.add("prepares",prepared);
  var attrs=new JsonObject();attrs.add("block_tint",words(EnvironmentAttributes.BLOCK_LIGHT_TINT.defaultValue()));attrs.addProperty("sky_factor",b(EnvironmentAttributes.SKY_LIGHT_FACTOR.defaultValue()));attrs.add("sky_color",words(EnvironmentAttributes.SKY_LIGHT_COLOR.defaultValue()));attrs.add("ambient",words(EnvironmentAttributes.AMBIENT_LIGHT_COLOR.defaultValue()));attrs.add("night_color",words(EnvironmentAttributes.NIGHT_VISION_COLOR.defaultValue()));out.add("attribute_defaults",attrs);
  out.addProperty("java_ubo_bytes",field(Lightmap.class,"LIGHTMAP_UBO_SIZE").getInt(null));Files.writeString(Path.of(args[1]),new Gson().toJson(out));
 }catch(Throwable e){e.printStackTrace(new java.io.PrintStream(new java.io.FileOutputStream(java.io.FileDescriptor.err)));System.exit(2);}}
 static JsonArray aWords(long l){var a=new JsonArray();a.add((l>>>32)&0xffffffffL);a.add(l&0xffffffffL);return a;}
}
'''
def inputs():
 rng=random.Random(263);prepares=[]
 for i in range(28):
  p=[0,.25,.5,.9,1][i%5];env=[bits(x)for x in [.9,.78,.58,.65,.8,.9,1,.04,.04,.04,1,1,1]]
  if i%4==1:env=[bits(x)for x in [.9,.78,.58,0,.48,.48,1,.188,.157,.129,1,1,1]]
  if i%4==2:env=[bits(x)for x in [.9,.78,.58,0,.675,.376,.804,.247,.278,.247,1,1,1]]
  if i%4==3:env=[bits(rng.random())for _ in range(13)]
  prepares.append({'environment':env,'tick_count':[0,10,35,150,0xffffffff,0x80000000,0x7fffffff][i%7],'partial':bits(p),'blend':bits([0,.25,.75,1][i%4]),'darkness_scale':[0,.5,1][i%3],'gamma':[0,.4,1][i%3],'night_duration':[None,1,199,200,201,0xffffffff,0xfffffffe][i%7],'water':bits([0,.3,1][i%3]),'conduit':bool(i%2),'flicker':bits((rng.random()-.5)*.05),'flash':None if i%3==0 else[bits(.1),bits(.8)],'hide_flash':i%6==0,'boss_fog':i%2==0,'boss':[bits(.2),bits(.7)]})
 return {'ticks':[{'seed':[0,0],'count':32},{'seed':[0,17],'count':32},{'seed':[0x87654321,0xabcdef01],'count':32}],'prepares':prepares}
def shader_inputs():
 # These are input uniform tests, not authority for live dimension/day/weather.
 scenarios=[]
 def add(name,s,b,n,d,o,g,bt,sc,a,nc):scenarios.append({'name':name,'uniforms':[bits(x)for x in [s,b,n,d,o,g,*bt,*sc,*a,*nc]]})
 add('day',.8,1.4,0,0,0,0,[.9,.78,.58],[.8,.9,1],[.04]*3,[1]*3)
 add('night-gamma',.1,1.38,0,0,0,.75,[.9,.78,.58],[.8,.9,1],[.04]*3,[1]*3)
 add('night-vision',.35,1.42,.85,0,.25,.4,[.9,.78,.58],[.4,.6,1],[.01]*3,[.75,1,.8])
 add('darkness',.7,1.4,0,.24,.7,.2,[.9,.78,.58],[.8,.9,1],[.04]*3,[1]*3)
 add('end-flash',1.2,1.37,0,0,.3,1,[.9,.78,.58],[.675,.376,.804],[.247,.278,.247],[1]*3)
 add('black',0,0,0,0,0,0,[1]*3,[1]*3,[0]*3,[1]*3)
 add('black-gamma',0,0,0,0,0,1,[1]*3,[1]*3,[0]*3,[1]*3)
 add('hdr',2.3,3.2,.3,.03,.2,.65,[1.8,.3,.7],[1.2,2.1,.1],[.01,.07,.02],[.5,2,1.2])
 return scenarios
def main():
 WORK.mkdir(parents=True,exist_ok=True);T.WORK=WORK
 paths,provenance=R.verified_client_classpath();data=inputs();cases=shader_inputs();p=WORK/'ReferenceVanillaLightmap.java';p.write_text(JAVA);incoming=WORK/'input.json';incoming.write_text(json.dumps(data))
 checks=[T.run('java',[R.JAVA,'-Xmx512m','-cp',os.pathsep.join(map(str,paths)),p,incoming,WORK/'observations.json'],timeout=90,max_rss=1024**3)]
 observed=json.loads((WORK/'observations.json').read_text());assert len(observed['ticks'])==3 and len(observed['prepares'])==28
 shader='assets/minecraft/shaders/core/lightmap.fsh';include='assets/minecraft/shaders/include/sample_lightmap.glsl'
 with zipfile.ZipFile(R.CLIENT)as jar:
  source=jar.read(shader);(WORK/'lightmap.fsh').write_bytes(source);sampler=jar.read(include);(WORK/'sample_lightmap.glsl').write_bytes(sampler)
  class_hashes={c:hashlib.sha256(jar.read(c.replace('.','/')+'.class')).hexdigest()for c in ['net.minecraft.client.renderer.Lightmap','net.minecraft.client.renderer.LightmapRenderStateExtractor','net.minecraft.client.renderer.GameRenderer','net.minecraft.client.renderer.EndFlashState','net.minecraft.client.renderer.state.LightmapRenderState','net.minecraft.client.renderer.rendertype.RenderSetup','net.minecraft.util.Mth','net.minecraft.util.LightCoordsUtil']}
 raw=struct.pack('<I',len(cases))
 for row in cases:
  u=list(map(f,row['uniforms']));padded=u[:6]+[0,0]+u[6:9]+[0]+u[9:12]+[0]+u[12:15]+[0]+u[15:18]+[0];raw+=struct.pack('<24f',*padded)
 (WORK/'gl-input.bin').write_bytes(raw)
 checks.append(T.run('gl-build',['clang','-std=c11','-O2','tools/reference_vanilla_lightmap_gl.c','-framework','OpenGL','-o',WORK/'gl-receiver'],timeout=30,max_rss=1024**3))
 checks.append(T.run('gl-shader',[WORK/'gl-receiver',WORK/'lightmap.fsh',WORK/'sample_lightmap.glsl',WORK/'gl-input.bin'],timeout=60,max_rss=1024**3))
 gl=json.loads((WORK/'gl-shader.stdout').read_text());assert len(gl['cases'])==len(cases)
 for r,o in zip(cases,gl.pop('cases')):r['observed']=o
 result={'pin':'26.3','authority':'Actual Java extractor.tick/private calculateDarknessScale/GameRenderer.nightVisionScale/boss interpolation/EndFlashState.getIntensity receivers plus actual installed lightmap shader on offscreen CGL RGBA32F/RGBA8 FBO. Remaining uniform assembly arithmetic is an independent bytecode-derived Java specification, not claimed a full client extractor receiver. No client/window/OS presentation.','provenance':provenance,'source':{'classes':class_hashes,'shader_entry':shader,'shader_sha256':hashlib.sha256(source).hexdigest(),'sample_include_sha256':hashlib.sha256(sampler).hexdigest(),'java_receiver_sha256':T.digest(p),'gl_receiver_sha256':T.digest(ROOT/'tools/reference_vanilla_lightmap_gl.c')},'inputs':data,'java':observed,'shader_backend':gl,'shader_cases':cases,'checks':checks,'boundary':'Offscreen OpenGL on this machine establishes this GL shader/storage boundary only; no claim of full Vulkan or Minecraft backend parity. Actual fully-black float NaNs and UNORM conversion remain documented separately. Test uniform inputs are not live gameplay authority.'}
 (ROOT/'reference/vanilla_lightmap.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'status':'passed','java_flicker_ticks':96,'java_prepare_helpers':28,'actual_shader_pixels':len(cases)*256,'backend':gl}))
if __name__=='__main__':main()
