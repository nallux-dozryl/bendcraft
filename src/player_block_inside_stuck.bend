import Base
import ./f64.bend as F
import ./movement.bend as M
import ./geometry.bend as A
import ./core.bend as C
import ./registry.bend as B
import ./player_fall_history.bend as H

# Receiver state survives travel and is replaced by admitted block callbacks.
# Impulse context is an explicit service boundary, not another history owner.
type Impulse is Data:
  Impulse{grace_time: U32, impact_position: Maybe<&2, M.Vec3>}

type Receiver is Data:
  Receiver{multiplier: M.Vec3, impulse: Impulse}

type Facts is Data:
  Player{flying: Bool, weaving: Bool}
  OtherLiving{fox_or_bee: Bool, weaving: Bool}
  OtherEntity{}

type Level is Data:
  ClientLevel{}
  OrdinaryLevel{}
  ServerLevel{client_authoritative: Bool, known_movement: M.Vec3,
              old_position: M.Vec3, position: M.Vec3}

type Error is Data:
  WorldError{cause: C.Error}
  RegistryError{cause: B.Error}
  UnsupportedCallback{name: String, state: U32}
  UnknownIntersection{}
  ServerBerryDamageRequired{}
  InvalidBerryAge{}
  InvalidMovementObservation{}
  BodyMismatch{}
  InvalidBox{}
  InvalidCoordinate{}
  QueryBudget{}
  NonCanonicalRequest{}

type Candidate is Data:
  Candidate{receiver: Receiver, history: H.History, impulse_reset: Bool}

type Read is Data:
  Read{position: C.Position, state: B.Resolved}

type Observation is Data:
  Observation{receiver: Receiver, history: H.History, impulse_reset: Bool,
              reads: List<&2, Read>}

# The caller supplies contacts in actual vanilla traversal order. Intersection
# must come from the entity-inside shape, not render or movement collision.
type Admission is Data:
  BlockIntersection{}
  NoBlockIntersection{}
  UnresolvedIntersection{}

type Contact is Data:
  Contact{position: C.Position, admission: Admission}

type Request is Data:
  Request{facts: Facts, level: Level, removed: Bool, no_physics: Bool,
          alive: Bool, contacts: List<&2, Contact>, fuel: Nat,
          tail: List<&2, Request>}

# Engine and fall history each have exactly one affine owner. Candidate Data is
# speculative until every requested read, callback and service is admitted.
type State is Type:
  State{world: C.World, registry: B.Registry, receiver: Receiver,
        history: H.State, tail: List<&1, State>}

type Scratch is Data:
  Scratch{candidate: Candidate, reversed: List<&2, Read>}

type Bounds is Data:
  Bounds{dimension: String, x: U32, y: U32, z: U32,
         max_x: U32, max_y: U32, max_z: U32}

type Stationary is Data:
  Stationary{facts: Facts, level: Level, removed: Bool, no_physics: Bool,
             alive: Bool, dimension: String, box: A.AABB, fuel: Nat}

def empty() -> Receiver:
  Receiver{M.Vec3.zero(), Impulse{0, None{}}}

def world_error(error: C.Error) -> String:
  match error:
    case C.PermissionDenied{}: "permission-denied"
    case C.UnknownDimension{name}: "unknown-dimension:" ++ name
    case C.InvalidState{state}: "invalid-state:" ++ U32.show(state)
    case C.MissingSection{key}: "missing-section:" ++ key
    case C.SectionExists{key}: "section-exists:" ++ key
    case C.InvalidCoordinate{}: "invalid-coordinate"
    case C.PastTick{}: "past-tick"
    case C.TooManyPending{}: "too-many-pending"

def error_text(error: Error) -> String:
  match error:
    case WorldError{cause}: "world:" ++ world_error(cause)
    case RegistryError{cause}: "registry:" ++ B.error_text(cause)
    case UnsupportedCallback{name, state}: "unsupported-callback:" ++ name ++ ":" ++ U32.show(state)
    case UnknownIntersection{}: "unknown-intersection"
    case ServerBerryDamageRequired{}: "server-berry-damage-required"
    case InvalidBerryAge{}: "invalid-berry-age"
    case InvalidMovementObservation{}: "invalid-movement-observation"
    case BodyMismatch{}: "body-mismatch"
    case InvalidBox{}: "invalid-box"
    case InvalidCoordinate{}: "invalid-coordinate"
    case QueryBudget{}: "query-budget"
    case NonCanonicalRequest{}: "noncanonical-request"

