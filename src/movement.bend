import Base
import ./f64.bend as F
import ./geometry.bend as G

# All simulation coordinates and velocities retain exact binary64 payloads.
type Vec3 is Data:
  Vec3{x: F.F64, y: F.F64, z: F.F64}

# Feet-center position plus the current collision box and pose dimensions.
type Body is Data:
  Body{position: Vec3, box: G.AABB, velocity: Vec3, width: F32, height: F32,
       on_ground: Bool, horizontal_collision: Bool, vertical_collision: Bool,
       vertical_collision_below: Bool}

type Resolution is Data:
  Resolution{displacement: Vec3, stepped: Bool}

type Transition is Data:
  Transition{body: Body, displacement: Vec3, stepped: Bool, position_changed: Bool}

# Entity.move's consumed stuck-speed phase, before edge backoff and collision.
# The multiplier is an explicit current receiver observation. It is not inferred
# from blocks, and the returned multiplier must replace that receiver field.
type StuckPreparation is Data:
  StuckPreparation{body: Body, requested: Vec3, multiplier: Vec3, applied: Bool}

type Error is Data:
  InvalidBody{component: U32, field: U32}
  InvalidDimensions{field: U32}
  InvalidRequest{axis: U32}
  InvalidStepHeight{}
  InvalidCollider{phase: U32, index: U32, field: U32}
  ReversedCollider{phase: U32, index: U32, axis: U32}
  NonFiniteResult{component: U32, field: U32}

def zero() -> F.F64:
  F.F64{0, 0}

def one() -> F.F64:
  F.F64{1072693248, 0}

def Vec3.zero() -> Vec3:
  Vec3{zero(), zero(), zero()}

def Vec3.add(a: Vec3, b: Vec3) -> Vec3:
  match a b:
    case Vec3{ax, ay, az} Vec3{bx, by, bz}: Vec3{F.add(ax, bx), F.add(ay, by), F.add(az, bz)}

def Vec3.length_squared(v: Vec3) -> F.F64:
  match v:
    case Vec3{+x, +y, +z}: F.add(F.add(F.mul(x, x), F.mul(y, y)), F.mul(z, z))

def Vec3.horizontal_squared(v: Vec3) -> F.F64:
  match v:
    case Vec3{+x, y, +z}: F.add(F.mul(x, x), F.mul(z, z))

def Vec3.axis(v: Vec3, axis: G.Axis) -> F.F64:
  match v axis:
    case Vec3{x, y, z} G.AxisX{}: x
    case Vec3{x, y, z} G.AxisY{}: y
    case Vec3{x, y, z} G.AxisZ{}: z

def Vec3.with_axis(v: Vec3, axis: G.Axis, value: F.F64) -> Vec3:
  match v axis:
    case Vec3{x, y, z} G.AxisX{}: Vec3{value, y, z}
    case Vec3{x, y, z} G.AxisY{}: Vec3{x, value, z}
    case Vec3{x, y, z} G.AxisZ{}: Vec3{x, y, value}

def box_move(box: G.AABB, vector: Vec3) -> G.AABB:
  match vector:
    case Vec3{x, y, z}: G.AABB.move(box, x, y, z)

def expand_low(+coordinate: F.F64, +delta: F.F64) -> F.F64:
  G.select_value(F.add(coordinate, delta), coordinate, F.is_lt(delta, zero()))

def expand_high(+coordinate: F.F64, +delta: F.F64) -> F.F64:
  G.select_value(F.add(coordinate, delta), coordinate, F.is_gt(delta, zero()))

def expand_towards(box: G.AABB, vector: Vec3) -> G.AABB:
  match box vector:
    case G.AABB{a, b, c, d, e, f} Vec3{+x, +y, +z}:
      G.AABB.new(expand_low(a, x), expand_low(b, y), expand_low(c, z), expand_high(d, x), expand_high(e, y), expand_high(f, z))

def initial_block_query(box: G.AABB, requested: Vec3) -> G.AABB:
  expand_towards(box, requested)

def initial_entity_query(box: G.AABB, requested: Vec3, maximum: F32) -> G.AABB:
  expand_towards(expand_towards(box, requested), Vec3{zero(), F.from_f32(maximum), zero()})

