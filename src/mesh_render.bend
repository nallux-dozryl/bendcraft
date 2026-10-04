import Base
import ./client_render.bend as R
import ./png.bend as P
import ./player_presentation.bend as Presentation

def dimensions(width:U32,height:U32) -> Bool:
  Presentation.dimensions(width,height)

# Input vertices are already baked, in the camera's finite coordinate frame.
# Production model parsing/baking, world tint, AO and lightmaps are upstream.
type Vec3 is Data:
  Vec3{x:F32,y:F32,z:F32}
type UV is Data:
  UV{u:F32,v:F32}
type Vertex is Data:
  Vertex{position:Vec3,uv:UV}
type Mode is Data:
  Opaque{}
  Cutout{threshold:U32}
  Translucent{}
type Address is Data:
  Clamp{}
  Repeat{}
type Cull is Data:
  NoCull{}
  Back{}
type Material is Data:
  Material{texture:U32,tint:U32,light:U32,shade:F32,mode:Mode,address:Address}
type Quad is Data:
  Quad{a:Vertex,b:Vertex,c:Vertex,d:Vertex,material:Material,cull:Cull,order:U32}
type Settings is Data:
  Settings{near:F32,far:F32,scale:F32,background:U32}
type Scene is Data:
  Scene{camera:R.Camera,quads:List<&2,Quad>,settings:Settings}
type Error is Data:
  Error{code:String}
type Triangle is Data:
  Triangle{origin:Vec3,e1:Vec3,e2:Vec3,uv:UV,uv1:UV,uv2:UV}
type Bounds is Data:
  Bounds{low:Vec3,high:Vec3}
type Prepared is Data:
  Prepared{a:Triangle,b:Triangle,material:Material,cull:Cull,order:U32,index:U32,bounds:Bounds}
type Spatial is Data:
  Empty{}
  Flat{quads:List<&2,Prepared>}
  Leaf{bounds:Bounds,quads:List<&2,Prepared>}
  Branch{bounds:Bounds,left:Spatial,right:Spatial}
type Span is Data:
  Span{near:F32,far:F32}
type Hit is Data:
  Hit{distance:F32,u:F32,v:F32}
type Fragment is Data:
  Fragment{distance:F32,order:U32,index:U32,color:U32}

def defaults() -> Settings:
  Settings{0.0001,64.0,0.7002075382,4284784875}

def finite(+value:F32) -> Bool:
  U32.is_ne(U32.and(F32.bits(value),2139095040),2139095040)

def bounded(+value:F32,limit:F32) -> Bool:
  finite(value) && F32.is_le(F32.abs(value),limit)

def valid_position(value:Vec3) -> Bool:
  Vec3{x,y,z} = value
  bounded(x,4096.0) && bounded(y,4096.0) && bounded(z,4096.0)

def valid_uv(value:UV) -> Bool:
  UV{u,v} = value
  bounded(u,65536.0) && bounded(v,65536.0)

def valid_vertex(value:Vertex) -> Bool:
  Vertex{position,uv} = value
  valid_position(position) && valid_uv(uv)

def valid_mode(mode:Mode) -> Bool:
  match mode:
    case Cutout{threshold}: U32.is_le(threshold,255)
    case _: True{}

def valid_material(value:Material,count:U32) -> Bool:
  Material{texture,tint,+light,+shade,mode,address} = value
  U32.is_lt(texture,count) && U32.is_eq(U32.shrn(light,24n),255) && finite(shade) && F32.is_ge(shade,0.0) && F32.is_le(shade,1.0) && valid_mode(mode)

def translucent(mode:Mode) -> U32:
  match mode:
    case Translucent{}: 1
    case _: 0

def material_translucent(material:Material) -> U32:
  Material{texture,tint,light,shade,mode,address} = material
  translucent(mode)

