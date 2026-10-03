import Base
import ../src/float_parse.bend as P

def bits_result(value: Result<&2, &2, String, F32>) -> Result<&2, &2, String, U32>:
  match value:
    case Fail{message}: Fail{message}
    case Done{number}: Done{F32.bits(number)}

# Finite grammar/signed-zero laws; full numeric rounding uses independent native
# oracles. These are not a universal decimal conversion theorem.
law strict_zero_and_grammar:
  {(P.parse_f32("-0.0"), P.parse_f32("00"), P.parse_f32("1e+")) == (Done{P.float_word(2147483648)}, Fail{"InvalidDecimal"}, Fail{"InvalidDecimal"}) : Result<&2, &2, String, F32> & Result<&2, &2, String, F32> & Result<&2, &2, String, F32>}

def strict_zero_and_grammar():
  {==}

def report_result(value: Result<&2, &2, String, F32>) -> IO(Unit):
  match value:
    case Done{number}: IO.print("ok|" ++ U32.show(F32.bits(number)))
    case Fail{message}: IO.print("error|" ++ message)

def report(text: String) -> IO(Unit):
  report_result(P.parse_f32(text))

def dispatch(text: String) -> IO(Unit):
  match text:
    case "@nul": report(SCon{Chr{49}, SCon{Chr{0}, SNil{}}})
    case "@surrogate": report(SCon{Chr{55296}, SNil{}})
    case _: report(text)

def run_args(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case arg <> rest:
      do IO<Unit>:
        dispatch(arg)
        run_args(rest)

def drop_program(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case program <> rest: run_args(rest)

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), drop_program)
