import Base
import ./inventory.bend as I
import ./cooking_effect_entities_model.bend as E
import ./item_entity_pickup_model.bend as M

def pops(values:List<&2,M.Pop>) -> List<&2,M.Publication>:
  match values:
    case Nil{}: []
    case M.Pop{slot,duration} <> rest: M.PopTime{slot,duration} <> pops(rest)
def optional(yes:Bool,value:M.Publication) -> List<&2,M.Publication>:
  match yes:
    case False{}: []
    case True{}: [value]
def resolved(valid:Bool,+owner:E.Uuid,owner_server:Bool,+receiver:E.Uuid,receiver_server:Bool,+item:I.Slot) -> Result<&2,&2,M.Error,List<&2,M.Publication>>:
  match valid:
    case False{}: Fail{M.Refused{"pickup thrower resolution does not match actual stored UUID"}}
    case True{}: Done{List.append(&2,M.Publication,optional(owner_server,M.ThrownPickedUpByEntity{owner,receiver,item}),optional(receiver_server,M.ThrownPickedUpByPlayer{receiver,owner,item}))}
def criteria(thrower:Maybe<&2,E.Uuid>,resolution:M.OwnerResolution,receiver:E.Uuid,server:Bool,item:I.Slot) -> Result<&2,&2,M.Error,List<&2,M.Publication>>:
  match thrower resolution:
    case None{} _: Done{[]}
    case Some{stored} M.UnknownOwner{}: Fail{M.Refused{"successful pickup requires actual world thrower lookup"}}
    case Some{stored} M.KnownAbsent{}: Done{[]}
    case Some{stored} M.ResolvedOwner{+owner,owner_server}: resolved(M.same_uuid(stored,owner),owner,owner_server,receiver,server,item)
def completed(+admission:M.Admission,common:E.Common,thrower:Maybe<&2,E.Uuid>,+item:I.Slot,+count:U32,discard:Bool,values:List<&2,M.Pop>) -> Result<&2,&2,M.Error,List<&2,M.Publication>>:
  M.Admission{admitted,server_side,dimension,+player_id,+uuid,+server,resolution} = admission
  E.Common{d,+id,most,least,random,fields,tick,first,removed,accessible,order} = common
  match item:
    case I.InvStack{I.ItemKey{item_id,components},current_count}:
      do Result<&2,&2,M.Error,List<&2,M.Publication>>:
        owner_events : List<&2,M.Publication> <- criteria(thrower,resolution,uuid,server,item)
        return List.append(&2,M.Publication,pops(values),List.append(&2,M.Publication,
          optional(Bool.not(removed),M.TakePacket{id,player_id,count}),List.append(&2,M.Publication,
          optional(server,M.MenuBroadcast{player_id}),List.append(&2,M.Publication,
          optional(discard,M.EntityDiscard{id}),M.PickupStat{uuid,item_id,count} <> owner_events))))
    case I.InvEmpty{}: Fail{M.Refused{"successful pickup requires a nonempty registered stack"}}
