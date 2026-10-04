import Base

# Pinned net.minecraft.util.Interval uses float bounds and a distinguished NaI.
# Numeric helpers reproduce Java Math.min/max signed-zero and NaN behavior;
# Base's comparison-only min/max is insufficient for these boundaries.
type Interval is Data:
  Range{minimum:F32,maximum:F32}
  NaI{}

def bits(value:U32) -> F32:
  match value:
    case U32{word}: F32{word}

def nan() -> F32: bits(2143289344)
def positive_infinity() -> F32: bits(2139095040)
def negative_infinity() -> F32: bits(4286578688)
def is_nan(+value:F32) -> Bool: Bool.not(F32.is_eq(value,value))
def negative(value:F32) -> Bool: U32.is_le(2147483648,F32.bits(value))
def is_infinite(value:F32) -> Bool:
  U32.is_eq(U32.and(F32.bits(value),2147483647),2139095040)

def minimum_zero(+a:F32,+b:F32,both:Bool) -> F32:
  match both:
    case True{}: bits(U32.or(F32.bits(a),F32.bits(b)))
    case False{}: Bool.pick(F32,F32.is_le(a,b),a,b)

def minimum_nan(+a:F32,+b:F32,an:Bool,bn:Bool) -> F32:
  match an bn:
    case True{} _: a
    case False{} True{}: b
    case False{} False{}: minimum_zero(a,b,F32.is_eq(a,0.0) && F32.is_eq(b,0.0))

def float_min(+a:F32,+b:F32) -> F32: minimum_nan(a,b,is_nan(a),is_nan(b))

def maximum_zero(+a:F32,+b:F32,both:Bool) -> F32:
  match both:
    case True{}: bits(U32.and(F32.bits(a),F32.bits(b)))
    case False{}: Bool.pick(F32,F32.is_ge(a,b),a,b)

def maximum_nan(+a:F32,+b:F32,an:Bool,bn:Bool) -> F32:
  match an bn:
    case True{} _: a
    case False{} True{}: b
    case False{} False{}: maximum_zero(a,b,F32.is_eq(a,0.0) && F32.is_eq(b,0.0))

def float_max(+a:F32,+b:F32) -> F32: maximum_nan(a,b,is_nan(a),is_nan(b))

def abs(value:F32) -> F32: bits(U32.and(F32.bits(value),2147483647))
def negate(value:F32) -> F32: bits(U32.xor(F32.bits(value),2147483648))
def infinite() -> Interval: Range{negative_infinity(),positive_infinity()}

def low(value:Interval) -> F32:
  match value:
    case Range{minimum,maximum}: minimum
    case NaI{}: nan()

def high(value:Interval) -> F32:
  match value:
    case Range{minimum,maximum}: maximum
    case NaI{}: nan()

def is_nai(value:Interval) -> Bool:
  match value:
    case NaI{}: True{}
    case _: False{}

def valid(value:Interval) -> Bool:
  match value:
    case NaI{}: True{}
    case Range{+minimum,+maximum}: Bool.not(is_nan(minimum) || is_nan(maximum)) && F32.is_le(minimum,maximum)

# Interval.of canonicalizes ZERO_TO_ONE even when its lower input is -0.
def canonical(+minimum:F32,+maximum:F32) -> Interval:
  Bool.pick(Interval,F32.is_eq(minimum,0.0) && F32.is_eq(maximum,1.0),
    Range{0.0,1.0},Range{minimum,maximum})

def admitted(minimum:F32,maximum:F32,ordered:Bool,nan_bounds:Bool) -> Result<&2,&2,String,Interval>:
  match ordered nan_bounds:
    case False{} _: Fail{"density interval maximum is below minimum"}
    case True{} True{}: Fail{"density interval bounds cannot include NaN; use NaI"}
    case True{} False{}: Done{canonical(minimum,maximum)}

def of(+minimum:F32,+maximum:F32) -> Result<&2,&2,String,Interval>:
  admitted(minimum,maximum,Bool.not(F32.is_lt(maximum,minimum)),is_nan(minimum) || is_nan(maximum))

def exact(+value:F32) -> Result<&2,&2,String,Interval>: of(value,value)
def symmetric(+value:F32) -> Result<&2,&2,String,Interval>: of(negate(value),value)

def endpoints_nan(minimum:F32,maximum:F32,nans:Bool) -> Result<&2,&2,String,Interval>:
  match nans:
    case True{}: Done{NaI{}}
    case False{}: of(minimum,maximum)

def computed(+minimum:F32,+maximum:F32) -> Result<&2,&2,String,Interval>:
  endpoints_nan(minimum,maximum,is_nan(minimum) || is_nan(maximum))

