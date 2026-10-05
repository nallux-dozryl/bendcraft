import Base
import ./entity_chunk_loading_model.bend as M
import ./entity_chunk_loading_math.bend as A
import ./entity_chunk_loading_tickets.bend as T

def unavailable(scope:M.Scope,reason:String) -> M.State: M.Unavailable{scope,reason}
def refuse(state:M.State,message:String) -> M.State & Result<&2,&2,String,Unit>:
  (state,Fail{message})
def commit(+view:M.View,result:Result<&2,&2,String,M.View>) -> M.State & Result<&2,&2,String,Unit>:
  match result:
    case Fail{message}: (M.State{view},Fail{message})
    case Done{next}: (M.State{next},Done{Unit{}})
def initialized(scope:M.Scope,reason:String,+context:M.Context,valid:Bool) -> M.State & Result<&2,&2,String,Unit>:
  match valid:
    case False{}: (M.Unavailable{scope,reason},Fail{"actual loader context was not admitted"})
    case True{}: (M.State{M.View{context,[],[],[],M.Word64{0,0},[]}},Done{Unit{}})
# Called by the actual provider's constructor seam, never by reading a saved
# manager, a camera footprint or resident Core sections. No live actor provider
# is currently installed; unavailable remains the honest startup owner there.
def initialize(state:M.State,+context:M.Context) -> M.State & Result<&2,&2,String,Unit>:
  match state:
    case M.State{view}: (M.State{view},Fail{"actual chunk loader is already initialized"})
    case M.Unavailable{+scope,reason}:
      initialized(scope,reason,context,T.context_valid(context) && A.scope_equal(scope,T.context_scope(context)))
def add_ticket(state:M.State,scope:M.Scope,key:M.ChunkKey,name:String,level:U32) -> M.State & Result<&2,&2,String,Unit>:
  match state:
    case M.Unavailable{actual,reason}: refuse(M.Unavailable{actual,reason},"actual chunk ticket producer is unavailable")
    case M.State{+view}: commit(view,T.add_plan(view,scope,key,name,level))
def remove_ticket(state:M.State,scope:M.Scope,key:M.ChunkKey,name:String,level:U32) -> M.State & Result<&2,&2,String,Unit>:
  match state:
    case M.Unavailable{actual,reason}: refuse(M.Unavailable{actual,reason},"actual chunk ticket producer is unavailable")
    case M.State{+view}: commit(view,T.remove_plan(view,scope,key,name,level))
def chunk_key(chunk:M.Chunk) -> M.ChunkKey:
  M.Chunk{key,level,status,loaded,promotion,entities,holder}=chunk
  key
def chunk_count(chunks:List<&2,M.Chunk>,+key:M.ChunkKey) -> Nat:
  match chunks:
    case Nil{}: 0n
    case head <> rest:
      Nat.add(A.choose(Nat,1n,0n,A.key_equal(chunk_key(head),key)),chunk_count(rest,key))
def found_head(head:M.Chunk,otherwise:Result<&2,&2,String,M.Chunk>,same:Bool) -> Result<&2,&2,String,M.Chunk>:
  match same:
    case True{}: Done{head}
    case False{}: otherwise
def chunk_find(chunks:List<&2,M.Chunk>,+key:M.ChunkKey) -> Result<&2,&2,String,M.Chunk>:
  match chunks:
    case Nil{}: Fail{"actual chunk scheduling observation is missing"}
    case +head <> rest: found_head(head,chunk_find(rest,key),A.key_equal(chunk_key(head),key))
def replaced_head(head:M.Chunk,rest:List<&2,M.Chunk>,replacement:M.Chunk,otherwise:List<&2,M.Chunk>,same:Bool) -> List<&2,M.Chunk>:
  match same:
    case True{}: replacement <> rest
    case False{}: head <> otherwise
def chunk_replace(chunks:List<&2,M.Chunk>,+replacement:M.Chunk) -> List<&2,M.Chunk>:
  match chunks:
    case Nil{}: [replacement]
    case +head <> +rest: replaced_head(head,rest,replacement,chunk_replace(rest,replacement),A.key_equal(chunk_key(head),chunk_key(replacement)))
