import Base
import ./worldgen_density_ast.bend as A
import ./worldgen_density_state.bend as S
import ./worldgen_density_compile.bend as C
import ./worldgen_perlin_noise.bend as P
import ./f64.bend as F
import ./worldgen_density_math.bend as M
import ./worldgen_density_interval.bend as I
import ./worldgen_density_spline.bend as SP
import ./worldgen_density_spline_eval.bend as SE
import ./worldgen_density_minmax.bend as MM
import ./worldgen_density_coordinates.bend as Coordinates

def float_bits(bits:U32) -> F32: M.float_bits(bits)
def clamp(value:F32,low:F32,high:F32) -> F32: M.clamp(value,low,high)
def unary(operation:A.Unary,value:F32) -> F32: M.unary(operation,value)

def binary(operation:A.Binary,left:F32,right:F32,right_constant:Bool) -> Result<&2,&2,String,F32>:
  match operation right_constant:
    case A.Add{} _: Done{F32.add(left,right)}
    case A.Subtract{} False{}: Done{F32.sub(left,right)}
    case A.Subtract{} True{}: Done{F32.add(left,F32.neg(right))}
    case A.Multiply{} _: Done{F32.mul(left,right)}
    case _ _: Fail{"density divide/min/max require the actual compiled range and constant-specialization implementation"}

def signed_le(a:U32,b:U32) -> Bool:
  U32.is_le(U32.xor(a,2147483648),U32.xor(b,2147483648))

def coordinate(axis:A.Axis,point:S.Point) -> U32:
  match axis point:
    case A.X{} S.Point{x,y,z}: x
    case A.Y{} S.Point{x,y,z}: y
    case A.Z{} S.Point{x,y,z}: z

def gradient_coordinate(+value:U32,+from:U32,+to:U32,ordered:Bool) -> U32:
  match ordered:
    case True{}: Bool.pick(U32,signed_le(value,from),from,Bool.pick(U32,signed_le(to,value),to,value))
    case False{}: Bool.pick(U32,signed_le(value,to),to,Bool.pick(U32,signed_le(from,value),from,value))

def gradient(axis:A.Axis,+from:U32,+to:U32,+from_value:F32,to_value:F32,point:S.Point) -> F32:
  +selected = gradient_coordinate(coordinate(axis,point),from,to,signed_le(from,to))
  factor = F32.div(F32.sub(to_value,from_value),F.to_f32(F.from_i32(U32.sub(to,from))))
  F32.add(from_value,F32.mul(F.to_f32(F.from_i32(U32.sub(selected,from))),factor))

def same_point(a:S.Point,b:S.Point) -> Bool:
  match a b:
    case S.Point{ax,ay,az} S.Point{bx,by,bz}: U32.is_eq(ax,bx) && U32.is_eq(ay,by) && U32.is_eq(az,bz)

def cached_point(point:S.Point,cached:Maybe<&2,S.Point>) -> Bool:
  match cached:
    case None{}: False{}
    case Some{old}: same_point(point,old)

def value_lookup(values:List<&2,S.Value>,+index:U32) -> Maybe<&2,F32>:
  match values:
    case Nil{}: None{}
    case S.Value{key,value} <> rest:
      Bool.pick(Maybe<&2,F32>,U32.is_eq(index,key),Some{value},value_lookup(rest,index))

def cache_for(+cache:S.Cache,+point:S.Point,same:Bool) -> S.Cache:
  match same:
    case True{}: cache
    case False{}: S.Cache{Some{point},[]}

def select_cache(cache:S.Cache,+point:S.Point) -> S.Cache:
  match cache:
    case S.Cache{+cached,values}: cache_for(S.Cache{cached,values},point,cached_point(point,cached))

def located(nodes:List<&2,A.Node>,+index:U32) -> Maybe<&2,A.Operation>:
  match nodes:
    case Nil{}: None{}
    case A.Node{key,original,operation} <> rest:
      Bool.pick(Maybe<&2,A.Operation>,U32.is_eq(index,key),Some{operation},located(rest,index))

