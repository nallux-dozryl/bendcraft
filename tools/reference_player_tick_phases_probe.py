#!/usr/bin/env python3
"""Pinned tick-phase call sites and narrow actual receiver observations.

Static bytecode order is labelled separately from executed receiver traces.
Full disassembly/observations remain in ignored build artifacts.
"""
from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import struct
import subprocess
import time
import zipfile

from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_model_probe import CLIENT, verified_client_classpath
import reference_local_input_probe as LI

RAW = ROOT / "build/player-tick-phases"
CLASSES = [
    "net.minecraft.client.Minecraft",
    "net.minecraft.client.multiplayer.ClientLevel",
    "net.minecraft.client.player.LocalPlayer",
    "net.minecraft.client.player.AbstractClientPlayer",
    "net.minecraft.world.entity.player.Player",
    "net.minecraft.world.entity.Avatar",
    "net.minecraft.world.entity.LivingEntity",
    "net.minecraft.world.entity.Entity",
    "net.minecraft.client.player.KeyboardInput",
]
METHODS = {
    "tickNonPassenger", "tickEntities", "lambda$tickEntities$0", "tick", "commonTick", "baseTick", "aiStep",
    "setOldPosAndRot", "setOldRot", "rangeChecks", "applyInput", "modifyInput",
    "updatePlayerPose", "getDesiredPose", "updateIsUnderwater", "setPose", "refreshDimensions",
    "onSyncedDataUpdated", "move", "restituteMovementAfterCollisions",
    "isHorizontalCollisionMinor", "setOnGroundWithMovement", "checkSupportingBlock",
    "doCheckFallDamage", "checkFallDamage", "checkFallDistanceAccumulation",
    "applyEffectsFromBlocks", "travel", "travelInAir", "maybeBackOffFromEdge",
    "updateAutoJump", "addWalkedDistance", "updateFluidInteraction", "updateBob",
    "isShiftKeyDown", "updateFallFlying", "resetFallDistance",
    "applyEffectsFromBlocksForLastMovements", "setOldPos", "updateSwimming",
    "sendChanges", "sendPosition", "sendIsSprintingIfNeeded",
    "canPlayerFitWithinBlocksAndEntitiesWhen", "isVisuallyCrawling", "isCrouching",
    "isMovingSlowly", "getEyeHeight", "getEyePosition", "reapplyPosition",
    "makeBoundingBox", "setBoundingBox",
}
PHASE_CALLS = METHODS | {
    "setOldPos", "setSprinting", "setOnGround", "setBoundingBox", "setPos",
    "setPosRaw", "setDeltaMovement", "recordMovement", "canPlayerFitWithinBlocksAndEntitiesWhen",
    "canPlayerFitWithinBlocksAndEntities", "moveTowardsClosestSpace", "jumpableVehicle",
    "jumpFromGround", "getBlockJumpFactor", "getBlockPosBelowThatAffectsMyMovement",
    "getOnPosLegacy", "getOnPos", "collide", "collideBoundingBox", "resetFallDistance",
    "clip", "fallOn", "stepOn", "canSimulateMovement", "canSimulateMovementThisTick",
    "isLocalInstanceAuthoritative", "canProcessInsideBlockStep", "remove",
    "updateSwingTime", "tickEffects", "handleFrictionAndCalculateMovement",
    "applyMovementEmissionAndPlaySound", "getBlockSpeedFactor", "getFriction",
    "shouldDiscardFriction", "handlePortal", "tickDeath", "tickRiding",
    "updateInWaterStateAndDoFluidPushing", "updateSwimming", "updateFallFlying",
    "updateWalkAnimation", "rideTick", "setShiftKeyDown", "isShiftKeyDown",
}
FIELD_MARKERS = {
    "tickCount", "xRotO", "yRotO", "yBodyRotO", "yHeadRotO", "xo", "yo", "zo",
    "crouching", "sprintTriggerTime", "jumpTriggerTime", "noJumpDelay", "jumping",
    "xxa", "yya", "zza", "xBob", "yBob", "xBobO", "yBobO", "fallDistance",
    "horizontalCollision", "minorHorizontalCollision", "verticalCollision",
    "verticalCollisionBelow", "mainSupportingBlockPos", "onGroundNoBlocks",
    "dimensions", "pose", "autoJumpEnabled", "isUnderWater",
}
API_FILES = [
    "src/player_rotation_tick.bend", "src/local_input.bend", "src/local_tick_world.bend",
    "src/local_move_world.bend", "src/player_fall_history.bend", "src/support.bend",
    "src/support_world.bend", "src/travel.bend", "src/player_tick.bend",
]
FIXTURE = "net.minecraft.fixture.LocalInputReceiverFixture"


