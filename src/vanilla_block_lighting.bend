import Base
import ./vanilla_block_lighting_model.bend as M
import ./vanilla_block_lighting_math.bend as F
import ./vanilla_block_lighting_geometry.bend as G
import ./vanilla_block_lighting_tables.bend as Tables
import ./block_model.bend as B

def guard(valid:Bool,message:String) -> Result<&2,&2,M.Error,Unit>:
  match valid:
    case True{}: Done{Unit{}}
    case False{}: Fail{M.Refused{message}}
def same_stamp(a:M.Stamp,b:M.Stamp) -> Bool:
  M.Stamp{r,d,t,v}=a
  M.Stamp{x,y,z,w}=b
  String.eq(r,x) && String.eq(d,y) && Nat.is_eq(t,z) && Nat.is_eq(v,w)
def state_valid(value:M.StateInfo) -> Bool:
  M.StateInfo{id,emission,emissive,solid,full,permeable,shade}=value
  U32.is_lt(emission,16) && F.unit(shade)
def quad_valid(q:M.Quad) -> Bool:
  M.Quad{a,b,c,d,direction,override,emission}=q
  G.vector_valid(a) && G.vector_valid(b) && G.vector_valid(c) && G.vector_valid(d) && U32.is_lt(emission,16)
def cardinal_valid(value:M.Cardinal) -> Bool:
  M.Cardinal{a,b,c,d,e,f}=value
  F.unit(a) && F.unit(b) && F.unit(c) && F.unit(d) && F.unit(e) && F.unit(f)
def bool_eq(+a:Bool,+b:Bool) -> Bool: (a && b) || (Bool.not(a) && Bool.not(b))
def state_shade(info:M.StateInfo) -> F32:
  M.StateInfo{id,e,r,s,f,p,h}=info
  h
def state_permeable(info:M.StateInfo) -> Bool:
  M.StateInfo{id,e,r,s,f,p,h}=info
  p
def same_state(a:M.StateInfo,b:M.StateInfo) -> Bool:
  M.StateInfo{id,e,r,s,f,p,h}=a
  M.StateInfo{v,a,b,c,d,g,k}=b
  U32.is_eq(id,v) && U32.is_eq(e,a) && bool_eq(r,b) && bool_eq(s,c) && bool_eq(f,d) && bool_eq(p,g) && U32.is_eq(F32.bits(h),F32.bits(k))
def count(values:List<&2,M.Cell>,+point:M.Position) -> Nat:
  match values:
    case Nil{}: 0n
    case M.Cell{p,i,b,s} <> rest: Nat.add(F.choose(Nat,1n,0n,G.same(p,point)),count(rest,point))
def found_gate(cell:M.Cell,same:Bool,continue:Unit -> Result<&2,&2,M.Error,M.Cell>) -> Result<&2,&2,M.Error,M.Cell>:
  match same:
    case True{}: Done{cell}
    case False{}: continue(Unit{})
def found(cells:List<&2,M.Cell>,+point:M.Position) -> Result<&2,&2,M.Error,M.Cell>:
  match cells:
    case Nil{}: Fail{M.Refused{"block lighting: actual world cell unavailable"}}
    case +cell <> rest:
      M.Cell{+p,info,block,sky}=cell
      found_gate(cell,G.same(p,point),u => found(rest,point))
def cell(+context:M.Context,+point:M.Position) -> Result<&2,&2,M.Error,M.Cell>:
  M.Context{stamp,+cells,cardinal}=context
  do Result<&2,&2,M.Error,M.Cell>:
    _ : Unit <- guard(Nat.is_eq(count(cells,point),1n),"block lighting: actual world cell missing or duplicated")
    found(cells,point)
def information(value:M.Cell) -> Result<&2,&2,M.Error,M.StateInfo>:
  match value:
    case M.Cell{p,None{},block,sky}: Fail{M.Refused{"block lighting: actual state properties unavailable"}}
    case M.Cell{p,Some{+info},block,sky}:
      do Result<&2,&2,M.Error,M.StateInfo>:
        _ : Unit <- guard(state_valid(info),"block lighting: actual state properties invalid")
        return info
def info(context:M.Context,point:M.Position) -> Result<&2,&2,M.Error,M.StateInfo>:
  do Result<&2,&2,M.Error,M.StateInfo>:
    value : M.Cell <- cell(context,point)
    information(value)
def levels(value:M.Cell,emission:U32) -> Result<&2,&2,M.Error,U32>:
  match value:
    case M.Cell{p,i,Some{+block},Some{+sky}}:
      do Result<&2,&2,M.Error,U32>:
        _ : Unit <- guard(U32.is_lt(block,16) && U32.is_lt(sky,16),"block lighting: raw brightness outside0..15")
        return F.pack(U32.max(block,emission),sky)
    case _: Fail{M.Refused{"block lighting: actual raw block/sky brightness unavailable"}}
