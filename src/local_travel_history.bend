import Base
import ./local_move_history.bend as MH
import ./local_move_world.bend as LM
import ./player_fall_history.bend as H
import ./travel.bend as T
import ./local_collision.bend as LC
import ./local_collision_world.bend as E
import ./player_input.bend as PI
import ./client_world.bend as W
import ./game.bend as G
import ./movement.bend as M
import ./locomotion.bend as L
import ./support.bend as SP
import ./fall_reset_world.bend as FR
import ./geometry.bend as A
import ./f64.bend as F

# Conditional current receiver observations, not inferred from old crouch/support
# or the radian camera. Actual travel always moves with MoverType.SELF.
type Hooks is Data:
  Hooks{keys: PI.Buttons, input: PI.Vector, flying: Bool, mode: LC.Mode,
        can_simulate: Bool, local_authoritative: Bool, stuck_multiplier: M.Vec3,
        removed: Bool, auto_jump_enabled: Bool, unit_block_speed: Bool,
        zero_restitution: Bool, environment: E.Environment, fuel: Nat,
        tail: List<&2, Hooks>}

# No Body/history authority in a request. Ground/attributes, degree yaw and current
# input fields are conditional resolved observations supplied by the caller.
type Request is Data:
  Request{input: M.Vec3, context: T.Context, hooks: Hooks, clip: H.Clip,
          tail: List<&2, Request>}

type Preparation is Data:
  Preparation{value: T.Prepared, tail: List<&2, Preparation>}

type Outcome is Data:
  Outcome{prepared: Preparation, movement: MH.Outcome, motion: LM.Motion,
          tail: List<&2, Outcome>}

type Error is Data:
  NonCanonicalState{}
  NonCanonicalRequest{field: U32}
  PreparationError{cause: T.Error}
  MovementError{cause: MH.Error}
  FinishError{cause: T.Error}

# Data rollback evidence contains no Core/Table owners. Its Body/history are
# immutable snapshots; MH.State remains the sole authoritative persistent owner.
type Frame is Data:
  Frame{view: W.View, support: SP.State, minor: LM.MinorState,
        history: H.History, request: Request, tail: List<&2, Frame>}

def frame_view(frame: Frame) -> W.View:
  Frame{view, support, minor, history, request, tail} = frame
  view

def frame_support(frame: Frame) -> SP.State:
  Frame{view, support, minor, history, request, tail} = frame
  support

def frame_minor(frame: Frame) -> LM.MinorState:
  Frame{view, support, minor, history, request, tail} = frame
  minor

def frame_history(frame: Frame) -> H.History:
  Frame{view, support, minor, history, request, tail} = frame
  history

def frame_request(frame: Frame) -> Request:
  Frame{view, support, minor, history, request, tail} = frame
  request

def request_context(request: Request) -> T.Context:
  Request{input, context, hooks, clip, tail} = request
  context

def request_input(request: Request) -> M.Vec3:
  Request{input, context, hooks, clip, tail} = request
  input

def request_hooks(request: Request) -> Hooks:
  Request{input, context, hooks, clip, tail} = request
  hooks

def request_clip(request: Request) -> H.Clip:
  Request{input, context, hooks, clip, tail} = request
  clip

def context_yaw(context: T.Context) -> F32:
  T.Context{ground, attributes, yaw, maximum, sprinting, no_gravity, discard, mode} = context
  yaw

def context_maximum(context: T.Context) -> F32:
  T.Context{ground, attributes, yaw, maximum, sprinting, no_gravity, discard, mode} = context
  maximum

def hooks_environment(hooks: Hooks) -> E.Environment:
  Hooks{keys, input, flying, mode, can_simulate, local_authoritative, stuck, removed, auto, speed, restitution, environment, fuel, tail} = hooks
  environment

def hooks_fuel(hooks: Hooks) -> Nat:
  Hooks{keys, input, flying, mode, can_simulate, local_authoritative, stuck, removed, auto, speed, restitution, environment, fuel, tail} = hooks
  fuel

def movement_context(+context: T.Context, history: H.History, hooks: Hooks) -> LM.Context:
  Hooks{keys, PI.Vector{xxa, zza}, flying, mode, simulate, authority, stuck, removed, auto, speed, restitution, environment, fuel, tail} = hooks
  LM.Context{LC.EdgeContext{context_maximum(context), MH.history_distance(history), flying, keys, LC.Self{}, mode},
    LC.MinorInput{context_yaw(context), xxa, zza}, simulate, authority, stuck, removed, auto, speed, restitution}

def preparation_value(prepared: Preparation) -> T.Prepared:
  Preparation{value, tail} = prepared
  value

def prepared_body(prepared: T.Prepared) -> M.Body:
  T.Prepared{body, requested, friction, acceleration, maximum, gravity, drag, discard} = prepared
  body

def prepared_request(prepared: T.Prepared) -> M.Vec3:
  T.Prepared{body, requested, friction, acceleration, maximum, gravity, drag, discard} = prepared
  requested

