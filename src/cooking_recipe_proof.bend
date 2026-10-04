import Base
import ./cooking_recipe_laws.bend as L
import ./cooking_recipe.bend as K
import ./inventory.bend as Inv

def L.unsupported_cannot_match(id,name,kind,tags,input): {==}
def L.unsupported_cannot_assemble(id,name,items,input): {==}
def L.empty_input_cannot_match_cooking(id,actual,ingredient,output,time,xp,kind,tags): {==}

def L.established_match_retains_registry_order(recipes,kind,tags,items,input,value):
  match recipes:
    case Nil{}: {==}
    case head <> rest: {==}

def L.invalid_input_cannot_publish_plan(catalog,kind,input): {==}
def L.empty_destination_ignores_container_limit(result,container_limit,result_limit): {==}
def L.different_keys_cannot_merge_output(key,other,count,amount,container_limit,result_limit,different):
  %Equal.sym(Bool,Inv.key_equal(key,other),False{},different) :
    {_ && U32.is_lt(container_limit,2147483648) && U32.is_le(U32.add(count,amount),U32.min(container_limit,result_limit)) == False{} : Bool}
  {==}
def L.nonempty_destination_cannot_accept_empty_result(key,count,container_limit,result_limit): {==}
def L.one_completion_spends_one_input_unit(remaining): {==}
def L.empty_input_cannot_underflow(): {==}
def L.last_input_is_cleared(key): {==}
def L.empty_output_copies_complete_result(result): {==}
def L.failed_completion_cannot_publish_mutation(value,slots): {==}
def L.absent_catalog_cannot_authorize_manufactured_plan(value,tags,items,input): {==}

def L.empty_fuel_is_preserved_at_completion(input):
  match input:
    case Inv.InvEmpty{}: {==}
    case Inv.InvStack{Inv.ItemKey{id,components},count}: {==}

def L.empty_input_cannot_fill_bucket(fuel):
  match fuel:
    case Inv.InvEmpty{}: {==}
    case Inv.InvStack{Inv.ItemKey{id,components},count}: {==}

def L.burn_retains_commit_snapshot(value,slots):
  K.Plan{id,kind,result,before,time,xp} = value
  K.FurnaceSlots{input,fuel,output} = slots
  {==}
