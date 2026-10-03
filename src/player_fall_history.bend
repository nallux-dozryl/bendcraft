import Base
import ./f64.bend as F

# Authoritative history is independent of body, velocity, support and camera.
type History is Data:
  History{distance: F.F64}

type State is Type:
  State{history: History}

# These modes describe the already established receiver/world boundary. This
# reducer cannot infer water, abilities, effects or callback behavior from ground.
type Mode is Data:
  NeutralDryNoDamage{}
  NoPhysics{}
  WaterOrFluid{}
  FlightOrPassenger{}
  ClimbOrEffects{}
  UnsupportedWorld{}
  NonLocalAuthority{}

# Entity.move's fall-reset ray is before position application. Its actual result
# must be supplied when the gate is taken, distance!=0 and resolved.lengthSqr>=1.
type Clip is Data:
  NotRequired{}
  Miss{}
  Hit{}
  Unknown{}

type Movement is Data:
  Movement{position_applied: Bool, resolved_y: F.F64, resolved_length_squared: F.F64, on_ground: Bool, clip: Clip}

type Error is Data:
  NonFinite{field: U32}
  InvalidLengthSquared{}
  UnsupportedMode{mode: Mode}
  MissingClipObservation{}
  UnexpectedClipObservation{}
  UnsupportedResetHit{}
  UnsupportedLanding{}
  NonFiniteResult{}

def field_error(field: U32, finite: Bool) -> Maybe<&2, Error>:
  match finite:
    case True{}: None{}
    case False{}: Some{NonFinite{field}}