def cache_value(state:S.State,+index:U32,result:Result<&2,&2,String,F32>) -> S.State & Result<&2,&2,String,F32>:
  match state result:
    case _ Fail{message}: (state,Fail{message})
    case S.State{program,pool,S.Cache{point,values}} Done{+value}:
      (S.State{program,pool,S.Cache{point,S.Value{index,value} <> values}},Done{value})

def remembered(index:U32,result:S.State & Result<&2,&2,String,F32>) -> S.State & Result<&2,&2,String,F32>:
  match result:
    case Tuple{state,status}: cache_value(state,index,status)

def continued(result:S.State & Result<&2,&2,String,F32>,
    next:S.State -> F32 -> S.State & Result<&2,&2,String,F32>) -> S.State & Result<&2,&2,String,F32>:
  match result:
    case Tuple{state,Fail{message}}: (state,Fail{message})
    case Tuple{state,Done{value}}: next(state)(value)

def transformed(operation:A.Unary,result:S.State & Result<&2,&2,String,F32>) -> S.State & Result<&2,&2,String,F32>:
  match result:
    case Tuple{state,Fail{message}}: (state,Fail{message})
    case Tuple{state,Done{value}}: (state,Done{unary(operation,value)})

def combined(operation:A.Binary,left:F32,right_constant:Bool,result:S.State & Result<&2,&2,String,F32>) -> S.State & Result<&2,&2,String,F32>:
  match result:
    case Tuple{state,Fail{message}}: (state,Fail{message})
    case Tuple{state,Done{right}}: (state,binary(operation,left,right,right_constant))

def binary_second(operation:A.Binary,left:F32,right:U32,right_constant:Bool,state:S.State,skip:Bool,
    next:S.State -> U32 -> S.State & Result<&2,&2,String,F32>) -> S.State & Result<&2,&2,String,F32>:
  match skip:
    case True{}: (state,Done{0.0})
    case False{}: combined(operation,left,right_constant,next(state)(right))

def multiply_skip(operation:A.Binary,left:F32,left_constant:Bool,right_constant:Bool) -> Bool:
  match operation:
    case A.Multiply{}: F32.is_eq(left,0.0) && Bool.not(left_constant || right_constant)
    case _: False{}

def clamped(low:F32,high:F32,result:S.State & Result<&2,&2,String,F32>) -> S.State & Result<&2,&2,String,F32>:
  match result:
    case Tuple{state,Fail{message}}: (state,Fail{message})
    case Tuple{state,Done{value}}: (state,Done{clamp(value,low,high)})

def lerped(alpha:F32,first:F32,result:S.State & Result<&2,&2,String,F32>) -> S.State & Result<&2,&2,String,F32>:
  match result:
    case Tuple{state,Fail{message}}: (state,Fail{message})
    case Tuple{state,Done{second}}: (state,Done{P.lerp(alpha,first,second)})

def lerp_branch(+alpha:F32,first:U32,second:U32,state:S.State,zero:Bool,one:Bool,
    first_read:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    second_read:S.State -> U32 -> S.State & Result<&2,&2,String,F32>) -> S.State & Result<&2,&2,String,F32>:
  match zero one:
    case True{} _: first_read(state)(first)
    case False{} True{}: second_read(state)(second)
    case False{} False{}:
      continued(first_read(state)(first),state => value => lerped(alpha,value,second_read(state)(second)))

def choice_branch(state:S.State,inside:U32,outside:U32,selected:Bool,
    inside_read:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    outside_read:S.State -> U32 -> S.State & Result<&2,&2,String,F32>) -> S.State & Result<&2,&2,String,F32>:
  match selected:
    case True{}: inside_read(state)(inside)
    case False{}: outside_read(state)(outside)

def produced(program:A.Program,cache:S.Cache,result:List<&1,S.Slot> & Result<&2,&2,String,F32>) -> S.State & Result<&2,&2,String,F32>:
  match result:
    case Tuple{pool,status}: (S.State{program,pool,cache},status)

def case_nodes(program:A.Program) -> List<&2,A.Node>:
  match program:
    case A.Program{plan,registry,expression,nodes,root}: nodes

def noise(state:S.State,key:S.Key,x:F.F64,y:F.F64,z:F.F64) -> S.State & Result<&2,&2,String,F32>:
  match state:
    case S.State{+program,pool,cache}:
      produced(program,cache,S.pool_get(List.length(&2,A.Node,case_nodes(program)),pool,key,x,y,z))

