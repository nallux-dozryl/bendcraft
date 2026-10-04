# Registry-backed block resource catalog

The new catalog connects the existing registry, blockstate dispatcher, resource
loader and model baker. A resource request names registry **blocks**, rather than
three selected model files. Every state of each requested block retains its
protocol block ID, namespaced block name, numeric state ID, ordered exact
property assignments and compiled variant/multipart root. The catalog retains
the original `BlockResources.Catalog` and canonical registry identity.

The catalog is generic. The included static profile is a useful pinned 26.3
consumer configuration, not its API's supported-name whitelist. Custom registry
names, property domains, resource namespaces, variants, weighted choices and
multipart conditions pass through the actual existing production modules.

## API

`src/resource_block_catalog.bend` provides pure preparation, lookup, selection
and baking. `src/resource_block_catalog_load.bend` owns archive IO and returns
the complete registry owner. `src/resource_block_catalog_profile.bend` supplies
an independently grounded static profile and a bridge for state-indexed meshes.

```text
C.Request { name: String, mode: Model | Invisible | Unsupported(renderer) }
C.Limits { max_blocks, max_states, max_state_text: U32, resources: BR.Limits }
C.Entry { identity: Registry.Resolved, mode: C.Mode, root: Maybe<Blockstate.Root> }
C.Catalog { registry_identity: String, entries: Map<C.Entry>,
            loaded_catalog: BlockResources.Catalog }
CL.Loaded { assets: ClientRender.Assets, catalog: C.Catalog }  # affine owner
C.Selection { variant_ticket: Maybe<U32>, part_tickets: Map<U32> }
C.Bound { identity: Registry.Resolved, variants: List<Blockstate.Variant>,
          binding: WorldMesh.Binding }

CL.load(jar, registry, requests, policy, limits)
  -> IO(Registry & Result<C.Error, CL.Loaded>)
C.lookup(catalog, state_id) -> Result<C.Error, C.Entry>
C.bind(catalog, state_id, selection, appearance) -> Result<C.Error, C.Bound>
C.binding(catalog, state_id, selection, appearance)
  -> Result<C.Error, WorldMesh.Binding>
CP.preview_bindings(catalog, appearance)
  -> Result<C.Error, List<WorldMesh.Binding>>
```

`CL.load` returns the same affine registry owner on successful and failed
preparation/load outcomes. It reads exact `assets/<namespace>/blockstates/*.json`
ZIP entries, checks the aggregate blockstate text budget before each read,
instantiates selectors against all exact registry states, and rejects decoder,
overlap and missing-state-model diagnostics. It loads every model dependency of
each compiled root, including alternatives that the current ticket does not
select. Its blockstate archive closes before `BR.load` opens the model/texture
archive; every failure path closes the archive owner.

`C.bind` selects the exact root for the requested state. Single variants need no
ticket. Weighted variants require an explicit bounded ticket; each weighted
selected multipart part requires a ticket indexed by its original part number.
Invalid tickets retain the existing blockstate dispatch error. Each selected
model is resolved from the retained loaded catalog and baked with its actual
`x/y/z/uvlock` transform. Multipart quads retain part/model order. The resulting
`WorldMesh.Binding.state` comes from the retained registry identity, and a
catalog key with a different embedded identity is rejected. A generic model
whose bake has no geometry returns `EmptyModelGeometry`; callers must identify
invisible or special-rendered blocks explicitly.

`C.first_selection` and `CP.preview_bindings` deliberately select ticket zero.
This gives existing state-indexed mesh consumers a complete deterministic
binding list. It is an explicit preview policy: Java's position-dependent RNG
does not belong to this helper. Per-position consumers call `C.bind` with their
own selection tickets and world appearance. Neither catalog API advances a
simulation tick or owns the caller's RNG.

## Pinned static profile

`CP.static_requests()` includes invisible air and the eleven blocks below. The
129 static block components therefore produce 130 catalog entries including
air, 33 model closure nodes and twelve static 16×16 sprites. Models and pixels
are read from the user's local installation and are not committed.

