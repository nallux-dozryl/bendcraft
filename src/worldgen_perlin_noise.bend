import Base
import ./f64.bend as F
import ./random.bend as R

# Pinned 26.3 GradientNoise/PerlinNoise/SmearedPerlinNoise scalar producers.
# There is no ImprovedNoise class in this release. Permutations are affine;
# sampling returns their owner with the float result, without cloning arrays.
type Mode is Data:
  Perlin{}
  Smeared{fudge_y_scale:F.F64}

type Noise is Type:
  Noise{perms:Array<U32>,offset_x:F.F64,offset_y:F.F64,offset_z:F.F64,mode:Mode}

def zero() -> F.F64: F.F64{0,0}
def one() -> F.F64: F.F64{1072693248,0}
def two() -> F.F64: F.F64{1073741824,0}
def half() -> F.F64: F.F64{1071644672,0}
def offset_scale() -> F.F64: F.F64{1081081856,0}
def round_off() -> F.F64: F.F64{1098907648,0}
# Math.nextDown(16777216.0), not the rounded integer boundary.
def half_round_off() -> F.F64: F.F64{1097859071,4294967295}
# The float 1.0e-7 promoted to double by SmearedPerlinNoise.computeFudgeY.
def smear_epsilon() -> F.F64: F.F64{1048238066,2684354560}

def choose(-A:Type,yes:A,no:A,condition:Bool) -> A:
  match condition:
    case True{}: yes
    case False{}: no

def paired(-A:Type,-B:Type,-C:Type,result:A & B,next:A -> B -> C) -> C:
  (a,b) = result
  next(a)(b)

# Math.floor over the binary64 payload, including signed zero, large finite
# values, infinities and NaNs. No i32 coordinate range limits the wrap step.
def floor_fraction(+negative:Bool,exponent:U32,retained:F.Wide,discarded:Bool) -> F.F64:
  match retained:
    case F.Wide{hi,lo}:
      +integer = {F.F64{U32.or(U32.or(F.sign_mask(negative),U32.shln(exponent,20n)),U32.and(hi,1048575)),lo} : F.F64}
      choose(F.F64,F.sub(integer,one()),integer,negative && discarded)

def floor_middle(negative:Bool,+exponent:U32,+significand:F.Wide) -> F.F64:
  +amount = U32.sub(1075,exponent)
  floor_fraction(negative,exponent,F.long_shift_left(U32.to_nat(amount),F.shift_right(amount,significand)),F.discarded(amount,significand))

def floor_small(+value:F.F64,negative:Bool,zero_value:Bool) -> F.F64:
  match zero_value:
    case True{}: value
    case False{}: choose(F.F64,F.neg(one()),zero(),negative)

def floor_parts(+value:F.F64,parts:F.Parts,small:Bool,integral:Bool) -> F.F64:
  match parts small integral:
    case F.Parts{negative,exponent,significand} True{} _: floor_small(value,negative,F.is_zero(value))
    case _ _ True{}: value
    case F.Parts{negative,exponent,significand} False{} False{}: floor_middle(negative,exponent,significand)

def floor_unpacked(+value:F.F64,parts:F.Parts) -> F.F64:
  match parts:
    case F.Parts{negative,+exponent,significand}:
      floor_parts(value,F.Parts{negative,exponent,significand},U32.is_lt(exponent,1023),U32.is_ge(exponent,1075))

def floor_double(+value:F.F64) -> F.F64:
  floor_unpacked(value,F.unpack(value))

# Mth.floor(double) is Math.floor followed by Java saturating d2i.
def floor_saturation(value:F.F64,nan:Bool) -> U32:
  match nan:
    case True{}: 0
    case False{}: U32.add(2147483647,Bool.to_u32(F.sign(value)))

def floor_i32_result(+value:F.F64,result:Result<&2,&2,F.F64ConversionError,U32>) -> U32:
  match result:
    case Done{word}: word
    case Fail{error}: floor_saturation(value,F.is_nan(value))

def floor_word(+value:F.F64) -> U32:
  floor_i32_result(value,F.floor_i32(value))

def wrap_gate(+value:F.F64,unchanged:Bool) -> F.F64:
  match unchanged:
    case True{}: value
    case False{}: F.sub(value,F.mul(floor_double(F.add(F.div(value,round_off()),half())),round_off()))

