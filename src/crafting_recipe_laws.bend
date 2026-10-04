import Base
import ./crafting_recipe.bend as R
import ./inventory.bend as Inv

law empty_pattern_cell_accepts_empty_slot:
  for tags:List<&2,R.Tag>
  {R.ingredient_matches(R.Empty{},tags,Inv.InvEmpty{}) == True{} : Bool}

law empty_pattern_cell_refuses_occupied_slot:
  for tags:List<&2,R.Tag>
  for key:Inv.ItemKey
  for count:U32
  {R.ingredient_matches(R.Empty{},tags,Inv.InvStack{key,count}) == False{} : Bool}

law nonempty_ingredient_refuses_empty_slot:
  for selectors:List<&2,R.Selector>
  for tags:List<&2,R.Tag>
  {R.ingredient_matches(R.AnyOf{selectors},tags,Inv.InvEmpty{}) == False{} : Bool}

law unsupported_recipe_cannot_manufacture_match:
  for id:String
  for kind:String
  for tags:List<&2,R.Tag>
  for grid:R.Grid
  {R.matches(R.Unsupported{id,kind},tags,grid) == False{} : Bool}

law exhausted_injective_assignment_refuses:
  for ingredients:List<&2,R.Ingredient>
  for slots:List<&2,Inv.Slot>
  for tags:List<&2,R.Tag>
  {R.shapeless_assign(ingredients,slots,tags,[]) == False{} : Bool}

law established_first_match_retains_order:
  for recipes:List<&2,R.Recipe>
  for tags:List<&2,R.Tag>
  for items:List<&2,R.ItemDefinition>
  for grid:R.Grid
  for value:R.Plan
  {R.find_recipes(recipes,tags,items,grid,Some{value}) == Some{value} : Maybe<&2,R.Plan>}

law invalid_grid_cannot_publish_plan:
  for catalog:R.Catalog
  for grid:R.Grid
  {R.find_checked(False{},catalog,grid) == Fail{"invalid crafting grid: dimensions, slot count, item definition or components"} : Result<&2,&2,String,Maybe<&2,R.Plan>>}

law plan_consumes_each_occupied_slot_once:
  for slots:List<&2,Inv.Slot>
  for items:List<&2,R.ItemDefinition>
  for index:U32
  {R.unit_consumption(R.consumption(slots,items,index)) == True{} : Bool}

law consumption_has_one_entry_per_occupied_slot:
  for slots:List<&2,Inv.Slot>
  for items:List<&2,R.ItemDefinition>
  for index:U32
  {List.length(&2,R.Consumption,R.consumption(slots,items,index)) == R.occupied_count(slots) : Nat}

law invalid_result_cannot_publish_items:
  for output:Inv.Slot
  {R.create_output_checked(False{},output) == Inv.InvEmpty{} : Inv.Slot}

law shaped_plan_retains_snapshot_and_validated_output:
  for id:String
  for width:U32
  for height:U32
  for cells:List<&2,R.Ingredient>
  for output:Inv.Slot
  for +items:List<&2,R.ItemDefinition>
  for grid_width:U32
  for grid_height:U32
  for +slots:List<&2,Inv.Slot>
  {R.plan(R.Shaped{id,width,height,cells,output},items,R.Grid{grid_width,grid_height,slots}) == Some{R.Plan{id,R.create_output(output,items),R.Grid{grid_width,grid_height,slots},R.consumption(slots,items,0)}} : Maybe<&2,R.Plan>}
