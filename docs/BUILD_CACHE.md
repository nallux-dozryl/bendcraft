# Ordinary native compilation cache

`tools/build_native.py` caches the **checked output of the pinned Bend native CLI**. It changes compilation reuse only. It implements no game behavior, skips no integration test, and does not replace independent BendTT proof checks.

```sh
python3 tools/build_native.py build server.bend -o build/server --report build/server-build.json
```

```python
from tools.build_native import ensure_native

build = ensure_native("server.bend", "build/server")
# Use the key-specific artifact when other callers may publish to the same output.
subprocess.run([build["artifact"]], check=True)
```

The stable API is:

```python
ensure_native(entry, output, *, bend=None, cache_dir=None, env=None, force=False) -> dict
```

`entry`, `output`, `bend`, and `cache_dir` accept strings or `Path` objects. The default Bend is `$BEND`, a Bend found on `$PATH`, or `~/.bend/bin/bend`. The default cache is `build/native-cache`. `env` overrides inherited build environment entries. `force=True` rebuilds the native executable with the same validation; it does not bypass route or dependency checks.

The returned dictionary includes `path` (the atomic convenience copy), `artifact` (the binary content-addressed executable), `cache_key`, `cache_hit`, `binary_sha256`, `binary_bytes`, `emitted_c_sha256`, `dependencies`, `compiler`, `identity`, `retries`, `output_replaced`, and `timings`. `timings.emission_seconds` measures the Bend C-emission command when it was needed; `native_seconds` measures the ordinary Bend native build command. `total_seconds` also includes content hashing, dependency resolution, stability checks and publication. A normal hit reports zero emission and native-build time.

`--report` writes that metadata as atomic JSON. Normal CLI output prints a smaller result. `--cache-dir`, `--bend` and `--force` mirror the API. Both `build ENTRY -o OUTPUT` and `ENTRY -o OUTPUT` are accepted. Exceptions `CacheUnavailable`, `BuildFailed`, and `InputsChanged` identify unsupported/unresolved dependencies, actual checker/compiler failures, and repeatedly moving inputs. CLI failures return nonzero and print the diagnostic; they do not publish an executable from an unverified generation.

## Key and dependency discovery

The rules were read from the pinned source at `../bend/bend2/bend.ts` (`BEND_DIR`, `book_file`, `name_hash`, `book_load`, foreign `parse_def`), `../bend/bend2/main.ts` (`book_read`, `cli_emit`, `cc_find`, `cli_build`), and `../bend/bend2/comp.ts` (`effect_srcs`, embedded C runtime). Compiler revision: `79df8d9c40722ee9507a1e253f283b51025f9d6c`. The installed executable is `bend 2.0.35`, SHA-256 `99b3de8f6c5643d245bed839df2c28d1bb12efd41bb221154d25c15695b72e8e`.

The installed compiler resolves Base as `bend2/base.bend` relative to the real executable, reads a leading module-import block recursively, and reads reachable native foreign `.c` effect files into emitted C. JavaScript effect bodies are not read by the native emitter. The cache conservatively hashes **all** `.c` foreign imports in the complete Bend graph, including unused Base effects. Its own Python policy file is keyed as well.

| Input | How it is keyed |
| --- | --- |
| Entry and every transitive Bend import | Resolved and lookup paths, SHA-256 and byte size; import cycles/missing files fail closed |
| Named/hash package imports | Existing local package-name mapping and recursively resolved local source files; missing mappings/files are never fetched by the cache |
| Installed Base and native effects | Executable-relative Base and every `.c` foreign body in the graph |
| Bend checker/emitter/runtime | Executable contents and exact reported version; the native runtime is embedded in this executable |
| Clang and native flags | Bend's actual first supported selection among `$CC`, `clang`, and numbered Clangs; executable hashes, version, actual `-###` driver commands, `-std=c11 -O3`, `-lpthread -lm` |
| Clang/linker content | Selected tools, non-system Mach-O dylib dependencies resolved through their load commands, complete Clang resource directory |
| SDK/link content | Actual driver sysroots, SDK settings, complete SDK `usr/lib`, and additional libraries selected by a tiny actual linker trace probe |
| Native/system headers | Clang `-M` applied to retained emitted C on every lookup; all reported header contents are hashed |
| Platform/configuration | Platform, architecture, OS build, uname, working directory, driver-disclosed configuration files and the SHA-256 of the entire inherited/overridden environment |

