import Base
import ./player_inventory_screen.bend as S
import ./player_inventory.bend as I
import ./player_item_definitions.bend as D
import ./inventory.bend as Inv
import ./inventory_laws.bend as Transfer

# Complete authority: all43 durable slots, all4 crafting inputs, carried,
# result availability/value, all saved ability fields, selected and revision.
# These equations bind the actual production event and reply entry points.
law event_retains_full_authority:
  for controller:S.State
  for +snapshot:I.MenuSnapshot
  for +catalog:D.Catalog
  for viewport:S.Viewport
  for event:Event
  for focused:Bool
  for captured:Bool
  {S.authority(S.decision_frame(S.step_frame(S.Frame{controller,snapshot,catalog},viewport,event,focused,captured))) == (snapshot,catalog) : I.MenuSnapshot & D.Catalog}

law reply_installs_full_authority:
  for controller:S.State
  for previous:I.MenuSnapshot
  for +snapshot:I.MenuSnapshot
  for +catalog:D.Catalog
  for accepted:Bool
  {S.authority(S.decision_frame(S.acknowledge(S.Frame{controller,previous,catalog},snapshot,accepted))) == (snapshot,catalog) : I.MenuSnapshot & D.Catalog}

law focus_loss_composes_without_changing_pending_or_authority:
  for +controller:S.State
  {S.controller(S.focus_lost(S.controller(S.focus_lost(controller)))) == S.controller(S.focus_lost(controller)) : S.State}

# The actual observation gate refuses updates while a request is pending,
# unfocused, or structurally invalid; every latch/reference/request survives.
law unadmitted_observation_retains_entire_controller:
  for controller:S.State
  for snapshot:I.MenuSnapshot
  {S.observed_checked(False{},controller,snapshot) == controller : S.State}

law refused_close_retains_owned_inventory:
  for state:I.State
  {I.close_checked(False{},state) == (state,Fail{"menu retains carried or crafting items; return/drop authority is required before closing"}) : I.State & Result<&2,&2,String,Unit>}

law menu_open_close_changes_only_open_flag:
  for state:I.State
  {I.menu_set(I.menu_set(state,True{}),False{}) == I.menu_set(state,False{}) : I.State}

law inventory_authority_refusal_retains_every_owned_slot:
  for state:I.State
  for index:U32
  for key:Inv.ItemKey
  for count:U32
  {I.acquire_checked(state,index,key,count,False{}) == (state,Fail{"creative acquisition requires player instabuild ability"}) : I.State & Result<&2,&2,String,Unit>}

law invalid_transfer_retains_every_owned_slot:
  for state:I.State
  for source:U32
  for destination:U32
  for count:U32
  for mode:Inv.TransferMode
  {I.transfer_guard(False{},state,source,destination,count,mode) == (state,Inv.InvRejected{Inv.InvBounds{}}) : I.State & Inv.TransferStatus}

# Successful transfer count conservation is discharged by the existing actual
# Inv.move_counts kernel proof, reused by menu_transfer_guard/transfer_read.
# No independent menu arithmetic or axiom is introduced here.
law production_transfer_count_conservation:
  for +requested:Nat
  for +source:Nat
  for +destination:Nat
  for room:Nat
  {Inv.count_total(Inv.move_counts(requested,source,destination,room)) == Nat.add(source,destination) : Nat}

