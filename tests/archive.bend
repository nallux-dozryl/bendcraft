import Base
import ../src/archive.bend as A
import ../src/compression.bend as C

def empty_zip() -> List<&2, U32>:
  [80, 75, 5, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

law empty_end:
  {A.end_record(22, empty_zip(), A.default_limits()) == Done{A.End{22, 0, 0, 0, 0, 0, 0, 0}} : Result<&2, &2, A.Error, A.End>}

def empty_end():
  {==}

law crc_fixture:
  {C.crc32([49, 50, 51, 52, 53, 54, 55, 56, 57]) == 3421780262 : U32}

def crc_fixture():
  {==}

law empty_equality:
  for bytes: List<&2, U32>
  {A.bytes_equal([], bytes) == List.is_empty(&2, U32, bytes) : Bool}

def empty_equality(bytes):
  match bytes:
    case Nil{}: {==}
    case head <> tail: {==}

def empty_end_ok(result: Result<&2, &2, A.Error, A.End>) -> Bool:
  match result:
    case Done{A.End{22, 0, 0, 0, 0, 0, 0, 0}}: True{}
    case _: False{}

def invalid_byte_ok(result: Result<&2, &2, A.Error, U32>) -> Bool:
  match result:
    case Fail{A.Error{"InvalidByte", 0, _}}: True{}
    case _: False{}

def fixture_ok() -> Bool:
  empty_end_ok(A.end_record(22, empty_zip(), A.default_limits())) &&
    U32.is_eq(C.crc32([49, 50, 51, 52, 53, 54, 55, 56, 57]), 3421780262) &&
    invalid_byte_ok(A.byte_count([256], 1, 0))

def units(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{code}, tail}: U32.show(code) ++ "," ++ units(tail)

def nibble(+value: U32) -> Char:
  A.choose(Char, Chr{U32.add(value, 48)}, Chr{U32.add(value, 87)}, U32.is_lt(value, 10))

def hex(bytes: List<&2, U32>) -> String:
  match bytes:
    case Nil{}: ""
    case +byte <> rest: SCon{nibble(U32.shrn(byte, 4n)), SCon{nibble(U32.and(byte, 15)), hex(rest)}}

def error_line(error: A.Error) -> String:
  A.Error{code, offset, message} = error
  "E\t" ++ code ++ "\t" ++ U32.show(offset) ++ "\t" ++ units(message)

def payload_line(result: Result<&2, &2, A.Error, List<&2, U32>>) -> String:
  match result:
    case Fail{error}: error_line(error)
    case Done{bytes}: "D\t" ++ hex(bytes)

def print_entry(entry: A.Entry) -> IO(Unit):
  A.Entry{ordinal, name, raw, needed, flags, method, crc, compressed, size, offset, ceiling} = entry
  IO.print("N\t" ++ U32.show(ordinal) ++ "\t" ++ units(name) ++ "\t" ++ U32.show(method) ++ "\t" ++ U32.show(crc) ++ "\t" ++ U32.show(compressed) ++ "\t" ++ U32.show(size) ++ "\t" ++ U32.show(offset) ++ "\t" ++ U32.show(ceiling) ++ "\t" ++ U32.show(flags))

def print_entries(entries: List<&2, A.Entry>) -> IO(Unit):
  match entries:
    case Nil{}: IO.pure(Unit, Unit{})
    case entry <> rest:
      do IO<Unit>:
        print_entry(entry)
        print_entries(rest)

def print_directory(directory: A.Directory) -> IO(Unit):
  A.Directory{end, entries, names} = directory
  print_entries(entries)

def indexed(result: A.Archive & A.Directory) -> IO(Unit):
  (archive, directory) = result
  do IO<Unit>:
    print_directory(directory)
    A.Archive.close(archive)

def read_report(result: A.Archive & Result<&2, &2, A.Error, List<&2, U32>>) -> IO(Unit):
  (archive, status) = result
  do IO<Unit>:
    IO.print(payload_line(status))
    A.Archive.close(archive)

def ordinal_read(archive: A.Archive, ordinal: Maybe<&2, U32>) -> IO(Unit):
  match ordinal:
    case None{}:
      do IO<Unit>:
        A.Archive.close(archive)
        IO.die(Unit, 2, "test ordinal must be unsigned integer")
    case Some{value}:
      do IO<Unit>:
        read : A.Archive & Result<&2, &2, A.Error, List<&2, U32>> <- A.Archive.read_ordinal(archive, value)
        read_report(read)

def opened(result: Result<&2, &1, A.Error, A.Archive>, mode: String, query: String) -> IO(Unit):
  match result:
    case Fail{error}: IO.print(error_line(error))
    case Done{archive}:
      match mode:
        case "index": indexed(A.Archive.directory(archive))
        case "ordinal": ordinal_read(archive, U32.read(query))
        case _:
          do IO<Unit>:
            read : A.Archive & Result<&2, &2, A.Error, List<&2, U32>> <- A.Archive.read(archive, query)
            read_report(read)

def encoding(text: String) -> A.NameEncoding:
  match text:
    case "cp437": A.CP437Fallback{}
    case _: A.UTF8Fallback{}

def limits(profile: String) -> A.Limits:
  match profile:
    case "tiny-file": A.Limits{128, 16777216, 65534, 4096, 33554432, 33554432}
    case "tiny-index": A.Limits{536870912, 1, 65534, 4096, 33554432, 33554432}
    case "tiny-entries": A.Limits{536870912, 16777216, 1, 4096, 33554432, 33554432}
    case "tiny-name": A.Limits{536870912, 16777216, 65534, 2, 33554432, 33554432}
    case "tiny-compressed": A.Limits{536870912, 16777216, 65534, 4096, 1, 33554432}
    case "tiny-output": A.Limits{536870912, 16777216, 65534, 4096, 33554432, 1}
    case "bad-limits": A.Limits{4294967295, 16777216, 65534, 4096, 33554432, 33554432}
    case _: A.default_limits()

def run_case(mode: String, charset: String, profile: String, path: String, query: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &1, A.Error, A.Archive> <- A.load(path, encoding(charset), limits(profile))
    opened(result, mode, query)

def batch(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case mode <> charset <> profile <> path <> query <> rest:
      do IO<Unit>:
        run_case(mode, charset, profile, path, query)
        IO.print("END")
        batch(rest)
    case _: IO.die(Unit, 2, "archive batch expects MODE CHARSET PROFILE PATH QUERY groups")

def paired(-X: Type, -Y: Type, -R: Type, pair: X & Y, body: X -> Y -> R) -> R:
  match pair:
    case Tuple{x, y}: body(x)(y)

def read_many(queries: List<String>, archive: A.Archive) -> IO(Unit):
  match queries:
    case Nil{}: A.Archive.close(archive)
    case name <> rest:
      do IO<Unit>:
        read : A.Archive & Result<&2, &2, A.Error, List<&2, U32>> <- A.Archive.read(archive, name)
        paired(A.Archive, Result<&2, &2, A.Error, List<&2, U32>>, IO(Unit), read, archive => status => (
          do IO<Unit>:
            IO.print(payload_line(status))
            read_many(rest, archive)
        ))

def many_opened(result: Result<&2, &1, A.Error, A.Archive>, queries: List<String>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print(error_line(error))
    case Done{archive}: read_many(queries, archive)

def main_args(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.print(A.choose(String, "fixtures pass", "fixtures FAIL", fixture_ok()))
    case "batch" <> rest: batch(rest)
    case "read-many" <> charset <> profile <> path <> queries:
      do IO<Unit>:
        result : Result<&2, &1, A.Error, A.Archive> <- A.load(path, encoding(charset), limits(profile))
        many_opened(result, queries)
    case mode <> charset <> profile <> path <> query <> Nil{}: run_case(mode, charset, profile, path, query)
    case _: IO.die(Unit, 2, "usage: archive-tests MODE CHARSET PROFILE PATH QUERY")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    main_args(List.tail(&1, String, args))
