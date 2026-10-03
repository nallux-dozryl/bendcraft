import Base
import ./block_model.bend as B
import ./mesh_render.bend as M
import ./json.bend as J

# Pure CPU geometry. Sprite layout/classification and lighting are explicit inputs.
type Error is Data:
  Unsupported{code:String}
  Invalid{code:String}
  MissingMaterial{reference:String}

type State is Data:
  State{x:U32,y:U32,z:U32,uvlock:Bool}
type Layer is Data:
  Solid{}
  Cutout{}
  Translucent{}
type Sprite is Data:
  Sprite{slot:U32,u0:F32,v0:F32,u1:F32,v1:F32,layer:Layer,animated:Bool}
type Context is Data:
  Context{sprites:Map<&2,Sprite>,missing:Maybe<&2,Sprite>}
type Baked is Data:
  Baked{a:M.Vertex,b:M.Vertex,c:M.Vertex,d:M.Vertex,direction:B.Direction,
    cullface:Maybe<&2,B.Direction>,sprite:String,texture:U32,tint_index:U32,
    light_emission:U32,shade_override:Maybe<&2,B.Direction>,layer:Layer,
    force_translucent:Bool,animated:Bool,default_shade:F32,nether_shade:F32}
type Appearance is Data:
  Appearance{tint:U32,light:U32,address:M.Address,cull:M.Cull,nether:Bool,cutout_threshold:U32}
type Mat is Data:
  Mat{a:B.Vec3,b:B.Vec3,c:B.Vec3,identity:Bool}
type Four is Data:
  Four{a:M.Vertex,b:M.Vertex,c:M.Vertex,d:M.Vertex}
type MaterialInput is Data:
  MaterialInput{sprite:Sprite,name:String,force:Bool}
type Trig is Data:
  Trig{sin:F32,cos:F32}
type Prepared is Data:
  Prepared{matrix:Mat,origin:B.Vec3,present:Bool}

def raw(n:U32) -> F32:
  match n:
    case U32{word}: F32{word}

def identity() -> Mat:
  Mat{B.Vec3{1.0,0.0,0.0},B.Vec3{0.0,1.0,0.0},B.Vec3{0.0,0.0,1.0},True{}}

def finite(+f:F32) -> Bool:
  U32.is_ne(U32.and(F32.bits(f),2139095040),2139095040)

def vec_finite(v:B.Vec3) -> Bool:
  B.Vec3{x,y,z} = v
  finite(x) && finite(y) && finite(z)

def vec_eq(a:B.Vec3,b:B.Vec3) -> Bool:
  match a b:
    case B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: F32.is_eq(x,xx) && F32.is_eq(y,yy) && F32.is_eq(z,zz)

def mat_identity(m:Mat) -> Bool:
  Mat{a,b,c,i} = m
  vec_eq(a,B.Vec3{1.0,0.0,0.0}) && vec_eq(b,B.Vec3{0.0,1.0,0.0}) && vec_eq(c,B.Vec3{0.0,0.0,1.0})

def add(a:B.Vec3,b:B.Vec3) -> B.Vec3:
  match a b:
    case B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{F32.add(x,xx),F32.add(y,yy),F32.add(z,zz)}
def sub(a:B.Vec3,b:B.Vec3) -> B.Vec3:
  match a b:
    case B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{F32.sub(x,xx),F32.sub(y,yy),F32.sub(z,zz)}
def scale(v:B.Vec3,+factor:F32) -> B.Vec3:
  B.Vec3{x,y,z} = v
  B.Vec3{F32.mul(x,factor),F32.mul(y,factor),F32.mul(z,factor)}

# JOML Math.fma uses separate multiply/add for the pinned default configuration.
def ma(a:F32,b:F32,c:F32) -> F32:
  F32.add(F32.mul(a,b),c)
def dot(a:B.Vec3,b:B.Vec3) -> F32:
  match a b:
    case B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: ma(x,xx,ma(y,yy,F32.mul(z,zz)))
def position_dot(a:B.Vec3,b:B.Vec3) -> F32:
  match a b:
    case B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: ma(x,xx,ma(y,yy,ma(z,zz,0.0)))
def transform(m:Mat,+v:B.Vec3) -> B.Vec3:
  Mat{a,b,c,i} = m
  J.choose(B.Vec3,v,B.Vec3{position_dot(a,v),position_dot(b,v),position_dot(c,v)},i)
def columns(m:Mat) -> Mat:
  Mat{B.Vec3{a,b,c},B.Vec3{d,e,f},B.Vec3{g,h,i},flag} = m
  Mat{B.Vec3{a,d,g},B.Vec3{b,e,h},B.Vec3{c,f,i},flag}
def multiply_columns(+a:Mat,b:Mat) -> Mat:
  Mat{+x,+y,+z,ai} = a
  Mat{+c0,+c1,+c2,bi} = b
  Mat{B.Vec3{dot(x,c0),dot(x,c1),dot(x,c2)},B.Vec3{dot(y,c0),dot(y,c1),dot(y,c2)},B.Vec3{dot(z,c0),dot(z,c1),dot(z,c2)},False{}}
