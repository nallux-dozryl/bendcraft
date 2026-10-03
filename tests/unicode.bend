import Base
import ../src/unicode.bend as Unicode

# These general laws concern empty inputs and budget transitions. The fixture
# equalities below are finite regression claims, not a universal UTF-8 theorem.
law decode_empty:
  for limit: Nat
  {Unicode.decode(limit, []) == Done{SNil{}} : Result<&2, &2, String, String>}

def decode_empty(limit):
  {==}

law encode_empty:
  for limit: Nat
  {Unicode.encode(limit, SNil{}) == Done{[]} : Result<&2, &2, String, List<&2, U32>>}

def encode_empty(limit):
  {==}

law decoder_no_room:
  for code: U32
  for reversed: String
  {Unicode.decoded_put(0n, code, reversed) == Fail{"UTF-8 scalar limit exceeded"} : Result<&2, &2, String, Unicode.Decoder>}

def decoder_no_room(code, reversed):
  {==}

law decoder_one_scalar_consumes_one:
  for remaining: Nat
  for code: U32
  for reversed: String
  {Unicode.decoded_put(1n+remaining, code, reversed) == Done{Unicode.Decoder{0, 0, 0, remaining, SCon{Chr{code}, reversed}}} : Result<&2, &2, String, Unicode.Decoder>}

def decoder_one_scalar_consumes_one(remaining, code, reversed):
  {==}

law encoder_no_room:
  for byte: U32
  for rest: List<&2, U32>
  for reversed: List<&2, U32>
  {Unicode.encoded_put(byte <> rest, 0n, reversed) == Fail{"UTF-8 byte limit exceeded"} : Result<&2, &2, String, Unicode.Encoder>}

def encoder_no_room(byte, rest, reversed):
  {==}

law encoder_one_byte_consumes_one:
  for byte: U32
  for rest: List<&2, U32>
  for remaining: Nat
  for reversed: List<&2, U32>
  {Unicode.encoded_put(byte <> rest, 1n+remaining, reversed) == Unicode.encoded_put(rest, remaining, byte <> reversed) : Result<&2, &2, String, Unicode.Encoder>}

def encoder_one_byte_consumes_one(byte, rest, remaining, reversed):
  {==}

law ordinary_nul_encode:
  {Unicode.encode(1n, SCon{Chr{0}, SNil{}}) == Done{[0]} : Result<&2, &2, String, List<&2, U32>>}

def ordinary_nul_encode():
  {==}

law ordinary_nul_decode:
  {Unicode.decode(1n, [0]) == Done{SCon{Chr{0}, SNil{}}} : Result<&2, &2, String, String>}

def ordinary_nul_decode():
  {==}

law strict_modified_nul_rejected:
  {Unicode.decode(1n, [192, 128]) == Fail{"invalid UTF-8 leading byte"} : Result<&2, &2, String, String>}

def strict_modified_nul_rejected():
  {==}

law strict_surrogate_encode_rejected:
  {Unicode.encode(4n, SCon{Chr{55296}, SNil{}}) == Fail{"invalid Unicode scalar in String"} : Result<&2, &2, String, List<&2, U32>>}

def strict_surrogate_encode_rejected():
  {==}

law strict_surrogate_decode_rejected:
  {Unicode.decode(1n, [237, 160, 128]) == Fail{"invalid UTF-8 scalar or overlong encoding"} : Result<&2, &2, String, String>}

def strict_surrogate_decode_rejected():
  {==}

law strict_out_of_range_encode_rejected:
  {Unicode.encode(4n, SCon{Chr{1114112}, SNil{}}) == Fail{"invalid Unicode scalar in String"} : Result<&2, &2, String, List<&2, U32>>}

def strict_out_of_range_encode_rejected():
  {==}

law strict_out_of_range_decode_rejected:
  {Unicode.decode(1n, [244, 144, 128, 128]) == Fail{"invalid UTF-8 scalar or overlong encoding"} : Result<&2, &2, String, String>}

def strict_out_of_range_decode_rejected():
  {==}

law incomplete_decode_rejected:
  {Unicode.decode(1n, [240, 144, 128]) == Fail{"incomplete UTF-8 sequence"} : Result<&2, &2, String, String>}

def incomplete_decode_rejected():
  {==}

law non_byte_rejected:
  {Unicode.decode(1n, [256]) == Fail{"input byte exceeds 255"} : Result<&2, &2, String, String>}

def non_byte_rejected():
  {==}

law supplementary_boundary_roundtrip_fixture:
  {Unicode.decode(2n, [240, 144, 128, 128, 244, 143, 191, 191]) == Done{SCon{Chr{65536}, SCon{Chr{1114111}, SNil{}}}} : Result<&2, &2, String, String>}

def supplementary_boundary_roundtrip_fixture():
  {==}

law noncharacter_fixture:
  {Unicode.encode(6n, SCon{Chr{65534}, SCon{Chr{65535}, SNil{}}}) == Done{[239, 191, 190, 239, 191, 191]} : Result<&2, &2, String, List<&2, U32>>}

def noncharacter_fixture():
  {==}

def parsed_number(found: Maybe<&2, U32>, acc: List<&2, U32>) -> Result<&2, &2, String, List<&2, U32>>:
  match found:
    case None{}: Fail{"invalid native fixture number"}
    case Some{value}: Done{value <> acc}

def parse_numbers(tokens: List<&2, String>, result: Result<&2, &2, String, List<&2, U32>>) -> Result<&2, &2, String, List<&2, U32>>:
  match tokens result:
    case _ Fail{message}: Fail{message}
    case Nil{} Done{acc}: Done{acc}
    case "" <> rest Done{acc}: parse_numbers(rest, Done{acc})
    case token <> rest Done{acc}: parse_numbers(rest, parsed_number(U32.read(token), acc))

