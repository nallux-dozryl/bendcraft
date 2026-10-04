import Base
import ./inventory.bend as Inv
import ./player_item_definitions.bend as D
import ./player_inventory_return.bend as Return
import ./nbt.bend as N

# Planning values are complete immutable observations. The production actor
# retains the sole Array owner until this complete per-item guard admits commit.
type Plan is Data:
  Plan{slots:List<&2,Inv.Slot>,before:List<&2,Nat>,after:List<&2,Nat>,valid:Bool,changed:Bool,message:String}

def slot_equal(a:Inv.Slot,b:Inv.Slot) -> Bool:
  match a b:
    case Inv.InvEmpty{} Inv.InvEmpty{}: True{}
    case Inv.InvStack{ak,ac} Inv.InvStack{bk,bc}: Inv.key_equal(ak,bk) && U32.is_eq(ac,bc)
    case _ _: False{}

def slots_equal(a:List<&2,Inv.Slot>,b:List<&2,Inv.Slot>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case av <> ar bv <> br: slot_equal(av,bv) && slots_equal(ar,br)
    case _ _: False{}

def reviewed(+before:List<&2,Inv.Slot>,+after:List<&2,Inv.Slot>,+catalog:D.Catalog,allowed:Bool,message:String) -> Plan:
  +queries = List.append(&2,Inv.ItemKey,Return.keys(before),Return.keys(after))
  Plan{after,Return.ledger(queries,before),Return.ledger(queries,after),
    allowed && Return.valid_slots(48n,before,catalog) && Return.valid_slots(48n,after,catalog),
    Bool.not(slots_equal(before,after)),message}

def untouched(+slots:List<&2,Inv.Slot>,catalog:D.Catalog) -> Plan:
  reviewed(slots,slots,catalog,True{},"")

def refused(+slots:List<&2,Inv.Slot>,catalog:D.Catalog,message:String) -> Plan:
  reviewed(slots,slots,catalog,False{},message)

def equipment_matches(found:Maybe<&2,U32>,index:U32) -> Bool:
  match found:
    case None{}: False{}
    case Some{target}: U32.is_eq(target,index)

def placeable(+index:U32,key:Inv.ItemKey) -> Bool:
  Inv.ItemKey{id,components} = key
  N.choose(Bool,equipment_matches(D.equipment(id),index),True{},U32.is_ge(index,36) && U32.is_lt(index,40))

def slot_limit(+index:U32,limit:U32) -> U32:
  N.choose(U32,1,limit,U32.is_ge(index,36) && U32.is_lt(index,40))

def exchanged(+slots:List<&2,Inv.Slot>,+index:U32,+button:U32,catalog:D.Catalog) -> Plan:
  reviewed(slots,Return.replace(Return.replace(slots,U32.to_nat(index),Return.at(slots,U32.to_nat(button))),
    U32.to_nat(button),Return.at(slots,U32.to_nat(index))),catalog,True{},"")

def moved_into_empty(+slots:List<&2,Inv.Slot>,index:U32,button:U32,key:Inv.ItemKey,+count:U32,limit:U32,catalog:D.Catalog) -> Plan:
  reviewed(slots,Return.moved(slots,button,index,key,Inv.move_counts(U32.to_nat(count),U32.to_nat(count),0n,U32.to_nat(limit))),catalog,True{},"")

def displaced_finished(empty:Bool,+before:List<&2,Inv.Slot>,returned:List<&2,Inv.Slot>,catalog:D.Catalog) -> Plan:
  match empty:
    case False{}: refused(before,catalog,"swap needs real drop or creative-discard ownership for the displaced item")
    case True{}: reviewed(before,List.take(&2,Inv.Slot,returned,48n),catalog,True{},"")

def pending_empty(slot:Inv.Slot) -> Bool:
  match slot:
    case Inv.InvEmpty{}: True{}
    case _: False{}

def displaced_inspected(before:List<&2,Inv.Slot>,+returned:List<&2,Inv.Slot>,catalog:D.Catalog) -> Plan:
  displaced_finished(pending_empty(Return.at(returned,48n)),before,returned,catalog)

def displaced_returned(+before:List<&2,Inv.Slot>,after:List<&2,Inv.Slot>,selected:U32,+catalog:D.Catalog) -> Plan:
  displaced_inspected(before,Return.return_at(after,catalog,48,selected),catalog)

# The49th immutable planning cell denotes only the displaced stack while the
# actual48-cell Array is untouched. It is never an owned UI cursor/backing slot.
def clipped_with_displaced(+slots:List<&2,Inv.Slot>,+index:U32,button:U32,key:Inv.ItemKey,+count:U32,limit:U32,selected:U32,catalog:D.Catalog) -> Plan:
  displaced_returned(slots,List.append(&2,Inv.Slot,Return.moved(slots,button,index,key,
    Inv.move_counts(U32.to_nat(count),U32.to_nat(count),0n,U32.to_nat(limit))),[Return.at(slots,U32.to_nat(index))]),selected,catalog)

def occupied_sized(clipped:Bool,slots:List<&2,Inv.Slot>,index:U32,button:U32,key:Inv.ItemKey,count:U32,limit:U32,selected:U32,catalog:D.Catalog) -> Plan:
  match clipped:
    case False{}: exchanged(slots,index,button,catalog)
    case True{}: clipped_with_displaced(slots,index,button,key,count,limit,selected,catalog)

def target_sized(target:Inv.Slot,slots:List<&2,Inv.Slot>,index:U32,button:U32,key:Inv.ItemKey,+count:U32,+limit:U32,selected:U32,catalog:D.Catalog) -> Plan:
  match target:
    case Inv.InvEmpty{}: moved_into_empty(slots,index,button,key,count,limit,catalog)
    case Inv.InvStack{old_key,old_count}: occupied_sized(U32.is_gt(count,limit),slots,index,button,key,count,limit,selected,catalog)

def known_limit(known:Maybe<&2,Inv.ItemMetadata>,+slots:List<&2,Inv.Slot>,+index:U32,button:U32,key:Inv.ItemKey,count:U32,selected:U32,catalog:D.Catalog) -> Plan:
  match known:
    case None{}: refused(slots,catalog,"swap item is outside the saved default-item profile")
    case Some{Inv.ItemMetadata{known,limit}}: target_sized(Return.at(slots,U32.to_nat(index)),slots,index,button,key,count,slot_limit(index,limit),selected,catalog)

def placement_allowed(allowed:Bool,slots:List<&2,Inv.Slot>,index:U32,button:U32,+key:Inv.ItemKey,count:U32,selected:U32,+catalog:D.Catalog) -> Plan:
  match allowed:
    case False{}: untouched(slots,catalog)
    case True{}: known_limit(D.metadata(catalog,key),slots,index,button,key,count,selected,catalog)

def source_read(source:Inv.Slot,slots:List<&2,Inv.Slot>,+index:U32,button:U32,selected:U32,catalog:D.Catalog) -> Plan:
  match source:
    case Inv.InvEmpty{}: exchanged(slots,index,button,catalog)
    case Inv.InvStack{+key,count}: placement_allowed(placeable(index,key),slots,index,button,key,count,selected,catalog)

def distinct(same:Bool,+slots:List<&2,Inv.Slot>,index:U32,+button:U32,selected:U32,catalog:D.Catalog) -> Plan:
  match same:
    case True{}: untouched(slots,catalog)
    case False{}: source_read(Return.at(slots,U32.to_nat(button)),slots,index,button,selected,catalog)

def button_allowed(allowed:Bool,slots:List<&2,Inv.Slot>,+index:U32,+button:U32,selected:U32,catalog:D.Catalog) -> Plan:
  match allowed:
    case False{}: untouched(slots,catalog)
    case True{}: distinct(U32.is_eq(index,button),slots,index,button,selected,catalog)

def valid_input(valid:Bool,slots:List<&2,Inv.Slot>,index:U32,+button:U32,selected:U32,catalog:D.Catalog) -> Plan:
  match valid:
    case False{}: refused(slots,catalog,"swap requires a valid complete owned inventory and menu slot")
    case True{}: button_allowed(U32.is_lt(button,9) || U32.is_eq(button,40),slots,index,button,selected,catalog)

def plan(+slots:List<&2,Inv.Slot>,+selected:U32,+index:U32,button:U32,+catalog:D.Catalog) -> Plan:
  valid_input(Return.valid_slots(48n,slots,catalog) && U32.is_lt(selected,9) &&
    (U32.is_lt(index,41) || (U32.is_ge(index,43) && U32.is_lt(index,47))),slots,index,button,selected,catalog)

def admitted(plan:Plan) -> Bool:
  Plan{slots,before,after,valid,changed,message} = plan
  valid && Return.counts_equal(before,after)

def before_counts(plan:Plan) -> List<&2,Nat>:
  Plan{slots,before,after,valid,changed,message} = plan
  before

def after_counts(plan:Plan) -> List<&2,Nat>:
  Plan{slots,before,after,valid,changed,message} = plan
  after

def slots(plan:Plan) -> List<&2,Inv.Slot>:
  Plan{slots,before,after,valid,changed,message} = plan
  slots

def changed(plan:Plan) -> Bool:
  Plan{slots,before,after,valid,changed,message} = plan
  changed

def message(plan:Plan) -> String:
  Plan{slots,before,after,valid,changed,message} = plan
  message
