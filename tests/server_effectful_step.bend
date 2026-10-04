import Base
import ../src/server.bend as S
import ../src/live.bend as L
import ../src/json.bend as J

type Counts is Type:
  Counts{value:U32}

def counted(state:Counts) -> IO(Counts):
  Counts{value} = state
  do IO<Counts>:
    IO.sleep(5)
    return Counts{U32.inc(value)}

def dispatched(state:Counts,session:L.Session,token:String,request:J.Value) -> IO(Counts & L.Session & J.Value):
  IO.pure(Counts & L.Session & J.Value,(state,session,request))

def read(state:Counts) -> Counts & U32:
  Counts{+value} = state
  (Counts{value},value)

def checked(value:U32) -> IO(Unit):
  match value:
    case 2: IO.print("effectful pulses complete before the following local snapshot")
    case _: IO.die(Unit,1,"effectful actor lost pulse order or owner")

def main() -> IO(Unit):
  do IO<Unit>:
    +mail : Chan(S.Message<Counts>) <- Chan.new(S.Message<Counts>,64)
    IO.spawn(Unit,S.actor(~Counts,~S.EffectfulStepDriver{counted,dispatched},mail,"",Counts{0}))
    first : Bool <- Chan.send(S.Message<Counts>,mail,S.Pulse{})
    second : Bool <- Chan.send(S.Message<Counts>,mail,S.Pulse{})
    value : U32 <- S.local_call(Counts,U32,S.Handle{mail},read)
    checked(value)
    S.stop(Counts,S.Handle{mail})
