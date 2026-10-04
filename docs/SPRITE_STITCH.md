# Static sprite rectangle stitching for Java 26.3

`src/sprite_stitch.bend` implements the pinned official `Stitcher` rectangle algorithm over caller-supplied static sprite entries. Its source and narrow driver pass ordinary Bend checking. Actual Java extraction, validation, and two fresh-run integrity checks pass. The installed native Bend binary passed the complete 498-case suite twice without source or expected-result changes. One full unchanged production-module kernel check also passed `ALL PROOFS CHECK` in 0.171 seconds.

The reference invokes actual `Stitcher` construction, `registerSprite`, `stitch`, and `gatherSprites`. A Java record implements the official `Entry` interface and supplies an identifier, dimensions, and an opaque test tag. The fixture does not implement a second packer. Reflection reads official rounded `Holder` sizes, the official comparator, and the padding field. Expected positions, callback order, atlas dimensions, and actual failures come from the official receiver.

## Typed interface and ownership

```text
Entry Data { namespace, path: String; width, height, tag: U32 }
Config Data { max_width, max_height, mip_level, padding_setting: U32 }
Limits Data { max_entries, max_id_codepoints: U32 }
Request Type { config: Config; entries: List<&2, Entry> }
Holder Data { entry: Entry; width, height: U32 }
Placement Data { holder: Holder; x, y: U32 }
Packed Data {
  width, height, padding: U32;
  sorted: List<&2, Holder>;
  placements: List<&2, Placement>
}
Error Data { code: String; tag: U32; partial: Maybe<&2, Packed> }

defaults() -> Limits                         # 4096 entries / 4096 chars per ID part
pack(Request, Limits) -> Request & Result<Error, Packed>
complete_within(Packed, Config) -> Bool
close_request(Request) -> Unit
padding_raw(level, setting: U32) -> U32
round_raw(value, level: U32) -> U32
power_raw(value: U32) -> U32
```

The request is an affine token. `pack` returns that same configuration and every input entry on success, a policy error, and `NoSpace`. Entries and result records are immutable Data; no arrays, images, resource handles, or GPU state are involved. `close_request` consumes the token. A caller can unpack a returned request, change the configuration, and submit its retained entries again. `NoSpace` includes the exact partial dimensions, complete sorted holder list, and occupied callbacks already present when the official algorithm would throw.

`tag` is caller metadata, preserved through sorting and callbacks. Duplicate identifiers, duplicate dimensions, and repeated tags are not rejected. Tags do not participate in the comparator. For fixture comparisons, tags are distinct so equal identifier/dimension registrations remain distinguishable.

`x,y` are the **padded region origin**. Content starts at `x+padding,y+padding`; the public holder dimensions include padding and mip rounding. `Packed.width,height` are the Stitcher storage extents, without an additional post-stitch resize. No UV or image-copy policy is implied.

## Rules from the pinned receiver

The constructor is `(maxWidth,maxHeight,mipLevel,paddingSetting)`, with four arguments. Its Java integer expression is:

```text
padding = (1 << mipLevel) << clamp(paddingSetting - 1, 0, 4)
holderWidth  = smallestFittingMinTexel(entry.width  + 2*padding, mipLevel)
holderHeight = smallestFittingMinTexel(entry.height + 2*padding, mipLevel)
```

Setting zero still gives one mip texel of padding. Settings 0 and 1 therefore agree. In the production `SpriteLoader` bytecode, the fourth input is zero unless anisotropic filtering is selected, in which case it comes from `Options.maxAnisotropyBit`. That caller also reduces the requested mip level using sprite dimensions and lowest-one-bit constraints before constructing the Stitcher. These are bytecode observations of the caller, **not** an executed production `SpriteLoader` test. This module receives the already chosen mip and padding setting explicitly.

Holders sort by descending rounded height, descending rounded width, then `Identifier.compareTo`. That identifier comparator compares **path first**, then namespace. Java's stable list sort retains registration order for otherwise equal holders. Bend uses Base's stable merge sort with the same comparator over the admitted positive dimensions.

Storage begins at `0×0`. Each holder searches regions in insertion order and child regions in their list order. Occupied regions reject new holders. An empty region rejects a holder larger than either extent; an exact fit stores it directly. A larger free region creates the occupied rectangle first and residual rectangles afterward:

- With both residual width and height positive, compare `max(region.height,residualWidth)` with `max(region.width,residualHeight)`. Greater-or-equal selects a bottom rectangle of holder width, then a right rectangle of full region height. Otherwise select a right rectangle of holder height, then a bottom rectangle of full region width.
- A zero residual width leaves the bottom rectangle; a zero residual height leaves the right rectangle. Exact fits leave no residual rectangle.

The Bend representation flattens that tree's depth-first **leaf order**. Replacing a free leaf with the occupied leaf and these ordered residual leaves preserves the official search and callback traversal in the admitted nonnegative rectangle domain. It is not a shelf, best-fit, or optimal packer.

