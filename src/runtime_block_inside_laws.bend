import Base
import ./runtime_block_inside.bend as R
import ./player_block_inside_stuck.bend as P
import ./player_block_inside_stuck_motion.bend as PM
import ./player_block_inside_sweep.bend as S
import ./player_block_inside_sweep_world.bend as W
import ./player_block_inside_sweep_motion.bend as SM
import ./player_block_inside_sweep_travel.bend as ST
import ./local_travel_history.bend as TH
import ./local_move_history.bend as MH
import ./local_move_world.bend as LM
import ./client_world.bend as CW
import ./game.bend as G
import ./movement.bend as M
import ./f64.bend as F
import ./core.bend as C
import ./registry.bend as B
import ./player_fall_history.bend as H
import ./support.bend as SP
import ./geometry.bend as A

law no_physics_preserves_complete_receiver_without_consumption:
  for +receiver: P.Receiver
  {R.consume(receiver, True{}) == receiver : P.Receiver}

law active_success_clears_multiplier_and_keeps_raw_impulse:
  for +multiplier: M.Vec3
  for +impulse: P.Impulse
  for active: {F.is_gt(M.Vec3.length_squared(multiplier), M.stuck_threshold()) == True{} : Bool}
  {R.consume(P.Receiver{multiplier, impulse}, False{}) ==
    P.Receiver{M.Vec3.zero(), impulse} : P.Receiver}

law inactive_success_keeps_raw_multiplier_and_impulse:
  for +multiplier: M.Vec3
  for +impulse: P.Impulse
  for inactive: {F.is_gt(M.Vec3.length_squared(multiplier), M.stuck_threshold()) == False{} : Bool}
  {R.consume(P.Receiver{multiplier, impulse}, False{}) ==
    P.Receiver{multiplier, impulse} : P.Receiver}

law callback_failure_restores_preconsumption_receiver_and_whole_motion_owner:
  for motion: MH.State
  for +previous: P.Receiver
  for consumed: P.Receiver
  for +error: SM.Error
  {R.completed(previous, (motion, consumed, Fail{error})) ==
    (motion, previous, Fail{R.CallbackError{error}}) : MH.State & P.Receiver & Result<&2, &2, R.Error, W.Observation>}

law callback_success_installs_actual_receiver_observation_and_whole_motion_owner:
  for motion: MH.State
  for previous: P.Receiver
  for +next: P.Receiver
  for +observation: W.Observation
  {R.completed(previous, (motion, next, Done{observation})) ==
    (motion, next, Done{observation}) : MH.State & P.Receiver & Result<&2, &2, R.Error, W.Observation>}

law noncanonical_hooks_refuse_before_consumption_or_world_callbacks:
  for motion: MH.State
  for +receiver: P.Receiver
  for facts: P.Facts
  for level: P.Level
  for old: M.Vec3
  for dimension: String
  for removed: Bool
  for physics: Bool
  for alive: Bool
  for traversal: Nat
  for reads: Nat
  for head: R.Hooks
  for tail: List<&2, R.Hooks>
  for outcome: TH.Outcome
  {R.after_successful_travel(motion, receiver,
    R.Hooks{facts, level, old, dimension, removed, physics, alive, traversal, reads, head <> tail}, outcome) ==
    (motion, receiver, Fail{R.NonCanonicalHooks{}}) : MH.State & P.Receiver & Result<&2, &2, R.Error, W.Observation>}

law request_uses_actual_held_dimensions_and_position_with_ordered_travel_record:
  for +position: M.Vec3
  for box: A.AABB
  for velocity: M.Vec3
  for +width: F32
  for +height: F32
  for ground: Bool
  for horizontal: Bool
  for vertical: Bool
  for below: Bool
  for yaw: F32
  for pitch: F32
  for palette: Maybe<&2, CW.Palette>
  for region: CW.Bounds
  for cache: Maybe<&2, CW.SnapshotCache>
  for +facts: P.Facts
  for +level: P.Level
  for +old: M.Vec3
  for dimension: String
  for +removed: Bool
  for +physics: Bool
  for +alive: Bool
  for +traversal: Nat
  for +reads: Nat
  for hooks_tail: List<&2, R.Hooks>
  for +record: Maybe<&2, S.Movement>
  {R.request(CW.View{M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below}, yaw, pitch, palette, region, cache},
    R.Hooks{facts, level, old, dimension, removed, physics, alive, traversal, reads, hooks_tail}, record) ==
    W.Request{facts, level, removed, physics, alive, width, height,
      ST.ready(R.record_list(record), old, position), traversal, reads, []} : W.Request}

