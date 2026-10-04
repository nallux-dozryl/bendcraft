import Base
import ./json.bend as J
import ./inventory.bend as Inv
import ./crafting_recipe.bend as R
import ./crafting_recipe_decoder.bend as D
import ./crafting_recipe_components.bend as C
import ./cooking_recipe_decoder.bend as KD
import ./furnace_authority_fuel.bend as F

def id(+value:J.Value) -> Result<&2,&2,String,String>:
  do Result<&2,&2,String,String>:
    raw : String <- D.text(value)
    +name : String = D.qualified(raw)
    D.guard(D.identifier(name),"invalid fuel resource identifier")
    return name
def field(+value:J.Value,+name:String) -> Result<&2,&2,String,J.Value>:
  D.require(J.member(value,name),name)
def strings(+values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,String>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,String>>:
        name : String <- id(head)
        tail : List<&2,String> <- strings(rest)
        return name <> tail
def block_string(+value:String) -> Result<&2,&2,String,F.Predicate>:
  match value:
    case SCon{Chr{35},rest}:
      do Result<&2,&2,String,F.Predicate>:
        name : String <- id(J.JString{rest})
        return F.BlockTag{name}
    case _: Fail{"block holder set requires array or tag string"}
def blocks(+value:Maybe<&2,J.Value>) -> Result<&2,&2,String,F.Predicate>:
  match value:
    case None{}: Done{F.AnyBlock{}}
    case Some{J.JString{raw}}: block_string(raw)
    case Some{J.JArray{values}}:
      do Result<&2,&2,String,F.Predicate>:
        names : List<&2,String> <- strings(values)
        return F.Blocks{names}
    case _: Fail{"invalid block holder set"}
def predicate_object(+value:J.Value,+supported:Bool) -> Result<&2,&2,String,F.Predicate>:
  match supported:
    case True{}: blocks(J.member(value,"blocks"))
    case False{}: Done{F.OtherPredicate{value}}
def predicate(+depth:Nat,+value:J.Value) -> Result<&2,&2,String,F.Predicate>:
  match depth value:
    case 0n _: Fail{"fuel decoder depth exhausted"}
    case 1n+rest J.JString{raw}:
      do Result<&2,&2,String,F.Predicate>:
        name : String <- id(value)
        return F.PredicateRef{name}
    case 1n+rest J.JObject{members}:
      do Result<&2,&2,String,F.Predicate>:
        raw : J.Value <- field(value,"type")
        name : String <- id(raw)
        predicate_object(value,String.eq(name,"minecraft:match_block") && Bool.not(Maybe.is_some(&2,J.Value,J.member(value,"state"))) && Bool.not(Maybe.is_some(&2,J.Value,J.member(value,"nbt"))))
    case _ _: Fail{"invalid fuel predicate"}
def optional_source(+value:Maybe<&2,J.Value>) -> J.Value:
  match value:
    case None{}: J.JNumber{"0"}
    case Some{source}: source
def int_object(parse_a:J.Value -> Result<&2,&2,String,F.IntExpr>,parse_b:J.Value -> Result<&2,&2,String,F.IntExpr>,+depth:Nat,+value:J.Value,+name:String) -> Result<&2,&2,String,F.IntExpr>:
  match name:
    case "minecraft:div":
      do Result<&2,&2,String,F.IntExpr>:
        a : J.Value <- field(value,"left")
        b : J.Value <- field(value,"right")
        left : F.IntExpr <- parse_a(a)
        right : F.IntExpr <- parse_b(b)
        return F.IntDiv{left,right}
    case "minecraft:conditional":
      do Result<&2,&2,String,F.IntExpr>:
        test : J.Value <- field(value,"condition")
        condition : F.Predicate <- predicate(depth,test)
        raw_yes : J.Value <- field(value,"on_true")
        yes : F.IntExpr <- parse_a(raw_yes)
        no : F.IntExpr <- parse_b(optional_source(J.member(value,"on_false")))
        return F.IntConditional{condition,yes,no}
    case _: Done{F.OtherInt{value}}
def int_expr(+depth:Nat,+value:J.Value) -> Result<&2,&2,String,F.IntExpr>:
  match depth value:
    case 0n _: Fail{"fuel decoder depth exhausted"}
    case 1n+rest J.JNumber{raw}:
      do Result<&2,&2,String,F.IntExpr>:
        bits : U32 <- KD.signed_raw(raw)
        return F.IntConstant{bits}
    case 1n+rest J.JString{raw}:
      do Result<&2,&2,String,F.IntExpr>:
        name : String <- id(value)
        return F.IntRef{name}
    case 1n+rest J.JObject{members}:
      do Result<&2,&2,String,F.IntExpr>:
        raw : J.Value <- field(value,"type")
        name : String <- id(raw)
        int_object(v => int_expr(rest,v),v => int_expr(rest,v),rest,value,name)
    case _ _: Fail{"invalid integer fuel expression"}
def float_object(parse_a:J.Value -> Result<&2,&2,String,F.FloatExpr>,parse_b:J.Value -> Result<&2,&2,String,F.FloatExpr>,+depth:Nat,+value:J.Value,+name:String) -> Result<&2,&2,String,F.FloatExpr>:
  match name:
    case "minecraft:conditional":
      do Result<&2,&2,String,F.FloatExpr>:
        test : J.Value <- field(value,"condition")
        condition : F.Predicate <- predicate(depth,test)
        raw_yes : J.Value <- field(value,"on_true")
        yes : F.FloatExpr <- parse_a(raw_yes)
        no : F.FloatExpr <- parse_b(optional_source(J.member(value,"on_false")))
        return F.FloatConditional{condition,yes,no}
    case _: Done{F.OtherFloat{value}}
def float_expr(+depth:Nat,+value:J.Value) -> Result<&2,&2,String,F.FloatExpr>:
  match depth value:
    case 0n _: Fail{"fuel decoder depth exhausted"}
    case 1n+rest J.JNumber{raw}:
      do Result<&2,&2,String,F.FloatExpr>:
        number : F32 <- KD.experience(Some{value})
        return F.FloatConstant{number}
    case 1n+rest J.JString{raw}:
      do Result<&2,&2,String,F.FloatExpr>:
        name : String <- id(value)
        return F.FloatRef{name}
    case 1n+rest J.JObject{members}:
      do Result<&2,&2,String,F.FloatExpr>:
        raw : J.Value <- field(value,"type")
        name : String <- id(raw)
        float_object(v => float_expr(rest,v),v => float_expr(rest,v),rest,value,name)
    case _ _: Fail{"invalid float fuel expression"}
def component_pair(+time:F.IntExpr,+speed:F.FloatExpr) -> Result<&2,&2,String,Maybe<&2,F.CookingFuel>>:
  match time speed:
    case F.IntConstant{x} F.FloatConstant{y}: Done{Some{F.CookingFuel{time,speed}}}
    case F.IntConstant{x} F.FloatRef{y}: Done{Some{F.CookingFuel{time,speed}}}
    case F.IntRef{x} F.FloatConstant{y}: Done{Some{F.CookingFuel{time,speed}}}
    case F.IntRef{x} F.FloatRef{y}: Done{Some{F.CookingFuel{time,speed}}}
    case _ _: Fail{"cooking fuel requires constant or registry reference fields"}
def component(+value:Maybe<&2,J.Value>) -> Result<&2,&2,String,Maybe<&2,F.CookingFuel>>:
  match value:
    case None{}: Done{None{}}
    case Some{+raw}:
      do Result<&2,&2,String,Maybe<&2,F.CookingFuel>>:
        a : J.Value <- field(raw,"burn_time")
        b : J.Value <- field(raw,"speed_multiplier")
        time : F.IntExpr <- int_expr(2n,a)
        speed : F.FloatExpr <- float_expr(2n,b)
        component_pair(time,speed)
def int_rows(+values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,F.IntDefinition>>:
  match values:
    case Nil{}: Done{[]}
    case +row <> rest:
      do Result<&2,&2,String,List<&2,F.IntDefinition>>:
        raw : J.Value <- field(row,"id")
        name : String <- id(raw)
        source : J.Value <- field(row,"source")
        value : F.IntExpr <- int_expr(256n,source)
        tail : List<&2,F.IntDefinition> <- int_rows(rest)
        return F.IntDefinition{name,value} <> tail
def float_rows(+values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,F.FloatDefinition>>:
  match values:
    case Nil{}: Done{[]}
    case +row <> rest:
      do Result<&2,&2,String,List<&2,F.FloatDefinition>>:
        raw : J.Value <- field(row,"id")
        name : String <- id(raw)
        source : J.Value <- field(row,"source")
        value : F.FloatExpr <- float_expr(256n,source)
        tail : List<&2,F.FloatDefinition> <- float_rows(rest)
        return F.FloatDefinition{name,value} <> tail
def predicate_rows(+values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,F.PredicateDefinition>>:
  match values:
    case Nil{}: Done{[]}
    case +row <> rest:
      do Result<&2,&2,String,List<&2,F.PredicateDefinition>>:
        raw : J.Value <- field(row,"id")
        name : String <- id(raw)
        source : J.Value <- field(row,"source")
        value : F.Predicate <- predicate(256n,source)
        tail : List<&2,F.PredicateDefinition> <- predicate_rows(rest)
        return F.PredicateDefinition{name,value} <> tail
def tag_rows(+values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,F.BlockTagDefinition>>:
  match values:
    case Nil{}: Done{[]}
    case +row <> rest:
      do Result<&2,&2,String,List<&2,F.BlockTagDefinition>>:
        raw : J.Value <- field(row,"id")
        name : String <- id(raw)
        array : J.Value <- field(row,"items")
        elements : List<&2,J.Value> <- D.array(array)
        members : List<&2,String> <- strings(elements)
        tail : List<&2,F.BlockTagDefinition> <- tag_rows(rest)
        return F.BlockTagDefinition{name,members} <> tail
def item_rows(+values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,F.ItemFuel>>:
  match values:
    case Nil{}: Done{[]}
    case +row <> rest:
      do Result<&2,&2,String,List<&2,F.ItemFuel>>:
        raw : J.Value <- field(row,"id")
        name : String <- id(raw)
        fuel : Maybe<&2,F.CookingFuel> <- component(J.member(row,"fuel"))
        tail : List<&2,F.ItemFuel> <- item_rows(rest)
        return F.ItemFuel{name,fuel} <> tail
def array_field(+value:J.Value,+name:String) -> Result<&2,&2,String,List<&2,J.Value>>:
  do Result<&2,&2,String,List<&2,J.Value>>:
    raw : J.Value <- field(value,name)
    D.array(raw)
def unique_rows(values:List<&2,J.Value>,+seen:List<&2,String>) -> Result<&2,&2,String,Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case +row <> rest:
      do Result<&2,&2,String,Unit>:
        raw : J.Value <- field(row,"id")
        +name : String <- id(raw)
        D.guard(Bool.not(F.contains(seen,name)),"duplicate fuel resource/default identifier")
        unique_rows(rest,name <> seen)
def fuel_default_rows(values:List<&2,C.Default>) -> Result<&2,&2,String,List<&2,F.ItemFuel>>:
  match values:
    case Nil{}: Done{[]}
    case C.Default{id,map} <> rest:
      do Result<&2,&2,String,List<&2,F.ItemFuel>>:
        fuel : Maybe<&2,F.CookingFuel> <- component(J.member(map,"minecraft:cooking_fuel"))
        tail : List<&2,F.ItemFuel> <- fuel_default_rows(rest)
        return F.ItemFuel{id,fuel} <> tail
def catalog(+value:J.Value) -> Result<&2,&2,String,F.Catalog>:
  do Result<&2,&2,String,F.Catalog>:
    +a : List<&2,J.Value> <- array_field(value,"ints")
    +b : List<&2,J.Value> <- array_field(value,"floats")
    +c : List<&2,J.Value> <- array_field(value,"predicates")
    +d : List<&2,J.Value> <- array_field(value,"tags")
    +f : List<&2,J.Value> <- array_field(value,"defaults")
    unique_rows(a,[])
    unique_rows(b,[])
    unique_rows(c,[])
    unique_rows(d,[])
    unique_rows(f,[])
    ints : List<&2,F.IntDefinition> <- int_rows(a)
    floats : List<&2,F.FloatDefinition> <- float_rows(b)
    predicates : List<&2,F.PredicateDefinition> <- predicate_rows(c)
    tags : List<&2,F.BlockTagDefinition> <- tag_rows(d)
    +defaults : List<&2,C.Default> <- D.defaults_rows(f,[])
    D.guard(KD.defaults_valid(defaults),"fuel defaults require actual initialized component maps")
    items : List<&2,F.ItemFuel> <- fuel_default_rows(defaults)
    return F.Catalog{ints,floats,predicates,tags,items,defaults}

# Component profile admission reuses shared codec/default equality. A caller
# cannot gain fuel authority by submitting the envelope marker or ItemMetadata.
def admit(+defaults:J.Value,+key:Inv.ItemKey,+patch:J.Value) -> Result<&2,&2,String,F.FuelProfile>:
  match defaults key:
    case J.JObject{+members} Inv.ItemKey{id,+payload}:
      do Result<&2,&2,String,F.FuelProfile>:
        actual : String <- C.resolve(defaults,patch)
        D.guard(String.eq(actual,payload),"fuel profile differs from exact canonical component identity")
        D.guard(String.eq(payload,"") || Maybe.is_some(&2,U32,R.component_limit(payload)),"invalid effective fuel component profile")
        edits : List<&2,C.Change> <- C.decode(patch)
        +effective : J.Value = J.JObject{C.apply(edits,members)}
        +limit : U32 = C.unsigned_default(J.member(effective,"minecraft:max_stack_size"),1)
        D.guard(U32.is_ge(limit,1) && U32.is_le(limit,99),"invalid fuel profile stack limit")
        fuel : Maybe<&2,F.CookingFuel> <- component(J.member(effective,"minecraft:cooking_fuel"))
        return F.FuelProfile{key,fuel,Inv.ItemMetadata{key,limit}}
    case _ _: Fail{"fuel profile requires initialized object defaults"}
