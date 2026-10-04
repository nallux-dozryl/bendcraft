# Generic registry-state actor frames

The new runnable entry is `remote_resource_catalog_client.bend`. It connects to
the existing private renderer transport, requests a catalog frame, loads the
official registry and the checked block-resource profile, and retains the sole
`CW.Assets` owner through native presentation. The legacy remote client entry
remains available. The generic entry has passed source validation. Frozen native
generations 001 and 002 produced no completed C: the first reached the old
progress guard, and the second reached the fixed 600-second total deadline while
compiler work was still advancing. The real consumer build and end-to-end run
remain pending.

## Actual producer and consumer

`GenericBackend.frame` uses the existing renderer lease, exact expected sequence,
renewal and `Scene.ensure` policy. `Session.snapshot` takes the canonical registry
identity already admitted by the saved session and obtains the actual pose-aware
eye through `local_player_runtime.eye`. `Read.snapshot` takes the real `W.State`,
observes `Core.clock` once, and reads every cell in its current region through
`Core.read_block`. It preserves the complete original view, registry and legacy
palette/cache; it neither consults nor replaces that cache. No sampling read
advances simulation. One-time scene initialization retains the existing backend
semantics and is separate from this read-only sampler.

All observed U32 state IDs, including air and states absent from the client's
resource catalog, reach the DTO. Bounds use the current `W.bounds_valid` contract:
each axis is 1..16, at most 4096 cells, with signed coordinates represented as raw
U32 words and x fastest, then y, then z. `W.position` currently selects the
Overworld. Invalid bounds, origin or camera are refused before Core reads;
missing sections retain Core's exact diagnostic.

`GS.Policy` supplies a seed and complete appearances, with a cell override before
a state override before the default. Cell seeds depend on the caller seed and
absolute position, not tick, revision or registry state. The mixer is an explicit
deterministic generic-client policy, **not Minecraft's Java position RNG**.
Weighted variant and multipart tickets are derived from each cell's seed against
the actual loaded blockstate root. Zero weight totals are refused. Repeated states
can retain different seeds and appearances; no state-indexed binding cache
collapses those decisions.

`Frame.frame` in `generic_resource_world_sample_frame.bend` checks the full
registry identity before sample or catalog lookup. It
validates every observed state, then omits only entries explicitly marked
`Invisible` from visible mesh/binding budgets. Unknown or unloaded states and
unsupported renderers retain catalog diagnostics. Each visible instance is
camera-relative and flows through the existing catalog selection, bake, material
binding, world mesh and renderer APIs.

`GenericClient.open_item_table` owns the native window, private `Presenter.Link`
and `CW.Assets`. It uses the actual presenter transport/correlation, command and
menu-intent APIs, hardware-key profiles, menu controller, inventory HUD,
presentation geometry/capture policy and trace writer. A correlated catalog
sample reaches `GenericDraw.draw` → `WRF.draw_catalog` → `CW.draw`, followed by
`Window.frame`. Failure paths close the window, resource owner and lease.

The shared `GS` module now contains the existing `Cell`, `Sample` and `Policy`
types, appearance/seed production and admission. Client-only weighted model
selection and frame binding live in `Frame`; the presenter calls
`Frame.draw_frame`. The shared module's dependency graph fell from 67 to 62
files and has no catalog/resource-owner import. Its three DTO declarations are
byte-identical to frozen client generation 001. The actor's separate legacy
`Backend` → `local_resource_world` → `RF`/`WRF` dependency was then removed by
joining `Backend.World.snapshot` to `local_resource_world_sample`. The original
client-facing module remains available. The pure extraction retains the shared
`V.Sample` type and all 26 common sampler function bodies, with only the
renderer error formatter replaced by identical pure text. Its six actual
palette/cache/alignment/read-owner refusal laws pass the independent kernel;
this proves those stated refusal paths, not rollback after a completed cache
refresh. See `evidence/local_resource_world_sample_kernel.json`.

## Additive wire v1

Existing tags and palette DTOs retain their encoding. The new command is
`[13,width,height]`. The reply is
`[1,7,epoch,sequence,[registry,tick,revision,origin,camera,cells]]`.

`origin` has six raw F64 words; `camera` has five raw F32 words. Each cell is
`[x,y,z,boundary,state,seed,appearance]`. Appearance is
`[tints,light,address,cull,nether,threshold]`, with tints as `[index,color]` pairs.
Address tags are clamp 0/repeat 1; cull tags are back 0/no-cull 1. The default has
no tints, white light `4294967295`, clamp/back, false Nether flag and threshold
128. Explicit tint overrides are supported; no biome tint is invented.

