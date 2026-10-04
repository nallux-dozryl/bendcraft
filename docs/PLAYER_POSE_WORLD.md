# Owned late player pose phase

`src/player_pose_world.bend` drives the frozen conditional `Player.updatePlayerPose` model against actual checked reads from the sole owned world. It receives authoritative pose/cached-eye Data separately, derives the initial Body from `W.State`, and installs the finished Body only after every pose and world query succeeds. It performs no tick, movement, support update, lifecycle callback, or rendering operation.

Current status: production and the complete harness pass ordinary Bend checking. Two fresh actual Java receiver runs agree exactly. The final installed native generation passed all81 fresh process invocations: 44 admitted actual updates, two scale refusals, 28 rejection/recovery jobs, four palette remaps, and running-clock, nonempty-event and edit/removal-recovery jobs. This covers 80 successful raw pose comparisons, 156 ordered query rows, 3,759 checked reads and 12 first-yield observations including repeated recovery/remap scenes. The build took 244.145012 seconds; comparisons totalled 9.305484 seconds (maximum 0.685088 per process). Root independently replayed every output and argument and verified the compiled closure and supplemental Base/effect dependencies.

The single installed full-import kernel attempt returned exit1 after 22.112368 seconds with the compiler's TypeScript/BendTT mismatch message. It produced no named failed law. Mathematical verification remains unresolved; ordinary checking and native parity do not replace that verdict. No retry, projection, second source verdict, Java refresh, gameplay change or old-output adoption occurred. Every build/comparison/proof group is reaped; no slot is held.

The first native generation's positive-I32 expected-error mismatch and the retained-resume event-seed `PastTick` remain preserved as historical failures. Root independently established the scanner's positive margin policy before approving the one expected-error correction. The second harness generation then changed only event stamp0→1 and matching Applied expected tick0→1. All81 command arrays and actual Java expectations stayed unchanged. The old binary/C/manifests, missing original73 duration receipts, complete pre-correction archives and pregrant reporting bytes remain pinned. The successful final generation used a fresh binary and fresh receipts for every job.

## Public interface and authority

```text
PPW.update_checked(world: W.State, prior_pose: PP.State,
                   request: PPW.Request)
 -> W.State & PP.State & Result<&2,&2,PPW.Error,PPW.Observation>

PPW.Request{context:PP.Context, environment:LCW.Environment,
            fuel:Nat, tail:[]}
PPW.Observation{transition:PP.Transition,
                queries:List<PPW.QueryRecord>, tail:[]}
PPW.QueryRecord{pose:PP.Pose, world:LCW.QueryRecord}
```

`W.State` remains the sole Body/Core/Registry owner. The separate `PP.State{pose,eye_height,tail:[]}` contains no Body. The transition's Body is immutable observation Data; subsequent simulation must use the returned `W.State` Body. There are no Tables and no caller-supplied fit answers. Context flags are explicit authoritative current flags, including current sampled shift; cached crouching and old input keys cannot substitute for them.

The entry rejects nonempty public request tails. Frozen `PP.begin_checked` rejects noncanonical pose tails and checks finite Body fields, exact metadata dimensions, exact cached eye height and exact reapplication AABB, alongside unit-scale adult-client admission. The initial Body comes from the world, so no independent Body can silently disagree with it.

## Query authority and admission

The environment must explicitly declare `KnownEmptyEntityCollisions` and a finite ordered `KnownClearBorderInterior{box}`. The original Body box and **every** actual pose candidate must lie within that declaration. Unknown actors, unresolved border policy, invalid declaration coordinates, and outside candidates reject. These are caller admission declarations; this module has no actor store or dynamic WorldBorder and does not discover those facts from air sections. The actual receiver separately records entity and border checks when reached. Its far-coordinate samples measured clear border results for the specific supplied queries; they do not prove general dynamic-border behavior outside those samples.

Each operation resolves air, stone, dirt and oak-planks IDs from the current owned Registry through frozen `LCW.current_palette`, then requires equality with the View palette. Missing, stale or unsupported palette metadata rejects while returning both nested owners. Registry numeric constants are never used as block identity.

Every pending `PP.Query` uses frozen `LCW.query` with its exact raw F64 box and current Core. A successful query is the sole producer of the internal checked `PP.FitAnswer`. The observation retains the requested pose, query box, Boolean, first yielded fullcube and every ordered Core read. No snapshot/render cache supplies a collision answer.

