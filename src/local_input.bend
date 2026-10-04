import Base
import ./f64.bend as F
import ./movement.bend as M
import ./locomotion.bend as L
import ./travel.bend as T
import ./player_tick.bend as P
import ./player_input.bend as PI

# The previous sampled ClientInput and the currently held device buttons are
# distinct. Bob values are LocalPlayer's degree-valued float animation cache.
type State is Data:
  State{keys: PI.Buttons, movement: PI.Vector, sprint_trigger: U32, crouching: Bool,
        x_bob: F32, y_bob: F32, x_bob_old: F32, y_bob_old: F32}

type Pose is Data:
  Standing{}
  Crouching{}
  OtherPose{}

type Abilities is Data:
  Abilities{mayfly: Bool, flying: Bool}

type Mode is Data:
  Neutral{}
  NonControlledCamera{}
  Swimming{}
  FallFlying{}
  Passenger{}
  UsingItem{}
  Screen{}
  AutoJump{}
  NoPhysics{}
  Sleeping{}
  VisualCrawling{}
  Portal{}
  PushOutNeeded{}
  EdgeBackoffNeeded{}
  Immobile{}
  NonNeutralEffects{}

# Fit results and the previous minor collision come from actual world/body
# observations. This module does not forge these observations or own a world.
type Context is Data:
  Context{fits_standing: Bool, fits_crouching: Bool, food_level: U32,
          abilities: Abilities, mobility_restricted: Bool,
          horizontal_collision: Bool, minor_horizontal_collision: Bool,
          sprint_window: U32, pose: Pose, mode: Mode}

type Controls is Data:
  Controls{state: State, sprinting: Bool, sprint_updates: List<&2, Bool>}

# The caller resolves attributes AFTER the control phase's sprint decision.
# P.Context.travel.yaw and pitch are Java degree-valued F32 angles.
type ApplyContext is Data:
  ApplyContext{tick: P.Context, sneaking_speed: F.F64, pitch: F32}

type PreTravel is Data:
  PreTravel{local: State, player: P.PreTravel}

type Error is Data:
  UnsupportedContext{mode: Mode}
  UnsupportedPose{}
  UnsupportedAbilities{}
  InvalidState{field: U32}
  InvalidAttribute{}
  InvalidPitch{}
  SprintContextMismatch{}
  PlayerError{cause: P.Error}

def initial() -> State:
  State{PI.empty(), PI.Vector{0.0, 0.0}, 0, False{}, 0.0, 0.0, 0.0, 0.0}

def positive(+word: U32) -> Bool:
  U32.is_ne(word, 0) && U32.is_le(word, 2147483647)

def choose_bool(selected: Bool, yes: Bool, no: Bool) -> Bool:
  match selected:
    case True{}: yes
    case False{}: no

def choose_word(selected: Bool, yes: U32, no: U32) -> U32:
  match selected:
    case True{}: yes
    case False{}: no

def same_bool(first: Bool, second: Bool) -> Bool:
  match first second:
    case False{} False{}: True{}
    case True{} True{}: True{}
    case _ _: False{}

def forward(vector: PI.Vector) -> Bool:
  PI.Vector{x, z} = vector
  F32.is_gt(z, L.float_bits(925353388))

def jump_key(keys: PI.Buttons) -> Bool:
  PI.Buttons{f, b, l, r, j, h, s} = keys
  j

def sprint_key(keys: PI.Buttons) -> Bool:
  PI.Buttons{f, b, l, r, j, h, s} = keys
  s

def crouch(old: PI.Buttons, fits_standing: Bool, fits_crouching: Bool) -> Bool:
  PI.Buttons{f, b, l, r, j, h, s} = old
  fits_crouching && (h || Bool.not(fits_standing))

# FoodData.hasEnoughFood widens the signed int to float before comparing >6f.
def enough_food(food: U32, mayfly: Bool) -> Bool:
  F32.is_gt(F.to_f32(F.from_i32(food)), 6.0) || mayfly

def possible(food: U32, mayfly: Bool, mobility: Bool) -> Bool:
  Bool.not(mobility) && enough_food(food, mayfly)

def can_start(current: Bool, next_forward: Bool, allowed: Bool, slow: Bool) -> Bool:
  Bool.not(current) && next_forward && allowed && Bool.not(slow)

def reset_trigger(old: PI.Buttons, next: PI.Buttons, trigger: U32) -> U32:
  PI.Buttons{f, b, l, r, j, h, s} = old
  PI.Buttons{nf, nb, nl, nr, nj, nh, ns} = next
  choose_word(h || nb, 0, trigger)

