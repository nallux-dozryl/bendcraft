#!/usr/bin/env python3
"""Actual pinned animation CODEC/CPU constructors/timeline; no GPU service."""
from __future__ import annotations
import argparse,copy,hashlib,json,random,struct,subprocess,zipfile
from reference_model_probe import ROOT,CLIENT,JAVA,verified_client_classpath
OUT=ROOT/'reference/sprite_animation.json';CACHE=ROOT/'reference/cache/sprite-animation'
CLASSES=['net.minecraft.client.renderer.texture.SpriteContents','net.minecraft.client.renderer.texture.SpriteContents$AnimatedTexture','net.minecraft.client.renderer.texture.SpriteContents$AnimationState','net.minecraft.client.renderer.texture.SpriteContents$FrameInfo','net.minecraft.client.resources.metadata.animation.AnimationMetadataSection','net.minecraft.client.resources.metadata.animation.AnimationFrame','net.minecraft.client.resources.metadata.animation.FrameSize','net.minecraft.client.renderer.texture.atlas.SpriteResourceLoader','net.minecraft.server.packs.resources.ResourceMetadata','net.minecraft.server.packs.resources.ResourceMetadata$2','net.minecraft.client.renderer.texture.MipmapGenerator','net.minecraft.client.resources.metadata.texture.TextureMetadataSection','com.mojang.blaze3d.platform.NativeImage']
SHADERS=['assets/minecraft/shaders/core/animate_sprite.vsh','assets/minecraft/shaders/core/animate_sprite_blit.fsh','assets/minecraft/shaders/core/animate_sprite_interpolate.fsh','assets/minecraft/shaders/include/animation_sprite.glsl']
SOURCE=r'''
import com.google.gson.*;
import com.mojang.serialization.*;
import com.mojang.blaze3d.platform.NativeImage;
import com.mojang.renderpearl.api.buffers.GpuBufferSlice;
import it.unimi.dsi.fastutil.ints.Int2ObjectOpenHashMap;
import net.minecraft.client.renderer.texture.SpriteContents;
import net.minecraft.client.resources.metadata.animation.*;
import net.minecraft.client.resources.metadata.texture.TextureMetadataSection;
import net.minecraft.resources.Identifier;
import net.minecraft.server.packs.resources.ResourceMetadata;
import java.lang.reflect.*;
import java.util.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.*;
import java.security.*;
import java.util.zip.*;
class SpriteAnimationProbe {
 static Gson G=new GsonBuilder().serializeNulls().disableHtmlEscaping().create();
 static Object field(Object o,String n)throws Exception{Field f=o.getClass().getDeclaredField(n);f.setAccessible(true);return f.get(o);}
 static String hex(byte[]b){return HexFormat.of().formatHex(b);}
 static String bits(float f){return String.format("%08x",Float.floatToRawIntBits(f));}
 static Throwable cause(Throwable t){while(t.getCause()!=null)t=t.getCause();return t;}
 static JsonObject fail(Throwable t){t=cause(t);JsonObject r=new JsonObject();r.addProperty("status","error");r.addProperty("exception",t.getClass().getName());r.addProperty("message",String.valueOf(t.getMessage()));return r;}
 static JsonElement optional(Optional<?> v){return v.isPresent()?G.toJsonTree(v.get()):JsonNull.INSTANCE;}
 static JsonObject metadata(AnimationMetadataSection m){JsonObject r=new JsonObject();r.add("width",optional(m.frameWidth()));r.add("height",optional(m.frameHeight()));r.addProperty("default_time",m.defaultFrameTime());r.addProperty("interpolate",m.interpolatedFrames());if(m.frames().isPresent()){JsonArray frames=new JsonArray();for(AnimationFrame f:m.frames().get()){JsonObject a=new JsonObject();a.addProperty("index",f.index());a.add("time",optional(f.time()));frames.add(a);}r.add("frames",frames);}else r.add("frames",JsonNull.INSTANCE);return r;}
 static JsonObject decode(JsonObject c){try{Optional<AnimationMetadataSection> m;if(c.get("mode").getAsString().equals("section")){JsonElement j=net.minecraft.util.GsonHelper.fromJson(G,new StringReader(c.get("json").getAsString()),JsonElement.class);DataResult<AnimationMetadataSection> d=AnimationMetadataSection.CODEC.parse(JsonOps.INSTANCE,j);if(d.result().isEmpty()){JsonObject r=new JsonObject();r.addProperty("status","error");r.addProperty("message",d.error().get().message());r.addProperty("partial",d.error().get().partialValue().isPresent());return r;}m=d.result();}else{ResourceMetadata document=ResourceMetadata.fromJsonStream(new ByteArrayInputStream(c.get("json").getAsString().getBytes(StandardCharsets.UTF_8)));m=document.getSection(AnimationMetadataSection.TYPE);}JsonObject r=m.map(SpriteAnimationProbe::metadata).orElse(new JsonObject());r.addProperty("status",m.isPresent()?"ok":"absent");return r;}catch(Throwable t){return fail(t);}}
 static JsonObject image(NativeImage im,boolean pixels)throws Exception{JsonObject r=new JsonObject();r.addProperty("width",im.getWidth());r.addProperty("height",im.getHeight());MessageDigest h=MessageDigest.getInstance("SHA-256");JsonArray a=new JsonArray();for(int y=0;y<im.getHeight();y++)for(int x=0;x<im.getWidth();x++){int p=im.getPixel(x,y);for(int s=24;s>=0;s-=8)h.update((byte)(p>>>s));if(pixels)a.add(Integer.toUnsignedLong(p));}r.addProperty("argb_sha256",hex(h.digest()));if(pixels)r.add("pixels",a);return r;}
 static JsonObject timeline(SpriteContents.AnimationState state,Object info)throws Exception{int entry=(int)field(state,"frame");List<?> frames=(List<?>)field(info,"frames");Object cur=frames.get(entry),next=frames.get((entry+1)%frames.size());JsonObject r=new JsonObject();r.addProperty("entry",entry);r.addProperty("sub_frame",(int)field(state,"subFrame"));r.addProperty("current",(int)field(cur,"index"));r.addProperty("next",(int)field(next,"index"));r.addProperty("duration",(int)field(cur,"time"));r.addProperty("dirty",(boolean)field(state,"isDirty"));r.addProperty("needs_to_draw",state.needsToDraw());return r;}
 static Optional<AnimationMetadataSection> rawMetadata(JsonObject c){if(!c.has("raw_metadata"))return Optional.empty();JsonObject a=c.getAsJsonObject("raw_metadata");Optional<List<AnimationFrame>> frames=Optional.empty();if(a.has("frames")&&!a.get("frames").isJsonNull()){List<AnimationFrame> fs=new ArrayList<>();for(JsonElement j:a.getAsJsonArray("frames")){JsonObject f=j.getAsJsonObject();fs.add(new AnimationFrame(f.get("index").getAsInt(),f.has("time")&&!f.get("time").isJsonNull()?Optional.of(f.get("time").getAsInt()):Optional.empty()));}frames=Optional.of(fs);}return Optional.of(new AnimationMetadataSection(frames,a.has("width")?Optional.of(a.get("width").getAsInt()):Optional.empty(),a.has("height")?Optional.of(a.get("height").getAsInt()):Optional.empty(),a.get("default_time").getAsInt(),a.get("interpolate").getAsBoolean()));}
 static JsonObject cpu(JsonObject c,ZipFile jar)throws Exception{NativeImage image;if(c.has("resource"))image=NativeImage.read(jar.getInputStream(jar.getEntry(c.get("resource").getAsString())));else{image=new NativeImage(c.get("sheet_width").getAsInt(),c.get("sheet_height").getAsInt(),true);JsonArray pixels=c.getAsJsonArray("pixels");for(int y=0;y<image.getHeight();y++)for(int x=0;x<image.getWidth();x++)image.setPixel(x,y,(int)pixels.get(x+y*image.getWidth()).getAsLong());}SpriteContents contents=null;JsonObject r=new JsonObject();r.add("original",image(image,true));try{Optional<AnimationMetadataSection> animation;Optional<TextureMetadataSection> texture;if(c.has("raw_metadata")){animation=rawMetadata(c);texture=Optional.empty();}else{ResourceMetadata doc=ResourceMetadata.fromJsonStream(new ByteArrayInputStream(c.get("json").getAsString().getBytes(StandardCharsets.UTF_8)));animation=doc.getSection(AnimationMetadataSection.TYPE);texture=doc.getSection(TextureMetadataSection.TYPE);}r.add("animation_metadata",animation.<JsonElement>map(SpriteAnimationProbe::metadata).orElse(JsonNull.INSTANCE));FrameSize size=animation.map(m->m.calculateFrameSize(image.getWidth(),image.getHeight())).orElse(new FrameSize(image.getWidth(),image.getHeight()));if(c.has("raw_frame_size")){JsonArray f=c.getAsJsonArray("raw_frame_size");size=new FrameSize(f.get(0).getAsInt(),f.get(1).getAsInt());}r.addProperty("frame_width",size.width());r.addProperty("frame_height",size.height());r.addProperty("loader_multiple",size.width()!=0&&size.height()!=0&&image.getWidth()%size.width()==0&&image.getHeight()%size.height()==0);contents=new SpriteContents(Identifier.fromNamespaceAndPath("probe",c.has("path")?c.get("path").getAsString():"animation"),size,image,animation,List.of(),texture);r.addProperty("is_animated",contents.isAnimated());r.add("unique_frames",G.toJsonTree(contents.getUniqueFrames().toIntArray()));r.addProperty("sprite_strategy",((net.minecraft.client.renderer.texture.MipmapStrategy)field(contents,"mipmapStrategy")).getSerializedName());r.addProperty("sprite_bias_f32",bits((float)field(contents,"alphaCutoffBias")));contents.increaseMipLevel(c.get("mip_level").getAsInt());NativeImage[] levels=(NativeImage[])field(contents,"byMipLevel");JsonArray mips=new JsonArray();for(NativeImage im:levels)mips.add(image(im,false));r.add("mip_chain",mips);Object info=field(contents,"animatedTexture");if(info!=null){int rows=(int)field(info,"frameRowSize");r.addProperty("row_size",rows);r.addProperty("interpolate",(boolean)field(info,"interpolateFrames"));JsonArray frames=new JsonArray();for(Object frame:(List<?>)field(info,"frames")){JsonObject f=new JsonObject();f.addProperty("index",(int)field(frame,"index"));f.addProperty("time",(int)field(frame,"time"));frames.add(f);}r.add("frames",frames);Constructor<?> ctor=SpriteContents.AnimationState.class.getDeclaredConstructors()[0];ctor.setAccessible(true);r.addProperty("state_constructor",ctor.toGenericString());try(SpriteContents.AnimationState state=(SpriteContents.AnimationState)ctor.newInstance(contents,info,new Int2ObjectOpenHashMap<>(),new GpuBufferSlice[0])){JsonArray states=new JsonArray();states.add(timeline(state,info));for(int i=0;i<c.get("ticks").getAsInt();i++){state.tick();states.add(timeline(state,info));}r.add("timeline",states);}Method fx=info.getClass().getDeclaredMethod("getFrameX",int.class),fy=info.getClass().getDeclaredMethod("getFrameY",int.class);fx.setAccessible(true);fy.setAccessible(true);JsonArray crops=new JsonArray();for(int index:contents.getUniqueFrames().toIntArray())for(int mip=0;mip<levels.length;mip++){int x=((int)fx.invoke(info,index)*size.width())>>mip,y=((int)fy.invoke(info,index)*size.height())>>mip,w=size.width()>>mip,h=size.height()>>mip;JsonObject crop=new JsonObject();crop.addProperty("index",index);crop.addProperty("mip",mip);crop.addProperty("x",x);crop.addProperty("y",y);crop.addProperty("width",w);crop.addProperty("height",h);try(NativeImage out=new NativeImage(w,h,true)){levels[mip].copyRect(out,x,y,0,0,w,h,false,false);crop.add("image",image(out,false));crop.addProperty("status","ok");}catch(Throwable t){crop.add("error",fail(t));crop.addProperty("status","error");}crops.add(crop);}r.add("crops",crops);}r.addProperty("status","ok");return r;}catch(Throwable t){r.add("error",fail(t));r.addProperty("status","error");return r;}finally{if(contents!=null)contents.close();else image.close();}}
 public static void main(String[]args)throws Exception{JsonObject in=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonObject(),out=new JsonObject();JsonArray rows=new JsonArray();for(JsonElement j:in.getAsJsonArray("decode_cases")){JsonObject c=j.getAsJsonObject(),r=new JsonObject();r.addProperty("id",c.get("id").getAsString());r.add("result",decode(c));rows.add(r);}out.add("decode_cases",rows);rows=new JsonArray();try(ZipFile jar=new ZipFile(args[2])){for(JsonElement j:in.getAsJsonArray("cpu_cases")){JsonObject c=j.getAsJsonObject(),r=new JsonObject();r.addProperty("id",c.get("id").getAsString());r.add("result",cpu(c,jar));rows.add(r);}}out.add("cpu_cases",rows);Files.writeString(Path.of(args[1]),G.toJson(out));}
}
'''
def sha(b):return hashlib.sha256(b).hexdigest()
def canonical(v):return json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=True).encode()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')
def inputs():
    decode=[];cpu=[];resources=[]
    def add(name,value=None,mode='section',raw=None):decode.append({'id':name,'mode':mode,'json':raw if raw is not None else json.dumps(value,separators=(',',':'))})
    add('defaults',{});add('unknown',{'other':[1,2]})
    for field in ['frames','width','height','frametime','interpolate']:
        for value in [None,True,False,0,1,-1,1.9,-1.9,'1',[],{},[0],[-1],[{'index':1}],[{'index':1,'time':2}]]:add(field+'_'+str(len(decode)),{field:value})
    for frame in [0,1,-1,1.9,2147483647,2147483648,4294967297,None,True,'0',{}, {'index':0,'time':None},{'index':0,'time':0},{'index':-1,'time':1},{'index':0,'time':1.9}]:add('frame_'+str(len(decode)),{'frames':[frame]})
    for token in ['1e30','1e-30','4294967296','4294967297','-4294967295','2147483648','-2147483649','1.9999999999999999999','1e999999999','NaN','Infinity','1.0f']:
        for field in ['width','frametime']:add('numeric_'+field+'_'+str(len(decode)),raw='{"'+field+'":'+token+'}')
    for raw in ['null','[]','true','0','"x"','{"frames":[0],"frames":[1,2]}','{"frametime":2} false','\ufeff{"frametime":2}','{bad}','{"frametime":1,}']:add('raw_'+str(len(decode)),raw=raw)
    for value in [{},{'animation':None},{'animation':[]},{'animation':{}},{'animation':{'frames':[]}}]:add('document_'+str(len(decode)),value,'document')
    rng=random.Random(2632026)
    def synthetic(name,w,h,animation=None,mip=0,ticks=32,extra=None):
        pixels=[((rng.choice([0,64,127,255])<<24)|rng.randrange(1<<24))for _ in range(w*h)];c={'id':name,'sheet_width':w,'sheet_height':h,'pixels':pixels,'json':json.dumps({}if animation is None else{'animation':animation},separators=(',',':')),'mip_level':mip,'ticks':ticks}
        if extra:c.update(extra)
        cpu.append(c)
    synthetic('absent',4,8);synthetic('default_grid',4,8,{});synthetic('two_dimensional_grid',8,12,{'width':4,'height':4},mip=2);synthetic('repeat',4,6,{'width':2,'height':2,'frames':[2,2,0],'frametime':2});synthetic('repeat_interpolate',4,6,{'width':2,'height':2,'frames':[2,2,0],'frametime':3,'interpolate':True});synthetic('single_index2',4,6,{'width':2,'height':2,'frames':[2]});synthetic('empty_frames',4,6,{'width':2,'height':2,'frames':[]});synthetic('invalid_index',4,6,{'width':2,'height':2,'frames':[99,2,0]});synthetic('width_only',4,12,{'width':2});synthetic('height_only',12,4,{'height':2});synthetic('nondivisible',5,7,{'width':2,'height':3});synthetic('odd_mip',6,12,{'width':3,'height':3},mip=1);synthetic('zero_frame_mip',4,8,{'width':1,'height':1},mip=1)
    for frames in [[{'index':0,'time':0},1,2],[{'index':-1,'time':1},1,2],[{'index':0,'time':-1},{'index':1,'time':2},{'index':2,'time':1}],[{'index':0,'time':1},{'index':0,'time':1}]]:
        raw=[f if isinstance(f,dict)else{'index':f}for f in frames];synthetic('raw_filtered_'+str(len(cpu)),4,6,extra={'raw_metadata':{'width':2,'height':2,'frames':raw,'default_time':1,'interpolate':False}})
    for t in [0,-1,2147483647]:synthetic('raw_default_'+str(t),4,6,extra={'raw_metadata':{'width':2,'height':2,'default_time':t,'interpolate':False}})
    for dims in [[0,1],[-1,1],[8,8]]:synthetic('raw_size_'+str(len(cpu)),4,6,{},extra={'raw_frame_size':dims})
    for i in range(32):
        fw=rng.randrange(1,6);fh=rng.randrange(1,6);cols=rng.randrange(1,5);rows=rng.randrange(2,5);frames=[{'index':rng.randrange(cols*rows),'time':rng.randrange(1,8)}for _ in range(rng.randrange(2,12))];synthetic('random_'+str(i),fw*cols,fh*rows,{'width':fw,'height':fh,'frames':frames,'interpolate':bool(rng.randrange(2))},ticks=64)
    with zipfile.ZipFile(CLIENT)as z:
        for name in sorted(n for n in z.namelist()if n.endswith('.png.mcmeta')):
            b=z.read(name);add('resource:'+name,mode='document',raw=b.decode());v=json.loads(b)
            if 'animation'not in v:continue
            png=name[:-7];pb=z.read(png);w,h=struct.unpack('>II',pb[16:24]);resources.append({'metadata_path':name,'metadata_sha256':sha(b),'resource':png,'resource_sha256':sha(pb),'width':w,'height':h});cpu.append({'id':'actual:'+png,'resource':png,'json':b.decode(),'mip_level':2 if min(w,h)>=4 else 0,'ticks':64,'path':png.split('/textures/',1)[1][:-4]})
    return {'decode_cases':decode,'cpu_cases':cpu,'resources':resources}
