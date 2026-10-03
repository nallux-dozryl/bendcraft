# Pinned Java 26.3 texture and model inputs

Confidence is high for the verified PNG resources, two independent pixel decoders, and the selected raw JSON definitions. [The reference](../reference/render_assets.json) inventories every PNG in the installed, hash-pinned 26.3 client jar and the immediate renderer model dependencies. It does not establish Java model-bake, texture-atlas, shader, lighting, or render fidelity.

The client jar SHA-256 is `4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d`. Every run verifies that hash against the pinned release reference before reading any resources. Every PNG has its original-byte size/hash, dimensions, depth/color type, chunk order/lengths, checked CRCs, IDAT count/size, palette/transparency properties, decoded RGBA hash, filter histogram, alpha summary, and corresponding `.png.mcmeta` reference when present. No PNG bytes or decoded pixel arrays are committed.

## Independent pixel oracle

All **3,965 PNGs** decode successfully through both Pillow 12.1.1 and a separate Python standard-library PNG decoder. Their complete RGBA byte arrays agree for every image. There are **zero unsupported images, decode errors, or decoder disagreements**. The decoder reads PNG chunks, checks CRCs, inflates the concatenated IDAT stream with zlib, reverses filters 0–4, expands packed grayscale/indexed samples, and applies grayscale/RGB/palette `tRNS` semantics. It does not call Pillow for its expected pixels.

The canonical pixel representation is row-major, top-to-bottom, left-to-right, straight unpremultiplied RGBA8. It contains 37,709,164 bytes over the full inventory. There is no tint, gamma/ICC transform, atlas placement, animation-frame selection, mipmap, or sampling operation. These are PNG sample expectations for loader comparisons, not an observation of Java's `NativeImage` or GPU upload layout.

| PNG color type | Bit depth | Files |
| --- | ---: | ---: |
| Grayscale (0) | 1 | 6 |
| Grayscale (0) | 2 | 5 |
| Grayscale (0) | 4 | 1 |
| Grayscale (0) | 8 | 176 |
| Indexed (3) | 1 | 15 |
| Indexed (3) | 2 | 116 |
| Indexed (3) | 4 | 737 |
| Indexed (3) | 8 | 1,828 |
| RGB (2) | 8 | 133 |
| Grayscale with alpha (4) | 8 | 401 |
| RGBA (6) | 8 | 547 |

All images are noninterlaced, use standard PNG compression/filter methods, and have exactly one IDAT. Only `IHDR`, `PLTE`, `tRNS`, `IDAT`, and `IEND` chunks occur; no trailing bytes occur. `PLTE` appears in all 2,696 indexed images. `tRNS` appears in 2,102 images: 1,966 indexed, 128 grayscale, and eight RGB. Partial alpha occurs in 236 decoded images. Observed scanline counts are filter 0: 107,179; filter 1: 3,687; filter 2: 7,013; filter 3: 1,438; filter 4: 5,417. The largest width and height are both 1,024.

There are 1,300 block PNGs. Other groups include 831 item, 743 entity, 563 GUI, and 300 particle PNGs; the complete group counts are in the fixture. The inventory includes 218 `.png.mcmeta` references, of which 63 have an animation section. Animation JSON is preserved with its source hash; animated PNG strips are decoded in full. The probe does not interpret Java's animation scheduling, default frame dimensions, interpolation, or runtime resource-reload behavior.

## Immediate texture fixtures

The renderer's requested stone/dirt/oak/glass/grass/snow textures all have dimensions 16×16. Their full RGBA hashes are below. The eight immediate textures additionally have 16 row hashes in the JSON for locating decoder disagreement without retaining pixels.

| Texture stem under `assets/minecraft/textures/block/` | Depth/type | RGBA SHA-256 |
| --- | --- | --- |
| `stone` | 8 / grayscale | `057ffefa8bfcd516c6f7828cdf33271f15a5fd429b127e8caa348d50a0787304` |
| `dirt` | 4 / indexed | `327b802852d3662bb8bded6acd1cfbd559be990d521d2609ec1a91de6f27b4c9` |
| `oak_planks` | 8 / indexed | `6138b0af077708bac68849ad2ea90ae403cdd4e8976d6cfddd13ccba7ad0c783` |
| `glass` | 8 / RGBA | `1a887f8f1ec788c7ad4b796e37da862440c57568a2dca643b10dafa09779178a` |
| `grass_block_top` | 8 / grayscale | `31bb5d5d3c5516aadfd1fd5c605fa46252c0f0612091d753c0621ca6890549fd` |
| `grass_block_side` | 8 / indexed | `62c47cebea3514034a031ca1199a2ce0dfcedf4be0d3d669f0067087ffe95419` |
| `grass_block_side_overlay` | 8 / grayscale | `acc365a4695b2b4973f49f13bc846da4a46b4e26d89c56ed6bbd9973971c096d` |
| `snow` | 2 / indexed | `c60d9c5c3afb01ea1bc1350234a57e44ce7306c333aec4c5f93bf0a575f845d3` |

