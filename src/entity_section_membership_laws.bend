import Base
import ./entity_section_membership.bend as P
import ./entity_section_membership_model.bend as M
import ./cooking_effect_entities_model.bend as E
import ./item_entity_tick_model.bend as T
import ./item_entity_tick_fields.bend as U
import ./vanilla_entity_fields.bend as V
import ./geometry.bend as A
import ./random.bend as R
import ./inventory.bend as I
import ./entity_section_membership_world.bend as W
import ./core.bend as C

def proposal_view(proposal:M.Proposal) -> M.View:
  M.Proposal{view,cursor,records,journal}=proposal
  view
def retained_owner(proposal:M.Proposal) -> Nat & List<&2,E.Record>:
  M.Proposal{view,cursor,records,journal}=proposal
  (cursor,records)
def authority(view:M.View) -> List<&2,M.Member> & (List<&2,M.Section> & List<&2,M.Chunk>):
  M.View{members,sections,chunks,tracked,ticked}=view
  (members,(sections,chunks))
def authority_members(value:List<&2,M.Member> & (List<&2,M.Section> & List<&2,M.Chunk>)) -> List<&2,M.Member>:
  (members,rest)=value
  members
def members(view:M.View) -> List<&2,M.Member>:
  authority_members(authority(view))

law erased_id_is_absent:
  for +values:List<&2,U32>
  for +id:U32
  {P.id_count(P.erase_id(values,id),id) == 0n : Nat}

law refused_commit_retains_complete_manager:
  for state:M.State
  for error:T.Error
  {P.commit(state,Fail{error}) == (state,Fail{error}) :
    M.State & Result<&2,&2,T.Error,M.Proposal>}

# A well-formed registration gives one entity ID to each dimension/UUID pair.
# This is an independent input invariant, rather than a filtered-count premise.
def uuid_links(values:List<&2,M.Member>,+dimension:String,+id:U32,+uuid:E.Uuid) -> Bool:
  match values:
    case Nil{}: True{}
    case M.Member{+d,i,k,o,box,other} <> rest:
      P.bool_eq(String.eq(d,dimension) && U32.is_eq(i,id),String.eq(d,dimension) && P.uuid_eq(other,uuid)) && uuid_links(rest,dimension,id,uuid)

law erased_membership_is_absent:
  for +values:List<&2,M.Member>
  for +dimension:String
  for +id:U32
  {P.member_count(P.erase_member(values,dimension,id),dimension,id) == 0n : Nat}

law erased_membership_releases_its_uuid:
  for +values:List<&2,M.Member>
  for +dimension:String
  for +id:U32
  for +uuid:E.Uuid
  for +linked:{uuid_links(values,dimension,id,uuid) == True{} : Bool}
  {P.uuid_count(P.erase_member(values,dimension,id),dimension,uuid) == 0n : Nat}

law accepted_commit_installs_view_and_returns_complete_proposal:
  for state:M.State
  for +view:M.View
  for +cursor:Nat
  for +records:List<&2,E.Record>
  for +journal:List<&2,M.CallbackEvent>
  {P.commit(state,Done{M.Proposal{view,cursor,records,journal}}) ==
    (M.State{view},Done{M.Proposal{view,cursor,records,journal}}) :
    M.State & Result<&2,&2,T.Error,M.Proposal>}

# Every raw Common field except the two section fields is retained, including
# RNG and the complete vanilla Fields record. Payload laws cover both variants.
law section_common_preserves_every_other_field:
  for dimension:String
  for id:U32
  for most:R.Bits64
  for least:R.Bits64
  for random:R.Source
  for fields:V.Fields
  for ticks:U32
  for first:Bool
  for removed:Bool
  for old_accessible:Bool
  for old_order:Nat
  for accessible:Bool
  for order:Nat
  {P.section_common(E.Common{dimension,id,most,least,random,fields,ticks,first,removed,old_accessible,old_order},accessible,order) ==
    E.Common{dimension,id,most,least,random,fields,ticks,first,removed,accessible,order} : E.Common}

