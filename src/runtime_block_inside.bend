import Base
import ./player_block_inside_stuck.bend as P
import ./player_block_inside_stuck_motion.bend as PM
import ./player_block_inside_sweep.bend as S
import ./player_block_inside_sweep_world.bend as W
import ./player_block_inside_sweep_motion.bend as SM
import ./player_block_inside_sweep_travel.bend as ST
import ./local_travel_history.bend as TH
import ./local_move_history.bend as MH
import ./client_world.bend as CW
import ./movement.bend as M

# These are actual receiver/profile observations supplied by the runtime owner.
# They are not transport parameters or inferred from a render palette.
type Hooks is Data:
  Hooks{facts: P.Facts, level: P.Level, old_position: M.Vec3,
        dimension: String, removed: Bool, no_physics: Bool, alive: Bool,
        traversal_fuel: Nat, read_fuel: Nat, tail: List<&2, Hooks>}

type Error is Data:
  NonCanonicalHooks{}
  CallbackError{cause: SM.Error}

def error_text(error: Error) -> String:
  match error:
    case NonCanonicalHooks{}: "noncanonical-block-inside-hooks"
    case CallbackError{cause}: SM.error_text(cause)

def record_list(record: Maybe<&2, S.Movement>) -> List<&2, S.Movement>:
  match record:
    case None{}: []
    case Some{movement}: [movement]

def request(view: CW.View, hooks: Hooks, record: Maybe<&2, S.Movement>) -> W.Request:
  match view hooks:
    case CW.View{M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below}, yaw, pitch, palette, region, cache}
         Hooks{facts, level, old, dimension, removed, physics, alive, traversal, reads, tail}:
      W.Request{facts, level, removed, physics, alive, width, height,
        ST.ready(record_list(record), old, position), traversal, reads, []}

def consume(receiver: P.Receiver, no_physics: Bool) -> P.Receiver:
  match no_physics:
    case True{}: receiver
    case False{}: P.travel_succeeded(receiver)

def same_impact(a: Maybe<&2, M.Vec3>, b: Maybe<&2, M.Vec3>) -> Bool:
  match a b:
    case None{} None{}: True{}
    case Some{x} Some{y}: SM.same_vector(x, y)
    case _ _: False{}

# Runtime retention compares IEEE payloads, including signed zero and NaNs.
# A numerical vector comparison would discard part of the receiver state.
def same_receiver(a: P.Receiver, b: P.Receiver) -> Bool:
  match a b:
    case P.Receiver{x, P.Impulse{grace, impact}}
         P.Receiver{y, P.Impulse{other, previous}}:
      SM.same_vector(x, y) && U32.is_eq(grace, other) && same_impact(impact, previous)

def dimension(hooks: Hooks) -> String:
  Hooks{facts, level, old, dimension, removed, physics, alive, traversal, reads, tail} = hooks
  dimension

def completed(previous: P.Receiver,
              result: MH.State & P.Receiver & Result<&2, &2, SM.Error, W.Observation>) -> MH.State & P.Receiver & Result<&2, &2, Error, W.Observation>:
  (motion, next, status) = result
  match status:
    case Fail{error}: (motion, previous, Fail{CallbackError{error}})
    case Done{observation}: (motion, next, Done{observation})

def framed(previous: P.Receiver, state: P.State, frame: PM.Frame,
           +hooks: Hooks, record: Maybe<&2, S.Movement>) -> MH.State & P.Receiver & Result<&2, &2, Error, W.Observation>:
  PM.Frame{+view, support, minor, tail} = frame
  completed(previous, SM.framed(state, PM.Frame{view, support, minor, tail}, dimension(hooks), request(view, hooks, record)))

def extracted(previous: P.Receiver, hooks: Hooks, record: Maybe<&2, S.Movement>,
              result: P.State & PM.Frame) -> MH.State & P.Receiver & Result<&2, &2, Error, W.Observation>:
  (state, frame) = result
  framed(previous, state, frame, hooks, record)

# Enter only after TH and outer Player.finish both succeed, with the finished
# Body installed in the sole MH owner. Callback refusal restores the original
# receiver supplied here; the enclosing runtime still owns pre-travel rollback.
# This current consumer executes one successful travel per dispatch. Multiple
# Entity.move calls require retaining and passing their full ordered queue.
def after_successful_travel(motion: MH.State, +receiver: P.Receiver,
                            hooks: Hooks, outcome: TH.Outcome) -> MH.State & P.Receiver & Result<&2, &2, Error, W.Observation>:
  match hooks:
    case Hooks{facts, level, old, dimension, removed, +physics, alive, traversal, reads, Nil{}}:
      extracted(receiver, Hooks{facts, level, old, dimension, removed, physics, alive, traversal, reads, []},
        ST.travel_record(outcome), PM.extract(motion, consume(receiver, physics)))
    case _: (motion, receiver, Fail{NonCanonicalHooks{}})
