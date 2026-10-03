# Texture metadata: pinned Java 26.3

`src/texture_metadata.bend` interprets the actual four-field `TextureMetadataSection.CODEC` under `JsonOps.INSTANCE`. The source and narrow test driver pass the ordinary Bend checker. Fresh native compilation took 8.531 seconds; all 350 native cases passed, and two complete native runs produced identical reports. Native evidence is `evidence/texture-metadata-native.json`; the earlier preflight remains explicitly marked unverified preparation. The Java reference executes the pinned codec, the production `ResourceMetadata` receiver, and real CPU `TextureContents`/`SpriteContents` constructors without opening a window. The separate full-import kernel attempt returned the compiler/BendTT mismatch after 5.099 seconds, with no source location; `evidence/texture-metadata-kernel.json` records the diagnostic, and no full-import mathematical proof claim is made. Confidence is high for these measured fields and receiver cases; GPU sampling, generated mipmap pixels, atlas stitching and final frames are outside this module.

## Typed API

```text
Strategy = Auto | Mean | Cutout | StrictCutout | DarkCutout
Metadata { blur: Bool, clamp: Bool, strategy: Strategy,
           alpha_cutoff_bias: F32 }
Error { code: String, field: String, message: String }

decode_section(J.Value) -> Result<Error, Metadata>
decode_document(J.Value) -> Result<Error, Maybe<Metadata>>
parse_document(String) -> Result<Error, Maybe<Metadata>>
parse_document_with(String, J.Limits) -> Result<Error, Maybe<Metadata>>
defaults() -> Metadata
strategy_name(Strategy) -> String
```

These are immutable Data values. There is no archive IO, texture ownership, sampler allocation, material classification or renderer admission in this module. The document API matches `ResourceMetadata.getSection(TextureMetadataSection.TYPE)`: a missing `texture` member returns `None`, while `"texture": null` or another nonobject fails. The section API requires an object and ignores unknown members.

| Field | Default | Accepted values |
|---|---|---|
| `blur` | `false` | JSON boolean |
| `clamp` | `false` | JSON boolean |
| `mipmap_strategy` | `"auto"` | Exact lowercase `auto`, `mean`, `cutout`, `strict_cutout`, `dark_cutout` |
| `alpha_cutoff_bias` | positive F32 zero | JSON number narrowed directly to F32 |

A null **field** is treated as absent by the official optional-field codec. Strings such as `"true"` and `"0.1"` are not coerced. Strategy spelling is case sensitive. Alpha bias is unrestricted by the codec: negative values, subnormals, signed zero and overflow infinities are preserved. Unquoted `NaN`/`Infinity` are invalid resource JSON; quoted versions are strings and fail the number codec. Bend calls the existing exact decimal-to-F32 parser and compares raw bits against actual Java values, including rounding ties.

`decode_section` assumes a parsed `J.Value` with unique object keys and strict JSON number lexemes. `ResourceJson` resolves duplicate keys to their last value before decoding. An arbitrary manually constructed malformed `JNumber` is rejected. The text wrapper uses the measured production STRICT Gson reader profile: initial BOM, one completed root without an EOF check, and last duplicate wins. Its default limits are one MiB of input codepoints and depth 255. ResourceJson also preserves the measured STRICT reader limit of 1,023 units in a numeric token. The existing numeric parser called by direct tree decoding separately limits a token to 4,096 codepoints and its coefficient to 1,024 digits. These are explicit engineering limits, not Java codec limits. Input has already become a Bend String; this API does not reproduce Java's replacement decoding of invalid UTF-8 bytes. The frozen resource loader continues its strict UTF-8 policy.

Errors use deterministic Bend codes and a field name. Java's combined diagnostic text and partial `DataResult` values are not reproduced. Production `ResourceMetadata` calls `getOrThrow`, so malformed fields fail the receiver even when its codec also records a partial value. The native oracle checks success/absence/rejection and every successful field, rather than equating the two implementations' diagnostic formatting.

## Actual consumers

The reference pins hashes of the production classes and a reproducible `javap -c -p` dump. CPU constructor executions check stored values; sampler and generation behavior below is read from those pinned method bodies, without activating GPU state.

