#!/usr/bin/env python3
"""Actual pinned CPU MipmapGenerator/NativeImage outputs, never a second generator."""
from __future__ import annotations
import argparse,copy,hashlib,json,random,subprocess,zipfile
from pathlib import Path
from reference_model_probe import ROOT,CLIENT,JAVA,verified_client_classpath
OUT=ROOT/'reference/texture_mipmap.json';CACHE=ROOT/'reference/cache/texture-mipmap'
CLASSES=['net.minecraft.client.renderer.texture.MipmapGenerator','net.minecraft.client.renderer.texture.MipmapStrategy','net.minecraft.util.ARGB','com.mojang.blaze3d.platform.TextureUtil','com.mojang.blaze3d.platform.Transparency','com.mojang.blaze3d.platform.NativeImage']
SOURCE=r'''
import com.google.gson.*;
import com.mojang.blaze3d.platform.*;
import net.minecraft.client.renderer.texture.*;
import net.minecraft.resources.Identifier;
import net.minecraft.util.ARGB;
import java.lang.reflect.*;
import java.nio.file.*;
import java.util.*;
import java.util.zip.*;
class TextureMipmapProbe {
 static Gson G=new GsonBuilder().serializeNulls().disableHtmlEscaping().create();
 static String bits(float f){return String.format("%08x",Float.floatToRawIntBits(f));}
 static int word(JsonElement e){return (int)e.getAsLong();}
 static JsonObject image(NativeImage im){JsonObject r=new JsonObject();r.addProperty("width",im.getWidth());r.addProperty("height",im.getHeight());JsonArray a=new JsonArray();for(int y=0;y<im.getHeight();y++)for(int x=0;x<im.getWidth();x++)a.add(Integer.toUnsignedLong(im.getPixel(x,y)));r.add("pixels",a);return r;}
 static JsonArray images(NativeImage[] levels){JsonArray r=new JsonArray();for(NativeImage im:levels)r.add(image(im));return r;}
 static NativeImage load(JsonObject j,ZipFile jar)throws Exception{
  if(j.has("resource"))return NativeImage.read(jar.getInputStream(jar.getEntry(j.get("resource").getAsString())));
  int w=j.get("width").getAsInt(),h=j.get("height").getAsInt();NativeImage im=new NativeImage(w,h,false);JsonArray a=j.getAsJsonArray("pixels");for(int y=0;y<h;y++)for(int x=0;x<w;x++)im.setPixel(x,y,word(a.get(x+y*w)));return im;
 }
 static JsonObject run(JsonObject c,ZipFile jar)throws Exception{
  List<NativeImage> owned=new ArrayList<>();NativeImage[] supplied=new NativeImage[c.getAsJsonArray("levels").size()],result=null;JsonObject out=new JsonObject();
  try {
   for(int i=0;i<supplied.length;i++){supplied[i]=load(c.getAsJsonArray("levels").get(i).getAsJsonObject(),jar);owned.add(supplied[i]);}
   out.add("before",images(supplied));Transparency actual=supplied.length==0?Transparency.NONE:supplied[0].computeTransparency();out.addProperty("computed_transparent",actual.hasTransparent());out.addProperty("computed_translucent",actual.hasTranslucent());
   Transparency tr=c.has("transparent")?Transparency.of(c.get("transparent").getAsBoolean(),c.get("translucent").getAsBoolean()):actual;out.addProperty("supplied_transparent",tr.hasTransparent());out.addProperty("supplied_translucent",tr.hasTranslucent());
   MipmapStrategy strategy=MipmapStrategy.valueOf(c.get("strategy").getAsString().toUpperCase(Locale.ROOT));out.addProperty("effective_strategy",(strategy==MipmapStrategy.AUTO?(tr.hasTransparent()?MipmapStrategy.CUTOUT:MipmapStrategy.MEAN):strategy).getSerializedName());
   try {
    result=MipmapGenerator.generateMipLevels(Identifier.fromNamespaceAndPath("probe",c.get("path").getAsString()),supplied,c.get("target_level").getAsInt(),strategy,Float.intBitsToFloat((int)Long.parseUnsignedLong(c.get("bias").getAsString(),16)),tr);
    out.addProperty("status","ok");out.addProperty("same_array",result==supplied);JsonArray reused=new JsonArray();for(NativeImage im:result){int index=-1;for(int i=0;i<supplied.length;i++)if(im==supplied[i]){index=i;break;}reused.add(index);if(!owned.contains(im))owned.add(im);}out.add("reused",reused);out.add("output",images(result));
   } catch(Throwable t){out.addProperty("status","error");out.addProperty("error_class",t.getClass().getName());out.addProperty("error_message",t.getMessage());}
   out.add("after_supplied",images(supplied));return out;
  } finally{for(NativeImage im:owned)im.close();}
 }
 static JsonObject tables()throws Exception{
  JsonObject r=new JsonObject();Field s=ARGB.class.getDeclaredField("SRGB_TO_LINEAR"),l=ARGB.class.getDeclaredField("LINEAR_TO_SRGB"),d=TextureUtil.class.getDeclaredField("DIRECTIONS");s.setAccessible(true);l.setAccessible(true);d.setAccessible(true);JsonArray a=new JsonArray();for(short v:(short[])s.get(null))a.add(v);r.add("srgb_to_linear",a);a=new JsonArray();for(byte v:(byte[])l.get(null))a.add(v&255);r.add("linear_to_srgb",a);r.add("solidify_directions",G.toJsonTree((int[][])d.get(null)));return r;
 }
 public static void main(String[] args)throws Exception{
  JsonObject in=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonObject(),out=new JsonObject();JsonArray rows=new JsonArray();try(ZipFile jar=new ZipFile(args[2])){for(JsonElement j:in.getAsJsonArray("cases")){JsonObject c=j.getAsJsonObject(),r=new JsonObject();r.addProperty("id",c.get("id").getAsString());r.add("result",run(c,jar));rows.add(r);}}out.add("cases",rows);out.add("tables",tables());
  rows=new JsonArray();Method dark=MipmapGenerator.class.getDeclaredMethod("darkenedAlphaBlend",int.class,int.class,int.class,int.class);dark.setAccessible(true);for(JsonElement j:in.getAsJsonArray("quads")){JsonArray q=j.getAsJsonArray();int a=word(q.get(0)),b=word(q.get(1)),c=word(q.get(2)),d=word(q.get(3));JsonObject r=new JsonObject();r.addProperty("mean",Integer.toUnsignedLong(ARGB.meanLinear(a,b,c,d)));r.addProperty("dark",Integer.toUnsignedLong((Integer)dark.invoke(null,a,b,c,d)));rows.add(r);}out.add("quads",rows);Files.writeString(Path.of(args[1]),G.toJson(out));
 }
}
'''
def sha(b):return hashlib.sha256(b).hexdigest()
def canonical(v):return json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=True).encode()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,sort_keys=True,indent=2)+'\n')
def inputs():
    rng=random.Random(2631026);cases=[];resources=[]
    def level(w,h,p):return {'width':w,'height':h,'pixels':p}
    def add(name,levels,strategy='mean',target=1,path='block/probe',bias='00000000',flags=None,domain='admitted'):
        c={'id':name,'levels':levels,'strategy':strategy,'target_level':target,'path':path,'bias':bias,'domain':domain}
        if flags is not None:c.update(transparent=flags[0],translucent=flags[1])
        cases.append(c)
    patterns={
     'ordered':[0xff010203,0xff040506,0xff070809,0xfffafbfc],
     'empty_rgb':[0x00ff0000,0x0000ff00,0x000000ff,0x00abcdef],
     'alpha_edges':[0x00ffffff,0x7f123456,0x80123456,0xff000000],
     'red_blue_tie':[0xffff0000,0x00010203,0x00abcdef,0xff0000ff],
     'single_seed':[0x0000ff00,0x000000ff,0xffa123ef,0x00ffffff],
     'uniform':[0x7f123456]*4}
    for name,p in patterns.items():
        for strategy in ['auto','mean','cutout','strict_cutout','dark_cutout']:
            for path in ['block/probe','item/probe']:
                add(f'{name}_{strategy}_{path.split("/")[0]}',[level(2,2,p)],strategy,1,path)
    for w,h in [(3,3),(5,3),(3,5),(7,9),(8,4),(4,8),(1,8),(8,1)]:
        p=[rng.getrandbits(32)for _ in range(w*h)]
        for strategy in ['mean','cutout','strict_cutout','dark_cutout']:add(f'extent_{w}_{h}_{strategy}',[level(w,h,p)],strategy,1,domain='outside'if min(w,h)<2 else'admitted')
    # Seed/tie fixtures expose the actual x-major initial queue and dark scan.
    for w,h,points in [(5,5,[(0,2,0xffff0000),(4,2,0xff0000ff)]),(5,5,[(2,0,0xff00ff00),(2,4,0xffffff00)]),(4,4,[(0,3,0xfff00000),(3,0,0xff0000f0)]),(7,3,[(1,1,0x01122334),(5,1,0xfe445566)])]:
        p=[0x00abcdef]*(w*h)
        for x,y,c in points:p[x+y*w]=c
        for strategy in ['cutout','strict_cutout','dark_cutout']:add(f'tie_{len(cases)}',[level(w,h,p)],strategy,1)
    p=[rng.getrandbits(32)for _ in range(64)]
    for strategy in ['cutout','strict_cutout','dark_cutout']:
        for bias in ['80000000','3e000000','bdcccccd','3f800000','bf800000','7f800000','ff800000','7fc00000','7fc12345']:
            add('bias_'+strategy+'_'+bias,[level(8,8,p)],strategy,2,bias=bias)
    for flags in [(False,False),(True,False),(False,True),(True,True)]:add('auto_flags_'+str(flags),[level(4,4,[0x00123456,0x80123456,0xffffffff,0xff000000]*4)],'auto',1,flags=flags)
    for strategy in ['mean','cutout','strict_cutout','dark_cutout']:
        for target in [0,1,2,3]:add(f'existing_{strategy}_{target}',[level(8,8,p),level(4,4,[rng.getrandbits(32)for _ in range(16)]),level(2,2,[rng.getrandbits(32)for _ in range(4)])],strategy,target)
        add(f'level_zero_precondition_{strategy}',[level(8,8,p)],strategy,0)
        add(f'existing_unusual_shape_{strategy}',[level(8,8,p),level(3,5,[rng.getrandbits(32)for _ in range(15)])],strategy,2)
    for path in ['', 'item/', 'items/probe', 'block/item/probe']:
        add('path_prefix_'+str(len(cases)),[level(4,4,[0x0000ff00,0xff123456,0x00abcdef,0x7f445566]*4)],'cutout',0,path=path)
    for target in [-1,-2,2147483647]:add('raw_target_'+str(target),[level(2,2,patterns['single_seed'])],'cutout',target,domain='outside')
    add('empty_levels',[],'mean',0,domain='outside');add('zero_next_level',[level(2,2,patterns['ordered'])],'cutout',2,domain='outside')
    for i in range(40):
        w=rng.choice([4,6,8,10]);h=rng.choice([4,6,8,10]);p=[rng.getrandbits(32)for _ in range(w*h)];add(f'random_{i:03d}',[level(w,h,p)],rng.choice(['auto','mean','cutout','strict_cutout','dark_cutout']),1 if min(w,h)<8 else 2,path=rng.choice(['item/probe','block/probe']))
    with zipfile.ZipFile(CLIENT)as z:
        for name in ['stone','dirt','oak_planks','glass','oak_leaves','grass_block_side_overlay','water_still','lava_still']:
            path=f'assets/minecraft/textures/block/{name}.png';b=z.read(path);resources.append({'path':path,'sha256':sha(b)});add('actual_'+name,[{'resource':path}],'auto'if name not in ['glass','water_still','lava_still']else'mean',3)
    quads=[[0,0,0,0],[0xffffffff]*4,[0xffff0000,0xff00ff00,0xff0000ff,0xffffffff],[0x00ffffff,0x7f123456,0x80123456,0xff000000]]+[[rng.getrandbits(32)for _ in range(4)]for _ in range(256)]
    return {'cases':cases,'quads':quads,'resources':resources}