def shifted_value(result:S.State & Result<&2,&2,String,F32>) -> S.State & Result<&2,&2,String,F32>:
  match result:
    case Tuple{state,Fail{message}}: (state,Fail{message})
    case Tuple{state,Done{value}}: (state,Done{F32.mul(value,4.0)})

def shift(state:S.State,key:String,point:S.Point,is_a:Bool) -> S.State & Result<&2,&2,String,F32>:
  match point is_a:
    case S.Point{x,y,z} True{}:
      shifted_value(noise(state,S.NormalKey{key},F.mul(F.from_i32(x),F.F64{1070596096,0}),P.zero(),F.mul(F.from_i32(z),F.F64{1070596096,0})))
    case S.Point{x,y,z} False{}:
      shifted_value(noise(state,S.NormalKey{key},F.mul(F.from_i32(z),F.F64{1070596096,0}),F.mul(F.from_i32(x),F.F64{1070596096,0}),P.zero()))

def coordinate_noise(state:S.State,key:String,value:Coordinates.Coordinates) -> S.State & Result<&2,&2,String,F32>:
  match value:
    case Coordinates.Coordinates{x,y,z}: noise(state,S.NormalKey{key},x,y,z)

def shifted_noise(state:S.State,key:String,xz:F.F64,y_scale:F.F64,point:S.Point,sx:F32,sy:F32,sz:F32,mode:A.NoiseMode) -> S.State & Result<&2,&2,String,F32>:
  match point:
    case S.Point{x,y,z}: coordinate_noise(state,key,Coordinates.shifted(x,y,z,xz,y_scale,sx,sy,sz,mode))

def operation(operation:A.Operation,state:S.State,+point:S.Point,
    read_one:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    read_two:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    read_three:S.State -> U32 -> S.State & Result<&2,&2,String,F32>) -> S.State & Result<&2,&2,String,F32>:
  match operation:
    case A.OpConstant{value}: (state,Done{value})
    case A.OpUnary{kind,input}: transformed(kind,read_one(state)(input))
    case A.OpBinary{+kind,left,right,+lc,+rc}:
      continued(read_one(state)(left),state => +value =>
        binary_second(kind,value,right,rc && Bool.not(lc),state,multiply_skip(kind,value,lc,rc),read_two))
    case A.OpGradient{axis,from,to,fv,tv}: (state,Done{gradient(axis,from,to,fv,tv,point)})
    case A.OpClamp{input,low,high}: clamped(low,high,read_one(state)(input))
    case A.OpLerp{alpha,first,second}:
      continued(read_one(state)(alpha),state => +value =>
        lerp_branch(value,first,second,state,F32.is_eq(value,0.0),F32.is_eq(value,1.0),read_two,read_three))
    case A.OpRangeChoice{input,low,high,inside,outside}:
      continued(read_one(state)(input),state => +value =>
        choice_branch(state,inside,outside,F32.is_ge(value,low) && F32.is_lt(value,high),read_two,read_three))
    case A.OpCache{input}: read_one(state)(input)
    case A.OpBaseNoise{config}:
      P.paired(U32,U32,S.State & Result<&2,&2,String,F32>,(coordinate(A.X{},point),coordinate(A.Z{},point)),
        x => z => noise(state,S.BaseKey{config},F.from_i32(x),F.from_i32(coordinate(A.Y{},point)),F.from_i32(z)))
    case A.OpNoise{key,xz,y,sx,sy,sz,mode}:
      continued(read_one(state)(sx),state => x_shift =>
        continued(read_two(state)(sy),state => y_shift =>
          continued(read_three(state)(sz),state => z_shift => shifted_noise(state,key,xz,y,point,x_shift,y_shift,z_shift,mode))))
    case A.OpShiftA{key}: shift(state,key,point,True{})
    case A.OpShiftB{key}: shift(state,key,point,False{})
    case A.OpMinMax{kind,left,right,mode}: MM.step(S.State,kind,left,right,mode,state,read_one,read_two)
    case A.OpBlendAlpha{}: (state,Done{1.0})
    case A.OpBlendOffset{}: (state,Done{0.0})
    case A.OpBlendDensity{input}: read_one(state)(input)
    case A.OpSpline{tree}: (state,Fail{"density spline requires the structural evaluator work route"})

