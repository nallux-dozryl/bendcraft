import Base
import ./worldgen_density_ast.bend as A
import ./worldgen_density_codec.bend as Codec
import ./worldgen_density_noise.bend as DN
import ./worldgen_blended_noise.bend as BL
import ./worldgen_density_interval.bend as I
import ./worldgen_density_math.bend as M
import ./worldgen_density_spline_range.bend as SR
import ./worldgen_perlin_noise.bend as P
import ./f64.bend as F
import ./json.bend as J

type Entry is Data:
  Entry{index:U32,range:I.Interval}

def binding(bindings:List<&2,A.Binding>,+key:String) -> Maybe<&2,J.Value>:
  match bindings:
    case Nil{}: None{}
    case A.Binding{name,value} <> rest:
      Bool.pick(Maybe<&2,J.Value>,String.eq(name,key),Some{value},binding(rest,key))

def found(entries:List<&2,Entry>,+index:U32) -> Maybe<&2,I.Interval>:
  match entries:
    case Nil{}: None{}
    case Entry{key,range} <> rest:
      Bool.pick(Maybe<&2,I.Interval>,U32.is_eq(key,index),Some{range},found(rest,index))

def child_result(value:Maybe<&2,I.Interval>) -> Result<&2,&2,String,I.Interval>:
  match value:
    case None{}: Fail{"density range child is absent or does not precede its parent"}
    case Some{range}: Done{range}

def child(entries:List<&2,Entry>,index:U32) -> Result<&2,&2,String,I.Interval>:
  child_result(found(entries,index))

def normal_parameters(parameters:DN.Parameters) -> Result<&2,&2,String,I.Interval>:
  match parameters:
    case DN.Parameters{octaves,normalization,maximum}: I.symmetric(maximum)

def normal_loaded(key:String,value:Maybe<&2,J.Value>) -> Result<&2,&2,String,I.Interval>:
  match value:
    case None{}: Fail{"density range requires the loaded normal-noise definition"}
    case Some{value}:
      do Result<&2,&2,String,I.Interval>:
        config:DN.Config <- Codec.noise_config(key,value)
        normal_parameters(DN.parameters(config))

def normal(registry:A.Registry,+key:String) -> Result<&2,&2,String,I.Interval>:
  match registry:
    case A.Registry{densities,noises}: normal_loaded(key,binding(noises,key))

# BlendedNoise.computeFbmRange uses a double frequency/fudge and double builder
# amplitude, then narrows each layer's amplitude and symmetric bound to float.
def fbm_range(fuel:Nat,+fudge:F.F64,+frequency:F.F64,+amplitude:F.F64,acc:I.Interval) -> Result<&2,&2,String,I.Interval>:
  match fuel:
    case 0n: Done{acc}
    case 1n+rest:
      do Result<&2,&2,String,I.Interval>:
        layer:I.Interval <- I.symmetric(F.to_f32(F.add(F.abs(F.mul(fudge,frequency)),P.two())))
        factor:I.Interval <- I.exact(F.to_f32(amplitude))
        contribution:I.Interval <- I.mul(layer,factor)
        next:I.Interval <- I.add(acc,contribution)
        fbm_range(rest,fudge,F.div(frequency,P.two()),F.mul(amplitude,P.two()),next)

def base(config:BL.Config) -> Result<&2,&2,String,I.Interval>:
  match config:
    case BL.Config{xz,y,xf,yf,smear}:
      fbm_range(16n,F.mul(F.mul(BL.base_scale(),y),smear),P.one(),BL.limit_amplitude(),I.Range{0.0,0.0})

def unary(+operation:A.Unary,+range:I.Interval) -> Result<&2,&2,String,I.Interval>:
  match operation range:
    case _ I.NaI{}: Done{I.NaI{}}
    case A.Abs{} _: I.absolute(range)
    case A.Square{} _: I.square(range)
    case A.Negate{} _: I.sub(I.Range{0.0,0.0},range)
    case _ I.Range{low,high}: I.mapped_endpoints(M.unary(operation,low),M.unary(operation,high))

