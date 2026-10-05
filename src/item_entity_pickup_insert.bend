import Base
import ./inventory.bend as I
import ./player_inventory_return.bend as R
import ./item_entity_pickup_model.bend as M

def done(slots:List<&2,I.Slot>,remaining:U32,inserted:U32,returned:Bool,pops:List<&2,M.Pop>) -> Result<&2,&2,M.Error,M.Insertion>:
  Done{M.Insertion{slots,remaining,inserted,returned,pops}}
def blocked(creative:Bool,slots:List<&2,I.Slot>,remaining:U32,inserted:U32,pops:List<&2,M.Pop>) -> Result<&2,&2,M.Error,M.Insertion>:
  match creative:
    case True{}: done(slots,0,inserted,True{},pops)
    case False{}: done(slots,remaining,inserted,False{},pops)
def advanced_counts(slots:List<&2,I.Slot>,+index:U32,key:I.ItemKey,inserted:U32,pops:List<&2,M.Pop>,
    next:List<&2,I.Slot> -> U32 -> U32 -> List<&2,M.Pop> -> Result<&2,&2,M.Error,M.Insertion>,counts:I.CountMove) -> Result<&2,&2,M.Error,M.Insertion>:
  I.CountMove{left,final,moved} = counts
  next(R.replace(slots,U32.to_nat(index),I.InvStack{key,U32.from_nat(final)}))(U32.from_nat(left))(U32.add(inserted,U32.from_nat(moved)))(List.append(&2,M.Pop,pops,[M.Pop{index,5}]))
def advanced(slots:List<&2,I.Slot>,index:U32,key:I.ItemKey,+count:U32,+stored:U32,limit:U32,inserted:U32,pops:List<&2,M.Pop>,
    next:List<&2,I.Slot> -> U32 -> U32 -> List<&2,M.Pop> -> Result<&2,&2,M.Error,M.Insertion>) -> Result<&2,&2,M.Error,M.Insertion>:
  advanced_counts(slots,index,key,inserted,pops,next,I.move_counts(U32.to_nat(count),U32.to_nat(count),U32.to_nat(stored),U32.to_nat(U32.sub(limit,stored))))
def destination(found:Maybe<&2,U32>,creative:Bool,+slots:List<&2,I.Slot>,key:I.ItemKey,count:U32,limit:U32,inserted:U32,pops:List<&2,M.Pop>,
    next:List<&2,I.Slot> -> U32 -> U32 -> List<&2,M.Pop> -> Result<&2,&2,M.Error,M.Insertion>) -> Result<&2,&2,M.Error,M.Insertion>:
  match found:
    case None{}: blocked(creative,slots,count,inserted,pops)
    case Some{+index}: advanced(slots,index,key,count,I.slot_count(R.at(slots,U32.to_nat(index))),limit,inserted,pops,next)
# Actual Inventory.add(-1,stack) repeats addResource until empty/no progress.
# The final no-progress survival return is FALSE even after partial insertion.
def resources(left:Nat,+slots:List<&2,I.Slot>,+selected:U32,+key:I.ItemKey,count:U32,+limit:U32,+creative:Bool,inserted:U32,pops:List<&2,M.Pop>) -> Result<&2,&2,M.Error,M.Insertion>:
  match left count:
    case _ 0: done(slots,0,inserted,True{},pops)
    case 0n _: Fail{M.BudgetExhausted{}}
    case 1n+rest _:
      destination(R.destination(slots,selected,key,limit),creative,slots,key,count,limit,inserted,pops,
        values => remaining => inserted => pops => resources(rest,values,selected,key,remaining,limit,creative,inserted,pops))
def damaged_target(found:Maybe<&2,U32>,creative:Bool,slots:List<&2,I.Slot>,key:I.ItemKey,+count:U32,limit:U32) -> Result<&2,&2,M.Error,M.Insertion>:
  match found:
    case None{}: blocked(creative,slots,count,0,[])
    case Some{+index}:
      do Result<&2,&2,M.Error,M.Insertion>:
        M.guarded(U32.is_le(count,limit),"damaged whole-copy exceeds current authoritative inventory stack domain")
        done(R.replace(slots,U32.to_nat(index),I.InvStack{key,count}),0,count,True{},[M.Pop{index,5}])
def insert(properties:M.Properties,+slots:List<&2,I.Slot>,selected:U32,count:U32,creative:Bool,budget:Nat) -> Result<&2,&2,M.Error,M.Insertion>:
  M.Properties{I.ItemMetadata{key,limit},damaged} = properties
  match damaged:
    case False{}: resources(budget,slots,selected,key,count,limit,creative,0,[])
    case True{}: damaged_target(R.find_empty(36n,0,slots),creative,slots,key,count,limit)
