import Base
import ./remote_resource_backend.bend as B
import ./local_player_session.bend as S
import ./local_player_entity_scene.bend as Scene
import ./remote_entity_frame.bend as Frame
import ./generic_resource_world_sample.bend as GS
import ./core.bend as C
import ./player_crafting_session_adapter.bend as Craft
import ./player_cooking_menu.bend as Cooking

def returned(lease:B.Lease,counter:Nat,nonce:String,capability:String,owner:C.Capability,
    crafting:Maybe<&2,Craft.Context>,cooking:Cooking.Handle,next_cooking_menu:U32,
    result:S.State & Result<&2,&2,String,Frame.Frame>) -> B.State & Result<&2,&2,String,Frame.Frame>:
  (saved,status) = result
  (B.State{saved,B.renewed(lease),counter,nonce,capability,owner,crafting,cooking,next_cooking_menu},status)

def checked(valid:Bool,state:B.State,width:U32,height:U32,policy:GS.Policy,partial:F32) ->
    B.State & Result<&2,&2,String,Frame.Frame>:
  match valid state:
    case False{} _: (state,Fail{"RendererLeaseOrSequence"})
    case True{} B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu}:
      returned(lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu,
        Scene.capture(saved,width,height,policy,partial))

# One lease admission/consumption governs both the world and entity read.
# A denied request does not query or normalize any part of the original owner.
def frame(state:B.State,+epoch:String,+sequence:Nat,width:U32,height:U32,policy:GS.Policy,partial:F32) ->
    B.State & Result<&2,&2,String,Frame.Frame>:
  B.State{saved,+lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu} = state
  checked(B.admitted(lease,epoch,sequence),
    B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu},width,height,policy,partial)
