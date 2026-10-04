#!/usr/bin/env python3
"""Derive a compact, independent static block resource catalog from pinned 26.3.

Official Java APIs supply schemas, instantiated blockstate roots and dependencies.
Python joins those observations to the official generated registry and summarizes
model inheritance, texture slots and alpha/layer requirements. Raw resource JSON,
decoded pixels, Java outputs and logs remain under ignored build/. This is an
oracle extractor, not a game implementation or a claim of rendering parity.
"""
from __future__ import annotations

import argparse
import collections
import csv
import hashlib
import io
import itertools
import json
import pathlib
import subprocess
import zipfile

from PIL import Image

from reference_inventory import ROOT, JAVA, canonical, fingerprint
from reference_model_probe import CLIENT, verified_client_classpath

BLOCKS = ("stone", "dirt", "oak_planks", "grass_block", "oak_log", "oak_slab",
          "oak_stairs", "oak_fence", "cobblestone", "sand", "bricks", "glass",
          "water", "chest")
DIR = ROOT / "build/resource-block-catalog-reference"
FIXTURE = ROOT / "reference/resource_block_catalog.json"
EVIDENCE = ROOT / "evidence/resource-block-catalog-reference.json"

JAVA_SOURCE = r'''
import com.google.gson.*;
import com.mojang.serialization.JsonOps;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.resources.Identifier;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.Property;
import net.minecraft.client.renderer.block.dispatch.*;
import net.minecraft.client.renderer.block.dispatch.multipart.MultiPartModel;
import net.minecraft.util.random.WeightedList;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.zip.*;

class ResourceBlockCatalogReference {
 static final Gson G=new GsonBuilder().serializeNulls().disableHtmlEscaping().create();
 static JsonElement desc(Object value)throws Exception {
  if(value==null)return JsonNull.INSTANCE;
  if(value instanceof Number v)return new JsonPrimitive(v);
  if(value instanceof Boolean v)return new JsonPrimitive(v);
  if(value instanceof String v)return new JsonPrimitive(v);
  if(value instanceof Identifier||value instanceof Enum<?>)return new JsonPrimitive(value.toString());
  if(value instanceof Optional<?> v)return desc(v.orElse(null));
  if(value instanceof WeightedList<?> v)return desc(v.unwrap());
  if(value instanceof Map<?,?> v){var out=new JsonObject();for(var e:v.entrySet())out.add(e.getKey().toString(),desc(e.getValue()));return out;}
  if(value instanceof Iterable<?> v){var out=new JsonArray();for(var e:v)out.add(desc(e));return out;}
  if(value.getClass().isRecord()){var out=new JsonObject();out.addProperty("class",value.getClass().getName());for(var component:value.getClass().getRecordComponents()){var accessor=component.getAccessor();accessor.setAccessible(true);out.add(component.getName(),desc(accessor.invoke(value)));}return out;}
  throw new IllegalArgumentException("Unexpected observation class "+value.getClass().getName());
 }
 @SuppressWarnings({"rawtypes","unchecked"})
 static JsonObject observe(ZipFile jar,String name)throws Exception {
  var id=Identifier.parse("minecraft:"+name);var block=BuiltInRegistries.BLOCK.getValue(id);var definition=block.getStateDefinition();
  var schema=new JsonObject();schema.addProperty("owner",block.toString());var properties=new JsonObject();
  for(var pp:definition.getProperties()){Property p=pp;var property=new JsonObject();property.addProperty("integer",p.getValueClass()==Integer.class);var domain=new JsonArray();for(var value:p.getPossibleValues())domain.add(p.getName((Comparable)value));property.add("values",domain);properties.add(p.getName(),property);}schema.add("properties",properties);
  var entry=jar.getEntry("assets/minecraft/blockstates/"+name+".json");
  var raw=new String(jar.getInputStream(entry).readAllBytes(),java.nio.charset.StandardCharsets.UTF_8);
  var parsed=BlockStateModelDispatcher.CODEC.parse(JsonOps.INSTANCE,JsonParser.parseString(raw)).getOrThrow();
  var roots=parsed.instantiate(definition,()->"resource-catalog:"+name);var out=new JsonObject();out.add("schema",schema);
  var selectors=new JsonArray();
  if(parsed.simpleModels().isPresent())for(var e:parsed.simpleModels().get().models().entrySet()){var row=new JsonObject();row.addProperty("kind","variant");row.addProperty("selector",e.getKey());row.add("choice",desc(e.getValue()));var matches=new JsonArray();var predicate=VariantSelector.predicate(definition,e.getKey());for(var state:definition.getPossibleStates())if(predicate.test(state))matches.add(Block.getId(state));row.add("matches",matches);selectors.add(row);}
  if(parsed.multiPart().isPresent()){int index=0;for(var part:parsed.multiPart().get().selectors()){var row=new JsonObject();row.addProperty("kind","multipart");row.addProperty("index",index++);row.add("condition",desc(part.condition()));row.add("choice",desc(part.variant()));var matches=new JsonArray();var predicate=part.instantiate(definition);for(var state:definition.getPossibleStates())if(predicate.test(state))matches.add(Block.getId(state));row.add("matches",matches);selectors.add(row);}}
  out.add("selectors",selectors);var states=new JsonArray();
  for(var state:definition.getPossibleStates()){var row=new JsonObject();row.addProperty("id",Block.getId(state));var values=new JsonObject();for(var pp:definition.getProperties()){Property p=pp;values.addProperty(p.getName(),p.getName(state.getValue(p)));}row.add("properties",values);
   row.addProperty("render_shape",state.getRenderShape().name());row.addProperty("has_block_entity",state.hasBlockEntity());var fluid=state.getFluidState();var fluidInfo=new JsonObject();fluidInfo.addProperty("identifier",BuiltInRegistries.FLUID.getKey(fluid.getType()).toString());fluidInfo.addProperty("amount",fluid.getAmount());fluidInfo.addProperty("source",fluid.isSource());row.add("fluid",fluidInfo);
   var root=roots.get(state);row.addProperty("mapped",root!=null);
   if(root!=null){var dependencies=new TreeSet<String>();root.resolveDependencies(model->dependencies.add(model.toString()));row.add("dependencies",desc(dependencies));
    if(root instanceof BlockStateModel.SimpleCachedUnbakedRoot){var field=root.getClass().getDeclaredField("contents");field.setAccessible(true);row.add("choice",desc(field.get(root)));}
    else if(root instanceof MultiPartModel.Unbaked){var key=root.visualEqualityGroup(state);var accessor=key.getClass().getDeclaredMethod("selectors");accessor.setAccessible(true);row.add("parts",desc(accessor.invoke(key)));}
    else throw new IllegalArgumentException("Unexpected root class "+root.getClass().getName());
   }states.add(row);
  }out.add("states",states);out.addProperty("block_protocol_id",BuiltInRegistries.BLOCK.getId(block));out.addProperty("default_state_id",Block.getId(block.defaultBlockState()));return out;
 }
 public static void main(String[] args)throws Exception {
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();var out=new JsonObject();
  try(var jar=new ZipFile(args[0])){for(int i=2;i<args.length;i++)out.add(args[i],observe(jar,args[i]));}
  Files.writeString(Path.of(args[1]),G.toJson(out));
 }
}
'''


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def rid(value: str) -> str:
    return value if ":" in value else "minecraft:" + value


