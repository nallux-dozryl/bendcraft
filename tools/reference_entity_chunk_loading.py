#!/usr/bin/env python3
"""Observe pinned 26.3 chunk status, tickets, and asynchronous entity loading.

Java owns the ticket store, simulation distance graph, and entity manager. The
controlled storage fixture decides when its real CompletableFuture completes;
Python only orchestrates the probe and checks independent expected boundaries.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import zipfile

from reference_model_probe import CLIENT, JAVA, verified_client_classpath

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "reference/entity_chunk_loading.json"
CLASSES = [
    "net.minecraft.server.level.ChunkLevel",
    "net.minecraft.server.level.FullChunkStatus",
    "net.minecraft.world.level.entity.Visibility",
    "net.minecraft.world.level.entity.PersistentEntitySectionManager",
    "net.minecraft.world.level.entity.PersistentEntitySectionManager$ChunkLoadStatus",
    "net.minecraft.server.level.Ticket",
    "net.minecraft.server.level.TicketType",
    "net.minecraft.world.level.TicketStorage",
    "net.minecraft.server.level.SimulationChunkTracker",
    "net.minecraft.server.level.LoadingChunkTracker",
    "net.minecraft.server.level.ChunkTracker",
    "net.minecraft.server.level.DistanceManager",
    "net.minecraft.server.level.DistanceManager$PlayerTicketTracker",
    "net.minecraft.server.level.ChunkHolder",
    "net.minecraft.server.level.ChunkMap",
    "net.minecraft.server.level.ServerChunkCache",
    "net.minecraft.server.level.ServerLevel",
]

SOURCE = r'''
import com.google.gson.*;
import java.lang.reflect.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.stream.*;
import it.unimi.dsi.fastutil.longs.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;
import net.minecraft.server.level.*;
import net.minecraft.world.entity.Entity.RemovalReason;
import net.minecraft.world.level.*;
import net.minecraft.world.level.entity.*;
import net.minecraft.world.phys.*;

class EntityChunkLoadingReference {
 static final Gson G=new GsonBuilder().serializeNulls().create();
 static final ChunkPos POS=new ChunkPos(-2,3);
 static Map<String,Object> row(Object...a){var r=new LinkedHashMap<String,Object>();for(int i=0;i<a.length;i+=2)r.put((String)a[i],a[i+1]);return r;}
 static Object field(Object o,String name)throws Exception{var f=o.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(o);}
 static void set(Object o,String name,Object value)throws Exception{var f=o.getClass().getDeclaredField(name);f.setAccessible(true);f.set(o,value);}
 static List<Long> bits(long key){return List.of(key>>>32,key&0xffffffffL);}
 static class E implements EntityAccess {
  final int id;final boolean always;final Env env;boolean removed=false;
  EntityInLevelCallback callback=EntityInLevelCallback.NULL;
  E(Env env,int id,boolean always){this.env=env;this.id=id;this.always=always;}
  public int getId(){return id;}public UUID getUUID(){return new UUID(0,id);}
  public BlockPos blockPosition(){return new BlockPos(POS.x()*16+id%8,1,POS.z()*16+1);}
  public AABB getBoundingBox(){var p=blockPosition();return new AABB(p.getX(),1,p.getZ(),p.getX()+.25,1.25,p.getZ()+.25);}
  public void setLevelCallback(EntityInLevelCallback c){callback=c;env.event(c==EntityInLevelCallback.NULL?"callback_cleared":"callback_installed",this);}
  public Stream<E>getSelfAndPassengers(){return Stream.of(this);}public Stream<E>getPassengersAndSelf(){return Stream.of(this);}
  public void setRemoved(RemovalReason r){removed=true;env.event("set_removed:"+r.name(),this);callback.onRemove(r);}
  public boolean isRemoved(){return removed;}public boolean shouldBeSaved(){return true;}public boolean isAlwaysTicking(){return always;}
 }
 static class Env implements LevelCallback<E>,EntityPersistentStorage<E> {
  final PersistentEntitySectionManager<E>manager=new PersistentEntitySectionManager<>(E.class,this,this);
  final List<CompletableFuture<ChunkEntities<E>>>requests=new ArrayList<>();
  final List<Object>events=new ArrayList<>(),steps=new ArrayList<>();final List<E>entities=new ArrayList<>();
  public CompletableFuture<ChunkEntities<E>>loadEntities(ChunkPos p){var f=new CompletableFuture<ChunkEntities<E>>();requests.add(f);events.add(row("event","load_request","position",List.of(p.x(),p.z()),"load_status",status()));return f;}
  public void storeEntities(ChunkEntities<E>c){events.add(row("event","store_entities","position",List.of(c.getPos().x(),c.getPos().z()),"ids",c.getEntities().map(e->e.id).toList(),"load_status",status()));}
  public void flush(boolean sync){}public void close(){}
  public void onCreated(E e){event("created",e);}public void onDestroyed(E e){event("destroyed",e);}
  public void onTickingStart(E e){event("ticking_start",e);}public void onTickingEnd(E e){event("ticking_end",e);}
  public void onTrackingStart(E e){event("tracking_start",e);}public void onTrackingEnd(E e){event("tracking_end",e);}
  public void onSectionChange(E e){event("section_change",e);}
  String status(){try{@SuppressWarnings("unchecked")var map=(Long2ObjectMap<Object>)field(manager,"chunkLoadStatuses");return map.get(POS.pack()).toString();}catch(Exception ex){throw new RuntimeException(ex);}}
  String visibility(){try{@SuppressWarnings("unchecked")var map=(Long2ObjectMap<Visibility>)field(manager,"chunkVisibility");return map.get(POS.pack()).name();}catch(Exception ex){throw new RuntimeException(ex);}}
  void event(String event,E e){events.add(row("event",event,"id",e.id,"load_status",status(),"visibility",visibility(),"known",manager.isLoaded(e.getUUID())));}
  E entity(int id,boolean always){var e=new E(this,id,always);entities.add(e);return e;}
  Object state()throws Exception {
   var globals=new ArrayList<Integer>();for(var e:manager.getEntityGetter().getAll())globals.add(e.id);
   var members=new ArrayList<Object>();for(var e:entities)members.add(row("id",e.id,"known",manager.isLoaded(e.getUUID()),"removed",e.removed,"callback_installed",e.callback!=EntityInLevelCallback.NULL));
   return row("load_status",status(),"visibility",visibility(),"entities_loaded",manager.areEntitiesLoaded(POS.pack()),"can_position_tick",manager.canPositionTick(POS),"requests",requests.size(),"inbox",((Queue<?>)field(manager,"loadingInbox")).size(),"queued_unload",((LongSet)field(manager,"chunksToUnload")).contains(POS.pack()),"global_ids",globals,"members",members);
  }
  void step(String action)throws Exception{steps.add(row("action",action,"events",new ArrayList<>(events),"state",state()));events.clear();}
  void status(FullChunkStatus s){manager.updateChunkStatus(POS,s);}
  void complete(E...es){requests.getLast().complete(new ChunkEntities<E>(POS,List.of(es)));}
  Object result(String id){return row("id",id,"position",List.of(POS.x(),POS.z()),"packed_key",bits(POS.pack()),"steps",steps);}
 }
 static Object success()throws Exception {
  var e=new Env();e.step("fresh");e.status(FullChunkStatus.FULL);e.step("full_requests_storage");e.status(FullChunkStatus.BLOCK_TICKING);e.step("repeat_accessible_does_not_request_again");
  e.complete(e.entity(11,false),e.entity(12,false));e.step("future_success_only_enqueues");e.manager.processPendingLoads();e.step("drain_success_registers_then_marks_loaded");
  e.status(FullChunkStatus.ENTITY_TICKING);e.step("entity_ticking_after_loaded");e.status(FullChunkStatus.INACCESSIBLE);e.step("hidden_ends_callbacks_before_unload");e.manager.tick();e.step("tick_stores_and_unloads_loaded_entities");
  e.status(FullChunkStatus.FULL);e.step("reactivation_requests_fresh_storage");return e.result("success-loaded-unload-reload");
 }
 static Object pendingHidden()throws Exception {
  var e=new Env();e.status(FullChunkStatus.ENTITY_TICKING);e.step("ticking_but_storage_pending");e.status(FullChunkStatus.INACCESSIBLE);e.step("hide_before_storage_completion");e.manager.tick();e.step("pending_unload_is_deferred");
  e.complete(e.entity(21,false),e.entity(22,true));e.step("hidden_future_success_only_enqueues");e.manager.tick();e.step("tick_drains_then_unloads_hidden_completion");return e.result("hidden-pending-completion");
 }
 static Object pendingReactivated()throws Exception {
  var e=new Env();e.status(FullChunkStatus.FULL);e.step("first_request");e.status(FullChunkStatus.INACCESSIBLE);e.step("hidden_pending");e.status(FullChunkStatus.ENTITY_TICKING);e.step("reactivated_pending_keeps_same_request");
  e.complete(e.entity(31,false));e.step("future_success");e.manager.tick();e.step("tick_registers_at_current_ticking_visibility");return e.result("reactivate-existing-pending-request");
 }
 static Object failed()throws Exception {
  var e=new Env();e.status(FullChunkStatus.ENTITY_TICKING);e.step("request_pending");e.requests.getLast().completeExceptionally(new IllegalStateException("fixture-storage-failure"));e.step("exceptional_completion_does_not_enqueue");
  e.manager.tick();e.step("tick_does_not_manufacture_loaded_or_retry");e.status(FullChunkStatus.FULL);e.step("repeat_accessible_does_not_retry_pending_failure");e.status(FullChunkStatus.INACCESSIBLE);e.manager.tick();e.step("hidden_failed_pending_still_defers_unload");return e.result("failed-storage-remains-pending");
 }
 static Object visibleBeforeLoaded()throws Exception {
  var e=new Env();var a=e.entity(41,false);e.manager.addNewEntity(a);e.step("new_entity_in_hidden_fresh_chunk");e.status(FullChunkStatus.ENTITY_TICKING);e.step("in_memory_entity_activates_while_storage_pending");
  e.complete();e.step("empty_storage_success_only_enqueues");e.manager.processPendingLoads();e.step("empty_success_is_loaded_without_new_callbacks");return e.result("existing-entity-ticks-before-file-loaded");
 }
 static Object ticketState(Ticket t)throws Exception{return row("level",t.getTicketLevel(),"ticks_left",String.valueOf(field(t,"ticksLeft")),"timed_out",t.isTimedOut());}
 static Object tickets()throws Exception {
  var s=new TicketStorage();long key=POS.pack();var events=new ArrayList<Object>();s.setLoadingChunkUpdatedListener((k,l,d)->events.add(row("kind","loading","key",bits(k),"level",l,"decrease",d)));s.setSimulationChunkUpdatedListener((k,l,d)->events.add(row("kind","simulation","key",bits(k),"level",l,"decrease",d)));
  var observations=new ArrayList<Object>();
  var loading=new Ticket(TicketType.PLAYER_LOADING,33);boolean added=s.addTicket(key,loading);observations.add(row("action","add_loading33","added",added,"loading_level",s.getTicketLevelAt(key,false),"simulation_level",s.getTicketLevelAt(key,true),"count",s.getTickets(key).size(),"events",new ArrayList<>(events)));events.clear();
  var sim=new Ticket(TicketType.PLAYER_SIMULATION,31);added=s.addTicket(key,sim);observations.add(row("action","add_simulation31","added",added,"loading_level",s.getTicketLevelAt(key,false),"simulation_level",s.getTicketLevelAt(key,true),"count",s.getTickets(key).size(),"events",new ArrayList<>(events)));events.clear();
  added=s.addTicket(key,new Ticket(TicketType.PLAYER_SIMULATION,31));observations.add(row("action","duplicate_type_and_level","added",added,"count",s.getTickets(key).size(),"same_object",s.getTickets(key).contains(sim),"events",new ArrayList<>(events)));events.clear();
  boolean removed=s.removeTicket(key,new Ticket(TicketType.PLAYER_SIMULATION,31));observations.add(row("action","remove_equal_type_and_level","removed",removed,"loading_level",s.getTicketLevelAt(key,false),"simulation_level",s.getTicketLevelAt(key,true),"count",s.getTickets(key).size(),"events",new ArrayList<>(events)));events.clear();
  var customA=new TicketType(7,6);var customB=new TicketType(7,6);s.addTicket(key,new Ticket(customA,30));s.addTicket(key,new Ticket(customB,30));observations.add(row("action","record_equal_type_distinct_reference","record_types_equal",customA.equals(customB),"count",s.getTickets(key).size(),"loading_level",s.getTicketLevelAt(key,false),"simulation_level",s.getTicketLevelAt(key,true),"events",new ArrayList<>(events)));events.clear();
  added=s.addTicket(key,new Ticket(TicketType.FORCED,29));observations.add(row("action","add_forced_lowers_both","added",added,"events",new ArrayList<>(events)));events.clear();removed=s.removeTicket(key,new Ticket(TicketType.FORCED,29));observations.add(row("action","direct_remove_notifies_simulation_then_loading","removed",removed,"events",new ArrayList<>(events)));events.clear();
  var timed=new Ticket(TicketType.UNKNOWN,34);var ttl=new TicketStorage();var sequence=new ArrayList<Object>();ttl.addTicket(key,timed);sequence.add(row("action","add", "ticket",ticketState(timed),"count",ttl.getTickets(key).size()));ttl.purgeStaleTickets(null);sequence.add(row("action","purge1","ticket",ticketState(timed),"count",ttl.getTickets(key).size()));
  boolean duplicate=ttl.addTicket(key,new Ticket(TicketType.UNKNOWN,34));sequence.add(row("action","duplicate_resets_original_timer","added",duplicate,"same_object",ttl.getTickets(key).getFirst()==timed,"ticket",ticketState(timed),"count",ttl.getTickets(key).size()));ttl.purgeStaleTickets(null);sequence.add(row("action","purge_after_reset1","ticket",ticketState(timed),"count",ttl.getTickets(key).size()));ttl.purgeStaleTickets(null);sequence.add(row("action","purge_after_reset2","ticket",ticketState(timed),"count",ttl.getTickets(key).size()));
  var timerCases=new ArrayList<Object>();for(long timeout:new long[]{0,1,20,40,300,Long.MIN_VALUE,Long.MAX_VALUE}){var t=new Ticket(new TicketType(timeout,18),31);var before=ticketState(t);t.decreaseTicksLeft();timerCases.add(row("timeout",Long.toString(timeout),"before",before,"after_one_decrement",ticketState(t)));}
  var purge=new TicketStorage();var purgeEvents=new ArrayList<Object>();purge.setLoadingChunkUpdatedListener((k,l,d)->purgeEvents.add(row("kind","loading","level",l,"decrease",d)));purge.setSimulationChunkUpdatedListener((k,l,d)->purgeEvents.add(row("kind","simulation","level",l,"decrease",d)));purge.addTicket(key,new Ticket(new TicketType(0,6),31));purge.addTicket(key,new Ticket(new TicketType(1,22),34));purgeEvents.clear();purge.purgeStaleTickets(null);var firstPurge=new ArrayList<>(purgeEvents);purgeEvents.clear();purge.purgeStaleTickets(null);
  return row("storage_steps",observations,"unknown_timeout_steps",sequence,"signed_timer_boundaries",timerCases,"purge_listener_order",row("first_purge_events",firstPurge,"second_purge_events",purgeEvents,"remaining_count",purge.getTickets(key).size(),"loading_level",purge.getTicketLevelAt(key,false),"simulation_level",purge.getTicketLevelAt(key,true)));
 }
 static Object graphState(SimulationChunkTracker tracker){var r=new ArrayList<Object>();for(int z=-3;z<=3;z++)for(int x=-3;x<=7;x++)r.add(row("position",List.of(x,z),"level",tracker.getLevel(new ChunkPos(x,z))));return r;}
 static Object graph(){var s=new TicketStorage();var t=new SimulationChunkTracker(s);var steps=new ArrayList<Object>();steps.add(row("action","empty","levels",graphState(t)));
  s.addTicket(new Ticket(TicketType.PLAYER_LOADING,20),new ChunkPos(0,0));t.runAllUpdates();steps.add(row("action","loading_only_has_no_simulation_source","levels",graphState(t)));
  s.addTicket(new Ticket(TicketType.PLAYER_SIMULATION,31),new ChunkPos(0,0));t.runAllUpdates();steps.add(row("action","simulation31_at_origin","levels",graphState(t)));
  s.addTicket(new Ticket(TicketType.FORCED,30),new ChunkPos(4,0));t.runAllUpdates();steps.add(row("action","competing_forced30_at_4_0","levels",graphState(t)));
  s.removeTicket(new Ticket(TicketType.PLAYER_SIMULATION,31),new ChunkPos(0,0));t.runAllUpdates();steps.add(row("action","remove_origin_source_recomputes","levels",graphState(t)));
  s.removeTicket(new Ticket(TicketType.FORCED,30),new ChunkPos(4,0));t.runAllUpdates();steps.add(row("action","remove_all_simulation_sources","levels",graphState(t)));return steps;
 }
 public static void main(String[]args)throws Exception {
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();
  var levels=new ArrayList<Object>();for(int l:new int[]{Integer.MIN_VALUE,-1,0,30,31,32,33,34,35,36,37,43,44,45,Integer.MAX_VALUE}){var status=ChunkLevel.fullStatus(l);var v=Visibility.fromFullChunkStatus(status);var generation=ChunkLevel.generationStatus(l);levels.add(row("level",l,"status",status.name(),"visibility",v.name(),"accessible",v.isAccessible(),"ticking",v.isTicking(),"entity_level",ChunkLevel.isEntityTicking(l),"block_level",ChunkLevel.isBlockTicking(l),"loaded_level",ChunkLevel.isLoaded(l),"generation_status",generation==null?null:generation.getName()));}
  var types=new ArrayList<Object>();for(var name:new String[]{"PLAYER_SPAWN","SPAWN_SEARCH","DRAGON","PLAYER_LOADING","PLAYER_SIMULATION","FORCED","PORTAL","ENDER_PEARL","UNKNOWN"}){var ty=(TicketType)TicketType.class.getField(name).get(null);types.add(row("name",name,"timeout",Long.toString(ty.timeout()),"flags",ty.flags(),"persist",ty.persist(),"loads",ty.doesLoad(),"simulates",ty.doesSimulate(),"keeps_dimension_active",ty.shouldKeepDimensionActive(),"can_expire_unloaded",ty.canExpireIfUnloaded()));}
  var result=row("version",SharedConstants.getCurrentVersion().id(),"full_radius",ChunkLevel.RADIUS_AROUND_FULL_CHUNK,"max_loading_level",ChunkLevel.MAX_LEVEL,"level_cases",levels,"ticket_types",types,"tickets",tickets(),"simulation_graph",graph(),"entity_load_cases",List.of(success(),pendingHidden(),pendingReactivated(),failed(),visibleBeforeLoaded()));
  Files.writeString(Path.of(args[0]),G.toJson(result));
 }
}
'''


def verify_observations(result: dict) -> None:
    assert result["version"] == "26.3"
    assert result["full_radius"] == 11 and result["max_loading_level"] == 44
    levels = {r["level"]: r for r in result["level_cases"]}
    for level, status, visibility in [
        (31, "ENTITY_TICKING", "TICKING"),
        (32, "BLOCK_TICKING", "TRACKED"),
        (33, "FULL", "TRACKED"),
        (34, "INACCESSIBLE", "HIDDEN"),
        (44, "INACCESSIBLE", "HIDDEN"),
        (45, "INACCESSIBLE", "HIDDEN"),
    ]:
        assert (levels[level]["status"], levels[level]["visibility"]) == (status, visibility)
    assert levels[44]["loaded_level"] and not levels[45]["loaded_level"]
    for stage, sources in zip(result["simulation_graph"], [[], [], [(0, 0, 31)], [(0, 0, 31), (4, 0, 30)], [(4, 0, 30)], []]):
        for r in stage["levels"]:
            x, z = r["position"]
            expected = min([33] + [level + max(abs(x - sx), abs(z - sz)) for sx, sz, level in sources])
            assert r["level"] == expected, (stage["action"], r, expected)
    storage = result["tickets"]["storage_steps"]
    assert [(r.get("loading_level"), r.get("simulation_level"), r["count"]) for r in storage[:2]] == [(33, 45, 1), (33, 31, 2)]
    assert not storage[2]["added"] and storage[2]["same_object"] and storage[2]["events"] == []
    assert storage[3]["removed"] and storage[3]["simulation_level"] == 45
    assert storage[4]["record_types_equal"] and storage[4]["count"] == 3
    assert [e["kind"] for e in storage[5]["events"]] == ["simulation", "loading"]
    assert [e["kind"] for e in storage[6]["events"]] == ["simulation", "loading"]
    purge = result["tickets"]["purge_listener_order"]
    assert purge["first_purge_events"] == [] and purge["remaining_count"] == 1
    assert purge["second_purge_events"] == [{"kind": "loading", "level": 31, "decrease": False}, {"kind": "simulation", "level": 31, "decrease": False}]
    ttl = result["tickets"]["unknown_timeout_steps"]
    assert [r["ticket"]["ticks_left"] for r in ttl] == ["1", "0", "1", "0", "-1"]
    assert [r["count"] for r in ttl] == [1, 1, 1, 1, 0]
    assert not ttl[2]["added"] and ttl[2]["same_object"]
    timer = {r["timeout"]: r for r in result["tickets"]["signed_timer_boundaries"]}
    assert timer["0"]["after_one_decrement"]["ticks_left"] == "0"
    assert timer["-9223372036854775808"]["before"]["timed_out"]
    assert timer["-9223372036854775808"]["after_one_decrement"] == {"level": 31, "ticks_left": "9223372036854775807", "timed_out": False}
    cases = {c["id"]: c["steps"] for c in result["entity_load_cases"]}
    success = cases["success-loaded-unload-reload"]
    assert [s["state"]["load_status"] for s in success] == ["FRESH", "PENDING", "PENDING", "PENDING", "LOADED", "LOADED", "LOADED", "FRESH", "PENDING"]
    assert success[2]["state"]["requests"] == 1 and success[2]["events"] == []
    assert success[3]["state"]["inbox"] == 1 and not success[3]["state"]["entities_loaded"]
    assert [(e["event"], e.get("id")) for e in success[4]["events"]] == [("callback_installed", 11), ("tracking_start", 11), ("callback_installed", 12), ("tracking_start", 12)]
    assert all(e["load_status"] == "PENDING" for e in success[4]["events"])
    assert [(e["event"], e["id"]) for e in success[6]["events"]] == [("ticking_end", 11), ("ticking_end", 12), ("tracking_end", 11), ("tracking_end", 12)]
    assert success[7]["events"][0]["event"] == "store_entities" and success[7]["events"][0]["ids"] == [11, 12]
    assert all(not m["known"] and m["removed"] and not m["callback_installed"] for m in success[7]["state"]["members"])
    hidden = cases["hidden-pending-completion"]
    assert hidden[0]["state"]["can_position_tick"] and not hidden[0]["state"]["entities_loaded"]
    assert hidden[2]["state"]["queued_unload"] and hidden[2]["state"]["load_status"] == "PENDING" and hidden[2]["events"] == []
    assert hidden[-1]["state"]["load_status"] == "FRESH" and not hidden[-1]["state"]["queued_unload"]
    reactivate = cases["reactivate-existing-pending-request"]
    assert all(s["state"]["requests"] == 1 for s in reactivate)
    assert not reactivate[2]["state"]["queued_unload"]
    assert [e["event"] for e in reactivate[-1]["events"]] == ["callback_installed", "tracking_start", "ticking_start"]
    failure = cases["failed-storage-remains-pending"]
    assert all(s["state"]["load_status"] == "PENDING" and s["state"]["requests"] == 1 and s["state"]["inbox"] == 0 and not s["state"]["entities_loaded"] for s in failure)
    assert failure[-1]["state"]["queued_unload"]
    existing = cases["existing-entity-ticks-before-file-loaded"]
    assert [e["event"] for e in existing[1]["events"]] == ["load_request", "tracking_start", "ticking_start"]
    assert existing[1]["state"]["global_ids"] == [41] and not existing[1]["state"]["entities_loaded"]
    assert existing[-1]["events"] == [] and existing[-1]["state"]["entities_loaded"]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", type=Path, default=ROOT / "build/entity-chunk-loading-reference/run-001")
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    paths, provenance = verified_client_classpath()
    source = work / "EntityChunkLoadingReference.java"
    source.write_text(SOURCE)
    command = [str(JAVA), "-Xmx256m", "--source", "25", "--class-path", os.pathsep.join(map(str, paths)), str(source), str(work / "observations.json")]
    started = time.monotonic()
    java = subprocess.run(command, capture_output=True, text=True, timeout=45)
    (work / "java.stdout").write_text(java.stdout)
    (work / "java.stderr").write_text(java.stderr)
    receipt = {"command": command, "returncode": java.returncode, "seconds": round(time.monotonic() - started, 4)}
    (work / "run.json").write_text(json.dumps(receipt, indent=2) + "\n")
    if java.returncode:
        raise RuntimeError(java.stderr)
    observations = json.loads((work / "observations.json").read_text())
    verify_observations(observations)
    bytecode = subprocess.run([str(JAVA.parent / "javap"), "-J-Xmx128m", "-c", "-p", "-constants", "-classpath", os.pathsep.join(map(str, paths)), *CLASSES], capture_output=True, text=True, check=True, timeout=30)
    (work / "receivers.javap").write_text(bytecode.stdout)
    with zipfile.ZipFile(CLIENT) as jar:
        classes = [{"name": name, "sha256": hashlib.sha256(jar.read(name.replace(".", "/") + ".class")).hexdigest()} for name in CLASSES]
    result = {
        "schema": 1,
        "pin": "26.3",
        "observations": observations,
        "provenance": provenance,
        "probe_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "java_source_sha256": hashlib.sha256(SOURCE.encode()).hexdigest(),
        "observations_sha256": hashlib.sha256(json.dumps(observations, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
        "receiver_classes": classes,
        "receiver_bytecode_sha256": hashlib.sha256(bytecode.stdout.encode()).hexdigest(),
        "run": receipt,
        "verification": "Actual pinned Java observations checked against independently audited bytecode boundaries; no host ticket or entity lifecycle implementation.",
        "boundary": "ChunkLevel/Visibility, Ticket/TicketStorage, real SimulationChunkTracker, and actual PersistentEntitySectionManager with controlled EntityAccess and asynchronous in-memory EntityPersistentStorage. No actual ChunkMap, ServerChunkCache, ServerLevel world, disk entity files, transport, renderer, or world reload; those future readiness/consumer joins are bytecode-audited only. Java signed-long timer extremum cases use custom TicketType fixtures and do not claim registered vanilla types use negative timeouts.",
    }
    OUTPUT.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"status": "passed", "entity_cases": len(observations["entity_load_cases"]), "entity_steps": sum(len(c["steps"]) for c in observations["entity_load_cases"]), "graph_cells": sum(len(s["levels"]) for s in observations["simulation_graph"]), "seconds": receipt["seconds"], "output": str(OUTPUT)}))


if __name__ == "__main__":
    main()
