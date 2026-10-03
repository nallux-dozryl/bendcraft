import Base
import ./player_look.bend as L
import ./f64.bend as F

# Camera angles are raw binary32 DEGREES. This owned projection does not contain
# Entity position/interpolation/invulnerability or LivingEntity body/head fields.
type State is Type:
  State{look: L.State, tick_count: U32}

type Error is Data:
  InvalidState{field: U32}
  FuelLimit{}
  FuelExhausted{axis: U32}

type Axis is Data:
  Axis{previous: F32, remaining: Nat}

def sub(a: F32, b: F32) -> F32:
  L.add(a, L.float_bits(U32.xor(L.raw(b), 2147483648)))

def below(+current: F32, previous: F32) -> Bool:
  F.is_lt(L.wide(sub(current, previous)), F.neg(F.from_u32(180)))

def above(+current: F32, previous: F32) -> Bool:
  F.is_ge(L.wide(sub(current, previous)), F.from_u32(180))

# One shared fuel unit per actual +/-360 update. Negative loop precedes positive
# loop for yaw, then negative precedes positive for pitch, matching rangeChecks.
def lower_loop(fuel: Nat, axis: U32, +current: F32, +previous: F32, needed: Bool) -> Result<&2, &2, Error, Axis>:
  match fuel needed:
    case 0n True{}: Fail{FuelExhausted{axis}}
    case 1n+rest True{}:
      +next = sub(previous, L.float_bits(1135869952))
      lower_loop(rest, axis, current, next, below(current, next))
    case _ False{}: Done{Axis{previous, fuel}}

def upper_loop(fuel: Nat, axis: U32, +current: F32, +previous: F32, needed: Bool) -> Result<&2, &2, Error, Axis>:
  match fuel needed:
    case 0n True{}: Fail{FuelExhausted{axis}}
    case 1n+rest True{}:
      +next = L.add(previous, L.float_bits(1135869952))
      upper_loop(rest, axis, current, next, above(current, next))
    case _ False{}: Done{Axis{previous, fuel}}

def lower_done(axis: U32, +current: F32, result: Result<&2, &2, Error, Axis>) -> Result<&2, &2, Error, Axis>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Axis{+previous, fuel}}: upper_loop(fuel, axis, current, previous, above(current, previous))

def normalize_axis(fuel: Nat, +axis: U32, +current: F32, +previous: F32) -> Result<&2, &2, Error, Axis>:
  lower_done(axis, current, lower_loop(fuel, axis, current, previous, below(current, previous)))

def field_error(field: U32, finite: Bool) -> Maybe<&2, Error>:
  match finite:
    case False{}: Some{InvalidState{field}}
    case True{}: None{}

def first_error(first: Maybe<&2, Error>, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match first:
    case Some{error}: Some{error}
    case None{}: rest

# All finite F32 fields are admitted. Ordered subtraction can overflow to +/-
# infinity; exact F32 comparisons still choose the actual Java loop direction.
# Fuel, rather than an angle cap or progress assumption, bounds huge histories.
def state_error(look: L.State) -> Maybe<&2, Error>:
  match look:
    case L.State{+yaw, +pitch, +old_yaw, +old_pitch}:
      first_error(field_error(0, L.finite(yaw)),
        first_error(field_error(1, L.finite(pitch)),
          first_error(field_error(2, L.finite(old_yaw)),
            field_error(3, L.finite(old_pitch)))))

def snapshot_count(+count: U32, increment: Bool) -> U32:
  match increment:
    case False{}: count
    case True{}: U32.add(count, 1)

def snapshot(look: L.State, count: U32, increment: Bool) -> State:
  match look:
    case L.State{+yaw, +pitch, _, _}: State{L.State{yaw, pitch, yaw, pitch}, snapshot_count(count, increment)}

def snapshot_gate(state: State, increment: Bool, error: Maybe<&2, Error>) -> State & Result<&2, &2, Error, Unit>:
  match state error:
    case State{look, count} Some{error}: (State{look, count}, Fail{error})
    case State{look, count} None{}: (snapshot(look, count, increment), Done{Unit{}})

def set_old_rot(state: State) -> State & Result<&2, &2, Error, Unit>:
  State{+look, count} = state
  snapshot_gate(State{look, count}, False{}, state_error(look))

# Entity.commonTick CAMERA/COUNTER projection only. Actual Java also snapshots
# position, decrements invulnerability and performs client interpolation.
def common_tick(state: State) -> State & Result<&2, &2, Error, Unit>:
  State{+look, count} = state
  snapshot_gate(State{look, count}, True{}, state_error(look))

def pitch_done(original: State, yaw: F32, result: Result<&2, &2, Error, Axis>) -> State & Result<&2, &2, Error, Unit>:
  match original result:
    case State{look, count} Fail{error}: (State{look, count}, Fail{error})
    case State{L.State{current_yaw, current_pitch, _, _}, count} Done{Axis{pitch, _}}:
      (State{L.State{current_yaw, current_pitch, yaw, pitch}, count}, Done{Unit{}})

def yaw_done(original: State, +look: L.State, result: Result<&2, &2, Error, Axis>) -> State & Result<&2, &2, Error, Unit>:
  match look result:
    case _ Fail{error}: (original, Fail{error})
    case L.State{_, pitch, _, previous} Done{Axis{yaw, fuel}}:
      pitch_done(original, yaw, normalize_axis(fuel, 1, pitch, previous))

def normalize_owned(state: State, fuel: Nat) -> State & Result<&2, &2, Error, Unit>:
  match state:
    case State{L.State{+yaw, +pitch, +old_yaw, +old_pitch}, count}:
      yaw_done(State{L.State{yaw, pitch, old_yaw, old_pitch}, count}, L.State{yaw, pitch, old_yaw, old_pitch}, normalize_axis(fuel, 0, yaw, old_yaw))

def normalize_gate(state: State, fuel: Nat, error: Maybe<&2, Error>, bounded: Bool) -> State & Result<&2, &2, Error, Unit>:
  match error bounded:
    case Some{error} _: (state, Fail{error})
    case None{} False{}: (state, Fail{FuelLimit{}})
    case None{} True{}: normalize_owned(state, fuel)

# Post-aiStep camera rangeChecks projection. Error returns the entire original
# owned State, including if yaw completed before pitch exhausted the shared fuel.
def normalize(+fuel: Nat, state: State) -> State & Result<&2, &2, Error, Unit>:
  State{+look, count} = state
  normalize_gate(State{look, count}, fuel, state_error(look), Nat.is_le(fuel, 16384n))
