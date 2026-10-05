import Base
import ./entity_section_membership_laws.bend as Laws
import ./entity_section_membership.bend as P
import ./entity_section_membership_model.bend as M
import ./cooking_effect_entities_model.bend as E
import ./geometry.bend as A
import ./item_entity_tick_model.bend as T
import ./item_entity_tick_fields.bend as U
import ./vanilla_entity_fields.bend as V

def erased_id_step(+head:U32,+rest:List<&2,U32>,+id:U32,same:Bool,
  +decision:{U32.is_eq(head,id) == same : Bool},
  induction:{P.id_count(P.erase_id(rest,id),id) == 0n : Nat}) ->
  {P.id_count(P.erase_id(head <> rest,id),id) == 0n : Nat}:
  match same:
    case True{}:
      %Equal.sym(Bool,U32.is_eq(head,id),True{},decision) :
        {P.id_count(P.choose(List<&2,U32>,P.erase_id(rest,id),head <> P.erase_id(rest,id),_),id) == 0n : Nat}
      induction
    case False{}:
      %Equal.sym(Bool,U32.is_eq(head,id),False{},decision) :
        {P.id_count(P.choose(List<&2,U32>,P.erase_id(rest,id),head <> P.erase_id(rest,id),_),id) == 0n : Nat}
      %Equal.sym(Bool,U32.is_eq(head,id),False{},decision) :
        {Nat.add(P.choose(Nat,1n,0n,_),P.id_count(P.erase_id(rest,id),id)) == 0n : Nat}
      induction

def Laws.erased_id_is_absent(values,id):
  match values:
    case Nil{}: {==}
    case head <> rest:
      erased_id_step(head,rest,id,U32.is_eq(head,id),{==},Laws.erased_id_is_absent(rest,id))

def Laws.refused_commit_retains_complete_manager(state,error): {==}

def erased_member_step(+d:String,+i:U32,+key:M.SectionKey,+order:Nat,+box:A.AABB,+uuid:E.Uuid,+rest:List<&2,M.Member>,+dimension:String,+id:U32,same:Bool,
  +decision:{(String.eq(d,dimension) && U32.is_eq(i,id)) == same : Bool},
  induction:{P.member_count(P.erase_member(rest,dimension,id),dimension,id) == 0n : Nat}) ->
  {P.member_count(P.erase_member(M.Member{d,i,key,order,box,uuid} <> rest,dimension,id),dimension,id) == 0n : Nat}:
  match same:
    case True{}:
      %Equal.sym(Bool,String.eq(d,dimension) && U32.is_eq(i,id),True{},decision) :
        {P.member_count(P.choose(List<&2,M.Member>,P.erase_member(rest,dimension,id),M.Member{d,i,key,order,box,uuid} <> P.erase_member(rest,dimension,id),_),dimension,id) == 0n : Nat}
      induction
    case False{}:
      %Equal.sym(Bool,String.eq(d,dimension) && U32.is_eq(i,id),False{},decision) :
        {P.member_count(P.choose(List<&2,M.Member>,P.erase_member(rest,dimension,id),M.Member{d,i,key,order,box,uuid} <> P.erase_member(rest,dimension,id),_),dimension,id) == 0n : Nat}
      %Equal.sym(Bool,String.eq(d,dimension) && U32.is_eq(i,id),False{},decision) :
        {Nat.add(P.choose(Nat,1n,0n,_),P.member_count(P.erase_member(rest,dimension,id),dimension,id)) == 0n : Nat}
      induction

def Laws.erased_membership_is_absent(values,dimension,id):
  match values:
    case Nil{}: {==}
    case M.Member{d,i,key,order,box,uuid} <> rest:
      erased_member_step(d,i,key,order,box,uuid,rest,dimension,id,String.eq(d,dimension) && U32.is_eq(i,id),{==},Laws.erased_membership_is_absent(rest,dimension,id))

def truth_type(value:Bool) -> Type:
  match value:
    case False{}: Empty
    case True{}: Unit
