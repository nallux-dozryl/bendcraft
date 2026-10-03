# Neutral player control packets

`src/player_controls.bend` composes the frozen keyboard, mouse and entity-look
modules into one pure packet operation. It owns no window, world, body, tick,
save or renderer. Angles remain four exact F32 fields in degrees. Platform
events arrive in the caller's observed order and include capture at each event;
the packet additionally carries the final focus and capture observations.

The public interface is:

```bend
type Controller is Data:
  Controller{buttons:PI.Buttons,look:PL.State,mouse:MI.State,options:MI.Options}

type Error is Data:
  MouseFailure{cause:MI.Error}
  LookFailure{cause:PL.Error}

controller_error(Controller) -> Maybe<&2,Error>
release(Controller) -> Controller
apply(Controller,PI.Bindings,CC.Packet) -> Result<&2,&2,Error,Controller>
describe_error(Error) -> String
```

`CC` is `src/client_controls.bend`. Its `PlatformEvent{event,captured}` and
`Release{}` actions form a finite list. Its `Packet{actions,focused,captured}`
is a single publication boundary. Controller fields are pure Data, so callers
retain their original owner while checking a prospective `Result`; they install
only `Done`. A failure exposes no prospective Controller or partial event batch.

`apply` first admits all initial mouse, option and look fields through the
frozen validators. Error precedence is mouse state, options, then look state;
within each family the original field order remains intact. Sensitivity must
be finite within `[0,1]`, and smoothing or scoping policies reject explicitly.
All finite degree fields are admitted, including signed zero and finite pitches
outside the usual camera range. This preserves the exact measured `Entity.turn`
setter behavior when a packet turns them.

Captured key down and key up update every matching keyboard binding. All U32
codes are admitted, including shared bindings and large values; uncaptured key
events preserve the held buttons. Captured relative `Look{dx,dy}` fields are
widened exactly from F32 to the pure F64 representation, and each goes through
`MI.relative` with active focus/capture for that event. The initial first-move
flag discards one captured relative event and becomes false; an uncaptured Look
does not consume it. Position fields retain their previous bits, because Base
Look events contain no absolute pointer position. Every Look payload is checked
for finite F32 values even when uncaptured. This last rule is this adapter's
explicit admission policy.

Mouse button, absolute Move, Scroll and Close events leave the Controller
unchanged. The caller handles their UI and lifecycle meaning and supplies an
explicit Release action where appropriate. In particular, ignored Scroll
numeric fields receive no extra floating-point admission rule here.

Release immediately clears all held buttons and accumulated mouse deltas,
sets the first-move flag true, and preserves position, view and options. The
standalone `release` function performs those field operations even if another
field is invalid; callers can always clear stuck input. In contrast, `apply`
validates the initial Controller before processing its Release actions. A
Release followed by a captured Look therefore discards that movement; a later
captured Look in the same packet can accumulate normally.

After all actions, exactly one `MI.finish` drains the accumulated deltas. Only
the packet's final `focused && captured` admits a turn; event capture alone
cannot authorize it. The active finish multiplies the accumulated F64 deltas
once by the exact frozen sensitivity expression and applies axis inversion.
The measured default scale is raw `3ff000001800000c`, rather than exactly one.
At most one `PL.turn` receives those already-scaled deltas for the entire packet.
There is no intermediate angle rounding for each Look action. The inactive
finish clears the accumulation without changing the first-move flag or view.

An active finish returns a turn even for zero accumulation. Thus an active
empty packet, or an active packet containing only Release, can invoke the
measured zero-input entity setters: finite out-of-range pitch and signed zero
may normalize. The standalone release, and `CC.release()` whose final flags are
false, preserve view bits. These are distinct API operations.

The operation rejects any failed input, accumulation, scaling or final look
admission atomically. A preceding prospective key change or first-move discard
cannot escape a later rejection. A caller which retains the prior Controller
can process the next packet normally; the test harness exercises that recovery
in the same process.

## Verification scope

The ordinary checker and independent kernel accept the actual full-import
source and harness. Kernel checks took 0.310 and 0.421 seconds respectively;
the recorded native cache miss took 9.957 seconds in total, including dependency
discovery, with 3.544 seconds recorded for native compilation. These are build
and check timings, not gameplay or arithmetic throughput measurements.