| Block | First state | State count | Relevant properties |
| --- | ---: | ---: | --- |
| stone | 1 | 1 | Weighted mirrored/rotated models |
| dirt | 10 | 1 | Weighted rotations |
| oak_planks | 15 | 1 | None |
| cobblestone | 14 | 1 | None |
| sand | 121 | 1 | Weighted rotations |
| bricks | 3832 | 1 | None |
| grass_block | 8 | 2 | snowy |
| oak_log | 139 | 3 | axis |
| oak_slab | 15177 | 6 | type, waterlogged |
| oak_stairs | 5463 | 80 | facing, half, shape, waterlogged |
| oak_fence | 8635 | 32 | east, north, south, waterlogged, west |

`CP.static_policy()` gives the grass side overlay `Cutout` and the other eleven
sprites `Solid`. Snowy grass uses `grass_block_snow` sides without tint.
Nonsnowy grass includes a tinted top and four tinted side overlays. The caller
must provide appearance tint index 0 from its biome/world state when rendering.
Waterlogged states retain their exact property identity but the static binding
contains the block component; fluid geometry remains a separate renderer.

`CP.vanilla_mode` explicitly classifies air/cave-air/void-air as invisible,
water/lava as unsupported fluid renderers, and chest/trapped-chest/ender-chest
as unsupported block-entity renderers. Other names use the generic model path
and its concrete loader/bake diagnostics. This small classifier does not claim
to enumerate every vanilla special renderer. Glass reaches the existing
`Resource:UnsupportedMetadata` boundary for its texture mipmap metadata; its
model independently records `force_translucent=true`. Treating glass as an
opaque cube or treating particle-only water/chest models as visible geometry
would contradict the pinned resources.

## Consumer integration

The resource-frame owner can replace its three hardcoded model roots and zero
transform binding loop with `CL.load(...,CP.static_requests(),CP.static_policy(),
C.defaults())`, then `CP.preview_bindings(catalog,appearance)`. Retain
`C.Catalog` in `RF.Assets` and `RF.Info`; obtain the texture count from
`catalog.loaded_catalog.sprites`. Keep the returned registry owner attached to
the existing world/engine. Resource-frame draw failure continues to return the
same texture owner; the catalog's Data metadata can be borrowed across frames.

The current `ClientWorld.material` admits only its historical air/stone/dirt/
planks palette, and `WorldVisibility` derives cube-neighbor masks from that
palette. Root consumer integration must generalize those admissions and
shape-aware visibility to render the new states through `WorldResourceFrame`.
Alternatively, a prepared raw snapshot can already pass the catalog bindings
to `WorldMesh.produce`. Catalog support and a state-indexed preview binding list
do not establish expanded live-world visibility or per-position variant RNG.

## Evidence and remaining execution

`reference/resource_block_catalog.json` records all 170 states of fourteen
blocks from fresh executions of the pinned official 26.3 Java dispatcher and
state APIs. Two independent Java runs reproduced exactly. State IDs/property
maps agree with official reports and the generated registry TSV. Model texture,
face, layer and tint summaries also agree with 110 previous Java production
bakes. The additional 41 states are chest (24), water (16) and glass (1), each
classified with its concrete unsupported dependency. Extraction and reproduction
commands are:

```sh
python3 tools/resource_block_catalog_reference.py
python3 tools/resource_block_catalog_reference.py --verify
/Users/chuah/.bend/bin/bend src/resource_block_catalog_proof.bend --check-only
/Users/chuah/.bend/bin/bend src/resource_block_catalog_profile.bend --check-only
```

All production sources and the fourteen contracts pass ordinary checking.
`evidence/resource-block-catalog-kernel.json` records independent-kernel
acceptance of the unchanged 765,300-byte selected declaration closure, with
zero exclusions: 9.241 seconds export and 0.141 seconds kernel checking. The
contracts establish complete registry/texture owner preservation, explicit
renderer and state-identity refusal, exact diagnostic retention, and transform/
binding identity mapping over arbitrary fields. They do not prove archive IO,
PNG decoding, IEEE geometry, Java RNG or final rendered frame parity.

The native harness is being added separately to exercise the actual loader and
binder against all static states and concrete failure cases. Native execution
and root live-client integration remain pending at this source/proof checkpoint.
Lighting, biome tint, fluid/block-entity geometry, atlas/mipmap sampling,
position randomness and actual visible client acceptance retain their own
production obligations.
