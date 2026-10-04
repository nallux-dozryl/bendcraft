import Base
import ./player_block_inside_sweep.bend as S
import ./player_block_inside_sweep_world.bend as W
import ./player_block_inside_sweep_motion.bend as SM
import ./player_block_inside_sweep_berry.bend as Berry
import ./player_block_inside_stuck.bend as P
import ./player_block_inside_stuck_motion.bend as PM
import ./core.bend as C
import ./registry.bend as B
import ./movement.bend as M
import ./player_fall_history.bend as H
import ./local_move_history.bend as MH
import ./local_move_world.bend as LM
import ./client_world.bend as CW
import ./game.bend as G
import ./support.bend as SP
import ./player_block_inside_sweep_travel.bend as ST
import ./local_travel_history.bend as TH
import ./travel.bend as T
import ./local_collision_world.bend as LCW
import ./f64.bend as F
import ./player_block_inside_sweep_clip.bend as Clip
import ./local_collision.bend as LC
import ./fall_reset_world.bend as FR

law next_segment_resets_only_local_seen_and_step:
  for +fuel: Nat
  for seen: List<&2, S.PackedKey>
  for +visits: List<&2, S.Visit>
  for last: U32
  for stopped: Bool
  for +failure: Maybe<&2, S.Error>
  for +tail: List<&2, S.Build>
  {S.segment_reset(S.Build{fuel, seen, visits, last, stopped, failure, tail}) ==
    S.Build{fuel, [], visits, 0, False{}, failure, tail} : S.Build}

law duplicate_crossing_does_not_advance_collector_or_visit_trace:
  for +build: S.Build
  for point: S.Point
  for step: U32
  for segment: S.Segment
  for rejected: Bool
  {S.emit_gate(build, point, step, segment, True{}, True{}, rejected) == build : S.Build}

law vanilla_step_limit_stops_without_work_budget_error:
  for +fuel: Nat
  for +seen: List<&2, S.PackedKey>
  for +visits: List<&2, S.Visit>
  for +last: U32
  for stopped: Bool
  for +failure: Maybe<&2, S.Error>
  for +tail: List<&2, S.Build>
  for point: S.Point
  for step: U32
  for segment: S.Segment
  for present: Bool
  {S.emit_gate(S.Build{fuel, seen, visits, last, stopped, failure, tail}, point, step, segment, present, False{}, True{}) ==
    S.Build{fuel, seen, visits, last, True{}, failure, tail} : S.Build}

law initial_range_keeps_duplicate_visits_but_not_duplicate_keys:
  for +fuel: Nat
  for +seen: List<&2, S.PackedKey>
  for +visits: List<&2, S.Visit>
  for last: U32
  for stopped: Bool
  for +failure: Maybe<&2, S.Error>
  for +tail: List<&2, S.Build>
  for +point: S.Point
  for +step: U32
  for +segment: S.Segment
  {S.emit_gate(S.Build{fuel, seen, visits, last, stopped, failure, tail}, point, step, segment, True{}, False{}, False{}) ==
    S.Build{fuel, seen, S.Visit{point, step, segment} <> visits, step, False{}, failure, tail} : S.Build}

law actual_air_read_preserves_receiver_and_global_seen:
  for state: P.State
  for dimension: String
  for +visit: S.Visit
  for facts: P.Facts
  for level: P.Level
  for +effects: P.Scratch
  for +keys: List<&2, S.PackedKey>
  for +collector: U32
  for +reads: List<&2, W.Read>
  for +callbacks: List<&2, W.Callback>
  for +tail: List<&2, W.Scratch>
  for +identity: B.Resolved
  for is_air: {W.air(identity) == True{} : Bool}
  {W.decoded(state, dimension, visit, facts, level, W.Scratch{effects, keys, collector, reads, callbacks, tail}, Done{identity}) ==
    (state, Done{W.Scratch{effects, keys, collector,
      W.Read{visit, identity, collector, S.seen(keys, S.key(S.visit_point(visit)))} <> reads, callbacks, tail}}) : P.State & Result<&2, &2, W.Error, W.Scratch>}

