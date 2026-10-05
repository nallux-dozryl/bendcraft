import Base
import ./player_cooking_client_input.bend as Input
import ./player_cooking_menu_screen.bend as Screen
import ./player_cooking_menu.bend as Menu
import ./player_inventory_screen.bend as InventoryScreen
import ./inventory_key_consumer.bend as Keys
import ./resource_client_wire.bend as Wire
import ./cooking_world_store.bend as Store

# The complete received cooking DTO includes its actual furnace handle/body and
# every persisted/player/crafting/carried/result/status field. Local UI work
# cannot replace any part of that authority. Correlation remains the presenter's
# transport obligation; these laws do not turn an uncorrelated DTO into authority.
law observation_installs_complete_received_snapshot:
  for controller:Screen.State
  for previous:Maybe<&2,Menu.Snapshot>
  for +snapshot:Menu.Snapshot
  {Input.authority(Input.observed(Input.State{controller,previous},snapshot)) == Some{snapshot} : Maybe<&2,Menu.Snapshot>}

law completion_installs_complete_received_snapshot:
  for controller:Screen.State
  for previous:Maybe<&2,Menu.Snapshot>
  for accepted:Bool
  for message:String
  for +snapshot:Menu.Snapshot
  for effects:List<&2,Store.Effect>
  {Input.updated_authority(Input.completed(Input.State{controller,previous},Menu.Reply{accepted,message,snapshot,effects})) == Some{snapshot} : Maybe<&2,Menu.Snapshot>}

law focus_retains_complete_received_snapshot:
  for +state:Input.State
  for focused:Bool
  for captured:Bool
  {Input.updated_authority(Input.focus(state,focused,captured)) == Input.authority(state) : Maybe<&2,Menu.Snapshot>}

law event_retains_complete_received_snapshot:
  for event:Event
  for intents:List<&2,Screen.Intent>
  for events:List<&2,Event>
  for +state:Input.State
  for viewport:InventoryScreen.Viewport
  for focused:Bool
  for captured:Bool
  {Input.batch_authority(Input.event(event,intents,events,state,viewport,focused,captured)) == Input.authority(state) : Maybe<&2,Menu.Snapshot>}

law packet_retains_complete_received_snapshot:
  for physical:Bool
  for profile:Keys.Profile
  for +state:Input.State
  for pending:List<Event>
  for viewport:InventoryScreen.Viewport
  for +focused:Bool
  for +captured:Bool
  {Input.batch_authority(Input.packet_keys(physical,profile,state,pending,viewport,focused,captured)) == Input.authority(state) : Maybe<&2,Menu.Snapshot>}

# Closed, nonpending cooking must leave the exact physical-marker/character
# batch available to the ordinary menu owner. It cannot normalize it first.
law inactive_packet_preserves_complete_original_batch:
  for physical:Bool
  for profile:Keys.Profile
  for +state:Input.State
  for pending:List<Event>
  for viewport:InventoryScreen.Viewport
  for +focused:Bool
  for +captured:Bool
  for inactive:{Input.active(state) == False{} : Bool}
  {Input.batch_events(Input.packet_keys(physical,profile,state,pending,viewport,focused,captured)) == Input.shared_events(pending) : List<&2,Event>}

# Active OS Close is delegated to the actual cooking screen's authoritative
# MenuClose/deferred Quit lifecycle. Its lifecycle contracts belong to that
# screen owner; inactive_packet_preserves_complete_original_batch above retains
# an inactive Close for the ordinary menu owner.

law inspect_preserves_actual_menu_owner:
  for +menu:U32
  {Input.wire(Menu.MenuInspect{menu}) == Wire.CookingInspect{menu} : Wire.Command}

law pickup_preserves_actual_menu_cell_and_button:
  for +menu:U32
  for +index:U32
  for +button:U32
  {Input.wire(Menu.MenuPickup{menu,index,button}) == Wire.CookingClick{menu,index,button} : Wire.Command}

law quick_move_preserves_actual_menu_cell:
  for +menu:U32
  for +index:U32
  {Input.wire(Menu.MenuQuickMove{menu,index}) == Wire.CookingQuickMove{menu,index} : Wire.Command}

law close_preserves_actual_menu_owner:
  for +menu:U32
  {Input.wire(Menu.MenuClose{menu}) == Wire.CookingClose{menu} : Wire.Command}
