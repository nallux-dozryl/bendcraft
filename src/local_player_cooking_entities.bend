import Base
import ./core.bend as C
import ./local_player_cooking.bend as Cooking
import ./local_player_cooking_entity_owner.bend as Owner
import ./cooking_effect_entities_model.bend as Model
import ./cooking_effect_entities.bend as Entities
import ./cooking_effect_consumer.bend as Consumer
import ./cooking_world_store.bend as Store
import ./random.bend as Random
import ./vanilla_entity_fields.bend as V

# The actor has no authenticated entity collision-shape/findFreePosition
# service yet. Existing-orb merges and item creation use the actual consumer;
# creation of a new orb retains its effect until that service is supplied.
def place(geometry:Unit,dimension:String,position:V.Vec3) -> Result<&2,&2,Model.Error,V.Vec3>:
  Fail{Model.Refused{"cooking-effects:entity-collision-placement-owner-required"}}

def random_error(error:Random.RandomError) -> String:
  match error:
    case Random.InvalidBound{}: "invalid-bound"
    case Random.RejectionFuelExhausted{}: "rejection-budget"
    case Random.UnsupportedHash{}: "unsupported-hash"

def error_text(error:Model.Error) -> String:
  match error:
    case Model.Refused{message}: message
    case Model.RandomFailure{error}: "cooking-effects:random-" ++ random_error(error)
    case Model.SpawnBudget{}: "cooking-effects:spawn-budget"
    case Model.IdBudget{}: "cooking-effects:id-budget"
    case Model.EntropyNeeded{count}: "cooking-effects:constructor-clock-budget"

def status(result:Result<&2,&2,Model.Error,Unit>) -> Result<&2,&2,String,Unit>:
  match result:
    case Fail{error}: Fail{error_text(error)}
    case Done{unit}: Done{unit}

# The affine constructor continuation keeps every other Sidecar field while
# the consumer owns the entity state. It installs exactly the returned carrier
# and suffix, with no temporary carrier published in the Session.
def delivered(world:C.World,restore:Owner.Carrier -> List<&2,Store.Effect> -> Cooking.Sidecar,entity_context:Model.Context,
    result:Model.State & Entities.Outcome) -> C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>:
  (owner,Entities.Outcome{pending,outcome,inputs}) = result
  (world,restore(Owner.Bound{entity_context,owner,inputs})(pending),status(outcome))

def clock_budget(context:Model.Context) -> Nat:
  Model.Context{items,Model.Limits{steps,rejections,ids},reserved} = context
  steps

def bound(world:C.World,restore:Owner.Carrier -> List<&2,Store.Effect> -> Cooking.Sidecar,+entity_context:Model.Context,
    effects:List<&2,Store.Effect>,owner:Model.State,inputs:List<&2,Random.Bits64>) -> IO(C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  do IO<C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>>:
    result : Model.State & Entities.Outcome <- Consumer.deliver_io(~Unit,~place,clock_budget(entity_context),Unit{},
      entity_context,effects,owner,inputs)
    return delivered(world,restore,entity_context,result)

def fallback(world:C.World,result:Cooking.Sidecar & Result<&2,&2,String,Unit>) -> IO(C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  (sidecar,outcome) = result
  IO.pure(C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>,(world,sidecar,outcome))

def ready(world:C.World,sidecar:Cooking.Sidecar) -> IO(C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  match sidecar:
    case Cooking.Uninitialized{}: IO.pure(C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>,(world,Cooking.Uninitialized{},Done{Unit{}}))
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,entity_owner,child <> rest}:
      IO.pure(C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>,
        (world,Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,entity_owner,child <> rest},
          Fail{"local-cooking:noncanonical-sidecar-tail"}))
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,Owner.Unbound{},Nil{}}:
      fallback(world,Cooking.deliver_pending(Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,Owner.Unbound{},[]}))
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,Owner.Bound{entity_context,owner,inputs},Nil{}}:
      bound(world,carrier => pending => Cooking.Initialized{context,light,loading,entries,phase,keys,pending,details,incarnations,acknowledged_resets,carrier,[]},
        entity_context,effects,owner,inputs)

def checked(sidecar:Cooking.Sidecar,result:C.World & Bool) -> IO(C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  (world,valid) = result
  match valid:
    case False{}: IO.pure(C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>,(world,sidecar,Fail{"local-cooking:invalid-context"}))
    case True{}: ready(world,sidecar)

# Pre-tick, post-completed-tick and startup all use this one owner path. IO
# retries an uncommitted entropy-dependent effect without replaying a tick.
def deliver_io(world:C.World,sidecar:Cooking.Sidecar) -> IO(C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  match sidecar:
    case Cooking.Uninitialized{}: ready(world,Cooking.Uninitialized{})
    case Cooking.Initialized{+context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,entity_owner,tail}:
      checked(Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,entity_owner,tail},
        Cooking.checked_world(world,context))
