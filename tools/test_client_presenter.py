#!/usr/bin/env python3
"""Actual hidden presenter/actor integration; Python only orchestrates tests."""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time

from platform_cache import ensure_platform
import platform_build
import platform_test

ROOT = Path(__file__).resolve().parents[1]
ENTRY = ROOT / "tests/client_presenter.bend"
BINARY = ROOT / "build/client-presenter-tests"
BUILD = ROOT / "build/client-presenter-build.json"
BEND = Path.home() / ".bend/bin/bend"
REPORT = ROOT / "evidence/client-presenter-native.json"
TOKEN = "presenter-integration-local-only"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ordinary_check() -> dict:
    started = time.monotonic()
    result = subprocess.run([str(BEND), str(ENTRY), "--check-only"], cwd=ROOT,
                            capture_output=True, text=True, timeout=30)
    diagnostic = result.stdout + result.stderr
    refused = [line[2:] for line in diagnostic.splitlines() if line.startswith("- ")]
    assert result.returncode == 1 and "Error: 38 defs rely on unsafe or foreign code:" in diagnostic, diagnostic
    assert len(refused) == 38 and refused[-1] == "main", diagnostic
    assert "../src/window_input.Native.status" in refused and "../src/client_presenter.loop" in refused, diagnostic
    return {"command": [str(BEND), "tests/client_presenter.bend", "--check-only"],
            "exit_code": result.returncode, "seconds": time.monotonic()-started,
            "admission": "typing and affine ownership reach exactly the declared native/unsafe refusals",
            "whole_module_proof": False, "stdout": result.stdout, "stderr": result.stderr}


def build_bounded(seconds: int) -> dict:
    command = [sys.executable, str(Path(__file__).resolve()), "--build-only"]
    child = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True, start_new_session=True)
    print(json.dumps({"event": "presenter.build_started", "pid": child.pid,
                      "timeout_seconds": seconds}), flush=True)
    try:
        stdout, stderr = child.communicate(timeout=seconds)
    except subprocess.TimeoutExpired:
        os.killpg(child.pid, signal.SIGTERM)
        try:
            stdout, stderr = child.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            stdout, stderr = child.communicate()
        raise AssertionError({"build_timeout_seconds": seconds, "stdout": stdout, "stderr": stderr})
    assert child.returncode == 0, {"stdout": stdout, "stderr": stderr, "exit_code": child.returncode}
    report = json.loads(BUILD.read_text())
    assert report["route"] == "guarded-macos-cpu-window" and sha(BINARY) == report["binary_sha256"]
    return report


def port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def request(stream, request_id: str, operation: str, args: dict | None = None) -> dict:
    value = {"id": request_id, "op": operation}
    if args is not None:
        value["args"] = args
    stream.write(json.dumps(value).encode()+b"\n")
    stream.flush()
    raw = stream.readline()
    assert raw, f"transport closed before {operation} reply"
    reply = json.loads(raw)
    assert reply["id"] == request_id and reply["ok"] is True, reply
    return reply


def clocks(outer: subprocess.Popen, number: int) -> list[dict]:
    deadline = time.monotonic()+5
    connection = None
    while connection is None:
        assert outer.poll() is None and time.monotonic() < deadline, "presenter exited before live transport was queried"
        try:
            connection = socket.create_connection(("127.0.0.1", number), timeout=.1)
        except (ConnectionRefusedError, TimeoutError):
            time.sleep(.002)
    with connection:
        connection.settimeout(2)
        with connection.makefile("rwb") as stream:
            login = request(stream, "login", "session.open", {"mode": "developer", "token": TOKEN})
            observed = []
            for index in range(20):
                reply = request(stream, f"clock-{index}", "world.clock")
                observed.append(reply)
                if reply["result"]["tick"] == 2:
                    break
                time.sleep(.002)
            assert observed[-1]["result"]["tick"] == 2, observed
            observed.append(request(stream, "clock-repeat", "world.clock"))
            assert all(reply["result"]["paused"] is True for reply in observed), observed
            assert observed[-1]["result"]["tick"] == 2, observed
            return [login, *observed]


