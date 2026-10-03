import Base
import ../src/f64.bend as F
import ../src/movement.bend as M
import ../src/locomotion.bend as L
import ./geometry.bend as T

def vector_show(vector: M.Vec3) -> String:
  match vector:
    case M.Vec3{x, y, z}: T.f64_show(x) ++ "|" ++ T.f64_show(y) ++ "|" ++ T.f64_show(z)

def digest_show(digest: L.Digest) -> String:
  match digest:
    case L.Digest{a, b, c, d, e, f, g, h}:
      U32.show(a) ++ "|" ++ U32.show(b) ++ "|" ++ U32.show(c) ++ "|" ++ U32.show(d) ++ "|" ++ U32.show(e) ++ "|" ++ U32.show(f) ++ "|" ++ U32.show(g) ++ "|" ++ U32.show(h)

def message_value(+index: U32, kind: U32) -> U32:
  match kind:
    case 0: 0
    case 1: 255
    case _: U32.and(index, 255)

def message_bytes(fuel: Nat, +index: U32, +kind: U32) -> List<&2, U32>:
  match fuel:
    case 0n: Nil{}
    case 1n+rest: message_value(index, kind) <> message_bytes(rest, U32.inc(index), kind)

def invalid_byte_value(index: U32, invalid_index: U32, invalid_value: U32) -> U32:
  Bool.pick(U32, U32.is_eq(index, invalid_index), invalid_value, 0)

def invalid_bytes(fuel: Nat, +index: U32, +invalid_index: U32, +invalid_value: U32) -> List<&2, U32>:
  match fuel:
    case 0n: Nil{}
    case 1n+rest: invalid_byte_value(index, invalid_index, invalid_value) <> invalid_bytes(rest, U32.inc(index), invalid_index, invalid_value)

def error_text(error: L.Error) -> String:
  match error:
    case L.TableLength{bytes}: "length|" ++ Nat.show(bytes)
    case L.TableByte{index, value}: "byte|" ++ U32.show(index) ++ "|" ++ U32.show(value)
    case L.TableHash{}: "hash"
    case L.TableRead{code, message}: "read|" ++ U32.show(code) ++ "|" ++ message

def decode_show(id: String, tables: L.Tables, result: Result<&2, &1, L.Error, L.Tables>) -> IO(L.Tables):
  match result:
    case Fail{error}:
      do IO<L.Tables>:
        IO.print(id ++ "|decode_error|" ++ error_text(error))
        return tables
    case Done{loaded}:
      do IO<L.Tables>:
        IO.print(id ++ "|decode_ok")
        return tables

def float_show(id: String, read: L.Tables & F32) -> IO(L.Tables):
  (tables, value) = read
  do IO<L.Tables>:
    IO.print(id ++ "|f32|" ++ U32.show(F32.bits(value)))
    return tables

def input_show(id: String, read: L.Tables & M.Vec3) -> IO(L.Tables):
  (tables, value) = read
  do IO<L.Tables>:
    IO.print(id ++ "|vector|" ++ vector_show(value))
    return tables

def index_show(id: String, cosine: Bool, hi: U32, lo: U32, tables: L.Tables) -> IO(L.Tables):
  match cosine:
    case False{}:
      do IO<L.Tables>:
        IO.print(id ++ "|index|" ++ U32.show(L.sine_index(F.F64{hi, lo})))
        return tables
    case True{}:
      do IO<L.Tables>:
        IO.print(id ++ "|index|" ++ U32.show(L.cosine_index(F.F64{hi, lo})))
        return tables

def parsed(id: String, op: String, fields: List<&2, U32>, tables: L.Tables) -> IO(L.Tables):
  match op fields:
    case "sha" kind <> Nil{}:
      do IO<L.Tables>:
        IO.print(id ++ "|digest|" ++ digest_show(L.sha_blocks(L.big_words(message_bytes(262144n, 0, kind)), L.digest_initial())))
        return tables
    case "invalid_byte" index <> value <> Nil{}:
      decode_show(id, tables, L.Tables.decode(invalid_bytes(262144n, 0, index, value)))
    case "sin" hi <> lo <> Nil{}: float_show(id, L.sin(tables, F.F64{hi, lo}))
    case "cos" hi <> lo <> Nil{}: float_show(id, L.cos(tables, F.F64{hi, lo}))
    case "sin_index" hi <> lo <> Nil{}: index_show(id, False{}, hi, lo, tables)
    case "cos_index" hi <> lo <> Nil{}: index_show(id, True{}, hi, lo, tables)
    case "normalize" xh <> xl <> yh <> yl <> zh <> zl <> Nil{}:
      do IO<L.Tables>:
        IO.print(id ++ "|vector|" ++ vector_show(L.normalize(M.Vec3{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{zh, zl}})))
        return tables
    case "input" xh <> xl <> yh <> yl <> zh <> zl <> acceleration <> yaw <> Nil{}:
      input_show(id, L.get_input_vector(tables, M.Vec3{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{zh, zl}}, L.float_bits(acceleration), L.float_bits(yaw)))
    case _ _: IO.die(L.Tables, 2, "invalid locomotion fields")

def number_gate(value: Maybe<&2, U32>, rest: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match value rest:
    case Some{value} Some{rest}: Some{value <> rest}
    case _ _: None{}

def numbers(fields: List<&2, String>) -> Maybe<&2, List<&2, U32>>:
  match fields:
    case Nil{}: Some{Nil{}}
    case field <> rest: number_gate(U32.read(field), numbers(rest))

def parsed_numbers(id: String, op: String, fields: Maybe<&2, List<&2, U32>>, tables: L.Tables) -> IO(L.Tables):
  match fields:
    case Some{fields}: parsed(id, op, fields, tables)
    case None{}: IO.die(L.Tables, 2, "invalid locomotion number")

def parse_header(parts: List<&2, String>, tables: L.Tables) -> IO(L.Tables):
  match parts:
    case id <> op <> rest: parsed_numbers(id, op, numbers(rest), tables)
    case _: IO.die(L.Tables, 2, "invalid locomotion header")

def table_all(fuel: Nat, +index: U32, read: L.Tables & F32) -> IO(L.Tables):
  match fuel:
    case 0n:
      (tables, value) = read
      IO.pure(L.Tables, tables)
    case 1n+rest:
      (tables, value) = read
      do IO<L.Tables>:
        IO.print("table|" ++ U32.show(index) ++ "|" ++ U32.show(F32.bits(value)))
        table_all(rest, U32.inc(index), L.Tables.at(tables, U32.inc(index)))

def dispatch(+arg: String, tables: L.Tables) -> IO(L.Tables):
  match arg:
    case "table_all": table_all(65536n, 0, L.Tables.at(tables, 0))
    case _: parse_header(String.split(arg, '|'), tables)

def run_args(args: List<String>, tables: L.Tables) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case arg <> rest:
      do IO<Unit>:
        tables : L.Tables <- dispatch(arg, tables)
        run_args(rest, tables)

def loaded(args: List<String>, result: Result<&2, &1, L.Error, L.Tables>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 3, "invalid locomotion table|" ++ error_text(error))
    case Done{tables}: run_args(args, tables)

def table_path(args: List<String>) -> IO(Unit):
  match args:
    case path <> rest:
      do IO<Unit>:
        result : Result<&2, &1, L.Error, L.Tables> <- L.Tables.load(path)
        loaded(rest, result)
    case _: IO.die(Unit, 2, "locomotion table path required")

def drop_program(args: List<String>) -> IO(Unit):
  match args:
    case program <> rest: table_path(rest)
    case _: IO.die(Unit, 2, "locomotion arguments required")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), drop_program)