def updated(view:M.View,chunk:M.Chunk,next:M.Word64,events:List<&2,M.LoaderEvent>) -> M.View:
  M.View{context,active,inactive,chunks,previous,journal}=view
  M.View{context,active,inactive,chunk_replace(chunks,chunk),next,List.append(&2,M.LoaderEvent,journal,events)}
def request_available(current:M.Word64,full:Bool) -> Result<&2,&2,String,M.Word64>:
  match full:
    case True{}: Fail{"chunk callback request identity is exhausted"}
    case False{}: Done{A.word_increment(current)}
def next_request(+current:M.Word64) -> Result<&2,&2,String,M.Word64>: request_available(current,A.word_full(current))
def cancelled(scope:M.Scope,key:M.ChunkKey,promotion:Maybe<&2,M.Promotion>) -> List<&2,M.LoaderEvent>:
  match promotion:
    case None{}: []
    case Some{M.Promotion{request,status}}: [M.PromotionCancelled{M.Receipt{scope,key,request}}]
def status_selected(key:M.ChunkKey,old:M.FullStatus,status:M.FullStatus,same:Bool) -> List<&2,M.LoaderEvent>:
  match same:
    case True{}: []
    case False{}: [M.StatusChanged{key,old,status}]
def status_events(key:M.ChunkKey,+old:M.FullStatus,+status:M.FullStatus) -> List<&2,M.LoaderEvent>: status_selected(key,old,status,A.status_equal(old,status))
def promotion_decided(+view:M.View,+scope:M.Scope,+key:M.ChunkKey,+level:U32,+desired:M.FullStatus,confirmed:M.FullStatus,loaded:Bool,promotion:Maybe<&2,M.Promotion>,entities:M.EntityPhase,holder:Maybe<&2,M.HolderReadiness>,next:M.Word64,promote:Bool) -> Result<&2,&2,String,M.View>:
  match promote:
    case True{}:
      do Result<&2,&2,String,M.View>:
        +request : M.Word64 <- next_request(next)
        return updated(view,M.Chunk{key,level,confirmed,loaded,Some{M.Promotion{request,desired}},entities,holder},request,
          List.append(&2,M.LoaderEvent,cancelled(scope,key,promotion),[M.PromotionRequested{M.Receipt{scope,key,request},desired}]))
    case False{}:
      Done{updated(view,M.Chunk{key,level,desired,loaded && U32.is_ne(A.status_rank(desired),0),None{},entities,holder},next,
        List.append(&2,M.LoaderEvent,cancelled(scope,key,promotion),status_events(key,confirmed,desired)))}
def level_changed(+view:M.View,scope:M.Scope,key:M.ChunkKey,level:U32,+desired:M.FullStatus,chunk:M.Chunk) -> Result<&2,&2,String,M.View>:
  M.View{context,active,inactive,chunks,next,journal}=view
  M.Chunk{old_key,+old_level,confirmed,loaded,promotion,entities,holder}=chunk
  promotion_decided(view,scope,key,level,desired,confirmed,loaded,promotion,entities,holder,next,U32.is_gt(A.status_rank(desired),A.status_rank(A.full_status(old_level))))
def level_same(+view:M.View,scope:M.Scope,key:M.ChunkKey,level:U32,desired:M.FullStatus,chunk:M.Chunk,same:Bool) -> Result<&2,&2,String,M.View>:
  M.View{context,active,inactive,chunks,next,journal}=view
  M.Chunk{old_key,old_level,confirmed,loaded,promotion,entities,holder}=chunk
  match same:
    case True{}: Done{updated(view,M.Chunk{key,level,confirmed,loaded,promotion,entities,holder},next,[])}
    case False{}: level_changed(view,scope,key,level,desired,M.Chunk{old_key,old_level,confirmed,loaded,promotion,entities,holder})
