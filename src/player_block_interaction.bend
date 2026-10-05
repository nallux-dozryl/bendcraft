import Base
import ./core.bend as C
import ./game.bend as G
import ./registry.bend as B
import ./client_world.bend as W
import ./fall_reset_world.bend as D
import ./geometry.bend as A
import ./movement.bend as M
import ./f64.bend as F
import ./locomotion.bend as T
import ./player_look.bend as Look
import ./local_player_record.bend as Record
import ./player_record.bend as Saved
import ./player_codec.bend as Codec
import ./player_pose.bend as Pose
import ./player_inventory.bend as I
import ./inventory.bend as Inv
import ./player_core_edit.bend as Edit

# The camera ray reads the same authoritative Engine that receives the edit.
# Admission is deliberately restricted to independently observed full cubes and
# air. Unknown shapes, fluids, missing chunks and survival digging are explicit
# unsuccessful outcomes, never invented hits or mutations.
type Outcome is Data:
  Outcome{changed:Bool,message:String}
type Face is Data:
  Down{}
  Up{}
  North{}
  South{}
  West{}
  East{}
type Hit is Data:
  Hit{position:C.Position,state:U32,face:Face,location:M.Vec3,inside:Bool}
type Plane is Data:
  Plane{amount:F.F64,face:Maybe<&2,Face>}
type Ray is Data:
  Ray{from:M.Vec3,to:M.Vec3,axes:D.Axes,tail:List<&2,Ray>}
type Authority is Data:
  Authority{capability:C.Capability,sequence:Nat,maybuild:Bool}

def one() -> F.F64: F.from_u32(1)
def zero() -> F.F64: F.from_u32(0)

# Default vanilla creative block reach. The supported ability profile excludes
# attribute modifiers; the pinned Java behavior probe records the actual value.
def creative_reach() -> F.F64: F.from_u32(5)

# Picking uses the block outline, not its interaction or collision shape.
# The pinned 26.3 furnace/smoker/blast-furnace class chains inherit getShape
# from BlockBehaviour, which returns the filled Shapes.block() for every state.
def supported_cube(+name:String) -> Bool:
  String.eq(name,"minecraft:stone") || String.eq(name,"minecraft:dirt") ||
    String.eq(name,"minecraft:oak_planks") || String.eq(name,"minecraft:grass_block") ||
    String.eq(name,"minecraft:bedrock") || String.eq(name,"minecraft:furnace") ||
    String.eq(name,"minecraft:smoker") || String.eq(name,"minecraft:blast_furnace")

def placeable(+name:String) -> Bool:
  String.eq(name,"minecraft:stone") || String.eq(name,"minecraft:dirt") ||
    String.eq(name,"minecraft:oak_planks")

def empty_shape(+name:String) -> Bool:
  String.eq(name,"minecraft:air") || String.eq(name,"minecraft:cave_air") ||
    String.eq(name,"minecraft:void_air")

def cube(position:C.Position) -> A.AABB:
  C.Position{dimension,x,y,z} = position
  W.full_cube(W.Cell{x,y,z,0})

def eye_body(height:F32,body:M.Body) -> M.Vec3:
  M.Body{M.Vec3{x,y,z},box,velocity,width,h,ground,horizontal,vertical,below} = body
  M.Vec3{x,F.add(y,F.from_f32(height)),z}

def eye(record:Record.Record) -> M.Vec3:
  Record.Record{motion,local,sprinting,Pose.State{pose,height,tail},minor,history,entity} = record
  eye_body(height,Record.body(motion))

def box_body(body:M.Body) -> A.AABB:
  M.Body{position,box,velocity,width,height,ground,horizontal,vertical,below} = body
  box

def body_box(record:Record.Record) -> A.AABB:
  Record.Record{motion,local,sprinting,pose,minor,history,entity} = record
  box_body(Record.body(motion))

def negate(value:F32) -> F32:
  Look.float_bits(U32.xor(F32.bits(value),2147483648))

def subtract(a:M.Vec3,b:M.Vec3) -> M.Vec3:
  M.Vec3{x,y,z} = a
  M.Vec3{a,b,c} = b
  M.Vec3{F.sub(x,a),F.sub(y,b),F.sub(z,c)}

def angles(record:Record.Record) -> F32 & F32:
  Record.Record{Saved.Record{snapshot,Look.State{yaw,pitch,previous_yaw,previous_pitch}},local,sprinting,pose,minor,history,entity} = record
  (Look.mul(negate(yaw),Look.float_bits(1016003125)),Look.mul(pitch,Look.float_bits(1016003125)))

