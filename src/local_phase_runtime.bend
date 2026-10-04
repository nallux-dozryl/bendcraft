import Base
import ./player_block_inside_stuck.bend as Inside
import ./runtime_block_inside.bend as RBI
import ./player_block_inside_sweep_world.bend as BIW
import ./local_move_history.bend as MH
import ./local_move_world.bend as LM
import ./local_travel_history.bend as TH
import ./local_input.bend as LI
import ./player_runtime.bend as PR
import ./player_tick.bend as P
import ./player_pose.bend as Pose
import ./player_pose_world.bend as PPW
import ./entity_common_tick.bend as ECT
import ./player_rotation_tick.bend as Rotation
import ./player_controls.bend as PC
import ./client_controls.bend as CC
import ./player_input.bend as PI
import ./player_look.bend as PL
import ./local_collision.bend as LC
import ./local_collision_world.bend as E
import ./player_fall_history.bend as H
import ./support.bend as SP
import ./travel.bend as T
import ./movement.bend as M
import ./locomotion.bend as L
import ./client_world.bend as W
import ./game.bend as G
import ./core.bend as C
import ./registry.bend as B
import ./f64.bend as F
import ./geometry.bend as A
import ./schedule.bend as Q
import ./mouse_input.bend as MI

# CheckedNotRequired neutral local phase. MH owns the ONLY world/Body/support/
# minor/history. This boxed header owns all other stable local metadata.
type Metadata is Data:
  Metadata{local: LI.State, player: PR.Metadata, sprinting: Bool,
    pose: Pose.State, controls: PC.Controller, entity: ECT.Metadata,
    receiver: Inside.Receiver, last_error: Maybe<&2, String>, tail: List<&2, Metadata>}

type State is Type:
  State{motion: MH.State, tables: L.Tables, metadata: Metadata,
    tail: List<&1, State>}

# This is conditional lifecycle evidence, not a whole-tick service detector.
# Ticking particles, interpolation and unimplemented inherited callbacks remain
# excluded. The scheduler context and direct local admission are distinct.
type Lifecycle is Data:
  NeutralDryLoadedNoParticles{}
  UnsupportedLifecycle{field: U32}

type ControlFacts is Data:
  ControlFacts{food_level: U32, abilities: LI.Abilities,
    mobility_restricted: Bool, sprint_window: U32, mode: LI.Mode}

# Source observations at the post-sprint/pre-input boundary. No Body, ground
# boolean, degree angles, keys, history or caller fit/clip result is supplied.
# This does not implement an owned attribute-modifier subsystem.
type ApplyFacts is Data:
  ApplyFacts{ground: T.GroundSample, attributes: T.Attributes,
    maximum_step: F32, sprinting: Bool, no_gravity: Bool,
    discard_friction: Bool, travel_mode: T.Mode, jump_strength: F.F64,
    jump_factor: F32, affected_by_fluids: Bool, tick_mode: P.Mode,
    sneaking_speed: F.F64}

type Request is Data:
  Request{lifecycle: Lifecycle, common: ECT.Context,
    control: ControlFacts, apply: ApplyFacts, environment: E.Environment,
    control_fuel: Nat, movement_fuel: Nat, rotation_fuel: Nat,
    pose_fuel: Nat, tail: List<&2, Request>}

# Outcomes expose immutable query/phase observations, never a persistent Body.
type Observation is Data:
  Observation{early_queries: List<&2, PPW.QueryRecord>,
    sprint_updates: List<&2, Bool>, jump_attempted: Bool, jumped: Bool,
    late_queries: List<&2, PPW.QueryRecord>, eye_position: M.Vec3,
    tail: List<&2, Observation>}

type Error is Data:
  NonCanonicalState{field: U32}
  NonCanonicalRequest{}
  LifecycleError{field: U32}
  EntityError{cause: ECT.Error}
  ControllerError{cause: PC.Error}
  PoseError{cause: Pose.Error}
  UnsupportedStablePose{}
  ControlWorldError{cause: E.Error}
  ControlBudget{}
  InputError{cause: LI.Error}
  SprintSetterMismatch{}
  TravelError{cause: TH.Error}
  FinishError{cause: P.Error}
  BlockInsideError{cause: RBI.Error}
  RotationError{cause: Rotation.Error}
  PoseWorldError{cause: PPW.Error}
  ViewError{reason: String}

# Complete rollback evidence has no engine/table owners. It is anchored after
# committed scheduled Core/commonTick work, or at direct local entry.
type Frame is Data:
  Frame{view: W.View, support: SP.State, minor: LM.MinorState,
    history: H.History, metadata: Metadata, request: Request,
    tail: List<&2, Frame>}

type Fits is Data:
  Fits{standing: Bool, crouching: Bool, records: List<&2, PPW.QueryRecord>}

type Work is Data:
  Work{frame: Frame, metadata: Metadata, early: List<&2, PPW.QueryRecord>,
    updates: List<&2, Bool>, prepared: P.PreTravel, context: P.Context,
    tail: List<&2, Work>}

def frame_view(frame: Frame) -> W.View:
  Frame{view, support, minor, history, metadata, request, tail} = frame
  view

def frame_metadata(frame: Frame) -> Metadata:
  Frame{view, support, minor, history, metadata, request, tail} = frame
  metadata

def frame_request(frame: Frame) -> Request:
  Frame{view, support, minor, history, metadata, request, tail} = frame
  request

def frame_support(frame: Frame) -> SP.State:
  Frame{view, support, minor, history, metadata, request, tail} = frame
  support

def frame_minor(frame: Frame) -> LM.MinorState:
  Frame{view, support, minor, history, metadata, request, tail} = frame
  minor

def frame_history(frame: Frame) -> H.History:
  Frame{view, support, minor, history, metadata, request, tail} = frame
  history

def local(metadata: Metadata) -> LI.State:
  Metadata{local, player, sprinting, pose, controls, entity, receiver, error, tail} = metadata
  local

def player(metadata: Metadata) -> PR.Metadata:
  Metadata{local, player, sprinting, pose, controls, entity, receiver, error, tail} = metadata
  player

def sprinting(metadata: Metadata) -> Bool:
  Metadata{local, player, sprinting, pose, controls, entity, receiver, error, tail} = metadata
  sprinting

def pose(metadata: Metadata) -> Pose.State:
  Metadata{local, player, sprinting, pose, controls, entity, receiver, error, tail} = metadata
  pose

def controls(metadata: Metadata) -> PC.Controller:
  Metadata{local, player, sprinting, pose, controls, entity, receiver, error, tail} = metadata
  controls

def entity(metadata: Metadata) -> ECT.Metadata:
  Metadata{local, player, sprinting, pose, controls, entity, receiver, error, tail} = metadata
  entity

def receiver(metadata: Metadata) -> Inside.Receiver:
  Metadata{local, player, sprinting, pose, controls, entity, receiver, error, tail} = metadata
  receiver

def with_receiver(metadata: Metadata, value: Inside.Receiver) -> Metadata:
  Metadata{local, player, sprinting, pose, controls, entity, previous, error, tail} = metadata
  Metadata{local, player, sprinting, pose, controls, entity, value, error, tail}

def with_controls(metadata: Metadata, controls: PC.Controller) -> Metadata:
  Metadata{local, player, sprinting, pose, old, entity, receiver, error, tail} = metadata
  Metadata{local, player, sprinting, pose, controls, entity, receiver, error, tail}

def with_entity(metadata: Metadata, entity: ECT.Metadata) -> Metadata:
  Metadata{local, player, sprinting, pose, controls, old, receiver, error, tail} = metadata
  Metadata{local, player, sprinting, pose, controls, entity, receiver, error, tail}

def with_local(metadata: Metadata, local: LI.State, sprinting: Bool) -> Metadata:
  Metadata{old, player, previous_sprint, pose, controls, entity, receiver, error, tail} = metadata
  Metadata{local, player, sprinting, pose, controls, entity, receiver, error, tail}

def with_player(metadata: Metadata, player: PR.Metadata) -> Metadata:
  Metadata{local, old, sprinting, pose, controls, entity, receiver, error, tail} = metadata
  Metadata{local, player, sprinting, pose, controls, entity, receiver, error, tail}

def with_pose(metadata: Metadata, pose: Pose.State) -> Metadata:
  Metadata{local, player, sprinting, old, controls, entity, receiver, error, tail} = metadata
  Metadata{local, player, sprinting, pose, controls, entity, receiver, error, tail}

def with_look(controls: PC.Controller, look: PL.State) -> PC.Controller:
  PC.Controller{buttons, old, mouse, options} = controls
  PC.Controller{buttons, look, mouse, options}

def view_body(view: W.View) -> M.Body:
  W.View{body, yaw, pitch, palette, region, cache} = view
  body

def body_position(body: M.Body) -> M.Vec3:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = body
  position

def with_body(view: W.View, body: M.Body) -> W.View:
  W.View{old, yaw, pitch, palette, region, cache} = view
  W.View{body, yaw, pitch, palette, region, cache}

def yaw(look: PL.State) -> F32:
  PL.State{yaw, pitch, old_yaw, old_pitch} = look
  yaw

def pitch(look: PL.State) -> F32:
  PL.State{yaw, pitch, old_yaw, old_pitch} = look
  pitch

def keys(local: LI.State) -> PI.Buttons:
  LI.State{keys, movement, trigger, crouching, x, y, xo, yo} = local
  keys

def shift(keys: PI.Buttons) -> Bool:
  PI.Buttons{forward, back, left, right, jump, shift, sprint} = keys
  shift

def processed_input(prepared: P.PreTravel) -> PI.Vector:
  P.PreTravel{P.State{body, P.Input{x, y, z}, jump, delay, trigger, sync, speed, head}, input, attempted, jumped} = prepared
  PI.Vector{x, z}

def prepared_input(prepared: P.PreTravel) -> M.Vec3:
  P.PreTravel{player, input, attempted, jumped} = prepared
  input

def prepared_body(prepared: P.PreTravel) -> M.Body:
  P.PreTravel{P.State{body, input, jump, delay, trigger, sync, speed, head}, vector, attempted, jumped} = prepared
  body

