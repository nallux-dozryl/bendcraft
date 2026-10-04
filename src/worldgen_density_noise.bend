import Base
import ./f64.bend as F
import ./random.bend as R
import ./worldgen_seed.bend as WS
import ./worldgen_perlin_noise.bend as P
import ./worldgen_blended_noise.bend as BL

# These are NormalNoise.Parameters' three actual codec choices. Legacy here is
# the parameter normalization formula, separate from LegacyFbmInitializer.
type Normalization is Data:
  Disabled{}
  Enabled{}
  Legacy{}

type Config is Data:
  Config{identity:String,base_amplitude:F.F64,base_octave:U32,octave_count:U32,
    normalize:Normalization,amplitude_modifiers:List<&2,F.F64>}

type Octave is Data:
  Octave{index:U32,frequency:F.F64,amplitude:F.F64}

type Parameters is Data:
  Parameters{octaves:List<&2,Octave>,normalization:F.F64,max_value:F32}

type Built is Type:
  Built{parameters:Parameters,stack:BL.Stack}

type Noise is Type:
  Noise{root:WS.Root,name:String,config:Config,built:Built}

def input_factor() -> F.F64: F.F64{1072712255,1803626750}
def third() -> F.F64: F.F64{1070945621,1431655765}
def perlin_deviation() -> F.F64: F.F64{1070680924,3817187881}
def amplitude_low() -> F.F64: F.F64{1055193269,2147483648}
def amplitude_high() -> F.F64: F.F64{1093567616,0}
def tenth() -> F.F64: F.F64{1069128089,2576980378}

# All admitted exponents are in [-32,63]. Math.pow(2,integer) is exact here;
# adding the bias to the signed Java word gives that exact normal double.
def pow_two(exponent:U32) -> F.F64:
  F.F64{U32.shln(U32.add(exponent,1023),20n),0}

def decimal_loop(room:Nat,+value:U32,text:String,finished:Bool) -> String:
  match room finished:
    case _ True{}: text
    case 0n False{}: text
    case 1n+left False{}:
      decimal_loop(left,U32.div(value,10),SCon{Chr{U32.add(48,U32.mod(value,10))},text},U32.is_lt(value,10))

# Integer.toString's exact digits, with sufficient fuel for every U32 magnitude.
# This avoids Base's mutually recursive formatter in the constructor closure.
def decimal_text(value:U32) -> String:
  decimal_loop(10n,value,"",False{})

def signed_text(value:U32,negative:Bool) -> String:
  match negative:
    case False{}: decimal_text(value)
    case True{}: "-" ++ decimal_text(U32.sub(0,value))

def octave_name(+index:U32) -> String:
  "octave_" ++ signed_text(index,U32.is_le(2147483648,index))

def finite_range(+value:F.F64,+low:F.F64,+high:F.F64) -> Bool:
  F.is_finite(value) && F.is_ge(value,low) && F.is_le(value,high)

def modifiers_valid(room:Nat,values:List<&2,F.F64>,remaining:U32) -> Bool:
  match room values:
    case _ Nil{}: U32.is_eq(remaining,0)
    case 0n _: False{}
    case 1n+left +head <> rest:
      # Codec.doubleRange compares boxed Doubles: -0.0 sorts below +0.0.
      Bool.not(F.is_zero(head) && F.sign(head)) &&
        finite_range(head,P.zero(),amplitude_high()) && modifiers_valid(left,rest,U32.sub(remaining,1))

def modifiers_admitted(values:List<&2,F.F64>,count:U32) -> Bool:
  match values:
    case Nil{}: True{}
    case _: modifiers_valid(32n,values,count)

# The signed base-octave bound and list shape are the actual 26.3 codec bounds.
# Modifier zeroes are retained in Config but omitted from the generated layers.
def config_valid(config:Config) -> Bool:
  match config:
    case Config{identity,amplitude,+octave,+count,normalize,modifiers}:
      finite_range(amplitude,amplitude_low(),amplitude_high()) &&
        (U32.is_le(octave,32) || U32.is_le(4294967264,octave)) &&
        U32.is_le(1,count) && U32.is_le(count,32) && modifiers_admitted(modifiers,count)

def supported_name(+name:String) -> Bool:
  Bool.not(String.eq(name,"minecraft:nether/temperature") || String.eq(name,"minecraft:nether/vegetation"))

def identity_matches(name:String,config:Config) -> Bool:
  match config:
    case Config{identity,amplitude,octave,count,normalize,modifiers}: String.eq(name,identity)

