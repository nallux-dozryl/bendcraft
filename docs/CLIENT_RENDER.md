# Bounded native client rendering integration

`src/client_render.bend` provides a checked pure Bend renderer and a real
JAR-to-pixel asset path. This is a verification instrument in the continuing
26.3 reimplementation. It does not establish Minecraft client parity or
completion.

## Shared snapshot contract

```text
R.Block{x: F32,y: F32,z: F32,state: U32,material: U32}
R.Camera{x: F32,y: F32,z: F32,yaw: F32,pitch: F32}
R.Snapshot{tick: Nat,revision: Nat,blocks: List<&2,R.Block>,camera: R.Camera}
R.Assets{textures: List<&2,R.Texture>}                 # affine owner
R.load_assets(path: String) -> IO(Result<&2,&1,A.Error,R.Assets>)
R.render(snapshot: R.Snapshot,assets: R.Assets,width: U32,height: U32)
  -> R.Assets & Base.Image                            # parallel CPU
R.render_gpu(snapshot: R.Snapshot,assets: R.Assets,width: U32,height: U32)
  -> R.Assets & Base.Image                            # one bang, optional Metal
R.write_ppm(path: String,image: Base.Image,width: U32,height: U32) -> IO(Unit)
```

A block is an opaque unit cube at its actual snapshot position. State IDs
remain attached for traceability; the simulation snapshot producer performs
an explicit supported state-to-material mapping. The renderer contains no
world generator, fabricated default block arrangement or simulation clock.
A snapshot is immutable. Rendering returns its affine asset owner and cannot
mutate sections or advance ticks. Authoritative positions remain raw binary64
in the motion subsystem; binary32 narrowing is exclusively a render boundary.
The camera's position is its eye, yaw/pitch are radians, yaw zero looks along
positive Z, positive yaw turns toward negative X and positive pitch looks down.

Dimensions supplied to these bounded APIs must be in 4..4,096. The image is a
power-of-two square tree covering the viewport; Base clips its unused region.
It casts normalized perspective rays with a fixed 70-degree vertical field of
view and a 64-block far distance. AABB slab intersection chooses the nearest
visible unit-cube face. Face coordinates select nearest texture samples;
the production `CardinalLighting.DEFAULT` directional factors (down 0.5, up 1, X sides 0.6, Z sides 0.8) feed a bounded integer RGB scaling calculation. This integer RGB quantization is an approximation of vanilla's final color pipeline: GPU UNORM rounding, sRGB conversions, material overrides and lightmap processing have not been reproduced. One balanced fork tree
ends in sequential 4x4 tiles. The initial implementation scans the immutable
candidate list per ray. It has not established scaling for large worlds.

## Actual asset loading

`load_assets` opens the installed pinned client JAR with `A.UTF8Fallback{}`
and bounded archive limits. Bend validates ZIP entry data and CRC, inflates
DEFLATE, parses PNG, reconstructs its scanlines and converts straight-alpha
RGBA words to owned texture trees. Base File effects provide bounded reads;
there is no custom native decoder or Python runtime asset pipeline. Errors
remain explicit and prevent startup; no synthetic fallback stands in for a
failed official resource load.

Material slots currently load these exact vanilla assets:

| Slot | Resource |
| --- | --- |
| 0 | `assets/minecraft/textures/block/stone.png` |
| 1 | `assets/minecraft/textures/block/dirt.png` |
| 2 | `assets/minecraft/textures/block/oak_planks.png` |

Only this opaque full-cube subset is rendered. An unsupported material slot
is visibly magenta rather than silently assigned another vanilla texture.
Full model/blockstate parsing, variant choice and rotations, mirrored stone
UVs, tint/overlay grass models, translucent materials, animated sprite timing,
world lighting, biome color, clouds, entities, particles, HUD/UI and the
vanilla dynamic field of view remain unimplemented here. Production CPU `FaceBakery` executions independently confirm all six unrotated cube UV orientations used here; rotated and mirrored variants remain outside this implementation. Reference fixtures
preserve those missing distinctions in `reference/render_assets.json`.

## Independent native image verification

```sh
/Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 tools/test_client_render.py
```

This generates a clearly identified 28-block **test fixture**, then builds
native macOS programs through `tools/platform_build.py`. Every launch sets
`BEND_MINECRAFT_LAUNCH_MODE=hidden`. Base still creates its real NSWindow,
CAMetalLayer and frame path; the build adapter suppresses foreground activation
and Space changes. No automated test calls the human foreground branch.

