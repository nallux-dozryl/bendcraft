import Base
import ./f64.bend as F
import ./geometry.bend as A
import ./movement.bend as M

# Original AABB.clip finite branch, retaining the Java X/Y/Z update order.
type Hit is Data:
  Hit{time: F.F64, found: Bool}

def half() -> F.F64:
  F.F64{1071644672, 0}

def one() -> F.F64:
  F.F64{1072693248, 0}

def subtract(a: M.Vec3, b: M.Vec3) -> M.Vec3:
  match a b:
    case M.Vec3{x, y, z} M.Vec3{u, v, w}: M.Vec3{F.sub(x, u), F.sub(y, v), F.sub(z, w)}

def center(box: A.AABB) -> M.Vec3:
  A.AABB{+a, +b, +c, d, e, f} = box
  M.Vec3{F.add(a, F.mul(half(), F.sub(d, a))),
    F.add(b, F.mul(half(), F.sub(e, b))), F.add(c, F.mul(half(), F.sub(f, c)))}

def sizes(box: A.AABB) -> M.Vec3:
  A.AABB{a, b, c, d, e, f} = box
  M.Vec3{F.sub(d, a), F.sub(e, b), F.sub(f, c)}

def point_gate(old: Hit, time: F.F64, valid: Bool) -> Hit:
  match valid:
    case True{}: Hit{time, True{}}
    case False{}: old

# Recursive context bounds native continuation specialization; internal tails
# are Nil. The transverse-axis permutation is supplied by clip_delta.
type AxisInput is Data:
  AxisInput{delta: M.Vec3, low: M.Vec3, high: M.Vec3,
            start: M.Vec3, tail: List<&2, AxisInput>}

def plane(input: AxisInput, high: Bool) -> F.F64:
  match input high:
    case AxisInput{delta, M.Vec3{x, y, z}, upper, start, tail} False{}: x
    case AxisInput{delta, lower, M.Vec3{x, y, z}, start, tail} True{}: x

def point(+old: Hit, input: AxisInput, plane: F.F64) -> Hit:
  match old input:
    case Hit{limit, found} AxisInput{M.Vec3{dx, dy, dz}, M.Vec3{low, low_y, low_z}, M.Vec3{high, high_y, high_z}, M.Vec3{x, y, z}, tail}:
      +t = F.div(F.sub(plane, x), dx)
      +a = F.add(y, F.mul(t, dy))
      +b = F.add(z, F.mul(t, dz))
      point_gate(old, t, F.is_gt(t, M.zero()) && F.is_lt(t, limit) &&
        F.is_gt(a, F.sub(low_y, A.epsilon())) && F.is_lt(a, F.add(high_y, A.epsilon())) &&
        F.is_gt(b, F.sub(low_z, A.epsilon())) && F.is_lt(b, F.add(high_z, A.epsilon())))

def axis_gate(old: Hit, +input: AxisInput, positive: Bool, negative: Bool) -> Hit:
  match positive negative:
    case True{} _: point(old, input, plane(input, False{}))
    case False{} True{}: point(old, input, plane(input, True{}))
    case False{} False{}: old

def axis(old: Hit, +input: AxisInput) -> Hit:
  AxisInput{M.Vec3{+dx, dy, dz}, low, high, start, tail} = input
  axis_gate(old, input, F.is_gt(dx, A.epsilon()), F.is_lt(dx, F.neg(A.epsilon())))

def hit_point(start: M.Vec3, delta: M.Vec3, hit: Hit) -> Maybe<&2, M.Vec3>:
  match start delta hit:
    case _ _ Hit{time, False{}}: None{}
    case M.Vec3{x, y, z} M.Vec3{u, v, w} Hit{+time, True{}}:
      Some{M.Vec3{F.add(x, F.mul(time, u)), F.add(y, F.mul(time, v)), F.add(z, F.mul(time, w))}}

def clip_delta(box: A.AABB, +start: M.Vec3, +delta: M.Vec3) -> Maybe<&2, M.Vec3>:
  A.AABB{+a, +b, +c, +d, +e, +f} = box
  M.Vec3{+x, +y, +z} = start
  M.Vec3{+u, +v, +w} = delta
  x_hit = axis(Hit{one(), False{}}, AxisInput{M.Vec3{u, v, w}, M.Vec3{a, b, c}, M.Vec3{d, e, f}, M.Vec3{x, y, z}, []})
  y_hit = axis(x_hit, AxisInput{M.Vec3{v, w, u}, M.Vec3{b, c, a}, M.Vec3{e, f, d}, M.Vec3{y, z, x}, []})
  hit_point(start, delta, axis(y_hit, AxisInput{M.Vec3{w, u, v}, M.Vec3{c, a, b}, M.Vec3{f, d, e}, M.Vec3{z, x, y}, []}))

def clip(box: A.AABB, +start: M.Vec3, end: M.Vec3) -> Maybe<&2, M.Vec3>:
  clip_delta(box, start, subtract(end, start))