def phase_inputs() -> list[dict]:
    """Explicit small receiver histories, independent of any Bend output."""
    seed = copy.deepcopy(LI.corpus_inputs()["ai_step"][0]["initial"])
    seed.update(previous_mask=0, previous_move_f32_bits=["00000000"] * 2,
                velocity=["0000000000000000"] * 3, input_f32_bits=["00000000"] * 3,
                jumping=False, jump_delay=0, jump_trigger=0, crouching=False,
                pose="STANDING", sprinting=False, sprint_trigger_time=0,
                horizontal_collision=False, minor_horizontal_collision=False,
                rotation_f32_bits=[fb(17), fb(-11), fb(12), fb(-9)])
    result = []
    for name, operation, held, count in [
        ("scheduled_shift", "level_tick", [32, 32, 0, 0], 0),
        ("direct_shift", "tick", [32, 32, 0, 0], 40),
        ("scheduled_sprint_jump", "level_tick", [65, 81, 1, 0], 7),
        ("scheduled_jump", "level_tick", [17, 1], 0),
        ("scheduled_blocked", "level_tick", [0], 0),
        ("scheduled_step", "level_tick", [0, 0], 0),
        ("scheduled_zero", "level_tick", [0], 0),
    ]:
        initial = copy.deepcopy(seed)
        if name == "direct_shift":
            initial["rotation_f32_bits"][2:] = [fb(737), fb(349)]
        if name in {"scheduled_blocked", "scheduled_step"}:
            initial.update(velocity=[db(.8), db(-.1), db(0)],
                           rotation_f32_bits=[fb(-90), fb(-11), fb(-90), fb(-9)],
                           step_height=db(1 if name.endswith("step") else 0),
                           world_blocks=[{"position": [1, 1, 0], "identifier": "minecraft:stone"}])
        result.append({"id": name, "operation": operation, "tick_count_u32": count,
                       "initial": initial, "steps": [{"held_mask": mask} for mask in held]})
    return result


def fb(value: float) -> str:
    return struct.pack(">f", value).hex()


def db(value: float) -> str:
    return struct.pack(">d", value).hex()


