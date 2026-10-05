import Base
import ./item_entity_tick.bend as Tick
import ./item_entity_tick_model.bend as T
import ./item_entity_tick_fields.bend as U
import ./item_entity_tick_merge.bend as M
import ./item_entity_tick_scene.bend as Scene
import ./item_entity_tick_world.bend as World
import ./cooking_effect_entities_model.bend as E
import ./inventory.bend as I
import ./random.bend as R
import ./vanilla_entity_fields.bend as V
import ./geometry.bend as A
import ./cooking_effect_geometry.bend as G
import ./support.bend as S
import ./item_entity_tick_motion.bend as Motion
import ./game.bend as Game
import ./slab_collision.bend as Slab

law refused_tick_returns_complete_entity_and_runtime_owner:
  for owner:T.Owner
  for error:T.Error
  {Tick.committed(owner,Fail{error}) == (owner,Fail{error}) : T.Owner & Result<&2,&2,T.Error,List<&2,T.Publication>>}
def refused_tick_returns_complete_entity_and_runtime_owner(owner,error): {==}
law refused_scene_returns_complete_world_rng_entity_list_and_runtime_owner:
  for state:T.State
  for view:E.View
  for runtimes:List<&2,T.RuntimeEntry>
  for error:T.Error
  for sound:Maybe<&2,R.Source>
  {Scene.committed(state,view,runtimes,Fail{error},sound) == (state,Fail{error}) : T.State & Result<&2,&2,T.Error,List<&2,T.Publication>>}
def refused_scene_returns_complete_world_rng_entity_list_and_runtime_owner(state,view,runtimes,error,sound):
  match view:
    case E.View{level,unique,cursor,order,records}: {==}
law sound_refusal_keeps_the_complete_current_and_neighbour_owners:
  for state:T.State
  for view:E.View
  for runtimes:List<&2,T.RuntimeEntry>
  for error:T.Error
  {Scene.accepted(state,view,runtimes,Fail{error}) == (state,Fail{error}) : T.State & Result<&2,&2,T.Error,List<&2,T.Publication>>}
def sound_refusal_keeps_the_complete_current_and_neighbour_owners(state,view,runtimes,error): {==}
law ungrounded_motion_clears_support_without_extra_world_queries:
  for +geometry:G.Context
  for +point:V.Vec3
  for +box:A.AABB
  for +state:S.State
  for +delta:V.Vec3
  {Motion.support_update(geometry,point,box,state,False{},delta) == Done{S.empty()} : Result<&2,&2,T.Error,S.State>}
def ungrounded_motion_clears_support_without_extra_world_queries(geometry,point,box,state,delta): {==}
law actual_empty_tick_discards_before_age_delay_or_runtime_updates:
  for +record:E.Record
  for +runtime:T.Runtime
  for +records:List<&2,E.Record>
  {Tick.discarded(T.Snapshot{record,runtime},records) == Done{T.Plan{T.Snapshot{U.discard(record),runtime},M.replace(records,U.discard(record)),[T.Removed{E.record_id(record)}]}} : Result<&2,&2,T.Error,T.Plan>}
def actual_empty_tick_discards_before_age_delay_or_runtime_updates(record,runtime,records): {==}
law infinite_age_sentinel_does_not_advance:
  {Tick.age_next(4294934528) == 4294934528 : U32}
def infinite_age_sentinel_does_not_advance(): {==}
law ordinary_age_wraps_signed_maximum:
  {Tick.age_next(2147483647) == 2147483648 : U32}
def ordinary_age_wraps_signed_maximum(): {==}
law negative_pickup_delay_retains_complete_item_record_except_position_snapshot:
  for +c:E.Common
  for item:I.Slot
  for age:U32
  for health:U32
  for thrower:Maybe<&2,E.Uuid>
  for target:Maybe<&2,E.Uuid>
  for bob:F32
  {Tick.item_start(E.Item{c,item,age,4294967295,health,thrower,target,bob}) == E.Item{Tick.item_start_common(c),item,age,4294967295,health,thrower,target,bob} : E.Record}
def negative_pickup_delay_retains_complete_item_record_except_position_snapshot(c,item,age,health,thrower,target,bob): {==}
law blocked_merge_preserves_both_complete_records:
  for first:E.Record
  for second:E.Record
  for maximum:U32
  {M.merged(first,second,maximum,False{}) == M.MergePair{first,second,[]} : M.MergePair}
def blocked_merge_preserves_both_complete_records(first,second,maximum): {==}
law equal_count_merge_keeps_neighbour_rng_health_and_identity:
  for +a:E.Common
  for +b:E.Common
  for +ak:I.ItemKey
  for +bk:I.ItemKey
  for +aa:U32
  for +ba:U32
  for +ad:U32
  for +bd:U32
  for +ah:U32
  for +bh:U32
  for +at:Maybe<&2,E.Uuid>
  for +bt:Maybe<&2,E.Uuid>
  for +target:Maybe<&2,E.Uuid>
  for +other:Maybe<&2,E.Uuid>
  for +ab:F32
  for +bb:F32
  {M.merged(E.Item{a,I.InvStack{ak,4},aa,ad,ah,at,target,ab},E.Item{b,I.InvStack{bk,4},ba,bd,bh,bt,other,bb},64,True{}) ==
    M.MergePair{U.discard(E.Item{a,I.InvStack{ak,0},aa,ad,ah,at,target,ab}),E.Item{b,I.InvStack{bk,8},M.signed_min(ba,aa),M.signed_max(bd,ad),bh,bt,other,bb},[T.Merge{E.common_id(a),E.common_id(b),4},T.Removed{E.common_id(a)}]} : M.MergePair}
def equal_count_merge_keeps_neighbour_rng_health_and_identity(a,b,ak,bk,aa,ba,ad,bd,ah,bh,at,bt,target,other,ab,bb): {==}
law refused_core_capture_keeps_both_affine_backing_owners:
  for engine:Game.Engine
  for catalog:Slab.Catalog
  for request:World.Request
  for message:String
  {World.guarded(engine,catalog,request,Fail{message}) == (engine,catalog,Fail{T.Refused{message}}) : Game.Engine & Slab.Catalog & Result<&2,&2,T.Error,T.Context>}
def refused_core_capture_keeps_both_affine_backing_owners(engine,catalog,request,message): {==}

law unavailable_section_migration_keeps_the_full_entity_and_runtime:
  for owner:T.Owner
  {Tick.committed(owner,Tick.section_refused()) ==
    (owner,Fail{T.Refused{"item entity-section migration/visibility callback authority unavailable"}}) : T.Owner & Result<&2,&2,T.Error,List<&2,T.Publication>>}
def unavailable_section_migration_keeps_the_full_entity_and_runtime(owner): {==}
