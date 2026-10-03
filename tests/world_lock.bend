import Base
import ../src/world_lock.bend as W

def released(result: Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match result:
    case Done{unit}: IO.print("released")
    case Fail{Tuple{code, message}}: IO.die(Unit, 1, "release:" ++ U32.show(code) ++ ":" ++ message)

def acquired(result: Result<&1, &1, U32 & String, W.Lease>, hold: U32) -> IO(Unit):
  match result:
    case Fail{Tuple{code, message}}: IO.die(Unit, 1, "acquire:" ++ U32.show(code) ++ ":" ++ message)
    case Done{lease}:
      do IO<Unit>:
        IO.print("acquired")
        IO.sleep(hold)
        result : Result<&1, &1, U32 & String, Unit> <- W.release(lease)
        released(result)

def configuration(args: List<&1, String>) -> IO(Unit):
  match args:
    case path <> "nul" <> Nil{}:
      do IO<Unit>:
        result : Result<&1, &1, U32 & String, W.Lease> <- W.acquire(path ++ Char.show(Chr{0}) ++ "suffix")
        acquired(result, 0)
    case path <> "release" <> Nil{}:
      do IO<Unit>:
        result : Result<&1, &1, U32 & String, W.Lease> <- W.acquire(path)
        acquired(result, 0)
    case path <> Nil{}:
      do IO<Unit>:
        result : Result<&1, &1, U32 & String, W.Lease> <- W.acquire(path)
        acquired(result, 30000)
    case other: IO.die(Unit, 1, "expected lease path and optional release marker")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<&1, String> <- IO.args()
    configuration(List.tail(&1, String, args))
