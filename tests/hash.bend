import Base
import ../src/hash.bend as H

type Operation is Data:
  HashHex{}
  HashValues{}
  HashRepeat{}
  HashFile{}
  HashLength{}
  HashRotate{}

def operation(text: String) -> Maybe<&2, Operation>:
  match text:
    case "hex": Some{HashHex{}}
    case "values": Some{HashValues{}}
    case "repeat": Some{HashRepeat{}}
    case "file": Some{HashFile{}}
    case "length": Some{HashLength{}}
    case "rotate": Some{HashRotate{}}
    case _: None{}

def number_result(result: Maybe<&2, U32>) -> U32:
  match result:
    case Some{value}: value
    case None{}: 0

def number(text: String) -> U32:
  number_result(U32.read(text))

def size_result(result: Maybe<&2, Nat>) -> Nat:
  match result:
    case Some{value}: value
    case None{}: 0n

def size(text: String) -> Nat:
  size_result(Nat.read(text))

def numbers(values: List<&2, String>) -> List<&2, U32>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: number(value) <> numbers(rest)

def decimal_values(text: String) -> List<&2, U32>:
  match text:
    case "": Nil{}
    case _: numbers(String.split(text, ','))

def byte_list_tail(values: List<&2, U32>) -> String:
  match values:
    case Nil{}: SNil{}
    case value <> rest: "," ++ U32.show(value) ++ byte_list_tail(rest)

def byte_list(values: List<&2, U32>) -> String:
  match values:
    case Nil{}: SNil{}
    case value <> rest: U32.show(value) ++ byte_list_tail(rest)

def nibble_letter(value: U32, valid: Bool) -> Maybe<&2, U32>:
  match valid:
    case False{}: None{}
    case True{}: Some{U32.sub(value, 87)}

def nibble_digit(+value: U32, valid: Bool) -> Maybe<&2, U32>:
  match valid:
    case True{}: Some{U32.sub(value, 48)}
    case False{}: nibble_letter(value, U32.is_ge(value, 97) && U32.is_le(value, 102))

def nibble(+value: U32) -> Maybe<&2, U32>:
  nibble_digit(value, U32.is_ge(value, 48) && U32.is_le(value, 57))

def hex_add(high: Maybe<&2, U32>, low: Maybe<&2, U32>, current: Result<&2, &2, String, List<&2, U32>>) -> Result<&2, &2, String, List<&2, U32>>:
  match high low current:
    case _ _ Fail{error}: Fail{error}
    case Some{a} Some{b} Done{values}: Done{U32.or(U32.shln(a, 4n), b) <> values}
    case _ _ _: Fail{"invalid test hex"}

def hex_parse(text: String, current: Result<&2, &2, String, List<&2, U32>>) -> Result<&2, &2, String, List<&2, U32>>:
  match text current:
    case _ Fail{error}: Fail{error}
    case SNil{} Done{values}: Done{List.reverse(&2, U32, values)}
    case SCon{Chr{a}, SCon{Chr{b}, rest}} _:
      hex_parse(rest, hex_add(nibble(a), nibble(b), current))
    case _ _: Fail{"odd test hex length"}

def report(id: String, result: Result<&2, &2, String, H.Digest>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print(id ++ "|error|" ++ error)
    case Done{+digest}: IO.print(id ++ "|digest|" ++ H.Digest.hex(digest) ++ "|" ++ byte_list(H.Digest.bytes(digest)))

def report_hex(id: String, limit: Nat, parsed: Result<&2, &2, String, List<&2, U32>>) -> IO(Unit):
  match parsed:
    case Fail{error}: IO.die(Unit, 2, error)
    case Done{bytes}: report(id, H.digest(limit, bytes))

def file_tail(id: String, limit: Nat, bytes: List<&2, U32>, read: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  (file, result) = read
  match result:
    case Done{Nil{}}:
      do IO<Unit>:
        File.close(file)
        report(id, H.digest(limit, bytes))
    case _:
      do IO<Unit>:
        File.close(file)
        IO.die(Unit, 2, "test file read failed or exceeds 4MiB")

def file_read(id: String, limit: Nat, read: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  (file, result) = read
  match result:
    case Fail{error}:
      do IO<Unit>:
        File.close(file)
        IO.die(Unit, 2, "test file read failed")
    case Done{bytes}:
      do IO<Unit>:
        tail : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, 1)
        file_tail(id, limit, bytes, tail)

def report_file(id: String, limit: Nat, path: String) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File, File.open(path, "r"))
    read : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, 4194304)
    file_read(id, limit, read)

def report_repeat(id: String, limit: Nat, count: Maybe<&2, Nat>, byte: U32) -> IO(Unit):
  match count:
    case None{}: IO.die(Unit, 2, "invalid hash repeat count")
    case Some{count}: report(id, H.digest(limit, List.replicate(U32, count, byte)))

def dispatch_limited(id: String, op: Operation, limit: Maybe<&2, Nat>, fields: List<&2, String>) -> IO(Unit):
  match op limit fields:
    case _ None{} _: IO.die(Unit, 2, "invalid hash size")
    case HashHex{} Some{limit} text <> Nil{}: report_hex(id, limit, hex_parse(text, Done{Nil{}}))
    case HashValues{} Some{limit} text <> Nil{}: report(id, H.digest(limit, decimal_values(text)))
    case HashRepeat{} Some{limit} count <> value <> Nil{}: report_repeat(id, limit, Nat.read(count), number(value))
    case HashFile{} Some{limit} path <> Nil{}: report_file(id, limit, path)
    case _ _ _: IO.die(Unit, 2, "invalid hash test protocol")

def dispatch_operation(id: String, op: Maybe<&2, Operation>, fields: List<&2, String>) -> IO(Unit):
  match op fields:
    case Some{HashHex{}} limit <> rest: dispatch_limited(id, HashHex{}, Nat.read(limit), rest)
    case Some{HashValues{}} limit <> rest: dispatch_limited(id, HashValues{}, Nat.read(limit), rest)
    case Some{HashRepeat{}} limit <> rest: dispatch_limited(id, HashRepeat{}, Nat.read(limit), rest)
    case Some{HashFile{}} limit <> rest: dispatch_limited(id, HashFile{}, Nat.read(limit), rest)
    case Some{HashLength{}} hi <> lo <> Nil{}: IO.print(id ++ "|length|" ++ byte_list(H.bit_length(number(hi), number(lo))))
    case Some{HashRotate{}} value <> shift <> Nil{}: IO.print(id ++ "|rotate|" ++ U32.show(H.rotate_right(number(value), size(shift))))
    case _ _: IO.die(Unit, 2, "invalid hash test protocol")

def dispatch(fields: List<&2, String>) -> IO(Unit):
  match fields:
    case id <> op <> rest: dispatch_operation(id, operation(op), rest)
    case _: IO.die(Unit, 2, "invalid hash test protocol")

def run_args(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{arg, rest}:
      do IO<Unit>:
        dispatch(String.split(arg, '|'))
        run_args(rest)

def drop_program(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{program, rest}: run_args(rest)

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), drop_program)
