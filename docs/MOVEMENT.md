# Exact bounded entity collision transition

`src/movement.bend` implements the Minecraft Java **26.3** collision axis order, candidate-height stepping, query bounds, pose-dimension AABB reconstruction, collision flags, and a declared neutral restitution context. Coordinates, positions, requested displacement, clipped displacement, and velocity use the pure exact binary64 payload in `src/f64.bend`. Java's explicit float casts for dimensions and step candidates use its exact `F.to_f32` and `F.from_f32` conversions. No gameplay code uses host floating arithmetic, foreign effects, unchecked proofs, or a compiler modification.

Confidence is **high** for the recorded direct game-method observations, including 159 executions of the actual `Entity.move` in a narrow real Level. Confidence remains **moderate** for the older composed `resolve` / `move` instrument, which follows inspected branch flow itself. The direct fixture closes that oracle gap for its declared neutral subset. It does not establish full player, server-world, or contextual-shape parity.

This is an intermediate verified movement path. It does not establish completion of player movement or of Minecraft.

## Interface and ownership

```bend
import ./movement.bend as M
import ./geometry.bend as G
import ./f64.bend as F

type Vec3 is Data:
  Vec3{x: F.F64, y: F.F64, z: F.F64}

type Body is Data:
  Body{position: Vec3, box: G.AABB, velocity: Vec3,
       width: F32, height: F32, on_ground: Bool,
       horizontal_collision: Bool, vertical_collision: Bool,
       vertical_collision_below: Bool}

type Resolution is Data:
  Resolution{displacement: Vec3, stepped: Bool}

type Transition is Data:
  Transition{body: Body, displacement: Vec3, stepped: Bool,
             position_changed: Bool}
```

Position is the entity's feet center. Width and height are the actual Java float pose dimensions. `Body.new(position,width,height,velocity,grounded)` creates the collision box with the `EntityDimensions.makeBoundingBox` calculation: float-rounded `width / 2`, promoted to double before adding or subtracting from X/Z; float height promoted before adding to Y. Current pose transitions and eye-height selection belong to later entity/player integration. The renderer may narrow an exact coordinate with `F.to_f32` without writing the body.

| Function | Contract |
| --- | --- |
| `collide_with_shapes(requested,box,colliders)` | Actual private `Entity.collideWithShapes` algorithm for an ordered list of independent occupied one-cell shapes or explicit empty shapes. |
| `candidate_step_heights(box,colliders,maximum:F32,previous:F32)` | Actual candidate collector semantics; returns sorted, deduplicated float values promoted to F64. |
| `resolve(box,grounded,maximum,requested,initial,step)` | Resolves initial clipping and the pinned step-up branch against two supplied ordered collision lists. |
| `move(body,requested,maximum,initial,step)` | Applies that resolution to immutable position/AABB/velocity/flags in the supported restitution context. |
| `move_checked(body,requested,maximum,initial,step)` | Validates state and both complete supplied collision lists before movement and validates finite output before returning `Done{Transition}`. |
| `initial_block_query(box,requested)` | Exact `box.expandTowards(requested)`. |
| `initial_entity_query(box,requested,maximum)` | Initial entity-collider sweep: requested expansion, then upward float maximum expansion. |
| `step_query(box,requested,baseline,maximum)` | Exact second block/border collision query bounds, including conditional landing adjustment and downward float epsilon margin. |

Every state and collision value is immutable Data. No function takes, aliases, duplicates, or replaces the Core section/world array owner. A caller keeps its owned world, materializes the required lists, and installs a successful returned body at the simulation tick boundary. `move_checked` returns `Result<&2,&2,Error,Transition>`; on `Fail`, the caller retains its earlier immutable body and does not commit a movement update.

`Transition.position_changed` is retained for integration compatibility, but its exact meaning is **the position-application gate was taken**. It can be true for zero displacement or when an addition rounds back to the same position. It is not a claim that the coordinate payload changed.

## Collision-source requirements

The shape representation is the exact occupied raw single-cell substrate of `geometry.bend`. Each `BoxCollider{AABB{...}}` means one occupied voxel cell with already-realized, finite, numerically nondecreasing coordinate endpoints. Degenerate occupied cells stay occupied. `EmptyCollider{}` means zero occupancy; it is a list entry with observable iterable epsilon behavior. Preserve list order and raw endpoint payloads.

The supplied lists must be the actual ordered results for their respective queries. Merely supplying a conservative spatial superset is insufficient for exact parity: extra entries can change tiny-displacement zeroing or introduce candidate step heights. An entire fixed finite list can be used for both phases only under the explicitly declared finite-shape test-world contract where that list defines each query result.

For world integration, obtain the initial entity list with `initial_entity_query`. Obtain initial block/border collisions with `initial_block_query`. Compute the baseline with `resolve(box,grounded,0.0,requested,initial,Nil{})`, then materialize the second list using `step_query`. This baseline wrapper preserves the original requested signed-zero vector when its squared length equals zero, matching `Entity.collide`'s bypass.

