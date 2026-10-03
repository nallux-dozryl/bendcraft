import Base
import ./json.bend as J
import ./framing.bend as F

type Phase is Data:
  Cold{}
  AwaitInitialized{}
  Ready{}

type Request is Data:
  Request{id: Maybe<&2, J.Value>, method: String, params: J.Value}

type Fault is Data:
  Fault{id: Maybe<&2, J.Value>, code: String, message: String}

type Plan is Data:
  Silent{phase: Phase}
  Reply{phase: Phase, value: J.Value}
  Discover{phase: Phase, id: J.Value}
  Call{phase: Phase, id: J.Value, name: String, arguments: J.Value}

type Tool is Data:
  Tool{name: String, descriptor: J.Value}

type Link is Type:
  Offline{message: String}
  Online{socket: Socket, buffer: F.Buffer, pending: List<&2, String>, sequence: Nat}

type Client is Type:
  Client{link: Link, phase: Phase}

type Outcome is Type:
  Outcome{client: Client, response: Maybe<&2, J.Value>}

type Reader is Type:
  Reader{file: File, buffer: F.Buffer, client: Client}

type Receive is Type:
  Again{link: Link}
  Received{link: Link, value: Result<&2, &2, String, J.Value>}

type IntegerScan is Data:
  IntegerScan{fraction: U32, trailing: U32, fraction_mode: Bool, all_zero: Bool,
    exponent: U32, negative: Bool, exponent_mode: Bool}

def obj(members: List<&2, J.Member>) -> J.Value:
  J.JObject{members}

def text(value: String) -> J.Value:
  J.JString{value}

def field(+value: J.Value, name: String) -> Maybe<&2, J.Value>:
  J.member(value, name)

def is_object(value: Maybe<&2, J.Value>) -> Bool:
  match value:
    case Some{J.JObject{members}}: True{}
    case _: False{}

def is_string(value: Maybe<&2, J.Value>) -> Bool:
  match value:
    case Some{J.JString{s}}: True{}
    case _: False{}

def string_or(value: Maybe<&2, J.Value>, fallback: String) -> String:
  match value:
    case Some{J.JString{s}}: s
    case _: fallback

def true_value(value: Maybe<&2, J.Value>) -> Bool:
  match value:
    case Some{J.JBool{True{}}}: True{}
    case _: False{}

def response(id: J.Value, result: J.Value) -> J.Value:
  obj([J.JMember{"jsonrpc", text("2.0")}, J.JMember{"id", id}, J.JMember{"result", result}])

def error(id: J.Value, code: String, message: String) -> J.Value:
  obj([J.JMember{"jsonrpc", text("2.0")}, J.JMember{"id", id},
    J.JMember{"error", obj([J.JMember{"code", J.JNumber{code}}, J.JMember{"message", text(message)}])}])

def protocol_fault(id: J.Value, code: String, message: String) -> Fault:
  Fault{Some{id}, code, message}

def bad_request(message: String) -> Fault:
  protocol_fault(J.JNull{}, "-32600", message)

def fallback_id(id: Maybe<&2, J.Value>) -> J.Value:
  match id:
    case Some{value}: value
    case None{}: J.JNull{}

# Exact integer-value validation of a parsed JSON number. This accepts 1.0,
# 10e-1 and huge integer exponents without float rounding or integer overflow.
# Parser input is bounded at 16384 characters, so exponent 16385 is sufficient
# to distinguish every possible relevant decimal shift.
def integer_end(state: IntegerScan) -> Bool:
  match state:
    case IntegerScan{+fraction, +trailing, mode, +zero, +exponent, True{}, emode}:
      zero || U32.is_ge(trailing, U32.add(fraction, exponent))
    case IntegerScan{+fraction, +trailing, mode, +zero, +exponent, False{}, emode}:
      zero || U32.is_ge(exponent, fraction) || U32.is_ge(trailing, U32.sub(fraction, exponent))

