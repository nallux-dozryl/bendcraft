# Guarded CPU Window compilation cache

`tools/platform_cache.py` is an opt-in cache for the pinned macOS Apple Silicon **CPU Window** build route. It retains checked Bend C, calls the unchanged `platform_build.transform`, and compiles that transformed C with the adapter's exact Objective-C CPU command. It never substitutes an ordinary untransformed native executable. Existing `platform_build.py`, `build_native.py`, Bend sources, and compiler/runtime code are unchanged.

```sh
python3 tools/platform_cache.py build client.bend -o build/client \
  --report build/client-build.json
```

```python
import os
import subprocess
from tools.platform_cache import ensure_platform

build = ensure_platform("client.bend", "build/client")
# Execute this content-addressed generation when callers share an output path.
subprocess.run([build["artifact"]], env={**os.environ,
    "BEND_MINECRAFT_LAUNCH_MODE": "hidden"}, check=True)
```

The stable API is:

```python
ensure_platform(entry, output, *, bend=None, cc=None, cache_dir=None,
                env=None, force=False) -> dict
```

Paths accept strings or `Path` objects. The default Bend is `$BEND` or `~/.bend/bin/bend`; the default C compiler is explicit `cc`, `$CC`, or `clang`. The default cache is `build/platform-cache`, separate from the ordinary native cache. `env` overrides inherited build environment entries. `force=True` recompiles the guarded native executable with all checks intact; retained C can still be reused. An empty cache forces fresh Bend emission too.

Results include `path` (an atomic convenience copy), `artifact` (the verified binary content-addressed generation), `cache_key`, `cache_hit`, `binary_sha256`, `binary_bytes`, `original_c_sha256`, `transformed_c_sha256`, `dependencies`, `compiler`, `identity`, `retries`, `output_replaced`, and `timings`. Use the artifact path if another caller can publish a different generation to the same output. Content-addressed artifacts are immutable by cache convention; external modification is detected and repaired, not trusted. Do not delete caches while callers still need their artifact paths.

`timings.emission_seconds` measures needed Bend C emission. `guarded_native_build_seconds` measures Clang compiling the retained transformed C. `total_seconds` also includes dependency discovery, hashing, stability checks, locks, and publication. A warm hit has zero emission and native-build times. `--report` atomically writes the full JSON result; normal CLI output is compact. `--bend`, `--cc`, `--cache-dir`, and `--force` mirror the API.

`CacheUnavailable`, `BuildFailed`, and `InputsChanged` distinguish unsupported/unresolvable inputs, actual checker/compiler errors, and repeatedly moving inputs. CLI errors return nonzero with a diagnostic. A failed generation does not replace a previously published executable.

## Pinned route and supported boundary

The policy pins Bend 2.0.35, executable SHA-256 `99b3de8f6c5643d245bed839df2c28d1bb12efd41bb221154d25c15695b72e8e`, and the unchanged `platform_build.py` SHA-256 `1c9c53f77e63afa313816b8f3d1ae2ac2459273b0d0e5a26c63bbdc58c7aba8c`. The adapter verifies the complete emitted Base Window implementation against SHA-256 `9cd6435eb582b65deca88afe1ddc8a4d9700f21347acbcf086fc19611cc1c4ba` before applying its launch-policy transform. A changed compiler, adapter policy, or Window body is refused until its rules are inspected and the pins updated.

The supported route requires `BANGS 0`, the pinned Window body, and direct framework imports limited to `AppKit/AppKit.h` and `QuartzCore/QuartzCore.h`. Actual imported module maps must belong to the closure resolved by those two frameworks. Unknown frameworks/modules, GPU/bang output and sidecars, non-Window output, other operating systems/architectures, and C/JS/BendTT/GPU output extensions are rejected. This cache has no `--gpu-build` invocation or Metal compile branch.

Compiler wrappers/scripts, dynamic-loader injection, `CCC_OVERRIDE_OPTIONS`, unresolvable dependencies, relative quoted native includes, source/header linker-option directives, assembly-directed linkage, and volatile compile-time macros are rejected. Header dependence on the transient main C filename is rejected too. Existing uncached routes remain available for unsupported output; the cache does not guess or silently fall back.

The native command is exactly the pinned adapter's CPU command:

```sh
clang -x objective-c -fobjc-arc -fmodules -std=c11 -O3 \
  VERIFIED_TRANSFORMED_C -lpthread -lm -o UNIQUE_NATIVE_OUTPUT
```

The initial Bend emission performs the compiler's normal checks. A retained generation is reused only after its complete source/toolchain policy key and C contents verify. Independent proof checks and integration test execution remain obligations of callers; this tool caches compilation output only.

## Key and dependency discovery

Import discovery reuses the inspected pinned loader rules in `build_native.py`, documented in `docs/BUILD_CACHE.md`. It resolves the entry's complete local transitive Bend graph, executable-relative installed Base, local named/hash package mappings, and all native `.c` foreign effect bodies. Missing dependencies are refused; no hub fetch is cached. The Bend executable contains the native runtime, so its contents cover that runtime dependency.