# Chunks are concatenated before the complete-input decode API is called.
# Chunk tests establish byte-list assembly independence, not streaming behavior.
def parse_chunks(chunks: List<&2, String>, result: Result<&2, &2, String, List<&2, U32>>) -> Result<&2, &2, String, List<&2, U32>>:
  match chunks result:
    case _ Fail{message}: Fail{message}
    case Nil{} Done{acc}: Done{List.reverse(&2, U32, acc)}
    case chunk <> rest Done{acc}: parse_chunks(rest, parse_numbers(String.split(chunk, ','), Done{acc}))

def forge_text(values: List<&2, U32>) -> String:
  match values:
    case Nil{}: SNil{}
    case code <> rest: SCon{Chr{code}, forge_text(rest)}

def scalar_values(text: String) -> List<&2, U32>:
  match text:
    case SNil{}: Nil{}
    case SCon{Chr{code}, rest}: code <> scalar_values(rest)

def values_json(values: List<&2, U32>, acc: List<&2, String>) -> String:
  match values:
    case Nil{}: "[" ++ String.join(List.reverse(&2, String, acc), ",") ++ "]"
    case value <> rest: values_json(rest, U32.show(value) <> acc)

def failed_json(message: String) -> String:
  "{\"ok\":false,\"error\":\"" ++ message ++ "\"}"

def values_summary(values: List<&2, U32>, count: U32, hash: U32) -> String:
  match values:
    case Nil{}: "{\"ok\":true,\"length\":" ++ U32.show(count) ++ ",\"fnv1a32\":" ++ U32.show(hash) ++ "}"
    case value <> rest: values_summary(rest, U32.add(count, 1), U32.mul(U32.xor(hash, value), 16777619))

def text_summary(text: String, count: U32, hash: U32) -> String:
  match text:
    case SNil{}: "{\"ok\":true,\"length\":" ++ U32.show(count) ++ ",\"fnv1a32\":" ++ U32.show(hash) ++ "}"
    case SCon{Chr{code}, rest}: text_summary(rest, U32.add(count, 1), U32.mul(U32.xor(hash, code), 16777619))

def decoded_json(result: Result<&2, &2, String, String>, summary: Bool) -> String:
  match result summary:
    case Fail{message} _: failed_json(message)
    case Done{text} True{}: text_summary(text, 0, 2166136261)
    case Done{text} False{}: "{\"ok\":true,\"values\":" ++ values_json(scalar_values(text), Nil{}) ++ "}"

def encoded_json(result: Result<&2, &2, String, List<&2, U32>>, summary: Bool) -> String:
  match result summary:
    case Fail{message} _: failed_json(message)
    case Done{values} True{}: values_summary(values, 0, 2166136261)
    case Done{values} False{}: "{\"ok\":true,\"values\":" ++ values_json(values, Nil{}) ++ "}"

def run_values(mode: String, limit: Nat, values: Result<&2, &2, String, List<&2, U32>>) -> String:
  match mode values:
    case _ Fail{message}: failed_json(message)
    case "d" Done{bytes}: decoded_json(Unicode.decode(limit, bytes), False{})
    case "e" Done{scalars}: encoded_json(Unicode.encode(limit, forge_text(scalars)), False{})
    case _ _: failed_json("invalid native fixture mode")

def repeated(count: Nat, +code: U32, acc: String) -> String:
  match count:
    case 0n: acc
    case 1n+remaining: repeated(remaining, code, SCon{Chr{code}, acc})

def ranged(count: Nat, +code: U32, acc: String) -> String:
  match count:
    case 0n: String.reverse(acc)
    case 1n+remaining: ranged(remaining, U32.add(code, 1), SCon{Chr{code}, acc})

def run_constructed(mode: String, limit: Nat, code: U32, count: Nat) -> String:
  match mode:
    case "erepeat": encoded_json(Unicode.encode(limit, repeated(count, code, SNil{})), True{})
    case "erange": encoded_json(Unicode.encode(limit, ranged(count, code, SNil{})), True{})
    case _: failed_json("invalid native fixture mode")

def run_file_values(result: Result<&1, &1, U32 & String, List<&2, U32>>, limit: Nat) -> String:
  match result:
    case Fail{error}: failed_json("native fixture read failed")
    case Done{bytes}: decoded_json(Unicode.decode(limit, bytes), True{})

def run_file_read(value: File & Result<&1, &1, U32 & String, List<&2, U32>>, limit: Nat) -> IO(Unit):
  (file, bytes) = value
  do IO<Unit>:
    File.close(file)
    IO.print(run_file_values(bytes, limit))

def run_file(limit: Nat, path: String) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File, File.open(path, "r"))
    value : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, 16777216)
    run_file_read(value, limit)

def run_spec(fields: List<&2, String>) -> IO(Unit):
  match fields:
    case "dfile" <> limit <> path <> Nil{}:
      run_file(Maybe.default(&2, Nat, Nat.read(limit), 0n), path)
    case mode <> limit <> payload <> Nil{}:
      IO.print(run_values(mode, Maybe.default(&2, Nat, Nat.read(limit), 0n), parse_chunks(String.split(payload, ';'), Done{Nil{}})))
    case mode <> limit <> code <> count <> Nil{}:
      IO.print(run_constructed(mode, Maybe.default(&2, Nat, Nat.read(limit), 0n), Maybe.default(&2, U32, U32.read(code), 0), Maybe.default(&2, Nat, Nat.read(count), 0n)))
    case _: IO.print(failed_json("invalid native fixture specification"))

def batch(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case spec <> rest:
      do IO<Unit>:
        run_spec(String.split(spec, '|'))
        batch(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    batch(List.tail(&1, String, args))
