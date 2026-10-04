import Base
import ./local_player_session.bend as S
import ./local_player_scene.bend as Scene
import ./local_resource_world.bend as World
import ./world_visibility.bend as V
import ./client_controls.bend as CC
import ./server.bend as Server
import ./live.bend as L
import ./json.bend as J
import ./core.bend as C
import ./player_inventory.bend as I
import ./player_block_interaction.bend as BI

# The public save session and private renderer lease live in one actor.
# Resources and the native window belong to the remote renderer process.
type Lease is Data:
  Lease{epoch:String,next:Nat,remaining:U32,active:Bool}

type State is Type:
  State{saved:S.State,lease:Lease,counter:Nat,nonce:String,capability:String,owner:C.Capability}

def idle() -> Lease:
  Lease{"",1n,0,False{}}

def maximum_sequence() -> Nat:
  Nat.add(Nat.mul(4294967295n,65536n),65535n)

def new_reserved(saved:S.State,nonce:String,capability:String,owner:C.Capability) -> State:
  State{saved,idle(),0n,nonce,capability,owner}

def new(saved:S.State,nonce:String,capability:String) -> State:
  new_reserved(saved,nonce,capability,C.Observer{})

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
    case State{saved,Lease{epoch,next,remaining,False{}},counter,nonce,capability,owner}:
      State{saved,Lease{epoch,next,remaining,False{}},counter,nonce,capability,owner}
    case State{saved,Lease{epoch,next,0,True{}},counter,nonce,capability,owner}:
      State{S.release(saved),Lease{epoch,next,0,False{}},counter,nonce,capability,owner}
    case State{saved,Lease{epoch,next,1,True{}},counter,nonce,capability,owner}:
      State{S.release(saved),Lease{epoch,next,0,False{}},counter,nonce,capability,owner}
    case State{saved,Lease{epoch,next,remaining,True{}},counter,nonce,capability,owner}:
      State{saved,Lease{epoch,next,U32.sub(remaining,1),True{}},counter,nonce,capability,owner}

# Lease expiry is checked on real actor pulses, including paused pulses, and
# releases physical controls before the same pulse can advance player physics.
def pulsed(state:State) -> State:
  State{saved,lease,counter,nonce,capability,owner} = state
  State{Scene.realtime_step(saved),lease,counter,nonce,capability,owner}

def realtime_active(state:State,live:Bool) -> State:
  match live:
    case False{}: state
    case True{}: pulsed(lease_tick(state))

def realtime_step(state:State) -> State:
  State{saved,lease,counter,nonce,+capability,owner} = state
  realtime_active(State{saved,lease,counter,nonce,capability,owner},Bool.not(String.is_empty(capability)))

def dispatched(lease:Lease,counter:Nat,nonce:String,capability:String,owner:C.Capability,result:S.State & L.Session & J.Value) -> State & L.Session & J.Value:
  (saved,session,value) = result
  (State{saved,lease,counter,nonce,capability,owner},session,value)

def dispatch(state:State,session:L.Session,token:String,request:J.Value) -> IO(State & L.Session & J.Value):
  State{saved,lease,counter,nonce,capability,owner} = state
  do IO<State & L.Session & J.Value>:
    result : S.State & L.Session & J.Value <- Scene.dispatch(saved,session,token,request)
    return dispatched(lease,counter,nonce,capability,owner,result)

def driver() -> Server.EffectfulDriver<State>:
  Server.EffectfulDriver{realtime_step,dispatch}

def hello_capacity(state:State,room:Bool) -> State & Result<&2,&2,String,String>:
  match state room:
    case _ False{}: (state,Fail{"RendererLeaseExhausted"})
    case State{saved,lease,+counter,+nonce,capability,owner} True{}:
      +fresh = nonce ++ ":" ++ Nat.show(1n+counter)
      (State{S.release(saved),Lease{fresh,1n,100,True{}},1n+counter,nonce,capability,owner},Done{fresh})

