import Base

# An item's complete foundation-layer identity. Components are an immutable,
# caller-canonicalized payload; equal IDs with different payloads never merge.
type ItemKey is Data:
  ItemKey{id: String, components: String}

type ItemMetadata is Data:
  ItemMetadata{key: ItemKey, stack_limit: U32}

type Slot is Data:
  InvEmpty{}
  InvStack{key: ItemKey, count: U32}

# Arrays remain affine. length is the logical length, which may be smaller than
# the power-of-two backing array. All access also checks actual backing size.
type Inventory is Type:
  Inventory{slots: Array<Slot>, length: U32}

type TransferMode is Data:
  TransferAny{}
  TransferSplit{}
  TransferMerge{}

type InventoryError is Data:
  InvBounds{}
  InvSameSlot{}
  InvNoSource{}
  InvBadMetadata{}
  InvInvalidStack{}
  InvDifferentItem{}
  InvFull{}
  InvSplitNeedsEmpty{}
  InvMergeNeedsStack{}

type TransferStatus is Data:
  InvMoved{count: U32}
  InvRejected{reason: InventoryError}

type CountMove is Data:
  CountMove{source: Nat, destination: Nat, moved: Nat}

def key_equal(a: ItemKey, b: ItemKey) -> Bool:
  match a b:
    case ItemKey{id_a, components_a} ItemKey{id_b, components_b}:
      String.eq(id_a, id_b) && String.eq(components_a, components_b)

def slot_count(slot: Slot) -> U32:
  match slot:
    case InvEmpty{}:
      0
    case InvStack{key, count}:
      count

def count_total(counts: CountMove) -> Nat:
  match counts:
    case CountMove{source, destination, moved}:
      Nat.add(source, destination)

# Tail-recursive arithmetic kernel called by commit_counts below. Runtime counts
# remain U32 in slots; only two touched counts cross this verified Nat boundary.
# The loop performs min(requested, source, room) constant-space iterations.
def move_counts_loop(requested: Nat, source: Nat, destination: Nat, room: Nat, moved: Nat) -> CountMove:
  match requested source room:
    case 0n _ _:
      CountMove{source, destination, moved}
    case 1n+q 0n _:
      CountMove{0n, destination, moved}
    case 1n+q 1n+s 0n:
      CountMove{1n+s, destination, moved}
    case 1n+q 1n+s 1n+r:
      move_counts_loop(q, s, 1n+destination, r, 1n+moved)

def move_counts(requested: Nat, source: Nat, destination: Nat, room: Nat) -> CountMove:
  move_counts_loop(requested, source, destination, room, 0n)

def count_source(counts: CountMove) -> Nat:
  match counts:
    case CountMove{source, destination, moved}:
      source

def count_moved(counts: CountMove) -> Nat:
  match counts:
    case CountMove{source, destination, moved}:
      moved

def new_result(length: U32, slots: Array<Slot>, valid: Bool) -> Maybe<Inventory>:
  match valid:
    case False{}:
      None{}
    case True{}:
      Some{Inventory{slots, length}}

def new_sized(+depth: Nat, +length: U32, valid: Bool) -> Maybe<Inventory>:
  match valid:
    case False{}:
      None{}
    case True{}:
      new_result(length, Array.new(Slot, depth, InvEmpty{}), U32.is_le(length, U32.shln(1, depth)))

# A maximum depth of 16 avoids unbounded allocations at a public constructor.
# It permits 65,536 slots; logical length 0 is supported with backing capacity 1.
def new(+depth: Nat, length: U32) -> Maybe<Inventory>:
  new_sized(depth, length, Nat.is_le(depth, 16n))

def indices_valid(+length: U32, +capacity: U32, +source: U32, +destination: U32) -> Bool:
  U32.is_lt(source, length) && U32.is_lt(destination, length) && U32.is_lt(source, capacity) && U32.is_lt(destination, capacity)

def read_result(length: U32, result: Array<Slot> & Slot) -> Inventory & Maybe<&2, Slot>:
  (slots, slot) = result
  (Inventory{slots, length}, Some{slot})

def read_valid(inv: Inventory, index: U32, valid: Bool) -> Inventory & Maybe<&2, Slot>:
  match inv valid:
    case Inventory{slots, length} False{}:
      (Inventory{slots, length}, None{})
    case Inventory{slots, length} True{}:
      read_result(length, Array.get(Slot, slots, index))

def read_sized(+length: U32, +index: U32, sized: Array<Slot> & U32) -> Inventory & Maybe<&2, Slot>:
  (slots, +capacity) = sized
  read_valid(Inventory{slots, length}, index, indices_valid(length, capacity, index, index))

def read(inv: Inventory, index: U32) -> Inventory & Maybe<&2, Slot>:
  Inventory{slots, length} = inv
  read_sized(length, index, Array.size(Slot, slots))

