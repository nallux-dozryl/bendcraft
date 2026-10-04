import Base
import ./generic_resource_world_sample_demand_laws.bend as L
import ./generic_resource_world_sample_demand.bend as D
import ./generic_resource_world_sample.bend as GS
import ./registry.bend as B
import ./resource_block_catalog.bend as C
import ./block_resources.bend as BR

def L.another_sample_registry_is_refused_before_registry_or_catalog_traversal(registry,admitted,declared,committed,tick,revision,origin,camera,cells,catalog_identity,entries,loaded,admission,limits,mismatch):
  %Equal.sym(Bool,String.eq(declared,admitted),False{},mismatch) :
    {D.gated(D.identity_first(_,admitted,declared,catalog_identity),D.Owner{registry,admitted,committed},
        GS.Sample{declared,tick,revision,origin,camera,cells},Some{C.Catalog{catalog_identity,entries,loaded}},admission,limits) ==
      (D.Owner{registry,admitted,committed},Fail{C.Error{"RegistryIdentityMismatch","catalog",declared ++ ":" ++ admitted}}) :
      D.Owner & Result<&2,&2,C.Error,D.Plan>}
  {==}

def L.initial_identity_refusal_preserves_the_complete_owner_before_decode(error,owner,sample,admission,limits): {==}
def L.initial_refuses_existing_commitments_without_inventing_a_catalog(owner,sample,admission,limits): {==}
def L.catalog_absence_uses_the_actual_registry_decode_and_returned_owner(registry,identity,committed,context,work,state): {==}

def L.prior_identity_refusal_retains_complete_registry_and_committed_inventory(owner,error,sample,catalog,admission,limits): {==}
def L.actual_identity_failure_keeps_the_returned_registry_and_full_inventory(registry,identity,committed,message,sample,catalog,admission,limits): {==}
def L.configuration_refusal_keeps_the_complete_owner_and_precise_error(owner,error,sample,catalog,admission,limits): {==}
def L.a_prior_traversal_error_stops_every_remaining_cell(cells,owner,context,error):
  match cells:
    case Nil{}: {==}
    case head <> tail: {==}
def L.a_repeated_raw_state_never_reenters_catalog_or_registry(owner,context,work,state): {==}
def L.an_already_demanded_sibling_family_adds_no_second_request(owner,context,work,name,state): {==}
def L.a_missing_committed_family_refuses_instead_of_reloading_forever(owner,context,work,name,state): {==}
def L.a_non_miss_lookup_refusal_retains_the_named_error_and_actual_owner(error,owner,context,work,state): {==}
def L.registry_decode_refusal_keeps_the_returned_owner_and_full_inventory(registry,identity,committed,error,context,work,state): {==}
def L.a_family_admission_refusal_never_mutates_the_committed_inventory(error,owner,work,name,mode): {==}
def L.an_absent_caller_mode_stays_an_explicit_named_refusal(name,state): {==}
def L.an_admitted_plan_preserves_prefix_addition_order_and_all_caller_materials(identity,committed,names,fallback,modes,materials,cells,families,catalog_limits,catalog,tail,seen_states,seen_families,reversed,count,allowed):
  %Equal.sym(Result<&2,&2,C.Error,Unit>,
    C.request_guard(List.append(&2,C.Request,committed,List.reverse(&2,C.Request,reversed)),catalog_limits),Done{Unit{}},allowed) :
    {D.plan_guarded(_,D.Plan{identity,List.append(&2,C.Request,committed,List.reverse(&2,C.Request,reversed)),List.reverse(&2,C.Request,reversed),materials}) ==
      Done{D.Plan{identity,List.append(&2,C.Request,committed,List.reverse(&2,C.Request,reversed)),List.reverse(&2,C.Request,reversed),materials}} :
      Result<&2,&2,C.Error,D.Plan>}
  {==}
