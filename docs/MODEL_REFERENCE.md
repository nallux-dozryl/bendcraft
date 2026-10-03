# Pinned Java 26.3 model semantics reference

Confidence: **high for the executed inputs and controlled atlas boundary**. This is reference extraction, not a Bend implementation or a gameplay/rendering fidelity claim.

`reference/model_semantics.json` records actual production Java deserialization, parent and texture resolution, blockstate selection and CPU geometry baking. `tools/reference_model_probe.py` runs installed official named client classes with verified official libraries. Minecraft is not opened, a client instance is not created, and no GPU upload or rendering method is invoked.

## Reproduce and verify

From `minecraft/`:

```sh
python3 tools/reference_model_probe.py extract
python3 tools/reference_model_probe.py validate
python3 tools/reference_model_probe.py selftest
```

The launcher Java 25.0.1 runtime supplies both `java` and `javap`. The tool verifies the pinned client SHA-256, version JSON SHA-256, and installed library size/SHA-1 against that JSON. Its fixture additionally fingerprints the executable and every used library with SHA-256. Eighty installed library artifacts are used; 34 absent Linux/Windows native artifacts are explicitly listed and excluded on this macOS ARM64 machine. No download is needed.

Client SHA-256: `4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d`. Version JSON SHA-256: `9a7b39dae3b9c8d30006b650e357aae220629b7852fa0fc7221db7a8646bd5e4`. Oracle version: `java26.3-client-model-probe-v1`.

The JSON fingerprints 136 relevant official named class files, the combined `javap -p -c` output and the exact embedded Java harness. Raw Java inputs, source, observations, bytecode and diagnostic logs are ignored under `reference/cache/model-probe/`. No image, sprite or extracted asset bytes are committed.

`evidence/model-reference-probe.json` records extraction. `evidence/model-reference-validation.json` records validation against a fresh Java process. `evidence/model-reference-selftest.json` records two independently launched Java processes with identical canonical results, equality to the committed reference, and seven rejected corruptions. Corruptions include changed UV bits with and without a resealed checksum, a changed resource model with a resealed checksum, changed lighting with a resealed checksum, and forged harness/class/library fingerprints. A checksum alone is insufficient: validation compares fresh source, pinned resources and actual Java observations.

## Executed coverage and schema

| Observation | Count |
| --- | ---: |
| Official model JSON resources, including parents | 27 |
| Official blockstate JSON resources | 8 |
| Actual states in these block definitions | 124 |
| Variant geometry bakes | 110 |
| Quads from these variant bakes | 844 |
| Official variant bake errors | 0 |
| Additional model JSON cases | 107 |
| Model-case errors observed | 44 |
| Parent/texture graph cases | 7 |
| Simple selector cases | 12 |
| Multipart condition cases | 17 |
| Dispatcher/weighted cases | 25 |
| Hashed JSON/PNG resource inputs | 43 |

The official blocks are stone, dirt, oak planks, grass block, glass, oak stairs, oak slab and oak fence. All states of those blocks are enumerated after `SharedConstants.tryDetectVersion()` and `Bootstrap.bootStrap()`. All production model variants referenced by their JSON are baked. Additional stone and mirrored-stone bakes cover every X/Y quarter-turn combination with UV lock both false and true. The selected stairs exercise half/facing/shape rotation combinations; fences exercise multipart side conditions and UV lock. Synthetic model cases execute face rotations, tint, light emission, shade overrides, single-axis and Euler element rotations, and parser boundaries.

`inputs` preserves original model and blockstate JSON strings, source resource hashes and explicit synthetic fixture inputs. It does not replace decimal lexemes with independently computed binary floats. `observations` is entirely emitted by Java. Important lanes are:

- `parsed_official_models`: actual `CuboidModel` records and nested values.
- `resolved_official_models`: actual `ResolvedModel` parent links, top geometry, ambient occlusion, GUI lighting, display transforms and texture materials.
- `official_blockstates`: actual `BlockStateModelDispatcher` codec/instantiation results, model records, production predicates' matching numeric block-state IDs and selected multipart indices. Root dependency sets contain all model dependencies, not only active multipart parts; use the predicate matches/indices for active parts.
- `baked_variants`: input model/X/Y/Z/UV-lock settings, production transformation and per-face/inverse-face matrices, effective default/explicit face UVs, and `QuadCollection` groups keyed by cull direction or `unculled`.
- `parse_cases`, `graph_cases`, `selector_cases`, `condition_cases`, `dispatcher_cases`: accepted production values or exact observed exception class/message. Java logging behavior during discovery/instantiation is retained in ignored stdout logs; an `ok` codec/instantiation result does not imply no logged diagnostic.
- `cardinal_lighting_f32`: actual `CardinalLighting.DEFAULT` and `NETHER` values returned by `byFace`.

