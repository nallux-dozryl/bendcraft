# Neutral player fall-history phases (26.3)

This module owns only the authoritative `Entity.fallDistance` projection, stored
as an exact F64 payload. It does not own or mutate a body, support cache, position,
velocity, health, attributes, blocks or camera. No runtime consumer has been
changed. Confidence is high for the independently observed phase contracts below;
complete player lifecycle integration is unverified.

## Actual phase contract

The pinned `Entity.move` collision result supplies Y directly to
`LivingEntity.checkFallDamage` and then `Entity.checkFallDamage`. Its position
application branch is taken when `resolved.lengthSqr() > 1e-7` or the separately
rounded `requested.lengthSqr() - resolved.lengthSqr() < 1e-7`. That branch is not a
fall-history update gate. Support/onGround handling follows the position branch,
then the local-authoritative receiver invokes `checkFallDamage` even when position
application was skipped. The actual paired wall fixture skips position application
and leaves XYZ unchanged, yet negative resolved Y increases history.

Dry downward movement executes this exact order:

```
fallDistance = fallDistance - (double)(float)resolvedY;
```

The accumulator is DOUBLE. The displacement is first rounded to binary32 and
then widened back to binary64. It is not the original binary64 resolved Y and is
not a newly subtracted `newPositionY - oldPositionY`. The high-position fixture
observes a rounded position difference separately from the actual callback Y.
Both positive and negative zero fail the strict `resolvedY < 0` test; downward
values that narrow to negative zero still execute the subtraction, including its
IEEE signed-zero behavior.

On ground, accumulation precedes landing callbacks. With positive accumulated
distance the actual receiver invokes `Block.fallOn` and emits `HIT_GROUND`, then
calls `resetFallDistance` unconditionally for ground. Reset assigns **positive
double zero**, including when the prior distance was negative or negative zero.
The fresh stone fixtures execute these actual callbacks and record entry, reset
and exit on a super-calling observer whose field results match a plain receiver.
The support position is recorded as an observation, never used as a substitute
for the actual onGround argument or authoritative distance.

The earlier position branch also tests `distance != 0 && resolved.lengthSqr >= 1`.
When true it clips along the normalized resolved direction, for the lesser of
its length and eight blocks, using `FALLDAMAGE_RESETTING` blocks and water fluids.
A non-MISS result resets history before position application and the later fall
check. This module admits a supplied, actually established MISS only; it explicitly
rejects reset hits. The fresh long-air fixture records the actual `ClientLevel.clip`
MISS and its endpoints, while zero-distance and skipped-position fixtures record
no ray call. The fixture world has real air/stone states; it does not implement
production pack tag loading or establish resetting-block/water-hit parity.

`Entity.move`'s noPhysics branch returns after position/recordMovement, without
fall checking. Its history is unchanged in the actual noPhysics fixture.

## Public API and admission

Import `src/player_fall_history.bend` as `H`:

```text
History Data { distance: F64 }
State Type { history: History }
Movement Data {
  position_applied: Bool,
  resolved_y: F64,
  resolved_length_squared: F64,
  on_ground: Bool,
  clip: NotRequired | Miss | Hit | Unknown
}
movement(mode, movement, state) -> State & Result<Error, Unit>
reset(state) -> State & Result<Error, Unit>
check_accumulation(velocity_y, state) -> State & Result<Error, Unit>
```

`position_applied` means the actual application branch was taken. It does not mean
that position payloads changed: a zero displacement or rounded addition can take
that branch. `resolved_length_squared` must be the actual ordered collision
result's lengthSqr, and onGround must be the actual value at the fall call point.
These are authoritative phase inputs supplied by the caller, not independent
untrusted requests. This reducer does not derive collision, the branch, support,
fluid state, ability/effect state or callbacks. Future adapters must establish
that boundary; there is no such adapter in this task.

`NeutralDryNoDamage` admits the ordinary local-authoritative, dry air/stone
receiver: default SAFE_FALL_DISTANCE=3, block fall multiplier=1 and entity
FALL_DAMAGE_MULTIPLIER=1; no passengers, impulse fall-damage exemptions, altered
attributes, effects, climbing/stuck blocks or special callbacks. Actual 26.3
default damage uses `floor(((distance + 1e-6) - 3) * 1 * 1)`. The source uses the
exact ordered F64 expression `((distance + 1e-6) - 3) < 1` to admit no-damage ground
landings. A distance slightly above three can therefore be admitted. Fresh values
around the floor boundary record actual `calculateFallDamage` and callback/reset
behavior; this is not an older-version ceil rule.

Damaging ground landings return `UnsupportedLanding` with the entire original
owned history. In the unchanged normal-constructor fixture, a real damaging
landing reaches the actual damage/sound path and fails because the declared
Minecraft service has no `gameRenderer` field, leaving accumulated distance before
reset. That is an observed service boundary failure, not a vanilla rejection or a
Bend emulation of damage. The Bend rejection is an explicit narrower contract.

`NoPhysics` admits the measured early history bypass; valid movement metadata is
checked but does not affect the returned history. `WaterOrFluid`,
`FlightOrPassenger`, `ClimbOrEffects`, `UnsupportedWorld` and `NonLocalAuthority`
return `UnsupportedMode`. A required ray accepts only `Miss`; absent/unknown
evidence returns `MissingClipObservation`. Superfluous MISS/unknown evidence
returns `UnexpectedClipObservation`. `Hit` returns `UnsupportedResetHit`.

