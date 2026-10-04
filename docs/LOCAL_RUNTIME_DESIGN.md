# Local runtime phase and ownership design — pinned Java 26.3

This is an integration design, not an implemented runtime or a new verification
result. It changes no production module. The existing `PlayerRuntime` implements
a bounded **plain `Player.aiStep`** facade. `LocalTickWorld` implements the local
input/motion projection, while the newly frozen `LocalMoveHistory` owns motion,
support, minor collision and fall history. `LocalTravelHistory` remains prepared
with native validation pending. `PlayerPose` has now passed its bounded native
comparisons and one full-import kernel verdict; its actual fit supplier remains
a separate integration dependency. Replacing one travel call would not establish
`LocalPlayer.tick` behavior.

Confidence is **high** in the quoted bounded phase observations and frozen MH
native comparisons, **moderate** in the proposed composition and transaction
policy, and **unknown** for an executed runtime using this design. Independent
kernel status is per module and per stated law; it does not transfer through this
document. [The design snapshot](../evidence/local-runtime-design-snapshot.json)
pins the files read, records provisional dependencies, and contains a small
projection of the actual phase corpus. It is not a build receipt.

## Three different operations must remain distinct

There is no `Core.commonTick` function in `src/core.bend`. The relevant operations
are:

| Operation | Authority and scope |
| --- | --- |
| Project `C.step` | Apply due typed world operations, advance the project simulation clock and its daylight policy. The existing runtime performs this before its player projection. This is a project actor policy. |
| Actual `Entity.commonTick` | Decrement positive invulnerability time; snapshot old position and rotation; invoke client interpolation; increment the entity's signed Java `tickCount` word. `Rotation.common_tick` implements only the camera snapshot and counter projection. |
| Actual virtual `LocalPlayer.tick` | Loaded-client guard, inherited entity/player lifecycle, local input and travel, post-aiStep rotation work, late pose update, then local presentation postlude. It does not call `commonTick` itself. |

Actual `ClientLevel.tickNonPassenger` calls `Entity.commonTick` before virtual
`Entity.tick`. A direct `LocalPlayer.tick` call omits that scheduler operation.
The scheduled corpus increments the entity count once, including its later
failure; four direct shift ticks retain count 40. Removed/passenger/frozen entity
iteration skips and the local loaded-client early return are distinct branches.
The former reaches neither phase; the latter can occur after commonTick.
Those branch predicates are pinned statically; this corpus does not execute the
loaded-client-false branch.

The actual outer `Minecraft.tick` also has keybind, renderer, entity, block-entity,
`sendChanges`, later client-level time/weather/chunk, audio and packet phases.
The receiver does not run that outer method. Project Core time, entity tickCount,
render frames and API polls must therefore remain separately named. No native
Minecraft client/server clock correspondence is established here.

The production-facing integration should initially advertise a **neutral local
phase projection**, rather than complete `LocalPlayer.tick`. In particular, the
observed second scheduled sprint frame reaches real sprint-particle code and
fails at the declared fixture's missing Minecraft `gameRenderer` service, before
aiStep. LocalInput's successful sprint-setter observations do not fill this full
tick service gap.

## Sole persistent owner

The following is a proposed type shape, not compilable production source. Names
`RuntimeState`, `EntityMetadata` and `LocalMetadata` below are design names.

```text
RuntimeState Type {
  motion: MH.State,                 # sole W/Core/Body/SP/minor/H ownership
  tables: L.Tables,                 # sole sine-table owner
  local: LI.State,                  # prior sampled keys/vector and local cache
  player: PRRuntime.Metadata,       # processed input/jump/speed/head projection
  sprinting: Bool,                  # current entity sprint flag
  pose: Pose.State,                 # selected pose and cached F32 eye height
  controls: PC.Controller,          # physical buttons/mouse/options/PL angles
  entity: EntityMetadata,           # entity counter; proposed old-position data
  last_error: Maybe<String>,
  tail: List<&1, RuntimeState>       # canonical empty
}

EntityMetadata Data {
  tick_count: U32,                  # Java int payload, wraps modulo 2^32
  previous_position: M.Vec3         # requires a new checked snapshot adapter
}
```

