import Base
import ./player_pose.bend as P
import ./local_collision_world.bend as E
import ./client_world.bend as W
import ./movement.bend as M
import ./geometry.bend as A
import ./core.bend as C
import ./game.bend as G
import ./registry.bend as B

# Conditional late pose update. World is the only Body/Core owner; pose and
# cached eye are separate Data. No caller collision answers or simulation tick.
type Request is Data:
  Request{context: P.Context, environment: E.Environment, fuel: Nat,
          tail: List<&2, Request>}

type Error is Data:
  NonCanonicalTail{}
  PoseError{cause: P.Error}
  WorldError{cause: E.Error}
  BodyOutsideInterior{}
  QueryBudget{}

type QueryRecord is Data:
  QueryRecord{pose: P.Pose, world: E.QueryRecord}

type Observation is Data:
  Observation{transition: P.Transition, queries: List<&2, QueryRecord>,
              tail: List<&2, Observation>}

# Recursive Data boxes avoid flattening the complete original View and Body
# across native continuations. Internal tails are always empty.
type Frame is Data:
  Frame{view: W.View, pose: P.State, environment: E.Environment,
        reversed: List<&2, QueryRecord>, tail: List<&2, Frame>}

def frame_view(frame: Frame) -> W.View:
  Frame{view, pose, environment, reversed, tail} = frame
  view

def frame_pose(frame: Frame) -> P.State:
  Frame{view, pose, environment, reversed, tail} = frame
  pose

def frame_environment(frame: Frame) -> E.Environment:
  Frame{view, pose, environment, reversed, tail} = frame
  environment

def body_box(body: M.Body) -> A.AABB:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = body
  box

def with_body(view: W.View, body: M.Body) -> W.View:
  W.View{old, yaw, pitch, palette, region, cache} = view
  W.View{body, yaw, pitch, palette, region, cache}

def transition_body(transition: P.Transition) -> M.Body:
  P.Transition{state, body, desired, selected, changed, refreshed, queries, tail} = transition
  body

def transition_state(transition: P.Transition) -> P.State:
  P.Transition{state, body, desired, selected, changed, refreshed, queries, tail} = transition
  state

def pose_progress(result: Result<&2, &2, P.Error, P.Progress>) -> Result<&2, &2, Error, P.Progress>:
  match result:
    case Fail{error}: Fail{PoseError{error}}
    case Done{progress}: Done{progress}

def record_clear(record: E.QueryRecord) -> Bool:
  E.QueryRecord{box, clear, yielded, reads} = record
  clear

def appended(frame: Frame, pose: P.Pose, record: E.QueryRecord) -> Frame:
  Frame{view, prior, environment, reversed, tail} = frame
  Frame{view, prior, environment, QueryRecord{pose, record} <> reversed, []}

def query_finished(frame: Frame, progress: P.Progress, +pose: P.Pose,
                   +box: A.AABB, result: C.World & Result<&2, &2, E.Error, E.QueryRecord>) -> C.World & Frame & Result<&2, &2, Error, P.Progress>:
  match result:
    case (world, Fail{error}): (world, frame, Fail{WorldError{error}})
    case (world, Done{+record}):
      (world, appended(frame, pose, record),
        pose_progress(P.answer_checked(progress, P.FitAnswer{pose, box, Done{record_clear(record)}})))

def loop(fuel: Nat, +palette: W.Palette, frame: Frame, world: C.World,
         progress: Result<&2, &2, Error, P.Progress>) -> C.World & Result<&2, &2, Error, Observation>:
  match fuel frame progress:
    case _ _ Fail{error}: (world, Fail{error})
    case _ Frame{view, pose, environment, reversed, tail} Done{P.Finished{transition, Nil{}}}:
      (world, Done{Observation{transition, List.reverse(&2, QueryRecord, reversed), []}})
    case _ _ Done{P.Finished{transition, _ <> _}}: (world, Fail{PoseError{P.NonCanonicalTail{2}}})
    case _ _ Done{P.Query{work, _ <> _}}: (world, Fail{PoseError{P.NonCanonicalTail{2}}})
    case 0n _ Done{P.Query{work, Nil{}}}: (world, Fail{QueryBudget{}})
    case 1n+rest Frame{view, prior, +environment, reversed, tail} Done{P.Query{P.Work{request, phase, desired, P.FitQuery{+pose, +box}, history}, Nil{}}}:
      W.paired(C.World, Frame & Result<&2, &2, Error, P.Progress>, C.World & Result<&2, &2, Error, Observation>,
        query_finished(Frame{view, prior, environment, reversed, []}, P.Query{P.Work{request, phase, desired, P.FitQuery{pose, box}, history}, []}, pose, box,
          E.query(world, palette, box, environment)),
        next => updated => W.paired(Frame, Result<&2, &2, Error, P.Progress>, C.World & Result<&2, &2, Error, Observation>,
          updated, frame => status => loop(rest, palette, frame, next, status)))

def packed(+frame: Frame, registry: B.Registry,
           result: C.World & Result<&2, &2, Error, Observation>) -> W.State & P.State & Result<&2, &2, Error, Observation>:
  match result:
    case (world, Fail{error}):
      (W.attach(G.Engine{world, registry}, frame_view(frame)), frame_pose(frame), Fail{error})
    case (world, Done{+observation}):
      Observation{+transition, queries, tail} = observation
      (W.attach(G.Engine{world, registry}, with_body(frame_view(frame), transition_body(transition))),
        transition_state(transition), Done{observation})

