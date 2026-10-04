import Base
import ./generic_resource_world_sample_demand.bend as D
import ./generic_resource_world_sample.bend as GS
import ./registry.bend as B
import ./resource_block_catalog.bend as C
import ./block_resources.bend as BR
import ./movement.bend as MV
import ./client_render.bend as R

law another_sample_registry_is_refused_before_registry_or_catalog_traversal:
  for registry:B.Registry
  for +admitted:String
  for +declared:String
  for +committed:List<&2,C.Request>
  for +tick:Nat
  for +revision:Nat
  for +origin:MV.Vec3
  for +camera:R.Camera
  for +cells:List<&2,GS.Cell>
  for +catalog_identity:String
  for +entries:Map<&2,C.Entry>
  for +loaded:BR.Catalog
  for +admission:D.Admission
  for +limits:D.Limits
  for mismatch:{String.eq(declared,admitted) == False{} : Bool}
  {D.collect(D.Owner{registry,admitted,committed},GS.Sample{declared,tick,revision,origin,camera,cells},
      C.Catalog{catalog_identity,entries,loaded},admission,limits) ==
    (D.Owner{registry,admitted,committed},Fail{C.Error{"RegistryIdentityMismatch","catalog",declared ++ ":" ++ admitted}}) :
    D.Owner & Result<&2,&2,C.Error,D.Plan>}

law prior_identity_refusal_retains_complete_registry_and_committed_inventory:
  for owner:D.Owner
  for error:C.Error
  for sample:GS.Sample
  for catalog:Maybe<&2,C.Catalog>
  for admission:D.Admission
  for limits:D.Limits
  {D.gated(Fail{error},owner,sample,catalog,admission,limits) == (owner,Fail{error}) :
    D.Owner & Result<&2,&2,C.Error,D.Plan>}

law actual_identity_failure_keeps_the_returned_registry_and_full_inventory:
  for registry:B.Registry
  for identity:String
  for committed:List<&2,C.Request>
  for message:String
  for sample:GS.Sample
  for catalog:Maybe<&2,C.Catalog>
  for admission:D.Admission
  for limits:D.Limits
  {D.identified((registry,Fail{message}),identity,committed,sample,catalog,admission,limits) ==
    (D.Owner{registry,identity,committed},Fail{C.Error{"RegistryIdentity","registry",message}}) :
    D.Owner & Result<&2,&2,C.Error,D.Plan>}

law configuration_refusal_keeps_the_complete_owner_and_precise_error:
  for owner:D.Owner
  for error:C.Error
  for sample:GS.Sample
  for catalog:Maybe<&2,C.Catalog>
  for admission:D.Admission
  for limits:D.Limits
  {D.prepared(Fail{error},owner,sample,catalog,admission,limits) == (owner,Fail{error}) :
    D.Owner & Result<&2,&2,C.Error,D.Plan>}

law a_prior_traversal_error_stops_every_remaining_cell:
  for cells:List<&2,GS.Cell>
  for owner:D.Owner
  for context:D.Context
  for error:C.Error
  {D.collect_cells(cells,owner,context,Fail{error}) == (owner,Fail{error}) :
    D.Owner & Result<&2,&2,C.Error,D.Work>}

law a_repeated_raw_state_never_reenters_catalog_or_registry:
  for owner:D.Owner
  for context:D.Context
  for work:D.Work
  for state:U32
  {D.state_seen(True{},owner,context,work,state) == (owner,Done{work}) :
    D.Owner & Result<&2,&2,C.Error,D.Work>}

law an_already_demanded_sibling_family_adds_no_second_request:
  for owner:D.Owner
  for context:D.Context
  for work:D.Work
  for name:String
  for state:U32
  {D.family_seen(True{},owner,context,work,name,state) == (owner,Done{work}) :
    D.Owner & Result<&2,&2,C.Error,D.Work>}

law a_missing_committed_family_refuses_instead_of_reloading_forever:
  for owner:D.Owner
  for context:D.Context
  for work:D.Work
  for name:String
  for state:U32
  {D.family_committed(True{},owner,context,work,name,state) ==
    (owner,Fail{C.Error{"CommittedFamilyMissing",name,U32.show(state)}}) :
    D.Owner & Result<&2,&2,C.Error,D.Work>}