`MH.State` already owns `W.State`, `SP.State`, `LM.MinorState`, `H.State` and its
recursive owned tail. W owns the single authoritative Body and game/Core engine.
There must be no additional persistent world, Body, support or history owner in
the new state. `L.Tables` leaves the runtime temporarily for LI/TH operations and
is returned and reinserted on every branch. All recursive state/request tails
must be rejected unchanged unless explicitly supported; an extra owned world
cannot be silently discarded.

| Stored field | Meaning; fields it must not replace |
| --- | --- |
| `motion.world.body` | Actual feet, box, velocity, dimensions and four collision/ground flags. Pose requests and P states borrow immutable checked Body snapshots. |
| `motion.support` | Supporting block and onGround-no-blocks cache. Body.onGround is a different actual field. Neither derives authoritative fall distance. |
| `motion.minor` | Previous/current published minor-collision flag, used by the next local control phase. It is not implied by horizontal collision. |
| `motion.history` | The single authoritative F64 fall-distance payload, including signed zero. Edge requests bind to this value. |
| `local.keys`, `local.movement` | Last actual ClientInput sample and raw keyboard vector. Physical buttons can change before these fields are resampled. |
| Other LI fields | Cached crouching, sprint-trigger timer, current/old bob values. Cached crouching is not the selected pose or current shift key. |
| Player metadata | Current processed x/y/z input, jumping, jump-delay/trigger, sync, stored speed and current head-yaw projection. It contains no Body. Resolved attributes are separate observations, not the stored speed field. |
| `sprinting` | Actual sprint flag resulting from ordered setters. Held sprint is an input, not this state. |
| `pose` | Selected pose and cached eye height. Body dimensions remain in Body and must be coherent with Pose metadata at a stable boundary. |
| `controls.look` | Sole persistent current/previous yaw and pitch in F32 **degrees**. W's radian angles are checked rendering projections. |
| `entity.tick_count` | Entity counter payload; it is not a copy or conversion of the Core Nat clock. |

Do not persist `P.State`, `P.PreTravel`, `TH.Outcome`, `Pose.Request.body` or a
second `Rotation.State` as competing authority. A P state is composed from the
sole Body plus player metadata. A Rotation owner is created temporarily from
`controls.look` and `entity.tick_count`, consumed by one checked operation, then
its fields are installed back into those two original locations. MH/TH outcomes
are immutable phase observations. They are useful for validation and reporting,
not alternative stored Bodies or histories.

Old position is deliberately marked as a missing adapter: Rotation only copies
camera angles/count. The phase corpus observes actual old-position writes, but
there is no current checked runtime owner operation for full `setOldPosAndRot`,
interpolation or positive invulnerability time. Until one is independently
implemented, require the explicit no-interpolation/neutral lifecycle boundary
and do not expose interpolated eye position. Merely adding metadata fields is
not an implementation of those phases.

Use small recursive Data boxes for rollback headers and named continuations.
Do not capture the whole RuntimeState, flattened Body, P/TH outcome and all
observations in each continuation. Existing native harnesses have encountered
the installed continuation-width limit; boxing may address representation, but
does not justify omitting a rollback field.

## Entry points and time

Input accepts a complete `CC.Packet` and applies `PC.apply` atomically. Controller
changes and the corresponding checked W view-angle projection publish together;
on failure return the prior controller/view. Input packets never advance Core or
entity counters and never run LI controls/prepare. Snapshot/status/discovery and
render polling also never invoke a tick. World snapshots may update only their
read cache through their existing read-only API.