def rejected(engine: G.Engine, +frame: Frame, cause: Error) -> W.State & P.State & Result<&2, &2, Error, Observation>:
  (W.attach(engine, frame_view(frame)), frame_pose(frame), Fail{cause})

def palette_gate(error: Maybe<&2, E.Error>, world: C.World, registry: B.Registry,
                 +frame: Frame, fuel: Nat, palette: W.Palette, progress: P.Progress) -> W.State & P.State & Result<&2, &2, Error, Observation>:
  match error:
    case Some{cause}: rejected(G.Engine{world, registry}, frame, WorldError{cause})
    case None{}: packed(frame, registry, loop(fuel, palette, frame, world, Done{progress}))

def palette_read(world: C.World, +frame: Frame, fuel: Nat, progress: P.Progress,
                 result: B.Registry & Result<&2, &2, E.Error, W.Palette>) -> W.State & P.State & Result<&2, &2, Error, Observation>:
  match result:
    case (registry, Fail{error}): rejected(G.Engine{world, registry}, frame, WorldError{error})
    case (registry, Done{+palette}):
      palette_gate(E.palette_error(E.view_palette(frame_view(frame)), palette), world, registry, frame, fuel, palette, progress)

def body_gate(admitted: Bool, engine: G.Engine, frame: Frame, fuel: Nat,
              progress: P.Progress) -> W.State & P.State & Result<&2, &2, Error, Observation>:
  match admitted:
    case False{}: rejected(engine, frame, BodyOutsideInterior{})
    case True{}:
      G.Engine{world, registry} = engine
      palette_read(world, frame, fuel, progress, E.current_palette(registry))

def environment_gate(error: Maybe<&2, E.Error>, engine: G.Engine, +frame: Frame,
                     fuel: Nat, progress: P.Progress) -> W.State & P.State & Result<&2, &2, Error, Observation>:
  match error:
    case Some{cause}: rejected(engine, frame, WorldError{cause})
    case None{}:
      body_gate(E.query_admitted(body_box(E.view_body(frame_view(frame))), frame_environment(frame)), engine, frame, fuel, progress)

def begun(engine: G.Engine, +frame: Frame, fuel: Nat,
          result: Result<&2, &2, P.Error, P.Progress>) -> W.State & P.State & Result<&2, &2, Error, Observation>:
  match result:
    case Fail{error}: rejected(engine, frame, PoseError{error})
    case Done{progress}:
      environment_gate(E.environment_error(frame_environment(frame)), engine, frame, fuel, progress)

def admitted(request: Request, engine: G.Engine, +view: W.View,
             +pose: P.State) -> W.State & P.State & Result<&2, &2, Error, Observation>:
  match request:
    case Request{context, environment, fuel, _ <> _}:
      (W.attach(engine, view), pose, Fail{NonCanonicalTail{}})
    case Request{context, +environment, fuel, Nil{}}:
      begun(engine, Frame{view, pose, environment, [], []}, fuel,
        P.begin_checked(P.Request{pose, E.view_body(view), context, []}))

def extracted(pose: P.State, request: Request,
              result: G.Engine & W.View) -> W.State & P.State & Result<&2, &2, Error, Observation>:
  (engine, view) = result
  admitted(request, engine, view, pose)

def update_checked(world: W.State, pose: P.State, request: Request) -> W.State & P.State & Result<&2, &2, Error, Observation>:
  extracted(pose, request, W.take(world))

law rejected_retains_entire_view_and_pose:
  for engine: G.Engine
  for +frame: Frame
  for cause: Error
  {rejected(engine, frame, cause) == (W.attach(engine, frame_view(frame)), frame_pose(frame), Fail{cause}) : W.State & P.State & Result<&2, &2, Error, Observation>}

def rejected_retains_entire_view_and_pose(engine, frame, cause):
  {==}

law zero_budget_preserves_core:
  for palette: W.Palette
  for view: W.View
  for pose: P.State
  for environment: E.Environment
  for reversed: List<&2, QueryRecord>
  for world: C.World
  for work: P.Work
  {loop(0n, palette, Frame{view, pose, environment, reversed, []}, world, Done{P.Query{work, []}}) == (world, Fail{QueryBudget{}}) : C.World & Result<&2, &2, Error, Observation>}

def zero_budget_preserves_core(palette, view, pose, environment, reversed, world, work):
  {==}

law outside_body_admission_preserves_owners:
  for engine: G.Engine
  for frame: Frame
  for fuel: Nat
  for progress: P.Progress
  {body_gate(False{}, engine, frame, fuel, progress) == rejected(engine, frame, BodyOutsideInterior{}) : W.State & P.State & Result<&2, &2, Error, Observation>}

def outside_body_admission_preserves_owners(engine, frame, fuel, progress):
  {==}

law pose_commit_retains_view_metadata:
  for old: M.Body
  for body: M.Body
  for yaw: F32
  for pitch: F32
  for palette: Maybe<&2, W.Palette>
  for region: W.Bounds
  for cache: Maybe<&2, W.SnapshotCache>
  {with_body(W.View{old, yaw, pitch, palette, region, cache}, body) == W.View{body, yaw, pitch, palette, region, cache} : W.View}

def pose_commit_retains_view_metadata(old, body, yaw, pitch, palette, region, cache):
  {==}
