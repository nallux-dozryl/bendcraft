import Base
import ./remote_resource_backend.bend as B
import ./resource_client_wire.bend as W
import ./world_visibility.bend as V
import ./server.bend as S
import ./framing.bend as F

# The socket remembers its assigned epoch. Cleanup never trusts an incoming
# request's epoch, so a stale socket cannot clear a newer renderer's controls.
type Link is Type:
  Link{socket:Socket,buffer:F.Buffer,epoch:String,deadline:Nat}
type Answer is Data:
  Answer{reply:W.Reply,assigned:String,keep:Bool}

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

def command(state:B.State,+epoch:String,+sequence:Nat,value:W.Command) -> B.State & Answer:
  match value:
    case W.Frame{width,height}: frame_answer(epoch,sequence,B.frame(state,epoch,sequence,width,height))
    case W.Input{packet}: unit_answer(epoch,sequence,B.input(state,epoch,sequence,packet))
    case W.Release{}: unit_answer(epoch,sequence,B.release(state,epoch,sequence))

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
        value : Answer <- S.local_call(B.State,Answer,handle,state => command(state,epoch,sequence,value))
        answer(handle,link,value)

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
    case Link{socket,buffer,epoch,deadline} True{}: fed(handle,socket,epoch,deadline,F.feed(buffer,bytes))

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
