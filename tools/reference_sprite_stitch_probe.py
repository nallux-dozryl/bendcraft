#!/usr/bin/env python3
"""Actual pinned 26.3 Stitcher receiver/callback, without client activation."""
from __future__ import annotations
import argparse, copy, hashlib, json, random, struct, subprocess, zipfile
from reference_model_probe import ROOT, CLIENT, JAVA, verified_client_classpath

OUT=ROOT/'reference/sprite_stitch.json'
CACHE=ROOT/'reference/cache/sprite-stitch'
CLASSES=['net.minecraft.client.renderer.texture.Stitcher','net.minecraft.client.renderer.texture.Stitcher$Holder','net.minecraft.client.renderer.texture.Stitcher$Region','net.minecraft.client.renderer.texture.Stitcher$Entry','net.minecraft.client.renderer.texture.Stitcher$SpriteLoader','net.minecraft.client.renderer.texture.StitcherException','net.minecraft.resources.Identifier','net.minecraft.util.Mth','net.minecraft.client.renderer.texture.SpriteLoader','net.minecraft.client.renderer.texture.TextureAtlasSprite']
SOURCE=r'''
import com.google.gson.*;
import net.minecraft.client.renderer.texture.*;
import net.minecraft.resources.Identifier;
import net.minecraft.util.Mth;
import java.util.*;
import java.nio.file.*;
import java.lang.reflect.*;
class SpriteStitchProbe {
 record E(int tag,Identifier name,int width,int height) implements Stitcher.Entry {}
 static Gson G=new GsonBuilder().serializeNulls().disableHtmlEscaping().create();
 static int n(JsonObject c,String k){return c.get(k).getAsInt();}
 static JsonObject entry(E e){JsonObject j=new JsonObject();j.addProperty("tag",e.tag());j.addProperty("namespace",e.name().getNamespace());j.addProperty("path",e.name().getPath());j.addProperty("width",e.width());j.addProperty("height",e.height());return j;}
 static Field field(Class<?> c,String n)throws Exception{Field f=c.getDeclaredField(n);f.setAccessible(true);return f;}
 static Throwable cause(Throwable t){while(t.getCause()!=null)t=t.getCause();return t;}
 static JsonObject pack(JsonObject c)throws Exception {
  JsonObject o=new JsonObject();Stitcher<E> s=new Stitcher<>(n(c,"max_width"),n(c,"max_height"),n(c,"mip_level"),n(c,"padding_setting"));
  o.addProperty("padding",field(Stitcher.class,"padding").getInt(s));String phase="register";Throwable error=null;
  try{for(JsonElement j:c.getAsJsonArray("entries")){JsonObject e=j.getAsJsonObject();s.registerSprite(new E(n(e,"tag"),Identifier.fromNamespaceAndPath(e.get("namespace").getAsString(),e.get("path").getAsString()),n(e,"width"),n(e,"height")));}phase="stitch";s.stitch();}catch(Throwable t){error=cause(t);}
  o.addProperty("status",error==null?"ok":"error");if(error!=null){o.addProperty("phase",phase);o.addProperty("exception",error.getClass().getName());o.addProperty("message",String.valueOf(error.getMessage()));}
  o.addProperty("width",s.getWidth());o.addProperty("height",s.getHeight());JsonArray placements=new JsonArray();
  s.gatherSprites((e,x,y,p)->{JsonObject r=entry(e);r.addProperty("x",x);r.addProperty("y",y);r.addProperty("padding",p);placements.add(r);});o.add("placements",placements);
  List<Object> holders=new ArrayList<>((List<?>)field(Stitcher.class,"texturesToBeStitched").get(s));
  @SuppressWarnings("unchecked") Comparator<Object> comp=(Comparator<Object>)field(Stitcher.class,"HOLDER_COMPARATOR").get(null);holders.sort(comp);JsonArray sorted=new JsonArray();
  for(Object h:holders){JsonObject e=entry((E)field(h.getClass(),"entry").get(h));e.addProperty("padded_width",field(h.getClass(),"width").getInt(h));e.addProperty("padded_height",field(h.getClass(),"height").getInt(h));sorted.add(e);}o.add("sorted",sorted);
  if(error instanceof StitcherException x){JsonArray all=new JsonArray();for(Stitcher.Entry e:x.getAllSprites())all.add(((E)e).tag());o.add("exception_sorted_tags",all);}
  return o;
 }
 static JsonObject raw(JsonObject c)throws Exception{
  JsonObject o=new JsonObject();int v=n(c,"value"),level=n(c,"level");
  Method m=Stitcher.class.getDeclaredMethod("smallestFittingMinTexel",int.class,int.class);m.setAccessible(true);
  o.addProperty("rounded",(int)m.invoke(null,v,level));o.addProperty("power_of_two",Mth.smallestEncompassingPowerOfTwo(v));
  Stitcher<E> s=new Stitcher<>(1,1,level,n(c,"padding_setting"));o.addProperty("padding",field(Stitcher.class,"padding").getInt(s));return o;
 }
 public static void main(String[] a)throws Exception{
  JsonObject in=JsonParser.parseString(Files.readString(Path.of(a[0]))).getAsJsonObject(),out=new JsonObject();JsonArray rows=new JsonArray();
  for(JsonElement j:in.getAsJsonArray("cases")){JsonObject c=j.getAsJsonObject(),r=new JsonObject();r.addProperty("id",c.get("id").getAsString());r.add("result",pack(c));rows.add(r);}out.add("cases",rows);rows=new JsonArray();
  for(JsonElement j:in.getAsJsonArray("recovery_cases")){JsonObject c=j.getAsJsonObject(),r=new JsonObject();r.addProperty("id",c.get("id").getAsString());r.add("result",pack(c));rows.add(r);}out.add("recovery_cases",rows);rows=new JsonArray();
  for(JsonElement j:in.getAsJsonArray("raw_cases")){JsonObject c=j.getAsJsonObject(),r=new JsonObject();r.addProperty("id",c.get("id").getAsString());r.add("result",raw(c));rows.add(r);}out.add("raw_cases",rows);Files.writeString(Path.of(a[1]),G.toJson(out));
 }
}
'''

