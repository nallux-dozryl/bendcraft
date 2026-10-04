import Base
import ./random.bend as R
import ./f64.bend as F
import ./vanilla_entity_fields.bend as V
import ./player_look.bend as PL
import ./core.bend as C
import ./cooking_effect_entities_model.bend as E

def raw(bits:U32) -> F32:
  U32{word} = bits
  F32{word}
def zero() -> F.F64: F.F64{0,0}
def half() -> F.F64: F.F64{1071644672,0}
def two() -> F.F64: F.F64{1073741824,0}
def point(position:C.Position) -> V.Vec3:
  C.Position{d,x,y,z} = position
  V.Vec3{F.from_i32(x),F.from_i32(y),F.from_i32(z)}
def centered(value:V.Vec3) -> V.Vec3:
  V.Vec3{x,y,z} = value
  V.Vec3{F.add(x,half()),F.add(y,half()),F.add(z,half())}
def center(position:C.Position) -> V.Vec3: centered(point(position))
def dimension(position:C.Position) -> String:
  C.Position{d,x,y,z} = position
  d
def offset_sum(sum:F.F64,middle:Bool) -> F.F64:
  match middle:
    case True{}: F.add(sum,F.F64{1069547520,0})
    case False{}: sum
def offset(value:F.F64,origin:F.F64,middle:Bool) -> F.F64:
  offset_sum(F.add(origin,F.mul(value,F.F64{1072168960,0})),middle)
# ITEM width=.25; x/z get width/2, y does not. Coordinates are signed
# integer block positions; Java floor on those exact integers is identity.
def drop_z(x:F.F64,y:F.F64,z:F.F64,result:R.Source & F.F64) -> R.Source & V.Vec3:
  (source,value) = result
  (source,V.Vec3{x,y,offset(value,z,True{})})
def drop_y(x:F.F64,y:F.F64,z:F.F64,result:R.Source & F.F64) -> R.Source & V.Vec3:
  (source,value) = result
  drop_z(x,offset(value,y,False{}),z,R.next_double(source))
def drop_x(origin:V.Vec3,result:R.Source & F.F64) -> R.Source & V.Vec3:
  V.Vec3{x,y,z} = origin
  (source,value) = result
  drop_y(offset(value,x,True{}),y,z,R.next_double(source))
def drop_position(source:R.Source,position:C.Position) -> R.Source & V.Vec3:
  drop_x(point(position),R.next_double(source))
def triangle_second(mean:F.F64,first:F.F64,result:R.Source & F.F64) -> R.Source & F.F64:
  (source,second) = result
  (source,F.add(mean,F.mul(F.F64{1069377231,1229702824},F.sub(first,second))))
def triangle_first(mean:F.F64,result:R.Source & F.F64) -> R.Source & F.F64:
  (source,first) = result
  triangle_second(mean,first,R.next_double(source))
def triangle(source:R.Source,mean:F.F64) -> R.Source & F.F64:
  triangle_first(mean,R.next_double(source))
def velocity_z(x:F.F64,y:F.F64,result:R.Source & F.F64) -> R.Source & V.Vec3:
  (source,z) = result
  (source,V.Vec3{x,y,z})
def velocity_y(x:F.F64,result:R.Source & F.F64) -> R.Source & V.Vec3:
  (source,y) = result
  velocity_z(x,y,triangle(source,zero()))
def velocity_x(result:R.Source & F.F64) -> R.Source & V.Vec3:
  (source,x) = result
  velocity_y(x,triangle(source,F.F64{1070176665,2576980378}))
def drop_velocity(source:R.Source) -> R.Source & V.Vec3:
  velocity_x(triangle(source,zero()))
def uuid_first(value:R.Bits64) -> R.Bits64:
  R.Bits64{hi,lo} = value
  R.Bits64{hi,U32.or(U32.and(lo,4294905855),16384)}