def first(first: Maybe<&2, Error>, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match first:
    case Some{cause}: Some{cause}
    case None{}: rest

def pose_error(error: Maybe<&2, Pose.Error>) -> Maybe<&2, Error>:
  match error:
    case None{}: None{}
    case Some{cause}: Some{PoseError{cause}}

def controller_error(error: Maybe<&2, PC.Error>) -> Maybe<&2, Error>:
  match error:
    case None{}: None{}
    case Some{cause}: Some{ControllerError{cause}}

def entity_error(error: Maybe<&2, ECT.Error>) -> Maybe<&2, Error>:
  match error:
    case None{}: None{}
    case Some{cause}: Some{EntityError{cause}}

def input_error(error: Maybe<&2, LI.Error>) -> Maybe<&2, Error>:
  match error:
    case None{}: None{}
    case Some{cause}: Some{InputError{cause}}

def request_lifecycle(request: Request) -> Lifecycle:
  Request{lifecycle, common, control, apply, environment, cf, mf, rf, pf, tail} = request
  lifecycle

def request_common(request: Request) -> ECT.Context:
  Request{lifecycle, common, control, apply, environment, cf, mf, rf, pf, tail} = request
  common

def request_control(request: Request) -> ControlFacts:
  Request{lifecycle, common, control, apply, environment, cf, mf, rf, pf, tail} = request
  control

def request_apply(request: Request) -> ApplyFacts:
  Request{lifecycle, common, control, apply, environment, cf, mf, rf, pf, tail} = request
  apply

def request_control_fuel(request: Request) -> Nat:
  Request{lifecycle, common, control, apply, environment, cf, mf, rf, pf, tail} = request
  cf

def request_movement_fuel(request: Request) -> Nat:
  Request{lifecycle, common, control, apply, environment, cf, mf, rf, pf, tail} = request
  mf

def request_pose_fuel(request: Request) -> Nat:
  Request{lifecycle, common, control, apply, environment, cf, mf, rf, pf, tail} = request
  pf

def entity_count(metadata: ECT.Metadata) -> U32:
  ECT.Metadata{o, old, invulnerable, count} = metadata
  count

def entity_old_position(metadata: ECT.Metadata) -> M.Vec3:
  ECT.Metadata{interpolation, old, invulnerable, count} = metadata
  old

def lifecycle_error(lifecycle: Lifecycle) -> Maybe<&2, Error>:
  match lifecycle:
    case NeutralDryLoadedNoParticles{}: None{}
    case UnsupportedLifecycle{field}: Some{LifecycleError{field}}

def control_facts_error(facts: ControlFacts) -> Maybe<&2, Error>:
  ControlFacts{food, +abilities, mobility, window, +mode} = facts
  input_error(LI.first_error(LI.mode_error(mode), LI.abilities_error(abilities)))

def stable_pose(state: Pose.State) -> Bool:
  match state:
    case Pose.State{Pose.Standing{}, eye, tail}: True{}
    case Pose.State{Pose.Crouching{}, eye, tail}: True{}
    case _: False{}

def stable_error(valid: Bool) -> Maybe<&2, Error>:
  match valid:
    case True{}: None{}
    case False{}: Some{UnsupportedStablePose{}}

def frame_error(+frame: Frame) -> Maybe<&2, Error>:
  +metadata = frame_metadata(frame)
  first(lifecycle_error(request_lifecycle(frame_request(frame))), first(control_facts_error(request_control(frame_request(frame))), first(controller_error(PC.controller_error(controls(metadata))),
    first(entity_error(ECT.metadata_error(entity(metadata))),
    first(input_error(LI.state_error(local(metadata))),
    first(stable_error(stable_pose(pose(metadata))),
      pose_error(Pose.state_error(pose(metadata), view_body(frame_view(frame))))))))))

def rollback_taken(tables: L.Tables, +frame: Frame, cause: Error,
                   result: G.Engine & W.View) -> State & Result<&2, &2, Error, Observation>:
  (engine, discarded) = result
  (State{MH.State{W.attach(engine, frame_view(frame)), frame_support(frame), frame_minor(frame), H.State{frame_history(frame)}, []},
    tables, frame_metadata(frame), []}, Fail{cause})

def rollback(motion: MH.State, tables: L.Tables, frame: Frame, cause: Error) -> State & Result<&2, &2, Error, Observation>:
  MH.State{world, support, minor, history, tail} = motion
  rollback_taken(tables, frame, cause, W.take(world))

def rollback_world(world: W.State, tables: L.Tables, frame: Frame, cause: Error) -> State & Result<&2, &2, Error, Observation>:
  rollback_taken(tables, frame, cause, W.take(world))

def request_environment(request: Request) -> E.Environment:
  Request{lifecycle, common, control, apply, environment, cf, mf, rf, pf, tail} = request
  environment

def request_rotation_fuel(request: Request) -> Nat:
  Request{lifecycle, common, control, apply, environment, cf, mf, rf, pf, tail} = request
  rf

def pose_context(local: LI.State) -> Pose.Context:
  Pose.Context{Pose.Flags{False{}, False{}, False{}, False{}, shift(keys(local)), False{}, False{}, False{}}, 1.0, False{}, Pose.AdultUnscaledClient{}}

def work_frame(work: Work) -> Frame:
  Work{frame, metadata, early, updates, prepared, context, tail} = work
  frame

def work_metadata(work: Work) -> Metadata:
  Work{frame, metadata, early, updates, prepared, context, tail} = work
  metadata

def work_prepared(work: Work) -> P.PreTravel:
  Work{frame, metadata, early, updates, prepared, context, tail} = work
  prepared

def work_context(work: Work) -> P.Context:
  Work{frame, metadata, early, updates, prepared, context, tail} = work
  context

def late_queries(observation: PPW.Observation) -> List<&2, PPW.QueryRecord>:
  PPW.Observation{transition, queries, tail} = observation
  queries

def decision_sprinting(decision: LI.Controls) -> Bool:
  LI.Controls{local, sprinting, updates} = decision
  sprinting

def decision_updates(decision: LI.Controls) -> List<&2, Bool>:
  LI.Controls{local, sprinting, updates} = decision
  updates

def eye_request(body: M.Body, +metadata: Metadata) -> Pose.Request:
  Pose.Request{pose(metadata), body, pose_context(local(metadata)), []}

def published(motion: MH.State, tables: L.Tables, metadata: Metadata,
              work: Work, late: List<&2, PPW.QueryRecord>, eye: M.Vec3) -> State & Result<&2, &2, Error, Observation>:
  Work{frame, old, early, updates, P.PreTravel{player, input, attempted, jumped}, context, tail} = work
  (State{motion, tables, metadata, []}, Done{Observation{early, updates, attempted, jumped, late, eye, []}})

def eye_finished(motion: MH.State, tables: L.Tables, metadata: Metadata, +work: Work,
                 late: List<&2, PPW.QueryRecord>, result: Result<&2, &2, Pose.Error, M.Vec3>) -> State & Result<&2, &2, Error, Observation>:
  match result:
    case Fail{cause}: rollback(motion, tables, work_frame(work), PoseError{cause})
    case Done{eye}: published(motion, tables, metadata, work, late, eye)

def view_finished(tables: L.Tables, support: SP.State, minor: LM.MinorState,
                  history: H.State, +metadata: Metadata, +work: Work,
                  late: List<&2, PPW.QueryRecord>, result: W.State & Result<&2, &2, String, Unit>) -> State & Result<&2, &2, Error, Observation>:
  (world, status) = result
  match status:
    case Fail{reason}: rollback_world(world, tables, work_frame(work), ViewError{reason})
    case Done{unit}:
      W.paired(G.Engine, W.View, State & Result<&2, &2, Error, Observation>, W.take(world),
        engine => +view => eye_finished(MH.State{W.attach(engine, view), support, minor, history, []}, tables, metadata, work, late,
          Pose.eye_position_checked(eye_request(view_body(view), metadata))))

def pose_selected(tables: L.Tables, support: SP.State, minor: LM.MinorState,
                  history: H.State, +metadata: Metadata, +work: Work,
                  +observation: PPW.Observation, world: W.State, accepted: Bool) -> State & Result<&2, &2, Error, Observation>:
  match accepted:
    case False{}: rollback_world(world, tables, work_frame(work), UnsupportedStablePose{})
    case True{}:
      +angles = PR.look(controls(metadata))
      view_finished(tables, support, minor, history, metadata, work, late_queries(observation),
        W.look(world, PL.mul(yaw(angles), PL.float_bits(1016003125)), PL.mul(pitch(angles), PL.float_bits(1016003125))))

def pose_finished(tables: L.Tables, support: SP.State, minor: LM.MinorState,
                  history: H.State, +metadata: Metadata, +work: Work,
                  result: W.State & Pose.State & Result<&2, &2, PPW.Error, PPW.Observation>) -> State & Result<&2, &2, Error, Observation>:
  (world, +pose, status) = result
  match status:
    case Fail{cause}: rollback_world(world, tables, work_frame(work), PoseWorldError{cause})
    case Done{observation}: pose_selected(tables, support, minor, history, with_pose(metadata, pose), work, observation, world, stable_pose(pose))

def late_pose(motion: MH.State, tables: L.Tables, +metadata: Metadata, +work: Work) -> State & Result<&2, &2, Error, Observation>:
  MH.State{world, support, minor, history, tail} = motion
  Work{+frame, old, early, updates, prepared, context, tail} = work
  pose_finished(tables, support, minor, history, metadata, work,
    PPW.update_checked(world, pose(metadata), PPW.Request{pose_context(local(metadata)), request_environment(frame_request(frame)), request_pose_fuel(frame_request(frame)), []}))

def rotation_finished(motion: MH.State, tables: L.Tables, +metadata: Metadata,
                      +work: Work, result: Rotation.State & Result<&2, &2, Rotation.Error, Unit>) -> State & Result<&2, &2, Error, Observation>:
  (Rotation.State{look, count}, status) = result
  match status:
    case Fail{cause}: rollback(motion, tables, work_frame(work), RotationError{cause})
    case Done{unit}: late_pose(motion, tables, with_controls(metadata, with_look(controls(metadata), look)), work)

def install_finished_taken(body:M.Body,support:SP.State,minor:LM.MinorState,history:H.State,
                           tail:List<&1,MH.State>,result:G.Engine & W.View) -> MH.State:
  (engine,view) = result
  MH.State{W.attach(engine,with_body(view,body)),support,minor,history,tail}


def install_finished_gate(motion:MH.State,player:P.State,flying:Bool) -> MH.State:
  match motion player flying:
    case motion _ False{}: motion
    case MH.State{world,support,minor,history,tail} P.State{body,input,jumping,delay,trigger,sync,speed,head} True{}:
      install_finished_taken(body,support,minor,history,tail,W.take(world))



def install_finished_body(motion:MH.State,player:P.State,context:P.Context) -> MH.State:
  P.Context{travel,strength,factor,affected,mode} = context
  install_finished_gate(motion,player,P.mode_flying(mode))



def player_finished(motion: MH.State, tables: L.Tables, +work: Work,
                    result: Result<&2, &2, P.Error, P.Transition>) -> State & Result<&2, &2, Error, Observation>:
  match result:
    case Fail{cause}: rollback(motion, tables, work_frame(work), FinishError{cause})
    case Done{P.Transition{+player, transition, attempted, jumped}}:
      +next = with_player(work_metadata(work), PR.metadata(player))
      rotation_finished(install_finished_body(motion,player,work_context(work)), tables, next, work,
        Rotation.normalize(request_rotation_fuel(frame_request(work_frame(work))), Rotation.State{PR.look(controls(next)), entity_count(entity(next))}))

# This closed client currently has no effect/impulse creator or mounted receiver.
# Flying and old position are actual held observations; the remaining flags are
# its explicit ClientLevel, alive/unremoved, normal-physics profile admission.
def block_inside_hooks(+metadata: Metadata, context: P.Context,
                       +request: Request) -> RBI.Hooks:
  P.Context{travel, strength, factor, affected, mode} = context
  RBI.Hooks{Inside.Player{P.mode_flying(mode), False{}}, Inside.ClientLevel{},
    entity_old_position(entity(metadata)), "minecraft:overworld", False{}, False{}, True{},
    request_movement_fuel(request), request_movement_fuel(request), []}

def finished_player(transition: P.Transition) -> P.State:
  P.Transition{player, movement, attempted, jumped} = transition
  player

def with_work_receiver(work: Work, receiver: Inside.Receiver) -> Work:
  Work{frame, metadata, early, updates, prepared, context, tail} = work
  Work{frame, with_receiver(metadata, receiver), early, updates, prepared, context, tail}

def block_inside_finished(tables: L.Tables, +work: Work, transition: P.Transition,
                         result: MH.State & Inside.Receiver & Result<&2, &2, RBI.Error, BIW.Observation>) -> State & Result<&2, &2, Error, Observation>:
  (motion, receiver, status) = result
  match status:
    case Fail{cause}: rollback(motion, tables, work_frame(work), BlockInsideError{cause})
    case Done{observation}: player_finished(motion, tables, with_work_receiver(work, receiver), Done{transition})

# Evaluate the outer finish once and install its flying Body before callbacks.
# Candidate metadata receives the returned receiver; Frame keeps rollback data.
def travel_outer_finished(+work: Work, motion: MH.State, tables: L.Tables,
                          outcome: TH.Outcome,
                          result: Result<&2, &2, P.Error, P.Transition>) -> State & Result<&2, &2, Error, Observation>:
  match result:
    case Fail{cause}: rollback(motion, tables, work_frame(work), FinishError{cause})
    case Done{+transition}:
      block_inside_finished(tables, work, transition,
        RBI.after_successful_travel(install_finished_body(motion, finished_player(transition), work_context(work)),
          receiver(work_metadata(work)), block_inside_hooks(work_metadata(work), work_context(work), frame_request(work_frame(work))), outcome))

# In the neutral path TH already owns this same body. Flight's outer Player
# override must be committed into that sole owner before rotation/late pose.

def traveled(+work: Work, result: MH.State & L.Tables & Result<&2, &2, TH.Error, TH.Outcome>) -> State & Result<&2, &2, Error, Observation>:
  (motion, tables, status) = result
  match status:
    case Fail{cause}: rollback(motion, tables, work_frame(work), TravelError{cause})
    case Done{+outcome}: travel_outer_finished(work, motion, tables, outcome, P.finish_checked(work_prepared(work), work_context(work), TH.outcome_transition(outcome)))

def travel_started(engine: G.Engine, tables: L.Tables, +work: Work) -> State & Result<&2, &2, Error, Observation>:
  Work{+frame, +metadata, early, updates, +prepared, +context, tail} = work
  P.Context{travel, strength, factor, affected, mode} = context
  traveled(work, TH.travel_checked(
    MH.State{W.attach(engine, with_body(frame_view(frame), prepared_body(prepared))), frame_support(frame), frame_minor(frame), H.State{frame_history(frame)}, []}, tables,
    TH.Request{prepared_input(prepared), travel,
      TH.Hooks{keys(local(metadata)), processed_input(prepared), False{}, LC.NeutralDry{}, True{}, True{},
        Inside.multiplier(receiver(metadata)), False{}, False{}, True{}, True{}, request_environment(frame_request(frame)), request_movement_fuel(frame_request(frame)), []}, H.NotRequired{}, []}))

def prepared(engine: G.Engine, +frame: Frame, +decision: LI.Controls,
             context: P.Context, early: List<&2, PPW.QueryRecord>,
             result: L.Tables & Result<&2, &2, LI.Error, LI.PreTravel>) -> State & Result<&2, &2, Error, Observation>:
  (tables, status) = result
  match status:
    case Fail{cause}: rollback_taken(tables, frame, InputError{cause}, (engine, frame_view(frame)))
    case Done{LI.PreTravel{local, value}}:
      travel_started(engine, tables, Work{frame, with_local(frame_metadata(frame), local, decision_sprinting(decision)), early, decision_updates(decision), value, context, []})

def apply_context(facts: ApplyFacts, +look: PL.State) -> LI.ApplyContext:
  ApplyFacts{ground, attrs, maximum, sprinting, no_gravity, discard, travel_mode,
    strength, factor, affected, tick_mode, sneak} = facts
  LI.ApplyContext{P.Context{T.Context{ground, attrs, yaw(look), maximum, sprinting, no_gravity, discard, travel_mode}, strength, factor, affected, tick_mode}, sneak, pitch(look)}

def replay_setters(updates: List<&2, Bool>, current: Bool) -> Bool:
  match updates:
    case Nil{}: current
    case value <> rest: replay_setters(rest, value)

def setter_gate(equal: Bool, engine: G.Engine, tables: L.Tables, +frame: Frame,
                +decision: LI.Controls, early: List<&2, PPW.QueryRecord>, +context: LI.ApplyContext) -> State & Result<&2, &2, Error, Observation>:
  match equal:
    case False{}: rollback_taken(tables, frame, SprintSetterMismatch{}, (engine, frame_view(frame)))
    case True{}:
      LI.ApplyContext{tick, sneak, pitch} = context
      prepared(engine, frame, decision, tick, early,
        LI.prepare_checked(tables, decision, PR.compose(view_body(frame_view(frame)), player(frame_metadata(frame))), context))

def controlled(engine: G.Engine, tables: L.Tables, +frame: Frame,
               early: List<&2, PPW.QueryRecord>, result: Result<&2, &2, LI.Error, LI.Controls>) -> State & Result<&2, &2, Error, Observation>:
  match result:
    case Fail{cause}: rollback_taken(tables, frame, InputError{cause}, (engine, frame_view(frame)))
    case Done{+decision}:
      LI.Controls{local, +final, updates} = decision
      setter_gate(LI.same_bool(final, replay_setters(updates, sprinting(frame_metadata(frame)))), engine, tables, frame, decision, early,
        apply_context(request_apply(frame_request(frame)), PR.look(controls(frame_metadata(frame)))))

def control_pose(pose: Pose.State) -> LI.Pose:
  match pose:
    case Pose.State{Pose.Standing{}, eye, tail}: LI.Standing{}
    case Pose.State{Pose.Crouching{}, eye, tail}: LI.Crouching{}
    case _: LI.OtherPose{}

def control_context_fields(+frame: Frame, fits: Fits, facts: ControlFacts,
                           body: M.Body, collision: LM.MinorState) -> LI.Context:
  Fits{standing, crouching, records} = fits
  ControlFacts{food, abilities, mobility, window, mode} = facts
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = body
  LM.MinorState{minor} = collision
  LI.Context{standing, crouching, food, abilities, mobility, horizontal, minor, window, control_pose(pose(frame_metadata(frame))), mode}

def control_context(+frame: Frame, fits: Fits) -> LI.Context:
  control_context_fields(frame, fits, request_control(frame_request(frame)), view_body(frame_view(frame)), frame_minor(frame))

def fits_finished(engine: G.Engine, tables: L.Tables, +frame: Frame, +fits: Fits) -> State & Result<&2, &2, Error, Observation>:
  Fits{standing, crouching, records} = fits
  +metadata = frame_metadata(frame)
  controlled(engine, tables, frame, records,
    LI.controls_checked(local(metadata), sprinting(metadata), PR.buttons(controls(metadata)), control_context(frame, fits)))

def record_clear(record: E.QueryRecord) -> Bool:
  E.QueryRecord{box, clear, yielded, reads} = record
  clear

def fit_box(query: Pose.FitQuery) -> A.AABB:
  Pose.FitQuery{pose, box} = query
  box

def standing_finished(registry: B.Registry, tables: L.Tables, +frame: Frame,
                      crouching: E.QueryRecord, result: C.World & Result<&2, &2, E.Error, E.QueryRecord>) -> State & Result<&2, &2, Error, Observation>:
  (world, status) = result
  match status:
    case Fail{cause}: rollback_taken(tables, frame, ControlWorldError{cause}, (G.Engine{world, registry}, frame_view(frame)))
    case Done{+standing}: fits_finished(G.Engine{world, registry}, tables, frame,
      Fits{record_clear(standing), True{}, [PPW.QueryRecord{Pose.Crouching{}, crouching}, PPW.QueryRecord{Pose.Standing{}, standing}]})

def standing_query(fuel: Nat, world: C.World, registry: B.Registry, tables: L.Tables,
                   +frame: Frame, +palette: W.Palette, crouching: E.QueryRecord,
                   result: Result<&2, &2, Pose.Error, Pose.Metadata>) -> State & Result<&2, &2, Error, Observation>:
  match fuel result:
    case _ Fail{cause}: rollback_taken(tables, frame, PoseError{cause}, (G.Engine{world, registry}, frame_view(frame)))
    case 0n Done{values}: rollback_taken(tables, frame, ControlBudget{}, (G.Engine{world, registry}, frame_view(frame)))
    case 1n+rest Done{values}:
      standing_finished(registry, tables, frame, crouching, E.query(world, palette,
        fit_box(Pose.fit_query(body_position(view_body(frame_view(frame))), Pose.Standing{}, values)), request_environment(frame_request(frame))))

def crouching_gate(needed: Bool, fuel: Nat, world: C.World, registry: B.Registry,
                   tables: L.Tables, +frame: Frame, +palette: W.Palette, +crouching: E.QueryRecord) -> State & Result<&2, &2, Error, Observation>:
  match needed:
    case True{}: standing_query(fuel, world, registry, tables, frame, palette, crouching, Pose.metadata(Pose.Standing{}))
    case False{}: fits_finished(G.Engine{world, registry}, tables, frame,
      Fits{True{}, record_clear(crouching), [PPW.QueryRecord{Pose.Crouching{}, crouching}]})

def crouching_finished(fuel: Nat, registry: B.Registry, tables: L.Tables, +frame: Frame,
                       palette: W.Palette, result: C.World & Result<&2, &2, E.Error, E.QueryRecord>) -> State & Result<&2, &2, Error, Observation>:
  (world, status) = result
  match status:
    case Fail{cause}: rollback_taken(tables, frame, ControlWorldError{cause}, (G.Engine{world, registry}, frame_view(frame)))
    case Done{+crouching}: crouching_gate(record_clear(crouching) && Bool.not(shift(keys(local(frame_metadata(frame))))), fuel, world, registry, tables, frame, palette, crouching)

def crouching_query(fuel: Nat, world: C.World, registry: B.Registry, tables: L.Tables,
                    +frame: Frame, +palette: W.Palette,
                    result: Result<&2, &2, Pose.Error, Pose.Metadata>) -> State & Result<&2, &2, Error, Observation>:
  match fuel result:
    case _ Fail{cause}: rollback_taken(tables, frame, PoseError{cause}, (G.Engine{world, registry}, frame_view(frame)))
    case 0n Done{values}: rollback_taken(tables, frame, ControlBudget{}, (G.Engine{world, registry}, frame_view(frame)))
    case 1n+rest Done{values}:
      crouching_finished(rest, registry, tables, frame, palette, E.query(world, palette,
        fit_box(Pose.fit_query(body_position(view_body(frame_view(frame))), Pose.Crouching{}, values)), request_environment(frame_request(frame))))

def palette_gate(error: Maybe<&2, E.Error>, world: C.World, registry: B.Registry,
                 tables: L.Tables, +frame: Frame, palette: W.Palette) -> State & Result<&2, &2, Error, Observation>:
  match error:
    case Some{cause}: rollback_taken(tables, frame, ControlWorldError{cause}, (G.Engine{world, registry}, frame_view(frame)))
    case None{}:
      crouching_query(request_control_fuel(frame_request(frame)), world, registry, tables, frame, palette, Pose.metadata(Pose.Crouching{}))

def palette_finished(world: C.World, tables: L.Tables, +frame: Frame,
                     result: B.Registry & Result<&2, &2, E.Error, W.Palette>) -> State & Result<&2, &2, Error, Observation>:
  (registry, status) = result
  match status:
    case Fail{cause}: rollback_taken(tables, frame, ControlWorldError{cause}, (G.Engine{world, registry}, frame_view(frame)))
    case Done{+palette}: palette_gate(E.palette_error(E.view_palette(frame_view(frame)), palette), world, registry, tables, frame, palette)

def environment_gate(error: Maybe<&2, E.Error>, engine: G.Engine, tables: L.Tables,
                     +frame: Frame) -> State & Result<&2, &2, Error, Observation>:
  match error:
    case Some{cause}: rollback_taken(tables, frame, ControlWorldError{cause}, (engine, frame_view(frame)))
    case None{}:
      G.Engine{world, registry} = engine
      palette_finished(world, tables, frame, E.current_palette(registry))

def admitted(engine: G.Engine, tables: L.Tables, +frame: Frame, error: Maybe<&2, Error>) -> State & Result<&2, &2, Error, Observation>:
  match error:
    case Some{cause}: rollback_taken(tables, frame, cause, (engine, frame_view(frame)))
    case None{}: environment_gate(E.environment_error(request_environment(frame_request(frame))), engine, tables, frame)

def local_extracted(tables: L.Tables, support: SP.State, minor: LM.MinorState,
                    history: H.History, metadata: Metadata, request: Request,
                    result: G.Engine & W.View) -> State & Result<&2, &2, Error, Observation>:
  (engine, view) = result
  +frame : Frame = Frame{view, support, minor, history, metadata, request, []}
  admitted(engine, tables, frame, frame_error(frame))

def local_ready(state: State, request: Request) -> State & Result<&2, &2, Error, Observation>:
  State{MH.State{world, support, minor, H.State{history}, tail}, tables, metadata, owned} = state
  local_extracted(tables, support, minor, history, metadata, request, W.take(world))

def common_finished(tables: L.Tables, support: SP.State, minor: LM.MinorState,
                    history: H.State, +metadata: Metadata, request: Request,
                    engine: G.Engine, view: W.View,
                    result: ECT.State & Result<&2, &2, ECT.Error, ECT.Snapshot>) -> State & Result<&2, &2, Error, Observation>:
  (ECT.State{next, tail}, status) = result
  match status:
    case Fail{cause}: (State{MH.State{W.attach(engine, view), support, minor, history, []}, tables, metadata, []}, Fail{EntityError{cause}})
    case Done{ECT.Snapshot{entity, look}}:
      local_ready(State{MH.State{W.attach(engine, view), support, minor, history, []}, tables,
        with_entity(with_controls(metadata, with_look(controls(metadata), look)), entity), []}, request)

def scheduled_extracted(tables: L.Tables, support: SP.State, minor: LM.MinorState,
                        history: H.State, +metadata: Metadata, +request: Request,
                        result: G.Engine & W.View) -> State & Result<&2, &2, Error, Observation>:
  (G.Engine{world, registry}, +view) = result
  common_finished(tables, support, minor, history, metadata, request, G.Engine{C.step(world), registry}, view,
    ECT.common_tick(ECT.State{entity(metadata), []}, ECT.Request{body_position(view_body(view)), PR.look(controls(metadata)), request_common(request), []}))

def scheduled_ready(state: State, request: Request) -> State & Result<&2, &2, Error, Observation>:
  State{MH.State{world, support, minor, history, tail}, tables, metadata, owned} = state
  scheduled_extracted(tables, support, minor, history, metadata, request, W.take(world))

# Structural checks happen before any owner extraction or Core step. Data/owned
# tails are returned verbatim. Unsupported numeric/lifecycle fields are admitted
# phase failures and obey the declared post-Core/post-common anchor policy.
def selected(state: State, request: Request, scheduled: Bool) -> State & Result<&2, &2, Error, Observation>:
  match scheduled:
    case False{}: local_ready(state, request)
    case True{}: scheduled_ready(state, request)

def canonical_pose(state: State, request: Request, scheduled: Bool, pose: Pose.State) -> State & Result<&2, &2, Error, Observation>:
  match pose:
    case Pose.State{value, eye, Nil{}}: selected(state, request, scheduled)
    case _: (state, Fail{NonCanonicalState{3}})

def canonical_metadata(motion: MH.State, tables: L.Tables, metadata: Metadata,
                       request: Request, scheduled: Bool) -> State & Result<&2, &2, Error, Observation>:
  match metadata:
    case Metadata{local, player, sprinting, +pose, controls, entity, receiver, error, Nil{}}:
      canonical_pose(State{motion, tables, Metadata{local, player, sprinting, pose, controls, entity, receiver, error, []}, []}, request, scheduled, pose)
    case _: (State{motion, tables, metadata, []}, Fail{NonCanonicalState{2}})

def canonical_motion(state: State, request: Request, scheduled: Bool) -> State & Result<&2, &2, Error, Observation>:
  match state:
    case State{MH.State{world, support, minor, history, Nil{}}, tables, metadata, Nil{}}:
      canonical_metadata(MH.State{world, support, minor, history, []}, tables, metadata, request, scheduled)
    case _: (state, Fail{NonCanonicalState{1}})

def canonical_request(state: State, request: Request, scheduled: Bool) -> State & Result<&2, &2, Error, Observation>:
  match request:
    case Request{lifecycle, common, control, apply, environment, cf, mf, rf, pf, Nil{}}:
      canonical_motion(state, Request{lifecycle, common, control, apply, environment, cf, mf, rf, pf, []}, scheduled)
    case _: (state, Fail{NonCanonicalRequest{}})

def checked(state: State, request: Request, scheduled: Bool) -> State & Result<&2, &2, Error, Observation>:
  match state:
    case State{motion, tables, metadata, Nil{}}: canonical_request(State{motion, tables, metadata, []}, request, scheduled)
    case State{motion, tables, metadata, owned}: (State{motion, tables, metadata, owned}, Fail{NonCanonicalState{0}})

def local_checked(state: State, request: Request) -> State & Result<&2, &2, Error, Observation>:
  checked(state, request, False{})

def scheduled_checked(state: State, request: Request) -> State & Result<&2, &2, Error, Observation>:
  checked(state, request, True{})

def realtime_selected(state: State, request: Request, paused: Bool) -> State & Result<&2, &2, Error, Maybe<&2, Observation>>:
  match paused:
    case True{}: (state, Done{None{}})
    case False{}:
      W.paired(State, Result<&2, &2, Error, Observation>, State & Result<&2, &2, Error, Maybe<&2, Observation>>, scheduled_checked(state, request),
        next => result => (next, Result.map(&2, &2, Error, Observation, Maybe<&2, Observation>, x => Some{x}, result)))

def realtime_clocked(tables: L.Tables, support: SP.State, minor: LM.MinorState,
                     history: H.State, metadata: Metadata, tail: List<&1, State>,
                     request: Request, registry: B.Registry, view: W.View,
                     result: C.World & C.Clock) -> State & Result<&2, &2, Error, Maybe<&2, Observation>>:
  (world, C.Clock{tick, time, paused, daylight, revision, pending}) = result
  realtime_selected(State{MH.State{W.attach(G.Engine{world, registry}, view), support, minor, history, []}, tables, metadata, tail}, request, paused)

def realtime_extracted(tables: L.Tables, support: SP.State, minor: LM.MinorState,
                       history: H.State, metadata: Metadata, tail: List<&1, State>,
                       request: Request, result: G.Engine & W.View) -> State & Result<&2, &2, Error, Maybe<&2, Observation>>:
  (G.Engine{world, registry}, view) = result
  realtime_clocked(tables, support, minor, history, metadata, tail, request, registry, view, C.clock(world))

def realtime_checked(state: State, request: Request) -> State & Result<&2, &2, Error, Maybe<&2, Observation>>:
  match state:
    case State{MH.State{world, support, minor, history, Nil{}}, tables, metadata, Nil{}}:
      realtime_extracted(tables, support, minor, history, metadata, [], request, W.take(world))
    case _: (state, Fail{NonCanonicalState{0}})

# Packet publication is independent of local input sampling and all clocks.
def packet_projected(tables: L.Tables, support: SP.State, minor: LM.MinorState,
                     history: H.State, metadata: Metadata, next: PC.Controller,
                     tail: List<&1, State>, owned: List<&1, MH.State>,
                     result: W.State & Result<&2, &2, String, Unit>) -> State & Result<&2, &2, Error, Unit>:
  (world, status) = result
  match status:
    case Fail{reason}: (State{MH.State{world, support, minor, history, owned}, tables, metadata, tail}, Fail{ViewError{reason}})
    case Done{unit}: (State{MH.State{world, support, minor, history, owned}, tables, with_controls(metadata, next), tail}, Done{Unit{}})

def packet_selected(motion: MH.State, tables: L.Tables, metadata: Metadata,
                    tail: List<&1, State>, result: Result<&2, &2, PC.Error, PC.Controller>) -> State & Result<&2, &2, Error, Unit>:
  MH.State{world, support, minor, history, owned} = motion
  match result:
    case Fail{cause}: (State{MH.State{world, support, minor, history, owned}, tables, metadata, tail}, Fail{ControllerError{cause}})
    case Done{+next}:
      +look = PR.look(next)
      packet_projected(tables, support, minor, history, metadata, next, tail, owned,
        W.look(world, PL.mul(yaw(look), PL.float_bits(1016003125)), PL.mul(pitch(look), PL.float_bits(1016003125))))

def input_checked(state: State, bindings: PI.Bindings, packet: CC.Packet) -> State & Result<&2, &2, Error, Unit>:
  State{motion, tables, +metadata, tail} = state
  packet_selected(motion, tables, metadata, tail, PC.apply(controls(metadata), bindings, packet))

def release(state: State) -> State:
  State{motion, tables, +metadata, tail} = state
  State{motion, tables, with_controls(metadata, PC.release(controls(metadata))), tail}

# This caller-supplied owner operation never schedules/samples by itself. It is
# a composition wrapper; read-only cache mutation discipline belongs to operation.
def query_finished(-A: Type, tables: L.Tables, metadata: Metadata,
                   tail: List<&1, State>, support: SP.State, minor: LM.MinorState,
                   history: H.State, owned: List<&1, MH.State>, result: W.State & A) -> State & A:
  (world, value) = result
  (State{MH.State{world, support, minor, history, owned}, tables, metadata, tail}, value)

def query(-A: Type, state: State, operation: W.State -> W.State & A) -> State & A:
  State{MH.State{world, support, minor, history, owned}, tables, metadata, tail} = state
  query_finished(A, tables, metadata, tail, support, minor, history, owned, operation(world))

def eye_extracted(motion_support: SP.State, minor: LM.MinorState, history: H.State,
                  owned: List<&1, MH.State>, tables: L.Tables, +metadata: Metadata,
                  tail: List<&1, State>, result: G.Engine & W.View) -> State & Result<&2, &2, Pose.Error, M.Vec3>:
  (engine, +view) = result
  (State{MH.State{W.attach(engine, view), motion_support, minor, history, owned}, tables, metadata, tail},
    Pose.eye_position_checked(eye_request(view_body(view), metadata)))

def eye_position_checked(state: State) -> State & Result<&2, &2, Pose.Error, M.Vec3>:
  State{MH.State{world, support, minor, history, owned}, tables, metadata, tail} = state
  eye_extracted(support, minor, history, owned, tables, metadata, tail, W.take(world))

law rollback_retains_returned_engine_tables_and_complete_anchor:
  for engine: G.Engine
  for tables: L.Tables
  for +frame: Frame
  for candidate: W.View
  for +cause: Error
  {rollback_taken(tables, frame, cause, (engine, candidate)) ==
    (State{MH.State{W.attach(engine, frame_view(frame)), frame_support(frame), frame_minor(frame), H.State{frame_history(frame)}, []},
      tables, frame_metadata(frame), []}, Fail{cause}) : State & Result<&2, &2, Error, Observation>}

def rollback_retains_returned_engine_tables_and_complete_anchor(engine, tables, frame, candidate, cause):
  {==}

law structural_owned_tail_retains_every_child:
  for motion: MH.State
  for tables: L.Tables
  for metadata: Metadata
  for child: State
  for tail: List<&1, State>
  for request: Request
  for scheduled: Bool
  {checked(State{motion, tables, metadata, child <> tail}, request, scheduled) ==
    (State{motion, tables, metadata, child <> tail}, Fail{NonCanonicalState{0}}) : State & Result<&2, &2, Error, Observation>}

def structural_owned_tail_retains_every_child(motion, tables, metadata, child, tail, request, scheduled):
  {==}

law ordered_setters_preserve_repeated_commands:
  for +value: Bool
  for rest: List<&2, Bool>
  for current: Bool
  {replay_setters(value <> value <> rest, current) == replay_setters(rest, value) : Bool}

def ordered_setters_preserve_repeated_commands(value, rest, current):
  {==}

law paused_pulse_runs_no_phase:
  for state: State
  for request: Request
  {realtime_selected(state, request, True{}) == (state, Done{None{}}) : State & Result<&2, &2, Error, Maybe<&2, Observation>>}

def paused_pulse_runs_no_phase(state, request):
  {==}


# Additive staged consumer entry. The fixed Facts path above is retained.
# This pause point precedes applyInput/jump and follows ONE real control sample.
type PrepareRequest is Data:
  PrepareRequest{lifecycle:Lifecycle, common:ECT.Context, control:ControlFacts,
    environment:E.Environment, control_fuel:Nat, movement_fuel:Nat,
    rotation_fuel:Nat, pose_fuel:Nat, tail:List<&2,PrepareRequest>}

type StageStamp is Data:
  StageStamp{clock:C.Clock, state_count:U32, event_count:Nat}

type PreFrame is Data:
  PreFrame{view:W.View, support:SP.State, minor:LM.MinorState,
    history:H.History, metadata:Metadata, request:PrepareRequest,
    stamp:StageStamp, tail:List<&2,PreFrame>}

type ApplyPending is Data:
  ApplyPending{frame:PreFrame, decision:LI.Controls,
    early:List<&2,PPW.QueryRecord>, error:Maybe<&2,Error>,
    tail:List<&2,ApplyPending>}

# State remains the sole owner, including any original structural child owners.
# Pending is immutable evidence; no new recursive owned child conversion occurs.
type ApplyStage is Type:
  ApplyStage{state:State, pending:ApplyPending}

type PrepareResult is Type:
  AwaitApply{stage:ApplyStage}
  Rejected{state:State, error:Error}
  Paused{state:State}

type ApplyIntent is Data:
  ApplyIntent{sprinting:Bool, sprint_updates:List<&2,Bool>}

def pre_frame_view(frame:PreFrame) -> W.View:
  PreFrame{view,support,minor,history,metadata,request,stamp,tail} = frame
  view

def pre_frame_support(frame:PreFrame) -> SP.State:
  PreFrame{view,support,minor,history,metadata,request,stamp,tail} = frame
  support

def pre_frame_minor(frame:PreFrame) -> LM.MinorState:
  PreFrame{view,support,minor,history,metadata,request,stamp,tail} = frame
  minor

def pre_frame_history(frame:PreFrame) -> H.History:
  PreFrame{view,support,minor,history,metadata,request,stamp,tail} = frame
  history

def pre_frame_metadata(frame:PreFrame) -> Metadata:
  PreFrame{view,support,minor,history,metadata,request,stamp,tail} = frame
  metadata

def pre_frame_request(frame:PreFrame) -> PrepareRequest:
  PreFrame{view,support,minor,history,metadata,request,stamp,tail} = frame
  request

def pre_frame_stamp(frame:PreFrame) -> StageStamp:
  PreFrame{view,support,minor,history,metadata,request,stamp,tail} = frame
  stamp

def pending_frame(pending:ApplyPending) -> PreFrame:
  ApplyPending{frame,decision,early,error,tail} = pending
  frame

def pending_decision(pending:ApplyPending) -> LI.Controls:
  ApplyPending{frame,decision,early,error,tail} = pending
  decision

def pending_early(pending:ApplyPending) -> List<&2,PPW.QueryRecord>:
  ApplyPending{frame,decision,early,error,tail} = pending
  early

def pre_request_lifecycle(request:PrepareRequest) -> Lifecycle:
  PrepareRequest{lifecycle,common,control,environment,cf,mf,rf,pf,tail} = request
  lifecycle

def pre_request_common(request:PrepareRequest) -> ECT.Context:
  PrepareRequest{lifecycle,common,control,environment,cf,mf,rf,pf,tail} = request
  common

def pre_request_control(request:PrepareRequest) -> ControlFacts:
  PrepareRequest{lifecycle,common,control,environment,cf,mf,rf,pf,tail} = request
  control

def pre_request_environment(request:PrepareRequest) -> E.Environment:
  PrepareRequest{lifecycle,common,control,environment,cf,mf,rf,pf,tail} = request
  environment

def pre_request_control_fuel(request:PrepareRequest) -> Nat:
  PrepareRequest{lifecycle,common,control,environment,cf,mf,rf,pf,tail} = request
  cf

def pre_request_full(request:PrepareRequest,facts:ApplyFacts) -> Request:
  PrepareRequest{lifecycle,common,control,environment,cf,mf,rf,pf,tail} = request
  Request{lifecycle,common,control,facts,environment,cf,mf,rf,pf,[]}

def pre_full_frame(frame:PreFrame,facts:ApplyFacts) -> Frame:
  PreFrame{view,support,minor,history,metadata,request,stamp,tail} = frame
  Frame{view,support,minor,history,metadata,pre_request_full(request,facts),[]}

def stage_stamp(engine:G.Engine) -> G.Engine & StageStamp:
  G.Engine{C.World{+tick,+time,+paused,+daylight,+revision,+count,sections,+pending,+events},registry} = engine
  (G.Engine{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},registry},
    StageStamp{C.Clock{tick,time,paused,daylight,revision,Q.length(C.Mutation,pending)},count,List.length(&2,C.CoreEvent,events)})

