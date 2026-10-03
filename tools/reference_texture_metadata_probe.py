#!/usr/bin/env python3
"""Pinned 26.3 texture CODEC/ResourceMetadata execution, without a window."""
from __future__ import annotations
import argparse, copy, hashlib, json, pathlib, subprocess, zipfile
from reference_model_probe import ROOT, CLIENT, JAVA, verified_client_classpath

OUT=ROOT/'reference/texture_metadata.json'
CACHE=ROOT/'reference/cache/texture-metadata'
CLASSES=['net.minecraft.client.resources.metadata.texture.TextureMetadataSection','net.minecraft.client.renderer.texture.MipmapStrategy','net.minecraft.server.packs.resources.ResourceMetadata','net.minecraft.server.packs.resources.ResourceMetadata$2','net.minecraft.client.renderer.texture.TextureContents','net.minecraft.client.renderer.texture.SpriteContents','net.minecraft.client.renderer.texture.MipmapGenerator','net.minecraft.client.renderer.texture.MipmappedTexture','net.minecraft.client.renderer.texture.ReloadableTexture','net.minecraft.client.renderer.texture.TextureAtlas','net.minecraft.client.renderer.texture.atlas.SpriteResourceLoader','com.mojang.blaze3d.systems.SamplerCache','net.minecraft.util.GsonHelper']
SOURCE=r'''
import com.google.gson.*;
import com.mojang.serialization.*;
import com.mojang.blaze3d.platform.NativeImage;
import net.minecraft.client.resources.metadata.texture.TextureMetadataSection;
import net.minecraft.client.resources.metadata.animation.FrameSize;
import net.minecraft.client.renderer.texture.*;
import net.minecraft.resources.Identifier;
import net.minecraft.server.packs.resources.ResourceMetadata;
import java.util.*;
import java.io.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.lang.reflect.*;
class TextureMetadataProbe {
 static Gson G=new GsonBuilder().serializeNulls().disableHtmlEscaping().create();
 static String bits(float f){return String.format("%08x",Float.floatToRawIntBits(f));}
 static JsonObject meta(TextureMetadataSection m){
  JsonObject o=new JsonObject();o.addProperty("blur",m.blur());o.addProperty("clamp",m.clamp());
  o.addProperty("strategy",m.mipmapStrategy().getSerializedName());o.addProperty("alpha_cutoff_bias_f32",bits(m.alphaCutoffBias()));return o;
 }
 static Throwable cause(Throwable e){while(e.getCause()!=null)e=e.getCause();return e;}
 static JsonObject fail(Throwable e){e=cause(e);JsonObject o=new JsonObject();o.addProperty("status","error");o.addProperty("exception",e.getClass().getName());o.addProperty("message",String.valueOf(e.getMessage()));return o;}
 static JsonObject section(String raw){
  try{JsonElement j=net.minecraft.util.GsonHelper.fromJson(G,new StringReader(raw),JsonElement.class);DataResult<TextureMetadataSection> r=TextureMetadataSection.CODEC.parse(JsonOps.INSTANCE,j);
   if(r.result().isPresent()){JsonObject o=meta(r.result().get());o.addProperty("status","ok");return o;}
   JsonObject o=new JsonObject();o.addProperty("status","error");o.addProperty("message",r.error().get().message());o.addProperty("partial",r.error().get().partialValue().isPresent());return o;
  }catch(Throwable e){return fail(e);}
 }
 static JsonObject document(String raw){
  try{ResourceMetadata r=ResourceMetadata.fromJsonStream(new ByteArrayInputStream(raw.getBytes(StandardCharsets.UTF_8)));
   Optional<TextureMetadataSection> m=r.getSection(TextureMetadataSection.TYPE);
   JsonObject o=m.isPresent()?meta(m.get()):new JsonObject();o.addProperty("status",m.isPresent()?"ok":"absent");return o;
  }catch(Throwable e){return fail(e);}
 }
 static JsonObject consumer(TextureMetadataSection m)throws Exception {
  JsonObject o=new JsonObject();TextureContents t=new TextureContents(null,m);o.addProperty("standalone_blur",t.blur());o.addProperty("standalone_clamp",t.clamp());
  NativeImage image=new NativeImage(2,2,false);for(int y=0;y<2;y++)for(int x=0;x<2;x++)image.setPixel(x,y,0xffffffff);SpriteContents s=null;
  try{s=new SpriteContents(Identifier.fromNamespaceAndPath("probe","texture"),new FrameSize(2,2),image,Optional.empty(),List.of(),Optional.ofNullable(m));
   Field strategy=SpriteContents.class.getDeclaredField("mipmapStrategy");strategy.setAccessible(true);
   Field bias=SpriteContents.class.getDeclaredField("alphaCutoffBias");bias.setAccessible(true);
   o.addProperty("sprite_strategy",((MipmapStrategy)strategy.get(s)).getSerializedName());o.addProperty("sprite_alpha_cutoff_bias_f32",bits(bias.getFloat(s)));
  }finally{if(s!=null)s.close();else image.close();}return o;
 }
 public static void main(String[] args)throws Exception {
  JsonObject in=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonObject();JsonObject out=new JsonObject();JsonArray rows=new JsonArray();
  for(JsonElement e:in.getAsJsonArray("cases")){JsonObject c=e.getAsJsonObject();JsonObject r=new JsonObject();r.addProperty("id",c.get("id").getAsString());String raw=c.get("json").getAsString();
   r.add("result",c.get("mode").getAsString().equals("section")?section(raw):document(raw));rows.add(r);}
  out.add("cases",rows);JsonArray consumers=new JsonArray();
  for(JsonElement e:in.getAsJsonArray("consumer_cases")){JsonObject c=e.getAsJsonObject();TextureMetadataSection m=c.get("json").isJsonNull()?null:TextureMetadataSection.CODEC.parse(JsonOps.INSTANCE,JsonParser.parseString(c.get("json").getAsString())).getOrThrow();
   JsonObject r=new JsonObject();r.addProperty("id",c.get("id").getAsString());r.add("result",consumer(m));consumers.add(r);}
  out.add("consumer_cases",consumers);Files.writeString(Path.of(args[1]),G.toJson(out));
 }
}
'''
def sha(b):return hashlib.sha256(b).hexdigest()
def canonical(x):return json.dumps(x,sort_keys=True,separators=(',',':'),ensure_ascii=True).encode()
def write(path,data):path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(data,sort_keys=True,indent=2)+'\n')
def inputs():
    cases=[];resources=[]
    def case(name,j=None,mode='section',raw=None):cases.append({'id':name,'mode':mode,'json':raw if raw is not None else json.dumps(j,separators=(',',':'))})
    case('defaults',{});case('multiple_invalid',{'blur':'true','clamp':1,'mipmap_strategy':'bad','alpha_cutoff_bias':[]});case('all_fields',{'blur':True,'clamp':True,'mipmap_strategy':'mean','alpha_cutoff_bias':.1});case('unknown_fields',{'unexpected':{'nested':[1,2]},'blur':False})
    for field in ['blur','clamp','mipmap_strategy','alpha_cutoff_bias']:
        for v in [None,True,False,0,1,-1,.5,'true','false','0.1','NaN','Infinity',[],{},['auto']]:case(field+'_'+str(len(cases)),{field:v})
    for v in ['auto','mean','cutout','strict_cutout','dark_cutout','AUTO','Mean','strict-cutout','', 'unknown']:case('strategy_'+v,{'mipmap_strategy':v})
    for raw in ['0','-0.0','0.1','1e-45','7.006492321624085e-46','-1e-100','1e40','-1e40','1e999999999','1.000000059604644775390625','1.0000000596046449','3.4028234663852886e38','3.4028235677973366e38','NaN','Infinity','-Infinity','1.0f','0x1.0p0']:
        case('float_'+raw,raw='{"alpha_cutoff_bias":'+raw+'}')
    for size in [1022,1023,1024,1025]:case('json_numeric_token_'+str(size),raw='{"alpha_cutoff_bias":'+('1'*size)+'}')
    for raw in ['null','[]','true','0','"x"','{"blur":true,"blur":false}','{"blur":true} false','{bad}','{"blur":true,}']:
        case('section_raw_'+str(len(cases)),raw=raw)
    for j in [{},{'animation':{'frametime':2}},{'texture':{}},{'texture':None},{'texture':[]},{'texture':True},{'texture':'auto'},{'texture':{'blur':True}},{'texture':{'blur':'true'}},{'unknown':1}]:case('document_'+str(len(cases)),j,'document')
    for raw in ['null','[]','true','0','"x"','{"texture":{}} false','{"texture":{"blur":true},"texture":{"blur":false}}','\ufeff{"texture":{}}','{"texture":{}} {bad}','{bad}','{"texture":{"alpha_cutoff_bias":1e40}}']:
        case('document_raw_'+str(len(cases)),mode='document',raw=raw)
    with zipfile.ZipFile(CLIENT)as z:
        for name in sorted(n for n in z.namelist()if n.endswith('.png.mcmeta')):
            b=z.read(name);resources.append({'path':name,'sha256':sha(b),'bytes':len(b)});case('resource:'+name,mode='document',raw=b.decode('utf8'))
    consumers=[{'id':'absent','json':None},{'id':'defaults','json':'{}'},{'id':'blur_clamp','json':'{"blur":true,"clamp":true}'},{'id':'glass_mean','json':'{"mipmap_strategy":"mean"}'},{'id':'bias_negative_zero','json':'{"alpha_cutoff_bias":-0.0}'},{'id':'bias_overflow','json':'{"alpha_cutoff_bias":1e40}'}]
    return {'cases':cases,'consumer_cases':consumers,'resources':resources}
