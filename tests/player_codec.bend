import Base
import ../src/f64.bend as F
import ../src/geometry.bend as G
import ../src/movement.bend as M
import ../src/travel.bend as T
import ../src/player_tick.bend as PT
import ../src/support.bend as SP
import ../src/nbt.bend as N
import ../src/player_codec.bend as P

def fixture() -> P.Snapshot:
  P.Snapshot{PT.State{M.Body{M.Vec3.zero(), G.AABB{M.zero(), M.zero(), M.zero(), M.zero(), M.zero(), M.zero()}, M.Vec3.zero(), P.float_bits(0), P.float_bits(0), False{}, False{}, False{}, False{}},
    PT.Input{P.float_bits(0), P.float_bits(0), P.float_bits(0)}, False{}, 4294967295, 2147483648, False{}, P.float_bits(0), P.float_bits(0)}, SP.State{Some{T.BlockPos{4294967295, 2147483648, 2147483647}}, True{}}, P.float_bits(0), P.float_bits(0), "minecraft:overworld"}

# These laws test representation, strict schema rejection, and Data retention. They do not
# establish universal NBT/vanilla-save or full neutral-player replay fidelity.
law signed_counter_words:
  for +bits: U32
  {P.int_value(N.Int{bits}, "jump_delay") == Done{bits} : Result<&2, &2, P.Error, U32>}

def signed_counter_words(bits):
  {==}

law double_vector_words:
  for +a: U32
  for +b: U32
  for +c: U32
  for +d: U32
  for +e: U32
  for +f: U32
  {P.vector_value(P.vector_tag(M.Vec3{F.F64{a, b}, F.F64{c, d}, F.F64{e, f}}), "position") == Done{M.Vec3{F.F64{a, b}, F.F64{c, d}, F.F64{e, f}}} : Result<&2, &2, P.Error, M.Vec3>}

def double_vector_words(a, b, c, d, e, f):
  {==}

law support_signed_coordinates:
  for +x: U32
  for +y: U32
  for +z: U32
  {P.main_value(P.main_tag(Some{T.BlockPos{x, y, z}})) == Done{Some{T.BlockPos{x, y, z}}} : Result<&2, &2, P.Error, Maybe<&2, T.BlockPos>>}

def support_signed_coordinates(x, y, z):
  {==}

law no_support_declared_type:
  {P.main_value(P.main_tag(None{})) == Done{None{}} : Result<&2, &2, P.Error, Maybe<&2, T.BlockPos>>}

def no_support_declared_type():
  {==}

law rejected_encoder_retains_snapshot:
  for +snapshot: P.Snapshot
  for +error: P.Error
  {(snapshot, P.encode_validated(4096, Fail{error})) == (snapshot, Fail{error}) : P.Snapshot & Result<&2, &2, P.Error, List<&2, U32>>}

def rejected_encoder_retains_snapshot(snapshot, error):
  {==}

law wrong_version_rejected:
  {P.version_value(N.Int{2}) == Fail{P.UnsupportedVersion{2}} : Result<&2, &2, P.Error, Unit>}

def wrong_version_rejected():
  {==}

law short_support_list_rejected:
  {P.main_value(N.ListTag{3, [N.Int{0}]}) == Fail{P.SchemaError{"support.main", "expected zero or three Int tags"}} : Result<&2, &2, P.Error, Maybe<&2, T.BlockPos>>}

def short_support_list_rejected():
  {==}

# Native harness: raw fixture words, physical NBT input/output, no host codec.
def fixture_words(bytes: List<&2, U32>, acc: List<&2, U32>) -> Result<&2, &2, String, List<&2, U32>>:
  match bytes:
    case Nil{}: Done{List.reverse(&2, U32, acc)}
    case a <> b <> c <> d <> rest:
      fixture_words(rest, U32.or(a, U32.or(U32.shln(b, 8n), U32.or(U32.shln(c, 16n), U32.shln(d, 24n)))) <> acc)
    case _: Fail{"fixture byte count is not a multiple of four"}

def fixture_support(present: U32, x: U32, y: U32, z: U32, no_blocks: U32) -> SP.State:
  SP.State{N.choose(Maybe<&2, T.BlockPos>, None{}, Some{T.BlockPos{x, y, z}}, U32.is_eq(present, 0)), U32.is_eq(no_blocks, 1)}

