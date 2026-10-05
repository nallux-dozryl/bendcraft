import Base
import ./cooking_effect_entities_model.bend as Model
import ./random.bend as Random
import ./local_player_cooking_geometry_owner.bend as GeometryOwner
import ./local_player_cooking_publication_owner.bend as Publisher
import ./local_player_cooking_tick_owner.bend as Tick
import ./local_player_cooking_tick_storage.bend as TickStorage
import ./local_player_cooking_storage.bend as Storage

# The carrier has the actual entity/RNG owner and its exact unconsumed clock
# inputs. An unbound actor has no random source and cannot manufacture one.
type Carrier is Type:
  Unbound{}
  PublicationOnly{publisher:Publisher.Carrier}
  Bound{context:Model.Context,state:Model.State,clock_inputs:List<&2,Random.Bits64>,geometry:Maybe<&1,GeometryOwner.Owner>,publisher:Publisher.Carrier}
  TickBound{context:Model.Context,state:Model.State,clock_inputs:List<&2,Random.Bits64>,geometry:Maybe<&1,GeometryOwner.Owner>,publisher:Publisher.Carrier,tick:Tick.State}

def empty() -> Carrier:
  Unbound{}

def publisher_returned(-A:Type,restore:Publisher.Carrier -> Carrier,result:Publisher.Carrier & A) -> Carrier & A:
  (publisher,answer) = result
  (restore(publisher),answer)

def unbound_publisher_returned(-A:Type,result:Publisher.Carrier & A) -> Carrier & A:
  match result:
    case (Publisher.Unbound{},answer): (Unbound{},answer)
    case (publisher,answer): (PublicationOnly{publisher},answer)

# The publication domain may be bound without an entity owner. This detour
# transfers only its actual journal; all entity/RNG/geometry fields remain in
# the affine constructor continuation, including on a refused operation.
def with_publisher(-A:Type,carrier:Carrier,operation:Publisher.Carrier -> Publisher.Carrier & A) -> Carrier & A:
  match carrier:
    case Unbound{}: unbound_publisher_returned(A,operation(Publisher.empty()))
    case PublicationOnly{publisher}:
      publisher_returned(A,publisher => PublicationOnly{publisher},operation(publisher))
    case Bound{context,state,inputs,geometry,publisher}:
      publisher_returned(A,publisher => Bound{context,state,inputs,geometry,publisher},operation(publisher))
    case TickBound{context,state,inputs,geometry,publisher,tick}:
      publisher_returned(A,publisher => TickBound{context,state,inputs,geometry,publisher,tick},operation(publisher))

def snapshotted(context:Model.Context,+inputs:List<&2,Random.Bits64>,geometry:Maybe<&1,GeometryOwner.Owner>,publisher:Publisher.Carrier,result:Model.State & Model.View) ->
    Carrier & Maybe<&2,Model.View> & List<&2,Random.Bits64>:
  (state,view) = result
  (Bound{context,state,inputs,geometry,publisher},Some{view},inputs)

def tick_snapshotted(context:Model.Context,+inputs:List<&2,Random.Bits64>,geometry:Maybe<&1,GeometryOwner.Owner>,
    publisher:Publisher.Carrier,tick:Tick.State,result:Model.State & Model.View) ->
    Carrier & Maybe<&2,Model.View> & List<&2,Random.Bits64>:
  (state,view) = result
  (TickBound{context,state,inputs,geometry,publisher,tick},Some{view},inputs)

def snapshot(carrier:Carrier) -> Carrier & Maybe<&2,Model.View> & List<&2,Random.Bits64>:
  match carrier:
    case Unbound{}: (Unbound{},None{},[])
    case PublicationOnly{publisher}: (PublicationOnly{publisher},None{},[])
    case Bound{context,state,inputs,geometry,publisher}: snapshotted(context,inputs,geometry,publisher,Model.inspect(state))
    case TickBound{context,state,inputs,geometry,publisher,tick}:
      tick_snapshotted(context,inputs,geometry,publisher,tick,Model.inspect(state))

def saved_legacy(context:Model.Context,+inputs:List<&2,Random.Bits64>,geometry:Maybe<&1,GeometryOwner.Owner>,
    publisher:Publisher.Carrier,result:Model.State & Model.View) -> Carrier & Maybe<&2,Storage.EntityRecovery>:
  (state,view) = result
  (Bound{context,state,inputs,geometry,publisher},Some{Storage.EntityRecovery{view,inputs}})

def saved_tick(context:Model.Context,+inputs:List<&2,Random.Bits64>,geometry:Maybe<&1,GeometryOwner.Owner>,
    publisher:Publisher.Carrier,+tick:Tick.State,result:Model.State & Model.View) -> Carrier & Maybe<&2,Storage.EntityRecovery>:
  (state,view) = result
  (TickBound{context,state,inputs,geometry,publisher,tick},Some{Storage.TickRecovery{Tick.snapshot(view,inputs,tick)}})

