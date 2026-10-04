import Base
import ./local_phase_runtime.bend as X
import ./local_player_record.bend as Record
import ./player_record.bend as Saved
import ./player_codec.bend as Codec
import ./player_runtime.bend as PR
import ./local_move_history.bend as MH
import ./local_move_world.bend as LM
import ./local_travel_history.bend as TH
import ./local_input.bend as LI
import ./player_tick.bend as P
import ./player_pose.bend as Pose
import ./player_pose_world.bend as PPW
import ./player_fall_history.bend as H
import ./entity_common_tick.bend as ECT
import ./player_rotation_tick.bend as Rotation
import ./player_controls.bend as PC
import ./player_input.bend as PI
import ./player_look.bend as PL
import ./mouse_input.bend as MI
import ./client_controls.bend as CC
import ./client_world.bend as W
import ./client_render.bend as Render
import ./support.bend as SP
import ./support_world.bend as SW
import ./local_collision_world.bend as E
import ./travel.bend as T
import ./movement.bend as M
import ./locomotion.bend as L
import ./f64.bend as F
import ./geometry.bend as A
import ./game.bend as G
import ./core.bend as C
import ./registry.bend as B

# X.State is the only runtime owner; this facade introduces no Body/Engine state.
# A bundle detour carries every unsaved field and every forged owned/Data tail.
type Transient is Type:
  Transient{tables: L.Tables, palette: Maybe<&2, W.Palette>, region: W.Bounds,
    cache: Maybe<&2, W.SnapshotCache>, buttons: PI.Buttons, mouse: MI.State,
    options: MI.Options, error: Maybe<&2, String>, state_tail: List<&1, X.State>,
    motion_tail: List<&1, MH.State>, metadata_tail: List<&2, X.Metadata>}

# Closed neutral client policy. Numerical ApplyFacts are not transport inputs.
type Driver is Data:
  Driver{request: X.PrepareRequest}

# Recursive Data boxes bound native continuations without owning another world.
type RenderFrame is Data:
  RenderFrame{view: W.View, origin: M.Vec3, tail: List<&2, RenderFrame>}

def detached_view(tables: L.Tables, support: SP.State, minor: LM.MinorState,
                  history: H.History, metadata: X.Metadata,
                  state_tail: List<&1, X.State>, motion_tail: List<&1, MH.State>,
                  result: G.Engine & W.View) -> G.Engine & Record.Record & Transient:
  X.Metadata{local, player, sprinting, pose, PC.Controller{buttons, look, mouse, options}, entity, error, metadata_tail} = metadata
  (engine, W.View{body, yaw, pitch, palette, region, cache}) = result
  (engine, Record.Record{Saved.Record{Codec.Snapshot{PR.compose(body, player), support, yaw, pitch, "minecraft:overworld"}, look}, local, sprinting, pose, minor, history, entity},
    Transient{tables, palette, region, cache, buttons, mouse, options, error, state_tail, motion_tail, metadata_tail})

def detach(state: X.State) -> G.Engine & Record.Record & Transient:
  X.State{MH.State{world, support, minor, H.State{history}, motion_tail}, tables, metadata, state_tail} = state
  detached_view(tables, support, minor, history, metadata, state_tail, motion_tail, W.take(world))

def attach(engine: G.Engine, record: Record.Record, transient: Transient) -> X.State:
  Record.Record{Saved.Record{Codec.Snapshot{+player, support, yaw, pitch, dimension}, look}, local, sprinting, pose, minor, history, entity} = record
  Transient{tables, palette, region, cache, buttons, mouse, options, error, state_tail, motion_tail, metadata_tail} = transient
  X.State{MH.State{W.State{engine, PR.player_body(player), yaw, pitch, palette, region, cache}, support, minor, H.State{history}, motion_tail}, tables,
    X.Metadata{local, PR.metadata(player), sprinting, pose, PC.Controller{buttons, look, mouse, options}, entity, error, metadata_tail}, state_tail}

