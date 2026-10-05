import Base
import ../src/item_component_effects.bend as E
import ../src/json.bend as J
import ./item_component.bend as Existing

def field(+value:J.Value,+name:String) -> Result<&2,&2,String,J.Value>:
  Existing.required(J.member(value,name),name)
def text_field(value:J.Value) -> Result<&2,&2,String,String>:
  Existing.text_value(value)
def words(value:J.Value) -> Result<&2,&2,String,U32>:
  Existing.number_value(J.as_u32(value))
def typed(value:Result<&2,&2,String,E.Effect>) -> J.Value:
  match value:
    case Fail{message}: Existing.error(message)
    case Done{E.Effect{kind,ticks}}:
      J.JArray{[J.JString{E.kind_name(kind)},Existing.number(ticks)]}
def selected(+id:String,+ticks:U32,result:Result<&2,&2,String,E.EffectType>) -> J.Value:
  match result:
    case Fail{message}: Existing.error(message)
    case Done{+kind}:
      +effect : E.Effect = E.Effect{kind,ticks}
      +tag : J.Value = E.json_effect_tag(effect)
      J.JObject{[J.JMember{"accepted",J.JBool{True{}}},J.JMember{"id",J.JString{E.kind_name(kind)}},
        J.JMember{"json",tag},J.JMember{"json_read",typed(E.json_effect(tag))},
        J.JMember{"nbt_read",typed(E.nbt_effect(E.nbt_tag(effect)))}]}
def effect(+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    raw_id : J.Value <- field(value,"id")
    +id : String <- text_field(raw_id)
    raw_ticks : J.Value <- field(value,"ticks")
    ticks : U32 <- words(raw_ticks)
    return selected(id,ticks,E.kind(id))
def mode(+value:J.Value,name:String) -> Result<&2,&2,String,J.Value>:
  match name:
    case "effect": effect(value)
    case _: Existing.fixture(value)
def fixture(+value:J.Value) -> Result<&2,&2,String,J.Value>:
  do Result<&2,&2,String,J.Value>:
    raw : J.Value <- field(value,"mode")
    name : String <- text_field(raw)
    mode(value,name)
def rows(values:List<&2,J.Value>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        Existing.print(fixture(value))
        rows(rest)
def parsed(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Done{J.JArray{values}}: rows(values)
    case Fail{message}: IO.die(Unit,2,message)
    case _: IO.die(Unit,2,"effect fixtures require array")
def read_done(result:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status) = result
  do IO<Unit>:
    File.close(file)
    input : String <- IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))
    parsed(J.parse_bounded(input,U32.to_nat(1048576),32))
def arguments(values:List<String>) -> IO(Unit):
  match values:
    case program <> path <> Nil{}:
      do IO<Unit>:
        file : File <- IO.try(File,File.open(path,"r"))
        result : File & Result<&1,&1,U32 & String,String> <- File.read(file,1048576)
        read_done(result)
    case _: IO.die(Unit,2,"expected effect dispatch fixture file")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
