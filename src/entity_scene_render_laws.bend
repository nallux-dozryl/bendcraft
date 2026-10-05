import Base
import ./entity_scene_render_model.bend as A
import ./entity_scene_render_assets.bend as Assets
import ./entity_scene_render.bend as Scene
import ./client_render.bend as R
import ./resource_block_catalog.bend as C
import ./resource_catalog_world.bend as CW
import ./item_entity_render_resources.bend as IR
import ./item_entity_render_model.bend as D
import ./mesh_render.bend as M
import ./world_mesh.bend as WM
import ./locomotion.bend as L
import ./remote_entity_frame.bend as EF
import ./remote_entity_snapshot_wire.bend as Wire

law texture_prefix_split_is_exact:
  for +prefix:List<&2,R.Texture>
  for +suffix:List<&2,R.Texture>
  {Assets.split_images(List.length(&2,R.Texture,prefix),List.append(&2,R.Texture,prefix,suffix)) == (prefix,suffix) : List<&2,R.Texture> & List<&2,R.Texture>}

law joined_owner_can_recover_both_complete_original_owners:
  for world_images:List<&2,R.Texture>
  for item_images:List<&2,R.Texture>
  for world:C.Catalog
  for wc:U32
  for items:D.Catalog
  {Assets.split(Assets.assemble(CW.Assets{R.Assets{world_images},world,wc},IR.Assets{R.Assets{item_images},items})) == (CW.Assets{R.Assets{world_images},world,wc},IR.Assets{R.Assets{item_images},items}) : CW.Assets & IR.Assets}

law failed_texture_admission_retains_both_owners:
  for world:CW.Assets
  for items:IR.Assets
  {Assets.admitted(False{},world,items) == A.Rejected{world,items,A.Refused{"scene:invalid physical texture domain"}} : A.Join}
def failed_texture_admission_retains_both_owners(world,items): {==}

law texture_rebasing_preserves_every_material_field:
  for slot:U32
  for tint:U32
  for light:U32
  for shade:F32
  for mode:M.Mode
  for address:M.Address
  for base:U32
  {Scene.rebase_material(M.Material{slot,tint,light,shade,mode,address},base) == M.Material{U32.add(base,slot),tint,light,shade,mode,address} : M.Material}
def texture_rebasing_preserves_every_material_field(slot,tint,light,shade,mode,address,base): {==}

law composition_preserves_vertices_uv_culling_and_uses_global_order:
  for a:M.Vertex
  for b:M.Vertex
  for c:M.Vertex
  for d:M.Vertex
  for material:M.Material
  for cull:M.Cull
  for old_order:U32
  for base:U32
  for global_order:U32
  {Scene.rebase_quad(M.Quad{a,b,c,d,material,cull,old_order},base,global_order) == M.Quad{a,b,c,d,Scene.rebase_material(material,base),cull,global_order} : M.Quad}
def composition_preserves_vertices_uv_culling_and_uses_global_order(a,b,c,d,material,cull,old_order,base,global_order): {==}

law sampled_light_retains_all_other_world_appearance:
  for tints:List<&2,WM.Tint>
  for old:U32
  for address:M.Address
  for cull:M.Cull
  for nether:Bool
  for threshold:U32
  for rgb:U32
  {Scene.appearance(WM.Appearance{tints,old,address,cull,nether,threshold},rgb) == WM.Appearance{tints,rgb,address,cull,nether,threshold} : WM.Appearance}
def sampled_light_retains_all_other_world_appearance(tints,old,address,cull,nether,threshold,rgb): {==}

law missing_light_authority_cannot_publish_a_scene:
  for reason:String
  for stamp:Wire.Stamp
  {Scene.lighting_ready(A.Missing{reason},stamp) == Fail{A.Refused{"scene:light authority unavailable:" ++ reason}} : Result<&2,&2,A.Error,A.Lighting>}
def missing_light_authority_cannot_publish_a_scene(reason,stamp): {==}

law missing_world_light_cannot_become_fullbright:
  for cells:Map<&2,Maybe<&2,A.WorldLight>>
  for state:U32
  {Scene.world_light((cells,None{}),state) == Fail{A.Refused{"scene:actual world light sample missing"}} : Result<&2,&2,A.Error,U32>}
def missing_world_light_cannot_become_fullbright(cells,state): {==}

law no_entities_preserves_existing_world_accumulator:
  for wc:U32
  for ec:U32
  for limits:WM.Limits
  for acc:WM.Accumulator
  {Scene.append_entities([],wc,ec,limits,acc) == Done{acc} : Result<&2,&2,A.Error,WM.Accumulator>}
def no_entities_preserves_existing_world_accumulator(wc,ec,limits,acc): {==}

law mismatched_publication_retains_numerical_owner:
  for context:A.Context
  for frame:EF.Frame
  for catalog:C.Catalog
  for wc:U32
  for items:D.Catalog
  for ec:U32
  for tables:L.Tables
  {Scene.prepare_gate(False{},context,frame,catalog,wc,items,ec,tables) == (tables,Fail{A.Refused{"scene:atomic publication stamp mismatch"}}) : L.Tables & Result<&2,&2,A.Error,A.Prepared>}
def mismatched_publication_retains_numerical_owner(context,frame,catalog,wc,items,ec,tables): {==}

law preparation_failure_preserves_full_physical_owner:
  for resources:R.Assets
  for catalog:C.Catalog
  for wc:U32
  for prefix:Nat
  for items:D.Catalog
  for ec:U32
  for tables:L.Tables
  for error:A.Error
  {Scene.prepare_owned((tables,Fail{error}),resources,catalog,wc,prefix,items,ec) == (A.Assets{resources,catalog,wc,prefix,items,ec},tables,Fail{error}) : A.Assets & L.Tables & Result<&2,&2,A.Error,A.Prepared>}
def preparation_failure_preserves_full_physical_owner(resources,catalog,wc,prefix,items,ec,tables,error): {==}

law failed_preparation_performs_no_render_and_retains_both_owners:
  for assets:A.Assets
  for tables:L.Tables
  for error:A.Error
  for width:U32
  for height:U32
  {Scene.draw_prepared((assets,tables,Fail{error}),width,height) == (assets,tables,Fail{error}) : A.Assets & L.Tables & Result<&2,&2,A.Error,Image>}
def failed_preparation_performs_no_render_and_retains_both_owners(assets,tables,error,width,height): {==}
