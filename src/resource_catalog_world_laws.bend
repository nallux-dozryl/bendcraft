import Base
import ./resource_catalog_world.bend as CW
import ./resource_block_catalog.bend as C
import ./block_resources.bend as BR
import ./block_model.bend as B
import ./blockstate_model.bend as S
import ./block_bake.bend as K
import ./registry.bend as G
import ./world_mesh.bend as WM
import ./mesh_render.bend as M
import ./client_render.bend as R

law metadata_view_preserves_the_complete_texture_owner:
  for resources:R.Assets
  for +catalog:C.Catalog
  for +textures:U32
  {CW.info(CW.Assets{resources,catalog,textures}) ==
    (CW.Assets{resources,catalog,textures},CW.Info{catalog,textures}) : CW.Assets & CW.Info}

law scene_refuses_another_registry_before_any_binding:
  for +declared:String
  for +actual:String
  for +tick:Nat
  for +revision:Nat
  for +instances:List<&2,CW.Instance>
  for +camera:R.Camera
  for +entries:Map<&2,C.Entry>
  for +loaded:BR.Catalog
  for +textures:U32
  for +render:WM.Frame
  for +limits:WM.Limits
  for mismatch:{String.eq(declared,actual) == False{} : Bool}
  {CW.scene(CW.Frame{declared,tick,revision,instances,camera},C.Catalog{actual,entries,loaded},textures,render,limits) ==
    Fail{C.Error{"RegistryIdentityMismatch","catalog",declared ++ ":" ++ actual}} : Result<&2,&2,C.Error,M.Scene>}

law prior_identity_refusal_is_not_replaced_by_frame_or_model_errors:
  for +error:C.Error
  for frame:CW.Frame
  for catalog:C.Catalog
  for textures:U32
  for render:WM.Frame
  for limits:WM.Limits
  {CW.scene_gated(Fail{error},frame,catalog,textures,render,limits) == Fail{error} : Result<&2,&2,C.Error,M.Scene>}

law invalid_frame_refusal_precedes_instance_traversal:
  for +error:C.Error
  for frame:CW.Frame
  for catalog:C.Catalog
  for textures:U32
  for render:WM.Frame
  for limits:WM.Limits
  {CW.scene_configured(Fail{error},frame,catalog,textures,render,limits) == Fail{error} : Result<&2,&2,C.Error,M.Scene>}

law an_empty_instance_suffix_preserves_all_accumulated_geometry:
  for catalog:C.Catalog
  for textures:U32
  for limits:WM.Limits
  for blocks:U32
  for bindings:U32
  for +acc:WM.Accumulator
  {CW.instances(Nil{},catalog,textures,limits,blocks,bindings,acc) == Done{acc} : Result<&2,&2,C.Error,WM.Accumulator>}

law exhausted_block_budget_refuses_before_catalog_access:
  for x:F32
  for y:F32
  for z:F32
  for +state:U32
  for material:U32
  for selection:C.Selection
  for appearance:WM.Appearance
  for tail:List<&2,CW.Instance>
  for catalog:C.Catalog
  for textures:U32
  for limits:WM.Limits
  for bindings:U32
  for acc:WM.Accumulator
  {CW.instances(CW.Instance{R.Block{x,y,z,state,material},selection,appearance} <> tail,catalog,textures,limits,0,bindings,acc) ==
    Fail{C.Error{"WorldMesh:BlockLimit","world",U32.show(state)}} : Result<&2,&2,C.Error,WM.Accumulator>}

law exhausted_binding_budget_refuses_before_catalog_access:
  for x:F32
  for y:F32
  for z:F32
  for +state:U32
  for material:U32
  for selection:C.Selection
  for appearance:WM.Appearance
  for tail:List<&2,CW.Instance>
  for catalog:C.Catalog
  for textures:U32
  for limits:WM.Limits
  for acc:WM.Accumulator
  {CW.instances(CW.Instance{R.Block{x,y,z,state,material},selection,appearance} <> tail,catalog,textures,limits,1,0,acc) ==
    Fail{C.Error{"WorldMesh:BindingLimit","world",U32.show(state)}} : Result<&2,&2,C.Error,WM.Accumulator>}

law cell_binding_uses_its_explicit_selection_and_appearance:
  for +x:F32
  for +y:F32
  for +z:F32
  for +state:U32
  for +material:U32
  for +selection:C.Selection
  for +appearance:WM.Appearance
  for +catalog:C.Catalog
  for acc:WM.Accumulator
  for textures:U32
  for limits:WM.Limits
  for +error:C.Error
  for refused:{C.bind(catalog,state,selection,appearance) == Fail{error} : Result<&2,&2,C.Error,C.Bound>}
  {CW.instance(CW.Instance{R.Block{x,y,z,state,material},selection,appearance},catalog,acc,textures,limits) ==
    Fail{error} : Result<&2,&2,C.Error,WM.Accumulator>}

law binding_admission_failure_does_not_advance_the_accumulator:
  for +error:C.Error
  for block:R.Block
  for binding:WM.Binding
  for acc:WM.Accumulator
  for textures:U32
  for limits:WM.Limits
  {CW.bound_checked(Fail{error},block,binding,acc,textures,limits) == Fail{error} : Result<&2,&2,C.Error,WM.Accumulator>}

