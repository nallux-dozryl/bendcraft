# CPU texture mipmaps for Java 26.3

`src/texture_mipmap.bend` implements the pinned CPU `MipmapGenerator` over owned ARGB pixel arrays. The source and narrow driver pass ordinary Bend checking. Actual official receiver extraction and two fresh Java repeats pass, including eight corruption checks. Two unchanged retained native runs pass 498 inputs: 204 successful frames, 33 policy rejections, 260 scalar quads and all 1,280 lookup values. They compare 28,120 actual Java output pixels, including 6,247 generated pixels, and 230 successful same-owner recoveries. The full production kernel verdict passes its three stated scalar laws. Confidence is high within this measured bounded domain; atlas integration and complete Minecraft acceptance remain separate work.

This is CPU image processing. It does not select animation frames, assemble padded atlas pixels, upload images, execute a GPU sampler, or change the frozen resource loader, sprite/baker or atlas contracts.

## Affine interface and admission

```text
Strategy Data = Auto | Mean | Cutout | StrictCutout | DarkCutout
Transparency Data { transparent, translucent: Bool }
Config Data {
  path: String; target_level: U32; strategy: Strategy;
  bias: F32; transparency: Transparency
}
Limits Data {
  max_dimension, max_levels, max_capacity,
  max_work_pixels, max_path_codepoints: U32
}
Level Type { width, height: U32; pixels: Array<U32> }
Chain Type { levels: List<&1, Level> }
Dimension Data { width, height, capacity: U32 }
Summary Data {
  effective: Strategy; early_return, base_preconditioned: Bool;
  original_levels: U32; dimensions: List<&2, Dimension>
}
Error Data { code: String; level: U32 }

defaults() -> Limits
generate(Chain, Config, Limits) -> Chain & Result<Error, Summary>
compute_transparency(Level, Limits) -> Level & Result<Error, Transparency>
close_chain(Chain) -> Unit
```

`generate` returns the sole chain owner on success and every error. An admitted success can mutate level zero or supplied higher levels and append generated levels. An error from prevalidation retains every original word, dimension, tree shape and unused capacity cell without pixel mutation. There is no second owner or implicit array clone. Scalar diagnostics borrow Data words while retaining their array; those diagnostic copies do not establish physical address identity.

Pixel words are straight-alpha `0xAARRGGBB`, matching the actual `NativeImage.getPixel/setPixel` API and existing PNG/Base pixel convention. Logical index is `x+y*width`. NativeImage's underlying little-endian ABGR representation is not exposed as the Bend word format.

Base arrays have power-of-two capacity. Each admitted buffer is a complete balanced tree with capacity at least `width*height`; an explicit bounded structural inspection retains both-child validation. The installed native representation enforces equal child classes while constructing `ANode`, so an unequal tree cannot reach this module through that constructor. The original defensive fixture failed during harness construction, before `compute_transparency` or `generate`; it is excluded from the revised native inputs. Production `inspect_array` remains unchanged, and **`BufferShape` has no native fixture coverage**. All original cells beyond the logical rectangle remain unchanged. New levels allocate the smallest sufficient power-of-two capacity and fill unused cells with zero. Padding capacity is storage policy, not additional NativeImage pixels or atlas border padding.

Default limits are dimension 8192, 16 supplied/target levels, 4,194,304 capacity cells, 1,048,576 logical work pixels and 4096 path codepoints. Configurable limits themselves must have positive dimension at most 16384, level count 1–16, capacity/work maxima at most 16,777,216, and path limit at most 65536. Zero capacity/work budgets reject any nonempty image. `target_level` must be below the chosen maximum level count. `path` is the caller's identifier path component; this module checks its length and exact `item/` prefix, and performs no identifier parsing or filesystem access.

Admission then checks nonempty supplied level count, all positive dimensions, every complete array shape, logical bounds, original capacity totals and logical work totals. It accounts for two additional rounded base-sized arrays when solidification is required, and for every generated level's actual rounded capacity. Generated dimensions are right-shifted by one; any zero dimension is rejected **before** pixel mutation. Original unused capacity and extra supplied levels count toward budgets even when an early return would not inspect their pixels in Java. The capacity budget conservatively counts supplied and generated arrays plus temporary solidification allocations, even though the temporaries are released before later mip allocation. The work limit counts logical rectangles; the fixed coverage sampling/search and BFS bound the additional work per rectangle.

