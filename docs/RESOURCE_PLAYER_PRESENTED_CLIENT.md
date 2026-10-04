# Concrete resource player presenter

`resource_player_presented_client.bend` is a versioned integrated consumer of the
existing saved Player session, actual resource loader, checked world visibility,
model baker, CPU mesh renderer and native Window. It preserves the original
`resource_player_client.bend` and boxed entry, their sealed sources and their
separate 600-second failed emission attempts. No compiler cause was established
by those failures or by the empty compiler graph control.

The new `src/resource_player_presenter.bend` uses fixed Session/Frame/Assets types
and named continuations. It calls the unchanged boxed scene snapshot/draw APIs;
it carries the sole loaded resource owner through every draw and closes all
nested asset owners on exit. The existing actor serializes input, TCP/MCP edits,
queries and real timer ticks. Existing OS packet handling and capture/release
come from `client_presenter.frame_input` and `window_input`, without a copied
input implementation. This structure is a changed real consumer experiment;
its compile time, memory cost and runtime behavior are unmeasured until the
separately granted guarded native build and integration suite run.

The initial finite scene and neutral plain Player travel profile remain an
explicit verification instrument. This entry retains the current CLI requirement
`--verification-fixture`. Loading a saved custom bundle preserves its Player
record, Core world, pending edits and peer highwater. It adds no LocalPlayer,
terrain generation, general blockstate selection or gameplay claims. Root owns
the later normal-entry/LocalPlayer integration.

When `BEND_MINECRAFT_FRAME_DIR` is absent or empty, frame tracing is disabled.
When the caller supplies an existing directory, the presenter prints immutable
`resource.sample` DTO records before drawing, then calls `Window.frame` and
writes **its returned Image** as `<serial>.ppm`. The subsequent `resource.image`
record gives the dimensions and a CRC32 of that same Image's RGBA bytes. The
sample/image/file serials pair the actor-owned world and camera with the returned
CPU image. File-open/write failures follow the normal release/close/stop path.
The directory is a caller-supplied diagnostic destination; ZIP resource IDs are
still resolved by the unchanged resource loader and never extracted to host paths.

The independent fixture preparation uses retained, previously executed pinned
26.3 Player receivers for exact positions across idle ticks, edited floor
collisions and reload. It computes six comparison-only samples for ticks 1–5
and saved nonzero look. Their raw cells come from the independently specified
world and edits, their masks from actual Java face-pair observations, their
vertices/UVs from actual zero-transform FaceBakery output, and their texels from
Pillow decoding of the original installed PNG bytes. The existing independent
float32 triangle/ray oracle specifies the current CPU renderer's nearest/clamp,
white tint/light, directional shade and integer byte quantization. Expected
samples/quads/pixels never enter the native client's input or resource pipeline.
The 1.62f eye offset is the current explicit scene contract, not a vanilla pose
measurement.

The planned actual native scenarios retain real 18-operation TCP/MCP discovery,
authorization refusals, paused queries, four Java-compared idle ticks, six queued
floor edits, exact save with pending edits, lease refusal, reload and separate
36/39-block frames, saved raw nonzero look, and unpaused timer cadence without
`simulation.step`. The first, restart and saved-look lanes compare every returned
128×128 RGB image, sample and RGBA CRC. The timer lane disables tracing. Startup
failures include missing/bad tables, missing/bad ZIP, a complete actual parent
closure with one broken PNG, and a corrupt bundle. Runtime failures include an
unsupported visibility state and an unavailable readback directory, followed by
a frames-zero restart of the unchanged durable bundle.

Preparation/audit use the bundled Python runtime with NumPy and Pillow:

```sh
TASK_PY=/Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$TASK_PY" tools/test_resource_player_presented_client.py --prepare
PYTHONDONTWRITEBYTECODE=1 "$TASK_PY" tools/test_resource_player_presented_client.py --audit
```

Preparation runs ordinary Bend checks and lightweight guarded-build metadata
probes, with no C emission, Java receiver execution or client launch. It pins
the original failed generations, current source/effect/compiler closure,
retained Java references, original resources, pixel expectations, oracle runtime,
MCP artifact and read-only AppKit observer. Audit never regenerates these files.
A changed/missing seal or source fails explicitly.

After an explicit lead slot grant, one installed guarded build can be run
separately from the retained-artifact suite:

```sh
PYTHONDONTWRITEBYTECODE=1 "$TASK_PY" tools/test_resource_player_presented_client.py --build-only --lead-slot-granted
PYTHONDONTWRITEBYTECODE=1 "$TASK_PY" tools/test_resource_player_presented_client.py --native --lead-slot-granted --build-report build/resource-player-presented-client/build.full.json
```

The owned build process group has a 600-second bound and recorded monotonic
start/deadline. All remaining non-zombie members are terminated/reaped on exit
or failure. A second build attempt and repeated runtime scenarios in this
working generation are refused. The guarded cache's unchanged policy may detect
changed inputs internally; a completed acceptance requires zero retries and
unchanged inputs. Original/transformed C, actual tool/native flags and complete
header/framework/library closure are checked through the existing guarded cache
receipt when a build succeeds. Build/runtime phases and the first failure's
stdout/stderr and available artifacts are preserved. No automatic source,
expectation or compiler repair follows a failure.

Every automated Window launch is hidden, GPU off, and uses the existing guarded
platform build. The existing AppKit observer checks frontmost PID, activation
notifications and Spaces notifications without activating or controlling apps.
Returned CPU pixels and a successful hidden `Window.frame` call establish no
actual drawable readback, visible presentation, focused physical input, vanilla
GPU/sRGB/lightmap/AO equivalence, UI, audio, multiplayer or full-game fidelity.
The static normalized three-model/white-light resource policy remains explicit;
new atlas/animation/texture consumers are not silently enabled.

Current status: preparation passed. The presenter and entry ordinary checks
reach only their declared unsafe/foreign boundaries (90 and 103 named defs).
Six independent comparison views are sealed. No installed C emission, new native
artifact, Window execution, presenter pixel comparison or full kernel verdict
has run for this generation. Preparation is not client acceptance.
