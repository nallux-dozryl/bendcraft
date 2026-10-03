# Bounded block resource interpretation

`src/block_resources.bend` connects the archive reader, strict UTF-8 decoding,
resource JSON profile, typed block models, PNG decoder, and renderer assets. All
resource interpretation and pixel construction execute in Bend. Archive effects
read the supplied ZIP/JAR and close it before returning. No resource is extracted
to a host path.

```bend
BR.load(path, roots, BR.StaticNormalized{layers}, BR.defaults())
  # IO(Result<&2,&1,BR.Error,BR.Loaded>)
BR.split(loaded) # R.Assets & BR.Catalog
BR.model(catalog, "minecraft:block/stone")
  # Result<&2,&2,BR.Error,B.Resolved>
```

`Loaded` has one affine `R.Assets` owner and an immutable `Catalog`. The catalog
contains canonical requested roots, decoded source models, effective resolved
models for the entire parent closure, ordered sprite information, `K.Context`,
and measured resource usage. `BR.model` accepts the same identifier normalization
as the model parser and reports an unloaded model explicitly.

The caller supplies a `Map<&2,K.Layer>` keyed by sprite resource IDs. For the
three fixture materials, a caller can map `minecraft:block/stone`,
`minecraft:block/dirt`, and `minecraft:block/oak_planks` to `K.Solid{}`. This is a
default caller mapping for three fixture materials. It is not a universal native
layer rule inferred from PNG alpha. The baker preserves model material flags and
upgrades an explicit `force_translucent` material as documented by its API.

The static policy admits each entire decoded image as one sprite with explicit
UV bounds `(0,0,1,1)`, `animated=False`, and no missing-texture fallback.
Rectangular images are allowed under that policy; their dimensions do not imply
frame selection. Absent or empty-object `.png.mcmeta` is accepted and recorded.
Animation, texture metadata, unknown metadata sections, and a non-object root
are rejected. Texture filtering, animation interpolation, atlas stitching,
resource-pack priorities, vanilla fallback selection, and world appearance are
future dependencies. This loader does not claim Java final-frame equivalence.
In the actual pinned JAR, `glass.png.mcmeta` specifies
`texture.mipmap_strategy = "mean"`. That image currently rejects with
`UnsupportedMetadata`, even when the caller supplies a translucent layer. The
suite treats this as a verified policy boundary rather than silently ignoring
the metadata.

## Closure, ordering, and limits

Requested IDs and layer keys use the exact observed block-model identifier rules:
absent or empty namespace becomes `minecraft`, namespace permits lowercase
ASCII letters/digits/`_.-`, and path additionally permits `/`. Empty paths,
leading slashes, and `../` remain accepted spellings. Their meaning here is an
exact ZIP entry name, constructed as `assets/{namespace}/models/{path}.json` or
`assets/{namespace}/textures/{path}.png`. There is no host-path normalization or
directory-name fallback. Archive duplicate entry lookup follows the validated
last-record rule.

Roots are deduplicated and sorted. Parent closure is visited depth first with
cycle/depth checks, a model count bound, and finite work fuel. Missing requested
models or parents reject the whole load. Every decoded closure model is resolved
with the existing typed model resolver. Texture references are collected from
requested effective models, including merged texture slots and element faces.
Abstract parents can retain unresolved slots until a child supplies them; their
standalone materials are not spuriously loaded. Unbound or cyclic references in
a requested model reject. Sprite IDs are deduplicated and sorted, and zero-based
slots match the ordered `R.Assets.textures` list. Two policy keys normalizing to
one ID reject instead of choosing an arbitrary layer.

A requested effective model can reference at most 1,024 distinct normalized
texture slots. The check happens before following aliases. This additional work
bound matters because a large alias graph can resolve to just one sprite and
otherwise evade a sprite-count limit. It is an explicit static-loader policy,
not a measured vanilla model limit.

Default limits are 256 models, parent depth 32, 1 MiB per text entry, 8 MiB per
PNG entry, 16 MiB aggregate decoded resource bytes, 256 sprites, 1,048,576
aggregate decoded pixels and aggregate padded Image backing pixels, side at most
256, and JSON depth 255. Declared entry size is
checked before archive decompression. PNG dimensions and remaining pixel budget
are checked before constructing an image. Metadata bytes count toward text and
aggregate bytes. Model and sprite counts describe actually loaded resources.
`Usage.pixels` reports the actual decoded count; the backing-pixel admission
counter is internal. A skinny image can therefore fail `ImageBudget` even when
its decoded pixel count fits, because the quadtree covers a square whose side is
the next power of two of the larger dimension.