def direction_values(yaw_sin:F32,yaw_cos:F32,+pitch_cos:F32,result:T.Tables & F32) -> T.Tables & M.Vec3:
  (tables,pitch_sin) = result
  (tables,M.Vec3{F.from_f32(Look.mul(yaw_sin,pitch_cos)),F.from_f32(negate(pitch_sin)),F.from_f32(Look.mul(yaw_cos,pitch_cos))})

def direction_pitch_sin(pitch:F.F64,yaw_sin:F32,yaw_cos:F32,result:T.Tables & F32) -> T.Tables & M.Vec3:
  (tables,pitch_cos) = result
  direction_values(yaw_sin,yaw_cos,pitch_cos,T.sin(tables,pitch))

def direction_pitch_cos(+pitch:F.F64,yaw_sin:F32,result:T.Tables & F32) -> T.Tables & M.Vec3:
  (tables,yaw_cos) = result
  direction_pitch_sin(pitch,yaw_sin,yaw_cos,T.cos(tables,pitch))

def direction_yaw_cos(yaw:F.F64,pitch:F.F64,result:T.Tables & F32) -> T.Tables & M.Vec3:
  (tables,yaw_sin) = result
  direction_pitch_cos(pitch,yaw_sin,T.cos(tables,yaw))

def direction_angles(tables:T.Tables,+yaw:F32,pitch:F32) -> T.Tables & M.Vec3:
  direction_yaw_cos(F.from_f32(yaw),F.from_f32(pitch),T.sin(tables,F.from_f32(yaw)))

def view_vector(tables:T.Tables,yaw:F32,pitch:F32) -> T.Tables & M.Vec3:
  direction_angles(tables,Look.mul(negate(yaw),Look.float_bits(1016003125)),Look.mul(pitch,Look.float_bits(1016003125)))

def direction_pair(tables:T.Tables,value:F32 & F32) -> T.Tables & M.Vec3:
  (yaw,pitch) = value
  direction_angles(tables,yaw,pitch)

def direction(tables:T.Tables,record:Record.Record) -> T.Tables & M.Vec3:
  direction_pair(tables,angles(record))

def endpoint(from:M.Vec3,direction:M.Vec3) -> M.Vec3:
  M.Vec3.add(from,T.scale(direction,creative_reach()))

def location(from:M.Vec3,delta:M.Vec3,amount:F.F64) -> M.Vec3:
  M.Vec3.add(from,T.scale(delta,amount))

# Original AABB.clip plane ordering is X, Y, Z; strictly nearer candidates win.
# Transverse boundaries use the actual 1e-7 expansion, not an arbitrary tolerance.
def plane_valid(+amount:F.F64,limit:F.F64,+first:F.F64,+second:F.F64,
    bounds_first:F.F64 & F.F64,bounds_second:F.F64 & F.F64) -> Bool:
  (low,high) = bounds_first
  (bottom,top) = bounds_second
  F.is_gt(amount,zero()) && F.is_lt(amount,limit) &&
    F.is_gt(first,F.sub(low,A.epsilon())) && F.is_lt(first,F.add(high,A.epsilon())) &&
    F.is_gt(second,F.sub(bottom,A.epsilon())) && F.is_lt(second,F.add(top,A.epsilon()))

def plane_checked(+amount:F.F64,face:Face,prior:Plane,first:F.F64,second:F.F64,
    bounds_first:F.F64 & F.F64,bounds_second:F.F64 & F.F64) -> Plane:
  Plane{+limit,old_face} = prior
  W.choose(Plane,Plane{amount,Some{face}},Plane{limit,old_face},plane_valid(amount,limit,first,second,bounds_first,bounds_second))

def axis_plane_result(from:F.F64,delta:F.F64,face:Face,prior:Plane,
    first:F.F64,first_delta:F.F64,second:F.F64,second_delta:F.F64,
    boundary:F.F64,bounds_first:F.F64 & F.F64,bounds_second:F.F64 & F.F64) -> Plane:
  +amount = F.div(F.sub(boundary,from),delta)
  plane_checked(amount,face,prior,F.add(first,F.mul(amount,first_delta)),F.add(second,F.mul(amount,second_delta)),bounds_first,bounds_second)

def axis_plane_checked(from:F.F64,delta:F.F64,negative:Face,positive:Face,prior:Plane,
    first:F.F64,first_delta:F.F64,second:F.F64,second_delta:F.F64,
    low:F.F64,high:F.F64,bounds_first:F.F64 & F.F64,bounds_second:F.F64 & F.F64,forward:Bool,backward:Bool) -> Plane:
  match forward backward:
    case True{} _: axis_plane_result(from,delta,negative,prior,first,first_delta,second,second_delta,low,bounds_first,bounds_second)
    case False{} True{}: axis_plane_result(from,delta,positive,prior,first,first_delta,second,second_delta,high,bounds_first,bounds_second)
    case False{} False{}: prior

