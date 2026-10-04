#!/usr/bin/env python3
"""Prepare an isolated world-mesh candidate and actual-production-path observer.

This command writes source/receipts only. It never launches Bend, Java, clang,
native clients, or benchmarks. Candidate files are ignored and are not shipped.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "build/mesh-layer-order-001"
EVIDENCE = ROOT / "evidence/mesh_layer_order.json"
REFERENCE = ROOT / "reference/mesh_layer_order.json"


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def replace_once(text: str, before: str, after: str) -> str:
    if text.count(before) != 1:
        raise ValueError(f"Expected one exact production source span: {before[:96]!r}")
    return text.replace(before, after, 1)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=Path("build/mesh-layer-order-001"))
    args = parser.parse_args()
    work = (ROOT / args.directory).resolve()
    if work.parent != ROOT / "build" or not work.name.startswith("mesh-layer-order-"):
        raise ValueError("Private source directory must be an immediate build/mesh-layer-order-* child")
    source = (ROOT / "src/world_mesh.bend").read_text()
    observer = (ROOT / "tests/mesh_layer_order.bend").read_text()
    candidate = source.replace("import ./", "import ../../src/")
    candidate = replace_once(candidate,
        "def translated(color:Maybe<&2,U32>,value:K.Baked,",
        "# The admitted WM scene contains at most 4096 quads: CUTOUT orders 0..4095\n"
        "# precede SOLID orders 4096..8191 only at exact ray-distance equality.\n"
        "# This models the separately submitted later cutout pass; within-layer\n"
        "# order remains the existing deterministic policy. Translucent is deferred.\n"
        "def layer_order(layer:K.Layer,count:U32) -> U32:\n"
        "  match layer:\n"
        "    case K.Cutout{}: count\n"
        "    case _: U32.add(count,4096)\n\n"
        "def layer_mesh(+value:K.Baked,appearance:K.Appearance,count:U32) -> M.Quad:\n"
        "  K.Baked{a,b,c,d,direction,cf,sprite,texture,index,emission,override,layer,force,animated,ds,ns} = value\n"
        "  K.mesh(value,appearance,layer_order(layer,count))\n\n"
        "def translated(color:Maybe<&2,U32>,value:K.Baked,")
    candidate = replace_once(candidate,
        "      +quad = translate_quad(K.mesh(value,mesh_appearance(appearance,color),count),origin)",
        "      +quad = translate_quad(layer_mesh(value,mesh_appearance(appearance,color),count),origin)")
    baseline = observer.replace("import ../src/", "import ../../src/")
    variant = replace_once(baseline,
        "import ../../src/world_mesh.bend as WM", "import ./world_mesh.bend as WM")
    inputs = {name: digest((ROOT / name).read_bytes()) for name in
        ("src/world_mesh.bend", "src/mesh_render.bend", "src/block_bake.bend", "src/client_render.bend",
         "tests/mesh_layer_order.bend", "reference/model_semantics.json", "reference/mesh_layer_order.json")}
    generated = {"world_mesh.baseline.bend": source,
                 "world_mesh.bend": candidate,
                 "baseline.bend": baseline,
                 "candidate.bend": variant}
    manifest = {"schema": 1, "status": "source_prepared", "sources": inputs,
                "outputs": {name: {"bytes": len(text.encode()), "sha256": digest(text.encode())}
                            for name, text in generated.items()},
                "production_mutations": [], "native_runs": 0, "source_checks": 0,
                "recipe": "Exact source-span changes to a private WM module; production M/K/R stay imported unchanged."}
    work.mkdir(parents=True, exist_ok=True)
    prior = work / "manifest.json"
    if prior.exists() and json.loads(prior.read_text()) != manifest:
        raise ValueError("Existing attempt has different sources; preserve it and choose a fresh attempt directory")
    for name, text in generated.items():
        (work / name).write_text(text)
    prior.write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n")
    reference = json.loads(REFERENCE.read_text())
    evidence = {"schema": 1, "pin": "26.3", "status": "source_prepared_native_pending",
                "reference_sha256": digest(REFERENCE.read_bytes()),
                "authority": {"configured_pipeline_facts": "pinned class bytecode", "gpu_frames_observed": 0,
                              "equal_depth_overwrite": "inference from inclusive depth, later cutout submission and disabled blending"},
                "preparer_sha256": digest(Path(__file__).read_bytes()),
                "private_candidate": {"directory": str(work.relative_to(ROOT)), **manifest},
                "observations": {"synthetic_cases": 11, "runs": 0, "compiled": False},
                "expected_pixels": {"solid-before-covered-cutout": {"baseline": 4294901760, "candidate": 4278255360},
                    "cutout-before-solid": {"baseline": 4278255360, "candidate": 4278255360},
                    "discarded-cutout": {"baseline": 4294901760, "candidate": 4294901760},
                    "alpha127-discarded": {"baseline": 4294901760, "candidate": 4294901760},
                    "alpha128-covered": {"baseline": 4294901760, "candidate": 4278255360},
                    "solid-nearer": {"baseline": 4294901760, "candidate": 4294901760},
                    "cutout-nearer": {"baseline": 4278255360, "candidate": 4278255360},
                    "cutout-one-ulp-farther": {"baseline": 4294901760, "candidate": 4294901760},
                    "solid-one-ulp-farther": {"baseline": 4278255360, "candidate": 4278255360},
                    "same-solid-layer-policy": {"baseline": 4294901760, "candidate": 4294901760},
                    "same-cutout-layer-policy": {"baseline": 4278255360, "candidate": 4278255360}},
                "limits": reference["limits"]}
    if EVIDENCE.exists():
        older = json.loads(EVIDENCE.read_text())
        evidence["prior_attempts"] = older.get("prior_attempts", [])
        if older.get("private_candidate", {}).get("directory") != str(work.relative_to(ROOT)):
            evidence["prior_attempts"].append({"directory": older.get("private_candidate", {}).get("directory", "build/mesh-layer-order-001"),
                "status": older.get("status"), "sources": older.get("private_candidate", {}).get("sources", {}),
                "source_checks": older.get("source_checks", [])})
        elif older.get("observations", {}).get("runs", 0):
            raise ValueError("Do not overwrite executed evidence with source preparation")
    EVIDENCE.write_text(json.dumps(evidence, sort_keys=True, indent=2) + "\n")
    print(json.dumps({"status": evidence["status"], "source_checks": 0, "native_runs": 0,
                      "manifest": str(prior.relative_to(ROOT))}, sort_keys=True))


if __name__ == "__main__":
    main()
