import Base
import ./inventory.bend as Inv
import ./player_item_definitions.bend as D
import ./player_inventory_return.bend as Return
import ./crafting_recipe.bend as R
import ./player_inventory.bend as I
import ./player_crafting_authority_components.bend as M

# Observations do not own stacks. A transaction is admitted in full while the
# outer authority retains its one player Array and optional bench Array.
type Transaction is Data:
  Transaction{slots:List<&2,Inv.Slot>,grid:R.Grid,taken:Inv.Slot,
    before:List<&2,Nat>,after:List<&2,Nat>,consumed:List<&2,Nat>,produced:List<&2,Nat>,valid:Bool,message:String}

type Work is Data:
  Work{slots:List<&2,Inv.Slot>,grid:List<&2,Inv.Slot>,consumed:List<&2,Inv.Slot>,remainders:List<&2,Inv.Slot>,valid:Bool}

def player_cells(+slots:List<&2,Inv.Slot>) -> List<&2,Inv.Slot>:
  List.append(&2,Inv.Slot,I.first(43n,slots),[Return.at(slots,47n)])

def all_cells(+slots:List<&2,Inv.Slot>,grid:R.Grid) -> List<&2,Inv.Slot>:
  R.Grid{width,height,inputs} = grid
  List.append(&2,Inv.Slot,R.choose(List<&2,Inv.Slot>,slots,player_cells(slots),U32.is_eq(width,3)),inputs)

def vector_add(a:List<&2,Nat>,b:List<&2,Nat>) -> List<&2,Nat>:
  match a b:
    case left <> rest right <> tail: Nat.add(left,right) <> vector_add(rest,tail)
    case _ _: []

def before_counts(value:Transaction) -> List<&2,Nat>:
  Transaction{slots,grid,taken,before,after,consumed,produced,valid,message} = value
  vector_add(before,produced)

def after_counts(value:Transaction) -> List<&2,Nat>:
  Transaction{slots,grid,taken,before,after,consumed,produced,valid,message} = value
  vector_add(after,consumed)

def admitted(+value:Transaction) -> Bool:
  Transaction{slots,grid,taken,before,after,consumed,produced,valid,message} = value
  valid && Return.counts_equal(before_counts(value),after_counts(value))

def message(value:Transaction) -> String:
  Transaction{slots,grid,taken,before,after,consumed,produced,valid,message} = value
  message

def slots(value:Transaction) -> List<&2,Inv.Slot>:
  Transaction{slots,grid,taken,before,after,consumed,produced,valid,message} = value
  slots

def grid(value:Transaction) -> R.Grid:
  Transaction{slots,grid,taken,before,after,consumed,produced,valid,message} = value
  grid

def taken(value:Transaction) -> Inv.Slot:
  Transaction{slots,grid,taken,before,after,consumed,produced,valid,message} = value
  taken

def refused(slots:List<&2,Inv.Slot>,grid:R.Grid,message:String) -> Transaction:
  Transaction{slots,grid,Inv.InvEmpty{},[],[],[],[],False{},message}

def inspected(+before_slots:List<&2,Inv.Slot>,+before_grid:R.Grid,+after_slots:List<&2,Inv.Slot>,+after_grid:R.Grid,+taken:Inv.Slot,+consumed:List<&2,Inv.Slot>,+remainders:List<&2,Inv.Slot>,+catalog:D.Catalog,allowed:Bool,+mode:M.Mode) -> Transaction:
  R.Grid{+width,+height,+inputs} = after_grid
  +before = all_cells(before_slots,before_grid)
  +after = all_cells(after_slots,after_grid)
  +produced = List.append(&2,Inv.Slot,[taken],remainders)
  +queries = List.append(&2,Inv.ItemKey,Return.keys(before),List.append(&2,Inv.ItemKey,Return.keys(after),List.append(&2,Inv.ItemKey,Return.keys(consumed),Return.keys(produced))))
  Transaction{after_slots,after_grid,taken,Return.ledger(queries,before),Return.ledger(queries,after),Return.ledger(queries,consumed),Return.ledger(queries,produced),
    allowed && M.valid_slots(48n,after_slots,mode,catalog) && M.valid_slots(U32.to_nat(U32.mul(width,height)),inputs,mode,catalog),
    "crafting remainder requires capacity or owned world-drop disposition"}

def returned(remainder:Inv.Slot,+slots:List<&2,Inv.Slot>,selected:U32,catalog:D.Catalog) -> List<&2,Inv.Slot>:
  Return.return_at(List.append(&2,Inv.Slot,slots,[remainder]),catalog,48,selected)

def return_finished(+returned:List<&2,Inv.Slot>,inputs:List<&2,Inv.Slot>,consumed:List<&2,Inv.Slot>,remainders:List<&2,Inv.Slot>) -> Work:
  Work{I.first(48n,returned),inputs,consumed,remainders,I.empty_slots([Return.at(returned,48n)])}

