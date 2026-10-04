# Plan

Replace the generic client's one-time static-profile load with registry-backed
demand loading. Each correlated world sample supplies numeric state IDs; the
client resolves missing IDs through its actual retained registry, accumulates
block-family requests, and installs a complete replacement resource generation.
This is a source-derived implementation plan, not an implemented consumer delta
or a native acceptance result. Confidence is high for the existing API and
pinned-bytecode findings below; execution and latency remain unmeasured here.

## Scope

- In: `remote_resource_catalog_client.bend`, the generic native client owner
  loop, an additive demand-loader module, source-derived material classification,
  and named refusal/owner-preservation contracts.
- Out: mutation of frozen native generations, working `mesh_render.bend`, the
  compiler, or existing metadata/animation refusals. Resource packs, animation,
  fluid/block-entity renderers, Java position RNG, biome tint, lighting and final
  raster equivalence are separate dependencies.

## Existing consumer control points

The entry's `registry_loaded` currently calls
`RF.catalog_load(jar, registry, Profile.static_requests(),
Profile.static_policy(), Catalog.defaults())`. Its `catalog_loaded` destructures
the returned pair and discards the registry owner. The subsequent native loop
carries only `CW.Assets`; it cannot resolve later observed states or reload its
resources. This is the concrete consumer bound to remove.

`GenericClient.sampled` receives a correlated `Wire.CatalogFrameReply`, then
calls `snapshot_ready`. That function queries the menu, and `inventory_timed`
eventually calls `Draw.draw(sample, assets, width, height)`. Add demand admission
between the correlated reply and `snapshot_ready`, including the initial sample
handled by `starting`. Keep the existing real frame/menu/input/presentation
route after admission; an extra standalone loader test is not the consumer
change.

| Existing API | Contract relevant to demand loading |
| --- | --- |
| `Registry.Registry.identity(registry)` | Returns the affine registry and its canonical identity, including failure. Cache the admitted identity once. |
| `Registry.Registry.decode(registry, state_id)` | Returns the same affine registry plus `Resolved{protocol_id,name,state_id,assignments}` or the actual registry error. It searches validated state intervals and decodes exact property domains. |
| `Catalog.lookup(catalog, state_id)` | Returns an admitted entry, `StateNotLoaded`, or another structured catalog error. Only `StateNotLoaded` is a load demand. |
| `Catalog.Request{name,mode}` | Requests a registry block family. The loader retains every exact state and every variant/multipart dependency for that family. |
| `RF.catalog_load(jar,registry,requests,policy,limits)` | Returns `IO(Registry & Result<Catalog.Error,CW.Assets>)`; delegates to `resource_catalog_world_load.load`. |
| `CW.info(assets)` | Returns the sole `CW.Assets` owner alongside immutable catalog/texture-count metadata. |
| `Draw.draw(sample,assets,width,height)` | Returns the complete resource owner on frame/bind/render success or failure, but converts catalog errors to text. Do structured demand admission before this conversion. |
| `CW.close_assets(assets)` | Consumes one complete resource generation. Use for an obsolete or refused candidate, never before a replacement succeeds. |

## Action items

- [ ] **Retain the registry owner and loading configuration.** Add a demand
context containing the actual `Registry.Registry`, cached canonical identity,
configured JAR, accumulated name-to-`Catalog.Mode` requests, material-policy
inputs, resource limits and generation number. Keep its registry array affine;
do not reconstruct state names from numeric constants, a profile table or
`GS.Sample` appearance fields. Replace the entry's discarded registry with this
context. Startup derives requests from the initial sample rather than loading
the static profile as its product default.

- [ ] **Gather missing states from every admitted sample.** Check sample identity
against the retained registry identity before any state lookup or load. Validate
the sample, collect unique state IDs including air, and call `Catalog.lookup`
against the current catalog. For each `StateNotLoaded`, thread the complete
registry through `Registry.decode`, then deduplicate by the returned namespaced
block name. Merge those names into the accumulated request map. Repeated cells,
different states of one family, and an already-loaded family do not cause
duplicate requests or repeated loads. Propagate `InvalidState`, identity
mismatch and corrupt-entry errors; never turn them into demand or fallback
geometry.

