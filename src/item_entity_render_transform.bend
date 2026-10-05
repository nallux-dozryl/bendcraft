import Base
import ./f64.bend as F
import ./random.bend as R
import ./vanilla_entity_fields.bend as V
import ./block_model.bend as B
import ./block_bake.bend as K
import ./mesh_render.bend as M

def signed(value:U32) -> F32: F.to_f32(F.from_i32(value))
def age(ticks:U32,partial:F32) -> F32: F32.add(signed(ticks),partial)
def spin(age:F32,bob:F32) -> F32: F32.add(F32.div(age,20.0),bob)
def hover(min_y:F32,sine:F32) -> F32:
  F32.add(F32.add(F32.mul(sine,0.1),0.1),F32.add(F32.neg(min_y),0.0625))
def count_small(+value:U32,first:Bool) -> U32:
  match first:
    case True{}: 1
    case False{}: U32.add(2,U32.add(Bool.to_u32(U32.is_gt(value,16)),U32.add(Bool.to_u32(U32.is_gt(value,32)),Bool.to_u32(U32.is_gt(value,48)))))
def copies(+count:U32) -> U32:
  count_small(count,U32.is_le(count,1) || U32.is_ge(count,2147483648))
def icon_unsigned(+value:U32) -> U32:
  U32.add(U32.add(U32.add(Bool.to_u32(U32.is_ge(value,3)),Bool.to_u32(U32.is_ge(value,7))),U32.add(Bool.to_u32(U32.is_ge(value,17)),Bool.to_u32(U32.is_ge(value,37)))),U32.add(U32.add(Bool.to_u32(U32.is_ge(value,73)),Bool.to_u32(U32.is_ge(value,149))),U32.add(U32.add(Bool.to_u32(U32.is_ge(value,307)),Bool.to_u32(U32.is_ge(value,617))),U32.add(Bool.to_u32(U32.is_ge(value,1237)),Bool.to_u32(U32.is_ge(value,2477))))))
def icon_signed(negative:Bool,value:U32) -> U32:
  match negative:
    case True{}: 0
    case False{}: icon_unsigned(value)
def icon(+value:U32) -> U32: icon_signed(U32.is_ge(value,2147483648),value)
def lerp(+partial:F.F64,+old:F.F64,current:F.F64) -> F.F64:
  F.add(old,F.mul(partial,F.sub(current,old)))
def relative(old:V.Vec3,current:V.Vec3,camera:V.Vec3,+partial:F32) -> M.Vec3:
  match old current camera:
    case V.Vec3{x,y,z} V.Vec3{xx,yy,zz} V.Vec3{cx,cy,cz}:
      M.Vec3{F.to_f32(F.sub(lerp(F.from_f32(partial),x,xx),cx)),F.to_f32(F.sub(lerp(F.from_f32(partial),y,yy),cy)),F.to_f32(F.sub(lerp(F.from_f32(partial),z,zz),cz))}
def scalar_offset(value:F32) -> F32:
  F32.mul(F32.sub(F32.mul(value,2.0),1.0),0.15)
def random_z(x:F32,y:F32,pair:R.Source & F32) -> R.Source & M.Vec3:
  (source,z) = pair
  (source,M.Vec3{x,y,scalar_offset(z)})
def random_y(x:F32,pair:R.Source & F32) -> R.Source & M.Vec3:
  (source,y) = pair
  random_z(x,scalar_offset(y),R.next_float(source))
def random_x(pair:R.Source & F32) -> R.Source & M.Vec3:
  (source,x) = pair
  random_y(scalar_offset(x),R.next_float(source))
def volume_random(source:R.Source) -> R.Source & M.Vec3:
  random_x(R.next_float(source))
def flat_y(z:F32,x:F32,pair:R.Source & F32) -> R.Source & M.Vec3:
  (source,y) = pair
  (source,M.Vec3{x,F32.mul(scalar_offset(y),0.5),z})
def flat_x(z:F32,pair:R.Source & F32) -> R.Source & M.Vec3:
  (source,x) = pair
  flat_y(z,F32.mul(scalar_offset(x),0.5),R.next_float(source))
