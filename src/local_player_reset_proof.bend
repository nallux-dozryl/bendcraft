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
import ./local_player_reset_laws.bend as Laws

def Laws.resolved_required_travel_commits_one_history_and_finish_result(engine, tables, frame, policy, prepared, candidate, returned, support, minor, move, observation, history, finished, resolved, metadata_valid, required, supplied, accumulated, completed):
  match candidate:
    case W.View{body, yaw, pitch, palette, region, cache}:
      %Equal.sym(W.State & L.Tables & SP.State & LM.MinorState & Result<&2, &2, LM.Error, LM.Outcome>, LM.move_checked(W.attach(engine, TH.with_body(TH.frame_view(frame), TH.prepared_body(prepared))), tables, TH.frame_support(frame), TH.frame_minor(frame), TH.reset_move_request(frame, prepared)), (W.attach(engine, candidate), returned, support, minor, Done{move}), resolved) : {TH.reset_moved(TH.ResetStage{frame, policy, TH.Preparation{prepared, []}, []}, _) == (MH.State{W.attach(engine, TH.with_body(candidate, LM.transition_body(finished))), support, minor, H.State{history}, []}, returned, Done{TH.ResetOutcome{TH.Outcome{TH.Preparation{prepared, []}, MH.Outcome{move, history, []}, LM.Motion{finished, []}, []}, Some{observation}, []}}) : MH.State & L.Tables & Result<&2, &2, TH.ResetError, TH.ResetOutcome>}
      %Equal.sym(Maybe<&2, H.Error>, H.movement_error(MH.movement_from(MH.outcome_transition(move), H.NotRequired{})), None{}, metadata_valid) : {TH.reset_metadata_checked(W.attach(engine, candidate), returned, support, minor, TH.ResetWork{TH.ResetStage{frame, policy, TH.Preparation{prepared, []}, []}, move, None{}, []}, _) == (MH.State{W.attach(engine, TH.with_body(candidate, LM.transition_body(finished))), support, minor, H.State{history}, []}, returned, Done{TH.ResetOutcome{TH.Outcome{TH.Preparation{prepared, []}, MH.Outcome{move, history, []}, LM.Motion{finished, []}, []}, Some{observation}, []}}) : MH.State & L.Tables & Result<&2, &2, TH.ResetError, TH.ResetOutcome>}
      %Equal.sym(Bool, TH.reset_is_required(TH.frame_history(frame), MH.outcome_transition(move)), True{}, required) : {TH.reset_requirement(W.attach(engine, candidate), returned, support, minor, TH.ResetWork{TH.ResetStage{frame, policy, TH.Preparation{prepared, []}, []}, move, None{}, []}, _) == (MH.State{W.attach(engine, TH.with_body(candidate, LM.transition_body(finished))), support, minor, H.State{history}, []}, returned, Done{TH.ResetOutcome{TH.Outcome{TH.Preparation{prepared, []}, MH.Outcome{move, history, []}, LM.Motion{finished, []}, []}, Some{observation}, []}}) : MH.State & L.Tables & Result<&2, &2, TH.ResetError, TH.ResetOutcome>}
      %Equal.sym(W.State & Result<&2, &2, FR.Error, FR.Observation>, FR.clip_checked(W.attach(engine, candidate), TH.reset_ray_request(TH.ResetStage{frame, policy, TH.Preparation{prepared, []}, []}, MH.outcome_transition(move))), (W.attach(engine, candidate), Done{observation}), supplied) : {TH.reset_supplied(returned, support, minor, TH.ResetWork{TH.ResetStage{frame, policy, TH.Preparation{prepared, []}, []}, move, None{}, []}, _) == (MH.State{W.attach(engine, TH.with_body(candidate, LM.transition_body(finished))), support, minor, H.State{history}, []}, returned, Done{TH.ResetOutcome{TH.Outcome{TH.Preparation{prepared, []}, MH.Outcome{move, history, []}, LM.Motion{finished, []}, []}, Some{observation}, []}}) : MH.State & L.Tables & Result<&2, &2, TH.ResetError, TH.ResetOutcome>}
      %Equal.sym(H.State & Result<&2, &2, H.Error, Unit>, H.movement(H.NeutralDryNoDamage{}, MH.movement_from(MH.outcome_transition(move), FR.observation_clip(observation)), H.State{TH.frame_history(frame)}), (H.State{history}, Done{Unit{}}), accumulated) : {TH.reset_history_finished(W.attach(engine, candidate), returned, support, minor, TH.ResetWork{TH.ResetStage{frame, policy, TH.Preparation{prepared, []}, []}, move, Some{observation}, []}, _) == (MH.State{W.attach(engine, TH.with_body(candidate, LM.transition_body(finished))), support, minor, H.State{history}, []}, returned, Done{TH.ResetOutcome{TH.Outcome{TH.Preparation{prepared, []}, MH.Outcome{move, history, []}, LM.Motion{finished, []}, []}, Some{observation}, []}}) : MH.State & L.Tables & Result<&2, &2, TH.ResetError, TH.ResetOutcome>}
      %Equal.sym(Result<&2, &2, T.Error, M.Transition>, T.finish_checked(prepared, MH.outcome_transition(move)), Done{finished}, completed) : {TH.reset_finished(W.attach(engine, candidate), returned, support, minor, H.State{history}, TH.ResetWork{TH.ResetStage{frame, policy, TH.Preparation{prepared, []}, []}, move, Some{observation}, []}, _) == (MH.State{W.attach(engine, TH.with_body(candidate, LM.transition_body(finished))), support, minor, H.State{history}, []}, returned, Done{TH.ResetOutcome{TH.Outcome{TH.Preparation{prepared, []}, MH.Outcome{move, history, []}, LM.Motion{finished, []}, []}, Some{observation}, []}}) : MH.State & L.Tables & Result<&2, &2, TH.ResetError, TH.ResetOutcome>}
      {==}