def observed_level(view:M.View,scope:M.Scope,key:M.ChunkKey,+level:U32,desired:M.FullStatus,+chunk:M.Chunk) -> Result<&2,&2,String,M.View>:
  M.Chunk{old_key,old_level,confirmed,loaded,promotion,entities,holder}=chunk
  level_same(view,scope,key,level,desired,chunk,A.status_equal(A.full_status(old_level),A.full_status(level)))
def new_level(+view:M.View,+scope:M.Scope,+key:M.ChunkKey,+level:U32,desired:M.FullStatus,inaccessible:Bool) -> Result<&2,&2,String,M.View>:
  M.View{context,active,inactive,chunks,+next,journal}=view
  match inaccessible:
    case True{}: Done{updated(view,M.Chunk{key,level,M.Inaccessible{},False{},None{},M.Fresh{},None{}},next,[])}
    case False{}: observed_level(view,scope,key,level,desired,M.Chunk{key,U32.add(T.context_maximum(context),1),M.Inaccessible{},False{},None{},M.Fresh{},None{}})
def level_selected(view:M.View,scope:M.Scope,key:M.ChunkKey,level:U32,+desired:M.FullStatus,existing:Result<&2,&2,String,M.Chunk>) -> Result<&2,&2,String,M.View>:
  match existing:
    case Done{chunk}: observed_level(view,scope,key,level,desired,chunk)
    case Fail{message}: new_level(view,scope,key,level,desired,A.status_equal(desired,M.Inaccessible{}))
def schedule_plan(+view:M.View,+scope:M.Scope,+key:M.ChunkKey,+level:U32) -> Result<&2,&2,String,M.View>:
  M.View{context,active,inactive,+chunks,next,journal}=view
  do Result<&2,&2,String,M.View>:
    _ : Unit <- T.guard(A.scope_equal(T.context_scope(context),scope),"chunk scheduling world/epoch mismatch")
    _ : Unit <- T.guard(Nat.is_le(chunk_count(chunks,key),1n),"duplicate actual chunk scheduling observation")
    level_selected(view,scope,key,level,A.full_status(level),chunk_find(chunks,key))
# The producer reports DistanceManager's actual scheduling event. Ticket source
# arithmetic alone does not call this function or publish a FullStatus.
def observe_schedule(state:M.State,scope:M.Scope,key:M.ChunkKey,level:U32) -> M.State & Result<&2,&2,String,Unit>:
  match state:
    case M.Unavailable{actual,reason}: refuse(M.Unavailable{actual,reason},"actual chunk scheduling producer is unavailable")
    case M.State{+view}: commit(view,schedule_plan(view,scope,key,level))
def promotion_matches(promotion:Maybe<&2,M.Promotion>,request:M.Word64,status:M.FullStatus) -> Bool:
  match promotion:
    case None{}: False{}
    case Some{M.Promotion{actual,expected}}: A.word_equal(actual,request) && A.status_equal(expected,status)
def with_entities(view:M.View,scope:M.Scope,+key:M.ChunkKey,level:U32,status:M.FullStatus,
    phase:M.EntityPhase,holder:Maybe<&2,M.HolderReadiness>,+next:M.Word64,events:List<&2,M.LoaderEvent>) -> Result<&2,&2,String,M.View>:
  match phase:
    case M.Fresh{}:
      do Result<&2,&2,String,M.View>:
        +request : M.Word64 <- next_request(next)
        return updated(view,M.Chunk{key,level,status,True{},None{},M.Pending{request},holder},request,
          List.append(&2,M.LoaderEvent,events,[M.EntitiesRequested{M.Receipt{scope,key,request}}]))
    case _:
      Done{updated(view,M.Chunk{key,level,status,True{},None{},phase,holder},next,events)}
def completed_chunk(+view:M.View,+completion:M.FullCompletion,chunk:M.Chunk) -> Result<&2,&2,String,M.View>:
  M.View{context,active,inactive,chunks,next,journal}=view
  M.FullCompletion{M.Receipt{+scope,+key,+request},+status}=completion
  M.Chunk{actual,+level,old,loaded,+promotion,phase,holder}=chunk
  do Result<&2,&2,String,M.View>:
    _ : Unit <- T.guard(promotion_matches(promotion,request,status),"stale or mismatched full-chunk completion")
    _ : Unit <- T.guard(A.status_equal(A.full_status(level),status) && U32.is_ne(A.status_rank(status),0),"full-chunk completion no longer requested")
    with_entities(view,scope,key,level,status,phase,holder,next,status_events(key,old,status))
