import Base
import ./entity_section_membership_model.bend as M
import ./cooking_effect_entities_model.bend as E
import ./item_entity_tick_model.bend as T
import ./item_entity_tick_fields.bend as U
import ./vanilla_entity_fields.bend as V
import ./geometry.bend as A
import ./f64.bend as F
import ./random.bend as R

def choose(~D:Data,a:D,b:D,value:Bool) -> D:
  match value:
    case True{}: a
    case False{}: b
def key_axis(value:F.F64,mask:U32) -> U32: U32.and(U32.shrn(V.floor_word(value),4n),mask)
def key(point:V.Vec3) -> M.SectionKey:
  V.Vec3{x,y,z}=point
  M.SectionKey{key_axis(x,4194303),key_axis(y,1048575),key_axis(z,4194303)}
def key_eq(a:M.SectionKey,b:M.SectionKey) -> Bool:
  M.SectionKey{+x,+y,+z}=a
  M.SectionKey{+a,+b,+c}=b
  U32.is_eq(x,a) && U32.is_eq(y,b) && U32.is_eq(z,c)
# LongAVLTreeSet signed packed-long ordering: X22 (signed), Z22, Y20.
def key_less(a:M.SectionKey,b:M.SectionKey) -> Bool:
  M.SectionKey{+x,+y,+z}=a
  M.SectionKey{+a,+b,+c}=b
  U32.is_lt(U32.xor(x,2097152),U32.xor(a,2097152)) ||
    (U32.is_eq(x,a) && (U32.is_lt(z,c) || (U32.is_eq(z,c) && U32.is_lt(y,b))))
def key_valid(value:M.SectionKey) -> Bool:
  M.SectionKey{+x,+y,+z}=value
  U32.is_lt(x,4194304) && U32.is_lt(y,1048576) && U32.is_lt(z,4194304)
def accessible(value:M.Visibility) -> Bool:
  match value:
    case M.Hidden{}: False{}
    case _: True{}
def ticking(value:M.Visibility) -> Bool:
  match value:
    case M.Ticking{}: True{}
    case _: False{}
def visibility_eq(a:M.Visibility,b:M.Visibility) -> Bool:
  match a b:
    case M.Hidden{} M.Hidden{}: True{}
    case M.Tracked{} M.Tracked{}: True{}
    case M.Ticking{} M.Ticking{}: True{}
    case _ _: False{}
def bool_eq(a:Bool,b:Bool) -> Bool:
  match a b:
    case True{} True{}: True{}
    case False{} False{}: True{}
    case _ _: False{}
def bits_eq(a:R.Bits64,b:R.Bits64) -> Bool:
  R.Bits64{+ah,+al}=a
  R.Bits64{+bh,+bl}=b
  U32.is_eq(ah,bh) && U32.is_eq(al,bl)
def uuid_eq(a:E.Uuid,b:E.Uuid) -> Bool:
  E.Uuid{am,al}=a
  E.Uuid{bm,bl}=b
  bits_eq(am,bm) && bits_eq(al,bl)
def common_uuid(value:E.Common) -> E.Uuid:
  E.Common{d,id,a,b,r,f,t,first,removed,accessible,order}=value
  E.Uuid{a,b}
def uuid_count(values:List<&2,M.Member>,+dimension:String,+uuid:E.Uuid) -> Nat:
  match values:
    case Nil{}: 0n
    case M.Member{d,id,key,order,box,other} <> rest:
      Nat.add(choose(Nat,1n,0n,String.eq(d,dimension) && uuid_eq(other,uuid)),uuid_count(rest,dimension,uuid))
def common_dimension(value:E.Common) -> String:
  E.Common{dimension,id,a,b,r,f,t,first,removed,accessible,order}=value
  dimension
def common_order(value:E.Common) -> Nat:
  E.Common{dimension,id,a,b,r,f,t,first,removed,accessible,order}=value
  order
def common_accessible(value:E.Common) -> Bool:
  E.Common{dimension,id,a,b,r,f,t,first,removed,accessible,order}=value
  accessible
def registration_ids(values:List<&2,M.Registration>,+dimension:String) -> List<&2,U32>:
  match values:
    case Nil{}: []
    case M.Registration{d,+id} <> +rest:
      +tail=registration_ids(rest,dimension)
      choose(List<&2,U32>,id <> tail,tail,String.eq(d,dimension))
def tracked(view:M.View,dimension:String) -> List<&2,U32>:
  M.View{members,sections,chunks,tracked,ticked}=view
  registration_ids(tracked,dimension)
def scheduled(view:M.View,dimension:String) -> List<&2,U32>:
  M.View{members,sections,chunks,tracked,ticked}=view
  registration_ids(ticked,dimension)
def erase_registration(values:List<&2,M.Registration>,+dimension:String,+id:U32) -> List<&2,M.Registration>:
  match values:
    case Nil{}: []
    case +head <> +rest:
      M.Registration{d,i}=head
      +tail=erase_registration(rest,dimension,id)
      choose(List<&2,M.Registration>,tail,head <> tail,String.eq(d,dimension) && U32.is_eq(i,id))
