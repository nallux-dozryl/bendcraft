import Base
import ./player_cooking_client_input.bend as Input
import ./player_cooking_client_input_laws.bend as L
import ./player_cooking_menu_screen.bend as Screen
import ./player_cooking_menu.bend as Menu
import ./player_inventory_screen.bend as InventoryScreen
import ./inventory_key_consumer.bend as Keys

def L.observation_installs_complete_received_snapshot(controller,previous,snapshot): {==}

def updated_retains_snapshot(+snapshot:Maybe<&2,Menu.Snapshot>,result:Screen.Update) ->
    {Input.updated_authority(Input.updated(snapshot,result)) == snapshot : Maybe<&2,Menu.Snapshot>}:
  match result:
    case Screen.Update{controller,intents,consumed}: {==}

def L.completion_installs_complete_received_snapshot(controller,previous,accepted,message,snapshot,effects):
  updated_retains_snapshot(Some{snapshot},Screen.completed(controller,Menu.Reply{accepted,message,snapshot,effects}))

def L.focus_retains_complete_received_snapshot(state,focused,captured):
  match state:
    case Input.State{controller,+snapshot}:
      updated_retains_snapshot(snapshot,Screen.focus(controller,focused,captured))

def stepped_retains_snapshot(+snapshot:Maybe<&2,Menu.Snapshot>,intents:List<&2,Screen.Intent>,events:List<&2,Event>,result:Screen.Update) ->
    {Input.batch_authority(Input.stepped(snapshot,intents,events,result)) == snapshot : Maybe<&2,Menu.Snapshot>}:
  match result:
    case Screen.Update{controller,requests,consumed}: {==}

def L.event_retains_complete_received_snapshot(event,intents,events,state,viewport,focused,captured):
  match state:
    case Input.State{controller,+snapshot}:
      stepped_retains_snapshot(snapshot,intents,events,Screen.step(controller,viewport,event,focused,captured))

def mapped_retains_snapshot(input:Maybe<&2,Event>,intents:List<&2,Screen.Intent>,events:List<&2,Event>,+state:Input.State,
    viewport:InventoryScreen.Viewport,focused:Bool,captured:Bool) ->
    {Input.batch_authority(Input.mapped(input,intents,events,state,viewport,focused,captured)) == Input.authority(state) : Maybe<&2,Menu.Snapshot>}:
  match input:
    case None{}: {==}
    case Some{value}: L.event_retains_complete_received_snapshot(value,intents,events,state,viewport,focused,captured)

def key_retains_snapshot(profile:Keys.Profile,input:Event,intents:List<&2,Screen.Intent>,events:List<&2,Event>,+state:Input.State,
    viewport:InventoryScreen.Viewport,focused:Bool,captured:Bool) ->
    {Input.batch_authority(Input.key_event(profile,input,intents,events,state,viewport,focused,captured)) == Input.authority(state) : Maybe<&2,Menu.Snapshot>}:
  mapped_retains_snapshot(Keys.event(profile,InventoryScreen.new(False{}),input),intents,events,state,viewport,focused,captured)

def events_retain_snapshot(pending:List<Event>,+viewport:InventoryScreen.Viewport,+focused:Bool,+captured:Bool,+batch:Input.Batch) ->
    {Input.batch_authority(Input.events(pending,viewport,focused,captured,batch)) == Input.batch_authority(batch) : Maybe<&2,Menu.Snapshot>}:
  match pending batch:
    case Nil{} Input.Batch{state,intents,reversed}: {==}
    case +head <> tail Input.Batch{+state,+intents,+reversed}:
      Equal.trans(Maybe<&2,Menu.Snapshot>,
        Input.batch_authority(Input.events(tail,viewport,focused,captured,Input.event(head,intents,reversed,state,viewport,focused,captured))),
        Input.batch_authority(Input.event(head,intents,reversed,state,viewport,focused,captured)),Input.authority(state),
        events_retain_snapshot(tail,viewport,focused,captured,Input.event(head,intents,reversed,state,viewport,focused,captured)),
        L.event_retains_complete_received_snapshot(head,intents,reversed,state,viewport,focused,captured))

