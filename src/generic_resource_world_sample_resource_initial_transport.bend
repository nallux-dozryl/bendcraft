import Base
import ./generic_resource_world_sample_resource_transport.bend as Transport
import ./generic_resource_world_sample_resources.bend as Resources
import ./generic_resource_world_sample_resource_policy.bend as Policy
import ./generic_resource_world_sample_presenter.bend as Draw
import ./remote_resource_presenter.bend as P
import ./registry.bend as Registry
import ./resource_block_catalog.bend as Catalog
import ./resource_block_catalog_profile.bend as Profile
import ./resource_catalog_world.bend as CW
import ./resource_frame.bend as RF

# Initial loading has no previous resource Session. Keep an actually loaded
# Registry on catalog refusal; successful construction owns it with CW.Assets.
type Outcome is Type:
  Loaded{session:Resources.Session}
  Failed{registry:Maybe<&1,Registry.Registry>,message:String}
type Message is Type:
  Pulse{}
  Completed{value:Outcome}

def catalog_loaded(jar:String,value:Registry.Registry & Result<&2,&1,Catalog.Error,CW.Assets>) -> Outcome:
  (registry,status) = value
  match status:
    case Fail{error}: Failed{Some{registry},"resource catalog: " ++ Draw.error_text(error)}
    case Done{assets}:
      Loaded{Resources.installed(registry,Profile.static_requests(),assets,Policy.config(jar))}

def registry_loaded(+jar:String,value:Result<&2,&1,Registry.Error,Registry.Registry>) -> IO(Outcome):
  match value:
    case Fail{error}: IO.pure(Outcome,Failed{None{},"registry: " ++ Registry.error_text(error)})
    case Done{registry}:
      do IO<Outcome>:
        value:Registry.Registry & Result<&2,&1,Catalog.Error,CW.Assets> <-
          RF.catalog_load(jar,registry,Profile.static_requests(),Policy.materials(),Catalog.defaults())
        return catalog_loaded(jar,value)

def close(value:Outcome) -> IO(Unit):
  match value:
    case Loaded{session}: Resources.close(session)
    case Failed{registry,message}: IO.pure(Unit,Unit{})

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

def work(mail:Chan(Message),jar:String,path:String) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(0)
    registry:Result<&2,&1,Registry.Error,Registry.Registry> <- Registry.Registry.load(path)
    result:Outcome <- registry_loaded(jar,registry)
    sent:Bool <- Chan.send(Message,mail,Completed{result})
    return Unit{}

# Closing a channel preserves buffered messages. Consume any late pulse and
# dispose any extra complete resource owner before returning to the entry.
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
      do IO<Unit>:
        close(result)
        drain(mail)

@unsafe
def receive(+mail:Chan(Message),link:P.Link) -> IO(P.Link & Outcome):
  do IO<P.Link & Outcome>:
    value:Maybe<&1,Message> <- Chan.recv(Message,mail)
    received(value,mail,link)

def received(value:Maybe<&1,Message>,+mail:Chan(Message),link:P.Link) -> IO(P.Link & Outcome):
  match value:
    case None{}:
      do IO<P.Link & Outcome>:
        P.close_link(link)
        IO.die(P.Link & Outcome,1,"initial resource load result channel closed")
    case Some{Completed{result}}:
      do IO<P.Link & Outcome>:
        Chan.close(Message,mail)
        drain(mail)
        return (link,result)
    case Some{Pulse{}}:
      do IO<P.Link & Outcome>:
        next:P.Link <- Transport.heartbeat(link)
        receive(mail,next)

# The caller owns Link exclusively. Every cold Registry/catalog load runs in
# the resource worker; only this receive loop sends release-only heartbeats.
# Dead Link still receives/drains the complete affine worker outcome.
def load(link:P.Link,jar:String,path:String) -> IO(P.Link & Outcome):
  do IO<P.Link & Outcome>:
    next:P.Link <- Transport.heartbeat(link)
    +mail:Chan(Message) <- Chan.new(Message,2)
    IO.spawn(Unit,pulse(mail))
    IO.spawn(Unit,work(mail,jar,path))
    receive(mail,next)
