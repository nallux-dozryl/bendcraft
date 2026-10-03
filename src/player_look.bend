import Base
import ./f64.bend as F

# Degrees, retaining Entity's current and previous four raw F32 fields.
# This is the neutral no-vehicle Entity.turn angle operation, not MouseHandler.
type State is Data:
  State{yaw: F32, pitch: F32, previous_yaw: F32, previous_pitch: F32}

type Error is Data:
  InvalidState{field: U32}
  InvalidInput{axis: U32}
  NonFiniteResult{field: U32}

def choose(-A: Data, yes: A, no: A, test: Bool) -> A:
  match test:
    case True{}: yes
    case False{}: no

def float_bits(bits: U32) -> F32:
  match bits:
    case U32{word}: F32{word}

def raw(value: F32) -> U32:
  match value:
    case F32{word}: U32{word}

def wide(value: F32) -> F.F64:
  F.widen_float_bits(raw(value))

def finite(+value: F32) -> Bool:
  U32.is_ne(U32.and(raw(value), 2139095040), 2139095040)

# Binary32 addition/multiplication via exact binary64 word arithmetic and one
# narrowing. A product of two finite F32 significands has at most 48 bits. For
# addition, relevant half-ULP cases are exact in F64; discarded tiny addends
# cannot move an F32 endpoint across its rounding interval.
def add(a: F32, b: F32) -> F32:
  F.to_f32(F.add(wide(a), wide(b)))

def mul(a: F32, b: F32) -> F32:
  F.to_f32(F.mul(wide(a), wide(b)))

# The measured bytecode converts double -> float before float * 0.15f.
def delta(value: F.F64) -> F32:
  mul(F.to_f32(value), float_bits(1041865114))

# Exact finite F32 remainder by 360. Integer modular doubling is bounded by
# the F32 exponent (at most 104 steps); fractional divisors fit U32 (<=360<<15).
def double_remainder(fuel: Nat, value: U32) -> U32:
  match fuel:
    case 0n: value
    case 1n+rest: double_remainder(rest, U32.mod(U32.shl(value), 360))

def fractional_remainder(+mantissa: U32, +shift: U32) -> U32:
  +remainder = U32.mod(mantissa, U32.shln(360, U32.to_nat(shift)))
  raw(F.to_f32(F.mul(F.from_u32(remainder), F.F64{U32.shln(U32.sub(1023, shift), 20n), 0})))

def large_remainder(+mantissa: U32, exponent: U32, integral: Bool) -> U32:
  match integral:
    case True{}: raw(F.to_f32(F.from_u32(double_remainder(U32.to_nat(U32.sub(exponent, 150)), U32.mod(mantissa, 360)))))
    case False{}: fractional_remainder(mantissa, U32.sub(150, exponent))

def remainder_large(+bits: U32) -> U32:
  +exponent = U32.and(U32.shrn(bits, 23n), 255)
  U32.or(U32.and(bits, 2147483648), large_remainder(U32.or(U32.and(bits, 8388607), 8388608), exponent, U32.is_ge(exponent, 150)))

def remainder_word(+bits: U32, large: Bool) -> U32:
  match large:
    case False{}: bits
    case True{}: remainder_large(bits)

def remainder360(+value: F32) -> F32:
  float_bits(remainder_word(raw(value), U32.is_ge(U32.and(raw(value), 2147483647), 1135869952)))

def clamp_pitch(+value: F32) -> F32:
  +wide = wide(value)
  choose(F32, float_bits(3266576384), choose(F32, float_bits(1119092736), value, F.is_gt(wide, F.from_u32(90))), F.is_lt(wide, F.neg(F.from_u32(90))))

# Entity setters reject a nonfinite candidate, retaining the old current field.
# setXRot first performs remainder360 then Math.clamp; past pitch has no remainder.
def set_yaw(old: F32, candidate: F32, valid: Bool) -> F32:
  match valid:
    case True{}: candidate
    case False{}: old

def set_pitch(old: F32, candidate: F32, valid: Bool) -> F32:
  match valid:
    case True{}: clamp_pitch(remainder360(candidate))
    case False{}: old

def turn_deltas(state: State, +dx: F32, +dy: F32) -> State:
  match state:
    case State{+yaw, +pitch, old_yaw, old_pitch}:
      +new_pitch = add(pitch, dy)
      +new_yaw = add(yaw, dx)
      State{set_yaw(yaw, new_yaw, finite(new_yaw)), clamp_pitch(set_pitch(pitch, new_pitch, finite(new_pitch))), add(old_yaw, dx), clamp_pitch(add(old_pitch, dy))}

# Diagnostic implementation step. Checked callers use turn; raw IEEE outcomes
# including nonfinite previous yaw are compared to Java by the native harness.
def turn_raw(state: State, dx: F.F64, dy: F.F64) -> State:
  turn_deltas(state, delta(dx), delta(dy))

def state_fields(finite_value: Bool, field: U32, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match finite_value:
    case False{}: Some{InvalidState{field}}
    case True{}: rest

def state_error(state: State) -> Maybe<&2, Error>:
  match state:
    case State{yaw, pitch, old_yaw, old_pitch}:
      state_fields(finite(yaw), 0, state_fields(finite(pitch), 1, state_fields(finite(old_yaw), 2, state_fields(finite(old_pitch), 3, None{}))))

def input_error(dx: F.F64, dy: F.F64) -> Maybe<&2, Error>:
  choose(Maybe<&2, Error>, choose(Maybe<&2, Error>, None{}, Some{InvalidInput{1}}, F.is_finite(dy)), Some{InvalidInput{0}}, F.is_finite(dx))

def first_error(first: Maybe<&2, Error>, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match first:
    case Some{error}: Some{error}
    case None{}: rest

def result_error(result: State) -> Maybe<&2, Error>:
  match result:
    case State{yaw, pitch, old_yaw, old_pitch}:
      choose(Maybe<&2, Error>,
        choose(Maybe<&2, Error>,
          choose(Maybe<&2, Error>, choose(Maybe<&2, Error>, None{}, Some{NonFiniteResult{3}}, finite(old_pitch)), Some{NonFiniteResult{2}}, finite(old_yaw)),
          Some{NonFiniteResult{1}}, finite(pitch)), Some{NonFiniteResult{0}}, finite(yaw))

def result_checked(result: State, error: Maybe<&2, Error>) -> Result<&2, &2, Error, State>:
  match error:
    case Some{error}: Fail{error}
    case None{}: Done{result}

def turned(+state: State, dx: F.F64, dy: F.F64) -> Result<&2, &2, Error, State>:
  +result = turn_raw(state, dx, dy)
  result_checked(result, result_error(result))

def turn_gate(state: State, dx: F.F64, dy: F.F64, error: Maybe<&2, Error>) -> Result<&2, &2, Error, State>:
  match error:
    case Some{error}: Fail{error}
    case None{}: turned(state, dx, dy)

def turn(+state: State, +dx: F.F64, +dy: F.F64) -> Result<&2, &2, Error, State>:
  turn_gate(state, dx, dy, first_error(state_error(state), input_error(dx, dy)))