def false_true(contradiction:{False{} == True{} : Bool}) -> Empty:
  %Equal.sym(Bool,False{},True{},contradiction) : truth_type(_)
  Unit{}
def conjunct_right(a:Bool,+b:Bool,admitted:{(a && b) == True{} : Bool}) -> {b == True{} : Bool}:
  match a:
    case True{}: admitted
    case False{}: Empty.absurd({b == True{} : Bool},false_true(admitted))

def erased_uuid_step(+d:String,+i:U32,+key:M.SectionKey,+order:Nat,+box:A.AABB,+other:E.Uuid,+rest:List<&2,M.Member>,+dimension:String,+id:U32,+uuid:E.Uuid,
  +idmatch:Bool,+uuidmatch:Bool,
  +id_decision:{(String.eq(d,dimension) && U32.is_eq(i,id)) == idmatch : Bool},
  +uuid_decision:{(String.eq(d,dimension) && P.uuid_eq(other,uuid)) == uuidmatch : Bool},
  linked:{(P.bool_eq(idmatch,uuidmatch) && Laws.uuid_links(rest,dimension,id,uuid)) == True{} : Bool},
  induction:{P.uuid_count(P.erase_member(rest,dimension,id),dimension,uuid) == 0n : Nat}) ->
  {P.uuid_count(P.erase_member(M.Member{d,i,key,order,box,other} <> rest,dimension,id),dimension,uuid) == 0n : Nat}:
  match idmatch uuidmatch:
    case True{} True{}:
      %Equal.sym(Bool,String.eq(d,dimension) && U32.is_eq(i,id),True{},id_decision) :
        {P.uuid_count(P.choose(List<&2,M.Member>,P.erase_member(rest,dimension,id),M.Member{d,i,key,order,box,other} <> P.erase_member(rest,dimension,id),_),dimension,uuid) == 0n : Nat}
      induction
    case False{} False{}:
      %Equal.sym(Bool,String.eq(d,dimension) && U32.is_eq(i,id),False{},id_decision) :
        {P.uuid_count(P.choose(List<&2,M.Member>,P.erase_member(rest,dimension,id),M.Member{d,i,key,order,box,other} <> P.erase_member(rest,dimension,id),_),dimension,uuid) == 0n : Nat}
      %Equal.sym(Bool,String.eq(d,dimension) && P.uuid_eq(other,uuid),False{},uuid_decision) :
        {Nat.add(P.choose(Nat,1n,0n,_),P.uuid_count(P.erase_member(rest,dimension,id),dimension,uuid)) == 0n : Nat}
      induction
    case True{} False{}:
      Empty.absurd({P.uuid_count(P.erase_member(M.Member{d,i,key,order,box,other} <> rest,dimension,id),dimension,uuid) == 0n : Nat},false_true(linked))
    case False{} True{}:
      Empty.absurd({P.uuid_count(P.erase_member(M.Member{d,i,key,order,box,other} <> rest,dimension,id),dimension,uuid) == 0n : Nat},false_true(linked))

def Laws.erased_membership_releases_its_uuid(values,dimension,id,uuid,linked):
  match values:
    case Nil{}: {==}
    case M.Member{d,i,key,order,box,other} <> rest:
      erased_uuid_step(d,i,key,order,box,other,rest,dimension,id,uuid,
        String.eq(d,dimension) && U32.is_eq(i,id),String.eq(d,dimension) && P.uuid_eq(other,uuid),{==},{==},linked,
        Laws.erased_membership_releases_its_uuid(rest,dimension,id,uuid,
          conjunct_right(P.bool_eq(String.eq(d,dimension) && U32.is_eq(i,id),String.eq(d,dimension) && P.uuid_eq(other,uuid)),Laws.uuid_links(rest,dimension,id,uuid),linked)))

