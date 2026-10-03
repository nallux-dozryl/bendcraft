#!/usr/bin/env python3
"""Verify real native atomic publication and process-interruption recovery."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import select
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
BEND = Path.home() / ".bend/bin/bend"
BINARY = ROOT / "build/atomic-file-tests"
WORK = ROOT / "build/atomic-file-oracle"
NEW = bytes([0, 1, 2, 255, 77, 105, 110, 101, 99, 114, 97, 102, 116, 10])
OLD = bytes(range(256)) * 7

def invoke(path: Path, suffix: str, mode="normal", pause=None):
    env = os.environ.copy()
    env.pop("MC_ATOMIC_PAUSE", None)
    if pause:
        env["MC_ATOMIC_PAUSE"] = pause
    return subprocess.Popen([str(BINARY), "--threads", "1", "--gpu", "off", str(path), suffix, mode],
                            cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def complete(path, suffix, mode="normal"):
    process = invoke(path, suffix, mode)
    stdout, stderr = process.communicate(timeout=10)
    assert process.returncode == 0 and stderr == b"", (stdout, stderr)
    return stdout.decode().splitlines()

def read_to_stage(process, stage):
    buffer = b""
    deadline = time.monotonic() + 8
    while True:
        remaining = deadline - time.monotonic()
        assert remaining > 0 and select.select([process.stdout], [], [], remaining)[0], stage
        chunk = os.read(process.stdout.fileno(), 1024)
        assert chunk, (stage, process.poll())
        buffer += chunk
        if stage.encode() in buffer.split(b"\n"):
            return

def main():
    started = time.monotonic()
    WORK.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(BEND), "tests/atomic_file.bend", "-o", str(BINARY)], cwd=ROOT, check=True)
    checks = []
    path = WORK / "success.bin"
    path.write_bytes(OLD)
    lines = complete(path, "success")
    assert lines == ["created", "written", "synced", "published", "directory_synced", "durable"]
    assert path.read_bytes() == NEW and not Path(str(path) + ".pending-success").exists()
    assert complete(path, "empty", "empty")[-1] == "durable" and path.read_bytes() == b""
    checks.append("real exclusive create, byte write, fsync/full-sync, rename and directory sync")
    crash_cases = []
    for stage in ["created", "written", "synced", "published", "directory_synced"]:
        for existed in [False, True]:
            for mode, payload in [("normal", NEW), ("empty", b"")]:
                suffix = f"crash-{stage.replace('_', '-')}-{int(existed)}-{mode}"
                destination = WORK / f"{suffix}.bin"
                destination.unlink(missing_ok=True)
                temp = Path(str(destination) + ".pending-" + suffix)
                temp.unlink(missing_ok=True)
                if existed:
                    destination.write_bytes(OLD)
                process = invoke(destination, suffix, mode, stage)
                try:
                    read_to_stage(process, stage)
                    process.kill()
                    stdout, stderr = process.communicate(timeout=5)
                    assert process.returncode == -9 and stderr == b""
                    published = stage in ["published", "directory_synced"]
                    if published:
                        assert destination.read_bytes() == payload and not temp.exists()
                    else:
                        assert destination.exists() is existed
                        if existed:
                            assert destination.read_bytes() == OLD
                        assert temp.is_file()
                        assert temp.read_bytes() == (b"" if stage == "created" else payload)
                    crash_cases.append({"stage": stage, "old_existed": existed, "empty_new": mode == "empty", "published": published})
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.communicate(timeout=5)
    checks.append("20 actual SIGKILL cases retain old or publish complete new bytes at each stage")
    blocked = WORK / "exclusive.bin"
    blocked.write_bytes(OLD)
    temp = Path(str(blocked) + ".pending-existing")
    temp.write_bytes(b"unowned-pending")
    assert complete(blocked, "existing")[-1].startswith("not_published:")
    assert blocked.read_bytes() == OLD and temp.read_bytes() == b"unowned-pending"
    linked = Path(str(blocked) + ".pending-symlink")
    linked.unlink(missing_ok=True)
    linked.symlink_to(temp.name)
    assert complete(blocked, "symlink")[-1].startswith("not_published:")
    assert linked.is_symlink() and temp.read_bytes() == b"unowned-pending" and blocked.read_bytes() == OLD
    checks.append("exclusive stale/symlink temporary collision leaves unowned files unchanged")
    assert complete(blocked, "invalid-bytes", "invalid")[-1].startswith("not_published:22:")
    assert blocked.read_bytes() == OLD and not Path(str(blocked) + ".pending-invalid-bytes").exists()
    assert complete(blocked, "../invalid-suffix") == ["not_published:22:temporary suffix must contain 1..64 lowercase letters, digits or hyphens"]
    assert blocked.read_bytes() == OLD
    checks.append("invalid byte values and unsafe suffix rejected without publishing or leaving owned temporary")
    folder = WORK / "destination-folder"
    folder.mkdir(exist_ok=True)
    marker = folder / "marker"
    marker.write_bytes(OLD)
    assert complete(folder, "rename-failure")[-1].startswith("not_published:")
    assert folder.is_dir() and marker.read_bytes() == OLD
    assert not Path(str(folder) + ".pending-rename-failure").exists()
    assert complete(WORK / "missing-parent" / "file.bin", "missing-parent")[-1].startswith("not_published:")
    checks.append("rename/open failures preserve destination and clean only successfully created temporary")
    verdict = subprocess.run([str(BEND), "tests/atomic_file.bend", "--check-only"], cwd=ROOT, capture_output=True, text=True)
    assert verdict.returncode != 0 and "SOME PROOFS FAIL" in verdict.stdout + verdict.stderr
    files = ["src/durability.bend", "src/native/durability.c", "src/native/durability.js", "src/atomic_file.bend", "tests/atomic_file.bend", "tools/test_atomic_file.py"]
    result = {"status": "passed", "checks": checks, "crash_cases": crash_cases,
              "source_sha256": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in files},
              "binary_sha256": hashlib.sha256(BINARY.read_bytes()).hexdigest(), "native_effects": 5,
              "checker_boundary": {"exit_code": verdict.returncode, "output": (verdict.stdout + verdict.stderr).strip()},
              "elapsed_seconds": round(time.monotonic() - started, 3), "command": "python3 tools/test_atomic_file.py",
              "limits": "File publication substrate only; no world-save schema, checksums, journal, automatic orphan recovery, concurrent world locking, simulated power loss or injected directory-sync failure established. Requires stable destination parent during publication. SIGKILL tests prove process-crash outcomes on this tested filesystem, not physical storage behavior."}
    (ROOT / "evidence/atomic-file.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"status": "passed", "checks": len(checks), "actual_kill_cases": len(crash_cases)}))

if __name__ == "__main__":
    main()
