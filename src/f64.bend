import Base

# IEEE-754 binary64 payload, high word first. No F32 conversion is involved.
type F64 is Data:
  F64{hi: U32, lo: U32}

type F64Class is Data:
  F64Zero{}
  F64Subnormal{}
  F64Normal{}
  F64Infinity{}
  F64NaN{}

type F64Order is Data:
  F64Less{}
  F64Equal{}
  F64Greater{}
  F64Unordered{}

# Internal unsigned 64-bit pair; every operation explicitly handles the carry.
type Wide is Data:
  Wide{hi: U32, lo: U32}

type Parts is Data:
  Parts{negative: Bool, exponent: U32, significand: Wide}

def from_bits(hi: U32, lo: U32) -> F64:
  F64{hi, lo}

def bits(value: F64) -> U32 & U32:
  match value:
    case F64{hi, lo}: (hi, lo)

def sign(value: F64) -> Bool:
  match value:
    case F64{hi, lo}: U32.is_ne(U32.and(hi, 2147483648), 0)

def neg(value: F64) -> F64:
  match value:
    case F64{hi, lo}: F64{U32.xor(hi, 2147483648), lo}

def abs(value: F64) -> F64:
  match value:
    case F64{hi, lo}: F64{U32.and(hi, 2147483647), lo}

def classify_fields(exponent: U32, fraction: Bool) -> F64Class:
  match exponent fraction:
    case 0 False{}: F64Zero{}
    case 0 True{}: F64Subnormal{}
    case 2047 False{}: F64Infinity{}
    case 2047 True{}: F64NaN{}
    case _ _: F64Normal{}

def classify(value: F64) -> F64Class:
  match value:
    case F64{+hi, lo}:
      classify_fields(U32.and(U32.shrn(hi, 20n), 2047), U32.is_ne(U32.or(U32.and(hi, 1048575), lo), 0))

def class_is_nan(kind: F64Class) -> Bool:
  match kind:
    case F64NaN{}: True{}
    case _: False{}

def is_nan(value: F64) -> Bool:
  class_is_nan(classify(value))

def class_is_zero(kind: F64Class) -> Bool:
  match kind:
    case F64Zero{}: True{}
    case _: False{}

def is_zero(value: F64) -> Bool:
  class_is_zero(classify(value))

def class_is_finite(kind: F64Class) -> Bool:
  match kind:
    case F64Infinity{}: False{}
    case F64NaN{}: False{}
    case _: True{}

def is_finite(value: F64) -> Bool:
  class_is_finite(classify(value))

def quiet_nan(value: F64) -> F64:
  match value:
    case F64{hi, lo}: F64{U32.or(hi, 524288), lo}

def canonical_nan() -> F64:
  F64{2146959360, 0}

def sign_mask(negative: Bool) -> U32:
  U32.shln(Bool.to_u32(negative), 31n)

def infinity(negative: Bool) -> F64:
  F64{U32.or(sign_mask(negative), 2146435072), 0}

def wide_add(a: Wide, b: Wide) -> Wide:
  match a b:
    case Wide{ah, +al} Wide{bh, bl}:
      +low = U32.add(al, bl)
      Wide{U32.add(U32.add(ah, bh), Bool.to_u32(U32.is_lt(low, al))), low}

def wide_sub(a: Wide, b: Wide) -> Wide:
  match a b:
    case Wide{ah, +al} Wide{bh, +bl}:
      Wide{U32.sub(U32.sub(ah, bh), Bool.to_u32(U32.is_lt(al, bl))), U32.sub(al, bl)}

def wide_increment(value: Wide) -> Wide:
  wide_add(value, Wide{0, 1})

def wide_shl(value: Wide) -> Wide:
  match value:
    case Wide{hi, +lo}:
      Wide{U32.or(U32.shl(hi), U32.shrn(lo, 31n)), U32.shl(lo)}

def wide_shr(value: Wide) -> Wide:
  match value:
    case Wide{+hi, lo}:
      Wide{U32.shr(hi), U32.or(U32.shr(lo), U32.shln(hi, 31n))}

def wide_shr_three(value: Wide) -> Wide:
  match value:
    case Wide{+hi, lo}:
      Wide{U32.shrn(hi, 3n), U32.or(U32.shrn(lo, 3n), U32.shln(hi, 29n))}

def wide_shr_jam(value: Wide) -> Wide:
  match value:
    case Wide{+hi, +lo}:
      Wide{U32.shr(hi), U32.or(U32.or(U32.shr(lo), U32.shln(hi, 31n)), U32.and(lo, 1))}

