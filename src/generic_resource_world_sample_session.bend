import Base
import ./generic_resource_world_sample.bend as GS
import ./generic_resource_world_sample_read.bend as Read
import ./local_player_session.bend as S
import ./local_player_runtime.bend as R
import ./local_phase_runtime.bend as X
import ./movement.bend as MV
import ./world_mesh.bend as WM

def eye_result(identity:String,policy:GS.Policy,
    result:X.State & Result<&2,&2,String,MV.Vec3>) -> X.State & Result<&2,&2,String,GS.Sample>:
  (player,status) = result
  match status:
    case Fail{message}: (player,Fail{message})
    case Done{origin}:
      R.query(Result<&2,&2,String,GS.Sample>,player,
        world => Read.snapshot(world,origin,identity,policy))

def player_snapshot(player:X.State,identity:String,policy:GS.Policy) -> X.State & Result<&2,&2,String,GS.Sample>:
  eye_result(identity,policy,R.eye(player))

def session_snapshot(state:S.State,policy:GS.Policy) -> S.State & Result<&2,&2,String,GS.Sample>:
  S.State{player,S.Shell{+identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation}} = state
  S.query(Result<&2,&2,String,GS.Sample>,
    S.State{player,S.Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation}},
    current => player_snapshot(current,identity,policy))

def snapshot_checked(valid:Bool,state:S.State,width:U32,height:U32,policy:GS.Policy) -> S.State & Result<&2,&2,String,GS.Sample>:
  match valid:
    case False{}: (state,Fail{"generic-resource:invalid-frame"})
    case True{}: session_snapshot(state,policy)

# The persisted session's registry identity is already the canonical identity
# admitted on load. Polling reads current Core and pose without advancing it.
def snapshot(state:S.State,+width:U32,+height:U32,policy:GS.Policy) -> S.State & Result<&2,&2,String,GS.Sample>:
  snapshot_checked(WM.frame_valid(WM.frame(width,height)),state,width,height,policy)
