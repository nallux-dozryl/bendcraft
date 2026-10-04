import Base
import ./inventory_key_consumer.bend as K
import ./inventory_key_consumer_laws.bend as L
import ./player_menu_input.bend as M
import ./player_menu_input_laws.bend as ML
import ./player_menu_input_proof.bend as MP
import ./player_inventory_screen.bend as S
import ./player_inventory.bend as I
import ./inventory.bend as Inv
import ./player_inventory_screen_laws.bend as SL
import ./player_inventory_screen_proof.bend as SP
import ./player_item_definitions.bend as D

def mapped_retains_authority(mapped:Maybe<&2,Event>,events:List<&2,Event>,intents:List<&2,S.Intent>,+state:M.State,
    viewport:S.Viewport,focused:Bool,captured:Bool) ->
    {M.batch_authority(M.key_event_mapped(mapped,events,intents,state,viewport,focused,captured)) == M.authority(state) : Maybe<&2,I.MenuSnapshot> & D.Catalog}:
  match mapped:
    case None{}: {==}
    case Some{input}: ML.event_retains_full_authority(input,events,intents,state,viewport,focused,captured)

def key_retains_authority(profile:K.Profile,input:Event,events:List<&2,Event>,intents:List<&2,S.Intent>,+state:M.State,
    viewport:S.Viewport,focused:Bool,captured:Bool) ->
    {M.batch_authority(M.key_event(profile,input,events,intents,state,viewport,focused,captured)) == M.authority(state) : Maybe<&2,I.MenuSnapshot> & D.Catalog}:
  M.State{controller,snapshot,catalog} = state
  mapped_retains_authority(K.event(profile,controller,input),events,intents,state,viewport,focused,captured)

def keys_retain_authority(left:Nat,pending:List<&2,Event>,+profile:K.Profile,+viewport:S.Viewport,+focused:Bool,+captured:Bool,+batch:M.Batch) ->
    {M.batch_authority(M.key_events_go(left,pending,profile,viewport,focused,captured,batch)) == M.batch_authority(batch) : Maybe<&2,I.MenuSnapshot> & D.Catalog}:
  match left pending batch:
    case 0n Nil{} M.Batch{state,intents,reversed}: {==}
    case 0n head <> tail M.Batch{state,intents,reversed}: {==}
    case 1n+n Nil{} M.Batch{state,intents,reversed}: {==}
    case 1n+n +head <> tail M.Batch{M.State{+controller,+snapshot,+catalog},+intents,+reversed}:
      Equal.trans(Maybe<&2,I.MenuSnapshot> & D.Catalog,
        M.batch_authority(M.key_events_go(n,K.following(profile,controller,head,tail),profile,viewport,focused,captured,M.key_event(profile,head,reversed,intents,M.State{controller,snapshot,catalog},viewport,focused,captured))),
        M.batch_authority(M.key_event(profile,head,reversed,intents,M.State{controller,snapshot,catalog},viewport,focused,captured)),
        (snapshot,catalog),
        keys_retain_authority(n,K.following(profile,controller,head,tail),profile,viewport,focused,captured,M.key_event(profile,head,reversed,intents,M.State{controller,snapshot,catalog},viewport,focused,captured)),
        key_retains_authority(profile,head,reversed,intents,M.State{controller,snapshot,catalog},viewport,focused,captured))

def packet_retains_authority(profile:K.Profile,+state:M.State,pending:List<Event>,viewport:S.Viewport,focused:Bool,captured:Bool,
    result:M.State & List<&2,S.Intent>,
    retained:{M.updated_authority(result) == M.authority(state) : Maybe<&2,I.MenuSnapshot> & D.Catalog}) ->
    {M.batch_authority(M.key_synchronized(profile,pending,viewport,focused,captured,result)) == M.authority(state) : Maybe<&2,I.MenuSnapshot> & D.Catalog}:
  (next,intents) = result
  +pending = M.shared_events(pending)
  Equal.trans(Maybe<&2,I.MenuSnapshot> & D.Catalog,
    M.batch_authority(M.key_events_go(List.length(&2,Event,pending),pending,profile,viewport,focused,captured,M.Batch{next,intents,[]})),
    M.authority(next),M.authority(state),
    keys_retain_authority(List.length(&2,Event,pending),pending,profile,viewport,focused,captured,M.Batch{next,intents,[]}),retained)