Physical `controls.buttons` and `LI.State.keys` must remain separate. Key events
or `PC.release` change the former. They do not prematurely rewrite the latter,
which belongs to the next actual ClientInput sampling phase. Focus/capture release
must clear held physical buttons and mouse state/rearm its first-move discard as
the existing controller specifies. Its interaction with the future local runtime
is still an integration test obligation, not full vanilla UI evidence.

An accepted explicit tick performs exactly one Core step. An unpaused realtime
pulse performs the same tick; a paused pulse performs none. Do not turn frame
rate into simulation cadence. The project keeps its existing world-step-before-
player policy, pending an explicit actor integration decision. This ordering is
not attributed to vanilla's outer client tick.

Keep a direct local-phase entry for reference testing separate from a scheduled
entry: it must not accidentally call commonTick or increment tickCount. Normal
scheduled runtime work has a single commonTick projection before local work.
An explicit outer-entity skip and an early local load guard must not be conflated
with a successful neutral tick. Those unobserved lifecycle branches remain
unsupported rather than being guessed from input or ground state.

## Proposed phase pipeline

This pipeline states the target ordering of the implemented field projection.
Unimplemented lifecycle stages shown in the actual order remain admission gaps;
they are not empty successful callbacks.

1. **Structural admission and project world step.** Reject malformed/noncanonical
   request/state tails without losing owners. For an accepted scheduled tick,
   run the existing C.step policy once and retain due mutations/clock changes.
   Resolve subsequent world observations from that returned engine, so a queued
   block edit cannot be missed by a stale context snapshot.
2. **Entity scheduler snapshot.** Establish the admitted entity/lifecycle
   boundary, snapshot current feet to proposed old-position metadata only after
   that adapter exists, and call temporary `Rotation.common_tick` once. This
   copies current camera angles to previous angles and increments the U32 word.
   Real invulnerability/interpolation work is outside the current projection.
   The rollback anchor for subsequent local work is after this committed phase.
3. **Local/inherited tick prelude.** Actual loaded guard, avatar/base-tick,
   fluid/swimming/environment, timers/effects and conditional particles precede
   aiStep. Admit only independently justified neutral contexts. They cannot be
   silently replaced by the input module. Full sprint-particle and broader
   lifecycle services remain unresolved.
4. **Local control sample using the prior cache.** Preserve the prior LI state.
   Resolve exact standing/crouching fit answers at this phase's current feet,
   current pose/dimensions, prior Body collision flags and MH.minor. Call
   `LI.controls_checked` with physical held buttons. It decrements the positive
   sprint-trigger timer, computes cached crouching from **previous sampled keys**,
   then samples current keys/vector. The resulting LI.Controls contains both
   the new local cache and an ordered list of sprint setter requests.
5. **Replay setters; resolve current attributes.** Replay every ordered sprint
   setter, preserving repeated setters and their order. Do not collapse them to
   one final boolean. Resolve travel/jump/sneak attributes after those changes;
   bind the resolved sprint flag to LI.Controls and T.Context. Attribute
   provenance remains a conditional caller contract until a checked resolver is
   integrated. Travel friction/jump factors must use actual support-aware sample
   positions and the post-Core world, not stored speed or a constant floor guess.
6. **Local apply-input and jump preparation, once.** Compose a temporary P.State
   from the authoritative Body and player metadata, and call
   `LI.prepare_checked` once. This applies actual velocity cleanup/countdowns,
   bob snapshot/update, local modify/square/slow-input processing and jump
   preparation. Its `.98f` input decay happens **once**. Do not subsequently call
   `P.prepare_checked`, `PW.tick_checked` or the old LTW path; those would either
   duplicate decay or execute another travel path. Install the prepared jump
   velocity into the candidate sole Body, retaining pre-pose dimensions.