def snapshot_words(words: List<&2, U32>, dimension: String) -> Result<&2, &2, String, P.Snapshot>:
  match words:
    case a <> b <> c <> d <> e <> f <> g <> h <> i <> j <> k <> l <> m <> n <> o <> p <> q <> r <>
         s <> t <> u <> v <> w <> x <> width <> height <> +ground <> +horizontal <> +vertical <> +below <>
         ix <> iy <> iz <> +jumping <> delay <> trigger <> +sync <> speed <> head <> yaw <> pitch <>
         +present <> +sx <> +sy <> +sz <> +no_blocks <> Nil{}:
      N.choose(Result<&2, &2, String, P.Snapshot>,
        Done{P.Snapshot{PT.State{M.Body{M.Vec3{F.F64{a, b}, F.F64{c, d}, F.F64{e, f}},
          G.AABB{F.F64{g, h}, F.F64{i, j}, F.F64{k, l}, F.F64{m, n}, F.F64{o, p}, F.F64{q, r}},
          M.Vec3{F.F64{s, t}, F.F64{u, v}, F.F64{w, x}}, P.float_bits(width), P.float_bits(height),
          U32.is_eq(ground, 1), U32.is_eq(horizontal, 1), U32.is_eq(vertical, 1), U32.is_eq(below, 1)},
          PT.Input{P.float_bits(ix), P.float_bits(iy), P.float_bits(iz)}, U32.is_eq(jumping, 1), delay, trigger, U32.is_eq(sync, 1), P.float_bits(speed), P.float_bits(head)},
          fixture_support(present, sx, sy, sz, no_blocks), P.float_bits(yaw), P.float_bits(pitch), dimension}},
        Fail{"noncanonical fixture Boolean or absent-support words"},
        U32.is_le(ground, 1) && U32.is_le(horizontal, 1) && U32.is_le(vertical, 1) && U32.is_le(below, 1) &&
        U32.is_le(jumping, 1) && U32.is_le(sync, 1) && U32.is_le(present, 1) && U32.is_le(no_blocks, 1) &&
        (U32.is_eq(present, 1) || (U32.is_eq(sx, 0) && U32.is_eq(sy, 0) && U32.is_eq(sz, 0))))
    case _: Fail{"native fixture requires exactly 46 words"}

def double_words(value: F.F64) -> List<&2, U32>:
  match value:
    case F.F64{hi, lo}: [hi, lo]

def vector_words(value: M.Vec3) -> List<&2, U32>:
  match value:
    case M.Vec3{x, y, z}: List.append(&2, U32, double_words(x), List.append(&2, U32, double_words(y), double_words(z)))

def box_words(value: G.AABB) -> List<&2, U32>:
  match value:
    case G.AABB{a, b, c, d, e, f}:
      List.append(&2, U32, double_words(a), List.append(&2, U32, double_words(b), List.append(&2, U32, double_words(c),
        List.append(&2, U32, double_words(d), List.append(&2, U32, double_words(e), double_words(f))))))

def bool_word(value: Bool) -> U32:
  match value:
    case True{}: 1
    case False{}: 0

def support_words(value: SP.State) -> List<&2, U32>:
  match value:
    case SP.State{None{}, flag}: [0, 0, 0, 0, bool_word(flag)]
    case SP.State{Some{T.BlockPos{x, y, z}}, flag}: [1, x, y, z, bool_word(flag)]

def body_words(value: M.Body) -> List<&2, U32>:
  match value:
    case M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below}:
      List.append(&2, U32, vector_words(position), List.append(&2, U32, box_words(box), List.append(&2, U32, vector_words(velocity),
        [F32.bits(width), F32.bits(height), bool_word(ground), bool_word(horizontal), bool_word(vertical), bool_word(below)])))

def snapshot_output(value: P.Snapshot) -> List<&2, U32>:
  match value:
    case P.Snapshot{PT.State{body, PT.Input{x, y, z}, jumping, delay, trigger, sync, speed, head}, support, yaw, pitch, dimension}:
      List.append(&2, U32, body_words(body), List.append(&2, U32,
        [F32.bits(x), F32.bits(y), F32.bits(z), bool_word(jumping), delay, trigger, bool_word(sync), F32.bits(speed), F32.bits(head), F32.bits(yaw), F32.bits(pitch)], support_words(support)))

def little_bytes(words: List<&2, U32>) -> List<&2, U32>:
  match words:
    case Nil{}: Nil{}
    case +word <> rest:
      U32.and(word, 255) <> U32.and(U32.shrn(word, 8n), 255) <> U32.and(U32.shrn(word, 16n), 255) <> U32.shrn(word, 24n) <> little_bytes(rest)

