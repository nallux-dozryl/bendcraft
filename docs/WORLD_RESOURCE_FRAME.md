# Neighbor-culled resource frames

`src/world_resource_frame.bend` combines the checked four-state visibility producer with an affine `ResourceFrame.Assets` owner. The resource loader and baker provide the actual geometry and textures; `WorldVisibility.produce` removes declared neighbor-cull groups; the retained textures feed the accelerated CPU `MeshRender.render`. A rejected sample, palette, scene, or renderer result returns the same asset fields and texture owner.

The production source and standalone harness pass ordinary checking, and the native composition passes all 97 sealed cases on its retained installed-compiler binary. These compare 3,693 actual quad records, 49 frames / 43,536 RGB pixels and RGBA CRCs, 1,536 original PNG texels, 36 full baked-face records and six binding appearances across two state-ID palettes. All 24 rejections pass their same-owner recovery redraws. The exact two-law palette projection passes the independent cached kernel. The full production verdict reached its 60-second cap without diagnostic output and remains unverified. Confidence is high within the explicit four-state static-white-light CPU domain.

`evidence/world-resource-frame-native.json` records the complete bounded native result. Its generation admission compares 94 source/compiler/tool/reference/fixture fingerprints before and after execution. `evidence/world-resource-frame-ordinary.json`, `world-resource-frame-kernel.json` and `world-resource-frame-full-verdict.json` distinguish ordinary, isolated mathematical and aggregate unverified results.

## Typed API

```text
resource_palette(ClientWorld.Palette) -> ResourceFrame.Palette
palette_match(ClientWorld.Palette, ResourceFrame.Palette) -> Bool

scene(WorldVisibility.Sample, ResourceFrame.Info, width, height, WorldMesh.Limits)
  -> Result<String, MeshRender.Scene>

draw_with(WorldVisibility.Sample, ResourceFrame.Assets,
          width, height, WorldMesh.Limits)
  -> ResourceFrame.Assets & Result<String, Image>
draw(WorldVisibility.Sample, ResourceFrame.Assets, width, height)
  -> ResourceFrame.Assets & Result<String, Image>

snapshot_draw(ClientWorld.State, ResourceFrame.Assets,
              width, height, WorldVisibility.Limits)
  -> ClientWorld.State & (ResourceFrame.Assets & Result<String, Image>)
```

`resource_palette` copies the four immutable palette words in air/stone/dirt/oak-planks order. `scene` requires all four words to match the asset palette exactly and both palettes to contain four distinct IDs. Matching only the three nonair bindings would be insufficient: the air ID also defines the visibility rule. `Palette:Mismatch` rejects before calling the visibility producer.

`scene` uses the original `RF.Info.bindings` and actual `texture_count`, existing `WorldMesh.frame` settings and explicit mesh budgets. `draw_with` obtains that Data information through `RF.info`, retains the sole affine Assets, and admits the scene. On admission failure it returns that original Assets value directly. On success it passes the existing `ClientRender.Assets` to `MeshRender.render`, then rewraps the returned resources with the original bindings, texture count, palette and catalog through the frozen `RF.rendered`. `draw` selects `WorldMesh.defaults()`.

`snapshot_draw` holds the sole world owner during `WorldVisibility.sample` and subsequent drawing. Sampling obtains camera-relative blocks and raw cell identities, validates the owned registry palette, and rereads the halo from that same owned world. Failures retain both owners. Sampling can populate the validated raw cache on a miss; this facade does not claim that every cache/view field stays unchanged. It neither steps simulation nor advances the world clock or logical revision.

The public `Sample` constructor is Data. Structural validation establishes raw/relative/mask alignment, unique signed XYZ cells, palette/material/state consistency, finite coordinates, six-bit masks and read counts. It does not authenticate that a caller actually sampled a world or that an arbitrary valid mask matches unseen neighbors. Use the owner-taking sampler, or a caller with equivalent checked authority. Likewise, public asset constructors do not authenticate load provenance; the admitted resource owner is expected to originate from `RF.load`.

## Error and budget behavior

Errors have these forms:

- `Palette:Mismatch` for an alias or any mismatched palette field.
- `Visibility:<code>:<x>,<y>,<z>,<boundary>:<state>:<detail>` for a sampler/producer error.
- `Render:<code>` for renderer validation.

Cell words are unsigned decimal encodings of the original U32 bits, including signed Java-int positions; no F32 coordinate is used as a neighbor identity. Boundary metadata and the state word are retained in the diagnostic. The visibility module still determines validation precedence within its own producer.

This composition inherits **pre-filter** WorldMesh budgets. An unculled 234-quad snapshot that retains 108 quads rejects a 108-quad producer budget. No frame is truncated to fit. Binding, block, tint and translucent limits remain enforced before face removal. Image dimensions remain the renderer's existing 4..1024 range and finite geometry/settings/material/texture checks remain in their original modules.