def move_request(+frame: Frame, +prepared: T.Prepared) -> MH.Request:
  MH.Request{LM.Request{prepared_body(prepared), prepared_request(prepared),
    movement_context(request_context(frame_request(frame)), frame_history(frame), request_hooks(frame_request(frame))),
    hooks_environment(request_hooks(frame_request(frame))), hooks_fuel(request_hooks(frame_request(frame))), []},
    request_clip(frame_request(frame)), []}

def view_body(view: W.View) -> M.Body:
  W.View{body, yaw, pitch, palette, region, cache} = view
  body

def with_body(view: W.View, body: M.Body) -> W.View:
  W.View{old, yaw, pitch, palette, region, cache} = view
  W.View{body, yaw, pitch, palette, region, cache}

def rollback_taken(tables: L.Tables, +frame: Frame, cause: Error,
                   result: G.Engine & W.View) -> MH.State & L.Tables & Result<&2, &2, Error, Outcome>:
  (engine, current) = result
  (MH.State{W.attach(engine, frame_view(frame)), frame_support(frame), frame_minor(frame), H.State{frame_history(frame)}, []}, tables, Fail{cause})

def rollback(state: MH.State, tables: L.Tables, frame: Frame, cause: Error) -> MH.State & L.Tables & Result<&2, &2, Error, Outcome>:
  MH.State{world, support, minor, history, tail} = state
  rollback_taken(tables, frame, cause, W.take(world))

def committed(tables: L.Tables, support: SP.State, minor: LM.MinorState, history: H.State,
              prepared: Preparation, movement: MH.Outcome, +transition: M.Transition,
              result: G.Engine & W.View) -> MH.State & L.Tables & Result<&2, &2, Error, Outcome>:
  (engine, view) = result
  (MH.State{W.attach(engine, with_body(view, LM.transition_body(transition))), support, minor, history, []},
    tables, Done{Outcome{prepared, movement, LM.Motion{transition, []}, []}})

def commit(state: MH.State, tables: L.Tables, prepared: Preparation, movement: MH.Outcome,
           transition: M.Transition) -> MH.State & L.Tables & Result<&2, &2, Error, Outcome>:
  MH.State{world, support, minor, history, tail} = state
  committed(tables, support, minor, history, prepared, movement, transition, W.take(world))

def finished(state: MH.State, tables: L.Tables, frame: Frame, prepared: Preparation,
             movement: MH.Outcome, result: Result<&2, &2, T.Error, M.Transition>) -> MH.State & L.Tables & Result<&2, &2, Error, Outcome>:
  match result:
    case Fail{cause}: rollback(state, tables, frame, FinishError{cause})
    case Done{transition}: commit(state, tables, prepared, movement, transition)

def movement_outcome(outcome: MH.Outcome) -> LM.Outcome:
  MH.Outcome{move, history, tail} = outcome
  move

def outcome_transition(outcome: Outcome) -> M.Transition:
  Outcome{prepared, movement, motion, tail} = outcome
  LM.motion_transition(motion)

def outcome_preparation(outcome: Outcome) -> T.Prepared:
  Outcome{prepared, movement, motion, tail} = outcome
  preparation_value(prepared)

def outcome_movement(outcome: Outcome) -> MH.Outcome:
  Outcome{prepared, movement, motion, tail} = outcome
  movement

def moved(+frame: Frame, +prepared: Preparation,
          result: MH.State & L.Tables & Result<&2, &2, MH.Error, MH.Outcome>) -> MH.State & L.Tables & Result<&2, &2, Error, Outcome>:
  (state, tables, status) = result
  match status:
    case Fail{cause}: rollback(state, tables, frame, MovementError{cause})
    case Done{+movement}:
      finished(state, tables, frame, prepared, movement,
        T.finish_checked(preparation_value(prepared), MH.outcome_transition(movement_outcome(movement))))

# Install the accelerated velocity once. Backoff only changes the request; MH's
# support/minor callbacks observe this original prepared velocity before restitution.
def prepared(engine: G.Engine, +frame: Frame,
             result: L.Tables & Result<&2, &2, T.Error, T.Prepared>) -> MH.State & L.Tables & Result<&2, &2, Error, Outcome>:
  (tables, status) = result
  match status:
    case Fail{cause}: rollback_taken(tables, frame, PreparationError{cause}, (engine, frame_view(frame)))
    case Done{+value}:
      moved(frame, Preparation{value, []}, MH.move_checked(
        MH.State{W.attach(engine, with_body(frame_view(frame), prepared_body(value))), frame_support(frame), frame_minor(frame), H.State{frame_history(frame)}, []},
        tables, move_request(frame, value)))

def extracted(tables: L.Tables, support: SP.State, minor: LM.MinorState,
              history: H.History, +request: Request,
              result: G.Engine & W.View) -> MH.State & L.Tables & Result<&2, &2, Error, Outcome>:
  (engine, +view) = result
  prepared(engine, Frame{view, support, minor, history, request, []},
    T.prepare_checked(tables, view_body(view), request_input(request), request_context(request)))