def integer_digit(state: IntegerScan, +digit: U32) -> IntegerScan:
  match state:
    case IntegerScan{fraction, trailing, mode, zero, exponent, negative, True{}}:
      IntegerScan{fraction, trailing, mode, zero, U32.min(16385, U32.add(U32.mul(exponent, 10), digit)), negative, True{}}
    case IntegerScan{+fraction, +trailing, +mode, zero, exponent, negative, False{}}:
      IntegerScan{J.choose(U32, U32.add(fraction, 1), fraction, mode),
        J.choose(U32, U32.add(trailing, 1), 0, U32.is_eq(digit, 0)), mode,
        zero && U32.is_eq(digit, 0), exponent, negative, False{}}

def integer_char(state: IntegerScan, c: U32) -> IntegerScan:
  match state:
    case IntegerScan{fraction, trailing, mode, zero, exponent, negative, +emode}:
      match c:
        case 45: IntegerScan{fraction, trailing, mode, zero, exponent, emode, emode}
        case 43: IntegerScan{fraction, trailing, mode, zero, exponent, negative, emode}
        case 46: IntegerScan{fraction, trailing, True{}, zero, exponent, negative, emode}
        case 69: IntegerScan{fraction, trailing, mode, zero, exponent, False{}, True{}}
        case 101: IntegerScan{fraction, trailing, mode, zero, exponent, False{}, True{}}
        case _: integer_digit(IntegerScan{fraction, trailing, mode, zero, exponent, negative, emode}, U32.sub(c, 48))

def integer_loop(raw: String, state: IntegerScan) -> Bool:
  match raw:
    case SNil{}: integer_end(state)
    case SCon{Chr{c}, tail}: integer_loop(tail, integer_char(state, c))

def integer_number(raw: String) -> Bool:
  integer_loop(raw, IntegerScan{0, 0, False{}, True{}, 0, False{}, False{}})

def checked_number_id(valid: Bool, raw: String) -> Result<&2, &2, String, Maybe<&2, J.Value>>:
  match valid:
    case True{}: Done{Some{J.JNumber{raw}}}
    case False{}: Fail{"request id must be a string or integer number"}

def request_id(value: Maybe<&2, J.Value>) -> Result<&2, &2, String, Maybe<&2, J.Value>>:
  match value:
    case None{}: Done{None{}}
    case Some{J.JString{s}}: Done{Some{J.JString{s}}}
    case Some{J.JNumber{+raw}}: checked_number_id(integer_number(raw), raw)
    case _: Fail{"request id must be a string or integer number, never null"}

def request_params(id: Maybe<&2, J.Value>, method: String, params: Maybe<&2, J.Value>) -> Result<&2, &2, Fault, Request>:
  match params:
    case None{}: Done{Request{id, method, obj([])}}
    case Some{J.JObject{members}}: Done{Request{id, method, J.JObject{members}}}
    case _: Fail{Fault{id, "-32602", "params must be an object"}}

def request_method(id: Maybe<&2, J.Value>, method: Maybe<&2, J.Value>, params: Maybe<&2, J.Value>) -> Result<&2, &2, Fault, Request>:
  match method:
    case Some{J.JString{name}}: request_params(id, name, params)
    case _: Fail{protocol_fault(fallback_id(id), "-32600", "request method must be a string")}

def request_header(valid: Bool, id: Maybe<&2, J.Value>, +value: J.Value) -> Result<&2, &2, Fault, Request>:
  match valid:
    case False{}: Fail{protocol_fault(fallback_id(id), "-32600", "jsonrpc must be 2.0")}
    case True{}: request_method(id, field(value, "method"), field(value, "params"))

def request_fields(found: Result<&2, &2, String, Maybe<&2, J.Value>>, +value: J.Value) -> Result<&2, &2, Fault, Request>:
  match found:
    case Fail{message}: Fail{bad_request(message)}
    case Done{id}: request_header(String.eq(string_or(field(value, "jsonrpc"), ""), "2.0"), id, value)

def decode_request(value: J.Value) -> Result<&2, &2, Fault, Request>:
  match value:
    case J.JObject{+members}: request_fields(request_id(field(J.JObject{members}, "id")), J.JObject{members})
    case _: Fail{bad_request("MCP messages must be individual JSON-RPC objects")}

