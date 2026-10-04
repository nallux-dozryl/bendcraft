import Base
import ./player_block_inside_stuck.bend as P
import ./player_block_inside_stuck_motion.bend as PM
import ./player_block_inside_sweep.bend as S
import ./player_block_inside_sweep_world.bend as W
import ./local_move_history.bend as MH
import ./client_world.bend as CW
import ./game.bend as G
import ./movement.bend as M

type Error is Data:
  DimensionsMismatch{}
  FinalPositionMismatch{}
  ReceiverPositionMismatch{}
  SweepError{cause: W.Error}

def error_text(error: Error) -> String:
  match error:
    case DimensionsMismatch{}: "body-dimensions-mismatch"
    case FinalPositionMismatch{}: "body-final-position-mismatch"
    case ReceiverPositionMismatch{}: "berry-receiver-position-mismatch"
    case SweepError{cause}: W.error_text(cause)

def same_vector(a: M.Vec3, b: M.Vec3) -> Bool:
  match a b:
    case M.Vec3{x, y, z} M.Vec3{u, v, w}:
      M.same_bits(x, u) && M.same_bits(y, v) && M.same_bits(z, w)

def endpoint(movements: List<&2, S.Movement>, fallback: M.Vec3) -> M.Vec3:
  match movements:
    case Nil{}: fallback
    case S.Movement{from, to, original} <> rest: endpoint(rest, to)

def receiver_position(level: P.Level, fallback: M.Vec3) -> M.Vec3:
  match level:
    case P.ServerLevel{authority, known, old, current}: current
    case _: fallback

def binding_error(dimensions: Bool, position: Bool, receiver: Bool) -> Maybe<&2, Error>:
  match dimensions position receiver:
    case False{} _ _: Some{DimensionsMismatch{}}
    case True{} False{} _: Some{FinalPositionMismatch{}}
    case True{} True{} False{}: Some{ReceiverPositionMismatch{}}
    case True{} True{} True{}: None{}

def view_binding(view: CW.View, request: W.Request) -> Maybe<&2, Error>:
  match view request:
    case CW.View{M.Body{+position, box, velocity, width, height, ground, horizontal, vertical, below}, yaw, pitch, palette, region, cache}
         W.Request{facts, level, removed, physics, alive, expected_width, expected_height, movements, traversal_fuel, read_fuel, tail}:
      binding_error(U32.is_eq(F32.bits(width), F32.bits(expected_width)) &&
        U32.is_eq(F32.bits(height), F32.bits(expected_height)),
        same_vector(position, endpoint(movements, position)),
        same_vector(position, receiver_position(level, position)))

def restore(frame: PM.Frame, result: P.State & Result<&2, &2, Error, W.Observation>) -> MH.State & P.Receiver & Result<&2, &2, Error, W.Observation>:
  match frame result:
    case PM.Frame{view, support, minor, tail} Tuple{P.State{world, registry, receiver, history, unused}, status}:
      (MH.State{CW.attach(G.Engine{world, registry}, view), support, minor, history, tail}, receiver, status)

def completed(frame: PM.Frame, result: P.State & Result<&2, &2, W.Error, W.Observation>) -> MH.State & P.Receiver & Result<&2, &2, Error, W.Observation>:
  (state, status) = result
  match status:
    case Fail{error}: restore(frame, (state, Fail{SweepError{error}}))
    case Done{observation}: restore(frame, (state, Done{observation}))

def gate(state: P.State, frame: PM.Frame, dimension: String, request: W.Request,
         error: Maybe<&2, Error>) -> MH.State & P.Receiver & Result<&2, &2, Error, W.Observation>:
  match error:
    case Some{error}: restore(frame, (state, Fail{error}))
    case None{}: completed(frame, W.query(state, dimension, request))

def framed(state: P.State, frame: PM.Frame, dimension: String, +request: W.Request) -> MH.State & P.Receiver & Result<&2, &2, Error, W.Observation>:
  PM.Frame{+view, support, minor, tail} = frame
  gate(state, PM.Frame{view, support, minor, tail}, dimension, request, view_binding(view, request))

def extracted(dimension: String, request: W.Request, value: P.State & PM.Frame) -> MH.State & P.Receiver & Result<&2, &2, Error, W.Observation>:
  (state, frame) = value
  framed(state, frame, dimension, request)

# The caller supplies the retained Entity.move records, including its original
# axis-dependent request. This joins their ordered callbacks to the actual MH
# owner after successful travel, before committing that tick's saved receiver.
def after_movements(motion: MH.State, receiver: P.Receiver, dimension: String,
                    request: W.Request) -> MH.State & P.Receiver & Result<&2, &2, Error, W.Observation>:
  extracted(dimension, request, PM.extract(motion, receiver))