def start_trigger(+trigger: U32, window: U32, old_forward: Bool, can_start: Bool) -> U32:
  choose_word(can_start && Bool.not(old_forward) && Bool.not(positive(trigger)), window, trigger)

def start_sprint(current: Bool, can_start: Bool, old_forward: Bool, trigger: U32, key: Bool) -> Bool:
  current || (can_start && (key || (Bool.not(old_forward) && positive(trigger))))

def stop_sprint(current: Bool, allowed: Bool, next_forward: Bool, horizontal: Bool, minor: Bool) -> Bool:
  current && allowed && next_forward && (Bool.not(horizontal) || minor)

def update_command(selected: Bool, value: Bool, rest: List<&2, Bool>) -> List<&2, Bool>:
  match selected:
    case False{}: rest
    case True{}: value <> rest

def sprint_commands(+can_start: Bool, old_forward: Bool, trigger: U32, key: Bool, started: Bool, kept: Bool) -> List<&2, Bool>:
  update_command(can_start && Bool.not(old_forward) && positive(trigger), True{},
    update_command(can_start && key, True{}, update_command(started && Bool.not(kept), False{}, Nil{})))

def controls_sample(state: State, +current: Bool, context: Context, sample: PI.Sample) -> Controls:
  State{+old, +old_move, trigger, old_crouch, x, y, xo, yo} = state
  Context{standing, crouching, food, Abilities{+mayfly, +flying}, mobility, horizontal, minor, window, pose, mode} = context
  PI.Sample{+next, move, +next_forward} = sample
  +crouching_now = Bool.not(flying) && crouch(old, standing, crouching)
  +allowed = possible(food, mayfly, mobility)
  +eligible = can_start(current, next_forward, allowed, crouching_now)
  +old_forward = forward(old_move)
  +remaining = reset_trigger(old, next, P.decrement(trigger))
  +key = sprint_key(next)
  +started = start_sprint(current, eligible, old_forward, remaining, key)
  +kept = stop_sprint(started, allowed, next_forward, horizontal, minor)
  Controls{State{next, move, start_trigger(remaining, window, old_forward, eligible), crouching_now, x, y, xo, yo},
    kept, sprint_commands(eligible, old_forward, remaining, key, started, kept)}

def controls(state: State, current: Bool, held: PI.Buttons, context: Context) -> Controls:
  controls_sample(state, current, context, PI.sample(held))

def sqrt32(value: F32) -> F32:
  F.to_f32(F.sqrt(F.from_f32(value)))

def length_squared(vector: PI.Vector) -> F32:
  PI.Vector{+x, +z} = vector
  F32.add(F32.mul(x, x), F32.mul(z, z))

def length(vector: PI.Vector) -> F32:
  sqrt32(length_squared(vector))

def scale(vector: PI.Vector, +factor: F32) -> PI.Vector:
  PI.Vector{x, z} = vector
  PI.Vector{F32.mul(x, factor), F32.mul(z, factor)}

def abs32(value: F32) -> F32:
  L.float_bits(U32.and(F32.bits(value), 2147483647))

def ratio(+x: F32, +z: F32, z_larger: Bool) -> F32:
  match z_larger:
    case True{}: F32.div(x, z)
    case False{}: F32.div(z, x)

def distance_ratio(+value: F32) -> F32:
  sqrt32(F32.add(1.0, F32.mul(value, value)))

def distance_to_square(vector: PI.Vector) -> F32:
  PI.Vector{x, z} = vector
  +a = abs32(x)
  +b = abs32(z)
  distance_ratio(ratio(a, b, F32.is_gt(b, a)))

def cap_one(value: F32, exceeds: Bool) -> F32:
  match exceeds:
    case True{}: 1.0
    case False{}: value

def square_unit(+unit: PI.Vector, size: F32) -> PI.Vector:
  +speed = F32.mul(size, distance_to_square(unit))
  scale(unit, cap_one(speed, F32.is_gt(speed, 1.0)))

def square_gate(vector: PI.Vector, +size: F32, nonpositive: Bool) -> PI.Vector:
  match nonpositive:
    case True{}: vector
    case False{}: square_unit(scale(vector, F32.div(1.0, size)), size)

def square_movement(+vector: PI.Vector) -> PI.Vector:
  +size = length(vector)
  square_gate(vector, size, F32.is_le(size, 0.0))

def slowdown(vector: PI.Vector, speed: F.F64, active: Bool) -> PI.Vector:
  match active:
    case False{}: vector
    case True{}: scale(vector, F.to_f32(speed))

def modify_gate(vector: PI.Vector, speed: F.F64, slow: Bool, zero_length: Bool) -> PI.Vector:
  match zero_length:
    case True{}: vector
    case False{}: square_movement(slowdown(scale(vector, L.float_bits(1065017672)), speed, slow))