def axis_plane(from:F.F64,+delta:F.F64,negative:Face,positive:Face,prior:Plane,
    first:F.F64,first_delta:F.F64,second:F.F64,second_delta:F.F64,
    bounds:F.F64 & F.F64,bounds_first:F.F64 & F.F64,bounds_second:F.F64 & F.F64) -> Plane:
  (low,high) = bounds
  axis_plane_checked(from,delta,negative,positive,prior,first,first_delta,second,second_delta,low,high,bounds_first,bounds_second,
    F.is_gt(delta,A.epsilon()),F.is_lt(delta,F.neg(A.epsilon())))

def clip_planes(from:M.Vec3,delta:M.Vec3,box:A.AABB) -> Plane:
  M.Vec3{+x,+y,+z} = from
  M.Vec3{+dx,+dy,+dz} = delta
  A.AABB{+a,+b,+c,+d,+e,+f} = box
  first = axis_plane(x,dx,West{},East{},Plane{one(),None{}},y,dy,z,dz,(a,d),(b,e),(c,f))
  second = axis_plane(y,dy,Down{},Up{},first,x,dx,z,dz,(b,e),(a,d),(c,f))
  axis_plane(z,dz,North{},South{},second,x,dx,y,dy,(c,f),(a,d),(b,e))

# The double overload narrows to floats before six strict dot comparisons.
# VALUES order is DOWN, UP, NORTH, SOUTH, WEST, EAST; score starts at the
# smallest positive float and default direction is NORTH. Float ties matter.
def face_normal(face:Face) -> F32 & F32 & F32:
  match face:
    case Down{}: (0.0,F32.neg(1.0),0.0)
    case Up{}: (0.0,1.0,0.0)
    case North{}: (0.0,0.0,F32.neg(1.0))
    case South{}: (0.0,0.0,1.0)
    case West{}: (F32.neg(1.0),0.0,0.0)
    case East{}: (1.0,0.0,0.0)

def direction_score(x:F32,y:F32,z:F32,normal:F32 & F32 & F32) -> F32:
  (a,b,c) = normal
  Look.add(Look.add(Look.mul(x,a),Look.mul(y,b)),Look.mul(z,c))

def nearest_checked(face:Face,score:F32,prior:Face,best:F32,nearer:Bool,next:Face -> F32 -> Face) -> Face:
  match nearer:
    case True{}: next(face)(score)
    case False{}: next(prior)(best)

def nearest_faces(faces:List<&2,Face>,+x:F32,+y:F32,+z:F32,prior:Face,+best:F32) -> Face:
  match faces:
    case Nil{}: prior
    case +face <> remaining:
      +score = direction_score(x,y,z,face_normal(face))
      nearest_checked(face,score,prior,best,F32.is_gt(score,best),next => value => nearest_faces(remaining,x,y,z,next,value))

def nearest_x(x:F.F64,y:F.F64,z:F.F64) -> Face:
  nearest_faces([Down{},Up{},North{},South{},West{},East{}],F.to_f32(x),F.to_f32(y),F.to_f32(z),North{},Look.float_bits(1))

def opposite(face:Face) -> Face:
  match face:
    case Down{}: Up{}
    case Up{}: Down{}
    case North{}: South{}
    case South{}: North{}
    case West{}: East{}
    case East{}: West{}

def clip_external(position:C.Position,state:U32,+from:M.Vec3,+delta:M.Vec3,plane:Plane) -> Maybe<&2,Hit>:
  Plane{amount,face} = plane
  match face:
    case None{}: None{}
    case Some{face}: Some{Hit{position,state,face,location(from,delta,amount),False{}}}

def clip_inside_checked(inside:Bool,position:C.Position,state:U32,+from:M.Vec3,+delta:M.Vec3,box:A.AABB,near:M.Vec3) -> Maybe<&2,Hit>:
  match inside:
    case True{}:
      M.Vec3{x,y,z} = delta
      Some{Hit{position,state,opposite(nearest_x(x,y,z)),near,True{}}}
    case False{}: clip_external(position,state,from,delta,clip_planes(from,delta,box))

def clip_inside(position:C.Position,state:U32,from:M.Vec3,delta:M.Vec3,+box:A.AABB,+near:M.Vec3) -> Maybe<&2,Hit>:
  M.Vec3{x,y,z} = near
  clip_inside_checked(A.AABB.contains(box,x,y,z),position,state,from,delta,box,near)