def full_plan(+view:M.View,+completion:M.FullCompletion) -> Result<&2,&2,String,M.View>:
  M.View{context,active,inactive,+chunks,next,journal}=view
  M.FullCompletion{M.Receipt{+scope,+key,request},status}=completion
  do Result<&2,&2,String,M.View>:
    _ : Unit <- T.guard(A.scope_equal(T.context_scope(context),scope),"full-chunk completion world/epoch mismatch")
    _ : Unit <- T.guard(Nat.is_eq(chunk_count(chunks,key),1n),"full-chunk completion requires one actual request")
    actual : M.Chunk <- chunk_find(chunks,key)
    completed_chunk(view,completion,actual)
# Only a successful current ChunkResult / promotion callback reaches this seam.
# It is a lifecycle event, not a boolean read from a saved manager or Core.
def full_completed(state:M.State,completion:M.FullCompletion) -> M.State & Result<&2,&2,String,Unit>:
  match state:
    case M.Unavailable{actual,reason}: refuse(M.Unavailable{actual,reason},"actual full-chunk completion producer is unavailable")
    case M.State{+view}: commit(view,full_plan(view,completion))
def phase_pending(phase:M.EntityPhase,request:M.Word64) -> Bool:
  match phase:
    case M.Pending{actual}: A.word_equal(actual,request)
    case _: False{}
def phase_inbox(phase:M.EntityPhase,request:M.Word64,artifact:String) -> Bool:
  match phase:
    case M.Inbox{actual,identity}: A.word_equal(actual,request) && String.eq(identity,artifact)
    case _: False{}
def phase_loaded(phase:M.EntityPhase,request:M.Word64,artifact:String) -> Bool:
  match phase:
    case M.Loaded{actual,identity}: A.word_equal(actual,request) && String.eq(identity,artifact)
    case _: False{}
def batch_chunk(+view:M.View,+batch:M.EntityBatch,chunk:M.Chunk,+insert:Bool) -> Result<&2,&2,String,M.View>:
  M.View{context,active,inactive,chunks,next,journal}=view
  M.EntityBatch{M.Receipt{scope,+key,+request},+artifact}=batch
  M.Chunk{old,level,status,loaded,promotion,+phase,holder}=chunk
  do Result<&2,&2,String,M.View>:
    _ : Unit <- T.guard(Bool.not(String.is_empty(artifact)),"actual entity-storage completion identity is missing")
    _ : Unit <- T.guard(A.choose(Bool,phase_inbox(phase,request,artifact),phase_pending(phase,request),insert),"stale or duplicate entity-storage completion")
    return updated(view,M.Chunk{key,level,status,loaded,promotion,
      A.choose(M.EntityPhase,M.Loaded{request,artifact},M.Inbox{request,artifact},insert),holder},next,
      [A.choose(M.LoaderEvent,M.EntitiesInserted{batch},M.EntitiesAvailable{batch},insert)])
def batch_plan(+view:M.View,+batch:M.EntityBatch,insert:Bool) -> Result<&2,&2,String,M.View>:
  M.View{context,active,inactive,+chunks,next,journal}=view
  M.EntityBatch{M.Receipt{scope,+key,request},artifact}=batch
  do Result<&2,&2,String,M.View>:
    _ : Unit <- T.guard(A.scope_equal(T.context_scope(context),scope),"entity-storage completion world/epoch mismatch")
    _ : Unit <- T.guard(Nat.is_eq(chunk_count(chunks,key),1n),"entity-storage completion requires one actual request")
    chunk : M.Chunk <- chunk_find(chunks,key)
    batch_chunk(view,batch,chunk,insert)