def quads_error(quads:List<&2,Quad>,+textures:U32,+count:U32,+layers:U32) -> String:
  match quads:
    case Nil{}: P.choose(String,"Limits","",U32.is_gt(count,4096) || U32.is_gt(layers,64))
    case Quad{+a,+b,+c,+d,+material,cull,order} <> tail:
      P.choose(String,"Vertex",P.choose(String,"Material",quads_error(tail,textures,U32.inc(count),U32.add(layers,material_translucent(material))),Bool.not(valid_material(material,textures))),Bool.not(valid_vertex(a) && valid_vertex(b) && valid_vertex(c) && valid_vertex(d)))

def settings_valid(settings:Settings) -> Bool:
  Settings{+near,+far,+scale,background} = settings
  finite(near) && finite(far) && finite(scale) && F32.is_gt(near,0.0) && F32.is_gt(far,near) && F32.is_le(far,4096.0) && F32.is_gt(scale,0.0) && F32.is_le(scale,8.0) && U32.is_eq(U32.shrn(background,24n),255)

def camera_valid(camera:R.Camera) -> Bool:
  R.Camera{x,y,z,yaw,pitch} = camera
  bounded(x,4096.0) && bounded(y,4096.0) && bounded(z,4096.0) && bounded(yaw,65536.0) && bounded(pitch,65536.0)

def texture_valid(texture:R.Texture) -> Bool:
  R.Texture{+width,+height,+side,image} = texture
  U32.is_gt(width,0) && U32.is_gt(height,0) && U32.is_le(width,side) && U32.is_le(height,side) && U32.is_le(side,4096) && U32.is_eq(U32.and(side,U32.sub(side,1)),0)

def textures_valid(textures:List<&2,R.Texture>) -> Bool:
  match textures:
    case Nil{}: True{}
    case head <> tail: texture_valid(head) && textures_valid(tail)

def validation(scene:Scene,+textures:List<&2,R.Texture>,+width:U32,+height:U32) -> String:
  Scene{+camera,quads,+settings} = scene
  P.choose(String,"Dimensions",P.choose(String,"Camera",P.choose(String,"Settings",P.choose(String,"Textures",quads_error(quads,U32.from_nat(List.length(&2,R.Texture,textures)),0,0),Bool.not(textures_valid(textures))),Bool.not(settings_valid(settings))),Bool.not(camera_valid(camera))),Bool.not(Presentation.dimensions(width,height)))

def subtract(a:Vec3,b:Vec3) -> Vec3:
  match a b:
    case Vec3{x,y,z} Vec3{xx,yy,zz}: Vec3{F32.sub(x,xx),F32.sub(y,yy),F32.sub(z,zz)}

def cross(a:Vec3,b:Vec3) -> Vec3:
  match a b:
    case Vec3{+x,+y,+z} Vec3{+xx,+yy,+zz}: Vec3{F32.sub(F32.mul(y,zz),F32.mul(z,yy)),F32.sub(F32.mul(z,xx),F32.mul(x,zz)),F32.sub(F32.mul(x,yy),F32.mul(y,xx))}

def dot(a:Vec3,b:Vec3) -> F32:
  match a b:
    case Vec3{x,y,z} Vec3{xx,yy,zz}: F32.add(F32.mul(x,xx),F32.add(F32.mul(y,yy),F32.mul(z,zz)))

def triangle(a:Vertex,b:Vertex,c:Vertex) -> Triangle:
  match a b c:
    case Vertex{+p,+uv} Vertex{q,uv1} Vertex{r,uv2}: Triangle{p,subtract(q,p),subtract(r,p),uv,uv1,uv2}

def minimum(a:Vec3,b:Vec3) -> Vec3:
  match a b:
    case Vec3{x,y,z} Vec3{xx,yy,zz}: Vec3{F32.min(x,xx),F32.min(y,yy),F32.min(z,zz)}

def maximum(a:Vec3,b:Vec3) -> Vec3:
  match a b:
    case Vec3{x,y,z} Vec3{xx,yy,zz}: Vec3{F32.max(x,xx),F32.max(y,yy),F32.max(z,zz)}

def position(vertex:Vertex) -> Vec3:
  Vertex{p,uv} = vertex
  p

