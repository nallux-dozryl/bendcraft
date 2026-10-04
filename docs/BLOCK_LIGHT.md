# Block light: production API and verification boundary

`src/block_light.bend` implements a resident block-light field and incremental
propagation in Bend. It accepts arbitrary catalog state IDs and properties;
Python only extracts reference observations and orchestrates comparisons.
The authoritative Core and resource-frame integration belongs to their owner.
Those existing files are unchanged by this lane.

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
