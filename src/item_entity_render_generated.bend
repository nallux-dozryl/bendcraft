import Base
import ./block_model.bend as B
import ./client_render.bend as R
import ./png.bend as P

# Pinned26.3 ItemModelGenerator now emits one side quad per exposed pixel,
# with0.1pixel UV inset. This is actual resource alpha, not a canned sprite.
def coordinate(n:U32) -> F32: F32.from_nat(U32.to_nat(n))
def face(direction:B.Direction,uv:B.UV,+slot:String,tint:U32) -> B.Face:
  B.Face{direction,None{},Some{uv},0,slot,tint}
def front(+slot:String,+tint:U32) -> B.Element:
  B.Element{B.Vec3{0.0,0.0,7.5},B.Vec3{16.0,16.0,8.5},None{},
    [face(B.South{},B.UV{0.0,0.0,16.0,16.0},slot,tint),face(B.North{},B.UV{16.0,0.0,0.0,16.0},slot,tint)],0,None{}}
def opaque_inside(inside:Bool,texture:R.Texture,x:U32,y:U32) -> Bool:
  match inside:
    case False{}: False{}
    case True{}:
      R.Texture{width,height,+side,image} = texture
      U32.is_ne(U32.and(U32.shrn(R.pixel_at(P.array_depth(13n,side,1),image,x,y,side),24n),255),0)
def opaque(+texture:R.Texture,+x:U32,+y:U32) -> Bool:
  R.Texture{width,height,side,image} = texture
  opaque_inside(U32.is_lt(x,width) && U32.is_lt(y,height),texture,x,y)
def edge(d:B.Direction,+x:U32,+y:U32) -> U32 & U32:
  match d:
    case B.Up{}: (x,U32.sub(y,1))
    case B.Down{}: (x,U32.inc(y))
    case B.East{}: (U32.sub(x,1),y)
    case _: (U32.inc(x),y)
def neighbor(texture:R.Texture,position:U32 & U32) -> Bool:
  (x,y) = position
  opaque(texture,x,y)
def inset_uv(direction:B.Direction,+x:F32,+y:F32,+sx:F32,+sy:F32) -> B.UV:
  match direction:
    case B.East{}: B.UV{F32.mul(F32.add(x,0.1),sx),F32.mul(F32.sub(F32.add(y,1.0),0.1),sy),F32.mul(F32.sub(F32.add(x,1.0),0.1),sx),F32.mul(F32.add(y,0.1),sy)}
    case B.West{}: B.UV{F32.mul(F32.add(x,0.1),sx),F32.mul(F32.sub(F32.add(y,1.0),0.1),sy),F32.mul(F32.sub(F32.add(x,1.0),0.1),sx),F32.mul(F32.add(y,0.1),sy)}
    case _: B.UV{F32.mul(F32.add(x,0.1),sx),F32.mul(F32.add(y,0.1),sy),F32.mul(F32.sub(F32.add(x,1.0),0.1),sx),F32.mul(F32.sub(F32.add(y,1.0),0.1),sy)}
def side_bounds(direction:B.Direction,+x:F32,+y:F32,+sx:F32,+sy:F32) -> B.Vec3 & B.Vec3:
  match direction:
    case B.Up{}: (B.Vec3{F32.mul(x,sx),F32.sub(16.0,F32.mul(y,sy)),7.5},B.Vec3{F32.mul(F32.add(x,1.0),sx),F32.sub(16.0,F32.mul(y,sy)),8.5})
    case B.Down{}: (B.Vec3{F32.mul(x,sx),F32.sub(16.0,F32.mul(F32.add(y,1.0),sy)),7.5},B.Vec3{F32.mul(F32.add(x,1.0),sx),F32.sub(16.0,F32.mul(F32.add(y,1.0),sy)),8.5})
    case B.East{}: (B.Vec3{F32.mul(x,sx),F32.sub(16.0,F32.mul(y,sy)),7.5},B.Vec3{F32.mul(x,sx),F32.sub(16.0,F32.mul(F32.add(y,1.0),sy)),8.5})
    case _: (B.Vec3{F32.mul(F32.add(x,1.0),sx),F32.sub(16.0,F32.mul(y,sy)),7.5},B.Vec3{F32.mul(F32.add(x,1.0),sx),F32.sub(16.0,F32.mul(F32.add(y,1.0),sy)),8.5})
def side_element(bounds:B.Vec3 & B.Vec3,direction:B.Direction,uv:B.UV,slot:String,tint:U32) -> B.Element:
  (low,high) = bounds
  B.Element{low,high,None{},[face(direction,uv,slot,tint)],0,None{}}
def side(+direction:B.Direction,x:U32,y:U32,width:U32,height:U32,slot:String,tint:U32) -> B.Element:
  +xx = coordinate(x)
  +yy = coordinate(y)
  +sx = F32.div(16.0,coordinate(width))
  +sy = F32.div(16.0,coordinate(height))
  side_element(side_bounds(direction,xx,yy,sx,sy),direction,inset_uv(direction,xx,yy,sx,sy),slot,tint)
def add_edge(exposed:Bool,direction:B.Direction,x:U32,y:U32,width:U32,height:U32,slot:String,tint:U32,rest:List<&2,B.Element>) -> List<&2,B.Element>:
  match exposed:
    case False{}: rest
    case True{}: side(direction,x,y,width,height,slot,tint) <> rest
def directions(values:List<&2,B.Direction>,+texture:R.Texture,+x:U32,+y:U32,+width:U32,+height:U32,+slot:String,+tint:U32,rest:List<&2,B.Element>) -> List<&2,B.Element>:
  match values:
    case Nil{}: rest
    case +head <> tail: add_edge(Bool.not(neighbor(texture,edge(head,x,y))),head,x,y,width,height,slot,tint,directions(tail,texture,x,y,width,height,slot,tint,rest))
def pixel_edges(visible:Bool,+texture:R.Texture,+x:U32,+y:U32,+width:U32,+height:U32,+slot:String,+tint:U32,rest:List<&2,B.Element>) -> List<&2,B.Element>:
  match visible:
    case False{}: rest
    case True{}: directions([B.Up{},B.Down{},B.East{},B.West{}],texture,x,y,width,height,slot,tint,rest)
def pixels(left:Nat,+texture:R.Texture,+index:U32,+width:U32,+height:U32,+slot:String,+tint:U32) -> List<&2,B.Element>:
  match left:
    case 0n: []
    case 1n+rest:
      +x = U32.mod(index,width)
      +y = U32.div(index,width)
      pixel_edges(opaque(texture,x,y),texture,x,y,width,height,slot,tint,pixels(rest,texture,U32.inc(index),width,height,slot,tint))
def elements(+texture:R.Texture,+slot:String,+tint:U32) -> List<&2,B.Element>:
  R.Texture{+width,+height,side,image} = texture
  front(slot,tint) <> pixels(U32.to_nat(U32.mul(width,height)),texture,0,width,height,slot,tint)