def canonical_state(state: MH.State, tables: L.Tables, request: Request) -> MH.State & L.Tables & Result<&2, &2, Error, Outcome>:
  match state:
    case MH.State{world, support, minor, H.State{history}, Nil{}}:
      extracted(tables, support, minor, history, request, W.take(world))
    case MH.State{world, support, minor, history, tail}:
      (MH.State{world, support, minor, history, tail}, tables, Fail{NonCanonicalState{}})

def hooks_gate(state: MH.State, tables: L.Tables, input: M.Vec3, context: T.Context,
               hooks: Hooks, clip: H.Clip) -> MH.State & L.Tables & Result<&2, &2, Error, Outcome>:
  match hooks:
    case Hooks{keys, axes, flying, mode, simulate, authority, stuck, removed, auto, speed, restitution, environment, fuel, Nil{}}:
      canonical_state(state, tables, Request{input, context, Hooks{keys, axes, flying, mode, simulate, authority, stuck, removed, auto, speed, restitution, environment, fuel, []}, clip, []})
    case _: (state, tables, Fail{NonCanonicalRequest{1}})

def travel_checked(state: MH.State, tables: L.Tables, request: Request) -> MH.State & L.Tables & Result<&2, &2, Error, Outcome>:
  match request:
    case Request{input, context, hooks, clip, Nil{}}: hooks_gate(state, tables, input, context, hooks, clip)
    case _: (state, tables, Fail{NonCanonicalRequest{0}})

law rollback_returns_same_engine_tables_and_complete_prior_state:
  for engine: G.Engine
  for tables: L.Tables
  for +frame: Frame
  for current: W.View
  for +error: Error
  {rollback_taken(tables, frame, error, (engine, current)) ==
    (MH.State{W.attach(engine, frame_view(frame)), frame_support(frame), frame_minor(frame), H.State{frame_history(frame)}, []}, tables, Fail{error}) : MH.State & L.Tables & Result<&2, &2, Error, Outcome>}

def rollback_returns_same_engine_tables_and_complete_prior_state(engine, tables, frame, current, error):
  {==}

law noncanonical_owned_tail_retains_every_child:
  for world: W.State
  for support: SP.State
  for minor: LM.MinorState
  for history: H.State
  for child: MH.State
  for tail: List<&1, MH.State>
  for tables: L.Tables
  for request: Request
  {canonical_state(MH.State{world, support, minor, history, child <> tail}, tables, request) ==
    (MH.State{world, support, minor, history, child <> tail}, tables, Fail{NonCanonicalState{}}) : MH.State & L.Tables & Result<&2, &2, Error, Outcome>}

def noncanonical_owned_tail_retains_every_child(world, support, minor, history, child, tail, tables, request):
  match history:
    case H.State{distance}: {==}

law request_tail_rejection_returns_state_and_tables:
  for state: MH.State
  for tables: L.Tables
  for input: M.Vec3
  for context: T.Context
  for hooks: Hooks
  for clipping: H.Clip
  for child: Request
  for tail: List<&2, Request>
  {travel_checked(state, tables, Request{input, context, hooks, clipping, child <> tail}) ==
    (state, tables, Fail{NonCanonicalRequest{0}}) : MH.State & L.Tables & Result<&2, &2, Error, Outcome>}

def request_tail_rejection_returns_state_and_tables(state, tables, input, context, hooks, clipping, child, tail):
  {==}

law late_finish_failure_restores_prior_state:
  for state: MH.State
  for tables: L.Tables
  for frame: Frame
  for prepared: Preparation
  for movement: MH.Outcome
  for error: T.Error
  {finished(state, tables, frame, prepared, movement, Fail{error}) ==
    rollback(state, tables, frame, FinishError{error}) : MH.State & L.Tables & Result<&2, &2, Error, Outcome>}

def late_finish_failure_restores_prior_state(state, tables, frame, prepared, movement, error):
  {==}

law degree_yaw_and_step_bind_from_travel_context:
  for +sample: T.GroundSample
  for +attributes: T.Attributes
  for +yaw: F32
  for +maximum: F32
  for +sprinting: Bool
  for +no_gravity: Bool
  for +discard: Bool
  for +travel_mode: T.Mode
  for history: H.History
  for +keys: PI.Buttons
  for +xxa: F32
  for +zza: F32
  for +flying: Bool
  for +hook_mode: LC.Mode
  for +simulate: Bool
  for +authority: Bool
  for +stuck: M.Vec3
  for +removed: Bool
  for +auto: Bool
  for +speed: Bool
  for +restitution: Bool
  for environment: E.Environment
  for fuel: Nat
  {movement_context(T.Context{sample, attributes, yaw, maximum, sprinting, no_gravity, discard, travel_mode}, history,
    Hooks{keys, PI.Vector{xxa, zza}, flying, hook_mode, simulate, authority, stuck, removed, auto, speed, restitution, environment, fuel, []}) ==
    LM.Context{LC.EdgeContext{maximum, MH.history_distance(history), flying, keys, LC.Self{}, hook_mode}, LC.MinorInput{yaw, xxa, zza}, simulate, authority, stuck, removed, auto, speed, restitution} : LM.Context}

