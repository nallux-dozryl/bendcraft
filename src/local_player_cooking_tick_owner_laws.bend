import Base
import ./local_player_cooking_tick_owner.bend as Tick
import ./local_player_cooking_tick_storage.bend as Storage
import ./local_player_cooking_entity_owner.bend as Owner
import ./local_player_cooking_publication_owner.bend as Publisher
import ./local_player_cooking_geometry_owner.bend as Geometry
import ./local_player_cooking.bend as Cooking
import ./local_player_cooking_entities.bend as Adapter
import ./local_player_cooking_storage.bend as Saved
import ./cooking_effect_entities_model.bend as Model
import ./cooking_effect_entities.bend as Entities
import ./cooking_world.bend as CW
import ./cooking_world_store.bend as Store
import ./block_light.bend as Light
import ./block_light_world.bend as BW
import ./item_entity_tick_model.bend as Runtime
import ./entity_section_membership_model.bend as Membership
import ./random.bend as Random
import ./game.bend as G

# A failed installation cannot replace an existing entity, its clocks,
# runtime/sound/manager metadata or either actual publication/geometry owner.
law restore_refusal_retains_complete_tick_owner:
  for previous:Model.Context
  for state:Model.State
  for times:List<&2,Random.Bits64>
  for geometry:Maybe<&1,Geometry.Owner>
  for publisher:Publisher.Carrier
  for tick:Tick.State
  for incoming_context:Model.Context
  for incoming:Storage.Stored
  {Owner.restore_tick(Owner.TickBound{previous,state,times,geometry,publisher,tick},incoming_context,incoming) ==
    (Owner.TickBound{previous,state,times,geometry,publisher,tick},Fail{"local-cooking:entity-owner-already-bound"}) :
    Owner.Carrier & Result<&2,&2,String,Unit>}

# A recursive metadata tail is retained in the live owner and refused before
# any save projection can omit it from the single actor image.
law recursive_metadata_save_refusal_retains_complete_owner:
  for context:Model.Context
  for state:Model.State
  for inputs:List<&2,Random.Bits64>
  for geometry:Maybe<&1,Geometry.Owner>
  for publisher:Publisher.Carrier
  for runtimes:Maybe<&2,List<&2,Runtime.RuntimeEntry>>
  for sound:Maybe<&2,Random.Source>
  for membership:Maybe<&2,Membership.View>
  for child:Tick.State
  for tail:List<&2,Tick.State>
  {Owner.persistence_ready(Owner.TickBound{context,state,inputs,geometry,publisher,
      Tick.State{runtimes,sound,membership,child <> tail}}) ==
    (Owner.TickBound{context,state,inputs,geometry,publisher,Tick.State{runtimes,sound,membership,child <> tail}},
      Fail{"local-cooking:noncanonical-tick-owner-tail"}) : Owner.Carrier & Result<&2,&2,String,Unit>}

# The actual publication detour changes only the returned journal domain.
# Complete runtime/sound/manager metadata survives a refused operation.
law publication_detour_retains_entity_and_tick_domains:
  for context:Model.Context
  for state:Model.State
  for inputs:List<&2,Random.Bits64>
  for geometry:Maybe<&1,Geometry.Owner>
  for previous:Publisher.Carrier
  for tick:Tick.State
  for returned:Publisher.Carrier
  for status:Result<&2,&2,String,Unit>
  {Owner.with_publisher(Result<&2,&2,String,Unit>,Owner.TickBound{context,state,inputs,geometry,previous,tick},
      publisher => (returned,status)) ==
    (Owner.TickBound{context,state,inputs,geometry,returned,tick},status) : Owner.Carrier & Result<&2,&2,String,Unit>}

# Snapshotting uses the actual Model.inspect result while retaining every
# Sidecar owner and both recursive tails. None and Some runtime/sound/manager
# fields are carried as supplied; this grants no loader or ticking authority.
law saved_snapshot_retains_complete_sidecar_and_tick_owner:
  for context:Cooking.Context
  for light:Light.State
  for loading:Maybe<&2,BW.Cursor>
  for entries:List<&1,Store.Entry>
  for phase:CW.Phase
  for keys:List<&2,String>
  for effects:List<&2,Store.Effect>
  for details:List<&2,Cooking.BodyDetails>
  for incarnations:Map<&2,Nat>
  for acknowledged:Nat
  for sidecar_tail:List<&1,Cooking.Sidecar>
  for entity_context:Model.Context
  for state:Model.State
  for +inputs:List<&2,Random.Bits64>
  for geometry:Maybe<&1,Geometry.Owner>
  for publisher:Publisher.Carrier
  for +tick:Tick.State
  for returned_state:Model.State
  for view:Model.View
  for inspected:{Model.inspect(state) == (returned_state,view) : Model.State & Model.View}
  {Cooking.saved_entity_snapshot(Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,
      incarnations,acknowledged,Owner.TickBound{entity_context,state,inputs,geometry,publisher,tick},sidecar_tail}) ==
    (Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,
      incarnations,acknowledged,Owner.TickBound{entity_context,returned_state,inputs,geometry,publisher,tick},sidecar_tail},
      Some{Saved.TickRecovery{Tick.snapshot(view,inputs,tick)}}) : Cooking.Sidecar & Maybe<&2,Saved.EntityRecovery>}

# This actual delivery-result continuation preserves all captured metadata
# while installing the returned engine, geometry, entity state and clock queue
# together. It makes no claim about the effect or item-tick algorithms.
law delivery_result_preserves_tick_metadata_and_complete_sidecar:
  for engine:G.Engine
  for context:Cooking.Context
  for light:Light.State
  for loading:Maybe<&2,BW.Cursor>
  for entries:List<&1,Store.Entry>
  for phase:CW.Phase
  for keys:List<&2,String>
  for details:List<&2,Cooking.BodyDetails>
  for incarnations:Map<&2,Nat>
  for acknowledged:Nat
  for tail:List<&1,Cooking.Sidecar>
  for entity_context:Model.Context
  for geometry:Maybe<&1,Geometry.Owner>
  for publisher:Publisher.Carrier
  for tick:Tick.State
  for state:Model.State
  for pending:List<&2,Store.Effect>
  for status:Result<&2,&2,Model.Error,Unit>
  for inputs:List<&2,Random.Bits64>
  {Adapter.delivered_engine_tick(owner => suffix => Cooking.Initialized{context,light,loading,entries,phase,keys,suffix,
      details,incarnations,acknowledged,owner,tail},entity_context,publisher,tick,
      (engine,geometry,state,Entities.Outcome{pending,status,inputs})) ==
    (engine,Cooking.Initialized{context,light,loading,entries,phase,keys,pending,details,incarnations,acknowledged,
      Owner.TickBound{entity_context,state,inputs,geometry,publisher,tick},tail},Adapter.status(status)) :
    G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>}
