import Base
import ./local_player_entity_scene.bend as Capture
import ./local_player_session.bend as S
import ./generic_resource_world_sample.bend as GS
import ./remote_entity_frame.bend as Frame
import ./local_player_cooking_storage.bend as Storage
import ./item_entity_render.bend as Render
import ./item_entity_render_model.bend as D
import ./cooking_effect_entities_model.bend as E
import ./random.bend as Random

# These refusals happen before the actual world/entity queries. Quantifying the
# affine Session covers its Core, inventory, cooking/entity/RNG arrays, clocks,
# geometry and arbitrary tails; no projection is substituted for that owner.
law invalid_frame_guard_retains_complete_session:
  for state:S.State
  for width:U32
  for height:U32
  for policy:GS.Policy
  for partial:F32
  {Capture.frame_checked(False{},state,width,height,policy,partial) ==
    (state,Fail{"generic-resource:invalid-frame"}) :
    S.State & Result<&2,&2,String,Frame.Frame>}

law invalid_partial_guard_retains_complete_session:
  for state:S.State
  for width:U32
  for height:U32
  for policy:GS.Policy
  for partial:F32
  {Capture.partial_checked(False{},state,width,height,policy,partial) ==
    (state,Fail{"remote-entity:invalid-partial"}) :
    S.State & Result<&2,&2,String,Frame.Frame>}

law unsupported_dimension_retains_complete_session:
  for state:S.State
  for dimension:String
  for width:U32
  for height:U32
  for policy:GS.Policy
  for partial:F32
  {Capture.dimension_checked(False{},state,dimension,width,height,policy,partial) ==
    (state,Fail{"remote-entity:unsupported-sample-dimension"}) :
    S.State & Result<&2,&2,String,Frame.Frame>}

law sample_refusal_retains_returned_session_and_exact_error:
  for state:S.State
  for dimension:String
  for partial:F32
  for message:String
  {Capture.sampled(dimension,partial,(state,Fail{message})) ==
    (state,Fail{message}) : S.State & Result<&2,&2,String,Frame.Frame>}

# Only the immutable parent-owned render projection is published. The complete
# actual returned Session still owns the entity arrays, RNG and clock inputs;
# the sample, dimension and interpolation fraction remain in one frame.
law captured_bound_projection_retains_complete_returned_session:
  for state:S.State
  for dimension:String
  for partial:F32
  for sample:GS.Sample
  for view:E.View
  for inputs:List<&2,Random.Bits64>
  {Capture.captured(dimension,partial,sample,
      (state,Some{Storage.EntityRecovery{view,inputs}})) ==
    (state,Done{Frame.Frame{sample,Render.render_snapshot(view),dimension,partial}}) :
    S.State & Result<&2,&2,String,Frame.Frame>}

law captured_unbound_owner_remains_explicitly_unbound:
  for state:S.State
  for dimension:String
  for partial:F32
  for sample:GS.Sample
  {Capture.captured(dimension,partial,sample,(state,None{})) ==
    (state,Done{Frame.Frame{sample,D.Unbound{},dimension,partial}}) :
    S.State & Result<&2,&2,String,Frame.Frame>}
