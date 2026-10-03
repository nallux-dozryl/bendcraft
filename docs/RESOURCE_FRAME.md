# Resource-to-frame adapter

`src/resource_frame.bend` connects the actual archive/model/PNG loader, pure model baker, camera-relative world mesh producer and BVH CPU renderer. It owns the resource textures across frames and returns that same affine owner on draw failures. Its current selection policy is explicitly the finite air/stone/dirt/oak-planks verification palette; it is an integration instrument within the full Minecraft 26.3 goal.

The full native suite passes twice on the exact retained draw, asset-audit and geometry executables. Each run checks eighteen configurations: four admitted resource loads and fourteen loader/palette rejections; 3,072 native texels against Pillow; 72 baked quad projections against actual Java CPU fixtures; 5,868 translated quad records; twenty-six frames / 33,792 RGB pixels and their RGBA readback CRCs; and ten draw/recovery pairs. All deterministic records agree between runs. `evidence/resource-frame-native.json` records `passed_bounded_domain`, with canonical report SHA-256 `6298aa5ec6dab6301aecc2d8a908b38bea05be9f796181d3f14c40de0b598409`. Runtime comparison passes took 10.301 and 8.749 seconds. Confidence is high within this explicitly bounded policy.

The first combined emission exceeded its 600-second bound without a binary. After separating the harness roots, fresh installed-compiler builds succeeded in 519.334 seconds (draw), 439.131 seconds (audit) and 291.043 seconds (geometry). Peak sampled physical footprints were 13.6G, 15.1G and 13.6G respectively. The exact draw and geometry C emissions were preserved before temporary cleanup. A read-only observer captured geometry's actual `clang -std=c11 -O3 … -lpthread -lm` invocation. Audit C and native sub-timings/invocation were missed between observations and remain explicitly unobserved; no re-emission was performed to fill that gap. Each phase has a separate build-profile receipt, and every native artifact has an exact source/preparation/hash receipt.

| Executable | Bytes | SHA-256 |
| --- | ---: | --- |
| `build/resource-frame-tests` | 3,669,656 | `258c2cc2da88961cf6419f9c8a810cbcbc82902a1d6a93fae9903910b0c5dae1` |
| `build/resource-frame-audit` | 3,742,184 | `00b741966ef112931a756c80ef56926b2df786f0c3b8d340417b0c55a893a153` |
| `build/resource-frame-geometry` | 3,776,328 | `7188132a8370caec8a2aa8aad8d652918c277da11df03016a8c3379e3d65cfd4` |

Initial draw diagnostics caught a custom test-error label mistake: invalid block origins return `WorldMesh:BlockOrigin:0` under the frozen producer contract, whereas the prepared fixture expected state 1. The original discrepancy is retained in `evidence/resource-frame-draw-diagnostic-mismatch.json`. The authorized correction changed only that expected label. `evidence/resource-frame-fixture-correction.json` proves identical executable-facing semantic inputs, input archive hashes, native binary and Java/pixel expectations before and after. The corrected draw cases and the final combined suite passed on the retained executables without recompilation or fixture regeneration.

The checkpoint validates the declared resource-to-frame algorithm. It does not establish production atlas, world-light, GPU or final vanilla-frame equivalence. Full Minecraft scope continues beyond this integration instrument.

## API and ownership

```text
Palette { air, stone, dirt, planks: U32 }                 # immutable Data
Info { bindings: List<WorldMesh.Binding>, texture_count: U32,
       palette: Palette, catalog: BlockResources.Catalog } # immutable Data
Assets { resources: ClientRender.Assets,
         bindings: List<WorldMesh.Binding>, texture_count: U32,
         palette: Palette, catalog: BlockResources.Catalog } # affine Type

load(jar: String, Palette) -> IO(Result<String, Assets>)
draw(ClientRender.Snapshot, Assets, width, height)
    -> Assets & Result<String, Image>
info(Assets) -> Assets & Info
close_assets(Assets) -> IO(Unit)
```

