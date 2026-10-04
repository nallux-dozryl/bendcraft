import Base
import ./inventory.bend as I
import ./cooking_recipe.bend as K
import ./crafting_recipe.bend as R
import ./crafting_recipe_components.bend as C
import ./json.bend as J

type Input is Data:
  Input{slot:I.Slot,patch:J.Value}
type Context is Data:
  Context{recipes:K.Catalog,defaults:List<&2,C.Default>,features:Map<&2,Maybe<&2,Bool>>}

def plain() -> Input: Input{I.InvEmpty{},J.JObject{[]}}
def guarded(valid:Bool,message:String) -> Result<&2,&2,String,Unit>:
  match valid:
    case False{}: Fail{message}
    case True{}: Done{Unit{}}
def non_air(key:I.ItemKey) -> Bool:
  I.ItemKey{id,components} = key
  Bool.not(String.eq(id,"minecraft:air"))
def admitted_metadata(found:Maybe<&2,I.ItemMetadata>,slot:I.Slot) -> Result<&2,&2,String,Maybe<&2,I.ItemMetadata>>:
  match found slot:
    case Some{+metadata} I.InvStack{+key,count}:
      do Result<&2,&2,String,Maybe<&2,I.ItemMetadata>>:
        guarded(non_air(key) && I.slot_valid(I.InvStack{key,count},metadata),"invalid campfire item count or component combination")
        return Some{metadata}
    case _ _: Fail{"campfire item has no admitted definition"}
def resolved(+catalog:K.Catalog,+key:I.ItemKey,count:U32,result:Result<&2,&2,String,String>) -> Result<&2,&2,String,Maybe<&2,I.ItemMetadata>>:
  I.ItemKey{id,+components} = key
  match result:
    case Fail{message}: Fail{message}
    case Done{expected}:
      do Result<&2,&2,String,Maybe<&2,I.ItemMetadata>>:
        guarded(String.eq(expected,components),"campfire component identity does not match initialized defaults and patch")
        admitted_metadata(K.output_metadata(catalog,key),I.InvStack{key,count})
def defaults_found(catalog:K.Catalog,key:I.ItemKey,count:U32,patch:J.Value,found:Maybe<&2,J.Value>) -> Result<&2,&2,String,Maybe<&2,I.ItemMetadata>>:
  match found:
    case None{}: Fail{"campfire component patch lacks initialized item defaults"}
    case Some{defaults}: resolved(catalog,key,count,C.resolve(defaults,patch))
def edits(+catalog:K.Catalog,defaults:List<&2,C.Default>,+key:I.ItemKey,count:U32,+patch:J.Value,result:Result<&2,&2,String,List<&2,C.Change>>) -> Result<&2,&2,String,Maybe<&2,I.ItemMetadata>>:
  I.ItemKey{+id,+components} = key
  match result:
    case Fail{message}: Fail{message}
    case Done{Nil{}}:
      do Result<&2,&2,String,Maybe<&2,I.ItemMetadata>>:
        guarded(String.is_empty(components),"campfire modified identity lacks its actual component patch")
        admitted_metadata(K.output_metadata(catalog,key),I.InvStack{key,count})
    case Done{changes}: defaults_found(catalog,key,count,patch,C.default_for(defaults,id))
# Metadata is rebuilt here from actual initialized defaults and decoded patch.
# A caller-supplied envelope or ItemMetadata record is never admission authority.
def admit(context:Context,input:Input) -> Result<&2,&2,String,Maybe<&2,I.ItemMetadata>>:
  Context{catalog,defaults,features} = context
  Input{slot,+patch} = input
  match slot:
    case I.InvEmpty{}: Done{None{}}
    case I.InvStack{key,count}: edits(catalog,defaults,key,count,patch,C.decode(patch))
def feature_read(result:Map<&2,Maybe<&2,Bool>> & Maybe<&2,Bool>) -> Result<&2,&2,String,Bool>:
  (features,found) = result
  match found:
    case None{}: Fail{"campfire output item lacks current feature admission"}
    case Some{enabled}: Done{enabled}
def feature_key(features:Map<&2,Maybe<&2,Bool>>,key:I.ItemKey) -> Result<&2,&2,String,Bool>:
  I.ItemKey{id,components} = key
  feature_read(Map.get(Maybe<&2,Bool>,None{},features,id))
def enabled(context:Context,slot:I.Slot) -> Result<&2,&2,String,Bool>:
  Context{catalog,defaults,features} = context
  feature_key(features,K.slot_key(slot))
def unsupported_kind(parts:List<&2,String>) -> Bool:
  match parts:
    case name <> rest: String.eq(name,"minecraft:campfire_cooking")
    case _: False{}
def supported(recipes:List<&2,K.Recipe>) -> Bool:
  match recipes:
    case Nil{}: True{}
    case K.Cooking{id,kind,input,output,time,xp} <> rest: supported(rest)
    case K.Unsupported{id,kind} <> rest: Bool.not(unsupported_kind(String.split(kind,'/'))) && supported(rest)
def cached(recipes:List<&2,K.Recipe>,+id:String,+tags:List<&2,R.Tag>,+items:List<&2,R.ItemDefinition>,+input:I.Slot) -> Maybe<&2,K.Plan>:
  match recipes:
    case Nil{}: None{}
    case +recipe <> rest:
      R.choose(Maybe<&2,K.Plan>,K.plan(recipe,items,input),cached(rest,id,tags,items,input),
        String.eq(K.recipe_id(recipe),id) && K.matches(recipe,K.Campfire{},tags,input))
def selected_fallback(context:Context,+input:Input,result:Result<&2,&2,String,Maybe<&2,I.ItemMetadata>>,found:Maybe<&2,K.Plan>) -> Result<&2,&2,String,Maybe<&2,K.Plan>>:
  Context{catalog,defaults,features} = context
  Input{slot,patch} = input
  match result found:
    case Fail{message} _: Fail{message}
    case Done{metadata} Some{plan}: Done{Some{plan}}
    case Done{None{}} None{}: K.find(catalog,K.Campfire{},slot)
    case Done{Some{metadata}} None{}: K.find_with_metadata(catalog,K.Campfire{},slot,[metadata])
def select_cached(+context:Context,id:String,+input:Input) -> Result<&2,&2,String,Maybe<&2,K.Plan>>:
  Context{K.Catalog{recipes,tags,items},defaults,features} = context
  Input{+slot,patch} = input
  selected_fallback(context,input,admit(context,input),cached(recipes,id,tags,items,slot))
def select(+context:Context,cache:Maybe<&2,String>,+input:Input) -> Result<&2,&2,String,Maybe<&2,K.Plan>>:
  match cache:
    case None{}: selected_fallback(context,input,admit(context,input),None{})
    case Some{id}: select_cached(context,id,input)
