import Base

# The pinned 26.3 CubicSpline and compiled SplineFunction use FLOAT throughout.
# Coordinates are raw JSON before DAG compilation and earlier node indices
# afterwards. There is no host callback or hidden numerical implementation.
type Tree<-Coordinate:Data> is Data:
  Constant{value:F32}
  Multi{coordinate:Coordinate,points:List<&2,Point<Coordinate>>}

type Point<-Coordinate:Data> is Data:
  Point{location:F32,value:Tree<Coordinate>,derivative:F32}

type Selection is Data:
  Endpoint{index:U32}
  Segment{left:U32,right:U32}

def float_bits(bits:U32) -> F32:
  match bits:
    case U32{word}: F32{word}

def negate(value:F32) -> F32:
  float_bits(U32.xor(F32.bits(value),2147483648))

def lerp(t:F32,+first:F32,second:F32) -> F32:
  F32.add(first,F32.mul(t,F32.sub(second,first)))

def extend_gate(x:F32,location:F32,+value:F32,derivative:F32,zero:Bool) -> F32:
  match zero:
    case True{}: value
    case False{}: F32.add(value,F32.mul(derivative,F32.sub(x,location)))

# Vanilla's derivative==0 branch retains signed zero and avoids 0*infinity.
def extend(x:F32,location:F32,value:F32,+derivative:F32) -> F32:
  extend_gate(x,location,value,derivative,F32.is_eq(derivative,0.0))

# Operation order is the actual CubicSpline.Multipoint.sample bytecode order.
def hermite(+x:F32,+l0:F32,+l1:F32,+v0:F32,+v1:F32,d0:F32,d1:F32) -> F32:
  +width = F32.sub(l1,l0)
  +t = F32.div(F32.sub(x,l0),width)
  a = F32.sub(F32.mul(d0,width),F32.sub(v1,v0))
  b = F32.add(F32.mul(negate(d1),width),F32.sub(v1,v0))
  F32.add(lerp(t,v0,v1),F32.mul(F32.mul(t,F32.sub(1.0,t)),lerp(t,a,b)))

def point_at(-Coordinate:Data,points:List<&2,Point<Coordinate>>,index:U32) -> Maybe<&2,Point<Coordinate>>:
  match points index:
    case Nil{} _: None{}
    case point <> rest 0: Some{point}
    case point <> rest _: point_at(Coordinate,rest,U32.sub(index,1))

def location_result(-Coordinate:Data,result:Maybe<&2,Point<Coordinate>>) -> Maybe<&2,F32>:
  match result:
    case None{}: None{}
    case Some{Point{location,value,derivative}}: Some{location}

def location_at(-Coordinate:Data,points:List<&2,Point<Coordinate>>,index:U32) -> Maybe<&2,F32>:
  location_result(Coordinate,point_at(Coordinate,points,index))

def less_than_location(+x:F32,value:Maybe<&2,F32>) -> Bool:
  match value:
    case None{}: False{}
    case Some{location}: F32.is_lt(x,location)

# This is Mth.binarySearch(0,locations.length,i -> x < locations[i]).
# JSON's constructor does not enforce sortedness or uniqueness, so replacing
# this with a linear walk or imposing either extra restriction is incorrect.
def search_choice(first:U32,length:U32,half:U32,middle:U32,before:Bool,
    next:U32 -> U32 -> U32) -> U32:
  match before:
    case True{}: next(first,half)
    case False{}: next(U32.inc(middle),U32.sub(length,U32.inc(half)))

def search(-Coordinate:Data,fuel:Nat,+points:List<&2,Point<Coordinate>>,+x:F32,
    +first:U32,+length:U32) -> U32:
  match fuel length:
    case _ 0: first
    case 0n _: first
    case 1n+rest _:
      +half = U32.shr(length)
      +middle = U32.add(first,half)
      search_choice(first,length,half,middle,less_than_location(x,location_at(Coordinate,points,middle)),
        next_first => next_length => search(Coordinate,rest,points,x,next_first,next_length))

def selected_last(+insertion:U32,count:U32,last:Bool) -> Selection:
  match last:
    case True{}: Endpoint{U32.sub(count,1)}
    case False{}: Segment{U32.sub(insertion,1),insertion}

def selected(+insertion:U32,+count:U32) -> Selection:
  match insertion:
    case 0: Endpoint{0}
    case _: selected_last(insertion,count,U32.is_eq(insertion,count))

def select(-Coordinate:Data,+points:List<&2,Point<Coordinate>>,x:F32) -> Result<&2,&2,String,Selection>:
  match points:
    case Nil{}: Fail{"density spline has no points"}
    case point <> rest:
      +count = U32.from_nat(List.length(&2,Point<Coordinate>,points))
      Done{selected(search(Coordinate,33n,points,x,0,count),count)}
