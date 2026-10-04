import Base
import ./f64.bend as F
import ./geometry.bend as G
import ./movement.bend as M
import ./locomotion.bend as L

type BlockPos is Data:
  BlockPos{x: U32, y: U32, z: U32}

type GroundSample is Data:
  GroundSample{position: BlockPos, friction: F32}

# Current resolved Player attributes, not stale stored LivingEntity speed.
type Attributes is Data:
  Attributes{movement_speed: F.F64, gravity: F.F64, friction_modifier: F.F64, air_drag_modifier: F.F64}

type Mode is Data:
  NeutralDryAir{}
  Liquid{}
  Swimming{}
  AbilityFlight{}
  ResolvedFlight{speed: F32}
  Gliding{}
  Climbing{}
  PowderSnow{}
  MobEffects{}
  Passenger{}
  UnloadedClient{}
  NonNeutralBlock{}
  NonAuthoritative{}
  EdgeBackoff{}

type Context is Data:
  Context{ground: GroundSample, attributes: Attributes, yaw: F32, maximum_step: F32,
          sprinting: Bool, no_gravity: Bool, discard_friction: Bool, mode: Mode}

type Prepared is Data:
  Prepared{body: M.Body, requested: M.Vec3, friction: F32, acceleration: F32,
           maximum_step: F32, gravity: F.F64, air_drag_modifier: F.F64, discard_friction: Bool}

type Error is Data:
  UnsupportedContext{mode: Mode}
  InvalidContext{field: U32}
  InvalidAttribute{field: U32}
  InvalidInput{field: U32}
  MovementError{cause: M.Error}

def body_velocity(body: M.Body, velocity: M.Vec3) -> M.Body:
  match body:
    case M.Body{position, box, old, width, height, ground, horizontal, vertical, below}:
      M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below}

def modified_friction(block: F32, modifier: F32) -> F32:
  F32.clamp(F32.sub(1.0, F32.mul(F32.sub(1.0, block), modifier)), 0.0, 1.0)

def ground_friction(ground: GroundSample, modifier: F.F64, grounded: Bool) -> F32:
  match ground grounded:
    case _ False{}: 1.0
    case GroundSample{position, friction} True{}: modified_friction(friction, F.to_f32(modifier))

def ground_speed(speed: F.F64, +friction: F32, corrected: Bool) -> F32:
  match corrected:
    case False{}: F.to_f32(speed)
    case True{}:
      F32.mul(F.to_f32(speed), F32.div(L.float_bits(1046294300), F32.mul(F32.mul(friction, friction), friction)))

def acceleration(speed: F.F64, +friction: F32, grounded: Bool, sprinting: Bool) -> F32:
  match grounded sprinting:
    case False{} False{}: L.float_bits(1017370378)
    case False{} True{}: L.float_bits(1020591603)
    case True{} _: ground_speed(speed, friction, F.is_gt(F.from_f32(friction), F.F64{1071854387, 858993459}))

def gravity_gate(gravity: F.F64, no_gravity: Bool) -> F.F64:
  match no_gravity:
    case True{}: M.zero()
    case False{}: gravity

def prepared_input(body: M.Body, friction: F32, acceleration: F32, maximum: F32, gravity: F.F64,
                   drag: F.F64, discard: Bool, read: L.Tables & M.Vec3) -> L.Tables & Prepared:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = body
  (tables, impulse) = read
  +requested = M.Vec3.add(velocity, impulse)
  (tables, Prepared{M.Body{position, box, requested, width, height, ground, horizontal, vertical, below}, requested, friction, acceleration, maximum, gravity, drag, discard})

def prepare_values(tables: L.Tables, body: M.Body, input: M.Vec3, yaw: F32, +friction: F32,
                   speed: F.F64, maximum: F32, gravity: F.F64, drag: F.F64, discard: Bool, ground: Bool, sprinting: Bool) -> L.Tables & Prepared:
  +accel = acceleration(speed, friction, ground, sprinting)
  prepared_input(body, friction, accel, maximum, gravity, drag, discard, L.get_input_vector(tables, input, accel, yaw))

def W_flight_speed(speed: F32, sprinting: Bool) -> F32:
  match sprinting:
    case False{}: speed
    case True{}: F32.mul(speed, 2.0)


def prepare_mode(tables: L.Tables, body: M.Body, input: M.Vec3, yaw: F32, +friction: F32,
                 speed: F.F64, maximum: F32, gravity: F.F64, drag: F.F64, discard: Bool,
                 ground: Bool, sprinting: Bool, mode: Mode) -> L.Tables & Prepared:
  match ground mode:
    case False{} ResolvedFlight{+flying_speed}:
      +accel = W_flight_speed(flying_speed, sprinting)
      prepared_input(body, friction, accel, maximum, gravity, drag, discard, L.get_input_vector(tables, input, accel, yaw))
    case _ _: prepare_values(tables, body, input, yaw, friction, speed, maximum, gravity, drag, discard, ground, sprinting)