7. **TH travel with MH ownership.** After TH is frozen and validated, pass the
   prepared travel Vec3, current processed xxa/zza, current sampled keys and
   conditional T.Context to `TH.travel_checked`. TH derives Body/ground from W,
   fall distance from H, and edge maximum/minor degree yaw from T.Context. It
   performs T.prepare acceleration, installs prepared velocity, MH collision/
   support/minor/history/restitution, then T.finish gravity/drag. There is no
   additional `.98` decay. A real reset-ray producer must provide `H.Miss` when
   required; absence of an observation is not MISS.
8. **Finish player metadata and admitted post-travel projection.** Use
   `P.finish_checked` once with the retained LI P.PreTravel and TH's final
   transition. T.finish has already run; do not run it again. Publish resulting
   player metadata only into the local candidate. Actual block effects follow
   travel before aiStep returns; movement emission, actor pushes, equipment,
   effects and lifecycle callbacks require separate implementation/admission.
   No unconditional fall-distance clamp is inserted: the observed neutral calls
   do not execute the gliding-only accumulation clamp.
9. **Post-aiStep camera normalization.** Call temporary `Rotation.normalize`
   after the admitted aiStep projection, with a shared fuel budget at most
   16,384. Keep its exact previous-yaw negative/positive loops followed by
   previous-pitch negative/positive loops. All comparisons and ±360 operations
   are ordered F32, including subtraction overflow and no-progress updates.
   Do not replace them by modulo arithmetic. Current angles/count are retained.
   In actual LivingEntity.tick the body-yaw loop sits between the camera yaw and
   pitch loops, and the head-yaw loop follows pitch. Rotation projects only the
   two independent camera components with its own bounded shared fuel. Body/head
   normalization, head-turn and sleep-angle resets remain outside that projection.
10. **Late pose/dimension/eye selection.** After normalization, construct a
    Pose.Request from the candidate sole Body, coherent prior Pose.State and
    **current** sampled shift key/lifecycle flags. `Pose.begin_checked` requests
    initial SWIMMING fit; false returns unchanged. Otherwise answer desired-fit
    and conditional CROUCHING fallback queries in their exact order. Each query
    uses the actual pose's dimensions at current post-motion feet, deflated by
    double 1e-7. Use a checked world-backed producer for block/entity/border
    collision; LI's earlier fit answers are not interchangeable. On change,
    install Pose.transition Body/state together: retain raw feet, velocity and
    all Body flags, rebuild the AABB and update cached F32 eye height. Do not use
    Body.new, which would reset unrelated flags. Do not repeat support/history
    after resize: their actual hooks already ran during move.
11. **Stable publication and view.** Validate supported stable pose/domain,
    install the complete candidate atomically, and make the rendering projection
    coherent with current PL degrees and pose eye height. Remaining Player/Local
    item, first-person/ambient and separate sendChanges work is not implemented
    by this publication. Network/sound outputs cannot be inferred from it.

TH's current API is
`travel_checked(MH.State, L.Tables, TH.Request) -> MH.State & L.Tables & Result<Error,Outcome>`.
Request/Hooks/MH tails require empty. No separately authoritative Body, fall
distance, onGround, minor yaw or edge maximum appears in its request. The
current source ordinary-checks five laws; the fresh broad direct travel corpus,
native comparisons and independent kernel verdict are pending. The small debug
receiver has three actual successful travel calls, one actual MISS and two
NotRequired paths. It is not TH-wide validation. The receiver's earlier
uninstalled-chunk-cache hypothesis was disproved: actual ClientLevel.hasChunk
returns true and both installed/uninstalled fixture variants have the same
gravity/output. Do not introduce an unloaded-client fallback from that hypothesis.

## Motion/support/minor/history order is internal

The verified actual local move order is collision/backoff/application gate,
support, conditional minor, actual legacy block sample, checkFallDamage, removed
gate, restitution/emission/block speed, then local auto-jump/walked distance.
Support and minor see the **original prepared velocity**, rather than final
restitution or gravity/drag velocity. Support can run when the position application
branch is skipped, and minor only runs when the actual horizontal-collision hook
is entered. A second support callback after TH's final drag would use the wrong
phase and must not be appended to the new runtime.

