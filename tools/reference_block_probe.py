#!/usr/bin/env python3
"""Probe pinned Java block-state physics and shapes in declared empty contexts.

This extracts Java reference observations only. It neither simulates Minecraft
nor establishes that an empty-context shape is valid for all worlds/entities.
"""
from __future__ import annotations

import argparse
import collections
import csv
import hashlib
import json
import pathlib
import re
import math
import struct
import shutil
import sys
import tempfile
import subprocess
import zipfile

from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json, write_tsv

SOURCE = r'''import java.io.*;
import java.nio.file.*;
import java.lang.reflect.*;
import java.util.*;
import com.google.gson.Gson;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.EmptyBlockGetter;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.Property;
import net.minecraft.world.level.material.FluidState;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.shapes.CollisionContext;
import net.minecraft.world.phys.shapes.VoxelShape;

class ReferenceBlockProbe {
    static final Gson JSON = new Gson();
    static final BlockGetter EMPTY = EmptyBlockGetter.INSTANCE;
    static final CollisionContext CONTEXT = CollisionContext.empty();
    static final BlockPos ORIGIN = BlockPos.ZERO;
    static final BlockPos OTHER = new BlockPos(7, 11, -13);
    static String f64(double value) { return String.format(Locale.ROOT, "%016x", Double.doubleToRawLongBits(value)); }
    static Map<String,String> floating(float value) {
        return Map.of("f32_bits", String.format(Locale.ROOT, "%08x", Float.floatToRawIntBits(value)), "promoted_f64_bits", f64((double)value));
    }
    static <T extends Comparable<T>> String propertyValue(Property<T> property, BlockState state) { return property.getName(state.getValue(property)); }
    static String owner(Class<?> type, String method, Class<?>... arguments) {
        while (type != null) {
            try { return type.getDeclaredMethod(method, arguments).getDeclaringClass().getName(); }
            catch (NoSuchMethodException ignored) { type = type.getSuperclass(); }
        }
        throw new IllegalStateException("Missing source method " + method);
    }
    interface ShapeCall { VoxelShape get(); }
    static Map<String,Object> shape(ShapeCall call) {
        try {
            List<List<String>> boxes = new ArrayList<>();
            for (AABB box : call.get().toAabbs()) boxes.add(List.of(f64(box.minX), f64(box.minY), f64(box.minZ), f64(box.maxX), f64(box.maxY), f64(box.maxZ)));
            return Map.of("aabbs_f64_bits", boxes);
        } catch (RuntimeException error) {
            return Map.of("error_class", error.getClass().getName(), "error_message", String.valueOf(error.getMessage()));
        }
    }
    static class TraceGetter implements BlockGetter {
        final Map<String,Integer> reads = new TreeMap<>();
        void hit(String method) { reads.merge(method,1,Integer::sum); }
        public BlockEntity getBlockEntity(BlockPos pos) { hit("getBlockEntity"); return EMPTY.getBlockEntity(pos); }
        public BlockState getBlockState(BlockPos pos) { hit("getBlockState"); return EMPTY.getBlockState(pos); }
        public FluidState getFluidState(BlockPos pos) { hit("getFluidState"); return EMPTY.getFluidState(pos); }
        public int getMinY() { hit("getMinY"); return EMPTY.getMinY(); }
        public int getHeight() { hit("getHeight"); return EMPTY.getHeight(); }
    }
    public static void main(String[] args) throws Exception {
        SharedConstants.tryDetectVersion();
        Bootstrap.bootStrap();
        Set<String> selected = new HashSet<>();
        if (args.length > 1 && !args[1].isEmpty()) selected.addAll(Arrays.asList(args[1].split(",")));
        Set<Block> seen = new HashSet<>();
        try (PrintWriter output = new PrintWriter(Files.newBufferedWriter(Path.of(args[0])))) {
            for (int id = 0; id < Block.BLOCK_STATE_REGISTRY.size(); id++) {
                BlockState state = Block.stateById(id);
                Block block = state.getBlock();
                String identifier = BuiltInRegistries.BLOCK.getKey(block).toString();
                if (!selected.isEmpty() && !selected.contains(identifier)) continue;
                if (seen.add(block)) {
                    Map<String,Object> b = new TreeMap<>();
                    b.put("kind", "block"); b.put("identifier", identifier); b.put("block_protocol_id", BuiltInRegistries.BLOCK.getId(block));
                    b.put("block_class", block.getClass().getName()); b.put("default_state_id", Block.getId(block.defaultBlockState()));
                    Map<String,String> owners = new TreeMap<>();
                    for (String method : List.of("getShape", "getCollisionShape", "getVisualShape")) owners.put(method, owner(block.getClass(), method, BlockState.class, BlockGetter.class, BlockPos.class, CollisionContext.class));
                    for (String method : List.of("getBlockSupportShape", "getInteractionShape", "getShadeBrightness")) owners.put(method, owner(block.getClass(), method, BlockState.class, BlockGetter.class, BlockPos.class));
                    for (String method : List.of("getFriction", "getSpeedFactor", "getJumpFactor", "getExplosionResistance", "getBounceRestitution", "getFallDistanceReduction")) owners.put(method, owner(block.getClass(), method));
                    b.put("method_owners", owners);
                    Map<String,String> stateOwners = new TreeMap<>();
                    for (String method : List.of("getLightEmission", "getLightDampening", "isSolidRender", "canOcclude", "requiresCorrectToolForDrops", "propagatesSkylightDown", "emissiveRendering", "liquid", "isAir", "isSolid", "getRenderShape", "isRandomlyTicking", "hasOffsetFunction")) stateOwners.put(method, owner(state.getClass(), method));
                    for (String method : List.of("getDestroySpeed", "getShadeBrightness")) stateOwners.put(method, owner(state.getClass(), method, BlockGetter.class, BlockPos.class));
                    b.put("state_method_owners", stateOwners); output.println(JSON.toJson(b));
                }
                Map<String,Object> r = new TreeMap<>();
                r.put("kind", "state"); r.put("state_id", id); r.put("identifier", identifier);
                Map<String,String> properties = new TreeMap<>();
                for (Property<?> property : state.getProperties()) properties.put(property.getName(), propertyValue(property, state));
                r.put("properties", properties);
                r.put("hardness", floating(state.getDestroySpeed(EMPTY, ORIGIN)));
                r.put("resistance", floating(block.getExplosionResistance()));
                r.put("friction", floating(block.getFriction()));
                r.put("speed_factor", floating(block.getSpeedFactor()));
                r.put("jump_factor", floating(block.getJumpFactor()));
                r.put("bounce_restitution", floating(block.getBounceRestitution()));
                r.put("fall_distance_reduction", floating(block.getFallDistanceReduction()));
                r.put("shade_brightness", floating(state.getShadeBrightness(EMPTY, ORIGIN)));
                r.put("light_emission", state.getLightEmission()); r.put("light_dampening", state.getLightDampening());
                r.put("air", state.isAir()); r.put("liquid", state.liquid()); r.put("solid", state.isSolid());
                r.put("can_occlude", state.canOcclude()); r.put("solid_render", state.isSolidRender());
                r.put("shape_light_occlusion", state.useShapeForLightOcclusion()); r.put("skylight_down", state.propagatesSkylightDown());
                r.put("emissive_rendering", state.emissiveRendering()); r.put("requires_correct_tool", state.requiresCorrectToolForDrops());
                r.put("replaceable", state.canBeReplaced()); r.put("randomly_ticking", state.isRandomlyTicking());
                r.put("has_block_entity", state.hasBlockEntity()); r.put("dynamic_shape", block.hasDynamicShape()); r.put("has_offset", state.hasOffsetFunction());
                r.put("render_shape", state.getRenderShape().name()); r.put("push_reaction", state.getPistonPushReaction().name());
                FluidState fluid = state.getFluidState();
                r.put("fluid", BuiltInRegistries.FLUID.getKey(fluid.getType()).toString()); r.put("fluid_amount", fluid.getAmount()); r.put("fluid_source", fluid.isSource());
                Map<String,Object> shapes = new TreeMap<>();
                shapes.put("collision_empty_origin", shape(() -> state.getCollisionShape(EMPTY, ORIGIN, CONTEXT)));
                shapes.put("outline_empty_origin", shape(() -> state.getShape(EMPTY, ORIGIN, CONTEXT)));
                shapes.put("occlusion", shape(state::getOcclusionShape));
                shapes.put("support_empty_origin", shape(() -> state.getBlockSupportShape(EMPTY, ORIGIN)));
                shapes.put("collision_empty_other_position", shape(() -> state.getCollisionShape(EMPTY, OTHER, CONTEXT)));
                shapes.put("outline_empty_other_position", shape(() -> state.getShape(EMPTY, OTHER, CONTEXT)));
                shapes.put("collision_position_context_2", shape(() -> state.getCollisionShape(EMPTY, ORIGIN, CollisionContext.positionContext(2.0))));
                shapes.put("collision_fluid_context", shape(() -> state.getCollisionShape(EMPTY, ORIGIN, CollisionContext.emptyWithFluidCollisions())));
                TraceGetter collisionTrace = new TraceGetter();
                shapes.put("collision_trace_empty_origin", shape(() -> state.getCollisionShape(collisionTrace, ORIGIN, CONTEXT)));
                TraceGetter outlineTrace = new TraceGetter();
                shapes.put("outline_trace_empty_origin", shape(() -> state.getShape(outlineTrace, ORIGIN, CONTEXT)));
                r.put("shapes", shapes); r.put("collision_world_reads", collisionTrace.reads); r.put("outline_world_reads", outlineTrace.reads);
                output.println(JSON.toJson(r));
            }
            if (output.checkError()) throw new IOException("Reference output write failed");
        }
    }
}
'''

