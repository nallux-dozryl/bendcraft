# Continuous player client verification

`player_client.bend` is a finite integration instrument connecting the owned
PlayerRuntime and leased PlayerSession to the existing presenter and cube renderer.
It requires `--verification-fixture`. It runs plain `Player.aiStep` with the exact
observed neutral test attributes `.1d` movement speed, `.08d` gravity and `.42d`
jump strength. It does not implement the normal `LocalPlayer` receiver.

The entry loads the pinned 26.3 assets, verified sine table, official block
registry and custom `bendex:player-record` bundle. A pristine Core receives the
39-block test scene through 47 Core mutations. A loaded nonpristine Core retains
terrain, body, metadata, support, raw look, pending edits and pause. By default the
loaded pause is preserved; `--unpaused` explicitly clears it. Restoring a session
clears ephemeral keys and mouse state. Hidden runs provide no held OS input.

`tools/test_player_client.py` defaults to preparation. Its `--prepare` lane never
emits C, builds an executable, compiles the desktop observer or launches a Window.
It hashes the complete discovered Bend/native-effect closure, compiler, test
helpers, jar, registry and sine table; obtains fresh actual Java idle-step and
restart expectations; and performs ordinary checks of the entry and scene.
Each Java fixture runs twice in fresh processes. The official `Player.aiStep`,
movement and support methods execute unchanged under declared neutral fixture
services. Per-tick fixture block writes precede each actual Java step.

```sh
python3 tools/test_player_client.py --prepare
```

The `--native` lane requires a lead-granted build/launch slot. It delegates to the
guarded CPU Window platform cache with a 600-second process-group build limit,
or accepts an already completed full receipt through `--build-report`. It adopts
the verified immutable artifact, never an ordinary untransformed executable.
It verifies the keyed dependency manifest, lookup-to-real-path identities, sizes,
file hashes, original C, guarded transformed C, convenience output and immutable
binary before and after execution. It reuses the independently verified immutable
MCP bridge from the frozen PlayerSession receipt.

```sh
python3 tools/test_player_client.py --native
# Existing completed guarded receipt, with the same audit and execution:
python3 tools/test_player_client.py --native --build-report build/player-client/build.full.json
```

Native checks use the normal entry without a synthetic replacement driver:

- Successful bounded hidden CPU frame-loop execution with 128×128 logical images
  in the source-defined 512×512 native Window.
- Actual external TCP and stdio MCP discovery, authentication, capability
  refusals and strict step arguments. The 18 advertised operations must agree
  across transports and exclude synthetic harness operations.
- Paused render/query observations retain the clock and exact initial PlayerRecord.
  Two explicit idle steps match independently observed raw Java words.
- Six queued collider removals/restorations have distinct deadlines, survive a
  durable save/restart and apply before each individual resumed physics step.
  PlayerRecord matches fresh actual Java; complete Core and custom bundle bytes
  match independent NBT encoding. Saved peer highwater survives restart.
- A separately loaded Record with nonzero current and past raw degree angles
  retains exact bytes on save; frame descriptions report the independently
  computed finite-F32 radian projections. Default pause and Core are preserved.
- A live lease contender refuses startup without changing the valid bundle.
  Render, close and unsaved timer advancement do not replace durable bytes.
- `--unpaused` clears a saved pause; bounded clock samples observe monotone
  timer advancement. The measured cadence does not establish gameplay speed.
- `--frames 0` completes the normal startup and cleanup path without a frame.
  Invalid arguments, missing or invalid assets/table, missing bundle/registry,
  corrupt/Core-only saves and invalid
  Window modes refuse at their expected startup boundaries. A subsequent hidden
  launch reuses the lease and preserves saved bytes.

A read-only AppKit observer samples the frontmost PID every 20 ms and records
application-activation and Spaces notifications. It passes only hidden or guarded
invalid launch modes, writes child output directly to files, and bounds each
child to 60 seconds. Every accepted run must retain the same frontmost application,
observe no Spaces change or child activation, exit normally and leave no listener.
This is an observation during these runs, not a proof about all transient desktop
behavior.

`client.frame` is printed before drawing. Exact log counts plus successful bounded
exit establish execution of the source-defined frame loop, not independent pixel
fidelity or drawable presentation. This entry has no image dump/readback option.
Focused OS keys, mouse capture/release, visible presentation, representative UI,
inventory and audio remain separate coordinated acceptance work under
`docs/VISUAL_ACCEPTANCE.md`. No hidden run substitutes for that evidence.

Compact tracked receipts are `evidence/player-client-preflight.json` and, after a
successful granted run, `evidence/player-client-native.json`. Full build manifests,
Java inputs/outputs, ordinary-check logs and child output stay under ignored
`build/player-client/`. Preparation is not native verification. Foreign IO and
lifetime loops retain their declared proof boundaries; no whole-client kernel or
full Minecraft parity claim follows from this instrument.

The recorded native run passed 22 bounded entry launches: 20 used the hidden
environment, and two invalid-mode values were refused before Window creation.
Five hidden launches succeeded, including the zero-frame recovery. The successful
loops described 850 frames. The suite matched four controlled idle steps to actual
Java, applied six queued collider edits, compared three exact durable bundles and
observed 17 startup/lease refusals. All 22 desktop observations retained frontmost
PID 50401 and recorded no activation or Spaces notifications.

The single guarded cache miss took 118.889 seconds: 51.779 seconds for C emission
and 58.913 seconds for Objective-C Clang, with dependency discovery and validation
included in the total. The receipt pins 3,678 dependencies and the immutable
5,526,248-byte executable. The unpaused lane observed 17 ticks over 0.825 seconds;
this bounded observation does not establish Minecraft performance.

Two initial runner defects were preserved in ignored attempt receipts: the old
17-operation expectation omitted the new `player.inspect`, and an expected Core
construction was incorrectly assumed to contain decoder-only `max_peer` metadata.
Both corrections retained the exact protocol and durable-byte assertions. No
production source or native binary changed, and continuation reused the successful
build. The compact receipt distinguishes the executed runner hash from the later
report-only finalization hash and retains the executed runner source under `build/`.

```sh
# Only after an orchestration correction, refusing changed sources/helpers/resources:
python3 tools/test_player_client.py --refresh-preflight 'Reason for the runner correction'
# Audit and compact an already successful full receipt without building or launching:
python3 tools/test_player_client.py --compact-only
```
