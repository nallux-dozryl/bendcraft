import Base

# FIPS 180-4 SHA-256 words, in output order. No host cryptography is called.
type Digest is Data:
  Digest{a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32}

# Internal state has one owned 64-word schedule. Public digest constructs this
# state; helpers/raw construction do not independently validate its invariants.
type State is Type:
  State{hash: Digest, schedule: Array<U32>, position: U32, partial: U32, length_hi: U32, length_lo: U32}

type Compression is Type:
  Compression{schedule: Array<U32>, words: Digest}

def native_limit() -> Nat:
  Nat.add(Nat.mul(65535n, Nat.mul(65536n, 65536n)), 4294967295n)

# Three divisions test limit < 2^48 without constructing 2^48 or expanding an
# enormous unary Nat during proof reduction. Each divisor is representable.
def valid_limit(limit: Nat) -> Bool:
  Nat.is_eq(Nat.div(Nat.div(Nat.div(limit, 65536n), 65536n), 65536n), 0n)

def initial() -> Digest:
  Digest{1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635, 1541459225}

def constants() -> List<&2, U32>:
  [1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221,
   3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580,
   3835390401, 4022224774, 264347078, 604807628, 770255983, 1249150122, 1555081692, 1996064986,
   2554220882, 2821834349, 2952996808, 3210313671, 3336571891, 3584528711, 113926993, 338241895,
   666307205, 773529912, 1294757372, 1396182291, 1695183700, 1986661051, 2177026350, 2456956037,
   2730485921, 2820302411, 3259730800, 3345764771, 3516065817, 3600352804, 4094571909, 275423344,
   430227734, 506948616, 659060556, 883997877, 958139571, 1322822218, 1537002063, 1747873779,
   1955562222, 2024104815, 2227730452, 2361852424, 2428436474, 2756734187, 3204031479, 3329325298]

def rotate_right(+value: U32, amount: Nat) -> U32:
  +shift = Nat.mod(amount, 32n)
  U32.or(U32.shrn(value, shift), U32.shln(value, Nat.sub(32n, shift)))

def choose(+x: U32, y: U32, z: U32) -> U32:
  U32.xor(U32.and(x, y), U32.and(U32.not(x), z))

def majority(+x: U32, +y: U32, +z: U32) -> U32:
  U32.xor(U32.xor(U32.and(x, y), U32.and(x, z)), U32.and(y, z))

def sigma0(+x: U32) -> U32:
  U32.xor(U32.xor(rotate_right(x, 2n), rotate_right(x, 13n)), rotate_right(x, 22n))

def sigma1(+x: U32) -> U32:
  U32.xor(U32.xor(rotate_right(x, 6n), rotate_right(x, 11n)), rotate_right(x, 25n))

def small0(+x: U32) -> U32:
  U32.xor(U32.xor(rotate_right(x, 7n), rotate_right(x, 18n)), U32.shrn(x, 3n))

def small1(+x: U32) -> U32:
  U32.xor(U32.xor(rotate_right(x, 17n), rotate_right(x, 19n)), U32.shrn(x, 10n))

def extend_read_d(index: U32, a: U32, b: U32, c: U32, read: Array<U32> & U32) -> Array<U32>:
  (schedule, d) = read
  Array.set(U32, schedule, index, U32.add(U32.add(U32.add(small1(a), b), small0(c)), d))

def extend_read_c(+index: U32, a: U32, b: U32, read: Array<U32> & U32) -> Array<U32>:
  (schedule, c) = read
  extend_read_d(index, a, b, c, Array.get(U32, schedule, U32.sub(index, 16)))

def extend_read_b(+index: U32, a: U32, read: Array<U32> & U32) -> Array<U32>:
  (schedule, b) = read
  extend_read_c(index, a, b, Array.get(U32, schedule, U32.sub(index, 15)))

def extend_read_a(+index: U32, read: Array<U32> & U32) -> Array<U32>:
  (schedule, a) = read
  extend_read_b(index, a, Array.get(U32, schedule, U32.sub(index, 7)))

def extended_word(+index: U32, schedule: Array<U32>) -> Array<U32>:
  extend_read_a(index, Array.get(U32, schedule, U32.sub(index, 2)))

def extend_schedule(fuel: Nat, +index: U32, schedule: Array<U32>) -> Array<U32>:
  match fuel:
    case 0n: schedule
    case 1n+rest:
      extend_schedule(rest, U32.inc(index), extended_word(index, schedule))

def round_words(a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, +first: U32, second: U32) -> Digest:
  Digest{U32.add(first, second), a, b, c, U32.add(d, first), e, f, g}

def round_step(words: Digest, constant: U32, word: U32) -> Digest:
  match words:
    case Digest{+a, +b, +c, d, +e, +f, +g, h}:
      round_words(a, b, c, d, e, f, g,
        U32.add(U32.add(U32.add(U32.add(h, sigma1(e)), choose(e, f, g)), constant), word),
        U32.add(sigma0(a), majority(a, b, c)))

