import Base
import ./worldgen_density_ast.bend as A
import ./f64.bend as F

type Coordinates is Data:
  Coordinates{x:F.F64,y:F.F64,z:F.F64}

# NoiseFunction's input arithmetic is binary64. Integer block positions are
# widened before multiplication, and each actual density shift is widened from
# its binary32 sample before addition. There is no intermediate float cast.
def shifted(x:U32,y:U32,z:U32,+xz_scale:F.F64,y_scale:F.F64,sx:F32,sy:F32,sz:F32,mode:A.NoiseMode) -> Coordinates:
  match mode:
    case A.Plain{}: Coordinates{F.mul(F.from_i32(x),xz_scale),F.mul(F.from_i32(y),y_scale),F.mul(F.from_i32(z),xz_scale)}
    case A.ShiftedXZ{}: Coordinates{F.add(F.mul(F.from_i32(x),xz_scale),F.from_f32(sx)),F.mul(F.from_i32(y),y_scale),F.add(F.mul(F.from_i32(z),xz_scale),F.from_f32(sz))}
    case A.ShiftedXYZ{}: Coordinates{F.add(F.mul(F.from_i32(x),xz_scale),F.from_f32(sx)),F.add(F.mul(F.from_i32(y),y_scale),F.from_f32(sy)),F.add(F.mul(F.from_i32(z),xz_scale),F.from_f32(sz))}
