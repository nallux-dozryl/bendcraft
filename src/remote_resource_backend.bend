import Base
import ./local_player_session.bend as S
import ./local_player_scene.bend as Scene
import ./local_resource_world.bend as World
import ./world_visibility.bend as V
import ./client_controls.bend as CC
import ./player_controls.bend as PC
import ./server.bend as Server
import ./live.bend as L
import ./json.bend as J
import ./core.bend as C
import ./player_inventory.bend as I
import ./player_block_interaction.bend as BI
import ./player_core_edit.bend as Edit
import ./inventory.bend as Inv
import ./world_mesh.bend as WM

# The public save session and private renderer lease live in one actor.
# Resources and the native window belong to the remote renderer process.
type Lease is Data:
  Lease{epoch:String,next:Nat,remaining:U32,active:Bool}

type State is Type:
  State{saved:S.State,lease:Lease,counter:Nat,nonce:String,capability:String,owner:C.Capability}
type MenuOutcome is Data:
  MenuOutcome{accepted:Bool,message:String,snapshot:I.MenuSnapshot}

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

def frame_ensured(width:U32,height:U32,result:S.State & Result<&2,&2,String,Unit>) -> S.State & Result<&2,&2,String,V.Sample>:
  (saved,status) = result
  match status:
    case Fail{message}: (saved,Fail{message})
    case Done{unit}: World.snapshot(saved,width,height)

def frame_supported(saved:S.State,width:U32,height:U32,dimensions:Bool) -> S.State & Result<&2,&2,String,V.Sample>:
  match dimensions:
    case False{}: World.snapshot(saved,width,height)
    case True{}: frame_ensured(width,height,Scene.ensure(saved))

def frame_sample(saved:S.State,+width:U32,+height:U32) -> S.State & Result<&2,&2,String,V.Sample>:
  frame_supported(saved,width,height,WM.frame_valid(WM.frame(width,height)))

def frame_checked(state:State,width:U32,height:U32,valid:Bool) -> State & Result<&2,&2,String,V.Sample>:
  match state valid:
    case _ False{}: (state,Fail{"RendererLeaseOrSequence"})
    case State{saved,lease,counter,nonce,capability,owner} True{}:
      frame_result(lease,counter,nonce,capability,owner,frame_sample(saved,width,height))

def frame(state:State,epoch:String,sequence:Nat,width:U32,height:U32) -> State & Result<&2,&2,String,V.Sample>:
  State{saved,+lease,counter,nonce,capability,owner} = state
  frame_checked(State{saved,lease,counter,nonce,capability,owner},width,height,admitted(lease,epoch,sequence))

def input_result(lease:Lease,counter:Nat,nonce:String,capability:String,owner:C.Capability,result:S.State & Result<&2,&2,String,Unit>) -> State & Result<&2,&2,String,Unit>:
  (saved,status) = result
  (State{saved,renewed(lease),counter,nonce,capability,owner},status)

# The renderer lease is admitted before this is called. Release and the rest
# of one physical input packet execute in the existing single actor operation.
def input_releasing(saved:S.State,packet:CC.Packet,needed:Bool) -> S.State & Result<&2,&2,String,Unit>:
  match needed:
    case False{}: Scene.input(saved,packet)
    case True{}: Scene.input(S.release(saved),packet)

def input_released(saved:S.State,+packet:CC.Packet) -> S.State & Result<&2,&2,String,Unit>:
  CC.Packet{+actions,focused,captured} = packet
  input_releasing(saved,CC.Packet{actions,focused,captured},PC.release_requested(actions))

def input_checked(state:State,packet:CC.Packet,valid:Bool) -> State & Result<&2,&2,String,Unit>:
  match state valid:
    case _ False{}: (state,Fail{"RendererLeaseOrSequence"})
    case State{saved,lease,counter,nonce,capability,owner} True{}:
      input_result(lease,counter,nonce,capability,owner,input_released(saved,packet))

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

def hotbar_owner_checked(saved:S.State,index:U32,player:Bool) -> S.State & Result<&2,&2,String,Unit>:
  match player:
    case False{}: (saved,Fail{"inventory:player-permission"})
    case True{}: S.inventory_select(saved,index)

