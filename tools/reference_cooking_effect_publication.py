#!/usr/bin/env python3
"""Observe pinned Java dirty/comparator publication receivers, not a host model."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import time
from pathlib import Path

from reference_inventory import ROOT, JAVA, canonical, fingerprint
from reference_model_probe import verified_client_classpath
from reference_movement_probe import SOURCE as MOVEMENT_SOURCE, DIRECT_SOURCE

WORK = ROOT / "build/cooking-effect-publication-reference"
OUTPUT = ROOT / "reference/cooking_effect_publication.json"
EVIDENCE = ROOT / "evidence/cooking-effect-publication-reference.json"

SOURCE = r'''
import java.nio.file.*;
import java.lang.reflect.*;
import java.security.*;
import java.util.*;
import com.google.gson.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;
import net.minecraft.core.registries.*;
import net.minecraft.resources.Identifier;
import net.minecraft.world.level.*;
import net.minecraft.world.level.block.*;
import net.minecraft.world.level.block.entity.*;
import net.minecraft.world.level.block.state.*;
import net.minecraft.world.level.chunk.*;
import net.minecraft.world.level.chunk.status.ChunkStatus;
import net.minecraft.world.level.redstone.Orientation;

class ReferenceCookingEffectPublication {
  static final Gson JSON = new GsonBuilder().serializeNulls().create();
  static final Method STATIC_CHANGED;
  static {
    try { STATIC_CHANGED=BlockEntity.class.getDeclaredMethod("setChanged",Level.class,BlockPos.class,BlockState.class);STATIC_CHANGED.setAccessible(true); }
    catch(ReflectiveOperationException error){throw new ExceptionInInitializerError(error);}
  }
  static List<Integer> position(BlockPos p) { return List.of(p.getX(),p.getY(),p.getZ()); }
  static BlockPos position(JsonArray p) { return new BlockPos(p.get(0).getAsInt(),p.get(1).getAsInt(),p.get(2).getAsInt()); }
  static String identity(BlockState s) { return BuiltInRegistries.BLOCK.getKey(s.getBlock()).toString(); }
  static BlockState state(String id) {
    return BuiltInRegistries.BLOCK.getOptional(Identifier.parse(id)).orElseThrow().defaultBlockState();
  }
  // Normal Level construction is inherited from the existing finite fixture.
  // Only map/chunk service inputs and the neighbour notification sink differ.
  // The three publication target methods are NOT overridden.
  static class World extends ReferenceDirectMovementProbe.FixtureLevel {
    final Map<Long,LevelChunk> chunks = new HashMap<>();
    final Set<Long> loaded = new HashSet<>();
    final List<Object> events = new ArrayList<>();
    final List<Object> notifications = new ArrayList<>();
    final List<Object> dirtyTransitions = new ArrayList<>();
    public boolean hasChunk(int x,int z) {
      boolean present=loaded.contains(ChunkPos.pack(x,z));
      events.add(Map.of("call","hasChunk","chunk",List.of(x,z),"loaded",present));
      return present;
    }
    public LevelChunk getChunk(int x,int z) {
      events.add(Map.of("call","getChunk","chunk",List.of(x,z)));
      LevelChunk c=chunks.get(ChunkPos.pack(x,z));
      if(c==null)throw new IllegalStateException("Unexpected unloaded chunk retrieval");
      return c;
    }
    public ChunkAccess getChunk(int x,int z,ChunkStatus status,boolean create) {
      if(status!=ChunkStatus.FULL)throw new IllegalStateException("Unexpected chunk status");
      return getChunk(x,z);
    }
    public BlockState getBlockState(BlockPos p) {
      BlockState s=blocks.get(p);
      if(s==null)throw new IllegalStateException("Undeclared block query: "+p);
      events.add(Map.of("call","getBlockState","position",position(p),"block",identity(s)));
      return s;
    }
    public void neighborChanged(BlockState s,BlockPos p,Block source,Orientation orientation,boolean moving) {
      Object row=Map.of("call","neighborChanged","position",position(p),"block",identity(s),
        "source",BuiltInRegistries.BLOCK.getKey(source).toString(),"orientation_null",orientation==null,"moving",moving);
      events.add(row);notifications.add(row);
    }
    LevelChunk fixtureChunk(BlockPos p) {
      LevelChunk c=new LevelChunk(this,ChunkPos.containing(p));
      c.tryMarkSaved();
      c.setUnsavedListener(q->{
        Object row=Map.of("call","dirty_transition","chunk",List.of(q.x(),q.z()),"unsaved",c.isUnsaved());
        events.add(row);dirtyTransitions.add(row);
      });
      chunks.put(ChunkPos.pack(p.getX()>>4,p.getZ()>>4),c);
      return c;
    }
  }
  static Object profile(World w,String id) {
    BlockState s=state(id);
    return Map.of("id",id,"state_id",Block.getId(s),"is_air",s.isAir(),
      "conductor",s.isRedstoneConductor(w,BlockPos.ZERO));
  }
  static Map<String,String> methodOwners() throws Exception {
    Map<String,String> out=new TreeMap<>();
    out.put("BlockEntity.setChanged",FurnaceBlockEntity.class.getMethod("setChanged").getDeclaringClass().getName());
    out.put("Level.blockEntityChanged",World.class.getMethod("blockEntityChanged",BlockPos.class).getDeclaringClass().getName());
    out.put("Level.updateNeighbourForOutputSignal",World.class.getMethod("updateNeighbourForOutputSignal",BlockPos.class,Block.class).getDeclaringClass().getName());
    out.put("LevelChunk.markUnsaved",LevelChunk.class.getMethod("markUnsaved").getDeclaringClass().getName());
    out.put("ChunkAccess.markUnsaved",ChunkAccess.class.getMethod("markUnsaved").getDeclaringClass().getName());
    if(!out.get("Level.blockEntityChanged").equals(Level.class.getName())||
       !out.get("Level.updateNeighbourForOutputSignal").equals(Level.class.getName())||
       !out.get("BlockEntity.setChanged").equals(BlockEntity.class.getName()))throw new IllegalStateException("Receiver override");
    return out;
  }
  static Map<String,Object> observe(JsonObject input) throws Exception {
    World world=new World();BlockPos origin=position(input.getAsJsonArray("position"));
    for(JsonElement raw:input.getAsJsonArray("loaded_chunks")){
      JsonArray p=raw.getAsJsonArray();world.loaded.add(ChunkPos.pack(p.get(0).getAsInt(),p.get(1).getAsInt()));
    }
    for(JsonElement raw:input.getAsJsonArray("writes")){
      JsonObject row=raw.getAsJsonObject();world.blocks.put(position(row.getAsJsonArray("position")),state(row.get("block").getAsString()));
    }
    LevelChunk chunk=world.fixtureChunk(origin);
    if(input.get("already_dirty").getAsBoolean())chunk.markUnsaved();
    BlockState cached=state(input.get("cached_state").getAsString());
    FurnaceBlockEntity entity=new FurnaceBlockEntity(origin,Blocks.FURNACE.defaultBlockState());
    // FurnaceBlockEntity validates its states and rejects air. The air branch
    // is a direct invocation of the original static publication receiver.
    if(!cached.isAir())entity.setBlockState(cached);entity.setLevel(world);
    world.events.clear();world.notifications.clear();world.dirtyTransitions.clear();
    boolean before=chunk.isUnsaved();
    for(int i=0;i<input.get("repeats").getAsInt();i++){
      if(cached.isAir())STATIC_CHANGED.invoke(null,world,origin,cached);else entity.setChanged();
    }
    Map<String,Object> out=new LinkedHashMap<>();
    out.put("id",input.get("id").getAsString());out.put("dirty_before",before);out.put("dirty_after",chunk.isUnsaved());
    out.put("cached_state",identity(cached));out.put("cached_is_air",cached.isAir());
    out.put("receiver",cached.isAir()?"BlockEntity.setChanged(Level,BlockPos,BlockState)":"FurnaceBlockEntity.setChanged()");
    out.put("notifications",world.notifications);out.put("dirty_transitions",world.dirtyTransitions);out.put("calls",world.events);
    return out;
  }
  public static void main(String[] args) throws Exception {
    SharedConstants.tryDetectVersion();Bootstrap.bootStrap();ReferenceDirectMovementProbe.initialize();
    List<Object> observations=new ArrayList<>();
    for(JsonElement e:JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonArray())observations.add(observe(e.getAsJsonObject()));
    List<String> directions=new ArrayList<>();for(Direction d:Direction.Plane.HORIZONTAL)directions.add(d.name());
    World profileWorld=new World();List<Object> profiles=new ArrayList<>();
    for(String id:List.of("minecraft:air","minecraft:cave_air","minecraft:void_air","minecraft:stone","minecraft:glass","minecraft:comparator"))profiles.add(profile(profileWorld,id));
    Map<String,Object> classes=new TreeMap<>();
    for(String name:List.of("net.minecraft.world.level.Level","net.minecraft.world.level.block.entity.BlockEntity",
        "net.minecraft.world.level.block.entity.FurnaceBlockEntity","net.minecraft.world.level.chunk.ChunkAccess",
        "net.minecraft.world.level.chunk.LevelChunk","net.minecraft.world.level.block.state.BlockBehaviour$BlockStateBase",
        "net.minecraft.world.level.block.state.BlockState","net.minecraft.world.level.block.AirBlock",
        "net.minecraft.core.Direction","net.minecraft.core.Direction$Plane")){
      Class<?> c=Class.forName(name);try(var stream=c.getResourceAsStream("/"+name.replace('.','/')+".class")){
        byte[] bytes=stream.readAllBytes();classes.put(name,Map.of("bytes",bytes.length,"sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes))));
      }
    }
    Files.writeString(Path.of(args[1]),JSON.toJson(Map.of("version",SharedConstants.getCurrentVersion().id(),"cases",observations,
      "horizontal_directions",directions,"block_profiles",profiles,"method_owners",methodOwners(),"runtime_classes",classes)));
  }
}
'''


def inputs() -> list[dict]:
    directions = {"NORTH": (0, 0, -1), "EAST": (1, 0, 0), "SOUTH": (0, 0, 1), "WEST": (-1, 0, 0)}

    def row(label, *, cached="minecraft:furnace", changes=(), origin=(12, 8, 12), loaded=None, dirty=False, repeats=1):
        blocks = {origin: "minecraft:furnace"}
        for dx, dy, dz in [*directions.values(), (0, 1, 0), (0, -1, 0)]:
            for distance in (1, 2):
                blocks[tuple(a + distance * b for a, b in zip(origin, (dx, dy, dz)))] = "minecraft:air"
        for direction, distance, block in changes:
            delta = directions.get(direction, {"UP": (0, 1, 0), "DOWN": (0, -1, 0)}.get(direction))
            blocks[tuple(a + distance * b for a, b in zip(origin, delta))] = block
        return {"id": label, "position": list(origin), "cached_state": cached, "writes": [
            {"position": list(p), "block": s} for p, s in sorted(blocks.items())],
            "loaded_chunks": loaded if loaded is not None else [[0, 0]], "already_dirty": dirty, "repeats": repeats}

    rows = [row("air-only"), row("air-kinds", changes=[("NORTH", 1, "minecraft:cave_air"), ("WEST", 1, "minecraft:void_air")]),
            row("direct-comparators", changes=[(d, 1, "minecraft:comparator") for d in directions]),
            row("conductor-comparator", changes=[("NORTH", 1, "minecraft:stone"), ("NORTH", 2, "minecraft:comparator")]),
            row("conductor-air", changes=[("EAST", 1, "minecraft:stone")]),
            row("nonconductor-comparator", changes=[("SOUTH", 1, "minecraft:glass"), ("SOUTH", 2, "minecraft:comparator")]),
            row("vertical-comparators", changes=[("UP", 1, "minecraft:comparator"), ("DOWN", 1, "minecraft:comparator")]),
            row("already-dirty", dirty=True), row("repeated-mark", repeats=2),
            row("missing-origin-chunk", loaded=[]),
            row("missing-north-chunk", origin=(0, 8, 0), loaded=[[0, 0], [-1, 0]], changes=[("NORTH", 1, "minecraft:comparator")])]
    for block in ["air", "cave_air", "void_air"]:
        rows.append(row("cached-" + block, cached="minecraft:" + block, changes=[(d, 1, "minecraft:comparator") for d in directions]))
    return rows


def validate(actual: dict, request: list[dict]) -> dict:
    assert actual["version"] == "26.3"
    assert actual["horizontal_directions"] == ["NORTH", "EAST", "SOUTH", "WEST"]
    rows = {r["id"]: r for r in actual["cases"]}
    assert len(rows) == len(request) == 14
    profiles = {p["id"]: p for p in actual["block_profiles"]}
    for air in ("air", "cave_air", "void_air"):
        assert profiles["minecraft:" + air]["is_air"] and not profiles["minecraft:" + air]["conductor"]
    assert profiles["minecraft:stone"]["conductor"] and not profiles["minecraft:glass"]["conductor"]
    for label, r in rows.items():
        assert r["receiver"] == ("BlockEntity.setChanged(Level,BlockPos,BlockState)" if label.startswith("cached-") else "FurnaceBlockEntity.setChanged()")
        assert r["dirty_after"] == (label != "missing-origin-chunk")
        assert r["dirty_before"] == (label == "already-dirty")
        transitions = 0 if label in ("already-dirty", "missing-origin-chunk") else 1
        assert len(r["dirty_transitions"]) == transitions
        for event in r["dirty_transitions"]:
            assert event["unsaved"]
        if r["notifications"]:
            assert r["calls"].index(r["dirty_transitions"][0]) < r["calls"].index(r["notifications"][0])
        for event in r["notifications"]:
            assert event["source"] == "minecraft:furnace" and event["block"] == "minecraft:comparator"
            assert event["orientation_null"] and not event["moving"]
    direct = rows["direct-comparators"]["notifications"]
    assert [r["position"] for r in direct] == [[12, 8, 11], [13, 8, 12], [12, 8, 13], [11, 8, 12]]
    assert [r["position"] for r in rows["conductor-comparator"]["notifications"]] == [[12, 8, 10]]
    for label in rows.keys() - {"direct-comparators", "conductor-comparator"}:
        assert rows[label]["notifications"] == []
    for label in ("cached-air", "cached-cave_air", "cached-void_air"):
        assert rows[label]["cached_is_air"]
        assert [c["call"] for c in rows[label]["calls"]] == ["hasChunk", "getChunk", "dirty_transition"]
    for label in ("air-only", "air-kinds", "vertical-comparators", "already-dirty"):
        assert len([c for c in rows[label]["calls"] if c["call"] == "getBlockState"]) == 4
    assert len([c for c in rows["conductor-air"]["calls"] if c["call"] == "getBlockState"]) == 5
    assert len([c for c in rows["nonconductor-comparator"]["calls"] if c["call"] == "getBlockState"]) == 4
    assert len([c for c in rows["repeated-mark"]["calls"] if c["call"] == "getBlockState"]) == 8
    assert len([c for c in rows["missing-north-chunk"]["calls"] if c["call"] == "getBlockState"]) == 3
    return {"cases": len(rows), "horizontal_order": actual["horizontal_directions"], "air_kinds_nonconducting": 3,
            "direct_comparator_notifications": 4, "conductor_comparator_notifications": 1,
            "cached_air_skips_scan": 3, "vertical_notifications": 0, "repeated_mark_transitions": 1,
            "boundary": "Actual dirty marking and comparator-dispatch selection/order; notification sink does not execute redstone scheduling."}


def run_stage(command: list[str], log: Path, seconds: float) -> dict:
    started = time.monotonic()
    result = subprocess.run(command, cwd=WORK, capture_output=True, timeout=seconds)
    log.write_bytes(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(log.read_text(errors="replace")[-5000:])
    return {"command": command, "seconds": round(time.monotonic() - started, 6), "exit_code": result.returncode,
            "log": fingerprint(log)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    request = inputs()
    (WORK / "input.json").write_bytes(canonical(request) + b"\n")
    sources = {"ReferenceCookingEffectPublication": SOURCE, "ReferenceMovementProbe": MOVEMENT_SOURCE,
               "ReferenceDirectMovementProbe": DIRECT_SOURCE}
    files = []
    for name, contents in sources.items():
        file = WORK / (name + ".java")
        file.write_text(contents)
        files.append(file)
    if args.prepare_only:
        print(json.dumps({"status": "prepared-file-only", "cases": len(request), "source_sha256": hashlib.sha256(SOURCE.encode()).hexdigest()}))
        return
    started = time.monotonic()
    history = []
    if EVIDENCE.exists():
        previous = json.loads(EVIDENCE.read_text())
        history = previous.get("previous_attempts", [])
        if previous.get("status") == "failed":
            history.append({k: v for k, v in previous.items() if k != "previous_attempts"})
    evidence = {"status": "running", "command": "python3 tools/reference_cooking_effect_publication.py", "stages": [],
                "previous_attempts": history, "java_sha256": hashlib.sha256(SOURCE.encode()).hexdigest()}
    try:
        jars, provenance = verified_client_classpath()
        cp = os.pathsep.join(map(str, jars))
        evidence["stages"].append(run_stage([str(JAVA.parent / "javac"), "-J-Xmx512m", "-cp", cp, "-d", str(WORK), *map(str, files)], WORK / "compile.log", 60))
        evidence["stages"].append(run_stage([str(JAVA), "-Xmx512m", "-cp", str(WORK) + os.pathsep + cp,
                                                 "ReferenceCookingEffectPublication", str(WORK / "input.json"), str(WORK / "actual.json")], WORK / "run.log", 60))
        actual = json.loads((WORK / "actual.json").read_text())
        validation = validate(actual, request)
        result = {"pin": "26.3", "inputs": request, "observations": actual, "provenance": provenance,
                  "source": {"script": fingerprint(Path(__file__)), "java_sha256": hashlib.sha256(SOURCE.encode()).hexdigest(),
                             "movement_fixture_script": fingerprint(ROOT / "tools/reference_movement_probe.py"),
                             "movement_java_sha256": hashlib.sha256(MOVEMENT_SOURCE.encode()).hexdigest(),
                             "level_fixture_java_sha256": hashlib.sha256(DIRECT_SOURCE.encode()).hexdigest()},
                  "receiver": "Normally constructed original Level and LevelChunk; actual FurnaceBlockEntity.setChanged for valid furnace states. Air branch calls actual protected static BlockEntity.setChanged(Level,BlockPos,BlockState); invalid air FurnaceBlockEntity state is not admitted. Actual Level.blockEntityChanged, Level.updateNeighbourForOutputSignal, LevelChunk.markUnsaved and ChunkAccess.markUnsaved. Finite exact block map and declared loaded chunks. neighborChanged is an observable sink; downstream comparator tick scheduling is outside this reference.",
                  "validation": validation}
        OUTPUT.write_bytes(canonical(result) + b"\n")
        evidence.update(status="passed", validation=validation, reference=fingerprint(OUTPUT), runtime_classes=actual["runtime_classes"],
                        method_owners=actual["method_owners"], source=result["source"])
    except Exception as error:
        evidence.update(status="failed", error=str(error))
        raise
    finally:
        evidence["seconds"] = round(time.monotonic() - started, 6)
        EVIDENCE.write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({"status": "passed", "cases": len(request), "seconds": evidence["seconds"]}))


if __name__ == "__main__":
    main()
