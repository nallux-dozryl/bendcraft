import Base
import ./player_inventory.bend as I
import ./player_inventory_return.bend as Return
import ./inventory.bend as Inv
import ./player_item_definitions.bend as D

# These observations cover the entire actual64-cell Array, including16 backing
# cells outside the48 logical slots; no small arithmetic projection substitutes
# for the production write path.
def retained_contents(slots:List<&1,Inv.Slot>) -> List<&2,Inv.Slot>:
  match slots:
    case Nil{}: []
    case slot <> rest: slot <> retained_contents(rest)

def inventory_contents(inventory:Inv.Inventory) -> List<&2,Inv.Slot>:
  Inv.Inventory{slots,length} = inventory
  retained_contents(Array.to_list(~Inv.Slot,slots))

def truth_type(value:Bool) -> Data:
  match value:
    case False{}: Empty
    case True{}: Unit

law false_is_not_true:
  for contradiction:{False{} == True{} : Bool}
  Empty

law conjunction_left_is_true:
  for +a:Bool
  for b:Bool
  for admitted:{Bool.and(a,b) == True{} : Bool}
  {a == True{} : Bool}

law conjunction_right_is_true:
  for a:Bool
  for +b:Bool
  for admitted:{Bool.and(a,b) == True{} : Bool}
  {b == True{} : Bool}

law admitted_nat_is_equal:
  for +a:Nat
  for +b:Nat
  for admitted:{Nat.is_eq(a,b) == True{} : Bool}
  {a == b : Nat}

law admitted_complete_ledgers_are_equal:
  for +before:List<&2,Nat>
  for +after:List<&2,Nat>
  for +admitted:{Return.counts_equal(before,after) == True{} : Bool}
  {before == after : List<&2,Nat>}

law production_plan_admission_conserves_every_item_count:
  for +plan:Return.Plan
  for admitted:{Return.admitted(plan) == True{} : Bool}
  {Return.before_counts(plan) == Return.after_counts(plan) : List<&2,Nat>}

law actual_production_return_preserves_complete_item_count_ledger:
  for +slots:List<&2,Inv.Slot>
  for +selected:U32
  for +catalog:D.Catalog
  for admitted:{Return.admitted(Return.plan(slots,selected,catalog)) == True{} : Bool}
  {Return.before_counts(Return.plan(slots,selected,catalog)) == Return.after_counts(Return.plan(slots,selected,catalog)) : List<&2,Nat>}

law refused_actual_plan_retains_complete_owned_inventory:
  for state:I.State
  for +plan:Return.Plan
  for refused:{Return.admitted(plan) == False{} : Bool}
  {I.close_planned(state,plan) == (state,Fail{"menu retains carried or crafting items; return/drop authority is required before closing"}) : I.State & Result<&2,&2,String,Unit>}

law refused_return_retains_complete_owned_inventory:
  for state:I.State
  for slots:List<&2,Inv.Slot>
  {I.close_return_guard(False{},state,slots) == (state,Fail{"menu retains carried or crafting items; return/drop authority is required before closing"}) : I.State & Result<&2,&2,String,Unit>}

law committed_return_retains_entire_noninventory_owner:
  for inventory:Inv.Inventory
  for selected:U32
  for abilities:I.Abilities
  for definitions:D.Catalog
  for status:I.Status
  for opened:Bool
  for revision:Nat
  for result:Maybe<&2,Inv.Slot>
  {I.close_written(selected,abilities,I.Profile{definitions,status,I.Menu{opened,revision,result}},inventory) ==
   (I.State{inventory,selected,abilities,I.Profile{definitions,status,I.Menu{False{},1n+revision,None{}}}},Done{Unit{}}) : I.State & Result<&2,&2,String,Unit>}

law closing_empty_menu_clears_only_derived_result_and_retains_owned_inventory:
  for inventory:Inv.Inventory
  for selected:U32
  for abilities:I.Abilities
  for definitions:D.Catalog
  for status:I.Status
  for opened:Bool
  for revision:Nat
  for +cached:Inv.Slot
  {I.close_empty_output(Some{cached},I.State{inventory,selected,abilities,I.Profile{definitions,status,I.Menu{opened,revision,Some{cached}}}}) ==
   (I.State{inventory,selected,abilities,I.Profile{definitions,status,I.Menu{False{},1n+revision,None{}}}},Done{Unit{}}) : I.State & Result<&2,&2,String,Unit>}

