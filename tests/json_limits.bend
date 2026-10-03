import Base
import ../src/json.bend as J

def rendered(result: Result<&2, &2, String, J.Value>) -> String:
  match result:
    case Fail{message}: "error\t" ++ message
    case Done{value}: "ok\t" ++ J.encode(value)

def failure_is(result: Result<&2, &2, String, J.Value>, expected: String) -> Bool:
  match result:
    case Fail{message}: String.eq(message, expected)
    case Done{value}: False{}

def is_null(result: Result<&2, &2, String, J.Value>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{J.JNull{}}: True{}
    case Done{value}: False{}

# Finite parser fixtures. They do not assert general JSON conformance.
def fixtures() -> Bool:
  is_null(J.parse_with("null", J.Limits{4n, 0})) &&
  failure_is(J.parse_with("null", J.Limits{3n, 64}), "JSON input exceeds 3 code points") &&
  failure_is(J.parse_with("[]", J.Limits{2n, 0}), "nesting limit exceeded at offset 0") &&
  failure_is(J.parse_with("[[]]", J.Limits{4n, 1}), "nesting limit exceeded at offset 1")

def native_fixtures() -> Bool:
  fixtures() &&
  failure_is(J.parse_with("null", J.Limits{Nat.add(4294967295n, 1n), 64}), "JSON max_codepoints exceeds supported limit 4294967295")

law finite_limits:
  {fixtures() == True{} : Bool}

def finite_limits():
  {==}

def batch(+limits: J.Limits, inputs: List<String>) -> IO(Unit):
  match inputs:
    case Nil{}: IO.pure(Unit, Unit{})
    case input <> rest:
      do IO<Unit>:
        IO.print(rendered(J.parse_with(input, limits)))
        batch(limits, rest)

def read_result(limits: J.Limits, pair: File & Result<&1, &1, U32 & String, String>) -> IO(Unit):
  (file, content) = pair
  do IO<Unit>:
    text : String <- IO.try(String, IO.pure(Result<&1, &1, U32 & String, String>, content))
    File.close(file)
    IO.print(rendered(J.parse_with(text, limits)))

def read_gate(limits: J.Limits, file: File, size: U32, supported: Bool) -> IO(Unit):
  match supported:
    case False{}:
      do IO<Unit>:
        File.close(file)
        IO.die(Unit, 2, "test file exceeds 32 MiB")
    case True{}:
      do IO<Unit>:
        pair : File & Result<&1, &1, U32 & String, String> <- File.read(file, size)
        read_result(limits, pair)

def read_size(limits: J.Limits, pair: File & Result<&1, &1, U32 & String, U32>) -> IO(Unit):
  (file, measured) = pair
  do IO<Unit>:
    +size : U32 <- IO.try(U32, IO.pure(Result<&1, &1, U32 & String, U32>, measured))
    read_gate(limits, file, size, U32.is_le(size, 33554432))

def file_input(limits: J.Limits, path: String) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File, File.open(path, "r"))
    pair : File & Result<&1, &1, U32 & String, U32> <- File.size(file)
    read_size(limits, pair)

def repeat(n: Nat, +c: Char) -> String:
  match n:
    case 0n: SNil{}
    case 1n+p: SCon{c, repeat(p, c)}

def nested(n: Nat, value: J.Value) -> J.Value:
  match n:
    case 0n: value
    case 1n+p: nested(p, J.JArray{value <> Nil{}})

def numbers(n: Nat) -> List<&2, J.Value>:
  match n:
    case 0n: Nil{}
    case 1n+p: J.JNumber{"-0.00E+400"} <> numbers(p)

def members(n: Nat) -> List<&2, J.Member>:
  match n:
    case 0n: Nil{}
    case 1n+ +p: J.JMember{"key-" ++ Nat.show(p), J.JNumber{"9007199254740993"}} <> members(p)

def generated(mode: String, n: Nat) -> J.Value:
  match mode:
    case "ast-ascii": J.JString{repeat(n, Chr{97})}
    case "ast-string": J.JString{repeat(n, Chr{128512})}
    case "ast-escaped": J.JString{repeat(n, Chr{10})}
    case "ast-array": J.JArray{numbers(n)}
    case "ast-object": J.JObject{members(n)}
    case _: nested(n, J.JNull{})

def generate_gate(mode: String, n: Nat, supported: Bool) -> IO(Unit):
  match supported:
    case False{}: IO.die(Unit, 2, "test AST count exceeds 4 Mi")
    case True{}: IO.print(J.encode(generated(mode, n)))

def generate(mode: String, count: Maybe<&2, Nat>) -> IO(Unit):
  match count:
    case None{}: IO.die(Unit, 2, "invalid AST count")
    case Some{+n}: generate_gate(mode, n, Nat.is_le(n, 4194304n))

def configured(+limits: J.Limits, args: List<String>) -> IO(Unit):
  match args:
    case "file" <> path <> Nil{}: file_input(limits, path)
    case "batch" <> inputs: batch(limits, inputs)
    case "text" <> text <> Nil{}: IO.print(rendered(J.parse_with(text, limits)))
    case _: IO.die(Unit, 2, "expected file PATH, batch TEXT..., or text TEXT")

def depth(cap: Nat, found: Maybe<&2, U32>, args: List<String>) -> IO(Unit):
  match found:
    case None{}: IO.die(Unit, 2, "invalid depth cap")
    case Some{n}: configured(J.Limits{cap, n}, args)

def length(found: Maybe<&2, Nat>, depth_text: String, args: List<String>) -> IO(Unit):
  match found:
    case None{}: IO.die(Unit, 2, "invalid input cap")
    case Some{n}: depth(n, U32.read(depth_text), args)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.print(J.choose(String, "limits-fixtures\tpass", "limits-fixtures\tFAIL", native_fixtures()))
    case "generate" <> mode <> count <> Nil{}: generate(mode, Nat.read(count))
    case cap <> maximum_depth <> rest: length(Nat.read(cap), maximum_depth, rest)
    case _: IO.die(Unit, 2, "usage: json-limits MAX_CODEPOINTS MAX_DEPTH MODE ...")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(List.tail(&1, String, args))