def execute(data,tag):
    cp,provenance=verified_client_classpath();CACHE.mkdir(parents=True,exist_ok=True);source=CACHE/'TextureMipmapProbe.java';source.write_text(SOURCE);inp=CACHE/(tag+'-inputs.json');out=CACHE/(tag+'-output.json');write(inp,data)
    command=[str(JAVA),'-Djava.awt.headless=true','--enable-native-access=ALL-UNNAMED','-cp',':'.join(map(str,cp)),str(source),str(inp),str(out),str(CLIENT)];r=subprocess.run(command,capture_output=True,text=True,timeout=120);(CACHE/(tag+'-stderr.txt')).write_text(r.stderr)
    if r.returncode:raise RuntimeError(r.stderr)
    bytecode=subprocess.run([str(JAVA.with_name('javap')),'-cp',':'.join(map(str,cp)),'-c','-p',*CLASSES],capture_output=True,check=True).stdout;(CACHE/'official-bytecode.txt').write_bytes(bytecode)
    with zipfile.ZipFile(CLIENT)as z:hashes={c:sha(z.read(c.replace('.','/')+'.class'))for c in CLASSES}
    v={'schema':1,'pin':'26.3','inputs':data,'observations':json.loads(out.read_text()),'provenance':{'classpath':provenance,'official_classes_sha256':hashes,'harness_sha256':sha(SOURCE.encode()),'bytecode_sha256':sha(bytecode)},'boundary':'Actual CPU NativeImage constructors/setPixel/read, original ARGB pixel arrays, actual five-strategy MipmapGenerator, existing image identities/base mutations, and untouched ARGB gamma table readouts. Failed Java calls may mutate and leak internal partial allocations; excluded recovery diagnostics. No atlas padding/copy/upload/GPU/animation frame selection.'};v['observation_sha256']=sha(canonical(v['observations']));return v