def length_squared(value:M.Vec3) -> F.F64:
  M.Vec3{+x,+y,+z} = value
  F.add(F.add(F.mul(x,x),F.mul(y,y)),F.mul(z,z))

def clip_length(+position:C.Position,state:U32,+from:M.Vec3,+delta:M.Vec3,small:Bool) -> Maybe<&2,Hit>:
  match small:
    case True{}: None{}
    case False{}: clip_inside(position,state,from,delta,cube(position),location(from,delta,F.F64{1062232653,3539053052}))

def clip_cube(position:C.Position,state:U32,+from:M.Vec3,to:M.Vec3) -> Maybe<&2,Hit>:
  +delta = subtract(to,from)
  clip_length(position,state,from,delta,F.is_lt(length_squared(delta),A.epsilon()))

def ray_position(ray:Ray) -> C.Position:
  Ray{from,to,axes,tail} = ray
  D.axes_position(axes)

def ray_next(ray:Ray) -> Maybe<&2,Ray>:
  Ray{from,to,+axes,tail} = ray
  W.choose(Maybe<&2,Ray>,Some{Ray{from,to,D.axes_advance(axes),[]}},None{},D.axes_active(axes))

def picked_name(empty:Bool,supported:Bool,ray:Ray,state:U32,registry:B.Registry,name:String) -> B.Registry & Result<&2,&2,String,Maybe<&2,Hit>>:
  match empty supported:
    case True{} _: (registry,Done{None{}})
    case False{} False{}: (registry,Fail{"interaction:unsupported-shape:" ++ name})
    case False{} True{}:
      Ray{from,to,axes,tail} = ray
      position = D.axes_position(axes)
      (registry,Done{clip_cube(position,state,from,to)})

def picked_state(ray:Ray,state:U32,result:B.Registry & Result<&2,&2,B.Error,B.Block>) -> B.Registry & Result<&2,&2,String,Maybe<&2,Hit>>:
  (registry,status) = result
  match status:
    case Fail{cause}: (registry,Fail{B.error_text(cause)})
    case Done{B.Block{protocol,+name,first,count,default_id,properties}}:
      picked_name(empty_shape(name),supported_cube(name),ray,state,registry,name)

def scan_next(engine:G.Engine,next:G.Engine -> Ray -> G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>,ray:Maybe<&2,Ray>) -> G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>:
  match ray:
    case None{}: (engine,Done{None{}})
    case Some{value}: next(engine)(value)

def scan_continue(ray:Ray,next:G.Engine -> Ray -> G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>,result:G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>) -> G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>:
  (engine,status) = result
  match status:
    case Fail{message}: (engine,Fail{message})
    case Done{Some{hit}}: (engine,Done{Some{hit}})
    case Done{None{}}: scan_next(engine,next,ray_next(ray))

def scan_picked(world:C.World,result:B.Registry & Result<&2,&2,String,Maybe<&2,Hit>>) -> G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>:
  (registry,status) = result
  (G.Engine{world,registry},status)

def scan_block(world:C.World,ray:Ray,state:U32,result:B.Registry & Result<&2,&2,B.Error,B.Block>) -> G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>:
  scan_picked(world,picked_state(ray,state,result))

def scan_read(registry:B.Registry,ray:Ray,result:C.World & Result<&2,&2,C.Error,U32>) -> G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>:
  (world,status) = result
  match status:
    case Fail{cause}: (G.Engine{world,registry},Fail{W.error_text(cause)})
    case Done{+state}: scan_block(world,ray,state,B.Registry.state_block(registry,state))

def scan_head(engine:G.Engine,+ray:Ray) -> G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>:
  G.Engine{world,registry} = engine
  scan_read(registry,ray,C.read_block(world,ray_position(ray)))

def scan(fuel:Nat,engine:G.Engine,+ray:Ray) -> G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>:
  match fuel:
    case 0n: (engine,Fail{"interaction:ray-work-budget"})
    case 1n+rest:
      scan_continue(ray,e => r => scan(rest,e,r),scan_head(engine,ray))

def pick_axes(engine:G.Engine,from:M.Vec3,to:M.Vec3,result:Result<&2,&2,D.Error,D.Axes>) -> G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>:
  match result:
    case Fail{cause}: (engine,Fail{D.error_text(cause)})
    case Done{axes}: scan(32n,engine,Ray{from,to,axes,[]})

def pick(engine:G.Engine,+from:M.Vec3,+to:M.Vec3) -> G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>:
  pick_axes(engine,from,to,D.axes(D.expanded(from,to),D.expanded(to,from)))

