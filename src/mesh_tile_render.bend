import Base
import ./mesh_render.bend as M
import ./client_render.bend as R
import ./player_presentation.bend as P

# Host-built tile candidates. Projection only proposes exclusions; the exact
# production hit test confirms each exclusion over all admitted tile pixels.
# Thus this first selector trades host work for an honest completeness contract.
type Screen is Data:
  Whole{}
  Rectangle{left:F32,top:F32,right:F32,bottom:F32}
type Lens is Data:
  Lens{origin:M.Vec3,du:M.Vec3,dv:M.Vec3,dw:M.Vec3,
    scale:F32,width:U32,height:U32,valid:Bool}
type Entry is Data:
  Entry{quad:M.Prepared,screen:Screen}
type Candidates is Data:
  Candidates{opaque:List<&2,M.Prepared>,alpha:List<&2,M.Prepared>}
type Cells is Data:
  Tile{entries:List<&2,Entry>}
  Node{tl:Cells,tr:Cells,bl:Cells,br:Cells}
type Owner is Data:
  Owner{scene:M.Scene,camera:R.Basis,settings:M.Settings,width:U32,height:U32,
    depth:Nat,cells:Cells}

def number(value:U32) -> F32:
  F32.from_nat(U32.to_nat(value))

def lens(camera:R.Basis,width:U32,height:U32) -> Lens:
  R.Basis{x,y,z,+rx,+rz,+ux,+uy,+uz,+fx,+fy,+fz,scale} = camera
  +right : M.Vec3 = M.Vec3{rx,0.0,rz}
  +up : M.Vec3 = M.Vec3{ux,uy,uz}
  +forward : M.Vec3 = M.Vec3{fx,fy,fz}
  +du = M.cross(up,forward)
  +det = M.dot(right,du)
  Lens{M.Vec3{x,y,z},du,M.cross(forward,right),M.cross(right,up),scale,width,height,
    M.finite(det) && F32.is_gt(det,0.5) && F32.is_lt(det,2.0)}

def point_rectangle(valid:Bool,+x:F32,+y:F32) -> Screen:
  match valid:
    case False{}: Whole{}
    case True{}: Rectangle{x,y,x,y}

def projected_coordinates(valid:Bool,u:F32,v:F32,+z:F32,+scale:F32,+width:U32,+height:U32) -> Screen:
  match valid:
    case False{}: Whole{}
    case True{}:
      +px = F32.mul(F32.add(F32.div(F32.div(u,z),F32.mul(scale,F32.div(number(width),number(height)))),1.0),F32.mul(number(width),0.5))
      +py = F32.mul(F32.sub(1.0,F32.div(F32.div(v,z),scale)),F32.mul(number(height),0.5))
      point_rectangle(M.finite(px) && M.finite(py),px,py)

def projected_point(valid:Bool,+point:M.Vec3,+value:Lens) -> Screen:
  match valid:
    case False{}: Whole{}
    case True{}:
      Lens{origin,du,dv,dw,+scale,+width,+height,usable} = value
      +relative = M.subtract(point,origin)
      +z = M.dot(relative,dw)
      +u = M.dot(relative,du)
      +v = M.dot(relative,dv)
      projected_coordinates(usable && M.finite(z) && M.finite(u) && M.finite(v) && F32.is_gt(z,0.25),u,v,z,scale,width,height)

def merged(a:Screen,b:Screen) -> Screen:
  match a b:
    case Rectangle{left,top,right,bottom} Rectangle{l,t,r,b}:
      Rectangle{F32.min(left,l),F32.min(top,t),F32.max(right,r),F32.max(bottom,b)}
    case _ _: Whole{}

# Eight corners enclose both prepared triangles. A broad screen margin makes
# most ordinary misses cheap proposals; it is not a float soundness assumption.
def screen(bounds:M.Bounds,+value:Lens) -> Screen:
  M.Bounds{M.Vec3{+lx,+ly,+lz},M.Vec3{+hx,+hy,+hz}} = bounds
  merged(merged(merged(projected_point(True{},M.Vec3{lx,ly,lz},value),projected_point(True{},M.Vec3{hx,ly,lz},value)),
    merged(projected_point(True{},M.Vec3{lx,hy,lz},value),projected_point(True{},M.Vec3{hx,hy,lz},value))),
    merged(merged(projected_point(True{},M.Vec3{lx,ly,hz},value),projected_point(True{},M.Vec3{hx,ly,hz},value)),
    merged(projected_point(True{},M.Vec3{lx,hy,hz},value),projected_point(True{},M.Vec3{hx,hy,hz},value))))

