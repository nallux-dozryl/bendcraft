import Base
import ./local_player_session.bend as S
import ./local_player_scene.bend as Scene
import ./local_resource_world.bend as World
import ./world_visibility.bend as V
import ./client_controls.bend as CC
import ./server.bend as Server
import ./live.bend as L
import ./json.bend as J

# The public save session and private renderer lease live in one actor.
# Resources and the native window belong to the remote renderer process.
type Lease is Data:
  Lease{epoch:String,next:Nat,remaining:U32,active:Bool}

type State is Type:
  State{saved:S.State,lease:Lease,counter:Nat,nonce:String,capability:String}

def idle() -> Lease:
  Lease{"",1n,0,False{}}

def maximum_sequence() -> Nat:
  Nat.add(Nat.mul(4294967295n,65536n),65535n)

def new(saved:S.State,nonce:String,capability:String) -> State:
  State{saved,idle(),0n,nonce,capability}

def renewed(lease:Lease) -> Lease:
  Lease{epoch,next,remaining,active} = lease
  Lease{epoch,1n+next,100,active}

def admitted(lease:Lease,epoch:String,+sequence:Nat) -> Bool:
  Lease{+actual,+next,remaining,+active} = lease
  active && String.eq(actual,epoch) && Nat.is_eq(next,sequence) &&
    Nat.is_gt(sequence,0n) && Nat.is_lt(sequence,maximum_sequence())

def expired(lease:Lease) -> Lease:
  Lease{epoch,next,remaining,active} = lease
  Lease{epoch,next,0,False{}}

def lease_tick(state:State) -> State:
  match state:
    case State{saved,Lease{epoch,next,remaining,False{}},counter,nonce,capability}:
      State{saved,Lease{epoch,next,remaining,False{}},counter,nonce,capability}
    case State{saved,Lease{epoch,next,0,True{}},counter,nonce,capability}:
      State{S.release(saved),Lease{epoch,next,0,False{}},counter,nonce,capability}
    case State{saved,Lease{epoch,next,1,True{}},counter,nonce,capability}:
      State{S.release(saved),Lease{epoch,next,0,False{}},counter,nonce,capability}
    case State{saved,Lease{epoch,next,remaining,True{}},counter,nonce,capability}:
      State{saved,Lease{epoch,next,U32.sub(remaining,1),True{}},counter,nonce,capability}

# Lease expiry is checked on real actor pulses, including paused pulses, and
# releases physical controls before the same pulse can advance player physics.
def pulsed(state:State) -> State:
  State{saved,lease,counter,nonce,capability} = state
  State{Scene.realtime_step(saved),lease,counter,nonce,capability}

def realtime_active(state:State,live:Bool) -> State:
  match live:
    case False{}: state
    case True{}: pulsed(lease_tick(state))

def realtime_step(state:State) -> State:
  State{saved,lease,counter,nonce,+capability} = state
  realtime_active(State{saved,lease,counter,nonce,capability},Bool.not(String.is_empty(capability)))

def dispatched(lease:Lease,counter:Nat,nonce:String,capability:String,result:S.State & L.Session & J.Value) -> State & L.Session & J.Value:
  (saved,session,value) = result
  (State{saved,lease,counter,nonce,capability},session,value)

def dispatch(state:State,session:L.Session,token:String,request:J.Value) -> IO(State & L.Session & J.Value):
  State{saved,lease,counter,nonce,capability} = state
  do IO<State & L.Session & J.Value>:
    result : S.State & L.Session & J.Value <- Scene.dispatch(saved,session,token,request)
    return dispatched(lease,counter,nonce,capability,result)

def driver() -> Server.EffectfulDriver<State>:
  Server.EffectfulDriver{realtime_step,dispatch}

def hello_capacity(state:State,room:Bool) -> State & Result<&2,&2,String,String>:
  match state room:
    case _ False{}: (state,Fail{"RendererLeaseExhausted"})
    case State{saved,lease,+counter,+nonce,capability} True{}:
      +fresh = nonce ++ ":" ++ Nat.show(1n+counter)
      (State{S.release(saved),Lease{fresh,1n,100,True{}},1n+counter,nonce,capability},Done{fresh})

def hello_available(state:State) -> State & Result<&2,&2,String,String>:
  match state:
    case State{saved,Lease{epoch,next,remaining,True{}},counter,nonce,capability}:
      (State{saved,Lease{epoch,next,remaining,True{}},counter,nonce,capability},Fail{"RendererLeaseBusy"})
    case State{saved,lease,+counter,+nonce,capability}:
      hello_capacity(State{saved,lease,counter,nonce,capability},Nat.is_lt(counter,maximum_sequence()))