def prepare(tables: L.Tables, body: M.Body, input: M.Vec3, context: Context) -> L.Tables & Prepared:
  match body context:
    case M.Body{position, box, velocity, width, height, +grounded, horizontal, vertical, below}
         Context{sample, Attributes{speed, gravity, modifier, drag}, yaw, maximum, sprinting, no_gravity, discard, mode}:
      prepare_mode(tables, M.Body{position, box, velocity, width, height, grounded, horizontal, vertical, below}, input, yaw,
                   ground_friction(sample, modifier, grounded), speed, maximum, gravity_gate(gravity, no_gravity), drag, discard, grounded, sprinting, mode)

# Player.getFlyingSpeed is selected only for airborne flight. Ground friction
# still selects the inherited movement attribute path before the outer Player
# travel override restores vertical velocity.

def flight_mode_error(valid:Bool) -> Maybe<&2,Error>:
  match valid:
    case True{}: None{}
    case False{}: Some{InvalidAttribute{4}}

def mode_error(mode: Mode) -> Maybe<&2, Error>:
  match mode:
    case NeutralDryAir{}: None{}
    case ResolvedFlight{speed}: flight_mode_error(F.is_finite(F.from_f32(speed)))
    case +mode: Some{UnsupportedContext{mode}}

def context_field(field: U32, valid: Bool, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match valid:
    case False{}: Some{InvalidContext{field}}
    case True{}: rest

def attribute_field(field: U32, valid: Bool, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match valid:
    case False{}: Some{InvalidAttribute{field}}
    case True{}: rest

def finite_range(+value: F.F64, low: F.F64, high: F.F64) -> Bool:
  F.is_finite(value) && F.is_ge(value, low) && F.is_le(value, high)

def attributes_error(attributes: Attributes) -> Maybe<&2, Error>:
  match attributes:
    case Attributes{speed, gravity, modifier, drag}:
      attribute_field(0, finite_range(speed, M.zero(), F.F64{1083179008, 0}),
      attribute_field(1, finite_range(gravity, F.F64{3220176896, 0}, M.one()),
      attribute_field(2, finite_range(modifier, M.zero(), F.F64{1084227584, 0}),
      attribute_field(3, finite_range(drag, M.zero(), F.F64{1084227584, 0}), None{}))))

def first_error(first: Maybe<&2, Error>, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match first:
    case Some{error}: Some{error}
    case None{}: rest

def movement_error(error: Maybe<&2, M.Error>) -> Maybe<&2, Error>:
  match error:
    case Some{error}: Some{MovementError{error}}
    case None{}: None{}

def input_error(field: Maybe<&2, U32>) -> Maybe<&2, Error>:
  match field:
    case Some{field}: Some{InvalidInput{field}}
    case None{}: None{}

def context_error(context: Context) -> Maybe<&2, Error>:
  match context:
    case Context{GroundSample{position, friction}, attributes, yaw, +maximum, sprint, no_gravity, discard, mode}:
      first_error(mode_error(mode),
        context_field(0, F.is_finite(F.from_f32(yaw)),
        context_field(1, finite_range(F.from_f32(friction), M.zero(), M.one()),
        context_field(2, F.is_finite(F.from_f32(maximum)) && F.is_ge(F.from_f32(maximum), M.zero()), attributes_error(attributes)))))

def prepared_invalid(prepared: Prepared) -> Maybe<&2, Error>:
  match prepared:
    case Prepared{body, requested, friction, acceleration, maximum, gravity, drag, discard}:
      first_error(movement_error(M.Body.invalid(body)), input_error(M.Vec3.invalid_field(requested)))

def prepared_checked(prepared: Prepared, error: Maybe<&2, Error>) -> Result<&2, &2, Error, Prepared>:
  match error:
    case Some{error}: Fail{error}
    case None{}: Done{prepared}

def checked_preparation(read: L.Tables & Prepared) -> L.Tables & Result<&2, &2, Error, Prepared>:
  (tables, +prepared) = read
  (tables, prepared_checked(prepared, prepared_invalid(prepared)))

def prepare_checked_gate(tables: L.Tables, body: M.Body, input: M.Vec3, context: Context, error: Maybe<&2, Error>) -> L.Tables & Result<&2, &2, Error, Prepared>:
  match error:
    case Some{error}: (tables, Fail{error})
    case None{}: checked_preparation(prepare(tables, body, input, context))

def prepare_checked(tables: L.Tables, +body: M.Body, +input: M.Vec3, +context: Context) -> L.Tables & Result<&2, &2, Error, Prepared>:
  error = first_error(context_error(context), first_error(movement_error(M.Body.invalid(body)), input_error(M.Vec3.invalid_field(input))))
  prepare_checked_gate(tables, body, input, context, error)

def with_stuck(prepared: Prepared, value: M.StuckPreparation) -> Prepared:
  Prepared{body, requested, friction, acceleration, maximum, gravity, drag, discard} = prepared
  M.StuckPreparation{next, corrected, multiplier, applied} = value
  Prepared{next, corrected, friction, acceleration, maximum, gravity, drag, discard}

def stuck_prepared(prepared: Prepared, result: Result<&2, &2, M.Error, M.StuckPreparation>) -> Result<&2, &2, Error, Prepared>:
  match result:
    case Fail{cause}: Fail{MovementError{cause}}
    case Done{value}: Done{with_stuck(prepared, value)}

# The relative input impulse is already in Prepared.requested. Entity.move
# consumes a stuck multiplier only after that impulse, before edge/collision.
def stuck_checked(+prepared: Prepared, multiplier: M.Vec3) -> Result<&2, &2, Error, Prepared>:
  Prepared{body, requested, friction, acceleration, maximum, gravity, drag, discard} = prepared
  stuck_prepared(prepared, M.stuck_checked(body, requested, multiplier))

def drag_gate(vector: M.Vec3, gravity: F.F64, +friction: F32, drag_modifier: F.F64, discard: Bool) -> M.Vec3:
  match vector discard:
    case M.Vec3{x, y, z} True{}: M.Vec3{x, F.sub(y, gravity), z}
    case M.Vec3{x, y, z} False{}:
      +modifier = F.to_f32(drag_modifier)
      +horizontal = F.from_f32(F32.mul(friction, modified_friction(L.float_bits(1063843267), modifier)))
      vertical = F.from_f32(modified_friction(L.float_bits(1065017672), modifier))
      M.Vec3{F.mul(x, horizontal), F.mul(F.sub(y, gravity), vertical), F.mul(z, horizontal)}

def finish(prepared: Prepared, movement: M.Transition) -> M.Transition:
  match prepared movement:
    case Prepared{old, requested, friction, acceleration, maximum, gravity, drag, discard}
         M.Transition{M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below}, displacement, stepped, changed}:
      M.Transition{M.Body{position, box, drag_gate(velocity, gravity, friction, drag, discard), width, height, ground, horizontal, vertical, below}, displacement, stepped, changed}

def finish_result(value: M.Transition, error: Maybe<&2, M.Error>) -> Result<&2, &2, Error, M.Transition>:
  match error:
    case Some{error}: Fail{MovementError{error}}
    case None{}: Done{value}

def finish_checked(prepared: Prepared, movement: M.Transition) -> Result<&2, &2, Error, M.Transition>:
  +value = finish(prepared, movement)
  finish_result(value, M.transition_invalid(value))

def move_result(prepared: Prepared, moved: Result<&2, &2, M.Error, M.Transition>) -> Result<&2, &2, Error, M.Transition>:
  match moved:
    case Fail{error}: Fail{MovementError{error}}
    case Done{value}: finish_checked(prepared, value)

def move_checked(+prepared: Prepared, initial: List<&2, G.Collider>, step: List<&2, G.Collider>) -> Result<&2, &2, Error, M.Transition>:
  Prepared{body, requested, friction, acceleration, maximum, gravity, drag, discard} = prepared
  move_result(prepared, M.move_checked(body, requested, maximum, initial, step))

def travel_prepared(initial: List<&2, G.Collider>, step: List<&2, G.Collider>, read: L.Tables & Result<&2, &2, Error, Prepared>) -> L.Tables & Result<&2, &2, Error, M.Transition>:
  (tables, result) = read
  match result:
    case Fail{error}: (tables, Fail{error})
    case Done{prepared}: (tables, move_checked(prepared, initial, step))

def travel_checked(tables: L.Tables, body: M.Body, input: M.Vec3, context: Context, initial: List<&2, G.Collider>, step: List<&2, G.Collider>) -> L.Tables & Result<&2, &2, Error, M.Transition>:
  travel_prepared(initial, step, prepare_checked(tables, body, input, context))

law rejected_preparation_retains_tables:
  for tables: L.Tables
  for body: M.Body
  for input: M.Vec3
  for context: Context
  for +error: Error
  {prepare_checked_gate(tables, body, input, context, Some{error}) == (tables, Fail{error}) : L.Tables & Result<&2, &2, Error, Prepared>}

def rejected_preparation_retains_tables(tables, body, input, context, error):
  {==}

law no_gravity_selects_positive_zero:
  for gravity: F.F64
  {gravity_gate(gravity, True{}) == M.zero() : F.F64}

def no_gravity_selects_positive_zero(gravity):
  {==}

law airborne_friction_skips_sample:
  for sample: GroundSample
  for modifier: F.F64
  {ground_friction(sample, modifier, False{}) == 1.0 : F32}

def airborne_friction_skips_sample(sample, modifier):
  match sample:
    case GroundSample{position, friction}: {==}

law friction_discard_preserves_horizontal_velocity:
  for +x: F.F64
  for y: F.F64
  for +z: F.F64
  for gravity: F.F64
  for friction: F32
  for drag: F.F64
  {drag_gate(M.Vec3{x, y, z}, gravity, friction, drag, True{}) == M.Vec3{x, F.sub(y, gravity), z} : M.Vec3}

def friction_discard_preserves_horizontal_velocity(x, y, z, gravity, friction, drag):
  {==}

law failed_movement_skips_gravity_and_drag:
  for prepared: Prepared
  for +error: M.Error
  {move_result(prepared, Fail{error}) == Fail{MovementError{error}} : Result<&2, &2, Error, M.Transition>}

def failed_movement_skips_gravity_and_drag(prepared, error):
  {==}
