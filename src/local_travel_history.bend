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
