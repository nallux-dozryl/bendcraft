# ItemEntity tick authority (pinned Java 26.3)

The new `item_entity_tick*` modules implement the ordinary authoritative server tick of the existing `cooking_effect_entities_model.Item` record. All simulation and RNG transitions are Bend. Java observes the installed pinned receiver; Python builds fixtures and compares results. This lane does not implement XP ticking, player pickup, actor scheduling, packet/audio delivery, rendering or a durable writer.

## Actual consumer API

Import `item_entity_tick_model` as T and `item_entity_tick_scene` as Scene.

```
T.State{entities:E.State,runtimes:List<RuntimeEntry>,sound:Maybe<random.Source>}
Scene.tick_id(Context,id:U32,common:Bool,State)
  -> State & Result<T.Error,List<T.Publication>>
```

This is the world-consumer entry point. It requires exactly one entity record and runtime for the ID. It preserves the level RNG, constructor seed factory, global ID cursor, next section-order cursor and unrelated records. Neighbour merges update both actual records in the sole entity state, retaining original query order through the checked section/order keys. Removed records and runtimes remain until the real removal publisher accepts. A removed record refuses scheduling, so the actor must skip it while delivering removal. `common=True` performs the real scheduler's `commonTick` before `ItemEntity.tick`; use False only after the caller already performed that phase. Both previous-position vectors and previous look angles are initialized from the current values in that phase.

`Tick.plan(Context,Snapshot,records)` provides a pure plan for composition with a broader owner. `Tick.tick(Context,Owner)` is an isolated owner entry point; it explicitly disables complete neighbour-query admission and refuses a due eligible merge. It cannot fabricate an empty world from an absent record collection. The actual world consumer uses Scene.

## Runtime and recovery seam

`Runtime` contains Physical (no-gravity/no-physics/bounce suppression, collision flags, stuck vector); BaseState (invulnerability/boarding counters, previous water/eye-water/powder-snow flags, sprint/swim/freezing/silent flags, last known position and speed); both fluid accumulators and eye flags; pending and final movement lists; and the actual support cache. `Context`, `Runtime` and `Cell` recursive tail fields must be `[]`; those fields keep native compiler continuations bounded and have no gameplay meaning. `Cell` begins with the actual registered block-state ID, followed by position, fluid/tag/height/flow/collision/physical-property observations.

`Fields.fresh_runtime()` is valid only at an actual fresh item-constructor join. It must not replace missing restored runtime. Recovery must preserve the complete Runtime, each E.Record (including item component identity and entity RNG), both entity-state factory/cursor fields, and the sound stream. No entity model or existing storage format was changed in this lane.

Java's `Level.soundSeedGenerator` is separate from `Level.random`. Vanilla constructs it with `RandomSource.createThreadSafe()` (the legacy LCG algorithm with thread-safe seed ownership). A splash consumes one `nextLong` from that authority. The caller must bootstrap it from the actual seed-factory/entropy owner once and persist the resulting source separately. The pinned Level constructor derives `randValue` with createThreadLocalInstance().nextInt() at bytecode offsets19/22. That temporary SingleThreadedRandomSource is seeded from Netty ThreadLocalRandom.current().nextLong(), and does not consume Minecraft’s unique-seed factory. It then initializes `random` with create() at37 and the separate sound stream with createThreadSafe() at44; both call Minecraft RandomSupport.generateUniqueSeed, before later item constructors. Bootstrap must spend the real Minecraft factory/time authority for those latter sources in that order, while the auxiliary draw requires its own actual Netty entropy observation. Restore must retain existing streams; it must never substitute `E.State.level_random`. A missing sound stream refuses the complete scene transaction. A silent splash still consumes its entity pitch/particle RNG and emits particles and the SPLASH event, while preserving the sound stream.

## Actual Core observation adapter

Load the physical `reference/item_entity_tick_profiles.json` with `Profiles.load(text)` once. Its entire UTF-8 file is checked against the recorded SHA before rows can be trusted. The 307 initialized dry states cover the existing four-state Core plus its 101 dry slab families; they are actual initialized Java physical metadata, not a product fuel/recipe table or a world-state substitution.

```
World.capture(Game.Engine,Slab.Catalog,World.Request)
  -> Game.Engine & Slab.Catalog & Result<T.Error,T.Context>
World.capture_world(client_world.State,Slab.Catalog,World.Request)
  -> client_world.State & Slab.Catalog & Result<T.Error,T.Context>
```

These call the existing actual `slab_collision_world` read transaction, retain both affine backing owners on every path, preserve all observed air cells, and convert real full/slab voxel shapes. Request carries the actual geometry request/environment and coverage, initialized item authority, admitted physical profiles, actual entity collision boxes, minimum Y, server/fast-lava/load/query-completeness facts, lifecycle observations and budgets. The block scan has a halo. Unknown or wet Core state IDs refuse; they never become air. Raw Context is an immutable observation-provider interface, not permission to invent missing facts. The exercised providers admit ordinary dry/slab block callbacks and actual neutral water cells. Fence/wall/custom callback admission requires a further provider/receiver join; current Core capture does not claim it.

