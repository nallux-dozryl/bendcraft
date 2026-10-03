# Checked camera-relative world mesh

`src/world_mesh.bend` is a pure producer between `ClientWorld.relative_snapshot`, actual `BlockBake.bake` results, and `MeshRender`. It borrows only immutable Data values. It has no world, registry, resource asset, window, or clock owner and performs no I/O. A render conversion cannot advance simulation time.

Confidence is **high for the stated finite geometry/pixel scenarios and structural laws**. The final harness passes ordinary checking and native execution. The whole actual producer with exact selected pure dependencies passes `--verdict` and the independent cached BendTT kernel. This establishes the bounded explicit composition below, not complete vanilla world rendering.

## Closed inputs and output

```bend
produce(snapshot: R.Snapshot,
        bindings: List<&2, Binding>,
        texture_count: U32,
        frame: Frame,
        limits: Limits)
  -> Result<&2,&2,Error,M.Scene>
```

`Binding{state,baked,appearance}` selects a previously baked model for one exact registry state ID. The model and its explicit `BlockBake.State` rotation/UV-lock inputs are selected by the caller. There is no inferred blockstate model selection, weighted variant, multipart evaluation, position RNG, or registry-ID assumption. The legacy `R.Block.material` field does not select these textures; the actual baked quad's texture slot does. The caller must supply the matching actual `R.Assets` texture count and pass the resulting Scene to the renderer with those same assets.

`Appearance{tints,light,address,cull,nether,cutout_threshold}` contains unique `Tint{index,color}` bindings, opaque per-channel ARGB light, sprite-local Clamp/Repeat addressing, explicit Back/NoCull triangle culling, the directional shade context, and cutout threshold. A raw tint index of `4294967295` (Java `-1`) always means untinted white and cannot be overridden in the tint map. Every other index needs an explicit color. `appearance()` defaults to no indexed tints, white light, Clamp, Back, default-world directional shading, and threshold 128. The caller supplies light and tint; the producer does not derive biome color, lightmap, ambient occlusion, or emissive illumination from world neighbors. Valid emission metadata is retained in the input bake but does not replace caller lighting.

`Frame{width,height,settings}` supplies dimensions and `MeshRender.Settings`; `frame(width,height)` uses the renderer's existing default clipping/lens/background. `Limits{max_blocks,max_bindings,max_quads,max_translucent,max_tints}` defaults to `4096,1024,4096,64,256`. The source quad budget is the combined quad count across all supplied bindings, including unused bindings. The output quad budget applies after instancing across all snapshot blocks. Limits may be lowered explicitly and reject instead of dropping input. Hard supported maxima are 4096 for blocks, bindings, quads, and per-binding tints, and 64 translucent output quads, matching the existing renderer workload boundary.

## Coordinates, faces and ordering

The camera must be finite and have XYZ numerically zero. This requires the snapshot's established F64 eye-relative conversion: subtract the authoritative F64 camera eye from exact signed block cells before narrowing to F32. The producer never reconstructs relative positions from absolute F32 world coordinates. For each local baked vertex, it performs exactly one native F32 addition per axis, `local + relative_block_origin`, then checks the resulting vertex. UV values remain bit-for-bit unchanged. The material is built using `BlockBake.mesh`, with the resolved tint, caller light/address/cull/cutout threshold, and selected actual default/nether bake shade.

The snapshot block-list order and each binding's baked-list order determine output order. Quad orders are consecutive U32 values starting at zero. This is an explicit bounded dispatch policy; it is not a measured claim about vanilla's complete chunk batching or coincident translucent draw order.

All baked faces are retained, including those with a declared `Baked.cullface`. That field is a face-neighbor cull-group annotation. It is distinct from `MeshRender.Cull`, which controls backface rejection of ray/triangle intersections. There is no neighbor-occlusion pass in this producer, and the Scene type has no neighbor-cull annotation field. The source binding remains available unchanged to callers that need that metadata. Animation is rejected explicitly because the current normalized resource contract provides static sprite images.

