import Base
import ./remote_resource_backend.bend as B
import ./resource_client_wire.bend as W
import ./world_visibility.bend as V
import ./generic_resource_world_sample.bend as GS
import ./generic_resource_world_sample_backend.bend as GenericBackend
import ./server.bend as S
import ./framing.bend as F
import ./resource_client_framing.bend as PrivateFraming
import ./player_inventory.bend as I
import ./player_block_interaction.bend as BI
import ./local_player_session.bend as Session
import ./player_crafting_session_adapter.bend as Craft
import ./item_component_wire_candidate.bend as Candidate
import ./core.bend as Core
import ./player_cooking_menu.bend as PCMenu
import ./player_cooking_session.bend as CookingSession
import ./remote_entity_frame.bend as EntityFrame
import ./remote_entity_scene_backend.bend as EntityBackend

# The socket remembers its assigned epoch. Cleanup never trusts an incoming
# request's epoch, so a stale socket cannot clear a newer renderer's controls.
type Link is Type:
  Link{socket:Socket,buffer:F.Buffer,epoch:String,deadline:Nat}
type Answer is Data:
  Answer{reply:W.Reply,assigned:String,keep:Bool}
type PreparedAnswer is Data:
  PreparedAnswer{answer:Answer,encoding:Result<&2,&2,String,String>}
type MenuRollback is Type:
  MenuRollback{inventory:I.State,lease:B.Lease,crafting:Maybe<&2,Craft.Context>,cooking:PCMenu.Handle,next_cooking_menu:U32}

def hello_answer(result:B.State & Result<&2,&2,String,String>) -> B.State & Answer:
  (state,status) = result
  match status:
    case Fail{message}: (state,Answer{W.Fault{"",0n,message},"",False{}})
    case Done{+epoch}: (state,Answer{W.HelloAck{epoch,0n},epoch,True{}})

def unit_answer(+epoch:String,sequence:Nat,result:B.State & Result<&2,&2,String,Unit>) -> B.State & Answer:
  (state,status) = result
  match status:
    case Fail{message}: (state,Answer{W.Fault{epoch,sequence,message},"",False{}})
    case Done{unit}: (state,Answer{W.Ack{epoch,sequence},epoch,True{}})

def frame_answer(+epoch:String,sequence:Nat,result:B.State & Result<&2,&2,String,V.Sample>) -> B.State & Answer:
  (state,status) = result
  match status:
    case Fail{message}: (state,Answer{W.Fault{epoch,sequence,message},"",False{}})
    case Done{sample}: (state,Answer{W.FrameReply{epoch,sequence,sample},epoch,True{}})

def catalog_frame_answer(+epoch:String,sequence:Nat,result:B.State & Result<&2,&2,String,GS.Sample>) -> B.State & Answer:
  (state,status) = result
  match status:
    case Fail{message}: (state,Answer{W.Fault{epoch,sequence,message},"",False{}})
    case Done{sample}: (state,Answer{W.CatalogFrameReply{epoch,sequence,sample},epoch,True{}})

def scene_frame_answer(+epoch:String,sequence:Nat,result:B.State & Result<&2,&2,String,EntityFrame.Frame>) -> B.State & Answer:
  (state,status) = result
  match status:
    case Fail{message}: (state,Answer{W.Fault{epoch,sequence,message},epoch,False{}})
    case Done{frame}: (state,Answer{W.SceneFrameReply{epoch,sequence,frame},epoch,True{}})

def inventory_answer(+epoch:String,sequence:Nat,result:B.State & Result<&2,&2,String,I.Snapshot>) -> B.State & Answer:
  (state,status) = result
  match status:
    case Fail{message}: (state,Answer{W.Fault{epoch,sequence,message},"",False{}})
    case Done{snapshot}: (state,Answer{W.InventoryReply{epoch,sequence,snapshot},epoch,True{}})

