import Base
import ./inventory.bend as Inv
import ./player_inventory.bend as I
import ./remote_resource_backend.bend as B
import ./remote_resource_transport.bend as T
import ./player_crafting_session_adapter.bend as CS
import ./local_player_session.bend as S
import ./local_phase_runtime.bend as X
import ./world_lock.bend as Lock
import ./persistence.bend as P
import ./extended_persistence.bend as E
import ./world_generation_settings.bend as WG
import ./core.bend as Core
import ./local_player_cooking.bend as Cooking

law rollback_inventory_reinstalls_complete_original_owner:
  for original:I.State
  for candidate:I.State
  {T.restored_inventory(original,candidate) == (original,Unit{}) : I.State & Unit}

law actual_actor_rollback_retains_world_shell_context_and_owner:
  for player:X.State
  for identity:String
  for path:String
  for highwater:U32
  for limits:P.Limits
  for lock:Lock.Lease
  for maximum:U32
  for catalog:List<&2,E.Operation>
  for fresh:Bool
  for generation:WG.Settings
  for cooking:Cooking.Sidecar
  for original:I.State
  for candidate:I.State
  for lease:B.Lease
  for new_lease:B.Lease
  for counter:Nat
  for nonce:String
  for capability:String
  for owner:Core.Capability
  for crafting:Maybe<&2,CS.Context>
  for new_crafting:Maybe<&2,CS.Context>
  {T.restore_menu(T.MenuRollback{original,lease,crafting},
      B.State{S.State{player,S.Shell{identity,path,highwater,limits,lock,maximum,catalog,candidate,fresh,generation,cooking}},new_lease,counter,nonce,capability,owner,new_crafting}) ==
    B.State{S.State{player,S.Shell{identity,path,highwater,limits,lock,maximum,catalog,original,fresh,generation,cooking}},B.renewed(lease),counter,nonce,capability,owner,crafting} : B.State}

law admitted_prospective_reply_publishes_exact_candidate_and_bytes:
  for epoch:String
  for sequence:Nat
  for rollback:T.MenuRollback
  for candidate:B.State
  for +answer:T.Answer
  for +text:String
  {T.prospective_encoded(epoch,sequence,rollback,candidate,answer,Done{text}) ==
    (candidate,T.PreparedAnswer{answer,Done{text}}) : B.State & T.PreparedAnswer}