The supported limit configuration itself is bounded: at most 4,096 models or
sprites, parent/JSON depth 255, 4 MiB text, 32 MiB PNG, 64 MiB aggregate bytes,
1,048,576 pixels, and side 1–1,024. Zero count/byte/pixel budgets are valid
configurations that reject nonempty requests. Archive indexing retains its own
existing finite limits. These bounds are implementation policies, not vanilla
resource-pack acceptance limits.

UTF-8 rejects invalid leading/continuation bytes, incomplete sequences, overlong
forms, surrogate scalars, and values above U+10FFFF. Resource JSON then uses the
independently measured strict Gson profile in `resource_json.bend`, including
initial BOM handling, duplicate object keys retaining the last value, and first
root completion. Those parser semantics are deliberate and are distinct from
the application protocol JSON parser.

The image constructor writes row-major PNG pixels into an owned indexed array
once, then builds the renderer's quadtree through bounded array reads. Padding
outside the actual image dimensions is zero. This avoids a full source-list scan
for each texel while preserving straight-alpha `0xAARRGGBB` pixels.

## Verification

Run `python3 tools/test_block_resources.py`. The script uses the pinned Bend
compiler to check the driver, check the resource module with the proven kernel,
and build a window-free native CPU test. The hidden launch environment remains
set. No window/input adapter is needed; the platform window builder intentionally
requires an actual window implementation and is not used for this CPU-only
driver.

Kernel checking has a 60-second bound and records a timeout as inconclusive;
native success never substitutes for that verdict. `--prepare-only` creates only
the independent fixtures. `--skip-kernel` and `--reuse-build` are explicit options
for a lead-scheduled native verification run or an already-built unchanged test
driver. Kernel status remains separately recorded in the evidence.

The independent model oracle is the executed official 26.3
`CuboidModel`/`ResolvedModel` reference in `reference/model_semantics.json`.
Decoded and inherited fields, source texture aliases/material flags, display
transforms, and raw F32 values are compared. Pillow independently decodes each
loaded PNG; every native `Image` texel is read back and compared as RGBA. The
suite also exercises malformed/missing resources, parent and texture cycles,
strict UTF-8, metadata rejection, exact ZIP identifier spelling, all resource
budgets, rectangular images, and deterministic repeated loads. An OS `lsof`
observation after the load returns checks that the archive is closed on success
and on failures in model, PNG, and metadata interpretation.

The generated summary is `evidence/block-resources-native.json`; official assets,
binary fixtures, and full native outputs remain in ignored build files or in the
installed pinned JAR. See `MODEL_REFERENCE.md`, `BLOCK_MODEL.md`, `PNG.md`,
`MESH_RENDER.md`, and `ARCHIVE.md` for the independently verified dependencies
and their boundaries. This is resource-to-asset integration evidence. It does not
establish a stitched atlas, blockstate selection, world lighting, live world mesh
production, or complete client/game parity.

The recorded native run passes 63 cases: 18 admitted loads and 45 expected
rejections. The three-material scene loads six source/effective models, three
16×16 sprites, 2,245 model bytes, and 543 PNG bytes. The supported noncube/grass
case loads twelve models and five 16×16 sprites. Across admitted cases, 5,026
texels are compared in each of two identical native runs. Six `lsof` checkpoints
confirm archive closure after success and after model-cycle, JSON, PNG CRC,
metadata, and archive-entry CRC failures. Kernel status is recorded separately.

Native compilation was expensive on this host: 658.193 seconds from the recorded
compiler launch to the binary's last modification, and a read-only Apple
`sample` reported a physical footprint of `11.7G`. The artifact is 3,657,736
bytes. `evidence/block-resources-build-profile.json` preserves these observations
and the sample hash; they describe build cost, not runtime resource loading or
game performance. The production module and Bend test source remained frozen
while a Python-only glass expectation was corrected against the same validated
native artifact. Future required harness changes should narrow imported test
helpers and large captured contexts before another expensive compilation.