def wide_is_zero(value: Wide) -> Bool:
  match value:
    case Wide{hi, lo}: U32.is_eq(U32.or(hi, lo), 0)

def wide_cmp_hi(al: U32, bl: U32, high: Cmp) -> Cmp:
  match high:
    case EQ{}: U32.cmp(al, bl)
    case LT{}: LT{}
    case GT{}: GT{}

def wide_cmp(a: Wide, b: Wide) -> Cmp:
  match a b:
    case Wide{ah, al} Wide{bh, bl}:
      wide_cmp_hi(al, bl, U32.cmp(ah, bh))

def shift_jam_small(+amount: U32, value: Wide) -> Wide:
  match value:
    case Wide{+hi, +lo}:
      +right = U32.to_nat(amount)
      +left = U32.to_nat(U32.sub(32, amount))
      Wide{U32.shrn(hi, right), U32.or(U32.or(U32.shrn(lo, right), U32.shln(hi, left)), Bool.to_u32(U32.is_ne(U32.shln(lo, left), 0)))}

def shift_jam_middle(+amount: U32, value: Wide) -> Wide:
  match value:
    case Wide{+hi, lo}:
      Wide{0, U32.or(U32.shrn(hi, U32.to_nat(U32.sub(amount, 32))), Bool.to_u32(U32.is_ne(U32.or(U32.shln(hi, U32.to_nat(U32.sub(64, amount))), lo), 0)))}

def shift_jam_bounded(+amount: U32, value: Wide, small: Bool) -> Wide:
  match small:
    case True{}: shift_jam_small(amount, value)
    case False{}: shift_jam_middle(amount, value)

def shift_jam_gate(+amount: U32, +value: Wide, large: Bool) -> Wide:
  match large:
    case False{}: shift_jam_bounded(amount, value, U32.is_lt(amount, 32))
    case True{}: Wide{0, Bool.to_u32(Bool.not(wide_is_zero(value)))}

# Exact word shifts plus a sticky predicate handle any exponent gap in O(1).
def shift_jam(+amount: U32, value: Wide) -> Wide:
  shift_jam_gate(amount, value, U32.is_ge(amount, 64))

def magnitude(value: F64) -> Wide:
  match value:
    case F64{hi, lo}: Wide{U32.and(hi, 2147483647), lo}

def ordered_result(order: Cmp, negative: Bool) -> F64Order:
  match order negative:
    case EQ{} _: F64Equal{}
    case LT{} False{}: F64Less{}
    case LT{} True{}: F64Greater{}
    case GT{} False{}: F64Greater{}
    case GT{} True{}: F64Less{}

def compare_signed(+a: F64, +b: F64, a_negative: Bool, different: Bool) -> F64Order:
  match a_negative different:
    case True{} True{}: F64Less{}
    case False{} True{}: F64Greater{}
    case _ False{}: ordered_result(wide_cmp(magnitude(a), magnitude(b)), a_negative)

def compare_zero(+a: F64, +b: F64, both_zero: Bool) -> F64Order:
  match both_zero:
    case True{}: F64Equal{}
    case False{}: compare_signed(a, b, sign(a), Bool.xor(sign(a), sign(b)))

def compare_classes(+a: F64, +b: F64, a_class: F64Class, b_class: F64Class) -> F64Order:
  match a_class b_class:
    case F64NaN{} _: F64Unordered{}
    case _ F64NaN{}: F64Unordered{}
    case _ _: compare_zero(a, b, is_zero(a) && is_zero(b))

def compare(+a: F64, +b: F64) -> F64Order:
  compare_classes(a, b, classify(a), classify(b))

def order_equal(order: F64Order) -> Bool:
  match order:
    case F64Equal{}: True{}
    case _: False{}

def order_less(order: F64Order) -> Bool:
  match order:
    case F64Less{}: True{}
    case _: False{}

def order_le(order: F64Order) -> Bool:
  match order:
    case F64Less{}: True{}
    case F64Equal{}: True{}
    case _: False{}

def is_eq(a: F64, b: F64) -> Bool:
  order_equal(compare(a, b))

def is_ne(a: F64, b: F64) -> Bool:
  Bool.not(is_eq(a, b))

def is_lt(a: F64, b: F64) -> Bool:
  order_less(compare(a, b))

def is_le(a: F64, b: F64) -> Bool:
  order_le(compare(a, b))

def is_gt(a: F64, b: F64) -> Bool:
  is_lt(b, a)

