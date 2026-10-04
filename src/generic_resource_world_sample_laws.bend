import Base
import ./generic_resource_world_sample.bend as GS
import ./resource_block_catalog.bend as C
import ./resource_catalog_world.bend as CW
import ./block_resources.bend as BR
import ./blockstate_model.bend as S
import ./world_mesh.bend as WM
import ./client_world.bend as W
import ./client_render.bend as R
import ./movement.bend as MV

law another_registry_is_refused_before_sample_or_state_validation:
  for +declared:String
  for +actual:String
  for +tick:Nat
  for +revision:Nat
  for +origin:MV.Vec3
  for +camera:R.Camera
  for +cells:List<&2,GS.Cell>
  for +entries:Map<&2,C.Entry>
  for +loaded:BR.Catalog
  for mismatch:{String.eq(declared,actual) == False{} : Bool}
  {GS.frame(GS.Sample{declared,tick,revision,origin,camera,cells},C.Catalog{actual,entries,loaded}) ==
    Fail{C.Error{"RegistryIdentityMismatch","catalog",declared ++ ":" ++ actual}} : Result<&2,&2,C.Error,CW.Frame>}

law prior_registry_refusal_retains_the_exact_diagnostic:
  for +error:C.Error
  for sample:GS.Sample
  for catalog:C.Catalog
  {GS.frame_gated(Fail{error},sample,catalog) == Fail{error} : Result<&2,&2,C.Error,CW.Frame>}

law invalid_sample_is_refused_before_catalog_traversal:
  for sample:GS.Sample
  for catalog:C.Catalog
  {GS.frame_configured(False{},sample,catalog) == Fail{C.Error{"InvalidSample","world",""}} : Result<&2,&2,C.Error,CW.Frame>}

law invisible_cells_do_not_consume_visible_binding_slots:
  for point:W.Cell
  for state:U32
  for selection:C.Selection
  for appearance:WM.Appearance
  for origin:MV.Vec3
  for +tail:List<&2,CW.Instance>
  {GS.retained_instance(C.Invisible{},point,state,selection,appearance,origin,tail) == tail : List<&2,CW.Instance>}

law a_single_model_choice_never_consumes_a_random_ticket:
  for variant:S.Variant
  for seed:U32
  {GS.choice_ticket(S.Single{variant},seed) == Done{None{}} : Result<&2,&2,C.Error,Maybe<&2,U32>>}

law a_zero_weight_total_is_refused_before_modulo:
  for entries:List<&2,S.Weighted>
  for seed:U32
  {GS.choice_ticket(S.WeightedChoice{entries,0},seed) ==
    Fail{C.Error{"InvalidWeightedChoice","catalog","zero total"}} : Result<&2,&2,C.Error,Maybe<&2,U32>>}

law an_absent_appearance_override_retains_the_complete_surface:
  for values:Map<&2,WM.Appearance>
  for key:String
  for +surface:WM.Appearance
  {GS.override(False{},values,key,surface) == surface : WM.Appearance}

law traversal_refusal_retains_the_original_state_error:
  for +error:C.Error
  for identity:String
  for tick:Nat
  for revision:Nat
  for camera:R.Camera
  {GS.framed(Fail{error},identity,tick,revision,camera) == Fail{error} : Result<&2,&2,C.Error,CW.Frame>}

law an_empty_state_suffix_never_accesses_catalog_models:
  for origin:MV.Vec3
  for catalog:C.Catalog
  {GS.instances(Nil{},origin,catalog) == Done{Nil{}} : Result<&2,&2,C.Error,List<&2,CW.Instance>>}
