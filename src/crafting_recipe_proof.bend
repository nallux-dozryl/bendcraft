import Base
import ./crafting_recipe_laws.bend as L
import ./crafting_recipe.bend as R
import ./inventory.bend as Inv

def L.empty_pattern_cell_accepts_empty_slot(tags): {==}
def L.empty_pattern_cell_refuses_occupied_slot(tags,key,count): {==}
def L.nonempty_ingredient_refuses_empty_slot(selectors,tags): {==}
def L.unsupported_recipe_cannot_manufacture_match(id,kind,tags,grid): {==}

def L.exhausted_injective_assignment_refuses(ingredients,slots,tags):
  match ingredients:
    case Nil{}: {==}
    case head <> rest: {==}

def L.established_first_match_retains_order(recipes,tags,items,grid,value):
  match recipes:
    case Nil{}: {==}
    case head <> rest: {==}

def L.invalid_grid_cannot_publish_plan(catalog,grid): {==}

def L.plan_consumes_each_occupied_slot_once(slots,items,index):
  match slots:
    case Nil{}: {==}
    case Inv.InvEmpty{} <> rest:
      L.plan_consumes_each_occupied_slot_once(rest,items,U32.add(index,1))
    case Inv.InvStack{Inv.ItemKey{id,components},count} <> rest:
      L.plan_consumes_each_occupied_slot_once(rest,items,U32.add(index,1))

def L.consumption_has_one_entry_per_occupied_slot(slots,items,index):
  match slots:
    case Nil{}: {==}
    case Inv.InvEmpty{} <> rest:
      L.consumption_has_one_entry_per_occupied_slot(rest,items,U32.add(index,1))
    case Inv.InvStack{Inv.ItemKey{id,components},count} <> rest:
      %L.consumption_has_one_entry_per_occupied_slot(rest,items,U32.add(index,1)) : {1n+List.length(&2,R.Consumption,R.consumption(rest,items,U32.add(index,1))) == 1n+_ : Nat}
      {==}

def L.invalid_result_cannot_publish_items(output): {==}
def L.shaped_plan_retains_snapshot_and_validated_output(id,width,height,cells,output,items,grid_width,grid_height,slots): {==}