def pre_frame_error(+frame:PreFrame) -> Maybe<&2,Error>:
  +metadata = pre_frame_metadata(frame)
  first(lifecycle_error(pre_request_lifecycle(pre_frame_request(frame))),
    first(control_facts_error(pre_request_control(pre_frame_request(frame))),
    first(controller_error(PC.controller_error(controls(metadata))),
    first(entity_error(ECT.metadata_error(entity(metadata))),
    first(input_error(LI.state_error(local(metadata))),
    first(stable_error(stable_pose(pose(metadata))),
      pose_error(Pose.state_error(pose(metadata),view_body(pre_frame_view(frame))))))))))

def pre_failure_taken(tables:L.Tables,+frame:PreFrame,cause:Error,
                      result:G.Engine & W.View) -> PrepareResult:
  (engine,discarded) = result
  Rejected{State{MH.State{W.attach(engine,pre_frame_view(frame)),pre_frame_support(frame),
    pre_frame_minor(frame),H.State{pre_frame_history(frame)},[]},tables,pre_frame_metadata(frame),[]},cause}

def pre_control_context_fields(+frame:PreFrame,fits:Fits,facts:ControlFacts,
                              body:M.Body,collision:LM.MinorState) -> LI.Context:
  Fits{standing,crouching,records} = fits
  ControlFacts{food,abilities,mobility,window,mode} = facts
  M.Body{position,box,velocity,width,height,ground,horizontal,vertical,below} = body
  LM.MinorState{minor} = collision
  LI.Context{standing,crouching,food,abilities,mobility,horizontal,minor,window,
    control_pose(pose(pre_frame_metadata(frame))),mode}

