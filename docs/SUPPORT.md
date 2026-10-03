# Supporting-block cache and sampling

`src/support.bend` implements the pinned Java **26.3** Entity supporting-block cache projection and the position/factor helpers needed by the neutral player motion path. It is pure checked Bend. The caller owns the world and supplies complete, ordered, actual full-cube candidates; the module performs no host call, world mutation, registry lookup, or trig lookup.

Confidence is **high for recorded bounded full-cube observations and separately recorded numeric helpers**. Context-dependent and non-full-cube shapes, fence/wall/gate cached sampling, complete world scanning, hazards and full Entity behavior remain outstanding under the full Minecraft implementation goal.

## Contract

```bend
type State is Data:
  State{main: Maybe<&2,T.BlockPos>, on_ground_no_blocks: Bool}

type Candidate is Data:
  FullCube{position: T.BlockPos}

type Queries is Data:
  Queries{primary: G.AABB, fallback: Maybe<&2,G.AABB>}

queries_checked(box: G.AABB, movement: Maybe<&2,M.Vec3>)
  -> Result<&2,&2,Error,Queries>

select_checked(position: M.Vec3, query: G.AABB,
               candidates: List<&2,Candidate>)
  -> Result<&2,&2,Error,Maybe<&2,T.BlockPos>>

needs_fallback(cache: State, grounded: Bool,
               primary: Maybe<&2,T.BlockPos>,
               movement: Maybe<&2,M.Vec3>) -> Bool

update_cached(cache: State, grounded: Bool,
              primary: Maybe<&2,T.BlockPos>,
              fallback: Maybe<&2,T.BlockPos>, has_movement: Bool) -> State

update_checked(cache: State, position: M.Vec3, box: G.AABB,
               grounded: Bool, movement: Maybe<&2,M.Vec3>,
               primary: List<&2,Candidate>, fallback: List<&2,Candidate>)
  -> Result<&2,&2,Error,State>

get_on_pos_checked(position: M.Vec3, cache: State, offset: F32)
  -> Result<&2,&2,Error,T.BlockPos>
below_position(position: M.Vec3, cache: State) -> T.BlockPos
block_position(position: M.Vec3) -> T.BlockPos
jump_factor(current: F32, below: F32) -> F32
```

Block coordinates are Java signed 32-bit two's-complement words stored in `U32`. Every coordinate payload is valid. Every combination of `main` and `on_ground_no_blocks` is also valid independently; neither the Body's grounded flag nor the cache coordinate reconstructs the other cache field. In particular, null movement after a miss can preserve a previous main coordinate while setting the no-blocks flag. Persist both fields for deterministic continuation.

A world adapter retains its owned world and the earlier immutable cache until the complete transition succeeds. Use `queries_checked` to obtain the potential primary/fallback boxes, collect actual candidates in the production order, run `select_checked`, and collect a fallback only when `needs_fallback` requests it. Commit `update_cached` only after all required world reads pass. `update_checked` is the convenient pure composition for callers already holding both complete candidate lists. This module receives no affine world owner; rejected Results cannot consume one. The caller remains responsible for returning and preserving its owners on failure.

`InvalidPosition{field}`, `InvalidBox{field}`, `ReversedBox{axis}`, `InvalidMovement{field}` and `InvalidOffset{}` reject nonfinite checked inputs or reversed cached boxes. Computed query boxes receive the same admission checks. These are deliberate finite-interface restrictions: raw helpers separately reproduce Java saturation/nonfinite position sampling, without admitting an unbounded collision query. Out-of-signed-int finite positions in position helpers saturate to Java int extrema. Candidate distances may overflow to positive infinity and then fail to beat the finite initial best distance; that observed result is supported.

The candidate constructor signifies an actual full unit cube at the supplied coordinate. It does not prove that the world contains that cube or that the candidate list is complete. Air contributes no candidate. For cached `get_on_pos`, the caller must establish that the current cached block state has no fence/wall/fence-gate exception. Air, stone, dirt and oak planks establish this in the current adapter. A cached block can be removed to air; the cache coordinate alone must never be used to infer block identity.

