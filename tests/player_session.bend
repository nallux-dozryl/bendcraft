import Base
import ../src/player_session.bend as S
import ../src/player_storage.bend as PS
import ../src/player_record.bend as PR
import ../src/player_runtime.bend as R
import ../src/player_tick.bend as P
import ../src/player_controls.bend as CT
import ../src/player_input.bend as I
import ../src/mouse_input.bend as MI
import ../src/support.bend as SP
import ../src/support_world.bend as SW
import ../src/travel.bend as T
import ../src/locomotion.bend as L
import ../src/movement.bend as M
import ../src/f64.bend as F
import ../src/client_world.bend as W
import ../src/registry.bend as B
import ../src/game.bend as G
import ../src/core.bend as C
import ../src/section_map.bend as SM
import ../src/schedule.bend as Q
import ../src/extended_persistence.bend as E
import ../src/atomic_file.bend as A
import ../src/world_lock.bend as WL
import ../src/server.bend as Server
import ../src/live.bend as Live
import ../src/json.bend as J

# The driver supplies measured neutral attributes and actual owned-world support
# callbacks. No gameplay arithmetic, native window, or alternate save codec here.
def context_value(yaw:F32,buttons:I.Buttons,sample:SW.Sample) -> P.Context:
  I.Buttons{forward,backward,left,right,jump,shift,sprint} = buttons
  SW.Sample{ground,factor} = sample
  P.Context{T.Context{ground,T.Attributes{F.F64{1069128089,2576980378},F.F64{1068792545,1202590843},F.from_u32(1),F.from_u32(1)},yaw,0.6,sprint,False{},False{},T.NeutralDryAir{}},F.F64{1071309127,2920577761},factor,True{},P.Neutral{}}

def sampled(yaw:F32,buttons:I.Buttons,result:W.State & Result<&2,&2,SW.Error,SW.Sample>) -> W.State & Result<&2,&2,String,P.Context>:
  (world,status) = result
  match status:
    case Fail{cause}: (world,Fail{SW.error_text(cause)})
    case Done{sample}: (world,Done{context_value(yaw,buttons,sample)})

def context(fail:Bool,world:W.State,support:SP.State,buttons:I.Buttons,yaw:F32) -> W.State & Result<&2,&2,String,P.Context>:
  match fail:
    case True{}: (world,Fail{"explicit-session-fixture-context-failure"})
    case False{}: sampled(yaw,buttons,SW.sample_checked(world,support))

def supported(result:W.State & Result<&2,&2,SW.Error,SP.State>) -> W.State & Result<&2,&2,String,SP.State>:
  (world,status) = result
  match status:
    case Fail{cause}: (world,Fail{SW.error_text(cause)})
    case Done{next}: (world,Done{next})

def after(world:W.State,support:SP.State,movement:M.Transition) -> W.State & Result<&2,&2,String,SP.State>:
  supported(SW.update_checked(world,support,movement))

def driver(fail:Bool) -> R.Driver:
  R.Driver{world => support => buttons => yaw => context(fail,world,support,buttons,yaw),after}

def pristine_core(world:C.World) -> C.World & Bool:
  match world:
    case C.World{+tick,time,paused,daylight,+revision,count,SM.EmptySections{},+pending,+events}:
      (C.World{tick,time,paused,daylight,revision,count,SM.EmptySections{},pending,events},Nat.is_eq(tick,0n) && Nat.is_eq(revision,0n) && List.is_empty(&2,Q.Pending<C.Mutation>,pending) && List.is_empty(&2,C.CoreEvent,events))
    case other: (other,False{})

def pristine_view(registry:B.Registry,view:W.View,result:C.World & Bool) -> W.State & Bool:
  (world,valid) = result
  (W.attach(G.Engine{world,registry},view),valid)

def pristine_extracted(result:G.Engine & W.View) -> W.State & Bool:
  (G.Engine{world,registry},view) = result
  pristine_view(registry,view,pristine_core(world))

def pristine(world:W.State) -> W.State & Bool:
  pristine_extracted(W.take(world))

def fixture_world(world:W.State) -> W.State & Result<&2,&2,String,Unit>:
  W.fixture_status(Done{Unit{}},world)