The root adapter maps the actual validated `ClientWorld.Palette` fields into this lightweight type. ResourceFrame deliberately avoids importing the complete world/game/server graph. State IDs are caller supplied; all four must be distinct. Duplicate IDs reject before archive IO. Air is omitted from the bindings, because valid world snapshots omit air. An air or unknown state in an input block list rejects through WorldMesh rather than acquiring placeholder geometry.

`load` requests the actual `minecraft:block/stone`, `minecraft:block/dirt` and `minecraft:block/oak_planks` model closures through BlockResources. It uses the frozen `StaticNormalized` policy with an explicit Solid caller mapping for those three fixture materials. Each resolved root is baked with `BlockBake.State{0,0,0,false}` and the actual catalog sprite context. Geometry, parent resolution, texture aliases and canonical texture slots therefore come from parsed resources and the baker. No cube vertices, UVs or texture bytes are hardcoded by this adapter.

The resulting bindings follow stone/dirt/planks state order; texture IDs/slots follow the loader's canonical ordering: dirt 0, oak planks 1, stone 2 for the official input. The adapter reads the texture count from the catalog sprite list. `Info` exposes bindings, palette, resolved/source models, sprites, metadata and context so a later visibility adapter can consume their Data values without cloning the texture owner.

`draw` calls `WorldMesh.produce` with the snapshot, retained bindings, actual texture count, requested dimensions and default producer limits. A successful scene goes to accelerated `MeshRender.render`. Producer and renderer errors retain Assets; the caller can correct the next snapshot and draw again. Errors use `WorldMesh:<code>:<state>` or `Render:<code>`. Load errors use `Resource:<code>:<resource>:<message>`, `Bake:<kind>:<detail>` or `Palette:DuplicateState`.

The archive is already closed by BlockResources before a successful load returns. The textures are managed Bend Image trees and retain no file or GPU handles. `close_assets` consumes their affine owner and releases its references; it performs no additional archive or GPU close operation. Baker failures after a resource load also consume the loaded image owner before returning the error.

## Explicit rendering policy

This adapter fixes these verification inputs:

- Zero model transform, UV lock false and three explicitly selected model IDs.
- Normalized full-image sprites, static textures, explicit Solid layer mapping.
- White tint/light, default cardinal shade, clamp addressing, backface culling and cutout threshold 128.
- Existing MeshRender near/far/lens/background defaults and WorldMesh finite bounds.

Cardinal shade factors and baked geometry are measured against the production Java CPU baker. The current integer RGB calculations, white illumination, camera lens, ray renderer and normalized texture layout are this instrument's declared policies. They do not reproduce vanilla AO, biome tint, lightmap, production atlas stitching, mipmap sampling, GPU rasterization, sRGB/blending or final frames. Nonempty `.mcmeta` stays rejected by the frozen loader, including glass's `mipmap_strategy=mean`.

Stone and dirt have actual weighted/rotated blockstate variants. This module deliberately selects the named unrotated models; it does not apply general blockstate, multipart, weighted random or position-seed selection. The separate measured Blockstate/ModelChoice path is the dependency for that later integration.

A snapshot must already be in the finite camera-relative frame: camera XYZ zero, and block origins produced by F64 world-cell minus F64 camera subtraction **before** F32 narrowing. ResourceFrame does not reconstruct world authority or repair already narrowed absolute coordinates. The native test driver performs the same explicit F64 subtraction for its far-coordinate fixture inputs; the authoritative ClientWorld/shared-actor path has separate integration evidence.

## Independent verification

```sh
python3 tools/test_resource_frame.py --prepare-only
# After a compiler slot is granted, build narrow phases separately:
python3 tools/test_resource_frame.py --skip-kernel --build-only --phase draw
python3 tools/test_resource_frame.py --skip-kernel --build-only --phase audit
python3 tools/test_resource_frame.py --skip-kernel --build-only --phase geometry
# An exact transitive-source/binary stamp is mandatory for reuse:
python3 tools/test_resource_frame.py --skip-kernel --reuse-build
```

