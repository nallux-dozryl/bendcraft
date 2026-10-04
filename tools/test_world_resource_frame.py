#!/usr/bin/env python3
"""Prepare sealed WorldResourceFrame tests without executing native programs.

Only fixtures and independent reference expectations are computed here. The
native input contains original V.Sample readbacks, a jar path, and test modes;
expected Java quads and Pillow pixels are kept in a separate oracle file.
"""
from __future__ import annotations

import argparse
import copy
import datetime
import hashlib
import io
import json
import math
import re
import struct
import sys
import zipfile
import zlib
from fractions import Fraction
from pathlib import Path

import numpy as np
from PIL import Image, __version__ as PILLOW_VERSION

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "build/world-resource-frame"
RECEIPT = ROOT / "evidence/world-resource-frame-preparation.json"
JAR = Path.home() / "Library/Application Support/minecraft/versions/26.3/26.3.jar"
HANDOFF = ROOT / "build/world-visibility-oracle/actual-sampler-samples.json"
MODEL_REFERENCE = ROOT / "reference/model_semantics.json"
VISIBILITY_REFERENCE = ROOT / "reference/world_visibility.json"
WV_EVIDENCE = ROOT / "evidence/world-visibility-native.json"
RF_DRAW_EVIDENCE = ROOT / "evidence/resource-frame-draw-native.json"
RF_FULL_EVIDENCE = ROOT / "evidence/resource-frame-native.json"
BEND = Path.home() / ".bend/bin/bend"
COMPILER_SOURCE = ROOT.parent / "bend/bend2/comp.ts"
PINS = {
    JAR: "4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d",
    HANDOFF: "a3b53695f498bd07d0e7e3afe8d083f5911b511b8f4622ec1835cd784910ed50",
    MODEL_REFERENCE: "3cbe8aa7780f14c1b37159a885710b04680e3b6c4ffa4975b4d8297015f11e7e",
    VISIBILITY_REFERENCE: "c81f6e26110d2275905a6d94f30462935814e8951fdd8e6c10f9a084febacbde",
    WV_EVIDENCE: "241e54fd3e722abdbbf6f512d90b8a42bb991b91ef65b349e28c2a768615fef1",
    RF_FULL_EVIDENCE: "ea6798bcad7cc3ef84837681fa6d39688498105dae5686a373c9b01171330887",
}
MODELS = ["minecraft:block/dirt", "minecraft:block/oak_planks", "minecraft:block/stone"]
STATE_NAMES = ["minecraft:air", "minecraft:stone", "minecraft:dirt", "minecraft:oak_planks"]
DIRECTIONS = ["down", "up", "north", "south", "west", "east"]
SLOTS = {name: index for index, name in enumerate(MODELS)}
DEFAULT_LIMITS = [4096, 1024, 4096, 64, 256]
SAMPLE_ERROR = "Visibility:SampleAlignment:0,0,0,0:0:raw-relative-mask-mismatch"
SAMPLE_FIELDS = {"tick", "revision", "blocks", "camera", "raw", "masks", "origin", "palette", "reads"}


def require(value, message):
    if not value:
        raise AssertionError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def digest(path):
    with path.open("rb") as source:
        value = hashlib.sha256()
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def relative(path):
    return str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)


def canonical(value):
    return json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":")).encode()


def save_or_check(path, data, verify):
    if verify:
        require(path.is_file() and path.read_bytes() == data, "prepared file is missing/stale: " + relative(path))
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return {"path": relative(path), "bytes": len(data), "sha256": sha(data)}


def source_fingerprints():
    pending = [ROOT / "src/world_resource_frame.bend", ROOT / "tests/world_resource_frame.bend"]
    values = {}
    while pending:
        path = pending.pop().resolve()
        if relative(path) in values:
            continue
        data = path.read_bytes()
        values[relative(path)] = sha(data)
        for name in re.findall(r"^import\s+(\.[^\s]+\.bend)", data.decode(), re.MULTILINE):
            pending.append(path.parent / name)
    values[relative(Path(__file__).resolve())] = digest(Path(__file__).resolve())
    values[relative(COMPILER_SOURCE)] = digest(COMPILER_SOURCE)
    values[relative(BEND)] = digest(BEND)
    return dict(sorted(values.items()))


def u32(value):
    return type(value) is int and 0 <= value <= 0xffffffff


def signed(value):
    return value if value < 0x80000000 else value - 0x100000000


def f(value):
    return np.float32(value)


def word(value):
    return struct.unpack("<I", struct.pack("<f", value))[0]


def unw(value):
    return struct.unpack("<f", struct.pack("<I", value))[0]


def double(value):
    return struct.unpack(">d", struct.pack(">II", *value))[0]