def fixture_controls(state:S.State) -> S.State:
  S.State{R.State{world,tables,metadata,support,CT.Controller{buttons,look,mouse,options},error},shell} = state
  S.State{R.State{world,tables,metadata,support,CT.Controller{I.Buttons{True{},False{},False{},False{},False{},False{},False{}},look,MI.State{F.from_u32(10),F.from_u32(20),F.from_u32(3),F.neg(F.from_u32(4)),False{}},options},error},shell}

def impossible_ready(ready:S.Ready) -> IO(S.State):
  S.Ready{state,first} = ready
  IO.pure(S.State,state)

def fixture_failed(state:S.State,message:String) -> IO(S.State):
  S.State{player,shell} = state
  IO.bind(S.Ready,S.State,S.startup_failed(shell,message),impossible_ready)

def fixture_finished(state:S.State,status:Result<&2,&2,String,Unit>) -> IO(S.State):
  match status:
    case Fail{message}: fixture_failed(state,message)
    case Done{unit}: IO.pure(S.State,fixture_controls(state))

def fixture_result(result:S.State & Result<&2,&2,String,Unit>) -> IO(S.State):
  (state,status) = result
  fixture_finished(state,status)

def fixture_gate(result:S.State & Bool) -> IO(S.State):
  (state,valid) = result
  match valid:
    case False{}: IO.pure(S.State,state)
    case True{}: fixture_result(S.query(Result<&2,&2,String,Unit>,state,p => R.query(Result<&2,&2,String,Unit>,p,fixture_world)))

def fixture_selected(mode:String,state:S.State) -> IO(S.State):
  match mode:
    case "scene": fixture_gate(S.query(Bool,state,p => R.query(Bool,p,pristine)))
    case "fail-context": fixture_gate(S.query(Bool,state,p => R.query(Bool,p,pristine)))
    case "normal": IO.pure(S.State,state)
    case _: IO.die(S.State,2,"unknown explicit player-session fixture mode")

def raw_f64(value:F.F64) -> J.Value:
  F.F64{high,low} = value
  J.JArray{[Live.uint(high),Live.uint(low)]}

def error_value(error:Maybe<&2,String>) -> J.Value:
  match error:
    case None{}: J.JNull{}
    case Some{message}: Live.text(message)

def transient_value(player:R.State) -> R.State & J.Value:
  R.State{world,tables,metadata,support,CT.Controller{+buttons,look,+mouse,options},+error} = player
  MI.State{x,y,ax,ay,first} = mouse
  (R.State{world,tables,metadata,support,CT.Controller{buttons,look,mouse,options},error},Live.obj([
    J.JMember{"buttons",Live.uint(I.mask(buttons))},J.JMember{"mouse_position",J.JArray{[raw_f64(x),raw_f64(y)]}},
    J.JMember{"mouse_accumulated",J.JArray{[raw_f64(ax),raw_f64(ay)]}},J.JMember{"ignore_first_move",Live.boolean(first)},
    J.JMember{"last_error",error_value(error)}]))

def transient_response(session:Live.Session,id:String,result:S.State & J.Value) -> S.State & Live.Session & J.Value:
  (state,value) = result
  S.success(state,session,id,value)

# Explicit read-only harness instrumentation; absent from production discovery.
# It does not mutate controls and is not advertised as a player API operation.
def transient_checked(state:S.State,session:Live.Session,id:String,valid:Bool) -> S.State & Live.Session & J.Value:
  match valid:
    case False{}: S.failure(state,session,id,Live.bad("InvalidArguments","fixture query takes no arguments"))
    case True{}: transient_response(session,id,S.query(J.Value,state,transient_value))

def transient_request(state:S.State,session:Live.Session,envelope:Live.Envelope) -> S.State & Live.Session & J.Value:
  Live.Session{+peer,sequence,capability} = session
  Live.Envelope{id,op,+args,at} = envelope
  transient_checked(S.observed(state,peer),Live.Session{peer,1n+sequence,capability},id,Live.validate_args(args,[]) && Maybe.is_none(&2,Nat,at))

def parsed(~runtime:R.Driver,state:S.State,session:Live.Session,token:String,request:J.Value,decoded:Result<&2,&2,Live.Fault,Live.Envelope>) -> IO(S.State & Live.Session & J.Value):
  match decoded:
    case Done{Live.Envelope{id,"fixture.transient",args,at}}: IO.pure(S.State & Live.Session & J.Value,transient_request(state,session,Live.Envelope{id,"fixture.transient",args,at}))
    case _: S.dispatch(~runtime,state,session,token,request)