def light_gate(context:M.Context,point:M.Position,emission:U32,emissive:Bool) -> Result<&2,&2,M.Error,U32>:
  match emissive:
    case True{}: Done{15728880}
    case False{}:
      do Result<&2,&2,M.Error,U32>:
        value : M.Cell <- cell(context,point)
        levels(value,emission)
def light(context:M.Context,point:M.Position,source:M.StateInfo) -> Result<&2,&2,M.Error,U32>:
  M.StateInfo{id,e,emissive,solid,full,permeable,shade}=source
  light_gate(context,point,e,emissive)
def sample(+context:M.Context,+point:M.Position) -> Result<&2,&2,M.Error,M.Corner>:
  do Result<&2,&2,M.Error,M.Corner>:
    +actual : M.StateInfo <- info(context,point)
    coords : U32 <- light(context,point,actual)
    return M.Corner{coords,state_shade(actual)}
def permeable(context:M.Context,point:M.Position) -> Result<&2,&2,M.Error,Bool>:
  do Result<&2,&2,M.Error,Bool>:
    actual : M.StateInfo <- info(context,point)
    return state_permeable(actual)
def side(value:M.Cardinal,direction:B.Direction) -> F32:
  M.Cardinal{+a,+b,+c,+d,+e,+f}=value
  match direction:
    case B.Down{}: a
    case B.Up{}: b
    case B.North{}: c
    case B.South{}: d
    case B.West{}: e
    case B.East{}: f
def shade_direction(override:Maybe<&2,B.Direction>,fallback:B.Direction) -> B.Direction:
  match override:
    case None{}: fallback
    case Some{value}: value
def cardinal(q:M.Quad,value:Maybe<&2,M.Cardinal>) -> Result<&2,&2,M.Error,F32>:
  M.Quad{a,b,c,d,direction,override,e}=q
  match value:
    case None{}: Fail{M.Refused{"block lighting: actual CardinalLighting unavailable"}}
    case Some{+actual}:
      do Result<&2,&2,M.Error,F32>:
        _ : Unit <- guard(cardinal_valid(actual),"block lighting: CardinalLighting invalid")
        return side(actual,shade_direction(override,direction))
def source_checked(+context:M.Context,+origin:M.Position,+source:M.StateInfo) -> Result<&2,&2,M.Error,Unit>:
  do Result<&2,&2,M.Error,Unit>:
    actual : M.StateInfo <- info(context,origin)
    guard(same_state(actual,source),"block lighting: source state differs from actual captured cell")
def mean_corner(a:M.Corner,b:M.Corner,c:M.Corner,center:M.Corner) -> M.Corner:
  M.Corner{x,r}=a
  M.Corner{y,s}=b
  M.Corner{z,t}=c
  M.Corner{w,u}=center
  M.Corner{F.blend(x,y,z,w),F.mean(r,s,t,u)}
def diagonal(context:M.Context,point:M.Position,fallback:M.Corner,open:Bool) -> Result<&2,&2,M.Error,M.Corner>:
  match open:
    case False{}: Done{fallback}
    case True{}: sample(context,point)
def light_gate_pick(context:M.Context,face:M.Position,neighbour:M.StateInfo,current:U32,near:Bool) -> Result<&2,&2,M.Error,U32>:
  match near:
    case False{}: Done{current}
    case True{}: light(context,face,neighbour)
def centered_light(+context:M.Context,+origin:M.Position,+source:M.StateInfo,+face:M.Position,+neighbour:M.StateInfo,cubic:Bool) -> Result<&2,&2,M.Error,U32>:
  M.StateInfo{id,e,r,+solid,f,p,h}=neighbour
  do Result<&2,&2,M.Error,U32>:
    current : U32 <- light(context,origin,source)
    # Java fetches source brightness first even when the adjacent result wins.
    light_gate_pick(context,face,neighbour,current,cubic || Bool.not(solid))

