# Pinned 26.3 player tick phases

This is a phase-order audit, not a full LocalRuntime implementation or a Bend
verification result. Confidence is **high** for the pinned bytecode call sites
and the explicitly observed receiver histories. Behavior outside those histories
remains **unverified**. Static branch layout and executed observations are kept
separate in the receipts.

The source is the installed official 26.3 client JAR, SHA-256
`4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d`.
The audit first reads the current Rotation, LocalInput, LocalTickWorld,
LocalMoveWorld and FallHistory APIs; their exact source hashes are recorded,
without changing any consumer or gameplay module.

## The scheduler is a separate phase

`ClientLevel.tickNonPassenger(Entity)` calls final `Entity.commonTick` at bytecode
offset 23, then virtual `Entity.tick` at 27, then ticks passengers. For the local
receiver, virtual dispatch enters `LocalPlayer.tick`. `ClientLevel.tickEntities`
iterates its entity tick list; its actual bootstrap callback skips removed
entities, passengers and entities frozen by the tick-rate manager before calling
`tickNonPassenger` through `guardEntityTick`. Both synthetic callback targets are
resolved from the actual class's `BootstrapMethods`, not inferred from names.

`Entity.commonTick` performs these operations in order:

1. Decrement positive `invulnerableTime`.
2. `setOldPosAndRot`: copy old position, then current yaw/pitch into old angles.
3. On the client, invoke the interpolation handler.
4. Increment the signed Java `tickCount` word.

Calling `LocalPlayer.tick` directly does not invoke that scheduler phase. The
fresh direct-tick history retains `tickCount=40` across four calls; scheduled
histories advance exactly once per call, including the call which later fails at
the declared service boundary. An entity skipped by the outer iteration does
not reach either phase. This differs from a tick which reaches `commonTick` but
whose local `tick` returns early because `connection.hasClientLoaded()` is false.
The latter load guard is established statically and is not exercised here.

The official `Minecraft.tick` has an additional outer order when a level exists
and the client is unpaused: tick-rate-manager tick at 31, game mode at 82, keybind
handling at 174 when no screen/overlay blocks it, renderer tick at 221,
`ClientLevel.tickEntities` at 237, block entities at 253, live local-player
`sendChanges` at 286, then the later `ClientLevel.tick(BooleanSupplier)` at 405.
Music/sound, level animation/particles, a client-tick-end packet and the keyboard
handler occupy their own guarded stages. `sendChanges` is a separate local method
in this JAR; local `tick` does not call it. Client-level time/weather/chunk work
is distinct from entity `tickCount`. This outer order is **static evidence only**:
the narrow receiver fixture substitutes the Minecraft service and does not run
actual `Minecraft.tick`. It establishes no server tick ordering or correspondence
between client clocks and the project's Core world-step operation.

## Inherited local tick order

The inheritance path is `LocalPlayer -> AbstractClientPlayer -> Player -> Avatar
-> LivingEntity -> Entity`. The actual Avatar class introduces no `tick` or
`aiStep` override in this JAR, so those special superclass calls resolve to the
inherited LivingEntity implementation.

| Stage | Actual call sites and relevant ordering |
| --- | --- |
| Local wrapper | LocalPlayer checks client-loaded at 4; ticks the drop-spam throttler at 15; calls the superclass at 19; first-person hands/items at 27; then each ambient sound handler at 60. |
| Avatar presentation | AbstractClientPlayer ticks its ClientAvatarState with current position/delta-movement at 12, before Player.tick at 16. |
| Player prelude | Player sets spectator `noPhysics`, clears ground for spectator/passenger, updates XP/sleep timers, calls `updateIsUnderwater` at 169, then inherited tick at 174. |
| Entity/Living base phase | LivingEntity.tick calls Entity.tick at 1; Entity.tick virtually calls baseTick. LivingEntity.baseTick ticks swing/sleep/enchantment paths, then Entity.baseTick at 50; its later effect/timer paths copy head/body old rotations. Entity.baseTick includes speed computation, portal, conditional sprint particles, powder-snow cache, fluid interaction at 100 and swimming at 105, followed by fire/lava/below-world/lifecycle paths. |
| Living movement | If not removed, LivingEntity.tick virtually calls aiStep at 178. This enters actual LocalPlayer.aiStep. |
| Living after movement | Head-turn work follows aiStep. Old yaw, body yaw, pitch and head yaw normalization loops are inline in LivingEntity.tick, followed by flight/sleep, dirty-attribute refresh and Elytra animation work. There is no called `rangeChecks` method; that name is a profiler section. |
| Player after inherited tick | World-coordinate clamping, attack/item timers, equipped-item/turtle-helmet/cooldown paths precede `updatePlayerPose` at 335. Pose selection therefore occurs after movement and inline rotation normalization. |
| Local postlude | First-person hands/items and ambient handlers run after Player.tick returns. These call sites are pinned statically; the observer does not independently isolate their algorithms or certify audio/presentation. |

