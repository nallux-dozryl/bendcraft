import Base
import ./src/schedule.bend as S
import ./src/section_laws.bend as SectionLaws
import ./src/inventory_laws.bend as InventoryLaws

# Every admitted action remains queued, even when its order key equals another.
law schedule_insert_count:
  for -P: Data
  for +ps: List<&2, S.Pending<P>>
  for +p: S.Pending<P>
  {S.length(P, S.insert(P, ps, p)) == 1n+S.length(P, ps) : Nat}

# Taking a due prefix partitions the queue without dropping or duplicating work.
law schedule_partition_count:
  for -P: Data
  for +ps: List<&2, S.Pending<P>>
  for +tick: Nat
  {S.partition_size(P, S.take_due(P, ps, tick)) == S.length(P, ps) : Nat}