def sha(b):return hashlib.sha256(b).hexdigest()
def canonical(x):return json.dumps(x,sort_keys=True,separators=(',',':'),ensure_ascii=True).encode()
def write(p,x):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(x,sort_keys=True,indent=2)+'\n')
def inputs():
    cases=[];resources=[]
    def add(name,dims=(),mw=256,mh=256,mip=0,pad=0,entries=None,domain='admitted'):
        entries=entries if entries is not None else[{'tag':i,'namespace':'probe','path':f'sprite/{i:04d}','width':w,'height':h}for i,(w,h)in enumerate(dims)]
        cases.append({'id':name,'max_width':mw,'max_height':mh,'mip_level':mip,'padding_setting':pad,'entries':entries,'domain':domain})
    add('empty');add('one',[(16,16)]);add('three_palette',[(16,16)]*3);add('non_power_max',[(17,7),(4,12),(6,6)],63,47)
    add('initial_tall_exceeds_height',[(4,40)],32,16);add('initial_wide_dropped',[(40,4)],16,32)
    add('wide_dropped_then_small',[(40,4),(3,3)],16,32);add('tall_exceeds_then_small',[(4,40),(3,3)],32,16)
    for pad in [-2147483648,-7,-1,0,1,2,3,4,5,6,2147483647]:
        for mip in [0,1,2,4]:add(f'padding_{pad}_{mip}',[(1,1),(7,11),(16,16),(19,5)],2048,2048,mip,pad)
    for size in [1,2,3,4,7,8,15,16,17,31,32,33,63,64,65,127,128,129]:
        add(f'rounding_{size}',[(size,size),(size,1),(1,size)],512,512,3)
    ties=[{'tag':i,'namespace':n,'path':p,'width':8,'height':8}for i,(n,p)in enumerate([('a','z'),('z','a'),('b','a'),('a','a'),('a','a'),('',''),('minecraft','../a'),('n','/a'),('n','a/b')])]
    add('path_before_namespace',entries=ties)
    for i in range(12):add(f'tie_rotation_{i}',entries=ties[i%len(ties):]+ties[:i%len(ties)])
    for mw,mh in [(8,8),(16,32),(32,16),(64,8),(8,64),(31,31),(0,16),(-1,16)]:add(f'failure_bounds_{mw}_{mh}',[(14,14)]*4,mw,mh,domain='admitted'if mw>0 and mh>0 else'outside')
    for dims in [[(40,2)],[(2,40)],[(31,31)],[(0,16)],[(16,0)],[(-1,7)],[(2147483647,1)],[(1073741824,1)],[(536870910,1)],[(536870912,1)]]:
        add('dimension_'+str(len(cases)),dims,64,64,domain='admitted'if all(0<w<=536870910 and 0<h<=536870910 for w,h in dims)else'outside')
    for ns,p in [('..','a'),('Bad','a'),('a','A'),('a','a:b'),('','a'),('a',''),('a','../x'),('a','/x')]:add('identifier_'+str(len(cases)),entries=[{'tag':0,'namespace':ns,'path':p,'width':4,'height':4}],domain='invalid-id'if ns=='..'or any(c.isupper()or c==':'for c in ns+p)else'admitted')
    for level in [-1,25,30,31,32,33,2147483647,-2147483648]:add('mip_outside_'+str(level),[(4,4)],64,64,level,0,domain='outside')
    for mw,mh in [(1073741824,1073741824),(2147483647,2147483647)]:add('max_outside_'+str(mw),[(1,1)]*3,mw,mh,domain='outside')
    rng=random.Random(2603)
    for i in range(180):
        count=rng.randrange(1,33);dims=[(rng.randrange(1,66),rng.randrange(1,66))for _ in range(count)]
        add(f'random_{i:03d}',dims,rng.choice([63,128,256,512]),rng.choice([63,128,256,512]),rng.randrange(0,4),rng.randrange(0,4))
    with zipfile.ZipFile(CLIENT)as z:
        entries=[]
        for name in sorted(n for n in z.namelist()if n.startswith('assets/')and n.endswith('.png')):
            b=z.read(name);w,h=struct.unpack('>II',b[16:24]);ns,tail=name[7:].split('/',1)
            if not tail.startswith('textures/'):continue
            p=tail[9:-4];entries.append({'tag':len(entries),'namespace':ns,'path':p,'width':w,'height':h});resources.append({'path':name,'sha256':sha(b),'width':w,'height':h})
        for count in [3,64,512,len(entries)]:add(f'official_static_rectangles_{count}',entries=entries[:count],mw=16384,mh=16384,mip=2,pad=0)
        add('official_rectangles_too_small',entries=entries[:512],mw=128,mh=128,mip=2)
    values=[-2147483648,-1073741824,-1,0,1,2,3,7,15,16,17,31,32,33,536870911,536870912,1073741823,1073741824,1073741825,2147483647]
    raw=[{'id':f'raw_{i}_{level}_{pad}','value':v,'level':level,'padding_setting':pad}for i,v in enumerate(values)for level,pad in [(0,0),(1,1),(4,3),(24,5),(30,5),(31,0),(32,0),(-1,-2147483648),(2147483647,2147483647)]]
    recovery=[dict(c,id=c['id']+'_recovery',max_width=16384,max_height=16384,mip_level=0,padding_setting=0)for c in cases if c['domain']=='admitted']
    return {'cases':cases,'recovery_cases':recovery,'raw_cases':raw,'resources':resources}
