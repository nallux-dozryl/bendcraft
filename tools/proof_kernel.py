#!/usr/bin/env python3
"""Bootstrap the exact independent BendTT verification dependency locally."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
VERSION = "4.34.0"
ARCHIVE = f"lean-{VERSION}-darwin_aarch64.tar.zst"
SHA256 = "69f263fa6e21bbc2466bbfb1affcd92479ee2714c883a07de548e099a5922932"
URL = f"https://github.com/leanprover/lean4/releases/download/v{VERSION}/{ARCHIVE}"

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bend", default=str(Path.home() / ".bend/bin/bend"))
    parser.add_argument("--proof", type=Path, default=ROOT / "PROOF.bend")
    args = parser.parse_args()
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise SystemExit("This bootstrap pins Apple Silicon macOS; supply Lean 4.34.0/BENDTT directly on other platforms")
    folder = ROOT / ".runtime/toolchains"
    folder.mkdir(parents=True, exist_ok=True)
    archive = folder / ARCHIVE
    if not archive.exists():
        temporary = folder / (ARCHIVE + ".download")
        urllib.request.urlretrieve(URL, temporary)
        if hashlib.file_digest(temporary.open("rb"), "sha256").hexdigest() != SHA256:
            raise SystemExit("Lean archive digest mismatch")
        temporary.replace(archive)
    if hashlib.file_digest(archive.open("rb"), "sha256").hexdigest() != SHA256:
        raise SystemExit("Lean archive digest mismatch")
    installation = folder / f"lean-{VERSION}-darwin_aarch64"
    if not (installation / "bin/lean").exists():
        subprocess.run(["tar", "--zstd", "-xf", str(archive), "-C", str(folder)], check=True)
    environment = os.environ.copy()
    environment["PATH"] = str(installation / "bin") + os.pathsep + environment.get("PATH", "")
    version = subprocess.run([str(installation / "bin/lean"), "--version"], capture_output=True, text=True, check=True).stdout.strip()
    completed = subprocess.run([args.bend, str(args.proof.resolve()), "--verdict"], env=environment, capture_output=True, text=True)
    if completed.returncode != 0 or completed.stdout.strip() != "ALL PROOFS CHECK":
        raise SystemExit(completed.stdout + completed.stderr)
    evidence = {"lean_version": version, "release_url": URL, "archive_sha256": SHA256,
                "proof": str(args.proof.resolve().relative_to(ROOT)),
                "proof_sha256": hashlib.sha256(args.proof.read_bytes()).hexdigest(),
                "command": "python3 tools/proof_kernel.py", "verdict": completed.stdout.strip(),
                "scope": "The imported implementation laws only; not game parity or host correctness."}
    (ROOT / "evidence/proof-kernel.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps(evidence, sort_keys=True))

if __name__ == "__main__":
    main()
