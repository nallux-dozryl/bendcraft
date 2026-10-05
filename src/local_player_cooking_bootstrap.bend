import Base
import ./core.bend as C
import ./local_player_cooking.bend as Cooking
import ./local_player_cooking_entity_owner.bend as Owner
import ./cooking_effect_entities_model.bend as Model
import ./cooking_effect_entities_math.bend as Math
import ./cooking_effect_entities_clock.bend as Clock
import ./random.bend as Random

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
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,Owner.Bound{previous,owner,inputs,geometry},Nil{}}:
      IO.pure(C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>,
        (world,Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,Owner.Bound{previous,owner,inputs,geometry},[]},
          Fail{"local-cooking:entity-owner-already-bound"}))
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,Owner.Unbound{},Nil{}}:
      do IO<C.World & Cooking.Sidecar & Result<&2,&2,String,Unit>>:
        owner : Model.State <- fresh()
        return finished(world,owner => Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged_resets,
          Owner.Bound{entity_context,owner,[],None{}},[]},owner)

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
