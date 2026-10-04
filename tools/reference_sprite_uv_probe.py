#!/usr/bin/env python3
"""Pinned actual TextureAtlasSprite constructor/UV methods; no client/window."""
from __future__ import annotations
import argparse,copy,hashlib,json,random,struct,subprocess,zipfile
from reference_model_probe import ROOT,CLIENT,JAVA,verified_client_classpath

OUT=ROOT/'reference/sprite_uv.json';CACHE=ROOT/'reference/cache/sprite-uv'
CLASSES=['net.minecraft.client.renderer.texture.TextureAtlasSprite','net.minecraft.client.renderer.texture.UvMapping','net.minecraft.client.renderer.texture.SpriteContents','net.minecraft.client.resources.metadata.animation.FrameSize','net.minecraft.client.resources.model.cuboid.FaceBakery','net.minecraft.client.resources.model.cuboid.CuboidFace','net.minecraft.client.resources.model.cuboid.CuboidFace$UVs','com.mojang.math.Quadrant','net.minecraft.client.renderer.texture.SpriteLoader','net.minecraft.client.renderer.texture.Stitcher','net.minecraft.client.renderer.texture.Stitcher$Holder','net.minecraft.client.renderer.texture.Stitcher$Region']
SOURCE=r'''
import com.google.gson.*;
import com.mojang.blaze3d.platform.NativeImage;
import net.minecraft.client.resources.metadata.animation.FrameSize;
import net.minecraft.client.renderer.texture.*;
import net.minecraft.resources.Identifier;
import net.minecraft.client.resources.model.cuboid.CuboidFace;
import com.mojang.math.Quadrant;
import java.lang.reflect.*;
import java.nio.file.*;
import java.util.*;
import java.util.zip.*;
class SpriteUvProbe {
 static Gson G=new GsonBuilder().serializeNulls().disableHtmlEscaping().create();
 static Constructor<TextureAtlasSprite> CTOR;
 record E(int tag,int width,int height,Identifier name)implements Stitcher.Entry{}
 static String bits(float f){return String.format("%08x",Float.floatToRawIntBits(f));}
 static float f(JsonElement j){return Float.intBitsToFloat((int)Long.parseUnsignedLong(j.getAsString(),16));}
 static int n(JsonObject c,String k){return c.get(k).getAsInt();}
 static JsonArray methods(Class<?> c){JsonArray a=new JsonArray();Arrays.stream(c.getDeclaredMethods()).map(Method::toGenericString).sorted().forEach(a::add);return a;}
 static JsonObject measure(SpriteContents contents,int aw,int ah,int x,int y,int p,JsonArray queries)throws Exception{
  TextureAtlasSprite s=CTOR.newInstance(Identifier.fromNamespaceAndPath("probe","atlas"),contents,aw,ah,x,y,p);JsonObject r=new JsonObject();
  r.addProperty("x",s.getX());r.addProperty("y",s.getY());r.addProperty("width",s.contents().width());r.addProperty("height",s.contents().height());r.addProperty("atlas",s.atlasLocation().toString());
  Field padding=TextureAtlasSprite.class.getDeclaredField("padding");padding.setAccessible(true);r.addProperty("padding",padding.getInt(s));
  r.addProperty("u0",bits(s.getU0()));r.addProperty("v0",bits(s.getV0()));r.addProperty("u1",bits(s.getU1()));r.addProperty("v1",bits(s.getV1()));JsonArray values=new JsonArray();
  for(JsonElement q:queries){JsonObject a=new JsonObject();a.addProperty("query",q.getAsString());a.addProperty("u",bits(s.getU(f(q))));a.addProperty("v",bits(s.getV(f(q))));values.add(a);}r.add("queries",values);
  values=new JsonArray();CuboidFace.UVs rect=new CuboidFace.UVs(0,0,16,16);for(int i=0;i<4;i++){JsonObject a=new JsonObject();float u=CuboidFace.getU(rect,Quadrant.R0,i),v=CuboidFace.getV(rect,Quadrant.R0,i);a.addProperty("normalized_u",bits(u));a.addProperty("normalized_v",bits(v));a.addProperty("u",bits(s.getU(u)));a.addProperty("v",bits(s.getV(v)));values.add(a);}r.add("mapped_corners",values);return r;
 }
 static JsonObject direct(JsonObject c,ZipFile jar)throws Exception{
  NativeImage image=c.has("resource")?NativeImage.read(jar.getInputStream(jar.getEntry(c.get("resource").getAsString()))):new NativeImage(1,1,false);
  if(!c.has("resource"))image.setPixel(0,0,0xffffffff);
  try(SpriteContents contents=new SpriteContents(Identifier.fromNamespaceAndPath("probe","entry"),new FrameSize(n(c,"width"),n(c,"height")),image)){
   return measure(contents,n(c,"atlas_width"),n(c,"atlas_height"),n(c,"x"),n(c,"y"),n(c,"padding"),c.getAsJsonArray("queries"));
  }
 }
 static JsonObject stitch(JsonObject c)throws Exception{
  Stitcher<E> st=new Stitcher<>(n(c,"max_width"),n(c,"max_height"),n(c,"mip_level"),n(c,"padding_setting"));
  for(JsonElement j:c.getAsJsonArray("entries")){JsonObject e=j.getAsJsonObject();st.registerSprite(new E(n(e,"tag"),n(e,"width"),n(e,"height"),Identifier.fromNamespaceAndPath("probe","entry/"+n(e,"tag"))));}st.stitch();JsonArray a=new JsonArray();
  st.gatherSprites((e,x,y,p)->{try{NativeImage im=new NativeImage(1,1,false);im.setPixel(0,0,0xffffffff);try(SpriteContents contents=new SpriteContents(e.name(),new FrameSize(e.width(),e.height()),im)){JsonObject r=measure(contents,st.getWidth(),st.getHeight(),x,y,p,c.getAsJsonArray("queries"));r.addProperty("tag",e.tag());a.add(r);}}catch(Exception z){throw new RuntimeException(z);}});
  JsonObject r=new JsonObject();r.addProperty("atlas_width",st.getWidth());r.addProperty("atlas_height",st.getHeight());r.add("sprites",a);return r;
 }
 public static void main(String[] args)throws Exception{
  CTOR=TextureAtlasSprite.class.getDeclaredConstructor(Identifier.class,SpriteContents.class,int.class,int.class,int.class,int.class,int.class);CTOR.setAccessible(true);
  JsonObject in=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonObject(),out=new JsonObject();JsonArray rows=new JsonArray();
  try(ZipFile jar=new ZipFile(args[2])){for(JsonElement j:in.getAsJsonArray("cases")){JsonObject c=j.getAsJsonObject(),r=new JsonObject();r.addProperty("id",c.get("id").getAsString());r.add("result",direct(c,jar));rows.add(r);}}out.add("cases",rows);rows=new JsonArray();
  for(JsonElement j:in.getAsJsonArray("stitch_cases")){JsonObject c=j.getAsJsonObject(),r=new JsonObject();r.addProperty("id",c.get("id").getAsString());r.add("result",stitch(c));rows.add(r);}out.add("stitch_cases",rows);
  out.add("texture_atlas_sprite_declared_methods",methods(TextureAtlasSprite.class));out.add("uv_mapping_declared_methods",methods(UvMapping.class));JsonArray shrink=new JsonArray();
  Arrays.stream(TextureAtlasSprite.class.getMethods()).filter(m->m.getName().toLowerCase(Locale.ROOT).contains("shrink")).map(Method::toGenericString).sorted().forEach(shrink::add);out.add("public_shrink_methods",shrink);Files.writeString(Path.of(args[1]),G.toJson(out));
 }
}
'''
def sha(b):return hashlib.sha256(b).hexdigest()
def canonical(x):return json.dumps(x,sort_keys=True,separators=(',',':'),ensure_ascii=True).encode()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,sort_keys=True,indent=2)+'\n')
QUERIES=['00000000','80000000','00000001','007fffff','00800000','3dcccccd','3e800000','3f000000','3f400000','3f7fffff','3f800000','3f800001','40000000','41800000','bf800000','be800000','7f7fffff','ff7fffff','7f800000','ff800000','7fc00000','7fc12345']
def inputs():
    cases=[];resources=[]
    def add(name,aw,ah,w,h,x=0,y=0,p=0,domain='admitted',resource=None,queries=None):
        c={'id':name,'atlas_width':aw,'atlas_height':ah,'width':w,'height':h,'x':x,'y':y,'padding':p,'domain':domain,'queries':queries or QUERIES}
        if resource:c['resource']=resource
        cases.append(c)
    add('normalized16',16,16,16,16);add('padded16',32,32,16,16,p=1);add('odd_nonsquare',127,63,17,9,7,11,3);add('one_pixel',3,5,1,1,1,2,1,domain='outside')
    add('corner_at_upper',64,64,16,17,44,43,2);add('content_only_fits',16,16,16,16,p=0);add('padding_past_edge',16,16,16,16,p=1,domain='outside')
    for edge in [16777215,16777216,16777217,16777218,536870880]:add('i2f_'+str(edge),536870912,536870912,7,11,edge,edge,3)
    for level in [0,1,2,4,8]:
        for setting in [0,1,2,5]:
            p=(1<<level)<<(max(0,min(setting-1,4)));add(f'mip_padding_{level}_{setting}',32768,16384,17,9,256,512,p)
    for aw,ah,w,h,x,y,p in [(0,0,1,1,0,0,0),(0,16,16,16,0,0,0),(-1,16,1,1,0,0,0),(16,16,0,0,0,0,0),(16,16,-1,1,0,0,0),(16,16,1,1,-1,-3,0),(16,16,1,1,0,0,-1),(2147483647,2147483647,1,1,2147483647,2147483647,1),(16,16,16,16,2147483647,2147483647,2147483647),(1073741824,1073741824,1,1,536870912,536870912,0)]:add('raw_'+str(len(cases)),aw,ah,w,h,x,y,p,domain='outside')
    rng=random.Random(2632603)
    for i in range(160):
        aw=rng.randrange(33,4097);ah=rng.randrange(33,4097);p=rng.randrange(0,5);w=rng.randrange(1,min(65,aw-2*p));h=rng.randrange(1,min(65,ah-2*p));x=rng.randrange(0,aw-w-2*p+1);y=rng.randrange(0,ah-h-2*p+1)
        queries=QUERIES[:16]+[f'{rng.randrange(0x3c000000,0x3f800001):08x}'for _ in range(4)];add(f'random_{i:03d}',aw,ah,w,h,x,y,p,queries=queries)
    with zipfile.ZipFile(CLIENT)as z:
        for name in ['stone','dirt','oak_planks','grass_block_top','glass','snow','water_still','lava_still']:
            path=f'assets/minecraft/textures/block/{name}.png';b=z.read(path);w,h=struct.unpack('>II',b[16:24]);resources.append({'path':path,'sha256':sha(b),'width':w,'height':h});add('actual_png_'+name,8192,8192,w,h,16,32,4,resource=path)
    stitch=[]
    for mip,pad in [(0,0),(1,0),(2,0),(2,2),(4,5)]:
        stitch.append({'id':f'actual_stitch_{mip}_{pad}','max_width':8192,'max_height':8192,'mip_level':mip,'padding_setting':pad,'entries':[{'tag':i,'width':w,'height':h}for i,(w,h)in enumerate([(16,16),(17,9),(7,31),(1,1),(63,27)])],'queries':QUERIES[:16]})
    return {'cases':cases,'stitch_cases':stitch,'resources':resources}
