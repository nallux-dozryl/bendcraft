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

def core_dispatch(world: C.World, session: L.Session, token: String, request: J.Value) -> C.World & L.Session & J.Value:
  L.dispatch(world, session, token, request)

type Answer is Data:
  Answer{session: L.Session, value: J.Value}

type Message is Data:
  Pulse{}
  Request{session: L.Session, value: J.Value, reply: Chan(Answer)}

type Link is Type:
  Link{socket: Socket, buffer: F.Buffer, session: L.Session}

def actor_reply(-State: Type, reply: Chan(Answer), result: State & L.Session & J.Value, rest: State -> IO(Unit)) -> IO(Unit):
  (world, session, value) = result
  do IO<Unit>:
    sent : Bool <- Chan.send(Answer, reply, Answer{session, value})
    rest(world)

def actor_message(-State: Type, driver: Driver<State>, +token: String, world: State, message: Maybe<&1, Message>, rest: State -> IO(Unit)) -> IO(Unit):
  match driver message:
    case Driver{step, dispatch} None{}:
      IO.pure(Unit, Unit{})
    case Driver{step, dispatch} Some{Pulse{}}:
      rest(step(world))
    case Driver{step, dispatch} Some{Request{session, value, reply}}:
      actor_reply(State, reply, dispatch(world, session, token, value), rest)

# Only the OS-driven lifetime is unsafe. State transitions live in checked
# pure modules. One actor is the sole owner of the authoritative world.
@unsafe
def actor(~State: Type, ~driver: Driver<State>, +mail: Chan(Message), +token: String, world: State) -> IO(Unit):
  do IO<Unit>:
    message : Maybe<&1, Message> <- Chan.recv(Message, mail)
    actor_message(State, driver, token, world, message, w => actor(~State, ~driver, mail, token, w))

def timer_sent(sent: Bool, rest: Unit -> IO(Unit)) -> IO(Unit):
  match sent:
    case True{}:
      rest(Unit{})
    case False{}:
      IO.pure(Unit, Unit{})

# Deadlines advance from the previous deadline, not sleep completion, so the
# timer does not accumulate request/compute latency as drift. Mail is bounded.
@unsafe
def timer(+mail: Chan(Message), +deadline: Nat) -> IO(Unit):
  do IO<Unit>:
    now : Nat <- IO.now()
    IO.sleep(U32.from_nat(Nat.sub(deadline, now)))
    sent : Bool <- Chan.send(Message, mail, Pulse{})
    timer_sent(sent, u => timer(mail, Nat.add(deadline, 50n)))

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

def ask(+mail: Chan(Message), socket: Socket, buffer: F.Buffer, session: L.Session, parsed: Result<&2, &2, String, J.Value>) -> IO(Maybe<&1, Link>):
  match parsed:
    case Fail{message}:
      send_value(socket, buffer, session, parse_error(message))
    case Done{value}:
      do IO<Maybe<&1, Link>>:
        reply : Chan(Answer) <- Chan.new(Answer, 1)
        +channel : Chan(Answer) = reply
        sent : Bool <- Chan.send(Message, mail, Request{session, value, channel})
        request_sent(socket, buffer, channel, sent)

def line_next(result: Maybe<&1, Link>, rest: Link -> IO(Maybe<&1, Link>)) -> IO(Maybe<&1, Link>):
  match result:
    case None{}:
      IO.pure(Maybe<&1, Link>, None{})
    case Some{link}:
      rest(link)

def line_ask(text: String, +mail: Chan(Message), link: Link, rest: Link -> IO(Maybe<&1, Link>)) -> IO(Maybe<&1, Link>):
  Link{socket, buffer, session} = link
  do IO<Maybe<&1, Link>>:
    result : Maybe<&1, Link> <- ask(mail, socket, buffer, session, J.parse(text))
    line_next(result, rest)

