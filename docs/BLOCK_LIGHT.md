# Block light: production API and verification boundary

`src/block_light.bend` implements a resident block-light field and incremental
propagation in Bend. It accepts arbitrary catalog state IDs and properties;
Python only extracts reference observations and orchestrates comparisons.
The authoritative Core and resource-frame integration belongs to their owner.
Those existing files are unchanged by this lane.

## Full pinned registry providers

`src/block_light_registry.bend` supplies the actual vanilla 26.3 state properties
and effective facing shapes for every **35,723** registered state. Its immutable
`BR.Catalog` is `Data`, so the existing `BL`/`BW` provider callbacks accept it
directly. This replaces the earlier 20/21-state receiver providers as production
input; neither their selected blocks nor their tested domains define a product
limit. There are 55 distinct effective face shapes and 18,757 contiguous state
ranges in the authenticated input. Those observed counts are data, not source
capacities: the decoder and maps use the loaded dimensions.

```text
BLR.load(identity:String, state_count:U32, max_bytes:Nat, path:String)
  -> IO<Result<&2,&2,BLR.Error,BR.Catalog>>
BR.properties(catalog:BR.Catalog, state:U32)
  -> Maybe<&2,BL.Descriptor>
BR.occludes(catalog:BR.Catalog, source:BL.Descriptor, target:BL.Descriptor,
            direction:BL.Direction) -> Bool
BR.occlusion(catalog:BR.Catalog, source_state:U32, target_state:U32,
             direction:BL.Direction) -> Result<&2,&2,BR.Error,Bool>
```

Use `reference/block_light_registry.tsv` and pass the identity and count from
the actual bound registry. `BLR.load` closes its real file owner on success,
read failure and over-budget input; checks the pinned SHA-256; decodes UTF-8;
and validates version, registry binding, contiguous complete state coverage,
property ranges, every face reference, matrix row indices/widths and unused
padding bits. `max_bytes` is caller loading policy; the current file is 522,187
bytes and the native check uses 1 MiB. File reads use the existing native U32
length API. `BLR.parse` provides the same authenticated path for existing byte
owners. The lower-level `BRD.decode` is a schema decoder, not an authentication
replacement. A changed or modded registry needs a matching provider through the
existing callback interface; this pinned loader refuses a mismatched binding.

Wire `BW.load_resume(~BR.Catalog,~BR.properties,~enabled,catalog,...)` and
`BW.advance(~BR.Catalog,~BR.occludes,catalog,...)`, or put the catalog into an
immutable consumer context with closed forwarding definitions. The `enabled`
provider still implements the actor's section lighting policy. The world and
field remain the single `BW.State` owner; loading this immutable catalog does
not create a second world. `BR.properties` returns `Some` for known air state 0
and `None` for an absent/out-of-domain descriptor. World residency continues to
come from Core and the bridge. `BR.occlusion` reports missing state/face/word
data explicitly. The Bool callback fails closed on unavailable data; the
bridge's property preflight already refuses unknown registry descriptors.

The installed pinned Java class observations settle the context dependency:
`BlockStateBase.getLightEmission` and `getLightDampening` read cached scalar
fields; `getFaceOcclusionShape(Direction)` reads a cached direction entry.
`initCache` constructs those entries from `Block.getOcclusionShape(BlockState)`
without a world or position argument. `LightEngine.getOcclusionShape` supplies
the cached face only when `canOcclude && useShapeForLightOcclusion`; otherwise it
supplies the empty shape. `LightEngine.shapeOccludes` unions the source's face
and the target's **opposite** face using actual `Shapes.faceShapeOccludes`.
The provider records precisely those effective shapes, rather than reusing
render, outline or collision geometry. All 199 states of dynamic-shape blocks
are included; this establishes cached block-light behavior, not context
independence of those other shape APIs. Neighbor-dependent state properties
such as connection/facing values must still arrive as the authoritative current
Core state IDs. Their gameplay update rules are outside this provider.

