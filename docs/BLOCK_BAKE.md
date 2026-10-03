# Pinned 26.3 CPU block baking

`src/block_bake.bend` computes geometry from `BlockModel.Resolved`. The test adapter decodes and resolves original model JSON in Bend before baking; Java quads are comparison outputs, never a production geometry table. Final verification matched 345 supported bake cases and 2,232 quads, including all 110 recorded official bakes and all 844 official quads. One recorded nonzero Euler case returned the declared unsupported result. Eleven explicit error cases passed; fresh Java and native runs reproduced twice, and six altered-observation cases were rejected. Confidence is high for this executed fixture domain. This is a CPU model-baking substrate, not a claim of Java frame or gameplay parity.

## API and caller inputs

`bake(resolved, State{x,y,z,uvlock}, Context{sprites,missing})` returns `Result<Error,List<Baked>>`. Each state angle is a U32 containing 0, 90, 180, or 270 degrees. All three axes and their composed rotations are supported.

`sprites` maps normalized sprite identifiers to `Sprite{slot,u0,v0,u1,v1,layer,animated}`. The atlas rectangle is F32; all four coordinates must be finite. `layer` is explicitly `Solid`, `Cutout`, or `Translucent`. The caller owns sprite loading, classification, animation, atlas layout, and texture slots. No alpha scan, atlas stitch, animation tick, or resource I/O occurs in the baker. A material's `force_translucent` sets its resulting layer to `Translucent`.

`missing=None` produces `MissingMaterial` for absent sprite IDs or unresolved texture slots. `missing=Some{Sprite}` supplies the explicit fallback record and reports sprite ID `minecraft:missingno`, matching the controlled Java oracle. The caller must supply the corresponding texture asset for the fallback slot.

`Baked` preserves four `MeshRender.Vertex` values, actual baked direction, declared cull group after the state transform, sprite ID/slot, Java tint-index bits, light emission, shade-direction override, layer, force-translucent and animated flags, and default/nether directional factors. Tint index `4294967295` encodes Java `-1`. Cull groups do not determine neighbor visibility, and element rotation does not rotate the declared cull group. `flags(baked)` uses the Java material flag encoding: translucent layer is bit 0 and animated sprite is bit 1.

`mesh(baked, Appearance{tint,light,address,cull,nether,cutout_threshold}, order)` produces a `MeshRender.Quad`. The caller supplies tint color, lighting, texture address/cutout policy, raster culling, and draw order. The adapter uses the observed directional factors, including the new model shade-direction override. Emission is retained as metadata; it does not invent world light.

## Exact numeric domain

The module implements default and explicit face UVs, face UV rotations, default cube/mirrored-cube orientation, F32 atlas mapping, vertex winding swaps, transformed cull groups, and state quarter turns with UV lock. Face directions follow Java EnumMap order (down/up/north/south/west/east). Production JSON accepts exact lower-case face keys; uppercase keys are rejected. It follows the production `FaceBakery`, `BlockMath`, `CuboidRotation`, and pinned JOML operation order. In 26.3 face UV coordinates are divided by 16 and mapped directly into the explicit atlas rectangle; this path has no assumed legacy UV shrink.

UV lock uses the quaternion face bases, composition, and affine inverse. The pinned Java probe reports `FASTMATH=false`, `USE_MATH_FMA=false`, and `HAS_Math_fma=false`; matrix products therefore use separate F32 multiplication and addition with the observed nesting. The fixed basis quaternion scalar and finite sine/cosine table are measured primitive math inputs, not stored expected vertices.

Single-axis element angles supported by the measured scalar table are `-90`, `-45`, `-22.5`, `0` (including negative zero), `13.5`, `22.5`, `45`, and `90` degrees, on X/Y/Z, with or without rescale. Other single-axis angles return `Unsupported{"ElementAngle"}`. Euler rotations are supported only when all components compare equal to zero; nonzero Euler rotations return `Unsupported{"ElementEuler"}`. Arbitrary transcendental approximations are not silently accepted.

Finite geometry/UV checks surface `Invalid` errors. This is an explicit runtime domain restriction; Java's acceptance of nonfinite UV values is not claimed equivalent. Invalid state turns and malformed typed face rotations are rejected. Degenerate faces are omitted when the production normalized-normal calculation yields no direction. Winding searches and swaps consume distinct vertices in order; failure is surfaced as `CannotFindWindingVertex`.

## Verification and reproducibility

Run from the `minecraft` directory:

```sh
python3 tools/test_block_bake.py --selftest
```

The command checks the pure source and adapter, attempts bounded kernel verdicts, builds the native Bend binary, runs actual installed Java production baking in an ignored directory, repeats fresh Java and native runs, and compares every vertex position/UV as raw F32 hexadecimal bits plus cull grouping and material metadata. It also rejects changed position, UV, direction, layer, tint, and quad-count observations and checks explicit runtime error surfaces. `--no-build --selftest` reruns the native/Java comparison against an already-built binary; it is not a source-build verification.

Pinned inputs come from `reference/model_semantics.json` (SHA256 `3cbe8aa7780f14c1b37159a885710b04680e3b6c4ffa4975b4d8297015f11e7e`) and the verified installed 26.3 client JAR and metadata. Original decimal tokens are retained in official model inputs. Controlled static sprites are normalized per image to the atlas rectangle `[0,1]`; transparency inputs are independently derived from the two-decoder PNG inventory. The Java oracle also uses this controlled normalized atlas and an explicit opaque magenta fallback. No sprite bytes are checked into Git.

The recorded official corpus includes 110 variant bakes and all 844 Java quads. Fresh probes add composed X/Y/Z quarter turns, UV lock, asymmetric bounds/UVs, X/Y/Z element rotations and rescale, signed zeros, reversed/degenerate bounds, missing textures, object textures/force translucency, and deterministic random finite inputs. Exact final counts, source hashes, primitive math observations, class hashes, unsupported cases, and validation outcomes are in `evidence/block-bake-tests.json` and `evidence/block-bake-math.json`.

Type checking and native equality do not establish a universal Java parity theorem. Both imported kernel-closure checks exceeded the bounded 60-second attempt, and remain inconclusive. Final native compilation exited successfully after 566.577 seconds with the complete 12-file Bend import closure unchanged; the actual build manifest is included in the evidence. Kernel validity is not inferred from compilation or native equality. The local structural identity-transform law is included in the typed adapter.

## Remaining coverage

Nonzero Euler rotations and unlisted single-axis angles remain explicit unsupported operations. Production atlas packing/mipmaps, dynamic animation, world tint, ambient occlusion, neighbor occlusion, light maps, and Java raster/frame output are outside this module's measured domain. Blockstate selection/weighting and resource ownership are separate modules. The full reimplementation goal remains open.
