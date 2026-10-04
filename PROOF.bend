import Base
# Foundation and player CoreEdit aggregation; a green verdict does not certify the
# saved client. Run the scoped production targets in docs/PRODUCTION_PROOFS.md.
import ./src/schedule.bend as S
import ./LAWS.bend as Laws
import ./src/section_proof.bend as SectionProof
import ./src/inventory_proof.bend as InventoryProof
import ./src/player_core_edit_proof.bend as PlayerCoreEditProof

def insert_case(-P: Data, c: Cmp, +p: S.Pending<P>, +q: S.Pending<P>, +t: List<&2, S.Pending<P>>, +rest: List<&2, S.Pending<P>>, e: {S.length(P, rest) == 1n+S.length(P, t) : Nat}) -> {S.length(P, S.insert_choose(P, c, p, q, t, u => rest)) == 2n+S.length(P, t) : Nat}:
  match c:
    case GT{}:
      %e : {1n+S.length(P, rest) == 1n+_ : Nat}
      {==}
    case LT{}:
      {==}
    case EQ{}:
      {==}

def Laws.schedule_insert_count(P, ps, p):
  match ps:
    case Nil{}:
      {==}
    case Con{+q, +t}:
      insert_case(P, S.compare(S.pending_stamp(P, p), S.pending_stamp(P, q)), p, q, t, S.insert(P, t, p), Laws.schedule_insert_count(P, t, p))

def partition_case(-P: Data, hit: Bool, +p: S.Pending<P>, +t: List<&2, S.Pending<P>>, r: List<&2, S.Pending<P>> & List<&2, S.Pending<P>>, e: {S.partition_size(P, r) == S.length(P, t) : Nat}) -> {S.partition_size(P, S.take_choose(P, hit, p, t, u => r)) == 1n+S.length(P, t) : Nat}:
  match hit r:
    case False{} Tuple{a, b}:
      {==}
    case True{} Tuple{+a, +b}:
      %e : {1n+Nat.add(S.length(P, a), S.length(P, b)) == 1n+_ : Nat}
      {==}

def Laws.schedule_partition_count(P, ps, tick):
  match ps:
    case Nil{}:
      {==}
    case Con{+p, +t}:
      partition_case(P, Nat.is_le(S.stamp_tick(S.pending_stamp(P, p)), tick), p, t, S.take_due(P, t, tick), Laws.schedule_partition_count(P, t, tick))