Declared `BlockBake.Baked.cullface` groups control neighbor visibility; the baked normal and triangle `MeshRender.Cull` remain distinct. Retained quads preserve original F32 vertex/UV bits, sprite slot, tint, white light, cardinal shade, address mode, backface behavior and raw snapshot/baked-list order. Face removal leaves gaps in quad order. No vanilla dispatch or transparency tie ordering is asserted.

## Prepared independent fixtures

The new harness imports production modules only, with boxed immutable draw inputs. Its file-path JSON protocol reads at most 1 MiB, checks EOF with a separate byte read, closes the file on every branch, decodes strict UTF-8 and uses a depth-64 checked JSON parser. Each Sample DTO word is checked U32; test tick/revision fields are explicitly restricted to U32. Raw signed XYZ/boundary/state/material, masks, F64 origin words and relative F32 words are decoded losslessly.

The verified native route calls `RF.load` once per palette configuration, then repeatedly calls the new facade with that same owner. Python supplies the sealed actual native WorldVisibility Sample outputs and archive paths/palette mapping; it does not supply expected baked quads, asset images or Java masks as native inputs. Expected geometry comes independently from actual Java model fixtures and raw cells; expected pixels come from the original PNG bytes and independent CPU ray/UV/color arithmetic. Both remain outside executable inputs. The existing ResourceFrame audit is a projected diagnostic rather than a lossless Assets serialization, so it is not used to reconstruct a cross-process affine owner.

`tools/test_world_resource_frame.py --prepare-only` prepares the fixture generation, and `--verify-existing` validates the retained generation without executing native programs. Use the bundled Python runtime with NumPy and Pillow. `evidence/world-resource-frame-preparation.json` pins source, harness, runner, compiler, the actual sampler handoff, original Java/JAR references and every prepared file. Native input JSON and comparison-only expectations are separate. A stale or missing generation rejects rather than silently regenerating for a comparison.

The completed 97-case corpus uses 46 genuine native Samples and 993 positive visible quads. It selects 22 representative frames, three empty dimension-edge frames and 24 baseline recovery frames, totaling 49 frames and 43,536 pixels. It covers the 39-block scene, raw and halo edits, registry remapping, far signed cells and empty views. The harness reports every field of each actual `K.Baked`, the retained binding appearance, texture headers and all original ARGB texels immediately after its same-process load. All 18 independently measured Java baked faces and 768 PNG texels match per palette; these diagnostics do not reconstruct an Assets owner. The 24 rejections cover every palette field and equality pair, malformed raw/mask/relative/read fields, pre-filter quad limits, missing bindings, invalid material slots, dimensions and an explicitly forged texture header. Each failure passes a baseline redraw with the retained owner. Forced test headers/bindings are restored only after recording the returned metadata; ordinary calls perform no test restoration. The returned bad-texture marker retains width zero and the returned missing-binding marker retains two bindings before restoration. Per-call metadata markers observe palette/count, bindings/root/sprite counts, usage and texture headers; they are not a deep serialization of every source/resolved catalog map field.

The native build succeeded in 585.70 seconds under its enforced 600-second process-group bound, without retries. The sampled physical footprint was 13.2 GiB and peak footprint 15.2 GiB; resident memory alone understated the swapped footprint. Complete emitted C was captured during the actual `-O3` clang invocation and remains retained byte-for-byte. The build receipt includes its exact bounded driver source, source/fixture pins, actual compiler flags, footprint observation and child cleanup. The slot was released after build, both native configurations and proof attempts had no live owned processes.

| Retained artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `build/world-resource-frame-tests` | 3,890,280 | `5b34bd0bc80cc2b7e8b95a7cff5679dcc6ebd62ca5c328980d2ffb3f99a98d12` |
| `build/world-resource-frame/emitted-program.c` | 11,351,562 | `9c16baa76d90f0dccd373ba2ff42ccff43a362ee33f496b98014b5032d3e2d19` |

Three source laws cover exact palette projection, rejection of a false palette guard, and preservation of a rejected scene message. The first two laws and exact palette-validation helpers passed export and the independent cached kernel in 0.14 seconds, with only module qualifications renamed. The third law has an ordinary witness only. The single full-production `--verdict` attempt was killed at its explicit 60-second cap; it produced no stdout/stderr and therefore establishes neither aggregate mathematical validity nor a specific diagnostic cause. No proof of the effectful loader, world sampler, renderer or full import graph is implied. The separately recorded existing aggregate JSON/kernel boundary remains distinct from this timed attempt.

The optional `snapshot_draw` world-owner facade passes ordinary checking but is not reached by this new native harness. Owned sampling itself has the frozen WorldVisibility evidence, and this suite consumes its sealed actual native outputs. This is an explicit composition boundary, not an assertion that this suite executed the optional facade or a visible client.

The declared domain is the four verified air/full-cube states with explicitly named zero-transform stone/dirt/oak-planks models, static normalized textures, Solid layers, white tint/light and existing CPU camera policy. General blockstate selection, contextual shapes, lighting/AO, biome tint, animated texture scheduling, stitched atlases, GPU/window lifecycle and full presentation remain outside this facade.