def initialize_result() -> J.Value:
  obj([J.JMember{"protocolVersion", text("2025-11-25")},
    J.JMember{"capabilities", obj([J.JMember{"tools", obj([J.JMember{"listChanged", J.JBool{False{}}}])}])},
    J.JMember{"serverInfo", obj([J.JMember{"name", text("minecraft-bend-foundation")}, J.JMember{"version", text("0.1.0")}] )},
    J.JMember{"instructions", text("Tools expose the implemented section-and-tick foundation of the pinned Minecraft 26.3 project. This is not full Minecraft gameplay. Tool schemas are live API request envelopes; keep op equal to the tool name. Developer capability comes from the configured environment token and the live server.")}])

def valid_client_info(value: Maybe<&2, J.Value>) -> Bool:
  match value:
    case Some{+info}: is_object(Some{info}) && is_string(field(info, "name")) && is_string(field(info, "version"))
    case _: False{}

def initialize_plan(valid: Bool, id: J.Value) -> Plan:
  match valid:
    case True{}: Reply{AwaitInitialized{}, response(id, initialize_result())}
    case False{}: Reply{Cold{}, error(id, "-32602", "initialize requires protocolVersion, capabilities and clientInfo name/version")}

def initialize(phase: Phase, id: J.Value, +params: J.Value) -> Plan:
  match phase:
    case Cold{}: initialize_plan(is_string(field(params, "protocolVersion")) && is_object(field(params, "capabilities")) && valid_client_info(field(params, "clientInfo")), id)
    case _: Reply{phase, error(id, "-32600", "MCP is already initialized")}

def notification(phase: Phase, method: String) -> Plan:
  match phase method:
    case AwaitInitialized{} "notifications/initialized": Silent{Ready{}}
    case _ _: Silent{phase}

def list_plan(cursor: Maybe<&2, J.Value>, id: J.Value) -> Plan:
  match cursor:
    case None{}: Discover{Ready{}, id}
    case _: Reply{Ready{}, error(id, "-32602", "tools/list returns the complete catalog and accepts no cursor")}

def call_op(valid: Bool, id: J.Value, name: String, arguments: J.Value) -> Plan:
  match valid:
    case True{}: Call{Ready{}, id, name, arguments}
    case False{}: Reply{Ready{}, error(id, "-32602", "tool name and live envelope op must match")}

def call_arguments(op: Maybe<&2, J.Value>, id: J.Value, +name: String, arguments: J.Value) -> Plan:
  match op arguments:
    case None{} J.JObject{members}: Call{Ready{}, id, name, obj(J.JMember{"op", text(name)} <> members)}
    case Some{J.JString{actual}} _: call_op(String.eq(actual, name), id, name, arguments)
    case _ _: Reply{Ready{}, error(id, "-32602", "tool envelope op must be a string matching the tool name")}

def call_object(arguments: Maybe<&2, J.Value>, id: J.Value, +name: String) -> Plan:
  match arguments:
    case None{}: Call{Ready{}, id, name, obj([J.JMember{"op", text(name)}])}
    case Some{J.JObject{+members}}: call_arguments(field(J.JObject{members}, "op"), id, name, J.JObject{members})
    case _: Reply{Ready{}, error(id, "-32602", "tools/call arguments must be an object")}

def call_name(found: Maybe<&2, J.Value>, id: J.Value, +params: J.Value) -> Plan:
  match found:
    case Some{J.JString{name}}: call_object(field(params, "arguments"), id, name)
    case _: Reply{Ready{}, error(id, "-32602", "tools/call requires a string name")}

def ready_method(phase: Phase, +id: J.Value, method: String, +params: J.Value) -> Plan:
  match phase method:
    case _ "ping": Reply{phase, response(id, obj([]))}
    case _ "initialize": initialize(phase, id, params)
    case Ready{} "tools/list": list_plan(field(params, "cursor"), id)
    case Ready{} "tools/call": call_name(field(params, "name"), id, params)
    case _ "tools/list": Reply{phase, error(id, "-32002", "MCP initialization is incomplete")}
    case _ "tools/call": Reply{phase, error(id, "-32002", "MCP initialization is incomplete")}
    case _ _: Reply{phase, error(id, "-32601", "method is not supported")}