def axis_order_gate(z_first: Bool) -> List<&2, G.Axis>:
  match z_first:
    case True{}: G.AxisY{} <> G.AxisZ{} <> G.AxisX{} <> Nil{}
    case False{}: G.AxisY{} <> G.AxisX{} <> G.AxisZ{} <> Nil{}

def axis_order(vector: Vec3) -> List<&2, G.Axis>:
  match vector:
    case Vec3{x, y, z}: axis_order_gate(F.is_lt(F.abs(x), F.abs(z)))

def collide_axis_gate(box: G.AABB, colliders: List<&2, G.Collider>, +accumulated: Vec3,
                      +axis: G.Axis, delta: F.F64, no_movement: Bool) -> Vec3:
  match no_movement:
    case True{}: accumulated
    case False{}:
      clipped = G.clip_colliders(axis, box_move(box, accumulated), colliders, delta)
      Vec3.with_axis(accumulated, axis, clipped)

def collide_axes(axes: List<&2, G.Axis>, +requested: Vec3, +box: G.AABB,
                 +colliders: List<&2, G.Collider>, accumulated: Vec3) -> Vec3:
  match axes:
    case Nil{}: accumulated
    case +axis <> rest:
      +delta = Vec3.axis(requested, axis)
      next = collide_axis_gate(box, colliders, accumulated, axis, delta, F.is_zero(delta))
      collide_axes(rest, requested, box, colliders, next)

def collide_nonempty(+requested: Vec3, box: G.AABB, colliders: List<&2, G.Collider>) -> Vec3:
  collide_axes(axis_order(requested), requested, box, colliders, Vec3.zero())

# The original AABB is moved by the accumulated vector before every nonzero
# axis. Repeatedly translating a box would introduce different IEEE rounding.
def collide_with_shapes(requested: Vec3, box: G.AABB, colliders: List<&2, G.Collider>) -> Vec3:
  match colliders:
    case Nil{}: requested
    case collider <> rest: collide_nonempty(requested, box, collider <> rest)

def cast_float(value: F.F64) -> F.F64:
  F.from_f32(F.to_f32(value))

def same_bits(a: F.F64, b: F.F64) -> Bool:
  match a b:
    case F.F64{ah, al} F.F64{bh, bl}: U32.is_eq(ah, bh) && U32.is_eq(al, bl)

def float_less(+a: F.F64, +b: F.F64) -> Bool:
  F.is_lt(a, b) || (F.is_zero(a) && F.is_zero(b) && F.sign(a) && Bool.not(F.sign(b)))

def insert_height_gate(value: F.F64, first: F.F64, rest: List<&2, F.F64>, inserted: List<&2, F.F64>, duplicate: Bool, before: Bool) -> List<&2, F.F64>:
  match duplicate before:
    case True{} _: first <> rest
    case False{} True{}: value <> first <> rest
    case False{} False{}: first <> inserted

def insert_height(+value: F.F64, heights: List<&2, F.F64>) -> List<&2, F.F64>:
  match heights:
    case Nil{}: value <> Nil{}
    case +first <> +rest: insert_height_gate(value, first, rest, insert_height(value, rest), same_bits(value, first), float_less(value, first))

def candidate_gate(heights: List<&2, F.F64>, value: F.F64, eligible: Bool) -> List<&2, F.F64>:
  match eligible:
    case True{}: insert_height(value, heights)
    case False{}: heights

def candidate(+coordinate: F.F64, min_y: F.F64, +maximum: F.F64, +previous: F.F64, heights: List<&2, F.F64>) -> List<&2, F.F64>:
  +value = cast_float(F.sub(coordinate, min_y))
  candidate_gate(heights, value, F.is_ge(value, zero()) && F.is_ne(value, previous) && F.is_le(value, maximum))

def collider_heights(collider: G.Collider, +min_y: F.F64, +maximum: F.F64, +previous: F.F64, heights: List<&2, F.F64>) -> List<&2, F.F64>:
  match collider:
    case G.EmptyCollider{}: candidate(zero(), min_y, maximum, previous, heights)
    case G.BoxCollider{G.AABB{a, +low, c, d, high, f}}:
      candidate(high, min_y, maximum, previous, candidate(low, min_y, maximum, previous, heights))

def collect_heights(colliders: List<&2, G.Collider>, +min_y: F.F64, +maximum: F.F64, +previous: F.F64, heights: List<&2, F.F64>) -> List<&2, F.F64>:
  match colliders:
    case Nil{}: heights
    case shape <> rest: collect_heights(rest, min_y, maximum, previous, collider_heights(shape, min_y, maximum, previous, heights))

