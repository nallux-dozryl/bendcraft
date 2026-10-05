import Base
import ./entity_section_membership_recovery_model.bend as D
import ./entity_section_membership_model.bend as M
import ./entity_section_membership.bend as MS
import ./entity_membership_codec_validation.bend as Check
import ./cooking_effect_entities_model.bend as E
import ./item_entity_tick_model.bend as T
import ./item_entity_tick_fields.bend as U
import ./geometry.bend as A
import ./movement.bend as Movement
import ./f64.bend as F
import ./random.bend as R

def checked(result:Result<&2,&2,String,Unit>) -> Result<&2,&2,T.Error,Unit>:
  match result:
    case Fail{message}: Fail{T.Refused{message}}
    case Done{unit}: Done{Unit{}}
def double_eq(a:F.F64,b:F.F64) -> Bool:
  F.F64{+ah,+al}=a
  F.F64{+bh,+bl}=b
  U32.is_eq(ah,bh) && U32.is_eq(al,bl)
def box_eq(a:A.AABB,b:A.AABB) -> Bool:
  A.AABB{x,y,z,p,q,r}=a
  A.AABB{g,h,i,j,k,l}=b
  double_eq(x,g) && double_eq(y,h) && double_eq(z,i) && double_eq(p,j) && double_eq(q,k) && double_eq(r,l)
def no_invalid(value:Maybe<&2,U32>) -> Bool:
  match value:
    case None{}: True{}
    case Some{index}: False{}
def finite_box(value:A.AABB) -> Bool: no_invalid(A.AABB.invalid_field(value))
# Pinned cooking-effect reference observes .25 Item and .5 Orb dimensions.
# This validates a saved box; it never changes a registered key or saved box.
def actual_box(+record:E.Record) -> A.AABB:
  match record:
    case E.Item{c,i,a,d,h,t,target,bob}: U.body(record)
    case E.Orb{c,v,a,h,n,following}: Movement.make_box(U.mv(U.pos(record)),0.5,0.5)
def record_count(values:List<&2,E.Record>,+id:U32) -> Nat:
  match values:
    case Nil{}: 0n
    case +head <> rest: Nat.add(MS.choose(Nat,1n,0n,U32.is_eq(E.record_id(head),id)),record_count(rest,id))
def runtime_count(values:List<&2,T.RuntimeEntry>,+id:U32) -> Nat:
  match values:
    case Nil{}: 0n
    case T.RuntimeEntry{key,runtime} <> rest:
      Nat.add(MS.choose(Nat,1n,0n,U32.is_eq(key,id)),runtime_count(rest,id))
def order_count(values:List<&2,M.Member>,+order:Nat) -> Nat:
  match values:
    case Nil{}: 0n
    case M.Member{d,id,key,other,box,uuid} <> rest:
      Nat.add(MS.choose(Nat,1n,0n,Nat.is_eq(other,order)),order_count(rest,order))
def records_valid(values:List<&2,E.Record>,+all:List<&2,E.Record>,+runtimes:List<&2,T.RuntimeEntry>,+members:List<&2,M.Member>) -> Result<&2,&2,T.Error,Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case +head <> rest:
      +id=E.record_id(head)
      +dimension=MS.common_dimension(E.common(head))
      do Result<&2,&2,T.Error,Unit>:
        U.guard(Nat.is_eq(record_count(all,id),1n),"membership recovery requires globally unique retained entity IDs")
        U.guard(Nat.is_eq(runtime_count(runtimes,id),1n),"membership recovery requires one actual retained runtime for every record")
        U.guard(Nat.is_eq(MS.member_count(members,dimension,id),MS.choose(Nat,0n,1n,U.removed(head))),"membership recovery requires live registration and removed tombstone detachment")
        records_valid(rest,all,runtimes,members)
def runtimes_valid(values:List<&2,T.RuntimeEntry>,+records:List<&2,E.Record>) -> Result<&2,&2,T.Error,Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case T.RuntimeEntry{id,runtime} <> rest:
      do Result<&2,&2,T.Error,Unit>:
        U.guard(Nat.is_eq(record_count(records,id),1n),"membership recovery refuses an orphan runtime")
        runtimes_valid(rest,records)
