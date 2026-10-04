import Base
import ./player_inventory.bend as I
import ./player_inventory_click_swap.bend as Swap
import ./player_inventory_return.bend as Return
import ./inventory.bend as Inv
import ./player_item_definitions.bend as D

# The ledgers query every key appearing anywhere in both complete48-cell
# observations. Admission also validates metadata and capacity before commit.
law production_swap_admission_conserves_every_item_count:
  for +plan:Swap.Plan
  for admitted:{Swap.admitted(plan) == True{} : Bool}
  {Swap.before_counts(plan) == Swap.after_counts(plan) : List<&2,Nat>}

law actual_swap_planner_conserves_complete_item_count_ledger:
  for +slots:List<&2,Inv.Slot>
  for +selected:U32
  for +index:U32
  for +button:U32
  for +catalog:D.Catalog
  for admitted:{Swap.admitted(Swap.plan(slots,selected,index,button,catalog)) == True{} : Bool}
  {Swap.before_counts(Swap.plan(slots,selected,index,button,catalog)) == Swap.after_counts(Swap.plan(slots,selected,index,button,catalog)) : List<&2,Nat>}

law refused_swap_plan_retains_complete_owned_player:
  for state:I.State
  for +plan:Swap.Plan
  for refused:{Swap.admitted(plan) == False{} : Bool}
  {I.swap_planned(state,plan) == (state,Fail{Swap.message(plan)}) : I.State & Result<&2,&2,String,Unit>}

law admitted_unchanged_swap_retains_complete_owned_player:
  for state:I.State
  for +plan:Swap.Plan
  for admitted:{Swap.admitted(plan) == True{} : Bool}
  for unchanged:{Swap.changed(plan) == False{} : Bool}
  {I.swap_planned(state,plan) == (state,Done{Unit{}}) : I.State & Result<&2,&2,String,Unit>}

law closed_inventory_menu_refuses_swap_and_retains_complete_owned_player:
  for inventory:Inv.Inventory
  for selected:U32
  for abilities:I.Abilities
  for catalog:D.Catalog
  for status:I.Status
  for revision:Nat
  for result:Maybe<&2,Inv.Slot>
  for index:U32
  for button:U32
  {I.menu_click(I.State{inventory,selected,abilities,I.Profile{catalog,status,I.Menu{False{},revision,result}}},index,I.Swap{button}) ==
    (I.State{inventory,selected,abilities,I.Profile{catalog,status,I.Menu{False{},revision,result}}},Fail{"player inventory menu is closed"}) : I.State & Result<&2,&2,String,Unit>}

# This actual commit retains all raw ability words, the complete item catalog,
# selection and menu-open owner; only revision and the derived cache change.
law committed_swap_retains_entire_noninventory_owner:
  for inventory:Inv.Inventory
  for selected:U32
  for abilities:I.Abilities
  for catalog:D.Catalog
  for status:I.Status
  for opened:Bool
  for revision:Nat
  for result:Maybe<&2,Inv.Slot>
  {I.swap_written(selected,abilities,I.Profile{catalog,status,I.Menu{opened,revision,result}},inventory) ==
    (I.State{inventory,selected,abilities,I.Profile{catalog,status,I.Menu{opened,1n+revision,None{}}}},Done{Unit{}}) : I.State & Result<&2,&2,String,Unit>}

# A false change decision retains even the derived recipe cache and revision.
law unchanged_swap_retains_complete_array_profile_and_derived_cache:
  for state:I.State
  for slots:List<&2,Inv.Slot>
  {I.swap_changed(False{},state,slots) == (state,Done{Unit{}}) : I.State & Result<&2,&2,String,Unit>}
