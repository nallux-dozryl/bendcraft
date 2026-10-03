#!/usr/bin/env python3
"""Isolated, sequential phase profile of concrete/generic Bend client builds."""
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
import time

import build_native
import platform_build

ROOT = Path(__file__).resolve().parents[1]
BEND = Path.home() / ".bend/bin/bend"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def processes():
    text = subprocess.run(["ps", "-Ao", "pid,etime,%cpu,args"], capture_output=True, text=True, check=True).stdout
    found = []
    for line in text.splitlines():
        m = re.match(r"\s*(\d+)\s+(\S+)\s+([\d.]+)\s+(.+)", line)
        if m and int(m[1]) != os.getpid() and ("/.bend/bin/bend " in m[4] or re.search(r"(?:^|/)clang(?:\s|$)", m[4])):
            found.append({"pid": int(m[1]), "elapsed": m[2], "cpu_percent": float(m[3]), "command": m[4][:600]})
    return found


def timed(command, folder, label, accepted=(0,), env=None):
    started = time.perf_counter()
    stdout, stderr = folder / (label + ".stdout"), folder / (label + ".stderr")
    observations = [{"seconds": 0, "processes": processes()}]
    with stdout.open("w") as out, stderr.open("w") as err:
        child = subprocess.Popen(["/usr/bin/time", "-lp", *map(str, command)], stdout=out, stderr=err, env=env)
        while child.poll() is None:
            time.sleep(.5)
            elapsed = time.perf_counter() - started
            if len(observations) == 1 or elapsed - observations[-1]["seconds"] >= 10:
                observations.append({"seconds": round(elapsed, 3), "processes": processes()})
        code = child.returncode
    elapsed = time.perf_counter() - started
    text = stderr.read_text()
    cpu = {}
    for kind in ("real", "user", "sys"):
        matches = re.findall(r"^" + kind + r" ([\d.]+)$", text, re.M)
        if matches:
            cpu[kind + "_seconds"] = float(matches[-1])
    resident = re.findall(r"^\s*(\d+)\s+maximum resident set size$", text, re.M)
    if resident:
        cpu["maximum_resident_bytes"] = int(resident[-1])
    result = {"command": list(map(str, command)), "return_code": code, "wall_seconds": elapsed,
              "resources": cpu, "process_observations": observations,
              "stdout_sha256": sha(stdout), "stderr_sha256": sha(stderr),
              "stdout_tail": stdout.read_text()[-1000:], "stderr_tail": text[-1600:]}
    print(json.dumps({"phase": label, "wall_seconds": round(elapsed, 3), "return_code": code,
                      "user_seconds": cpu.get("user_seconds")}), flush=True)
    if code not in accepted:
        raise RuntimeError(f"{label} failed: {result['stdout_tail']}\n{result['stderr_tail']}")
    return result


def metrics(path):
    source = path.read_text()
    functions = []
    pattern = re.compile(r"^([A-Za-z_][A-Za-z0-9_ \t*]*?)\s+([A-Za-z_]\w*)\([^;{}]*\)\s*\{", re.M)
    for m in pattern.finditer(source):
        if m[1].startswith("typedef"):
            continue
        i, depth, quoted = m.end(), 1, None
        while i < len(source) and depth:
            c = source[i]
            if quoted:
                if c == "\\": i += 2; continue
                if c == quoted: quoted = None
            elif source.startswith("//", i):
                n = source.find("\n", i); i = len(source) if n < 0 else n; continue
            elif source.startswith("/*", i):
                n = source.find("*/", i + 2); i = len(source) if n < 0 else n + 2; continue
            elif c in "\"'": quoted = c
            elif c == "{": depth += 1
            elif c == "}": depth -= 1
            i += 1
        body = source[m.start():i]
        functions.append({"name": m[2], "bytes": len(body.encode()), "lines": body.count("\n") + 1,
                          "cases": len(re.findall(r"\bcase\b", body))})
    fid = re.findall(r"^#define FID_([A-Z0-9_]+)\s+\d+", source, re.M)
    grouped = {}
    for name in fid:
        stem = re.sub(r"_(?:[CK]\d+|\d+)$", "", name)
        grouped[stem] = grouped.get(stem, 0) + 1
    return {"sha256": sha(path), "bytes": path.stat().st_size, "lines": source.count("\n"),
            "function_definition_count": len(functions), "fid_count": len(fid),
            "cid_count": len(re.findall(r"^#define CID_", source, re.M)),
            "native_spin_helper_count": sum(f["name"].startswith("spin_") for f in functions),
            "host_loop_instantiations": re.findall(r"^#define FID_SRC_CLIENT_HOST_LOOP_(\d+)\s+\d+", source, re.M),
            "wl_case_segments": len(re.findall(r"\bWL_CASE\(", source)),
            "case_count": len(re.findall(r"\bcase\b", source)),
            "largest_functions": sorted(functions, key=lambda x:x["bytes"], reverse=True)[:25],
            "largest_fid_families": sorted(grouped.items(), key=lambda x:x[1], reverse=True)[:35],
            "gpu_bangs": not bool(re.search(r"^#define BANGS\s+0$", source, re.M))}