law actual_duplicate_read_keeps_callbacks_and_collector_unchanged:
  for state: P.State
  for dimension: String
  for +visit: S.Visit
  for facts: P.Facts
  for level: P.Level
  for +effects: P.Scratch
  for +keys: List<&2, S.PackedKey>
  for +collector: U32
  for +reads: List<&2, W.Read>
  for +callbacks: List<&2, W.Callback>
  for +tail: List<&2, W.Scratch>
  for +identity: B.Resolved
  for nonair: {W.air(identity) == False{} : Bool}
  for supported: {W.full_inside(identity) == True{} : Bool}
  for duplicate: {S.seen(keys, S.key(S.visit_point(visit))) == True{} : Bool}
  {W.decoded(state, dimension, visit, facts, level, W.Scratch{effects, keys, collector, reads, callbacks, tail}, Done{identity}) ==
    (state, Done{W.Scratch{effects, keys, collector, W.Read{visit, identity, collector, True{}} <> reads, callbacks, tail}}) : P.State & Result<&2, &2, W.Error, W.Scratch>}

law callback_refusal_wins_over_later_traversal_failure:
  for state: P.State
  for +error: W.Error
  for terminal: Maybe<&2, S.Error>
  {W.finish(state, Fail{error}, terminal) == (state, Fail{error}) : P.State & Result<&2, &2, W.Error, W.Observation>}

law deferred_traversal_failure_discards_all_speculative_callbacks:
  for state: P.State
  for scratch: W.Scratch
  for +error: S.Error
  {W.finish(state, Done{scratch}, Some{error}) == (state, Fail{W.TraversalError{error}}) : P.State & Result<&2, &2, W.Error, W.Observation>}

law read_budget_refusal_retains_complete_arbitrary_owner:
  for state: P.State
  for dimension: String
  for facts: P.Facts
  for level: P.Level
  for visit: S.Visit
  for rest: List<&2, S.Visit>
  for terminal: Maybe<&2, S.Error>
  for scratch: W.Scratch
  {W.loop(0n, state, dimension, facts, level, visit <> rest, terminal, Done{scratch}) ==
    (state, Fail{W.ReadBudget{}}) : P.State & Result<&2, &2, W.Error, W.Observation>}

law failed_read_retains_world_registry_receiver_history_and_affine_tail:
  for world: C.World
  for registry: B.Registry
  for receiver: P.Receiver
  for history: H.State
  for tail: List<&1, P.State>
  for dimension: String
  for visit: S.Visit
  for facts: P.Facts
  for level: P.Level
  for scratch: W.Scratch
  for +error: C.Error
  {W.read_owner(registry, receiver, history, tail, dimension, visit, facts, level, scratch, (world, Fail{error})) ==
    (P.State{world, registry, receiver, history, tail}, Fail{W.ProducerError{P.WorldError{error}}}) : P.State & Result<&2, &2, W.Error, W.Scratch>}

law actual_core_refusal_retains_complete_sweep_owner:
  for world: C.World
  for registry: B.Registry
  for receiver: P.Receiver
  for history: H.State
  for tail: List<&1, P.State>
  for +dimension: String
  for +visit: S.Visit
  for facts: P.Facts
  for level: P.Level
  for scratch: W.Scratch
  for +error: C.Error
  for service: {C.read_block(world, W.position(dimension, visit)) == (world, Fail{error}) : C.World & Result<&2, &2, C.Error, U32>}
  {W.read(P.State{world, registry, receiver, history, tail}, dimension, visit, facts, level, scratch) ==
    (P.State{world, registry, receiver, history, tail}, Fail{W.ProducerError{P.WorldError{error}}}) : P.State & Result<&2, &2, W.Error, W.Scratch>}

law registry_decode_refusal_retains_every_owned_field:
  for state: P.State
  for dimension: String
  for visit: S.Visit
  for facts: P.Facts
  for level: P.Level
  for scratch: W.Scratch
  for +error: B.Error
  {W.decoded(state, dimension, visit, facts, level, scratch, Fail{error}) ==
    (state, Fail{W.ProducerError{P.RegistryError{error}}}) : P.State & Result<&2, &2, W.Error, W.Scratch>}