def validate(v,fresh=None):
    if v['schema']!=1 or v['pin']!='26.3':raise ValueError('Pin/schema differs')
    if v['inputs']!=inputs():raise ValueError('Inputs differ')
    if v['observation_sha256']!=sha(canonical(v['observations'])):raise ValueError('Observations digest differs')
    if v['provenance']['harness_sha256']!=sha(SOURCE.encode()):raise ValueError('Harness differs')
    if fresh is not None and(v['observations']!=fresh['observations']or v['provenance']!=fresh['provenance']):raise ValueError('Fresh actual receivers/provenance differ')
    rows=v['observations']['cases'];tables=v['observations']['tables'];assert len(tables['srgb_to_linear'])==256 and len(tables['linear_to_srgb'])==1024
    return {'cases':len(rows),'successful':sum(x['result']['status']=='ok'for x in rows),'failed_diagnostics':sum(x['result']['status']=='error'for x in rows),'scalar_quads':len(v['inputs']['quads']),'actual_pngs':len(v['inputs']['resources']),'lut_values':1280}
def main():
    p=argparse.ArgumentParser();p.add_argument('mode',choices=['extract','validate','selftest']);a=p.parse_args()
    if a.mode=='extract':v=execute(inputs(),'extract');summary=validate(v);write(OUT,v)
    else:
        v=json.loads(OUT.read_text());fresh=execute(inputs(),a.mode+'-fresh');summary=validate(v,fresh)
        if a.mode=='selftest':
            validate(v,execute(inputs(),'selftest-second'));checks=[]
            def fault(name,fn,reseal=False):
                bad=copy.deepcopy(v);fn(bad)
                if reseal:bad['observation_sha256']=sha(canonical(bad['observations']))
                try:validate(bad,fresh)
                except ValueError:checks.append(name);return
                raise AssertionError('Accepted corruption:'+name)
            fault('mip_pixel',lambda b:b['observations']['cases'][0]['result']['output'][1]['pixels'].__setitem__(0,0))
            fault('mip_pixel_resealed',lambda b:b['observations']['cases'][0]['result']['output'][1]['pixels'].__setitem__(0,0),True)
            fault('base_mutation',lambda b:b['observations']['cases'][6]['result']['output'][0]['pixels'].__setitem__(0,0),True)
            fault('image_identity',lambda b:b['observations']['cases'][0]['result']['reused'].__setitem__(0,-1),True)
            fault('srgb_table',lambda b:b['observations']['tables']['srgb_to_linear'].__setitem__(255,0),True)
            fault('inverse_table',lambda b:b['observations']['tables']['linear_to_srgb'].__setitem__(1023,0),True)
            fault('class_hash',lambda b:b['provenance']['official_classes_sha256'].__setitem__(CLASSES[0],'0'*64))
            fault('resource_hash',lambda b:b['inputs']['resources'][0].__setitem__('sha256','0'*64))
            summary.update(fresh_java_runs=2,corruptions_rejected=checks)
    write(ROOT/('evidence/texture-mipmap-reference'+(''if a.mode=='extract'else'-'+a.mode)+'.json'),{'status':'passed','summary':summary,'reference_sha256':sha(OUT.read_bytes()),'observation_sha256':v['observation_sha256'],'command':'python3 tools/reference_texture_mipmap_probe.py '+a.mode});print(summary)
if __name__=='__main__':main()
