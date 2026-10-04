# Block-inside stuck receiver producer

This slice produces the state consumed by the existing player-motion stuck phase. It implements pinned Java 26.3 web and sweet-berry callbacks, ordered callbacks over actual Core block states, and the exact stationary block-intersection query. It does not enable cobweb or berry gameplay in the saved four-state client. The moving swept traversal and the root runtime receiver join are separate dependencies.

## Pinned behavior and timing

`LivingEntity.aiStep` calls `travel` before `applyEffectsFromBlocks`. A callback therefore supplies the multiplier for the next `Entity.move`. The multiplier survives ticks with no eligible callback. Each eligible callback replaces it; multiple callbacks do not multiply their effects together.

`WebBlock.entityInside` applies `(0.25, double(0.05f), 0.25)` or, for a living entity with the actual Weaving effect, `(0.5, 0.25, 0.5)`. `SweetBerryBushBlock.entityInside` returns immediately for nonliving entities, foxes and bees. Other living entities receive `(double(0.8f), 0.75, double(0.8f))` at every berry age.

The inherited `Entity.makeStuckInBlock` resets fall distance and replaces the multiplier. `Player.makeStuckInBlock` suppresses both changes while `abilities.flying` is true, but always invokes `tryResetCurrentImpulseContext`. That gate clears the impact position only if the grace timer is exactly zero; a nonzero timer, including a negative Java-int payload, preserves both fields. Producer state stores the raw timer word and optional position, rather than treating an impulse reset as unconditional.

The production constants are exact raw binary64 encodings observed from the original methods:

| Value | Raw double bits |
| --- | --- |
| Web X/Z | `3fd0000000000000` |
| Web Y, promoted `.05f` | `3fa99999a0000000` |
| Weaving X/Z | `3fe0000000000000` |
| Weaving Y | `3fd0000000000000` |
| Berry X/Z, promoted `.8f` | `3fe99999a0000000` |
| Berry Y | `3fe8000000000000` |
| Stationary deflation, promoted `1e-5f` | `3ee4f8b580000000` |
| Berry hurt threshold, promoted `.003f` | `3f689374c0000000` |

The reference contains 142 cases and 254 steps. Two independent JVM runs agree exactly. It includes normally constructed players, nonliving entities, real foxes and bees, original effect/equipment setters, direct original block callbacks, and public stationary dispatch. There are 225 observed entity-inside shapes, all identical to the original `Shapes.block()` for the supported callback states, and 155 observed actual impulse-reset calls. Ordinary and resealed corruptions are rejected. See `reference/player_block_inside_stuck.json` and `evidence/player-block-inside-stuck-reference*.json`.

## Production API and ownership

`src/player_block_inside_stuck.bend` defines:

```text
Receiver{multiplier: M.Vec3,
         impulse: Impulse{grace_time: U32, impact_position: Maybe<M.Vec3>}}
State{world: Core.World, registry: Registry.Registry,
      receiver: Receiver, history: H.State, tail: List<State>}
```

`callback_checked(receiver, history, facts, level, resolved)` executes the actual admitted callback branches and returns a candidate receiver/history. The facts distinguish Player, OtherLiving and OtherEntity; the Player facts carry flying and Weaving observations. OtherLiving carries the actual fox/bee exclusion observation. Both fields must come from the actual receiver rather than equipment or a render state.

`query(state, request)` reads each admitted contact through `Core.read_block`, decodes its actual state ID through `Registry.decode`, and evaluates the callback. The registry is the general loaded metadata owner; the query does not use the four-state visual palette or assume that movement collision describes entity-inside collision. Contact positions carry their dimension. The caller supplies contacts in the original traversal order, with a `BlockIntersection`, `NoBlockIntersection`, or `UnresolvedIntersection` admission. The traversal service must establish the original entity-inside intersection and deduplication. This is an explicit service boundary, not an assertion that supplied contacts were geometrically verified by this module.

The shared Core reader now uses `section_map_read` so a read cannot reorder a queried hash-collision bucket through pop/set reinsertion. This was a real shared-service retention defect exposed by the complete raw-owner observer. See `docs/SECTION_MAP_READ.md`; Core integration is root-owned.

Candidates remain separate immutable Data until every read and callback succeeds. Failure restores the original receiver and owned fall history, retaining the complete world, registry and arbitrary affine tail. Missing sections remain failures; unloaded positions do not become air. Query fuel is an explicit work budget. Unknown intersections, unknown callback classes, invalid state metadata and required damage services refuse the entire candidate. The supported neutral callbacks are air, stone, dirt and oak planks. All other classes besides cobweb and sweet berry are refused.

`stationary(state, request)` implements the stationary `Entity.checkInsideBlocks` slice: deflate the actual box by `double(1e-5f)`, floor its endpoints, enumerate X fastest, then Y, then Z, and read the actual loaded states. It uses the original full entity-inside shapes independently observed for the admitted classes. The removed/noPhysics/alive gates suppress reads. This entry is for a genuinely stationary traversal. Passing the final box of a moving entity is not equivalent to the moving swept traversal.