def degree_yaw_and_step_bind_from_travel_context(sample, attributes, yaw, maximum, sprinting, no_gravity, discard, travel_mode, history, keys, xxa, zza, flying, hook_mode, simulate, authority, stuck, removed, auto, speed, restitution, environment, fuel):
  {==}

# Additive resolved-motion reset supplier path. The original API above is kept
# byte-identical; its caller-supplied Clip contract remains available.
type ResetPolicy is Data:
  ResetPolicy{interior: A.AABB, work: Nat, profile: FR.Profile,
              tail: List<&2, ResetPolicy>}

# Policy carries no independent Body, history, endpoints or clip observation.
type ResetRequest is Data:
  ResetRequest{input: M.Vec3, context: T.Context, hooks: Hooks,
               policy: ResetPolicy, tail: List<&2, ResetRequest>}

type ResetError is Data:
  ResetTravelError{cause: Error}
  ResetSupplierError{cause: FR.Error}
  ResetHistoryError{cause: H.Error}

type ResetOutcome is Data:
  ResetOutcome{travel: Outcome, ray: Maybe<&2, FR.Observation>,
               tail: List<&2, ResetOutcome>}

# Boxed continuations keep one sole World/Tables owner outside Data snapshots.
type ResetStage is Data:
  ResetStage{frame: Frame, policy: ResetPolicy, prepared: Preparation,
             tail: List<&2, ResetStage>}

type ResetWork is Data:
  ResetWork{stage: ResetStage, move: LM.Outcome,
            ray: Maybe<&2, FR.Observation>, tail: List<&2, ResetWork>}

def reset_travel_error_text(error: T.Error) -> String:
  match error:
    case T.UnsupportedContext{mode}: "unsupported-context"
    case T.InvalidContext{field}: "invalid-context:" ++ U32.show(field)
    case T.InvalidAttribute{field}: "invalid-attribute:" ++ U32.show(field)
    case T.InvalidInput{field}: "invalid-input:" ++ U32.show(field)
    case T.MovementError{cause}: "invalid-body"

def reset_history_error_text(error: H.Error) -> String:
  match error:
    case H.NonFinite{field}: "nonfinite:" ++ U32.show(field)
    case H.InvalidLengthSquared{}: "negative-square"
    case H.UnsupportedMode{mode}: "unsupported-mode"
    case H.MissingClipObservation{}: "missing-clip"
    case H.UnexpectedClipObservation{}: "unexpected-clip"
    case H.UnsupportedResetHit{}: "reset-hit"
    case H.UnsupportedLanding{}: "landing"
    case H.NonFiniteResult{}: "nonfinite-result"

def reset_movement_error_text(error: MH.Error) -> String:
  match error:
    case MH.NonCanonicalState{}: "noncanonical-state"
    case MH.NonCanonicalRequest{field}: "noncanonical-request:" ++ U32.show(field)
    case MH.HistoryMismatch{}: "history-mismatch"
    case MH.MoveError{cause}: "move:" ++ LM.error_text(cause)
    case MH.HistoryError{cause}: "history:" ++ reset_history_error_text(cause)

def reset_old_error_text(error: Error) -> String:
  match error:
    case NonCanonicalState{}: "noncanonical-state"
    case NonCanonicalRequest{field}: "noncanonical-request:" ++ U32.show(field)
    case PreparationError{cause}: "prepare:" ++ reset_travel_error_text(cause)
    case MovementError{cause}: "movement:" ++ reset_movement_error_text(cause)
    case FinishError{cause}: "finish:" ++ reset_travel_error_text(cause)

def reset_error_text(error: ResetError) -> String:
  match error:
    case ResetTravelError{cause}: reset_old_error_text(cause)
    case ResetSupplierError{cause}: "reset-supplier:" ++ FR.error_text(cause)
    case ResetHistoryError{cause}: "reset-history:" ++ reset_history_error_text(cause)

def reset_outcome_travel(outcome: ResetOutcome) -> Outcome:
  ResetOutcome{travel, ray, tail} = outcome
  travel

def reset_outcome_ray(outcome: ResetOutcome) -> Maybe<&2, FR.Observation>:
  ResetOutcome{travel, ray, tail} = outcome
  ray

def reset_outcome_transition(outcome: ResetOutcome) -> M.Transition:
  outcome_transition(reset_outcome_travel(outcome))

def reset_stage_frame(stage: ResetStage) -> Frame:
  ResetStage{frame, policy, prepared, tail} = stage
  frame

def reset_stage_policy(stage: ResetStage) -> ResetPolicy:
  ResetStage{frame, policy, prepared, tail} = stage
  policy

def reset_stage_preparation(stage: ResetStage) -> Preparation:
  ResetStage{frame, policy, prepared, tail} = stage
  prepared

