This is the production visual projection and resource-backed ItemEntity /
ExperienceOrb preparation for the pinned Java26.3 entity owner. Confidence is
high in the independently observed receiver formulas and immutable ownership
seams. All production/resource/receiver declarations pass the original ordinary
checker, and14implementation-connected laws pass the independent kernel with
zero exclusions. The actual Java reference covers4resource bakes,72item clusters
and22XP billboards. Native resource comparison is prepared but currently blocked
by original C-producer expansion in shared block_model.int_scan_admitted; the
precise retained trace is evidence/item-entity-render-source.json. No successful
C/native pixel or transform parity is claimed yet. Verification receipts keep
floating-point and integration boundaries explicit; this is not a finished
vanilla renderer.

The live consumer must use the actual Session's existing entity owner and one
atomic world/entity capture. The additive wire DTO is defined in
`src/item_entity_render_model.bend`:

```text
Common{dimension,id,current:Vec3<F64>,old:Vec3<F64>,tick_count,
       removed,accessible,source_order}
Record = Item{common,full Inv.Slot,bob:F32} | Orb{common,value}
Snapshot = Unbound{} | Bound{records:List<Record>}
Model.render_snapshot(E.View) -> Snapshot
Render.render_snapshot(E.View) -> Snapshot  # forwarding compatibility alias
Render.prepare_snapshot(Context,Snapshot,L.Tables)
  -> L.Tables & Result<Error,Frame>
Render.prepare(Context,E.View,L.Tables) -> L.Tables & Result<Error,Frame>
Render.capture(Context,E.State,L.Tables)
  -> E.State & L.Tables & Result<Error,Frame>
```

Unbound refuses explicitly; Bound with an empty list is a real empty frame.
Projection preserves the existing record sequence and source-order field,
including removed/inaccessible records, and preparation filters those records
and other dimensions. It neither advances ticks nor reads/changes entity RNG,
UUID/factory cursors, health, pickup timers, inventory owners, or tick sidecars.
Interpolation uses `V.Fields.position_old` (Java xOld/yOld/zOld), not position_o
(xo/yo/zo). F64 interpolation and camera subtraction happen before F32 narrowing.
Visual age is signed tickCount + partialTick, independent of item despawn age.

Context supplies the actual dimension, F64 camera origin, partialTick in[0,1],
actual camera billboard quaternion, exact-key Catalog, settled per-ID block/sky
light levels and evaluated RGB lightmap samples, and caller work budgets. The
caller must not fabricate white light, an identity camera or partialTick0 for
normal gameplay. `Light.item_rgb` is the actual item lightmap evaluation;
`Light.orb_rgb` is its evaluation after the Java orb block-light boost of7,
clamped to15. Packed light is retained in Draw diagnostics. Current mesh rendering
accepts RGB rather than vanilla shader packed-light evaluation; actual normal /
block-light shading remains the shader/scene consumer seam. Camera quaternion
components are checked finite, while actual normalized camera admission belongs
to the capture consumer. Scan budget charges every published source record.
Quad budget prevents publication of a partial frame, but currently checks after
geometry preparation; resource and source-snapshot admission must also bound
allocation. These execution budgets are not product entity/item limits.

`Resources.load(installedJar,Definitions.Catalog,fullKeys,BR.Limits)` returns an
affine `Resources.Assets{textures:R.Assets,catalog:Model.Catalog}`. It requires
actual initialized defaults, authenticates complete key identity using the
existing component admission, reads actual ITEM_MODEL / DAMAGE and registry ID,
and resolves the installed `assets/<namespace>/items/...json` and model parents.
Requests are generic over registered exact keys; the four oracle items are test
inputs, never a product ID whitelist. Render copy seed is registry ID + effective
DAMAGE. A local newly seeded LegacyRandomSource supplies copy offsets without
consuming simulation RNG. Copy counts are the actual1/2/3/4/5 thresholds, and
flat-versus-volume copy offsets use actual transformed model depth.

Supported client item dispatch is direct `minecraft:model` without dynamic tint
providers. Normal cuboid models reuse real block_model/block_bake parsing,
inheritance, UVs, rotations and materials. Generated models follow the actual
26.3 ItemModelGenerator: front/back planes at7.5/8.5, one exposed side face per
actual nonzero-alpha pixel,0.1pixel UV inset, up to five contiguous resource
layers. Side iteration is deterministic rather than Java's unordered side set;
geometry comparisons therefore compare the complete vertex/UV multiset. Ground
translation and scale are inherited and applied once. Nonzero ground-display
rotation explicitly refuses pending the general resource display-quaternion
provider; it is not silently discarded. Animated sprite metadata refuses until
an animation/frame-union owner exists. Fractional alpha in a nontranslucent bake
refuses until actual material classification is supplied. Explicit translucent
materials preserve their alpha path.

Selectors/composites/special item models, dynamic tints and foil/glint explicitly
refuse. Missing initialized defaults, missing exact-key ground models, unknown
light samples, and absent actual orb atlas also refuse. These are concrete
missing providers, not fallback cubes or substitute item sprites. Item body
shadows, outline/fire/name-tag passes, full GPU shader behavior, and complete
vanilla item-model coverage are outside this module's implemented body pass.

XP preparation uses actual getIcon value thresholds, the installed
`minecraft:entity/experience/experience_orb`64x64 atlas,16x16 UV regions, camera
billboard quaternion,0.3 scale and0.1 upward translation. Mth sine comes from the
existing hash-verified affine numerical table. Actual red/green/blue/alpha is
sin-based red,255,sin-based blue,128. Item bob uses that same table; spin uses the
actual ItemEntity.getSpin formula. JOML's half-angle quaternion path is implemented
with native F32 sine and the pinned cosFromSin arithmetic. Native sinf versus
Java `(float)Math.sin(double)` and pre-applying ground geometry versus composing
matrices are named numerical boundaries to be measured in the prepared native comparison; they
are not part of a raw-bit parity claim or the pure kernel proof.

`Resources.inspect` lends the immutable catalog while returning its sole asset
owner. `Resources.draw(Frame,Assets,camera,settings,width,height)` feeds real
mesh_render geometry and installed textures and returns that same owner. The
live world consumer must join world and entity quads into **one** existing mesh
scene and **one** shared texture owner. A separate atlas requires explicit slot
remapping/rebinding on every world resource swap; texture_count alone is not a
generation identity. Assign deterministic global orders, validate actual slots,
and charge the existing shared mesh/translucent budgets before publication.
A separate RGB overlay would lose world occlusion. Lead owns this join, the
atomic Session/GS.Sample capture, strict wire codec/budgets and presentation.
No E.View may be fabricated from the reduced visual DTO. NativeControls and
Motion consume the actual typed Snapshot directly as described in
`docs/generic_resource_world_sample_item_entities.md`.

Reproducible focused commands are:

```text
python3 tools/reference_item_entity_render.py
python3 tools/test_item_entity_render.py
python3 tools/test_item_entity_render_proof.py
```

The reference invokes actual installed ItemModelGenerator / FaceBakery /
ItemClusterRenderState / ItemEntityRenderer copy submissions and
ExperienceOrbRenderer CPU geometry callbacks. A controlled normalized UV atlas
avoids GPU/client activation; this is not vanilla atlas stitching. The registry
and all item component initializers are actual pinned Java receivers. Source,
jar, metadata and library hashes are recorded; no proprietary PNGs, jars or
binaries are committed. Kernel receipts preserve all original checked terms and
verify actual production projection/refusal/material laws. Native/Java and pixel
boundaries remain distinct from proof and from live wire/world/OS acceptance.
