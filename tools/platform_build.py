#!/usr/bin/env python3
"""Build pinned Bend macOS windows with opt-in hidden automated launches.

The generated Base window implementation is reused, not copied. Only its
application policy and final presentation calls are transformed. Fail closed
on compiler or complete window implementation changes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

PINNED_VERSION = "bend 2.0.35"
PINNED_COMPILER_SHA256 = "99b3de8f6c5643d245bed839df2c28d1bb12efd41bb221154d25c15695b72e8e"
PINNED_WINDOW_SHA256 = "9cd6435eb582b65deca88afe1ddc8a4d9700f21347acbcf086fc19611cc1c4ba"
WINDOW_START = "// Window\n// ======\n\n// All window effects share this source; each entry is present only when\n// its effect is reachable.\n"
WINDOW_END = "static void __attribute__((constructor)) window_close_use(void) {\n  io_eff(CID_WINDOW_CLOSE, window_close_run, 0);\n}\n\n#endif\n"
PATCH_MARKER = "// Minecraft project launch policy; guarded by tools/platform_build.py."
MODE_ENV = "BEND_MINECRAFT_LAUNCH_MODE"

MODE_INSERT = """  // Minecraft project launch policy; guarded by tools/platform_build.py.
  const char* launch_mode = getenv("BEND_MINECRAFT_LAUNCH_MODE");
  bool hidden = launch_mode != NULL && strcmp(launch_mode, "hidden") == 0;
  if (launch_mode != NULL && !hidden && strcmp(launch_mode, "human") != 0) {
    *why = "Window.open: BEND_MINECRAFT_LAUNCH_MODE must be human or hidden";
    return EINVAL;
  }
"""


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def transform(generated: str) -> str:
    """Patch only the exact pinned emitted Base window effect source."""
    if PATCH_MARKER in generated:
        raise ValueError("C source was already transformed")
    if generated.count(WINDOW_START) != 1 or generated.count(WINDOW_END) != 1:
        raise ValueError("expected exactly one complete Base window implementation")
    start = generated.index(WINDOW_START)
    end = generated.index(WINDOW_END, start) + len(WINDOW_END)
    window = generated[start:end]
    if digest(window.encode()) != PINNED_WINDOW_SHA256:
        raise ValueError("emitted Base window implementation differs from pinned digest")
    changes = [
        ("  if (NSScreen.screens.count == 0) {\n", MODE_INSERT + "  if (NSScreen.screens.count == 0) {\n"),
        ("    NSApp.activationPolicy = NSApplicationActivationPolicyRegular;\n",
         "    NSApp.activationPolicy = hidden ? NSApplicationActivationPolicyProhibited\n"
         "      : NSApplicationActivationPolicyRegular;\n"),
        ("    [win makeKeyAndOrderFront:nil];\n    [NSApp activateIgnoringOtherApps:YES];\n",
         "    if (!hidden) {\n      [win makeKeyAndOrderFront:nil];\n"
         "      [NSApp activateIgnoringOtherApps:YES];\n    }\n"),
    ]
    for old, new in changes:
        if window.count(old) != 1:
            raise ValueError("pinned launch statement missing or ambiguous")
        window = window.replace(old, new, 1)
    return generated[:start] + window + generated[end:]


def compiler_path(value: str) -> Path:
    found = shutil.which(value)
    path = Path(found or value).expanduser().resolve()
    if not path.is_file():
        raise ValueError(f"compiler not found: {path}")
    if digest(path.read_bytes()) != PINNED_COMPILER_SHA256:
        raise ValueError("Bend executable differs from the verified pinned compiler digest")
    version = subprocess.run([str(path), "version"], check=True, text=True,
                             capture_output=True).stdout.strip()
    if version != PINNED_VERSION:
        raise ValueError(f"expected {PINNED_VERSION}, observed {version}")
    return path


def clang_path(value: str, gpu: bool) -> str:
    found = shutil.which(value)
    if found is None:
        raise ValueError(f"C compiler not found: {value}")
    info = subprocess.run([found, "--version"], check=True, text=True,
                          capture_output=True).stdout
    match = re.search(r"^(Apple )?(?:\w+ )?clang version (\d+)", info, re.M)
    minimum = 17 if gpu and match and match[1] else 19 if gpu else 14
    if match is None or int(match[2]) < minimum:
        raise ValueError(f"Bend build needs clang >= {minimum}")
    return found


def build(entry: Path, output: Path, bend: Path, cc: str) -> dict:
    output = output.resolve()
    if output == entry.resolve() or output.is_dir():
        raise ValueError("output must be a distinct file")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="minecraft-platform-") as temporary:
        raw = Path(temporary) / "generated.c"
        subprocess.run([str(bend), str(entry.resolve()), "-o", str(raw)], check=True)
        if not raw.is_file():
            raise ValueError("Bend did not emit C; inspect its checker output")
        original = raw.read_text()
        patched = transform(original)
        raw.write_text(patched)
        gpu = not re.search(r"^#define BANGS\s+0$", patched, re.M)
        report = {
            "compiler_version": PINNED_VERSION,
            "compiler_sha256": PINNED_COMPILER_SHA256,
            "base_window_sha256": PINNED_WINDOW_SHA256,
            "generated_sha256": digest(original.encode()),
            "transformed_sha256": digest(patched.encode()),
            "entry": str(entry.resolve()), "output": str(output),
            "gpu_bangs": gpu,
        }
        if output.suffix == ".c":
            output.write_text(patched)
            return report
        if output.suffix in {".js", ".mjs", ".bendtt"}:
            raise ValueError("this adapter builds native executables or emitted .c only")
        clang = clang_path(cc, gpu)
        command = [clang, "-x", "objective-c", "-fobjc-arc", "-fmodules",
                   "-std=c11", "-O3", str(raw), "-lpthread", "-lm", "-o", str(output)]
        if gpu:
            command.insert(1, "-DBEND_METAL=1")
        subprocess.run(command, check=True)
        if gpu:
            environment = os.environ.copy()
            environment[MODE_ENV] = "hidden"
            subprocess.run([str(output), "--gpu-build"], env=environment, check=True)
        report["binary_sha256"] = digest(output.read_bytes())
        report["clang"] = clang
        return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("entry", type=Path)
    parser.add_argument("-o", "--output", required=True, type=Path)
    parser.add_argument("--bend", default=str(Path.home() / ".bend/bin/bend"))
    parser.add_argument("--cc", default=os.environ.get("CC", "clang"))
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        if sys.platform != "darwin":
            raise ValueError("this launch adapter is macOS-only")
        report = build(args.entry, args.output, compiler_path(args.bend), args.cc)
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, sort_keys=True))
        return 0
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"platform build failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
