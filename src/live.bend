import Base
import ./json.bend as J
import ./core.bend as C
import ./schedule.bend as Q

type Session is Data:
  Session{peer: U32, sequence: Nat, capability: C.Capability}

type Tag is Data:
  Discover{}
  Ping{}
  Open{}
  Clock{}
  Pause{}
  StepTicks{}
  Create{}
  Get{}
  Set{}
  Time{}
  Daylight{}
  Cancel{}
  Events{}

type Access is Data:
  Public{}
  DeveloperOnly{}

type Argument is Data:
  Text{allowed: List<&2, String>}
  Boolean{}
  Unsigned{minimum: U32, maximum: U32}
  Signed{}
  StringMap{}

type Field is Data:
  Field{name: String, argument: Argument, required: Bool}

type Operation is Data:
  Operation{tag: Tag, name: String, phase: String, access: Access,
    fields: List<&2, Field>, scheduled: Bool, description: String}

type Fault is Data:
  Fault{code: String, message: String}

type Envelope is Data:
  Envelope{id: String, operation: String, arguments: J.Value, at: Maybe<&2, Nat>}

type Command is Data:
  DiscoverCommand{}
  PingCommand{}
  OpenCommand{mode: String, token: String}
  ClockCommand{}
  PauseCommand{paused: Bool}
  StepCommand{ticks: U32}
  CreateCommand{position: C.Position, fill: U32}
  GetCommand{position: C.Position}
  SetCommand{position: C.Position, state: U32}
  TimeCommand{day_time: U32}
  DaylightCommand{enabled: Bool}
  CancelCommand{peer: U32, sequence: U32}
  EventsCommand{}

def new_session(peer: U32) -> Session:
  Session{peer, 0n, C.Observer{}}

def capability(session: Session) -> C.Capability:
  Session{peer, sequence, cap} = session
  cap

def peer(session: Session) -> U32:
  Session{p, sequence, cap} = session
  p

def sequence(session: Session) -> Nat:
  Session{p, seq, cap} = session
  seq

def mode_name(cap: C.Capability) -> String:
  match cap:
    case C.Observer{}: "observer"
    case C.Player{peer}: "player"
    case C.Developer{}: "developer"

def obj(members: List<&2, J.Member>) -> J.Value:
  J.JObject{members}

def text(s: String) -> J.Value:
  J.JString{s}

def uint(n: U32) -> J.Value:
  J.JNumber{U32.show(n)}

def natural(n: Nat) -> J.Value:
  J.JNumber{Nat.show(n)}

def boolean(b: Bool) -> J.Value:
  J.JBool{b}

def fault_value(fault: Fault) -> J.Value:
  match fault:
    case Fault{code, message}:
      obj([J.JMember{"code", text(code)}, J.JMember{"message", text(message)}])

def bad(code: String, message: String) -> Fault:
  Fault{code, message}

def invalid(name: String) -> Fault:
  bad("InvalidArguments", "invalid or missing argument: " ++ name)

def success(w: C.World, session: Session, id: String, result: J.Value) -> C.World & Session & J.Value:
  (w, session, obj([J.JMember{"id", text(id)}, J.JMember{"ok", boolean(True{})}, J.JMember{"result", result}]))

def failure(w: C.World, session: Session, id: String, fault: Fault) -> C.World & Session & J.Value:
  (w, session, obj([J.JMember{"id", text(id)}, J.JMember{"ok", boolean(False{})}, J.JMember{"error", fault_value(fault)}]))

def coordinate_fields() -> List<&2, Field>:
  [Field{"dimension", Text{[]}, True{}}, Field{"x", Signed{}, True{}},
    Field{"y", Signed{}, True{}}, Field{"z", Signed{}, True{}}]

