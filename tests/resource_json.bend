import Base
import ../src/json.bend as J
import ../src/resource_json.bend as R

def number_is(result: Result<&2, &2, String, J.Value>, expected: String) -> Bool:
  match result:
    case Done{J.JNumber{raw}}: String.eq(raw, expected)
    case _: False{}

def string_is(result: Result<&2, &2, String, J.Value>, expected: String) -> Bool:
  match result:
    case Done{J.JString{text}}: String.eq(text, expected)
    case _: False{}

def empty_object(result: Result<&2, &2, String, J.Value>) -> Bool:
  match result:
    case Done{J.JObject{Nil{}}}: True{}
    case _: False{}

def rejected(result: Result<&2, &2, String, J.Value>) -> Bool:
  match result:
    case Fail{message}: True{}
    case Done{value}: False{}

def duplicate_fixture(result: Result<&2, &2, String, J.Value>) -> Bool:
  match result:
    case Done{J.JObject{J.JMember{"a", J.JNumber{"3"}} <> J.JMember{"b", J.JNumber{"2"}} <> Nil{}}}: True{}
    case _: False{}

# Finite executable fixture laws; no theorem of general Gson correspondence.
law checked_prefix:
  {empty_object(R.parse("{} {bad")) == True{} : Bool}

def checked_prefix():
  {==}

law checked_duplicate:
  {duplicate_fixture(R.parse("{\"a\":1,\"b\":2,\"a\":3}")) == True{} : Bool}

def checked_duplicate():
  {==}

law checked_surrogate:
  {string_is(R.parse("\"\\ud800\""), SCon{Chr{55296}, SNil{}}) == True{} : Bool}

def checked_surrogate():
  {==}

law checked_pair:
  {string_is(R.parse("\"\\ud83d\\ude00\""), "😀") == True{} : Bool}

def checked_pair():
  {==}

law checked_delimiter:
  {number_is(R.parse(SCon{Chr{49}, SCon{Chr{12}, SCon{Chr{120}, SNil{}}}}), "1") == True{} : Bool}

def checked_delimiter():
  {==}

law checked_invalid_token:
  {rejected(R.parse("1/x")) == True{} : Bool}

def checked_invalid_token():
  {==}

law checked_bom:
  {empty_object(R.parse(SCon{Chr{65279}, "{}"})) == True{} : Bool}

def checked_bom():
  {==}

# Native harness. Fixtures contain little-endian U32 character values, allowing
# NUL and lone UTF-16 units without relying on a host UTF-8 argument decoder.
def fixture_text(bytes: List<&2, U32>, reversed: String) -> Result<&2, &2, String, String>:
  match bytes:
    case Nil{}: Done{String.reverse(reversed)}
    case a <> b <> c <> d <> rest:
      code = U32.or(a, U32.or(U32.shln(b, 8n), U32.or(U32.shln(c, 16n), U32.shln(d, 24n))))
      fixture_text(rest, SCon{Chr{code}, reversed})
    case _: Fail{"invalid U32 fixture byte count"}

# FNV is over UTF-16 units, not UTF-8 bytes. Full hexadecimal units are published
# for strings <=2048 units; larger stress strings publish length and FNV only.
def utf16_units(text: String, +acc: List<&2, U32>) -> List<&2, U32>:
  match text:
    case SNil{}: List.reverse(&2, U32, acc)
    case SCon{Chr{+c}, rest}:
      utf16_units(rest, R.choose(List<&2, U32>,
        U32.add(56320, U32.and(U32.sub(c, 65536), 1023)) <> U32.add(55296, U32.shrn(U32.sub(c, 65536), 10n)) <> acc,
        c <> acc, U32.is_gt(c, 65535)))

def hex_digit(+n: U32) -> Char:
  R.choose(Char, Chr{U32.add(n, 48)}, Chr{U32.add(n, 87)}, U32.is_lt(n, 10))

def unit_hex(+unit: U32) -> String:
  Char.show(hex_digit(U32.and(U32.shrn(unit, 12n), 15))) ++
  Char.show(hex_digit(U32.and(U32.shrn(unit, 8n), 15))) ++
  Char.show(hex_digit(U32.and(U32.shrn(unit, 4n), 15))) ++
  Char.show(hex_digit(U32.and(unit, 15)))

