import Base
import ./local_player_session.bend as S
import ./local_player_scene.bend as Scene
import ./local_player_runtime.bend as R
import ./local_player_record.bend as Record
import ./player_record.bend as Saved
import ./player_codec.bend as Codec
import ./local_player_cooking_storage.bend as Storage
import ./generic_resource_world_sample.bend as GS
import ./generic_resource_world_sample_session.bend as Sample
import ./remote_entity_frame.bend as Frame
import ./item_entity_render.bend as Render
import ./item_entity_render_model.bend as D
import ./world_mesh.bend as WM
import ./player_look.bend as Look
import ./local_player_cooking_tick_storage.bend as TickStorage
import ./local_player_effect_tick_recovery.bend as TickRecovery

# Only the immutable presentation projection leaves this continuation. The
# real entity/RNG owner and unused constructor clocks remain in the Session.
def projected(value:Maybe<&2,Storage.EntityRecovery>) -> D.Snapshot:
  match value:
    case None{}: D.Unbound{}
    case Some{Storage.EntityRecovery{view,inputs}}: Render.render_snapshot(view)
    case Some{Storage.TickRecovery{TickStorage.Stored{TickRecovery.Recovery{view,runtimes,sound},inputs,membership}}}:
      Render.render_snapshot(view)

def captured(dimension:String,partial:F32,sample:GS.Sample,
    result:S.State & Maybe<&2,Storage.EntityRecovery>) -> S.State & Result<&2,&2,String,Frame.Frame>:
  (state,entities) = result
  (state,Done{Frame.Frame{sample,projected(entities),dimension,partial}})

def sampled(dimension:String,partial:F32,result:S.State & Result<&2,&2,String,GS.Sample>) ->
    S.State & Result<&2,&2,String,Frame.Frame>:
  match result:
    case (state,Fail{message}): (state,Fail{message})
    case (state,Done{sample}): captured(dimension,partial,sample,S.cooking_entities(state))

def dimension(record:Record.Record) -> String:
  Record.Record{Saved.Record{Codec.Snapshot{player,support,yaw,pitch,value},look},
    local,sprinting,pose,minor,history,entity} = record
  value

# The existing sample reader fixes W.position to the Overworld. Refuse another
# profile rather than stamp a different dimension onto those actual cells.
def dimension_checked(valid:Bool,state:S.State,dimension:String,width:U32,height:U32,
    policy:GS.Policy,partial:F32) -> S.State & Result<&2,&2,String,Frame.Frame>:
  match valid:
    case False{}: (state,Fail{"remote-entity:unsupported-sample-dimension"})
    case True{}: sampled(dimension,partial,Sample.snapshot(state,width,height,policy))

def recorded(width:U32,height:U32,policy:GS.Policy,partial:F32,
    result:S.State & Result<&2,&2,String,Record.Record>) -> S.State & Result<&2,&2,String,Frame.Frame>:
  match result:
    case (state,Fail{message}): (state,Fail{message})
    case (state,Done{record}):
      +actual = dimension(record)
      dimension_checked(String.eq(actual,"minecraft:overworld"),state,actual,width,height,policy,partial)

def ensured(width:U32,height:U32,policy:GS.Policy,partial:F32,
    result:S.State & Result<&2,&2,String,Unit>) -> S.State & Result<&2,&2,String,Frame.Frame>:
  match result:
    case (state,Fail{message}): (state,Fail{message})
    case (state,Done{unit}):
      recorded(width,height,policy,partial,S.query(Result<&2,&2,String,Record.Record>,state,R.record_checked))

def partial_valid(+partial:F32) -> Bool:
  Look.finite(partial) && F32.is_ge(partial,0.0) && F32.is_le(partial,1.0)

def partial_checked(valid:Bool,state:S.State,width:U32,height:U32,policy:GS.Policy,partial:F32) ->
    S.State & Result<&2,&2,String,Frame.Frame>:
  match valid:
    case False{}: (state,Fail{"remote-entity:invalid-partial"})
    case True{}: ensured(width,height,policy,partial,Scene.ensure(state))

def frame_checked(valid:Bool,state:S.State,width:U32,height:U32,policy:GS.Policy,+partial:F32) ->
    S.State & Result<&2,&2,String,Frame.Frame>:
  match valid:
    case False{}: (state,Fail{"generic-resource:invalid-frame"})
    case True{}: partial_checked(partial_valid(partial),state,width,height,policy,partial)

# One synchronous actor continuation reads the world sample and the actual
# entity owner. Neither subquery ticks Core or enters IO, so there is no pulse
# between them. GS.Sample contains the same Core tick/revision and pose-aware
# F64 origin/camera used by the entity frame; partial is one validated supplied
# render fraction, not an invented server clock observation.
def capture(state:S.State,+width:U32,+height:U32,policy:GS.Policy,partial:F32) ->
    S.State & Result<&2,&2,String,Frame.Frame>:
  frame_checked(WM.frame_valid(WM.frame(width,height)),state,width,height,policy,partial)