def multiplier(receiver: Receiver) -> M.Vec3:
  Receiver{value, impulse} = receiver
  value

def choose(-T: Data, yes: T, no: T, gate: Bool) -> T:
  match gate:
    case True{}: yes
    case False{}: no

def paired(-A: Type, -B: Type, -T: Type, value: A & B, finish: A -> B -> T) -> T:
  match value:
    case (a, b): finish(a, b)

def consume_gate(receiver: Receiver, active: Bool) -> Receiver:
  match receiver active:
    case Receiver{value, impulse} False{}: Receiver{value, impulse}
    case Receiver{value, impulse} True{}: Receiver{M.Vec3.zero(), impulse}

# Call only after successful travel. Failed travel retains the entire receiver.
# This is the same exact ordered threshold as Entity.move's existing M phase.
def travel_succeeded(+receiver: Receiver) -> Receiver:
  consume_gate(receiver, F.is_gt(M.Vec3.length_squared(multiplier(receiver)), M.stuck_threshold()))

# Pinned raw doubles include the original .05f/.8f promotions; these are not
# decimal-double .05/.8 approximations. See the independent Java reference.
def web_multiplier(weaving: Bool) -> M.Vec3:
  choose(M.Vec3, M.Vec3{F.F64{1071644672, 0}, F.F64{1070596096, 0}, F.F64{1071644672, 0}},
    M.Vec3{F.F64{1070596096, 0}, F.F64{1068079513, 2684354560}, F.F64{1070596096, 0}}, weaving)

def berry_multiplier() -> M.Vec3:
  M.Vec3{F.F64{1072273817, 2684354560}, F.F64{1072168960, 0}, F.F64{1072273817, 2684354560}}

def weaving(facts: Facts) -> Bool:
  match facts:
    case Player{flying, value}: value
    case OtherLiving{excluded, value}: value
    case OtherEntity{}: False{}

def berry_eligible(facts: Facts) -> Bool:
  match facts:
    case Player{flying, effect}: True{}
    case OtherLiving{excluded, effect}: Bool.not(excluded)
    case OtherEntity{}: False{}

def unchanged(receiver: Receiver, history: H.History) -> Candidate:
  Candidate{receiver, history, False{}}

def impulse_gate(impulse: Impulse, clear: Bool) -> Impulse:
  match impulse clear:
    case Impulse{grace, position} False{}: Impulse{grace, position}
    case Impulse{grace, position} True{}: Impulse{0, None{}}

def impulse_reset(+impulse: Impulse) -> Impulse:
  Impulse{grace, position} = impulse
  impulse_gate(impulse, U32.is_eq(grace, 0))

def entity_set(receiver: Receiver, value: M.Vec3) -> Candidate:
  Receiver{old, impulse} = receiver
  Candidate{Receiver{value, impulse}, H.History{M.zero()}, False{}}

def player_set(receiver: Receiver, history: H.History, value: M.Vec3,
               flying: Bool) -> Candidate:
  Receiver{old, +impulse} = receiver
  Impulse{grace, position} = impulse
  match flying:
    case True{}: Candidate{Receiver{old, impulse_reset(impulse)}, history, U32.is_eq(grace, 0)}
    case False{}: Candidate{Receiver{value, impulse_reset(impulse)}, H.History{M.zero()}, U32.is_eq(grace, 0)}

def make_stuck(receiver: Receiver, history: H.History, facts: Facts,
               value: M.Vec3) -> Result<&2, &2, Error, Candidate>:
  match facts:
    case Player{flying, effect}: Done{player_set(receiver, history, value, flying)}
    case _: Done{entity_set(receiver, value)}