def entries(prepared:List<&2,M.Prepared>,+value:Lens) -> List<&2,Entry>:
  match prepared:
    case Nil{}: []
    case +head <> tail: Entry{head,screen(M.bounds_of(head),value)} <> entries(tail,value)

def may_overlap(bounds:Screen,+x:U32,+y:U32) -> Bool:
  match bounds:
    case Whole{}: True{}
    case Rectangle{left,top,right,bottom}:
      F32.is_le(F32.sub(left,32.0),number(U32.add(x,15))) &&
      F32.is_le(F32.sub(top,32.0),number(U32.add(y,15))) &&
      F32.is_ge(F32.add(right,32.0),number(x)) && F32.is_ge(F32.add(bottom,32.0),number(y))

def ray_direction(camera:R.Basis,quad:M.Prepared,settings:M.Settings,direction:R.Direction) -> Maybe<&2,M.Hit>:
  match camera direction:
    case R.Basis{ox,oy,oz,rx,rz,ux,uy,uz,fx,fy,fz,scale} R.Direction{dx,dy,dz}:
      M.quad_hit(quad,M.Vec3{ox,oy,oz},M.Vec3{dx,dy,dz},settings)

def ray_hit(admitted:Bool,quad:M.Prepared,+camera:R.Basis,settings:M.Settings,x:U32,y:U32,width:U32,height:U32) -> Maybe<&2,M.Hit>:
  match admitted:
    case False{}: None{}
    case True{}:
      ray_direction(camera,quad,settings,R.direction(camera,x,y,width,height))

def has_hit(value:Maybe<&2,M.Hit>) -> Bool:
  match value:
    case None{}: False{}
    case Some{hit}: True{}

# Exact finite raster support, including M's cull/determinant/near/far tests.
# This tail loop is host candidate construction, never a per-ray Spatial walk.
def any_hit(fuel:Nat,found:Bool,+quad:M.Prepared,+camera:R.Basis,+settings:M.Settings,+x:U32,+y:U32,+width:U32,+height:U32,+index:U32) -> Bool:
  match fuel found:
    case 0n True{}: True{}
    case 0n False{}: False{}
    case 1n+rest True{}: True{}
    case 1n+rest False{}:
      +px = U32.add(x,U32.mod(index,16))
      +py = U32.add(y,U32.div(index,16))
      any_hit(rest,has_hit(ray_hit(U32.is_lt(px,width) && U32.is_lt(py,height),quad,camera,settings,px,py,width,height)),quad,camera,settings,x,y,width,height,U32.inc(index))

def admitted(proposal:Bool,quad:M.Prepared,camera:R.Basis,settings:M.Settings,x:U32,y:U32,width:U32,height:U32) -> Bool:
  match proposal:
    case True{}: True{}
    case False{}: any_hit(256n,False{},quad,camera,settings,x,y,width,height,0)

def is_alpha(quad:M.Prepared) -> Bool:
  M.Prepared{a,b,material,cull,order,index,bounds} = quad
  U32.is_eq(M.material_translucent(material),1)

def selected(keep:Bool,alpha:Bool,quad:M.Prepared,opaque:List<&2,M.Prepared>,blend:List<&2,M.Prepared>) -> Candidates:
  match keep alpha:
    case False{} _: Candidates{opaque,blend}
    case True{} False{}: Candidates{quad <> opaque,blend}
    case True{} True{}: Candidates{opaque,quad <> blend}

def retained_entry(keep:Bool,entry:Entry,tail:List<&2,Entry>) -> List<&2,Entry>:
  match keep:
    case False{}: tail
    case True{}: entry <> tail

def tile_entries(remaining:List<&2,Entry>,+camera:R.Basis,+settings:M.Settings,+x:U32,+y:U32,+width:U32,+height:U32,reverse:List<&2,Entry>) -> List<&2,Entry>:
  match remaining:
    case Nil{}: List.reverse(&2,Entry,reverse)
    case +head <> tail:
      Entry{+quad,bounds} = head
      tile_entries(tail,camera,settings,x,y,width,height,
        retained_entry(admitted(may_overlap(bounds,x,y),quad,camera,settings,x,y,width,height),head,reverse))

