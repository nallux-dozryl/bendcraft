import Base
import ./json.bend as J
import ./inventory.bend as Inv
import ./crafting_recipe.bend as R
import ./crafting_recipe_decoder.bend as D
import ./crafting_recipe_components.bend as C
import ./cooking_recipe.bend as K

def signed_magnitude(parsed:Maybe<&2,U32>,+negative:Bool) -> Result<&2,&2,String,U32>:
  match parsed:
    case None{}: Fail{"cookingtime codec outside signed integer lexeme domain"}
    case Some{+value}:
      do Result<&2,&2,String,U32>:
        D.guard(U32.is_le(value,R.choose(U32,2147483648,2147483647,negative)),"cookingtime codec outside signed integer lexeme domain")
        return R.choose(U32,U32.sub(0,value),value,negative)

def signed_raw(value:String) -> Result<&2,&2,String,U32>:
  match value:
    case SCon{Chr{45},rest}: signed_magnitude(J.u32_lexeme(rest),True{})
    case _: signed_magnitude(J.u32_lexeme(value),False{})

def cooking_time(value:J.Value) -> Result<&2,&2,String,U32>:
  match value:
    case J.JNumber{raw}: signed_raw(raw)
    case _: Fail{"cookingtime must be a number"}

def float_read(value:Maybe<&2,F32>) -> Result<&2,&2,String,F32>:
  match value:
    case None{}: Fail{"experience codec outside supported numeric domain"}
    case Some{actual}: Done{actual}

def number_token(value:Result<&2,&2,String,J.Value>,raw:String) -> Bool:
  match value:
    case Done{J.JNumber{actual}}: String.eq(actual,raw)
    case _: False{}

def experience(value:Maybe<&2,J.Value>) -> Result<&2,&2,String,F32>:
  match value:
    case None{}: Done{0.0}
    case Some{J.JNull{}}: Done{0.0}
    case Some{J.JNumber{+raw}}:
      do Result<&2,&2,String,F32>:
        D.guard(number_token(J.parse_bounded(raw,128n,1),raw),"experience codec outside supported numeric domain")
        float_read(F32.read(raw))
    case Some{other}: Fail{"experience must be a number"}

def kind(value:String) -> Maybe<&2,K.CookingKind>:
  match value:
    case "minecraft:smelting": Some{K.Smelting{}}
    case "minecraft:blasting": Some{K.Blasting{}}
    case "minecraft:smoking": Some{K.Smoking{}}
    case "minecraft:campfire_cooking": Some{K.Campfire{}}
    case _: None{}

def optional_string(value:Maybe<&2,J.Value>) -> Bool:
  match value:
    case None{}: True{}
    case Some{J.JNull{}}: True{}
    case Some{J.JString{raw}}: True{}
    case _: False{}

def optional_bool(value:Maybe<&2,J.Value>) -> Bool:
  match value:
    case None{}: True{}
    case Some{J.JNull{}}: True{}
    case Some{J.JBool{raw}}: True{}
    case _: False{}

def category(value:Maybe<&2,J.Value>) -> Bool:
  match value:
    case None{}: True{}
    case Some{J.JNull{}}: True{}
    case Some{J.JString{+raw}}: String.eq(raw,"food") || String.eq(raw,"blocks") || String.eq(raw,"misc")
    case _: False{}

def ordinary(+id:String,kind:K.CookingKind,+value:J.Value,defaults:List<&2,C.Default>) -> Result<&2,&2,String,K.Recipe>:
  do Result<&2,&2,String,K.Recipe>:
    D.guard(optional_string(J.member(value,"group")) && optional_bool(J.member(value,"show_notification")) && category(J.member(value,"category")),"invalid cooking book/common field")
    raw_ingredient : J.Value <- D.field(value,"ingredient")
    ingredient : R.Ingredient <- D.ingredient(raw_ingredient)
    raw_time : J.Value <- D.field(value,"cookingtime")
    time : U32 <- cooking_time(raw_time)
    xp : F32 <- experience(J.member(value,"experience"))
    raw_output : J.Value <- D.field(value,"result")
    template : Inv.Slot <- D.result(raw_output)
    output : Inv.Slot <- D.resolve_output(template,defaults)
    return K.Cooking{id,kind,ingredient,output,time,xp}

def outside_domain(+message:String) -> Bool:
  String.eq(message,"component codec outside supported domain") || String.eq(message,"recipe output requires initialized component defaults") ||
    String.eq(message,"cookingtime codec outside signed integer lexeme domain") || String.eq(message,"experience codec outside supported numeric domain")