The actor must mark `entity_queries_complete` only when E.State contains the complete actual item-query owners and their accessibility/section ordering. Collision boxes must come from the actual entity-collision query. Large fall-resetting motion requires the actual `fall_clip` observation. Moving into a different packed `SectionPos.asLong` key currently refuses because actual destination visibility/insertion-order callbacks are not joined; the actor must supply that manager authority before such movement is admitted. The predicate follows actual floor/cast, 16-block sections, and the X/Z22-bit and Y20-bit masks. The owned merge key sign-extends masked X before the existing comparator, matching signed packed-long ordering. Retaining an old section ordinal would change later neighbour-query order. Portal/mount/sprint/freezing/active-fire services, nonneutral inside/step/fall callbacks, missing cells, incomplete queries, exhausted budgets, client network/local-authority movement and dimension mismatches refuse the whole owner. Those services are remaining integration dependencies, not successful no-op ticks.

The precise migration seam is `Tick.after_move -> moved_ready -> section_ready`, immediately before `section_merge` and the neighbour query. A manager provider must receive the original registered key/Common, proposed Snapshot/position/bbox, dimension/ID, complete immutable query records, current next-section cursor and actual destination visibility/membership facts. It returns updated Common accessibility/order, cursor and a staged membership/callback journal; it owns ID/section facts rather than a duplicate E.State. Existing destination sections retain their real status; creation requires actual chunk visibility. The actor commits the manager journal/cursor only after the complete Scene and separate sound plan succeeds. Removal callbacks must leave actual membership before subsequent scheduling/query, while record/runtime tombstones remain until publication accepts. The reserved `entity_section_membership*` lane provides this authority. Its actual ordered query is the future bridge into a fixed ordered neighbour-ID list; the current shared orb query module is not modified.

## Transitions and publications

The implementation preserves signed pickup-delay and age sentinels/wrap, empty-item early discard, ordinary gravity and buoyancy, two fluid observations and actual current normalization, noCollision/nearest escape draws, actual voxel movement clipping, support selection, restitution/drag/speed factors, fall accounting, movement history and age-based despawn. Merge admission uses shared initialized-default reconstruction and exact effective component equality; target UUIDs gate merging, thrower UUIDs do not. The neighbour survives equal counts, minimum age and maximum delay follow the surviving stack, and transfer is capped at 64 even for a genuine maximum-99 patch.

Publications carry exact particles, SeededSplash position/volume/pitch/high-speed choice/seed, SPLASH position, and GroundEvent position/supporting BlockPos/state ID. Removed, Synced and Bounce are actor journals; Synced describes a flag transition. Delivery must remain in the real actor/world transaction. Pickup remains the independent `item_entity_pickup*` owner; unwrap/pass/rejoin E.State while preserving the tick Runtime and sound owner.

## Evidence and practical boundary

Commands:

```
python3 tools/reference_item_entity_tick.py
/Users/chuah/.bend/bin/bend tests/item_entity_tick.bend --check-only
python3 tools/test_item_entity_tick.py
python3 tools/test_item_entity_tick_profiles.py
python3 tools/test_item_entity_tick_proof.py
python3 tools/reference_item_entity_tick_sections.py
python3 tools/test_item_entity_tick_sections.py
```

`reference/item_entity_tick.json` pins installed JAR/library identities and observes actual `ItemEntity.tick`, `commonTick`, private `tryToMerge`, normal Entity constructors, real chunks/block collisions and entity-section storage. Fixture-only I/O sinks capture Java events; no host timer, movement or merging algorithm exists. Targeted cases cover ordinary/disabled gravity, signed sentinels, empty discard, despawn, stone/slab landings, collision escape, stationary ground, still/flowing/diagonal water, audible/silent splash and component/target-sensitive merges. Native comparisons retain full effective component maps, all observed motion/RNG bits, ordered effects and runtime fields. Seven complete owner refusal cases and two scene-commit checks additionally exercise the real Scene functions, including missing sound and removed scheduling. The physical loader is checked natively on all 307 newly observed metadata rows and a one-byte append refusal.

The changed section closure independently observes 33 actual Java packed-key cases and natively checks both equality and signed packed-long order, including negative/zero boundaries, integer saturation/NaN and masked-key wrapping. It also checks the actual False section branch through Scene.committed, retaining the full entity/runtime/RNG/factory/cursors/sound. The 24-case main tick/native evidence retains its original source snapshot before this additive refusal/key closure; the changed narrow evidence pins the final production sources. No unchanged tick corpus replay is claimed.

The proof target contains 12 connected ordinary laws and 11 selected independent-kernel laws. It checks complete entity/runtime/state refusal ownership, sound-refusal ownership, early empty discard, signed sentinels/wrap, negative delay, complete blocked merge, equal-count transfer conservation/identity, the ungrounded support branch and complete ownership when section-migration authority is unavailable. The full affine Core refusal law passes the source checker; its independent export traverses the existing shared `Nat.show` recursion limitation and is explicitly excluded. Original declaration maps and checked proof/type/body terms remain unchanged in selected export. These laws do not establish the Java specification, arbitrary callback services, durable-save recovery or release performance.

The bounded correctness build uses clang `-O0 -fomit-frame-pointer`. Apple clang's earlier optimized backend attempt failed with a live-register/prologue diagnostic; release optimization remains unverified. Runtime/cell recursive tails resolve the original native continuation-arity limit without editing Bend or replacing simulation with host code. Final check counts, commands, measured resource use and exact source pins are in `evidence/item-entity-tick-native.json`, `evidence/item-entity-tick-profiles.json` `evidence/item-entity-tick-proof.json` and `evidence/item-entity-tick-sections.json`.
