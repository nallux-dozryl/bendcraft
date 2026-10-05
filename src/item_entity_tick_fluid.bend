import Base
import ./item_entity_tick_model.bend as T
import ./item_entity_tick_fields.bend as U
import ./f64.bend as F
import ./geometry.bend as A
import ./vanilla_entity_fields.bend as V
import ./cooking_effect_geometry.bend as G
import ./cooking_effect_entities_model.bend as E

type ScanBounds is Data:
  ScanBounds{+x:U32,+y:U32,+z:U32,+xx:U32,+yy:U32,zz:U32}
type FluidFrame is Data:
  FluidFrame{water:T.Fluid,lava:T.Fluid,+eye_water:Bool,+eye_lava:Bool,any:Bool}
type ScanCursor is Data:
  ScanCursor{+x:U32,+y:U32,z:U32}
def blank() -> T.Fluid: T.Fluid{U.zero(),U.vec(),0,False{}}
def fresh() -> FluidFrame: FluidFrame{blank(),blank(),False{},False{},False{}}
def cell_match(+cell:T.Cell,+x:U32,+y:U32,+z:U32) -> Bool:
  T.Cell{+state,a,b,c,w,l,h,ch,flow,fluid,full,f,s,r,suppress,inside,step,wb,bubble,fall,+cell_tail}=cell
  U32.is_eq(a,x) && U32.is_eq(b,y) && U32.is_eq(c,z)
def lookup_gate(+cell:T.Cell,+same:Bool,continue:Unit -> Result<&2,&2,T.Error,T.Cell>) -> Result<&2,&2,T.Error,T.Cell>:
  match same:
    case True{}: Done{cell}
    case False{}: continue(Unit{})
def lookup(cells:List<&2,T.Cell>,+x:U32,+y:U32,+z:U32) -> Result<&2,&2,T.Error,T.Cell>:
  match cells:
    case Nil{}: Fail{T.Refused{"item tick queried an unavailable block/fluid cell"}}
    case +cell <> rest: lookup_gate(cell,cell_match(cell,x,y,z),u => lookup(rest,x,y,z))
def integer(result:Result<&2,&2,F.F64ConversionError,U32>) -> Result<&2,&2,T.Error,U32>:
  match result:
    case Done{v}: Done{v}
    case Fail{e}: Fail{T.Refused{"item tick coordinate outside signed integer domain"}}
def ceiling(+value:F.F64) -> Result<&2,&2,T.Error,U32>:
  do Result<&2,&2,T.Error,U32>:
    +floor : U32 <- integer(F.floor_i32(F.neg(value)))
    return U32.sub(0,floor)
def bounds(+box:A.AABB) -> Result<&2,&2,T.Error,ScanBounds>:
  A.AABB{x,y,z,a,b,c}=box
  do Result<&2,&2,T.Error,ScanBounds>:
    +x : U32 <- integer(F.floor_i32(x))
    +y : U32 <- integer(F.floor_i32(y))
    +z : U32 <- integer(F.floor_i32(z))
    +a : U32 <- ceiling(a)
    +b : U32 <- ceiling(b)
    +c : U32 <- ceiling(c)
    return ScanBounds{x,y,z,U32.sub(a,1),U32.sub(b,1),U32.sub(c,1)}
def accumulator(old:T.Fluid,+height:F.F64,+flow:V.Vec3,+tag:Bool) -> T.Fluid:
  match old tag:
    case old False{}: old
    case T.Fluid{h,prior,n,p} True{}:
      +high=A.math_max(height,h)
      T.Fluid{high,U.add(prior,U.select(V.Vec3,U.scale(flow,high,high,high),flow,F.is_lt(high,F.F64{1071225241,2576980378}))),U32.inc(n),True{}}