FLOAT_FIELDS = ["hardness", "resistance", "friction", "speed_factor", "jump_factor", "bounce_restitution", "fall_distance_reduction", "shade_brightness"]
FLAGS = ["air", "liquid", "solid", "can_occlude", "solid_render", "shape_light_occlusion", "skylight_down", "emissive_rendering", "requires_correct_tool", "replaceable", "randomly_ticking", "has_block_entity", "dynamic_shape", "has_offset", "fluid_source"]
SHAPES = ["collision_empty_origin", "outline_empty_origin", "occlusion", "support_empty_origin", "collision_empty_other_position", "outline_empty_other_position", "collision_position_context_2", "collision_fluid_context", "collision_trace_empty_origin", "outline_trace_empty_origin"]


def verified_classpath() -> tuple[list[pathlib.Path], dict]:
    release = json.loads((ROOT / "reference/release.json").read_text())
    cache = ROOT / "reference/cache"
    bundle = cache / "26.3-server.jar"
    server = cache / "versions/26.3/server-26.3.jar"
    if fingerprint(bundle)["sha256"] != release["server_bundle"]["sha256"] or fingerprint(server)["sha256"] != release["server_bundle"]["nested_server_sha256"]:
        raise ValueError("Pinned server artifact checksum mismatch")
    jars = [server]
    with zipfile.ZipFile(bundle) as archive:
        for line in archive.read("META-INF/libraries.list").decode().splitlines():
            sha, _, relative = line.split("\t")
            path = cache / "libraries" / relative
            if fingerprint(path)["sha256"] != sha:
                raise ValueError("Pinned server library checksum mismatch")
            jars.append(path)
    return jars, release


