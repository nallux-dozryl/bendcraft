import Base
import ./f64.bend as F
import ./geometry.bend as A
import ./movement.bend as M
import ./player_block_inside_stuck.bend as P
import ./player_block_inside_sweep_clip.bend as C

def choose(-T: Data, +yes: T, +no: T, +condition: Bool) -> T:
  match condition:
    case True{}: yes
    case False{}: no

def decide(-T: Type, flag: Bool, yes: Unit -> T, no: Unit -> T) -> T:
  match flag:
    case True{}: yes(Unit{})
    case False{}: no(Unit{})

type Point is Data:
  Point{x: U32, y: U32, z: U32}

# Equality of these masked words is exactly equality of BlockPos.asLong.
type PackedKey is Data:
  PackedKey{x: U32, y: U32, z: U32}

type Step is Data:
  Positive{}
  Negative{}
  StationaryAxis{}

type Signs is Data:
  Signs{x: Step, y: Step, z: Step}

type Order is Data:
  Order{first: A.Axis, second: A.Axis, third: A.Axis}

type Movement is Data:
  Movement{from: M.Vec3, to: M.Vec3, axis_dependent_original: Maybe<&2, M.Vec3>}

type Error is Data:
  InvalidMovement{index: U32, field: U32}
  InvalidDimensions{field: U32}
  InvalidCoordinate{}
  TraversalBudget{}

def error_text(+error: Error) -> String:
  match error:
    case InvalidMovement{index, field}: "invalid-movement:" ++ U32.show(index) ++ ":" ++ U32.show(field)
    case InvalidDimensions{field}: "invalid-dimensions:" ++ U32.show(field)
    case InvalidCoordinate{}: "invalid-coordinate"
    case TraversalBudget{}: "traversal-budget"

type Segment is Data:
  Segment{from: M.Vec3, to: M.Vec3, box: A.AABB, far: Bool,
          tail: List<&2, Segment>}

type Visit is Data:
  Visit{position: Point, step: U32, segment: Segment}

# Failure is deferred until the preceding visits have been read in order by
# the owned world consumer. No speculative receiver is committed on failure.
type Plan is Data:
  Plan{visits: List<&2, Visit>, failure: Maybe<&2, Error>}

# Recursive private state bounds continuation width. All internal tails are Nil.
type Build is Data:
  Build{fuel: Nat, seen: List<&2, PackedKey>, reversed: List<&2, Visit>,
        last_step: U32, stopped: Bool, failure: Maybe<&2, Error>, tail: List<&2, Build>}

type Range is Data:
  Range{current: Point, start: Point, end: Point, order: Order, signs: Signs}

type DDA is Data:
  DDA{cell: Point, times: M.Vec3, intervals: M.Vec3, signs: Signs,
      corner: Signs, start: M.Vec3, end: M.Vec3, sizes: M.Vec3,
      collisions: U32, tail: List<&2, DDA>}

def key(+point: Point) -> PackedKey:
  Point{x, y, z} = point
  PackedKey{U32.and(x, 67108863), U32.and(y, 4095), U32.and(z, 67108863)}

def key_equal(+a: PackedKey, +b: PackedKey) -> Bool:
  match a b:
    case PackedKey{x, y, z} PackedKey{u, v, w}: U32.is_eq(x, u) && U32.is_eq(y, v) && U32.is_eq(z, w)

def seen(+keys: List<&2, PackedKey>, +target: PackedKey) -> Bool:
  match keys:
    case Nil{}: False{}
    case value <> rest: key_equal(value, target) || seen(rest, target)

def added(+keys: List<&2, PackedKey>, +value: PackedKey, +present: Bool) -> List<&2, PackedKey>:
  match present:
    case True{}: keys
    case False{}: value <> keys

def sign_gate(+positive: Bool, +negative: Bool) -> Step:
  match positive negative:
    case True{} _: Positive{}
    case False{} True{}: Negative{}
    case False{} False{}: StationaryAxis{}

def sign(+value: F.F64) -> Step:
  sign_gate(F.is_gt(value, M.zero()), F.is_lt(value, M.zero()))

