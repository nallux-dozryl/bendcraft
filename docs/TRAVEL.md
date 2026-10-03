# Neutral dry-air Player travel

`src/travel.bend` implements a bounded Minecraft Java **26.3** Player dry-air travel transition using the exact input-vector path in `locomotion.bend` and exact collision transition in `movement.bend`. It samples supplied pre-move ground friction and current resolved attributes, adds the input acceleration, performs movement and restitution, then applies gravity and drag. The decisive oracle invokes the **untouched actual `Player.travel`**, inherited `LivingEntity.travel` / `travelInAir`, and production `Entity.move` in a real finite Level fixture. It does not substitute a hand-composed travel algorithm.

Confidence is **high for the recorded admitted neutral cases**. Actual Player tick/aiStep, ServerPlayer/world integration, fluids, hazards, flight, glide, climb, and other travel contexts remain incomplete under the full Minecraft goal.

## Stable owner-retaining interface

```bend
type BlockPos is Data:
  BlockPos{x: U32, y: U32, z: U32}

type GroundSample is Data:
  GroundSample{position: BlockPos, friction: F32}

type Attributes is Data:
  Attributes{movement_speed: F.F64, gravity: F.F64,
             friction_modifier: F.F64, air_drag_modifier: F.F64}

type Context is Data:
  Context{ground: GroundSample, attributes: Attributes,
          yaw: F32, maximum_step: F32, sprinting: Bool,
          no_gravity: Bool, discard_friction: Bool, mode: Mode}

type Prepared is Data:
  Prepared{body: M.Body, requested: M.Vec3, friction: F32,
           acceleration: F32, maximum_step: F32, gravity: F.F64,
           air_drag_modifier: F.F64, discard_friction: Bool}
```

Block coordinates are signed Java 32-bit **two's-complement words stored in U32**, matching `F.from_i32` / `F.floor_i32`. The ground sample must come from the actual supporting-block-aware `getBlockPosBelowThatAffectsMyMovement()` contract, before movement; it is not universally `floor(position.y - 0.5)`. This module consumes that explicit resolved sample and does not pretend to own the support/world resolver. Attributes are the current resolved values, including modifiers and sanitization, rather than base values or stale LivingEntity speed. The oracle actually sets and reads Player's real AttributeMap and supplier; sprinting fixtures include the actual speed modifier.

The checked functions are:

```bend
prepare_checked(tables: L.Tables, body: M.Body, input: M.Vec3,
                context: Context)
  -> L.Tables & Result<&2,&2,Error,Prepared>

move_checked(prepared: Prepared, initial: List<&2,G.Collider>,
             step: List<&2,G.Collider>)
  -> Result<&2,&2,Error,M.Transition>

finish_checked(prepared: Prepared, movement: M.Transition)
  -> Result<&2,&2,Error,M.Transition>

travel_checked(tables: L.Tables, body: M.Body, input: M.Vec3,
               context: Context, initial: List<&2,G.Collider>,
               step: List<&2,G.Collider>)
  -> L.Tables & Result<&2,&2,Error,M.Transition>
```

`prepare_checked` returns the Tables owner on success and every failure. Admission precedes table lookup. Its Prepared body carries the accelerated velocity, and its requested displacement is that velocity. The caller keeps its earlier immutable Body until the complete transition succeeds; it must not install the Prepared intermediate state.

For an owned world, perform these steps:

1. Resolve the pre-move ground sample, current attributes, and supported context. Call `prepare_checked` and retain its returned Tables owner.
2. On `Done{prepared}`, obtain entity and initial block/border collision lists with `M.initial_entity_query` and `M.initial_block_query` using `prepared.body.box`, `prepared.requested`, and `prepared.maximum_step`.
3. Compute the initial baseline with `M.resolve(box,grounded,0.0,request,initial,Nil{})`, then obtain the exact second list with `M.step_query` and the same retained maximum step.
4. Call `move_checked(prepared,initial,step)`, which performs checked movement **and finishes gravity/drag**. Install only a successful returned Body at the simulation tick boundary.

