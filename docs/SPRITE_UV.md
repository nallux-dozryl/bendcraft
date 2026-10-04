# Sprite placement and normalized UVs for Java 26.3

`src/sprite_uv.bend` implements the scalar constructor and interpolation contract observed in the pinned official `TextureAtlasSprite`. The source and narrow driver pass ordinary Bend checking. Extraction, fresh official Java validation, and the two-run reference integrity suite pass. The unchanged installed native executable passes the complete 249-case corpus twice, including 4,700 actual receiver interpolation query pairs. One full unchanged production-module kernel verdict also passes. Confidence is high within that measured scalar contract; the atlas/frame integration described below remains unimplemented.

This is a placement-to-UV prerequisite. It does not construct atlas pixels, choose animation frames, generate mipmaps, upload textures, or execute a GPU frame. Existing `StaticNormalized` resource loading and `BlockBake` sprite contexts remain unchanged.

## Typed interface

```text
Input Data {
  atlas_width, atlas_height, width, height, x, y, padding: U32
}
Mapping Data {
  input: Input;
  content_x, content_y: U32;
  u0, v0, u1, v1: F32
}
UV Data { u, v: F32 }
Corners Data { a, b, c, d: UV }
Error Data { code: String }

raw_mapping(Input) -> Mapping
derive(Input) -> Result<Error, Mapping>
get_u(Mapping, F32) -> F32
get_v(Mapping, F32) -> F32
map(Mapping, UV) -> UV
corners(Mapping) -> Corners
mapped_corners(Mapping) -> Corners
mapping_input(Mapping) -> Input
content_origin(Mapping) -> U32 & U32
```

All records are immutable Data. There is no image, file, allocation handle, or affine owner to recover. `Mapping.input` retains the original seven raw integer words. Errors contain the explicit caller-policy code and do not claim to be Java exceptions.

`x,y` are the **padded region origin** supplied by the actual Stitcher callback. They are not the content origin. The constructor applies padding once, producing `content_x=x+padding` and `content_y=y+padding`. It preserves `x,y` for its own `getX/getY`; the Bend mapping retains them in `input`.

There is no `from_stitch` convenience wrapper in this checkpoint. A caller must retain an authoritative `Packed`/`Placement` pair, check completeness and bounds, and choose a placement from that packing before supplying its dimensions, callback coordinates and padding. A freely constructed `Input` cannot authenticate packing membership. In particular, `derive` must not be treated as proof that arbitrary coordinates came from the Stitcher.

## Exact receiver operations

The actual protected constructor is:

```text
TextureAtlasSprite(Identifier atlas, SpriteContents contents,
                   int atlasWidth, int atlasHeight,
                   int x, int y, int padding)
```

It reads the frame dimensions from `SpriteContents` and evaluates these expressions, with Java integer additions **before** conversion to float:

```text
u0 = (float)(x + padding) / (float)atlasWidth
u1 = (float)(x + padding + contents.width()) / (float)atlasWidth
v0 = (float)(y + padding) / (float)atlasHeight
v1 = (float)(y + padding + contents.height()) / (float)atlasHeight
```

`raw_mapping` accepts U32 two's-complement words, wraps these additions as Java `int`, converts the resulting signed integer to F32, then divides once as F32. It does not divide the addends separately, convert each addend before addition, or introduce F64 intermediate arithmetic. The positive admitted path remains below the integer-overflow boundary. The raw reference deliberately includes zero/negative divisors, negative frame dimensions, and overflowing integer sums, so those receiver observations remain distinct from usable atlas admission.

The interpolation methods take **normalized** coordinates:

```text
getU(t) = u0 + (u1 - u0) * t
getV(t) = v0 + (v1 - v0) * t
```

Each subtraction, multiplication and addition rounds separately to F32, following the pinned `fsub`, `fmul`, `fadd` bytecode. There is no clamp, division by 16, or shrink adjustment in these methods. Queries outside `[0,1]` extrapolate. Nonfinite queries follow the raw arithmetic receiver; admission does not silently replace or clamp them.

The actual `CuboidFace.getU/getV` performs the model rectangle conversion from sixteenth units to normalized coordinates before calling the sprite mapper. Its unrotated `UVs(0,0,16,16)`/`Quadrant.R0` order is `(0,0),(0,1),(1,1),(1,0)`. `mapped_corners` executes those four actual interpolation inputs in that order. `corners` returns the stored getter endpoints in the corresponding order.

