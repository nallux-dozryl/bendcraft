# Resource-backed continuous Player client verification

`resource_player_client.bend` is a finite integration instrument. It connects the
existing owned PlayerRuntime, leased PlayerSession and continuous presenter to
`WorldVisibility.Sample`, `ResourceFrame.Assets` and `WorldResourceFrame.draw`.
The root owns both the entry and `src/resource_player_scene.bend`; this runner
uses them unchanged. The scene retains the exact measured plain `Player.aiStep`
test profile `.1d` speed, `.08d` gravity and `.42d` jump strength. It is not a
normal `LocalPlayer` receiver.

The entry requires `--verification-fixture`. It loads the official 26.3 registry,
verified sine table and custom Core/PlayerRecord bundle. Pristine Core admission
creates the existing 39-block scene through 47 mutations; saved terrain, pending
edits, body, metadata, support, raw look and pause are retained. By default a
loaded pause is preserved. `--unpaused` explicitly clears it. Restore clears
physical keys and mouse state; hidden tests supply no held OS input.

The renderer resolves the actual registry's air, stone, dirt and oak-planks
bindings, loads the three official root models and their cube parent chain, and
owns three static textures. Visibility samples the source-defined finite region
and neighboring blocks. This domain uses zero model transforms, normalized
static UVs, Solid layers and white tint/light. General blockstate selection,
lighting/AO, biome tint, animated textures, an atlas and GPU rendering are outside
this instrument.

`tools/test_resource_player_client.py` defaults to preparation. It seals the
complete discovered Bend/native-effect source closure, test helper closure,
compiler, original resources, selected model/PNG bytes, retained desktop observer
and actual immutable MCP artifact. It runs ordinary checks of the entry and
scene and obtains fresh independent actual Java idle-step/restart observations.
Every Java fixture executes twice in fresh processes. The official plain
`Player.aiStep` runs with declared fixture services; fixture block writes precede
each Java tick. Expected Core and bundle bytes use independent NBT encoding;
raw angle projection uses the existing exact rational F32 oracle.

```sh
python3 tools/test_resource_player_client.py --prepare
python3 tools/test_resource_player_client.py --audit
```

Preparation creates only ignored fixture/reference/report files and compact
tracked preflight evidence. It does not emit C, compile a native artifact or
observer, launch any client, activate an application, take screenshots, post
input or request permissions. Its preliminary compiler context includes the
actual compiler driver/configuration/environment. SDK header/module/framework
and selected link inputs cannot be sealed completely before emitted C exists;
the guarded platform cache resolves and verifies that closure during the
explicitly granted native lane.

The single planned build command is:

```sh
python3 tools/platform_cache.py build resource_player_client.bend -o build/resource-player-client/client --report build/resource-player-client/build.full.json
```

The runner invokes this command in a process group with a 600-second limit,
records termination if it fails or times out, and makes no second entry build.
An already completed full receipt can be adopted instead. The native lane
requires the lead's later explicit build/launch slot:

```sh
python3 tools/test_resource_player_client.py --native --lead-slot-granted
# Or reuse a completed receipt, preserving all execution and receipt checks:
python3 tools/test_resource_player_client.py --native --lead-slot-granted --build-report build/resource-player-client/build.full.json
```

A native run adopts only the verified immutable guarded macOS CPU Window artifact.
It validates dependency lookup identities, sizes and hashes, original C, the
unchanged guarded transform, transformed C, immutable executable and convenience
output before and after execution. Input-generation retries are rejected for
this sealed observation. The runner reuses the frozen actual MCP binary and
copies the previously verified read-only desktop observer byte for byte. It
never builds a replacement MCP bridge or synthetic client driver.

The bounded hidden scenarios are:

- Paused 128×128 CPU presenter execution, actual palette/resource loading,
  exact 18-operation TCP/MCP discovery, developer authentication and observer
  capability refusals. Four paused clock/Record queries cannot advance time.
- Two explicit idle ticks match independently observed actual Java Records.
  Six queued floor edits survive an exact durable save/restart. Each resumed
  deadline is stepped separately: tick 4/revision 50 has 36 visible blocks and
  216 neighbor reads; tick 5/revision 53 has 39 blocks and 234 reads. Both Core
  headers and whole PlayerRecords must match independent expectations before
  exact bundle comparison. Saved peer highwater survives reload.
- A separately loaded nonzero current/past raw degree look retains its exact
  Record and durable bytes; frame descriptions report independently rounded
  F32 radian words. Default pause stays intact.
- `--unpaused` uses the real 50 ms actor timer. Seven bounded clock samples must
  advance monotonically without `simulation.step`, edits or held inputs.
  Unsaved timer/render/close activity cannot overwrite the durable bundle.
- A live lease contender, unknown argv, missing sine/jar, invalid ZIP, a valid
  ZIP containing a deliberately invalid dirt PNG, and a corrupt custom bundle
  refuse without replacing saved bytes. The bad PNG fixture preserves all
  other selected official bytes and has independently valid ZIP integrity.
- An API edit installs the actual official water state, outside the renderer's
  four-state domain. The next real frame query must fail and close the client.
  A zero-frame restart then proves bounded lease/listener recovery and unchanged
  durable bytes. `--frames 0` loads assets and completes startup/cleanup while
  producing no frame description.

Every launch uses explicit `BEND_MINECRAFT_LAUNCH_MODE=hidden`, two Bend workers and
`--gpu off`. The read-only AppKit observer samples frontmost PID every 20 ms and
records activation/Spaces notifications. Every accepted run must preserve its
sampled frontmost application, report no child activation or Spaces change, exit
within 60 seconds and leave no listener. These are observations of the bounded
runs, not a proof of all transient desktop behavior. Source-defined failure
cleanup closes assets, stops the server and releases the lease; the suite checks
observable exit, recovery and durable state, not deep owner serialization or a
heap/FD leak theorem.

`client.frame` is described before drawing. Metadata and a successful frame-loop
exit do not establish independent pixels or drawable presentation. This entry
has no dump/readback option. The separate frozen
`evidence/world-resource-frame-native.json` provides 97 bounded native cases,
49 frames/43,536 independently checked CPU pixels, selected quads/texels and
failure/recovery evidence for its own domain. The entry suite audits that receipt
and generation; it does not count those pixels as new presenter readback. The
whole imported WRF kernel check timed out and remains unverified; declared
foreign/unsafe boundaries are not a whole-client proof.

Preparation status is recorded in
`evidence/resource-player-client-preflight.json`; successful granted execution
will produce `evidence/resource-player-client-native.json`. Full source/compiler/
SDK manifests, reference fixtures, ordinary logs and child output remain ignored
under `build/resource-player-client/`. Native execution is not started by the
preparation checkpoint. Focused keyboard/mouse delivery, capture/release,
first-move discard, visible presentation, UI, inventory and audio require the
separate coordinated visible lane. No hidden receipt establishes full Minecraft
26.3 parity or gameplay speed.