HELPERS = r'''
 static Map<String,Object> phaseState(LocalPlayer p)throws Exception{
  Map<String,Object> m=new TreeMap<>();Map<String,Object> all=state(p);
  for(String key:List.of("key_presses","crouching","pose","width_f32_bits","height_f32_bits","box","position","velocity","body_flags","minor_horizontal_collision","rotation_f32_bits","input_f32_bits","jumping","jump_delay","sprint_trigger_time","sprinting","movement_speed","bob_f32_bits"))m.put(key,all.get(key));
  m.put("tick_count_u32",Integer.toUnsignedLong(p.tickCount));m.put("fall_distance_f64_bits",bits(p.fallDistance));m.put("old_position",List.of(bits(p.xo),bits(p.yo),bits(p.zo)));
  m.put("cached_eye_height_f32_bits",bits((float)read(p,"eyeHeight")));m.put("get_eye_height_f32_bits",bits(p.getEyeHeight()));m.put("pose_eye_height_f32_bits",bits(p.getDimensions(p.getPose()).eyeHeight()));m.put("eye_position_f64_bits",vector(p.getEyePosition()));
  m.put("body_head_rotation_f32_bits",List.of(bits(p.yBodyRot),bits(p.yBodyRotO),bits(p.yHeadRot),bits(p.yHeadRotO)));
  Optional<?> support=(Optional<?>)read(p,"mainSupportingBlockPos");m.put("support",support.isPresent()?List.of(((BlockPos)support.get()).getX(),((BlockPos)support.get()).getY(),((BlockPos)support.get()).getZ()):null);m.put("on_ground_no_blocks",read(p,"onGroundNoBlocks"));return m;
 }
 static class ObservedKeyboardInput extends KeyboardInput {
  final ObservedPlayer player;
  ObservedKeyboardInput(Options options,ObservedPlayer player){super(options);this.player=player;}
  public void tick(){player.phase("keyboard_entry");super.tick();player.phase("keyboard_exit");}
 }
 static void phasesCorpus(HolderLookup.Provider lookup)throws Exception{
  JsonArray values=JsonParser.parseString(new String(Base64.getDecoder().decode(__PHASE_INPUT__),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonArray();
  for(JsonElement e:values)for(boolean observed:List.of(false,true)){
   JsonObject in=e.getAsJsonObject();Context c=new Context(lookup,observed);LocalPlayer p=c.player;JsonObject init=in.getAsJsonObject("initial");configure(c,init);p.tickCount=(int)in.get("tick_count_u32").getAsLong();p.yHeadRot=p.getYRot();p.yHeadRotO=p.getYRot();p.yBodyRot=p.getYRot();p.yBodyRotO=p.getYRot();
   if(init.has("step_height"))p.getAttribute(Attributes.STEP_HEIGHT).setBaseValue(d(init.get("step_height")));
   if(init.has("world_blocks"))for(JsonElement b:init.getAsJsonArray("world_blocks")){JsonObject block=b.getAsJsonObject();JsonArray pos=block.getAsJsonArray("position");if(!block.get("identifier").getAsString().equals("minecraft:stone"))throw new AssertionError("Only declared real full-cube stone fixture");c.level.blocks.put(new BlockPos(pos.get(0).getAsInt(),pos.get(1).getAsInt(),pos.get(2).getAsInt()),Blocks.STONE.defaultBlockState());}
   List<Map<String,Object>> steps=new ArrayList<>();
   for(JsonElement se:in.getAsJsonArray("steps")){
    JsonObject step=se.getAsJsonObject();c.keys(step.get("held_mask").getAsInt());Map<String,Object> row=new TreeMap<>();row.put("before",phaseState(p));row.put("input",step);
    if(observed){ObservedPlayer o=(ObservedPlayer)p;o.calls.clear();o.tickPhases.clear();o.phaseRecording=true;}
    try{if(in.get("operation").getAsString().equals("level_tick"))c.level.tickNonPassenger(p);else if(in.get("operation").getAsString().equals("tick"))p.tick();else throw new AssertionError("Unknown phase entry");row.put("ok",true);}
    catch(Throwable failure){Throwable r=failure;while(r.getCause()!=null)r=r.getCause();row.put("ok",false);row.put("error_class",r.getClass().getName());row.put("error_message",String.valueOf(r.getMessage()));row.put("error_stack",Arrays.stream(r.getStackTrace()).map(StackTraceElement::toString).toList());}
    if(observed){ObservedPlayer o=(ObservedPlayer)p;o.phaseRecording=false;row.put("phases",List.copyOf(o.tickPhases));row.put("local_input_observers",List.copyOf(o.calls));}else{row.put("phases",List.of());row.put("local_input_observers",List.of());}
    row.put("after",phaseState(p));steps.add(row);if(!row.get("ok").equals(true))break;
   }
   output(Map.of("id",in.get("id").getAsString(),"operation",in.get("operation").getAsString(),"observed",observed,"steps",steps,"service_calls",c.level.observations,"outgoing_packet_classes",c.connection.sent));
  }
 }
'''

OBSERVER = r'''
  boolean phaseRecording;
  final List<Map<String,Object>> tickPhases=new ArrayList<>();
  void phase(String name){phase(name,Map.of());}
  void phase(String name,Map<String,Object> details){if(tickPhases!=null&&phaseRecording)try{Map<String,Object> row=new TreeMap<>();row.put("phase",name);row.put("state",phaseState(this));row.put("details",details);tickPhases.add(row);}catch(Exception e){throw new RuntimeException(e);}}
  public void tick(){phase("tick_entry");super.tick();phase("tick_exit");}
  public void baseTick(){phase("base_tick_entry");super.baseTick();phase("base_tick_exit");}
  public void aiStep(){phase("ai_step_entry");super.aiStep();phase("ai_step_exit");}
  public void setOldRot(){phase("set_old_rot_entry");super.setOldRot();phase("set_old_rot_exit");}
  protected void updateBob(){phase("update_bob_entry");super.updateBob();phase("update_bob_exit");}
  protected boolean updateIsUnderwater(){phase("underwater_entry");boolean result=super.updateIsUnderwater();phase("underwater_exit",Map.of("result",result));return result;}
  protected boolean updateFluidInteraction(){phase("fluid_interaction_entry");boolean result=super.updateFluidInteraction();phase("fluid_interaction_exit",Map.of("result",result));return result;}
  public void move(MoverType type,Vec3 requested){phase("move_entry",Map.of("requested",vector(requested)));super.move(type,requested);phase("move_exit");}
  public void recordMovement(MoverType type,Vec3 resolved){phase("record_movement_entry",Map.of("resolved",vector(resolved)));super.recordMovement(type,resolved);phase("record_movement_exit");}
  public void setOnGroundWithMovement(boolean ground,boolean horizontal,Vec3 resolved){Map<String,Object> details=new TreeMap<>();details.put("ground",ground);details.put("horizontal",horizontal);details.put("resolved",resolved==null?null:vector(resolved));phase("support_entry",details);super.setOnGroundWithMovement(ground,horizontal,resolved);phase("support_exit",details);}
  protected boolean isHorizontalCollisionMinor(Vec3 resolved){phase("minor_entry",Map.of("resolved",vector(resolved)));boolean minor=super.isHorizontalCollisionMinor(resolved);phase("minor_exit",Map.of("result",minor));return minor;}
  protected void checkFallDamage(double y,boolean ground,BlockState block,BlockPos pos){Map<String,Object> details=Map.of("resolved_y_f64_bits",bits(y),"ground",ground,"block",BuiltInRegistries.BLOCK.getKey(block.getBlock()).toString(),"position",List.of(pos.getX(),pos.getY(),pos.getZ()));phase("fall_entry",details);super.checkFallDamage(y,ground,block,pos);phase("fall_exit",details);}
  public void checkFallDistanceAccumulation(){phase("fall_clamp_entry");super.checkFallDistanceAccumulation();phase("fall_clamp_exit");}
  protected void updateFallFlying(){phase("fall_flying_entry");super.updateFallFlying();phase("fall_flying_exit");}
  protected void applyEffectsFromBlocks(){phase("block_effects_entry");super.applyEffectsFromBlocks();phase("block_effects_exit");}
  protected void updatePlayerPose(){phase("pose_update_entry");super.updatePlayerPose();phase("pose_update_exit");}
  public void setPose(Pose pose){phase("set_pose_entry",Map.of("requested",pose.name()));super.setPose(pose);phase("set_pose_exit",Map.of("requested",pose.name()));}
  public void refreshDimensions(){phase("dimensions_entry");super.refreshDimensions();phase("dimensions_exit");}
'''


