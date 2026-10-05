import Base
import ./furnace_authority_cache_laws.bend as L
import ./furnace_authority.bend as A
import ./crafting_recipe.bend as R
import ./cooking_recipe.bend as K

def L.matched_dispatch_preserves_result(recipe,items,input,matched):
  match matched:
    case False{}: {==}
    case True{}: {==}
def L.identified_dispatch_preserves_result(recipe,kind,tags,items,input,identified,fallback):
  match identified:
    case False{}: {==}
    case True{}:
      L.matched_dispatch_preserves_result(recipe,items,input,K.matches(recipe,kind,tags,input))
def L.cached_lookup_preserves_previous_result(recipes,id,kind,tags,items,input):
  match recipes:
    case Nil{}: {==}
    case +recipe <> +rest:
      %L.cached_lookup_preserves_previous_result(rest,id,kind,tags,items,input) :
        {A.cached_recipe_identified(recipe,kind,tags,items,input,String.eq(K.recipe_id(recipe),id),unit => A.cached_recipe(rest,id,kind,tags,items,input)) == R.choose(Maybe<&2,K.Plan>,R.choose(Maybe<&2,K.Plan>,K.plan(recipe,items,input),None{},K.matches(recipe,kind,tags,input)),_,String.eq(K.recipe_id(recipe),id)) : Maybe<&2,K.Plan>}
      L.identified_dispatch_preserves_result(recipe,kind,tags,items,input,String.eq(K.recipe_id(recipe),id),A.cached_recipe(rest,id,kind,tags,items,input))
def L.first_identical_id_does_not_search_later_duplicates(recipe,rest,id,kind,tags,items,input,hit,invalid):
  %Equal.sym(Bool,String.eq(K.recipe_id(recipe),id),True{},hit) :
    {A.cached_recipe_identified(recipe,kind,tags,items,input,_,unit => A.cached_recipe(rest,id,kind,tags,items,input)) == None{} : Maybe<&2,K.Plan>}
  %Equal.sym(Bool,K.matches(recipe,kind,tags,input),False{},invalid) :
    {A.cached_recipe_matched(recipe,items,input,_) == None{} : Maybe<&2,K.Plan>}
  {==}
def L.first_matching_id_preserves_complete_plan(recipe,rest,id,kind,tags,items,input,hit,valid):
  %Equal.sym(Bool,String.eq(K.recipe_id(recipe),id),True{},hit) :
    {A.cached_recipe_identified(recipe,kind,tags,items,input,_,unit => A.cached_recipe(rest,id,kind,tags,items,input)) == K.plan(recipe,items,input) : Maybe<&2,K.Plan>}
  %Equal.sym(Bool,K.matches(recipe,kind,tags,input),True{},valid) :
    {A.cached_recipe_matched(recipe,items,input,_) == K.plan(recipe,items,input) : Maybe<&2,K.Plan>}
  {==}
