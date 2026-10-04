import Base
import ./resource_block_catalog_laws.bend as L
import ./registry.bend as G

def L.failed_lookup_preserves_complete_registry(registry,error,mode): {==}
def L.successful_lookup_preserves_complete_registry_and_metadata(registry,metadata,mode): {==}
def L.unsupported_mode_refuses_arbitrary_renderer(name,renderer): {==}
def L.missing_state_model_refuses_state_identity(name,state): {==}
def L.blockstate_transform_maps_all_rotation_and_uvlock_fields(model,x,y,z,lock): {==}
def L.bound_binding_preserves_full_identity_and_requested_state(protocol,name,state,properties,mode,root,variants,baked,appearance): {==}
def L.invisible_state_has_no_geometry_for_arbitrary_tickets(identity,root,selection):
  match identity:
    case G.Resolved{protocol,name,state,properties}: {==}
def L.weighted_choice_requires_owned_random_ticket(entries,total,name): {==}
def L.single_choice_ignores_unneeded_random_ticket(variant,ticket,name):
  match ticket:
    case None{}: {==}
    case Some{value}: {==}
def L.unloaded_state_refuses_arbitrary_catalog_entries(entries,state): {==}
def L.load_installs_complete_texture_owner_and_catalog(assets,loaded_catalog,identity,entries): {==}
def L.load_failure_preserves_precise_resource_diagnostic(code,name,detail,identity,entries): {==}
def L.preparation_refusal_preserves_complete_registry(error,registry,requests): {==}
def L.mismatched_entry_refuses_requested_state(entry,state): {==}
