import Base
import ../src/inventory.bend as Inv
import ../src/player_item_definitions.bend as D
import ../src/crafting_recipe.bend as R
import ../src/player_crafting_authority_components.bend as M
import ../src/item_component.bend as C
import ../src/crafting_recipe_components.bend as Components
import ../src/json.bend as J

# Test-only structural observation. Ordering, constructor choice and every
# stored field are part of the expected context; no matcher or admission path
# decides whether an actual value is retained.
def flag_same(expected:Bool,actual:Bool) -> Bool:
  match expected actual:
    case True{} True{}: True{}
    case False{} False{}: True{}
    case _ _: False{}

def key_same(expected:Inv.ItemKey,actual:Inv.ItemKey) -> Bool:
  Inv.ItemKey{id,components} = expected
  Inv.ItemKey{other,payload} = actual
  String.eq(id,other) && String.eq(components,payload)

def slot_same(expected:Inv.Slot,actual:Inv.Slot) -> Bool:
  match expected actual:
    case Inv.InvEmpty{} Inv.InvEmpty{}: True{}
    case Inv.InvStack{key,count} Inv.InvStack{other,amount}:
      key_same(key,other) && U32.is_eq(count,amount)
    case _ _: False{}

def definition_same(expected:D.Definition,actual:D.Definition) -> Bool:
  D.Definition{number,id,description,limit,component_set,identity,enabled} = expected
  D.Definition{other_number,other_id,other_description,other_limit,other_set,other_identity,other_enabled} = actual
  U32.is_eq(number,other_number) && String.eq(id,other_id) &&
    String.eq(description,other_description) && U32.is_eq(limit,other_limit) &&
    U32.is_eq(component_set,other_set) && String.eq(identity,other_identity) &&
    flag_same(enabled,other_enabled)

def definitions_same(expected:List<&2,D.Definition>,actual:List<&2,D.Definition>) -> Bool:
  match expected actual:
    case Nil{} Nil{}: True{}
    case head <> rest other <> tail: definition_same(head,other) && definitions_same(rest,tail)
    case _ _: False{}

def defaults_same(expected:List<&2,Components.Default>,actual:List<&2,Components.Default>) -> Bool:
  match expected actual:
    case Nil{} Nil{}: True{}
    case Components.Default{id,value} <> rest Components.Default{other,map} <> tail:
      String.eq(id,other) && String.eq(J.encode(value),J.encode(map)) && defaults_same(rest,tail)
    case _ _: False{}

def catalog_defaults_same(expected:D.Catalog,actual:D.Catalog) -> Bool:
  match expected actual:
    case D.Catalog{definitions,count} D.Catalog{other,amount}: True{}
    case D.InitializedCatalog{definitions,count,defaults} D.InitializedCatalog{other,amount,maps}: defaults_same(defaults,maps)
    case _ _: False{}

def definition_catalog_same(+expected:D.Catalog,+actual:D.Catalog) -> Bool:
  U32.is_eq(D.count(expected),D.count(actual)) && definitions_same(D.all(expected),D.all(actual)) && catalog_defaults_same(expected,actual)

def selector_same(expected:R.Selector,actual:R.Selector) -> Bool:
  match expected actual:
    case R.Item{id} R.Item{other}: String.eq(id,other)
    case R.TagRef{id} R.TagRef{other}: String.eq(id,other)
    case _ _: False{}

def selectors_same(expected:List<&2,R.Selector>,actual:List<&2,R.Selector>) -> Bool:
  match expected actual:
    case Nil{} Nil{}: True{}
    case head <> rest other <> tail: selector_same(head,other) && selectors_same(rest,tail)
    case _ _: False{}

def ingredient_same(expected:R.Ingredient,actual:R.Ingredient) -> Bool:
  match expected actual:
    case R.Empty{} R.Empty{}: True{}
    case R.AnyOf{selectors} R.AnyOf{other}: selectors_same(selectors,other)
    case _ _: False{}