def registry_event(+view:M.View,event:M.CallbackEvent) -> M.View:
  M.View{members,sections,chunks,+tracked,+ticked}=view
  match event:
    case M.TrackingStart{+dimension,+id}: M.View{members,sections,chunks,List.append(&2,M.Registration,tracked,[M.Registration{dimension,id}]),ticked}
    case M.TrackingEnd{+dimension,+id}: M.View{members,sections,chunks,erase_registration(tracked,dimension,id),ticked}
    case M.TickingStart{+dimension,+id}: M.View{members,sections,chunks,tracked,List.append(&2,M.Registration,ticked,[M.Registration{dimension,id}])}
    case M.TickingEnd{+dimension,+id}: M.View{members,sections,chunks,tracked,erase_registration(ticked,dimension,id)}
    case _: view
def registry_events(events:List<&2,M.CallbackEvent>,+view:M.View) -> M.View:
  match events:
    case Nil{}: view
    case head <> rest: registry_events(rest,registry_event(view,head))
def stage(+view:M.View,next_order:Nat,records:List<&2,E.Record>,+journal:List<&2,M.CallbackEvent>) -> M.Proposal:
  M.Proposal{registry_events(journal,view),next_order,records,journal}
def section_common(value:E.Common,accessible:Bool,order:Nat) -> E.Common:
  E.Common{d,id,a,b,r,f,t,first,removed,old_accessible,old_order}=value
  E.Common{d,id,a,b,r,f,t,first,removed,accessible,order}
def section_record(+value:E.Record,accessible:Bool,order:Nat) -> E.Record:
  U.with_common(value,section_common(E.common(value),accessible,order))
def replace_record(values:List<&2,E.Record>,+replacement:E.Record) -> List<&2,E.Record>:
  match values:
    case Nil{}: []
    case +head <> rest:
      choose(E.Record,replacement,head,U32.is_eq(E.record_id(head),E.record_id(replacement)) && String.eq(common_dimension(E.common(head)),common_dimension(E.common(replacement)))) <> replace_record(rest,replacement)
def id_count(values:List<&2,U32>,+id:U32) -> Nat:
  match values:
    case Nil{}: 0n
    case head <> rest: Nat.add(choose(Nat,1n,0n,U32.is_eq(head,id)),id_count(rest,id))
def record_count(values:List<&2,E.Record>,+dimension:String,+id:U32) -> Nat:
  match values:
    case Nil{}: 0n
    case +head <> rest:
      Nat.add(choose(Nat,1n,0n,U32.is_eq(E.record_id(head),id) && String.eq(common_dimension(E.common(head)),dimension)),record_count(rest,dimension,id))
def member_count(values:List<&2,M.Member>,+dimension:String,+id:U32) -> Nat:
  match values:
    case Nil{}: 0n
    case M.Member{d,i,k,o,box,uuid} <> rest:
      Nat.add(choose(Nat,1n,0n,String.eq(d,dimension) && U32.is_eq(i,id)),member_count(rest,dimension,id))
def section_count(values:List<&2,M.Section>,+dimension:String,+key:M.SectionKey) -> Nat:
  match values:
    case Nil{}: 0n
    case M.Section{d,k,v,ids} <> rest:
      Nat.add(choose(Nat,1n,0n,String.eq(d,dimension) && key_eq(k,key)),section_count(rest,dimension,key))
def member(values:List<&2,M.Member>,+dimension:String,+id:U32) -> Result<&2,&2,T.Error,M.Member>:
  match values:
    case Nil{}: Fail{T.Refused{"entity section registration is missing"}}
    case +head <> +rest:
      M.Member{d,i,k,o,box,uuid}=head
      choose(Result<&2,&2,T.Error,M.Member>,Done{head},member(rest,dimension,id),String.eq(d,dimension) && U32.is_eq(i,id))
def section(values:List<&2,M.Section>,+dimension:String,+key:M.SectionKey) -> Maybe<&2,M.Section>:
  match values:
    case Nil{}: None{}
    case +head <> +rest:
      M.Section{d,k,v,ids}=head
      choose(Maybe<&2,M.Section>,Some{head},section(rest,dimension,key),String.eq(d,dimension) && key_eq(k,key))
def located_section(+member:M.Member,value:Maybe<&2,M.Section>) -> Result<&2,&2,T.Error,M.Located>:
  M.Member{d,+id,k,o,box,uuid}=member
  match value:
    case None{}: Fail{T.Refused{"registered entity section is missing"}}
    case Some{+section}:
      M.Section{d,k,v,+ids}=section
      do Result<&2,&2,T.Error,M.Located>:
        _ : Unit <- U.guard(Nat.is_eq(id_count(ids,id),1n),"registered entity must occur once in its section")
        return M.Located{member,section}
def located_member(+found:M.Member,+sections:List<&2,M.Section>,+dimension:String) -> Result<&2,&2,T.Error,M.Located>:
  M.Member{d,i,+key,o,box,uuid}=found
  do Result<&2,&2,T.Error,M.Located>:
    _ : Unit <- U.guard(Nat.is_eq(section_count(sections,dimension,key),1n),"registered entity section must be unique")
    located_section(found,section(sections,dimension,key))