def expected(mode: int) -> dict:
    # These fixed scenario outcomes are independent expectations, not a host
    # presenter/state-machine implementation. All actual transitions run Bend.
    snapshots, draws, packets, releases, text, frames = 3, 3, 4, 1, "R|", 3
    exit_code, error = 0, "client closed"
    if mode == 1:
        snapshots, draws, packets, frames = 1, 0, 1, 0
        exit_code, error = 1, "frame query: injected snapshot failure"
    elif mode == 2:
        snapshots, draws, packets, frames = 1, 1, 1, 1
        exit_code, error = 1, "render: injected draw failure"
    elif mode == 5:
        snapshots, draws, packets, releases, frames = 0, 0, 2, 4, 0
        text, error = "R|K8710|L0|M010|K2710|R|K8700|X0|R|R|", "synthetic packet closed"
    elif mode == 6:
        snapshots, draws, packets, frames = 0, 0, 2, 0
        text, error = "M010|K8710|R|", "synthetic packet closed"
    elif mode == 7:
        snapshots, draws, packets, releases, frames = 0, 0, 2, 2, 0
        text, error = "R|R|", "synthetic packet closed"
    elif mode == 8:
        snapshots, draws, packets, frames = 0, 0, 1, 0
        exit_code, error = 22, "window open: injected open failure"
    elif mode == 9:
        snapshots, draws, packets, frames = 2, 1, 2, 1
        exit_code, error = 1, "frame query: injected snapshot failure"
    elif mode == 10:
        snapshots, draws, packets, frames = 2, 2, 2, 2
        exit_code, error = 1, "render: injected draw failure"
    elif mode == 12:
        snapshots, draws, packets, frames = 0, 0, 1, 0
    elif mode in (11, 13):
        snapshots, draws, packets, frames = 1, 1, 2, 1
    return dict(mode=mode, snapshots=snapshots, draws=draws, packets=packets,
                releases=releases, trace=text, frames=frames, exit_code=exit_code, error=error)


def check_observation(raw: dict, marker: dict, mode: int, external: list[dict]) -> dict:
    want = expected(mode)
    assert not raw["timed_out"] and raw["child_status"] == want["exit_code"], raw
    assert want["error"] in raw["stderr"], raw
    assert raw["before_frontmost_pid"] == raw["after_frontmost_pid"] > 0, raw
    assert raw["sampled_frontmost_pids"] == [raw["before_frontmost_pid"]], raw
    assert raw["space_change_notifications"] == 0 and raw["child_pid"] not in raw["activation_notification_pids"], raw
    fields, events = {}, []
    for line in raw["stdout"].splitlines():
        if line.startswith("{"):
            events.append(json.loads(line))
        elif "=" in line:
            key, text = line.split("=", 1)
            fields[key] = text
    before = json.loads(fields["before"])
    after = marker["after"]
    assert before["native_macos"] and after["native_macos"], marker
    assert before["frontmost_pid"] == after["frontmost_pid"] == raw["before_frontmost_pid"], raw
    assert before["space_change_notifications"] == after["space_change_notifications"] == 0, marker
    if mode not in (8, 11):
        window = json.loads(fields["window"])
        assert window["native_macos"] and window["window_number"] > 0, window
        assert window["activation_policy"] == 2, window
        assert not any(window[key] for key in ("visible", "key", "main", "app_active")), window
        assert window["frontmost_pid"] == before["frontmost_pid"] and window["space_change_notifications"] == 0, window
        assert fields["native_status"] == "false,false", fields
    assert marker["closed"] is True and marker["draws"] == want["draws"], marker
    actor = marker["actor"]
    for key in ("mode", "snapshots", "packets", "releases", "trace"):
        assert actor[key] == want[key], (mode, key, actor, want)
    assert actor["tick"] == 2 and actor["paused"] is True and actor["pulses"] >= 4, actor
    assert actor["focused"] is False and actor["captured"] is False, actor
    frames = [event for event in events if event.get("event") == "harness.frame"]
    assert len(frames) == want["frames"], (frames, want)
    assert [frame["ordinal"] for frame in frames] == list(range(1, want["frames"]+1)), frames
    assert all(frame["tick"] == 2 and frame["width"] == 32 and frame["height"] == 24 for frame in frames), frames
    if mode == 4:
        assert all(frame["capture_allowed"] is False for frame in frames), frames
    if mode in (5, 6, 7):
        assert fields["physical_event_count"] == "0", fields
        batch = [event for event in events if event.get("event") == "harness.packet"]
        assert len(batch) == 1 and batch[0]["actor"]["packets"] == 1, batch
        assert batch[0]["keep"] is (mode != 5) and batch[0]["captured"] is False, batch
        assert batch[0]["actor"]["trace"] == want["trace"][:-2], batch
    if mode == 3:
        assert raw["stdout"].count("input rejected: injected input rejection") == want["packets"], raw
    return {"mode": mode, "expected": want, "marker": marker, "live_replies": external,
            "native_events": events, "native_fields": fields,
            "observer": {key: value for key, value in raw.items() if key not in ("stdout", "stderr")},
            "stdout": raw["stdout"], "stderr": raw["stderr"]}


