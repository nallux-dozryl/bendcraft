import Base
import ./client_world.bend as CW
import ./runtime_block_inside_join_laws.bend as Laws
import ./local_phase_runtime.bend as X
import ./local_player_runtime.bend as RT
import ./runtime_block_inside.bend as R
import ./player_block_inside_stuck.bend as P
import ./player_block_inside_sweep_world.bend as W
import ./local_travel_history.bend as TH
import ./local_move_history.bend as MH
import ./player_tick.bend as Tick

def Laws.receiver_update_preserves_every_other_metadata_field(local, player, sprinting, pose, controls, entity, previous, receiver, error, tail):
  {==}

def Laws.work_receiver_update_retains_original_complete_rollback_frame(frame, metadata, early, updates, prepared, context, tail, receiver):
  {==}

def Laws.callbacks_use_actual_old_position_and_precommit_selected_flying(local, player, sprinting, pose, controls, interpolation, old, invulnerable, count, receiver, error, tail, travel, strength, factor, affected, mode, request):
  {==}

def Laws.callback_refusal_restores_complete_pretravel_anchor(engine, tables, frame, metadata, early, updates, prepared, context, work_tail, candidate, support, minor, history, receiver, transition, error):
  match candidate:
    case CW.View{body, yaw, pitch, palette, region, cache}: {==}

def Laws.outer_finish_refusal_restores_anchor_before_any_callback(engine, tables, frame, metadata, early, updates, prepared, context, work_tail, candidate, support, minor, history, outcome, error):
  match candidate:
    case CW.View{body, yaw, pitch, palette, region, cache}: {==}

def Laws.actual_outer_finish_refusal_rolls_back_public_travel(work, motion, tables, outcome, error, service):
  %Equal.sym(Result<&2, &2, Tick.Error, Tick.Transition>, Tick.finish_checked(X.work_prepared(work), X.work_context(work), TH.outcome_transition(outcome)), Fail{error}, service) :
    {X.travel_outer_finished(work, motion, tables, outcome, _) == X.rollback(motion, tables, X.work_frame(work), X.FinishError{error}) : X.State & Result<&2, &2, X.Error, X.Observation>}
  {==}

def Laws.actual_post_finish_callback_refusal_rolls_back_public_join(work, motion, tables, outcome, transition, returned, ignored, error, service):
  %Equal.sym(MH.State & P.Receiver & Result<&2, &2, R.Error, W.Observation>,
    R.after_successful_travel(X.install_finished_body(motion, X.finished_player(transition), X.work_context(work)),
      X.receiver(X.work_metadata(work)), X.block_inside_hooks(X.work_metadata(work), X.work_context(work), X.frame_request(X.work_frame(work))), outcome),
    (returned, ignored, Fail{error}), service) :
    {X.block_inside_finished(tables, work, transition, _) == X.rollback(returned, tables, X.work_frame(work), X.BlockInsideError{error}) : X.State & Result<&2, &2, X.Error, X.Observation>}
  {==}

def Laws.player_metadata_update_preserves_receiver(metadata, player):
  match metadata:
    case X.Metadata{local, old, sprinting, pose, controls, entity, receiver, error, tail}: {==}

def Laws.control_metadata_update_preserves_receiver(metadata, controls):
  match metadata:
    case X.Metadata{local, player, sprinting, pose, previous, entity, receiver, error, tail}: {==}

def Laws.pose_metadata_update_preserves_receiver(metadata, pose):
  match metadata:
    case X.Metadata{local, player, sprinting, previous, controls, entity, receiver, error, tail}: {==}

def Laws.successful_startup_restore_resets_transient_receiver_and_preserves_affine_owners(tables, palette, region, cache, buttons, mouse, options, receiver, error, state_tail, motion_tail, metadata_tail):
  {==}

def Laws.failed_startup_validation_retains_entire_runtime_owner_and_receiver(state, error):
  {==}