def reset_work_stage(work: ResetWork) -> ResetStage:
  ResetWork{stage, move, ray, tail} = work
  stage

def reset_work_move(work: ResetWork) -> LM.Outcome:
  ResetWork{stage, move, ray, tail} = work
  move

def reset_work_ray(work: ResetWork) -> Maybe<&2, FR.Observation>:
  ResetWork{stage, move, ray, tail} = work
  ray

def reset_body_feet(body: M.Body) -> M.Vec3:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = body
  position

# Actual Vec3.normalize followed by scale(min(length,8)), then old feet + delta.
# Called only after checked finite squared length >= 1 and finite resolved move.
def reset_length_limit(+length: F.F64) -> F.F64:
  W.choose(F.F64, length, F.from_u32(8), F.is_lt(length, F.from_u32(8)))

def reset_ray_to(old_feet: M.Vec3, +resolved: M.Vec3) -> M.Vec3:
  M.Vec3.add(old_feet, L.scale(L.normalize(resolved),
    reset_length_limit(F.sqrt(M.Vec3.length_squared(resolved)))))

def reset_ray_policy(+stage: ResetStage, transition: M.Transition, policy: ResetPolicy) -> FR.Request:
  ResetPolicy{interior, work, profile, tail} = policy
  +old_feet = reset_body_feet(view_body(frame_view(reset_stage_frame(stage))))
  FR.Request{old_feet, reset_ray_to(old_feet, LM.transition_displacement(transition)), interior, work, profile, []}

def reset_ray_request(+stage: ResetStage, transition: M.Transition) -> FR.Request:
  reset_ray_policy(stage, transition, reset_stage_policy(stage))

def reset_required_metadata(history: H.History, movement: H.Movement) -> Bool:
  H.Movement{applied, y, squared, ground, clip} = movement
  H.clip_required(MH.history_distance(history), applied, squared)

def reset_is_required(history: H.History, transition: M.Transition) -> Bool:
  reset_required_metadata(history, MH.movement_from(transition, H.NotRequired{}))

def reset_move_request(+frame: Frame, +prepared: T.Prepared) -> LM.Request:
  LM.Request{prepared_body(prepared), prepared_request(prepared),
    movement_context(request_context(frame_request(frame)), frame_history(frame), request_hooks(frame_request(frame))),
    hooks_environment(request_hooks(frame_request(frame))), hooks_fuel(request_hooks(frame_request(frame))), []}

def reset_rollback_taken(tables: L.Tables, +frame: Frame, cause: ResetError,
                        result: G.Engine & W.View) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  (engine, current) = result
  (MH.State{W.attach(engine, frame_view(frame)), frame_support(frame), frame_minor(frame), H.State{frame_history(frame)}, []}, tables, Fail{cause})

def reset_rollback(world: W.State, tables: L.Tables, frame: Frame,
                   cause: ResetError) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  reset_rollback_taken(tables, frame, cause, W.take(world))

def reset_committed(tables: L.Tables, support: SP.State, minor: LM.MinorState,
                    history_state: H.State, +work: ResetWork, +transition: M.Transition,
                    result: G.Engine & W.View) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  H.State{+history} = history_state
  (engine, view) = result
  (MH.State{W.attach(engine, with_body(view, LM.transition_body(transition))), support, minor, H.State{history}, []}, tables,
    Done{ResetOutcome{Outcome{reset_stage_preparation(reset_work_stage(work)),
      MH.Outcome{reset_work_move(work), history, []}, LM.Motion{transition, []}, []}, reset_work_ray(work), []}})

def reset_finished(world: W.State, tables: L.Tables, support: SP.State,
                   minor: LM.MinorState, history: H.State, work: ResetWork,
                   result: Result<&2, &2, T.Error, M.Transition>) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  match result:
    case Fail{cause}: reset_rollback(world, tables, reset_stage_frame(reset_work_stage(work)), ResetTravelError{FinishError{cause}})
    case Done{transition}: reset_committed(tables, support, minor, history, work, transition, W.take(world))

def reset_history_finished(world: W.State, tables: L.Tables, support: SP.State,
                           minor: LM.MinorState, +work: ResetWork,
                           result: H.State & Result<&2, &2, H.Error, Unit>) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  (history, status) = result
  match status:
    case Fail{cause}: reset_rollback(world, tables, reset_stage_frame(reset_work_stage(work)), ResetHistoryError{cause})
    case Done{unit}:
      reset_finished(world, tables, support, minor, history, work,
        T.finish_checked(preparation_value(reset_stage_preparation(reset_work_stage(work))), MH.outcome_transition(reset_work_move(work))))

def reset_apply_history(world: W.State, tables: L.Tables, support: SP.State,
                        minor: LM.MinorState, +work: ResetWork, clip: H.Clip) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  reset_history_finished(world, tables, support, minor, work,
    H.movement(H.NeutralDryNoDamage{}, MH.movement_from(MH.outcome_transition(reset_work_move(work)), clip),
      H.State{frame_history(reset_stage_frame(reset_work_stage(work)))}))

