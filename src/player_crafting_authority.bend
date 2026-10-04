import Base
import ./inventory.bend as Inv
import ./player_inventory.bend as I
import ./player_item_definitions.bend as D
import ./crafting_recipe.bend as R
import ./player_crafting_authority_plan.bend as P
import ./player_crafting_authority_components.bend as M

# The outer menu adapter avoids an inventory -> recipe -> inventory import
# cycle. Its optional bench retains a separate16-cell Array with9 logical
# inputs. The player owns its original64-cell Array with48 logical cells.
type GridOwner is Type:
  PlayerGrid{}
  TableGrid{inventory:Inv.Inventory,revision:Nat}

type State is Type:
  State{player:I.State,catalog:R.Catalog,grid:GridOwner,cache:Maybe<&2,R.Plan>,components:M.Mode}

type Snapshot is Data:
  Snapshot{player:I.MenuSnapshot,grid:R.Grid,cache:Maybe<&2,R.Plan>}

# The inventory constructors are public. Reject malformed logical lengths or
# unbalanced/backing-short trees before any slot access or owned mutation.
def shape_pair(left:Array<Inv.Slot> & Bool,right:Array<Inv.Slot> & Bool) -> Array<Inv.Slot> & Bool:
  (xs,first) = left
  (ys,second) = right
  (ANode{xs,ys},first && second)

def shape(+depth:Nat,slots:Array<Inv.Slot>) -> Array<Inv.Slot> & Bool:
  match depth slots:
    case 0n ALeaf{value}: (ALeaf{value},True{})
    case 0n ANode{left,right}: (ANode{left,right},False{})
    case 1n+rest ALeaf{value}: (ALeaf{value},False{})
    case 1n+rest ANode{left,right}: shape_pair(shape(rest,left),shape(rest,right))

def inventory_shaped(result:Array<Inv.Slot> & Bool,+length:U32,expected:U32) -> Inv.Inventory & Bool:
  (slots,valid) = result
  (Inv.Inventory{slots,length},valid && U32.is_eq(length,expected))

def inventory_shape(inventory:Inv.Inventory,expected:U32,depth:Nat) -> Inv.Inventory & Bool:
  Inv.Inventory{slots,length} = inventory
  inventory_shaped(shape(depth,slots),length,expected)

def table_shape(result:Inv.Inventory & Bool,player:I.State,catalog:R.Catalog,cache:Maybe<&2,R.Plan>,mode:M.Mode,revision:Nat,valid:Bool) -> State & Bool:
  (table,allowed) = result
  (State{player,catalog,TableGrid{table,revision},cache,mode},valid && allowed)

def owner_shape(owner:GridOwner,player:I.State,catalog:R.Catalog,cache:Maybe<&2,R.Plan>,mode:M.Mode,valid:Bool) -> State & Bool:
  match owner:
    case PlayerGrid{}: (State{player,catalog,PlayerGrid{},cache,mode},valid)
    case TableGrid{table,revision}: table_shape(inventory_shape(table,9,4n),player,catalog,cache,mode,revision,valid)

def player_shape(result:Inv.Inventory & Bool,selected:U32,abilities:I.Abilities,profile:I.Profile,catalog:R.Catalog,owner:GridOwner,cache:Maybe<&2,R.Plan>,mode:M.Mode) -> State & Bool:
  (inventory,valid) = result
  owner_shape(owner,I.State{inventory,selected,abilities,profile},catalog,cache,mode,valid)

def checked_owner(state:State) -> State & Bool:
  State{I.State{inventory,selected,abilities,profile},catalog,owner,cache,mode} = state
  player_shape(inventory_shape(inventory,48,6n),selected,abilities,profile,catalog,owner,cache,mode)

def new_with_components(player:I.State,catalog:R.Catalog,components:M.Mode) -> State:
  State{player,catalog,PlayerGrid{},None{},components}

def new(player:I.State,catalog:R.Catalog) -> State:
  State{player,catalog,PlayerGrid{},None{},M.DefaultOnly{}}

def parts_snapshot(result:I.State & I.MenuSnapshot,catalog:R.Catalog,owner:GridOwner,+cache:Maybe<&2,R.Plan>,grid:R.Grid,mode:M.Mode) -> State & Snapshot:
  (player,snapshot) = result
  (State{player,catalog,owner,cache,mode},Snapshot{snapshot,grid,cache})

