import Base
import ../src/json.bend as J
import ../src/inventory.bend as I
import ../src/core.bend as C
import ../src/random.bend as R
import ../src/vanilla_entity_fields.bend as V
import ../src/campfire_authority_items.bend as A
import ../src/campfire_authority_loader.bend as campfire_authority_loader
import ../src/furnace_authority.bend as furnace_authority
import ../src/cooking_world_store.bend as Store
import ../src/cooking_effect_entities_model.bend as E
import ../src/cooking_effect_entities.bend as D
import ../src/cooking_effect_entities_math.bend as M
import ../src/cooking_effect_entities_query.bend as Q
import ../src/cooking_effect_entities_clock.bend as Clock
import ./cooking_effect_entities_values.bend as T

def clear(geometry:Bool,dimension:String,point:V.Vec3) -> Result<&2,&2,E.Error,V.Vec3>: Done{point}
def unknown(geometry:Bool,dimension:String,point:V.Vec3) -> Result<&2,&2,E.Error,V.Vec3>: Fail{E.Refused{"unloaded collision section"}}
def context(items:A.Context,steps:Nat,ids:Nat,reserved:List<&2,U32>) -> E.Context: E.Context{items,E.Limits{steps,64n,ids},reserved}
def initial() -> E.State: E.new(R.seeded_legacy(R.Bits64{0,123}),E.java_initial_uniquifier(),0)
def times() -> List<&2,R.Bits64>: [R.Bits64{0,1},R.Bits64{0,2},R.Bits64{0,3},R.Bits64{0,4}]
def position() -> C.Position: C.Position{"minecraft:overworld",0,64,0}
def stack(count:U32) -> I.Slot: I.InvStack{I.ItemKey{"minecraft:stone",""},count}
def expected() -> String: J.encode(T.view(E.View{R.seeded_legacy(R.Bits64{0,123}),E.java_initial_uniquifier(),0,0n,[]}))
def report(label:String,value:Bool) -> J.Value: J.JObject{[J.JMember{"label",J.JString{label}},J.JMember{"ok",J.JBool{value}}]}
def unchanged_snapshot(before:String,failed:Bool,result:E.State & E.View) -> Bool:
  (state,view) = result
  failed && String.eq(before,J.encode(T.view(view)))
def refused(before:String,result:E.State & Result<&2,&2,E.Error,List<&2,R.Bits64>>) -> Bool:
  match result:
    case (state,Fail{error}): unchanged_snapshot(before,True{},E.inspect(state))
    case (state,Done{times}): False{}
def id(result:Result<&2,&2,E.Error,U32>,wanted:U32) -> Bool:
  match result:
    case Done{actual}: U32.is_eq(actual,wanted)
    case _: False{}
def suffix(pending:List<&2,Store.Effect>,status:Result<&2,&2,E.Error,Unit>,times:List<&2,R.Bits64>) -> Bool:
  match pending status times:
    case Store.Drop{p,0,I.InvStack{I.ItemKey{id,c},1}} <> Store.Dirty{q} <> Nil{} Fail{E.EntropyNeeded{1n}} Nil{}: True{}
    case _ _ _: False{}
def prefix_view(valid:Bool,result:E.State & E.View) -> Bool:
  (state,E.View{level,unique,cursor,order,records}) = result
  valid && Bool.not(String.eq(J.encode(T.source(level)),J.encode(T.source(R.seeded_legacy(R.Bits64{0,123}))))) &&
    String.eq(J.encode(T.bits(unique)),J.encode(T.bits(E.java_initial_uniquifier()))) && U32.is_zero(cursor) && Nat.is_eq(order,0n) && Nat.is_eq(List.length(&2,E.Record,records),0n)
def prefix_fields(pending:List<&2,Store.Effect>,status:Result<&2,&2,E.Error,Unit>,times:List<&2,R.Bits64>,result:E.State & E.View) -> Bool:
  prefix_view(suffix(pending,status,times),result)
def prefix(result:E.State & D.Outcome) -> Bool:
  (state,D.Outcome{pending,status,times}) = result
  prefix_fields(pending,status,times,E.inspect(state))
