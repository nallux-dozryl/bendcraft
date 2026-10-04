import Base
import ./core.bend as C
import ./cooking_recipe.bend as K
import ./campfire_authority.bend as CA

type Family is Data:
  Furnace{kind:K.CookingKind}
  Campfire{kind:CA.CampfireKind}
type Binding is Data:
  Binding{state:U32,block:String,family:Family,lit:Bool,unlit_state:U32,lit_state:U32}
type Catalog is Data:
  Catalog{registry_identity:String,state_count:U32,bindings:Map<&2,Maybe<&2,Binding>>}
type Classification is Data:
  Other{}
  Cooking{binding:Binding}

def equal_position(a:C.Position,b:C.Position) -> Bool:
  C.Position{d,x,y,z} = a
  C.Position{e,u,v,w} = b
  String.eq(d,e) && U32.is_eq(x,u) && U32.is_eq(y,v) && U32.is_eq(z,w)
def key(position:C.Position) -> String:
  C.Position{dimension,x,y,z} = position
  dimension ++ "/" ++ U32.show(x) ++ "/" ++ U32.show(y) ++ "/" ++ U32.show(z)
def same_family(a:Family,b:Family) -> Bool:
  match a b:
    case Furnace{x} Furnace{y}: K.kind_equal(x,y)
    case Campfire{CA.Ordinary{}} Campfire{CA.Ordinary{}}: True{}
    case Campfire{CA.Soul{}} Campfire{CA.Soul{}}: True{}
    case _ _: False{}
def same_block(a:Binding,b:Binding) -> Bool:
  Binding{state,+block,+family,lit,unlit,lit_id} = a
  Binding{other,name,kind,light,dark,bright} = b
  String.eq(block,name) && same_family(family,kind)
def lit_state(binding:Binding,value:Bool) -> U32:
  Binding{state,block,family,lit,dark,bright} = binding
  Bool.pick(U32,value,bright,dark)
def found(value:Maybe<&2,Binding>) -> Classification:
  match value:
    case None{}: Other{}
    case Some{binding}: Cooking{binding}
def map_found(result:Map<&2,Maybe<&2,Binding>> & Maybe<&2,Binding>) -> Classification:
  (entries,value) = result
  found(value)
def bounded(+catalog:Catalog,+state:U32,known:Bool) -> Result<&2,&2,String,Classification>:
  Catalog{identity,count,bindings} = catalog
  match known:
    case False{}: Fail{"cooking-world:unknown-registry-state"}
    case True{}:
      Done{map_found(Map.get(Maybe<&2,Binding>,None{},bindings,U32.show(state)))}
def classify(+catalog:Catalog,+state:U32) -> Result<&2,&2,String,Classification>:
  Catalog{identity,+count,bindings} = catalog
  bounded(catalog,state,U32.is_lt(state,count))