def modify_input(+vector: PI.Vector, speed: F.F64, slow: Bool) -> PI.Vector:
  modify_gate(vector, speed, slow, F32.is_eq(length_squared(vector), 0.0))

def bob(+old: F32, angle: F32) -> F32:
  F32.add(old, F32.mul(F32.sub(angle, old), 0.5))

def replace_input(input: P.Input, vector: PI.Vector) -> P.Input:
  P.Input{x, y, z} = input
  PI.Vector{nx, nz} = vector
  P.Input{nx, y, nz}

def applied_vector(local: State, player: P.State, context: ApplyContext, vector: PI.Vector) -> State & P.State:
  State{+keys, move, trigger, +crouching_now, +x, +y, xo, yo} = local
  P.State{body, input, old_jump, delay, jump_trigger, sync, stored, head} = player
  ApplyContext{P.Context{T.Context{ground, attributes, +yaw, maximum, sprinting, no_gravity, discard, travel_mode}, strength, factor, affected, tick_mode}, sneak, pitch} = context
  (State{keys, move, trigger, crouching_now, bob(x, pitch), bob(y, yaw), x, y},
    P.State{body, replace_input(input, vector), jump_key(keys), delay, jump_trigger, sync, stored, head})

def applied_state(+local: State, player: P.State, +context: ApplyContext) -> State & P.State:
  State{keys, move, trigger, slow, x, y, xo, yo} = local
  ApplyContext{tick, sneak, pitch} = context
  applied_vector(local, player, context, modify_input(move, sneak, slow))

def cleaned_state(player: P.State) -> P.State:
  P.State{body, input, jumping, delay, trigger, sync, speed, head} = player
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = body
  P.State{M.Body{position, box, P.clean_velocity(velocity), width, height, ground, horizontal, vertical, below},
    input, jumping, P.decrement(delay), P.decrement(trigger), sync, speed, head}

