# Cooking item and XP entities

This owner consumes actual `cooking_world_store.Effect.Drop` and `Experience`
values into affine, typed item/XP entity state. It does not merely retain spawn
intents. The first consumer is the live cooking effect facade and its Session
Sidecar. Session, storage, notification publication, and actor wiring remain
owned by the integration lead.

## Consumer API

Import `cooking_effect_entities_model.bend` as `E`,
`cooking_effect_entities.bend` as `D`, and
`cooking_effect_entities_clock.bend` as `Clock`.

- `E.State` owns the level RNG, process seed uniquifier, entity ID cursor,
  next section insertion order, and `List<&1,E.Entity>`.
- `E.Entity{record:E.Record}` is the affine entity owner. `E.Record` contains
  actual item or XP state. `E.Common` includes dimension, ID, UUID, constructor
  RNG state, position/motion/previous fields, rotation, first-tick/tick count,
  removal, accessibility, and section insertion order. Items retain complete
  `Inv.Slot` component identity, age, pickup delay, health, bob, thrower and
  pickup target. Orbs retain value, age, health, count and following reference.
  Nullable references use `E.Uuid{most,least}`. These are spawned-state records,
  not a claim that all later Entity/LivingEntity callbacks are installed.
- `E.inspect(state) -> State & View` returns a complete immutable snapshot
  beside the sole owner; `E.install(view)` reinstalls the owner.
- `E.Context{items:campfire_authority_items.Context,
  limits:E.Limits{spawn_steps,rejection_steps,id_steps},reserved_ids}` uses real
  loaded item definitions, initialized defaults and component admission.
  Budgets are caller-selected resource bounds, not game catalog or stack limits.
- `D.apply(~Geometry,~place,geometry,context,effect,state,times)` returns
  `State & Result<Error,List<Bits64>>`. Its timestamp list supplies actual
  constructor `nanoTime` values; the result retains unused tickets.
- `D.deliver(~Geometry,~place,geometry,context,effects,state,times)` returns
  `State & Outcome{pending,status,remaining_times}`. Successful effects commit
  in order. On refusal, the current effect and exact ordered suffix remain;
  the current effect's whole original owner and RNG survive. Already committed
  prefix effects must not be replayed.
- `Clock.apply(~Geometry,~place,geometry,context,effect,state)` returns
  `IO(State & Result<Error,Unit>)`. It obtains a native monotonic nanosecond
  ticket only when an actual new constructor requires one. A merge or empty
  drop does not obtain a constructor ticket. Candidate replay does not advance
  the authoritative RNG/factory/IDs until the complete effect succeeds.

`place` has the exact checked type:

```text
Geometry -> String -> vanilla_entity_fields.Vec3
  -> Result<&2,&2,E.Error,vanilla_entity_fields.Vec3>
```

It returns the XP constructor's **final base position**, after the actual
world's `noCollision`/`findFreePosition` handling. It must refuse unresolved or
unloaded geometry explicitly. `cooking_effect_geometry*` supplies the real
Core-derived adapter in its separately owned lane. Java checks an orb's
0.5-wide, 0.5-high initial bounding box. When obstructed, the search center is
base position plus `(0,0.25,0)`, the search shape is a 0.5 cube at that center,
and `findFreePosition` receives `(entity,shape,center,0.5,0.5,0.5)`. Its optional
result is converted back to base position by subtracting 0.25 from Y; an empty
optional keeps the original position. Construction here uses the cooking XP
zero-direction award path.

`Dirty`, nonzero `BlockUpdate`, and nonzero `BlockChange` belong to the facade's
real block-entity/comparator/block-update/game-event publishers. This consumer
returns their exact suffix instead of silently claiming publication. Zero
notification counts and already-applied `OwnerReset` consume no entity/RNG
state. The live facade can use `Clock.apply` for each released item/XP effect
and its own publisher for the other effects, advancing the pending queue only
on success.

## Observed 26.3 behavior

The installed Java `Containers.dropItemStack` always consumes three **level**
`nextDouble` draws, including empty drops. With item width 0.25, the coordinate
span is 0.75; X/Z additionally receive 0.125, Y does not. Each nonempty fragment
uses `nextInt(21)+10`, limited by the remaining count, and six further level
`nextDouble` draws for three triangular velocities with spread
`0.11485000171139836` and mean `(0,0.2,0)`. They are not Gaussian draws.

The actual `ItemEntity` constructor has a separate legacy RNG created through
`RandomSource.create()`. It consumes UUID, bob, yaw and two initial motion
samples even though Containers subsequently replaces that initial motion.
New items have age 0, pickup delay **0**, health 5 and null thrower/target.
The RNG factory advances the process seed uniquifier by multiplication with
1181783497276652981 and XORs that result with `System.nanoTime`; UUID masks and
float operation ordering are preserved in Bend. The initial uniquifier is
8682522807148012, available through `E.java_initial_uniquifier()`.

