import Base
import ../src/json.bend as J
import ../src/u32_decimal.bend as Decimal
import ../src/inventory.bend as Inv
import ../src/crafting_recipe.bend as R
import ../src/cooking_recipe.bend as K
import ../src/furnace_authority.bend as A
import ../src/furnace_authority_cache_laws.bend as L
import ../src/furnace_authority_cache_proof.bend as P

type Case is Data:
  Case{id:String,recipes:List<&2,K.Recipe>,cached:Maybe<&2,String>,kind:K.CookingKind,input:Inv.Slot}

def num(value:U32) -> J.Value: J.JNumber{Decimal.show(value)}
def txt(value:String) -> J.Value: J.JString{value}
def obj(values:List<&2,J.Member>) -> J.Value: J.JObject{values}
def slot(value:Inv.Slot) -> J.Value:
  match value:
    case Inv.InvEmpty{}: J.JNull{}
    case Inv.InvStack{Inv.ItemKey{id,components},count}:
      obj([J.JMember{"id",txt(id)},J.JMember{"components",txt(components)},J.JMember{"count",num(count)}])
def plan(value:Maybe<&2,K.Plan>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{K.Plan{id,kind,output,before,time,xp}}:
      obj([J.JMember{"id",txt(id)},J.JMember{"kind",txt(K.kind_name(kind))},J.JMember{"output",slot(output)},
        J.JMember{"before",slot(before)},J.JMember{"time",num(time)},J.JMember{"experience_bits",num(F32.bits(xp))}])
def optional(value:Maybe<&2,String>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{id}: txt(id)
def selection(value:Result<&2,&2,String,A.Selection>) -> J.Value:
  match value:
    case Fail{message}: obj([J.JMember{"error",txt(message)}])
    case Done{A.Selection{value,cached}}:
      obj([J.JMember{"plan",plan(value)},J.JMember{"cached",optional(cached)}])
def stack(id:String,count:U32) -> Inv.Slot: Inv.InvStack{Inv.ItemKey{id,""},count}
def items() -> List<&2,R.ItemDefinition>:
  [R.ItemDefinition{"minecraft:beef",64,Inv.InvEmpty{}},R.ItemDefinition{"minecraft:cooked_beef",64,Inv.InvEmpty{}},
   R.ItemDefinition{"minecraft:coal",64,Inv.InvEmpty{}},R.ItemDefinition{"minecraft:charcoal",64,Inv.InvEmpty{}}]
def tags() -> List<&2,R.Tag>: [R.Tag{"test:raw_food",["minecraft:beef"]}]
def recipe(id:String,kind:K.CookingKind,ingredient:R.Ingredient,output:Inv.Slot,time:U32,xp:F32) -> K.Recipe:
  K.Cooking{id,kind,ingredient,output,time,xp}
def beef() -> R.Ingredient: R.AnyOf{[R.Item{"minecraft:beef"}]}
def first() -> K.Recipe: recipe("test:first",K.Smelting{},beef(),stack("minecraft:cooked_beef",1),200,0.35)
def second() -> K.Recipe: recipe("test:first",K.Smelting{},beef(),stack("minecraft:charcoal",2),73,1.25)
def previous_plan(+recipes:List<&2,K.Recipe>,cached:Maybe<&2,String>,kind:K.CookingKind,input:Inv.Slot) -> Maybe<&2,K.Plan>:
  match cached:
    case None{}: None{}
    case Some{id}: L.previous_cached_recipe(recipes,id,kind,tags(),items(),input)
def observed(values:List<&2,Case>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case Case{id,+recipes,+cached,+kind,+input} <> rest:
      obj([J.JMember{"id",txt(id)},J.JMember{"actual",plan(A.cached_plan(K.Catalog{recipes,tags(),items()},kind,input,cached))},
        J.JMember{"previous",plan(previous_plan(recipes,cached,kind,input))}]) <> observed(rest)
def selected(values:List<&2,Case>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case Case{id,recipes,cached,kind,input} <> rest:
      obj([J.JMember{"id",txt(id)},J.JMember{"actual",selection(A.select(K.Catalog{recipes,tags(),items()},
        A.Frame{kind,10,1600,41,200,1.0,cached,[]},input,[]))}]) <> selected(rest)
def main() -> IO(Unit):
  IO.print(J.encode(obj([
    J.JMember{"cached",J.JArray{observed([
      Case{"absent-cache",[first()],None{},K.Smelting{},stack("minecraft:beef",2)},
      Case{"empty-catalog",[],Some{"test:first"},K.Smelting{},stack("minecraft:beef",2)},
      Case{"missing-id",[first()],Some{"test:missing"},K.Smelting{},stack("minecraft:beef",2)},
      Case{"matching-head",[first()],Some{"test:first"},K.Smelting{},stack("minecraft:beef",2)},
      Case{"skip-different-id",[K.Unsupported{"test:other","unknown"},first()],Some{"test:first"},K.Smelting{},stack("minecraft:beef",2)},
      Case{"cached-id-beats-earlier-input-match",[recipe("test:other",K.Smelting{},beef(),stack("minecraft:charcoal",2),73,1.25),first()],Some{"test:first"},K.Smelting{},stack("minecraft:beef",2)},
      Case{"first-duplicate-wins",[first(),second()],Some{"test:first"},K.Smelting{},stack("minecraft:beef",2)},
      Case{"unsupported-first-duplicate",[K.Unsupported{"test:first","unknown"},first()],Some{"test:first"},K.Smelting{},stack("minecraft:beef",2)},
      Case{"wrong-kind-first-duplicate",[recipe("test:first",K.Blasting{},beef(),stack("minecraft:charcoal",2),73,1.25),first()],Some{"test:first"},K.Smelting{},stack("minecraft:beef",2)},
      Case{"wrong-input-first-duplicate",[recipe("test:first",K.Smelting{},R.AnyOf{[R.Item{"minecraft:coal"}]},stack("minecraft:charcoal",2),73,1.25),first()],Some{"test:first"},K.Smelting{},stack("minecraft:beef",2)},
      Case{"invalid-output-id-keeps-plan",[recipe("test:first",K.Smelting{},beef(),stack("test:unknown",1),73,1.25),first()],Some{"test:first"},K.Smelting{},stack("minecraft:beef",2)},
      Case{"zero-output-keeps-plan",[recipe("test:first",K.Smelting{},beef(),stack("minecraft:charcoal",0),73,1.25)],Some{"test:first"},K.Smelting{},stack("minecraft:beef",2)},
      Case{"oversized-output-keeps-plan",[recipe("test:first",K.Smelting{},beef(),stack("minecraft:charcoal",65),73,1.25)],Some{"test:first"},K.Smelting{},stack("minecraft:beef",2)},
      Case{"empty-input",[first()],Some{"test:first"},K.Smelting{},Inv.InvEmpty{}},
      Case{"zero-input-count",[first()],Some{"test:first"},K.Smelting{},stack("minecraft:beef",0)},
      Case{"tag-input",[recipe("test:first",K.Smelting{},R.AnyOf{[R.TagRef{"test:raw_food"}]},stack("minecraft:charcoal",2),73,1.25)],Some{"test:first"},K.Smelting{},stack("minecraft:beef",2)},
      Case{"missing-tag",[recipe("test:first",K.Smelting{},R.AnyOf{[R.TagRef{"test:missing"}]},stack("minecraft:charcoal",2),73,1.25)],Some{"test:first"},K.Smelting{},stack("minecraft:beef",2)},
      Case{"exact-component-output",[recipe("test:first",K.Smelting{},beef(),Inv.InvStack{Inv.ItemKey{"minecraft:charcoal","BendCraftComponents1\t16\t{\"minecraft:max_stack_size\":16}"},7},73,1.25)],Some{"test:first"},K.Smelting{},stack("minecraft:beef",2)}
    ])}},
    J.JMember{"selection",J.JArray{selected([
      Case{"unsupported-first-falls-back",[K.Unsupported{"test:first","unknown"},first()],Some{"test:first"},K.Smelting{},stack("minecraft:beef",2)},
      Case{"invalid-output-does-not-fall-back",[recipe("test:first",K.Smelting{},beef(),stack("test:unknown",1),73,1.25),first()],Some{"test:first"},K.Smelting{},stack("minecraft:beef",2)},
      Case{"missing-cache-falls-back",[first()],Some{"test:missing"},K.Smelting{},stack("minecraft:beef",2)},
      Case{"miss-retains-cache",[first()],Some{"test:missing"},K.Smelting{},stack("minecraft:coal",2)},
      Case{"invalid-input-count-refuses",[first()],Some{"test:missing"},K.Smelting{},stack("minecraft:beef",65)},
      Case{"empty-input-retains-cache",[first()],Some{"test:missing"},K.Smelting{},Inv.InvEmpty{}}
    ])}}
  ])))