def remainder_matching(same:Bool,+key:Inv.ItemKey,+count:U32,remaining:U32,+slots:List<&2,Inv.Slot>,+inputs:List<&2,Inv.Slot>,index:U32,selected:U32,catalog:D.Catalog,consumed:List<&2,Inv.Slot>,+remainders:List<&2,Inv.Slot>) -> Work:
  match same:
    case True{}: Work{slots,Return.replace(inputs,U32.to_nat(index),Inv.InvStack{key,U32.add(remaining,count)}),consumed,Inv.InvStack{key,count} <> remainders,True{}}
    case False{}: return_finished(returned(Inv.InvStack{key,count},slots,selected,catalog),inputs,consumed,Inv.InvStack{key,count} <> remainders)

def remainder_target(target:Inv.Slot,+key:Inv.ItemKey,+count:U32,slots:List<&2,Inv.Slot>,inputs:List<&2,Inv.Slot>,index:U32,selected:U32,catalog:D.Catalog,consumed:List<&2,Inv.Slot>,remainders:List<&2,Inv.Slot>) -> Work:
  match target:
    case Inv.InvEmpty{}: Work{slots,Return.replace(inputs,U32.to_nat(index),Inv.InvStack{key,count}),consumed,Inv.InvStack{key,count} <> remainders,True{}}
    case Inv.InvStack{other,remaining}: remainder_matching(Inv.key_equal(key,other),key,count,remaining,slots,inputs,index,selected,catalog,consumed,remainders)

def remainder_known(remainder:Inv.Slot,slots:List<&2,Inv.Slot>,+inputs:List<&2,Inv.Slot>,+index:U32,selected:U32,catalog:D.Catalog,consumed:List<&2,Inv.Slot>,remainders:List<&2,Inv.Slot>) -> Work:
  match remainder:
    case Inv.InvEmpty{}: Work{slots,inputs,consumed,remainders,True{}}
    case Inv.InvStack{key,count}: remainder_target(Return.at(inputs,U32.to_nat(index)),key,count,slots,inputs,index,selected,catalog,consumed,remainders)

def consume_admitted(valid:Bool,+key:Inv.ItemKey,+amount:U32,slots:List<&2,Inv.Slot>,+inputs:List<&2,Inv.Slot>,+index:U32,+count:U32,remainder:Inv.Slot,selected:U32,catalog:D.Catalog,consumed:List<&2,Inv.Slot>,remainders:List<&2,Inv.Slot>) -> Work:
  match valid:
    case False{}: Work{slots,inputs,consumed,remainders,False{}}
    case True{}: remainder_known(remainder,slots,Return.replace(inputs,U32.to_nat(index),Inv.canonical_stack(key,U32.sub(amount,count),U32.is_eq(amount,count))),index,selected,catalog,Inv.InvStack{key,count} <> consumed,remainders)

def consumed_slot(slot:Inv.Slot,slots:List<&2,Inv.Slot>,+inputs:List<&2,Inv.Slot>,+index:U32,+count:U32,remainder:Inv.Slot,selected:U32,catalog:D.Catalog,consumed:List<&2,Inv.Slot>,remainders:List<&2,Inv.Slot>) -> Work:
  match slot:
    case Inv.InvEmpty{}: Work{slots,inputs,consumed,remainders,False{}}
    case Inv.InvStack{key,+amount}: consume_admitted(U32.is_eq(count,1) && U32.is_gt(amount,0),key,amount,slots,inputs,index,count,remainder,selected,catalog,consumed,remainders)

def work_slots(work:Work) -> List<&2,Inv.Slot>:
  Work{slots,inputs,consumed,remainders,valid} = work
  slots

def consume_one(valid:Bool,+work:Work,+index:U32,count:U32,remainder:Inv.Slot,selected:U32,catalog:D.Catalog) -> Work:
  match valid:
    case False{}: Work{work_slots(work),[],[],[],False{}}
    case True{}:
      Work{slots,+inputs,consumed,remainders,allowed} = work
      consumed_slot(Return.at(inputs,U32.to_nat(index)),slots,inputs,index,count,remainder,selected,catalog,consumed,remainders)


def consume(steps:List<&2,R.Consumption>,+work:Work,+selected:U32,+catalog:D.Catalog) -> Work:
  match steps work:
    case Nil{} _: work
    case _ Work{slots,inputs,consumed,remainders,False{}}: Work{slots,inputs,consumed,remainders,False{}}
    case R.Consumption{+index,count,remainder} <> rest Work{slots,+inputs,consumed,remainders,True{}}:
      consume(rest,consume_one(Nat.is_lt(U32.to_nat(index),List.length(&2,Inv.Slot,inputs)),work,index,count,remainder,selected,catalog),selected,catalog)