def encapsulated(+a:F32,+b:F32,an:Bool,bn:Bool) -> Result<&2,&2,String,Interval>:
  match an bn:
    case True{} True{}: Done{NaI{}}
    case True{} False{}: exact(b)
    case False{} True{}: exact(a)
    case False{} False{}: of(float_min(a,b),float_max(a,b))

def encapsulating(+a:F32,+b:F32) -> Result<&2,&2,String,Interval>:
  encapsulated(a,b,is_nan(a),is_nan(b))

def add(a:Interval,b:Interval) -> Result<&2,&2,String,Interval>:
  match a b:
    case Range{amin,amax} Range{bmin,bmax}: computed(F32.add(amin,bmin),F32.add(amax,bmax))
    case _ _: Done{NaI{}}

def sub(a:Interval,b:Interval) -> Result<&2,&2,String,Interval>:
  match a b:
    case Range{amin,amax} Range{bmin,bmax}: computed(F32.sub(amin,bmax),F32.sub(amax,bmin))
    case _ _: Done{NaI{}}

# Interval.mulBound treats zero times an infinite bound as positive zero.
def mul_bound(+a:F32,+b:F32) -> F32:
  Bool.pick(F32,F32.is_eq(a,0.0) || F32.is_eq(b,0.0),0.0,F32.mul(a,b))

def products(+a:F32,+b:F32,+c:F32,+d:F32) -> Result<&2,&2,String,Interval>:
  of(float_min(float_min(a,b),float_min(c,d)),float_max(float_max(a,b),float_max(c,d)))

def mul(a:Interval,b:Interval) -> Result<&2,&2,String,Interval>:
  match a b:
    case Range{+amin,+amax} Range{+bmin,+bmax}:
      products(mul_bound(amin,bmin),mul_bound(amin,bmax),mul_bound(amax,bmin),mul_bound(amax,bmax))
    case _ _: Done{NaI{}}

def min(a:Interval,b:Interval) -> Result<&2,&2,String,Interval>:
  match a b:
    case Range{amin,amax} Range{bmin,bmax}: of(float_min(amin,bmin),float_min(amax,bmax))
    case _ _: Done{NaI{}}

def max(a:Interval,b:Interval) -> Result<&2,&2,String,Interval>:
  match a b:
    case Range{amin,amax} Range{bmin,bmax}: of(float_max(amin,bmin),float_max(amax,bmax))
    case _ _: Done{NaI{}}

def reciprocal_case(+minimum:F32,+maximum:F32,all_zero:Bool,crosses:Bool) -> Result<&2,&2,String,Interval>:
  match all_zero crosses:
    case True{} _: Done{NaI{}}
    case False{} True{}: Done{infinite()}
    case False{} False{}:
      Bool.pick(Result<&2,&2,String,Interval>,F32.is_eq(maximum,0.0),
        of(negative_infinity(),F32.div(1.0,minimum)),
        Bool.pick(Result<&2,&2,String,Interval>,F32.is_eq(minimum,0.0),
          of(F32.div(1.0,maximum),positive_infinity()),of(F32.div(1.0,maximum),F32.div(1.0,minimum))))

def reciprocal(a:Interval) -> Result<&2,&2,String,Interval>:
  match a:
    case NaI{}: Done{NaI{}}
    case Range{+minimum,+maximum}:
      reciprocal_case(minimum,maximum,F32.is_eq(minimum,0.0) && F32.is_eq(maximum,0.0),
        F32.is_lt(minimum,0.0) && F32.is_gt(maximum,0.0))

def div(a:Interval,b:Interval) -> Result<&2,&2,String,Interval>:
  do Result<&2,&2,String,Interval>:
    inverse:Interval <- reciprocal(b)
    mul(a,inverse)

def contains(a:Interval,+value:F32) -> Bool:
  match a:
    case NaI{}: False{}
    case Range{minimum,maximum}: F32.is_ge(value,minimum) && F32.is_le(value,maximum)

def absolute(+a:Interval) -> Result<&2,&2,String,Interval>:
  match a:
    case NaI{}: Done{NaI{}}
    case Range{+minimum,+maximum}:
      of(Bool.pick(F32,contains(a,0.0),0.0,float_min(abs(minimum),abs(maximum))),float_max(abs(minimum),abs(maximum)))

def square(+a:Interval) -> Result<&2,&2,String,Interval>:
  match a:
    case NaI{}: Done{NaI{}}
    case Range{+minimum,+maximum}:
      +first = F32.mul(minimum,minimum)
      +second = F32.mul(maximum,maximum)
      of(Bool.pick(F32,contains(a,0.0),0.0,float_min(first,second)),float_max(first,second))