# The actual save snapshot observes the one Model owner. Runtime, sound and
# manager availability remain separate and preserve the complete saved DTO.
def saved_snapshot(carrier:Carrier) -> Carrier & Maybe<&2,Storage.EntityRecovery>:
  match carrier:
    case Unbound{}: (Unbound{},None{})
    case PublicationOnly{publisher}: (PublicationOnly{publisher},None{})
    case Bound{context,state,inputs,geometry,publisher}: saved_legacy(context,inputs,geometry,publisher,Model.inspect(state))
    case TickBound{context,state,inputs,geometry,publisher,tick}: saved_tick(context,inputs,geometry,publisher,tick,Model.inspect(state))

def persistence_ready(carrier:Carrier) -> Carrier & Result<&2,&2,String,Unit>:
  match carrier:
    case TickBound{context,state,inputs,geometry,publisher,+tick}:
      (TickBound{context,state,inputs,geometry,publisher,tick},Tick.require_canonical(tick))
    case other: (other,Done{Unit{}})

# Refusal returns the incoming affine owner separately. Neither the retained
# carrier nor an incoming RNG/entity owner is reconstructed or discarded.
def bind(carrier:Carrier,context:Model.Context,state:Model.State,inputs:List<&2,Random.Bits64>) ->
    Carrier & Maybe<&1,Model.State> & Result<&2,&2,String,Unit>:
  match carrier:
    case Unbound{}: (Bound{context,state,inputs,None{},Publisher.empty()},None{},Done{Unit{}})
    case PublicationOnly{publisher}: (Bound{context,state,inputs,None{},publisher},None{},Done{Unit{}})
    case Bound{previous,owner,times,geometry,publisher}:
      (Bound{previous,owner,times,geometry,publisher},Some{state},Fail{"local-cooking:entity-owner-already-bound"})
    case TickBound{previous,owner,times,geometry,publisher,tick}:
      (TickBound{previous,owner,times,geometry,publisher,tick},Some{state},Fail{"local-cooking:entity-owner-already-bound"})

def restore_absent(publisher:Publisher.Carrier,inputs:List<&2,Random.Bits64>) -> Carrier & Result<&2,&2,String,Unit>:
  match inputs:
    case Nil{}: (PublicationOnly{publisher},Done{Unit{}})
    case head <> rest: (PublicationOnly{publisher},Fail{"local-cooking:entity-clock-inputs-without-owner"})

def restore_view(context:Model.Context,publisher:Publisher.Carrier,view:Maybe<&2,Model.View>,inputs:List<&2,Random.Bits64>) ->
    Carrier & Result<&2,&2,String,Unit>:
  match view:
    case None{}: restore_absent(publisher,inputs)
    case Some{value}: (Bound{context,Model.install(value),inputs,None{},publisher},Done{Unit{}})

def restore_unbound_absent(inputs:List<&2,Random.Bits64>) -> Carrier & Result<&2,&2,String,Unit>:
  match inputs:
    case Nil{}: (Unbound{},Done{Unit{}})
    case head <> rest: (Unbound{},Fail{"local-cooking:entity-clock-inputs-without-owner"})

def restore_unbound(context:Model.Context,view:Maybe<&2,Model.View>,inputs:List<&2,Random.Bits64>) ->
    Carrier & Result<&2,&2,String,Unit>:
  match view:
    case None{}: restore_unbound_absent(inputs)
    case Some{value}: (Bound{context,Model.install(value),inputs,None{},Publisher.empty()},Done{Unit{}})

# Install is called only for a supplied complete View after the carrier gate.
# Immutable rejected View/clock inputs remain with the saved actor payload.
def restore(carrier:Carrier,context:Model.Context,view:Maybe<&2,Model.View>,inputs:List<&2,Random.Bits64>) ->
    Carrier & Result<&2,&2,String,Unit>:
  match carrier:
    case Unbound{}: restore_unbound(context,view,inputs)
    case PublicationOnly{publisher}: restore_view(context,publisher,view,inputs)
    case Bound{previous,owner,times,geometry,publisher}:
      (Bound{previous,owner,times,geometry,publisher},Fail{"local-cooking:entity-owner-already-bound"})
    case TickBound{previous,owner,times,geometry,publisher,tick}:
      (TickBound{previous,owner,times,geometry,publisher,tick},Fail{"local-cooking:entity-owner-already-bound"})

def restored_tick(context:Model.Context,publisher:Publisher.Carrier,result:Model.State & List<&2,Random.Bits64> & Tick.State) ->
    Carrier & Result<&2,&2,String,Unit>:
  (state,inputs,tick) = result
  (TickBound{context,state,inputs,None{},publisher,tick},Done{Unit{}})

# Decoded runtime/sound/manager None values are retained. This installs no
# manager authority and does not call a fresh runtime or random constructor.
def restore_tick(carrier:Carrier,context:Model.Context,saved:TickStorage.Stored) -> Carrier & Result<&2,&2,String,Unit>:
  match carrier:
    case Unbound{}: restored_tick(context,Publisher.empty(),Tick.installed(saved))
    case PublicationOnly{publisher}: restored_tick(context,publisher,Tick.installed(saved))
    case Bound{previous,owner,times,geometry,publisher}:
      (Bound{previous,owner,times,geometry,publisher},Fail{"local-cooking:entity-owner-already-bound"})
    case TickBound{previous,owner,times,geometry,publisher,tick}:
      (TickBound{previous,owner,times,geometry,publisher,tick},Fail{"local-cooking:entity-owner-already-bound"})
