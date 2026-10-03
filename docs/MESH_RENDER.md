# Bounded baked-quad CPU renderer

Confidence is high for the supplied geometry and the explicitly defined algorithm covered by native evidence. This is a separate rendering component. The existing client remains on `client_render.bend`; model loading, model baking and world integration are separate dependencies.

`src/mesh_render.bend` is pure checked Bend. It borrows immutable `R.Texture` image trees from the single owned `R.Assets` value and returns that owner on success and failure:

```bend
render(scene: Scene, assets: R.Assets, width: U32, height: U32)
  -> R.Assets & Result<&2,&2,Error,Image>
```

The renderer has no foreign game implementation, runtime Java dependency or Python decoder. Its CPU fork tree uses the existing Base `Image` type. The test driver loads real textures from the pinned official JAR through the existing pure Bend ZIP, DEFLATE and PNG modules. Synthetic finite RGBA textures are explicitly test fixtures.

## Input contract

`Scene{camera:R.Camera,quads:List<&2,Quad>,settings:Settings}` contains already baked quads. `Vertex{position:Vec3,uv:UV}` stores F32 position and normalized sprite-local UV values. `Quad{a,b,c,d,material,cull,order}` preserves the input vertex order, splitting the surface into `(a,b,c)` and `(a,c,d)`. Triangles may define a nonplanar quad; this explicitly renders two triangles rather than estimating a plane. Degenerate triangles and intersections with determinant magnitude at most F32 `1e-8` produce no hit.

Geometry and camera positions must share one finite coordinate frame. Absolute F32 world coordinates lose adjacent-cell precision at large world positions. World integration must subtract the authoritative F64 camera origin from exact block coordinates **before** narrowing to F32. A camera-relative mesh uses camera XYZ zero. Translating the original Java-local positions into the frame is an integration operation, not a model bake.

`Settings{near,far,scale,background}` explicitly supplies distance clipping, tangent of half the vertical field of view, and an opaque ARGB background. `defaults()` gives near F32 `0.0001`, far `64`, scale F32 `0.7002075382` (the existing 70-degree verification lens) and a constant blue background. Pixel-center rays use the existing `R.Camera` yaw/pitch convention: yaw zero faces +Z, positive yaw turns toward −X and positive pitch faces down.

Validation rejects the entire scene and returns its asset owner when any of these fail:

- Width/height are 4–1024; at most 4096 quads and 64 translucent quads are supplied.
- Positions, including camera XYZ, are finite and have magnitude at most 4096. Yaw/pitch and UV components are finite and have magnitude at most 65536.
- Near is positive, far is greater than near and at most 4096, and scale is positive and at most 8. Background alpha is 255.
- Every material texture slot exists; shade is finite within `[0,1]`; light alpha is 255; a cutout threshold is at most 255.
- Texture dimensions are positive, fit their power-of-two image side, and side is at most 4096. `R.Texture` requires a valid corresponding image tree from the established asset constructor; the renderer does not validate every tree leaf.

Error codes are `Dimensions`, `Camera`, `Settings`, `Textures`, `Vertex`, `Material` and `Limits`. Count limits reject instead of silently truncating geometry or alpha layers. The dimension limit is a workload bound, not an implemented production window-resolution policy.

## Explicit material and pixel algorithm

`Material{texture,tint,light,shade,mode,address}` uses a texture-list slot, packed straight-alpha `0xAARRGGBB` tint, packed opaque `0xFFRRGGBB` per-channel light, F32 shade, coverage mode and address mode. Tint/light/shade are supplied observations or explicit caller policies. No biome tint, ambient occlusion, light emission expansion or lightmap is inferred.

Nearest-neighbor `Clamp` clips each UV to `[0,1]` and maps endpoint 1 to the final texel. `Repeat` uses `value-floor(value)`; negative UVs repeat and integer endpoint 1 maps to texel zero. The full decoded image is sampled. Animated atlas frame selection, mipmaps, stitched atlas borders and filtering are not implemented here.

For each RGB channel the defined quantization is:

```text
floor(F32(F32(float(textureByte * tintByte * lightByte) / 65025) * shade))
alpha = floor(textureAlpha * tintAlpha / 255)
```

The integer product is at most `255³`, exactly representable in binary32. Subsequent division/multiplication follow Base F32 rounding. This quantization is **not** a claim about Java GPU sRGB, UNORM or lightmap behavior. Java-reference directional-light F32 values may be supplied without implying final-frame equivalence.

- `Opaque` always covers a valid intersection and outputs alpha 255, even if its input texture alpha is zero. The caller explicitly selected this policy.
- `Cutout{threshold}` covers when effective alpha is greater than or equal to the supplied threshold, then outputs alpha 255. No vanilla threshold is assumed.
- `Translucent` retains effective alpha. Zero-alpha fragments are skipped. Fragments strictly before the nearest covered solid fragment are composed from far to near over an opaque background. Each blend channel is `floor((source * alpha + target * (255-alpha)) / 255)`; output alpha is 255.

`Cull.Back` accepts positive ray/triangle determinant, using the supplied winding as the front. `Cull.NoCull` accepts either side. Scene construction must apply neighbor `cullface` pruning explicitly if desired; it is distinct from backface culling.

Depth comparison uses exact F32 values, without an equality epsilon. Lower depth wins. An exact depth tie prefers lower `Quad.order`, then lower input-list index. This key also defines translucent order and solid/translucent ties: a translucent fragment with an earlier key lies in front; a later key is occluded. Duplicate order values remain deterministic for a fixed input list. Intersections on the shared diagonal contribute at most one fragment for a quad; the first triangle wins an exact triangle-depth tie. Separate coincident quads remain separate layers by explicit input.

