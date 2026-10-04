import Base
import ./player_block_inside_sweep.bend as S
import ./player_block_inside_sweep_clip.bend as Clip
import ./local_travel_history.bend as TH
import ./local_move_history.bend as MH
import ./local_move_world.bend as LM
import ./travel.bend as T
import ./movement.bend as M
import ./f64.bend as F

# Read the original admission flag and resolved displacement from the retained
# actual motion outcome. The record endpoint is the original Vec3.add result,
# which can differ in raw zero bits from the retained Body.position.
def record_gate(+from: M.Vec3, original: M.Vec3, displacement: M.Vec3,
                admitted: Bool) -> Maybe<&2, S.Movement>:
  match admitted:
    case False{}: None{}
    case True{}: Some{S.Movement{from, M.Vec3.add(from, displacement), Some{original}}}

def record_motion(from: M.Vec3, original: M.Vec3, motion: LM.Motion) -> Maybe<&2, S.Movement>:
  LM.Motion{M.Transition{body, displacement, stepped, admitted}, tail} = motion
  record_gate(from, original, displacement, admitted)

def record_move(from: M.Vec3, move: LM.Outcome) -> Maybe<&2, S.Movement>:
  LM.Outcome{motion, backoff, before, minor, tail} = move
  record_motion(from, LM.backoff_requested(backoff), motion)

def body_position(body: M.Body) -> M.Vec3:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = body
  position

def travel_record(outcome: TH.Outcome) -> Maybe<&2, S.Movement>:
  TH.Outcome{TH.Preparation{T.Prepared{body, requested, friction, acceleration, maximum, gravity, drag, discard}, prepared_tail},
    MH.Outcome{move, history, movement_tail}, final_motion, tail} = outcome
  record_move(body_position(body), move)

def reset_record(outcome: TH.ResetOutcome) -> Maybe<&2, S.Movement>:
  TH.ResetOutcome{travel, ray, tail} = outcome
  travel_record(travel)

def last_to(movements: List<&2, S.Movement>, fallback: M.Vec3) -> M.Vec3:
  match movements:
    case Nil{}: fallback
    case S.Movement{from, to, original} <> rest: last_to(rest, to)

def bridged(pending: List<&2, S.Movement>, endpoint: M.Vec3,
            position: M.Vec3, needed: Bool) -> List<&2, S.Movement>:
  match needed:
    case False{}: pending
    case True{}: List.concat(&2, S.Movement, [pending, [S.Movement{endpoint, position, None{}}]])

def ready_tail(+pending: List<&2, S.Movement>, +endpoint: M.Vec3,
               +position: M.Vec3) -> List<&2, S.Movement>:
  bridged(pending, endpoint, position,
    F.is_gt(M.Vec3.length_squared(Clip.subtract(endpoint, position)), S.tiny_square()))

# This is the original public dispatcher's ready-list selection for an already
# retained queue. Queue insertion/coalescing and owner storage remain with the
# caller; a callback query must consume the resulting list once in order.
def ready(pending: List<&2, S.Movement>, old_position: M.Vec3,
          +position: M.Vec3) -> List<&2, S.Movement>:
  match pending:
    case Nil{}: [S.Movement{old_position, position, None{}}]
    case +first <> +rest:
      ready_tail(first <> rest, last_to(first <> rest, position), position)