def neighbor(hit:Hit) -> C.Position:
  Hit{C.Position{dimension,x,y,z},state,face,location,inside} = hit
  match face:
    case Down{}: C.Position{dimension,x,U32.sub(y,1),z}
    case Up{}: C.Position{dimension,x,U32.add(y,1),z}
    case North{}: C.Position{dimension,x,y,U32.sub(z,1)}
    case South{}: C.Position{dimension,x,y,U32.add(z,1)}
    case West{}: C.Position{dimension,U32.sub(x,1),y,z}
    case East{}: C.Position{dimension,U32.add(x,1),y,z}

def edited(registry:B.Registry,result:C.World & Result<&2,&2,Edit.Error,Unit>) -> G.Engine & Outcome:
  (world,status) = result
  match status:
    case Fail{cause}: (G.Engine{world,registry},Outcome{False{},Edit.error_text(cause)})
    case Done{unit}: (G.Engine{world,registry},Outcome{True{},""})

def edit_clock(authority:Authority,registry:B.Registry,position:C.Position,state:U32,result:C.World & C.Clock) -> G.Engine & Outcome:
  Authority{cap,sequence,maybuild} = authority
  (world,C.Clock{tick,time,paused,daylight,revision,pending}) = result
  edited(registry,Edit.edit(world,cap,position,state,revision,sequence,maybuild))

def edit(authority:Authority,engine:G.Engine,position:C.Position,state:U32) -> G.Engine & Outcome:
  G.Engine{world,registry} = engine
  edit_clock(authority,registry,position,state,C.clock(world))

def default_state(result:B.Registry & Result<&2,&2,B.Error,B.Block>) -> B.Registry & Result<&2,&2,String,U32>:
  (registry,status) = result
  match status:
    case Fail{cause}: (registry,Fail{B.error_text(cause)})
    case Done{B.Block{protocol,name,first,count,default_id,properties}}: (registry,Done{default_id})

def bare_action(result:G.Engine & Unit & Outcome) -> G.Engine & Outcome:
  (engine,unit,outcome) = result
  (engine,outcome)

def bare_execution(result:G.Engine & Unit & T.Tables & Outcome) -> G.Engine & T.Tables & Outcome:
  (engine,unit,tables,outcome) = result
  (engine,tables,outcome)

def default_edited(result:G.Engine & Outcome) -> G.Engine & Unit & Outcome:
  (engine,outcome) = result
  (engine,Unit{},outcome)

def default_edit(authority:Authority,engine:G.Engine,unit:Unit,position:C.Position,state:U32) -> G.Engine & Unit & Outcome:
  default_edited(edit(authority,engine,position,state))

def break_hit_with_owner(-Extra:Type,editor:Authority -> G.Engine -> Extra -> C.Position -> U32 -> G.Engine & Extra & Outcome,extra:Extra,authority:Authority,engine:G.Engine,hit:Hit,air:U32) -> G.Engine & Extra & Outcome:
  Hit{position,state,face,location,inside} = hit
  editor(authority,engine,extra,position,air)

def break_hit(authority:Authority,engine:G.Engine,hit:Hit,air:U32) -> G.Engine & Outcome:
  bare_action(break_hit_with_owner(Unit,default_edit,Unit{},authority,engine,hit,air))

def break_state_with_owner(-Extra:Type,editor:Authority -> G.Engine -> Extra -> C.Position -> U32 -> G.Engine & Extra & Outcome,extra:Extra,authority:Authority,world:C.World,hit:Hit,result:B.Registry & Result<&2,&2,String,U32>) -> G.Engine & Extra & Outcome:
  (registry,status) = result
  match status:
    case Fail{message}: (G.Engine{world,registry},extra,Outcome{False{},message})
    case Done{air}: break_hit_with_owner(Extra,editor,extra,authority,G.Engine{world,registry},hit,air)

def break_state(authority:Authority,world:C.World,hit:Hit,result:B.Registry & Result<&2,&2,String,U32>) -> G.Engine & Outcome:
  bare_action(break_state_with_owner(Unit,default_edit,Unit{},authority,world,hit,result))

def break_block_with_owner(-Extra:Type,editor:Authority -> G.Engine -> Extra -> C.Position -> U32 -> G.Engine & Extra & Outcome,extra:Extra,authority:Authority,engine:G.Engine,hit:Hit) -> G.Engine & Extra & Outcome:
  G.Engine{world,registry} = engine
  break_state_with_owner(Extra,editor,extra,authority,world,hit,default_state(B.Registry.block(registry,"minecraft:air")))

def break_block(authority:Authority,engine:G.Engine,hit:Hit) -> G.Engine & Outcome:
  bare_action(break_block_with_owner(Unit,default_edit,Unit{},authority,engine,hit))

