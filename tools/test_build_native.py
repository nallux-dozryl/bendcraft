#!/usr/bin/env python3
"""Exercise cache boundaries using the actual pinned Bend and native executables."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

import build_native as cache


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bend", type=Path, default=Path.home() / ".bend/bin/bend")
    parser.add_argument("--report", type=Path, default=cache.ROOT / "evidence/build-cache-selftest.json")
    args = parser.parse_args()
    observations, checks = [], []
    started = time.perf_counter()
    with tempfile.TemporaryDirectory(prefix="minecraft-native-cache-test-", dir=cache.ROOT / "build") as temporary:
        root = Path(temporary)
        installed = args.bend.resolve()
        (root / "install/bin").mkdir(parents=True)
        bend = root / "install/bin/bend"
        # A distinct real executable path makes BEND_DIR resolve to this isolated
        # test installation. Never modify the shared installed Base/effects.
        os.link(installed, bend)
        shutil.copytree(installed.parent.parent / "bend2", root / "install/bend2")
        project, directory = root / "fixture", root / "cache"
        project.mkdir()
        headers = root / "include"
        headers.mkdir()
        header = headers / "cache_fixture_extra.h"
        header.write_text('#define CACHE_TAG "native-A\\n"\n')
        env = {"CPATH": str(headers)}
        entry, direct, transitive, effect = [project / n for n in ("main.bend", "direct.bend", "transitive.bend", "effect.c")]
        entry.write_text('import Base\nimport ./direct.bend as D\nimport ./effect.bend as E\n\ndef main() -> IO(Unit):\n  IO.bind(Unit, Unit, E.ping(), ignored => IO.print(U32.show(D.value())))\n')
        direct.write_text('import Base\nimport ./transitive.bend as T\n\ndef value() -> U32:\n  U32.add(T.value(), 1)\n')
        transitive.write_text('import Base\n\ndef value() -> U32:\n  17\n')
        (project / "effect.bend").write_text('import Base\n\ndef ping() -> IO(Unit):\n  import "./effect.c"\n')
        effect.write_text('#include <cache_fixture_extra.h>\nTerm cache_ping_run(Env e, Term* f, IoWork* w) {\n  fputs(CACHE_TAG, stdout);\n  return term_pak(CID(Unit), 0);\n}\nstatic void __attribute__((constructor)) cache_ping_use(void) {\n  io_eff(CID(ping), cache_ping_run, 0);\n}\n')
        output = root / "native"

        def build(label, expected, **kwargs):
            report = cache.ensure_native(entry, output, bend=bend, cache_dir=directory, env=kwargs.pop("env", env), **kwargs)
            actual = subprocess.run([report["artifact"]], check=True, text=True, capture_output=True).stdout
            published = subprocess.run([str(output)], check=True, text=True, capture_output=True).stdout
            assert actual == expected and published == expected, (label, expected, actual, published)
            assert sha(output) == report["binary_sha256"] == sha(Path(report["artifact"]))
            observations.append({"label": label, "cache_hit": report["cache_hit"], "cache_key": report["cache_key"],
                                 "binary_sha256": report["binary_sha256"], "output": actual,
                                 "dependency_count": len(report["dependencies"]), "timings": report["timings"],
                                 "retries": report["retries"]})
            return report

        previous = build("first-build", "native-A\n18\n")
        assert not previous["cache_hit"]
        reused = build("reuse", "native-A\n18\n")
        assert reused["cache_hit"] and reused["cache_key"] == previous["cache_key"]
        elsewhere = root / "different-output-name"
        another = cache.ensure_native(entry, elsewhere, bend=bend, cache_dir=directory, env=env)
        assert another["cache_hit"] and another["cache_key"] == reused["cache_key"]
        assert sha(elsewhere) == reused["binary_sha256"]
        checks += ["first actual native build", "same-key digest-checked reuse and equivalent execution",
                   "same inputs reuse across distinct native output paths"]

        def miss(label, expected, previous):
            report = build(label, expected)
            assert not report["cache_hit"] and report["cache_key"] != previous["cache_key"], label
            checks.append(label + " invalidation with actual native execution")
            return report

        entry.write_text(entry.read_text() + "\n# Direct entry content invalidation.\n")
        previous = miss("entry", "native-A\n18\n", previous)
        direct.write_text(direct.read_text().replace("T.value(), 1", "T.value(), 2"))
        previous = miss("direct-import", "native-A\n19\n", previous)
        transitive.write_text(transitive.read_text().replace("  17", "  18"))
        previous = miss("transitive-import", "native-A\n20\n", previous)
        effect.write_text(effect.read_text() + "\n/* Native dependency content changed. */\n")
        previous = miss("native-effect", "native-A\n20\n", previous)
        header.write_text(header.read_text().replace("native-A", "native-B"))
        previous = miss("native-header", "native-B\n20\n", previous)
        assert previous["timings"]["emission_seconds"] == 0, "header change need not re-emit Bend"
        base = root / "install/bend2/base.bend"
        base.write_text(base.read_text() + "\n# Isolated Base invalidation.\n")
        previous = miss("installed-Base", "native-B\n20\n", previous)
        base_effect = root / "install/bend2/effs/print.c"
        base_effect.write_text(base_effect.read_text() + "\n/* Isolated Base native effect invalidation. */\n")
        previous = miss("installed-Base-native-effect", "native-B\n20\n", previous)
        configured = build("compiler-environment-config", "native-B\n20\n", env={**env, "MACOSX_DEPLOYMENT_TARGET": "14.0"})
        assert not configured["cache_hit"] and configured["cache_key"] != previous["cache_key"]
        checks.append("compiler deployment-target configuration invalidates and executes")
        previous = build("configuration-restored", "native-B\n20\n")
        assert previous["cache_hit"]

        # Isolate actual clang resource files before mutating them. The shared
        # compiler binary is only hard-linked; neither binary is modified.
        clang_install = root / "clang-install"
        (clang_install / "bin").mkdir(parents=True)
        actual_clang = Path(previous["compiler"]["resource_dir"]).parents[2] / "bin/clang"
        own_clang = clang_install / "bin/clang"
        os.link(actual_clang, own_clang)
        os.link(actual_clang.with_name("ld"), own_clang.with_name("ld"))
        shutil.copytree(previous["compiler"]["resource_dir"], clang_install / "lib/clang/17")
        for dylib in ("libLTO.dylib", "libtapi.dylib", "libcodedirectory.dylib", "libswiftDemangle.dylib"):
            (clang_install / "lib" / dylib).symlink_to(actual_clang.parent.parent / "lib" / dylib)
        clang_env = {**env, "CC": str(own_clang), "SDKROOT": previous["compiler"]["sysroots"][0]}
        toolchain_before = build("isolated-clang-resource-before", "native-B\n20\n", env=clang_env)
        resource_header = clang_install / "lib/clang/17/include/limits.h"
        resource_header.write_text(resource_header.read_text() + "\n/* Isolated resource content invalidation. */\n")
        toolchain_after = build("isolated-clang-resource-after", "native-B\n20\n", env=clang_env)
        assert not toolchain_after["cache_hit"] and toolchain_before["cache_key"] != toolchain_after["cache_key"]
        checks.append("actual isolated clang resource content invalidates without modifying installed tools")

        build("toolchain-configuration-restored", "native-B\n20\n")
        output.write_bytes(b"corrupt output")
        restored = build("published-output-corruption", "native-B\n20\n")
        assert restored["cache_hit"] and restored["output_replaced"]
        checks.append("corrupt published executable repaired from verified cache")
        artifact = Path(restored["artifact"])
        artifact.write_bytes(b"corrupt cached executable")
        repaired = build("cached-executable-corruption", "native-B\n20\n")
        assert not repaired["cache_hit"]
        checks.append("corrupt cached executable rejected and recompiled")
        manifest = directory / "entries" / repaired["cache_key"] / "manifest.json"
        record = json.loads(manifest.read_text())
        record["binary_sha256"] = "0" * 64
        manifest.write_text(json.dumps(record))
        repaired = build("manifest-digest-mismatch", "native-B\n20\n")
        assert not repaired["cache_hit"]
        checks.append("manifest/executable digest mismatch rejected")
        source_manifests = list((directory / "sources").glob("*/manifest.json"))
        for source_manifest in source_manifests:
            source_record = json.loads(source_manifest.read_text())
            if source_record["sha256"] == repaired["emitted_c_sha256"]:
                source_manifest.with_name("generated.c").write_text("corrupt emitted source")
        repaired = build("emitted-source-corruption", "native-B\n20\n")
        assert repaired["cache_hit"] and repaired["timings"]["emission_seconds"] > 0
        checks.append("corrupt retained emitted C regenerated before reuse")

        preserved = output.read_bytes()

        def refused(label, callback):
            try:
                callback()
            except (cache.CacheUnavailable, cache.BuildFailed) as e:
                checks.append(label + ": " + str(e).split("\n")[0])
            else:
                raise AssertionError(label + " was unexpectedly cached")
            assert output.read_bytes() == preserved, label + " changed output on failure"

        saved = transitive.read_text()
        transitive.unlink()
        refused("missing transitive dependency", lambda: build("bad-missing", ""))
        transitive.write_text(saved)
        saved_effect = effect.read_text()
        effect.unlink()
        refused("missing native dependency", lambda: build("bad-native", ""))
        effect.write_text(saved_effect)
        header.unlink()
        refused("missing native header", lambda: build("bad-header", ""))
        header.write_text('#define CACHE_TAG "native-B\\n"\n')
        effect.write_text(saved_effect + '\n#include "unresolved_relative.h"\n')
        refused("relative native include", lambda: build("bad-include", ""))
        effect.write_text(saved_effect)
        entry_bytes = entry.read_bytes()
        refused("dependency overwrite", lambda: cache.ensure_native(entry, entry, bend=bend, cache_dir=directory, env=env))
        assert entry.read_bytes() == entry_bytes
        refused("non-native output extension", lambda: cache.ensure_native(entry, output.with_suffix(".c"), bend=bend, cache_dir=directory, env=env))
        refused("compiler injection", lambda: build("bad-injection", "", env={**env, "CCC_OVERRIDE_OPTIONS": "+-O0"}))
        unverified = root / "unverified-bend"
        shutil.copy2(bend, unverified)
        with unverified.open("ab") as binary:
            binary.write(b"unverified compiler content")
        refused("unverified Bend binary content", lambda: cache.ensure_native(entry, output, bend=unverified, cache_dir=directory, env=env))
        wrapper = root / "clang-wrapper"
        wrapper.write_text('#!/bin/sh\nexec /usr/bin/clang "$@"\n')
        wrapper.chmod(0o755)
        refused("unresolvable compiler wrapper", lambda: build("bad-wrapper", "", env={**env, "CC": str(wrapper)}))
        missing_package = project / "missing-package.bend"
        missing_package.write_text('import Base\nimport cache-fixture@1.0.0.0/main.bend as P\n\ndef main() -> IO(Unit):\n  IO.print(U32.show(P.value()))\n')
        library = root / "library"
        named_env = {**env, "BEND_LIB": str(library)}
        refused("unresolved hub name without fetching", lambda: cache.ensure_native(missing_package, output, bend=bend, cache_dir=directory, env=named_env))
        (library / "names").mkdir(parents=True)
        for package, value in (("0x" + "1" * 32, 5), ("0x" + "2" * 32, 6)):
            (library / package).mkdir()
            (library / package / "main.bend").write_text(f"import Base\n\ndef value() -> U32:\n  {value}\n")
        mapping = library / "names/cache-fixture@1.0.0.0"
        mapping.write_text("0x" + "1" * 32 + "\n")
        named_before = cache.ensure_native(missing_package, root / "named-native", bend=bend, cache_dir=directory, env=named_env)
        assert subprocess.run([named_before["artifact"]], check=True, text=True, capture_output=True).stdout == "5\n"
        mapping.write_text("0x" + "2" * 32 + "\n")
        named_after = cache.ensure_native(missing_package, root / "named-native", bend=bend, cache_dir=directory, env=named_env)
        assert not named_after["cache_hit"] and named_after["cache_key"] != named_before["cache_key"]
        assert subprocess.run([named_after["artifact"]], check=True, text=True, capture_output=True).stdout == "6\n"
        checks.append("actual locally resolved named import and package-name mapping invalidation")

        window = project / "window.bend"
        window.write_text('import Base\n\ndef main() -> IO(Unit):\n  IO.bind(Result<&1, &1, U32 & String, Window>, Unit, Window.open("cache-test", 16, 16), result => IO.pure(Unit, Unit{}))\n')
        # Guard the actual emitted framework path, without launching any window.
        try:
            cache.ensure_native(window, output, bend=bend, cache_dir=directory, env=env)
        except cache.CacheUnavailable as e:
            assert "platform_build.py" in str(e), str(e)
            checks.append("checked Window emission is rejected specifically by the guarded platform route")
        else:
            raise AssertionError("valid Window program escaped the platform-route guard")
        assert output.read_bytes() == preserved
        refused("GPU/bang emitted route", lambda: cache.guard_route('#define BANGS 1\n'))

        # A first miss is slow enough for four actual callers to rendezvous. Use
        # processes (CLI), not only threads, to exercise OS file locking.
        concurrent = root / "concurrent-cache"
        def caller(index):
            report = root / f"concurrent-{index}.json"
            command = ["python3", str(Path(cache.__file__)), "build", str(entry), "-o", str(root / "concurrent-output"),
                       "--bend", str(bend), "--cache-dir", str(concurrent), "--report", str(report)]
            result = subprocess.run(command, env={**os.environ, **env}, text=True, capture_output=True)
            assert result.returncode == 0, result.stderr
            return json.loads(report.read_text())
        with ThreadPoolExecutor(max_workers=4) as workers:
            concurrent_reports = list(workers.map(caller, range(4)))
        assert sum(not r["cache_hit"] for r in concurrent_reports) == 1
        assert len({r["cache_key"] for r in concurrent_reports}) == 1
        assert len({r["binary_sha256"] for r in concurrent_reports}) == 1
        assert subprocess.run([str(root / "concurrent-output")], capture_output=True, text=True, check=True).stdout == "native-B\n20\n"
        checks.append("four simultaneous CLI processes: exactly one native build, three verified hits, one complete output")

        other_entry = project / "other.bend"
        other_entry.write_text('import Base\n\ndef main() -> IO(Unit):\n  IO.print("other-generation")\n')
        shared = root / "different-keys-output"
        def different_key(which):
            source = entry if which == 0 else other_entry
            return cache.ensure_native(source, shared, bend=bend, cache_dir=directory, env=env)
        with ThreadPoolExecutor(max_workers=2) as workers:
            generations = list(workers.map(different_key, (0, 1)))
        assert len({r["cache_key"] for r in generations}) == 2
        for result, expected in zip(generations, ("native-B\n20\n", "other-generation\n")):
            assert subprocess.run([result["artifact"]], capture_output=True, text=True, check=True).stdout == expected
        assert sha(shared) in {r["binary_sha256"] for r in generations}
        assert subprocess.run([str(shared)], capture_output=True, text=True, check=True).stdout in ("native-B\n20\n", "other-generation\n")
        checks.append("two concurrent different keys share one output: complete published generation and separate correct immutable artifacts")

        # Mutate a transitive input after the pre-build snapshot, then run actual
        # Bend. The old generation must be discarded and the new key rebuilt.
        original_run = cache.run
        mutations = []
        def mutating_run(command, environment):
            if command[0] == str(bend) and command[-1].endswith("/program") and not mutations:
                transitive.write_text(transitive.read_text().replace("  18", "  19"))
                mutations.append("native")
            return original_run(command, environment)
        cache.run = mutating_run
        try:
            changed = build("input-changes-during-native-build", "native-B\n21\n", force=True)
        finally:
            cache.run = original_run
        assert changed["retries"] == 1 and mutations == ["native"]
        checks.append("input changes during actual native build: old generation discarded, retry uses new key")

        # A source cache cannot retain C emitted from a moving input under its old
        # key; otherwise restoring that input could yield a poisoned future hit.
        entry.write_text(entry.read_text() + "\n# New emission generation.\n")
        mutations.clear()
        def moving_emission(command, environment):
            result = original_run(command, environment)
            if command[0] == str(bend) and command[-1].endswith("/generated.c") and not mutations:
                transitive.write_text(transitive.read_text().replace("  19", "  20"))
                mutations.append("emission")
            return result
        cache.run = moving_emission
        try:
            changed = build("input-changes-during-emission", "native-B\n22\n")
        finally:
            cache.run = original_run
        assert changed["retries"] == 1 and mutations == ["emission"]
        transitive.write_text(transitive.read_text().replace("  20", "  19"))
        restored = build("restore-before-moving-emission", "native-B\n21\n")
        checks.append("input changes during C emission: source generation discarded; restored inputs execute correctly")

        forced = build("force-rebuild", "native-B\n21\n", force=True)
        assert not forced["cache_hit"]
        checks.append("explicit force still runs the native checker/build")
        evidence = {"status": "pass", "scope": "verified ordinary macOS CPU Bend CLI compilation cache; no gameplay change",
                    "command": "python3 tools/test_build_native.py", "compiler_version": cache.PINNED_VERSION,
                    "compiler_sha256": sha(installed), "build_tool_sha256": sha(Path(cache.__file__)),
                    "test_tool_sha256": sha(Path(__file__)), "platform": cache.platform.platform(),
                    "checks": checks, "actual_build_observations": observations,
                    "concurrency": {"processes": 4, "native_builds": 1, "cache_hits": 3,
                                    "same_key": True, "same_binary_digest": True},
                    "dependency_kinds": sorted({d["kind"] for d in forced["dependencies"]}),
                    "dependency_count": len(forced["dependencies"]),
                    "timing_seconds": time.perf_counter() - started}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({"status": "pass", "checks": len(checks), "actual_build_observations": len(observations),
                      "report": str(args.report), "timing_seconds": evidence["timing_seconds"]}, indent=2))


if __name__ == "__main__":
    main()
