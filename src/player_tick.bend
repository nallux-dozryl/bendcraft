import Base
import ./f64.bend as F
import ./geometry.bend as G
import ./movement.bend as M
import ./locomotion.bend as L
import ./travel.bend as T

type Input is Data:
  Input{xxa: F32, yya: F32, zza: F32}

type State is Data:
  State{body: M.Body, input: Input, jumping: Bool, jump_delay: U32, jump_trigger: U32,
        needs_sync: Bool, stored_speed: F32, head_yaw: F32}

type Mode is Data:
  Neutral{}
  Immobile{}
  Interpolating{}
  SimulationDisabled{}
  IneffectiveAi{}
  NonEmptyEquipment{}
  NearbyActors{}
  NonNeutralEffects{}

type Context is Data:
  Context{travel: T.Context, jump_strength: F.F64, jump_factor: F32, affected_by_fluids: Bool, mode: Mode}

type PreTravel is Data:
  PreTravel{state: State, input: M.Vec3, jump_attempted: Bool, jumped: Bool}

type Transition is Data:
  Transition{state: State, movement: M.Transition, jump_attempted: Bool, jumped: Bool}

type Error is Data:
  UnsupportedContext{mode: Mode}
  TravelError{cause: T.Error}
  InvalidState{field: U32}
  InvalidJump{field: U32}

def choose_f64(selected: Bool, yes: F.F64, no: F.F64) -> F.F64:
  match selected:
    case True{}: yes
    case False{}: no

def decrement_gate(value: U32, positive: Bool) -> U32:
  match positive:
    case False{}: value
    case True{}: U32.sub(value, 1)

# Raw signed Java-int words: only strictly positive values decrement.
def decrement(+value: U32) -> U32:
  decrement_gate(value, U32.is_ne(value, 0) && U32.is_le(value, 2147483647))

def clean_component(+value: F.F64) -> F.F64:
  choose_f64(F.is_lt(F.abs(value), F.F64{1063818100, 3161095930}), M.zero(), value)

def clean_horizontal(vector: M.Vec3, clear: Bool) -> M.Vec3:
  match vector clear:
    case M.Vec3{x, y, z} True{}: M.Vec3{M.zero(), clean_component(y), M.zero()}
    case M.Vec3{x, y, z} False{}: M.Vec3{x, clean_component(y), z}

def clean_velocity(+vector: M.Vec3) -> M.Vec3:
  clean_horizontal(vector, F.is_lt(M.Vec3.horizontal_squared(vector), F.F64{1055055830, 2496441151}))

def decay(input: Input) -> Input:
  match input:
    case Input{x, y, z}: Input{F32.mul(x, L.float_bits(1065017672)), y, F32.mul(z, L.float_bits(1065017672))}

def input_vector(input: Input) -> M.Vec3:
  match input:
    case Input{x, y, z}: M.Vec3{F.from_f32(x), F.from_f32(y), F.from_f32(z)}

def jump_power(strength: F.F64, factor: F32) -> F32:
  F32.add(F32.mul(F32.mul(F.to_f32(strength), 1.0), factor), 0.0)

def jump_height(+old: F.F64, +power: F.F64) -> F.F64:
  choose_f64(F.is_gt(old, power), old, power)

def jump_velocity(vector: M.Vec3, power: F32) -> M.Vec3:
  match vector:
    case M.Vec3{x, y, z}: M.Vec3{x, jump_height(y, F.from_f32(power)), z}

def sprint_impulse(sine: F32, cosine: F32) -> M.Vec3:
  M.Vec3{F.mul(F.from_f32(L.float_bits(U32.xor(F32.bits(sine), 2147483648))), F.F64{1070176665, 2576980378}), M.zero(), F.mul(F.from_f32(cosine), F.F64{1070176665, 2576980378})}

def sprint_cosine(vector: M.Vec3, sine: F32, read: L.Tables & F32) -> L.Tables & M.Vec3:
  (tables, cosine) = read
  (tables, M.Vec3.add(vector, sprint_impulse(sine, cosine)))