| Input | Resolution and key |
| --- | --- |
| Bend/native graph and installed Base | Lookup and resolved paths, SHA-256 and size; all native bodies in the graph are conservatively included |
| Compiler and cache policies | Exact Bend bytes/version; `build_native.py`, this cache, and pinned `platform_build.py` contents |
| Original and transformed C | Both SHA-256 values; cached C must verify and reproduce the unchanged adapter transform |
| Clang flags/configuration | Exact Objective-C flags and actual `-###` driver commands, selected driver/config contents, target and sysroot |
| Toolchain | Clang/linker binaries, resolved non-system Mach-O tool dylibs, and complete Clang resource contents |
| Headers/modules | Actual `-M -Xclang -module-file-deps` on transformed C; reported headers, module maps and PCM contents |
| SDK/framework/link inputs | Actual selected SDK settings and `usr/lib`; Objective-C linker trace for the known import closure, including selected framework stubs, reexports, archives, and externally shadowed libraries |
| Platform/environment | Platform/architecture, OS build, uname, working directory, and the SHA-256 of the entire inherited/overridden environment |

Every lookup reruns actual Objective-C dependency and linker probes and hashes the resolved inputs. Framework headers/linker stubs are keyed by their actual selected bytes, not just framework names or SDK version. A private framework/header or Clang-resource change therefore invalidates reuse. The probes build tiny binaries but never execute them. Transient probe object filenames are normalized/excluded; actual external paths and configuration remain keyed.

Environment values are hashed rather than printed because inherited entries can contain secrets. Unrelated environment changes deliberately over-invalidate. Apple's protected dyld shared-cache libraries have no individually accessible disk file; their identity is tied to the recorded OS build/ABI. File-backed toolchain libraries and actual selected SDK link inputs are individually hashed.

Source/compiler/environment policy keys retain checked original and transformed C. Final native keys additionally include both C hashes and the complete discovered dependency manifest. Header-only changes can reuse verified C while rebuilding native output. A valid source-cache hit still reruns the exact Window transform and verifies both C digests.

## Integrity and concurrent publication

Per-source and per-native-key file locks permit one builder for a generation. Source emission, native compilation, binary freezing, and output publication use unique temporary paths. Content manifests and inode/size/time/mode stamps are rediscovered before publication. Changing inputs discard the candidate; stable source changes retry up to three attempts. A source changing from CPU to GPU during compilation is refused before publication and never enters a GPU build branch.

Native compilation copies freshly verified transformed C into its own unique build directory. It does not re-emit mutable Bend sources through the adapter CLI after preflight. This preserves the delegated transform and pinned CPU flags while closing the CPU-to-GPU race and avoiding a duplicate cold emission.

Native manifests, entry executables, and content-addressed artifacts must all pass digest checks before reuse. Corrupted retained C is re-emitted through Bend and the guard; corrupted artifacts/manifests trigger native rebuilding; a damaged output copy is replaced from verified bytes. Publication uses an output lock, a digest-checked sibling temporary file, `fsync`, and atomic replacement. Concurrent different keys may publish to one output, whose last completed generation wins; their returned artifact paths remain distinct and content-addressed.

## Verification and measured limits

```sh
python3 tools/test_platform_cache.py
```

`evidence/platform-cache-selftest.json` records actual small checked Window builds and native executions under the adapter's hidden mode. A real `NSWorkspace` observer checks foreground application sampling, activation notifications, Spaces notifications, child status, and native window state. Tests do not request a visible window or foreground activation.

The suite checks first build/reuse; entry, direct/transitive import, native effect/header, Base, deployment configuration, framework header/module/linker and Clang-resource invalidation; manifest/C/artifact/output corruption; missing inputs and unsupported routes; changed transform policy; moving inputs; and three concurrent CLI callers producing one native build and two verified hits. Two different source keys also publish concurrently to one output and must retain distinct correct artifacts. Shared compiler/SDK/Window files are not mutated: these cases use isolated copies or overlays. The unchanged adapter CLI is independently built and executed, with identical original/transformed C hashes and expected hidden native behavior.

The evidence records first-miss, warm-lookup and unchanged-adapter timings on this machine. Strict dependency hashing/probing has substantial fixed cost, so the tiny fixture can compile directly faster than a warm cache lookup. Its measurements establish correctness and lookup overhead; they do not establish gameplay speed, visible acceptance, or whole-client build savings. Actual client/persistent-client cached execution and end-to-end timing remain integration work.

The stable-source selftest passed **31 checks and 26 actual hidden Window executions** in 256.69 seconds. Its fixture resolved 3,633 dependency records. The measured build phases were:

| Route | Total seconds | Bend emission | Guarded Clang build |
| --- | ---: | ---: | ---: |
| Cache first miss | 9.249 | 0.101 | 0.418 |
| Cache warm hit | 6.768 | 0 | 0 |
| Unchanged direct adapter | 0.613 | Included | Included |

These are one observation per listed route, not a benchmark distribution. Confidence is high in the exercised cache/hidden-launch results and moderate in timing repeatability. The selftest evidence records the exact cache/test policy hashes and confirms the two pre-existing build policies remain unchanged.
