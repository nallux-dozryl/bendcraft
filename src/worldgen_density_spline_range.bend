import Base
import ./worldgen_density_spline.bend as S
import ./worldgen_density_interval.bend as I

type BoundPoint is Data:
  BoundPoint{location:F32,range:I.Interval,derivative:F32}

type Bounds is Data:
  Bounds{minimum:F32,maximum:F32}

type Work<-Coordinate:Data> is Data:
  TreeWork{tree:S.Tree<Coordinate>}
  PointsWork{points:List<&2,S.Point<Coordinate>>}

type Output is Data:
  RangeOutput{range:I.Interval}
  PointsOutput{points:List<&2,BoundPoint>}

# Counts traversal work by structural recursion on the same Tree constructor.
# A multi node contributes its dispatch plus the terminating point-list visit.
def size(-Coordinate:Data,tree:S.Tree<Coordinate>) -> Nat:
  match tree:
    case S.Constant{value}: 1n
    case S.Multi{coordinate,Nil{}}: 2n
    case S.Multi{+coordinate,S.Point{location,value,derivative} <> rest}:
      1n+Nat.add(size(Coordinate,value),size(Coordinate,S.Multi{coordinate,rest}))

def last(points:List<&2,BoundPoint>) -> Maybe<&2,BoundPoint>:
  match points:
    case Nil{}: None{}
    case point <> Nil{}: Some{point}
    case point <> rest: last(rest)

def include(+a:Bounds,+b:F32,+c:F32) -> Bounds:
  match a:
    case Bounds{minimum,maximum}:
      Bounds{I.float_min(minimum,I.float_min(b,c)),I.float_max(maximum,I.float_max(b,c))}

def extension(acc:Bounds,+x:F32,point:BoundPoint) -> Bounds:
  match point:
    case BoundPoint{+location,+range,+derivative}:
      include(acc,S.extend(x,location,I.low(range),derivative),S.extend(x,location,I.high(range),derivative))

def extend_if(acc:Bounds,x:F32,point:BoundPoint,needed:Bool) -> Bounds:
  match needed:
    case False{}: acc
    case True{}: extension(acc,x,point)

def ends(+range:I.Interval,first:BoundPoint,last:BoundPoint) -> Bounds:
  match first last:
    case BoundPoint{+fl,+fr,+fd} BoundPoint{+ll,+lr,+ld}:
      extend_if(extend_if(Bounds{I.positive_infinity(),I.negative_infinity()},I.low(range),BoundPoint{fl,fr,fd},
          F32.is_lt(I.low(range),fl)),I.high(range),BoundPoint{ll,lr,ld},F32.is_gt(I.high(range),ll))

def include_children(points:List<&2,BoundPoint>,acc:Bounds) -> Bounds:
  match points acc:
    case Nil{} _: acc
    case BoundPoint{location,+range,derivative} <> rest Bounds{minimum,maximum}:
      include_children(rest,Bounds{I.float_min(minimum,I.low(range)),I.float_max(maximum,I.high(range))})

def segment_bounds(flat:Bool,acc:Bounds,left:BoundPoint,right:BoundPoint) -> Bounds:
  match flat acc left right:
    case True{} _ _ _: acc
    case False{} Bounds{minimum,maximum} BoundPoint{l0,+r0,d0} BoundPoint{l1,+r1,d1}:
      +width = F32.sub(l1,l0)
      +p = F32.mul(d0,width)
      +q = F32.mul(d1,width)
      +lo0 = I.low(r0)
      +hi0 = I.high(r0)
      +lo1 = I.low(r1)
      +hi1 = I.high(r1)
      base_min = I.float_min(lo0,lo1)
      base_max = I.float_max(hi0,hi1)
      a = F32.add(F32.sub(p,hi1),lo0)
      b = F32.add(F32.sub(p,lo1),hi0)
      c = F32.sub(F32.add(I.negate(q),lo1),hi0)
      d = F32.sub(F32.add(I.negate(q),hi1),lo0)
      Bounds{I.float_min(minimum,F32.add(base_min,F32.mul(0.25,I.float_min(a,c)))),
        I.float_max(maximum,F32.add(base_max,F32.mul(0.25,I.float_max(b,d))))}

def segments(points:List<&2,BoundPoint>,acc:Bounds) -> Bounds:
  match points:
    case Nil{}: acc
    case point <> Nil{}: acc
    case BoundPoint{l0,r0,+d0} <> BoundPoint{+l1,+r1,+d1} <> rest:
      segments(BoundPoint{l1,r1,d1} <> rest,
        segment_bounds(F32.is_eq(d0,0.0) && F32.is_eq(d1,0.0),acc,BoundPoint{l0,r0,d0},BoundPoint{l1,r1,d1}))

