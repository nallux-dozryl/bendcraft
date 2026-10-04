#!/usr/bin/env python3
"""Observe installed 26.3 Containers/ItemEntity/ExperienceOrb receivers."""
from __future__ import annotations
import hashlib,json,os,subprocess,time
from pathlib import Path
from reference_model_probe import verified_client_classpath,JAVA
ROOT=Path(__file__).resolve().parents[1];WORK=ROOT/'build/cooking-effect-entities-reference'
SOURCE=r'''import java.util.*;import java.util.function.*;import java.util.concurrent.atomic.*;import java.nio.file.*;import java.lang.reflect.*;
import com.google.gson.*;import com.mojang.serialization.*;import sun.misc.Unsafe;
import net.minecraft.world.Containers;import net.minecraft.SharedConstants;import net.minecraft.server.Bootstrap;import net.minecraft.core.*;import net.minecraft.core.registries.*;import net.minecraft.core.component.*;import net.minecraft.data.registries.VanillaRegistries;import net.minecraft.resources.*;import net.minecraft.server.level.*;import net.minecraft.world.level.*;import net.minecraft.world.level.entity.*;import net.minecraft.world.level.levelgen.*;import net.minecraft.world.item.*;import net.minecraft.world.entity.*;import net.minecraft.world.entity.item.*;import net.minecraft.world.phys.*;import net.minecraft.world.phys.shapes.*;import net.minecraft.util.*;
class CookingEffectEntitiesReference {
 static Gson JSON=new GsonBuilder().serializeNulls().create();static RegistryOps<JsonElement> OPS;static Unsafe U;static AtomicLong UNIQUE;
 static Object get(Object o,String name)throws Exception{Class<?> c=o instanceof Class<?>?(Class<?>)o:o.getClass();while(c!=null){try{Field f=c.getDeclaredField(name);f.setAccessible(true);return f.get(o instanceof Class<?>?null:o);}catch(NoSuchFieldException e){c=c.getSuperclass();}}throw new NoSuchFieldException(name);}
 static void set(Object o,String name,Object value)throws Exception{Class<?> c=o.getClass();while(c!=null){try{Field f=c.getDeclaredField(name);f.setAccessible(true);f.set(o,value);return;}catch(NoSuchFieldException e){c=c.getSuperclass();}}throw new NoSuchFieldException(name);}
 static long[] bits(long x){return new long[]{Integer.toUnsignedLong((int)(x>>>32)),Integer.toUnsignedLong((int)x)};}
 static long[] dbl(double x){return bits(Double.doubleToRawLongBits(x));}
 static Object vec(Vec3 p){return List.of(dbl(p.x),dbl(p.y),dbl(p.z));}
 static Object random(RandomSource r)throws Exception{if(r instanceof LegacyRandomSource)return Map.of("kind","legacy","seed",bits(((AtomicLong)get(r,"seed")).get()));Object s=get(r,"randomNumberGenerator");return Map.of("kind","xoroshiro","low",bits((long)get(s,"seedLo")),"high",bits((long)get(s,"seedHi")));}
 static Object stack(ItemStack s){if(s.isEmpty())return null;return Map.of("id",BuiltInRegistries.ITEM.getKey(s.getItem()).toString(),"count",Integer.toUnsignedLong(s.getCount()),"components",DataComponentMap.CODEC.encodeStart(OPS,s.getComponents()).result().orElseThrow());}
 static Object record(Entity e,long order)throws Exception{
  var b=new LinkedHashMap<String,Object>();b.put("dimension","minecraft:overworld");b.put("id",Integer.toUnsignedLong(e.getId()));b.put("uuid_most",bits(e.getUUID().getMostSignificantBits()));b.put("uuid_least",bits(e.getUUID().getLeastSignificantBits()));b.put("random",random((RandomSource)get(e,"random")));b.put("position",vec(e.position()));b.put("velocity",vec(e.getDeltaMovement()));b.put("position_o",vec(new Vec3(e.xo,e.yo,e.zo)));b.put("yaw",Integer.toUnsignedLong(Float.floatToRawIntBits(e.getYRot())));b.put("pitch",Integer.toUnsignedLong(Float.floatToRawIntBits(e.getXRot())));b.put("yaw_o",Integer.toUnsignedLong(Float.floatToRawIntBits(e.yRotO)));b.put("pitch_o",Integer.toUnsignedLong(Float.floatToRawIntBits(e.xRotO)));b.put("tick_count",Integer.toUnsignedLong(e.tickCount));b.put("first_tick",get(e,"firstTick"));b.put("removed",e.isRemoved());b.put("accessible",true);b.put("section_order",order);b.put("on_ground",e.onGround());b.put("air",Integer.toUnsignedLong(e.getAirSupply()));b.put("fire",Integer.toUnsignedLong(e.getRemainingFireTicks()));b.put("portal_cooldown",Integer.toUnsignedLong(e.getPortalCooldown()));b.put("invulnerable",e.isInvulnerable());b.put("needs_sync",e.needsSync);
  var out=new LinkedHashMap<String,Object>();out.put("common",b);out.put("age",Integer.toUnsignedLong((int)get(e,"age")));out.put("health",Integer.toUnsignedLong((int)get(e,"health")));
  if(e instanceof ItemEntity i){out.put("kind","item");out.put("item",stack(i.getItem()));out.put("pickup_delay",Integer.toUnsignedLong((int)get(e,"pickupDelay")));out.put("bob",Integer.toUnsignedLong(Float.floatToRawIntBits(i.bobOffs)));out.put("thrower",get(i,"thrower"));out.put("target",get(i,"target"));}else{ExperienceOrb o=(ExperienceOrb)e;out.put("kind","orb");out.put("value",o.getValue());out.put("count",Integer.toUnsignedLong((int)get(o,"count")));out.put("following",get(o,"followingPlayer"));}return out;
 }
 static class World extends ServerLevel {
  RandomSource rng;List<Entity> entities;List<long[]> times;EntitySectionStorage<Entity> sections;int next;long begin;boolean obstructed;Vec3 free;
  private World(){super(null,null,null,null,Level.OVERWORLD,null,false,0,List.of(),false);}
  public boolean isClientSide(){return false;}public RandomSource getRandom(){return rng;}public int getNextEntityId(){return ++next;}
  public boolean noCollision(AABB box){return !obstructed;}
  public Optional<Vec3> findFreePosition(Entity e,VoxelShape s,Vec3 center,double x,double y,double z){return Optional.ofNullable(free);}
  public <T extends Entity> List<T> getEntities(EntityTypeTest<Entity,T> test,AABB box,Predicate<? super T> predicate){List<T> out=new ArrayList<>();sections.getEntities(test,box,e->{if(predicate.test(e))out.add(e);return Continuation.CONTINUE;});return out;}
  void add(Entity e){entities.add(e);sections.getOrCreateSection(SectionPos.asLong(e.blockPosition())).add(e);}
  public boolean addFreshEntity(Entity e){try{
   long end=System.nanoTime(),unique=UNIQUE.get(),raw=((AtomicLong)get((RandomSource)get(e,"random"),"seed")).get();int draws=e instanceof ItemEntity?10:11;
   for(int i=0;i<draws;i++)raw=((raw-11)*246154705703781L)&((1L<<48)-1);
   long low=(raw^25214903917L^unique)&((1L<<48)-1);long stamp=(begin&~((1L<<48)-1))|low;if(stamp<begin)stamp+=1L<<48;
   if(stamp<begin||stamp>end)throw new AssertionError("constructor entropy did not fall in actual nanoTime interval: "+stamp+" "+begin+" "+end);
   times.add(bits(stamp));add(e);return true;
  }catch(Exception ex){throw new RuntimeException(ex);}}
 }
 static World world(String kind,long seed)throws Exception{World w=(World)U.allocateInstance(World.class);w.rng=kind.equals("legacy")?RandomSource.create(seed):new XoroshiroRandomSource(seed);set(w,"random",w.rng);w.entities=new ArrayList<>();w.times=new ArrayList<>();w.sections=new EntitySectionStorage<>(Entity.class,c->Visibility.TICKING);return w;}
 static Object records(World w)throws Exception{List<Object> out=new ArrayList<>();for(int i=0;i<w.entities.size();i++)out.add(record(w.entities.get(i),i));return out;}
 static ItemStack item(JsonObject a){if(a.get("item").isJsonNull())return ItemStack.EMPTY;var v=a.getAsJsonObject("item");var s=new ItemStack(BuiltInRegistries.ITEM.getValue(Identifier.parse(v.get("id").getAsString())),1);if(v.has("components"))s.applyComponents(DataComponentPatch.CODEC.parse(OPS,v.get("components")).result().orElseThrow());s.setCount(v.get("count").getAsInt());return s;}
 public static void main(String[] args){try{run(args);}catch(Throwable t){t.printStackTrace(new java.io.PrintStream(new java.io.FileOutputStream(java.io.FileDescriptor.err)));System.exit(1);}}
 static void run(String[] args)throws Exception{SharedConstants.tryDetectVersion();Bootstrap.bootStrap();var lookup=VanillaRegistries.createWorldLookup();for(var pending:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup))pending.forEach((holder,components)->holder.bindComponents(components));OPS=RegistryOps.create(JsonOps.INSTANCE,lookup);Field u=Unsafe.class.getDeclaredField("theUnsafe");u.setAccessible(true);U=(Unsafe)u.get(null);UNIQUE=(AtomicLong)get(RandomSupport.class,"SEED_UNIQUIFIER");World warm=world("legacy",1);new ItemEntity(warm,0,0,0,new ItemStack(Items.STONE));new ExperienceOrb(warm,0,0,0,1);
  var inputs=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonArray();List<Object> cases=new ArrayList<>();for(var raw:inputs){var c=raw.getAsJsonObject();World w=world(c.get("random").getAsString(),c.get("seed").getAsLong());Vec3 p=new Vec3(c.get("x").getAsInt()+.5,c.get("y").getAsInt()+.5,c.get("z").getAsInt()+.5);
   if(c.has("merge")){int ticket=w.rng.nextInt(40);w.rng=c.get("random").getAsString().equals("legacy")?RandomSource.create(c.get("seed").getAsLong()):new XoroshiroRandomSource(c.get("seed").getAsLong());set(w,"random",w.rng);ExperienceOrb a=new ExperienceOrb(w,p.x,p.y,p.z,1),b=new ExperienceOrb(w,p.x,p.y,p.z,1);a.setId(ticket+80);b.setId(ticket+40);set(a,"age",77);set(b,"age",11);if(c.get("merge").getAsString().equals("section")){a.setPos(p.x,p.y,-.1);b.setPos(p.x,p.y,.1);}w.add(a);w.add(b);w.next=200;}
   if(c.has("unstuck")){w.obstructed=true;w.free=new Vec3(p.x+1,p.y+.25+2,p.z+3);}
   Object before=records(w),level=random(w.rng);long unique=UNIQUE.get();int cursor=w.next;w.begin=System.nanoTime();List<Object> rounded=new ArrayList<>();for(var action:c.getAsJsonArray("actions")){var a=action.getAsJsonObject();if(a.get("op").getAsString().equals("drop"))Containers.dropItemStack(w,c.get("x").getAsInt(),c.get("y").getAsInt(),c.get("z").getAsInt(),item(a));else{int uses=a.get("uses").getAsInt();float rate=Float.intBitsToFloat((int)a.get("rate").getAsLong()),product=uses*rate;int total=Mth.floor(product);float fraction=Mth.frac(product);if(fraction!=0&&w.rng.nextFloat()<fraction)total++;rounded.add(total);ExperienceOrb.award(w,p,total);}}
   cases.add(Map.ofEntries(Map.entry("id",c.get("id").getAsString()),Map.entry("initial_records",before),Map.entry("records",records(w)),Map.entry("level_before",level),Map.entry("level_after",random(w.rng)),Map.entry("unique_before",bits(unique)),Map.entry("unique_after",bits(UNIQUE.get())),Map.entry("cursor_before",Integer.toUnsignedLong(cursor)),Map.entry("cursor_after",Integer.toUnsignedLong(w.next)),Map.entry("times",w.times),Map.entry("rounded",rounded)));
  }Files.writeString(Path.of(args[1]),JSON.toJson(Map.of("version",SharedConstants.getCurrentVersion().id(),"cases",cases,"item_width",EntityTypes.ITEM.getWidth(),"orb_width",EntityTypes.EXPERIENCE_ORB.getWidth(),"orb_height",EntityTypes.EXPERIENCE_ORB.getHeight())));
 }
}'''
def bits_float(v):
    import struct
    return int.from_bytes(struct.pack('>f',v),'big')