At 64x64 and 128x128, the test reads back the actual Bend-produced image tree
into a PPM artifact. It compares every pixel with an independent Python
binary32 ray/AABB/UV/shading calculation using Pillow-decoded official texture
bytes. Forced CPU and Metal output must agree byte for byte. This proves the
stated renderer calculation and asset path on those finite frames. It is not
an independent Java framebuffer parity comparison.

The native platform observation checks invisibility, nonkey/nonmain state,
inactive application and activation policy 2. A returned hidden
`Window.frame` is separately recorded and does **not** prove on-screen
presentation. PPM readback is the pixel evidence. The independent platform
observer's focus/Space contract remains documented in `docs/PLATFORM.md`.

`evidence/client-render-native.json` records output hashes, dimensions, exact
asset/source digests and observed timings. Timings are a bounded smoke
measurement with millisecond resolution and a handful of warm frames, not an
equivalent-quality Minecraft benchmark. CPU is the default render path for
this small scene; `render_gpu` is explicit for GPU integration/verification.
`bend src/client_render.bend --verdict` reports `ALL PROOFS CHECK`. It checks
Bend definitions and establishes no theorem about AppKit, Metal, Minecraft
presentation or unimplemented model semantics. Confidence in this finite
CPU/Metal and independent-pixel integration is high; Minecraft rendering
parity remains unknown.

## Shared-actor client entry

`client.bend` loads the verified official texture subset, creates the explicitly
requested verification fixture through `src/client_world.bend`, and gives that
single owned `Game.Engine` to the normal server actor. The display obtains
immutable snapshots using typed `Server.local_call`; developer TCP requests,
clock pulses, motion verification queries and renderer snapshots serialize
through the same actor. No second render world or cloned section store exists.

The window/controller is now shared through closed typed callbacks in
`src/client_host.bend`. The save-owning entry and exact camera-relative view are
documented in [PERSISTENT_CLIENT.md](PERSISTENT_CLIENT.md). The normal entry's
legacy pixels and synthetic controls were independently rerun after this
refactor; evidence is `evidence/client-host-integration.json`.

Build with the native launch adapter:

```sh
python3 tools/platform_build.py client.bend -o build/minecraft-client \
  --report build/client-render-entry-build.json
```

For a finite automated run:

```sh
BEND_MINECRAFT_LAUNCH_MODE=hidden MC_DEV_TOKEN=local-verification-token \
  MC_LIVE_PORT=47163 build/minecraft-client --gpu off \
  --verification-fixture --frames 3 --dump build/client-render-entry.ppm
```

`--jar PATH` selects an explicit client JAR location. Startup currently requires
`--verification-fixture` because a playable world loader/generator has not been
implemented. An unspecified mode fails with that explanation. A human can omit
the hidden environment variable and `--frames` to run the normal foreground
window. The developer token is the same explicitly configured local API token
used by the existing server; it is not an account credential.

Human controls are deliberately bounded verification actions: W/A/S/D submit
0.25-unit horizontal collision moves using the current camera direction; Q/E
submit 0.25-unit vertical moves. Grabbed mouse motion submits camera angles;
Escape or closing the window quits. These are discrete actions per key event,
including OS repeats. They do not claim vanilla WASD acceleration, gravity,
friction, jumping, abilities, sensitivity or pose semantics. The simulation
remains on the actor's 50 ms cadence and rendering never advances it.

Automated hidden launches do not grab the cursor. A finite frame count closes
the window, acknowledges actor/timer stop and then terminates the process.
The server's accept effect may still be OS-parked at this interim boundary;
process termination releases it without forging or duplicating a Listener.
There is no save-on-exit implementation in this instrument. The unsafe client
loop covers OS lifetime only; it prevents a complete client kernel verdict,
while the pure PNG, renderer, snapshot and collision modules retain their own
separately checked contracts.

The native entry integration test runs **100 hidden frames** of the 39-block
owned-section fixture, authenticates through the real TCP API, changes all
36 floor blocks and explicitly steps the shared simulation. Every pixel
before and after must equal the independently calculated expected frame.
Snapshot logs must reflect tick/revision 1/47 and 2/83; the completed client
process must exit 0 and release its real listening port. These tests establish
the stated shared-authority integration without establishing vanilla controls
or framebuffer parity.

A separate generated native test sends explicit Bend `Key(W,down)` and
`Look(12,-7)` fixtures through the actual client event handler and shared
actor. It compares all three authoritative binary64 position words and every
pixel after the resulting camera move. This verifies controller/actor/camera
wiring. Hidden windows receive no focused keyboard or mouse input, so
hardware input/focus behavior remains untested. Java geometry and lighting
observations are reproducible via `tools/reference_model_probe.py` and
`reference/model_semantics.json`; they are separate from the current integer
color output approximation.