def action_answer(+epoch:String,sequence:Nat,result:B.State & Result<&2,&2,String,BI.Outcome>) -> B.State & Answer:
  (state,status) = result
  match status:
    case Fail{message}: (state,Answer{W.Fault{epoch,sequence,message},"",False{}})
    case Done{BI.Outcome{changed,message}}: (state,Answer{W.ActionReply{epoch,sequence,changed,message},epoch,True{}})

def menu_answer(+epoch:String,sequence:Nat,result:B.State & Result<&2,&2,String,B.MenuOutcome>) -> B.State & Answer:
  (state,status) = result
  match status:
    case Fail{message}: (state,Answer{W.Fault{epoch,sequence,message},"",False{}})
    case Done{B.MenuOutcome{accepted,message,snapshot}}:
      (state,Answer{W.MenuReply{epoch,sequence,accepted,message,snapshot},epoch,True{}})

def cooking_wire(+epoch:String,+sequence:Nat,reply:PCMenu.Reply) -> W.Reply:
  PCMenu.Reply{accepted,message,snapshot,effects} = reply
  W.CookingReply{epoch,sequence,accepted,message,snapshot}

def cooking_admitted(result:Result<&2,&2,String,String>) -> Result<&2,&2,String,Unit>:
  match result:
    case Fail{message}: Fail{"cooking-menu:prospective-reply-refused"}
    case Done{encoded}: Done{Unit{}}

def cooking_admit(epoch:String,sequence:Nat,reply:PCMenu.Reply) -> Result<&2,&2,String,Unit>:
  cooking_admitted(W.encode_reply(cooking_wire(epoch,sequence,reply)))

def cooking_answer(+epoch:String,+sequence:Nat,result:B.State & Result<&2,&2,String,PCMenu.Reply>) -> B.State & Answer:
  (state,status) = result
  match status:
    case Fail{message}: (state,Answer{W.Fault{epoch,sequence,message},epoch,False{}})
    case Done{reply}: (state,Answer{cooking_wire(epoch,sequence,reply),epoch,True{}})

def cooking_command(state:B.State,+epoch:String,+sequence:Nat,request:CookingSession.Request) -> B.State & Answer:
  cooking_answer(epoch,sequence,B.cooking_request(state,epoch,sequence,request,reply => cooking_admit(epoch,sequence,reply)))

def command(state:B.State,+epoch:String,+sequence:Nat,value:W.Command) -> B.State & Answer:
  match value:
    case W.Frame{width,height}: frame_answer(epoch,sequence,B.frame(state,epoch,sequence,width,height))
    case W.FrameCatalog{width,height}: catalog_frame_answer(epoch,sequence,GenericBackend.frame(state,epoch,sequence,width,height,GS.defaults()))
    case W.SceneFrame{width,height,partial}: scene_frame_answer(epoch,sequence,EntityBackend.frame(state,epoch,sequence,width,height,GS.defaults(),partial))
    case W.Input{packet}: unit_answer(epoch,sequence,B.input(state,epoch,sequence,packet))
    case W.Release{}: unit_answer(epoch,sequence,B.release(state,epoch,sequence))
    case W.Action{button}: action_answer(epoch,sequence,B.action(state,epoch,sequence,button))
    case W.Hotbar{index}: unit_answer(epoch,sequence,B.hotbar(state,epoch,sequence,index))
    case W.Inventory{}: inventory_answer(epoch,sequence,B.inventory(state,epoch,sequence))
    case W.Transfer{source,destination,count,mode}: menu_answer(epoch,sequence,B.transfer(state,epoch,sequence,source,destination,count,mode))
    case W.Acquire{index,key,count}: menu_answer(epoch,sequence,B.acquire(state,epoch,sequence,index,key,count))
    case W.MenuInspect{}: menu_answer(epoch,sequence,B.menu_inspect(state,epoch,sequence))
    case W.MenuOpen{}: menu_answer(epoch,sequence,B.menu_open(state,epoch,sequence))
    case W.MenuClose{}: menu_answer(epoch,sequence,B.menu_close(state,epoch,sequence))
    case W.MenuClick{index,click}: menu_answer(epoch,sequence,B.menu_click(state,epoch,sequence,index,click))
    case W.Select{index}: menu_answer(epoch,sequence,B.select(state,epoch,sequence,index))
    case W.CookingOpen{position}: cooking_command(state,epoch,sequence,CookingSession.Open{position})
    case W.CookingInspect{menu}: cooking_command(state,epoch,sequence,CookingSession.Act{PCMenu.MenuInspect{menu}})
    case W.CookingClick{menu,index,button}: cooking_command(state,epoch,sequence,CookingSession.Act{PCMenu.MenuPickup{menu,index,button}})
    case W.CookingQuickMove{menu,index}: cooking_command(state,epoch,sequence,CookingSession.Act{PCMenu.MenuQuickMove{menu,index}})
    case W.CookingClose{menu}: cooking_command(state,epoch,sequence,CookingSession.Act{PCMenu.MenuClose{menu}})
    case W.CookingUse{offhand}: cooking_command(state,epoch,sequence,CookingSession.Use{offhand,sequence})