`python3 tools/reference_block_light_registry.py` observed every state, all
3,025 unique face pairs, and checked the interned representative's union
behavior against each actual state-face object (11,788,590 checks). It binds
the installed classpath and official class hashes in
`reference/block_light_registry.json`. Python only compresses the observations;
the decoder, table lookup and runtime edge composition are Bend.

`python3 tools/test_block_light_registry.py` checks the actual authenticated
native loader, all 35,723 emission/dampening/six-face rows, all 3,025 matrix
pairs, 214,338 directed edge compositions, and 23 rejection/unknown/read guards.
The independent kernel checks 11 implementation-connected laws: out-of-domain
descriptors/faces, missing entries, source-error priority, conservative failure,
unsigned bit 31 and next-word bit 32, truncated rows, invalid range admission,
canonical numbers, and rejecting unauthenticated input before decoding. They
do not prove the Java table contents or propagation convergence. The native
check took 2.05 s and peaked at 43,843,584 bytes RSS, including file loading,
hashing, every provider query and output; this is a resource/real-file check,
not a long-session leak bound. Evidence is
`evidence/block-light-registry-reference.json` and
`evidence/block-light-registry-provider.json`. No unchanged settled propagation
phases were rerun. Actor/frame adoption, sky light and rendered brightness
remain separate lead-owned integration work.

## Actual Core bridge

`src/block_light_world.bend` joins the **actual** `Core.World` and `BL.State`
in `BW.State{world,light,loading}`. It is ready for the authoritative actor and
resource-frame owner to adopt; their entry points have not been edited here.
It calls Core admission, validation, reads, mutation application and event
completion, plus real `Section.snapshot`. There is no secondary world or host
lighting implementation. A frame or actor consumer transfers its Core owner
into `BW.begin(world)` once and retains the joined owner thereafter.

The three supplied providers are closed Bend definitions over immutable data:

```text
properties: Context -> U32 -> Maybe<&2,BL.Descriptor>
enabled: Context -> Core.Position -> Bool
occludes: Context -> BL.Descriptor -> BL.Descriptor -> BL.Direction -> Bool
```

`properties` must return the requested raw state ID and both light properties
within 0..15. `None` yields `MissingDescriptor`; a different ID or invalid level
yields `InvalidDescriptor`. `enabled` receives a normalized **section origin**;
disabled sections use effective emission zero but retain their real dampening.
`occludes` has the exact directional shape contract described below. The full
`BR` provider above supplies these pinned properties independently of the
render catalog; this adapter does not infer them from collision geometry,
render models or a small block list.

| Bridge operation | Consumer contract |
| --- | --- |
| `BW.begin(world)` | Preserve the actual world and enumerate its owned section keys. Start an empty light field and resumable bootstrap cursor. No fixed region, section count, height or block list is assumed. |
| `BW.load_resume(~Context,~properties,~enabled,context,budget,state)` | Return `State & Result<Error,Unit>`. Each section acquisition and each cell publication consumes one unit. Acquisition copies 4096 scalar IDs with `Section.snapshot`, returning the original array and exact map/bucket order. Every cell, including air, is published. Missing properties stop at that cell and retain the cursor for retry. |
| `BW.progress(state)` | Return the owner with `Loading`, `Propagating{pending}`, or `Settled`. A successful load call may still leave loading or propagation work. |
| `BW.apply(~Context,~properties,~enabled,context,state,mutation)` | Authorized low-level Core application with registry/catalog and existence preflight. Block edits publish their descriptor only after real Core acceptance; section creation publishes all 4096 fill cells. A refused operation retains both owners. Bootstrap refuses mutations. It does not perform permission admission or increment the revision. |
| `BW.apply_finished(stamp,apply_result)` | Complete a successful immediate application through `Core.finish`, incrementing revision and recording `Applied`. Refused immediate applications retain both states and return the error. |
| `BW.admit(~Context,~properties,~enabled,context,state,cap,stamp,mutation)` | Preserve Core's developer capability, future tick, queue bound and registry validation priority; preflight descriptors, then call actual `Core.admit`. May queue during bootstrap. |
| `BW.step(~Context,~properties,~enabled,context,state)` | Partition actual Core pending actions, preflight the entire due descriptor batch before changing the clock, then call actual `Core.apply` and `Core.finish` in Core order. Successes update light; Core refusals record `Rejected` and leave light unchanged. Missing catalog data retains the complete old tick, pending batch and both owners for retry. Bootstrap refuses a tick. |
| `BW.realtime_step(...)` | Preserve Core's paused no-op behavior; otherwise call the bridge tick seam. The consumer must use this seam instead of bypassing it with `Core.step`. |
| `BW.advance(~Context,~occludes,context,budget,state)` | Bounded propagation over the joined owner. Bootstrap does not propagate an incomplete domain. |
| `BW.sample_batch(positions,state)` | Return `State & Result<Error,FrameSamples>`. Only a completed bootstrap and `BL.Stable` can produce a frame. Each observation reads the actual current Core array and light field, with the actual Core clock/revision. Missing world plus missing field yields explicit `None/None`; only one resident owner yields `ResidencyMismatch`. Pending fields return `LightPending` without reads. |