law complete_production_array_commit_and_backing_retention:
  for new0:Inv.Slot
  for new1:Inv.Slot
  for new2:Inv.Slot
  for new3:Inv.Slot
  for new4:Inv.Slot
  for new5:Inv.Slot
  for new6:Inv.Slot
  for new7:Inv.Slot
  for new8:Inv.Slot
  for new9:Inv.Slot
  for new10:Inv.Slot
  for new11:Inv.Slot
  for new12:Inv.Slot
  for new13:Inv.Slot
  for new14:Inv.Slot
  for new15:Inv.Slot
  for new16:Inv.Slot
  for new17:Inv.Slot
  for new18:Inv.Slot
  for new19:Inv.Slot
  for new20:Inv.Slot
  for new21:Inv.Slot
  for new22:Inv.Slot
  for new23:Inv.Slot
  for new24:Inv.Slot
  for new25:Inv.Slot
  for new26:Inv.Slot
  for new27:Inv.Slot
  for new28:Inv.Slot
  for new29:Inv.Slot
  for new30:Inv.Slot
  for new31:Inv.Slot
  for new32:Inv.Slot
  for new33:Inv.Slot
  for new34:Inv.Slot
  for new35:Inv.Slot
  for new36:Inv.Slot
  for new37:Inv.Slot
  for new38:Inv.Slot
  for new39:Inv.Slot
  for new40:Inv.Slot
  for new41:Inv.Slot
  for new42:Inv.Slot
  for new43:Inv.Slot
  for new44:Inv.Slot
  for new45:Inv.Slot
  for new46:Inv.Slot
  for new47:Inv.Slot
  for old0:Inv.Slot
  for old1:Inv.Slot
  for old2:Inv.Slot
  for old3:Inv.Slot
  for old4:Inv.Slot
  for old5:Inv.Slot
  for old6:Inv.Slot
  for old7:Inv.Slot
  for old8:Inv.Slot
  for old9:Inv.Slot
  for old10:Inv.Slot
  for old11:Inv.Slot
  for old12:Inv.Slot
  for old13:Inv.Slot
  for old14:Inv.Slot
  for old15:Inv.Slot
  for old16:Inv.Slot
  for old17:Inv.Slot
  for old18:Inv.Slot
  for old19:Inv.Slot
  for old20:Inv.Slot
  for old21:Inv.Slot
  for old22:Inv.Slot
  for old23:Inv.Slot
  for old24:Inv.Slot
  for old25:Inv.Slot
  for old26:Inv.Slot
  for old27:Inv.Slot
  for old28:Inv.Slot
  for old29:Inv.Slot
  for old30:Inv.Slot
  for old31:Inv.Slot
  for old32:Inv.Slot
  for old33:Inv.Slot
  for old34:Inv.Slot
  for old35:Inv.Slot
  for old36:Inv.Slot
  for old37:Inv.Slot
  for old38:Inv.Slot
  for old39:Inv.Slot
  for old40:Inv.Slot
  for old41:Inv.Slot
  for old42:Inv.Slot
  for old43:Inv.Slot
  for old44:Inv.Slot
  for old45:Inv.Slot
  for old46:Inv.Slot
  for old47:Inv.Slot
  for old48:Inv.Slot
  for old49:Inv.Slot
  for old50:Inv.Slot
  for old51:Inv.Slot
  for old52:Inv.Slot
  for old53:Inv.Slot
  for old54:Inv.Slot
  for old55:Inv.Slot
  for old56:Inv.Slot
  for old57:Inv.Slot
  for old58:Inv.Slot
  for old59:Inv.Slot
  for old60:Inv.Slot
  for old61:Inv.Slot
  for old62:Inv.Slot
  for old63:Inv.Slot
  {inventory_contents(I.write_returned([new0,new1,new2,new3,new4,new5,new6,new7,new8,new9,new10,new11,new12,new13,new14,new15,new16,new17,new18,new19,new20,new21,new22,new23,new24,new25,new26,new27,new28,new29,new30,new31,new32,new33,new34,new35,new36,new37,new38,new39,new40,new41,new42,new43,new44,new45,new46,new47],0,Inv.Inventory{ANode{ANode{ANode{ANode{ANode{ANode{ALeaf{old0},ALeaf{old1}},ANode{ALeaf{old2},ALeaf{old3}}},ANode{ANode{ALeaf{old4},ALeaf{old5}},ANode{ALeaf{old6},ALeaf{old7}}}},ANode{ANode{ANode{ALeaf{old8},ALeaf{old9}},ANode{ALeaf{old10},ALeaf{old11}}},ANode{ANode{ALeaf{old12},ALeaf{old13}},ANode{ALeaf{old14},ALeaf{old15}}}}},ANode{ANode{ANode{ANode{ALeaf{old16},ALeaf{old17}},ANode{ALeaf{old18},ALeaf{old19}}},ANode{ANode{ALeaf{old20},ALeaf{old21}},ANode{ALeaf{old22},ALeaf{old23}}}},ANode{ANode{ANode{ALeaf{old24},ALeaf{old25}},ANode{ALeaf{old26},ALeaf{old27}}},ANode{ANode{ALeaf{old28},ALeaf{old29}},ANode{ALeaf{old30},ALeaf{old31}}}}}},ANode{ANode{ANode{ANode{ANode{ALeaf{old32},ALeaf{old33}},ANode{ALeaf{old34},ALeaf{old35}}},ANode{ANode{ALeaf{old36},ALeaf{old37}},ANode{ALeaf{old38},ALeaf{old39}}}},ANode{ANode{ANode{ALeaf{old40},ALeaf{old41}},ANode{ALeaf{old42},ALeaf{old43}}},ANode{ANode{ALeaf{old44},ALeaf{old45}},ANode{ALeaf{old46},ALeaf{old47}}}}},ANode{ANode{ANode{ANode{ALeaf{old48},ALeaf{old49}},ANode{ALeaf{old50},ALeaf{old51}}},ANode{ANode{ALeaf{old52},ALeaf{old53}},ANode{ALeaf{old54},ALeaf{old55}}}},ANode{ANode{ANode{ALeaf{old56},ALeaf{old57}},ANode{ALeaf{old58},ALeaf{old59}}},ANode{ANode{ALeaf{old60},ALeaf{old61}},ANode{ALeaf{old62},ALeaf{old63}}}}}}},48})) ==
   [new0,new1,new2,new3,new4,new5,new6,new7,new8,new9,new10,new11,new12,new13,new14,new15,new16,new17,new18,new19,new20,new21,new22,new23,new24,new25,new26,new27,new28,new29,new30,new31,new32,new33,new34,new35,new36,new37,new38,new39,new40,new41,new42,new43,new44,new45,new46,new47,old48,old49,old50,old51,old52,old53,old54,old55,old56,old57,old58,old59,old60,old61,old62,old63] : List<&2,Inv.Slot>}
