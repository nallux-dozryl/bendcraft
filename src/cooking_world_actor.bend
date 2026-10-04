import Base
import ./core.bend as C
import ./block_light.bend as L
import ./block_light_world.bend as W
import ./cooking_world.bend as B
import ./cooking_world_tick.bend as T
import ./cooking_world_store.bend as S

def started(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,context:B.Context,result:B.State & Result<&2,&2,B.Error,Unit>) -> B.State & Result<&2,&2,B.Error,List<&2,S.Effect>>:
  (owner,status) = result
  match status:
    case Fail{error}: (owner,Fail{error})
    case Done{unit}: T.finish_tick(~Light,~properties,~enabled,light_context,context,owner)
def unpaused(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    +light_context:Light,+context:B.Context,owner:B.State,paused:Bool) -> B.State & Result<&2,&2,B.Error,List<&2,S.Effect>>:
  match paused:
    case True{}: (owner,Done{[]})
    case False{}: started(~Light,~properties,~enabled,light_context,context,B.start_tick(~Light,~properties,~enabled,light_context,context,owner))
# Call once at the existing vanilla simulation cadence. Pending cooking resumes
# its original tick before another Core tick is admitted. Failures return that
# complete recoverable owner; a successful result releases effects once.
def realtime_tick(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,context:B.Context,owner:B.State) -> B.State & Result<&2,&2,B.Error,List<&2,S.Effect>>:
  match owner:
    case B.State{world,entries,B.Cooking{tick,effects},keys}:
      T.finish_tick(~Light,~properties,~enabled,light_context,context,B.State{world,entries,B.Cooking{tick,effects},keys})
    case B.State{W.State{C.World{tick,time,+paused,daylight,revision,count,sections,pending,events},light,loading},entries,B.Idle{},keys}:
      unpaused(~Light,~properties,~enabled,light_context,context,
        B.State{W.State{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},light,loading},entries,B.Idle{},keys},paused)
