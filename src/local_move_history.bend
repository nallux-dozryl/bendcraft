import Base
import ./local_move_world.bend as LM
import ./player_fall_history.bend as H
import ./client_world.bend as W
import ./locomotion.bend as L
import ./support.bend as SP
import ./local_collision.bend as LC
import ./movement.bend as M
import ./geometry.bend as A
import ./game.bend as G
import ./f64.bend as F

# There is one authoritative World/body and one owned history. Recursive boxes
# bound native continuation width; canonical callers use empty tails.
type State is Type:
  State{world: W.State, support: SP.State, minor: LM.MinorState,
        history: H.State, tail: List<&1, State>}

type Request is Data:
  Request{move: LM.Request, clip: H.Clip, tail: List<&2, Request>}

# History here is an immutable result observation, never another owned State.
type Outcome is Data:
  Outcome{move: LM.Outcome, history: H.History, tail: List<&2, Outcome>}

type Error is Data:
  NonCanonicalState{}
  NonCanonicalRequest{field: U32}
  HistoryMismatch{}
  MoveError{cause: LM.Error}
  HistoryError{cause: H.Error}

# Snapshot Data contains no engine/table/array owners and no second player Body.
# The View's immutable Body is rollback evidence, as in LM's own Frame.
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

def request_move(request: Request) -> LM.Request:
  Request{move, clip, tail} = request
  move

def request_clip(request: Request) -> H.Clip:
  Request{move, clip, tail} = request
  clip

def history_distance(history: H.History) -> F.F64:
  H.History{distance} = history
  distance

def edge_distance(edge: LC.EdgeContext) -> F.F64:
  LC.EdgeContext{maximum, distance, flying, keys, mover, mode} = edge
  distance

def history_matches(+history: H.History, move: LM.Request) -> Bool:
  M.same_bits(history_distance(history), edge_distance(LM.context_edge(LM.request_context(move))))

def movement_from(transition: M.Transition, clip: H.Clip) -> H.Movement:
  match transition:
    case M.Transition{M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below}, +resolved, stepped, applied}:
      H.Movement{applied, M.Vec3.axis(resolved, A.AxisY{}), M.Vec3.length_squared(resolved), ground, clip}

def outcome_transition(outcome: LM.Outcome) -> M.Transition:
  LM.Outcome{motion, backoff, before, minor, tail} = outcome
  LM.motion_transition(motion)

def rollback_taken(tables: L.Tables, +frame: Frame, cause: Error,
                   result: G.Engine & W.View) -> State & L.Tables & Result<&2, &2, Error, Outcome>:
  (engine, current) = result
  (State{W.attach(engine, frame_view(frame)), frame_support(frame), frame_minor(frame), H.State{frame_history(frame)}, []}, tables, Fail{cause})

def rollback(world: W.State, tables: L.Tables, frame: Frame, cause: Error) -> State & L.Tables & Result<&2, &2, Error, Outcome>:
  rollback_taken(tables, frame, cause, W.take(world))

def history_finished(world: W.State, tables: L.Tables, frame: Frame,
                     support: SP.State, minor: LM.MinorState, move: LM.Outcome,
                     result: H.State & Result<&2, &2, H.Error, Unit>) -> State & L.Tables & Result<&2, &2, Error, Outcome>:
  (H.State{+history}, status) = result
  match status:
    case Fail{cause}: rollback(world, tables, frame, HistoryError{cause})
    case Done{unit}: (State{world, support, minor, H.State{history}, []}, tables, Done{Outcome{move, history, []}})

# LM's admitted queries/support/minor are history-independent after backoff.
# Computing an immutable candidate first executes no observable callbacks. It is
# equivalent only for this neutral no-damage, actual-MISS/NotRequired projection.
def moved(+frame: Frame,
          result: W.State & L.Tables & SP.State & LM.MinorState & Result<&2, &2, LM.Error, LM.Outcome>) -> State & L.Tables & Result<&2, &2, Error, Outcome>:
  (world, tables, support, minor, status) = result
  match status:
    case Fail{cause}: rollback(world, tables, frame, MoveError{cause})
    case Done{+move}:
      history_finished(world, tables, frame, support, minor, move,
        H.movement(H.NeutralDryNoDamage{}, movement_from(outcome_transition(move), request_clip(frame_request(frame))), H.State{frame_history(frame)}))

def bound_history(equal: Bool, world: W.State, tables: L.Tables, +frame: Frame) -> State & L.Tables & Result<&2, &2, Error, Outcome>:
  match equal:
    case False{}: rollback(world, tables, frame, HistoryMismatch{})
    case True{}:
      moved(frame, LM.move_checked(world, tables, frame_support(frame), frame_minor(frame), request_move(frame_request(frame))))

def extracted(tables: L.Tables, support: SP.State, minor: LM.MinorState,
              +history: H.History, +request: Request,
              result: G.Engine & W.View) -> State & L.Tables & Result<&2, &2, Error, Outcome>:
  (engine, +view) = result
  bound_history(history_matches(history, request_move(request)), W.attach(engine, view), tables, Frame{view, support, minor, history, request, []})

def canonical_move(state: State, tables: L.Tables, +request: Request) -> State & L.Tables & Result<&2, &2, Error, Outcome>:
  match state:
    case State{world, support, minor, H.State{history}, Nil{}}:
      extracted(tables, support, minor, history, request, W.take(world))
    case State{world, support, minor, history, tail}:
      (State{world, support, minor, history, tail}, tables, Fail{NonCanonicalState{}})

def move_inner_gate(state: State, tables: L.Tables, move: LM.Request, clip: H.Clip) -> State & L.Tables & Result<&2, &2, Error, Outcome>:
  match move:
    case LM.Request{body, delta, context, environment, fuel, Nil{}}:
      canonical_move(state, tables, Request{LM.Request{body, delta, context, environment, fuel, []}, clip, []})
    case _: (state, tables, Fail{NonCanonicalRequest{1}})

def move_tail_gate(state: State, tables: L.Tables, request: Request) -> State & L.Tables & Result<&2, &2, Error, Outcome>:
  match request:
    case Request{move, clip, Nil{}}: move_inner_gate(state, tables, move, clip)
    case Request{move, clip, tail}: (state, tables, Fail{NonCanonicalRequest{0}})

# No independent H.Mode permits a false noPhysics history bypass. LM admits the
# neutral move or rejects its context; only its success reaches the fixed H mode.
# Error restores the entire prior View/support/minor/history; Tables always return.
def move_checked(state: State, tables: L.Tables, request: Request) -> State & L.Tables & Result<&2, &2, Error, Outcome>:
  move_tail_gate(state, tables, request)
