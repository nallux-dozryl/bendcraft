import Base
import ../src/json.bend as J

def equal_parse(result: Result<&2, &2, String, J.Value>, expected: String) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{value}: String.eq(J.encode(value), expected)

def equal(text: String, expected: String) -> Bool:
  equal_parse(J.parse(text), expected)

def rejected(result: Result<&2, &2, String, J.Value>) -> Bool:
  match result:
    case Fail{message}: True{}
    case Done{value}: False{}

def eq_u32(result: Maybe<&2, U32>, expected: U32) -> Bool:
  match result:
    case None{}: False{}
    case Some{n}: U32.is_eq(n, expected)

def regressions() -> Bool:
  equal(" \t\r\n{\"a\":[null,true,false,-12.50e+3],\"b\":{}} ", "{\"a\":[null,true,false,-12.50e+3],\"b\":{}}") &&
  equal("\"\\u0041\\u00e9\\u20ac\\ud83d\\ude00\"", "\"Aé€😀\"") &&
  equal("\"\\b\\f\\n\\r\\t\\u0000\\\\\\\"\\/\"", "\"\\b\\f\\n\\r\\t\\u0000\\\\\\\"/\"") &&
  rejected(J.parse("{\"a\":1,\"\\u0061\":2}")) &&
  rejected(J.parse("[1,]")) && rejected(J.parse("{\"a\":0,}")) &&
  rejected(J.parse("00")) && rejected(J.parse("1.")) && rejected(J.parse("1e+")) &&
  rejected(J.parse("\"\\uD800\"")) && rejected(J.parse("\"\\uDC00\"")) &&
  rejected(J.parse("\"\\uD800\\u0041\"")) &&
  rejected(J.parse(SCon{Chr{34}, SCon{Chr{0}, SCon{Chr{34}, SNil{}}}})) &&
  rejected(J.parse(SCon{Chr{34}, SCon{Chr{55296}, SCon{Chr{34}, SNil{}}}})) &&
  rejected(J.parse(SCon{Chr{34}, SCon{Chr{1114112}, SCon{Chr{34}, SNil{}}}})) &&
  String.eq(J.encode(J.JString{SCon{Chr{0}, SNil{}}}), "\"\\u0000\"") &&
  eq_u32(J.as_u32(J.JNumber{"4294967295"}), 4294967295) &&
  eq_u32(J.as_u32(J.JNumber{"0"}), 0) &&
  Maybe.is_none(&2, U32, J.as_u32(J.JNumber{"4294967296"})) &&
  Maybe.is_none(&2, U32, J.as_u32(J.JNumber{"-0"})) &&
  Maybe.is_none(&2, U32, J.as_u32(J.JNumber{"1.0"})) &&
  Maybe.is_none(&2, U32, J.as_u32(J.JNumber{"01"}))

# These are finite fixture equalities, not a general JSON correctness theorem.
def checker_fixtures() -> Bool:
  equal("null", "null") && equal("[true]", "[true]") &&
  rejected(J.parse("1e")) && equal("\"\\u0041\"", "\"A\"")

law checked_fixtures:
  {checker_fixtures() == True{} : Bool}

def checked_fixtures():
  {==}

def report_u32(result: Maybe<&2, U32>) -> String:
  match result:
    case None{}: "none"
    case Some{n}: "u32\t" ++ U32.show(n)

def report_string(result: Maybe<&2, String>) -> String:
  match result:
    case None{}: "none"
    case Some{text}: "string\t" ++ J.quote(text)

def report_member(result: Maybe<&2, J.Value>) -> String:
  match result:
    case None{}: "none"
    case Some{value}: "member\t" ++ J.encode(value)

def report(result: Result<&2, &2, String, J.Value>, mode: String, key: String) -> String:
  match result:
    case Fail{message}: "error\t" ++ message
    case Done{value}:
      match mode:
        case "u32": report_u32(J.as_u32(value))
        case "string": report_string(J.as_string(value))
        case "member": report_member(J.member(value, key))
        case _: "ok\t" ++ J.encode(value)

def batch(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case +mode <> +text <> key <> rest:
      do IO<Unit>:
        IO.print(J.choose(String, "ok\t" ++ J.encode(J.JString{text}), report(J.parse(text), mode, key), String.eq(mode, "quote")))
        batch(rest)
    case _: IO.die(Unit, 2, "batch expects MODE TEXT KEY triples")

def dispatch_args(args: List<String>) -> IO(Unit):
  match args:
    case "batch" <> rest: batch(rest)
    case Nil{}:
      IO.print(J.choose(String, "regressions\tpass", "regressions\tFAIL", regressions()))
    case +mode <> +text <> key <> Nil{}:
      IO.print(report(J.parse(text), mode, key))
    case +mode <> +text <> Nil{}:
      IO.print(J.choose(String, "ok\t" ++ J.encode(J.JString{text}), report(J.parse(text), mode, ""), String.eq(mode, "quote")))
    case _: IO.die(Unit, 2, "usage: json-tests [parse|u32|string|quote TEXT] or [member TEXT KEY]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    dispatch_args(List.tail(&1, String, args))