# These equations reduce complete step_frame through its actual shared invariant
# gate. All saved/crafting/result/status/catalog and controller fields are
# quantified; the proof introduces no projected controller or inventory model.
law full_offhand_key_requests_hovered_swap:
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
  {S.step_frame(S.Frame{S.State{True{},0,buttons,False{},True{},source,offer,0,0,row,query,message,S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},S.Viewport{320,180,960,540},Key{70,True{}},True{},False{}) ==
    S.Decision{S.Frame{S.State{True{},2048,buttons,False{},True{},None{},None{},3,0,row,query,S.Waiting{},S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},[S.MenuClick{slot,I.Swap{40}}],True{}} : S.Decision}

law full_number_key_requests_hovered_swap:
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
  {S.step_frame(S.Frame{S.State{True{},0,buttons,False{},True{},source,offer,0,0,row,query,message,S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},S.Viewport{320,180,960,540},Key{49,True{}},True{},False{}) ==
    S.Decision{S.Frame{S.State{True{},1,buttons,False{},True{},None{},None{},3,0,row,query,S.Waiting{},S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},[S.MenuClick{slot,I.Swap{0}}],True{}} : S.Decision}

law carried_item_blocks_shortcut_and_retains_full_frame:
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
  for +key:Inv.ItemKey
  for +count:U32
  for valid:{I.menu_snapshot_valid(I.MenuSnapshot{saved,craft,Inv.InvStack{key,count},result,True{},revision}) == True{} : Bool}
  {S.step_frame(S.Frame{S.State{True{},0,buttons,False{},True{},source,offer,0,0,row,query,message,S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvStack{key,count},result,True{},revision},catalog},S.Viewport{320,180,960,540},Key{70,True{}},True{},False{}) ==
    S.Decision{S.Frame{S.State{True{},2048,buttons,False{},True{},source,offer,0,0,row,query,message,S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvStack{key,count},result,True{},revision},catalog},[],True{}} : S.Decision}

law resized_viewport_refuses_stale_hover_and_retains_full_frame:
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
  {S.step_frame(S.Frame{S.State{True{},0,buttons,False{},True{},source,offer,0,0,row,query,message,S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},S.Viewport{320,180,1920,1080},Key{70,True{}},True{},False{}) ==
    S.Decision{S.Frame{S.State{True{},2048,buttons,False{},True{},source,offer,0,0,row,query,message,S.Outside{}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},[],True{}} : S.Decision}

law completed_swap_then_held_key_retains_received_authority:
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
  for +previous:I.MenuSnapshot
  for valid:{I.menu_snapshot_valid(I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision}) == True{} : Bool}
  {S.step_frame(S.decision_frame(S.acknowledge(S.Frame{S.State{True{},2048,buttons,False{},True{},source,offer,3,0,row,query,message,S.AtViewport{320,180,960,540,S.Slot{slot}}},previous,catalog},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},True{})),S.Viewport{320,180,960,540},Key{70,True{}},True{},False{}) ==
    S.Decision{S.Frame{S.State{True{},2048,0,False{},True{},None{},None{},0,0,row,query,S.Ready{},S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},[],True{}} : S.Decision}

law closed_menu_digit_passes_world_and_retains_full_frame:
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
  for +carried:Inv.Slot
  for valid:{I.menu_snapshot_valid(I.MenuSnapshot{saved,craft,carried,result,False{},revision}) == True{} : Bool}
  {S.step_frame(S.Frame{S.State{False{},0,buttons,False{},True{},source,offer,0,3,row,query,message,S.Outside{}},I.MenuSnapshot{saved,craft,carried,result,False{},revision},catalog},S.Viewport{320,180,960,540},Key{57,True{}},True{},False{}) ==
    S.Decision{S.Frame{S.State{False{},256,buttons,False{},True{},source,offer,0,3,row,query,message,S.Outside{}},I.MenuSnapshot{saved,craft,carried,result,False{},revision},catalog},[],False{}} : S.Decision}


law captured_pointer_releases_controls_and_retains_full_frame:
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
  {S.step_frame(S.Frame{S.State{True{},0,buttons,False{},True{},source,offer,0,0,row,query,message,S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},S.Viewport{320,180,960,540},Key{70,True{}},True{},True{}) ==
    S.Decision{S.Frame{S.State{True{},2048,buttons,True{},True{},source,offer,0,0,row,query,message,S.Outside{}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},[S.ReleaseControls{},S.Capture{False{}}],True{}} : S.Decision}

law pending_swap_refuses_second_request_and_retains_full_frame:
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
  {S.step_frame(S.Frame{S.State{True{},0,buttons,False{},True{},source,offer,3,0,row,query,message,S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},S.Viewport{320,180,960,540},Key{70,True{}},True{},False{}) ==
    S.Decision{S.Frame{S.State{True{},2048,buttons,False{},True{},source,offer,3,0,row,query,message,S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},[],True{}} : S.Decision}

