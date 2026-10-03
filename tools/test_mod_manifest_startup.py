#!/usr/bin/env python3
"""Exercise the actual compiled driver's manifest gate before TCP startup."""
from __future__ import annotations

import copy
import hashlib
import json
import os
from pathlib import Path
import select
import socket
import subprocess
import tempfile
import time

from test_server import Client, TOKEN, free_port

ROOT = Path(__file__).resolve().parents[1]
BEND = Path.home() / ".bend/bin/bend"
SOURCE = "mods/examples/time_overhaul.bend"
MANIFEST = "mods/examples/time_overhaul.json"


def encoded(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()


def environment(port, path):
    env = os.environ.copy()
    env.pop("MC_MOD_MANIFEST", None)
    env.pop("MC_BLOCK_REGISTRY", None)
    env.update(MC_DEV_TOKEN=TOKEN, MC_LIVE_PORT=str(port))
    if path is not None:
        env["MC_MOD_MANIFEST"] = str(path)
    return env


def start(binary, port, path):
    return subprocess.Popen([str(binary), "--threads", "4", "--gpu", "off"],
                            cwd=ROOT, env=environment(port, path),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def stop(process):
    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=3)
    stderr = process.stderr.read().decode(errors="replace")
    assert TOKEN not in stderr, stderr
    return stderr


def valid(binary, name, path, manifest):
    port = free_port()
    process = start(binary, port, path)
    client = None
    try:
        assert select.select([process.stdout], [], [], 10)[0], (name, "startup timeout")
        ready = json.loads(process.stdout.readline())
        assert ready["event"] == "server.ready" and ready["port"] == port, (name, ready)
        client = Client(port)
        catalog = client.result("discover")["operations"]
        declared = set(manifest["operations"] + manifest["queries"])
        custom = {op["name"] for op in catalog if op["name"].startswith("mod.time_overhaul.")}
        assert custom == declared and len(catalog) == 18, (name, custom, declared)
        client.result("session.open", {"mode": "developer", "token": TOKEN})
        status = client.result("mod.time_overhaul.status")
        assert status["mod"] == manifest["id"] and status["ticks_per_pulse"] == 1, (name, status)
        # Validate that the same compiled handler remains installed after the gate.
        assert client.result("mod.time_overhaul.configure", {"ticks_per_pulse": 3})["ticks_per_pulse"] == 3
        assert client.result("mod.time_overhaul.status")["ticks_per_pulse"] == 3
    finally:
        if client is not None:
            client.close()
        assert stop(process) == "", name
    return {"name": name, "status": "ready", "discovered_tools": 18}


def invalid(binary, name, path, expected):
    port = free_port()
    env = environment(port, path)
    # The manifest must fail before registry loading and transport configuration.
    env.update(MC_BLOCK_REGISTRY="/nonexistent/manifest-must-fail-before-registry", MC_DEV_TOKEN="")
    result = subprocess.run([str(binary), "--threads", "4", "--gpu", "off"],
                            cwd=ROOT, env=env, capture_output=True, timeout=10)
    stdout = result.stdout.decode(errors="replace")
    stderr = result.stderr.decode(errors="replace")
    assert result.returncode == 2, (name, result.returncode, stdout, stderr)
    assert stdout == "" and "server.ready" not in stderr, (name, stdout, stderr)
    assert "mod manifest startup: " + expected in stderr, (name, expected, stderr)
    assert "registry loading failed" not in stderr and "MC_DEV_TOKEN" not in stderr, (name, stderr)
    assert TOKEN not in stderr, (name, stderr)
    with socket.socket() as probe:
        assert probe.connect_ex(("127.0.0.1", port)) != 0, (name, "listener opened")
    return {"name": name, "status": "rejected-before-ready", "exit_code": result.returncode,
            "diagnostic": stderr.strip()}


def main():
    started = time.monotonic()
    binary = ROOT / "build/time-overhaul-manifest-tests"
    (ROOT / "build").mkdir(exist_ok=True)
    checked = subprocess.run([str(BEND), SOURCE, "--check-only"], cwd=ROOT,
                             capture_output=True, text=True, timeout=60)
    # The IO executable already reaches the standard server's unsafe loops;
    # keep that result visible rather than claiming pure module verification.
    checker_output = (checked.stdout + checked.stderr).strip()
    assert "7 defs rely on unsafe or foreign code" in checker_output, checker_output
    assert "startup_" not in checker_output, checker_output
    subprocess.run([str(BEND), SOURCE, "-o", str(binary)], cwd=ROOT, check=True, timeout=120)
    base = json.loads((ROOT / MANIFEST).read_text())
    outcomes = []
    outcomes.append(valid(binary, "default-file", None, base))
    outcomes.append(valid(binary, "explicit-relative-path", MANIFEST, base))
    with tempfile.TemporaryDirectory(prefix="bend-mod-manifest-") as temporary:
        folder = Path(temporary)
        def fixture(name, content):
            path = folder / (name + ".json")
            path.write_bytes(content)
            return path
        def changed(**fields):
            value = copy.deepcopy(base)
            value.update(fields)
            return encoded(value)
        good = [
            ("explicit-absolute-path", encoded(base)),
            ("normalized-version-triples", changed(version=[1, 0, 0], api_version=[1, 0, 0])),
            ("optional-empty-requirements", encoded({key: value for key, value in base.items()
                                                     if key not in ["dependencies", "before", "after", "events"]})),
            ("decoded-ascii-escapes", encoded(base).replace(b"bendex:time_overhaul", b"\\u0062endex:time_overhaul")
                                               .replace(b"mod.time_overhaul.status", b"mod.time_overhaul.\\u0073tatus")),
            ("maximum-codepoint-file", encoded(base) + b" " * (16384 - len(encoded(base))))
        ]
        for name, content in good:
            outcomes.append(valid(binary, name, fixture(name, content), base))
        bad = [
            ("compiled-identity", changed(id="bendex:other"), "CompiledIdentityMismatch:"),
            ("compiled-version", changed(version="1.1.0"), "CompiledVersionMismatch:"),
            ("compiled-api", changed(api_version="2.0.0"), "ApiVersionMismatch:"),
            ("compiled-side-client", changed(side="client"), "CompiledSideMismatch:"),
            ("compiled-side-both", changed(side="both"), "CompiledSideMismatch:"),
            ("missing-operation", changed(operations=[]), "CompiledOperationsMismatch:"),
            ("unknown-operation", changed(operations=["mod.time_overhaul.other"]), "CompiledOperationsMismatch:"),
            ("extra-operation", changed(operations=base["operations"] + ["mod.time_overhaul.other"]), "CompiledOperationsMismatch:"),
            ("missing-query", changed(queries=[]), "CompiledQueriesMismatch:"),
            ("unknown-query", changed(queries=["mod.time_overhaul.other"]), "CompiledQueriesMismatch:"),
            ("swapped-callable-roles", changed(operations=base["queries"], queries=base["operations"]), "CompiledOperationsMismatch:"),
            ("undeclared-runtime-events", changed(events=["mod.time_overhaul.pulse"]), "CompiledEventsMismatch:"),
            ("compiled-data-version", changed(data_version=1), "CompiledDataVersionMismatch:"),
            ("unsupported-hot-reload", changed(reload="safe"), "CompiledReloadMismatch:"),
            ("missing-dependency", changed(dependencies=[{"id": "bendex:absent", "range": {}}]), "MissingDependency:"),
            ("self-dependency-cycle", changed(dependencies=[{"id": base["id"], "range": {}}]), "Cycle:"),
            ("incompatible-self-version", changed(dependencies=[{"id": base["id"], "range": {"min": {"version": "2.0.0", "inclusive": True}}}]), "IncompatibleDependency:"),
            ("missing-order-before", changed(before=["bendex:absent"]), "MissingOrderTarget:"),
            ("self-order-after-cycle", changed(after=[base["id"]]), "Cycle:"),
            ("unknown-field", changed(unknown=True), "InvalidManifest:"),
            ("wrong-field-type", changed(data_version="0"), "InvalidManifest:"),
            ("wrong-side-value", changed(side="dedicated"), "InvalidManifest:"),
            ("missing-version", encoded({key: value for key, value in base.items() if key != "version"}), "InvalidManifest:"),
            ("malformed-version", changed(version="01.0.0"), "InvalidManifest:"),
            ("version-u32-overflow", changed(version=[4294967296, 0, 0]), "InvalidManifest:"),
            ("duplicate-declaration", changed(operations=base["operations"] * 2), "InvalidMetadata:"),
            ("duplicate-json-member", encoded(base).replace(b'{', b'{"id":"bendex:time_overhaul",', 1), "ManifestJSON:"),
            ("trailing-json-junk", encoded(base) + b"{}", "ManifestJSON:"),
            ("empty-file", b"", "ManifestJSON:"),
            ("json-syntax", b'{"id":', "ManifestJSON:"),
            ("overlong-utf8-ascii", encoded(base).replace(b"bendex:", b"bendex\xc0\xba"), "ManifestUTF8:"),
            ("utf8-surrogate", b'"\xed\xa0\x80"', "ManifestUTF8:"),
            ("utf8-out-of-range", b'"\xf4\x90\x80\x80"', "ManifestUTF8:"),
            ("utf8-truncated", encoded(base) + b"\xe2", "ManifestUTF8:"),
            ("utf8-continuation", encoded(base) + b"\x80", "ManifestUTF8:"),
            ("codepoint-limit", encoded(base) + b" " * (16385 - len(encoded(base))), "ManifestUTF8:"),
            ("byte-limit", encoded(base) + b" " * (65537 - len(encoded(base))), "ManifestSize:"),
            ("json-depth-limit", b'[' * 65 + b'0' + b']' * 65, "ManifestJSON:")
        ]
        for name, content, expected in bad:
            outcomes.append(invalid(binary, name, fixture(name, content), expected))
        outcomes.append(invalid(binary, "missing-file", folder / "missing.json", "ManifestReadError:"))
        outcomes.append(invalid(binary, "directory-file", folder, "ManifestReadError:"))
        outcomes.append(invalid(binary, "explicit-empty-path", "", "ManifestReadError:"))
    sources = [SOURCE, MANIFEST, "src/mods.bend", "src/json.bend", "src/framing.bend", "src/server.bend", "src/game.bend", "tools/test_mod_manifest_startup.py"]
    report = {"schema": 1, "status": "passed", "kind": "actual_compiled_driver_manifest_startup",
              "command": "python3 tools/test_mod_manifest_startup.py", "build_command": f"{BEND} {SOURCE} -o build/time-overhaul-manifest-tests",
              "source_sha256": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in sources},
              "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
              "checker": {"exit_code": checked.returncode, "output": checker_output},
              "valid_startups": sum(case["status"] == "ready" for case in outcomes),
              "invalid_startups": sum(case["status"] != "ready" for case in outcomes), "cases": outcomes,
              "elapsed_seconds": round(time.monotonic() - started, 3),
              "limits": "One compile-time linked typed driver; startup metadata validation precedes registry loading/listener startup. No runtime code loading, lifecycle hook execution, hot reload, state migration or persistence established."}
    (ROOT / "evidence/mods-startup.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({key: report[key] for key in ["status", "valid_startups", "invalid_startups", "elapsed_seconds"]}))


if __name__ == "__main__":
    main()
