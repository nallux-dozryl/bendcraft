import Base
import ../src/json.bend as J

# Serializer fixtures construct valid ASTs directly. No parser envelope applies.
def deep_value(depth: Nat) -> J.Value:
  match depth:
    case 0n: J.JNumber{"9007199254740993"}
    case 1n+rest: J.JArray{deep_value(rest) <> Nil{}}

def wide_values(count: Nat) -> List<&2, J.Value>:
  match count:
    case 0n: Nil{}
    case 1n+rest: J.JNull{} <> wide_values(rest)

def wide_members(count: Nat) -> List<&2, J.Member>:
  match count:
    case 0n: Nil{}
    case 1n+ +rest:
      J.JMember{"k" ++ Nat.show(rest), J.JNumber{"-0.00E+400"}} <> wide_members(rest)

def long_text(count: Nat) -> String:
  match count:
    case 0n: SNil{}
    case 1n+rest: SCon{Chr{128512}, long_text(rest)}

def mixed() -> J.Value:
  J.JObject{J.JMember{"z", J.JArray{J.JNull{} <> J.JArray{Nil{}} <> J.JBool{False{}} <> Nil{}}} <> J.JMember{"q\"\\", J.JString{SCon{Chr{0}, "\n😀"}}} <> J.JMember{"n", J.JNumber{"-0.00E+400"}} <> Nil{}}

# Finite output equality only; it is not a general serializer theorem.
law exact_mixed_fixture:
  {J.encode(mixed()) == "{\"z\":[null,[],false],\"q\\\"\\\\\":\"\\u0000\\n😀\",\"n\":-0.00E+400}" : String}

def exact_mixed_fixture():
  {==}

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(J.encode(mixed()))
    IO.print(J.encode(deep_value(256n)))
    IO.print(J.encode(J.JArray{wide_values(20000n)}))
    IO.print(J.encode(J.JObject{wide_members(4000n)}))
    IO.print(J.encode(J.JString{long_text(20000n)}))