## Exact update and selection

For a grounded update, the primary query is constructed by the actual Java AABB constructor from:

```text
[minX, minY - 1.0E-6d, minZ, maxX, minY, maxZ]
```

Subtraction is separately rounded binary64. If the primary selection is present, it replaces the cache and clears the no-blocks flag. If it is absent and the old no-blocks flag is true, the cache becomes absent and no fallback is queried. Otherwise, non-null movement queries the slab translated by `(-movement.x, +0d, -movement.z)` and stores its optional result. The distance calculation still uses the current Entity position; it does not use the backward query center. With null movement the previous main coordinate is retained and the no-blocks flag becomes true. An airborne update clears the main coordinate and the flag, with no supporting query.

Null movement is different from a zero vector. Neutral production `Entity.move` applies `setPos`/records movement before calling `setOnGroundWithMovement`, and passes the resolved displacement as a non-null Vec3 even when it is zero. Its support slab therefore uses the post-move box and its selection uses the post-move position. Other explicit `setOnGround` paths can supply Java null. Updating cache during the travel movement phase preserves the next tick's support/friction/jump sampling order; gravity and drag do not change its position or box.

For exact full-cube `Shapes.block()` states, actual BlockCollisions uses strict AABB intersections. The module derives the full cube endpoints by widening signed coordinates and adding `1d`, then filters candidates with those same strict comparisons. No extra voxel epsilon is introduced.

The selector starts with `Double.MAX_VALUE`. Each distance follows actual `BlockPos.distToCenterSqr` operation order:

```text
dx = ((double)x + .5d) - entityX
... similarly dy, dz
distance = (dx*dx + dy*dy) + dz*dz
```

Every addition, subtraction and product separately rounds binary64. Smaller distance wins. Equal distance uses `previous.compareTo(candidate) < 0`: actual Vec3i compares Y, then Z, then X by **wrapping signed int subtraction**. A mathematically safe lexical comparison would be wrong at coordinate overflow boundaries. Supplied production iteration order matters where wrapped comparison ceases to behave like a total mathematical order.

## Position and jump-factor helpers

`getOnPos()` uses float `1.0E-5f` (`3727c5ac`), legacy uses `.2f` (`3e4ccccd`), and the friction/jump support helper uses `.500001f` (`3f000011`). With no cached main, all XYZ coordinates come from actual `Mth.floor`, with Y first subtracting the widened float offset. With a cached full-cube main and offset at or below `1.0E-5f`, the cached coordinate is returned unchanged. Larger offset keeps cached X/Z and replaces Y with `Mth.floor(entityY - widenedOffset)`. Fence/wall/gate tag exceptions require future context support.

Pinned `Mth.floor(double)` calls `Math.floor` then Java double-to-int conversion: NaN becomes zero and out-of-range values saturate. Raw `get_on_pos` also preserves the observed float-comparison branch for NaN offsets; the checked API rejects nonfinite positions and offsets before returning a new value. Raw nonfinite offset helpers are isolated from world collision queries.

Actual `Entity.getBlockJumpFactor` reads both the current block factor and the block below even when the current factor will win. If the widened current factor equals `1d`, the below factor is returned; otherwise the current factor is returned. `jump_factor` implements this numerical selection. World adapters must perform both actual reads and validate their block contexts. Honey helper observations establish its `.5f` priority only; they do not admit honey movement or its block effects.

## Independent reference and verification

`tools/reference_support_probe.py` calls untouched production `Entity.setOnGroundWithMovement`, its private supporting update, actual `CollisionGetter.findSupportingBlock`, actual BlockCollisions, and the original position/jump helpers on the existing actual Player/finite Level fixture. Cache seeding and observation use reflection. The supporting-query observer calls the production superclass first and returns its unchanged Optional, then independently enumerates production BlockCollisions to record ordered candidates and raw distance/shape observations. It never replaces the selector with a host algorithm.

