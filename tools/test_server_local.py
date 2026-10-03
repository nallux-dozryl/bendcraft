#!/usr/bin/env python3
"""Verify typed local calls and real TCP share one authoritative owner."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import select
import subprocess
import time
from test_server import Client, free_port, TOKEN

ROOT = Path(__file__).resolve().parents[1]
BEND = Path.home() / ".bend/bin/bend"

def main():
    started = time.monotonic()
    binary = ROOT / "build/server-local-tests"
    subprocess.run([str(BEND), "tests/server_local.bend", "-o", str(binary)], cwd=ROOT, check=True)
    port = free_port()
    env = os.environ.copy()
    env.update(MC_DEV_TOKEN=TOKEN, MC_LIVE_PORT=str(port))
    process = subprocess.Popen([str(binary), "--threads", "4", "--gpu", "off"], cwd=ROOT, env=env,
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    client = None
    checks = []
    def local(command):
        process.stdin.write(command.encode())
        process.stdin.flush()
        assert select.select([process.stdout], [], [], 5)[0], "typed local call timed out"
        return json.loads(process.stdout.readline())
    try:
        assert select.select([process.stdout], [], [], 10)[0], "actor startup timed out"
        assert json.loads(process.stdout.readline())["event"] == "server.ready"
        client = Client(port)
        client.result("session.open", {"mode": "developer", "token": TOKEN})
        assert local("q") == {"missing": True}
        p = {"dimension": "minecraft:overworld", "x": -17, "y": 0, "z": 32}
        client.result("world.section.create", p | {"fill": 0}, at=1)
        client.result("world.block.set", p | {"state": 140}, at=1)
        assert local("c") == {"tick": 0, "revision": 0, "pending": 2}
        assert local("s") == {"tick": 1, "revision": 2, "pending": 0}
        assert local("q") == {"state": 140}
        assert client.result("world.block.get", p)["state"] == 140
        checks.append("TCP queued edits execute in typed local step and appear in local snapshot")
        assert local("m") == {"tick": 1, "revision": 2, "pending": 1}
        assert client.result("world.clock")["pending"] == 1
        assert client.result("simulation.step", {"ticks": 1})["tick"] == 2
        assert local("q") == {"state": 321}
        assert client.result("world.block.get", p)["state"] == 321
        events = client.result("world.events")["events"]
        assert events[0]["stamp"]["peer"] == 0 and events[0]["kind"] == "applied", events
        checks.append("typed local admission executes through TCP step with shared event ordering")
        client.result("simulation.pause", {"paused": False})
        time.sleep(.17)
        client.result("simulation.pause", {"paused": True})
        remote = client.result("world.clock")
        assert local("c") == {"tick": remote["tick"], "revision": remote["revision"], "pending": 0}
        assert remote["tick"] > 2
        checks.append("same realtime timer and pause state observed by typed and remote queries")
        process.stdin.write(b"x")
        process.stdin.flush()
        assert process.wait(timeout=5) == 0
        assert client.reader.readline() == b""
        checks.append("actor stop acknowledges then explicit process exit releases actual listener and socket")
        files = ["src/server.bend", "tests/server_local.bend", "tools/test_server_local.py"]
        evidence = {"status": "passed", "actual_transport": True, "checks": checks,
                    "state": "one affine Core.World owned by the shared actor; no world clone",
                    "source_sha256": {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in files},
                    "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                    "elapsed_seconds": round(time.monotonic()-started, 3), "command": "python3 tools/test_server_local.py",
                    "shutdown_limit": "Stop closes the state actor and timer; native process Halt releases parked accept and client sockets."}
        (ROOT / "evidence/server-local.json").write_text(json.dumps(evidence, indent=2)+"\n")
        print(json.dumps({"status": "passed", "shared_owner_checks": len(checks)}))
    finally:
        if client is not None:
            client.close()
        if process.poll() is None:
            process.terminate()
            try: process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)
        errors = process.stderr.read().decode(errors="replace")
        assert TOKEN not in errors

if __name__ == "__main__":
    main()