def source_dependencies(jars: list[pathlib.Path], blocks: dict) -> dict:
    owners = sorted(set(owner for record in blocks.values() for field in ["method_owners", "state_method_owners"] for owner in record[field].values()))
    result = subprocess.run([str(JAVA.parent / "javap"), "-classpath", str(jars[0]), "-c", "-p", *owners], capture_output=True, text=True, check=True)
    (ROOT / "reference/cache/block-method-bytecode.txt").write_text(result.stdout)
    chunks = result.stdout.split('Compiled from "')[1:]
    if len(chunks) != len(owners):
        raise ValueError("Unexpected block-owner javap report topology")
    relevant = {method for record in blocks.values() for field in ["method_owners", "state_method_owners"] for method in record[field]}
    records = {}
    for owner, chunk in zip(owners, chunks):
        if owner not in chunk.splitlines()[1]:
            raise ValueError("Unexpected block-owner javap declaration")
        methods = re.findall(r"^  ((?:public|protected|private).*?\([^\n]*\);)\n(.*?)(?=^  (?:public|protected|private|static)|\Z)", chunk, re.M | re.S)
        for signature, body in methods:
            match = re.search(r"([\w$<>]+)\([^\n]*\);$", signature)
            if not match or match[1] not in relevant:
                continue
            method = match[1]
            calls = sorted(set(re.findall(r"// (?:InterfaceMethod|Method) (.+)", body)))
            fields = sorted(set(re.findall(r"// Field (.+)", body)))
            categories = []
            if any(any(marker in call for marker in ["BlockGetter.", "LevelReader.", "LevelAccessor.", "Level."]) for call in calls):
                categories.append("world_or_neighbor_read_direct_or_delegated")
            if any(any(marker in call for marker in ["CollisionContext.isAbove:", "CollisionContext.isDescending:", "CollisionContext.isHoldingItem:", "CollisionContext.canStandOnFluid:", "CollisionContext.alwaysCollideWithFluid:", "CollisionContext.isPlacement:", "CollisionContext.getCollisionShape:", "EntityCollisionContext.getEntity:"]) for call in calls):
                categories.append("collision_context_or_entity_dependency")
            if any("CollisionContext.empty:" in call for call in calls):
                categories.append("fixed_empty_collision_context_used")
            if any("getOffset" in call or "BlockPos." in call for call in calls):
                categories.append("position_dependency")
            if any("getShape" in call or "getCollisionShape" in call or "apply:" in call for call in calls):
                categories.append("delegation_requires_further_analysis")
            records[owner + "#" + signature] = {"owner": owner, "method": method, "signature": signature,
                                                  "direct_call_references": calls, "field_references": fields, "dependency_categories": categories,
                                                  "bytecode_text_sha256": hashlib.sha256(body.encode()).hexdigest(),
                                                  "analysis_scope": "direct references only; absence of a marker is not proof of context independence"}
    return records


