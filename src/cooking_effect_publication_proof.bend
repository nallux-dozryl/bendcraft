import Base
import ./cooking_effect_publication_journal.bend as J
import ./cooking_effect_publication_laws.bend as Laws

def Laws.failed_full_save_retains_complete_journal(owner,message): {==}

def Laws.future_snapshot_cannot_clear_complete_journal(sequence,unsaved,last,saved,chunks,future):
  %Equal.sym(Bool,Nat.is_le(saved,sequence),False{},future) :
    {J.committed_valid(J.State{J.View{sequence,unsaved,last}},J.Snapshot{saved,chunks},
        (_ && J.chunks_valid(chunks,saved,Set.new()))) ==
      J.State{J.View{sequence,unsaved,last}} : J.State}
  {==}

def Laws.repeated_mark_deduplicates_actual_chunk_and_advances_receipt(captured,last): {==}
def Laws.older_actual_save_preserves_later_same_chunk_and_latest_receipt(first,later): {==}
def Laws.older_actual_save_clears_only_saved_chunk_and_preserves_latest_receipt(first,later): {==}
def Laws.missing_current_source_retains_complete_engine_and_journal(engine,owner): {==}
def Laws.lit_change_attests_same_owner_and_new_incarnation_retains_owners(engine,owner): {==}