def execute(data,tag):
    cp,provenance=verified_client_classpath();CACHE.mkdir(parents=True,exist_ok=True)
    src=CACHE/'TextureMetadataProbe.java';src.write_text(SOURCE);inp=CACHE/(tag+'-inputs.json');out=CACHE/(tag+'-output.json');write(inp,data)
    cmd=[str(JAVA),'-Djava.awt.headless=true','--enable-native-access=ALL-UNNAMED','-cp',':'.join(map(str,cp)),str(src),str(inp),str(out)]
    r=subprocess.run(cmd,capture_output=True,text=True,timeout=90)
    (CACHE/(tag+'-stderr.txt')).write_text(r.stderr)
    if r.returncode:raise RuntimeError(r.stderr)
    if not out.is_file():raise RuntimeError('Official probe produced no output')
    bytecode=subprocess.run([str(JAVA.with_name('javap')),'-classpath',':'.join(map(str,cp)),'-c','-p',*CLASSES],capture_output=True,check=True).stdout
    (CACHE/'consumer-bytecode.txt').write_bytes(bytecode)
    sampler_api=subprocess.run([str(JAVA.with_name('javap')),'-classpath',':'.join(map(str,cp)),'-p','-v','com.mojang.renderpearl.api.device.GpuDevice'],capture_output=True,check=True).stdout
    (CACHE/'gpu-device-api.txt').write_bytes(sampler_api)
    api_class=None
    for archive in cp:
        with zipfile.ZipFile(archive)as z:
            name='com/mojang/renderpearl/api/device/GpuDevice.class'
            if name in z.namelist():api_class={'library':archive.name,'class_sha256':sha(z.read(name))};break
    if api_class is None:raise ValueError('Verified sampler API class missing')
    with zipfile.ZipFile(CLIENT)as z:classes={name:sha(z.read(name.replace('.','/')+'.class'))for name in CLASSES}
    return {'schema':1,'pin':'26.3','inputs':data,'observations':json.loads(out.read_text()),'provenance':{'classpath':provenance,'official_classes_sha256':classes,'harness_sha256':sha(SOURCE.encode()),'consumer_bytecode_sha256':sha(bytecode),'sampler_api':api_class,'sampler_api_bytecode_sha256':sha(sampler_api)},'boundary':'Official CODEC and ResourceMetadata receiver; actual CPU TextureContents/SpriteContents construction. No GPU sampler, mipmap pixel generation, atlas stitch or frame execution.'}
