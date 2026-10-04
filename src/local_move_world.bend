import Base
import ./client_world.bend as W
import ./local_collision_world.bend as E
import ./local_collision.bend as LC
import ./support_world.bend as SW
import ./support.bend as SP
import ./locomotion.bend as L
import ./movement.bend as M
import ./geometry.bend as A
import ./f64.bend as F
import ./game.bend as G

# Explicit resolved admission: no inference from old support/crouch caches.
type Context is Data:
  Context{edge: LC.EdgeContext, minor: LC.MinorInput,
          can_simulate: Bool, local_authoritative: Bool,
          stuck_multiplier: M.Vec3, removed: Bool, auto_jump_enabled: Bool,
          unit_block_speed: Bool, zero_restitution: Bool}

type MinorState is Data:
  MinorState{minor: Bool}

type Request is Data:
  Request{body: M.Body, requested: M.Vec3, context: Context,
          environment: E.Environment, fuel: Nat, tail: List<&2, Request>}

# Immutable evidence, not another authoritative player body.
type BodySnapshot is Data:
  BodySnapshot{body: M.Body, tail: List<&2, BodySnapshot>}

type Motion is Data:
  Motion{transition: M.Transition, tail: List<&2, Motion>}

type Outcome is Data:
  Outcome{motion: Motion, backoff: E.Observation,
          pre_restitution: BodySnapshot, minor_hook: Maybe<&2, LC.MinorObservation>,
          tail: List<&2, Outcome>}

type Error is Data:
  BodyMismatch{}
  ContextDenied{field: U32}
  HookAdmission{cause: LC.Error}
  BackoffError{cause: E.Error}
  CollisionError{cause: String}
  SupportError{cause: SW.Error}
  MinorError{cause: LC.Error}
  OutsideInterior{}
  InvalidSweep{}

type Frame is Data:
  Frame{view: W.View, support: SP.State, minor: MinorState,
        request: Request, tail: List<&2, Frame>}

type Prepared is Data:
  Prepared{frame: Frame, motion: Motion, backoff: E.Observation,
           pre_restitution: BodySnapshot, support: SP.State,
           tail: List<&2, Prepared>}

def error_text(error: Error) -> String:
  match error:
    case BodyMismatch{}: "local-move-body-mismatch"
    case ContextDenied{field}: "local-move-context:" ++ U32.show(field)
    case HookAdmission{cause}: "local-move-hook-admission"
    case BackoffError{cause}: E.error_text(cause)
    case CollisionError{cause}: cause
    case SupportError{cause}: SW.error_text(cause)
    case MinorError{cause}: "local-move-minor-error"
    case OutsideInterior{}: "local-move-sweep-outside-interior"
    case InvalidSweep{}: "local-move-invalid-sweep"

def frame_view(frame: Frame) -> W.View:
  Frame{view, support, minor, request, tail} = frame
  view

def frame_support(frame: Frame) -> SP.State:
  Frame{view, support, minor, request, tail} = frame
  support

def frame_minor(frame: Frame) -> MinorState:
  Frame{view, support, minor, request, tail} = frame
  minor

def frame_request(frame: Frame) -> Request:
  Frame{view, support, minor, request, tail} = frame
  request

def request_body(request: Request) -> M.Body:
  Request{body, requested, context, environment, fuel, tail} = request
  body

def request_context(request: Request) -> Context:
  Request{body, requested, context, environment, fuel, tail} = request
  context

def request_environment(request: Request) -> E.Environment:
  Request{body, requested, context, environment, fuel, tail} = request
  environment

def context_edge(context: Context) -> LC.EdgeContext:
  Context{edge, minor, simulate, authority, stuck, removed, auto, unit_speed, restitution} = context
  edge

def context_minor(context: Context) -> LC.MinorInput:
  Context{edge, minor, simulate, authority, stuck, removed, auto, unit_speed, restitution} = context
  minor

def context_mode(context: Context) -> LC.Mode:
  Context{LC.EdgeContext{maximum, fall, flying, keys, mover, mode}, minor, simulate, authority, stuck, removed, auto, unit_speed, restitution} = context
  mode

def context_maximum(context: Context) -> F32:
  Context{LC.EdgeContext{maximum, fall, flying, keys, mover, mode}, minor, simulate, authority, stuck, removed, auto, unit_speed, restitution} = context
  maximum

def snapshot_body(snapshot: BodySnapshot) -> M.Body:
  BodySnapshot{body, tail} = snapshot
  body

def motion_transition(motion: Motion) -> M.Transition:
  Motion{transition, tail} = motion
  transition

def transition_body(transition: M.Transition) -> M.Body:
  M.Transition{body, displacement, stepped, applied} = transition
  body