def execute(data,tag):
    cp,provenance=verified_client_classpath();CACHE.mkdir(parents=True,exist_ok=True)
    src=CACHE/'SpriteStitchProbe.java';src.write_text(SOURCE);inp=CACHE/(tag+'-inputs.json');out=CACHE/(tag+'-output.json');write(inp,data)
    cmd=[str(JAVA),'-Djava.awt.headless=true','-cp',':'.join(map(str,cp)),str(src),str(inp),str(out)]
    r=subprocess.run(cmd,capture_output=True,text=True,timeout=90);(CACHE/(tag+'-stderr.txt')).write_text(r.stderr)
    if r.returncode:raise RuntimeError(r.stderr)
    b=subprocess.run([str(JAVA.with_name('javap')),'-classpath',':'.join(map(str,cp)),'-c','-p',*CLASSES],capture_output=True,check=True).stdout
    (CACHE/'official-bytecode.txt').write_bytes(b)
    with zipfile.ZipFile(CLIENT)as z:classes={n:sha(z.read(n.replace('.','/')+'.class'))for n in CLASSES}
    return {'schema':1,'pin':'26.3','inputs':data,'observations':json.loads(out.read_text()),'provenance':{'classpath':provenance,'official_classes_sha256':classes,'harness_sha256':sha(SOURCE.encode()),'bytecode_sha256':sha(b)},'boundary':'Actual official Stitcher constructor/registerSprite/stitch/gatherSprites with supplied Entry DTO rectangles. Reflection observes official Holder sort/rounded sizes. Not production sprite-source/animation frame selection, mipmap pixel generation, TextureAtlasSprite construction or GPU atlas upload.'}
