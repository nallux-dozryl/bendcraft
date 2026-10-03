#!/usr/bin/env python3
"""Actual native lease contention, release, and process-death recovery."""
from __future__ import annotations
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import select
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
BEND = Path.home() / ".bend/bin/bend"

def main():
    started = time.monotonic()
    binary = ROOT / "build/world-lock-tests"
    subprocess.run([str(BEND), "tests/world_lock.bend", "-o", str(binary)], cwd=ROOT, check=True)
    checks = []
    processes = []
    def quick(path, expected=None, mode="release"):
        result = subprocess.run([str(binary), str(path), mode], cwd=ROOT, capture_output=True, timeout=5)
        if expected is None:
            assert result.returncode == 0 and result.stdout == b"acquired\nreleased\n", result
        else:
            assert result.returncode == 1 and result.stderr.startswith(f"acquire:{expected}:".encode()), result
        return result
    def holder(path):
        process = subprocess.Popen([str(binary), str(path)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        processes.append(process)
        assert select.select([process.stdout], [], [], 5)[0]
        assert process.stdout.readline() == b"acquired\n", process.stderr.read()
        return process
    try:
        with tempfile.TemporaryDirectory(prefix="bendex-world-lease-") as folder:
            directory = Path(folder)
            path = directory / "world.lock"
            quick(path)
            assert path.is_file() and path.stat().st_mode & 0o777 == 0o600
            inode = path.stat().st_ino
            path.write_bytes(b"persistent lock inode, never save bytes\n")
            original = path.read_bytes()
            first = holder(path)
            quick(path, errno.EWOULDBLOCK)
            with path.open("rb") as separate:
                try: fcntl.flock(separate.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError: pass
                else: raise AssertionError("native exclusive lock was not observed independently")
            assert path.stat().st_ino == inode and path.read_bytes() == original
            checks.append("native exclusivity agrees with independent Python flock; file bytes/inode unchanged")
            other = directory / "other.lock"
            quick(other)
            checks.append("different world lock remains independently available")
            first.kill()
            assert first.wait(timeout=5) < 0
            for _ in range(5):
                quick(path)
                assert path.stat().st_ino == inode and path.read_bytes() == original
            checks.append("SIGKILL releases kernel lease; five restarts reuse the retained inode")
            contenders = [subprocess.Popen([str(binary), str(path)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(8)]
            processes.extend(contenders)
            winners = []
            failures = []
            for contender in contenders:
                assert select.select([contender.stdout], [], [], 5)[0]
                line = contender.stdout.readline()
                if line == b"acquired\n": winners.append(contender)
                else:
                    assert contender.wait(timeout=5) == 1
                    errors = contender.stderr.read()
                    assert errors.startswith(f"acquire:{errno.EWOULDBLOCK}:".encode()), errors
                    failures.append(contender)
            assert len(winners) == 1 and len(failures) == 7
            winners[0].kill()
            winners[0].wait(timeout=5)
            quick(path)
            checks.append("eight simultaneous processes produce one lease and seven immediate failures")
            target = directory / "target"
            target.write_bytes(b"must remain untouched")
            symlink = directory / "symlink.lock"
            symlink.symlink_to(target)
            quick(symlink, errno.ELOOP)
            assert target.read_bytes() == b"must remain untouched"
            quick(directory, errno.EISDIR)
            fifo = directory / "fifo.lock"
            os.mkfifo(fifo)
            quick(fifo, errno.EINVAL)
            quick(directory / "absent" / "world.lock", errno.ENOENT)
            quick(path, errno.EILSEQ, "nul")
            checks.append("symlink, directory, FIFO, missing parent and embedded NUL fail without blocking or mutating target")
            guarded = directory / "guarded"
            guarded.mkdir()
            guarded.chmod(0)
            try:
                if os.geteuid() != 0:
                    quick(guarded / "world.lock", errno.EACCES)
                    checks.append("unwritable parent rejects acquisition")
            finally: guarded.chmod(0o700)
            quick(path)
            assert path.read_bytes() == original
            checks.append("explicit successful release permits subsequent acquisition")
        files = ["src/world_lock.bend", "src/native/world_lock.c", "src/native/world_lock.js", "tests/world_lock.bend", "tools/test_world_lock.py"]
        evidence = {"status": "passed", "actual_native_processes": True, "checks": checks,
                    "concurrent_contenders": 8, "winners": 1, "post_crash_reacquisitions": 5,
                    "source_sha256": {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in files},
                    "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                    "elapsed_seconds": round(time.monotonic()-started, 3), "command": "python3 tools/test_world_lock.py",
                    "limits": "Cooperating local processes using a stable parent and lock inode. No hostile inode replacement, filesystem/network lock failure, or durable save-content claim."}
        (ROOT / "evidence/world-lock.json").write_text(json.dumps(evidence, indent=2)+"\n")
        print(json.dumps({"status": "passed", "checks": len(checks), "concurrent_contenders": 8}))
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)

if __name__ == "__main__":
    main()
