import Base
import ./player_inventory_screen.bend as S
import ./player_inventory.bend as I
import ./inventory.bend as Inv
import ./player_item_definitions.bend as D
import ./player_inventory_screen_laws.bend as L
import ./inventory_proof.bend as TransferProof
import ./inventory_laws.bend as Transfer

def L.event_retains_full_authority(controller,snapshot,catalog,viewport,event,focused,captured): {==}
def L.reply_installs_full_authority(controller,previous,snapshot,catalog,accepted): {==}

def L.focus_loss_composes_without_changing_pending_or_authority(controller):
  match controller:
    case S.State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,hover}: {==}

def L.unadmitted_observation_retains_entire_controller(controller,snapshot): {==}

def L.refused_close_retains_owned_inventory(state): {==}

def L.menu_open_close_changes_only_open_flag(state):
  match state:
    case I.State{inventory,selected,abilities,I.Profile{definitions,status,I.Menu{opened,revision,result}}}: {==}

def L.inventory_authority_refusal_retains_every_owned_slot(state,index,key,count):
  I.refused_acquisition_preserves_inventory(state,index,key,count)

def L.invalid_transfer_retains_every_owned_slot(state,source,destination,count,mode): {==}

def L.production_transfer_count_conservation(requested,source,destination,room):
  Transfer.count_conservation(requested,source,destination,room)

def L.full_offhand_key_requests_hovered_swap(saved,craft,result,revision,catalog,buttons,source,offer,row,query,message,slot,valid):
  %Equal.sym(Bool,I.menu_snapshot_valid(I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision}),True{},valid) : {S.decided(I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog,S.step_checked(_,S.State{True{},0,buttons,False{},True{},source,offer,0,0,row,query,message,S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog,S.Viewport{320,180,960,540},Key{70,True{}},True{},False{})) == S.Decision{S.Frame{S.State{True{},2048,buttons,False{},True{},None{},None{},3,0,row,query,S.Waiting{},S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},[S.MenuClick{slot,I.Swap{40}}],True{}} : S.Decision}
  {==}

def L.full_number_key_requests_hovered_swap(saved,craft,result,revision,catalog,buttons,source,offer,row,query,message,slot,valid):
  %Equal.sym(Bool,I.menu_snapshot_valid(I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision}),True{},valid) : {S.decided(I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog,S.step_checked(_,S.State{True{},0,buttons,False{},True{},source,offer,0,0,row,query,message,S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog,S.Viewport{320,180,960,540},Key{49,True{}},True{},False{})) == S.Decision{S.Frame{S.State{True{},1,buttons,False{},True{},None{},None{},3,0,row,query,S.Waiting{},S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},[S.MenuClick{slot,I.Swap{0}}],True{}} : S.Decision}
  {==}

def L.carried_item_blocks_shortcut_and_retains_full_frame(saved,craft,result,revision,catalog,buttons,source,offer,row,query,message,slot,key,count,valid):
  %Equal.sym(Bool,I.menu_snapshot_valid(I.MenuSnapshot{saved,craft,Inv.InvStack{key,count},result,True{},revision}),True{},valid) : {S.decided(I.MenuSnapshot{saved,craft,Inv.InvStack{key,count},result,True{},revision},catalog,S.step_checked(_,S.State{True{},0,buttons,False{},True{},source,offer,0,0,row,query,message,S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvStack{key,count},result,True{},revision},catalog,S.Viewport{320,180,960,540},Key{70,True{}},True{},False{})) == S.Decision{S.Frame{S.State{True{},2048,buttons,False{},True{},source,offer,0,0,row,query,message,S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvStack{key,count},result,True{},revision},catalog},[],True{}} : S.Decision}
  {==}

def L.resized_viewport_refuses_stale_hover_and_retains_full_frame(saved,craft,result,revision,catalog,buttons,source,offer,row,query,message,slot,valid):
  %Equal.sym(Bool,I.menu_snapshot_valid(I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision}),True{},valid) : {S.decided(I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog,S.step_checked(_,S.State{True{},0,buttons,False{},True{},source,offer,0,0,row,query,message,S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog,S.Viewport{320,180,1920,1080},Key{70,True{}},True{},False{})) == S.Decision{S.Frame{S.State{True{},2048,buttons,False{},True{},source,offer,0,0,row,query,message,S.Outside{}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},[],True{}} : S.Decision}
  {==}

def L.completed_swap_then_held_key_retains_received_authority(saved,craft,result,revision,catalog,buttons,source,offer,row,query,message,slot,previous,valid):
  %Equal.sym(Bool,I.menu_snapshot_valid(I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision}),True{},valid) : {S.decided(I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog,S.step_checked(_,S.State{True{},2048,0,False{},True{},None{},None{},0,0,row,query,S.Ready{},S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog,S.Viewport{320,180,960,540},Key{70,True{}},True{},False{})) == S.Decision{S.Frame{S.State{True{},2048,0,False{},True{},None{},None{},0,0,row,query,S.Ready{},S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},[],True{}} : S.Decision}
  {==}

def L.closed_menu_digit_passes_world_and_retains_full_frame(saved,craft,result,revision,catalog,buttons,source,offer,row,query,message,slot,carried,valid):
  %Equal.sym(Bool,I.menu_snapshot_valid(I.MenuSnapshot{saved,craft,carried,result,False{},revision}),True{},valid) : {S.decided(I.MenuSnapshot{saved,craft,carried,result,False{},revision},catalog,S.step_checked(_,S.State{False{},0,buttons,False{},True{},source,offer,0,3,row,query,message,S.Outside{}},I.MenuSnapshot{saved,craft,carried,result,False{},revision},catalog,S.Viewport{320,180,960,540},Key{57,True{}},True{},False{})) == S.Decision{S.Frame{S.State{False{},256,buttons,False{},True{},source,offer,0,3,row,query,message,S.Outside{}},I.MenuSnapshot{saved,craft,carried,result,False{},revision},catalog},[],False{}} : S.Decision}
  {==}

def L.captured_pointer_releases_controls_and_retains_full_frame(saved,craft,result,revision,catalog,buttons,source,offer,row,query,message,slot,valid):
  %Equal.sym(Bool,I.menu_snapshot_valid(I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision}),True{},valid) : {S.decided(I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog,S.step_checked(_,S.State{True{},0,buttons,False{},True{},source,offer,0,0,row,query,message,S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog,S.Viewport{320,180,960,540},Key{70,True{}},True{},True{})) == S.Decision{S.Frame{S.State{True{},2048,buttons,True{},True{},source,offer,0,0,row,query,message,S.Outside{}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},[S.ReleaseControls{},S.Capture{False{}}],True{}} : S.Decision}
  {==}

def L.pending_swap_refuses_second_request_and_retains_full_frame(saved,craft,result,revision,catalog,buttons,source,offer,row,query,message,slot,valid):
  %Equal.sym(Bool,I.menu_snapshot_valid(I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision}),True{},valid) : {S.decided(I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog,S.step_checked(_,S.State{True{},0,buttons,False{},True{},source,offer,3,0,row,query,message,S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog,S.Viewport{320,180,960,540},Key{70,True{}},True{},False{})) == S.Decision{S.Frame{S.State{True{},2048,buttons,False{},True{},source,offer,3,0,row,query,message,S.AtViewport{320,180,960,540,S.Slot{slot}}},I.MenuSnapshot{saved,craft,Inv.InvEmpty{},result,True{},revision},catalog},[],True{}} : S.Decision}
  {==}

