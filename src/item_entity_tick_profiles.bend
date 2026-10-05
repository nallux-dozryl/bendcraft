import Base
import ./item_entity_tick_model.bend as T
import ./json.bend as J
import ./crafting_recipe_decoder.bend as D
import ./item_entity_tick_fields.bend as U
import ./player_look.bend as PL
import ./unicode.bend as UTF
import ./hash.bend as H

# Actual initialized dry Core/slab receiver metadata. Unknown and waterlogged
# states have no profile; they are refused rather than coerced to an air cell.
type Profile is Data:
  Profile{state:U32,full:Bool,friction:F32,speed:F32,restitution:F32,
    suppresses:Bool,neutral_inside:Bool,neutral_step:Bool}
def pinned_sha256() -> String: "5f637a2e7f77814a7d459780c30aec1f58d58adcf4b127035117ff172d25126e"
def flag(value:J.Value) -> Result<&2,&2,String,Bool>:
  match value:
    case J.JBool{v}: Done{v}
    case _: Fail{"item profile expected boolean"}
def boolean(value:J.Value,name:String) -> Result<&2,&2,String,Bool>:
  do Result<&2,&2,String,Bool>:
    raw : J.Value <- D.field(value,name)
    flag(raw)
def float(value:J.Value,name:String) -> Result<&2,&2,String,F32>:
  do Result<&2,&2,String,F32>:
    bits : U32 <- D.number_field(value,name)
    return PL.float_bits(bits)
def profile(+raw:J.Value) -> Result<&2,&2,String,Profile>:
  do Result<&2,&2,String,Profile>:
    state : U32 <- D.number_field(raw,"state")
    full : Bool <- boolean(raw,"full")
    friction : F32 <- float(raw,"friction")
    speed : F32 <- float(raw,"speed")
    restitution : F32 <- float(raw,"restitution")
    suppress : Bool <- boolean(raw,"suppresses")
    inside : Bool <- boolean(raw,"neutral_inside")
    step : Bool <- boolean(raw,"neutral_step")
    return Profile{state,full,friction,speed,restitution,suppress,inside,step}
def rows(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,Profile>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,Profile>>:
        head : Profile <- profile(head)
        tail : List<&2,Profile> <- rows(rest)
        return head <> tail
def parsed(+raw:J.Value) -> Result<&2,&2,String,List<&2,Profile>>:
  do Result<&2,&2,String,List<&2,Profile>>:
    profiles : J.Value <- D.field(raw,"profiles")
    values : List<&2,J.Value> <- D.array(profiles)
    rows(values)
def verified(text:String,valid:Bool) -> Result<&2,&2,String,List<&2,Profile>>:
  match valid:
    case False{}: Fail{"item initialized block profile bytes differ from pinned receiver output"}
    case True{}:
      do Result<&2,&2,String,List<&2,Profile>>:
        raw : J.Value <- J.parse_bounded(text,262144n,32)
        parsed(raw)
# SHA is checked on the complete UTF-8 physical file, before any row is trusted.
def load(+text:String) -> Result<&2,&2,String,List<&2,Profile>>:
  do Result<&2,&2,String,List<&2,Profile>>:
    bytes : List<&2,U32> <- UTF.encode(262144n,text)
    digest : H.Digest <- H.digest(262144n,bytes)
    verified(text,String.eq(H.Digest.hex(digest),pinned_sha256()))
def find_next(+head:Profile,result:Result<&2,&2,T.Error,Profile>,same:Bool) -> Result<&2,&2,T.Error,Profile>:
  match same:
    case True{}: Done{head}
    case False{}: result
def find(values:List<&2,Profile>,+state:U32) -> Result<&2,&2,T.Error,Profile>:
  match values:
    case Nil{}: Fail{T.Refused{"actual Core state has no verified dry item tick profile"}}
    case Profile{+id,+full,+friction,+speed,+restitution,+suppress,+inside,+step} <> rest:
      find_next(Profile{id,full,friction,speed,restitution,suppress,inside,step},find(rest,state),U32.is_eq(id,state))
def cell(profile:Profile,x:U32,y:U32,z:U32) -> T.Cell:
  Profile{id,full,friction,speed,restitution,suppress,inside,step}=profile
  T.Cell{id,x,y,z,False{},False{},0.0,0.0,U.vec(),False{},full,friction,speed,restitution,suppress,inside,step,False{},False{},False{},[]}