def verify_outputs() -> dict:
    metadata = json.loads((ROOT / "reference/block_physics.json").read_text())
    table = ROOT / "generated/reference_block_physics.tsv"
    if fingerprint(table)["sha256"] != metadata["table"]["sha256"]:
        raise ValueError("Block physics table SHA-256 mismatch")
    with table.open() as stream:
        rows = list(csv.DictReader(stream, delimiter="\t"))
    if len(rows) != metadata["states_probed"]:
        raise ValueError("Block physics table row-count mismatch")
    shapes = metadata["shape_dictionary"]
    if set(shapes) != set(map(str, range(len(shapes)))):
        raise ValueError("Block shape dictionary IDs are not contiguous")
    checksums = []
    endpoints, primitives = 0, 0
    for index in range(len(shapes)):
        shape = shapes[str(index)]
        value = {key: item for key, item in shape.items() if key != "content_sha256"}
        if hashlib.sha256(canonical(value)).hexdigest() != shape["content_sha256"]:
            raise ValueError("Block shape dictionary content SHA-256 mismatch")
        checksums.append(shape["content_sha256"])
        for box in shape.get("aabbs_f64_bits", []):
            if len(box) != 6 or any(not re.fullmatch("[0-9a-f]{16}", bits) for bits in box):
                raise ValueError("Invalid float64 AABB encoding")
            numbers = [struct.unpack(">d", bytes.fromhex(bits))[0] for bits in box]
            if any(not math.isfinite(value) for value in numbers) or any(numbers[axis] > numbers[axis + 3] for axis in range(3)):
                raise ValueError("Nonfinite or inverted block AABB")
            endpoints += 6
    if checksums != sorted(checksums):
        raise ValueError("Shape dictionary IDs are not in checksum order")
    official = json.loads((ROOT / "reference/reports/reports/blocks.json").read_text())
    expected = {state["id"]: identifier for identifier, block in official.items() if identifier in metadata["blocks"] for state in block["states"]}
    rows_by_id = {}
    for row in rows:
        state_id = int(row["state_id"])
        if state_id in rows_by_id or expected.get(state_id) != row["block_identifier"]:
            raise ValueError("Block physics state ID/identifier mismatch or duplicate")
        rows_by_id[state_id] = row
        for field in FLOAT_FIELDS:
            f32, f64 = row[field + "_f32_bits"], row[field + "_promoted_f64_bits"]
            if not re.fullmatch("[0-9a-f]{8}", f32) or not re.fullmatch("[0-9a-f]{16}", f64):
                raise ValueError("Invalid block floating property encoding")
            value = struct.unpack(">f", bytes.fromhex(f32))[0]
            if not math.isfinite(value) or struct.pack(">d", value).hex() != f64:
                raise ValueError("Block float32-to-float64 widening mismatch")
            primitives += 1
        for name in SHAPES:
            if row[name + "_shape_id"] not in shapes:
                raise ValueError("Missing block shape dictionary reference")
        if any(row[name] not in {"0", "1"} for name in FLAGS):
            raise ValueError("Invalid block flag encoding")
    if rows_by_id.keys() != expected.keys():
        raise ValueError("Block physics table misses official states")
    raw = ROOT / "reference/cache/block-probe.jsonl"
    observed_ids = set()
    if raw.exists():
        with raw.open() as stream:
            for line in stream:
                record = json.loads(line)
                if record["kind"] != "state":
                    continue
                state_id = record["state_id"]
                if state_id not in rows_by_id or state_id in observed_ids:
                    raise ValueError("Cached Java block observations differ from table coverage")
                observed_ids.add(state_id)
                row = rows_by_id[state_id]
                for field in FLOAT_FIELDS:
                    for encoding in ["f32_bits", "promoted_f64_bits"]:
                        if row[field + "_" + encoding] != record[field][encoding]:
                            raise ValueError("Block floating property differs from Java observation")
                for name in SHAPES:
                    observed_hash = hashlib.sha256(canonical(record["shapes"][name])).hexdigest()
                    if shapes[row[name + "_shape_id"]]["content_sha256"] != observed_hash:
                        raise ValueError("Block shape differs from Java observation")
                for name in FLAGS:
                    if int(row[name]) != int(record[name]):
                        raise ValueError("Block flag differs from Java observation")
        if observed_ids != rows_by_id.keys():
            raise ValueError("Cached Java block observations miss table states")
    evidence = {"pin": "26.3", "kind": "block_reference_extraction_verification", "states_verified": len(rows),
                "source_float32_to_float64_values_verified": primitives, "shape_dictionary_records_verified": len(shapes),
                "shape_float64_endpoints_verified": endpoints, "cached_java_state_records_compared": len(observed_ids),
                "table_sha256": fingerprint(table)["sha256"], "reproduce": "python3 tools/reference_block_probe.py --verify-existing",
                "bend_behavioral_parity_established": False}
    write_json(ROOT / "evidence/reference_block_validation.json", evidence)
    return evidence


