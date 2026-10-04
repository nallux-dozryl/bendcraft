import Base
import ./travel.bend as T
import ./f64.bend as F
import ./player_block_inside_sweep_world.bend as W
import ./local_phase_runtime.bend as X
import ./local_player_runtime.bend as RT
import ./runtime_block_inside.bend as R
import ./player_block_inside_stuck.bend as P
import ./local_travel_history.bend as TH
import ./local_move_history.bend as MH
import ./local_move_world.bend as LM
import ./player_tick.bend as Tick
import ./player_runtime.bend as PR
import ./player_pose.bend as Pose
import ./player_controls.bend as PC
import ./local_input.bend as LI
import ./entity_common_tick.bend as ECT
import ./player_pose_world.bend as PPW
import ./client_world.bend as CW
import ./game.bend as G
import ./locomotion.bend as L
import ./movement.bend as M
import ./support.bend as SP
import ./player_fall_history.bend as H
import ./player_input.bend as PI
import ./mouse_input.bend as MI
import ./local_player_record.bend as Record

law receiver_update_preserves_every_other_metadata_field:
  for +local: LI.State
  for +player: PR.Metadata
  for +sprinting: Bool
  for +pose: Pose.State
  for +controls: PC.Controller
  for +entity: ECT.Metadata
  for previous: P.Receiver
  for +receiver: P.Receiver
  for +error: Maybe<&2, String>
  for +tail: List<&2, X.Metadata>
  {X.with_receiver(X.Metadata{local, player, sprinting, pose, controls, entity, previous, error, tail}, receiver) ==
    X.Metadata{local, player, sprinting, pose, controls, entity, receiver, error, tail} : X.Metadata}

law work_receiver_update_retains_original_complete_rollback_frame:
  for +frame: X.Frame
  for +metadata: X.Metadata
  for +early: List<&2, PPW.QueryRecord>
  for +updates: List<&2, Bool>
  for +prepared: Tick.PreTravel
  for +context: Tick.Context
  for +tail: List<&2, X.Work>
  for +receiver: P.Receiver
  {X.with_work_receiver(X.Work{frame, metadata, early, updates, prepared, context, tail}, receiver) ==
    X.Work{frame, X.with_receiver(metadata, receiver), early, updates, prepared, context, tail} : X.Work}

law callbacks_use_actual_old_position_and_precommit_selected_flying:
  for local: LI.State
  for player: PR.Metadata
  for sprinting: Bool
  for pose: Pose.State
  for controls: PC.Controller
  for interpolation: M.Vec3
  for +old: M.Vec3
  for invulnerable: U32
  for count: U32
  for receiver: P.Receiver
  for error: Maybe<&2, String>
  for tail: List<&2, X.Metadata>
  for travel: T.Context
  for strength: F.F64
  for factor: F32
  for affected: Bool
  for +mode: Tick.Mode
  for +request: X.Request
  {X.block_inside_hooks(X.Metadata{local, player, sprinting, pose, controls, ECT.Metadata{interpolation, old, invulnerable, count}, receiver, error, tail},
    Tick.Context{travel, strength, factor, affected, mode}, request) ==
    R.Hooks{P.Player{Tick.mode_flying(mode), False{}}, P.ClientLevel{}, old, "minecraft:overworld", False{}, False{}, True{},
      X.request_movement_fuel(request), X.request_movement_fuel(request), []} : R.Hooks}

law callback_refusal_restores_complete_pretravel_anchor:
  for engine: G.Engine
  for tables: L.Tables
  for +frame: X.Frame
  for metadata: X.Metadata
  for early: List<&2, PPW.QueryRecord>
  for updates: List<&2, Bool>
  for prepared: Tick.PreTravel
  for context: Tick.Context
  for work_tail: List<&2, X.Work>
  for candidate: CW.View
  for support: SP.State
  for minor: LM.MinorState
  for history: H.State
  for receiver: P.Receiver
  for transition: Tick.Transition
  for +error: R.Error
  {X.block_inside_finished(tables, X.Work{frame, metadata, early, updates, prepared, context, work_tail}, transition,
    (MH.State{CW.attach(engine, candidate), support, minor, history, []}, receiver, Fail{error})) ==
    (X.State{MH.State{CW.attach(engine, X.frame_view(frame)), X.frame_support(frame), X.frame_minor(frame), H.State{X.frame_history(frame)}, []},
      tables, X.frame_metadata(frame), []}, Fail{X.BlockInsideError{error}}) : X.State & Result<&2, &2, X.Error, X.Observation>}