def reset_with_observation(work: ResetWork, observation: FR.Observation) -> ResetWork:
  ResetWork{stage, move, ray, tail} = work
  ResetWork{stage, move, Some{observation}, []}

def reset_supplied(tables: L.Tables, support: SP.State, minor: LM.MinorState,
                   work: ResetWork, result: W.State & Result<&2, &2, FR.Error, FR.Observation>) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  (world, status) = result
  match status:
    case Fail{cause}: reset_rollback(world, tables, reset_stage_frame(reset_work_stage(work)), ResetSupplierError{cause})
    case Done{+observation}:
      reset_apply_history(world, tables, support, minor, reset_with_observation(work, observation), FR.observation_clip(observation))

# No supplier invocation, profile/box admission or Core read in the False branch.
def reset_requirement(world: W.State, tables: L.Tables, support: SP.State,
                      minor: LM.MinorState, +work: ResetWork, required: Bool) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  match required:
    case False{}: reset_apply_history(world, tables, support, minor, work, H.NotRequired{})
    case True{}:
      reset_supplied(tables, support, minor, work,
        FR.clip_checked(world, reset_ray_request(reset_work_stage(work), MH.outcome_transition(reset_work_move(work)))))

def reset_metadata_checked(world: W.State, tables: L.Tables, support: SP.State,
                           minor: LM.MinorState, +work: ResetWork,
                           error: Maybe<&2, H.Error>) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  match error:
    case Some{cause}: reset_rollback(world, tables, reset_stage_frame(reset_work_stage(work)), ResetHistoryError{cause})
    case None{}:
      reset_requirement(world, tables, support, minor, work,
        reset_is_required(frame_history(reset_stage_frame(reset_work_stage(work))), MH.outcome_transition(reset_work_move(work))))

def reset_moved(+stage: ResetStage,
                result: W.State & L.Tables & SP.State & LM.MinorState & Result<&2, &2, LM.Error, LM.Outcome>) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  (world, tables, support, minor, status) = result
  match status:
    case Fail{cause}: reset_rollback(world, tables, reset_stage_frame(stage), ResetTravelError{MovementError{MH.MoveError{cause}}})
    case Done{+move}:
      reset_metadata_checked(world, tables, support, minor, ResetWork{stage, move, None{}, []},
        H.movement_error(MH.movement_from(MH.outcome_transition(move), H.NotRequired{})))

def reset_prepared(engine: G.Engine, +frame: Frame, policy: ResetPolicy,
                   result: L.Tables & Result<&2, &2, T.Error, T.Prepared>) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  (tables, status) = result
  match status:
    case Fail{cause}: reset_rollback_taken(tables, frame, ResetTravelError{PreparationError{cause}}, (engine, frame_view(frame)))
    case Done{+value}:
      reset_moved(ResetStage{frame, policy, Preparation{value, []}, []},
        LM.move_checked(W.attach(engine, with_body(frame_view(frame), prepared_body(value))), tables,
          frame_support(frame), frame_minor(frame), reset_move_request(frame, value)))

def reset_initial_history(engine: G.Engine, tables: L.Tables, +frame: Frame,
                          policy: ResetPolicy, error: Maybe<&2, H.Error>) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  match error:
    case Some{cause}: reset_rollback_taken(tables, frame, ResetHistoryError{cause}, (engine, frame_view(frame)))
    case None{}:
      reset_prepared(engine, frame, policy,
        T.prepare_checked(tables, view_body(frame_view(frame)), request_input(frame_request(frame)), request_context(frame_request(frame))))

def reset_extracted(tables: L.Tables, support: SP.State, minor: LM.MinorState,
                     +history: H.History, request: Request, policy: ResetPolicy,
                     result: G.Engine & W.View) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  (engine, view) = result
  reset_initial_history(engine, tables, Frame{view, support, minor, history, request, []}, policy, H.history_error(history))

def reset_canonical_state(state: MH.State, tables: L.Tables, request: Request,
                           policy: ResetPolicy) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  match state:
    case MH.State{world, support, minor, H.State{history}, Nil{}}:
      reset_extracted(tables, support, minor, history, request, policy, W.take(world))
    case MH.State{world, support, minor, history, tail}:
      (MH.State{world, support, minor, history, tail}, tables, Fail{ResetTravelError{NonCanonicalState{}}})

def reset_policy_gate(state: MH.State, tables: L.Tables, request: Request,
                       policy: ResetPolicy) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  match policy:
    case ResetPolicy{interior, work, profile, Nil{}}:
      reset_canonical_state(state, tables, request, ResetPolicy{interior, work, profile, []})
    case _: (state, tables, Fail{ResetTravelError{NonCanonicalRequest{2}}})