def slot_valid(slot: Slot, metadata: ItemMetadata) -> Bool:
  match slot metadata:
    case InvEmpty{} _:
      True{}
    case InvStack{key, +count} ItemMetadata{known, +limit}:
      key_equal(key, known) && U32.is_gt(limit, 0) && U32.is_gt(count, 0) && U32.is_le(count, limit)

def load_valid(inv: Inventory, index: U32, slot: Slot, valid: Bool) -> Inventory & Bool:
  match inv valid:
    case Inventory{slots, length} False{}:
      (Inventory{slots, length}, False{})
    case Inventory{slots, length} True{}:
      (Inventory{Array.set(Slot, slots, index, slot), length}, True{})

# Explicit state-loading primitive, for save/fixture/registry initialization.
# It may replace counts. It is not a gameplay acquisition or creative command.
def load_sized(+length: U32, +index: U32, +slot: Slot, metadata: ItemMetadata, sized: Array<Slot> & U32) -> Inventory & Bool:
  (slots, +capacity) = sized
  load_valid(Inventory{slots, length}, index, slot, indices_valid(length, capacity, index, index) && slot_valid(slot, metadata))

def load_slot(inv: Inventory, index: U32, slot: Slot, metadata: ItemMetadata) -> Inventory & Bool:
  Inventory{slots, length} = inv
  load_sized(length, index, slot, metadata, Array.size(Slot, slots))

def canonical_stack(key: ItemKey, count: U32, zero: Bool) -> Slot:
  match zero:
    case True{}:
      InvEmpty{}
    case False{}:
      InvStack{key, count}

# All count arithmetic is delegated to the proved kernel. On success, only the
# two touched slots are replaced. Conversions are bounded by validated U32
# source counts and destination room; no U32 addition/subtraction can wrap.
def commit_counts(inv: Inventory, source: U32, destination: U32, +key: ItemKey, counts: CountMove) -> Inventory & TransferStatus:
  match inv counts:
    case Inventory{slots, length} CountMove{remaining, final, 0n}:
      (Inventory{slots, length}, InvMoved{0})
    case Inventory{slots, length} CountMove{remaining, final, 1n+m}:
      +left = U32.from_nat(remaining)
      target = {InvStack{key, U32.from_nat(final)} : Slot}
      slots = Array.set(Slot, slots, source, canonical_stack(key, left, U32.is_zero(left)))
      slots = Array.set(Slot, slots, destination, target)
      (Inventory{slots, length}, InvMoved{U32.from_nat(1n+m)})

def move_ready(inv: Inventory, source: U32, destination: U32, requested: U32, key: ItemKey, source_count: U32, +destination_count: U32, limit: U32, full: Bool) -> Inventory & TransferStatus:
  match full:
    case True{}:
      (inv, InvRejected{InvFull{}})
    case False{}:
      commit_counts(inv, source, destination, key, move_counts(U32.to_nat(requested), U32.to_nat(source_count), U32.to_nat(destination_count), U32.to_nat(U32.sub(limit, destination_count))))

def metadata_valid(inv: Inventory, source: U32, destination: U32, requested: U32, +key: ItemKey, +count: U32, +target_count: U32, metadata: ItemMetadata, valid: Bool) -> Inventory & TransferStatus:
  match metadata valid:
    case _ False{}:
      (inv, InvRejected{InvInvalidStack{}})
    case ItemMetadata{known, +limit} True{}:
      move_ready(inv, source, destination, requested, key, count, target_count, limit, U32.is_eq(target_count, limit))

def metadata_check(inv: Inventory, source: U32, destination: U32, requested: U32, +key: ItemKey, +count: U32, +target_count: U32, +metadata: ItemMetadata, compatible: Bool) -> Inventory & TransferStatus:
  match metadata compatible:
    case _ False{}:
      (inv, InvRejected{InvBadMetadata{}})
    case ItemMetadata{known, +limit} True{}:
      metadata_valid(inv, source, destination, requested, key, count, target_count, ItemMetadata{known, limit}, U32.is_gt(count, 0) && U32.is_le(count, limit) && U32.is_le(target_count, limit))

def target_compatible(inv: Inventory, source: U32, destination: U32, requested: U32, +key: ItemKey, count: U32, target_count: U32, +metadata: ItemMetadata, compatible: Bool) -> Inventory & TransferStatus:
  match metadata compatible:
    case _ False{}:
      (inv, InvRejected{InvDifferentItem{}})
    case ItemMetadata{+known, +limit} True{}:
      metadata_check(inv, source, destination, requested, key, count, target_count, ItemMetadata{known, limit}, key_equal(key, known) && U32.is_gt(limit, 0))

def target_stack_checked(inv: Inventory, source: U32, destination: U32, requested: U32, +key: ItemKey, count: U32, other: ItemKey, target_count: U32, metadata: ItemMetadata, nonzero: Bool) -> Inventory & TransferStatus:
  match nonzero:
    case False{}:
      (inv, InvRejected{InvInvalidStack{}})
    case True{}:
      target_compatible(inv, source, destination, requested, key, count, target_count, metadata, key_equal(key, other))