# Success first enters the inbox. The current M/E owner must perform insertion
# before acknowledging entities_inserted with that exact batch identity.
def entities_available(state:M.State,batch:M.EntityBatch) -> M.State & Result<&2,&2,String,Unit>:
  match state:
    case M.Unavailable{actual,reason}: refuse(M.Unavailable{actual,reason},"actual entity-storage producer is unavailable")
    case M.State{+view}: commit(view,batch_plan(view,batch,False{}))
def entities_inserted(state:M.State,batch:M.EntityBatch) -> M.State & Result<&2,&2,String,Unit>:
  match state:
    case M.Unavailable{actual,reason}: refuse(M.Unavailable{actual,reason},"actual entity insertion consumer is unavailable")
    case M.State{+view}: commit(view,batch_plan(view,batch,True{}))
def failed_chunk(+view:M.View,+receipt:M.Receipt,message:String,chunk:M.Chunk) -> Result<&2,&2,String,M.View>:
  M.View{context,active,inactive,chunks,next,journal}=view
  M.Receipt{scope,key,request}=receipt
  M.Chunk{actual,level,status,loaded,promotion,+phase,holder}=chunk
  do Result<&2,&2,String,M.View>:
    _ : Unit <- T.guard(phase_pending(phase,request),"stale entity-storage failure")
    return updated(view,M.Chunk{actual,level,status,loaded,promotion,phase,holder},next,[M.EntityReadFailed{receipt,message}])
def failure_plan(+view:M.View,+receipt:M.Receipt,message:String) -> Result<&2,&2,String,M.View>:
  M.View{context,active,inactive,+chunks,next,journal}=view
  M.Receipt{scope,+key,request}=receipt
  do Result<&2,&2,String,M.View>:
    _ : Unit <- T.guard(A.scope_equal(T.context_scope(context),scope),"entity-storage failure world/epoch mismatch")
    chunk : M.Chunk <- chunk_find(chunks,key)
    failed_chunk(view,receipt,message,chunk)
# Pinned Java logs a read failure and leaves PENDING. It does not fabricate an
# empty successful batch or automatically start a second request.
def entity_failed(state:M.State,receipt:M.Receipt,message:String) -> M.State & Result<&2,&2,String,Unit>:
  match state:
    case M.Unavailable{actual,reason}: refuse(M.Unavailable{actual,reason},"actual entity-storage producer is unavailable")
    case M.State{+view}: commit(view,failure_plan(view,receipt,message))
def unload_ready(chunk:M.Chunk) -> Bool:
  M.Chunk{key,level,status,loaded,promotion,phase,holder}=chunk
  match status phase:
    case M.Inaccessible{} M.Fresh{}: True{}
    case M.Inaccessible{} M.Loaded{request,artifact}: True{}
    case _ _: False{}
def unloaded_chunk(+view:M.View,+batch:M.EntityBatch,chunk:M.Chunk) -> Result<&2,&2,String,M.View>:
  M.View{context,active,inactive,chunks,next,journal}=view
  M.EntityBatch{M.Receipt{scope,key,request},artifact}=batch
  M.Chunk{actual,level,+status,loaded,promotion,+phase,holder}=chunk
  do Result<&2,&2,String,M.View>:
    _ : Unit <- T.guard(A.status_equal(status,M.Inaccessible{}),"entity unload requires actual hidden chunk status")
    _ : Unit <- T.guard(phase_loaded(phase,request,artifact),"entity unload requires the current completed insertion")
    return updated(view,M.Chunk{actual,level,status,loaded,promotion,M.Fresh{},holder},next,[M.EntitiesUnloaded{batch}])
def unload_plan(+view:M.View,+batch:M.EntityBatch) -> Result<&2,&2,String,M.View>:
  M.View{context,active,inactive,+chunks,next,journal}=view
  M.EntityBatch{M.Receipt{scope,+key,request},artifact}=batch
  do Result<&2,&2,String,M.View>:
    _ : Unit <- T.guard(A.scope_equal(T.context_scope(context),scope),"entity unload world/epoch mismatch")
    chunk : M.Chunk <- chunk_find(chunks,key)
    unloaded_chunk(view,batch,chunk)
