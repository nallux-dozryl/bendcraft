import Base
import ./f64.bend as F

# Raw long bit patterns, high word first. State words use the same layout.
type Bits64 is Data:
  Bits64{hi: U32, lo: U32}

type Source is Data:
  Legacy{seed: Bits64}
  Xoroshiro{low: Bits64, high: Bits64}

type Positional is Data:
  LegacyPositional{seed: Bits64}
  XoroshiroPositional{low: Bits64, high: Bits64}

type RandomError is Data:
  InvalidBound{}
  RejectionFuelExhausted{}
  UnsupportedHash{}

def bits_add(a: Bits64, b: Bits64) -> Bits64:
  match a b:
    case Bits64{ah, +al} Bits64{bh, +bl}:
      +lo = U32.add(al, bl)
      Bits64{U32.add(U32.add(ah, bh), Bool.to_u32(U32.is_lt(lo, al))), lo}

def bits_xor(a: Bits64, b: Bits64) -> Bits64:
  match a b:
    case Bits64{ah, al} Bits64{bh, bl}: Bits64{U32.xor(ah, bh), U32.xor(al, bl)}

def bits_zero(value: Bits64) -> Bool:
  match value:
    case Bits64{hi, lo}: U32.is_zero(U32.or(hi, lo))

def bits_shl(value: Bits64, +amount: Nat) -> Bits64:
  match value:
    case Bits64{hi, +lo}: Bits64{U32.or(U32.shln(hi, amount), U32.shrn(lo, Nat.sub(32n, amount))), U32.shln(lo, amount)}

def bits_shr(value: Bits64, +amount: Nat) -> Bits64:
  match value:
    case Bits64{+hi, lo}: Bits64{U32.shrn(hi, amount), U32.or(U32.shrn(lo, amount), U32.shln(hi, Nat.sub(32n, amount)))}

def bits_rot(value: Bits64, +amount: Nat) -> Bits64:
  match value:
    case Bits64{+hi, +lo}: Bits64{U32.or(U32.shln(hi, amount), U32.shrn(lo, Nat.sub(32n, amount))), U32.or(U32.shln(lo, amount), U32.shrn(hi, Nat.sub(32n, amount)))}

def bits_rot49(value: Bits64) -> Bits64:
  match value:
    case Bits64{hi, lo}: bits_rot(Bits64{lo, hi}, 17n)

# Exact unsigned 32x32 product using 16-bit limbs: intermediates fit U32.
def product32_finish(a1: U32, b1: U32, first: U32, carry: U32, +cross: U32) -> Bits64:
  Bits64{U32.add(U32.add(U32.mul(a1, b1), carry), U32.shrn(cross, 16n)), U32.or(U32.shln(cross, 16n), U32.and(first, 65535))}

def product32_cross(+a0: U32, a1: U32, +b0: U32, +b1: U32, +first: U32, +cross: U32) -> Bits64:
  product32_finish(a1, b1, first, U32.shrn(cross, 16n), U32.add(U32.mul(a0, b1), U32.and(cross, 65535)))

def product32_parts(+a0: U32, +a1: U32, +b0: U32, b1: U32, +first: U32) -> Bits64:
  product32_cross(a0, a1, b0, b1, first, U32.add(U32.mul(a1, b0), U32.shrn(first, 16n)))

def product32(+a: U32, +b: U32) -> Bits64:
  product32_parts(U32.and(a, 65535), U32.shrn(a, 16n), U32.and(b, 65535), U32.shrn(b, 16n), U32.mul(U32.and(a, 65535), U32.and(b, 65535)))

def bits_mul_finish(cross: U32, product: Bits64) -> Bits64:
  match product:
    case Bits64{hi, lo}: Bits64{U32.add(hi, cross), lo}

def bits_mul(a: Bits64, b: Bits64) -> Bits64:
  match a b:
    case Bits64{ah, +al} Bits64{bh, +bl}: bits_mul_finish(U32.add(U32.mul(ah, bl), U32.mul(al, bh)), product32(al, bl))

def sign_extend(+word: U32) -> Bits64:
  Bits64{U32.sub(0, U32.shrn(word, 31n)), word}

def bits_sar16(value: Bits64) -> Bits64:
  match value:
    case Bits64{+hi, lo}: Bits64{U32.or(U32.shrn(hi, 16n), U32.shln(U32.sub(0, U32.shrn(hi, 31n)), 16n)), U32.or(U32.shrn(lo, 16n), U32.shln(hi, 16n))}