# This catalog is the sole operation/argument schema inventory.
def catalog() -> List<&2, Operation>:
  [Operation{Discover{}, "discover", "discovery", Public{}, [], False{}, "List the implemented foundation operations and their strict schemas."},
   Operation{Ping{}, "ping", "discovery", Public{}, [], False{}, "Return version and session identity."},
   Operation{Open{}, "session.open", "session", Public{}, [Field{"mode", Text{["observer", "developer", "player"]}, True{}}, Field{"token", Text{[]}, False{}}], False{}, "Observer mode is available; developer mode needs the configured nonempty token; player mode is unavailable."},
   Operation{Clock{}, "world.clock", "query", DeveloperOnly{}, [], False{}, "Return tick, daylight/time, pause state, revision and pending count."},
   Operation{Pause{}, "simulation.pause", "control", DeveloperOnly{}, [Field{"paused", Boolean{}, True{}}], False{}, "Set the shared simulation pause state immediately."},
   Operation{StepTicks{}, "simulation.step", "control", DeveloperOnly{}, [Field{"ticks", Unsigned{1, 1000}, True{}}], False{}, "Advance the shared core by one through 1000 ticks; pause state remains unchanged."},
   Operation{Create{}, "world.section.create", "admission", DeveloperOnly{}, List.append(&2, Field, coordinate_fields(), [Field{"fill", Unsigned{0, 4294967295}, True{}}]), True{}, "Schedule creation of the section containing this signed block position; existence is checked when applied."},
   Operation{Get{}, "world.block.get", "query", DeveloperOnly{}, coordinate_fields(), False{}, "Read a registry state ID from an existing section."},
   Operation{Set{}, "world.block.set", "admission", DeveloperOnly{}, List.append(&2, Field, coordinate_fields(), [Field{"state", Unsigned{0, 4294967295}, True{}}]), True{}, "Schedule one registry state ID update; section presence is checked when applied."},
   Operation{Time{}, "world.time.set", "admission", DeveloperOnly{}, [Field{"day_time", Unsigned{0, 4294967295}, True{}}], True{}, "Schedule a foundation day-time value."},
   Operation{Daylight{}, "world.daylight.set", "admission", DeveloperOnly{}, [Field{"enabled", Boolean{}, True{}}], True{}, "Schedule the foundation daylight-cycle switch."},
   Operation{Cancel{}, "action.cancel", "control", DeveloperOnly{}, [Field{"peer", Unsigned{0, 4294967295}, True{}}, Field{"sequence", Unsigned{1, 4294967295}, True{}}, Field{"tick", Unsigned{0, 4294967295}, False{}}], False{}, "Cancel a pending action by this session's peer/sequence identity; optional tick is validated but ignored."},
   Operation{Events{}, "world.events", "query", DeveloperOnly{}, [], False{}, "Snapshot up to 1024 newest core applied/rejected events; this is not a subscription."}]