def hello_checked(state:State,authorized:Bool) -> State & Result<&2,&2,String,String>:
  match authorized:
    case False{}: (state,Fail{"RendererAuthenticationFailed"})
    case True{}: hello_available(state)

def hello(state:State,presented:String) -> State & Result<&2,&2,String,String>:
  State{saved,lease,counter,nonce,+capability} = state
  hello_checked(State{saved,lease,counter,nonce,capability},
    Bool.not(String.is_empty(capability)) && String.eq(capability,presented))

def frame_result(lease:Lease,counter:Nat,nonce:String,capability:String,result:S.State & Result<&2,&2,String,V.Sample>) -> State & Result<&2,&2,String,V.Sample>:
  (saved,status) = result
  (State{saved,renewed(lease),counter,nonce,capability},status)

def frame_checked(state:State,width:U32,height:U32,valid:Bool) -> State & Result<&2,&2,String,V.Sample>:
  match state valid:
    case _ False{}: (state,Fail{"RendererLeaseOrSequence"})
    case State{saved,lease,counter,nonce,capability} True{}:
      frame_result(lease,counter,nonce,capability,World.snapshot(saved,width,height))

def frame(state:State,epoch:String,sequence:Nat,width:U32,height:U32) -> State & Result<&2,&2,String,V.Sample>:
  State{saved,+lease,counter,nonce,capability} = state
  frame_checked(State{saved,lease,counter,nonce,capability},width,height,admitted(lease,epoch,sequence))

def input_result(lease:Lease,counter:Nat,nonce:String,capability:String,result:S.State & Result<&2,&2,String,Unit>) -> State & Result<&2,&2,String,Unit>:
  (saved,status) = result
  (State{saved,renewed(lease),counter,nonce,capability},status)

def input_checked(state:State,packet:CC.Packet,valid:Bool) -> State & Result<&2,&2,String,Unit>:
  match state valid:
    case _ False{}: (state,Fail{"RendererLeaseOrSequence"})
    case State{saved,lease,counter,nonce,capability} True{}:
      input_result(lease,counter,nonce,capability,Scene.input(saved,packet))

def input(state:State,epoch:String,sequence:Nat,packet:CC.Packet) -> State & Result<&2,&2,String,Unit>:
  State{saved,+lease,counter,nonce,capability} = state
  input_checked(State{saved,lease,counter,nonce,capability},packet,admitted(lease,epoch,sequence))

def release_checked(state:State,valid:Bool) -> State & Result<&2,&2,String,Unit>:
  match state valid:
    case _ False{}: (state,Fail{"RendererLeaseOrSequence"})
    case State{saved,lease,counter,nonce,capability} True{}:
      (State{S.release(saved),renewed(lease),counter,nonce,capability},Done{Unit{}})

def release(state:State,epoch:String,sequence:Nat) -> State & Result<&2,&2,String,Unit>:
  State{saved,+lease,counter,nonce,capability} = state
  release_checked(State{saved,lease,counter,nonce,capability},admitted(lease,epoch,sequence))

def disconnect_checked(state:State,matching:Bool) -> State & Unit:
  match state matching:
    case _ False{}: (state,Unit{})
    case State{saved,lease,counter,nonce,capability} True{}:
      (State{S.release(saved),expired(lease),counter,nonce,capability},Unit{})

# EOF from an older socket cannot release a newer connection's controls.
def disconnect(state:State,epoch:String) -> State & Unit:
  State{saved,+lease,counter,nonce,capability} = state
  Lease{+actual,next,remaining,+active} = lease
  disconnect_checked(State{saved,lease,counter,nonce,capability},active && String.eq(actual,epoch))

def stop_release(state:State) -> State & Unit:
  State{saved,lease,counter,nonce,capability} = state
  (State{S.release(saved),expired(lease),counter,nonce,""},Unit{})

law rejected_hello_preserves_complete_actor:
  for state:State
  {hello_checked(state,False{}) == (state,Fail{"RendererAuthenticationFailed"}) : State & Result<&2,&2,String,String>}
def rejected_hello_preserves_complete_actor(state):
  match state:
    case State{saved,lease,counter,nonce,capability}: {==}

law stale_disconnect_preserves_complete_actor:
  for state:State
  {disconnect_checked(state,False{}) == (state,Unit{}) : State & Unit}
def stale_disconnect_preserves_complete_actor(state):
  match state:
    case State{saved,lease,counter,nonce,capability}: {==}