law late_callback_service_refusal_discards_prior_effects:
  for +dimension: String
  for +visit: S.Visit
  for +identity: B.Resolved
  for +facts: P.Facts
  for +level: P.Level
  for +receiver: P.Receiver
  for +history: H.History
  for +impulse: Bool
  for +prior_reads: List<&2, P.Read>
  for +keys: List<&2, S.PackedKey>
  for +collector: U32
  for +reads: List<&2, W.Read>
  for +callbacks: List<&2, W.Callback>
  for +tail: List<&2, W.Scratch>
  for +error: P.Error
  for service: {P.callback_checked(receiver, history, facts, level, identity) == Fail{error} : Result<&2, &2, P.Error, P.Candidate>}
  {W.callback(dimension, visit, identity, facts, level,
    W.Scratch{P.Scratch{P.Candidate{receiver, history, impulse}, prior_reads}, keys, collector, reads, callbacks, tail}) ==
    Fail{W.ProducerError{error}} : Result<&2, &2, W.Error, W.Scratch>}

law successful_sweep_commits_only_receiver_and_history:
  for world: C.World
  for registry: B.Registry
  for old_receiver: P.Receiver
  for old_history: H.State
  for tail: List<&1, P.State>
  for +receiver: P.Receiver
  for +history: H.History
  for +impulse: Bool
  for +producer_reads: List<&2, P.Read>
  for keys: List<&2, S.PackedKey>
  for collector: U32
  for +reads: List<&2, W.Read>
  for +callbacks: List<&2, W.Callback>
  for scratch_tail: List<&2, W.Scratch>
  {W.commit(P.State{world, registry, old_receiver, old_history, tail},
    W.Scratch{P.Scratch{P.Candidate{receiver, history, impulse}, producer_reads}, keys, collector, reads, callbacks, scratch_tail}) ==
    (P.State{world, registry, receiver, H.State{history}, tail},
      Done{W.Observation{P.Observation{receiver, history, impulse, List.reverse(&2, P.Read, producer_reads)},
        List.reverse(&2, W.Read, reads), List.reverse(&2, W.Callback, callbacks)}}) : P.State & Result<&2, &2, W.Error, W.Observation>}

law noncanonical_request_cannot_read_or_commit:
  for state: P.State
  for dimension: String
  for facts: P.Facts
  for level: P.Level
  for removed: Bool
  for physics: Bool
  for alive: Bool
  for width: F32
  for height: F32
  for movements: List<&2, S.Movement>
  for traversal_fuel: Nat
  for read_fuel: Nat
  for head: W.Request
  for tail: List<&2, W.Request>
  {W.query(state, dimension, W.Request{facts, level, removed, physics, alive, width, height, movements, traversal_fuel, read_fuel, head <> tail}) ==
    (state, Fail{W.NonCanonicalRequest{}}) : P.State & Result<&2, &2, W.Error, W.Observation>}

law authoritative_berry_uses_actual_known_movement_observation:
  for +known: M.Vec3
  for old: M.Vec3
  for current: M.Vec3
  {Berry.damage_movement(Berry.ReceiverInput{True{}, known, old, current}) == known : M.Vec3}

law other_authority_berry_uses_actual_old_minus_current:
  for known: M.Vec3
  for +old: M.Vec3
  for +current: M.Vec3
  {Berry.damage_movement(Berry.ReceiverInput{False{}, known, old, current}) == P.vector_subtract(old, current) : M.Vec3}

law rejected_body_binding_retains_actual_motion_environment:
  for world: C.World
  for registry: B.Registry
  for +view: CW.View
  for support: SP.State
  for minor: LM.MinorState
  for history: H.State
  for tail: List<&1, MH.State>
  for +receiver: P.Receiver
  for dimension: String
  for request: W.Request
  for +error: SM.Error
  {SM.gate(P.State{world, registry, receiver, history, []}, PM.Frame{view, support, minor, tail}, dimension, request, Some{error}) ==
    (MH.State{CW.attach(G.Engine{world, registry}, view), support, minor, history, tail}, receiver, Fail{error}) : MH.State & P.Receiver & Result<&2, &2, SM.Error, W.Observation>}

