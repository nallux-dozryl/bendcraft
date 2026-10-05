import Base
import ./local_player_cooking_tick_owner_laws.bend as Laws
import ./local_player_cooking_tick_owner.bend as Tick
import ./local_player_cooking_entity_owner.bend as Owner
import ./local_player_cooking_publication_owner.bend as Publisher
import ./local_player_cooking.bend as Cooking
import ./local_player_cooking_storage.bend as Saved
import ./cooking_effect_entities_model.bend as Model

def Laws.restore_refusal_retains_complete_tick_owner(previous,state,times,geometry,publisher,tick,incoming_context,incoming): {==}
def Laws.recursive_metadata_save_refusal_retains_complete_owner(context,state,inputs,geometry,publisher,runtimes,sound,membership,child,tail): {==}
def Laws.publication_detour_retains_entity_and_tick_domains(context,state,inputs,geometry,previous,tick,returned,status): {==}

def Laws.saved_snapshot_retains_complete_sidecar_and_tick_owner(context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,sidecar_tail,entity_context,state,inputs,geometry,publisher,tick,returned_state,view,inspected):
  %Equal.sym(Model.State & Model.View,Model.inspect(state),(returned_state,view),inspected) :
    {Cooking.entity_saved(owner => Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,
        incarnations,acknowledged,owner,sidecar_tail},Owner.saved_tick(entity_context,inputs,geometry,publisher,tick,_)) ==
      (Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,
        incarnations,acknowledged,Owner.TickBound{entity_context,returned_state,inputs,geometry,publisher,tick},sidecar_tail},
        Some{Saved.TickRecovery{Tick.snapshot(view,inputs,tick)}}) : Cooking.Sidecar & Maybe<&2,Saved.EntityRecovery>}
  {==}

def Laws.delivery_result_preserves_tick_metadata_and_complete_sidecar(engine,context,light,loading,entries,phase,keys,details,incarnations,acknowledged,tail,entity_context,geometry,publisher,tick,state,pending,status,inputs): {==}
