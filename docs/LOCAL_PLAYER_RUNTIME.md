# Owned LocalPlayer client facade

`src/local_player_runtime.bend` consumes `local_phase_runtime.State` directly. It
introduces no second live Body, Core, or sine-table owner. The saved session and
scene use this facade; the earlier plain Player client remains a separate path.

The source and focused harness pass ordinary checking. Native behavior and the
full-import mathematical kernel are pending. Prepared expectations reuse eight
unchanged actual 26.3 receiver outcomes; preparation alone does not establish
that this new consumer executes them correctly.

## Public operations

`fresh(world,tables)` initializes neutral local metadata around the supplied
standing adult Body without terrain creation. This is an instrument startup
policy, not a complete vanilla constructor/lifecycle implementation.
`record(state)` returns the same owner with an immutable durable projection.
`record_checked(state)` additionally rejects every root/MH/metadata tail and
validates the complete record, including pose/eye/Body coherence. A failed
checked projection returns the original state and diagnostic result; it does
not overwrite `last_error`. `restore(state,record)` validates atomically and
restores all durable fields. Startup restore clears physical buttons, mouse
accumulation, and the old diagnostic while preserving caller mouse options and
the saved LI previous sampled keys/vector, bob, sprint timer, all degrees,
support, minor flag, fall history, and Entity historical metadata.

`detach(state) -> Engine & Record & Transient` and `attach(engine,record,transient)
-> State` are unconditional lossless owner detours. Transient retains the exact
sine Tables, view palette/region/raw cache, physical controller state/options,
diagnostic, root and MH owned children, and metadata children. Pose's immutable
tail remains inside Record. Generic detours do not silently canonicalize forged
tails. The all-field detour law includes those tails; save/inspect consumers use
the separate checked admission before publishing a head projection.

`query(A,state,operation)` threads a world reader with all runtime fields.
`input(state,bindings,packet)` applies the production atomic packet path and
returns a String result; no simulation tick or LI sampling occurs. `release`
clears physical input and mouse accumulation through the existing controller.
`step(driver,state)` advances one explicit scheduled tick; `advance(~driver,n,
state)` repeats it; `realtime_step` retains the complete canonical paused state.
The typed `Driver{request:PrepareRequest}` permits trusted callers to choose
structural lifecycle/control/environment/budget declarations. The actual saved
client scene fixes `driver()`, and transport requests cannot supply those
declarations or numerical ApplyFacts/fit/clip answers.

## Post-control owned sampling

One explicit tick commits Core's step and Entity commonTick once, then prepares
early real fit reads and LI.controls once. The returned opaque stage stores that
single control decision and its ordered sprint setters. The facade reads its
intent, runs exactly one `support_world.sample_checked` using the stage's sole
world and support cache, and resumes the stored stage. No control, fit, input,
Core step, or commonTick is repeated. Current palette identity is dynamically
checked by the early LCW phase, and the closed provider makes no intervening
registry mutation. Every support/current/below read remains checked.

The fixed default profile uses these raw actually observed post-control values:

| Field | Raw value |
|---|---|
| Walking movement speed F64 | `3fb99999a0000000` (widened 0.1f) |
| Sprinting movement speed F64 | `3fc0a3d710f5c290` |
| Gravity F64 | `3fb47ae147ae147b` |
| Friction and air drag modifiers F64 | `3ff0000000000000` |
| Maximum step F32 | `3f19999a` |
| Jump strength F64 | `3fdae147a0000000` (widened 0.42f) |
| Sneaking speed F64 | `3fd3333333333333` |

Ground coordinates/friction and current/below jump factor come from the owned
support-aware world; they are not constant floor or cached-speed substitutes.
The four admitted identifiers air/stone/dirt/oak_planks each have measured
friction `3f19999a` and jump factor `3f800000`. Unsupported or missing reads
reject. Registry state IDs are dynamically resolved, not hardcoded here.

The ordered setter list stays in X and is validated/replayed as control
evidence. Selecting the default resolved numerical attribute by its final Bool
does not implement AttributeInstance removal/addition or observable intermediate
attribute values. Additional equipment/effects/modifiers are outside this
declared profile. Food20, no flight, normal sprint window7, adult unscaled
standing/crouching, inactive interpolation, dry loaded no-particle lifecycle,
empty actors and clear border interior `[-64,64]^3` are explicit admission
contracts. Query boxes must be admitted; padded scanner cells are still read and
missing/unsupported states reject. The budgets are two early fits, 512 movement
probes, 4096 rotation operations, and three late pose queries.

LI preparation, actual owned world movement/support/minor/history, PT finish,
rotation, and late pose each execute once. Fall reset-ray admission is explicitly
`NotRequired`; a required ray rejects rather than fabricating MISS. Local phase
failures restore the complete direct/post-common anchor, retaining committed
scheduled Core/commonTick work and the sole owners. The facade then stores the
formatted tick diagnostic. Structural tail refusal precedes Core/commonTick.
This facade does not claim unsupported particles, full inherited lifecycle,
general attributes, fluid/flight/equipment motion, or full LocalPlayer tick.

## Pose-authoritative rendering

`eye(state)` uses the coherent cached Pose eye. `snapshot(state,width,height)`
reads that exact F64 position, shares W's checked raw-cell sampler and success
cache, and forms each block coordinate as exact signed cell minus exact cached
eye origin before F32 narrowing. Camera XYZ are zero; yaw/pitch retain the owned
view's renderer projection. The API dimensions are retained for the client
signature and do not change world sampling. No tick, Body shift, fixed1.62 eye,
or post-F32 crouch correction is used.

The terrain cache stores raw signed cells/state/material, keyed by revision,
region and palette. Camera-relative conversion is fresh on every query. A
failed sample retains the prior view/cache. Trusted direct low-level Core
mutations or registry changes can bypass revision and must explicitly call
`W.invalidate_cache`; revision is not a universal mutation detector.

## Focused verification preparation

`tools/test_local_player_runtime.py --prepare` checks the full source/harness and
seals their complete Bend/Base/effect closure, host helpers, table, compiler and
reference. It never builds Java or native output. Heavy actions require the
lead's separate grant: one installed native build capped600s followed by one
120s harness process; only after comparisons pass, one full-import kernel capped
60s. First failures and raw streams are retained under ignored build storage;
public evidence contains compact pinned summaries.

The eight independent actual outcomes are scheduled_shift0..3,
scheduled_jump0..1, scheduled_sprint_jump0, and scheduled_zero0 from the unchanged
`reference/local_phase_runtime.json`. Cases with seeded maximum step0/1 and the
sprint particle service failure are excluded from this default0.6 profile.
Exact comparisons cover Body, support/minor/fall, LI/PT/ECT metadata, sprint,
pose/cached eye, degree state, and separate Core cadence. The focused policies
exercise atomic invalid packets, paused realtime versus explicit stepping,
device-only restore, Data/owned tail detours/refusals, four distinct child Core
owners, structural scheduled refusal, and forged staged header/body/clock
rejection before an observable provider callback. Camera fixtures create actual
checked sections and adjacent stone/dirt cells at origin and ±30,000,000,
compare exact F32 words for standing/crouching eyes and cache hits, and check
missing-section ownership/cache refusal. The session integration harness owns
the actual TCP/MCP/save/reload consumer tests separately.
