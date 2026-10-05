import Base
import ./extended_persistence.bend as Persistence
import ./local_player_cooking_publication_laws.bend as Laws

def Laws.failed_save_retains_complete_publication_owner(context,journal,tail,message):
  {==}
def Laws.publisher_return_retains_complete_entity_owner(context,state,times,geometry,returned,status):
  {==}
def Laws.failed_save_retains_complete_cooking_sidecar(context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,entity_context,state,times,geometry,publisher_context,journal,publisher_tail,tail,message):
  {==}
def Laws.nondurable_receipt_retains_complete_session(state,snapshot):
  {==}
def Laws.absent_save_snapshot_retains_complete_session(state,receipt):
  match receipt:
    case Persistence.NotCommitted{}: {==}
    case Persistence.DurablyCommitted{}: {==}
def Laws.noncanonical_publication_tail_retains_complete_owner(engine,context,journal,child,tail,producer,current,position):
  {==}
