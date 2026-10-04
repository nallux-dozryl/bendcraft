import Base
import ./player_block_inside_sweep_laws.bend as Laws
import ./player_block_inside_sweep_world.bend as W
import ./player_block_inside_sweep.bend as S
import ./player_block_inside_stuck.bend as P
import ./core.bend as C
import ./registry.bend as B
import ./player_block_inside_sweep_motion.bend as SM
import ./player_block_inside_stuck_motion.bend as PM
import ./client_world.bend as CW
import ./game.bend as G
import ./local_move_history.bend as MH
import ./player_block_inside_sweep_travel.bend as ST
import ./travel.bend as T
import ./movement.bend as M
import ./f64.bend as F
import ./player_block_inside_sweep_clip.bend as Clip

def Laws.next_segment_resets_only_local_seen_and_step(fuel, seen, visits, last, stopped, failure, tail):
  {==}

def Laws.duplicate_crossing_does_not_advance_collector_or_visit_trace(build, point, step, segment, rejected):
  match build:
    case S.Build{fuel, seen, visits, last, stopped, failure, tail}: {==}

def Laws.vanilla_step_limit_stops_without_work_budget_error(fuel, seen, visits, last, stopped, failure, tail, point, step, segment, present):
  {==}

def Laws.initial_range_keeps_duplicate_visits_but_not_duplicate_keys(fuel, seen, visits, last, stopped, failure, tail, point, step, segment):
  {==}

def Laws.actual_air_read_preserves_receiver_and_global_seen(state, dimension, visit, facts, level, effects, keys, collector, reads, callbacks, tail, identity, is_air):
  %Equal.sym(Bool, W.air(identity), True{}, is_air) : {(state,
    W.admitted(dimension, visit, identity, facts, level,
      W.Scratch{effects, keys, collector, W.Read{visit, identity, collector, S.seen(keys, S.key(S.visit_point(visit)))} <> reads, callbacks, tail},
      _, W.full_inside(identity), S.seen(keys, S.key(S.visit_point(visit))))) ==
    (state, Done{W.Scratch{effects, keys, collector, W.Read{visit, identity, collector, S.seen(keys, S.key(S.visit_point(visit)))} <> reads, callbacks, tail}}) : P.State & Result<&2, &2, W.Error, W.Scratch>}
  {==}

def Laws.actual_duplicate_read_keeps_callbacks_and_collector_unchanged(state, dimension, visit, facts, level, effects, keys, collector, reads, callbacks, tail, identity, nonair, supported, duplicate):
  %Equal.sym(Bool, S.seen(keys, S.key(S.visit_point(visit))), True{}, duplicate) : {(state,
    W.admitted(dimension, visit, identity, facts, level,
      W.Scratch{effects, keys, collector, W.Read{visit, identity, collector, _} <> reads, callbacks, tail},
      W.air(identity), W.full_inside(identity), _)) ==
    (state, Done{W.Scratch{effects, keys, collector, W.Read{visit, identity, collector, True{}} <> reads, callbacks, tail}}) : P.State & Result<&2, &2, W.Error, W.Scratch>}
  %Equal.sym(Bool, W.air(identity), False{}, nonair) : {(state,
    W.admitted(dimension, visit, identity, facts, level,
      W.Scratch{effects, keys, collector, W.Read{visit, identity, collector, True{}} <> reads, callbacks, tail},
      _, W.full_inside(identity), True{})) ==
    (state, Done{W.Scratch{effects, keys, collector, W.Read{visit, identity, collector, True{}} <> reads, callbacks, tail}}) : P.State & Result<&2, &2, W.Error, W.Scratch>}
  %Equal.sym(Bool, W.full_inside(identity), True{}, supported) : {(state,
    W.admitted(dimension, visit, identity, facts, level,
      W.Scratch{effects, keys, collector, W.Read{visit, identity, collector, True{}} <> reads, callbacks, tail},
      False{}, _, True{})) ==
    (state, Done{W.Scratch{effects, keys, collector, W.Read{visit, identity, collector, True{}} <> reads, callbacks, tail}}) : P.State & Result<&2, &2, W.Error, W.Scratch>}
  {==}

def Laws.callback_refusal_wins_over_later_traversal_failure(state, error, terminal):
  {==}

