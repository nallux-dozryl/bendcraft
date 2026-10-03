import Base
import ./core.bend as C
import ./json.bend as J
import ./live.bend as L
import ./framing.bend as F

# Compile-time drivers permit complete typed replacement of owned simulation
# state and transition/operation semantics, without foreign plugins or boxed
# reusable closures. Transport remains shared across vanilla and overhauls.
type Driver<-State: Type> is Type:
  Driver{step: State -> State, dispatch: State -> L.Session -> String -> J.Value -> State & L.Session & J.Value}

# Effectful dispatch retains the state owner while persistence/other OS work
# completes. The pure Driver API is preserved through the adapter below.
type EffectfulDriver<-State: Type> is Type:
  EffectfulDriver{step: State -> State, dispatch: State -> L.Session -> String -> J.Value -> IO(State & L.Session & J.Value)}

def pure_step(-State: Type, driver: Driver<State>, world: State) -> State:
  Driver{step, dispatch} = driver
  step(world)

def pure_dispatch(-State: Type, driver: Driver<State>, world: State, session: L.Session, token: String, request: J.Value) -> IO(State & L.Session & J.Value):
  Driver{step, dispatch} = driver
  IO.pure(State & L.Session & J.Value, dispatch(world, session, token, request))

def core_dispatch(world: C.World, session: L.Session, token: String, request: J.Value) -> C.World & L.Session & J.Value:
  L.dispatch(world, session, token, request)

type Answer is Data:
  Answer{session: L.Session, value: J.Value}

type Message<-State: Type> is Type:
  Pulse{}
  Request{session: L.Session, value: J.Value, reply: Chan(Answer)}
  Local{operation: State -> IO(State)}
  Stop{reply: Chan(Unit)}

# Channels are duplicable capabilities; the world itself never leaves its
# single actor. Local operations are trusted compiled Bend code.
type Handle<-State: Type> is Data:
  Handle{mail: Chan(Message<State>)}

type Link is Type:
  Link{socket: Socket, buffer: F.Buffer, session: L.Session}

def actor_reply(-State: Type, reply: Chan(Answer), result: State & L.Session & J.Value, rest: State -> IO(Unit)) -> IO(Unit):
  (world, session, value) = result
  do IO<Unit>:
    sent : Bool <- Chan.send(Answer, reply, Answer{session, value})
    rest(world)

def actor_message(-State: Type, +mail: Chan(Message<State>), driver: EffectfulDriver<State>, +token: String, world: State, message: Maybe<&1, Message<State>>, rest: State -> IO(Unit)) -> IO(Unit):
  match driver message:
    case EffectfulDriver{step, dispatch} None{}:
      IO.pure(Unit, Unit{})
    case EffectfulDriver{step, dispatch} Some{Pulse{}}:
      rest(step(world))
    case EffectfulDriver{step, dispatch} Some{Request{session, value, reply}}:
      do IO<Unit>:
        result : State & L.Session & J.Value <- dispatch(world, session, token, value)
        actor_reply(State, reply, result, rest)
    case EffectfulDriver{step, dispatch} Some{Local{operation}}:
      do IO<Unit>:
        next : State <- operation(world)
        rest(next)
    case EffectfulDriver{step, dispatch} Some{Stop{reply}}:
      do IO<Unit>:
        Chan.close(Message<State>, mail)
        sent : Bool <- Chan.send(Unit, reply, Unit{})
        return Unit{}

# Only the OS-driven lifetime is unsafe. State transitions live in checked
# pure modules. One actor is the sole owner of the authoritative world.
@unsafe
def actor(~State: Type, ~driver: EffectfulDriver<State>, +mail: Chan(Message<State>), +token: String, world: State) -> IO(Unit):
  do IO<Unit>:
    message : Maybe<&1, Message<State>> <- Chan.recv(Message<State>, mail)
    actor_message(State, mail, driver, token, world, message, w => actor(~State, ~driver, mail, token, w))

def timer_sent(sent: Bool, rest: Unit -> IO(Unit)) -> IO(Unit):
  match sent:
    case True{}:
      rest(Unit{})
    case False{}:
      IO.pure(Unit, Unit{})