def pre_control_context(+frame:PreFrame,fits:Fits) -> LI.Context:
  pre_control_context_fields(frame,fits,pre_request_control(pre_frame_request(frame)),
    view_body(pre_frame_view(frame)),pre_frame_minor(frame))

def pre_decision_gate(equal:Bool,engine:G.Engine,tables:L.Tables,+frame:PreFrame,
                      decision:LI.Controls,early:List<&2,PPW.QueryRecord>) -> PrepareResult:
  match equal:
    case False{}: pre_failure_taken(tables,frame,SprintSetterMismatch{},(engine,pre_frame_view(frame)))
    case True{}:
      AwaitApply{ApplyStage{State{MH.State{W.attach(engine,pre_frame_view(frame)),pre_frame_support(frame),
        pre_frame_minor(frame),H.State{pre_frame_history(frame)},[]},tables,pre_frame_metadata(frame),[]},
        ApplyPending{frame,decision,early,None{},[]}}}

def pre_controlled(engine:G.Engine,tables:L.Tables,+frame:PreFrame,
                   early:List<&2,PPW.QueryRecord>,result:Result<&2,&2,LI.Error,LI.Controls>) -> PrepareResult:
  match result:
    case Fail{cause}: pre_failure_taken(tables,frame,InputError{cause},(engine,pre_frame_view(frame)))
    case Done{+decision}:
      pre_decision_gate(LI.same_bool(decision_sprinting(decision),
        replay_setters(decision_updates(decision),sprinting(pre_frame_metadata(frame)))),
        engine,tables,frame,decision,early)

