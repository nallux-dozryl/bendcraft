import Base
import ./inventory.bend as Inventory
import ./inventory_laws.bend as Laws

def Laws.nat_add_right_successor(a, b):
  match a:
    case 0n:
      {==}
    case 1n+p:
      Equal.cong(Nat, Nat, x => 1n+x, Nat.add(p, 1n+b), 1n+Nat.add(p, b), Laws.nat_add_right_successor(p, b))

def Laws.loop_count_conservation(requested, source, destination, room, moved):
  match requested source room:
    case 0n _ _:
      {==}
    case 1n+q 0n _:
      {==}
    case 1n+q 1n+s 0n:
      {==}
    case 1n+q 1n+s 1n+r:
      Equal.trans(Nat,
        Inventory.count_total(Inventory.move_counts_loop(q, s, 1n+destination, r, 1n+moved)),
        Nat.add(s, 1n+destination), 1n+Nat.add(s, destination),
        Laws.loop_count_conservation(q, s, 1n+destination, r, 1n+moved),
        Laws.nat_add_right_successor(s, destination))

def Laws.loop_source_conservation(requested, source, destination, room, moved):
  match requested source room:
    case 0n _ _:
      {==}
    case 1n+q 0n _:
      {==}
    case 1n+q 1n+s 0n:
      {==}
    case 1n+q 1n+s 1n+r:
      Equal.trans(Nat,
        Nat.add(Inventory.count_source(Inventory.move_counts_loop(q, s, 1n+destination, r, 1n+moved)),
          Inventory.count_moved(Inventory.move_counts_loop(q, s, 1n+destination, r, 1n+moved))),
        Nat.add(s, 1n+moved), 1n+Nat.add(s, moved),
        Laws.loop_source_conservation(q, s, 1n+destination, r, 1n+moved),
        Laws.nat_add_right_successor(s, moved))

def Laws.count_conservation(requested, source, destination, room):
  Laws.loop_count_conservation(requested, source, destination, room, 0n)

# Nat.add(a,0) is not definitionally a; discharge it structurally.
def add_zero(a: Nat) -> {Nat.add(a, 0n) == a : Nat}:
  match a:
    case 0n: {==}
    case 1n+p:
      Equal.cong(Nat, Nat, x => 1n+x, Nat.add(p, 0n), p, add_zero(p))

def Laws.moved_is_source_decrement(requested, source, destination, room):
  Equal.trans(Nat,
    Nat.add(Inventory.count_source(Inventory.move_counts(requested, source, destination, room)),
      Inventory.count_moved(Inventory.move_counts(requested, source, destination, room))),
    Nat.add(source, 0n), source,
    Laws.loop_source_conservation(requested, source, destination, room, 0n),
    add_zero(source))

def Laws.zero_request_identity(source, destination, room):
  {==}

def Laws.zero_room_identity(requested, source, destination):
  match requested source:
    case 0n _:
      {==}
    case 1n+q 0n:
      {==}
    case 1n+q 1n+s:
      {==}

def Laws.bounds_rollback(inv, source, destination, requested, metadata, mode):
  {==}

def Laws.same_slot_rollback(inv, source, destination, requested, metadata, mode):
  match inv:
    case Inventory.Inventory{slots, length}:
      {==}

def Laws.full_destination_rollback(inv, source, destination, requested, key, source_count, destination_count, limit):
  {==}

def Laws.zero_move_commit_identity(inv, source, destination, key, remaining, final):
  match inv:
    case Inventory.Inventory{slots, length}: {==}

def Laws.different_item_rollback(inv, source, destination, requested, key, count, target_count, metadata):
  match metadata:
    case Inventory.ItemMetadata{known, limit}: {==}

def Laws.invalid_stack_rollback(inv, source, destination, requested, key, count, target_count, metadata):
  match metadata:
    case Inventory.ItemMetadata{known, limit}: {==}

def Laws.bad_metadata_rollback(inv, source, destination, requested, key, count, target_count, metadata):
  match metadata:
    case Inventory.ItemMetadata{known, limit}: {==}

def Laws.mode_error_rollback(inv, source, destination, requested, metadata, source_slot, target_slot, reason):
  match source_slot target_slot:
    case Inventory.InvEmpty{} Inventory.InvEmpty{}: {==}
    case Inventory.InvEmpty{} Inventory.InvStack{target_key, target_count}: {==}
    case Inventory.InvStack{source_key, source_count} Inventory.InvEmpty{}: {==}
    case Inventory.InvStack{source_key, source_count} Inventory.InvStack{target_key, target_count}: {==}

def Laws.empty_source_rollback(inv, source, destination, requested, metadata, target_slot):
  match target_slot:
    case Inventory.InvEmpty{}: {==}
    case Inventory.InvStack{target_key, target_count}: {==}
