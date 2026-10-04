#!/usr/bin/env python3
"""Exact raw replay of the pinned Java block-interaction observations.

This helper prepares TSV test inputs and compares caller-supplied stdout. It
never builds or launches compiler, native, Java, or UI processes. The combined
playable consumer supplies its admitted executable and invokes
``block-reference-cases SINE_TABLE INPUT_TSV``. Omitting INPUT_TSV uses stdin.
"""
from __future__ import annotations

import argparse
import collections
import copy
import hashlib
import json
from pathlib import Path
import re

import reference_player_block_interaction_probe as R
from reference_inventory import canonical, fingerprint

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "build/player-block-reference"
ENTRY = ROOT / "tests/player_block_reference.bend"
TABLE = ROOT / "generated/reference_mth_sin.f32"
REFERENCE = R.OUTPUT
UNIT = ["0000000000000000"] * 3 + ["3ff0000000000000"] * 3
OPERATIONS = ("direction_nearest", "view_vector", "shape_clip", "aabb_clip", "reach_constants")
OPPOSITE = {"DOWN": "UP", "UP": "DOWN", "NORTH": "SOUTH", "SOUTH": "NORTH", "WEST": "EAST", "EAST": "WEST"}
HEX64 = re.compile(r"[0-9a-f]{16}\Z")
HEX32 = re.compile(r"[0-9a-f]{8}\Z")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_pin(path):
    path = Path(path).resolve()
    return {"path": str(path), **fingerprint(path)}


def raw_words(raw):
    """Split hexadecimal binary64 payloads without floating-point conversion."""
    require(isinstance(raw, str) and HEX64.fullmatch(raw), "Invalid reference F64 payload")
    return [int(raw[:8], 16), int(raw[8:], 16)]


def vector_words(values):
    require(isinstance(values, list) and len(values) == 3, "Invalid reference Vec3 arity")
    return [word for raw in values for word in raw_words(raw)]


def float_word(raw):
    require(isinstance(raw, str) and HEX32.fullmatch(raw), "Invalid reference F32 payload")
    return int(raw, 16)


def position_words(values):
    require(isinstance(values, list) and len(values) == 3 and
            all(type(value) is int and -(1 << 31) <= value < (1 << 31) for value in values),
            "Invalid reference signed BlockPos")
    return [value & 0xffffffff for value in values]


def tsv(values):
    values = list(map(str, values))
    require(all(not any(c in value for c in "\t\r\n\x00") for value in values), "Unsafe reference TSV field")
    return "\t".join(values)


def exclusion(case):
    """Admission is the exact product full-cube contract, never inferred tags."""
    if case["operation"] not in ("shape_clip", "aabb_clip"):
        return None
    boxes = case["input"]["boxes"]
    if boxes != [UNIT]:
        if not boxes:
            return "empty shape outside direct full-cube clip entry"
        if len(boxes) != 1:
            return "multiple boxes outside supported full-cube shape contract"
        return "single box differs from the supported local unit cube"
    if case["operation"] == "shape_clip":
        require(case["observation"]["realized_boxes_f64_bits"] == [UNIT],
                "Java realization changed for admitted unit cube: " + case["id"])
    return None


def project(case):
    """Encode inputs and copy exact independent outputs; implement no geometry."""
    label, operation, incoming, desired = case["id"], case["operation"], case["input"], case["expected"]
    if operation == "direction_nearest":
        require(desired["face"] in OPPOSITE and desired["float_overload_face"] == desired["face"] and
                desired["opposite"] == OPPOSITE[desired["face"]], "Invalid nearest observation: " + label)
        return tsv([label, "nearest", *vector_words(incoming["vector_f64_bits"])]), \
            tsv([label, "nearest", desired["face"], desired["opposite"]])
    if operation == "view_vector":
        return tsv([label, "view", float_word(incoming["yaw_f32_bits"]), float_word(incoming["pitch_f32_bits"])]), \
            tsv([label, "view", *vector_words(desired["vector_f64_bits"])])
    if operation in ("shape_clip", "aabb_clip"):
        command = tsv([label, operation, *position_words(incoming["position"]),
                       *vector_words(incoming["from_f64_bits"]), *vector_words(incoming["to_f64_bits"])])
        require(type(desired["hit"]) is bool, "Invalid reference hit flag: " + label)
        if not desired["hit"]:
            require(set(desired) == {"hit"}, "Null reference hit has extra output fields: " + label)
            return command, tsv([label, "clip", 0])
        require(desired["face"] in OPPOSITE and type(desired["inside"]) is bool and desired["type"] == "BLOCK",
                "Invalid reference BlockHitResult: " + label)
        require(desired["position"] == incoming["position"], "Java hit BlockPos differs: " + label)
        if operation == "aabb_clip":
            require(desired["inside"] is False, "AABB.clip unexpectedly reported inside: " + label)
        return command, tsv([label, "clip", 1, desired["face"], int(desired["inside"]),
                             *position_words(desired["position"]), *vector_words(desired["location_f64_bits"])])
    if operation == "reach_constants":
        return tsv([label, "reach"]), tsv([label, "reach", *raw_words(desired["actual_attribute_with_creative_modifier_f64_bits"])])
    raise AssertionError("Unsupported reference operation: " + operation)