`src/player_block_inside_stuck_motion.bend` provides actual consumers over `MH.State`:

```text
after_contacts(motion, receiver, request)
  -> MH.State & Receiver & Result<Error, Observation>
after_stationary(motion, receiver, request)
  -> MH.State & Receiver & Result<Error, Observation>
```

The adapter extracts the sole Core/Registry/history owners and restores the actual world/body view, support, minor state, cache and arbitrary MH tail. Its stationary entry requires exact raw-bit equality between the request box and the current body box. `BodyMismatch` retains the complete motion owner and receiver.

## Root runtime join

The named existing client dependency is `local_phase_runtime.reset_stage_travel_started`, whose `TH.Hooks` still supplies a literal zero multiplier. The root owns that runtime, LocalPhase/minor/session records, the provider, entries and persistence integration.

The concrete join is:

1. Store the new Receiver in the actual transient player/runtime owner, initialized with `empty()`: positive zero multiplier, zero grace and no impact position. It is not another fall-history or body owner.
2. Before the existing `TH.ability_travel_with_reset_checked`, supply `multiplier(receiver)` to its Hooks.
3. Retain the original Receiver on any failure of the enclosing player transaction. After a successful normal-physics stuck phase, use `travel_succeeded(receiver)`. It clears only an active multiplier under the exact existing `M.stuck_threshold()` gate, preserving impulse fields and retaining every inactive raw multiplier bit, including signed zero.
4. After successful travel, before committing `reset_stage_traveled`/`player_finished`, invoke `after_contacts` with the actual movement's checked block traversal. Invoke `after_stationary` only for a genuinely stationary traversal. Retain its returned history and Receiver for the next movement.
5. Keep this callback join inside the existing root rollback transaction. A later player-finish or provider failure must also restore the original motion/receiver, not expose a partially consumed or partially produced multiplier.

This slice does not add receiver fields to the root record or save codec. A consumer that constructs a new receiver uses `empty`; reconstructing other lifecycle states must preserve or initialize the actual transient fields according to that lifecycle's Java contract. Codec/lifecycle integration has not been inferred from a fabricated persistence field.

The impulse grace timer is stored for the exact callback reset gate. The LivingEntity timer tick and impulse-producing lifecycle are separate consumer responsibilities; this slice does not decrement that timer or create an impulse.

## Explicit damage and traversal boundaries

For a real `ServerLevel`, nonzero-age berry bushes can call `hurtServer` after the setter. The movement is the observed known movement for a client-authoritative receiver, otherwise `oldPosition - position`. Damage is required when horizontal squared movement is positive and either absolute horizontal component reaches `double(.003f)`. Flying does not suppress this damage branch. The module admits a server callback only when the exact predicate establishes no damage; otherwise it returns `ServerBerryDamageRequired` with whole-owner retention. Health, damage-source/effect semantics and a real ServerLevel damage observation remain separate dependencies. ClientLevel and ordinary non-ServerLevel callbacks have no such branch.

The full Java dispatcher also handles moving sweeps, movement step limits, deduplication, fluids, fire/freezing collectors and ground `stepOn`. This module is the admitted stuck callback producer, not a replacement for those services. The current saved client catalog remains air/stone/dirt/planks; no cobweb/berry state installation, render/material integration, swept dispatch or visible gameplay acceptance is claimed here.

## Verification

`src/player_block_inside_stuck_laws.bend` states 15 production laws. They cover exact replacement and exclusion behavior, flying/impulse retention, grace-dependent reset, complete arbitrary owner retention at budget/world/intersection/callback refusals, preservation of affine environment owners on commit, transient consumption, and the actual MH adapter's body-mismatch rollback. A callback-service premise is explicitly bound to the real `callback_checked`, and earlier speculative results are discarded on its refusal.

The independently checked final source export retains every original declaration map, checked source type and checked proof body, selects the 15 production roots without altering them, and has zero exclusions. The final check includes the actual shared Core reader join. IR: 3,550,707 bytes. Ordinary/source-export/kernel times: 5.121/35.960/0.673 seconds. See `evidence/player-block-inside-stuck-proof.json`. Original successful receipts before the raw-constant refinement and shared reader join remain in ignored build directories.

Reproduction:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_block_inside_stuck_probe.py --verify-existing
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_block_inside_stuck_proof.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_block_inside_stuck.py
```

The prepared native harness calls actual production reducers. Its world/registry retention observations include raw registry slots/names, every section cell and trie bucket, clocks, pending operations and events, so a successful canonical serialization cannot mask rollback corruption. Two bounded build attempts ended before native comparisons; their retained diagnostics drove removal of an unrelated client graph and boxing of observer continuation state. Native execution remains pending and its result will be recorded separately in `evidence/player-block-inside-stuck-native.json`; the root live consumer and visible acceptance remain separately tracked.
