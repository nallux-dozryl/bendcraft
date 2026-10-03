import Base
import ./f64.bend as F

# Immutable, normalized Java AABB endpoints. No array or world owner is copied.
type AABB is Data:
  AABB{min_x: F.F64, min_y: F.F64, min_z: F.F64, max_x: F.F64, max_y: F.F64, max_z: F.F64}

type Axis is Data:
  AxisX{}
  AxisY{}
  AxisZ{}

type Collider is Data:
  EmptyCollider{}
  BoxCollider{box: AABB}

type Error is Data:
  NonFiniteCoordinate{field: U32}
  NonFiniteMoving{field: U32}
  NonFiniteObstacle{index: U32, field: U32}
  NonFiniteDelta{}

def zero() -> F.F64:
  F.F64{0, 0}

# The exact binary64 encoding of the Java collision literal 1.0E-7.
def epsilon() -> F.F64:
  F.F64{1048238066, 2596056904}

def math_min_zero(a: F.F64, b: F.F64, negative_a: Bool) -> F.F64:
  match negative_a:
    case True{}: a
    case False{}: b

def math_max_zero(a: F.F64, b: F.F64, negative_a: Bool) -> F.F64:
  match negative_a:
    case True{}: b
    case False{}: a

def select_value(a: F.F64, b: F.F64, choose_a: Bool) -> F.F64:
  match choose_a:
    case True{}: a
    case False{}: b

def math_min_ordered(+a: F.F64, +b: F.F64, both_zero: Bool) -> F.F64:
  match both_zero:
    case True{}: math_min_zero(a, b, F.sign(a))
    case False{}: select_value(a, b, F.is_le(a, b))

def math_max_ordered(+a: F.F64, +b: F.F64, both_zero: Bool) -> F.F64:
  match both_zero:
    case True{}: math_max_zero(a, b, F.sign(a))
    case False{}: select_value(a, b, F.is_ge(a, b))

# Math.min/max preserve the selected NaN input; arithmetic NaN payload policy
# remains that of F64. The Java oracle below establishes finite behavior only.
def math_min_classes(+a: F.F64, +b: F.F64, a_nan: Bool, b_nan: Bool) -> F.F64:
  match a_nan b_nan:
    case True{} _: a
    case False{} True{}: b
    case False{} False{}: math_min_ordered(a, b, F.is_zero(a) && F.is_zero(b))

def math_max_classes(+a: F.F64, +b: F.F64, a_nan: Bool, b_nan: Bool) -> F.F64:
  match a_nan b_nan:
    case True{} _: a
    case False{} True{}: b
    case False{} False{}: math_max_ordered(a, b, F.is_zero(a) && F.is_zero(b))

def math_min(+a: F.F64, +b: F.F64) -> F.F64:
  math_min_classes(a, b, F.is_nan(a), F.is_nan(b))

def math_max(+a: F.F64, +b: F.F64) -> F.F64:
  math_max_classes(a, b, F.is_nan(a), F.is_nan(b))

def AABB.new(+x1: F.F64, +y1: F.F64, +z1: F.F64, +x2: F.F64, +y2: F.F64, +z2: F.F64) -> AABB:
  AABB{math_min(x1, x2), math_min(y1, y2), math_min(z1, z2), math_max(x1, x2), math_max(y1, y2), math_max(z1, z2)}

def AABB.move(box: AABB, +x: F.F64, +y: F.F64, +z: F.F64) -> AABB:
  match box:
    case AABB{a, b, c, d, e, f}:
      AABB.new(F.add(a, x), F.add(b, y), F.add(c, z), F.add(d, x), F.add(e, y), F.add(f, z))

def AABB.inflate(box: AABB, +x: F.F64, +y: F.F64, +z: F.F64) -> AABB:
  match box:
    case AABB{a, b, c, d, e, f}:
      AABB.new(F.sub(a, x), F.sub(b, y), F.sub(c, z), F.add(d, x), F.add(e, y), F.add(f, z))

def AABB.deflate(box: AABB, x: F.F64, y: F.F64, z: F.F64) -> AABB:
  AABB.inflate(box, F.neg(x), F.neg(y), F.neg(z))

def AABB.intersects(a: AABB, b: AABB) -> Bool:
  match a b:
    case AABB{ax, ay, az, aw, ah, ad} AABB{bx, by, bz, bw, bh, bd}:
      F.is_lt(ax, bw) && F.is_gt(aw, bx) && F.is_lt(ay, bh) && F.is_gt(ah, by) && F.is_lt(az, bd) && F.is_gt(ad, bz)