def reference_plan():
    """Verify existing provenance through file reads only, then project cases."""
    validation = R.verify()
    reference = json.loads(REFERENCE.read_bytes())
    require(set(case["operation"] for case in reference["cases"]) == set(OPERATIONS), "Reference operation set changed")
    commands, expected, cases, excluded = [], [], [], []
    for case in reference["cases"]:
        reason = exclusion(case)
        if reason:
            excluded.append({"id": case["id"], "operation": case["operation"], "reason": reason, "tags": case["tags"]})
            continue
        command, answer = project(case)
        commands.append(command)
        expected.append(answer)
        cases.append({"id": case["id"], "operation": case["operation"], "tags": case["tags"]})
    admitted = collections.Counter(case["operation"] for case in cases)
    total = collections.Counter(case["operation"] for case in reference["cases"])
    omitted = collections.Counter(case["operation"] for case in excluded)
    require(all(admitted[operation] == total[operation] for operation in ("direction_nearest", "view_vector", "reach_constants")),
            "Non-clip reference observations were excluded")
    require(all(admitted[operation] > 0 for operation in OPERATIONS), "Required reference lane is empty")
    require(len(cases) + len(excluded) == len(reference["cases"]), "Reference admission count differs")
    tags = collections.Counter(tag for case in cases for tag in case["tags"])
    for tag in ("enum_tie_priority", "float_narrowing", "minimum_score_gate", "float_operation_order",
                "squared_length_gate", "strict_transverse_epsilon", "exact_face_tie", "scaled_inside_sample",
                "inside_nearest_float_tie", "strict_segment_end", "translated_block_position", "seeded_random"):
        require(tags[tag] > 0, "Targeted admitted reference category missing: " + tag)
    nulls = [case["id"] for case in reference["cases"] if case["operation"] in ("shape_clip", "aabb_clip") and
             exclusion(case) is None and case["expected"]["hit"] is False]
    nearest_zero = next(case for case in reference["cases"] if case["id"] == "direction_nearest:ordinary-0.0-0.0-0.0")
    return {"reference": file_pin(REFERENCE), "reference_validation": validation,
            "commands": commands, "expected_rows": expected, "cases": cases, "excluded": excluded,
            "total_cases": len(reference["cases"]), "admitted_cases": len(cases), "excluded_cases": len(excluded),
            "operation_counts": {operation: {"total": total[operation], "admitted": admitted[operation], "excluded": omitted[operation]}
                                 for operation in OPERATIONS}, "admitted_tag_counts": dict(sorted(tags.items())),
            "null_clip_ids": nulls, "zero_nearest_default": nearest_zero["expected"],
            "reach_scope": "Production creative_reach compared with actual Player attribute after production creative modifier; survival/default and modifier metadata remain Java reference observations."}


def manifest_seal(value):
    return sha(canonical({key: item for key, item in value.items() if key != "seal_sha256"}))