def multiply_rows(a:Mat,b:Mat) -> Mat:
  multiply_columns(a,columns(b))
def multiply(+a:Mat,+b:Mat) -> Mat:
  Mat{x,y,z,+ai} = a
  Mat{xx,yy,zz,+bi} = b
  J.choose(Mat,b,J.choose(Mat,a,multiply_rows(a,b),bi),ai)

def inverse(m:Mat) -> Mat:
  Mat{B.Vec3{+a,+d,+g},B.Vec3{+b,+e,+h},B.Vec3{+c,+f,+i},flag} = m
  +ae = F32.mul(a,e)
  +bd = F32.mul(b,d)
  +cd = F32.mul(c,d)
  +af = F32.mul(a,f)
  +bf = F32.mul(b,f)
  +ce = F32.mul(c,e)
  +det = F32.add(F32.add(F32.mul(F32.sub(ae,bd),i),F32.mul(F32.sub(cd,af),h)),F32.mul(F32.sub(bf,ce),g))
  +r = F32.div(1.0,det)
  Mat{B.Vec3{F32.mul(F32.sub(F32.mul(e,i),F32.mul(f,h)),r),F32.mul(F32.sub(F32.mul(f,g),F32.mul(d,i)),r),F32.mul(F32.sub(F32.mul(d,h),F32.mul(e,g)),r)},
    B.Vec3{F32.mul(F32.sub(F32.mul(h,c),F32.mul(i,b)),r),F32.mul(F32.sub(F32.mul(i,a),F32.mul(g,c)),r),F32.mul(F32.sub(F32.mul(g,b),F32.mul(h,a)),r)},
    B.Vec3{F32.mul(F32.sub(bf,ce),r),F32.mul(F32.sub(cd,af),r),F32.mul(F32.sub(ae,bd),r)},False{}}

# Actual Matrix4f.rotation(Quaternionfc) operation order, including signed zeros.
def quaternion(+x:F32,+y:F32,+z:F32,+w:F32) -> Mat:
  +ww = F32.mul(w,w)
  +xx = F32.mul(x,x)
  +yy = F32.mul(y,y)
  +zz = F32.mul(z,z)
  +zw = F32.mul(z,w)
  +xy = F32.mul(x,y)
  +xz = F32.mul(x,z)
  +yw = F32.mul(y,w)
  +yz = F32.mul(y,z)
  +xw = F32.mul(x,w)
  +dzw = F32.add(zw,zw)
  +dxy = F32.add(xy,xy)
  +dxz = F32.add(xz,xz)
  +dyw = F32.add(yw,yw)
  +dyz = F32.add(yz,yz)
  +dxw = F32.add(xw,xw)
  Mat{B.Vec3{F32.sub(F32.sub(F32.add(ww,xx),zz),yy),F32.add(F32.neg(dzw),dxy),F32.add(dyw,dxz)},
    B.Vec3{F32.add(dxy,dzw),F32.sub(F32.add(F32.sub(yy,zz),ww),xx),F32.sub(dyz,dxw)},
    B.Vec3{F32.sub(dxz,dyw),F32.add(dyz,dxw),F32.add(F32.sub(F32.sub(zz,yy),xx),ww)},False{}}

# Fixed scalar result of pinned Quaternionf.rotateX/Y(+/-PI/2); not baked quads.
def face_basis(d:B.Direction) -> Mat:
  match d:
    case B.South{}: identity()
    case B.North{}: quaternion(raw(2147483648),1.0,0.0,raw(2147483648))
    case B.East{}: quaternion(0.0,raw(1060439283),0.0,raw(1060439283))
    case B.West{}: quaternion(0.0,F32.neg(raw(1060439283)),0.0,raw(1060439283))
    case B.Up{}: quaternion(F32.neg(raw(1060439283)),0.0,raw(2147483648),raw(1060439283))
    case B.Down{}: quaternion(raw(1060439283),0.0,0.0,raw(1060439283))

def axis_once(a:B.Axis,v:B.Vec3) -> B.Vec3:
  match a v:
    case B.X{} B.Vec3{x,y,z}: B.Vec3{x,z,F32.neg(y)}
    case B.Y{} B.Vec3{x,y,z}: B.Vec3{F32.neg(z),y,x}
    case B.Z{} B.Vec3{x,y,z}: B.Vec3{y,F32.neg(x),z}
def turns(n:Nat,+a:B.Axis,v:B.Vec3) -> B.Vec3:
  match n:
    case 0n: v
    case 1n+p: turns(p,a,axis_once(a,v))
def state_vector(state:State,v:B.Vec3) -> B.Vec3:
  State{x,y,z,lock} = state
  turns(U32.to_nat(U32.div(z,90)),B.Z{},turns(U32.to_nat(U32.div(y,90)),B.Y{},turns(U32.to_nat(U32.div(x,90)),B.X{},v)))
def positive_zero(+f:F32) -> F32:
  J.choose(F32,0.0,f,F32.is_eq(f,0.0))
def zeros(v:B.Vec3) -> B.Vec3:
  B.Vec3{x,y,z} = v
  B.Vec3{positive_zero(x),positive_zero(y),positive_zero(z)}
