#!/usr/bin/env python3
"""Observe actual ItemEntity tick joined to actual PersistentEntitySectionManager."""
import hashlib,json,os,re,subprocess,time
from pathlib import Path
from reference_model_probe import verified_client_classpath,JAVA
import reference_item_entity_tick as Tick
ROOT=Path(__file__).resolve().parents[1];WORK=ROOT/'build/item-entity-tick-managed-reference'
BODY=r'''
class ManagedItemTickReference {
 static class Env implements LevelCallback<Entity>,EntityPersistentStorage<Entity> {
  final PersistentEntitySectionManager<Entity> manager=new PersistentEntitySectionManager<>(Entity.class,this,this);
  final EntityTickList ticks=new EntityTickList();final List<Object> events=new ArrayList<>();
  void event(String name,Entity e){events.add(Map.of("event",name,"id",e.getId()));}
  public CompletableFuture<ChunkEntities<Entity>> loadEntities(ChunkPos p){return CompletableFuture.completedFuture(new ChunkEntities<Entity>(p,List.of()));}
  public void storeEntities(ChunkEntities<Entity> c){throw new AssertionError("writer outside reference");}public void flush(boolean sync){}
  public void onCreated(Entity e){event("created",e);}public void onDestroyed(Entity e){event("destroyed",e);}
  public void onTrackingStart(Entity e){event("tracking_start",e);}public void onTrackingEnd(Entity e){event("tracking_end",e);}
  public void onTickingStart(Entity e){ticks.add(e);event("ticking_start",e);}public void onTickingEnd(Entity e){ticks.remove(e);event("ticking_end",e);}
  public void onSectionChange(Entity e){event("section_change",e);}
  List<Integer> scheduled(){List<Integer> out=new ArrayList<>();ticks.forEach(e->out.add(e.getId()));return out;}
  List<Integer> tracked(){List<Integer> out=new ArrayList<>();manager.getEntityGetter().getAll().forEach(e->out.add(e.getId()));return out;}
  List<Integer> query(JsonArray b){List<Integer> out=new ArrayList<>();manager.getEntityGetter().get(new AABB(b.get(0).getAsDouble(),b.get(1).getAsDouble(),b.get(2).getAsDouble(),b.get(3).getAsDouble(),b.get(4).getAsDouble(),b.get(5).getAsDouble()),e->out.add(e.getId()));return out;}
  Object sections()throws Exception{
   Object storage=CookingEffectEntitiesReference.get(manager,"sectionStorage");
   var sections=(it.unimi.dsi.fastutil.longs.Long2ObjectMap<EntitySection<Entity>>)CookingEffectEntitiesReference.get(storage,"sections");
   long[] keys=sections.keySet().toLongArray();Arrays.sort(keys);List<Object> out=new ArrayList<>();
   for(long k:keys){var s=sections.get(k);out.add(Map.of("key",CookingEffectEntitiesReference.bits(k),"status",s.getStatus().name(),"members",s.getEntities().map(Entity::getId).toList()));}return out;
  }
 }
 static class World extends ItemEntityTickReference.World {
  Env env;List<Object> queries;
  private World(){super();}
  public <T extends Entity> List<T> getEntities(EntityTypeTest<Entity,T> type,AABB box,Predicate<? super T> predicate){
   List<T> out=new ArrayList<>();env.manager.getEntityGetter().get(type,box,e->{if(predicate.test(e))out.add(e);return Continuation.CONTINUE;});queries.add(out.stream().map(Entity::getId).toList());return out;
  }
 }
 static World world(JsonObject c)throws Exception{
  var base=ItemEntityTickReference.world(c);var w=(World)ItemEntityTickReference.U.allocateInstance(World.class);
  for(Class<?> k=ItemEntityTickReference.World.class;k!=null;k=k.getSuperclass())for(Field f:k.getDeclaredFields())if(!Modifier.isStatic(f.getModifiers())){f.setAccessible(true);f.set(w,f.get(base));}
  w.env=new Env();w.queries=new ArrayList<>();for(var raw:c.getAsJsonArray("chunks")){var a=raw.getAsJsonObject();w.env.manager.updateChunkStatus(new ChunkPos(a.get("x").getAsInt(),a.get("z").getAsInt()),Visibility.valueOf(a.get("status").getAsString()));}return w;
 }
 static JsonObject record(ItemEntity e,int order,Env env)throws Exception{
  var raw=ItemEntityTickReference.JSON.toJsonTree(CookingEffectEntitiesReference.record(e,order)).getAsJsonObject();raw.getAsJsonObject("common").addProperty("accessible",env.tracked().contains(e.getId()));return raw;
 }
 static List<Object> cells(World w,JsonArray range)throws Exception{
  int a=range.get(0).getAsInt(),b=range.get(1).getAsInt(),c=range.get(2).getAsInt(),d=range.get(3).getAsInt(),e=range.get(4).getAsInt(),f=range.get(5).getAsInt();List<Object> out=new ArrayList<>();
  for(int x=a;x<d;x++)for(int y=b;y<e;y++)for(int z=c;z<f;z++)out.add(ItemEntityTickReference.cell(w,x,y,z));return out;
 }
 public static void main(String[] args)throws Exception{
  // Reuse real pinned initialization with zero tick/profile cases, not a replay.
  ItemEntityTickReference.main(new String[]{args[2],args[3],args[4],args[2]});List<Object> out=new ArrayList<>();
  for(var raw:JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonArray()){
   var c=raw.getAsJsonObject();var w=world(c);List<ItemEntity> items=new ArrayList<>();items.add(ItemEntityTickReference.entity(w,c,71));
   if(c.has("neighbours"))for(var n:c.getAsJsonArray("neighbours"))items.add(ItemEntityTickReference.entity(w,n.getAsJsonObject(),71+items.size()));
   for(var e:items)if(!w.env.manager.addNewEntity(e))throw new AssertionError("fixture registration");
   var row=new LinkedHashMap<String,Object>();row.put("id",c.get("id").getAsString());row.put("cells",cells(w,c.getAsJsonArray("coverage")));List<Object> before=new ArrayList<>(),patches=new ArrayList<>(),runtimes=new ArrayList<>();
   for(int i=0;i<items.size();i++){var e=items.get(i);before.add(record(e,i,w.env));patches.add(DataComponentPatch.CODEC.encodeStart(ItemEntityTickReference.OPS,e.getItem().getComponentsPatch()).result().orElseThrow());runtimes.add(ItemEntityTickReference.runtime(e));}
   row.put("before",before);row.put("patches",patches);row.put("runtime_before",runtimes);row.put("query_before",w.env.query(c.getAsJsonArray("coverage")));row.put("sections_before",w.env.sections());row.put("tracked_before",w.env.tracked());row.put("scheduled_before",w.env.scheduled());row.put("sound_before",CookingEffectEntitiesReference.random((RandomSource)CookingEffectEntitiesReference.get(w,"soundSeedGenerator")));
   w.env.events.clear();w.events.clear();var source=items.get(0);long oldKey=SectionPos.asLong(source.blockPosition());source.commonTick();source.tick();boolean changed=oldKey!=SectionPos.asLong(source.blockPosition());
   List<Object> after=new ArrayList<>(),afterRuntimes=new ArrayList<>();for(int i=0;i<items.size();i++){var e=items.get(i);after.add(record(e,i==0&&changed?items.size():i,w.env));afterRuntimes.add(ItemEntityTickReference.runtime(e));}
   row.put("after",after);row.put("runtime_after",afterRuntimes);row.put("callbacks",w.env.events);row.put("queries",w.queries);row.put("query_after",w.env.query(c.getAsJsonArray("coverage")));row.put("sections_after",w.env.sections());row.put("tracked_after",w.env.tracked());row.put("scheduled_after",w.env.scheduled());row.put("sound_after",CookingEffectEntitiesReference.random((RandomSource)CookingEffectEntitiesReference.get(w,"soundSeedGenerator")));row.put("effects",w.events);row.put("section_key_changed",changed);out.add(row);
  }
  Files.writeString(Path.of(args[1]),ItemEntityTickReference.JSON.toJson(out));
 }
}
'''
def source():
    base=Tick.source().replace('private World(){super(null','protected World(){super(null').replace('w.sections.getOrCreateSection(SectionPos.asLong(e.blockPosition())).add(e);return e;','return e;')
    parts=[BODY,base];imports=set(re.findall(r'import [^;]+;', '\n'.join(parts)))
    imports.add('import java.util.concurrent.*;')
    return '\n'.join(sorted(imports))+'\n'+'\n'.join(re.sub(r'import [^;]+;','',p) for p in parts)

