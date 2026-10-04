import Base
import ./core.bend as C
import ./local_player_cooking.bend as Cooking
import ./local_player_cooking_entities.bend as Adapter
import ./local_player_cooking_entity_owner.bend as Owner
import ./cooking_effect_entities_model.bend as Model
import ./cooking_effect_entities.bend as Entities
import ./cooking_world.bend as CW
import ./cooking_world_store.bend as Store
import ./block_light.bend as Light
import ./block_light_world.bend as BW
import ./random.bend as Random

# The actual delivery splice uses the constructor continuation supplied by
# its caller. The returned entity/RNG owner and raw remaining clock inputs
# replace the temporary carrier; the returned pending effects replace the
# released queue. Every other complete affine/Data owner survives exactly.
# This helper contract permits an arbitrary retained recursive Sidecar tail;
# admission of that tail by the separate ready/IO path is outside this law.
# Status formatting remains the real Adapter.status subsystem interface.
law delivered_result_installs_complete_entity_owner_and_preserves_sidecar:
  for world:C.World
  for context:Cooking.Context
  for light:Light.State
  for loading:Maybe<&2,BW.Cursor>
  for entries:List<&1,Store.Entry>
  for phase:CW.Phase
  for keys:List<&2,String>
  for details:List<&2,Cooking.BodyDetails>
  for incarnations:Map<&2,Nat>
  for acknowledged_resets:Nat
  for sidecar_tail:List<&1,Cooking.Sidecar>
  for entity_context:Model.Context
  for returned_state:Model.State
  for pending:List<&2,Store.Effect>
  for outcome:Result<&2,&2,Model.Error,Unit>
  for remaining_times:List<&2,Random.Bits64>
  {Adapter.delivered(world,
      carrier => suffix => Cooking.Initialized{context,light,loading,entries,phase,keys,suffix,
        details,incarnations,acknowledged_resets,carrier,sidecar_tail},
      entity_context,(returned_state,Entities.Outcome{pending,outcome,remaining_times})) ==
    (world,Cooking.Initialized{context,light,loading,entries,phase,keys,pending,
      details,incarnations,acknowledged_resets,
      Owner.Bound{entity_context,returned_state,remaining_times},sidecar_tail},Adapter.status(outcome)) :
    C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>}