All finite F64 history values are admitted, without magnitude caps, including
signed zeros and independently seeded negative/large values for field semantics.
This does not claim negative distances are naturally reachable neutral gameplay.
Input history/Y/squared length/delta-Y must be finite; squared length must be
numerically nonnegative. F64-to-F32 overflow or any nonfinite computed accumulator
returns `NonFiniteResult` unchanged. Actual Java direct-check overflow diagnostics
can publish infinity; this is a deliberate finite-state protection in Bend.
All errors preserve the original owner and raw history words. Recovery tests
reuse that owner through a later explicit reset; invalid history remains rejected.

## Other phases and explicit exclusions

`reset` models the distance assignment of actual public `resetFallDistance`, with
a finite-state guard. It does not detect why lifecycle code requested that reset.
`check_accumulation` models actual public `checkFallDistanceAccumulation`: if
authoritative delta-movement Y is strictly greater than `-0.5` and distance is
strictly greater than `1`, replace distance with exact double `1`; otherwise retain
the raw payload. Fresh neighboring Y/distance values establish both strict
boundaries. This phase is separate from move/checkFallDamage. The pinned
`LivingEntity.updateFallFlying` calls it; a consumer must schedule it at the actual
call point rather than inventing a movement post-step clamp.

The pinned bytecode inventory separately identifies fluid interaction resets,
Player flight reset in aiStep, climb/effect/ride resets, bubble-column and
makeStuckInBlock resets, and lava's baseTick multiplication by double `0.5`.
Those lifecycle branches and their service/callback effects are not implemented
or behaviorally certified here. `doCheckFallDamage` has a separate unloaded-chunk
gate and caller-supplied displacement contract; network/server dispatch and its
support handling are also excluded. No damage, health, block callback, effect,
sound, fluid, complete aiStep, full tick or full physics parity is claimed.

## Reproducible evidence

The Java probe derives a private copy of the frozen LI constructor fixture.
It substitutes the same four explicitly declared external service types:
Minecraft, Gui, Tutorial and ClientPacketListener. Actual Entity/LivingEntity/
Player/LocalPlayer/ClientLevel/Block bytes remain from the pinned installed 26.3
jar and are checked in the observed loaded-class tree. FixtureLevel extends the
actual ClientLevel and supplies finite real air/stone lookup/collision chunks.
Observers call super for checkFallDamage, recordMovement, reset and clamp; they
do not replace those algorithms. A direct actual private collide call supplies
an independently retained diagnostic result; its Y must match the later actual
move callback and the observed application gate.

Run from the project directory:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_fall_history_probe.py --extract
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_fall_history_probe.py --rerun
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_fall_history_probe.py --selftest
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_fall_history.py --prepare
# Native/kernel commands require the lead's separately granted heavy slot.
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_fall_history.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_fall_history.py --kernel
```

The checked `reference/player_fall_history.json` retains every fixture input and
actual observation. Compact `evidence/player-fall-history-reference-*.json`
receipts link complete ignored raw sources, stdout, class maps and observations
under `build/player-fall-history-reference/`, with canonical hashes/counts and
commands. Integrity verification rejects six corruptions: jar, runtime, library,
class, launcher and actual observation. Python only orchestrates execution and
converts word encodings; it does not calculate fall-history expected values.

At preparation, 228 paired cases produce 478 actual step observations (239 on each
plain/super-calling receiver). A fresh independent Java execution reproduces the
canonical fixtures and all 4,401 loaded official class hashes exactly. Six real
damaging-land failures and two actual F32-overflow diagnostics are retained,
separately labeled as excluded contexts. Six integrity mutations are rejected.
Ordinary source and harness checks pass. All **298 native comparison/policy cases
pass twice** on the retained installed native executable, in 0.799131 and 0.078863
seconds. The single native generation emitted C in 0.886451 seconds and built in
2.247182 seconds; these are local workload measurements, not full-game speed
comparisons. Full imported production source kernel verification passes in
0.454272 seconds and the complete twelve-law harness passes in 11.958553 seconds.
No projection, proof retry or source/reference repair was used.

`player-fall-history-prepared.json` records the frozen pre-execution hashes and
case categories; native/kernel receipts and the final generation audit bind the
same inputs, executable, emitted C, compiler and 1,629 compilation dependencies.

| Frozen artifact | SHA-256 |
| --- | --- |
| Production source | `b181c43948cc01e66b05e0edf9dbc0338e1ebdcfecbf86a525731a07aad26db3` |
| Harness | `627be53c5657fa6ce1eaa87ae83ccbfc122ce8b087e30f7212289c5f23ed2590` |
| Probe | `c35e70d970e9cd787fc023743716ca73e1c26ea9fdf4b01ac403896e79fdce69` |
| Runner | `f05bfc26a903e6ac82fd2576e1f0fb34e3dfde561babe3db60db62753fb1ea32` |
| Fixture file | `831c2f369cb4b433f62885ab25594db673468f0f80702f25834e786e5ebed320` |
| Native executable | `581b5018df04dad8775753da91efbe27fa395091806b03c283c5243409c44de0` |
| Retained emitted C | `2cfc83817cab5e17c52fa9fb082d58e0bcca957bc3c6b94d991506446f0504ad` |

The twelve laws quantify guarded owner retention, exact reset/clamp assignments,
noPhysics bypass, nonnegative-displacement identity and clip policy. They do not
prove universal numerical/gameplay parity; independent actual receiver fixtures
provide the separately bounded behavioral evidence.