def pre_fits_finished(engine: G.Engine, tables: L.Tables, +frame: PreFrame, +fits: Fits) -> PrepareResult:
  Fits{standing, crouching, records} = fits
  +metadata = pre_frame_metadata(frame)
  pre_controlled(engine, tables, frame, records,
    LI.controls_checked(local(metadata), sprinting(metadata), PR.buttons(controls(metadata)), pre_control_context(frame, fits)))


def pre_standing_finished(registry: B.Registry, tables: L.Tables, +frame: PreFrame,
                      crouching: E.QueryRecord, result: C.World & Result<&2, &2, E.Error, E.QueryRecord>) -> PrepareResult:
  (world, status) = result
  match status:
    case Fail{cause}: pre_failure_taken(tables, frame, ControlWorldError{cause}, (G.Engine{world, registry}, pre_frame_view(frame)))
    case Done{+standing}: pre_fits_finished(G.Engine{world, registry}, tables, frame,
      Fits{record_clear(standing), True{}, [PPW.QueryRecord{Pose.Crouching{}, crouching}, PPW.QueryRecord{Pose.Standing{}, standing}]})


def pre_standing_query(fuel: Nat, world: C.World, registry: B.Registry, tables: L.Tables,
                   +frame: PreFrame, +palette: W.Palette, crouching: E.QueryRecord,
                   result: Result<&2, &2, Pose.Error, Pose.Metadata>) -> PrepareResult:
  match fuel result:
    case _ Fail{cause}: pre_failure_taken(tables, frame, PoseError{cause}, (G.Engine{world, registry}, pre_frame_view(frame)))
    case 0n Done{values}: pre_failure_taken(tables, frame, ControlBudget{}, (G.Engine{world, registry}, pre_frame_view(frame)))
    case 1n+rest Done{values}:
      pre_standing_finished(registry, tables, frame, crouching, E.query(world, palette,
        fit_box(Pose.fit_query(body_position(view_body(pre_frame_view(frame))), Pose.Standing{}, values)), pre_request_environment(pre_frame_request(frame))))


def pre_crouching_gate(needed: Bool, fuel: Nat, world: C.World, registry: B.Registry,
                   tables: L.Tables, +frame: PreFrame, +palette: W.Palette, +crouching: E.QueryRecord) -> PrepareResult:
  match needed:
    case True{}: pre_standing_query(fuel, world, registry, tables, frame, palette, crouching, Pose.metadata(Pose.Standing{}))
    case False{}: pre_fits_finished(G.Engine{world, registry}, tables, frame,
      Fits{True{}, record_clear(crouching), [PPW.QueryRecord{Pose.Crouching{}, crouching}]})


def pre_crouching_finished(fuel: Nat, registry: B.Registry, tables: L.Tables, +frame: PreFrame,
                       palette: W.Palette, result: C.World & Result<&2, &2, E.Error, E.QueryRecord>) -> PrepareResult:
  (world, status) = result
  match status:
    case Fail{cause}: pre_failure_taken(tables, frame, ControlWorldError{cause}, (G.Engine{world, registry}, pre_frame_view(frame)))
    case Done{+crouching}: pre_crouching_gate(record_clear(crouching) && Bool.not(shift(keys(local(pre_frame_metadata(frame))))), fuel, world, registry, tables, frame, palette, crouching)


def pre_crouching_query(fuel: Nat, world: C.World, registry: B.Registry, tables: L.Tables,
                    +frame: PreFrame, +palette: W.Palette,
                    result: Result<&2, &2, Pose.Error, Pose.Metadata>) -> PrepareResult:
  match fuel result:
    case _ Fail{cause}: pre_failure_taken(tables, frame, PoseError{cause}, (G.Engine{world, registry}, pre_frame_view(frame)))
    case 0n Done{values}: pre_failure_taken(tables, frame, ControlBudget{}, (G.Engine{world, registry}, pre_frame_view(frame)))
    case 1n+rest Done{values}:
      pre_crouching_finished(rest, registry, tables, frame, palette, E.query(world, palette,
        fit_box(Pose.fit_query(body_position(view_body(pre_frame_view(frame))), Pose.Crouching{}, values)), pre_request_environment(pre_frame_request(frame))))


def pre_palette_gate(error: Maybe<&2, E.Error>, world: C.World, registry: B.Registry,
                 tables: L.Tables, +frame: PreFrame, palette: W.Palette) -> PrepareResult:
  match error:
    case Some{cause}: pre_failure_taken(tables, frame, ControlWorldError{cause}, (G.Engine{world, registry}, pre_frame_view(frame)))
    case None{}:
      pre_crouching_query(pre_request_control_fuel(pre_frame_request(frame)), world, registry, tables, frame, palette, Pose.metadata(Pose.Crouching{}))


def pre_palette_finished(world: C.World, tables: L.Tables, +frame: PreFrame,
                     result: B.Registry & Result<&2, &2, E.Error, W.Palette>) -> PrepareResult:
  (registry, status) = result
  match status:
    case Fail{cause}: pre_failure_taken(tables, frame, ControlWorldError{cause}, (G.Engine{world, registry}, pre_frame_view(frame)))
    case Done{+palette}: pre_palette_gate(E.palette_error(E.view_palette(pre_frame_view(frame)), palette), world, registry, tables, frame, palette)


def pre_environment_gate(error: Maybe<&2, E.Error>, engine: G.Engine, tables: L.Tables,
                     +frame: PreFrame) -> PrepareResult:
  match error:
    case Some{cause}: pre_failure_taken(tables, frame, ControlWorldError{cause}, (engine, pre_frame_view(frame)))
    case None{}:
      G.Engine{world, registry} = engine
      pre_palette_finished(world, tables, frame, E.current_palette(registry))


def pre_admitted(engine: G.Engine, tables: L.Tables, +frame: PreFrame, error: Maybe<&2, Error>) -> PrepareResult:
  match error:
    case Some{cause}: pre_failure_taken(tables, frame, cause, (engine, pre_frame_view(frame)))
    case None{}: pre_environment_gate(E.environment_error(pre_request_environment(pre_frame_request(frame))), engine, tables, frame)


def pre_extracted_stamp(tables:L.Tables,support:SP.State,minor:LM.MinorState,
                        history:H.History,metadata:Metadata,request:PrepareRequest,
                        view:W.View,result:G.Engine & StageStamp) -> PrepareResult:
  (engine,stamp) = result
  +frame : PreFrame = PreFrame{view,support,minor,history,metadata,request,stamp,[]}
  pre_admitted(engine,tables,frame,pre_frame_error(frame))

def pre_local_extracted(tables:L.Tables,support:SP.State,minor:LM.MinorState,
                        history:H.History,metadata:Metadata,request:PrepareRequest,
                        result:G.Engine & W.View) -> PrepareResult:
  (engine,view) = result
  pre_extracted_stamp(tables,support,minor,history,metadata,request,view,stage_stamp(engine))

def pre_local_ready(state:State,request:PrepareRequest) -> PrepareResult:
  State{MH.State{world,support,minor,H.State{history},tail},tables,metadata,owned} = state
  pre_local_extracted(tables,support,minor,history,metadata,request,W.take(world))

def pre_common_finished(tables:L.Tables,support:SP.State,minor:LM.MinorState,
                       history:H.State,+metadata:Metadata,request:PrepareRequest,
                       engine:G.Engine,view:W.View,
                       result:ECT.State & Result<&2,&2,ECT.Error,ECT.Snapshot>) -> PrepareResult:
  (ECT.State{next,tail},status) = result
  match status:
    case Fail{cause}: Rejected{State{MH.State{W.attach(engine,view),support,minor,history,[]},tables,metadata,[]},EntityError{cause}}
    case Done{ECT.Snapshot{entity,look}}:
      pre_local_ready(State{MH.State{W.attach(engine,view),support,minor,history,[]},tables,
        with_entity(with_controls(metadata,with_look(controls(metadata),look)),entity),[]},request)

def pre_scheduled_extracted(tables:L.Tables,support:SP.State,minor:LM.MinorState,
                           history:H.State,+metadata:Metadata,+request:PrepareRequest,
                           result:G.Engine & W.View) -> PrepareResult:
  (G.Engine{world,registry},+view) = result
  pre_common_finished(tables,support,minor,history,metadata,request,G.Engine{C.step(world),registry},view,
    ECT.common_tick(ECT.State{entity(metadata),[]},ECT.Request{body_position(view_body(view)),
      PR.look(controls(metadata)),pre_request_common(request),[]}))

def pre_scheduled_ready(state:State,request:PrepareRequest) -> PrepareResult:
  State{MH.State{world,support,minor,history,tail},tables,metadata,owned} = state
  pre_scheduled_extracted(tables,support,minor,history,metadata,request,W.take(world))

def pre_selected(state:State,request:PrepareRequest,scheduled:Bool) -> PrepareResult:
  match scheduled:
    case False{}: pre_local_ready(state,request)
    case True{}: pre_scheduled_ready(state,request)

def pre_canonical_pose(state:State,request:PrepareRequest,scheduled:Bool,pose:Pose.State) -> PrepareResult:
  match pose:
    case Pose.State{value,eye,Nil{}}: pre_selected(state,request,scheduled)
    case _: Rejected{state,NonCanonicalState{3}}