def locate(+view:M.View,+dimension:String,+id:U32) -> Result<&2,&2,T.Error,M.Located>:
  M.View{+members,+sections,chunks,tracked,ticked}=view
  do Result<&2,&2,T.Error,M.Located>:
    _ : Unit <- U.guard(Nat.is_eq(member_count(members,dimension,id),1n),"entity section registration must be unique")
    +found : M.Member <- member(members,dimension,id)
    located_member(found,sections,dimension)
def chunk_matches(+chunk:M.Chunk,+dimension:String,+key:M.SectionKey) -> Bool:
  M.Chunk{d,x,z,loaded,v}=chunk
  M.SectionKey{k,y,l}=key
  String.eq(d,dimension) && U32.is_eq(U32.and(x,4194303),k) && U32.is_eq(U32.and(z,4194303),l)
def chunk_count(values:List<&2,M.Chunk>,+dimension:String,+key:M.SectionKey) -> Nat:
  match values:
    case Nil{}: 0n
    case +head <> rest: Nat.add(choose(Nat,1n,0n,chunk_matches(head,dimension,key)),chunk_count(rest,dimension,key))
def chunk(values:List<&2,M.Chunk>,+dimension:String,+key:M.SectionKey) -> Result<&2,&2,T.Error,M.Chunk>:
  match values:
    case Nil{}: Fail{T.Refused{"actual destination chunk loaded/visibility facts are missing"}}
    case +head <> +rest:
      choose(Result<&2,&2,T.Error,M.Chunk>,Done{head},chunk(rest,dimension,key),chunk_matches(head,dimension,key))
def created_destination(+dimension:String,+key:M.SectionKey,value:M.Chunk) -> Result<&2,&2,T.Error,M.Destination>:
  M.Chunk{d,x,z,loaded,+visibility}=value
  do Result<&2,&2,T.Error,M.Destination>:
    _ : Unit <- U.guard(loaded,"entity section destination chunk is not loaded")
    return M.Destination{M.Section{dimension,key,visibility,[]},True{}}
def destination_missing(+dimension:String,+key:M.SectionKey,+chunks:List<&2,M.Chunk>,value:Maybe<&2,M.Section>) -> Result<&2,&2,T.Error,M.Destination>:
  match value:
    case Some{section}: Done{M.Destination{section,False{}}}
    case None{}:
      do Result<&2,&2,T.Error,M.Destination>:
        _ : Unit <- U.guard(Nat.is_eq(chunk_count(chunks,dimension,key),1n),"actual destination chunk loaded/visibility facts must be unique")
        +actual : M.Chunk <- chunk(chunks,dimension,key)
        created_destination(dimension,key,actual)
def destination(view:M.View,+dimension:String,+key:M.SectionKey) -> Result<&2,&2,T.Error,M.Destination>:
  M.View{members,+sections,+chunks,tracked,ticked}=view
  do Result<&2,&2,T.Error,M.Destination>:
    _ : Unit <- U.guard(Nat.is_le(section_count(sections,dimension,key),1n),"destination entity section must be unique")
    destination_missing(dimension,key,chunks,section(sections,dimension,key))
def erase_id(values:List<&2,U32>,+id:U32) -> List<&2,U32>:
  match values:
    case Nil{}: []
    case +head <> +rest:
      +tail=erase_id(rest,id)
      choose(List<&2,U32>,tail,head <> tail,U32.is_eq(head,id))
def erase_member(values:List<&2,M.Member>,+dimension:String,+id:U32) -> List<&2,M.Member>:
  match values:
    case Nil{}: []
    case +head <> +rest:
      M.Member{d,i,k,o,box,uuid}=head
      +tail=erase_member(rest,dimension,id)
      choose(List<&2,M.Member>,tail,head <> tail,String.eq(d,dimension) && U32.is_eq(i,id))
def erase_section(values:List<&2,M.Section>,+dimension:String,+key:M.SectionKey) -> List<&2,M.Section>:
  match values:
    case Nil{}: []
    case +head <> +rest:
      M.Section{d,k,v,ids}=head
      +tail=erase_section(rest,dimension,key)
      choose(List<&2,M.Section>,tail,head <> tail,String.eq(d,dimension) && key_eq(k,key))
def boxed_member(+value:M.Member,+box:A.AABB,changed:Bool) -> M.Member:
  M.Member{d,id,key,order,old,uuid}=value
  choose(M.Member,M.Member{d,id,key,order,box,uuid},value,changed)
def member_boxes(values:List<&2,M.Member>,+dimension:String,+id:U32,+box:A.AABB) -> List<&2,M.Member>:
  match values:
    case Nil{}: []
    case +head <> rest:
      M.Member{d,i,k,o,old,uuid}=head
      boxed_member(head,box,String.eq(d,dimension) && U32.is_eq(i,id)) <> member_boxes(rest,dimension,id,box)
def replace_box(view:M.View,dimension:String,id:U32,box:A.AABB) -> M.View:
  M.View{members,sections,chunks,tracked,ticked}=view
  M.View{member_boxes(members,dimension,id,box),sections,chunks,tracked,ticked}
