# Local keyboard and input phases — Java 26.3

`src/local_input.bend` passes ordinary type/termination checking, independent
kernel checking, and native comparisons against direct actual Java 26.3 calls.
Confidence is high for the recorded input/control and pre-travel phases. The
reference directly executes actual `Options`, `KeyboardInput`, `ClientInput`,
`Vec2`, private `LocalPlayer` helpers, and a normally constructed LocalPlayer's
untouched `applyInput` and neutral `aiStep` through inherited travel. Full
LocalPlayer ticking, the Minecraft client lifecycle, rendering, networking,
and operating-system input remain outside this evidence.

## Production boundary

The authoritative world/body remains in the existing world bridge. This module
retains only previous sampled keys/vector, the signed Java-int sprint timer,
the crouching flag, and four float bob caches. Device-held keys are separate
from the previous sampled keys. Both use `player_input.Buttons`; vectors use
`player_input.Vector`.

`controls_checked(state, current_sprinting, held, context)` returns a checked
`Controls {state, sprinting, sprint_updates}`. The context supplies actual standing/crouching
fit results, current food/ability observations, previous major/minor collision
flags, configured sprint-window value, current pose, and admission mode. The
caller resolves current attributes after this sprint decision. In particular,
the actual Java `setSprinting` removes and conditionally adds the sprint
attribute modifier; it cannot be represented by blindly scaling a prior
resolved speed. The ordered boolean setter list preserves duplicate true
updates and a later false update when production executes those calls.
Attribute resolution replays those setters before sampling the current speed.

`prepare_checked(tables, controls, player, ApplyContext {tick, sneaking_speed,
pitch})` returns the sole Tables owner and a checked
`PreTravel {local, player: PlayerTick.PreTravel}`. `tick` contains the actual
post-decision movement/gravity/jump attributes and degree-valued float yaw;
pitch is also a Java degree-valued float. This facade uses the frozen
PlayerTick cleanup, signed countdown, and jump helpers. It replaces xxa/zza
and jumping through the LocalPlayer input path, preserving yya. Calling the
generic `PlayerTick.prepare_checked` afterward would decay xxa/zza a second
time and is incorrect.

Every rejection retains the affine Tables owner. Bodies and controller state
are immutable data, so the caller retains the previous values for rollback.
Preparation validates admission, existing state, resolved attribute ranges,
and computed float results before looking up jump trigonometry. A mismatch
between the chosen sprint state and travel context rejects.

The checked signatures are:

```text
controls_checked(State, Bool, PlayerInput.Buttons, Context)
  -> Result<Error, Controls>
prepare_checked(Locomotion.Tables, Controls, PlayerTick.State, ApplyContext)
  -> Locomotion.Tables & Result<Error, PreTravel>
```

`State` has `keys`, `movement`, raw signed-int `sprint_trigger`, `crouching`,
and F32 `x_bob`, `y_bob`, `x_bob_old`, `y_bob_old`. `Controls` adds the final
`sprinting` and ordered `sprint_updates`. `PreTravel` holds the next local
state and the prepared `PlayerTick.PreTravel`. There is no second LocalInput
finish operation: integration uses the prepared player's input for checked
world/travel, then calls `PlayerTick.finish_checked`. An adapter must retain
the prior local state as well as the authoritative world Body for complete
rollback. A control result already advances the sampled input cache.

## Observed order and numerical operations

Actual `KeyboardInput.tick` samples seven real key mappings. Opposing buttons
cancel; the two impulses are normalized through actual float Vec2 operations.
All 128 masks have been observed. Forward-left yields `3f3504f3` in both
components. Private square correction directly applied to that vector yields
`3f3504f4` in both components, demonstrating why a double-normalized input or
mathematical real-number shortcut does not establish exact behavior.

LocalPlayer's control phase decrements a strictly positive sprint timer and
reads the previous jump/shift/forward state. It computes crouching from the
previous shift state and actual fit results before ticking the input. It then
clears the timer for previous shift, item slowdown, or new backward input;
detects a forward double tap; applies held sprint; and evaluates sprint stop
conditions using current forward input, food/mobility, and prior collision
flags. Consequently newly held shift and newly released shift have phase
latency in the crouching flag. Current entity pose is a distinct observation;
the crouching boolean does not establish a body dimension.

Actual LocalPlayer input replacement returns a zero-length input unchanged.
Otherwise it scales by `.98f`, conditionally scales by the float narrowing of
the resolved SNEAKING_SPEED double attribute, and applies the exact float
square-speed correction. Every multiply, add, subtraction and division is a
separate F32 operation. Mth.sqrt(float) widens to double, calls Math.sqrt, and
narrows to float; the checked implementation uses the already verified pure
F64 square root and float conversion. Bob caches copy old values before the
separately rounded `old + (angle - old) * .5f` updates.

## Explicit remaining scope

This neutral controller admits controlled-camera, dry-air, nonpassenger,
nonitem-use, nonswimming, nonflying, nonspectator, nonautojump, nonportal,
nonimmobile, effect-free contexts with standing or crouching pose. May-fly and
flying abilities currently reject. Screens and other nonneutral modes reject.
Fit and collision observations must be resolved from actual authoritative
world/state, never supplied as unconditional truth by integration.