def consumed_result(work:Work,before_slots:List<&2,Inv.Slot>,+before_grid:R.Grid,taken:Inv.Slot,catalog:D.Catalog,+mode:M.Mode) -> Transaction:
  Work{slots,grid,consumed,remainders,valid} = work
  R.Grid{width,height,inputs} = before_grid
  inspected(before_slots,before_grid,slots,R.Grid{width,height,grid},taken,consumed,remainders,catalog,valid,mode)

def consumed(before_slots:List<&2,Inv.Slot>,+before_grid:R.Grid,taken:Inv.Slot,after_slots:List<&2,Inv.Slot>,steps:List<&2,R.Consumption>,selected:U32,+catalog:D.Catalog,+mode:M.Mode) -> Transaction:
  R.Grid{width,height,inputs} = before_grid
  consumed_result(consume(steps,Work{after_slots,inputs,[],[],True{}},selected,catalog),before_slots,before_grid,taken,catalog,mode)

def moved_output(+before_slots:List<&2,Inv.Slot>,before_grid:R.Grid,+key:Inv.ItemKey,+taken:U32,+carried:U32,steps:List<&2,R.Consumption>,selected:U32,catalog:D.Catalog,+mode:M.Mode) -> Transaction:
  consumed(before_slots,before_grid,Inv.InvStack{key,taken},Return.replace(before_slots,47n,Inv.InvStack{key,U32.add(carried,taken)}),steps,selected,catalog,mode)

def output_capacity(allowed:Bool,slots:List<&2,Inv.Slot>,grid:R.Grid,key:Inv.ItemKey,count:U32,carried:U32,steps:List<&2,R.Consumption>,selected:U32,catalog:D.Catalog,+mode:M.Mode) -> Transaction:
  match allowed:
    case False{}: refused(slots,grid,"carried stack cannot take the complete crafting result")
    case True{}: moved_output(slots,grid,key,count,carried,steps,selected,catalog,mode)

def output_carried(carried:Inv.Slot,slots:List<&2,Inv.Slot>,grid:R.Grid,+key:Inv.ItemKey,+count:U32,+limit:U32,steps:List<&2,R.Consumption>,selected:U32,catalog:D.Catalog,button:U32,+mode:M.Mode) -> Transaction:
  match carried:
    case Inv.InvEmpty{}:
      output_capacity(U32.is_le(count,limit),slots,grid,key,count,0,steps,selected,catalog,mode)
    case Inv.InvStack{other,+amount}:
      output_capacity(Inv.key_equal(key,other) && U32.is_le(amount,limit) && U32.is_le(count,U32.sub(limit,amount)),slots,grid,key,count,amount,steps,selected,catalog,mode)

def output_metadata_with(metadata:Maybe<&2,Inv.ItemMetadata>,+slots:List<&2,Inv.Slot>,grid:R.Grid,key:Inv.ItemKey,count:U32,steps:List<&2,R.Consumption>,selected:U32,catalog:D.Catalog,button:U32,+mode:M.Mode) -> Transaction:
  match metadata:
    case None{}: refused(slots,grid,"crafting result lacks inventory component admission")
    case Some{Inv.ItemMetadata{actual,limit}}: output_carried(Return.at(slots,47n),slots,grid,key,count,limit,steps,selected,catalog,button,mode)

def output_with(output:Inv.Slot,slots:List<&2,Inv.Slot>,grid:R.Grid,steps:List<&2,R.Consumption>,selected:U32,+catalog:D.Catalog,button:U32,+mode:M.Mode) -> Transaction:
  match output:
    case Inv.InvEmpty{}: refused(slots,grid,"crafting result is empty")
    case Inv.InvStack{+key,count}: output_metadata_with(M.metadata(mode,catalog,key),slots,grid,key,count,steps,selected,catalog,button,mode)

def plan_with(slots:List<&2,Inv.Slot>,+grid:R.Grid,recipe:R.Plan,selected:U32,catalog:D.Catalog,button:U32,+mode:M.Mode) -> Transaction:
  R.Plan{id,result,before,steps} = recipe
  output_with(result,slots,grid,steps,selected,catalog,button,mode)

def output_metadata(metadata:Maybe<&2,Inv.ItemMetadata>,slots:List<&2,Inv.Slot>,grid:R.Grid,key:Inv.ItemKey,count:U32,steps:List<&2,R.Consumption>,selected:U32,catalog:D.Catalog,button:U32) -> Transaction:
  output_metadata_with(metadata,slots,grid,key,count,steps,selected,catalog,button,M.DefaultOnly{})

def output(output:Inv.Slot,slots:List<&2,Inv.Slot>,grid:R.Grid,steps:List<&2,R.Consumption>,selected:U32,catalog:D.Catalog,button:U32) -> Transaction:
  output_with(output,slots,grid,steps,selected,catalog,button,M.DefaultOnly{})

def plan(slots:List<&2,Inv.Slot>,grid:R.Grid,recipe:R.Plan,selected:U32,catalog:D.Catalog,button:U32) -> Transaction:
  plan_with(slots,grid,recipe,selected,catalog,button,M.DefaultOnly{})