def inputs():
    def drop(count=None,patch=None,id='stone'):
        s=None if count is None else {'id':'minecraft:'+id,'count':count}
        if patch is not None:s['components']=patch
        return {'op':'drop','item':s}
    def xp(n,rate=1.):return {'op':'xp','uses':n,'rate':bits_float(rate)}
    cases=[]
    for kind in ['legacy','xoroshiro']:
        for label,actions in [('empty',[drop()]),('single',[drop(1)]),('fragment',[drop(99,{'minecraft:enchantment_glint_override':True})]),('ordered',[drop(),drop(64),xp(19,.7)]),('rounding',[xp(3,.1),xp(-3,.1),xp(1,float('nan'))]),('denominations',[xp(n) for n in [1,3,7,17,37,73,149,307,617,1237,2477,5000]])]:
            cases.append({'id':kind+'-'+label,'random':kind,'seed':-987654321,'x':-7,'y':65,'z':3,'actions':actions})
    for mode in ['same','section']:
        cases.append({'id':'merge-'+mode,'random':'legacy','seed':17,'x':0,'y':0,'z':0,'merge':mode,'actions':[xp(1)]})
    cases.append({'id':'unstuck','random':'legacy','seed':456,'x':10,'y':-3,'z':7,'unstuck':True,'actions':[xp(7)]})
    return cases