def reattach(result: G.Engine & Record.Record & Transient) -> X.State:
  (engine, record, transient) = result
  attach(engine, record, transient)

def recorded(result: G.Engine & Record.Record & Transient) -> X.State & Record.Record:
  (engine, +record, transient) = result
  (attach(engine, record, transient), record)

# This unconditional projection and detour are lossless, not save admission.
def record(state: X.State) -> X.State & Record.Record:
  recorded(detach(state))

def canonical(state: X.State) -> X.State & Bool:
  match state:
    case X.State{MH.State{world, support, minor, history, Nil{}}, tables,
      X.Metadata{local, player, sprinting, pose, controls, entity, error, Nil{}}, Nil{}}:
      (X.State{MH.State{world, support, minor, history, []}, tables,
        X.Metadata{local, player, sprinting, pose, controls, entity, error, []}, []}, True{})
    case other: (other, False{})

def string_result(-E: Data, -A: Data, format: E -> String, result: Result<&2, &2, E, A>) -> Result<&2, &2, String, A>:
  match result:
    case Fail{error}: Fail{format(error)}
    case Done{value}: Done{value}

def checked_record(result: X.State & Record.Record) -> X.State & Result<&2, &2, String, Record.Record>:
  (state, value) = result
  (state, string_result(Record.Error, Record.Record, Record.error_text, Record.validate(value)))

def record_gate(valid: Bool, state: X.State) -> X.State & Result<&2, &2, String, Record.Record>:
  match valid:
    case False{}: (state, Fail{"noncanonical local-player runtime ownership or metadata tail"})
    case True{}: checked_record(record(state))

def record_canonical(result: X.State & Bool) -> X.State & Result<&2, &2, String, Record.Record>:
  (state, valid) = result
  record_gate(valid, state)

def record_checked(state: X.State) -> X.State & Result<&2, &2, String, Record.Record>:
  record_canonical(canonical(state))

def restored_transient(transient: Transient) -> Transient:
  Transient{tables, palette, region, cache, buttons, mouse, options, error, owned, motion, metadata} = transient
  Transient{tables, palette, region, cache, PI.empty(), MI.initial(), options, None{}, owned, motion, metadata}

def restore_detached(value: Record.Record, result: G.Engine & Record.Record & Transient) -> X.State & Result<&2, &2, String, Unit>:
  (engine, old_record, transient) = result
  (attach(engine, value, restored_transient(transient)), Done{Unit{}})

def restore_validated(state: X.State, result: Result<&2, &2, Record.Error, Record.Record>) -> X.State & Result<&2, &2, String, Unit>:
  match result:
    case Fail{error}: (state, Fail{Record.error_text(error)})
    case Done{value}: restore_detached(value, detach(state))

def restore_gate(valid: Bool, state: X.State, value: Record.Record) -> X.State & Result<&2, &2, String, Unit>:
  match valid:
    case False{}: (state, Fail{"noncanonical local-player restore owner"})
    case True{}: restore_validated(state, Record.validate(value))

# Startup admission is atomic. LI previous sampled keys and all durable history
# remain exact; only actual physical buttons/mouse and diagnostics are cleared.
def restore_canonical(value: Record.Record, result: X.State & Bool) -> X.State & Result<&2, &2, String, Unit>:
  (state, valid) = result
  restore_gate(valid, state, value)

def restore(state: X.State, value: Record.Record) -> X.State & Result<&2, &2, String, Unit>:
  restore_canonical(value, canonical(state))

def fresh_taken(tables: L.Tables, result: G.Engine & W.View) -> X.State:
  (engine, W.View{+body, yaw, pitch, palette, region, cache}) = result
  +position = X.body_position(body)
  X.State{MH.State{W.State{engine, body, 0.0, 0.0, palette, region, cache}, SP.State{None{}, False{}}, LM.MinorState{False{}}, H.State{H.History{F.from_u32(0)}}, []}, tables,
    X.Metadata{LI.initial(), PR.Metadata{P.Input{0.0, 0.0, 0.0}, False{}, 0, 0, False{}, 0.0, 0.0}, False{},
      Pose.State{Pose.Standing{}, L.float_bits(1070554153), []}, PC.Controller{PI.empty(), PL.State{0.0, 0.0, 0.0, 0.0}, MI.initial(), MI.default_options()},
      ECT.Metadata{position, position, 0, 0}, None{}, []}, []}