The saved 104-section world follows the same path: pass its decoded real Core
owner to `begin`, resume its enumerated section arrays, then advance until
`Settled`. Bootstrap is a loading operation, not a simulation tick; it preserves
tick, time, revision, pending actions and event history. One acquisition has a
fixed 4096-scalar snapshot cost, so the budget is work units rather than a hard
microsecond guarantee. An accepted section creation also publishes 4096 cells
in that call. Map/FIFO memory and initialization latency require native checks;
this is not compact vanilla nibble storage.

Bootstrap seeds each resident level at zero and schedules only effective
emitters plus their six neighbors. `begin` starts a new field and loading
forbids edits/propagation, so nonemitting cells cannot have an incoming positive
level during initialization. Processing an emitter schedules changed consumers
through the existing propagation function. A fully nonemitting saved world
therefore becomes settled as soon as loading finishes. Accepted edits and
section creation retain their incremental notifications, and unknown positions
remain absent. This avoids notifying every initially dark cell and its neighbors
while initializing the current 425,984-cell world.

Core currently has no section-unload mutation. The bridge does not invent an
eviction permission policy or silently keep a stale sidecar after replacement.
A replaced/persisted Core owner starts a new bootstrap with `begin`; absent
sections remain unknown and stop propagation. External direct Core edits,
catalog shape changes or lighting-enablement changes require republishing or
rebootstrap before settled sampling. The actor owner must retain this joined
state across frames and route accepted mutations through this API. Renderer
brightness, sky light, chunk loading policy and actor/frame entry adoption
remain separate integration work.

`src/block_light_world_laws.bend` and `src/block_light_world_proof.bend` prove
eleven contracts against this actual adapter: zero-load owner retention,
bootstrap edit/tick/frame refusal, failed preflight retention, pending-frame
refusal, daylight preserving the whole block-light owner, explicit unknowns,
rejection of a field with no corresponding world cell, nonemitting bootstrap
preserving queued work, and zero air neighbors supplying no light. The independent
kernel verifies them; they do not prove world-scale performance or convergence.

The initial bridge checkpoint `6963fcd` passed 28 retained Java phases and 1,594
actual Core-ID/light sample pairs through `tools/test_block_light_world.py`.
Its pinned source receipt is `evidence/block-light-world-native.json`; those
unchanged propagation cases were not replayed for the bootstrap repair.
`python3 tools/test_block_light_world_saved.py` checks the current initializer
against the actual saved 104-section world. It losslessly supplies all 425,984
saved IDs to real Bend-owned Section arrays, checks section/cell counts and
checksums plus tick/time/revision retention, verifies resident-cell count and
settled sampling, and applies/removes a source through actual Core edits.
The test also bootstraps a preexisting glowstone source behind complementary
slabs against 25 retained Java-observed levels, checks disabled emission and
unknown boundaries, and independently checks all 11 bridge laws. A narrow
installed-JAR catalog query added dirt state 10 and 2,646 directed shape
observations with **zero** settled-phase reruns; its pinned result is
`reference/block_light_world_saved.json`.

