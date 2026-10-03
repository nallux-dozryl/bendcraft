# Neutral camera rotation tick phases

`src/player_rotation_tick.bend` implements an owned camera/count projection of two observed Minecraft Java **26.3** tick phases. It leaves the existing `Player.aiStep` runtime unchanged. Angles use raw binary32 **degrees**, as in `player_look.bend`; the world's rendering angles remain a separate radians representation.

```bend
type State is Type:
  State{look: PlayerLook.State, tick_count: U32}

set_old_rot(state) -> State & Result<Error, Unit>
common_tick(state) -> State & Result<Error, Unit>
normalize(fuel: Nat, state) -> State & Result<Error, Unit>
```

The actual result type is `Result<&2,&2,Error,Unit>`. Every operation consumes and returns the sole `State` owner. `set_old_rot` copies current yaw/pitch to their previous fields, preserving the count. `common_tick` does the same camera snapshot and adds one to the count modulo 2³². This unsigned word stores Java's signed `int` bits. Actual receiver observations include transitions through `2147483647`, `2147483648`, and `4294967295`, including wrap to zero.

`normalize` receives camera fields **after** `aiStep`. It executes the previous-yaw negative loop, previous-yaw positive loop, previous-pitch negative loop, and previous-pitch positive loop, in that order. Each comparison uses binary32 `current - previous`. The negative loop runs while the difference is strictly below −180; the positive loop runs while it is greater than or equal to +180. Each update performs a binary32 subtraction or addition of 360. Current fields and the counter are preserved. A modulo shortcut would change rounding and is not used. Existing `PlayerLook.add` supplies word-based exact F32 arithmetic through `f64.bend`; no host floating-point game implementation, foreign decoding, unsafe recursion, or axioms are added.

Java `LivingEntity.tick` also checks body/head angles between and after these camera checks. This module has no body/head state. `Entity.commonTick` also snapshots position, decrements invulnerability, and invokes client interpolation. Full `LocalPlayer.tick` executes many other lifecycle paths. The API implements their **camera/count projection**, without claiming a complete tick implementation or changing runtime/session consumers.

## All finite fields; explicitly bounded work

**Every finite F32 word is admitted in all four fields**, including huge yaw histories, signed zeros, subnormals, and synthetic current pitches beyond normal setter limits. There is no angle-magnitude restriction. Java fixtures seed raw fields only after ordinary constructors; this separates numerical projection coverage from physically reachable player configurations.

Finite subtraction can overflow to positive or negative infinity. These comparison results retain actual Java F32 ordering and are not rejected as invalid stored state. NaN/infinity input fields are rejected before any operation. Adding/subtracting 360 may round back to the same huge previous word: the loop still spends fuel and eventually returns `FuelExhausted`. No progress assumption or angle cap replaces the measured arithmetic. Huge equal current/previous angles require no updates and succeed with zero fuel.

`normalize` accepts at most **16,384 shared fuel units**, spending one per actual previous-angle update across both axes. Zero fuel succeeds when no update is needed. Larger fuel values are rejected before recursion. All loop recursion follows decreasing `Nat` fuel.

| Error | Meaning |
|---|---|
| `InvalidState{field}` | Nonfinite input field |
| `FuelLimit{}` | Requested fuel exceeds 16,384 |
| `FuelExhausted{axis}` | An angle update remains, with no shared fuel |

Fields are yaw=0, pitch=1, previous yaw=2, previous pitch=3; axes are yaw=0 and pitch=1. Validation visits fields in that order. State errors precede fuel-limit errors. **Every failure returns the entire original state**, including when yaw completes before pitch runs out of fuel. No partial previous angle or count becomes visible. The native harness consumes the returned owner again after failure, checking recovery and subsequent admission.

## Actual reference boundary

`tools/reference_player_rotation_tick_probe.py` derives the fixture from the frozen, normally constructed LocalPlayer service boundary in `reference_local_input_probe.py`. Four external class names are supplied from declared source: `Minecraft`, `Gui`, `Tutorial`, and `ClientPacketListener`. Official `Entity`, `LivingEntity`, `Player`, `AbstractClientPlayer`, `LocalPlayer`, `ClientLevel`, and `Options` load from unchanged, hash-pinned 26.3 jar bytes. No unsafe allocation, skipped gameplay constructor, gameplay receiver replacement, UI, or foreground window is used.

The fixture uses an actual `ClientLevel` subclass with a finite real stone floor, real air elsewhere, and real block/fluid/collision lookups. A LocalPlayer subclass records camera fields before and after `aiStep` while calling `super.aiStep`; its final camera/count observations must match the ordinary unobserved receiver. These service substitutions and the finite neutral world are explicit observation limits, not whole-client parity.

