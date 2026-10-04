import Base
import ./player_crafting_backend_laws.bend as Laws
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

def Laws.denied_crafting_request_retains_complete_actor(state,request):
  match state:
    case B.State{saved,lease,counter,nonce,capability,owner,crafting}: {==}

def Laws.denied_menu_observation_retains_complete_actor(state):
  match state:
    case B.State{saved,lease,counter,nonce,capability,owner,crafting}: {==}

def Laws.denied_physical_packet_retains_complete_actor_before_release(state,packet):
  match state:
    case B.State{saved,lease,counter,nonce,capability,owner,crafting}: {==}

def Laws.inadmissible_crafting_request_retains_complete_actor(saved,lease,counter,nonce,capability,owner,crafting,epoch,sequence,request,denied):
  %Equal.sym(Bool,B.admitted(lease,epoch,sequence),False{},denied) :
    {B.crafting_checked(B.State{saved,lease,counter,nonce,capability,owner,crafting},request,_) == (B.State{saved,lease,counter,nonce,capability,owner,crafting},Fail{"RendererLeaseOrSequence"}) : B.State & Result<&2,&2,String,B.MenuOutcome>}
  {==}

def Laws.inadmissible_menu_open_retains_complete_actor(saved,lease,counter,nonce,capability,owner,crafting,epoch,sequence,denied):
  %Equal.sym(Bool,B.admitted(lease,epoch,sequence),False{},denied) :
    {B.crafting_checked(B.State{saved,lease,counter,nonce,capability,owner,crafting},CS.CraftOpen{},_) == (B.State{saved,lease,counter,nonce,capability,owner,crafting},Fail{"RendererLeaseOrSequence"}) : B.State & Result<&2,&2,String,B.MenuOutcome>}
  {==}

def Laws.inadmissible_menu_close_retains_complete_actor(saved,lease,counter,nonce,capability,owner,crafting,epoch,sequence,denied):
  %Equal.sym(Bool,B.admitted(lease,epoch,sequence),False{},denied) :
    {B.crafting_checked(B.State{saved,lease,counter,nonce,capability,owner,crafting},CS.CraftClose{},_) == (B.State{saved,lease,counter,nonce,capability,owner,crafting},Fail{"RendererLeaseOrSequence"}) : B.State & Result<&2,&2,String,B.MenuOutcome>}
  {==}

def Laws.inadmissible_result_click_retains_complete_actor(saved,lease,counter,nonce,capability,owner,crafting,epoch,sequence,index,click,denied):
  %Equal.sym(Bool,B.admitted(lease,epoch,sequence),False{},denied) :
    {B.crafting_checked(B.State{saved,lease,counter,nonce,capability,owner,crafting},CS.CraftClick{index,click},_) == (B.State{saved,lease,counter,nonce,capability,owner,crafting},Fail{"RendererLeaseOrSequence"}) : B.State & Result<&2,&2,String,B.MenuOutcome>}
  {==}

def Laws.inadmissible_menu_inspect_retains_complete_actor(saved,lease,counter,nonce,capability,owner,crafting,epoch,sequence,denied):
  %Equal.sym(Bool,B.admitted(lease,epoch,sequence),False{},denied) :
    {B.menu_inspect_checked(B.State{saved,lease,counter,nonce,capability,owner,crafting},_) == (B.State{saved,lease,counter,nonce,capability,owner,crafting},Fail{"RendererLeaseOrSequence"}) : B.State & Result<&2,&2,String,B.MenuOutcome>}
  {==}

def Laws.public_dispatch_rejoins_complete_session_and_context(saved,lease,counter,nonce,capability,owner,crafting,session,value):
  {==}

def Laws.committed_craft_with_failed_refresh_stays_accepted(saved,context,lease,counter,nonce,capability,owner,message,snapshot,grid,taken):
  {==}