Policy errors are `LimitsRange`, `LevelRange`, `PathLimit`, `LevelCount`, `DimensionRange`, `BufferShape`, `BufferLength`, `CapacityLimit`, `WorkLimit` and `ZeroGeneratedDimension`. They are explicit engineering admission, not invented official Java exceptions. Internal unchecked scalar/array helpers require the bounds established by the public entry points.

## Actual six-parameter receiver

The official call is:

```text
MipmapGenerator.generateMipLevels(
    Identifier name, NativeImage[] supplied, int targetLevel,
    MipmapStrategy strategy, float alphaCutoffBias,
    Transparency transparency)
```

The five serialized strategy names remain `auto`, `mean`, `cutout`, `strict_cutout` and `dark_cutout`. AUTO resolves to CUTOUT when the **supplied** `Transparency.hasTransparent()` is true, otherwise MEAN. `hasTranslucent()` does not participate in that choice. The explicit flags can differ from the image's computed transparency; this module preserves that receiver parameter instead of silently inferring a strategy. The separate checked helper computes both flags from original logical alpha bytes: alpha zero means transparent, alpha 1–254 means translucent.

When there is exactly one supplied image and the path does not start with `item/`, CUTOUT and STRICT_CUTOUT solidify its transparent RGB; DARK_CUTOUT fills its empty RGB with a dark color. This happens **before** checking whether enough mip levels already exist. Thus a target of zero can still change the base image. `item/` itself matches the prefix; `items/probe`, an empty path and `block/item/probe` do not. MEAN performs no such preconditioning.

If `targetLevel+1 <= supplied.length`, Java returns the original array, preserving every extra supplied level. Otherwise it allocates a new array, reuses level zero and every provided level encountered, and generates missing levels from the previous level. Provided levels do not have to be half the preceding image size: actual receiver fixtures include an 8×8 base followed by a 3×5 provided image, then a generated 1×2 image. Cutout alpha scaling also applies to reused provided higher levels when the array is extended.

NativeImage generation uses `previous.width >> 1` and `previous.height >> 1`, with no `max(1,...)`. Odd trailing rows/columns are omitted. A 1×8 or 8×1 image cannot generate level one. Negative or overflowing raw target integers can pass Java's early-return arithmetic; these are retained reference diagnostics and excluded by the Bend target policy.

## Quantized gamma and pixel averaging

The untouched official `ARGB` class initializes a 256-entry short sRGB→linear table and a 1024-entry byte linear→sRGB table. The forward values have ten-bit depth (0–1023); inverse values are 0–255. Initialization uses the actual class's piecewise sRGB formulas, Java `Math.pow` and float rounding. Bend embeds the complete actual table readouts as immutable balanced lookup trees, with exact table hashes in source comments. It does not substitute an older power-2.2 curve or compute an approximate gamma function at runtime.

MEAN invokes actual `ARGB.meanLinear`: alpha is the integer sum of the four alpha bytes divided by four. Each RGB component is the integer sum of the four forward lookup values divided by four, then indexed into the inverse lookup table. Hidden RGB in transparent input pixels contributes unless an applicable preconditioning step changed it. The four inputs are top-left, top-right, bottom-left, bottom-right. Generated pixels are visited X first, then Y, as in the official bytecode.

DARK_CUTOUT uses a different blend. A source with alpha zero contributes nothing; each other source contributes its alpha and RGB channels through `forward[channel]/1023` as F32. Each component's sum starts at F32 zero, adds the four sources in their actual order, divides by four, multiplies by 1023, floors, and indexes the inverse table. Alpha therefore follows this gamma path too. It is not ordinary alpha averaging or premultiplied-alpha blending.

## Solidification and dark fill

Actual `TextureUtil.solidify` seeds every nonzero-alpha pixel into a FIFO queue in X-major/Y-minor order. A multi-source Manhattan BFS visits neighbors in `(+X,-X,+Y,-Y)` order. It updates only a strictly shorter distance, so equal-distance ties retain the first seed. Transparent pixels take the selected seed's RGB and retain alpha zero. Nontransparent pixels retain their original complete word. An image with no seeds becomes zero RGB/alpha at the base. Bend uses bounded queue processing and two owned arrays for color and distance; queue fuel is the logical pixel count.

Actual `fillEmptyAreasWithDarkColor` chooses the first nonzero-alpha pixel with strictly smallest `red+green+blue`, using the same X-major/Y-minor scan. Each selected channel is multiplied by three and divided by four as integer arithmetic; transparent pixels receive that RGB with alpha zero. If there is no nonzero-alpha pixel, the initial selected word is all ones, producing RGB `(191,191,191)`. Real receiver tie fixtures independently exercise seed order and first-minimum selection.

