import Base
import ./inventory.bend as Inv
import ./player_item_definitions.bend as D
import ./nbt.bend as N

# Immutable planning over the complete48 logical slots. No planner value owns
# a stack; the sole inventory Array remains owned by the server actor.
type Plan is Data:
  Plan{slots:List<&2,Inv.Slot>,before_counts:List<&2,Nat>,after_counts:List<&2,Nat>,returned:Bool,valid:Bool}

def at(values:List<&2,Inv.Slot>,index:Nat) -> Inv.Slot:
  match values index:
    case value <> rest 0n: value
    case value <> rest 1n+n: at(rest,n)
    case _ _: Inv.InvEmpty{}

def replace(values:List<&2,Inv.Slot>,index:Nat,value:Inv.Slot) -> List<&2,Inv.Slot>:
  match values index:
    case head <> rest 0n: value <> rest
    case head <> rest 1n+n: head <> replace(rest,n,value)
    case _ _: values

def compatible(+key:Inv.ItemKey,+limit:U32,slot:Inv.Slot) -> Bool:
  match slot:
    case Inv.InvEmpty{}: False{}
    case Inv.InvStack{other,+count}: Inv.key_equal(key,other) && U32.is_lt(count,limit) && U32.is_gt(limit,1)

def find_matching(left:Nat,+index:U32,slots:List<&2,Inv.Slot>,+key:Inv.ItemKey,+limit:U32) -> Maybe<&2,U32>:
  match left slots:
    case 1n+n slot <> rest:
      N.choose(Maybe<&2,U32>,Some{index},find_matching(n,U32.add(index,1),rest,key,limit),compatible(key,limit,slot))
    case _ _: None{}

def find_empty(left:Nat,+index:U32,slots:List<&2,Inv.Slot>) -> Maybe<&2,U32>:
  match left slots:
    case 1n+n Inv.InvEmpty{} <> rest: Some{index}
    case 1n+n slot <> rest: find_empty(n,U32.add(index,1),rest)
    case _ _: None{}

def chosen_match(found:Maybe<&2,U32>,slots:List<&2,Inv.Slot>) -> Maybe<&2,U32>:
  match found:
    case Some{index}: Some{index}
    case None{}: find_empty(36n,0,slots)

# Actual Java26.3 order: selected merge, offhand merge, ascending main merge;
# only then first empty main. Equipment empty cells are not free main slots.
def destination(+slots:List<&2,Inv.Slot>,+selected:U32,+key:Inv.ItemKey,+limit:U32) -> Maybe<&2,U32>:
  N.choose(Maybe<&2,U32>,Some{selected},N.choose(Maybe<&2,U32>,Some{40},
    chosen_match(find_matching(36n,0,slots,key,limit),slots),compatible(key,limit,at(slots,40n))),
    compatible(key,limit,at(slots,U32.to_nat(selected))))

def slot_from_count(key:Inv.ItemKey,+count:Nat) -> Inv.Slot:
  Inv.canonical_stack(key,U32.from_nat(count),Nat.is_eq(count,0n))

def moved(slots:List<&2,Inv.Slot>,+source:U32,+target:U32,+key:Inv.ItemKey,counts:Inv.CountMove) -> List<&2,Inv.Slot>:
  Inv.CountMove{remaining,final,moved} = counts
  replace(replace(slots,U32.to_nat(source),slot_from_count(key,remaining)),U32.to_nat(target),slot_from_count(key,final))

def return_target(target:Maybe<&2,U32>,+slots:List<&2,Inv.Slot>,source:U32,key:Inv.ItemKey,+count:U32,limit:U32) -> List<&2,Inv.Slot>:
  match target:
    case Some{+index}:
      +stored = Inv.slot_count(at(slots,U32.to_nat(index)))
      moved(slots,source,index,key,Inv.move_counts(U32.to_nat(count),U32.to_nat(count),U32.to_nat(stored),U32.to_nat(U32.sub(limit,stored))))
    case None{}: slots

def return_source(slot:Inv.Slot,+slots:List<&2,Inv.Slot>,source:U32,+selected:U32,+limit:U32) -> List<&2,Inv.Slot>:
  match slot:
    case Inv.InvEmpty{}: slots
    case Inv.InvStack{+key,count}: return_target(destination(slots,selected,key,limit),slots,source,key,count,limit)

def return_once(+slots:List<&2,Inv.Slot>,+source:U32,selected:U32,limit:U32) -> List<&2,Inv.Slot>:
  return_source(at(slots,U32.to_nat(source)),slots,source,selected,limit)

def return_slot(fuel:Nat,slots:List<&2,Inv.Slot>,+source:U32,+selected:U32,+limit:U32) -> List<&2,Inv.Slot>:
  match fuel:
    case 0n: slots
    case 1n+n: return_slot(n,return_once(slots,source,selected,limit),source,selected,limit)

def return_known(known:Maybe<&2,Inv.ItemMetadata>,slots:List<&2,Inv.Slot>,source:U32,selected:U32) -> List<&2,Inv.Slot>:
  match known:
    case None{}: slots
    case Some{Inv.ItemMetadata{key,limit}}: return_slot(38n,slots,source,selected,limit)

