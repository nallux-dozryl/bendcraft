#!/usr/bin/env python3
"""Actual hidden Window cache tests; no foreground activation is requested."""
from __future__ import annotations
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

import platform_cache as cache
import platform_test

ROOT = cache.ROOT


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def sdk_overlay(source, target):
    """Copy only AppKit; all other SDK entries remain read-only symlinks."""
    target.mkdir()
    def level(src, dst, special):
        for child in src.iterdir():
            here = dst/child.name
            if child.name == special:
                here.mkdir()
            else:
                here.symlink_to(child, target_is_directory=child.is_dir())
    level(source,target,"System")
    level(source/"System",target/"System","Library")
    level(source/"System/Library",target/"System/Library","Frameworks")
    for child in (source/"System/Library/Frameworks").iterdir():
        here=target/"System/Library/Frameworks"/child.name
        if child.name=="AppKit.framework": shutil.copytree(child,here,symlinks=True)
        else: here.symlink_to(child,target_is_directory=child.is_dir())


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report",type=Path,default=ROOT/"evidence/platform-cache-selftest.json")
    args=parser.parse_args()
    observations, checks=[],[]
    started=time.perf_counter()
    package_api=subprocess.run([sys.executable,"-c","from tools.platform_cache import ensure_platform; print(ensure_platform.__name__)"],
                               cwd=ROOT,capture_output=True,text=True)
    assert package_api.returncode==0 and package_api.stdout.strip()=="ensure_platform",package_api.stderr
    checks.append("stable Python API imports both as a tools package and script module")
    with tempfile.TemporaryDirectory(prefix="platform-cache-test-",dir=ROOT/"build") as temporary:
        root=Path(temporary); project=root/"fixture"; project.mkdir()
        installed=Path.home()/".bend/bin/bend"
        (root/"install/bin").mkdir(parents=True)
        bend=root/"install/bin/bend"; os.link(installed,bend)
        shutil.copytree(installed.parent.parent/"bend2",root/"install/bend2")
        headers=root/"include"; headers.mkdir()
        header=headers/"cache_extra.h"; header.write_text('#define CACHE_TAG "effect-A\\n"\n')
        env={"CPATH":str(headers)}
        entry=project/"main.bend"; direct=project/"direct.bend"; transitive=project/"transitive.bend"; effect=project/"effect.c"
        direct.write_text('import Base\nimport ./transitive.bend as T\n\ndef value() -> U32:\n  U32.add(T.value(), 1)\n')
        transitive.write_text('import Base\n\ndef value() -> U32:\n  17\n')
        (project/"effect.bend").write_text('import Base\n\ndef mark() -> IO(Unit):\n  import "./effect.c"\n')
        effect.write_text('#include <cache_extra.h>\nTerm marker_run(Env e, Term* f, IoWork* w) { fputs(CACHE_TAG,stdout); return term_pak(CID(Unit),0); }\nstatic void __attribute__((constructor)) marker_use(void) { io_eff(CID(mark),marker_run,0); }\n')
        shutil.copy2(ROOT/"src/platform.bend",project/"platform.bend")
        (project/"native").mkdir(); shutil.copy2(ROOT/"src/native/platform.c",project/"native/platform.c")
        fixture=(ROOT/"tests/platform.bend").read_text().replace("../src/platform.bend","./platform.bend")
        fixture=fixture.replace("import Base", "import Base\nimport ./direct.bend as D\nimport ./effect.bend as E",1)
        fixture=fixture.replace('    before : String <- P.Platform.observe()', '    E.mark()\n    IO.print("value=" ++ U32.show(D.value()))\n    before : String <- P.Platform.observe()')
        entry.write_text(fixture)
        swift=root/"observer.swift"; observer=root/"observer"
        swift.write_text(platform_test.OBSERVER)
        subprocess.run(["/usr/bin/swiftc","-O",str(swift),"-o",str(observer)],check=True,capture_output=True)
        output=root/"native"; directory=root/"cache"

        def observe(artifact,expected_tag,expected_value):
            execution=subprocess.run([str(observer),str(artifact)],env={**os.environ,"BEND_MINECRAFT_LAUNCH_MODE":"hidden"},check=True,text=True,capture_output=True,timeout=25)
            report=json.loads(execution.stdout)
            assert report["child_status"]==0 and not report["timed_out"], report
            assert report["before_frontmost_pid"]==report["after_frontmost_pid"]>0
            assert report["sampled_frontmost_pids"]==[report["before_frontmost_pid"]]
            assert report["child_pid"] not in report["activation_notification_pids"] and report["space_change_notifications"]==0
            values={}
            for line in report["stdout"].splitlines():
                if line.startswith("platform_") and "=" in line:
                    key,text=line.split("=",1); values[key]=json.loads(text)
            assert report["stdout"].startswith(expected_tag+"\nvalue="+str(expected_value)+"\n"),report["stdout"]
            assert values["platform_frame_returned"] is True
            window=values["platform_window"]
            assert window["native_macos"] and window["window_number"]>0
            assert all(window[k] is False for k in ("visible","key","main","app_active")) and window["activation_policy"]==2
            return {"child_status":report["child_status"],"frontmost_unchanged":True,"space_changes":0,
                    "activated_child":False,"window_visible":False,"frame_returned":True,
                    "observations_sha256":hashlib.sha256(json.dumps(report,sort_keys=True).encode()).hexdigest()}

        def build(label,tag="effect-A",value=18,**kwargs):
            report=cache.ensure_platform(entry,output,bend=bend,cache_dir=directory,env=kwargs.pop("env",env),**kwargs)
            assert sha(output)==sha(report["artifact"])==report["binary_sha256"]
            seen=observe(report["artifact"],tag,value)
            observations.append({"label":label,"cache_hit":report["cache_hit"],"cache_key":report["cache_key"],
                                 "binary_sha256":report["binary_sha256"],"timings":report["timings"],
                                 "retries":report["retries"],"hidden_execution":seen})
            return report

        previous=build("first-miss"); assert not previous["cache_hit"]
        reused=build("warm-hit"); assert reused["cache_hit"] and reused["cache_key"]==previous["cache_key"]
        assert reused["timings"]["emission_seconds"]==reused["timings"]["guarded_native_build_seconds"]==0
        checks+=['actual guarded CPU Window miss/hit execute hidden without focus/Space changes','hit skips Bend emission and guarded native build']
        baseline_path,baseline_report=root/"adapter-native",root/"adapter-report.json"
        baseline_started=time.perf_counter()
        baseline_result=subprocess.run([sys.executable,str(ROOT/"tools/platform_build.py"),str(entry),"-o",str(baseline_path),
                                       "--bend",str(bend),"--cc",previous["compiler"]["path"],"--report",str(baseline_report)],
                                      env={**os.environ,**env},capture_output=True,text=True)
        assert baseline_result.returncode==0,baseline_result.stderr
        baseline=json.loads(baseline_report.read_text())
        baseline["elapsed_seconds"]=time.perf_counter()-baseline_started
        assert baseline["gpu_bangs"] is False and baseline["generated_sha256"]==previous["original_c_sha256"]
        assert baseline["transformed_sha256"]==previous["transformed_c_sha256"]
        baseline["hidden_execution"]=observe(baseline_path,"effect-A",18)
        checks.append("independent unchanged platform_build CLI has identical original/transformed C and hidden native behavior")

        def miss(label,value,tag="effect-A"):
            nonlocal previous
            next=build(label,tag,value); assert not next["cache_hit"] and next["cache_key"]!=previous["cache_key"]
            checks.append(label+" invalidation and hidden native execution"); previous=next
        entry.write_text(entry.read_text()+"\n# Direct source change.\n"); miss("entry",18)
        direct.write_text(direct.read_text().replace("T.value(), 1","T.value(), 2")); miss("direct-import",19)
        transitive.write_text(transitive.read_text().replace("  17","  18")); miss("transitive-import",20)
        effect.write_text(effect.read_text()+"\n/* Native effect content change. */\n"); miss("native-effect",20)
        header.write_text(header.read_text().replace("effect-A","effect-B")); miss("native-header",20,"effect-B")
        assert previous["timings"]["emission_seconds"]==0
        base=root/"install/bend2/base.bend"; base.write_text(base.read_text()+"\n# Isolated Base comment.\n"); miss("installed-Base",20,"effect-B")
        configured=build("compiler-config","effect-B",20,env={**env,"MACOSX_DEPLOYMENT_TARGET":"14.0"})
        assert not configured["cache_hit"] and configured["cache_key"]!=previous["cache_key"]
        checks.append("actual compiler/deployment configuration invalidation")
        restored=build("config-restored","effect-B",20); assert restored["cache_hit"]

        sdk=Path(previous["compiler"]["sysroots"][0]); private_sdk=root/"SDK.sdk"; sdk_overlay(sdk,private_sdk)
        sdk_env={**env,"SDKROOT":str(private_sdk)}
        sdk_before=build("isolated-framework-before","effect-B",20,env=sdk_env)
        appkit=private_sdk/"System/Library/Frameworks/AppKit.framework"
        framework_header=appkit/"Versions/C/Headers/AppKit.h"
        if not framework_header.is_file(): framework_header=(appkit/"Headers/AppKit.h").resolve()
        assert framework_header.is_relative_to(root),framework_header
        framework_header.write_text(framework_header.read_text()+"\n/* Isolated SDK framework header change. */\n")
        sdk_header=build("isolated-framework-header","effect-B",20,env=sdk_env)
        assert not sdk_header["cache_hit"] and sdk_header["cache_key"]!=sdk_before["cache_key"]
        stub=(appkit/"AppKit.tbd").resolve()
        if not stub.is_file(): stub=next(appkit.rglob("AppKit.tbd")).resolve()
        assert stub.is_relative_to(root),stub
        stub.write_text(stub.read_text()+"\n \n")
        sdk_link=build("isolated-framework-linker","effect-B",20,env=sdk_env)
        assert not sdk_link["cache_hit"] and sdk_link["cache_key"]!=sdk_header["cache_key"]
        checks+=['actual private SDK framework header/module closure invalidation','actual private SDK framework linker input invalidation']
        build("sdk-config-restored","effect-B",20)
        clang_install=root/"clang-install"; (clang_install/"bin").mkdir(parents=True)
        resource=Path(previous["compiler"]["resource_dir"]); actual_clang=resource.parents[2]/"bin/clang"
        own_clang=clang_install/"bin/clang"; os.link(actual_clang,own_clang)
        os.link(actual_clang.with_name("ld"),own_clang.with_name("ld"))
        shutil.copytree(resource,clang_install/"lib/clang/17")
        for dylib in ("libLTO.dylib","libtapi.dylib","libcodedirectory.dylib","libswiftDemangle.dylib"):
            (clang_install/"lib"/dylib).symlink_to(actual_clang.parent.parent/"lib"/dylib)
        tool_env={**env,"CC":str(own_clang),"SDKROOT":str(sdk)}
        tool_before=build("isolated-toolchain-before","effect-B",20,env=tool_env)
        limits=clang_install/"lib/clang/17/include/limits.h"
        limits.write_text(limits.read_text()+"\n/* Isolated clang resource bytes changed. */\n")
        tool_after=build("isolated-toolchain-after","effect-B",20,env=tool_env)
        assert not tool_after["cache_hit"] and tool_after["cache_key"]!=tool_before["cache_key"]
        checks.append("actual private clang resource content invalidation")
        build("toolchain-config-restored","effect-B",20)

        output.write_bytes(b"corrupt output")
        repaired=build("output-corruption","effect-B",20); assert repaired["cache_hit"] and repaired["output_replaced"]
        Path(repaired["artifact"]).write_bytes(b"corrupt cached executable")
        repaired=build("artifact-corruption","effect-B",20); assert not repaired["cache_hit"]
        manifest=directory/"entries"/repaired["cache_key"]/"manifest.json"
        data=json.loads(manifest.read_text()); data["binary_sha256"]="0"*64; manifest.write_text(json.dumps(data))
        repaired=build("manifest-corruption","effect-B",20); assert not repaired["cache_hit"]
        checks+=['published/cached/manifest corruption is repaired without executing mismatched bytes']
        for source_manifest in (directory/"sources").glob("*/manifest.json"):
            source_record=json.loads(source_manifest.read_text())
            if source_record["transformed_sha256"]==repaired["transformed_c_sha256"]:
                source_manifest.with_name("transformed.c").write_text("corrupt transformed C")
        source_repaired=build("transformed-source-corruption","effect-B",20)
        assert source_repaired["cache_hit"] and source_repaired["timings"]["emission_seconds"]>0
        checks.append("corrupt retained transformed C is regenerated through the exact guard before reuse")
        preserved=output.read_bytes()
        def refused(label,call,expected=None):
            try:call()
            except (cache.CacheUnavailable,cache.BuildFailed) as e:
                if expected: assert isinstance(e,cache.CacheUnavailable) and expected in str(e),str(e)
                checks.append(label+": "+str(e).split("\n")[0])
            else:raise AssertionError(label+" was accepted")
            assert output.read_bytes()==preserved
        saved=transitive.read_text(); transitive.unlink()
        refused("missing transitive dependency",lambda:build("bad","effect-B",20)); transitive.write_text(saved)
        refused("ordinary non-Window source",lambda:cache._route("#define BANGS 0\nint main(void){return 0;}"))
        refused("GPU/bang route",lambda:cache._route("#define BANGS 1\n"))
        refused("unknown framework route",lambda:cache._route("#define BANGS 0\n#import <Unknown/Unknown.h>\n"))
        refused("dependency overwrite",lambda:cache.ensure_platform(entry,entry,bend=bend,cache_dir=directory,env=env))
        window_effect=root/"install/bend2/effs/window.c"
        saved_window=window_effect.read_text()
        window_effect.write_text(saved_window.replace("win.acceptsMouseMovedEvents = YES;","win.acceptsMouseMovedEvents = NO;"))
        refused("modified Window implementation guard",lambda:build("bad-window","effect-B",20))
        window_effect.write_text(saved_window)
        gpu_entry=project/"gpu.bend"
        gpu_text=entry.read_text().replace("Pix{2241348}","Pix{pixel!(2241348)}")
        gpu_text=gpu_text.replace("def main()", "def pixel(x:U32) -> U32:\n  U32.add(x, 0)\n\ndef main()")
        gpu_entry.write_text(gpu_text)
        refused("actual checked GPU Window fixture",lambda:cache.ensure_platform(gpu_entry,output,bend=bend,cache_dir=directory,env=env),"GPU/bang/sidecar")
        saved_header=header.read_text(); header.write_text(saved_header+"\n#define UNCACHEABLE_TIME __TIME__\n")
        refused("volatile native header",lambda:build("volatile-header","effect-B",20),"volatile compile-time macro")
        header.write_text(saved_header)

        # Change policy bytes only in an isolated tool checkout; new imports run
        # in new processes so byte/key invalidation is real, not monkeypatching.
        tools=root/"tools"; tools.mkdir()
        for name in ("platform_cache.py","platform_build.py","build_native.py"):
            shutil.copy2(ROOT/"tools"/name,tools/name)
        policy_cache=root/"policy-cache"
        def policy_build(label):
            report=root/(label+".json")
            result=subprocess.run([sys.executable,str(tools/"platform_cache.py"),"build",str(entry),"-o",str(output),"--bend",str(bend),"--cache-dir",str(policy_cache),"--report",str(report)],env={**os.environ,**env},text=True,capture_output=True)
            return result,json.loads(report.read_text()) if report.exists() else None
        result,policy_first=policy_build("policy-first"); assert result.returncode==0,result.stderr
        copied_policy=tools/"platform_cache.py"; copied_policy.write_text(copied_policy.read_text()+"\n# Isolated cache policy byte change.\n")
        result,policy_next=policy_build("policy-next"); assert result.returncode==0,result.stderr
        assert not policy_next["cache_hit"] and policy_next["cache_key"]!=policy_first["cache_key"]
        copied_adapter=tools/"platform_build.py"; copied_adapter.write_text(copied_adapter.read_text()+"\n# Uninspected transform policy change.\n")
        result,_=policy_build("adapter-changed"); assert result.returncode!=0 and "platform_build.py changed" in result.stderr
        checks+=['new cache policy bytes invalidate via actual separate CLI','changed transform/build policy explicitly refuses unknown semantics']

        concurrent=root/"concurrent-cache"
        def caller(i):
            report=root/f"concurrent-{i}.json"
            result=subprocess.run([sys.executable,str(ROOT/"tools/platform_cache.py"),"build",str(entry),"-o",str(root/"concurrent-output"),"--bend",str(bend),"--cache-dir",str(concurrent),"--report",str(report)],env={**os.environ,**env},capture_output=True,text=True)
            assert result.returncode==0,result.stderr
            return json.loads(report.read_text())
        with ThreadPoolExecutor(max_workers=3) as pool: simultaneous=list(pool.map(caller,range(3)))
        assert sum(not r["cache_hit"] for r in simultaneous)==1
        assert len({r["cache_key"] for r in simultaneous})==1 and len({r["binary_sha256"] for r in simultaneous})==1
        concurrent_observation=observe(simultaneous[0]["artifact"],"effect-B",20)
        checks.append("three simultaneous actual CLI processes: one guarded build and two verified hits")

        alternate=project/"alternate.bend"
        alternate.write_text(entry.read_text().replace("U32.show(D.value())","U32.show(U32.add(D.value(), 10))"))
        different_cache=root/"different-key-cache"; different_output=root/"different-key-output"
        def generation(source):
            return cache.ensure_platform(source,different_output,bend=bend,cache_dir=different_cache,env=env)
        with ThreadPoolExecutor(max_workers=2) as pool:
            different=list(pool.map(generation,(entry,alternate)))
        assert all(not r["cache_hit"] for r in different) and len({r["cache_key"] for r in different})==2
        assert len({r["binary_sha256"] for r in different})==2 and sha(different_output) in {r["binary_sha256"] for r in different}
        different_observations=[observe(report["artifact"],"effect-B",value) for report,value in zip(different,(20,30))]
        checks.append("two simultaneous source keys sharing an output retain distinct correct hidden artifacts")

        original_run=cache._run; moved_to_gpu=[]; commands=[]; saved_entry=entry.read_text()
        def native_build(command):
            return "-o" in command and Path(command[-1]).name=="program" and Path(command[0]).name=="clang"
        def changing_route(command,environment):
            commands.append(list(map(str,command)))
            if native_build(command) and not moved_to_gpu:
                entry.write_text(gpu_text); moved_to_gpu.append(True)
            return original_run(command,environment)
        cache._run=changing_route
        try:refused("CPU-to-GPU source change during compilation",lambda:build("moving-gpu","effect-B",20,force=True),"GPU/bang/sidecar")
        finally:cache._run=original_run; entry.write_text(saved_entry)
        assert moved_to_gpu and not any("--gpu-build" in c or "-DBEND_METAL=1" in c for c in commands)
        assert not list(root.rglob("*.gpu"))
        checks.append("moving CPU/GPU route never invokes GPU compilation/build or publishes an executable")

        moved=[]
        def moving(command,environment):
            if native_build(command) and not moved:
                transitive.write_text(transitive.read_text().replace("  18","  19")); moved.append(True)
            return original_run(command,environment)
        cache._run=moving
        try:changed=build("moving-input","effect-B",21,force=True)
        finally:cache._run=original_run
        assert changed["retries"]==1 and moved
        checks.append("input change during retained C compilation discards old generation and retries")
        evidence={"status":"pass","scope":"strict cache of guarded macOS CPU Window output; hidden launches only",
                  "command":"python3 tools/test_platform_cache.py","checks":checks,"observations":observations,
                  "policy_sha256":sha(ROOT/"tools/platform_cache.py"),"test_sha256":sha(Path(__file__)),
                  "unchanged_platform_build_sha256":sha(ROOT/"tools/platform_build.py"),
                  "unchanged_build_native_sha256":sha(ROOT/"tools/build_native.py"),
                  "unchanged_adapter_baseline":baseline,
                  "dependency_count":len(changed["dependencies"]),"dependency_kinds":sorted({d["kind"] for d in changed["dependencies"]}),
                  "concurrency":{"processes":3,"guarded_builds":1,"verified_hits":2,"hidden_execution":concurrent_observation},
                  "different_key_concurrency":{"processes":2,"distinct_keys":2,"distinct_artifacts":2,
                                               "hidden_executions":different_observations},
                  "actual_hidden_executions":len(observations)+4,
                  "timing_seconds":time.perf_counter()-started}
    args.report.parent.mkdir(parents=True,exist_ok=True); args.report.write_text(json.dumps(evidence,indent=2)+"\n")
    print(json.dumps({"status":"pass","checks":len(checks),"observations":len(observations),"report":str(args.report)},indent=2))

if __name__=="__main__": main()