def mask48(value: Bits64) -> Bits64:
  match value:
    case Bits64{hi, lo}: Bits64{U32.and(hi, 65535), lo}

def seeded_legacy(seed: Bits64) -> Source:
  Legacy{mask48(bits_xor(seed, Bits64{5, 3740067437}))}

def mix_stafford_finish(+value: Bits64) -> Bits64:
  bits_xor(value, bits_shr(value, 31n))

def mix_stafford_middle(+value: Bits64) -> Bits64:
  mix_stafford_finish(bits_mul(bits_xor(value, bits_shr(value, 27n)), Bits64{2496678331, 321982955}))

def mix_stafford(+value: Bits64) -> Bits64:
  mix_stafford_middle(bits_mul(bits_xor(value, bits_shr(value, 30n)), Bits64{3210233709, 484763065}))

def xoro_guard(low: Bits64, high: Bits64, zero: Bool) -> Source:
  match zero:
    case True{}: Xoroshiro{Bits64{2654435769, 2135587861}, Bits64{1779033703, 4089235721}}
    case False{}: Xoroshiro{low, high}

def raw_xoroshiro(+low: Bits64, +high: Bits64) -> Source:
  xoro_guard(low, high, bits_zero(low) && bits_zero(high))

def seed_xoro_unmixed(+low: Bits64) -> Source:
  raw_xoroshiro(mix_stafford(low), mix_stafford(bits_add(low, Bits64{2654435769, 2135587861})))

def seeded_xoroshiro(seed: Bits64) -> Source:
  seed_xoro_unmixed(bits_xor(seed, Bits64{1779033703, 4089235721}))

def reseed(source: Source, seed: Bits64) -> Source:
  match source:
    case Legacy{old}: seeded_legacy(seed)
    case Xoroshiro{low, high}: seeded_xoroshiro(seed)

def legacy_step(seed: Bits64) -> Bits64:
  mask48(bits_add(bits_mul(seed, Bits64{5, 3740067437}), Bits64{0, 11}))

def legacy_bits_output(+seed: Bits64, +count: Nat) -> Source & U32:
  match seed:
    case Bits64{+hi, +lo}:
      (Legacy{Bits64{hi, lo}}, U32.or(U32.shln(hi, Nat.sub(count, 16n)), U32.shrn(lo, Nat.sub(48n, count))))

# Internal count is one of 1,24,26,27,31,32; handle the <=16 path separately.
def legacy_bits_small(+seed: Bits64, count: Nat) -> Source & U32:
  match seed:
    case Bits64{+hi, lo}: (Legacy{Bits64{hi, lo}}, U32.shrn(hi, Nat.sub(16n, count)))

def legacy_bits_select(seed: Bits64, count: Nat, small: Bool) -> Source & U32:
  match small:
    case True{}: legacy_bits_small(seed, count)
    case False{}: legacy_bits_output(seed, count)

def legacy_bits(seed: Bits64, +count: Nat) -> Source & U32:
  legacy_bits_select(legacy_step(seed), count, Nat.is_le(count, 16n))

def xoro_output(+low: Bits64, +high: Bits64, +mixed: Bits64) -> Source & Bits64:
  (Xoroshiro{bits_xor(bits_xor(bits_rot49(low), mixed), bits_shl(mixed, 21n)), bits_rot(mixed, 28n)}, bits_add(bits_rot(bits_add(low, high), 17n), low))

def xoro_step(+low: Bits64, +high: Bits64) -> Source & Bits64:
  xoro_output(low, high, bits_xor(high, low))

def long_low(result: Source & Bits64) -> Source & U32:
  match result:
    case (source, Bits64{hi, lo}): (source, lo)

def next_int(source: Source) -> Source & U32:
  match source:
    case Legacy{seed}: legacy_bits(seed, 32n)
    case Xoroshiro{low, high}: long_low(xoro_step(low, high))

def legacy_long_second(first: U32, result: Source & U32) -> Source & Bits64:
  match result:
    case (source, +second): (source, Bits64{U32.sub(first, U32.shrn(second, 31n)), second})

def legacy_long_first(result: Source & U32) -> Source & Bits64:
  match result:
    case (Legacy{seed}, first): legacy_long_second(first, legacy_bits(seed, 32n))
    case (Xoroshiro{low, high}, first): (Xoroshiro{low, high}, Bits64{first, 0})

def next_long(source: Source) -> Source & Bits64:
  match source:
    case Legacy{seed}: legacy_long_first(legacy_bits(seed, 32n))
    case Xoroshiro{low, high}: xoro_step(low, high)

