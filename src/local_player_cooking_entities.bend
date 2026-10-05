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
import ./game.bend as G
import ./registry.bend as Registry
import ./local_player_cooking_geometry_owner.bend as GeometryOwner
import ./local_player_cooking_entity_delivery.bend as Delivery
import ./local_player_cooking_publication_owner.bend as Publisher

# This actor currently binds one overworld Level RNG. Global factory/IDs are
# retained, but a different Level needs its own random owner before consuming
# its item/XP callback. Prefix splitting does not execute or reorder effects.
type Scope is Data:
  Scope{prefix:List<&2,Store.Effect>,suffix:List<&2,Store.Effect>}

def overworld(position:C.Position) -> Bool:
  C.Position{dimension,x,y,z} = position
  String.eq(dimension,"minecraft:overworld")

def supported(effect:Store.Effect) -> Bool:
  match effect:
    case Store.Drop{position,slot,item}: overworld(position)
    case Store.Experience{position,request}: overworld(position)
    case _: True{}

def scoped_cons(effect:Store.Effect,result:Scope) -> Scope:
  Scope{prefix,suffix} = result
  Scope{effect <> prefix,suffix}

def scoped_next(effect:Store.Effect,rest:List<&2,Store.Effect>,allowed:Bool,
    next:Unit -> Scope) -> Scope:
  match allowed:
    case False{}: Scope{[],effect <> rest}
    case True{}: scoped_cons(effect,next(Unit{}))

def scope(effects:List<&2,Store.Effect>) -> Scope:
  match effects:
    case Nil{}: Scope{[],[]}
    case +effect <> +rest: scoped_next(effect,rest,supported(effect),unit => scope(rest))

def scoped_result(result:Model.State & Entities.Outcome,suffix:List<&2,Store.Effect>) -> Model.State & Entities.Outcome:
  (owner,Entities.Outcome{pending,outcome,inputs}) = result
  match outcome suffix:
    case Fail{error} suffix:
      (owner,Entities.Outcome{List.append(&2,Store.Effect,pending,suffix),Fail{error},inputs})
    case Done{unit} Nil{}: (owner,Entities.Outcome{pending,Done{unit},inputs})
    case Done{unit} head <> rest:
      (owner,Entities.Outcome{List.append(&2,Store.Effect,pending,head <> rest),
        Fail{Model.Refused{"cooking-effects:per-level-random-owner-required"}},inputs})

# This Core-only compatibility route cannot capture the Registry/catalog.
# The actual actor uses deliver_engine_io below for authenticated placement;
# this route retains a new-orb request rather than fabricating its geometry.
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
    geometry:Maybe<&1,GeometryOwner.Owner>,publisher:Publisher.Carrier,result:Model.State & Entities.Outcome) -> C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>:
  (owner,Entities.Outcome{pending,outcome,inputs}) = result
  (world,restore(Owner.Bound{entity_context,owner,inputs,geometry,publisher})(pending),status(outcome))

def clock_budget(context:Model.Context) -> Nat:
  Model.Context{items,Model.Limits{steps,rejections,ids},reserved} = context
  steps

def scoped_io(+entity_context:Model.Context,owner:Model.State,inputs:List<&2,Random.Bits64>,partition:Scope) -> IO(Model.State & Entities.Outcome):
  Scope{prefix,suffix} = partition
  do IO<Model.State & Entities.Outcome>:
    result : Model.State & Entities.Outcome <- Consumer.deliver_io(~Unit,~place,clock_budget(entity_context),Unit{},
      entity_context,prefix,owner,inputs)
    return scoped_result(result,suffix)