def ingredients_same(expected:List<&2,R.Ingredient>,actual:List<&2,R.Ingredient>) -> Bool:
  match expected actual:
    case Nil{} Nil{}: True{}
    case head <> rest other <> tail: ingredient_same(head,other) && ingredients_same(rest,tail)
    case _ _: False{}

def recipe_same(expected:R.Recipe,actual:R.Recipe) -> Bool:
  match expected actual:
    case R.Shaped{id,width,height,cells,output} R.Shaped{other,other_width,other_height,other_cells,other_output}:
      String.eq(id,other) && U32.is_eq(width,other_width) && U32.is_eq(height,other_height) &&
        ingredients_same(cells,other_cells) && slot_same(output,other_output)
    case R.Shapeless{id,ingredients,output} R.Shapeless{other,other_ingredients,other_output}:
      String.eq(id,other) && ingredients_same(ingredients,other_ingredients) && slot_same(output,other_output)
    case R.Unsupported{id,kind} R.Unsupported{other,other_kind}:
      String.eq(id,other) && String.eq(kind,other_kind)
    case _ _: False{}

def recipes_same(expected:List<&2,R.Recipe>,actual:List<&2,R.Recipe>) -> Bool:
  match expected actual:
    case Nil{} Nil{}: True{}
    case head <> rest other <> tail: recipe_same(head,other) && recipes_same(rest,tail)
    case _ _: False{}

def names_same(expected:List<&2,String>,actual:List<&2,String>) -> Bool:
  match expected actual:
    case Nil{} Nil{}: True{}
    case head <> rest other <> tail: String.eq(head,other) && names_same(rest,tail)
    case _ _: False{}

def tag_same(expected:R.Tag,actual:R.Tag) -> Bool:
  R.Tag{id,items} = expected
  R.Tag{other,other_items} = actual
  String.eq(id,other) && names_same(items,other_items)

def tags_same(expected:List<&2,R.Tag>,actual:List<&2,R.Tag>) -> Bool:
  match expected actual:
    case Nil{} Nil{}: True{}
    case head <> rest other <> tail: tag_same(head,other) && tags_same(rest,tail)
    case _ _: False{}

def item_same(expected:R.ItemDefinition,actual:R.ItemDefinition) -> Bool:
  R.ItemDefinition{id,limit,remainder} = expected
  R.ItemDefinition{other,other_limit,other_remainder} = actual
  String.eq(id,other) && U32.is_eq(limit,other_limit) && slot_same(remainder,other_remainder)

def items_same(expected:List<&2,R.ItemDefinition>,actual:List<&2,R.ItemDefinition>) -> Bool:
  match expected actual:
    case Nil{} Nil{}: True{}
    case head <> rest other <> tail: item_same(head,other) && items_same(rest,tail)
    case _ _: False{}

def recipe_catalog_same(expected:R.Catalog,actual:R.Catalog) -> Bool:
  R.Catalog{recipes,tags,items} = expected
  R.Catalog{other_recipes,other_tags,other_items} = actual
  recipes_same(recipes,other_recipes) && tags_same(tags,other_tags) && items_same(items,other_items)

def defaults_same(expected:C.Defaults,actual:C.Defaults) -> Bool:
  match expected actual:
    case C.InitializedSuspiciousStew{} C.InitializedSuspiciousStew{}: True{}

def mode_same(expected:M.Mode,actual:M.Mode) -> Bool:
  match expected actual:
    case M.DefaultOnly{} M.DefaultOnly{}: True{}
    case M.TypedStew{defaults} M.TypedStew{other}: defaults_same(defaults,other)
    case _ _: False{}

def context_same(expected_definitions:D.Catalog,expected_recipes:R.Catalog,expected_mode:M.Mode,
    actual_definitions:D.Catalog,actual_recipes:R.Catalog,actual_mode:M.Mode) -> Bool:
  definition_catalog_same(expected_definitions,actual_definitions) &&
    recipe_catalog_same(expected_recipes,actual_recipes) && mode_same(expected_mode,actual_mode)