def name_in(names: List<&2, String>, +name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case h <> t: String.eq(h, name) || name_in(t, name)

def field_names(fields: List<&2, Field>) -> List<&2, String>:
  match fields:
    case Nil{}: []
    case Field{name, arg, req} <> tail: name <> field_names(tail)

def names_continue(pair: Map<&2, Unit> & Bool, known: Bool, rest: Map<&2, Unit> -> Bool) -> Bool:
  (seen, duplicate) = pair
  match duplicate known:
    case False{} True{}: rest(seen)
    case _ _: False{}

def valid_names(members: List<&2, J.Member>, +names: List<&2, String>, seen: Map<&2, Unit>) -> Bool:
  match members:
    case Nil{}: True{}
    case J.JMember{+key, value} <> tail:
      names_continue(Map.has(&2, Unit, seen, key), name_in(names, key), next => valid_names(tail, names, Map.set(&2, Unit, next, key, Unit{})))

def i32_magnitude(found: Maybe<&2, U32>, negative: Bool) -> Maybe<&2, U32>:
  match found negative:
    case None{} _: None{}
    case Some{+n} True{}:
      J.choose(Maybe<&2, U32>, Some{U32.sub(0, n)}, None{}, U32.is_le(n, 2147483648))
    case Some{+n} False{}:
      J.choose(Maybe<&2, U32>, Some{n}, None{}, U32.is_le(n, 2147483647))

def i32_raw(raw: String) -> Maybe<&2, U32>:
  match raw:
    case SCon{Chr{45}, tail}: i32_magnitude(J.u32_lexeme(tail), True{})
    case other: i32_magnitude(J.u32_lexeme(other), False{})

def as_i32(value: J.Value) -> Maybe<&2, U32>:
  match value:
    case J.JNumber{raw}: i32_raw(raw)
    case _: None{}

def bounded(found: Maybe<&2, U32>, minimum: U32, maximum: U32) -> Bool:
  match found:
    case None{}: False{}
    case Some{+n}: U32.is_ge(n, minimum) && U32.is_le(n, maximum)

def string_map_next(pair: Map<&2, Unit> & Bool, key: String, rest: Map<&2, Unit> -> Bool) -> Bool:
  (seen, duplicate) = pair
  match duplicate:
    case True{}: False{}
    case False{}: rest(Map.set(&2, Unit, seen, key, Unit{}))

def string_map_members(members: List<&2, J.Member>, seen: Map<&2, Unit>) -> Bool:
  match members:
    case Nil{}: True{}
    case J.JMember{+key, J.JString{value}} <> tail:
      string_map_next(Map.has(&2, Unit, seen, key), key, next => string_map_members(tail, next))
    case _: False{}

def valid_argument(argument: Argument, value: J.Value) -> Bool:
  match argument value:
    case Text{+allowed} J.JString{s}: List.is_empty(&2, String, allowed) || name_in(allowed, s)
    case Boolean{} J.JBool{b}: True{}
    case Unsigned{minimum, maximum} v: bounded(J.as_u32(v), minimum, maximum)
    case Signed{} v: Maybe.is_some(&2, U32, as_i32(v))
    case StringMap{} J.JObject{members}: string_map_members(members, MTip{})
    case _ _: False{}

def valid_field(found: Maybe<&2, J.Value>, argument: Argument, required: Bool) -> Bool:
  match found:
    case None{}: Bool.not(required)
    case Some{value}: valid_argument(argument, value)

def valid_fields(fields: List<&2, Field>, +args: J.Value) -> Bool:
  match fields:
    case Nil{}: True{}
    case Field{name, argument, req} <> tail:
      valid_field(J.member(args, name), argument, req) && valid_fields(tail, args)

def validate_args(args: J.Value, +fields: List<&2, Field>) -> Bool:
  match args:
    case J.JObject{+members}:
      valid_names(members, field_names(fields), MTip{}) && valid_fields(fields, J.JObject{members})
    case _: False{}

def lookup(operations: List<&2, Operation>, +name: String) -> Maybe<&2, Operation>:
  match operations:
    case Nil{}: None{}
    case +op <> tail:
      Operation{tag, +actual, phase, access, fields, scheduled, description} = op
      J.choose(Maybe<&2, Operation>, Some{op}, lookup(tail, name), String.eq(actual, name))

def from_string(found: Maybe<&2, J.Value>, +name: String) -> Result<&2, &2, Fault, String>:
  match found:
    case Some{J.JString{s}}: Done{s}
    case _: Fail{invalid(name)}

def get_string(+args: J.Value, +name: String) -> Result<&2, &2, Fault, String>:
  from_string(J.member(args, name), name)

def optional_string(found: Maybe<&2, J.Value>) -> Result<&2, &2, Fault, String>:
  match found:
    case None{}: Done{""}
    case Some{J.JString{s}}: Done{s}
    case _: Fail{invalid("token")}

def from_number(found: Maybe<&2, U32>, name: String) -> Result<&2, &2, Fault, U32>:
  match found:
    case Some{n}: Done{n}
    case None{}: Fail{invalid(name)}

def number_value(found: Maybe<&2, J.Value>, +name: String, signed: Bool) -> Result<&2, &2, Fault, U32>:
  match found:
    case None{}: Fail{invalid(name)}
    case Some{+value}:
      from_number(J.choose(Maybe<&2, U32>, as_i32(value), J.as_u32(value), signed), name)

def get_number(+args: J.Value, +name: String, signed: Bool) -> Result<&2, &2, Fault, U32>:
  number_value(J.member(args, name), name, signed)

def from_bool(found: Maybe<&2, J.Value>, name: String) -> Result<&2, &2, Fault, Bool>:
  match found:
    case Some{J.JBool{b}}: Done{b}
    case _: Fail{invalid(name)}

def get_bool(+args: J.Value, +name: String) -> Result<&2, &2, Fault, Bool>:
  from_bool(J.member(args, name), name)

def position(+args: J.Value) -> Result<&2, &2, Fault, C.Position>:
  do Result<&2, &2, Fault, C.Position>:
    d : String <- get_string(args, "dimension")
    x : U32 <- get_number(args, "x", True{})
    y : U32 <- get_number(args, "y", True{})
    z : U32 <- get_number(args, "z", True{})
    return C.Position{d, x, y, z}

def arguments(found: Maybe<&2, J.Value>) -> Result<&2, &2, Fault, J.Value>:
  match found:
    case None{}: Done{obj([])}
    case Some{J.JObject{members}}: Done{J.JObject{members}}
    case _: Fail{bad("InvalidRequest", "args must be an object")}

def at_value(found: Maybe<&2, U32>) -> Result<&2, &2, Fault, Maybe<&2, Nat>>:
  match found:
    case None{}: Fail{bad("InvalidRequest", "at must be an unsigned U32 integer lexeme")}
    case Some{n}: Done{Some{U32.to_nat(n)}}

def at(found: Maybe<&2, J.Value>) -> Result<&2, &2, Fault, Maybe<&2, Nat>>:
  match found:
    case None{}: Done{None{}}
    case Some{value}: at_value(J.as_u32(value))

def envelope_string(found: Maybe<&2, J.Value>, name: String) -> Result<&2, &2, Fault, String>:
  match found:
    case Some{J.JString{s}}: Done{s}
    case _: Fail{bad("InvalidRequest", name ++ " must be a string")}

def envelope_fields(+request: J.Value, valid: Bool) -> Result<&2, &2, Fault, Envelope>:
  match valid:
    case False{}: Fail{bad("InvalidRequest", "unknown or duplicate request field")}
    case True{}:
      do Result<&2, &2, Fault, Envelope>:
        id : String <- envelope_string(J.member(request, "id"), "id")
        op : String <- envelope_string(J.member(request, "op"), "op")
        args : J.Value <- arguments(J.member(request, "args"))
        tick : Maybe<&2, Nat> <- at(J.member(request, "at"))
        return Envelope{id, op, args, tick}

def envelope(request: J.Value) -> Result<&2, &2, Fault, Envelope>:
  match request:
    case J.JObject{+members}:
      envelope_fields(J.JObject{members}, valid_names(members, ["id", "op", "args", "at"], MTip{}))
    case _: Fail{bad("InvalidRequest", "request must be an object")}

def id_of(found: Maybe<&2, J.Value>) -> String:
  match found:
    case Some{J.JString{id}}: id
    case _: ""

def decode(tag: Tag, +args: J.Value) -> Result<&2, &2, Fault, Command>:
  match tag:
    case Discover{}: Done{DiscoverCommand{}}
    case Ping{}: Done{PingCommand{}}
    case Open{}:
      do Result<&2, &2, Fault, Command>:
        mode : String <- get_string(args, "mode")
        token : String <- optional_string(J.member(args, "token"))
        return OpenCommand{mode, token}
    case Clock{}: Done{ClockCommand{}}
    case Pause{}:
      do Result<&2, &2, Fault, Command>:
        paused : Bool <- get_bool(args, "paused")
        return PauseCommand{paused}
    case StepTicks{}:
      do Result<&2, &2, Fault, Command>:
        ticks : U32 <- get_number(args, "ticks", False{})
        return StepCommand{ticks}
    case Create{}:
      do Result<&2, &2, Fault, Command>:
        p : C.Position <- position(args)
        fill : U32 <- get_number(args, "fill", False{})
        return CreateCommand{p, fill}
    case Get{}:
      do Result<&2, &2, Fault, Command>:
        p : C.Position <- position(args)
        return GetCommand{p}
    case Set{}:
      do Result<&2, &2, Fault, Command>:
        p : C.Position <- position(args)
        state : U32 <- get_number(args, "state", False{})
        return SetCommand{p, state}
    case Time{}:
      do Result<&2, &2, Fault, Command>:
        time : U32 <- get_number(args, "day_time", False{})
        return TimeCommand{time}
    case Daylight{}:
      do Result<&2, &2, Fault, Command>:
        enabled : Bool <- get_bool(args, "enabled")
        return DaylightCommand{enabled}
    case Cancel{}:
      do Result<&2, &2, Fault, Command>:
        p : U32 <- get_number(args, "peer", False{})
        seq : U32 <- get_number(args, "sequence", False{})
        return CancelCommand{p, seq}
    case Events{}: Done{EventsCommand{}}

# JSON-schema emission derives directly from the same argument descriptors.
def texts(values: List<&2, String>) -> List<&2, J.Value>:
  match values:
    case Nil{}: []
    case h <> t: text(h) <> texts(t)

def argument_schema(argument: Argument) -> J.Value:
  match argument:
    case Text{Nil{}}: obj([J.JMember{"type", text("string")}])
    case Text{h <> t}: obj([J.JMember{"type", text("string")}, J.JMember{"enum", J.JArray{texts(h <> t)}}])
    case Boolean{}: obj([J.JMember{"type", text("boolean")}])
    case Unsigned{minimum, maximum}:
      obj([J.JMember{"type", text("integer")}, J.JMember{"minimum", uint(minimum)}, J.JMember{"maximum", uint(maximum)}, J.JMember{"x-number-format", text("unsigned-integer-lexeme")}])
    case Signed{}:
      obj([J.JMember{"type", text("integer")}, J.JMember{"minimum", J.JNumber{"-2147483648"}}, J.JMember{"maximum", uint(2147483647)}, J.JMember{"x-number-format", text("signed-integer-lexeme")}])
    case StringMap{}:
      obj([J.JMember{"type", text("object")}, J.JMember{"additionalProperties", obj([J.JMember{"type", text("string")}])}])

def schema_properties(fields: List<&2, Field>) -> List<&2, J.Member>:
  match fields:
    case Nil{}: []
    case Field{name, arg, req} <> rest: J.JMember{name, argument_schema(arg)} <> schema_properties(rest)

def schema_required(fields: List<&2, Field>) -> List<&2, J.Value>:
  match fields:
    case Nil{}: []
    case Field{name, arg, True{}} <> rest: text(name) <> schema_required(rest)
    case Field{name, arg, False{}} <> rest: schema_required(rest)

def args_schema(+fields: List<&2, Field>) -> J.Value:
  obj([J.JMember{"type", text("object")}, J.JMember{"properties", obj(schema_properties(fields))},
    J.JMember{"required", J.JArray{schema_required(fields)}}, J.JMember{"additionalProperties", boolean(False{})}])

def request_properties(name: String, fields: List<&2, Field>, scheduled: Bool) -> List<&2, J.Member>:
  +base = {[J.JMember{"id", argument_schema(Text{[]})}, J.JMember{"op", obj([J.JMember{"const", text(name)}])}, J.JMember{"args", args_schema(fields)}] : List<&2, J.Member>}
  J.choose(List<&2, J.Member>, List.append(&2, J.Member, base, [J.JMember{"at", argument_schema(Unsigned{0, 4294967295})}]), base, scheduled)

def request_schema(name: String, +fields: List<&2, Field>, scheduled: Bool) -> J.Value:
  obj([J.JMember{"type", text("object")}, J.JMember{"properties", obj(request_properties(name, fields, scheduled))},
    J.JMember{"required", J.JArray{J.choose(List<&2, J.Value>, [text("id"), text("op")], [text("id"), text("op"), text("args")], List.is_empty(&2, J.Value, schema_required(fields)))}}, J.JMember{"additionalProperties", boolean(False{})}])

def access_name(access: Access) -> String:
  match access:
    case Public{}: "observer"
    case DeveloperOnly{}: "developer"

def operation_value(operation: Operation) -> J.Value:
  match operation:
    case Operation{tag, +name, phase, access, fields, +scheduled, description}:
      obj([J.JMember{"name", text(name)}, J.JMember{"phase", text(phase)}, J.JMember{"permitted_mode", text(access_name(access))},
        J.JMember{"version", text("26.3")}, J.JMember{"status", text("implemented-foundation")}, J.JMember{"scheduled", boolean(scheduled)},
        J.JMember{"description", text(description)}, J.JMember{"input_schema", request_schema(name, fields, scheduled)}])

def catalog_values(operations: List<&2, Operation>) -> List<&2, J.Value>:
  match operations:
    case Nil{}: []
    case h <> t: operation_value(h) <> catalog_values(t)

def discovery() -> J.Value:
  obj([J.JMember{"version", text("26.3")}, J.JMember{"surface", text("section-and-tick-foundation")},
    J.JMember{"operations", J.JArray{catalog_values(catalog())}}, J.JMember{"subscriptions", boolean(False{})}, J.JMember{"batch", boolean(False{})}, J.JMember{"player_mode", boolean(False{})}])

def stamp_value(stamp: Q.Stamp) -> J.Value:
  match stamp:
    case Q.Stamp{tick, peer, seq}:
      obj([J.JMember{"tick", natural(tick)}, J.JMember{"peer", uint(peer)}, J.JMember{"sequence", natural(seq)}])

def clock_value(clock: C.Clock) -> J.Value:
  match clock:
    case C.Clock{tick, time, paused, daylight, revision, pending}:
      obj([J.JMember{"tick", natural(tick)}, J.JMember{"day_time", natural(time)}, J.JMember{"paused", boolean(paused)},
        J.JMember{"daylight", boolean(daylight)}, J.JMember{"revision", natural(revision)}, J.JMember{"pending", natural(pending)}])

def core_fault(error: C.Error) -> Fault:
  match error:
    case C.PermissionDenied{}: bad("PermissionDenied", "developer capability required")
    case C.UnknownDimension{d}: bad("UnknownDimension", "unknown dimension: " ++ d)
    case C.InvalidState{s}: bad("InvalidState", "registry state ID out of range: " ++ U32.show(s))
    case C.MissingSection{k}: bad("MissingSection", "section does not exist: " ++ k)
    case C.SectionExists{k}: bad("SectionExists", "section already exists: " ++ k)
    case C.InvalidCoordinate{}: bad("InvalidCoordinate", "invalid section coordinate")
    case C.PastTick{}: bad("PastTick", "scheduled tick must be later than the current world tick")
    case C.TooManyPending{}: bad("TooManyPending", "pending action capacity reached")

def event_value(event: C.CoreEvent) -> J.Value:
  match event:
    case C.Applied{stamp, revision}:
      obj([J.JMember{"kind", text("applied")}, J.JMember{"stamp", stamp_value(stamp)}, J.JMember{"revision", natural(revision)}])
    case C.Rejected{stamp, error}:
      obj([J.JMember{"kind", text("rejected")}, J.JMember{"stamp", stamp_value(stamp)}, J.JMember{"error", fault_value(core_fault(error))}])

def event_values(events: List<&2, C.CoreEvent>) -> List<&2, J.Value>:
  match events:
    case Nil{}: []
    case h <> t: event_value(h) <> event_values(t)

def clock_response(pair: C.World & C.Clock, session: Session, id: String) -> C.World & Session & J.Value:
  (w, clock) = pair
  success(w, session, id, clock_value(clock))

def events_response(pair: C.World & List<&2, C.CoreEvent>, session: Session, id: String) -> C.World & Session & J.Value:
  (w, events) = pair
  success(w, session, id, obj([J.JMember{"order", text("newest-first")}, J.JMember{"events", J.JArray{event_values(events)}}]))

def admitted(pair: C.World & Result<&2, &2, C.Error, Unit>, session: Session, id: String, stamp: Q.Stamp) -> C.World & Session & J.Value:
  (w, result) = pair
  match result:
    case Fail{error}: failure(w, session, id, core_fault(error))
    case Done{u}: success(w, session, id, obj([J.JMember{"accepted", boolean(True{})}, J.JMember{"stamp", stamp_value(stamp)}]))

def target_tick(at: Maybe<&2, Nat>, current: Nat) -> Nat:
  match at:
    case None{}: 1n+current
    case Some{tick}: tick

def clock_tick(clock: C.Clock) -> Nat:
  C.Clock{tick, time, paused, daylight, revision, pending} = clock
  tick

def clock_pending(clock: C.Clock) -> Nat:
  C.Clock{tick, time, paused, daylight, revision, pending} = clock
  pending

def mutation_clock(pair: C.World & C.Clock, +session: Session, id: String, at: Maybe<&2, Nat>, mutation: C.Mutation) -> C.World & Session & J.Value:
  (w, clock) = pair
  +stamp = {Q.Stamp{target_tick(at, clock_tick(clock)), peer(session), sequence(session)} : Q.Stamp}
  admitted(C.admit(w, capability(session), stamp, mutation), session, id, stamp)

def mutate(w: C.World, session: Session, id: String, at: Maybe<&2, Nat>, mutation: C.Mutation) -> C.World & Session & J.Value:
  mutation_clock(C.clock(w), session, id, at, mutation)

def read_response(pair: C.World & Result<&2, &2, C.Error, U32>, session: Session, id: String) -> C.World & Session & J.Value:
  (w, result) = pair
  match result:
    case Fail{error}: failure(w, session, id, core_fault(error))
    case Done{state}: success(w, session, id, obj([J.JMember{"state", uint(state)}]))

def read_known(known: Bool, w: C.World, session: Session, id: String, +p: C.Position) -> C.World & Session & J.Value:
  match known:
    case False{}: failure(w, session, id, core_fault(C.UnknownDimension{C.dimension(p)}))
    case True{}: read_response(C.read_block(w, p), session, id)

def opened(allowed: Bool, w: C.World, session: Session, id: String, +cap: C.Capability) -> C.World & Session & J.Value:
  match allowed:
    case False{}: failure(w, session, id, bad("AuthenticationFailed", "developer token rejected"))
    case True{}:
      Session{+p, +seq, old} = session
      success(w, Session{p, seq, cap}, id, obj([J.JMember{"mode", text(mode_name(cap))}, J.JMember{"peer", uint(p)}, J.JMember{"sequence", natural(seq)}]))

def open_mode(mode: String, w: C.World, session: Session, id: String, +configured: String, supplied: String) -> C.World & Session & J.Value:
  match mode:
    case "developer": opened(Bool.not(String.is_empty(configured)) && String.eq(configured, supplied), w, session, id, C.Developer{})
    case "observer": opened(True{}, w, session, id, C.Observer{})
    case "player": failure(w, session, id, bad("PlayerUnavailable", "player mode requires a real player/abilities binding and is unavailable"))
    case _: failure(w, session, id, invalid("mode"))

def cancel_after(pair: C.World & C.Clock, session: Session, id: String, before: Nat, p: U32, seq: U32) -> C.World & Session & J.Value:
  (w, clock) = pair
  success(w, session, id, obj([J.JMember{"cancelled", boolean(Nat.is_lt(clock_pending(clock), before))}, J.JMember{"peer", uint(p)}, J.JMember{"sequence", uint(seq)}]))

def cancel_before(pair: C.World & C.Clock, session: Session, id: String, +p: U32, +seq: U32) -> C.World & Session & J.Value:
  (w, clock) = pair
  cancel_after(C.clock(C.cancel(w, Q.Stamp{0n, p, U32.to_nat(seq)})), session, id, clock_pending(clock), p, seq)

def cancel_checked(valid: Bool, w: C.World, session: Session, id: String, p: U32, seq: U32) -> C.World & Session & J.Value:
  match valid:
    case False{}: failure(w, session, id, bad("PermissionDenied", "cancellation requires this peer and a prior server sequence"))
    case True{}: cancel_before(C.clock(w), session, id, p, seq)

def execute(command: Command, w: C.World, +session: Session, configured: String, id: String, at: Maybe<&2, Nat>) -> C.World & Session & J.Value:
  match command:
    case DiscoverCommand{}: success(w, session, id, discovery())
    case PingCommand{}:
      success(w, session, id, obj([J.JMember{"version", text("26.3")}, J.JMember{"peer", uint(peer(session))}, J.JMember{"sequence", natural(sequence(session))}, J.JMember{"mode", text(mode_name(capability(session)))}]))
    case OpenCommand{mode, token}: open_mode(mode, w, session, id, configured, token)
    case ClockCommand{}: clock_response(C.clock(w), session, id)
    case PauseCommand{paused}: clock_response(C.clock(C.set_paused(w, paused)), session, id)
    case StepCommand{ticks}: clock_response(C.clock(C.advance(U32.to_nat(ticks), w)), session, id)
    case CreateCommand{p, fill}: mutate(w, session, id, at, C.SectionCreate{p, fill})
    case GetCommand{+p}: read_known(C.dimension_known(C.dimension(p)), w, session, id, p)
    case SetCommand{p, state}: mutate(w, session, id, at, C.BlockSet{p, state})
    case TimeCommand{time}: mutate(w, session, id, at, C.TimeSet{U32.to_nat(time)})
    case DaylightCommand{enabled}: mutate(w, session, id, at, C.DaylightSet{enabled})
    case CancelCommand{+p, +seq}:
      cancel_checked(U32.is_eq(p, peer(session)) && Nat.is_lt(U32.to_nat(seq), sequence(session)), w, session, id, p, seq)
    case EventsCommand{}: events_response(C.events(w), session, id)

def execute_decoded(result: Result<&2, &2, Fault, Command>, w: C.World, session: Session, configured: String, id: String, at: Maybe<&2, Nat>) -> C.World & Session & J.Value:
  match result:
    case Fail{fault}: failure(w, session, id, fault)
    case Done{command}: execute(command, w, session, configured, id, at)

def permitted(access: Access, session: Session) -> Bool:
  match access:
    case Public{}: True{}
    case DeveloperOnly{}: C.developer(capability(session))

def checked_operation(valid: Bool, allowed: Bool, w: C.World, session: Session, configured: String, id: String, tag: Tag, args: J.Value, at: Maybe<&2, Nat>) -> C.World & Session & J.Value:
  match valid allowed:
    case False{} _: failure(w, session, id, bad("InvalidArguments", "arguments or scheduled at field do not match the operation schema"))
    case True{} False{}: failure(w, session, id, bad("PermissionDenied", "developer capability required"))
    case True{} True{}: execute_decoded(decode(tag, args), w, session, configured, id, at)

def operation_ready(found: Maybe<&2, Operation>, w: C.World, +session: Session, configured: String, id: String, +args: J.Value, +at: Maybe<&2, Nat>) -> C.World & Session & J.Value:
  match found:
    case None{}: failure(w, session, id, bad("UnknownOperation", "operation is not implemented"))
    case Some{Operation{tag, name, phase, +access, fields, scheduled, description}}:
      checked_operation(validate_args(args, fields) && (scheduled || Maybe.is_none(&2, Nat, at)), permitted(access, session), w, session, configured, id, tag, args, at)

def dispatch_envelope(result: Result<&2, &2, Fault, Envelope>, w: C.World, session: Session, configured: String, fallback_id: String) -> C.World & Session & J.Value:
  match result:
    case Fail{fault}: failure(w, session, fallback_id, fault)
    case Done{Envelope{id, +op, args, at}}: operation_ready(lookup(catalog(), op), w, session, configured, id, args, at)

def dispatch(w: C.World, session: Session, developer_token: String, +request: J.Value) -> C.World & Session & J.Value:
  Session{p, seq, cap} = session
  dispatch_envelope(envelope(request), w, Session{p, 1n+seq, cap}, developer_token, id_of(J.member(request, "id")))
