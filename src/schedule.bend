import Base

# Tick-boundary order is independent of arrival order within the boundary.
type Stamp is Data:
  Stamp{tick: Nat, peer: U32, sequence: Nat}

type Pending<-P: Data> is Data:
  Pending{stamp: Stamp, operation: P}

def stamp_tick(s: Stamp) -> Nat:
  Stamp{tick, peer, sequence} = s
  tick

def stamp_peer(s: Stamp) -> U32:
  Stamp{tick, peer, sequence} = s
  peer

def stamp_sequence(s: Stamp) -> Nat:
  Stamp{tick, peer, sequence} = s
  sequence

def compare_sequence(c: Cmp, a: Nat, b: Nat) -> Cmp:
  match c:
    case EQ{}:
      Nat.cmp(a, b)
    case other:
      other

def compare_peer(c: Cmp, +a: Stamp, +b: Stamp) -> Cmp:
  match c:
    case EQ{}:
      compare_sequence(U32.cmp(stamp_peer(a), stamp_peer(b)), stamp_sequence(a), stamp_sequence(b))
    case other:
      other

def compare(+a: Stamp, +b: Stamp) -> Cmp:
  compare_peer(Nat.cmp(stamp_tick(a), stamp_tick(b)), a, b)

def pending_stamp(-P: Data, p: Pending<P>) -> Stamp:
  Pending{s, operation} = p
  s

def length(-P: Data, ps: List<&2, Pending<P>>) -> Nat:
  match ps:
    case Nil{}:
      0n
    case Con{p, t}:
      1n+length(P, t)

def insert_choose(-P: Data, c: Cmp, p: Pending<P>, q: Pending<P>, t: List<&2, Pending<P>>, rest: Unit -> List<&2, Pending<P>>) -> List<&2, Pending<P>>:
  match c:
    case GT{}:
      q <> rest(Unit{})
    case other:
      p <> q <> t

# Identity uniqueness is enforced at admission; this function preserves all
# entries, including equal stamps, so no queued action can silently disappear.
def insert(-P: Data, +ps: List<&2, Pending<P>>, +p: Pending<P>) -> List<&2, Pending<P>>:
  match ps:
    case Nil{}:
      [p]
    case Con{+q, t}:
      insert_choose(P, compare(pending_stamp(P, p), pending_stamp(P, q)), p, q, t, u => insert(P, t, p))

def prepend_due(-P: Data, p: Pending<P>, r: List<&2, Pending<P>> & List<&2, Pending<P>>) -> List<&2, Pending<P>> & List<&2, Pending<P>>:
  (due, future) = r
  (p <> due, future)

def take_choose(-P: Data, hit: Bool, p: Pending<P>, t: List<&2, Pending<P>>, rest: Unit -> List<&2, Pending<P>> & List<&2, Pending<P>>) -> List<&2, Pending<P>> & List<&2, Pending<P>>:
  match hit:
    case True{}:
      prepend_due(P, p, rest(Unit{}))
    case False{}:
      ([], p <> t)

# Requires sorted input; insert maintains the order. Actions are removed only
# when their tick is due, and the future suffix is retained exactly.
def take_due(-P: Data, +ps: List<&2, Pending<P>>, +tick: Nat) -> List<&2, Pending<P>> & List<&2, Pending<P>>:
  match ps:
    case Nil{}:
      ([], [])
    case Con{+p, t}:
      take_choose(P, Nat.is_le(stamp_tick(pending_stamp(P, p)), tick), p, t, u => take_due(P, t, tick))

def same_identity(+a: Stamp, +b: Stamp) -> Bool:
  U32.is_eq(stamp_peer(a), stamp_peer(b)) && Nat.is_eq(stamp_sequence(a), stamp_sequence(b))

def cancel_choose(-P: Data, hit: Bool, p: Pending<P>, r: List<&2, Pending<P>>) -> List<&2, Pending<P>>:
  match hit:
    case True{}:
      r
    case False{}:
      p <> r

def cancel(-P: Data, ps: List<&2, Pending<P>>, +identity: Stamp) -> List<&2, Pending<P>>:
  match ps:
    case Nil{}:
      []
    case Con{+p, t}:
      cancel_choose(P, same_identity(pending_stamp(P, p), identity), p, cancel(P, t, identity))

def partition_size(-P: Data, pair: List<&2, Pending<P>> & List<&2, Pending<P>>) -> Nat:
  (a, b) = pair
  Nat.add(length(P, a), length(P, b))