def placement_empty_checked_with_owner(-Extra:Type,editor:Authority -> G.Engine -> Extra -> C.Position -> U32 -> G.Engine & Extra & Outcome,extra:Extra,authority:Authority,engine:G.Engine,position:C.Position,state:U32,empty:Bool) -> G.Engine & Extra & Outcome:
  match empty:
    case False{}: (engine,extra,Outcome{False{},"interaction:placement-occupied"})
    case True{}: editor(authority,engine,extra,position,state)

def placement_empty_checked(authority:Authority,engine:G.Engine,position:C.Position,state:U32,empty:Bool) -> G.Engine & Outcome:
  bare_action(placement_empty_checked_with_owner(Unit,default_edit,Unit{},authority,engine,position,state,empty))

def placement_empty_with_owner(-Extra:Type,editor:Authority -> G.Engine -> Extra -> C.Position -> U32 -> G.Engine & Extra & Outcome,extra:Extra,authority:Authority,world:C.World,position:C.Position,state:U32,result:B.Registry & Result<&2,&2,B.Error,B.Block>) -> G.Engine & Extra & Outcome:
  (registry,status) = result
  match status:
    case Fail{cause}: (G.Engine{world,registry},extra,Outcome{False{},B.error_text(cause)})
    case Done{B.Block{protocol,name,first,count,default_id,properties}}:
      placement_empty_checked_with_owner(Extra,editor,extra,authority,G.Engine{world,registry},position,state,empty_shape(name))

def placement_empty(authority:Authority,world:C.World,position:C.Position,state:U32,result:B.Registry & Result<&2,&2,B.Error,B.Block>) -> G.Engine & Outcome:
  bare_action(placement_empty_with_owner(Unit,default_edit,Unit{},authority,world,position,state,result))

def placement_read_with_owner(-Extra:Type,editor:Authority -> G.Engine -> Extra -> C.Position -> U32 -> G.Engine & Extra & Outcome,extra:Extra,authority:Authority,registry:B.Registry,position:C.Position,state:U32,result:C.World & Result<&2,&2,C.Error,U32>) -> G.Engine & Extra & Outcome:
  (world,status) = result
  match status:
    case Fail{cause}: (G.Engine{world,registry},extra,Outcome{False{},W.error_text(cause)})
    case Done{old}: placement_empty_with_owner(Extra,editor,extra,authority,world,position,state,B.Registry.state_block(registry,old))

def placement_read(authority:Authority,registry:B.Registry,position:C.Position,state:U32,result:C.World & Result<&2,&2,C.Error,U32>) -> G.Engine & Outcome:
  bare_action(placement_read_with_owner(Unit,default_edit,Unit{},authority,registry,position,state,result))

def placement_fits_with_owner(-Extra:Type,editor:Authority -> G.Engine -> Extra -> C.Position -> U32 -> G.Engine & Extra & Outcome,extra:Extra,intersects:Bool,authority:Authority,engine:G.Engine,+position:C.Position,state:U32) -> G.Engine & Extra & Outcome:
  match intersects:
    case True{}: (engine,extra,Outcome{False{},"interaction:placement-intersects-player"})
    case False{}:
      G.Engine{world,registry} = engine
      placement_read_with_owner(Extra,editor,extra,authority,registry,position,state,C.read_block(world,position))

def placement_fits(intersects:Bool,authority:Authority,engine:G.Engine,+position:C.Position,state:U32) -> G.Engine & Outcome:
  bare_action(placement_fits_with_owner(Unit,default_edit,Unit{},intersects,authority,engine,position,state))

def placement_state_with_owner(-Extra:Type,editor:Authority -> G.Engine -> Extra -> C.Position -> U32 -> G.Engine & Extra & Outcome,extra:Extra,authority:Authority,world:C.World,record:Record.Record,+position:C.Position,result:B.Registry & Result<&2,&2,String,U32>) -> G.Engine & Extra & Outcome:
  (registry,status) = result
  match status:
    case Fail{message}: (G.Engine{world,registry},extra,Outcome{False{},message})
    case Done{state}:
      placement_fits_with_owner(Extra,editor,extra,A.AABB.intersects(body_box(record),cube(position)),authority,G.Engine{world,registry},position,state)

def placement_state(authority:Authority,world:C.World,record:Record.Record,+position:C.Position,result:B.Registry & Result<&2,&2,String,U32>) -> G.Engine & Outcome:
  bare_action(placement_state_with_owner(Unit,default_edit,Unit{},authority,world,record,position,result))

