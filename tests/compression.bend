import Base
import ../src/compression.bend as C

# Finite fixtures only; these do not establish universal DEFLATE correctness.
law empty_checksums:
  {(C.adler32([]), C.crc32([])) == (1, 0) : U32 & U32}

def empty_checksums():
  {==}

law invalid_byte:
  {C.inflate_raw([256], C.Limits{1, 0}) == Fail{C.Error{"InvalidByte"}} : Result<&2, &1, C.Error, C.Decoded>}

def invalid_byte():
  {==}

law stored_fixture:
  {C.inflate_raw([1, 1, 0, 254, 255, 65], C.Limits{6, 1}) == Done{C.Decoded{[65], 1, 6, 4325442, 3554254475}} : Result<&2, &1, C.Error, C.Decoded>}

def stored_fixture():
  {==}

law empty_stored_writer:
  {C.store_raw([], C.Limits{0, 5}) == Done{C.Encoded{[1, 0, 0, 255, 255], 5, 0, 1, 0}} : Result<&2, &1, C.Error, C.Encoded>}

def empty_stored_writer():
  {==}

def encoded_result(result: Result<&2, &1, C.Error, C.Encoded>) -> Result<&2, &1, C.Error, C.Decoded>:
  match result:
    case Fail{error}: Fail{error}
    case Done{C.Encoded{bytes, size, source_size, adler, crc}}:
      Done{C.Decoded{bytes, size, source_size, adler, crc}}

def decode(mode: String, bytes: List<&2, U32>, limits: C.Limits) -> Result<&2, &1, C.Error, C.Decoded>:
  match mode:
    case "raw": C.inflate_raw(bytes, limits)
    case "zlib": C.inflate_zlib(bytes, limits)
    case "gzip": C.inflate_gzip(bytes, limits)
    case "encode-raw": encoded_result(C.store_raw(bytes, limits))
    case "encode-zlib": encoded_result(C.store_zlib(bytes, limits))
    case "encode-gzip": encoded_result(C.store_gzip(bytes, limits))
    case _: Fail{C.Error{"UnknownFixtureMode"}}

def fnv(bytes: List<&2, U32>, hash: U32) -> U32:
  match bytes:
    case Nil{}: hash
    case byte <> rest: fnv(rest, U32.mul(U32.xor(hash, byte), 16777619))

def digest(result: Result<&2, &1, C.Error, C.Decoded>) -> Result<&2, &1, C.Error, U32>:
  match result:
    case Fail{error}: Fail{error}
    case Done{C.Decoded{bytes, size, consumed, adler, crc}}:
      Done{U32.xor(U32.xor(U32.add(crc, size), adler), fnv(bytes, 2166136261))}

def benchmark(n: Nat, +mode: String, +bytes: List<&2, U32>, +limits: C.Limits, hash: U32) -> Result<&2, &1, C.Error, U32>:
  match n:
    case 0n: Done{hash}
    case 1n+p:
      do Result<&2, &1, C.Error, U32>:
        value : U32 <- digest(decode(mode, bytes, limits))
        benchmark(p, mode, bytes, limits, U32.add(hash, value))

def report_failure(error: C.Error) -> IO(Unit):
  C.Error{code} = error
  IO.print("{\"ok\":false,\"error\":\"" ++ code ++ "\"}")

def report_bench(result: Result<&2, &1, C.Error, U32>) -> IO(Unit):
  match result:
    case Fail{error}: report_failure(error)
    case Done{hash}: IO.print("{\"ok\":true,\"digest\":" ++ U32.show(hash) ++ "}")

def timed_bench(result: Result<&2, &1, C.Error, U32>, started: Nat, read_ms: Nat) -> IO(Unit):
  match result:
    case Fail{error}: report_failure(error)
    case Done{hash}:
      do IO<Unit>:
        ended : Nat <- IO.now()
        IO.print("{\"ok\":true,\"digest\":" ++ U32.show(hash) ++ ",\"read_ms\":" ++ Nat.show(read_ms) ++
          ",\"steady_ms\":" ++ Nat.show(Nat.sub(ended, started)) ++ "}")

def run_bench(mode: String, bytes: List<&2, U32>, limits: C.Limits, iterations: U32, read_ms: Nat) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    timed_bench(benchmark(U32.to_nat(iterations), mode, bytes, limits, 0), started, read_ms)

def written(result: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (file, status) = result
  do IO<Unit>:
    IO.pass(Unit, status)
    File.close(file)

def publish(path: String, result: Result<&2, &1, C.Error, C.Decoded>) -> IO(Unit):
  match result:
    case Fail{error}: report_failure(error)
    case Done{C.Decoded{bytes, +size, consumed, adler, crc}}:
      do IO<Unit>:
        file : File <- IO.try(File, File.open(path, "w"))
        result : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(file, bytes)
        written(result)
        IO.print("{\"ok\":true,\"size\":" ++ U32.show(size) ++ ",\"consumed\":" ++ U32.show(consumed) ++
          ",\"adler\":" ++ U32.show(adler) ++ ",\"crc\":" ++ U32.show(crc) ++ "}")

def execute(mode: String, input: List<&2, U32>, +limits: C.Limits, path: String, iterations: U32, read_ms: Nat) -> IO(Unit):
  match mode:
    case "bench-raw": run_bench("raw", input, limits, iterations, read_ms)
    case "bench-zlib": run_bench("zlib", input, limits, iterations, read_ms)
    case "bench-gzip": run_bench("gzip", input, limits, iterations, read_ms)
    case _: publish(path, decode(mode, input, limits))

def loaded(mode: String, limits: C.Limits, path: String, iterations: U32, read_started: Nat,
    result: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  (file, status) = result
  do IO<Unit>:
    File.close(file)
    bytes : List<&2, U32> <- IO.pass(List<&2, U32>, status)
    read_ended : Nat <- IO.now()
    execute(mode, bytes, limits, path, iterations, Nat.sub(read_ended, read_started))

def read_case(mode: String, limits: C.Limits, input: String, output: String, iterations: U32) -> IO(Unit):
  do IO<Unit>:
    started : Nat <- IO.now()
    file : File <- IO.try(File, File.open(input, "r"))
    result : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, 16777216)
    loaded(mode, limits, output, iterations, started, result)

def configuration(mode: String, input_limit: Maybe<&2, U32>, output_limit: Maybe<&2, U32>, input: String,
    output: String, iterations: Maybe<&2, U32>) -> IO(Unit):
  match input_limit output_limit iterations:
    case Some{a} Some{b} Some{n}: read_case(mode, C.Limits{a, b}, input, output, n)
    case _ _ _: IO.die(Unit, 2, "invalid compression fixture number")

def batch(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case mode <> input_limit <> output_limit <> input <> output <> iterations <> rest:
      do IO<Unit>:
        configuration(mode, U32.read(input_limit), U32.read(output_limit), input, output, U32.read(iterations))
        batch(rest)
    case _: IO.die(Unit, 2, "usage: compression-tests MODE MAX_INPUT MAX_OUTPUT INPUT_PATH OUTPUT_PATH ITERATIONS ...")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    batch(List.tail(&1, String, args))