def sprint_sine(vector: M.Vec3, angle: F.F64, read: L.Tables & F32) -> L.Tables & M.Vec3:
  (tables, sine) = read
  sprint_cosine(vector, sine, L.cos(tables, angle))

def sprint_jump(tables: L.Tables, vector: M.Vec3, yaw: F32, sprinting: Bool) -> L.Tables & M.Vec3:
  match sprinting:
    case False{}: (tables, vector)
    case True{}:
      +angle = F.from_f32(F32.mul(yaw, L.float_bits(1016003125)))
      sprint_sine(vector, angle, L.sin(tables, angle))

def pretravel(state: State, attempted: Bool, jumped: Bool) -> PreTravel:
  match state:
    case State{body, +input, jumping, delay, trigger, sync, speed, head}:
      PreTravel{State{body, input, jumping, delay, trigger, sync, speed, head}, input_vector(input), attempted, jumped}

def jumped_state(body: M.Body, input: Input, jumping: Bool, delay: U32, trigger: U32, speed: F32, head: F32,
                 read: L.Tables & M.Vec3) -> L.Tables & PreTravel:
  (tables, velocity) = read
  (tables, pretravel(State{T.body_velocity(body, velocity), input, jumping, delay, trigger, True{}, speed, head}, True{}, True{}))

def jump_guard(tables: L.Tables, body: M.Body, input: Input, jumping: Bool, trigger: U32, sync: Bool, speed: F32, head: F32,
               +power: F32, yaw: F32, sprinting: Bool, perform: Bool) -> L.Tables & PreTravel:
  match body perform:
    case body False{}: (tables, pretravel(State{body, input, jumping, 10, trigger, sync, speed, head}, True{}, False{}))
    case M.Body{position, box, +velocity, width, height, ground, horizontal, vertical, below} True{}:
      jumped_state(M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below}, input, jumping, 10, trigger, speed, head,
                   sprint_jump(tables, jump_velocity(velocity, power), yaw, sprinting))

def jump_attempt(tables: L.Tables, state: State, context: Context) -> L.Tables & PreTravel:
  match state context:
    case State{body, input, jumping, delay, trigger, sync, speed, head}
         Context{T.Context{sample, attributes, yaw, maximum, sprinting, no_gravity, discard, mode}, strength, factor, affected, tick_mode}:
      +power = jump_power(strength, factor)
      jump_guard(tables, body, input, jumping, trigger, sync, speed, head, power, yaw, sprinting, F32.is_gt(power, L.float_bits(925353388)))

def jump_gate(tables: L.Tables, state: State, context: Context, holding: Bool, attempt: Bool) -> L.Tables & PreTravel:
  match state holding attempt:
    case State{body, input, jumping, delay, trigger, sync, speed, head} False{} _:
      (tables, pretravel(State{body, input, jumping, 0, trigger, sync, speed, head}, False{}, False{}))
    case state True{} False{}: (tables, pretravel(state, False{}, False{}))
    case state True{} True{}: jump_attempt(tables, state, context)

def prepared_state(tables: L.Tables, +state: State, +context: Context) -> L.Tables & PreTravel:
  State{M.Body{position, box, velocity, width, height, +ground, horizontal, vertical, below}, input, +jumping, +delay, trigger, sync, speed, head} = state
  Context{travel, strength, factor, +affected, mode} = context
  jump_gate(tables, state, context, jumping && affected, ground && U32.is_eq(delay, 0))

def prepare(tables: L.Tables, state: State, context: Context) -> L.Tables & PreTravel:
  match state:
    case State{body, input, jumping, delay, trigger, sync, speed, head}:
      M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = body
      prepared_state(tables, State{M.Body{position, box, clean_velocity(velocity), width, height, ground, horizontal, vertical, below}, decay(input), jumping, decrement(delay), decrement(trigger), sync, speed, head}, context)

def mode_error(mode: Mode) -> Maybe<&2, Error>:
  match mode:
    case Neutral{}: None{}
    case mode: Some{UnsupportedContext{mode}}

