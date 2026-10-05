import Base
import ./vanilla_block_lighting_model.bend as M
import ./vanilla_block_lighting_math.bend as F
import ./block_model.bend as B

def same(a:M.Position,b:M.Position) -> Bool:
  M.Position{x,y,z}=a
  M.Position{r,s,t}=b
  U32.is_eq(x,r) && U32.is_eq(y,s) && U32.is_eq(z,t)
def offset(p:M.Position,d:B.Direction) -> M.Position:
  M.Position{+x,+y,+z}=p
  match d:
    case B.Down{}: M.Position{x,U32.sub(y,1),z}
    case B.Up{}: M.Position{x,U32.inc(y),z}
    case B.North{}: M.Position{x,y,U32.sub(z,1)}
    case B.South{}: M.Position{x,y,U32.inc(z)}
    case B.West{}: M.Position{U32.sub(x,1),y,z}
    case B.East{}: M.Position{U32.inc(x),y,z}
def vector_valid(v:B.Vec3) -> Bool:
  B.Vec3{x,y,z}=v
  F.finite(x) && F.finite(y) && F.finite(z)
def min(a:B.Vec3,b:B.Vec3) -> B.Vec3:
  B.Vec3{x,y,z}=a
  B.Vec3{r,s,t}=b
  B.Vec3{F32.min(x,r),F32.min(y,s),F32.min(z,t)}
def max(a:B.Vec3,b:B.Vec3) -> B.Vec3:
  B.Vec3{x,y,z}=a
  B.Vec3{r,s,t}=b
  B.Vec3{F32.max(x,r),F32.max(y,s),F32.max(z,t)}
def full_axis(+low:F32,+high:F32) -> Bool: F32.is_lt(low,0.0001) && F32.is_gt(high,0.9999)
def partial(low:B.Vec3,high:B.Vec3,dir:B.Direction) -> Bool:
  B.Vec3{+x,+y,+z}=low
  B.Vec3{+a,+b,+c}=high
  match dir:
    case B.Down{}: Bool.not(full_axis(x,a) && full_axis(z,c))
    case B.Up{}: Bool.not(full_axis(x,a) && full_axis(z,c))
    case B.North{}: Bool.not(full_axis(x,a) && full_axis(y,b))
    case B.South{}: Bool.not(full_axis(x,a) && full_axis(y,b))
    case B.West{}: Bool.not(full_axis(y,b) && full_axis(z,c))
    case B.East{}: Bool.not(full_axis(y,b) && full_axis(z,c))
def cubic(low:B.Vec3,high:B.Vec3,dir:B.Direction,+solid:Bool) -> Bool:
  B.Vec3{+x,+y,+z}=low
  B.Vec3{+a,+b,+c}=high
  match dir:
    case B.Down{}: F32.is_eq(y,b) && (F32.is_lt(y,0.0001) || solid)
    case B.Up{}: F32.is_eq(y,b) && (F32.is_gt(b,0.9999) || solid)
    case B.North{}: F32.is_eq(z,c) && (F32.is_lt(z,0.0001) || solid)
    case B.South{}: F32.is_eq(z,c) && (F32.is_gt(c,0.9999) || solid)
    case B.West{}: F32.is_eq(x,a) && (F32.is_lt(x,0.0001) || solid)
    case B.East{}: F32.is_eq(x,a) && (F32.is_gt(a,0.9999) || solid)
def shape(q:M.Quad,full:Bool) -> M.Bounds:
  M.Quad{+a,+b,+c,+d,+direction,override,emission}=q
  +low=min(min(min(min(B.Vec3{32.0,32.0,32.0},a),b),c),d)
  +high=max(max(max(max(B.Vec3{F32.sub(0.0,32.0),F32.sub(0.0,32.0),F32.sub(0.0,32.0)},a),b),c),d)
  M.Bounds{low,high,cubic(low,high,direction,full),partial(low,high,direction)}
def extent(bounds:M.Bounds,index:U32) -> F32:
  M.Bounds{B.Vec3{+x,+y,+z},B.Vec3{+a,+b,+c},cubic,partial}=bounds
  match index:
    case 0: y
    case 1: b
    case 2: z
    case 3: c
    case 4: x
    case 5: a
    case 6: F32.sub(1.0,y)
    case 7: F32.sub(1.0,b)
    case 8: F32.sub(1.0,z)
    case 9: F32.sub(1.0,c)
    case 10: F32.sub(1.0,x)
    case _: F32.sub(1.0,a)
def weights(+shape:M.Bounds,values:List<&2,U32>) -> M.Weights:
  match values:
    case a <> b <> c <> d <> e <> f <> g <> h <> Nil{}:
      M.Weights{F32.mul(extent(shape,a),extent(shape,b)),F32.mul(extent(shape,c),extent(shape,d)),F32.mul(extent(shape,e),extent(shape,f)),F32.mul(extent(shape,g),extent(shape,h))}
    case _: M.Weights{0.0,0.0,0.0,0.0}
def seen(values:List<&2,M.Position>,+p:M.Position) -> Bool:
  match values:
    case Nil{}: False{}
    case head <> rest: same(head,p) || seen(rest,p)
def unique_head(+head:M.Position,prior:List<&2,M.Position>,duplicate:Bool,continue:List<&2,M.Position> -> List<&2,M.Position>) -> List<&2,M.Position>:
  match duplicate:
    case True{}: continue(prior)
    case False{}: head <> continue(head <> prior)
def unique(values:List<&2,M.Position>,+prior:List<&2,M.Position>) -> List<&2,M.Position>:
  match values:
    case Nil{}: []
    case +head <> rest: unique_head(head,prior,seen(prior,head),p => unique(rest,p))