## Alpha coverage and bias

CUTOUT and DARK_CUTOUT use cutoff `0.5f`; STRICT_CUTOUT uses `0.3f`. Original base coverage is measured after preconditioning, with alpha scale one. Coverage visits each adjacent 2×2 logical cell in Y-major/X-minor order. For each cell it samples a 4×4 grid at normalized offsets `0.125,0.375,0.625,0.875`, bilinearly interpolating clamped scaled alpha with the exact ordered F32 multiplies/adds. A sample counts only when its value is strictly greater than the cutoff. Cell counts divide by 16 and accumulate as F32, then divide by `(width-1)*(height-1)` converted to F32.

For each higher cutout level, the official routine searches at most five scales. Its interval begins `[0,4]`, candidate/best scale are one, and best error starts at maximum finite F32. It retains a candidate only for strictly smaller absolute coverage error. Coverage below target moves the lower bound; coverage above target moves the upper bound; equal or unordered comparison stops. The next candidate is `(low+high)*0.5f`.

Finally each alpha becomes `clamp(alpha/255 * bestScale + bias + 0.025f,0,1)`, in that operation order, multiplied by 255 and floored. RGB is preserved. One-dimensional coverage divides zero by zero; its NaN search comparisons leave the initialized scale, matching the terminating observed receiver path. Bias is raw F32. Positive infinity produces opaque higher-level alpha; negative infinity and the recorded quiet NaNs produce zero alpha. These finite and nonfinite cases terminate under the same fixed loop bounds and remain admitted. Exact NaN payload/pixel effects are pinned-target observations, not universal architecture guarantees.

## Reference and prepared tests

Installed client JAR SHA256:
`4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d`.
Untouched ARGB class SHA256:
`03cc9d35c6482408a96fdec73db7ab71ffb1b52e39b3b6fa7cb6e23fed126fee`.

The Java probe uses actual CPU NativeImage allocation, `setPixel`, `getPixel`, PNG decoding and `computeTransparency`, then the real generator. It records original pixels, all output pixels, supplied-image mutations, returned-array identity and actual reused-image indices. It closes accessible unique images normally. Java failing calls can mutate the base and leave unreachable internal partial allocations; those cases are explicitly excluded recovery diagnostics. The Bend policy rejects them before mutation and claims no equivalence to their partial-mutating failure behavior.

The reference includes 216 receiver cases (206 successes and 10 errors), 260 actual mean/dark scalar quads, all 1,280 table values and eight real PNG resources. Cases cover all five strategies, item prefix/level-zero preconditioning, AUTO flag overrides, FIFO ties, non-square/odd extents, one-dimensional failures, extra/unusual supplied levels, biases including infinities/NaNs, and deterministic random RGBA inputs. Water and lava fixtures use their complete PNG strips as logical input images; animation frame selection is not implied.

The independent reference selftest executes two fresh official Java runs and rejects eight mutations: unsealed/resealed mip pixels, base mutation, image reuse identity, forward/inverse table values, class provenance and resource hashes. The reviewed native preparation has 498 inputs: 237 frame/policy cases, 260 scalar quads, and one complete table readback. Native execution twice verifies 204 successful frames and 33 policy rejections. The rejection counts are nine `ZeroGeneratedDimension`, four `LevelRange`, three `LevelCount`, seven `LimitsRange`, one `PathLimit`, three `DimensionRange`, one `BufferLength`, three `CapacityLimit` and two `WorkLimit`. Native `BufferShape` coverage remains absent.

Executable fixtures contain original supplied pixel words, caller buffer-capacity cells and configuration only. Expected generated/preconditioned pixels remain outside the executable inputs in the independently produced reference. Every original unused capacity marker is checked for preservation; generated unused cells must be zero. After every returned owner, the harness performs a second MEAN/target-zero call with default limits, checking recovery or repeat rejection and complete word preservation. It does not reconstruct the chain from oracle output.

Preparation pins compiler, transitive sources, reference, runner, semantic inputs and every case-file byte. Non-prepare phases require that exact generation and fail rather than silently regenerate it. Native reuse additionally checks the retained executable hash. A native failure stops the sequence; there is no automated source/expectation/compiler retry.

