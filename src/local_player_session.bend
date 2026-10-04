import Base
import ./local_player_runtime.bend as R
import ./local_phase_runtime.bend as X
import ./local_move_history.bend as MH
import ./player_fall_history.bend as H
import ./player_runtime.bend as Plain
import ./player_controls.bend as CT
import ./local_player_record.bend as PR
import ./local_player_storage.bend as PS
import ./client_controls.bend as CC
import ./player_input.bend as PI
import ./client_world.bend as W
import ./client_render.bend as CR
import ./extended_persistence.bend as E
import ./persistence.bend as P
import ./world_lock.bend as WL
import ./locomotion.bend as T
import ./game.bend as G
import ./core.bend as C
import ./registry.bend as B
import ./live.bend as L
import ./json.bend as J

# The LocalPlayer runtime owns the only Engine/body. The leased save shell
# transfers that Engine and the complete supported local record through the
# existing atomic extension transaction. Renderer/API reads never tick it.
type Shell is Type:
  Shell{identity:String,path:String,highwater:U32,limits:P.Limits,lease:WL.Lease,
    maximum:U32,catalog:List<&2,E.Operation>}
type State is Type:
  State{player:X.State,shell:Shell}

def to_bundle_split(shell:Shell,result:G.Engine & PR.Record & R.Transient) -> E.State<PR.Record> & R.Transient:
  Shell{identity,path,highwater,limits,lease,maximum,catalog} = shell
  (engine,record,transient) = result
  (E.State{P.State{engine,identity,path,highwater,limits,lease},record,maximum,catalog},transient)

def to_bundle(state:State) -> E.State<PR.Record> & R.Transient:
  State{player,shell} = state
  to_bundle_split(shell,R.detach(player))

def from_bundle(stored:E.State<PR.Record>,transient:R.Transient) -> State:
  E.State{P.State{engine,identity,path,highwater,limits,lease},record,maximum,catalog} = stored
  State{R.attach(engine,record,transient),Shell{identity,path,highwater,limits,lease,maximum,catalog}}

def queried(-A:Type,shell:Shell,result:X.State & A) -> State & A:
  (player,value) = result
  (State{player,shell},value)

def query(-A:Type,state:State,operation:X.State -> X.State & A) -> State & A:
  State{player,shell} = state
  queried(A,shell,operation(player))

def snapshot(state:State,width:U32,height:U32) -> State & Result<&2,&2,String,CR.Snapshot>:
  query(Result<&2,&2,String,CR.Snapshot>,state,p => R.snapshot(p,width,height))

def input(state:State,bindings:PI.Bindings,packet:CC.Packet) -> State & Result<&2,&2,String,Unit>:
  query(Result<&2,&2,String,Unit>,state,p => R.input(p,bindings,packet))

def release(state:State) -> State:
  State{player,shell} = state
  State{R.release(player),shell}

def realtime_step(driver:R.Driver,state:State) -> State:
  State{player,shell} = state
  State{R.realtime_step(driver,player),shell}

def advance(~driver:R.Driver,state:State,ticks:U32) -> State:
  State{player,shell} = state
  State{R.advance(~driver,U32.to_nat(ticks),player),shell}

def catalog(unit:Unit) -> List<&2,E.Operation>:
  [E.Operation{"player.inspect",L.Public{},[],"Observe the complete supported LocalPlayer record as exact typed NBT bytes; this query does not advance simulation."}]

def byte_values(bytes:List<&2,U32>) -> List<&2,J.Value>:
  match bytes:
    case Nil{}: []
    case byte <> rest: L.uint(byte) <> byte_values(rest)

def inspected(engine:G.Engine,record:PR.Record,result:Result<&2,&2,PR.Error,List<&2,U32>>) -> G.Engine & PR.Record & Result<&2,&2,L.Fault,J.Value>:
  match result:
    case Fail{error}: (engine,record,Fail{L.bad("InvalidPlayerState",PR.error_text(error))})
    case Done{bytes}: (engine,record,Done{L.obj([J.JMember{"format",L.text("bendex:local-player-record")},J.JMember{"nbt_bytes",J.JArray{byte_values(bytes)}}])})

def operation_dispatch(engine:G.Engine,+record:PR.Record,session:L.Session,envelope:L.Envelope) -> G.Engine & PR.Record & Result<&2,&2,L.Fault,J.Value>:
  L.Envelope{id,op,args,at} = envelope
  match op:
    case "player.inspect": inspected(engine,record,PR.encode(record))
    case _: (engine,record,Fail{L.bad("UnknownOperation","unknown player operation")})

def operation_dispatch_plain(engine:G.Engine,record:PR.Record,session:L.Session,envelope:L.Envelope) -> G.Engine & PR.Record & Result<&2,&2,L.Fault,J.Value>:
  operation_dispatch(engine,record,session,envelope)

def operations() -> E.Operations<PR.Record>:
  E.Operations{catalog,operation_dispatch_plain}

