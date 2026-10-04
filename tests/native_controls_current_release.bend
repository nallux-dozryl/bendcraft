import Base
import ../src/client_controls.bend as CC
import ../src/player_controls.bend as C
import ../src/player_input.bend as PI
import ./player_controls.bend as Fixture

# This observer uses the complete existing raw controller/packet fixture parser.
# It publishes full native words for unconditional release and unchanged atomic
# input. On refusal the fixture reporter echoes its supplied prior controller;
# this is a controller observation, not a runtime-owner commit observation.
def json_bool(value:Bool) -> String:
  match value:
    case True{}: "true"
    case False{}: "false"

def observe(+controller:C.Controller,+bindings:PI.Bindings,+packet:CC.Packet) -> String:
  CC.Packet{+actions,+focused,+captured} = packet
  +packet : CC.Packet = CC.Packet{actions,focused,captured}
  +released = C.release_packet(controller,packet)
  +canonical = C.capture_release(controller)
  "{\"requested\":" ++ json_bool(C.release_requested(actions)) ++
    ",\"released\":" ++ Fixture.controller_words(released) ++
    ",\"repeated\":" ++ Fixture.controller_words(C.release_packet(released,packet)) ++
    ",\"canonical\":" ++ Fixture.controller_words(canonical) ++
    ",\"ordinary\":" ++ Fixture.report(C.apply(controller,bindings,packet),controller) ++
    ",\"after_release\":" ++ Fixture.report(C.apply(released,bindings,packet),released) ++ "}"

def packets(pending:List<&2,CC.Packet>,+bindings:PI.Bindings,+controller:C.Controller) -> IO(Unit):
  match pending:
    case Nil{}: IO.pure(Unit,Unit{})
    case +packet <> rest:
      do IO<Unit>:
        IO.print(observe(controller,bindings,packet))
        packets(rest,bindings,C.release_packet(controller,packet))

def fixture(value:Maybe<&2,Fixture.Fixture>) -> IO(Unit):
  match value:
    case Some{Fixture.PacketFixture{controller,bindings,pending}}: packets(pending,bindings,controller)
    case Some{Fixture.ReleaseFixture{controller}}: IO.print(Fixture.controller_words(C.capture_release(controller)))
    case None{}: IO.die(Unit,2,"invalid unconditional release fixture")

def batch(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case arg <> rest:
      do IO<Unit>:
        fixture(Fixture.fixture_numbers(Fixture.numbers(String.split(arg,'|'))))
        batch(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    batch(List.tail(&1,String,args))