def member_record(+member:M.Member,+visibility:M.Visibility,+record:E.Record,+cursor:Nat) -> Result<&2,&2,T.Error,Unit>:
  M.Member{dimension,id,+key,+order,+box,+uuid}=member
  +common=E.common(record)
  do Result<&2,&2,T.Error,Unit>:
    U.guard(Bool.not(U.removed(record)),"membership recovery refuses a registered removed record")
    U.guard(MS.uuid_eq(uuid,MS.common_uuid(common)),"membership recovery UUID disagrees with retained record")
    U.guard(MS.key_eq(key,MS.key(U.pos(record))),"membership recovery registered packed key disagrees with retained position callback")
    U.guard(Nat.is_eq(order,MS.common_order(common)) && Nat.is_lt(order,cursor),"membership recovery order/cursor disagrees with retained record")
    U.guard(MS.bool_eq(MS.common_accessible(common),MS.accessible(visibility)),"membership recovery cached accessibility disagrees with retained record")
    U.guard(finite_box(box) && box_eq(box,actual_box(record)),"membership recovery actual entity box disagrees with retained record or is unsupported")
    return Unit{}
def located_record(+found:M.Located,+record:E.Record,+cursor:Nat) -> Result<&2,&2,T.Error,Unit>:
  M.Located{+member,M.Section{d,k,visibility,ids}}=found
  member_record(member,visibility,record,cursor)
def members_valid(values:List<&2,M.Member>,+view:M.View,+records:List<&2,E.Record>,+cursor:Nat) -> Result<&2,&2,T.Error,Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case +head <> rest:
      M.Member{+dimension,+id,key,+order,box,uuid}=head
      M.View{+all,sections,chunks,tracked,ticked}=view
      do Result<&2,&2,T.Error,Unit>:
        U.guard(Nat.is_eq(order_count(all,order),1n),"membership recovery refuses duplicate insertion order")
        U.guard(Nat.is_eq(MS.record_count(records,dimension,id),1n),"membership recovery registered record is missing or duplicated")
        +actual : E.Record <- MS.record(records,dimension,id)
        +found : M.Located <- MS.locate(view,dimension,id)
        located_record(found,actual,cursor)
        members_valid(rest,view,records,cursor)
def chunk_key(value:M.Chunk) -> M.SectionKey:
  M.Chunk{dimension,x,z,loaded,status}=value
  M.SectionKey{U32.and(x,4194303),0,U32.and(z,4194303)}
def observation_valid(+actual:M.Chunk) -> Result<&2,&2,T.Error,Unit>:
  M.Chunk{d,x,z,+loaded,+visibility}=actual
  U.guard(loaded || Bool.not(MS.accessible(visibility)),"membership recovery refuses accessible visibility without current loaded evidence")
def observations_valid(values:List<&2,M.Chunk>,+all:List<&2,M.Chunk>) -> Result<&2,&2,T.Error,Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case +head <> rest:
      M.Chunk{+dimension,x,z,loaded,status}=head
      do Result<&2,&2,T.Error,Unit>:
        U.guard(Nat.is_eq(MS.chunk_count(all,dimension,chunk_key(head)),1n),"membership recovery current loader observations must be unique")
        observation_valid(head)
        observations_valid(rest,all)
def observations_cover(values:List<&2,M.Chunk>,+actual:List<&2,M.Chunk>) -> Result<&2,&2,T.Error,Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case +head <> rest:
      M.Chunk{+dimension,x,z,loaded,status}=head
      do Result<&2,&2,T.Error,Unit>:
        U.guard(Nat.is_eq(MS.chunk_count(actual,dimension,chunk_key(head)),1n),"membership recovery current loader observation is missing for a saved chunk")
        observations_cover(rest,actual)
def entities_with_records(view:E.View,records:List<&2,E.Record>) -> E.View:
  E.View{level,unique,cursor,order,prior}=view
  E.View{level,unique,cursor,order,records}