def age_value(value: String) -> Result<&2, &2, Error, U32>:
  match value:
    case "0": Done{0}
    case "1": Done{1}
    case "2": Done{2}
    case "3": Done{3}
    case _: Fail{InvalidBerryAge{}}

def berry_age(assignments: List<&2, B.Assignment>) -> Result<&2, &2, Error, U32>:
  match assignments:
    case B.Assignment{"age", value} <> Nil{}: age_value(value)
    case _: Fail{InvalidBerryAge{}}

def vector_subtract(a: M.Vec3, b: M.Vec3) -> M.Vec3:
  match a b:
    case M.Vec3{ax, ay, az} M.Vec3{bx, by, bz}:
      M.Vec3{F.sub(ax, bx), F.sub(ay, by), F.sub(az, bz)}

def server_movement(level: Level) -> M.Vec3:
  match level:
    case ServerLevel{authority, known, old, position}:
      choose(M.Vec3, known, vector_subtract(old, position), authority)
    case _: M.Vec3.zero()

def berry_damage_horizontal(+movement: M.Vec3) -> Bool:
  M.Vec3{+x, y, +z} = movement
  F.is_gt(M.Vec3.horizontal_squared(movement), M.zero()) &&
    (F.is_ge(F.abs(x), F.F64{1063818100, 3221225472}) || F.is_ge(F.abs(z), F.F64{1063818100, 3221225472}))

def berry_damage_finite(movement: M.Vec3, finite: Bool) -> Result<&2, &2, Error, Unit>:
  match finite:
    case False{}: Fail{InvalidMovementObservation{}}
    case True{}:
      choose(Result<&2, &2, Error, Unit>, Fail{ServerBerryDamageRequired{}}, Done{Unit{}}, berry_damage_horizontal(movement))

def berry_movement(+movement: M.Vec3) -> Result<&2, &2, Error, Unit>:
  M.Vec3{+x, y, +z} = movement
  berry_damage_finite(movement, F.is_finite(x) && F.is_finite(z))

def berry_damage(level: Level, age: U32) -> Result<&2, &2, Error, Unit>:
  match level age:
    case ServerLevel{authority, known, old, position} 0: Done{Unit{}}
    case ServerLevel{+authority, +known, +old, +position} _:
      berry_movement(server_movement(ServerLevel{authority, known, old, position}))
    case _ _: Done{Unit{}}

def berry_ready(receiver: Receiver, history: H.History, facts: Facts,
                status: Result<&2, &2, Error, Unit>) -> Result<&2, &2, Error, Candidate>:
  match status:
    case Fail{error}: Fail{error}
    case Done{unit}: make_stuck(receiver, history, facts, berry_multiplier())

def berry_aged(receiver: Receiver, history: H.History, facts: Facts,
               level: Level, age: Result<&2, &2, Error, U32>) -> Result<&2, &2, Error, Candidate>:
  match age:
    case Fail{error}: Fail{error}
    case Done{value}: berry_ready(receiver, history, facts, berry_damage(level, value))

def berry_callback(receiver: Receiver, history: H.History, facts: Facts,
                   level: Level, assignments: List<&2, B.Assignment>, eligible: Bool) -> Result<&2, &2, Error, Candidate>:
  match eligible:
    case False{}: Done{unchanged(receiver, history)}
    case True{}: berry_aged(receiver, history, facts, level, berry_age(assignments))

# Exact admitted BlockState.entityInside callback slice. Unknown callbacks are
# refused, including fluid/fire/damage behavior not owned by this module.
def callback_checked(receiver: Receiver, history: H.History, +facts: Facts,
                     level: Level, resolved: B.Resolved) -> Result<&2, &2, Error, Candidate>:
  match resolved:
    case B.Resolved{protocol, "minecraft:air", state, assignments}: Done{unchanged(receiver, history)}
    case B.Resolved{protocol, "minecraft:stone", state, assignments}: Done{unchanged(receiver, history)}
    case B.Resolved{protocol, "minecraft:dirt", state, assignments}: Done{unchanged(receiver, history)}
    case B.Resolved{protocol, "minecraft:oak_planks", state, assignments}: Done{unchanged(receiver, history)}
    case B.Resolved{protocol, "minecraft:cobweb", state, assignments}:
      make_stuck(receiver, history, facts, web_multiplier(weaving(facts)))
    case B.Resolved{protocol, "minecraft:sweet_berry_bush", state, assignments}:
      berry_callback(receiver, history, facts, level, assignments, berry_eligible(facts))
    case B.Resolved{protocol, name, state, assignments}: Fail{UnsupportedCallback{name, state}}