# No terrain or owner duplication; caller supplies the existing standing Body.
def fresh(world: W.State, tables: L.Tables) -> X.State:
  fresh_taken(tables, W.take(world))

def query(-A: Type, state: X.State, operation: W.State -> W.State & A) -> X.State & A:
  X.query(A, state, operation)

def release(state: X.State) -> X.State:
  X.release(state)

def pose_error_text(error: Pose.Error) -> String:
  match error:
    case Pose.NonCanonicalTail{owner}: "pose-tail:" ++ U32.show(owner)
    case Pose.UnsupportedContext{}: "pose-context"
    case Pose.UnsupportedScale{}: "pose-scale"
    case Pose.UnsupportedAge{}: "pose-age"
    case Pose.UnknownPose{id}: "pose-unknown:" ++ U32.show(id)
    case Pose.InvalidBody{cause}: "pose-invalid-body"
    case Pose.StaleDimensions{}: "pose-dimensions"
    case Pose.StaleEyeHeight{}: "pose-eye"
    case Pose.StaleBox{}: "pose-box"
    case Pose.InvalidQuery{field}: "pose-query:" ++ U32.show(field)
    case Pose.MismatchedPose{}: "pose-answer-pose"
    case Pose.MismatchedQuery{}: "pose-answer-query"
    case Pose.QueryDenied{reason}: reason
    case Pose.MissingObservation{}: "pose-answer-missing"
    case Pose.ExtraObservations{}: "pose-answer-extra"
    case Pose.UnexpectedAnswer{}: "pose-answer-unexpected"
    case Pose.InvalidProgress{}: "pose-progress"

def pose_world_error_text(error: PPW.Error) -> String:
  match error:
    case PPW.NonCanonicalTail{}: "pose-world-tail"
    case PPW.PoseError{cause}: pose_error_text(cause)
    case PPW.WorldError{cause}: E.error_text(cause)
    case PPW.BodyOutsideInterior{}: "pose-body-outside-interior"
    case PPW.QueryBudget{}: "pose-query-budget"

def entity_error_text(error: ECT.Error) -> String:
  match error:
    case ECT.NonCanonicalState{}: "entity-owner-tail"
    case ECT.NonCanonicalRequest{}: "entity-request-tail"
    case ECT.UnsupportedContext{context}: "entity-common-context"
    case ECT.NonFinite{field}: "entity-nonfinite:" ++ U32.show(field)

def input_error_text(error: LI.Error) -> String:
  match error:
    case LI.UnsupportedContext{mode}: "local-input-context"
    case LI.UnsupportedPose{}: "local-input-pose"
    case LI.UnsupportedAbilities{}: "local-input-abilities"
    case LI.InvalidState{field}: "local-input-state:" ++ U32.show(field)
    case LI.InvalidAttribute{}: "local-input-attribute"
    case LI.InvalidPitch{}: "local-input-pitch"
    case LI.SprintContextMismatch{}: "local-input-sprint-context"
    case LI.PlayerError{cause}: "local-input-player-preparation"

def history_error_text(error: H.Error) -> String:
  match error:
    case H.NonFinite{field}: "fall-nonfinite:" ++ U32.show(field)
    case H.InvalidLengthSquared{}: "fall-length"
    case H.UnsupportedMode{mode}: "fall-context"
    case H.MissingClipObservation{}: "fall-reset-ray-required"
    case H.UnexpectedClipObservation{}: "fall-reset-ray-unexpected"
    case H.UnsupportedResetHit{}: "fall-reset-hit"
    case H.UnsupportedLanding{}: "fall-damage-required"
    case H.NonFiniteResult{}: "fall-nonfinite-result"