The original 499-input run remains a failed attempt. Its unchanged source, harness, runner, cases, preparation, native receipt, original C, executable and available rawtrace are archived under `build/texture-mipmap/archive-failed-33682c9f`. The frozen runner retained only the final 5,000 stdout characters on nonzero exit, so complete original stdout is unavailable. Read-only localization shows `tests/texture_mipmap.bend:75` constructs a leaf paired with a two-leaf node; original C line 37176 calls `blk_node`, whose unequal-class guard at lines 1882–1891 posts `ERR_TAGS`. No runtime stack trace beyond `bend: runtime fail-stop` was observed. The original failure is not a comparator mismatch or a production error-return success.

After parent review, the revised runner removes exactly `policy_unequal_tree` and adds explicit retained-artifact adoption. Full AST comparison confirms unchanged comparator functions and exactly one input filter; every remaining input and the original expected dictionary is equal. No Bend/harness/reference changes or rebuild occurred. `--adopt-build` validates the reviewed archive hash, original producer receipt, source closure, installed Base/native-effect bodies, compiler, original C and binary before creating a separate adoption receipt. Reuse validates that receipt against the revised preparation. Installed effect bodies are present byte-for-byte in original C after the compiler's CID/FID substitution; Base also matches earlier independent root receipts. The complete system native/header/library closure was not captured.

```sh
python3 tools/reference_texture_mipmap_probe.py extract
python3 tools/reference_texture_mipmap_probe.py validate
python3 tools/reference_texture_mipmap_probe.py selftest
python3 tools/test_texture_mipmap.py --prepare-only
/Users/chuah/.bend/bin/bend src/texture_mipmap.bend --check-only
/Users/chuah/.bend/bin/bend tests/texture_mipmap.bend --check-only
# Fresh builds require a heavy-slot grant and a 600-second group cap:
python3 tools/test_texture_mipmap.py --skip-kernel --build-only
python3 tools/test_texture_mipmap.py --skip-kernel --reuse-build
# Separate retained-artifact path used here; do not rebuild before adoption:
python3 tools/test_texture_mipmap.py --skip-kernel --adopt-build
python3 tools/test_texture_mipmap.py --skip-kernel --reuse-build
# One separately granted unchanged production verdict, 60-second group cap:
/Users/chuah/.bend/bin/bend src/texture_mipmap.bend --verdict
```

Three kernel-checked scalar laws establish zeroing the alpha byte and the black/white endpoints of the embedded integer MEAN lookup path. The single full production `--verdict` invocation passes in 0.747 seconds; no harness/projection attempt or retry occurred. These laws do not prove the full generator's Java equivalence.

The one installed native build took 13.164 seconds and produced a 1,644,520-byte executable. The original 1,917,384-byte C and actual `clang -std=c11 -O3 ... -lpthread -lm`/cc1 invocations are retained. The two adopted native runs take 0.280 and 0.278 seconds. Original build physical footprint and peak RSS were not observed. Generated C has 90 production mipmap closures; the largest has 15 captured words.

Frozen hashes:

- Production source: `6be887316b9660442be7a2f7d701edd1d6675c6956f243b9bdbc6c54794bd38b`.
- Harness: `05dc6119fb4c4cd8e3712110af4f431f9e69497987a4b6406e3d833a1399991d`.
- Actual reference: `77297d625f5e43cd126803846a7f50604773d49fbc07a90fbd37a5f08c2b4aec`.
- Original producer runner/preparation: `b365d301ab5c2ff718370e2d1ef08bf404967dcb6e495b71953075ee60883f78` / `33682c9f6b72784c9a4427484ea20a69b4bc23d008afce2038ff780c11d63d3a`.
- Revised verification runner/preparation: `03987baf68b6f2407e57c9093cdfb2630cac25228f9517ede4bd8deb55789e44` / `74dce69959a9c4ea2a403feb6a8bd7f4baf0f22703af8a5193cadd962033a4f4`.
- Retained binary: `20f03b4a18e82570e5ee6b699a714309067697f414f455a379e41609057ca284`.
- Original emitted C: `34c460b8128c8fe40901553da90c4338adebf80f63533ac111f44014a33df9ad`.
- Canonical native output: `76a2063f67b043900dc77e3626d19c9ced2e89437f3a1af14da4d6ef0e73d07a`.

`evidence/texture-mipmap-native.json`, `texture-mipmap-kernel.json`, `texture-mipmap-build-profile.json`, `texture-mipmap-native-runtime-failure.json` and `texture-mipmap-repair-activation.json` retain separate native, proof, producer-cost, original-failure and reviewed-generation records. The native receipt says kernel not run in that runner phase; the separately produced kernel receipt records the subsequent successful verdict.