MH computes a checked immutable neutral motion candidate before atomically
reducing fall history. This equivalence is justified only in its admitted
read-only support/minor and no-damage MISS/NotRequired field projection, whose
operations do not depend on newly accumulated history. It does not reorder real
damage, block callbacks, sounds or game events. Integration must preserve this
qualification rather than treating the reducer as full movement effects.

Fall history derives from the collision transition: resolved Y, ordered binary64
length squared `((x*x)+(y*y))+(z*z)`, returned Body.onGround, and the actual
position-application branch. `M.Transition.position_changed` records that branch,
including zero displacement or rounded addition retaining identical XYZ words.
It is not a raw XYZ inequality. When resolved Y is negative, actual accumulation
is `distance - (double)(float)resolvedY`, not requested Y, final Y velocity, or
newY−oldY. Ground resets to positive double zero only on the admitted no-damage
branch. Default landing admission uses the exact ordered expression
`((distance + 1e-6) - 3) < 1` and default multipliers 1/1.

For an applied position branch, old distance numerically nonzero and resolved
length squared at least one require actual reset-ray MISS evidence. Other cases
require NotRequired. Hit, unknown/missing/superfluous evidence and damaging
landings reject and roll back. Neither SP.ground nor an absent clip callback
establishes the history or ray result. The world-backed ray implementation is
still a runtime prerequisite; current MH fixtures supply actual observations.

There is an API staging dependency here. Current MH/TH requests carry `H.Clip`
before execution, but the required-ray predicate uses the **resolved** collision
vector and application gate produced inside that execution. A general runtime
cannot establish its required MISS from the original request alone. A future
checked staged/callback API must expose the resolved pre-position phase, thread
the same world owner through the ray query, bind its answer to that exact phase,
then continue motion/history. An independently checked read-only precomputation
would instead need evidence of identical collision/world generation and operation
order. Neither mechanism exists in the frozen APIs.

For a narrower initial runtime, `NotRequired` can be supplied as a checked
assertion: MH accepts it only when the actual computed transition does not require
a ray, otherwise returns a history error and restores the candidate. This avoids
an invented MISS, but excludes required-ray moves and must be advertised as that
smaller domain. It is not complete long-fall behavior.

Actual ray endpoints start at the pre-application position and extend along the
normalized resolved direction for the lesser of its length and eight blocks;
the query uses FALLDAMAGE_RESETTING block semantics and water fluids. Exact
numeric endpoint construction, resetting-block tag membership and fluid/hit
semantics need their own world-backed implementation and observations. Existing
block collision lookup is not that ray algorithm, and the receiver's explicit
empty-tag/neutral-fluid boundary does not establish production pack-tag behavior.

## Crouch, pose and eye must expose the right frame

The scheduled and direct shift histories independently observe:

| Frame | Current shift | Crouch cache in move | Move height / eye F32 bits | Completed pose height / eye F32 bits |
| --- | --- | --- | --- | --- |
| First hold | true | false | `3fe66666` / `3fcf5c29` | CROUCHING `3fc00000` / `3fa28f5c` |
| Second hold | true | true | `3fc00000` / `3fa28f5c` | CROUCHING `3fc00000` / `3fa28f5c` |
| First release | false | true | `3fc00000` / `3fa28f5c` | STANDING `3fe66666` / `3fcf5c29` |
| Second release | false | false | `3fe66666` / `3fcf5c29` | STANDING `3fe66666` / `3fcf5c29` |

Thus the first hold uses standing collision geometry during movement but crouched
geometry/eye at completed tick. The first release moves with crouched dimensions
before standing selection. Pose cannot be installed before LI/TH to make the
current key appear immediately effective. Cached crouch, pose and current keys
remain separate stored/phase values.