def hotbar_checked(state:State,index:U32,valid:Bool) -> State & Result<&2,&2,String,Unit>:
  match state valid:
    case _ False{}: (state,Fail{"RendererLeaseOrSequence"})
    case State{saved,lease,counter,nonce,capability,+owner} True{}:
      input_result(lease,counter,nonce,capability,owner,hotbar_owner_checked(saved,index,Maybe.is_some(&2,U32,Edit.player_peer(owner))))

def hotbar(state:State,epoch:String,sequence:Nat,index:U32) -> State & Result<&2,&2,String,Unit>:
  State{saved,+lease,counter,nonce,capability,owner} = state
  hotbar_checked(State{saved,lease,counter,nonce,capability,owner},index,admitted(lease,epoch,sequence))

def action_result(lease:Lease,counter:Nat,nonce:String,capability:String,owner:C.Capability,result:S.State & BI.Outcome) -> State & Result<&2,&2,String,BI.Outcome>:
  (saved,status) = result
  (State{saved,renewed(lease),counter,nonce,capability,owner},Done{status})

def action_ensured(owner:C.Capability,sequence:Nat,button:U32,result:S.State & Result<&2,&2,String,Unit>) -> S.State & BI.Outcome:
  (saved,status) = result
  match status:
    case Fail{message}: (saved,BI.Outcome{False{},message})
    case Done{unit}: S.block_action(saved,owner,sequence,button)

def action_supported(saved:S.State,owner:C.Capability,sequence:Nat,button:U32,ready:Bool) -> S.State & BI.Outcome:
  match ready:
    case False{}: S.block_action(saved,owner,sequence,button)
    case True{}: action_ensured(owner,sequence,button,Scene.ensure(saved))

def action_abilities(owner:C.Capability,sequence:Nat,+button:U32,result:S.State & I.Abilities) -> S.State & BI.Outcome:
  (saved,I.Abilities{instabuild,maybuild}) = result
  action_supported(saved,owner,sequence,button,instabuild && maybuild && U32.is_le(button,1))

def action_owner_checked(saved:S.State,owner:C.Capability,sequence:Nat,button:U32,player:Bool) -> S.State & BI.Outcome:
  match player:
    case False{}: (saved,BI.Outcome{False{},"interaction:permission-denied"})
    case True{}: action_abilities(owner,sequence,button,S.inventory_abilities(saved))

def action_requested(saved:S.State,+owner:C.Capability,sequence:Nat,button:U32) -> S.State & BI.Outcome:
  action_owner_checked(saved,owner,sequence,button,Maybe.is_some(&2,U32,Edit.player_peer(owner)))

# The private request supplies only a button. The actor retains its reserved
# saved-player capability; observers and developer API sessions cannot forge it.
def action_checked(state:State,sequence:Nat,button:U32,valid:Bool) -> State & Result<&2,&2,String,BI.Outcome>:
  match state valid:
    case _ False{}: (state,Fail{"RendererLeaseOrSequence"})
    case State{saved,lease,counter,nonce,capability,+owner} True{}:
      action_result(lease,counter,nonce,capability,owner,action_requested(saved,owner,sequence,button))

def action(state:State,epoch:String,+sequence:Nat,button:U32) -> State & Result<&2,&2,String,BI.Outcome>:
  State{saved,+lease,counter,nonce,capability,owner} = state
  action_checked(State{saved,lease,counter,nonce,capability,owner},sequence,button,admitted(lease,epoch,sequence))

# Every admitted menu operation reports the actual server-owned inventory.
# A gameplay refusal consumes the private sequence and keeps the lease usable.
def menu_observed(lease:Lease,counter:Nat,nonce:String,capability:String,owner:C.Capability,accepted:Bool,message:String,result:S.State & I.MenuSnapshot) -> State & Result<&2,&2,String,MenuOutcome>:
  (saved,snapshot) = result
  (State{saved,renewed(lease),counter,nonce,capability,owner},Done{MenuOutcome{accepted,message,snapshot}})