def bool_int(result: Source & U32) -> Source & Bool:
  match result:
    case (source, word): (source, U32.is_ne(U32.and(word, 1), 0))

def next_boolean(source: Source) -> Source & Bool:
  match source:
    case Legacy{seed}: bool_int(legacy_bits(seed, 1n))
    case Xoroshiro{low, high}: bool_int(long_low(xoro_step(low, high)))

def float_word(value: U32) -> F32:
  match value:
    case U32{word}: F32{word}

def float_normalize(fuel: Nat, +word: U32, exponent: U32, ready: Bool) -> F32:
  match fuel ready:
    case 0n _: float_word(U32.or(U32.shln(exponent, 23n), U32.and(word, 8388607)))
    case 1n+rest True{}: float_word(U32.or(U32.shln(exponent, 23n), U32.and(word, 8388607)))
    case 1n+rest False{}:
      +shifted = U32.shl(word)
      float_normalize(rest, shifted, U32.sub(exponent, 1), U32.is_ge(shifted, 8388608))

def fraction24(+word: U32, zero: Bool) -> F32:
  match zero:
    case True{}: float_word(0)
    case False{}: float_normalize(24n, word, 126, U32.is_ge(word, 8388608))

def float_result(result: Source & U32) -> Source & F32:
  match result:
    case (source, +word): (source, fraction24(word, U32.is_zero(word)))

def xoro_float(result: Source & Bits64) -> Source & F32:
  match result:
    case (source, Bits64{hi, lo}): float_result((source, U32.shrn(hi, 8n)))

def next_float(source: Source) -> Source & F32:
  match source:
    case Legacy{seed}: float_result(legacy_bits(seed, 24n))
    case Xoroshiro{low, high}: xoro_float(xoro_step(low, high))

def double_pack(exponent: U32, word: Bits64) -> F.F64:
  match word:
    case Bits64{hi, lo}: F.F64{U32.or(U32.shln(exponent, 20n), U32.and(hi, 1048575)), lo}

def double_ready(word: Bits64) -> Bool:
  match word:
    case Bits64{hi, lo}: U32.is_ge(hi, 1048576)

def double_normalize(fuel: Nat, +word: Bits64, exponent: U32, ready: Bool) -> F.F64:
  match fuel ready:
    case 0n _: double_pack(exponent, word)
    case 1n+rest True{}: double_pack(exponent, word)
    case 1n+rest False{}:
      +shifted = bits_shl(word, 1n)
      double_normalize(rest, shifted, U32.sub(exponent, 1), double_ready(shifted))

def fraction53(+word: Bits64, zero: Bool) -> F.F64:
  match zero:
    case True{}: F.F64{0, 0}
    case False{}: double_normalize(53n, word, 1022, double_ready(word))

def double_result(result: Source & Bits64) -> Source & F.F64:
  match result:
    case (source, +word): (source, fraction53(word, bits_zero(word)))

def legacy_double_second(first: U32, result: Source & U32) -> Source & F.F64:
  match result:
    case (source, second): double_result((source, bits_add(bits_shl(Bits64{0, first}, 27n), Bits64{0, second})))

def legacy_double_first(result: Source & U32) -> Source & F.F64:
  match result:
    case (Legacy{seed}, first): legacy_double_second(first, legacy_bits(seed, 27n))
    case (Xoroshiro{low, high}, first): (Xoroshiro{low, high}, F.F64{0, 0})

def xoro_double(result: Source & Bits64) -> Source & F.F64:
  match result:
    case (source, word): double_result((source, bits_shr(word, 11n)))

def next_double(source: Source) -> Source & F.F64:
  match source:
    case Legacy{seed}: legacy_double_first(legacy_bits(seed, 26n))
    case Xoroshiro{low, high}: xoro_double(xoro_step(low, high))

# Every candidate consumes one draw; successful state advancement equals Java.
# Failure restores the caller's original state, including exhaustion.
type Candidate is Data:
  Candidate{source: Source, value: U32, accepted: Bool}

def legacy_power_result(source: Source, product: Bits64) -> Candidate:
  match product:
    case Bits64{hi, lo}: Candidate{source, U32.or(U32.shl(hi), U32.shrn(lo, 31n)), True{}}

def legacy_reject(source: Source, +bits: U32, +bound: U32, +value: U32) -> Candidate:
  Candidate{source, value, U32.is_lt(U32.add(U32.sub(bits, value), U32.sub(bound, 1)), 2147483648)}