Pose supports a verified bounded adult, unscaled client metadata/conditional selection
projection: exact F32 scale 1, baby false, coherent Body dimensions/box/eye and
canonical tails. Its observed fixture covers additional seeded flag/fit branches,
but LI's neutral controls currently admit Standing/Crouching only. Initial
runtime admission should therefore require those stable poses and reject a
candidate Swimming/other unsupported transition with complete local rollback
until the appropriate gait/lifecycle is independently implemented. Returning
Standing regardless of a forced crawl result would corrupt the real selection.

Current `W.eye_position` hardcodes 1.62f. It cannot provide a completed crouched
view. The future view adapter must use the sole cached `Pose.State.eye_height`,
widen that F32 to F64, then add it to feet Y in F64. At feet Y exactly 1 the
actual standing/crouching eye Y words are `4004f5c290000000` and
`400228f5c0000000`. The current fixed instrument camera remains valid only for
its original scope. This design does not change it.

PC/PL owns degree angles. Renderer W yaw/pitch are the existing rounded F32
radian projection (factor word `3c8efa35`), not movement yaw authority. Mouse
turn changes current and previous camera angles through PL.turn at the input
phase; the later scheduled commonTick snapshots current angles again. Previous
angles then normalize after aiStep. Interpolated camera/eye snapshots additionally
need old feet and actual interpolation semantics, which remain unimplemented.

## Rollback and externally observable effects

The proposed runtime transaction has an explicit boundary; it must be reviewed
and independently tested during implementation. Do not imply this policy is
vanilla's exception behavior.

| Failure/entry | Proposed retained state |
| --- | --- |
| Malformed/noncanonical tick request before acceptance | Every original owner/tail and all clocks unchanged. |
| Accepted project tick, then entity projection admission failure | Completed Core step/due edits retained; entity projection unchanged if commonTick did not succeed. |
| Failure after successful scheduled commonTick | Core and committed camera snapshot/entity count retained; complete local candidate rolled back to the **post-commonTick** anchor. |
| Direct local phase failure | No Core/commonTick was run; complete local prior retained. |
| Input packet failure | Prior controller and view retained, no clock or local sample advanced. |
| Paused realtime pulse / read-only snapshot | No simulation or entity phase; only allowed read cache maintenance. |

A single boxed local rollback frame must contain the entire prior W.View, SP,
minor, H history, LI cache, player metadata, sprint flag, pose/eye, controller,
entity metadata at that anchor and prior error/report data. Restore all of those
after LI, context, TH prepare/MH/finish, P.finish, rotation fuel, pose-query or view
projection failure. MH rollback alone is insufficient for the enclosing tick
because successful input/cache/sprint phases may already have produced candidate
fields. Late pose failure must also restore moved Body/support/minor/history.

Retain returned Tables and the returned engine owner; canonical Core sections,
trie structure/revision, clocks, pending operations and events must equal the
post-world-step anchor except for separately authorized operations. No second
engine/world is manufactured to recover. Nonempty owned tails are returned
verbatim before extraction. Diagnostic last_error may be replaced deliberately
after rollback, but must not cause a partial gameplay commit.

The actual scheduled sprint failure increments count 8→9 and snapshots old
position before failing in base tick. It establishes that scheduler work already
occurred, not a Java transaction. Other partially executed Java fields can also
remain after an exception. Whole local rollback is an explicit Bend extension
protecting valid simulation state in the stated pure projection. It cannot undo
external packets, damage, audio, block callbacks or arbitrary mod effects; those
require their own execution/commit contracts before admission.

## Dependency status and actual domain