def resource_path(identifier: str, category: str, suffix: str) -> str:
    namespace, path = rid(identifier).split(":", 1)
    return f"assets/{namespace}/{category}/{path}{suffix}"


def choice_projection(value: dict) -> dict:
    def variant(v: dict) -> dict:
        state = v["modelState"]
        return {"model": v["modelLocation"], **{axis: int(state[axis][1:]) for axis in "xyz"},
                "uvlock": state["uvLock"]}
    if value["class"].endswith("SingleVariant$Unbaked"):
        return {"kind": "single", "variant": variant(value["variant"])}
    assert value["class"].endswith("WeightedVariants$Unbaked"), value
    entries = [{"variant": variant(e["value"]["variant"]), "weight": e["weight"]}
               for e in value["entries"]]
    return {"kind": "weighted", "total": sum(e["weight"] for e in entries), "entries": entries}


def condition_projection(value: dict | None) -> dict | None:
    if value is None:
        return None
    tokens = []
    def visit(node):
        if node["class"].endswith("KeyValueCondition"):
            tokens.append({"kind": "keys", "tests": {k: [{"value": t["value"], "negated": t["negated"]}
                           for t in terms["entries"]] for k, terms in node["tests"].items()}})
        else:
            assert node["class"].endswith("CombinedCondition"), node
            tokens.append({"kind": node["operation"].lower(), "count": len(node["terms"])})
            for term in node["terms"]:
                visit(term)
    visit(value)
    return {"tokens": tokens}