def execute(observer: Path, mode: int, repetition: int) -> dict:
    number = port()
    marker = ROOT / f"build/client-presenter-{mode}-{repetition}.json"
    marker.unlink(missing_ok=True)
    environment = {**os.environ, platform_build.MODE_ENV: "hidden",
                   "MC_DEV_TOKEN": TOKEN, "MC_LIVE_PORT": str(number)}
    outer = subprocess.Popen([str(observer), str(BINARY), str(mode), str(marker)], cwd=ROOT,
                             env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                             start_new_session=True)
    try:
        external = clocks(outer, number)
        stdout, stderr = outer.communicate(timeout=20)
        assert outer.returncode == 0, (stdout, stderr)
        result = check_observation(json.loads(stdout), json.loads(marker.read_text()), mode, external)
    finally:
        if outer.poll() is None:
            os.killpg(outer.pid, signal.SIGTERM)
            try:
                outer.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(outer.pid, signal.SIGKILL)
                outer.communicate()
    with socket.socket() as probe:
        probe.settimeout(.2)
        assert probe.connect_ex(("127.0.0.1", number)) != 0, "process exited but listener remains"
    result["listener_released_after_process_exit"] = True
    result["repetition"] = repetition
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--build-timeout", type=int, default=600)
    args = parser.parse_args()
    if args.build_only:
        value = ensure_platform(ENTRY, BINARY, bend=BEND)
        BUILD.write_text(json.dumps(value, indent=2, sort_keys=True)+"\n")
        print(json.dumps({"cache_hit": value["cache_hit"], "binary_sha256": value["binary_sha256"]}))
        return
    checked = ordinary_check()
    if args.prepare_only:
        print(json.dumps({"status": "prepared_typing_native_boundary", "ordinary_check": checked,
                          "entry_sha256": sha(ENTRY), "scenarios": 14, "native_build_started": False}, indent=2))
        return
    build = build_bounded(args.build_timeout)
    closure = {item["path"]: item["sha256"] for item in build["dependencies"] if "sha256" in item}
    own = {str(path.relative_to(ROOT)): sha(path) for path in
           (ENTRY, Path(__file__).resolve(), ROOT/"tools/platform_cache.py", ROOT/"tools/platform_build.py", ROOT/"tools/platform_test.py")}
    swift = ROOT / "build/client-presenter-observer.swift"
    observer = ROOT / "build/client-presenter-observer"
    swift.write_text(platform_test.OBSERVER)
    compiled = subprocess.run(["/usr/bin/swiftc", "-O", str(swift), "-o", str(observer)],
                              capture_output=True, text=True, timeout=60)
    assert compiled.returncode == 0, compiled.stderr
    observations = []
    for repetition in range(2):
        for mode in range(14):
            observations.append(execute(observer, mode, repetition))
        print(json.dumps({"event": "presenter.cases_passed", "repetition": repetition, "cases": 14}), flush=True)
    assert own == {name: sha(ROOT/name) for name in own}, "test/build policy changed during execution"
    for path, digest in closure.items():
        assert sha(Path(path)) == digest, f"transitive dependency changed: {path}"
    evidence = {"status": "passed_hidden_native_presenter_integration", "confidence": "high for recorded bounded scenarios",
                "time_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "command": "python3 tools/test_client_presenter.py --build-timeout 600",
                "ordinary_check": checked, "build": build, "test_sources_sha256": own,
                "observer_source_sha256": sha(swift), "observer_binary_sha256": sha(observer),
                "native_runs": len(observations), "scenario_count": 14, "observations": observations,
                "scope": ["real hidden NativeWindow, Window.frame/grab/status/close", "actual shared Server actor, timer, local_call and external TCP clock query", "owned core state remains paused at tick2 while timer pulses, snapshots and inputs run", "whole synthetic event batch arrives in one actor operation", "final Release, asset-close File write and close before actor stop", "snapshot/draw/input and opened(Fail) cleanup injections"],
                "limitations": ["No visible presentation or physical keyboard/mouse input acceptance", "No actual focused-to-unfocused OS transition; only synthetic prior-capture flag against real unfocused native state", "Open failure injected into existing opened callback, not an observed OS allocation failure", "File marker proves the asset callback and ordering; it does not count all native resources", "Server.stop closes the actor; its accept socket is released by process exit", "Native/unsafe dependency refusals are not a whole-module kernel proof"]}
    REPORT.write_text(json.dumps(evidence, indent=2, sort_keys=True)+"\n")
    print(json.dumps({"status": evidence["status"], "native_runs": len(observations),
                      "binary_sha256": build["binary_sha256"], "evidence": str(REPORT)}))


if __name__ == "__main__":
    main()
