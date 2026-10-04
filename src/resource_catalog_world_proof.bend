import Base
import ./resource_catalog_world_laws.bend as L
import ./resource_catalog_world.bend as CW
import ./resource_block_catalog.bend as C
import ./block_resources.bend as BR
import ./blockstate_model.bend as S
import ./block_bake.bend as K
import ./registry.bend as G
import ./world_mesh.bend as WM
import ./mesh_render.bend as M
import ./client_render.bend as R

def L.metadata_view_preserves_the_complete_texture_owner(resources,catalog,textures): {==}

def L.scene_refuses_another_registry_before_any_binding(declared,actual,tick,revision,instances,camera,entries,loaded,textures,render,limits,mismatch):
  %Equal.sym(Bool,String.eq(declared,actual),False{},mismatch) :
    {CW.scene_gated(CW.identity_guard(_,declared,actual),CW.Frame{declared,tick,revision,instances,camera},C.Catalog{actual,entries,loaded},textures,render,limits) ==
      Fail{C.Error{"RegistryIdentityMismatch","catalog",declared ++ ":" ++ actual}} : Result<&2,&2,C.Error,M.Scene>}
  {==}

def L.prior_identity_refusal_is_not_replaced_by_frame_or_model_errors(error,frame,catalog,textures,render,limits): {==}
def L.invalid_frame_refusal_precedes_instance_traversal(error,frame,catalog,textures,render,limits): {==}
def L.an_empty_instance_suffix_preserves_all_accumulated_geometry(catalog,textures,limits,blocks,bindings,acc): {==}
def L.exhausted_block_budget_refuses_before_catalog_access(x,y,z,state,material,selection,appearance,tail,catalog,textures,limits,bindings,acc): {==}
def L.exhausted_binding_budget_refuses_before_catalog_access(x,y,z,state,material,selection,appearance,tail,catalog,textures,limits,acc): {==}

def L.cell_binding_uses_its_explicit_selection_and_appearance(x,y,z,state,material,selection,appearance,catalog,acc,textures,limits,error,refused):
  %Equal.sym(Result<&2,&2,C.Error,C.Bound>,C.bind(catalog,state,selection,appearance),Fail{error},refused) :
    {CW.instance_bound(_,R.Block{x,y,z,state,material},acc,textures,limits) == Fail{error} : Result<&2,&2,C.Error,WM.Accumulator>}
  {==}

def L.binding_admission_failure_does_not_advance_the_accumulator(error,block,binding,acc,textures,limits): {==}

def L.admitted_cell_extends_the_existing_accumulator(identity,variants,baked,appearance,x,y,z,state,material,acc,textures,blocks,bindings,quads,layers,tints,next,checked,origin,generated):
  %Equal.sym(Result<&2,&2,String,Unit>,WM.bindings_check(WM.Binding{state,baked,appearance} <> Nil{},textures,1,quads,tints),Done{Unit{}},checked) :
    {CW.bound_checked(CW.binding_check(_,state),R.Block{x,y,z,state,material},WM.Binding{state,baked,appearance},acc,textures,WM.Limits{blocks,bindings,quads,layers,tints}) ==
      Done{next} : Result<&2,&2,C.Error,WM.Accumulator>}
  %Equal.sym(Bool,WM.block_bound(R.Block{x,y,z,state,material}),True{},origin) :
    {CW.mesh_result(WM.Accumulator,WM.bound_block(_,R.Block{x,y,z,state,material},Some{WM.Binding{state,baked,appearance}},acc,textures,WM.Limits{blocks,bindings,quads,layers,tints})) ==
      Done{next} : Result<&2,&2,C.Error,WM.Accumulator>}
  %Equal.sym(Result<&2,&2,WM.Error,WM.Accumulator>,WM.baked_produce(baked,appearance,M.Vec3{x,y,z},acc,textures,WM.Limits{blocks,bindings,quads,layers,tints},state),Done{next},generated) :
    {CW.mesh_result(WM.Accumulator,_) == Done{next} : Result<&2,&2,C.Error,WM.Accumulator>}
  {==}

def L.world_mesh_errors_retain_the_exact_state(code,state): {==}
def L.scene_failure_preserves_the_complete_assets_owner(error,assets,width,height): {==}
def L.render_failure_preserves_the_complete_assets_owner(resources,catalog,textures,code): {==}
def L.render_success_preserves_the_complete_assets_owner_and_image(resources,catalog,textures,image): {==}
def L.sprite_metadata_retains_loaded_texture_slot_order(identity,entries,roots,source,models,sprites,context,usage,textures): {==}
def L.an_empty_admitted_frame_retains_camera_and_render_settings(identity,tick,revision,camera,catalog,textures,width,height,settings,limits):
  match limits:
    case WM.Limits{blocks,bindings,quads,layers,tints}: {==}
def L.a_zero_shared_quad_budget_refuses_the_next_quad(a,b,c,d,material,cull,order,reversed,translucent,blocks,bindings,layers,tints,state): {==}
