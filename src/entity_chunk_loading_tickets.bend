import Base
import ./entity_chunk_loading_model.bend as M
import ./entity_chunk_loading_math.bend as A

def guard(allowed:Bool,message:String) -> Result<&2,&2,String,Unit>:
  match allowed:
    case True{}: Done{Unit{}}
    case False{}: Fail{message}
def context_scope(context:M.Context) -> M.Scope:
  M.Context{scope,types,maximum}=context
  scope
def context_maximum(context:M.Context) -> U32:
  M.Context{scope,types,maximum}=context
  maximum
def type_found(head:M.TicketType,otherwise:Result<&2,&2,String,M.TicketType>,equal:Bool) -> Result<&2,&2,String,M.TicketType>:
  A.choose(Result<&2,&2,String,M.TicketType>,Done{head},otherwise,equal)
def type_named(types:List<&2,M.TicketType>,+name:String) -> Result<&2,&2,String,M.TicketType>:
  match types:
    case Nil{}: Fail{"actual chunk ticket type is unavailable"}
    case +head <> rest:
      M.TicketType{identity,time,flags}=head
      type_found(head,type_named(rest,name),String.eq(identity,name))
def type_name_count(types:List<&2,M.TicketType>,+name:String) -> Nat:
  match types:
    case Nil{}: 0n
    case M.TicketType{identity,time,flags} <> rest:
      Nat.add(A.choose(Nat,1n,0n,String.eq(identity,name)),type_name_count(rest,name))
def types_valid(types:List<&2,M.TicketType>) -> Bool:
  match types:
    case Nil{}: True{}
    case M.TicketType{+identity,time,flags} <> +rest:
      Bool.not(String.is_empty(identity)) && Nat.is_eq(type_name_count(rest,identity),0n) && types_valid(rest)
def context_valid(context:M.Context) -> Bool:
  M.Context{M.Scope{world,dimension,epoch},types,+maximum}=context
  Bool.not(String.is_empty(world)) && Bool.not(String.is_empty(dimension)) && types_valid(types) &&
    U32.is_ge(maximum,33) && U32.is_lt(maximum,2147483647)
def ticket_new(kind:M.TicketType,level:U32) -> M.Ticket:
  M.TicketType{+name,+timeout,+flags}=kind
  M.Ticket{M.TicketType{name,timeout,flags},level,timeout}
def ticket_level(ticket:M.Ticket) -> U32:
  M.Ticket{kind,level,left}=ticket
  level
def ticket_kind(ticket:M.Ticket) -> M.TicketType:
  M.Ticket{kind,level,left}=ticket
  kind
def reset(ticket:M.Ticket) -> M.Ticket:
  M.Ticket{kind,level,left}=ticket
  ticket_new(kind,level)
def ticket_timed_out(ticket:M.Ticket) -> Bool:
  M.Ticket{kind,level,left}=ticket
  A.has_timeout(kind) && A.word_negative(left)
def decreased(ticket:M.Ticket) -> M.Ticket:
  M.Ticket{+kind,level,+left}=ticket
  M.Ticket{kind,level,A.choose(M.Word64,A.word_decrement(left),left,A.has_timeout(kind))}
def lowest_with(level:U32,next:Maybe<&2,U32>) -> Maybe<&2,U32>:
  match next:
    case None{}: Some{level}
    case Some{other}: Some{A.int_min(level,other)}
def lowest_head(level:U32,+next:Maybe<&2,U32>,eligible:Bool) -> Maybe<&2,U32>:
  A.choose(Maybe<&2,U32>,lowest_with(level,next),next,eligible)
def lowest(tickets:List<&2,M.Ticket>,+channel:M.Channel) -> Maybe<&2,U32>:
  match tickets:
    case Nil{}: None{}
    case M.Ticket{kind,level,left} <> rest:
      lowest_head(level,lowest(rest,channel),A.channel_flag(kind,channel))
def lowest_result(fallback:U32,result:Maybe<&2,U32>) -> U32:
  match result:
    case None{}: fallback
    case Some{actual}: actual