def error_text(error: P.Error) -> String:
  match error:
    case P.NbtError{message}: "NbtError: " ++ message
    case P.SchemaError{field, message}: "SchemaError: " ++ field ++ ": " ++ message
    case P.UnsupportedVersion{bits}: "UnsupportedVersion: " ++ U32.show(bits)
    case P.UnsupportedDimension{}: "UnsupportedDimension"
    case P.UnsupportedByteBudget{max_bytes}: "UnsupportedByteBudget: " ++ U32.show(max_bytes)
    case P.InvalidState{cause}: "InvalidState"
    case P.InconsistentBody{}: "InconsistentBody"
    case P.InvalidView{field}: "InvalidView: " ++ U32.show(field)

def hex_char(+n: U32) -> Char:
  N.choose(Char, Chr{U32.add(n, 48)}, Chr{U32.add(n, 87)}, U32.is_lt(n, 10))

def quote_char(+code: U32) -> String:
  match code:
    case 34: "\\\""
    case 92: "\\\\"
    case _:
      N.choose(String, "\\u00" ++ Char.show(hex_char(U32.div(code, 16))) ++ Char.show(hex_char(U32.mod(code, 16))), Char.show(Chr{code}), U32.is_lt(code, 32))

def quote(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{code}, rest}: quote_char(code) ++ quote(rest)

def failure(error: P.Error) -> IO(Unit):
  IO.print("{\"ok\":false,\"error\":\"" ++ quote(error_text(error)) ++ "\"}")

def written(report: String, result: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (file, status) = result
  do IO<Unit>:
    IO.pass(Unit, status)
    File.close(file)
    IO.print(report)

def publish(path: String, bytes: List<&2, U32>, report: String) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File, File.open(path, "w"))
    result : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(file, bytes)
    written(report, result)

def encoded(path: String, result: Result<&2, &2, P.Error, List<&2, U32>>) -> IO(Unit):
  match result:
    case Fail{error}: failure(error)
    case Done{bytes}: publish(path, bytes, "{\"ok\":true}")

def encode_fixture(path: String, max_bytes: U32, result: Result<&2, &2, String, P.Snapshot>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit, 2, message)
    case Done{snapshot}: encoded(path, P.encode_with(max_bytes, snapshot))

def parsed_fixture(path: String, dimension: String, max_bytes: U32, result: Result<&2, &2, String, List<&2, U32>>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit, 2, message)
    case Done{words}: encode_fixture(path, max_bytes, snapshot_words(words, dimension))

def decoded(path: String, result: Result<&2, &2, P.Error, P.Snapshot>) -> IO(Unit):
  match result:
    case Fail{error}: failure(error)
    case Done{+snapshot}:
      P.Snapshot{state, support, yaw, pitch, dimension} = snapshot
      publish(path, little_bytes(snapshot_output(snapshot)), "{\"ok\":true,\"dimension\":\"" ++ quote(dimension) ++ "\"}")

def execute(mode: String, input: List<&2, U32>, output: String, dimension: String, max_bytes: U32) -> IO(Unit):
  match mode:
    case "encode": parsed_fixture(output, dimension, max_bytes, fixture_words(input, Nil{}))
    case "decode": decoded(output, P.decode_with(max_bytes, input))
    case _: IO.die(Unit, 2, "expected encode or decode mode")

def loaded(mode: String, output: String, dimension: String, max_bytes: U32,
           result: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  (file, status) = result
  do IO<Unit>:
    File.close(file)
    bytes : List<&2, U32> <- IO.pass(List<&2, U32>, status)
    execute(mode, bytes, output, dimension, max_bytes)

def read_fixture(mode: String, input: String, output: String, dimension: String, max_bytes: U32) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File, File.open(input, "r"))
    result : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, 262144)
    loaded(mode, output, dimension, max_bytes, result)

def configuration(mode: String, input: String, output: String, dimension: String, limit: Maybe<&2, U32>) -> IO(Unit):
  match limit:
    case None{}: IO.die(Unit, 2, "invalid fixture byte budget")
    case Some{limit}: read_fixture(mode, input, output, dimension, limit)

def batch(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case mode <> input <> output <> dimension <> limit <> rest:
      do IO<Unit>:
        configuration(mode, input, output, dimension, U32.read(limit))
        batch(rest)
    case _: IO.die(Unit, 2, "expected MODE INPUT OUTPUT DIMENSION MAX_BYTES groups")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    batch(List.tail(&1, String, args))
