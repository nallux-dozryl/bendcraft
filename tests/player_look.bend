import Base
import ../src/f64.bend as F
import ../src/player_look.bend as L

law raw_bitcast_inverse:
  for bits: U32
  {L.raw(L.float_bits(bits)) == bits : U32}

def raw_bitcast_inverse(bits):
  match bits:
    case U32{word}: {==}

law positive_zero_delta:
  {L.raw(L.delta(F.F64{0, 0})) == 0 : U32}

def positive_zero_delta():
  {==}

law negative_zero_delta:
  {L.raw(L.delta(F.F64{2147483648, 0})) == 2147483648 : U32}

def negative_zero_delta():
  {==}

law zero_turn_fixture:
  {L.turn_raw(L.State{L.float_bits(0), L.float_bits(0), L.float_bits(0), L.float_bits(0)}, F.F64{0, 0}, F.F64{0, 0}) == L.State{L.float_bits(0), L.float_bits(0), L.float_bits(0), L.float_bits(0)} : L.State}

def zero_turn_fixture():
  {==}

law wrapped_pitch_zero_delta:
  {L.turn_raw(L.State{L.float_bits(1099431936), L.float_bits(1136033792), L.float_bits(3253207040), L.float_bits(1136033792)}, F.F64{0, 0}, F.F64{0, 0}) == L.State{L.float_bits(1099431936), L.float_bits(1084227584), L.float_bits(3253207040), L.float_bits(1119092736)} : L.State}

def wrapped_pitch_zero_delta():
  {==}

law rejected_turn_retains_state:
  for +state: L.State
  for dx: F.F64
  for dy: F.F64
  for +error: L.Error
  {(state, L.turn_gate(state, dx, dy, Some{error})) == (state, Fail{error}) : L.State & Result<&2, &2, L.Error, L.State>}

def rejected_turn_retains_state(state, dx, dy, error):
  {==}

law finite_state_has_no_error:
  {L.state_error(L.State{L.float_bits(0), L.float_bits(0), L.float_bits(0), L.float_bits(0)}) == None{} : Maybe<&2, L.Error>}

def finite_state_has_no_error():
  {==}

law nonfinite_input_rejected:
  {L.input_error(F.F64{2146435072, 0}, F.F64{0, 0}) == Some{L.InvalidInput{0}} : Maybe<&2, L.Error>}

def nonfinite_input_rejected():
  {==}

# Native fixture observer receives raw U32 words only. It compares both checked
# API status and the actual finite-input IEEE diagnostics of turn_raw.
def state_words(value: L.State) -> String:
  match value:
    case L.State{a, b, c, d}: "[" ++ U32.show(L.raw(a)) ++ "," ++ U32.show(L.raw(b)) ++ "," ++ U32.show(L.raw(c)) ++ "," ++ U32.show(L.raw(d)) ++ "]"

def error_words(value: L.Error) -> String:
  match value:
    case L.InvalidState{field}: "{\"kind\":\"InvalidState\",\"field\":" ++ U32.show(field) ++ "}"
    case L.InvalidInput{axis}: "{\"kind\":\"InvalidInput\",\"field\":" ++ U32.show(axis) ++ "}"
    case L.NonFiniteResult{field}: "{\"kind\":\"NonFiniteResult\",\"field\":" ++ U32.show(field) ++ "}"

def result_words(result: Result<&2, &2, L.Error, L.State>) -> String:
  match result:
    case Done{state}: "\"ok\":true,\"state\":" ++ state_words(state)
    case Fail{error}: "\"ok\":false,\"error\":" ++ error_words(error)

def report_gate(+state: L.State, +dx: F.F64, +dy: F.F64, error: Maybe<&2, L.Error>) -> String:
  match error:
    case Some{error}: "{" ++ result_words(Fail{error}) ++ "}"
    case None{}: "{" ++ result_words(L.turn(state, dx, dy)) ++ ",\"raw_state\":" ++ state_words(L.turn_raw(state, dx, dy)) ++ "}"

def report(+state: L.State, +dx: F.F64, +dy: F.F64) -> String:
  report_gate(state, dx, dy, L.first_error(L.state_error(state), L.input_error(dx, dy)))

