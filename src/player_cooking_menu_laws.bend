import Base
import ./player_cooking_menu.bend as Menu
import ./player_cooking_menu_transfer.bend as Move
import ./cooking_world.bend as CW
import ./cooking_world_store.bend as Store
import ./cooking_world_bindings.bend as Binding
import ./furnace_authority.bend as FA
import ./player_inventory.bend as I
import ./player_item_definitions.bend as D
import ./player_cooking_menu_campfire.bend as Camp
import ./player_cooking_menu_screen.bend as Screen
import ./player_inventory_screen.bend as InventoryScreen
import ./campfire_authority_items.bend as AI
import ./core.bend as C
import ./inventory.bend as Inv
import ./cooking_recipe.bend as K

# Each refusal equation retains the complete actual owners, including Core
# pending/events, light, all store entries, player hidden backing and profile.
law refused_slot_access_retains_both_actual_owners:
  for admit:Menu.Reply -> Result<&2,&2,String,Unit>
  for context:CW.Context
  for access:Menu.Access
  for owner:CW.State
  for inventory:I.State
  for handle:Menu.Handle
  for snapshot:I.MenuSnapshot
  for action:Menu.Action
  {Menu.slot_admitted(False{},admit,context,access,owner,inventory,handle,snapshot,action) ==
    (owner,inventory,Done{Menu.reply(False{},"cooking-menu:authority-menu-range-or-incarnation-refused",handle,None{},snapshot,[])}) : CW.State & I.State & Result<&2,&2,String,Menu.Reply>}
def refused_slot_access_retains_both_actual_owners(admit,context,access,owner,inventory,handle,snapshot,action): {==}

law reply_budget_refusal_retains_both_actual_owners:
  for context:CW.Context
  for access:Menu.Access
  for owner:CW.State
  for inventory:I.State
  for handle:Menu.Handle
  for binding:Binding.Binding
  for old:FA.Snapshot
  for snapshot:I.MenuSnapshot
  for plan:Move.Plan
  for message:String
  {Menu.preflighted(context,access,owner,inventory,handle,binding,old,snapshot,plan,Fail{message}) ==
    (owner,inventory,Done{Menu.reply(False{},message,handle,Some{Menu.view(old)},snapshot,[])}) : CW.State & I.State & Result<&2,&2,String,Menu.Reply>}
def reply_budget_refusal_retains_both_actual_owners(context,access,owner,inventory,handle,binding,old,snapshot,plan,message): {==}

law failed_return_admission_retains_both_actual_owners:
  for owner:CW.State
  for inventory:I.State
  for before:Menu.Handle
  for after:Menu.Handle
  for furnace:Maybe<&2,Menu.FurnaceView>
  for snapshot:I.MenuSnapshot
  for opened:Bool
  for message:String
  {Menu.returned_admitted(owner,inventory,before,after,furnace,snapshot,opened,Fail{message}) ==
    (owner,inventory,Done{Menu.reply(False{},message,before,None{},snapshot,[])}) : CW.State & I.State & Result<&2,&2,String,Menu.Reply>}
def failed_return_admission_retains_both_actual_owners(owner,inventory,before,after,furnace,snapshot,opened,message): {==}

law missing_menu_search_retains_actual_store_order:
  for context:CW.Context
  for position:C.Position
  for state:U32
  for entries:List<&1,Store.Entry>
  {Menu.find(0n,context,position,state,entries) == (entries,Fail{"cooking-menu:missing-owner"}) : List<&1,Store.Entry> & Result<&2,&2,String,Menu.Live>}
def missing_menu_search_retains_actual_store_order(context,position,state,entries):
  match entries:
    case Nil{}: {==}
    case head <> rest: {==}

law blocked_transfer_retains_complete_observation:
  for values:List<&2,Inv.Slot>
  for source:U32
  for target:U32
  for limit:U32
  for item:Inv.Slot
  for existing:Inv.Slot
  {Move.move_valid(False{},values,source,target,limit,item,existing) == values : List<&2,Inv.Slot>}
def blocked_transfer_retains_complete_observation(values,source,target,limit,item,existing): {==}

law changed_player_publication_retains_profile_authority:
  for owned:Inv.Inventory
  for selected:U32
  for abilities:I.Abilities
  for catalog:D.Catalog
  for status:I.Status
  for opened:Bool
  for revision:Nat
  for result:Maybe<&2,Inv.Slot>
  {Menu.publish_revision(I.State{owned,selected,abilities,I.Profile{catalog,status,I.Menu{opened,revision,result}}},True{}) ==
    I.State{owned,selected,abilities,I.Profile{catalog,status,I.Menu{opened,1n+revision,None{}}}} : I.State}
def changed_player_publication_retains_profile_authority(owned,selected,abilities,catalog,status,opened,revision,result): {==}

# World hand placement obeys the same combined-owner publication boundary.
law campfire_reply_budget_refusal_retains_both_actual_owners:
  for context:CW.Context
  for owner:CW.State
  for inventory:I.State
  for position:C.Position
  for access:Menu.Access
  for snapshot:I.MenuSnapshot
  for index:U32
  for held:AI.Input
  for message:String
  {Camp.admitted(Fail{message},context,owner,inventory,position,access,snapshot,index,held) ==
    (owner,inventory,Done{Menu.reply(False{},message,Menu.Closed{},None{},snapshot,[])}) : CW.State & I.State & Result<&2,&2,String,Menu.Reply>}
