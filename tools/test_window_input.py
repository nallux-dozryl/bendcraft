#!/usr/bin/env python3
"""Verify the affine macOS focus/capture query with hidden real native windows."""
from __future__ import annotations

import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

import platform_build

ROOT = Path(__file__).resolve().parents[1]
ENTRY = ROOT / "tests/window_input.bend"
OUTPUT = ROOT / "build/window-input-tests"
BEND = Path.home() / ".bend/bin/bend"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    paths = ["src/window_input.bend", "src/native/window_input.c",
             "src/native/window_input.js", "src/platform.bend",
             "src/native/platform.c", "src/native/platform.js",
             "tests/window_input.bend", "tools/platform_build.py",
             "tools/test_window_input.py"]
    sources = {p: sha(ROOT / p) for p in paths}
    checked = subprocess.run([str(BEND), str(ENTRY), "--check-only"],
                             cwd=ROOT, text=True, capture_output=True, timeout=30)
    expected = ["../src/window_input.Native.status", "../src/window_input.capture",
                "../src/platform.Platform.observe", "../src/platform.Platform.inspect", "main"]
    diagnostic = checked.stdout + checked.stderr
    refusals = [line[2:] for line in diagnostic.splitlines() if line.startswith("- ")]
    assert checked.returncode == 1 and refusals == expected, diagnostic
    assert "Error: 5 defs rely on unsafe or foreign code:" in diagnostic
    started = time.monotonic()
    build = platform_build.build(ENTRY, OUTPUT,
                                platform_build.compiler_path(str(BEND)), "clang")
    elapsed = time.monotonic() - started
    environment = os.environ.copy()
    environment[platform_build.MODE_ENV] = "hidden"
    observations = []
    for _ in range(3):
        ran = subprocess.run([str(OUTPUT)], cwd=ROOT, env=environment, text=True,
                             capture_output=True, timeout=30, check=True)
        values = dict(line.split("=", 1) for line in ran.stdout.splitlines())
        assert values["initial"] == values["after_capture_attempt"] == values["after_frame"] == "False,False"
        assert values["capture_result"] == "False"
        assert values["frame_events"] == "0"
        before, window, after = (json.loads(values[key]) for key in ["before", "window", "after"])
        assert before["native_macos"] and window["native_macos"] and after["native_macos"]
        assert before["frontmost_pid"] == window["frontmost_pid"] == after["frontmost_pid"]
        assert before["space_change_notifications"] == window["space_change_notifications"] == after["space_change_notifications"] == 0
        assert not window["visible"] and not window["key"] and not window["app_active"]
        observations.append({"before": before, "window": window, "after": after,
                             "focus_capture": [values[key] for key in ["initial", "after_capture_attempt", "after_frame"]],
                             "capture_result": values["capture_result"], "frame_events": 0})
    assert sources == {p: sha(ROOT / p) for p in paths}, "source changed during verification"
    evidence = {"status": "passed_hidden_native_boundary", "confidence": "high for recorded hidden cases",
                "time_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "sources_sha256": sources, "build": build, "build_seconds": elapsed,
                "ordinary_check": {"exit_code": checked.returncode,
                                   "admission": "typing/affinity reaches the exact five declared native-dependent refusals",
                                   "whole_module_proof": False, "stdout": checked.stdout,
                                   "stderr": checked.stderr},
                "observations": observations,
                "scope": "Same affine Base Window returned; real hidden AppKit focus/capture reads, failed capture attempt, frame and close. No focus/Spaces activation observed.",
                "unverified": ["visible focused capture", "real keyboard/mouse events", "focus-loss transition while held", "presenter actor integration", "non-macOS native windows"],
                "command": "python3 tools/test_window_input.py"}
    target = ROOT / "evidence/window-input-native.json"
    target.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status": evidence["status"], "native_runs": 3,
                      "build_seconds": elapsed, "binary_sha256": build["binary_sha256"],
                      "evidence": str(target)}))


if __name__ == "__main__":
    main()
