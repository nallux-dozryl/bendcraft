import Base
import ./player_block_inside_stuck.bend as P
import ./local_move_history.bend as MH
import ./local_move_world.bend as LM
import ./client_world.bend as W
import ./game.bend as G
import ./support.bend as SP
import ./player_fall_history.bend as H
import ./movement.bend as M
import ./geometry.bend as A

# Actual motion-owner adapter. Body, cache, support, minor and arbitrary affine
# tail stay in the join frame while P retains the only world/registry/history.
type Frame is Type:
  Frame{view: W.View, support: SP.State, minor: LM.MinorState,
        tail: List<&1, MH.State>}

def extract(motion: MH.State, receiver: P.Receiver) -> P.State & Frame:
  match motion:
    case MH.State{W.State{G.Engine{world, registry}, body, yaw, pitch, palette, region, cache}, support, minor, history, tail}:
      (P.State{world, registry, receiver, history, []},
        Frame{W.View{body, yaw, pitch, palette, region, cache}, support, minor, tail})

def restore(frame: Frame, result: P.State & Result<&2, &2, P.Error, P.Observation>) -> MH.State & P.Receiver & Result<&2, &2, P.Error, P.Observation>:
  match frame result:
    case Frame{view, support, minor, tail} Tuple{P.State{world, registry, receiver, history, unused}, status}:
      (MH.State{W.attach(G.Engine{world, registry}, view), support, minor, history, tail}, receiver, status)

def contacts_extracted(+request: P.Request, result: P.State & Frame) -> MH.State & P.Receiver & Result<&2, &2, P.Error, P.Observation>:
  match result:
    case (state, frame): restore(frame, P.query(state, request))

# Run after successful travel; store the resulting Receiver for next travel.
def after_contacts(motion: MH.State, receiver: P.Receiver,
                   request: P.Request) -> MH.State & P.Receiver & Result<&2, &2, P.Error, P.Observation>:
  contacts_extracted(request, extract(motion, receiver))

def same_box(a: A.AABB, b: A.AABB) -> Bool:
  match a b:
    case A.AABB{a, b, c, d, e, f} A.AABB{x, y, z, u, v, w}:
      M.same_bits(a, x) && M.same_bits(b, y) && M.same_bits(c, z) &&
        M.same_bits(d, u) && M.same_bits(e, v) && M.same_bits(f, w)

def view_box(view: W.View) -> A.AABB:
  W.View{M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below}, yaw, pitch, palette, region, cache} = view
  box

def request_box(request: P.Stationary) -> A.AABB:
  P.Stationary{facts, level, removed, physics, alive, dimension, box, fuel} = request
  box

def frame_box(frame: Frame) -> A.AABB:
  Frame{view, support, minor, tail} = frame
  view_box(view)

def stationary_gate(state: P.State, frame: Frame, request: P.Stationary,
                    matched: Bool) -> MH.State & P.Receiver & Result<&2, &2, P.Error, P.Observation>:
  match matched:
    case False{}: restore(frame, (state, Fail{P.BodyMismatch{}}))
    case True{}: restore(frame, P.stationary(state, request))

def stationary_frame(state: P.State, frame: Frame, +request: P.Stationary) -> MH.State & P.Receiver & Result<&2, &2, P.Error, P.Observation>:
  Frame{+view, support, minor, tail} = frame
  stationary_gate(state, Frame{view, support, minor, tail}, request, same_box(view_box(view), request_box(request)))

def stationary_extracted(+request: P.Stationary, result: P.State & Frame) -> MH.State & P.Receiver & Result<&2, &2, P.Error, P.Observation>:
  match result:
    case (state, frame): stationary_frame(state, frame, request)

def after_stationary(motion: MH.State, receiver: P.Receiver,
                     request: P.Stationary) -> MH.State & P.Receiver & Result<&2, &2, P.Error, P.Observation>:
  stationary_extracted(request, extract(motion, receiver))
