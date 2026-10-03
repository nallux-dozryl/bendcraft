import Base
import ./f64.bend as F
import ./movement.bend as M

# A single owner for the pinned numerical table; no renderer approximation.
type Tables is Type:
  Tables{sine: Array<F32>}

type Error is Data:
  TableLength{bytes: Nat}
  TableByte{index: U32, value: U32}
  TableHash{}
  TableRead{code: U32, message: String}

type Digest is Data:
  Digest{a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32}

def float_bits(value: U32) -> F32:
  match value:
    case U32{word}: F32{word}

def big_word(a: U32, b: U32, c: U32, d: U32) -> U32:
  U32.or(U32.or(U32.shln(a, 24n), U32.shln(b, 16n)), U32.or(U32.shln(c, 8n), d))

def little_word(a: U32, b: U32, c: U32, d: U32) -> U32:
  big_word(d, c, b, a)

def rotate(+value: U32, right: Nat, left: Nat) -> U32:
  U32.or(U32.shrn(value, right), U32.shln(value, left))

def sigma0(+value: U32) -> U32:
  U32.xor(U32.xor(rotate(value, 7n, 25n), rotate(value, 18n, 14n)), U32.shrn(value, 3n))

def sigma1(+value: U32) -> U32:
  U32.xor(U32.xor(rotate(value, 17n, 15n), rotate(value, 19n, 13n)), U32.shrn(value, 10n))

def sum0(+value: U32) -> U32:
  U32.xor(U32.xor(rotate(value, 2n, 30n), rotate(value, 13n, 19n)), rotate(value, 22n, 10n))

def sum1(+value: U32) -> U32:
  U32.xor(U32.xor(rotate(value, 6n, 26n), rotate(value, 11n, 21n)), rotate(value, 25n, 7n))

def choose(+e: U32, f: U32, g: U32) -> U32:
  U32.xor(U32.and(e, f), U32.and(U32.not(e), g))

def majority(+a: U32, +b: U32, +c: U32) -> U32:
  U32.xor(U32.xor(U32.and(a, b), U32.and(a, c)), U32.and(b, c))

def digest_initial() -> Digest:
  Digest{1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635, 1541459225}

def digest_expected() -> Digest:
  Digest{3455773800, 1886948889, 1040138013, 3752053373, 1058703728, 1121420133, 2717792835, 1004757629}

def digest_equal(a: Digest, b: Digest) -> Bool:
  match a b:
    case Digest{a, b, c, d, e, f, g, h} Digest{i, j, k, l, m, n, o, p}:
      U32.is_eq(a, i) && U32.is_eq(b, j) && U32.is_eq(c, k) && U32.is_eq(d, l) && U32.is_eq(e, m) && U32.is_eq(f, n) && U32.is_eq(g, o) && U32.is_eq(h, p)

def digest_add(a: Digest, b: Digest) -> Digest:
  match a b:
    case Digest{a, b, c, d, e, f, g, h} Digest{i, j, k, l, m, n, o, p}:
      Digest{U32.add(a, i), U32.add(b, j), U32.add(c, k), U32.add(d, l), U32.add(e, m), U32.add(f, n), U32.add(g, o), U32.add(h, p)}

def round_finish(a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, +t1: U32, t2: U32) -> Digest:
  Digest{U32.add(t1, t2), a, b, c, U32.add(d, t1), e, f, g}

def sha_round(state: Digest, constant: U32, word: U32) -> Digest:
  match state:
    case Digest{+a, +b, +c, d, +e, +f, +g, h}:
      t1 = U32.add(U32.add(U32.add(U32.add(h, sum1(e)), choose(e, f, g)), constant), word)
      t2 = U32.add(sum0(a), majority(a, b, c))
      round_finish(a, b, c, d, e, f, g, t1, t2)