def bound(world:C.World,restore:Owner.Carrier -> List<&2,Store.Effect> -> Cooking.Sidecar,+entity_context:Model.Context,
    effects:List<&2,Store.Effect>,owner:Model.State,inputs:List<&2,Random.Bits64>,geometry:Maybe<&1,GeometryOwner.Owner>,publisher:Publisher.Carrier) -> IO(C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  do IO<C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>>:
    result : Model.State & Entities.Outcome <- scoped_io(entity_context,owner,inputs,scope(effects))
    return delivered(world,restore,entity_context,geometry,publisher,result)

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
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,Owner.PublicationOnly{publisher},Nil{}}:
      fallback(world,Cooking.deliver_pending(Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,Owner.PublicationOnly{publisher},[]}))
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,Owner.Bound{entity_context,owner,inputs,geometry,publisher},Nil{}}:
      bound(world,carrier => pending => Cooking.Initialized{context,light,loading,entries,phase,keys,pending,details,incarnations,acknowledged_resets,carrier,[]},
        entity_context,effects,owner,inputs,geometry,publisher)

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

# The engine detour permits real shape capture with the same Registry/Core.
# The returned collision catalog and entity owner are installed together.
def delivered_engine(restore:Owner.Carrier -> List<&2,Store.Effect> -> Cooking.Sidecar,
    entity_context:Model.Context,publisher:Publisher.Carrier,
    result:G.Engine & Maybe<&1,GeometryOwner.Owner> & Model.State & Entities.Outcome) ->
    G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>:
  (engine,geometry,owner,Entities.Outcome{pending,outcome,inputs}) = result
  (engine,restore(Owner.Bound{entity_context,owner,inputs,geometry,publisher})(pending),status(outcome))

def bound_engine(engine:G.Engine,restore:Owner.Carrier -> List<&2,Store.Effect> -> Cooking.Sidecar,
    +entity_context:Model.Context,effects:List<&2,Store.Effect>,owner:Model.State,
    inputs:List<&2,Random.Bits64>,geometry:Maybe<&1,GeometryOwner.Owner>,publisher:Publisher.Carrier) ->
    IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  do IO<G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>>:
    result : G.Engine & Maybe<&1,GeometryOwner.Owner> & Model.State & Entities.Outcome <-
      Delivery.deliver_io(~supported,effects,engine,geometry,entity_context,owner,inputs)
    return delivered_engine(restore,entity_context,publisher,result)

def engine_fallback(engine:G.Engine,result:Cooking.Sidecar & Result<&2,&2,String,Unit>) ->
    IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  (sidecar,status) = result
  IO.pure(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>,(engine,sidecar,status))

def engine_ready(engine:G.Engine,sidecar:Cooking.Sidecar) ->
    IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  match sidecar:
    case Cooking.Uninitialized{}:
      IO.pure(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>,(engine,Cooking.Uninitialized{},Done{Unit{}}))
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,carrier,child <> rest}:
      IO.pure(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>,
        (engine,Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,carrier,child <> rest},
          Fail{"local-cooking:noncanonical-sidecar-tail"}))
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,Owner.Unbound{},Nil{}}:
      engine_fallback(engine,Cooking.deliver_pending(Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,Owner.Unbound{},[]}))
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,Owner.PublicationOnly{publisher},Nil{}}:
      engine_fallback(engine,Cooking.deliver_pending(Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,Owner.PublicationOnly{publisher},[]}))
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,
        Owner.Bound{entity_context,owner,inputs,geometry,publisher},Nil{}}:
      bound_engine(engine,carrier => pending => Cooking.Initialized{context,light,loading,entries,phase,keys,pending,details,incarnations,acknowledged,carrier,[]},
        entity_context,effects,owner,inputs,geometry,publisher)

def engine_checked(registry:Registry.Registry,sidecar:Cooking.Sidecar,result:C.World & Bool) ->
    IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  (world,valid) = result
  match valid:
    case False{}: IO.pure(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>,(G.Engine{world,registry},sidecar,Fail{"local-cooking:invalid-context"}))
    case True{}: engine_ready(G.Engine{world,registry},sidecar)

def deliver_engine_io(sidecar:Cooking.Sidecar,engine:G.Engine) ->
    IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  match sidecar:
    case Cooking.Uninitialized{}: engine_ready(engine,Cooking.Uninitialized{})
    case Cooking.Initialized{+context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,carrier,tail}:
      G.Engine{world,registry} = engine
      engine_checked(registry,Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,carrier,tail},
        Cooking.checked_world(world,context))
