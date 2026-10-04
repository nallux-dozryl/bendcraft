import Base
import ./crafting_recipe.bend as R

# Signed Java integers cross the public boundary as two's-complement U32 bits.
# Conversions never cast negative/out-of-range floats to unsigned C integers.
def signed_float(+bits:U32) -> F32:
  R.choose(F32,U32.to_f32(bits),F32.neg(U32.to_f32(U32.sub(0,bits))),U32.is_lt(bits,2147483648))

def cast_sign(value:F32,negative:Bool) -> U32:
  match negative:
    case False{}: F32.to_u32(value)
    case True{}: U32.sub(0,F32.to_u32(F32.neg(value)))

def cast_finite(+value:F32) -> U32:
  cast_sign(value,F32.is_lt(value,0.0))

def cast_range(+value:F32,low:Bool,high:Bool) -> U32:
  match low high:
    case True{} _: 2147483648
    case _ True{}: 2147483647
    case _ _: cast_finite(value)

def cast_number(value:F32,valid:Bool) -> U32:
  match valid:
    case False{}: 0
    case True{}:
      +number = value
      cast_range(number,F32.is_le(number,F32.neg(2147483648.0)),F32.is_ge(number,2147483648.0))

def java_int(+value:F32) -> U32:
  cast_number(value,F32.is_eq(value,value))

# Mth.floor(float) is Math.floor((double)value), then Java's saturating int cast.
def floor(value:F32) -> U32:
  java_int(F32.floor(value))

def total_time_checked(base:U32,speed:F32,positive:Bool) -> U32:
  match positive:
    case False{}: base
    case True{}: java_int(F32.ceil(F32.div(signed_float(base),speed)))

def total_time(base:U32,+speed:F32) -> U32:
  total_time_checked(base,speed,F32.is_gt(speed,0.0))

# createExperience uses float multiplication and the server RandomSource's
# nextFloat(), not a double-valued random ticket. Caller owns the RNG advance.
def award_product(+product:F32,+ticket:F32) -> U32:
  +whole = floor(product)
  +fraction = F32.sub(product,signed_float(whole))
  R.choose(U32,U32.add(whole,1),whole,F32.is_ne(fraction,0.0) && F32.is_lt(ticket,fraction))

def experience(uses:U32,rate:F32,ticket:F32) -> U32:
  award_product(F32.mul(signed_float(uses),rate),ticket)

def fraction(+uses:U32,+rate:F32) -> F32:
  +product = F32.mul(signed_float(uses),rate)
  F32.sub(product,signed_float(floor(product)))
