# Neutral mouse accumulation and scaling

`src/mouse_input.bend` provides checked pure F64 mouse accumulation and produces the double arguments supplied to `Entity.turn`. The caller passes those returned deltas to `PlayerLook.turn` once. This module receives actual focus/capture observations; it does not query or change an OS window.

```text
State{position_x, position_y, accumulated_x, accumulated_y:F64,
      ignore_first_move:Bool}
Move = PointerMove{x,y,relative_x,relative_y:F64,window_matches:Bool}
Options{sensitivity:F64,invert_x,invert_y,smooth_camera,scoping:Bool}
Deltas{dx,dy:F64}
Frame{state:State,turn:Maybe<Deltas>}

initial() -> State
ignore_next_move(State) -> State
on_move(State,Move,focused:Bool,captured:Bool) -> Result<Error,State>
relative(State,dx:F64,dy:F64,focused:Bool,captured:Bool) -> Result<Error,State>
finish(State,Options,focused:Bool,captured:Bool,player_present:Bool)
  -> Result<Error,Frame>
```

All positions and accumulated values preserve raw F64 bits, including signed zeros. `initial` has four positive zeros and `ignore_first_move=true`, matching the actual MouseHandler constructor. Capture and focus are explicit caller inputs; the actual constructor has mouse capture false. The constructor `PointerMove` avoids the existing Base constructor named `Move`.

## Observed handler semantics

Actual pinned Java 26.3 SDL mouse-motion fields x/y/xrel/yrel are F32, widened exactly to F64 before `MouseHandler.onMove`. A presenter starting from OS F32 deltas must use exact widening, preserve event order, and accumulate with F64 addition. It must not apply sensitivity using F32 arithmetic or replace the actual default scale by one.

`on_move` implements these actual pure field changes:

- A zero or different window handle is represented by `window_matches=false` and preserves the complete state.
- A matching first move updates absolute position, clears the first-move flag, and discards its delta even when unfocused.
- Subsequent focused, captured moves add supplied relative deltas to the accumulation. Absolute coordinate changes do not substitute for those relative deltas.
- Subsequent focused, uncaptured moves add `x-old_x` and `y-old_y`, each using ordered F64 subtraction then addition. Supplied relative deltas are unused in this branch.
- Unfocused subsequent moves update position without accumulating movement.

The captured-only `relative` convenience retains the absolute position supplied by the caller and delegates the same accumulation/first-move behavior. It rejects uncaptured mode with `UnsupportedRelativeMode`, because that mode needs an absolute coordinate observation. `finish` still supports uncaptured/inactive frames: it clears the accumulation and returns no turn. `ignore_next_move` lets the caller re-arm the actual discard policy after capture transitions.

## Exact neutral scaling

`default_options` contains sensitivity Double 0.5, invert X/Y false, smooth camera false and scoping false. These are defaults, not reads of the user's saved settings. Actual constructor/default bytecode and constructed OptionInstance behavior are recorded separately in the reference.

The normal neutral path uses this exact binary64 order, rounding after every multiply and add:

```text
a = sensitivity * 0.6000000238418579d
a = a + 0.20000000298023224d
cube = (a * a) * a
scale = cube * 8.0d
dx = accumulated_x * scale
dy = accumulated_y * scale
```

The two coefficients are exact F64 promotions of 0.6f and 0.2f: `3fe3333340000000` and `3fc99999a0000000`. Actual default unit accumulation reaches both Tutorial.onMouse and LocalPlayer.turn as raw double `3ff000001800000c` (1.0000000894069698). Tutorial receives the scaled values before inversion; the player receives optional per-axis `dneg` afterward. This module returns the latter pair and does not implement tutorial callbacks.

The subsequent Entity operation first narrows these arguments to F32 and then multiplies by 0.15f; that belongs to `src/player_look.bend`. Mouse scaling is not folded into a guessed final radians coefficient.

All arithmetic here uses the existing checked F64 integer-word implementation. There is no host float arithmetic, Foreign function, unsafe definition, native parser, or native gameplay adapter in this module.

## Checked policy and wrapper boundary

Positions, accumulated values, all four move numbers, and returned turn deltas must be finite. Sensitivity must be finite and in [0,1], with either sign of zero admitted. Validation always checks the whole initial state and whole move, including values that an inactive or invalid-handle production path would ignore. `finish` also checks options on inactive frames. These are explicit additional bounded simulation admissions.