def reconciled(+prior:D.Plan,proposal:M.Proposal) -> D.Plan:
  D.Plan{+entities,runtimes,membership,+journal}=prior
  M.Proposal{next,order,records,events}=proposal
  D.Plan{entities_with_records(entities,records),runtimes,next,List.append(&2,M.CallbackEvent,journal,events)}
def reconcile(observations:List<&2,M.Chunk>,+plan:D.Plan) -> Result<&2,&2,T.Error,D.Plan>:
  match observations:
    case Nil{}: Done{plan}
    case head <> rest:
      D.Plan{E.View{level,unique,cursor,+order,+records},runtimes,+membership,journal}=plan
      do Result<&2,&2,T.Error,D.Plan>:
        +proposal : M.Proposal <- MS.update_chunk(membership,head,order,records)
        reconcile(rest,reconciled(plan,proposal))
def validated(+image:M.View,+entities:E.View,+runtimes:List<&2,T.RuntimeEntry>,+current:List<&2,M.Chunk>) -> Result<&2,&2,T.Error,D.Plan>:
  M.View{+members,sections,+chunks,tracked,ticked}=image
  E.View{level,unique,cursor,+order,+records}=entities
  do Result<&2,&2,T.Error,D.Plan>:
    checked(Check.validate(image))
    records_valid(records,records,runtimes,members)
    runtimes_valid(runtimes,records)
    members_valid(members,image,records,order)
    observations_valid(current,current)
    observations_cover(chunks,current)
    reconcile(current,D.Plan{entities,runtimes,image,[]})
def observed_image(+image:M.View,+entities:E.View,+runtimes:List<&2,T.RuntimeEntry>,current:Maybe<&2,List<&2,M.Chunk>>) -> Result<&2,&2,T.Error,D.Plan>:
  match current:
    case None{}: Fail{T.Refused{"membership recovery requires actual current loader visibility observations"}}
    case Some{facts}: validated(image,entities,runtimes,facts)
def prepare(image:Maybe<&2,M.View>,entities:E.View,runtimes:List<&2,T.RuntimeEntry>,current:Maybe<&2,List<&2,M.Chunk>>) -> Result<&2,&2,T.Error,D.Plan>:
  match image:
    case None{}: Fail{T.Refused{"membership recovery image is unavailable; decoded records cannot mint registration"}}
    case Some{image}: observed_image(image,entities,runtimes,current)
def installed(scene:T.State,plan:D.Plan) -> T.State & M.State & Result<&2,&2,T.Error,List<&2,M.CallbackEvent>>:
  T.State{old,prior_runtimes,sound}=scene
  D.Plan{entities,runtimes,membership,journal}=plan
  (T.State{E.install(entities),runtimes,sound},M.State{membership},Done{journal})
def accepted(scene:T.State,manager:M.State,+plan:D.Plan,result:Result<&2,&2,T.Error,Unit>) -> T.State & M.State & Result<&2,&2,T.Error,List<&2,M.CallbackEvent>>:
  match result:
    case Fail{error}: (scene,manager,Fail{error})
    case Done{unit}: installed(scene,plan)
def commit(scene:T.State,manager:M.State,result:Result<&2,&2,T.Error,D.Plan>,acceptance:Result<&2,&2,T.Error,Unit>) -> T.State & M.State & Result<&2,&2,T.Error,List<&2,M.CallbackEvent>>:
  match result:
    case Fail{error}: (scene,manager,Fail{error})
    case Done{plan}: accepted(scene,manager,plan,acceptance)
def activated(+image:Maybe<&2,M.View>,+current:Maybe<&2,List<&2,M.Chunk>>,+runtimes:List<&2,T.RuntimeEntry>,+sound:Maybe<&2,R.Source>,manager:M.State,+acceptance:Result<&2,&2,T.Error,Unit>,result:E.State & E.View) -> T.State & M.State & Result<&2,&2,T.Error,List<&2,M.CallbackEvent>>:
  (owner,+view)=result
  commit(T.State{owner,runtimes,sound},manager,prepare(image,view,runtimes,current),acceptance)