def append_nil(+values:List<&2,M.CallbackEvent>) -> {List.append(&2,M.CallbackEvent,values,[]) == values : List<&2,M.CallbackEvent>}:
  match values:
    case Nil{}: {==}
    case head <> rest:
      Equal.cong(List<&2,M.CallbackEvent>,List<&2,M.CallbackEvent>,tail => head <> tail,List.append(&2,M.CallbackEvent,rest,[]),rest,append_nil(rest))

def Laws.accepted_commit_installs_view_and_returns_complete_proposal(state,view,cursor,records,journal): {==}
def Laws.section_common_preserves_every_other_field(dimension,id,most,least,random,fields,ticks,first,removed,old_accessible,old_order,accessible,order): {==}
def Laws.section_item_preserves_complete_payload(common,item,age,delay,health,thrower,target,bob,accessible,order): {==}
def Laws.section_orb_preserves_complete_payload(common,value,age,health,count,following,accessible,order): {==}
def Laws.movement_stop_orders_tracking_before_ticking(dimension,id): {==}
def Laws.movement_within_ticking_announces_section_change(dimension,id): {==}
def Laws.chunk_stop_orders_complete_ticking_pass_before_tracking(dimension,ids):
  %Equal.sym(List<&2,M.CallbackEvent>,List.append(&2,M.CallbackEvent,P.id_events(~P.tracking_end,ids,dimension),[]),P.id_events(~P.tracking_end,ids,dimension),append_nil(P.id_events(~P.tracking_end,ids,dimension))) :
    {List.append(&2,M.CallbackEvent,P.id_events(~P.ticking_end,ids,dimension),_) == List.append(&2,M.CallbackEvent,P.id_events(~P.ticking_end,ids,dimension),P.id_events(~P.tracking_end,ids,dimension)) : List<&2,M.CallbackEvent>}
  {==}
def Laws.chunk_start_orders_complete_tracking_pass_before_ticking(dimension,ids): {==}
def Laws.query_rejected_section_skips_all_entity_records(view,dimension,key,box,records,ids): {==}
def and_false(value:Bool) -> {(value && False{}) == False{} : Bool}:
  match value:
    case False{}: {==}
    case True{}: {==}
def query_tail_identity(value:Result<&2,&2,T.Error,List<&2,E.Record>>) ->
  {Result.bind(&2,&2,T.Error,List<&2,E.Record>,List<&2,E.Record>,value,tail => Done{List.append(&2,E.Record,[],tail)}) == value : Result<&2,&2,T.Error,List<&2,E.Record>>}:
  match value:
    case Done{tail}: {==}
    case Fail{error}: {==}
def Laws.hidden_section_is_skipped_before_querying_arbitrary_tail(view,dimension,hidden_dimension,key,ids,rest,box,records):
  %Equal.sym(Bool,String.eq(hidden_dimension,dimension) && False{},False{},and_false(String.eq(hidden_dimension,dimension))) :
    {Result.bind(&2,&2,T.Error,List<&2,E.Record>,List<&2,E.Record>,P.query_section_gate(view,dimension,key,box,records,ids,_ && P.section_in_box(key,box)),head => Result.bind(&2,&2,T.Error,List<&2,E.Record>,List<&2,E.Record>,P.query_sections(rest,view,dimension,box,records),tail => Done{List.append(&2,E.Record,head,tail)})) == P.query_sections(rest,view,dimension,box,records) : Result<&2,&2,T.Error,List<&2,E.Record>>}
  query_tail_identity(P.query_sections(rest,view,dimension,box,records))

