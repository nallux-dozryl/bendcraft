import Base
import ./worldgen_density_ast.bend as A
import ./worldgen_density_interval.bend as I

def constants(+left:I.Interval,+right:I.Interval,lc:Bool,rc:Bool,bound:F32) -> A.MinMaxMode:
  match lc rc:
    case True{} _: A.ConstantLeft{I.low(left)}
    case False{} True{}: A.ConstantRight{I.low(right)}
    case False{} False{}: A.BoundedRight{bound}

def minimum_mode(+left:I.Interval,+right:I.Interval,lc:Bool,rc:Bool,first:Bool,second:Bool) -> A.MinMaxMode:
  match first second:
    case True{} _: A.ReadLeft{}
    case False{} True{}: A.ReadRight{}
    case False{} False{}: constants(left,right,lc,rc,I.low(right))

def maximum_mode(+left:I.Interval,+right:I.Interval,lc:Bool,rc:Bool,first:Bool,second:Bool) -> A.MinMaxMode:
  match first second:
    case True{} _: A.ReadLeft{}
    case False{} True{}: A.ReadRight{}
    case False{} False{}: constants(left,right,lc,rc,I.high(right))

# The strict compile-time disjoint tests precede direct-constant selection.
# Generic runtime bounds are inclusive, as in MinSampler and MaxSampler.
def mode(operation:A.Binary,+left:I.Interval,+right:I.Interval,lc:Bool,rc:Bool) -> Result<&2,&2,String,A.MinMaxMode>:
  match operation:
    case A.Minimum{}: Done{minimum_mode(left,right,lc,rc,F32.is_lt(I.high(left),I.low(right)),F32.is_lt(I.high(right),I.low(left)))}
    case A.Maximum{}: Done{maximum_mode(left,right,lc,rc,F32.is_gt(I.low(left),I.high(right)),F32.is_gt(I.low(right),I.high(left)))}
    case _: Fail{"density MinMax operation must be minimum or maximum"}

def combine(operation:A.Binary,left:F32,right:F32) -> Result<&2,&2,String,F32>:
  match operation:
    case A.Minimum{}: Done{I.float_min(left,right)}
    case A.Maximum{}: Done{I.float_max(left,right)}
    case _: Fail{"density MinMax operation must be minimum or maximum"}

def skip(operation:A.Binary,value:F32,bound:F32) -> Bool:
  match operation:
    case A.Minimum{}: F32.is_le(value,bound)
    case A.Maximum{}: F32.is_ge(value,bound)
    case _: False{}

def combined(-Owner:Type,operation:A.Binary,first:F32,result:Owner & Result<&2,&2,String,F32>) -> Owner & Result<&2,&2,String,F32>:
  match result:
    case Tuple{owner,Fail{message}}: (owner,Fail{message})
    case Tuple{owner,Done{value}}: (owner,combine(operation,first,value))

def constant_combined(-Owner:Type,operation:A.Binary,constant:F32,result:Owner & Result<&2,&2,String,F32>) -> Owner & Result<&2,&2,String,F32>:
  match result:
    case Tuple{owner,Fail{message}}: (owner,Fail{message})
    case Tuple{owner,Done{value}}: (owner,combine(operation,value,constant))

def second(-Owner:Type,operation:A.Binary,owner:Owner,first:F32,right:U32,skip:Bool,
    read:Owner -> U32 -> Owner & Result<&2,&2,String,F32>) -> Owner & Result<&2,&2,String,F32>:
  match skip:
    case True{}: (owner,Done{first})
    case False{}: combined(Owner,operation,first,read(owner,right))

def first(-Owner:Type,+operation:A.Binary,right:U32,+bound:F32,result:Owner & Result<&2,&2,String,F32>,
    read:Owner -> U32 -> Owner & Result<&2,&2,String,F32>) -> Owner & Result<&2,&2,String,F32>:
  match result:
    case Tuple{owner,Fail{message}}: (owner,Fail{message})
    case Tuple{owner,Done{+value}}: second(Owner,operation,owner,value,right,skip(operation,value,bound),read)

def step(-Owner:Type,operation:A.Binary,left:U32,right:U32,mode:A.MinMaxMode,owner:Owner,
    read_left:Owner -> U32 -> Owner & Result<&2,&2,String,F32>,
    read_right:Owner -> U32 -> Owner & Result<&2,&2,String,F32>) -> Owner & Result<&2,&2,String,F32>:
  match mode:
    case A.ReadLeft{}: read_left(owner,left)
    case A.ReadRight{}: read_right(owner,right)
    case A.ConstantLeft{value}: constant_combined(Owner,operation,value,read_right(owner,right))
    case A.ConstantRight{value}: constant_combined(Owner,operation,value,read_left(owner,left))
    case A.BoundedRight{bound}: first(Owner,operation,right,bound,read_left(owner,left),read_right)
