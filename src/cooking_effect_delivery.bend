import Base
import ./cooking_world_store.bend as Store

# This consumer receives only released effects: the Sidecar already applied
# every OwnerReset to its physical Details/incarnation owner. It cannot grant
# an item/XP/RNG or notification owner that the live actor does not possess.
type Outcome is Data:
  Outcome{pending:List<&2,Store.Effect>,status:Result<&2,&2,String,Unit>}

def refused(effects:List<&2,Store.Effect>,owner:String) -> Outcome:
  Outcome{effects,Fail{"cooking-effects:" ++ owner ++ "-owner-required"}}

# Preserve the first unsupported effect and its entire ordered suffix. Empty
# Drop calls also require the real level RNG owner; they are not no-ops.
def deliver(effects:List<&2,Store.Effect>) -> Outcome:
  match effects:
    case Nil{}: Outcome{[],Done{Unit{}}}
    case Store.OwnerReset{position} <> rest: deliver(rest)
    case Store.BlockUpdate{position,0n} <> rest: deliver(rest)
    case Store.BlockChange{position,0n} <> rest: deliver(rest)
    case Store.Drop{position,slot,item} <> rest:
      refused(Store.Drop{position,slot,item} <> rest,"item-entity-and-level-rng")
    case Store.Experience{position,request} <> rest:
      refused(Store.Experience{position,request} <> rest,"xp-orb-and-level-rng")
    case Store.Dirty{position} <> rest:
      refused(Store.Dirty{position} <> rest,"block-entity-and-comparator-publisher")
    case Store.BlockUpdate{position,1n+count} <> rest:
      refused(Store.BlockUpdate{position,1n+count} <> rest,"block-update-publisher")
    case Store.BlockChange{position,1n+count} <> rest:
      refused(Store.BlockChange{position,1n+count} <> rest,"game-event-publisher")