These two corner helpers are intentionally distinct. For the actual odd, non-square `127×63` atlas fixture with frame `17×9`, origin `(7,11)` and padding 3, `getV(1)` differs by one F32 ULP from `getV1()`. Subtracting and adding can round differently from returning the stored endpoint. Using `v1` directly for a corner whose normalized V is one would therefore skip the measured interpolation operation for that fixture.

## No shrink API in the pinned release

The pinned `TextureAtlasSprite` and `UvMapping` declared-method inventories contain no shrink field accessor or method. Reflection finds no public method whose name contains `shrink`; the actual `FaceBakery` path calls `getU/getV` directly. The original class hashes, complete declared-method inventories and combined class bytecode hash are retained in the reference provenance. Ignored `reference/cache/sprite-uv/official-bytecode.txt` contains the inspected bytecode.

This module consequently exposes no invented `uvShrinkRatio`, zero-valued substitute, or formula copied from another release. Absence of that API does not prove an absence of every possible texture filtering artifact or adjustment elsewhere in the renderer.

## Explicit usable-layout admission

`derive` adds caller policy over the unchecked scalar receiver:

1. Atlas dimensions must be positive and no greater than `2^29`; otherwise `AtlasRange`.
2. Frame dimensions must be positive and no greater than `2^29`; otherwise `FrameRange`.
3. Each unsigned origin and padding value must be no greater than `2^29`; otherwise `OriginRange`.
4. `x+2*padding+width <= atlas_width` and `y+2*padding+height <= atlas_height`; otherwise `PaddedBounds`.

The full two-sided padded rectangle must fit. A content rectangle that fits while its right or bottom padding does not fit is rejected. These ordered guards are engineering admission, not validations performed by the actual constructor. Guarded extent sums remain below U32 wraparound. The policy does not impose a power-of-two atlas requirement, mip alignment, or a particular mip level: those belong to the authoritative packing and loader context.

The bound supports testing actual int-to-F32 rounding above `2^24`. It is not a claim that a GPU can allocate a `2^29` texture. A small frame's UV span can collapse at huge dimensions under the measured F32 rules; this module preserves that result and makes no sampling-quality guarantee. A later GPU/atlas admission layer must validate its own texture size limits.

## Actual receiver corpus and boundaries

The pinned client JAR SHA256 is
`4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d`.
The reference invokes the real protected `TextureAtlasSprite` constructor reflectively. It constructs real `SpriteContents` and CPU `NativeImage` instances with their normal constructors, then closes them normally. No client activation, window, GPU service, unsafe allocation, forged contents fields, or replacement sprite implementation is involved.

For scalar boundary fixtures, an opaque 1×1 CPU image accompanies the supplied `FrameSize`. Those frame dimensions intentionally differ from the image dimensions for many tests, including huge and malformed raw values. The receiver stores the supplied frame dimensions, enabling direct scalar observation without allocating a huge image. This is a constructor fixture, not evidence of production frame selection. Eight additional fixtures decode the actual pinned PNGs through the actual `NativeImage.read`: stone, dirt, oak planks, grass top, glass, snow, water still and lava still. Complete strips are passed as their supplied frame dimensions; animation metadata is absent and animation frame selection is not tested.

`reference/sprite_uv.json` records:

- 210 direct actual constructor cases, including odd/non-square extents, edge/padding admission, mip-derived padding examples, int-to-F32 precision boundaries, raw signed overflow, 160 deterministic random layouts, and eight original resource hashes/dimensions.
- Five actual Stitcher scenes, with 25 callbacks passed directly to the actual sprite constructor. These include non-square and odd frames, mip levels 0/1/2/4, and different padding settings.
- Raw F32 `getU/getV` queries covering normalized corners, interior/random coordinates, extrapolation, signed zero, subnormals, finite limits, infinities and two quiet NaN bit patterns.
- Actual `CuboidFace`/`Quadrant.R0` mapped corners, original integer getters, atlas identity, frame dimensions and reflective padding.
- Pinned class, Java/library, harness and bytecode provenance plus the complete relevant API inventories.

