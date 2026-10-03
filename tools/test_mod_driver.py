#!/usr/bin/env python3
"""Exercise a complete typed Bend driver replacement through TCP and MCP."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import select
import subprocess
import time
from test_server import Client, free_port, TOKEN
from test_mcp import MCP

ROOT = Path(__file__).resolve().parents[1]
BEND = Path.home() / ".bend/bin/bend"

def main():
    started = time.monotonic()
    binary = ROOT / "build/time-overhaul-server"
    mcp_binary = ROOT / "build/minecraft-mcp"
    for source, output in [("mods/examples/time_overhaul.bend", binary), ("mcp.bend", mcp_binary)]:
        subprocess.run([str(BEND), source, "-o", str(output)], cwd=ROOT, check=True)
    port = free_port()
    env = os.environ.copy()
    env.update(MC_DEV_TOKEN=TOKEN, MC_LIVE_PORT=str(port))
    process = subprocess.Popen([str(binary), "--threads", "4", "--gpu", "off"], cwd=ROOT, env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    clients = []
    mcp = None
    checks = []
    try:
        assert select.select([process.stdout], [], [], 10)[0], "mod server startup timed out"
        assert json.loads(process.stdout.readline())["event"] == "server.ready"
        observer, developer = Client(port), Client(port)
        clients.extend([observer, developer])
        catalog = observer.result("discover")["operations"]
        names = [op["name"] for op in catalog]
        assert len(set(names)) == len(names) == 18
        assert {"mod.time_overhaul.status", "mod.time_overhaul.configure", "registry.state.resolve"} <= set(names)
        observer.fault("PermissionDenied", "mod.time_overhaul.status")
        developer.result("session.open", {"mode": "developer", "token": TOKEN})
        before = developer.result("mod.time_overhaul.status")
        assert before["ticks_per_pulse"] == 1 and before["state_owner"] == "typed-complete-driver"
        assert before["restart_persistence"] is False
        checks.append("actual extra owned state and dynamic catalog with capability checks")
        # Explicit stepping stays exact even when realtime policy is replaced.
        developer.result("mod.time_overhaul.configure", {"ticks_per_pulse": 4})
        start = developer.result("world.clock")
        stop = developer.result("simulation.step", {"ticks": 3})
        assert stop["tick"] - start["tick"] == 3
        frozen = developer.result("mod.time_overhaul.status")
        time.sleep(0.17)
        assert developer.result("world.clock")["tick"] == stop["tick"]
        assert developer.result("mod.time_overhaul.status")["pulses"] > frozen["pulses"]
        checks.append("mod state updates while paused; explicit stepping remains exact")
        baseline = developer.result("mod.time_overhaul.status")
        for args in [{"ticks_per_pulse": 0}, {"ticks_per_pulse": 11}, {"ticks_per_pulse": 1.0},
                     {"ticks_per_pulse": 2, "extra": True}]:
            developer.fault("InvalidArguments", "mod.time_overhaul.configure", args)
        developer.fault("InvalidArguments", "mod.time_overhaul.configure", {"ticks_per_pulse": 2}, at=100)
        assert developer.result("mod.time_overhaul.status")["ticks_per_pulse"] == baseline["ticks_per_pulse"]
        checks.append("mod schemas reject invalid configuration without changing rate")
        position = {"dimension": "minecraft:overworld", "x": -17, "y": 0, "z": 32}
        clock = developer.result("world.clock")
        # Actions due inside a multi-tick pulse must still apply at each exact
        # target tick through the shared checked core, not be skipped.
        create = developer.result("world.section.create", position | {"fill": 0}, at=clock["tick"] + 1)
        edit = developer.result("world.block.set", position | {"state": 140}, at=clock["tick"] + 2)
        developer.result("simulation.pause", {"paused": False})
        time.sleep(0.28)
        developer.result("simulation.pause", {"paused": True})
        after = developer.result("world.clock")
        changed = after["tick"] - clock["tick"]
        assert changed % 4 == 0 and 12 <= changed <= 40, changed
        assert developer.result("world.block.get", position)["state"] == 140
        events = developer.result("world.events")["events"]
        assert [event["stamp"] for event in events] == [edit["stamp"], create["stamp"]]
        assert [event["kind"] for event in events] == ["applied", "applied"]
        checks.append("replacement realtime transition runs four exact ticks per pulse and applies intervening actions")
        mcp = MCP(mcp_binary, port, TOKEN)
        mcp.initialize()
        listed = mcp.request("tools/list")["result"]["tools"]
        expected = [{"name": op["name"], "description": op["description"], "inputSchema": op["input_schema"]} for op in catalog]
        assert listed == expected
        observed = mcp.call("mod.time_overhaul.status")
        assert observed["ticks_per_pulse"] == 4
        assert mcp.call("mod.time_overhaul.configure", {"ticks_per_pulse": 2})["ticks_per_pulse"] == 2
        assert developer.result("mod.time_overhaul.status")["ticks_per_pulse"] == 2
        assert mcp.call("world.block.get", position)["state"] == 140
        assert mcp.call("registry.state.decode", {"state": 140})["name"] == "minecraft:oak_log"
        mcp.finish()
        checks.append("unchanged actual MCP adapter discovers and executes mod operations on shared state")
        files = ["mods/examples/time_overhaul.bend", "src/server.bend", "src/game.bend", "src/live.bend", "src/core.bend", "src/mcp.bend", "mcp.bend", "tools/test_mod_driver.py"]
        evidence = {"status": "passed", "kind": "actual_complete_driver_replacement_tcp_and_mcp", "checks": checks,
                    "source_sha256": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in files},
                    "binaries_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [binary, mcp_binary]},
                    "realtime_ticks_over_280ms": changed, "ticks_per_pulse": 4, "discovered_tools": len(names),
                    "elapsed_seconds": round(time.monotonic() - started, 3), "command": "python3 tools/test_mod_driver.py",
                    "limits": "One compiled typed system replacement example. No runtime code loading, player hooks, manifest integration, persistence/reload/migrations or broad subsystem mod coverage established."}
        (ROOT / "evidence/mod-driver.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(json.dumps({"status": "passed", "checks": len(checks), "tools": len(names), "realtime_ticks": changed}))
    finally:
        if mcp is not None:
            mcp.cleanup()
        for client in clients:
            client.close()
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)
        stderr = process.stderr.read().decode(errors="replace")
        assert TOKEN not in stderr
        if stderr:
            print(stderr)

if __name__ == "__main__":
    main()