def motion_error_text(error: MH.Error) -> String:
  match error:
    case MH.NonCanonicalState{}: "motion-owner-tail"
    case MH.NonCanonicalRequest{field}: "motion-request-tail:" ++ U32.show(field)
    case MH.HistoryMismatch{}: "motion-history-mismatch"
    case MH.MoveError{cause}: LM.error_text(cause)
    case MH.HistoryError{cause}: history_error_text(cause)

def travel_error_text(error: TH.Error) -> String:
  match error:
    case TH.NonCanonicalState{}: "travel-owner-tail"
    case TH.NonCanonicalRequest{field}: "travel-request-tail:" ++ U32.show(field)
    case TH.PreparationError{cause}: "travel-preparation"
    case TH.MovementError{cause}: motion_error_text(cause)
    case TH.FinishError{cause}: "travel-finish"

def error_text(error: X.Error) -> String:
  match error:
    case X.NonCanonicalState{field}: "local-player-tail:" ++ U32.show(field)
    case X.NonCanonicalRequest{}: "local-player-request-tail"
    case X.LifecycleError{field}: "local-player-lifecycle:" ++ U32.show(field)
    case X.EntityError{cause}: entity_error_text(cause)
    case X.ControllerError{cause}: PC.describe_error(cause)
    case X.PoseError{cause}: pose_error_text(cause)
    case X.UnsupportedStablePose{}: "local-player-pose-needs-unsupported-locomotion"
    case X.ControlWorldError{cause}: E.error_text(cause)
    case X.ControlBudget{}: "local-control-query-budget"
    case X.InputError{cause}: input_error_text(cause)
    case X.SprintSetterMismatch{}: "local-sprint-setter-mismatch"
    case X.TravelError{cause}: travel_error_text(cause)
    case X.FinishError{cause}: "local-player-finish"
    case X.RotationError{cause}: "local-player-rotation"
    case X.PoseWorldError{cause}: pose_world_error_text(cause)
    case X.ViewError{reason}: reason

def input_result(result: X.State & Result<&2, &2, X.Error, Unit>) -> X.State & Result<&2, &2, String, Unit>:
  (state, status) = result
  (state, string_result(X.Error, Unit, error_text, status))

def input(state: X.State, bindings: PI.Bindings, packet: CC.Packet) -> X.State & Result<&2, &2, String, Unit>:
  input_result(X.input_checked(state, bindings, packet))

def driver() -> Driver:
  Driver{X.PrepareRequest{X.NeutralDryLoadedNoParticles{}, ECT.NeutralClientInactiveInterpolation{},
    X.ControlFacts{20, LI.Abilities{False{}, False{}}, False{}, 7, LI.Neutral{}},
    E.Environment{E.KnownEmptyEntityCollisions{}, E.KnownClearBorderInterior{A.AABB{F.from_i32(4294967232), F.from_i32(4294967232), F.from_i32(4294967232), F.from_u32(64), F.from_u32(64), F.from_u32(64)}}},
    2n, 512n, 4096n, 3n, []}}

# Raw attribute values observed at untouched LocalPlayer.travel entry. The fixed
# profile excludes equipment/effects/modifiers besides the actual sprint setter.
def attributes(sprinting: Bool) -> T.Attributes:
  T.Attributes{W.choose(F.F64, F.F64{1069589463, 284541584}, F.F64{1069128089, 2684354560}, sprinting),
    F.F64{1068792545, 1202590843}, F.from_u32(1), F.from_u32(1)}

def apply_sample(+sprinting: Bool, result: W.State & Result<&2, &2, SW.Error, SW.Sample>) -> W.State & Result<&2, &2, X.Error, X.ApplyFacts>:
  (world, status) = result
  match status:
    case Fail{cause}: (world, Fail{X.ViewError{SW.error_text(cause)}})
    case Done{SW.Sample{ground, factor}}:
      (world, Done{X.ApplyFacts{ground, attributes(sprinting), L.float_bits(1058642330), sprinting, False{}, False{}, T.NeutralDryAir{},
        F.F64{1071309127, 2684354560}, factor, True{}, P.Neutral{}, F.F64{1070805811, 858993459}}})