def quad_bounds(+a:Vertex,+b:Vertex,+c:Vertex,+d:Vertex) -> Bounds:
  Bounds{minimum(minimum(position(a),position(b)),minimum(position(c),position(d))),maximum(maximum(position(a),position(b)),maximum(position(c),position(d)))}

def prepare_quad(q:Quad,index:U32) -> Prepared:
  Quad{+a,+b,+c,+d,material,cull,order} = q
  Prepared{triangle(a,b,c),triangle(a,c,d),material,cull,order,index,quad_bounds(a,b,c,d)}

def prepare(quads:List<&2,Quad>,+index:U32) -> List<&2,Prepared>:
  match quads:
    case Nil{}: []
    case q <> tail: prepare_quad(q,index) <> prepare(tail,U32.inc(index))

def bounds_of(q:Prepared) -> Bounds:
  Prepared{a,b,material,cull,order,index,bounds} = q
  bounds

def merge_bounds(a:Bounds,b:Bounds) -> Bounds:
  match a b:
    case Bounds{low,high} Bounds{other_low,other_high}: Bounds{minimum(low,other_low),maximum(high,other_high)}

def all_bounds(quads:List<&2,Prepared>,bounds:Bounds) -> Bounds:
  match quads:
    case Nil{}: bounds
    case head <> tail: all_bounds(tail,merge_bounds(bounds,bounds_of(head)))

def component(axis:U32,value:Vec3) -> F32:
  match axis value:
    case 0 Vec3{x,y,z}: x
    case 1 Vec3{x,y,z}: y
    case _ Vec3{x,y,z}: z

def longest(bounds:Bounds) -> U32:
  Bounds{low,high} = bounds
  +extent = subtract(high,low)
  P.choose(U32,0,P.choose(U32,1,2,F32.is_ge(component(1,extent),component(2,extent))),F32.is_ge(component(0,extent),component(1,extent)) && F32.is_ge(component(0,extent),component(2,extent)))

def midpoint(+bounds:Bounds,+axis:U32) -> F32:
  Bounds{low,high} = bounds
  F32.mul(F32.add(component(axis,low),component(axis,high)),0.5)

def partition(quads:List<&2,Prepared>,+axis:U32,+middle:F32) -> List<&2,Prepared> & List<&2,Prepared>:
  match quads:
    case Nil{}: ([],[])
    case +head <> tail:
      P.paired(List<&2,Prepared>,List<&2,Prepared>,List<&2,Prepared> & List<&2,Prepared>,partition(tail,axis,middle),+left => +right => P.choose(List<&2,Prepared> & List<&2,Prepared>,(head <> left,right),(left,head <> right),F32.is_lt(midpoint(bounds_of(head),axis),middle)))

def is_empty(quads:List<&2,Prepared>) -> Bool:
  match quads:
    case Nil{}: True{}
    case _: False{}

def leaf_ready(quads:List<&2,Prepared>) -> Bool:
  Nat.is_le(List.length(&2,Prepared,quads),6n)

def spatial(+n:Nat,+quads:List<&2,Prepared>,stop:Bool) -> Spatial:
  match n quads stop:
    case _ Nil{} _: Empty{}
    case 0n +head <> tail _: Leaf{all_bounds(tail,bounds_of(head)),quads}
    case _ +head <> tail True{}: Leaf{all_bounds(tail,bounds_of(head)),quads}
    case 1n+p +head <> tail False{}:
      +bounds = all_bounds(tail,bounds_of(head))
      +axis = longest(bounds)
      P.paired(List<&2,Prepared>,List<&2,Prepared>,Spatial,partition(quads,axis,midpoint(bounds,axis)),+left => +right => Branch{bounds,spatial(p,left,leaf_ready(left) || is_empty(right)),spatial(p,right,leaf_ready(right) || is_empty(left))})

