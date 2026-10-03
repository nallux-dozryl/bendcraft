import Base
import ../src/schedule.bend as S

def require(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, message)

def payloads(ps: List<&2, S.Pending<U32>>) -> List<&2, U32>:
  match ps:
    case Nil{}:
      []
    case Con{S.Pending{s, op}, t}:
      op <> payloads(t)

def equal_words(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case Con{x, t} Con{y, u}:
      U32.is_eq(x, y) && equal_words(t, u)
    case _ _:
      False{}

def p(tick: Nat, peer: U32, sequence: Nat, value: U32) -> S.Pending<U32>:
  S.Pending{S.Stamp{tick, peer, sequence}, value}

def checks(+q4: List<&2, S.Pending<U32>>, partition: List<&2, S.Pending<U32>> & List<&2, S.Pending<U32>>) -> IO(Unit):
  (due, future) = partition
  do IO<Unit>:
    require(equal_words(payloads(q4), [291, 412, 413, 432, 701]), "tick/peer/sequence ordering failed")
    require(equal_words(payloads(due), [291, 412, 413, 432]), "due prefix failed")
    require(equal_words(payloads(future), [701]), "future action lost")
    require(equal_words(payloads(S.cancel(U32, q4, S.Stamp{0n, 1, 2n})), [291, 413, 432, 701]), "cancel identity failed")
    require(equal_words(payloads(S.cancel(U32, q4, S.Stamp{0n, 99, 99n})), [291, 412, 413, 432, 701]), "missing cancel mutated queue")
    require(Nat.is_eq(S.partition_size(U32, S.take_due(U32, q4, 0n)), 5n), "early partition lost action")
    require(Nat.is_eq(S.partition_size(U32, S.take_due(U32, q4, 100n)), 5n), "late partition lost action")
    IO.print("PASS schedule: order, due/future partition, cancellation, conservation")

def main() -> IO(Unit):
  +q0 = S.insert(U32, [], p(4n, 3, 2n, 432))
  +q1 = S.insert(U32, q0, p(2n, 9, 1n, 291))
  +q2 = S.insert(U32, q1, p(4n, 1, 3n, 413))
  +q3 = S.insert(U32, q2, p(4n, 1, 2n, 412))
  +q4 = S.insert(U32, q3, p(7n, 0, 1n, 701))
  checks(q4, S.take_due(U32, q4, 4n))
