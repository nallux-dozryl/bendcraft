import Base
import ../src/json.bend as J
import ../src/crafting_recipe_decoder.bend as D
import ../src/crafting_recipe_components.bend as C
import ../src/campfire_authority_items.bend as A
import ../src/campfire_authority_loader.bend as L
import ../src/inventory.bend as I
import ../src/core.bend as Core
import ../src/random.bend as R
import ../src/f64.bend as F
import ../src/vanilla_entity_fields.bend as V
import ../src/cooking_world_store.bend as Store
import ../src/furnace_authority.bend as FA
import ../src/cooking_effect_entities_model.bend as E
import ../src/cooking_effect_entities.bend as Effects
import ./cooking_effect_entities_values.bend as T

def placement(move:Bool,dimension:String,point:V.Vec3) -> Result<&2,&2,E.Error,V.Vec3>:
  match move:
    case False{}: Done{point}
    case True{}:
      V.Vec3{x,y,z} = point
      Done{V.Vec3{F.add(x,F.from_u32(1)),F.add(y,F.from_u32(2)),F.add(z,F.from_u32(3))}}
def patch(value:Maybe<&2,J.Value>) -> J.Value:
  match value:
    case None{}: J.JObject{[]}
    case Some{value}: value
def item_raw(+raw:J.Value,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,I.Slot>:
  match raw:
    case J.JNull{}: Done{I.InvEmpty{}}
    case _:
      do Result<&2,&2,String,I.Slot>:
        id : String <- D.text_field(raw,"id")
        count : U32 <- D.number_field(raw,"count")
        components : String <- C.patch_text(J.member(raw,"components"))
        D.resolve_output(I.InvStack{I.ItemKey{id,components},count},defaults)
def PL_float(value:U32) -> F32:
  U32{word} = value
  F32{word}
def action_kind(drop:Bool,+raw:J.Value,position:Core.Position,defaults:List<&2,C.Default>) -> Result<&2,&2,String,Store.Effect>:
  match drop:
    case True{}:
      do Result<&2,&2,String,Store.Effect>:
        value : J.Value <- D.field(raw,"item")
        item : I.Slot <- item_raw(value,defaults)
        return Store.Drop{position,0,item}
    case False{}:
      do Result<&2,&2,String,Store.Effect>:
        uses : U32 <- D.number_field(raw,"uses")
        rate : U32 <- D.number_field(raw,"rate")
        return Store.Experience{position,FA.XpRequest{"bendcraft:receiver",uses,PL_float(rate)}}
def action(+raw:J.Value,position:Core.Position,defaults:List<&2,C.Default>) -> Result<&2,&2,String,Store.Effect>:
  do Result<&2,&2,String,Store.Effect>:
    op : String <- D.text_field(raw,"op")
    action_kind(String.eq(op,"drop"),raw,position,defaults)
def actions(values:List<&2,J.Value>,+position:Core.Position,+defaults:List<&2,C.Default>) -> Result<&2,&2,String,List<&2,Store.Effect>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,Store.Effect>>:
        head : Store.Effect <- action(head,position,defaults)
        tail : List<&2,Store.Effect> <- actions(rest,position,defaults)
        return head <> tail
def inspected(result:E.State & E.View) -> Result<&2,&2,String,J.Value>:
  (state,view) = result
  Done{T.view(view)}
def delivered(result:E.State & Effects.Outcome) -> Result<&2,&2,String,J.Value>:
  (state,status) = result
  match status:
    case Effects.Outcome{Nil{},Done{unit},Nil{}}: inspected(E.inspect(state))
    case _: Fail{"entities receiver did not consume exact effect/timestamp list"}
def move(raw:Maybe<&2,J.Value>) -> Bool:
  match raw:
    case Some{J.JBool{value}}: value
    case _: False{}
def fixture(+raw:J.Value,+context:A.Context) -> Result<&2,&2,String,J.Value>:
  A.Context{recipes,+defaults,features} = context
  do Result<&2,&2,String,J.Value>:
    x : U32 <- D.number_field(raw,"x")
    y : U32 <- D.number_field(raw,"y")
    z : U32 <- D.number_field(raw,"z")
    base : J.Value <- D.field(raw,"level_before")
    level : R.Source <- T.read_source(base)
    unique : R.Bits64 <- T.bits_field(raw,"unique_before")
    cursor : U32 <- D.number_field(raw,"cursor_before")
    record_values : List<&2,J.Value> <- T.array_field(raw,"initial_records")
    +records : List<&2,E.Record> <- T.read_records(record_values)
    time_values : List<&2,J.Value> <- T.array_field(raw,"times")
    times : List<&2,R.Bits64> <- T.read_times(time_values)
    action_values : List<&2,J.Value> <- T.array_field(raw,"actions")
    effects : List<&2,Store.Effect> <- actions(action_values,Core.Position{"minecraft:overworld",x,y,z},defaults)
    delivered(Effects.deliver(~Bool,~placement,move(J.member(raw,"unstuck")),E.Context{context,E.Limits{4096n,64n,1024n},[]},effects,E.install(E.View{level,unique,cursor,List.length(&2,E.Record,records),records}),times))
def fixtures(values:List<&2,J.Value>,+context:A.Context) -> Result<&2,&2,String,List<&2,J.Value>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,J.Value>>:
        head : J.Value <- fixture(head,context)
        tail : List<&2,J.Value> <- fixtures(rest,context)
        return head <> tail
def execute(+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    catalog : J.Value <- D.field(value,"catalog")
    context : A.Context <- L.catalog(catalog)
    cases : List<&2,J.Value> <- T.array_field(value,"cases")
    results : List<&2,J.Value> <- fixtures(cases,context)
    return J.JArray{results}
def respond(result:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{value}: IO.print(J.encode(value))
def parsed(result:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{value}: respond(execute(value))
def read_done(value:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status) = value
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
    case _: IO.die(Unit,2,"expected entity receiver fixture path")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