# These commands own only inventory, immutable recipe context and the lease.
# A frame, world edit or physical packet must never use inventory-only rollback.
def prospective_menu(value:W.Command) -> Bool:
  match value:
    case W.Transfer{source,destination,count,mode}: True{}
    case W.Acquire{index,key,count}: True{}
    case W.MenuInspect{}: True{}
    case W.MenuOpen{}: True{}
    case W.MenuClose{}: True{}
    case W.MenuClick{index,click}: True{}
    case W.Select{index}: True{}
    case _: False{}

def answer_reply(value:Answer) -> W.Reply:
  Answer{reply,assigned,keep} = value
  reply

def prepared(result:B.State & Answer) -> B.State & PreparedAnswer:
  (state,+value) = result
  (state,PreparedAnswer{value,W.encode_reply(answer_reply(value))})

def candidate_saved(+lease:B.Lease,counter:Nat,nonce:String,capability:String,owner:Core.Capability,
    +crafting:Maybe<&2,Craft.Context>,+cooking:PCMenu.Handle,+next_cooking_menu:U32,result:Session.State & I.State) -> B.State & MenuRollback:
  (saved,original) = result
  (B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu},MenuRollback{original,lease,crafting,cooking,next_cooking_menu})

def menu_candidate(state:B.State) -> B.State & MenuRollback:
  B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu} = state
  candidate_saved(lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu,Session.inventory_query(I.State,saved,Candidate.prepare))

def restored_inventory(original:I.State,candidate:I.State) -> I.State & Unit:
  (original,Unit{})

def restored_saved(lease:B.Lease,counter:Nat,nonce:String,capability:String,owner:Core.Capability,
    crafting:Maybe<&2,Craft.Context>,cooking:PCMenu.Handle,next_cooking_menu:U32,result:Session.State & Unit) -> B.State:
  (saved,unit) = result
  B.State{saved,B.renewed(lease),counter,nonce,capability,owner,crafting,cooking,next_cooking_menu}

def restore_menu(rollback:MenuRollback,candidate:B.State) -> B.State:
  MenuRollback{original,lease,crafting,cooking,next_cooking_menu} = rollback
  B.State{saved,new_lease,counter,nonce,capability,owner,new_crafting,new_cooking,new_next_cooking_menu} = candidate
  restored_saved(lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu,
    Session.inventory_query(Unit,saved,discarded => restored_inventory(original,discarded)))

def fallback_encoded(+epoch:String,+sequence:Nat,state:B.State,+value:Answer,
    encoding:Result<&2,&2,String,String>) -> B.State & PreparedAnswer:
  match encoding:
    case Done{text}: (state,PreparedAnswer{value,Done{text}})
    case Fail{message}:
      prepared((state,Answer{W.Fault{epoch,sequence,"Wire:InventoryReplyEncoding"},epoch,False{}}))

