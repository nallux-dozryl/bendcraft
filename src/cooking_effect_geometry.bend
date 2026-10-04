import Base
import ./f64.bend as F
import ./geometry.bend as A
import ./vanilla_entity_fields.bend as V
import ./cooking_effect_entities_model.bend as E
import ./cooking_effect_geometry_voxel.bend as S

type Obstacle is Data:
  Obstacle{box:A.AABB,shape:S.Shape,full:Bool}
type Context is Data:
  Context{dimension:String,coverage:A.AABB,blocks:List<&2,Obstacle>,entities:List<&2,A.AABB>,voxel_budget:U32}
type Prepared is Data:
  Prepared{point:V.Vec3,body:A.AABB,center:V.Vec3,search:S.Shape,outer:A.AABB}

def quarter() -> F.F64: F.from_f32(0.25)
def half() -> F.F64: F.from_f32(0.5)
def shift_y(point:V.Vec3,y:F.F64) -> V.Vec3:
  V.Vec3{x,v,z} = point
  V.Vec3{x,F.add(v,y),z}
def body(point:V.Vec3) -> A.AABB:
  V.Vec3{+x,+y,+z} = point
  A.AABB{F.sub(x,quarter()),y,F.sub(z,quarter()),F.add(x,quarter()),F.add(y,half()),F.add(z,quarter())}
def search_box(center:V.Vec3) -> A.AABB:
  V.Vec3{+x,+y,+z} = center
  A.AABB{F.sub(x,quarter()),F.sub(y,quarter()),F.sub(z,quarter()),F.add(x,quarter()),F.add(y,quarter()),F.add(z,quarter())}
def inflate(box:A.AABB,+amount:F.F64) -> A.AABB:
  A.AABB{a,b,c,d,e,f} = box
  A.AABB{F.sub(a,amount),F.sub(b,amount),F.sub(c,amount),F.add(d,amount),F.add(e,amount),F.add(f,amount)}
def enclosing(a:A.AABB,b:A.AABB) -> A.AABB:
  A.AABB{ax,ay,az,bx,by,bz} = a
  A.AABB{cx,cy,cz,dx,dy,dz} = b
  A.AABB{A.math_min(ax,cx),A.math_min(ay,cy),A.math_min(az,cz),A.math_max(bx,dx),A.math_max(by,dy),A.math_max(bz,dz)}
def bounds_more(values:List<&2,A.AABB>,current:A.AABB) -> A.AABB:
  match values:
    case Nil{}: current
    case value <> rest: bounds_more(rest,enclosing(current,value))
def shape_bounds(values:List<&2,A.AABB>) -> Result<&2,&2,String,A.AABB>:
  match values:
    case Nil{}: Fail{"geometry:empty-search"}
    case head <> rest: Done{bounds_more(rest,head)}
def prepared(+point:V.Vec3,+search:S.Shape,bounds:A.AABB) -> Prepared:
  Prepared{point,body(point),shift_y(point,quarter()),search,inflate(bounds,half())}
def prepare(+point:V.Vec3) -> Result<&2,&2,String,Prepared>:
  do Result<&2,&2,String,Prepared>:
    +search : S.Shape <- S.create(search_box(shift_y(point,quarter())))
    bounds : A.AABB <- shape_bounds(S.boxes(search))
    return prepared(point,search,bounds)
def contained(query:A.AABB,interior:A.AABB) -> Bool:
  A.AABB{a,b,c,d,e,f} = query
  A.AABB{x,y,z,u,v,w} = interior
  F.is_ge(a,x) && F.is_ge(b,y) && F.is_ge(c,z) && F.is_le(d,u) && F.is_le(e,v) && F.is_le(f,w)
def guard(valid:Bool,error:String) -> Result<&2,&2,String,Unit>:
  match valid:
    case True{}: Done{Unit{}}
    case False{}: Fail{error}
def shape_empty(shape:S.Shape) -> Bool:
  S.Shape{x,y,z,cells} = shape
  List.is_empty(&2,S.Cell,cells)
def intersects_partial(shape:S.Shape,query:S.Shape,budget:U32) -> Result<&2,&2,String,Bool>:
  do Result<&2,&2,String,Bool>:
    overlap : S.Shape <- S.join_unoptimized_limited(shape,query,0,budget)
    return Bool.not(shape_empty(overlap))
def obstacle_hit(obstacle:Obstacle,+query:A.AABB,shape:S.Shape,budget:U32) -> Result<&2,&2,String,Bool>:
  match obstacle:
    case Obstacle{box,source,True{}}: Done{A.AABB.intersects(box,query)}
    case Obstacle{box,source,False{}}: intersects_partial(source,shape,budget)
def hit_more(hit:Bool,next:Unit -> Result<&2,&2,String,Bool>) -> Result<&2,&2,String,Bool>:
  match hit:
    case True{}: Done{True{}}
    case False{}: next(Unit{})