def hello_available(state:State) -> State & Result<&2,&2,String,String>:
  match state:
    case State{saved,Lease{epoch,next,remaining,True{}},counter,nonce,capability,owner}:
      (State{saved,Lease{epoch,next,remaining,True{}},counter,nonce,capability,owner},Fail{"RendererLeaseBusy"})
    case State{saved,lease,+counter,+nonce,capability,owner}:
      hello_capacity(State{saved,lease,counter,nonce,capability,owner},Nat.is_lt(counter,maximum_sequence()))

def hello_checked(state:State,authorized:Bool) -> State & Result<&2,&2,String,String>:
  match authorized:
    case False{}: (state,Fail{"RendererAuthenticationFailed"})
    case True{}: hello_available(state)

def hello(state:State,presented:String) -> State & Result<&2,&2,String,String>:
  State{saved,lease,counter,nonce,+capability,owner} = state
  hello_checked(State{saved,lease,counter,nonce,capability,owner},
    Bool.not(String.is_empty(capability)) && String.eq(capability,presented))

def frame_result(lease:Lease,counter:Nat,nonce:String,capability:String,owner:C.Capability,result:S.State & Result<&2,&2,String,V.Sample>) -> State & Result<&2,&2,String,V.Sample>:
  (saved,status) = result
  (State{saved,renewed(lease),counter,nonce,capability,owner},status)

def frame_checked(state:State,width:U32,height:U32,valid:Bool) -> State & Result<&2,&2,String,V.Sample>:
  match state valid:
    case _ False{}: (state,Fail{"RendererLeaseOrSequence"})
    case State{saved,lease,counter,nonce,capability,owner} True{}:
      frame_result(lease,counter,nonce,capability,owner,World.snapshot(saved,width,height))

def frame(state:State,epoch:String,sequence:Nat,width:U32,height:U32) -> State & Result<&2,&2,String,V.Sample>:
  State{saved,+lease,counter,nonce,capability,owner} = state
  frame_checked(State{saved,lease,counter,nonce,capability,owner},width,height,admitted(lease,epoch,sequence))

def input_result(lease:Lease,counter:Nat,nonce:String,capability:String,owner:C.Capability,result:S.State & Result<&2,&2,String,Unit>) -> State & Result<&2,&2,String,Unit>:
  (saved,status) = result
  (State{saved,renewed(lease),counter,nonce,capability,owner},status)

def input_checked(state:State,packet:CC.Packet,valid:Bool) -> State & Result<&2,&2,String,Unit>:
  match state valid:
    case _ False{}: (state,Fail{"RendererLeaseOrSequence"})
    case State{saved,lease,counter,nonce,capability,owner} True{}:
      input_result(lease,counter,nonce,capability,owner,Scene.input(saved,packet))

def input(state:State,epoch:String,sequence:Nat,packet:CC.Packet) -> State & Result<&2,&2,String,Unit>:
  State{saved,+lease,counter,nonce,capability,owner} = state
  input_checked(State{saved,lease,counter,nonce,capability,owner},packet,admitted(lease,epoch,sequence))

def inventory_result(lease:Lease,counter:Nat,nonce:String,capability:String,owner:C.Capability,result:S.State & I.Snapshot) -> State & Result<&2,&2,String,I.Snapshot>:
  (saved,snapshot) = result
  (State{saved,renewed(lease),counter,nonce,capability,owner},Done{snapshot})

def inventory_checked(state:State,valid:Bool) -> State & Result<&2,&2,String,I.Snapshot>:
  match state valid:
    case _ False{}: (state,Fail{"RendererLeaseOrSequence"})
    case State{saved,lease,counter,nonce,capability,owner} True{}:
      inventory_result(lease,counter,nonce,capability,owner,S.inventory_inspect(saved))

def inventory(state:State,epoch:String,sequence:Nat) -> State & Result<&2,&2,String,I.Snapshot>:
  State{saved,+lease,counter,nonce,capability,owner} = state
  inventory_checked(State{saved,lease,counter,nonce,capability,owner},admitted(lease,epoch,sequence))