If no existing region accepts a holder, expansion computes the current and candidate powers of two independently for X and Y. Candidate X uses `storageX+holder.width`; candidate Y uses `storageY+holder.height`. An axis is available if its candidate does not exceed the corresponding maximum. If exactly one available axis changes its power of two, that axis wins. Otherwise X wins when available and current rounded X is no greater than current rounded Y. X growth appends a right strip; Y growth appends a bottom strip. The strip is added to storage even when its `Region.add` returns false.

`gatherSprites` visits occupied leaves in region-tree order, independent of registration or holder sort order, and passes the same constructor padding with each callback.

## Actual unusual outcomes and separate admission

The official `expand` ignores the Boolean returned by its new region's `add`. Also, initial X growth sets the storage height to the candidate Y size without rechecking `maxHeight`. The actual fixture shows:

| Supplied entry and maximum | Official result with mip 0 / setting 0 |
|---|---|
| 16×16, maximum 256×256 | holder 18×18, storage 32×32, callback `(0,0,1)` |
| 40×4, maximum 16×32 | success, storage 0×8, **no callback** |
| 4×40, maximum 32×16 | success, storage 8×64, callback `(0,0,1)` |
| 40×4 followed by 3×3, maximum 16×32 | success, storage 8×8, only the second entry has a callback |

These results are preserved. `complete_within` separately checks callback count equals holder count, returned dimensions are within the caller maxima, and every padded placement lies within the returned extents. It returns false for the missing or oversized results above. Empty input returns `0×0` and passes this predicate. The caller must choose whether an incomplete/oversized packing is admissible; `pack` does not silently rewrite the official result.

`NoSpace` is the actual branch where neither candidate expansion axis fits. It can follow prior storage growth beyond a requested maximum because of the initial-height behavior. Policy errors are distinct and never presented as official Java exception diagnostics.

## Explicit bounded packing domain

The typed rectangle path accepts:

- Atlas maxima from 1 through `2^29`, independently; they need not be powers of two.
- Mip levels from 0 through 24.
- Positive entry dimensions no greater than `2^29`, and resulting padded/rounded holder dimensions in the same range.
- The caller's entry and identifier-part length budgets; defaults are 4096 each.
- Identifier characters accepted by actual `Identifier.fromNamespaceAndPath`: lowercase ASCII letters, digits, `_`, `-`, `.` in namespace; additionally `/` in path. Namespace `..` is rejected. Empty namespace or path is accepted, and is preserved rather than normalized to `minecraft`.

Paths such as `../x` and `/x` are permitted identifier strings, as observed in the actual constructor. This module performs no host filesystem access. An atlas/resource loader must decide its own resource interpretation and admission separately.

The maxima/holder bound keeps intermediate extent sums at or below `2^30`, so the executed packing path uses Java-positive integer comparisons and does not encounter the signed-overflow geometry seen in the raw fixture. Policy codes are `AtlasRange`, `MipRange`, `InvalidIdentifier`, `IdentifierLimit`, `EntryRange`, `HolderRange`, and `EntryLimit`. Validation checks configuration first, then count, then entries in registration order; each entry checks identifier syntax, name budget, dimensions, and rounded holder size. Those guards are engineering policy, not additions to the official receiver.

The three public raw helpers reproduce Java 32-bit wrap, arithmetic right shift, low-five-bit shift distances, and constructor subtraction overflow. For example, `Integer.MIN_VALUE - 1` wraps positive before clamping the padding setting; negative and oversized mip integers mask their shift distance. Raw power rounding can return `0x80000000` or zero. Actual pathological rectangle receiver results are retained in the reference but rejected by the typed packing path; a success with a negative storage extent is not declared a usable atlas.

## Reference corpus and verification commands

Pinned installed client JAR SHA256:
`4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d`.

`reference/sprite_stitch.json` contains:

- 304 actual constructor/register/stitch/callback cases: deterministic random scenes, growth/split/tie behavior, stable duplicate-ID ordering, namespace/path ordering, mip/padding boundaries, non-power maxima, true `NoSpace`, initial oversized quirks, identifier failures, and out-of-domain integer cases.
- 282 separately executed wider-atlas retry cases for admitted input entries, supporting same-owner native recovery checks.
- 180 actual raw arithmetic cases, including signed limits, overflow powers, levels -1/31/32/large integers, and padding-setting subtraction overflow.
- Hash-pinned original PNG dimensions for 3,964 `assets/*/textures/*.png` resources. Their **complete content rectangles** are supplied as static DTO dimensions. Animated strips are not converted to frames and this is not the production block atlas inventory.

The actual 3,964-rectangle DTO scene produces 4096×4096 storage with mip level 2 / setting 0. A 512-rectangle prefix produces 512×1024. The actual algorithm, rather than a Python packing reimplementation, supplies these observations.

