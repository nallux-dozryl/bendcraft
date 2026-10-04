# Generic registry-state actor frames

The new runnable entry is `remote_resource_catalog_client.bend`. It connects to
the existing private renderer transport, requests a catalog frame, loads the
official registry and the checked block-resource profile, and retains the sole
`CW.Assets` owner through native presentation. The legacy remote client entry
remains available. The generic entry has passed source validation. Its first
frozen native emission terminated at the producer's progress guard before C was
produced; the real consumer build and end-to-end run remain pending.

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

Fresh client generation 002 is prepared from current production sources with
the separately verified private telescope-cache/progress correction and the
existing native platform transform. Nine upstream regression graphs produced
exactly equal C and native expected outputs; the tenth retained its expected
compiler refusal. The correction's full generic-client behavior remains
unmeasured until emission and the real actor/window run finish. Preparation
starts no compiler or native process and retains generation 001 unchanged.

The profile is an explicit coverage instrument, not the normal product's
content boundary. The registry-backed demand-loader plan is recorded in
`docs/generic_resource_world_sample_demand_plan.md`, including complete
generation replacement, a single transport owner during cold loading and the
pinned face-UV material-classification requirement.

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