def transition_displacement(transition: M.Transition) -> M.Vec3:
  M.Transition{body, displacement, stepped, applied} = transition
  displacement

def body_box(body: M.Body) -> A.AABB:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = body
  box

def body_velocity(body: M.Body) -> M.Vec3:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = body
  velocity

def body_horizontal(body: M.Body) -> Bool:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = body
  horizontal

def with_velocity(body: M.Body, velocity: M.Vec3) -> M.Body:
  M.Body{position, box, old, width, height, ground, horizontal, vertical, below} = body
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below}

def with_body(view: W.View, body: M.Body) -> W.View:
  W.View{old, yaw, pitch, palette, region, cache} = view
  W.View{body, yaw, pitch, palette, region, cache}

def installed(body: M.Body, result: G.Engine & W.View) -> W.State:
  (engine, view) = result
  W.attach(engine, with_body(view, body))

def install_body(world: W.State, body: M.Body) -> W.State:
  installed(body, W.take(world))

def rollback_taken(tables: L.Tables, +frame: Frame, cause: Error,
                   result: G.Engine & W.View) -> W.State & L.Tables & SP.State & MinorState & Result<&2, &2, Error, Outcome>:
  (engine, current) = result
  (W.attach(engine, frame_view(frame)), tables, frame_support(frame), frame_minor(frame), Fail{cause})

def rollback(world: W.State, tables: L.Tables, frame: Frame, cause: Error) -> W.State & L.Tables & SP.State & MinorState & Result<&2, &2, Error, Outcome>:
  rollback_taken(tables, frame, cause, W.take(world))