def sha_constants() -> List<&2, U32>:
  [1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221,
   3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580,
   3835390401, 4022224774, 264347078, 604807628, 770255983, 1249150122, 1555081692, 1996064986,
   2554220882, 2821834349, 2952996808, 3210313671, 3336571891, 3584528711, 113926993, 338241895,
   666307205, 773529912, 1294757372, 1396182291, 1695183700, 1986661051, 2177026350, 2456956037,
   2730485921, 2820302411, 3259730800, 3345764771, 3516065817, 3600352804, 4094571909, 275423344,
   430227734, 506948616, 659060556, 883997877, 958139571, 1322822218, 1537002063, 1747873779,
   1955562222, 2024104815, 2227730452, 2361852424, 2428436474, 2756734187, 3204031479, 3329325298]

def schedule_seed(words: List<&2, U32>, +index: U32, array: Array<U32>) -> Array<U32>:
  match words:
    case Nil{}: array
    case word <> rest: schedule_seed(rest, U32.inc(index), Array.set(U32, array, index, word))

def schedule_d(index: U32, a: U32, b: U32, c: U32, read: Array<U32> & U32) -> Array<U32>:
  (array, d) = read
  Array.set(U32, array, index, U32.add(U32.add(U32.add(sigma1(a), b), sigma0(c)), d))

def schedule_c(+index: U32, a: U32, b: U32, read: Array<U32> & U32) -> Array<U32>:
  (array, c) = read
  schedule_d(index, a, b, c, Array.get(U32, array, U32.sub(index, 16)))

def schedule_b(+index: U32, a: U32, read: Array<U32> & U32) -> Array<U32>:
  (array, b) = read
  schedule_c(index, a, b, Array.get(U32, array, U32.sub(index, 15)))

def schedule_a(+index: U32, read: Array<U32> & U32) -> Array<U32>:
  (array, a) = read
  schedule_b(index, a, Array.get(U32, array, U32.sub(index, 7)))

def schedule_next(+index: U32, array: Array<U32>) -> Array<U32>:
  schedule_a(index, Array.get(U32, array, U32.sub(index, 2)))

def schedule_expand(fuel: Nat, +index: U32, array: Array<U32>) -> Array<U32>:
  match fuel:
    case 0n: array
    case 1n+rest:
      schedule_expand(rest, U32.inc(index), schedule_next(index, array))

def sha_rounds(constants: List<&2, U32>, index: U32, read: Array<U32> & U32, state: Digest) -> Digest:
  match constants:
    case Nil{}: state
    case constant <> rest:
      (array, word) = read
      +next = U32.inc(index)
      sha_rounds(rest, next, Array.get(U32, array, next), sha_round(state, constant, word))

def sha_block(words: List<&2, U32>, +state: Digest) -> Digest:
  array = schedule_expand(48n, 16, schedule_seed(words, 0, Array.new(U32, 6n, 0)))
  digest_add(state, sha_rounds(sha_constants(), 0, Array.get(U32, array, 0), state))

# Fixed 262144-byte message padding: 2097152 bits, a whole number of blocks.
def sha_padding(state: Digest) -> Digest:
  sha_block([2147483648, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2097152], state)

def sha_blocks(words: List<&2, U32>, state: Digest) -> Digest:
  match words:
    case Nil{}: sha_padding(state)
    case a <> b <> c <> d <> e <> f <> g <> h <> i <> j <> k <> l <> m <> n <> o <> p <> rest:
      sha_blocks(rest, sha_block([a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p], state))
    case _: Digest{0, 0, 0, 0, 0, 0, 0, 0}

def big_words(bytes: List<&2, U32>) -> List<&2, U32>:
  match bytes:
    case a <> b <> c <> d <> rest: big_word(a, b, c, d) <> big_words(rest)
    case _: Nil{}

def byte_valid_gate(index: U32, value: U32, invalid: Bool) -> Maybe<&2, Error>:
  match invalid:
    case True{}: Some{TableByte{index, value}}
    case False{}: None{}

