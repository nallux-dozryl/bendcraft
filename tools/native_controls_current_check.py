#!/usr/bin/env python3
"""Compile/run the actual native input boundary in a hidden AppKit window."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build/native_controls_current"
EVIDENCE = ROOT / "evidence/native_controls_current.json"
BASE = Path.home() / ".bend/bend2/effs/window.c"
PINNED_BASE = "617611d994fb7f4c57467f8d1a7e644ba19d4fce35770613dea2711e6cafd65c"

def pin(path: Path) -> dict:
    data = path.read_bytes()
    return {"path": str(path.resolve()), "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}

def run(command: list[str], expected_code: int = 0, **kwargs) -> dict:
    started = time.monotonic()
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=60, **kwargs)
    report = {"command": command, "exit_code": result.returncode,
              "stdout": result.stdout, "stderr": result.stderr,
              "seconds": round(time.monotonic()-started,6)}
    if result.returncode != expected_code:
        EVIDENCE.write_text(json.dumps({"status":"failed","attempt":report},indent=2)+"\n")
        raise RuntimeError(json.dumps(report))
    return report

def main() -> None:
    BUILD.mkdir(parents=True,exist_ok=True)
    sources = [BASE, ROOT / "src/native/player_presentation.c", ROOT / "tests/native_controls_current.m",
        ROOT / "tests/native_controls_current_proof.bend", ROOT / "src/player_controls.bend",
        ROOT / "src/player_presentation_native.bend"]
    identities = [pin(path) for path in sources]
    assert identities[0]["sha256"] == PINNED_BASE,"Base Window changed; review boundary before rerunning"
    base = BASE.read_text()
    # The entire pinned Base input class is reused, including superclass calls.
    view = base[base.index("@interface BendView"):base.index("static id<MTLDevice> window_dev;")]
    view_pin = hashlib.sha256(view.encode()).hexdigest()
    adapter = sources[1].read_text()
    translate = lambda source: re.sub(r"CID\(([A-Za-z0-9_.]+)\)",
        lambda match:"CID_"+match[1].replace(".","_").upper(),source)
    generated = sources[2].read_text().replace("// MC_BASE_SOURCE",translate(view)).replace(
        "// MC_ADAPTER_SOURCE",translate(adapter))
    emitted = BUILD / "boundary.m"
    emitted.write_text(generated)
    binary = BUILD / "boundary"
    compiled = run(["/usr/bin/clang","-x","objective-c","-fobjc-arc","-fmodules","-O1",
                    "-framework","AppKit","-framework","QuartzCore",str(emitted),"-o",str(binary)])
    executed = run([str(binary)],env={**os.environ,"BEND_MINECRAFT_LAUNCH_MODE":"hidden"})
    observations = json.loads(executed["stdout"])
    bend = str(Path.home() / ".bend/bin/bend")
    proofs = run([bend,"tests/native_controls_current_proof.bend","--verdict"])
    assert "ALL PROOFS CHECK" in proofs["stdout"]
    baseline = run([bend,"tests/player_controls.bend","--verdict"])
    assert "ALL PROOFS CHECK" in baseline["stdout"]
    native_check = run([bend,"src/player_presentation_native.bend","--check-only"],expected_code=1)
    assert (native_check["stdout"]+native_check["stderr"]).strip() == (
        "SOME PROOFS FAIL\nError: 4 defs rely on unsafe or foreign code:\n"
        "- Native.configure\n- Native.measure\n- Native.milliseconds\n- measure")
    # Counterexample sensitivity: the new successful-fold laws must reject an
    # implementation that drops every action while retaining the initial owner.
    mutate_imports = lambda path: re.sub(r"^import (\S+\.bend) as (\w+)$",
        lambda m:"import "+str((path.parent / m[1]).resolve())+" as "+m[2],path.read_text(),flags=re.M)
    production = sources[4]
    mutant = BUILD / "mutant_player_controls.bend"
    implementation = mutate_imports(production)
    before = "case head <> rest Done{controller}: fold(rest,bindings,action(head,controller,bindings))"
    assert implementation.count(before) == 1
    mutant.write_text(implementation.replace(before,"case head <> rest Done{controller}: Done{controller}"))
    mutant_proof = BUILD / "mutant_proof.bend"
    original = str(production.resolve())
    rewritten = mutate_imports(sources[3])
    assert rewritten.count("import "+original+" as C") == 1
    mutant_proof.write_text(rewritten.replace("import "+original+" as C","import "+str(mutant)+" as C"))
    mutation = run([bend,str(mutant_proof),"--check-only"],expected_code=1)
    mutation_output = mutation["stdout"]+mutation["stderr"]
    assert "SOME PROOFS FAIL" in mutation_output and "Location: ordered_action_prefix" in mutation_output
    assert identities == [pin(path) for path in sources],"source changed while checking"
    evidence = {"status":"passed","confidence":"high for recorded native boundary assertions",
        "sources":identities,"base_view_sha256":view_pin,"emitted":pin(emitted),"binary":pin(binary),
        "compile":compiled,"run":executed,"observations":observations,
        "pure_control_proof":proofs,"existing_eight_control_laws":baseline,
        "native_source_boundary":native_check,"dropped_action_mutant":mutation,
        "scope":["actual AppKit hidden content view installation and Base buffer/layer ownership",
            "content-point pointer/button boundary and outside rejection before Bend scaling",
            "signed relative Look payload under direct fixture flag without OS capture",
            "physical-key paired logical release, repeat suppression and duplicate logical-key hold",
            "all ten native modifier masks, simultaneous sided Shift and stale focus flags",
            "focus/application/close callback release and hidden capture refusal",
            "drawable/content measurement and actual backing conversion after hidden resize",
            "foreground pid, hidden/key/active state and Space-notification observations"],
        "unverified":["real OS input delivery and held-event cadence","positive cursor capture/release",
            "visible native presentation/framebuffer","OS fullscreen transition","physical multi-screen migration",
            "resize while rendering and matching pending-event geometry","whole-game/Java input parity"],
        "reproduce":"python3 tools/native_controls_current_check.py"}
    EVIDENCE.write_text(json.dumps(evidence,indent=2,sort_keys=True)+"\n")
    print(json.dumps({"status":"passed","observations":observations,"evidence":str(EVIDENCE)}))

if __name__ == "__main__":
    main()