def mode_target(mode: TransferMode, target: Slot) -> Maybe<&2, InventoryError>:
  match mode target:
    case TransferSplit{} InvStack{key, count}:
      Some{InvSplitNeedsEmpty{}}
    case TransferMerge{} InvEmpty{}:
      Some{InvMergeNeedsStack{}}
    case _ _:
      None{}

def transfer_pair(inv: Inventory, source: U32, destination: U32, requested: U32, metadata: ItemMetadata, source_slot: Slot, target_slot: Slot, mode_error: Maybe<&2, InventoryError>) -> Inventory & TransferStatus:
  match source_slot target_slot mode_error:
    case _ _ Some{reason}:
      (inv, InvRejected{reason})
    case InvEmpty{} _ None{}:
      (inv, InvRejected{InvNoSource{}})
    case InvStack{key, count} InvEmpty{} None{}:
      target_compatible(inv, source, destination, requested, key, count, 0, metadata, True{})
    case InvStack{+key, count} InvStack{other, +target_count} None{}:
      target_stack_checked(inv, source, destination, requested, key, count, other, target_count, metadata, U32.is_gt(target_count, 0))

def transfer_target_read(length: U32, source: U32, destination: U32, requested: U32, metadata: ItemMetadata, mode: TransferMode, source_slot: Slot, result: Array<Slot> & Slot) -> Inventory & TransferStatus:
  (slots, +target_slot) = result
  transfer_pair(Inventory{slots, length}, source, destination, requested, metadata, source_slot, target_slot, mode_target(mode, target_slot))

def transfer_source_read(length: U32, source: U32, +destination: U32, requested: U32, metadata: ItemMetadata, mode: TransferMode, result: Array<Slot> & Slot) -> Inventory & TransferStatus:
  (slots, source_slot) = result
  transfer_target_read(length, source, destination, requested, metadata, mode, source_slot, Array.get(Slot, slots, destination))

def transfer_distinct(inv: Inventory, +source: U32, +destination: U32, requested: U32, metadata: ItemMetadata, mode: TransferMode, same: Bool) -> Inventory & TransferStatus:
  match inv same:
    case Inventory{slots, length} True{}:
      (Inventory{slots, length}, InvRejected{InvSameSlot{}})
    case Inventory{slots, length} False{}:
      transfer_source_read(length, source, destination, requested, metadata, mode, Array.get(Slot, slots, source))

# This gate is on the real public transfer path and is separately proved to
# preserve the entire owned inventory on an invalid index pair.
def transfer_guard(inv: Inventory, +source: U32, +destination: U32, requested: U32, metadata: ItemMetadata, mode: TransferMode, valid: Bool) -> Inventory & TransferStatus:
  match valid:
    case False{}:
      (inv, InvRejected{InvBounds{}})
    case True{}:
      transfer_distinct(inv, source, destination, requested, metadata, mode, U32.is_eq(source, destination))

def transfer_sized(+length: U32, +source: U32, +destination: U32, requested: U32, metadata: ItemMetadata, mode: TransferMode, sized: Array<Slot> & U32) -> Inventory & TransferStatus:
  (slots, +capacity) = sized
  transfer_guard(Inventory{slots, length}, source, destination, requested, metadata, mode, indices_valid(length, capacity, source, destination))

def transfer_mode(inv: Inventory, source: U32, destination: U32, requested: U32, metadata: ItemMetadata, mode: TransferMode) -> Inventory & TransferStatus:
  Inventory{slots, length} = inv
  transfer_sized(length, source, destination, requested, metadata, mode, Array.size(Slot, slots))

def transfer(inv: Inventory, source: U32, destination: U32, requested: U32, metadata: ItemMetadata) -> Inventory & TransferStatus:
  transfer_mode(inv, source, destination, requested, metadata, TransferAny{})

def split(inv: Inventory, source: U32, destination: U32, requested: U32, metadata: ItemMetadata) -> Inventory & TransferStatus:
  transfer_mode(inv, source, destination, requested, metadata, TransferSplit{})

def merge(inv: Inventory, source: U32, destination: U32, requested: U32, metadata: ItemMetadata) -> Inventory & TransferStatus:
  transfer_mode(inv, source, destination, requested, metadata, TransferMerge{})

def error_name(error: InventoryError) -> String:
  match error:
    case InvBounds{}: "bounds"
    case InvSameSlot{}: "same_slot"
    case InvNoSource{}: "no_source"
    case InvBadMetadata{}: "bad_metadata"
    case InvInvalidStack{}: "invalid_stack"
    case InvDifferentItem{}: "different_item"
    case InvFull{}: "full"
    case InvSplitNeedsEmpty{}: "split_needs_empty"
    case InvMergeNeedsStack{}: "merge_needs_stack"

def status_show(status: TransferStatus) -> String:
  match status:
    case InvMoved{count}:
      "moved:" ++ U32.show(count)
    case InvRejected{reason}:
      "rejected:" ++ error_name(reason)