def Laws.deferred_traversal_failure_discards_all_speculative_callbacks(state, scratch, error):
  {==}

def Laws.read_budget_refusal_retains_complete_arbitrary_owner(state, dimension, facts, level, visit, rest, terminal, scratch):
  {==}

def Laws.failed_read_retains_world_registry_receiver_history_and_affine_tail(world, registry, receiver, history, tail, dimension, visit, facts, level, scratch, error):
  {==}

def Laws.actual_core_refusal_retains_complete_sweep_owner(world, registry, receiver, history, tail, dimension, visit, facts, level, scratch, error, service):
  %Equal.sym(C.World & Result<&2, &2, C.Error, U32>, C.read_block(world, W.position(dimension, visit)), (world, Fail{error}), service) :
    {W.read_owner(registry, receiver, history, tail, dimension, visit, facts, level, scratch, _) ==
      (P.State{world, registry, receiver, history, tail}, Fail{W.ProducerError{P.WorldError{error}}}) : P.State & Result<&2, &2, W.Error, W.Scratch>}
  {==}

def Laws.registry_decode_refusal_retains_every_owned_field(state, dimension, visit, facts, level, scratch, error):
  match scratch:
    case W.Scratch{effects, keys, collector, reads, callbacks, tail}: {==}

def Laws.late_callback_service_refusal_discards_prior_effects(dimension, visit, identity, facts, level, receiver, history, impulse, prior_reads, keys, collector, reads, callbacks, tail, error, service):
  %Equal.sym(Result<&2, &2, P.Error, P.Candidate>, P.callback_checked(receiver, history, facts, level, identity), Fail{error}, service) :
    {W.candidate_done(dimension, visit, identity,
      W.Scratch{P.Scratch{P.Candidate{receiver, history, impulse}, prior_reads}, keys, collector, reads, callbacks, tail}, _) ==
      Fail{W.ProducerError{error}} : Result<&2, &2, W.Error, W.Scratch>}
  {==}

def Laws.successful_sweep_commits_only_receiver_and_history(world, registry, old_receiver, old_history, tail, receiver, history, impulse, producer_reads, keys, collector, reads, callbacks, scratch_tail):
  {==}

def Laws.noncanonical_request_cannot_read_or_commit(state, dimension, facts, level, removed, physics, alive, width, height, movements, traversal_fuel, read_fuel, head, tail):
  {==}

def Laws.authoritative_berry_uses_actual_known_movement_observation(known, old, current):
  {==}

def Laws.other_authority_berry_uses_actual_old_minus_current(known, old, current):
  {==}

def Laws.rejected_body_binding_retains_actual_motion_environment(world, registry, view, support, minor, history, tail, receiver, dimension, request, error):
  {==}

def Laws.completed_sweep_restores_every_motion_environment_field(world, registry, view, support, minor, history, tail, receiver, observation):
  {==}

def Laws.existing_refusal_prevents_every_remaining_world_read(fuel, state, dimension, facts, level, visits, terminal, error):
  match fuel visits:
    case 0n Nil{}: {==}
    case 0n visit <> rest: {==}
    case 1n+p Nil{}: {==}
    case 1n+p visit <> rest: {==}

def Laws.earliest_actual_read_refusal_prevents_later_reads(fuel, state, dimension, facts, level, visit, rest, terminal, scratch, error, service):
  %Equal.sym(P.State & Result<&2, &2, W.Error, W.Scratch>, W.read(state, dimension, visit, facts, level, scratch), (state, Fail{error}), service) :
    {P.paired(P.State, Result<&2, &2, W.Error, W.Scratch>, P.State & Result<&2, &2, W.Error, W.Observation>,
      _, next => status => W.loop(fuel, next, dimension, facts, level, rest, terminal, status)) ==
      (state, Fail{error}) : P.State & Result<&2, &2, W.Error, W.Observation>}
  Laws.existing_refusal_prevents_every_remaining_world_read(fuel, state, dimension, facts, level, rest, terminal, error)