The inherited fixture's local-authority, bounce, movement-emission, actor-free, loaded no-fluid chunk and finite-world contracts remain explicit in the reference source fingerprints and fixture metadata. These return contracts do not establish full Level/ServerLevel/entity behavior. Bounded support histories write only air, stone, dirt and oak planks. Honey/slime factor cases call only the numerical helper and execute no support query or block effects.

The corpus contains **188 histories, 529 cache transitions, 444 actual supporting queries, 236 signed comparison helpers, 176 finite-input distance helpers, 396 position/offset helpers and 24 block jump-factor helpers**. It includes corner ties, epsilon neighbors, zero and null displacement, stale-cache removal and reintroduction, known-absent fallback suppression, airborne resets, wrapped signed comparisons, distance overflow, huge finite sampling positions and nonfinite raw offsets. Two fresh actual Java reruns match. Both unsealed and checksum-resealed cache corruption are rejected.

A separate focused experiment executes **10 untouched actual Player.move calls** and records the real supporting-call arguments, position application and movement-recording hooks. All ten leave the raw position and box equal; six skip both position application and movement recording while still calling the supporting update. A floor-blocked `-.0004d` request selects the floor support and replaces stale cache, while a wall-blocked `.0004d` request clears cached support. Zero displacement enters position application and movement recording, then clears support through its airborne flag. Signed-zero displacement payloads are retained in the actual supporting call. These observations establish that `position_changed=false` must not suppress cache update in the admitted authority context. The experiment adds separate evidence and leaves the earlier support reference observations/source strings unchanged.

The native harness compares isolated updates and histories carrying the previous native cache, observed primary/fallback query boxes, every recorded selection, strict filtering of extra far cubes, candidate distances, signed comparison payloads, sample coordinates and factor payloads. Checked malformed numeric inputs are followed by a successful continuation to test prior-cache retention. The four production kernel laws establish their specific airborne/null/known-absent/factor statements; they do not prove general Java parity.

```sh
python3 tools/reference_support_probe.py
python3 tools/reference_support_probe.py --verify-existing
python3 tools/reference_support_probe.py --selftest
python3 tools/reference_support_probe.py --move-gate
python3 tools/test_support.py
```

When resource scheduling splits the final build/kernel from the native test run, `python3 tools/test_support.py --skip-build --skip-checks --reuse-checked` accepts the completed bounded records only after every recorded production/harness/dependency source hash matches. It never converts a skipped or interrupted check into a pass. The narrowed final native build passed in **3.216004 seconds**, and its full import-closure independent kernel passed in **7.987922 seconds**. Native counts and timings are recorded independently in the final verification evidence.

Recorded verification status, hashes, timings and commands live in `evidence/support*.json`. An interrupted full harness verdict during concurrent compiler memory pressure is recorded explicitly in `support-kernel-interruption.json`; it is inconclusive and is not a mathematical failure. The first test-harness native emission also remained unfinished beyond 21 minutes. A one-second macOS process sample reported physical footprint `12.0G` and peak `12.9G`; the lead interrupted that own process before any binary was created. `support-build-diagnostic.json` records the sample hash, interrupted command and measured state without inferring a correctness failure. The harness then separated operation dispatch from numeric-list matching and removed imports of other test modules, while the production support source remained unchanged. Its ordinary check decreased from 5.329590 seconds to 0.416643 seconds; exact cause within the compiler is still unknown. Native/kernel results must be read from their completed evidence, not inferred from this implementation description. Workload timings do not establish a Minecraft performance advantage.

Required continuation includes sole-world owner integration, actual candidate query ordering/completeness, resolved support/block context, full contextual shapes and cached fence/wall/gate semantics, attributes/abilities, additional Entity/Player tick state and the remaining complete Minecraft systems.