def source_level(tickets:List<&2,M.Ticket>,channel:M.Channel,fallback:U32) -> U32:
  lowest_result(fallback,lowest(tickets,channel))
def bucket_count(buckets:List<&2,M.Bucket>,+key:M.ChunkKey) -> Nat:
  match buckets:
    case Nil{}: 0n
    case M.Bucket{candidate,tickets} <> rest:
      Nat.add(A.choose(Nat,1n,0n,A.key_equal(candidate,key)),bucket_count(rest,key))
def bucket_tickets(buckets:List<&2,M.Bucket>,+key:M.ChunkKey) -> List<&2,M.Ticket>:
  match buckets:
    case Nil{}: []
    case M.Bucket{candidate,tickets} <> rest:
      A.choose(List<&2,M.Ticket>,tickets,bucket_tickets(rest,key),A.key_equal(candidate,key))
def bucket_replacement(key:M.ChunkKey,tickets:List<&2,M.Ticket>,rest:List<&2,M.Bucket>) -> List<&2,M.Bucket>:
  match tickets:
    case Nil{}: rest
    case _: M.Bucket{key,tickets} <> rest
def bucket_replace(buckets:List<&2,M.Bucket>,+key:M.ChunkKey,+tickets:List<&2,M.Ticket>) -> List<&2,M.Bucket>:
  match buckets:
    case Nil{}:
      match tickets:
        case Nil{}: []
        case _: [M.Bucket{key,tickets}]
    case +head <> +rest:
      M.Bucket{candidate,previous}=head
      A.choose(List<&2,M.Bucket>,bucket_replacement(key,tickets,rest),
        head <> bucket_replace(rest,key,tickets),A.key_equal(candidate,key))
def ticket_count(tickets:List<&2,M.Ticket>,+candidate:M.Ticket) -> Nat:
  match tickets:
    case Nil{}: 0n
    case head <> rest:
      Nat.add(A.choose(Nat,1n,0n,A.same_ticket(head,candidate)),ticket_count(rest,candidate))
def type_matches(kind:M.TicketType,result:Result<&2,&2,String,M.TicketType>) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{actual}: A.type_equal(kind,actual)
def tickets_valid(+types:List<&2,M.TicketType>,tickets:List<&2,M.Ticket>) -> Bool:
  match tickets:
    case Nil{}: True{}
    case +head <> +rest:
      M.Ticket{+kind,level,left}=head
      M.TicketType{+name,time,flags}=kind
      Nat.is_eq(ticket_count(rest,head),0n) &&
        type_matches(kind,type_named(types,name)) && tickets_valid(types,rest)
def buckets_valid(+types:List<&2,M.TicketType>,buckets:List<&2,M.Bucket>) -> Bool:
  match buckets:
    case Nil{}: True{}
    case M.Bucket{+key,+tickets} <> +rest:
      Nat.is_eq(bucket_count(rest,key),0n) && Bool.not(List.is_empty(&2,M.Ticket,tickets)) &&
        tickets_valid(types,tickets) && buckets_valid(types,rest)
def add_prepend(head:M.Ticket,result:M.TicketsChanged) -> M.TicketsChanged:
  M.TicketsChanged{tickets,changed,loading,simulation}=result
  M.TicketsChanged{head <> tickets,changed,loading,simulation}
def add_found(+head:M.Ticket,rest:List<&2,M.Ticket>,otherwise:M.TicketsChanged,equal:Bool) -> M.TicketsChanged:
  A.choose(M.TicketsChanged,M.TicketsChanged{reset(head) <> rest,False{},False{},False{}},
    add_prepend(head,otherwise),equal)
def add_entries(tickets:List<&2,M.Ticket>,+candidate:M.Ticket) -> M.TicketsChanged:
  match tickets:
    case Nil{}: M.TicketsChanged{[candidate],True{},False{},False{}}
    case +head <> +rest:
      add_found(head,rest,add_entries(rest,candidate),A.same_ticket(head,candidate))
def removed(head:M.Ticket,rest:List<&2,M.Ticket>) -> M.TicketsChanged:
  M.Ticket{+kind,level,left}=head
  M.TicketsChanged{rest,True{},A.type_flag(kind,2),A.type_flag(kind,4)}