def identity_flag(+m:Mat) -> Mat:
  Mat{a,b,c,i} = m
  Mat{a,b,c,mat_identity(m)}
def state_matrix(+state:State) -> Mat:
  identity_flag(columns(Mat{zeros(state_vector(state,B.Vec3{1.0,0.0,0.0})),zeros(state_vector(state,B.Vec3{0.0,1.0,0.0})),zeros(state_vector(state,B.Vec3{0.0,0.0,1.0})),False{}}))
def direction_eq(a:B.Direction,b:B.Direction) -> Bool:
  match a b:
    case B.Down{} B.Down{}: True{}
    case B.Up{} B.Up{}: True{}
    case B.North{} B.North{}: True{}
    case B.South{} B.South{}: True{}
    case B.West{} B.West{}: True{}
    case B.East{} B.East{}: True{}
    case _ _: False{}
def direction_vector(d:B.Direction) -> B.Vec3:
  match d:
    case B.Down{}: B.Vec3{0.0,F32.neg(1.0),0.0}
    case B.Up{}: B.Vec3{0.0,1.0,0.0}
    case B.North{}: B.Vec3{0.0,0.0,F32.neg(1.0)}
    case B.South{}: B.Vec3{0.0,0.0,1.0}
    case B.West{}: B.Vec3{F32.neg(1.0),0.0,0.0}
    case B.East{}: B.Vec3{1.0,0.0,0.0}
def nearest(v:B.Vec3) -> B.Direction:
  B.Vec3{+x,+y,+z} = v
  J.choose(B.Direction,J.choose(B.Direction,B.Down{},B.Up{},F32.is_lt(y,0.0)),J.choose(B.Direction,J.choose(B.Direction,B.North{},B.South{},F32.is_lt(z,0.0)),J.choose(B.Direction,B.West{},B.East{},F32.is_lt(x,0.0)),F32.is_ge(F32.abs(z),F32.abs(x))),F32.is_ge(F32.abs(y),F32.abs(x)) && F32.is_ge(F32.abs(y),F32.abs(z)))
def rotate_direction(state:State,d:B.Direction) -> B.Direction:
  nearest(state_vector(state,direction_vector(d)))
def cull(state:State,d:Maybe<&2,B.Direction>) -> Maybe<&2,B.Direction>:
  match d:
    case None{}: None{}
    case Some{x}: Some{rotate_direction(state,x)}
def inverse_face_matrix(+m:Mat,d:B.Direction,lock:Bool) -> Mat:
  Mat{a,b,c,+i} = m
  +global = multiply(m,face_basis(d))
  +facing = nearest(transform(global,B.Vec3{0.0,0.0,1.0}))
  J.choose(Mat,identity(),inverse(multiply(J.choose(Mat,identity(),inverse(face_basis(facing)),direction_eq(facing,B.South{})),global)),Bool.not(lock) || i)
def inverse_face(+state:State,d:B.Direction) -> Mat:
  State{x,y,z,lock} = state
  inverse_face_matrix(state_matrix(state),d,lock)

def default_uv(d:B.Direction,from:B.Vec3,to:B.Vec3) -> B.UV:
  match d from to:
    case B.Down{} B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.UV{x,F32.sub(16.0,zz),xx,F32.sub(16.0,z)}
    case B.Up{} B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.UV{x,z,xx,zz}
    case B.North{} B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.UV{F32.sub(16.0,xx),F32.sub(16.0,yy),F32.sub(16.0,x),F32.sub(16.0,y)}
    case B.South{} B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.UV{x,F32.sub(16.0,yy),xx,F32.sub(16.0,y)}
    case B.West{} B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.UV{z,F32.sub(16.0,yy),zz,F32.sub(16.0,y)}
    case B.East{} B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.UV{F32.sub(16.0,zz),F32.sub(16.0,yy),F32.sub(16.0,z),F32.sub(16.0,y)}
def face_uv(value:Maybe<&2,B.UV>,d:B.Direction,from:B.Vec3,to:B.Vec3) -> B.UV:
  match value:
    case Some{v}: v
    case None{}: default_uv(d,from,to)
def uv_corner(uv:B.UV,index:U32) -> M.UV:
  match uv index:
    case B.UV{u,v,uu,vv} 0: M.UV{F32.div(u,16.0),F32.div(v,16.0)}
    case B.UV{u,v,uu,vv} 1: M.UV{F32.div(u,16.0),F32.div(vv,16.0)}
    case B.UV{u,v,uu,vv} 2: M.UV{F32.div(uu,16.0),F32.div(vv,16.0)}
    case B.UV{u,v,uu,vv} _: M.UV{F32.div(uu,16.0),F32.div(v,16.0)}
def mapped_coords(result:B.Vec3,uv:M.UV,i:Bool) -> M.UV:
  B.Vec3{x,y,z} = result
  J.choose(M.UV,uv,M.UV{F32.add(x,0.5),F32.add(y,0.5)},i)
