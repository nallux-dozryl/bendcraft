import Base
import ./player_runtime.bend as R
import ./player_record.bend as PR
import ./player_codec.bend as PC
import ./player_storage.bend as PS
import ./player_controls.bend as CT
import ./client_controls.bend as CC
import ./player_input.bend as PI
import ./mouse_input.bend as MI
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

# The runtime owns the sole Engine/body. The lease and save policy remain an
# affine shell. A bundle operation transfers the Engine and checked record into
# E.State temporarily; the transient header contains no body or look authority.
type Shell is Type:
  Shell{identity:String,path:String,highwater:U32,limits:P.Limits,lease:WL.Lease,
    maximum:U32,catalog:List<&2,E.Operation>}
type State is Type:
  State{player:R.State,shell:Shell}
type Transient is Type:
  Transient{tables:T.Tables,palette:Maybe<&2,W.Palette>,region:W.Bounds,
    cache:Maybe<&2,W.SnapshotCache>,buttons:PI.Buttons,mouse:MI.State,
    options:MI.Options,error:Maybe<&2,String>}

def to_bundle_view(shell:Shell,tables:T.Tables,buttons:PI.Buttons,mouse:MI.State,options:MI.Options,error:Maybe<&2,String>,record:PR.Record,result:G.Engine & W.View) -> E.State<PR.Record> & Transient:
  Shell{identity,path,highwater,limits,lease,maximum,catalog} = shell
  (engine,W.View{body,yaw,pitch,palette,region,cache}) = result
  (E.State{P.State{engine,identity,path,highwater,limits,lease},record,maximum,catalog},Transient{tables,palette,region,cache,buttons,mouse,options,error})

def to_bundle_controls(shell:Shell,world:W.State,tables:T.Tables,controls:CT.Controller,error:Maybe<&2,String>,record:PR.Record) -> E.State<PR.Record> & Transient:
  CT.Controller{buttons,look,mouse,options} = controls
  to_bundle_view(shell,tables,buttons,mouse,options,error,record,W.take(world))

def to_bundle_record(shell:Shell,result:R.State & PR.Record) -> E.State<PR.Record> & Transient:
  (R.State{world,tables,metadata,support,controls,error},record) = result
  to_bundle_controls(shell,world,tables,controls,error,record)

def to_bundle(state:State) -> E.State<PR.Record> & Transient:
  State{player,shell} = state
  to_bundle_record(shell,R.record(player))

def from_bundle(stored:E.State<PR.Record>,transient:Transient) -> State:
  E.State{P.State{engine,identity,path,highwater,limits,lease},PR.Record{PC.Snapshot{+player,support,yaw,pitch,dimension},look},maximum,catalog} = stored
  Transient{tables,palette,region,cache,buttons,mouse,options,error} = transient
  State{R.State{W.State{engine,R.player_body(player),yaw,pitch,palette,region,cache},tables,R.metadata(player),support,CT.Controller{buttons,look,mouse,options},error},Shell{identity,path,highwater,limits,lease,maximum,catalog}}

def queried(-A:Type,shell:Shell,result:R.State & A) -> State & A:
  (player,value) = result
  (State{player,shell},value)

def query(-A:Type,state:State,operation:R.State -> R.State & A) -> State & A:
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
  [E.Operation{"player.inspect",L.Public{},[],"Observe the current neutral player record as exact typed NBT bytes; this query does not advance simulation."}]

def byte_values(bytes:List<&2,U32>) -> List<&2,J.Value>:
  match bytes:
    case Nil{}: []
    case byte <> rest: L.uint(byte) <> byte_values(rest)

def inspected(engine:G.Engine,record:PR.Record,result:Result<&2,&2,PR.Error,List<&2,U32>>) -> G.Engine & PR.Record & Result<&2,&2,L.Fault,J.Value>:
  match result:
    case Fail{error}: (engine,record,Fail{L.bad("InvalidPlayerState",PS.error_text(error))})
    case Done{bytes}: (engine,record,Done{L.obj([J.JMember{"format",L.text("bendex:player-record")},J.JMember{"nbt_bytes",J.JArray{byte_values(bytes)}}])})

def operation_dispatch(engine:G.Engine,+record:PR.Record,session:L.Session,envelope:L.Envelope) -> G.Engine & PR.Record & Result<&2,&2,L.Fault,J.Value>:
  L.Envelope{id,op,args,at} = envelope
  match op:
    case "player.inspect": inspected(engine,record,PR.encode(record))
    case _: (engine,record,Fail{L.bad("UnknownOperation","unknown player operation")})

def operation_dispatch_plain(engine:G.Engine,record:PR.Record,session:L.Session,envelope:L.Envelope) -> G.Engine & PR.Record & Result<&2,&2,L.Fault,J.Value>:
  operation_dispatch(engine,record,session,envelope)

def operations() -> E.Operations<PR.Record>:
  E.Operations{catalog,operation_dispatch_plain}

def dispatched(transient:Transient,result:E.State<PR.Record> & L.Session & J.Value) -> State & L.Session & J.Value:
  (stored,session,value) = result
  (from_bundle(stored,transient),session,value)

def delegate_bundle(session:L.Session,token:String,request:J.Value,result:E.State<PR.Record> & Transient) -> IO(State & L.Session & J.Value):
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

def parsed(~driver:R.Driver,state:State,session:L.Session,token:String,request:J.Value,result:Result<&2,&2,L.Fault,L.Envelope>) -> IO(State & L.Session & J.Value):
  match result:
    case Done{envelope}:
      L.Envelope{id,+op,args,at} = envelope
      match op:
        case "simulation.step": IO.pure(State & L.Session & J.Value,step_envelope(~driver,state,session,L.Envelope{id,op,args,at}))
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

def startup_restored(shell:Shell,first_peer:U32,result:R.State & Result<&2,&2,String,Unit>) -> IO(Ready):
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

def returned_bundle(result:E.State<PR.Record> & Transient) -> State:
  (stored,transient) = result
  from_bundle(stored,transient)

law bundle_transfer_preserves_all_runtime_and_save_fields:
  for state:State
  {returned_bundle(to_bundle(state)) == state : State}

def bundle_transfer_preserves_all_runtime_and_save_fields(state):
  match state:
    case State{R.State{W.State{engine,body,yaw,pitch,palette,region,cache},tables,
      R.Metadata{input,jumping,delay,trigger,sync,speed,head},support,
      CT.Controller{buttons,look,mouse,options},error},
      Shell{identity,path,highwater,limits,lease,maximum,catalog}}: {==}
