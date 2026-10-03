#!/usr/bin/env python3
"""Measure a narrow tick-manager fixture in the actual pinned Java classes.

This launches a headless Java probe, not the client, server or an account login.
It is independent reference evidence, not a test of the Bend implementation.
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import subprocess
import zipfile

from reference_inventory import ROOT, JAVA, write_json

SOURCE = '''import net.minecraft.world.TickRateManager;

class ReferenceTickProbe {
    public static void main(String[] args) {
        TickRateManager ticks = new TickRateManager();
        float rate = ticks.tickrate();
        long nanos = ticks.nanosecondsPerTick();
        float millis = ticks.millisecondsPerTick();
        ticks.setTickRate(7.0f);
        long sevenNanos = ticks.nanosecondsPerTick();
        ticks.setTickRate(0.25f);
        float clampedRate = ticks.tickrate();
        long clampedNanos = ticks.nanosecondsPerTick();
        ticks.setFrozen(true);
        ticks.tick();
        boolean frozenNormal = ticks.runsNormally();
        ticks.setFrozenTicksToRun(2);
        ticks.tick();
        boolean step1 = ticks.runsNormally();
        int remaining1 = ticks.frozenTicksToRun();
        ticks.tick();
        boolean step2 = ticks.runsNormally();
        int remaining2 = ticks.frozenTicksToRun();
        ticks.tick();
        boolean exhausted = ticks.runsNormally();
        ticks.setFrozen(false);
        ticks.tick();
        boolean resumed = ticks.runsNormally();
        System.out.println("{\\"default_tickrate\\":" + rate
            + ",\\"default_nanoseconds_per_tick\\":" + nanos
            + ",\\"default_milliseconds_per_tick\\":" + millis
            + ",\\"seven_nanoseconds_per_tick\\":" + sevenNanos
            + ",\\"clamped_tickrate\\":" + clampedRate
            + ",\\"clamped_nanoseconds_per_tick\\":" + clampedNanos
            + ",\\"frozen_runs_normally\\":" + frozenNormal
            + ",\\"step1_runs_normally\\":" + step1
            + ",\\"step1_remaining\\":" + remaining1
            + ",\\"step2_runs_normally\\":" + step2
            + ",\\"step2_remaining\\":" + remaining2
            + ",\\"exhausted_runs_normally\\":" + exhausted
            + ",\\"resumed_runs_normally\\":" + resumed + "}");
    }
}
'''

EXPECTED = {"default_tickrate": 20.0, "default_nanoseconds_per_tick": 50_000_000, "default_milliseconds_per_tick": 50.0,
            "seven_nanoseconds_per_tick": 142_857_142, "clamped_tickrate": 1.0, "clamped_nanoseconds_per_tick": 1_000_000_000,
            "frozen_runs_normally": False, "step1_runs_normally": True, "step1_remaining": 1,
            "step2_runs_normally": True, "step2_remaining": 0, "exhausted_runs_normally": False, "resumed_runs_normally": True}


def main() -> None:
    cache = ROOT / "reference/cache"
    server = cache / "versions/26.3/server-26.3.jar"
    if not server.exists():
        raise RuntimeError("Run tools/reference_inventory.py first to verify and unpack the pinned server")
    release = json.loads((ROOT / "reference/release.json").read_text())
    if hashlib.sha256(server.read_bytes()).hexdigest() != release["server_bundle"]["nested_server_sha256"]:
        raise ValueError("Unpacked reference server SHA-256 mismatch")
    bundle_path = cache / "26.3-server.jar"
    if hashlib.sha256(bundle_path.read_bytes()).hexdigest() != release["server_bundle"]["sha256"]:
        raise ValueError("Pinned reference server bundle SHA-256 mismatch")
    jars = [server]
    with zipfile.ZipFile(bundle_path) as bundle:
        for line in bundle.read("META-INF/libraries.list").decode().splitlines():
            expected_sha, coordinate, relative = line.split("\t")
            library_path = cache / "libraries" / relative
            if hashlib.sha256(library_path.read_bytes()).hexdigest() != expected_sha:
                raise ValueError(f"Unpacked reference library SHA-256 mismatch: {coordinate}")
            jars.append(library_path)
    folder = ROOT / "reference/extracted/probes"
    folder.mkdir(parents=True, exist_ok=True)
    source = folder / "ReferenceTickProbe.java"
    source.write_text(SOURCE)
    command = [str(JAVA), "--class-path", ":".join(map(str, jars)), str(source)]
    result = subprocess.run(command, capture_output=True, text=True, check=True)
    observed = json.loads(result.stdout)
    if observed != EXPECTED:
        raise ValueError(f"Java reference tick observations differ from bytecode-derived expectations: {observed}")
    write_json(ROOT / "evidence/reference_tick_probe.json", {"pin": "26.3", "kind": "java_reference_behavior_observation",
                                                            "class": "net.minecraft.world.TickRateManager", "probe_source_sha256": hashlib.sha256(SOURCE.encode()).hexdigest(),
                                                            "reference_server_sha256": release["server_bundle"]["nested_server_sha256"],
                                                            "reproduce": "python3 tools/reference_tick_probe.py", "observed": observed, "expected": EXPECTED,
                                                            "comparison_passed": True, "process_exit_code": result.returncode,
                                                            "limits": "TickRateManager defaults/rate clamp/frozen stepping only. No entity exceptions, server scheduling, integration or Bend comparison.",
                                                            "bend_behavioral_parity_established": False})
    print(json.dumps(observed, sort_keys=True))


if __name__ == "__main__":
    main()