The exact field writes, method descriptors, class bytes, guarded instructions and
offsets are available through `evidence/player-tick-phases-bytecode.json` and its
ignored full disassembly artifacts. Ascending bytecode offsets describe layout;
they are not a claim that every branch is executed.

## Input cache, crouch and dimensions use different phases

In actual LocalPlayer.aiStep, positive sprint-trigger time is decremented first.
Portal/spinning paths follow. Previous `input.keyPresses` supplies old jump/shift
and forward state. The crouching cache is computed before current key sampling:
the `crouching` field is written at 158, then `ClientInput.tick` is called at 165,
followed by tutorial input at 179. LocalPlayer's `isShiftKeyDown` reads that input
cache directly. Current keys subsequently drive push-out, ordered sprint setter,
flight/gliding/fluid/riding paths. The inherited aiStep begins at 1106.

AbstractClientPlayer.aiStep calls its avatar bob update before Player.aiStep.
Player's inventory/regeneration/flight reset paths precede inherited LivingEntity
aiStep. LivingEntity performs countdown and velocity cleanup, invokes virtual
`applyInput` at 208, handles immobility/server AI and jump paths, then travel.
The actual local override supplies the LocalInput decay/square/slow-input path;
calling PlayerTick.prepare afterward would apply the different decay again.
This is why the frozen LocalTickWorld starts with LocalInput.prepare and goes
directly through travel/movement/PlayerTick.finish.

The fresh scheduled and direct shift histories each observe:

| Frame | Newly held shift | Cached `crouching` during movement | Actual height during movement | Pose/height after Player's pose update |
| --- | --- | --- | --- | --- |
| First hold | true | false | `3fe66666` (1.8f) | CROUCHING, `3fc00000` (1.5f) |
| Second hold | true | true | `3fc00000` | CROUCHING, `3fc00000` |
| First release | false | true | `3fc00000` | STANDING, `3fe66666` |
| Second release | false | false | `3fe66666` | STANDING, `3fe66666` |

Thus setting pose/body dimensions before the first new-shift movement would
change the actual query geometry. Treating cached crouching as the current pose
also fails on the first hold/release frames. The snapshot records keys, cached
crouching, pose, current width/height, exact body AABB and position separately.

The static pose selection in Player.updatePlayerPose first asks whether SWIMMING
fits. A false answer returns immediately. Otherwise it obtains desired pose:
sleeping, swimming, fall flying, spin attack, or current shift while not flying,
then standing. Spectator/passenger paths accept the desired pose; the normal
path tests its fit, falls back to CROUCHING if that fits, otherwise SWIMMING.
`canPlayerFitWithinBlocksAndEntitiesWhen` uses actual dimensions for the proposed
pose at current position, deflates its AABB by double `1e-7`, and invokes
`Level.noCollision(entity,box)`. This requires block/entity/border semantics and
an exact query, not an assumed empty collider list. In these open-floor traces
the requested standing/crouching poses fit. Forced crawl, obstructed standing,
sleeping, swimming, gliding and spin-attack branches are **not observed here**.
Entity's visual-crawl test also considers visual swimming and water; local
`isMovingSlowly` tests cached crouch or visual crawl. No unobserved fit/crawl branch
is admitted by these observations.

## Eye height is an actual cached field