The inspected Entity overload of the misleadingly named `collectCollidersIgnoringWorldBorder` actually appends supplied entity shapes, an optional close-border shape, then block collisions. The CollisionContext overload omits the border shape. Both initial and step branches in `Entity.collide` use the Entity overload. The block collision iterator's exact enumeration/filtering and dynamic world-border representation remain the resolver's responsibility. The movement module does not claim to implement them.

Do not treat empty-context shapes in `reference/block_physics.json` as entity/world-independent behavior. States flagged for context, neighbor, offset, or dynamic dependencies require their actual contextual resolver. Multi-cell shapes and merged voxel shapes cannot be flattened into an arbitrary box sequence under this module's parity claim. The initial bridge can explicitly support verified independent full boxes and reject all unsupported states.

## Pinned behavior

The axis order is Y, then Z, then X when `abs(requested.x) < abs(requested.z)`; otherwise it is Y, X, Z. A zero-valued requested axis is skipped. For every nonzero axis, Java moves the **original** AABB by the accumulated collision vector, then clips. Repeatedly moving an already moved AABB would introduce different IEEE rounding and is not used. Empty collision lists preserve the requested vector including negative zero. Nonempty lists accumulate from positive-zero `Vec3.ZERO`; the `resolve` wrapper separately preserves a zero-length requested vector before that operation.

Stepping requires a positive float `maxUpStep`, a prior grounded state or a newly clipped downward displacement, and an exact X or Z clipping difference. The grounded/step decision uses exact double comparisons; the later horizontal collision flags use the different `Mth.equal` tolerance.

When the initial move lands, the step search starts from the original box moved by the clipped Y displacement. Otherwise it starts from the original box. Every candidate is `(float)(shapeY - adjustedBox.minY)`, with values below zero, equal to `(float)baseline.y`, or above the maximum excluded. The collector observes both Y coordinate endpoints of each raw occupied shape and the actual empty shape's single zero coordinate. Values are deduplicated by float bits and sorted with float comparison, retaining signed-zero distinctions where they survive the comparison filters.

Candidates are attempted in ascending order. The first attempt whose `x*x + z*z` is strictly greater than the initial clipped horizontal squared distance is returned; later candidates are not computed. Its displacement subtracts the original/adjusted minimum-Y correction using the actual rounded AABB endpoints. There is no invented down-settling move or maximum-height preference.

The step query expands the adjusted box towards `(requested.x,(double)maximum,requested.z)`. Only when the original collision did not land, it further expands downward by `(double)-1.0E-5f`, bits `0xbee4f8b580000000`. The position-application gate is `resolved.lengthSqr > 1.0E-7 || requested.lengthSqr - resolved.lengthSqr < 1.0E-7`. A taken gate proposes position plus displacement, retains the old position when all XYZ coordinates compare numerically equal, then rebuilds the AABB from the retained or updated position. This preserves signed-zero payloads just like `Entity.setPosRaw`.

The supported state-application context is a locally authoritative entity permitted to simulate movement, with suppressed bounce and block speed factor exactly `1.0f`. Horizontal flags use strict `abs(resolved - requested) < (double)1.0E-5f`, where the epsilon is `0x3ee4f8b580000000`; equality at the threshold counts as a collision. Vertical collision uses exact numeric inequality; downward vertical collision sets `vertical_collision_below` and `on_ground`. With zero requested Y, authoritative handling still updates those vertical/grounded flags. Neutral restitution preserves Java's signed-zero multiplications on blocked velocity components. General bounce, gravity, drag, and block-speed policies are not silently substituted.

## Checked-state policy

Validation order is body position, stored AABB, velocity, width/height; requested XYZ; maximum step height; initial list; step list. Lists are validated completely before stationary movement or early clipping can skip entries. Body/vector/box coordinates must be finite, dimensions and maximum must be finite and nonnegative, and occupied obstacle endpoints must be numerically nondecreasing. The output position, box, velocity, and displacement must remain finite.

Errors are `InvalidBody{component,field}`, `InvalidDimensions{field}`, `InvalidRequest{axis}`, `InvalidStepHeight`, `InvalidCollider{phase,index,field}`, `ReversedCollider{phase,index,axis}`, and `NonFiniteResult{component,field}`. Components 0/1/2 designate position/AABB/velocity; output component 3 designates displacement. Collider phase 0/1 designates initial/step. All indices are zero-based. Raw `move`/`resolve` expose the underlying algorithms separately. These rejection rules protect simulation state and are an explicit extension; Java's raw geometry methods accept nonfinite inputs.

## Verification and outstanding work

Reproduce the independent fixtures and checks:

```sh
python3 tools/reference_movement_probe.py
python3 tools/reference_movement_probe.py --verify-existing
python3 tools/reference_movement_probe.py --selftest
python3 tools/test_movement.py
```