def direction(+value: F.F64) -> Step:
  choose(Step, Positive{}, Negative{}, F.is_ge(value, M.zero()))

def opposite(+value: Step) -> Step:
  match value:
    case Positive{}: Negative{}
    case Negative{}: Positive{}
    case StationaryAxis{}: StationaryAxis{}

def signed_double(+value: Step) -> F.F64:
  match value:
    case Positive{}: M.one()
    case Negative{}: F.neg(M.one())
    case StationaryAxis{}: M.zero()

def increment(+value: U32, +step: Step) -> U32:
  match step:
    case Positive{}: U32.inc(value)
    case Negative{}: U32.sub(value, 1)
    case StationaryAxis{}: value

def signs(+vector: M.Vec3) -> Signs:
  M.Vec3{x, y, z} = vector
  Signs{sign(x), sign(y), sign(z)}

def directions(+vector: M.Vec3) -> Signs:
  M.Vec3{x, y, z} = vector
  Signs{direction(x), direction(y), direction(z)}

def order_gate(+z_before_x: Bool) -> Order:
  match z_before_x:
    case True{}: Order{A.AxisY{}, A.AxisZ{}, A.AxisX{}}
    case False{}: Order{A.AxisY{}, A.AxisX{}, A.AxisZ{}}

def order(+vector: M.Vec3) -> Order:
  M.Vec3{x, y, z} = vector
  order_gate(F.is_lt(F.abs(x), F.abs(z)))

def point_axis(+point: Point, +axis: A.Axis) -> U32:
  match point axis:
    case Point{x, y, z} A.AxisX{}: x
    case Point{x, y, z} A.AxisY{}: y
    case Point{x, y, z} A.AxisZ{}: z

def point_with(+point: Point, +axis: A.Axis, +value: U32) -> Point:
  match point axis:
    case Point{x, y, z} A.AxisX{}: Point{value, y, z}
    case Point{x, y, z} A.AxisY{}: Point{x, value, z}
    case Point{x, y, z} A.AxisZ{}: Point{x, y, value}

def signs_axis(+value: Signs, +axis: A.Axis) -> Step:
  match value axis:
    case Signs{x, y, z} A.AxisX{}: x
    case Signs{x, y, z} A.AxisY{}: y
    case Signs{x, y, z} A.AxisZ{}: z

def signed_le(+a: U32, +b: U32) -> Bool:
  U32.is_le(U32.xor(a, 2147483648), U32.xor(b, 2147483648))

def range_axis_sign(+low: U32, +high: U32, +sign: Step) -> U32 & U32:
  match sign:
    case Negative{}: (high, low)
    case _: (low, high)

def range_axis(+a: U32, +b: U32, +sign: Step) -> U32 & U32:
  range_axis_sign(choose(U32, a, b, signed_le(a, b)), choose(U32, b, a, signed_le(a, b)), sign)

def negative(+sign: Step) -> Bool:
  match sign:
    case Negative{}: True{}
    case _: False{}

def range_start(+a: U32, +b: U32, +sign: Step) -> U32:
  choose(U32, choose(U32, b, a, signed_le(a, b)), choose(U32, a, b, signed_le(a, b)), negative(sign))

def range_end(+a: U32, +b: U32, +sign: Step) -> U32:
  choose(U32, choose(U32, a, b, signed_le(a, b)), choose(U32, b, a, signed_le(a, b)), negative(sign))

def range(+a: Point, +b: Point, +order: Order, +signs: Signs) -> Range:
  Point{+x, +y, +z} = a
  Point{+u, +v, +w} = b
  Signs{+sx, +sy, +sz} = signs
  +start = {Point{range_start(x, u, sx), range_start(y, v, sy), range_start(z, w, sz)} : Point}
  Range{start, start, Point{range_end(x, u, sx), range_end(y, v, sy), range_end(z, w, sz)}, order, signs}