def is_ge(a: F64, b: F64) -> Bool:
  is_le(b, a)

def unpack_exponent(negative: Bool, exponent: U32, fraction: Wide, subnormal: Bool) -> Parts:
  match fraction subnormal:
    case Wide{hi, lo} True{}:
      Parts{negative, 1, Wide{hi, lo}}
    case Wide{hi, lo} False{}:
      Parts{negative, exponent, Wide{U32.or(hi, 1048576), lo}}

def unpack(value: F64) -> Parts:
  match value:
    case F64{+hi, lo}:
      +exponent = U32.and(U32.shrn(hi, 20n), 2047)
      unpack_exponent(U32.is_ne(U32.and(hi, 2147483648), 0), exponent, Wide{U32.and(hi, 1048575), lo}, U32.is_eq(exponent, 0))

def extend_significand(value: Wide) -> Wide:
  match value:
    case Wide{hi, +lo}:
      Wide{U32.or(U32.shln(hi, 3n), U32.shrn(lo, 29n)), U32.shln(lo, 3n)}

def pack_finite(negative: Bool, exponent: U32, rounded: Wide) -> F64:
  match rounded:
    case Wide{+hi, lo}:
      F64{U32.or(U32.or(sign_mask(negative), U32.shln(U32.mul(exponent, Bool.to_u32(U32.is_ge(hi, 1048576))), 20n)), U32.and(hi, 1048575)), lo}

def pack_overflow(negative: Bool, exponent: U32, rounded: Wide, overflow: Bool) -> F64:
  match overflow:
    case True{}: infinity(negative)
    case False{}: pack_finite(negative, exponent, rounded)

def pack_ready(negative: Bool, +exponent: U32, rounded: Wide, carry: Bool) -> F64:
  match carry:
    case False{}: pack_overflow(negative, exponent, rounded, U32.is_ge(exponent, 2047))
    case True{}:
      +next_exponent = U32.inc(exponent)
      pack_overflow(negative, next_exponent, wide_shr(rounded), U32.is_ge(next_exponent, 2047))

def pack_rounded(negative: Bool, exponent: U32, rounded: Wide) -> F64:
  match rounded:
    case Wide{+hi, lo}:
      pack_ready(negative, exponent, Wide{hi, lo}, U32.is_ge(hi, 2097152))

def round_decide(negative: Bool, exponent: U32, retained: Wide, increment: Bool) -> F64:
  match increment:
    case True{}: pack_rounded(negative, exponent, wide_increment(retained))
    case False{}: pack_rounded(negative, exponent, retained)

def round_retained(negative: Bool, exponent: U32, +extra: U32, retained: Wide) -> F64:
  match retained:
    case Wide{hi, +lo}:
      round_decide(negative, exponent, Wide{hi, lo}, U32.is_gt(extra, 4) || (U32.is_eq(extra, 4) && U32.is_ne(U32.and(lo, 1), 0)))

def round_pack(negative: Bool, exponent: U32, extended: Wide) -> F64:
  match extended:
    case Wide{hi, +lo}:
      round_retained(negative, exponent, U32.and(lo, 7), wide_shr_three(Wide{hi, lo}))

# Finite subtraction needs at most 53 left shifts. Match on real structural
# fuel and on its bit predicates, never on a fabricated termination token.
def normalize_left_loop(fuel: Nat, negative: Bool, +exponent: U32, extended: Wide, needs_shift: Bool) -> F64:
  match fuel extended needs_shift:
    case 0n _ _: round_pack(negative, exponent, extended)
    case 1n+rest _ False{}: round_pack(negative, exponent, extended)
    case 1n+rest Wide{hi, +lo} True{}:
      +next_exponent = U32.sub(exponent, 1)
      +next_high = U32.or(U32.shl(hi), U32.shrn(lo, 31n))
      normalize_left_loop(rest, negative, next_exponent, Wide{next_high, U32.shl(lo)}, U32.is_gt(next_exponent, 1) && U32.is_lt(next_high, 8388608))

def normalize_left(negative: Bool, +exponent: U32, extended: Wide) -> F64:
  match extended:
    case Wide{+hi, lo}:
      normalize_left_loop(53n, negative, exponent, Wide{hi, lo}, U32.is_gt(exponent, 1) && U32.is_lt(hi, 8388608))

def normalize_sum(negative: Bool, +exponent: U32, extended: Wide, carry: Bool) -> F64:
  match carry:
    case False{}: round_pack(negative, exponent, extended)
    case True{}: round_pack(negative, U32.inc(exponent), wide_shr_jam(extended))