def AABB.contains(box: AABB, +x: F.F64, +y: F.F64, +z: F.F64) -> Bool:
  match box:
    case AABB{a, b, c, d, e, f}:
      F.is_ge(x, a) && F.is_lt(x, d) && F.is_ge(y, b) && F.is_lt(y, e) && F.is_ge(z, c) && F.is_lt(z, f)

def AABB.axis(box: AABB, axis: Axis) -> F.F64 & F.F64:
  match box axis:
    case AABB{a, b, c, d, e, f} AxisX{}: (a, d)
    case AABB{a, b, c, d, e, f} AxisY{}: (b, e)
    case AABB{a, b, c, d, e, f} AxisZ{}: (c, f)

def next_axis(axis: Axis) -> Axis:
  match axis:
    case AxisX{}: AxisY{}
    case AxisY{}: AxisZ{}
    case AxisZ{}: AxisX{}

def previous_axis(axis: Axis) -> Axis:
  match axis:
    case AxisX{}: AxisZ{}
    case AxisY{}: AxisX{}
    case AxisZ{}: AxisY{}

# One occupied ArrayVoxelShape cell: findIndex(v) is the first coordinate > v,
# minus one. Keep the rounded epsilon shifts rather than rearranging equations.
def cell_overlap(moving: F.F64 & F.F64, obstacle: F.F64 & F.F64) -> Bool:
  (low, high) = moving
  (start, end) = obstacle
  F.is_lt(F.add(low, epsilon()), end) && F.is_ge(F.sub(high, epsilon()), start)

def transverse_overlap(+axis: Axis, +moving: AABB, +obstacle: AABB) -> Bool:
  cell_overlap(AABB.axis(moving, next_axis(axis)), AABB.axis(obstacle, next_axis(axis))) && cell_overlap(AABB.axis(moving, previous_axis(axis)), AABB.axis(obstacle, previous_axis(axis)))

def positive_gap(+delta: F.F64, +gap: F.F64, eligible: Bool) -> F.F64:
  match eligible:
    case True{}: math_min(delta, gap)
    case False{}: delta

def negative_gap(+delta: F.F64, +gap: F.F64, eligible: Bool) -> F.F64:
  match eligible:
    case True{}: math_max(delta, gap)
    case False{}: delta

def positive_clip(+moving_max: F.F64, +obstacle_min: F.F64, delta: F.F64, candidate: Bool) -> F.F64:
  match candidate:
    case False{}: delta
    case True{}:
      +gap = F.sub(obstacle_min, moving_max)
      positive_gap(delta, gap, F.is_ge(gap, F.neg(epsilon())))

def negative_clip(+moving_min: F.F64, +obstacle_max: F.F64, delta: F.F64, candidate: Bool) -> F.F64:
  match candidate:
    case False{}: delta
    case True{}:
      +gap = F.sub(obstacle_max, moving_min)
      negative_gap(delta, gap, F.is_le(gap, epsilon()))

def clip_direction(moving: F.F64 & F.F64, obstacle: F.F64 & F.F64, +delta: F.F64, positive: Bool, negative: Bool) -> F.F64:
  (+low, +high) = moving
  (+start, +end) = obstacle
  match positive negative:
    case True{} _: positive_clip(high, start, delta, F.is_lt(F.sub(high, epsilon()), start))
    case False{} True{}: negative_clip(low, end, delta, F.is_ge(F.add(low, epsilon()), end))
    case False{} False{}: delta

def clip_overlap(+axis: Axis, moving: AABB, obstacle: AABB, +delta: F.F64, overlap: Bool) -> F.F64:
  match overlap:
    case False{}: delta
    case True{}: clip_direction(AABB.axis(moving, axis), AABB.axis(obstacle, axis), delta, F.is_gt(delta, zero()), F.is_lt(delta, zero()))

def clip_box_gate(+axis: Axis, +moving: AABB, +obstacle: AABB, delta: F.F64, tiny: Bool) -> F.F64:
  match tiny:
    case True{}: zero()
    case False{}: clip_overlap(axis, moving, obstacle, delta, transverse_overlap(axis, moving, obstacle))

# The obstacle denotes an occupied cell, not Shapes.box construction. In
# particular, this function does not snap coordinates or infer an empty shape.
def clip_box(axis: Axis, moving: AABB, obstacle: AABB, +delta: F.F64) -> F.F64:
  clip_box_gate(axis, moving, obstacle, delta, F.is_lt(F.abs(delta), epsilon()))

