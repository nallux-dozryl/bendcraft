import Base
import ./block_model.bend as B

# Immutable receiver observations, bound to the same real publication stamp.
# They never own or replace Core or the block/sky field.
type Stamp is Data:
  Stamp{registry:String,dimension:String,tick:Nat,revision:Nat}
type Position is Data:
  Position{x:U32,y:U32,z:U32}
type StateInfo is Data:
  StateInfo{state:U32,emission:U32,emissive:Bool,solid:Bool,collision_full:Bool,
    permeable:Bool,shade:F32}
type Cell is Data:
  Cell{position:Position,info:Maybe<&2,StateInfo>,block:Maybe<&2,U32>,sky:Maybe<&2,U32>}
type Cardinal is Data:
  Cardinal{down:F32,up:F32,north:F32,south:F32,west:F32,east:F32}
type Quad is Data:
  Quad{a:B.Vec3,b:B.Vec3,c:B.Vec3,d:B.Vec3,direction:B.Direction,
    shade_override:Maybe<&2,B.Direction>,emission:U32}
type Mode is Data:
  Smooth{}
  Flat{known:Maybe<&2,U32>}
type Request is Data:
  Request{stamp:Stamp,origin:Position,source:StateInfo,quad:Quad,mode:Mode}
type Context is Data:
  Context{stamp:Stamp,cells:List<&2,Cell>,cardinal:Maybe<&2,Cardinal>}
type Vertex is Data:
  Vertex{raw_light:U32,light:U32,color:U32}
type Appearance is Data:
  Appearance{a:Vertex,b:Vertex,c:Vertex,d:Vertex}
type Error is Data:
  Refused{message:String}
type Bounds is Data:
  Bounds{minimum:B.Vec3,maximum:B.Vec3,cubic:Bool,partial:Bool}
type Weights is Data:
  Weights{a:F32,b:F32,c:F32,d:F32}
type Adjacency is Data:
  Adjacency{a:B.Direction,b:B.Direction,c:B.Direction,d:B.Direction,
    w0:List<&2,U32>,w1:List<&2,U32>,w2:List<&2,U32>,w3:List<&2,U32>,
    r0:U32,r1:U32,r2:U32,r3:U32,weighted:Bool}
type Corner is Data:
  Corner{light:U32,shade:F32}
type Corners is Data:
  Corners{a:Corner,b:Corner,c:Corner,d:Corner}