def fallback_observed(+epoch:String,+sequence:Nat,lease:B.Lease,counter:Nat,nonce:String,capability:String,
    owner:Core.Capability,crafting:Maybe<&2,Craft.Context>,cooking:PCMenu.Handle,next_cooking_menu:U32,result:Session.State & I.MenuSnapshot) -> B.State & PreparedAnswer:
  (saved,snapshot) = result
  +value:Answer = Answer{W.MenuReply{epoch,sequence,False{},"inventory:prospective-reply-refused",snapshot},epoch,True{}}
  fallback_encoded(epoch,sequence,B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu},value,W.encode_reply(answer_reply(value)))

# Observation of the restored owner does not refresh or replace its cache.
def menu_fallback(+epoch:String,+sequence:Nat,state:B.State) -> B.State & PreparedAnswer:
  B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu} = state
  fallback_observed(epoch,sequence,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu,
    Session.inventory_query(I.MenuSnapshot,saved,Candidate.inspect))

def prospective_encoded(epoch:String,sequence:Nat,rollback:MenuRollback,candidate:B.State,value:Answer,
    encoding:Result<&2,&2,String,String>) -> B.State & PreparedAnswer:
  match encoding:
    case Done{text}: (candidate,PreparedAnswer{value,Done{text}})
    case Fail{message}: menu_fallback(epoch,sequence,restore_menu(rollback,candidate))

def prospective_completed(epoch:String,sequence:Nat,rollback:MenuRollback,result:B.State & Answer) -> B.State & PreparedAnswer:
  (candidate,+value) = result
  prospective_encoded(epoch,sequence,rollback,candidate,value,W.encode_reply(answer_reply(value)))

def prospective_geometry(+epoch:String,+sequence:Nat,value:W.Command,rollback:MenuRollback,
    result:B.State & Bool) -> B.State & PreparedAnswer:
  (candidate,valid) = result
  match valid:
    case False{}: menu_fallback(epoch,sequence,restore_menu(rollback,candidate))
    case True{}: prospective_completed(epoch,sequence,rollback,command(candidate,epoch,sequence,value))

def geometry_saved(lease:B.Lease,counter:Nat,nonce:String,capability:String,owner:Core.Capability,
    crafting:Maybe<&2,Craft.Context>,cooking:PCMenu.Handle,next_cooking_menu:U32,result:Session.State & Bool) -> B.State & Bool:
  (saved,valid) = result
  (B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu},valid)

def menu_geometry(state:B.State) -> B.State & Bool:
  B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu} = state
  geometry_saved(lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu,Session.inventory_query(Bool,saved,Candidate.geometry))

def prospective_cloned(+epoch:String,+sequence:Nat,value:W.Command,result:B.State & MenuRollback) -> B.State & PreparedAnswer:
  (candidate,rollback) = result
  # Invoke the real command once. Reply admission precedes actor publication.
  prospective_geometry(epoch,sequence,value,rollback,menu_geometry(candidate))

def prospective_checked(state:B.State,+epoch:String,+sequence:Nat,+value:W.Command,admitted:Bool) -> B.State & PreparedAnswer:
  match admitted:
    case False{}: prepared(command(state,epoch,sequence,value))
    case True{}: prospective_cloned(epoch,sequence,value,menu_candidate(state))

def command_prepared(state:B.State,+epoch:String,+sequence:Nat,+value:W.Command) -> B.State & PreparedAnswer:
  B.State{saved,+lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu} = state
  prospective_checked(B.State{saved,lease,counter,nonce,capability,owner,crafting,cooking,next_cooking_menu},epoch,sequence,value,
    prospective_menu(value) && B.admitted(lease,epoch,sequence))

def close_link(+handle:S.Handle<B.State>,link:Link) -> IO(Maybe<&1,Link>):
  Link{socket,buffer,epoch,deadline} = link
  do IO<Maybe<&1,Link>>:
    Socket.close(socket)
    released : Unit <- S.local_call(B.State,Unit,handle,state => B.disconnect(state,epoch))
    return None{}