Environment values are hashed rather than included in reports. Recording the entire environment deliberately over-invalidates when an unrelated variable changes. Content keys exclude file timestamps; timestamps/inodes/modes are additionally compared while building to detect changing inputs, including a change-and-restore during compilation. The driver's random temporary object filename is normalized; target, SDK, linker, configuration and user paths are retained.

macOS libraries residing only in Apple's protected dyld shared cache have no individual disk file to hash. Their identity is tied to the recorded OS build and ABI. Installed toolchain dylibs, such as the linker's `@rpath/libtapi.dylib` and `libLTO.dylib`, are hashed as files.

An initial miss emits C through Bend and then invokes the ordinary native CLI. That extra first-miss emission enables subsequent lookups to rediscover header resolution without running Bend's emitter. Header-only changes reuse valid emitted C but rebuild the native executable. A new source/compiler/configuration key emits C again. Native builds preserve the compiler's normal checker and failure behavior.

## Integrity, atomicity and concurrency

The local cache has separate source, native-entry and content-addressed binary directories. Cached source and executables are verified against their recorded SHA-256 before use. A corrupted artifact or mismatched native manifest causes a rebuild; a corrupted output copy is replaced from a verified artifact. Corrupt retained C is re-emitted before any native lookup.

Per-key OS file locks permit one builder for a key. Builds use unique temporary paths. Input content and file stamps are rediscovered before publication; a moving generation is discarded and retried up to three attempts. Source emission is checked before it enters the source cache, preventing an input change during emission from poisoning a future restored-input hit. Directory replacement publishes only complete cache entries. Output publication uses a unique sibling temporary file, `fsync`, a digest check and atomic replacement under a separate output lock.

Concurrent different keys may target one convenience output path: the last completed publication wins, and the path always holds a complete generation. Each result's `artifact` points to its own binary digest, allowing the caller to execute its requested generation independently of that output race. No cache garbage collection is performed by this tool. Remove unused caches only when callers no longer need their artifact paths.

## Deliberate supported boundary

This implementation verifies the pinned Apple Silicon Bend executable and ordinary macOS CPU C output. A changed/unrecognized Bend executable is rejected until its loader/build rules are inspected and the policy is updated. This is a fail-closed compatibility boundary, rather than reuse under guessed compiler behavior.

GPU/bang output, Objective-C/framework output, and the macOS Window transform are outside this cache. Window builds continue through the separately guarded `tools/platform_build.py`; the cache never substitutes an untransformed window binary. X11/ALSA linkage and Linux library/loader resolution require separately verified policies. Output extensions selecting C, JS or BendTT are rejected. Output paths must not alias a dependency or be symlinks.

Unresolved native includes, missing imports/headers, relative quoted native includes, compiler scripts/wrappers, dynamic-loader injection, `CCC_OVERRIDE_OPTIONS`, source-directed linker pragmas and volatile compile-time macros are rejected. Relative quoted includes would resolve against the compiler's generated C directory, rather than the foreign effect's source directory; the cache does not guess this path. Ordinary uncached Bend remains available for a build route the cache cannot resolve.

## Verification and measured limits

Run:

```sh
python3 tools/test_build_native.py
```

The test creates isolated Base/effect and Clang-resource installations, leaving the shared installations unchanged. It builds and executes actual native fixtures with independent expected output. Evidence is `evidence/build-cache-selftest.json`; it records entry/direct/transitive/native/header/Base/configuration invalidation, corruption rejection/repair, locally resolved package imports, missing dependencies, route guards, changing inputs, and concurrent callers. Four simultaneous CLI processes must yield exactly one native build and three verified hits. Two different keys sharing one output must retain distinct correct artifacts.

This is a strict content cache, so dependency hashing and discovery have a fixed cost. A tiny fixture can compile directly faster than a cache lookup. The measured fixture timings are in the evidence; they establish cache behavior and overhead, not a whole-game performance result. Actual server/MCP execution equivalence and end-to-end build measurements belong to the integration run. No proof or gameplay-parity conclusion follows from a cached build.
