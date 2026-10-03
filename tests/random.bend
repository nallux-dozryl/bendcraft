import Base
import ../src/random.bend as R
import ../src/f64.bend as F

def number_maybe(value: Maybe<&2, U32>) -> U32:
  match value:
    case Some{x}: x
    case None{}: 0

def number(text: String) -> U32:
  number_maybe(U32.read(text))

def bits_show(value: R.Bits64) -> String:
  match value:
    case R.Bits64{hi, lo}: U32.show(hi) ++ "," ++ U32.show(lo)

def source_show(source: R.Source) -> String:
  match source:
    case R.Legacy{seed}: "l," ++ bits_show(seed) ++ ",0,0"
    case R.Xoroshiro{low, high}: "x," ++ bits_show(low) ++ "," ++ bits_show(high)

def factory_show(factory: R.Positional) -> String:
  match factory:
    case R.LegacyPositional{seed}: "l," ++ bits_show(seed) ++ ",0,0"
    case R.XoroshiroPositional{low, high}: "x," ++ bits_show(low) ++ "," ++ bits_show(high)

def f64_show(value: F.F64) -> String:
  match value:
    case F.F64{hi, lo}: U32.show(hi) ++ "," ++ U32.show(lo)

def int_result(result: R.Source & U32) -> R.Source & String:
  match result:
    case (source, value): (source, U32.show(value))

def long_result(result: R.Source & R.Bits64) -> R.Source & String:
  match result:
    case (source, value): (source, bits_show(value))

def bool_result(result: R.Source & Bool) -> R.Source & String:
  match result:
    case (source, value): (source, U32.show(Bool.to_u32(value)))

def float_result(result: R.Source & F32) -> R.Source & String:
  match result:
    case (source, value): (source, U32.show(F32.bits(value)))

def double_result(result: R.Source & F.F64) -> R.Source & String:
  match result:
    case (source, value): (source, f64_show(value))

def error_show(error: R.RandomError) -> String:
  match error:
    case R.InvalidBound{}: "invalid"
    case R.RejectionFuelExhausted{}: "fuel"
    case R.UnsupportedHash{}: "unsupported"

def bound_show(result: Result<&2, &2, R.RandomError, U32>) -> String:
  match result:
    case Done{value}: "ok:" ++ U32.show(value)
    case Fail{error}: error_show(error)

def bounded_result(result: R.Source & Result<&2, &2, R.RandomError, U32>) -> R.Source & String:
  match result:
    case (source, value): (source, bound_show(value))

def fork_result(result: R.Source & R.Source) -> R.Source & String:
  match result:
    case (parent, child): (child, "parent:" ++ source_show(parent))

def position_result(x: U32, y: U32, z: U32, result: R.Source & R.Positional) -> R.Source & String:
  match result:
    case (parent, +factory): (R.at(factory, x, y, z), "parent:" ++ source_show(parent) ++ ";factory:" ++ factory_show(factory))

def seed_result(seed: R.Bits64, result: R.Source & R.Positional) -> R.Source & String:
  match result:
    case (parent, +factory): (R.from_seed(factory, seed), "parent:" ++ source_show(parent) ++ ";factory:" ++ factory_show(factory))

def hash_done(original: R.Source, description: String, result: Result<&2, &2, R.RandomError, R.Source>) -> R.Source & String:
  match result:
    case Done{child}: (child, description)
    case Fail{error}: (original, error_show(error))

def hash_result(+original: R.Source, text: String, result: R.Source & R.Positional) -> R.Source & String:
  match result:
    case (parent, +factory): hash_done(original, "parent:" ++ source_show(parent) ++ ";factory:" ++ factory_show(factory), R.from_hash_of(factory, text))

def operation(+source: R.Source, fields: List<&2, String>) -> R.Source & String:
  match fields:
    case "i" <> Nil{}: int_result(R.next_int(source))
    case "l" <> Nil{}: long_result(R.next_long(source))
    case "b" <> Nil{}: bool_result(R.next_boolean(source))
    case "f" <> Nil{}: float_result(R.next_float(source))
    case "d" <> Nil{}: double_result(R.next_double(source))
    case "n" <> bound <> fuel <> Nil{}: bounded_result(R.next_bounded(U32.to_nat(number(fuel)), source, number(bound)))
    case "c" <> count <> Nil{}: (R.consume_count(source, number(count)), "-")
    case "s" <> hi <> lo <> Nil{}: (R.reseed(source, R.Bits64{number(hi), number(lo)}), "-")
    case "k" <> Nil{}: fork_result(R.fork(source))
    case "p" <> x <> y <> z <> Nil{}: position_result(number(x), number(y), number(z), R.fork_positional(source))
    case "t" <> hi <> lo <> Nil{}: seed_result(R.Bits64{number(hi), number(lo)}, R.fork_positional(source))
    case "h" <> text: hash_result(source, String.join(text, ":"), R.fork_positional(source))
    case _: (source, "bad_operation")

def report(label: String, index: U32, result: R.Source & String) -> IO(R.Source):
  match result:
    case (+source, output):
      do IO<R.Source>:
        IO.print(label ++ "|" ++ U32.show(index) ++ "|" ++ output ++ "|" ++ source_show(source))
        return source

def run_operations(operations: List<&2, String>, +label: String, +index: U32, source: R.Source) -> IO(Unit):
  match operations:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> tail:
      do IO<Unit>:
        next: R.Source <- report(label, index, operation(source, String.split(head, ':')))
        run_operations(tail, label, U32.inc(index), next)

def run_source(+label: String, source: R.Source, operations: String) -> IO(Unit):
  do IO<Unit>:
    initial: R.Source <- report(label, 0, (source, "init"))
    run_operations(String.split(operations, ';'), label, 1, initial)

def dispatch_source(label: String, kind: String, hi: U32, lo: U32, sh: U32, sl: U32, operations: String) -> IO(Unit):
  match kind:
    case "l": run_source(label, R.seeded_legacy(R.Bits64{hi, lo}), operations)
    case "x": run_source(label, R.seeded_xoroshiro(R.Bits64{hi, lo}), operations)
    case "r": run_source(label, R.raw_xoroshiro(R.Bits64{hi, lo}, R.Bits64{sh, sl}), operations)
    case _: IO.die(Unit, 2, "invalid RNG source")

def dispatch(fields: List<&2, String>) -> IO(Unit):
  match fields:
    case label <> kind <> hi <> lo <> sh <> sl <> operations <> Nil{}:
      dispatch_source(label, kind, number(hi), number(lo), number(sh), number(sl), operations)
    case _: IO.die(Unit, 2, "invalid RNG fixture")

def run_args(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> tail:
      do IO<Unit>:
        dispatch(String.split(head, '|'))
        run_args(tail)

def drop_program(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> tail: run_args(tail)

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), drop_program)