def blocks_hit(values:List<&2,Obstacle>,+query:A.AABB,+shape:S.Shape,+budget:U32) -> Result<&2,&2,String,Bool>:
  match values:
    case Nil{}: Done{False{}}
    case head <> rest:
      do Result<&2,&2,String,Bool>:
        hit : Bool <- obstacle_hit(head,query,shape,budget)
        hit_more(hit,u => blocks_hit(rest,query,shape,budget))
def entities_hit(values:List<&2,A.AABB>,+query:A.AABB) -> Bool:
  match values:
    case Nil{}: False{}
    case box <> rest: A.AABB.intersects(box,query) || entities_hit(rest,query)
def no_collision_more(hit:Bool,entities:List<&2,A.AABB>,query:A.AABB) -> Bool:
  Bool.not(hit || entities_hit(entities,query))
def no_collision(context:Context,+query:A.AABB) -> Result<&2,&2,String,Bool>:
  Context{dimension,coverage,blocks,entities,+budget} = context
  do Result<&2,&2,String,Bool>:
    guard(contained(query,coverage),"geometry:body-outside-captured-region")
    shape : S.Shape <- S.create(query)
    hit : Bool <- blocks_hit(blocks,query,shape,budget)
    return no_collision_more(hit,entities,query)
def union_intersecting(obstacle:Obstacle,current:S.Shape,budget:U32) -> Result<&2,&2,String,S.Shape>:
  Obstacle{box,shape,full} = obstacle
  do Result<&2,&2,String,S.Shape>:
    inflated : S.Shape <- S.create(inflate(box,quarter()))
    S.join_limited(current,inflated,1,budget)
def union_hit(obstacle:Obstacle,current:S.Shape,budget:U32,hit:Bool) -> Result<&2,&2,String,S.Shape>:
  match hit:
    case False{}: Done{current}
    case True{}: union_intersecting(obstacle,current,budget)
def union_blocks(values:List<&2,Obstacle>,+outer:A.AABB,+query:S.Shape,+budget:U32,current:S.Shape) -> Result<&2,&2,String,S.Shape>:
  match values:
    case Nil{}: Done{current}
    case +head <> rest:
      do Result<&2,&2,String,S.Shape>:
        hit : Bool <- obstacle_hit(head,outer,query,budget)
        next : S.Shape <- union_hit(head,current,budget,hit)
        union_blocks(rest,outer,query,budget,next)
def free_position(context:Context,+search:S.Shape,point:V.Vec3,+outer:A.AABB) -> Result<&2,&2,String,Maybe<&2,V.Vec3>>:
  Context{dimension,coverage,blocks,entities,+budget} = context
  do Result<&2,&2,String,Maybe<&2,V.Vec3>>:
    guard(contained(outer,coverage),"geometry:search-outside-captured-region")
    query : S.Shape <- S.create(outer)
    colliders : S.Shape <- union_blocks(blocks,outer,query,budget,S.empty())
    free : S.Shape <- S.join_limited(search,colliders,2,budget)
    return S.closest(free,point)
def unstuck_result(point:V.Vec3,free:Maybe<&2,V.Vec3>) -> V.Vec3:
  match free:
    case None{}: point
    case Some{value}: shift_y(value,F.neg(quarter()))
def place_clear(context:Context,request:Prepared,clear:Bool) -> Result<&2,&2,String,V.Vec3>:
  Prepared{point,query,center,shape,outer} = request
  match clear:
    case True{}: Done{point}
    case False{}:
      do Result<&2,&2,String,V.Vec3>:
        free : Maybe<&2,V.Vec3> <- free_position(context,shape,center,outer)
        return unstuck_result(point,free)
def place_prepared(+context:Context,+request:Prepared) -> Result<&2,&2,String,V.Vec3>:
  Prepared{point,+query,center,shape,outer} = request
  do Result<&2,&2,String,V.Vec3>:
    clear : Bool <- no_collision(context,query)
    place_clear(context,request,clear)
def place_query(+context:Context,dimension:String,+point:V.Vec3) -> Result<&2,&2,String,V.Vec3>:
  Context{actual,coverage,blocks,entities,budget} = context
  do Result<&2,&2,String,V.Vec3>:
    guard(String.eq(dimension,actual),"geometry:dimension-mismatch")
    guard(V.vector_finite(point),"geometry:nonfinite-position")
    request : Prepared <- prepare(point)
    place_prepared(context,request)
def entity_result(value:Result<&2,&2,String,V.Vec3>) -> Result<&2,&2,E.Error,V.Vec3>:
  match value:
    case Done{point}: Done{point}
    case Fail{message}: Fail{E.Refused{message}}
# Exact signature consumed by CookingEffects.apply / the clock adapter.
def place(context:Context,dimension:String,point:V.Vec3) -> Result<&2,&2,E.Error,V.Vec3>:
  entity_result(place_query(context,dimension,point))