def apply_provider(sprinting: Bool, world: W.State, support: SP.State) -> W.State & Result<&2, &2, X.Error, X.ApplyFacts>:
  apply_sample(sprinting, SW.sample_checked(world, support))

def with_error(state: X.State, error: Maybe<&2, String>) -> X.State:
  X.State{motion, tables, X.Metadata{local, player, sprinting, pose, controls, entity, old, tail}, owned} = state
  X.State{motion, tables, X.Metadata{local, player, sprinting, pose, controls, entity, error, tail}, owned}

def tick_result(result: X.State & Result<&2, &2, X.Error, X.Observation>) -> X.State:
  (state, status) = result
  match status:
    case Fail{cause}: with_error(state, Some{error_text(cause)})
    case Done{value}: with_error(state, None{})

def apply_resolved(result: X.ApplyStage & Result<&2, &2, X.Error, X.ApplyFacts>) -> X.State:
  (stage, status) = result
  tick_result(X.resume_apply_checked(stage, status))

def intent_ready(result: X.ApplyStage & X.ApplyIntent) -> X.State:
  (stage, X.ApplyIntent{sprinting, updates}) = result
  apply_resolved(X.stage_query(stage, world => support => apply_provider(sprinting, world, support)))

def prepared_tick(result: X.PrepareResult) -> X.State:
  match result:
    case X.Rejected{state, error}: with_error(state, Some{error_text(error)})
    case X.Paused{state}: state
    case X.AwaitApply{stage}: intent_ready(X.stage_intent(stage))

def step(driver: Driver, state: X.State) -> X.State:
  Driver{request} = driver
  prepared_tick(X.prepare_scheduled_checked(state, request))

def realtime_step(driver: Driver, state: X.State) -> X.State:
  Driver{request} = driver
  prepared_tick(X.prepare_realtime_checked(state, request))

def advance(~driver: Driver, ticks: Nat, state: X.State) -> X.State:
  match ticks:
    case 0n: state
    case 1n+rest: advance(~driver, rest, step(driver, state))

def eye_result(result: X.State & Result<&2, &2, Pose.Error, M.Vec3>) -> X.State & Result<&2, &2, String, M.Vec3>:
  (state, status) = result
  (state, string_result(Pose.Error, M.Vec3, pose_error_text, status))

def eye(state: X.State) -> X.State & Result<&2, &2, String, M.Vec3>:
  eye_result(X.eye_position_checked(state))

def frame_view(frame: RenderFrame) -> W.View:
  RenderFrame{view, origin, tail} = frame
  view

def frame_region(frame: RenderFrame) -> W.Bounds:
  RenderFrame{W.View{body,yaw,pitch,palette,region,cache},origin,tail} = frame
  region

def raw_snapshot_success(registry: B.Registry, frame: RenderFrame, tick: Nat, +revision: Nat,
                         core: C.World, +blocks: List<&2, W.RawBlock>) -> W.State & Result<&2, &2, String, Render.Snapshot>:
  RenderFrame{W.View{body, +yaw, +pitch, +palette, +region, cache}, origin, tail} = frame
  (W.attach(G.Engine{core, registry}, W.View{body, yaw, pitch, palette, region, W.cache_value(palette, revision, region, blocks)}),
    Done{Render.Snapshot{tick, revision, W.relative_blocks(blocks, origin), Render.Camera{0.0, 0.0, 0.0, yaw, pitch}}})

def raw_snapshot_status(registry: B.Registry, +frame: RenderFrame, tick: Nat, +revision: Nat,
                        result: C.World & Result<&2, &2, String, List<&2, W.RawBlock>>) -> W.State & Result<&2, &2, String, Render.Snapshot>:
  (core, status) = result
  match status:
    case Fail{reason}: (W.attach(G.Engine{core, registry}, frame_view(frame)), Fail{reason})
    case Done{blocks}: raw_snapshot_success(registry, frame, tick, revision, core, blocks)