# Deadlines advance from the previous deadline, not sleep completion, so the
# timer does not accumulate request/compute latency as drift. Mail is bounded.
@unsafe
def timer(-State: Type, +mail: Chan(Message<State>), +deadline: Nat) -> IO(Unit):
  do IO<Unit>:
    now : Nat <- IO.now()
    IO.sleep(U32.from_nat(Nat.sub(deadline, now)))
    sent : Bool <- Chan.send(Message<State>, mail, Pulse{})
    timer_sent(sent, u => timer(State, mail, Nat.add(deadline, 50n)))

def sent_link(buffer: F.Buffer, session: L.Session, result: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Maybe<&1, Link>):
  (socket, status) = result
  match status:
    case Done{u}:
      IO.pure(Maybe<&1, Link>, Some{Link{socket, buffer, session}})
    case Fail{error}:
      do IO<Maybe<&1, Link>>:
        Socket.close(socket)
        return None{}

def send_value(socket: Socket, buffer: F.Buffer, session: L.Session, value: J.Value) -> IO(Maybe<&1, Link>):
  do IO<Maybe<&1, Link>>:
    result : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send(socket, J.encode(value) ++ "\n")
    sent_link(buffer, session, result)

def answered(socket: Socket, buffer: F.Buffer, answer: Answer) -> IO(Maybe<&1, Link>):
  Answer{session, value} = answer
  send_value(socket, buffer, session, value)

def request_sent(socket: Socket, buffer: F.Buffer, reply: Chan(Answer), sent: Bool) -> IO(Maybe<&1, Link>):
  match sent:
    case False{}:
      do IO<Maybe<&1, Link>>:
        Chan.close(Answer, reply)
        Socket.close(socket)
        return None{}
    case True{}:
      do IO<Maybe<&1, Link>>:
        answer : Answer <- IO.join(Answer, reply)
        answered(socket, buffer, answer)

def parse_error(message: String) -> J.Value:
  J.JObject{[J.JMember{"id", J.JNull{}}, J.JMember{"ok", J.JBool{False{}}},
    J.JMember{"error", J.JObject{[J.JMember{"code", J.JString{"invalid_json"}}, J.JMember{"message", J.JString{message}}]}}]}

def ask(-State: Type, +mail: Chan(Message<State>), socket: Socket, buffer: F.Buffer, session: L.Session, parsed: Result<&2, &2, String, J.Value>) -> IO(Maybe<&1, Link>):
  match parsed:
    case Fail{message}:
      send_value(socket, buffer, session, parse_error(message))
    case Done{value}:
      do IO<Maybe<&1, Link>>:
        reply : Chan(Answer) <- Chan.new(Answer, 1)
        +channel : Chan(Answer) = reply
        sent : Bool <- Chan.send(Message<State>, mail, Request{session, value, channel})
        request_sent(socket, buffer, channel, sent)

def line_next(result: Maybe<&1, Link>, rest: Link -> IO(Maybe<&1, Link>)) -> IO(Maybe<&1, Link>):
  match result:
    case None{}:
      IO.pure(Maybe<&1, Link>, None{})
    case Some{link}:
      rest(link)

def line_ask(-State: Type, text: String, +mail: Chan(Message<State>), link: Link, rest: Link -> IO(Maybe<&1, Link>)) -> IO(Maybe<&1, Link>):
  Link{socket, buffer, session} = link
  do IO<Maybe<&1, Link>>:
    result : Maybe<&1, Link> <- ask(State, mail, socket, buffer, session, J.parse(text))
    line_next(result, rest)

def lines(-State: Type, records: List<&2, String>, +mail: Chan(Message<State>), link: Link) -> IO(Maybe<&1, Link>):
  match records:
    case Nil{}:
      IO.pure(Maybe<&1, Link>, Some{link})
    case Con{text, tail}:
      line_ask(State, text, mail, link, l => lines(State, tail, mail, l))

def feed_result(-State: Type, +mail: Chan(Message<State>), socket: Socket, session: L.Session, fed: Result<&1, &1, String, F.Buffer & List<&2, String>>) -> IO(Maybe<&1, Link>):
  match fed:
    case Fail{error}:
      do IO<Maybe<&1, Link>>:
        Socket.close(socket)
        return None{}
    case Done{Tuple{buffer, records}}:
      lines(State, records, mail, Link{socket, buffer, session})