def sent_status(+handle:S.Handle<B.State>,buffer:F.Buffer,old:String,assigned:String,socket:Socket,
    status:Result<&1,&1,U32 & String,Unit>,keep:Bool) -> IO(Maybe<&1,Link>):
  match status keep:
    case Done{unit} True{}:
      do IO<Maybe<&1,Link>>:
        now : Nat <- IO.now()
        return Some{Link{socket,buffer,assigned,5000n+now}}
    case Fail{cause} True{}: close_link(handle,Link{socket,buffer,assigned,0n})
    case _ _: close_link(handle,Link{socket,buffer,old,0n})

def sent(handle:S.Handle<B.State>,buffer:F.Buffer,old:String,assigned:String,keep:Bool,
    result:Socket & Result<&1,&1,U32 & String,Unit>) -> IO(Maybe<&1,Link>):
  (socket,status) = result
  sent_status(handle,buffer,old,assigned,socket,status,keep)

def encoding_failed(handle:S.Handle<B.State>,link:Link,assigned:String,keep:Bool) -> IO(Maybe<&1,Link>):
  match link keep:
    case Link{socket,buffer,epoch,deadline} True{}: close_link(handle,Link{socket,buffer,assigned,deadline})
    case _ False{}: close_link(handle,link)

def encoded(+handle:S.Handle<B.State>,link:Link,assigned:String,keep:Bool,result:Result<&2,&2,String,String>) -> IO(Maybe<&1,Link>):
  match link result:
    case Link{socket,buffer,epoch,deadline} Fail{message}:
      encoding_failed(handle,Link{socket,buffer,epoch,deadline},assigned,keep)
    case Link{socket,buffer,epoch,deadline} Done{text}:
      do IO<Maybe<&1,Link>>:
        written : Socket & Result<&1,&1,U32 & String,Unit> <- TCP.send(socket,text ++ "\n")
        sent(handle,buffer,epoch,assigned,keep,written)

def answer(+handle:S.Handle<B.State>,link:Link,value:Answer) -> IO(Maybe<&1,Link>):
  Answer{reply,assigned,keep} = value
  encoded(handle,link,assigned,keep,W.encode_reply(reply))

def prepared_answer(handle:S.Handle<B.State>,link:Link,value:PreparedAnswer) -> IO(Maybe<&1,Link>):
  PreparedAnswer{Answer{reply,assigned,keep},encoding} = value
  encoded(handle,link,assigned,keep,encoding)

def hello_allowed(+handle:S.Handle<B.State>,link:Link,capability:String,allowed:Bool) -> IO(Maybe<&1,Link>):
  match allowed:
    case False{}: answer(handle,link,Answer{W.Fault{"",0n,"Wire:DuplicateHello"},"",False{}})
    case True{}:
      do IO<Maybe<&1,Link>>:
        value : Answer <- S.local_call(B.State,Answer,handle,state => hello_answer(B.hello(state,capability)))
        answer(handle,link,value)

def call_allowed(+handle:S.Handle<B.State>,link:Link,+epoch:String,+sequence:Nat,value:W.Command,allowed:Bool) -> IO(Maybe<&1,Link>):
  match allowed:
    case False{}: answer(handle,link,Answer{W.Fault{epoch,sequence,"Wire:SocketEpoch"},"",False{}})
    case True{}:
      do IO<Maybe<&1,Link>>:
        value : PreparedAnswer <- S.local_call(B.State,PreparedAnswer,handle,state => command_prepared(state,epoch,sequence,value))
        prepared_answer(handle,link,value)

def request_parsed(+handle:S.Handle<B.State>,link:Link,result:Result<&2,&2,String,W.Request>) -> IO(Maybe<&1,Link>):
  Link{socket,buffer,+assigned,deadline} = link
  match result:
    case Fail{message}:
      answer(handle,Link{socket,buffer,assigned,deadline},Answer{W.Fault{"",0n,"Wire:MalformedRequest"},"",False{}})
    case Done{W.Hello{capability}}:
      hello_allowed(handle,Link{socket,buffer,assigned,deadline},capability,String.is_empty(assigned))
    case Done{W.Call{+epoch,sequence,value}}:
      call_allowed(handle,Link{socket,buffer,assigned,deadline},epoch,sequence,value,
        Bool.not(String.is_empty(assigned)) && String.eq(assigned,epoch))