`finish_checked` is available when integration already has a checked movement result and needs to apply the final phase once. Calling it after `move_checked` would apply gravity and drag twice. `travel_checked` combines the phases for a caller that already supplies complete ordered collision lists. The module never takes, copies, or replaces the owned world/registry arrays.

## Admission and unsupported modes

`Mode.NeutralDryAir` requires permission to simulate movement and local authority, no passenger/controller, no swimming, ability flight, fall flying, liquid, climbable or powder-snow behavior, no mob effects, loaded client chunks if applicable, unit block speed factor, suppressed bounce, ordinary non-omnidirectional drag, and no sneaking edge backoff. The caller must establish these facts from actual world/entity state.

Explicit rejecting modes are `Liquid`, `Swimming`, `AbilityFlight`, `Gliding`, `Climbing`, `PowderSnow`, `MobEffects`, `Passenger`, `UnloadedClient`, `NonNeutralBlock`, `NonAuthoritative`, and `EdgeBackoff`. Unsupported modes reject before table use. Grounding comes from the actual supplied Body and never from a separate Context flag.

Validation order is Context mode; finite yaw, ground friction `[0,1]`, finite nonnegative maximum step; current finite attributes; Body; input vector. Movement then validates both complete collision lists before clipping, and finite final state is checked after gravity/drag. Attribute admission uses movement speed `[0,1024]`, gravity `[-1,1]`, and friction/air-drag modifiers `[0,2048]`. These explicit finite-state rejection rules extend Java's raw numerical behavior and protect simulation state.

Errors are `UnsupportedContext{mode}`, `InvalidContext{field}`, `InvalidAttribute{field}`, `InvalidInput{field}`, and `MovementError{cause:M.Error}`. Context indices 0/1/2 mean yaw, ground friction, and maximum step. Attribute indices 0/1/2/3 mean movement speed, gravity, friction modifier, and air-drag modifier. The complete owner is returned with failed preparation and failed combined travel. Existing movement errors preserve their named component/field indices.

## Exact operation order

For grounded bodies, narrow the friction attribute to F32 and calculate:

```text
friction = clamp_f32(1f - (1f - sampled_block_friction) * modifier, 0f, 1f)
```

Every float operation rounds separately. Airborne bodies select `1f` without using the ground sample in the formula. Ground acceleration reads the current resolved Player movement-speed attribute and narrows it to float. If widened friction is **strictly greater than `.6d`**, it uses float:

```text
speed * (0.21600002f / ((friction * friction) * friction))
```

Otherwise it uses that speed directly. In particular `.6f` is slightly greater than `.6d`, so substituting a float comparison changes the branch. Airborne Player speed is `.02f`, or `.025999999f` while sprinting; movement-speed attributes are not used for this ordinary airborne acceleration.

The verified `get_input_vector` result is added to the existing exact binary64 velocity in XYZ order. This **accelerated velocity is the displacement request**. After exact Entity movement and neutral restitution, subtract current binary64 gravity from the returned Y velocity. `no_gravity` selects positive double zero. Gravity does not affect the displacement requested during this same travel call.

If friction is discarded, preserve returned X/Z and the gravity-adjusted Y directly. Otherwise narrow the air-drag modifier and calculate modified `.91f` horizontal and `.98f` vertical drag with the same float formula. Horizontal drag multiplies the **pre-move** friction sample by modified `.91f` in float before widening. Widen both final float multipliers to double, then multiply the components independently in binary64. Do not resample friction under the destination block or use invented fixed drag constants.

Position, AABB, dimensions, collision/ground flags, clipped displacement, step outcome, and position-application gate come from the movement phase. Finishing changes only velocity. CPU F32 primitives implement the Java float friction/acceleration/drag operations; F64 operations remain exact pure integer code. There are no GPU bangs, foreign gameplay helpers, unchecked laws, or compiler changes.

## Actual Java fixture and confidence boundary