def sum_extended(negative: Bool, exponent: U32, extended: Wide) -> F64:
  match extended:
    case Wide{+hi, lo}:
      normalize_sum(negative, exponent, Wide{hi, lo}, U32.is_ge(hi, 16777216))

def finite_aligned(negative: Bool, exponent: U32, large: Wide, small: Wide, different: Bool) -> F64:
  match different:
    case False{}: sum_extended(negative, exponent, wide_add(large, small))
    case True{}: normalize_left(negative, exponent, wide_sub(large, small))

def finite_parts(a: Parts, b: Parts) -> F64:
  match a b:
    case Parts{+negative_a, +exponent_a, significand_a} Parts{negative_b, exponent_b, significand_b}:
      finite_aligned(negative_a, exponent_a, extend_significand(significand_a), shift_jam(U32.sub(exponent_a, exponent_b), extend_significand(significand_b)), Bool.xor(negative_a, negative_b))

def finite_ordered(+a: F64, +b: F64, order: Cmp) -> F64:
  match order:
    case EQ{}: finite_parts(unpack(a), unpack(b))
    case GT{}: finite_parts(unpack(a), unpack(b))
    case LT{}: finite_parts(unpack(b), unpack(a))

def finite_zero(+a: F64, +b: F64, equal_opposites: Bool) -> F64:
  match equal_opposites:
    case True{}: F64{0, 0}
    case False{}: finite_ordered(a, b, wide_cmp(magnitude(a), magnitude(b)))

def finite_add(+a: F64, +b: F64) -> F64:
  finite_zero(a, b, Bool.xor(sign(a), sign(b)) && Cmp.is_eq(wide_cmp(magnitude(a), magnitude(b))))

def infinity_pair(a: F64, b: F64, same_sign: Bool) -> F64:
  match same_sign:
    case True{}: a
    case False{}: canonical_nan()

def non_nan_add(+a: F64, +b: F64, a_class: F64Class, b_class: F64Class) -> F64:
  match a_class b_class:
    case F64Infinity{} F64Infinity{}: infinity_pair(a, b, Bool.not(Bool.xor(sign(a), sign(b))))
    case F64Infinity{} _: a
    case _ F64Infinity{}: b
    case _ _: finite_add(a, b)

def operation_effective(a: F64, b: F64, a_class: F64Class, b_class: F64Class, subtract: Bool) -> F64:
  match subtract:
    case False{}: non_nan_add(a, b, a_class, b_class)
    case True{}: non_nan_add(a, neg(b), a_class, b_class)

def operation_classes(a: F64, b: F64, subtract: Bool, a_class: F64Class, b_class: F64Class) -> F64:
  match a_class b_class:
    case F64NaN{} _: quiet_nan(a)
    case _ F64NaN{}: quiet_nan(b)
    case _ _: operation_effective(a, b, a_class, b_class, subtract)

def add(+a: F64, +b: F64) -> F64:
  operation_classes(a, b, False{}, classify(a), classify(b))

def sub(+a: F64, +b: F64) -> F64:
  operation_classes(a, b, True{}, classify(a), classify(b))

# A 128-bit product accumulator for two at-most-53-bit significands.
type Quad is Data:
  Quad{w3: U32, w2: U32, w1: U32, w0: U32}

def quad_join(high: Wide, low: Wide) -> Quad:
  match high low:
    case Wide{w3, w2} Wide{w1, w0}: Quad{w3, w2, w1, w0}

def quad_add_low(ah: Wide, bh: Wide, +al: Wide, bl: Wide) -> Quad:
  +low = wide_add(al, bl)
  quad_join(wide_add(wide_add(ah, bh), Wide{0, Bool.to_u32(Cmp.is_lt(wide_cmp(low, al)))}), low)

def quad_add(a: Quad, b: Quad) -> Quad:
  match a b:
    case Quad{a3, a2, a1, a0} Quad{b3, b2, b1, b0}:
      quad_add_low(Wide{a3, a2}, Wide{b3, b2}, Wide{a1, a0}, Wide{b1, b0})

def quad_shl(value: Quad) -> Quad:
  match value:
    case Quad{w3, +w2, +w1, +w0}:
      Quad{U32.or(U32.shl(w3), U32.shrn(w2, 31n)), U32.or(U32.shl(w2), U32.shrn(w1, 31n)), U32.or(U32.shl(w1), U32.shrn(w0, 31n)), U32.shl(w0)}