Each baked quad contains four positions, four packed UV values, direction, sprite identifier, tint index, shade direction override, light emission, actual material layer/flags, and the production `BlockModelLighter.getDirectionalBrightness` result for default and Nether cardinal-lighting inputs. Float values use lowercase eight-digit `Float.floatToRawIntBits` strings; packed UV uses unsigned 64-bit hexadecimal. `UVPair.unpackU/V` are invoked by Java. U occupies the high 32 bits and V the low 32 bits. JOML matrix arrays are column-major F32 values. Vertex order is the actual returned bake order, not reconstructed from a face equation. Array/quad ordering in these fixtures was stable across the two fresh processes; no general sorting or ordering law is asserted.

## Production paths and controlled inputs

The core measured paths are `CuboidModel.fromStream`, `TextureSlots.parseTextureMap` through that parser, `ModelDiscovery.resolve`, `ResolvedModel.findTop*`, `Variant.CODEC`, `BlockStateModelDispatcher.CODEC` and `instantiate`, `VariantSelector.predicate`, multipart `Condition.CODEC` and `instantiate`, `WeightedList.getRandom`, and `ResolvedModel.bakeTopGeometry` → `UnbakedCuboidGeometry.bake` → `FaceBakery.bakeQuad`. The full production baker creates `BakedQuad.MaterialInfo` through the actual `MaterialBaker`, uses the decoded sprite's transparency, and groups culled/unculled quads through production `QuadCollection` construction.

The supplied `ModelBaker.Interner` returns its inputs; identity deduplication is not measured. Its material resolver is an actual `MaterialBaker` supplied with controlled `SpriteLoader.Preparations`. Every real referenced sprite is read directly from the pinned JAR using production `NativeImage.read` and `SpriteContents`. For each sprite, the atlas width/height equals its image width/height, placement is `(0,0)`, and padding is zero, producing normalized sprite-local UVs `(0,0)`–`(1,1)`. These regions intentionally overlap. This is a controlled input for geometry/material classification, **not** a valid stitched production atlas.

The resolver's missing material uses an explicitly generated opaque magenta 16×16 sprite. `ModelDiscovery` is supplied an explicitly parsed empty `{}` model as its missing-parent fallback. Therefore parent cycle/filtering and fallback behavior is observed, but production missing-model geometry and missing-sprite appearance are not claimed. Synthetic faces with missing texture slots can bake against that controlled replacement.

Reflective access is limited to official `TextureAtlasSprite` construction, `FaceBakery.defaultFaceUV`, `BlockModelLighter.getDirectionalBrightness`, private record accessors and multipart visual-equality indices. Reflection does not replace arithmetic or parsing with a reimplementation. Java's installed LWJGL native PNG/memory support and JOML execute on the reference host; they are not a Bend runtime or proof dependency.

## Measured cube UV and brightness contracts

For the unrotated full cube with ordinary default UVs, local coordinates `x,y,z` are normalized to `[0,1]`:

| Face | Sprite-local U | Sprite-local V | Default cardinal brightness |
| --- | --- | --- | --- |
| West | `z` | `1-y` | F32 `0.6` / `3f19999a` |
| East | `1-z` | `1-y` | F32 `0.6` / `3f19999a` |
| Down | `x` | `1-z` | F32 `0.5` / `3f000000` |
| Up | `x` | `z` | F32 `1` / `3f800000` |
| North | `1-x` | `1-y` | F32 `0.8` / `3f4ccccd` |
| South | `x` | `1-y` | F32 `0.8` / `3f4ccccd` |

The equations are a human-readable interpretation of six actual Java vertex/UV observations. The raw quads are the authority. `cube_mirrored` has actual explicit `[16,0,0,16]` UVs on all faces; the variant fixtures preserve its reversed U mapping and rotated/UV-locked behavior. Normalized atlas UVs are not texture sampling, wrap or filtering fixtures.

`CardinalLighting.NETHER` returns down/up F32 `0.9` / `3f666666` and the same side values as default. `BlockModelLighter.getDirectionalBrightness` chooses `materialInfo.shadeDirectionOverride` when present, otherwise the supplied quad direction, then calls `CardinalLighting.byFace`. Assigning these floats to integer RGB multiplication or measuring only a custom rendered scene does not establish a vanilla final-frame match.

