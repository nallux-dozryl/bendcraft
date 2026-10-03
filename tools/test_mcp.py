#!/usr/bin/env python3
"""Actual MCP stdio subprocess -> persistent loopback TCP -> native Bend server.

This is an independent protocol client/test orchestrator. It contains no game
implementation or MCP server SDK/adapter. Tokens and raw secret-bearing request
bodies are never printed or included in saved evidence.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
from decimal import Decimal
import hashlib
import json
import os
from pathlib import Path
import select
import socket
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
TOKEN = "integration-test-token"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def free_port() -> int:
    with socket.socket() as held:
        held.bind(("127.0.0.1", 0))
        return held.getsockname()[1]


def encode(value: dict) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8") + b"\n"


class MCP:
    def __init__(self, binary: Path, port: int, token: str | None):
        environment = os.environ.copy()
        environment["MC_LIVE_PORT"] = str(port)
        environment.pop("MC_DEV_TOKEN", None)
        if token is not None:
            environment["MC_DEV_TOKEN"] = token
        self.process = subprocess.Popen([str(binary), "--threads", "1", "--gpu", "off"],
                                        cwd=ROOT, env=environment, stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.buffer = b""
        self.sequence = 0
        self.live_sequence = 0
        self.requests = 0
        self.responses = 0
        self.notifications = 0

    def raw(self, data: bytes, fragment: bool = False) -> None:
        require(self.process.stdin is not None and not self.process.stdin.closed, "MCP stdin already closed")
        if fragment:
            for byte in data:
                self.process.stdin.write(bytes([byte]))
                self.process.stdin.flush()
                time.sleep(0.001)
        else:
            self.process.stdin.write(data)
            self.process.stdin.flush()

    def receive(self, timeout: float = 5) -> dict:
        deadline = time.monotonic() + timeout
        while b"\n" not in self.buffer:
            remaining = deadline - time.monotonic()
            require(remaining > 0, "MCP response timed out")
            require(bool(select.select([self.process.stdout], [], [], remaining)[0]), "MCP response timed out")
            chunk = os.read(self.process.stdout.fileno(), 8192)
            require(bool(chunk), "MCP stdout closed before its response")
            self.buffer += chunk
        line, self.buffer = self.buffer.split(b"\n", 1)
        require(TOKEN.encode() not in line, "MCP leaked the configured token")
        try:
            value = json.loads(line.decode("utf-8", errors="strict"), parse_float=Decimal)
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise AssertionError("MCP stdout contained a non-JSON or invalid UTF-8 message") from None
        require(isinstance(value, dict) and value.get("jsonrpc") == "2.0", "invalid JSON-RPC response")
        require(("result" in value) != ("error" in value), "response must have exactly one of result/error")
        self.responses += 1
        return value

    def no_response(self, duration: float = 0.06) -> None:
        require(not self.buffer, "unexpected buffered notification response")
        require(not select.select([self.process.stdout], [], [], duration)[0], "notification produced stdout")

    def request(self, method: str, params: dict | None = None, expected_error: int | None = None,
                fragment: bool = False, id_value=None) -> dict:
        self.sequence += 1
        identity = self.sequence if id_value is None else id_value
        request = {"jsonrpc": "2.0", "id": identity, "method": method}
        if params is not None:
            request["params"] = params
        self.requests += 1
        self.raw(encode(request), fragment=fragment)
        value = self.receive()
        require(value.get("id") == identity, "MCP request/response id mismatch")
        if expected_error is not None:
            require(value.get("error", {}).get("code") == expected_error, "unexpected JSON-RPC error code")
        else:
            require("result" in value, "expected MCP result response")
        return value

    def notify(self, method: str, params: dict | None = None) -> None:
        request = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            request["params"] = params
        self.notifications += 1
        self.raw(encode(request))

    def initialize(self, version: str = "2025-11-25", fragment: bool = False) -> dict:
        value = self.request("initialize", {"protocolVersion": version, "capabilities": {},
                             "clientInfo": {"name": "independent-stdio-test", "version": "1"}},
                             fragment=fragment, id_value="initialize-分割-🙂")
        result = value["result"]
        require(result["protocolVersion"] == "2025-11-25", "wrong negotiated protocol version")
        require(result["capabilities"] == {"tools": {"listChanged": False}}, "unsupported capability advertised")
        require(result["serverInfo"]["name"] == "minecraft-bend-foundation", "wrong server implementation identity")
        self.notify("notifications/initialized")
        return result

    def call(self, name: str, args: dict | None = None, *, fault: str | None = None, **extra) -> dict:
        self.live_sequence += 1
        identity = f"tool-envelope-{self.live_sequence}"
        envelope = {"id": identity, "op": name}
        if args is not None:
            envelope["args"] = args
        envelope.update(extra)
        response = self.request("tools/call", {"name": name, "arguments": envelope})["result"]
        structured = response["structuredContent"]
        require(response["content"] == [{"type": "text", "text": response["content"][0]["text"]}], "invalid text content shape")
        require(json.loads(response["content"][0]["text"]) == structured, "text and structured live results differ")
        require(response["isError"] is (structured["ok"] is False), "tool error flag differs from live result")
        require(structured["id"] == identity, "live envelope id changed")
        if fault is None:
            require(structured["ok"] is True, "expected successful live operation")
            return structured["result"]
        require(structured["ok"] is False and structured["error"]["code"] == fault, "unexpected live tool error")
        return structured

    def finish(self) -> None:
        if self.process.stdin is not None and not self.process.stdin.closed:
            self.process.stdin.close()
        self.process.wait(timeout=5)
        trailing = self.buffer + self.process.stdout.read()
        error = self.process.stderr.read()
        require(not trailing, "unexpected trailing MCP stdout")
        require(TOKEN.encode() not in error, "MCP stderr leaked configured token")
        require(self.process.returncode == 0 and not error, "MCP did not shut down cleanly at EOF")

    def cleanup(self) -> None:
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=3)
        for stream in [self.process.stdin, self.process.stdout, self.process.stderr]:
            if stream is not None and not stream.closed:
                stream.close()


def discover_tcp(port: int) -> dict:
    with socket.create_connection(("127.0.0.1", port), timeout=5) as connection:
        connection.sendall(encode({"id": "independent-discovery", "op": "discover"}))
        with connection.makefile("rb") as reader:
            value = json.loads(reader.readline(262145))
        require(value["ok"] is True, "independent TCP discovery failed")
        return value["result"]


def build(command: list[str | Path]) -> subprocess.CompletedProcess[str]:
    result = subprocess.run([str(part) for part in command], cwd=ROOT,
                            text=True, capture_output=True, timeout=120)
    require(result.returncode == 0, "Bend native build/check failed: " + result.stdout + result.stderr)
    return result


def fingerprint(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bend", type=Path, default=Path.home() / ".bend/bin/bend")
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()
    started = time.monotonic()
    native = ROOT / "build/minecraft-mcp"
    server_binary = ROOT / "build/mcp-test-server"
    server = None
    clients: list[MCP] = []
    checks: list[str] = []
    try:
        framing_verdict = build([args.bend, "tests/framing.bend", "--verdict"])
        # Reuse only digest-verified compilation; every protocol/proof check
        # below still runs. Explicit --skip-build retains its legacy behavior.
        native_builds = {}
        if not args.skip_build:
            from build_native import ensure_native
            for source, output in [("mcp.bend", native), ("server.bend", server_binary)]:
                native_builds[source] = ensure_native(ROOT/source, output, bend=args.bend)
            native = Path(native_builds["mcp.bend"]["artifact"])
            server_binary = Path(native_builds["server.bend"]["artifact"])
        port = free_port()
        environment = os.environ.copy()
        environment.update(MC_LIVE_PORT=str(port), MC_DEV_TOKEN=TOKEN,
                           MC_BLOCK_REGISTRY=str(ROOT / "generated/reference_blocks.tsv"))
        server = subprocess.Popen([str(server_binary), "--threads", "2", "--gpu", "off"],
                                  cwd=ROOT, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        require(bool(select.select([server.stdout], [], [], 10)[0]), "native live server startup timed out")
        ready = json.loads(server.stdout.readline())
        require(ready.get("port") == port and ready.get("status") == "foundation", "wrong native server readiness")
        direct = discover_tcp(port)
        operations = direct["operations"]
        require(bool(operations) and len({operation["name"] for operation in operations}) == len(operations),
                "empty or duplicate live operation catalog")
        tool_count = len(operations)
        first = MCP(native, port, TOKEN)
        clients.append(first)
        first.request("ping")
        first.request("tools/list", expected_error=-32002)
        first.notify("notifications/initialized")
        first.request("tools/call", {"name": "ping"}, expected_error=-32002)
        first.request("initialize", {"protocolVersion": "2025-11-25"}, expected_error=-32602)
        result = first.request("initialize", {"protocolVersion": "2025-11-25", "capabilities": {},
                               "clientInfo": {"name": "independent-test", "version": "1"}},
                               fragment=True, id_value="initialize-分割-🙂")["result"]
        require(result["protocolVersion"] == "2025-11-25", "wrong initialization version")
        first.request("tools/list", expected_error=-32002)
        first.notify("notifications/initialized")
        first.notify("notifications/unknown")
        first.no_response()
        first.request("initialize", {}, expected_error=-32600)
        checks.append("actual UTF-8 stdio initialization, phase enforcement, ping and silent notifications")

        listed = first.request("tools/list")["result"]["tools"]
        expected = [{"name": operation["name"], "description": operation["description"],
                     "inputSchema": operation["input_schema"]} for operation in direct["operations"]]
        require(listed == expected, "MCP tools differ from actual independently queried live schemas")
        require([tool["name"] for tool in listed] == [tool["name"] for tool in
                first.request("tools/list")["result"]["tools"]], "tool order changed between discoveries")
        first.request("tools/list", {"cursor": "unsupported"}, expected_error=-32602)
        first.request("tools/call", {"name": "worldgen.generate", "arguments": {}}, expected_error=-32602)
        first.request("tools/call", {"name": "ping", "arguments": {"op": "simulation.step"}}, expected_error=-32602)
        first.request("tools/call", {"arguments": {}}, expected_error=-32602)
        first.request("tools/call", {"name": "ping", "arguments": []}, expected_error=-32602)
        automatic = first.request("tools/call", {"name": "ping", "arguments": {}})["result"]["structuredContent"]
        require(automatic["ok"] is True and automatic["id"].startswith("mcp-live-"), "missing generated live identity/op")
        checks.append(f"{tool_count} tool names, descriptions and full input schemas derived from actual TCP discover; unknown/name-op validation")

        names = {tool["name"] for tool in listed}
        if {"registry.block", "registry.state.decode", "registry.state.resolve"} <= names:
            metadata = first.call("registry.block", {"name": "minecraft:oak_log"})
            state = metadata["default_state_id"]
            decoded = first.call("registry.state.decode", {"state": state})
            require(decoded["name"] == "minecraft:oak_log", "dynamic registry tool returned wrong block")
            resolved = first.call("registry.state.resolve", {"name": decoded["name"],
                                  "properties": decoded["properties"], "policy": "exact"})
            require(resolved["state"] == state, "newly discovered registry tool could not be called")
            checks.append("new registry extension operations list and execute without an MCP operation whitelist")

        first.call("simulation.pause", {"paused": True})
        peer = first.call("ping")["peer"]
        second = MCP(native, port, TOKEN)
        clients.append(second)
        second.initialize(version="2099-01-01")
        other_peer = second.call("ping")["peer"]
        require(peer != other_peer, "independent MCP processes share a live session identity")
        origin = {"dimension": "minecraft:overworld", "x": -17, "y": -1, "z": 31}
        baseline = first.call("world.clock")
        created = first.call("world.section.create", origin | {"fill": 0})
        require(created["stamp"]["peer"] == peer and created["stamp"]["tick"] == baseline["tick"] + 1, "create stamp differs")
        first.call("world.block.get", origin, fault="MissingSection")
        first.call("simulation.step", {"ticks": 1})
        require(first.call("world.block.get", origin)["state"] == 0, "creation was not applied")
        first.call("world.block.set", origin | {"state": 1})
        require(first.call("world.block.get", origin)["state"] == 0, "scheduled set applied before tick")
        first.call("simulation.step", {"ticks": 1})
        require(first.call("world.block.get", origin)["state"] == 1, "scheduled set did not apply")
        require(second.call("world.block.get", origin)["state"] == 1, "second real MCP process did not see shared world")
        before_cancel = first.call("world.clock")
        future = first.call("world.time.set", {"day_time": 9999}, at=before_cancel["tick"] + 3)["stamp"]
        second.call("action.cancel", {"peer": future["peer"], "sequence": future["sequence"]}, fault="PermissionDenied")
        require(first.call("action.cancel", {"peer": future["peer"], "sequence": future["sequence"]})["cancelled"] is True,
                "own scheduled action could not be cancelled across MCP calls")
        after_cancel = first.call("simulation.step", {"ticks": 3})
        require(after_cancel["day_time"] == before_cancel["day_time"] + 3, "cancelled time mutation applied")
        require(len(first.call("world.events")["events"]) >= 2, "live events were not exposed")
        checks.append("actual create/set/step/query/cancel across persistent stdio/TCP sessions and two shared-state MCP clients")

        unchanged = first.call("world.clock")
        first.call("simulation.step", {"ticks": 0}, fault="InvalidArguments")
        first.call("simulation.step", {"ticks": 1001}, fault="InvalidArguments")
        first.call("world.block.set", origin | {"state": 35723}, fault="InvalidState")
        first.call("world.block.get", origin | {"x": "-17"}, fault="InvalidArguments")
        first.call("world.clock", {"unexpected": True}, fault="InvalidArguments")
        first.call("world.clock", unexpected=True, fault="InvalidRequest")
        require(first.call("world.clock") == unchanged, "rejected tool calls changed simulation state")
        observer = MCP(native, port, None)
        clients.append(observer)
        observer.initialize()
        require(observer.request("tools/list")["result"]["tools"] == expected, "observer discovery differs")
        require(observer.call("ping")["mode"] == "observer", "absent token escalated capability")
        observer.call("world.clock", fault="PermissionDenied")
        observer.call("session.open", {"mode": "developer"}, fault="AuthenticationFailed")
        observer.call("session.open", {"mode": "player"}, fault="PlayerUnavailable")
        require(observer.call("ping")["mode"] == "observer", "rejected authentication changed observer capability")
        checks.append("live permission/schema/domain failures returned as isError tool results with matching text/structured content")

        first.raw(b'{"jsonrpc":"2.0","id":90,"method":"ping",}\n')
        require(first.receive()["error"]["code"] == -32700, "malformed JSON was not parse error")
        first.raw(b'{"jsonrpc":"2.0","id":91,"method":"ping","method":"tools/list"}\n')
        require(first.receive()["error"]["code"] == -32700, "duplicate JSON key was not parse error")
        for value in [[], True, 17]:
            first.raw(json.dumps(value).encode() + b"\n")
            require(first.receive()["error"]["code"] == -32600, "nonobject/batch was accepted")
        first.request("unknown/method", expected_error=-32601)
        for identity, change, code in [
            (100001, {"jsonrpc": "2.1"}, -32600),
            (100002, {"method": 3}, -32600),
            (100003, {"params": []}, -32602),
        ]:
            request = {"jsonrpc": "2.0", "id": identity, "method": "ping"} | change
            first.raw(encode(request))
            response = first.receive()
            require(response["id"] == identity and response["error"]["code"] == code, "malformed request id/code mismatch")
        for raw in [b"null", b"true", b"100004.5", b"-100009.01", b"123.001e-1", b"1e-400", b"1e-999999"]:
            first.raw(b'{"jsonrpc":"2.0","id":' + raw + b',"method":"ping"}\n')
            response = first.receive()
            require(response["id"] is None and response["error"]["code"] == -32600, "invalid MCP id was accepted")
        for raw in [b"100005.0", b"1000060e-1", b"-1000070e-1", b"0.001234e7", b"100008000e-3",
                    b"1.230001e6", b"-0e-999999", b"1e400", b"1e999999", '"identity-分割-🙂"'.encode("utf-8")]:
            first.raw(b'{"jsonrpc":"2.0","id":' + raw + b',"method":"ping"}\n', fragment=True)
            response = first.receive()
            require(response["id"] == json.loads(raw, parse_float=Decimal) and response["result"] == {}, "valid exact integer/string id changed")
        first.notify("notifications/cancelled", {"requestId": "none"})
        first.notify("tools/call", {"name": "simulation.step", "arguments": {"args": {"ticks": 1000}}})
        first.no_response()
        require(first.call("world.clock") == unchanged, "a request-only tool notification mutated the world")
        checks.append("JSON-RPC parse/invalid-request/method/params errors, exact integer IDs, Unicode splits and silent notifications")

        prefix = MCP(native, port, TOKEN)
        clients.append(prefix)
        prefix.initialize()
        before_prefix = first.call("world.clock")["tick"]
        prefix_request = {"jsonrpc": "2.0", "id": "valid-prefix", "method": "tools/call",
                          "params": {"name": "simulation.step", "arguments": {"op": "simulation.step", "args": {"ticks": 1}}}}
        prefix.raw(encode(prefix_request) + b"\xc0\xaf\n")
        require(prefix.receive()["result"]["structuredContent"]["result"]["tick"] == before_prefix + 1,
                "valid request before malformed UTF-8 was lost")
        require(prefix.receive()["error"]["code"] == -32700, "malformed UTF-8 did not produce a protocol error")
        prefix.process.wait(timeout=5)
        require(prefix.process.returncode == 0, "malformed input did not close the adapter")
        require(first.call("world.clock")["tick"] == before_prefix + 1, "valid prefix applied wrong number of times")
        partial = MCP(native, port, None)
        clients.append(partial)
        partial.raw(b'{"jsonrpc":"2.0","id":1')
        partial.process.stdin.close()
        require(partial.receive()["error"]["code"] == -32700, "partial EOF record was flushed or ignored")
        partial.process.wait(timeout=5)
        require(partial.process.returncode == 0, "partial EOF did not terminate cleanly")
        checks.append("LF segmentation preserves valid mutation before malformed later stdin frame; partial EOF is rejected")

        # Invalid startup credentials must produce stderr only, never JSON or
        # secret-bearing diagnostic text. Only the fixed test token is used.
        for configured in ["wrong-integration-token"]:
            bad = MCP(native, port, configured)
            clients.append(bad)
            bad.process.stdin.close()
            bad.process.wait(timeout=5)
            output, diagnostic = bad.process.stdout.read(), bad.process.stderr.read()
            require(bad.process.returncode != 0 and output == b"", "startup authentication failure polluted stdout")
            require(configured.encode() not in diagnostic and TOKEN.encode() not in diagnostic,
                    "startup authentication leaked a token")
        checks.append("configured developer authentication stays on the persistent live session; rejected tokens never reach stdout/stderr")

        second.finish()
        observer.finish()
        server.terminate()
        server.wait(timeout=5)
        first.request("tools/list", expected_error=-32603)
        first.request("ping")
        disconnected = first.request("tools/call", {"name": "ping", "arguments": {}})["result"]
        require(disconnected["isError"] is True and disconnected["structuredContent"]["error"]["code"] == "LiveTransportError",
                "live disconnect did not return a tool transport error")
        first.finish()
        checks.append("real live-server disconnect returns protocol/tool errors while MCP ping remains usable; clean stdio EOF shutdown")

        checker = subprocess.run([str(args.bend), "mcp.bend", "--check-only"], cwd=ROOT,
                                 text=True, capture_output=True, timeout=120)
        require(checker.returncode == 1 and "rely on unsafe or foreign code" in checker.stderr,
                "IO lifetime proof boundary was hidden")
        source_files = [ROOT / "mcp.bend", ROOT / "src/mcp.bend", ROOT / "src/framing.bend",
                        ROOT / "tests/framing.bend", ROOT / "src/json.bend", ROOT / "server.bend",
                        ROOT / "src/server.bend", ROOT / "src/live.bend", ROOT / "src/game.bend",
                        ROOT / "src/core.bend", ROOT / "src/registry.bend", Path(__file__).resolve()]
        evidence = {
            "status": "passed", "kind": "actual_mcp_stdio_and_live_tcp_integration",
            "native_builds": native_builds,
            "recorded_at_utc": datetime.now(timezone.utc).isoformat(), "command": "python3 tools/test_mcp.py" + (" --skip-build" if args.skip_build else ""),
            "checks": checks, "current_tool_count": tool_count, "mcp_processes": len(clients),
            "stdio_responses_observed": sum(client.responses for client in clients),
            "stdio_requests_sent": sum(client.requests for client in clients),
            "notifications_sent": sum(client.notifications for client in clients),
            "source_sha256": {str(path.relative_to(ROOT)): fingerprint(path) for path in source_files},
            "binary_sha256": {"mcp": fingerprint(native), "live_server": fingerprint(server_binary)},
            "registry_input_sha256": fingerprint(ROOT / "generated/reference_blocks.tsv"),
            "compiler_sha256": fingerprint(args.bend), "protocol_version": "2025-11-25",
            "checker_boundary": {"returncode": checker.returncode, "stdout": checker.stdout, "stderr": checker.stderr},
            "framing_verdict": {"returncode": framing_verdict.returncode,
                                "stdout": framing_verdict.stdout, "stderr": framing_verdict.stderr},
            "official_sources": [
                "https://modelcontextprotocol.io/specification/2025-11-25/basic",
                "https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle",
                "https://modelcontextprotocol.io/specification/2025-11-25/basic/transports",
                "https://modelcontextprotocol.io/specification/2025-11-25/server/tools",
            ],
            "limits": [
                "Foundation live operations only; no full Minecraft behavior or vanilla multiplayer parity.",
                "Serial synchronous MCP requests; no tasks, subscriptions, server-to-client requests or list-change notifications.",
                "Schemas are forwarded from actual live discovery; game authorization/validation stays in live/core.",
                "Stalled live reads use Base recv_bytes without a wall-clock deadline; process termination is the client fallback.",
                "IO lifetime recursion is unsafe; pure framing/protocol/schema code is checked but has no universal MCP correctness proof.",
            ],
            "elapsed_seconds": round(time.monotonic() - started, 3),
        }
        (ROOT / "evidence/mcp-integration.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(json.dumps({"status": "passed", "checks": len(checks), "tools": tool_count,
                          "mcp_processes": len(clients), "stdio_responses": evidence["stdio_responses_observed"]}))
        return 0
    except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
        print("MCP verification failed: " + str(error))
        return 1
    finally:
        for client in clients:
            client.cleanup()
        if server is not None and server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=3)


if __name__ == "__main__":
    raise SystemExit(main())