The **229 fixtures** run on both receivers (**458 observations**): eleven `setOldRot`, seventeen `commonTick`, six neutral `aiStep` baselines, 140 original actual `LocalPlayer.tick`, sixteen common-then-tick, sixteen actual `ClientLevel.tickNonPassenger`, eight new huge-equal actual ticks, and fifteen standalone Java F32 arithmetic diagnostics. Fresh extraction and an independent JVM repeat produced identical canonical observations, fixture values, and the 4,379-class loaded official tree. Six deliberate integrity mutations target client, Java runtime, library, official class, launcher source, and fixture output; all are rejected.

The **original 196 fixture inputs and outputs remain byte-identical**. New snapshots include maximum finite words and huge unequal current/previous values; snapshots are safe because they contain no angle loops. New huge full-tick calls require bit-identical current/previous fields, with body/head seeded consistently, and observe unchanged camera angles. Python rejects huge unequal full-tick inputs before launch; the Java huge-equal branch also checks equality before ticking. **The probe never invokes an unequal huge full tick**, which could stall in real Java. Each JVM process has a 120-second process-group watchdog.

The fifteen numeric diagnostics invoke Java F32 operators on the actual receiver's raw finite fields. They record subtraction overflow to ±infinity, unchanged ±360 updates, binade/rounding transitions, and one-step comparison results. They do **not** execute production Minecraft normalization. Native numeric comparisons and fuel-policy tests are labeled separately from actual tick observations. No host loop computes game expected values.

`reference/player_rotation_tick.json` retains every checked camera/count value, phase input, and numeric observation. Compact evidence retains source/runtime/library/class hashes, counts, commands, timing, and canonical observation hashes. Complete raw observations, loaded class maps, generated sources, launcher, stdout and stderr stay in ignored `build/player-rotation-tick-reference/*.full.json`, linked by file hashes. Extract/repeat raw file hashes can differ because serialized stdout order differs; their canonical observation/class-tree hashes must agree.

## Verification and generations

The all-finite source and **eleven-law** harness pass ordinary typing and full imported independent-kernel verdicts. The native corpus passed **594 checks twice**: actual camera phases, neutral aiStep identity baselines, huge equal-angle zero fuel, overflow/numerical steps, maximum-fuel no-progress exhaustion, exact/shared fuel, rollback, nonfinite rejection, and owner reuse. Current native binary SHA-256 is `43db2f166dd09342934499ea98416fdcf097a180af097b68de9051540f71c4da`. The two comparison runs took 0.510 and 0.094 seconds. Full imported source and eleven-law harness kernel verdicts passed in 0.337 and 0.535 seconds, within the separate 60-second watchdogs. These current-generation results are recorded separately in `evidence/player-rotation-tick-native.json` and `evidence/player-rotation-tick-kernel.json`; ordinary typing was checked independently.

The eleven laws establish direct snapshot copying, rejection retention, excessive-fuel gate retention, no fuel spent for unnecessary updates, zero-fuel rejection for required updates, a counter-wrap fixture, absence of a finite-field angle gate, and rollback of a completed yaw when pitch fails. They do not prove all normalization outputs or complete Minecraft lifecycle parity. Independent native/reference observations supply finite-case behavioral evidence.

The preceding angle-capped generation is preserved separately by `evidence/player-rotation-tick-bounded-generation.json` and byte-identical `*-bounded-*` receipts. Its generation key is `f07ceed1deac3a81c1ca1966993c95a94dc4f882c3ee9df113225b68ef5649be`; its 540 checks passed twice and its original eight laws passed full kernel verdicts. Seventeen original source/harness/tool/document/reference/raw/build/evidence files are frozen under ignored `build/player-rotation-tick-frozen/<generation>/`. The manifest maps original receipt paths to those exact historical copies; its immutable native cache artifact remains unchanged and is also copied under the frozen snapshot’s `native/` directory so cache pruning cannot remove the historical executable. Those results describe the **historical capped generation**, not the broadened source.

The unchanged content-checked ordinary native cache records and verifies all transitive dependencies and immutable executable bytes before/after comparisons. Full build and execution receipts remain under ignored `build/`; checked evidence records their hashes, canonical dependency hash/count, generation key, compiler metadata, timings, and project pins. `--compact-existing` validates/formats an existing execution without a new Java/native run, distinguishing its original runner from the report formatter. Heavy jobs require the lead's shared-machine slot.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_rotation_tick_probe.py --feasibility
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_rotation_tick_probe.py --extract
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_rotation_tick_probe.py --rerun
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_rotation_tick_probe.py --selftest
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_rotation_tick.py --prepare
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_rotation_tick.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_rotation_tick.py --kernel
```

The native build child has a 600-second process-group watchdog. Full imported source and harness kernel attempts run sequentially with a 60-second bound each. `--skip-build` compares an existing immutable artifact only after every recorded dependency/artifact digest is checked; it cannot reuse the old bounded artifact after source changes. No runtime/session consumer integration is claimed here.