def execute(data,tag):
    cp,provenance=verified_client_classpath();CACHE.mkdir(parents=True,exist_ok=True);src=CACHE/'SpriteUvProbe.java';src.write_text(SOURCE);inp=CACHE/(tag+'-inputs.json');out=CACHE/(tag+'-output.json');write(inp,data)
    cmd=[str(JAVA),'-Djava.awt.headless=true','--enable-native-access=ALL-UNNAMED','-cp',':'.join(map(str,cp)),str(src),str(inp),str(out),str(CLIENT)]
    r=subprocess.run(cmd,capture_output=True,text=True,timeout=90);(CACHE/(tag+'-stderr.txt')).write_text(r.stderr)
    if r.returncode:raise RuntimeError(r.stderr)
    b=subprocess.run([str(JAVA.with_name('javap')),'-cp',':'.join(map(str,cp)),'-c','-p',*CLASSES],capture_output=True,check=True).stdout;(CACHE/'official-bytecode.txt').write_bytes(b)
    with zipfile.ZipFile(CLIENT)as z:classes={c:sha(z.read(c.replace('.','/')+'.class'))for c in CLASSES}
    return {'schema':1,'pin':'26.3','inputs':data,'observations':json.loads(out.read_text()),'provenance':{'classpath':provenance,'official_classes_sha256':classes,'harness_sha256':sha(SOURCE.encode()),'bytecode_sha256':sha(b)},'boundary':'Actual SpriteContents(FrameSize,NativeImage) and TextureAtlasSprite constructor/getters/getU/getV. Scalar direct fixtures use a1x1 opaque CPU image with supplied FrameSize, intentionally distinct from image dimensions; eight resources decode actual pinned PNGs. Five scenes use actual Stitcher callbacks directly. No animation metadata, mipmap generation, GPU upload, UBO execution or final frame.'}