The measured current `begin` plus resumable loading took 5,555 ms. The complete
native receiver, including extra initialization/edit checks and array summaries,
took 9.9695 s and peaked at 443,318,272 bytes RSS. These measurements are in
`evidence/block-light-world-saved.json`. They establish the saved-world loading
seam, not a frame-time guarantee or acceptable memory for a larger world. The
string-keyed light map still costs hundreds of megabytes at 425,984 cells; compact
section storage remains future production work. Sky light, rendered brightness,
long-session memory and actor/resource-frame entry adoption are not claimed.

## API

Import `src/block_light.bend` as `BL` and retain one `BL.State` owner beside the
authoritative world. Coordinates use the existing `Core.Position`: dimension
name plus raw two's-complement `U32` x/y/z, exactly as Core stores them.

| Operation | Result and meaning |
| --- | --- |
| `BL.new()` | An empty resident field with no queued work. |
| `BL.publish(state, position, BL.Descriptor{registry_state, effective_emission, dampening})` | `State & Result<&2,&2,Error,Unit>`. Publish a loaded cell or accepted block/property edit. Both light values must be 0 through 15; invalid input preserves the complete previous state and returns `InvalidDescriptor`. |
| `BL.unload(state, position)` | Remove this resident cell and schedule the neighbors that previously received its light. |
| `BL.status(state)` | Return the same owner beside `Stable{}` or `MoreWork{pending}`. |
| `BL.advance(~Context, ~occludes, context, budget, state)` | Return the sole owner beside status after at most `budget:Nat` queued cell visits. Resume the same owner when `MoreWork` remains. An already settled field returns immediately. |
| `BL.sample(state, position)` | `State & Maybe<&2,U32>`. `Some{0}` is known darkness; `None{}` is unknown/unloaded. A sampled level is provisional while work remains. |

The provider signature is:

```text
Context is Data
occludes: Context -> BL.Descriptor -> BL.Descriptor -> BL.Direction -> Bool
```

It receives **source descriptor, target descriptor, source-to-target direction**.
Directions are `Down`, `Up`, `North`, `South`, `West`, `East`; `direction_id`
returns the pinned Java ordinals 0,1,2,3,4,5. The provider must use the union of
the source's facing occlusion shape and the target's opposite facing shape,
including the actual `canOcclude`/`useShapeForLightOcclusion` policy. It must be
a total, exact provider over the states published to this field. Model render
geometry or collision solidity alone does not satisfy that contract.

For example, a catalog with immutable `Catalog.LightShapes` and a closed
`Catalog.faces_occlude` definition can call:

```text
BL.advance(~Catalog.LightShapes, ~Catalog.faces_occlude, shapes, budget, state)
```

The `~` provider is closed compile-time syntax; changing catalog data travels
through the ordinary immutable `context` argument. If that context changes
occlusion for already resident states, republish the affected cells so their
dependency edges are scheduled again.

## Authoritative edits and presentation

1. Apply/validate a mutation through the existing authoritative Core owner.
2. After acceptance, resolve its complete state properties in the catalog and
   publish the descriptor. Publish **every** newly resident cell, including air,
   before expecting light to cross it; notify unloads explicitly. Batch section
   admission may publish all 4096 cells before advancing.
3. Run bounded `advance` calls at the simulation's existing cadence. An edit
   that changes emission, dampening, or directional shapes uses the same API.
4. A resource-frame consumer reads a field reported `Stable`, threading its
   owner through `sample`. It must handle unknown samples explicitly, rather
   than substituting a claimed known world light value.

