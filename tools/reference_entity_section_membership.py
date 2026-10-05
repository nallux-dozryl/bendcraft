#!/usr/bin/env python3
"""Observe pinned Java 26.3 entity membership/lifecycle and spatial query order.

The probe uses actual PersistentEntitySectionManager, Callback, EntitySectionStorage,
and LevelEntityGetterAdapter classes. EntityAccess and persistence are controlled
fixtures; Python does not implement the expected manager or query behavior.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

from reference_model_probe import JAVA, verified_client_classpath

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "build/entity-section-membership-reference"
OUTPUT = ROOT / "reference/entity_section_membership.json"

SOURCE = r'''
import com.google.gson.*;
import java.lang.reflect.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.stream.*;
import it.unimi.dsi.fastutil.longs.*;
import net.minecraft.core.*;
import net.minecraft.util.*;
import net.minecraft.world.entity.Entity.RemovalReason;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.entity.*;
import net.minecraft.world.phys.*;

class EntitySectionMembershipReference {
 static final AABB QUERY = new AABB(-40,-40,-40,80,80,80);
 static final Gson G = new GsonBuilder().serializeNulls().create();
 static Map<String,Object> row(Object... a) {
  var r=new LinkedHashMap<String,Object>();for(int i=0;i<a.length;i+=2)r.put((String)a[i],a[i+1]);return r;
 }
 static Object field(Object o,String name)throws Exception {
  var f=o.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(o);
 }
 static List<Long> bits(long key){return List.of(key>>>32,key&0xffffffffL);}
 static List<Integer> coords(long key){return List.of(SectionPos.x(key),SectionPos.y(key),SectionPos.z(key));}
 static class E implements EntityAccess {
  final int id; final UUID uuid; final boolean always; final Env env;
  double x,y,z; boolean removed=false; EntityInLevelCallback callback=EntityInLevelCallback.NULL;
  E(Env env,int id,double x,double y,double z,boolean always,UUID uuid){
   this.env=env;this.id=id;this.x=x;this.y=y;this.z=z;this.always=always;this.uuid=uuid;
  }
  public int getId(){return id;}
  public UUID getUUID(){return uuid;}
  public BlockPos blockPosition(){return BlockPos.containing(x,y,z);}
  public AABB getBoundingBox(){return new AABB(x-.125,y,z-.125,x+.125,y+.25,z+.125);}
  public void setLevelCallback(EntityInLevelCallback c){callback=c;env.event(c==EntityInLevelCallback.NULL?"callback_cleared":"callback_installed",this);}
  public Stream<E> getSelfAndPassengers(){return Stream.of(this);}
  public Stream<E> getPassengersAndSelf(){return Stream.of(this);}
  public void setRemoved(RemovalReason reason){removed=true;callback.onRemove(reason);}
  public boolean isRemoved(){return removed;}
  public boolean shouldBeSaved(){return true;}
  public boolean isAlwaysTicking(){return always;}
  public String toString(){return "ReferenceEntity["+id+"]";}
  void move(double x,double y,double z){this.x=x;this.y=y;this.z=z;callback.onMove();}
 }
 static class Env implements LevelCallback<E>,EntityPersistentStorage<E> {
  final PersistentEntitySectionManager<E> manager=new PersistentEntitySectionManager<>(E.class,this,this);
  final List<E> entities=new ArrayList<>(); final List<Object> events=new ArrayList<>();final List<Object> steps=new ArrayList<>();
  E entity(int id,double x,double y,double z,boolean always){return entity(id,x,y,z,always,new UUID(0,id));}
  E entity(int id,double x,double y,double z,boolean always,UUID uuid){var e=new E(this,id,x,y,z,always,uuid);entities.add(e);return e;}
  public CompletableFuture<ChunkEntities<E>> loadEntities(ChunkPos p){return CompletableFuture.completedFuture(new ChunkEntities<E>(p,List.of()));}
  public void storeEntities(ChunkEntities<E> c){throw new AssertionError("Save is outside this probe");}
  public void flush(boolean sync){}
  public void onCreated(E e){event("created",e);}public void onDestroyed(E e){event("destroyed",e);}
  public void onTickingStart(E e){event("ticking_start",e);}public void onTickingEnd(E e){event("ticking_end",e);}
  public void onTrackingStart(E e){event("tracking_start",e);}public void onTrackingEnd(E e){event("tracking_end",e);}
  public void onSectionChange(E e){event("section_change",e);}
  List<Integer> globals(){var ids=new ArrayList<Integer>();for(var e:manager.getEntityGetter().getAll())ids.add(e.id);return ids;}
  List<Integer> query(AABB q){var ids=new ArrayList<Integer>();manager.getEntityGetter().get(q,e->ids.add(e.id));return ids;}
  Object key(E e)throws Exception{return e.callback==EntityInLevelCallback.NULL?null:bits((long)field(e.callback,"currentSectionKey"));}
  @SuppressWarnings("unchecked") EntitySectionStorage<E> storage()throws Exception{return (EntitySectionStorage<E>)field(manager,"sectionStorage");}
  List<Object> sections()throws Exception {
   @SuppressWarnings("unchecked") var sections=(Long2ObjectMap<EntitySection<E>>)field(storage(),"sections");
   var keys=sections.keySet().toLongArray();Arrays.sort(keys);var result=new ArrayList<Object>();
   for(long key:keys){var s=sections.get(key);result.add(row("key",bits(key),"coordinates",coords(key),"status",s.getStatus().name(),"members",s.getEntities().map(e->e.id).toList()));}return result;
  }
  Object state()throws Exception {
   var callbacks=new ArrayList<Object>();var known=new ArrayList<Integer>();
   for(var e:entities){callbacks.add(row("id",e.id,"key",key(e)));if(manager.isLoaded(e.uuid))known.add(e.id);}
   return row("sections",sections(),"query_ids",query(QUERY),"global_ids",globals(),"known_ids",known,"callback_keys",callbacks,"visible_count",manager.count());
  }
  void event(String name,E e){try{events.add(row("event",name,"id",e.id,"registered",manager.isLoaded(e.uuid),"callback_key",key(e),"sections",sections(),"query_ids",query(QUERY),"global_ids",globals()));}catch(Exception ex){throw new RuntimeException(ex);}}
  void status(int x,int z,Visibility v){manager.updateChunkStatus(new ChunkPos(x,z),v);}
  void resetEvents(){events.clear();}
  void step(String action,Object... details)throws Exception {var r=row("action",action,"events",new ArrayList<>(events),"state",state());for(int i=0;i<details.length;i+=2)r.put((String)details[i],details[i+1]);steps.add(r);events.clear();}
  Object result(String id,String category,Object... details){var r=row("id",id,"category",category,"steps",steps);for(int i=0;i<details.length;i+=2)r.put((String)details[i],details[i+1]);return r;}
 }
 static Object registration(Visibility v,boolean always)throws Exception {
  var env=new Env();env.status(0,0,v);env.resetEvents();var e=env.entity(1,1,1,1,always);
  boolean ok=env.manager.addNewEntity(e);env.step("register","accepted",ok);
  var dup=env.entity(2,17,1,1,always,e.uuid);boolean accepted=env.manager.addNewEntity(dup);env.step("register_duplicate_uuid","accepted",accepted);
  return env.result("register-"+v+"-"+always,"registration","visibility",v.name(),"always_ticking",always);
 }
 static Object move(Visibility from,Visibility to,boolean always,boolean occupied)throws Exception {
  var env=new Env();env.status(0,0,from);env.status(1,0,to);
  var a=env.entity(1,1,1,1,always);env.manager.addNewEntity(a);
  if(occupied){env.manager.addNewEntity(env.entity(2,2,1,1,false));env.manager.addNewEntity(env.entity(3,17,1,1,false));env.manager.addNewEntity(env.entity(4,18,1,1,false));}
  env.step("registered");a.move(19,1,1);env.step("move","from",List.of(1,1,1),"to",List.of(19,1,1));
  a.move(3,1,1);env.step("move_back","from",List.of(19,1,1),"to",List.of(3,1,1));
  return env.result("move-"+from+"-"+to+"-"+always+"-"+occupied,"move","source_visibility",from.name(),"destination_visibility",to.name(),"always_ticking",always,"occupied_sections",occupied);
 }
 static Object sameKey(String label,double x,double y,double z)throws Exception {
  var env=new Env();env.status(0,0,Visibility.TICKING);var a=env.entity(1,1,1,1,false);env.manager.addNewEntity(a);env.manager.addNewEntity(env.entity(2,2,1,1,false));env.step("registered");
  a.move(x,y,z);env.step("move","to",List.of(x,y,z));return env.result(label,"same_packed_key");
 }
 static Object chunkStatus(Visibility from,Visibility to)throws Exception {
  var env=new Env();env.status(0,0,from);env.manager.addNewEntity(env.entity(1,1,-15,1,false));env.manager.addNewEntity(env.entity(2,2,1,1,false));env.manager.addNewEntity(env.entity(3,3,1,1,false));env.manager.addNewEntity(env.entity(4,4,17,1,false));env.manager.addNewEntity(env.entity(5,5,1,1,true));env.step("registered");
  env.status(0,0,to);env.step("change_chunk_visibility");return env.result("visibility-"+from+"-"+to,"chunk_visibility","source_visibility",from.name(),"destination_visibility",to.name());
 }
 static Object removal(Visibility visibility,boolean always,RemovalReason reason)throws Exception {
  var env=new Env();env.status(0,0,visibility);var a=env.entity(1,1,1,1,always);env.manager.addNewEntity(a);env.step("registered");a.setRemoved(reason);env.step("remove");
  a.move(17,1,1);env.step("move_after_removed");var replacement=env.entity(2,17,1,1,always,a.uuid);boolean accepted=env.manager.addNewEntity(replacement);env.step("reregister_uuid","accepted",accepted);
  return env.result("remove-"+visibility+"-"+always+"-"+reason,"removal","visibility",visibility.name(),"always_ticking",always,"reason",reason.name(),"should_destroy",reason.shouldDestroy(),"should_save",reason.shouldSave());
 }
 static Object ordering()throws Exception {
  var env=new Env();int[][] sections={{1,0,0},{0,-1,0},{0,0,-1},{-1,0,0},{0,0,0},{0,1,0},{0,0,1},{0,-2,-1},{0,1,-1},{-1,-1,-1},{1,-1,-1}};
  for(var s:sections)env.status(s[0],s[2],Visibility.TRACKED);
  int id=1;for(var s:sections){env.manager.addNewEntity(env.entity(id++,s[0]*16+1,s[1]*16+1,s[2]*16+1,false));}env.manager.addNewEntity(env.entity(id++,2,1,1,false));env.step("registered");
  var a=env.entities.get(0);a.move(3,1,1);env.step("move_to_existing_section");
  var abort=new ArrayList<Integer>();env.storage().getEntities(QUERY,e->{abort.add(e.id);return abort.size()==3?Continuation.ABORT:Continuation.CONTINUE;});
  env.step("query_abort_after_three","abort_query_ids",abort);
  return env.result("signed-section-and-insertion-order","query_order","query_box",List.of(-40,-40,-40,80,80,80));
 }
 static Object loadedRegistration(boolean legacy)throws Exception {
  var env=new Env();env.status(0,0,Visibility.TICKING);var a=env.entity(1,1,1,1,false);
  if(legacy)env.manager.addLegacyChunkEntities(Stream.of(a));else env.manager.addWorldGenChunkEntities(Stream.of(a));env.step("register");return env.result(legacy?"legacy-loaded-registration":"worldgen-registration","registration_origin");
 }
 public static void main(String[] args)throws Exception {
  var cases=new ArrayList<Object>();for(var v:Visibility.values())for(boolean a:new boolean[]{false,true})cases.add(registration(v,a));
  for(var f:Visibility.values())for(var t:Visibility.values())for(boolean a:new boolean[]{false,true})cases.add(move(f,t,a,false));
  cases.add(move(Visibility.TICKING,Visibility.TICKING,false,true));
  cases.add(sameKey("same-section-no-reinsertion",15.5,15.5,15.5));
  cases.add(sameKey("packed-x-alias-no-reinsertion",67108865,1,1));
  cases.add(sameKey("packed-y-alias-no-reinsertion",1,16777217,1));
  cases.add(sameKey("packed-z-alias-no-reinsertion",1,1,67108865));
  for(var f:Visibility.values())for(var t:Visibility.values())cases.add(chunkStatus(f,t));
  for(var v:Visibility.values())for(boolean a:new boolean[]{false,true})for(var r:RemovalReason.values())cases.add(removal(v,a,r));
  cases.add(ordering());cases.add(loadedRegistration(true));cases.add(loadedRegistration(false));
  var enums=new ArrayList<Object>();for(var v:Visibility.values())enums.add(row("name",v.name(),"accessible",v.isAccessible(),"ticking",v.isTicking()));
  Files.writeString(Path.of(args[0]),G.toJson(row("cases",cases,"visibility_values",enums,"default_query_box",List.of(-40,-40,-40,80,80,80))));
 }
}
'''

CLASSES = [
    "net.minecraft.world.level.entity.PersistentEntitySectionManager",
    "net.minecraft.world.level.entity.PersistentEntitySectionManager$Callback",
    "net.minecraft.world.level.entity.EntitySectionStorage",
    "net.minecraft.world.level.entity.EntitySection",
    "net.minecraft.world.level.entity.EntityLookup",
    "net.minecraft.world.level.entity.LevelEntityGetterAdapter",
    "net.minecraft.world.level.entity.Visibility",
    "net.minecraft.util.ClassInstanceMultiMap",
    "net.minecraft.world.entity.Entity$RemovalReason",
]


def verify_observations(result: dict) -> None:
    """Cross-check dynamic observations against an independent bytecode audit."""
    cases = {case["id"]: case for case in result["cases"]}
    assert len(cases) == 71, "Missing or duplicate scenario"
    transitions = {
        ("HIDDEN", "HIDDEN"): [],
        ("HIDDEN", "TRACKED"): ["tracking_start", "section_change"],
        ("HIDDEN", "TICKING"): ["tracking_start", "ticking_start", "section_change"],
        ("TRACKED", "HIDDEN"): ["tracking_end"],
        ("TRACKED", "TRACKED"): ["section_change"],
        ("TRACKED", "TICKING"): ["ticking_start", "section_change"],
        ("TICKING", "HIDDEN"): ["tracking_end", "ticking_end"],
        ("TICKING", "TRACKED"): ["ticking_end", "section_change"],
        ("TICKING", "TICKING"): ["section_change"],
    }
    for case in result["cases"]:
        if case["category"] == "move":
            expected = ["section_change"] if case["always_ticking"] else transitions[
                case["source_visibility"], case["destination_visibility"]]
            assert [event["event"] for event in case["steps"][1]["events"]] == expected, case["id"]
            destination = next(section for section in case["steps"][1]["state"]["sections"]
                               if section["coordinates"] == [1, 0, 0])
            assert destination["members"][-1] == 1, case["id"]
        elif case["category"] == "same_packed_key":
            before, after = case["steps"]
            assert after["events"] == [] and before["state"]["sections"] == after["state"]["sections"], case["id"]
        elif case["category"] == "registration":
            first, duplicate = case["steps"]
            assert first["accepted"] and not duplicate["accepted"], case["id"]
            assert duplicate["events"] == [] and duplicate["state"]["sections"] == first["state"]["sections"], case["id"]
        elif case["category"] == "removal":
            removed = case["steps"][1]
            expected = []
            if case["always_ticking"] or case["visibility"] == "TICKING":
                expected.append("ticking_end")
            if case["always_ticking"] or case["visibility"] != "HIDDEN":
                expected.append("tracking_end")
            if case["should_destroy"]:
                expected.append("destroyed")
            expected.append("callback_cleared")
            assert [event["event"] for event in removed["events"]] == expected, case["id"]
            assert removed["state"]["sections"] == [] and removed["state"]["known_ids"] == [], case["id"]
            assert case["steps"][2]["events"] == [] and case["steps"][3]["accepted"], case["id"]
    order = cases["signed-section-and-insertion-order"]["steps"]
    assert order[0]["state"]["query_ids"] == [4, 10, 5, 12, 6, 2, 7, 3, 9, 8, 1, 11]
    assert order[1]["state"]["query_ids"] == [4, 10, 5, 12, 1, 6, 2, 7, 3, 9, 8, 11]
    assert order[2]["abort_query_ids"] == [4, 10, 5]
    assert [event["event"] for event in cases["legacy-loaded-registration"]["steps"][0]["events"]] == ["callback_installed", "tracking_start", "ticking_start"]
    assert [event["event"] for event in cases["worldgen-registration"]["steps"][0]["events"]] == ["callback_installed", "created", "tracking_start", "ticking_start"]
    chunk = cases["visibility-TICKING-HIDDEN"]["steps"][1]
    assert [(event["event"], event["id"]) for event in chunk["events"]] == [
        ("ticking_end", 2), ("ticking_end", 3), ("tracking_end", 2), ("tracking_end", 3),
        ("ticking_end", 4), ("tracking_end", 4), ("ticking_end", 1), ("tracking_end", 1)]


def main() -> None:
    WORK.mkdir(parents=True, exist_ok=True)
    paths, pin = verified_client_classpath()
    source = WORK / "EntitySectionMembershipReference.java"
    source.write_text(SOURCE)
    start = time.monotonic()
    java = subprocess.run(
        [str(JAVA), "-Xmx256m", "--source", "25", "--class-path",
         os.pathsep.join(map(str, paths)), str(source), str(WORK / "output.json")],
        capture_output=True, text=True, timeout=45,
    )
    (WORK / "java.stdout").write_text(java.stdout)
    (WORK / "java.stderr").write_text(java.stderr)
    if java.returncode:
        raise RuntimeError(java.stderr)
    bytecode = subprocess.run(
        [str(JAVA.parent / "javap"), "-c", "-p", "-classpath",
         os.pathsep.join(map(str, paths)), *CLASSES],
        capture_output=True, text=True, check=True, timeout=20,
    )
    (WORK / "receivers.javap").write_text(bytecode.stdout)
    result = json.loads((WORK / "output.json").read_text())
    verify_observations(result)
    result.update(
        pin="26.3", provenance=pin,
        source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        java_source_sha256=hashlib.sha256(SOURCE.encode()).hexdigest(),
        receiver_bytecode_sha256=hashlib.sha256(bytecode.stdout.encode()).hexdigest(),
        verification="Runtime scenarios cross-checked against an independent pinned-bytecode audit",
        seconds=round(time.monotonic() - start, 4),
        boundary=("Actual pinned Java manager registration, callback movement/removal, "
                  "chunk visibility updates, section membership, visible lookup, and AABB "
                  "query order. Controlled EntityAccess position/AABB and no-op in-memory "
                  "EntityPersistentStorage; no real world, item physics, persistence, "
                  "chunk streaming, networking, or renderer observation."),
    )
    OUTPUT.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"status": "passed", "cases": len(result["cases"]),
                      "steps": sum(len(c["steps"]) for c in result["cases"])}))


if __name__ == "__main__":
    main()