def retained_section(+dimension:String,+key:M.SectionKey,+visibility:M.Visibility,ids:List<&2,U32>,sections:List<&2,M.Section>) -> List<&2,M.Section>:
  match ids:
    case Nil{}: sections
    case +head <> +rest: M.Section{dimension,key,visibility,head <> rest} <> sections
def deleted_event(+dimension:String,+key:M.SectionKey,ids:List<&2,U32>) -> List<&2,M.CallbackEvent>:
  match ids:
    case Nil{}: [M.SectionDeleted{dimension,key}]
    case _: []
def transition(+dimension:String,+id:U32,+old:M.Visibility,+next:M.Visibility) -> List<&2,M.CallbackEvent>:
  List.append(&2,M.CallbackEvent,
    choose(List<&2,M.CallbackEvent>,[M.TrackingEnd{dimension,id}],[],accessible(old) && Bool.not(accessible(next))),
    List.append(&2,M.CallbackEvent,
      choose(List<&2,M.CallbackEvent>,[M.TrackingStart{dimension,id}],[],Bool.not(accessible(old)) && accessible(next)),
      List.append(&2,M.CallbackEvent,
        choose(List<&2,M.CallbackEvent>,[M.TickingEnd{dimension,id}],[],ticking(old) && Bool.not(ticking(next))),
        List.append(&2,M.CallbackEvent,
          choose(List<&2,M.CallbackEvent>,[M.TickingStart{dimension,id}],[],Bool.not(ticking(old)) && ticking(next)),
          choose(List<&2,M.CallbackEvent>,[M.SectionChange{dimension,id}],[],accessible(next))))))
def move_same(+view:M.View,+proposed:T.Snapshot,+box:A.AABB,+records:List<&2,E.Record>,next_order:Nat) -> M.Moved:
  T.Snapshot{+record,runtime}=proposed
  M.Moved{T.Snapshot{record,runtime},M.Proposal{replace_box(view,common_dimension(E.common(record)),E.record_id(record),box),next_order,replace_record(records,record),[]}}
def move_changed(+view:M.View,+located:M.Located,+proposed:T.Snapshot,+box:A.AABB,+records:List<&2,E.Record>,+next_order:Nat,destination:M.Destination) -> Result<&2,&2,T.Error,M.Moved>:
  M.View{members,sections,chunks,tracked,ticked}=view
  M.Located{M.Member{+dimension,+id,+old_key,order,old_box,+uuid},M.Section{d,k,+old_visibility,+old_ids}}=located
  T.Snapshot{+record,runtime}=proposed
  M.Destination{M.Section{d,+new_key,+visibility,+ids},+created}=destination
  +remaining=erase_id(old_ids,id)
  +changed=section_record(record,accessible(visibility),next_order)
  +creation=choose(List<&2,M.CallbackEvent>,[M.SectionCreated{dimension,new_key,visibility}],[],created)
  +journal=List.append(&2,M.CallbackEvent,[M.Detached{dimension,id,old_key}],List.append(&2,M.CallbackEvent,deleted_event(dimension,old_key,remaining),List.append(&2,M.CallbackEvent,creation,M.Inserted{dimension,id,new_key,next_order} <> transition(dimension,id,old_visibility,visibility))))
  do Result<&2,&2,T.Error,M.Moved>:
    _ : Unit <- U.guard(Nat.is_eq(id_count(ids,id),0n),"destination entity section already contains moving ID")
    return M.Moved{T.Snapshot{changed,runtime},stage(
      M.View{M.Member{dimension,id,new_key,next_order,box,uuid} <> erase_member(members,dimension,id),
        M.Section{dimension,new_key,visibility,List.append(&2,U32,ids,[id])} <>
          retained_section(dimension,old_key,old_visibility,remaining,erase_section(erase_section(sections,dimension,old_key),dimension,new_key)),chunks,tracked,ticked},
      1n+next_order,replace_record(records,changed),journal)}
def move_key(+view:M.View,+located:M.Located,+proposed:T.Snapshot,+box:A.AABB,+records:List<&2,E.Record>,+next_order:Nat,+new_key:M.SectionKey,same:Bool) -> Result<&2,&2,T.Error,M.Moved>:
  M.Located{M.Member{+dimension,id,k,o,old_box,uuid},section}=located
  match same:
    case True{}: Done{move_same(view,proposed,box,records,next_order)}
    case False{}:
      do Result<&2,&2,T.Error,M.Moved>:
        +target : M.Destination <- destination(view,dimension,new_key)
        move_changed(view,located,proposed,box,records,next_order,target)