law outer_finish_refusal_restores_anchor_before_any_callback:
  for engine: G.Engine
  for tables: L.Tables
  for +frame: X.Frame
  for metadata: X.Metadata
  for early: List<&2, PPW.QueryRecord>
  for updates: List<&2, Bool>
  for prepared: Tick.PreTravel
  for context: Tick.Context
  for work_tail: List<&2, X.Work>
  for candidate: CW.View
  for support: SP.State
  for minor: LM.MinorState
  for history: H.State
  for outcome: TH.Outcome
  for +error: Tick.Error
  {X.travel_outer_finished(X.Work{frame, metadata, early, updates, prepared, context, work_tail},
    MH.State{CW.attach(engine, candidate), support, minor, history, []}, tables, outcome, Fail{error}) ==
    (X.State{MH.State{CW.attach(engine, X.frame_view(frame)), X.frame_support(frame), X.frame_minor(frame), H.State{X.frame_history(frame)}, []},
      tables, X.frame_metadata(frame), []}, Fail{X.FinishError{error}}) : X.State & Result<&2, &2, X.Error, X.Observation>}

law actual_outer_finish_refusal_rolls_back_public_travel:
  for +work: X.Work
  for motion: MH.State
  for tables: L.Tables
  for +outcome: TH.Outcome
  for +error: Tick.Error
  for service: {Tick.finish_checked(X.work_prepared(work), X.work_context(work), TH.outcome_transition(outcome)) == Fail{error} : Result<&2, &2, Tick.Error, Tick.Transition>}
  {X.traveled(work, (motion, tables, Done{outcome})) ==
    X.rollback(motion, tables, X.work_frame(work), X.FinishError{error}) : X.State & Result<&2, &2, X.Error, X.Observation>}

law actual_post_finish_callback_refusal_rolls_back_public_join:
  for +work: X.Work
  for motion: MH.State
  for tables: L.Tables
  for +outcome: TH.Outcome
  for +transition: Tick.Transition
  for returned: MH.State
  for ignored: P.Receiver
  for +error: R.Error
  for service: {R.after_successful_travel(X.install_finished_body(motion, X.finished_player(transition), X.work_context(work)),
    X.receiver(X.work_metadata(work)), X.block_inside_hooks(X.work_metadata(work), X.work_context(work), X.frame_request(X.work_frame(work))), outcome) ==
    (returned, ignored, Fail{error}) : MH.State & P.Receiver & Result<&2, &2, R.Error, W.Observation>}
  {X.travel_outer_finished(work, motion, tables, outcome, Done{transition}) ==
    X.rollback(returned, tables, X.work_frame(work), X.BlockInsideError{error}) : X.State & Result<&2, &2, X.Error, X.Observation>}

law player_metadata_update_preserves_receiver:
  for +metadata: X.Metadata
  for player: PR.Metadata
  {X.receiver(X.with_player(metadata, player)) == X.receiver(metadata) : P.Receiver}

law control_metadata_update_preserves_receiver:
  for +metadata: X.Metadata
  for controls: PC.Controller
  {X.receiver(X.with_controls(metadata, controls)) == X.receiver(metadata) : P.Receiver}

law pose_metadata_update_preserves_receiver:
  for +metadata: X.Metadata
  for pose: Pose.State
  {X.receiver(X.with_pose(metadata, pose)) == X.receiver(metadata) : P.Receiver}

law successful_startup_restore_resets_transient_receiver_and_preserves_affine_owners:
  for tables: L.Tables
  for +palette: Maybe<&2, CW.Palette>
  for +region: CW.Bounds
  for +cache: Maybe<&2, CW.SnapshotCache>
  for buttons: PI.Buttons
  for mouse: MI.State
  for +options: MI.Options
  for receiver: P.Receiver
  for error: Maybe<&2, String>
  for state_tail: List<&1, X.State>
  for motion_tail: List<&1, MH.State>
  for +metadata_tail: List<&2, X.Metadata>
  {RT.restored_transient(RT.Transient{tables, palette, region, cache, buttons, mouse, options, receiver, error, state_tail, motion_tail, metadata_tail}) ==
    RT.Transient{tables, palette, region, cache, PI.empty(), MI.initial(), options, P.empty(), None{}, state_tail, motion_tail, metadata_tail} : RT.Transient}

law failed_startup_validation_retains_entire_runtime_owner_and_receiver:
  for state: X.State
  for +error: Record.Error
  {RT.restore_validated(state, Fail{error}) == (state, Fail{Record.error_text(error)}) : X.State & Result<&2, &2, String, Unit>}