def sources(values: list[dict]) -> dict[str, str]:
    result = LI.receiver_sources({})
    source = result[FIXTURE]
    needle = "  final List<Map<String,Object>> calls=new ArrayList<>();"
    assert source.count(needle) == 1
    source = source.replace(needle, needle + OBSERVER)
    needle = "input=new KeyboardInput(mc.options);"
    assert source.count(needle) == 1
    source = source.replace(needle, "input=observed?new ObservedKeyboardInput(mc.options,(ObservedPlayer)player):new KeyboardInput(mc.options);")
    # The existing super-calling LI observers also mark boundaries in this trace.
    for begin, end, phase in [
        ("public void applyInput(){", "super.applyInput();", "apply_input"),
        ("public void travel(Vec3 input){", "super.travel(input);", "travel"),
        ("public void jumpFromGround(){", "super.jumpFromGround();", "jump"),
        ("public void setSprinting(boolean value){", "super.setSprinting(value);", "sprint_setter"),
    ]:
        assert source.count(begin) == source.count(end) == 1
        source = source.replace(begin, begin + 'phase("' + phase + '_entry");')
        source = source.replace(end, end + 'phase("' + phase + '_exit");')
    needle = " public static void run(String mode)throws Exception{"
    assert source.count(needle) == 1
    helper = HELPERS.replace("__PHASE_INPUT__", LI.java_string(base64.b64encode(canonical(values)).decode()))
    source = source.replace(needle, helper + "\n" + needle)
    needle = '  if(mode.equals("corpus"))'
    assert source.count(needle) == 1
    source = source.replace(needle, '  if(mode.equals("tick-phases")){phasesCorpus(lookup);return;}\n' + needle)
    result[FIXTURE] = source
    return result