def first_error(first: Maybe<&2, Error>, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match first:
    case Some{error}: Some{error}
    case None{}: rest

def denied(field: U32, accepted: Bool) -> Maybe<&2, Error>:
  match accepted:
    case True{}: None{}
    case False{}: Some{ContextDenied{field}}

def hook_error(error: Maybe<&2, LC.Error>) -> Maybe<&2, Error>:
  match error:
    case None{}: None{}
    case Some{cause}: Some{HookAdmission{cause}}

def neutral_error(context: Context) -> Maybe<&2, Error>:
  match context:
    case Context{edge, minor, simulate, authority, stuck, removed, auto, unit_speed, restitution}:
      first_error(denied(0, simulate), first_error(denied(1, authority),
        first_error(denied(2, M.Vec3.numerically_equal(stuck, M.Vec3.zero())),
        first_error(denied(3, Bool.not(removed)), first_error(denied(4, Bool.not(auto)),
        first_error(denied(5, unit_speed), denied(6, restitution)))))))

def context_error(+body: M.Body, +requested: M.Vec3, +context: Context) -> Maybe<&2, Error>:
  first_error(neutral_error(context), first_error(hook_error(LC.edge_error(body, requested, context_edge(context))),
    hook_error(LC.minor_error(body, context_minor(context), requested, context_mode(context)))))

# Conservative no-read admission for initial/step/entity sweeps.
# The downward margin encloses the actual negative step-query epsilon.
# Support slabs are checked separately from the resolved pre-restitution Body.
def collision_sweep(body: M.Body, corrected: M.Vec3, maximum: F32) -> A.AABB:
  M.expand_towards(M.initial_entity_query(body_box(body), corrected, maximum), M.Vec3{M.zero(), F.neg(M.one()), M.zero()})

def sweep_error(+sweep: A.AABB, environment: E.Environment) -> Maybe<&2, Error>:
  W.choose(Maybe<&2, Error>, None{}, Some{InvalidSweep{}},
    Maybe.is_none(&2, U32, A.AABB.invalid_field(sweep)) && W.query_ordered(sweep))

# Separate finite validity from the declared border interior containment.
def sweep_gate(error: Maybe<&2, Error>, admitted: Bool) -> Maybe<&2, Error>:
  match error:
    case Some{cause}: Some{cause}
    case None{}: W.choose(Maybe<&2, Error>, None{}, Some{OutsideInterior{}}, admitted)

def checked_sweep(+body: M.Body, +corrected: M.Vec3, maximum: F32, +environment: E.Environment) -> Maybe<&2, Error>:
  +sweep = collision_sweep(body, corrected, maximum)
  sweep_gate(sweep_error(sweep, environment), E.query_admitted(sweep, environment))

def pre_transition(transition: M.Transition, velocity: M.Vec3) -> M.Transition:
  match transition:
    case M.Transition{body, delta, stepped, applied}: M.Transition{with_velocity(body, velocity), delta, stepped, applied}

def committed(world: W.State, tables: L.Tables, prepared: Prepared,
              minor: MinorState, observation: Maybe<&2, LC.MinorObservation>) -> W.State & L.Tables & SP.State & MinorState & Result<&2, &2, Error, Outcome>:
  match prepared:
    case Prepared{frame, +motion, backoff, before, support, tail}:
      (install_body(world, transition_body(motion_transition(motion))), tables, support, minor,
        Done{Outcome{motion, backoff, before, observation, []}})

def prepared_frame(prepared: Prepared) -> Frame:
  Prepared{frame, motion, backoff, before, support, tail} = prepared
  frame

def minor_finished(world: W.State, +prepared: Prepared,
                   result: L.Tables & Result<&2, &2, LC.Error, LC.MinorObservation>) -> W.State & L.Tables & SP.State & MinorState & Result<&2, &2, Error, Outcome>:
  (tables, status) = result
  match status:
    case Fail{error}: rollback(world, tables, prepared_frame(prepared), MinorError{error})
    case Done{+observed}:
      LC.MinorObservation{minor, rotated_x, rotated_z, input_squared, movement_squared, angle} = observed
      committed(world, tables, prepared, MinorState{minor}, Some{observed})

def minor_gate(horizontal: Bool, world: W.State, tables: L.Tables, +prepared: Prepared) -> W.State & L.Tables & SP.State & MinorState & Result<&2, &2, Error, Outcome>:
  match horizontal:
    case False{}: committed(world, tables, prepared, MinorState{False{}}, None{})
    case True{}:
      Prepared{+frame, +motion, backoff, +before, support, tail} = prepared
      +context = request_context(frame_request(frame))
      minor_finished(world, prepared, LC.minor_checked(tables, snapshot_body(before), context_minor(context), transition_displacement(motion_transition(motion)), context_mode(context)))

def support_finished(tables: L.Tables, frame: Frame, +motion: Motion,
                     backoff: E.Observation, +before: BodySnapshot,
                     result: W.State & Result<&2, &2, SW.Error, SP.State>) -> W.State & L.Tables & SP.State & MinorState & Result<&2, &2, Error, Outcome>:
  (world, status) = result
  match status:
    case Fail{error}: rollback(world, tables, frame, SupportError{error})
    case Done{support}:
      minor_gate(body_horizontal(snapshot_body(before)), world, tables, Prepared{frame, motion, backoff, before, support, []})

def support_query_result(grounded: Bool, +environment: E.Environment,
                         result: Result<&2, &2, SP.Error, SP.Queries>) -> Maybe<&2, Error>:
  match grounded result:
    case _ Fail{cause}: Some{SupportError{SW.SupportError{cause}}}
    case False{} Done{query}: None{}
    case True{} Done{SP.Queries{primary, None{}}}:
      W.choose(Maybe<&2, Error>, None{}, Some{OutsideInterior{}}, E.query_admitted(primary, environment))
    case True{} Done{SP.Queries{primary, Some{fallback}}}:
      W.choose(Maybe<&2, Error>, None{}, Some{OutsideInterior{}}, E.query_admitted(primary, environment) && E.query_admitted(fallback, environment))

def support_query_error(body: M.Body, delta: M.Vec3, environment: E.Environment) -> Maybe<&2, Error>:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = body
  support_query_result(ground, environment, SP.queries_checked(box, Some{delta}))

def support_gate(error: Maybe<&2, Error>, world: W.State, tables: L.Tables,
                 +frame: Frame, motion: Motion, backoff: E.Observation,
                 +before: BodySnapshot, phase: M.Transition) -> W.State & L.Tables & SP.State & MinorState & Result<&2, &2, Error, Outcome>:
  match error:
    case Some{cause}: rollback(world, tables, frame, cause)
    case None{}:
      support_finished(tables, frame, motion, backoff, before,
        SW.update_checked(install_body(world, snapshot_body(before)), frame_support(frame), phase))

def moved(tables: L.Tables, +frame: Frame, backoff: E.Observation,
          result: W.State & Result<&2, &2, String, M.Transition>) -> W.State & L.Tables & SP.State & MinorState & Result<&2, &2, Error, Outcome>:
  (world, status) = result
  match status:
    case Fail{error}: rollback(world, tables, frame, CollisionError{error})
    case Done{+transition}:
      +phase = pre_transition(transition, body_velocity(request_body(frame_request(frame))))
      +before : BodySnapshot = BodySnapshot{transition_body(phase), []}
      support_gate(support_query_error(snapshot_body(before), transition_displacement(phase), request_environment(frame_request(frame))), world, tables, frame, Motion{transition, []}, backoff, before, phase)

def backoff_requested(observation: E.Observation) -> M.Vec3:
  E.Observation{corrected, queries} = observation
  corrected

def collision_gate(error: Maybe<&2, Error>, world: W.State, tables: L.Tables,
                   +frame: Frame, +backoff: E.Observation) -> W.State & L.Tables & SP.State & MinorState & Result<&2, &2, Error, Outcome>:
  match error:
    case Some{cause}: rollback(world, tables, frame, cause)
    case None{}:
      +context = request_context(frame_request(frame))
      moved(tables, frame, backoff, W.move(world, backoff_requested(backoff), context_maximum(context)))

def backed_off(tables: L.Tables, +frame: Frame,
               result: W.State & Result<&2, &2, E.Error, E.Observation>) -> W.State & L.Tables & SP.State & MinorState & Result<&2, &2, Error, Outcome>:
  (world, status) = result
  match status:
    case Fail{error}: rollback(world, tables, frame, BackoffError{error})
    case Done{+backoff}:
      E.Observation{+corrected, queries} = backoff
      +request = frame_request(frame)
      collision_gate(checked_sweep(request_body(request), corrected, context_maximum(request_context(request)), request_environment(request)), world, tables, frame, backoff)

def context_admitted(world: W.State, tables: L.Tables, +frame: Frame,
                     request: Request) -> W.State & L.Tables & SP.State & MinorState & Result<&2, &2, Error, Outcome>:
  match request:
    case Request{body, requested, context, environment, fuel, tail}:
      backed_off(tables, frame, E.backoff_checked(world, E.Request{body, requested, context_edge(context), environment, fuel, []}))

def request_error(request: Request) -> Maybe<&2, Error>:
  match request:
    case Request{body, requested, context, environment, fuel, tail}: context_error(body, requested, context)

def context_gate(error: Maybe<&2, Error>, world: W.State, tables: L.Tables,
                 +frame: Frame) -> W.State & L.Tables & SP.State & MinorState & Result<&2, &2, Error, Outcome>:
  match error:
    case Some{cause}: rollback(world, tables, frame, cause)
    case None{}: context_admitted(world, tables, frame, frame_request(frame))

def authority_gate(equal: Bool, world: W.State, tables: L.Tables, +frame: Frame) -> W.State & L.Tables & SP.State & MinorState & Result<&2, &2, Error, Outcome>:
  match equal:
    case False{}: rollback(world, tables, frame, BodyMismatch{})
    case True{}:
      context_gate(request_error(frame_request(frame)), world, tables, frame)

def extracted(tables: L.Tables, support: SP.State, minor: MinorState,
              +request: Request, result: G.Engine & W.View) -> W.State & L.Tables & SP.State & MinorState & Result<&2, &2, Error, Outcome>:
  (engine, +view) = result
  authority_gate(E.same_body(E.view_body(view), request_body(request)), W.attach(engine, view), tables, Frame{view, support, minor, request, []})

def move_checked(world: W.State, tables: L.Tables, support: SP.State,
                 minor: MinorState, request: Request) -> W.State & L.Tables & SP.State & MinorState & Result<&2, &2, Error, Outcome>:
  extracted(tables, support, minor, request, W.take(world))

law restored_view_support_and_minor_on_failure:
  for tables: L.Tables
  for +frame: Frame
  for +cause: Error
  for engine: G.Engine
  for current: W.View
  {rollback_taken(tables, frame, cause, (engine, current)) == (W.attach(engine, frame_view(frame)), tables, frame_support(frame), frame_minor(frame), Fail{cause}) : W.State & L.Tables & SP.State & MinorState & Result<&2, &2, Error, Outcome>}

def restored_view_support_and_minor_on_failure(tables, frame, cause, engine, current):
  {==}

law pre_restitution_retains_original_velocity:
  for +velocity: M.Vec3
  for position: M.Vec3
  for box: A.AABB
  for ignored: M.Vec3
  for width: F32
  for height: F32
  for ground: Bool
  for horizontal: Bool
  for vertical: Bool
  for below: Bool
  {body_velocity(with_velocity(M.Body{position, box, ignored, width, height, ground, horizontal, vertical, below}, velocity)) == velocity : M.Vec3}

def pre_restitution_retains_original_velocity(velocity, position, box, ignored, width, height, ground, horizontal, vertical, below):
  {==}

law denied_context_retains_tables_and_world:
  for world: W.State
  for tables: L.Tables
  for frame: Frame
  for +cause: Error
  {context_gate(Some{cause}, world, tables, frame) == rollback(world, tables, frame, cause) : W.State & L.Tables & SP.State & MinorState & Result<&2, &2, Error, Outcome>}

def denied_context_retains_tables_and_world(world, tables, frame, cause):
  {==}