LocalPlayer.aiStep also attempts four `moveTowardsClosestSpace` calls before
the sprint/travel phase. The current boundary requires an observed context
where these do not change velocity. Player's crouch edge-backoff and
LocalPlayer's minor-horizontal-collision helper remain separate required
movement work. The minor helper uses a double rotated-input dot product,
Math.sqrt and Math.acos; inheriting generic Entity's constant false answer does
not match LocalPlayer. Crouching near ledges and overlap/push-out contexts
cannot be generalized from flat-world fixture results.

Entity.commonTick resets old position/rotation before client interpolation;
LocalPlayer.aiStep does not perform this reset. LivingEntity.tick later wraps
past yaw/head/body/pitch by 360f to keep adjacent differences within its range.
An aiStep-only controller composition cannot claim those full tick phases.

## Direct oracle and evidence

The fixture uses normal `LocalPlayer`, `AbstractClientPlayer`, `Player`,
`LivingEntity`, `Entity`, `ClientLevel`, and `Options` constructors. Official
gameplay bytes are untouched. Four external service classes are substituted:
`Minecraft` supplies identity/camera/options and inert lifecycle services;
`ClientPacketListener` supplies a deterministic profile, real player/clock/
registry metadata and an outgoing packet sink; `Gui` has no screen;
`Tutorial.onInput` is a sink. No production Minecraft constructor, window,
unsafe allocation, installed options, or user account data is used.

The real ClientLevel fixture contains exactly 25 stone floor blocks at
`x,z=-2..2`, `y=0`, otherwise air. Labelled ceiling cases add actual oak top
slabs. Actual dimension/biome/damage registries are used with explicitly empty
environment timelines and tags in this neutral context. State/fluid/chunk
queries supply the actual fixture states. These return contracts and service
substitutes are declared in `reference/local_input.json`; they do not establish
complete ClientLevel behavior. Observers call production super methods and
each final receiver is compared with an independent unobserved receiver.

The frozen direct corpus has 128 keyboard masks, 2,048 vector cases, 112
input receivers and 28 actual aiStep histories containing 140 ticks. An
independent Java rerun reproduced every recorded observation and the loaded
4,398-class provenance tree. Verification checks the installed official client,
runtime, all 80 library fingerprints, class/method inventories, receiver and
launcher sources, and observation digest. Six injected provenance/observation
mutations were rejected. See
`evidence/local-input-reference-independent.json` and
`evidence/local-input-reference-integrity.json`.

Native comparison covers all 128 actual keyboard masks; 2,048 square/length
helper cases; 112 input modifiers, 224 bob operations and 112 sprint predicates;
211 applyInput projections; and 130 neutral control/pre-travel projections.
The remaining ten aiStep ticks exercise visual-crawling or blindness contexts
that checked neutral controller admission rejects. Static helper comparison
includes nonfinite operands, with NaN class comparison only. Finite results,
infinities and signed zero compare exact raw bits. Generic Vec2 normalization
is retained as reference data; native normalization coverage here is the full
keyboard specialization already provided by PlayerInput.

The driver also checks 26 histories/130 ticks with native controller caches
fed into the next native control phase. Subsequent Body/PlayerTick metadata
comes from actual Java observations; this is not a native full physical-tick
trajectory claim. Thirty-two explicit rejection cases retain the real Tables
owner and are followed by a valid preparation in the same native process.
Five malformed protocol cases reject. Project-only `jump_attempted` and
`jumped` labels are not compared with nonexistent vanilla fields; actual
pre-travel state/vector and direct jump call observations provide the oracle.

The final narrow native build took 5.447114 seconds. Independent kernel
verification took 4.893707 seconds and reported `ALL PROOFS CHECK` for the
complete import closure and four quantified production laws: rejection owner
retention, rejected controls not sampling held keys, preserved vertical input,
and ordered duplicate sprint setters. Timings describe this verification run,
not game performance. All nine source hashes were unchanged during both jobs.

Final implementation SHA-256:
`5e3555fdb06258a76478a32d32332455ad186ec956607ce981e198a3c28ca02e`.
Reference SHA-256:
`1b75b5db33e516c417c27033cb9cf12b3d6d1b66ba03e366416dac1d3da98d8d`.
The final manifests contain dependency, compiler, runtime, tool, reference and
binary hashes in `evidence/local-input-verification.json`,
`evidence/local-input-build-final.json` and
`evidence/local-input-kernel-final.json`.

Reproduce the direct actual oracle with
`python3 tools/reference_local_input_probe.py --rerun`, and its integrity and
mutation checks with `--selftest`. Use `--extract` to regenerate the stored
corpus; see its CLI for receiver-only experiments. Run the native build,
bounded kernel check, and
all comparisons with `python3 tools/test_local_input.py`. To reuse completed
checks, use `--skip-build --skip-checks --reuse-checked`; reuse verifies exact
source and binary hashes before accepting the previous checks.