def table_inspected(player:I.State,+snapshot:I.MenuSnapshot,catalog:R.Catalog,+cache:Maybe<&2,R.Plan>,+revision:Nat,result:Inv.Inventory & List<&2,Inv.Slot>,mode:M.Mode) -> State & Snapshot:
  (table,+slots) = result
  (State{player,catalog,TableGrid{table,revision},cache,mode},Snapshot{snapshot,R.Grid{3,3,slots},cache})

def inspected_owner(owner:GridOwner,player:I.State,+snapshot:I.MenuSnapshot,catalog:R.Catalog,+cache:Maybe<&2,R.Plan>,mode:M.Mode) -> State & Snapshot:
  match owner:
    case PlayerGrid{}:
      I.MenuSnapshot{saved,craft,carried,result,opened,revision} = snapshot
      (State{player,catalog,PlayerGrid{},cache,mode},Snapshot{snapshot,R.Grid{2,2,craft},cache})
    case TableGrid{table,revision}:
      table_inspected(player,snapshot,catalog,cache,revision,I.read_slots(9n,0,Inv.read(table,0),[]),mode)

def inspected(result:I.State & I.MenuSnapshot,catalog:R.Catalog,owner:GridOwner,cache:Maybe<&2,R.Plan>,mode:M.Mode) -> State & Snapshot:
  (player,snapshot) = result
  inspected_owner(owner,player,snapshot,catalog,cache,mode)

# Refusal reporting must not index an unbalanced public Array constructor.
# This structural walk returns the exact owner and its physical slot sequence.
def array_snapshot_pair(left:Array<Inv.Slot> & List<&2,Inv.Slot>,right:Array<Inv.Slot> & List<&2,Inv.Slot>) -> Array<Inv.Slot> & List<&2,Inv.Slot>:
  (xs,first) = left
  (ys,second) = right
  (ANode{xs,ys},List.append(&2,Inv.Slot,first,second))

def array_snapshot(slots:Array<Inv.Slot>) -> Array<Inv.Slot> & List<&2,Inv.Slot>:
  match slots:
    case ALeaf{+value}: (ALeaf{value},[value])
    case ANode{left,right}: array_snapshot_pair(array_snapshot(left),array_snapshot(right))

def inventory_snapshotted(result:Array<Inv.Slot> & List<&2,Inv.Slot>,+length:U32) -> Inv.Inventory & List<&2,Inv.Slot>:
  (slots,values) = result
  (Inv.Inventory{slots,length},I.first(U32.to_nat(length),values))

def inventory_snapshot(inventory:Inv.Inventory) -> Inv.Inventory & List<&2,Inv.Slot>:
  Inv.Inventory{slots,length} = inventory
  inventory_snapshotted(array_snapshot(slots),length)

def malformed_table(result:Inv.Inventory & List<&2,Inv.Slot>,player:I.State,snapshot:I.MenuSnapshot,catalog:R.Catalog,+cache:Maybe<&2,R.Plan>,mode:M.Mode,revision:Nat) -> State & Snapshot:
  (table,slots) = result
  (State{player,catalog,TableGrid{table,revision},cache,mode},Snapshot{snapshot,R.Grid{3,3,I.first(9n,slots)},cache})

def malformed_owner(owner:GridOwner,player:I.State,+snapshot:I.MenuSnapshot,catalog:R.Catalog,+cache:Maybe<&2,R.Plan>,mode:M.Mode) -> State & Snapshot:
  match owner:
    case PlayerGrid{}:
      I.MenuSnapshot{saved,craft,carried,result,opened,revision} = snapshot
      (State{player,catalog,PlayerGrid{},cache,mode},Snapshot{snapshot,R.Grid{2,2,craft},cache})
    case TableGrid{table,revision}: malformed_table(inventory_snapshot(table),player,snapshot,catalog,cache,mode,revision)

def malformed_player(result:I.State & I.MenuSnapshot,catalog:R.Catalog,owner:GridOwner,cache:Maybe<&2,R.Plan>,mode:M.Mode) -> State & Snapshot:
  (player,snapshot) = result
  malformed_owner(owner,player,snapshot,catalog,cache,mode)

def malformed_inspect(state:State) -> State & Snapshot:
  State{I.State{inventory,+selected,+abilities,+profile},catalog,owner,cache,mode} = state
  malformed_player(I.menu_inspected(selected,abilities,profile,inventory_snapshot(inventory)),catalog,owner,cache,mode)

def inspect_valid(state:State) -> State & Snapshot:
  State{player,catalog,owner,cache,mode} = state
  inspected(I.menu_inspect(player),catalog,owner,cache,mode)

def inspect_checked(result:State & Bool) -> State & Snapshot:
  (state,allowed) = result
  match allowed:
    case False{}: malformed_inspect(state)
    case True{}: inspect_valid(state)