def mapped_uv(matrix:Mat,+uv:M.UV) -> M.UV:
  Mat{a,b,c,+i} = matrix
  M.UV{+u,+v} = uv
  mapped_coords(transform(matrix,B.Vec3{F32.sub(u,0.5),F32.sub(v,0.5),0.0}),uv,i)
def atlas_uv(uv:M.UV,sprite:Sprite) -> M.UV:
  match uv sprite:
    case M.UV{u,v} Sprite{slot,+u0,+v0,u1,v1,layer,animated}: M.UV{F32.add(u0,F32.mul(F32.sub(u1,u0),u)),F32.add(v0,F32.mul(F32.sub(v1,v0),v))}

def corner(d:B.Direction,index:U32,from:B.Vec3,to:B.Vec3) -> B.Vec3:
  match d index from to:
    case B.Down{} 0 B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{x,y,zz}
    case B.Down{} 1 B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{x,y,z}
    case B.Down{} 2 B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{xx,y,z}
    case B.Down{} _ B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{xx,y,zz}
    case B.Up{} 0 B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{x,yy,z}
    case B.Up{} 1 B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{x,yy,zz}
    case B.Up{} 2 B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{xx,yy,zz}
    case B.Up{} _ B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{xx,yy,z}
    case B.North{} 0 B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{xx,yy,z}
    case B.North{} 1 B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{xx,y,z}
    case B.North{} 2 B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{x,y,z}
    case B.North{} _ B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{x,yy,z}
    case B.South{} 0 B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{x,yy,zz}
    case B.South{} 1 B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{x,y,zz}
    case B.South{} 2 B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{xx,y,zz}
    case B.South{} _ B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{xx,yy,zz}
    case B.West{} 0 B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{x,yy,z}
    case B.West{} 1 B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{x,y,z}
    case B.West{} 2 B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{x,y,zz}
    case B.West{} _ B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{x,yy,zz}
    case B.East{} 0 B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{xx,yy,zz}
    case B.East{} 1 B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{xx,y,zz}
    case B.East{} 2 B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{xx,y,z}
    case B.East{} _ B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{xx,yy,z}

def rotated(+p:B.Vec3,rotation:Prepared) -> B.Vec3:
  Prepared{m,+o,present} = rotation
  J.choose(B.Vec3,add(transform(m,sub(p,o)),o),p,present)
def centered(+p:B.Vec3,m:Mat) -> B.Vec3:
  Mat{a,b,c,+i} = m
  J.choose(B.Vec3,p,add(transform(m,sub(p,B.Vec3{0.5,0.5,0.5})),B.Vec3{0.5,0.5,0.5}),i)
def mesh_vec(v:B.Vec3) -> M.Vec3:
  B.Vec3{x,y,z} = v
  M.Vec3{x,y,z}
def block_vec(v:M.Vec3) -> B.Vec3:
  M.Vec3{x,y,z} = v
  B.Vec3{x,y,z}
def vertex_finite(v:M.Vertex) -> Bool:
  M.Vertex{p,M.UV{u,v}} = v
  vec_finite(block_vec(p)) && finite(u) && finite(v)
def four_checked(+f:Four,valid:Bool) -> Result<&2,&2,Error,Four>:
  match valid:
    case True{}: Done{f}
    case False{}: Fail{Invalid{"NonFiniteBakedVertex"}}
def four_finite(f:Four) -> Bool:
  Four{a,b,c,d} = f
  vertex_finite(a) && vertex_finite(b) && vertex_finite(c) && vertex_finite(d)
def vertex(+index:U32,d:B.Direction,from:B.Vec3,to:B.Vec3,uv:B.UV,turn:U32,state_matrix:Mat,face_matrix:Mat,rot:Prepared,sprite:Sprite) -> M.Vertex:
  M.Vertex{mesh_vec(centered(rotated(B.vec_div(corner(d,index,from,to),16.0),rot),state_matrix)),atlas_uv(mapped_uv(face_matrix,uv_corner(uv,U32.mod(U32.add(index,U32.div(turn,90)),4))),sprite)}
def at(f:Four,index:U32) -> M.Vertex:
  match f index:
    case Four{a,b,c,d} 0: a
    case Four{a,b,c,d} 1: b
    case Four{a,b,c,d} 2: c
    case Four{a,b,c,d} _: d
def vertex_position(v:M.Vertex) -> B.Vec3:
  M.Vertex{p,uv} = v
  block_vec(p)
def cross(a:B.Vec3,b:B.Vec3) -> B.Vec3:
  match a b:
    case B.Vec3{+x,+y,+z} B.Vec3{+xx,+yy,+zz}: B.Vec3{F32.sub(F32.mul(y,zz),F32.mul(z,yy)),F32.sub(F32.mul(z,xx),F32.mul(x,zz)),F32.sub(F32.mul(x,yy),F32.mul(y,xx))}
def normalize(+v:B.Vec3) -> B.Vec3:
  scale(v,F32.div(1.0,F32.sqrt(dot(v,v))))
def four_normal(+f:Four) -> B.Vec3:
  +a = vertex_position(at(f,0))
  normalize(cross(sub(vertex_position(at(f,1)),a),sub(vertex_position(at(f,2)),a)))