def candidate_step_heights(box: G.AABB, colliders: List<&2, G.Collider>, maximum: F32, previous: F32) -> List<&2, F.F64>:
  match box:
    case G.AABB{a, min_y, c, d, e, f}: collect_heights(colliders, min_y, F.from_f32(maximum), F.from_f32(previous), Nil{})

def step_result(vector: Vec3, correction: F.F64) -> Resolution:
  match vector:
    case Vec3{x, y, z}: Resolution{Vec3{F.sub(x, zero()), F.sub(y, correction), F.sub(z, zero())}, True{}}

def min_y(box: G.AABB) -> F.F64:
  match box:
    case G.AABB{a, y, c, d, e, f}: y

def try_heights_go(heights: List<&2, F.F64>, +requested: Vec3, +original: G.AABB, +adjusted: G.AABB,
                   +colliders: List<&2, G.Collider>, +baseline: Vec3, pending: Vec3, accepted: Bool) -> Resolution:
  match heights accepted:
    case _ True{}: step_result(pending, F.sub(min_y(original), min_y(adjusted)))
    case Nil{} False{}: Resolution{baseline, False{}}
    case height <> rest False{}:
      x = Vec3.axis(requested, G.AxisX{})
      z = Vec3.axis(requested, G.AxisZ{})
      +attempt = collide_with_shapes(Vec3{x, height, z}, adjusted, colliders)
      try_heights_go(rest, requested, original, adjusted, colliders, baseline, attempt,
                    F.is_gt(Vec3.horizontal_squared(attempt), Vec3.horizontal_squared(baseline)))

def try_heights(heights: List<&2, F.F64>, requested: Vec3, original: G.AABB, adjusted: G.AABB,
                colliders: List<&2, G.Collider>, +baseline: Vec3) -> Resolution:
  try_heights_go(heights, requested, original, adjusted, colliders, baseline, baseline, False{})

def adjusted_box(box: G.AABB, baseline: Vec3, landed: Bool) -> G.AABB:
  match landed:
    case False{}: box
    case True{}:
      G.AABB.move(box, zero(), Vec3.axis(baseline, G.AxisY{}), zero())

def step_query_gate(box: G.AABB, landed: Bool) -> G.AABB:
  match landed:
    case True{}: box
    case False{}: expand_towards(box, Vec3{zero(), F.F64{3202676917, 2147483648}, zero()})

def step_query(+box: G.AABB, +requested: Vec3, +baseline: Vec3, maximum: F32) -> G.AABB:
  +landed = F.is_ne(Vec3.axis(requested, G.AxisY{}), Vec3.axis(baseline, G.AxisY{})) && F.is_lt(Vec3.axis(requested, G.AxisY{}), zero())
  expanded = expand_towards(adjusted_box(box, baseline, landed), Vec3{Vec3.axis(requested, G.AxisX{}), F.from_f32(maximum), Vec3.axis(requested, G.AxisZ{})})
  step_query_gate(expanded, landed)

def resolve_step_gate(+box: G.AABB, maximum: F32, +requested: Vec3,
                      +step_colliders: List<&2, G.Collider>, +baseline: Vec3, landed: Bool, eligible: Bool) -> Resolution:
  match eligible:
    case False{}: Resolution{baseline, False{}}
    case True{}:
      +adjusted = adjusted_box(box, baseline, landed)
      clipped_y = Vec3.axis(baseline, G.AxisY{})
      heights = candidate_step_heights(adjusted, step_colliders, maximum, F.to_f32(clipped_y))
      try_heights(heights, requested, box, adjusted, step_colliders, baseline)

def resolve_baseline(+box: G.AABB, grounded: Bool, +maximum: F32, +requested: Vec3,
                     step_colliders: List<&2, G.Collider>, +baseline: Vec3) -> Resolution:
  Vec3{+x, +y, +z} = requested
  Vec3{cx, cy, cz} = baseline
  +landed = F.is_ne(y, cy) && F.is_lt(y, zero())
  eligible = F.is_gt(F.from_f32(maximum), zero()) && (landed || grounded) && (F.is_ne(x, cx) || F.is_ne(z, cz))
  resolve_step_gate(box, maximum, requested, step_colliders, baseline, landed, eligible)