def feed_segment(-State: Type, bytes: List<&2, U32>, +mail: Chan(Message<State>), link: Link, rest: Link -> IO(Maybe<&1, Link>)) -> IO(Maybe<&1, Link>):
  Link{socket, buffer, session} = link
  do IO<Maybe<&1, Link>>:
    next : Maybe<&1, Link> <- feed_result(State, mail, socket, session, F.feed(buffer, bytes))
    line_next(next, rest)

# Apply complete records individually. A later malformed record cannot erase
# an earlier request merely because both arrived in the same TCP receive.
def feed_segments(-State: Type, segments: List<&2, List<&2, U32>>, +mail: Chan(Message<State>), link: Link) -> IO(Maybe<&1, Link>):
  match segments:
    case Nil{}:
      IO.pure(Maybe<&1, Link>, Some{link})
    case Con{bytes, tail}:
      feed_segment(State, bytes, mail, link, l => feed_segments(State, tail, mail, l))

def received(-State: Type, +mail: Chan(Message<State>), buffer: F.Buffer, session: L.Session, result: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Maybe<&1, Link>):
  (socket, status) = result
  match status:
    case Fail{error}:
      do IO<Maybe<&1, Link>>:
        Socket.close(socket)
        return None{}
    case Done{Nil{}}:
      do IO<Maybe<&1, Link>>:
        Socket.close(socket)
        return None{}
    case Done{bytes}:
      feed_segments(State, F.segments(bytes), mail, Link{socket, buffer, session})

def read_next(result: Maybe<&1, Link>, rest: Link -> IO(Unit)) -> IO(Unit):
  match result:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{link}:
      rest(link)

@unsafe
def read_loop(-State: Type, +mail: Chan(Message<State>), link: Link) -> IO(Unit):
  Link{socket, buffer, session} = link
  do IO<Unit>:
    result : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- TCP.recv_bytes(socket, 8192)
    next : Maybe<&1, Link> <- received(State, mail, buffer, session, result)
    read_next(next, l => read_loop(State, mail, l))

def accepted(-State: Type, +mail: Chan(Message<State>), peer: U32, result: Listener & Result<&1, &1, U32 & String, Socket>) -> IO(Listener):
  (listener, status) = result
  do IO<Listener>:
    socket : Socket <- IO.pass(Socket, status)
    IO.spawn(Unit, read_loop(State, mail, Link{socket, F.new(), L.new_session(peer)}))
    return listener

@unsafe
def accept_loop(-State: Type, +mail: Chan(Message<State>), listener: Listener, +peer: U32) -> IO(Unit):
  match peer:
    case 0:
      do IO<Unit>:
        IO.print_err("live peer identity range exhausted; listener closed")
        Listener.close(listener)
    case +actual:
      do IO<Unit>:
        result : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept(listener)
        next : Listener <- accepted(State, mail, actual, result)
        accept_loop(State, mail, next, U32.inc(actual))

def token_checked(token: String, empty: Bool) -> IO(String):
  match empty:
    case True{}:
      IO.die(String, 1, "MC_DEV_TOKEN must be nonempty")
    case False{}:
      IO.pure(String, token)

def required_token(result: Result<&1, &1, U32 & String, String>) -> IO(String):
  match result:
    case Fail{error}:
      IO.die(String, 1, "MC_DEV_TOKEN must be configured for the local developer API")
    case Done{+token}:
      token_checked(token, String.is_empty(token))


def port_range(port: U32, valid: Bool) -> IO(U32):
  match valid:
    case True{}:
      IO.pure(U32, port)
    case False{}:
      IO.die(U32, 1, "MC_LIVE_PORT must be an integer from 1 through 65535")

def port_checked(port: Maybe<&2, U32>) -> IO(U32):
  match port:
    case None{}:
      IO.die(U32, 1, "MC_LIVE_PORT must be an integer from 1 through 65535")
    case Some{+p}:
      port_range(p, U32.is_gt(p, 0) && U32.is_lt(p, 65536))


def configured_port(result: Result<&1, &1, U32 & String, String>) -> IO(U32):
  match result:
    case Fail{error}:
      IO.pure(U32, 47163)
    case Done{text}:
      port_checked(J.as_u32(J.JNumber{text}))

def first_peer_checked(first_peer: U32) -> IO(U32):
  match first_peer:
    case 0: IO.die(U32, 1, "live peer identity range exhausted")
    case actual: IO.pure(U32, actual)