def choice_models(choice: dict) -> list[str]:
    variants = [choice["variant"]] if choice["kind"] == "single" else [e["variant"] for e in choice["entries"]]
    return sorted({v["model"] for v in variants})


def roots_models(root: dict) -> list[str]:
    choices = [root["choice"]] if root["kind"] == "variant" else [p["choice"] for p in root["parts"]]
    return sorted({model for choice in choices for model in choice_models(choice)})


def verify_sources() -> tuple[list[pathlib.Path], dict, dict]:
    cp, runtime = verified_client_classpath()
    release = json.loads((ROOT / "reference/release.json").read_text())
    inventory = json.loads((ROOT / "evidence/reference_inventory.json").read_text())
    tables = {}
    for name in ("blocks", "registries", "resources"):
        relative = f"generated/reference_{name}.tsv"
        got = fingerprint(ROOT / relative)
        expected = inventory["generated_tables"][relative]
        assert all(got[k] == expected[k] for k in ("bytes", "sha1", "sha256")), relative
        tables[relative] = got
    reports = {}
    for name in ("blocks.json", "registries.json"):
        path = ROOT / "reference/reports/reports" / name
        raw = path.read_bytes()
        got = {"bytes": len(raw), "canonical_json_sha256": digest(canonical(json.loads(raw)))}
        assert got == release["reports"]["principal_reports"][name], name
        reports["reference/reports/reports/" + name] = got
    metadata = json.loads((ROOT / "reference/release.json").read_text())["client"]
    got = fingerprint(CLIENT)
    assert got["sha1"] == metadata["official"]["sha1"] and got["bytes"] == metadata["official"]["size"]
    classes = {}
    with zipfile.ZipFile(CLIENT) as jar:
        for path in ("net/minecraft/client/renderer/block/dispatch/BlockStateModelDispatcher.class",
                     "net/minecraft/client/renderer/block/dispatch/VariantSelector.class",
                     "net/minecraft/client/renderer/block/dispatch/BlockStateModel$SimpleCachedUnbakedRoot.class",
                     "net/minecraft/client/resources/model/cuboid/FaceBakery.class",
                     "net/minecraft/client/resources/model/sprite/Material.class",
                     "net/minecraft/client/renderer/chunk/ChunkSectionLayer.class",
                     "net/minecraft/client/color/block/BlockTintSources$4.class",
                     "net/minecraft/world/level/block/LiquidBlock.class",
                     "net/minecraft/client/renderer/block/FluidStateModelSet.class",
                     "net/minecraft/client/renderer/block/FluidRenderer.class",
                     "net/minecraft/client/renderer/blockentity/ChestRenderer.class"):
            raw = jar.read(path)
            classes[path] = {"bytes": len(raw), "sha256": digest(raw)}
    return cp, runtime, {"tables": tables, "official_reports": reports,
                         "client": got, "version_metadata": runtime["metadata"], "classes": classes}