def erased_registration_step(+d:String,+i:U32,+rest:List<&2,M.Registration>,+dimension:String,+id:U32,dimension_match:Bool,id_match:Bool,
  +dimension_decision:{String.eq(d,dimension) == dimension_match : Bool},
  +id_decision:{U32.is_eq(i,id) == id_match : Bool},
  induction:{P.id_count(P.registration_ids(P.erase_registration(rest,dimension,id),dimension),id) == 0n : Nat}) ->
  {P.id_count(P.registration_ids(P.erase_registration(M.Registration{d,i} <> rest,dimension,id),dimension),id) == 0n : Nat}:
  match dimension_match id_match:
    case False{} _:
      %Equal.sym(Bool,String.eq(d,dimension),False{},dimension_decision) :
        {P.id_count(P.registration_ids(P.choose(List<&2,M.Registration>,P.erase_registration(rest,dimension,id),M.Registration{d,i} <> P.erase_registration(rest,dimension,id),_ && U32.is_eq(i,id)),dimension),id) == 0n : Nat}
      %Equal.sym(Bool,String.eq(d,dimension),False{},dimension_decision) :
        {P.id_count(P.choose(List<&2,U32>,i <> P.registration_ids(P.erase_registration(rest,dimension,id),dimension),P.registration_ids(P.erase_registration(rest,dimension,id),dimension),_),id) == 0n : Nat}
      induction
    case True{} True{}:
      %Equal.sym(Bool,String.eq(d,dimension),True{},dimension_decision) :
        {P.id_count(P.registration_ids(P.choose(List<&2,M.Registration>,P.erase_registration(rest,dimension,id),M.Registration{d,i} <> P.erase_registration(rest,dimension,id),_ && U32.is_eq(i,id)),dimension),id) == 0n : Nat}
      %Equal.sym(Bool,U32.is_eq(i,id),True{},id_decision) :
        {P.id_count(P.registration_ids(P.choose(List<&2,M.Registration>,P.erase_registration(rest,dimension,id),M.Registration{d,i} <> P.erase_registration(rest,dimension,id),_),dimension),id) == 0n : Nat}
      induction
    case True{} False{}:
      %Equal.sym(Bool,String.eq(d,dimension),True{},dimension_decision) :
        {P.id_count(P.registration_ids(P.choose(List<&2,M.Registration>,P.erase_registration(rest,dimension,id),M.Registration{d,i} <> P.erase_registration(rest,dimension,id),_ && U32.is_eq(i,id)),dimension),id) == 0n : Nat}
      %Equal.sym(Bool,U32.is_eq(i,id),False{},id_decision) :
        {P.id_count(P.registration_ids(P.choose(List<&2,M.Registration>,P.erase_registration(rest,dimension,id),M.Registration{d,i} <> P.erase_registration(rest,dimension,id),_),dimension),id) == 0n : Nat}
      %Equal.sym(Bool,String.eq(d,dimension),True{},dimension_decision) :
        {P.id_count(P.choose(List<&2,U32>,i <> P.registration_ids(P.erase_registration(rest,dimension,id),dimension),P.registration_ids(P.erase_registration(rest,dimension,id),dimension),_),id) == 0n : Nat}
      %Equal.sym(Bool,U32.is_eq(i,id),False{},id_decision) :
        {Nat.add(P.choose(Nat,1n,0n,_),P.id_count(P.registration_ids(P.erase_registration(rest,dimension,id),dimension),id)) == 0n : Nat}
      induction

def Laws.erased_registration_is_absent_from_dimension_ids(values,dimension,id):
  match values:
    case Nil{}: {==}
    case M.Registration{d,i} <> rest:
      erased_registration_step(d,i,rest,dimension,id,String.eq(d,dimension),U32.is_eq(i,id),{==},{==},Laws.erased_registration_is_absent_from_dimension_ids(rest,dimension,id))

def Laws.tracking_end_removes_actual_getter_membership(view,dimension,id):
  match view:
    case M.View{members,sections,chunks,tracked,ticked}:
      Laws.erased_registration_is_absent_from_dimension_ids(tracked,dimension,id)
def Laws.ticking_end_removes_actual_scheduler_membership(view,dimension,id):
  match view:
    case M.View{members,sections,chunks,tracked,ticked}:
      Laws.erased_registration_is_absent_from_dimension_ids(ticked,dimension,id)