def campfire_reply_budget_refusal_retains_both_actual_owners(context,owner,inventory,position,access,snapshot,index,held,message): {==}

law campfire_refused_access_retains_both_actual_owners:
  for admit:Menu.Reply -> Result<&2,&2,String,Unit>
  for context:CW.Context
  for owner:CW.State
  for inventory:I.State
  for position:C.Position
  for access:Menu.Access
  for snapshot:I.MenuSnapshot
  for offhand:Bool
  {Camp.allowed(False{},admit,context,owner,inventory,position,access,snapshot,offhand) ==
    (owner,inventory,Done{Menu.reply(False{},"cooking-menu:campfire-world-authority-refused",Menu.Closed{},None{},snapshot,[])}) : CW.State & I.State & Result<&2,&2,String,Menu.Reply>}
def campfire_refused_access_retains_both_actual_owners(admit,context,owner,inventory,position,access,snapshot,offhand): {==}

# This equation retains every controller field that belongs to a correlated
# in-flight action while clearing all native holds/pointer metadata on focus loss.
law screen_focus_loss_retains_pending_and_authority_identity:
  for menu:U32
  for open:Bool
  for shift:U32
  for keys:U32
  for buttons:U32
  for pending:Bool
  for hover:Maybe<&2,U32>
  for viewport:InventoryScreen.Viewport
  for point:Maybe<&2,Screen.Point>
  for message:String
  for quit:U32
  {Screen.focus(Screen.State{menu,open,True{},False{},shift,keys,buttons,pending,hover,viewport,point,message,quit},False{},False{}) ==
    Screen.Update{Screen.State{menu,open,False{},False{},0,0,0,pending,None{},viewport,None{},message,quit},[Screen.ReleaseControls{},Screen.Capture{False{}}],open} : Screen.Update}
def screen_focus_loss_retains_pending_and_authority_identity(menu,open,shift,keys,buttons,pending,hover,viewport,point,message,quit): {==}

# Full production completion equations bind the server snapshot to every UI
# field and the actual deferred-close action. No helper-only Bool projection
# substitutes for this response/controller/capture composition.
law confirmed_os_close_reconciles_full_controller_and_quits:
  for old:U32
  for focused:Bool
  for captured:Bool
  for shift:U32
  for keys:U32
  for buttons:U32
  for pending:Bool
  for hover:Maybe<&2,U32>
  for viewport:InventoryScreen.Viewport
  for point:Maybe<&2,Screen.Point>
  for previous_message:String
  for accepted:Bool
  for message:String
  for saved:I.Persisted
  for craft:List<&2,Inv.Slot>
  for carried:Inv.Slot
  for result:Maybe<&2,Inv.Slot>
  for opened:Bool
  for revision:Nat
  for effects:List<&2,Store.Effect>
  {Screen.completed(Screen.State{old,True{},focused,captured,shift,keys,buttons,pending,hover,viewport,point,previous_message,2},
    Menu.Reply{accepted,message,Menu.Snapshot{Menu.Closed{},None{},I.MenuSnapshot{saved,craft,carried,result,opened,revision}},effects}) ==
    Screen.Update{Screen.State{0,False{},focused,False{},0,0,0,False{},None{},viewport,None{},message,0},[Screen.Quit{}],True{}} : Screen.Update}
def confirmed_os_close_reconciles_full_controller_and_quits(old,focused,captured,shift,keys,buttons,pending,hover,viewport,point,previous_message,accepted,message,saved,craft,carried,result,opened,revision,effects): {==}

law deferred_os_close_binds_acknowledged_menu_before_close:
  for old:U32
  for menu:U32
  for peer:U32
  for position:C.Position
  for block:String
  for kind:K.CookingKind
  for token:Nat
  for furnace:Maybe<&2,Menu.FurnaceView>
  for focused:Bool
  for captured:Bool
  for shift:U32
  for keys:U32
  for buttons:U32
  for hover:Maybe<&2,U32>
  for viewport:InventoryScreen.Viewport
  for point:Maybe<&2,Screen.Point>
  for previous_message:String
  for accepted:Bool
  for message:String
  for saved:I.Persisted
  for craft:List<&2,Inv.Slot>
  for carried:Inv.Slot
  for result:Maybe<&2,Inv.Slot>
  for revision:Nat
  for effects:List<&2,Store.Effect>
  {Screen.completed(Screen.State{old,False{},focused,captured,shift,keys,buttons,True{},hover,viewport,point,previous_message,1},
    Menu.Reply{accepted,message,Menu.Snapshot{Menu.Furnace{menu,peer,position,block,kind,token},furnace,I.MenuSnapshot{saved,craft,carried,result,True{},revision}},effects}) ==
    Screen.Update{Screen.State{menu,True{},focused,False{},0,0,0,True{},None{},viewport,None{},"",2},[Screen.Request{Menu.MenuClose{menu}}],True{}} : Screen.Update}
def deferred_os_close_binds_acknowledged_menu_before_close(old,menu,peer,position,block,kind,token,furnace,focused,captured,shift,keys,buttons,hover,viewport,point,previous_message,accepted,message,saved,craft,carried,result,revision,effects): {==}
