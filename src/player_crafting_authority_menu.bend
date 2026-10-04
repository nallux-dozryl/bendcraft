import Base
import ./inventory.bend as Inv
import ./player_inventory.bend as I
import ./player_crafting_authority.bend as A
import ./crafting_recipe.bend as R
import ./player_crafting_authority_components.bend as M

# Named request producer for the existing session/actor menu boundary. The
# caller retains the complete A.State through each request. No inventory-to-
# recipe import, second Array owner, independent click cache or output slot is
# introduced in the inventory foundation.
type Reply is Data:
  Reply{accepted:Bool,message:String,snapshot:I.MenuSnapshot,grid:R.Grid,taken:Inv.Slot,cache_refreshed:Bool}

def reported(result:A.State & A.Snapshot,accepted:Bool,message:String,taken:Inv.Slot,refreshed:Bool) -> A.State & Reply:
  (state,A.Snapshot{snapshot,grid,cache}) = result
  (state,Reply{accepted,message,snapshot,grid,taken,refreshed})

def report(state:A.State,accepted:Bool,message:String,taken:Inv.Slot,refreshed:Bool) -> A.State & Reply:
  reported(A.inspect(state),accepted,message,taken,refreshed)

# Physics acceptance and subsequent derived-cache refresh are distinct facts.
# A refresh failure cannot retrospectively report an admitted, committed craft
# as an atomic refusal. Valid full service catalogs make that branch unreachable
# for ordinary inputs; a changed/incomplete service catalog remains observable.
def refreshed(result:A.State & Result<&2,&2,String,Unit>,taken:Inv.Slot) -> A.State & Reply:
  (state,status) = result
  match status:
    case Fail{message}: report(state,True{},message,taken,False{})
    case Done{unit}: report(state,True{},"",taken,True{})

def refresh_report(result:A.State & Result<&2,&2,String,Unit>) -> A.State & Reply:
  (state,status) = result
  match status:
    case Fail{message}: report(state,False{},message,Inv.InvEmpty{},False{})
    case Done{unit}: report(state,True{},"",Inv.InvEmpty{},True{})

def refresh(state:A.State) -> A.State & Reply:
  refresh_report(A.refresh(state))

def taken(result:A.State & Result<&2,&2,String,Inv.Slot>) -> A.State & Reply:
  (state,status) = result
  match status:
    case Fail{message}: report(state,False{},message,Inv.InvEmpty{},False{})
    case Done{slot}: refreshed(A.refresh(state),slot)

def invalidated(player:I.State,catalog:R.Catalog,owner:A.GridOwner,mode:M.Mode) -> A.State:
  A.State{player,catalog,owner,None{},mode}

def ordinary(result:I.State & Result<&2,&2,String,Unit>,catalog:R.Catalog,owner:A.GridOwner,cache:Maybe<&2,R.Plan>,mode:M.Mode) -> A.State & Reply:
  (player,status) = result
  match status:
    case Fail{message}: report(A.State{player,catalog,owner,cache,mode},False{},message,Inv.InvEmpty{},False{})
    case Done{unit}: refreshed(A.refresh(invalidated(player,catalog,owner,mode)),Inv.InvEmpty{})

def open_owned(state:A.State) -> A.State & Reply:
  A.State{player,catalog,owner,cache,mode} = state
  ordinary(I.menu_open(player),catalog,owner,cache,mode)

def open_checked(result:A.State & Bool) -> A.State & Reply:
  (state,allowed) = result
  match allowed:
    case False{}: report(state,False{},"invalid crafting inventory owner geometry",Inv.InvEmpty{},False{})
    case True{}: open_owned(state)

def open(state:A.State) -> A.State & Reply:
  open_checked(A.checked_owner(state))

def closed(result:I.State & Result<&2,&2,String,Unit>,catalog:R.Catalog,cache:Maybe<&2,R.Plan>,mode:M.Mode) -> A.State & Reply:
  (player,status) = result
  match status:
    case Fail{message}: report(A.State{player,catalog,A.PlayerGrid{},cache,mode},False{},message,Inv.InvEmpty{},False{})
    case Done{unit}: report(invalidated(player,catalog,A.PlayerGrid{},mode),True{},"",Inv.InvEmpty{},True{})

def close_owned(state:A.State) -> A.State & Reply:
  A.State{player,catalog,owner,cache,mode} = state
  match owner:
    case A.TableGrid{table,revision}:
      report(A.State{player,catalog,A.TableGrid{table,revision},cache,mode},False{},"crafting-table close requires owned input return or drop disposition",Inv.InvEmpty{},False{})
    case A.PlayerGrid{}: closed(I.menu_close(player),catalog,cache,mode)

def close_checked(result:A.State & Bool) -> A.State & Reply:
  (state,allowed) = result
  match allowed:
    case False{}: report(state,False{},"invalid crafting inventory owner geometry",Inv.InvEmpty{},False{})
    case True{}: close_owned(state)

def close(state:A.State) -> A.State & Reply:
  close_checked(A.checked_owner(state))

def result_click(click:I.Click,state:A.State) -> A.State & Reply:
  match click:
    case I.Pickup{button}: taken(A.take(state,button))
    case _: report(state,False{},"crafting result click kind requires its authoritative consumer",Inv.InvEmpty{},False{})

def ordinary_click(owner:A.GridOwner,player:I.State,catalog:R.Catalog,cache:Maybe<&2,R.Plan>,mode:M.Mode,index:U32,click:I.Click) -> A.State & Reply:
  match owner:
    case A.TableGrid{table,revision}:
      report(A.State{player,catalog,A.TableGrid{table,revision},cache,mode},False{},"crafting-table input clicks require the nine-input topology consumer",Inv.InvEmpty{},False{})
    case A.PlayerGrid{}: ordinary(I.menu_click(player,index,click),catalog,A.PlayerGrid{},cache,mode)

def click_index(result:Bool,state:A.State,index:U32,click:I.Click) -> A.State & Reply:
  match result:
    case True{}: result_click(click,state)
    case False{}:
      A.State{player,catalog,owner,cache,mode} = state
      ordinary_click(owner,player,catalog,cache,mode,index,click)

def click_checked(result:A.State & Bool,+index:U32,click:I.Click) -> A.State & Reply:
  (state,allowed) = result
  match allowed:
    case False{}: report(state,False{},"invalid crafting inventory owner geometry",Inv.InvEmpty{},False{})
    case True{}: click_index(U32.is_eq(index,0),state,index,click)

def click(state:A.State,index:U32,click:I.Click) -> A.State & Reply:
  click_checked(A.checked_owner(state),index,click)

def inspected(result:A.State & A.Snapshot) -> A.State & I.MenuSnapshot:
  (state,A.Snapshot{snapshot,grid,cache}) = result
  (state,snapshot)

def inspect(state:A.State) -> A.State & I.MenuSnapshot: inspected(A.inspect(state))
