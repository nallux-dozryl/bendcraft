import Base
import ./f64.bend as F
import ./random.bend as R
import ./worldgen_perlin_noise.bend as P

# Actual 26.3 NoiseStack layers use double frequencies and float amplitudes.
# Each layer owns the actual GradientNoise permutation; no array is duplicated.
type Layer is Type:
  Layer{noise:P.Noise,frequency:F.F64,amplitude:F32}

type Stack is Type:
  Stack{layers:List<&1,Layer>}

type Config is Data:
  Config{xz_scale:F.F64,y_scale:F.F64,xz_factor:F.F64,y_factor:F.F64,smear_scale_multiplier:F.F64}

type Blended is Type:
  Blended{config:Config,min_limit:Stack,max_limit:Stack,main:Stack}

def base_scale() -> F.F64: F.F64{1082483531,3332894622}
# 0.9999847412109375 / (2^16-1) = exactly2^-16.
def limit_amplitude() -> F.F64: F.F64{1055916032,0}
# Rounded double12.75 / (2^8-1), before Builder.add casts to float.
def main_amplitude() -> F.F64: F.F64{1068079513,2576980378}

def fbm_prepend(noise:P.Noise,frequency:F.F64,amplitude:F.F64,
    result:R.Source & Result<&2,&1,String,List<&1,Layer>>) -> R.Source & Result<&2,&1,String,List<&1,Layer>>:
  match result:
    case Tuple{source,Done{layers}}: (source,Done{Layer{noise,frequency,F.to_f32(amplitude)} <> layers})
    case Tuple{source,Fail{error}}: (source,Fail{error})

def fbm_created(frequency:F.F64,amplitude:F.F64,result:R.Source & Result<&2,&1,String,P.Noise>,
    next:R.Source -> R.Source & Result<&2,&1,String,List<&1,Layer>>) -> R.Source & Result<&2,&1,String,List<&1,Layer>>:
  match result:
    case Tuple{source,Fail{error}}: (source,Fail{error})
    case Tuple{source,Done{noise}}: fbm_prepend(noise,frequency,amplitude,next(source))

# Creation order starts at frequency1, halves the double frequency and doubles
# the double amplitude after each constructor. Each individual amplitude is
# narrowed to float exactly once when added to the stack.
def fbm_layers(count:Nat,+random_fuel:Nat,source:R.Source,+frequency:F.F64,+amplitude:F.F64,+fudge:F.F64) -> R.Source & Result<&2,&1,String,List<&1,Layer>>:
  match count:
    case 0n: (source,Done{[]})
    case 1n+rest:
      fbm_created(frequency,amplitude,P.create(random_fuel,source,P.Smeared{F.mul(fudge,frequency)}),
        s => fbm_layers(rest,random_fuel,s,F.div(frequency,P.two()),F.mul(amplitude,P.two()),fudge))

def fbm_stack(result:R.Source & Result<&2,&1,String,List<&1,Layer>>) -> R.Source & Result<&2,&1,String,Stack>:
  match result:
    case Tuple{source,Done{layers}}: (source,Done{Stack{layers}})
    case Tuple{source,Fail{error}}: (source,Fail{error})

def create_fbm(random_fuel:Nat,source:R.Source,count:Nat,fudge:F.F64,amplitude:F.F64) -> R.Source & Result<&2,&1,String,Stack>:
  fbm_stack(fbm_layers(count,random_fuel,source,P.one(),amplitude,fudge))

def blended_main(config:Config,min_limit:Stack,max_limit:Stack,
    result:R.Source & Result<&2,&1,String,Stack>) -> R.Source & Result<&2,&1,String,Blended>:
  match result:
    case Tuple{source,Done{main}}: (source,Done{Blended{config,min_limit,max_limit,main}})
    case Tuple{source,Fail{error}}: (source,Fail{error})

