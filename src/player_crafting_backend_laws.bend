import Base
import ./remote_resource_backend.bend as B
import ./local_player_session.bend as S
import ./player_crafting_session_adapter.bend as CS
import ./player_crafting_authority_menu.bend as Menu
import ./player_inventory.bend as I
import ./inventory.bend as Inv
import ./core.bend as C
import ./client_controls.bend as CC
import ./live.bend as L
import ./json.bend as J
import ./crafting_recipe.bend as R
import ./player_cooking_menu.bend as PCMenu

# These equations retain the actual complete actor: its original Session world,
# inventory Arrays, File lease, recursive runtime owners, private lease fields,
# player capability, immutable recipe context and cooking menu metadata.
law denied_crafting_request_retains_complete_actor:
  for state:B.State
  for request:CS.Request
  {B.crafting_checked(state,request,False{}) == (state,Fail{"RendererLeaseOrSequence"}) : B.State & Result<&2,&2,String,B.MenuOutcome>}

law denied_menu_observation_retains_complete_actor:
  for state:B.State
  {B.menu_inspect_checked(state,False{}) == (state,Fail{"RendererLeaseOrSequence"}) : B.State & Result<&2,&2,String,B.MenuOutcome>}

law denied_physical_packet_retains_complete_actor_before_release:
  for state:B.State
  for packet:CC.Packet
  {B.input_checked(state,packet,False{}) == (state,Fail{"RendererLeaseOrSequence"}) : B.State & Result<&2,&2,String,Unit>}

law inadmissible_crafting_request_retains_complete_actor:
  for saved:S.State
  for +lease:B.Lease
  for counter:Nat
  for nonce:String
  for capability:String
  for owner:C.Capability
  for crafting:Maybe<&2,CS.Context>
  for cooking:PCMenu.Handle
  for next_cooking_menu:U32
  for +epoch:String
  for +sequence:Nat
  for request:CS.Request
  for denied:{B.admitted(lease,epoch,sequence) == False{} : Bool}
  {B.crafting_menu(B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu},epoch,sequence,request) == (B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu},Fail{"RendererLeaseOrSequence"}) : B.State & Result<&2,&2,String,B.MenuOutcome>}

law inadmissible_menu_open_retains_complete_actor:
  for saved:S.State
  for +lease:B.Lease
  for counter:Nat
  for nonce:String
  for capability:String
  for owner:C.Capability
  for crafting:Maybe<&2,CS.Context>
  for cooking:PCMenu.Handle
  for next_cooking_menu:U32
  for +epoch:String
  for +sequence:Nat
  for denied:{B.admitted(lease,epoch,sequence) == False{} : Bool}
  {B.menu_open(B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu},epoch,sequence) == (B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu},Fail{"RendererLeaseOrSequence"}) : B.State & Result<&2,&2,String,B.MenuOutcome>}

law inadmissible_menu_close_retains_complete_actor:
  for saved:S.State
  for +lease:B.Lease
  for counter:Nat
  for nonce:String
  for capability:String
  for owner:C.Capability
  for crafting:Maybe<&2,CS.Context>
  for cooking:PCMenu.Handle
  for next_cooking_menu:U32
  for +epoch:String
  for +sequence:Nat
  for denied:{B.admitted(lease,epoch,sequence) == False{} : Bool}
  {B.menu_close(B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu},epoch,sequence) == (B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu},Fail{"RendererLeaseOrSequence"}) : B.State & Result<&2,&2,String,B.MenuOutcome>}

law inadmissible_result_click_retains_complete_actor:
  for saved:S.State
  for +lease:B.Lease
  for counter:Nat
  for nonce:String
  for capability:String
  for owner:C.Capability
  for crafting:Maybe<&2,CS.Context>
  for cooking:PCMenu.Handle
  for next_cooking_menu:U32
  for +epoch:String
  for +sequence:Nat
  for index:U32
  for click:I.Click
  for denied:{B.admitted(lease,epoch,sequence) == False{} : Bool}
  {B.menu_click(B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu},epoch,sequence,index,click) == (B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu},Fail{"RendererLeaseOrSequence"}) : B.State & Result<&2,&2,String,B.MenuOutcome>}

law inadmissible_menu_inspect_retains_complete_actor:
  for saved:S.State
  for +lease:B.Lease
  for counter:Nat
  for nonce:String
  for capability:String
  for owner:C.Capability
  for crafting:Maybe<&2,CS.Context>
  for cooking:PCMenu.Handle
  for next_cooking_menu:U32
  for +epoch:String
  for +sequence:Nat
  for denied:{B.admitted(lease,epoch,sequence) == False{} : Bool}
  {B.menu_inspect(B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu},epoch,sequence) == (B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu},Fail{"RendererLeaseOrSequence"}) : B.State & Result<&2,&2,String,B.MenuOutcome>}

law public_dispatch_rejoins_complete_session_and_context:
  for saved:S.State
  for lease:B.Lease
  for counter:Nat
  for nonce:String
  for capability:String
  for owner:C.Capability
  for crafting:Maybe<&2,CS.Context>
  for cooking:PCMenu.Handle
  for next_cooking_menu:U32
  for session:L.Session
  for value:J.Value
  {B.dispatched(lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu,(saved,session,value)) ==
    (B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu},session,value) : B.State & L.Session & J.Value}

# A cache-refresh failure after a committed take must not turn the reply into
# a refusal. The exact committed Session and returned Context remain the actor.
law committed_craft_with_failed_refresh_stays_accepted:
  for saved:S.State
  for context:CS.Context
  for lease:B.Lease
  for counter:Nat
  for nonce:String
  for capability:String
  for owner:C.Capability
  for cooking:PCMenu.Handle
  for next_cooking_menu:U32
  for message:String
  for snapshot:I.MenuSnapshot
  for grid:R.Grid
  for taken:Inv.Slot
  {B.crafting_reported(lease,counter,nonce,capability,owner,cooking,next_cooking_menu,(saved,context,Menu.Reply{True{},message,snapshot,grid,taken,False{}})) ==
    (B.State{saved,B.renewed(lease),counter,nonce,capability,owner,Some{context},cooking,next_cooking_menu},Done{B.MenuOutcome{True{},message,snapshot}}) : B.State & Result<&2,&2,String,B.MenuOutcome>}