`effective_emission` is zero when block lighting is disabled for that section;
otherwise it is the actual state's emission. This module does not infer lighting
enablement from block IDs. Loading, enabling/disabling lighting, and catalog
replacement are consumer lifecycle events and must publish the appropriate
descriptors and resident domain.

This lane has not changed `Core.World`, `world_mesh`, or `world_resource_frame`.
It does not implement sky light, Java section/nibble persistence or light
packets, chunk lifecycle policy, face brightness, packed shader color, gamma,
smooth/ambient occlusion shading, or renderer adoption. Block levels 0..15 are
not already the RGB `world_mesh.Appearance.light` value.

## Propagation and boundaries

For a known target, the settled value is the maximum of its effective emission
and all open incoming neighbor contributions. Each contribution is the source
level minus `max(1, target.dampening)`, saturated at zero. The target's own
emission survives target opacity; an opaque emitter can illuminate adjacent air.

The field owns a string-keyed resident map and a deduplicated FIFO. A descriptor
edit schedules itself and all six neighbors. A changed light level schedules
its six consumers. Local recomputation supports decreases, competing sources,
newly opaque barriers, source changes, and newly open paths; it does not keep
stale light forever after source removal. Every native comparison settles
this same implementation under budgets 1,7,64, rather than resetting or solving
each phase in a separate reference algorithm.

Unknown cells contribute no light and stop propagation. Loading a neighboring
cell schedules both directions, so the resident field may extend on later
admission. Dimensions do not share keys. At signed I32 endpoints, a neighbor
outside that domain is absent; there is no coordinate wrap connecting opposite
world edges. This is a closed resident-domain policy, not a claim of complete
Java chunk-storage lifecycle parity. Callers requiring external boundary light
must admit those known neighboring cells or a sufficient known halo.

Java uses specialized decrease/increase queues. Bend's bounded local relaxation
targets the same settled field; intermediate levels, visitation order, and work
counts deliberately differ. The map representation is a reusable initial
production implementation, not evidence of chunk-scale performance or compact
nibble storage. No full-game performance claim is made.

## Reproducible checks

```sh
python3 tools/reference_block_light_probe.py
python3 tools/test_block_light.py
```

The first command verifies the installed official 26.3 client/classpath hashes
and runs its **unmodified `BlockLightEngine`** through a declared
`LightChunk`/`LightChunkGetter` receiver. It observes real emission/attenuation
properties, directional shape edges, all-registry property distributions, and
settled add/remove/edit phases. Unlisted positions return actual bedrock and
absent chunks return null to the engine's real fallback. A fixture cell labeled
`unloaded` becomes bedrock in Java; the Bend unknown sample is compared as
`None`, while every remaining resident sample is compared exactly.

The second command checks the actual Bend source, checks eight implementation
laws through the independent BendTT kernel, emits/compiles a narrow CPU native
receiver, and compares every Java-observed phase. Only catalog descriptors,
shape callback data, coordinates, and edits enter that executable. Expected
levels stay in the comparison process; Python never propagates light.
The same native receiver also checks separate dimensions, signed endpoint
boundaries, and rejection of invalid emission/dampening against the retained
settled owner. A named `/usr/bin/time -l` native resource check records peak RSS
for the bounded six-direction receiver under budget one; it does not establish
world-scale memory use or a long-session leak bound. Lighting has no custom FFI.

`src/block_light_laws.bend` and `src/block_light_proof.bend` establish complete
owner retention on rejected descriptors and zero budgets, inert settled work,
unknown versus dark semantics, facing-direction inversion, blocked transfer,
and saturation. The two work-control laws use an open-face provider; their
branches do not call it. These are actual production-function laws, not a proof
of convergence, every published map invariant, or whole-game lighting parity.
Native/oracle evidence supplies the named behavioral checks separately.

Evidence is recorded in `evidence/block-light-reference.json` and
`evidence/block-light-native.json`; raw compiler and receiver artifacts remain
under ignored `build/block-light-*` directories.
