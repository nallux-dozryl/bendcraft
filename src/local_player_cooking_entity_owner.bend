import Base
import ./cooking_effect_entities_model.bend as Model
import ./random.bend as Random
import ./local_player_cooking_geometry_owner.bend as GeometryOwner

# The carrier has the actual entity/RNG owner and its exact unconsumed clock
# inputs. An unbound actor has no random source and cannot manufacture one.
type Carrier is Type:
  Unbound{}
  Bound{context:Model.Context,state:Model.State,clock_inputs:List<&2,Random.Bits64>,geometry:Maybe<&1,GeometryOwner.Owner>}

def empty() -> Carrier:
  Unbound{}

def snapshotted(context:Model.Context,+inputs:List<&2,Random.Bits64>,geometry:Maybe<&1,GeometryOwner.Owner>,result:Model.State & Model.View) ->
    Carrier & Maybe<&2,Model.View> & List<&2,Random.Bits64>:
  (state,view) = result
  (Bound{context,state,inputs,geometry},Some{view},inputs)

def snapshot(carrier:Carrier) -> Carrier & Maybe<&2,Model.View> & List<&2,Random.Bits64>:
  match carrier:
    case Unbound{}: (Unbound{},None{},[])
    case Bound{context,state,inputs,geometry}: snapshotted(context,inputs,geometry,Model.inspect(state))

# Refusal returns the incoming affine owner separately. Neither the retained
# carrier nor an incoming RNG/entity owner is reconstructed or discarded.
def bind(carrier:Carrier,context:Model.Context,state:Model.State,inputs:List<&2,Random.Bits64>) ->
    Carrier & Maybe<&1,Model.State> & Result<&2,&2,String,Unit>:
  match carrier:
    case Unbound{}: (Bound{context,state,inputs,None{}},None{},Done{Unit{}})
    case Bound{previous,owner,times,geometry}:
      (Bound{previous,owner,times,geometry},Some{state},Fail{"local-cooking:entity-owner-already-bound"})

def restore_absent(inputs:List<&2,Random.Bits64>) -> Carrier & Result<&2,&2,String,Unit>:
  match inputs:
    case Nil{}: (Unbound{},Done{Unit{}})
    case head <> rest: (Unbound{},Fail{"local-cooking:entity-clock-inputs-without-owner"})

def restore_view(context:Model.Context,view:Maybe<&2,Model.View>,inputs:List<&2,Random.Bits64>) ->
    Carrier & Result<&2,&2,String,Unit>:
  match view:
    case None{}: restore_absent(inputs)
    case Some{value}: (Bound{context,Model.install(value),inputs,None{}},Done{Unit{}})

# Install is called only for a supplied complete View after the carrier gate.
# Immutable rejected View/clock inputs remain with the saved actor payload.
def restore(carrier:Carrier,context:Model.Context,view:Maybe<&2,Model.View>,inputs:List<&2,Random.Bits64>) ->
    Carrier & Result<&2,&2,String,Unit>:
  match carrier:
    case Unbound{}: restore_view(context,view,inputs)
    case Bound{previous,owner,times,geometry}:
      (Bound{previous,owner,times,geometry},Fail{"local-cooking:entity-owner-already-bound"})