def reset_hooks_gate(state: MH.State, tables: L.Tables, input: M.Vec3,
                      context: T.Context, hooks: Hooks, policy: ResetPolicy) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  match hooks:
    case Hooks{keys, axes, flying, mode, simulate, authority, stuck, removed, auto, speed, restitution, environment, fuel, Nil{}}:
      reset_policy_gate(state, tables,
        Request{input, context, Hooks{keys, axes, flying, mode, simulate, authority, stuck, removed, auto, speed, restitution, environment, fuel, []}, H.NotRequired{}, []}, policy)
    case _: (state, tables, Fail{ResetTravelError{NonCanonicalRequest{1}}})

# Moves exactly once. The neutral supplier is readonly and admits only MISS;
# reuse of LM's post-collision candidate does not claim actual callback ordering
# or any reset hit, damage, portal, auto-jump or context-sensitive block parity.
def travel_with_reset_checked(state: MH.State, tables: L.Tables,
                              request: ResetRequest) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  match request:
    case ResetRequest{input, context, hooks, policy, Nil{}}: reset_hooks_gate(state, tables, input, context, hooks, policy)
    case _: (state, tables, Fail{ResetTravelError{NonCanonicalRequest{0}}})

law reset_supplier_failure_restores_preparation_anchor:
  for world: W.State
  for tables: L.Tables
  for support: SP.State
  for minor: LM.MinorState
  for +work: ResetWork
  for cause: FR.Error
  {reset_supplied(tables, support, minor, work, (world, Fail{cause})) ==
    reset_rollback(world, tables, reset_stage_frame(reset_work_stage(work)), ResetSupplierError{cause}) : MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>}

def reset_supplier_failure_restores_preparation_anchor(world, tables, support, minor, work, cause):
  {==}

law reset_noncanonical_owned_tail_retains_every_child:
  for world: W.State
  for support: SP.State
  for minor: LM.MinorState
  for history: H.State
  for child: MH.State
  for tail: List<&1, MH.State>
  for tables: L.Tables
  for request: Request
  for policy: ResetPolicy
  {reset_canonical_state(MH.State{world, support, minor, history, child <> tail}, tables, request, policy) ==
    (MH.State{world, support, minor, history, child <> tail}, tables, Fail{ResetTravelError{NonCanonicalState{}}}) : MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>}

def reset_noncanonical_owned_tail_retains_every_child(world, support, minor, history, child, tail, tables, request, policy):
  match history:
    case H.State{distance}: {==}

law reset_unrequired_branch_has_no_supplier:
  for world: W.State
  for tables: L.Tables
  for support: SP.State
  for minor: LM.MinorState
  for work: ResetWork
  {reset_requirement(world, tables, support, minor, work, False{}) ==
    reset_apply_history(world, tables, support, minor, work, H.NotRequired{}) : MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>}

def reset_unrequired_branch_has_no_supplier(world, tables, support, minor, work):
  {==}

law reset_finish_failure_restores_preparation_anchor:
  for world: W.State
  for tables: L.Tables
  for support: SP.State
  for minor: LM.MinorState
  for history: H.State
  for +work: ResetWork
  for cause: T.Error
  {reset_finished(world, tables, support, minor, history, work, Fail{cause}) ==
    reset_rollback(world, tables, reset_stage_frame(reset_work_stage(work)), ResetTravelError{FinishError{cause}}) : MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>}

def reset_finish_failure_restores_preparation_anchor(world, tables, support, minor, history, work, cause):
  {==}


# Status-aware dispatcher shares the actual move/supplier/finish and rollback
# helpers. The original neutral dispatcher and its generic laws remain exact.
def ability_reset_apply_history(history_mode:H.Mode,world: W.State, tables: L.Tables, support: SP.State,
                        minor: LM.MinorState, +work: ResetWork, clip: H.Clip) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  reset_history_finished(world, tables, support, minor, work,
    H.movement(history_mode, MH.movement_from(MH.outcome_transition(reset_work_move(work)), clip),
      H.State{frame_history(reset_stage_frame(reset_work_stage(work)))}))


def ability_reset_supplied(history_mode:H.Mode,tables: L.Tables, support: SP.State, minor: LM.MinorState,
                   work: ResetWork, result: W.State & Result<&2, &2, FR.Error, FR.Observation>) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  (world, status) = result
  match status:
    case Fail{cause}: reset_rollback(world, tables, reset_stage_frame(reset_work_stage(work)), ResetSupplierError{cause})
    case Done{+observation}:
      ability_reset_apply_history(history_mode,world, tables, support, minor, reset_with_observation(work, observation), FR.observation_clip(observation))


def ability_reset_requirement(history_mode:H.Mode,world: W.State, tables: L.Tables, support: SP.State,
                      minor: LM.MinorState, +work: ResetWork, required: Bool) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  match required:
    case False{}: ability_reset_apply_history(history_mode,world, tables, support, minor, work, H.NotRequired{})
    case True{}:
      ability_reset_supplied(history_mode,tables, support, minor, work,
        FR.clip_checked(world, reset_ray_request(reset_work_stage(work), MH.outcome_transition(reset_work_move(work)))))