def verified_move(+view:M.View,+original:E.Common,+registered:M.SectionKey,+proposed:T.Snapshot,+box:A.AABB,+next_order:Nat,+records:List<&2,E.Record>,+located:M.Located) -> Result<&2,&2,T.Error,M.Moved>:
  T.Snapshot{+record,runtime}=proposed
  M.Located{M.Member{d,i,+old_key,+order,old_box,+uuid},M.Section{d,k,+visibility,ids}}=located
  +new_key=key(U.pos(record))
  do Result<&2,&2,T.Error,M.Moved>:
    _ : Unit <- U.guard(key_eq(old_key,registered) && Nat.is_eq(order,common_order(original)) && bool_eq(accessible(visibility),common_accessible(original)) && uuid_eq(uuid,common_uuid(original)),"original entity Common disagrees with registered section authority")
    _ : Unit <- U.guard(Nat.is_eq(common_order(E.common(record)),order) && bool_eq(common_accessible(E.common(record)),accessible(visibility)),"proposed entity must retain prior section facts until its move callback")
    _ : Unit <- U.guard(Nat.is_lt(order,next_order),"entity section insertion cursor must follow registered order")
    move_key(view,located,proposed,box,records,next_order,new_key,key_eq(registered,new_key))
def on_move(+view:M.View,+original:E.Common,+registered:M.SectionKey,+proposed:T.Snapshot,+box:A.AABB,+next_order:Nat,+records:List<&2,E.Record>) -> Result<&2,&2,T.Error,M.Moved>:
  T.Snapshot{+record,+runtime}=proposed
  +dimension=common_dimension(original)
  +id=E.common_id(original)
  do Result<&2,&2,T.Error,M.Moved>:
    _ : Unit <- U.guard(String.eq(common_dimension(E.common(record)),dimension) && U32.is_eq(E.record_id(record),id) && uuid_eq(common_uuid(E.common(record)),common_uuid(original)),"section move must preserve dimension, entity ID and UUID")
    _ : Unit <- U.guard(key_valid(registered),"registered section key is malformed")
    _ : Unit <- U.guard(Bool.not(U.removed_common(original)),"removed entity has no move callback")
    _ : Unit <- U.guard(Nat.is_eq(record_count(records,dimension,id),1n),"section move query record must be unique")
    +located : M.Located <- locate(view,dimension,id)
    # box is the actual entity box supplied by the physics receiver, not a
    # point-derived fabricated shape. Manager movement itself indexes position.
    verified_move(view,original,registered,proposed,box,next_order,records,located)
def removed_located(+view:M.View,+located:M.Located,+destroy:Bool,+next_order:Nat,+records:List<&2,E.Record>) -> M.Proposal:
  M.View{members,sections,chunks,tracked,ticked}=view
  M.Located{M.Member{+dimension,+id,+key,order,old_box,uuid},M.Section{d,k,+visibility,+ids}}=located
  +remaining=erase_id(ids,id)
  +events=List.append(&2,M.CallbackEvent,[M.Detached{dimension,id,key}],List.append(&2,M.CallbackEvent,
    choose(List<&2,M.CallbackEvent>,[M.TickingEnd{dimension,id}],[],ticking(visibility)),List.append(&2,M.CallbackEvent,
    choose(List<&2,M.CallbackEvent>,[M.TrackingEnd{dimension,id}],[],accessible(visibility)),List.append(&2,M.CallbackEvent,
    choose(List<&2,M.CallbackEvent>,[M.Destroyed{dimension,id}],[],destroy),deleted_event(dimension,key,remaining)))))
  stage(M.View{erase_member(members,dimension,id),retained_section(dimension,key,visibility,remaining,erase_section(sections,dimension,key)),chunks,tracked,ticked},next_order,records,events)
def record(values:List<&2,E.Record>,+dimension:String,+id:U32) -> Result<&2,&2,T.Error,E.Record>:
  match values:
    case Nil{}: Fail{T.Refused{"registered entity query record is missing"}}
    case +head <> +rest:
      choose(Result<&2,&2,T.Error,E.Record>,Done{head},record(rest,dimension,id),U32.is_eq(E.record_id(head),id) && String.eq(common_dimension(E.common(head)),dimension))
def removed_verified(+view:M.View,+located:M.Located,+destroy:Bool,+next_order:Nat,+records:List<&2,E.Record>,+actual:E.Record) -> Result<&2,&2,T.Error,M.Proposal>:
  M.Located{M.Member{dimension,id,key,+order,box,+uuid},M.Section{d,k,+visibility,ids}}=located
  do Result<&2,&2,T.Error,M.Proposal>:
    _ : Unit <- U.guard(uuid_eq(uuid,common_uuid(E.common(actual))) && Nat.is_eq(order,common_order(E.common(actual))) && bool_eq(accessible(visibility),common_accessible(E.common(actual))),"removal record disagrees with registered section authority")
    return removed_located(view,located,destroy,next_order,records)
def on_removed(+view:M.View,+dimension:String,+id:U32,+destroy:Bool,+next_order:Nat,+records:List<&2,E.Record>) -> Result<&2,&2,T.Error,M.Proposal>:
  do Result<&2,&2,T.Error,M.Proposal>:
    _ : Unit <- U.guard(Nat.is_eq(record_count(records,dimension,id),1n),"removed section entity record must be retained until publication")
    +located : M.Located <- locate(view,dimension,id)
    +actual : E.Record <- record(records,dimension,id)
    removed_verified(view,located,destroy,next_order,records,actual)
