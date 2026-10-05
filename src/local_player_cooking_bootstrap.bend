import Base
import ./core.bend as C
import ./local_player_cooking.bend as Cooking
import ./local_player_cooking_entity_owner.bend as Owner
import ./cooking_effect_entities_model.bend as Model
import ./cooking_effect_entities_math.bend as Math
import ./cooking_effect_entities_clock.bend as Clock
import ./random.bend as Random
import ./local_player_cooking_publication_owner.bend as Publisher
import ./local_player_cooking_tick_owner.bend as Tick

# A declared fresh isolated actor process owns this factory boundary. Its
# Level Legacy source is independent of the world seed. The following sound
# factory allocation also advances the same constructor uniquifier. This
# profile has no preexisting entity allocator: its pinned static cursor is 0.
# Saved complete Views bypass this transition entirely.
def sound_created(level:Random.Source,result:Random.Bits64 & Random.Source) -> Model.State:
  (unique,sound) = result
  Model.new(level,unique,0)

def sound_time(level:Random.Source,unique:Random.Bits64,time:Random.Bits64) -> Model.State:
  sound_created(level,Math.constructor_source(unique,time))

def level_created(result:Random.Bits64 & Random.Source) -> IO(Model.State):
  (unique,level) = result
  do IO<Model.State>:
    observed : Random.Bits64 <- Clock.now()
    return sound_time(level,unique,observed)

def fresh() -> IO(Model.State):
  do IO<Model.State>:
    observed : Random.Bits64 <- Clock.now()
    level_created(Math.constructor_source(Model.java_initial_uniquifier(),observed))

# The actual actor retains the sound source allocated by the same second
# constructor call. The legacy fresh API above keeps its historical return.
def sound_created_owned(level:Random.Source,result:Random.Bits64 & Random.Source) -> Model.State & Random.Source:
  (unique,sound) = result
  (Model.new(level,unique,0),sound)

def sound_time_owned(level:Random.Source,unique:Random.Bits64,time:Random.Bits64) -> Model.State & Random.Source:
  sound_created_owned(level,Math.constructor_source(unique,time))

def level_created_owned(result:Random.Bits64 & Random.Source) -> IO(Model.State & Random.Source):
  (unique,level) = result
  do IO<Model.State & Random.Source>:
    observed : Random.Bits64 <- Clock.now()
    return sound_time_owned(level,unique,observed)

def fresh_owned() -> IO(Model.State & Random.Source):
  do IO<Model.State & Random.Source>:
    observed : Random.Bits64 <- Clock.now()
    level_created_owned(Math.constructor_source(Model.java_initial_uniquifier(),observed))

def finished_owned(world:C.World,restore:Model.State -> Tick.State -> Cooking.Sidecar,result:Model.State & Random.Source) ->
    C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>:
  (owner,sound) = result
  (world,restore(owner)(Tick.fresh(sound)),Done{Unit{}})

def finished(world:C.World,restore:Model.State -> Cooking.Sidecar,owner:Model.State) -> C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>:
  (world,restore(owner),Done{Unit{}})

def ready(world:C.World,sidecar:Cooking.Sidecar,entity_context:Model.Context) -> IO(C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  match sidecar:
    case Cooking.Uninitialized{}:
      IO.pure(C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>,(world,Cooking.Uninitialized{},Fail{"local-cooking:uninitialized"}))
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,entity_owner,child <> rest}:
      IO.pure(C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>,
        (world,Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,entity_owner,child <> rest},
          Fail{"local-cooking:noncanonical-sidecar-tail"}))
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,Owner.Bound{previous,owner,inputs,geometry,publisher},Nil{}}:
      IO.pure(C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>,
        (world,Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,Owner.Bound{previous,owner,inputs,geometry,publisher},[]},
          Fail{"local-cooking:entity-owner-already-bound"}))
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,
        Owner.TickBound{previous,owner,inputs,geometry,publisher,tick},Nil{}}:
      IO.pure(C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>,
        (world,Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,
          Owner.TickBound{previous,owner,inputs,geometry,publisher,tick},[]},Fail{"local-cooking:entity-owner-already-bound"}))
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,Owner.Unbound{},Nil{}}:
      do IO<C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>>:
        result : Model.State & Random.Source <- fresh_owned()
        return finished_owned(world,owner => tick => Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,
          Owner.TickBound{entity_context,owner,[],None{},Publisher.empty(),tick},[]},result)
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,Owner.PublicationOnly{publisher},Nil{}}:
      do IO<C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>>:
        result : Model.State & Random.Source <- fresh_owned()
        return finished_owned(world,owner => tick => Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,
          Owner.TickBound{entity_context,owner,[],None{},publisher,tick},[]},result)

def checked(sidecar:Cooking.Sidecar,context:Model.Context,result:C.World & Bool) -> IO(C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  (world,valid) = result
  match valid:
    case False{}:
      IO.pure(C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>,(world,sidecar,Fail{"local-cooking:invalid-context"}))
    case True{}: ready(world,sidecar,context)

# Canonical admission and an unbound carrier are checked before either actual
# clock read. Every refusal retains the sole World and complete Sidecar.
def begin(world:C.World,sidecar:Cooking.Sidecar,entity_context:Model.Context) -> IO(C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  match sidecar:
    case Cooking.Uninitialized{}: ready(world,Cooking.Uninitialized{},entity_context)
    case Cooking.Initialized{+context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,entity_owner,tail}:
      checked(Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,entity_owner,tail},entity_context,
        Cooking.checked_world(world,context))