def inspect(state:State) -> State & Snapshot:
  inspect_checked(checked_owner(state))

def output(plan:Maybe<&2,R.Plan>) -> Maybe<&2,Inv.Slot>:
  match plan:
    case None{}: None{}
    case Some{R.Plan{id,Inv.InvEmpty{},before,consumption}}: None{}
    case Some{R.Plan{id,result,before,consumption}}: Some{result}

def cache_player(player:I.State,result:Maybe<&2,Inv.Slot>) -> I.State:
  I.State{inventory,selected,abilities,I.Profile{definitions,status,I.Menu{opened,revision,previous}}} = player
  I.State{inventory,selected,abilities,I.Profile{definitions,status,I.Menu{opened,revision,result}}}

def refreshed(result:Result<&2,&2,String,Maybe<&2,R.Plan>>,state:State) -> State & Result<&2,&2,String,Unit>:
  match result:
    case Fail{message}: (state,Fail{message})
    case Done{+cache}:
      State{player,catalog,owner,old,mode} = state
      (State{cache_player(player,output(cache)),catalog,owner,cache,mode},Done{Unit{}})

def grid_metadata(player:I.State,grid:R.Grid,mode:M.Mode) -> I.State & List<&2,Inv.ItemMetadata>:
  I.State{inventory,selected,abilities,+profile} = player
  I.Profile{definitions,status,menu} = profile
  R.Grid{width,height,slots} = grid
  (I.State{inventory,selected,abilities,profile},M.input_metadata(slots,mode,definitions))

def refresh_grid(result:I.State & List<&2,Inv.ItemMetadata>,+catalog:R.Catalog,owner:GridOwner,cache:Maybe<&2,R.Plan>,mode:M.Mode,+grid:R.Grid) -> State & Result<&2,&2,String,Unit>:
  (player,metadata) = result
  refreshed(R.find_with_metadata(catalog,grid,metadata),State{player,catalog,owner,cache,mode})

def refresh_inspected(result:State & Snapshot) -> State & Result<&2,&2,String,Unit>:
  (State{player,+catalog,owner,cache,+mode},Snapshot{snapshot,+grid,previous}) = result
  refresh_grid(grid_metadata(player,grid,mode),catalog,owner,cache,mode,grid)

def refresh_checked(result:State & Bool) -> State & Result<&2,&2,String,Unit>:
  (state,allowed) = result
  match allowed:
    case False{}: (state,Fail{"invalid crafting inventory owner geometry"})
    case True{}: refresh_inspected(inspect(state))

def refresh(state:State) -> State & Result<&2,&2,String,Unit>:
  refresh_checked(checked_owner(state))

def commit_player(player:I.State,slots:List<&2,Inv.Slot>) -> I.State:
  I.State{inventory,selected,abilities,profile} = player
  I.revised(I.State{I.write_returned(slots,0,inventory),selected,abilities,profile})

def player_grid_written(player:I.State,+slots:List<&2,Inv.Slot>,inputs:List<&2,Inv.Slot>) -> I.State:
  commit_player(player,List.append(&2,Inv.Slot,I.first(43n,slots),List.append(&2,Inv.Slot,inputs,[I.list_slot(I.skip(47n,slots))])))

def commit_grid(grid:R.Grid,state:State,+transaction:P.Transaction) -> State & Result<&2,&2,String,Inv.Slot>:
  R.Grid{width,height,inputs} = grid
  State{player,catalog,owner,cache,mode} = state
  match owner:
    case PlayerGrid{}:
      (State{player_grid_written(player,P.slots(transaction),inputs),catalog,PlayerGrid{},None{},mode},Done{P.taken(transaction)})
    case TableGrid{table,revision}:
      (State{commit_player(player,P.slots(transaction)),catalog,TableGrid{I.write_returned(inputs,0,table),1n+revision},None{},mode},Done{P.taken(transaction)})

def commit(state:State,+transaction:P.Transaction) -> State & Result<&2,&2,String,Inv.Slot>:
  commit_grid(P.grid(transaction),state,transaction)

def take_guard(allowed:Bool,state:State,+transaction:P.Transaction) -> State & Result<&2,&2,String,Inv.Slot>:
  match allowed:
    case False{}: (state,Fail{P.message(transaction)})
    case True{}: commit(state,transaction)

def take_planned(state:State,+transaction:P.Transaction) -> State & Result<&2,&2,String,Inv.Slot>:
  take_guard(P.admitted(transaction),state,transaction)

