import Base
import ./player_menu_input.bend as M
import ./player_menu_input_laws.bend as L
import ./player_inventory_screen.bend as S
import ./player_inventory.bend as I
import ./player_item_definitions.bend as D

def L.observation_installs_received_full_authority(controller,previous,catalog,snapshot): {==}

def updated_retains_authority(+snapshot:Maybe<&2,I.MenuSnapshot>,+catalog:D.Catalog,result:S.Update) ->
    {M.updated_authority(M.updated(snapshot,catalog,result)) == (snapshot,catalog) : Maybe<&2,I.MenuSnapshot> & D.Catalog}:
  match result:
    case S.Update{controller,intents,consumed}: {==}

def L.synchronization_retains_full_authority(state,focused,captured):
  match state:
    case M.State{controller,None{},catalog}:
      updated_retains_authority(None{},catalog,S.synchronize(controller,focused,captured))
    case M.State{controller,Some{+snapshot},catalog}:
      updated_retains_authority(Some{snapshot},catalog,S.synchronize_authority(controller,snapshot,focused,captured))

def L.event_retains_full_authority(event,events,intents,state,viewport,focused,captured):
  match state:
    case M.State{controller,None{},catalog}: {==}
    case M.State{controller,Some{snapshot},catalog}: {==}

def events_retain_authority(events:List<Event>,+viewport:S.Viewport,+focused:Bool,+captured:Bool,+batch:M.Batch) ->
    {M.batch_authority(M.events(events,viewport,focused,captured,batch)) == M.batch_authority(batch) : Maybe<&2,I.MenuSnapshot> & D.Catalog}:
  match events batch:
    case Nil{} M.Batch{state,intents,reversed}: {==}
    case +head <> tail M.Batch{+state,+intents,+reversed}:
      Equal.trans(Maybe<&2,I.MenuSnapshot> & D.Catalog,
        M.batch_authority(M.events(tail,viewport,focused,captured,M.event(head,reversed,intents,state,viewport,focused,captured))),
        M.batch_authority(M.event(head,reversed,intents,state,viewport,focused,captured)),M.authority(state),
        events_retain_authority(tail,viewport,focused,captured,M.event(head,reversed,intents,state,viewport,focused,captured)),
        L.event_retains_full_authority(head,reversed,intents,state,viewport,focused,captured))

def packet_from_synchronization(+state:M.State,events:List<Event>,viewport:S.Viewport,focused:Bool,captured:Bool,
    result:M.State & List<&2,S.Intent>,
    retained:{M.updated_authority(result) == M.authority(state) : Maybe<&2,I.MenuSnapshot> & D.Catalog}) ->
    {M.batch_authority(M.synchronized(events,viewport,focused,captured,result)) == M.authority(state) : Maybe<&2,I.MenuSnapshot> & D.Catalog}:
  (next,intents) = result
  Equal.trans(Maybe<&2,I.MenuSnapshot> & D.Catalog,
    M.batch_authority(M.events(events,viewport,focused,captured,M.Batch{next,intents,[]})),
    M.authority(next),M.authority(state),
    events_retain_authority(events,viewport,focused,captured,M.Batch{next,intents,[]}),retained)

def L.packet_retains_full_authority(state,events,viewport,focused,captured):
  packet_from_synchronization(state,events,viewport,focused,captured,M.synchronize(state,focused,captured),
    L.synchronization_retains_full_authority(state,focused,captured))

def L.completion_installs_received_full_authority(controller,previous,catalog,snapshot,accepted):
  updated_retains_authority(Some{snapshot},catalog,S.completed(controller,snapshot,accepted))