def byte_valid(bytes: List<&2, U32>, +index: U32, error: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match bytes error:
    case _ Some{error}: Some{error}
    case Nil{} None{}: None{}
    case +value <> rest None{}: byte_valid(rest, U32.inc(index), byte_valid_gate(index, value, U32.is_gt(value, 255)))

def table_words(bytes: List<&2, U32>, +index: U32, array: Array<F32>) -> Tables:
  match bytes:
    case a <> b <> c <> d <> rest:
      table_words(rest, U32.inc(index), Array.set(F32, array, index, float_bits(little_word(a, b, c, d))))
    case _: Tables{array}

def table_hash_gate(bytes: List<&2, U32>, valid: Bool) -> Result<&2, &1, Error, Tables>:
  match valid:
    case True{}: Done{table_words(bytes, 0, Array.new(F32, 16n, 0.0))}
    case False{}: Fail{TableHash{}}

def table_byte_gate(+bytes: List<&2, U32>, error: Maybe<&2, Error>) -> Result<&2, &1, Error, Tables>:
  match error:
    case Some{error}: Fail{error}
    case None{}: table_hash_gate(bytes, digest_equal(sha_blocks(big_words(bytes), digest_initial()), digest_expected()))

def table_length_gate(+bytes: List<&2, U32>, +count: Nat, valid: Bool) -> Result<&2, &1, Error, Tables>:
  match valid:
    case False{}: Fail{TableLength{count}}
    case True{}: table_byte_gate(bytes, byte_valid(bytes, 0, None{}))

def Tables.decode(+bytes: List<&2, U32>) -> Result<&2, &1, Error, Tables>:
  +count = List.length(&2, U32, bytes)
  table_length_gate(bytes, count, Nat.is_eq(count, 262144n))

def table_read(read: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Result<&2, &1, Error, Tables>):
  (file, result) = read
  match result:
    case Fail{(code, message)}:
      do IO<Result<&2, &1, Error, Tables>>:
        File.close(file)
        return Fail{TableRead{code, message}}
    case Done{bytes}:
      do IO<Result<&2, &1, Error, Tables>>:
        File.close(file)
        return Tables.decode(bytes)

def table_open(opened: Result<&1, &1, U32 & String, File>) -> IO(Result<&2, &1, Error, Tables>):
  match opened:
    case Fail{(code, message)}: IO.pure(Result<&2, &1, Error, Tables>, Fail{TableRead{code, message}})
    case Done{file}:
      do IO<Result<&2, &1, Error, Tables>>:
        read : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, 262145)
        table_read(read)

def Tables.load(path: String) -> IO(Result<&2, &1, Error, Tables>):
  do IO<Result<&2, &1, Error, Tables>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    table_open(opened)

def index_word(value: F.Word64) -> U32:
  match value:
    case F.Word64{hi, lo}: U32.and(lo, 65535)

def sine_index(angle: F.F64) -> U32:
  index_word(F.to_java_long(F.mul(angle, F.F64{1086611248, 1841940611})))

def cosine_index(angle: F.F64) -> U32:
  index_word(F.to_java_long(F.add(F.mul(angle, F.F64{1086611248, 1841940611}), F.F64{1087373312, 0})))

def table_value(read: Array<F32> & F32) -> Tables & F32:
  (array, value) = read
  (Tables{array}, value)

def Tables.at(tables: Tables, index: U32) -> Tables & F32:
  match tables:
    case Tables{array}:
      table_value(Array.get(F32, array, index))

def sin(tables: Tables, angle: F.F64) -> Tables & F32:
  Tables.at(tables, sine_index(angle))

def cos(tables: Tables, angle: F.F64) -> Tables & F32:
  Tables.at(tables, cosine_index(angle))

def normalize_gate(vector: M.Vec3, +length: F.F64, small: Bool) -> M.Vec3:
  match vector small:
    case _ True{}: M.Vec3.zero()
    case M.Vec3{x, y, z} False{}: M.Vec3{F.div(x, length), F.div(y, length), F.div(z, length)}

def normalize_length(vector: M.Vec3, +length: F.F64) -> M.Vec3:
  normalize_gate(vector, length, F.is_lt(length, F.F64{1055193269, 2147483648}))

def normalize(+vector: M.Vec3) -> M.Vec3:
  normalize_length(vector, F.sqrt(M.Vec3.length_squared(vector)))

def scale(vector: M.Vec3, +factor: F.F64) -> M.Vec3:
  match vector:
    case M.Vec3{x, y, z}: M.Vec3{F.mul(x, factor), F.mul(y, factor), F.mul(z, factor)}

