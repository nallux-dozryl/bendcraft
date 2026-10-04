import Base
import ./inventory.bend as Inv
import ./player_inventory.bend as I
import ./player_item_definitions.bend as D
import ./crafting_recipe.bend as R
import ./player_crafting_authority.bend as A
import ./player_crafting_authority_plan.bend as P
import ./player_crafting_authority_components.bend as M
import ./player_inventory_close_laws.bend as Close

# Every queried key occurs in the entire before/after player+active grid,
# consumed inputs or produced output/remainders. Transformations are measured
# by before+produced = after+consumed, rather than unchanged item identities.
def shape_owner(result:Array<Inv.Slot> & Bool) -> Array<Inv.Slot>:
  (slots,valid) = result
  slots

def snapshot_owner(result:Array<Inv.Slot> & List<&2,Inv.Slot>) -> Array<Inv.Slot>:
  (slots,values) = result
  slots

law malformed_snapshot_walk_retains_complete_original_array:
  for slots:Array<Inv.Slot>
  {snapshot_owner(A.array_snapshot(slots)) == slots : Array<Inv.Slot>}

law geometry_shape_check_retains_complete_original_array:
  for depth:Nat
  for slots:Array<Inv.Slot>
  {shape_owner(A.shape(depth,slots)) == slots : Array<Inv.Slot>}

law admitted_craft_preserves_complete_transformation_ledger:
  for +transaction:P.Transaction
  for admitted:{P.admitted(transaction) == True{} : Bool}
  {P.before_counts(transaction) == P.after_counts(transaction) : List<&2,Nat>}

law actual_crafting_plan_preserves_complete_transformation_ledger:
  for +slots:List<&2,Inv.Slot>
  for +grid:R.Grid
  for +recipe:R.Plan
  for +selected:U32
  for +catalog:D.Catalog
  for +button:U32
  for admitted:{P.admitted(P.plan(slots,grid,recipe,selected,catalog,button)) == True{} : Bool}
  {P.before_counts(P.plan(slots,grid,recipe,selected,catalog,button)) == P.after_counts(P.plan(slots,grid,recipe,selected,catalog,button)) : List<&2,Nat>}

law refused_craft_retains_entire_player_bench_catalog_and_cache:
  for state:A.State
  for +transaction:P.Transaction
  for refused:{P.admitted(transaction) == False{} : Bool}
  {A.take_planned(state,transaction) == (state,Fail{P.message(transaction)}) : A.State & Result<&2,&2,String,Inv.Slot>}

law stale_plan_retains_entire_crafting_authority:
  for state:A.State
  for snapshot:I.MenuSnapshot
  for grid:R.Grid
  for plan:R.Plan
  for button:U32
  {A.cached_current(False{},state,snapshot,grid,plan,button) == (state,Fail{"stale crafting plan; refresh required"}) : A.State & Result<&2,&2,String,Inv.Slot>}

law absent_plan_retains_entire_crafting_authority:
  for state:A.State
  for snapshot:I.MenuSnapshot
  for grid:R.Grid
  for button:U32
  {A.cached_take(None{},state,snapshot,grid,button) == (state,Fail{"crafting plan is absent; refresh required"}) : A.State & Result<&2,&2,String,Inv.Slot>}

law closed_menu_or_invalid_button_retains_entire_crafting_authority:
  for state:A.State
  for snapshot:I.MenuSnapshot
  for grid:R.Grid
  for cache:Maybe<&2,R.Plan>
  for button:U32
  {A.take_open(False{},state,snapshot,grid,cache,button) == (state,Fail{"player inventory menu is closed or pickup button invalid"}) : A.State & Result<&2,&2,String,Inv.Slot>}

law changed_recipe_retains_entire_crafting_authority:
  for state:A.State
  for snapshot:I.MenuSnapshot
  for grid:R.Grid
  for plan:R.Plan
  for button:U32
  {A.selected_plan(False{},state,snapshot,grid,plan,button) == (state,Fail{"cached crafting recipe changed; refresh required"}) : A.State & Result<&2,&2,String,Inv.Slot>}

law empty_result_refuses_before_owned_mutation:
  for state:A.State
  for +slots:List<&2,Inv.Slot>
  for +grid:R.Grid
  for steps:List<&2,R.Consumption>
  for selected:U32
  for catalog:D.Catalog
  for button:U32
  {A.take_planned(state,P.output(Inv.InvEmpty{},slots,grid,steps,selected,catalog,button)) == (state,Fail{"crafting result is empty"}) : A.State & Result<&2,&2,String,Inv.Slot>}