def separate(quads:List<&2,Prepared>) -> List<&2,Prepared> & List<&2,Prepared>:
  match quads:
    case Nil{}: ([],[])
    case +head <> tail:
      Prepared{a,b,+material,cull,order,index,bounds} = head
      P.paired(List<&2,Prepared>,List<&2,Prepared>,List<&2,Prepared> & List<&2,Prepared>,separate(tail),+opaque => +alpha => P.choose(List<&2,Prepared> & List<&2,Prepared>,(opaque,head <> alpha),(head <> opaque,alpha),U32.is_eq(material_translucent(material),1)))

def max_abs(value:Vec3) -> F32:
  Vec3{x,y,z} = value
  F32.max(F32.abs(x),F32.max(F32.abs(y),F32.abs(z)))

def expanded_span(+origin:F32,+direction:F32,+low:F32,+high:F32,+padding:F32,parallel:Bool) -> Span:
  +lo = F32.sub(low,padding)
  +hi = F32.add(high,padding)
  P.choose(Span,P.choose(Span,Span{F32.neg(100000000000000000000.0),100000000000000000000.0},Span{100000000000000000000.0,F32.neg(100000000000000000000.0)},F32.is_ge(origin,lo) && F32.is_le(origin,hi)),Span{F32.min(F32.div(F32.sub(lo,origin),direction),F32.div(F32.sub(hi,origin),direction)),F32.max(F32.div(F32.sub(lo,origin),direction),F32.div(F32.sub(hi,origin),direction))},parallel)

def box_span(origin:F32,+direction:F32,low:F32,high:F32,padding:F32) -> Span:
  expanded_span(origin,direction,low,high,padding,F32.is_eq(direction,0.0))

def span_join(a:Span,b:Span) -> Span:
  match a b:
    case Span{near,far} Span{other_near,other_far}: Span{F32.max(near,other_near),F32.min(far,other_far)}

def span_valid(value:Span,best:F32) -> Bool:
  Span{+near,+far} = value
  F32.is_le(near,far) && F32.is_ge(far,0.0) && F32.is_le(near,best)

def bounds_hit(bounds:Bounds,+origin:Vec3,direction:Vec3,best:F32) -> Bool:
  Bounds{+low,+high} = bounds
  Vec3{ox,oy,oz} = origin
  Vec3{dx,dy,dz} = direction
  +padding = F32.add(0.002,F32.mul(0.00001,F32.add(F32.max(max_abs(low),max_abs(high)),max_abs(origin))))
  span_valid(span_join(span_join(box_span(ox,dx,component(0,low),component(0,high),padding),box_span(oy,dy,component(1,low),component(1,high),padding)),box_span(oz,dz,component(2,low),component(2,high),padding)),best)

def determinant_valid(cull:Cull,+det:F32) -> Bool:
  match cull:
    case Back{}: F32.is_gt(det,0.00000001)
    case NoCull{}: F32.is_gt(F32.abs(det),0.00000001)

def uv_interpolate(base:UV,one:UV,two:UV,+u:F32,+v:F32) -> UV:
  match base one two:
    case UV{+a,+b} UV{c,d} UV{e,f}: UV{F32.add(a,F32.add(F32.mul(F32.sub(c,a),u),F32.mul(F32.sub(e,a),v))),F32.add(b,F32.add(F32.mul(F32.sub(d,b),u),F32.mul(F32.sub(f,b),v)))}

def hit_chosen(valid:Bool,distance:F32,uv:UV) -> Maybe<&2,Hit>:
  match valid uv:
    case True{} UV{u,v}: Some{Hit{distance,u,v}}
    case False{} _: None{}

