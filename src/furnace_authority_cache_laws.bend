import Base
import ./inventory.bend as Inv
import ./crafting_recipe.bend as R
import ./cooking_recipe.bend as K
import ./furnace_authority.bend as A

# Retained pre-repair semantics. This specification deliberately evaluates both
# alternatives; it states result equivalence, not a runtime cost bound.
def previous_cached_recipe(+recipes:List<&2,K.Recipe>,+id:String,+kind:K.CookingKind,+tags:List<&2,R.Tag>,+items:List<&2,R.ItemDefinition>,+input:Inv.Slot) -> Maybe<&2,K.Plan>:
  match recipes:
    case Nil{}: None{}
    case +recipe <> rest:
      R.choose(Maybe<&2,K.Plan>,R.choose(Maybe<&2,K.Plan>,K.plan(recipe,items,input),None{},K.matches(recipe,kind,tags,input)),previous_cached_recipe(rest,id,kind,tags,items,input),String.eq(K.recipe_id(recipe),id))

law matched_dispatch_preserves_result:
  for +recipe:K.Recipe
  for +items:List<&2,R.ItemDefinition>
  for +input:Inv.Slot
  for +matched:Bool
  {A.cached_recipe_matched(recipe,items,input,matched) == R.choose(Maybe<&2,K.Plan>,K.plan(recipe,items,input),None{},matched) : Maybe<&2,K.Plan>}
law identified_dispatch_preserves_result:
  for +recipe:K.Recipe
  for +kind:K.CookingKind
  for +tags:List<&2,R.Tag>
  for +items:List<&2,R.ItemDefinition>
  for +input:Inv.Slot
  for +identified:Bool
  for +fallback:Maybe<&2,K.Plan>
  {A.cached_recipe_identified(recipe,kind,tags,items,input,identified,unit => fallback) == R.choose(Maybe<&2,K.Plan>,R.choose(Maybe<&2,K.Plan>,K.plan(recipe,items,input),None{},K.matches(recipe,kind,tags,input)),fallback,identified) : Maybe<&2,K.Plan>}
law cached_lookup_preserves_previous_result:
  for +recipes:List<&2,K.Recipe>
  for +id:String
  for +kind:K.CookingKind
  for +tags:List<&2,R.Tag>
  for +items:List<&2,R.ItemDefinition>
  for +input:Inv.Slot
  {A.cached_recipe(recipes,id,kind,tags,items,input) == previous_cached_recipe(recipes,id,kind,tags,items,input) : Maybe<&2,K.Plan>}
law first_identical_id_does_not_search_later_duplicates:
  for +recipe:K.Recipe
  for rest:List<&2,K.Recipe>
  for +id:String
  for +kind:K.CookingKind
  for +tags:List<&2,R.Tag>
  for +items:List<&2,R.ItemDefinition>
  for +input:Inv.Slot
  for hit:{String.eq(K.recipe_id(recipe),id) == True{} : Bool}
  for invalid:{K.matches(recipe,kind,tags,input) == False{} : Bool}
  {A.cached_recipe(recipe <> rest,id,kind,tags,items,input) == None{} : Maybe<&2,K.Plan>}
law first_matching_id_preserves_complete_plan:
  for +recipe:K.Recipe
  for rest:List<&2,K.Recipe>
  for +id:String
  for +kind:K.CookingKind
  for +tags:List<&2,R.Tag>
  for +items:List<&2,R.ItemDefinition>
  for +input:Inv.Slot
  for hit:{String.eq(K.recipe_id(recipe),id) == True{} : Bool}
  for valid:{K.matches(recipe,kind,tags,input) == True{} : Bool}
  {A.cached_recipe(recipe <> rest,id,kind,tags,items,input) == K.plan(recipe,items,input) : Maybe<&2,K.Plan>}