def plan(phase: Phase, request: Request) -> Plan:
  match request:
    case Request{None{}, method, params}: notification(phase, method)
    case Request{Some{id}, method, params}: ready_method(phase, id, method, params)

def live_id(value: Maybe<&2, J.Value>) -> String:
  string_or(value, "")

def live_envelope_id(found: Maybe<&2, J.Value>, members: List<&2, J.Member>, sequence: Nat) -> String & J.Value:
  match found:
    case None{}:
      +id = "mcp-live-" ++ Nat.show(sequence)
      (id, obj(J.JMember{"id", text(id)} <> members))
    case Some{value}: (live_id(Some{value}), J.JObject{members})

def live_envelope(value: J.Value, sequence: Nat) -> String & J.Value:
  match value:
    case J.JObject{+members}:
      live_envelope_id(field(J.JObject{members}, "id"), members, sequence)
    case _: ("", value)

def close_link(link: Link) -> IO(Unit):
  match link:
    case Offline{message}: IO.pure(Unit, Unit{})
    case Online{socket, buffer, pending, sequence}: Socket.close(socket)

def failed_receive(socket: Socket, +message: String) -> IO(Receive):
  do IO<Receive>:
    Socket.close(socket)
    return Received{Offline{message}, Fail{message}}

def framed_receive(socket: Socket, sequence: Nat, result: Result<&1, &1, String, F.Buffer & List<&2, String>>) -> IO(Receive):
  match result:
    case Fail{message}: failed_receive(socket, "live server sent an invalid or oversized record")
    case Done{Tuple{buffer, lines}}:
      IO.pure(Receive, Again{Online{socket, buffer, lines, sequence}})

def received_bytes(buffer: F.Buffer, sequence: Nat, result: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Receive):
  (socket, status) = result
  match status:
    case Fail{error}: failed_receive(socket, "live server receive failed")
    case Done{Nil{}}: failed_receive(socket, "live server closed the connection")
    case Done{bytes}: framed_receive(socket, sequence, F.feed(buffer, bytes))

def live_parsed(socket: Socket, buffer: F.Buffer, pending: List<&2, String>, sequence: Nat, result: Result<&2, &2, String, J.Value>) -> IO(Link & Result<&2, &2, String, J.Value>):
  match result:
    case Done{value}: IO.pure(Link & Result<&2, &2, String, J.Value>, (Online{socket, buffer, pending, sequence}, Done{value}))
    case Fail{message}:
      do IO<Link & Result<&2, &2, String, J.Value>>:
        Socket.close(socket)
        return (Offline{"live server sent invalid JSON"}, Fail{"live server sent invalid JSON"})

# Only the externally controlled IO lifetimes recurse unsafely. Pure framing,
# protocol planning, validation and schema mapping above remain checked Bend.
@unsafe
def receive_next(step: Receive) -> IO(Link & Result<&2, &2, String, J.Value>):
  match step:
    case Received{link, value}: IO.pure(Link & Result<&2, &2, String, J.Value>, (link, value))
    case Again{link}: receive(link)

@unsafe
def receive(link: Link) -> IO(Link & Result<&2, &2, String, J.Value>):
  match link:
    case Offline{+message}: IO.pure(Link & Result<&2, &2, String, J.Value>, (Offline{message}, Fail{message}))
    case Online{socket, buffer, text <> rest, sequence}: live_parsed(socket, buffer, rest, sequence, J.parse(text))
    case Online{socket, buffer, Nil{}, sequence}:
      do IO<Link & Result<&2, &2, String, J.Value>>:
        bytes : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- TCP.recv_bytes(socket, 8192)
        next : Receive <- received_bytes(buffer, sequence, bytes)
        receive_next(next)

def checked_live_response(valid: Bool, link: Link, value: J.Value) -> IO(Link & Result<&2, &2, String, J.Value>):
  match valid:
    case True{}: IO.pure(Link & Result<&2, &2, String, J.Value>, (link, Done{value}))
    case False{}:
      do IO<Link & Result<&2, &2, String, J.Value>>:
        close_link(link)
        return (Offline{"live response id mismatch"}, Fail{"live response id mismatch"})

