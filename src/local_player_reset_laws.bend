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

# These are whole-owner composition laws over the functions used by the saved
# remote_resource_server actor. Service premises are actual production results;
# none assumes the theorem's final State. They preserve Engine and Tables,
# rather than dropping them to compare a small scalar projection.
#
# The success law states an extensional single-completion property. It does not
# prove a runtime cost/call-count theorem or IEEE arithmetic correctness: the
# actual LM/H/T outcomes and FR read-only answer remain explicit premises.
law resolved_required_travel_commits_one_history_and_finish_result:
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
  for accumulated: {H.movement(H.NeutralDryNoDamage{}, MH.movement_from(MH.outcome_transition(move), FR.observation_clip(observation)), H.State{TH.frame_history(frame)}) == (H.State{history}, Done{Unit{}}) : H.State & Result<&2, &2, H.Error, Unit>}
  for completed: {T.finish_checked(prepared, MH.outcome_transition(move)) == Done{finished} : Result<&2, &2, T.Error, M.Transition>}
  {TH.reset_prepared(engine, frame, policy, (tables, Done{prepared})) == (MH.State{W.attach(engine, TH.with_body(candidate, LM.transition_body(finished))), support, minor, H.State{history}, []}, returned, Done{TH.ResetOutcome{TH.Outcome{TH.Preparation{prepared, []}, MH.Outcome{move, history, []}, LM.Motion{finished, []}, []}, Some{observation}, []}}) : MH.State & L.Tables & Result<&2, &2, TH.ResetError, TH.ResetOutcome>}

# An actual required-ray refusal is threaded through TH, X, the facade's
# diagnostic adapter, and the complete lossless save detour. Candidate Body,
# support, minor/history, post-input/jump metadata and cache do not survive;
# the returned Engine/Tables and complete declared phase anchor do survive.
# The anchor may be direct entry or the post-common scheduled anchor.
law required_ray_refusal_restores_whole_phase_and_save_owner:
  for engine: G.Engine
  for tables: L.Tables
  for +candidate: W.View
  for support: SP.State
  for minor: LM.MinorState
  for +reset_work: TH.ResetWork
  for +phase_work: X.Work
  for +cause: FR.Error
  for refused: {FR.clip_checked(W.attach(engine, candidate), TH.reset_ray_request(TH.reset_work_stage(reset_work), MH.outcome_transition(TH.reset_work_move(reset_work)))) == (W.attach(engine, candidate), Fail{cause}) : W.State & Result<&2, &2, FR.Error, FR.Observation>}
  {R.reattach(R.detach(R.tick_result(X.reset_stage_traveled(phase_work, TH.reset_requirement(W.attach(engine, candidate), tables, support, minor, reset_work, True{}))))) == R.with_error(X.State{MH.State{W.attach(engine, X.frame_view(X.work_frame(phase_work))), X.frame_support(X.work_frame(phase_work)), X.frame_minor(X.work_frame(phase_work)), H.State{X.frame_history(X.work_frame(phase_work))}, []}, tables, X.frame_metadata(X.work_frame(phase_work)), []}, Some{R.error_text(X.reset_stage_error(TH.ResetSupplierError{cause}))}) : X.State}

# The scheduled interface equals direct preparation at the *actual* successful
# post-common state: Core.step occurs once, ECT.common_tick occurs once, and the
# same world, support/minor/history, tables and all other metadata are carried.
# There is no claim that direct preparation at the old state is equivalent.
law scheduled_preparation_equals_direct_after_one_common_tick:
  for world: C.World
  for registry: B.Registry
  for tables: L.Tables
  for +view: W.View
  for +support: SP.State
  for +minor: LM.MinorState
  for +history: H.History
  for +metadata: X.Metadata
  for +request: X.PrepareRequest
  for +entity: ECT.Metadata
  for +look: PL.State
  for common: {ECT.common_tick(ECT.State{X.entity(metadata), []}, ECT.Request{X.body_position(X.view_body(view)), PR.look(X.controls(metadata)), X.pre_request_common(request), []}) == (ECT.State{entity, []}, Done{ECT.Snapshot{entity, look}}) : ECT.State & Result<&2, &2, ECT.Error, ECT.Snapshot>}
  {X.pre_scheduled_ready(X.State{MH.State{W.attach(G.Engine{world, registry}, view), support, minor, H.State{history}, []}, tables, metadata, []}, request) == X.pre_local_ready(X.State{MH.State{W.attach(G.Engine{C.step(world), registry}, view), support, minor, H.State{history}, []}, tables, X.with_entity(X.with_controls(metadata, X.with_look(X.controls(metadata), look)), entity), []}, request) : X.PrepareResult}