def observe(values: list[dict], label: str) -> dict:
    paths, provenance = verified_client_classpath()
    derived = sources(values)
    payload = {"sources": derived, "client_jar": str(CLIENT), "mode": "tick-phases"}
    encoded = base64.b64encode(canonical(payload)).decode()
    launcher = LI.RECEIVER_LAUNCHER.replace("Base64.getDecoder().decode(args[0])",
        'Base64.getDecoder().decode(String.join("",new String[]{' +
        ",".join(json.dumps(encoded[i:i+6144]) for i in range(0, len(encoded), 6144)) + '}))', 1)
    command = [str(JAVA), "--source", "25", "--class-path", os.pathsep.join(map(str, paths)), "/dev/stdin"]
    started = time.monotonic()
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        stdout, stderr = process.communicate(launcher, timeout=120)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
        raise RuntimeError("120-second Java phase probe cap expired")
    rows = [json.loads(line[len("LOCAL_RECEIVER_JSON:"):]) for line in stdout.splitlines()
            if line.startswith("LOCAL_RECEIVER_JSON:")]
    loaded = [json.loads(line[len("LOCAL_INPUT_CLASSES:"):]) for line in stdout.splitlines()
              if line.startswith("LOCAL_INPUT_CLASSES:")]
    raw = RAW / (label + ".full.json")
    write_json(raw, {"observations": rows, "official_classes": loaded, "sources": derived,
                     "launcher": launcher, "command": command, "stdout": stdout,
                     "stderr": stderr, "returncode": process.returncode, "classpath": provenance})
    assert process.returncode == 0, (process.returncode, stderr[-4500:], stdout[-1000:])
    assert len(loaded) == 1 and len(rows) == 2 * len(values)
    with zipfile.ZipFile(CLIENT) as jar:
        for name, sha in loaded[0].items():
            assert sha == digest(jar.read(name.replace(".", "/") + ".class")), name
    for name in CLASSES:
        if name in LI.RECEIVER_SOURCES:
            continue
        assert name in loaded[0], name
    cases = []
    for value, plain, observed in zip(values, rows[::2], rows[1::2]):
        assert plain["id"] == observed["id"] == value["id"]
        assert not plain["observed"] and observed["observed"]
        assert len(plain["steps"]) == len(observed["steps"])
        for i, (a, b) in enumerate(zip(plain["steps"], observed["steps"])):
            for key in ["before", "after", "ok", "input"]:
                assert a[key] == b[key], (value["id"], i, key)
            if not a["ok"]:
                for key in ["error_class", "error_message"]:
                    assert a[key] == b[key]
        cases.append({"id": value["id"], "operation": value["operation"],
                      "steps": observed["steps"], "observer_free_state_parity": True,
                      "outgoing_packet_classes": observed["outgoing_packet_classes"],
                      "service_calls_plain": plain["service_calls"],
                      "service_calls_observed": observed["service_calls"]})
    return {"cases": cases, "inputs": values, "raw_artifact": {"path": str(raw.relative_to(ROOT)), **fingerprint(raw)},
            "execution": {"seconds": round(time.monotonic()-started, 6), "returncode": process.returncode,
                          "command_sha256": digest(canonical(command)),
                          "stdout_sha256": digest(stdout.encode()), "stderr_sha256": digest(stderr.encode())},
            "loaded_official_class_count": len(loaded[0]),
            "loaded_official_class_tree_sha256": digest(canonical(loaded[0])),
            "loaded_critical_classes_sha256": {name: loaded[0][name] for name in CLASSES if name not in LI.RECEIVER_SOURCES},
            "derived_sources_sha256": {name: digest(source.encode()) for name, source in derived.items()},
            "base_templates_sha256": {name: digest(source.encode()) for name, source in LI.RECEIVER_SOURCES.items()},
            "launcher_sha256": digest(launcher.encode()), "classpath_sha256": digest(canonical(provenance))}