def activate(scene:T.State,manager:M.State,image:Maybe<&2,M.View>,current:Maybe<&2,List<&2,M.Chunk>>,acceptance:Result<&2,&2,T.Error,Unit>) -> T.State & M.State & Result<&2,&2,T.Error,List<&2,M.CallbackEvent>>:
  T.State{owner,runtimes,sound}=scene
  activated(image,current,runtimes,sound,manager,acceptance,E.inspect(owner))

def record_length(values:List<&2,E.Record>) -> Nat:
  match values:
    case Nil{}: 0n
    case head <> rest: 1n+record_length(rest)
def prior_ids_retained(values:List<&2,E.Record>,+constructed:List<&2,E.Record>) -> Bool:
  match values:
    case Nil{}: True{}
    case +head <> rest:
      Nat.is_eq(record_count(constructed,E.record_id(head)),1n) && prior_ids_retained(rest,constructed)
def constructor_cursor(+before:Nat,+after:Nat) -> Result<&2,&2,T.Error,Unit>:
  do Result<&2,&2,T.Error,Unit>:
    U.guard(Nat.is_lt(before,Check.maximum_order()),"fresh registration insertion cursor is exhausted")
    U.guard(Nat.is_eq(after,1n+before),"fresh registration requires exactly one constructor cursor advance")
def constructor_ready(before:E.View) -> Result<&2,&2,T.Error,Unit>:
  E.View{level,unique,id,order,records}=before
  U.guard(Nat.is_lt(order,Check.maximum_order()),"fresh registration insertion cursor is exhausted")
def fresh_added(+base:D.Plan,+constructed:E.Plan,+record:E.Record,+runtime:T.Runtime,proposal:M.Proposal) -> D.Fresh:
  D.Plan{entities,+runtimes,membership,+prior}=base
  E.Plan{E.View{+level,+unique,+id,order,records},remaining}=constructed
  M.Proposal{membership,+next_order,+records,journal}=proposal
  D.Fresh{D.Plan{E.View{level,unique,id,next_order,records},List.append(&2,T.RuntimeEntry,runtimes,[T.RuntimeEntry{E.record_id(record),runtime}]),membership,List.append(&2,M.CallbackEvent,prior,journal)},remaining}
def moved_proposal(moved:M.Moved) -> M.Proposal:
  M.Moved{snapshot,proposal}=moved
  proposal
def fresh_base(+base:D.Plan,+constructed:E.Plan,+record:E.Record,+runtime:T.Runtime,+pre_order:Nat) -> Result<&2,&2,T.Error,D.Fresh>:
  D.Plan{E.View{level,unique,id,order,+prior},runtimes,+membership,journal}=base
  +box=actual_box(record)
  do Result<&2,&2,T.Error,D.Fresh>:
    U.guard(finite_box(box),"fresh registration requires a verified finite actual entity box")
    moved : M.Moved <- MS.on_add(membership,T.Snapshot{record,runtime},box,pre_order,List.append(&2,E.Record,prior,[record]),True{})
    return fresh_added(base,constructed,record,runtime,moved_proposal(moved))
def fresh_record(+before:E.View,+manager:M.View,+runtimes:List<&2,T.RuntimeEntry>,+constructed:E.Plan,+id:U32,+runtime:T.Runtime,+current:Maybe<&2,List<&2,M.Chunk>>,+record:E.Record) -> Result<&2,&2,T.Error,D.Fresh>:
  E.View{level,unique,cursor,+order,+prior}=before
  do Result<&2,&2,T.Error,D.Fresh>:
    U.guard(Nat.is_eq(MS.common_order(E.common(record)),order),"fresh record must carry the pre-registration constructor order")
    U.guard(Nat.is_eq(record_count(prior,id),0n) && Nat.is_eq(runtime_count(runtimes,id),0n),"fresh registration entity/runtime ID is already owned")
    +base : D.Plan <- prepare(Some{manager},before,runtimes,current)
    fresh_base(base,constructed,record,runtime,order)
# E.item_created already assigns pre_order and advances its proposed cursor.
# The manager registers with that same pre_order; it never advances it twice.
# Existing records come from the retained owner, with only loader accessibility
# reconciliation applied, rather than trusting a constructor's copied prefix.
def constructor_dimension(records:List<&2,E.Record>,+id:U32) -> String:
  match records:
    case Nil{}: ""
    case +head <> +rest:
      MS.choose(String,MS.common_dimension(E.common(head)),constructor_dimension(rest,id),U32.is_eq(E.record_id(head),id))