law invalid_origin_retains_the_requested_registry_state:
  for +x:F32
  for +y:F32
  for +z:F32
  for +state:U32
  for +material:U32
  for binding:WM.Binding
  for acc:WM.Accumulator
  for textures:U32
  for limits:WM.Limits
  for refused:{WM.block_bound(R.Block{x,y,z,state,material}) == False{} : Bool}
  {CW.bound_checked(Done{Unit{}},R.Block{x,y,z,state,material},binding,acc,textures,limits) ==
    Fail{C.Error{"WorldMesh:BlockOrigin","world",U32.show(state)}} : Result<&2,&2,C.Error,WM.Accumulator>}

# The actual cell path must pass the complete incoming accumulator, appearance,
# translated origin, and state to the baker. Its premises are subsystem outcomes,
# rather than an alternate implementation or assumptions about geometry values.
law admitted_cell_extends_the_existing_accumulator:
  for identity:G.Resolved
  for variants:List<&2,S.Variant>
  for +baked:List<&2,K.Baked>
  for +appearance:WM.Appearance
  for +x:F32
  for +y:F32
  for +z:F32
  for +state:U32
  for +material:U32
  for +acc:WM.Accumulator
  for +textures:U32
  for +blocks:U32
  for +bindings:U32
  for +quads:U32
  for +layers:U32
  for +tints:U32
  for +next:WM.Accumulator
  for checked:{WM.bindings_check(WM.Binding{state,baked,appearance} <> Nil{},textures,1,quads,tints) == Done{Unit{}} : Result<&2,&2,String,Unit>}
  for origin:{WM.block_bound(R.Block{x,y,z,state,material}) == True{} : Bool}
  for generated:{WM.baked_produce(baked,appearance,M.Vec3{x,y,z},acc,textures,WM.Limits{blocks,bindings,quads,layers,tints},state) == Done{next} : Result<&2,&2,WM.Error,WM.Accumulator>}
  {CW.instance_bound(Done{C.Bound{identity,variants,WM.Binding{state,baked,appearance}}},R.Block{x,y,z,state,material},acc,textures,WM.Limits{blocks,bindings,quads,layers,tints}) ==
    Done{next} : Result<&2,&2,C.Error,WM.Accumulator>}

law world_mesh_errors_retain_the_exact_state:
  for +code:String
  for +state:U32
  {CW.mesh_result(WM.Accumulator,Fail{WM.Error{code,state}}) ==
    Fail{C.Error{"WorldMesh:" ++ code,"world",U32.show(state)}} : Result<&2,&2,C.Error,WM.Accumulator>}

law scene_failure_preserves_the_complete_assets_owner:
  for +error:C.Error
  for assets:CW.Assets
  for width:U32
  for height:U32
  {CW.produced(Fail{error},assets,width,height) == (assets,Fail{error}) : CW.Assets & Result<&2,&2,C.Error,Image>}

law render_failure_preserves_the_complete_assets_owner:
  for resources:R.Assets
  for +catalog:C.Catalog
  for +textures:U32
  for +code:String
  {CW.rendered((resources,Fail{M.Error{code}}),catalog,textures) ==
    (CW.Assets{resources,catalog,textures},Fail{C.Error{"Render:" ++ code,"scene",""}}) : CW.Assets & Result<&2,&2,C.Error,Image>}

law render_success_preserves_the_complete_assets_owner_and_image:
  for resources:R.Assets
  for +catalog:C.Catalog
  for +textures:U32
  for +image:Image
  {CW.rendered((resources,Done{image}),catalog,textures) ==
    (CW.Assets{resources,catalog,textures},Done{image}) : CW.Assets & Result<&2,&2,C.Error,Image>}

law sprite_metadata_retains_loaded_texture_slot_order:
  for identity:String
  for entries:Map<&2,C.Entry>
  for roots:List<&2,String>
  for source:Map<&2,B.Model>
  for models:Map<&2,B.Resolved>
  for +sprites:List<&2,BR.SpriteInfo>
  for context:K.Context
  for usage:BR.Usage
  for textures:U32
  {CW.sprite_infos(CW.Info{C.Catalog{identity,entries,BR.Catalog{roots,source,models,sprites,context,usage}},textures}) ==
    sprites : List<&2,BR.SpriteInfo>}

law an_empty_admitted_frame_retains_camera_and_render_settings:
  for identity:String
  for tick:Nat
  for revision:Nat
  for +camera:R.Camera
  for catalog:C.Catalog
  for textures:U32
  for width:U32
  for height:U32
  for +settings:M.Settings
  for limits:WM.Limits
  {CW.scene_configured(Done{Unit{}},CW.Frame{identity,tick,revision,Nil{},camera},catalog,textures,WM.Frame{width,height,settings},limits) ==
    Done{M.Scene{camera,Nil{},settings}} : Result<&2,&2,C.Error,M.Scene>}

law a_zero_shared_quad_budget_refuses_the_next_quad:
  for a:M.Vertex
  for b:M.Vertex
  for c:M.Vertex
  for d:M.Vertex
  for material:M.Material
  for cull:M.Cull
  for order:U32
  for reversed:List<&2,M.Quad>
  for translucent:U32
  for blocks:U32
  for bindings:U32
  for layers:U32
  for tints:U32
  for +state:U32
  {CW.mesh_result(WM.Accumulator,WM.add_valid(True{},M.Quad{a,b,c,d,material,cull,order},WM.Accumulator{reversed,0,translucent},WM.Limits{blocks,bindings,0,layers,tints},state)) ==
    Fail{C.Error{"WorldMesh:QuadLimit","world",U32.show(state)}} : Result<&2,&2,C.Error,WM.Accumulator>}