def seal(v):v['observation_sha256']=sha(canonical(v['observations']));return v
def validate(v,fresh=None):
    if v['pin']!='26.3'or v['schema']!=1:raise ValueError('Wrong pin/schema')
    if v['inputs']!=inputs():raise ValueError('Inputs differ')
    if v['provenance']['harness_sha256']!=sha(SOURCE.encode()):raise ValueError('Harness differs')
    if v['observation_sha256']!=sha(canonical(v['observations'])):raise ValueError('Observation digest differs')
    if fresh is not None and(v['observations']!=fresh['observations']or v['provenance']!=fresh['provenance']):raise ValueError('Fresh official execution/provenance differs')
    if [x['id']for x in v['observations']['cases']]!=[x['id']for x in v['inputs']['cases']]:raise ValueError('Case order differs')
    return {'packing_cases':len(v['inputs']['cases']),'recovery_cases':len(v['inputs']['recovery_cases']),'raw_integer_cases':len(v['inputs']['raw_cases']),'actual_texture_rectangles':len(v['inputs']['resources']),'successful_cases':sum(x['result']['status']=='ok'for x in v['observations']['cases'])}
def main():
    ap=argparse.ArgumentParser();ap.add_argument('mode',choices=['extract','validate','selftest']);a=ap.parse_args()
    if a.mode=='extract':v=seal(execute(inputs(),'extract'));summary=validate(v);write(OUT,v)
    else:
        v=json.loads(OUT.read_text());fresh=seal(execute(inputs(),a.mode+'-fresh'));summary=validate(v,fresh)
        if a.mode=='selftest':
            validate(v,seal(execute(inputs(),'selftest-second')));checks=[]
            def fault(name,change,reseal=False):
                bad=copy.deepcopy(v);change(bad)
                if reseal:seal(bad)
                try:validate(bad,fresh)
                except ValueError:checks.append(name);return
                raise AssertionError('Corruption accepted: '+name)
            fault('placement_unsealed',lambda b:b['observations']['cases'][1]['result']['placements'][0].__setitem__('x',7))
            fault('placement_resealed',lambda b:b['observations']['cases'][1]['result']['placements'][0].__setitem__('x',7),True)
            fault('rounded_dimensions',lambda b:b['observations']['cases'][1]['result']['sorted'][0].__setitem__('padded_width',16),True)
            fault('callback_order',lambda b:b['observations']['cases'][2]['result']['placements'].reverse(),True)
            fault('failure_status',lambda b:b['observations']['cases'][3]['result'].__setitem__('status','wrong'),True)
            fault('raw_overflow',lambda b:b['observations']['raw_cases'][0]['result'].__setitem__('power_of_two',1),True)
            fault('resource_bytes',lambda b:b['inputs']['resources'][0].__setitem__('sha256','0'*64))
            fault('class_hash',lambda b:b['provenance']['official_classes_sha256'].__setitem__(CLASSES[0],'0'*64))
            summary.update(fresh_java_runs=2,corruptions_rejected=checks)
    write(ROOT/('evidence/sprite-stitch-reference'+(''if a.mode=='extract'else'-'+a.mode)+'.json'),{'status':'passed','summary':summary,'reference_sha256':sha(OUT.read_bytes()),'observation_sha256':v['observation_sha256'],'command':'python3 tools/reference_sprite_stitch_probe.py '+a.mode});print(summary)
if __name__=='__main__':main()