def guards(+items:A.Context) -> List<&2,J.Value>:
  [report("fragment budget refusal retains complete owner",refused(expected(),D.apply(~Bool,~clear,False{},context(items,1n,1024n,[]),Store.Drop{position(),0,stack(99)},initial(),times()))),
   report("constructor entropy refusal retains complete owner",refused(expected(),D.apply(~Bool,~clear,False{},context(items,64n,1024n,[]),Store.Drop{position(),0,stack(1)},initial(),[]))),
   report("invalid component identity refusal retains owner",refused(expected(),D.apply(~Bool,~clear,False{},context(items,64n,1024n,[]),Store.Drop{position(),0,I.InvStack{I.ItemKey{"minecraft:stone","forged"},1}},initial(),times()))),
   report("unloaded XP placement refusal retains RNG and owner",refused(expected(),D.apply(~Bool,~unknown,False{},context(items,64n,1024n,[]),Store.Experience{position(),furnace_authority.XpRequest{"r",1,1.0}},initial(),times()))),
   report("entity ID refusal retains candidate and RNG",refused(expected(),D.apply(~Bool,~clear,False{},context(items,64n,0n,[]),Store.Drop{position(),0,stack(1)},initial(),times()))),
   report("ordered prefix commits empty RNG draws and keeps failed suffix",prefix(D.deliver(~Bool,~clear,False{},context(items,64n,1024n,[]),[Store.Drop{position(),0,I.InvEmpty{}},Store.Drop{position(),0,stack(1)},Store.Dirty{position()}],initial(),[]))),
   report("ID allocator skips signed wrapping zero and reserved IDs",id(E.next_id(context(items,64n,4n,[1,2]),4294967295,[]),3)),
   report("signed wrapping XP residue",Q.residue(4294967256,0) && Bool.not(Q.residue(4294967257,0)))]
def respond(values:List<&2,J.Value>) -> IO(Unit): IO.print(J.encode(J.JArray{values}))
def item_total(records:List<&2,E.Record>) -> U32:
  match records:
    case Nil{}: 0
    case E.Item{common,I.InvStack{key,count},age,delay,health,thrower,target,bob} <> rest: U32.add(count,item_total(rest))
    case head <> rest: item_total(rest)
def clock_view(valid:Bool,result:E.State & E.View) -> Bool:
  (state,E.View{level,unique,+cursor,order,+records}) = result
  valid && U32.is_gt(cursor,1) && Nat.is_eq(order,List.length(&2,E.Record,records)) && U32.is_eq(item_total(records),99)
def clock_spawn(result:E.State & Result<&2,&2,E.Error,Unit>) -> Bool:
  match result:
    case (state,Fail{error}): False{}
    case (state,Done{unit}): clock_view(True{},E.inspect(state))
def loaded(result:Result<&2,&2,String,A.Context>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{+items}:
      do IO<Unit>:
        +first : R.Bits64 <- Clock.now()
        second : R.Bits64 <- Clock.now()
        spawned : E.State & Result<&2,&2,E.Error,Unit> <- Clock.apply(~Bool,~clear,False{},context(items,64n,1024n,[]),Store.Drop{position(),0,stack(99)},initial())
        respond(report("native clock retry installs every actual stack fragment",clock_spawn(spawned)) <> report("native monotonic clock returns progressing 64-bit nanoseconds",Bool.not(R.bits_zero(first)) && Bool.not(String.eq(J.encode(T.bits(first)),J.encode(T.bits(second))))) <> guards(items))
def parsed(result:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{value}: loaded(campfire_authority_loader.catalog(value))
def read_done(result:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status) = result
  do IO<Unit>:
    File.close(file)
    input : String <- IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))
    parsed(J.parse_bounded(input,16777216n,64))
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> path <> Nil{}:
      do IO<Unit>:
        file : File <- IO.try(File,File.open(path,"r"))
        result : File & Result<&1,&1,U32 & String,String> <- File.read(file,16777216)
        read_done(result)
    case _: IO.die(Unit,2,"expected initialized catalog fixture path")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