def dispatched(transient:R.Transient,result:E.State<PR.Record> & L.Session & J.Value) -> State & L.Session & J.Value:
  (stored,session,value) = result
  (from_bundle(stored,transient),session,value)

def delegate_bundle(session:L.Session,token:String,request:J.Value,result:E.State<PR.Record> & R.Transient) -> IO(State & L.Session & J.Value):
  (stored,transient) = result
  do IO<State & L.Session & J.Value>:
    result : E.State<PR.Record> & L.Session & J.Value <- E.dispatch(~PR.Record,~PS.codec(),~operations(),stored,session,token,request)
    return dispatched(transient,result)

def delegate(state:State,session:L.Session,token:String,request:J.Value) -> IO(State & L.Session & J.Value):
  delegate_bundle(session,token,request,to_bundle(state))

def response(state:State,session:L.Session,value:J.Value) -> State & L.Session & J.Value:
  (state,session,value)

def success(state:State,session:L.Session,id:String,value:J.Value) -> State & L.Session & J.Value:
  response(state,session,L.obj([J.JMember{"id",L.text(id)},J.JMember{"ok",L.boolean(True{})},J.JMember{"result",value}]))

def failure(state:State,session:L.Session,id:String,fault:L.Fault) -> State & L.Session & J.Value:
  response(state,session,L.obj([J.JMember{"id",L.text(id)},J.JMember{"ok",L.boolean(False{})},J.JMember{"error",L.fault_value(fault)}]))

def observed(state:State,+peer:U32) -> State:
  State{player,Shell{identity,path,+highwater,limits,lease,maximum,catalog}} = state
  State{player,Shell{identity,path,U32.max(highwater,peer),limits,lease,maximum,catalog}}

def clock_core(registry:B.Registry,view:W.View,result:C.World & C.Clock) -> W.State & C.Clock:
  (world,clock) = result
  (W.attach(G.Engine{world,registry},view),clock)

def clock_world(result:G.Engine & W.View) -> W.State & C.Clock:
  (G.Engine{world,registry},view) = result
  clock_core(registry,view,C.clock(world))

def clock_read(world:W.State) -> W.State & C.Clock:
  clock_world(W.take(world))

def clock_response(session:L.Session,id:String,result:State & C.Clock) -> State & L.Session & J.Value:
  (state,clock) = result
  success(state,session,id,L.clock_value(clock))

def stepped(~driver:R.Driver,state:State,session:L.Session,id:String,result:Result<&2,&2,L.Fault,L.Command>) -> State & L.Session & J.Value:
  match result:
    case Fail{fault}: failure(state,session,id,fault)
    case Done{L.StepCommand{ticks}}:
      clock_response(session,id,query(C.Clock,advance(~driver,state,ticks),p => R.query(C.Clock,p,clock_read)))
    case _: failure(state,session,id,L.bad("InvalidArguments","expected a simulation step command"))

def step_checked(~driver:R.Driver,state:State,session:L.Session,id:String,args:J.Value,valid:Bool,allowed:Bool) -> State & L.Session & J.Value:
  match valid allowed:
    case False{} _: failure(state,session,id,L.bad("InvalidArguments","arguments or scheduled at field do not match the operation schema"))
    case True{} False{}: failure(state,session,id,L.bad("PermissionDenied","developer capability required"))
    case True{} True{}: stepped(~driver,state,session,id,L.decode(L.StepTicks{},args))

# Intercept the real reserved core operation. Each individual tick applies due
# edits then player physics; delegating to Core.advance would skip interleaving.
def step_envelope(~driver:R.Driver,state:State,session:L.Session,envelope:L.Envelope) -> State & L.Session & J.Value:
  L.Session{+peer,sequence,+capability} = session
  L.Envelope{id,op,+args,at} = envelope
  step_checked(~driver,observed(state,peer),L.Session{peer,1n+sequence,capability},id,args,L.validate_args(args,[L.Field{"ticks",L.Unsigned{1,1000},True{}}]) && Maybe.is_none(&2,Nat,at),C.developer(capability))

# The durable codec cannot see transient ownership tails. Check the complete
# runtime only after the existing save/inspect schema and capability gates.
# Other requests keep the unconditional detach/attach owner-preserving path.
def record_refused(state:State,session:L.Session,id:String,code:String,message:String) -> State & L.Session & J.Value:
  L.Session{+peer,sequence,capability} = session
  failure(observed(state,peer),L.Session{peer,1n+sequence,capability},id,L.bad(code,message))

def record_runtime_checked(shell:Shell,session:L.Session,token:String,request:J.Value,id:String,code:String,result:X.State & Result<&2,&2,String,PR.Record>) -> IO(State & L.Session & J.Value):
  (player,status) = result
  match status:
    case Fail{message}: IO.pure(State & L.Session & J.Value,record_refused(State{player,shell},session,id,code,message))
    case Done{record}: delegate(State{player,shell},session,token,request)

def record_admitted(state:State,session:L.Session,token:String,request:J.Value,id:String,code:String) -> IO(State & L.Session & J.Value):
  State{player,shell} = state
  record_runtime_checked(shell,session,token,request,id,code,R.record_checked(player))