def fixture(a: Maybe<&2, U32>, b: Maybe<&2, U32>, c: Maybe<&2, U32>, d: Maybe<&2, U32>,
            x: Maybe<&2, U32>, y: Maybe<&2, U32>, z: Maybe<&2, U32>, w: Maybe<&2, U32>) -> IO(Unit):
  match a b c d x y z w:
    case Some{a} Some{b} Some{c} Some{d} Some{x} Some{y} Some{z} Some{w}:
      IO.print(report(L.State{L.float_bits(a), L.float_bits(b), L.float_bits(c), L.float_bits(d)}, F.F64{x, y}, F.F64{z, w}))
    case _ _ _ _ _ _ _ _: IO.die(Unit, 2, "invalid raw look fixture word")

def batch(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case a <> b <> c <> d <> x <> y <> z <> w <> rest:
      do IO<Unit>:
        fixture(U32.read(a), U32.read(b), U32.read(c), U32.read(d), U32.read(x), U32.read(y), U32.read(z), U32.read(w))
        batch(rest)
    case _: IO.die(Unit, 2, "expected YAW PITCH PREV_YAW PREV_PITCH DX_HI DX_LO DY_HI DY_LO groups")

type Deltas is Data:
  Deltas{dx: F.F64, dy: F.F64}

def read_deltas(a: Maybe<&2, U32>, b: Maybe<&2, U32>, c: Maybe<&2, U32>, d: Maybe<&2, U32>) -> Maybe<&2, Deltas>:
  match a b c d:
    case Some{a} Some{b} Some{c} Some{d}: Some{Deltas{F.F64{a, b}, F.F64{c, d}}}
    case _ _ _ _: None{}

def deltas_gate(value: Maybe<&2, Deltas>) -> IO(Unit):
  match value:
    case None{}: IO.die(Unit, 2, "invalid raw chained look input")
    case Some{_}: IO.pure(Unit, Unit{})

def delta_x(value: Maybe<&2, Deltas>) -> F.F64:
  match value:
    case None{}: F.F64{0, 0}
    case Some{Deltas{dx, _}}: dx

def delta_y(value: Maybe<&2, Deltas>) -> F.F64:
  match value:
    case None{}: F.F64{0, 0}
    case Some{Deltas{_, dy}}: dy

def chain_written(result: Result<&2, &2, L.Error, L.State>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 2, "chain rejected: " ++ error_words(error))
    case Done{+state}: IO.print("{" ++ result_words(Done{state}) ++ ",\"raw_state\":" ++ state_words(state) ++ "}")

def chain_advanced(result: Result<&2, &2, L.Error, L.State>, fallback: L.State) -> L.State:
  match result:
    case Fail{_}: fallback
    case Done{state}: state

def chain(args: List<String>, +state: L.State) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case x <> y <> z <> w <> rest:
      +parsed = read_deltas(U32.read(x), U32.read(y), U32.read(z), U32.read(w))
      +result = L.turn(state, delta_x(parsed), delta_y(parsed))
      do IO<Unit>:
        deltas_gate(parsed)
        chain_written(result)
        chain(rest, chain_advanced(result, state))
    case _: IO.die(Unit, 2, "expected chained DX_HI DX_LO DY_HI DY_LO groups")

def chain_initial(a: Maybe<&2, U32>, b: Maybe<&2, U32>, c: Maybe<&2, U32>, d: Maybe<&2, U32>, rest: List<String>) -> IO(Unit):
  match a b c d:
    case Some{a} Some{b} Some{c} Some{d}: chain(rest, L.State{L.float_bits(a), L.float_bits(b), L.float_bits(c), L.float_bits(d)})
    case _ _ _ _: IO.die(Unit, 2, "invalid raw chained look state")

def entry(args: List<String>) -> IO(Unit):
  match args:
    case "chain" <> a <> b <> c <> d <> rest: chain_initial(U32.read(a), U32.read(b), U32.read(c), U32.read(d), rest)
    case _: batch(args)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    entry(List.tail(&1, String, args))