def observe_java(cp: list[pathlib.Path]) -> tuple[dict, dict]:
    DIR.mkdir(parents=True, exist_ok=True)
    source = DIR / "ResourceBlockCatalogReference.java"
    source.write_text(JAVA_SOURCE)
    outputs = []
    runs = []
    for run in (1, 2):
        output = DIR / f"java-{run}.json"
        command = [str(JAVA), "-cp", ":".join(map(str, cp)), str(source), str(CLIENT), str(output), *BLOCKS]
        result = subprocess.run(command, cwd=DIR, capture_output=True, text=True, timeout=120)
        (DIR / f"java-{run}.stdout.log").write_text(result.stdout)
        (DIR / f"java-{run}.stderr.log").write_text(result.stderr)
        if result.returncode:
            raise RuntimeError(f"Java observation failed ({result.returncode}): {result.stderr[-4000:]}")
        outputs.append(json.loads(output.read_text()))
        runs.append({"output_sha256": digest(canonical(outputs[-1])), "exit_code": result.returncode})
    assert outputs[0] == outputs[1], "Independent Java runs differ"
    return outputs[0], {"harness_sha256": digest(JAVA_SOURCE.encode()), "runs": runs,
                        "classpath_manifest_sha256": digest(canonical([str(p) for p in cp]))}


def official_registry() -> dict:
    blocks = json.loads((ROOT / "reference/reports/reports/blocks.json").read_text())
    registries = json.loads((ROOT / "reference/reports/reports/registries.json").read_text())
    with (ROOT / "generated/reference_blocks.tsv").open() as source:
        rows = {row["identifier"].split(":", 1)[1]: row for row in csv.DictReader(source, delimiter="\t")}
    out = {}
    for name in BLOCKS:
        row = rows[name]
        identifier = row["identifier"]
        properties = json.loads(row["ordered_properties_json"])
        combinations = itertools.product(*(p["values"] for p in properties))
        states = [{"id": int(row["first_state_id"]) + offset,
                   "properties": {p["name"]: v for p, v in zip(properties, values)}}
                  for offset, values in enumerate(combinations)]
        raw = blocks[identifier]
        assert states == [{"id": s["id"], "properties": s.get("properties", {})} for s in raw["states"]]
        assert len(states) == int(row["state_count"])
        assert [s["id"] for s in raw["states"] if s.get("default")] == [int(row["default_state_id"])]
        assert registries["minecraft:block"]["entries"][identifier]["protocol_id"] == int(row["block_protocol_id"])
        out[name] = {"identifier": identifier, **{field: int(row[field]) for field in
                     ("block_protocol_id", "first_state_id", "state_count", "default_state_id")},
                     "ordered_properties": properties, "states": states}
    return out