def snapshot(folder, revision):
    env = dict(os.environ)
    book = build_native.Snapshot()
    base = BEND.resolve().parent.parent / "bend2/base.bend"
    build_native.source_graph(ROOT / "client.bend", base.resolve(), env, book)
    files = book.manifest()
    staged = []
    folder.mkdir(parents=True, exist_ok=True)
    for item in files:
        source = Path(item["path"])
        try: relative = source.relative_to(ROOT)
        except ValueError: continue
        target = folder / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        assert sha(target) == item["sha256"]
        staged.append({"relative_path": str(relative), "sha256": item["sha256"], "source_path": str(source)})
    concrete = subprocess.run(["git", "show", f"{revision}:minecraft/client.bend"], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    current = (folder / "client.bend").read_text()
    (folder / "concrete.bend").write_text(concrete)
    (folder / "generic.bend").write_text(current)
    # Isolate the callback-record template axis while retaining State templates.
    candidate = current.replace("./src/client_host.bend", "./src/client_host_runtime.bend")
    candidate = candidate.replace("~H.Driver{", "H.Driver{")
    host = (folder / "src/client_host.bend").read_text()
    host = host.replace("~driver:Driver<State>", "+driver:Driver<State>").replace("~driver", "driver")
    (folder / "runtime_driver.bend").write_text(candidate)
    (folder / "src/client_host_runtime.bend").write_text(host)
    assert "~driver" not in host and "~State" in host
    return {"files": files, "staged_files": staged, "historical_entry_revision": revision,
            "historical_entry_sha256": sha(folder / "concrete.bend"),
            "current_entry_sha256": sha(folder / "generic.bend"),
            "candidate_entry_sha256": sha(folder / "runtime_driver.bend"),
            "candidate_host_sha256": sha(folder / "src/client_host_runtime.bend"),
            "candidate_change": "keep ~State; replace ~driver with +driver; remove ~driver/~H.Driver call-site markers"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--revision", default="8031ee4")
    parser.add_argument("--variants", nargs="+", choices=("concrete", "generic", "persistent", "runtime_driver"), default=["concrete", "generic", "persistent"])
    parser.add_argument("--output", type=Path, default=ROOT / "build/client-build-profile")
    parser.add_argument("--report", type=Path, default=ROOT / "evidence/client-build-profile.json")
    parser.add_argument("--summarize-only", action="store_true", help="refresh metrics/analysis from retained C and logs without compiling")
    parser.add_argument("--resume", action="store_true", help="add new variants to an existing verified frozen snapshot")
    parser.add_argument("--clang-trace", action="store_true", help="use locally verified -ftime-trace=PATH profiling flag")
    parser.add_argument("--quiet-wait", type=float, default=60)
    args = parser.parse_args()
    if args.summarize_only:
        report = json.loads(args.report.read_text())
        for variant, result in report["variants"].items():
            result["raw_c"] = metrics(args.output / variant / "raw.c")
            result["build_command_real_seconds"] = sum(result[phase]["resources"]["real_seconds"] for phase in ("emission_including_check", "clang")) + (result["gpu_build"]["resources"]["real_seconds"] if result.get("gpu_build") else 0)
        report["analysis_tool_sha256"] = sha(Path(__file__))
        generic, concrete, persistent = (report["variants"].get(n) for n in ("generic", "concrete", "persistent"))
        if generic and concrete:
            report["comparison"] = {"generic_vs_concrete": {
                "c_bytes_percent_change": 100*(generic["raw_c"]["bytes"]/concrete["raw_c"]["bytes"]-1),
                "build_wall_percent_change": 100*(generic["build_total_without_extra_check_seconds"]/concrete["build_total_without_extra_check_seconds"]-1),
                "build_command_real_percent_change": 100*(generic["build_command_real_seconds"]/concrete["build_command_real_seconds"]-1),
                "fid_delta": generic["raw_c"]["fid_count"]-concrete["raw_c"]["fid_count"],
                "explicit_function_delta": generic["raw_c"]["function_definition_count"]-concrete["raw_c"]["function_definition_count"]}}
        if persistent and generic:
            report.setdefault("comparison", {})["persistent_vs_generic"] = {
                "c_bytes_percent_change": 100*(persistent["raw_c"]["bytes"]/generic["raw_c"]["bytes"]-1),
                "fid_delta": persistent["raw_c"]["fid_count"]-generic["raw_c"]["fid_count"],
                "explicit_function_delta": persistent["raw_c"]["function_definition_count"]-generic["raw_c"]["function_definition_count"]}
            integration_path = ROOT / "evidence/persistent-client-integration.json"
            if integration_path.exists():
                integration = json.loads(integration_path.read_text())
                report["prior_persistent_integration"] = {"evidence_sha256": sha(integration_path),
                    "build_seconds": integration["build_seconds"],
                    "raw_c_sha256_matches": persistent["raw_c"]["sha256"] == integration["native_build"]["generated_sha256"],
                    "transformed_c_sha256_matches": persistent["transformed_c_sha256"] == integration["native_build"]["transformed_sha256"]}
        for variant, result in report["variants"].items():
            external = {}
            for phase in ("check", "emission_including_check", "clang"):
                for observation in result[phase]["process_observations"]:
                    for process in observation["processes"]:
                        if str(args.output) not in process["command"]:
                            external[process["pid"]] = process
            result["observed_other_compilers"] = list(external.values())
        args.report.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({"status": report["status"], "comparison": report.get("comparison"), "prior_persistent_integration": report.get("prior_persistent_integration")}, indent=2))
        return
    if args.output.exists() and not args.resume:
        raise RuntimeError("choose a new isolated profile output or explicitly --resume; measurements are not overwritten")
    compiler = platform_build.compiler_path(str(BEND))
    if args.resume:
        report = json.loads(args.report.read_text())
        staged = report["snapshot"]
        for item in staged["files"]:
            if not Path(item["path"]).is_file() or sha(item["path"]) != item["sha256"]:
                raise RuntimeError("cannot resume a moving original dependency graph")
        for item in staged["staged_files"]:
            if sha(args.output / "input" / item["relative_path"]) != item["sha256"]:
                raise RuntimeError("cannot resume modified staged dependencies")
        # Retain an earlier rejected candidate without repeating its checker.
        rejected = args.output / "runtime_driver/check.stderr"
        if rejected.exists() and "its type must be Data" in rejected.read_text():
            report["rejected_candidates"] = {"runtime_driver": {
                "status": "checker-rejected", "diagnostic": rejected.read_text()[:1800],
                "stderr_sha256": sha(rejected), "candidate_host_sha256": staged["candidate_host_sha256"],
                "reason": "+driver requires Data, but Driver<State> is Type; no cast or ownership weakening attempted"}}
        report["resume_profiling_tool_sha256"] = sha(Path(__file__))
    else:
        args.output.mkdir(parents=True)
        staged = snapshot(args.output / "input", args.revision)
        report = {"status": "running", "scope": "isolated builds, no game/window launch", "snapshot": staged,
                  "compiler": {"path": str(compiler), "sha256": sha(compiler), "version": platform_build.PINNED_VERSION},
                  "platform_policy_sha256": sha(Path(platform_build.__file__)),
                  "profiling_tool_sha256": sha(Path(__file__)), "variants": {}}
    if "persistent" in args.variants:
        additional = build_native.Snapshot()
        base = compiler.parent.parent / "bend2/base.bend"
        build_native.source_graph(ROOT / "persistent_client.bend", base.resolve(), dict(os.environ), additional)
        known = {item["lookup"]: item for item in staged["files"]}
        copied = {item["relative_path"]: item for item in staged["staged_files"]}
        for item in additional.manifest():
            if item["lookup"] in known:
                if item["sha256"] != known[item["lookup"]]["sha256"]:
                    raise RuntimeError("persistent dependencies differ from the frozen client comparison")
            else:
                staged["files"].append(item)
                known[item["lookup"]] = item
            source = Path(item["path"])
            try: relative = source.relative_to(ROOT)
            except ValueError: continue
            target = args.output / "input" / relative
            if str(relative) not in copied:
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
                record = {"relative_path": str(relative), "sha256": item["sha256"], "source_path": str(source)}
                staged["staged_files"].append(record)
                copied[str(relative)] = record
            assert sha(target) == item["sha256"]
        shutil.copy2(args.output / "input/persistent_client.bend", args.output / "input/persistent.bend")
        staged["persistent_entry_sha256"] = sha(args.output / "input/persistent.bend")
    before = {x["path"]: x["sha256"] for x in staged["files"]}
    world = next(x for x in staged["staged_files"] if x["relative_path"] == "src/client_world.bend")
    if world["sha256"] != "05040abf35b2b9ceaf87fed5c48f8d074d211750a59ab00fa6ff08e60a9ea5d7":
        raise RuntimeError("client world is not the root-audited frozen profile dependency")
    args.report.parent.mkdir(parents=True, exist_ok=True)
    def save(): args.report.write_text(json.dumps(report, indent=2) + "\n")
    save()
    deadline = time.monotonic() + args.quiet_wait
    while processes() and time.monotonic() < deadline:
        time.sleep(1)
    report.setdefault("quiet_intervals", []).append({"requested_variants": args.variants, "initial_other_compilers": processes()})
    save()
    for variant in args.variants:
        if variant in report["variants"]:
            raise RuntimeError("requested variant was already measured; broad reruns require a fresh output")
        folder = args.output / variant
        if folder.exists():
            raise RuntimeError("requested variant already has phase logs; existing measurements are not overwritten")
        folder.mkdir()
        entry = args.output / "input" / (variant + ".bend")
        raw, generated, binary = folder / "raw.c", folder / "transformed.c", folder / "native"
        checked = timed([compiler, entry, "--check-only"], folder, "check", accepted=(0,1))
        # A FAIL due solely to existing unsafe/foreign promises is still a valid
        # measurement of book_valid + book_promises, not a mathematical verdict.
        check_diagnostic = (folder / "check.stderr").read_text()
        if checked["return_code"] and "unsafe or foreign code" not in check_diagnostic:
            if variant == "runtime_driver" and "its type must be Data" in check_diagnostic:
                report.setdefault("rejected_candidates", {})[variant] = {"status": "checker-rejected", "check": checked,
                    "diagnostic": check_diagnostic[:1800], "reason": "+driver requires Data, but Driver<State> is Type"}
                save()
                continue
            raise RuntimeError("checking failed for a reason other than the existing promise boundary")
        emitted = timed([compiler, entry, "-o", raw], folder, "emit")
        if not raw.is_file(): raise RuntimeError("Bend did not emit C")
        generated.write_text(platform_build.transform(raw.read_text()))
        size = metrics(raw)
        gpu = size["gpu_bangs"]
        cc = platform_build.clang_path(os.environ.get("CC", "clang"), gpu)
        command = [cc, "-x", "objective-c", "-fobjc-arc", "-fmodules", "-std=c11", "-O3", str(generated), "-lpthread", "-lm", "-o", str(binary)]
        if gpu: command.insert(1, "-DBEND_METAL=1")
        if args.clang_trace:
            help_text = subprocess.run([cc, "--help"], capture_output=True, text=True, check=True).stdout
            if "-ftime-trace=<value>" not in help_text: raise RuntimeError("Clang does not advertise requested trace flag")
            command.insert(1, "-ftime-trace=" + str(folder / "clang-trace.json"))
        compiled = timed(command, folder, "clang")
        gpu_build = None
        if gpu:
            gpu_env = dict(os.environ, BEND_MINECRAFT_LAUNCH_MODE="hidden")
            gpu_build = timed([binary, "--gpu-build"], folder, "gpu", env=gpu_env)
        result = {"check": checked, "emission_including_check": emitted,
                  "emission_minus_check_estimate_seconds": emitted["wall_seconds"] - checked["wall_seconds"],
                  "raw_c": size, "transformed_c_sha256": sha(generated), "clang": compiled,
                  "gpu_build": gpu_build, "binary_sha256": sha(binary), "binary_bytes": binary.stat().st_size,
                  "build_total_without_extra_check_seconds": emitted["wall_seconds"] + compiled["wall_seconds"] + (gpu_build["wall_seconds"] if gpu_build else 0)}
        report["variants"][variant] = result
        save()
        print(json.dumps({"variant": variant, "raw_c_bytes": size["bytes"], "functions": size["function_definition_count"],
                          "fids": size["fid_count"], "build_total_seconds": result["build_total_without_extra_check_seconds"]}), flush=True)
    moved = [p for p, original in before.items() if not Path(p).is_file() or sha(p) != original]
    report["original_inputs_changed_during_profile"] = moved
    report["staged_inputs_changed_during_profile"] = [x["relative_path"] for x in staged["staged_files"] if sha(args.output / "input" / x["relative_path"]) != x["sha256"]]
    report["status"] = "pass" if not moved and not report["staged_inputs_changed_during_profile"] else "inputs-changed"
    save()
    if report["status"] != "pass": raise RuntimeError("profile dependencies moved; measurements are not a stable-source comparison")


if __name__ == "__main__":
    main()
