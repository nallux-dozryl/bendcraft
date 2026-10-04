import Base
import ./generic_resource_world_sample.bend as GS
import ./generic_resource_world_sample_session.bend as Sample
import ./remote_resource_backend.bend as B
import ./local_player_session.bend as S
import ./local_player_scene.bend as Scene
import ./world_mesh.bend as WM
import ./core.bend as C
import ./player_crafting_session_adapter.bend as CS
import ./player_cooking_menu.bend as PCMenu

def ensured(width:U32,height:U32,policy:GS.Policy,result:S.State & Result<&2,&2,String,Unit>) -> S.State & Result<&2,&2,String,GS.Sample>:
  (saved,status) = result
  match status:
    case Fail{message}: (saved,Fail{message})
    case Done{unit}: Sample.snapshot(saved,width,height,policy)

def supported(valid:Bool,saved:S.State,width:U32,height:U32,policy:GS.Policy) -> S.State & Result<&2,&2,String,GS.Sample>:
  match valid:
    case False{}: Sample.snapshot(saved,width,height,policy)
    case True{}: ensured(width,height,policy,Scene.ensure(saved))

def sampled(saved:S.State,+width:U32,+height:U32,policy:GS.Policy) -> S.State & Result<&2,&2,String,GS.Sample>:
  supported(WM.frame_valid(WM.frame(width,height)),saved,width,height,policy)

def returned(lease:B.Lease,counter:Nat,nonce:String,capability:String,owner:C.Capability,crafting:Maybe<&2,CS.Context>,
    cooking:PCMenu.Handle,next_cooking_menu:U32,
    result:S.State & Result<&2,&2,String,GS.Sample>) -> B.State & Result<&2,&2,String,GS.Sample>:
  (saved,status) = result
  (B.State{saved,B.renewed(lease),counter,nonce,capability,owner,crafting,cooking,next_cooking_menu},status)

def checked(valid:Bool,state:B.State,width:U32,height:U32,policy:GS.Policy) -> B.State & Result<&2,&2,String,GS.Sample>:
  match valid state:
    case False{} _: (state,Fail{"RendererLeaseOrSequence"})
    case True{} B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu}:
      returned(lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu,sampled(saved,width,height,policy))

# Same actor lease and expected-sequence admission as the legacy frame path.
def frame(state:B.State,epoch:String,sequence:Nat,width:U32,height:U32,policy:GS.Policy) -> B.State & Result<&2,&2,String,GS.Sample>:
  B.State{saved,+lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu} = state
  checked(B.admitted(lease,epoch,sequence),B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu},width,height,policy)