def quad_accumulate(value: Quad, accumulator: Quad, odd: Bool) -> Quad:
  match odd:
    case False{}: accumulator
    case True{}: quad_add(accumulator, value)

def multiply_significands_loop(fuel: Nat, +multiplicand: Quad, multiplier: Wide, accumulator: Quad) -> Quad:
  match fuel multiplier:
    case 0n _: accumulator
    case 1n+rest Wide{hi, +lo}:
      multiply_significands_loop(rest, quad_shl(multiplicand), wide_shr(Wide{hi, lo}), quad_accumulate(multiplicand, accumulator, U32.is_ne(U32.and(lo, 1), 0)))

def multiply_significands(a: Wide, b: Wide) -> Quad:
  match a:
    case Wide{hi, lo}:
      multiply_significands_loop(53n, Quad{0, 0, hi, lo}, b, Quad{0, 0, 0, 0})

def normalize_factor_loop(fuel: Nat, negative: Bool, exponent: U32, significand: Wide, needs_shift: Bool) -> Parts:
  match fuel significand needs_shift:
    case 0n _ _: Parts{negative, exponent, significand}
    case 1n+rest _ False{}: Parts{negative, exponent, significand}
    case 1n+rest Wide{hi, +lo} True{}:
      +next_high = U32.or(U32.shl(hi), U32.shrn(lo, 31n))
      normalize_factor_loop(rest, negative, U32.sub(exponent, 1), Wide{next_high, U32.shl(lo)}, U32.is_lt(next_high, 1048576))

# Shifted exponent = ordinary biased exponent + 2048, so subnormal
# normalization never uses wrapping unsigned arithmetic for a negative exponent.
def normalize_factor(parts: Parts) -> Parts:
  match parts:
    case Parts{negative, exponent, Wide{+hi, lo}}:
      normalize_factor_loop(52n, negative, U32.add(exponent, 2048), Wide{hi, lo}, U32.is_lt(hi, 1048576))

def product_shift(+amount: U32, product: Quad) -> Wide:
  match product:
    case Quad{w3, +w2, +w1, w0}:
      +right = U32.to_nat(U32.sub(amount, 32))
      +left = U32.to_nat(U32.sub(64, amount))
      Wide{U32.or(U32.shln(w3, left), U32.shrn(w2, right)), U32.or(U32.or(U32.shln(w2, left), U32.shrn(w1, right)), Bool.to_u32(U32.is_ne(U32.or(U32.shln(w1, left), w0), 0)))}

def product_underflow(negative: Bool, +shifted_exponent: U32, extended: Wide, underflow: Bool) -> F64:
  match underflow:
    case True{}:
      round_pack(negative, 1, shift_jam(U32.sub(2049, shifted_exponent), extended))
    case False{}:
      round_pack(negative, U32.sub(shifted_exponent, 2048), extended)

def product_normalized(negative: Bool, +shifted_exponent: U32, extended: Wide) -> F64:
  product_underflow(negative, shifted_exponent, extended, U32.is_le(shifted_exponent, 2048))

def product_high(negative: Bool, shifted_exponent: U32, product: Quad, carry: Bool) -> F64:
  match carry:
    case False{}: product_normalized(negative, shifted_exponent, product_shift(49, product))
    case True{}: product_normalized(negative, U32.inc(shifted_exponent), product_shift(50, product))

def product_ready(negative: Bool, shifted_exponent: U32, product: Quad) -> F64:
  match product:
    case Quad{+w3, w2, w1, w0}:
      product_high(negative, shifted_exponent, Quad{w3, w2, w1, w0}, U32.is_ge(w3, 512))

def multiply_parts(a: Parts, b: Parts) -> F64:
  match a b:
    case Parts{negative_a, exponent_a, significand_a} Parts{negative_b, exponent_b, significand_b}:
      product_ready(Bool.xor(negative_a, negative_b), U32.sub(U32.add(exponent_a, exponent_b), 3071), multiply_significands(significand_a, significand_b))

def multiply_finite(a: F64, b: F64) -> F64:
  multiply_parts(normalize_factor(unpack(a)), normalize_factor(unpack(b)))