def initial_amplitude(amplitude:F.F64,+count:U32,normalize:Normalization) -> F.F64:
  match normalize:
    case Disabled{}: amplitude
    case _:
      F.mul(amplitude,F.div(pow_two(U32.sub(count,1)),F.sub(pow_two(count),P.one())))

def octave_prepend(index:U32,frequency:F.F64,amplitude:F.F64,zero:Bool,rest:List<&2,Octave>) -> List<&2,Octave>:
  match zero:
    case True{}: rest
    case False{}: Octave{index,frequency,amplitude} <> rest

def default_octaves(count:Nat,+index:U32,+frequency:F.F64,+amplitude:F.F64) -> List<&2,Octave>:
  match count:
    case 0n: []
    case 1n+left:
      Octave{index,frequency,F.mul(amplitude,P.one())} <>
        default_octaves(left,U32.inc(index),F.mul(frequency,P.two()),F.mul(amplitude,P.half()))

def modified_octaves(values:List<&2,F.F64>,+index:U32,+frequency:F.F64,+amplitude:F.F64) -> List<&2,Octave>:
  match values:
    case Nil{}: []
    case +modifier <> rest:
      octave_prepend(index,frequency,F.mul(amplitude,modifier),F.is_zero(modifier),
        modified_octaves(rest,U32.inc(index),F.mul(frequency,P.two()),F.mul(amplitude,P.half())))

def build_octaves(count:U32,index:U32,frequency:F.F64,amplitude:F.F64,modifiers:List<&2,F.F64>) -> List<&2,Octave>:
  match modifiers:
    case Nil{}: default_octaves(U32.to_nat(count),index,frequency,amplitude)
    case _: modified_octaves(modifiers,index,frequency,amplitude)

# Sequential DoubleStream.sum uses compensated addition for abs amplitudes.
# estimateDeviation has a distinct ordinary left-to-right double sum.
type Sum is Data:
  Sum{total:F.F64,compensation:F.F64,simple:F.F64}

def sum_add(state:Sum,+value:F.F64) -> Sum:
  match state:
    case Sum{+total,compensation,simple}:
      +corrected = F.sub(value,compensation)
      +next = F.add(total,corrected)
      Sum{next,F.sub(F.sub(next,total),corrected),F.add(simple,value)}

def infinite_class(kind:F.F64Class) -> Bool:
  match kind:
    case F.F64Infinity{}: True{}
    case _: False{}

def infinite(value:F.F64) -> Bool:
  infinite_class(F.classify(value))

def sum_finish_case(value:F.F64,simple:F.F64,use_simple:Bool) -> F.F64:
  match use_simple:
    case True{}: simple
    case False{}: value

def sum_finish(state:Sum) -> F.F64:
  match state:
    case Sum{total,compensation,+simple}:
      +value = F.sub(total,compensation)
      sum_finish_case(value,simple,F.is_nan(value) && infinite(simple))

def absolute_sum(octaves:List<&2,Octave>,state:Sum) -> F.F64:
  match octaves:
    case Nil{}: sum_finish(state)
    case Octave{index,frequency,amplitude} <> rest: absolute_sum(rest,sum_add(state,F.abs(amplitude)))

def deviation_sum(octaves:List<&2,Octave>,accumulator:F.F64) -> F.F64:
  match octaves:
    case Nil{}: F.sqrt(accumulator)
    case Octave{index,frequency,amplitude} <> rest:
      +scaled = F.mul(perlin_deviation(),F.abs(amplitude))
      deviation_sum(rest,F.add(accumulator,F.mul(scaled,scaled)))

def normalization_case(sum:F.F64,deviation:F.F64,zero:Bool) -> F.F64:
  match zero:
    case True{}: P.zero()
    case False{}: F.div(F.mul(sum,third()),F.mul(deviation,F.sqrt(P.two())))

def normal_factor(sum:F.F64,+deviation:F.F64) -> F.F64:
  normalization_case(sum,deviation,F.is_zero(deviation))

type Span is Data:
  Span{first:U32,last:U32}

def span_max(last:U32,index:U32,positive:Bool) -> U32:
  match positive:
    case True{}: U32.max(last,index)
    case False{}: index

def span_update(+index:U32,span:Span,zero:Bool) -> Span:
  match span zero:
    case _ True{}: span
    case Span{first,+last} False{}:
      Span{U32.min(first,index),span_max(last,index,U32.is_lt(last,2147483648))}

