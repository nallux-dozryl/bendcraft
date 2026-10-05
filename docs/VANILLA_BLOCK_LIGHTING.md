# Pinned26.3 pervertex block lighting

`vanilla_block_lighting*` implements actual `BlockModelLighter.prepareQuadAmbientOcclusion` and `prepareQuadFlat`, including the pinned `LightCoordsUtil` blending and `QuadInstance` color/emission operations. Simulation is pure Bend; Java only observes the installed receiver and initialized states. There is no block-ID or fixture recipe dispatch in production. All six directions, finite baked coordinates, state observations and cardinal brightness values are inputs.

```
M.Request{stamp:M.Stamp,origin:M.Position,source:M.StateInfo,
          quad:M.Quad,mode:M.Mode}
L.stencil(Request) -> List<M.Position>
L.resolve(Request,Context) -> Result<M.Error,M.Appearance>
M.Appearance{a:M.Vertex,b:M.Vertex,c:M.Vertex,d:M.Vertex}
M.Vertex{raw_light:U32,light:U32,color:U32}
```

`M.Stamp{registry,dimension,tick:Nat,revision:Nat}` is extracted from the actual publication. Request and captured Context must match exactly. `M.Position` stores Java signed coordinate bits in U32. Cells contain `Maybe<StateInfo>`, `Maybe<block level>` and `Maybe<sky level>`; missing resident state or unavailable raw fields never become air/fullbright. StateInfo contains actual registered stateID, emission, emissiveRendering, solidRender, collisionFull, lightPermeable and shadeBrightness. Source must match the actual captured origin cell, including complete state properties and shade bits. CardinalLighting's actual six float values are mandatory; a dimension label does not authorize a guessed default. Shade/cardinal values must be finite0..1 and emissions/raw levels0..15. Nonfinite geometry refuses.

`vanilla_block_lighting_baked.request(stamp,origin,source,baked,ambient_option,first_part_ao,known_flat)` converts the existing actual `block_bake.Baked` vertices/direction/material flags. It retains exact baked position floats, shade override and element emission. AO mode follows the actual ModelBlockRenderer condition: option enabled, source emission0, and **first collected model part** useAmbientOcclusion. It must not independently choose mode for each later part. Item/gui `useBlockLight` or `gui_light` is not a BlockModelLighter world-lighting flag and cannot replace this selection. Existing `default_shade`/`nether_shade` cached in Baked must not shade the resulting colors again.

The conservative stencil deduplicates at most14 positions: origin and forward face, four lateral edges, four forward edge permeability tests and four conditional diagonals. Smooth cubic faces can probe two cells along the face normal. A face counts as cubic when planar on that axis and at the strict1e-4/0.9999 boundary **or** the source has an actual full collision shape. Partial/noncubic weighting uses the actual face bounds, pinned adjacency-weight tables and direction-specific vertex remap. Opaque forward edges skip diagonal sampling and reuse the exact edge0 light/shade pair, including both lower corners. The resolver accesses only required diagonals; unavailable unused diagonal cells do not cause refusal. The stencil is a capture superset, not a claim that Java reads every possible diagonal. Face culling/skipRendering and biome/model tint selection stay with the actual model/catalog consumer; this module implements AO occlusion, not those separate callbacks.

Raw block/sky levels are packed at bits4/20. AO `smoothBlend` repairs zero or missing-sky neighbours only when the center level is above2, then averages exact packed bytes. Weighted partial faces preserve the fractional low four bits. Source-state emission raises only block light; emissiveRendering returns Java fullbright as an actual state property, rather than a missing-field fallback. Element emission is separately applied to each final vertex: emission0 preserves every fractional bit; nonzero emission raises **both** integer block and sky levels and repacks, following the actual26.3 helper. Color follows Java's two quantization stages: AO mean/weighted clamp to ARGB.gray, then ARGB.scaleRGB by actual directional brightness. A flat face instead uses ARGB.gray(side) directly. Shade override affects directional brightness, not the AO sample direction.

The live capture owner must thread the sole Core and block/sky authority through the arbitrary-position sample batch at the same stamp, resolve actual state properties from loaded catalog and any required world-dependent collision/shade receiver, then build M.Context. `sky_light_world.sample_batch` already supports exact arbitrary positions and returns its actual clock. A static occlusion/emission descriptor alone cannot infer collisionFull/shadeBrightness or solidRender; unsupported state/world-dependent property receivers must remain explicit refusals. This module does not create a second world or authenticate caller-made properties as actual Core observations.

The minimal renderer join is:

1. Construct the Request from actual selected Baked geometry and first-part AO mode; union its stencil with other captured positions.
2. Capture actual state/raw block/sky/property/cardinal facts once at the existing publication stamp, then call `L.resolve`.
3. For each corresponding baked vertex, use `Vertex.light` with the lightmap owner's `sample_packed(texture,packed)` and retain `Vertex.color` as the AO/side-shade ARGB multiplier. Apply actual tint once; interpolate vertex appearance in the rasterizer. Keep raw packed coordinates available for the actual shader boundary.
4. Add pervertex appearance to the lead-owned mesh path. Existing WM.Appearance's singleRGB cannot carry this result; assigning the origin cell's RGB to all vertices would discard the computed semantics. Current material shade must become1 for this already shaded path.

No shared world_mesh, Core, Session or renderer files were edited. Actual live field capture, shader/raster interpolation, face culling/tint callbacks and publication are consumer integration seams, not completed by the pure lighting module.

## Verification

```
python3 tools/reference_vanilla_block_lighting.py
/Users/chuah/.bend/bin/bend tests/vanilla_block_lighting.bend --check-only
/Users/chuah/.bend/bin/bend src/vanilla_block_lighting_baked.bend --check-only
python3 tools/test_vanilla_block_lighting.py
python3 tools/test_vanilla_block_lighting_proof.py
```

The new independent Java reference observes actual initialized flags/shade/full collision, receiver world queries, face-cubic/partial flags and four raw/final packed-coordinate/ARGB records.42 cases/168 vertex records cover six directions, full/partial/inset faces, opaque diagonal fallback, mixed permeability, source/emissive/element emission, custom side shade and override, known flat coordinates, nonplanar/outside-unit geometry and strict threshold boundaries. Native Bend matches every coordinate/color bit. Its deduplicated stencil includes every actual Java world query. Eight native refusals cover stale stamp, absent state/light/cardinal, duplicate position, invalid brightness, nonfinite geometry and source mismatch.

Seven implementation-connected independent-kernel laws cover fractional preservation without element emission, actual emissive bypass, opaque diagonal fallback, unweighted corner retention, uniform known-flat lighting for arbitrary quad fields, and missing state/block-brightness refusal. No axioms, foreign declarations or scope exclusions. Exact source pins, bounded timings and commands are in `evidence/vanilla-block-lighting-native.json` and `evidence/vanilla-block-lighting-proof.json`. Native correctness uses clang-O2 with explicit `-ffp-contract=off`; it does not establish GPU arithmetic or renderer performance. No unchanged physics, recipe, model or lighting corpus was replayed.
