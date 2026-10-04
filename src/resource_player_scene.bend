import Base
import ./player_session.bend as S
import ./player_runtime.bend as R
import ./player_scene.bend as P
import ./client_presenter.bend as CP
import ./client_controls.bend as CC
import ./client_world.bend as W
import ./client_render.bend as CR
import ./world_visibility.bend as V
import ./world_resource_frame.bend as F
import ./resource_frame.bend as RF
import ./world_mesh.bend as WM
import ./game.bend as G
import ./registry.bend as B
import ./core.bend as C

# The actor returns immutable visible-cell observations. Textures stay with the
# presenter. No frame query advances the shared simulation clock.
def sampled(value:W.State & Result<&2,&2,V.Error,V.Sample>) -> W.State & Result<&2,&2,String,V.Sample>:
  (world,status) = value
  match status:
    case Fail{error}: (world,Fail{F.visibility_error(error)})
    case Done{frame}: (world,Done{frame})

def world_snapshot(world:W.State) -> W.State & Result<&2,&2,String,V.Sample>:
  sampled(V.sample(world,V.defaults()))

def snapshot_valid(state:S.State,valid:Bool) -> S.State & Result<&2,&2,String,V.Sample>:
  match valid:
    case False{}: (state,Fail{"ResourceScene:Frame"})
    case True{}:
      S.query(Result<&2,&2,String,V.Sample>,state,p => R.query(Result<&2,&2,String,V.Sample>,p,world_snapshot))

def snapshot(state:S.State,width:U32,height:U32) -> S.State & Result<&2,&2,String,V.Sample>:
  snapshot_valid(state,WM.frame_valid(WM.frame(width,height)))

law invalid_frame_preserves_session:
  for state:S.State
  {snapshot_valid(state,False{}) == (state,Fail{"ResourceScene:Frame"}) : S.State & Result<&2,&2,String,V.Sample>}
def invalid_frame_preserves_session(state):
  {==}

def input(state:S.State,packet:CC.Packet) -> S.State & Result<&2,&2,String,Unit>:
  P.input(state,packet)

# This finite scene has no menu yet; the existing presenter observes actual
# capture after each request rather than trusting this scene policy.
def capture_allowed(frame:V.Sample) -> Bool:
  True{}

def presenter_driver() -> CP.Driver<S.State,V.Sample>:
  CP.Driver{snapshot,input,capture_allowed}

def describe(frame:V.Sample) -> String:
  V.Sample{CR.Snapshot{tick,revision,blocks,CR.Camera{x,y,z,yaw,pitch}},raw,masks,origin,palette,reads} = frame
  "{\"event\":\"client.frame\",\"tick\":" ++ Nat.show(tick) ++ ",\"revision\":" ++ Nat.show(revision) ++
    ",\"renderer\":\"resource-visibility-instrument\",\"blocks\":" ++ Nat.show(List.length(&2,CR.Block,blocks)) ++
    ",\"neighbor_reads\":" ++ U32.show(reads) ++ ",\"yaw_f32\":" ++ U32.show(F32.bits(yaw)) ++ ",\"pitch_f32\":" ++ U32.show(F32.bits(pitch)) ++ "}"

def renderer() -> CP.Renderer<V.Sample,RF.Assets>:
  CP.Renderer{F.draw,describe,RF.close_assets}

# Resolve resource state bindings from the actual registry while returning the
# complete existing world View. Loading remains a separate explicit IO step.
def palette_result(value:B.Registry & Result<&2,&2,String,W.Palette>,world:C.World,view:W.View) -> W.State & Result<&2,&2,String,RF.Palette>:
  (registry,status) = value
  match status:
    case Fail{error}: (W.attach(G.Engine{world,registry},view),Fail{error})
    case Done{palette}: (W.attach(G.Engine{world,registry},view),Done{F.resource_palette(palette)})

def world_palette(world:W.State) -> W.State & Result<&2,&2,String,RF.Palette>:
  W.State{G.Engine{core,registry},body,yaw,pitch,palette,region,cache} = world
  palette_result(W.palette_air(W.supported_block(B.Registry.block(registry,"minecraft:air"))),core,W.View{body,yaw,pitch,palette,region,cache})

def resource_palette(state:S.State) -> S.State & Result<&2,&2,String,RF.Palette>:
  S.query(Result<&2,&2,String,RF.Palette>,state,p => R.query(Result<&2,&2,String,RF.Palette>,p,world_palette))