def Laws.required_ray_refusal_restores_whole_phase_and_save_owner(engine, tables, candidate, support, minor, reset_work, phase_work, cause, refused):
  match candidate reset_work:
    case W.View{body, yaw, pitch, palette, region, cache} TH.ResetWork{TH.ResetStage{TH.Frame{W.View{old_body, old_yaw, old_pitch, old_palette, old_region, old_cache}, old_support, old_minor, old_history, old_request, frame_tail}, policy, prepared, stage_tail}, move, ray, work_tail}:
      %Equal.sym(W.State & Result<&2, &2, FR.Error, FR.Observation>, FR.clip_checked(W.attach(engine, candidate), TH.reset_ray_request(TH.reset_work_stage(reset_work), MH.outcome_transition(TH.reset_work_move(reset_work)))), (W.attach(engine, candidate), Fail{cause}), refused) : {R.reattach(R.detach(R.tick_result(X.reset_stage_traveled(phase_work, TH.reset_supplied(tables, support, minor, reset_work, _))))) == R.with_error(X.State{MH.State{W.attach(engine, X.frame_view(X.work_frame(phase_work))), X.frame_support(X.work_frame(phase_work)), X.frame_minor(X.work_frame(phase_work)), H.State{X.frame_history(X.work_frame(phase_work))}, []}, tables, X.frame_metadata(X.work_frame(phase_work)), []}, Some{R.error_text(X.reset_stage_error(TH.ResetSupplierError{cause}))}) : X.State}
      R.bundle_detour_preserves_every_owner_and_field(R.with_error(X.State{MH.State{W.attach(engine, X.frame_view(X.work_frame(phase_work))), X.frame_support(X.work_frame(phase_work)), X.frame_minor(X.work_frame(phase_work)), H.State{X.frame_history(X.work_frame(phase_work))}, []}, tables, X.frame_metadata(X.work_frame(phase_work)), []}, Some{R.error_text(X.reset_stage_error(TH.ResetSupplierError{cause}))}))

def Laws.scheduled_preparation_equals_direct_after_one_common_tick(world, registry, tables, view, support, minor, history, metadata, request, entity, look, common):
  match view:
    case W.View{body, yaw, pitch, palette, region, cache}:
      %Equal.sym(ECT.State & Result<&2, &2, ECT.Error, ECT.Snapshot>, ECT.common_tick(ECT.State{X.entity(metadata), []}, ECT.Request{X.body_position(X.view_body(view)), PR.look(X.controls(metadata)), X.pre_request_common(request), []}), (ECT.State{entity, []}, Done{ECT.Snapshot{entity, look}}), common) : {X.pre_common_finished(tables, support, minor, H.State{history}, metadata, request, G.Engine{C.step(world), registry}, view, _) == X.pre_local_ready(X.State{MH.State{W.attach(G.Engine{C.step(world), registry}, view), support, minor, H.State{history}, []}, tables, X.with_entity(X.with_controls(metadata, X.with_look(X.controls(metadata), look)), entity), []}, request) : X.PrepareResult}
      {==}

