#!/usr/bin/env python3
"""Test actual last peer allocation: no wrap/reuse, existing session retained."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import select
import socket
import subprocess
from test_server import Client, free_port, TOKEN

ROOT = Path(__file__).resolve().parents[1]
BEND = Path.home() / ".bend/bin/bend"

def main():
    binary = ROOT / "build/server-peer-tests"
    subprocess.run([str(BEND), "tests/server_peer.bend", "-o", str(binary)], cwd=ROOT, check=True)
    port = free_port()
    env = os.environ.copy()
    env.update(MC_DEV_TOKEN=TOKEN, MC_LIVE_PORT=str(port))
    process = subprocess.Popen([str(binary), "--threads", "4", "--gpu", "off"], cwd=ROOT, env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    client = None
    try:
        assert select.select([process.stdout], [], [], 10)[0]
        assert json.loads(process.stdout.readline())["event"] == "server.ready"
        client = Client(port)
        assert client.result("ping")["peer"] == 4294967295
        assert select.select([process.stderr], [], [], 5)[0]
        warning = process.stderr.readline().decode().strip()
        assert warning == "live peer identity range exhausted; listener closed"
        try:
            extra = socket.create_connection(("127.0.0.1", port), timeout=2)
        except ConnectionRefusedError:
            pass
        else:
            extra.close()
            raise AssertionError("exhausted listener accepted another peer")
        assert client.result("ping")["peer"] == 4294967295
        opened = client.result("session.open", {"mode": "developer", "token": TOKEN})
        assert opened["peer"] == 4294967295
        assert client.result("simulation.step", {"ticks": 1})["tick"] == 1
        result = {"status": "passed", "actual_transport": True, "last_allocated_peer": 4294967295,
                  "new_connections": "refused", "existing_connection": "still_operational",
                  "source_sha256": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in ["src/server.bend", "tests/server_peer.bend", "tools/test_server_peer.py"]},
                  "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(), "command": "python3 tools/test_server_peer.py"}
        (ROOT / "evidence/server-peer.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps({"status": "passed", "last_peer": 4294967295, "identity_reuse": False}))
    finally:
        if client is not None:
            client.close()
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)

if __name__ == "__main__":
    main()
