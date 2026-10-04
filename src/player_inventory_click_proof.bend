import Base
import ./player_inventory.bend as I
import ./player_inventory_click_swap.bend as Swap
import ./player_inventory_click_laws.bend as L
import ./player_inventory_return.bend as Return
import ./player_inventory_close_laws.bend as Close
import ./player_inventory_close_proof.bend as CloseProof

# Reuse the independently certified complete-ledger and64-cell Array commit
# foundation used by the same actual production write_returned operation.
def L.production_swap_admission_conserves_every_item_count(plan,admitted):
  match plan:
    case Swap.Plan{slots,before,after,valid,changed,message}:
      Close.admitted_complete_ledgers_are_equal(before,after,
        Close.conjunction_right_is_true(valid,Return.counts_equal(before,after),admitted))

def L.actual_swap_planner_conserves_complete_item_count_ledger(slots,selected,index,button,catalog,admitted):
  L.production_swap_admission_conserves_every_item_count(Swap.plan(slots,selected,index,button,catalog),admitted)

def L.refused_swap_plan_retains_complete_owned_player(state,plan,refused):
  %Equal.sym(Bool,Swap.admitted(plan),False{},refused) : {I.swap_guard(_,state,plan) == (state,Fail{Swap.message(plan)}) : I.State & Result<&2,&2,String,Unit>}
  {==}

def L.admitted_unchanged_swap_retains_complete_owned_player(state,plan,admitted,unchanged):
  %Equal.sym(Bool,Swap.admitted(plan),True{},admitted) : {I.swap_guard(_,state,plan) == (state,Done{Unit{}}) : I.State & Result<&2,&2,String,Unit>}
  %Equal.sym(Bool,Swap.changed(plan),False{},unchanged) : {I.swap_changed(_,state,Swap.slots(plan)) == (state,Done{Unit{}}) : I.State & Result<&2,&2,String,Unit>}
  {==}

def L.closed_inventory_menu_refuses_swap_and_retains_complete_owned_player(inventory,selected,abilities,catalog,status,revision,result,index,button): {==}
def L.committed_swap_retains_entire_noninventory_owner(inventory,selected,abilities,catalog,status,opened,revision,result): {==}
def L.unchanged_swap_retains_complete_array_profile_and_derived_cache(state,slots): {==}
