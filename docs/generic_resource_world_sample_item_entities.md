This is the concrete additive item-entity join for the generic client, prepared
while generic006 builds. It does not change that demand/Actor017 baseline or
claim entity-render acceptance. Confidence is high in the inspected ownership
and composition boundaries; the wire projection, item resources and lighting
suppliers below remain prerequisites.

The existing renderer boundary is
`item_entity_render.prepare(Context,E.View,L.Tables) -> L.Tables & Result<Error,Frame>`.
Frame exposes ordered draws and real `mesh_render.Quad`s. Its capture API returns
the actual `E.State` alongside tables and result. The production Session read is
`local_player_session.cooking_entities(State) -> State & Maybe<EntityRecovery>`;
EntityRecovery contains the observed View plus clock inputs. A renderer query
must retain the returned Session and project the observed records. It must not
install a copied owner or expose simulation RNG/clock queues over the render wire.

Parent-owned additive projection APIs are the appropriate next seam:

```text
RenderModel.render_snapshot(E.View) -> RenderModel.Snapshot
ItemRender.prepare_snapshot(Context,Snapshot,Tables)
  -> Tables & Result<Error,Frame>
```

Snapshot needs an explicit Unbound case. Each bound record must preserve actual
dimension/id, current and old F64 position words, tick count, removed and
accessible flags and source order. Items additionally need their complete Slot
and bob F32; orbs need their value. These are the fields the current renderer
uses. A reduced DTO cannot be reconstructed as E.View without inventing omitted
metadata. NativeControls owns strict encoding, validation and reply-budget
admission; oversized snapshots require a named refusal, never silent truncation.
Its proposed separate command20/reply9 is not an implemented protocol claim.

Motion owns the real Session/Scene capture. Prefer one atomic immutable reply
holding the existing GS.Sample and render Snapshot with actual dimension and
timing/context, after one normal realtime step and without an intervening step.
Separate tag13/tag20 queries otherwise need an actual shared capture stamp and
mismatch refusal: epoch/sequence, world tick and block revision alone do not
prove that an entity carrier was unchanged. The context must supply actual
interpolation partial and billboard orientation. Derive camera origin from the
exact pose-aware sample origin. Existing transforms interpolate/subtract in F64
before narrowing; preserve that behavior rather than converting absolute world
positions to F32 or supplying a fixed eye height.

The client must retain one complete affine owner:

```text
JoinedAssets{
  world:ResourceSession.Session,
  tables:NumericalTables.Tables,
  items:RenderModel.Catalog,
  committed_items:ItemResourceLedger
}
```

Initialize the numerical tables through their existing checked loader. Every
resource, draw, failure and close continuation must thread or consume the entire
owner. Catalog's immutable geometry and `texture_count` do not identify an atlas
generation or own textures. Bind item slots to the same actual texture/context
generation as world assets. Prefer one union resource load from all committed
block roots plus source-resolved item roots, producing both catalogs from one
BR.Loaded texture owner. `resource_block_catalog_load.source_after_close` is the
existing concrete root-plan seam immediately before BR.load. Parent owns actual
26.3 item dispatch/generated geometry loading and inherited ground-transform
application. If a separate atlas is used, explicit slot remapping and rebinding
on every world swap are required. Failed candidates retain the previous complete
owner and both ledgers; publish only after combined frame admission.

World and entity geometry must share one render:

```text
Frame.draw_frame(world_sample,world_info)
  -> CW.instances(...,empty_accumulator)
ItemRender.prepare_snapshot(context,entity_snapshot,tables)
  -> append validated item/orb quads with one stable global order
  -> WM.finish(shared_accumulator,sample.camera,settings)
  -> Mesh.render(scene,the_same_texture_owner,width,height)
  -> existing HUD/menu composition -> Window.frame
```

Do this at GenericClient's actual correlated snapshot/resource/menu/draw chain,
replacing its world-only Session.draw after coherent resource admission. Separate
RGB overlays lose world occlusion; fake CW.Instances misroute entities through
block-state selection. Item copies currently preserve local quad orders and orb
quads use order0, while mesh tie-breaking uses distance/order/index. Assign one
deterministic global order and charge the shared4096-quad/64-translucent budgets,
validating every material slot against the real shared atlas. Entity diagnostics
must not invent block state IDs. HUD icons remain a separate consumer.

Current Context also requires actual per-ID settled block/sky levels and RGB
lightmap samples. GS.Sample has none of those. Packed light is diagnostic state,
not a replacement for material RGB. Preserve current exact-ground-model,
settled-light/lightmap, orb-atlas, camera/interpolation and budget refusals until
the real suppliers exist. Do not supply white light, default partial/quaternion,
all-solid materials or inferred alpha layers to make a fixture draw. Arbitrary
item dispatch, generated geometry, special models and foil/glint remain explicit
resource/renderer work. This plan does not gate generic006 demand acceptance or
the current cooking actor consumer.
