import Base
import ../src/f64.bend as F
import ../src/movement.bend as M
import ../src/player_look.bend as PL
import ../src/entity_common_tick.bend as E

law positive_countdown_one_reaches_zero:
  {E.decrement(1) == 0 : U32}
def positive_countdown_one_reaches_zero():
  {==}

law signed_negative_countdown_is_retained:
  {E.decrement(2147483648) == 2147483648 : U32}
def signed_negative_countdown_is_retained():
  {==}

law minus_one_countdown_is_retained:
  {E.decrement(4294967295) == 4294967295 : U32}
def minus_one_countdown_is_retained():
  {==}

law common_counter_wraps:
  {E.counter(4294967295, True{}) == 0 : U32}
def common_counter_wraps():
  {==}

law finite_field_refusal_does_not_depend_on_magnitude:
  for field: U32
  {E.finite_field(field, True{}) == None{} : Maybe<&2, E.Error>}
def finite_field_refusal_does_not_depend_on_magnitude(field):
  {==}

# Raw U32 protocol only. No other tests or JSON modules are imported. Recursive
# boxes and named pair continuations retain all owners without broad captures.
type Case is Data:
  Case{flags: U32, metadata: E.Metadata, request: E.Request, tail: List<&2, Case>}

def truth(value: Bool) -> String:
  match value:
    case True{}: "true"
    case False{}: "false"

def words(value: F.F64) -> String:
  F.F64{hi, lo} = value
  "[" ++ U32.show(hi) ++ "," ++ U32.show(lo) ++ "]"

def vector(value: M.Vec3) -> String:
  M.Vec3{x, y, z} = value
  "[" ++ words(x) ++ "," ++ words(y) ++ "," ++ words(z) ++ "]"

def look(value: PL.State) -> String:
  PL.State{a, b, c, d} = value
  "[" ++ U32.show(PL.raw(a)) ++ "," ++ U32.show(PL.raw(b)) ++ "," ++ U32.show(PL.raw(c)) ++ "," ++ U32.show(PL.raw(d)) ++ "]"

def metadata(value: E.Metadata) -> String:
  E.Metadata{o, old, invulnerable, count} = value
  "{\"position_o\":" ++ vector(o) ++ ",\"position_old\":" ++ vector(old) ++ ",\"invulnerable\":" ++ U32.show(invulnerable) ++ ",\"count\":" ++ U32.show(count) ++ "}"

def context_code(value: E.Context) -> U32:
  match value:
    case E.NeutralClientInactiveInterpolation{}: 0
    case E.ActiveInterpolation{}: 1
    case E.NonClient{}: 2
    case E.UnsupportedLifecycle{}: 3

def request(value: E.Request) -> String:
  E.Request{position, angles, context, tail} = value
  "{\"position\":" ++ vector(position) ++ ",\"look\":" ++ look(angles) ++ ",\"context\":" ++ U32.show(context_code(context)) ++ ",\"nonempty_tail\":" ++ truth(Bool.not(List.is_empty(&2, E.Request, tail))) ++ "}"

def error(value: E.Error) -> String:
  match value:
    case E.NonCanonicalState{}: "{\"kind\":\"NonCanonicalState\"}"
    case E.NonCanonicalRequest{}: "{\"kind\":\"NonCanonicalRequest\"}"
    case E.UnsupportedContext{context}: "{\"kind\":\"UnsupportedContext\",\"context\":" ++ U32.show(context_code(context)) ++ "}"
    case E.NonFinite{field}: "{\"kind\":\"NonFinite\",\"field\":" ++ U32.show(field) ++ "}"

def status(value: Result<&2, &2, E.Error, E.Snapshot>) -> String:
  match value:
    case Fail{cause}: "{\"ok\":false,\"error\":" ++ error(cause) ++ "}"
    case Done{E.Snapshot{fields, angles}}: "{\"ok\":true,\"snapshot\":{\"metadata\":" ++ metadata(fields) ++ ",\"look\":" ++ look(angles) ++ "}}"