# Called after the actual hidden-chunk store/unload consumer completes. Pending
# or inbox data cannot be declared unloaded; the returned owner is retained.
def entities_unloaded(state:M.State,batch:M.EntityBatch) -> M.State & Result<&2,&2,String,Unit>:
  match state:
    case M.Unavailable{actual,reason}: refuse(M.Unavailable{actual,reason},"actual entity unload consumer is unavailable")
    case M.State{+view}: commit(view,unload_plan(view,batch))
def holder_chunk(view:M.View,key:M.ChunkKey,holder:M.HolderReadiness,chunk:M.Chunk) -> M.View:
  M.View{context,active,inactive,chunks,+next,journal}=view
  M.Chunk{actual,level,status,loaded,promotion,phase,previous}=chunk
  updated(M.View{context,active,inactive,chunks,next,journal},M.Chunk{actual,level,status,loaded,promotion,phase,Some{holder}},next,[])
def holder_plan(+view:M.View,scope:M.Scope,+key:M.ChunkKey,holder:M.HolderReadiness) -> Result<&2,&2,String,M.View>:
  M.View{context,active,inactive,+chunks,next,journal}=view
  do Result<&2,&2,String,M.View>:
    _ : Unit <- T.guard(A.scope_equal(T.context_scope(context),scope),"ChunkHolder observation world/epoch mismatch")
    chunk : M.Chunk <- chunk_find(chunks,key)
    return holder_chunk(view,key,holder,chunk)
def observe_holder(state:M.State,scope:M.Scope,key:M.ChunkKey,holder:M.HolderReadiness) -> M.State & Result<&2,&2,String,Unit>:
  match state:
    case M.Unavailable{actual,reason}: refuse(M.Unavailable{actual,reason},"actual ChunkHolder observation producer is unavailable")
    case M.State{+view}: commit(view,holder_plan(view,scope,key,holder))
def purged_view(view:M.View,+key:M.ChunkKey,result:M.TicketsChanged) -> M.View:
  M.View{+context,active,inactive,chunks,next,journal}=view
  M.TicketsChanged{+tickets,changed,loading,simulation}=result
  M.View{context,T.bucket_replace(active,key,tickets),inactive,chunks,next,
    List.append(&2,M.LoaderEvent,journal,T.bulk_events(key,tickets,U32.add(T.context_maximum(context),1),loading,simulation))}
def holder_found(result:Result<&2,&2,String,M.Chunk>) -> Maybe<&2,M.HolderReadiness>:
  match result:
    case Fail{message}: None{}
    case Done{M.Chunk{key,level,status,loaded,promotion,phase,holder}}: holder
def purge_plan(+view:M.View,scope:M.Scope,+key:M.ChunkKey) -> Result<&2,&2,String,M.View>:
  M.View{context,+active,inactive,+chunks,next,journal}=view
  do Result<&2,&2,String,M.View>:
    _ : Unit <- T.guard(A.scope_equal(T.context_scope(context),scope),"ticket expiration world/epoch mismatch")
    _ : Unit <- T.guard(Nat.is_le(T.bucket_count(active,key),1n),"duplicate actual chunk ticket bucket")
    holder : Maybe<&2,M.HolderReadiness> = holder_found(chunk_find(chunks,key))
    changed : M.TicketsChanged <- T.purge_entries(T.bucket_tickets(active,key),holder)
    return purged_view(view,key,changed)
def purge_chunk(state:M.State,scope:M.Scope,key:M.ChunkKey) -> M.State & Result<&2,&2,String,Unit>:
  match state:
    case M.Unavailable{actual,reason}: refuse(M.Unavailable{actual,reason},"actual ticket expiration producer is unavailable")
    case M.State{+view}: commit(view,purge_plan(view,scope,key))
def inspect(state:M.State) -> M.State & Result<&2,&2,String,M.View>:
  match state:
    case M.Unavailable{scope,+reason}: (M.Unavailable{scope,reason},Fail{reason})
    case M.State{+view}: (M.State{view},Done{view})