def place_name_with_owner(-Extra:Type,editor:Authority -> G.Engine -> Extra -> C.Position -> U32 -> G.Engine & Extra & Outcome,extra:Extra,valid:Bool,authority:Authority,engine:G.Engine,record:Record.Record,hit:Hit,name:String) -> G.Engine & Extra & Outcome:
  match valid:
    case False{}: (engine,extra,Outcome{False{},"interaction:unsupported-held-item"})
    case True{}:
      G.Engine{world,registry} = engine
      placement_state_with_owner(Extra,editor,extra,authority,world,record,neighbor(hit),default_state(B.Registry.block(registry,name)))

def place_name(valid:Bool,authority:Authority,engine:G.Engine,record:Record.Record,hit:Hit,name:String) -> G.Engine & Outcome:
  bare_action(place_name_with_owner(Unit,default_edit,Unit{},valid,authority,engine,record,hit,name))

def place_block_with_owner(-Extra:Type,editor:Authority -> G.Engine -> Extra -> C.Position -> U32 -> G.Engine & Extra & Outcome,extra:Extra,authority:Authority,engine:G.Engine,record:Record.Record,held:Inv.Slot,hit:Hit) -> G.Engine & Extra & Outcome:
  match held:
    case Inv.InvEmpty{}: (engine,extra,Outcome{False{},"interaction:empty-hand"})
    case Inv.InvStack{Inv.ItemKey{+name,+components},+count}:
      place_name_with_owner(Extra,editor,extra,placeable(name) && String.eq(components,"") && U32.is_gt(count,0) && U32.is_le(count,64),authority,engine,record,hit,name)

def place_block(authority:Authority,engine:G.Engine,record:Record.Record,held:Inv.Slot,hit:Hit) -> G.Engine & Outcome:
  bare_action(place_block_with_owner(Unit,default_edit,Unit{},authority,engine,record,held,hit))

def action_hit_with_owner(-Extra:Type,editor:Authority -> G.Engine -> Extra -> C.Position -> U32 -> G.Engine & Extra & Outcome,extra:Extra,button:U32,authority:Authority,engine:G.Engine,record:Record.Record,held:Inv.Slot,hit:Hit) -> G.Engine & Extra & Outcome:
  match button:
    case 0: break_block_with_owner(Extra,editor,extra,authority,engine,hit)
    case 1: place_block_with_owner(Extra,editor,extra,authority,engine,record,held,hit)
    case _: (engine,extra,Outcome{False{},"interaction:invalid-button"})

def action_hit(button:U32,authority:Authority,engine:G.Engine,record:Record.Record,held:Inv.Slot,hit:Hit) -> G.Engine & Outcome:
  bare_action(action_hit_with_owner(Unit,default_edit,Unit{},button,authority,engine,record,held,hit))

def action_picked_with_owner(-Extra:Type,editor:Authority -> G.Engine -> Extra -> C.Position -> U32 -> G.Engine & Extra & Outcome,extra:Extra,authority:Authority,record:Record.Record,held:Inv.Slot,button:U32,result:G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>) -> G.Engine & Extra & Outcome:
  (engine,status) = result
  match status:
    case Fail{message}: (engine,extra,Outcome{False{},message})
    case Done{None{}}: (engine,extra,Outcome{False{},"interaction:miss"})
    case Done{Some{hit}}: action_hit_with_owner(Extra,editor,extra,button,authority,engine,record,held,hit)

def action_picked(authority:Authority,record:Record.Record,held:Inv.Slot,button:U32,result:G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>) -> G.Engine & Outcome:
  bare_action(action_picked_with_owner(Unit,default_edit,Unit{},authority,record,held,button,result))

def action_return_with_owner(-Extra:Type,tables:T.Tables,result:G.Engine & Extra & Outcome) -> G.Engine & Extra & T.Tables & Outcome:
  (engine,extra,status) = result
  (engine,extra,tables,status)

def action_return(tables:T.Tables,result:G.Engine & Outcome) -> G.Engine & T.Tables & Outcome:
  (engine,status) = result
  (engine,tables,status)

def action_direction_with_owner(-Extra:Type,editor:Authority -> G.Engine -> Extra -> C.Position -> U32 -> G.Engine & Extra & Outcome,extra:Extra,authority:Authority,engine:G.Engine,+record:Record.Record,held:Inv.Slot,button:U32,result:T.Tables & M.Vec3) -> G.Engine & Extra & T.Tables & Outcome:
  (tables,direction) = result
  +from = eye(record)
  action_return_with_owner(Extra,tables,action_picked_with_owner(Extra,editor,extra,authority,record,held,button,pick(engine,from,endpoint(from,direction))))