def range_next_axes(+value: Range, +first_more: Bool, +second_more: Bool, +third_more: Bool) -> Maybe<&2, Range>:
  Range{+current, +start, end, Order{+first, +second, +third}, +signs} = value
  match first_more second_more third_more:
    case _ _ True{}:
      Some{Range{point_with(current, third, increment(point_axis(current, third), signs_axis(signs, third))), start, end, Order{first, second, third}, signs}}
    case _ True{} False{}:
      Some{Range{point_with(point_with(current, third, point_axis(start, third)), second, increment(point_axis(current, second), signs_axis(signs, second))), start, end, Order{first, second, third}, signs}}
    case True{} False{} False{}:
      Some{Range{point_with(point_with(point_with(current, third, point_axis(start, third)), second, point_axis(start, second)), first, increment(point_axis(current, first), signs_axis(signs, first))), start, end, Order{first, second, third}, signs}}
    case False{} False{} False{}: None{}

def range_next(+value: Range) -> Maybe<&2, Range>:
  Range{+current, start, +end, Order{first, second, third}, signs} = value
  range_next_axes(value, U32.is_ne(point_axis(current, first), point_axis(end, first)),
    U32.is_ne(point_axis(current, second), point_axis(end, second)),
    U32.is_ne(point_axis(current, third), point_axis(end, third)))

def coordinate_ready(+x: Result<&2, &2, F.F64ConversionError, U32>,
                     +y: Result<&2, &2, F.F64ConversionError, U32>,
                     +z: Result<&2, &2, F.F64ConversionError, U32>) -> Result<&2, &2, Error, Point>:
  match x y z:
    case Done{x} Done{y} Done{z}: Done{Point{x, y, z}}
    case _ _ _: Fail{InvalidCoordinate{}}

def coordinate(+value: M.Vec3) -> Result<&2, &2, Error, Point>:
  M.Vec3{x, y, z} = value
  coordinate_ready(F.floor_i32(x), F.floor_i32(y), F.floor_i32(z))

def box_range_ready(+delta: M.Vec3, +stationary: Bool,
                    +low: Result<&2, &2, Error, Point>, +high: Result<&2, &2, Error, Point>) -> Result<&2, &2, Error, Range>:
  match stationary low high:
    case True{} Done{low} Done{high}: Done{range(low, high, Order{A.AxisZ{}, A.AxisY{}, A.AxisX{}}, Signs{Positive{}, Positive{}, Positive{}})}
    case False{} Done{low} Done{high}: Done{range(low, high, order(delta), directions(delta))}
    case _ _ _: Fail{InvalidCoordinate{}}

def box_range(+box: A.AABB, +delta: M.Vec3, +stationary: Bool) -> Result<&2, &2, Error, Range>:
  A.AABB{a, b, c, d, e, f} = box
  box_range_ready(delta, stationary, coordinate(M.Vec3{a, b, c}), coordinate(M.Vec3{d, e, f}))

def failed(+build: Build, +error: Error) -> Build:
  Build{fuel, seen, reversed, last, stopped, old, tail} = build
  Build{fuel, seen, reversed, last, stopped, Some{error}, tail}

def broken(+build: Build) -> Bool:
  Build{fuel, seen, reversed, last, stopped, failure, tail} = build
  Bool.not(Maybe.is_none(&2, Error, failure))

def unavailable(+build: Build) -> Bool:
  Build{fuel, seen, reversed, last, stopped, failure, tail} = build
  stopped || Bool.not(Maybe.is_none(&2, Error, failure))

def emit_gate(+build: Build, +point: Point, +step: U32, +segment: Segment,
              +present: Bool, +skipped: Bool, +rejected: Bool) -> Build:
  match build skipped rejected:
    case build True{} _: build
    case Build{fuel, seen, reversed, last, stopped, failure, tail} False{} True{}:
      Build{fuel, seen, reversed, last, True{}, failure, tail}
    case Build{fuel, seen, reversed, last, stopped, failure, tail} False{} False{}:
      Build{fuel, added(seen, key(point), present), Visit{point, step, segment} <> reversed, step, False{}, failure, tail}