| Dependency | Status at this read-only snapshot | Consequence |
| --- | --- | --- |
| Current PlayerRuntime | Native plain-player/runtime behavior passed; full runtime kernel timed out/unverified. | Reuse actor ownership/time discipline; do not claim local lifecycle or reuse its appended support timing. |
| LI | Independent actual helper/control/aiStep observations and native comparisons passed; recorded kernel pass for stated laws. | Reuse local cache/input preparation; external fits/attributes/lifecycle remain conditional. |
| LTW | Native local aiStep motion/metadata corpus passed; full source kernel mismatch, whole-module proof unverified. | Ordering example only. Its TW path does not own new minor/history or late pose/rotation. |
| Rotation | All-finite camera projection: 594 native checks twice; full source/eleven-law harness kernel passed. | Reuse snapshots/count/fuel loops. Position/interpolation/invulnerability/head/body lifecycle still missing. |
| FallHistory | 239 projected steps/478 paired observations; bounded native pass; full source/twelve-law harness kernel passed. | Reuse authoritative F64 reducer, fixed no-damage/clip context. No damage/callback simulation. |
| LM | Frozen native actual neutral motion/recovery/remap pass; full kernel mismatch/unverified. | Reuse internal support/minor velocity/order and conservative query admission. |
| MH | Frozen native two identical suites: 83 admitted observed moves, two measured exclusions, 28 recoveries and 14 remapped moves each; full source kernel mismatch, harness skipped. | Sole persistent motion/history owner. Root retained-output audit is separate and pending at assignment. |
| TH | Ordinary prepared source/harness; five source laws; three-call Java debug only; broad extraction and native/kernel pending. | Conditional prerequisite; no runtime execution authorized by this document. |
| Pose | Frozen bounded native pass: 243 exact raw rows, including 46 actual update cases (44 admitted), 86 fit queries and 29 rejection/recoveries; one full-import harness kernel pass including four source laws. | Conditional late phase; world-backed query adapter not supplied by Pose; lifecycle flags are preseeded conditions. |
| Actual phase corpus | 16 distinct entry calls, 15 successes/one fixture service failure; 540 snapshots; paired receivers and two runs. | Establishes measured order/cache latency and gaps, not whole-game acceptance. |

Initial combined domain is the **intersection**, not the union, of these
contracts. It must be explicit in the integration API:

- Finite valid Body/box/input fields; the existing signed-i32 ClientWorld floor
  admission and padded scan extents of 3 through 16 on each query axis. Finite
  four-state palette is dynamically resolved: air, stone, dirt, oak planks.
  Unknown/missing state/section never becomes implicit air.
- Known-empty entity collisions and a known-clear finite border interior are
  explicit conditional declarations, with conservative sweeps/support slabs
  inside the admitted interior. Query fuel counts actual reducer answers; an
  insufficient budget rejects rather than omitting a collision.
- Dry neutral, locally authoritative, able to simulate; noPhysics unsupported by
  LM; LI abilities require both mayfly and flying false; no passenger/climbing/
  swimming/effects/nonneutral blocks. Stuck
  multiplier numerically zero, not removed, auto-jump disabled, unit block speed
  and zero restitution. Body onGround, SP state and minor flag retain their
  distinct semantics.
- Actual current keys/processed axes, support-aware block friction, post-sprint
  attributes and jump factors are provenance obligations. T currently validates
  finite yaw, nonnegative finite maximum step, block friction 0..1; movement speed
  0..1024, gravity −1..1 and friction/air-drag modifiers 0..2048. Those broad
  numerical ranges do not establish realistic attribute resolution or broaden
  admitted modes.
- Single finite F64 history; actual MISS/NotRequired evidence; default safe-fall
  distance 3 and multipliers 1/1; exact no-damage landing threshold. No reset-hit,
  damaged landing, fluid/flight/climb/effect reset is inferred.
- All finite raw F32 camera fields admit Rotation's numerical projection, but
  runtime controller/physical-look admission is stricter. Shared rotation fuel
  ≤16,384; huge no-progress states can exhaust and roll back. The Java oracle
  never executes huge unequal full ticks because the actual loops can stall.
- Adult unscaled client pose, coherent selected pose/dimensions/eye, initially
  stable Standing/Crouching only. Pose-specific current flags and real query
  answers are mandatory; forced crawl/other movement gaits remain excluded.