# Clone only tile-local cons spines. The retained cell list is a borrower;
# fin consumes the two new lists, never a list owned by the returned Cells.
def split_entries(remaining:List<&2,Entry>,value:Candidates) -> Candidates:
  match remaining:
    case Nil{}:
      Candidates{opaque,alpha} = value
      Candidates{List.reverse(&2,M.Prepared,opaque),List.reverse(&2,M.Prepared,alpha)}
    case Entry{+quad,bounds} <> tail:
      Candidates{opaque,alpha} = value
      split_entries(tail,selected(True{},is_alpha(quad),quad,opaque,alpha))

def cells(n:Nat,+remaining:List<&2,Entry>,+camera:R.Basis,+settings:M.Settings,+x:U32,+y:U32,+side:U32,+width:U32,+height:U32) -> Cells:
  match n:
    case 0n: Tile{tile_entries(remaining,camera,settings,x,y,width,height,[])}
    case 1n+ +rest:
      +half = U32.div(side,2)
      a b c d = cells(rest,remaining,camera,settings,x,y,half,width,height) cells(rest,remaining,camera,settings,U32.add(x,half),y,half,width,height)
        cells(rest,remaining,camera,settings,x,U32.add(y,half),half,width,height) cells(rest,remaining,camera,settings,U32.add(x,half),U32.add(y,half),half,width,height)
      Node{a,b,c,d}

def prepare(+scene:M.Scene,+width:U32,+height:U32) -> Owner:
  M.Scene{camera,quads,+settings} = scene
  +basis = M.basis(camera,settings)
  +depth = Nat.max(4n,P.depth(width,height))
  Owner{scene,basis,settings,width,height,depth,
    cells(Nat.sub(depth,4n),entries(M.prepare(quads,0),lens(basis,width,height)),basis,settings,0,0,U32.shln(1,depth),width,height)}

# These are the existing production intersection, opaque winner, texture and
# ordered alpha-compositing operations. Pixels see only flat candidate lists.
def pixel_direction(opaque:List<&2,M.Prepared>,alpha:List<&2,M.Prepared>,+textures:List<&2,R.Texture>,camera:R.Basis,+settings:M.Settings,direction:R.Direction) -> U32:
  match camera settings direction:
    case R.Basis{ox,oy,oz,rx,rz,ux,uy,uz,fx,fy,fz,scale} M.Settings{near,+far,scale,+background} R.Direction{dx,dy,dz}:
      +origin : M.Vec3 = M.Vec3{ox,oy,oz}
      +direction : M.Vec3 = M.Vec3{dx,dy,dz}
      +best = M.opaque_trace(opaque,origin,direction,settings,textures,M.Fragment{F32.add(far,1.0),4294967295,4294967295,background})
      M.pixel_best(best,alpha,textures,origin,direction,settings)

def pixel_valid(valid:Bool,opaque:List<&2,M.Prepared>,alpha:List<&2,M.Prepared>,+camera:R.Basis,settings:M.Settings,textures:List<&2,R.Texture>,x:U32,y:U32,width:U32,height:U32) -> U32:
  match valid:
    case False{}: 0
    case True{}:
      pixel_direction(opaque,alpha,textures,camera,settings,R.direction(camera,x,y,width,height))

def pixel(opaque:List<&2,M.Prepared>,alpha:List<&2,M.Prepared>,camera:R.Basis,settings:M.Settings,textures:List<&2,R.Texture>,+x:U32,+y:U32,+width:U32,+height:U32) -> U32:
  pixel_valid(U32.is_lt(x,width) && U32.is_lt(y,height),opaque,alpha,camera,settings,textures,x,y,width,height)

def b2(+opaque:List<&2,M.Prepared>,+alpha:List<&2,M.Prepared>,+camera:R.Basis,+settings:M.Settings,+textures:List<&2,R.Texture>,+x:U32,+y:U32,+width:U32,+height:U32) -> Image:
  +xx = U32.add(x,1)
  +yy = U32.add(y,1)
  Qua{Pix{pixel(opaque,alpha,camera,settings,textures,x,y,width,height)},Pix{pixel(opaque,alpha,camera,settings,textures,xx,y,width,height)},Pix{pixel(opaque,alpha,camera,settings,textures,x,yy,width,height)},Pix{pixel(opaque,alpha,camera,settings,textures,xx,yy,width,height)}}

def b4(+opaque:List<&2,M.Prepared>,+alpha:List<&2,M.Prepared>,+camera:R.Basis,+settings:M.Settings,+textures:List<&2,R.Texture>,+x:U32,+y:U32,+width:U32,+height:U32) -> Image:
  +xx = U32.add(x,2)
  +yy = U32.add(y,2)
  Qua{b2(opaque,alpha,camera,settings,textures,x,y,width,height),b2(opaque,alpha,camera,settings,textures,xx,y,width,height),b2(opaque,alpha,camera,settings,textures,x,yy,width,height),b2(opaque,alpha,camera,settings,textures,xx,yy,width,height)}