def execute(data,tag):
    cp,provenance=verified_client_classpath();CACHE.mkdir(parents=True,exist_ok=True);src=CACHE/'SpriteAnimationProbe.java';src.write_text(SOURCE);inp=CACHE/(tag+'-inputs.json');out=CACHE/(tag+'-output.json');write(inp,data);command=[str(JAVA),'-Djava.awt.headless=true','--enable-native-access=ALL-UNNAMED','-cp',':'.join(map(str,cp)),str(src),str(inp),str(out),str(CLIENT)];p=subprocess.run(command,capture_output=True,text=True,timeout=120);(CACHE/(tag+'-stderr.txt')).write_text(p.stderr)
    if p.returncode:raise RuntimeError(p.stderr[-6000:])
    bytecode=subprocess.run([str(JAVA.with_name('javap')),'-cp',':'.join(map(str,cp)),'-c','-p',*CLASSES],capture_output=True,check=True).stdout;(CACHE/'probe-bytecode.txt').write_bytes(bytecode)
    with zipfile.ZipFile(CLIENT)as z:classes={c:sha(z.read(c.replace('.','/')+'.class'))for c in CLASSES};shaders={s:sha(z.read(s))for s in SHADERS}
    return {'schema':1,'pin':'26.3','inputs':data,'observations':json.loads(out.read_text()),'provenance':{'classpath':provenance,'classes_sha256':classes,'shader_resource_sha256':shaders,'harness_sha256':sha(SOURCE.encode()),'bytecode_sha256':sha(bytecode)},'boundary':'Untouched animation CODEC/ResourceMetadata, normal NativeImage/SpriteContents, actual increaseMipLevel and NativeImage.copyRect. Private actual AnimationState constructor receives real empty GPU-owner collections exclusively for tick/needsToDraw; these CPU methods never read omitted GPU owners. Reflective reads only, no writes/Unsafe/mock GPU objects/device/client/window. Public createAnimationState/drawToAtlas/upload and shader interpolation unexecuted. Static getUniqueFrames[1] remains raw sentinel and is not cropped.'}