def event_keeps_authority(+view:M.View,event:M.CallbackEvent) ->
  {Laws.authority(P.registry_event(view,event)) == Laws.authority(view) : List<&2,M.Member> & (List<&2,M.Section> & List<&2,M.Chunk>)}:
  match view:
    case M.View{members,sections,chunks,tracked,ticked}:
      match event:
        case M.TrackingStart{dimension,id}: {==}
        case M.TrackingEnd{dimension,id}: {==}
        case M.TickingStart{dimension,id}: {==}
        case M.TickingEnd{dimension,id}: {==}
        case M.SectionCreated{dimension,key,visibility}: {==}
        case M.SectionDeleted{dimension,key}: {==}
        case M.Inserted{dimension,id,key,order}: {==}
        case M.Detached{dimension,id,key}: {==}
        case M.Created{dimension,id}: {==}
        case M.SectionChange{dimension,id}: {==}
        case M.Destroyed{dimension,id}: {==}

def Laws.callback_journal_preserves_complete_section_authority(events,view):
  match events:
    case Nil{}: {==}
    case head <> rest:
      Equal.trans(List<&2,M.Member> & (List<&2,M.Section> & List<&2,M.Chunk>),
        Laws.authority(P.registry_events(rest,P.registry_event(view,head))),Laws.authority(P.registry_event(view,head)),Laws.authority(view),
        Laws.callback_journal_preserves_complete_section_authority(rest,P.registry_event(view,head)),event_keeps_authority(view,head))

def Laws.removal_retains_cursor_and_complete_entity_records(view,located,destroy,cursor,records):
  match view located:
    case M.View{members,sections,chunks,tracked,ticked} M.Located{M.Member{dimension,id,key,order,box,uuid},M.Section{d,k,visibility,ids}}: {==}

def registry_keeps_members(+events:List<&2,M.CallbackEvent>,+view:M.View) ->
  {Laws.members(P.registry_events(events,view)) == Laws.members(view) : List<&2,M.Member>}:
  Equal.cong(List<&2,M.Member> & (List<&2,M.Section> & List<&2,M.Chunk>),List<&2,M.Member>,Laws.authority_members,
    Laws.authority(P.registry_events(events,view)),Laws.authority(view),Laws.callback_journal_preserves_complete_section_authority(events,view))

def Laws.removed_entity_has_no_section_membership(view,dimension,id,key,order,box,uuid,section,destroy,cursor,records):
  match view section:
    case M.View{+members,+sections,+chunks,+tracked,+ticked} M.Section{d,k,+visibility,+ids}:
      +remaining=P.erase_id(ids,id)
      +events=List.append(&2,M.CallbackEvent,[M.Detached{dimension,id,key}],List.append(&2,M.CallbackEvent,
        P.choose(List<&2,M.CallbackEvent>,[M.TickingEnd{dimension,id}],[],P.ticking(visibility)),List.append(&2,M.CallbackEvent,
        P.choose(List<&2,M.CallbackEvent>,[M.TrackingEnd{dimension,id}],[],P.accessible(visibility)),List.append(&2,M.CallbackEvent,
        P.choose(List<&2,M.CallbackEvent>,[M.Destroyed{dimension,id}],[],destroy),P.deleted_event(dimension,key,remaining)))))
      +changed={M.View{P.erase_member(members,dimension,id),P.retained_section(dimension,key,visibility,remaining,P.erase_section(sections,dimension,key)),chunks,tracked,ticked} : M.View}
      %Equal.sym(List<&2,M.Member>,Laws.members(P.registry_events(events,changed)),P.erase_member(members,dimension,id),registry_keeps_members(events,changed)) :
        {P.member_count(_,dimension,id) == 0n : Nat}
      Laws.erased_membership_is_absent(members,dimension,id)