def lines(records: List<&2, String>, +mail: Chan(Message), link: Link) -> IO(Maybe<&1, Link>):
  match records:
    case Nil{}:
      IO.pure(Maybe<&1, Link>, Some{link})
    case Con{text, tail}:
      line_ask(text, mail, link, l => lines(tail, mail, l))

def feed_result(+mail: Chan(Message), socket: Socket, session: L.Session, fed: Result<&1, &1, String, F.Buffer & List<&2, String>>) -> IO(Maybe<&1, Link>):
  match fed:
    case Fail{error}:
      do IO<Maybe<&1, Link>>:
        Socket.close(socket)
        return None{}
    case Done{Tuple{buffer, records}}:
      lines(records, mail, Link{socket, buffer, session})

def feed_segment(bytes: List<&2, U32>, +mail: Chan(Message), link: Link, rest: Link -> IO(Maybe<&1, Link>)) -> IO(Maybe<&1, Link>):
  Link{socket, buffer, session} = link
  do IO<Maybe<&1, Link>>:
    next : Maybe<&1, Link> <- feed_result(mail, socket, session, F.feed(buffer, bytes))
    line_next(next, rest)

# Apply complete records individually. A later malformed record cannot erase
# an earlier request merely because both arrived in the same TCP receive.
def feed_segments(segments: List<&2, List<&2, U32>>, +mail: Chan(Message), link: Link) -> IO(Maybe<&1, Link>):
  match segments:
    case Nil{}:
      IO.pure(Maybe<&1, Link>, Some{link})
    case Con{bytes, tail}:
      feed_segment(bytes, mail, link, l => feed_segments(tail, mail, l))

def received(+mail: Chan(Message), buffer: F.Buffer, session: L.Session, result: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Maybe<&1, Link>):
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
      feed_segments(F.segments(bytes), mail, Link{socket, buffer, session})

def read_next(result: Maybe<&1, Link>, rest: Link -> IO(Unit)) -> IO(Unit):
  match result:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{link}:
      rest(link)

@unsafe
def read_loop(+mail: Chan(Message), link: Link) -> IO(Unit):
  Link{socket, buffer, session} = link
  do IO<Unit>:
    result : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- TCP.recv_bytes(socket, 8192)
    next : Maybe<&1, Link> <- received(mail, buffer, session, result)
    read_next(next, l => read_loop(mail, l))

def accepted(+mail: Chan(Message), peer: U32, result: Listener & Result<&1, &1, U32 & String, Socket>) -> IO(Listener):
  (listener, status) = result
  do IO<Listener>:
    socket : Socket <- IO.pass(Socket, status)
    IO.spawn(Unit, read_loop(mail, Link{socket, F.new(), L.new_session(peer)}))
    return listener

@unsafe
def accept_loop(+mail: Chan(Message), listener: Listener, +peer: U32) -> IO(Unit):
  do IO<Unit>:
    result : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept(listener)
    next : Listener <- accepted(mail, peer, result)
    accept_loop(mail, next, U32.inc(peer))

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

def run(~State: Type, ~driver: Driver<State>, initial: State) -> IO(Unit):
  do IO<Unit>:
    token_result : Result<&1, &1, U32 & String, String> <- IO.get_env("MC_DEV_TOKEN")
    token : String <- required_token(token_result)
    port_result : Result<&1, &1, U32 & String, String> <- IO.get_env("MC_LIVE_PORT")
    +port : U32 <- configured_port(port_result)
    +mail : Chan(Message) <- Chan.new(Message, 64)
    IO.spawn(Unit, actor(~State, ~driver, mail, token, initial))
    now : Nat <- IO.now()
    IO.spawn(Unit, timer(mail, Nat.add(now, 50n)))
    listener : Listener <- IO.try(Listener, TCP.listen("127.0.0.1", port))
    IO.print("{\"event\":\"server.ready\",\"host\":\"127.0.0.1\",\"port\":" ++ U32.show(port) ++ ",\"target\":\"26.3\",\"status\":\"foundation\"}")
    accept_loop(mail, listener, 1)
