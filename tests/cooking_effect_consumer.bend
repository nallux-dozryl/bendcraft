import Base
import ../src/cooking_effect_consumer.bend as Consumer
import ../src/cooking_effect_entities.bend as Entities
import ../src/cooking_effect_entities_model.bend as E
import ../src/local_player_effect_entities_codec.bend as Codec
import ../src/cooking_effect_recovery.bend as Recovery
import ../src/cooking_world_store.bend as Store
import ../src/cooking_recipe.bend as K
import ../src/crafting_recipe.bend as Craft
import ../src/crafting_recipe_components.bend as Components
import ../src/campfire_authority_items.bend as CI
import ../src/core.bend as C
import ../src/inventory.bend as I
import ../src/furnace_authority.bend as F
import ../src/random.bend as R
import ../src/vanilla_entity_fields.bend as V
import ../src/nbt.bend as N
import ../src/json.bend as J
import ../src/u32_decimal.bend as Decimal

def placement(owner:Unit,dimension:String,point:V.Vec3) -> Result<&2,&2,E.Error,V.Vec3>:
  Fail{E.Refused{"actual-world-orb-placement-unavailable"}}
def context() -> E.Context:
  # A focused one-item authority fixture, not the live registry/default loader.
  E.Context{CI.Context{K.Catalog{[],[],[Craft.ItemDefinition{"minecraft:stone",64,I.InvEmpty{}}]},
    [Components.Default{"minecraft:stone",J.JObject{[]}}],Map.new(&2,Maybe<&2,Bool>)},E.Limits{64n,64n,32n},[]}
def point() -> C.Position: C.Position{"minecraft:overworld",4294967289,65,3}
def empty_drop() -> Store.Effect: Store.Drop{point(),0,I.InvEmpty{}}
def stone(count:U32) -> Store.Effect: Store.Drop{point(),1,I.InvStack{I.ItemKey{"minecraft:stone",""},count}}
def blocked() -> List<&2,Store.Effect>: [Store.Dirty{point()},Store.OwnerReset{point()},empty_drop()]
def clocks() -> List<&2,R.Bits64>: [R.Bits64{1333781,1777858490},R.Bits64{111,222},R.Bits64{333,444}]
def limits() -> N.Limits: N.Limits{16777216,64,16777216}
def byte_text(values:List<&2,U32>) -> String:
  match values:
    case Nil{}: ""
    case word <> Nil{}: Decimal.show(word)
    case word <> rest: Decimal.show(word) ++ "," ++ byte_text(rest)
def clock_text(values:List<&2,R.Bits64>) -> String:
  match values:
    case Nil{}: ""
    case R.Bits64{hi,lo} <> Nil{}: Decimal.show(hi) ++ "," ++ Decimal.show(lo)
    case R.Bits64{hi,lo} <> rest: Decimal.show(hi) ++ "," ++ Decimal.show(lo) ++ "," ++ clock_text(rest)
def error_text(error:E.Error) -> String:
  match error:
    case E.Refused{message}: "refused:" ++ message
    case E.RandomFailure{R.InvalidBound{}}: "random:invalid-bound"
    case E.RandomFailure{R.RejectionFuelExhausted{}}: "random:rejection-fuel"
    case E.RandomFailure{R.UnsupportedHash{}}: "random:unsupported-hash"
    case E.SpawnBudget{}: "spawn-budget"
    case E.IdBudget{}: "id-budget"
    case E.EntropyNeeded{count}: "entropy:" ++ Nat.show(count)
def status_text(status:Result<&2,&2,E.Error,Unit>) -> String:
  match status:
    case Done{unit}: "done"
    case Fail{error}: error_text(error)
def encoded_bytes(status:Result<&2,&2,String,List<&2,U32>>) -> String:
  match status:
    case Fail{message}: "ERROR:" ++ message
    case Done{bytes}: byte_text(bytes)
def observed(label:String,outcome:Entities.Outcome,observed:E.State & E.View) -> IO(Unit):
  Entities.Outcome{pending,status,times} = outcome
  (state,view) = observed
  IO.print(label ++ "\t" ++ status_text(status) ++ "\t" ++ encoded_bytes(Codec.encode(limits(),view)) ++
    "\t" ++ encoded_bytes(Recovery.encode(limits(),pending)) ++ "\t" ++ clock_text(times))
def output(label:String,result:E.State & Entities.Outcome) -> IO(Unit):
  (state,outcome) = result
  observed(label,outcome,E.inspect(state))
def pure_case(label:String,effects:List<&2,Store.Effect>,view:E.View,times:List<&2,R.Bits64>) -> IO(Unit):
  output(label,Consumer.deliver(~Unit,~placement,Unit{},context(),effects,E.install(view),times))
def io_case(label:String,budget:Nat,effects:List<&2,Store.Effect>,view:E.View,times:List<&2,R.Bits64>) -> IO(Unit):
  IO.bind(E.State & Entities.Outcome,Unit,
    Consumer.deliver_io(~Unit,~placement,budget,Unit{},context(),effects,E.install(view),times),output(label))
def cases(+view:E.View) -> IO(Unit):
  do IO<Unit>:
    pure_case("empty-pure",[],view,clocks())
    pure_case("acknowledged-prefix",[Store.OwnerReset{point()},Store.BlockUpdate{point(),0n},Store.BlockChange{point(),0n}],view,clocks())
    pure_case("dirty-retains-owner",blocked(),view,clocks())
    pure_case("empty-prefix-blocked",empty_drop() <> blocked(),view,clocks())
    io_case("empty-drop-io",1n,[empty_drop()],view,clocks())
    io_case("zero-budget-required-clock",0n,stone(1) <> blocked(),view,[])
    io_case("zero-budget-prefix",0n,empty_drop() <> stone(1) <> blocked(),view,[])
    io_case("clock-budget-refusal",1n,stone(64) <> blocked(),view,[])
    io_case("supplied-clock-item-prefix",1n,stone(1) <> blocked(),view,clocks())
    io_case("unavailable-xp-placement",1n,
      Store.Experience{point(),F.XpRequest{"minecraft:cooked_beef",1,1.0}} <> blocked(),view,clocks())
def decoded(status:Result<&2,&2,String,E.View>) -> IO(Unit):
  match status:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{view}: cases(view)
def loaded(result:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(Unit):
  (file,status) = result
  do IO<Unit>:
    File.close(file)
    bytes : List<&2,U32> <- IO.try(List<&2,U32>,IO.pure(Result<&1,&1,U32 & String,List<&2,U32>>,status))
    decoded(Codec.decode(limits(),bytes))
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case exe <> path <> Nil{}:
      do IO<Unit>:
        file : File <- IO.try(File,File.open(path,"r"))
        value : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,16777217)
        loaded(value)
    case _: IO.die(Unit,2,"Expected independently constructed complete entity-owner NBT")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