def seal(v):v['observation_sha256']=sha(canonical(v['observations']));return v
def validate(v,fresh=None):
    if v['schema']!=1 or v['pin']!='26.3':raise ValueError('Pin/schema differs')
    if v['inputs']!=inputs():raise ValueError('Inputs differ')
    if v['observation_sha256']!=sha(canonical(v['observations'])):raise ValueError('Observations digest differs')
    if v['provenance']['harness_sha256']!=sha(SOURCE.encode()):raise ValueError('Harness differs')
    if fresh is not None and(v['observations']!=fresh['observations']or v['provenance']!=fresh['provenance']):raise ValueError('Fresh official execution/provenance differs')
    if v['observations']['public_shrink_methods']!=[]:raise ValueError('Unexpected actual shrink method')
    return {'direct_cases':len(v['inputs']['cases']),'stitch_scenes':len(v['inputs']['stitch_cases']),'stitch_sprites':sum(len(x['result']['sprites'])for x in v['observations']['stitch_cases']),'actual_pngs':len(v['inputs']['resources']),'public_shrink_methods':0}
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
            fault('corner_unsealed',lambda b:b['observations']['cases'][1]['result'].__setitem__('u0','00000000'))
            fault('corner_resealed',lambda b:b['observations']['cases'][1]['result'].__setitem__('u0','00000000'),True)
            fault('normalized_interpolation',lambda b:b['observations']['cases'][0]['result']['queries'][13].__setitem__('u','3f800000'),True)
            fault('callback_padding',lambda b:b['observations']['stitch_cases'][0]['result']['sprites'][0].__setitem__('padding',0),True)
            fault('shrink_method_invented',lambda b:b['observations']['public_shrink_methods'].append('float uvShrinkRatio()'),True)
            fault('api_inventory',lambda b:b['observations']['uv_mapping_declared_methods'].clear(),True)
            fault('resource_hash',lambda b:b['inputs']['resources'][0].__setitem__('sha256','0'*64))
            fault('class_hash',lambda b:b['provenance']['official_classes_sha256'].__setitem__(CLASSES[0],'0'*64))
            summary.update(fresh_java_runs=2,corruptions_rejected=checks)
    write(ROOT/('evidence/sprite-uv-reference'+(''if a.mode=='extract'else'-'+a.mode)+'.json'),{'status':'passed','summary':summary,'reference_sha256':sha(OUT.read_bytes()),'observation_sha256':v['observation_sha256'],'command':'python3 tools/reference_sprite_uv_probe.py '+a.mode});print(summary)
if __name__=='__main__':main()