def prepare_reference(directory=None):
    """Return reusable manifest; write only test inputs, expected TSV, manifest."""
    directory = Path(directory or WORK).resolve()
    plan = reference_plan()
    inputs = ("\n".join(plan.pop("commands")) + "\n").encode("ascii")
    outputs = ("\n".join(plan["expected_rows"]) + "\n").encode("ascii")
    require(len(inputs) < 4194304, "Reference test stdin exceeds Bend bound")
    directory.mkdir(parents=True, exist_ok=True)
    input_path, expected_path, manifest_path = directory / "inputs.tsv", directory / "expected.tsv", directory / "manifest.json"
    input_path.write_bytes(inputs)
    expected_path.write_bytes(outputs)
    value = {"schema_version": 1, "status": "prepared-native-unverified", **plan,
             "input_path": str(input_path), "expected_path": str(expected_path), "manifest_path": str(manifest_path),
             "input": file_pin(input_path), "expected": file_pin(expected_path), "entry": file_pin(ENTRY),
             "helper": file_pin(__file__), "sine_table": file_pin(TABLE),
             "mode": "block-reference-cases", "arguments": [str(TABLE), str(input_path)],
             "compiler_executions": 0, "native_executions": 0, "Java_executions": 0, "UI_executions": 0}
    value["seal_sha256"] = manifest_seal(value)
    value["comparator_controls"] = comparator_controls(value)
    value["seal_sha256"] = manifest_seal(value)
    manifest_path.write_bytes(canonical(value) + b"\n")
    return value


def admitted_manifest(value):
    if isinstance(value, (str, Path)):
        value = json.loads(Path(value).read_bytes())
    require(isinstance(value, dict) and value.get("schema_version") == 1, "Invalid block reference manifest")
    require(value.get("seal_sha256") == manifest_seal(value), "Block reference manifest seal differs")
    for field in ("reference", "input", "expected", "entry", "helper", "sine_table"):
        require(file_pin(value[field]["path"]) == value[field], "Block reference manifest file changed: " + field)
    require(Path(value["input_path"]).resolve() == Path(value["input"]["path"]), "Reference stdin path differs")
    require(Path(value["expected_path"]).resolve() == Path(value["expected"]["path"]), "Reference expected path differs")
    desired = ("\n".join(value["expected_rows"]) + "\n").encode("ascii")
    require(Path(value["expected_path"]).read_bytes() == desired, "Expected TSV differs from admitted rows")
    require(len(value["cases"]) == len(value["expected_rows"]) == value["admitted_cases"], "Reference manifest arity differs")
    # A self-consistent reseal cannot make altered expected rows authoritative.
    # Reproject actual Java observations and exact admission on every replay.
    plan = reference_plan()
    require(all(value.get(key) == item for key, item in plan.items() if key != "commands"),
            "Reference manifest differs from independent Java projection")
    require(Path(value["input_path"]).read_bytes() == ("\n".join(plan["commands"]) + "\n").encode("ascii"),
            "Reference inputs differ from independent Java projection")
    return value


def compare(outputs, input_manifest):
    """Compare exact stdout bytes, including row order, fields, and signed zero."""
    value = admitted_manifest(input_manifest)
    observed = outputs.read_bytes() if isinstance(outputs, Path) else outputs.encode("ascii") if isinstance(outputs, str) else outputs
    require(isinstance(observed, bytes), "Reference outputs must be bytes, text, or a Path")
    desired = ("\n".join(value["expected_rows"]) + "\n").encode("ascii")
    if observed != desired:
        actual_lines, expected_lines = observed.splitlines(), desired.splitlines()
        for index in range(max(len(actual_lines), len(expected_lines))):
            actual = actual_lines[index] if index < len(actual_lines) else b"<missing>"
            expected = expected_lines[index] if index < len(expected_lines) else b"<unexpected>"
            if actual != expected:
                label = value["cases"][index]["id"] if index < len(value["cases"]) else "unexpected-output"
                raise AssertionError(f"Exact block reference mismatch row {index + 1} ({label}): expected {expected!r}, observed {actual!r}")
        raise AssertionError("Exact block reference output terminators differ")
    return {"status": "passed", "cases": value["admitted_cases"], "total_reference_cases": value["total_cases"],
            "excluded_cases": value["excluded_cases"], "operation_counts": copy.deepcopy(value["operation_counts"]),
            "exact_stdout_sha256": sha(observed), "manifest_seal_sha256": value["seal_sha256"],
            "raw_F64_words_compared": True, "face_inside_and_BlockPos_compared": True,
            "reference": value["reference"], "null_clip_cases": len(value["null_clip_ids"]),
            "scope": "All nearest/view/creative-reach observations and exactly one local full unit cube for both clip methods; unsupported shapes explicitly excluded."}


