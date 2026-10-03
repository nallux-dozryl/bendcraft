import Base
import ../src/framing.bend as F

type Report is Data:
  Report{buffer: F.Buffer, step: String}

def final_split(buffer: F.Buffer, lines: List<&2, String>) -> Bool:
  match buffer lines:
    case F.Buffer{Nil{}, 0} "é" <> Nil{}: True{}
    case _ _: False{}

def split_second(result: Result<&1, &1, String, F.Buffer & List<&2, String>>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{value}:
      (buffer, lines) = value
      final_split(buffer, lines)

def split_continue(lines: List<&2, String>, buffer: F.Buffer) -> Bool:
  match lines:
    case Nil{}: split_second(F.feed(buffer, [169, 10]))
    case _: False{}

def split_first(result: Result<&1, &1, String, F.Buffer & List<&2, String>>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{value}:
      (buffer, lines) = value
      split_continue(lines, buffer)

def rejected(result: Result<&1, &1, String, F.Buffer & List<&2, String>>) -> Bool:
  match result:
    case Fail{message}: True{}
    case Done{value}: False{}

# Finite fixture equalities, not a general framing or UTF-8 correctness law.
def checker_fixtures() -> Bool:
  split_first(F.feed(F.new(), [195])) &&
  rejected(F.feed(F.new(), [195, 10])) &&
  rejected(F.feed(F.new(), [192, 128, 10])) &&
  rejected(F.feed(F.new(), [237, 160, 128, 10])) &&
  rejected(F.feed(F.new(), [97, 10, 192, 128, 10]))

law checked_segments:
  {F.segments([97, 10, 10, 195, 169]) == [[97, 10], [10], [195, 169]] : List<&2, List<&2, U32>>}

def checked_segments():
  {==}

law checked_empty_segments:
  {F.segments([]) == [] : List<&2, List<&2, U32>>}

def checked_empty_segments():
  {==}

law checked_terminated_segments:
  {F.segments([97, 10]) == [[97, 10]] : List<&2, List<&2, U32>>}

def checked_terminated_segments():
  {==}

law checked_fixtures:
  {checker_fixtures() == True{} : Bool}

def checked_fixtures():
  {==}

# The native harness receives trusted decimal byte chunks as arguments. It
# does not perform the framing/UTF-8 decoding under test; that is F.feed.
def parsed_number(found: Maybe<&2, U32>, acc: List<&2, U32>) -> Result<&2, &2, String, List<&2, U32>>:
  match found:
    case None{}: Fail{"invalid native fixture number"}
    case Some{byte}: Done{byte <> acc}

def parse_numbers(tokens: List<&2, String>, result: Result<&2, &2, String, List<&2, U32>>) -> Result<&2, &2, String, List<&2, U32>>:
  match tokens result:
    case _ Fail{message}: Fail{message}
    case Nil{} Done{acc}: Done{List.reverse(&2, U32, acc)}
    case "" <> rest Done{acc}: parse_numbers(rest, Done{acc})
    case token <> rest Done{acc}: parse_numbers(rest, parsed_number(U32.read(token), acc))

def apply_chunk(bytes: Result<&2, &2, String, List<&2, U32>>, buffer: F.Buffer) -> Result<&1, &1, String, F.Buffer & List<&2, String>>:
  match bytes:
    case Fail{message}: Fail{message}
    case Done{values}: F.feed(buffer, values)

def scalar_numbers(text: String, acc: List<&2, String>) -> String:
  match text:
    case SNil{}: "[" ++ String.join(List.reverse(&2, String, acc), ",") ++ "]"
    case SCon{Chr{code}, rest}: scalar_numbers(rest, U32.show(code) <> acc)

def line_numbers(lines: List<&2, String>, acc: List<&2, String>) -> String:
  match lines:
    case Nil{}: "[" ++ String.join(List.reverse(&2, String, acc), ",") ++ "]"
    case line <> rest: line_numbers(rest, scalar_numbers(line, Nil{}) <> acc)

# FNV-1a over the reversed pending bytes verifies preservation/order without
# dumping a 65536-byte partial record at every receive split.
def pending_hash(bytes: List<&2, U32>, acc: U32) -> U32:
  match bytes:
    case Nil{}: acc
    case byte <> rest: pending_hash(rest, U32.mul(U32.xor(acc, byte), 16777619))

def report_buffer(buffer: F.Buffer, lines: List<&2, String>) -> Result<&2, &2, String, Report>:
  match buffer:
    case F.Buffer{+reversed, +size}:
      Done{Report{F.Buffer{reversed, size},
        "{\"ok\":true,\"lines\":" ++ line_numbers(lines, Nil{}) ++
        ",\"pending_size\":" ++ U32.show(size) ++
        ",\"pending_reverse_fnv1a32\":" ++ U32.show(pending_hash(reversed, 2166136261)) ++ "}"}}

def report_feed(result: Result<&1, &1, String, F.Buffer & List<&2, String>>) -> Result<&2, &2, String, Report>:
  match result:
    case Fail{message}: Fail{message}
    case Done{value}:
      (buffer, lines) = value
      report_buffer(buffer, lines)

def collect(step: String, previous: List<&2, String>) -> List<&2, String>:
  match step:
    case SNil{}: previous
    case _: step <> previous

def report_end(eof: Result<&1, &1, String, Unit>, steps: List<&2, String>) -> String:
  match eof:
    case Done{value}: "{\"steps\":[" ++ String.join(List.reverse(&2, String, steps), ",") ++ "],\"eof\":true}"
    case Fail{message}: "{\"steps\":[" ++ String.join(List.reverse(&2, String, steps), ",") ++ "],\"eof\":false}"

def run_chunks(chunks: List<&2, String>, result: Result<&2, &2, String, Report>, previous: List<&2, String>) -> String:
  match chunks result:
    case _ Fail{message}:
      # F.feed and the trusted fixture parser use fixed ASCII error strings.
      report_end(Fail{"connection failed"}, ("{\"ok\":false,\"error\":\"" ++ message ++ "\"}") <> previous)
    case Nil{} Done{Report{buffer, step}}:
      report_end(F.finish(buffer), collect(step, previous))
    case chunk <> rest Done{Report{buffer, step}}:
      run_chunks(rest, report_feed(apply_chunk(parse_numbers(String.split(chunk, ','), Done{Nil{}}), buffer)), collect(step, previous))

def batch(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case chunks <> rest:
      do IO<Unit>:
        IO.print(run_chunks(String.split(chunks, ';'), Done{Report{F.new(), ""}}, Nil{}))
        batch(rest)

def dispatch(args: List<String>) -> IO(Unit):
  match args:
    case "batch" <> rest: batch(rest)
    case Nil{}: IO.print(Bool.pick(String, checker_fixtures(), "framing fixtures pass", "framing fixtures FAIL"))
    case _: IO.die(Unit, 2, "usage: framing-tests batch CHUNK[,BYTE...][;CHUNK...] ...")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    dispatch(List.tail(&1, String, args))
