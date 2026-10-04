# Staged neutral travel with a checked fall-reset ray (26.3 design)

This is a source-design proposal. No new gameplay module, receiver, native build
or proof has been executed. Confidence is high in the frozen API/bytecode facts
below; correctness of the proposed composition remains unverified. FR itself is
ordinary-prepared and awaits host-driver adoption and a native grant. Existing
TH/MH/LM/H/FR consumers and sources remain unchanged.

The proposed adapter can reuse `LM.move_checked` exactly once and `H.movement`
exactly once. It cannot call `TH.travel_checked` or `MH.move_checked` first:
both require a clip observation before returning their collision transition.
Supplying a guessed `Miss`, or retrying movement after a guessed `NotRequired`
fails, would conceal the missing supplier or duplicate movement. The new adapter
instead reuses their owner shape and pure metadata helpers.

## Proposed affine interface

Suggested future module: `src/fall_reset_travel.bend`, imported as `FT`. This path
is proposed only and has not been created.

```text
travel_checked(MH.State, L.Tables, FT.Request)
 -> MH.State & L.Tables & Result<&2, &2, FT.Error, FT.Outcome>

RayPolicy Data {
 interior: A.AABB,
 work: Nat,
 profile: FR.Profile,
 tail: List<&2, RayPolicy>
}
Request Data {
 input: M.Vec3,
 context: T.Context,
 hooks: TH.Hooks,
 ray: RayPolicy,
 tail: List<&2, Request>
}
RayMetadata Data {
 old_feet: M.Vec3, resolved: M.Vec3,
 old_distance: F.F64, length_squared: F.F64,
 length: F.F64, limit: F.F64, to: M.Vec3,
 tail: List<&2, RayMetadata>
}
RayOutcome Data {
 NotRequired { old_distance: F.F64, position_applied: Bool,
               length_squared: F.F64 }
 Required { metadata: RayMetadata, checked: FR.Observation }
}
Outcome Data {
 prepared: TH.Preparation,
 movement: MH.Outcome,
 ray: RayOutcome,
 final_motion: LM.Motion,
 tail: List<&2, Outcome>
}
```

`MH.State` already owns the sole `W.State`, `SP.State`, `LM.MinorState` and
`H.State`; Tables stay external. Request carries no authoritative Body/history,
explicit ray endpoints, clip value, grounded Boolean, edge distance, edge maximum
or independent minor yaw. Immutable observations are Data, not additional
persistent owners. Recursive boxes limit native continuation capture widths.
All request/policy/Hook tails and the owned State tail must be empty. A nonempty
owned tail returns every original child owner before extraction.

Reuse `TH.Hooks` for the current logical keys, current xxa/zza, flying/mode and
existing neutral movement declarations, LCW environment and backoff query fuel.
Derive the LM Body from `T.Prepared.body`, the request from `T.Prepared.requested`,
the edge distance from the sole saved H history, maximum from `T.Context`, mover
as SELF, and minor degree yaw from `T.Context.yaw`. Shift key, crouching, current
input fields and the direct travel Vec3 remain distinct. W camera radians do not
supply the degree yaw. Ground friction, current resolved attributes and mode
remain explicitly conditional caller observations; this adapter does not acquire
their provenance merely by combining modules.

Proposed errors: noncanonical State/request (with outer/Hook/ray field index),
`PreparationError{T.Error}`, `MovementError{LM.Error}`,
`HistoryMetadataError{H.Error}`, `RayError{FR.Error}`,
`HistoryError{H.Error}`, and `FinishError{T.Error}`. Do not expose an independent
H.Mode/noPhysics bypass. Only admitted LM success reaches fixed
`H.NeutralDryNoDamage`.

## Exact phase data and endpoint derivation

The original Entity.move bytecode first performs edge backoff at 186 and collide
at 192. Its application gate uses resolved length squared at 199 and branches to
227 or skips to 363. Inside the taken branch, distance is tested at 228–233 and
resolved length squared against one at 234–241. The required clip call at 299
occurs before movement recording/position application at 347/353. Support at 530,
minor at 544, legacy support-block sampling at 559/570 and fall checking at 596
follow. Restitution is at 648. These offsets are pinned stored bytecode facts,
not a fresh execution of the proposed adapter.

The adapter sequence is:

1. Validate canonical owners/requests. Save immutable `Frame{prior View, prior SP,
   prior minor, prior H.History, request}`. Extract the existing Engine once.
2. Call `T.prepare_checked` with the prior authoritative Body, direct input and
   Context. Install the returned prepared Body in the candidate View once. Its
   original feet and AABB remain the old values; only prepared velocity changes.
3. Call `LM.move_checked` once with the derived request. Keep its returned world,
   support, minor and motion candidate, and retain the still-unchanged H owner.
4. Extract the transition's **resolved displacement** and `position_changed`
   application-branch bit. Use `MH.movement_from(transition, H.NotRequired{})` only
   as pure metadata, then `H.history_error`/`H.movement_error` to admit finite old
   history, finite resolved Y and finite nonnegative ordered length squared. This
   early metadata check does not apply history or fabricate clip evidence.