def return_key(slot:Inv.Slot,catalog:D.Catalog,slots:List<&2,Inv.Slot>,source:U32,selected:U32) -> List<&2,Inv.Slot>:
  match slot:
    case Inv.InvEmpty{}: slots
    case Inv.InvStack{key,count}: return_known(D.metadata(catalog,key),slots,source,selected)

def return_at(+slots:List<&2,Inv.Slot>,catalog:D.Catalog,+source:U32,selected:U32) -> List<&2,Inv.Slot>:
  return_key(at(slots,U32.to_nat(source)),catalog,slots,source,selected)

def craft_return(left:Nat,+source:U32,slots:List<&2,Inv.Slot>,+catalog:D.Catalog,+selected:U32) -> List<&2,Inv.Slot>:
  match left:
    case 0n: slots
    case 1n+n: craft_return(n,U32.add(source,1),return_at(slots,catalog,source,selected),catalog,selected)

def known_valid(slot:Inv.Slot,known:Maybe<&2,Inv.ItemMetadata>) -> Bool:
  match known:
    case None{}: False{}
    case Some{metadata}: Inv.slot_valid(slot,metadata)

def slot_valid(slot:Inv.Slot,+catalog:D.Catalog) -> Bool:
  match slot:
    case Inv.InvEmpty{}: True{}
    case Inv.InvStack{+key,count}: known_valid(slot,D.metadata(catalog,key))

def valid_slots(left:Nat,slots:List<&2,Inv.Slot>,+catalog:D.Catalog) -> Bool:
  match left slots:
    case 0n Nil{}: True{}
    case 1n+n slot <> rest: slot_valid(slot,catalog) && valid_slots(n,rest,catalog)
    case _ _: False{}

def temporary_empty(slots:List<&2,Inv.Slot>) -> Bool:
  match slots:
    case Nil{}: True{}
    case Inv.InvEmpty{} <> rest: temporary_empty(rest)
    case _: False{}

def skip(left:Nat,slots:List<&2,Inv.Slot>) -> List<&2,Inv.Slot>:
  match left slots:
    case 0n _: slots
    case 1n+n slot <> rest: skip(n,rest)
    case _ _: []

def keys(slots:List<&2,Inv.Slot>) -> List<&2,Inv.ItemKey>:
  match slots:
    case Nil{}: []
    case Inv.InvEmpty{} <> rest: keys(rest)
    case Inv.InvStack{key,count} <> rest: key <> keys(rest)

def count_key(+key:Inv.ItemKey,slots:List<&2,Inv.Slot>) -> Nat:
  match slots:
    case Nil{}: 0n
    case Inv.InvEmpty{} <> rest: count_key(key,rest)
    case Inv.InvStack{other,count} <> rest:
      Nat.add(N.choose(Nat,U32.to_nat(count),0n,Inv.key_equal(key,other)),count_key(key,rest))

def ledger(queries:List<&2,Inv.ItemKey>,+slots:List<&2,Inv.Slot>) -> List<&2,Nat>:
  match queries:
    case Nil{}: []
    case key <> rest: count_key(key,slots) <> ledger(rest,slots)

def counts_equal(before:List<&2,Nat>,after:List<&2,Nat>) -> Bool:
  match before after:
    case Nil{} Nil{}: True{}
    case a <> left b <> right: Nat.is_eq(a,b) && counts_equal(left,right)
    case _ _: False{}

def reviewed(+before:List<&2,Inv.Slot>,+after:List<&2,Inv.Slot>,catalog:D.Catalog) -> Plan:
  +queries = List.append(&2,Inv.ItemKey,keys(before),keys(after))
  Plan{after,ledger(queries,before),ledger(queries,after),temporary_empty(skip(43n,after)),valid_slots(48n,after,catalog)}

def plan_checked(valid:Bool,+slots:List<&2,Inv.Slot>,+selected:U32,+catalog:D.Catalog) -> Plan:
  match valid:
    case False{}: Plan{slots,[],[],False{},False{}}
    case True{}: reviewed(slots,craft_return(4n,43,return_at(slots,catalog,47,selected),catalog,selected),catalog)

def plan(+slots:List<&2,Inv.Slot>,+selected:U32,+catalog:D.Catalog) -> Plan:
  plan_checked(U32.is_lt(selected,9) && valid_slots(48n,slots,catalog),slots,selected,catalog)

def admitted(plan:Plan) -> Bool:
  Plan{slots,before,after,returned,valid} = plan
  returned && valid && counts_equal(before,after)

def before_counts(plan:Plan) -> List<&2,Nat>:
  Plan{slots,before,after,returned,valid} = plan
  before

def after_counts(plan:Plan) -> List<&2,Nat>:
  Plan{slots,before,after,returned,valid} = plan
  after

def slots(plan:Plan) -> List<&2,Inv.Slot>:
  Plan{slots,before,after,returned,valid} = plan
  slots