def summarize_resources(observed: dict) -> tuple[dict, dict, dict]:
    models, textures, resources = {}, {}, {}
    raw_models = {}
    with (ROOT / "generated/reference_resources.tsv").open() as source:
        manifest = {r["logical_path"]: r for r in csv.DictReader(source, delimiter="\t") if r["source"] == "client_jar"}
    with zipfile.ZipFile(CLIENT) as jar:
        paths = set(jar.namelist())
        def read(path):
            value = jar.read(path)
            record = {"sha256": digest(value), "bytes": len(value)}
            expected = manifest[path]
            assert record["sha256"] == expected["content_hash"] and record["bytes"] == int(expected["bytes"]), path
            resources[path] = record
            return value
        def texture(identifier):
            identifier = rid(identifier)
            if identifier in textures:
                return textures[identifier]
            path = resource_path(identifier, "textures", ".png")
            raw = read(path)
            with Image.open(io.BytesIO(raw)) as image:
                rgba = image.convert("RGBA")
                alpha = rgba.getchannel("A").tobytes()
                record = {"resource": path, "width": image.width, "height": image.height,
                          "alpha_min": min(alpha), "alpha_max": max(alpha),
                          "alpha_zero_pixels": alpha.count(0),
                          "alpha_partial_pixels": sum(0 < value < 255 for value in alpha)}
            record["alpha_mode"] = "translucent" if record["alpha_partial_pixels"] else "cutout" if record["alpha_zero_pixels"] else "opaque"
            metadata_path = path + ".mcmeta"
            record["animated"] = False
            if metadata_path in paths:
                metadata = json.loads(read(metadata_path))
                record["metadata_sections"] = sorted(metadata)
                record["animated"] = "animation" in metadata
            textures[identifier] = record
            return record
        def load_model(identifier):
            identifier = rid(identifier)
            if identifier in raw_models:
                return
            path = resource_path(identifier, "models", ".json")
            value = json.loads(read(path))
            raw_models[identifier] = value
            if "parent" in value:
                load_model(value["parent"])
        for name in BLOCKS:
            read(f"assets/minecraft/blockstates/{name}.json")
            for state in observed[name]["states"]:
                for model in state["dependencies"]:
                    load_model(model)
        def summarize_model(identifier):
            chain = []
            current = identifier
            while current is not None:
                assert current not in chain, (identifier, chain)
                chain.append(current)
                current = rid(raw_models[current]["parent"]) if "parent" in raw_models[current] else None
            slots, elements, geometry_owner = {}, [], None
            for current in reversed(chain):
                value = raw_models[current]
                slots.update(value.get("textures", {}))
                if "elements" in value:
                    elements, geometry_owner = value["elements"], current
            def resolve(slot):
                seen = []
                if slot not in slots:
                    return {"sprite": None, "force_translucent": False, "layer": "unbound", "unresolved_slot": slot}
                value = slots[slot]
                while isinstance(value, str) and value.startswith("#"):
                    key = value[1:]
                    assert key not in seen, (identifier, slot, key)
                    if key not in slots:
                        return {"sprite": None, "force_translucent": False, "layer": "unbound", "unresolved_slot": key}
                    seen.append(key)
                    value = slots[key]
                material = {"sprite": rid(value), "force_translucent": False} if isinstance(value, str) else {
                    "sprite": rid(value["sprite"]), "force_translucent": value.get("force_translucent", False)}
                alpha = texture(material["sprite"])
                material["layer"] = "translucent" if material["force_translucent"] or alpha["alpha_mode"] == "translucent" else "cutout" if alpha["alpha_mode"] == "cutout" else "solid"
                return material
            resolved_slots = {key: resolve(key) for key in sorted(slots)}
            layers, usage = collections.Counter(), {}
            tinted, cullfaces, directions = collections.Counter(), collections.Counter(), collections.Counter()
            for element in elements:
                for direction, face in element.get("faces", {}).items():
                    key = face["texture"]
                    material = resolved_slots.get(key[1:], resolve(key[1:])) if key.startswith("#") else {"sprite": rid(key), "force_translucent": False}
                    if "layer" not in material:
                        alpha = texture(material["sprite"])
                        material["layer"] = "translucent" if alpha["alpha_mode"] == "translucent" else "cutout" if alpha["alpha_mode"] == "cutout" else "solid"
                    layers[material["layer"]] += 1
                    tint = face.get("tintindex", -1)
                    if tint != -1:
                        tinted[str(tint)] += 1
                    cullfaces[face.get("cullface", "none")] += 1
                    directions[direction] += 1
                    signature = (material["sprite"], material["layer"], tint)
                    if signature not in usage:
                        usage[signature] = {"sprite": material["sprite"], "layer": material["layer"], "tintindex": tint, "faces": 0}
                    usage[signature]["faces"] += 1
            return {"resource": resource_path(identifier, "models", ".json"),
                    "parent": rid(raw_models[identifier]["parent"]) if "parent" in raw_models[identifier] else None,
                    "chain": chain, "textures": resolved_slots,
                    "geometry": {"owner": geometry_owner, "element_count": len(elements),
                                 "face_count": sum(layers.values()), "faces_by_layer": dict(sorted(layers.items())),
                                 "faces_by_direction": dict(sorted(directions.items())),
                                 "faces_by_cullface": dict(sorted(cullfaces.items())),
                                 "tint_index_face_counts": dict(sorted(tinted.items())),
                                 "texture_usage": [usage[key] for key in sorted(usage, key=lambda key: (key[0] or "", key[1], key[2]))]}}
        for identifier in sorted(raw_models):
            models[identifier] = summarize_model(identifier)
    return models, textures, resources