def correlated(id: String, result: Link & Result<&2, &2, String, J.Value>) -> IO(Link & Result<&2, &2, String, J.Value>):
  (link, status) = result
  match status:
    case Fail{message}: IO.pure(Link & Result<&2, &2, String, J.Value>, (link, Fail{message}))
    case Done{+value}: checked_live_response(String.eq(id, live_id(field(value, "id"))), link, value)

def sent(id: String, buffer: F.Buffer, sequence: Nat, result: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Link & Result<&2, &2, String, J.Value>):
  (socket, status) = result
  match status:
    case Fail{error}:
      do IO<Link & Result<&2, &2, String, J.Value>>:
        Socket.close(socket)
        return (Offline{"live server send failed"}, Fail{"live server send failed"})
    case Done{unit}:
      do IO<Link & Result<&2, &2, String, J.Value>>:
        received : Link & Result<&2, &2, String, J.Value> <- receive(Online{socket, buffer, Nil{}, sequence})
        correlated(id, received)

def send_envelope(socket: Socket, buffer: F.Buffer, sequence: Nat, envelope: String & J.Value) -> IO(Link & Result<&2, &2, String, J.Value>):
  (id, value) = envelope
  do IO<Link & Result<&2, &2, String, J.Value>>:
    result : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send(socket, J.encode(value) ++ "\n")
    sent(id, buffer, sequence, result)

def exchange(link: Link, envelope: J.Value) -> IO(Link & Result<&2, &2, String, J.Value>):
  match link:
    case Offline{+message}: IO.pure(Link & Result<&2, &2, String, J.Value>, (Offline{message}, Fail{message}))
    case Online{socket, buffer, Nil{}, +sequence}:
      send_envelope(socket, buffer, 1n+sequence, live_envelope(envelope, sequence))
    case Online{socket, buffer, pending, sequence}:
      do IO<Link & Result<&2, &2, String, J.Value>>:
        Socket.close(socket)
        return (Offline{"unexpected unsolicited live response"}, Fail{"unexpected unsolicited live response"})

def tool_fields(name: Maybe<&2, J.Value>, description: Maybe<&2, J.Value>, schema: Maybe<&2, J.Value>) -> Result<&2, &2, String, Tool>:
  match name description schema:
    case Some{J.JString{+n}} Some{J.JString{d}} Some{J.JObject{members}}:
      Done{Tool{n, obj([J.JMember{"name", text(n)}, J.JMember{"description", text(d)}, J.JMember{"inputSchema", J.JObject{members}}])}}
    case _ _ _: Fail{"live catalog contains a malformed tool descriptor"}

def tool_from(+operation: J.Value) -> Result<&2, &2, String, Tool>:
  tool_fields(field(operation, "name"), field(operation, "description"), field(operation, "input_schema"))

def tool_append(found: Result<&2, &2, String, Tool>, tools: List<&2, Tool>) -> Result<&2, &2, String, List<&2, Tool>>:
  match found:
    case Fail{message}: Fail{message}
    case Done{tool}: Done{tool <> tools}

def tools_loop(operations: List<&2, J.Value>, result: Result<&2, &2, String, List<&2, Tool>>) -> Result<&2, &2, String, List<&2, Tool>>:
  match operations result:
    case _ Fail{message}: Fail{message}
    case Nil{} Done{tools}: Done{List.reverse(&2, Tool, tools)}
    case operation <> rest Done{tools}: tools_loop(rest, tool_append(tool_from(operation), tools))

def catalog_operations(found: Maybe<&2, J.Value>) -> Result<&2, &2, String, List<&2, Tool>>:
  match found:
    case Some{J.JArray{operations}}: tools_loop(operations, Done{Nil{}})
    case _: Fail{"live discovery omitted its operation array"}

def catalog_result(found: Maybe<&2, J.Value>) -> Result<&2, &2, String, List<&2, Tool>>:
  match found:
    case Some{result}: catalog_operations(field(result, "operations"))
    case _: Fail{"live discovery omitted its result"}