def selftest() -> None:
    global ROOT
    original_root = ROOT
    script = original_root / "tools/reference_block_probe.py"
    command = [sys.executable, str(script)]
    paths = [original_root / name for name in ["generated/reference_block_physics.tsv", "reference/block_physics.json", "evidence/reference_block_probe.json", "evidence/reference_block_validation.json"]]
    subprocess.run(command, capture_output=True, text=True, check=True)
    before = {str(path.relative_to(original_root)): fingerprint(path)["sha256"] for path in paths}
    subprocess.run(command, capture_output=True, text=True, check=True)
    after = {str(path.relative_to(original_root)): fingerprint(path)["sha256"] for path in paths}
    if before != after:
        raise ValueError("Block reference outputs are not byte reproducible")
    failures = []
    with tempfile.TemporaryDirectory(prefix="minecraft-26.3-block-reference-check-") as tmp:
        temporary = pathlib.Path(tmp)
        for folder in ["reference", "generated", "evidence"]:
            (temporary / folder).mkdir()
        (temporary / "reference/reports").symlink_to(original_root / "reference/reports", target_is_directory=True)
        table = temporary / "generated/reference_block_physics.tsv"
        metadata_path = temporary / "reference/block_physics.json"
        shutil.copy2(paths[0], table)
        shutil.copy2(paths[1], metadata_path)
        metadata = json.loads(metadata_path.read_text())
        # Replacing a widened Java 0.6f by a double literal 0.6 is a real
        # fidelity failure; the numbers only appear equal when rounded.
        data = table.read_bytes()
        if b"3fe3333340000000" not in data:
            raise ValueError("Default friction widening fixture not found")
        table.write_bytes(data.replace(b"3fe3333340000000", b"3fe3333333333333", 1))
        ROOT = temporary
        def rejected(label: str, expected_message: str) -> None:
            try:
                verify_outputs()
            except ValueError as error:
                if expected_message not in str(error):
                    raise
                failures.append({"mutation": label, "expected_rejection": expected_message, "rejected": True})
            else:
                raise ValueError("Block reference verifier accepted deliberate corruption")
        try:
            rejected("Replace a widened 0.6f by float64 literal 0.6", "table SHA-256 mismatch")
            metadata["table"]["sha256"] = fingerprint(table)["sha256"]
            write_json(metadata_path, metadata)
            rejected("Same wrong widening with checksum updated", "float32-to-float64 widening mismatch")
            shutil.copy2(paths[0], table)
            metadata = json.loads(paths[1].read_text())
            shape = next(value for value in metadata["shape_dictionary"].values() if value.get("aabbs_f64_bits") == [["0000000000000000"] * 3 + ["3ff0000000000000"] * 3])
            shape["aabbs_f64_bits"][0][3] = "bff0000000000000"  # maxX=-1, minX=0
            shape["content_sha256"] = hashlib.sha256(canonical({key: value for key, value in shape.items() if key != "content_sha256"})).hexdigest()
            write_json(metadata_path, metadata)
            rejected("Invert full-cube maxX with shape checksum updated", "inverted block AABB")
        finally:
            ROOT = original_root
    evidence = {"pin": "26.3", "kind": "block_reference_reproducibility_and_failure_checks", "full_java_probe_runs": 2,
                "outputs_reproduced": after, "corruption_checks": failures, "reproduce": "python3 tools/reference_block_probe.py --selftest",
                "bend_behavioral_parity_established": False}
    write_json(original_root / "evidence/reference_block_selftest.json", evidence)
    print(json.dumps({"outputs_reproduced": len(after), "corruption_failures_rejected": len(failures)}, sort_keys=True))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blocks", default="", help="Comma-separated representative block identifiers; default probes all states")
    parser.add_argument("--verify-existing", action="store_true", help="Independently read/check current table and shape dictionary without rerunning Java")
    parser.add_argument("--selftest", action="store_true", help="Rerun all-state Java probe twice and test checksum, widening and AABB corruption failures")
    args = parser.parse_args()
    if args.selftest:
        selftest()
        return
    selected = set(filter(None, args.blocks.split(",")))
    jars, release = verified_classpath()
    if args.verify_existing:
        print(json.dumps(verify_outputs(), sort_keys=True))
        return
    folder = ROOT / "reference/extracted/probes"
    folder.mkdir(parents=True, exist_ok=True)
    source = folder / "ReferenceBlockProbe.java"
    source.write_text(SOURCE)
    raw = ROOT / "reference/cache/block-probe.jsonl"
    command = [str(JAVA), "--class-path", ":".join(map(str, jars)), str(source), str(raw), args.blocks]
    process = subprocess.run(command, capture_output=True, text=True)
    (ROOT / "reference/cache/block-probe.log").write_text(process.stdout + process.stderr)
    if process.returncode:
        raise RuntimeError(f"Pinned Java block probe failed ({process.returncode}); see reference/cache/block-probe.log")
    block_records, state_records = {}, []
    for line in raw.read_text().splitlines():
        record = json.loads(line)
        if record["kind"] == "block":
            block_records[record["identifier"]] = record
        else:
            state_records.append(record)
    official_blocks = json.loads((ROOT / "reference/reports/reports/blocks.json").read_text())
    official_registries = json.loads((ROOT / "reference/reports/reports/registries.json").read_text())
    if selected - official_blocks.keys():
        raise ValueError("Requested representative block not in pinned registry")
    expected = {state["id"]: (identifier, state.get("properties", {})) for identifier, record in official_blocks.items()
                if not selected or identifier in selected for state in record["states"]}
    if len(expected) != len(state_records):
        raise ValueError("Java block state probe coverage mismatch")
    seen_ids = set()
    for record in state_records:
        state_id = record["state_id"]
        if state_id in seen_ids or (record["identifier"], record["properties"]) != expected[state_id]:
            raise ValueError("Java block state ID/property mismatch against official report")
        seen_ids.add(state_id)
    for identifier, record in block_records.items():
        official_id = official_registries["minecraft:block"]["entries"][identifier]["protocol_id"]
        if record["block_protocol_id"] != official_id:
            raise ValueError("Java block protocol ID mismatch")
    source_methods = source_dependencies(jars, block_records)
    shapes, errors, rows = {}, [], []
    variation, flags, reads = collections.Counter(), collections.Counter(), collections.Counter()
    block_observations = collections.defaultdict(collections.Counter)
    for record in state_records:
        ids = {}
        for name in SHAPES:
            value = record["shapes"][name]
            key = hashlib.sha256(canonical(value)).hexdigest()
            shapes.setdefault(key, value)
            ids[name] = key
            if "error_class" in value:
                errors.append({"state_id": record["state_id"], "identifier": record["identifier"], "query": name, **value})
        changes = {"collision_changes_with_position": ids["collision_empty_origin"] != ids["collision_empty_other_position"],
                   "outline_changes_with_position": ids["outline_empty_origin"] != ids["outline_empty_other_position"],
                   "collision_changes_with_position_context": ids["collision_empty_origin"] != ids["collision_position_context_2"],
                   "collision_changes_with_fluid_context": ids["collision_empty_origin"] != ids["collision_fluid_context"],
                   "collision_changes_with_trace_getter": ids["collision_empty_origin"] != ids["collision_trace_empty_origin"],
                   "outline_changes_with_trace_getter": ids["outline_empty_origin"] != ids["outline_trace_empty_origin"]}
        variation.update(name for name, value in changes.items() if value)
        block_observations[record["identifier"]].update(name for name, value in changes.items() if value)
        block_observations[record["identifier"]].update({"states_probed": 1, "dynamic_shape_states": int(record["dynamic_shape"]), "offset_states": int(record["has_offset"]),
                                                        "collision_world_read_states": int(bool(record["collision_world_reads"])), "outline_world_read_states": int(bool(record["outline_world_reads"]))})
        flags.update(name for name in FLAGS if record[name])
        reads.update("collision:" + name for name in record["collision_world_reads"])
        reads.update("outline:" + name for name in record["outline_world_reads"])
        row = [record["state_id"], record["identifier"]]
        row += [record[field][encoding] for field in FLOAT_FIELDS for encoding in ["f32_bits", "promoted_f64_bits"]]
        row += [record["light_emission"], record["light_dampening"], record["render_shape"], record["push_reaction"], record["fluid"], record["fluid_amount"]]
        row += [int(record[name]) for name in FLAGS]
        row += [ids[name] for name in SHAPES]
        row += [record["collision_world_reads"], record["outline_world_reads"]]
        row += [int(changes[name]) for name in changes]
        rows.append(row)
    headers = ["state_id", "block_identifier"] + [field + "_" + encoding for field in FLOAT_FIELDS for encoding in ["f32_bits", "promoted_f64_bits"]]
    headers += ["light_emission", "light_dampening", "render_shape", "push_reaction", "fluid_identifier", "fluid_amount"] + FLAGS
    headers += [name + "_shape_id" for name in SHAPES] + ["collision_world_reads_json", "outline_world_reads_json"] + list(changes)
    ordered_shape_hashes = sorted(shapes)
    shape_indexes = {sha: index for index, sha in enumerate(ordered_shape_hashes)}
    shape_columns = [index for index, header in enumerate(headers) if header.endswith("_shape_id")]
    for row in rows:
        for index in shape_columns:
            row[index] = shape_indexes[row[index]]
    shape_dictionary = {str(shape_indexes[sha]): {"content_sha256": sha, **shapes[sha]} for sha in ordered_shape_hashes}
    for identifier, block in block_records.items():
        block["observed_state_classification_counts"] = dict(sorted(block_observations[identifier].items()))
        classifications = {}
        for query, method in [("collision", "getCollisionShape"), ("outline", "getShape"), ("support", "getBlockSupportShape"), ("shade_brightness", "getShadeBrightness")]:
            owner = block["method_owners"][method]
            matching = [record for record in source_methods.values() if record["owner"] == owner and record["method"] == method]
            classifications[query] = {"declaring_owner": owner, "detected_direct_dependency_categories": sorted(set(category for record in matching for category in record["dependency_categories"])),
                                      "scope": "declared empty-world/context observation; absence of a direct dependency marker does not establish independence"}
        block["shape_source_classification"] = classifications
    path = ROOT / "generated/reference_block_physics.tsv"
    write_tsv(path, headers, rows)
    metadata = {"pin": "26.3", "reference_only": True, "blocks_probed": len(block_records), "states_probed": len(state_records), "all_pinned_states_probed": not selected,
                "blocks": block_records, "shape_dictionary": shape_dictionary, "source_method_dependencies": source_methods,
                "contexts": {"world": "EmptyBlockGetter.INSTANCE: AIR everywhere, empty fluids, no block entities; not a placed-block world",
                             "origin": [0, 0, 0], "other_position": [7, 11, -13], "collision": "CollisionContext.empty()",
                             "alternatives": ["CollisionContext.positionContext(2.0)", "CollisionContext.emptyWithFluidCollisions()"],
                             "trace": "BlockGetter wrapper returning EmptyBlockGetter results; getter calls counted independently"},
                "floating_encoding": {"primitive_properties": "Source float32 bits plus exact Java widening to float64 bits", "aabb_endpoints": "Double.doubleToRawLongBits, 16 lowercase hexadecimal digits, minX,minY,minZ,maxX,maxY,maxZ", "shape_dictionary_ids": "Zero-based indexes of SHA256-sorted canonical shape records; full SHA256 stored per dictionary record, AABB decomposition and traversal order retained"},
                "state_flag_counts": dict(sorted(flags.items())), "context_variation_state_counts": dict(sorted(variation.items())), "world_getter_read_state_counts": dict(sorted(reads.items())),
                "query_errors": errors, "table": fingerprint(path) | {"rows": len(rows)},
                "limits": ["Every queried shape has the declared context. Unchanged sampled contexts do not prove universal world/entity independence.",
                           "hasDynamicShape and hasOffsetFunction are official flags, not a complete classification of dependencies.",
                           "Source dependency analysis records direct bytecode method/field references only; delegation, callbacks, lambdas and predicates require further analysis.",
                           "Hardness is the state destroySpeed value; player/tool/effect-dependent break progress and explosion effects are not implemented or verified.",
                           "AABB shape extraction does not establish movement, collision traversal order, epsilon rules, rendering or physics transitions."]}
    write_json(ROOT / "reference/block_physics.json", metadata)
    evidence = {"pin": "26.3", "kind": "java_reference_block_physics_observation", "blocks_probed": len(block_records), "states_probed": len(state_records),
                "all_ids_and_properties_match_official_reports": True, "all_pinned_states_probed": not selected, "unique_shape_records": len(shapes),
                "source_methods_examined": len(source_methods), "context_variation_state_counts": dict(sorted(variation.items())), "query_error_count": len(errors),
                "table_sha256": fingerprint(path)["sha256"], "probe_source_sha256": hashlib.sha256(SOURCE.encode()).hexdigest(),
                "reference_server_sha256": release["server_bundle"]["nested_server_sha256"], "reproduce": "python3 tools/reference_block_probe.py" + (" --blocks " + args.blocks if args.blocks else ""),
                "process_exit_code": process.returncode, "bend_behavioral_parity_established": False}
    write_json(ROOT / "evidence/reference_block_probe.json", evidence)
    verify_outputs()
    print(json.dumps({key: evidence[key] for key in ["blocks_probed", "states_probed", "unique_shape_records", "source_methods_examined", "context_variation_state_counts", "query_error_count"]}, sort_keys=True))


if __name__ == "__main__":
    main()
