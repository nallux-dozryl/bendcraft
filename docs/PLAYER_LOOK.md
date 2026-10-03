# Neutral player look angles

`src/player_look.bend` implements the angle-field projection of the pinned Minecraft Java 26.3 `Entity.turn(double,double)` operation. `State` owns four binary32 fields in degrees:

```text
State{yaw, pitch, previous_yaw, previous_pitch}
turn(State, dx:F64, dy:F64) -> Result<Error,State>
```

`dx` and `dy` are the double arguments already supplied to `Entity.turn`; they are not raw cursor displacement with sensitivity applied. The current and previous yaw and pitch are explicit because preserving only current fields would lose actual update semantics. The caller owns any later conversion to renderer radians.

## Measured operation

The installed 26.3 Entity method narrows each double argument to float **before** multiplying by `0.15f` (`0x3e19999a`). Its setters and old-field updates have different behavior:

1. Add the scaled pitch delta to current pitch with binary32 RN-even addition. `setXRot` rejects a nonfinite candidate, retaining the current field. Otherwise it computes float remainder by 360 and clamps the remainder to [-90,90].
2. Add the scaled yaw delta to current yaw. `setYRot` rejects a nonfinite candidate; otherwise it stores it without remainder.
3. Clamp current pitch and call its setter again.
4. Add the pitch and yaw deltas directly to previous pitch and previous yaw. Clamp previous pitch to [-90,90] **without remainder**.

For example, pitch 80 and dy 2000 produce current pitch 20 and previous pitch 90 when previous pitch was also 80. An initial current pitch 365 with zero delta becomes 5; previous pitch 365 becomes 90. This also explains why the input domain admits every finite pitch rather than rejecting initial values outside the clamp interval.

A finite `Double.MAX_VALUE` dx narrows to positive float infinity. Java logs setter rejection and retains current yaw, but directly adding it to previous yaw produces infinity. Huge dy can retain current pitch while clamping previous pitch to 90. The reference records these actual warnings and raw outcomes; the checked Bend API admits only a finite resulting state.

## Checked admission and ownership

All four initial state fields and both F64 inputs must be finite. Signed zeros, finite subnormals, and all finite magnitudes are admitted. Validation uses this deterministic order:

- `InvalidState{field}`: yaw 0, pitch 1, previous yaw 2, previous pitch 3.
- `InvalidInput{axis}`: dx 0, dy 1.
- `NonFiniteResult{field}`: the same four state indices after computing the actual raw field projection.

`turn` publishes a `Done` state only when all final fields are finite. `State` and `Error` are Data, so a caller may retain and reuse its valid prior state after `Fail`; failure does not return a partially updated state. This is an explicit simulation admission policy, not a claim that Java itself rejects all such turns. `turn_raw` is an unchecked diagnostic helper for tests; production callers use `turn`.

Binary32 addition and multiplication use the existing checked F64 integer-word implementation and one RN-even narrowing. A product of two F32 significands fits within 48 bits. Relevant binary32 addition midpoint cases also fit binary64 precision; a much smaller discarded addend cannot cross a binary32 rounding boundary. Float remainder by 360 uses finite bounded integer modular arithmetic, at most 104 doubling steps and a fractional divisor at most `360 << 15`. No simulation step calls host float arithmetic, a Foreign function, or an unsafe definition.

## Reference and verification

`tools/reference_player_look_probe.py` invokes the actual pinned `Entity.turn` and inherited getters/setters on a constructor-skipped concrete `ArmorStand` with a null vehicle. An observed subclass delegates every getter/setter to the production superclass and records exact arguments, return values, before/after states, and warning order. Every step is compared to an unmodified ArmorStand. All 135 unrelated inherited instance fields are checked unchanged. Actual release `SharedConstants.IS_RUNNING_IN_IDE` is false, preventing the setter warning path from entering an IDE pause hook.

The frozen corpus has 3,246 fixtures, 3,606 steps per receiver, and 7,212 production turn calls. Two fresh Java 25.0.1 processes reproduced identical observations. There were no exceptions; 1,077 steps emitted setter warnings. The corpus covers double-to-float midpoints, underflow/overflow, signed zeros, clamp/remainder transitions, current/previous independent overflow, 708 pitch exponent cases, raw random finite states/deltas, and 24 chains of 16 turns. Eight nonfinite-input observations remain outside Bend admission.