def support(name: str, state: dict, models: dict) -> dict:
    if name == "water":
        assert state["render_shape"] == "INVISIBLE" and state["fluid"]["identifier"] != "minecraft:empty"
        return {"classification": "unsupported_fluid", "supported": False,
                "caveats": ["Fluid surfaces, height, flow, biome tint, animation and translucent rendering require the fluid renderer; static model has no geometry."]}
    if name == "chest":
        assert state["render_shape"] == "MODEL" and state["has_block_entity"]
        return {"classification": "unsupported_block_entity", "supported": False,
                "caveats": ["Chest body, lid motion and single/double texture selection require the chest block entity renderer; static model has no geometry."]}
    selected = roots_models(state["root"])
    assert state["render_shape"] == "MODEL" and not state["has_block_entity"]
    layers = sorted({layer for model in selected for layer in models[model]["geometry"]["faces_by_layer"]})
    if "translucent" in layers:
        return {"classification": "unsupported_translucent", "supported": False, "layers": layers,
                "static_loader_error": "UnsupportedMetadata",
                "caveats": ["26.3 glass texture material explicitly forces translucent rendering despite binary source alpha; sorting/blending is outside the static solid/cutout catalog.",
                            "Official glass texture metadata requests mipmap_strategy=mean; the current StaticNormalized loader rejects nonempty metadata."]}
    caveats = ["Support describes static resource assembly; lighting, culling, atlas sampling, mipmaps and native presentation remain separate parity obligations."]
    if name == "grass_block" and state["properties"]["snowy"] == "false":
        caveats.append("Tint index 0 affects the top and four cutout side-overlay faces; biome/block color application is required.")
    if state["properties"].get("waterlogged") == "true":
        caveats.append("Only the static block component is supported; the waterlogged fluid component requires the fluid renderer.")
    if state["root"]["kind"] == "variant" and state["root"]["choice"]["kind"] == "weighted":
        caveats.append("Weighted choices must use the pinned position/random selection semantics; fixture lists choices without fixing a random outcome.")
    return {"classification": "supported_static_cutout" if "cutout" in layers else "supported_static_solid",
            "supported": True, "layers": layers, "caveats": caveats}