def orders_before(values:List<&2,M.Member>,+next_order:Nat) -> Bool:
  match values:
    case Nil{}: True{}
    case M.Member{d,id,k,order,box,uuid} <> rest: Nat.is_lt(order,next_order) && orders_before(rest,next_order)
def added_destination(+view:M.View,+proposed:T.Snapshot,+box:A.AABB,+next_order:Nat,+records:List<&2,E.Record>,+created:Bool,target:M.Destination) -> Result<&2,&2,T.Error,M.Moved>:
  M.View{members,sections,chunks,tracked,ticked}=view
  T.Snapshot{+record,runtime}=proposed
  M.Destination{M.Section{+dimension,+key,+visibility,+ids},+new_section}=target
  +id=E.record_id(record)
  +changed=section_record(record,accessible(visibility),next_order)
  +journal=List.append(&2,M.CallbackEvent,
    choose(List<&2,M.CallbackEvent>,[M.SectionCreated{dimension,key,visibility}],[],new_section),
    M.Inserted{dimension,id,key,next_order} <> List.append(&2,M.CallbackEvent,
      choose(List<&2,M.CallbackEvent>,[M.Created{dimension,id}],[],created),List.append(&2,M.CallbackEvent,
      choose(List<&2,M.CallbackEvent>,[M.TrackingStart{dimension,id}],[],accessible(visibility)),
      choose(List<&2,M.CallbackEvent>,[M.TickingStart{dimension,id}],[],ticking(visibility)))))
  do Result<&2,&2,T.Error,M.Moved>:
    _ : Unit <- U.guard(Nat.is_eq(id_count(ids,id),0n),"entity registration destination already contains ID")
    return M.Moved{T.Snapshot{changed,runtime},stage(
      M.View{M.Member{dimension,id,key,next_order,box,common_uuid(E.common(record))} <> members,
        M.Section{dimension,key,visibility,List.append(&2,U32,ids,[id])} <> erase_section(sections,dimension,key),chunks,tracked,ticked},
      1n+next_order,replace_record(records,changed),journal)}
def on_add(+view:M.View,+proposed:T.Snapshot,+box:A.AABB,+next_order:Nat,+records:List<&2,E.Record>,+created:Bool) -> Result<&2,&2,T.Error,M.Moved>:
  M.View{+members,sections,chunks,tracked,ticked}=view
  T.Snapshot{+record,runtime}=proposed
  +dimension=common_dimension(E.common(record))
  +id=E.record_id(record)
  do Result<&2,&2,T.Error,M.Moved>:
    _ : Unit <- U.guard(Bool.not(U.removed(record)),"removed entity cannot register in a section")
    _ : Unit <- U.guard(Nat.is_eq(member_count(members,dimension,id),0n),"entity ID is already registered")
    _ : Unit <- U.guard(Nat.is_eq(uuid_count(members,dimension,common_uuid(E.common(record))),0n),"entity UUID is already registered")
    _ : Unit <- U.guard(Nat.is_eq(record_count(records,dimension,id),1n),"new entity record must be unique in prospective sole owner")
    _ : Unit <- U.guard(orders_before(members,next_order),"section insertion cursor would reuse a registered order")
    +target : M.Destination <- destination(view,dimension,key(U.pos(record)))
    added_destination(view,proposed,box,next_order,records,created,target)

# Section storage traversal uses packed long order inside each X column.
def insert_section(+value:M.Section,sections:List<&2,M.Section>) -> List<&2,M.Section>:
  M.Section{d,+key,v,ids}=value
  match sections:
    case Nil{}: [value]
    case +head <> +rest:
      M.Section{d,+other,v,ids}=head
      choose(List<&2,M.Section>,value <> head <> rest,head <> insert_section(value,rest),key_less(key,other))
def sorted_sections(sections:List<&2,M.Section>) -> List<&2,M.Section>:
  match sections:
    case Nil{}: []
    case head <> rest: insert_section(head,sorted_sections(rest))
def signed_axis(+value:U32,sign:U32,extension:U32) -> U32:
  choose(U32,U32.or(value,extension),value,U32.is_ne(U32.and(value,sign),0))
def signed_section(+point:F.F64) -> U32:
  +block=V.floor_word(point)
  signed_axis(U32.shrn(block,4n),134217728,4026531840)
def within(+value:U32,+lower:U32,+upper:U32) -> Bool:
  Bool.not(U.signed_lt(value,lower)) && Bool.not(U.signed_lt(upper,value))
def section_in_box(value:M.SectionKey,box:A.AABB) -> Bool:
  M.SectionKey{x,y,z}=value
  A.AABB{minx,miny,minz,maxx,maxy,maxz}=box
  within(signed_axis(x,2097152,4290772992),signed_section(F.sub(minx,F.from_u32(2))),signed_section(F.add(maxx,F.from_u32(2)))) &&
  within(signed_axis(y,524288,4293918720),signed_section(F.sub(miny,F.from_u32(4))),signed_section(maxy)) &&
  within(signed_axis(z,2097152,4290772992),signed_section(F.sub(minz,F.from_u32(2))),signed_section(F.add(maxz,F.from_u32(2))))