def validate_sample(sample):
    require(set(sample) == SAMPLE_FIELDS, "sample field set")
    for name in ("tick", "revision", "reads"):
        require(u32(sample[name]), "sample test DTO U32 " + name)
    for name, width in (("blocks", 5), ("raw", 6), ("masks", 6)):
        require(all(len(row) == width and all(map(u32, row)) for row in sample[name]), "sample words " + name)
    for name, width in (("camera", 5), ("origin", 6), ("palette", 4)):
        require(len(sample[name]) == width and all(map(u32, sample[name])), "sample words " + name)
    require(len(set(sample["palette"])) == 4, "sealed sample palette distinct")
    require(sample["reads"] == 6 * len(sample["raw"]), "sealed sample six reads per block")
    require(len(sample["raw"]) == len(sample["masks"]) == len(sample["blocks"]), "sealed sample list lengths")
    origin = [double(sample["origin"][i:i + 2]) for i in range(0, 6, 2)]
    require(all(math.isfinite(value) for value in origin), "sealed sample finite origin")
    for raw, mask, block in zip(sample["raw"], sample["masks"], sample["blocks"]):
        require(raw[:5] == mask[:5] and raw[3] <= 3 and mask[5] <= 63, "lossless cell boundary/state/mask")
        material = sample["palette"].index(raw[4]) - 1
        require(material >= 0 and raw[5] == material, "sealed sample material matches palette")
        position = [word(float(Fraction(signed(cell)) - Fraction.from_float(eye))) for cell, eye in zip(raw[:3], origin)]
        require(block == [*position, raw[4], raw[5]], "independent exact signed-cell relative position")
    require(len({tuple(row[:3]) for row in sample["raw"]}) == len(sample["raw"]), "sealed raw cells unique")


def references():
    for path, expected in PINS.items():
        require(digest(path) == expected, "pinned input changed: " + relative(path))
    handoff = json.loads(HANDOFF.read_text())
    passed = json.loads(WV_EVIDENCE.read_text())
    resources = json.loads(RF_FULL_EVIDENCE.read_text())
    require(resources["status"] == "passed_bounded_domain" and resources["two_native_runs_equal"] is True,
            "prior resource-frame projected readback receipt passed twice")
    for name, expected in resources["native_source_fingerprint"].items():
        path = BEND if name == "pinned_compiler_sha256" else ROOT / name
        require(digest(path) == expected, "prior RF readback dependency changed: " + name)
    require(passed["status"] == "passed_split_native_integration", "sealed sampler evidence passed")
    require(passed["actual_sampler_samples"] == {"path": relative(HANDOFF), "sha256": PINS[HANDOFF]}, "sampler handoff provenance")
    # The runner framing correction after the handoff did not change the 36
    # compiled/reference dependencies; its separate receipt records that fact.
    for name, expected in handoff["source_sha256"].items():
        if name != "tools/test_world_visibility.py":
            require(digest(ROOT / name) == expected, "native Sample dependency changed: " + name)
    require(handoff["sampler_binary_sha256"] == "5ab7ea1d2b6db7ac95a19ff3013ecce3a68e69a8a02d393e51023d08f0164dab", "sampler artifact origin")
    model = json.loads(MODEL_REFERENCE.read_text())
    visibility = json.loads(VISIBILITY_REFERENCE.read_text())
    quads, textures, entries = {}, [], {}
    with zipfile.ZipFile(JAR) as archive:
        def check_model(identifier):
            namespace, path = identifier.split(":", 1)
            name = f"assets/{namespace}/models/{path}.json"
            if name in entries:
                return
            data = archive.read(name)
            require(data.decode() == model["inputs"]["models"][identifier], "original model bytes " + identifier)
            entries[name] = {"bytes": len(data), "sha256": sha(data)}
            parent = json.loads(data).get("parent")
            if parent:
                check_model(parent if ":" in parent else "minecraft:" + parent)

        for identifier in MODELS:
            check_model(identifier)
            baked = next(record for record in model["observations"]["baked_variants"] if record["input"] == {"model": identifier})
            require(baked["status"] == "ok" and baked["result"]["quad_count"] == 6, "six actual Java cube faces")
            groups = baked["result"]["quad_groups"]
            require(not groups["unculled"], "closed cube groups")
            quads[identifier] = []
            for direction in DIRECTIONS:
                require(len(groups[direction]) == 1, "one face per measured cull group")
                value = groups[direction][0]
                require(value["sprite"] == identifier and value["layer"] == "SOLID" and value["tint_index"] == -1
                        and value["material_flags"] == value["light_emission"] == 0, "closed RF appearance domain")
                quads[identifier].append(value)
            namespace, path = identifier.split(":", 1)
            name = f"assets/{namespace}/textures/{path}.png"
            data = archive.read(name)
            with Image.open(io.BytesIO(data)) as image:
                rgba = np.array(image.convert("RGBA"), dtype=np.uint8)
            require(rgba.shape == (16, 16, 4) and np.all(rgba[:, :, 3] == 255), "opaque source PNG dimensions")
            entries[name] = {"bytes": len(data), "sha256": sha(data), "rgba_sha256": sha(rgba.tobytes())}
            textures.append(rgba)
    return handoff, passed, visibility, quads, textures, entries