def action_direction(authority:Authority,engine:G.Engine,+record:Record.Record,held:Inv.Slot,button:U32,result:T.Tables & M.Vec3) -> G.Engine & T.Tables & Outcome:
  bare_execution(action_direction_with_owner(Unit,default_edit,Unit{},authority,engine,record,held,button,result))

def execute_record_with_owner(-Extra:Type,editor:Authority -> G.Engine -> Extra -> C.Position -> U32 -> G.Engine & Extra & Outcome,extra:Extra,engine:G.Engine,record:Record.Record,tables:T.Tables,held:Inv.Slot,cap:C.Capability,sequence:Nat,button:U32,maybuild:Bool,allowed:Bool,status:Result<&2,&2,Record.Error,Record.Record>) -> G.Engine & Extra & T.Tables & Outcome:
  match allowed status:
    case False{} _: (engine,extra,tables,Outcome{False{},"interaction:creative-build-ability-required"})
    case True{} Fail{cause}: (engine,extra,tables,Outcome{False{},Record.error_text(cause)})
    case True{} Done{valid}: action_direction_with_owner(Extra,editor,extra,Authority{cap,sequence,maybuild},engine,valid,held,button,direction(tables,record))

def execute_record(engine:G.Engine,record:Record.Record,tables:T.Tables,held:Inv.Slot,cap:C.Capability,sequence:Nat,button:U32,maybuild:Bool,allowed:Bool,status:Result<&2,&2,Record.Error,Record.Record>) -> G.Engine & T.Tables & Outcome:
  bare_execution(execute_record_with_owner(Unit,default_edit,Unit{},engine,record,tables,held,cap,sequence,button,maybuild,allowed,status))

def execute_player_with_owner(-Extra:Type,editor:Authority -> G.Engine -> Extra -> C.Position -> U32 -> G.Engine & Extra & Outcome,extra:Extra,engine:G.Engine,+record:Record.Record,tables:T.Tables,abilities:I.Abilities,held:Inv.Slot,cap:C.Capability,sequence:Nat,+button:U32) -> G.Engine & Extra & T.Tables & Outcome:
  I.Abilities{instabuild,+maybuild} = abilities
  execute_record_with_owner(Extra,editor,extra,engine,record,tables,held,cap,sequence,button,maybuild,
    instabuild && maybuild && U32.is_le(button,1),Record.validate(record))

def execute_player(engine:G.Engine,+record:Record.Record,tables:T.Tables,abilities:I.Abilities,held:Inv.Slot,cap:C.Capability,sequence:Nat,+button:U32) -> G.Engine & T.Tables & Outcome:
  bare_execution(execute_player_with_owner(Unit,default_edit,Unit{},engine,record,tables,abilities,held,cap,sequence,button))

def execute_checked_with_owner(-Extra:Type,editor:Authority -> G.Engine -> Extra -> C.Position -> U32 -> G.Engine & Extra & Outcome,extra:Extra,engine:G.Engine,record:Record.Record,tables:T.Tables,abilities:I.Abilities,held:Inv.Slot,cap:C.Capability,sequence:Nat,button:U32,authorized:Bool) -> G.Engine & Extra & T.Tables & Outcome:
  match authorized:
    case False{}: (engine,extra,tables,Outcome{False{},"interaction:permission-denied"})
    case True{}: execute_player_with_owner(Extra,editor,extra,engine,record,tables,abilities,held,cap,sequence,button)

def execute_checked(engine:G.Engine,record:Record.Record,tables:T.Tables,abilities:I.Abilities,held:Inv.Slot,cap:C.Capability,sequence:Nat,button:U32,authorized:Bool) -> G.Engine & T.Tables & Outcome:
  bare_execution(execute_checked_with_owner(Unit,default_edit,Unit{},engine,record,tables,abilities,held,cap,sequence,button,authorized))

def execute_with_owner(-Extra:Type,editor:Authority -> G.Engine -> Extra -> C.Position -> U32 -> G.Engine & Extra & Outcome,extra:Extra,engine:G.Engine,record:Record.Record,tables:T.Tables,abilities:I.Abilities,held:Inv.Slot,+cap:C.Capability,sequence:Nat,button:U32) -> G.Engine & Extra & T.Tables & Outcome:
  execute_checked_with_owner(Extra,editor,extra,engine,record,tables,abilities,held,cap,sequence,button,Maybe.is_some(&2,U32,Edit.player_peer(cap)))

def execute(engine:G.Engine,record:Record.Record,tables:T.Tables,abilities:I.Abilities,held:Inv.Slot,+cap:C.Capability,sequence:Nat,button:U32) -> G.Engine & T.Tables & Outcome:
  bare_execution(execute_with_owner(Unit,default_edit,Unit{},engine,record,tables,abilities,held,cap,sequence,button))