# Java Shapes.collide checks tiny delta before each iterable element. An empty
# list therefore preserves even negative zero; a nonempty list may return +0.
def clip_go(+axis: Axis, +moving: AABB, obstacles: List<&2, AABB>, delta: F.F64, tiny: Bool) -> F.F64:
  match obstacles tiny:
    case Nil{} _: delta
    case Con{box, rest} True{}: zero()
    case Con{box, rest} False{}:
      +next = clip_box(axis, moving, box, delta)
      clip_go(axis, moving, rest, next, F.is_lt(F.abs(next), epsilon()))

def clip(axis: Axis, moving: AABB, obstacles: List<&2, AABB>, +delta: F.F64) -> F.F64:
  clip_go(axis, moving, obstacles, delta, F.is_lt(F.abs(delta), epsilon()))

def clip_collider(axis: Axis, moving: AABB, collider: Collider, delta: F.F64) -> F.F64:
  match collider:
    case EmptyCollider{}: delta
    case BoxCollider{box}: clip_box(axis, moving, box, delta)

def clip_colliders_go(+axis: Axis, +moving: AABB, colliders: List<&2, Collider>, delta: F.F64, tiny: Bool) -> F.F64:
  match colliders tiny:
    case Nil{} _: delta
    case Con{shape, rest} True{}: zero()
    case Con{shape, rest} False{}:
      +next = clip_collider(axis, moving, shape, delta)
      clip_colliders_go(axis, moving, rest, next, F.is_lt(F.abs(next), epsilon()))

def clip_colliders(axis: Axis, moving: AABB, colliders: List<&2, Collider>, +delta: F.F64) -> F.F64:
  clip_colliders_go(axis, moving, colliders, delta, F.is_lt(F.abs(delta), epsilon()))

# Checked entry points are explicit simulation validation, not Java AABB's
# permissive nonfinite policy. The raw API above remains available separately.
def first_nonfinite_gate(rest: Maybe<&2, U32>, index: U32, finite: Bool) -> Maybe<&2, U32>:
  match finite:
    case False{}: Some{index}
    case True{}: rest

def first_nonfinite(values: List<&2, F.F64>, +index: U32) -> Maybe<&2, U32>:
  match values:
    case Nil{}: None{}
    case Con{value, rest}: first_nonfinite_gate(first_nonfinite(rest, U32.inc(index)), index, F.is_finite(value))

def AABB.invalid_field(box: AABB) -> Maybe<&2, U32>:
  match box:
    case AABB{a, b, c, d, e, f}: first_nonfinite(a <> b <> c <> d <> e <> f <> Nil{}, 0)

def checked_new_gate(a: F.F64, b: F.F64, c: F.F64, d: F.F64, e: F.F64, f: F.F64, invalid: Maybe<&2, U32>) -> Result<&2, &2, Error, AABB>:
  match invalid:
    case None{}: Done{AABB.new(a, b, c, d, e, f)}
    case Some{field}: Fail{NonFiniteCoordinate{field}}

def AABB.checked_new(+a: F.F64, +b: F.F64, +c: F.F64, +d: F.F64, +e: F.F64, +f: F.F64) -> Result<&2, &2, Error, AABB>:
  checked_new_gate(a, b, c, d, e, f, first_nonfinite(a <> b <> c <> d <> e <> f <> Nil{}, 0))

def check_obstacles_field(rest: Maybe<&2, Error>, index: U32, field: Maybe<&2, U32>) -> Maybe<&2, Error>:
  match field:
    case Some{value}: Some{NonFiniteObstacle{index, value}}
    case None{}: rest

def check_obstacles(boxes: List<&2, AABB>, +index: U32) -> Maybe<&2, Error>:
  match boxes:
    case Nil{}: None{}
    case Con{box, rest}: check_obstacles_field(check_obstacles(rest, U32.inc(index)), index, AABB.invalid_field(box))

def clip_checked_obstacles(axis: Axis, moving: AABB, obstacles: List<&2, AABB>, delta: F.F64, error: Maybe<&2, Error>) -> Result<&2, &2, Error, F.F64>:
  match error:
    case Some{value}: Fail{value}
    case None{}: Done{clip(axis, moving, obstacles, delta)}

def clip_checked_delta(axis: Axis, moving: AABB, +obstacles: List<&2, AABB>, delta: F.F64, finite: Bool) -> Result<&2, &2, Error, F.F64>:
  match finite:
    case False{}: Fail{NonFiniteDelta{}}
    case True{}: clip_checked_obstacles(axis, moving, obstacles, delta, check_obstacles(obstacles, 0))