The observer records actual cached `eyeHeight`, actual zero-argument
`getEyeHeight()`, the new pose's dimension metadata, and raw F64
`getEyePosition()` at every boundary. It never derives eye height from a body
height ratio. The field/getter agree for all 572 measured state samples.

| Stable pose | Body height F32 | Cached/getter eye height F32 | Actual eye Y when feet Y is exactly 1 |
| --- | --- | --- | --- |
| STANDING | `3fe66666` | `3fcf5c29` (1.62f) | `4004f5c290000000` |
| CROUCHING | `3fc00000` | `3fa28f5c` (1.27f) | `400228f5c0000000` |

`setPose` updates synced data, which calls the virtual synced-data handler. The
inherited Entity handler refreshes dimensions for the pose accessor. In actual
Entity.refreshDimensions, dimensions are assigned at 18, cached eye height at
26, and `reapplyPosition` is invoked at 30. `reapplyPosition` calls setPos with
the retained current coordinates, rebuilding the body AABB. The later server
size-growth adjustment is guarded away for the observed client player.

All four observed refreshes retain the exact position words. Width and horizontal
AABB coordinates remain identical; AABB maxY and cached eye height change.
At `dimensions_entry`, the new pose is already selected while old body/eye values
are still cached; after refresh the caches match the new pose metadata. The
first-shift aiStep and move therefore use the standing eye height, whereas the
completed tick exposes the crouching eye height. First release reverses this
after movement. These callback snapshots describe actual transient ordering;
they are not separately admitted runtime states.

A future view adapter needs the authoritative eye offset corresponding to its
chosen snapshot phase, widened from the actual F32 value before F64 position
arithmetic. It also needs old position/interpolation handling for interpolated
eye views. Zero-argument eye position is observed here; the static interpolated
`getEyePosition(float)` path is pinned but not independently exercised. The
existing fixed instrument camera does not establish this lifecycle behavior.

## Movement hooks and post-travel effects

For the observed normal local-authoritative movement path, Entity.move has the
following order. Early `noPhysics`, removed, piston/stuck, nonauthoritative and
simulation-disabled branches have their own guards and are not generalized by
this list.

1. Apply admitted movement preprocessing; Player edge backoff at 186 produces the
   request used by private collide at 192. It does not replace delta-movement.
2. Evaluate the movement application gate. Its admitted path performs an optional
   earlier fall-reset ray, records the movement path, applies position and calls
   recordMovement. A skipped gate retains the old position/box.
3. Establish collision flags and call `setOnGroundWithMovement` at 530 in the
   local-authoritative path. Support selection receives non-null resolved
   displacement even for zero movement and when the application gate skipped.
4. If horizontally colliding, call `isHorizontalCollisionMinor` at 544.
5. Read `getOnPosLegacy` at 559 and its actual block state, then call
   `checkFallDamage` at 596 under the authority guard. LivingEntity's override
   can refresh fluid interaction before Entity's history/callback path.
6. If removed, return. Otherwise the simulation guard admits private restitution
   at 648; movement emission/sound at 698 has additional client-authority,
   emission and passenger guards; block speed-factor scaling follows at 702/722.
7. LocalPlayer's wrapper calls updateAutoJump at 41 and addWalkedDistance at 56
   after the inherited move returns.

Support, minor and fall observers see the final position/box/flags with the
pre-restitution delta-movement. The actual blocked fixture observes support,
then one minor call, then fall. Its original velocity remains present at those
callbacks and changes by move exit. Private restitution is not overridden or
directly instrumented: its exact placement is static, while the surrounding
callback states and final velocity are observed. Six measured moves skip the
application gate but still call support and fall. The real step resolves Y to
exact F64 `3ff0000000000000` and updates legacy supporting position accordingly.

After travel returns, LivingEntity.aiStep calls applyEffectsFromBlocks at 628
for server or locally authoritative client, then client animation and later
push/actor/server-effect paths. Actual applyEffectsFromBlocks collects queued
movement paths, constructs a fallback old-to-current path if needed, performs
ground block `stepOn`, inside-block effects and fire/rain-related work. This is
**after** travel's gravity/drag completion, unlike support/minor/fall hooks inside
move. All successful traces observe the block-effects entry and exit; their
stone/air contexts do not certify arbitrary block/effect callbacks.