def request_ready(handle:S.Handle<B.State>,link:Link,result:Result<&2,&2,String,W.Request>,room:Bool) -> IO(Maybe<&1,Link>):
  match room:
    case False{}: close_link(handle,link)
    case True{}: request_parsed(handle,link,result)

def request(handle:S.Handle<B.State>,link:Link,result:Result<&2,&2,String,W.Request>) -> IO(Maybe<&1,Link>):
  Link{socket,buffer,epoch,+deadline} = link
  do IO<Maybe<&1,Link>>:
    now : Nat <- IO.now()
    request_ready(handle,Link{socket,buffer,epoch,deadline},result,Nat.is_lt(now,deadline))

def next(result:Maybe<&1,Link>,rest:Link -> IO(Maybe<&1,Link>)) -> IO(Maybe<&1,Link>):
  match result:
    case None{}: IO.pure(Maybe<&1,Link>,None{})
    case Some{link}: rest(link)

def line(+handle:S.Handle<B.State>,text:String,link:Link,rest:Link -> IO(Maybe<&1,Link>)) -> IO(Maybe<&1,Link>):
  do IO<Maybe<&1,Link>>:
    result : Maybe<&1,Link> <- request(handle,link,W.decode_request(text))
    next(result,rest)

def lines(+handle:S.Handle<B.State>,records:List<&2,String>,link:Link) -> IO(Maybe<&1,Link>):
  match records:
    case Nil{}: IO.pure(Maybe<&1,Link>,Some{link})
    case text <> tail: line(handle,text,link,l => lines(handle,tail,l))

def fed(+handle:S.Handle<B.State>,socket:Socket,epoch:String,deadline:Nat,
    result:Result<&1,&1,String,F.Buffer & List<&2,String>>) -> IO(Maybe<&1,Link>):
  match result:
    case Fail{message}: close_link(handle,Link{socket,F.new(),epoch,deadline})
    case Done{Tuple{buffer,records}}: lines(handle,records,Link{socket,buffer,epoch,deadline})