def clip_checked_moving(axis: Axis, moving: AABB, obstacles: List<&2, AABB>, +delta: F.F64, invalid: Maybe<&2, U32>) -> Result<&2, &2, Error, F.F64>:
  match invalid:
    case Some{field}: Fail{NonFiniteMoving{field}}
    case None{}: clip_checked_delta(axis, moving, obstacles, delta, F.is_finite(delta))

def clip_checked(axis: Axis, +moving: AABB, obstacles: List<&2, AABB>, delta: F.F64) -> Result<&2, &2, Error, F.F64>:
  clip_checked_moving(axis, moving, obstacles, delta, AABB.invalid_field(moving))

# These are implementation laws. Java parity is separately fixture-backed.
law empty_clip_preserves_payload:
  for axis: Axis
  for moving: AABB
  for +delta: F.F64
  {clip(axis, moving, Nil{}, delta) == delta : F.F64}

def empty_clip_preserves_payload(axis, moving, delta):
  {==}

law empty_collider_preserves_payload:
  for axis: Axis
  for moving: AABB
  for +delta: F.F64
  {clip_collider(axis, moving, EmptyCollider{}, delta) == delta : F.F64}

def empty_collider_preserves_payload(axis, moving, delta):
  {==}

law nonempty_iterable_tiny_returns_positive_zero:
  for axis: Axis
  for moving: AABB
  for collider: Collider
  for rest: List<&2, Collider>
  for +delta: F.F64
  for tiny: {F.is_lt(F.abs(delta), epsilon()) == True{} : Bool}
  {clip_colliders(axis, moving, collider <> rest, delta) == F.F64{0, 0} : F.F64}

def nonempty_iterable_tiny_returns_positive_zero(axis, moving, collider, rest, delta, tiny):
  %Equal.sym(Bool, F.is_lt(F.abs(delta), epsilon()), True{}, tiny) : {clip_colliders_go(axis, moving, collider <> rest, delta, _) == F.F64{0, 0} : F.F64}
  {==}

law tiny_clip_returns_positive_zero:
  for axis: Axis
  for moving: AABB
  for obstacle: AABB
  for +delta: F.F64
  for tiny: {F.is_lt(F.abs(delta), epsilon()) == True{} : Bool}
  {clip_box(axis, moving, obstacle, delta) == F.F64{0, 0} : F.F64}

def tiny_clip_returns_positive_zero(axis, moving, obstacle, delta, tiny):
  %Equal.sym(Bool, F.is_lt(F.abs(delta), epsilon()), True{}, tiny) : {clip_box_gate(axis, moving, obstacle, delta, _) == F.F64{0, 0} : F.F64}
  {==}

law disjoint_transverse_preserves_delta:
  for +axis: Axis
  for +moving: AABB
  for +obstacle: AABB
  for +delta: F.F64
  for large: {F.is_lt(F.abs(delta), epsilon()) == False{} : Bool}
  for disjoint: {transverse_overlap(axis, moving, obstacle) == False{} : Bool}
  {clip_box(axis, moving, obstacle, delta) == delta : F.F64}

def disjoint_transverse_preserves_delta(axis, moving, obstacle, delta, large, disjoint):
  %Equal.sym(Bool, F.is_lt(F.abs(delta), epsilon()), False{}, large) : {clip_box_gate(axis, moving, obstacle, delta, _) == delta : F.F64}
  %Equal.sym(Bool, transverse_overlap(axis, moving, obstacle), False{}, disjoint) : {clip_overlap(axis, moving, obstacle, delta, _) == delta : F.F64}
  {==}

law signed_zero_constructor:
  {AABB.new(F.F64{0, 0}, F.F64{2147483648, 0}, F.F64{0, 0}, F.F64{2147483648, 0}, F.F64{0, 0}, F.F64{0, 0}) == AABB{F.F64{2147483648, 0}, F.F64{2147483648, 0}, F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}} : AABB}

def signed_zero_constructor():
  {==}

law checked_nonfinite_first_coordinate:
  for b: F.F64
  for c: F.F64
  for d: F.F64
  for e: F.F64
  for f: F.F64
  {AABB.checked_new(F.F64{2146435072, 0}, b, c, d, e, f) == Fail{NonFiniteCoordinate{0}} : Result<&2, &2, Error, AABB>}

def checked_nonfinite_first_coordinate(b, c, d, e, f):
  {==}