def hotbar_checked(state:State,index:U32,valid:Bool) -> State & Result<&2,&2,String,Unit>:
  match state valid:
    case _ False{}: (state,Fail{"RendererLeaseOrSequence"})
    case State{saved,lease,counter,nonce,capability,owner} True{}:
      input_result(lease,counter,nonce,capability,owner,S.inventory_select(saved,index))

def hotbar(state:State,epoch:String,sequence:Nat,index:U32) -> State & Result<&2,&2,String,Unit>:
  State{saved,+lease,counter,nonce,capability,owner} = state
  hotbar_checked(State{saved,lease,counter,nonce,capability,owner},index,admitted(lease,epoch,sequence))

def action_result(lease:Lease,counter:Nat,nonce:String,capability:String,owner:C.Capability,result:S.State & BI.Outcome) -> State & Result<&2,&2,String,BI.Outcome>:
  (saved,status) = result
  (State{saved,renewed(lease),counter,nonce,capability,owner},Done{status})

# The private request supplies only a button. The actor retains its reserved
# saved-player capability; observers and developer API sessions cannot forge it.
def action_checked(state:State,sequence:Nat,button:U32,valid:Bool) -> State & Result<&2,&2,String,BI.Outcome>:
  match state valid:
    case _ False{}: (state,Fail{"RendererLeaseOrSequence"})
    case State{saved,lease,counter,nonce,capability,+owner} True{}:
      action_result(lease,counter,nonce,capability,owner,S.block_action(saved,owner,sequence,button))

def action(state:State,epoch:String,+sequence:Nat,button:U32) -> State & Result<&2,&2,String,BI.Outcome>:
  State{saved,+lease,counter,nonce,capability,owner} = state
  action_checked(State{saved,lease,counter,nonce,capability,owner},sequence,button,admitted(lease,epoch,sequence))

def release_checked(state:State,valid:Bool) -> State & Result<&2,&2,String,Unit>:
  match state valid:
    case _ False{}: (state,Fail{"RendererLeaseOrSequence"})
    case State{saved,lease,counter,nonce,capability,owner} True{}:
      (State{S.release(saved),renewed(lease),counter,nonce,capability,owner},Done{Unit{}})

def release(state:State,epoch:String,sequence:Nat) -> State & Result<&2,&2,String,Unit>:
  State{saved,+lease,counter,nonce,capability,owner} = state
  release_checked(State{saved,lease,counter,nonce,capability,owner},admitted(lease,epoch,sequence))

def disconnect_checked(state:State,matching:Bool) -> State & Unit:
  match state matching:
    case _ False{}: (state,Unit{})
    case State{saved,lease,counter,nonce,capability,owner} True{}:
      (State{S.release(saved),expired(lease),counter,nonce,capability,owner},Unit{})

# EOF from an older socket cannot release a newer connection's controls.
def disconnect(state:State,epoch:String) -> State & Unit:
  State{saved,+lease,counter,nonce,capability,owner} = state
  Lease{+actual,next,remaining,+active} = lease
  disconnect_checked(State{saved,lease,counter,nonce,capability,owner},active && String.eq(actual,epoch))

def stop_release(state:State) -> State & Unit:
  State{saved,lease,counter,nonce,capability,owner} = state
  (State{S.release(saved),expired(lease),counter,nonce,"",owner},Unit{})

law rejected_hello_preserves_complete_actor:
  for state:State
  {hello_checked(state,False{}) == (state,Fail{"RendererAuthenticationFailed"}) : State & Result<&2,&2,String,String>}
def rejected_hello_preserves_complete_actor(state):
  match state:
    case State{saved,lease,counter,nonce,capability,owner}: {==}

law stale_disconnect_preserves_complete_actor:
  for state:State
  {disconnect_checked(state,False{}) == (state,Unit{}) : State & Unit}
def stale_disconnect_preserves_complete_actor(state):
  match state:
    case State{saved,lease,counter,nonce,capability,owner}: {==}
