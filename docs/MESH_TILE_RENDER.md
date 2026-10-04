# Flat candidates for the actual mesh renderer

`src/mesh_tile_render.bend` is a separate production renderer importing the existing
MeshRender and ClientRender modules. It changes neither module and is not yet wired
into ResourceFrame. Its pixel calculations use actual `M.quad_hit`,
`M.opaque_trace`, `M.pixel_best`, texture sampling, cutout coverage, source indices,
supplied order, and sorted alpha composition.

The owner loop is:

```text
prepare(scene,width,height) -> Owner
  draw(owner,resources) -> Owner & resources & Image
  release(Owner) -> original Scene
```

`prepare` is an unchecked pure preparation helper: its caller must first apply the
same `M.validation(scene,textures,width,height)` admission used by MeshRender.
Owner retains the complete source Scene, basis, settings, dimensions, backing
depth, and candidate cell tree. `draw` returns that owner and all texture Images.
The consumer releases the owner once after the draw completes. `release` runs an
explicit host tree/list destructor and returns the original complete Scene.
There is no GPU bang or device destructor in this initial implementation.

A balanced fork tree ends at16×16 tiles, or an8×8/4×4 backing image for the
existing smaller valid dimensions. `b16`, `b8`, `b4`, and `b2` are explicit
straight-line image constructors; pixels see short flat opaque/alpha lists rather
than a Spatial tree. Each tile clones only its local list spines from retained
entries. `fin` consumes those local lists after the final pixel read. In the focused
native008 artifact, the node reader has two `term_peek` sites and zero
`ctr_take`, `term_sink`, or `term_keep` calls; tile pixel/b2/b4/b8 readers likewise
have no owner-count operations. Image constructor allocation remains necessary.
This is a compiled CPU result for the pinned consumer, not a GPU claim.

Projection uses the camera basis inverse and eight prepared-bounds corners to
propose a broad screen rectangle. Near-plane, nonfinite, or unstable projections
retain the quad. A projected miss alone never excludes a quad: the selector scans
all256 admitted pixel centres with the actual production `M.quad_hit` and excludes
it only if every sample misses. This confirms exclusions under the renderer's real
binary32/cull/near/far behavior and avoids relying on an unproved fixed-margin float
culling claim. The extra host intersection work can exceed the current BVH's cost.
Performance must include preparation and drawing before choosing integration.

Six actual laws passed ordinary checking and the independent cached BendTT kernel
with zero selective-export exclusions. The source API retained every original
`tlds`, `ctrs`, `tmps`, checked type, body and proof; only the root order selection
changed. The laws cover complete owner/resource retention, complete Image retention
through list release,256 backing pixels per straight-line tile, whole-raster
rejection completeness, production admission completeness, and omitted-miss
invariance of the complete production opaque traversal. This is conditional
composition around actual hit results, not an independent theorem proving floating
point triangle geometry. Current Mesh borrower changes required a structural
Prepared/list-case adaptation of the omitted-miss proof; its statement is unchanged.
See `evidence/mesh-tile-render-proof-003.json` for the current exact generation;
earlier numbered receipts retain their original source manifests.

The focused native consumer compares all output words with current `M.render_flat`
and `M.render`, then with the existing independent pixel oracle using retained real
Java baked quad inputs and official PNG textures. Its cases cover empty and
rectangular frames, actual stone/glass geometry, cutout, translucent alpha/order,
source-index ties, occlusion, a near-plane crossing, near/far rejection, an offscreen
miss, and a stone-grid total-cost sample. All15 cases and10,975 visible pixel words
per renderer passed exactly. The forced false-proposal selector also agrees with
the independent hit oracle, and release returns each original Scene quad count.
The first run exposed an incorrect minimum backing side; the corrected4×7 case
now passes with the actual Presentation depth. The failed generation is retained.

The corrected pre-borrow fixture measured80ms for Tile preparation+draw+forced
output,76ms for the flat Mesh renderer, and3ms for its BVH at64×64 with216 real
stone quads. Later runs with the Mesh borrower repair vary under concurrent work;
they support no full-frame speed claim. The exact256-ray miss confirmation makes
this Tile implementation unsuitable for production integration. ResourceFrame
continues to use the BVH renderer. See `evidence/mesh-tile-render-native-001.json`
and `evidence/mesh-render-borrow-repair-001.json`.

No Java final framebuffer, GPU or window parity is claimed by these tests.