def barycentric_scalar(valid:Bool,+ax:F32,+ay:F32,+az:F32,bx:F32,by:F32,bz:F32,dx:F32,dy:F32,dz:F32,+tx:F32,+ty:F32,+tz:F32,px:F32,py:F32,pz:F32,+det:F32,uv:UV,uv1:UV,uv2:UV,settings:Settings) -> Maybe<&2,Hit>:
  match valid:
    case False{}: None{}
    case True{}:
      Settings{near,far,scale,background} = settings
      +inverse = F32.div(1.0,det)
      +u = F32.mul(F32.add(F32.mul(tx,px),F32.add(F32.mul(ty,py),F32.mul(tz,pz))),inverse)
      +qx = F32.sub(F32.mul(ty,az),F32.mul(tz,ay))
      +qy = F32.sub(F32.mul(tz,ax),F32.mul(tx,az))
      +qz = F32.sub(F32.mul(tx,ay),F32.mul(ty,ax))
      +v = F32.mul(F32.add(F32.mul(dx,qx),F32.add(F32.mul(dy,qy),F32.mul(dz,qz))),inverse)
      +distance = F32.mul(F32.add(F32.mul(bx,qx),F32.add(F32.mul(by,qy),F32.mul(bz,qz))),inverse)
      hit_chosen(F32.is_ge(u,0.0) && F32.is_le(u,1.0) && F32.is_ge(v,0.0) && F32.is_le(F32.add(u,v),1.0) && F32.is_ge(distance,near) && F32.is_le(distance,far),distance,uv_interpolate(uv,uv1,uv2,u,v))

def intersect(triangle:Triangle,cull:Cull,origin:Vec3,direction:Vec3,settings:Settings) -> Maybe<&2,Hit>:
  Triangle{Vec3{x,y,z},Vec3{+ax,+ay,+az},Vec3{+bx,+by,+bz},uv,uv1,uv2} = triangle
  Vec3{ox,oy,oz} = origin
  Vec3{+dx,+dy,+dz} = direction
  +px = F32.sub(F32.mul(dy,bz),F32.mul(dz,by))
  +py = F32.sub(F32.mul(dz,bx),F32.mul(dx,bz))
  +pz = F32.sub(F32.mul(dx,by),F32.mul(dy,bx))
  +det = F32.add(F32.mul(ax,px),F32.add(F32.mul(ay,py),F32.mul(az,pz)))
  barycentric_scalar(determinant_valid(cull,det),ax,ay,az,bx,by,bz,dx,dy,dz,F32.sub(ox,x),F32.sub(oy,y),F32.sub(oz,z),px,py,pz,det,uv,uv1,uv2,settings)

def nearer(first:Maybe<&2,Hit>,second:Maybe<&2,Hit>) -> Maybe<&2,Hit>:
  match first second:
    case None{} _: second
    case _ None{}: first
    case Some{Hit{+a,u,v}} Some{Hit{+b,uu,vv}}: P.choose(Maybe<&2,Hit>,first,second,F32.is_le(a,b))

def quad_hit(prepared:Prepared,+origin:Vec3,+direction:Vec3,+settings:Settings) -> Maybe<&2,Hit>:
  Prepared{a,b,material,+cull,order,index,bounds} = prepared
  nearer(intersect(a,cull,origin,direction,settings),intersect(b,cull,origin,direction,settings))

def coordinate(address:Address,+value:F32) -> F32:
  match address:
    case Clamp{}: F32.min(1.0,F32.max(0.0,value))
    case Repeat{}: F32.sub(value,F32.floor(value))

def texel(texture:R.Texture,+address:Address,u:F32,v:F32) -> U32:
  R.Texture{+width,+height,+side,image} = texture
  +x = U32.min(U32.sub(width,1),F32.to_u32(F32.mul(F32.from_nat(U32.to_nat(width)),coordinate(address,u))))
  +y = U32.min(U32.sub(height,1),F32.to_u32(F32.mul(F32.from_nat(U32.to_nat(height)),coordinate(address,v))))
  R.pixel_at(P.array_depth(13n,side,1),image,x,y,side)

def sample(textures:List<&2,R.Texture>,index:Nat,+address:Address,+u:F32,+v:F32) -> U32:
  match textures index:
    case Nil{} _: 4294902015
    case head <> tail 0n: texel(head,address,u,v)
    case head <> tail 1n+p: sample(tail,p,address,u,v)

def channel(+color:U32,shift:Nat) -> U32:
  U32.and(U32.shrn(color,shift),255)