The existing 65536-byte/scalar, depth-8 and value-budget admission remains in
force. Cell and tint limits do not promise that every maximum-length combination
fits a transport message. Decode and encode both validate identity shape, clock
range, finite relative camera/origin, appearance constraints, unique positions
and cell budgets. The transport retains its actor-owned lease/sequence authority.

## Verification and scope

The actual generic entry and its 79-file consumer closure passed the ordinary
source API checker with stable source pins. The complete composition check
covered 7516 declarations after the module split and selected exactly 22 current arbitrary laws: nine
mapping/admission laws, ten actual Core-read/sampler composition laws, and three
session/actor/texture-owner refusal laws. Checked original types and proof bodies
were retained. The independent kernel checked the 2,137,964-byte closure in
0.356822 seconds, with zero exclusions. See
`evidence/generic_resource_world_sample_kernel.json`.

The first reader proof required a structural Nat split; affine consumer owners
required ordinary rather than duplicable proof quantifiers. An intermediate
composition check also encountered a concurrently changing Motion dependency.
Failed attempts remain under `build/generic-resource-world-sample-proof-*` and
in the tool transcript; no failed verdict has been presented as a pass.

The profile currently contains air plus 129 states from 11 useful block families,
using pinned 26.3 resources. Its earlier independent Java geometry/current native
pixel evidence is in `docs/resource_catalog_world.md`; that evidence does not
establish this new wire/window consumer's behavior.

The real native sampler observer passed two runs of 37 observations before the
subsequent module split: 38 sampler successes, 36 refusals and 8,446 observed
cells in total. All 74 observations retained complete Core storage, metadata,
registry identity and all View/cache fields. Direct and full-text wire codecs
were checked separately, including their token, value and byte-budget refusals.
The two runs were identical. These are frozen generation 002 results, with exact
working-source guards passing at execution; post-split native behavior and the
real actor/window join remain separate checks. See
`evidence/generic_resource_world_sample_read_native.json`.

Standalone client generation 001 passed its full source checker, then hit the
90-second no-recorded-progress guard during emission pass 2 after 219.54 seconds.
The process group was reaped and no C or native executable was produced. The
private producer logged only pass boundaries, so this receipt does not prove
that the compiler had stopped doing work. A corrected private producer with
actual function progress and measured memory retention is separate work; no
equivalent retry or original compiler edit was performed.

Fresh client generation 002 used current production sources with
the separately verified private telescope-cache/progress correction and the
existing native platform transform. Nine upstream regression graphs produced
exactly equal C and native expected outputs; the tenth retained its expected
compiler refusal. Its actual full-client emission reached the fixed total
deadline after 600.805701 seconds during ownership pass 5. The process group was
reaped; no completed C, clang run, native executable or window resulted. Sampled
peak RSS was 3,950,903,296 bytes, below the 8 GiB cap. All frozen input bytes
remained stable. The 34,913 genuine work records show functions and counters
advancing; completed pass ownership/hot counts were 2265/449, 2487/688,
2555/702 and 2592/704. The measured remaining blocker is repeated work during
ownership convergence. This result does not prove a stall or a memory-cap
failure. Both failed generations remain intact; a subsequent attempt requires
a substantive correction. See
`evidence/generic_resource_world_sample_client_native_002.json`.

The independent generic runtime helper's recorded preparation admitted the
actual Actor016 artifact, matched its unchanged Wire/GS DTOs and verified saved
degrees project to the same camera radians. Native acceptance now requires an
explicit completed actor generation and binds its WORK/SOURCE/ACTOR together
through the existing boundary owner; this result uses producer017. Its
backend/renderer inputs explicitly pin the official
registry and installed JAR. The inherited 20-second actor startup bound has
been replaced in this new helper by fixed 120-second readiness and 180-second
lifetime bounds using the existing actual process owner. These are adapter
preparations, not an executed generic client test. The complete 128-pixel
Java-geometry/current-CPU oracle, exact 512-cell sample, typed save/cold reload
and unloaded-glass refusal were exercised by the successful generic003 run.

The generation002 work telemetry isolated the actual numeric scanners as the
dominant repeated emitter work. A private scalar-continuation substitution has
now been adopted narrowly in `block_model.int_scan` and
`blockstate_model.scan_number`: each exponent update is computed once, then a
Bool guard invokes the unchanged recursive continuation or returns the exact
old error. Wrapped U32 arithmetic, threshold 100000, all scanner arguments and
all other decoder bytes remain unchanged. Original compiler files and frozen
client001/002 are preserved.