def emit(+build: Build, +point: Point, +step: U32, +segment: Segment,
         +limit: U32, +skip_seen: Bool) -> Build:
  Build{fuel, +keys, reversed, last, stopped, failure, tail} = build
  +present = seen(keys, key(point))
  emit_gate(Build{fuel, keys, reversed, last, stopped, failure, tail}, point, step, segment,
    present, skip_seen && present, U32.is_ge(step, limit))

def fuel_set(+build: Build, +fuel: Nat) -> Build:
  Build{old, seen, reversed, last, stopped, failure, tail} = build
  Build{fuel, seen, reversed, last, stopped, failure, tail}

def range_current(value: Range) -> Point:
  Range{current, start, end, order, signs} = value
  current

def range_loop(fuel: Nat, value: Maybe<&2, Range>, +segment: Segment, +step: U32,
               +limit: U32, +skip_seen: Bool, +build: Build) -> Build:
  match fuel value:
    case _ None{}: build
    case 0n Some{value}:
      decide(Build, unavailable(build), _ => build, _ => failed(build, TraversalBudget{}))
    case 1n+ +p Some{+value}:
      decide(Build, unavailable(build), _ => build,
        _ => range_loop(p, range_next(value), segment, step, limit, skip_seen,
          emit(fuel_set(build, p), range_current(value), step, segment, limit, skip_seen)))

def get_fuel(+build: Build) -> Nat:
  Build{value, seen, reversed, last, stopped, failure, tail} = build
  value

def enumerated(+build: Build, +segment: Segment, +step: U32, +limit: U32, +skip_seen: Bool,
               +value: Result<&2, &2, Error, Range>) -> Build:
  match value:
    case Fail{error}: failed(build, error)
    case Done{range}: range_loop(get_fuel(build), Some{range}, segment, step, limit, skip_seen, build)

def tiny_square() -> F.F64:
  F.F64{1037794527, 3221225472}

def far_threshold() -> F.F64:
  F.F64{1072693227, 122322944}

def furthest_gate(+signs: Signs, +x_least: Bool, +y_before_z: Bool) -> Signs:
  match signs x_least y_before_z:
    case Signs{x, y, z} True{} _: Signs{opposite(x), opposite(z), y}
    case Signs{x, y, z} False{} True{}: Signs{z, opposite(y), opposite(x)}
    case Signs{x, y, z} False{} False{}: Signs{opposite(y), x, opposite(z)}

def furthest(+delta: M.Vec3) -> Signs:
  M.Vec3{+x, +y, +z} = delta
  +a = F.abs(x)
  +b = F.abs(y)
  +c = F.abs(z)
  furthest_gate(directions(delta), F.is_le(a, b) && F.is_le(a, c), F.is_le(b, c))

def corner_vectors(+center: M.Vec3, +sizes: M.Vec3, +corner: Signs) -> M.Vec3:
  match center sizes corner:
    case M.Vec3{cx, cy, cz} M.Vec3{sx, sy, sz} Signs{x, y, z}:
      M.Vec3{F.add(cx, F.mul(F.mul(sx, C.half()), signed_double(x))),
        F.add(cy, F.mul(F.mul(sy, C.half()), signed_double(y))),
        F.add(cz, F.mul(F.mul(sz, C.half()), signed_double(z)))}

def corner_position(+box: A.AABB, +corner: Signs) -> M.Vec3:
  corner_vectors(C.center(box), C.sizes(box), corner)

def interval(+component: F.F64, +sign: Step) -> F.F64:
  match sign:
    case StationaryAxis{}: F.F64{2146435071, 4294967295}
    case value: F.div(signed_double(value), component)

def crossing_time_sign(+fraction: F.F64, +interval: F.F64, +sign: Step) -> F.F64:
  match sign:
    case Positive{}: F.mul(interval, F.sub(M.one(), fraction))
    case _: F.mul(interval, fraction)

def crossing_time(+value: F.F64, +floor: U32, +interval: F.F64, +sign: Step) -> F.F64:
  crossing_time_sign(F.sub(value, F.from_i32(floor)), interval, sign)

