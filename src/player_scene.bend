import Base
import ./player_session.bend as S
import ./player_runtime.bend as R
import ./player_tick.bend as P
import ./player_input.bend as I
import ./client_controls.bend as CC
import ./support.bend as SP
import ./support_world.bend as SW
import ./travel.bend as T
import ./movement.bend as M
import ./f64.bend as F
import ./client_world.bend as W
import ./persistent_client_world.bend as PW
import ./client_render.bend as CR
import ./client_presenter.bend as CP
import ./game.bend as G
import ./core.bend as C
import ./live.bend as L
import ./json.bend as J

# An explicit finite integration instrument. These exact double attributes are
# the independently observed plain Player test profile, not LocalPlayer defaults.
def context_value(yaw:F32,buttons:I.Buttons,sample:SW.Sample) -> P.Context:
  I.Buttons{forward,backward,left,right,jump,shift,sprint} = buttons
  SW.Sample{ground,factor} = sample
  P.Context{T.Context{ground,T.Attributes{F.F64{1069128089,2576980378},F.F64{1068792545,1202590843},F.from_u32(1),F.from_u32(1)},yaw,0.6,sprint,False{},False{},T.NeutralDryAir{}},F.F64{1071309127,2920577761},factor,True{},P.Neutral{}}

def sampled(yaw:F32,buttons:I.Buttons,result:W.State & Result<&2,&2,SW.Error,SW.Sample>) -> W.State & Result<&2,&2,String,P.Context>:
  (world,status) = result
  match status:
    case Fail{cause}: (world,Fail{SW.error_text(cause)})
    case Done{sample}: (world,Done{context_value(yaw,buttons,sample)})

def context(world:W.State,support:SP.State,buttons:I.Buttons,yaw:F32) -> W.State & Result<&2,&2,String,P.Context>:
  sampled(yaw,buttons,SW.sample_checked(world,support))

def supported(result:W.State & Result<&2,&2,SW.Error,SP.State>) -> W.State & Result<&2,&2,String,SP.State>:
  (world,status) = result
  match status:
    case Fail{cause}: (world,Fail{SW.error_text(cause)})
    case Done{next}: (world,Done{next})

def after(world:W.State,support:SP.State,movement:M.Transition) -> W.State & Result<&2,&2,String,SP.State>:
  supported(SW.update_checked(world,support,movement))

def motion_driver() -> R.Driver:
  R.Driver{context,after}

def realtime_step(state:S.State) -> S.State:
  S.realtime_step(motion_driver(),state)

def dispatch(state:S.State,session:L.Session,token:String,request:J.Value) -> IO(S.State & L.Session & J.Value):
  S.dispatch(~motion_driver(),state,session,token,request)

# Base macOS lowercases characters; modifier events use 65536 + hardware code.
# Physical input verification remains separate from this source-derived mapping.
def bindings() -> I.Bindings:
  I.Bindings{119,115,97,100,32,65592,65595}

def input(state:S.State,packet:CC.Packet) -> S.State & Result<&2,&2,String,Unit>:
  S.input(state,bindings(),packet)

def capture_allowed(frame:CR.Snapshot) -> Bool:
  True{}

def presenter_driver() -> CP.Driver<S.State,CR.Snapshot>:
  CP.Driver{S.snapshot,input,S.release,capture_allowed}

def rendered(result:CR.Assets & Image) -> CR.Assets & Result<&2,&2,String,Image>:
  (assets,image) = result
  (assets,Done{image})

def draw(frame:CR.Snapshot,assets:CR.Assets,width:U32,height:U32) -> CR.Assets & Result<&2,&2,String,Image>:
  rendered(CR.render(frame,assets,width,height))

def describe(frame:CR.Snapshot) -> String:
  CR.Snapshot{tick,revision,blocks,CR.Camera{x,y,z,yaw,pitch}} = frame
  "{\"event\":\"client.frame\",\"tick\":" ++ Nat.show(tick) ++ ",\"revision\":" ++ Nat.show(revision) ++ ",\"renderer\":\"cube-instrument\",\"yaw_f32\":" ++ U32.show(F32.bits(yaw)) ++ ",\"pitch_f32\":" ++ U32.show(F32.bits(pitch)) ++ "}"

# Loading closes the archive. Assets contain owned image values, no live handles.
def close_assets(assets:CR.Assets) -> IO(Unit):
  IO.pure(Unit,Unit{})

def renderer() -> CP.Renderer<CR.Snapshot,CR.Assets>:
  CP.Renderer{draw,describe,close_assets}

def pristine_result(view:W.View,result:G.Engine & Bool) -> W.State & Bool:
  (engine,valid) = result
  (W.attach(engine,view),valid)

def pristine_extracted(result:G.Engine & W.View) -> W.State & Bool:
  (engine,view) = result
  pristine_result(view,PW.pristine(engine))

def pristine(world:W.State) -> W.State & Bool:
  pristine_extracted(W.take(world))

def fixture_world(world:W.State) -> W.State & Result<&2,&2,String,Unit>:
  W.fixture_status(Done{Unit{}},world)

def fixture_failed(state:S.State,message:String) -> IO(S.Ready):
  S.State{player,shell} = state
  S.startup_failed(shell,"finite scene: " ++ message)

def fixture_finished(first_peer:U32,result:S.State & Result<&2,&2,String,Unit>) -> IO(S.Ready):
  (state,status) = result
  match status:
    case Fail{message}: fixture_failed(state,message)
    case Done{unit}: IO.pure(S.Ready,S.Ready{state,first_peer})

def fixture_gate(first_peer:U32,result:S.State & Bool) -> IO(S.Ready):
  (state,valid) = result
  match valid:
    case False{}: IO.pure(S.Ready,S.Ready{state,first_peer})
    case True{}: fixture_finished(first_peer,S.query(Result<&2,&2,String,Unit>,state,p => R.query(Result<&2,&2,String,Unit>,p,fixture_world)))

# Only a pristine Core is initialized. Loaded terrain, player and pause survive.
def initialize(ready:S.Ready) -> IO(S.Ready):
  S.Ready{state,first_peer} = ready
  fixture_gate(first_peer,S.query(Bool,state,p => R.query(Bool,p,pristine)))

def unpaused_world(result:G.Engine & W.View) -> W.State & Unit:
  (G.Engine{world,registry},view) = result
  (W.attach(G.Engine{C.set_paused(world,False{}),registry},view),Unit{})

def unpause(world:W.State) -> W.State & Unit:
  unpaused_world(W.take(world))

def started_unpaused(result:S.State & Unit,first_peer:U32) -> S.Ready:
  (state,unit) = result
  S.Ready{state,first_peer}

def run_requested(ready:S.Ready,run:Bool) -> S.Ready:
  S.Ready{state,first_peer} = ready
  match run:
    case False{}: S.Ready{state,first_peer}
    case True{}: started_unpaused(S.query(Unit,state,p => R.query(Unit,p,unpause)),first_peer)