def record_valid(state:State,session:L.Session,token:String,request:J.Value,id:String,code:String,valid:Bool,permitted:Bool) -> IO(State & L.Session & J.Value):
  match valid permitted:
    case True{} True{}: record_admitted(state,session,token,request,id,code)
    case _ _: delegate(state,session,token,request)

def save_envelope(state:State,+session:L.Session,token:String,request:J.Value,envelope:L.Envelope) -> IO(State & L.Session & J.Value):
  L.Envelope{id,op,args,at} = envelope
  record_valid(state,session,token,request,id,"SaveEncodingFailed",L.validate_args(args,[]) && Maybe.is_none(&2,Nat,at),C.developer(L.capability(session)))

def inspect_envelope(state:State,session:L.Session,token:String,request:J.Value,envelope:L.Envelope) -> IO(State & L.Session & J.Value):
  L.Envelope{id,op,args,at} = envelope
  record_valid(state,session,token,request,id,"InvalidPlayerState",L.validate_args(args,[]) && Maybe.is_none(&2,Nat,at),True{})

def parsed(~driver:R.Driver,state:State,session:L.Session,token:String,request:J.Value,result:Result<&2,&2,L.Fault,L.Envelope>) -> IO(State & L.Session & J.Value):
  match result:
    case Done{envelope}:
      L.Envelope{id,+op,args,at} = envelope
      match op:
        case "simulation.step": IO.pure(State & L.Session & J.Value,step_envelope(~driver,state,session,L.Envelope{id,op,args,at}))
        case "world.save": save_envelope(state,session,token,request,L.Envelope{id,op,args,at})
        case "player.inspect": inspect_envelope(state,session,token,request,L.Envelope{id,op,args,at})
        case _: delegate(state,session,token,request)
    case _: delegate(state,session,token,request)

def dispatch(~driver:R.Driver,state:State,session:L.Session,token:String,+request:J.Value) -> IO(State & L.Session & J.Value):
  parsed(~driver,state,session,token,request,L.envelope(request))

type Ready is Type:
  Ready{state:State,first_peer:U32}

def startup_closed(message:String,result:Result<&1,&1,U32 & String,Unit>) -> IO(Ready):
  match result:
    case Fail{(code,cause)}: IO.die(Ready,1,"player session startup refused: " ++ message ++ "; lease release: " ++ cause)
    case Done{unit}: IO.die(Ready,1,"player session startup refused: " ++ message)

def startup_failed(shell:Shell,message:String) -> IO(Ready):
  Shell{identity,path,highwater,limits,lease,maximum,catalog} = shell
  do IO<Ready>:
    result : Result<&1,&1,U32 & String,Unit> <- WL.release(lease)
    startup_closed(message,result)

def startup_restored(shell:Shell,first_peer:U32,result:X.State & Result<&2,&2,String,Unit>) -> IO(Ready):
  (player,status) = result
  match status:
    case Fail{message}: startup_failed(shell,message)
    case Done{unit}: IO.pure(Ready,Ready{State{player,shell},first_peer})

def startup_world(shell:Shell,first_peer:U32,tables:T.Tables,record:PR.Record,result:W.State & Result<&2,&2,String,Unit>) -> IO(Ready):
  (world,status) = result
  match status:
    case Fail{message}: startup_failed(shell,message)
    case Done{unit}: startup_restored(shell,first_peer,R.restore(R.fresh(world,tables),record))

def startup_base(base:P.State,record:PR.Record,maximum:U32,catalog:List<&2,E.Operation>,first_peer:U32,tables:T.Tables) -> IO(Ready):
  P.State{engine,identity,path,highwater,limits,lease} = base
  startup_world(Shell{identity,path,highwater,limits,lease,maximum,catalog},first_peer,tables,record,W.new(engine))

# Caller loads the closed PS codec/operations before adoption. The supplied
# Tables are the pinned owned sine lookup. Palette failure closes the save lease.
def new(ready:E.Ready<PR.Record>,tables:T.Tables) -> IO(Ready):
  E.Ready{E.State{base,record,maximum,catalog},first_peer} = ready
  startup_base(base,record,maximum,catalog,first_peer,tables)

def returned_bundle(result:E.State<PR.Record> & R.Transient) -> State:
  (stored,transient) = result
  from_bundle(stored,transient)


law bundle_transfer_preserves_all_local_runtime_and_save_fields:
  for state:State
  {returned_bundle(to_bundle(state)) == state : State}

def bundle_transfer_preserves_all_local_runtime_and_save_fields(state):
  match state:
    case State{X.State{MH.State{W.State{engine,body,yaw,pitch,palette,region,cache},support,minor,H.State{history},motion_tail},tables,
      X.Metadata{local,Plain.Metadata{input,jumping,delay,trigger,sync,speed,head},sprinting,pose,
        CT.Controller{buttons,look,mouse,options},entity,error,metadata_tail},state_tail},
      Shell{identity,path,highwater,limits,lease,maximum,catalog}}: {==}
