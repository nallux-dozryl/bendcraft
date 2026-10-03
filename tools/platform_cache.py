#!/usr/bin/env python3
"""Opt-in cache of the exact guarded macOS CPU Window build route."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import sys
import tempfile
import time
from typing import Mapping

if __package__:
    from . import build_native as native
    from . import platform_build as adapter
else:
    import build_native as native
    import platform_build as adapter

ROOT = Path(__file__).resolve().parents[1]
PINNED_ADAPTER = "1c9c53f77e63afa313816b8f3d1ae2ac2459273b0d0e5a26c63bbdc58c7aba8c"
FLAGS = ["-x", "objective-c", "-fobjc-arc", "-fmodules", "-std=c11", "-O3"]
FRAMEWORK_IMPORTS = {"AppKit/AppKit.h", "QuartzCore/QuartzCore.h"}
CacheUnavailable, BuildFailed, InputsChanged = native.CacheUnavailable, native.BuildFailed, native.InputsChanged


def _run(command, env):
    return native.run(list(map(str, command)), env)


def _route(raw):
    if not re.search(r"^#define BANGS\s+0$", raw, re.M):
        raise CacheUnavailable("GPU/bang/sidecar output is outside the CPU Window cache")
    imports = set(re.findall(r'^\s*#\s*import\s+<([^>]+)>', raw, re.M))
    if not imports or not imports.issubset(FRAMEWORK_IMPORTS):
        raise CacheUnavailable(f"unknown framework import route: {sorted(imports)}")
    if re.search(r"^\s*#\s*pragma\s+(?:comment\s*\(\s*(?:lib|linker)|clang\s+linker_option)", raw, re.M):
        raise CacheUnavailable("source-directed linker options have unresolved library dependencies")
    if ".linker_option" in raw:
        raise CacheUnavailable("assembly-directed linker options have unresolved dependencies")
    if re.search(r'^\s*#\s*import\s+(?!<)', raw, re.M):
        raise CacheUnavailable("non-angle framework imports are outside the pinned Window route")
    try:
        transformed = adapter.transform(raw)
    except ValueError as e:
        raise CacheUnavailable(f"guarded Window transform refused source: {e}") from e
    return transformed


def _collect(entry, bend, env):
    snapshot, context, effective = native._collect(entry, bend, env)
    snapshot.add(Path(__file__), "platform-cache-policy")
    snapshot.add(Path(adapter.__file__), "guarded-transform-policy")
    if native.file_digest(Path(adapter.__file__)) != PINNED_ADAPTER:
        raise CacheUnavailable("platform_build.py changed; inspect its transform/build rules before updating this cache policy")
    selected = context["compiler"]["path"]
    if Path(selected).resolve() != Path(env["CC"]).resolve():
        raise CacheUnavailable("requested C compiler is not supported by the guarded platform builder")
    driver_result = _run([selected, *FLAGS, "/dev/null", "-lpthread", "-lm", "-o", "/dev/null", "-###"], env)
    driver = driver_result.stdout + driver_result.stderr
    # Normalize only the driver's transient object path.
    for name in re.findall(r'"([^"\n]*/null-[0-9a-f]+\.o)"', driver):
        driver = driver.replace(name, "<temporary.o>")
    for line in driver.splitlines():
        if line.startswith("Configuration file: "):
            snapshot.add(Path(line[len("Configuration file: "):]), "objc-clang-config")
    context = {**context, "route": "guarded-macos-cpu-window-v1", "objc_driver_probe": driver,
               "objc_flags": FLAGS + ["<transformed.c>", "-lpthread", "-lm", "-o", "<native>"],
               "framework_imports": sorted(FRAMEWORK_IMPORTS), "files": snapshot.manifest()}
    return snapshot, context, effective


def _source(entry, bend, env, cache):
    snapshot, context, effective = _collect(entry, bend, env)
    prekey = native.digest(native.encoded(context))
    directory = cache / "sources" / prekey
    original, transformed = directory / "original.c", directory / "transformed.c"
    emission_seconds = 0.0
    with native.lock(cache / "locks" / ("source-" + prekey + ".lock")):
        record = native.read_json(directory / "manifest.json")
        valid = (record and record.get("prekey") == prekey and original.is_file() and transformed.is_file()
                 and record.get("original_sha256") == native.file_digest(original)
                 and record.get("transformed_sha256") == native.file_digest(transformed))
        if not valid:
            with tempfile.TemporaryDirectory(prefix=".source-", dir=cache / "sources") as temporary:
                temporary = Path(temporary)
                raw = temporary / "original.c"
                started = time.perf_counter()
                _run([bend, entry, "-o", raw], effective)
                emission_seconds = time.perf_counter() - started
                if not raw.is_file():
                    raise BuildFailed("Bend did not emit checked Window C")
                patched = _route(raw.read_text())
                (temporary / "transformed.c").write_text(patched)
                after, after_context, _ = _collect(entry, bend, env)
                if native.digest(native.encoded(after_context)) != prekey or after.stamps != snapshot.stamps:
                    raise InputsChanged("inputs changed during guarded C emission")
                record = {"prekey": prekey, "original_sha256": native.file_digest(raw),
                          "transformed_sha256": native.digest(patched.encode())}
                (temporary / "manifest.json").write_bytes(native.encoded(record))
                if directory.exists(): shutil.rmtree(directory)
                os.replace(temporary, directory)
        raw = original.read_text()
        patched = _route(raw)
        if native.digest(patched.encode()) != record["transformed_sha256"] or transformed.read_text() != patched:
            raise InputsChanged("retained source differs from current guarded transform")
    return snapshot, context, effective, prekey, original, transformed, record, emission_seconds


def _deps(cc, source, env, snapshot, folder):
    output = folder / "headers.d"
    # The installed cc1 advertises -module-file-deps. It reports PCM, module maps
    # and their underlying headers, including imported framework modules.
    _run([cc, *FLAGS, "-M", "-Xclang", "-module-file-deps", "-MF", output,
          "-MT", "window-cache-probe", source], env)
    text = output.read_text().replace("\\\n", "")
    try:
        paths = shlex.split(text.split(":", 1)[1])
    except (ValueError, IndexError) as e:
        raise CacheUnavailable("unparseable Objective-C module/header dependency graph") from e
    maps = set()
    for item in paths:
        path = Path(item)
        if path.resolve() == source.resolve(): continue
        kind = "objc-pcm" if item.endswith(".pcm") else "objc-module-map" if item.endswith("modulemap") else "objc-header"
        snapshot.add(path, kind)
        if kind == "objc-header":
            header_text = path.read_text(errors="replace")
            if re.search(r"^\s*#\s*pragma\s+(?:comment\s*\(\s*(?:lib|linker)|clang\s+linker_option)", header_text, re.M):
                raise CacheUnavailable(f"header-directed linker options are unsupported: {path}")
            if re.search(r"\b__(?:DATE|TIME|TIMESTAMP)__\b", header_text):
                raise CacheUnavailable(f"volatile compile-time macro in native header: {path}")
            if re.search(r"\b__BASE_FILE__\b", header_text) or ".linker_option" in header_text:
                raise CacheUnavailable(f"transient filename or assembly-directed linkage in native header: {path}")
        if kind == "objc-module-map":
            maps.add(str(path.resolve()))
    return maps


def _prepare(entry, bend, env, cache):
    snapshot, context, effective, prekey, original, transformed, record, seconds = _source(entry, bend, env, cache)
    cc = context["compiler"]["path"]
    with tempfile.TemporaryDirectory(prefix=".deps-", dir=cache) as temporary:
        temporary = Path(temporary)
        native_maps = _deps(cc, transformed, effective, snapshot, temporary)
        probe = temporary / "frameworks.m"
        probe.write_text(''.join(f'#import <{name}>\n' for name in sorted(FRAMEWORK_IMPORTS)) + "int main(void) { return 0; }\n")
        probe_folder = temporary / "probe"
        probe_folder.mkdir()
        framework_maps = _deps(cc, probe, effective, snapshot, probe_folder)
        if not native_maps.issubset(framework_maps):
            raise CacheUnavailable("native source imports framework modules outside the pinned AppKit/QuartzCore closure")
        # Link the exact known import closure to discover selected stubs/reexports
        # and external library shadowing. Never execute this probe.
        result = _run([cc, *FLAGS, probe, "-lpthread", "-lm", "-Wl,-t", "-o", temporary / "link-probe"], effective)
        selected = []
        for line in (result.stdout + result.stderr).splitlines():
            value = line.strip().split("(", 1)[0]
            path = Path(value)
            if not path.is_absolute() or value.startswith(str(temporary) + "/"): continue
            if re.fullmatch(r".*/frameworks-[0-9a-f]+\.o", value): continue
            if not path.is_file():
                raise CacheUnavailable(f"unresolved Objective-C linker input: {value}")
            snapshot.add(path, "objc-linker-selected-input")
            selected.append(str(path.resolve()))
        if not any("AppKit.framework/" in p for p in selected) or not any("QuartzCore.framework/" in p for p in selected):
            raise CacheUnavailable("framework linker trace did not resolve AppKit and QuartzCore")
    key_data = {"prekey": prekey, "original_c_sha256": record["original_sha256"],
                "transformed_c_sha256": record["transformed_sha256"], "dependencies": snapshot.manifest()}
    return {"cache_key": native.digest(native.encoded(key_data)), "key_data": key_data, "snapshot": snapshot,
            "context": context, "env": effective, "source_report": record, "emission_seconds": seconds,
            "original_path": original, "transformed_path": transformed}


def ensure_platform(entry: str | Path, output: str | Path, *, bend: str | Path | None = None,
                    cc: str | Path | None = None, cache_dir: str | Path | None = None,
                    env: Mapping[str, str] | None = None, force: bool = False) -> dict:
    """Reuse only verified artifacts of the unchanged guarded CPU Window builder."""
    started = time.perf_counter()
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise CacheUnavailable("verified CPU Window cache requires macOS Apple Silicon")
    environment = dict(os.environ)
    if env: environment.update({str(k):str(v) for k,v in env.items()})
    for name in set(native.UNSUPPORTED_ENV) | {k for k in environment if k.startswith("DYLD_")}:
        if environment.get(name): raise CacheUnavailable(f"unresolved compiler injection: {name}")
    requested_cc = cc or environment.get("CC") or "clang"
    environment["CC"] = str(native.resolve_executable(requested_cc, environment))
    bend = native.resolve_executable(str(bend or environment.get("BEND") or Path.home()/".bend/bin/bend"), environment).resolve()
    entry, output = Path(entry).expanduser().resolve(), Path(output).expanduser().absolute()
    if output.is_symlink() or output.is_dir() or output.suffix in (".c", ".js", ".mjs", ".cjs", ".bendtt", ".gpu"):
        raise CacheUnavailable("output must be a distinct plain native file; emitted/GPU/symlink routes are unsupported")
    cache = Path(cache_dir or ROOT/"build/platform-cache").expanduser().resolve()
    for name in ("", "sources", "entries", "artifacts", "locks"):
        (cache/name).mkdir(parents=True, exist_ok=True, mode=0o700)
    output.parent.mkdir(parents=True, exist_ok=True)
    retries = 0
    for attempt in range(3):
        try:
            prepared = _prepare(entry, bend, environment, cache)
            if str(output.resolve()) in {d["path"] for d in prepared["snapshot"].manifest()}:
                raise CacheUnavailable("native output would overwrite a build dependency")
            key = prepared["cache_key"]
            directory = cache/"entries"/key
            build_seconds = 0.0
            with native.lock(cache/"locks"/("native-"+key+".lock")):
                record = None if force else native._verified(directory, key)
                hit = record is not None
                if not hit:
                    with tempfile.TemporaryDirectory(prefix=".native-", dir=cache/"entries") as temporary:
                        temporary = Path(temporary)
                        binary, generated = temporary/"program", temporary/"generated.c"
                        source = prepared["source_report"]
                        original = prepared["original_path"].read_text()
                        patched = _route(original)
                        if (native.digest(original.encode()) != source["original_sha256"] or
                            native.digest(patched.encode()) != source["transformed_sha256"] or
                            prepared["transformed_path"].read_text() != patched):
                            raise InputsChanged("retained guarded C changed before native compilation")
                        generated.write_text(patched)
                        build_started = time.perf_counter()
                        # The pinned adapter's exact CPU command compiles retained
                        # guarded C. Re-emitting mutable Bend here could enter its
                        # GPU build branch after a previously valid CPU preflight.
                        clang = prepared["context"]["compiler"]["path"]
                        command = [clang, *FLAGS, generated, "-lpthread", "-lm", "-o", binary]
                        compiled = _run(command, prepared["env"])
                        build_seconds = time.perf_counter()-build_started
                        if not binary.is_file() or not os.access(binary, os.X_OK):
                            raise BuildFailed("guarded CPU command did not produce a Window executable")
                        built = {"compiler_version":adapter.PINNED_VERSION,
                                 "compiler_sha256":adapter.PINNED_COMPILER_SHA256,
                                 "base_window_sha256":adapter.PINNED_WINDOW_SHA256,
                                 "generated_sha256":source["original_sha256"],
                                 "transformed_sha256":source["transformed_sha256"],
                                 "gpu_bangs":False, "clang":clang,
                                 "build_command":[clang,*FLAGS,"<verified transformed.c>","-lpthread","-lm","-o","<native>"],
                                 "build_stdout":compiled.stdout[-4000:],"build_stderr":compiled.stderr[-4000:]}
                        checked = _prepare(entry, bend, environment, cache)
                        if checked["cache_key"] != key or checked["snapshot"].stamps != prepared["snapshot"].stamps:
                            raise InputsChanged("dependencies changed during guarded native build")
                        record = {"cache_key": key, "key_data": prepared["key_data"], "route": "guarded-cpu-window",
                                  "binary_sha256": native.file_digest(binary), "binary_bytes": binary.stat().st_size,
                                  "adapter": built}
                        native._freeze(binary, cache, record["binary_sha256"])
                        (temporary/"manifest.json").write_bytes(native.encoded(record))
                        if directory.exists(): shutil.rmtree(directory)
                        os.replace(temporary, directory)
                else:
                    checked = _prepare(entry, bend, environment, cache)
                    if checked["cache_key"] != key or checked["snapshot"].stamps != prepared["snapshot"].stamps:
                        raise InputsChanged("dependencies changed during Window cache verification")
                if native._verified(directory, key) is None:
                    raise InputsChanged("guarded executable failed its final digest check")
                binary = cache/"artifacts"/record["binary_sha256"]/"program"
                replaced = native._publish(binary, output, record["binary_sha256"], cache)
                return {"path":str(output), "artifact":str(binary), "cache_key":key, "cache_hit":hit,
                        "binary_sha256":record["binary_sha256"], "binary_bytes":record["binary_bytes"],
                        "original_c_sha256":prepared["source_report"]["original_sha256"],
                        "transformed_c_sha256":prepared["source_report"]["transformed_sha256"],
                        "route":"guarded-macos-cpu-window", "output_replaced":replaced, "retries":retries,
                        "dependencies":prepared["snapshot"].manifest(), "compiler":prepared["context"]["compiler"],
                        "identity":{k:v for k,v in prepared["context"].items() if k not in ("files","compiler")},
                        "timings":{"total_seconds":time.perf_counter()-started, "emission_seconds":prepared["emission_seconds"],
                                   "guarded_native_build_seconds":build_seconds}}
        except InputsChanged:
            retries += 1
            if attempt == 2: raise InputsChanged("inputs kept changing; no Window executable was published")
    raise AssertionError("unreachable")


def main():
    argv = sys.argv[1:]
    if argv and argv[0]=="build": argv=argv[1:]
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("entry",type=Path); parser.add_argument("-o","--output",required=True,type=Path)
    parser.add_argument("--bend"); parser.add_argument("--cc"); parser.add_argument("--cache-dir",type=Path)
    parser.add_argument("--force",action="store_true"); parser.add_argument("--report",type=Path)
    args=parser.parse_args(argv)
    try:
        result=ensure_platform(args.entry,args.output,bend=args.bend,cc=args.cc,cache_dir=args.cache_dir,force=args.force)
    except (CacheUnavailable,BuildFailed,InputsChanged) as e:
        print(f"platform cache: {e}",file=sys.stderr); return 1
    if args.report:
        args.report.parent.mkdir(parents=True,exist_ok=True)
        with tempfile.NamedTemporaryFile(prefix=".report-",dir=args.report.parent,delete=False) as out:
            out.write(json.dumps(result,indent=2).encode()+b"\n"); name=out.name
        os.replace(name,args.report)
    print(json.dumps({k:result[k] for k in ("path","artifact","cache_key","cache_hit","binary_sha256","timings")},indent=2))
    return 0

if __name__=="__main__": raise SystemExit(main())
