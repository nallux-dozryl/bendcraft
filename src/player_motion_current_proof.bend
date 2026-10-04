import Base
import ./movement.bend as M
import ./f64.bend as F
import ./travel.bend as T
import ./local_travel_history.bend as TH
import ./local_move_history.bend as MH
import ./player_fall_history.bend as H
import ./locomotion.bend as L
import ./client_world.bend as W
import ./player_motion_current_laws.bend as Laws

def Laws.inactive_multiplier_preserves_every_raw_field(body, request, multiplier, inactive):
  match body:
    case M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below}:
      %Equal.sym(Bool, F.is_gt(M.Vec3.length_squared(multiplier), M.stuck_threshold()), False{}, inactive) : {M.stuck_gate(M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below}, request, multiplier, _) == M.StuckPreparation{M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below}, request, multiplier, False{}} : M.StuckPreparation}
      {==}

def Laws.active_multiplier_scales_request_and_clears_velocity(position, box, velocity, width, height, ground, horizontal, vertical, below, x, y, z, sx, sy, sz):
  {==}

def Laws.refused_multiplier_has_no_candidate(body, request, multiplier, cause):
  {==}

def Laws.corrected_preparation_preserves_travel_factors(body, request, friction, acceleration, maximum, gravity, drag, discard, next, corrected, multiplier, applied):
  {==}

def Laws.resolved_hook_preserves_all_other_receiver_observations(keys, input, flying, mode, simulate, authority, stuck, removed, auto, speed, restitution, environment, fuel, tail):
  {==}

def Laws.acceleration_failure_retains_complete_motion_owner(engine, tables, frame, cause):
  {==}

def Laws.refused_scaled_request_retains_complete_ability_motion_owner(mode, engine, tables, frame, policy, prepared, cause, refused):
  %Equal.sym(Result<&2, &2, T.Error, T.Prepared>, T.stuck_checked(prepared, TH.hooks_stuck(TH.request_hooks(TH.frame_request(frame)))), Fail{cause}, refused) : {TH.ability_reset_prepared(mode, engine, frame, policy, (tables, _)) == (MH.State{W.attach(engine, TH.frame_view(frame)), TH.frame_support(frame), TH.frame_minor(frame), H.State{TH.frame_history(frame)}, []}, tables, Fail{TH.ResetTravelError{TH.PreparationError{cause}}}) : MH.State & L.Tables & Result<&2, &2, TH.ResetError, TH.ResetOutcome>}
  {==}

def Laws.checked_stuck_failure_cannot_reach_collision(prepared, cause):
  {==}