law completed_sweep_restores_every_motion_environment_field:
  for world: C.World
  for registry: B.Registry
  for +view: CW.View
  for support: SP.State
  for minor: LM.MinorState
  for history: H.State
  for tail: List<&1, MH.State>
  for +receiver: P.Receiver
  for +observation: W.Observation
  {SM.completed(PM.Frame{view, support, minor, tail}, (P.State{world, registry, receiver, history, []}, Done{observation})) ==
    (MH.State{CW.attach(G.Engine{world, registry}, view), support, minor, history, tail}, receiver, Done{observation}) : MH.State & P.Receiver & Result<&2, &2, SM.Error, W.Observation>}

law existing_refusal_prevents_every_remaining_world_read:
  for fuel: Nat
  for state: P.State
  for dimension: String
  for facts: P.Facts
  for level: P.Level
  for visits: List<&2, S.Visit>
  for terminal: Maybe<&2, S.Error>
  for +error: W.Error
  {W.loop(fuel, state, dimension, facts, level, visits, terminal, Fail{error}) ==
    (state, Fail{error}) : P.State & Result<&2, &2, W.Error, W.Observation>}

# The premise is the actual owned read service, including Registry and callback
# refusal after arbitrary earlier speculative effects. The rest is never read.
law earliest_actual_read_refusal_prevents_later_reads:
  for +fuel: Nat
  for state: P.State
  for +dimension: String
  for +facts: P.Facts
  for +level: P.Level
  for +visit: S.Visit
  for +rest: List<&2, S.Visit>
  for +terminal: Maybe<&2, S.Error>
  for +scratch: W.Scratch
  for +error: W.Error
  for service: {W.read(state, dimension, visit, facts, level, scratch) == (state, Fail{error}) : P.State & Result<&2, &2, W.Error, W.Scratch>}
  {W.loop(1n+fuel, state, dimension, facts, level, visit <> rest, terminal, Done{scratch}) ==
    (state, Fail{error}) : P.State & Result<&2, &2, W.Error, W.Observation>}

law public_motion_join_installs_only_actual_successful_service_result:
  for world: C.World
  for registry: B.Registry
  for +view: CW.View
  for support: SP.State
  for minor: LM.MinorState
  for history: H.State
  for tail: List<&1, MH.State>
  for +receiver: P.Receiver
  for +dimension: String
  for +request: W.Request
  for +next_receiver: P.Receiver
  for next_history: H.State
  for +observation: W.Observation
  for binding: {SM.view_binding(view, request) == None{} : Maybe<&2, SM.Error>}
  for service: {W.query(P.State{world, registry, receiver, history, []}, dimension, request) ==
    (P.State{world, registry, next_receiver, next_history, []}, Done{observation}) : P.State & Result<&2, &2, W.Error, W.Observation>}
  {SM.after_movements(MH.State{CW.attach(G.Engine{world, registry}, view), support, minor, history, tail}, receiver, dimension, request) ==
    (MH.State{CW.attach(G.Engine{world, registry}, view), support, minor, next_history, tail}, next_receiver, Done{observation}) : MH.State & P.Receiver & Result<&2, &2, SM.Error, W.Observation>}

law public_motion_join_preserves_full_owner_on_service_refusal:
  for world: C.World
  for registry: B.Registry
  for +view: CW.View
  for support: SP.State
  for minor: LM.MinorState
  for history: H.State
  for tail: List<&1, MH.State>
  for +receiver: P.Receiver
  for +dimension: String
  for +request: W.Request
  for +error: W.Error
  for binding: {SM.view_binding(view, request) == None{} : Maybe<&2, SM.Error>}
  for service: {W.query(P.State{world, registry, receiver, history, []}, dimension, request) ==
    (P.State{world, registry, receiver, history, []}, Fail{error}) : P.State & Result<&2, &2, W.Error, W.Observation>}
  {SM.after_movements(MH.State{CW.attach(G.Engine{world, registry}, view), support, minor, history, tail}, receiver, dimension, request) ==
    (MH.State{CW.attach(G.Engine{world, registry}, view), support, minor, history, tail}, receiver, Fail{SM.SweepError{error}}) : MH.State & P.Receiver & Result<&2, &2, SM.Error, W.Observation>}