def java_masks(group, name, sample, visibility):
    if group == "empty-known-air":
        require(not sample["raw"], "empty actual sample")
        return []
    if group in ("official", "alternate"):
        scene_id = "fixture-edited-40" if name in ("raw-edit", "uncached") else "fixture-39"
    elif group.startswith("far-"):
        scene_id = "halo-edge-far-" + str(int(group[4:]) // 4)
    else:
        scene_id = "halo-edge-origin"
    scene = next(record for record in visibility["observations"]["scenes"] if record["id"] == scene_id)
    expected = []
    require(len(scene["blocks"]) == len(sample["raw"]), "Java scene block count")
    for actual, block in zip(sample["raw"], scene["blocks"]):
        require(actual[:3] == block["position_u32"] and actual[4] == sample["palette"][STATE_NAMES.index(block["state"])], "Java raw position/state")
        mask = block["visible_direction_mask"]
        if group == "halo-cache-edit" and name in ("halo-edit", "halo-recached"):
            # The native edit changes the external Down neighbor to air. Use
            # the actual Java pair observation for that edited adjacency.
            pair = next(record for record in visibility["observations"]["state_pair_matrix"]
                        if record["current"] == block["state"] and record["adjacent"] == "minecraft:air" and record["direction_ordinal"] == 0)
            require(pair["should_render_face"] is True, "measured edited Down face")
            mask |= 1
        expected.append([*actual[:5], mask])
    require(sample["masks"] == expected, "actual mask differs from independent Java observations: " + group + "/" + name)
    return expected


def quad_words(quad, position, order):
    words = []
    for vertex in quad["vertices"]:
        words.extend(word(f(f(unw(int(value, 16))) + f(unw(origin)))) for value, origin in zip(vertex["position_f32"], position))
        words.extend(int(value, 16) for value in vertex["uv_f32"])
    return [*words, SLOTS[quad["sprite"]], 0xffffffff, 0xffffffff,
            int(quad["default_directional_brightness_f32"], 16), 0, 0, 0, 1, order]


def expected_quads(sample, java_quads):
    models = dict(zip(sample["palette"][1:], (MODELS[2], MODELS[0], MODELS[1])))
    result = []
    for index, (block, mask) in enumerate(zip(sample["blocks"], sample["masks"])):
        for direction, quad in enumerate(java_quads[models[block[3]]]):
            if mask[5] & (1 << direction):
                result.append(quad_words(quad, block[:3], 6 * index + direction))
    return result


def expected_assets(palette, java_quads, textures):
    """Full comparison-only readbacks; these never enter RF.load input."""
    expected = {"textures": {}, "bindings": {}, "baked": {}}
    for slot, texture in enumerate(textures):
        packed = ((texture[:, :, 3].astype(np.uint32) << 24) | (texture[:, :, 0].astype(np.uint32) << 16)
                  | (texture[:, :, 1].astype(np.uint32) << 8) | texture[:, :, 2].astype(np.uint32))
        expected["textures"][str(slot)] = {"dimensions": [16, 16, 16], "pixels": packed.reshape(-1).tolist()}
    for state, model in zip(palette[1:], (MODELS[2], MODELS[0], MODELS[1])):
        expected["bindings"][str(state)] = {"appearance": [0xffffffff, 0, 1, 0, 128], "tints": []}
        baked = []
        for cull_group, quad in enumerate(java_quads[model]):
            vertex_words = [int(value, 16) for vertex in quad["vertices"]
                            for value in [*vertex["position_f32"], *vertex["uv_f32"]]]
            override = quad["shade_direction_override"]
            baked.append({"sprite": quad["sprite"], "vertices": vertex_words,
                          "metadata": [DIRECTIONS.index(quad["direction"]), cull_group, SLOTS[quad["sprite"]],
                                       quad["tint_index"] & 0xffffffff, quad["light_emission"],
                                       0xffffffff if override is None else DIRECTIONS.index(override),
                                       0, 0, 0, int(quad["default_directional_brightness_f32"], 16),
                                       int(quad["nether_directional_brightness_f32"], 16)]})
        expected["baked"][str(state)] = baked
    return expected


# Independent triangle/ray oracle, with explicit float32 grouping, actual Java
# faces and Pillow texels. It performs no game state or resource implementation.
def cross(a, b):
    return np.stack([a[..., 1] * b[..., 2] - a[..., 2] * b[..., 1],
                     a[..., 2] * b[..., 0] - a[..., 0] * b[..., 2],
                     a[..., 0] * b[..., 1] - a[..., 1] * b[..., 0]], axis=-1)


def dot(a, b):
    return a[..., 0] * b[..., 0] + (a[..., 1] * b[..., 1] + a[..., 2] * b[..., 2])


def directions(camera, width, height):
    x, y = np.meshgrid(np.arange(width, dtype=np.float32), np.arange(height, dtype=np.float32))
    yaw, pitch = map(unw, camera[3:])
    sy, cy, sp, cp = map(f, (math.sin(yaw), math.cos(yaw), math.sin(pitch), math.cos(pitch)))
    scale = f(.7002075382)
    u = ((x + f(.5)) * f(2) / f(width) - f(1)) * (scale * (f(width) / f(height)))
    v = (f(1) - (y + f(.5)) * f(2) / f(height)) * scale
    dx = -sy * cp + (cy * u + (-sy * sp) * v)
    dy = -sp + cp * v
    dz = cy * cp + (sy * u + (cy * sp) * v)
    length = np.sqrt(dx * dx + (dy * dy + dz * dz), dtype=np.float32)
    return np.stack([dx / length, dy / length, dz / length], axis=-1).reshape(-1, 3)


def triangle(vertices, origin, rays):
    position, uv = vertices[:, :3], vertices[:, 3:]
    edge_a, edge_b = position[1] - position[0], position[2] - position[0]
    pv = cross(rays, edge_b)
    det = dot(edge_a, pv)
    with np.errstate(divide="ignore", invalid="ignore"):
        inv = f(1) / det
        tvec = origin - position[0]
        u = dot(tvec, pv) * inv
        qv = cross(tvec, edge_a)
        v = dot(rays, qv) * inv
        depth = dot(edge_b, qv) * inv
        hit = (det > f(1e-8)) & (u >= 0) & (u <= 1) & (v >= 0) & (u + v <= 1) & (depth >= f(.0001)) & (depth <= f(64))
        coords = uv[0] + ((uv[1] - uv[0]) * u[:, None] + (uv[2] - uv[0]) * v[:, None])
    return hit, depth, coords


def image_oracle(sample, quads, textures, width, height):
    rays = directions(sample["camera"], width, height)
    origin = np.array(list(map(unw, sample["camera"][:3])), dtype=np.float32)
    best = np.full(width * height, f(65), dtype=np.float32)
    orders = np.full(width * height, 0xffffffff, dtype=np.uint32)
    background = 4284784875
    output = np.tile([(background >> shift) & 255 for shift in (16, 8, 0)], (width * height, 1)).astype(np.uint32)
    for words in quads:
        vertices = np.array([[unw(value) for value in words[index:index + 5]] for index in range(0, 20, 5)], dtype=np.float32)
        first = triangle(vertices[:3], origin, rays)
        second = triangle(vertices[[0, 2, 3]], origin, rays)
        use = first[0] & (~second[0] | (first[1] <= second[1]))
        valid = first[0] | second[0]
        depth = np.where(use, first[1], second[1])
        uv = np.where(use[:, None], first[2], second[2])
        hit = valid & ((depth < best) | ((depth == best) & (words[-1] < orders)))
        texture = textures[words[20]]
        th, tw = texture.shape[:2]
        uv = np.clip(np.nan_to_num(uv, nan=0, posinf=0, neginf=0), 0, 1)
        xy = np.minimum(np.array([tw - 1, th - 1]), (uv * np.array([tw, th], dtype=np.float32)).astype(np.uint32))
        rgba = texture[xy[:, 1], xy[:, 0]].astype(np.uint32)
        rgb = np.floor((rgba[:, :3] * np.uint32(65025)).astype(np.float32) / f(65025) * f(unw(words[23]))).astype(np.uint32)
        best[hit], orders[hit], output[hit] = depth[hit], words[-1], rgb[hit]
    return output.astype(np.uint8).reshape(height, width, 3).tobytes()


def rendered(group):
    return not group.startswith("far-") or int(group[4:]) % 4 == 0


def parse_native_stdout(text):
    """Prepared read-only verifier; this function never launches a process."""
    data = {"assets": {}, "asset_order": [], "scenes": {}, "quads": {}, "scene_errors": {},
            "frames": {}, "checksums": {}, "errors": {}, "asset_textures": {}, "asset_bindings": {}, "asset_baked": {}}

    def words(value, length):
        values = [int(part) for part in value.split(",")]
        require(len(values) == length and all(map(u32, values)), "native record word width/range")
        return values

    def unique(target, identifier, value):
        require(identifier not in target, "duplicate native record: " + identifier)
        target[identifier] = value

    for line in text.splitlines():
        # IO.print is applied to newline-terminated diagnostic blocks by the
        # native harness; their exact empty framing lines carry no records.
        if line == "":
            continue
        fields = line.split("|")
        kind = fields[0]
        if kind == "asset-texture":
            require(len(fields) == 4 and u32(int(fields[1])), "native asset-texture shape")
            dimensions = words(fields[2], 3)
            pixels = words(fields[3], dimensions[0] * dimensions[1])
            unique(data["asset_textures"], fields[1], {"dimensions": dimensions, "pixels": pixels})
        elif kind == "asset-binding":
            require(len(fields) == 4 and u32(int(fields[1])), "native asset-binding shape")
            unique(data["asset_bindings"], fields[1], {"appearance": words(fields[2], 5),
                                                    "tints": [words(row, 2) for row in fields[3].split(";") if row]})
        elif kind == "asset-baked":
            require(len(fields) == 6 and u32(int(fields[1])), "native asset-baked shape")
            values = data["asset_baked"].setdefault(fields[1], [])
            require(int(fields[2]) == len(values), "native asset-baked index")
            values.append({"sprite": fields[3], "vertices": words(fields[4], 20), "metadata": words(fields[5], 11)})
        elif kind == "assets":
            require(len(fields) == 9 and fields[2] in ("before", "returned", "after"), "native asset marker shape")
            marker = {"count_palette": words(fields[3], 5), "bindings": int(fields[4]),
                      "roots": int(fields[5]), "sprites": int(fields[6]), "usage": words(fields[7], 5),
                      "headers": [words(row, 3) for row in fields[8].split(";") if row]}
            require(all(map(u32, (marker["bindings"], marker["roots"], marker["sprites"]))), "native catalog count words")
            identifier = fields[1] + "|" + fields[2]
            unique(data["assets"], identifier, marker)
            data["asset_order"].append(identifier)
        elif kind == "scene":
            require(len(fields) == 3 and u32(int(fields[2])), "native scene count")
            unique(data["scenes"], fields[1], int(fields[2]))
        elif kind == "quad":
            require(len(fields) == 4, "native quad record shape")
            values = data["quads"].setdefault(fields[1], [])
            require(int(fields[2]) == len(values), "native quad output index")
            values.append(words(fields[3], 29))
        elif kind == "frame":
            require(len(fields) == 5 and all(map(u32, map(int, fields[2:4]))), "native frame record shape")
            unique(data["frames"], fields[1], {"width": int(fields[2]), "height": int(fields[3]), "path": fields[4]})
        elif kind == "checksum":
            require(len(fields) == 3 and u32(int(fields[2])), "native checksum word")
            unique(data["checksums"], fields[1], int(fields[2]))
        elif kind in ("scene-error", "error"):
            require(len(fields) == 3, "native error record shape")
            unique(data["scene_errors" if kind == "scene-error" else "errors"], fields[1], fields[2])
        else:
            raise AssertionError("unrecognized native record: " + line[:200])
    return data


def verify_native_output(config, expectations, text, entries, assets):
    """Compare an already captured output; not called by preparation modes.

    Fault markers must prove the returned value still contains the deliberately
    damaged header/binding count before the harness restores it. Only subsequent
    baseline draw success can establish that the retained owner remains usable.
    """
    data = parse_native_stdout(text)
    require(data["asset_textures"] == assets["textures"], "actual RF decoded all 768 ARGB texels/header/slots differs from original PNGs")
    require(data["asset_bindings"] == assets["bindings"], "actual RF explicit state bindings/appearance differs")
    require(data["asset_baked"] == assets["baked"], "actual RF full Baked geometry and metadata differs from actual Java groups")
    cases = config["cases"]
    ids = {case["id"] for case in cases}
    require(len(ids) == len(cases), "native config case IDs unique")
    scene_errors = {case["id"]: expectations[case["id"]]["error"] for case in cases
                    if expectations[case["id"]]["error"] and case["mode"] != "bad-texture"}
    draw_errors = {case["id"]: expectations[case["id"]]["error"] for case in cases if expectations[case["id"]]["error"]}
    frames = {case["id"] for case in cases if "frame" in expectations[case["id"]]}
    require(data["scene_errors"] == scene_errors and data["errors"] == draw_errors, "native exact rejection map")
    require(set(data["scenes"]) == ids - set(scene_errors), "native exact scene map including zero-quad scenes")
    require(set(data["quads"]) <= set(data["scenes"]), "native unknown quad scenario")
    require(set(data["frames"]) == set(data["checksums"]) == frames, "native exact selected frame map")
    usage = [sum("/models/" in name for name in entries), 3,
             sum(value["bytes"] for name, value in entries.items() if "/models/" in name),
             sum(value["bytes"] for name, value in entries.items() if "/textures/" in name), 768]
    original = {"count_palette": [3, *config["palette"]], "bindings": 3, "roots": 3, "sprites": 3,
                "usage": usage, "headers": [[16, 16, 16] for _ in range(3)]}
    order, checked_quads, checked_pixels, owner_recoveries = [], 0, 0, 0
    for case in cases:
        identifier, expected = case["id"], expectations[case["id"]]
        stages = ("before", "after") if case["mode"] == "scene-only" else ("before", "returned", "after")
        order.extend(identifier + "|" + stage for stage in stages)
        for stage in stages:
            wanted = copy.deepcopy(original)
            if stage == "returned" and case["mode"] == "bad-texture":
                wanted["headers"][0][0] = 0
            if stage == "returned" and case["mode"] == "missing-binding":
                wanted["bindings"] = 2
            require(data["assets"][identifier + "|" + stage] == wanted,
                    "native retained owner metadata mismatch: " + identifier + "/" + stage)
        if identifier in data["scenes"]:
            require(data["scenes"][identifier] == len(expected["quads"]) and data["quads"].get(identifier, []) == expected["quads"],
                    "actual RF scene differs from translated, visibility-filtered Java quads: " + identifier)
            checked_quads += len(expected["quads"])
        if identifier in frames:
            frame, wanted = data["frames"][identifier], expected["frame"]
            require([frame["width"], frame["height"]] == [wanted["width"], wanted["height"]], "native frame dimensions")
            expected_path = case.get("output", "build/world-resource-frame/frames/" + identifier + ".ppm")
            require(frame["path"] == expected_path, "native frame output path")
            path = Path(frame["path"])
            if not path.is_absolute():
                path = ROOT / path
            with Image.open(path) as image:
                require(image.format == "PPM" and image.size == (wanted["width"], wanted["height"]), "native PPM header")
                rgb = image.convert("RGB").tobytes()
            require(sha(rgb) == wanted["rgb_sha256"] and data["checksums"][identifier] == wanted["rgba_crc32"],
                    "native RGB/complete RGBA CRC differs from independent ray oracle: " + identifier)
            checked_pixels += wanted["pixels"]
            owner_recoveries += bool(expected["same_owner_recovery_of"])
    require(data["asset_order"] == order and set(data["assets"]) == set(order), "native exact owner marker sequence")
    return {"cases": len(cases), "checked_quads": checked_quads, "checked_pixels": checked_pixels,
            "checked_asset_texels": 768, "checked_full_baked_quads": 18, "checked_asset_bindings": 3,
            "frames": len(frames), "rejections": len(draw_errors), "same_owner_recovery_draws": owner_recoveries}


def prepared_cases(handoff):
    configs = {"official": {"jar": str(JAR), "palette": [0, 1, 10, 15], "samples": {}, "cases": []},
               "alternate": {"jar": str(JAR), "palette": [2, 1, 3, 0], "samples": {}, "cases": []}}
    origins, errors, recoveries = {}, {}, {}
    for group, samples in sorted(handoff["samples"].items()):
        config = configs["alternate" if group == "alternate" else "official"]
        for name, sample in sorted(samples.items()):
            identifier = group + "--" + name
            config["samples"][identifier] = copy.deepcopy(sample)
            config["cases"].append({"id": identifier, "sample": identifier, "width": 32, "height": 24,
                                    "mode": "normal" if rendered(group) else "scene-only", "limits": DEFAULT_LIMITS.copy()})
            origins[identifier] = [group, name]
    config = configs["official"]
    base_id = "official--initial"
    base = config["samples"][base_id]
    for width, height in ((4, 4), (1024, 4), (4, 1024)):
        config["cases"].append({"id": f"dimension-{width}-{height}", "sample": "empty-known-air--empty-known-air",
                                "width": width, "height": height, "mode": "normal", "limits": DEFAULT_LIMITS.copy()})

    def reject(identifier, error, change=None, mode="normal", width=32, height=24, limits=None):
        sample_id = base_id
        if change:
            sample_id = identifier + "-input"
            sample = copy.deepcopy(base)
            change(sample)
            config["samples"][sample_id] = sample
        config["cases"].append({"id": identifier, "sample": sample_id, "width": width, "height": height,
                                "mode": mode, "limits": limits or DEFAULT_LIMITS.copy()})
        errors[identifier] = error
        recovery = identifier + "-recovery"
        config["cases"].append({"id": recovery, "sample": base_id, "width": 32, "height": 24,
                                "mode": "normal", "limits": DEFAULT_LIMITS.copy()})
        recoveries[recovery] = identifier

    for field, name in enumerate(("air", "stone", "dirt", "planks")):
        reject("palette-" + name, "Palette:Mismatch", lambda s, i=field: s["palette"].__setitem__(i, 0xfffffffc))
    for a in range(4):
        for b in range(a + 1, 4):
            reject(f"palette-alias-{a}-{b}", "Palette:Mismatch", lambda s, a=a, b=b: s["palette"].__setitem__(b, s["palette"][a]))
    reject("mask-length", SAMPLE_ERROR, lambda s: s["masks"].pop())
    reject("mask-range", SAMPLE_ERROR, lambda s: s["masks"][0].__setitem__(5, 64))
    reject("mask-cell", SAMPLE_ERROR, lambda s: s["masks"][0].__setitem__(0, 123))
    reject("mask-state", SAMPLE_ERROR, lambda s: s["masks"][0].__setitem__(4, s["palette"][2]))
    reject("duplicate-raw", SAMPLE_ERROR, lambda s: s["raw"].__setitem__(1, s["raw"][0].copy()))
    reject("raw-material", SAMPLE_ERROR, lambda s: s["raw"][0].__setitem__(5, 1))
    reject("relative-coordinate", SAMPLE_ERROR, lambda s: s["blocks"][0].__setitem__(0, word(1)))
    reject("read-count", SAMPLE_ERROR, lambda s: s.__setitem__("reads", s["reads"] - 1))
    require(base["blocks"][108 // 6][3] == 1, "independent exact pre-filter budget failure state")
    reject("pre-filter-budget", "Visibility:Mesh:QuadLimit:0,0,0,0:1:", limits=[4096, 1024, 108, 64, 256])
    reject("missing-binding", "Visibility:Mesh:MissingState:0,0,0,0:1:", mode="missing-binding")
    reject("bad-material", "Visibility:Mesh:BakedQuad:0,0,0,0:0:", mode="bad-material")
    reject("width-under-min", "Visibility:Mesh:Frame:0,0,0,0:0:", width=3)
    reject("height-over-max", "Visibility:Mesh:Frame:0,0,0,0:0:", height=1025)
    reject("bad-texture", "Render:Textures", mode="bad-texture")
    require(len(origins) == 46 and len(errors) == len(recoveries) == 24, "bounded frozen case count")
    return configs, origins, errors, recoveries


def prepare(verify):
    handoff, previous, visibility, java_quads, textures, entries = references()
    before = source_fingerprints()
    configs, origins, errors, recoveries = prepared_cases(handoff)
    expectations, files, images = {}, [], {}
    previous_frames = {(group["name"].removesuffix("-geometry"), frame["scenario"]): frame["rgb_sha256"]
                       for group in previous["groups"] for frame in group.get("frames", [])}
    samples = {identifier: sample for config in configs.values() for identifier, sample in config["samples"].items()}
    for identifier, (group, name) in origins.items():
        sample = samples[identifier]
        validate_sample(sample)
        java_masks(group, name, sample, visibility)
    for config_name, config in configs.items():
        for case in config["cases"]:
            identifier, sample = case["id"], samples[case["sample"]]
            expectation = {"error": errors.get(identifier), "same_owner_recovery_of": recoveries.get(identifier)}
            if identifier not in errors or case["mode"] == "bad-texture":
                quads = expected_quads(sample, java_quads)
                expectation["quads"] = quads
            if identifier not in errors and case["mode"] != "scene-only":
                rgb = image_oracle(sample, quads, textures, case["width"], case["height"])
                rgba = np.column_stack([np.frombuffer(rgb, dtype=np.uint8).reshape(-1, 3),
                                        np.full(case["width"] * case["height"], 255, dtype=np.uint8)]).tobytes()
                expectation["frame"] = {"width": case["width"], "height": case["height"],
                                          "pixels": case["width"] * case["height"], "rgb_sha256": sha(rgb),
                                          "rgba_crc32": zlib.crc32(rgba)}
                if identifier in origins:
                    require(sha(rgb) == previous_frames[tuple(origins[identifier])], "prepared oracle differs from independently verified WV frame: " + identifier)
                images[identifier] = rgb
                files.append(save_or_check(WORK / "expected-rgb" / (identifier + ".rgb"), rgb, verify))
            expectations[identifier] = expectation
        data = canonical(config)
        require(len(data) <= 1024 * 1024, "native JSON input exceeds 1 MiB")
        files.append(save_or_check(WORK / (config_name + "-input.json"), data, verify))
    for recovery in recoveries:
        require(images[recovery] == images["official--initial"], "same-owner recovery oracle differs")
    require(images["official--initial"] != images["official--raw-edit"], "inside edit must change pixels")
    changed = sum(a != b for a, b in zip(np.frombuffer(images["official--initial"], dtype=np.uint8).reshape(-1, 3).tolist(),
                                       np.frombuffer(images["official--raw-edit"], dtype=np.uint8).reshape(-1, 3).tolist()))
    require(changed > 0, "edit pixel count")
    assets = {name: expected_assets(config["palette"], java_quads, textures) for name, config in configs.items()}
    expected = {"schema": 1, "cases": expectations, "assets": assets, "actual_sample_origins": origins,
                "native_input_has_no_expected_quads_or_pixels": True}
    files.append(save_or_check(WORK / "independent-expected.json", canonical(expected), verify))
    after = source_fingerprints()
    require(before == after, "adapter/reference source changed during preparation")
    counters = {"genuine_native_samples": len(origins), "positive_geometry_cases": len(origins),
                "positive_visible_quads": sum(len(expectations[name]["quads"]) for name in origins),
                "full_asset_baked_quads_per_palette": 18, "asset_texels_per_palette": 768,
                "representative_frames": sum("frame" in expectations[name] for name in origins),
                "dimension_edge_frames": 3, "negative_cases": len(errors), "planned_same_owner_recoveries": len(recoveries),
                "total_native_cases": len(expectations), "prepared_frames": len(images),
                "prepared_pixels": sum(value.get("frame", {}).get("pixels", 0) for value in expectations.values()),
                "inside_edit_changed_pixels": changed}
    receipt = {"schema": 1, "status": "prepared_unverified_native", "confidence": "high for preparation and prior sealed Sample provenance; native adapter unknown",
               "timestamp_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
               "scope": "Pure Python fixture/reference preparation; no native program, loader, Bend checker, or kernel invoked",
               "oracle_sha256": digest(Path(__file__).resolve()), "source_sha256_begin": before, "source_sha256_end": after,
               "source_unchanged_during_preparation": True,
               "pinned_inputs": {relative(path): expected for path, expected in PINS.items()},
               "prior_native_sampler": {"path": relative(HANDOFF), "sha256": PINS[HANDOFF],
                                         "binary_sha256": handoff["sampler_binary_sha256"], "compiler_profile": "exact emitted C, CPU -O0"},
               "original_jar_entries": entries, "files": files, "prepared_counters": counters,
               "native_counters": {"builds": 0, "loader_invocations": 0, "draws": 0, "checked_quads": 0, "checked_pixels": 0,
                                   "checked_full_asset_baked_quads": 0, "checked_asset_texels": 0, "owner_recoveries": 0},
               "libraries": {"python": sys.version, "numpy": np.__version__, "pillow": PILLOW_VERSION},
               "resource_adoption_gate": {"status": "prior_projected_RF_readbacks_verified; new_native_same_owner_full_diagnostics_pending",
                                          "observed_full_RF_receipt": {"path": relative(RF_FULL_EVIDENCE), "sha256": PINS[RF_FULL_EVIDENCE]},
                                          "prior_verified_scope": "two native passes of 768 texels/header/slots, sprite + projected 29 mesh words; complete K.Baked metadata was not emitted",
                                          "new_comparison_only_expectations": "18 full baked quads plus 768 ARGB texels and 3 complete explicit appearances, each requested palette",
                                          "required_in_new_native_root": ["actual native RF.Info palette and bindings for requested state IDs",
                                                                          "native texture slot/header and all 768 ARGB texels vs original PNGs",
                                                                          "native baked 20 vertex/UV words and all 11 metadata words vs actual Java groups",
                                                                          "source, executable, generated entry, input and output hashes for those same-owner readbacks"]},
               "prepared_protocol": {"native_first_argument": "JSON file path", "root_fields": ["jar", "palette", "samples", "cases"],
                                     "modes": ["normal", "scene-only", "bad-texture", "missing-binding", "bad-material"],
                                     "sample_boundary_metadata": "all six raw/mask words preserved; no regeneration from expected geometry",
                                     "read_only_native_verifier": "parse_native_stdout/verify_native_output prepared but never invoked in preparation",
                                     "fault_owner_validation": "before/after original metadata; returned width0 or binding count2 must precede explicit baseline recovery"},
               "boundaries": ["Prepared native RGB/CRC and raw-quad comparisons target actual RF.load -> WRF.scene/draw -> BVH M.render execution.",
                              "Preparation is not evidence of native WorldResourceFrame success or affine owner recovery.",
                              "Only measured air/stone/dirt/oak_planks static opaque full-cube geometry is covered.",
                              "No expected Java quads, pixels, texture arrays or baked DTOs enter the planned RF.load native input.",
                              "Optional owned W snapshot_draw scenarios require a separate narrow entry and grant.",
                              "No visible-window, GPU, final vanilla frame, broad client or full Minecraft parity claim."],
               "required_native_grant": "explicit bounded native build/load/draw slot after verified RF asset/geometry handoff; one process group at a time"}
    if not verify:
        RECEIPT.parent.mkdir(parents=True, exist_ok=True)
        RECEIPT.write_text(json.dumps(receipt, sort_keys=True, indent=2) + "\n")
    else:
        old = json.loads(RECEIPT.read_text())
        for key in ("oracle_sha256", "pinned_inputs", "files", "prepared_counters", "source_sha256_begin"):
            require(old[key] == receipt[key], "prepared receipt is stale: " + key)
    print(json.dumps({"status": "verified_preparation" if verify else receipt["status"],
                      "receipt": relative(RECEIPT), "receipt_sha256": digest(RECEIPT),
                      "oracle_sha256": receipt["oracle_sha256"], "prepared_counters": counters}, sort_keys=True))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    options = parser.add_mutually_exclusive_group()
    options.add_argument("--prepare-only", action="store_true", help="create Python-only fixtures; no native execution")
    options.add_argument("--verify-existing", action="store_true", help="check existing preparation without execution")
    args = parser.parse_args()
    prepare(args.verify_existing)


if __name__ == "__main__":
    main()