def dda_point_signs(+box: A.AABB, +delta: M.Vec3, +corner: Signs,
                    +start: M.Vec3, +end: M.Vec3, +point: Point, +signed: Signs) -> Result<&2, &2, Error, DDA>:
  M.Vec3{dx, dy, dz} = delta
  M.Vec3{x, y, z} = start
  Point{px, py, pz} = point
  Signs{+sx, +sy, +sz} = signed
  +ix = interval(dx, sx)
  +iy = interval(dy, sy)
  +iz = interval(dz, sz)
  Done{DDA{point, M.Vec3{crossing_time(x, px, ix, sx), crossing_time(y, py, iy, sy), crossing_time(z, pz, iz, sz)},
    M.Vec3{ix, iy, iz}, Signs{sx, sy, sz}, corner, start, end, C.sizes(box), 0, []}}

def dda_prepared(+box: A.AABB, +delta: M.Vec3, +corner: Signs,
                 +start: M.Vec3, +end: M.Vec3, +position: Result<&2, &2, Error, Point>) -> Result<&2, &2, Error, DDA>:
  match position:
    case Fail{error}: Fail{error}
    case Done{point}: dda_point_signs(box, delta, corner, start, end, point, signs(delta))

def dda_new(+box: A.AABB, +delta: M.Vec3) -> Result<&2, &2, Error, DDA>:
  +corner = furthest(delta)
  +end = corner_position(box, corner)
  +start = C.subtract(end, delta)
  dda_prepared(box, delta, corner, start, end, coordinate(start))

def dda_axis(+x_before_y: Bool, +x_before_z: Bool, +y_before_z: Bool) -> A.Axis:
  match x_before_y x_before_z y_before_z:
    case True{} True{} _: A.AxisX{}
    case True{} False{} _: A.AxisZ{}
    case False{} _ True{}: A.AxisY{}
    case False{} _ False{}: A.AxisZ{}

def dda_advance(+value: DDA) -> DDA:
  DDA{+cell, +times, intervals, +signs, corner, start, end, sizes, collisions, tail} = value
  M.Vec3{+x, +y, +z} = times
  +axis = dda_axis(F.is_lt(x, y), F.is_lt(x, z), F.is_lt(y, z))
  DDA{point_with(cell, axis, increment(point_axis(cell, axis), signs_axis(signs, axis))),
    M.Vec3.with_axis(times, axis, F.add(M.Vec3.axis(times, axis), M.Vec3.axis(intervals, axis))),
    intervals, signs, corner, start, end, sizes, collisions, tail}

def dda_more(+value: DDA) -> Bool:
  DDA{cell, M.Vec3{x, y, z}, intervals, signs, corner, start, end, sizes, collisions, tail} = value
  F.is_le(x, M.one()) || F.is_le(y, M.one()) || F.is_le(z, M.one())

def cell_box(+point: Point) -> A.AABB:
  Point{+x, +y, +z} = point
  A.AABB{F.from_i32(x), F.from_i32(y), F.from_i32(z),
    F.from_i32(U32.inc(x)), F.from_i32(U32.inc(y)), F.from_i32(U32.inc(z))}

def clamp(+value: F.F64, +low: F.F64, +high: F.F64) -> F.F64:
  A.math_max(low, A.math_min(value, high))

def crossing_coordinate(+value: F.F64, +cell: U32) -> F.F64:
  clamp(value, F.add(F.from_i32(cell), P.deflation()),
    F.sub(F.add(F.from_i32(cell), M.one()), P.deflation()))

def opposite_point(+position: M.Vec3, +cell: Point, +sizes: M.Vec3, +corner: Signs) -> Result<&2, &2, Error, Point>:
  match position cell sizes corner:
    case M.Vec3{x, y, z} Point{cx, cy, cz} M.Vec3{sx, sy, sz} Signs{dx, dy, dz}:
      coordinate(M.Vec3{F.sub(crossing_coordinate(x, cx), F.mul(sx, signed_double(dx))),
        F.sub(crossing_coordinate(y, cy), F.mul(sy, signed_double(dy))),
        F.sub(crossing_coordinate(z, cz), F.mul(sz, signed_double(dz)))})

