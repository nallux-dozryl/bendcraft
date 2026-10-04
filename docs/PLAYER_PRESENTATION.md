# Production player presentation

`remote_resource_client.bend` joins the actual remote saved-player actor to
`remote_resource_presenter.bend`. `player_presentation.bend` supplies one shared
dimension and coordinate policy to the presenter, HUD, `mesh_render.bend` and
`world_mesh.bend`. The native adapter is project-owned; Base Window and the guarded
platform transform remain unchanged.

The human default requests 1920×1080 output, 100% internal scene resolution and
automatic HUD scale. These are source defaults, not measured performance choices.
The pure `player_client_options.bend` parser classifies long options by equality
to avoid structural string-pattern expansion. The entry accepts `--width`, `--height`, `--render-scale` (25–100 percent),
`--hud-scale` (0 automatic, 1–4 explicit), `--display-native`, `--fullscreen` and
`--windowed`. Actual drawable dimensions determine scene allocation after window
configuration and after each resize. Native mode requests the screen's available
content extent; fullscreen requests its full extent. The known 3456×2234 physical
display fits the policy, but actual mode/screen geometry is read from AppKit.

`--item-table PATH` selects the catalog input; its bytes must match the observed
complete table's SHA256 before UTF-8 decoding and parsing. The client and saved
authority share that verification function. Missing or altered input produces a
load error rather than a reduced or fabricated catalog.

The scene renders at `max(4,floor(output*render_percent/100))` per axis. Integer
nearest-neighbor projection maps that scene to output only when extents differ.
The HUD/menu is composited afterward, using its own logical canvas. Automatic HUD
scale uses the largest integer 1–4 for which a 320×180 canvas fits. At 1920×1080,
automatic scale 4 produces a 480×270 canvas; at 3456×2234 it produces 864×558.
Explicit scale is honored even at small outputs; the menu can report insufficient
space. Default hidden tests remain 128×128 scene/output in the existing 512×512
guarded Window. Explicit hidden extents support offscreen high-resolution checks.

Dimensions 4–4096 per axis are admitted. This is a concrete current Image tree and
buffer allocation bound, not a measured hardware ceiling. The backing side is the
next power of two at least as large as either axis. The actual renderer allocates
its full square backing tree, including sky and rectangular padding:

| Scene extent | Backing side | Image leaves | Visible pixels |
| --- | ---: | ---: | ---: |
|128×128|128|16,384|16,384|
|1920×1080|2048|4,194,304|2,073,600|
|3456×2234|4096|16,777,216|7,720,704|

Those are logical leaves, not runtime byte/RSS estimates. The sparse HUD and
resampler reuse constant subtrees, but the existing world renderer does not yet
collapse constant sky/padding allocations. Output increases do not increase the
separate world geometry submission budget or view distance.

Base's native event positions are content points. The adapter reports both
content-point and drawable extents; the presenter scales absolute mouse, move and
scroll positions into drawable coordinates before menu hit testing. Out-of-range
positions become an output-extent sentinel, so a drag outside the view does not
click an edge slot. Relative Look deltas and key codes are unchanged. Drawable
and point extents are checked before initial capture and subsequent frame queries.

`player_presentation_laws/proof` binds structural induction to the actual
`Mesh.tile` and `Mesh.frame` allocation, the world/frame dimension interface,
event ordering, key/Look preservation and outside pointer rejection.
`player_presentation_input_laws/proof` binds focus/capture suppression to the
actual HUD command path, first-capture click consumption, excluded compositor
subtree preservation, matching-scene identity and projection crop padding.
No axioms are declared. All seven allocation/interface/event/outside-pointer laws
pass the independent kernel through a read-only source-API export retaining every
definition, term and selected proof unchanged. Unrelated law roots are omitted
from the export order; no selected law or implementation is excluded. The earlier
monolithic 60-second timeout remains retained. The separate nine HUD/input laws
also pass an independent kernel verdict through the same read-only export route,
with all nine roots included and no export exclusions. The menu adapter retains the complete received authority during local input and
installs complete fresh replies even when an operation is refused; its separate
five full-authority laws pass the independent kernel in 0.362 seconds with the
complete 1,454,490-byte referenced export and zero exclusions
(`evidence/player-menu-input-kernel-001.json`). Server observations reconcile an idle menu on
refocus, preserve pending requests, and release captured world controls before
menu events. Each reply-driven capture checks current native focus immediately
before capture. The presenter IO join and native boundaries remain outside the
seven plus nine completed laws. Public proof evidence records the exact source,
compiled terms, export API/script, Node and independent kernel identities.

Literal tests inspect actual composition at 1920×1080, with a 960×540 scene and
scale 4 HUD. They check crosshair extents, selected borders, resource icons, decimal
count shadows, untouched world pixels, output edges and zero crop padding. Samples
do not prove all U32 arithmetic or the native AppKit/Metal boundary. Exact pixel
comparison, drawable behavior, resize/fullscreen, focus/Spaces and frame/RSS
measurements remain native checks. `client.timing|serial|elapsed_ms` measures the
render/composition/Window.frame envelope before trace I/O; it does not establish
input latency, display refresh, framebuffer readback or sustained FPS.

The current renderer003 is now native-built. Actual fresh hidden 128 startup
loads the full item table/JAR, matches all 16,384 CPU pixels against the independent
original Java/JAR/HUD comparator and saves the complete fresh state durably.
Two trace-disabled 1920×1080 scene/output frames preserve the 480×270 HUD and pass
in 3.827/3.909-second render/composition/Window.frame envelopes. Recording the
high-resolution CPU image exposes a subsequent private-input failure; keep that
failed attempt separate. These observations do not establish physical OS input,
drawable framebuffer equality, Retina resizing/fullscreen or sustained FPS.

Renderer004 implements structural bounds before ray construction, matched
parallel/nonparallel slab spans and16×16 sequential tiles below the fork tree.
Its128×128 captured CPU image matches the independent Java/JAR/HUD oracle and
renderer003 byte-for-byte. Eight trace-disabled1920×1080 envelopes take
1015,1272,951,923,961,949,956,945ms (median953.5ms), with unchanged100% scene/output
quality,480×270 HUD and two CPU workers. It is still slow; no FPS or input-latency
claim follows. Full1080 pixel comparison remains pending.

The borrowed mesh traversal and scalar candidate repair now pass15 exact native
fixtures and18 current independent-kernel laws (8 presentation,6 tile,4 reader),
zero exclusions. The current eight presentation statement types are unchanged;
proofs handle the structural resource-list/tree zero branch explicitly. Receipts
are `evidence/mesh-render-presentation-kernel-001.json` and
`evidence/mesh-render-borrow-repair-001.json`. Renderer005 is compiling from the
frozen004 sources plus only this MeshRender overlay; full-frame performance is
unmeasured. The slower tile prepass remains separate. Both working launch
artifacts are preserved.