def seal(v):v['observation_sha256']=sha(canonical(v['observations']));return v
def validate(v,fresh=None):
    if v['schema']!=1 or v['pin']!='26.3':raise ValueError('Pin/schema mismatch')
    if v['inputs']!=inputs():raise ValueError('Input mismatch')
    if v.get('observation_sha256')!=sha(canonical(v['observations'])):raise ValueError('Observation digest mismatch')
    if v['provenance']['harness_sha256']!=sha(SOURCE.encode()):raise ValueError('Harness mismatch')
    _,current_classpath=verified_client_classpath()
    if v['provenance']['classpath']!=current_classpath:raise ValueError('Classpath provenance mismatch')
    with zipfile.ZipFile(CLIENT)as jar:
        if v['provenance']['classes_sha256']!={c:sha(jar.read(c.replace('.','/')+'.class'))for c in CLASSES}:raise ValueError('Class provenance mismatch')
        if v['provenance']['shader_resource_sha256']!={s:sha(jar.read(s))for s in SHADERS}:raise ValueError('Shader provenance mismatch')
    if fresh is not None and(v['observations']!=fresh['observations']or v['provenance']!=fresh['provenance']):raise ValueError('Fresh official receiver/provenance mismatch')
    for key in ['decode_cases','cpu_cases']:
        if [c['id']for c in v['observations'][key]]!=[c['id']for c in v['inputs'][key]]:raise ValueError('Case order mismatch')
    rows=v['observations']['cpu_cases'];return {'decode_cases':len(v['inputs']['decode_cases']),'cpu_cases':len(rows),'actual_animated_pngs':len(v['inputs']['resources']),'cpu_successes':sum(c['result']['status']=='ok'for c in rows),'cpu_errors':sum(c['result']['status']=='error'for c in rows),'timeline_samples':sum(len(c['result'].get('timeline',[]))for c in rows),'crop_receivers':sum(len(c['result'].get('crops',[]))for c in rows)}
