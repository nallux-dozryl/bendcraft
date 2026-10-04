#!/usr/bin/env python3
"""Prove and execute unconditional release without changing atomic input."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

import build_native
import test_player_controls as Controls
from reference_inventory import fingerprint

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build/native_controls_current_release"
EVIDENCE = ROOT / "evidence/native_controls_current_release.json"
BEND = Path.home() / ".bend/bin/bend"

def pin(path: Path) -> dict:
    data = path.read_bytes()
    return {"path":str(path.resolve()),"bytes":len(data),"sha256":hashlib.sha256(data).hexdigest()}

def command(args: list[str], expected: int = 0) -> dict:
    started = time.monotonic()
    result = subprocess.run(args,cwd=ROOT,capture_output=True,text=True,timeout=60)
    receipt = {"command":args,"exit_code":result.returncode,"stdout":result.stdout,
        "stderr":result.stderr,"seconds":round(time.monotonic()-started,6)}
    assert result.returncode == expected,receipt
    return receipt

def release(words: list[int]) -> list[int]:
    result = words.copy()
    result[0] = 0
    result[9:14] = [0,0,0,0,1]
    return result

def ignored_release_mutant() -> dict:
    directory = BUILD / "mutant"
    directory.mkdir(exist_ok=True)
    paths = [ROOT / "src/player_controls.bend",ROOT / "tests/native_controls_current_release_laws.bend",
        ROOT / "tests/native_controls_current_release_proof.bend"]
    replacements = {str(path):directory / path.name for path in paths}
    for path in paths:
        def absolute(match: re.Match) -> str:
            target = (path.parent / match[1]).resolve()
            return "import "+str(replacements.get(str(target),target))+match[2]
        value = re.sub(r"^import (\.\.?/\S+\.bend)(.*)$",absolute,path.read_text(),flags=re.M)
        if path == paths[0]:
            before = "case True{}: release(controller)"
            assert value.count(before) == 1
            value = value.replace(before,"case True{}: controller")
        replacements[str(path)].write_text(value)
    result = command([str(BEND),str(replacements[str(paths[2])]),"--verdict"],expected=1)
    assert "SOME PROOFS FAIL" in result["stderr"] and "Laws.canonical_release_consumes_existing_packet" in result["stderr"],result
    return result

def cases() -> list[dict]:
    # Independent raw-word expectation: release changes exactly mask, both
    # accumulated double words and first-move; it never evaluates preserved data.
    raw32 = [0,0x80000000,1,0x7f7fffff,0x7f800000,0xff800000,0x7fc00123,0xffc0f00d]
    raw64 = [0,0x8000000000000000,1,0x7fefffffffffffff,0x7ff0000000000000,
        0xfff0000000000000,0x7ff8000000000123,0xffffffffffffffff]
    actions = [[],[Controls.key(119,True)],[Controls.look(0x7fc00123,0,False)],
        [Controls.RELEASE],[Controls.RELEASE,Controls.look(0x7fc00123,0,False)],
        [Controls.look(0x7fc00123,0,True),Controls.RELEASE],
        [Controls.RELEASE,Controls.key(119,True)],
        [Controls.key(32,True),Controls.RELEASE,Controls.key(119,True)]]
    result = []
    for mask in range(128):
        for pattern,events in enumerate(actions):
            wide = lambda index: [raw64[index%8]>>32,raw64[index%8]&0xffffffff]
            words = [mask,*[raw32[(mask+i)%8] for i in range(4)],
                *wide(mask),*wide(mask+1),*wide(mask+2),*wide(mask+3),mask&1,
                *wide(mask+4),mask&1,(mask>>1)&1,(mask>>2)&1,(mask>>3)&1]
            focused,captured = bool(mask&1),bool(mask&2)
            packet = Controls.packet(events,focused,captured)
            request = [0,*words,*Controls.DEFAULT_BINDINGS,*Controls.packet_words(packet)]
            result.append({"id":f"raw_mask_{mask}/pattern_{pattern}","words":words,"packet":packet,
                "request":"|".join(map(str,request)),"expected":release(words) if any(a[0]==0 for a in events) else words})
    # These finite initial controllers isolate rollback of Release followed by
    # malformed Look from failure due to preserved invalid initial fields.
    for mask in range(128):
        value = Controls.controller(mask=mask,mouse=[0,0,0,0,False])
        words = Controls.controller_words(value)
        for captured in (False,True):
            packet = Controls.packet([Controls.RELEASE,Controls.look(0x7fc00123,0,captured)],False,False)
            request = [0,*words,*Controls.DEFAULT_BINDINGS,*Controls.packet_words(packet)]
            result.append({"id":f"valid_controller_atomic_failure_{mask}_{int(captured)}","words":words,
                "packet":packet,"request":"|".join(map(str,request)),"expected":release(words),"must_refuse":True})
    return result

def native_cases(binary: Path, corpus: list[dict]) -> dict:
    reports = 0
    refused = 0
    batches = []
    for start in range(0,len(corpus),64):
        group = corpus[start:start+64]
        receipt = command([str(binary),"--gpu","off","--threads","1","--",*[case["request"] for case in group]])
        lines = receipt["stdout"].splitlines()
        assert len(lines) == len(group),(start,len(lines),len(group))
        for case,line in zip(group,lines,strict=True):
            actual = json.loads(line)
            expected = case["expected"]
            assert actual["released"] == expected and actual["repeated"] == expected,case["id"]
            assert actual["canonical"] == release(case["words"]),case["id"]
            assert actual["requested"] == any(action[0]==0 for action in case["packet"]["actions"]),case["id"]
            if case.get("must_refuse"):
                assert not actual["ordinary"]["ok"] and actual["ordinary"]["retained_controller"] == case["words"],case["id"]
                assert not actual["after_release"]["ok"] and actual["after_release"]["retained_controller"] == expected,case["id"]
                refused += 1
            reports += 1
        batches.append({"cases":len(group),"seconds":receipt["seconds"],
            "stdout_sha256":hashlib.sha256(receipt["stdout"].encode()).hexdigest()})
    return {"cases":reports,"valid_controller_malformed_packet_refusals_after_release":refused,"batches":batches}

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build",action="store_true",help="Build two narrow CPU harnesses before running; coordinate heavy slots")
    args = parser.parse_args()
    BUILD.mkdir(parents=True,exist_ok=True)
    sources = [ROOT / "src/player_controls.bend",ROOT / "src/client_controls.bend",
        ROOT / "tests/native_controls_current_release_laws.bend",ROOT / "tests/native_controls_current_release_proof.bend",
        ROOT / "tests/native_controls_current_release.bend",Path(__file__)]
    source_pins = [pin(path) for path in sources]
    proofs = command([str(BEND),str(sources[3]),"--verdict"])
    assert "ALL PROOFS CHECK" in proofs["stdout"]
    mutation = ignored_release_mutant()
    exported = command([str(BEND),str(sources[3]),"-o",str(BUILD / "proof.bendtt")])
    existing = command([str(BEND),"tests/player_controls.bend","--verdict"])
    successful = command([str(BEND),"tests/native_controls_current_proof.bend","--verdict"])
    ordinary = command([str(BEND),str(sources[4]),"--check-only"])
    release_binary = BUILD / "release"
    existing_binary = BUILD / "atomic"
    builds = []
    if args.build:
        for entry,binary in ((sources[4],release_binary),(ROOT / "tests/player_controls.bend",existing_binary)):
            report = build_native.ensure_native(entry,binary,bend=BEND)
            (BUILD / (binary.name+"-build.json")).write_text(json.dumps(report,indent=2)+"\n")
            builds.append({key:report[key] for key in ("path","binary_sha256","cache_key","cache_hit","timings")})
    assert release_binary.is_file() and existing_binary.is_file(),"run --build after coordinating a CPU compile slot"
    corpus = cases()
    observed = native_cases(release_binary,corpus)
    # Reuse the frozen independently prepared Java/rational corpus without
    # regenerating or overwriting evidence owned by another lane.
    reference_path = ROOT / "evidence/player-controls-reference.json"
    reference = json.loads(reference_path.read_text())
    cached_path = ROOT / "build/player-controls-reference-cache/corpus.json"
    frozen = cached_path.read_bytes()
    assert hashlib.sha256(frozen).hexdigest() == reference["corpus_sha256"]
    for name,identity in {**reference["reference_files"],**reference["helper_identities"]}.items():
        assert fingerprint(ROOT / name) == identity,name
    atomic_corpus = json.loads(frozen)
    atomic_batches,failures = Controls.native_run(atomic_corpus,existing_binary)
    assert not failures,failures[:3]
    malformed = Controls.native_malformed(existing_binary)
    assert source_pins == [pin(path) for path in sources],"source changed during checks"
    evidence = {"status":"passed","confidence":"high for stated controller contracts and native raw-word checks",
        "source_identities":source_pins,"kernel_roots":10,"kernel":proofs,"export":exported,
        "kernel_rejects_ignored_release":mutation,
        "kernel_ir":pin(BUILD / "proof.bendtt"),
        "existing_eight_laws":existing,"existing_four_successful_fold_laws":successful,"ordinary":ordinary,
        "builds":builds,"release_binary":pin(release_binary),"atomic_binary":pin(existing_binary),
        "release_cases":observed,"existing_atomic_corpus":{"cases":len(atomic_corpus),"reports":reference["reports"],
            "corpus":pin(cached_path),"reference":pin(reference_path),"batches":atomic_batches,"failures":failures,
            "malformed_protocol_cases":len(malformed)},
        "consumer_boundary":"Presenter/runtime joins are root-owned and not established by these controller-only receipts; fixture failure reports echo their supplied prior controller",
        "unverified":["physical OS capture/focus/input","visible fullscreen/presentation","new presenter consumer integration"],
        "reproduce":"python3 tools/native_controls_current_release_check.py --build"}
    EVIDENCE.write_text(json.dumps(evidence,indent=2,sort_keys=True)+"\n")
    print(json.dumps({"status":"passed","kernel_roots":10,"release_cases":observed["cases"],
        "valid_controller_malformed_packet_refusals_after_release":observed["valid_controller_malformed_packet_refusals_after_release"],
        "existing_atomic_cases":len(atomic_corpus),"existing_atomic_reports":reference["reports"],"evidence":str(EVIDENCE)}))

if __name__ == "__main__":
    main()
