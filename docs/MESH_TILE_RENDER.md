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

A balanced fork tree ends at16×16 tiles. `b16`, `b8`, `b4`, and `b2` are explicit
straight-line image constructors; pixels see short flat opaque/alpha lists rather
than a Spatial tree. Each tile clones only its local list spines from retained
entries. `fin` consumes those local lists after the final pixel read. Actual emitted
C borrowing must be inspected before claiming that this structure avoids counted
reads in the compiled artifact.

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
point triangle geometry. See `evidence/mesh-tile-render-proof-001.json`.

The focused native consumer compares all output words with current `M.render_flat`
and `M.render`, then with the existing independent pixel oracle using retained real
Java baked quad inputs and official PNG textures. Its cases cover empty and
rectangular frames, actual stone/glass geometry, cutout, translucent alpha/order,
source-index ties, occlusion, a near-plane crossing, near/far rejection, an offscreen
miss, and a stone-grid total-cost sample. Native comparisons, timing and emitted-C
borrow inspection remain pending. No Java final framebuffer, GPU or window parity
is claimed by these tests.