- [ ] **Supply explicit renderer requirements from pinned sources.** The existing
`Profile.vanilla_mode` only names invisible air/cave-air/void-air, fluid water/lava,
and chest/trapped-chest/ender-chest block-entity refusals; other names take the
generic model path. It is not an exhaustive special-renderer provider.
`Registry.Block` does not retain render shape, fluid state or block-entity
requirements. Add pinned, source-derived requirements keyed to canonical
registry identity/state, or obtain those requirements from an admitted backend
provider. Distinguish an invisible block component from an absent fluid/entity
component. In particular, waterlogged model states need a separate fluid
requirement: `Catalog.Request.mode` is family-level and cannot express that
state-specific obligation. Refuse an unavailable observed component as
`UnsupportedRenderer` with its actual block/state and component name. Retain
`EmptyModelGeometry` for an unclassified generic model that bakes no faces;
never silently classify it as air.

- [ ] **Implement a face-level material provider before calling the path arbitrary
vanilla resource demand.** Resolve the actual model parents and texture aliases,
retain decoded source alpha, and classify each cuboid face's original/default UV
rectangle using the pinned rule below. Preserve material `force_translucent`
independently, including forced and unforced references to one sprite. The
current `BR.StaticNormalized{layers}` map and `K.Sprite.layer` assign one layer
per sprite, so they cannot represent arbitrary faces sampling different alpha
regions of one image. Add a classification input at `K.face_ready`, where
`K.face_uv(uv,direction,from,to)` still has those original/default coordinates;
do not infer classification from the transformed final `K.Baked` vertex UVs.
Preserve the existing explicit-layer API for its current consumers. A staged
demand adapter using that API must retain `Resource:MissingLayer` for unadmitted
sprites rather than inventing all-solid or whole-image classifications.

- [ ] **Reload the accumulated request set into a complete candidate.** Call the
existing loader with one deduplicated request list and the admitted complete
policy. Keep old `CW.Assets` live while loading. The returned registry replaces
the worker's prior registry on both outcomes; only successful loading proposes
new resources. Validate the candidate against an admitted current sample through
the real selection/bind/draw path. Commit requests and generation only after
success. On failure retain old requests/catalog/resources and return the exact
failure; close any successfully loaded but refused candidate. A replacement
must carry `R.Assets`, `Catalog.Catalog` and `texture_count` together: sorted
sprite insertion can change all existing texture slot numbers. Do not merge
catalog entries onto an old texture list or reuse old baked bindings by state.

- [ ] **Keep the main input/transport owner responsive during cold loads.** The
backend renews for 100 pulses; the real timer advances at 50 ms, and the transport
also has a 5000 ms read deadline. A blocking reload in the current client loop
can lose its renderer lease. Use the existing `IO.spawn`/`Chan` ownership pattern
for one loader worker: it exclusively owns the registry and candidate resources,
while the main loop owns `Window`, `Presenter.Link` and the old assets. Release
held controls through `Wire.Release` before an unavailable-resource wait; that
operation releases saved controls and renews the lease. Continue one correlated
request stream while polling worker completion. Re-query after a cold load,
coalesce newly observed family demands, and render only a sample admitted by the
installed generation. Never create another socket reader or share the registry
array. Closing must stop/drain the worker and consume every returned candidate.

- [ ] **Preserve named boundaries and deliberate budgets.** Do not relax
`Resource:UnsupportedAnimation`, `Resource:UnsupportedMetadata`, missing
blockstate/model/texture errors, missing tint, or unsupported bake operations.
Demand growth is governed by resource/work budgets, not the static profile's
state count. Current defaults still cap block and model requests at 256; catalog
limits permit at most 4096 blocks and 65535 states, while BR has independent
model/sprite/byte/pixel/side limits. Select production limits using measured
resource cost and retain the concrete `BlockBudget`, `StateBudget`,
`BlockstateByteBudget` and BR errors when exceeded. Do not silently drop older
families or truncate a sample to fit the catalog.

