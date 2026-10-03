import Base
import ../src/json.bend as J
import ../src/live.bend as L
import ../src/core.bend as C

def trace_clock(pair: C.World & C.Clock, +session: L.Session, response: J.Value) -> C.World & L.Session & J.Value:
  (w, clock) = pair
  (w, session, L.obj([J.JMember{"response", response}, J.JMember{"session", L.obj([
    J.JMember{"peer", L.uint(L.peer(session))}, J.JMember{"sequence", L.natural(L.sequence(session))},
    J.JMember{"mode", L.text(L.mode_name(L.capability(session)))}])}, J.JMember{"clock", L.clock_value(clock)}]))

def trace(result: C.World & L.Session & J.Value) -> C.World & L.Session & J.Value:
  (w, session, response) = result
  trace_clock(C.clock(w), session, response)

def parse_dispatch(result: Result<&2, &2, String, J.Value>, w: C.World, session: L.Session, token: String) -> C.World & L.Session & J.Value:
  match result:
    case Fail{message}: L.failure(w, session, "", L.bad("ParseError", message))
    case Done{request}: L.dispatch(w, session, token, request)

def print_if(emit: Bool, output: J.Value) -> IO(Unit):
  match emit:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: IO.print(J.encode(output))

def run_requests(requests: List<String>, current: C.World & L.Session & J.Value, +token: String, emit: Bool) -> IO(Unit):
  match requests:
    case Nil{}:
      (w, session, output) = current
      print_if(emit, output)
    case request <> tail:
      (w, session, output) = current
      do IO<Unit>:
        print_if(emit, output)
        run_requests(tail, trace(parse_dispatch(J.parse(request), w, session, token)), token, True{})

def response_text(pair: C.World & L.Session & J.Value) -> String:
  (w, session, response) = pair
  J.encode(response)

def ping_fixture() -> String:
  response_text(L.dispatch(C.new(16), L.new_session(7), "fixture-token", L.obj([
    J.JMember{"id", L.text("p")}, J.JMember{"op", L.text("ping")} ])))

law ping_fixture_checked:
  {ping_fixture() == "{\"id\":\"p\",\"ok\":true,\"result\":{\"version\":\"26.3\",\"peer\":7,\"sequence\":1,\"mode\":\"observer\"}}" : String}

def ping_fixture_checked():
  {==}

def denied_fixture() -> String:
  response_text(L.dispatch(C.new(16), L.new_session(7), "fixture-token", L.obj([
    J.JMember{"id", L.text("c")}, J.JMember{"op", L.text("world.clock")} ])))

law denied_fixture_checked:
  {denied_fixture() == "{\"id\":\"c\",\"ok\":false,\"error\":{\"code\":\"PermissionDenied\",\"message\":\"developer capability required\"}}" : String}

def denied_fixture_checked():
  {==}

# Fill the queue only through real authenticated dispatch; no fabricated pending state.
def capacity_request() -> J.Value:
  L.obj([J.JMember{"id", L.text("capacity")}, J.JMember{"op", L.text("world.time.set")},
    J.JMember{"args", L.obj([J.JMember{"day_time", L.uint(0)}])}])

def capacity_fill(fuel: Nat, current: C.World & L.Session & J.Value) -> C.World & L.Session & J.Value:
  match fuel:
    case 0n:
      (w, session, prior) = current
      trace(L.dispatch(w, session, "fixture-token", capacity_request()))
    case 1n+rest:
      (w, session, prior) = current
      capacity_fill(rest, L.dispatch(w, session, "fixture-token", capacity_request()))

def capacity_fixture() -> String:
  response_text(capacity_fill(4096n, L.dispatch(C.new(16), L.new_session(7), "fixture-token", L.obj([
    J.JMember{"id", L.text("open")}, J.JMember{"op", L.text("session.open")},
    J.JMember{"args", L.obj([J.JMember{"mode", L.text("developer")}, J.JMember{"token", L.text("fixture-token")}])}]))))

def args_main(args: List<String>) -> IO(Unit):
  match args:
    case "capacity" <> Nil{}: IO.print(capacity_fixture())
    case token <> requests: run_requests(requests, (C.new(16), L.new_session(7), J.JNull{}), token, False{})
    case _: IO.die(Unit, 2, "usage: live-tests CONFIGURED_FIXTURE_TOKEN JSON_REQUEST...")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    args_main(List.tail(&1, String, args))