def modifier_span(values:List<&2,F.F64>,+index:U32,span:Span) -> Span:
  match values:
    case Nil{}: span
    case modifier <> rest:
      modifier_span(rest,U32.inc(index),span_update(index,span,F.is_zero(modifier)))

def parity_span(values:List<&2,F.F64>,count:U32) -> Span:
  match values:
    case Nil{}: Span{0,U32.sub(count,1)}
    case _: modifier_span(values,0,Span{2147483647,2147483648})

def parity_factor(amplitude:F.F64,span:Span) -> F.F64:
  match span:
    case Span{first,last}:
      F.div(F.mul(F.mul(amplitude,P.half()),third()),
        F.mul(tenth(),F.add(P.one(),F.div(P.one(),F.from_i32(U32.inc(U32.sub(last,first)))))))

def parameters_factor(octaves:List<&2,Octave>,sum:F.F64,factor:F.F64,
    amplitude:F.F64,count:U32,modifiers:List<&2,F.F64>,legacy:Bool) -> Parameters:
  match legacy:
    case False{}: Parameters{octaves,factor,F.to_f32(F.mul(F.mul(sum,third()),F.from_u32(6)))}
    case True{}:
      +parity = parity_factor(amplitude,parity_span(modifiers,count))
      +adjusted = F.mul(sum,F.div(parity,factor))
      Parameters{octaves,parity,F.to_f32(F.mul(F.mul(adjusted,third()),F.from_u32(6)))}

def legacy_normalization(normalize:Normalization) -> Bool:
  match normalize:
    case Legacy{}: True{}
    case _: False{}

def parameters_octaves(+octaves:List<&2,Octave>,amplitude:F.F64,count:U32,
    normalize:Normalization,modifiers:List<&2,F.F64>) -> Parameters:
  +sum = absolute_sum(octaves,Sum{P.zero(),P.zero(),P.zero()})
  +factor = normal_factor(sum,deviation_sum(octaves,P.zero()))
  parameters_factor(octaves,sum,factor,amplitude,count,modifiers,
    legacy_normalization(normalize) && Bool.not(F.is_zero(factor)))

def parameters(config:Config) -> Parameters:
  match config:
    case Config{identity,+amplitude,+octave,+count,+normalize,+modifiers}:
      parameters_octaves(build_octaves(count,octave,pow_two(octave),initial_amplitude(amplitude,count,normalize),modifiers),
        amplitude,count,normalize,modifiers)

def named_perlin(random_fuel:Nat,result:Result<&2,&2,String,R.Source>) -> Result<&2,&1,String,P.Noise>:
  match result:
    case Fail{message}: Fail{message}
    case Done{source}:
      P.paired(R.Source,Result<&2,&1,String,P.Noise>,Result<&2,&1,String,P.Noise>,
        P.create(random_fuel,source,P.Perlin{}),advanced => status => status)

def layers_prepend(first:P.Noise,second:P.Noise,+frequency:F.F64,+amplitude:F32,
    result:Result<&2,&1,String,List<&1,BL.Layer>>) -> Result<&2,&1,String,List<&1,BL.Layer>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{layers}:
      Done{BL.Layer{first,frequency,amplitude} <>
        BL.Layer{second,F.mul(frequency,input_factor()),amplitude} <> layers}

def layers_second(first:P.Noise,frequency:F.F64,amplitude:F32,result:Result<&2,&1,String,P.Noise>,
    rest:Unit -> Result<&2,&1,String,List<&1,BL.Layer>>) -> Result<&2,&1,String,List<&1,BL.Layer>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{second}: layers_prepend(first,second,frequency,amplitude,rest(Unit{}))

def layers_first(frequency:F.F64,amplitude:F32,result:Result<&2,&1,String,P.Noise>,
    second:Unit -> Result<&2,&1,String,P.Noise>,rest:Unit -> Result<&2,&1,String,List<&1,BL.Layer>>) ->
    Result<&2,&1,String,List<&1,BL.Layer>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{first}: layers_second(first,frequency,amplitude,second(Unit{}),rest)

# Two positional factories are forked once before any layer constructor. Each
# nonzero modifier adds its first and second Perlin layer in that exact order.
def create_layers(octaves:List<&2,Octave>,+random_fuel:Nat,+first:R.Positional,+second:R.Positional,
    +normalization:F.F64) -> Result<&2,&1,String,List<&1,BL.Layer>>:
  match octaves:
    case Nil{}: Done{[]}
    case Octave{index,+frequency,amplitude} <> rest:
      +name = octave_name(index)
      +scaled = F.to_f32(F.mul(normalization,amplitude))
      layers_first(frequency,scaled,named_perlin(random_fuel,WS.named(first,name)),
        unit => named_perlin(random_fuel,WS.named(second,name)),
        unit => create_layers(rest,random_fuel,first,second,normalization))