def query_member(+member:M.Member,+record:E.Record,+query_box:A.AABB) -> Result<&2,&2,T.Error,List<&2,E.Record>>:
  M.Member{dimension,id,key,order,box,uuid}=member
  do Result<&2,&2,T.Error,List<&2,E.Record>>:
    _ : Unit <- U.guard(Nat.is_eq(order,common_order(E.common(record))) && uuid_eq(uuid,common_uuid(E.common(record))) && common_accessible(E.common(record)),"query entity Common disagrees with section authority")
    return choose(List<&2,E.Record>,[record],[],A.AABB.intersects(box,query_box) && Bool.not(U.removed(record)))
def query_registered(+found:M.Member,+key:M.SectionKey,+actual:E.Record,+box:A.AABB) -> Result<&2,&2,T.Error,List<&2,E.Record>>:
  M.Member{d,id,+registered,o,b,uuid}=found
  do Result<&2,&2,T.Error,List<&2,E.Record>>:
    _ : Unit <- U.guard(key_eq(registered,key),"query section contains entity registered elsewhere")
    query_member(found,actual,box)
def query_ids(ids:List<&2,U32>,+view:M.View,+dimension:String,+key:M.SectionKey,+box:A.AABB,+records:List<&2,E.Record>) -> Result<&2,&2,T.Error,List<&2,E.Record>>:
  match ids:
    case Nil{}: Done{[]}
    case +id <> rest:
      M.View{+members,sections,chunks,tracked,ticked}=view
      do Result<&2,&2,T.Error,List<&2,E.Record>>:
        _ : Unit <- U.guard(Nat.is_eq(member_count(members,dimension,id),1n) && Nat.is_eq(record_count(records,dimension,id),1n),"query membership and entity record must be unique")
        +found : M.Member <- member(members,dimension,id)
        +actual : E.Record <- record(records,dimension,id)
        +head : List<&2,E.Record> <- query_registered(found,key,actual,box)
        +tail : List<&2,E.Record> <- query_ids(rest,view,dimension,key,box,records)
        return List.append(&2,E.Record,head,tail)
def query_section_gate(+view:M.View,+dimension:String,+key:M.SectionKey,+box:A.AABB,+records:List<&2,E.Record>,ids:List<&2,U32>,admitted:Bool) -> Result<&2,&2,T.Error,List<&2,E.Record>>:
  match admitted:
    case False{}: Done{[]}
    case True{}: query_ids(ids,view,dimension,key,box,records)
def query_sections(sections:List<&2,M.Section>,+view:M.View,+dimension:String,+box:A.AABB,+records:List<&2,E.Record>) -> Result<&2,&2,T.Error,List<&2,E.Record>>:
  match sections:
    case Nil{}: Done{[]}
    case M.Section{+d,+key,+visibility,+ids} <> rest:
      do Result<&2,&2,T.Error,List<&2,E.Record>>:
        +head : List<&2,E.Record> <- query_section_gate(view,dimension,key,box,records,ids,String.eq(d,dimension) && accessible(visibility) && section_in_box(key,box))
        +tail : List<&2,E.Record> <- query_sections(rest,view,dimension,box,records)
        return List.append(&2,E.Record,head,tail)
def query(+view:M.View,dimension:String,box:A.AABB,records:List<&2,E.Record>) -> Result<&2,&2,T.Error,List<&2,E.Record>>:
  M.View{members,sections,chunks,tracked,ticked}=view
  query_sections(sorted_sections(sections),view,dimension,box,records)

# updateChunkStatus differs from Callback.onMove: per section, all ticking
# stops precede tracking transitions, and ticking starts follow them.
def id_events(~event:String -> U32 -> M.CallbackEvent,ids:List<&2,U32>,+dimension:String) -> List<&2,M.CallbackEvent>:
  match ids:
    case Nil{}: []
    case head <> rest: event(dimension,head) <> id_events(~event,rest,dimension)
def ticking_end(dimension:String,id:U32) -> M.CallbackEvent: M.TickingEnd{dimension,id}
def ticking_start(dimension:String,id:U32) -> M.CallbackEvent: M.TickingStart{dimension,id}
def tracking_end(dimension:String,id:U32) -> M.CallbackEvent: M.TrackingEnd{dimension,id}
def tracking_start(dimension:String,id:U32) -> M.CallbackEvent: M.TrackingStart{dimension,id}
def chunk_transition(+dimension:String,+ids:List<&2,U32>,+old:M.Visibility,+next:M.Visibility) -> List<&2,M.CallbackEvent>:
  List.append(&2,M.CallbackEvent,
    choose(List<&2,M.CallbackEvent>,id_events(~ticking_end,ids,dimension),[],ticking(old) && Bool.not(ticking(next))),
    List.append(&2,M.CallbackEvent,
      choose(List<&2,M.CallbackEvent>,id_events(~tracking_end,ids,dimension),[],accessible(old) && Bool.not(accessible(next))),
      List.append(&2,M.CallbackEvent,
        choose(List<&2,M.CallbackEvent>,id_events(~tracking_start,ids,dimension),[],Bool.not(accessible(old)) && accessible(next)),
        choose(List<&2,M.CallbackEvent>,id_events(~ticking_start,ids,dimension),[],Bool.not(ticking(old)) && ticking(next)))))
