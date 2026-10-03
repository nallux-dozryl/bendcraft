# 26.3 block physics and shape reference

The headless Java probe covers **all 1,286 blocks and 35,723 states** in the pinned release. It records primitive physics/light/render values and 357,230 explicitly contextual shape queries, with zero query exceptions. This is independent **Java reference extraction**, not a Bend physics implementation or a gameplay parity result.

Confidence is high in the observed values, raw floating-point encodings, state mappings and declared contexts. Dependency classification is moderate because the bytecode scan records direct references, while callbacks and further delegation remain open. Universal behavior across all worlds, positions, entities and block entities is unknown.

## Inputs and reproduction

The probe uses the exact verified inner 26.3 server and the libraries listed in its official bundle manifest. Every jar is checked against the recorded SHA-256 before it enters the classpath. The Java source is created only in ignored `reference/extracted/probes/ReferenceBlockProbe.java`. It calls `SharedConstants.tryDetectVersion()` and `Bootstrap.bootStrap()`, then queries the registered states. It opens no game window, starts no ticking server, and performs no account login.

Run from the `minecraft` directory:

```sh
python3 tools/reference_block_probe.py
python3 tools/reference_block_probe.py --verify-existing
python3 tools/reference_block_probe.py --selftest
```

The full extraction verifies every state ID, property assignment and block protocol ID against the official generator reports. `--verify-existing` independently reads the table/dictionary, verifies their encodings and content hashes, checks state identity, and compares the table with cached Java observation records when available. `--selftest` performs two complete Java extractions, compares four output files byte-for-byte, and exercises deliberate corruption failures.

A representative subset can be regenerated with `--blocks minecraft:stone,minecraft:oak_stairs,minecraft:oak_fence,minecraft:powder_snow`. This **replaces the output dataset** with the selected blocks' states. The current checked dataset is the full release. Run without `--blocks` to restore it. Integer shape dictionary indexes are local to the generated dataset, so always consume the table and dictionary from the same extraction.

Raw Java observations, logs and `javap` output remain ignored in `reference/cache`. Named classes are already present in the release; no mappings or decompiler download is used. The base inventory's hashes/runtime details are in [REFERENCE.md](REFERENCE.md).

## Interface

[generated/reference_block_physics.tsv](../generated/reference_block_physics.tsv) contains one row per state, 57 named columns and 35,723 data rows. It is 13,073,465 bytes, with SHA-256:

```text
5524f68f61ee1fa34df98d02bd7e86f1cd1ea2b5f05df3e9365aec14b567d7d1
```

[reference/block_physics.json](../reference/block_physics.json) contains the shape dictionary, block/default-state/class identities, declaring method owners, direct bytecode call/field references, per-block classification/counts, contexts, table fingerprint and explicit limits.

| Column group | Observed data |
| --- | --- |
| Identity | Official state ID and block identifier |
| Float32 and widened float64 pairs | Hardness, explosion resistance, friction, speed factor, jump factor, bounce restitution, fall-distance reduction, empty-world shade brightness |
| Light/render | Light emission/dampening, render-shape enum, piston push-reaction enum, occlusion/solid-render/skylight/emissive flags |
| Other state flags | Air/liquid/legacy-solid, correct-tool requirement, replaceability, random ticking, block entity, dynamic-shape flag, offset-function flag |
| Fluid | Registered fluid identifier, amount and source flag |
| Shapes | Ten references into the exact shape dictionary |
| Dependency observations | Collision/outline world-getter read counts and six sampled context-change flags |

Use column names rather than hard-coded offsets. State/property decoding remains in [reference_blocks.tsv](../generated/reference_blocks.tsv); this table does not assign new state or protocol IDs. The tool-requirement flag describes `requiresCorrectToolForDrops()`, rather than a complete tool-effectiveness, break-progress or drop rule.

### Floating-point representation

Each primitive property retains the **source float32 bits** as eight hexadecimal digits and Java's exact widening to float64 as sixteen hexadecimal digits. Shape endpoints retain `Double.doubleToRawLongBits`, with no decimal rounding. Signed zeros and exact binary values are preserved.

For example, ordinary block friction is the float32 value with bits `3f19999a`, widened to float64 bits `3fe3333340000000`. Its widened value is approximately `0.6000000238418579`; a float64 literal `0.6` has different bits (`3fe3333333333333`). Ice friction similarly widens its float32 value to approximately `0.9800000190734863`. Soul-sand/honey speed factors widen to approximately `0.4000000059604645`.

Use the float32 encoding when reproducing a Java operation that remains float32, and the widened encoding where Java promotes the stored value. These paired inputs do not by themselves specify expression evaluation order, intermediate rounding, vector operations or movement equations.

The shape dictionary has **963 distinct encoded records** and 15,756 exact float64 endpoints. Each record contains ordered AABB arrays:

```text
[minX, minY, minZ, maxX, maxY, maxZ]
```

The coordinates are the local coordinates returned by `VoxelShape.toAabbs()`, including any offset applied by the queried implementation. Empty shapes contain an empty list. The dictionary preserves Java's decomposition and traversal order; two decompositions of the same geometric union can have different record identities. Each record has a full SHA-256 of its canonical JSON. Small integer dictionary indexes are assigned by sorting those hashes, avoiding repeated 64-character hashes in every state row.