def wrap(+value:F.F64,farlands:Bool) -> F.F64:
  wrap_gate(value,farlands || (F.is_ge(value,F.neg(half_round_off())) && F.is_lt(value,half_round_off())))

def identity_permutation(fuel:Nat,+index:U32,perms:Array<U32>) -> Array<U32>:
  match fuel:
    case 0n: perms
    case 1n+rest: identity_permutation(rest,U32.inc(index),Array.set(U32,perms,index,index))

def shuffled_step(+index:U32,source:R.Source,perms:Array<U32>,draw:Result<&2,&2,R.RandomError,U32>,
    next:R.Source -> Array<U32> -> R.Source & Result<&2,&1,String,Array<U32>>) -> R.Source & Result<&2,&1,String,Array<U32>>:
  match draw:
    case Fail{error}: (source,Fail{"noise permutation random rejection fuel exhausted"})
    case Done{relative}:
      +other = U32.add(index,relative)
      paired(Array<U32>,U32,R.Source & Result<&2,&1,String,Array<U32>>,Array.get(U32,perms,index),perms => at_index =>
        paired(Array<U32>,U32,R.Source & Result<&2,&1,String,Array<U32>>,Array.get(U32,perms,other),perms => at_other =>
          next(source,Array.set(U32,Array.set(U32,perms,index,at_other),other,at_index))))

def shuffled_draw(+index:U32,perms:Array<U32>,result:R.Source & Result<&2,&2,R.RandomError,U32>,
    next:R.Source -> Array<U32> -> R.Source & Result<&2,&1,String,Array<U32>>) -> R.Source & Result<&2,&1,String,Array<U32>>:
  (source,draw) = result
  shuffled_step(index,source,perms,draw,next)

# Draw bound=1 at index255 still advances Java's RandomSource. Every successful
# constructor consumes the three nextDouble calls before all256 nextInt calls.
def shuffle(fuel:Nat,+index:U32,+random_fuel:Nat,source:R.Source,perms:Array<U32>) -> R.Source & Result<&2,&1,String,Array<U32>>:
  match fuel:
    case 0n: (source,Done{perms})
    case 1n+rest:
      shuffled_draw(index,perms,R.next_bounded(random_fuel,source,U32.sub(256,index)),
        s => a => shuffle(rest,U32.inc(index),random_fuel,s,a))

def initialized(offset_x:F.F64,offset_y:F.F64,offset_z:F.F64,mode:Mode,
    result:R.Source & Result<&2,&1,String,Array<U32>>) -> R.Source & Result<&2,&1,String,Noise>:
  match result:
    case Tuple{source,Done{perms}}: (source,Done{Noise{perms,offset_x,offset_y,offset_z,mode}})
    case Tuple{source,Fail{error}}: (source,Fail{error})

def initialize_commit(original:R.Source,result:R.Source & Result<&2,&1,String,Noise>) -> R.Source & Result<&2,&1,String,Noise>:
  match result:
    case Tuple{source,Done{noise}}: (source,Done{noise})
    case Tuple{source,Fail{error}}: (original,Fail{error})

def create(random_fuel:Nat,+source:R.Source,mode:Mode) -> R.Source & Result<&2,&1,String,Noise>:
  paired(R.Source,F.F64,R.Source & Result<&2,&1,String,Noise>,R.next_double(source),s => offset_x =>
    paired(R.Source,F.F64,R.Source & Result<&2,&1,String,Noise>,R.next_double(s),s => offset_y =>
      paired(R.Source,F.F64,R.Source & Result<&2,&1,String,Noise>,R.next_double(s),s => offset_z =>
        initialize_commit(source,initialized(F.mul(offset_x,offset_scale()),F.mul(offset_y,offset_scale()),F.mul(offset_z,offset_scale()),mode,
          shuffle(256n,0,random_fuel,s,identity_permutation(256n,0,Array.new(U32,8n,0))))))))

def permute(perms:Array<U32>,index:U32) -> Array<U32> & U32:
  paired(Array<U32>,U32,Array<U32> & U32,Array.get(U32,perms,U32.and(index,255)),perms => value =>
    (perms,U32.and(value,255)))

type Corners is Data:
  Corners{n000:U32,n100:U32,n010:U32,n110:U32,n001:U32,n101:U32,n011:U32,n111:U32}

