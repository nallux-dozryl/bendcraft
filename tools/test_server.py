#!/usr/bin/env python3
"""Exercise the real native Bend server using independent TCP clients."""
from __future__ import annotations
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import select
import socket
import subprocess
import time
from build_native import ensure_native

ROOT = Path(__file__).resolve().parents[1]
BEND = Path.home() / ".bend/bin/bend"
TOKEN = "integration-test-token"

class Client:
    def __init__(self, port: int):
        self.socket = socket.create_connection(("127.0.0.1", port), timeout=5)
        self.socket.settimeout(5)
        self.reader = self.socket.makefile("rb")
        self.sequence = 0
    def receive(self):
        line = self.reader.readline(262145)
        if not line:
            raise AssertionError("server closed a valid connection")
        return json.loads(line)
    def call(self, op: str, args=None, **extra):
        self.sequence += 1
        request = {"id": f"request-{self.sequence}", "op": op}
        if args is not None:
            request["args"] = args
        request.update(extra)
        self.socket.sendall(json.dumps(request, ensure_ascii=False, separators=(",", ":")).encode() + b"\n")
        response = self.receive()
        assert response["id"] == request["id"], (request, response)
        return response
    def result(self, op: str, args=None, **extra):
        response = self.call(op, args, **extra)
        assert response["ok"] is True, response
        return response["result"]
    def fault(self, expected: str, op: str, args=None, **extra):
        response = self.call(op, args, **extra)
        assert response["ok"] is False and response["error"]["code"] == expected, response
        return response
    def close(self):
        self.reader.close()
        self.socket.close()

def free_port() -> int:
    with socket.socket() as reserved:
        reserved.bind(("127.0.0.1", 0))
        return reserved.getsockname()[1]

