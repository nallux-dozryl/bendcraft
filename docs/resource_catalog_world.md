# Generic catalog world frames

`src/resource_catalog_world.bend` binds each present world cell through the real registry-state catalog, then extends one frame-wide `WM.Accumulator`. Each `Instance` carries the actual `R.Block`, explicit `C.Selection` and `WM.Appearance`; repeated states may choose different weighted models or cell tints. Catalog entries that are absent from the frame are not baked or checked for world tint requirements.

`CW.Assets` has one `R.Assets` texture owner, the complete loaded `C.Catalog`, and its material-context texture count. `CW.Info` exposes retained catalog identity and sprite slot metadata while returning that same owner. A `CW.Frame` carries registry identity, tick, revision, cells and relative camera; draw rejects another registry before configuration or catalog access. Tick and revision are retained metadata, not simulation scheduling.

The actual `src/resource_frame.bend` now exposes:

- `catalog_load(jar, registry, requests, policy, limits)` returns the complete registry owner together with `CW.Assets` or the exact catalog error.
- `catalog_info(assets)` returns the assets owner and catalog metadata.
- `catalog_draw(frame, assets, width, height, limits)` returns the assets owner and an image or precise catalog/world/render error.
- `catalog_close(assets)` releases its managed texture images.

The existing five-field RF owner and four-field metadata shapes are preserved for HUD, menu and legacy clients. Root owns the `world_resource_frame.bend` consumer adapter and actor/wire adoption. In particular, the current `remote_resource_client` still uses the three-state resource palette and its version-1 sample wire does not carry generic registry identity, per-cell appearance or weighted selection. This adapter does not change world visibility, occlusion or collision classification. Fluids, special entity renderers, unsupported animations and material metadata remain explicit catalog/resource rejections; waterlogged static geometry does not render its fluid.

Budget admission checks registry identity, frame/camera, then per-cell block and binding allowances before accessing a state. Binding allowance counts cells, including invisible cells, rather than distinct states. The shared accumulator charges total quad and translucent budgets and preserves sequential world order. Binding validation applies to the current cell only; an unused grass entry cannot reject an untinted stone frame.

## Verification

The 18 `resource_catalog_world_laws` and loader failure-owner law are arbitrary pure contracts for identity/error precedence, complete owner return, explicit selection/appearance pass-through, accumulator composition, shared budget refusal and sprite slot retention. Their subsystem premises identify actual bake/admission outcomes; they do not assert unproved geometric or raster fidelity. The checked original declarations and proof terms are retained by the selective exporter. All 19 current selected roots passed the independent kernel with zero exclusions; see `evidence/resource_catalog_world_kernel_002.json`. The prior 18-law receipt is retained separately.

Reproduce in a fresh output directory:

```sh
mkdir build/resource-catalog-world-kernel-fresh
/opt/homebrew/bin/node --stack-size=4096 --experimental-transform-types tools/resource_catalog_world_proof.mjs build/resource-catalog-world-kernel-fresh
/Users/chuah/.bend/bendtt/e15042434e73aab0/bendtt build/resource-catalog-world-kernel-fresh/selected.bendtt
```

`tests/resource_catalog_world.bend` uses the actual RF catalog loader and world draw route. Its ordinary source check passed. `tools/resource_catalog_world_test.py prepare` prepares 18 frames: 11 successful geometry/pixel cases and seven diagnostic/owner-return cases. The Java reference supplies exact selected vertex/UV/material words, and official pinned 26.3 textures feed the existing independent binary32/Pillow ray oracle. Geometry is compared as a multiset because Java quad groups do not retain source element/face order; native sequential order is checked separately. The current corpus selects only Java-observed variants. Across the larger static profile, 123 states plus air have geometry observations, while six states (three oak logs, cobblestone, sand and bricks) do not.

The native build uses the previously measured private queue/zero-available-arity producer, exact immutable project/foreign source copies and bounded process groups. Original `comp.ts`/`bend.ts` remain untouched. The first immutable build passed (249.368 seconds emission, 39.610 seconds compilation; 5.48 GiB sampled peak RSS). Its first native run passed all 11 successful geometry/pixel cases but failed the exact invalid-origin diagnostic: existing `WM.bound_block` supplied state zero instead of the requested state. That failed run and build are retained. The current CW admission wrapper now retains the actual state before invoking the admitted WM path; the additional arbitrary actual-path law proves this refusal behavior. Corrected generation 002 native verification is pending the coordinated two-heavy-job window.

```sh
python3 tools/resource_catalog_world_test.py prepare --generation 2
python3 tools/resource_catalog_world_test.py build --generation 2
python3 tools/resource_catalog_world_test.py run --generation 2
```

The tool preserves each preparation/build generation and refuses equivalent retries. Use a fresh `--generation` number after a source correction; preparations, native attempts and failure receipts are preserved. The two additional loader-refusal cases verify registry owner return for unsupported fluid and duplicate requests before an intentionally absent archive can be opened.

## Known composition gap

Grass side base and cutout overlay quads are coplanar. Current production sequential ordering lets the solid base win the depth tie. The old renderer host fixture helper inserted a cutout priority; the new world oracle explicitly removes that fixture rule and verifies current composition. The first unbuilt preparation is retained with the correction receipt in `evidence/resource_catalog_world_oracle_correction.json`. This is a known layer-order defect, not a Java final-raster fidelity result; a separate `mesh_layer_order*` investigation owns that correction. No actor/wire, fluid, occlusion, GPU or presentation parity is claimed here.