# The fourteen byte-permutation reads of actual PerlinNoise.sampleAndLerp.
# Hash offsets use Java i32 addition followed by the actual255 index mask.
def corner_hashes(perms:Array<U32>,+ix:U32,+iy:U32,+iz:U32) -> Array<U32> & Corners:
  paired(Array<U32>,U32,Array<U32> & Corners,permute(perms,ix),perms => +px0 =>
    paired(Array<U32>,U32,Array<U32> & Corners,permute(perms,U32.inc(ix)),perms => +px1 =>
      paired(Array<U32>,U32,Array<U32> & Corners,permute(perms,U32.add(px0,iy)),perms => +py00 =>
        paired(Array<U32>,U32,Array<U32> & Corners,permute(perms,U32.inc(U32.add(px0,iy))),perms => +py01 =>
          paired(Array<U32>,U32,Array<U32> & Corners,permute(perms,U32.add(px1,iy)),perms => +py10 =>
            paired(Array<U32>,U32,Array<U32> & Corners,permute(perms,U32.inc(U32.add(px1,iy))),perms => +py11 =>
              paired(Array<U32>,U32,Array<U32> & Corners,permute(perms,U32.add(py00,iz)),perms => n000 =>
                paired(Array<U32>,U32,Array<U32> & Corners,permute(perms,U32.add(py10,iz)),perms => n100 =>
                  paired(Array<U32>,U32,Array<U32> & Corners,permute(perms,U32.add(py01,iz)),perms => n010 =>
                    paired(Array<U32>,U32,Array<U32> & Corners,permute(perms,U32.add(py11,iz)),perms => n110 =>
                      paired(Array<U32>,U32,Array<U32> & Corners,permute(perms,U32.inc(U32.add(py00,iz))),perms => n001 =>
                        paired(Array<U32>,U32,Array<U32> & Corners,permute(perms,U32.inc(U32.add(py10,iz))),perms => n101 =>
                          paired(Array<U32>,U32,Array<U32> & Corners,permute(perms,U32.inc(U32.add(py01,iz))),perms => n011 =>
                            paired(Array<U32>,U32,Array<U32> & Corners,permute(perms,U32.inc(U32.add(py11,iz))),perms => n111 =>
                              (perms,Corners{n000,n100,n010,n110,n001,n101,n011,n111})))))))))))))))

# SmearedPerlinNoise keeps the original, unwrapped input y for the positive
# clamp, then floors the double quotient plus the promoted-float epsilon.
def gradient_y(mode:Mode,+input_y:F.F64,+fraction_y:F.F64) -> F.F64:
  match mode:
    case Perlin{}: fraction_y
    case Smeared{+fudge_y_scale}:
      capped = choose(F.F64,input_y,fraction_y,F.is_ge(input_y,zero()) && F.is_lt(input_y,fraction_y))
      F.sub(fraction_y,F.mul(F.from_i32(floor_word(F.add(F.div(capped,fudge_y_scale),smear_epsilon()))),fudge_y_scale))

type Gradient is Data:
  Gradient{x:F32,y:F32,z:F32}

def gradient_index(index:U32) -> Gradient:
  match index:
    case 0: Gradient{1.0,1.0,0.0}
    case 1: Gradient{F32.neg(1.0),1.0,0.0}
    case 2: Gradient{1.0,F32.neg(1.0),0.0}
    case 3: Gradient{F32.neg(1.0),F32.neg(1.0),0.0}
    case 4: Gradient{1.0,0.0,1.0}
    case 5: Gradient{F32.neg(1.0),0.0,1.0}
    case 6: Gradient{1.0,0.0,F32.neg(1.0)}
    case 7: Gradient{F32.neg(1.0),0.0,F32.neg(1.0)}
    case 8: Gradient{0.0,1.0,1.0}
    case 9: Gradient{0.0,F32.neg(1.0),1.0}
    case 10: Gradient{0.0,1.0,F32.neg(1.0)}
    case 11: Gradient{0.0,F32.neg(1.0),F32.neg(1.0)}
    case 12: Gradient{1.0,1.0,0.0}
    case 13: Gradient{0.0,F32.neg(1.0),1.0}
    case 14: Gradient{F32.neg(1.0),1.0,0.0}
    case _: Gradient{0.0,F32.neg(1.0),F32.neg(1.0)}