def dda_count(+value: DDA) -> U32:
  DDA{cell, times, intervals, signs, corner, start, end, sizes, count, tail} = value
  count

def dda_increment(+value: DDA) -> DDA:
  DDA{cell, times, intervals, signs, corner, start, end, sizes, count, tail} = value
  DDA{cell, times, intervals, signs, corner, start, end, sizes, U32.inc(count), tail}

def crossing_range(+cell: Point, +other: Result<&2, &2, Error, Point>, +delta: M.Vec3) -> Result<&2, &2, Error, Range>:
  match other:
    case Fail{error}: Fail{error}
    case Done{point}: Done{range(cell, point, order(delta), directions(delta))}

def dda_hit(+build: Build, +value: DDA, +segment: Segment, +limit: U32,
            +delta: M.Vec3, +position: M.Vec3) -> Build & DDA:
  DDA{+cell, times, intervals, signs, corner, start, end, sizes, count, tail} = value
  +next = dda_increment(value)
  (enumerated(build, segment, dda_count(next), limit, True{},
    crossing_range(cell, opposite_point(position, cell, sizes, corner), delta)), next)

def dda_crossed(+build: Build, +value: DDA, +segment: Segment, +limit: U32,
                +delta: M.Vec3, +clipped: Maybe<&2, M.Vec3>) -> Build & DDA:
  match clipped:
    case None{}: (build, value)
    case Some{position}: dda_hit(build, value, segment, limit, delta, position)

def dda_work_next(build: Build, +segment: Segment, +limit: U32, +delta: M.Vec3, +next: DDA) -> Build & DDA:
  DDA{cell, times, intervals, signs, corner, start, end, sizes, count, tail} = next
  dda_crossed(build, next, segment, limit, delta, C.clip(cell_box(cell), start, end))

def dda_work(build: Build, value: DDA, segment: Segment, limit: U32, delta: M.Vec3, work: Nat) -> Build & DDA:
  match work:
    case 0n: (failed(build, TraversalBudget{}), value)
    case 1n+q: dda_work_next(fuel_set(build, q), segment, limit, delta, dda_advance(value))

def dda_loop(fuel: Nat, +build: Build, +value: DDA, +segment: Segment, +limit: U32, +delta: M.Vec3) -> Build & DDA:
  match fuel:
    case 0n:
      decide(Build & DDA, unavailable(build) || Bool.not(dda_more(value)),
        _ => (build, value), _ => (failed(build, TraversalBudget{}), value))
    case 1n+p:
      decide(Build & DDA, unavailable(build) || Bool.not(dda_more(value)),
        _ => (build, value),
        _ => P.paired(Build, DDA, Build & DDA,
          dda_work(build, value, segment, limit, delta, get_fuel(build)),
          next => moved => dda_loop(p, next, moved, segment, limit, delta)))

def segment_box(+segment: Segment) -> A.AABB:
  Segment{from, to, box, far, tail} = segment
  box

def dda_finished_guard(+build: Build, +value: DDA, +segment: Segment, +limit: U32, +delta: M.Vec3, +blocked: Bool) -> Build:
  match blocked:
    case True{}: build
    case False{}: enumerated(build, segment, U32.inc(dda_count(value)), limit, True{}, box_range(segment_box(segment), delta, False{}))

def dda_finished(+build: Build, +value: DDA, +segment: Segment, +limit: U32, +delta: M.Vec3) -> Build:
  dda_finished_guard(build, value, segment, limit, delta, unavailable(build))

def moving_dda_finished(+segment: Segment, +limit: U32, +delta: M.Vec3, result: Build & DDA) -> Build:
  (build, value) = result
  dda_finished(build, value, segment, limit, delta)

def moving_dda(+build: Build, +segment: Segment, +limit: U32, +delta: M.Vec3,
               +ready: Result<&2, &2, Error, DDA>) -> Build:
  match ready:
    case Fail{error}: failed(build, error)
    case Done{value}:
      moving_dda_finished(segment, limit, delta, dda_loop(get_fuel(build), build, value, segment, limit, delta))