def ascii(bytes:List<&2,U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case +value <> tail: U32.is_lt(value,128) && ascii(tail)

def scalars(text:String) -> List<&2,U32>:
  match text:
    case SNil{}: []
    case SCon{Chr{value},tail}: value <> scalars(tail)

def segment_valid(+handle:S.Handle<B.State>,bytes:List<&2,U32>,link:Link,valid:Bool) -> IO(Maybe<&1,Link>):
  match link valid:
    case _ False{}: close_link(handle,link)
    case Link{socket,buffer,epoch,deadline} True{}: fed(handle,socket,epoch,deadline,PrivateFraming.feed(buffer,bytes))

def segment(+handle:S.Handle<B.State>,+bytes:List<&2,U32>,link:Link,rest:Link -> IO(Maybe<&1,Link>)) -> IO(Maybe<&1,Link>):
  do IO<Maybe<&1,Link>>:
    result : Maybe<&1,Link> <- segment_valid(handle,bytes,link,ascii(bytes))
    next(result,rest)

# Segment before ASCII admission: a malformed later record cannot erase a
# completed earlier request merely because TCP.poll returned them together.
def segments(+handle:S.Handle<B.State>,values:List<&2,List<&2,U32>>,link:Link) -> IO(Maybe<&1,Link>):
  match values:
    case Nil{}: IO.pure(Maybe<&1,Link>,Some{link})
    case bytes <> tail: segment(handle,bytes,link,l => segments(handle,tail,l))

def received_status(+handle:S.Handle<B.State>,buffer:F.Buffer,epoch:String,deadline:Nat,
    result:Socket & Result<&1,&1,U32 & String,Maybe<&1,String>>) -> IO(Maybe<&1,Link>):
  (socket,status) = result
  match status:
    case Done{Some{SCon{head,tail}}}:
      segments(handle,F.segments(scalars(SCon{head,tail})),Link{socket,buffer,epoch,deadline})
    case _: close_link(handle,Link{socket,buffer,epoch,deadline})

def received_late(handle:S.Handle<B.State>,buffer:F.Buffer,epoch:String,deadline:Nat,
    result:Socket & Result<&1,&1,U32 & String,Maybe<&1,String>>) -> IO(Maybe<&1,Link>):
  (socket,status) = result
  close_link(handle,Link{socket,buffer,epoch,deadline})

def received_ready(handle:S.Handle<B.State>,buffer:F.Buffer,epoch:String,deadline:Nat,
    result:Socket & Result<&1,&1,U32 & String,Maybe<&1,String>>,room:Bool) -> IO(Maybe<&1,Link>):
  match room:
    case True{}: received_status(handle,buffer,epoch,deadline,result)
    case False{}: received_late(handle,buffer,epoch,deadline,result)

def received(handle:S.Handle<B.State>,buffer:F.Buffer,epoch:String,+deadline:Nat,
    result:Socket & Result<&1,&1,U32 & String,Maybe<&1,String>>) -> IO(Maybe<&1,Link>):
  do IO<Maybe<&1,Link>>:
    now : Nat <- IO.now()
    received_ready(handle,buffer,epoch,deadline,result,Nat.is_lt(now,deadline))

@unsafe
def continued(+handle:S.Handle<B.State>,result:Maybe<&1,Link>) -> IO(Unit):
  match result:
    case None{}: IO.pure(Unit,Unit{})
    case Some{link}: read_loop(handle,link)

def read_ready(+handle:S.Handle<B.State>,link:Link,+now:Nat,room:Bool) -> IO(Unit):
  match link room:
    case _ False{}:
      do IO<Unit>:
        closed : Maybe<&1,Link> <- close_link(handle,link)
        return Unit{}
    case Link{socket,buffer,epoch,+deadline} True{}:
      do IO<Unit>:
        result : Socket & Result<&1,&1,U32 & String,Maybe<&1,String>> <- TCP.poll(socket,8192,U32.from_nat(Nat.sub(deadline,now)))
        next : Maybe<&1,Link> <- received(handle,buffer,epoch,deadline,result)
        continued(handle,next)

@unsafe
def read_loop(+handle:S.Handle<B.State>,link:Link) -> IO(Unit):
  Link{socket,buffer,epoch,+deadline} = link
  do IO<Unit>:
    +now : Nat <- IO.now()
    read_ready(handle,Link{socket,buffer,epoch,deadline},now,Nat.is_lt(now,deadline))

def accepted(+handle:S.Handle<B.State>,result:Listener & Result<&1,&1,U32 & String,Socket>) -> IO(Listener):
  (listener,status) = result
  do IO<Listener>:
    socket : Socket <- IO.pass(Socket,status)
    now : Nat <- IO.now()
    IO.spawn(Unit,read_loop(handle,Link{socket,F.new(),"",5000n+now}))
    return listener

@unsafe
def accept_loop(+handle:S.Handle<B.State>,listener:Listener) -> IO(Unit):
  do IO<Unit>:
    result : Listener & Result<&1,&1,U32 & String,Socket> <- TCP.accept(listener)
    next : Listener <- accepted(handle,result)
    accept_loop(handle,next)

def start(handle:S.Handle<B.State>,+port:U32) -> IO(Unit):
  do IO<Unit>:
    listener : Listener <- IO.try(Listener,TCP.listen("127.0.0.1",port))
    IO.print("{\"event\":\"renderer.ready\",\"host\":\"127.0.0.1\",\"port\":" ++ U32.show(port) ++ ",\"protocol\":1}")
    IO.spawn(Unit,accept_loop(handle,listener))