def active_cell(+frame:FluidFrame,+cell:T.Cell,+min_y:F.F64,+eye:V.Vec3) -> FluidFrame:
  FluidFrame{water,lava,ew,el,any}=frame
  T.Cell{+state,+x,+y,+z,+w,+l,h,ch,+flow,fluid,full,f,s,r,suppress,inside,step,wb,bubble,fall,+cell_tail}=cell
  V.Vec3{ex,+ey,ez}=eye
  +eye_inside=U32.is_eq(x,V.floor_word(ex)) && U32.is_eq(z,V.floor_word(ez)) && F.is_ge(ey,F.from_i32(y)) && F.is_le(ey,F.add(F.from_i32(y),F.from_f32(ch)))
  +height=F.sub(F.add(F.from_i32(y),F.from_f32(h)),min_y)
  FluidFrame{accumulator(water,height,flow,w),accumulator(lava,height,flow,l),ew || (w && eye_inside),el || (l && eye_inside),True{}}
def add_cell(+frame:FluidFrame,+cell:T.Cell,+min_y:F.F64,+eye:V.Vec3,+inside:Bool) -> FluidFrame:
  match inside:
    case False{}: frame
    case True{}: active_cell(frame,cell,min_y,eye)
def accept_cell(+frame:FluidFrame,+cell:T.Cell,+min_y:F.F64,+box:A.AABB,+eye:V.Vec3) -> FluidFrame:
  T.Cell{+state,x,y,z,w,l,h,ch,flow,+fluid,full,f,s,r,suppress,inside,step,wb,bubble,fall,+cell_tail}=cell
  A.AABB{a,low,b,c,d,e}=box
  add_cell(frame,cell,min_y,eye,fluid && F.is_ge(F.add(F.from_i32(y),F.from_f32(h)),low))
def next_x(+bounds:ScanBounds,+x:U32) -> Maybe<&2,ScanCursor>:
  ScanBounds{a,y,z,+xx,b,c}=bounds
  U.select(Maybe<&2,ScanCursor>,None{},Some{ScanCursor{U32.inc(x),y,z}},U32.is_eq(x,xx))
def next_y_cursor(+bounds:ScanBounds,+x:U32,+y:U32) -> Maybe<&2,ScanCursor>:
  ScanBounds{a,b,z,c,d,e}=bounds
  Some{ScanCursor{x,U32.inc(y),z}}
def next_y(+bounds:ScanBounds,+x:U32,+y:U32,+end:Bool) -> Maybe<&2,ScanCursor>:
  match end:
    case True{}: next_x(bounds,x)
    case False{}: next_y_cursor(bounds,x,y)
def next_row(+bounds:ScanBounds,+x:U32,+y:U32) -> Maybe<&2,ScanCursor>:
  ScanBounds{a,b,c,d,yy,e}=bounds
  next_y(bounds,x,y,U32.is_eq(y,yy))
def next_z(+bounds:ScanBounds,+x:U32,+y:U32,+z:U32,+end:Bool) -> Maybe<&2,ScanCursor>:
  match end:
    case False{}: Some{ScanCursor{x,y,U32.inc(z)}}
    case True{}: next_row(bounds,x,y)
def next_cursor(+bounds:ScanBounds,+cursor:ScanCursor) -> Maybe<&2,ScanCursor>:
  ScanBounds{a,b,c,d,e,zz}=bounds
  ScanCursor{x,y,+z}=cursor
  next_z(bounds,x,y,z,U32.is_eq(z,zz))
def scanned(+cell:T.Cell,+frame:FluidFrame,+min_y:F.F64,+box:A.AABB,+eye:V.Vec3,next:FluidFrame -> Result<&2,&2,T.Error,FluidFrame>) -> Result<&2,&2,T.Error,FluidFrame>:
  next(accept_cell(frame,cell,min_y,box,eye))
def scan_one(cells:List<&2,T.Cell>,+box:A.AABB,+eye:V.Vec3,+min_y:F.F64,+cursor:ScanCursor,+frame:FluidFrame,next:FluidFrame -> Result<&2,&2,T.Error,FluidFrame>) -> Result<&2,&2,T.Error,FluidFrame>:
  ScanCursor{x,y,z}=cursor
  do Result<&2,&2,T.Error,FluidFrame>:
    +cell : T.Cell <- lookup(cells,x,y,z)
    scanned(cell,frame,min_y,box,eye,next)