def pre_canonical_metadata(motion:MH.State,tables:L.Tables,metadata:Metadata,
                          request:PrepareRequest,scheduled:Bool) -> PrepareResult:
  match metadata:
    case Metadata{local,player,sprinting,+pose,controls,entity, receiver, error,Nil{}}:
      pre_canonical_pose(State{motion,tables,Metadata{local,player,sprinting,pose,controls,entity, receiver, error,[]},[]},request,scheduled,pose)
    case _: Rejected{State{motion,tables,metadata,[]},NonCanonicalState{2}}

def pre_canonical_motion(state:State,request:PrepareRequest,scheduled:Bool) -> PrepareResult:
  match state:
    case State{MH.State{world,support,minor,history,Nil{}},tables,metadata,Nil{}}:
      pre_canonical_metadata(MH.State{world,support,minor,history,[]},tables,metadata,request,scheduled)
    case _: Rejected{state,NonCanonicalState{1}}

def pre_canonical_request(state:State,request:PrepareRequest,scheduled:Bool) -> PrepareResult:
  match request:
    case PrepareRequest{lifecycle,common,control,environment,cf,mf,rf,pf,Nil{}}:
      pre_canonical_motion(state,PrepareRequest{lifecycle,common,control,environment,cf,mf,rf,pf,[]},scheduled)
    case _: Rejected{state,NonCanonicalRequest{}}

def prepare_checked(state:State,request:PrepareRequest,scheduled:Bool) -> PrepareResult:
  match state:
    case State{motion,tables,metadata,Nil{}}:
      pre_canonical_request(State{motion,tables,metadata,[]},request,scheduled)
    case State{motion,tables,metadata,owned}: Rejected{State{motion,tables,metadata,owned},NonCanonicalState{0}}

def prepare_local_checked(state:State,request:PrepareRequest) -> PrepareResult:
  prepare_checked(state,request,False{})

def prepare_scheduled_checked(state:State,request:PrepareRequest) -> PrepareResult:
  prepare_checked(state,request,True{})

def pre_realtime_selected(state:State,request:PrepareRequest,paused:Bool) -> PrepareResult:
  match paused:
    case True{}: Paused{state}
    case False{}: prepare_scheduled_checked(state,request)

def pre_realtime_clocked(tables:L.Tables,support:SP.State,minor:LM.MinorState,
                         history:H.State,metadata:Metadata,request:PrepareRequest,
                         registry:B.Registry,view:W.View,result:C.World & C.Clock) -> PrepareResult:
  (world,C.Clock{tick,time,paused,daylight,revision,pending}) = result
  pre_realtime_selected(State{MH.State{W.attach(G.Engine{world,registry},view),support,minor,history,[]},tables,metadata,[]},request,paused)

def pre_realtime_extracted(tables:L.Tables,support:SP.State,minor:LM.MinorState,
                           history:H.State,metadata:Metadata,request:PrepareRequest,
                           result:G.Engine & W.View) -> PrepareResult:
  (G.Engine{world,registry},view) = result
  pre_realtime_clocked(tables,support,minor,history,metadata,request,registry,view,C.clock(world))

def prepare_realtime_checked(state:State,request:PrepareRequest) -> PrepareResult:
  match state:
    case State{MH.State{world,support,minor,history,Nil{}},tables,metadata,Nil{}}:
      pre_realtime_extracted(tables,support,minor,history,metadata,request,W.take(world))
    case _: Rejected{state,NonCanonicalState{0}}

def stage_intent(stage:ApplyStage) -> ApplyStage & ApplyIntent:
  ApplyStage{state,+pending} = stage
  +decision = pending_decision(pending)
  (ApplyStage{state,pending},ApplyIntent{decision_sprinting(decision),decision_updates(decision)})

# Structural admission preserves every affine child before any query or resume.
def stage_shape_pose(state:State,pose:Pose.State) -> State & Maybe<&2,Error>:
  match pose:
    case Pose.State{value,eye,Nil{}}: (state,None{})
    case _: (state,Some{NonCanonicalState{3}})

def stage_shape_metadata(motion:MH.State,tables:L.Tables,metadata:Metadata) -> State & Maybe<&2,Error>:
  match metadata:
    case Metadata{local,player,sprinting,+pose,controls,entity, receiver, error,Nil{}}:
      stage_shape_pose(State{motion,tables,Metadata{local,player,sprinting,pose,controls,entity, receiver, error,[]},[]},pose)
    case _: (State{motion,tables,metadata,[]},Some{NonCanonicalState{2}})

def stage_shape(state:State) -> State & Maybe<&2,Error>:
  match state:
    case State{MH.State{world,support,minor,history,Nil{}},tables,metadata,Nil{}}:
      stage_shape_metadata(MH.State{world,support,minor,history,[]},tables,metadata)
    case State{motion,tables,metadata,Nil{}}:
      (State{motion,tables,metadata,[]},Some{NonCanonicalState{1}})
    case _: (state,Some{NonCanonicalState{0}})

def pre_protocol_request(request:PrepareRequest) -> Maybe<&2,Error>:
  match request:
    case PrepareRequest{lifecycle,common,control,environment,cf,mf,rf,pf,Nil{}}: None{}
    case _: Some{NonCanonicalRequest{}}

def pre_protocol_pose(pose:Pose.State) -> Maybe<&2,Error>:
  match pose:
    case Pose.State{value,eye,Nil{}}: None{}
    case _: Some{NonCanonicalState{3}}

def pre_protocol_metadata(metadata:Metadata) -> Maybe<&2,Error>:
  match metadata:
    case Metadata{local,player,sprinting,pose,controls,entity, receiver, error,Nil{}}: pre_protocol_pose(pose)
    case _: Some{NonCanonicalState{2}}

def pre_protocol_frame(frame:PreFrame) -> Maybe<&2,Error>:
  match frame:
    case PreFrame{view,support,minor,history,metadata,request,stamp,Nil{}}:
      first(pre_protocol_metadata(metadata),pre_protocol_request(request))
    case _: Some{NonCanonicalRequest{}}

def pending_structure(pending:ApplyPending) -> Maybe<&2,Error>:
  match pending:
    case ApplyPending{frame,decision,early,error,Nil{}}: pre_protocol_frame(frame)
    case _: Some{NonCanonicalRequest{}}

def pending_error(pending:ApplyPending) -> Maybe<&2,Error>:
  ApplyPending{frame,decision,early,error,tail} = pending
  error

def pending_protocol(+pending:ApplyPending) -> Maybe<&2,Error>:
  first(pending_structure(pending),pending_error(pending))

def pending_remember(pending:ApplyPending,cause:Error) -> ApplyPending:
  ApplyPending{frame,decision,early,error,tail} = pending
  ApplyPending{frame,decision,early,first(error,Some{cause}),tail}

def same_stage_palette(a:Maybe<&2,W.Palette>,b:Maybe<&2,W.Palette>) -> Bool:
  match a b:
    case None{} None{}: True{}
    case Some{x} Some{y}: W.same_palette(x,y)
    case _ _: False{}

def same_stage_view(a:W.View,b:W.View) -> Bool:
  W.View{body,yaw,pitch,palette,region,cache} = a
  W.View{other,oyaw,opitch,opalette,oregion,ocache} = b
  E.same_body(body,other) && U32.is_eq(F32.bits(yaw),F32.bits(oyaw)) &&
    U32.is_eq(F32.bits(pitch),F32.bits(opitch)) && W.same_region(region,oregion) &&
    same_stage_palette(palette,opalette)

def same_stage_clock(a:C.Clock,b:C.Clock) -> Bool:
  C.Clock{tick,time,paused,daylight,revision,pending} = a
  C.Clock{otick,otime,opaused,odaylight,orevision,opending} = b
  Nat.is_eq(tick,otick) && Nat.is_eq(time,otime) && LI.same_bool(paused,opaused) &&
    LI.same_bool(daylight,odaylight) && Nat.is_eq(revision,orevision) && Nat.is_eq(pending,opending)

def same_stage_stamp(a:StageStamp,b:StageStamp) -> Bool:
  StageStamp{clock,count,events} = a
  StageStamp{other,ocount,oevents} = b
  same_stage_clock(clock,other) && U32.is_eq(count,ocount) && Nat.is_eq(events,oevents)

# Raw immutable owner-header comparisons admit the exact captured authority.
def same_stage_float(a:F32,b:F32) -> Bool:
  U32.is_eq(F32.bits(a),F32.bits(b))

def same_stage_buttons(a:PI.Buttons,b:PI.Buttons) -> Bool:
  PI.Buttons{f,bk,l,r,j,h,s} = a
  PI.Buttons{of,ob,ol,orr,oj,oh,os} = b
  LI.same_bool(f,of) && LI.same_bool(bk,ob) && LI.same_bool(l,ol) &&
    LI.same_bool(r,orr) && LI.same_bool(j,oj) && LI.same_bool(h,oh) && LI.same_bool(s,os)

def same_stage_local(a:LI.State,b:LI.State) -> Bool:
  LI.State{keys,PI.Vector{x,z},trigger,crouching,xb,yb,xo,yo} = a
  LI.State{other,PI.Vector{ox,oz},ot,oc,oxb,oyb,oxo,oyo} = b
  same_stage_buttons(keys,other) && same_stage_float(x,ox) && same_stage_float(z,oz) &&
    U32.is_eq(trigger,ot) && LI.same_bool(crouching,oc) && same_stage_float(xb,oxb) &&
    same_stage_float(yb,oyb) && same_stage_float(xo,oxo) && same_stage_float(yo,oyo)

def same_stage_player(a:PR.Metadata,b:PR.Metadata) -> Bool:
  PR.Metadata{P.Input{x,y,z},jump,delay,trigger,sync,speed,head} = a
  PR.Metadata{P.Input{ox,oy,oz},oj,od,ot,os,ov,oh} = b
  same_stage_float(x,ox) && same_stage_float(y,oy) && same_stage_float(z,oz) &&
    LI.same_bool(jump,oj) && U32.is_eq(delay,od) && U32.is_eq(trigger,ot) &&
    LI.same_bool(sync,os) && same_stage_float(speed,ov) && same_stage_float(head,oh)

def same_stage_pose(a:Pose.State,b:Pose.State) -> Bool:
  match a b:
    case Pose.State{pose,eye,Nil{}} Pose.State{other,oeye,Nil{}}:
      Pose.same_pose(pose,other) && same_stage_float(eye,oeye)
    case _ _: False{}

def same_stage_look(a:PL.State,b:PL.State) -> Bool:
  PL.State{yaw,pitch,old_yaw,old_pitch} = a
  PL.State{oy,op,opy,opp} = b
  same_stage_float(yaw,oy) && same_stage_float(pitch,op) &&
    same_stage_float(old_yaw,opy) && same_stage_float(old_pitch,opp)

def same_stage_mouse(a:MI.State,b:MI.State) -> Bool:
  MI.State{x,y,ax,ay,ignore} = a
  MI.State{ox,oy,oax,oay,oi} = b
  M.same_bits(x,ox) && M.same_bits(y,oy) && M.same_bits(ax,oax) &&
    M.same_bits(ay,oay) && LI.same_bool(ignore,oi)

def same_stage_options(a:MI.Options,b:MI.Options) -> Bool:
  MI.Options{sensitivity,x,y,smooth,scoping} = a
  MI.Options{other,ox,oy,osm,osc} = b
  M.same_bits(sensitivity,other) && LI.same_bool(x,ox) && LI.same_bool(y,oy) &&
    LI.same_bool(smooth,osm) && LI.same_bool(scoping,osc)

def same_stage_controller(a:PC.Controller,b:PC.Controller) -> Bool:
  PC.Controller{buttons,look,mouse,options} = a
  PC.Controller{other,ol,om,oo} = b
  same_stage_buttons(buttons,other) && same_stage_look(look,ol) &&
    same_stage_mouse(mouse,om) && same_stage_options(options,oo)

def same_stage_entity(a:ECT.Metadata,b:ECT.Metadata) -> Bool:
  ECT.Metadata{position,old,invulnerable,count} = a
  ECT.Metadata{op,oo,oi,oc} = b
  E.vector_bits(position,op) && E.vector_bits(old,oo) &&
    U32.is_eq(invulnerable,oi) && U32.is_eq(count,oc)

def same_stage_diagnostic(a:Maybe<&2,String>,b:Maybe<&2,String>) -> Bool:
  match a b:
    case None{} None{}: True{}
    case Some{x} Some{y}: String.eq(x,y)
    case _ _: False{}

def same_stage_metadata(a:Metadata,b:Metadata) -> Bool:
  match a b:
    case Metadata{local,player,sprint,pose,controls,entity, receiver, error,Nil{}}
         Metadata{ol,op,os,opo,oc,oe,other_receiver, oerr,Nil{}}:
      same_stage_local(local,ol) && same_stage_player(player,op) && LI.same_bool(sprint,os) &&
        same_stage_pose(pose,opo) && same_stage_controller(controls,oc) &&
        same_stage_entity(entity,oe) && RBI.same_receiver(receiver,other_receiver) && same_stage_diagnostic(error,oerr)
    case _ _: False{}