The fixture subclasses actual `Player`, using its actual Player/Avatar/LivingEntity constructors, equipment, abilities, and registered default attribute supplier. The finite Level reuses the movement oracle's genuine Level constructor with official dimension, biome, and damage-type values. It returns actual stone, dirt, oak-plank, ice, blue-ice, and slime-block default states or air. Actual `BlockCollisions`, CollisionContext, and block shape methods enumerate/filter the colliders. These admitted states are non-fluid full cubes; collision lists and their order are observed directly.

`FixturePlayer` implements required abstract game mode as SURVIVAL, returns NONE for movement emission, returns true for suppressed bounce, and returns false for `isClientAuthoritative`. The last constant selects the declared locally authoritative server-side fixture through the **actual final Entity authority calculation**; ordinary Player's default server-side value is client-authoritative. This is a recorded return contract, not evidence about ServerPlayer/client replication. It keeps sneaking false, so Player edge backoff is inactive. The oracle asserts the supported guards and fails when they are not established.

The observers for below-position sampling, Player speed/flying-speed reads, `moveRelative`, `move`, and `recordMovement` record values and call their superclass. They do not replace any algorithm. **Player.travel, LivingEntity.travel/travelInAir and its acceleration helper, Entity.move/collide, attribute-value reads, LivingEntity.checkFallDamage, and EntityFluidInteraction.update/hasFluidAndLoaded checks all run unchanged.** Final expected Body fields are read after the complete travel method. The movement observer separately reads the requested velocity immediately before `super.move` and the Body immediately afterward, before gravity and drag. The actual private modified-friction helper is independently called for a supplemental friction observation; it does not compute the expected final Body.

Living fall handling asks `Level.getChunk` for fluid presence. The added fixture override returns actual loaded `LevelChunk` objects with all-air/no-fluid sections for **only** `EntityFluidInteraction.hasFluidAndLoaded`; an unexpected non-fluid use throws. Collision/friction storage is the finite solid map. The no-fluid section result is truthful for all admitted non-fluid solids, while this remains a declared instrumentation boundary rather than saved chunk storage. Other unrelated services retain throwing guards. Copied biome/damage constructor registries bind tags empty; blocks, entity types, and attributes use the original built-in registries. No real ServerLevel, world tick, actor traffic, saved chunks, data-pack tags, sounds, or hazards are claimed.

## Verification

```sh
python3 tools/reference_travel_probe.py
python3 tools/reference_travel_probe.py --verify-existing
python3 tools/reference_travel_probe.py --selftest
python3 tools/test_travel.py
```

The corpus contains **1,205 actual Player.travel calls**. Native outputs compare exact raw position, AABB, velocity, float dimensions, and major collision/ground flags. Each fixture also compares its prepared accelerated request/friction/acceleration and its exact post-move Body before gravity/drag. Cases cover grounded/airborne travel, six real full-cube materials, float friction/drag clamping, zero/subnormal movement speed, huge finite yaw, gravity/no-gravity, friction discard, actual sprint attribute modification, floor/wall/corner/ceiling/step behavior, tiny movement, signed zero, and 768 seeded finite cases.

The checked suite probes **58 rejection cases**, then performs a successful actual transition after each rejection to observe retained Tables ownership. Five laws pass the primary checker and independent BendTT kernel: rejected preparation retains Tables, no-gravity chooses positive zero, airborne friction bypasses the sample, discarded friction preserves horizontal velocity, and failed movement skips gravity/drag. These narrow laws do not establish full Player behavioral parity. The independent Java self-test repeats all actual executions twice and rejects corrupted expected outputs with and without a resealed checksum. Artifact/runtime/library/class/method hashes and the fixture's exact return contracts are recorded in `reference/travel.json` and `evidence/travel-reference*.json`.

Current native/kernel/build timings and hashes are in `evidence/travel-verification.json`; timings are verification workloads and do not establish a Minecraft performance advantage. Required continuation includes the actual supporting-block/friction/attribute resolver, Engine/owned-world integration, full Player input tick and jumping, actual ServerPlayer/world execution, effects and general restitution, liquid/swimming/flight/glide/climb, hazards, controllers, networking, and their authoritative branch state.
