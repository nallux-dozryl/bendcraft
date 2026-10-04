import Base
import ./worldgen_density_ast.bend as A

def float_bits(bits:U32) -> F32:
  match bits:
    case U32{word}: F32{word}

def clamp(+value:F32,+low:F32,+high:F32) -> F32:
  Bool.pick(F32,F32.is_lt(value,low),low,Bool.pick(F32,F32.is_gt(value,high),high,value))

def unary(operation:A.Unary,+value:F32) -> F32:
  match operation:
    case A.Abs{}: float_bits(U32.and(F32.bits(value),2147483647))
    case A.Square{}: F32.mul(value,value)
    case A.Cube{}: F32.mul(F32.mul(value,value),value)
    case A.HalfNegative{}: Bool.pick(F32,F32.is_gt(value,0.0),value,F32.mul(value,0.5))
    case A.QuarterNegative{}: Bool.pick(F32,F32.is_gt(value,0.0),value,F32.mul(value,0.25))
    case A.Squeeze{}:
      +limited = clamp(value,F32.neg(1.0),1.0)
      F32.sub(F32.div(limited,2.0),F32.div(F32.mul(F32.mul(limited,limited),limited),24.0))
    case A.Negate{}: float_bits(U32.xor(F32.bits(value),2147483648))

