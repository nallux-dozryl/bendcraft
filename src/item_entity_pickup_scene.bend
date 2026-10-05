import Base
import ./random.bend as random
import ./player_inventory.bend as P
import ./cooking_effect_entities_model.bend as E
import ./item_entity_pickup_model.bend as M
import ./item_entity_pickup.bend as Pickup

# This joins the already-real spawn owner: no parallel entity list or world.
def prepend(entity:E.Entity,result:List<&1,E.Entity> & P.State & Result<&2,&2,M.Error,M.Effects>) -> List<&1,E.Entity> & P.State & Result<&2,&2,M.Error,M.Effects>:
  (entities,player,status) = result
  (entity <> entities,player,status)
def touched(rest:List<&1,E.Entity>,result:E.Entity & P.State & Result<&2,&2,M.Error,M.Effects>) -> List<&1,E.Entity> & P.State & Result<&2,&2,M.Error,M.Effects>:
  (entity,player,status) = result
  (entity <> rest,player,status)
def found(yes:Bool,admission:M.Admission,context:M.Context,entity:E.Entity,rest:List<&1,E.Entity>,player:P.State,
    next:List<&1,E.Entity> -> P.State -> List<&1,E.Entity> & P.State & Result<&2,&2,M.Error,M.Effects>) -> List<&1,E.Entity> & P.State & Result<&2,&2,M.Error,M.Effects>:
  match yes:
    case False{}: prepend(entity,next(rest)(player))
    case True{}: touched(rest,Pickup.touch(admission,context,entity,player))
def exhausted(entities:List<&1,E.Entity>,player:P.State) -> List<&1,E.Entity> & P.State & Result<&2,&2,M.Error,M.Effects>:
  (entities,player,Fail{M.BudgetExhausted{}})
def find(left:Nat,+admission:M.Admission,+context:M.Context,+wanted:U32,entities:List<&1,E.Entity>,player:P.State) -> List<&1,E.Entity> & P.State & Result<&2,&2,M.Error,M.Effects>:
  match left entities:
    case _ Nil{}: ([],player,Fail{M.Refused{"pickup entity ID is absent from the actual owner"}})
    case 0n values: exhausted(values,player)
    case 1n+rest E.Entity{+record} <> tail:
      found(U32.is_eq(wanted,E.record_id(record)),admission,context,E.Entity{record},tail,player,
        values => player => find(rest,admission,context,wanted,values,player))
def joined(level:random.Source,uniquifier:random.Bits64,cursor:U32,order:Nat,result:List<&1,E.Entity> & P.State & Result<&2,&2,M.Error,M.Effects>) -> E.State & P.State & Result<&2,&2,M.Error,M.Effects>:
  (entities,player,status) = result
  (E.State{level,uniquifier,cursor,order,entities},player,status)
# Removed entities retain their record until the actor's entity-removal callback;
# preserving list order also preserves the spawn owner's section-order metadata.
def touch_id(admission:M.Admission,context:M.Context,wanted:U32,state:E.State,player:P.State,scan_budget:Nat) -> E.State & P.State & Result<&2,&2,M.Error,M.Effects>:
  E.State{level,uniquifier,cursor,order,entities} = state
  joined(level,uniquifier,cursor,order,find(scan_budget,admission,context,wanted,entities,player))