def Laws.public_motion_join_installs_only_actual_successful_service_result(world, registry, view, support, minor, history, tail, receiver, dimension, request, next_receiver, next_history, observation, binding, service):
  match view:
    case CW.View{body, yaw, pitch, palette, region, cache}:
      %Equal.sym(Maybe<&2, SM.Error>, SM.view_binding(CW.View{body, yaw, pitch, palette, region, cache}, request), None{}, binding) :
        {SM.gate(P.State{world, registry, receiver, history, []}, PM.Frame{CW.View{body, yaw, pitch, palette, region, cache}, support, minor, tail}, dimension, request, _) ==
          (MH.State{CW.attach(G.Engine{world, registry}, CW.View{body, yaw, pitch, palette, region, cache}), support, minor, next_history, tail}, next_receiver, Done{observation}) : MH.State & P.Receiver & Result<&2, &2, SM.Error, W.Observation>}
      %Equal.sym(P.State & Result<&2, &2, W.Error, W.Observation>, W.query(P.State{world, registry, receiver, history, []}, dimension, request),
        (P.State{world, registry, next_receiver, next_history, []}, Done{observation}), service) :
        {SM.completed(PM.Frame{CW.View{body, yaw, pitch, palette, region, cache}, support, minor, tail}, _) ==
          (MH.State{CW.attach(G.Engine{world, registry}, CW.View{body, yaw, pitch, palette, region, cache}), support, minor, next_history, tail}, next_receiver, Done{observation}) : MH.State & P.Receiver & Result<&2, &2, SM.Error, W.Observation>}
      {==}

def Laws.public_motion_join_preserves_full_owner_on_service_refusal(world, registry, view, support, minor, history, tail, receiver, dimension, request, error, binding, service):
  match view:
    case CW.View{body, yaw, pitch, palette, region, cache}:
      %Equal.sym(Maybe<&2, SM.Error>, SM.view_binding(CW.View{body, yaw, pitch, palette, region, cache}, request), None{}, binding) :
        {SM.gate(P.State{world, registry, receiver, history, []}, PM.Frame{CW.View{body, yaw, pitch, palette, region, cache}, support, minor, tail}, dimension, request, _) ==
          (MH.State{CW.attach(G.Engine{world, registry}, CW.View{body, yaw, pitch, palette, region, cache}), support, minor, history, tail}, receiver, Fail{SM.SweepError{error}}) : MH.State & P.Receiver & Result<&2, &2, SM.Error, W.Observation>}
      %Equal.sym(P.State & Result<&2, &2, W.Error, W.Observation>, W.query(P.State{world, registry, receiver, history, []}, dimension, request),
        (P.State{world, registry, receiver, history, []}, Fail{error}), service) :
        {SM.completed(PM.Frame{CW.View{body, yaw, pitch, palette, region, cache}, support, minor, tail}, _) ==
          (MH.State{CW.attach(G.Engine{world, registry}, CW.View{body, yaw, pitch, palette, region, cache}), support, minor, history, tail}, receiver, Fail{SM.SweepError{error}}) : MH.State & P.Receiver & Result<&2, &2, SM.Error, W.Observation>}
      {==}

def Laws.empty_original_queue_uses_old_to_current_fallback(old, position):
  {==}

def Laws.actual_subthreshold_endpoint_retains_complete_ordered_queue(pending, endpoint, position, within):
  %Equal.sym(Bool, F.is_gt(M.Vec3.length_squared(Clip.subtract(endpoint, position)), S.tiny_square()), False{}, within) :
    {ST.bridged(pending, endpoint, position, _) == pending : List<&2, S.Movement>}
  {==}

def Laws.dispatched_bridge_appends_without_changing_prior_records(pending, endpoint, position):
  {==}

def Laws.refused_position_change_never_creates_a_travel_record(prepared, prepared_tail, body, displacement, stepped, motion_tail, backoff, before, minor, move_tail, history, history_tail, final_motion, travel_tail, ray, reset_tail):
  match prepared:
    case T.Prepared{before_body, requested, friction, acceleration, maximum, gravity, drag, discard}: {==}

def Laws.actual_travel_record_retains_post_backoff_original_and_raw_endpoint(prepared, prepared_tail, body, displacement, stepped, motion_tail, backoff, before, minor, move_tail, history, history_tail, final_motion, travel_tail, ray, reset_tail):
  match prepared:
    case T.Prepared{before_body, requested, friction, acceleration, maximum, gravity, drag, discard}: {==}
