import Base
import ./inventory.bend as Inv
import ./player_inventory.bend as I
import ./resource_client_wire.bend as W
import ./player_crafting_authority.bend as Authority

# A prospective wire operation owns an independent copy of every Array leaf.
# The complete old player owner survives until the actual reply encoder accepts
# the candidate. Profile, raw status, derived result, logical length and hidden
# backing cells retain their exact values; this is not a public projection.
def cloned(+length:U32,+selected:U32,+abilities:I.Abilities,+profile:I.Profile,
    result:Array<Inv.Slot> & Array<Inv.Slot>) -> I.State & I.State:
  (original,candidate) = result
  (I.State{Inv.Inventory{original,length},selected,abilities,profile},
    I.State{Inv.Inventory{candidate,length},selected,abilities,profile})

def clone(owner:I.State) -> I.State & I.State:
  I.State{Inv.Inventory{array,length},selected,abilities,profile} = owner
  cloned(length,selected,abilities,profile,Array.clone(Inv.Slot,array))

def prepared(result:I.State & I.State) -> I.State & I.State:
  (original,candidate) = result
  (candidate,original)

# S.inventory_query can install the candidate and return the original as its
# rollback value without duplicating any Session/world/Shell owner.
def prepare(owner:I.State) -> I.State & I.State:
  prepared(clone(owner))

def geometry_checked(selected:U32,abilities:I.Abilities,profile:I.Profile,
    result:Inv.Inventory & Bool) -> I.State & Bool:
  (inventory,valid) = result
  (I.State{inventory,selected,abilities,profile},valid)

# The actor's sole player menu has48 logical cells in its64-cell backing tree.
# Use the existing actual authority shape guard before any indexed operation.
def geometry(owner:I.State) -> I.State & Bool:
  I.State{inventory,selected,abilities,profile} = owner
  geometry_checked(selected,abilities,profile,Authority.inventory_shape(inventory,48,6n))

# A refused malformed tree must be observed structurally, never by indexing.
# Authority.inventory_snapshot preserves its tree and reads actual leaf order.
def inspect(owner:I.State) -> I.State & I.MenuSnapshot:
  I.State{inventory,+selected,+abilities,+profile} = owner
  I.menu_inspected(selected,abilities,profile,Authority.inventory_snapshot(inventory))

# A may carry the immutable new recipe context alongside its complete reply.
# Callers keep the old context until Done and retain it on Fail. No Session,
# world/runtime owner or lease is duplicated by this inventory transaction.
def finish(-A:Data,original:I.State,candidate:I.State,value:A,
    encoding:Result<&2,&2,String,String>) -> I.State & Result<&2,&2,String,A>:
  match encoding:
    case Fail{message}: (original,Fail{message})
    case Done{text}: (candidate,Done{value})

def checked(-A:Data,original:I.State,result:I.State & A,reply:A -> W.Reply) -> I.State & Result<&2,&2,String,A>:
  (candidate,+value) = result
  finish(A,original,candidate,value,W.encode_reply(reply(value)))

def run_cloned(-A:Data,owners:I.State & I.State,operation:I.State -> I.State & A,reply:A -> W.Reply) -> I.State & Result<&2,&2,String,A>:
  (original,candidate) = owners
  checked(A,original,operation(candidate),reply)

def run(-A:Data,owner:I.State,operation:I.State -> I.State & A,reply:A -> W.Reply) -> I.State & Result<&2,&2,String,A>:
  run_cloned(A,clone(owner),operation,reply)
