import Base
import ./runtime_block_inside_laws.bend as Laws
import ./runtime_block_inside.bend as R
import ./player_block_inside_stuck.bend as P
import ./player_block_inside_stuck_motion.bend as PM
import ./player_block_inside_sweep_motion.bend as SM
import ./player_block_inside_sweep_world.bend as W
import ./player_block_inside_sweep_travel.bend as ST
import ./local_travel_history.bend as TH
import ./local_move_history.bend as MH
import ./movement.bend as M
import ./f64.bend as F
import ./client_world.bend as CW
import ./game.bend as G

def Laws.no_physics_preserves_complete_receiver_without_consumption(receiver):
  {==}

def Laws.active_success_clears_multiplier_and_keeps_raw_impulse(multiplier, impulse, active):
  %Equal.sym(Bool, F.is_gt(M.Vec3.length_squared(multiplier), M.stuck_threshold()), True{}, active) :
    {P.consume_gate(P.Receiver{multiplier, impulse}, _) == P.Receiver{M.Vec3.zero(), impulse} : P.Receiver}
  {==}

def Laws.inactive_success_keeps_raw_multiplier_and_impulse(multiplier, impulse, inactive):
  %Equal.sym(Bool, F.is_gt(M.Vec3.length_squared(multiplier), M.stuck_threshold()), False{}, inactive) :
    {P.consume_gate(P.Receiver{multiplier, impulse}, _) == P.Receiver{multiplier, impulse} : P.Receiver}
  {==}

def Laws.callback_failure_restores_preconsumption_receiver_and_whole_motion_owner(motion, previous, consumed, error):
  {==}

def Laws.callback_success_installs_actual_receiver_observation_and_whole_motion_owner(motion, previous, next, observation):
  {==}

def Laws.noncanonical_hooks_refuse_before_consumption_or_world_callbacks(motion, receiver, facts, level, old, dimension, removed, physics, alive, traversal, reads, head, tail, outcome):
  {==}

def Laws.request_uses_actual_held_dimensions_and_position_with_ordered_travel_record(position, box, velocity, width, height, ground, horizontal, vertical, below, yaw, pitch, palette, region, cache, facts, level, old, dimension, removed, physics, alive, traversal, reads, hooks_tail, record):
  {==}

def Laws.public_callback_refusal_restores_original_receiver_and_complete_held_owner(world, registry, view, support, minor, history, tail, receiver, facts, level, old, dimension, removed, physics, alive, traversal, reads, outcome, error, service):
  match view:
    case CW.View{body, yaw, pitch, palette, region, cache}:
      %Equal.sym(MH.State & P.Receiver & Result<&2, &2, SM.Error, W.Observation>,
        SM.framed(P.State{world, registry, R.consume(receiver, physics), history, []},
          PM.Frame{CW.View{body, yaw, pitch, palette, region, cache}, support, minor, tail}, dimension,
          R.request(CW.View{body, yaw, pitch, palette, region, cache}, R.Hooks{facts, level, old, dimension, removed, physics, alive, traversal, reads, []}, ST.travel_record(outcome))),
        (MH.State{CW.attach(G.Engine{world, registry}, CW.View{body, yaw, pitch, palette, region, cache}), support, minor, history, tail}, R.consume(receiver, physics), Fail{error}), service) :
        {R.completed(receiver, _) ==
          (MH.State{CW.attach(G.Engine{world, registry}, CW.View{body, yaw, pitch, palette, region, cache}), support, minor, history, tail}, receiver, Fail{R.CallbackError{error}}) :
            MH.State & P.Receiver & Result<&2, &2, R.Error, W.Observation>}
      {==}

def Laws.public_callback_success_keeps_entire_actual_service_owner_and_receiver(world, registry, view, support, minor, history, tail, receiver, facts, level, old, dimension, removed, physics, alive, traversal, reads, outcome, next_motion, next_receiver, observation, service):
  match view:
    case CW.View{body, yaw, pitch, palette, region, cache}:
      %Equal.sym(MH.State & P.Receiver & Result<&2, &2, SM.Error, W.Observation>,
        SM.framed(P.State{world, registry, R.consume(receiver, physics), history, []},
          PM.Frame{CW.View{body, yaw, pitch, palette, region, cache}, support, minor, tail}, dimension,
          R.request(CW.View{body, yaw, pitch, palette, region, cache}, R.Hooks{facts, level, old, dimension, removed, physics, alive, traversal, reads, []}, ST.travel_record(outcome))),
        (next_motion, next_receiver, Done{observation}), service) :
        {R.completed(receiver, _) == (next_motion, next_receiver, Done{observation}) :
          MH.State & P.Receiver & Result<&2, &2, R.Error, W.Observation>}
      {==}

def Laws.receiver_comparison_rejects_missing_impact(impact):
  {==}
