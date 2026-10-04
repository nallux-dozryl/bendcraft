import Base
import ../src/inventory.bend as Inv
import ../src/player_inventory.bend as I
import ../src/crafting_recipe.bend as R
import ../src/crafting_recipe_decoder.bend as D
import ../src/json.bend as J

type Case is Data:
  Case{id:String,recipe:R.Catalog,grid:R.Grid,player:List<&2,Inv.Slot>,selected:U32,abilities:I.Abilities,status:I.Status,revision:Nat,opened:Bool,button:U32,operation:U32}

def boolean(value:J.Value) -> Result<&2,&2,String,Bool>:
  match value:
    case J.JBool{result}: Done{result}
    case _: Fail{"fixture boolean required"}

def flag(value:J.Value,name:String) -> Result<&2,&2,String,Bool>:
  do Result<&2,&2,String,Bool>:
    raw:J.Value <- D.field(value,name)
    boolean(raw)

def slot(+value:J.Value) -> Result<&2,&2,String,Inv.Slot>:
  match value:
    case J.JNull{}: Done{Inv.InvEmpty{}}
    case _:
      do Result<&2,&2,String,Inv.Slot>:
        id:String <- D.text_field(value,"id")
        components:String <- D.text_field(value,"components")
        count:U32 <- D.number_field(value,"count")
        return Inv.InvStack{Inv.ItemKey{id,components},count}

def slots(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,Inv.Slot>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,Inv.Slot>>:
        first:Inv.Slot <- slot(value)
        tail:List<&2,Inv.Slot> <- slots(rest)
        return first <> tail

def slot_field(value:J.Value,name:String) -> Result<&2,&2,String,List<&2,Inv.Slot>>:
  do Result<&2,&2,String,List<&2,Inv.Slot>>:
    raw:J.Value <- D.field(value,name)
    values:List<&2,J.Value> <- D.array(raw)
    slots(values)

def grid(+value:J.Value) -> Result<&2,&2,String,R.Grid>:
  do Result<&2,&2,String,R.Grid>:
    width:U32 <- D.number_field(value,"width")
    height:U32 <- D.number_field(value,"height")
    cells:List<&2,Inv.Slot> <- slot_field(value,"slots")
    return R.Grid{width,height,cells}

def abilities(+value:J.Value) -> Result<&2,&2,String,I.Abilities>:
  do Result<&2,&2,String,I.Abilities>:
    instabuild:Bool <- flag(value,"instabuild")
    maybuild:Bool <- flag(value,"maybuild")
    return I.Abilities{instabuild,maybuild}

def status(+value:J.Value) -> Result<&2,&2,String,I.Status>:
  do Result<&2,&2,String,I.Status>:
    invulnerable:Bool <- flag(value,"invulnerable")
    mayfly:Bool <- flag(value,"mayfly")
    flying:Bool <- flag(value,"flying")
    walking:U32 <- D.number_field(value,"walking_speed")
    speed:U32 <- D.number_field(value,"flying_speed")
    return I.Status{invulnerable,mayfly,flying,walking,speed}

def case_value(+value:J.Value) -> Result<&2,&2,String,Case>:
  do Result<&2,&2,String,Case>:
    id:String <- D.text_field(value,"id")
    raw_catalog:J.Value <- D.field(value,"catalog")
    catalog:R.Catalog <- D.catalog(raw_catalog)
    raw_grid:J.Value <- D.field(value,"grid")
    active:R.Grid <- grid(raw_grid)
    player:List<&2,Inv.Slot> <- slot_field(value,"player")
    selected:U32 <- D.number_field(value,"selected")
    +profile:J.Value <- D.field(value,"profile")
    ability:I.Abilities <- abilities(profile)
    current:I.Status <- status(profile)
    revision:U32 <- D.number_field(value,"revision")
    opened:Bool <- flag(value,"opened")
    button:U32 <- D.number_field(value,"button")
    operation:U32 <- D.number_field(value,"operation")
    return Case{id,catalog,active,player,selected,ability,current,U32.to_nat(revision),opened,button,operation}

def cases(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,Case>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,Case>>:
        first:Case <- case_value(value)
        tail:List<&2,Case> <- cases(rest)
        return first <> tail

def document(value:J.Value) -> Result<&2,&2,String,List<&2,Case>>:
  do Result<&2,&2,String,List<&2,Case>>:
    raw:J.Value <- D.field(value,"cases")
    values:List<&2,J.Value> <- D.array(raw)
    cases(values)

def parse(text:String) -> Result<&2,&2,String,List<&2,Case>>:
  do Result<&2,&2,String,List<&2,Case>>:
    value:J.Value <- J.parse_bounded(text,U32.to_nat(8388608),64)
    document(value)
