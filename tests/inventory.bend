import Base
import ../src/inventory.bend as Inv
import ../src/inventory_proof.bend as Proof

def number_result(value: Maybe<&2, U32>) -> U32:
  match value:
    case None{}: 4294967295
    case Some{x}: x

def number(text: String) -> U32:
  number_result(U32.read(text))

def key(code: U32) -> Inv.ItemKey:
  match code:
    case 2: Inv.ItemKey{"minecraft:dirt", "{}"}
    case 3: Inv.ItemKey{"minecraft:stone", "{name:a}"}
    case 4: Inv.ItemKey{"minecraft:stone", "{name:b}"}
    case 5: Inv.ItemKey{"minecraft:stone", "{ }"}
    case 6: Inv.ItemKey{"sentinel", "locked"}
    case 7: Inv.ItemKey{"outside", "guard"}
    case _: Inv.ItemKey{"minecraft:stone", "{}"}

def fixture_slot(code: U32, count: U32) -> Inv.Slot:
  match code:
    case 0: Inv.InvEmpty{}
    case _: Inv.InvStack{key(code), count}

def code_if(code: U32, yes: Bool, remaining: U32) -> U32:
  match yes:
    case True{}: code
    case False{}: remaining

def key_code(+item: Inv.ItemKey) -> U32:
  code_if(1, Inv.key_equal(item, key(1)),
    code_if(2, Inv.key_equal(item, key(2)),
      code_if(3, Inv.key_equal(item, key(3)),
        code_if(4, Inv.key_equal(item, key(4)),
          code_if(5, Inv.key_equal(item, key(5)),
            code_if(6, Inv.key_equal(item, key(6)),
              code_if(7, Inv.key_equal(item, key(7)), 99)))))))

def slot_show(slot: Inv.Slot) -> String:
  match slot:
    case Inv.InvEmpty{}: "0:0"
    case Inv.InvStack{item, count}:
      U32.show(key_code(item)) ++ ":" ++ U32.show(count)

def slots_show(slots: List<Inv.Slot>) -> String:
  match slots:
    case Nil{}: ""
    case Con{slot, rest}: "|" ++ slot_show(slot) ++ slots_show(rest)

def report(label: String, result: Inv.Inventory & Inv.TransferStatus) -> IO(Unit):
  (Inv.Inventory{slots, length}, status) = result
  IO.print(label ++ "|" ++ Inv.status_show(status) ++ slots_show(Array.to_list(~Inv.Slot, slots)))

def load_status(result: Inv.Inventory & Bool) -> Inv.Inventory & Inv.TransferStatus:
  (inv, valid) = result
  (inv, Inv.InvMoved{Bool.to_u32(valid)})

def read_status(result: Inv.Inventory & Maybe<&2, Inv.Slot>) -> Inv.Inventory & Inv.TransferStatus:
  (inv, slot) = result
  match slot:
    case None{}: (inv, Inv.InvRejected{Inv.InvBounds{}})
    case Some{x}: (inv, Inv.InvMoved{Inv.slot_count(x)})

def new_status(inv: Inv.Inventory, result: Maybe<Inv.Inventory>) -> Inv.Inventory & Inv.TransferStatus:
  match result:
    case None{}: (inv, Inv.InvRejected{Inv.InvInvalidStack{}})
    case Some{fresh}: (fresh, Inv.InvMoved{0})

def run_mode(inv: Inv.Inventory, si: U32, di: U32, requested: U32, metadata: Inv.ItemMetadata, mode: String) -> Inv.Inventory & Inv.TransferStatus:
  match mode:
    case "new": new_status(inv, Inv.new(U32.to_nat(requested), di))
    case "load": load_status(Inv.load_slot(inv, si, fixture_slot(di, requested), metadata))
    case "read": read_status(Inv.read(inv, si))
    case "split": Inv.split(inv, si, di, requested, metadata)
    case "merge": Inv.merge(inv, si, di, requested, metadata)
    case _: Inv.transfer(inv, si, di, requested, metadata)

def fixture_slots(sk: U32, sc: U32, dk: U32, dc: U32, shape: U32) -> Array<Inv.Slot>:
  match shape:
    case 1:
      ANode{ANode{ALeaf{fixture_slot(sk, sc)}, ALeaf{fixture_slot(dk, dc)}}, ALeaf{fixture_slot(6, 17)}}
    case 2:
      ANode{ALeaf{fixture_slot(sk, sc)}, ANode{ALeaf{fixture_slot(dk, dc)}, ALeaf{fixture_slot(6, 17)}}}
    case 3:
      ALeaf{fixture_slot(sk, sc)}
    case _:
      ANode{ANode{ALeaf{fixture_slot(sk, sc)}, ALeaf{fixture_slot(dk, dc)}}, ANode{ALeaf{fixture_slot(6, 17)}, ALeaf{fixture_slot(7, 23)}}}

def run_case(label: String, mode: String, sc: U32, dc: U32, limit: U32, requested: U32, si: U32, di: U32, sk: U32, dk: U32, mk: U32, logical: U32, shape: U32) -> IO(Unit):
  slots = fixture_slots(sk, sc, dk, dc, shape)
  report(label, run_mode(Inv.Inventory{slots, logical}, si, di, requested, Inv.ItemMetadata{key(mk), limit}, mode))

def dispatch(fields: List<&2, String>) -> IO(Unit):
  match fields:
    case label <> mode <> sc <> dc <> limit <> requested <> si <> di <> sk <> dk <> mk <> logical <> shape <> Nil{}:
      run_case(label, mode, number(sc), number(dc), number(limit), number(requested), number(si), number(di), number(sk), number(dk), number(mk), number(logical), number(shape))
    case _:
      IO.die(Unit, 2, "invalid inventory test protocol")

def run_args(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{arg, rest}:
      do IO<Unit>:
        dispatch(String.split(arg, '|'))
        run_args(rest)

def drop_program(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{program, rest}: run_args(rest)

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), drop_program)