def derive(observed: dict, sources: dict) -> dict:
    registry = official_registry()
    models, textures, resources = summarize_resources(observed)
    blocks = {}
    for name in BLOCKS:
        java, block = observed[name], registry[name]
        assert java["block_protocol_id"] == block["block_protocol_id"]
        assert java["default_state_id"] == block["default_state_id"]
        assert [{"id": s["id"], "properties": s["properties"]} for s in java["states"]] == block["states"]
        assert {p["name"]: p["values"] for p in block["ordered_properties"]} == {
            k: p["values"] for k, p in java["schema"]["properties"].items()}
        variants, parts, order, matches = {}, [], [], []
        for selector in java["selectors"]:
            choice = choice_projection(selector["choice"])
            if selector["kind"] == "variant":
                variants[selector["selector"]] = choice
                order.append(selector["selector"])
                matches.append({"selector": selector["selector"], "state_ids": selector["matches"]})
            else:
                assert selector["index"] == len(parts)
                parts.append({"condition": condition_projection(selector["condition"]), "choice": choice})
                matches.append({"part_index": selector["index"], "state_ids": selector["matches"]})
        states = []
        for value in java["states"]:
            assert value["mapped"], (name, value["id"])
            root = {"kind": "variant", "choice": choice_projection(value["choice"])} if "choice" in value else {
                "kind": "multipart", "parts": [{"index": index, "choice": parts[index]["choice"]} for index in value["parts"]]}
            state = {"id": value["id"], "properties": value["properties"], "root": root,
                     "dependencies": value["dependencies"], "selected_models": roots_models(root),
                     "render_shape": value["render_shape"], "has_block_entity": value["has_block_entity"], "fluid": value["fluid"]}
            # Production multipart root dependencies include every selector's model,
            # while selected_models includes only the parts active for this state.
            assert set(state["selected_models"]) <= set(state["dependencies"])
            state["support"] = support(name, state, models)
            if state["support"]["supported"]:
                assert all(models[m]["geometry"]["face_count"] > 0 and
                           "unbound" not in models[m]["geometry"]["faces_by_layer"] for m in state["selected_models"])
            states.append(state)
        blocks[name] = {k: v for k, v in block.items() if k != "states"} | {
            "schema": java["schema"], "states": states,
            "blockstate": {"resource": f"assets/minecraft/blockstates/{name}.json",
                           "definition": {"variants": variants or None, "selector_order": order or None,
                                          "multipart": parts or None}, "selector_matches": matches},
            "models": sorted({model for s in states for model in s["dependencies"]}),
            "support_classifications": dict(sorted(collections.Counter(s["support"]["classification"] for s in states).items()))}
    supported_blocks = [name for name in BLOCKS if all(state["support"]["supported"] for state in blocks[name]["states"])]
    profile_models = sorted({model for name in supported_blocks for root in blocks[name]["models"] for model in models[root]["chain"]})
    profile_textures = {material["sprite"]: material["layer"] for name in supported_blocks for root in blocks[name]["models"]
                        for material in models[root]["textures"].values() if material["sprite"] is not None}
    assert len(profile_textures) == 12 and all(layer in ("solid", "cutout") for layer in profile_textures.values())
    return {"schema": 1, "pin": "26.3", "authority": "Pinned official Java dispatcher/state APIs, official generated blocks/registries reports, and jar resource metadata/alpha summaries.",
            "scope": "All official states of 14 chosen blocks; static model resources only. Support classification is a catalog boundary, not a full renderer parity claim.",
            "sources": sources, "blocks": blocks, "models": models, "textures": textures, "resources": resources,
            "static_solid_cutout_profile": {"blocks": supported_blocks, "models": profile_models,
                "sprite_layers": dict(sorted(profile_textures.items())),
                "states": sum(blocks[name]["state_count"] for name in supported_blocks),
                "unsupported_requests": {"glass": "UnsupportedMetadata", "water": "fluid", "chest": "block_entity"},
                "caveat": "Waterlogged block states include the static block component only; grass world tint and position RNG remain separate inputs."}}


def crosscheck_previous_production_bakes(fixture: dict) -> dict:
    """Validate summaries against the existing independent production FaceBakery run.

    These 110 controlled-atlas observations cover the original eight-block corpus;
    they establish layer/sprite/tint face metadata only, not the atlas or frames.
    """
    path = ROOT / "reference/model_semantics.json"
    reference = json.loads(path.read_text())
    assert reference["pin"] == "26.3"
    assert reference["provenance"]["client"] == fixture["sources"]["client"]
    for section in ("inputs", "observations"):
        assert digest(canonical(reference[section])) == reference[section + "_sha256"]
    with zipfile.ZipFile(CLIENT) as jar:
        for cls in reference["source"]["classes"]:
            raw = jar.read(cls["class"].replace(".", "/") + ".class")
            assert len(raw) == cls["bytes"] and digest(raw) == cls["sha256"]
    matched, variants = set(), 0
    for case in reference["observations"]["baked_variants"]:
        model = case["input"]["model"]
        if case["status"] != "ok" or model not in fixture["models"]:
            continue
        quads = [quad for group in case["result"]["quad_groups"].values() for quad in group]
        actual = collections.Counter((quad["sprite"], quad["layer"].lower(), quad["tint_index"]) for quad in quads)
        expected = {(usage["sprite"], usage["layer"], usage["tintindex"]): usage["faces"]
                    for usage in fixture["models"][model]["geometry"]["texture_usage"]}
        assert actual == expected, (model, actual, expected)
        assert len(quads) == fixture["models"][model]["geometry"]["face_count"]
        matched.add(model)
        variants += 1
    assert variants == 110 and len(matched) == 14
    return {"fixture": str(path.relative_to(ROOT)), "fixture_sha256": fingerprint(path)["sha256"],
            "observations_sha256": reference["observations_sha256"], "matched_baked_variants": variants,
            "matched_models": sorted(matched), "scope": "Production CPU bake face counts, material layers, sprites and tint indices under controlled normalized atlas."}