def built_layers(source:R.Source,parameters:Parameters,result:Result<&2,&1,String,List<&1,BL.Layer>>) ->
    R.Source & Result<&2,&1,String,Built>:
  match result:
    case Fail{message}: (source,Fail{message})
    case Done{layers}: (source,Done{Built{parameters,BL.Stack{layers}}})

def forked_second(+random_fuel:Nat,first:R.Positional,+parameters:Parameters,
    result:R.Source & R.Positional) -> R.Source & Result<&2,&1,String,Built>:
  match parameters result:
    case Parameters{octaves,normalization,max_value} Tuple{source,second}:
      built_layers(source,parameters,create_layers(octaves,random_fuel,first,second,normalization))

def forked_first(random_fuel:Nat,parameters:Parameters,result:R.Source & R.Positional) ->
    R.Source & Result<&2,&1,String,Built>:
  match result:
    case Tuple{source,first}: forked_second(random_fuel,first,parameters,R.fork_positional(source))

def initialize_commit(original:R.Source,result:R.Source & Result<&2,&1,String,Built>) ->
    R.Source & Result<&2,&1,String,Built>:
  match result:
    case Tuple{source,Fail{message}}: (original,Fail{message})
    case Tuple{source,Done{built}}: (source,Done{built})

def initialize_gate(+random_fuel:Nat,+source:R.Source,config:Config,valid:Bool) ->
    R.Source & Result<&2,&1,String,Built>:
  match valid:
    case False{}: (source,Fail{"normal-noise configuration is outside the pinned finite codec ranges"})
    case True{}:
      initialize_commit(source,forked_first(random_fuel,parameters(config),R.fork_positional(source)))

# Failure rolls the entire constructor source back, including both initial
# positional forks and any earlier successful named octave constructors.
def initialize(random_fuel:Nat,source:R.Source,+config:Config) -> R.Source & Result<&2,&1,String,Built>:
  initialize_gate(random_fuel,source,config,config_valid(config))

def created(root:WS.Root,name:String,config:Config,result:R.Source & Result<&2,&1,String,Built>) ->
    Result<&2,&1,String,Noise>:
  match result:
    case Tuple{advanced,Fail{message}}: Fail{message}
    case Tuple{advanced,Done{built}}: Done{Noise{root,name,config,built}}

def create_named(root:WS.Root,name:String,random_fuel:Nat,+config:Config,
    result:Result<&2,&2,String,R.Source>) -> Result<&2,&1,String,Noise>:
  match result:
    case Fail{message}: Fail{message}
    case Done{source}: created(root,name,config,initialize(random_fuel,source,config))

def root_factory(root:WS.Root) -> R.Positional:
  match root:
    case WS.Root{seed,legacy,factory}: factory

def create_validated(+root:WS.Root,+name:String,random_fuel:Nat,+config:Config,valid:Bool) ->
    Result<&2,&1,String,Noise>:
  match valid:
    case False{}: Fail{"normal-noise configuration or parameter identity is invalid"}
    case True{}:
      create_named(root,name,random_fuel,config,WS.named(root_factory(root),name))

def create_supported(root:WS.Root,+name:String,random_fuel:Nat,+config:Config,supported:Bool) ->
    Result<&2,&1,String,Noise>:
  match supported:
    case False{}: Fail{"normal-noise legacy Nether biome initializer is unavailable"}
    case True{}: create_validated(root,name,random_fuel,config,config_valid(config) && identity_matches(name,config))

def create(root:WS.Root,+name:String,random_fuel:Nat,config:Config) -> Result<&2,&1,String,Noise>:
  create_supported(root,name,random_fuel,config,supported_name(name))

# NoiseStack.Perlin.get uses double coordinate*frequency for each input, then
# one float product and one float accumulator add per interleaved layer.
def get(noise:Noise,+x:F.F64,+y:F.F64,+z:F.F64) -> Noise & F32:
  match noise:
    case Noise{root,name,config,Built{parameters,stack}}:
      P.paired(BL.Stack,F32,Noise & F32,BL.stack_get(stack,False{},x,y,z),
        stack => value => (Noise{root,name,config,Built{parameters,stack}},value))