def first_error(first: Maybe<&2, Error>, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match first:
    case Some{error}: Some{error}
    case None{}: rest

def history_error(history: History) -> Maybe<&2, Error>:
  match history:
    case History{distance}: field_error(0, F.is_finite(distance))

def length_error(nonnegative: Bool) -> Maybe<&2, Error>:
  match nonnegative:
    case True{}: None{}
    case False{}: Some{InvalidLengthSquared{}}

def movement_error(movement: Movement) -> Maybe<&2, Error>:
  match movement:
    case Movement{_, +y, +squared, _, _}:
      first_error(field_error(1, F.is_finite(y)), first_error(field_error(2, F.is_finite(squared)), length_error(F.is_ge(squared, F.from_u32(0)))))

def clip_error(required: Bool, clip: Clip) -> Maybe<&2, Error>:
  match required clip:
    case False{} NotRequired{}: None{}
    case True{} Miss{}: None{}
    case _ Hit{}: Some{UnsupportedResetHit{}}
    case True{} _: Some{MissingClipObservation{}}
    case False{} _: Some{UnexpectedClipObservation{}}

def clip_required(+distance: F.F64, applied: Bool, squared: F.F64) -> Bool:
  Bool.and(applied, Bool.and(F.is_ne(distance, F.from_u32(0)), F.is_ge(squared, F.from_u32(1))))

# Actual arithmetic is dsub(distance, f2d(d2f(resolvedY))). It is neither
# distance-resolvedY nor distance-(newPositionY-oldPositionY).
def accumulate_if(+distance: F.F64, y: F.F64, negative: Bool) -> F.F64:
  match negative:
    case False{}: distance
    case True{}: F.sub(distance, F.from_f32(F.to_f32(y)))

def accumulate(+distance: F.F64, +y: F.F64) -> F.F64:
  accumulate_if(distance, y, F.is_lt(y, F.from_u32(0)))

def finish_ground(original: State, +distance: F.F64, ground: Bool, safe: Bool) -> State & Result<&2, &2, Error, Unit>:
  match ground safe:
    case False{} _: (State{History{distance}}, Done{Unit{}})
    case True{} True{}: (State{History{F.from_u32(0)}}, Done{Unit{}})
    case True{} False{}: (original, Fail{UnsupportedLanding{}})

def safe_landing(distance: F.F64) -> Bool:
  F.is_lt(F.sub(F.add(distance, F.from_bits(1051772663, 2696277389)), F.from_u32(3)), F.from_u32(1))

def finish_finite(original: State, +distance: F.F64, ground: Bool, finite: Bool) -> State & Result<&2, &2, Error, Unit>:
  match finite:
    case False{}: (original, Fail{NonFiniteResult{}})
    case True{}: finish_ground(original, distance, ground, safe_landing(distance))

def movement_ready(original: State, +distance: F.F64, movement: Movement, error: Maybe<&2, Error>) -> State & Result<&2, &2, Error, Unit>:
  match movement error:
    case _ Some{error}: (original, Fail{error})
    case Movement{_, y, _, ground, _} None{}:
      +next = accumulate(distance, y)
      finish_finite(original, next, ground, F.is_finite(next))

def movement_clip(state: State, movement: Movement) -> State & Result<&2, &2, Error, Unit>:
  match state movement:
    case State{History{+distance}} Movement{+applied, +y, +squared, +ground, +clip}:
      movement_ready(State{History{distance}}, distance, Movement{applied, y, squared, ground, clip}, clip_error(clip_required(distance, applied, squared), clip))

def movement_mode(mode: Mode, state: State, movement: Movement) -> State & Result<&2, &2, Error, Unit>:
  match mode:
    case NeutralDryNoDamage{}: movement_clip(state, movement)
    case NoPhysics{}: (state, Done{Unit{}})
    case _: (state, Fail{UnsupportedMode{mode}})

def movement_gate(mode: Mode, state: State, movement: Movement, error: Maybe<&2, Error>) -> State & Result<&2, &2, Error, Unit>:
  match error:
    case Some{error}: (state, Fail{error})
    case None{}: movement_mode(mode, state, movement)

# position_applied is metadata for the earlier reset ray, never a history gate.
# Safe landing assumes actual default SAFE_FALL_DISTANCE=3, ordinary air/stone
# multipliers=1 and no impulse/effect modifiers. Actual damage is the floor of
# ((distance+1e-6)-3), so the ordered expression must be <1 for no damage.
def movement(+mode: Mode, +movement: Movement, state: State) -> State & Result<&2, &2, Error, Unit>:
  State{+history} = state
  movement_gate(mode, State{history}, movement, first_error(history_error(history), movement_error(movement)))

def reset_gate(state: State, error: Maybe<&2, Error>) -> State & Result<&2, &2, Error, Unit>:
  match error:
    case Some{error}: (state, Fail{error})
    case None{}: (State{History{F.from_u32(0)}}, Done{Unit{}})

# Explicit reset phase only; this does not detect or execute water, flight,
# climbing, effects, riding, stuck-block or fall-resetting-ray lifecycle paths.
def reset(state: State) -> State & Result<&2, &2, Error, Unit>:
  State{+history} = state
  reset_gate(State{history}, history_error(history))

def clamp_if(+distance: F.F64, needed: Bool) -> F.F64:
  match needed:
    case False{}: distance
    case True{}: F.from_u32(1)

def clamp_ready(history: History, y: F.F64) -> State:
  match history:
    case History{+distance}:
      State{History{clamp_if(distance, Bool.and(F.is_gt(y, F.neg(F.from_bits(1071644672, 0))), F.is_gt(distance, F.from_u32(1))))}}

def clamp_gate(state: State, y: F.F64, error: Maybe<&2, Error>) -> State & Result<&2, &2, Error, Unit>:
  match state error:
    case State{history} Some{error}: (State{history}, Fail{error})
    case State{history} None{}: (clamp_ready(history, y), Done{Unit{}})

# Exact Entity.checkFallDistanceAccumulation phase: y>-0.5 && distance>1.
# The caller supplies the authoritative DELTA MOVEMENT Y at this call point.
# It is not automatically run during movement/checkFallDamage in this module.
def check_accumulation(+velocity_y: F.F64, state: State) -> State & Result<&2, &2, Error, Unit>:
  State{+history} = state
  clamp_gate(State{history}, velocity_y, first_error(history_error(history), field_error(3, F.is_finite(velocity_y))))