def moving_dda_guard(+build: Build, +segment: Segment, +limit: U32, +delta: M.Vec3,
                     +ready: Result<&2, &2, Error, DDA>, +blocked: Bool) -> Build:
  match blocked:
    case True{}: build
    case False{}: moving_dda(build, segment, limit, delta, ready)

def moving_initial(+build: Build, +segment: Segment, +limit: U32, +delta: M.Vec3) -> Build:
  Segment{from, to, +box, far, tail} = segment
  +next = enumerated(build, segment, 0, limit, False{}, box_range(M.box_move(box, M.Vec3{F.neg(M.Vec3.axis(delta, A.AxisX{})), F.neg(M.Vec3.axis(delta, A.AxisY{})), F.neg(M.Vec3.axis(delta, A.AxisZ{}))}), delta, False{}))
  moving_dda_guard(next, segment, limit, delta, dda_new(box, delta), unavailable(next))

def segment_run(+build: Build, +segment: Segment, +limit: U32, +delta: M.Vec3, +tiny: Bool) -> Build:
  match tiny:
    case True{}: enumerated(build, segment, 0, limit, False{}, box_range(segment_box(segment), delta, True{}))
    case False{}: moving_initial(build, segment, limit, delta)

def segment_reset(+build: Build) -> Build:
  Build{fuel, seen, reversed, last, stopped, failure, tail} = build
  Build{fuel, [], reversed, 0, False{}, failure, tail}

def last_step(+build: Build) -> U32:
  Build{fuel, seen, reversed, last, stopped, failure, tail} = build
  last

def segment_guard(+build: Build, +from: M.Vec3, +to: M.Vec3, +width: F32, +height: F32, +limit: U32, +blocked: Bool) -> Build & U32:
  match blocked:
    case True{}: (build, 0)
    case False{}:
      +delta = C.subtract(to, from)
      +distance = M.Vec3.length_squared(delta)
      +result = segment_run(segment_reset(build), Segment{from, to, P.deflated(M.make_box(to, width, height)),
        F.is_gt(distance, F.mul(far_threshold(), far_threshold())), []}, limit, delta, F.is_lt(distance, tiny_square()))
      (result, U32.inc(last_step(result)))

def segment(+build: Build, +from: M.Vec3, +to: M.Vec3, +width: F32, +height: F32, +limit: U32) -> Build & U32:
  segment_guard(build, from, to, width, height, limit, broken(build))

def remaining(+limit: U32, +used: U32) -> U32:
  choose(U32, 0, U32.sub(limit, used), U32.is_ge(used, limit))

def relative(+from: M.Vec3, +axis: A.Axis, +distance: F.F64) -> M.Vec3:
  match from axis:
    case M.Vec3{x, y, z} A.AxisX{}: M.Vec3{F.add(x, F.mul(M.one(), distance)), F.add(y, F.mul(M.zero(), distance)), F.add(z, F.mul(M.zero(), distance))}
    case M.Vec3{x, y, z} A.AxisY{}: M.Vec3{F.add(x, F.mul(M.zero(), distance)), F.add(y, F.mul(M.one(), distance)), F.add(z, F.mul(M.zero(), distance))}
    case M.Vec3{x, y, z} A.AxisZ{}: M.Vec3{F.add(x, F.mul(M.zero(), distance)), F.add(y, F.mul(M.zero(), distance)), F.add(z, F.mul(M.one(), distance))}

def movement_segment_result(result: Build & U32) -> Build & U32:
  (next, used) = result
  (next, remaining(16, used))

def axes_loop(axes: List<&2, A.Axis>, +delta: M.Vec3, +from: M.Vec3,
              +width: F32, +height: F32, +limit: U32, +build: Build) -> Build & U32:
  match axes:
    case Nil{}: (build, limit)
    case +axis <> +rest:
      +distance = M.Vec3.axis(delta, axis)
      +to = relative(from, axis, distance)
      decide(Build & U32, F.is_zero(distance),
        _ => axes_loop(rest, delta, from, width, height, limit, build),
        _ => P.paired(Build, U32, Build & U32, segment(build, from, to, width, height, limit),
          next => used => axes_loop(rest, delta, to, width, height, remaining(limit, used), next)))