def fresh_prepare(+before:E.View,+manager:M.View,+runtimes:List<&2,T.RuntimeEntry>,+constructed:E.Plan,+id:U32,+runtime:T.Runtime,+current:Maybe<&2,List<&2,M.Chunk>>) -> Result<&2,&2,T.Error,D.Fresh>:
  E.View{level,unique,cursor,+pre_order,+prior}=before
  E.Plan{E.View{level,unique,+last_id,+next_order,+records},remaining}=constructed
  do Result<&2,&2,T.Error,D.Fresh>:
    constructor_cursor(pre_order,next_order)
    U.guard(U32.is_eq(last_id,id) && Nat.is_eq(record_count(records,id),1n),"fresh constructor entity ID/cursor is inconsistent")
    U.guard(Nat.is_eq(record_length(records),1n+record_length(prior)) && prior_ids_retained(prior,records),"fresh constructor must add exactly one retained entity identity")
    +record : E.Record <- MS.record(records,constructor_dimension(records,id),id)
    fresh_record(before,manager,runtimes,constructed,id,runtime,current,record)
def fresh_installed(scene:T.State,+fresh:D.Fresh) -> T.State & M.State & Result<&2,&2,T.Error,D.FreshPublication>:
  T.State{old,prior_runtimes,sound}=scene
  D.Fresh{D.Plan{entities,runtimes,membership,journal},remaining}=fresh
  (T.State{E.install(entities),runtimes,sound},M.State{membership},Done{D.FreshPublication{journal,remaining}})
def fresh_accepted(scene:T.State,manager:M.State,+fresh:D.Fresh,result:Result<&2,&2,T.Error,Unit>) -> T.State & M.State & Result<&2,&2,T.Error,D.FreshPublication>:
  match result:
    case Fail{error}: (scene,manager,Fail{error})
    case Done{unit}: fresh_installed(scene,fresh)
def fresh_commit(scene:T.State,manager:M.State,result:Result<&2,&2,T.Error,D.Fresh>,acceptance:Result<&2,&2,T.Error,Unit>) -> T.State & M.State & Result<&2,&2,T.Error,D.FreshPublication>:
  match result:
    case Fail{error}: (scene,manager,Fail{error})
    case Done{fresh}: fresh_accepted(scene,manager,fresh,acceptance)
def fresh_inspected(+membership:M.View,+constructed:E.Plan,+id:U32,+runtime:T.Runtime,+current:Maybe<&2,List<&2,M.Chunk>>,+runtimes:List<&2,T.RuntimeEntry>,+sound:Maybe<&2,R.Source>,manager:M.State,+acceptance:Result<&2,&2,T.Error,Unit>,result:E.State & E.View) -> T.State & M.State & Result<&2,&2,T.Error,D.FreshPublication>:
  (owner,+view)=result
  fresh_commit(T.State{owner,runtimes,sound},manager,fresh_prepare(view,membership,runtimes,constructed,id,runtime,current),acceptance)
def fresh_owned(scene:T.State,+constructed:E.Plan,+id:U32,+runtime:T.Runtime,+current:Maybe<&2,List<&2,M.Chunk>>,+acceptance:Result<&2,&2,T.Error,Unit>,result:M.State & M.View) -> T.State & M.State & Result<&2,&2,T.Error,D.FreshPublication>:
  T.State{owner,runtimes,sound}=scene
  (manager,membership)=result
  fresh_inspected(membership,constructed,id,runtime,current,runtimes,sound,manager,acceptance,E.inspect(owner))
def fresh(scene:T.State,manager:M.State,constructed:E.Plan,id:U32,runtime:T.Runtime,current:Maybe<&2,List<&2,M.Chunk>>,acceptance:Result<&2,&2,T.Error,Unit>) -> T.State & M.State & Result<&2,&2,T.Error,D.FreshPublication>:
  fresh_owned(scene,constructed,id,runtime,current,acceptance,MS.inspect(manager))