def comparator_controls(value):
    """Corrupt synthetic output only; no native acceptance is claimed."""
    rows = value["expected_rows"]
    baseline = "\n".join(rows) + "\n"
    compare(baseline, value)
    faults = {}

    def field(name, index, column, replacement):
        altered = rows.copy()
        parts = altered[index].split("\t")
        require(parts[column] != str(replacement), "Inert corruption did not change field: " + name)
        parts[column] = str(replacement)
        altered[index] = "\t".join(parts)
        faults[name] = "\n".join(altered) + "\n"

    nearest = next(i for i, row in enumerate(rows) if row.split("\t")[1] == "nearest")
    view = next(i for i, row in enumerate(rows) if row.split("\t")[1] == "view")
    hit = next(i for i, row in enumerate(rows) if row.split("\t")[1:3] == ["clip", "1"])
    miss = next(i for i, row in enumerate(rows) if row.split("\t")[1:3] == ["clip", "0"])
    translated = next(i for i, row in enumerate(rows) if row.startswith("shape_clip:translated\t"))
    reach = next(i for i, row in enumerate(rows) if row.split("\t")[1] == "reach")
    face = rows[nearest].split("\t")[2]
    field("nearest-face", nearest, 2, OPPOSITE[face])
    field("nearest-opposite", nearest, 3, face)
    field("view-low-word", view, 3, int(rows[view].split("\t")[3]) ^ 1)
    negative_zero = next((i, column) for i, row in enumerate(rows) if row.split("\t")[1] == "view"
                         for column in (2, 4, 6) if row.split("\t")[column:column + 2] == ["2147483648", "0"])
    field("view-signed-zero", *negative_zero, 0)
    field("clip-hit-face", hit, 3, OPPOSITE[rows[hit].split("\t")[3]])
    field("clip-inside", hit, 4, 1 - int(rows[hit].split("\t")[4]))
    field("clip-location-low-word", hit, 9, int(rows[hit].split("\t")[9]) ^ 1)
    field("negative-BlockPos", translated, 7, 13)
    field("clip-miss", miss, 2, 1)
    field("creative-reach", reach, 3, int(rows[reach].split("\t")[3]) ^ 1)
    faults.update({"missing-response": "\n".join(rows[:-1]) + "\n",
                   "duplicate-response": baseline + rows[0] + "\n",
                   "reordered-responses": "\n".join([rows[1], rows[0], *rows[2:]]) + "\n",
                   "CRLF-output": baseline.replace("\n", "\r\n"),
                   "missing-final-newline": baseline[:-1], "extra-blank-response": baseline + "\n"})
    refused = []
    for name, corrupted in faults.items():
        require(corrupted != baseline, "Inert output corruption did not change bytes: " + name)
        try:
            compare(corrupted, value)
        except AssertionError:
            refused.append(name)
        else:
            raise AssertionError("Comparator admitted inert output corruption: " + name)
    changed = copy.deepcopy(value)
    changed["expected_rows"][0] = rows[nearest].replace(face, OPPOSITE[face], 1)
    changed["seal_sha256"] = manifest_seal(changed)
    try:
        compare(baseline, changed)
    except AssertionError:
        refused.append("resealed-expected-row")
    else:
        raise AssertionError("Comparator admitted resealed expected row corruption")
    return {"status": "passed", "synthetic_baseline_compared": True, "corruptions_refused": refused,
            "shared_reference_files_changed": False, "compiler_executions": 0, "native_executions": 0,
            "Java_executions": 0, "UI_executions": 0,
            "scope": "Host comparator sensitivity using reference-derived synthetic output only; native replay remains unverified."}


def summary(value):
    return {key: value[key] for key in ("status", "manifest_path", "input_path", "expected_path", "seal_sha256",
                                       "total_cases", "admitted_cases", "excluded_cases", "operation_counts", "comparator_controls")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare", action="store_true")
    parser.add_argument("--directory", type=Path)
    parser.add_argument("--compare", type=Path, help="Captured native stdout; comparison starts no processes")
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args()
    require(args.prepare != bool(args.compare), "Choose exactly one of --prepare or --compare")
    if args.prepare:
        print(json.dumps(summary(prepare_reference(args.directory)), sort_keys=True))
    else:
        print(json.dumps(compare(args.compare, args.manifest or WORK / "manifest.json"), sort_keys=True))


if __name__ == "__main__":
    main()
