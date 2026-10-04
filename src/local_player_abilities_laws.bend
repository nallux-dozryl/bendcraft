import Base
import ./local_travel_history.bend as TH
import ./local_phase_runtime.bend as X
import ./local_player_runtime.bend as R
import ./local_move_history.bend as MH
import ./local_move_world.bend as LM
import ./player_fall_history.bend as H
import ./fall_reset_world.bend as FR
import ./travel.bend as T
import ./movement.bend as M
import ./locomotion.bend as L
import ./client_world.bend as W
import ./support.bend as SP
import ./game.bend as G
import ./core.bend as C
import ./registry.bend as B
import ./entity_common_tick.bend as ECT
import ./player_runtime.bend as PR
import ./player_look.bend as PL

import ./player_inventory.bend as I

# Actual required-ray failure traverses the status-aware history dispatcher,
# whole-phase rollback and the status consumer. Numerical supplier results are
# premises; the full returned world/tables and all original status words remain.
law required_ray_refusal_retains_whole_owner_and_saved_status:
  for engine: G.Engine
  for tables: L.Tables
  for +candidate: W.View
  for support: SP.State
  for minor: LM.MinorState
  for +reset_work: TH.ResetWork
  for +phase_work: X.Work
  for mode: H.Mode
  for +saved: I.Status
  for selection: R.AbilitySelection
  for +cause: FR.Error
  for refused: {FR.clip_checked(W.attach(engine, candidate), TH.reset_ray_request(TH.reset_work_stage(reset_work), MH.outcome_transition(TH.reset_work_move(reset_work)))) == (W.attach(engine, candidate), Fail{cause}) : W.State & Result<&2, &2, FR.Error, FR.Observation>}
  {R.status_tick_result(saved, selection, X.reset_stage_traveled(phase_work, TH.ability_reset_requirement(mode, W.attach(engine, candidate), tables, support, minor, reset_work, True{}))) == (R.with_error(X.State{MH.State{W.attach(engine, X.frame_view(X.work_frame(phase_work))), X.frame_support(X.work_frame(phase_work)), X.frame_minor(X.work_frame(phase_work)), H.State{X.frame_history(X.work_frame(phase_work))}, []}, tables, X.frame_metadata(X.work_frame(phase_work)), []}, Some{R.error_text(X.reset_stage_error(TH.ResetSupplierError{cause}))}), saved) : X.State & I.Status}

# Provider and checked runtime are separate actual production results. Neither
# premise assumes the final saved status. The consumer publishes the complete
# returned owner, clears diagnostics and changes only the flying field after
# real post-travel ground cancellation; all raw profile words remain exact.
law admitted_tick_publishes_returned_owner_and_only_flying_status:
  for stage: X.ApplyStage
  for ready: X.ApplyStage
  for +facts: X.ApplyFacts
  for +selection: R.AbilitySelection
  for +invulnerable: Bool
  for +mayfly: Bool
  for +old_flying: Bool
  for +walking_speed: U32
  for +flying_speed: U32
  for +sprinting: Bool
  for updates: List<&2, Bool>
  for engine: G.Engine
  for +body: M.Body
  for yaw: F32
  for pitch: F32
  for palette: Maybe<&2, W.Palette>
  for region: W.Bounds
  for cache: Maybe<&2, W.SnapshotCache>
  for support: SP.State
  for minor: LM.MinorState
  for history: H.State
  for owned: List<&1, MH.State>
  for tables: L.Tables
  for metadata: X.Metadata
  for tail: List<&1, X.State>
  for observation: X.Observation
  for supplied: {X.stage_query(stage, world => support => R.status_apply_provider(I.Status{invulnerable,mayfly,old_flying,walking_speed,flying_speed},selection,sprinting,world,support)) == (ready,Done{facts}) : X.ApplyStage & Result<&2,&2,X.Error,X.ApplyFacts>}
  for applied: {X.resume_apply_with_reset_checked(ready,Done{facts},R.reset_policy()) == (X.State{MH.State{W.State{engine,body,yaw,pitch,palette,region,cache},support,minor,history,owned},tables,metadata,tail},Done{observation}) : X.State & Result<&2,&2,X.Error,X.Observation>}
  {R.status_intent(I.Status{invulnerable,mayfly,old_flying,walking_speed,flying_speed},selection,(stage,X.ApplyIntent{sprinting,updates})) == (R.with_error(X.State{MH.State{W.State{engine,body,yaw,pitch,palette,region,cache},support,minor,history,owned},tables,metadata,tail},None{}), I.Status{invulnerable,mayfly,R.selection_flying(selection) && Bool.not(R.body_grounded(body)),walking_speed,flying_speed}) : X.State & I.Status}

# Full actual LM/FR/H/T composition, including mayfly landing immunity.
law status_history_dispatch_commits_resolved_movement_once:
  for +mode: H.Mode
  for engine: G.Engine
  for tables: L.Tables
  for +frame: TH.Frame
  for +policy: TH.ResetPolicy
  for +prepared: T.Prepared
  for +candidate: W.View
  for returned: L.Tables
  for +support: SP.State
  for +minor: LM.MinorState
  for +move: LM.Outcome
  for +observation: FR.Observation
  for +history: H.History
  for +finished: M.Transition
  for resolved: {LM.move_checked(W.attach(engine, TH.with_body(TH.frame_view(frame), TH.prepared_body(prepared))), tables, TH.frame_support(frame), TH.frame_minor(frame), TH.reset_move_request(frame, prepared)) == (W.attach(engine, candidate), returned, support, minor, Done{move}) : W.State & L.Tables & SP.State & LM.MinorState & Result<&2, &2, LM.Error, LM.Outcome>}
  for metadata_valid: {H.movement_error(MH.movement_from(MH.outcome_transition(move), H.NotRequired{})) == None{} : Maybe<&2, H.Error>}
  for required: {TH.reset_is_required(TH.frame_history(frame), MH.outcome_transition(move)) == True{} : Bool}
  for supplied: {FR.clip_checked(W.attach(engine, candidate), TH.reset_ray_request(TH.ResetStage{frame, policy, TH.Preparation{prepared, []}, []}, MH.outcome_transition(move))) == (W.attach(engine, candidate), Done{observation}) : W.State & Result<&2, &2, FR.Error, FR.Observation>}
  for accumulated: {H.movement(mode, MH.movement_from(MH.outcome_transition(move), FR.observation_clip(observation)), H.State{TH.frame_history(frame)}) == (H.State{history}, Done{Unit{}}) : H.State & Result<&2, &2, H.Error, Unit>}
  for completed: {T.finish_checked(prepared, MH.outcome_transition(move)) == Done{finished} : Result<&2, &2, T.Error, M.Transition>}
  {TH.ability_reset_prepared(mode,engine, frame, policy, (tables, Done{prepared})) == (MH.State{W.attach(engine, TH.with_body(candidate, LM.transition_body(finished))), support, minor, H.State{history}, []}, returned, Done{TH.ResetOutcome{TH.Outcome{TH.Preparation{prepared, []}, MH.Outcome{move, history, []}, LM.Motion{finished, []}, []}, Some{observation}, []}}) : MH.State & L.Tables & Result<&2, &2, TH.ResetError, TH.ResetOutcome>}