def travel_error(error: Maybe<&2, T.Error>) -> Maybe<&2, Error>:
  match error:
    case None{}: None{}
    case Some{cause}: Some{TravelError{cause}}

def first_error(first: Maybe<&2, Error>, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match first:
    case Some{error}: Some{error}
    case None{}: rest

def state_field(field: U32, valid: Bool, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match valid:
    case False{}: Some{InvalidState{field}}
    case True{}: rest

def jump_field(field: U32, valid: Bool, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match valid:
    case False{}: Some{InvalidJump{field}}
    case True{}: rest

def context_error(context: Context) -> Maybe<&2, Error>:
  match context:
    case Context{travel, strength, factor, affected, mode}:
      first_error(mode_error(mode), first_error(travel_error(T.context_error(travel)),
        jump_field(0, T.finite_range(strength, M.zero(), F.F64{1077936128, 0}),
        jump_field(1, T.finite_range(F.from_f32(factor), M.zero(), M.one()), None{}))))

def state_error(state: State) -> Maybe<&2, Error>:
  match state:
    case State{body, Input{x, y, z}, jumping, delay, trigger, sync, speed, head}:
      first_error(travel_error(T.movement_error(M.Body.invalid(body))),
        state_field(0, F.is_finite(F.from_f32(x)),
        state_field(1, F.is_finite(F.from_f32(y)),
        state_field(2, F.is_finite(F.from_f32(z)),
        state_field(5, F.is_finite(F.from_f32(speed)),
        state_field(6, F.is_finite(F.from_f32(head)), None{}))))))

def prepared_result(value: PreTravel, error: Maybe<&2, Error>) -> Result<&2, &2, Error, PreTravel>:
  match error:
    case Some{error}: Fail{error}
    case None{}: Done{value}

def preparation_result(read: L.Tables & PreTravel) -> L.Tables & Result<&2, &2, Error, PreTravel>:
  (tables, +value) = read
  PreTravel{state, input, attempted, jumped} = value
  (tables, prepared_result(value, state_error(state)))

def prepare_gate(tables: L.Tables, state: State, context: Context, error: Maybe<&2, Error>) -> L.Tables & Result<&2, &2, Error, PreTravel>:
  match error:
    case Some{error}: (tables, Fail{error})
    case None{}: preparation_result(prepare(tables, state, context))

def prepare_checked(tables: L.Tables, +state: State, +context: Context) -> L.Tables & Result<&2, &2, Error, PreTravel>:
  prepare_gate(tables, state, context, first_error(context_error(context), state_error(state)))

def finish(prepared: PreTravel, context: Context, +movement: M.Transition) -> Transition:
  PreTravel{State{old, input, jumping, delay, trigger, sync, speed, head}, vector, attempted, jumped} = prepared
  Context{T.Context{sample, T.Attributes{current_speed, gravity, friction, drag}, yaw, maximum, sprinting, no_gravity, discard, mode}, strength, factor, affected, tick_mode} = context
  M.Transition{body, displacement, stepped, changed} = movement
  Transition{State{body, input, jumping, delay, trigger, sync, F.to_f32(current_speed), yaw}, movement, attempted, jumped}

def finished_result(value: Transition, error: Maybe<&2, Error>) -> Result<&2, &2, Error, Transition>:
  match error:
    case Some{error}: Fail{error}
    case None{}: Done{value}

def checked_finish_value(+value: Transition, error: Maybe<&2, Error>) -> Result<&2, &2, Error, Transition>:
  Transition{state, moved, attempted, jumped} = value
  finished_result(value, first_error(error, state_error(state)))

def finish_checked(prepared: PreTravel, +context: Context, movement: M.Transition) -> Result<&2, &2, Error, Transition>:
  checked_finish_value(finish(prepared, context, movement), context_error(context))

def travel_result(prepared: PreTravel, context: Context, read: L.Tables & Result<&2, &2, T.Error, M.Transition>) -> L.Tables & Result<&2, &2, Error, Transition>:
  (tables, result) = read
  match result:
    case Fail{cause}: (tables, Fail{TravelError{cause}})
    case Done{movement}: (tables, finish_checked(prepared, context, movement))

def begin_travel(tables: L.Tables, +prepared: PreTravel, +context: Context, initial: List<&2, G.Collider>, step: List<&2, G.Collider>) -> L.Tables & Result<&2, &2, Error, Transition>:
  PreTravel{State{body, input, jumping, delay, trigger, sync, speed, head}, vector, attempted, jumped} = prepared
  Context{travel, strength, factor, affected, mode} = context
  travel_result(prepared, context, T.travel_checked(tables, body, vector, travel, initial, step))

def tick_prepared(context: Context, initial: List<&2, G.Collider>, step: List<&2, G.Collider>, read: L.Tables & Result<&2, &2, Error, PreTravel>) -> L.Tables & Result<&2, &2, Error, Transition>:
  (tables, result) = read
  match result:
    case Fail{error}: (tables, Fail{error})
    case Done{prepared}: begin_travel(tables, prepared, context, initial, step)

def tick_checked(tables: L.Tables, state: State, +context: Context, initial: List<&2, G.Collider>, step: List<&2, G.Collider>) -> L.Tables & Result<&2, &2, Error, Transition>:
  tick_prepared(context, initial, step, prepare_checked(tables, state, context))

law rejected_preparation_retains_tables:
  for tables: L.Tables
  for state: State
  for context: Context
  for +error: Error
  {prepare_gate(tables, state, context, Some{error}) == (tables, Fail{error}) : L.Tables & Result<&2, &2, Error, PreTravel>}

def rejected_preparation_retains_tables(tables, state, context, error):
  {==}

law input_decay_preserves_vertical_input:
  for x: F32
  for +y: F32
  for z: F32
  {decay(Input{x, y, z}) == Input{F32.mul(x, L.float_bits(1065017672)), y, F32.mul(z, L.float_bits(1065017672))} : Input}

def input_decay_preserves_vertical_input(x, y, z):
  {==}

law horizontal_cleanup_selects_positive_zero:
  for x: F.F64
  for +y: F.F64
  for z: F.F64
  {clean_horizontal(M.Vec3{x, y, z}, True{}) == M.Vec3{M.zero(), clean_component(y), M.zero()} : M.Vec3}

def horizontal_cleanup_selects_positive_zero(x, y, z):
  {==}

law released_jump_resets_delay_without_lookup:
  for tables: L.Tables
  for +body: M.Body
  for +input: Input
  for +jumping: Bool
  for delay: U32
  for +trigger: U32
  for +sync: Bool
  for +speed: F32
  for +head: F32
  for context: Context
  for attempt: Bool
  {jump_gate(tables, State{body, input, jumping, delay, trigger, sync, speed, head}, context, False{}, attempt) == (tables, pretravel(State{body, input, jumping, 0, trigger, sync, speed, head}, False{}, False{})) : L.Tables & PreTravel}

def released_jump_resets_delay_without_lookup(tables, body, input, jumping, delay, trigger, sync, speed, head, context, attempt):
  {==}

law ineffective_jump_starts_cooldown:
  for tables: L.Tables
  for +body: M.Body
  for +input: Input
  for +jumping: Bool
  for +trigger: U32
  for +sync: Bool
  for +speed: F32
  for +head: F32
  for power: F32
  for yaw: F32
  for sprinting: Bool
  {jump_guard(tables, body, input, jumping, trigger, sync, speed, head, power, yaw, sprinting, False{}) == (tables, pretravel(State{body, input, jumping, 10, trigger, sync, speed, head}, True{}, False{})) : L.Tables & PreTravel}

def ineffective_jump_starts_cooldown(tables, body, input, jumping, trigger, sync, speed, head, power, yaw, sprinting):
  match body:
    case M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below}: {==}

law failed_travel_retains_tables:
  for prepared: PreTravel
  for context: Context
  for tables: L.Tables
  for +cause: T.Error
  {travel_result(prepared, context, (tables, Fail{cause})) == (tables, Fail{TravelError{cause}}) : L.Tables & Result<&2, &2, Error, Transition>}

def failed_travel_retains_tables(prepared, context, tables, cause):
  {==}