def keys_retain_snapshot(left:Nat,pending:List<&2,Event>,+profile:Keys.Profile,+viewport:InventoryScreen.Viewport,+focused:Bool,+captured:Bool,+batch:Input.Batch) ->
    {Input.batch_authority(Input.key_events_go(left,pending,profile,viewport,focused,captured,batch)) == Input.batch_authority(batch) : Maybe<&2,Menu.Snapshot>}:
  match left pending batch:
    case 0n Nil{} Input.Batch{state,intents,reversed}: {==}
    case 0n head <> tail Input.Batch{state,intents,reversed}: {==}
    case 1n+n Nil{} Input.Batch{state,intents,reversed}: {==}
    case 1n+n +head <> tail Input.Batch{+state,+intents,+reversed}:
      Equal.trans(Maybe<&2,Menu.Snapshot>,
        Input.batch_authority(Input.key_events_go(n,Keys.following(profile,InventoryScreen.new(False{}),head,tail),profile,viewport,focused,captured,Input.key_event(profile,head,intents,reversed,state,viewport,focused,captured))),
        Input.batch_authority(Input.key_event(profile,head,intents,reversed,state,viewport,focused,captured)),Input.authority(state),
        keys_retain_snapshot(n,Keys.following(profile,InventoryScreen.new(False{}),head,tail),profile,viewport,focused,captured,Input.key_event(profile,head,intents,reversed,state,viewport,focused,captured)),
        key_retains_snapshot(profile,head,intents,reversed,state,viewport,focused,captured))

def active_packet_retains_snapshot(physical:Bool,profile:Keys.Profile,pending:List<Event>,viewport:InventoryScreen.Viewport,focused:Bool,captured:Bool,+state:Input.State,intents:List<&2,Screen.Intent>) ->
    {Input.batch_authority(Input.active_packet(physical,profile,pending,viewport,focused,captured,Input.Batch{state,intents,[]})) == Input.authority(state) : Maybe<&2,Menu.Snapshot>}:
  match physical:
    case False{}: events_retain_snapshot(pending,viewport,focused,captured,Input.Batch{state,intents,[]})
    case True{}:
      +shared = Input.shared_events(pending)
      keys_retain_snapshot(List.length(&2,Event,shared),shared,profile,viewport,focused,captured,Input.Batch{state,intents,[]})

def packet_from_focus(routed:Bool,physical:Bool,profile:Keys.Profile,+state:Input.State,pending:List<Event>,viewport:InventoryScreen.Viewport,focused:Bool,captured:Bool,
    result:Input.State & List<&2,Screen.Intent>,
    retained:{Input.updated_authority(result) == Input.authority(state) : Maybe<&2,Menu.Snapshot>}) ->
    {Input.batch_authority(Input.focused_packet(routed,physical,profile,pending,viewport,focused,captured,result)) == Input.authority(state) : Maybe<&2,Menu.Snapshot>}:
  match routed:
    case False{}:
      (next,intents) = result
      retained
    case True{}:
      (+next,intents) = result
      Equal.trans(Maybe<&2,Menu.Snapshot>,
        Input.batch_authority(Input.active_packet(physical,profile,pending,viewport,focused,captured,Input.Batch{next,intents,[]})),
        Input.authority(next),Input.authority(state),
        active_packet_retains_snapshot(physical,profile,pending,viewport,focused,captured,next,intents),retained)

def L.packet_retains_complete_received_snapshot(physical,profile,state,pending,viewport,focused,captured):
  packet_from_focus(Input.active(state),physical,profile,state,pending,viewport,focused,captured,Input.focus(state,focused,captured),
    L.focus_retains_complete_received_snapshot(state,focused,captured))

def inactive_from_focus(physical:Bool,profile:Keys.Profile,pending:List<Event>,viewport:InventoryScreen.Viewport,focused:Bool,captured:Bool,
    result:Input.State & List<&2,Screen.Intent>) ->
    {Input.batch_events(Input.focused_packet(False{},physical,profile,pending,viewport,focused,captured,result)) == Input.shared_events(pending) : List<&2,Event>}:
  (state,intents) = result
  {==}

def L.inactive_packet_preserves_complete_original_batch(physical,profile,state,pending,viewport,focused,captured,inactive):
  %Equal.sym(Bool,Input.active(state),False{},inactive) :
    {Input.batch_events(Input.focused_packet(_,physical,profile,pending,viewport,focused,captured,Input.focus(state,focused,captured))) == Input.shared_events(pending) : List<&2,Event>}
  inactive_from_focus(physical,profile,pending,viewport,focused,captured,Input.focus(state,focused,captured))

def L.inspect_preserves_actual_menu_owner(menu): {==}
def L.pickup_preserves_actual_menu_cell_and_button(menu,index,button): {==}
def L.quick_move_preserves_actual_menu_cell(menu,index): {==}
def L.close_preserves_actual_menu_owner(menu): {==}
