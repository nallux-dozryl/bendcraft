import Base
import ./core.bend as C
import ./game.bend as G
import ./registry.bend as Registry
import ./player_block_interaction.bend as BI
import ./client_world.bend as W
import ./fall_reset_world.bend as D
import ./geometry.bend as A
import ./movement.bend as M
import ./f64.bend as F
import ./locomotion.bend as T
import ./local_player_record.bend as Record
import ./local_player_runtime.bend as Runtime
import ./local_phase_runtime.bend as X
import ./png.bend as Pair

# The ray reads the sole actual Engine and restores every transient runtime
# field. Non-cooking solid hits block use; unknown outlines fail explicitly.
type Family is Data:
  Furnace{}
  Campfire{}
  Other{}
type Hit is Data:
  Hit{position:C.Position,family:Family}
type Pick is Data:
  Pick{hit:Maybe<&2,Hit>,blocked:Bool}

def classified(furnace:Bool,campfire:Bool) -> Family:
  match furnace campfire:
    case True{} _: Furnace{}
    case False{} True{}: Campfire{}
    case False{} False{}: Other{}

def family(+name:String) -> Family:
  classified(String.eq(name,"minecraft:furnace") || String.eq(name,"minecraft:blast_furnace") || String.eq(name,"minecraft:smoker"),
    String.eq(name,"minecraft:campfire") || String.eq(name,"minecraft:soul_campfire"))

def campfire_box(position:C.Position) -> A.AABB:
  C.Position{dimension,x,y,z} = position
  +a = F.from_i32(x)
  +b = F.from_i32(y)
  +c = F.from_i32(z)
  A.AABB{a,b,c,F.add(a,F.from_u32(1)),F.add(b,F.div(F.from_u32(7),F.from_u32(16))),F.add(c,F.from_u32(1))}

def clipped_inside(+position:C.Position,+state:U32,+from:M.Vec3,+delta:M.Vec3,small:Bool) -> Maybe<&2,BI.Hit>:
  match small:
    case True{}: None{}
    case False{}: BI.clip_inside(position,state,from,delta,campfire_box(position),BI.location(from,delta,F.F64{1062232653,3539053052}))

def clip_campfire(+position:C.Position,state:U32,+from:M.Vec3,to:M.Vec3) -> Maybe<&2,BI.Hit>:
  +delta = BI.subtract(to,from)
  clipped_inside(position,state,from,delta,F.is_lt(BI.length_squared(delta),A.epsilon()))

def clipped(+kind:Family,value:Maybe<&2,BI.Hit>) -> Pick:
  match value:
    case None{}: Pick{None{},False{}}
    case Some{BI.Hit{position,state,face,location,inside}}: Pick{Some{Hit{position,kind}},True{}}

def selected(+kind:Family,+ray:BI.Ray,+state:U32) -> Pick:
  match kind:
    case Campfire{}:
      BI.Ray{from,to,axes,tail} = ray
      clipped(Campfire{},clip_campfire(BI.ray_position(ray),state,from,to))
    case other:
      BI.Ray{from,to,axes,tail} = ray
      clipped(other,BI.clip_cube(BI.ray_position(ray),state,from,to))

def named_shape(name:String,ray:BI.Ray,state:U32,empty:Bool,kind:Family,cube:Bool) -> Result<&2,&2,String,Pick>:
  match empty kind cube:
    case True{} _ _: Done{Pick{None{},False{}}}
    case False{} Other{} False{}: Fail{"cooking-target:unsupported-outline:" ++ name}
    case False{} Other{} True{}: Done{selected(Other{},ray,state)}
    case False{} kind _: Done{selected(kind,ray,state)}

def named(+name:String,ray:BI.Ray,state:U32) -> Result<&2,&2,String,Pick>:
  named_shape(name,ray,state,BI.empty_shape(name),family(name),BI.supported_cube(name))