def blended_max(config:Config,min_limit:Stack,result:R.Source & Result<&2,&1,String,Stack>,
    next:R.Source -> R.Source & Result<&2,&1,String,Stack>) -> R.Source & Result<&2,&1,String,Blended>:
  match result:
    case Tuple{source,Done{max_limit}}: blended_main(config,min_limit,max_limit,next(source))
    case Tuple{source,Fail{error}}: (source,Fail{error})

def blended_min(config:Config,result:R.Source & Result<&2,&1,String,Stack>,
    next:R.Source -> Stack -> R.Source & Result<&2,&1,String,Blended>) -> R.Source & Result<&2,&1,String,Blended>:
  match result:
    case Tuple{source,Done{min_limit}}: next(source,min_limit)
    case Tuple{source,Fail{error}}: (source,Fail{error})

def create_commit(original:R.Source,result:R.Source & Result<&2,&1,String,Blended>) -> R.Source & Result<&2,&1,String,Blended>:
  match result:
    case Tuple{source,Done{blended}}: (source,Done{blended})
    case Tuple{source,Fail{error}}: (original,Fail{error})

def create_unchecked(+random_fuel:Nat,+source:R.Source,+config:Config) -> R.Source & Result<&2,&1,String,Blended>:
  Config{xz_scale,y_scale,xz_factor,+y_factor,smear_scale_multiplier} = config
  +fudge = F.mul(F.mul(base_scale(),y_scale),smear_scale_multiplier)
  create_commit(source,blended_min(config,create_fbm(random_fuel,source,16n,fudge,limit_amplitude()),
    s => min_limit => blended_max(config,min_limit,create_fbm(random_fuel,s,16n,fudge,limit_amplitude()),
      t => create_fbm(random_fuel,t,8n,F.div(fudge,y_factor),main_amplitude()))))

# These are the actual BlendedNoise.CODEC ranges, not product world bounds.
def scale_low() -> F.F64: F.F64{1062232653,3539053052}
def scale_high() -> F.F64: F.F64{1083129856,0}
def smear_high() -> F.F64: F.F64{1075838976,0}

def in_range(+value:F.F64,+low:F.F64,+high:F.F64) -> Bool:
  F.is_finite(value) && F.is_ge(value,low) && F.is_le(value,high)

def config_valid(config:Config) -> Bool:
  match config:
    case Config{xz_scale,y_scale,xz_factor,y_factor,smear_scale_multiplier}:
      in_range(xz_scale,scale_low(),scale_high()) && in_range(y_scale,scale_low(),scale_high()) &&
        in_range(xz_factor,scale_low(),scale_high()) && in_range(y_factor,scale_low(),scale_high()) &&
        in_range(smear_scale_multiplier,P.one(),smear_high())

def create_gate(random_fuel:Nat,source:R.Source,config:Config,valid:Bool) -> R.Source & Result<&2,&1,String,Blended>:
  match valid:
    case False{}: (source,Fail{"blended-noise configuration is outside the pinned finite codec ranges"})
    case True{}: create_unchecked(random_fuel,source,config)

# Admission runs before any RandomSource call. A refused Config preserves the
# exact source, as does an exhausted bounded-draw constructor transaction.
def create(random_fuel:Nat,source:R.Source,+config:Config) -> R.Source & Result<&2,&1,String,Blended>:
  create_gate(random_fuel,source,config,config_valid(config))

def stack_layers(layers:List<&1,Layer>,+farlands:Bool,+x:F.F64,+y:F.F64,+z:F.F64,accumulator:F32) -> List<&1,Layer> & F32:
  match layers:
    case Nil{}: ([],accumulator)
    case Layer{noise,+frequency,+amplitude} <> rest:
      P.paired(P.Noise,F32,List<&1,Layer> & F32,P.get(noise,farlands,F.mul(x,frequency),F.mul(y,frequency),F.mul(z,frequency)),noise => value =>
        P.paired(List<&1,Layer>,F32,List<&1,Layer> & F32,stack_layers(rest,farlands,x,y,z,F32.add(accumulator,F32.mul(amplitude,value))),rest => total =>
          (Layer{noise,frequency,amplitude} <> rest,total)))