def Laws.removed_entity_releases_uuid_registration(view,dimension,id,key,order,box,uuid,section,destroy,cursor,records,linked):
  match view section:
    case M.View{+members,+sections,+chunks,+tracked,+ticked} M.Section{d,k,+visibility,+ids}:
      +remaining=P.erase_id(ids,id)
      +events=List.append(&2,M.CallbackEvent,[M.Detached{dimension,id,key}],List.append(&2,M.CallbackEvent,
        P.choose(List<&2,M.CallbackEvent>,[M.TickingEnd{dimension,id}],[],P.ticking(visibility)),List.append(&2,M.CallbackEvent,
        P.choose(List<&2,M.CallbackEvent>,[M.TrackingEnd{dimension,id}],[],P.accessible(visibility)),List.append(&2,M.CallbackEvent,
        P.choose(List<&2,M.CallbackEvent>,[M.Destroyed{dimension,id}],[],destroy),P.deleted_event(dimension,key,remaining)))))
      +changed={M.View{P.erase_member(members,dimension,id),P.retained_section(dimension,key,visibility,remaining,P.erase_section(sections,dimension,key)),chunks,tracked,ticked} : M.View}
      %Equal.sym(List<&2,M.Member>,Laws.members(P.registry_events(events,changed)),P.erase_member(members,dimension,id),registry_keeps_members(events,changed)) :
        {P.uuid_count(_,dimension,uuid) == 0n : Nat}
      Laws.erased_membership_releases_its_uuid(members,dimension,id,uuid,linked)

def no_removal_without_record(+view:M.View,+dimension:String,+id:U32,+destroy:Bool,+cursor:Nat,+records:List<&2,E.Record>,missing:{P.record_count(records,dimension,id) == 0n : Nat}) ->
  {P.on_removed(view,dimension,id,destroy,cursor,records) == Fail{T.Refused{"removed section entity record must be retained until publication"}} : Result<&2,&2,T.Error,M.Proposal>}:
  %Equal.sym(Nat,P.record_count(records,dimension,id),0n,missing) :
    {Result.bind(&2,&2,T.Error,Unit,M.Proposal,U.guard(Nat.is_eq(_,1n),"removed section entity record must be retained until publication"),ignore => Result.bind(&2,&2,T.Error,M.Located,M.Proposal,P.locate(view,dimension,id),located => Result.bind(&2,&2,T.Error,E.Record,M.Proposal,P.record(records,dimension,id),actual => P.removed_verified(view,located,destroy,cursor,records,actual)))) == Fail{T.Refused{"removed section entity record must be retained until publication"}} : Result<&2,&2,T.Error,M.Proposal>}
  {==}
def Laws.removal_without_retained_record_keeps_complete_manager(state,view,dimension,id,destroy,cursor,records,missing):
  Equal.cong(Result<&2,&2,T.Error,M.Proposal>,M.State & Result<&2,&2,T.Error,M.Proposal>,result => P.commit(state,result),
    P.on_removed(view,dimension,id,destroy,cursor,records),Fail{T.Refused{"removed section entity record must be retained until publication"}},
    no_removal_without_record(view,dimension,id,destroy,cursor,records,missing))

def Laws.removal_stale_record_keeps_complete_manager(state,view,dimension,id,key,order,box,uuid,section_dimension,section_key,visibility,ids,destroy,cursor,records,actual,disagrees):
  %Equal.sym(Bool,P.uuid_eq(uuid,P.common_uuid(E.common(actual))) && Nat.is_eq(order,P.common_order(E.common(actual))) && P.bool_eq(P.accessible(visibility),P.common_accessible(E.common(actual))),False{},disagrees) :
    {P.commit(state,Result.bind(&2,&2,T.Error,Unit,M.Proposal,U.guard(_,"removal record disagrees with registered section authority"),ignore => Done{P.removed_located(view,M.Located{M.Member{dimension,id,key,order,box,uuid},M.Section{section_dimension,section_key,visibility,ids}},destroy,cursor,records)})) == (state,Fail{T.Refused{"removal record disagrees with registered section authority"}}) : M.State & Result<&2,&2,T.Error,M.Proposal>}
  {==}