Cooking XP uses the actual F32 product/floor/fraction and a level `nextFloat`
only when its fraction is nonzero, including NaN. The shared verified furnace
XP calculation is reused. Removal awards occur at block center. Positive
amounts decompose into 2477, 1237, 617, 307, 149, 73, 37, 17, 7, 3 and 1. Every
value first consumes level `nextInt(40)` to try nearby matching orbs. A match
increments count and sets age to zero without allocating an entity, drawing
constructor RNG, acquiring time, or changing UUID/ID. Signed wrapping ID
subtraction and Java remainder semantics are retained.

Merge selection follows actual accessible `EntitySectionStorage` order:
signed ascending section X, packed unsigned Z/Y order within X, then insertion
order inside the section; candidates must intersect the exact query AABB,
match dimension/value/residue, and be accessible and not removed. Existing
records' accessibility and section order must be updated by their later
residency/movement consumer. Only authoritative registered IDs belong in this
owner and `Context.reserved_ids`; despawned records must leave the registration
owner. The ID cursor skips wrapping zero and occupied/reserved IDs.

## Ownership, persistence, and remaining live work

The retained `View` contains the complete implemented record and RNG/cursor
state required by the live durable codec. The separately owned
`local_player_effect_entities_codec` is the internal snapshot codec; this lane
has not edited or admitted storage/Session framing. Both normal mutation and
refusal preserve the single owned entity state.

`State.level_random` represents one actual ServerLevel's RNG. The current
playable actor uses the overworld. When additional ServerLevels or entity
producers coexist, their level RNGs must remain distinct while joining one
shared process seed factory and ID allocator; independently creating a fresh
factory/cursor per subsystem would be incorrect. `reserved_ids` joins other
registered entities and does not confer another allocator owner.

The integration lead still owns installation into the live Sidecar/Session,
durable queue/snapshot framing, and publication of released notifications.
Subsequent real item/orb world ticks, collision/fluid motion, item merging,
age/despawn, pickup and inventory/XP transfer, visual/audio presentation,
network registration and residency updates must consume these actual records.
Those consumers are not claimed installed by this spawn lane.

## Verification

Confidence is high for the checked spawn contract and observed cases; full
entity gameplay and final live integration are separate work.

- `python3 tools/reference_cooking_effect_entities.py` observes actual pinned
  Java Containers/ItemEntity/ExperienceOrb receivers. It uses real
  `EntitySectionStorage` query order and explicitly declared world geometry
  responses. It neither substitutes entity constructors nor overrides their
  RNG. Initial legacy seeds and constructor timestamps are recovered from the
  observed final seeds and checked against the real `nanoTime` interval.
- `python3 tools/test_cooking_effect_entities.py` compares 15 scenarios and 61
  final records: both level RNG implementations, empty/one/99/64-item drops,
  patched full identity, ordered actions, XP rounding/NaN/negative amounts,
  all denominations, same-section/packed-section merging, and relocation.
  UUID, RNG/factory/cursor state, position/velocity and rotations match by raw
  bits. `evidence/cooking-effect-entities-native.json` records the result.
- `python3 tools/test_cooking_effect_entities_guards.py` checks ten native
  rollback, component refusal, unloaded placement, pending suffix, signed ID,
  real monotonic clock and clock-driven multi-fragment guards. Its foreign
  boundary is explicitly recorded in
  `evidence/cooking-effect-entities-guards.json`.
- Eight connected laws in `cooking_effect_entities_laws.bend` passed ordinary
  checking and the independent BendTT kernel, with unchanged checked terms and
  no exclusions. The laws cover complete-owner rollback, failed ordered suffix,
  missing entropy, zero inner work, and orb merge fields/RNG/factory/cursor.
  They do not prove arbitrary Java parity, FFI behavior or installed gameplay.
  `tools/cooking_effect_entities_proof.mjs` exports those exact checked roots;
  `evidence/cooking-effect-entities-proof.json` records hashes and commands.

The installed bundled compiler crossed the bounded 2 GiB process-tree limit
while emitting this narrow graph. A read-only diagnostic compiled the identical
original checked book through the pinned source compiler under Node in 7.22 s
and 973 MB sampled RSS. The production native checks therefore execute that
unchanged compiler API with a 1.5 GiB Node heap cap, then compile its actual C
with Clang. Transitive source hashes and compiler hashes are recorded. No
compiler checkout was edited, no declaration was substituted, and this does
not claim the installed bundled emitter stayed below its bound. A GC/host difference is an inference from the bounded measurements; no exponential source expansion was demonstrated. The native
clock's only host implementation is full 64-bit `CLOCK_MONOTONIC` nanoseconds
through the runtime's `io_tick()`. The JavaScript fallback follows the browser's
exposed monotonic timer precision and has no native-parity receipt here.