def b8(+opaque:List<&2,M.Prepared>,+alpha:List<&2,M.Prepared>,+camera:R.Basis,+settings:M.Settings,+textures:List<&2,R.Texture>,+x:U32,+y:U32,+width:U32,+height:U32) -> Image:
  +xx = U32.add(x,4)
  +yy = U32.add(y,4)
  Qua{b4(opaque,alpha,camera,settings,textures,x,y,width,height),b4(opaque,alpha,camera,settings,textures,xx,y,width,height),b4(opaque,alpha,camera,settings,textures,x,yy,width,height),b4(opaque,alpha,camera,settings,textures,xx,yy,width,height)}

def b16(+opaque:List<&2,M.Prepared>,+alpha:List<&2,M.Prepared>,+camera:R.Basis,+settings:M.Settings,+textures:List<&2,R.Texture>,+x:U32,+y:U32,+width:U32,+height:U32) -> Image:
  +xx = U32.add(x,8)
  +yy = U32.add(y,8)
  Qua{b8(opaque,alpha,camera,settings,textures,x,y,width,height),b8(opaque,alpha,camera,settings,textures,xx,y,width,height),b8(opaque,alpha,camera,settings,textures,x,yy,width,height),b8(opaque,alpha,camera,settings,textures,xx,yy,width,height)}

# Explicit last consumption after every borrowed pixel read.
def fin(image:Image,opaque:List<&2,M.Prepared>,alpha:List<&2,M.Prepared>) -> Image:
  match opaque alpha:
    case head <> tail _: fin(image,tail,alpha)
    case Nil{} head <> tail: fin(image,[],tail)
    case Nil{} Nil{}: image

def tile(value:Candidates,camera:R.Basis,settings:M.Settings,textures:List<&2,R.Texture>,x:U32,y:U32,width:U32,height:U32) -> Image:
  Candidates{+opaque,+alpha} = value
  fin(b16(opaque,alpha,camera,settings,textures,x,y,width,height),opaque,alpha)

# Balanced forks stop at16 pixels. No per-pixel fork or Spatial ownership.
def node(value:Cells,+camera:R.Basis,+settings:M.Settings,+textures:List<&2,R.Texture>,+x:U32,+y:U32,+side:U32,+width:U32,+height:U32) -> Image:
  match value:
    case Tile{entries}: tile(split_entries(entries,Candidates{[],[]}),camera,settings,textures,x,y,width,height)
    case Node{tl,tr,bl,br}:
      +half = U32.div(side,2)
      a b c d = node(tl,camera,settings,textures,x,y,half,width,height) node(tr,camera,settings,textures,U32.add(x,half),y,half,width,height)
        node(bl,camera,settings,textures,x,U32.add(y,half),half,width,height) node(br,camera,settings,textures,U32.add(x,half),U32.add(y,half),half,width,height)
      Qua{a,b,c,d}

# Owner is returned whole: source scene, camera/settings/dimensions/depth and
# the complete candidate tree. Resources likewise retain all texture Images.
def draw(+owner:Owner,assets:R.Assets) -> Owner & R.Assets & Image:
  Owner{scene,camera,settings,width,height,depth,cells} = owner
  R.Assets{+textures} = assets
  (owner,R.Assets{textures},node(cells,camera,settings,textures,0,0,U32.shln(1,depth),width,height))

def drop_entries(values:List<&2,Entry>) -> Unit:
  match values:
    case Nil{}: Unit{}
    case head <> tail: drop_entries(tail)

# Host-only drop; no bang on a scene/tree destructor.
def drop_cells(value:Cells) -> Unit:
  match value:
    case Tile{entries}: drop_entries(entries)
    case Node{tl,tr,bl,br}:
      a b c d = drop_cells(tl) drop_cells(tr) drop_cells(bl) drop_cells(br)
      Unit{}

def released(scene:M.Scene,dropped:Unit) -> M.Scene:
  match dropped:
    case Unit{}: scene

def release(owner:Owner) -> M.Scene:
  Owner{scene,camera,settings,width,height,depth,cells} = owner
  released(scene,drop_cells(cells))

def retained(value:Owner & R.Assets & Image) -> Owner & List<&2,R.Texture>:
  (owner,R.Assets{textures},image) = value
  (owner,textures)