Both focused baseline and candidate native harnesses matched 45 pinned-Java
numeric cases (90 observations). Accepted outputs match the complete existing
projections; rejected inputs match rejection status. Four extra exponent-limit
inputs per variant preserve exact old/new errors, without claiming Java parity
outside the existing bounded parser. Six arbitrary continuation laws passed
ordinary checking; their initial six-root Safe export hit its 60-second cap and
produced no kernel artifact. Whole-parser equivalence is not established.

The same focused harnesses produced 13.04%/18.80% less C for model/blockstate;
scanner-plus-guard emitted lines fell 23.99%/36.48%. Observed emission elapsed
times were 62.382→37.285 seconds and 82.763→51.122 seconds. These are focused
compiler measurements, not full-client or game speed claims. See
`evidence/generic_resource_world_sample_numeric_continuations_adoption.json`.
The fresh generic003 consumer generation emitted complete C in 228.907 seconds
(24,055,884 bytes), reached its ownership fixpoint after seven passes, and
compiled natively in 74.151 seconds. Its 6,959,528-byte renderer has SHA-256
`3346be8b07699db488591935b8e9e502c10a8f1aa437c99543dcb97d4f21ce6a`.
All frozen source/foreign pins remained unchanged. Two host plain-cache routing
failures are retained: Window output and the project AppKit effects require the
existing guarded platform route. The completed C was reused for the corrected
Objective-C compile; the emitter did not rerun. The earlier incomplete002 build
does not supply a comparable full-emission speed baseline.

Actual generic003 plus explicitly admitted Actor017 passed the hidden native
Window/socket consumer. Two correlated FrameCatalog/menu pairs each retained
all 512 raw cells and produced 32,768 total exact 128×128 pixels against the
independent pinned-Java geometry/current-CPU/HUD oracle. Slab and stair geometry
contributed 884 and 616 pixels outside HUD coverage. The full 104-section typed
world, 36 main and 7 equipment slots, status, WG fields and clocks were durably
saved; the 1,712,616-byte complete save matched its independent expectation and
cold reload recovered the exact sample and authority. The separate actual
glass-state 661 fixture stopped with `render: StateNotLoaded:catalog:661`.

All five owned runtime groups were reaped. The native OS observer reported zero
activation and Spaces notifications and unchanged foreground PID. This checks
the actual returned Window-frame CPU image; AppKit drawable readback and visible
OS-input acceptance remain unclaimed. The initial artifact preflight reached
upcoming 018, failed before native launch, and is preserved; explicit generation
selection resolved the intended completed 017 artifact. Public launcher adoption
remains separate. See
`evidence/generic_resource_world_sample_client_native_003.json` and
`evidence/generic_resource_world_sample_client_runtime_001.json`.

The profile is an explicit coverage instrument, not the normal product's
content boundary. The registry-backed demand-loader plan is recorded in
`docs/generic_resource_world_sample_demand_plan.md`, including complete
generation replacement, a single transport owner during cold loading and the
pinned face-UV material-classification requirement.
The new `Demand.initial` and `Demand.collect` source APIs retain the actual
affine registry and committed family inventory, derive missing families through
`Registry.decode`, coalesce observed states/families and produce complete
replacement requests. Startup represents the absence of a catalog explicitly.
Renderer modes and materials require explicit admission; no guessed vanilla
classifier is supplied. These new APIs and their 16 proposed branch/prefix laws
are prepared but remain unchecked and unintegrated. They do not remove the
current runnable entry's static profile yet. See
`docs/generic_resource_world_sample_demand.md`.

Generic model faces are currently retained rather than applying the legacy
three-full-cube neighbor classifier. Biome tint production, full light sampling,
Java position RNG, dimension selection, unsupported/special renderers and full
catalog content remain explicit acceptance gaps. The grass coplanar layer-order
gap remains recorded separately; no Java GPU-raster equivalence is claimed.

Reproduce the pure composition verdict in a fresh directory:

```sh
mkdir build/generic-resource-world-sample-proof-fresh
/opt/homebrew/bin/node --stack-size=4096 --max-old-space-size=6144 --experimental-transform-types tools/generic_resource_world_sample_proof.mjs build/generic-resource-world-sample-proof-fresh
/Users/chuah/.bend/bendtt/e15042434e73aab0/bendtt build/generic-resource-world-sample-proof-fresh/selected.bendtt
```

Use `--client-source-only` with the same tool for the standalone consumer's source
API check. Neither invocation starts a window or compiles a native client.
