# Production mesh readers and scalar selection

The existing MeshRender entry and pixel arithmetic are preserved. The change
matches Spatial constructors on rejected visibility, Prepared on missing hits,
and the texture list on rejected candidates. Each path reads its owner instead
of letting an unmatched boxed parameter become a runtime sink. Padding returns
zero before direction/intersection work and reads only the owner constructors.

`prepared_frame` retains the full BVH and alpha list until the drawn Image is
complete. Its last use is the explicit host `finish_tree`/`finish_quads` walk.
Neither walker uses a GPU bang. The frame still uses the existing16-pixel fork
boundary and full requested quality; bounds expansion, near/far tests, UVs,
cutout thresholds, source-index/order ties and alpha composition are unchanged.
`spatial_mode` constructs only the requested BVH or Flat mode. Concrete
`chosen_hit`/`chosen_fragment` selectors return scalar records and avoid generic
conditional boxing of per-hit records.

Four generic laws independently pass the cached kernel with no export exclusions:
the actual Hit and Fragment selectors equal the established conditional interface,
and both actual last-owner walkers preserve the complete Image. The complete
production tree walk is proved by structural induction, including both children
of each Branch. The Tile renderer's six conditional hit/owner laws also pass at
the current Mesh source. The eight existing presentation statements remain
unchanged; their padding proof needs the actual constructor cases, and root owns
its current recertification. This receipt records the latest ordinary deadline
without claiming that eight-root kernel result.

The focused compiled consumer compares every pixel in15 cases (10,975 per
renderer) with the retained pre-change renderer captures and the existing
independent binary32/Pillow oracle on actual Java baked vertex/UV/material words
and official PNG textures. All current Tile, flat and BVH outputs pass exactly,
including cutout, translucent order/source-index ties, occlusion, near-plane
crossing, near/far rejection, rectangular/minimum dimensions and a216-quad grid.
These are Java geometry inputs, not a Java final framebuffer comparison.

In this exact emitted C, `spatial_trace` changes from three `ctr_take` and four
field-sink sites to three `term_peek` sites, with zero takes/sinks/keeps/seals.
`opaque_trace` and `trans_trace` change from two takes each to two peeks each.
Their continuations, the frame and tile traversal have zero owner-count operations.
The solid-candidate continuation has zero heap allocations/count calls after
removing the previous two generic Fragment boxes, eight seals and one take.
Constructing the output Image still allocates its required nodes. Prepared is
flattened in the focused consumer and the original renderer004 C; current full
renderer C must still verify its own context-specific borrowing decisions.

Small CPU timer samples vary under concurrent work and do not establish a
full-frame speedup. The separate Tile exact-miss prepass remains too expensive
and is not integrated into ResourceFrame. Root's production renderer build and
full-pixel frame measurement decide the practical outcome. Source/API/IR/kernel,
raw captures, process-group cleanup, exact C function locations and counts are
pinned in `evidence/mesh-render-borrow-repair-001.json`.