# The protocol constructs one child level only. This inspector retains any
# deeper owner verbatim and reports its presence rather than discarding it.
def serialize_child(value: E.State) -> E.State & String:
  match value:
    case E.State{+fields, Nil{}}: (E.State{fields, []}, "{\"metadata\":" ++ metadata(fields) ++ ",\"tail_nonempty\":false}")
    case E.State{+fields, child <> tail}: (E.State{fields, child <> tail}, "{\"metadata\":" ++ metadata(fields) ++ ",\"tail_nonempty\":true}")

def tail_rest(child: E.State, header: String, result: List<&1, E.State> & String) -> List<&1, E.State> & String:
  (rest, text) = result
  (child <> rest, header ++ "," ++ text)

def one_child(result: E.State & String) -> List<&1, E.State> & String:
  (child, text) = result
  (child <> Nil{}, text)

def tail_then(result: E.State & String, rest: List<&1, E.State> & String) -> List<&1, E.State> & String:
  (child, text) = result
  tail_rest(child, text, rest)

def serialize_tail(value: List<&1, E.State>) -> List<&1, E.State> & String:
  match value:
    case Nil{}: (Nil{}, "")
    case child <> Nil{}: one_child(serialize_child(child))
    case child <> next <> tail: tail_then(serialize_child(child), serialize_tail(next <> tail))

def state_tail(+fields: E.Metadata, result: List<&1, E.State> & String) -> E.State & String:
  (tail, text) = result
  (E.State{fields, tail}, "{\"metadata\":" ++ metadata(fields) ++ ",\"tail\":[" ++ text ++ "]}")

def serialize_state(value: E.State) -> E.State & String:
  E.State{fields, tail} = value
  state_tail(fields, serialize_tail(tail))

def rendered(req: E.Request, outcome: Result<&2, &2, E.Error, E.Snapshot>, result: E.State & String) -> E.State & String:
  (state, text) = result
  (state, "{\"state\":" ++ text ++ ",\"status\":" ++ status(outcome) ++ ",\"request\":" ++ request(req) ++ "}")

def report(req: E.Request, result: E.State & Result<&2, &2, E.Error, E.Snapshot>) -> E.State & String:
  (state, outcome) = result
  rendered(req, outcome, serialize_state(state))

def operation(state: E.State, req: E.Request, common: Bool) -> E.State & Result<&2, &2, E.Error, E.Snapshot>:
  match common:
    case False{}: E.set_old_pos_and_rot(state, req)
    case True{}: E.common_tick(state, req)

def next_request(req: E.Request, value: Result<&2, &2, E.Error, E.Snapshot>) -> E.Request:
  match req value:
    case req Fail{cause}: req
    case E.Request{position, old_look, context, tail} Done{E.Snapshot{fields, angles}}:
      E.Request{position, angles, context, tail}

type Work is Type:
  Begin{state: E.State, request: E.Request, modes: List<&2, Bool>, text: String, first: Bool}
  Operated{request: E.Request, modes: List<&2, Bool>, text: String, first: Bool, result: E.State & Result<&2,&2,E.Error,E.Snapshot>}
  Reported{request: E.Request, modes: List<&2, Bool>, text: String, first: Bool, result: E.State & String}

def append_line(text: String, line: String, first: Bool) -> String:
  match first:
    case True{}: line
    case False{}: text ++ "," ++ line

def steps_go(fuel: Nat, work: Work) -> E.State & String:
  match fuel work:
    case 0n Begin{state, req, modes, text, first}: (state, "{\"protocol_error\":\"step-limit\"}")
    case 0n Operated{req, modes, text, first, (state, outcome)}: (state, "{\"protocol_error\":\"step-limit\"}")
    case 0n Reported{req, modes, text, first, (state, line)}: (state, "{\"protocol_error\":\"step-limit\"}")
    case 1n+rest Begin{state, req, Nil{}, text, first}: (state, text)
    case 1n+rest Begin{state, +req, common <> modes, text, first}:
      steps_go(rest, Operated{req, modes, text, first, operation(state, req, common)})
    case 1n+rest Operated{+req, modes, text, first, (state, +outcome)}:
      steps_go(rest, Reported{next_request(req, outcome), modes, text, first, report(req, (state, outcome))})
    case 1n+rest Reported{req, modes, text, first, (state, line)}:
      steps_go(rest, Begin{state, req, modes, append_line(text, line, first), False{}})