Stone and dirt use filter 0 throughout. Oak planks exercises filters 0, 1, and 3. The grass overlay is grayscale with a two-byte `tRNS` value `0000`: raw grayscale sample zero becomes transparent, while the other samples are opaque. Glass stores alpha directly. Grass top and side are fully opaque. The snowy-grass model also depends on `grass_block_snow.png`, whose full RGBA hash is `42ded5447acafd562ccf26414d873410e6df3cb63156076c8a565f62d43ae7a7`.

## Selected model dependencies

Five exact blockstate definitions are retained: stone, dirt, oak planks, grass block, and glass. They lead to seven concrete models, 13 model source files including parents, and eight texture dependencies. Every source JSON has its raw-resource hash. `selected_models.model_sources` retains the original parsed JSON. `data_derived_models` separately records texture/element inheritance, parent chains, alias traversal, element source, face definitions, explicit UV/tint markers, terminal texture definitions, and resource paths.

This is a data-derived interpretation. No Java model loader or bake executes. Abstract parent texture variables remain explicitly unbound when viewed without a child; all faces in the seven concrete blockstate-referenced models resolve to existing PNG resources. Missing source UVs remain marked `absent_in_source_java_default_not_executed`. Raw source transforms, cull faces, explicit rotations/tints and model flags are retained; their runtime application is not inferred.

- Stone's empty-property variant is an array containing stone, stone mirrored, stone rotated 180°, and stone mirrored rotated 180°. The mirrored parent explicitly uses `[16,0,0,16]` UVs for every face. The ordinary cube parent omits UV arrays. Therefore a single fixed cube orientation does not verify the variant/bake behavior.
- Dirt declares four rotations, 0/90/180/270°. Oak planks declares one model. Both inherit `cube_all`, whose face texture aliases lead to the child's `all` texture.
- Grass `snowy=false` declares four rotations. Its model has one six-face cube plus four coplanar side-overlay faces. The upper base face and all four overlay faces declare `tintindex: 0`; the side base and bottom do not. All ten faces have explicit `[0,0,16,16]` UVs. A plain cube with one grass texture would omit both layering and tint.
- Grass `snowy=true` references `grass_block_snow`, inheriting `cube_bottom_top` with dirt bottom, snowy-grass side, and grass-block-top texture. Those exact source definitions are retained without inventing a snow/tint substitution.
- Glass uses `cube_all`, but its `all` entry is the object `{"force_translucent":true,"sprite":"minecraft:block/glass"}`. The resolver preserves this object and its aliases. Treating every terminal texture entry as a string would misread this release. The flag's actual render-pass behavior remains unmeasured.

Parent/texture inheritance here covers only the selected known JSON fields. It is not a general model codec, merge/reload engine, weighted-variant RNG, block color provider, UV-lock transform, culling algorithm, or bake implementation.

## Reproduction and integrity

Run from `minecraft/`:

```sh
python3 tools/reference_render_probe.py
python3 tools/reference_render_probe.py --verify-existing
python3 tools/reference_render_probe.py --selftest
```

Extraction needs Python with Pillow and reads only the pinned client jar and release reference. It writes reference metadata and evidence; it launches no native client and changes no focus. PNG bytes/pixels are held in memory. The verifier rereads the complete jar, independently decodes every PNG again, rebuilds the selected dependency graph, and compares the entire observation with the saved reference. Counts, unique paths, chunk topology, byte lengths, two-decoder hashes and required model texture paths also have explicit checks.

The selftest performs two fresh full observation runs and compares all records/model inputs exactly. It rejects five deliberate corruptions: a wrong pixel hash before checksum resealing; the same wrong hashes for both decoders after resealing, rejected against fresh pixels; an altered glass sprite after resealing, rejected against the actual model JSON; a damaged IDAT rejected by PNG CRC; and the same damage after recomputing CRC, rejected by the independent zlib checksum. Corruption uses in-memory copies and never modifies the installed jar.

Evidence is [extraction](../evidence/reference-render-probe.json), [fresh resource validation](../evidence/reference-render-validation.json), and [reproduction/corruption checks](../evidence/reference-render-selftest.json). The canonical observation SHA-256 is `a712177de30b67117e5d1164d97d0030ab19769d9c9eb5ef81c7f8281c685ced`; the evidence records the complete file fingerprint. Unsupported reference formats/errors have explicit per-resource statuses and a validation list; that list is empty for this pinned inventory. The reference decoder intentionally excludes interlaced PNG, 16-bit samples, unknown critical chunks, and APNG frame decoding, none of which occur here.
