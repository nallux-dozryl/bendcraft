import Base
import ./json.bend as J
import ./inventory.bend as Inv
import ./crafting_recipe.bend as R

# Decoder for the installed 26.3 ordinary crafting schema. Resource IO and pack
# precedence remain the caller's job. The exact JSON parser lives in Bend.
type PatternKey is Data:
  PatternKey{symbol:U32,ingredient:R.Ingredient}

type Bounds is Data:
  Bounds{left:U32,top:U32,right:U32,bottom:U32,occupied:Bool}

def guard(valid:Bool,message:String) -> Result<&2,&2,String,Unit>:
  match valid:
    case False{}: Fail{message}
    case True{}: Done{Unit{}}

def require(value:Maybe<&2,J.Value>,field:String) -> Result<&2,&2,String,J.Value>:
  match value:
    case None{}: Fail{"missing crafting recipe " ++ field}
    case Some{value}: Done{value}

def text(value:J.Value) -> Result<&2,&2,String,String>:
  match value:
    case J.JString{value}: Done{value}
    case _: Fail{"crafting recipe field must be a string"}

def number_read(value:Maybe<&2,U32>) -> Result<&2,&2,String,U32>:
  match value:
    case None{}: Fail{"crafting recipe count must be a positive integer"}
    case Some{actual}: Done{actual}

def number(value:J.Value) -> Result<&2,&2,String,U32>:
  match value:
    case J.JNumber{raw}: number_read(J.as_u32(J.JNumber{raw}))
    case _: Fail{"crafting recipe count must be an integer"}

def identifier_tail(value:String,+path:Bool,+nonempty:Bool) -> Bool:
  match value path:
    case SNil{} _: path && nonempty
    case SCon{Chr{58},rest} False{}: nonempty && identifier_tail(rest,True{},False{})
    case SCon{Chr{+code},rest} _:
      (U32.is_eq(code,95) || U32.is_eq(code,45) || U32.is_eq(code,46) || (path && U32.is_eq(code,47)) ||
        (U32.is_ge(code,97) && U32.is_le(code,122)) || (U32.is_ge(code,48) && U32.is_le(code,57))) && identifier_tail(rest,path,True{})

def identifier(+value:String) -> Bool:
  Nat.is_le(String.length(value),256n) && identifier_tail(value,False{},False{})

def qualified(+value:String) -> String:
  R.choose(String,value,"minecraft:" ++ value,String.contains(value,":"))

def selector(value:String) -> Result<&2,&2,String,R.Selector>:
  match value:
    case SCon{Chr{35},rest}:
      do Result<&2,&2,String,R.Selector>:
        +id : String = qualified(rest)
        guard(identifier(id),"invalid crafting ingredient tag identifier")
        return R.TagRef{id}
    case _:
      do Result<&2,&2,String,R.Selector>:
        +id : String = qualified(value)
        guard(identifier(id) && Bool.not(String.eq(id,"minecraft:air")),"invalid crafting ingredient item identifier")
        return R.Item{id}

def direct_alternative(value:R.Selector) -> Result<&2,&2,String,R.Selector>:
  match value:
    case R.Item{id}: Done{R.Item{id}}
    case R.TagRef{id}: Fail{"ingredient alternatives must contain direct item identifiers"}

