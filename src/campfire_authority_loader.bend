import Base
import ./json.bend as J
import ./crafting_recipe.bend as R
import ./crafting_recipe_decoder.bend as D
import ./crafting_recipe_components.bend as C
import ./cooking_recipe.bend as K
import ./cooking_recipe_decoder.bend as KD
import ./campfire_authority_items.bend as A

def absent(result:Map<&2,Maybe<&2,Bool>> & Maybe<&2,Bool>) -> Bool:
  (features,value) = result
  Maybe.is_none(&2,Bool,value)
def flag(value:J.Value) -> Result<&2,&2,String,Bool>:
  match value:
    case J.JBool{enabled}: Done{enabled}
    case _: Fail{"campfire feature admission must be boolean"}
def features(values:List<&2,J.Value>,+items:List<&2,R.ItemDefinition>,+seen:Map<&2,Maybe<&2,Bool>>) -> Result<&2,&2,String,Map<&2,Maybe<&2,Bool>>>:
  match values:
    case Nil{}: Done{seen}
    case +head <> rest:
      do Result<&2,&2,String,Map<&2,Maybe<&2,Bool>>>:
        raw : J.Value <- D.field(head,"id")
        +id : String <- D.text(raw)
        value : J.Value <- D.field(head,"enabled")
        enabled : Bool <- flag(value)
        A.guarded(Maybe.is_some(&2,R.ItemDefinition,R.item_definition(items,id)),"unknown campfire feature item")
        A.guarded(absent(Map.get(Maybe<&2,Bool>,None{},seen,id)),"duplicate campfire feature item")
        features(rest,items,Map.set(&2,Maybe<&2,Bool>,seen,id,Some{enabled}))
def context(+value:J.Value,+recipes:K.Catalog) -> Result<&2,&2,String,A.Context>:
  K.Catalog{cooking,tags,+items} = recipes
  do Result<&2,&2,String,A.Context>:
    raw_items : J.Value <- D.field(value,"items")
    item_values : List<&2,J.Value> <- D.array(raw_items)
    defaults : List<&2,C.Default> <- D.defaults_rows(item_values,[])
    raw_features : J.Value <- D.field(value,"campfire_features")
    feature_values : List<&2,J.Value> <- D.array(raw_features)
    admission : Map<&2,Maybe<&2,Bool>> <- features(feature_values,items,MTip{})
    return A.Context{recipes,defaults,admission}
def catalog(+value:J.Value) -> Result<&2,&2,String,A.Context>:
  do Result<&2,&2,String,A.Context>:
    recipes : K.Catalog <- KD.catalog(value)
    context(value,recipes)
def parse(text:String,max_codepoints:Nat,max_depth:U32) -> Result<&2,&2,String,A.Context>:
  do Result<&2,&2,String,A.Context>:
    value : J.Value <- J.parse_bounded(text,max_codepoints,max_depth)
    catalog(value)
