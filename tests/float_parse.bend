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

law java_names_and_zero:
  {(P.parse_java_f32("-NaN"), P.parse_java_f32("+NaN"), P.parse_java_f32(" -00.0F ")) == (Done{P.float_word(2143289344)}, Done{P.float_word(2143289344)}, Done{P.float_word(2147483648)}) : Result<&2, &2, String, F32> & Result<&2, &2, String, F32> & Result<&2, &2, String, F32>}

def java_names_and_zero():
  {==}

def report_result(value: Result<&2, &2, String, F32>) -> IO(Unit):
  match value:
    case Done{number}: IO.print("ok|" ++ U32.show(F32.bits(number)))
    case Fail{message}: IO.print("error|" ++ message)

def report(text: String) -> IO(Unit):
  report_result(P.parse_f32(text))

def report_java(text: String) -> IO(Unit):
  report_result(P.parse_java_f32(text))

def dispatch(text: String) -> IO(Unit):
  match text:
    case "@nul": report(SCon{Chr{49}, SCon{Chr{0}, SNil{}}})
    case "@surrogate": report(SCon{Chr{55296}, SNil{}})
    case "@java_trim_nul": report_java(SCon{Chr{0}, SCon{Chr{49}, SCon{Chr{0}, SNil{}}}})
    case "@java_middle_nul": report_java(SCon{Chr{49}, SCon{Chr{0}, SCon{Chr{50}, SNil{}}}})
    case SCon{Chr{106}, SCon{Chr{124}, rest}}: report_java(rest)
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