The shared query scanner admits exactly air and independent full cubes for stone, dirt and oak planks. It validates the exact finite AABB and signed-coordinate margins before scanning, limits each cursor axis to 16 cells, preserves actual cursor order, skips corners before reads, reads and resolves other shell states before shape filtering, and stops at the first actual intersecting fullcube. Missing sections and all unsupported states reject even when a later shell filter would omit that state's shape. Partial or context-dependent shapes remain unsupported. No additional epsilon is invented; the frozen pose query and frozen cursor bounds retain their measured arithmetic.

Fuel counts total issued fit queries. It is decremented once before each world query, including requested duplicate poses. Exhaustion after an earlier successful query rejects the whole operation. The actual initial Swimming fit early return, desired fit, spectator/passenger exemption, and Crouching fallback remain in frozen PP. A failed Crouching fallback selects Swimming without another fit query. Equal selected/current poses retain the existing Body and eye without refresh.

## Commit, rollback and cache

The operation extracts one `G.Engine` and a complete original View, retaining the original pose Data in a recursive private frame. All queries are reads. On any validation, palette, query, budget or checked-pose failure, the returned world reattaches that **entire** original View and returns the original pose state; temporary history never becomes committed state. Success changes only View.body and returns the finished pose/cached-eye Data. Feet, velocity and unrelated Body flags are preserved by the verified PP reapplication path. View yaw/pitch, palette, region and exact raw-block snapshot cache remain unchanged, as do Core clocks, pause/daylight flags, sections, pending commands and events.

The raw-block cache is independent of Body and camera position. Pose changes need no terrain invalidation. Public low-level `Core.apply`, `Core.write_block` and trusted registry mutations may bypass revision: callers must retain the explicit `W.invalidate_cache` requirement after those changes. This bridge does not make revision a universal mutation detector. The harness's fixture edits deliberately invalidate before refreshing render samples.

Cached eye is actual pose metadata, never a body-height ratio. PPW does not revise the existing W render-camera eye projection; a future presenter must consume the returned authoritative PP eye offset explicitly. It also does not repair support caches after a late dimension change or implement scale/age transitions, service callbacks, crawling locomotion, full LocalPlayer.tick, or commonTick.

## Independent reference and prepared checks

`tools/reference_player_pose_world_probe.py` derives a private observer-only copy of the frozen PlayerPose normal receiver. Its only changes are class/output names and additional active-query read metadata: actual state ID/name/ordinal. Official gameplay classes are loaded byte-identically from the pinned 26.3 client JAR; normal constructors and the four frozen external-service mocks remain. All gameplay observers call `super`. The underlying actual `Level.noCollision`, lazy production BlockCollisions iterator and actual `Player.updatePlayerPose` determine the outcomes. Plain versus observed final projections match, two full raw receiver runs match, and projection equality with the frozen PP corpus is checked field-for-field.

The canonical `reference/player_pose_world.json` contains 46 actual contexts: 44 adult unit-scale updates plus two scale contexts retained as admission diagnostics. All reference contexts contain 86 fit queries, 2,233 ordered reads and eight first yields; the 44 admitted updates contain 82 queries, 1,961 reads and all eight yields. Worlds are the actual declared 25-cell stone floor at x,z=-2..2, y=0, air elsewhere, with explicit stone/air edits. The owned harness loads checked air sections needed by observed read positions and applies the same edits. Production entry code creates no terrain.

`tools/test_player_pose_world.py` prepares those actual cases, 28 explicit failure/recovery jobs, running-clock and nonempty-event preservation jobs, low-level edit/removal recovery, and four dynamic palette remaps. Every failure retains exact Body/pose, View/cache, clocks, pending/event rows and lossless section contents, then uses the same returned Engine for a reference-matched recovery. Unknown state injection occurs at a shell coordinate reached only by the later desired query, exercising rollback after an earlier read. Candidate-interior and fuel failures likewise exercise a successful initial query before rejection. The coordinate-limit fixtures establish coherent Bodies before scanner refusal. The remapped palette changes both air and stone numeric IDs.