def round_read(words: Digest, constant: U32, read: Array<U32> & U32) -> Compression:
  (schedule, word) = read
  Compression{schedule, round_step(words, constant, word)}

def rounds(constants: List<&2, U32>, +index: U32, current: Compression) -> Compression:
  match constants current:
    case Nil{} _: current
    case Con{constant, rest} Compression{schedule, words}:
      rounds(rest, U32.inc(index), round_read(words, constant, Array.get(U32, schedule, index)))

def add_digest(left: Digest, right: Digest) -> Digest:
  match left right:
    case Digest{a, b, c, d, e, f, g, h} Digest{w, x, y, z, i, j, k, l}:
      Digest{U32.add(a, w), U32.add(b, x), U32.add(c, y), U32.add(d, z), U32.add(e, i), U32.add(f, j), U32.add(g, k), U32.add(h, l)}

def compress_finish(hash: Digest, current: Compression) -> Array<U32> & Digest:
  match current:
    case Compression{schedule, words}: (schedule, add_digest(hash, words))

def compress(+hash: Digest, schedule: Array<U32>) -> Array<U32> & Digest:
  compress_finish(hash, rounds(constants(), 0, Compression{extend_schedule(48n, 16, schedule), hash}))

def new_state() -> State:
  State{initial(), Array.new(U32, 6n, 0), 0, 0, 0, 0}

def write_word(hash: Digest, schedule: Array<U32>, +position: U32, partial: U32, hi: U32, lo: U32, full_word: Bool) -> State:
  match full_word:
    case False{}: State{hash, schedule, position, partial, hi, lo}
    case True{}: State{hash, Array.set(U32, schedule, U32.sub(U32.shrn(position, 2n), 1), partial), position, 0, hi, lo}

def compressed_state(hi: U32, lo: U32, compressed: Array<U32> & Digest) -> State:
  (schedule, hash) = compressed
  State{hash, schedule, 0, 0, hi, lo}

def complete_block(state: State, full: Bool) -> State:
  match state full:
    case _ False{}: state
    case State{hash, schedule, position, partial, hi, lo} True{}:
      compressed_state(hi, lo, compress(hash, schedule))

def append_byte(state: State, byte: U32) -> State:
  match state:
    case State{hash, schedule, +position, partial, hi, +lo}:
      +next = U32.inc(position)
      +next_lo = U32.inc(lo)
      complete_block(write_word(hash, schedule, next, U32.or(U32.shln(partial, 8n), byte), U32.add(hi, Bool.to_u32(U32.is_zero(next_lo))), next_lo, U32.is_zero(U32.and(next, 3))), U32.is_eq(next, 64))

def append_list(bytes: List<&2, U32>, state: State) -> State:
  match bytes:
    case Nil{}: state
    case byte <> rest: append_list(rest, append_byte(state, byte))

def append_checked(state: State, byte: U32, valid: Bool) -> Result<&2, &1, String, State>:
  match valid:
    case False{}: Fail{"input byte exceeds 255"}
    case True{}: Done{append_byte(state, byte)}

def process(bytes: List<&2, U32>, room: Nat, state: Result<&2, &1, String, State>) -> Result<&2, &1, String, State>:
  match bytes room state:
    case _ _ Fail{error}: Fail{error}
    case Nil{} _ Done{state}: Done{state}
    case byte <> rest 0n Done{state}: Fail{"byte limit exceeded"}
    case +byte <> rest 1n+remaining Done{state}:
      process(rest, remaining, append_checked(state, byte, U32.is_le(byte, 255)))

def word_bytes(+word: U32) -> List<&2, U32>:
  U32.shrn(word, 24n) <> U32.and(U32.shrn(word, 16n), 255) <> U32.and(U32.shrn(word, 8n), 255) <> U32.and(word, 255) <> Nil{}

def bit_length(+hi: U32, +lo: U32) -> List<&2, U32>:
  List.append(&2, U32, word_bytes(U32.or(U32.shln(hi, 3n), U32.shrn(lo, 29n))), word_bytes(U32.shln(lo, 3n)))

def zero_padding(+position: U32, first_block: Bool) -> Nat:
  match first_block:
    case True{}: U32.to_nat(U32.sub(55, position))
    case False{}: U32.to_nat(U32.sub(119, position))

def append_zeros(count: Nat, state: State) -> State:
  match count:
    case 0n: state
    case 1n+rest: append_zeros(rest, append_byte(state, 0))

def state_digest(state: State) -> Digest:
  match state:
    case State{hash, schedule, position, partial, hi, lo}: hash

