import Base
import ./inventory.bend as I
import ./random.bend as random
import ./vanilla_entity_fields.bend as vanilla_entity_fields
import ./item_entity_pickup_scene.bend as Scene
import ./player_inventory.bend as P
import ./cooking_effect_entities_model.bend as E
import ./item_entity_pickup_model.bend as M
import ./item_entity_pickup.bend as D
import ./item_entity_pickup_insert.bend as Insert
import ./item_entity_pickup_publications.bend as Pub

law refused_candidate_retains_both_complete_affine_owners:
  for entity:E.Entity
  for player:P.State
  for error:M.Error
  {M.committed(entity,player,Fail{error}) == (entity,player,Fail{error}) : E.Entity & P.State & Result<&2,&2,M.Error,M.Effects>}
def refused_candidate_retains_both_complete_affine_owners(entity,player,error): {==}

law inactive_touch_retains_inventory_and_all_entity_fields:
  for admission:M.Admission
  for context:M.Context
  for record:E.Record
  for player:P.State
  {D.dispatched(False{},admission,context,record,player) == (E.Entity{record},player,Done{M.Effects{False{},0,D.record_count(record),False{},[]}}) : E.Entity & P.State & Result<&2,&2,M.Error,M.Effects>}
def inactive_touch_retains_inventory_and_all_entity_fields(admission,context,record,player): {==}

law unadmitted_touch_never_reads_or_installs_inventory:
  for admission:M.Admission
  for context:M.Context
  for record:E.Record
  for player:P.State
  {D.admitted(False{},admission,context,record,player) == (E.Entity{record},player,Fail{M.Refused{"item touch was not authoritatively admitted in the entity dimension"}}) : E.Entity & P.State & Result<&2,&2,M.Error,M.Effects>}
def unadmitted_touch_never_reads_or_installs_inventory(admission,context,record,player): {==}

law client_side_item_receiver_is_inactive:
  for dimension:String
  for uuid:E.Uuid
  for owner:M.OwnerResolution
  for common:E.Common
  for item:I.Slot
  for age:U32
  for delay:U32
  for health:U32
  for thrower:Maybe<&2,E.Uuid>
  for target:Maybe<&2,E.Uuid>
  for bob:F32
  {D.active(M.Admission{True{},False{},dimension,1,uuid,True{},owner},E.Item{common,item,age,delay,health,thrower,target,bob}) == False{} : Bool}
def client_side_item_receiver_is_inactive(dimension,uuid,owner,common,item,age,delay,health,thrower,target,bob): {==}

law partial_survival_insertion_retains_residue_without_take_or_stats:
  for admission:M.Admission
  for common:E.Common
  for key:I.ItemKey
  for original:U32
  for age:U32
  for delay:U32
  for health:U32
  for thrower:Maybe<&2,E.Uuid>
  for target:Maybe<&2,E.Uuid>
  for bob:F32
  for slots:List<&2,I.Slot>
  for remaining:U32
  for inserted:U32
  for pops:List<&2,M.Pop>
  {D.inserted(admission,E.Item{common,I.InvStack{key,original},age,delay,health,thrower,target,bob},original,M.Insertion{slots,remaining,inserted,False{},pops}) == Done{M.Plan{E.Item{D.removed(common,False{}),I.InvStack{key,remaining},age,delay,health,thrower,target,bob},slots,M.Effects{False{},inserted,remaining,False{},Pub.pops(pops)}}} : Result<&2,&2,M.Error,M.Plan>}
def partial_survival_insertion_retains_residue_without_take_or_stats(admission,common,key,original,age,delay,health,thrower,target,bob,slots,remaining,inserted,pops): {==}

law discarded_item_retains_original_count_and_nonpickup_fields:
  for common:E.Common
  for key:I.ItemKey
  for previous:U32
  for original:U32
  for age:U32
  for delay:U32
  for health:U32
  for thrower:Maybe<&2,E.Uuid>
  for target:Maybe<&2,E.Uuid>
  for bob:F32
  {D.changed(E.Item{common,I.InvStack{key,previous},age,delay,health,thrower,target,bob},original,True{}) == E.Item{D.removed(common,True{}),I.InvStack{key,original},age,delay,health,thrower,target,bob} : E.Record}
def discarded_item_retains_original_count_and_nonpickup_fields(common,key,previous,original,age,delay,health,thrower,target,bob): {==}

law survival_no_progress_keeps_residue_and_false_return:
  for slots:List<&2,I.Slot>
  for remaining:U32
  for inserted:U32
  for pops:List<&2,M.Pop>
  {Insert.blocked(False{},slots,remaining,inserted,pops) == Done{M.Insertion{slots,remaining,inserted,False{},pops}} : Result<&2,&2,M.Error,M.Insertion>}
def survival_no_progress_keeps_residue_and_false_return(slots,remaining,inserted,pops): {==}

law creative_no_progress_clears_residue_and_returns_true:
  for slots:List<&2,I.Slot>
  for remaining:U32
  for inserted:U32
  for pops:List<&2,M.Pop>
  {Insert.blocked(True{},slots,remaining,inserted,pops) == Done{M.Insertion{slots,0,inserted,True{},pops}} : Result<&2,&2,M.Error,M.Insertion>}
