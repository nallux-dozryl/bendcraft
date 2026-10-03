import Base
import ./big_uint.bend as B

# Fixed public budgets: 4096 codepoints, 1024 mantissa digits. Exponent magnitude
# saturates at 100000 after each digit, but the complete grammar is validated.
type Decimal is Data:
  Decimal{stage: U32, negative: Bool, coefficient: B.BigUInt, digits: U32, significant: U32, fraction: U32, exp_negative: Bool, exponent: U32}

type Bounds is Data:
  Bounds{low: U32, high: U32}

def choose(-A: Data, yes: A, no: A, test: Bool) -> A:
  match test:
    case True{}: yes
    case False{}: no

def float_word(value: U32) -> F32:
  match value:
    case U32{word}: F32{word}

def signed_word(negative: Bool, value: U32) -> F32:
  float_word(U32.or(value, choose(U32, 2147483648, 0, negative)))

# Boundary between positive finite payload k and k+1, including the upper
# rounding boundary of maximum finite. It is exactly mantissa * 2^power.
def midpoint_compare_scaled(+numerator: B.BigUInt, +denominator: B.BigUInt, +mantissa: U32, +exponent: U32, normal_power: Bool) -> Cmp:
  match normal_power:
    case True{}: B.compare(numerator, B.shl(B.mul_add(denominator, mantissa, 0), U32.sub(exponent, 151)))
    case False{}: B.compare(B.shl(numerator, U32.sub(151, exponent)), B.mul_add(denominator, mantissa, 0))

def midpoint_normal(numerator: B.BigUInt, denominator: B.BigUInt, +word: U32) -> Cmp:
  +exponent = U32.shrn(word, 23n)
  midpoint_compare_scaled(numerator, denominator, U32.inc(U32.shl(U32.or(U32.and(word, 8388607), 8388608))), exponent, U32.is_ge(exponent, 151))

def midpoint_compare(numerator: B.BigUInt, denominator: B.BigUInt, +word: U32, subnormal: Bool) -> Cmp:
  match subnormal:
    case True{}: B.compare(B.shl(numerator, 150), B.mul_add(denominator, U32.inc(U32.shl(word)), 0))
    case False{}: midpoint_normal(numerator, denominator, word)

def midpoint_order(numerator: B.BigUInt, denominator: B.BigUInt, +word: U32) -> Cmp:
  midpoint_compare(numerator, denominator, word, U32.is_lt(word, 8388608))

def search_side(low: U32, high: U32, +middle: U32, lower: Bool) -> Bounds:
  match lower:
    case True{}: Bounds{low, middle}
    case False{}: Bounds{U32.inc(middle), high}

def search_order(low: U32, high: U32, +middle: U32, order: Cmp) -> Bounds:
  match order:
    case LT{}: search_side(low, high, middle, True{})
    case GT{}: search_side(low, high, middle, False{})
    case EQ{}: search_side(low, high, middle, U32.is_eq(U32.and(middle, 1), 0))

def search_middle(numerator: B.BigUInt, denominator: B.BigUInt, low: U32, high: U32, +middle: U32) -> Bounds:
  search_order(low, high, middle, midpoint_order(numerator, denominator, middle))

def search_step(numerator: B.BigUInt, denominator: B.BigUInt, +low: U32, +high: U32, active: Bool) -> Bounds:
  match active:
    case False{}: Bounds{low, high}
    case True{}: search_middle(numerator, denominator, low, high, U32.shr(U32.add(low, high)))

# Binary search over all nonnegative finite payloads and positive infinity.
# At most 31 comparisons; equality at a midpoint selects the even payload.
def search(fuel: Nat, +numerator: B.BigUInt, +denominator: B.BigUInt, bounds: Bounds) -> Bounds:
  match fuel bounds:
    case 0n _: bounds
    case 1n+rest Bounds{+low, +high}:
      search(rest, numerator, denominator, search_step(numerator, denominator, low, high, U32.is_lt(low, high)))

def search_finish(negative: Bool, bounds: Bounds, complete: Bool) -> Result<&2, &2, String, F32>:
  match bounds complete:
    case Bounds{low, high} True{}: Done{signed_word(negative, low)}
    case _ False{}: Fail{"RoundingBudget"}

def rounded(negative: Bool, bounds: Bounds) -> Result<&2, &2, String, F32>:
  match bounds:
    case Bounds{+low, +high}: search_finish(negative, Bounds{low, high}, U32.is_eq(low, high))