def finalize(state: State) -> Digest:
  match state:
    case State{hash, schedule, +position, partial, +hi, +lo}:
      state_digest(append_list(bit_length(hi, lo), append_zeros(zero_padding(position, U32.is_le(position, 55)), append_byte(State{hash, schedule, position, partial, hi, lo}, 128))))

def finish(result: Result<&2, &1, String, State>) -> Result<&2, &2, String, Digest>:
  match result:
    case Fail{error}: Fail{error}
    case Done{state}: Done{finalize(state)}

def digest_gate(limit: Nat, bytes: List<&2, U32>, valid_limit: Bool) -> Result<&2, &2, String, Digest>:
  match valid_limit:
    case False{}: Fail{"limit exceeds native Nat capacity"}
    case True{}: finish(process(bytes, limit, Done{new_state()}))

def digest(+max_bytes: Nat, bytes: List<&2, U32>) -> Result<&2, &2, String, Digest>:
  digest_gate(max_bytes, bytes, valid_limit(max_bytes))

def Digest.words(value: Digest) -> List<&2, U32>:
  match value:
    case Digest{a, b, c, d, e, f, g, h}: [a, b, c, d, e, f, g, h]

def digest_bytes(words: List<&2, U32>) -> List<&2, U32>:
  match words:
    case Nil{}: Nil{}
    case word <> rest: List.append(&2, U32, word_bytes(word), digest_bytes(rest))

def Digest.bytes(value: Digest) -> List<&2, U32>:
  digest_bytes(Digest.words(value))

def hex_character(value: U32, decimal: Bool) -> Char:
  match decimal:
    case True{}: Chr{U32.add(value, 48)}
    case False{}: Chr{U32.add(value, 87)}

def word_hex(fuel: Nat, +value: U32, acc: String) -> String:
  match fuel:
    case 0n: acc
    case 1n+rest:
      +digit = U32.and(value, 15)
      word_hex(rest, U32.shrn(value, 4n), SCon{hex_character(digit, U32.is_lt(digit, 10)), acc})

def digest_hex(words: List<&2, U32>) -> String:
  match words:
    case Nil{}: SNil{}
    case word <> rest: word_hex(8n, word, SNil{}) ++ digest_hex(rest)

def Digest.hex(value: Digest) -> String:
  digest_hex(Digest.words(value))

# Implementation laws; no cryptographic security theorem is claimed.
law zero_budget_rejects_nonempty:
  for byte: U32
  for rest: List<&2, U32>
  {digest(0n, byte <> rest) == Fail{"byte limit exceeded"} : Result<&2, &2, String, Digest>}

def zero_budget_rejects_nonempty(byte, rest):
  {==}

law oversized_native_limit_rejected:
  for +limit: Nat
  for bytes: List<&2, U32>
  for oversized: {valid_limit(limit) == False{} : Bool}
  {digest(limit, bytes) == Fail{"limit exceeds native Nat capacity"} : Result<&2, &2, String, Digest>}

def oversized_native_limit_rejected(limit, bytes, oversized):
  %Equal.sym(Bool, valid_limit(limit), False{}, oversized) : {digest_gate(limit, bytes, _) == Fail{"limit exceeds native Nat capacity"} : Result<&2, &2, String, Digest>}
  {==}

law invalid_first_byte_rejected:
  for +byte: U32
  for rest: List<&2, U32>
  for invalid: {U32.is_le(byte, 255) == False{} : Bool}
  {digest(1n, byte <> rest) == Fail{"input byte exceeds 255"} : Result<&2, &2, String, Digest>}

def invalid_first_byte_rejected(byte, rest, invalid):
  match rest:
    case Nil{}:
      %Equal.sym(Bool, U32.is_le(byte, 255), False{}, invalid) : {finish(process(Nil{}, 0n, append_checked(new_state(), byte, _))) == Fail{"input byte exceeds 255"} : Result<&2, &2, String, Digest>}
      {==}
    case Con{head, tail}:
      %Equal.sym(Bool, U32.is_le(byte, 255), False{}, invalid) : {finish(process(head <> tail, 0n, append_checked(new_state(), byte, _))) == Fail{"input byte exceeds 255"} : Result<&2, &2, String, Digest>}
      {==}

law word_output_big_endian:
  {word_bytes(305419896) == [18, 52, 86, 120] : List<&2, U32>}

def word_output_big_endian():
  {==}

law rotate_boundary_fixture:
  {rotate_right(2147483649, 33n) == 3221225472 : U32}

def rotate_boundary_fixture():
  {==}

law padding_last_one_block:
  {zero_padding(55, True{}) == 0n : Nat}

def padding_last_one_block():
  {==}

law padding_first_two_blocks:
  {zero_padding(56, False{}) == 63n : Nat}

def padding_first_two_blocks():
  {==}

law bit_length_low_word_carry:
  {bit_length(1, 0) == [0, 0, 0, 8, 0, 0, 0, 0] : List<&2, U32>}

def bit_length_low_word_carry():
  {==}