def axes_order(+build: Build, +delta: M.Vec3, +from: M.Vec3, +width: F32, +height: F32, +value: Order) -> Build & U32:
  Order{a, b, c} = value
  axes_loop([a, b, c], delta, from, width, height, 16, build)

def movement_parts_guard(+build: Build, +from: M.Vec3, +to: M.Vec3, +original: Maybe<&2, M.Vec3>,
                         +width: F32, +height: F32, +delta: M.Vec3, +nonzero: Bool) -> Build & U32:
  match original nonzero:
    case Some{vector} True{}: axes_order(build, delta, from, width, height, order(vector))
    case _ _:
      movement_segment_result(segment(build, from, to, width, height, 16))

def segment_build(result: Build & U32) -> Build:
  (next, used) = result
  next

def movement_parts(+build: Build, +from: M.Vec3, +to: M.Vec3, +original: Maybe<&2, M.Vec3>,
                   +width: F32, +height: F32) -> Build & U32:
  +delta = C.subtract(to, from)
  movement_parts_guard(build, from, to, original, width, height, delta, F.is_gt(M.Vec3.length_squared(delta), M.zero()))

def movement_finished(+build: Build, +to: M.Vec3, +width: F32, +height: F32, +remainder: U32) -> Build:
  match remainder:
    case 0: segment_build(segment(build, to, to, width, height, 1))
    case _: build

def movement_valid_guard(+from: Maybe<&2, U32>, +to: Maybe<&2, U32>, +original: Maybe<&2, M.Vec3>) -> Bool:
  match from to original:
    case None{} None{} None{}: True{}
    case None{} None{} Some{vector}: Maybe.is_none(&2, U32, M.Vec3.invalid_field(vector))
    case _ _ _: False{}

def movement_valid(+value: Movement) -> Bool:
  Movement{from, to, original} = value
  movement_valid_guard(M.Vec3.invalid_field(from), M.Vec3.invalid_field(to), original)

def movements_loop(movements: List<&2, Movement>, +width: F32, +height: F32, +index: U32, +build: Build) -> Build:
  match movements:
    case Nil{}: build
    case Movement{+from, +to, +original} <> rest:
      decide(Build, broken(build), _ => build,
        _ => decide(Build, movement_valid(Movement{from, to, original}),
          _ => P.paired(Build, U32, Build,
            movement_parts(build, from, to, original, width, height),
            next => remainder => movements_loop(rest, width, height, U32.inc(index),
              movement_finished(next, to, width, height, remainder))),
          _ => failed(build, InvalidMovement{index, 0})))

def plan_build(+build: Build) -> Plan:
  Build{fuel, seen, reversed, last, stopped, failure, tail} = build
  Plan{List.reverse(&2, Visit, reversed), failure}

def plan_checked(+movements: List<&2, Movement>, +width: F32, +height: F32, +fuel: Nat,
                 +invalid: Maybe<&2, M.Error>) -> Plan:
  match invalid:
    case None{}: plan_build(movements_loop(movements, width, height, 0, Build{fuel, [], [], 0, False{}, None{}, []}))
    case Some{M.InvalidDimensions{field}}: Plan{[], Some{InvalidDimensions{field}}}
    case Some{error}: Plan{[], Some{InvalidDimensions{0}}}

def plan(+movements: List<&2, Movement>, +width: F32, +height: F32, +fuel: Nat) -> Plan:
  plan_checked(movements, width, height, fuel, M.dimension_error(width, height))

def inside(+visit: Visit) -> Bool:
  Visit{position, step, Segment{from, to, box, far, tail}} = visit
  far || A.AABB.intersects(box, cell_box(position))

def visit_point(+visit: Visit) -> Point:
  Visit{position, step, segment} = visit
  position

def visit_step(+visit: Visit) -> U32:
  Visit{position, step, segment} = visit
  step