def same_steps(a:List<&2,R.Consumption>,b:List<&2,R.Consumption>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case R.Consumption{slot,count,remainder} <> rest R.Consumption{other,amount,remaining} <> tail:
      U32.is_eq(slot,other) && U32.is_eq(count,amount) && R.snapshot_equal([remainder],[remaining]) && same_steps(rest,tail)
    case _ _: False{}

def same_plan(a:R.Plan,b:R.Plan) -> Bool:
  R.Plan{+id,+result,before,+steps} = a
  R.Plan{other,output,grid,remaining} = b
  String.eq(id,other) && R.snapshot_equal([result],[output]) && R.current(R.Plan{id,result,before,steps},grid) && same_steps(steps,remaining)

def selected_plan(verified:Bool,state:State,snapshot:I.MenuSnapshot,grid:R.Grid,plan:R.Plan,button:U32) -> State & Result<&2,&2,String,Inv.Slot>:
  match verified:
    case False{}: (state,Fail{"cached crafting recipe changed; refresh required"})
    case True{}:
      State{player,catalog,owner,cache,+mode} = state
      I.State{inventory,+selected,abilities,+profile} = player
      I.Profile{definitions,status,menu} = profile
      take_planned(State{I.State{inventory,selected,abilities,profile},catalog,owner,cache,mode},P.plan_with(I.menu_slots(snapshot),grid,plan,selected,definitions,button,mode))

def freshly_selected(found:Result<&2,&2,String,Maybe<&2,R.Plan>>,state:State,snapshot:I.MenuSnapshot,grid:R.Grid,+plan:R.Plan,button:U32) -> State & Result<&2,&2,String,Inv.Slot>:
  match found:
    case Fail{message}: (state,Fail{message})
    case Done{None{}}: (state,Fail{"cached crafting recipe no longer matches"})
    case Done{Some{actual}}: selected_plan(same_plan(plan,actual),state,snapshot,grid,plan,button)

def cached_with_metadata(result:I.State & List<&2,Inv.ItemMetadata>,+catalog:R.Catalog,owner:GridOwner,cache:Maybe<&2,R.Plan>,mode:M.Mode,snapshot:I.MenuSnapshot,+grid:R.Grid,plan:R.Plan,button:U32) -> State & Result<&2,&2,String,Inv.Slot>:
  (player,metadata) = result
  freshly_selected(R.find_with_metadata(catalog,grid,metadata),State{player,catalog,owner,cache,mode},snapshot,grid,plan,button)

def cached_current(current:Bool,state:State,snapshot:I.MenuSnapshot,+grid:R.Grid,plan:R.Plan,button:U32) -> State & Result<&2,&2,String,Inv.Slot>:
  match current:
    case False{}: (state,Fail{"stale crafting plan; refresh required"})
    case True{}:
      State{player,+catalog,owner,cache,+mode} = state
      cached_with_metadata(grid_metadata(player,grid,mode),catalog,owner,cache,mode,snapshot,grid,plan,button)

def cached_take(cache:Maybe<&2,R.Plan>,state:State,snapshot:I.MenuSnapshot,+grid:R.Grid,button:U32) -> State & Result<&2,&2,String,Inv.Slot>:
  match cache:
    case None{}: (state,Fail{"crafting plan is absent; refresh required"})
    case Some{+plan}: cached_current(R.current(plan,grid),state,snapshot,grid,plan,button)

def take_open(allowed:Bool,state:State,snapshot:I.MenuSnapshot,grid:R.Grid,cache:Maybe<&2,R.Plan>,button:U32) -> State & Result<&2,&2,String,Inv.Slot>:
  match allowed:
    case False{}: (state,Fail{"player inventory menu is closed or pickup button invalid"})
    case True{}: cached_take(cache,state,snapshot,grid,button)

def take_inspected(result:State & Snapshot,+button:U32) -> State & Result<&2,&2,String,Inv.Slot>:
  (state,Snapshot{+snapshot,grid,cache}) = result
  I.MenuSnapshot{saved,craft,carried,result,opened,revision} = snapshot
  take_open(opened && U32.is_lt(button,2),state,snapshot,grid,cache,button)

def take_checked(result:State & Bool,button:U32) -> State & Result<&2,&2,String,Inv.Slot>:
  (state,allowed) = result
  match allowed:
    case False{}: (state,Fail{"invalid crafting inventory owner geometry"})
    case True{}: take_inspected(inspect(state),button)

def take(state:State,button:U32) -> State & Result<&2,&2,String,Inv.Slot>:
  take_checked(checked_owner(state),button)