The CPU path separates opaque/cutout quads from translucent quads once per frame. It builds a midpoint spatial hierarchy for the opaque/cutout list, splitting on the longest extent, with at most ten levels and six-quads as the leaf target. An unsplittable set stays in a leaf. A ray visits only spatial nodes whose expanded F32 box passes the slab test. Padding is explicitly `0.002 + 0.00001*(maxAbsBoundsCoordinate + maxAbsCameraCoordinate)`; the ray/triangle arithmetic remains binary32. This padding is an engineering policy, not a formally proved error bound for every ill-conditioned triangle within the input domain. `render_flat` retains the same materials and pixel algorithm with a flat opaque/cutout scan for differential verification or caller-selected fallback.

Only translucent hits need sorting. Sorting is a bounded per-pixel insertion list with at most 64 candidates; opaque pixels are never generally sorted. Tests compare accelerated and flat output to the independent pixel oracle, including shared diagonals and quarter-turn geometry. This is not a scaling or response-time guarantee for arbitrary 4096-quad scenes or large loaded worlds.

## Reproduce

```sh
/Users/chuah/.bend/bin/bend src/mesh_render.bend --verdict
python3 tools/test_mesh_render.py
python3 tools/test_mesh_render.py --flat
```

The orchestrator selects the installed workspace Python with NumPy/Pillow. It generates an ignored compact raw-bit fixture file and a small names/material adapter, builds the window-free driver with the pinned Bend compiler, and sets `BEND_MINECRAFT_LAUNCH_MODE=hidden`. Checked Bend test code reads the exact F32 words; no fixture decimal conversion is involved. The driver does not open a window. `platform_build.py` deliberately rejects this driver because it has no reachable Base window implementation to verify or transform; no change to that adapter is needed. Automated clients that open windows continue to require the hidden adapter.

The driver independently reads back actual Bend-produced pixels through `R.pixels_of` and PPM output; a checksum forces every pixel before recording elapsed milliseconds. The oracle checks both the complete RGB bytes and an independently computed RGBA CRC, including output alpha 255. Timings include rendering, image readback and pure CRC, with millisecond clock resolution. PPM file writing occurs after the elapsed-time sample.

The test consumes `reference/model_semantics.json` from the actual pinned Java CPU baker. Its 110 variants/844 quads include unrotated, mirrored, all quarter-turn cube/UV-lock cases, slabs, stairs, fences, grass and glass. Original raw F32 vertex and UV bits are injected through an exact word cast; no decimal round trip or reconstructed cube UVs replace the reference geometry. Actual texture bytes come from the installed pinned JAR. See `MODEL_REFERENCE.md` for the controlled normalized-atlas boundary and the separately executed reference provenance.

An alternative double-precision plane/Gram-barycentric oracle checks 4220 native rays: two triangle interiors, the shared diagonal, the culled back and an outside point for each actual Java quad. An independent vectorized binary32 pixel oracle checks every RGB output byte. Synthetic scenes isolate address modes, integer alpha blending, tint/light quantization, equal-depth and duplicate-order policies, degenerate triangles, cutout coverage, clipping and culling. Rejected scenes are followed by a successful render using the returned assets. Results and source fingerprints are recorded in `evidence/mesh-render-native.json` and `evidence/mesh-render-flat.json`; generated fixture source, logs and image artifacts stay ignored under `build/`.

Grass fixtures explicitly supply tint `0xFF78B44A`, white per-channel light, cutout threshold 128 and a lower order for coplanar cutout overlays than for their opaque base. This is a tested caller policy, not a measured vanilla biome tint, cutoff or GPU draw-order rule. The practical fixture contains 36 floor blocks plus a slab, regular and inner rotated stairs, fence post/side, grass layers and glass: 280 quads total.

The final recorded native runs check **225771 complete RGB pixels and RGBA CRCs per path**, 4220 alternative-oracle rays, ten analytical alpha/color center samples, and fourteen rejected scenes followed by successful asset recovery. Rectangular 31×17 and minimal 4×7 frames also verify aspect ratio and image-tree padding. Accelerated and flat paths have identical image hashes for every case and identical raw-bit input fingerprints. The maximum ray distance/UV difference against the alternative plane oracle is `3.5762788286319847e-8`.

| Final 280-quad fixture | Spatial CPU, including readback/CRC | Flat CPU, including readback/CRC |
| --- | ---: | ---: |
| 64×64, four samples | 8–9 ms | 122–128 ms |
| 128×128, four samples | 33–35 ms | 406–622 ms |

The final accelerated empty 128×128 samples take 8 ms, providing context for the readback/checksum overhead. Earlier runs during different concurrent host workloads measured 50–54 ms for the practical scene and 10–12 ms for empty frames. These are observed millisecond samples, not controlled Minecraft comparative benchmarks or a guaranteed frame budget. The final native build takes 14.5 seconds and the complete native test process takes 1.8 seconds on this run; reference pixel computation is outside those native timings.

`evidence/mesh-render-baseline.json` retains the first measured flat implementation before spatial rejection, with its original source and fixture fingerprints. It is historical evidence: that first intermediate source is superseded, and its earlier grass tie policy differs from the final fixture policy. Use the current `--flat` command and `evidence/mesh-render-flat.json` for a reproducible comparison against the final accelerated implementation and identical material inputs.

Remaining dependencies include Bend production model baking, actual world mesh selection, weighted/position RNG, neighbor culling, tint/light/AO, pack selection/reloads, animation/mipmaps/filtering, production atlas behavior, Java raster/transparency equivalence and final-frame reference measurements. A supplied Java bake or matching custom CPU pixel oracle does not establish those behaviors.