# Both specialized26.3 NoiseStack.Perlin/SmearedPerlin.get implementations
# have the same scalar float-accumulation opcode order as NoiseStack.get.
def stack_get(stack:Stack,farlands:Bool,x:F.F64,y:F.F64,z:F.F64) -> Stack & F32:
  Stack{layers} = stack
  P.paired(List<&1,Layer>,F32,Stack & F32,stack_layers(layers,farlands,x,y,z,0.0),layers => value =>
    (Stack{layers},value))

# Mth.clamp(value,0,1): below0 returns+0; otherwise Math.min(value,1).
# This spelling retains NaN and signed zero, unlike Base.F32.min on NaN.
def clamp_alpha(+value:F32) -> F32:
  P.choose(F32,0.0,P.choose(F32,1.0,value,F32.is_gt(value,1.0)),F32.is_lt(value,0.0))

type BlendCase is Data:
  FirstOnly{}
  SecondOnly{}
  Both{}

def blend_case(+alpha:F32) -> BlendCase:
  P.choose(BlendCase,FirstOnly{},P.choose(BlendCase,SecondOnly{},Both{},F32.is_eq(alpha,1.0)),F32.is_eq(alpha,0.0))

# Match the actual scalar LerpFunction sampler's endpoint short circuit. A
# skipped noise Stack is returned unchanged; mixed values sample min then max.
def blend_limits(first:Stack,second:Stack,+farlands:Bool,+x:F.F64,+y:F.F64,+z:F.F64,alpha:F32,which:BlendCase) -> Stack & (Stack & F32):
  match which:
    case FirstOnly{}:
      P.paired(Stack,F32,Stack & (Stack & F32),stack_get(first,farlands,x,y,z),first => value =>
        (first,(second,value)))
    case SecondOnly{}:
      P.paired(Stack,F32,Stack & (Stack & F32),stack_get(second,farlands,x,y,z),second => value =>
        (first,(second,value)))
    case Both{}:
      P.paired(Stack,F32,Stack & (Stack & F32),stack_get(first,farlands,x,y,z),first => a =>
        P.paired(Stack,F32,Stack & (Stack & F32),stack_get(second,farlands,x,y,z),second => b =>
          (first,(second,P.lerp(alpha,a,b)))))

def blended_result(config:Config,main:Stack,result:Stack & (Stack & F32)) -> Blended & F32:
  (min_limit,tail) = result
  (max_limit,value) = tail
  (Blended{config,min_limit,max_limit,main},value)

# BlendedNoise.compileSampler's real scalar producer. Each input-axis scaling
# is double; frequencies of the main sampler are divided before multiplication
# by the input coordinate. Main+0.5, clamp and final lerp all operate in float.
def get(blended:Blended,+farlands:Bool,+x:F.F64,+y:F.F64,+z:F.F64) -> Blended & F32:
  match blended:
    case Blended{Config{+xz_scale,+y_scale,+xz_factor,+y_factor,smear_scale_multiplier},min_limit,max_limit,main}:
      +xz_multiplier = F.mul(base_scale(),xz_scale)
      +y_multiplier = F.mul(base_scale(),y_scale)
      P.paired(Stack,F32,Blended & F32,stack_get(main,farlands,
        F.mul(x,F.div(xz_multiplier,xz_factor)),F.mul(y,F.div(y_multiplier,y_factor)),F.mul(z,F.div(xz_multiplier,xz_factor))),main => +main_value =>
          blended_result(Config{xz_scale,y_scale,xz_factor,y_factor,smear_scale_multiplier},main,
            blend_limits(min_limit,max_limit,farlands,F.mul(x,xz_multiplier),F.mul(y,y_multiplier),F.mul(z,xz_multiplier),
              clamp_alpha(F32.add(main_value,0.5)),blend_case(clamp_alpha(F32.add(main_value,0.5))))))

def sample_block(blended:Blended,farlands:Bool,x:U32,y:U32,z:U32) -> Blended & F32:
  get(blended,farlands,F.from_i32(x),F.from_i32(y),F.from_i32(z))
