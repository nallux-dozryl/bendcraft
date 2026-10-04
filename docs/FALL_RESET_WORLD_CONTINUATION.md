# FallResetWorld split verification continuation

This is host-only verification preparation for the existing checked reset-ray supplier. No supplier build, native comparison or full harness kernel verdict has run in this continuation. Production remains `src/fall_reset_world.bend` SHA256 `8353ad65484f28b80ae49a3b4191bf98aad5903f6565f6d17f2d64eeec2c7948`; the unchanged test entry remains `tests/fall_reset_world.bend`. This preparation does not establish the saved LocalPlayer consumer's required-ray integration.

`tools/test_fall_reset_world_continuation.py` imports the frozen runner `tools/test_fall_reset_world.py` (`d304fd0e…`) and reuses its request construction, corpus, policy and registry-remap selection, parser, raw comparisons and complete owner checks. It does not call the frozen runner's `main`, `bound`, preparation or reference-generation functions. The original host adoption `c297f08f…`, its 23 archived originals, Java reports, reference bytes and current 58-source closure remain at their original pinned paths. The new history manifest points to these files without duplicating assets or old build payloads.

Independent review `build/review-fall-reset-world/current-admission/admission.json` (`d2e637a4…`) admitted the source/reference files and identified two host blockers: the native builder's three-attempt `InputsChanged` catch and cleanup stopping at the first permission error. The new tool uses the exact retained LocalPlayer constructor-abort strategy: creating `InputsChanged` raises a distinct exception before the retry catch can handle it. Its binding is restored on every exit; a build receipt must report `retries == 0` and `cache_hit == false`. Build output and private cache must initially be absent.

The public modes are mutually exclusive:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_fall_reset_world_continuation.py --prepare
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_fall_reset_world_continuation.py --audit
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_fall_reset_world_continuation.py --build-only
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_fall_reset_world_continuation.py --native-only
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_fall_reset_world_continuation.py --proof-only
```

Preparation reads files and exercises inert objects; audit only reads the sealed files. The execution modes need separately coordinated lead grants. Build-only allows one 600-second builder child and publishes a retained artifact/consumer manifest; it never executes the binary. Native-only requires that exact artifact and all current native dependencies, with no cache or build fallback. Proof-only invokes the unchanged full harness with `--verdict` once, bounded to 60 seconds; any refusal remains separate from a native result. Each process has a separate five-second cleanup deadline. A complete native suite has many independently bounded processes, not one 120-second overall deadline.

The native sequence is the existing full corpus twice: per run, 107 actual completed Java MISS cases (492 visits, 984 ordered reads), 29 checked policy/recovery cases and 14 remapped-registry cases, totaling 150 processes. Hits, interrupted Java clips and other excluded observations remain excluded. The eight-byte endpoints/expansions, ordered duplicate reads, body, clocks, queue, view and canonical Core checks remain the frozen comparisons. Every run uses a fresh remap directory so the frozen `remap` function cannot overwrite an earlier table. Rerun equality includes every registry content fingerprint and every result; only the private run-directory path metadata differs.

Runtime scopes replace only `F.BINARY`, `F.WORK`, `F.ATTEMPT`, `F.SEALED`, `F.execute_process`, `F.checked_seal`, `F.LAST_EXECUTION`, and the builder exception constructor. Original bindings are restored and checked in `finally`. No subprocess or OS module is globally replaced. Inert controls use explicit fake supervisor operations and a scoped builder `_prepare` that refuses before emission; they never accept a mocked game result.

Raw stdout/stderr files are opened exclusively before launch. Every launched PID/group is added immediately to a durable journal; discovered additional groups are also registered. Receipts are written before UTF-8 decoding, parsing or comparison assertions. Cleanup catches and records each group's probe/signal/wait errors, visits later groups, and treats unknown absence as a failure. An unconditional parent sweep runs after semantic errors too. Overall success evidence is published only after that sweep succeeds. A launch failure or empty journal cannot become a successful process result. Existing attempts, artifacts, manifests and evidence are never overwritten; there is no automatic repair or retry.

The scope remains the existing explicit client-player/overworld profile, finite clear interior and admitted four-state world. This supplier's shape/read/owner evidence does not establish general raycasting, fall damage, movement mutation or full LocalPlayer/client fidelity. All preparation controls and counts are verification evidence, not implementation coverage.