def indexed(state:S.State,index:U32,point:S.Point,found:Maybe<&2,A.Operation>,
    read_one:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    read_two:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    read_three:S.State -> U32 -> S.State & Result<&2,&2,String,F32>) -> S.State & Result<&2,&2,String,F32>:
  match found:
    case None{}: (state,Fail{"density DAG node index is absent"})
    case Some{op}: remembered(index,operation(op,state,point,read_one,read_two,read_three))

def cached(state:S.State,index:U32,point:S.Point,node:Maybe<&2,A.Operation>,hit:Maybe<&2,F32>,
    read_one:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    read_two:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    read_three:S.State -> U32 -> S.State & Result<&2,&2,String,F32>) -> S.State & Result<&2,&2,String,F32>:
  match hit:
    case Some{value}: (state,Done{value})
    case None{}: indexed(state,index,point,node,read_one,read_two,read_three)

type Work is Data:
  NodeWork{index:U32}
  SplineWork{tree:SP.Tree<U32>}

def work_indexed(state:S.State,index:U32,point:S.Point,+found:Maybe<&2,A.Operation>,
    read_one:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    read_two:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    read_three:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    read_spline:SP.Tree<U32> -> S.State -> S.State & Result<&2,&2,String,F32>) -> S.State & Result<&2,&2,String,F32>:
  match found:
    case Some{A.OpSpline{tree}}: remembered(index,read_spline(tree)(state))
    case _: indexed(state,index,point,found,read_one,read_two,read_three)

def work_cached(state:S.State,index:U32,point:S.Point,node:Maybe<&2,A.Operation>,hit:Maybe<&2,F32>,
    read_one:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    read_two:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    read_three:S.State -> U32 -> S.State & Result<&2,&2,String,F32>,
    read_spline:SP.Tree<U32> -> S.State -> S.State & Result<&2,&2,String,F32>) -> S.State & Result<&2,&2,String,F32>:
  match hit:
    case Some{value}: (state,Done{value})
    case None{}: work_indexed(state,index,point,node,read_one,read_two,read_three,read_spline)

# Density nodes and nested spline trees share one structural recursion. Only
# selected spline children are visited; the same node cache and seeded pool
# cross every branch. Coordinate evaluation remains an actual DAG read.
def work(+depth:Nat,state:S.State,task:Work,+point:S.Point) -> S.State & Result<&2,&2,String,F32>:
  match depth state task:
    case 0n _ _: (state,Fail{"density evaluation exceeds caller depth budget"})
    case 1n+ +left S.State{+program,pool,S.Cache{cached_point,+values}} NodeWork{+index}:
      work_cached(S.State{program,pool,S.Cache{cached_point,values}},index,point,located(case_nodes(program),index),value_lookup(values,index),
        state => child => work(left,state,NodeWork{child},point),
        state => child => work(left,state,NodeWork{child},point),
        state => child => work(left,state,NodeWork{child},point),
        tree => state => work(left,state,SplineWork{tree},point))
    case 1n+ +left _ SplineWork{tree}:
      SE.step(S.State,tree,state,
        state => child => work(left,state,NodeWork{child},point),
        tree => state => work(left,state,SplineWork{tree},point),
        tree => state => work(left,state,SplineWork{tree},point),
        tree => state => work(left,state,SplineWork{tree},point))

def run(depth:Nat,state:S.State,index:U32,point:S.Point) -> S.State & Result<&2,&2,String,F32>:
  work(depth,state,NodeWork{index},point)

def transaction(original:S.Cache,result:S.State & Result<&2,&2,String,F32>) -> S.State & Result<&2,&2,String,F32>:
  match result:
    case Tuple{S.State{program,pool,cache},Fail{message}}: (S.State{program,pool,original},Fail{message})
    case Tuple{state,Done{value}}: (state,Done{value})

def evaluate(depth:Nat,state:S.State,index:U32,+point:S.Point) -> S.State & Result<&2,&2,String,F32>:
  match state:
    case S.State{program,pool,+cache}:
      transaction(cache,run(depth,S.State{program,pool,select_cache(cache,point)},index,point))
