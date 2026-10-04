import Base
import ./inventory.bend as inventory
import ./random.bend as R
import ./vanilla_entity_fields.bend as V
import ./cooking_world_store.bend as Store
import ./cooking_effect_entities_model.bend as E
import ./cooking_effect_entities.bend as D
import ./cooking_effect_entities_spawn.bend as S
import ./cooking_effect_entities_query.bend as Q
import ./cooking_effect_entities_xp.bend as X

law refused_spawn_retains_complete_actual_owner:
  for state:E.State
  for error:E.Error
  {E.commit(state,Fail{error}) == (state,Fail{error}) : E.State & Result<&2,&2,E.Error,List<&2,R.Bits64>>}
def refused_spawn_retains_complete_actual_owner(state,error): {==}

law delivery_refusal_retains_failed_effect_and_ordered_suffix:
  for effect:Store.Effect
  for rest:List<&2,Store.Effect>
  for times:List<&2,R.Bits64>
  for state:E.State
  for error:E.Error
  for next:E.State -> List<&2,R.Bits64> -> E.State & D.Outcome
  {D.delivered(effect,rest,times,(state,Fail{error}),next) == (state,D.Outcome{effect <> rest,Fail{error},times}) : E.State & D.Outcome}
def delivery_refusal_retains_failed_effect_and_ordered_suffix(effect,rest,times,state,error,next): {==}

law constructor_entropy_missing_cannot_install_an_item:
  for dimension:String
  for point:V.Vec3
  for velocity:V.Vec3
  for item:inventory.Slot
  for level:R.Source
  for unique:R.Bits64
  for cursor:U32
  for order:Nat
  for records:List<&2,E.Record>
  for id:U32
  {S.item_spawn(dimension,point,velocity,item,E.View{level,unique,cursor,order,records},[],id) == Fail{E.EntropyNeeded{1n}} : Result<&2,&2,E.Error,E.Plan>}
def constructor_entropy_missing_cannot_install_an_item(dimension,point,velocity,item,level,unique,cursor,order,records,id): {==}

law constructor_entropy_missing_cannot_install_an_orb:
  for dimension:String
  for point:V.Vec3
  for value:U32
  for level:R.Source
  for unique:R.Bits64
  for cursor:U32
  for order:Nat
  for records:List<&2,E.Record>
  for id:U32
  {X.orb_spawn(dimension,point,value,E.View{level,unique,cursor,order,records},[],id) == Fail{E.EntropyNeeded{1n}} : Result<&2,&2,E.Error,E.Plan>}
def constructor_entropy_missing_cannot_install_an_orb(dimension,point,value,level,unique,cursor,order,records,id): {==}

law zero_award_does_not_spend_constructor_entropy_or_rng:
  for Geometry:Data
  for place:Geometry -> String -> V.Vec3 -> Result<&2,&2,E.Error,V.Vec3>
  for geometry:Geometry
  for context:E.Context
  for dimension:String
  for point:V.Vec3
  for view:E.View
  for times:List<&2,R.Bits64>
  {X.award_loop(~Geometry,~place,0n,geometry,context,dimension,point,0,view,times) == Done{E.Plan{view,times}} : Result<&2,&2,E.Error,E.Plan>}
def zero_award_does_not_spend_constructor_entropy_or_rng(Geometry,place,geometry,context,dimension,point,view,times): {==}

law zero_fragment_count_does_not_spend_constructor_entropy_or_rng:
  for context:E.Context
  for dimension:String
  for point:V.Vec3
  for key:inventory.ItemKey
  for view:E.View
  for times:List<&2,R.Bits64>
  {S.drop_loop(0n,context,dimension,point,key,0,view,times) == Done{E.Plan{view,times}} : Result<&2,&2,E.Error,E.Plan>}
def zero_fragment_count_does_not_spend_constructor_entropy_or_rng(context,dimension,point,key,view,times): {==}

law merging_orbs_resets_age_and_increments_count:
  for common:E.Common
  for value:U32
  for age:U32
  for health:U32
  for count:U32
  for following:Maybe<&2,E.Uuid>
  {Q.update_choice(E.Orb{common,value,age,health,count,following},True{}) == E.Orb{common,value,0,health,U32.inc(count),following} : E.Record}
def merging_orbs_resets_age_and_increments_count(common,value,age,health,count,following): {==}

law orb_merge_keeps_level_rng_factory_id_cursor_and_entropy:
  for level:R.Source
  for unique:R.Bits64
  for cursor:U32
  for order:Nat
  for records:List<&2,E.Record>
  for id:U32
  for times:List<&2,R.Bits64>
  {X.merged(E.View{level,unique,cursor,order,records},id,times) == Done{E.Plan{E.View{level,unique,cursor,order,Q.update(records,id)},times}} : Result<&2,&2,E.Error,E.Plan>}
def orb_merge_keeps_level_rng_factory_id_cursor_and_entropy(level,unique,cursor,order,records,id,times): {==}
