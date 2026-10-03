import Base
import ./inventory.bend as Inventory

# These equations cover the actual Nat kernel called by the U32 slot commit.
# They do not claim a fully verified Array implementation or conversion theorem.
law nat_add_right_successor:
  for a: Nat
  for b: Nat
  {Nat.add(a, 1n+b) == 1n+Nat.add(a, b) : Nat}

law loop_count_conservation:
  for +requested: Nat
  for +source: Nat
  for +destination: Nat
  for +room: Nat
  for moved: Nat
  {Inventory.count_total(Inventory.move_counts_loop(requested, source, destination, room, moved)) == Nat.add(source, destination) : Nat}

law loop_source_conservation:
  for +requested: Nat
  for +source: Nat
  for +destination: Nat
  for +room: Nat
  for +moved: Nat
  {Nat.add(Inventory.count_source(Inventory.move_counts_loop(requested, source, destination, room, moved)), Inventory.count_moved(Inventory.move_counts_loop(requested, source, destination, room, moved))) == Nat.add(source, moved) : Nat}

law count_conservation:
  for +requested: Nat
  for +source: Nat
  for +destination: Nat
  for +room: Nat
  {Inventory.count_total(Inventory.move_counts(requested, source, destination, room)) == Nat.add(source, destination) : Nat}

law moved_is_source_decrement:
  for +requested: Nat
  for +source: Nat
  for +destination: Nat
  for +room: Nat
  {Nat.add(Inventory.count_source(Inventory.move_counts(requested, source, destination, room)), Inventory.count_moved(Inventory.move_counts(requested, source, destination, room))) == source : Nat}

law zero_request_identity:
  for +source: Nat
  for +destination: Nat
  for room: Nat
  {Inventory.move_counts(0n, source, destination, room) == Inventory.CountMove{source, destination, 0n} : Inventory.CountMove}

law zero_room_identity:
  for requested: Nat
  for +source: Nat
  for +destination: Nat
  {Inventory.move_counts(requested, source, destination, 0n) == Inventory.CountMove{source, destination, 0n} : Inventory.CountMove}

# A false bounds guard on the real transfer path preserves the affine owner
# exactly, including all slots, keys, components, and logical length.
law bounds_rollback:
  for inv: Inventory.Inventory
  for source: U32
  for destination: U32
  for requested: U32
  for metadata: Inventory.ItemMetadata
  for mode: Inventory.TransferMode
  {Inventory.transfer_guard(inv, source, destination, requested, metadata, mode, False{}) == (inv, Inventory.InvRejected{Inventory.InvBounds{}}) : Inventory.Inventory & Inventory.TransferStatus}

law same_slot_rollback:
  for inv: Inventory.Inventory
  for source: U32
  for destination: U32
  for requested: U32
  for metadata: Inventory.ItemMetadata
  for mode: Inventory.TransferMode
  {Inventory.transfer_distinct(inv, source, destination, requested, metadata, mode, True{}) == (inv, Inventory.InvRejected{Inventory.InvSameSlot{}}) : Inventory.Inventory & Inventory.TransferStatus}

law full_destination_rollback:
  for inv: Inventory.Inventory
  for source: U32
  for destination: U32
  for requested: U32
  for key: Inventory.ItemKey
  for source_count: U32
  for destination_count: U32
  for limit: U32
  {Inventory.move_ready(inv, source, destination, requested, key, source_count, destination_count, limit, True{}) == (inv, Inventory.InvRejected{Inventory.InvFull{}}) : Inventory.Inventory & Inventory.TransferStatus}

law zero_move_commit_identity:
  for inv: Inventory.Inventory
  for source: U32
  for destination: U32
  for key: Inventory.ItemKey
  for remaining: Nat
  for final: Nat
  {Inventory.commit_counts(inv, source, destination, key, Inventory.CountMove{remaining, final, 0n}) == (inv, Inventory.InvMoved{0}) : Inventory.Inventory & Inventory.TransferStatus}

law different_item_rollback:
  for inv: Inventory.Inventory
  for source: U32
  for destination: U32
  for requested: U32
  for key: Inventory.ItemKey
  for count: U32
  for target_count: U32
  for metadata: Inventory.ItemMetadata
  {Inventory.target_compatible(inv, source, destination, requested, key, count, target_count, metadata, False{}) == (inv, Inventory.InvRejected{Inventory.InvDifferentItem{}}) : Inventory.Inventory & Inventory.TransferStatus}

law invalid_stack_rollback:
  for inv: Inventory.Inventory
  for source: U32
  for destination: U32
  for requested: U32
  for key: Inventory.ItemKey
  for count: U32
  for target_count: U32
  for metadata: Inventory.ItemMetadata
  {Inventory.metadata_valid(inv, source, destination, requested, key, count, target_count, metadata, False{}) == (inv, Inventory.InvRejected{Inventory.InvInvalidStack{}}) : Inventory.Inventory & Inventory.TransferStatus}

law bad_metadata_rollback:
  for inv: Inventory.Inventory
  for source: U32
  for destination: U32
  for requested: U32
  for key: Inventory.ItemKey
  for count: U32
  for target_count: U32
  for metadata: Inventory.ItemMetadata
  {Inventory.metadata_check(inv, source, destination, requested, key, count, target_count, metadata, False{}) == (inv, Inventory.InvRejected{Inventory.InvBadMetadata{}}) : Inventory.Inventory & Inventory.TransferStatus}

law mode_error_rollback:
  for inv: Inventory.Inventory
  for source: U32
  for destination: U32
  for requested: U32
  for metadata: Inventory.ItemMetadata
  for source_slot: Inventory.Slot
  for target_slot: Inventory.Slot
  for reason: Inventory.InventoryError
  {Inventory.transfer_pair(inv, source, destination, requested, metadata, source_slot, target_slot, Some{reason}) == (inv, Inventory.InvRejected{reason}) : Inventory.Inventory & Inventory.TransferStatus}

law empty_source_rollback:
  for inv: Inventory.Inventory
  for source: U32
  for destination: U32
  for requested: U32
  for metadata: Inventory.ItemMetadata
  for target_slot: Inventory.Slot
  {Inventory.transfer_pair(inv, source, destination, requested, metadata, Inventory.InvEmpty{}, target_slot, None{}) == (inv, Inventory.InvRejected{Inventory.InvNoSource{}}) : Inventory.Inventory & Inventory.TransferStatus}