Error priority is deterministic: state fields position X 0, position Y 1, accumulated X 2, accumulated Y 3; then move fields x 0, y 1, relative X 2, relative Y 3. Finish checks state first, then sensitivity, smooth-camera policy, and scoping policy. New accumulation or delta overflow yields `NonFiniteAccumulation{axis}` or `NonFiniteDeltas{axis}`, X 0 before Y 1. Unsupported uncaptured `relative` rejects its mode before evaluating its state/input values.

`State`, `Options`, `Deltas` and `Frame` are Data. A failure returns no partial updated state or deltas, and the caller can retain its prior state. `ignore_next_move` and `clear` are pure field helpers, so they assume the caller already holds a valid state.

Actual private `turnPlayer` preserves accumulatedDX/DY; it resets normal-branch SmoothDouble fields. This was executed and observed. The surrounding `handleAccumulatedMovement` frame wrapper reads an SDL timer, gates turning on focused/captured/non-null-player state, then clears accumulation to positive zero even when inactive. That wrapper was inspected as pinned bytecode and was **not executed** by these tests. `finish` implements this explicit pure gate/reset policy; its reset is not attributed to a direct private-turn observation. Pause is not an independent predicate in the inspected methods; the per-frame mouse call precedes the frame's pause-state update. Screen/menu capture transitions remain the caller's responsibility.

Smooth camera and scoping are rejected explicitly. Actual smooth-camera behavior needs persistent SmoothDouble state and elapsed time. Actual first-person scoping uses the sensitivity cube without the factor eight. This module admits neutral non-scoping input; camera type has no effect in that branch. It does not approximate either unsupported path or support switching into them with unrepresented filter state.

## Reference and verification

`tools/reference_mouse_input_probe.py` constructs real MouseHandler, SmoothDouble, ScrollWheelHandler, OptionInstances and inactive Tutorial objects. Fixture-only Unsafe allocation skips Minecraft, Options, Window and LocalPlayer constructors. Window handle/focused getters read injected fixture fields; no native window is created. LocalPlayer's actual item-use flag false makes actual Player.isScoping short-circuit. Entity owns all six angle getter/setter/turn methods on the unmodified LocalPlayer receiver.

For every event, an observed LocalPlayer/Tutorial pair delegates to actual production methods and is compared against separate unmodified receivers, including exact raw fields and warning logs. Unrelated fields use raw primitive comparisons/reference identity rather than accidentally invoking gameplay `Entity.equals`. The corpus contains 1,408 fixtures and 4,651 events per receiver: 3,810 production calls and 841 explicitly labeled focus/capture/drain field mutations. There are 1,958 actual private turns, zero exceptions, and 491 logged steps. Two fresh Java 25.0.1 processes reproduce identical observations.

The corpus covers handle/focus/capture/first-move combinations, both inversion axes, signed zeros, subnormal/midpoint/overflow boundaries, sensitivity endpoints and neighboring doubles, random finite sequences, 64 captured two-move pipelines and 32 uncaptured diagnostics. It includes actual `setIgnoreFirstMove` calls. Explicit drains are fixture field mutations and never claim full handler-wrapper execution.

An independent Fraction oracle matches 1,811 admitted actual onMove transitions and 1,950 admitted private-turn scaled arguments with integer rational RN-even after every operation. Eight nonfinite moves and eight downstream states remain outside admission. Native verification separately compares actual method projections, captured relative convenience, explicit wrapper gate/reset policy, carried two-move pipelines, and rejection/recovery cases. Actual source and full harness pass the independent kernel, including nine stated laws. All 7,164 native cases pass, including 64 state-carrying captured two-move→finish pipelines, 32 separately labeled uncaptured wrapper-policy pairs, 118 admission cases, 110 successful same-process rejection followups, and five malformed packet cases. Exact commands, hashes and phase timings are recorded in `evidence/mouse-input-*.json`; these checks establish the stated laws and recorded fixtures rather than a universal MouseHandler/IEEE equivalence theorem.

Reproduce:

```sh
python3 tools/reference_mouse_input_probe.py selftest
python3 tools/test_mouse_input.py --oracle-only
python3 tools/test_mouse_input.py
```

`--skip-build` requires a prior verified immutable artifact and revalidates every recorded dependency. No client/window construction, SDL timer call, real input, foreground operation, capture/release operation, or complete visible mouse/client acceptance is claimed. Confidence is high within the executed neutral method projection and the separately identified wrapper policy.