law missing_component_admission_refuses_before_owned_mutation:
  for state:A.State
  for +slots:List<&2,Inv.Slot>
  for +grid:R.Grid
  for key:Inv.ItemKey
  for count:U32
  for steps:List<&2,R.Consumption>
  for selected:U32
  for catalog:D.Catalog
  for button:U32
  {A.take_planned(state,P.output_metadata(None{},slots,grid,key,count,steps,selected,catalog,button)) == (state,Fail{"crafting result lacks inventory component admission"}) : A.State & Result<&2,&2,String,Inv.Slot>}

law refused_refresh_retains_entire_authority_and_previous_result:
  for state:A.State
  for +message:String
  {A.refreshed(Fail{message},state) == (state,Fail{message}) : A.State & Result<&2,&2,String,Unit>}

law craft_commit_preserves_all_noninventory_player_fields:
  for inventory:Inv.Inventory
  for selected:U32
  for abilities:I.Abilities
  for definitions:D.Catalog
  for status:I.Status
  for opened:Bool
  for revision:Nat
  for result:Maybe<&2,Inv.Slot>
  for slots:List<&2,Inv.Slot>
  {A.commit_player(I.State{inventory,selected,abilities,I.Profile{definitions,status,I.Menu{opened,revision,result}}},slots) ==
    I.State{I.write_returned(slots,0,inventory),selected,abilities,I.Profile{definitions,status,I.Menu{opened,1n+revision,None{}}}} : I.State}

law actual_typed_crafting_plan_preserves_complete_transformation_ledger:
  for +slots:List<&2,Inv.Slot>
  for +grid:R.Grid
  for +recipe:R.Plan
  for +selected:U32
  for +catalog:D.Catalog
  for +button:U32
  for +mode:M.Mode
  for admitted:{P.admitted(P.plan_with(slots,grid,recipe,selected,catalog,button,mode)) == True{} : Bool}
  {P.before_counts(P.plan_with(slots,grid,recipe,selected,catalog,button,mode)) == P.after_counts(P.plan_with(slots,grid,recipe,selected,catalog,button,mode)) : List<&2,Nat>}

law default_only_refuses_all_nonempty_component_keys:
  for catalog:D.Catalog
  for key:Inv.ItemKey
  {M.plain(False{},M.DefaultOnly{},catalog,key) == None{} : Maybe<&2,Inv.ItemMetadata>}

law absent_initialized_component_definition_refuses:
  for key:Inv.ItemKey
  {M.component_definition(None{},key) == None{} : Maybe<&2,Inv.ItemMetadata>}

law complete_bench_commit_retains_seven_nonlogical_backing_cells:
  for new0:Inv.Slot
  for new1:Inv.Slot
  for new2:Inv.Slot
  for new3:Inv.Slot
  for new4:Inv.Slot
  for new5:Inv.Slot
  for new6:Inv.Slot
  for new7:Inv.Slot
  for new8:Inv.Slot
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
  {Close.inventory_contents(I.write_returned([new0,new1,new2,new3,new4,new5,new6,new7,new8],0,Inv.Inventory{ANode{ANode{ANode{ANode{ALeaf{old0},ALeaf{old1}},ANode{ALeaf{old2},ALeaf{old3}}},ANode{ANode{ALeaf{old4},ALeaf{old5}},ANode{ALeaf{old6},ALeaf{old7}}}},ANode{ANode{ANode{ALeaf{old8},ALeaf{old9}},ANode{ALeaf{old10},ALeaf{old11}}},ANode{ANode{ALeaf{old12},ALeaf{old13}},ANode{ALeaf{old14},ALeaf{old15}}}}},9})) == [new0,new1,new2,new3,new4,new5,new6,new7,new8,old9,old10,old11,old12,old13,old14,old15] : List<&2,Inv.Slot>}


law malformed_owner_take_retains_entire_authority:
  for state:A.State
  for button:U32
  {A.take_checked((state,False{}),button) == (state,Fail{"invalid crafting inventory owner geometry"}) : A.State & Result<&2,&2,String,Inv.Slot>}

law malformed_owner_refresh_retains_entire_authority:
  for state:A.State
  {A.refresh_checked((state,False{})) == (state,Fail{"invalid crafting inventory owner geometry"}) : A.State & Result<&2,&2,String,Unit>}
