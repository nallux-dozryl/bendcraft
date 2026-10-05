import Base
import ./inventory.bend as I
import ./player_inventory.bend as P
import ./campfire_authority_items.bend as A
import ./cooking_effect_entities_model.bend as E
import ./item_entity_pickup_model.bend as M
import ./item_entity_pickup_properties.bend as Props
import ./item_entity_pickup_insert.bend as Insert
import ./item_entity_pickup_publications.bend as Pub

def removed(common:E.Common,discard:Bool) -> E.Common:
  E.Common{dimension,id,most,least,random,fields,tick,first,old,accessible,order} = common
  E.Common{dimension,id,most,least,random,fields,tick,first,old || discard,accessible,order}
def changed(record:E.Record,count:U32,discard:Bool) -> E.Record:
  match record:
    case E.Item{common,I.InvStack{key,previous},age,delay,health,thrower,target,bob}: E.Item{removed(common,discard),I.InvStack{key,count},age,delay,health,thrower,target,bob}
    case _: record
def successful(+admission:M.Admission,+record:E.Record,+original:U32,+slots:List<&2,I.Slot>,+remaining:U32,inserted:U32,values:List<&2,M.Pop>) -> Result<&2,&2,M.Error,M.Plan>:
  match record:
    case E.Item{common,I.InvStack{key,old},age,delay,health,thrower,target,bob}:
      +discard = U32.is_zero(remaining)
      +final_count = Bool.pick(U32,discard,original,remaining)
      do Result<&2,&2,M.Error,M.Plan>:
        publications : List<&2,M.Publication> <- Pub.completed(admission,common,thrower,I.InvStack{key,final_count},original,discard,values)
        return M.Plan{changed(record,final_count,discard),slots,M.Effects{True{},inserted,remaining,discard,publications}}
    case _: Fail{M.Refused{"pickup planning requires a nonempty item entity"}}
def inserted(admission:M.Admission,+record:E.Record,original:U32,result:M.Insertion) -> Result<&2,&2,M.Error,M.Plan>:
  M.Insertion{slots,+remaining,inserted,returned,values} = result
  match returned:
    case False{}: Done{M.Plan{changed(record,remaining,False{}),slots,M.Effects{False{},inserted,remaining,False{},Pub.pops(values)}}}
    case True{}: successful(admission,record,original,slots,remaining,inserted,values)
def planned(+admission:M.Admission,context:M.Context,+record:E.Record,+snapshot:P.MenuSnapshot) -> Result<&2,&2,M.Error,M.Plan>:
  M.Context{+items,budget} = context
  match record:
    case E.Item{common,I.InvStack{+key,+count},age,delay,health,thrower,target,bob}:
      P.MenuSnapshot{P.Persisted{P.Snapshot{selected,main,P.Abilities{creative,maybuild}},equipment,status},craft,carried,result,opened,revision} = snapshot
      +slots = P.menu_slots(snapshot)
      do Result<&2,&2,M.Error,M.Plan>:
        M.guarded(U32.is_lt(selected,9),"pickup selected hotbar index is invalid")
        M.string_error(Unit,Props.valid(48n,slots,items))
        properties : M.Properties <- M.string_error(M.Properties,Props.of_key(items,key))
        insertion : M.Insertion <- Insert.insert(properties,slots,selected,count,creative,budget)
        inserted(admission,record,count,insertion)
    case _: Fail{M.Refused{"pickup planning requires a nonempty item entity"}}
def record_count(record:E.Record) -> U32:
  match record:
    case E.Item{common,item,age,delay,health,thrower,target,bob}: I.slot_count(item)
    case _: 0
def empty_plan(+record:E.Record,slots:List<&2,I.Slot>) -> Result<&2,&2,M.Error,M.Plan>:
  Done{M.Plan{record,slots,M.no_effects(record_count(record))}}
def candidate(admission:M.Admission,context:M.Context,+record:E.Record,+snapshot:P.MenuSnapshot) -> Result<&2,&2,M.Error,M.Plan>:
  match record:
    case E.Item{common,I.InvEmpty{},age,delay,health,thrower,target,bob}: empty_plan(record,P.menu_slots(snapshot))
    case E.Item{common,I.InvStack{key,0},age,delay,health,thrower,target,bob}: empty_plan(record,P.menu_slots(snapshot))
    case E.Item{common,I.InvStack{key,count},age,delay,health,thrower,target,bob}: planned(admission,context,record,snapshot)
    case _: Fail{M.Refused{"item pickup requires an actual item entity"}}
def active(admission:M.Admission,record:E.Record) -> Bool:
  M.Admission{admitted,server_side,dimension,player_id,+uuid,server,resolution} = admission
  match record:
    case E.Item{common,item,age,delay,health,thrower,target,bob}: server_side && U32.is_zero(delay) && M.target(target,uuid)
    case _: False{}
def inspected(admission:M.Admission,context:M.Context,+record:E.Record,result:P.State & P.MenuSnapshot) -> E.Entity & P.State & Result<&2,&2,M.Error,M.Effects>:
  (player,snapshot) = result
  M.committed(E.Entity{record},player,candidate(admission,context,record,snapshot))
def inactive(+record:E.Record,player:P.State) -> E.Entity & P.State & Result<&2,&2,M.Error,M.Effects>:
  (E.Entity{record},player,Done{M.no_effects(record_count(record))})
def dispatched(allowed:Bool,admission:M.Admission,context:M.Context,+record:E.Record,player:P.State) -> E.Entity & P.State & Result<&2,&2,M.Error,M.Effects>:
  match allowed:
    case False{}: inactive(record,player)
    case True{}: inspected(admission,context,record,P.menu_inspect(player))
def admitted(valid:Bool,+admission:M.Admission,context:M.Context,+record:E.Record,player:P.State) -> E.Entity & P.State & Result<&2,&2,M.Error,M.Effects>:
  match valid:
    case False{}: (E.Entity{record},player,Fail{M.Refused{"item touch was not authoritatively admitted in the entity dimension"}})
    case True{}: dispatched(active(admission,record),admission,context,record,player)
def dimension_matches(+dimension:String,common:E.Common) -> Bool:
  E.Common{stored,id,most,least,random,fields,tick,first,removed,accessible,order} = common
  String.eq(dimension,stored)
def matches(admission:M.Admission,record:E.Record) -> Bool:
  M.Admission{valid,server_side,dimension,player_id,uuid,server,resolution} = admission
  valid && dimension_matches(dimension,E.common(record))
# Reads retain the actual inventory Array. Only an entirely admitted candidate
# is installed; any refusal retains both complete affine owners.
def touch(+admission:M.Admission,context:M.Context,entity:E.Entity,player:P.State) -> E.Entity & P.State & Result<&2,&2,M.Error,M.Effects>:
  E.Entity{+record} = entity
  admitted(matches(admission,record),admission,context,record,player)
