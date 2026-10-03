import Base
import ../src/nbt.bend as N

def hex_digit(+c: U32) -> U32:
  N.choose(U32, U32.sub(c, 48), N.choose(U32, U32.sub(c, 55), N.choose(U32, U32.sub(c, 87), 256, U32.is_ge(c, 97) && U32.is_le(c, 102)), U32.is_ge(c, 65) && U32.is_le(c, 70)), U32.is_ge(c, 48) && U32.is_le(c, 57))

def unhex_cons(+a: U32, +b: U32, result: Result<&2, &2, String, List<&2, U32>>) -> Result<&2, &2, String, List<&2, U32>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{bytes}:
      N.choose(Result<&2, &2, String, List<&2, U32>>, Done{U32.add(U32.mul(a, 16), b) <> bytes}, Fail{"invalid hex"}, U32.is_lt(a, 16) && U32.is_lt(b, 16))

def unhex(text: String) -> Result<&2, &2, String, List<&2, U32>>:
  match text:
    case SNil{}: Done{Nil{}}
    case SCon{Chr{a}, SCon{Chr{b}, t}}: unhex_cons(hex_digit(a), hex_digit(b), unhex(t))
    case _: Fail{"odd hex length"}

def hex_char(+n: U32) -> Char:
  N.choose(Char, Chr{U32.add(n, 48)}, Chr{U32.add(n, 87)}, U32.is_lt(n, 10))

def hex_bytes(bytes: List<&2, U32>) -> String:
  match bytes:
    case Nil{}: ""
    case +h <> t:
      Char.show(hex_char(U32.div(h, 16))) ++ Char.show(hex_char(U32.mod(h, 16))) ++ hex_bytes(t)

def encoded(result: Result<&2, &2, String, List<&2, U32>>) -> String:
  match result:
    case Fail{message}: "error\t" ++ message
    case Done{bytes}: "ok\t" ++ hex_bytes(bytes)

def decoded(result: Result<&2, &2, String, N.Root>) -> String:
  match result:
    case Fail{message}: "error\t" ++ message
    case Done{root}: encoded(N.encode(root))

def input_bytes(result: Result<&2, &2, String, List<&2, U32>>) -> String:
  match result:
    case Fail{message}: "error\t" ++ message
    case Done{bytes}: decoded(N.decode(bytes))

def roundtrip(text: String) -> String:
  input_bytes(unhex(text))

def fails_decode(result: Result<&2, &2, String, N.Root>) -> Bool:
  match result:
    case Fail{message}: True{}
    case Done{root}: False{}

def fails_encode(result: Result<&2, &2, String, List<&2, U32>>) -> Bool:
  match result:
    case Fail{message}: True{}
    case Done{bytes}: False{}

def regressions() -> Bool:
  String.eq(roundtrip("00"), "ok\t00") &&
  String.eq(roundtrip("0800000002c080"), "ok\t0800000002c080") &&
  String.eq(roundtrip("0800000003eda080"), "ok\t0800000003eda080") &&
  String.eq(roundtrip("0800000006eda0bdedb880"), "ok\t0800000006eda0bdedb880") &&
  String.eq(roundtrip("0500007fa12345"), "ok\t0500007fa12345") &&
  String.eq(roundtrip("0600008000000000000000"), "ok\t0600008000000000000000") &&
  String.eq(roundtrip("0a00000100016101010001610200"), "ok\t0a00000100016101010001610200") &&
  fails_decode(N.decode(256 <> Nil{})) &&
  fails_encode(N.encode(N.Root{N.Text{Nil{}}, N.Byte{256}})) &&
  fails_encode(N.encode(N.Root{N.Text{Nil{}}, N.Short{65536}})) &&
  fails_encode(N.encode(N.Root{N.Text{1 <> Nil{}}, N.End{}})) &&
  fails_encode(N.encode(N.Root{N.Text{Nil{}}, N.StringTag{N.Text{65536 <> Nil{}}}})) &&
  fails_encode(N.encode(N.Root{N.Text{Nil{}}, N.ByteArray{256 <> Nil{}}})) &&
  fails_encode(N.encode(N.Root{N.Text{Nil{}}, N.ListTag{1, N.Int{7} <> Nil{}}})) &&
  fails_encode(N.encode(N.Root{N.Text{Nil{}}, N.Compound{N.Member{N.Text{Nil{}}, N.End{}} <> Nil{}}})) &&
  fails_decode(N.decode_with(N.Limits{0, 512, 1048576}, 0 <> Nil{})) &&
  fails_encode(N.encode_with(N.Limits{0, 512, 1048576}, N.Root{N.Text{Nil{}}, N.End{}})) &&
  fails_decode(N.decode_with(N.Limits{8, 0, 8}, 10 <> 0 <> 0 <> 0 <> Nil{})) &&
  fails_encode(N.encode_with(N.Limits{8, 0, 8}, N.Root{N.Text{Nil{}}, N.Compound{Nil{}}})) &&
  String.eq(encoded(N.encode_with(N.Limits{4, 1, 0}, N.Root{N.Text{Nil{}}, N.Compound{Nil{}}})), "ok\t0a000000") &&
  fails_encode(N.encode_with(N.Limits{8, 1, 0}, N.Root{N.Text{Nil{}}, N.ListTag{1, N.Byte{0} <> Nil{}}}))

# Finite fixtures, not a general NBT correctness theorem.
law checked_end_fixture:
  {N.decode(0 <> Nil{}) == Done{N.Root{N.Text{Nil{}}, N.End{}}} : Result<&2, &2, String, N.Root>}

def checked_end_fixture():
  {==}

law checked_raw_float_fixture:
  {N.encode(N.Root{N.Text{Nil{}}, N.Float{2141266757}}) == Done{5 <> 0 <> 0 <> 127 <> 161 <> 35 <> 69 <> Nil{}} : Result<&2, &2, String, List<&2, U32>>}

def checked_raw_float_fixture():
  {==}

def batch(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case text <> rest:
      do IO<Unit>:
        IO.print(roundtrip(text))
        batch(rest)

def file_read(result: File & Result<&1, &1, U32 & String, String>) -> IO(Unit):
  (file, content) = result
  do IO<Unit>:
    text : String <- IO.try(String, IO.pure(Result<&1, &1, U32 & String, String>, content))
    File.close(file)
    IO.print(roundtrip(text))

def file_size(result: File & Result<&1, &1, U32 & String, U32>) -> IO(Unit):
  (file, measured) = result
  do IO<Unit>:
    size : U32 <- IO.try(U32, IO.pure(Result<&1, &1, U32 & String, U32>, measured))
    content : File & Result<&1, &1, U32 & String, String> <- File.read(file, size)
    file_read(content)

def file_input(path: String) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File, File.open(path, "r"))
    sized : File & Result<&1, &1, U32 & String, U32> <- File.size(file)
    file_size(sized)

def dispatch(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.print(N.choose(String, "regressions\tpass", "regressions\tFAIL", regressions()))
    case "batch" <> rest: batch(rest)
    case "file" <> path <> Nil{}: file_input(path)
    case text <> Nil{}: IO.print(roundtrip(text))
    case _: IO.die(Unit, 2, "usage: nbt-tests [HEX | batch HEX... | file PATH]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    dispatch(List.tail(&1, String, args))