def alternatives(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,R.Selector>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,R.Selector>>:
        name : String <- text(value)
        selected : R.Selector <- selector(name)
        choice : R.Selector <- direct_alternative(selected)
        tail : List<&2,R.Selector> <- alternatives(rest)
        return choice <> tail

def ingredient(value:J.Value) -> Result<&2,&2,String,R.Ingredient>:
  match value:
    case J.JString{value}:
      do Result<&2,&2,String,R.Ingredient>:
        selected : R.Selector <- selector(value)
        return R.AnyOf{[selected]}
    case J.JArray{+values}:
      do Result<&2,&2,String,R.Ingredient>:
        guard(Nat.is_gt(List.length(&2,J.Value,values),0n),"empty crafting ingredient alternatives")
        choices : List<&2,R.Selector> <- alternatives(values)
        return R.AnyOf{choices}
    case _: Fail{"26.3 ingredient requires an item/tag string or an array of strings"}

def ingredients(values:List<&2,J.Value>) -> Result<&2,&2,String,List<&2,R.Ingredient>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,R.Ingredient>>:
        head : R.Ingredient <- ingredient(value)
        tail : List<&2,R.Ingredient> <- ingredients(rest)
        return head <> tail

def array(value:J.Value) -> Result<&2,&2,String,List<&2,J.Value>>:
  match value:
    case J.JArray{values}: Done{values}
    case _: Fail{"crafting recipe field must be an array"}

def count(value:Maybe<&2,J.Value>) -> Result<&2,&2,String,U32>:
  match value:
    case None{}: Done{1}
    case Some{value}: number(value)

def result(+value:J.Value) -> Result<&2,&2,String,Inv.Slot>:
  do Result<&2,&2,String,Inv.Slot>:
    raw_id : J.Value <- require(J.member(value,"id"),"result.id")
    raw_name : String <- text(raw_id)
    +id : String = qualified(raw_name)
    +amount : U32 <- count(J.member(value,"count"))
    guard(identifier(id) && Bool.not(String.eq(id,"minecraft:air")),"invalid crafting result identifier")
    guard(U32.is_ge(amount,1) && U32.is_le(amount,99),"crafting result count must be1..99")
    guard(Bool.not(Maybe.is_some(&2,J.Value,J.member(value,"components"))),"patched crafting result requires component semantics")
    return Inv.InvStack{Inv.ItemKey{id,""},amount}

def key_symbol(value:String) -> Result<&2,&2,String,U32>:
  match value:
    case SCon{Chr{+code},SNil{}}:
      do Result<&2,&2,String,U32>:
        guard(U32.is_le(code,65535) && Bool.not(U32.is_eq(code,32)),"recipe key must be one non-space Java character")
        return code
    case _: Fail{"recipe key must be one non-space Java character"}

def key_exists(keys:List<&2,PatternKey>,+symbol:U32) -> Bool:
  match keys:
    case Nil{}: False{}
    case PatternKey{actual,ingredient} <> rest: U32.is_eq(actual,symbol) || key_exists(rest,symbol)

def keys(members:List<&2,J.Member>,+previous:List<&2,PatternKey>) -> Result<&2,&2,String,List<&2,PatternKey>>:
  match members:
    case Nil{}: Done{List.reverse(&2,PatternKey,previous)}
    case J.JMember{name,value} <> rest:
      do Result<&2,&2,String,List<&2,PatternKey>>:
        +symbol : U32 <- key_symbol(name)
        parsed : R.Ingredient <- ingredient(value)
        guard(Bool.not(key_exists(previous,symbol)),"duplicate crafting recipe key")
        keys(rest,PatternKey{symbol,parsed} <> previous)

def key_object(value:J.Value) -> Result<&2,&2,String,List<&2,PatternKey>>:
  match value:
    case J.JObject{members}: keys(members,[])
    case _: Fail{"crafting recipe key must be an object"}

def pattern_rows(values:List<&2,J.Value>,+width:Nat,first:Bool) -> Result<&2,&2,String,List<&2,String>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,String>>:
        +row : String <- text(value)
        guard(Nat.is_ge(String.length(row),1n) && Nat.is_le(String.length(row),3n),"crafting pattern row width must be1..3")
        guard(first || Nat.is_eq(String.length(row),width),"crafting pattern rows must have equal width")
        tail : List<&2,String> <- pattern_rows(rest,String.length(row),False{})
        return row <> tail

def include(bounds:Bounds,+x:U32,+y:U32,occupied:Bool) -> Bounds:
  match bounds occupied:
    case _ False{}: bounds
    case Bounds{left,top,right,bottom,False{}} True{}: Bounds{x,y,x,y,True{}}
    case Bounds{+left,+top,+right,+bottom,True{}} True{}:
      Bounds{R.choose(U32,x,left,U32.is_lt(x,left)),R.choose(U32,y,top,U32.is_lt(y,top)),
        R.choose(U32,x,right,U32.is_gt(x,right)),R.choose(U32,y,bottom,U32.is_gt(y,bottom)),True{}}

def row_bounds(row:String,+y:U32,+x:U32,bounds:Bounds) -> Bounds:
  match row:
    case SNil{}: bounds
    case SCon{Chr{code},rest}: row_bounds(rest,y,U32.add(x,1),include(bounds,x,y,Bool.not(U32.is_eq(code,32))))

def pattern_bounds(rows:List<&2,String>,+y:U32,bounds:Bounds) -> Bounds:
  match rows:
    case Nil{}: bounds
    case row <> rest: pattern_bounds(rest,U32.add(y,1),row_bounds(row,y,0,bounds))

def lookup_key(keys:List<&2,PatternKey>,+symbol:U32) -> Result<&2,&2,String,R.Ingredient>:
  match keys symbol:
    case _ 32: Done{R.Empty{}}
    case Nil{} _: Fail{"crafting pattern uses undefined key"}
    case PatternKey{actual,ingredient} <> rest _: R.choose(Result<&2,&2,String,R.Ingredient>,Done{ingredient},lookup_key(rest,symbol),U32.is_eq(actual,symbol))

def cells_row(row:String,+keys:List<&2,PatternKey>,+left:U32,+right:U32,+x:U32) -> Result<&2,&2,String,List<&2,R.Ingredient>>:
  match row:
    case SNil{}: Done{[]}
    case SCon{Chr{code},rest}:
      do Result<&2,&2,String,List<&2,R.Ingredient>>:
        head : R.Ingredient <- lookup_key(keys,code)
        +tail : List<&2,R.Ingredient> <- cells_row(rest,keys,left,right,U32.add(x,1))
        return R.choose(List<&2,R.Ingredient>,head <> tail,tail,U32.is_ge(x,left) && U32.is_le(x,right))

def cells_rows(rows:List<&2,String>,+keys:List<&2,PatternKey>,+bounds:Bounds,+y:U32) -> Result<&2,&2,String,List<&2,R.Ingredient>>:
  match rows:
    case Nil{}: Done{[]}
    case row <> rest:
      Bounds{left,+top,right,+bottom,occupied} = bounds
      do Result<&2,&2,String,List<&2,R.Ingredient>>:
        head : List<&2,R.Ingredient> <- cells_row(row,keys,left,right,0)
        +tail : List<&2,R.Ingredient> <- cells_rows(rest,keys,bounds,U32.add(y,1))
        return R.choose(List<&2,R.Ingredient>,List.append(&2,R.Ingredient,head,tail),tail,U32.is_ge(y,top) && U32.is_le(y,bottom))

def symbol_used(rows:List<&2,String>,+symbol:U32) -> Bool:
  match rows:
    case Nil{}: False{}
    case row <> rest: String.contains(row,Char.show(Chr{symbol})) || symbol_used(rest,symbol)

def keys_used(keys:List<&2,PatternKey>,+rows:List<&2,String>) -> Bool:
  match keys:
    case Nil{}: True{}
    case PatternKey{symbol,ingredient} <> rest: symbol_used(rows,symbol) && keys_used(rest,rows)

def shaped_bounds(bounds:Bounds,id:String,rows:List<&2,String>,keys:List<&2,PatternKey>,output:Inv.Slot) -> Result<&2,&2,String,R.Recipe>:
  match bounds:
    case Bounds{left,top,right,bottom,False{}}: Fail{"crafting pattern cannot be empty"}
    case Bounds{+left,+top,+right,+bottom,True{}}:
      do Result<&2,&2,String,R.Recipe>:
        cells : List<&2,R.Ingredient> <- cells_rows(rows,keys,bounds,0)
        return R.Shaped{id,U32.add(U32.sub(right,left),1),U32.add(U32.sub(bottom,top),1),cells,output}

def shaped(id:String,+value:J.Value,output:Inv.Slot) -> Result<&2,&2,String,R.Recipe>:
  do Result<&2,&2,String,R.Recipe>:
    raw_pattern : J.Value <- require(J.member(value,"pattern"),"pattern")
    +values : List<&2,J.Value> <- array(raw_pattern)
    guard(Nat.is_ge(List.length(&2,J.Value,values),1n) && Nat.is_le(List.length(&2,J.Value,values),3n),"crafting pattern height must be1..3")
    +rows : List<&2,String> <- pattern_rows(values,0n,True{})
    raw_key : J.Value <- require(J.member(value,"key"),"key")
    +mapping : List<&2,PatternKey> <- key_object(raw_key)
    guard(keys_used(mapping,rows),"crafting recipe contains unused keys")
    shaped_bounds(pattern_bounds(rows,0,Bounds{0,0,0,0,False{}}),id,rows,mapping,output)

def shapeless(id:String,value:J.Value,output:Inv.Slot) -> Result<&2,&2,String,R.Recipe>:
  do Result<&2,&2,String,R.Recipe>:
    raw : J.Value <- require(J.member(value,"ingredients"),"ingredients")
    +values : List<&2,J.Value> <- array(raw)
    guard(Nat.is_ge(List.length(&2,J.Value,values),1n) && Nat.is_le(List.length(&2,J.Value,values),9n),"shapeless crafting requires1..9 ingredients")
    parsed : List<&2,R.Ingredient> <- ingredients(values)
    return R.Shapeless{id,parsed,output}

def ordinary_output(kind:String,id:String,value:J.Value,output:Inv.Slot) -> Result<&2,&2,String,R.Recipe>:
  match kind:
    case "minecraft:crafting_shaped": shaped(id,value,output)
    case "minecraft:crafting_shapeless": shapeless(id,value,output)
    case _: Fail{"unsupported ordinary recipe subclass"}

def ordinary_plain(plain:Bool,kind:String,id:String,+value:J.Value,raw_result:J.Value) -> Result<&2,&2,String,R.Recipe>:
  match plain:
    case False{}: Done{R.Unsupported{id,kind ++ "/patched_result"}}
    case True{}:
      do Result<&2,&2,String,R.Recipe>:
        output : Inv.Slot <- result(raw_result)
        ordinary_output(kind,id,value,output)

def ordinary(kind:String,id:String,+value:J.Value) -> Result<&2,&2,String,R.Recipe>:
  do Result<&2,&2,String,R.Recipe>:
    +raw_result : J.Value <- require(J.member(value,"result"),"result")
    ordinary_plain(Bool.not(Maybe.is_some(&2,J.Value,J.member(raw_result,"components"))),kind,id,value,raw_result)

def decode_kind(kind:String,id:String,+value:J.Value) -> Result<&2,&2,String,R.Recipe>:
  match kind:
    case "minecraft:crafting_shaped": ordinary(kind,id,value)
    case "minecraft:crafting_shapeless": ordinary(kind,id,value)
    case _: Done{R.Unsupported{id,kind}}

def decode(+id:String,+value:J.Value) -> Result<&2,&2,String,R.Recipe>:
  do Result<&2,&2,String,R.Recipe>:
    guard(identifier(id),"invalid crafting recipe identifier")
    raw_type : J.Value <- require(J.member(value,"type"),"type")
    kind : String <- text(raw_type)
    decode_kind(kind,id,value)

def parse(id:String,text:String) -> Result<&2,&2,String,R.Recipe>:
  do Result<&2,&2,String,R.Recipe>:
    value : J.Value <- J.parse_bounded(text,65536n,32)
    decode(id,value)

def field(+value:J.Value,+name:String) -> Result<&2,&2,String,J.Value>:
  require(J.member(value,name),name)

def text_field(value:J.Value,name:String) -> Result<&2,&2,String,String>:
  do Result<&2,&2,String,String>:
    raw : J.Value <- field(value,name)
    text(raw)

def number_field(value:J.Value,name:String) -> Result<&2,&2,String,U32>:
  do Result<&2,&2,String,U32>:
    raw : J.Value <- field(value,name)
    number(raw)

def slot(+value:J.Value) -> Result<&2,&2,String,Inv.Slot>:
  match value:
    case J.JNull{}: Done{Inv.InvEmpty{}}
    case _:
      do Result<&2,&2,String,Inv.Slot>:
        +id : String <- text_field(value,"id")
        +amount : U32 <- number_field(value,"count")
        guard(identifier(id) && Bool.not(String.eq(id,"minecraft:air")) && U32.is_ge(amount,1) && U32.is_le(amount,99),"invalid crafting catalog stack")
        return Inv.InvStack{Inv.ItemKey{id,""},amount}

def item_rows(values:List<&2,J.Value>,+previous:List<&2,R.ItemDefinition>) -> Result<&2,&2,String,List<&2,R.ItemDefinition>>:
  match values:
    case Nil{}: Done{List.reverse(&2,R.ItemDefinition,previous)}
    case +value <> rest:
      do Result<&2,&2,String,List<&2,R.ItemDefinition>>:
        +id : String <- text_field(value,"id")
        +limit : U32 <- number_field(value,"limit")
        raw : J.Value <- field(value,"remainder")
        remainder : Inv.Slot <- slot(raw)
        guard(identifier(id) && U32.is_ge(limit,1) && U32.is_le(limit,99),"invalid crafting catalog item definition")
        guard(Bool.not(Maybe.is_some(&2,R.ItemDefinition,R.item_definition(previous,id))),"duplicate crafting catalog item")
        item_rows(rest,R.ItemDefinition{id,limit,remainder} <> previous)

def remainders_known(definitions:List<&2,R.ItemDefinition>,+items:List<&2,R.ItemDefinition>) -> Bool:
  match definitions:
    case Nil{}: True{}
    case R.ItemDefinition{id,limit,remainder} <> rest: R.slot_valid(items,remainder) && remainders_known(rest,items)

def names(values:List<&2,J.Value>,+items:List<&2,R.ItemDefinition>) -> Result<&2,&2,String,List<&2,String>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,String,List<&2,String>>:
        +id : String <- text(value)
        guard(identifier(id) && Maybe.is_some(&2,R.ItemDefinition,R.item_definition(items,id)),"tag contains an unknown item")
        tail : List<&2,String> <- names(rest,items)
        return id <> tail

def tag_rows(values:List<&2,J.Value>,+items:List<&2,R.ItemDefinition>,+previous:List<&2,R.Tag>) -> Result<&2,&2,String,List<&2,R.Tag>>:
  match values:
    case Nil{}: Done{List.reverse(&2,R.Tag,previous)}
    case +value <> rest:
      do Result<&2,&2,String,List<&2,R.Tag>>:
        +id : String <- text_field(value,"id")
        raw : J.Value <- field(value,"items")
        members : List<&2,J.Value> <- array(raw)
        parsed : List<&2,String> <- names(members,items)
        guard(identifier(id),"invalid crafting catalog tag identifier")
        guard(Bool.not(Maybe.is_some(&2,List<&2,String>,R.tag_members(previous,id))),"duplicate crafting catalog tag")
        tag_rows(rest,items,R.Tag{id,parsed} <> previous)

def selector_known(selector:R.Selector,tags:List<&2,R.Tag>,items:List<&2,R.ItemDefinition>) -> Bool:
  match selector:
    case R.Item{id}: Maybe.is_some(&2,R.ItemDefinition,R.item_definition(items,id))
    case R.TagRef{id}: Maybe.is_some(&2,List<&2,String>,R.tag_members(tags,id))

def selectors_known(values:List<&2,R.Selector>,+tags:List<&2,R.Tag>,+items:List<&2,R.ItemDefinition>) -> Bool:
  match values:
    case Nil{}: True{}
    case value <> rest: selector_known(value,tags,items) && selectors_known(rest,tags,items)

def ingredients_known(values:List<&2,R.Ingredient>,+tags:List<&2,R.Tag>,+items:List<&2,R.ItemDefinition>) -> Bool:
  match values:
    case Nil{}: True{}
    case R.Empty{} <> rest: ingredients_known(rest,tags,items)
    case R.AnyOf{selectors} <> rest: selectors_known(selectors,tags,items) && ingredients_known(rest,tags,items)

def output_known(output:Inv.Slot,items:List<&2,R.ItemDefinition>) -> Bool:
  match output:
    case Inv.InvEmpty{}: False{}
    case Inv.InvStack{Inv.ItemKey{id,components},+count}:
      String.is_empty(components) && U32.is_ge(count,1) && U32.is_le(count,99) && Maybe.is_some(&2,R.ItemDefinition,R.item_definition(items,id))

def recipe_known(recipe:R.Recipe,+tags:List<&2,R.Tag>,+items:List<&2,R.ItemDefinition>) -> Bool:
  match recipe:
    case R.Shaped{id,width,height,cells,output}: ingredients_known(cells,tags,items) && output_known(output,items)
    case R.Shapeless{id,ingredients,output}: ingredients_known(ingredients,tags,items) && output_known(output,items)
    case R.Unsupported{id,kind}: True{}

def recipe_id(recipe:R.Recipe) -> String:
  match recipe:
    case R.Shaped{id,width,height,cells,output}: id
    case R.Shapeless{id,ingredients,output}: id
    case R.Unsupported{id,kind}: id

def recipe_exists(recipes:List<&2,R.Recipe>,+id:String) -> Bool:
  match recipes:
    case Nil{}: False{}
    case recipe <> rest: String.eq(recipe_id(recipe),id) || recipe_exists(rest,id)

def recipe_rows(values:List<&2,J.Value>,+tags:List<&2,R.Tag>,+items:List<&2,R.ItemDefinition>,+previous:List<&2,R.Recipe>) -> Result<&2,&2,String,List<&2,R.Recipe>>:
  match values:
    case Nil{}: Done{List.reverse(&2,R.Recipe,previous)}
    case +value <> rest:
      do Result<&2,&2,String,List<&2,R.Recipe>>:
        +id : String <- text_field(value,"id")
        source : J.Value <- field(value,"source")
        +recipe : R.Recipe <- decode(id,source)
        guard(Bool.not(recipe_exists(previous,id)),"duplicate crafting catalog recipe")
        guard(recipe_known(recipe,tags,items),"crafting recipe contains an unknown item/tag or invalid output count")
        recipe_rows(rest,tags,items,recipe <> previous)

# Interchange: {items:[{id,limit,remainder}], tags:[{id,items:[id]}],
# recipes:[{id,source:<26.3 recipe JSON>}]} in the authoritative registry order.
# Nested tags must be resolved by the data-pack tag loader before this boundary.
def catalog(+value:J.Value) -> Result<&2,&2,String,R.Catalog>:
  do Result<&2,&2,String,R.Catalog>:
    raw_items : J.Value <- field(value,"items")
    item_values : List<&2,J.Value> <- array(raw_items)
    +items : List<&2,R.ItemDefinition> <- item_rows(item_values,[])
    guard(remainders_known(items,items),"crafting catalog contains an unknown or invalid remainder")
    raw_tags : J.Value <- field(value,"tags")
    tag_values : List<&2,J.Value> <- array(raw_tags)
    +tags : List<&2,R.Tag> <- tag_rows(tag_values,items,[])
    raw_recipes : J.Value <- field(value,"recipes")
    recipe_values : List<&2,J.Value> <- array(raw_recipes)
    recipes : List<&2,R.Recipe> <- recipe_rows(recipe_values,tags,items,[])
    return R.Catalog{recipes,tags,items}

def parse_catalog_with(text:String,max_codepoints:Nat,max_depth:U32) -> Result<&2,&2,String,R.Catalog>:
  do Result<&2,&2,String,R.Catalog>:
    value : J.Value <- J.parse_bounded(text,max_codepoints,max_depth)
    catalog(value)

def parse_catalog(text:String) -> Result<&2,&2,String,R.Catalog>:
  parse_catalog_with(text,U32.to_nat(8388608),64)