def Laws.query_cannot_publish_retained_record_without_membership(view,dimension,id,rest,key,box,records,absent):
  match view:
    case M.View{members,sections,chunks,tracked,ticked}:
      %Equal.sym(Nat,P.member_count(members,dimension,id),0n,absent) :
        {Result.bind(&2,&2,T.Error,Unit,List<&2,E.Record>,U.guard(Nat.is_eq(_,1n) && Nat.is_eq(P.record_count(records,dimension,id),1n),"query membership and entity record must be unique"),ignore => Result.bind(&2,&2,T.Error,M.Member,List<&2,E.Record>,P.member(members,dimension,id),found => Result.bind(&2,&2,T.Error,E.Record,List<&2,E.Record>,P.record(records,dimension,id),actual => Result.bind(&2,&2,T.Error,List<&2,E.Record>,List<&2,E.Record>,P.query_registered(found,key,actual,box),head => Result.bind(&2,&2,T.Error,List<&2,E.Record>,List<&2,E.Record>,P.query_ids(rest,M.View{members,sections,chunks,tracked,ticked},dimension,key,box,records),tail => Done{List.append(&2,E.Record,head,tail)}))))) == Fail{T.Refused{"query membership and entity record must be unique"}} : Result<&2,&2,T.Error,List<&2,E.Record>>}
      {==}

def Laws.same_section_move_retains_order_cursor_and_full_snapshot(members,sections,chunks,tracked,ticked,located,record,runtime,box,records,cursor,new_key):
  match located:
    case M.Located{M.Member{d,id,key,order,old,uuid},section}: {==}

def Laws.insertion_appends_after_existing_section_members(members,sections,chunks,tracked,ticked,record,runtime,dimension,key,ids,box,cursor,records,absent):
  %Equal.sym(Nat,P.id_count(ids,E.record_id(record)),0n,absent) :
    {Result.bind(&2,&2,T.Error,Unit,M.Moved,U.guard(Nat.is_eq(_,0n),"entity registration destination already contains ID"),ignore => Done{M.Moved{T.Snapshot{P.section_record(record,False{},cursor),runtime},P.stage(M.View{M.Member{dimension,E.record_id(record),key,cursor,box,P.common_uuid(E.common(record))} <> members,M.Section{dimension,key,M.Hidden{},List.append(&2,U32,ids,[E.record_id(record)])} <> P.erase_section(sections,dimension,key),chunks,tracked,ticked},1n+cursor,P.replace_record(records,P.section_record(record,False{},cursor)),[M.Inserted{dimension,E.record_id(record),key,cursor}])}}) ==
      Done{M.Moved{T.Snapshot{P.section_record(record,False{},cursor),runtime},M.Proposal{M.View{M.Member{dimension,E.record_id(record),key,cursor,box,P.common_uuid(E.common(record))} <> members,M.Section{dimension,key,M.Hidden{},List.append(&2,U32,ids,[E.record_id(record)])} <> P.erase_section(sections,dimension,key),chunks,tracked,ticked},1n+cursor,P.replace_record(records,P.section_record(record,False{},cursor)),[M.Inserted{dimension,E.record_id(record),key,cursor}]}}} : Result<&2,&2,T.Error,M.Moved>}
  {==}

def Laws.empty_section_visibility_update_retains_complete_records(dimension,key,old,actual_dimension,x,z,loaded,next,view,records):
  match old next:
    case M.Hidden{} M.Hidden{}: {==}
    case M.Hidden{} M.Tracked{}: {==}
    case M.Hidden{} M.Ticking{}: {==}
    case M.Tracked{} M.Hidden{}: {==}
    case M.Tracked{} M.Tracked{}: {==}
    case M.Tracked{} M.Ticking{}: {==}
    case M.Ticking{} M.Hidden{}: {==}
    case M.Ticking{} M.Tracked{}: {==}
    case M.Ticking{} M.Ticking{}: {==}
def Laws.zero_membership_chunk_update_retains_cursor_and_complete_records(members,chunks,tracked,ticked,actual,cursor,records): {==}
def Laws.missing_physical_section_retains_complete_returned_core(world,dimension,point,visibility,error): {==}
def Laws.physical_section_does_not_fabricate_missing_visibility(world,dimension,point,state):
  match point:
    case V.Vec3{x,y,z}: {==}