def initial(receiver: Receiver, history: H.History) -> Scratch:
  Scratch{unchanged(receiver, history), []}

def observation(scratch: Scratch) -> Observation:
  Scratch{Candidate{receiver, history, impulse}, reversed} = scratch
  Observation{receiver, history, impulse, List.reverse(&2, Read, reversed)}

def commit(state: State, scratch: Scratch) -> State & Result<&2, &2, Error, Observation>:
  State{world, registry, old, history, tail} = state
  Scratch{+candidate, reversed} = scratch
  Candidate{receiver, next, impulse} = candidate
  (State{world, registry, receiver, H.State{next}, tail}, Done{observation(Scratch{candidate, reversed})})

def finish(state: State, result: Result<&2, &2, Error, Scratch>) -> State & Result<&2, &2, Error, Observation>:
  match result:
    case Fail{error}: (state, Fail{error})
    case Done{scratch}: commit(state, scratch)

def step_candidate(position: C.Position, +resolved: B.Resolved,
                   scratch: Scratch, status: Result<&2, &2, Error, Candidate>) -> Result<&2, &2, Error, Scratch>:
  match scratch status:
    case _ Fail{error}: Fail{error}
    case Scratch{Candidate{old, history, prior_impulse}, reversed} Done{Candidate{receiver, next, impulse}}:
      Done{Scratch{Candidate{receiver, next, (prior_impulse || impulse)}, Read{position, resolved} <> reversed}}

def candidate_history(candidate: Candidate) -> H.History:
  Candidate{receiver, history, impulse} = candidate
  history

def candidate_receiver(candidate: Candidate) -> Receiver:
  Candidate{receiver, history, impulse} = candidate
  receiver

def decoded(state: State, +facts: Facts, level: Level, position: C.Position,
            +scratch: Scratch, resolved: Result<&2, &2, B.Error, B.Resolved>) -> State & Result<&2, &2, Error, Scratch>:
  match scratch resolved:
    case _ Fail{error}: (state, Fail{RegistryError{error}})
    case Scratch{+candidate, +reversed} Done{+identity}:
      (state, step_candidate(position, identity, Scratch{candidate, reversed},
        callback_checked(candidate_receiver(candidate), candidate_history(candidate), facts, level, identity)))

def decode_read(world: C.World, receiver: Receiver, history: H.State, tail: List<&1, State>,
                facts: Facts, level: Level, position: C.Position, scratch: Scratch,
                decoded_value: B.Registry & Result<&2, &2, B.Error, B.Resolved>) -> State & Result<&2, &2, Error, Scratch>:
  (registry, result) = decoded_value
  decoded(State{world, registry, receiver, history, tail}, facts, level, position, scratch, result)

def block_read(registry: B.Registry, receiver: Receiver, history: H.State, tail: List<&1, State>,
               facts: Facts, level: Level, position: C.Position, scratch: Scratch,
               read: C.World & Result<&2, &2, C.Error, U32>) -> State & Result<&2, &2, Error, Scratch>:
  (world, status) = read
  match status:
    case Fail{error}: (State{world, registry, receiver, history, tail}, Fail{WorldError{error}})
    case Done{state}: decode_read(world, receiver, history, tail, facts, level, position, scratch, B.Registry.decode(registry, state))

def contact_read(state: State, facts: Facts, level: Level, +position: C.Position,
                 scratch: Scratch) -> State & Result<&2, &2, Error, Scratch>:
  State{world, registry, receiver, history, tail} = state
  block_read(registry, receiver, history, tail, facts, level, position, scratch, C.read_block(world, position))