```sh
python3 tools/reference_sprite_stitch_probe.py extract
python3 tools/reference_sprite_stitch_probe.py validate
python3 tools/reference_sprite_stitch_probe.py selftest
python3 tools/test_sprite_stitch.py --prepare-only
/Users/chuah/.bend/bin/bend src/sprite_stitch.bend --check-only
/Users/chuah/.bend/bin/bend tests/sprite_stitch.bend --check-only
# Only after the lead grants a heavy build slot:
python3 tools/test_sprite_stitch.py --skip-kernel --build-only
python3 tools/test_sprite_stitch.py --skip-kernel --reuse-build
```

The reference selftest executes two fresh official Java runs and rejects eight mutations, including altered callback coordinates/order, rounded sizes, raw overflow output, resource hashes, and class provenance. Native preparation contains 498 cases, with 14 explicit caller policy boundaries beyond the receiver corpus. Its sealed generation pins the exact reference, compiler, transitive Bend sources, runner, semantic inputs, and each case-file byte hash. Non-prepare phases require that generation and fail on stale/missing inputs instead of rewriting them. Native reuse also requires the recorded source generation and exact binary hash.

The prepared native suite compares all admitted dimensions, padding, stable holder order, callback order/positions and original entries, true `NoSpace` partial layouts, structured policy rejections, raw integer words, and the complete retained request after every call. Admitted cases retry with a wider configuration using their returned entry list and compare against the separate actual Java retries. Rectangle non-overlap, padded bounds, and mip alignment are independently checked without using them to select expected placements.

Three kernel-checked concrete laws establish only `padding_raw(0,0)=1`, `round_raw(18,2)=20`, and `power_raw(0)=0`. The full production module's termination/type/proof verdict also passed, but those mathematical checks do not prove whole-algorithm Java parity. That behavioral evidence comes from the independent actual receiver comparisons.

`evidence/sprite-stitch-native.json` records both equal native runs: 177 successful admitted/policy-boundary packings, 108 exact `NoSpace` partial layouts, 33 policy rejections, 180 raw integer comparisons, 290 retained-owner wider-atlas retries, and 5,994 callback placements across successful primary cases. Twenty-two actual Java success cases fail the separate `complete_within` predicate; all are preserved and documented by ID. The canonical native report SHA256 is `237141fb30a98def13ba77261bae8dbb210f4154b09e185bc22c6ea0d64ddd31`.

Per-case native timing includes packing, result/owner/recovery encoding, forced encoded-string traversal, and a short marker write. It excludes the full diagnostic stdout write and initial fixture parsing. These are useful total-work upper bounds, not a pure packing microbenchmark:

| Supplied actual PNG rectangle prefix | First / second native measurement |
|---|---:|
| 64 | 7 / 7 ms |
| 512 | 70 / 70 ms |
| 3,964 | 1,424 / 1,417 ms |

The complete native runs took 3.525 and 2.952 seconds. The large entry measurement includes its second, wider-atlas owner-recovery packing and complete original/result serialization. This is startup prerequisite cost, with no production animation inventory or frame-time claim.

The actual installed native build took 6.708 seconds with `/Users/chuah/.bend/bin/bend tests/sprite_stitch.bend -o build/sprite-stitch-tests`. Its 1,514,240-byte binary SHA256 is `5540a279b0ddb0269ca69ee0d9d9842bb7f7782373cb51c09d6a539b8e698307`. The exact 1,344,176-byte generated C was preserved before cleanup at ignored `build/sprite-stitch/preserved.c`, SHA256 `01f6d2b61d09343bc1f199736bcd02a118a40dfb84790e2d07e643e63eac267d`. The observed real native invocation used Apple CommandLineTools clang `-std=c11 -O3`, and its actual cc1 flags are retained in the build profile. No generated C or compiler source was edited or manually recompiled. The process-group cap was 600 seconds; the successful build completed well before it. Build peak footprint was not sampled and remains unobserved.

`evidence/sprite-stitch-preparation-retention.json` rejects seven additional manifest mutations without rewriting the original prepared case files, including resealed source, runner, reference, semantic-input, case-byte and missing-file changes. The final sealed preparation SHA256 is `ea823e7bd235fee655b94c9398a5d73aa926ea83677cc703985715d92e7b1de7`; source/runner/reference hashes are bound in both preparation and the native artifact receipt.

## Integration boundary

This prerequisite consumes rectangle metadata. It does not select animation frame dimensions, load PNGs, create padded atlas image pixels, implement mipmap strategies or alpha-cutoff bias, derive atlas UVs, stitch resource sources, upload an atlas, or execute GPU sampling/rendering. Existing `StaticNormalized` resource loading and normalized `BlockBake` sprite contexts remain unchanged. Future integration must explicitly choose production frame dimensions, the effective mip level and padding setting, completeness policy, texture copy/mipmap behavior, and atlas UV construction, then verify those behaviors separately.