def smooth_corners(+context:M.Context,+origin:M.Position,+source:M.StateInfo,+direction:B.Direction,+bounds:M.Bounds,+adj:M.Adjacency) -> Result<&2,&2,M.Error,M.Corners>:
  M.Bounds{low,high,+cubic,partial}=bounds
  M.Adjacency{+a,+b,+c,+d,w0,w1,w2,w3,r0,r1,r2,r3,weighted}=adj
  +base=F.choose(M.Position,G.offset(origin,direction),origin,cubic)
  +face=G.offset(origin,direction)
  do Result<&2,&2,M.Error,M.Corners>:
    +edge0 : M.Corner <- sample(context,G.offset(base,a))
    +edge1 : M.Corner <- sample(context,G.offset(base,b))
    +edge2 : M.Corner <- sample(context,G.offset(base,c))
    +edge3 : M.Corner <- sample(context,G.offset(base,d))
    +open0 : Bool <- permeable(context,G.offset(G.offset(base,a),direction))
    +open1 : Bool <- permeable(context,G.offset(G.offset(base,b),direction))
    +open2 : Bool <- permeable(context,G.offset(G.offset(base,c),direction))
    +open3 : Bool <- permeable(context,G.offset(G.offset(base,d),direction))
    diagonal02 : M.Corner <- diagonal(context,G.offset(G.offset(base,a),c),edge0,open0 || open2)
    diagonal03 : M.Corner <- diagonal(context,G.offset(G.offset(base,a),d),edge0,open0 || open3)
    diagonal12 : M.Corner <- diagonal(context,G.offset(G.offset(base,b),c),edge0,open1 || open2)
    diagonal13 : M.Corner <- diagonal(context,G.offset(G.offset(base,b),d),edge0,open1 || open3)
    neighbour : M.StateInfo <- info(context,face)
    coords : U32 <- centered_light(context,origin,source,face,neighbour,cubic)
    brightness : M.StateInfo <- info(context,base)
    +center : M.Corner = M.Corner{coords,state_shade(brightness)}
    return M.Corners{mean_corner(edge3,edge0,diagonal03,center),mean_corner(edge2,edge0,diagonal02,center),mean_corner(edge2,edge1,diagonal12,center),mean_corner(edge3,edge1,diagonal13,center)}
def weighted_corner(corners:M.Corners,+weights:M.Weights) -> M.Corner:
  M.Corners{M.Corner{a,r},M.Corner{b,s},M.Corner{c,t},M.Corner{d,u}}=corners
  M.Corner{F.weighted_light(a,b,c,d,weights),F32.clamp(F.weighted(r,s,t,u,weights),0.0,1.0)}
def corners_weighted(+corners:M.Corners,+bounds:M.Bounds,adj:M.Adjacency) -> M.Corners:
  M.Adjacency{a,b,c,d,w0,w1,w2,w3,r0,r1,r2,r3,weighted}=adj
  M.Corners{weighted_corner(corners,G.weights(bounds,w0)),weighted_corner(corners,G.weights(bounds,w1)),weighted_corner(corners,G.weights(bounds,w2)),weighted_corner(corners,G.weights(bounds,w3))}
def weighted_gate(+corners:M.Corners,bounds:M.Bounds,adj:M.Adjacency,partial:Bool) -> M.Corners:
  match partial:
    case False{}: corners
    case True{}: corners_weighted(corners,bounds,adj)
def shaped_corners(+corners:M.Corners,+bounds:M.Bounds,+adj:M.Adjacency) -> M.Corners:
  M.Bounds{low,high,cubic,+partial}=bounds
  M.Adjacency{a,b,c,d,w0,w1,w2,w3,r0,r1,r2,r3,+weighted}=adj
  weighted_gate(corners,bounds,adj,partial && weighted)
def corner_vertex(corner:M.Corner,side:F32,emission:U32) -> M.Vertex:
  M.Corner{light,brightness}=corner
  F.vertex(light,brightness,side,emission)
def vertex_at(+a:M.Vertex,+b:M.Vertex,+c:M.Vertex,+d:M.Vertex,+r0:U32,+r1:U32,+r2:U32,+index:U32) -> M.Vertex:
  F.choose(M.Vertex,a,F.choose(M.Vertex,b,F.choose(M.Vertex,c,d,U32.is_eq(r2,index)),U32.is_eq(r1,index)),U32.is_eq(r0,index))
def appeared(corners:M.Corners,adj:M.Adjacency,+side:F32,+emission:U32) -> M.Appearance:
  M.Corners{a,b,c,d}=corners
  M.Adjacency{x,y,z,t,w0,w1,w2,w3,+r0,+r1,+r2,r3,weighted}=adj
  +a=corner_vertex(a,side,emission)
  +b=corner_vertex(b,side,emission)
  +c=corner_vertex(c,side,emission)
  +d=corner_vertex(d,side,emission)
  M.Appearance{vertex_at(a,b,c,d,r0,r1,r2,0),vertex_at(a,b,c,d,r0,r1,r2,1),vertex_at(a,b,c,d,r0,r1,r2,2),vertex_at(a,b,c,d,r0,r1,r2,3)}
def smooth(+context:M.Context,+origin:M.Position,+source:M.StateInfo,+quad:M.Quad,side:F32) -> Result<&2,&2,M.Error,M.Appearance>:
  M.StateInfo{id,e,r,s,+full,p,h}=source
  M.Quad{a,b,c,d,+direction,override,+emission}=quad
  +bounds=G.shape(quad,full)
  +adj=Tables.adjacency(direction)
  do Result<&2,&2,M.Error,M.Appearance>:
    corners : M.Corners <- smooth_corners(context,origin,source,direction,bounds,adj)
    return appeared(shaped_corners(corners,bounds,adj),adj,side,emission)