def steps(fuel: Nat, state: E.State, req: E.Request, modes: List<&2, Bool>) -> E.State & String:
  steps_go(fuel, Begin{state, req, modes, "", True{}})

def repair64_if(value: F.F64, finite: Bool) -> F.F64:
  match finite:
    case True{}: value
    case False{}: F.from_u32(0)

def repair64(+value: F.F64) -> F.F64:
  repair64_if(value, F.is_finite(value))

def repair_vector(value: M.Vec3) -> M.Vec3:
  M.Vec3{x, y, z} = value
  M.Vec3{repair64(x), repair64(y), repair64(z)}

def repair32_if(value: F32, finite: Bool) -> F32:
  match finite:
    case True{}: value
    case False{}: PL.float_bits(0)

def repair32(+value: F32) -> F32:
  repair32_if(value, PL.finite(value))

def repair_request(value: E.Request) -> E.Request:
  E.Request{position, PL.State{a, b, c, d}, context, tail} = value
  E.Request{repair_vector(position), PL.State{repair32(a), repair32(b), repair32(c), repair32(d)}, E.NeutralClientInactiveInterpolation{}, []}

def repaired_fields(value: E.Metadata) -> E.Metadata:
  E.Metadata{o, old, invulnerable, count} = value
  E.Metadata{repair_vector(o), repair_vector(old), invulnerable, count}

def restored_children(child: E.State, header: String, result: List<&1, E.State> & String) -> List<&1, E.State> & String:
  (rest, text) = result
  (child <> rest, header ++ "," ++ text)

def restored_result(result: E.State & String, rest: List<&1,E.State> & String) -> List<&1,E.State> & String:
  (child, text) = result
  restored_children(child, text, rest)

def recover_children(+req: E.Request, value: List<&1, E.State>) -> List<&1, E.State> & String:
  match value:
    case Nil{}: (Nil{}, "")
    case child <> Nil{}: one_child(report(req, E.common_tick(child, req)))
    case child <> next <> tail: restored_result(report(req, E.common_tick(child, req)), recover_children(req, next <> tail))

def root_recovered(child_text: String, result: E.State & String) -> String:
  (state, text) = result
  "{\"root\":" ++ text ++ ",\"children\":[" ++ child_text ++ "]}"

def children_recovered(fields: E.Metadata, +req: E.Request, result: List<&1, E.State> & String) -> String:
  (children, text) = result
  root_recovered(text, report(req, E.common_tick(E.State{repaired_fields(fields), []}, req)))

def recover(state: E.State, +req: E.Request) -> String:
  E.State{fields, tail} = state
  children_recovered(fields, repair_request(req), recover_children(repair_request(req), tail))

def recovering(req: E.Request, result: E.State & String) -> String:
  (state, first) = result
  "{\"first\":" ++ first ++ ",\"recovery\":" ++ recover(state, req) ++ "}"

def context(value: U32) -> E.Context:
  match value:
    case 0: E.NeutralClientInactiveInterpolation{}
    case 1: E.ActiveInterpolation{}
    case 2: E.NonClient{}
    case _: E.UnsupportedLifecycle{}

def constant_metadata() -> E.Metadata:
  E.Metadata{M.Vec3{F.from_u32(7), F.from_u32(8), F.from_u32(9)}, M.Vec3.zero(), 7, 99}

def with_tail(fields: E.Metadata, nonempty: Bool) -> E.State:
  match nonempty:
    case False{}: E.State{fields, []}
    case True{}: E.State{fields, E.State{constant_metadata(), []} <> Nil{}}