def verify_phase_facts(cases: list[dict]) -> dict:
    """Assert only facts directly present in measured raw receiver traces."""
    successful = 0
    skipped_application = 0
    minor = 0
    dimensions = 0
    eye_samples = 0
    summary = []
    required = ["tick_entry", "base_tick_entry", "base_tick_exit", "ai_step_entry",
                "keyboard_entry", "keyboard_exit", "update_bob_entry", "update_bob_exit",
                "apply_input_entry", "apply_input_exit", "travel_entry", "move_entry",
                "support_entry", "support_exit", "fall_entry", "fall_exit", "move_exit",
                "travel_exit", "block_effects_entry", "block_effects_exit", "ai_step_exit",
                "pose_update_entry", "pose_update_exit", "tick_exit"]
    for case in cases:
        for index, step in enumerate(case["steps"]):
            phases = step["phases"]
            names = [p["phase"] for p in phases]
            before, after = step["before"], step["after"]
            count = (before["tick_count_u32"] + int(case["operation"] == "level_tick")) & 0xffffffff
            assert after["tick_count_u32"] == count
            for state in [before, after] + [p["state"] for p in phases]:
                assert state["cached_eye_height_f32_bits"] == state["get_eye_height_f32_bits"]
                pos = [struct.unpack(">d", bytes.fromhex(v))[0] for v in state["position"]]
                eye = struct.unpack(">f", bytes.fromhex(state["cached_eye_height_f32_bits"]))[0]
                assert state["eye_position_f64_bits"] == [db(pos[0]), db(pos[1] + eye), db(pos[2])]
                eye_samples += 1
            if not step["ok"]:
                assert case["id"] == "scheduled_sprint_jump" and index == 1
                assert names[-1] == "base_tick_entry" and "ai_step_entry" not in names
                assert step["error_class"] == "java.lang.NoSuchFieldError" and "gameRenderer" in step["error_message"]
                continue
            successful += 1
            assert all(names.count(name) == 1 for name in required)
            assert [names.index(name) for name in required] == sorted(names.index(name) for name in required)
            assert "fall_clamp_entry" not in names and "fall_flying_entry" not in names
            if case["operation"] == "level_tick":
                assert names.index("set_old_rot_exit") < names.index("tick_entry")
            else:
                assert "set_old_rot_entry" not in names
            event = {p["phase"]: p for p in phases}
            assert event["keyboard_exit"]["state"]["key_presses"][5] == bool(step["input"]["held_mask"] & 32)
            assert event["keyboard_entry"]["state"]["crouching"] == event["keyboard_exit"]["state"]["crouching"]
            if "record_movement_entry" not in names:
                skipped_application += 1
                assert names.count("support_entry") == names.count("fall_entry") == 1
            if "minor_entry" in names:
                minor += 1
                assert names.index("support_exit") < names.index("minor_entry") < names.index("fall_entry")
            if "dimensions_entry" in names:
                dimensions += 1
                a, b = event["dimensions_entry"]["state"], event["dimensions_exit"]["state"]
                assert a["position"] == b["position"]
                assert a["box"][:4] == b["box"][:4] and a["box"][5] == b["box"][5]
                assert a["box"][4] != b["box"][4]
                assert a["cached_eye_height_f32_bits"] != b["cached_eye_height_f32_bits"]
                assert a["cached_eye_height_f32_bits"] != a["pose_eye_height_f32_bits"]
                assert b["cached_eye_height_f32_bits"] == b["pose_eye_height_f32_bits"]
            summary.append({"id": case["id"], "index": index,
                            "before_pose": before["pose"], "after_pose": after["pose"],
                            "move_height_f32_bits": event["move_entry"]["state"]["height_f32_bits"],
                            "move_eye_height_f32_bits": event["move_entry"]["state"]["cached_eye_height_f32_bits"],
                            "after_eye_height_f32_bits": after["cached_eye_height_f32_bits"],
                            "application_recorded": "record_movement_entry" in names,
                            "phase_order_sha256": digest(canonical(names))})
    by_id = {c["id"]: c for c in cases}
    for id in ["scheduled_shift", "direct_shift"]:
        rows = by_id[id]["steps"]
        assert [s["after"]["crouching"] for s in rows] == [False, True, True, False]
        assert [s["after"]["pose"] for s in rows] == ["CROUCHING", "CROUCHING", "STANDING", "STANDING"]
        assert [next(p for p in s["phases"] if p["phase"] == "move_entry")["state"]["height_f32_bits"] for s in rows] == ["3fe66666", "3fc00000", "3fc00000", "3fe66666"]
    direct = by_id["direct_shift"]["steps"][0]
    event = {p["phase"]: p for p in direct["phases"]}
    assert event["ai_step_exit"]["state"]["rotation_f32_bits"][2:] == [fb(737), fb(349)]
    assert event["pose_update_entry"]["state"]["rotation_f32_bits"][2:] == [fb(17), fb(-11)]
    step = by_id["scheduled_step"]["steps"][0]
    assert next(p for p in step["phases"] if p["phase"] == "support_entry")["details"]["resolved"][1] == db(1)
    assert "jump_entry" in [p["phase"] for p in by_id["scheduled_jump"]["steps"][0]["phases"]]
    return {"successful_call_order_checks": successful, "application_gate_skips_with_support_and_fall": skipped_application,
            "minor_calls_after_support_before_fall": minor, "pose_dimension_refreshes": dimensions,
            "retained_position_on_every_observed_refresh": True, "raw_eye_field_getter_position_checks": eye_samples,
            "neutral_calls_with_gliding_clamp": 0, "shift_cache_pose_latency_checked": True,
            "inline_camera_normalization_between_ai_step_and_pose_checked": True, "summary": summary}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def method_name(signature: str) -> str:
    match = re.search(r"([\w$<>]+)\([^\n]*\);$", signature)
    return match[1] if match else "<unknown>"


def target_name(target: str) -> str:
    return target.split(":", 1)[0].rsplit(".", 1)[-1].strip('"')