def same_stage_block(a:Maybe<&2,T.BlockPos>,b:Maybe<&2,T.BlockPos>) -> Bool:
  match a b:
    case None{} None{}: True{}
    case Some{T.BlockPos{x,y,z}} Some{T.BlockPos{ox,oy,oz}}:
      U32.is_eq(x,ox) && U32.is_eq(y,oy) && U32.is_eq(z,oz)
    case _ _: False{}

def same_stage_support(a:SP.State,b:SP.State) -> Bool:
  SP.State{main,no_blocks} = a
  SP.State{other,onb} = b
  same_stage_block(main,other) && LI.same_bool(no_blocks,onb)

def same_stage_minor(a:LM.MinorState,b:LM.MinorState) -> Bool:
  LM.MinorState{minor} = a
  LM.MinorState{other} = b
  LI.same_bool(minor,other)

def same_stage_history(a:H.History,b:H.History) -> Bool:
  H.History{distance} = a
  H.History{other} = b
  M.same_bits(distance,other)

def same_stage_header(support:SP.State,minor:LM.MinorState,history:H.History,
                      metadata:Metadata,+frame:PreFrame) -> Bool:
  same_stage_support(support,pre_frame_support(frame)) && same_stage_minor(minor,pre_frame_minor(frame)) &&
    same_stage_history(history,pre_frame_history(frame)) && same_stage_metadata(metadata,pre_frame_metadata(frame))

# Read owned authority without advancing or querying it. Return the exact stage
# (including all caches and tails) so a pre-callback refusal is lossless.
def stage_inspected_stamp(+view:W.View,tables:L.Tables,+support:SP.State,
                          +minor:LM.MinorState,+history:H.History,+metadata:Metadata,
                          owned:List<&1,MH.State>,tail:List<&1,State>,+pending:ApplyPending,
                          result:G.Engine & StageStamp) -> ApplyStage & Bool:
  (engine,stamp) = result
  +frame = pending_frame(pending)
  (ApplyStage{State{MH.State{W.attach(engine,view),support,minor,H.State{history},owned},tables,metadata,tail},pending},
    same_stage_view(view,pre_frame_view(frame)) && same_stage_stamp(stamp,pre_frame_stamp(frame)) &&
    same_stage_header(support,minor,history,metadata,frame))

def stage_inspected_view(tables:L.Tables,support:SP.State,minor:LM.MinorState,
                         history:H.History,metadata:Metadata,owned:List<&1,MH.State>,
                         tail:List<&1,State>,pending:ApplyPending,result:G.Engine & W.View) -> ApplyStage & Bool:
  (engine,view) = result
  stage_inspected_stamp(view,tables,support,minor,history,metadata,owned,tail,pending,stage_stamp(engine))

def stage_inspect(stage:ApplyStage) -> ApplyStage & Bool:
  ApplyStage{State{MH.State{world,support,minor,H.State{history},owned},tables,metadata,tail},pending} = stage
  stage_inspected_view(tables,support,minor,history,metadata,owned,tail,pending,W.take(world))

def stage_anchor(engine:G.Engine,tables:L.Tables,+frame:PreFrame) -> State:
  State{MH.State{W.attach(engine,pre_frame_view(frame)),pre_frame_support(frame),
    pre_frame_minor(frame),H.State{pre_frame_history(frame)},[]},tables,pre_frame_metadata(frame),[]}

def stage_rollback_taken(tables:L.Tables,frame:PreFrame,cause:Error,
                         result:G.Engine & W.View) -> State & Result<&2,&2,Error,Observation>:
  (engine,discarded) = result
  (stage_anchor(engine,tables,frame),Fail{cause})

def stage_rollback(state:State,pending:ApplyPending,cause:Error) -> State & Result<&2,&2,Error,Observation>:
  State{MH.State{world,support,minor,history,owned},tables,metadata,tail} = state
  stage_rollback_taken(tables,pending_frame(pending),cause,W.take(world))

def stage_query_status(state:State,pending:ApplyPending,status:Result<&2,&2,Error,ApplyFacts>) -> ApplyStage & Result<&2,&2,Error,ApplyFacts>:
  match status:
    case Fail{+cause}: (ApplyStage{state,pending_remember(pending,cause)},Fail{cause})
    case Done{facts}: (ApplyStage{state,pending},Done{facts})

# Cache changes are admitted. Body, projected angles, palette/region and standard
# Core mutation/scheduling changes are rejected. A closed read-only provider is
# still required: immutable stamp evidence is not a duplicate world snapshot.
def stage_query_guard(equal:Bool,engine:G.Engine,view:W.View,tables:L.Tables,
                      support:SP.State,minor:LM.MinorState,history:H.State,
                      metadata:Metadata,+pending:ApplyPending,
                      status:Result<&2,&2,Error,ApplyFacts>) -> ApplyStage & Result<&2,&2,Error,ApplyFacts>:
  match equal:
    case False{}:
      +cause : Error = ViewError{"apply-provider-authority-drift"}
      (ApplyStage{stage_anchor(engine,tables,pending_frame(pending)),pending_remember(pending,cause)},Fail{cause})
    case True{}:
      stage_query_status(State{MH.State{W.attach(engine,view),support,minor,history,[]},tables,metadata,[]},pending,status)

def stage_query_stamped(+view:W.View,tables:L.Tables,support:SP.State,
                        minor:LM.MinorState,history:H.State,metadata:Metadata,
                        +pending:ApplyPending,status:Result<&2,&2,Error,ApplyFacts>,
                        result:G.Engine & StageStamp) -> ApplyStage & Result<&2,&2,Error,ApplyFacts>:
  (engine,stamp) = result
  +frame = pending_frame(pending)
  stage_query_guard(same_stage_view(view,pre_frame_view(frame)) && same_stage_stamp(stamp,pre_frame_stamp(frame)),
    engine,view,tables,support,minor,history,metadata,pending,status)

def stage_query_taken(tables:L.Tables,support:SP.State,minor:LM.MinorState,
                      history:H.State,metadata:Metadata,pending:ApplyPending,
                      status:Result<&2,&2,Error,ApplyFacts>,result:G.Engine & W.View) -> ApplyStage & Result<&2,&2,Error,ApplyFacts>:
  (engine,view) = result
  stage_query_stamped(view,tables,support,minor,history,metadata,pending,status,stage_stamp(engine))

def stage_query_returned(tables:L.Tables,support:SP.State,minor:LM.MinorState,
                         history:H.State,metadata:Metadata,pending:ApplyPending,
                         result:W.State & Result<&2,&2,Error,ApplyFacts>) -> ApplyStage & Result<&2,&2,Error,ApplyFacts>:
  (world,status) = result
  stage_query_taken(tables,support,minor,history,metadata,pending,status,W.take(world))

def stage_query_ready(state:State,pending:ApplyPending,
                      operation:W.State -> SP.State -> W.State & Result<&2,&2,Error,ApplyFacts>) -> ApplyStage & Result<&2,&2,Error,ApplyFacts>:
  State{MH.State{world,+support,minor,history,owned},tables,metadata,tail} = state
  stage_query_returned(tables,support,minor,history,metadata,pending,operation(world,support))

def stage_query_inspected(operation:W.State -> SP.State -> W.State & Result<&2,&2,Error,ApplyFacts>,
                          result:ApplyStage & Bool) -> ApplyStage & Result<&2,&2,Error,ApplyFacts>:
  (ApplyStage{state,pending},equal) = result
  match equal:
    case False{}: (ApplyStage{state,pending},Fail{ViewError{"apply-provider-authority-drift"}})
    case True{}: stage_query_ready(state,pending,operation)

def stage_query_admitted(error:Maybe<&2,Error>,state:State,pending:ApplyPending,
                         operation:W.State -> SP.State -> W.State & Result<&2,&2,Error,ApplyFacts>) -> ApplyStage & Result<&2,&2,Error,ApplyFacts>:
  match error:
    case Some{cause}: (ApplyStage{state,pending},Fail{cause})
    case None{}: stage_query_inspected(operation,stage_inspect(ApplyStage{state,pending}))

def stage_query_shaped(+pending:ApplyPending,
                       operation:W.State -> SP.State -> W.State & Result<&2,&2,Error,ApplyFacts>,
                       result:State & Maybe<&2,Error>) -> ApplyStage & Result<&2,&2,Error,ApplyFacts>:
  (state,error) = result
  stage_query_admitted(first(error,pending_protocol(pending)),state,pending,operation)

def stage_query(stage:ApplyStage,
                operation:W.State -> SP.State -> W.State & Result<&2,&2,Error,ApplyFacts>) -> ApplyStage & Result<&2,&2,Error,ApplyFacts>:
  ApplyStage{state,pending} = stage
  stage_query_shaped(pending,operation,stage_shape(state))

# Reuse the original reducers after supplying actual post-control facts. The
# provider's cache is kept on success; every local failure restores PreFrame.
def stage_travel_started(engine:G.Engine,candidate:W.View,tables:L.Tables,+work:Work) -> State & Result<&2,&2,Error,Observation>:
  Work{+frame,+metadata,early,updates,+prepared,+context,tail} = work
  P.Context{travel,strength,factor,affected,mode} = context
  traveled(work,TH.travel_checked(
    MH.State{W.attach(engine,with_body(candidate,prepared_body(prepared))),frame_support(frame),frame_minor(frame),H.State{frame_history(frame)},[]},tables,
    TH.Request{prepared_input(prepared),travel,
      TH.Hooks{keys(local(metadata)),processed_input(prepared),False{},LC.NeutralDry{},True{},True{},
        Inside.multiplier(receiver(metadata)),False{},False{},True{},True{},request_environment(frame_request(frame)),request_movement_fuel(frame_request(frame)),[]},H.NotRequired{},[]}))

def stage_prepared(engine:G.Engine,candidate:W.View,+frame:Frame,+decision:LI.Controls,
                   context:P.Context,early:List<&2,PPW.QueryRecord>,
                   result:L.Tables & Result<&2,&2,LI.Error,LI.PreTravel>) -> State & Result<&2,&2,Error,Observation>:
  (tables,status) = result
  match status:
    case Fail{cause}: rollback_taken(tables,frame,InputError{cause},(engine,candidate))
    case Done{LI.PreTravel{local,value}}:
      stage_travel_started(engine,candidate,tables,Work{frame,with_local(frame_metadata(frame),local,decision_sprinting(decision)),early,decision_updates(decision),value,context,[]})

def stage_setter_gate(equal:Bool,engine:G.Engine,candidate:W.View,tables:L.Tables,
                      +frame:Frame,+decision:LI.Controls,early:List<&2,PPW.QueryRecord>,
                      +context:LI.ApplyContext) -> State & Result<&2,&2,Error,Observation>:
  match equal:
    case False{}: rollback_taken(tables,frame,SprintSetterMismatch{},(engine,candidate))
    case True{}:
      LI.ApplyContext{tick,sneak,pitch} = context
      stage_prepared(engine,candidate,frame,decision,tick,early,
        LI.prepare_checked(tables,decision,PR.compose(view_body(frame_view(frame)),player(frame_metadata(frame))),context))

def apply_sprinting(facts:ApplyFacts) -> Bool:
  ApplyFacts{ground,attrs,maximum,sprinting,no_gravity,discard,mode,strength,factor,affected,tick_mode,sneak} = facts
  sprinting

def stage_apply(engine:G.Engine,candidate:W.View,tables:L.Tables,+pending:ApplyPending,+facts:ApplyFacts) -> State & Result<&2,&2,Error,Observation>:
  +anchor = pending_frame(pending)
  +frame = pre_full_frame(anchor,facts)
  +decision = pending_decision(pending)
  +final = decision_sprinting(decision)
  stage_setter_gate(LI.same_bool(final,apply_sprinting(facts)) &&
    LI.same_bool(final,replay_setters(decision_updates(decision),sprinting(pre_frame_metadata(anchor)))),
    engine,candidate,tables,frame,decision,pending_early(pending),
    apply_context(facts,PR.look(controls(pre_frame_metadata(anchor)))))

def stage_resume_taken(tables:L.Tables,pending:ApplyPending,facts:ApplyFacts,
                      result:G.Engine & W.View) -> State & Result<&2,&2,Error,Observation>:
  (engine,candidate) = result
  stage_apply(engine,candidate,tables,pending,facts)

def stage_resume_ready(state:State,pending:ApplyPending,facts:ApplyFacts) -> State & Result<&2,&2,Error,Observation>:
  State{MH.State{world,support,minor,history,owned},tables,metadata,tail} = state
  stage_resume_taken(tables,pending,facts,W.take(world))