def catalog_success(ok: Bool, response: J.Value) -> Result<&2, &2, String, List<&2, Tool>>:
  match ok:
    case True{}: catalog_result(field(response, "result"))
    case False{}: Fail{"live discovery failed"}

def catalog(status: Result<&2, &2, String, J.Value>) -> Result<&2, &2, String, List<&2, Tool>>:
  match status:
    case Fail{message}: Fail{message}
    case Done{+value}: catalog_success(true_value(field(value, "ok")), value)

def descriptors(tools: List<&2, Tool>) -> List<&2, J.Value>:
  match tools:
    case Nil{}: Nil{}
    case Tool{name, descriptor} <> rest: descriptor <> descriptors(rest)

def known_tool(tools: List<&2, Tool>, +name: String) -> Bool:
  match tools:
    case Nil{}: False{}
    case Tool{actual, descriptor} <> rest: String.eq(actual, name) || known_tool(rest, name)

def discovery_envelope() -> J.Value:
  obj([J.JMember{"op", text("discover")}])

def discovered_catalog(status: Result<&2, &2, String, List<&2, Tool>>, link: Link, phase: Phase, id: J.Value) -> IO(Outcome):
  match status:
    case Fail{message}: IO.pure(Outcome, Outcome{Client{link, phase}, Some{error(id, "-32603", message)}})
    case Done{tools}: IO.pure(Outcome, Outcome{Client{link, phase}, Some{response(id, obj([J.JMember{"tools", J.JArray{descriptors(tools)}}]))}})

def discovered(phase: Phase, id: J.Value, result: Link & Result<&2, &2, String, J.Value>) -> IO(Outcome):
  (link, status) = result
  discovered_catalog(catalog(status), link, phase, id)

def tool_result(+live: J.Value, is_error: Bool) -> J.Value:
  obj([J.JMember{"content", J.JArray{[obj([J.JMember{"type", text("text")}, J.JMember{"text", text(J.encode(live))}])]}},
    J.JMember{"structuredContent", live}, J.JMember{"isError", J.JBool{is_error}}])

def transport_tool_error(message: String) -> J.Value:
  tool_result(obj([J.JMember{"ok", J.JBool{False{}}}, J.JMember{"error", obj([J.JMember{"code", text("LiveTransportError")}, J.JMember{"message", text(message)}])}]), True{})

def tool_live(id: J.Value, phase: Phase, result: Link & Result<&2, &2, String, J.Value>) -> IO(Outcome):
  (link, status) = result
  match status:
    case Fail{message}: IO.pure(Outcome, Outcome{Client{link, phase}, Some{response(id, transport_tool_error(message))}})
    case Done{+value}: IO.pure(Outcome, Outcome{Client{link, phase}, Some{response(id, tool_result(value, Bool.not(true_value(field(value, "ok")))))}})

def call_known(known: Bool, phase: Phase, id: J.Value, arguments: J.Value, link: Link) -> IO(Outcome):
  match known:
    case False{}: IO.pure(Outcome, Outcome{Client{link, phase}, Some{error(id, "-32602", "unknown tool")}})
    case True{}:
      do IO<Outcome>:
        result : Link & Result<&2, &2, String, J.Value> <- exchange(link, arguments)
        tool_live(id, phase, result)

def call_catalog(status: Result<&2, &2, String, List<&2, Tool>>, link: Link, phase: Phase, id: J.Value, name: String, arguments: J.Value) -> IO(Outcome):
  match status:
    case Fail{message}: IO.pure(Outcome, Outcome{Client{link, phase}, Some{response(id, transport_tool_error(message))}})
    case Done{tools}: call_known(known_tool(tools, name), phase, id, arguments, link)

def call_discovered(phase: Phase, id: J.Value, name: String, arguments: J.Value, result: Link & Result<&2, &2, String, J.Value>) -> IO(Outcome):
  (link, status) = result
  call_catalog(catalog(status), link, phase, id, name, arguments)