def ready_notice(port: U32) -> IO(Unit):
  IO.print("{\"event\":\"server.ready\",\"host\":\"127.0.0.1\",\"port\":" ++ U32.show(port) ++ ",\"target\":\"26.3\",\"status\":\"foundation\"}")

def start_effectful_from_peer(~State: Type, ~driver: EffectfulDriver<State>, initial: State, first_peer: U32) -> IO(Handle<State>):
  do IO<Handle<State>>:
    token_result : Result<&1, &1, U32 & String, String> <- IO.get_env("MC_DEV_TOKEN")
    token : String <- required_token(token_result)
    port_result : Result<&1, &1, U32 & String, String> <- IO.get_env("MC_LIVE_PORT")
    +port : U32 <- configured_port(port_result)
    first : U32 <- first_peer_checked(first_peer)
    listener : Listener <- IO.try(Listener, TCP.listen("127.0.0.1", port))
    +mail : Chan(Message<State>) <- Chan.new(Message<State>, 64)
    IO.spawn(Unit, actor(~State, ~driver, mail, token, initial))
    now : Nat <- IO.now()
    IO.spawn(Unit, timer(State, mail, Nat.add(now, 50n)))
    ready_notice(port)
    IO.spawn(Unit, accept_loop(State, mail, listener, first))
    return Handle{mail}

def start_effectful(~State: Type, ~driver: EffectfulDriver<State>, initial: State) -> IO(Handle<State>):
  start_effectful_from_peer(~State, ~driver, initial, 1)

def start_handle(~State: Type, ~driver: Driver<State>, initial: State) -> IO(Handle<State>):
  start_effectful(~State,
    ~EffectfulDriver{w => pure_step(State, driver, w), w => s => t => r => pure_dispatch(State, driver, w, s, t, r)}, initial)

def local_answer(-State: Type, -A: Type, reply: Chan(A), result: State & A) -> IO(State):
  (world, answer) = result
  do IO<State>:
    sent : Bool <- Chan.send(A, reply, answer)
    return world

def local_operation(-State: Type, -A: Type, reply: Chan(A), query: State -> State & A, world: State) -> IO(State):
  local_answer(State, A, reply, query(world))

def local_sent(-A: Type, reply: Chan(A), sent: Bool) -> IO(A):
  match sent:
    case True{}: IO.join(A, reply)
    case False{}:
      do IO<A>:
        Chan.close(A, reply)
        IO.die(A, 1, "authoritative actor is closed")

# Serialize local input and snapshot requests with live API requests/ticks.
# The result can be Data or an affine owner; no State clone is required.
def local_call(-State: Type, -A: Type, handle: Handle<State>, query: State -> State & A) -> IO(A):
  Handle{mail} = handle
  do IO<A>:
    +reply : Chan(A) <- Chan.new(A, 1)
    sent : Bool <- Chan.send(Message<State>, mail, Local{world => local_operation(State, A, reply, query, world)})
    local_sent(A, reply, sent)

def stop_sent(+reply: Chan(Unit), sent: Bool) -> IO(Unit):
  match sent:
    case True{}: IO.join(Unit, reply)
    case False{}: Chan.close(Unit, reply)

# Stops the state actor and timer. The accept socket can still be parked in
# the OS; the owning process must exit to release that listener and clients.
def stop(-State: Type, handle: Handle<State>) -> IO(Unit):
  Handle{mail} = handle
  do IO<Unit>:
    +reply : Chan(Unit) <- Chan.new(Unit, 1)
    sent : Bool <- Chan.send(Message<State>, mail, Stop{reply})
    stop_sent(reply, sent)

def run_effectful_from_peer(~State: Type, ~driver: EffectfulDriver<State>, initial: State, first_peer: U32) -> IO(Unit):
  do IO<Unit>:
    handle : Handle<State> <- start_effectful_from_peer(~State, ~driver, initial, first_peer)
    return Unit{}

def run_effectful(~State: Type, ~driver: EffectfulDriver<State>, initial: State) -> IO(Unit):
  run_effectful_from_peer(~State, ~driver, initial, 1)

def run(~State: Type, ~driver: Driver<State>, initial: State) -> IO(Unit):
  run_effectful(~State,
    ~EffectfulDriver{w => pure_step(State, driver, w), w => s => t => r => pure_dispatch(State, driver, w, s, t, r)}, initial)