Native comparisons use complete independently encoded raw-word query rows, including signed zero, all read order and first-shape fields. Section serialization is lossless run-length encoding of all 4,096 values in each owned section, including exact keys and retained trie structure. Large stdout, fixture sets, Java traces and build manifests stay under ignored `build/`; public evidence contains compact pins/counts. Four local laws specify complete rejection restoration, zero-budget Core retention, outside-body owner retention and success View metadata retention; ordinary checking is not an independent kernel verdict.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_pose_world_probe.py --extract
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_pose_world.py --prepare
# Separate lead grants required for these heavy actions:
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_pose_world.py --native
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_pose_world.py --kernel
```

The current `--prepare`, `--native`, `--skip-build` and `--kernel` routes select the explicit second harness generation. Native emission used one fresh installed build with a 600-second whole-process-group cap, retaining actual emitted C and clang invocation. It writes `build/player-pose-world-tests-generation2` and a separate `build/player-pose-world-tests-generation2-artifacts/` tree; the original binary, C, manifest and outputs are untouched. Every one of the 81 comparisons receives a 60-second whole-group cap. Its receipt is persisted before exit-status, parser or comparison assertions, then updated with the exact result; the first failure stops the run. No old output is adopted as a new comparison and no original per-case duration is invented.

After all81 comparisons passed, the separately granted single full-import kernel verdict used a 60-second whole-group cap and returned the mismatch described above. `--skip-build` applies only to this new artifact and rejects changed source/reference/runner/compiler or binary pins. It cannot adopt the old binary. The runner rejects existing new emission or comparison attempts instead of silently retrying. No Java refresh occurs in native or reuse actions.

The historical reviewed resume path was separate from `--skip-build`. Original runner/preparation/handoff and build artifacts are archived byte-identically. The new runner checks every original function's AST, permits only the positive-margin expected error correction, checks unchanged global values and explicit CLI additions, and compares every original fixture/command against the archived prepared list. Every compiled dependency except the explicitly adopted orchestration runner must match the original manifest. Artifact adoption also checks binary, C, compiler, clang, wrapper, invocation file and all retained raw streams. The original 73 per-case durations were not persisted before the terminal assertion and remain recorded as absent.

```sh
# Offline preparation only; executes no binary/compiler/Java/proof:
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_pose_world.py --prepare-resume
# Historical granted run, now stopped at job75; not a current retry command:
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_pose_world.py --resume
```

`--resume` revalidates the 73 retained streams before launching the eight pending processes, each capped at 60 seconds. It persists each new execution receipt before any parser, status or comparison assertion, then stops on the first failure. It cannot rebuild, re-extract the oracle, rerun a completed process, or resume an already attempted execution silently. That generation stopped at event setup and never reached complete parity or a kernel run. Its historical action functions remain preserved, while generation checks reject the now changed harness/runner before reuse.


The complete pre-correction generation is preserved byte-identically under ignored `build/player-pose-world-generation2-prior/`: 203 files, including current and original harness/runner/preparation/adoption/handoffs, all old raw results, the native binary and C, build/invocation receipts and both failures. The archive manifest pins each original-to-copy mapping. Second-generation preflight checked every archived file, preserved all original artifacts, and permitted only the harness stamp and runner among the 33 compiled-closure pins. Its AST check preserves every pre-existing runner function except the one `retained()` event literal, and preserves original imports/globals. The eight added functions provide separated paths, unchanged job construction, archive/AST/data guards, capped receipt-persisting execution, preparation, read-only clang capture, fresh native comparison and the conditional full-import proof route. `evidence/player-pose-world-generation2-preparation.json` and `-generation2-handoff.json` seal the proposal; neither is a native/proof verdict.


The final native manifest pins installed Bend2.0.35, actual `/usr/bin/clang`, the capture wrapper, actual command rows and the 18,639,584-byte emitted C file. The actual flags are `-std=c11 -O3`, `-lpthread`, `-lm` and the explicit output path. Clang command seals use canonical UTF-8 JSON with `ensure_ascii=False`, sorted keys, compact separators and no final newline. Beyond the runner's historical 33-file closure, root's source graph pins 58 resolved Base/effect/Bend entries; these were rechecked before and after native comparisons and the sole kernel attempt. Broad unrelated Python helper snapshots remain informational.

`evidence/player-pose-world-native.json` records final native PASS. `-kernel.json` and `-kernel-release.json` record the failed installed kernel invocation and unresolved mathematical verdict. `-generation2-release.json` pins all native group cleanup and dependency checks. `-final-handoff.json` seals the final source/harness/runner/oracle/document/evidence generation. Large raw streams, every per-process execution receipt, exact section/query output, C, binary and full source-graph/archive mappings remain under ignored `build/`. Documentation reporting changes do not alter the frozen production, harness, runner, reference or compiled generation.