Coordinates must not be clamped to a unit cube. For example, the default unconnected oak fence's collision AABB has X/Z interval `[0.375, 0.625]` and Y interval `[0, 1.5]`. Stone has the unit-cube collision shape; honey's empty-context collision shape is inset in X/Z and reaches Y `0.9375`; soul sand reaches Y `0.875`. These examples describe the queried shapes, rather than a replacement movement or rendering algorithm.

## Declared contexts and queries

The baseline world is **`EmptyBlockGetter.INSTANCE`**: it returns air at every queried position, empty fluids and no block entities. It does not represent the sampled state placed in a real world. Baseline position is `(0,0,0)` and baseline collision context is **`CollisionContext.empty()`**.

| Shape column | Exact query/context |
| --- | --- |
| `collision_empty_origin_shape_id` | `state.getCollisionShape(emptyWorld, origin, emptyContext)` |
| `outline_empty_origin_shape_id` | `state.getShape(emptyWorld, origin, emptyContext)` |
| `occlusion_shape_id` | `state.getOcclusionShape()` |
| `support_empty_origin_shape_id` | `state.getBlockSupportShape(emptyWorld, origin)` |
| `collision_empty_other_position_shape_id` | Same collision query at `(7,11,-13)` |
| `outline_empty_other_position_shape_id` | Same outline query at `(7,11,-13)` |
| `collision_position_context_2_shape_id` | Collision with `CollisionContext.positionContext(2.0)` |
| `collision_fluid_context_shape_id` | Collision with `CollisionContext.emptyWithFluidCollisions()` |
| `collision_trace_empty_origin_shape_id` | Baseline collision with a getter wrapper delegating all results to `EmptyBlockGetter`, recording calls |
| `outline_trace_empty_origin_shape_id` | Baseline outline with that getter wrapper |

The explicit context collision overload is used, rather than substituting the overload that may return a cached collision shape. The tracing wrapper has the same returned values as `EmptyBlockGetter`; the two resulting shapes were also compared. No sampled shape changed merely because the getter was wrapped.

## Observed dependencies and unresolved cases

| Observation | State count |
| --- | ---: |
| Collision changed between the two positions | 52 |
| Outline changed between the two positions | 110 |
| Collision changed when fluid collision was enabled | 32 |
| Collision changed for the sampled position-only context | 0 |
| Official `hasDynamicShape()` flag | 199 |
| Official `hasOffsetFunction()` flag | 151 |
| Collision called `getBlockEntity` on the tracing world | 114 |
| Outline called `getBlockEntity` on the tracing world | 102 |

The 52 position-changing collisions are bamboo (12 states), pointed dripstone (20) and sulfur spikes (20). Outline changes also include mangrove propagules and several flowers. All 151 offset-flagged states need the exact offset function, even though the two sampled coordinates produce a change for only 110 outline states. Two coordinates cannot enumerate all possible offsets.

The block-entity reads occur for shulker-box variants and, for collision, moving pistons. A missing block entity is only the probe's fallback case. Actual opening/progress, piston animation, movement and attached state need real block-entity fixtures. Their empty-world shapes cannot serve as universal shapes.

Direct collision-method bytecode exposes collision/entity-context calls for water, lava, powder snow and scaffolding; outline-method bytecode exposes them for light blocks and scaffolding. Powder snow reads an `EntityCollisionContext` entity and the entity's fall distance and calls walkability/descending/above/placement logic. The sampled context with a height but no real entity does not exercise those conditions. Scaffolding calls above/descending/placement logic. Therefore their unchanged sampled values do **not** justify a static collision classification.

The 32 fluid-context changes are the water and lava level states. This demonstrates that even an empty-world query changes when the declared collision context changes. It does not implement fluid forces, stand-on-fluid entity rules, currents, swimming or neighboring-fluid behavior.

The metadata records 255 source method bodies and their declaring owners, direct calls, fields and detected dependency categories. Calling `CollisionContext.empty()` is classified as fixed empty-context use, rather than evidence that a method reads an entity. A `BlockState.getFluidState()` field lookup is not mislabeled as a world getter read. Function/predicate application, delegated shape calls and absent direct markers remain explicitly incomplete analyses.

The pinned `BlockStateBase.getDestroySpeed(BlockGetter, BlockPos)` body reads the stored `destroySpeed:F` field and returns it; it makes no world calls. That supports interpreting this hardness column as a state primitive. Player break progress is a different method with player/tool/effect inputs. Other block/state declaring methods and references are retained so further analysis can distinguish stored constants from state functions and contextual behavior.

The data do not establish universal world/entity independence, numerical collision resolution, epsilon handling, shape-grid traversal, placement/update rules, actual lighting propagation, rendering or complete player movement. Those remain separate implementation and independently verified reference tasks.

## Verification evidence

[reference_block_probe.json](../evidence/reference_block_probe.json) records the complete observation counts, zero query errors, state/property agreement, source/server hashes and output fingerprint. [reference_block_validation.json](../evidence/reference_block_validation.json) verifies all 35,723 rows, 285,784 exact float32-to-float64 widening pairs, 963 shape records, 15,756 AABB endpoints, dictionary references and the cached Java observations.

[reference_block_selftest.json](../evidence/reference_block_selftest.json) records two complete Java reruns with four byte-identical outputs. It rejects a corrupted friction value by checksum, rejects that same incorrect widening after checksum resealing, and rejects an inverted full-cube AABB after its shape checksum is recomputed. These tests validate the reference extraction and transport, rather than the game implementation.