def execute(plan: Plan, link: Link) -> IO(Outcome):
  match plan:
    case Silent{phase}: IO.pure(Outcome, Outcome{Client{link, phase}, None{}})
    case Reply{phase, value}: IO.pure(Outcome, Outcome{Client{link, phase}, Some{value}})
    case Discover{phase, id}:
      do IO<Outcome>:
        result : Link & Result<&2, &2, String, J.Value> <- exchange(link, discovery_envelope())
        discovered(phase, id, result)
    case Call{phase, id, name, arguments}:
      do IO<Outcome>:
        result : Link & Result<&2, &2, String, J.Value> <- exchange(link, discovery_envelope())
        call_discovered(phase, id, name, arguments, result)

def fault_outcome(fault: Fault, client: Client) -> IO(Outcome):
  match fault:
    case Fault{None{}, code, message}: IO.pure(Outcome, Outcome{client, None{}})
    case Fault{Some{id}, code, message}: IO.pure(Outcome, Outcome{client, Some{error(id, code, message)}})

def decoded_request(parsed: Result<&2, &2, Fault, Request>, client: Client) -> IO(Outcome):
  match parsed:
    case Fail{fault}: fault_outcome(fault, client)
    case Done{request}:
      Client{link, phase} = client
      execute(plan(phase, request), link)

def handle(parsed: Result<&2, &2, String, J.Value>, client: Client) -> IO(Outcome):
  match parsed:
    case Fail{message}: IO.pure(Outcome, Outcome{client, Some{error(J.JNull{}, "-32700", "invalid JSON: " ++ message)}})
    case Done{value}: decoded_request(decode_request(value), client)

def emit(outcome: Outcome) -> IO(Client):
  match outcome:
    case Outcome{client, None{}}: IO.pure(Client, client)
    case Outcome{client, Some{value}}:
      do IO<Client>:
        IO.write(J.encode(value) ++ "\n")
        return client

def line_done(outcome: Outcome) -> IO(Client):
  emit(outcome)

def line(text: String, client: Client) -> IO(Client):
  do IO<Client>:
    outcome : Outcome <- handle(J.parse(text), client)
    line_done(outcome)

def record_next(text: String, client: Client, rest: Client -> IO(Client)) -> IO(Client):
  do IO<Client>:
    next : Client <- line(text, client)
    rest(next)

def records(lines: List<&2, String>, client: Client) -> IO(Client):
  match lines:
    case Nil{}: IO.pure(Client, client)
    case text <> tail: record_next(text, client, c => records(tail, c))

def close_reader(reader: Reader) -> IO(Unit):
  Reader{file, buffer, Client{link, phase}} = reader
  do IO<Unit>:
    File.close(file)
    close_link(link)

def framed_reader(file: File, client: Client, fed: Result<&1, &1, String, F.Buffer & List<&2, String>>) -> IO(Maybe<&1, Reader>):
  match fed:
    case Fail{message}:
      do IO<Maybe<&1, Reader>>:
        IO.write(J.encode(error(J.JNull{}, "-32700", "invalid stdio record: " ++ message)) ++ "\n")
        close_reader(Reader{file, F.new(), client})
        return None{}
    case Done{Tuple{buffer, lines}}:
      do IO<Maybe<&1, Reader>>:
        next : Client <- records(lines, client)
        return Some{Reader{file, buffer, next}}

def segment_next(result: Maybe<&1, Reader>, rest: Reader -> IO(Maybe<&1, Reader>)) -> IO(Maybe<&1, Reader>):
  match result:
    case None{}: IO.pure(Maybe<&1, Reader>, None{})
    case Some{reader}: rest(reader)

def segment_feed(bytes: List<&2, U32>, reader: Reader, rest: Reader -> IO(Maybe<&1, Reader>)) -> IO(Maybe<&1, Reader>):
  Reader{file, buffer, client} = reader
  do IO<Maybe<&1, Reader>>:
    next : Maybe<&1, Reader> <- framed_reader(file, client, F.feed(buffer, bytes))
    segment_next(next, rest)

def segments(parts: List<&2, List<&2, U32>>, reader: Reader) -> IO(Maybe<&1, Reader>):
  match parts:
    case Nil{}: IO.pure(Maybe<&1, Reader>, Some{reader})
    case bytes <> rest: segment_feed(bytes, reader, r => segments(rest, r))

