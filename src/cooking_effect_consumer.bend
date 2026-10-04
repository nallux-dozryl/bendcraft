import Base
import ./random.bend as R
import ./vanilla_entity_fields.bend as V
import ./cooking_world_store.bend as Store
import ./cooking_effect_entities_model.bend as E
import ./cooking_effect_entities.bend as Entities
import ./cooking_effect_entities_clock.bend as Clock

# Keep the actual affine entity owner and every unconsumed constructor clock
# input alongside the exact pending suffix. The world/placement receiver is
# supplied by the caller from its sole Core; this seam never creates a world.
def deliver(~Geometry:Data,~place:Geometry -> String -> V.Vec3 -> Result<&2,&2,E.Error,V.Vec3>,
    geometry:Geometry,context:E.Context,effects:List<&2,Store.Effect>,state:E.State,times:List<&2,R.Bits64>) -> E.State & Entities.Outcome:
  Entities.deliver(~Geometry,~place,geometry,context,effects,state,times)

def resumed(result:E.State & Entities.Outcome,
    next:List<&2,Store.Effect> -> E.State -> List<&2,R.Bits64> -> IO(E.State & Entities.Outcome)) -> IO(E.State & Entities.Outcome):
  match result:
    case (state,Entities.Outcome{pending,Fail{E.EntropyNeeded{needed}},times}):
      IO.bind(R.Bits64,E.State & Entities.Outcome,Clock.now(),
        time => next(pending)(state)(List.append(&2,R.Bits64,times,[time])))
    case result: IO.pure(E.State & Entities.Outcome,result)

# Monotonic time acquisition is an explicit IO boundary. A completed prefix is
# never replayed. Exhausting the caller's clock budget preserves the owner,
# failing effect, exact suffix and all clock inputs for atomic save/recovery.
# Empty item drops commit their three LEVEL draws without reading the clock.
def deliver_io(~Geometry:Data,~place:Geometry -> String -> V.Vec3 -> Result<&2,&2,E.Error,V.Vec3>,
    left:Nat,+geometry:Geometry,+context:E.Context,effects:List<&2,Store.Effect>,state:E.State,times:List<&2,R.Bits64>) -> IO(E.State & Entities.Outcome):
  match left:
    case 0n:
      IO.pure(E.State & Entities.Outcome,deliver(~Geometry,~place,geometry,context,effects,state,times))
    case 1n+rest:
      resumed(deliver(~Geometry,~place,geometry,context,effects,state,times),
        pending => owner => values => deliver_io(~Geometry,~place,rest,geometry,context,pending,owner,values))
