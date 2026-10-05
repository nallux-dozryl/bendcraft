import Base
import ./entity_chunk_loading_model.bend as M
import ./entity_chunk_loading_math.bend as A
import ./entity_chunk_loading_tickets.bend as T
import ./entity_chunk_loading.bend as L
import ./entity_chunk_loading_observation.bend as O
import ./entity_section_membership_model.bend as Membership

# Entire actual metadata owners are quantified: tickets, inactive tickets,
# request counters, pending completions and the ordered callback journal.
law unavailable_ticket_retains_complete_owner:
  for scope:M.Scope
  for reason:String
  for supplied:M.Scope
  for key:M.ChunkKey
  for name:String
  for level:U32
  {L.add_ticket(M.Unavailable{scope,reason},supplied,key,name,level) ==
    (M.Unavailable{scope,reason},Fail{"actual chunk ticket producer is unavailable"}) :
    M.State & Result<&2,&2,String,Unit>}
law refused_transition_retains_complete_loader:
  for view:M.View
  for message:String
  {L.commit(view,Fail{message}) == (M.State{view},Fail{message}) : M.State & Result<&2,&2,String,Unit>}
law unavailable_completion_never_creates_loaded_authority:
  for scope:M.Scope
  for reason:String
  for receipt:M.FullCompletion
  {L.full_completed(M.Unavailable{scope,reason},receipt) ==
    (M.Unavailable{scope,reason},Fail{"actual full-chunk completion producer is unavailable"}) :
    M.State & Result<&2,&2,String,Unit>}
law pending_entities_are_not_a_loaded_receipt:
  for request:M.Word64
  {A.entities_loaded(M.Pending{request}) == False{} : Bool}
law successful_future_inbox_is_not_completed_insertion:
  for request:M.Word64
  for artifact:String
  {A.entities_loaded(M.Inbox{request,artifact}) == False{} : Bool}
law actual_loaded_phase_is_recognized:
  for request:M.Word64
  for artifact:String
  {A.entities_loaded(M.Loaded{request,artifact}) == True{} : Bool}
law storage_pending_does_not_disable_actual_ticking_visibility:
  for key:M.ChunkKey
  for level:U32
  for loaded:Bool
  for promotion:Maybe<&2,M.Promotion>
  for request:M.Word64
  for holder:Maybe<&2,M.HolderReadiness>
  {(A.can_tick(M.EntityTicking{}),L.unload_ready(M.Chunk{key,level,M.EntityTicking{},loaded,promotion,M.Pending{request},holder})) ==
    (True{},False{}) : Bool & Bool}
law hidden_pending_load_cannot_be_declared_unloaded:
  for key:M.ChunkKey
  for level:U32
  for loaded:Bool
  for promotion:Maybe<&2,M.Promotion>
  for request:M.Word64
  for holder:Maybe<&2,M.HolderReadiness>
  {L.unload_ready(M.Chunk{key,level,M.Inaccessible{},loaded,promotion,M.Pending{request},holder}) == False{} : Bool}
law unloaded_status_never_ticking:
  {A.can_tick(M.Inaccessible{}) == False{} : Bool}
law full_and_block_ticking_are_tracked:
  {(A.visibility(M.Full{}),A.visibility(M.BlockTicking{})) == (M.Tracked{},M.Tracked{}) : M.Visibility & M.Visibility}
law no_timeout_preserves_every_raw_countdown:
  for identity:String
  for flags:U32
  for level:U32
  for left:M.Word64
  {T.decreased(M.Ticket{M.TicketType{identity,M.Word64{0,0},flags},level,left}) ==
    M.Ticket{M.TicketType{identity,M.Word64{0,0},flags},level,left} : M.Ticket}
law exact_zero_timeout_is_not_expired:
  for identity:String
  for flags:U32
  for level:U32
  for left:M.Word64
  {T.ticket_timed_out(M.Ticket{M.TicketType{identity,M.Word64{0,0},flags},level,left}) == False{} : Bool}

law absent_provider_never_mints_current_recovery_facts:
  for scope:M.Scope
  for reason:String
  for supplied:M.Scope
  {O.current(M.Unavailable{scope,reason},supplied) ==
    (M.Unavailable{scope,reason},Fail{"actual chunk ticket/status/load-completion provider is unavailable: " ++ reason}) :
    M.State & Result<&2,&2,String,List<&2,Membership.Chunk>>}