Before scene adoption, validation checks frame dimensions 4–1024 and renderer settings; relative camera angles; bounded finite source and translated positions (absolute component at most 4096); finite UV components (absolute component at most 65536); texture indices below the supplied count; finite selected shade in `[0,1]`; opaque light alpha; threshold at most 255; emission 0–15; consistent forced-translucent layer; source/output/translucent budgets; unique states/tints; and every required indexed tint. Material count must be nonzero. The renderer separately validates the actual textures and image dimensions before allocating/rendering the image. Inputs are already immutable lists; this module does not claim a streaming memory budget or validate raw resource text itself.

`Error{code,state}` returns the relevant state where available. Configuration/source-binding errors use state zero, which is a diagnostic sentinel and may also be a valid registry state. Codes are `Limits`, `Frame`, `RelativeCamera`, `TextureCount`, `BindingLimit`, `DuplicateState`, `Appearance`, `SourceQuadLimit`, `UnsupportedAnimation`, `BakedMetadata`, `MissingTint`, `BakedQuad`, `MissingState`, `BlockOrigin`, `BlockLimit`, `TranslatedQuad`, `QuadLimit`, and `TranslucentLimit`.

## Verification scope

The bounded native harness loads the installed pinned 26.3 JAR through the production `BlockResources` ZIP/DEFLATE/JSON/model/PNG path, bakes actual stone/dirt/oak-planks resources, resolves their state IDs from the actual registry, and converts actual camera-relative world snapshots. No expected Java quad is supplied to the producer. The independent oracle uses the separately captured pinned Java bake output only to compare translated vertex/UV/material words. Python also compares every output RGB byte against the existing independent MeshRender pixel oracle and extracts PNG textures only for that oracle.

The final run checked **40 snapshots, 892 blocks, 5,352 world quads, and 16 frames totaling 12,288 exact RGB pixels**, with zero mismatches. The 39-block fixture produced 234 quads; the raw edit produced 40 blocks/240 quads and changed 42 pixels while tick remained 1 and revision remained 47. Cached and uncached frames matched exactly. A legitimate reordered registry changed IDs while producing the same geometry and pixels. All eight signed-axis combinations near ±30,000,000 cells, each with four binary64 fractions, passed exact relative-origin/translated-vertex checks; eight representative far frames also passed every-pixel comparison. Thirty-two validation outcomes include 29 exact rejection codes and three accepted cases; one additional emitted quad verifies explicit tint `0xFF112233`, white light, nether shade bits `0x3F666666`, Repeat, NoCull and order zero.

The recorded native build took 543.066206 seconds and the complete runner 588.528457 seconds on this shared host, within the granted 600-second build cap. These are build/verification observations, not a rendering or Minecraft performance comparison. `evidence/world-mesh-native.json` records all counters, hashes, commands and observed frames; sources, binary and inputs remained unchanged during execution. Rendering stayed hidden and bounded at 32×24, so this does not establish visible client/input acceptance or vanilla final-frame equivalence. Stone explicitly selects the unrotated stone model; the sealed Java metadata also identifies a weighted mirrored alternative, which is outside this fixed binding test.

Two structural laws state that translation preserves a vertex's UV and a quad's material/cull/order for arbitrary typed values. The entire actual producer and exact selected pure dependencies passed ordinary checking, `--verdict`, and the cached independent BendTT kernel after module-qualification renaming. Exact isolated source, translation, proof goals/witnesses, dependency fingerprints and commands are recorded in `evidence/world-mesh-kernel.json`. This does not verify the complete effectful/resource import chain or establish floating-point arithmetic parity, complete scene correctness, state/model selection, resource fidelity, rendering parity, or runtime effects.

Reproduce the scoped native verification with one sufficiently provisioned build slot:

```sh
python3 tools/test_world_mesh.py
```

Remaining fidelity includes actual blockstate variant/multipart selection, neighboring shape occlusion, world tint/light/AO, animated/stitched atlas behavior, vanilla batching/raster/transparency policy, and the native client presenter/input integration.