def ordinary_result(value:Result<&2,&2,String,K.Recipe>,id:String,kind:String) -> Result<&2,&2,String,K.Recipe>:
  match value:
    case Done{actual}: Done{actual}
    case Fail{+message}: R.choose(Result<&2,&2,String,K.Recipe>,Done{K.Unsupported{id,kind ++ "/unsupported_codec_domain"}},Fail{message},outside_domain(message))

def decode_kind(selected:Maybe<&2,K.CookingKind>,+id:String,raw_kind:String,value:J.Value,defaults:List<&2,C.Default>) -> Result<&2,&2,String,K.Recipe>:
  match selected:
    case None{}: Done{K.Unsupported{id,raw_kind}}
    case Some{actual}: ordinary_result(ordinary(id,actual,value,defaults),id,raw_kind)

def decode(+id:String,+value:J.Value,defaults:List<&2,C.Default>) -> Result<&2,&2,String,K.Recipe>:
  do Result<&2,&2,String,K.Recipe>:
    D.guard(D.identifier(id),"invalid cooking recipe identifier")
    +raw_kind : String <- D.text_field(value,"type")
    decode_kind(kind(raw_kind),id,raw_kind,value,defaults)

def known(recipe:K.Recipe,tags:List<&2,R.Tag>,+items:List<&2,R.ItemDefinition>) -> Bool:
  match recipe:
    case K.Unsupported{id,kind}: True{}
    case K.Cooking{id,kind,ingredient,output,time,xp}: D.ingredients_known([ingredient],tags,items) && D.output_known(output,items)

def exists(recipes:List<&2,K.Recipe>,+id:String) -> Bool:
  match recipes:
    case Nil{}: False{}
    case recipe <> rest: String.eq(K.recipe_id(recipe),id) || exists(rest,id)

def rows(values:List<&2,J.Value>,+tags:List<&2,R.Tag>,+items:List<&2,R.ItemDefinition>,+defaults:List<&2,C.Default>,+previous:List<&2,K.Recipe>) -> Result<&2,&2,String,List<&2,K.Recipe>>:
  match values:
    case Nil{}: Done{List.reverse(&2,K.Recipe,previous)}
    case +value <> rest:
      do Result<&2,&2,String,List<&2,K.Recipe>>:
        +id : String <- D.text_field(value,"id")
        source : J.Value <- D.field(value,"source")
        +recipe : K.Recipe <- decode(id,source,defaults)
        D.guard(Bool.not(exists(previous,id)),"duplicate cooking catalog recipe")
        D.guard(known(recipe,tags,items),"cooking recipe contains an unknown item/tag or invalid output count")
        rows(rest,tags,items,defaults,recipe <> previous)

def default_object(+value:J.Value) -> Bool:
  match value:
    case J.JObject{members}: Maybe.is_none(&2,J.Value,J.member(value,"error"))
    case _: False{}

def defaults_valid(values:List<&2,C.Default>) -> Bool:
  match values:
    case Nil{}: True{}
    case C.Default{id,components} <> rest: default_object(components) && defaults_valid(rest)

def catalog(+value:J.Value) -> Result<&2,&2,String,K.Catalog>:
  do Result<&2,&2,String,K.Catalog>:
    raw_items : J.Value <- D.field(value,"items")
    +item_values : List<&2,J.Value> <- D.array(raw_items)
    +items : List<&2,R.ItemDefinition> <- D.item_rows(item_values,[])
    +defaults : List<&2,C.Default> <- D.defaults_rows(item_values,[])
    D.guard(defaults_valid(defaults),"cooking defaults require actual initialized maps, not serialization errors")
    D.guard(D.remainders_known(items,items),"cooking catalog contains an unknown or invalid remainder")
    raw_tags : J.Value <- D.field(value,"tags")
    tag_values : List<&2,J.Value> <- D.array(raw_tags)
    +tags : List<&2,R.Tag> <- D.tag_rows(tag_values,items,[])
    raw_recipes : J.Value <- D.field(value,"recipes")
    recipe_values : List<&2,J.Value> <- D.array(raw_recipes)
    recipes : List<&2,K.Recipe> <- rows(recipe_values,tags,items,defaults,[])
    return K.Catalog{recipes,tags,items}

def parse_catalog_with(text:String,max_codepoints:Nat,max_depth:U32) -> Result<&2,&2,String,K.Catalog>:
  do Result<&2,&2,String,K.Catalog>:
    value : J.Value <- J.parse_bounded(text,max_codepoints,max_depth)
    catalog(value)

def parse_catalog(text:String) -> Result<&2,&2,String,K.Catalog>:
  parse_catalog_with(text,U32.to_nat(8388608),64)