def resolve_zero_gate(+box: G.AABB, grounded: Bool, maximum: F32, +requested: Vec3,
                      initial_colliders: List<&2, G.Collider>, step_colliders: List<&2, G.Collider>, stationary: Bool) -> Resolution:
  match stationary:
    case True{}: Resolution{requested, False{}}
    case False{}: resolve_baseline(box, grounded, maximum, requested, step_colliders, collide_with_shapes(requested, box, initial_colliders))

# Lists represent exact ordered results from the two collider queries. They
# may be identical for a declared finite-shape world; no world arrays are owned.
def resolve(+box: G.AABB, grounded: Bool, maximum: F32, +requested: Vec3,
             initial_colliders: List<&2, G.Collider>, step_colliders: List<&2, G.Collider>) -> Resolution:
  resolve_zero_gate(box, grounded, maximum, requested, initial_colliders, step_colliders, F.is_zero(Vec3.length_squared(requested)))

def make_box(position: Vec3, width: F32, height: F32) -> G.AABB:
  Vec3{+x, +y, +z} = position
  +half = cast_float(F.div(F.from_f32(width), F.from_u32(2)))
  G.AABB.new(F.sub(x, half), y, F.sub(z, half), F.add(x, half), F.add(y, F.from_f32(height)), F.add(z, half))

def Body.new(+position: Vec3, +width: F32, +height: F32, velocity: Vec3, grounded: Bool) -> Body:
  Body{position, make_box(position, width, height), velocity, width, height, grounded, False{}, False{}, False{}}

def equal_movement(a: F.F64, b: F.F64) -> Bool:
  F.is_lt(F.abs(F.sub(b, a)), F.F64{1055193269, 2147483648})

# Supported restitution context: locally authoritative, can-simulate entity,
# suppressed bounce (zero restitution) and block speed factor exactly 1.0f.
def stop_horizontal(value: F.F64, blocked: Bool) -> F.F64:
  match blocked:
    case False{}: value
    case True{}: F.mul(F.neg(value), zero())

def stop_vertical(value: F.F64, blocked: Bool) -> F.F64:
  match blocked:
    case False{}: value
    case True{}: F.mul(F.mul(F.sub(zero(), value), one()), zero())

def restitution(velocity: Vec3, x_blocked: Bool, z_blocked: Bool, vertical: Bool, active: Bool) -> Vec3:
  match velocity active:
    case Vec3{x, y, z} False{}: Vec3{F.mul(x, one()), y, F.mul(z, one())}
    case Vec3{x, y, z} True{}:
      Vec3{F.mul(stop_horizontal(x, x_blocked), one()), stop_vertical(y, vertical), F.mul(stop_horizontal(z, z_blocked), one())}

def Vec3.numerically_equal(a: Vec3, b: Vec3) -> Bool:
  match a b:
    case Vec3{ax, ay, az} Vec3{bx, by, bz}: F.is_eq(ax, bx) && F.is_eq(ay, by) && F.is_eq(az, bz)

def retain_position(current: Vec3, proposed: Vec3, equal: Bool) -> Vec3:
  match equal:
    case True{}: current
    case False{}: proposed

def advance_gate(+position: Vec3, box: G.AABB, +width: F32, +height: F32, displacement: Vec3, changed: Bool) -> Vec3 & G.AABB:
  match changed:
    case False{}: (position, box)
    case True{}:
      +proposed = Vec3.add(position, displacement)
      +next = retain_position(position, proposed, Vec3.numerically_equal(position, proposed))
      (next, make_box(next, width, height))

def finish_transition(advanced: Vec3 & G.AABB, velocity: Vec3, width: F32, height: F32,
                      +below: Bool, horizontal: Bool, vertical: Bool, displacement: Vec3, stepped: Bool, changed: Bool) -> Transition:
  match advanced:
    case (position, box): Transition{Body{position, box, velocity, width, height, below, horizontal, vertical, below}, displacement, stepped, changed}

