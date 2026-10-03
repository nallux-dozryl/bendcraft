# Owned plain Player runtime verification

`src/player_runtime.bend` owns one `client_world.State`, sine tables, Player
metadata, the supporting-block history, and the complete physical controller.
The world view is the sole movement body authority. This facade samples held
buttons before each admitted neutral **plain `Player.aiStep`** projection. The
actual `LocalPlayer` override, slowdown and sprint state machine, real OS input
capture, and full Player/ServerPlayer ticks are separate capabilities.

The standalone `tests/player_runtime.bend` imports production modules only. Its
normal callbacks call `SupportWorld.sample_checked` before movement and
`SupportWorld.update_checked` after the returned transition, including zero
displacement and rejected position application. The fixture uses the frozen
39-block `client_world.fixture`: floor x/z -3..2 at y0, dirt at x2 and (1,1,1),
and planks at (2,1,2)/(2,2,2). Eight sections cover -16..15; setup has Core tick1
and revision47. Attributes are the declared neutral test settings: speed .1,
gravity .08, friction/drag modifiers1, jump strength .42, and explicitly supplied
step height. Java observations verify admitted block friction .6f and jump
factor1f. These values are fixture inputs, not a general attribute resolver.

`step(driver,state)` advances Core first and then physics. `advance(~driver,n,state)`
repeats that ordering for each tick. Rejected physics retains the Core clock and
due edits and restores body, complete view/cache, metadata, support and controls.
`realtime_step` retains the complete state when paused. Snapshot and query may
populate the declared read cache; neither advances simulation time.

`input(state,bindings,packet)` publishes the complete accepted controller and
rounded renderer projection atomically. Degree look fields are authoritative;
the renderer uses binary32 multiplication by radians factor `0x3c8efa35`.
Rejected packet folds or renderer projections retain the previous controller,
view, Core and error field. `release` clears held buttons and accumulated mouse
deltas while preserving mouse position/options/look and rearming first discard.

`record(state)` returns the state and custom `player_record.Record` save
projection. `restore(state,record)` validates its motion/degree/radian agreement
and admits only overworld records in this facade. Failure preserves the complete
state. Success installs body, metadata, support and raw look, clears physical
buttons and initializes the mouse, preserves options/tables/Core/region/palette/
cache, and clears the last error. The custom record does not restore the world
or claim Minecraft's vanilla player save format.

The Python runner obtains fresh actual 26.3 `Player.aiStep` and support results
using the existing pinned Java fixture adapters. Only fixture block storage is
changed between calls to represent due edits; actual movement/support/game
methods execute unchanged. Fresh actual `KeyboardInput.tick` outputs supply the
raw movement samples for every seven-button mask. Fraction-based binary32/64
rounding supplies independent packet/look/projection expectations. Independent
NBT readers/encoders compare whole Core snapshots and exact player-record bytes.
Python does not implement gameplay.

Reproduce preparation without a native build:

```sh
python3 tools/test_player_runtime.py --prepare
```

After obtaining the lead's heavy build slot, run:

```sh
python3 tools/test_player_runtime.py
python3 tools/test_player_runtime.py --skip-build
```

Native reuse requires the immutable executable digest, exact transitive source
generation, compiler identity, sine table and independent reference provenance.
It also checks every dependency lookup still resolves to the recorded file and
rehashes its content, including Base, native effects, runtime, compiler, SDK and
link inputs. The keyed manifest and retained C must agree with the receipt. The
compilation cache preserves ordinary checks; the test runner attempts the whole
production Runtime BendTT verdict with a 600-second process-group bound. Java
parity and rollback are separate native observations; a timeout adopts no
mathematical verdict. A failed bounded attempt can be resumed for native checks
only with its exact compiler/source-generation receipt, retaining the explicit
unverified kernel status.

The bounded lanes cover held-forward/release, held-jump, diagonal/opposing keys,
dirt-step and blocked movement, signed counters, scheduled floor/collision edits,
bulk versus individual ticks, paused render/query, packet fold and projection
rollback, rejected context/preparation/support with same-owner recovery, exact
record projection, rejected restore and successful ephemeral-state clearing.
The `advance` harness operation uses a closed default driver at .6f step height;
individual `step` operations accept the fixture's explicit height or failure
phase. Runtime fields and Core snapshots are retained between operations inside
the actual Bend binary.

Preparation writes compact `evidence/player-runtime-reference.json`; complete
Java observations and native stdout remain under ignored `build/player-runtime`.
Native acceptance is recorded separately in
`evidence/player-runtime-verification.json`. Preparation alone does not establish
native integration success, LocalPlayer parity, capture, visible presentation,
or gameplay performance.

The current frozen native lane passed 73 exact actual-Java Player state and
support-cache comparisons across eight sequences, plus two bulk/individual tick
comparisons. Seventeen actual executable launches carried 244 harness operations.
The supplemental lanes passed six exact packet expectations, packet fold and
renderer-projection rollback, paused whole-state retention and read-only clock
checks, three rejected-physics phases with retained due edits and same-owner
recovery, and record restore/rejection checks. Restore uses distinct nonzero
current and previous raw degree fields, changed physical state and custom options;
the independent NBT oracle compares exact record bytes throughout.

Native compilation produced the verified 3,464,696-byte executable with 1,663
content-keyed dependencies: its miss took 68.246 seconds including 15.774 seconds
of C emission and 46.583 seconds in the native CLI phase. These are build phase
observations on this host, not gameplay performance measurements. The whole
Runtime `--verdict` process reached the 600.083-second bound in Bend without
stdout, stderr or a kernel verdict. It was terminated and remains **kernel
unverified** in `evidence/player-runtime-kernel-attempt.json`; no broader compiler
or kernel defect is inferred. The existing source laws state paused-selection
identity and metadata roundtrip, not Minecraft parity.

Reproduce the native lane using that recorded bounded attempt without repeating
the export or compiling again:

```sh
python3 tools/test_player_runtime.py --skip-build \
  --resume-kernel-attempt evidence/player-runtime-kernel-attempt.json
```

This command rechecks ordinary source/harness typing and termination, the full
immutable native receipt and reference hashes, and executes every native lane.
It preserves `runtime_kernel_verified=false` and does not convert the attempted
kernel check into a successful proof claim.