def with_request_tail(position: M.Vec3, angles: PL.State, ctx: E.Context, nonempty: Bool) -> E.Request:
  match nonempty:
    case False{}: E.Request{position, angles, ctx, []}
    case True{}: E.Request{position, angles, ctx, E.Request{M.Vec3.zero(), PL.State{0.0,0.0,0.0,0.0}, E.NonClient{}, []} <> Nil{}}

def common_modes(fuel: Nat) -> List<&2, Bool>:
  match fuel:
    case 0n: []
    case 1n+rest: True{} <> common_modes(rest)

def finished(result: E.State & String) -> String:
  (state, text) = result
  "{\"steps\":[" ++ text ++ "]}"

def case_state(value: Case) -> E.State:
  Case{flags, fields, req, tail} = value
  with_tail(fields, U32.is_ne(U32.and(flags, 64), 0))

def case_request(value: Case) -> E.Request:
  Case{flags, fields, req, tail} = value
  req

def case_flags(value: Case) -> U32:
  Case{flags, fields, req, tail} = value
  flags

def recover_case(+value: Case) -> String:
  +req = case_request(value)
  recovering(req, report(req, E.common_tick(case_state(value), req)))

def dispatch_code(op: U32, +value: Case) -> String:
  match op:
    case 0: finished(steps(64n, case_state(value), case_request(value), False{} <> Nil{}))
    case 1: finished(steps(64n, case_state(value), case_request(value), True{} <> Nil{}))
    case 2: finished(steps(64n, case_state(value), case_request(value), common_modes(U32.to_nat(U32.and(U32.shrn(case_flags(value), 8n), 15)))))
    case 3: recover_case(value)
    case 4: finished(steps(64n, case_state(value), case_request(value), False{} <> True{} <> False{} <> True{} <> Nil{}))
    case _: "{\"protocol_error\":\"unknown-operation\"}"

def dispatch(+value: Case) -> String:
  dispatch_code(U32.and(case_flags(value), 7), value)

def cases(values: List<&2, U32>) -> List<&2, String>:
  match values:
    case Nil{}: []
    case +flags <> invulnerable <> count <> a <> b <> c <> d <> e <> f <> g <> h <> i <> j <> k <> l <> m <> n <> o <> p <> q <> r <> s <> t <> u <> v <> rest:
      dispatch(Case{flags, E.Metadata{M.Vec3{F.F64{a,b},F.F64{c,d},F.F64{e,f}}, M.Vec3{F.F64{g,h},F.F64{i,j},F.F64{k,l}}, invulnerable, count},
        with_request_tail(M.Vec3{F.F64{m,n},F.F64{o,p},F.F64{q,r}}, PL.State{PL.float_bits(s),PL.float_bits(t),PL.float_bits(u),PL.float_bits(v)}, context(U32.and(U32.shrn(flags, 4n),3)), U32.is_ne(U32.and(flags,128),0)), []}) <> cases(rest)
    case _: "{\"protocol_error\":\"truncated-record\"}" <> Nil{}

def read_word(value: Maybe<&2, U32>) -> Result<&2, &2, String, U32>:
  match value:
    case None{}: Fail{"invalid-u32"}
    case Some{word}: Done{word}

# Read all arguments before production dispatch. Invalid words fail the protocol.
def parse(values: List<String>) -> Result<&2, &2, String, List<&2, U32>>:
  match values:
    case Nil{}: Done{Nil{}}
    case first <> rest:
      # Result.bind sequences a parser failure without a computed match.
      do Result<&2, &2, String, List<&2, U32>>:
        number: U32 <- read_word(U32.read(first))
        tail: List<&2, U32> <- parse(rest)
        return number <> tail

def print_lines(lines: List<&2, String>) -> IO(Unit):
  match lines:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> rest:
      do IO<Unit>:
        IO.print(first)
        print_lines(rest)

def execute(value: Result<&2, &2, String, List<&2, U32>>) -> IO(Unit):
  match value:
    case Fail{error}: IO.print("{\"protocol_error\":\"invalid-u32\"}")
    case Done{values}: print_lines(cases(values))

def main() -> IO(Unit):
  do IO<Unit>:
    args: List<String> <- IO.args()
    execute(parse(List.tail(&1, String, args)))