def apply_resolution(body: Body, requested: Vec3, result: Resolution) -> Transition:
  match body requested result:
    case Body{position, box, velocity, +width, +height, old_grounded, old_horizontal, old_vertical, old_below} Vec3{+x, +y, +z} Resolution{+displacement, stepped}:
      Vec3{cx, cy, cz} = displacement
      +x_blocked = Bool.not(equal_movement(x, cx))
      +z_blocked = Bool.not(equal_movement(z, cz))
      +horizontal = x_blocked || z_blocked
      +vertical = F.is_ne(y, cy)
      +below = vertical && F.is_lt(y, zero())
      +requested_y = F.is_gt(F.abs(y), zero())
      +d2 = Vec3.length_squared(displacement)
      +changed = F.is_gt(d2, G.epsilon()) || F.is_lt(F.sub(Vec3.length_squared(Vec3{x, y, z}), d2), G.epsilon())
      advanced = advance_gate(position, box, width, height, displacement, changed)
      next_velocity = restitution(velocity, x_blocked, z_blocked, vertical, (requested_y && vertical) || horizontal)
      finish_transition(advanced, next_velocity, width, height, below, horizontal, vertical, displacement, stepped, changed)

def move(+body: Body, +requested: Vec3, maximum: F32,
          initial_colliders: List<&2, G.Collider>, step_colliders: List<&2, G.Collider>) -> Transition:
  Body{position, box, velocity, width, height, grounded, horizontal, vertical, below} = body
  apply_resolution(body, requested, resolve(box, grounded, maximum, requested, initial_colliders, step_colliders))

def Vec3.invalid_field(vector: Vec3) -> Maybe<&2, U32>:
  match vector:
    case Vec3{x, y, z}: G.first_nonfinite(x <> y <> z <> Nil{}, 0)