law section_item_preserves_complete_payload:
  for +common:E.Common
  for item:I.Slot
  for age:U32
  for delay:U32
  for health:U32
  for thrower:Maybe<&2,E.Uuid>
  for target:Maybe<&2,E.Uuid>
  for bob:F32
  for accessible:Bool
  for order:Nat
  {P.section_record(E.Item{common,item,age,delay,health,thrower,target,bob},accessible,order) ==
    E.Item{P.section_common(common,accessible,order),item,age,delay,health,thrower,target,bob} : E.Record}

law section_orb_preserves_complete_payload:
  for +common:E.Common
  for value:U32
  for age:U32
  for health:U32
  for count:U32
  for following:Maybe<&2,E.Uuid>
  for accessible:Bool
  for order:Nat
  {P.section_record(E.Orb{common,value,age,health,count,following},accessible,order) ==
    E.Orb{P.section_common(common,accessible,order),value,age,health,count,following} : E.Record}

law movement_stop_orders_tracking_before_ticking:
  for +dimension:String
  for +id:U32
  {P.transition(dimension,id,M.Ticking{},M.Hidden{}) ==
    [M.TrackingEnd{dimension,id},M.TickingEnd{dimension,id}] : List<&2,M.CallbackEvent>}

law movement_within_ticking_announces_section_change:
  for dimension:String
  for id:U32
  {P.transition(dimension,id,M.Ticking{},M.Ticking{}) ==
    [M.SectionChange{dimension,id}] : List<&2,M.CallbackEvent>}

law chunk_stop_orders_complete_ticking_pass_before_tracking:
  for +dimension:String
  for +ids:List<&2,U32>
  {P.chunk_transition(dimension,ids,M.Ticking{},M.Hidden{}) ==
    List.append(&2,M.CallbackEvent,P.id_events(~P.ticking_end,ids,dimension),P.id_events(~P.tracking_end,ids,dimension)) : List<&2,M.CallbackEvent>}

law chunk_start_orders_complete_tracking_pass_before_ticking:
  for +dimension:String
  for +ids:List<&2,U32>
  {P.chunk_transition(dimension,ids,M.Hidden{},M.Ticking{}) ==
    List.append(&2,M.CallbackEvent,P.id_events(~P.tracking_start,ids,dimension),P.id_events(~P.ticking_start,ids,dimension)) : List<&2,M.CallbackEvent>}

law query_rejected_section_skips_all_entity_records:
  for view:M.View
  for dimension:String
  for key:M.SectionKey
  for box:A.AABB
  for records:List<&2,E.Record>
  for ids:List<&2,U32>
  {P.query_section_gate(view,dimension,key,box,records,ids,False{}) == Done{[]} :
    Result<&2,&2,T.Error,List<&2,E.Record>>}

law hidden_section_is_skipped_before_querying_arbitrary_tail:
  for +view:M.View
  for +dimension:String
  for hidden_dimension:String
  for key:M.SectionKey
  for ids:List<&2,U32>
  for rest:List<&2,M.Section>
  for +box:A.AABB
  for +records:List<&2,E.Record>
  {P.query_sections(M.Section{hidden_dimension,key,M.Hidden{},ids} <> rest,view,dimension,box,records) ==
    P.query_sections(rest,view,dimension,box,records) : Result<&2,&2,T.Error,List<&2,E.Record>>}

law erased_registration_is_absent_from_dimension_ids:
  for +values:List<&2,M.Registration>
  for +dimension:String
  for +id:U32
  {P.id_count(P.registration_ids(P.erase_registration(values,dimension,id),dimension),id) == 0n : Nat}

law tracking_end_removes_actual_getter_membership:
  for +view:M.View
  for +dimension:String
  for +id:U32
  {P.id_count(P.tracked(P.registry_event(view,M.TrackingEnd{dimension,id}),dimension),id) == 0n : Nat}

law ticking_end_removes_actual_scheduler_membership:
  for +view:M.View
  for +dimension:String
  for +id:U32
  {P.id_count(P.scheduled(P.registry_event(view,M.TickingEnd{dimension,id}),dimension),id) == 0n : Nat}

law callback_journal_preserves_complete_section_authority:
  for +events:List<&2,M.CallbackEvent>
  for +view:M.View
  {authority(P.registry_events(events,view)) == authority(view) :
    List<&2,M.Member> & (List<&2,M.Section> & List<&2,M.Chunk>)}