def units_hex(units: List<&2, U32>) -> String:
  match units:
    case Nil{}: ""
    case unit <> rest: unit_hex(unit) ++ units_hex(rest)

def units_hash(units: List<&2, U32>, hash: U32) -> U32:
  match units:
    case Nil{}: hash
    case unit <> rest: units_hash(rest, U32.mul(U32.xor(hash, unit), 16777619))

def text_units(+units: List<&2, U32>, +size: Nat, full: Bool) -> String:
  match full:
    case True{}: "{\"utf16_hex\":\"" ++ units_hex(units) ++ "\"}"
    case False{}: "{\"utf16_length\":" ++ Nat.show(size) ++ ",\"utf16_fnv1a32\":" ++ U32.show(units_hash(units, 2166136261)) ++ "}"

def text_projection_go(+units: List<&2, U32>) -> String:
  +size = List.length(&2, U32, units)
  text_units(units, size, Nat.is_le(size, 2048n))

def text_projection(text: String) -> String:
  text_projection_go(utf16_units(text, Nil{}))

# This observer is native-only. Its generated-container recursion is excluded
# from the verbatim parser kernel projection, as is the unrelated J serializer.
def tree_go(value: J.Value, continuation: Bool) -> String:
  match value:
    case J.JNull{}: "{\"kind\":\"null\"}"
    case J.JBool{True{}}: "{\"kind\":\"boolean\",\"value\":true}"
    case J.JBool{False{}}: "{\"kind\":\"boolean\",\"value\":false}"
    case J.JNumber{raw}: "{\"kind\":\"number\",\"lexeme\":" ++ J.quote(raw) ++ "}"
    case J.JString{text}: "{\"kind\":\"string\",\"text\":" ++ text_projection(text) ++ "}"
    case J.JArray{Nil{}}: R.choose(String, "]}", "{\"kind\":\"array\",\"elements\":[]}", continuation)
    case J.JArray{h <> rest}:
      R.choose(String, ",", "{\"kind\":\"array\",\"elements\":[", continuation) ++ tree_go(h, False{}) ++ tree_go(J.JArray{rest}, True{})
    case J.JObject{Nil{}}: R.choose(String, "]}", "{\"kind\":\"object\",\"members\":[]}", continuation)
    case J.JObject{J.JMember{key, value} <> rest}:
      R.choose(String, ",{", "{\"kind\":\"object\",\"members\":[{", continuation) ++ "\"key\":" ++ text_projection(key) ++ ",\"value\":" ++ tree_go(value, False{}) ++ "}" ++ tree_go(J.JObject{rest}, True{})

def report(result: Result<&2, &2, String, J.Value>) -> String:
  match result:
    case Fail{message}: "{\"ok\":false,\"error\":" ++ J.quote(message) ++ "}"
    case Done{value}: "{\"ok\":true,\"tree\":" ++ tree_go(value, False{}) ++ "}"

def run_fixture(result: Result<&2, &2, String, String>, limits: J.Limits) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit, 2, message)
    case Done{text}: IO.print(report(R.parse_with(text, limits)))

def loaded(limits: J.Limits, result: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  (file, status) = result
  do IO<Unit>:
    File.close(file)
    bytes : List<&2, U32> <- IO.pass(List<&2, U32>, status)
    run_fixture(fixture_text(bytes, SNil{}), limits)

def read_fixture(path: String, limits: J.Limits) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File, File.open(path, "r"))
    result : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, 67108864)
    loaded(limits, result)

def configuration(path: String, max_codepoints: Maybe<&2, Nat>, max_depth: Maybe<&2, U32>) -> IO(Unit):
  match max_codepoints max_depth:
    case Some{a} Some{b}: read_fixture(path, J.Limits{a, b})
    case _ _: IO.die(Unit, 2, "invalid fixture limits")

def batch(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case path <> codepoints <> depth <> rest:
      do IO<Unit>:
        configuration(path, Nat.read(codepoints), U32.read(depth))
        batch(rest)
    case _: IO.die(Unit, 2, "expected PATH MAX_CODEPOINTS MAX_DEPTH triples")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    batch(List.tail(&1, String, args))