The eight stated laws cover unconditional release fields, release idempotence,
uncaptured keys, total release actions, sticky failed folds, initial admission
retaining a caller's Data owner, absence of an inactive turn, and a failed finish
publishing no Controller. They do not assert a universal IEEE arithmetic or
whole-client parity theorem.

The native test observer receives bounded numeric pipe fixtures. A Controller
uses 20 raw U32 words; bindings use seven U32 words. Fixture parsing checks
Boolean encodings, masks, canonical action padding, complete consumption and
limits before converting counts to Nat: at most 4,096 actions in a packet and
64 packets in a sequence. These are test-transport budgets. The pure production
API takes a finite list and introduces no artificial key or packet-count cap.
Mode 0 applies one packet, mode 1 calls unconditional release, and mode 2
genuinely carries accepted Controllers across a sequence while preserving the
prior Controller after failure. Reports project exact raw fields and keyboard
sample bits.

Expected keyboard and mouse/look observations come from independently executed
pinned Java 26.3 methods in the frozen reference fixtures. Relative-only retained
positions and final drain/gating are declared composition policies. The frozen
mouse reference executes actual `onMove` and `turnPlayer`; its native-frame
wrapper drain/gating remains a primary-bytecode observation. Additional packet
expectations use exact rational IEEE rounding rather than extracting results
from the Controller implementation. No native window or foreground session is
created by this work, and these packet fixtures establish no OS capture or
visible presentation claim.

All 1,141 native requests and 1,727 projected reports pass. This includes 44
exact-F32-widenable actual Java two-move pipelines, 256 actual entity-turn
projections and all 128 keyboard masks. Twenty additional mouse pairs were
excluded from this relative F32 input API because their F64 inputs cannot be
represented exactly by Base Look fields. A fresh actual MouseHandler run
confirms sensitivity raw `3fdfffffe5555567` gives exactly unit F64 scale; this
permits the 256 frozen Entity.turn raw observations to decide their composition
expectations directly. The unit-scale fixture supplements the ordinary default
scale, endpoints, signed-zero and rounding-boundary cases.

The remaining corpus includes 64 genuine eight-packet sequences, 76 carried
valid-owner rejection/recovery cases, 126 failed-request followups in the same
process, all release/capture orderings, inactive gates, shared and high U32 keys,
unsupported options and nonfinite initial/event/final fields. Fifty-four
malformed fixture requests reject with exit 2 and zero output, including small
and large count bombs, reserved padding and a later malformed packet in an
otherwise valid sequence. Valid 4,096-action and 64-packet boundaries execute.

`evidence/player-controls-reference.json` records actual oracle provenance and
the independent expected-corpus digest. `player-controls-kernel.json` records
the independent checks and law scope. `player-controls-build.json` records the
content-checked compiler/dependency receipt, immutable executable and process
bounds. `player-controls-native.json` records actual native comparisons,
malformed cases and recoveries. A final audit matches the same seven-file Bend
closure across those receipts, verifies all 1,633 recorded native dependencies,
and verifies immutable executable SHA-256
`bdefbeae3bf63660af2ce116ccb3adb9ef2e8de603250ddfe314069bddef83f1`.
Confidence is high for the recorded neutral composition and stated laws.

Reproduce from the project directory:

```sh
/Users/chuah/.bend/bin/bend src/player_controls.bend --verdict
/Users/chuah/.bend/bin/bend tests/player_controls.bend --verdict
python3 tools/test_player_controls.py --oracle-only
python3 tools/build_native.py tests/player_controls.bend -o build/player-controls-tests --bend /Users/chuah/.bend/bin/bend --report build/player-controls-build.json
python3 tools/test_player_controls.py --skip-build --binary build/player-controls-tests
```

The runner invokes no Bend compiler or kernel; build/check receipts are separate.
The recorded comparison used the digest-specific immutable artifact rather than
the convenience output path. The reference helper caches stay under ignored
`build/player-controls-reference-cache`; frozen keyboard/mouse/look reference
files and helpers are retained unchanged.