def main():
    ap=argparse.ArgumentParser();ap.add_argument('mode',choices=['extract','validate','selftest']);a=ap.parse_args()
    if a.mode=='extract':v=seal(execute(inputs(),'extract'));summary=validate(v);write(OUT,v)
    else:
        v=json.loads(OUT.read_text());fresh=seal(execute(inputs(),a.mode+'-fresh'));summary=validate(v,fresh)
        if a.mode=='selftest':
            validate(v,seal(execute(inputs(),'selftest-second')));checks=[]
            def fault(name,fn,reseal=False):
                bad=copy.deepcopy(v);fn(bad)
                if reseal:seal(bad)
                try:validate(bad,fresh)
                except ValueError:checks.append(name);return
                raise AssertionError('Accepted corruption:'+name)
            cpu=next(i for i,c in enumerate(v['observations']['cpu_cases'])if 'timeline'in c['result']);crop=next(i for i,c in enumerate(v['observations']['cpu_cases'])if c['result'].get('crops'))
            fault('timeline_unsealed',lambda b:b['observations']['cpu_cases'][cpu]['result']['timeline'][1].__setitem__('sub_frame',99));fault('timeline_resealed',lambda b:b['observations']['cpu_cases'][cpu]['result']['timeline'][1].__setitem__('sub_frame',99),True);fault('crop_resealed',lambda b:b['observations']['cpu_cases'][crop]['result']['crops'][0]['image'].__setitem__('argb_sha256','0'*64),True);fault('static_sentinel',lambda b:b['observations']['cpu_cases'][0]['result'].__setitem__('unique_frames',[0]),True);fault('metadata_coercion',lambda b:b['observations']['decode_cases'][0]['result'].__setitem__('default_time',2),True);fault('class_hash',lambda b:b['provenance']['classes_sha256'].__setitem__(CLASSES[0],'0'*64));fault('resource_hash',lambda b:b['inputs']['resources'][0].__setitem__('resource_sha256','0'*64));fault('shader_hash',lambda b:b['provenance']['shader_resource_sha256'].__setitem__(SHADERS[0],'0'*64));summary.update(fresh_java_runs=2,corruptions_rejected=checks)
    write(ROOT/('evidence/sprite-animation-reference'+(''if a.mode=='extract'else'-'+a.mode)+'.json'),{'status':'passed','summary':summary,'reference_sha256':sha(OUT.read_bytes()),'observation_sha256':v['observation_sha256'],'command':'python3 tools/reference_sprite_animation_probe.py '+a.mode});print(summary)
if __name__=='__main__':main()