def normalize_input_gate(vector: M.Vec3, large: Bool) -> M.Vec3:
  match large:
    case False{}: vector
    case True{}: normalize(vector)

def rotate_input(vector: M.Vec3, sine: F32, cosine: F32) -> M.Vec3:
  match vector:
    case M.Vec3{+x, y, +z}:
      +s = F.from_f32(sine)
      +c = F.from_f32(cosine)
      M.Vec3{F.sub(F.mul(x, c), F.mul(z, s)), y, F.add(F.mul(z, c), F.mul(x, s))}

def input_cosine(vector: M.Vec3, sine: F32, read: Tables & F32) -> Tables & M.Vec3:
  (tables, cosine) = read
  (tables, rotate_input(vector, sine, cosine))

def input_sine(vector: M.Vec3, angle: F.F64, read: Tables & F32) -> Tables & M.Vec3:
  (tables, sine) = read
  input_cosine(vector, sine, cos(tables, angle))

def input_trig(tables: Tables, vector: M.Vec3, +angle: F.F64) -> Tables & M.Vec3:
  input_sine(vector, angle, sin(tables, angle))

def input_gate(tables: Tables, vector: M.Vec3, length_squared: F.F64, acceleration: F32, yaw: F32, small: Bool) -> Tables & M.Vec3:
  match small:
    case True{}: (tables, M.Vec3.zero())
    case False{}:
      scaled = scale(normalize_input_gate(vector, F.is_gt(length_squared, M.one())), F.from_f32(acceleration))
      input_trig(tables, scaled, F.from_f32(F32.mul(yaw, float_bits(1016003125))))

def input_length(tables: Tables, vector: M.Vec3, +length_squared: F.F64, acceleration: F32, yaw: F32) -> Tables & M.Vec3:
  input_gate(tables, vector, length_squared, acceleration, yaw, F.is_lt(length_squared, F.F64{1048238066, 2596056904}))

def get_input_vector(tables: Tables, +vector: M.Vec3, acceleration: F32, yaw: F32) -> Tables & M.Vec3:
  input_length(tables, vector, M.Vec3.length_squared(vector), acceleration, yaw)

law small_normalization_is_zero:
  for vector: M.Vec3
  for length: F.F64
  {normalize_gate(vector, length, True{}) == M.Vec3.zero() : M.Vec3}

def small_normalization_is_zero(vector, length):
  match vector:
    case M.Vec3{x, y, z}: {==}

law small_input_preserves_table_owner:
  for tables: Tables
  for vector: M.Vec3
  for length_squared: F.F64
  for acceleration: F32
  for yaw: F32
  {input_gate(tables, vector, length_squared, acceleration, yaw, True{}) == (tables, M.Vec3.zero()) : Tables & M.Vec3}

def small_input_preserves_table_owner(tables, vector, length_squared, acceleration, yaw):
  {==}

law unit_input_bypasses_normalization:
  for vector: M.Vec3
  {normalize_input_gate(vector, False{}) == vector : M.Vec3}

def unit_input_bypasses_normalization(vector):
  {==}

law hash_failure_rejects_before_table_allocation:
  for bytes: List<&2, U32>
  {table_hash_gate(bytes, False{}) == Fail{TableHash{}} : Result<&2, &1, Error, Tables>}

def hash_failure_rejects_before_table_allocation(bytes):
  {==}

law stationary_normalization_is_zero:
  {normalize(M.Vec3.zero()) == M.Vec3.zero() : M.Vec3}

def stationary_normalization_is_zero():
  {==}

law length_failure_rejects_before_hash:
  for bytes: List<&2, U32>
  for count: Nat
  {table_length_gate(bytes, count, False{}) == Fail{TableLength{count}} : Result<&2, &1, Error, Tables>}

def length_failure_rejects_before_hash(bytes, count):
  {==}

law positive_infinity_saturates_to_last_index:
  {sine_index(F.F64{2146435072, 0}) == 65535 : U32}

def positive_infinity_saturates_to_last_index():
  {==}

law negative_infinity_saturates_to_first_index:
  {sine_index(F.F64{4293918720, 0}) == 0 : U32}

def negative_infinity_saturates_to_first_index():
  {==}