def remove_found(+head:M.Ticket,rest:List<&2,M.Ticket>,otherwise:M.TicketsChanged,equal:Bool) -> M.TicketsChanged:
  A.choose(M.TicketsChanged,removed(head,rest),add_prepend(head,otherwise),equal)
def remove_entries(tickets:List<&2,M.Ticket>,+candidate:M.Ticket) -> M.TicketsChanged:
  match tickets:
    case Nil{}: M.TicketsChanged{[],False{},False{},False{}}
    case +head <> +rest:
      remove_found(head,rest,remove_entries(rest,candidate),A.same_ticket(head,candidate))
def source_event(key:M.ChunkKey,channel:M.Channel,level:U32,decrease:Bool,publish:Bool) -> List<&2,M.LoaderEvent>:
  match publish:
    case False{}: []
    case True{}: [M.SourceLevelChanged{key,channel,level,decrease}]
# The actual direct add/remove listener order is simulation, then loading.
def direct_events(+key:M.ChunkKey,+before:List<&2,M.Ticket>,+after:List<&2,M.Ticket>,
    +fallback:U32,+added:Bool,+changed:Bool,loading:Bool,simulation:Bool) -> List<&2,M.LoaderEvent>:
  +old_sim=source_level(before,M.Simulation{},fallback)
  +old_load=source_level(before,M.Loading{},fallback)
  +new_sim=source_level(after,M.Simulation{},fallback)
  +new_load=source_level(after,M.Loading{},fallback)
  List.append(&2,M.LoaderEvent,
    source_event(key,M.Simulation{},new_sim,added,changed && simulation && (Bool.not(added) || A.int_less(new_sim,old_sim))),
    source_event(key,M.Loading{},new_load,added,changed && loading && (Bool.not(added) || A.int_less(new_load,old_load))))
def changed_view(+view:M.View,+key:M.ChunkKey,+before:List<&2,M.Ticket>,+kind:M.TicketType,
    +added:Bool,result:M.TicketsChanged) -> M.View:
  M.View{+context,active,inactive,chunks,next,journal}=view
  M.TicketsChanged{+tickets,+changed,loading,simulation}=result
  M.View{context,bucket_replace(active,key,tickets),inactive,chunks,next,
    List.append(&2,M.LoaderEvent,journal,direct_events(key,before,tickets,U32.add(context_maximum(context),1),
      added,changed,A.choose(Bool,A.type_flag(kind,2),loading,added),A.choose(Bool,A.type_flag(kind,4),simulation,added)))}
def add_plan(+view:M.View,+scope:M.Scope,+key:M.ChunkKey,+name:String,level:U32) -> Result<&2,&2,String,M.View>:
  M.View{+context,+active,inactive,chunks,next,journal}=view
  M.Context{actual,+types,maximum}=context
  do Result<&2,&2,String,M.View>:
    _ : Unit <- guard(A.scope_equal(actual,scope),"chunk ticket world/epoch mismatch")
    _ : Unit <- guard(Nat.is_le(bucket_count(active,key),1n),"duplicate actual chunk ticket bucket")
    +kind : M.TicketType <- type_named(types,name)
    +before : List<&2,M.Ticket> = bucket_tickets(active,key)
    return changed_view(view,key,before,kind,True{},add_entries(before,ticket_new(kind,level)))
def remove_plan(+view:M.View,scope:M.Scope,+key:M.ChunkKey,name:String,level:U32) -> Result<&2,&2,String,M.View>:
  M.View{context,+active,inactive,chunks,next,journal}=view
  M.Context{actual,types,maximum}=context
  do Result<&2,&2,String,M.View>:
    _ : Unit <- guard(A.scope_equal(actual,scope),"chunk ticket world/epoch mismatch")
    _ : Unit <- guard(Nat.is_le(bucket_count(active,key),1n),"duplicate actual chunk ticket bucket")
    +kind : M.TicketType <- type_named(types,name)
    +before : List<&2,M.Ticket> = bucket_tickets(active,key)
    return changed_view(view,key,before,kind,False{},remove_entries(before,ticket_new(kind,level)))