def multiply_classes(+a: F64, +b: F64, a_class: F64Class, b_class: F64Class) -> F64:
  match a_class b_class:
    case F64NaN{} _: quiet_nan(a)
    case _ F64NaN{}: quiet_nan(b)
    case F64Infinity{} F64Zero{}: canonical_nan()
    case F64Zero{} F64Infinity{}: canonical_nan()
    case F64Infinity{} _: infinity(Bool.xor(sign(a), sign(b)))
    case _ F64Infinity{}: infinity(Bool.xor(sign(a), sign(b)))
    case F64Zero{} _: F64{sign_mask(Bool.xor(sign(a), sign(b))), 0}
    case _ F64Zero{}: F64{sign_mask(Bool.xor(sign(a), sign(b))), 0}
    case _ _: multiply_finite(a, b)

def mul(+a: F64, +b: F64) -> F64:
  multiply_classes(a, b, classify(a), classify(b))

# Restoring binary division: one integer bit and 55 fraction bits. The
# remainder stays below twice the normalized 53-bit denominator.
def quotient_step(remainder: Wide, denominator: Wide, subtract: Bool) -> Wide:
  match subtract:
    case False{}: remainder
    case True{}: wide_sub(remainder, denominator)

def quotient_bit(quotient: Wide, bit: Bool) -> Wide:
  match quotient:
    case Wide{hi, +lo}:
      Wide{U32.or(U32.shl(hi), U32.shrn(lo, 31n)), U32.or(U32.shl(lo), Bool.to_u32(bit))}

def quotient_jam(quotient: Wide, remainder: Wide) -> Wide:
  match quotient:
    case Wide{hi, lo}:
      Wide{hi, U32.or(lo, Bool.to_u32(Bool.not(wide_is_zero(remainder))))}

def divide_significands_loop(fuel: Nat, +remainder: Wide, +denominator: Wide, quotient: Wide) -> Wide:
  match fuel:
    case 0n: quotient_jam(quotient, remainder)
    case 1n+rest:
      +subtract = Bool.not(Cmp.is_lt(wide_cmp(remainder, denominator)))
      divide_significands_loop(rest, wide_shl(quotient_step(remainder, denominator, subtract)), denominator, quotient_bit(quotient, subtract))

def divide_normalized(negative: Bool, shifted_exponent: U32, numerator: Wide, denominator: Wide, smaller: Bool) -> F64:
  match smaller:
    case False{}:
      product_normalized(negative, shifted_exponent, divide_significands_loop(56n, numerator, denominator, Wide{0, 0}))
    case True{}:
      product_normalized(negative, U32.sub(shifted_exponent, 1), divide_significands_loop(56n, wide_shl(numerator), denominator, Wide{0, 0}))

def divide_parts(a: Parts, b: Parts) -> F64:
  match a b:
    case Parts{negative_a, exponent_a, +numerator} Parts{negative_b, exponent_b, +denominator}:
      divide_normalized(Bool.xor(negative_a, negative_b), U32.sub(U32.add(exponent_a, 3071), exponent_b), numerator, denominator, Cmp.is_lt(wide_cmp(numerator, denominator)))

def divide_finite(a: F64, b: F64) -> F64:
  divide_parts(normalize_factor(unpack(a)), normalize_factor(unpack(b)))

def divide_classes(+a: F64, +b: F64, a_class: F64Class, b_class: F64Class) -> F64:
  match a_class b_class:
    case F64NaN{} _: quiet_nan(a)
    case _ F64NaN{}: quiet_nan(b)
    case F64Infinity{} F64Infinity{}: canonical_nan()
    case F64Zero{} F64Zero{}: canonical_nan()
    case F64Infinity{} _: infinity(Bool.xor(sign(a), sign(b)))
    case _ F64Zero{}: infinity(Bool.xor(sign(a), sign(b)))
    case _ F64Infinity{}: F64{sign_mask(Bool.xor(sign(a), sign(b))), 0}
    case F64Zero{} _: F64{sign_mask(Bool.xor(sign(a), sign(b))), 0}
    case _ _: divide_finite(a, b)

def div(+a: F64, +b: F64) -> F64:
  divide_classes(a, b, classify(a), classify(b))

# Integer input words are converted exactly without a floating intermediary.
def from_word_zero(negative: Bool, magnitude: U32, zero: Bool) -> F64:
  match zero:
    case True{}: F64{0, 0}
    case False{}: normalize_left(negative, 1075, extend_significand(Wide{0, magnitude}))

def from_u32(+value: U32) -> F64:
  from_word_zero(False{}, value, U32.is_zero(value))

def from_i32_sign(+value: U32, negative: Bool) -> F64:
  match negative:
    case False{}: from_u32(value)
    case True{}: from_word_zero(True{}, U32.sub(0, value), False{})