def inputs():
    def c(name,**kw):
        r=dict(id=name,count=4,position=[15.95,2,.5],velocity=[.2,0,0],ground=False,age=0,delay=10,first=True,tick=1,no_gravity=True,silent=False,blocks=[],coverage=[14,-1,-1,19,4,3],chunks=[dict(x=0,z=0,status='TICKING'),dict(x=1,z=0,status='TICKING')],neighbours=[]);r.update(kw);return r
    neighbours=[c('first',position=[16.25,2,.5],velocity=[0,0,0],age=9,delay=3),c('second',position=[16.4,2,.5],velocity=[0,0,0],age=11,delay=2)]
    rows=[c('cross-empty-section'),c('cross-destination-tie-order',neighbours=neighbours),c('cross-removes-two-neighbours',count=9,neighbours=neighbours),c('cross-patched-max99',count=40,components={'minecraft:max_stack_size':99},neighbours=[c('other',count=40,position=[16.25,2,.5],velocity=[0,0,0],components={'minecraft:max_stack_size':99})])]
    for status in ['HIDDEN','TRACKED']:
        rows.append(c('cross-'+status.lower(),chunks=[dict(x=0,z=0,status='TICKING'),dict(x=1,z=0,status=status)],neighbours=neighbours))
    rows.extend([c('same-section-query',count=9,position=[15.1,2,.5],tick=39,coverage=[13,-1,-1,19,4,3],neighbours=[c('first',position=[15.45,2,.5],velocity=[0,0,0]),c('second',position=[15.6,2,.5],velocity=[0,0,0])]),c('empty-removal',count=0),c('despawn-removal',age=5999,velocity=[0,0,0]),c('cross-splash',coverage=[13,-3,-2,19,4,3],position=[15.95,.2,.5],velocity=[.2,-.4,.1],first=False,blocks=[dict(id='minecraft:water',x=15,y=0,z=0),dict(id='minecraft:water',x=16,y=0,z=0)])])
    return rows
