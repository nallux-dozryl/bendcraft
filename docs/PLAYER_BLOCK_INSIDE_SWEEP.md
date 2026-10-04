# Moving block-inside traversal and retained callback receiver

The new `player_block_inside_sweep*` modules implement the ordered moving traversal used by pinned Minecraft Java 26.3 `Entity.checkInsideBlocks`. They query the actual owned Core world and general Registry, then reuse the committed stuck callback producer. They preserve the stationary producer and shared section reader. The live saved client still uses its air/stone/dirt/planks palette and has not joined this receiver or movement queue; no cobweb or berry gameplay is established by this slice.

## Actual original observations

`tools/reference_player_block_inside_sweep_probe.py` invokes the installed pinned game's original `BlockGetter.forEachBlockIntersectedBetween`, `Entity` moving dispatcher, and `AABB.clip`. Expected traversal is captured from those methods, rather than computed by a host replacement. Original visitor calls, ordered world reads, collector steps, callbacks, receiver/fall/impulse observations and final movement lists are retained in the independent fixture.

The final fixture has 143 cases and 182 steps. Two independent JVM captures agree exactly. It includes 59 direct walks with 959 visitor calls (955 accepted and four rejected by the original visitor), 117 entity sweeps with 1,656 actual reads and 986 callbacks, six AABB geometry observations, six appended mixed-air/repeated/packed-key-alias cases, and eight original ready-endpoint bridge/zero boundary cases. Every original case from the previous 135-case capture remains entirely unchanged. The final fixture SHA-256 is `12a08395c05c5401d68637d97f9e13f64ebf9633b02bb7d842dc924c476d2c28`; case checksum is `e2e858dcdc936f9a5c2d02fc95f4b93eb0827faffaf91768a3d373441117f16c`. Six resealed corruption controls fail validation. Class, jar, runtime, library and generator pins are recorded in `evidence/player-block-inside-sweep-reference*.json`.

The traversal preserves these consequential original distinctions:

- A movement retains its `from`, `to`, and optional **original axis-dependent request**. The original request determines Y/Z/X versus Y/X/Z decomposition; it cannot be reconstructed from the collision-resolved displacement.
- Each movement gets 16 visitor step levels. This is a successful vanilla traversal limit, not a limit of 16 block reads. A segment consumes its last accepted step plus one, including the original default when no visit is accepted. Later nonzero axes are still attempted with an exhausted allowance. An exhausted movement also performs the original one-step stationary endpoint fallback.
- Tiny movement uses the squared float `1e-5f` threshold and X-fastest endpoint enumeration. Moving traversal enumerates the translated initial box, uses the original furthest-corner permutation and DDA/clip crossing order, then visits new endpoint positions. Directional ranges use the third chosen axis fastest. Equal crossing times select Z, then Y, then X.
- Each segment has a local packed-position set that includes air. The entity dispatcher has a second packed-position set shared across all segments and movements. It reads and decodes the actual state before checking the second set. A repeated non-air callback is skipped; the repeated read remains observable. Air, cave air and void air do not reserve an entity-wide callback key, including when their packed key aliases a later cobweb.
- Position-set equality follows `BlockPos.asLong`: 26-bit X/Z and 12-bit Y masks. Query coordinates themselves remain the complete signed int words. The mask is not applied to Core positions.
- The endpoint box is constructed from the movement endpoint and actual float width/height, then deflated by promoted `1e-5f`. The callback's inside Boolean is `far || endpointBox.intersects(cell)`. For independently observed `Shapes.block()` entity-inside shapes, original identity comparison admits the callback independently of that Boolean. The Boolean is not an admission gate.

`player_block_inside_sweep_clip` preserves the original strict X/Y/Z plane tests, double epsilon, arithmetic order and strict earliest hit. No general shape is substituted with a cube. The owned query admits only independently established full entity-inside shapes with empty fluids: stone, dirt, oak planks, cobweb and sweet berry, plus all three original air classes. Every other class refuses with `UnsupportedInsideShape`.

## Production interfaces and ownership

```text
S.Movement{from: Vec3, to: Vec3,
           axis_dependent_original: Maybe<Vec3>}
S.plan(movements, width, height, traversal_fuel) -> S.Plan

W.Request{facts: P.Facts, level: P.Level,
          removed, no_physics, alive,
          width, height, movements,
          traversal_fuel, read_fuel, tail: []}
W.query(state: P.State, dimension, request)
  -> P.State & Result<W.Error, W.Observation>

SM.after_movements(motion: MH.State, receiver: P.Receiver,
                   dimension, request)
  -> MH.State & P.Receiver & Result<SM.Error, W.Observation>
```

