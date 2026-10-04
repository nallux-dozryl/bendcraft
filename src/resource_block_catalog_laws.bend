import Base
import ./resource_block_catalog.bend as C
import ./resource_block_catalog_load.bend as CL
import ./registry.bend as G
import ./blockstate_model.bend as S
import ./block_resources.bend as BR
import ./block_bake.bend as K
import ./world_mesh.bend as WM
import ./client_render.bend as R

law failed_lookup_preserves_complete_registry:
  for registry:G.Registry
  for +error:G.Error
  for mode:C.Mode
  {C.looked_up((registry,Fail{error}),mode) == (registry,Fail{C.Error{"Registry","registry",G.error_text(error)}}) : G.Registry & Result<&2,&2,C.Error,C.Block>}

law successful_lookup_preserves_complete_registry_and_metadata:
  for registry:G.Registry
  for +metadata:G.Block
  for +mode:C.Mode
  {C.looked_up((registry,Done{metadata}),mode) == (registry,Done{C.Block{metadata,mode}}) : G.Registry & Result<&2,&2,C.Error,C.Block>}

law unsupported_mode_refuses_arbitrary_renderer:
  for +name:String
  for +renderer:String
  {C.mode_guard(C.Unsupported{renderer},name) == Fail{C.Error{"UnsupportedRenderer",name,renderer}} : Result<&2,&2,C.Error,Unit>}

law missing_state_model_refuses_state_identity:
  for +name:String
  for +state:U32
  {C.root_required(None{},name,state) == Fail{C.Error{"MissingStateModel",name,U32.show(state)}} : Result<&2,&2,C.Error,S.Root>}

law blockstate_transform_maps_all_rotation_and_uvlock_fields:
  for model:String
  for +x:U32
  for +y:U32
  for +z:U32
  for +lock:Bool
  {C.variant_state(S.Variant{model,x,y,z,lock}) == K.State{x,y,z,lock} : K.State}

law bound_binding_preserves_full_identity_and_requested_state:
  for +protocol:U32
  for +name:String
  for +state:U32
  for +properties:List<&2,G.Assignment>
  for mode:C.Mode
  for root:Maybe<&2,S.Root>
  for +variants:List<&2,S.Variant>
  for +baked:List<&2,K.Baked>
  for +appearance:WM.Appearance
  {C.bound_entry(C.Entry{G.Resolved{protocol,name,state,properties},mode,root},variants,baked,appearance) == C.Bound{G.Resolved{protocol,name,state,properties},variants,WM.Binding{state,baked,appearance}} : C.Bound}

law invisible_state_has_no_geometry_for_arbitrary_tickets:
  for identity:G.Resolved
  for root:Maybe<&2,S.Root>
  for selection:C.Selection
  {C.selected(C.Entry{identity,C.Invisible{},root},selection) == Done{Nil{}} : Result<&2,&2,C.Error,List<&2,S.Variant>>}

law weighted_choice_requires_owned_random_ticket:
  for entries:List<&2,S.Weighted>
  for total:U32
  for +name:String
  {C.ticket(S.WeightedChoice{entries,total},None{},name) == Fail{C.Error{"MissingRandomTicket",name,"weighted model choice needs an explicit ticket"}} : Result<&2,&2,C.Error,S.Variant>}

law single_choice_ignores_unneeded_random_ticket:
  for +variant:S.Variant
  for ticket:Maybe<&2,U32>
  for name:String
  {C.ticket(S.Single{variant},ticket,name) == Done{variant} : Result<&2,&2,C.Error,S.Variant>}

law unloaded_state_refuses_arbitrary_catalog_entries:
  for entries:Map<&2,C.Entry>
  for +state:U32
  {C.lookup_found(False{},entries,state) == Fail{C.Error{"StateNotLoaded","catalog",U32.show(state)}} : Result<&2,&2,C.Error,C.Entry>}

law load_installs_complete_texture_owner_and_catalog:
  for assets:R.Assets
  for +loaded_catalog:BR.Catalog
  for +identity:String
  for +entries:Map<&2,C.Entry>
  {CL.resources_loaded(Done{BR.Loaded{assets,loaded_catalog}},identity,entries) == Done{CL.Loaded{assets,C.Catalog{identity,entries,loaded_catalog}}} : Result<&2,&1,C.Error,CL.Loaded>}

law load_failure_preserves_precise_resource_diagnostic:
  for +code:String
  for +name:String
  for +detail:String
  for identity:String
  for entries:Map<&2,C.Entry>
  {CL.resources_loaded(Fail{BR.Error{code,name,detail}},identity,entries) == Fail{C.Error{"Resource:" ++ code,name,detail}} : Result<&2,&1,C.Error,CL.Loaded>}

law preparation_refusal_preserves_complete_registry:
  for +error:C.Error
  for registry:G.Registry
  for requests:List<&2,C.Request>
  {CL.prepare_guarded(Fail{error},registry,requests) == (registry,Fail{error}) : G.Registry & Result<&2,&2,C.Error,CL.Prepared>}

law mismatched_entry_refuses_requested_state:
  for entry:C.Entry
  for +state:U32
  {C.state_identity_guard(False{},entry,state) == Fail{C.Error{"StateIdentityMismatch","catalog",U32.show(state)}} : Result<&2,&2,C.Error,C.Entry>}