def rgb_channel(texel:U32,tint:U32,light:U32,shade:F32) -> U32:
  F32.to_u32(F32.floor(F32.mul(F32.div(F32.from_nat(U32.to_nat(U32.mul(U32.mul(texel,tint),light))),65025.0),shade)))

def colored(material:Material,+pixel:U32) -> U32:
  Material{texture,+tint,+light,+shade,mode,address} = material
  P.argb(U32.div(U32.mul(channel(pixel,24n),channel(tint,24n)),255),rgb_channel(channel(pixel,16n),channel(tint,16n),channel(light,16n),shade),rgb_channel(channel(pixel,8n),channel(tint,8n),channel(light,8n),shade),rgb_channel(channel(pixel,0n),channel(tint,0n),channel(light,0n),shade))

def hit_color(hit:Hit,+material:Material,textures:List<&2,R.Texture>) -> U32:
  Hit{distance,u,v} = hit
  Material{texture,tint,light,shade,mode,address} = material
  colored(material,sample(textures,U32.to_nat(texture),address,u,v))

def solid(mode:Mode,alpha:U32) -> Bool:
  match mode:
    case Opaque{}: True{}
    case Cutout{threshold}: U32.is_ge(alpha,threshold)
    case Translucent{}: False{}

def before(a:Fragment,b:Fragment) -> Bool:
  match a b:
    case Fragment{+distance,+order,+index,color} Fragment{+other,+other_order,other_index,c}:
      F32.is_lt(distance,other) || (F32.is_eq(distance,other) && (U32.is_lt(order,other_order) || (U32.is_eq(order,other_order) && U32.is_lt(index,other_index))))

def solid_candidate(hit:Maybe<&2,Hit>,prepared:Prepared,+textures:List<&2,R.Texture>,+best:Fragment) -> Fragment:
  match hit prepared:
    case None{} _: best
    case Some{Hit{+distance,+u,+v}} Prepared{a,b,+material,cull,order,index,bounds}:
      Material{texture,tint,light,shade,+mode,address} = material
      +color = hit_color(Hit{distance,u,v},material,textures)
      +candidate : Fragment = Fragment{distance,order,index,U32.or(color,4278190080)}
      P.choose(Fragment,candidate,best,solid(mode,channel(color,24n)) && before(candidate,best))

def opaque_trace(quads:List<&2,Prepared>,+origin:Vec3,+direction:Vec3,+settings:Settings,+textures:List<&2,R.Texture>,best:Fragment) -> Fragment:
  match quads:
    case Nil{}: best
    case +head <> tail: opaque_trace(tail,origin,direction,settings,textures,solid_candidate(quad_hit(head,origin,direction,settings),head,textures,best))

def distance(fragment:Fragment) -> F32:
  Fragment{value,order,index,color} = fragment
  value

def spatial_visible(tree:Spatial,origin:Vec3,direction:Vec3,best:F32) -> Bool:
  match tree:
    case Empty{}: False{}
    case Flat{quads}: True{}
    case Leaf{bounds,quads}: bounds_hit(bounds,origin,direction,best)
    case Branch{bounds,left,right}: bounds_hit(bounds,origin,direction,best)

def spatial_trace(tree:Spatial,+origin:Vec3,+direction:Vec3,+settings:Settings,+textures:List<&2,R.Texture>,+best:Fragment,visible:Bool) -> Fragment:
  match tree visible:
    case _ False{}: best
    case Empty{} _: best
    case Flat{quads} True{}: opaque_trace(quads,origin,direction,settings,textures,best)
    case Leaf{bounds,quads} True{}: opaque_trace(quads,origin,direction,settings,textures,best)
    case Branch{bounds,+left,+right} True{}: spatial_trace(right,origin,direction,settings,textures,spatial_trace(left,origin,direction,settings,textures,best,spatial_visible(left,origin,direction,distance(best))),spatial_visible(right,origin,direction,distance(best)))