def from_i32(+value: U32) -> F64:
  from_i32_sign(value, U32.is_ne(U32.and(value, 2147483648), 0))

# Float NaNs keep their sign and 23-bit payload shifted into the double
# fraction, with the binary64 quiet bit set. Finite widening is exact.
def widen_float_fields(negative: Bool, exponent: U32, +fraction: U32) -> F64:
  match exponent:
    case 0:
      normalize_left(negative, 926, extend_significand(Wide{0, fraction}))
    case 255:
      F64{U32.or(U32.or(sign_mask(negative), 2146435072), U32.or(U32.shrn(fraction, 3n), U32.mul(524288, Bool.to_u32(U32.is_ne(fraction, 0))))), U32.shln(fraction, 29n)}
    case _:
      F64{U32.or(U32.or(sign_mask(negative), U32.shln(U32.add(exponent, 896), 20n)), U32.shrn(fraction, 3n)), U32.shln(fraction, 29n)}

def widen_float_subnormal(negative: Bool, +fraction: U32, zero: Bool) -> F64:
  match zero:
    case True{}: F64{sign_mask(negative), 0}
    case False{}: normalize_left(negative, 926, extend_significand(Wide{0, fraction}))

def widen_float(negative: Bool, exponent: U32, +fraction: U32) -> F64:
  match exponent:
    case 0: widen_float_subnormal(negative, fraction, U32.is_zero(fraction))
    case _: widen_float_fields(negative, exponent, fraction)

def widen_float_bits(+value: U32) -> F64:
  widen_float(U32.is_ne(U32.and(value, 2147483648), 0), U32.and(U32.shrn(value, 23n), 255), U32.and(value, 8388607))

def from_f32(value: F32) -> F64:
  widen_float_bits(F32.bits(value))

type F64ConversionError is Data:
  F64NaNConversion{}
  F64OutOfI32Range{}

def shift_right_small(+amount: U32, value: Wide) -> Wide:
  match value:
    case Wide{+hi, lo}:
      +right = U32.to_nat(amount)
      Wide{U32.shrn(hi, right), U32.or(U32.shrn(lo, right), U32.shln(hi, U32.to_nat(U32.sub(32, amount))))}

def shift_right_middle(amount: U32, value: Wide) -> Wide:
  match value:
    case Wide{hi, lo}: Wide{0, U32.shrn(hi, U32.to_nat(U32.sub(amount, 32)))}

def shift_right_bounded(amount: U32, value: Wide, small: Bool) -> Wide:
  match small:
    case True{}: shift_right_small(amount, value)
    case False{}: shift_right_middle(amount, value)

def shift_right_gate(+amount: U32, value: Wide, large: Bool) -> Wide:
  match large:
    case True{}: Wide{0, 0}
    case False{}: shift_right_bounded(amount, value, U32.is_lt(amount, 32))

def shift_right(+amount: U32, value: Wide) -> Wide:
  shift_right_gate(amount, value, U32.is_ge(amount, 64))

def discarded_small(amount: U32, value: Wide) -> Bool:
  match value:
    case Wide{hi, lo}: U32.is_ne(U32.shln(lo, U32.to_nat(U32.sub(32, amount))), 0)

def discarded_middle(amount: U32, value: Wide) -> Bool:
  match value:
    case Wide{hi, lo}: U32.is_ne(U32.or(U32.shln(hi, U32.to_nat(U32.sub(64, amount))), lo), 0)

def discarded_bounded(amount: U32, value: Wide, small: Bool) -> Bool:
  match small:
    case True{}: discarded_small(amount, value)
    case False{}: discarded_middle(amount, value)

def discarded_gate(+amount: U32, value: Wide, large: Bool) -> Bool:
  match large:
    case True{}: Bool.not(wide_is_zero(value))
    case False{}: discarded_bounded(amount, value, U32.is_lt(amount, 32))

def discarded(+amount: U32, value: Wide) -> Bool:
  discarded_gate(amount, value, U32.is_ge(amount, 64))

def encode_i32(negative: Bool, magnitude: U32) -> U32:
  match negative:
    case True{}: U32.sub(0, magnitude)
    case False{}: magnitude

def convert_i32_range(+negative: Bool, magnitude: U32, fraction: Bool, floor: Bool, valid: Bool) -> Result<&2, &2, F64ConversionError, U32>:
  match valid:
    case False{}: Fail{F64OutOfI32Range{}}
    case True{}: Done{encode_i32(negative, U32.add(magnitude, Bool.to_u32(negative && floor && fraction)))}