def main():
    WORK.mkdir(parents=True,exist_ok=True);(WORK/'CookingEffectEntitiesReference.java').write_text(SOURCE);cases=inputs();(WORK/'input.json').write_text(json.dumps(cases,separators=(',',':')))
    paths,provenance=verified_client_classpath();cmd=[JAVA,'-Xmx512m','--source','25','--class-path',os.pathsep.join(map(str,paths)),WORK/'CookingEffectEntitiesReference.java',WORK/'input.json',WORK/'output.json']
    start=time.monotonic();p=subprocess.run(list(map(str,cmd)),cwd=WORK,capture_output=True,text=True,timeout=120);(WORK/'java.stdout').write_text(p.stdout);(WORK/'java.stderr').write_text(p.stderr);assert p.returncode==0,p.stderr
    output=json.loads((WORK/'output.json').read_text());assert output['version']=='26.3'
    result={'pin':'26.3','inputs':cases,'observations':output,'provenance':provenance,'receiver':'Installed Java Containers.dropItemStack and ExperienceOrb.award; real ItemEntity/ExperienceOrb constructors; actual EntitySectionStorage query order. World fixture captures addFreshEntity and provides declared noCollision/findFreePosition responses. Entropy recovered from observed final legacy seed via inverse LCG and checked against actual System.nanoTime interval; no constructor RNG overridden.','command':'python3 tools/reference_cooking_effect_entities.py','seconds':round(time.monotonic()-start,3),'probe_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    (ROOT/'reference/cooking_effect_entities.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'cases':len(cases),'seconds':result['seconds'],'entities':sum(len(c['records']) for c in output['cases'])}))
if __name__=='__main__':main()