def raw_snapshot_found(registry: B.Registry, +frame: RenderFrame, tick: Nat, revision: Nat,
                       palette: W.Palette, core: C.World, found: Maybe<&2, List<&2, W.RawBlock>>) -> W.State & Result<&2, &2, String, Render.Snapshot>:
  match found:
    case Some{blocks}: raw_snapshot_status(registry, frame, tick, revision, (core, Done{blocks}))
    case None{}:
      +region = frame_region(frame)
      raw_snapshot_status(registry, frame, tick, revision, W.sample(U32.to_nat(W.volume(region)), 0, region, palette, core, Done{[]}))

def raw_snapshot_view(registry: B.Registry, +frame: RenderFrame, tick: Nat, +revision: Nat,
                      core: C.World, view: W.View) -> W.State & Result<&2, &2, String, Render.Snapshot>:
  W.View{body, yaw, pitch, palette, region, cache} = view
  match palette:
    case None{}: (W.attach(G.Engine{core, registry}, frame_view(frame)), Fail{"palette-unavailable"})
    case Some{+actual}: raw_snapshot_found(registry, frame, tick, revision, actual, core, W.cached_blocks(cache, revision, region, actual))

def raw_snapshot_clocked(registry: B.Registry, +frame: RenderFrame, result: C.World & C.Clock) -> W.State & Result<&2, &2, String, Render.Snapshot>:
  (core, C.Clock{tick, time, paused, daylight, revision, pending}) = result
  raw_snapshot_view(registry,frame,tick,revision,core,frame_view(frame))

def raw_snapshot_taken(origin: M.Vec3, result: G.Engine & W.View) -> W.State & Result<&2, &2, String, Render.Snapshot>:
  (G.Engine{core, registry}, view) = result
  raw_snapshot_clocked(registry, RenderFrame{view, origin, []}, C.clock(core))

def raw_snapshot_gate(valid: Bool, world: W.State, origin: M.Vec3) -> W.State & Result<&2, &2, String, Render.Snapshot>:
  match valid:
    case False{}: (world, Fail{"invalid-relative-camera"})
    case True{}: raw_snapshot_taken(origin, W.take(world))

def raw_snapshot(world: W.State, +origin: M.Vec3) -> W.State & Result<&2, &2, String, Render.Snapshot>:
  W.State{engine, body, +yaw, +pitch, palette, region, cache} = world
  raw_snapshot_gate(W.finite_relative_origin(origin) && PL.finite(yaw) && PL.finite(pitch), W.State{engine, body, yaw, pitch, palette, region, cache}, origin)

def snapshot_eye(result: X.State & Result<&2, &2, String, M.Vec3>) -> X.State & Result<&2, &2, String, Render.Snapshot>:
  (state, status) = result
  match status:
    case Fail{cause}: (state, Fail{cause})
    case Done{origin}: query(Result<&2, &2, String, Render.Snapshot>, state, world => raw_snapshot(world, origin))

# Exact signed cells minus authoritative F64 cached-eye origin BEFORE narrowing.
# No body shift, post-F32 correction, tick, or cache update on a failed sample.
def snapshot(state: X.State, width: U32, height: U32) -> X.State & Result<&2, &2, String, Render.Snapshot>:
  snapshot_eye(eye(state))

law bundle_detour_preserves_every_owner_and_field:
  for state: X.State
  {reattach(detach(state)) == state : X.State}

def bundle_detour_preserves_every_owner_and_field(state):
  match state:
    case X.State{MH.State{W.State{engine,body,yaw,pitch,palette,region,cache},support,minor,H.State{history},motion_tail},tables,
      X.Metadata{local,PR.Metadata{input,jumping,delay,trigger,sync,speed,head},sprinting,pose,
        PC.Controller{buttons,look,mouse,options},entity,error,metadata_tail},state_tail}: {==}

law stopped_schedule_preserves_every_owner_and_field:
  for state: X.State
  {advance(~driver(),0n,state) == state : X.State}

def stopped_schedule_preserves_every_owner_and_field(state):
  {==}