def clamp_case(a:Interval,+bottom:F32,+top:F32,valid:Bool) -> Result<&2,&2,String,Interval>:
  match a valid:
    case _ False{}: Fail{"density interval clamp minimum exceeds maximum"}
    case NaI{} True{}: Done{NaI{}}
    case Range{+minimum,+maximum} True{}:
      Bool.pick(Result<&2,&2,String,Interval>,F32.is_ge(minimum,top),exact(top),
        Bool.pick(Result<&2,&2,String,Interval>,F32.is_le(maximum,bottom),exact(bottom),
          of(float_max(minimum,bottom),float_min(maximum,top))))

def clamp(a:Interval,+bottom:F32,+top:F32) -> Result<&2,&2,String,Interval>:
  clamp_case(a,bottom,top,Bool.not(F32.is_gt(bottom,top)))

def mapped_endpoints(+first:F32,+second:F32) -> Result<&2,&2,String,Interval>:
  of(float_min(first,second),float_max(first,second))

def lerp_bound(alpha:F32,+first:F32,last:F32) -> F32:
  F32.add(first,mul_bound(alpha,F32.sub(last,first)))

def infinite_lerp_case(+alpha:F32,+first:F32,+last:F32,a:F32,b:F32,both:Bool) -> F32:
  match both:
    case False{}: F32.add(a,b)
    case True{}:
      Bool.pick(F32,F32.is_le(alpha,0.0),
        Bool.pick(F32,F32.is_gt(last,first),negative_infinity(),positive_infinity()),
        Bool.pick(F32,F32.is_ge(alpha,1.0),
          Bool.pick(F32,F32.is_gt(last,first),positive_infinity(),negative_infinity()),nan()))

def infinite_lerp(+alpha:F32,+first:F32,+last:F32) -> F32:
  +a = mul_bound(F32.sub(1.0,alpha),first)
  +b = mul_bound(alpha,last)
  infinite_lerp_case(alpha,first,last,a,b,is_infinite(a) && is_infinite(b))

def lerp_pair_bounds(+minimum:F32,+maximum:F32,+first:F32,+last:F32,finite:Bool,same:Bool) -> Result<&2,&2,String,Interval>:
  match finite same:
    case True{} _: encapsulating(lerp_bound(minimum,first,last),lerp_bound(maximum,first,last))
    case False{} True{}: exact(first)
    case False{} False{}:
      +a = infinite_lerp(minimum,first,last)
      +b = infinite_lerp(maximum,first,last)
      Bool.pick(Result<&2,&2,String,Interval>,is_nan(a) || is_nan(b),Done{NaI{}},encapsulating(a,b))

def lerp_pair(alpha:Interval,+first:F32,+last:F32) -> Result<&2,&2,String,Interval>:
  match alpha:
    case NaI{}: Done{NaI{}}
    case Range{minimum,maximum}:
      Bool.pick(Result<&2,&2,String,Interval>,is_nan(first) || is_nan(last),Done{NaI{}},
        lerp_pair_bounds(minimum,maximum,first,last,Bool.not(is_infinite(first) || is_infinite(last)),F32.is_eq(first,last)))

def encapsulate_loop(values:List<&2,Interval>,+minimum:F32,+maximum:F32,found:Bool) -> Result<&2,&2,String,Interval>:
  match values:
    case Nil{}: Bool.pick(Result<&2,&2,String,Interval>,found,of(minimum,maximum),Done{NaI{}})
    case NaI{} <> rest: encapsulate_loop(rest,minimum,maximum,found)
    case Range{bottom,top} <> rest:
      encapsulate_loop(rest,float_min(minimum,bottom),float_max(maximum,top),True{})

def encapsulate_ranges(values:List<&2,Interval>) -> Result<&2,&2,String,Interval>:
  match values:
    case Nil{}: Fail{"density interval encapsulation requires a nonempty list"}
    case _: encapsulate_loop(values,positive_infinity(),negative_infinity(),False{})

def lerp(alpha:Interval,first:Interval,last:Interval) -> Result<&2,&2,String,Interval>:
  match alpha first last:
    case Range{+amin,+amax} Range{+fmin,+fmax} Range{+lmin,+lmax}:
      do Result<&2,&2,String,Interval>:
        a:Interval <- lerp_pair(Range{amin,amax},fmin,lmin)
        b:Interval <- lerp_pair(Range{amin,amax},fmax,lmin)
        c:Interval <- lerp_pair(Range{amin,amax},fmin,lmax)
        d:Interval <- lerp_pair(Range{amin,amax},fmax,lmax)
        encapsulate_ranges([a,b,c,d])
    case _ _ _: Done{NaI{}}