def main() -> None:
    start = time.perf_counter()
    native_build = ensure_native(ROOT / "server.bend", ROOT / "build/minecraft-server", bend=BEND)
    binary = Path(native_build["artifact"])
    port = free_port()
    environment = os.environ.copy()
    environment.update(MC_DEV_TOKEN=TOKEN, MC_LIVE_PORT=str(port))
    process = subprocess.Popen([str(binary), "--threads", "4", "--gpu", "off"], cwd=ROOT,
                               env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    clients = []
    checks = []
    def passed(name):
        checks.append(name)
    try:
        assert select.select([process.stdout], [], [], 10)[0], "server startup timed out"
        ready = json.loads(process.stdout.readline())
        assert ready == {"event": "server.ready", "host": "127.0.0.1", "port": port, "target": "26.3", "status": "foundation"}, ready
        first, second = Client(port), Client(port)
        clients.extend([first, second])
        discovery = first.result("discover")
        names = [op["name"] for op in discovery["operations"]]
        assert len(names) == len(set(names)) == 16
        assert {"registry.block", "registry.state.decode", "registry.state.resolve"} <= set(names)
        assert discovery["player_mode"] is False and discovery["subscriptions"] is False and discovery["batch"] is False
        for operation in discovery["operations"]:
            assert operation["input_schema"]["additionalProperties"] is False
        passed("actual catalog discovery and explicit unfinished surface")
        first.fault("PermissionDenied", "world.clock")
        first.fault("PermissionDenied", "registry.block", {"name": "minecraft:stone"})
        first.fault("AuthenticationFailed", "session.open", {"mode": "developer", "token": "incorrect"})
        first.fault("PlayerUnavailable", "session.open", {"mode": "player"})
        a = first.result("session.open", {"mode": "developer", "token": TOKEN})
        b = second.result("session.open", {"mode": "developer", "token": TOKEN})
        assert a["peer"] != b["peer"] and a["peer"] < b["peer"]
        first.result("simulation.pause", {"paused": True})
        clock = first.result("world.clock")
        assert clock["tick"] == 0 and clock["paused"] is True
        passed("independent sessions, capability checks and authentication")
        # Explicit official report entries are the oracle, rather than the
        # runtime TSV or the implementation's mixed-radix formula.
        blocks_path = ROOT / "reference/reports/reports/blocks.json"
        reports = json.loads(blocks_path.read_text())
        canonical = json.dumps(reports, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
        expected_hash = json.loads((ROOT / "reference/release.json").read_text())["reports"]["principal_reports"]["blocks.json"]["canonical_json_sha256"]
        assert hashlib.sha256(canonical).hexdigest() == expected_hash
        chosen = ["minecraft:air", "minecraft:stone", "minecraft:oak_log", "minecraft:water", "minecraft:oak_stairs", "minecraft:chest", "minecraft:mangrove_propagule"]
        registry_queries = 0
        for name in chosen:
            states = reports[name]["states"]
            metadata = first.result("registry.block", {"name": name})
            assert metadata["name"] == name and metadata["state_count"] == len(states)
            assert metadata["first_state_id"] == min(s["id"] for s in states)
            default = next(s for s in states if s.get("default"))
            assert metadata["default_state_id"] == default["id"]
            assert first.result("registry.state.resolve", {"name": name, "properties": {}, "policy": "defaults"})["state"] == default["id"]
            registry_queries += 2
            for state in [states[0], states[len(states) // 2], states[-1]]:
                props = dict(reversed(list(state.get("properties", {}).items())))
                resolved = first.result("registry.state.resolve", {"name": name, "properties": props, "policy": "exact"})
                assert resolved["state"] == state["id"]
                decoded = second.result("registry.state.decode", {"state": state["id"]})
                assert decoded["name"] == name and decoded["properties"] == props
                registry_queries += 2
        baseline = first.result("world.clock")
        first.fault("MissingProperty", "registry.state.resolve", {"name": "minecraft:oak_log", "properties": {}, "policy": "exact"})
        first.fault("InvalidValue", "registry.state.resolve", {"name": "minecraft:oak_log", "properties": {"axis": "q"}, "policy": "exact"})
        first.fault("UnknownProperty", "registry.state.resolve", {"name": "minecraft:stone", "properties": {"axis": "x"}, "policy": "defaults"})
        first.fault("InvalidArguments", "registry.state.resolve", {"name": "minecraft:oak_log", "properties": {"axis": 1}, "policy": "exact"})
        first.fault("InvalidArguments", "registry.state.resolve", {"name": "minecraft:oak_log", "properties": {}, "policy": "implicit"})
        first.fault("InvalidArguments", "registry.block", {"name": "minecraft:stone"}, at=1)
        first.fault("UnknownBlock", "registry.block", {"name": "test:missing"})
        first.fault("InvalidResource", "registry.block", {"name": "stone"})
        first.fault("InvalidState", "registry.state.decode", {"state": 35723})
        assert first.result("world.clock") == baseline
        passed("runtime registry queries match explicit official states and preserve world on rejection")
        origin = {"dimension": "minecraft:overworld", "x": 0, "y": 0, "z": 0}
        # Reverse arrival order. The earlier peer creates the section before the
        # later peer's edit when the same tick is applied.
        edit = second.result("world.block.set", origin | {"state": 1})
        created = first.result("world.section.create", origin | {"fill": 0})
        assert edit["stamp"]["tick"] == created["stamp"]["tick"] == 1
        first.fault("MissingSection", "world.block.get", origin)
        stepped = first.result("simulation.step", {"ticks": 1})
        assert stepped["tick"] == 1 and stepped["revision"] == 2
        assert first.result("world.block.get", origin)["state"] == 1
        assert second.result("world.block.get", origin)["state"] == 1
        passed("shared state and deterministic peer order despite reverse arrival")
        negative = {"dimension": "minecraft:overworld", "x": -17, "y": -1, "z": 31}
        first.result("world.section.create", negative | {"fill": 2}, at=4)
        first.result("simulation.step", {"ticks": 2})
        first.fault("MissingSection", "world.block.get", negative)
        first.result("simulation.step", {"ticks": 1})
        assert first.result("world.block.get", negative)["state"] == 2
        assert first.result("world.block.get", negative | {"x": -32, "y": -16, "z": 16})["state"] == 2
        assert first.result("world.block.get", origin)["state"] == 1
        passed("future scheduling, signed floor boundaries and section isolation")
        duplicate = first.result("world.section.create", origin | {"fill": 2})
        first.result("simulation.step", {"ticks": 1})
        assert first.result("world.block.get", origin)["state"] == 1
        duplicate_events = first.result("world.events")["events"]
        assert duplicate_events[0]["kind"] == "rejected" and duplicate_events[0]["error"]["code"] == "SectionExists"
        assert duplicate_events[0]["stamp"] == duplicate["stamp"]
        passed("application-time rejection event and existing-section rollback")
        baseline = first.result("world.clock")
        accepted = first.result("world.time.set", {"day_time": 9999}, at=baseline["tick"] + 4)
        stamp = accepted["stamp"]
        second.fault("PermissionDenied", "action.cancel", {"peer": stamp["peer"], "sequence": stamp["sequence"]})
        cancelled = first.result("action.cancel", {"peer": stamp["peer"], "sequence": stamp["sequence"], "tick": 0})
        assert cancelled["cancelled"] is True
        after = first.result("simulation.step", {"ticks": 4})
        assert after["day_time"] == baseline["day_time"] + 4
        passed("own action cancellation and cross-session rejection")
        baseline = first.result("world.clock")
        first.fault("InvalidState", "world.block.set", origin | {"state": 35723})
        first.fault("UnknownDimension", "world.block.set", origin | {"dimension": "invalid:dimension", "state": 0})
        first.fault("InvalidArguments", "world.block.get", origin | {"x": -2147483649})
        first.fault("InvalidArguments", "world.block.get", origin | {"x": 2147483648})
        first.fault("InvalidArguments", "world.block.get", origin | {"x": 1.0})
        first.fault("InvalidArguments", "simulation.step", {"ticks": 1001})
        first.fault("InvalidArguments", "simulation.step", {"ticks": 1, "unexpected": True})
        first.fault("InvalidArguments", "world.clock", at=123)
        first.fault("UnknownOperation", "worldgen.generate")
        assert first.result("world.clock") == baseline
        passed("strict schemas, bounds and unchanged world on rejected requests")
        # One scalar's bytes arrive separately, followed by CRLF. The ID must
        # survive native receive decoding and both serializers exactly.
        unicode_id = "分割-🙂-e\u0301"
        wire = json.dumps({"id": unicode_id, "op": "ping"}, ensure_ascii=False).encode() + b"\r\n"
        for byte in wire:
            first.socket.sendall(bytes([byte]))
        assert first.receive()["id"] == unicode_id
        first.socket.sendall(b'{"id":"duplicate","op":"ping","op":"world.clock"}\n')
        malformed = first.receive()
        assert malformed["id"] is None and malformed["error"]["code"] == "invalid_json"
        assert first.result("ping")["mode"] == "developer"
        passed("arbitrary UTF-8 receive splits, CRLF and parse-error recovery")
        requests = [{"id": f"batch-{i}", "op": "ping"} for i in range(3)]
        first.socket.sendall(b"".join(json.dumps(r).encode() + b"\n" for r in requests))
        assert [first.receive()["id"] for _ in requests] == [r["id"] for r in requests]
        passed("multiple NDJSON records in one send preserve response order")
        # Each independently connected client uses the actual socket interface.
        def concurrent_client(index):
            client = Client(port)
            try:
                client.result("session.open", {"mode": "developer", "token": TOKEN})
                return [client.result("world.block.get", origin)["state"] for _ in range(30)]
            finally:
                client.close()
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            observed = list(executor.map(concurrent_client, range(4)))
        assert observed == [[1] * 30] * 4
        passed("four concurrent external clients, 120 shared-state reads")
        prefix_client = Client(port)
        try:
            prefix_client.result("session.open", {"mode": "developer", "token": TOKEN})
            before_prefix = first.result("world.clock")["tick"]
            prefix = {"id": "valid-prefix", "op": "simulation.step", "args": {"ticks": 1}}
            prefix_client.socket.sendall(json.dumps(prefix).encode() + b"\n\xc0\xaf\n")
            delivered = prefix_client.receive()
            assert delivered["ok"] and delivered["id"] == "valid-prefix"
            assert delivered["result"]["tick"] == before_prefix + 1
            try:
                assert prefix_client.socket.recv(1) == b""
            except ConnectionResetError:
                pass
            assert first.result("world.clock")["tick"] == before_prefix + 1
        finally:
            prefix_client.close()
        passed("valid request before malformed frame applies independently of recv grouping")
        invalid = Client(port)
        try:
            invalid.socket.sendall(b"\xc0\xaf\n")
            try:
                assert invalid.socket.recv(1) == b""
            except ConnectionResetError:
                pass
        finally:
            invalid.close()
        assert first.result("world.block.get", origin)["state"] == 1
        passed("malformed UTF-8 disconnect preserves other sessions and world")
        # Paused actor receives realtime pulses but cannot advance simulation.
        before = first.result("world.clock")["tick"]
        time.sleep(0.16)
        assert first.result("world.clock")["tick"] == before
        first.result("simulation.pause", {"paused": False})
        time.sleep(0.28)
        first.result("simulation.pause", {"paused": True})
        realtime = first.result("world.clock")["tick"] - before
        assert 3 <= realtime <= 10, realtime
        passed("realtime 50ms driver and paused-state isolation")
        events = first.result("world.events")
        assert events["order"] == "newest-first" and len(events["events"]) == 4
        evidence = {"status": "passed", "kind": "actual_external_tcp_integration", "checks": checks,
                    "native_build": native_build,
                    "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                      for p in [ROOT / "server.bend", *[ROOT / f"src/{n}.bend" for n in ("server", "game", "registry", "live", "core", "schedule", "section", "section_map", "json", "framing")]]},
                    "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(), "compiler": "Bend 2.0.35",
                    "clients": 8, "concurrent_read_requests": 120, "realtime_ticks_over_280ms": realtime,
                    "official_registry_queries": registry_queries, "official_block_report_canonical_sha256": expected_hash,
                    "elapsed_seconds": round(time.perf_counter() - start, 3), "command": "python3 tools/test_server.py",
                    "vanilla_multiplayer_parity": False,
                    "limits": "Persistent developer foundation operations only; no actual player synchronization/gameplay, persistence, subscriptions, batching semantics, mod protocol or full vanilla systems yet."}
        (ROOT / "evidence/server-integration.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(json.dumps({"status": "passed", "checks": len(checks), "concurrent_read_requests": 120, "realtime_ticks": realtime}))
    finally:
        for client in clients:
            client.close()
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)
        error = process.stderr.read().decode(errors="replace")
        if error:
            print(error)

if __name__ == "__main__":
    main()
