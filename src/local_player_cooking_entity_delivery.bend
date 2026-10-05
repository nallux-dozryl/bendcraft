import Base
import ./game.bend as G
import ./local_player_cooking_geometry_owner.bend as Owner
import ./local_player_cooking_geometry.bend as Capture
import ./cooking_effect_geometry.bend as Geometry
import ./cooking_effect_entities_model.bend as Model
import ./cooking_effect_entities.bend as Entities
import ./cooking_effect_consumer.bend as Consumer
import ./cooking_world_store.bend as Store
import ./random.bend as Random
import ./vanilla_entity_fields.bend as V

# The first actual placement request triggers capture. Existing orb merges
# complete without this callback, so unavailable cells do not reject a merge.
def uncaptured(unit:Unit,dimension:String,point:V.Vec3) -> Result<&2,&2,Model.Error,V.Vec3>:
  Fail{Model.Refused{"local-cooking:geometry-capture-required"}}

def requested(status:Result<&2,&2,Model.Error,Unit>) -> Bool:
  match status:
    case Fail{Model.Refused{message}}: String.eq(message,"local-cooking:geometry-capture-required")
    case _: False{}

def clock_budget(context:Model.Context) -> Nat:
  Model.Context{items,Model.Limits{steps,rejections,ids},reserved} = context
  steps

def stopped(engine:G.Engine,geometry:Maybe<&1,Owner.Owner>,owner:Model.State,
    pending:List<&2,Store.Effect>,rest:List<&2,Store.Effect>,status:Result<&2,&2,Model.Error,Unit>,times:List<&2,Random.Bits64>) ->
    G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome:
  (engine,geometry,owner,Entities.Outcome{List.append(&2,Store.Effect,pending,rest),status,times})

def completed(engine:G.Engine,geometry:Maybe<&1,Owner.Owner>,rest:List<&2,Store.Effect>,
    result:Model.State & Entities.Outcome,
    next:G.Engine -> Maybe<&1,Owner.Owner> -> Model.State -> List<&2,Random.Bits64> ->
      IO(G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome)) ->
    IO(G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome):
  (owner,Entities.Outcome{pending,status,times}) = result
  match status:
    case Fail{error}: IO.pure(G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome,
      stopped(engine,geometry,owner,pending,rest,Fail{error},times))
    case Done{unit}: next(engine)(geometry)(owner)(times)

def captured(+effect:Store.Effect,rest:List<&2,Store.Effect>,+context:Model.Context,
    owner:Model.State,times:List<&2,Random.Bits64>,
    next:G.Engine -> Maybe<&1,Owner.Owner> -> Model.State -> List<&2,Random.Bits64> ->
      IO(G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome),
    result:G.Engine & Owner.Owner & Result<&2,&2,String,Geometry.Context>) ->
    IO(G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome):
  (engine,geometry,status) = result
  match status:
    case Fail{message}: IO.pure(G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome,
      (engine,Some{geometry},owner,Entities.Outcome{effect <> rest,Fail{Model.Refused{message}},times}))
    case Done{snapshot}:
      do IO<G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome>:
        result : Model.State & Entities.Outcome <- Consumer.deliver_io(~Geometry.Context,~Geometry.place,
          clock_budget(context),snapshot,context,[effect],owner,times)
        completed(engine,Some{geometry},rest,result,next)

def capture_needed(+effect:Store.Effect,rest:List<&2,Store.Effect>,engine:G.Engine,
    geometry:Maybe<&1,Owner.Owner>,context:Model.Context,owner:Model.State,times:List<&2,Random.Bits64>,
    next:G.Engine -> Maybe<&1,Owner.Owner> -> Model.State -> List<&2,Random.Bits64> ->
      IO(G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome)) ->
    IO(G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome):
  match geometry:
    case None{}: IO.pure(G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome,
      (engine,None{},owner,Entities.Outcome{effect <> rest,
        Fail{Model.Refused{"cooking-effects:entity-collision-placement-owner-required"}},times}))
    case Some{geometry}:
      captured(effect,rest,context,owner,times,next,Capture.capture(engine,geometry,effect))

def capture_result(+effect:Store.Effect,rest:List<&2,Store.Effect>,engine:G.Engine,
    geometry:Maybe<&1,Owner.Owner>,context:Model.Context,
    next:G.Engine -> Maybe<&1,Owner.Owner> -> Model.State -> List<&2,Random.Bits64> ->
      IO(G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome),
    result:Model.State & Entities.Outcome) ->
    IO(G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome):
  (owner,Entities.Outcome{pending,status,times}) = result
  capture_needed(effect,rest,engine,geometry,context,owner,times,next)

def attempted(+effect:Store.Effect,rest:List<&2,Store.Effect>,engine:G.Engine,
    geometry:Maybe<&1,Owner.Owner>,context:Model.Context,
    next:G.Engine -> Maybe<&1,Owner.Owner> -> Model.State -> List<&2,Random.Bits64> ->
      IO(G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome),
    result:Model.State & Entities.Outcome,needs:Bool) ->
    IO(G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome):
  match needs:
    case False{}: completed(engine,geometry,rest,result,next)
    case True{}: capture_result(effect,rest,engine,geometry,context,next,result)

def observed(+effect:Store.Effect,rest:List<&2,Store.Effect>,engine:G.Engine,
    geometry:Maybe<&1,Owner.Owner>,context:Model.Context,
    next:G.Engine -> Maybe<&1,Owner.Owner> -> Model.State -> List<&2,Random.Bits64> ->
      IO(G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome),
    result:Model.State & Entities.Outcome) ->
    IO(G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome):
  (owner,+outcome) = result
  Entities.Outcome{pending,+status,times} = outcome
  attempted(effect,rest,engine,geometry,context,next,(owner,outcome),requested(status))

def admitted(+effect:Store.Effect,rest:List<&2,Store.Effect>,engine:G.Engine,
    geometry:Maybe<&1,Owner.Owner>,+context:Model.Context,owner:Model.State,times:List<&2,Random.Bits64>,
    next:G.Engine -> Maybe<&1,Owner.Owner> -> Model.State -> List<&2,Random.Bits64> ->
      IO(G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome),allowed:Bool) ->
    IO(G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome):
  match allowed:
    case False{}: IO.pure(G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome,
      (engine,geometry,owner,Entities.Outcome{effect <> rest,
        Fail{Model.Refused{"cooking-effects:per-level-random-owner-required"}},times}))
    case True{}:
      do IO<G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome>:
        result : Model.State & Entities.Outcome <- Consumer.deliver_io(~Unit,~uncaptured,
          clock_budget(context),Unit{},context,[effect],owner,times)
        observed(effect,rest,engine,geometry,context,next,result)

# Each committed effect advances once. Geometry/entropy retries operate only
# on the current atomic effect and retain all successful earlier mutations.
def deliver_io(~supported:Store.Effect -> Bool,effects:List<&2,Store.Effect>,engine:G.Engine,geometry:Maybe<&1,Owner.Owner>,
    +context:Model.Context,owner:Model.State,times:List<&2,Random.Bits64>) ->
    IO(G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome):
  match effects:
    case Nil{}: IO.pure(G.Engine & Maybe<&1,Owner.Owner> & Model.State & Entities.Outcome,
      (engine,geometry,owner,Entities.Outcome{[],Done{Unit{}},times}))
    case +effect <> +rest:
      admitted(effect,rest,engine,geometry,context,owner,times,
        engine => geometry => owner => times => deliver_io(~supported,rest,engine,geometry,context,owner,times),supported(effect))