def contact(state: State, facts: Facts, level: Level, item: Contact,
            scratch: Scratch) -> State & Result<&2, &2, Error, Scratch>:
  match item:
    case Contact{position, UnresolvedIntersection{}}: (state, Fail{UnknownIntersection{}})
    case Contact{position, NoBlockIntersection{}}: (state, Done{scratch})
    case Contact{position, BlockIntersection{}}: contact_read(state, facts, level, position, scratch)

def loop(fuel: Nat, state: State, +facts: Facts, +level: Level,
         contacts: List<&2, Contact>, current: Result<&2, &2, Error, Scratch>) -> State & Result<&2, &2, Error, Observation>:
  match fuel contacts current:
    case _ _ Fail{error}: finish(state, Fail{error})
    case _ Nil{} Done{scratch}: finish(state, Done{scratch})
    case 0n _ Done{scratch}: finish(state, Fail{QueryBudget{}})
    case 1n+p item <> rest Done{scratch}:
      paired(State, Result<&2, &2, Error, Scratch>, State & Result<&2, &2, Error, Observation>,
        contact(state, facts, level, item, scratch), next => status => loop(p, next, facts, level, rest, status))

def state_initial(state: State) -> State & Scratch:
  State{world, registry, +receiver, H.State{+history}, tail} = state
  (State{world, registry, receiver, H.State{history}, tail}, initial(receiver, history))

def query_initial(state: State, scratch: Scratch, facts: Facts, level: Level,
                  contacts: List<&2, Contact>, fuel: Nat, admitted: Bool) -> State & Result<&2, &2, Error, Observation>:
  match admitted:
    case False{}: finish(state, Done{scratch})
    case True{}: loop(fuel, state, facts, level, contacts, Done{scratch})

def query_admitted(state: State, +facts: Facts, +level: Level, +contacts: List<&2, Contact>,
                   +fuel: Nat, +admitted: Bool) -> State & Result<&2, &2, Error, Observation>:
  paired(State, Scratch, State & Result<&2, &2, Error, Observation>, state_initial(state),
    original => scratch => query_initial(original, scratch, facts, level, contacts, fuel, admitted))

def query(state: State, request: Request) -> State & Result<&2, &2, Error, Observation>:
  match request:
    case Request{facts, level, removed, physics, alive, contacts, fuel, Nil{}}:
      query_admitted(state, facts, level, contacts, fuel, Bool.not(removed || physics) && alive)
    case _: (state, Fail{NonCanonicalRequest{}})

def deflation() -> F.F64:
  F.F64{1055193269, 2147483648}

def deflated(+box: A.AABB) -> A.AABB:
  A.AABB.deflate(box, deflation(), deflation(), deflation())

def ordered(box: A.AABB) -> Bool:
  A.AABB{a, b, c, d, e, f} = box
  F.is_le(a, d) && F.is_le(b, e) && F.is_le(c, f)

def coordinate(result: Result<&2, &2, F.F64ConversionError, U32>) -> Result<&2, &2, Error, U32>:
  match result:
    case Fail{error}: Fail{InvalidCoordinate{}}
    case Done{value}: Done{value}

def box_bounds(dimension: String, box: A.AABB) -> Result<&2, &2, Error, Bounds>:
  A.AABB{a, b, c, d, e, f} = box
  do Result<&2, &2, Error, Bounds>:
    x : U32 <- coordinate(F.floor_i32(a))
    y : U32 <- coordinate(F.floor_i32(b))
    z : U32 <- coordinate(F.floor_i32(c))
    u : U32 <- coordinate(F.floor_i32(d))
    v : U32 <- coordinate(F.floor_i32(e))
    w : U32 <- coordinate(F.floor_i32(f))
    Done{Bounds{dimension, x, y, z, u, v, w}}

def stationary_bounds(dimension: String, box: A.AABB) -> Result<&2, &2, Error, Bounds>:
  box_bounds(dimension, deflated(box))

def bounds_position(bounds: Bounds) -> C.Position:
  Bounds{dimension, x, y, z, u, v, w} = bounds
  C.Position{dimension, x, y, z}