def summary(fixture: dict) -> dict:
    states = [state for block in fixture["blocks"].values() for state in block["states"]]
    return {"blocks": len(fixture["blocks"]), "states": len(states), "models": len(fixture["models"]),
            "textures": len(fixture["textures"]), "resources": len(fixture["resources"]),
            "support_classifications": dict(sorted(collections.Counter(s["support"]["classification"] for s in states).items())),
            "weighted_state_roots": sum(s["root"]["kind"] == "variant" and s["root"]["choice"]["kind"] == "weighted" for s in states),
            "multipart_state_roots": sum(s["root"]["kind"] == "multipart" for s in states),
            "tinted_models": sorted(name for name, model in fixture["models"].items() if model["geometry"]["tint_index_face_counts"])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true", help="Re-observe Java and compare committed fixture/evidence without rewriting")
    args = parser.parse_args()
    cp, runtime, sources = verify_sources()
    observed, java = observe_java(cp)
    fixture = derive(observed, sources)
    geometry_crosscheck = crosscheck_previous_production_bakes(fixture)
    payload = canonical(fixture) + b"\n"
    evidence = {"schema": 1, "pin": "26.3", "reproduce": "python3 tools/resource_block_catalog_reference.py --verify",
                "extractor_sha256": fingerprint(pathlib.Path(__file__))["sha256"],
                "fixture": {"path": str(FIXTURE.relative_to(ROOT)), "sha256": digest(payload), "bytes": len(payload)},
                "sources": sources, "java": java | {"runtime": runtime["java"], "version": runtime["java_version"],
                    "verified_libraries_sha256": digest(canonical(runtime["libraries"]))},
                "summary": summary(fixture),
                "geometry_crosscheck": geometry_crosscheck,
                "checks": {"official_client_sha1_size_sha256": True, "official_registry_report_hashes": True,
                    "generated_table_hashes": True, "selected_resource_hashes_match_official_inventory": True,
                    "tsv_states_equal_official_report_and_java_states": True, "java_runs_reproduce": True,
                    "all_selected_states_mapped": True, "all_selected_model_dependencies_resolved": True,
                    "summaries_match_existing_production_java_geometry": True,
                    "no_raw_assets_or_pixels_in_fixture": True},
                "limits": ["Model geometry is summarized; no proprietary model source, texture bytes or pixels are committed.",
                    "No Bend/native build, atlas bake or visible client session is executed by this reference extractor.",
                    "PNG alpha gives source texture requirements; force_translucent overrides alpha and mipmap/render behavior remains separately tested.",
                    "Weighted roots retain all official choices and weights; no fixed seed/position selects a single outcome here."]}
    if args.verify:
        assert FIXTURE.read_bytes() == payload, "Committed fixture differs from fresh official observation"
        assert json.loads(EVIDENCE.read_text()) == evidence, "Committed evidence differs from reproduced metadata"
    else:
        FIXTURE.write_bytes(payload)
        EVIDENCE.write_text(json.dumps(evidence, sort_keys=True, indent=2) + "\n")
    print(json.dumps({"mode": "verify" if args.verify else "extract", **evidence["summary"],
                      "fixture_sha256": evidence["fixture"]["sha256"]}, sort_keys=True))


if __name__ == "__main__":
    main()
