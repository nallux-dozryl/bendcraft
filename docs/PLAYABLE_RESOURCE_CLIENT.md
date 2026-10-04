# Saved-player world and HUD paired renderer

Current tested local artifacts are `build/compiler-producer-diagnostic-010/actor`
and `build/playable-renderer-current/003/renderer`; launch with the latter
directory's `play.sh`. Fresh missing-world creation, full canonical v3 save and
cold backend reload pass. The actual fresh 128×128 image matches every RGB
channel of the original-JAR/Java quad and literal HUD oracle. Trace-disabled
1920×1080 frames pass at 3.827/3.909 seconds; the optional 25% scene setting
passes at 434/653 ms with 1920×1080 output. These observations do not establish
responsive full-quality gameplay or physical OS-input/drawable acceptance.
See `evidence/playable-renderer-current-build-003.json`, the matching launch,
fresh-pixel and profile evidence. The expanded comparison route below remains
a distinct prepared target; its planned artifacts are not the current launcher.


`tools/test_playable_resource_client.py` targets the named production
`remote_resource_client.bend` entry. Current preparation/build/runtime files live
under `build/playable-resource-client-current`. The earlier six-frame source-only
preparation and exact runner/document bytes remain archived under
`build/playable-resource-client-prepared-002` and its public evidence. Those
receipts describe the earlier fixed 320×180 presentation and admit no new build.

Two paused saved fixtures contain retained actual Java standing/crouched Local
records, an explicit −61 Y translation and the visible finite stone/dirt/planks
world fixture translated identically. The format 3 envelope stores explicit
WG.stone_dirt(seed 0) settings, seven equipment slots and exact raw ability words.
The first demand fills 96 missing sections while preserving the eight existing
sections and increments world revision once; the eight-cube view starts at
floor(Body)−4 on every axis. Visible cells and their neighbor halo remain in the
existing sections. Repeated paused views preserve that revision.

Authored 36-slot inventories exercise saved
selections 4/8, counts 1/2/12/64, all three resolved textures and an invisible main
slot 35 sentinel, with a separate saved offhand stack. These records are saved inputs, not simulated physics results.

Actual pinned Java state-pair masks and baked quads plus original JAR PNG bytes
supply the independent comparison data. Old native renderer source receipts are
historical. The row-bounded NumPy/Pillow ray comparator is controlled against the
retained comparator at 128×128. An independent painter uses literal glyph rows,
rectangle/texture geometry, per-physical-pixel world darkening and inverted RGB.
Its HUD canvas is independent of scene resolution. Literal 128 and 1080 controls
check crosshair bounds, bar edges and selected borders before native execution.

The current route prepares six baseline 128×128 frames and three frames per scene
at both 1920×1080 and 3456×2234, with 100% scene rendering and automatic HUD scale.
Every actual returned `Window.frame` CPU raster must match every expected RGB pixel
and CRC. Frame/sample serials, ticks, revisions, world cells, read counts and
scene/output/HUD dimensions must correlate. A transparent loopback relay forwards
unchanged requests and replies; it checks epoch/sequence and authoritative
Frame→MenuInspect/MenuReply correlation without substituting any
actor/resource/pixel data. The production client loads the same SHA-verified full
item table as the authority, and its menu uses only received MenuSnapshots. A
compatible current menu actor is required before the expanded route can be
admitted.

The planned current actor producer is
`build/playable-client-backend-session/002/backend-native`, with its exact source
map under `build/playable-client-current-source/002`. The helper admits that actor
only after its completed build, consumer manifest, dependency checks and cleanup
exist. Every current actor dependency must be byte-identical to the compiled
original or its mapped source. Its direct server entry receives `--paused` and
other server flags without the old combined consumer's `backend-server` token.

Earlier combined builds and retained pre-expansion actor attempt 001 timed out
before C output and produced no admitted actor binary. They remain historical
failures and cannot satisfy the current menu/terrain route.

The renderer uses the existing guarded macOS Window build and retained desktop
observer. Each hidden process must leave focus/Spaces unchanged. Full saved/public
player and inventory values and durable bytes must remain unchanged. The default
baseline Window remains 512×512; explicit high-resolution CLI requests exercise the
real output and scene dimensions without an unsolicited foreground launch.

Native observations record the actual monotonic render/composition/Window.frame
envelope before trace I/O and sampled process RSS at 50ms intervals. RSS sampling
does not establish allocator peak, and the timing envelope does not establish
input latency, display refresh, drawable framebuffer readback or sustained FPS.
The observer caps each renderer at 60 seconds; the paired chain caps at 600 seconds.
Failure, partial timing, immutable streams and owned-group cleanup are retained.

Build/runtime use automated exact identities and bounded cleanup with two-heavy-job
coordination. The helper neither rebuilds the backend nor requests manual grants.
Run with the bundled Python runtime containing NumPy and Pillow:

```sh
python3 tools/test_playable_resource_client.py --prepare
python3 tools/test_playable_resource_client.py --audit
python3 tools/test_playable_resource_client.py --build
python3 tools/test_playable_resource_client.py --native
```

Preparation and build remain behavior-unverified until actual native results
exist. AppKit resize/fullscreen, physical OS input, all-item models and full
vanilla GUI parity remain separate named boundaries.