def legacy_candidate_power(source: Source, +bits: U32, +bound: U32, power: Bool) -> Candidate:
  match power:
    case True{}: legacy_power_result(source, product32(bits, bound))
    case False{}: legacy_reject(source, bits, bound, U32.mod(bits, bound))

def legacy_candidate(+bound: U32, result: Source & U32) -> Candidate:
  match result:
    case (source, bits): legacy_candidate_power(source, bits, bound, U32.is_zero(U32.and(bound, U32.sub(bound, 1))))

def xoro_candidate_product(source: Source, +bound: U32, product: Bits64) -> Candidate:
  match product:
    case Bits64{hi, +lo}: Candidate{source, hi, Bool.not(U32.is_lt(lo, bound) && U32.is_lt(lo, U32.mod(U32.sub(0, bound), bound)))}

def xoro_candidate(+bound: U32, result: Source & U32) -> Candidate:
  match result:
    case (source, bits): xoro_candidate_product(source, bound, product32(bits, bound))

def bounded_candidate(source: Source, bound: U32) -> Candidate:
  match source:
    case Legacy{seed}: legacy_candidate(bound, legacy_bits(seed, 31n))
    case Xoroshiro{low, high}: xoro_candidate(bound, long_low(xoro_step(low, high)))

# A structurally decreasing fuel loop; no probability-based termination claim.
def bounded_loop(fuel: Nat, +source: Source, +bound: U32, candidate: Maybe<&2, Candidate>) -> Result<&2, &1, RandomError, Source & U32>:
  match fuel candidate:
    case _ Some{Candidate{ready, value, True{}}}: Done{(ready, value)}
    case 0n _: Fail{RejectionFuelExhausted{}}
    case 1n+rest None{}: bounded_loop(rest, source, bound, Some{bounded_candidate(source, bound)})
    case 1n+rest Some{Candidate{+retry, value, False{}}}: bounded_loop(rest, retry, bound, Some{bounded_candidate(retry, bound)})

def bounded_commit(original: Source, result: Result<&2, &1, RandomError, Source & U32>) -> Source & Result<&2, &2, RandomError, U32>:
  match result:
    case Done{(source, value)}: (source, Done{value})
    case Fail{error}: (original, Fail{error})

def bounded_guard(fuel: Nat, +source: Source, bound: U32, valid: Bool) -> Source & Result<&2, &2, RandomError, U32>:
  match valid:
    case False{}: (source, Fail{InvalidBound{}})
    case True{}: bounded_commit(source, bounded_loop(fuel, source, bound, None{}))

def next_bounded(fuel: Nat, source: Source, +bound: U32) -> Source & Result<&2, &2, RandomError, U32>:
  bounded_guard(fuel, source, bound, U32.is_ge(bound, 1) && U32.is_le(bound, 2147483647))

def fork_legacy(result: Source & Bits64) -> Source & Source:
  match result:
    case (source, seed): (source, seeded_legacy(seed))

def fork_xoro_second(low: Bits64, result: Source & Bits64) -> Source & Source:
  match result:
    case (source, high): (source, raw_xoroshiro(low, high))

def fork_xoro_first(result: Source & Bits64) -> Source & Source:
  match result:
    case (source, low): fork_xoro_second(low, next_long(source))

def fork(source: Source) -> Source & Source:
  match source:
    case Legacy{seed}: fork_legacy(next_long(Legacy{seed}))
    case Xoroshiro{low, high}: fork_xoro_first(xoro_step(low, high))

def positional_legacy(result: Source & Bits64) -> Source & Positional:
  match result:
    case (source, seed): (source, LegacyPositional{seed})

def positional_xoro_second(low: Bits64, result: Source & Bits64) -> Source & Positional:
  match result:
    case (source, high): (source, XoroshiroPositional{low, high})

def positional_xoro_first(result: Source & Bits64) -> Source & Positional:
  match result:
    case (source, low): positional_xoro_second(low, next_long(source))

def fork_positional(source: Source) -> Source & Positional:
  match source:
    case Legacy{seed}: positional_legacy(next_long(Legacy{seed}))
    case Xoroshiro{low, high}: positional_xoro_first(xoro_step(low, high))

def position_mix(+value: Bits64) -> Bits64:
  bits_sar16(bits_add(bits_mul(bits_mul(value, value), Bits64{0, 42317861}), bits_mul(value, Bits64{0, 11})))

