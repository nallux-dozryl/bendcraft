import Base
import ./cooking_recipe.bend as K
import ./crafting_recipe.bend as R
import ./inventory.bend as Inv

law unsupported_cannot_match:
  for id:String
  for name:String
  for kind:K.CookingKind
  for tags:List<&2,R.Tag>
  for input:Inv.Slot
  {K.matches(K.Unsupported{id,name},kind,tags,input) == False{} : Bool}

law unsupported_cannot_assemble:
  for id:String
  for name:String
  for items:List<&2,R.ItemDefinition>
  for input:Inv.Slot
  {K.plan(K.Unsupported{id,name},items,input) == None{} : Maybe<&2,K.Plan>}

law empty_input_cannot_match_cooking:
  for id:String
  for actual:K.CookingKind
  for ingredient:R.Ingredient
  for output:Inv.Slot
  for time:U32
  for xp:F32
  for kind:K.CookingKind
  for tags:List<&2,R.Tag>
  {K.matches(K.Cooking{id,actual,ingredient,output,time,xp},kind,tags,Inv.InvEmpty{}) == False{} : Bool}

law established_match_retains_registry_order:
  for recipes:List<&2,K.Recipe>
  for kind:K.CookingKind
  for tags:List<&2,R.Tag>
  for items:List<&2,R.ItemDefinition>
  for input:Inv.Slot
  for value:K.Plan
  {K.find_recipes(recipes,kind,tags,items,input,Some{value}) == Some{value} : Maybe<&2,K.Plan>}

law invalid_input_cannot_publish_plan:
  for catalog:K.Catalog
  for kind:K.CookingKind
  for input:Inv.Slot
  {K.find_checked(False{},catalog,kind,input) == Fail{"invalid cooking input: item definition, count or components"} : Result<&2,&2,String,Maybe<&2,K.Plan>>}

law empty_destination_ignores_container_limit:
  for result:Inv.Slot
  for container_limit:U32
  for result_limit:U32
  {K.capacity(Inv.InvEmpty{},result,container_limit,result_limit) == True{} : Bool}

law different_keys_cannot_merge_output:
  for +key:Inv.ItemKey
  for +other:Inv.ItemKey
  for count:U32
  for amount:U32
  for container_limit:U32
  for result_limit:U32
  for different:{Inv.key_equal(key,other) == False{} : Bool}
  {K.capacity(Inv.InvStack{key,count},Inv.InvStack{other,amount},container_limit,result_limit) == False{} : Bool}

law nonempty_destination_cannot_accept_empty_result:
  for key:Inv.ItemKey
  for count:U32
  for container_limit:U32
  for result_limit:U32
  {K.capacity(Inv.InvStack{key,count},Inv.InvEmpty{},container_limit,result_limit) == False{} : Bool}

law one_completion_spends_one_input_unit:
  for +remaining:Nat
  {1n+K.decrement_count(1n+remaining) == 1n+remaining : Nat}

law empty_input_cannot_underflow:
  {K.consume_input(Inv.InvEmpty{}) == Inv.InvEmpty{} : Inv.Slot}

law last_input_is_cleared:
  for key:Inv.ItemKey
  {K.consume_input(Inv.InvStack{key,1}) == Inv.InvEmpty{} : Inv.Slot}

law empty_output_copies_complete_result:
  for result:Inv.Slot
  {K.merge_output(Inv.InvEmpty{},result) == result : Inv.Slot}

law failed_completion_cannot_publish_mutation:
  for value:K.Plan
  for slots:K.FurnaceSlots
  {K.completion_checked(False{},value,slots) == Fail{"cooking completion refused: stale plan, invalid authority, kind or output capacity"} : Result<&2,&2,String,K.Completion>}

law absent_catalog_cannot_authorize_manufactured_plan:
  for value:K.Plan
  for tags:List<&2,R.Tag>
  for items:List<&2,R.ItemDefinition>
  for input:Inv.Slot
  {K.authentic([],value,tags,items,input) == False{} : Bool}

law empty_fuel_is_preserved_at_completion:
  for input:Inv.Slot
  {K.completed_fuel(input,Inv.InvEmpty{}) == Inv.InvEmpty{} : Inv.Slot}

law empty_input_cannot_fill_bucket:
  for fuel:Inv.Slot
  {K.completed_fuel(Inv.InvEmpty{},fuel) == fuel : Inv.Slot}

law burn_retains_commit_snapshot:
  for value:K.Plan
  for +slots:K.FurnaceSlots
  {K.burn_snapshot(K.burn(value,slots)) == slots : K.FurnaceSlots}