def parse_methods(text: str) -> list[dict]:
    starts = list(re.finditer(r"^  ((?:public|protected|private|static)[^\n]*\([^\n]*\);)\n", text, re.M))
    methods = []
    for i, start in enumerate(starts):
        signature = start[1]
        name = method_name(signature)
        if name not in METHODS:
            continue
        body = text[start.end():starts[i + 1].start() if i + 1 < len(starts) else len(text)]
        descriptor = re.search(r"^    descriptor: (.+)$", body, re.M)
        instructions = []
        for line in body.splitlines():
            instruction = re.match(r"\s+(\d+):\s+(\S+)\s*(.*)", line)
            if instruction:
                instructions.append({"offset": int(instruction[1]), "opcode": instruction[2], "operand": instruction[3]})
        calls = []
        writes = []
        for instruction in instructions:
            comment = instruction["operand"].split("// ", 1)
            if len(comment) < 2:
                continue
            if instruction["opcode"].startswith("invoke") and comment[1].startswith(("Method ", "InterfaceMethod ")):
                target = comment[1].split(" ", 1)[1]
                calls.append({"offset": instruction["offset"], "opcode": instruction["opcode"], "target": target})
            if instruction["opcode"] in {"putfield", "putstatic"} and comment[1].startswith("Field "):
                writes.append({"offset": instruction["offset"], "opcode": instruction["opcode"], "target": comment[1][6:]})
        methods.append({"name": name, "signature": signature, "descriptor": descriptor[1] if descriptor else None,
                        "body_sha256": digest(body.encode()), "body": body,
                        "instructions": instructions, "calls": calls, "field_writes": writes})
    return methods