def main():
    WORK.mkdir(parents=True,exist_ok=True);paths,pin=verified_client_classpath();rows=inputs();(WORK/'input.json').write_text(json.dumps(rows));(WORK/'empty.json').write_text('[]');(WORK/'tags.json').write_text(json.dumps(json.loads((ROOT/'reference/item_entity_tick.json').read_text())['fluid_tags']));code=source();(WORK/'ManagedItemTickReference.java').write_text(code);start=time.monotonic()
    p=subprocess.run([str(JAVA),'-Xmx512m','--source','25','--class-path',os.pathsep.join(map(str,paths)),str(WORK/'ManagedItemTickReference.java'),str(WORK/'input.json'),str(WORK/'output.json'),str(WORK/'empty.json'),str(WORK/'initialization.json'),str(WORK/'tags.json')],capture_output=True,text=True,timeout=60)
    (WORK/'java.stdout').write_text(p.stdout);(WORK/'java.stderr').write_text(p.stderr);assert p.returncode==0,p.stderr
    observed=json.loads((WORK/'output.json').read_text());transport=dict(cases=observed,profiles=[]);compact=Tick.compact_observations(transport);result=dict(pin='26.3',inputs=rows,observations=compact,provenance=pin,source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),java_source_sha256=hashlib.sha256(code.encode()).hexdigest(),seconds=round(time.monotonic()-start,4),boundary='Actual ItemEntity.commonTick/tick with actual PersistentEntitySectionManager callbacks, LevelEntityGetterAdapter queries and EntityTickList. Controlled chunks/block/fluid access and I/O sinks only. Absolute scalar section_order is a serial projection; actual section/query/tracking/ticking insertion order is observed independently. Removed Common accessibility is not a Java field and remains a native tombstone projection.')
    (ROOT/'reference/item_entity_tick_managed.json').write_text(json.dumps(result,separators=(',',':'))+'\n');print(json.dumps(dict(status='passed',cases=len(rows))))
if __name__=='__main__':main()
