The runnable `remote_resource_catalog_client.bend` now retains its actual loaded
Registry and extends its resource catalog when a sampled state belongs to a
missing family. The complete changed client passes ordinary source checking in
14.740 seconds. The changed native renderer has not yet been built or run;
generic003's earlier socket/pixel/save result remains an immutable, separate
result. Confidence is high for the checked source interfaces and pinned original
resource metadata; changed native behavior is unverified.

`generic_resource_world_sample_resources.Session` owns the actual
`Demand.Owner` (Registry, admitted identity and committed family requests),
`CW.Assets`, and resource-loading configuration. Startup still loads the existing
air plus 129-state profile for the current scene and icon baseline. That list
no longer defines the complete set of potentially admitted families: real sample
misses can extend it under the explicit renderer/material/resource budgets.

The actual client frame loop follows this sequence:

1. Use the existing catalog to build the actual sample frame. A successful warm
   frame returns the same Session without Registry hashing, planning or reload.
2. Only `StateNotLoaded` invokes the existing demand planner. It threads the
   actual Registry and complete committed request inventory through validation,
   decoding and coalescing. Other failures retain their diagnostic.
3. Load **all** planned requests and materials through `RF.catalog_load`, keeping
   the previous assets and ledger outside that call. Texture slots and catalog
   entries are replaced as one coherent material context.
4. Preserve the returned Registry and old assets/ledger on load refusal. A loaded
   candidate must also pass actual `Frame.draw_frame` and `CW.scene`; failure
   closes only the candidate and returns the preserved Session.
5. Publish the candidate and full ledger only after admission, emit one
   `catalog.demand|old_count|new_count|families` diagnostic, and close the previous
   assets last. The normal draw and HUD/menu routines then use that Session.

The existing client refusal behavior closes the client after receiving the
preserved Session. Resource demand does not mutate the actor's authoritative
world. Source checking does not prove IO publication or disposal effects. The
new pure complete-Session law source covers refusal/unchanged continuations;
it has not yet been checked and is not a gate ahead of the actual native run.

The policy explicitly admits model loading by default and names air as invisible,
fluids and chest families as unsupported special renderers. Those named overrides
are not an exhaustive classification of Java special rendering. Other model,
material, animation and renderer forms still face the existing loader checks.
No white tint is fabricated for grass: a required but absent tint remains a
rendering refusal. This is not a claim of complete lighting, position randomness,
ambient occlusion or all vanilla drawable-state coverage.

The policy adds caller-declared Solid layers for the original furnace top, side,
front and lit-front sprites. The pinned 26.3 JAR contains eight furnace states
(four facings by two lit values), their exact model selections and rotations,
one inherited unit cube with six faces, and four opaque unanimated 16×16 sprites.
The Solid assignments are explicit caller admission, not a newly observed Java
GPU render-layer result. Arbitrary missing material declarations remain failures.

The prepared native test reuses the existing actual actor/renderer/relay/save
helpers and independent slab/stair/HUD pixel oracle. It adds both original north
furnace states to the real 512-cell socket sample behind the camera, verifies
their zero visible-pixel contribution, and expects one family publication followed
by a warm frame. Exact old visible pixels then test coherent retention and texture
slot remapping while sampled furnace bindings exercise the real demand path.
This fixture does not establish independently observed Java furnace pixels.
It requires an explicit completed actor generation and a fresh changed renderer.

Attempts are retained under
`build/generic-resource-world-sample-demand-source/001..007`: the first host call
omitted the established 4096-KiB Node stack; subsequent failures exposed computed
tuple matches, policy destructuring, Context/Session annotations and an affine
Options use. Each was repaired before the complete seventh check passed. A
file-only furnace fixture preparation also retained its initial incorrect
immediate-parent-elements assumption before following the actual model-parent
chain successfully. Neither preparation attempt launched native code.

The public launcher remains Actor017/Renderer008. The previous generic003 public
adoption proposal is separate from this demand-enabled candidate; no launcher
promotion or changed native result is inferred from this source checkpoint.