def flat_appearance(+light:U32,+side:F32,+emission:U32) -> M.Appearance:
  +vertex=F.flat_vertex(light,side,emission)
  M.Appearance{vertex,vertex,vertex,vertex}
def flat_unknown(+context:M.Context,+origin:M.Position,source:M.StateInfo,+direction:B.Direction,+emission:U32,+side:F32,bounds:M.Bounds) -> Result<&2,&2,M.Error,M.Appearance>:
  M.Bounds{low,high,cubic,partial}=bounds
  do Result<&2,&2,M.Error,M.Appearance>:
    coords : U32 <- light(context,F.choose(M.Position,G.offset(origin,direction),origin,cubic),source)
    return flat_appearance(coords,side,emission)
def flat(+context:M.Context,+origin:M.Position,+source:M.StateInfo,+quad:M.Quad,side:F32,known:Maybe<&2,U32>) -> Result<&2,&2,M.Error,M.Appearance>:
  M.StateInfo{id,e,r,s,+full,p,h}=source
  M.Quad{a,b,c,d,+direction,override,+emission}=quad
  match known:
    case Some{light}: Done{flat_appearance(light,side,emission)}
    case None{}:
      flat_unknown(context,origin,source,direction,emission,side,G.shape(quad,full))
def resolved(+context:M.Context,request:M.Request,side:F32) -> Result<&2,&2,M.Error,M.Appearance>:
  M.Request{stamp,origin,source,quad,mode}=request
  match mode:
    case M.Smooth{}: smooth(context,origin,source,quad,side)
    case M.Flat{known}: flat(context,origin,source,quad,side,known)
def resolve(+request:M.Request,+context:M.Context) -> Result<&2,&2,M.Error,M.Appearance>:
  M.Request{+stamp,+origin,+source,+quad,mode}=request
  M.Context{+actual,cells,+cardinals}=context
  do Result<&2,&2,M.Error,M.Appearance>:
    _ : Unit <- guard(same_stamp(stamp,actual),"block lighting: stale or different world/catalog stamp")
    _ : Unit <- guard(state_valid(source) && quad_valid(quad),"block lighting: nonfinite geometry or invalid source/emission")
    _ : Unit <- source_checked(context,origin,source)
    brightness : F32 <- cardinal(quad,cardinals)
    resolved(context,request,brightness)
# Actual ModelBlockRenderer chooses AO once using the FIRST collected part.
# gui_light/block-light item flags do not replace this world-render selection.
def mode(+ambient_option:Bool,+first_part_ao:Bool,+source_emission:U32,flat:Maybe<&2,U32>) -> M.Mode:
  F.choose(M.Mode,M.Smooth{},M.Flat{flat},ambient_option && first_part_ao && U32.is_eq(source_emission,0))
def stencil_smooth(+origin:M.Position,+quad:M.Quad,+bounds:M.Bounds,adj:M.Adjacency) -> List<&2,M.Position>:
  M.Quad{v0,v1,v2,v3,+direction,override,e}=quad
  M.Bounds{low,high,cubic,partial}=bounds
  M.Adjacency{+a,+b,+c,+d,w0,w1,w2,w3,r0,r1,r2,r3,weighted}=adj
  +base=F.choose(M.Position,G.offset(origin,direction),origin,cubic)
  G.unique([origin,G.offset(origin,direction),G.offset(base,a),G.offset(base,b),G.offset(base,c),G.offset(base,d),G.offset(G.offset(base,a),direction),G.offset(G.offset(base,b),direction),G.offset(G.offset(base,c),direction),G.offset(G.offset(base,d),direction),G.offset(G.offset(base,a),c),G.offset(G.offset(base,a),d),G.offset(G.offset(base,b),c),G.offset(G.offset(base,b),d)],[])
def flat_stencil(+origin:M.Position,+direction:B.Direction,bounds:M.Bounds) -> List<&2,M.Position>:
  M.Bounds{low,high,cubic,partial}=bounds
  G.unique([origin,F.choose(M.Position,G.offset(origin,direction),origin,cubic)],[])
def stencil(request:M.Request) -> List<&2,M.Position>:
  M.Request{stamp,+origin,M.StateInfo{id,e,r,s,+full,p,h},+quad,mode}=request
  M.Quad{a,b,c,d,+direction,override,emission}=quad
  match mode:
    case M.Smooth{}: stencil_smooth(origin,quad,G.shape(quad,full),Tables.adjacency(direction))
    case M.Flat{Some{coords}}: [origin]
    case M.Flat{None{}}:
      flat_stencil(origin,direction,G.shape(quad,full))