Glass's actual object texture has `sprite` plus `force_translucent:true`, and its baked material layer is `TRANSLUCENT` under the controlled atlas. Stone/dirt/oak opaque faces produce `SOLID`. Grass overlay transparency produces `CUTOUT`; tint indices are recorded but biome/world tint application is not run.

## Selected parser and resolution findings

These are executed 26.3 facts for the recorded cases, not a full schema specification:

- Missing geometry, ambient occlusion, GUI light and display fields remain nullable in the unbaked record. `ResolvedModel` applies defaults/inheritance. Explicit `elements:[]` suppresses inherited elements; an absent `elements` field inherits geometry. The parent texture alias `side:#all` resolves to a child's overridden `all` value.
- Parent cycles and self-parent models are removed from the resolved map rather than causing an exception in the tested discovery graphs. Missing parents resolve through the supplied fallback. Texture alias cycles/missing aliases produce unresolved materials and diagnostics. Path identifiers containing `../` or a leading `/` were accepted by identifier parsing; this does not authorize filesystem traversal or establish resource access. Uppercase/invalid namespace characters were rejected.
- Unknown members were ignored in the exercised model/texture/variant cases. An empty parent string becomes no parent. Duplicate model `parent` keys select the last value in the exercised Gson parse. A null/top-level array/malformed JSON was rejected. Some Gson helper fields coerce primitive values: `ambientocclusion:0` becomes false, `ambientocclusion:"false"` becomes false, numeric face `texture:1` becomes `"1"`, and `light_emission:1.9` becomes integer 1. Material object `force_translucent` and variant `uvlock` codec inputs require actual booleans.
- F32 endpoint extents include `-16` and `32`; the immediately tested out-of-range finite endpoints fail. Face UVs require four values; face UV arrays are not endpoint-clamped. Invalid cull-face strings become null in the tested case. Face quarter rotations accept wrapping values `360`→R0 and `-90`→R270; `45` fails.
- Unlike older model assumptions, the tested 26.3 element rotations accept arbitrary angles including `13.5` and `90`, plus Euler `x,y,z`. Origin is mandatory. Missing Euler components default to zero in the exercised input. Raw origin, transformation and rescale behavior are measured through the production parser/baker. The legacy element `shade:false` member is ignored in the exercised case; `shade_direction_override` is the measured current field.
- Display translation is divided by 16 and clamped to `[-5,5]`, and scale is clamped to `[-4,4]` in the exercised case. The fixture preserves F32 rounding and left-hand transform fallback outcomes rather than imposing a Python interpretation.
- Simple variant selectors and multipart terms differ. A simple `facing=north|south` selector fails; repeated `facing=north,facing=south` uses the last value; `half=top,` is accepted in the recorded case. Multipart `true|false`, individual `!true`, nested AND/OR, boolean JSON values and empty OR/AND lists are measured. Empty OR matches zero fence states; empty AND matches all 32. The recorded `!true|false` is interpreted per term, and matches 16 states; it is not negation of the whole disjunction.
- A single variant object ignores the tested `weight` member, including zero/negative values. Weighted variant arrays require positive weights; sum overflow above `2147483647` is rejected. A valid weighted-array fixture also records 16 actual `WeightedList.getRandom` results for each seed 0, 42 and -1. These are isolated selection calls; block-position RNG seeding and renderer random-consumption order are outside this task.

## Decimal-to-F32 requirements

The original JSON lexemes and production F32 results include:

| JSON decimal | Actual F32 bits |
| --- | --- |
| `0.1` | `3dcccccd` |
| `-0.0` | `80000000` |
| `1e-45` | `00000001` |
| `1.000000059604644775390625` | `3f800000` |
| `1.0000000596046449` | `3f800001` |
| `1e40` in a face UV | `7f800000` |

This establishes concrete subnormal, signed-zero, halfway rounding and infinity fixtures. Integer-only JSON handling or decimal conversion using host-independent integer shortcuts cannot silently supply these semantics. This task supplies reference expectations; it does not implement decimal conversion in Bend.

## Unmeasured behavior

Production atlas stitching, atlas sources and pack precedence, animation metadata/mipmaps, UV padding/filtering, GPU uploads, rasterization, transparency sorting/OIT, shader execution, biome tint, lightmap generation, neighbor/world occlusion and AO, item display rendering, normal transformation for lighting, block-offset/position random seeding, client reload scheduling and final frames remain unmeasured. The data-derived predecessor `reference/render_assets.json` continues to be a PNG inventory/selected dependency interpretation; this file adds a separate actual Java execution layer. Neither reference inventory counts as implementing a renderer or model loader.
