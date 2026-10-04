import Base
import ./movement.bend as M
import ./geometry.bend as A
import ./f64.bend as F
import ./travel.bend as T
import ./local_travel_history.bend as TH
import ./local_move_history.bend as MH
import ./local_move_world.bend as LM
import ./player_fall_history.bend as H
import ./locomotion.bend as L
import ./client_world.bend as W
import ./game.bend as G
import ./player_input.bend as PI
import ./local_collision.bend as LC
import ./local_collision_world.bend as E

law inactive_multiplier_preserves_every_raw_field:
  for +body: M.Body
  for +request: M.Vec3
  for +multiplier: M.Vec3
  for inactive: {F.is_gt(M.Vec3.length_squared(multiplier), M.stuck_threshold()) == False{} : Bool}
  {M.stuck(body, request, multiplier) == M.StuckPreparation{body, request, multiplier, False{}} : M.StuckPreparation}

law active_multiplier_scales_request_and_clears_velocity:
  for +position: M.Vec3
  for +box: A.AABB
  for velocity: M.Vec3
  for +width: F32
  for +height: F32
  for +ground: Bool
  for +horizontal: Bool
  for +vertical: Bool
  for +below: Bool
  for +x: F.F64
  for +y: F.F64
  for +z: F.F64
  for +sx: F.F64
  for +sy: F.F64
  for +sz: F.F64
  {M.stuck_gate(M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below}, M.Vec3{x, y, z}, M.Vec3{sx, sy, sz}, True{}) ==
    M.StuckPreparation{M.Body{position, box, M.Vec3.zero(), width, height, ground, horizontal, vertical, below}, M.Vec3{F.mul(x, sx), F.mul(y, sy), F.mul(z, sz)}, M.Vec3.zero(), True{}} : M.StuckPreparation}

law refused_multiplier_has_no_candidate:
  for body: M.Body
  for request: M.Vec3
  for multiplier: M.Vec3
  for +cause: M.Error
  {M.stuck_checked_gate(body, request, multiplier, Some{cause}) == Fail{cause} : Result<&2, &2, M.Error, M.StuckPreparation>}

law corrected_preparation_preserves_travel_factors:
  for body: M.Body
  for request: M.Vec3
  for +friction: F32
  for +acceleration: F32
  for +maximum: F32
  for +gravity: F.F64
  for +drag: F.F64
  for +discard: Bool
  for +next: M.Body
  for +corrected: M.Vec3
  for multiplier: M.Vec3
  for applied: Bool
  {T.with_stuck(T.Prepared{body, request, friction, acceleration, maximum, gravity, drag, discard}, M.StuckPreparation{next, corrected, multiplier, applied}) == T.Prepared{next, corrected, friction, acceleration, maximum, gravity, drag, discard} : T.Prepared}

law resolved_hook_preserves_all_other_receiver_observations:
  for +keys: PI.Buttons
  for +input: PI.Vector
  for +flying: Bool
  for +mode: LC.Mode
  for +simulate: Bool
  for +authority: Bool
  for stuck: M.Vec3
  for +removed: Bool
  for +auto: Bool
  for +speed: Bool
  for +restitution: Bool
  for +environment: E.Environment
  for +fuel: Nat
  for +tail: List<&2, TH.Hooks>
  {TH.resolved_hooks(TH.Hooks{keys, input, flying, mode, simulate, authority, stuck, removed, auto, speed, restitution, environment, fuel, tail}) == TH.Hooks{keys, input, flying, mode, simulate, authority, M.Vec3.zero(), removed, auto, speed, restitution, environment, fuel, tail} : TH.Hooks}

law acceleration_failure_retains_complete_motion_owner:
  for engine: G.Engine
  for tables: L.Tables
  for +frame: TH.Frame
  for +cause: T.Error
  {TH.stuck_prepared(engine, frame, (tables, Fail{cause})) == (MH.State{W.attach(engine, TH.frame_view(frame)), TH.frame_support(frame), TH.frame_minor(frame), H.State{TH.frame_history(frame)}, []}, tables, Fail{TH.PreparationError{cause}}) : MH.State & L.Tables & Result<&2, &2, TH.Error, TH.Outcome>}

# This numerical-service premise binds the actual checked production phase.
# A rejection must restore the original world/body/support/minor/history and
# Tables owner, including when flight history dispatch was selected.
law refused_scaled_request_retains_complete_ability_motion_owner:
  for mode: H.Mode
  for engine: G.Engine
  for tables: L.Tables
  for +frame: TH.Frame
  for policy: TH.ResetPolicy
  for +prepared: T.Prepared
  for +cause: T.Error
  for refused: {T.stuck_checked(prepared, TH.hooks_stuck(TH.request_hooks(TH.frame_request(frame)))) == Fail{cause} : Result<&2, &2, T.Error, T.Prepared>}
  {TH.ability_reset_stuck_prepared(mode, engine, frame, policy, (tables, Done{prepared})) == (MH.State{W.attach(engine, TH.frame_view(frame)), TH.frame_support(frame), TH.frame_minor(frame), H.State{TH.frame_history(frame)}, []}, tables, Fail{TH.ResetTravelError{TH.PreparationError{cause}}}) : MH.State & L.Tables & Result<&2, &2, TH.ResetError, TH.ResetOutcome>}

law checked_stuck_failure_cannot_reach_collision:
  for prepared: T.Prepared
  for +cause: M.Error
  {T.stuck_prepared(prepared, Fail{cause}) == Fail{T.MovementError{cause}} : Result<&2, &2, T.Error, T.Prepared>}