5. Compute the required predicate with existing
   `H.clip_required(oldDistance, positionApplied, resolvedLengthSquared)`.
   Numerical positive/negative zero distances both make it false; edge-context
   binding still preserves their exact raw history payload. `position_changed`
   denotes the actual application branch, not an old/new-position comparison.
6. If false, produce `H.NotRequired{}` without calling FR or manufacturing ray
   endpoints. Ray profile/interior/work are unused in this branch, although its
   canonical policy tail remains checked. If true, derive the exact endpoints
   from saved old feet and resolved movement, then call FR once.
7. Pass FR's actual returned `FR.observation_clip` into
   `H.movement(H.NeutralDryNoDamage{}, MH.movement_from(transition, clip), history)`.
   Do not substitute a literal Miss. The not-required branch passes NotRequired.
8. Call `T.finish_checked(prepared, transition)` once after successful history.
   Its gravity and drag use LM's final restituted velocity, not the ray vector,
   prepared request or pre-restitution snapshot. Commit final Body/SP/minor/H
   atomically only after success.

For a required ray, retain the actual operation order:

```text
gateSquared = ((resolved.x*resolved.x) + (resolved.y*resolved.y))
              + (resolved.z*resolved.z)
length = sqrt(M.Vec3.length_squared(resolved))
limit = Math.min(length, 8.0)
unit = L.normalize(resolved)
offset = L.scale(unit, limit)
from = saved_old_feet
to = M.Vec3.add(saved_old_feet, offset)
```

Existing exact `M.Vec3.length_squared`, `F.sqrt`, `L.normalize`, `L.scale` and
`M.Vec3.add` provide the operations. Length and normalization each perform their
own actual squared-length/sqrt calculation; normalize divides each component by
length. There is no divide-once or `resolved * min(length,8)/length` shortcut.
For admitted required rays length is finite and at least one, so a small pure
positive-finite minimum helper can select length or raw double eight with the
same Math.min result; generic NaN/signed-zero minimum semantics need not be
invented. The normalize small-vector threshold is never reached on this path.
No Tables lookup is needed for the endpoint calculation.

The endpoint source must be `Frame.View.Body.position`, never the candidate
world's post-move position, its new AABB minimum, a camera/eye point, or final
gravity/drag velocity. The transition displacement is collision-resolved after
backoff, not the original/prepared/corrected requested vector. A skipped position
gate suppresses the ray but does not suppress the later H accumulation.

## Neutral equivalence boundary and rollback

Actual Java clips **before** position/support/minor/fall/restitution. Frozen LM
returns a candidate after support/minor/restitution, so the proposed adapter's FR
reads occur later in its internal evaluation. This is not global query/callback
trace parity. It is admissible only as the same neutral **field projection**:
all world queries are read-only under one Engine owner; supported selectors are
history-independent and produce checked MISS; no concurrent edit intervenes;
admitted support/minor do not consume updated history; restitution is neutral;
damaging/resetting/block/event/autoJump callbacks are outside the contract.

For actual MISS the earlier Java ray does not reset history. Thus computing LM's
immutable candidate first and applying H afterward can preserve the same bounded
Body/SP/minor/H fields without moving an observable callback. H remains the
actual `distance - (double)(float)resolvedY` reducer and safe positive-zero landing
reset. It is applied once with resolved Y, pre-drag length squared, final move
onGround and the application-gate metadata. No `.98` input decay or automatic
`checkFallDistanceAccumulation` clamp is added.

This reasoning does **not** admit reset hits, fluid/flight/effects, damage,
history-sensitive bounce, sounds/game events, autoJump/walkedDistance, arbitrary
block callbacks, after-travel effects, or whole LocalPlayer.travel/tick semantics.
Supporting/minor candidate snapshots remain exactly LM's original-velocity
observations. Generic observable phase parity would require a future collision
prepare/callback/commit boundary before LM finalization; that is not supplied by
the frozen API and must not be claimed by this adapter.

Every failure restores the one outer Frame, not merely LM's local pre-move Frame
(which already contains accelerated velocity). Take the **returned** world,
retain its Engine/Registry/Core owner, and reattach the original saved View.
Rebuild canonical MH.State with prior SP/minor and `H.State{prior History}`;
return the Tables owner from the failing phase. Do not duplicate Engine/Tables,
keep a second persistent Body, reset history on error, or publish the candidate.

This applies after preparation, backoff/collision/support/minor, metadata, any FR
read failure, H landing/clip failure and T finish failure. Prior View includes raw
velocity/flags, yaw/pitch, dynamic palette, region and snapshot cache. Read-only
queries preserve canonical cells/trie, revision, clocks and pending/events. H
updates only its local owned History. A finish failure after successful FR/H must
restore prior history as well as motion. An owned noncanonical tail returns
verbatim; child owners must never be reconstructed as empty tails.

## Separate query policies and pathological rays

