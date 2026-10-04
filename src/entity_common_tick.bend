import Base
import ./f64.bend as F
import ./movement.bend as M
import ./player_look.bend as PL

# Only commonTick metadata is owned here. Current Body/position and all four
# PL angles remain caller authority; the request is immutable phase input.
type Metadata is Data:
  Metadata{position_o: M.Vec3, position_old: M.Vec3,
    invulnerable_time: U32, tick_count: U32}

type State is Type:
  State{metadata: Metadata, tail: List<&1, State>}

# This token is conditional caller evidence, not a handler/lifecycle detector.
# The actual normal LocalPlayer has an inactive SteppedInterpolationHandler.
type Context is Data:
  NeutralClientInactiveInterpolation{}
  ActiveInterpolation{}
  NonClient{}
  UnsupportedLifecycle{}

type Request is Data:
  Request{position: M.Vec3, look: PL.State, context: Context,
    tail: List<&2, Request>}

type Snapshot is Data:
  Snapshot{metadata: Metadata, look: PL.State}

type Error is Data:
  NonCanonicalState{}
  NonCanonicalRequest{}
  UnsupportedContext{context: Context}
  NonFinite{field: U32}

def first(first: Maybe<&2, Error>, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match first:
    case Some{error}: Some{error}
    case None{}: rest

def finite_field(field: U32, finite: Bool) -> Maybe<&2, Error>:
  match finite:
    case True{}: None{}
    case False{}: Some{NonFinite{field}}

def vector_error(+base: U32, vector: M.Vec3) -> Maybe<&2, Error>:
  M.Vec3{x, y, z} = vector
  first(finite_field(base, F.is_finite(x)),
    first(finite_field(U32.add(base, 1), F.is_finite(y)),
      finite_field(U32.add(base, 2), F.is_finite(z))))

def metadata_error(metadata: Metadata) -> Maybe<&2, Error>:
  Metadata{o, old, invulnerable, count} = metadata
  first(vector_error(0, o), vector_error(3, old))

def look_error(look: PL.State) -> Maybe<&2, Error>:
  PL.State{yaw, pitch, previous_yaw, previous_pitch} = look
  first(finite_field(9, PL.finite(yaw)),
    first(finite_field(10, PL.finite(pitch)),
      first(finite_field(11, PL.finite(previous_yaw)),
        finite_field(12, PL.finite(previous_pitch)))))

def context_error(context: Context) -> Maybe<&2, Error>:
  match context:
    case NeutralClientInactiveInterpolation{}: None{}
    case context: Some{UnsupportedContext{context}}

def request_error(request: Request) -> Maybe<&2, Error>:
  Request{position, look, context, tail} = request
  first(context_error(context), first(vector_error(6, position), look_error(look)))

# Java if (invulnerableTime > 0) uses signed int comparison; negative payloads
# (high bit set) are retained. No conversion through Nat or floating point.
def decrement_if(value: U32, positive: Bool) -> U32:
  match positive:
    case False{}: value
    case True{}: U32.sub(value, 1)

def decrement(+value: U32) -> U32:
  decrement_if(value, U32.is_gt(value, 0) && U32.is_lt(value, 2147483648))

def counter(+value: U32, common: Bool) -> U32:
  match common:
    case False{}: value
    case True{}: U32.add(value, 1)

def invulnerability(value: U32, common: Bool) -> U32:
  match common:
    case False{}: value
    case True{}: decrement(value)

def copied_metadata(metadata: Metadata, +position: M.Vec3, +common: Bool) -> Metadata:
  Metadata{o, old, invulnerable, count} = metadata
  Metadata{position, position, invulnerability(invulnerable, common), counter(count, common)}

def copied_look(look: PL.State) -> PL.State:
  PL.State{+yaw, +pitch, previous_yaw, previous_pitch} = look
  PL.State{yaw, pitch, yaw, pitch}

def accepted(metadata: Metadata, request: Request, common: Bool) -> State & Result<&2, &2, Error, Snapshot>:
  Request{position, look, context, tail} = request
  +next = copied_metadata(metadata, position, common)
  (State{next, []}, Done{Snapshot{next, copied_look(look)}})

def guarded(state: State, request: Request, common: Bool, error: Maybe<&2, Error>) -> State & Result<&2, &2, Error, Snapshot>:
  match state error:
    case State{metadata, tail} Some{cause}: (State{metadata, tail}, Fail{cause})
    case State{metadata, tail} None{}: accepted(metadata, request, common)

def canonical_request(state: State, request: Request, common: Bool) -> State & Result<&2, &2, Error, Snapshot>:
  match state request:
    case State{metadata, tail} Request{position, look, context, _ <> _}: (State{metadata, tail}, Fail{NonCanonicalRequest{}})
    case State{+metadata, tail} Request{+position, +look, +context, Nil{}}:
      guarded(State{metadata, tail}, Request{position, look, context, []}, common,
        first(context_error(context), first(metadata_error(metadata),
          first(vector_error(6, position), look_error(look)))))

def snapshot(state: State, request: Request, common: Bool) -> State & Result<&2, &2, Error, Snapshot>:
  match state:
    case State{metadata, child <> tail}: (State{metadata, child <> tail}, Fail{NonCanonicalState{}})
    case State{metadata, Nil{}}: canonical_request(State{metadata, []}, request, common)

# Final Entity.setOldPosAndRot() snapshots both position triples and angles.
# It does not decrement invulnerability or increment the count.
def set_old_pos_and_rot(state: State, request: Request) -> State & Result<&2, &2, Error, Snapshot>:
  snapshot(state, request, False{})

# Neutral Entity.commonTick projection only. Actual order is signed countdown,
# position/angle snapshot, inactive client handler call, then wrapping count.
# Handler cancel/reset internals are not represented; current Body is external.
def common_tick(state: State, request: Request) -> State & Result<&2, &2, Error, Snapshot>:
  snapshot(state, request, True{})

law refusal_returns_complete_original_owner:
  for state: State
  for request: Request
  for common: Bool
  for error: Error
  {guarded(state, request, common, Some{error}) == (state, Fail{error}) : State & Result<&2, &2, Error, Snapshot>}

def refusal_returns_complete_original_owner(state, request, common, error):
  match state:
    case State{metadata, tail}: {==}

law snapshot_copies_both_old_positions_and_preserves_countdown:
  for o: M.Vec3
  for old: M.Vec3
  for +position: M.Vec3
  for invulnerable: U32
  for count: U32
  {copied_metadata(Metadata{o, old, invulnerable, count}, position, False{}) ==
    Metadata{position, position, invulnerable, count} : Metadata}

def snapshot_copies_both_old_positions_and_preserves_countdown(o, old, position, invulnerable, count):
  {==}

law snapshot_preserves_current_angles_exactly:
  for +yaw: F32
  for +pitch: F32
  for previous_yaw: F32
  for previous_pitch: F32
  {copied_look(PL.State{yaw, pitch, previous_yaw, previous_pitch}) ==
    PL.State{yaw, pitch, yaw, pitch} : PL.State}

def snapshot_preserves_current_angles_exactly(yaw, pitch, previous_yaw, previous_pitch):
  {==}

law noncanonical_request_retains_state:
  for state: State
  for position: M.Vec3
  for look: PL.State
  for context: Context
  for child: Request
  for tail: List<&2, Request>
  for common: Bool
  {canonical_request(state, Request{position, look, context, child <> tail}, common) ==
    (state, Fail{NonCanonicalRequest{}}) : State & Result<&2, &2, Error, Snapshot>}

def noncanonical_request_retains_state(state, position, look, context, child, tail, common):
  match state:
    case State{metadata, owned}: {==}

law noncanonical_owned_tail_retains_every_child:
  for metadata: Metadata
  for child: State
  for tail: List<&1, State>
  for request: Request
  for common: Bool
  {snapshot(State{metadata, child <> tail}, request, common) ==
    (State{metadata, child <> tail}, Fail{NonCanonicalState{}}) : State & Result<&2, &2, Error, Snapshot>}

def noncanonical_owned_tail_retains_every_child(metadata, child, tail, request, common):
  {==}