| Consumer | Texture settings it uses |
|---|---|
| `TextureContents` | `blur` and `clamp`, both false when metadata is absent |
| `ReloadableTexture.setSampler` | U/V address is `CLAMP_TO_EDGE` when clamp is true, otherwise `REPEAT`; min/mag filter is `LINEAR` when blur is true, otherwise `NEAREST`; mipmaps disabled |
| `MipmappedTexture.setSampler` | Same address policy; min filter always `LINEAR`, mag filter follows blur; mipmaps enabled |
| `MipmappedTexture.doLoad` | Calls mip generation with **AUTO and bias zero**, rather than the metadata strategy/bias |
| `SpriteContents` | Stores metadata strategy and bias, defaulting to AUTO and positive zero; its constructor does not read blur/clamp |
| `SpriteContents.increaseMipLevel` | Passes stored strategy/bias and image transparency to production `MipmapGenerator` |
| `TextureAtlas.upload` | Sets an atlas sampler with clamp-to-edge and nearest min/mag filtering; this call does not consult each sprite's blur/clamp |
| `SpriteResourceLoader` | Obtains animation and texture metadata before image decoding; a metadata exception is caught, logged and returns a null sprite |

The filter parameter names are verified from the installed `GpuDevice.createSampler` method's `MethodParameters`: address U/V, min filter, mag filter, anisotropy, max LOD. `SamplerCache` passes its two filter arguments to those same positions and encodes its mipmap flag as unrestricted max LOD versus max LOD zero. No GPU sampler was constructed by the probe.

`MipmapGenerator.generateMipLevels` resolves AUTO to CUTOUT when `Transparency.hasTransparent()` is true and to MEAN otherwise. For a single base image whose identifier does not start with `item/`, CUTOUT and STRICT_CUTOUT call `TextureUtil.solidify`, and DARK_CUTOUT calls `fillEmptyAreasWithDarkColor`, **before** the early return for already sufficient mip levels. This can therefore modify level zero even when requesting no additional levels. Generated levels use `ARGB.meanLinear` except the DARK_CUTOUT branch, which uses its separate darkened blend. Cutout-family modes then adjust alpha coverage; STRICT_CUTOUT uses threshold F32 0.3, the others F32 0.5, and passes the metadata bias to `scaleAlphaToCoverage`. These are observed control paths, not an implemented Bend mipmap algorithm or a pixel-equivalence result.

The actual glass resource is:

```json
{"texture":{"mipmap_strategy":"mean"}}
```

It decodes to `Metadata{false,false,Mean,+0}`. Choosing MEAN is a mip generation policy; it does not assign a translucent render layer. Layer classification remains a separate model/material input.

## Reproduction and current integration boundary

```sh
python3 tools/reference_texture_metadata_probe.py extract
python3 tools/reference_texture_metadata_probe.py validate
python3 tools/reference_texture_metadata_probe.py selftest
python3 tools/test_texture_metadata.py --prepare-only
# Run only after the lead grants a compiler slot:
python3 tools/test_texture_metadata.py --skip-kernel
# Reuse verifies the exact transitive source and binary generation:
python3 tools/test_texture_metadata.py --skip-kernel --reuse-build
```

`reference/texture_metadata.json` contains 344 actual official cases, including all 218 `.png.mcmeta` files in the pinned jar, and six CPU consumer constructions. There are 60 texture sections in the jar; the other 158 metadata files have no such section. These sections comprise 48 strategy entries, five alpha biases of 0.1 (cactus side/top, kelp, kelp plant and tripwire), six blur entries and the shadow texture clamp entry. The whole case set observes 104 successful metadata values, 161 absent sections and 79 rejected inputs. The reference selftest runs two fresh Java processes and rejects six input, value, absence, consumer or provenance corruptions. The native driver also passes six explicit budget tests. In the 344 official cases, every successful metadata field and raw F32 word agrees with actual Java; all absence and rejection outcomes agree. All native launches are window-free with `BEND_MINECRAFT_LAUNCH_MODE=hidden`; no focus or Spaces change is needed.

The existing `BlockResources.StaticNormalized`, `BlockBake.Sprite` and renderer APIs remain frozen. In particular, glass metadata is still rejected by that loader. A later explicit resource policy should retain this typed metadata separately from layer and animation, bind the intended standalone/atlas consumer, and build independently verified mip chains and sampler state before admitting it as production behavior. An explicitly selected normalized-image verification policy could retain decoded metadata while declaring disabled mipmaps and its own filter/address settings, but accepting parser output under that policy would not establish vanilla rendering. The production atlas path needs its own preprocessing, mipmap, atlas and GPU evidence.