law removal_retains_cursor_and_complete_entity_records:
  for view:M.View
  for located:M.Located
  for destroy:Bool
  for +cursor:Nat
  for +records:List<&2,E.Record>
  {retained_owner(P.removed_located(view,located,destroy,cursor,records)) == (cursor,records) : Nat & List<&2,E.Record>}

law removed_entity_has_no_section_membership:
  for +view:M.View
  for +dimension:String
  for +id:U32
  for +key:M.SectionKey
  for order:Nat
  for box:A.AABB
  for uuid:E.Uuid
  for section:M.Section
  for destroy:Bool
  for cursor:Nat
  for records:List<&2,E.Record>
  {P.member_count(members(proposal_view(P.removed_located(view,M.Located{M.Member{dimension,id,key,order,box,uuid},section},destroy,cursor,records))),dimension,id) == 0n : Nat}

law removed_entity_releases_uuid_registration:
  for +view:M.View
  for +dimension:String
  for +id:U32
  for +key:M.SectionKey
  for order:Nat
  for box:A.AABB
  for +uuid:E.Uuid
  for section:M.Section
  for destroy:Bool
  for cursor:Nat
  for records:List<&2,E.Record>
  for linked:{uuid_links(members(view),dimension,id,uuid) == True{} : Bool}
  {P.uuid_count(members(proposal_view(P.removed_located(view,M.Located{M.Member{dimension,id,key,order,box,uuid},section},destroy,cursor,records))),dimension,uuid) == 0n : Nat}

# These complete-owner refusals compose the actual callbacks with actual
# manager commit, rather than asserting only that a guard helper is false.
law removal_without_retained_record_keeps_complete_manager:
  for state:M.State
  for +view:M.View
  for +dimension:String
  for +id:U32
  for +destroy:Bool
  for +cursor:Nat
  for +records:List<&2,E.Record>
  for missing:{P.record_count(records,dimension,id) == 0n : Nat}
  {P.commit(state,P.on_removed(view,dimension,id,destroy,cursor,records)) ==
    (state,Fail{T.Refused{"removed section entity record must be retained until publication"}}) : M.State & Result<&2,&2,T.Error,M.Proposal>}

law removal_stale_record_keeps_complete_manager:
  for state:M.State
  for +view:M.View
  for +dimension:String
  for +id:U32
  for +key:M.SectionKey
  for +order:Nat
  for +box:A.AABB
  for +uuid:E.Uuid
  for +section_dimension:String
  for +section_key:M.SectionKey
  for +visibility:M.Visibility
  for +ids:List<&2,U32>
  for +destroy:Bool
  for +cursor:Nat
  for +records:List<&2,E.Record>
  for +actual:E.Record
  for disagrees:{(P.uuid_eq(uuid,P.common_uuid(E.common(actual))) && Nat.is_eq(order,P.common_order(E.common(actual))) && P.bool_eq(P.accessible(visibility),P.common_accessible(E.common(actual)))) == False{} : Bool}
  {P.commit(state,P.removed_verified(view,M.Located{M.Member{dimension,id,key,order,box,uuid},M.Section{section_dimension,section_key,visibility,ids}},destroy,cursor,records,actual)) ==
    (state,Fail{T.Refused{"removal record disagrees with registered section authority"}}) : M.State & Result<&2,&2,T.Error,M.Proposal>}

law query_cannot_publish_retained_record_without_membership:
  for +view:M.View
  for +dimension:String
  for +id:U32
  for rest:List<&2,U32>
  for key:M.SectionKey
  for box:A.AABB
  for records:List<&2,E.Record>
  for absent:{P.member_count(members(view),dimension,id) == 0n : Nat}
  {P.query_ids(id <> rest,view,dimension,key,box,records) ==
    Fail{T.Refused{"query membership and entity record must be unique"}} : Result<&2,&2,T.Error,List<&2,E.Record>>}