def stage_resume_status(state:State,pending:ApplyPending,status:Result<&2,&2,Error,ApplyFacts>) -> State & Result<&2,&2,Error,Observation>:
  match status:
    case Fail{cause}: stage_rollback(state,pending,cause)
    case Done{facts}: stage_resume_ready(state,pending,facts)

def stage_resume_protocol(error:Maybe<&2,Error>,state:State,pending:ApplyPending,
                          status:Result<&2,&2,Error,ApplyFacts>) -> State & Result<&2,&2,Error,Observation>:
  match error:
    case Some{cause}: stage_rollback(state,pending,cause)
    case None{}: stage_resume_status(state,pending,status)

def stage_resume_inspected(status:Result<&2,&2,Error,ApplyFacts>,
                           result:ApplyStage & Bool) -> State & Result<&2,&2,Error,Observation>:
  (ApplyStage{state,+pending},equal) = result
  match equal:
    case False{}: (state,Fail{ViewError{"apply-provider-authority-drift"}})
    case True{}: stage_resume_protocol(pending_error(pending),state,pending,status)

def stage_resume_structured(error:Maybe<&2,Error>,state:State,+pending:ApplyPending,
                            status:Result<&2,&2,Error,ApplyFacts>) -> State & Result<&2,&2,Error,Observation>:
  match error:
    case Some{cause}: (state,Fail{cause})
    case None{}: stage_resume_inspected(status,stage_inspect(ApplyStage{state,pending}))

def stage_resume_shaped(+pending:ApplyPending,status:Result<&2,&2,Error,ApplyFacts>,
                        result:State & Maybe<&2,Error>) -> State & Result<&2,&2,Error,Observation>:
  (state,error) = result
  match error:
    case Some{cause}: (state,Fail{cause})
    case None{}: stage_resume_structured(pending_structure(pending),state,pending,status)

def resume_apply_checked(stage:ApplyStage,status:Result<&2,&2,Error,ApplyFacts>) -> State & Result<&2,&2,Error,Observation>:
  ApplyStage{state,pending} = stage
  stage_resume_shaped(pending,status,stage_shape(state))

law staged_provider_failure_restores_complete_anchor:
  for engine:G.Engine
  for tables:L.Tables
  for +frame:PreFrame
  for candidate:W.View
  for +cause:Error
  {stage_rollback_taken(tables,frame,cause,(engine,candidate)) ==
    (stage_anchor(engine,tables,frame),Fail{cause}) : State & Result<&2,&2,Error,Observation>}

def staged_provider_failure_restores_complete_anchor(engine,tables,frame,candidate,cause):
  {==}

law staged_paused_pulse_retains_exact_owner:
  for state:State
  for request:PrepareRequest
  {pre_realtime_selected(state,request,True{}) == Paused{state} : PrepareResult}

def staged_paused_pulse_retains_exact_owner(state,request):
  {==}

law staged_precheck_refusal_retains_stage_without_calling_provider:
  for stage:ApplyStage
  for operation:W.State -> SP.State -> W.State & Result<&2,&2,Error,ApplyFacts>
  {stage_query_inspected(operation,(stage,False{})) ==
    (stage,Fail{ViewError{"apply-provider-authority-drift"}}) : ApplyStage & Result<&2,&2,Error,ApplyFacts>}

def staged_precheck_refusal_retains_stage_without_calling_provider(stage,operation):
  match stage:
    case ApplyStage{state,pending}: {==}

# Additive required-ray policy. The original CheckedNotRequired entry points
# and Error constructors above remain unchanged. A closed consumer must choose
# the declared world/tag/work policy; transport callers cannot supply it.
def reset_stage_error(cause:TH.ResetError) -> Error:
  match cause:
    case TH.ResetTravelError{error}: TravelError{error}
    case TH.ResetSupplierError{error}: ViewError{"local-phase-reset:" ++ TH.reset_error_text(TH.ResetSupplierError{error})}
    case TH.ResetHistoryError{error}: TravelError{TH.MovementError{MH.HistoryError{error}}}

def reset_stage_traveled(+work:Work,
                         result:MH.State & L.Tables & Result<&2,&2,TH.ResetError,TH.ResetOutcome>) -> State & Result<&2,&2,Error,Observation>:
  (motion,tables,status) = result
  match status:
    case Fail{cause}: rollback(motion,tables,work_frame(work),reset_stage_error(cause))
    case Done{+outcome}: travel_outer_finished(work,motion,tables,TH.reset_outcome_travel(outcome),
      P.finish_checked(work_prepared(work),work_context(work),TH.reset_outcome_transition(outcome)))

def ability_history_gate(history:H.History,flying:Bool) -> H.History:
  match flying:
    case False{}: history
    case True{}: H.History{M.zero()}


def ability_history(history:H.History,mode:P.Mode) -> H.History:
  ability_history_gate(history,P.mode_flying(mode))



def ability_history_mode_gate(mayfly:Bool) -> H.Mode:
  match mayfly:
    case False{}: H.NeutralDryNoDamage{}
    case True{}: H.DryImmuneLanding{}


def ability_history_mode(mode:P.Mode) -> H.Mode:
  ability_history_mode_gate(P.mode_mayfly(mode))



def reset_stage_travel_started(engine:G.Engine,candidate:W.View,tables:L.Tables,
                               +work:Work,policy:TH.ResetPolicy) -> State & Result<&2,&2,Error,Observation>:
  Work{+frame,+metadata,early,updates,+prepared,+context,tail} = work
  P.Context{travel,strength,factor,affected,+mode} = context
  reset_stage_traveled(work,TH.ability_travel_with_reset_checked(ability_history_mode(mode),
    MH.State{W.attach(engine,with_body(candidate,prepared_body(prepared))),frame_support(frame),frame_minor(frame),H.State{ability_history(frame_history(frame),mode)},[]},tables,
    TH.ResetRequest{prepared_input(prepared),travel,
      TH.Hooks{keys(local(metadata)),processed_input(prepared),P.mode_flying(mode),LC.NeutralDry{},True{},True{},
        Inside.multiplier(receiver(metadata)),False{},False{},True{},True{},request_environment(frame_request(frame)),request_movement_fuel(frame_request(frame)),[]},policy,[]}))



def reset_stage_prepared(engine:G.Engine,candidate:W.View,+frame:Frame,+decision:LI.Controls,
                         context:P.Context,early:List<&2,PPW.QueryRecord>,policy:TH.ResetPolicy,
                         result:L.Tables & Result<&2,&2,LI.Error,LI.PreTravel>) -> State & Result<&2,&2,Error,Observation>:
  (tables,status) = result
  match status:
    case Fail{cause}: rollback_taken(tables,frame,InputError{cause},(engine,candidate))
    case Done{LI.PreTravel{local,value}}:
      reset_stage_travel_started(engine,candidate,tables,
        Work{frame,with_local(frame_metadata(frame),local,decision_sprinting(decision)),early,decision_updates(decision),value,context,[]},policy)

def reset_stage_setter_gate(equal:Bool,engine:G.Engine,candidate:W.View,tables:L.Tables,
                            +frame:Frame,+decision:LI.Controls,early:List<&2,PPW.QueryRecord>,
                            +context:LI.ApplyContext,policy:TH.ResetPolicy) -> State & Result<&2,&2,Error,Observation>:
  match equal:
    case False{}: rollback_taken(tables,frame,SprintSetterMismatch{},(engine,candidate))
    case True{}:
      LI.ApplyContext{tick,sneak,pitch} = context
      reset_stage_prepared(engine,candidate,frame,decision,tick,early,policy,
        LI.prepare_checked(tables,decision,PR.compose(view_body(frame_view(frame)),player(frame_metadata(frame))),context))

def reset_stage_apply(engine:G.Engine,candidate:W.View,tables:L.Tables,+pending:ApplyPending,
                      +facts:ApplyFacts,policy:TH.ResetPolicy) -> State & Result<&2,&2,Error,Observation>:
  +anchor = pending_frame(pending)
  +frame = pre_full_frame(anchor,facts)
  +decision = pending_decision(pending)
  +final = decision_sprinting(decision)
  reset_stage_setter_gate(LI.same_bool(final,apply_sprinting(facts)) &&
    LI.same_bool(final,replay_setters(decision_updates(decision),sprinting(pre_frame_metadata(anchor)))),
    engine,candidate,tables,frame,decision,pending_early(pending),
    apply_context(facts,PR.look(controls(pre_frame_metadata(anchor)))),policy)

def reset_stage_resume_taken(tables:L.Tables,pending:ApplyPending,facts:ApplyFacts,
                             policy:TH.ResetPolicy,result:G.Engine & W.View) -> State & Result<&2,&2,Error,Observation>:
  (engine,candidate) = result
  reset_stage_apply(engine,candidate,tables,pending,facts,policy)

def reset_stage_resume_ready(state:State,pending:ApplyPending,facts:ApplyFacts,
                             policy:TH.ResetPolicy) -> State & Result<&2,&2,Error,Observation>:
  State{MH.State{world,support,minor,history,owned},tables,metadata,tail} = state
  reset_stage_resume_taken(tables,pending,facts,policy,W.take(world))

def reset_stage_resume_status(state:State,pending:ApplyPending,
                              status:Result<&2,&2,Error,ApplyFacts>,policy:TH.ResetPolicy) -> State & Result<&2,&2,Error,Observation>:
  match status:
    case Fail{cause}: stage_rollback(state,pending,cause)
    case Done{facts}: reset_stage_resume_ready(state,pending,facts,policy)

def reset_stage_resume_protocol(error:Maybe<&2,Error>,state:State,pending:ApplyPending,
                                status:Result<&2,&2,Error,ApplyFacts>,policy:TH.ResetPolicy) -> State & Result<&2,&2,Error,Observation>:
  match error:
    case Some{cause}: stage_rollback(state,pending,cause)
    case None{}: reset_stage_resume_status(state,pending,status,policy)

def reset_stage_resume_inspected(status:Result<&2,&2,Error,ApplyFacts>,policy:TH.ResetPolicy,
                                 result:ApplyStage & Bool) -> State & Result<&2,&2,Error,Observation>:
  (ApplyStage{state,+pending},equal) = result
  match equal:
    case False{}: (state,Fail{ViewError{"apply-provider-authority-drift"}})
    case True{}: reset_stage_resume_protocol(pending_error(pending),state,pending,status,policy)

def reset_stage_resume_structured(error:Maybe<&2,Error>,state:State,+pending:ApplyPending,
                                  status:Result<&2,&2,Error,ApplyFacts>,policy:TH.ResetPolicy) -> State & Result<&2,&2,Error,Observation>:
  match error:
    case Some{cause}: (state,Fail{cause})
    case None{}: reset_stage_resume_inspected(status,policy,stage_inspect(ApplyStage{state,pending}))

def reset_stage_resume_shaped(+pending:ApplyPending,status:Result<&2,&2,Error,ApplyFacts>,
                              policy:TH.ResetPolicy,result:State & Maybe<&2,Error>) -> State & Result<&2,&2,Error,Observation>:
  (state,error) = result
  match error:
    case Some{cause}: (state,Fail{cause})
    case None{}: reset_stage_resume_structured(pending_structure(pending),state,pending,status,policy)

# Preparation/provider admission is exactly the existing staged path. Only the
# admitted travel dispatcher differs: LM forms its immutable candidate, the
# real required ray runs before history completion/commit, H updates once, and
# travel finish precedes unchanged player finish/rotation/late pose. This is a
# fixed neutral read-only ordering equivalence; observable callbacks are outside
# admission. Every admitted failure rolls back PreFrame.
def resume_apply_with_reset_checked(stage:ApplyStage,status:Result<&2,&2,Error,ApplyFacts>,
                                    policy:TH.ResetPolicy) -> State & Result<&2,&2,Error,Observation>:
  ApplyStage{state,pending} = stage
  reset_stage_resume_shaped(pending,status,policy,stage_shape(state))

law reset_resume_structural_refusal_retains_exact_owner:
  for state:State
  for pending:ApplyPending
  for status:Result<&2,&2,Error,ApplyFacts>
  for policy:TH.ResetPolicy
  for +cause:Error
  {reset_stage_resume_shaped(pending,status,policy,(state,Some{cause})) ==
    (state,Fail{cause}) : State & Result<&2,&2,Error,Observation>}

def reset_resume_structural_refusal_retains_exact_owner(state,pending,status,policy,cause):
  {==}

law reset_provider_failure_uses_complete_pre_frame_anchor:
  for state:State
  for pending:ApplyPending
  for policy:TH.ResetPolicy
  for cause:Error
  {reset_stage_resume_status(state,pending,Fail{cause},policy) ==
    stage_rollback(state,pending,cause) : State & Result<&2,&2,Error,Observation>}

def reset_provider_failure_uses_complete_pre_frame_anchor(state,pending,policy,cause):
  {==}