`checkFallDistanceAccumulation` is not an unconditional neutral post-move clamp.
LivingEntity.aiStep calls updateFallFlying at 494 only if isFallFlying at 487 is
true; updateFallFlying calls the clamp at 1, before that travel stage. Slow-fall
and levitation have separate reset guards. The 15 successful neutral traces
observe no gliding/clamp call. FallHistory remains a separate admitted projection
with explicit reset-ray and no-damage context, not a complete fall/damage effect.

## Integration gaps

The measured APIs can compose the declared motion projection. A full LocalRuntime
still needs these separately resolved phases:

- Entity old position/interpolation, invulnerability/lifecycle state and the
  correct scheduler/load/freeze admission around tickCount and rotation snapshots.
- Actual pose-fit selection, dynamic dimensions/AABB and authoritative cached eye
  metadata after movement. Open-floor shift observations do not admit crawl or
  obstructed standing.
- Base-tick portal, sprint-particle, fluid/swimming/fire/lava/environment/equipment
  paths and local presentation/service callbacks.
- Movement hooks at their actual internal timing. Appending support/minor/fall
  after a finalized TW/LTW transition misses their original-velocity and
  pre-restitution context. LocalMoveWorld's temporary BodySnapshot is intended
  for this boundary but its verification status is independent of this audit.
- Authoritative fall history, required ray evidence, damage/block/game-event
  callbacks, movement emission, speed factors, autojump/walked distance and the
  after-travel inside-block/stepOn/push paths.
- Player post-inherited timers/cooldowns/bounds/pose, local first-person/ambient
  work, and the separate sendChanges/network stage. Full Minecraft/UI/audio/clock
  integration is not executed by this receiver fixture.

The second scheduled sprint frame stops in actual
`Entity.spawnSprintParticle -> ClientLevel.addParticle -> doAddParticle` during
baseTick. The unchanged headless Minecraft service lacks its `gameRenderer`
field. This is a **fixture service gap**, not a vanilla rejection or a runtime
gameplay failure. It occurs before that frame's aiStep, keyboard sampling or
planned jump; the rest of that history is not executed. No additional service
mock or replacement algorithm was introduced to conceal it. The separate
non-sprint jump history completes through untouched full local ticks.

## Reproduction and receipts

Run from the project directory:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_tick_phases_probe.py --inventory
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_tick_phases_probe.py --extract
```

The second command runs two fresh Java extractions, each capped at 120 seconds
with process-group termination. Final measured runs took 5.395155 and 5.172782
seconds. It makes no Bend/native build. Normally constructed actual
ClientLevel/LocalPlayer/KeyboardInput receivers execute the official methods.
The same four LI external service fixtures are copied privately: Minecraft,
Gui, Tutorial and ClientPacketListener. Super-calling observers only record
boundaries; the plain receiver independently matches every before/after state
and failure. All 4,391 recorded official class-byte hashes match the installed
JAR, including the complete player inheritance chain. This is the observed
class set, not a claim that every client class or gameplay branch ran.

Seven histories execute 16 distinct entry calls: 15 complete and one recorded
service failure. Each is run plain and observed in both extractions, for 64 actual
receiver calls total. There are 540 phase snapshots in the observed corpus. Exact
states, phases, failure and service records match the fresh rerun. The observed
world is the same 25-stone floor at `x,z=-2..2,y=0`, all other cells air, with one
declared stone at `(1,1,0)` in the blocked/step histories.

`reference/player_tick_phases.json` retains explicit inputs and compact
delta-encoded phase snapshots. Every phase snapshot reconstructs exactly from
its step's initial snapshot and ordered field changes; no eye/body fields are
dropped. Full LI observer records, fixture source, launcher, disassembly,
class tree, stdout and stderr remain in ignored `build/player-tick-phases/`.
`evidence/player-tick-phases-observed.json` and
`evidence/player-tick-phases-bytecode.json` contain compact hashes, counts,
call-site summaries and pinned raw-artifact references. No existing production
module, consumer, compiler, root status document or LTW artifact changes during
this phase audit.