def first_error(first: Maybe<&2, Error>, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match first:
    case Some{error}: Some{error}
    case None{}: rest

def field_error(field: U32, valid: Bool, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match valid:
    case False{}: Some{InvalidState{field}}
    case True{}: rest

def state_error(state: State) -> Maybe<&2, Error>:
  State{keys, PI.Vector{x, z}, trigger, crouching_now, bx, by, ox, oy} = state
  field_error(0, F.is_finite(F.from_f32(x)),
  field_error(1, F.is_finite(F.from_f32(z)),
  field_error(2, F.is_finite(F.from_f32(bx)),
  field_error(3, F.is_finite(F.from_f32(by)),
  field_error(4, F.is_finite(F.from_f32(ox)),
  field_error(5, F.is_finite(F.from_f32(oy)), None{}))))))

def mode_error(mode: Mode) -> Maybe<&2, Error>:
  match mode:
    case Neutral{}: None{}
    case mode: Some{UnsupportedContext{mode}}

def pose_error(pose: Pose) -> Maybe<&2, Error>:
  match pose:
    case OtherPose{}: Some{UnsupportedPose{}}
    case _: None{}

def abilities_error(abilities: Abilities) -> Maybe<&2, Error>:
  match abilities:
    case Abilities{mayfly, flying}: None{}

def context_error(context: Context) -> Maybe<&2, Error>:
  Context{standing, crouching_now, food, abilities, mobility, horizontal, minor, window, pose, mode} = context
  first_error(mode_error(mode), first_error(pose_error(pose), abilities_error(abilities)))

def controls_result(value: Controls, error: Maybe<&2, Error>) -> Result<&2, &2, Error, Controls>:
  match error:
    case Some{error}: Fail{error}
    case None{}: Done{value}

def controls_gate(state: State, current: Bool, held: PI.Buttons, context: Context, error: Maybe<&2, Error>) -> Result<&2, &2, Error, Controls>:
  match error:
    case Some{error}: Fail{error}
    case None{}: controls_result(controls(state, current, held, context), None{})

def controls_checked(+state: State, current: Bool, held: PI.Buttons, +context: Context) -> Result<&2, &2, Error, Controls>:
  controls_gate(state, current, held, context, first_error(context_error(context), state_error(state)))

def player_error(error: Maybe<&2, P.Error>) -> Maybe<&2, Error>:
  match error:
    case None{}: None{}
    case Some{cause}: Some{PlayerError{cause}}

def attribute_error(valid: Bool) -> Maybe<&2, Error>:
  match valid:
    case True{}: None{}
    case False{}: Some{InvalidAttribute{}}

def pitch_error(valid: Bool) -> Maybe<&2, Error>:
  match valid:
    case True{}: None{}
    case False{}: Some{InvalidPitch{}}

def sprint_error(matches: Bool) -> Maybe<&2, Error>:
  match matches:
    case True{}: None{}
    case False{}: Some{SprintContextMismatch{}}

def apply_error(controls: Controls, player: P.State, +context: ApplyContext) -> Maybe<&2, Error>:
  Controls{state, sprinting, updates} = controls
  ApplyContext{+tick, sneak, pitch} = context
  P.Context{T.Context{sample, attrs, yaw, maximum, current_sprint, no_gravity, discard, travel_mode}, strength, factor, affected, mode} = tick
  first_error(state_error(state), first_error(player_error(P.state_error(player)),
    first_error(player_error(P.context_error(tick)), first_error(sprint_error(same_bool(sprinting, current_sprint)),
    first_error(attribute_error(T.finite_range(sneak, M.zero(), M.one())), pitch_error(F.is_finite(F.from_f32(pitch))))))))

def prepared_result(local: State, result: L.Tables & Result<&2, &2, P.Error, P.PreTravel>) -> L.Tables & Result<&2, &2, Error, PreTravel>:
  (tables, value) = result
  match value:
    case Fail{cause}: (tables, Fail{PlayerError{cause}})
    case Done{prepared}: (tables, Done{PreTravel{local, prepared}})

def applied_gate(tables: L.Tables, local: State, player: P.State, context: P.Context, error: Maybe<&2, Error>) -> L.Tables & Result<&2, &2, Error, PreTravel>:
  match error:
    case Some{error}: (tables, Fail{error})
    case None{}: prepared_result(local, P.preparation_result(P.prepared_state(tables, player, context)))

def prepare_applied(tables: L.Tables, applied: State & P.State, context: P.Context) -> L.Tables & Result<&2, &2, Error, PreTravel>:
  (+local, +player) = applied
  applied_gate(tables, local, player, context, first_error(state_error(local), player_error(P.state_error(player))))

def prepare_ability(local: State, +context: ApplyContext, read: L.Tables & P.State) -> L.Tables & Result<&2, &2, Error, PreTravel>:
  ApplyContext{tick, sneak, pitch} = context
  (tables, player) = read
  prepare_applied(tables, applied_state(local, cleaned_state(player), context), tick)


def prepare(tables: L.Tables, controls: Controls, player: P.State, +context: ApplyContext) -> L.Tables & Result<&2, &2, Error, PreTravel>:
  Controls{local, sprinting, updates} = controls
  ApplyContext{tick, sneak, pitch} = context
  prepare_ability(local, context, P.local_ability_input(tables, player, tick))


def prepare_gate(tables: L.Tables, controls: Controls, player: P.State, +context: ApplyContext, error: Maybe<&2, Error>) -> L.Tables & Result<&2, &2, Error, PreTravel>:
  match error:
    case Some{error}: (tables, Fail{error})
    case None{}: prepare(tables, controls, player, context)

# This invokes the LocalPlayer input replacement exactly once, then the existing
# Player jump phase. Calling P.prepare_checked here would decay .98f twice.
def prepare_checked(tables: L.Tables, +controls: Controls, +player: P.State, +context: ApplyContext) -> L.Tables & Result<&2, &2, Error, PreTravel>:
  prepare_gate(tables, controls, player, context, apply_error(controls, player, context))

law rejected_preparation_retains_tables:
  for tables: L.Tables
  for controls: Controls
  for player: P.State
  for context: ApplyContext
  for +error: Error
  {prepare_gate(tables, controls, player, context, Some{error}) == (tables, Fail{error}) : L.Tables & Result<&2, &2, Error, PreTravel>}

def rejected_preparation_retains_tables(tables, controls, player, context, error):
  {==}

law rejected_controls_do_not_sample_held_buttons:
  for state: State
  for current: Bool
  for held: PI.Buttons
  for context: Context
  for +error: Error
  {controls_gate(state, current, held, context, Some{error}) == Fail{error} : Result<&2, &2, Error, Controls>}

def rejected_controls_do_not_sample_held_buttons(state, current, held, context, error):
  {==}

law input_replacement_preserves_vertical_input:
  for x: F32
  for +y: F32
  for z: F32
  for +nx: F32
  for +nz: F32
  {replace_input(P.Input{x, y, z}, PI.Vector{nx, nz}) == P.Input{nx, y, nz} : P.Input}

def input_replacement_preserves_vertical_input(x, y, z, nx, nz):
  {==}

law repeated_sprint_setters_remain_ordered:
  for +rest: List<&2, Bool>
  {update_command(True{}, True{}, update_command(True{}, True{}, rest)) == True{} <> True{} <> rest : List<&2, Bool>}

def repeated_sprint_setters_remain_ordered(rest):
  {==}