def rational(negative: Bool, coefficient: B.BigUInt, +power: U32, positive: Bool) -> Result<&2, &2, String, F32>:
  match positive:
    case True{}: rounded(negative, search(31n, B.times_ten(U32.to_nat(U32.sub(power, 200000)), coefficient), B.one(), Bounds{0, 2139095040}))
    case False{}: rounded(negative, search(31n, coefficient, B.times_ten(U32.to_nat(U32.sub(200000, power)), B.one()), Bounds{0, 2139095040}))

def decimal_range(negative: Bool, coefficient: B.BigUInt, +power: U32, adjusted: U32, underflow: Bool) -> Result<&2, &2, String, F32>:
  match underflow:
    case True{}: Done{signed_word(negative, 0)}
    case False{}: rational(negative, coefficient, power, U32.is_ge(power, 200000))

def decimal_overflow(negative: Bool, coefficient: B.BigUInt, power: U32, +adjusted: U32, overflow: Bool) -> Result<&2, &2, String, F32>:
  match overflow:
    case True{}: Done{signed_word(negative, 2139095040)}
    case False{}: decimal_range(negative, coefficient, power, adjusted, U32.is_lt(adjusted, 199954))

def decimal_power(negative: Bool, coefficient: B.BigUInt, +significant: U32, +power: U32) -> Result<&2, &2, String, F32>:
  +adjusted = U32.sub(U32.add(power, significant), 1)
  decimal_overflow(negative, coefficient, power, adjusted, U32.is_gt(adjusted, 200038))

def decimal_exponent(negative: Bool, coefficient: B.BigUInt, significant: U32, fraction: U32, exponent: U32, exp_negative: Bool) -> Result<&2, &2, String, F32>:
  match exp_negative:
    case True{}: decimal_power(negative, coefficient, significant, U32.sub(U32.sub(200000, exponent), fraction))
    case False{}: decimal_power(negative, coefficient, significant, U32.sub(U32.add(200000, exponent), fraction))

def decimal_zero(negative: Bool, coefficient: B.BigUInt, significant: U32, fraction: U32, exp_negative: Bool, exponent: U32, zero: Bool) -> Result<&2, &2, String, F32>:
  match zero:
    case True{}: Done{signed_word(negative, 0)}
    case False{}: decimal_exponent(negative, coefficient, significant, fraction, exponent, exp_negative)

def decimal_finish(value: Decimal, valid: Bool) -> Result<&2, &2, String, F32>:
  match value valid:
    case _ False{}: Fail{"InvalidDecimal"}
    case Decimal{stage, negative, coefficient, digits, +significant, fraction, exp_negative, exponent} True{}:
      decimal_zero(negative, coefficient, significant, fraction, exp_negative, exponent, U32.is_eq(significant, 0))

def accepting(+stage: U32) -> Bool:
  U32.is_eq(stage, 2) || U32.is_eq(stage, 3) || U32.is_eq(stage, 5) || U32.is_eq(stage, 8)

def finish(value: Decimal) -> Result<&2, &2, String, F32>:
  match value:
    case Decimal{+stage, negative, coefficient, digits, significant, fraction, exp_negative, exponent}:
      decimal_finish(Decimal{stage, negative, coefficient, digits, significant, fraction, exp_negative, exponent}, accepting(stage))

def digit(+code: U32) -> Bool:
  U32.is_ge(code, 48) && U32.is_le(code, 57)

def digit_stage(next: U32, code: U32, valid: Bool) -> Result<&2, &2, String, U32>:
  match valid:
    case True{}: Done{next}
    case False{}: Fail{"InvalidDecimal"}

def first_digit(+code: U32) -> Result<&2, &2, String, U32>:
  digit_stage(choose(U32, 2, 3, U32.is_eq(code, 48)), code, digit(code))