def L.physical_packet_retains_complete_received_authority(state,profile,pending,viewport,focused,captured):
  packet_retains_authority(profile,state,pending,viewport,focused,captured,M.synchronize(state,focused,captured),ML.synchronization_retains_full_authority(state,focused,captured))

def L.unavailable_native_channel_keeps_actual_legacy_packet(state,profile,pending,viewport,focused,captured): {==}
def L.default_physical_profile_is_valid(): {==}

def L.physical_offhand_consumes_paired_character_and_retains_full_owner(saved,craft,result,revision,catalog,buttons,source,offer,row,query,message,slot,valid):
  Equal.cong(S.Decision,M.Batch,decision => M.finished(M.decided(Key{70,True{}},[],[],decision)),S.step_frame(S.Frame{S.State{True{},0,buttons,False{},True{},source,offer,0,0,row,query,message,S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},S.Viewport{320,180,960,540},Key{70,True{}},True{},False{}),S.Decision{S.Frame{S.State{True{},2048,buttons,False{},True{},None{},None{},3,0,row,query,S.Waiting{},S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},[S.MenuClick{slot,I.Swap{40}}],True{}},SL.full_offhand_key_requests_hovered_swap(saved,craft,result,revision,catalog,buttons,source,offer,row,query,message,slot,valid))

def L.rebound_offhand_requests_actual_full_owner_swap(saved,craft,result,revision,catalog,slot,valid):
  Equal.cong(S.Decision,M.Batch,decision => M.decided(Key{70,True{}},[],[],decision),S.step_frame(S.Frame{S.State{True{},0,0,False{},True{},None{},None{},0,0,0,"",S.Ready{},S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},S.Viewport{320,180,960,540},Key{70,True{}},True{},False{}),S.Decision{S.Frame{S.State{True{},2048,0,False{},True{},None{},None{},3,0,0,"",S.Waiting{},S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},[S.MenuClick{slot,I.Swap{40}}],True{}},SL.full_offhand_key_requests_hovered_swap(saved,craft,result,revision,catalog,0,None{},None{},0,"",S.Ready{},slot,valid))

def L.physical_world_digit_keeps_single_semantic_event_and_full_owner(saved,craft,carried,result,revision,catalog,valid):
  Equal.cong(S.Decision,M.Batch,decision => M.finished(M.decided(Key{57,True{}},[],[],decision)),S.step_frame(S.Frame{S.State{False{},0,0,False{},True{},None{},None{},0,3,0,"",S.Ready{},S.Outside{}},I.MenuSnapshot{saved,craft,carried,result,False{},revision},catalog},S.Viewport{320,180,960,540},Key{57,True{}},True{},False{}),S.Decision{S.Frame{S.State{False{},256,0,False{},True{},None{},None{},0,3,0,"",S.Ready{},S.Outside{}},I.MenuSnapshot{saved,craft,carried,result,False{},revision},catalog},[],False{}},SL.closed_menu_digit_passes_world_and_retains_full_frame(saved,craft,result,revision,catalog,0,None{},None{},0,"",S.Ready{},0,carried,valid))

def L.searching_retains_actual_character_instead_of_physical_shortcut(saved,craft,carried,result,revision,catalog,valid):
  %Equal.sym(Bool,I.menu_snapshot_valid(I.MenuSnapshot{saved,craft,carried,result,True{},revision}),True{},valid) : {M.finished(M.decided(Key{113,True{}},[],[],S.decided(I.MenuSnapshot{saved,craft,carried,result,True{},revision},catalog,S.step_checked(_,S.State{True{},0,0,False{},True{},None{},None{},0,3,0,"",S.Ready{},S.Outside{}},I.MenuSnapshot{saved,craft,carried,result,True{},revision},catalog,S.Viewport{320,180,960,540},Key{113,True{}},True{},False{})))) == M.Batch{M.State{S.State{True{},0,0,False{},True{},None{},None{},0,3,0,"q",S.Ready{},S.Outside{}},Some{I.MenuSnapshot{saved,craft,carried,result,True{},revision}},catalog},[],[]} : M.Batch}
  {==}