def creative_no_progress_clears_residue_and_returns_true(slots,remaining,inserted,pops): {==}

law unresolved_thrower_refuses_success_publication:
  for thrower:E.Uuid
  for receiver:E.Uuid
  for server:Bool
  for item:I.Slot
  {Pub.criteria(Some{thrower},M.UnknownOwner{},receiver,server,item) == Fail{M.Refused{"successful pickup requires actual world thrower lookup"}} : Result<&2,&2,M.Error,List<&2,M.Publication>>}
def unresolved_thrower_refuses_success_publication(thrower,receiver,server,item): {==}

law absent_thrower_does_not_require_world_resolution:
  for owner:M.OwnerResolution
  for receiver:E.Uuid
  for server:Bool
  for item:I.Slot
  {Pub.criteria(None{},owner,receiver,server,item) == Done{[]} : Result<&2,&2,M.Error,List<&2,M.Publication>>}
def absent_thrower_does_not_require_world_resolution(owner,receiver,server,item): {==}

law exhausted_operation_budget_cannot_install_partial_inventory:
  for slots:List<&2,I.Slot>
  for selected:U32
  for key:I.ItemKey
  for limit:U32
  for creative:Bool
  for inserted:U32
  for pops:List<&2,M.Pop>
  {Insert.resources(0n,slots,selected,key,1,limit,creative,inserted,pops) == Fail{M.BudgetExhausted{}} : Result<&2,&2,M.Error,M.Insertion>}
def exhausted_operation_budget_cannot_install_partial_inventory(slots,selected,key,limit,creative,inserted,pops): {==}

law successful_emptying_restores_original_entity_count_and_stat_quantity:
  for dimension:String
  for receiver:E.Uuid
  for fields:vanilla_entity_fields.Fields
  for random:random.Source
  for most:random.Bits64
  for least:random.Bits64
  for id:U32
  for player_id:U32
  for tick:U32
  for first:Bool
  for accessible:Bool
  for order:Nat
  for item_id:String
  for components:String
  for original:U32
  for age:U32
  for delay:U32
  for health:U32
  for target:Maybe<&2,E.Uuid>
  for bob:F32
  for slots:List<&2,I.Slot>
  for inserted:U32
  for pops:List<&2,M.Pop>
  {D.successful(M.Admission{True{},True{},dimension,player_id,receiver,False{},M.KnownAbsent{}},E.Item{E.Common{dimension,id,most,least,random,fields,tick,first,False{},accessible,order},I.InvStack{I.ItemKey{item_id,components},original},age,delay,health,None{},target,bob},original,slots,0,inserted,pops) == Done{M.Plan{E.Item{E.Common{dimension,id,most,least,random,fields,tick,first,True{},accessible,order},I.InvStack{I.ItemKey{item_id,components},original},age,delay,health,None{},target,bob},slots,M.Effects{True{},inserted,0,True{},List.append(&2,M.Publication,Pub.pops(pops),[M.TakePacket{id,player_id,original},M.EntityDiscard{id},M.PickupStat{receiver,item_id,original}])}}} : Result<&2,&2,M.Error,M.Plan>}
def successful_emptying_restores_original_entity_count_and_stat_quantity(dimension,receiver,fields,random,most,least,id,player_id,tick,first,accessible,order,item_id,components,original,age,delay,health,target,bob,slots,inserted,pops): {==}

law exhausted_scene_scan_retains_entities_player_rng_factory_and_ids:
  for admission:M.Admission
  for context:M.Context
  for wanted:U32
  for level:random.Source
  for factory:random.Bits64
  for cursor:U32
  for order:Nat
  for head:E.Entity
  for tail:List<&1,E.Entity>
  for player:P.State
  {Scene.touch_id(admission,context,wanted,E.State{level,factory,cursor,order,head <> tail},player,0n) == (E.State{level,factory,cursor,order,head <> tail},player,Fail{M.BudgetExhausted{}}) : E.State & P.State & Result<&2,&2,M.Error,M.Effects>}
def exhausted_scene_scan_retains_entities_player_rng_factory_and_ids(admission,context,wanted,level,factory,cursor,order,head,tail,player): {==}

# These are the actual branches called by dispatched/find, not substitute
# owner types. The complete gate laws above also check ordinarily.
law inactive_production_branch_retains_both_actual_owners:
  for record:E.Record
  for player:P.State
  {D.inactive(record,player) == (E.Entity{record},player,Done{M.Effects{False{},0,D.record_count(record),False{},[]}}) : E.Entity & P.State & Result<&2,&2,M.Error,M.Effects>}
def inactive_production_branch_retains_both_actual_owners(record,player): {==}

law exhausted_production_scan_branch_retains_the_full_ordered_list:
  for entities:List<&1,E.Entity>
  for player:P.State
  {Scene.exhausted(entities,player) == (entities,player,Fail{M.BudgetExhausted{}}) : List<&1,E.Entity> & P.State & Result<&2,&2,M.Error,M.Effects>}
def exhausted_production_scan_branch_retains_the_full_ordered_list(entities,player): {==}