# Sorted near-to-far fragments. A tie uses supplied order then source index.
def insert_fragment(fragments:List<&2,Fragment>,+fragment:Fragment) -> List<&2,Fragment>:
  match fragments:
    case Nil{}: [fragment]
    case +head <> +tail: P.choose(List<&2,Fragment>,fragment <> fragments,head <> insert_fragment(tail,fragment),before(fragment,head))

def trans_candidate(hit:Maybe<&2,Hit>,prepared:Prepared,+textures:List<&2,R.Texture>,+best:Fragment,+fragments:List<&2,Fragment>) -> List<&2,Fragment>:
  match hit prepared:
    case None{} _: fragments
    case Some{Hit{+distance,+u,+v}} Prepared{a,b,+material,cull,order,index,bounds}:
      +color = hit_color(Hit{distance,u,v},material,textures)
      +fragment : Fragment = Fragment{distance,order,index,color}
      P.choose(List<&2,Fragment>,insert_fragment(fragments,fragment),fragments,before(fragment,best) && U32.is_gt(channel(color,24n),0))

def trans_selected(mode:Mode,+head:Prepared,+origin:Vec3,+direction:Vec3,+settings:Settings,+textures:List<&2,R.Texture>,+best:Fragment,fragments:List<&2,Fragment>) -> List<&2,Fragment>:
  match mode:
    case Translucent{}: trans_candidate(quad_hit(head,origin,direction,settings),head,textures,best,fragments)
    case _: fragments

def trans_trace(quads:List<&2,Prepared>,+origin:Vec3,+direction:Vec3,+settings:Settings,+textures:List<&2,R.Texture>,+best:Fragment,fragments:List<&2,Fragment>) -> List<&2,Fragment>:
  match quads:
    case Nil{}: fragments
    case +head <> tail:
      Prepared{a,b,Material{texture,tint,light,shade,mode,address},cull,order,index,bounds} = head
      trans_trace(tail,origin,direction,settings,textures,best,trans_selected(mode,head,origin,direction,settings,textures,best,fragments))

def blend_channel(source:U32,target:U32,+alpha:U32) -> U32:
  U32.div(U32.add(U32.mul(source,alpha),U32.mul(target,U32.sub(255,alpha))),255)

def blend(+source:U32,+target:U32) -> U32:
  +alpha = channel(source,24n)
  P.argb(255,blend_channel(channel(source,16n),channel(target,16n),alpha),blend_channel(channel(source,8n),channel(target,8n),alpha),blend_channel(channel(source,0n),channel(target,0n),alpha))

def composite(fragments:List<&2,Fragment>,background:U32) -> U32:
  match fragments:
    case Nil{}: background
    case Fragment{distance,order,index,color} <> tail: blend(color,composite(tail,background))

def basis_value(value:R.Basis,settings:Settings) -> R.Basis:
  R.Basis{x,y,z,rx,rz,ux,uy,uz,fx,fy,fz,old} = value
  Settings{near,far,scale,background} = settings
  R.Basis{x,y,z,rx,rz,ux,uy,uz,fx,fy,fz,scale}

def basis(camera:R.Camera,settings:Settings) -> R.Basis:
  basis_value(R.basis(camera),settings)

def pixel_best(+best:Fragment,quads:List<&2,Prepared>,textures:List<&2,R.Texture>,origin:Vec3,direction:Vec3,settings:Settings) -> U32:
  Fragment{distance,order,index,color} = best
  composite(trans_trace(quads,origin,direction,settings,textures,best,[]),color)

def pixel_direction(tree:Spatial,+quads:List<&2,Prepared>,+textures:List<&2,R.Texture>,camera:R.Basis,+settings:Settings,direction:R.Direction) -> U32:
  R.Basis{x,y,z,rx,rz,ux,uy,uz,fx,fy,fz,scale} = camera
  Settings{near,far,scale,background} = settings
  R.Direction{dx,dy,dz} = direction
  +origin : Vec3 = Vec3{x,y,z}
  +dir : Vec3 = Vec3{dx,dy,dz}
  +best = spatial_trace(tree,origin,dir,settings,textures,Fragment{F32.add(far,1.0),4294967295,4294967295,background},True{})
  pixel_best(best,quads,textures,origin,dir,settings)