def validate(value,fresh=None):
    expected=inputs()
    if value['pin']!='26.3'or value['schema']!=1:raise ValueError('Version/schema mismatch')
    if value['inputs']!=expected:raise ValueError('Official inputs differ')
    if value['provenance']['harness_sha256']!=sha(SOURCE.encode()):raise ValueError('Harness differs')
    if value.get('observation_sha256')!=sha(canonical(value['observations'])):raise ValueError('Observation digest mismatch')
    if fresh is not None and value['observations']!=fresh['observations']:raise ValueError('Fresh official execution differs')
    if fresh is not None and value['provenance']!=fresh['provenance']:raise ValueError('Fresh provenance differs')
    rows=value['observations']['cases']
    if [c['id']for c in rows]!=[c['id']for c in expected['cases']]:raise ValueError('Case order differs')
    return {'cases':len(rows),'official_png_metadata_files':len(expected['resources']),'consumer_cases':len(value['observations']['consumer_cases']),'status_counts':{s:sum(c['result']['status']==s for c in rows)for s in ['ok','absent','error']}}
def sealed(value):value['observation_sha256']=sha(canonical(value['observations']));return value
def main():
    ap=argparse.ArgumentParser();ap.add_argument('mode',choices=['extract','validate','selftest']);args=ap.parse_args()
    if args.mode=='extract':
        v=sealed(execute(inputs(),'extract'));summary=validate(v);write(OUT,v);write(ROOT/'evidence/texture-metadata-reference.json',{'status':'passed','summary':summary,'reference_sha256':sha(OUT.read_bytes()),'observation_sha256':v['observation_sha256'],'command':'python3 tools/reference_texture_metadata_probe.py extract'});print(summary)
    else:
        v=json.loads(OUT.read_text());fresh=sealed(execute(inputs(),args.mode+'-fresh'));summary=validate(v,fresh)
        if args.mode=='selftest':
            second=sealed(execute(inputs(),'selftest-second'));validate(v,second);checks=[]
            def fault(name,mutate,reseal=False):
                bad=copy.deepcopy(v);mutate(bad)
                if reseal:sealed(bad)
                try:validate(bad,fresh)
                except ValueError:checks.append(name);return
                raise AssertionError('Corruption accepted: '+name)
            fault('unsealed_bits',lambda b:b['observations']['cases'][0]['result'].__setitem__('alpha_cutoff_bias_f32','80000000'))
            fault('resealed_bits',lambda b:b['observations']['cases'][0]['result'].__setitem__('alpha_cutoff_bias_f32','80000000'),True)
            fault('resealed_absence',lambda b:b['observations']['cases'][0]['result'].__setitem__('status','absent'),True)
            fault('input_resource',lambda b:b['inputs']['resources'][0].__setitem__('sha256','0'*64))
            fault('consumer',lambda b:b['observations']['consumer_cases'][0]['result'].__setitem__('sprite_strategy','mean'),True)
            fault('class_provenance',lambda b:b['provenance']['official_classes_sha256'].__setitem__(CLASSES[0],'0'*64))
            summary.update(fresh_java_runs=2,corruptions_rejected=checks)
        write(ROOT/('evidence/texture-metadata-reference-'+args.mode+'.json'),{'status':'passed','summary':summary,'reference_sha256':sha(OUT.read_bytes()),'command':'python3 tools/reference_texture_metadata_probe.py '+args.mode});print(summary)
if __name__=='__main__':main()