def normal_direction(+normal:B.Vec3) -> Maybe<&2,B.Direction>:
  J.choose(Maybe<&2,B.Direction>,Some{nearest(normal)},None{},vec_finite(normal) && Bool.not(vec_eq(normal,B.Vec3{0.0,0.0,0.0})))
def min_first(+a:F32,+b:F32) -> F32:
  J.choose(F32,b,a,F32.is_lt(b,a))
def max_first(+a:F32,+b:F32) -> F32:
  J.choose(F32,b,a,F32.is_gt(b,a))
def minimum(a:B.Vec3,b:B.Vec3) -> B.Vec3:
  match a b:
    case B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{min_first(x,xx),min_first(y,yy),min_first(z,zz)}
def maximum(a:B.Vec3,b:B.Vec3) -> B.Vec3:
  match a b:
    case B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{max_first(x,xx),max_first(y,yy),max_first(z,zz)}
def replace(f:Four,index:U32,v:M.Vertex) -> Four:
  match f index:
    case Four{a,b,c,d} 0: Four{v,b,c,d}
    case Four{a,b,c,d} 1: Four{a,v,c,d}
    case Four{a,b,c,d} 2: Four{a,b,v,d}
    case Four{a,b,c,d} _: Four{a,b,c,v}
def swap(+f:Four,+i:U32,+j:U32) -> Four:
  replace(replace(f,i,at(f,j)),j,at(f,i))
def find_index(fuel:Nat,+f:Four,+index:U32,+p:B.Vec3) -> Maybe<&2,U32>:
  match fuel:
    case 0n: None{}
    case 1n+rest:
      J.choose(Maybe<&2,U32>,Some{index},find_index(rest,f,U32.inc(index),p),vec_eq(vertex_position(at(f,index)),p))
def found_index(value:Maybe<&2,U32>) -> Result<&2,&2,Error,U32>:
  match value:
    case None{}: Fail{Invalid{"CannotFindWindingVertex"}}
    case Some{i}: Done{i}
def winding_step(fuel:Nat,+f:Four,+d:B.Direction,+lo:B.Vec3,+hi:B.Vec3,+i:U32) -> Result<&2,&2,Error,Four>:
  match fuel:
    case 0n: Done{f}
    case 1n+ +rest:
      do Result<&2,&2,Error,Four>:
        j : U32 <- found_index(find_index(1n+rest,f,i,corner(d,i,lo,hi)))
        winding_step(rest,swap(f,i,j),d,lo,hi,U32.inc(i))
def winding_gate(+f:Four,d:B.Direction,present:Bool) -> Result<&2,&2,Error,Four>:
  match present:
    case True{}: Done{f}
    case False{}:
      +lo = minimum(minimum(minimum(minimum(B.Vec3{999.0,999.0,999.0},vertex_position(at(f,0))),vertex_position(at(f,1))),vertex_position(at(f,2))),vertex_position(at(f,3)))
      +hi = maximum(maximum(maximum(maximum(B.Vec3{F32.neg(999.0),F32.neg(999.0),F32.neg(999.0)},vertex_position(at(f,0))),vertex_position(at(f,1))),vertex_position(at(f,2))),vertex_position(at(f,3)))
      winding_step(4n,f,d,lo,hi,0)
def winding(f:Four,d:B.Direction,rot:Prepared) -> Result<&2,&2,Error,Four>:
  Prepared{m,o,present} = rot
  winding_gate(f,d,present)

# Scalar sin/cosFromSin results measured from pinned JOML, for this finite domain.
# No arbitrary-angle transcendental approximation is admitted.
def trig_bits(bits:U32) -> Maybe<&2,Trig>:
  match bits:
    case 3266576384: Some{Trig{F32.neg(1.0),0.0}}
    case 3258187776: Some{Trig{F32.neg(raw(1060439283)),raw(1060439283)}}
    case 3249799168: Some{Trig{F32.neg(raw(1053028118)),raw(1064076126)}}
    case 0: Some{Trig{0.0,1.0}}
    case 2147483648: Some{Trig{raw(2147483648),1.0}}
    case 1096286208: Some{Trig{raw(1047465037),raw(1064889660)}}
    case 1102315520: Some{Trig{raw(1053028118),raw(1064076126)}}
    case 1110704128: Some{Trig{raw(1060439283),raw(1060439283)}}
    case 1119092736: Some{Trig{1.0,raw(2147483648)}}
    case _: None{}
def axis_matrix(axis:B.Axis,trig:Trig) -> Mat:
  match axis trig:
    case B.X{} Trig{+s,+c}: Mat{B.Vec3{1.0,0.0,0.0},B.Vec3{0.0,c,F32.neg(s)},B.Vec3{0.0,s,c},False{}}
    case B.Y{} Trig{+s,+c}: Mat{B.Vec3{c,0.0,s},B.Vec3{0.0,1.0,0.0},B.Vec3{F32.neg(s),0.0,c},False{}}
    case B.Z{} Trig{+s,+c}: Mat{B.Vec3{c,F32.neg(s),0.0},B.Vec3{s,c,0.0},B.Vec3{0.0,0.0,1.0},False{}}