def pixel(+tree:Spatial,+quads:List<&2,Prepared>,+textures:List<&2,R.Texture>,+camera:R.Basis,+settings:Settings,+x:U32,+y:U32,+width:U32,+height:U32) -> U32:
  P.choose(U32,pixel_direction(tree,quads,textures,camera,settings,R.direction(camera,x,y,width,height)),0,U32.is_lt(x,width) && U32.is_lt(y,height))

def tile(+n:Nat,+tree:Spatial,+quads:List<&2,Prepared>,+textures:List<&2,R.Texture>,+camera:R.Basis,+settings:Settings,+x:U32,+y:U32,+side:U32,+width:U32,+height:U32) -> Image:
  match n:
    case 0n: Pix{pixel(tree,quads,textures,camera,settings,x,y,width,height)}
    case 1n+p:
      +half = U32.div(side,2)
      Qua{tile(p,tree,quads,textures,camera,settings,x,y,half,width,height),tile(p,tree,quads,textures,camera,settings,U32.add(x,half),y,half,width,height),tile(p,tree,quads,textures,camera,settings,x,U32.add(y,half),half,width,height),tile(p,tree,quads,textures,camera,settings,U32.add(x,half),U32.add(y,half),half,width,height)}

def frame(+n:Nat,+tree:Spatial,+quads:List<&2,Prepared>,+textures:List<&2,R.Texture>,+camera:R.Basis,+settings:Settings,+x:U32,+y:U32,+side:U32,+width:U32,+height:U32) -> Image:
  match n:
    case 0n: tile(2n,tree,quads,textures,camera,settings,x,y,side,width,height)
    case 1n+p:
      +half = U32.div(side,2)
      a b c d = frame(p,tree,quads,textures,camera,settings,x,y,half,width,height) frame(p,tree,quads,textures,camera,settings,U32.add(x,half),y,half,width,height)
        frame(p,tree,quads,textures,camera,settings,x,U32.add(y,half),half,width,height) frame(p,tree,quads,textures,camera,settings,U32.add(x,half),U32.add(y,half),half,width,height)
      Qua{a,b,c,d}

def render_prepared(pair:List<&2,Prepared> & List<&2,Prepared>,camera:R.Camera,+settings:Settings,+textures:List<&2,R.Texture>,+width:U32,+height:U32,accelerated:Bool) -> Image:
  (+opaque,alpha) = pair
  +depth = Presentation.depth(width,height)
  frame(Nat.sub(depth,2n),P.choose(Spatial,spatial(10n,opaque,leaf_ready(opaque)),Flat{opaque},accelerated),alpha,textures,basis(camera,settings),settings,0,0,U32.shln(1,depth),width,height)

def render_valid(error:String,scene:Scene,+textures:List<&2,R.Texture>,+width:U32,+height:U32,accelerated:Bool) -> Result<&2,&2,Error,Image>:
  match error:
    case "":
      Scene{camera,quads,+settings} = scene
      Done{render_prepared(separate(prepare(quads,0)),camera,settings,textures,width,height,accelerated)}
    case _: Fail{Error{error}}

def render_mode(+scene:Scene,assets:R.Assets,+width:U32,+height:U32,accelerated:Bool) -> R.Assets & Result<&2,&2,Error,Image>:
  R.Assets{+textures} = assets
  (R.Assets{textures},render_valid(validation(scene,textures,width,height),scene,textures,width,height,accelerated))

def render(scene:Scene,assets:R.Assets,width:U32,height:U32) -> R.Assets & Result<&2,&2,Error,Image>:
  render_mode(scene,assets,width,height,True{})

def render_flat(scene:Scene,assets:R.Assets,width:U32,height:U32) -> R.Assets & Result<&2,&2,Error,Image>:
  render_mode(scene,assets,width,height,False{})