- Neutral base/effect/equipment/presentation fields and no interpolation until
  their adapters exist. Do not treat a boolean `neutral` as independently proven
  absence of full tick effects. In particular sprint particles, arbitrary block
  effects/pushes, network sendChanges and full Minecraft/client construction are
  unresolved.

The scheduler/lifecycle admission needs explicit provenance for client-loaded
true, an ordinarily ticking local nonremoved/nonpassenger/nonfrozen entity,
invulnerableTime zero and no active interpolation. Positive invulnerability
countdown is not implemented by Rotation; an active interpolation handler can
change current angles between the snapshot and count increment. If those facts
cannot be established from owned state/services, reject the local phase rather
than asserting them from the existing Body. Sleeping/spin/gliding/swimming and
other pose flags remain false in the proposed Standing/Crouching runtime domain.

Current player-record persistence stores the plain player/support/PL snapshot.
It omits LI cache, minor/fall history, pose/eye, entity count and old position.
It cannot be rebranded as a complete local runtime record. A future versioned
custom record must define which fields survive restore, which physical/mouse
fields clear, and how cached keys/pose/history coherence is restored, then test
interruption/corruption/owner recovery. Vanilla save parity is not established.

## Integration acceptance obligations

After TH validation/freeze, first pin its and Pose's exact generations and replace the
old runtime path in a separate owned task. Compare the integrated phase outputs
against unchanged actual histories, including first press/release dimensions,
old/current camera angles and entity count, original-velocity support/minor,
fall signed-zero/narrowing/landing, gravity/drag and final eye position. Test
post-commonTick rollback separately from preacceptance/direct-phase rollback,
with complete canonical Core and all local-owner retention.

Use real conditional query producers for pre-control fits, support/friction,
reset clips and late Pose fits. Verify each query's phase/body/box and do not
reuse unrelated fit answers. Add failures after candidate history/rotation/pose
changes, then reuse every returned owner. Confirm packets/snapshots/frames do not
advance either clock and pause/explicit step have the intended distinct behavior.

These are future test requirements, not tests performed by this design task.
Whole visible OS-input acceptance, renderer/audio/network/full lifecycle parity
remain governed by the project contract and need their own evidence. This task
reads source and existing receipts only; it launches no compiler, native binary,
Java receiver, window or UI.

The lightweight audit hashes 59 consulted source/document/reference/receipt files,
checks seven current source-to-receipt bindings, verifies the two complete ignored
phase-report hashes and reconstructs every delta-encoded phase to its exact
recorded final state. Both four-frame shift histories and the scheduled failure's
counter increment are checked directly from the existing corpus. These checks
validate this document's inputs; they do not execute a new runtime. The ignored
metadata script and canonical JSON serialization are pinned in the snapshot.

Primary review handles:

- [Actual tick phase audit](PLAYER_TICK_PHASES.md), [complete checked phase corpus](../reference/player_tick_phases.json), and [phase integrity receipt](../evidence/player-tick-phases-audit.json).
- [Current plain-player runtime](PLAYER_RUNTIME.md) and [existing local aiStep adapter](LOCAL_TICK_WORLD.md).
- [Frozen movement/history owner](LOCAL_MOVE_HISTORY.md) and [frozen MH handoff](../evidence/local-move-history-handoff.json).
- [Prepared TH contract](LOCAL_TRAVEL_HISTORY.md) and [its three-call debug receipt](../evidence/local-travel-history-reference-debug.json).
- [Verified Pose contract](PLAYER_POSE.md), [actual Pose observations](../evidence/player-pose-reference.json), and [native/kernel aggregate](../evidence/player-pose-verification.json).
- [Camera snapshot/normalization scope](PLAYER_ROTATION_TICK.md) and [fall-history scope](PLAYER_FALL_HISTORY.md).
