import Base
import ./item_entity_tick_model.bend as T
import ./item_entity_tick.bend as Tick
import ./item_entity_tick_fields.bend as U
import ./item_entity_tick_merge.bend as Merge
import ./cooking_effect_entities_model.bend as E
import ./random.bend as R

def runtime_for(values:List<&2,T.RuntimeEntry>,+id:U32) -> Result<&2,&2,T.Error,T.Runtime>:
  match values:
    case Nil{}: Fail{T.Refused{"item tick runtime is missing; restored defaults cannot be guessed"}}
    case T.RuntimeEntry{+key,+runtime} <> +rest:
      U.select(Result<&2,&2,T.Error,T.Runtime>,Done{runtime},runtime_for(rest,id),U32.is_eq(id,key))
def replace_runtime(values:List<&2,T.RuntimeEntry>,+id:U32,+runtime:T.Runtime) -> List<&2,T.RuntimeEntry>:
  match values:
    case Nil{}: []
    case T.RuntimeEntry{+key,+prior} <> +rest:
      T.RuntimeEntry{key,U.select(T.Runtime,runtime,prior,U32.is_eq(key,id))} <> replace_runtime(rest,id,runtime)
def found(records:List<&2,E.Record>,+id:U32) -> Result<&2,&2,T.Error,E.Record>:
  match records:
    case Nil{}: Fail{T.Refused{"item tick entity ID is absent"}}
    case +record <> +rest:
      U.select(Result<&2,&2,T.Error,E.Record>,Done{record},found(rest,id),U32.is_eq(E.record_id(record),id))
def count_id(records:List<&2,E.Record>,+id:U32) -> U32:
  match records:
    case Nil{}: 0
    case +record <> +rest: U32.add(U.select(U32,1,0,U32.is_eq(E.record_id(record),id)),count_id(rest,id))
def count_runtime(values:List<&2,T.RuntimeEntry>,+id:U32) -> U32:
  match values:
    case Nil{}: 0
    case T.RuntimeEntry{+key,+r} <> +rest: U32.add(U.select(U32,1,0,U32.is_eq(key,id)),count_runtime(rest,id))
def snapshot_phase(+record:E.Record,+runtime:T.Runtime,+common:Bool) -> T.Snapshot:
  U.select(T.Snapshot,Tick.common_tick(T.Snapshot{record,runtime}),T.Snapshot{record,runtime},common)
def planned(+context:T.Context,+view:E.View,+runtimes:List<&2,T.RuntimeEntry>,+id:U32,+common:Bool) -> Result<&2,&2,T.Error,T.Plan>:
  E.View{+level,+unique,+cursor,+order,+records}=view
  do Result<&2,&2,T.Error,T.Plan>:
    _ : Unit <- U.guard(U32.is_eq(count_id(records,id),1) && U32.is_eq(count_runtime(runtimes,id),1),"item tick entity/runtime ID must be unique")
    +record : E.Record <- found(records,id)
    _ : Unit <- U.guard(Bool.not(U.removed(record)),"removed item must leave tick scheduling after removal publication")
    +runtime : T.Runtime <- runtime_for(runtimes,id)
    Tick.plan(context,snapshot_phase(record,runtime,common),records)
type Sounds is Data:
  Sounds{source:Maybe<&2,R.Source>,events:List<&2,T.Publication>}
def sound_tail(+head:T.Publication,value:Sounds) -> Sounds:
  Sounds{+source,+events}=value
  Sounds{source,head <> events}
def sounded(+head:T.Publication,result:R.Source & R.Bits64,next:Maybe<&2,R.Source> -> Result<&2,&2,T.Error,Sounds>) -> Result<&2,&2,T.Error,Sounds>:
  match head:
    case T.Splash{+position,+volume,+pitch,+high}:
      (+source,+seed)=result
      do Result<&2,&2,T.Error,Sounds>:
        +tail : Sounds <- next(Some{source})
        return sound_tail(T.SeededSplash{position,volume,pitch,high,seed},tail)
    case _: Fail{T.Refused{"internal item splash sound publication mismatch"}}
def sound_source(+head:T.Publication,source:Maybe<&2,R.Source>,next:Maybe<&2,R.Source> -> Result<&2,&2,T.Error,Sounds>) -> Result<&2,&2,T.Error,Sounds>:
  match source:
    case None{}: Fail{T.Refused{"item splash requires actual separate Level.soundSeedGenerator authority"}}
    case Some{+source}: sounded(head,R.next_long(source),next)
def sounds(values:List<&2,T.Publication>,+source:Maybe<&2,R.Source>) -> Result<&2,&2,T.Error,Sounds>:
  match values:
    case Nil{}: Done{Sounds{source,[]}}
    case T.Splash{+p,+v,+pitch,+high} <> +rest: sound_source(T.Splash{p,v,pitch,high},source,next => sounds(rest,next))
    case +head <> +rest:
      do Result<&2,&2,T.Error,Sounds>:
        +tail : Sounds <- sounds(rest,source)
        return sound_tail(head,tail)
def accepted(state:T.State,+view:E.View,+runtimes:List<&2,T.RuntimeEntry>,result:Result<&2,&2,T.Error,Sounds>) -> T.State & Result<&2,&2,T.Error,List<&2,T.Publication>>:
  match result:
    case Fail{+error}: (state,Fail{error})
    case Done{Sounds{+sound,+events}}: (T.State{E.install(view),runtimes,sound},Done{events})
def committed(state:T.State,+view:E.View,+runtimes:List<&2,T.RuntimeEntry>,result:Result<&2,&2,T.Error,T.Plan>,+sound:Maybe<&2,R.Source>) -> T.State & Result<&2,&2,T.Error,List<&2,T.Publication>>:
  E.View{+level,+unique,+cursor,+order,+prior}=view
  match result:
    case Fail{+error}: (state,Fail{error})
    case Done{T.Plan{T.Snapshot{+record,+runtime},+records,+events}}:
      accepted(state,E.View{level,unique,cursor,order,records},replace_runtime(runtimes,E.record_id(record),runtime),sounds(events,sound))
def inspected(+context:T.Context,+id:U32,+common:Bool,+runtimes:List<&2,T.RuntimeEntry>,+sound:Maybe<&2,R.Source>,result:E.State & E.View) -> T.State & Result<&2,&2,T.Error,List<&2,T.Publication>>:
  (entities,+view)=result
  committed(T.State{entities,runtimes,sound},view,runtimes,planned(context,view,runtimes,id,common),sound)
# The sound stream is independent of level_random and must never be fabricated.
# common=True is actual server tickNonPassenger commonTick -> ItemEntity.tick.
# Removed records/runtimes remain until the real removal publisher accepts.
def tick_id(+context:T.Context,+id:U32,+common:Bool,state:T.State) -> T.State & Result<&2,&2,T.Error,List<&2,T.Publication>>:
  T.State{entities,+runtimes,+sound}=state
  inspected(context,id,common,runtimes,sound,E.inspect(entities))