The fresh reference selftest executes two official Java runs and rejects eight corruptions: altered unsealed/resealed endpoint words, interpolation, callback padding, an invented shrink method, API inventory, resource hash and class hash. Native preparation adds 14 separate caller-policy boundary cases, yielding 249 inputs. Its sealed manifest pins the exact compiler, transitive Bend sources, runner, reference, semantic inputs and case-file bytes. Non-prepare phases require the preserved generation and fail instead of regenerating missing or stale fixtures.

```sh
python3 tools/reference_sprite_uv_probe.py extract
python3 tools/reference_sprite_uv_probe.py validate
python3 tools/reference_sprite_uv_probe.py selftest
python3 tools/test_sprite_uv.py --prepare-only
/Users/chuah/.bend/bin/bend src/sprite_uv.bend --check-only
/Users/chuah/.bend/bin/bend tests/sprite_uv.bend --check-only
# Only after the lead grants a heavy build slot:
python3 tools/test_sprite_uv.py --skip-kernel --build-only
python3 tools/test_sprite_uv.py --skip-kernel --reuse-build
```

The two source laws establish integer content origin for the supplied padding example and retention of the original `Input`. They do not prove F32 arithmetic parity. The native suite compares every endpoint, stored corner, actual mapped corner and recorded interpolation query against actual Java F32 words on the pinned target. Raw NaN payload comparisons are target observations, not a claim that every architecture preserves identical payload propagation.

`evidence/sprite-uv-native.json` records 224 admitted cases and 25 policy rejections, with both native outputs equal. All 4,700 actual interpolation query pairs pass, including the recorded quiet NaN payload words and arithmetic-generated nonfinite words. The canonical native report SHA256 is `5b20a9677855bf02bb6cb33419c75fd4699d89d2b61cb87d0e8f1404fe7c6bc6`. The complete native runs, including fixture parsing, comparison-driver serialization and stdout, took 0.662 and 0.084 seconds; these are test-driver timings, not a production atlas benchmark.

The actual installed native build took 4.692 seconds. Its 1,405,568-byte binary SHA256 is `1da8caa5ed3a5fa4798a63a42c2c085486a68f219270d0135f7ad466731b5e80`. The original 1,060,064-byte generated C was preserved before compiler cleanup at ignored `build/sprite-uv/preserved.c`, SHA256 `f2b0fbf0017c36616d6e0a2e023616d446af5ef41756e9cbb4e3f75fa06ba782`. The actual native invocation used Apple CommandLineTools clang `-std=c11 -O3`; `evidence/sprite-uv-build-profile.json` retains its real cc1 flags, compiler identity and before/after generation pins. Read-only generated metadata records four UV closures and at most seven capture words across all generated closures. No generated C or compiler source was edited or manually compiled. The independent process-group wrapper enforced a 600-second cap. Peak build RSS/physical footprint was not sampled and remains unobserved.

The separately recorded full production `--verdict` passed `ALL PROOFS CHECK` in 0.116 seconds under a 60-second process-group cap. It ran exactly once after the native evidence was written. `evidence/sprite-uv-kernel.json` records that result; the native report's `kernel:not-run` refers specifically to its `--skip-kernel` runner invocation, not to this later standalone check.

`evidence/sprite-uv-preparation-retention.json` rejects seven additional manifest/existence mutations without changing prepared files, covering seal, resealed source/runner/reference/semantic/case-byte hashes, and a missing manifest. The sealed preparation SHA256 remains `ce8daa2f6d32dd31ce1c017db4c684ae03933cc3f9831893034c9d9632a00d13`. No source, reference, runner, harness, semantic inputs or expectations changed between the granted emission and successful comparisons.

## Later sprite-context integration

A caller can construct the existing `BlockBake.Sprite` with the mapping's stored `u0,v0,u1,v1`, its explicit slot, layer and animation policy. `BlockBake.atlas_uv` already uses the same ordered subtraction/multiplication/addition contract as `get_u/get_v`. The slot must refer to the corresponding **atlas texture**, rather than retaining a previous slot that points to a separate per-image texture. This checkpoint neither repoints those slots nor constructs that atlas image.

Future integration must retain authoritative packing membership, choose actual static frame dimensions and mip/padding settings, construct and verify padded atlas pixels/mipmaps, establish material/animation admission, and test the atlas sampler/render path. UV scalar equivalence alone does not establish final frame equivalence.