The accepted preparation is sealed in `build/resource-frame/preparation.json`. Build-only, reuse and ordinary execution phases validate and retain existing `cases.json` and ZIP bytes; they never regenerate them. Validation binds the runner and transitive Bend/compiler hashes, official client and Java reference, registry inventory, Pillow version, executable-facing semantic inputs, expected labels, archive byte/member/content hashes, and independently recomputed pixel/quad expectations. Missing or stale preparation fails explicitly and requires `--prepare-only`. That flag deliberately creates and seals a fresh preparation.

`evidence/resource-frame-preparation-retention.json` records the one-time adoption of the exact successful draw generation and nine rejection checks for missing files/manifests, stale labels, changed content/provenance/source/pixels/archive hashes and a damaged seal. All eleven independent oracle function ASTs, case bytes, archive bytes and the retained draw executable stayed unchanged. Exact draw-artifact reuse was exercised with no emission or fixture rewrite.

The narrow native driver imports no other Bend test module and no ClientWorld/Game/Server module. Three generated ignored entry wrappers call its draw, asset-audit and geometry roots. The draw root contains the complete resource-to-frame path and retains one Assets owner through each configuration's frames and recovery cases. The asset and translated-geometry diagnostics run in separate loads under the same exact production source generation; their comparisons do not claim readback from the draw root's internal owner. All three entries must pass before the complete report is accepted. It receives source archive paths, state bindings and snapshots. It never receives expected Java geometry or image bytes. The Python runner supplies independent reference comparisons only.

The verified suite has 18 configurations: four successful resource loads and fourteen load/palette rejections. Successful loads cover the official jar, a ZIP containing the exact required official resource subset, and two arbitrary state-ID remaps including U32 extremes. Each compares all 18 actual Java zero-transform baked quads and every byte of the three Pillow-decoded RGBA textures. The official palette is `[0,1,10,15]` under the pinned registry inventory.

There are 26 successful views and ten draw rejection/recovery pairs. Views include the 39-block finite scene, edited blocks, tick-only changes, camera movement/look, an empty snapshot, 32×24/64×48/128×96 images, and camera-relative inputs around positive and negative 30 million. Exact translated vertex/UV words are compared against the actual Java fixture. Independent NumPy ray/triangle, UV sampling and color arithmetic compares every produced RGB pixel and the Bend RGBA readback CRC. Far translations and tick-only changes must preserve the baseline image; edited/moved/look views must change it.

Draw failures cover unknown/air state, absolute or NaN camera, invalid dimensions, NaN block origin, translated geometry bounds, quad budget and an explicitly forged invalid texture header. The last fixture forces a failure in MeshRender after successful world-mesh production; the driver restores the original Data header without replacing the texture image owner. Every rejection is followed by a baseline draw with that retained owner, and its pixels must match. Loader failures cover missing archive/model/texture, malformed model JSON, parent cycle, PNG CRC, frozen metadata rejection, unsupported element Euler bake and all six palette-ID equality pairs.

The native draw-only run measured the 39-block baseline at 2 ms for 32×24, 8 ms for 64×48 and 26 ms for 128×96 (representative first-run values). Measurements time `draw` plus forced RGBA readback/CRC and its short checksum print; PPM file output follows the end timestamp. This gives a bounded practical scene cost, not Minecraft FPS or a comparison with Java's complete renderer. Both native runs must agree on all deterministic records, excluding elapsed times. Source/dependency and binary hashes are checked before and after execution.

This is a window-free CPU pipeline test with `BEND_MINECRAFT_LAUNCH_MODE=hidden`. Actual hidden presentation is owned by the root integration. Visible OS input/presentation acceptance and final vanilla frame comparisons remain required by the project contract.