def binary(operation:A.Binary,left:I.Interval,right:I.Interval) -> Result<&2,&2,String,I.Interval>:
  match operation:
    case A.Add{}: I.add(left,right)
    case A.Subtract{}: I.sub(left,right)
    case A.Multiply{}: I.mul(left,right)
    case A.Divide{}: I.div(left,right)
    case A.Minimum{}: I.min(left,right)
    case A.Maximum{}: I.max(left,right)

def minmax(operation:A.Binary,left:U32,right:U32,mode:A.MinMaxMode,+entries:List<&2,Entry>) -> Result<&2,&2,String,I.Interval>:
  match mode:
    case A.ReadLeft{}: child(entries,left)
    case A.ReadRight{}: child(entries,right)
    case _:
      do Result<&2,&2,String,I.Interval>:
        first:I.Interval <- child(entries,left)
        second:I.Interval <- child(entries,right)
        binary(operation,first,second)

def operation(operation:A.Operation,+registry:A.Registry,+entries:List<&2,Entry>) -> Result<&2,&2,String,I.Interval>:
  match operation:
    case A.OpConstant{value}: I.exact(value)
    case A.OpUnary{kind,index}:
      do Result<&2,&2,String,I.Interval>:
        value:I.Interval <- child(entries,index)
        unary(kind,value)
    case A.OpBinary{kind,left,right,lc,rc}:
      do Result<&2,&2,String,I.Interval>:
        first:I.Interval <- child(entries,left)
        second:I.Interval <- child(entries,right)
        binary(kind,first,second)
    case A.OpMinMax{kind,left,right,mode}: minmax(kind,left,right,mode,entries)
    case A.OpGradient{axis,bottom,top,from,to}: I.encapsulating(from,to)
    case A.OpClamp{index,low,high}:
      do Result<&2,&2,String,I.Interval>:
        value:I.Interval <- child(entries,index)
        I.clamp(value,low,high)
    case A.OpLerp{alpha,first,second}:
      do Result<&2,&2,String,I.Interval>:
        amount:I.Interval <- child(entries,alpha)
        left:I.Interval <- child(entries,first)
        right:I.Interval <- child(entries,second)
        I.lerp(amount,left,right)
    case A.OpRangeChoice{index,low,high,inside,outside}:
      do Result<&2,&2,String,I.Interval>:
        left:I.Interval <- child(entries,inside)
        right:I.Interval <- child(entries,outside)
        I.encapsulate_ranges([left,right])
    case A.OpCache{index}: child(entries,index)
    case A.OpBaseNoise{config}: base(config)
    case A.OpNoise{key,xz,y,sx,sy,sz,mode}: normal(registry,key)
    case A.OpShiftA{key}:
      do Result<&2,&2,String,I.Interval>:
        value:I.Interval <- normal(registry,key)
        I.mul(value,I.Range{4.0,4.0})
    case A.OpShiftB{key}:
      do Result<&2,&2,String,I.Interval>:
        value:I.Interval <- normal(registry,key)
        I.mul(value,I.Range{4.0,4.0})
    case A.OpBlendAlpha{}: Done{I.Range{0.0,1.0}}
    case A.OpBlendOffset{}: Done{I.infinite()}
    case A.OpBlendDensity{index}: child(entries,index)
    case A.OpSpline{tree}:
      SR.range(~U32,~List<&2,Entry>,~(entries => index => child(entries,index)),tree,entries)

# Compilation visits each node only after all children have been assigned an
# index. The range table shares that same complete finite DAG and exact registry.
def analyze(nodes:List<&2,A.Node>,+registry:A.Registry,+entries:List<&2,Entry>) -> Result<&2,&2,String,List<&2,Entry>>:
  match nodes:
    case Nil{}: Done{entries}
    case A.Node{index,original,op} <> rest:
      do Result<&2,&2,String,List<&2,Entry>>:
        range:I.Interval <- operation(op,registry,entries)
        analyze(rest,registry,Entry{index,range} <> entries)

def program(program:A.Program) -> Result<&2,&2,String,List<&2,Entry>>:
  match program:
    case A.Program{plan,registry,expression,nodes,root}: analyze(nodes,registry,[])
