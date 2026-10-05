import Base
import ./item_entity_tick_model.bend as T
import ./cooking_effect_entities_model.bend as E
import ./vanilla_entity_fields.bend as V
import ./f64.bend as F
import ./inventory.bend as I
import ./movement.bend as M
import ./entity_common_tick.bend as CT
import ./geometry.bend as A
import ./random.bend as R
import ./support.bend as S

def zero() -> F.F64: F.F64{0,0}
def vec() -> V.Vec3: V.Vec3{zero(),zero(),zero()}
def mv(v:V.Vec3) -> M.Vec3:
  V.Vec3{x,y,z}=v
  M.Vec3{x,y,z}
def vv(v:M.Vec3) -> V.Vec3:
  M.Vec3{x,y,z}=v
  V.Vec3{x,y,z}
def add(a:V.Vec3,b:V.Vec3) -> V.Vec3: vv(M.Vec3.add(mv(a),mv(b)))
def sub(a:V.Vec3,b:V.Vec3) -> V.Vec3:
  V.Vec3{x,y,z}=a
  V.Vec3{a,b,c}=b
  V.Vec3{F.sub(x,a),F.sub(y,b),F.sub(z,c)}
def scale(v:V.Vec3,+x:F.F64,+y:F.F64,+z:F.F64) -> V.Vec3:
  V.Vec3{a,b,c}=v
  V.Vec3{F.mul(a,x),F.mul(b,y),F.mul(c,z)}
def length(v:V.Vec3) -> F.F64: M.Vec3.length_squared(mv(v))
def normal_div(v:V.Vec3,+length:F.F64) -> V.Vec3:
  V.Vec3{+x,+y,+z}=v
  V.Vec3{F.div(x,length),F.div(y,length),F.div(z,length)}
def normal_gate(+v:V.Vec3,+length:F.F64,small:Bool) -> V.Vec3:
  match small:
    case True{}: vec()
    case False{}: normal_div(v,length)
def normal(+v:V.Vec3) -> V.Vec3:
  +n=F.sqrt(length(v))
  normal_gate(v,n,F.is_lt(n,F.from_f32(0.00001)))
def signed_lt(a:U32,b:U32) -> Bool: U32.is_lt(U32.xor(a,2147483648),U32.xor(b,2147483648))
def positive(+v:U32) -> Bool: U32.is_gt(v,0) && U32.is_lt(v,2147483648)
def decrement(v:U32) -> U32: CT.decrement(v)
def select(~A:Data,a:A,b:A,c:Bool) -> A:
  match c:
    case True{}: a
    case False{}: b
def common_fields(c:E.Common) -> V.Fields:
  E.Common{d,id,a,b,r,f,t,first,removed,accessible,order}=c
  f
def fields(r:E.Record) -> V.Fields: common_fields(E.common(r))
def pos_fields(fields:V.Fields) -> V.Vec3:
  V.Fields{p,v,o,old,l,h,b,fall,g,a,f,portal,i,s}=fields
  p
def pos(r:E.Record) -> V.Vec3: pos_fields(fields(r))
def velocity_fields(fields:V.Fields) -> V.Vec3:
  V.Fields{p,v,o,old,l,h,b,fall,g,a,f,portal,i,s}=fields
  v
def velocity(r:E.Record) -> V.Vec3: velocity_fields(fields(r))
def ground_fields(fields:V.Fields) -> Bool:
  V.Fields{p,v,o,old,l,h,b,fall,g,a,f,portal,i,s}=fields
  g
def ground(r:E.Record) -> Bool: ground_fields(fields(r))
def removed_common(c:E.Common) -> Bool:
  E.Common{d,id,a,b,r,f,t,first,removed,accessible,order}=c
  removed
def removed(r:E.Record) -> Bool: removed_common(E.common(r))
def tick_count_common(c:E.Common) -> U32:
  E.Common{d,id,a,b,r,f,t,first,removed,accessible,order}=c
  t
def tick_count(r:E.Record) -> U32: tick_count_common(E.common(r))
def with_fields(c:E.Common,f:V.Fields) -> E.Common:
  E.Common{d,id,a,b,r,old,t,first,removed,accessible,order}=c
  E.Common{d,id,a,b,r,f,t,first,removed,accessible,order}
def with_common(record:E.Record,c:E.Common) -> E.Record:
  match record:
    case E.Item{old,item,age,delay,h,thrower,target,bob}: E.Item{c,item,age,delay,h,thrower,target,bob}
    case E.Orb{old,v,age,h,n,following}: E.Orb{c,v,age,h,n,following}
def set_fields(+record:E.Record,f:V.Fields) -> E.Record: with_common(record,with_fields(E.common(record),f))
def set_velocity_fields(f:V.Fields,v:V.Vec3) -> V.Fields:
  V.Fields{p,old,o,oo,l,h,b,fall,g,a,fire,portal,i,s}=f
  V.Fields{p,v,o,oo,l,h,b,fall,g,a,fire,portal,i,s}
def set_velocity(+r:E.Record,v:V.Vec3) -> E.Record: set_fields(r,set_velocity_fields(fields(r),v))
def set_position_fields(f:V.Fields,p:V.Vec3) -> V.Fields:
  V.Fields{old,v,o,oo,l,h,b,fall,g,a,fire,portal,i,s}=f
  V.Fields{p,v,o,oo,l,h,b,fall,g,a,fire,portal,i,s}
def set_position(+r:E.Record,p:V.Vec3) -> E.Record: set_fields(r,set_position_fields(fields(r),p))
def common_removed(c:E.Common) -> E.Common:
  E.Common{d,id,a,b,r,f,t,first,old,accessible,order}=c
  E.Common{d,id,a,b,r,f,t,first,True{},accessible,order}
def discard(+r:E.Record) -> E.Record: with_common(r,common_removed(E.common(r)))
def source(r:E.Record) -> E.Common:
  E.common(r)
def set_random(c:E.Common,r:R.Source) -> E.Common:
  E.Common{d,id,a,b,old,f,t,first,removed,accessible,order}=c
  E.Common{d,id,a,b,r,f,t,first,removed,accessible,order}
def body(r:E.Record) -> A.AABB:
  M.make_box(mv(pos(r)),0.25,0.25)
def slot(r:E.Record) -> I.Slot:
  match r:
    case E.Item{c,i,a,d,h,t,target,b}: i
    case _: I.InvEmpty{}
def empty(slot:I.Slot) -> Bool:
  match slot:
    case I.InvEmpty{}: True{}
    case I.InvStack{I.ItemKey{id,components},count}: Bool.not(positive(count)) || String.eq(id,"minecraft:air")
def guard(v:Bool,message:String) -> Result<&2,&2,T.Error,Unit>:
  match v:
    case True{}: Done{Unit{}}
    case False{}: Fail{T.Refused{message}}
def string_result(~A:Data,r:Result<&2,&2,String,A>) -> Result<&2,&2,T.Error,A>:
  match r:
    case Done{v}: Done{v}
    case Fail{s}: Fail{T.Refused{s}}

# Only a fresh constructor receiver has these exact defaults. Restore must load
# or reconstruct the runtime explicitly instead of calling this constructor.
def fresh_runtime() -> T.Runtime:
  T.Runtime{T.Physical{False{},False{},False{},False{},False{},False{},False{},vec()},
    T.BaseState{0,0,False{},False{},False{},False{},False{},False{},False{},False{},None{},vec()},
    T.Fluids{T.Fluid{zero(),vec(),0,False{}},T.Fluid{zero(),vec(),0,False{}},False{},False{},False{}},[],[],S.empty(),[]}