`P.State` owns the sole Core world, Registry, receiver, fall-history state and arbitrary affine tail. Every visited coordinate goes through the actual `Core.read_block` and `Registry.decode`. The read therefore preserves actual section-map collision buckets through the committed `section_map_read` join; missing sections and invalid registry states remain refusals.

All callback changes and ordered trace prefixes remain immutable speculative Data until the whole query succeeds. A late world, registry, unsupported shape, callback or work-budget refusal discards them and retains the original receiver and history. A deferred invalid later movement or traversal failure is reported only after preceding visits are queried, so an earlier real read/callback failure wins. Successful commit changes precisely the returned receiver and history while retaining the world, Registry and affine tail. Observations include all read identities, prior collector step/dedup state, and admitted callbacks.

`traversal_fuel` and `read_fuel` are checked service work budgets. Their exhaustion refuses the transaction; they are separate from the original successful 16-step limit. Finite coordinate floors outside signed-I32 representability also refuse. Java's saturated double-to-int behavior outside that admitted domain is not implemented. Signed raw cell increments and original wrapped upper-cell bounds are retained inside the admitted domain.

Removed, noPhysics or initially dead receivers perform no geometry work or reads. The admitted callback slice cannot change alive status. Actual damage/collector effects that can change receiver lifecycle require additional services.

The actual MH adapter extracts the sole world/Registry/history owners through the committed `PM.extract`. Its frame retains the complete body, yaw/pitch, palette, region, cache, support, minor state and arbitrary affine MH tail. It requires exact raw float equality of request width/height with held dimensions, the original squared-distance bridge threshold between the final ready endpoint and held body position, and exact raw `ServerLevel.current_position` equality with that position. Any binding refusal restores the entire original owner and receiver. An empty ready list does not invent a movement; the caller must supply the original public dispatcher's fallback records when that dispatcher would create them.

`player_block_inside_sweep_travel` supplies the named retained-TH consumer directly. `travel_record(TH.Outcome)` and `reset_record(TH.ResetOutcome)` read the actual prepared start, `LM.Outcome.backoff.corrected`, resolved displacement and original `position_changed` flag. A refused position change yields no record. An admitted record retains the original post-backoff request and computes the raw endpoint as original `Vec3.add(from, displacement)`, rather than copying a possibly numerically-equal retained Body position. `ready(pending, oldPosition, currentPosition)` preserves the ordered input queue, supplies old-to-current fallback when empty and appends a no-axis-original bridge only above the original squared float epsilon. Original observations show no bridge at exact equality, and a queued `-0` endpoint can remain unequal in raw bits to a held `+0` body. Queue insertion and the original 100-entry coalescing remain outside this helper.

## Berry receiver input

`player_block_inside_sweep_berry.ReceiverInput` explicitly stores the original callback receiver observations:

```text
ReceiverInput{client_authoritative, known_movement,
              old_position, current_position}
server_level(input) -> P.Level
damage_movement(input) -> Vec3
damage_required(input) -> Bool
```

For a client-authoritative receiver, the actual known-movement service is selected. That service can delegate to its controlling Player; it is not necessarily the current velocity, movement queue or swept displacement. Otherwise the actual old position minus current position is selected. The unused vector branch remains independent, including arbitrary nonfinite payloads. The exact existing horizontal predicate uses promoted `.003f` and positive horizontal squared movement. Flying suppresses the player's setter but does not suppress the berry damage branch.

This API supplies inputs to the committed checked callback. It does not invent health or a `ServerLevel`. A mature server berry requiring `hurtServer` returns `ServerBerryDamageRequired` and retains the whole owner. The Java sweep fixture uses a plain Level and empty fluids; actual ServerLevel damage execution remains unobserved and unimplemented by this slice.

## Named real consumer join

The existing consumer is `local_phase_runtime.reset_stage_travel_started` and `reset_stage_traveled`, around `TH.ability_travel_with_reset_checked` before `player_finished`. Root owns that runtime, its records/provider/session/persistence and integration.

The concrete join is:

1. Retain `P.Receiver` in the actual transient runtime owner. Supply its multiplier to the existing `TH.Hooks`; that field currently remains a literal zero.
2. Retain the actual `Entity.move` records through the successful movement. Preserve the original axis-dependent request after stuck scaling and the actual edge backoff, before collision resolution, plus its original start/end. For multiple moves, preserve their ordered queue. Public dispatcher queue draining/fallback creation is a separate caller obligation; the native stored-route comparisons use original observed ready lists.
3. On successful normal-physics stuck consumption, update the receiver with the committed `P.travel_succeeded`. Keep the original receiver on any enclosing failure. NoPhysics/lifecycle branches must follow their actual consumption contracts.
4. Invoke `SM.after_movements` with actual dimensions, facts and berry receiver observations after successful travel and before committing `player_finished`. Retain its returned motion history and receiver for the next move.
5. Keep the join inside the existing root rollback transaction. A later finish/provider failure restores both original motion and original receiver. Callback impulses and grace-timer lifecycle require their own actual providers; this slice neither decrements the timer nor creates an impact.

The producer enables no new registry states, world placements, visual materials, persisted receiver fields or live runtime callbacks on its own. The flat client cannot establish cobweb/berry gameplay until those real consumer/statekeeping joins exist.

## Proof and native evidence

There are 28 actual production laws in `player_block_inside_sweep_laws` with proofs in `player_block_inside_sweep_proof`. They establish per-segment local reset, duplicate and successful-limit policy, actual ordered air/duplicate reads, arbitrary full-owner rollback and successful commit, early real read/callback failure precedence, berry selected-branch independence, both success and refusal through the actual public MH adapter, and exact record/ready-list binding to the actual retained TH outcome. Named premises refer to actual `Core.read_block`, `W.read`, `P.callback_checked`, `SM.view_binding` and `W.query`; they are not unconditional proofs of every array or IEEE traversal calculation. Geometric and numeric parity is established separately by the original Java observations and targeted native comparison.

The fresh independent kernel export retains all original declaration maps and checked source types/proof bodies. All 28 selected roots pass with zero exclusions. IR size is 3,861,962 bytes; ordinary/source-export/kernel times are 4.665/26.901/0.655 seconds. All 48 source pins matched immediately before the scoped production commit. See `evidence/player-block-inside-sweep-proof.json`.

The first narrowed native build stopped at its unchanged 180-second cap during initial Bend C emission (180.558 seconds, peak physical footprint recorded by the sampler as 8.3G). It produced no C, cache record or binary and never executed the target. Its process group was confirmed absent. The first changed route boxed the previously flattened movement Segment with an inert recursive private tail, but also hit the same cap before C emission completed (180.454 seconds). Its distinct failed receipt is retained as `evidence/player-block-inside-sweep-failure-1791138249806010000.json`. The final substantive route also boxes the Clip.AxisInput and native parser MovementRead continuations; every production/internal constructor uses Nil. It preserves the same arithmetic and traversal order and completes initial C emission in 60.964 seconds. This changes representation rather than traversal semantics. The changed source closure was freshly checked and independently proved before the replacement native run. The failed receipt is retained in `evidence/player-block-inside-sweep-failure-1791137795368827000.json`; exact diagnosis/sample remain under its ignored build directory.

The third substantive targeted native run passed: 1,000 operations and all 1,466 output rows matched exactly. The corpus includes 117 original sweeps / 1,656 reads / 986 callbacks, 59 walks / 955 accepted visits, six clips, 147 mandatory State-versus-Observation authority joins, 173 raw owner checks, 152 checkpoints, 24 atomic refusals, 26 same-owner recoveries and seven genuinely queried collision sequences. Build time was 164.878 seconds (C emission 60.964; native compile 99.077); target time was 84.548 seconds. All 34 source/reference pins matched. Both process groups were confirmed absent. See `evidence/player-block-inside-sweep-build.json` and `evidence/player-block-inside-sweep-native.json`. The host harness compares original accepted visit/read/callback traces and exact receiver/history/impulse state, checks complete raw Core/Registry owners on refusals and actual held State against returned Observation on successes, and queries deliberately colliding section-map buckets. It includes explicit late failures and same-owner recoveries.

Reproduce:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_block_inside_sweep_probe.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_block_inside_sweep_probe.py --verify-existing
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_block_inside_sweep_proof.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_block_inside_sweep.py
```

The original callback inside Boolean is not exposed by the fixture, so native comparison does not invent an independent oracle for it. General entity-inside shapes, fluids, ground `stepOn`, fire/freezing/collector effects, movement-queue formation, real server berry damage, full world ticking and visible client gameplay acceptance remain separate dependencies. Native trace equality and these ownership laws do not establish those behaviors.