def block(world:C.World,ray:BI.Ray,state:U32,result:Registry.Registry & Result<&2,&2,Registry.Error,Registry.Block>) -> G.Engine & Result<&2,&2,String,Pick>:
  (registry,status) = result
  match status:
    case Fail{error}: (G.Engine{world,registry},Fail{Registry.error_text(error)})
    case Done{Registry.Block{protocol,name,first,count,default_id,properties}}:
      (G.Engine{world,registry},named(name,ray,state))

def read(registry:Registry.Registry,ray:BI.Ray,result:C.World & Result<&2,&2,C.Error,U32>) -> G.Engine & Result<&2,&2,String,Pick>:
  (world,status) = result
  match status:
    case Fail{error}: (G.Engine{world,registry},Fail{W.error_text(error)})
    case Done{+state}: block(world,ray,state,Registry.Registry.state_block(registry,state))

def head(engine:G.Engine,+ray:BI.Ray) -> G.Engine & Result<&2,&2,String,Pick>:
  G.Engine{world,registry} = engine
  read(registry,ray,C.read_block(world,BI.ray_position(ray)))

def next(engine:G.Engine,ray:Maybe<&2,BI.Ray>,resume:G.Engine -> BI.Ray -> G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>) -> G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>:
  match ray:
    case None{}: (engine,Done{None{}})
    case Some{ray}: resume(engine)(ray)

def continued(ray:BI.Ray,resume:G.Engine -> BI.Ray -> G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>,result:G.Engine & Result<&2,&2,String,Pick>) -> G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>:
  (engine,status) = result
  match status:
    case Fail{message}: (engine,Fail{message})
    case Done{Pick{hit,True{}}}: (engine,Done{hit})
    case Done{Pick{hit,False{}}}: next(engine,BI.ray_next(ray),resume)

# Neutral default interaction range is at most5: a3D DDA crosses fewer than
# 32 cells. The bound follows the supported range, not a test fixture count.
def scan(left:Nat,engine:G.Engine,+ray:BI.Ray) -> G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>:
  match left:
    case 0n: (engine,Fail{"cooking-target:ray-work-budget"})
    case 1n+n: continued(ray,e => r => scan(n,e,r),head(engine,ray))

def axes(engine:G.Engine,from:M.Vec3,to:M.Vec3,result:Result<&2,&2,D.Error,D.Axes>) -> G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>:
  match result:
    case Fail{error}: (engine,Fail{D.error_text(error)})
    case Done{axes}: scan(32n,engine,BI.Ray{from,to,axes,[]})

def pick(engine:G.Engine,+from:M.Vec3,+to:M.Vec3) -> G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>:
  axes(engine,from,to,D.axes(D.expanded(from,to),D.expanded(to,from)))

def picked(+record:Record.Record,transient:Runtime.Detached,result:G.Engine & Result<&2,&2,String,Maybe<&2,Hit>>) -> X.State & Result<&2,&2,String,Maybe<&2,Hit>>:
  (engine,status) = result
  (Runtime.attach(engine,record,transient),status)

def detached(+range:F.F64,result:G.Engine & Record.Record & Runtime.Detached) -> X.State & Result<&2,&2,String,Maybe<&2,Hit>>:
  (engine,+record,Runtime.Detached{tables,palette,region,cache,buttons,mouse,options,receiver,error,st,mt,dt}) = result
  +from = BI.eye(record)
  Pair.paired(T.Tables,M.Vec3,X.State & Result<&2,&2,String,Maybe<&2,Hit>>,BI.direction(tables,record),
    actual => direction => picked(record,Runtime.Detached{actual,palette,region,cache,buttons,mouse,options,receiver,error,st,mt,dt},
      pick(engine,from,M.Vec3.add(from,T.scale(direction,range)))))

def checked(range:F.F64,result:X.State & Result<&2,&2,String,Record.Record>) -> X.State & Result<&2,&2,String,Maybe<&2,Hit>>:
  (state,status) = result
  match status:
    case Fail{message}: (state,Fail{message})
    case Done{record}: detached(range,Runtime.detach(state))

def query(state:X.State,range:F.F64) -> X.State & Result<&2,&2,String,Maybe<&2,Hit>>:
  checked(range,Runtime.record_checked(state))
