import Base
import ../src/f64.bend as F

def number_result(value: Maybe<&2, U32>) -> U32:
  match value:
    case Some{x}: x
    case None{}: 0

def number(text: String) -> U32:
  number_result(U32.read(text))

def value_show(value: F.F64) -> String:
  match value:
    case F.F64{hi, lo}: U32.show(hi) ++ "|" ++ U32.show(lo)

def class_code(kind: F.F64Class) -> U32:
  match kind:
    case F.F64Zero{}: 0
    case F.F64Subnormal{}: 1
    case F.F64Normal{}: 2
    case F.F64Infinity{}: 3
    case F.F64NaN{}: 4

def order_code(order: F.F64Order) -> U32:
  match order:
    case F.F64Less{}: 0
    case F.F64Equal{}: 1
    case F.F64Greater{}: 2
    case F.F64Unordered{}: 3

def relation_mask(+a: F.F64, +b: F.F64) -> U32:
  U32.or(U32.or(U32.or(U32.or(U32.or(Bool.to_u32(F.is_eq(a, b)), U32.shln(Bool.to_u32(F.is_ne(a, b)), 1n)), U32.shln(Bool.to_u32(F.is_lt(a, b)), 2n)), U32.shln(Bool.to_u32(F.is_le(a, b)), 3n)), U32.shln(Bool.to_u32(F.is_gt(a, b)), 4n)), U32.shln(Bool.to_u32(F.is_ge(a, b)), 5n))

def report(label: String, +a: F.F64, +b: F.F64) -> IO(Unit):
  IO.print(label ++ "|" ++ value_show(F.add(a, b)) ++ "|" ++ value_show(F.sub(a, b)) ++ "|" ++ value_show(F.mul(a, b)) ++ "|" ++ value_show(F.div(a, b)) ++ "|" ++ U32.show(order_code(F.compare(a, b))) ++ "|" ++ U32.show(class_code(F.classify(a))) ++ "|" ++ U32.show(class_code(F.classify(b))) ++ "|" ++ U32.show(Bool.to_u32(F.sign(a))) ++ "|" ++ U32.show(Bool.to_u32(F.sign(b))) ++ "|" ++ U32.show(Bool.to_u32(F.is_finite(a))) ++ "|" ++ U32.show(Bool.to_u32(F.is_finite(b))) ++ "|" ++ U32.show(relation_mask(a, b)) ++ "|" ++ value_show(F.neg(a)) ++ "|" ++ value_show(F.abs(a)))

def benchmark_loop(fuel: Nat, accumulator: F.F64, +delta: F.F64) -> F.F64:
  match fuel:
    case 0n: accumulator
    case 1n+rest: benchmark_loop(rest, F.add(accumulator, delta), delta)

def benchmark_mul_loop(fuel: Nat, accumulator: F.F64, +delta: F.F64) -> F.F64:
  match fuel:
    case 0n: accumulator
    case 1n+rest: benchmark_mul_loop(rest, F.mul(accumulator, delta), delta)

def benchmark_div_loop(fuel: Nat, accumulator: F.F64, +delta: F.F64) -> F.F64:
  match fuel:
    case 0n: accumulator
    case 1n+rest: benchmark_div_loop(rest, F.div(accumulator, delta), delta)

def benchmark_finish(started: Nat, result: F.F64) -> IO(Unit):
  IO.bind(Nat, Unit, IO.now(), ended => IO.print("bench|" ++ value_show(result) ++ "|" ++ Nat.show(Nat.sub(ended, started))))

def benchmark_start(iterations: U32, initial: F.F64, delta: F.F64, started: Nat) -> IO(Unit):
  benchmark_finish(started, benchmark_loop(U32.to_nat(iterations), initial, delta))

def benchmark_report(iterations: U32, initial: F.F64, delta: F.F64) -> IO(Unit):
  IO.bind(Nat, Unit, IO.now(), started => benchmark_start(iterations, initial, delta, started))

def benchmark_mul_start(iterations: U32, initial: F.F64, delta: F.F64, started: Nat) -> IO(Unit):
  benchmark_finish(started, benchmark_mul_loop(U32.to_nat(iterations), initial, delta))

def benchmark_mul_report(iterations: U32, initial: F.F64, delta: F.F64) -> IO(Unit):
  IO.bind(Nat, Unit, IO.now(), started => benchmark_mul_start(iterations, initial, delta, started))

def benchmark_div_start(iterations: U32, initial: F.F64, delta: F.F64, started: Nat) -> IO(Unit):
  benchmark_finish(started, benchmark_div_loop(U32.to_nat(iterations), initial, delta))

def benchmark_div_report(iterations: U32, initial: F.F64, delta: F.F64) -> IO(Unit):
  IO.bind(Nat, Unit, IO.now(), started => benchmark_div_start(iterations, initial, delta, started))

def float_word(value: U32) -> F32:
  match value:
    case U32{word}: F32{word}

def conversion_show(result: Result<&2, &2, F.F64ConversionError, U32>) -> String:
  match result:
    case Done{bits}: "ok:" ++ U32.show(bits)
    case Fail{F.F64NaNConversion{}}: "nan"
    case Fail{F.F64OutOfI32Range{}}: "range"

def conversion_report(+word: U32, +value: F.F64) -> IO(Unit):
  IO.print("convert|" ++ U32.show(word) ++ "|" ++ value_show(F.from_u32(word)) ++ "|" ++ value_show(F.from_i32(word)) ++ "|" ++ value_show(F.from_f32(float_word(word))) ++ "|" ++ conversion_show(F.trunc_i32(value)) ++ "|" ++ conversion_show(F.floor_i32(value)))

def dispatch_label(label: String, ah: U32, al: U32, bh: U32, bl: U32, extra: U32) -> IO(Unit):
  match label:
    case "bench": benchmark_report(ah, F.F64{al, bh}, F.F64{bl, extra})
    case "benchmul": benchmark_mul_report(ah, F.F64{al, bh}, F.F64{bl, extra})
    case "benchdiv": benchmark_div_report(ah, F.F64{al, bh}, F.F64{bl, extra})
    case "convert": conversion_report(ah, F.F64{al, bh})
    case _: report(label, F.F64{ah, al}, F.F64{bh, bl})

def dispatch(fields: List<&2, String>) -> IO(Unit):
  match fields:
    case label <> ah <> al <> bh <> bl <> extra <> Nil{}:
      dispatch_label(label, number(ah), number(al), number(bh), number(bl), number(extra))
    case _: IO.die(Unit, 2, "invalid binary64 test protocol")

def run_args(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{arg, rest}:
      do IO<Unit>:
        dispatch(String.split(arg, '|'))
        run_args(rest)

def drop_program(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{program, rest}: run_args(rest)

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), drop_program)