law same_section_move_retains_order_cursor_and_full_snapshot:
  for +members:List<&2,M.Member>
  for +sections:List<&2,M.Section>
  for +chunks:List<&2,M.Chunk>
  for +tracked:List<&2,M.Registration>
  for +ticked:List<&2,M.Registration>
  for located:M.Located
  for +record:E.Record
  for +runtime:T.Runtime
  for +box:A.AABB
  for +records:List<&2,E.Record>
  for +cursor:Nat
  for new_key:M.SectionKey
  {P.move_key(M.View{members,sections,chunks,tracked,ticked},located,T.Snapshot{record,runtime},box,records,cursor,new_key,True{}) ==
    Done{M.Moved{T.Snapshot{record,runtime},M.Proposal{M.View{P.member_boxes(members,P.common_dimension(E.common(record)),E.record_id(record),box),sections,chunks,tracked,ticked},cursor,P.replace_record(records,record),[]}}} : Result<&2,&2,T.Error,M.Moved>}

# Existing destination insertion retains the arbitrary ID prefix and appends
# the new ID. Hidden insertion changes neither operational callback registry.
law insertion_appends_after_existing_section_members:
  for +members:List<&2,M.Member>
  for +sections:List<&2,M.Section>
  for +chunks:List<&2,M.Chunk>
  for +tracked:List<&2,M.Registration>
  for +ticked:List<&2,M.Registration>
  for +record:E.Record
  for +runtime:T.Runtime
  for +dimension:String
  for +key:M.SectionKey
  for +ids:List<&2,U32>
  for +box:A.AABB
  for +cursor:Nat
  for +records:List<&2,E.Record>
  for absent:{P.id_count(ids,E.record_id(record)) == 0n : Nat}
  {P.added_destination(M.View{members,sections,chunks,tracked,ticked},T.Snapshot{record,runtime},box,cursor,records,False{},M.Destination{M.Section{dimension,key,M.Hidden{},ids},False{}}) ==
    Done{M.Moved{T.Snapshot{P.section_record(record,False{},cursor),runtime},M.Proposal{
      M.View{M.Member{dimension,E.record_id(record),key,cursor,box,P.common_uuid(E.common(record))} <> members,
        M.Section{dimension,key,M.Hidden{},List.append(&2,U32,ids,[E.record_id(record)])} <> P.erase_section(sections,dimension,key),chunks,tracked,ticked},
      1n+cursor,P.replace_record(records,P.section_record(record,False{},cursor)),[M.Inserted{dimension,E.record_id(record),key,cursor}]}}} : Result<&2,&2,T.Error,M.Moved>}

law empty_section_visibility_update_retains_complete_records:
  for +dimension:String
  for +key:M.SectionKey
  for old:M.Visibility
  for actual_dimension:String
  for x:U32
  for z:U32
  for loaded:Bool
  for +next:M.Visibility
  for view:M.View
  for +records:List<&2,E.Record>
  {P.chunk_section(M.Section{dimension,key,old,[]},M.Chunk{actual_dimension,x,z,loaded,next},view,records,True{}) ==
    Done{M.ChunkChanged{[M.Section{dimension,key,next,[]}],records,[]}} : Result<&2,&2,T.Error,M.ChunkChanged>}

law zero_membership_chunk_update_retains_cursor_and_complete_records:
  for +members:List<&2,M.Member>
  for +chunks:List<&2,M.Chunk>
  for +tracked:List<&2,M.Registration>
  for +ticked:List<&2,M.Registration>
  for +actual:M.Chunk
  for +cursor:Nat
  for +records:List<&2,E.Record>
  {P.update_chunk(M.View{members,[],chunks,tracked,ticked},actual,cursor,records) ==
    Done{M.Proposal{M.View{members,[],actual <> P.erase_chunk(chunks,actual),tracked,ticked},cursor,records,[]}} : Result<&2,&2,T.Error,M.Proposal>}

law missing_physical_section_retains_complete_returned_core:
  for world:C.World
  for dimension:String
  for point:V.Vec3
  for visibility:Maybe<&2,M.Visibility>
  for error:C.Error
  {W.observed(dimension,point,visibility,(world,Fail{error})) ==
    (world,Fail{T.Refused{"actual entity destination Core section is unavailable"}}) : C.World & Result<&2,&2,T.Error,M.Chunk>}

law physical_section_does_not_fabricate_missing_visibility:
  for world:C.World
  for dimension:String
  for point:V.Vec3
  for state:U32
  {W.observed(dimension,point,None{},(world,Done{state})) ==
    (world,Fail{T.Refused{"actual entity chunk visibility observation is missing"}}) : C.World & Result<&2,&2,T.Error,M.Chunk>}