def inventory() -> dict:
    RAW.mkdir(parents=True, exist_ok=True)
    full = {}
    public = {}
    javap = JAVA.parent / "javap"
    with zipfile.ZipFile(CLIENT) as jar:
        for owner in CLASSES:
            command = [str(javap), "-classpath", str(CLIENT), "-p", "-c", "-s", owner]
            process = subprocess.run(command, capture_output=True, text=True, timeout=30, check=True)
            text = process.stdout
            path = RAW / (owner.rsplit(".", 1)[-1] + ".javap.txt")
            path.write_text(text)
            methods = parse_methods(text)
            entry = owner.replace(".", "/") + ".class"
            full[owner] = {"class_entry": entry, "class_sha256": digest(jar.read(entry)), "methods": methods}
            public[owner] = {"class_entry": entry, "class_sha256": full[owner]["class_sha256"],
                             "javap_artifact": {"path": str(path.relative_to(ROOT)), **fingerprint(path)},
                             "methods": [{"name": m["name"], "signature": m["signature"], "descriptor": m["descriptor"],
                                          "body_sha256": m["body_sha256"],
                                          "phase_calls_in_bytecode_order": [c for c in m["calls"] if target_name(c["target"]) in PHASE_CALLS],
                                          "phase_field_writes": [c for c in m["field_writes"] if target_name(c["target"]) in FIELD_MARKERS],
                                          "all_call_count": len(m["calls"]),
                                          "branch_count": sum(i["opcode"].startswith("if") or i["opcode"] in {"goto", "tableswitch", "lookupswitch"} for i in m["instructions"])} for m in methods]}
    raw = RAW / "bytecode-inventory.full.json"
    write_json(raw, full)
    # Resolve the synthetic entity iteration callbacks from actual BootstrapMethods.
    verbose_path = RAW / "ClientLevel.verbose.javap.txt"
    verbose = subprocess.run([str(javap), "-classpath", str(CLIENT), "-p", "-v",
                              "net.minecraft.client.multiplayer.ClientLevel"],
                             capture_output=True, text=True, timeout=30, check=True).stdout
    verbose_path.write_text(verbose)
    bootstrap = verbose[verbose.index("BootstrapMethods:"):]
    callbacks = re.findall(r"REF_invokeVirtual net/minecraft/client/multiplayer/ClientLevel\.(?:lambda\$tickEntities\$0|tickNonPassenger):[^\n]+", bootstrap)
    assert len(callbacks) == 2
    result = {"schema_version": 1, "status": "extracted", "pin": "26.3",
              "kind": "static call sites, not executed traces",
              "ordering_limit": "Ascending bytecode offsets are instruction layout; guarded branches, loops and virtual dispatch require call-path interpretation. Full instructions/guards remain in raw artifacts.",
              "raw_artifact": {"path": str(raw.relative_to(ROOT)), **fingerprint(raw)},
              "client_jar": fingerprint(CLIENT), "java_runtime": fingerprint(JAVA), "javap": fingerprint(javap),
              "classes": public, "entity_iteration_actual_bootstrap_targets": callbacks,
              "bootstrap_raw_artifact": {"path": str(verbose_path.relative_to(ROOT)), **fingerprint(verbose_path)},
              "api_sources_sha256": {p: digest((ROOT / p).read_bytes()) for p in API_FILES}}
    write_json(ROOT / "evidence/player-tick-phases-bytecode.json", result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", action="store_true")
    parser.add_argument("--extract", action="store_true")
    args = parser.parse_args()
    result = inventory()
    if args.extract:
        producers_before = {"probe": digest(Path(__file__).read_bytes()), "local_input_probe": digest(Path(LI.__file__).read_bytes()),
                            "client_jar": fingerprint(CLIENT)["sha256"]}
        incoming = phase_inputs()
        observed = observe(incoming, "final-first")
        repeated = observe(incoming, "final-rerun")
        assert observed["cases"] == repeated["cases"], "Fresh actual phase rerun differs"
        assert observed["loaded_official_class_tree_sha256"] == repeated["loaded_official_class_tree_sha256"]
        facts = verify_phase_facts(observed["cases"])
        producers_after = {"probe": digest(Path(__file__).read_bytes()), "local_input_probe": digest(Path(LI.__file__).read_bytes()),
                           "client_jar": fingerprint(CLIENT)["sha256"]}
        assert producers_before == producers_after, "Probe/fixture/JAR changed during extraction"
        # Reference snapshots are delta-encoded without dropping any phase-state field.
        compact = copy.deepcopy(observed["cases"])
        for case in compact:
            for step in case["steps"]:
                previous = step["before"]
                for phase in step["phases"]:
                    current = phase.pop("state")
                    assert current.keys() == previous.keys()
                    phase["state_changes"] = {key: value for key, value in current.items() if previous[key] != value}
                    previous = current
                step["local_input_observer_methods"] = [c["method"] for c in step.pop("local_input_observers")]
        reference = {"schema_version": 1, "pin": "26.3", "kind": "actual receiver traces",
                     "inputs": incoming, "cases": compact,
                     "snapshot_encoding": "Start from each step.before; apply each phase.state_changes to the previous complete state. Details and event order are exact. Full uncompressed observations remain in pinned raw artifacts.",
                     "cases_full_sha256": digest(canonical(observed["cases"])),
                     "cases_compact_sha256": digest(canonical(compact)),
                     "raw_artifacts": [observed["raw_artifact"], repeated["raw_artifact"]]}
        # Lossless phase-state round trip; full LI observer snapshots intentionally stay raw.
        for original, encoded in zip(observed["cases"], compact):
            for a, b in zip(original["steps"], encoded["steps"]):
                current = copy.deepcopy(b["before"])
                for p, q in zip(a["phases"], b["phases"]):
                    current.update(q["state_changes"])
                    assert current == p["state"] and p["phase"] == q["phase"] and p["details"] == q["details"]
        write_json(ROOT / "reference/player_tick_phases.json", reference)
        evidence = {key: value for key, value in observed.items() if key not in {"cases", "inputs"}}
        evidence.update(schema_version=1, pin="26.3", status="observed",
                        kind="actual normally constructed receiver behavior; no Bend/native verdict",
                        independent_rerun= {key: repeated[key] for key in ["raw_artifact", "execution", "loaded_official_class_tree_sha256"]},
                        exact_observation_rerun_equal=True, observer_free_state_parity=True,
                        producers_before_sha256=producers_before, producers_after_sha256=producers_after,
                        observed_facts=facts,
                        histories=len(incoming), actual_entry_calls=sum(len(c["steps"]) for c in observed["cases"]),
                        actual_receiver_entry_calls_both_reruns=4 * sum(len(c["steps"]) for c in observed["cases"]),
                        successful_calls=sum(s["ok"] for c in observed["cases"] for s in c["steps"]),
                        failures=[{"id": c["id"], "error_class": s["error_class"], "error_message": s["error_message"]} for c in observed["cases"] for s in c["steps"] if not s["ok"]],
                        phase_snapshots=sum(len(s["phases"]) for c in observed["cases"] for s in c["steps"]),
                        reference_artifact={"path": "reference/player_tick_phases.json", **fingerprint(ROOT / "reference/player_tick_phases.json")},
                        inputs_sha256=digest(canonical(incoming)), cases_full_sha256=reference["cases_full_sha256"],
                        probe_sha256=digest(Path(__file__).read_bytes()),
                        imported_producer_sha256=digest(Path(LI.__file__).read_bytes()),
                        api_sources_sha256={p: digest((ROOT / p).read_bytes()) for p in API_FILES},
                        client_jar=fingerprint(CLIENT), java_runtime=fingerprint(JAVA),
                        external_service_boundary="Unchanged four LI service fixtures; normally constructed real ClientLevel/player/input. No additional service mocks. Observer methods call super. Pose/metadata snapshots observe effects, not model them.")
        write_json(ROOT / "evidence/player-tick-phases-observed.json", evidence)
        print(json.dumps({key: evidence[key] for key in ["status", "histories", "actual_entry_calls", "successful_calls", "failures", "phase_snapshots"]}, indent=2))
        return
    print(json.dumps({"status": result["status"], "classes": len(result["classes"]),
                      "methods": sum(len(c["methods"]) for c in result["classes"].values()),
                      "raw_sha256": result["raw_artifact"]["sha256"]}, indent=2))


if __name__ == "__main__":
    main()