def column_factor(v:B.Vec3) -> F32:
  B.Vec3{x,y,z} = v
  F32.div(1.0,F32.max(F32.max(F32.abs(x),F32.abs(y)),F32.abs(z)))
def row_scale(v:B.Vec3,f:B.Vec3) -> B.Vec3:
  match v f:
    case B.Vec3{x,y,z} B.Vec3{xx,yy,zz}: B.Vec3{F32.mul(x,xx),F32.mul(y,yy),F32.mul(z,zz)}
def rescale_with(+m:Mat,+f:B.Vec3) -> Mat:
  Mat{a,b,c,i} = m
  Mat{row_scale(a,f),row_scale(b,f),row_scale(c,f),False{}}
def rescale_columns(m:Mat) -> B.Vec3:
  Mat{a,b,c,i} = m
  B.Vec3{column_factor(a),column_factor(b),column_factor(c)}
def rescale_matrix(+m:Mat,rescale:Bool) -> Mat:
  J.choose(Mat,rescale_with(m,rescale_columns(columns(m))),m,rescale && Bool.not(mat_identity(m)))
def axis_prepared(axis:B.Axis,origin:B.Vec3,rescale:Bool,trig:Maybe<&2,Trig>) -> Result<&2,&2,Error,Prepared>:
  match trig:
    case None{}: Fail{Unsupported{"ElementAngle"}}
    case Some{v}: Done{Prepared{rescale_matrix(axis_matrix(axis,v),rescale),origin,True{}}}
def axis_angle(+axis:B.Axis,+angle:F32,+origin:B.Vec3,rescale:Bool) -> Result<&2,&2,Error,Prepared>:
  J.choose(Result<&2,&2,Error,Prepared>,Done{Prepared{identity(),origin,True{}}},axis_prepared(axis,origin,rescale,trig_bits(F32.bits(angle))),F32.is_eq(angle,0.0))
def element_rotation(value:Maybe<&2,B.Rotation>) -> Result<&2,&2,Error,Prepared>:
  match value:
    case None{}: Done{Prepared{identity(),B.Vec3{0.0,0.0,0.0},False{}}}
    case Some{B.Rotation{origin,B.SingleAxis{axis,angle},rescale}}:
      axis_angle(axis,angle,origin,rescale)
    case Some{B.Rotation{origin,B.Euler{angles},rescale}}:
      J.choose(Result<&2,&2,Error,Prepared>,Done{Prepared{identity(),origin,True{}}},Fail{Unsupported{"ElementEuler"}},vec_eq(angles,B.Vec3{0.0,0.0,0.0}))

def shade(d:B.Direction,nether:Bool) -> F32:
  match d:
    case B.Down{}: J.choose(F32,0.9,0.5,nether)
    case B.Up{}: J.choose(F32,0.9,1.0,nether)
    case B.North{}: 0.8
    case B.South{}: 0.8
    case B.West{}: 0.6
    case B.East{}: 0.6
def shade_direction(override:Maybe<&2,B.Direction>,fallback:B.Direction) -> B.Direction:
  match override:
    case None{}: fallback
    case Some{d}: d
def sprite_finite(sprite:Sprite) -> Bool:
  Sprite{slot,u0,v0,u1,v1,layer,animated} = sprite
  finite(u0) && finite(v0) && finite(u1) && finite(v1)
def sprite_checked(+sprite:Sprite,valid:Bool) -> Result<&2,&2,Error,Sprite>:
  match valid:
    case True{}: Done{sprite}
    case False{}: Fail{Invalid{"NonFiniteSpriteUV"}}
def sprite_missing(missing:Maybe<&2,Sprite>,name:String) -> Result<&2,&2,Error,Sprite>:
  match missing:
    case None{}: Fail{MissingMaterial{name}}
    case Some{+sprite}: sprite_checked(sprite,sprite_finite(sprite))
def sprite_present(+sprites:Map<&2,Sprite>,missing:Maybe<&2,Sprite>,+name:String,present:Bool) -> Result<&2,&2,Error,Sprite>:
  match present:
    case False{}: sprite_missing(missing,name)
    case True{}:
      +sprite = B.map_value(Sprite,Map.get(Sprite,Sprite{0,0.0,0.0,1.0,1.0,Solid{},False{}},sprites,name))
      sprite_checked(sprite,sprite_finite(sprite))
def sprite_lookup(ctx:Context,+name:String) -> Result<&2,&2,Error,Sprite>:
  Context{+sprites,missing} = ctx
  sprite_present(sprites,missing,name,B.map_has(Sprite,Map.has(&2,Sprite,sprites,name)))
def missing_material(ctx:Context,reference:String) -> Result<&2,&2,Error,MaterialInput>:
  Context{sprites,missing} = ctx
  do Result<&2,&2,Error,MaterialInput>:
    sp : Sprite <- sprite_missing(missing,reference)
    Done{MaterialInput{sp,"minecraft:missingno",False{}}}