def body_error_field(component: U32, invalid: Maybe<&2, U32>, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match invalid:
    case None{}: rest
    case Some{field}: Some{InvalidBody{component, field}}

def dimension_error_gate(width_ok: Bool, height_ok: Bool) -> Maybe<&2, Error>:
  match width_ok height_ok:
    case False{} _: Some{InvalidDimensions{0}}
    case True{} False{}: Some{InvalidDimensions{1}}
    case True{} True{}: None{}

def dimension_error(width: F32, height: F32) -> Maybe<&2, Error>:
  +w = F.from_f32(width)
  +h = F.from_f32(height)
  dimension_error_gate(F.is_finite(w) && F.is_ge(w, zero()), F.is_finite(h) && F.is_ge(h, zero()))

def Body.invalid(body: Body) -> Maybe<&2, Error>:
  match body:
    case Body{position, box, velocity, width, height, grounded, horizontal, vertical, below}:
      body_error_field(0, Vec3.invalid_field(position), body_error_field(1, G.AABB.invalid_field(box), body_error_field(2, Vec3.invalid_field(velocity), dimension_error(width, height))))

def bounds_error_gate(phase: U32, index: U32, x: Bool, y: Bool, z: Bool) -> Maybe<&2, Error>:
  match x y z:
    case False{} _ _: Some{ReversedCollider{phase, index, 0}}
    case True{} False{} _: Some{ReversedCollider{phase, index, 1}}
    case True{} True{} False{}: Some{ReversedCollider{phase, index, 2}}
    case True{} True{} True{}: None{}

def bounds_error(phase: U32, index: U32, box: G.AABB) -> Maybe<&2, Error>:
  match box:
    case G.AABB{a, b, c, d, e, f}: bounds_error_gate(phase, index, F.is_le(a, d), F.is_le(b, e), F.is_le(c, f))

def collider_error_field(phase: U32, index: U32, invalid: Maybe<&2, U32>, bounds: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match invalid:
    case None{}: bounds
    case Some{field}: Some{InvalidCollider{phase, index, field}}

def collider_error(+phase: U32, +index: U32, collider: G.Collider) -> Maybe<&2, Error>:
  match collider:
    case G.EmptyCollider{}: None{}
    case G.BoxCollider{+box}: collider_error_field(phase, index, G.AABB.invalid_field(box), bounds_error(phase, index, box))

def first_error(first: Maybe<&2, Error>, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match first:
    case None{}: rest
    case Some{value}: Some{value}

def colliders_error(colliders: List<&2, G.Collider>, +phase: U32, +index: U32) -> Maybe<&2, Error>:
  match colliders:
    case Nil{}: None{}
    case shape <> rest: first_error(collider_error(phase, index, shape), colliders_error(rest, phase, U32.inc(index)))

def request_error(invalid: Maybe<&2, U32>) -> Maybe<&2, Error>:
  match invalid:
    case None{}: None{}
    case Some{axis}: Some{InvalidRequest{axis}}

def maximum_error(ok: Bool) -> Maybe<&2, Error>:
  match ok:
    case True{}: None{}
    case False{}: Some{InvalidStepHeight{}}

def result_error_field(component: U32, invalid: Maybe<&2, U32>, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match invalid:
    case None{}: rest
    case Some{field}: Some{NonFiniteResult{component, field}}

def transition_invalid(value: Transition) -> Maybe<&2, Error>:
  match value:
    case Transition{Body{position, box, velocity, width, height, grounded, horizontal, vertical, below}, displacement, stepped, changed}:
      result_error_field(0, Vec3.invalid_field(position), result_error_field(1, G.AABB.invalid_field(box), result_error_field(2, Vec3.invalid_field(velocity), result_error_field(3, Vec3.invalid_field(displacement), None{}))))

def checked_result(value: Transition, invalid: Maybe<&2, Error>) -> Result<&2, &2, Error, Transition>:
  match invalid:
    case None{}: Done{value}
    case Some{error}: Fail{error}

def move_checked_gate(body: Body, requested: Vec3, maximum: F32, initial: List<&2, G.Collider>, step: List<&2, G.Collider>, invalid: Maybe<&2, Error>) -> Result<&2, &2, Error, Transition>:
  match invalid:
    case Some{error}: Fail{error}
    case None{}:
      +result = move(body, requested, maximum, initial, step)
      checked_result(result, transition_invalid(result))

# Rejection is a simulation policy. Java's raw methods accept nonfinite input.
def move_checked(+body: Body, +requested: Vec3, +maximum: F32, +initial: List<&2, G.Collider>, +step: List<&2, G.Collider>) -> Result<&2, &2, Error, Transition>:
  +m = F.from_f32(maximum)
  invalid = first_error(Body.invalid(body), first_error(request_error(Vec3.invalid_field(requested)), first_error(maximum_error(F.is_finite(m) && F.is_ge(m, zero())), first_error(colliders_error(initial, 0, 0), colliders_error(step, 1, 0)))))
  move_checked_gate(body, requested, maximum, initial, step, invalid)

def stuck_threshold() -> F.F64:
  F.F64{1048238066, 2596056904}

def Vec3.multiply(a: Vec3, b: Vec3) -> Vec3:
  match a b:
    case Vec3{ax, ay, az} Vec3{bx, by, bz}:
      Vec3{F.mul(ax, bx), F.mul(ay, by), F.mul(az, bz)}

def stuck_gate(body: Body, requested: Vec3, multiplier: Vec3, active: Bool) -> StuckPreparation:
  match body active:
    case body False{}: StuckPreparation{body, requested, multiplier, False{}}
    case Body{position, box, velocity, width, height, ground, horizontal, vertical, below} True{}:
      StuckPreparation{Body{position, box, Vec3.zero(), width, height, ground, horizontal, vertical, below},
        Vec3.multiply(requested, multiplier), Vec3.zero(), True{}}

# SELF/PLAYER movers multiply their request. Piston/noPhysics have different
# earlier branches and are deliberately outside this entry's contract.
def stuck(+body: Body, +requested: Vec3, +multiplier: Vec3) -> StuckPreparation:
  stuck_gate(body, requested, multiplier, F.is_gt(Vec3.length_squared(multiplier), stuck_threshold()))

def stuck_invalid(value: StuckPreparation) -> Maybe<&2, Error>:
  StuckPreparation{body, requested, multiplier, applied} = value
  first_error(Body.invalid(body), result_error_field(3, Vec3.invalid_field(requested), None{}))

def stuck_result(value: StuckPreparation, invalid: Maybe<&2, Error>) -> Result<&2, &2, Error, StuckPreparation>:
  match invalid:
    case Some{cause}: Fail{cause}
    case None{}: Done{value}

def stuck_checked_gate(body: Body, requested: Vec3, multiplier: Vec3,
                      invalid: Maybe<&2, Error>) -> Result<&2, &2, Error, StuckPreparation>:
  match invalid:
    case Some{cause}: Fail{cause}
    case None{}:
      +value = stuck(body, requested, multiplier)
      stuck_result(value, stuck_invalid(value))

# InvalidBody component 3 names the observed multiplier. Finite multiplication
# overflow names NonFiniteResult component 3, the scaled displacement request.
def stuck_checked(+body: Body, +requested: Vec3, +multiplier: Vec3) -> Result<&2, &2, Error, StuckPreparation>:
  stuck_checked_gate(body, requested, multiplier,
    first_error(Body.invalid(body), first_error(request_error(Vec3.invalid_field(requested)),
      body_error_field(3, Vec3.invalid_field(multiplier), None{}))))

law empty_colliders_preserve_requested:
  for +requested: Vec3
  for box: G.AABB
  {collide_with_shapes(requested, box, Nil{}) == requested : Vec3}

def empty_colliders_preserve_requested(requested, box):
  {==}

law zero_axis_skips_colliders:
  for box: G.AABB
  for colliders: List<&2, G.Collider>
  for +accumulated: Vec3
  for axis: G.Axis
  for delta: F.F64
  {collide_axis_gate(box, colliders, accumulated, axis, delta, True{}) == accumulated : Vec3}

def zero_axis_skips_colliders(box, colliders, accumulated, axis, delta):
  {==}

law no_candidates_preserves_baseline:
  for requested: Vec3
  for original: G.AABB
  for adjusted: G.AABB
  for colliders: List<&2, G.Collider>
  for +baseline: Vec3
  {try_heights(Nil{}, requested, original, adjusted, colliders, baseline) == Resolution{baseline, False{}} : Resolution}

def no_candidates_preserves_baseline(requested, original, adjusted, colliders, baseline):
  {==}

law stationary_resolve_preserves_payload:
  for box: G.AABB
  for grounded: Bool
  for maximum: F32
  for +requested: Vec3
  for initial: List<&2, G.Collider>
  for step: List<&2, G.Collider>
  {resolve_zero_gate(box, grounded, maximum, requested, initial, step, True{}) == Resolution{requested, False{}} : Resolution}

def stationary_resolve_preserves_payload(box, grounded, maximum, requested, initial, step):
  {==}

law accepted_step_stops_search:
  for heights: List<&2, F.F64>
  for requested: Vec3
  for +original: G.AABB
  for +adjusted: G.AABB
  for colliders: List<&2, G.Collider>
  for baseline: Vec3
  for +pending: Vec3
  {try_heights_go(heights, requested, original, adjusted, colliders, baseline, pending, True{}) == step_result(pending, F.sub(min_y(original), min_y(adjusted))) : Resolution}

def accepted_step_stops_search(heights, requested, original, adjusted, colliders, baseline, pending):
  match heights:
    case Nil{}: {==}
    case value <> rest: {==}

law checked_error_rejects_before_move:
  for body: Body
  for requested: Vec3
  for maximum: F32
  for initial: List<&2, G.Collider>
  for step: List<&2, G.Collider>
  for +error: Error
  {move_checked_gate(body, requested, maximum, initial, step, Some{error}) == Fail{error} : Result<&2, &2, Error, Transition>}

def checked_error_rejects_before_move(body, requested, maximum, initial, step, error):
  {==}

law nonempty_zero_axes_produce_positive_zero:
  for box: G.AABB
  for collider: G.Collider
  for rest: List<&2, G.Collider>
  {collide_with_shapes(Vec3{F.F64{2147483648, 0}, F.F64{0, 0}, F.F64{2147483648, 0}}, box, collider <> rest) == Vec3.zero() : Vec3}

def nonempty_zero_axes_produce_positive_zero(box, collider, rest):
  {==}

law stationary_signed_zero_preserves_payload:
  for box: G.AABB
  for grounded: Bool
  for maximum: F32
  for initial: List<&2, G.Collider>
  for step: List<&2, G.Collider>
  {resolve(box, grounded, maximum, Vec3{F.F64{2147483648, 0}, F.F64{2147483648, 0}, F.F64{2147483648, 0}}, initial, step) == Resolution{Vec3{F.F64{2147483648, 0}, F.F64{2147483648, 0}, F.F64{2147483648, 0}}, False{}} : Resolution}

def stationary_signed_zero_preserves_payload(box, grounded, maximum, initial, step):
  {==}

law numerically_equal_proposal_retains_current_payload:
  for +current: Vec3
  for proposed: Vec3
  {retain_position(current, proposed, True{}) == current : Vec3}

def numerically_equal_proposal_retains_current_payload(current, proposed):
  {==}