# Stages: 0 start, 1 minus, 2 integer zero, 3 integer, 4 dot, 5 fraction,
# 6 exponent marker, 7 exponent sign, 8 exponent digits.
def next_stage(stage: U32, +code: U32) -> Result<&2, &2, String, U32>:
  match stage:
    case 0:
      match code:
        case 45: Done{1}
        case _: first_digit(code)
    case 1: first_digit(code)
    case 2:
      match code:
        case 46: Done{4}
        case 101: Done{6}
        case 69: Done{6}
        case _: Fail{"InvalidDecimal"}
    case 3:
      match code:
        case 46: Done{4}
        case 101: Done{6}
        case 69: Done{6}
        case _: digit_stage(3, code, digit(code))
    case 4: digit_stage(5, code, digit(code))
    case 5:
      match code:
        case 101: Done{6}
        case 69: Done{6}
        case _: digit_stage(5, code, digit(code))
    case 6:
      match code:
        case 43: Done{7}
        case 45: Done{7}
        case _: digit_stage(8, code, digit(code))
    case 7: digit_stage(8, code, digit(code))
    case _: digit_stage(8, code, digit(code))

def mantissa_digit(value: Decimal, +next: U32, +code: U32, allowed: Bool) -> Result<&2, &2, String, Decimal>:
  match value allowed:
    case _ False{}: Fail{"DigitLimit"}
    case Decimal{stage, negative, coefficient, digits, +significant, fraction, exp_negative, exponent} True{}:
      Done{Decimal{next, negative, B.mul_add(coefficient, 10, U32.sub(code, 48)), U32.inc(digits), U32.add(significant, Bool.to_u32(U32.is_ne(significant, 0) || U32.is_ne(code, 48))), U32.add(fraction, Bool.to_u32(U32.is_eq(next, 5))), exp_negative, exponent}}

def exponent_digit(value: Decimal, next: U32, code: U32) -> Result<&2, &2, String, Decimal>:
  match value:
    case Decimal{stage, negative, coefficient, digits, significant, fraction, exp_negative, exponent}:
      +expanded = U32.add(U32.mul(exponent, 10), U32.sub(code, 48))
      Done{Decimal{next, negative, coefficient, digits, significant, fraction, exp_negative, choose(U32, 100000, expanded, U32.is_gt(expanded, 100000))}}

def nondigit(value: Decimal, +next: U32, +code: U32) -> Result<&2, &2, String, Decimal>:
  match value:
    case Decimal{stage, negative, coefficient, digits, significant, fraction, exp_negative, exponent}:
      Done{Decimal{next, U32.is_eq(next, 1) || negative, coefficient, digits, significant, fraction, U32.is_eq(next, 7) && U32.is_eq(code, 45) || exp_negative, exponent}}

def digit_kind(value: Decimal, +next: U32, code: U32, exponent: Bool) -> Result<&2, &2, String, Decimal>:
  match value exponent:
    case _ True{}: exponent_digit(value, next, code)
    case Decimal{stage, negative, coefficient, +digits, significant, fraction, exp_negative, exponent} False{}:
      mantissa_digit(Decimal{stage, negative, coefficient, digits, significant, fraction, exp_negative, exponent}, next, code, U32.is_lt(digits, 1024))

def update(value: Decimal, +next: U32, +code: U32, is_digit: Bool) -> Result<&2, &2, String, Decimal>:
  match is_digit:
    case False{}: nondigit(value, next, code)
    case True{}: digit_kind(value, next, code, U32.is_eq(next, 8))

def step(value: Decimal, +code: U32) -> Result<&2, &2, String, Decimal>:
  match value:
    case Decimal{+stage, negative, coefficient, digits, significant, fraction, exp_negative, exponent}:
      do Result<&2, &2, String, Decimal>:
        next : U32 <- next_stage(stage, code)
        update(Decimal{stage, negative, coefficient, digits, significant, fraction, exp_negative, exponent}, next, code, digit(code))

def scan(text: String, value: Decimal) -> Result<&2, &2, String, F32>:
  match text:
    case SNil{}: finish(value)
    case SCon{character, rest}:
      do Result<&2, &2, String, F32>:
        next : Decimal <- step(value, Char.to_u32(character))
        scan(rest, next)

def within(fuel: Nat, text: String) -> Bool:
  match fuel text:
    case _ SNil{}: True{}
    case 0n SCon{character, rest}: False{}
    case 1n+remaining SCon{character, rest}: within(remaining, rest)

def parse_budget(text: String, allowed: Bool) -> Result<&2, &2, String, F32>:
  match allowed:
    case False{}: Fail{"InputLimit"}
    case True{}: scan(text, Decimal{0, False{}, B.zero(), 0, 0, 0, False{}, 0})

# Strict JSON number token, with no surrounding whitespace/coercion grammar.
def parse_f32(+text: String) -> Result<&2, &2, String, F32>:
  parse_budget(text, within(4096n, text))