def material_name(ctx:Context,+name:String) -> String:
  Context{sprites,missing} = ctx
  J.choose(String,name,"minecraft:missingno",B.map_has(Sprite,Map.has(&2,Sprite,sprites,name)))
def material_sprite(+ctx:Context,value:Maybe<&2,B.Material>,reference:String) -> Result<&2,&2,Error,MaterialInput>:
  match value:
    case Some{B.Material{+name,force}}:
      do Result<&2,&2,Error,MaterialInput>:
        sp : Sprite <- sprite_lookup(ctx,name)
        Done{MaterialInput{sp,material_name(ctx,name),force}}
    case None{}: missing_material(ctx,reference)
def baked_ready(f:Four,+direction:B.Direction,cullface:Maybe<&2,B.Direction>,name:String,sprite:Sprite,tint:U32,emission:U32,+override:Maybe<&2,B.Direction>,+force:Bool) -> Baked:
  Four{a,b,c,d} = f
  Sprite{texture,u0,v0,u1,v1,layer,animated} = sprite
  +sd = shade_direction(override,direction)
  Baked{a,b,c,d,direction,cullface,name,texture,tint,emission,override,J.choose(Layer,Translucent{},layer,force),force,animated,shade(sd,False{}),shade(sd,True{})}
def oriented_face(f:Four,direction:Maybe<&2,B.Direction>,rot:Prepared,cullface:Maybe<&2,B.Direction>,name:String,sprite:Sprite,tint:U32,emission:U32,override:Maybe<&2,B.Direction>,force:Bool) -> Result<&2,&2,Error,Maybe<&2,Baked>>:
  match direction:
    case None{}: Done{None{}}
    case Some{+dir}:
      do Result<&2,&2,Error,Maybe<&2,Baked>>:
        wound : Four <- winding(f,dir,rot)
        Done{Some{baked_ready(wound,dir,cullface,name,sprite,tint,emission,override,force)}}
def face_ready(face:B.Face,+from:B.Vec3,+to:B.Vec3,emission:U32,override:Maybe<&2,B.Direction>,+rot:Prepared,+state:State,material:MaterialInput) -> Result<&2,&2,Error,Maybe<&2,Baked>>:
  B.Face{+d,cullface,uv,+turn,+texture,tint} = face
  MaterialInput{+sprite,name,force} = material
  +coords = face_uv(uv,d,from,to)
  +sm = state_matrix(state)
  +fm = inverse_face(state,d)
  +f : Four = Four{vertex(0,d,from,to,coords,turn,sm,fm,rot,sprite),vertex(1,d,from,to,coords,turn,sm,fm,rot,sprite),vertex(2,d,from,to,coords,turn,sm,fm,rot,sprite),vertex(3,d,from,to,coords,turn,sm,fm,rot,sprite)}
  do Result<&2,&2,Error,Maybe<&2,Baked>>:
    checked : Four <- four_checked(f,four_finite(f))
    oriented_face(checked,normal_direction(four_normal(f)),rot,cull(state,cullface),name,sprite,tint,emission,override,force)
def face_bake(+face:B.Face,from:B.Vec3,to:B.Vec3,emission:U32,override:Maybe<&2,B.Direction>,rot:Prepared,state:State,resolved:B.Resolved,ctx:Context) -> Result<&2,&2,Error,Maybe<&2,Baked>>:
  B.Face{d,cullface,uv,turn,+texture,tint} = face
  do Result<&2,&2,Error,Maybe<&2,Baked>>:
    material : MaterialInput <- material_sprite(ctx,B.material(resolved,texture),texture)
    face_ready(face,from,to,emission,override,rot,state,material)
def face_direction(face:B.Face) -> B.Direction:
  B.Face{d,c,u,r,t,i} = face
  d
def face_find(faces:List<&2,B.Face>,+d:B.Direction) -> Maybe<&2,B.Face>:
  match faces:
    case Nil{}: None{}
    case +face <> tail:
      J.choose(Maybe<&2,B.Face>,Some{face},face_find(tail,d),direction_eq(face_direction(face),d))
def face_prefix(value:Maybe<&2,B.Face>,tail:List<&2,B.Face>) -> List<&2,B.Face>:
  match value:
    case None{}: tail
    case Some{f}: f <> tail
def ordered_faces(order:List<&2,B.Direction>,+faces:List<&2,B.Face>) -> List<&2,B.Face>:
  match order:
    case Nil{}: []
    case d <> tail: face_prefix(face_find(faces,d),ordered_faces(tail,faces))
def valid_turn(+n:U32) -> Bool:
  U32.is_lt(n,360) && U32.is_eq(U32.mod(n,90),0)
def uv_finite(v:Maybe<&2,B.UV>) -> Bool:
  match v:
    case None{}: True{}
    case Some{B.UV{a,b,c,d}}: finite(a) && finite(b) && finite(c) && finite(d)
def face_valid(face:B.Face) -> Bool:
  B.Face{d,c,uv,turn,t,i} = face
  uv_finite(uv) && valid_turn(turn)
def face_checked(face:B.Face,valid:Bool) -> Result<&2,&2,Error,B.Face>:
  match valid:
    case True{}: Done{face}
    case False{}: Fail{Invalid{"FaceUVOrRotation"}}
