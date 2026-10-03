# Client build phase profile

The current generic host adds a bounded cost in this comparison: **48.67 s versus 43.06 s** for the old concrete entry, using identical current dependencies. Its emitted C is **3.15% larger**, with **44 additional worker IDs and one additional explicit C function definition**. These measurements do not support attributing the earlier 136.159 s loaded build to a large template explosion in the current source.

The persistent entry has a materially larger graph: **36.56% more emitted C bytes than the generic fixture client**, 1,055 additional worker IDs and 188 additional explicit C function definitions. Its one observed build took **116.30 s**, with other compiler jobs active. Both its raw and transformed C match the earlier **250.075 s** persistent integration build byte for byte. Changed generated code therefore does not explain that timing gap.

Confidence is **high** in the stable-source comparison, generated graph counts, successful compilation, and byte-identical persistent C; **moderate** in the approximate 13% generic build overhead as a repeatable rate. Each variant was measured once, and later compiler work overlapped portions of the run. No fully uncontended persistent timing was obtained.

## Measurements

Times below are the child command's `/usr/bin/time -lp` real seconds. The JSON also records orchestration wall time, which includes sampling/polling overhead, user/system CPU time, maximum resident size, phase logs and process observations. Build total excludes the extra diagnostic checking run.

| Variant | Check + promise audit | C emission, including normal checking | Clang | Build total | Raw C bytes | Explicit C definitions | Native `spin_` helpers | Worker IDs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Concrete entry from `8031ee4` | 2.70 s | 30.27 s | 12.79 s | 43.06 s | 6,899,484 | 916 | 656 | 2,338 |
| Current generic client | 2.73 s | 33.59 s | 15.08 s | 48.67 s | 7,117,092 | 917 | 657 | 2,382 |
| Current persistent client | 4.13 s | 88.49 s | 27.81 s | 116.30 s | 9,719,390 | 1,105 | 819 | 3,437 |

Emission is the largest phase in each observation: roughly 69–76% of the ordinary build total. It includes the compiler's normal loader/checker; the separate checking run suggests that most of the emission command's elapsed cost lies after checking. Subtracting the checking run is only an estimate, because `--check-only` also performs a promise-graph audit and the phases were separate processes.

Generic emission user CPU increased from 25.75 to 27.02 s; Clang user CPU increased from 12.28 to 14.72 s. The emitter's final output grows by 217,608 bytes and one native helper. This is a real but modest code-generation cost, rather than a multiplication of all movement/render kernels across many host instances.

Persistent emission used 37.29 user + 40.98 system CPU seconds, versus 88.49 real seconds. Persistent Clang used 24.83 user + 1.61 system CPU seconds, versus 27.81 real seconds. The initial quiet wait was capped at 60 seconds; the block-model native compiler was still active when it expired. Block-model, resource-JSON and mesh module checking/building were observed during this variant. Mesh verdict/native jobs also overlapped portions of the earlier concrete/generic observations. This profile records those conditions and does not extrapolate a precise uncontended persistent build time.

The generic C contains one host-loop specialization, `SRC_CLIENT_HOST_LOOP_0`. Persistent C contains one, `SRC_CLIENT_HOST_LOOP_1`. The persistent entry's import of the fixture client for options does **not** cause both host-loop variants to be emitted. Its extra worker families include persistence dispatch, load, and world-codec snapshots, consistent with its larger save-owning actor/state graph.

Function-definition counts use a reproducible scan of explicit C signatures. Worker segments are counted separately from `#define FID_...` declarations, since the compiler's worker dispatch macros are not separate explicit C function signatures. Raw C includes conditional runtime/device sections, so these are emitted-source metrics rather than machine-code function counts.

## Frozen source and build procedure

`tools/profile_client_build.py` created an isolated import tree under `build/client-build-profile/input`. The concrete entry is exactly `git show 8031ee4:minecraft/client.bend`, with current dependencies. Current generic and persistent entries use their exact checkpointed contents. Relative imports retain the same layout; production sources are untouched. The installed Base/native effects were also fingerprinted. No original or staged dependency changed between snapshot and completion.

Key source hashes:

| File | SHA-256 |
| --- | --- |
| `client.bend` | `9dfca72a2a5e2922a6d54aadcdfec02086f33087947f92f15c924ab2ad3c501b` |
| `src/client_host.bend` | `9af145e28d5a1dca2b6b4124bb6e06fc75aa905871447b65ce0997803cc3dacd` |
| `src/client_world.bend` | `05040abf35b2b9ceaf87fed5c48f8d074d211750a59ab00fa6ff08e60a9ea5d7` |
| `persistent_client.bend` | `7413d455b4a21e402733d14a0a8dae559ffec8de2c0aba8edef362697bed7c43` |

The compiler is the pinned `bend 2.0.35`, executable SHA-256 `99b3de8f6c5643d245bed839df2c28d1bb12efd41bb221154d25c15695b72e8e`. The CLI and source `../bend/bend2/main.ts` were inspected: there is no dedicated Bend phase-profiler flag. The tool uses the real `--check-only`, C-output and native Clang routes. Local Clang help advertises `-ftime-trace=<value>`; the tool supports it as an opt-in, but these observations use the exact production Clang flags without profiling instrumentation.

The current `tools/platform_build.py` transformation was reused unchanged, with its exact compiler/window guards. Clang received `-x objective-c -fobjc-arc -fmodules -std=c11 -O3`, the transformed C, `-lpthread -lm`, and the native output. All three variants emitted `BANGS 0`; no GPU build or main/window execution occurred.

`--check-only` returns a failure after normal checking when the graph contains existing unsafe/foreign promises. The profile preserves that real diagnostic, rather than relabeling it a proof pass. Successful C emission/native compilation confirm ordinary compiler acceptance. This work does not establish an independent BendTT theorem or rerun gameplay integration tests.

Persistent raw C SHA-256 is `9e6dfd3c2b8e8e108fef9d596a99dc0ae085354dd1deae960971f89e5fedff2d`; transformed C is `f5461ca433b075e682942ada9bedc4ffee873a079f3beb4fddf0079db535b33e`. Both equal the hashes in `evidence/persistent-client-integration.json`. That integration already recorded actual CPU/native behavior; this task profiles compilation only.

## Rejected candidate and recommended contract

A bounded candidate kept `~State` but replaced the templated `~driver` record with a shared runtime `+driver` record. The actual checker rejected it at `move_control`: expected `Data`, observed `Type`, because `+driver` may be used many times.

This is required by the language contract. The Bend guide states that closures are affine and can be called at most once; top-level definitions can be called freely. Templates accept closed syntax, substitute it at compile time, and permit repeated calls. `Driver<State>` contains function values and is `Type`. Making it reusable would need a different checked representation, rather than changing one quantity marker. No cast, `@unsafe` workaround, or ownership relaxation was attempted. The failed candidate and full diagnostic are retained in the evidence.

Keep the checkpointed `~State`/closed `~Driver` interface. It selects the exact typed snapshot/move/look callbacks and preserves the sole actor's owned State. A roughly 13% observed cold-build increment is acceptable for the shared host contract; this profile gives no reason to duplicate its implementation or alter simulation semantics.

The larger practical efficiency opportunity is a **separately verified Window compilation cache** for repeated integrations. The existing ordinary native cache intentionally rejects this route. Extending it is feasible, but requires additional key/dependency rules: exact `platform_build.py` transformation and guards, raw and transformed C digests, Objective-C/module flags, module maps and current framework/header closure, actual framework linker inputs, SDK/toolchain identity, and any GPU sidecar if a future entry has bangs. It must cache the transformed executable, preserve the guarded hidden/human launch policy, verify artifact digests, and retain all proof/integration obligations. It should not merely remove the current Window rejection.

Such an extension could avoid redoing the measured 48.67 s generic or 116.30 s loaded persistent build on unchanged inputs, minus its own dependency verification overhead. No Window-cache hit cost or speedup was measured here, and no cache/platform policy was changed.

## Reproduction and evidence

For a fresh bounded profile:

```sh
python3 tools/profile_client_build.py --output build/client-profile-new --report evidence/client-build-profile-new.json
```

The tool refuses to overwrite existing phase measurements. `--resume --variants persistent` adds the persistent variant to an existing verified snapshot without repeating concrete/generic. `--summarize-only` refreshes source metrics and comparisons from retained files without compiling. The original run tested the rejected runtime candidate; its checker diagnostic was recovered on the resumed run. Tool hashes for the original measurements, resumed persistent measurement and final analysis are recorded separately.

Evidence: `evidence/client-build-profile.json`. Raw C, transformed C, binaries and full phase logs remain under the ignored build directory. There were no production source/compiler/runtime changes, no skipped checks, and no commits.