def menu_status(lease:Lease,counter:Nat,nonce:String,capability:String,owner:C.Capability,result:S.State & Result<&2,&2,String,Unit>) -> State & Result<&2,&2,String,MenuOutcome>:
  (saved,status) = result
  match status:
    case Fail{message}: menu_observed(lease,counter,nonce,capability,owner,False{},message,S.menu_inspect(saved))
    case Done{unit}: menu_observed(lease,counter,nonce,capability,owner,True{},"",S.menu_inspect(saved))

def menu_player_checked(state:State,operation:S.State -> S.State & Result<&2,&2,String,Unit>,player:Bool) -> State & Result<&2,&2,String,MenuOutcome>:
  match state player:
    case State{saved,lease,counter,nonce,capability,owner} False{}:
      menu_observed(lease,counter,nonce,capability,owner,False{},"inventory:player-permission",S.menu_inspect(saved))
    case State{saved,lease,counter,nonce,capability,owner} True{}:
      menu_status(lease,counter,nonce,capability,owner,operation(saved))

def menu_mutation_checked(state:State,operation:S.State -> S.State & Result<&2,&2,String,Unit>,valid:Bool) -> State & Result<&2,&2,String,MenuOutcome>:
  match state valid:
    case _ False{}: (state,Fail{"RendererLeaseOrSequence"})
    case State{saved,lease,counter,nonce,capability,+owner} True{}:
      menu_player_checked(State{saved,lease,counter,nonce,capability,owner},operation,Maybe.is_some(&2,U32,Edit.player_peer(owner)))

# Ordinary inventory movement does not require maybuild. Acquisition is gated
# by the actual inventory's instabuild ability inside S.inventory_acquire.
def menu_mutation(state:State,epoch:String,sequence:Nat,operation:S.State -> S.State & Result<&2,&2,String,Unit>) -> State & Result<&2,&2,String,MenuOutcome>:
  State{saved,+lease,counter,nonce,capability,owner} = state
  menu_mutation_checked(State{saved,lease,counter,nonce,capability,owner},operation,admitted(lease,epoch,sequence))

def menu_inspect_checked(state:State,valid:Bool) -> State & Result<&2,&2,String,MenuOutcome>:
  match state valid:
    case _ False{}: (state,Fail{"RendererLeaseOrSequence"})
    case State{saved,lease,counter,nonce,capability,owner} True{}:
      menu_observed(lease,counter,nonce,capability,owner,True{},"",S.menu_inspect(saved))

def menu_inspect(state:State,epoch:String,sequence:Nat) -> State & Result<&2,&2,String,MenuOutcome>:
  State{saved,+lease,counter,nonce,capability,owner} = state
  menu_inspect_checked(State{saved,lease,counter,nonce,capability,owner},admitted(lease,epoch,sequence))

def transfer_status(result:S.State & Inv.TransferStatus) -> S.State & Result<&2,&2,String,Unit>:
  (saved,status) = result
  match status:
    case Inv.InvMoved{count}: (saved,Done{Unit{}})
    case Inv.InvRejected{reason}: (saved,Fail{Inv.error_name(reason)})

def transfer_checked(saved:S.State,source:U32,destination:U32,count:U32,mode:Inv.TransferMode,bounds:Bool) -> S.State & Result<&2,&2,String,Unit>:
  match bounds:
    case False{}: (saved,Fail{"inventory:main-slot"})
    case True{}: transfer_status(S.inventory_transfer(saved,source,destination,count,mode))

def transfer(state:State,epoch:String,sequence:Nat,+source:U32,+destination:U32,count:U32,mode:Inv.TransferMode) -> State & Result<&2,&2,String,MenuOutcome>:
  menu_mutation(state,epoch,sequence,saved => transfer_checked(saved,source,destination,count,mode,U32.is_lt(source,36) && U32.is_lt(destination,36)))

def acquire_checked(saved:S.State,index:U32,key:Inv.ItemKey,count:U32,bounds:Bool) -> S.State & Result<&2,&2,String,Unit>:
  match bounds:
    case False{}: (saved,Fail{"inventory:main-slot"})
    case True{}: S.inventory_acquire(saved,index,key,count)