law empty_original_queue_uses_old_to_current_fallback:
  for +old: M.Vec3
  for +position: M.Vec3
  {ST.ready([], old, position) == [S.Movement{old, position, None{}}] : List<&2, S.Movement>}

law actual_subthreshold_endpoint_retains_complete_ordered_queue:
  for +pending: List<&2, S.Movement>
  for +endpoint: M.Vec3
  for +position: M.Vec3
  for within: {F.is_gt(M.Vec3.length_squared(Clip.subtract(endpoint, position)), S.tiny_square()) == False{} : Bool}
  {ST.ready_tail(pending, endpoint, position) == pending : List<&2, S.Movement>}

law dispatched_bridge_appends_without_changing_prior_records:
  for +pending: List<&2, S.Movement>
  for +endpoint: M.Vec3
  for +position: M.Vec3
  {ST.bridged(pending, endpoint, position, True{}) ==
    List.append(&2, S.Movement, pending, [S.Movement{endpoint, position, None{}}]) : List<&2, S.Movement>}

law refused_position_change_never_creates_a_travel_record:
  for prepared: T.Prepared
  for prepared_tail: List<&2, TH.Preparation>
  for body: M.Body
  for displacement: M.Vec3
  for stepped: Bool
  for motion_tail: List<&2, LM.Motion>
  for backoff: LCW.Observation
  for before: LM.BodySnapshot
  for minor: Maybe<&2, LC.MinorObservation>
  for move_tail: List<&2, LM.Outcome>
  for history: H.History
  for history_tail: List<&2, MH.Outcome>
  for final_motion: LM.Motion
  for travel_tail: List<&2, TH.Outcome>
  for ray: Maybe<&2, FR.Observation>
  for reset_tail: List<&2, TH.ResetOutcome>
  {ST.reset_record(TH.ResetOutcome{TH.Outcome{TH.Preparation{prepared, prepared_tail},
    MH.Outcome{LM.Outcome{LM.Motion{M.Transition{body, displacement, stepped, False{}}, motion_tail}, backoff, before, minor, move_tail}, history, history_tail}, final_motion, travel_tail}, ray, reset_tail}) ==
    None{} : Maybe<&2, S.Movement>}

law actual_travel_record_retains_post_backoff_original_and_raw_endpoint:
  for +prepared: T.Prepared
  for prepared_tail: List<&2, TH.Preparation>
  for body: M.Body
  for +displacement: M.Vec3
  for stepped: Bool
  for motion_tail: List<&2, LM.Motion>
  for +backoff: LCW.Observation
  for before: LM.BodySnapshot
  for minor: Maybe<&2, LC.MinorObservation>
  for move_tail: List<&2, LM.Outcome>
  for history: H.History
  for history_tail: List<&2, MH.Outcome>
  for final_motion: LM.Motion
  for travel_tail: List<&2, TH.Outcome>
  for ray: Maybe<&2, FR.Observation>
  for reset_tail: List<&2, TH.ResetOutcome>
  {ST.reset_record(TH.ResetOutcome{TH.Outcome{TH.Preparation{prepared, prepared_tail},
    MH.Outcome{LM.Outcome{LM.Motion{M.Transition{body, displacement, stepped, True{}}, motion_tail}, backoff, before, minor, move_tail}, history, history_tail}, final_motion, travel_tail}, ray, reset_tail}) ==
    Some{S.Movement{ST.body_position(TH.prepared_body(prepared)),
      M.Vec3.add(ST.body_position(TH.prepared_body(prepared)), displacement), Some{LM.backoff_requested(backoff)}}} : Maybe<&2, S.Movement>}