`TH.Hooks.environment` keeps LCW's explicit known-empty entity collisions and
known-clear-border query-AABB admission. Padded block cells are still read and
resolved before shape filtering. That conditional LCW admission does not imply
whole-cell containment or actual border detection.

`RayPolicy.interior` is a separate FR domain: every **visited full cell** must fit
inside it, and expanded endpoints/cursors obey FR's conservative i32 margin.
The new module passes this box and the exact FR.Profile unchanged; it does not
derive a stronger ray domain from LCW's AABB-only declaration. The ray itself
queries block/fluid selectors, not entity/border collision services. Required
UnresolvedTags, stale/absent palettes, missing sections, unsupported states,
unsafe domains/cursors and work exhaustion all fail with complete rollback.
No missing read becomes air. Non-required rays do not need a tag reload or
invented profile truth because no clip service is called.

Backoff fuel and FR read work are separate budgets with different units. The
former bounds pending edge queries; FR reserves two actual block reads per cell.
The caller supplies explicit finite allowances. Do not silently consume the same
Nat twice, infer sufficient work from endpoint distance, or retry after a failed
budget. A future aggregate budget API would need measured per-phase accounting;
this proposal does not claim one.

The existing actual FR observations prove that total length at least one does
not guarantee a terminating ray. From `(0,0,0)` to `(1,-5e-324,0)` or
`(1,-1e-320,0)`, actual length/lengthSquared equal one and normalization/scaling
retain the tiny Y component. Expanded X starts at `-1e-7`; NaN Y timing causes
repeated stationary-Z selection. Each actual call records 128 visits to
`(-1,0,0)`, 256 returned reads, then external read attempt 257 interrupts. These
are incomplete calls, not MISS returns.

The proposed composition must let FR return a budget/interior/cursor/Core error
and roll back the complete pre-travel state. It must not exclude the case solely
by total length, deduplicate cells, repair a private NaN timing or fabricate MISS.
Whether untouched whole LocalPlayer.travel reaches exactly these endpoints in a
corresponding admitted movement fixture still needs direct receiver observation.

## Required independent reference and validation

The frozen TH reference already has 87 admitted direct travel calls, including
five actual required MISS calls and six application-gate skips. FR copied all
seven required actual endpoint pairs from TH/MH and independently executed their
clip traversal. These establish existing component observations, not a fresh
proof or native result for the proposed integrated endpoint supplier.

A new disjoint probe should reuse the normal-constructor TH receiver and the
same four named external LI services, then add super-calling clip/read/selector
observers with the **actual default tag reload** and plain-observed field parity.
Untouched `LocalPlayer.travel` and inherited movement must remain decisive. No
hand-composed Java or Python transition supplies expected fields. The first
corpus must retain existing TH cases and add:

- Required motion just below/at/above lengthSquared one and lengths below/at/above
  eight; positive, negative, diagonal, collision-clipped, edge-corrected and
  signed-zero components. Record actual old feet, prepared/corrected/resolved
  vectors, endpoint bits, clip return, every ordered block/fluid read and selector.
- Distance `+0`, `-0`, finite nonzero; blocked/tiny application-gate skips;
  current/previous support and original prepared velocity at support/minor/fall;
  safe landing, chained history before gravity/drag, and final travel velocity.
- Integer/stationary axes, exact corner ties and endpoint epsilon neighborhoods.
  Retain deliberate and subnormal watchdog interruptions with partial traces.
  Add direct whole-travel mixed negative-subnormal Y trials to determine whether
  their actual resolved ray is pathological; never assume a helper-only ray ran
  inside Entity.move.
- Actual unsupported resetting/water/portal selectors as measured exclusions,
  plus owned missing/unknown sections, stale/absent palettes, work/domain policy
  failure and same-owner recovery. Actual Java may continue on states which the
  bounded Bend supplier intentionally refuses; label that policy distinction.
- Required-ray failure after LM's changed candidate, H unsupported landing after
  successful FR, late finish injection, noncanonical request/owned child tails,
  running/pending Core and cache preservation, and dynamic four-state remaps.

Compare raw endpoint and grouped ray/collision/support observations independently;
do not report globally identical read order for staged evaluation. Native suites
must compare complete Body/SP/minor/H and all owner data, not just final position.
Meaningful laws should state one outer rollback frame at every late failure,
raw old-feet/resolved binding, retained canonical/child owners, and no caller clip
or duplicated motion. Ordinary checks and independent verdicts remain separate.

Concrete prerequisites/blockers are FR's still-unverified native behavior and
host receipt adoption; new exact endpoint/adaptor source/type checks; fresh direct
whole-travel ray observations; independently granted native/proof work; and the
existing full-import kernel mismatch. No new numerical primitive or change to
LM/H is required for the bounded MISS/NotRequired field projection. Actual tag,
attribute/support provenance and observable callbacks remain separate full-goal
work. An initial runtime may honestly admit CheckedNotRequired only; required
rays must then reject until this checked supplier composition is implemented.