law a_non_miss_lookup_refusal_retains_the_named_error_and_actual_owner:
  for error:C.Error
  for owner:D.Owner
  for context:D.Context
  for work:D.Work
  for state:U32
  {D.missing_lookup(False{},error,owner,context,work,state) == (owner,Fail{error}) :
    D.Owner & Result<&2,&2,C.Error,D.Work>}

law registry_decode_refusal_keeps_the_returned_owner_and_full_inventory:
  for registry:B.Registry
  for identity:String
  for committed:List<&2,C.Request>
  for error:B.Error
  for context:D.Context
  for work:D.Work
  for state:U32
  {D.decoded((registry,Fail{error}),identity,committed,context,work,state) ==
    (D.Owner{registry,identity,committed},Fail{C.Error{"Registry","registry",B.error_text(error)}}) :
    D.Owner & Result<&2,&2,C.Error,D.Work>}

law a_family_admission_refusal_never_mutates_the_committed_inventory:
  for error:C.Error
  for owner:D.Owner
  for work:D.Work
  for name:String
  for mode:C.Mode
  {D.family_admitted(Fail{error},owner,work,name,mode) == (owner,Fail{error}) :
    D.Owner & Result<&2,&2,C.Error,D.Work>}

law an_absent_caller_mode_stays_an_explicit_named_refusal:
  for name:String
  for state:U32
  {D.missing_mode(None{},name,state) == Fail{C.Error{"ModeNotAdmitted",name,U32.show(state)}} :
    Result<&2,&2,C.Error,C.Mode>}

law an_admitted_plan_preserves_prefix_addition_order_and_all_caller_materials:
  for +identity:String
  for +committed:List<&2,C.Request>
  for names:Map<&2,Unit>
  for fallback:Maybe<&2,C.Mode>
  for modes:Map<&2,C.Mode>
  for +materials:BR.Policy
  for cells:U32
  for families:U32
  for +catalog_limits:C.Limits
  for catalog:Maybe<&2,C.Catalog>
  for tail:List<&2,D.Context>
  for seen_states:Map<&2,Unit>
  for seen_families:Map<&2,Unit>
  for +reversed:List<&2,C.Request>
  for count:U32
  for allowed:{C.request_guard(List.append(&2,C.Request,committed,List.reverse(&2,C.Request,reversed)),catalog_limits) == Done{Unit{}} :
    Result<&2,&2,C.Error,Unit>}
  {D.plan(D.Context{identity,committed,names,D.Admission{fallback,modes,materials},D.Limits{cells,families,catalog_limits},catalog,tail},
      D.Work{seen_states,seen_families,reversed,count}) ==
    Done{D.Plan{identity,List.append(&2,C.Request,committed,List.reverse(&2,C.Request,reversed)),List.reverse(&2,C.Request,reversed),materials}} :
    Result<&2,&2,C.Error,D.Plan>}

law initial_identity_refusal_preserves_the_complete_owner_before_decode:
  for error:C.Error
  for owner:D.Owner
  for sample:GS.Sample
  for admission:D.Admission
  for limits:D.Limits
  {D.initial_gated(Fail{error},owner,sample,admission,limits) == (owner,Fail{error}) :
    D.Owner & Result<&2,&2,C.Error,D.Plan>}

law initial_refuses_existing_commitments_without_inventing_a_catalog:
  for owner:D.Owner
  for sample:GS.Sample
  for admission:D.Admission
  for limits:D.Limits
  {D.initial_inventory_checked(False{},owner,sample,admission,limits) ==
    (owner,Fail{C.Error{"InitialCommittedInventory","demand","initial demand requires an empty committed inventory"}}) :
    D.Owner & Result<&2,&2,C.Error,D.Plan>}

law catalog_absence_uses_the_actual_registry_decode_and_returned_owner:
  for registry:B.Registry
  for identity:String
  for committed:List<&2,C.Request>
  for context:D.Context
  for work:D.Work
  for +state:U32
  {D.state_catalog(None{},D.Owner{registry,identity,committed},context,work,state) ==
    D.decoded(B.Registry.decode(registry,state),identity,committed,context,work,state) :
    D.Owner & Result<&2,&2,C.Error,D.Work>}