def acquire(state:State,epoch:String,sequence:Nat,+index:U32,key:Inv.ItemKey,count:U32) -> State & Result<&2,&2,String,MenuOutcome>:
  menu_mutation(state,epoch,sequence,saved => acquire_checked(saved,index,key,count,U32.is_lt(index,36)))

def menu_open(state:State,epoch:String,sequence:Nat) -> State & Result<&2,&2,String,MenuOutcome>:
  menu_mutation(state,epoch,sequence,S.menu_open)

def select(state:State,epoch:String,sequence:Nat,index:U32) -> State & Result<&2,&2,String,MenuOutcome>:
  menu_mutation(state,epoch,sequence,saved => S.inventory_select(saved,index))

def menu_close(state:State,epoch:String,sequence:Nat) -> State & Result<&2,&2,String,MenuOutcome>:
  menu_mutation(state,epoch,sequence,S.menu_close)

def menu_click(state:State,epoch:String,sequence:Nat,index:U32,click:I.Click) -> State & Result<&2,&2,String,MenuOutcome>:
  menu_mutation(state,epoch,sequence,saved => S.menu_click(saved,index,click))

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

law rejected_menu_mutation_preserves_complete_actor:
  for state:State
  for operation:S.State -> S.State & Result<&2,&2,String,Unit>
  {menu_mutation_checked(state,operation,False{}) == (state,Fail{"RendererLeaseOrSequence"}) : State & Result<&2,&2,String,MenuOutcome>}
def rejected_menu_mutation_preserves_complete_actor(state,operation):
  match state:
    case State{saved,lease,counter,nonce,capability,owner}: {==}

law inadmissible_menu_call_preserves_complete_actor:
  for saved:S.State
  for +lease:Lease
  for counter:Nat
  for nonce:String
  for capability:String
  for owner:C.Capability
  for +epoch:String
  for +sequence:Nat
  for operation:S.State -> S.State & Result<&2,&2,String,Unit>
  for denied:{admitted(lease,epoch,sequence) == False{} : Bool}
  {menu_mutation(State{saved,lease,counter,nonce,capability,owner},epoch,sequence,operation) ==
    (State{saved,lease,counter,nonce,capability,owner},Fail{"RendererLeaseOrSequence"}) : State & Result<&2,&2,String,MenuOutcome>}
def inadmissible_menu_call_preserves_complete_actor(saved,lease,counter,nonce,capability,owner,epoch,sequence,operation,denied):
  %Equal.sym(Bool,admitted(lease,epoch,sequence),False{},denied) :
    {menu_mutation_checked(State{saved,lease,counter,nonce,capability,owner},operation,_) ==
      (State{saved,lease,counter,nonce,capability,owner},Fail{"RendererLeaseOrSequence"}) : State & Result<&2,&2,String,MenuOutcome>}
  {==}

# This gate precedes inventory reads and demand generation, so a denied
# retained player cannot change any owner in the actual saved session.
law rejected_action_owner_preserves_saved_session:
  for saved:S.State
  for owner:C.Capability
  for sequence:Nat
  for button:U32
  {action_owner_checked(saved,owner,sequence,button,False{}) ==
    (saved,BI.Outcome{False{},"interaction:permission-denied"}) : S.State & BI.Outcome}
def rejected_action_owner_preserves_saved_session(saved,owner,sequence,button):
  {==}

law unauthorized_action_preserves_saved_session:
  for saved:S.State
  for +owner:C.Capability
  for sequence:Nat
  for button:U32
  for denied:{Edit.player_peer(owner) == None{} : Maybe<&2,U32>}
  {action_requested(saved,owner,sequence,button) ==
    (saved,BI.Outcome{False{},"interaction:permission-denied"}) : S.State & BI.Outcome}
def unauthorized_action_preserves_saved_session(saved,owner,sequence,button,denied):
  %Equal.sym(Maybe<&2,U32>,Edit.player_peer(owner),None{},denied) :
    {action_owner_checked(saved,owner,sequence,button,Maybe.is_some(&2,U32,_)) ==
      (saved,BI.Outcome{False{},"interaction:permission-denied"}) : S.State & BI.Outcome}
  {==}
