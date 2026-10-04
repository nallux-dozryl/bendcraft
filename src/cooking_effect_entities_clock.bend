import Base
import ./random.bend as R
import ./vanilla_entity_fields.bend as V
import ./cooking_world_store.bend as Store
import ./cooking_effect_entities_model.bend as E
import ./cooking_effect_entities.bend as D

def Native.nanoseconds() -> IO(U32 & U32):
  import "./cooking_effect_entities_clock.c"
  import "./cooking_effect_entities_clock.js"
def words(value:U32 & U32) -> R.Bits64:
  (hi,lo) = value
  R.Bits64{hi,lo}
def now() -> IO(R.Bits64):
  do IO<R.Bits64>:
    value : U32 & U32 <- Native.nanoseconds()
    return words(value)
def completed(result:E.State & Result<&2,&2,E.Error,List<&2,R.Bits64>>) -> E.State & Result<&2,&2,E.Error,Unit>:
  (state,status) = result
  (state,Result.map(&2,&2,E.Error,List<&2,R.Bits64>,Unit,times => Unit{},status))
def finished(state:E.State,result:Result<&2,&2,E.Error,E.Plan>) -> E.State & Result<&2,&2,E.Error,Unit>:
  completed(E.commit(state,result))
def retry(+times:List<&2,R.Bits64>,state:E.State,result:Result<&2,&2,E.Error,E.Plan>,
    next:E.State -> List<&2,R.Bits64> -> IO(E.State & Result<&2,&2,E.Error,Unit>)) -> IO(E.State & Result<&2,&2,E.Error,Unit>):
  match result:
    case Fail{E.EntropyNeeded{count}}:
      do IO<E.State & Result<&2,&2,E.Error,Unit>>:
        time : R.Bits64 <- now()
        next(state)(List.append(&2,R.Bits64,times,[time]))
    case result: IO.pure(E.State & Result<&2,&2,E.Error,Unit>,finished(state,result))
def attempt(~Geometry:Data,~place:Geometry -> String -> V.Vec3 -> Result<&2,&2,E.Error,V.Vec3>,
    left:Nat,+geometry:Geometry,+context:E.Context,+effect:Store.Effect,state:E.State,+view:E.View,+times:List<&2,R.Bits64>) -> IO(E.State & Result<&2,&2,E.Error,Unit>):
  match left:
    case 0n: IO.pure(E.State & Result<&2,&2,E.Error,Unit>,finished(state,D.plan(~Geometry,~place,geometry,context,effect,view,times)))
    case 1n+rest:
      retry(times,state,D.plan(~Geometry,~place,geometry,context,effect,view,times),
        owner => values => attempt(~Geometry,~place,rest,geometry,context,effect,owner,view,values))
def inspected(~Geometry:Data,~place:Geometry -> String -> V.Vec3 -> Result<&2,&2,E.Error,V.Vec3>,
    geometry:Geometry,context:E.Context,effect:Store.Effect,left:Nat,result:E.State & E.View) -> IO(E.State & Result<&2,&2,E.Error,Unit>):
  (state,view) = result
  attempt(~Geometry,~place,left,geometry,context,effect,state,view,[])
# System.nanoTime-equivalent monotonic nanoseconds is the only new host gap.
# Java factory mixing and all entity/RNG semantics remain in pure Bend.
def apply(~Geometry:Data,~place:Geometry -> String -> V.Vec3 -> Result<&2,&2,E.Error,V.Vec3>,
    geometry:Geometry,+context:E.Context,effect:Store.Effect,state:E.State) -> IO(E.State & Result<&2,&2,E.Error,Unit>):
  E.Context{items,E.Limits{steps,rejections,ids},reserved} = context
  inspected(~Geometry,~place,geometry,context,effect,steps,E.inspect(state))