def flat_random(source:R.Source,z:F32) -> R.Source & M.Vec3:
  flat_x(z,R.next_float(source))
def copied(head:M.Vec3,rest:List<&2,M.Vec3>) -> List<&2,M.Vec3>: head <> rest
def offset_next(+z:F32,step:F32,pair:R.Source & M.Vec3,
    next:R.Source -> F32 -> List<&2,M.Vec3>) -> List<&2,M.Vec3>:
  (source,head) = pair
  copied(head,next(source)(F32.add(z,step)))
def offset_choice(flat:Bool,source:R.Source,z:F32) -> R.Source & M.Vec3:
  match flat:
    case False{}: volume_random(source)
    case True{}: flat_random(source,z)
def offset_tail(n:Nat,source:R.Source,+z:F32,+step:F32,+flat:Bool) -> List<&2,M.Vec3>:
  match n:
    case 0n: []
    case 1n+rest: offset_next(z,step,offset_choice(flat,source,z),source => next_z => offset_tail(rest,source,next_z,step,flat))
def offsets_chosen(flat:Bool,seed:U32,+count:U32,depth:F32) -> List<&2,M.Vec3>:
  match flat:
    case False{}: M.Vec3{0.0,0.0,0.0} <> offset_tail(U32.to_nat(U32.sub(count,1)),R.seeded_legacy(R.sign_extend(seed)),0.0,0.0,False{})
    case True{}:
      +step = F32.mul(depth,1.5)
      +start = F32.neg(F32.div(F32.mul(step,signed(U32.sub(count,1))),2.0))
      M.Vec3{0.0,0.0,start} <> offset_tail(U32.to_nat(U32.sub(count,1)),R.seeded_legacy(R.sign_extend(seed)),F32.add(start,step),step,True{})
def offsets(seed:U32,count:U32,+depth:F32) -> List<&2,M.Vec3>:
  offsets_chosen(F32.is_le(depth,0.0625),seed,count,depth)
def vec(a:M.Vec3) -> B.Vec3:
  M.Vec3{x,y,z} = a
  B.Vec3{x,y,z}
def moved(point:M.Vec3,+matrix:K.Mat,offset:M.Vec3,origin:M.Vec3) -> M.Vec3:
  K.mesh_vec(K.add(K.transform(matrix,K.add(vec(point),vec(offset))),vec(origin)))
def vertex(value:M.Vertex,matrix:K.Mat,offset:M.Vec3,origin:M.Vec3) -> M.Vertex:
  M.Vertex{position,uv} = value
  M.Vertex{moved(position,matrix,offset,origin),uv}
def material(value:M.Material,light:U32) -> M.Material:
  M.Material{texture,tint,old,shade,mode,address} = value
  M.Material{texture,tint,light,shade,mode,address}
def quad(value:M.Quad,+matrix:K.Mat,+offset:M.Vec3,+origin:M.Vec3,light:U32) -> M.Quad:
  M.Quad{a,b,c,d,m,cull,order} = value
  M.Quad{vertex(a,matrix,offset,origin),vertex(b,matrix,offset,origin),vertex(c,matrix,offset,origin),vertex(d,matrix,offset,origin),material(m,light),cull,order}
def mesh(values:List<&2,M.Quad>,+matrix:K.Mat,+offset:M.Vec3,+origin:M.Vec3,+light:U32) -> List<&2,M.Quad>:
  match values:
    case Nil{}: []
    case head <> rest: quad(head,matrix,offset,origin,light) <> mesh(rest,matrix,offset,origin,light)
def clustered(offsets:List<&2,M.Vec3>,+values:List<&2,M.Quad>,+matrix:K.Mat,+origin:M.Vec3,+light:U32) -> List<&2,M.Quad>:
  match offsets:
    case Nil{}: []
    case offset <> rest: List.append(&2,M.Quad,mesh(values,matrix,offset,origin,light),clustered(rest,values,matrix,origin,light))