def convert_i32_sign(negative: Bool, +magnitude: U32, +fraction: Bool, +floor: Bool) -> Result<&2, &2, F64ConversionError, U32>:
  match negative:
    case False{}: convert_i32_range(False{}, magnitude, fraction, floor, U32.is_le(magnitude, 2147483647))
    case True{}: convert_i32_range(True{}, magnitude, fraction, floor, U32.is_le(magnitude, 2147483648) && Bool.not(U32.is_eq(magnitude, 2147483648) && floor && fraction))

def convert_i32_integer(negative: Bool, fraction: Bool, floor: Bool, integer: Wide) -> Result<&2, &2, F64ConversionError, U32>:
  match integer:
    case Wide{hi, lo}: convert_i32_sign(negative, lo, fraction, floor)

def convert_i32_exponent(negative: Bool, +exponent: U32, +significand: Wide, floor: Bool, too_large: Bool) -> Result<&2, &2, F64ConversionError, U32>:
  match too_large:
    case True{}: Fail{F64OutOfI32Range{}}
    case False{}:
      +amount = U32.sub(1075, exponent)
      convert_i32_integer(negative, discarded(amount, significand), floor, shift_right(amount, significand))

def convert_i32_parts(parts: Parts, floor: Bool) -> Result<&2, &2, F64ConversionError, U32>:
  match parts:
    case Parts{negative, +exponent, significand}:
      convert_i32_exponent(negative, exponent, significand, floor, U32.is_gt(exponent, 1054))

def convert_i32_class(+value: F64, floor: Bool, kind: F64Class) -> Result<&2, &2, F64ConversionError, U32>:
  match kind:
    case F64NaN{}: Fail{F64NaNConversion{}}
    case F64Infinity{}: Fail{F64OutOfI32Range{}}
    case _: convert_i32_parts(unpack(value), floor)

def trunc_i32(+value: F64) -> Result<&2, &2, F64ConversionError, U32>:
  convert_i32_class(value, False{}, classify(value))

def floor_i32(+value: F64) -> Result<&2, &2, F64ConversionError, U32>:
  convert_i32_class(value, True{}, classify(value))

# Exact narrowing. Normal/subnormal paths retain 24 significant bits plus
# guard/round/sticky information and round only once, including underflow.
def narrow_float_word(value: U32) -> F32:
  match value:
    case U32{word}: F32{word}

def narrow_float_round(negative: Bool, offset: U32, extended: Wide) -> F32:
  match extended:
    case Wide{hi, +lo}:
      +rounding = U32.and(lo, 7)
      rounded = U32.add(U32.shrn(lo, 3n), Bool.to_u32(U32.is_gt(rounding, 4) || (U32.is_eq(rounding, 4) && U32.is_ne(U32.and(lo, 8), 0))))
      narrow_float_word(U32.or(sign_mask(negative), U32.add(offset, rounded)))

def narrow_float_exponent(negative: Bool, +exponent: U32, significand: Wide, normal: Bool) -> F32:
  match normal:
    case True{}: narrow_float_round(negative, U32.shln(U32.sub(exponent, 897), 23n), shift_jam(26, significand))
    case False{}: narrow_float_round(negative, 0, shift_jam(U32.sub(923, exponent), significand))

def narrow_float_range(negative: Bool, +exponent: U32, significand: Wide, overflow: Bool) -> F32:
  match overflow:
    case True{}: narrow_float_word(U32.or(sign_mask(negative), 2139095040))
    case False{}: narrow_float_exponent(negative, exponent, significand, U32.is_ge(exponent, 897))

def narrow_float_parts(parts: Parts) -> F32:
  match parts:
    case Parts{negative, +exponent, significand}: narrow_float_range(negative, exponent, significand, U32.is_gt(exponent, 1150))

def narrow_float_nan(value: F64) -> F32:
  match value:
    case F64{+hi, lo}:
      narrow_float_word(U32.or(U32.or(U32.and(hi, 2147483648), 2143289344), U32.or(U32.shln(U32.and(hi, 1048575), 3n), U32.shrn(lo, 29n))))

def narrow_float_class(+value: F64, kind: F64Class) -> F32:
  match kind:
    case F64NaN{}: narrow_float_nan(value)
    case F64Infinity{}: narrow_float_word(U32.or(sign_mask(sign(value)), 2139095040))
    case _: narrow_float_parts(unpack(value))

def to_f32(+value: F64) -> F32:
  narrow_float_class(value, classify(value))