def finished_reader(valid: Result<&1, &1, String, Unit>, reader: Reader) -> IO(Maybe<&1, Reader>):
  match valid:
    case Done{unit}:
      do IO<Maybe<&1, Reader>>:
        close_reader(reader)
        return None{}
    case Fail{message}:
      do IO<Maybe<&1, Reader>>:
        IO.write(J.encode(error(J.JNull{}, "-32700", message)) ++ "\n")
        close_reader(reader)
        return None{}

def stdin_read(buffer: F.Buffer, client: Client, result: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Maybe<&1, Reader>):
  (file, status) = result
  match status:
    case Fail{error}:
      do IO<Maybe<&1, Reader>>:
        IO.print_err("MCP stdin read failed")
        close_reader(Reader{file, buffer, client})
        return None{}
    case Done{Nil{}}: finished_reader(F.finish(buffer), Reader{file, F.new(), client})
    case Done{bytes}: segments(F.segments(bytes), Reader{file, buffer, client})

@unsafe
def read_again(next: Maybe<&1, Reader>) -> IO(Unit):
  match next:
    case None{}: IO.pure(Unit, Unit{})
    case Some{reader}: read_loop(reader)

@unsafe
def read_loop(reader: Reader) -> IO(Unit):
  Reader{file, buffer, client} = reader
  do IO<Unit>:
    bytes : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, 8192)
    next : Maybe<&1, Reader> <- stdin_read(buffer, client, bytes)
    read_again(next)

def token_value(result: Result<&1, &1, U32 & String, String>) -> String:
  match result:
    case Fail{error}: ""
    case Done{token}: token

def port_valid(valid: Bool, port: U32) -> IO(U32):
  match valid:
    case True{}: IO.pure(U32, port)
    case False{}: IO.die(U32, 1, "MC_LIVE_PORT must be an integer from 1 through 65535")

def port_found(value: Maybe<&2, U32>) -> IO(U32):
  match value:
    case None{}: IO.die(U32, 1, "MC_LIVE_PORT must be an integer from 1 through 65535")
    case Some{+port}: port_valid(U32.is_gt(port, 0) && U32.is_lt(port, 65536), port)

def port_configured(result: Result<&1, &1, U32 & String, String>) -> IO(U32):
  match result:
    case Fail{error}: IO.pure(U32, 47163)
    case Done{text}: port_found(J.as_u32(J.JNumber{text}))

def authentication_valid(valid: Bool, link: Link) -> IO(Link):
  match valid:
    case True{}: IO.pure(Link, link)
    case False{}:
      do IO<Link>:
        close_link(link)
        IO.die(Link, 1, "MCP developer authentication failed")

def authenticated(result: Link & Result<&2, &2, String, J.Value>) -> IO(Link):
  (link, status) = result
  match status:
    case Done{value}: authentication_valid(true_value(field(value, "ok")), link)
    case Fail{message}:
      do IO<Link>:
        close_link(link)
        IO.die(Link, 1, "MCP live server authentication transport failed")

def authenticate(token: String, link: Link) -> IO(Link):
  match token:
    case SNil{}: IO.pure(Link, link)
    case _:
      do IO<Link>:
        result : Link & Result<&2, &2, String, J.Value> <- exchange(link,
          obj([J.JMember{"op", text("session.open")}, J.JMember{"args", obj([J.JMember{"mode", text("developer")}, J.JMember{"token", text(token)}])}]))
        authenticated(result)

def run() -> IO(Unit):
  do IO<Unit>:
    configured : Result<&1, &1, U32 & String, String> <- IO.get_env("MC_LIVE_PORT")
    port : U32 <- port_configured(configured)
    credentials : Result<&1, &1, U32 & String, String> <- IO.get_env("MC_DEV_TOKEN")
    socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
    link : Link <- authenticate(token_value(credentials), Online{socket, F.new(), Nil{}, 0n})
    input : File <- IO.try(File, File.open("/dev/stdin", "r"))
    read_loop(Reader{input, F.new(), Client{link, Cold{}}})