def access_ids(ids:List<&2,U32>,+dimension:String,+next:M.Visibility,+view:M.View,+records:List<&2,E.Record>) -> Result<&2,&2,T.Error,List<&2,E.Record>>:
  match ids:
    case Nil{}: Done{records}
    case +id <> rest:
      do Result<&2,&2,T.Error,List<&2,E.Record>>:
        _ : Unit <- U.guard(Nat.is_eq(record_count(records,dimension,id),1n),"visibility change requires complete entity records")
        +actual : E.Record <- record(records,dimension,id)
        +registered : M.Located <- locate(view,dimension,id)
        access_ids(rest,dimension,next,view,replace_record(records,section_record(actual,accessible(next),common_order(E.common(actual)))))
def chunk_section(+head:M.Section,+actual:M.Chunk,+view:M.View,+records:List<&2,E.Record>,matches:Bool) -> Result<&2,&2,T.Error,M.ChunkChanged>:
  M.Section{+dimension,+key,+old,+ids}=head
  M.Chunk{d,x,z,loaded,+next}=actual
  match matches:
    case False{}: Done{M.ChunkChanged{[head],records,[]}}
    case True{}:
      do Result<&2,&2,T.Error,M.ChunkChanged>:
        +updated : List<&2,E.Record> <- access_ids(ids,dimension,next,view,records)
        return M.ChunkChanged{[M.Section{dimension,key,next,ids}],updated,chunk_transition(dimension,ids,old,next)}
def chunk_head(+head:M.Section,+actual:M.Chunk,+view:M.View,+records:List<&2,E.Record>) -> Result<&2,&2,T.Error,M.ChunkChanged>:
  M.Section{+dimension,+key,old,ids}=head
  chunk_section(head,actual,view,records,chunk_matches(actual,dimension,key))
def chunk_records(changed:M.ChunkChanged) -> List<&2,E.Record>:
  M.ChunkChanged{sections,records,journal}=changed
  records
def chunk_appended(+head:M.ChunkChanged,tail:M.ChunkChanged) -> M.ChunkChanged:
  M.ChunkChanged{sections,prior,journal}=head
  M.ChunkChanged{rest,records,events}=tail
  M.ChunkChanged{List.append(&2,M.Section,sections,rest),records,List.append(&2,M.CallbackEvent,journal,events)}
def chunk_sections(sections:List<&2,M.Section>,+actual:M.Chunk,+view:M.View,+records:List<&2,E.Record>) -> Result<&2,&2,T.Error,M.ChunkChanged>:
  match sections:
    case Nil{}: Done{M.ChunkChanged{[],records,[]}}
    case +head <> rest:
      do Result<&2,&2,T.Error,M.ChunkChanged>:
        +changed : M.ChunkChanged <- chunk_head(head,actual,view,records)
        +tail : M.ChunkChanged <- chunk_sections(rest,actual,view,chunk_records(changed))
        return chunk_appended(changed,tail)
def erase_chunk(values:List<&2,M.Chunk>,+actual:M.Chunk) -> List<&2,M.Chunk>:
  match values:
    case Nil{}: []
    case +head <> +rest:
      M.Chunk{od,ox,oz,l,v}=head
      M.Chunk{+d,+x,+z,loaded,visibility}=actual
      +tail=erase_chunk(rest,actual)
      choose(List<&2,M.Chunk>,tail,head <> tail,String.eq(d,od) && U32.is_eq(U32.and(x,4194303),U32.and(ox,4194303)) && U32.is_eq(U32.and(z,4194303),U32.and(oz,4194303)))
def updated_chunk(view:M.View,+actual:M.Chunk,next_order:Nat,changed:M.ChunkChanged) -> M.Proposal:
  M.View{members,old,+chunks,tracked,ticked}=view
  M.ChunkChanged{sections,records,journal}=changed
  stage(M.View{members,sections,actual <> erase_chunk(chunks,actual),tracked,ticked},next_order,records,journal)
def update_chunk(+view:M.View,+actual:M.Chunk,+next_order:Nat,+records:List<&2,E.Record>) -> Result<&2,&2,T.Error,M.Proposal>:
  M.View{members,+sections,chunks,tracked,ticked}=view
  do Result<&2,&2,T.Error,M.Proposal>:
    +changed : M.ChunkChanged <- chunk_sections(sorted_sections(sections),actual,view,records)
    return updated_chunk(view,actual,next_order,changed)
def commit(state:M.State,result:Result<&2,&2,T.Error,M.Proposal>) -> M.State & Result<&2,&2,T.Error,M.Proposal>:
  match result:
    case Fail{error}: (state,Fail{error})
    case Done{+proposal}:
      M.Proposal{view,next_order,records,journal}=proposal
      (M.State{view},Done{proposal})
def inspected(+view:M.View) -> M.State & M.View: (M.State{view},view)
def inspect(state:M.State) -> M.State & M.View:
  M.State{view}=state
  inspected(view)