- [ ] **Verify actual composition and the real consumer delta.** Add laws against
the real demand transition and existing `Registry.decode`/loader interfaces for
identity-before-demand, duplicate-family coalescing, monotone committed requests,
failure retention of registry and old assets, and absence of partial swaps.
Validate a sequence of actual generic samples that first renders an arbitrary
supported block outside the profile, moves to a second newly demanded family,
returns to the first, and repeats without another load. Include invalid state,
unknown registry, unsupported renderer, metadata/animation, missing layer/tint,
budget, worker-stop and stale-generation cases. A targeted Java fixture must
sample opaque/cutout/translucent subrectangles of the same synthetic texture,
reversed UV endpoints, explicit/default UVs, and forced/unforced material uses;
compare actual `FaceBakery` quad layers, not a mirrored classifier. Test texture
slot reordering with a reload and exercise a load exceeding the lease interval
without sharing transport owners. Native/window jobs require separate heavy-job
coordination and leave frozen generations intact.

## Pinned layer authority and the existing Bend gap

The cached production declarations/bytecode are
`reference/cache/model-probe/official-javap.txt`, pinned by
`reference/model_semantics.json`. Its 1,311,304 bytes and SHA-256
`8a7cf5001d613280c5f23da84c3990c48eb0e631ca96d7098a41f709816629c7`
match the reference record. The installed `26.3.jar` has SHA-256
`4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d`;
the relevant cached source-class hashes match the actual installed class bytes.
These were checked by reading files only, with no Java/native process launched.

- `MaterialBaker.bakeForAtlas`, lines 19989–20004, resolves the sprite and copies
  `Material.forceTranslucent` into `Material.Baked`; it does not decide the
  cuboid face layer.
- `FaceBakery.computeMaterialTransparency`, lines 16247–16285, immediately
  returns `Transparency.TRANSLUCENT` when forced. Otherwise it supplies
  min/max original face UV components divided by 16 to
  `SpriteContents.computeTransparency`. `bakeQuad`, lines 16288–16314, obtains
  explicit or default face UVs before this classification.
- `SpriteContents.computeTransparency`, lines 10623–10742, uses cached
  transparency for an opaque image or the entire `(0,0,1,1)` rectangle.
  Otherwise its rectangle uses `floor(min*dimension)` and
  `ceil(max*dimension)`; the nonanimated path scans that source rectangle.
  The animated path aggregates the rectangle over referenced unique frames,
  which remains an unsupported loader requirement here.
- `NativeImage.computeTransparency`, lines 1797–1902, sets transparent for alpha
  zero and translucent for alpha other than zero or 255 in that rectangle. A
  non-RGBA native image returns no transparency.
- `BakedQuad.MaterialInfo.of`, lines 18827–18830, calls
  `ChunkSectionLayer.byTransparency`. The cached class bytecode at
  `build/mesh-layer-order-java/net.minecraft.client.renderer.chunk.ChunkSectionLayer.javap.txt`,
  lines 63–75, chooses `TRANSLUCENT` if any translucent alpha is present, then
  `CUTOUT` if transparent alpha is present, otherwise `SOLID`. Its source-class
  SHA-256 is `ff7872789c797fb1071c02659dc6cc1a201dfca91dfba3904ee65aebf8dd0ee6`.

The existing actual-Java `baked_variants` fixture in `model_semantics.json`
records six translucent glass quads (input model `minecraft:block/glass`) and
solid grass side bases with cutout side overlays. Its harness uses production
`NativeImage`, `SpriteContents`, `MaterialBaker` and `FaceBakery` with controlled
normalized sprite coordinates. Those samples support their own outcomes; the
production bytecode establishes the general rectangle rule. They do not provide
mixed-region texture acceptance evidence for a new Bend implementation.

Existing Bend semantics remain narrower: `B.Material` preserves the force flag;
`BR.layer_for` requires a caller-supplied sprite layer; `K.baked_ready` uses that
layer and upgrades forced materials to translucent. The loader rejects animation
and nonempty metadata sections. Source alpha classification is therefore a new
explicit input/implementation obligation, not behavior already supplied by
`StaticNormalized`, and a global sprite map alone is not arbitrary Java parity.

## Open questions

- Which exact pinned source provider will supply state-specific fluid/entity
  requirements absent from `Registry.Block` and `GS.Sample`? The small existing
  name classifier cannot be promoted to exhaustive renderer admission.
- How will the additive face-classification context retain source-alpha data
  alongside affine textures without introducing a second pixel owner or tying
  the policy to obsolete sprite slots? This requires a concrete Bend API design.
- What production resource limits and worker latency are supported on the target
  machine? The existing loader defaults and fixture timing are not that evidence.