An independent Python Fraction oracle matches all 3,598 admitted production steps using integer/rational RN-even cast, multiply, add, exact truncating remainder, and clamp. It does not use host floating arithmetic to decide expected results. The native harness passes raw U32 words into actual Bend definitions. All 3,606 production comparisons pass: 2,922 Done states, 676 NonFiniteResult failures, and 8 InvalidInput rejections. Both actual source and full harness pass the independent kernel; all eight laws pass. All 24 chains carry the Bend returned state into the next call, totaling 384 turns. Thirty-nine admission cases, their successful same-process recovery calls, and five malformed harness argument cases pass.

Reproduce:

```sh
python3 tools/reference_player_look_probe.py selftest
python3 tools/test_player_look.py --oracle-only
python3 tools/test_player_look.py
```

`--skip-build` requires the prior content-checked immutable artifact and revalidates its entire recorded dependency closure. Ordinary checker results, independent full-import kernel results, native artifact fingerprints, counts, and commands are recorded separately in `evidence/player-look-*.json`. The laws concern raw-bit conversion, signed zero, concrete complete turns including the 365-degree pitch case, validation, and owner retention. They do not constitute a universal Entity or IEEE arithmetic equivalence theorem.

## Boundary

The returned field projection is for the neutral no-vehicle path. It does not implement warning emission, rider `onPassengerTurned` callbacks, client interpolation/rendering, or entity constructor/level behavior. Production warnings are retained only by the Java reference; calling Bend `turn` has no logging side effect.

Pinned MouseHandler has no isolated static neutral scaling helper. Its actual private `turnPlayer` path reads client options, player, tutorial, smooth filters, camera and scoping state. Only its bytecode wiring was inspected here. Default sensitivity scaling, MouseHandler behavior, SDL capture, and full mouse/client fidelity are not claimed or implemented by this module.

Confidence is high for the recorded pinned neutral field projection and its explicit finite-state policy; broader client/look behavior remains outside this evidence.

## Additional MouseHandler bytecode analysis

`evidence/player-look-mouse-bytecode.json` records a bounded analysis of actual pinned class bytes, separate from the executed Entity reference. SDL motion coordinates and relative displacements are F32, widened exactly to F64 before `MouseHandler.onMove`. Captured, focused input accumulates relative displacements with F64 addition. Wrong or zero window handles return; the first move records position and discards its delta. Uncaptured input instead accumulates double coordinate differences.

Options constructor defaults before loading saved settings are sensitivity Double 0.5, both invert flags false, smooth camera false, and FIRST_PERSON camera. Neutral `turnPlayer` computes, in this F64 order:

```text
a = sensitivity * 0.6000000238418579d
a = a + 0.20000000298023224d
cube = (a * a) * a
scale = cube * 8.0d
dx = accumulatedDX * scale
dy = accumulatedDY * scale
```

The coefficients are the exact binary64 promotions of 0.6f and 0.2f. The derived default scale is `0x3ff000001800000c` (1.0000000894069698), so replacing it by exactly 1 changes raw results. Tutorial sees these deltas before optional `dneg` inversion. The subsequent Entity method then narrows to F32 and multiplies by 0.15f.

Smooth camera uses persistent filter state and elapsed time; first-person scoping uses the cube without the factor eight. `handleAccumulatedMovement` gates turning on focused/captured/non-null-player state and clears accumulations even when inactive. The inspected movement methods have no pause predicate; the per-frame call precedes the frame's pause-state update. These are bytecode findings, not an executed MouseHandler fidelity claim.

A viable later no-window fixture can constructor-skip Minecraft, Options and LocalPlayer; construct real OptionInstances, MouseHandler and an inactive Tutorial; set current/past rotations, a null vehicle, and the LocalPlayer item-use flag false. The actual `Player.isScoping` then short-circuits, and invoking the private `turnPlayer` need not call a window or SDL timer. `onMove` can separately use a constructor-skipped Window whose handle/focused getters only read fields. This fixture's viability remains to be executed and validated. The existing Look source and its tests are unchanged by this analysis.