# This is the settled graph value, not a chunk-ready or status callback. A
# caller must still observe ChunkHolder's successful future confirmation.
def capped_level(+level:U32,+dist:U32,+cap:U32) -> U32:
  A.choose(U32,U32.min(dist,cap),
    U32.add(U32.min(level,cap),U32.min(dist,U32.sub(cap,U32.min(level,cap)))),A.int_less(level,0))
def level_entries(tickets:List<&2,M.Ticket>,+channel:M.Channel,+dist:U32,+cap:U32) -> U32:
  match tickets:
    case Nil{}: cap
    case M.Ticket{kind,level,left} <> rest:
      +remaining=level_entries(rest,channel,dist,cap)
      A.choose(U32,U32.min(capped_level(level,dist,cap),remaining),remaining,A.channel_flag(kind,channel))
def settled_level(buckets:List<&2,M.Bucket>,+key:M.ChunkKey,+channel:M.Channel,+cap:U32) -> U32:
  match buckets:
    case Nil{}: cap
    case M.Bucket{other,tickets} <> rest:
      U32.min(level_entries(tickets,channel,A.distance(other,key),cap),settled_level(rest,key,channel,cap))
# Long countdown subtraction is exact. Expiration pauses for a real updating
# holder not ready for saving, unless CAN_EXPIRE_IF_UNLOADED is set.
def expiry_qualified(timed:Bool,bypass:Bool,holder:Maybe<&2,M.HolderReadiness>) -> Result<&2,&2,String,Bool>:
  match timed bypass:
    case False{} _: Done{False{}}
    case True{} True{}: Done{True{}}
    case True{} False{}:
      match holder:
        case None{}: Fail{"actual ChunkHolder save-readiness observation is missing"}
        case Some{M.NotReadyForSaving{}}: Done{False{}}
        case _: Done{True{}}
def expiry_allowed(+kind:M.TicketType,holder:Maybe<&2,M.HolderReadiness>) -> Result<&2,&2,String,Bool>:
  expiry_qualified(A.has_timeout(kind),A.type_flag(kind,16),holder)
def purge_tail(+head:M.Ticket,result:M.TicketsChanged,+expire:Bool) -> M.TicketsChanged:
  M.Ticket{+kind,level,left}=head
  M.TicketsChanged{+tail,+changed,+loading,+simulation}=result
  M.TicketsChanged{A.choose(List<&2,M.Ticket>,tail,head <> tail,expire),changed || expire,
    loading || (expire && A.type_flag(kind,2)),simulation || (expire && A.type_flag(kind,4))}
def purged_head(+head:M.Ticket,+allowed:Bool,result:Result<&2,&2,String,M.TicketsChanged>) -> Result<&2,&2,String,M.TicketsChanged>:
  +changed=A.choose(M.Ticket,decreased(head),head,allowed)
  do Result<&2,&2,String,M.TicketsChanged>:
    tail : M.TicketsChanged <- result
    return purge_tail(changed,tail,allowed && ticket_timed_out(changed))
def purge_entries(tickets:List<&2,M.Ticket>,+holder:Maybe<&2,M.HolderReadiness>) -> Result<&2,&2,String,M.TicketsChanged>:
  match tickets:
    case Nil{}: Done{M.TicketsChanged{[],False{},False{},False{}}}
    case +head <> rest:
      do Result<&2,&2,String,M.TicketsChanged>:
        allowed : Bool <- expiry_allowed(ticket_kind(head),holder)
        purged_head(head,allowed,purge_entries(rest,holder))
# Bulk expiry/close listener order is loading, then simulation, even when the
# new minimum is unchanged. Caller iteration order is kept explicitly.
def bulk_events(+key:M.ChunkKey,+tickets:List<&2,M.Ticket>,+fallback:U32,loading:Bool,simulation:Bool) -> List<&2,M.LoaderEvent>:
  List.append(&2,M.LoaderEvent,source_event(key,M.Loading{},source_level(tickets,M.Loading{},fallback),False{},loading),
    source_event(key,M.Simulation{},source_level(tickets,M.Simulation{},fallback),False{},simulation))