def finish_bounds(bounds:Bounds) -> Result<&2,&2,String,I.Interval>:
  match bounds:
    case Bounds{minimum,maximum}: I.of(minimum,maximum)

def finish_ends(range:I.Interval,+points:List<&2,BoundPoint>,last:Maybe<&2,BoundPoint>) -> Result<&2,&2,String,I.Interval>:
  match points last:
    case first <> rest Some{end}:
      finish_bounds(segments(points,include_children(points,ends(range,first,end))))
    case _ _: Fail{"density spline has no points"}

# Exact conservative Interval algorithm from pinned CubicSpline.Multipoint.
# All child ranges participate, even outside the coordinate interval. NaI for
# the coordinate returns before traversing children; child NaI reaches Interval.of.
def finish(range:I.Interval,+points:List<&2,BoundPoint>) -> Result<&2,&2,String,I.Interval>:
  finish_ends(range,points,last(points))

def as_output(result:Result<&2,&2,String,I.Interval>) -> Result<&2,&2,String,Output>:
  match result:
    case Fail{message}: Fail{message}
    case Done{range}: Done{RangeOutput{range}}

def as_range(result:Result<&2,&2,String,Output>) -> Result<&2,&2,String,I.Interval>:
  match result:
    case Fail{message}: Fail{message}
    case Done{RangeOutput{range}}: Done{range}
    case _: Fail{"density spline internal range result mismatch"}

def multi_result(range:I.Interval,result:Result<&2,&2,String,Output>) -> Result<&2,&2,String,Output>:
  match result:
    case Fail{message}: Fail{message}
    case Done{PointsOutput{points}}: as_output(finish(range,points))
    case _: Fail{"density spline internal point result mismatch"}

def points_result(point:BoundPoint,result:Result<&2,&2,String,Output>) -> Result<&2,&2,String,Output>:
  match result:
    case Fail{message}: Fail{message}
    case Done{PointsOutput{points}}: Done{PointsOutput{point <> points}}
    case _: Fail{"density spline internal point result mismatch"}

def tree_result(result:Result<&2,&2,String,Output>,next:I.Interval -> Result<&2,&2,String,Output>) -> Result<&2,&2,String,Output>:
  match result:
    case Fail{message}: Fail{message}
    case Done{RangeOutput{range}}: next(range)
    case _: Fail{"density spline internal range result mismatch"}

def coordinate_result(result:Result<&2,&2,String,I.Interval>,next:I.Interval -> Result<&2,&2,String,Output>) -> Result<&2,&2,String,Output>:
  match result:
    case Fail{message}: Fail{message}
    case Done{I.NaI{}}: Done{RangeOutput{I.NaI{}}}
    case Done{range}: next(range)

def range_work(~Coordinate:Data,~Context:Data,
    ~coordinate_range:Context -> Coordinate -> Result<&2,&2,String,I.Interval>,
    steps:Nat,work:Work<Coordinate>,+context:Context) -> Result<&2,&2,String,Output>:
  match steps work:
    case 0n _: Fail{"density spline range traversal work budget exhausted"}
    case 1n+remaining TreeWork{S.Constant{value}}: as_output(I.exact(value))
    case 1n+remaining TreeWork{S.Multi{coordinate,points}}:
      coordinate_result(coordinate_range(context,coordinate),range =>
        multi_result(range,range_work(~Coordinate,~Context,~coordinate_range,remaining,PointsWork{points},context)))
    case 1n+remaining PointsWork{Nil{}}: Done{PointsOutput{[]}}
    case 1n+ +remaining PointsWork{S.Point{location,value,derivative} <> rest}:
      tree_result(range_work(~Coordinate,~Context,~coordinate_range,remaining,TreeWork{value},context),range =>
        points_result(BoundPoint{location,range,derivative},
          range_work(~Coordinate,~Context,~coordinate_range,remaining,PointsWork{rest},context)))

def range(~Coordinate:Data,~Context:Data,
    ~coordinate_range:Context -> Coordinate -> Result<&2,&2,String,I.Interval>,
    +tree:S.Tree<Coordinate>,context:Context) -> Result<&2,&2,String,I.Interval>:
  as_range(range_work(~Coordinate,~Context,~coordinate_range,size(Coordinate,tree),TreeWork{tree},context))