def uuid_second(value:R.Bits64) -> R.Bits64:
  R.Bits64{hi,lo} = value
  R.Bits64{U32.or(U32.and(hi,1073741823),2147483648),lo}
def uuid_last(first:R.Bits64,result:R.Source & R.Bits64) -> R.Source & (R.Bits64 & R.Bits64):
  (source,last) = result
  (source,(uuid_first(first),uuid_second(last)))
def uuid_drawn(result:R.Source & R.Bits64) -> R.Source & (R.Bits64 & R.Bits64):
  (source,first) = result
  uuid_last(first,R.next_long(source))
def uuid(source:R.Source) -> R.Source & (R.Bits64 & R.Bits64):
  uuid_drawn(R.next_long(source))
def constructor_source(+unique:R.Bits64,time:R.Bits64) -> R.Bits64 & R.Source:
  +next = R.bits_mul(unique,R.Bits64{275155412,1419247029})
  (next,R.seeded_legacy(R.bits_xor(next,time)))
def fields_default(position:V.Vec3,velocity:V.Vec3,yaw:F32,prior:V.Fields) -> V.Fields:
  V.Fields{p,v,o,old,look,head,body,fall,ground,air,fire,portal,invulnerable,sync} = prior
  V.Fields{position,velocity,o,old,PL.State{yaw,raw(0),raw(0),raw(0)},head,body,fall,ground,air,fire,portal,invulnerable,sync}
def fields(position:V.Vec3,velocity:V.Vec3,yaw:F32) -> V.Fields:
  fields_default(position,velocity,yaw,V.default_fields())
def base(dimension:String,id:U32,most:R.Bits64,least:R.Bits64,source:R.Source,fields:V.Fields,order:Nat) -> E.Common:
  E.Common{dimension,id,most,least,source,fields,0,True{},False{},True{},order}
def consume_item_last(bob:F32,yaw:F32,result:R.Source & F.F64) -> R.Source & (F32 & F32):
  (source,value) = result
  (source,(bob,yaw))
def consume_item_x(bob:F32,yaw:F32,result:R.Source & F.F64) -> R.Source & (F32 & F32):
  (source,value) = result
  consume_item_last(bob,yaw,R.next_double(source))
def item_yaw(bob:F32,result:R.Source & F32) -> R.Source & (F32 & F32):
  (source,value) = result
  consume_item_x(bob,F32.mul(value,360.0),R.next_double(source))
def item_bob(result:R.Source & F32) -> R.Source & (F32 & F32):
  (source,value) = result
  item_yaw(F32.mul(F32.mul(value,raw(1078530011)),2.0),R.next_float(source))
def item_rotation(source:R.Source) -> R.Source & (F32 & F32):
  item_bob(R.next_float(source))
def orb_horizontal(value:F.F64) -> F.F64:
  F.mul(F.sub(F.mul(value,F.F64{1070176665,2576980378}),F.F64{1069128089,2576980378}),two())
def orb_z(x:F.F64,y:F.F64,yaw:F32,result:R.Source & F.F64) -> R.Source & (V.Vec3 & F32):
  (source,z) = result
  (source,(V.Vec3{x,y,orb_horizontal(z)},yaw))
def orb_y(x:F.F64,yaw:F32,result:R.Source & F.F64) -> R.Source & (V.Vec3 & F32):
  (source,y) = result
  orb_z(x,F.mul(F.mul(y,F.F64{1070176665,2576980378}),two()),yaw,R.next_double(source))
def orb_x(yaw:F32,result:R.Source & F.F64) -> R.Source & (V.Vec3 & F32):
  (source,x) = result
  orb_y(orb_horizontal(x),yaw,R.next_double(source))
def orb_yaw(result:R.Source & F32) -> R.Source & (V.Vec3 & F32):
  (source,yaw) = result
  orb_x(F32.mul(yaw,360.0),R.next_double(source))
def orb_rotation(source:R.Source) -> R.Source & (V.Vec3 & F32):
  orb_yaw(R.next_float(source))
