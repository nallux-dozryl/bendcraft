import Base
import ./random.bend as R
import ./f64.bend as F
import ./vanilla_entity_fields.bend as V
import ./inventory.bend as I
import ./campfire_authority_items.bend as CI

type Uuid is Data:
  Uuid{most:R.Bits64,least:R.Bits64}
type Common is Data:
  Common{dimension:String,id:U32,uuid_most:R.Bits64,uuid_least:R.Bits64,
    random:R.Source,fields:V.Fields,tick_count:U32,first_tick:Bool,removed:Bool,
    accessible:Bool,section_order:Nat}
type Record is Data:
  Item{common:Common,item:I.Slot,age:U32,pickup_delay:U32,health:U32,
    thrower:Maybe<&2,Uuid>,target:Maybe<&2,Uuid>,bob:F32}
  Orb{common:Common,value:U32,age:U32,health:U32,count:U32,
    following:Maybe<&2,Uuid>}
type Entity is Type:
  Entity{record:Record}
type State is Type:
  State{level_random:R.Source,seed_uniquifier:R.Bits64,last_id:U32,
    next_section_order:Nat,entities:List<&1,Entity>}
type View is Data:
  View{level_random:R.Source,seed_uniquifier:R.Bits64,last_id:U32,
    next_section_order:Nat,records:List<&2,Record>}
type Limits is Data:
  Limits{spawn_steps:Nat,rejection_steps:Nat,id_steps:Nat}
type Context is Data:
  Context{items:CI.Context,limits:Limits,reserved_ids:List<&2,U32>}
type Error is Data:
  Refused{message:String}
  RandomFailure{error:R.RandomError}
  SpawnBudget{}
  IdBudget{}
  EntropyNeeded{count:Nat}
type Plan is Data:
  Plan{view:View,remaining_times:List<&2,R.Bits64>}
type Bounded is Data:
  Bounded{source:R.Source,value:U32}

def common(value:Record) -> Common:
  match value:
    case Item{base,item,age,delay,health,thrower,target,bob}: base
    case Orb{base,value,age,health,count,following}: base
def records_cons(+head:Record,result:List<&1,Entity> & List<&2,Record>) -> List<&1,Entity> & List<&2,Record>:
  (owners,tail) = result
  (Entity{head} <> owners,head <> tail)
def records(entities:List<&1,Entity>) -> List<&1,Entity> & List<&2,Record>:
  match entities:
    case Nil{}: ([],[])
    case Entity{+head} <> rest: records_cons(head,records(rest))
def inspected(+level:R.Source,+seed:R.Bits64,+cursor:U32,+order:Nat,result:List<&1,Entity> & List<&2,Record>) -> State & View:
  (owners,values) = result
  (State{level,seed,cursor,order,owners},View{level,seed,cursor,order,values})
# Complete immutable persistence/render snapshot alongside the sole owner.
def inspect(state:State) -> State & View:
  State{+level,+seed,+cursor,+order,entities} = state
  inspected(level,seed,cursor,order,records(entities))
def install_records(values:List<&2,Record>) -> List<&1,Entity>:
  match values:
    case Nil{}: []
    case head <> rest: Entity{head} <> install_records(rest)
def install(view:View) -> State:
  View{level,seed,cursor,order,values} = view
  State{level,seed,cursor,order,install_records(values)}
def new(level:R.Source,seed_uniquifier:R.Bits64,last_id:U32) -> State:
  State{level,seed_uniquifier,last_id,0n,[]}
def java_initial_uniquifier() -> R.Bits64: R.Bits64{2021557,1605148140}
def commit(state:State,result:Result<&2,&2,Error,Plan>) -> State & Result<&2,&2,Error,List<&2,R.Bits64>>:
  match result:
    case Fail{error}: (state,Fail{error})
    case Done{Plan{view,times}}: (install(view),Done{times})
def refused(message:String) -> Result<&2,&2,Error,Unit>: Fail{Refused{message}}
def guard(value:Bool,message:String) -> Result<&2,&2,Error,Unit>:
  match value:
    case False{}: refused(message)
    case True{}: Done{Unit{}}
def random_result(result:R.Source & Result<&2,&2,R.RandomError,U32>) -> Result<&2,&2,Error,Bounded>:
  match result:
    case (source,Fail{error}): Fail{RandomFailure{error}}
    case (source,Done{value}): Done{Bounded{source,value}}
def common_id(value:Common) -> U32:
  Common{d,id,a,b,r,f,t,first,removed,accessible,order} = value
  id
def record_id(value:Record) -> U32: common_id(common(value))
def id_used(values:List<&2,Record>,+wanted:U32) -> Bool:
  match values:
    case Nil{}: False{}
    case head <> rest:
      U32.is_eq(record_id(head),wanted) || id_used(rest,wanted)
def reserved(values:List<&2,U32>,+wanted:U32) -> Bool:
  match values:
    case Nil{}: False{}
    case head <> rest: U32.is_eq(head,wanted) || reserved(rest,wanted)
def id_choice(value:U32,valid:Bool) -> Maybe<&2,U32>:
  match valid:
    case False{}: None{}
    case True{}: Some{value}
def id_loop(left:Nat,+cursor:U32,+values:List<&2,Record>,+ids:List<&2,U32>,candidate:Maybe<&2,U32>) -> Result<&2,&2,Error,U32>:
  match left candidate:
    case _ Some{value}: Done{value}
    case 0n _: Fail{IdBudget{}}
    case 1n+rest None{}:
      +next = U32.inc(cursor)
      id_loop(rest,next,values,ids,id_choice(next,Bool.not(U32.is_zero(next) || id_used(values,next) || reserved(ids,next))))
def next_id(context:Context,cursor:U32,values:List<&2,Record>) -> Result<&2,&2,Error,U32>:
  Context{items,Limits{steps,rejections,ids},reserved} = context
  id_loop(ids,cursor,values,reserved,None{})