def baked_prefix(v:Maybe<&2,Baked>,rest:List<&2,Baked>) -> List<&2,Baked>:
  match v:
    case None{}: rest
    case Some{q}: q <> rest
def faces_bake(faces:List<&2,B.Face>,+from:B.Vec3,+to:B.Vec3,+emission:U32,+override:Maybe<&2,B.Direction>,+rot:Prepared,+state:State,+resolved:B.Resolved,+ctx:Context) -> Result<&2,&2,Error,List<&2,Baked>>:
  match faces:
    case Nil{}: Done{[]}
    case +face <> tail:
      do Result<&2,&2,Error,List<&2,Baked>>:
        checked : B.Face <- face_checked(face,face_valid(face))
        head : Maybe<&2,Baked> <- face_bake(checked,from,to,emission,override,rot,state,resolved,ctx)
        rest : List<&2,Baked> <- faces_bake(tail,from,to,emission,override,rot,state,resolved,ctx)
        Done{baked_prefix(head,rest)}
def rotation_finite(value:Maybe<&2,B.Rotation>) -> Bool:
  match value:
    case None{}: True{}
    case Some{B.Rotation{origin,v,rescale}}: vec_finite(origin)
def element_ready(element:B.Element,+state:State,resolved:B.Resolved,ctx:Context) -> Result<&2,&2,Error,List<&2,Baked>>:
  B.Element{from,to,rot,faces,emission,override} = element
  do Result<&2,&2,Error,List<&2,Baked>>:
    rotation : Prepared <- element_rotation(rot)
    faces_bake(ordered_faces([B.Down{},B.Up{},B.North{},B.South{},B.West{},B.East{}],faces),from,to,emission,override,rotation,state,resolved,ctx)
def element_valid(element:B.Element) -> Bool:
  B.Element{from,to,rot,faces,emission,override} = element
  vec_finite(from) && vec_finite(to) && rotation_finite(rot)
def element_gate(element:B.Element,state:State,resolved:B.Resolved,ctx:Context,valid:Bool) -> Result<&2,&2,Error,List<&2,Baked>>:
  match valid:
    case False{}: Fail{Invalid{"NonFiniteElement"}}
    case True{}: element_ready(element,state,resolved,ctx)
def element_bake(+element:B.Element,state:State,resolved:B.Resolved,ctx:Context) -> Result<&2,&2,Error,List<&2,Baked>>:
  element_gate(element,state,resolved,ctx,element_valid(element))
def elements_bake(elements:List<&2,B.Element>,+state:State,+resolved:B.Resolved,+ctx:Context) -> Result<&2,&2,Error,List<&2,Baked>>:
  match elements:
    case Nil{}: Done{[]}
    case e <> tail:
      do Result<&2,&2,Error,List<&2,Baked>>:
        head : List<&2,Baked> <- element_bake(e,state,resolved,ctx)
        rest : List<&2,Baked> <- elements_bake(tail,state,resolved,ctx)
        Done{List.append(&2,Baked,head,rest)}
def bake_valid(resolved:B.Resolved,state:State,ctx:Context) -> Result<&2,&2,Error,List<&2,Baked>>:
  B.Resolved{id,parent,+elements,present,ao,gui,display,textures,diagnostics} = resolved
  elements_bake(elements,state,B.Resolved{id,parent,elements,present,ao,gui,display,textures,diagnostics},ctx)
def bake_gate(resolved:B.Resolved,state:State,ctx:Context,valid:Bool) -> Result<&2,&2,Error,List<&2,Baked>>:
  match valid:
    case False{}: Fail{Invalid{"StateQuarterTurns"}}
    case True{}: bake_valid(resolved,state,ctx)
def bake(resolved:B.Resolved,+state:State,ctx:Context) -> Result<&2,&2,Error,List<&2,Baked>>:
  State{+x,+y,+z,lock} = state
  bake_gate(resolved,state,ctx,valid_turn(x) && valid_turn(y) && valid_turn(z))

def mesh_mode(layer:Layer,threshold:U32) -> M.Mode:
  match layer:
    case Solid{}: M.Opaque{}
    case Cutout{}: M.Cutout{threshold}
    case Translucent{}: M.Translucent{}
def layer_flag(layer:Layer) -> U32:
  match layer:
    case Translucent{}: 1
    case _: 0
def flags(value:Baked) -> U32:
  Baked{a,b,c,d,direction,cf,sprite,texture,tint_index,emission,override,layer,force,animated,ds,ns} = value
  U32.or(layer_flag(layer),J.choose(U32,2,0,animated))
def mesh(value:Baked,appearance:Appearance,order:U32) -> M.Quad:
  Baked{a,b,c,d,direction,cf,sprite,texture,tint_index,emission,override,layer,force,animated,ds,ns} = value
  Appearance{tint,light,address,cull,nether,threshold} = appearance
  M.Quad{a,b,c,d,M.Material{texture,tint,light,J.choose(F32,ns,ds,nether),mesh_mode(layer,threshold),address},cull,order}