def position_seed(x: U32, y: U32, z: U32) -> Bits64:
  position_mix(bits_xor(bits_xor(sign_extend(U32.mul(x, 3129871)), bits_mul(sign_extend(z), Bits64{0, 116129781})), sign_extend(y)))

def at(factory: Positional, x: U32, y: U32, z: U32) -> Source:
  match factory:
    case LegacyPositional{seed}: seeded_legacy(bits_xor(position_seed(x, y, z), seed))
    case XoroshiroPositional{low, high}: raw_xoroshiro(bits_xor(position_seed(x, y, z), low), high)

def from_seed(factory: Positional, +seed: Bits64) -> Source:
  match factory:
    case LegacyPositional{old}: seeded_legacy(seed)
    case XoroshiroPositional{low, high}: raw_xoroshiro(bits_xor(seed, low), bits_xor(seed, high))

# Java hashCode counts UTF-16 code units, including supplementary characters.
def hash_unit(hash: U32, unit: U32) -> U32:
  U32.add(U32.mul(hash, 31), unit)

def hash_char(hash: U32, +code: U32, supplementary: Bool) -> U32:
  match supplementary:
    case False{}: hash_unit(hash, code)
    case True{}:
      +rest = U32.sub(code, 65536)
      hash_unit(hash_unit(hash, U32.add(55296, U32.shrn(rest, 10n))), U32.add(56320, U32.and(rest, 1023)))

def java_hash_loop(text: String, hash: U32) -> U32:
  match text:
    case SNil{}: hash
    case SCon{head, tail}:
      +code = Char.to_u32(head)
      java_hash_loop(tail, hash_char(hash, code, U32.is_ge(code, 65536)))

def java_string_hash(text: String) -> U32:
  java_hash_loop(text, 0)

def from_hash_of(factory: Positional, text: String) -> Result<&2, &2, RandomError, Source>:
  match factory:
    case LegacyPositional{seed}: Done{seeded_legacy(bits_xor(sign_extend(java_string_hash(text)), seed))}
    case XoroshiroPositional{low, high}: Fail{UnsupportedHash{}}

def consume_loop(fuel: Nat, source: Source) -> Source:
  match fuel:
    case 0n: source
    case 1n+rest: consume_loop(rest, Pair.fst(Source, U32, next_int(source)))

def consume_count(source: Source, +count: U32) -> Source:
  consume_loop(U32.to_nat(U32.mul(count, Bool.to_u32(U32.is_lt(count, 2147483648)))), source)

# Laws are about the actual transactional boundary and advancement functions.
law invalid_bound_rollback:
  for fuel: Nat
  for +source: Source
  for bound: U32
  {bounded_guard(fuel, source, bound, False{}) == (source, Fail{InvalidBound{}}) : Source & Result<&2, &2, RandomError, U32>}

def invalid_bound_rollback(fuel, source, bound):
  {==}

law exhaustion_rollback:
  for +source: Source
  for bound: U32
  {bounded_guard(0n, source, bound, True{}) == (source, Fail{RejectionFuelExhausted{}}) : Source & Result<&2, &2, RandomError, U32>}

def exhaustion_rollback(source, bound):
  {==}

law failed_draw_rollback:
  for +source: Source
  for +error: RandomError
  {bounded_commit(source, Fail{error}) == (source, Fail{error}) : Source & Result<&2, &2, RandomError, U32>}

def failed_draw_rollback(source, error):
  {==}

law zero_bound_rollback:
  for fuel: Nat
  for +source: Source
  {next_bounded(fuel, source, 0) == (source, Fail{InvalidBound{}}) : Source & Result<&2, &2, RandomError, U32>}

def zero_bound_rollback(fuel, source):
  {==}

law consume_zero_identity:
  for +source: Source
  {consume_loop(0n, source) == source : Source}

def consume_zero_identity(source):
  {==}

law consume_successor_advances:
  for rest: Nat
  for +source: Source
  {consume_loop(1n+rest, source) == consume_loop(rest, Pair.fst(Source, U32, next_int(source))) : Source}

def consume_successor_advances(rest, source):
  {==}

law consumption_composes:
  for +a: Nat
  for +b: Nat
  for +source: Source
  {consume_loop(Nat.add(a, b), source) == consume_loop(b, consume_loop(a, source)) : Source}

def consumption_composes(a, b, source):
  match a:
    case 0n: {==}
    case 1n+rest: consumption_composes(rest, b, Pair.fst(Source, U32, next_int(source)))