def ability_reset_metadata_checked(history_mode:H.Mode,world: W.State, tables: L.Tables, support: SP.State,
                           minor: LM.MinorState, +work: ResetWork,
                           error: Maybe<&2, H.Error>) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  match error:
    case Some{cause}: reset_rollback(world, tables, reset_stage_frame(reset_work_stage(work)), ResetHistoryError{cause})
    case None{}:
      ability_reset_requirement(history_mode,world, tables, support, minor, work,
        reset_is_required(frame_history(reset_stage_frame(reset_work_stage(work))), MH.outcome_transition(reset_work_move(work))))


def ability_reset_moved(history_mode:H.Mode,+stage: ResetStage,
                result: W.State & L.Tables & SP.State & LM.MinorState & Result<&2, &2, LM.Error, LM.Outcome>) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  (world, tables, support, minor, status) = result
  match status:
    case Fail{cause}: reset_rollback(world, tables, reset_stage_frame(stage), ResetTravelError{MovementError{MH.MoveError{cause}}})
    case Done{+move}:
      ability_reset_metadata_checked(history_mode,world, tables, support, minor, ResetWork{stage, move, None{}, []},
        H.movement_error(MH.movement_from(MH.outcome_transition(move), H.NotRequired{})))


def ability_reset_prepared(history_mode:H.Mode,engine: G.Engine, +frame: Frame, policy: ResetPolicy,
                   result: L.Tables & Result<&2, &2, T.Error, T.Prepared>) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  (tables, status) = result
  match status:
    case Fail{cause}: reset_rollback_taken(tables, frame, ResetTravelError{PreparationError{cause}}, (engine, frame_view(frame)))
    case Done{+value}:
      ability_reset_moved(history_mode,ResetStage{frame, policy, Preparation{value, []}, []},
        LM.move_checked(W.attach(engine, with_body(frame_view(frame), prepared_body(value))), tables,
          frame_support(frame), frame_minor(frame), reset_move_request(frame, value)))


def ability_reset_initial_history(history_mode:H.Mode,engine: G.Engine, tables: L.Tables, +frame: Frame,
                          policy: ResetPolicy, error: Maybe<&2, H.Error>) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  match error:
    case Some{cause}: reset_rollback_taken(tables, frame, ResetHistoryError{cause}, (engine, frame_view(frame)))
    case None{}:
      ability_reset_prepared(history_mode,engine, frame, policy,
        T.prepare_checked(tables, view_body(frame_view(frame)), request_input(frame_request(frame)), request_context(frame_request(frame))))


def ability_reset_extracted(history_mode:H.Mode,tables: L.Tables, support: SP.State, minor: LM.MinorState,
                     +history: H.History, request: Request, policy: ResetPolicy,
                     result: G.Engine & W.View) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  (engine, view) = result
  ability_reset_initial_history(history_mode,engine, tables, Frame{view, support, minor, history, request, []}, policy, H.history_error(history))


def ability_reset_canonical_state(history_mode:H.Mode,state: MH.State, tables: L.Tables, request: Request,
                           policy: ResetPolicy) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  match state:
    case MH.State{world, support, minor, H.State{history}, Nil{}}:
      ability_reset_extracted(history_mode,tables, support, minor, history, request, policy, W.take(world))
    case MH.State{world, support, minor, history, tail}:
      (MH.State{world, support, minor, history, tail}, tables, Fail{ResetTravelError{NonCanonicalState{}}})


def ability_reset_policy_gate(history_mode:H.Mode,state: MH.State, tables: L.Tables, request: Request,
                       policy: ResetPolicy) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  match policy:
    case ResetPolicy{interior, work, profile, Nil{}}:
      ability_reset_canonical_state(history_mode,state, tables, request, ResetPolicy{interior, work, profile, []})
    case _: (state, tables, Fail{ResetTravelError{NonCanonicalRequest{2}}})


def ability_reset_hooks_gate(history_mode:H.Mode,state: MH.State, tables: L.Tables, input: M.Vec3,
                      context: T.Context, hooks: Hooks, policy: ResetPolicy) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  match hooks:
    case Hooks{keys, axes, flying, mode, simulate, authority, stuck, removed, auto, speed, restitution, environment, fuel, Nil{}}:
      ability_reset_policy_gate(history_mode,state, tables,
        Request{input, context, Hooks{keys, axes, flying, mode, simulate, authority, stuck, removed, auto, speed, restitution, environment, fuel, []}, H.NotRequired{}, []}, policy)
    case _: (state, tables, Fail{ResetTravelError{NonCanonicalRequest{1}}})


def ability_travel_with_reset_checked(history_mode:H.Mode,state: MH.State, tables: L.Tables,
                              request: ResetRequest) -> MH.State & L.Tables & Result<&2, &2, ResetError, ResetOutcome>:
  match request:
    case ResetRequest{input, context, hooks, policy, Nil{}}: ability_reset_hooks_gate(history_mode,state, tables, input, context, hooks, policy)
    case _: (state, tables, Fail{ResetTravelError{NonCanonicalRequest{0}}})