# The service premise names the actual production full-owner sweep, not a
# substitute query. Every World/View/support/minor/history/affine-tail field
# remains in the public join's quantified input and returned owner.
law public_callback_refusal_restores_original_receiver_and_complete_held_owner:
  for world: C.World
  for registry: B.Registry
  for +view: CW.View
  for support: SP.State
  for minor: LM.MinorState
  for history: H.State
  for tail: List<&1, MH.State>
  for +receiver: P.Receiver
  for +facts: P.Facts
  for +level: P.Level
  for +old: M.Vec3
  for +dimension: String
  for +removed: Bool
  for +physics: Bool
  for +alive: Bool
  for +traversal: Nat
  for +reads: Nat
  for +outcome: TH.Outcome
  for +error: SM.Error
  for service: {SM.framed(P.State{world, registry, R.consume(receiver, physics), history, []},
    PM.Frame{view, support, minor, tail}, dimension,
    R.request(view, R.Hooks{facts, level, old, dimension, removed, physics, alive, traversal, reads, []}, ST.travel_record(outcome))) ==
    (MH.State{CW.attach(G.Engine{world, registry}, view), support, minor, history, tail}, R.consume(receiver, physics), Fail{error}) :
      MH.State & P.Receiver & Result<&2, &2, SM.Error, W.Observation>}
  {R.after_successful_travel(MH.State{CW.attach(G.Engine{world, registry}, view), support, minor, history, tail}, receiver,
    R.Hooks{facts, level, old, dimension, removed, physics, alive, traversal, reads, []}, outcome) ==
    (MH.State{CW.attach(G.Engine{world, registry}, view), support, minor, history, tail}, receiver, Fail{R.CallbackError{error}}) :
      MH.State & P.Receiver & Result<&2, &2, R.Error, W.Observation>}

law public_callback_success_keeps_entire_actual_service_owner_and_receiver:
  for world: C.World
  for registry: B.Registry
  for +view: CW.View
  for support: SP.State
  for minor: LM.MinorState
  for history: H.State
  for tail: List<&1, MH.State>
  for +receiver: P.Receiver
  for +facts: P.Facts
  for +level: P.Level
  for +old: M.Vec3
  for +dimension: String
  for +removed: Bool
  for +physics: Bool
  for +alive: Bool
  for +traversal: Nat
  for +reads: Nat
  for +outcome: TH.Outcome
  for next_motion: MH.State
  for +next_receiver: P.Receiver
  for +observation: W.Observation
  for service: {SM.framed(P.State{world, registry, R.consume(receiver, physics), history, []},
    PM.Frame{view, support, minor, tail}, dimension,
    R.request(view, R.Hooks{facts, level, old, dimension, removed, physics, alive, traversal, reads, []}, ST.travel_record(outcome))) ==
    (next_motion, next_receiver, Done{observation}) : MH.State & P.Receiver & Result<&2, &2, SM.Error, W.Observation>}
  {R.after_successful_travel(MH.State{CW.attach(G.Engine{world, registry}, view), support, minor, history, tail}, receiver,
    R.Hooks{facts, level, old, dimension, removed, physics, alive, traversal, reads, []}, outcome) ==
    (next_motion, next_receiver, Done{observation}) : MH.State & P.Receiver & Result<&2, &2, R.Error, W.Observation>}

law receiver_comparison_rejects_missing_impact:
  for impact: M.Vec3
  {R.same_impact(None{}, Some{impact}) == False{} : Bool}