def dispatch(~runtime:R.Driver,state:S.State,session:Live.Session,token:String,+request:J.Value) -> IO(S.State & Live.Session & J.Value):
  parsed(~runtime,state,session,token,request,Live.envelope(request))

def serve(~runtime:R.Driver,first:U32,state:S.State) -> IO(Unit):
  Server.run_effectful_from_peer(~S.State,~Server.EffectfulDriver{state => S.realtime_step(runtime,state),state => session => token => request => dispatch(~runtime,state,session,token,request)},state,first)

def served(mode:String,first:U32,state:S.State) -> IO(Unit):
  match mode:
    case "fail-context": serve(~driver(True{}),first,state)
    case _: serve(~driver(False{}),first,state)

def initialized(+mode:String,ready:S.Ready) -> IO(Unit):
  S.Ready{state,first} = ready
  do IO<Unit>:
    kept : S.State <- fixture_selected(mode,state)
    served(mode,first,kept)

def loaded(mode:String,tables:L.Tables) -> IO(Unit):
  do IO<Unit>:
    stored : E.Ready<PR.Record> <- E.load_with(~PR.Record,~PS.codec(),~S.operations(),PS.limits())
    ready : S.Ready <- S.new(stored,tables)
    initialized(mode,ready)

def table_result(mode:String,result:Result<&2,&1,L.Error,L.Tables>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.die(Unit,2,"session sine table load failed")
    case Done{tables}: loaded(mode,tables)

# Separate primitive interruption lane: actual leased Atomic.publish_with over
# independently encoded bundle bytes. Session.dispatch's quiet save is exercised
# separately; this hook only exposes deterministic publication-stage pauses.
def atomic_pause_selected(valid:Bool) -> IO(Unit):
  match valid:
    case True{}: IO.sleep(30000)
    case False{}: IO.pure(Unit,Unit{})

def atomic_pause(name:String,stage:A.Stage) -> IO(Unit):
  atomic_pause_selected(String.eq(name,A.stage_name(stage)))

def atomic_pause_result(stage:A.Stage,result:Result<&1,&1,U32 & String,String>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.pure(Unit,Unit{})
    case Done{name}: atomic_pause(name,stage)

def atomic_observe_inner(+stage:A.Stage) -> IO(Unit):
  do IO<Unit>:
    IO.print(A.stage_name(stage))
    name : Result<&1,&1,U32 & String,String> <- IO.get_env("MC_ATOMIC_PAUSE")
    atomic_pause_result(stage,name)

def atomic_observe(stage:A.Stage) -> IO(Unit):
  atomic_observe_inner(stage)

def atomic_loaded(result:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(List<&2,U32>):
  (file,status) = result
  do IO<List<&2,U32>>:
    File.close(file)
    IO.pass(List<&2,U32>,status)

def atomic_read(path:String) -> IO(List<&2,U32>):
  do IO<List<&2,U32>>:
    file : File <- IO.try(File,File.open(path,"r"))
    result : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,16846848)
    atomic_loaded(result)

def atomic_lease(path:String,suffix:String,payload:String,lease:WL.Lease) -> IO(Unit):
  do IO<Unit>:
    bytes : List<&2,U32> <- atomic_read(payload)
    result : A.Outcome <- A.publish_with(~atomic_observe,path,suffix,bytes)
    released : Result<&1,&1,U32 & String,Unit> <- WL.release(lease)
    IO.pass(Unit,released)
    IO.print(A.outcome_text(result))

def atomic_acquired(path:String,suffix:String,payload:String,result:Result<&1,&1,U32 & String,WL.Lease>) -> IO(Unit):
  match result:
    case Fail{(code,message)}: IO.die(Unit,1,message)
    case Done{lease}: atomic_lease(path,suffix,payload,lease)

def atomic(+path:String,suffix:String,payload:String) -> IO(Unit):
  do IO<Unit>:
    lease : Result<&1,&1,U32 & String,WL.Lease> <- WL.acquire(path ++ ".lock")
    atomic_acquired(path,suffix,payload,lease)

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case exe <> "atomic" <> path <> suffix <> payload <> Nil{}: atomic(path,suffix,payload)
    case exe <> table <> mode <> Nil{}:
      do IO<Unit>:
        result : Result<&2,&1,L.Error,L.Tables> <- L.Tables.load(table)
        table_result(mode,result)
    case _: IO.die(Unit,2,"expected verified sine table path/mode or atomic path suffix payload")

def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),arguments)