def gradient_components(gradient:Gradient,x:F32,y:F32,z:F32) -> F32:
  match gradient:
    case Gradient{gx,gy,gz}: F32.add(F32.add(F32.mul(gx,x),F32.mul(gy,y)),F32.mul(gz,z))

def gradient_dot(hash:U32,x:F32,y:F32,z:F32) -> F32:
  gradient_components(gradient_index(U32.and(hash,15)),x,y,z)

# Exact float opcode order from pinned Mth; there is no fused multiply-add.
def smoothstep(+t:F32) -> F32:
  F32.mul(F32.mul(F32.mul(t,t),t),F32.add(F32.mul(t,F32.sub(F32.mul(t,6.0),15.0)),10.0))

def lerp(t:F32,+first:F32,second:F32) -> F32:
  F32.add(first,F32.mul(t,F32.sub(second,first)))

def lerp2(+tx:F32,ty:F32,a:F32,b:F32,c:F32,d:F32) -> F32:
  lerp(ty,lerp(tx,a,b),lerp(tx,c,d))

def lerp3(+tx:F32,+ty:F32,tz:F32,a:F32,b:F32,c:F32,d:F32,e:F32,f:F32,g:F32,h:F32) -> F32:
  lerp(tz,lerp2(tx,ty,a,b,c,d),lerp2(tx,ty,e,f,g,h))

def sample_corners(corners:Corners,+dx:F32,+dy:F32,+dz:F32,fade_y:F32) -> F32:
  Corners{n000,n100,n010,n110,n001,n101,n011,n111} = corners
  lerp3(smoothstep(dx),smoothstep(fade_y),smoothstep(dz),
    gradient_dot(n000,dx,dy,dz),gradient_dot(n100,F32.sub(dx,1.0),dy,dz),
    gradient_dot(n010,dx,F32.sub(dy,1.0),dz),gradient_dot(n110,F32.sub(dx,1.0),F32.sub(dy,1.0),dz),
    gradient_dot(n001,dx,dy,F32.sub(dz,1.0)),gradient_dot(n101,F32.sub(dx,1.0),dy,F32.sub(dz,1.0)),
    gradient_dot(n011,dx,F32.sub(dy,1.0),F32.sub(dz,1.0)),gradient_dot(n111,F32.sub(dx,1.0),F32.sub(dy,1.0),F32.sub(dz,1.0)))

def sample_result(dx:F32,dy:F32,dz:F32,fade_y:F32,result:Array<U32> & Corners) -> Array<U32> & F32:
  (perms,corners) = result
  (perms,sample_corners(corners,dx,dy,dz,fade_y))

def sample_and_lerp(perms:Array<U32>,ix:U32,iy:U32,iz:U32,dx:F32,dy:F32,dz:F32,fade_y:F32) -> Array<U32> & F32:
  sample_result(dx,dy,dz,fade_y,corner_hashes(perms,ix,iy,iz))

# The real scalar get path: wrap before each double offset, floor through Mth,
# then narrow the local fractions to float before gradient/interpolation work.
# Smeared gradient-y and interpolation-y are deliberately separate values.
def get(noise:Noise,+farlands:Bool,x:F.F64,+y:F.F64,z:F.F64) -> Noise & F32:
  match noise:
    case Noise{perms,+offset_x,+offset_y,+offset_z,+mode}:
      +sx = F.add(wrap(x,farlands),offset_x)
      +sy = F.add(wrap(y,farlands),offset_y)
      +sz = F.add(wrap(z,farlands),offset_z)
      +ix = floor_word(sx)
      +iy = floor_word(sy)
      +iz = floor_word(sz)
      +fraction_y = F.sub(sy,F.from_i32(iy))
      paired(Array<U32>,F32,Noise & F32,sample_and_lerp(perms,ix,iy,iz,
        F.to_f32(F.sub(sx,F.from_i32(ix))),F.to_f32(gradient_y(mode,y,fraction_y)),
        F.to_f32(F.sub(sz,F.from_i32(iz))),F.to_f32(fraction_y)),perms => value =>
          (Noise{perms,offset_x,offset_y,offset_z,mode},value))

# PerlinNoise.get(x,z) wraps these two axes before invoking its virtual3D get.
def get2(noise:Noise,+farlands:Bool,x:F.F64,z:F.F64) -> Noise & F32:
  get(noise,farlands,wrap(x,farlands),zero(),wrap(z,farlands))
