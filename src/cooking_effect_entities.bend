import Base
import ./core.bend as C
import ./random.bend as R
import ./vanilla_entity_fields.bend as V
import ./cooking_world_store.bend as Store
import ./cooking_effect_entities_model.bend as E
import ./cooking_effect_entities_spawn.bend as S
import ./cooking_effect_entities_xp.bend as X

# This facade consumes actual items/orbs. Other released effects belong to the
# Sidecar's block-entity/comparator/block-update/game-event publishers.
type Outcome is Data:
  Outcome{pending:List<&2,Store.Effect>,status:Result<&2,&2,E.Error,Unit>,remaining_times:List<&2,R.Bits64>}
def plan(~Geometry:Data,~place:Geometry -> String -> V.Vec3 -> Result<&2,&2,E.Error,V.Vec3>,
    geometry:Geometry,context:E.Context,effect:Store.Effect,view:E.View,times:List<&2,R.Bits64>) -> Result<&2,&2,E.Error,E.Plan>:
  match effect:
    case Store.Drop{position,slot,item}: S.drop(context,position,item,view,times)
    case Store.Experience{position,request}: X.experience(~Geometry,~place,geometry,context,position,request,view,times)
    case Store.OwnerReset{position}: Done{E.Plan{view,times}}
    case Store.BlockUpdate{position,0n}: Done{E.Plan{view,times}}
    case Store.BlockChange{position,0n}: Done{E.Plan{view,times}}
    case Store.Dirty{position}: Fail{E.Refused{"cooking-entities:block-entity-and-comparator-publisher-required"}}
    case Store.OwnedDirty{source}: Fail{E.Refused{"cooking-entities:publication-owner-required"}}
    case Store.BlockUpdate{position,1n+count}: Fail{E.Refused{"cooking-entities:block-update-publisher-required"}}
    case Store.BlockChange{position,1n+count}: Fail{E.Refused{"cooking-entities:game-event-publisher-required"}}
def planned(~Geometry:Data,~place:Geometry -> String -> V.Vec3 -> Result<&2,&2,E.Error,V.Vec3>,
    geometry:Geometry,context:E.Context,effect:Store.Effect,times:List<&2,R.Bits64>,snapshot:E.State & E.View) -> E.State & Result<&2,&2,E.Error,List<&2,R.Bits64>>:
  (state,view) = snapshot
  E.commit(state,plan(~Geometry,~place,geometry,context,effect,view,times))
# Atomic per-effect mutation, including all fragments/RNG/UUIDs/IDs. A refusal
# returns the complete original entity owner. Entropy tickets are supplied by
# the clock boundary; they are consumed only by actual new constructors.
def apply(~Geometry:Data,~place:Geometry -> String -> V.Vec3 -> Result<&2,&2,E.Error,V.Vec3>,
    geometry:Geometry,context:E.Context,effect:Store.Effect,state:E.State,times:List<&2,R.Bits64>) -> E.State & Result<&2,&2,E.Error,List<&2,R.Bits64>>:
  planned(~Geometry,~place,geometry,context,effect,times,E.inspect(state))
def delivered(effect:Store.Effect,rest:List<&2,Store.Effect>,times:List<&2,R.Bits64>,
    result:E.State & Result<&2,&2,E.Error,List<&2,R.Bits64>>,
    next:E.State -> List<&2,R.Bits64> -> E.State & Outcome) -> E.State & Outcome:
  (state,status) = result
  match status:
    case Fail{error}: (state,Outcome{effect <> rest,Fail{error},times})
    case Done{remaining}: next(state)(remaining)
# Commit only the successfully consumed ordered prefix; preserve the failing
# effect and exact suffix, so a live retry cannot duplicate an earlier spawn.
def deliver(~Geometry:Data,~place:Geometry -> String -> V.Vec3 -> Result<&2,&2,E.Error,V.Vec3>,
    +geometry:Geometry,+context:E.Context,effects:List<&2,Store.Effect>,state:E.State,+times:List<&2,R.Bits64>) -> E.State & Outcome:
  match effects:
    case Nil{}: (state,Outcome{[],Done{Unit{}},times})
    case +effect <> +rest:
      delivered(effect,rest,times,apply(~Geometry,~place,geometry,context,effect,state,times),
        state => remaining => deliver(~Geometry,~place,geometry,context,rest,state,remaining))
