import Base
import ./local_player_cooking_tick_storage_laws.bend as L
import ./local_player_cooking_tick_storage.bend as S
import ./local_player_effect_tick_recovery.bend as Q
import ./local_player_effect_tick_recovery_laws.bend as Recovery
import ./local_player_effect_tick_recovery_proof.bend as RecoveryProof
import ./cooking_effect_entities_model.bend as E
import ./item_entity_tick_model.bend as T
import ./random.bend as R
import ./entity_section_membership_model.bend as M

def L.inspect_retains_complete_tick_owner_and_sidecars(view,runtimes,sound,clocks,membership):
  %Recovery.tick_inspect_retains_complete_owner(view,runtimes,sound) :
    {S.inspected(clocks,membership,Q.inspect(T.State{E.install(view),runtimes,sound})) == S.inspected(clocks,membership,_) : T.State & S.Stored}
  {==}
def L.restore_retains_complete_separate_authorities(view,runtimes,sound,clocks,membership): {==}
def L.full_restore_inspect_is_lossless(view,runtimes,sound,clocks,membership):
  %L.inspect_retains_complete_tick_owner_and_sidecars(view,runtimes,sound,clocks,membership) :
    {Done{S.inspect(T.State{E.install(view),runtimes,sound},clocks,membership)} == Done{_} : Result<&2,&1,String,T.State & S.Stored>}
  {==}
def L.unavailable_runtime_cannot_be_restored_from_entity_records(view,clocks,membership): {==}
