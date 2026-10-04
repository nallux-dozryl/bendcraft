import Base
import ./generic_resource_world_sample_laws.bend as L
import ./generic_resource_world_sample.bend as GS
import ./resource_block_catalog.bend as C
import ./resource_catalog_world.bend as CW
import ./block_resources.bend as BR
import ./blockstate_model.bend as S
import ./world_mesh.bend as WM
import ./client_world.bend as W
import ./client_render.bend as R
import ./movement.bend as MV

def L.another_registry_is_refused_before_sample_or_state_validation(declared,actual,tick,revision,origin,camera,cells,entries,loaded,mismatch):
  %Equal.sym(Bool,String.eq(declared,actual),False{},mismatch) :
    {GS.frame_gated(CW.identity_guard(_,declared,actual),GS.Sample{declared,tick,revision,origin,camera,cells},C.Catalog{actual,entries,loaded}) ==
      Fail{C.Error{"RegistryIdentityMismatch","catalog",declared ++ ":" ++ actual}} : Result<&2,&2,C.Error,CW.Frame>}
  {==}
def L.prior_registry_refusal_retains_the_exact_diagnostic(error,sample,catalog): {==}
def L.invalid_sample_is_refused_before_catalog_traversal(sample,catalog): {==}
def L.invisible_cells_do_not_consume_visible_binding_slots(point,state,selection,appearance,origin,tail): {==}
def L.a_single_model_choice_never_consumes_a_random_ticket(variant,seed): {==}
def L.a_zero_weight_total_is_refused_before_modulo(entries,seed): {==}
def L.an_absent_appearance_override_retains_the_complete_surface(values,key,surface): {==}
def L.traversal_refusal_retains_the_original_state_error(error,identity,tick,revision,camera): {==}
def L.an_empty_state_suffix_never_accesses_catalog_models(origin,catalog): {==}