def scan(+left:Nat,+cells:List<&2,T.Cell>,+box:A.AABB,+eye:V.Vec3,+min_y:F.F64,+bounds:ScanBounds,cursor:Maybe<&2,ScanCursor>,+frame:FluidFrame) -> Result<&2,&2,T.Error,FluidFrame>:
  match left cursor:
    case _ None{}: Done{frame}
    case 0n _: Fail{T.Refused{"item fluid scan budget exhausted"}}
    case 1n+rest Some{+cursor}:
      scan_one(cells,box,eye,min_y,cursor,frame,next => scan(rest,cells,box,eye,min_y,bounds,next_cursor(bounds,cursor),next))
def scan_ready(+cells:List<&2,T.Cell>,+box:A.AABB,+eye:V.Vec3,+min_y:F.F64,+bounds:ScanBounds,+left:Nat) -> Result<&2,&2,T.Error,FluidFrame>:
  ScanBounds{x,y,z,a,b,c}=bounds
  scan(left,cells,box,eye,min_y,bounds,Some{ScanCursor{x,y,z}},fresh())
def observe_box(cells:List<&2,T.Cell>,+coverage:A.AABB,+point:V.Vec3,+body:A.AABB,+budget:Nat) -> Result<&2,&2,T.Error,FluidFrame>:
  V.Vec3{x,y,z}=point
  A.AABB{a,min_y,b,c,d,e}=body
  +box=G.inflate(body,F.neg(F.F64{1062232653,3539053052}))
  do Result<&2,&2,T.Error,FluidFrame>:
    _ : Unit <- U.guard(G.contained(G.inflate(box,F.from_u32(1)),coverage),"item fluid chunk halo outside observed coverage")
    +bounds : ScanBounds <- bounds(box)
    scan_ready(cells,box,V.Vec3{x,F.add(y,F.from_f32(0.2125)),z},min_y,bounds,budget)
def observe_loaded(cells:List<&2,T.Cell>,+coverage:A.AABB,+record:E.Record,+budget:Nat,+loaded:Bool) -> Result<&2,&2,T.Error,FluidFrame>:
  match loaded:
    case False{}: Done{fresh()}
    case True{}:
      observe_box(cells,coverage,U.pos(record),U.body(record),budget)
def observe(+context:T.Context,+record:E.Record) -> Result<&2,&2,T.Error,FluidFrame>:
  T.Context{items,geometry,cells,coverage,min,server,fast,+loaded,complete,rain,portal,mount,budget,clip,+context_tail}=context
  observe_loaded(cells,coverage,record,budget,loaded)
def pushed(+velocity:V.Vec3,+current:V.Vec3,+rate:F.F64) -> V.Vec3:
  V.Vec3{+x,y,+z}=velocity
  +push=U.scale(U.normal(current),rate,rate,rate)
  +small=F.is_lt(F.abs(x),F.F64{1063818100,3161095930}) && F.is_lt(F.abs(z),F.F64{1063818100,3161095930}) && F.is_lt(F.sqrt(U.length(push)),F.F64{1064464023,2370821948})
  U.add(velocity,U.select(V.Vec3,U.scale(U.normal(push),F.F64{1064464023,2370821948},F.F64{1064464023,2370821948},F.F64{1064464023,2370821948}),push,small))
def current_gate(+velocity:V.Vec3,+current:V.Vec3,+rate:F.F64,+valid:Bool) -> V.Vec3:
  match valid:
    case False{}: velocity
    case True{}: pushed(velocity,current,rate)
def current(+velocity:V.Vec3,fluid:T.Fluid,+rate:F.F64) -> V.Vec3:
  T.Fluid{h,+flow,n,p}=fluid
  current_gate(velocity,flow,rate,U32.is_ne(n,0) && F.is_ge(U.length(flow),F.from_f32(0.00001)))

def water_height(fluids:T.Fluids) -> Bool:
  T.Fluids{T.Fluid{+height,+flow,+count,+present},+lava,+eye,+el,+fast}=fluids
  F.is_gt(height,U.zero())
