import Base
import ./generic_resource_world_sample_resources.bend as Resources
import ./resource_block_catalog.bend as C
import ./remote_resource_presenter.bend as P
import ./resource_client_wire.bend as Wire
import ./client_controls.bend as Controls

# The resource worker owns Session. The caller remains the sole owner of Link.
# One bounded channel carries timer pulses and the complete affine worker result.
type Message is Type:
  Pulse{}
  Completed{value:Resources.Session & Result<&2,&2,C.Error,Unit>}

@unsafe
def pulse(+mail:Chan(Message)) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(500)
    sent:Bool <- Chan.send(Message,mail,Pulse{})
    pulse_sent(sent,mail)

def pulse_sent(sent:Bool,mail:Chan(Message)) -> IO(Unit):
  match sent:
    case False{}: IO.pure(Unit,Unit{})
    case True{}: pulse(mail)

def work(mail:Chan(Message),value:Resources.Preparation,width:U32,height:U32) -> IO(Unit):
  do IO<Unit>:
    # Defer pure planning inside the spawned IO continuation as well as its IO.
    IO.sleep(0)
    result:Resources.Session & Result<&2,&2,C.Error,Unit> <- Resources.resolve(value,width,height)
    sent:Bool <- Chan.send(Message,mail,Completed{result})
    return Unit{}

def heartbeat_result(value:P.Link & Result<&2,&2,String,Wire.Reply>) -> IO(P.Link):
  (link,status) = value
  match status:
    case Done{Wire.Ack{epoch,sequence}}: IO.pure(P.Link,link)
    case Fail{message}:
      do IO<P.Link>:
        P.close_link(link)
        return P.Dead{message}
    case Done{other}:
      do IO<P.Link>:
        P.close_link(link)
        return P.Dead{"resource loading: Wire:ExpectedAck"}

def heartbeat(link:P.Link) -> IO(P.Link):
  match link:
    case P.Dead{message}: IO.pure(P.Link,P.Dead{message})
    case P.Open{socket,buffer,pending,epoch,sequence}:
      do IO<P.Link>:
        value:P.Link & Result<&2,&2,String,Wire.Reply> <-
          P.call(P.Open{socket,buffer,pending,epoch,sequence},Wire.Input{Controls.Packet{[],False{},False{}}})
        heartbeat_result(value)

# Chan.close rejects later sends but preserves already buffered messages. Drain
# those messages so a late timer pulse cannot leave a closed channel row alive.
@unsafe
def drain(+mail:Chan(Message)) -> IO(Unit):
  do IO<Unit>:
    value:Maybe<&1,Message> <- Chan.recv(Message,mail)
    drained(value,mail)

def drained(value:Maybe<&1,Message>,mail:Chan(Message)) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit,Unit{})
    case Some{Pulse{}}: drain(mail)
    case Some{Completed{result}}:
      (session,status) = result
      do IO<Unit>:
        Resources.close(session)
        drain(mail)

@unsafe
def receive(+mail:Chan(Message),link:P.Link) -> IO(P.Link & (Resources.Session & Result<&2,&2,C.Error,Unit>)):
  do IO<P.Link & (Resources.Session & Result<&2,&2,C.Error,Unit>)>:
    value:Maybe<&1,Message> <- Chan.recv(Message,mail)
    received(value,mail,link)

def received(value:Maybe<&1,Message>,+mail:Chan(Message),link:P.Link) -> IO(P.Link & (Resources.Session & Result<&2,&2,C.Error,Unit>)):
  match value:
    case None{}:
      do IO<P.Link & (Resources.Session & Result<&2,&2,C.Error,Unit>)>:
        P.close_link(link)
        IO.die(P.Link & (Resources.Session & Result<&2,&2,C.Error,Unit>),1,"resource load result channel closed")
    case Some{Completed{result}}:
      do IO<P.Link & (Resources.Session & Result<&2,&2,C.Error,Unit>)>:
        Chan.close(Message,mail)
        drain(mail)
        return (link,result)
    case Some{Pulse{}}:
      do IO<P.Link & (Resources.Session & Result<&2,&2,C.Error,Unit>)>:
        next:P.Link <- heartbeat(link)
        receive(mail,next)

# Network failure leaves a Dead Link but still drains the resource result. The
# ordinary client continuation then closes the returned complete resource owner.
def load(link:P.Link,value:Resources.Preparation,width:U32,height:U32) -> IO(P.Link & (Resources.Session & Result<&2,&2,C.Error,Unit>)):
  do IO<P.Link & (Resources.Session & Result<&2,&2,C.Error,Unit>)>:
    next:P.Link <- heartbeat(link)
    +mail:Chan(Message) <- Chan.new(Message,2)
    IO.spawn(Unit,pulse(mail))
    IO.spawn(Unit,work(mail,value,width,height))
    receive(mail,next)
