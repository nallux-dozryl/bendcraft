import Base
import ./inventory_key_consumer.bend as K
import ./player_menu_input.bend as M
import ./player_inventory_screen.bend as S
import ./player_inventory.bend as I
import ./inventory.bend as Inv
import ./player_item_definitions.bend as D

# The actual native packet/controller join retains the entire received actor
# authority and catalog for every input, profile, focus and capture state.
law physical_packet_retains_complete_received_authority:
  for +state:M.State
  for profile:K.Profile
  for pending:List<Event>
  for viewport:S.Viewport
  for +focused:Bool
  for +captured:Bool
  {M.batch_authority(M.packet_keys(True{},profile,state,pending,viewport,focused,captured)) == M.authority(state) : Maybe<&2,I.MenuSnapshot> & D.Catalog}

law unavailable_native_channel_keeps_actual_legacy_packet:
  for state:M.State
  for profile:K.Profile
  for pending:List<Event>
  for viewport:S.Viewport
  for focused:Bool
  for captured:Bool
  {M.packet_keys(False{},profile,state,pending,viewport,focused,captured) == M.packet(state,pending,viewport,focused,captured) : M.Batch}

law default_physical_profile_is_valid:
  {K.valid(K.defaults()) == True{} : Bool}

# A different character layout cannot turn the same physical F into a world
# key. This equation binds the production event adapter, controller, complete
# arbitrary authority, and the exact typed click; the paired q is consumed.
law physical_offhand_consumes_paired_character_and_retains_full_owner:
  for +saved:I.Persisted
  for +craft:List<&2,Inv.Slot>
  for +result:Maybe<&2,Inv.Slot>
  for +revision:Nat
  for +catalog:D.Catalog
  for +buttons:U32
  for +source:Maybe<&2,U32>
  for +offer:Maybe<&2,D.Definition>
  for +row:U32
  for +query:String
  for +message:S.Notice
  for +slot:U32
  for valid:{I.menu_snapshot_valid(I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision}) == True{} : Bool}
  {M.key_events_shared([Key{2147549187,True{}},Key{113,True{}}],K.defaults(),S.Viewport{320,180,960,540},True{},False{},
    M.Batch{M.State{S.State{True{},0,buttons,False{},True{},source,offer,0,0,row,query,message,S.AtViewport{320,180,960,540,S.Slot{slot}}},Some{I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision}},catalog},[],[]}) ==
    M.Batch{M.State{S.State{True{},2048,buttons,False{},True{},None{},None{},3,0,row,query,S.Waiting{},S.AtViewport{320,180,960,540,S.Slot{slot}}},Some{I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision}},catalog},[S.MenuClick{slot,I.Swap{40}}],[]} : M.Batch}

law rebound_offhand_requests_actual_full_owner_swap:
  for +saved:I.Persisted
  for +craft:List<&2,Inv.Slot>
  for +result:Maybe<&2,Inv.Slot>
  for +revision:Nat
  for +catalog:D.Catalog
  for +slot:U32
  for valid:{I.menu_snapshot_valid(I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision}) == True{} : Bool}
  {M.key_event(K.Profile{[None{},None{},None{},None{},None{},None{},None{},None{},None{}],Some{12},None{},None{}},Key{2147483660,True{}},[],[],
    M.State{S.State{True{},0,0,False{},True{},None{},None{},0,0,0,"",S.Ready{},S.AtViewport{320,180,960,540,S.Slot{slot}}},Some{I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision}},catalog},S.Viewport{320,180,960,540},True{},False{}) ==
    M.Batch{M.State{S.State{True{},2048,0,False{},True{},None{},None{},3,0,0,"",S.Waiting{},S.AtViewport{320,180,960,540,S.Slot{slot}}},Some{I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision}},catalog},[S.MenuClick{slot,I.Swap{40}}],[]} : M.Batch}

law physical_world_digit_keeps_single_semantic_event_and_full_owner:
  for +saved:I.Persisted
  for +craft:List<&2,Inv.Slot>
  for +carried:Inv.Slot
  for +result:Maybe<&2,Inv.Slot>
  for +revision:Nat
  for +catalog:D.Catalog
  for valid:{I.menu_snapshot_valid(I.MenuSnapshot{saved,craft,carried,result,False{},revision}) == True{} : Bool}
  {M.key_events_shared([Key{2147549209,True{}},Key{119,True{}}],K.defaults(),S.Viewport{320,180,960,540},True{},False{},
    M.Batch{M.State{S.State{False{},0,0,False{},True{},None{},None{},0,3,0,"",S.Ready{},S.Outside{}},Some{I.MenuSnapshot{saved,craft,carried,result,False{},revision}},catalog},[],[]}) ==
    M.Batch{M.State{S.State{False{},256,0,False{},True{},None{},None{},0,3,0,"",S.Ready{},S.Outside{}},Some{I.MenuSnapshot{saved,craft,carried,result,False{},revision}},catalog},[],[Key{57,True{}}]} : M.Batch}

law searching_retains_actual_character_instead_of_physical_shortcut:
  for +saved:I.Persisted
  for +craft:List<&2,Inv.Slot>
  for +carried:Inv.Slot
  for +result:Maybe<&2,Inv.Slot>
  for +revision:Nat
  for +catalog:D.Catalog
  for valid:{I.menu_snapshot_valid(I.MenuSnapshot{saved,craft,carried,result,True{},revision}) == True{} : Bool}
  {M.key_events_shared([Key{2147549187,True{}},Key{113,True{}}],K.defaults(),S.Viewport{320,180,960,540},True{},False{},
    M.Batch{M.State{S.State{True{},0,0,False{},True{},None{},None{},0,3,0,"",S.Ready{},S.Outside{}},Some{I.MenuSnapshot{saved,craft,carried,result,True{},revision}},catalog},[],[]}) ==
    M.Batch{M.State{S.State{True{},0,0,False{},True{},None{},None{},0,3,0,"q",S.Ready{},S.Outside{}},Some{I.MenuSnapshot{saved,craft,carried,result,True{},revision}},catalog},[],[]} : M.Batch}
