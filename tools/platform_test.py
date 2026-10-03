#!/usr/bin/env python3
"""Verify the project launch transform and actual hidden native launch.

An independent AppKit observer polls frontmost PID every 20 ms and records
activation / Space-change notifications while the native Bend child runs.
No UI is ordered, clicked, focused, captured or moved by this test.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys

import platform_build as adapter

ROOT = Path(__file__).resolve().parents[1]
OBSERVER = r'''
import AppKit
import Foundation

let workspace = NSWorkspace.shared
func frontmost() -> Int32 { workspace.frontmostApplication?.processIdentifier ?? -1 }
let before = frontmost()
var pids = Set<Int32>([before])
var activations = [Int32]()
var spaces = 0
let center = workspace.notificationCenter
let activated = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
    object: nil, queue: .main) { note in
    if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
        activations.append(app.processIdentifier)
    }
}
let changed = center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
    object: nil, queue: .main) { _ in spaces += 1 }
let process = Process()
process.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
process.arguments = Array(CommandLine.arguments.dropFirst(2))
let output = Pipe()
let errors = Pipe()
process.standardOutput = output
process.standardError = errors
try process.run()
let start = Date()
var samples = 0
while process.isRunning && Date().timeIntervalSince(start) < 15 {
    pids.insert(frontmost())
    samples += 1
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
}
let timedOut = process.isRunning
if timedOut { process.terminate() }
process.waitUntilExit()
for _ in 0..<10 {
    pids.insert(frontmost())
    samples += 1
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
}
let after = frontmost()
let report: [String: Any] = [
    "before_frontmost_pid": before, "after_frontmost_pid": after,
    "sampled_frontmost_pids": pids.sorted(), "samples": samples,
    "activation_notification_pids": activations, "space_change_notifications": spaces,
    "child_pid": process.processIdentifier, "child_status": process.terminationStatus,
    "timed_out": timedOut, "elapsed_seconds": Date().timeIntervalSince(start),
    "stdout": String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
    "stderr": String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
]
center.removeObserver(activated)
center.removeObserver(changed)
let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
'''


def check(condition: bool, description: str) -> None:
    if not condition:
        raise AssertionError(description)


def verify_transform(raw: str) -> list[str]:
    patched = adapter.transform(raw)
    tests = ["exact pinned full window effect accepted"]
    check(patched.count(adapter.PATCH_MARKER) == 1, "one launch policy required")
    check("if (!hidden) {\n      [win makeKeyAndOrderFront:nil];\n"
          "      [NSApp activateIgnoringOtherApps:YES];\n    }" in patched,
          "normal foreground calls must be preserved together")
    tests.append("original human foreground calls preserved in nonhidden branch")
    # Independent perturbations probe the fail-closed boundary, rather than
    # comparing the implementation to a second copy of its replacement text.
    bad_inputs = {
        "runtime behavior changed": raw.replace("win.acceptsMouseMovedEvents = YES;",
                                                   "win.acceptsMouseMovedEvents = NO;"),
        "duplicate window implementation": raw + raw[raw.index(adapter.WINDOW_START):
                                                       raw.index(adapter.WINDOW_END) + len(adapter.WINDOW_END)],
        "missing final source boundary": raw.replace(adapter.WINDOW_END, ""),
        "reapplication": patched,
    }
    for name, bad in bad_inputs.items():
        try:
            adapter.transform(bad)
        except ValueError:
            tests.append(f"rejected {name}")
        else:
            raise AssertionError(f"unsafe input accepted: {name}")
    return tests


def run_probe(observer: Path, binary: Path, mode: str, gpu: str) -> dict:
    environment = os.environ.copy()
    environment[adapter.MODE_ENV] = mode
    result = subprocess.run([str(observer), str(binary), "--gpu", gpu],
                            env=environment, text=True, capture_output=True,
                            timeout=25, check=True)
    report = json.loads(result.stdout)
    report["launch_mode"] = mode
    report["gpu_option"] = gpu
    check(not report["timed_out"], "native child timed out")
    before = report["before_frontmost_pid"]
    check(before > 0 and before == report["after_frontmost_pid"], "frontmost app changed")
    check(report["sampled_frontmost_pids"] == [before], "frontmost app changed during launch")
    check(report["space_change_notifications"] == 0, "a Space change was observed")
    check(report["child_pid"] not in report["activation_notification_pids"], "child activated")
    records = {}
    for line in report["stdout"].splitlines():
        if line.startswith("platform_") and "=" in line:
            key, value = line.split("=", 1)
            records[key] = json.loads(value)
    report["native_observations"] = records
    if mode == "hidden":
        check(report["child_status"] == 0, "hidden native child failed")
        check(records.get("platform_frame_returned") is True, "Base Window.frame did not return")
        window = records["platform_window"]
        check(window["native_macos"] is True, "native window was not observed")
        check(window["window_number"] > 0, "no native NSWindow number")
        check(all(window[key] is False for key in ["visible", "key", "main", "app_active"]),
              "hidden native window was visible, key, main, or active")
        check(window["activation_policy"] == 2, "application policy was not Prohibited")
        check(all(record["frontmost_pid"] == before for record in records.values()
                  if isinstance(record, dict)), "native and observer focus observations differ")
        check(all(record["space_change_notifications"] == 0 for record in records.values()
                  if isinstance(record, dict)), "native Space notification observed")
    else:
        check(report["child_status"] == 22, "invalid launch mode must fail with EINVAL")
        check("must be human or hidden" in report["stderr"], "missing invalid-mode diagnostic")
        check(set(records) == {"platform_before"}, "invalid mode progressed past Window.open")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bend", default=str(Path.home() / ".bend/bin/bend"))
    parser.add_argument("--cc", default=os.environ.get("CC", "clang"))
    parser.add_argument("--evidence", type=Path, default=ROOT / "evidence/platform-launch.json")
    args = parser.parse_args()
    try:
        check(sys.platform == "darwin", "native test requires macOS desktop session")
        bend = adapter.compiler_path(args.bend)
        work = ROOT / "build"
        work.mkdir(exist_ok=True)
        entry = ROOT / "tests/platform.bend"
        raw = work / "platform-test-original.c"
        subprocess.run([str(bend), str(entry), "-o", str(raw)], check=True)
        checks = verify_transform(raw.read_text())
        compiler_check = subprocess.run([str(bend), str(entry), "--check-only"],
                                       text=True, capture_output=True)
        check(compiler_check.returncode == 1 and "rely on unsafe or foreign code" in
              compiler_check.stdout + compiler_check.stderr,
              "expected honest foreign effect proof-boundary report")
        swift = work / "platform-observer.swift"
        observer = work / "platform-observer"
        swift.write_text(OBSERVER)
        subprocess.run(["/usr/bin/swiftc", "-O", str(swift), "-o", str(observer)], check=True)
        binary = work / "platform-probe"
        build = adapter.build(entry, binary, bend, args.cc)
        runs = [run_probe(observer, binary, "hidden", "off"),
                run_probe(observer, binary, "invalid", "off")]
        # A generated fixture exercises the adapter's GPU build path with a
        # bounded parallel computation; the tracked game stays Bend-owned.
        gpu_entry = work / "platform-gpu.bend"
        gpu_entry.write_text(entry.read_text().replace("def finish(",
            "def probe_color(+fuel: Nat) -> U32:\n"
            "  match fuel:\n    case 0n:\n      1\n    case 1n+rest:\n"
            "      a b = probe_color(rest) probe_color(rest)\n      (a + b : U32)\n\n"
            "def finish(", 1).replace("Pix{2241348}", "Pix{probe_color!(7n)}"))
        gpu_binary = work / "platform-gpu-probe"
        gpu_build = adapter.build(gpu_entry, gpu_binary, bend, args.cc)
        check(gpu_build["gpu_bangs"] is True, "GPU fixture has no bang")
        check(gpu_binary.with_suffix(".gpu").is_file(), "GPU sidecar was not built")
        runs += [run_probe(observer, gpu_binary, "hidden", "off"),
                 run_probe(observer, gpu_binary, "hidden", "on")]
        report = {
            "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
            "status": "passed",
            "commands": [
                "python3 tools/platform_test.py",
                "python3 tools/platform_build.py tests/platform.bend -o build/platform-probe",
                "BEND_MINECRAFT_LAUNCH_MODE=hidden build/platform-probe --gpu off",
            ],
            "transform_checks": checks,
            "compiler_check": {"status": compiler_check.returncode,
                               "stdout": compiler_check.stdout, "stderr": compiler_check.stderr},
            "cpu_build": build, "gpu_build": gpu_build, "runs": runs,
            "boundary": [
                "Foreign observations are not Bend proofs.",
                "A returned hidden Window.frame does not establish drawable presentation or pixel fidelity.",
                "Foreground human branch was verified statically, not launched by automation.",
                "Polling and notifications are observations during these runs, not proof against all transient OS changes.",
                "No Minecraft gameplay, UI, audio, renderer, or Java parity claim is established.",
            ],
        }
        args.evidence.parent.mkdir(parents=True, exist_ok=True)
        args.evidence.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({"status": "passed", "runs": len(runs),
                          "transform_checks": len(checks), "evidence": str(args.evidence)}))
        return 0
    except (AssertionError, ValueError, OSError, subprocess.SubprocessError, KeyError) as error:
        print(f"platform tests failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