`reference/movement.json` carries official server/bundle/runtime/class/library hashes, named bytecode-method hashes, deterministic input seed, and every raw-bit observation. There are 823 direct collision calls, 823 direct candidate collectors, 823 composed resolutions, 823 composed state transitions, 173 cases each for the initial block query, entity query, step query, and bounding-box construction, and **159 actual `Entity.move` cases**: **4,143** Java-backed cases in total. The native suite repeats all 982 state transitions through the checked entry point, checks 348 direct Level collision-query bounds, and probes 101 rejection cases. Targeted cases cover floor/ceiling/wall/corner clipping, float step-limit neighborhoods, ceilings that prevent stepping, grounded and airborne stepping, zero/tiny/signed movement, exact epsilon and adjacent doubles, axis/list ordering, degenerate occupied cells, and seeded finite shape sets. Nine implementation laws pass the compiler and independent BendTT kernel. Native emission inspection verifies zero host floating-arithmetic scalar simulation helpers.

### Actual Entity.move fixture

The direct lane creates a genuine `Level` superclass instance with dimension, biome, and damage-type values obtained from the official `VanillaRegistries.createWorldLookup`. Its finite storage returns actual default stone, dirt, and oak-plank block states, or air. `getChunkForCollisions` returns that finite BlockGetter with all chunks available. `getBlockCollisions` records and materializes `super.getBlockCollisions`; the actual `BlockCollisions` iterator, CollisionContext, state collision shape, shape ordering, and query-filtering code execute. The default actual WorldBorder is distant from every fixture. Other entity collisions are explicitly empty.

`FixtureEntity` extends the actual `Entity` and uses registered `minecraft:player` default dimensions, **not** a `Player`, `LivingEntity`, or `ServerPlayer` implementation. Its `maxUpStep` is the input float constant; movement emission returns NONE; required abstract save/data methods contain no extra state; `hurtServer` returns false, with damage/health outside the comparison. Shift-key state activates the actual `isSuppressingBounce` method. `recordMovement` observes the returned displacement and calls its superclass. `Entity.move`, its private `collide`, position update, collision-flag assignments, restitution, supporting-block handling, and fall-damage handling are neither overridden nor reproduced by the direct fixture.

The Level's game-event sink is inert and counted. Unrelated abstract services throw if reached. Its minimal writable LevelData supplies time zero, NORMAL difficulty, non-hardcore, unlocked difficulty, and default respawn data. The copied biome/damage registries bind their tags empty to permit construction; blocks and entity types use the original built-in registries. This is a declared finite fixture, with no saved chunks, world ticking, actors, or data-pack tag loading. Its full-cube states have no contextual shape dependency.

The extractor directly invokes the private production `Entity.collide` to observe displacement and actual ordered collider/query results, then invokes the untouched `Entity.move` on the same initial body. It verifies that collision-query traces agree between those calls, and that movement's observed callback displacement agrees whenever the position gate is taken. The expected position, AABB, velocity, and collision/grounded flags are read from the actual entity after `move`. Position-application is observed via `recordMovement`; step success is identified by strict horizontal improvement over an actual initial collision call. The direct lane contains eight successful full-cube step-ups and retains actual input bodies/collider sets in `observation.actual_input` for the Bend comparison.

This direct runtime evidence exposed and repaired a discrepancy missed by the composed instrument: `(-0,1,-0)` plus a positive-zero movement proposal remained `(-0,1,-0)` in Java because `setPosRaw` compared coordinates numerically; Bend had replaced it with `(+0,1,+0)`. The repaired transition retains current payloads on a numerically equal proposal. A resealed corrupted expected result recreating that regression is rejected by the independent Java self-test.

Current exact counts, build/check/native timings, hashes, rejection cases, and confidence are in `evidence/movement-verification.json`. Java reproducibility and corrupted-result rejection are in `evidence/movement-reference-selftest.json`. `evidence/movement-cast-samples.json` contains the 74 actual Java-observed shape-coordinate deltas separately checked by the numeric owner. These timings are verification workloads and establish no Minecraft performance advantage.

Required continuation includes actual player/server-world integration beyond this neutral Level fixture, contextual block and border collision retrieval, full voxel shapes, player input and acceleration, locomotion attributes, gravity and drag, pose transitions, swimming/flying/climbing, edge backoff/pistons, bounce and block effects, supporting-block state, fall damage, and movement sounds/events. The numeric owner has now added `F.sqrt` and `F.to_java_long`; integrating `Vec3.normalize` and the pinned 65,536-entry float sine table remains necessary for `Entity.getInputVector`. In 26.3, `Mth.sin/cos` take double angles: their table index uses `angle * 10430.378350470453d`, cosine additionally adds `16384.0d`, then casts to long and masks with 65535. The preceding yaw multiply remains float `yaw * 0.017453292f`. A previous-version float/int lookup formula would be incorrect here.