def next_bounds_gate(bounds: Bounds, lower_x: U32, lower_y: U32,
                     more_x: Bool, more_y: Bool, more_z: Bool) -> Maybe<&2, Bounds>:
  match bounds more_x more_y more_z:
    case Bounds{dimension, x, y, z, u, v, w} True{} _ _:
      Some{Bounds{dimension, U32.inc(x), y, z, u, v, w}}
    case Bounds{dimension, x, y, z, u, v, w} False{} True{} _:
      Some{Bounds{dimension, lower_x, U32.inc(y), z, u, v, w}}
    case Bounds{dimension, x, y, z, u, v, w} False{} False{} True{}:
      Some{Bounds{dimension, lower_x, lower_y, U32.inc(z), u, v, w}}
    case Bounds{dimension, x, y, z, u, v, w} False{} False{} False{}: None{}

def next_bounds(+bounds: Bounds, lower_x: U32, lower_y: U32) -> Maybe<&2, Bounds>:
  Bounds{dimension, +x, +y, +z, +u, +v, +w} = bounds
  next_bounds_gate(bounds, lower_x, lower_y, U32.is_ne(x, u), U32.is_ne(y, v), U32.is_ne(z, w))

def scan_next(fuel: Nat, state: State, +facts: Facts, +level: Level,
              +lower_x: U32, +lower_y: U32, bounds: Maybe<&2, Bounds>,
              current: Result<&2, &2, Error, Scratch>) -> State & Result<&2, &2, Error, Observation>:
  match fuel bounds current:
    case _ _ Fail{error}: finish(state, Fail{error})
    case _ None{} Done{scratch}: finish(state, Done{scratch})
    case 0n Some{bounds} Done{scratch}: finish(state, Fail{QueryBudget{}})
    case 1n+p Some{+bounds} Done{scratch}:
      paired(State, Result<&2, &2, Error, Scratch>, State & Result<&2, &2, Error, Observation>,
        contact(state, facts, level, Contact{bounds_position(bounds), BlockIntersection{}}, scratch),
        next => status => scan_next(p, next, facts, level, lower_x, lower_y, next_bounds(bounds, lower_x, lower_y), status))

def stationary_ready(state: State, facts: Facts, level: Level, fuel: Nat,
                     bounds: Result<&2, &2, Error, Bounds>) -> State & Result<&2, &2, Error, Observation>:
  match bounds:
    case Fail{error}: (state, Fail{error})
    case Done{+bounds}:
      Bounds{dimension, x, y, z, u, v, w} = bounds
      paired(State, Scratch, State & Result<&2, &2, Error, Observation>, state_initial(state),
        original => scratch => scan_next(fuel, original, facts, level, x, y, Some{bounds}, Done{scratch}))

def stationary_box(state: State, facts: Facts, level: Level, dimension: String,
                   +box: A.AABB, fuel: Nat, valid: Bool) -> State & Result<&2, &2, Error, Observation>:
  match valid:
    case False{}: (state, Fail{InvalidBox{}})
    case True{}: stationary_ready(state, facts, level, fuel, stationary_bounds(dimension, box))

# Exact stationary Entity.checkInsideBlocks slice for the supported callback
# classes whose entity-inside shape is Shapes.block. Moving sweep admission is
# deliberately separate; this entry does not substitute a final-position box.
def stationary_admitted(state: State, facts: Facts, level: Level, dimension: String,
                        +box: A.AABB, fuel: Nat, admitted: Bool) -> State & Result<&2, &2, Error, Observation>:
  match admitted:
    case False{}: query_admitted(state, facts, level, [], fuel, False{})
    case True{}:
      stationary_box(state, facts, level, dimension, box, fuel,
        Maybe.is_none(&2, U32, A.AABB.invalid_field(box)) && ordered(box))

def stationary(state: State, request: Stationary) -> State & Result<&2, &2, Error, Observation>:
  Stationary{facts, level, removed, physics, alive, dimension, box, fuel} = request
  stationary_admitted(state, facts, level, dimension, box, fuel, Bool.not(removed || physics) && alive)
