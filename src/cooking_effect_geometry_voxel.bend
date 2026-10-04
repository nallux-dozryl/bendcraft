import Base
import ./f64.bend as F
import ./geometry.bend as A
import ./vanilla_entity_fields.bend as V

type Axis is Data:
  Axis{coords:List<&2,F.F64>,cube:Bool}
type Range is Data:
  Range{axis:Axis,start:U32,end:U32}
type Cell is Data:
  Cell{x:U32,y:U32,z:U32}
type Shape is Data:
  Shape{x:Axis,y:Axis,z:Axis,cells:List<&2,Cell>}
type Point is Data:
  Point{value:F.F64,first:U32,second:U32}
type Merge is Data:
  Merge{points:List<&2,Point>,cube:Bool}
type MergeFrame is Data:
  MergeFrame{first:List<&2,F.F64>,second:List<&2,F.F64>,ai:U32,bi:U32,reversed:List<&2,Point>}
type BoxStep is Data:
  BoxStep{remaining:List<&2,Cell>,box:A.AABB}

def pick(-T:Data,test:Bool,yes:T,no:T) -> T:
  match test:
    case True{}: yes
    case False{}: no
def zero() -> F.F64: F.from_u32(0)
def at(values:List<&2,F.F64>,index:U32) -> F.F64:
  match values index:
    case Nil{} _: zero()
    case head <> rest 0: head
    case head <> rest _: at(rest,U32.sub(index,1))
def size(axis:Axis) -> U32:
  Axis{coords,cube} = axis
  U32.sub(U32.from_nat(List.length(&2,F.F64,coords)),1)
def cell_equal(a:Cell,b:Cell) -> Bool:
  Cell{x,y,z} = a
  Cell{u,v,w} = b
  U32.is_eq(x,u) && U32.is_eq(y,v) && U32.is_eq(z,w)
def occupied(values:List<&2,Cell>,+wanted:Cell) -> Bool:
  match values:
    case Nil{}: False{}
    case head <> rest: cell_equal(head,wanted) || occupied(rest,wanted)
def empty() -> Shape: Shape{Axis{[zero()],False{}},Axis{[zero()],False{}},Axis{[zero()],False{}},[]}
def same_coords(a:List<&2,F.F64>,b:List<&2,F.F64>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: F.is_eq(x,y) && same_coords(xs,ys)
    case _ _: False{}
def coordinate_points(values:List<&2,F.F64>,+index:U32) -> List<&2,Point>:
  match values:
    case Nil{}: []
    case value <> rest: Point{value,index,index} <> coordinate_points(rest,U32.inc(index))
def appended(+value:F.F64,+ai:U32,+bi:U32,reversed:List<&2,Point>) -> List<&2,Point>:
  match reversed:
    case Nil{}: [Point{value,ai,bi}]
    case Point{+prior,a,b} <> +tail:
      pick(List<&2,Point>,F.is_lt(prior,F.sub(value,A.epsilon())),Point{value,ai,bi} <> Point{prior,a,b} <> tail,Point{prior,ai,bi} <> tail)
def accepted(first:List<&2,F.F64>,second:List<&2,F.F64>,+ai:U32,+bi:U32,reversed:List<&2,Point>,value:F.F64,skip:Bool) -> MergeFrame:
  match skip:
    case True{}: MergeFrame{first,second,ai,bi,reversed}
    case False{}: MergeFrame{first,second,ai,bi,appended(value,U32.sub(ai,1),U32.sub(bi,1),reversed)}
def merge_choose(first:List<&2,F.F64>,second:List<&2,F.F64>,+ai:U32,+bi:U32,reversed:List<&2,Point>,first_only:Bool,second_only:Bool,take_first:Bool) -> Maybe<&2,MergeFrame>:
  match first second take_first:
    case a <> ar +bs True{}: Some{accepted(ar,bs,U32.inc(ai),bi,reversed,a,Bool.not(first_only) && (U32.is_eq(bi,0) || List.is_empty(&2,F.F64,bs)))}
    case +as b <> br False{}: Some{accepted(as,br,ai,U32.inc(bi),reversed,b,Bool.not(second_only) && (U32.is_eq(ai,0) || List.is_empty(&2,F.F64,as)))}
    case _ _ _: None{}
def merge_step(frame:MergeFrame,first_only:Bool,second_only:Bool) -> Maybe<&2,MergeFrame>:
  match frame:
    case MergeFrame{Nil{},Nil{},ai,bi,reversed}: None{}
    case MergeFrame{a <> ar,Nil{},ai,bi,reversed}: merge_choose(a <> ar,[],ai,bi,reversed,first_only,second_only,True{})
    case MergeFrame{Nil{},b <> br,ai,bi,reversed}: merge_choose([],b <> br,ai,bi,reversed,first_only,second_only,False{})
    case MergeFrame{+a <> +ar,+b <> +br,ai,bi,reversed}: merge_choose(a <> ar,b <> br,ai,bi,reversed,first_only,second_only,F.is_lt(a,F.add(b,A.epsilon())))
def merge_more(frame:MergeFrame,status:Maybe<&2,MergeFrame>,next:MergeFrame -> List<&2,Point>) -> List<&2,Point>:
  match frame status:
    case MergeFrame{a,b,ai,bi,reversed} None{}: List.reverse(&2,Point,reversed)
    case _ Some{frame}: next(frame)
def indirect(fuel:Nat,+frame:MergeFrame,+first_only:Bool,+second_only:Bool) -> List<&2,Point>:
  match fuel:
    case 0n: []
    case 1n+rest: merge_more(frame,merge_step(frame,first_only,second_only),next => indirect(rest,next,first_only,second_only))
def cube_points(fuel:Nat,+index:U32,+count:U32,+first:U32,+second:U32) -> List<&2,Point>:
  match fuel:
    case 0n: []
    case 1n+rest: Point{F.div(F.from_u32(index),F.from_u32(count)),U32.div(index,U32.div(count,first)),U32.div(index,U32.div(count,second))} <> cube_points(rest,U32.inc(index),count,first,second)
def nonempty_points(values:List<&2,Point>) -> List<&2,Point>:
  match values:
    case Nil{}: [Point{zero(),4294967295,4294967295}]
    case head <> rest: head <> rest
def merge_fallback(+a:Axis,+b:Axis,first_only:Bool,second_only:Bool,identical:Bool) -> Merge:
  match a b identical:
    case Axis{xs,cube} Axis{ys,other} True{}: Merge{coordinate_points(xs,0),cube}
    case Axis{+xs,cube} Axis{+ys,other} False{}: Merge{nonempty_points(indirect(1n+Nat.add(List.length(&2,F.F64,xs),List.length(&2,F.F64,ys)),MergeFrame{xs,ys,0,0,[]},first_only,second_only)),False{}}
def merge_axis_checked(+a:Axis,+b:Axis,first_only:Bool,second_only:Bool,cubic:Bool) -> Merge:
  match a b cubic:
    case _ _ True{}:
      +count = U32.max(size(a),size(b))
      Merge{cube_points(1n+U32.to_nat(count),0,count,size(a),size(b)),True{}}
    case Axis{+xs,xc} Axis{+ys,yc} False{}:
      merge_fallback(a,b,first_only,second_only,same_coords(xs,ys))
def merge_axis(+a:Axis,+b:Axis,+multiplier:U32,first_only:Bool,second_only:Bool) -> Merge:
  Axis{xs,+xc} = a
  Axis{ys,+yc} = b
  merge_axis_checked(a,b,first_only,second_only,xc && yc && U32.is_le(U32.mul(multiplier,U32.max(size(a),size(b))),256))
def point_coords(values:List<&2,Point>) -> List<&2,F.F64>:
  match values:
    case Nil{}: []
    case Point{value,a,b} <> rest: value <> point_coords(rest)
def merge_axis_value(merged:Merge) -> Axis:
  Merge{points,cube} = merged
  Axis{point_coords(points),cube}
def merge_size(value:Merge) -> U32:
  Merge{points,cube} = value
  U32.sub(U32.from_nat(List.length(&2,Point,points)),1)
def boolean(op:U32,a:Bool,b:Bool) -> Bool:
  match op:
    case 0: a && b
    case 1: a || b
    case _: a && Bool.not(b)
def joined_z(points:List<&2,Point>,+first:List<&2,Cell>,+second:List<&2,Cell>,+px:Point,+py:Point,+x:U32,+y:U32,+z:U32,+op:U32) -> List<&2,Cell>:
  match points:
    case Nil{}: []
    case last <> Nil{}: []
    case Point{v,az,bz} <> +rest:
      Point{vx,ax,bx} = px
      Point{vy,ay,by} = py
      pick(List<&2,Cell>,boolean(op,occupied(first,Cell{ax,ay,az}),occupied(second,Cell{bx,by,bz})),Cell{x,y,z} <> joined_z(rest,first,second,px,py,x,y,U32.inc(z),op),joined_z(rest,first,second,px,py,x,y,U32.inc(z),op))
def joined_x(points:List<&2,Point>,+zs:List<&2,Point>,+first:List<&2,Cell>,+second:List<&2,Cell>,+py:Point,+x:U32,+y:U32,+op:U32) -> List<&2,Cell>:
  match points:
    case Nil{}: []
    case last <> Nil{}: []
    case +px <> rest: List.append(&2,Cell,joined_z(zs,first,second,px,py,x,y,0,op),joined_x(rest,zs,first,second,py,U32.inc(x),y,op))
def joined_y(points:List<&2,Point>,+xs:List<&2,Point>,+zs:List<&2,Point>,+first:List<&2,Cell>,+second:List<&2,Cell>,+y:U32,+op:U32) -> List<&2,Cell>:
  match points:
    case Nil{}: []
    case last <> Nil{}: []
    case +py <> rest: List.append(&2,Cell,joined_x(xs,zs,first,second,py,0,y,op),joined_y(rest,xs,zs,first,second,U32.inc(y),op))
def join_ready(+x:Merge,+y:Merge,+z:Merge,first:List<&2,Cell>,second:List<&2,Cell>,op:U32) -> Shape:
  Merge{xs,xc} = x
  Merge{ys,yc} = y
  Merge{zs,zc} = z
  Shape{merge_axis_value(x),merge_axis_value(y),merge_axis_value(z),joined_y(ys,xs,zs,first,second,0,op)}
def join_axes(+a:Shape,+b:Shape,+op:U32) -> Shape:
  Shape{ax,ay,az,ac} = a
  Shape{bx,by,bz,bc} = b
  +first_only = U32.is_ne(op,0)
  +second_only = U32.is_eq(op,1)
  +x = merge_axis(ax,bx,1,first_only,second_only)
  +y = merge_axis(ay,by,merge_size(x),first_only,second_only)
  z = merge_axis(az,bz,U32.mul(merge_size(x),merge_size(y)),first_only,second_only)
  join_ready(x,y,z,ac,bc,op)
def join_gate(+a:Shape,+b:Shape,+op:U32,a_empty:Bool,b_empty:Bool) -> Shape:
  match a_empty b_empty:
    case True{} _: pick(Shape,U32.is_eq(op,1),b,empty())
    case False{} True{}: pick(Shape,U32.is_ne(op,0),a,empty())
    case False{} False{}: join_axes(a,b,op)
def join_unoptimized(+a:Shape,+b:Shape,op:U32) -> Shape:
  Shape{ax,ay,az,ac} = a
  Shape{bx,by,bz,bc} = b
  join_gate(a,b,op,List.is_empty(&2,Cell,ac),List.is_empty(&2,Cell,bc))

# Shapes.create's dyadic unit-cube detection and Math.round tie convention.
def round_read(+value:F.F64,result:Result<&2,&2,F.F64ConversionError,U32>) -> Result<&2,&2,String,U32>:
  match result:
    case Fail{error}: Fail{"geometry:unit-round-range"}
    case Done{+floor}: Done{pick(U32,F.is_ge(value,F.add(F.from_i32(floor),F.from_f32(0.5))),U32.inc(floor),floor)}
def round_small(+value:F.F64) -> Result<&2,&2,String,U32>: round_read(value,F.floor_i32(value))
def bits_next(bits:U32,hit:Bool,next:Unit -> Result<&2,&2,String,U32>) -> Result<&2,&2,String,U32>:
  match hit:
    case True{}: Done{bits}
    case False{}: next(Unit{})
def find_bits_loop(fuel:Nat,+lo:F.F64,+hi:F.F64,+bits:U32) -> Result<&2,&2,String,U32>:
  match fuel:
    case 0n: Done{4294967295}
    case 1n+rest:
      +scale = F.from_u32(U32.shln(1,U32.to_nat(bits)))
      +a = F.mul(lo,scale)
      +b = F.mul(hi,scale)
      do Result<&2,&2,String,U32>:
        x : U32 <- round_small(a)
        y : U32 <- round_small(b)
        bits_next(bits,F.is_lt(F.abs(F.sub(a,F.from_i32(x))),F.mul(A.epsilon(),scale)) && F.is_lt(F.abs(F.sub(b,F.from_i32(y))),F.mul(A.epsilon(),scale)),u => find_bits_loop(rest,lo,hi,U32.inc(bits)))
def find_bits_gate(lo:F.F64,hi:F.F64,admitted:Bool) -> Result<&2,&2,String,U32>:
  match admitted:
    case True{}: find_bits_loop(4n,lo,hi,0)
    case False{}: Done{4294967295}
def find_bits(+lo:F.F64,+hi:F.F64) -> Result<&2,&2,String,U32>:
  find_bits_gate(lo,hi,F.is_ge(lo,F.neg(A.epsilon())) && F.is_le(hi,F.F64{1072693248,450359963}))
def coords(fuel:Nat,+index:U32,+count:U32) -> List<&2,F.F64>:
  match fuel:
    case 0n: []
    case 1n+rest: F.div(F.from_u32(index),F.from_u32(count)) <> coords(rest,U32.inc(index),count)
def rect_z(fuel:Nat,+x:U32,+y:U32,+z:U32) -> List<&2,Cell>:
  match fuel:
    case 0n: []
    case 1n+rest: Cell{x,y,z} <> rect_z(rest,x,y,U32.inc(z))
def rect_x(fuel:Nat,+x:U32,+y:U32,+z:U32,+depth:U32) -> List<&2,Cell>:
  match fuel:
    case 0n: []
    case 1n+rest: List.append(&2,Cell,rect_z(U32.to_nat(depth),x,y,z),rect_x(rest,U32.inc(x),y,z,depth))
def rect_y(fuel:Nat,+x:U32,+y:U32,+z:U32,+width:U32,+depth:U32) -> List<&2,Cell>:
  match fuel:
    case 0n: []
    case 1n+rest: List.append(&2,Cell,rect_x(U32.to_nat(width),x,y,z,depth),rect_y(rest,x,U32.inc(y),z,width,depth))
def cube_axis(lo:F.F64,hi:F.F64,+bits:U32) -> Result<&2,&2,String,Range>:
  +count = U32.shln(1,U32.to_nat(bits))
  do Result<&2,&2,String,Range>:
    start : U32 <- round_small(F.mul(lo,F.from_u32(count)))
    end : U32 <- round_small(F.mul(hi,F.from_u32(count)))
    return Range{Axis{coords(1n+U32.to_nat(count),0,count),True{}},start,end}
def cube_rect(x:Range,y:Range,z:Range) -> Shape:
  Range{ax,+xs,xe} = x
  Range{ay,+ys,ye} = y
  Range{az,+zs,ze} = z
  Shape{ax,ay,az,rect_y(U32.to_nat(U32.sub(ye,ys)),xs,ys,zs,U32.sub(xe,xs),U32.sub(ze,zs))}
def create_bits(box:A.AABB,x:U32,y:U32,z:U32,raw:Bool) -> Result<&2,&2,String,Shape>:
  match box raw:
    case A.AABB{a,b,c,d,e,f} True{}: Done{Shape{Axis{[a,d],False{}},Axis{[b,e],False{}},Axis{[c,f],False{}},[Cell{0,0,0}]}}
    case A.AABB{a,b,c,d,e,f} False{}:
      do Result<&2,&2,String,Shape>:
        ax : Range <- cube_axis(a,d,x)
        ay : Range <- cube_axis(b,e,y)
        az : Range <- cube_axis(c,f,z)
        return cube_rect(ax,ay,az)
def create_nonempty(+box:A.AABB) -> Result<&2,&2,String,Shape>:
  A.AABB{a,b,c,d,e,f} = box
  do Result<&2,&2,String,Shape>:
    +x : U32 <- find_bits(a,d)
    +y : U32 <- find_bits(b,e)
    +z : U32 <- find_bits(c,f)
    create_bits(box,x,y,z,U32.is_eq(x,4294967295) || U32.is_eq(y,4294967295) || U32.is_eq(z,4294967295))
def create_checked(box:A.AABB,small:Bool) -> Result<&2,&2,String,Shape>:
  match small:
    case True{}: Done{empty()}
    case False{}: create_nonempty(box)
def create(+box:A.AABB) -> Result<&2,&2,String,Shape>:
  A.AABB{a,b,c,d,e,f} = box
  create_checked(box,F.is_lt(F.sub(d,a),A.epsilon()) || F.is_lt(F.sub(e,b),A.epsilon()) || F.is_lt(F.sub(f,c),A.epsilon()))
def z_strip(fuel:Nat,+cells:List<&2,Cell>,+x:U32,+y:U32,+z:U32) -> Bool:
  match fuel:
    case 0n: True{}
    case 1n+rest: occupied(cells,Cell{x,y,z}) && z_strip(rest,cells,x,y,U32.inc(z))
def xz_rectangle(fuel:Nat,+cells:List<&2,Cell>,+x:U32,+y:U32,+z:U32,+depth:U32) -> Bool:
  match fuel:
    case 0n: True{}
    case 1n+rest: z_strip(U32.to_nat(depth),cells,x,y,z) && xz_rectangle(rest,cells,U32.inc(x),y,z,depth)
def run_z_next(accepted:Bool,index:U32,next:Unit -> U32) -> U32:
  match accepted:
    case False{}: index
    case True{}: next(Unit{})
def run_z(fuel:Nat,+cells:List<&2,Cell>,+x:U32,+y:U32,+z:U32) -> U32:
  match fuel:
    case 0n: z
    case 1n+rest: run_z_next(occupied(cells,Cell{x,y,z}),z,u => run_z(rest,cells,x,y,U32.inc(z)))
def run_x(fuel:Nat,+cells:List<&2,Cell>,+x:U32,+y:U32,+z:U32,+depth:U32) -> U32:
  match fuel:
    case 0n: x
    case 1n+rest: run_z_next(z_strip(U32.to_nat(depth),cells,x,y,z),x,u => run_x(rest,cells,U32.inc(x),y,z,depth))
def run_y(fuel:Nat,+cells:List<&2,Cell>,+x:U32,+y:U32,+z:U32,+width:U32,+depth:U32) -> U32:
  match fuel:
    case 0n: y
    case 1n+rest: run_z_next(xz_rectangle(U32.to_nat(width),cells,x,y,z,depth),y,u => run_y(rest,cells,x,U32.inc(y),z,width,depth))
def inside(cell:Cell,a:Cell,b:Cell) -> Bool:
  Cell{+x,+y,+z} = cell
  Cell{u,v,w} = a
  Cell{p,q,r} = b
  U32.is_ge(x,u) && U32.is_lt(x,p) && U32.is_ge(y,v) && U32.is_lt(y,q) && U32.is_ge(z,w) && U32.is_lt(z,r)
def cleared(values:List<&2,Cell>,+a:Cell,+b:Cell) -> List<&2,Cell>:
  match values:
    case Nil{}: []
    case +head <> +rest: pick(List<&2,Cell>,inside(head,a,b),cleared(rest,a,b),head <> cleared(rest,a,b))
def grid_box(x:Axis,y:Axis,z:Axis,a:Cell,b:Cell) -> A.AABB:
  Axis{+xs,cx} = x
  Axis{+ys,cy} = y
  Axis{+zs,cz} = z
  Cell{ax,ay,az} = a
  Cell{bx,by,bz} = b
  A.AABB{at(xs,ax),at(ys,ay),at(zs,az),at(xs,bx),at(ys,by),at(zs,bz)}
def box_last(+x:Axis,+y:Axis,+z:Axis,+cells:List<&2,Cell>,+a:Cell,bx:U32,by:U32,bz:U32) -> BoxStep:
  +b : Cell = Cell{bx,by,bz}
  BoxStep{cleared(cells,a,b),grid_box(x,y,z,a,b)}
def box_y(+x:Axis,+y:Axis,+z:Axis,+cells:List<&2,Cell>,+a:Cell,+bx:U32,+bz:U32) -> BoxStep:
  Cell{+ax,+ay,+az} = a
  box_last(x,y,z,cells,a,bx,run_y(U32.to_nat(size(y)),cells,ax,ay,az,U32.sub(bx,ax),U32.sub(bz,az)),bz)
def box_x(+x:Axis,+y:Axis,+z:Axis,+cells:List<&2,Cell>,+a:Cell,+bz:U32) -> BoxStep:
  Cell{+ax,ay,+az} = a
  box_y(x,y,z,cells,a,run_x(U32.to_nat(size(x)),cells,ax,ay,az,U32.sub(bz,az)),bz)
def box_first(+x:Axis,+y:Axis,+z:Axis,+cells:List<&2,Cell>,+a:Cell) -> BoxStep:
  Cell{ax,ay,+az} = a
  box_x(x,y,z,cells,a,run_z(U32.to_nat(size(z)),cells,ax,ay,az))
def boxes_more(step:BoxStep,next:List<&2,Cell> -> List<&2,A.AABB>) -> List<&2,A.AABB>:
  BoxStep{cells,box} = step
  box <> next(cells)
def boxes_loop(fuel:Nat,+x:Axis,+y:Axis,+z:Axis,cells:List<&2,Cell>) -> List<&2,A.AABB>:
  match fuel cells:
    case _ Nil{}: []
    case 0n _: []
    case 1n+rest +head <> +tail: boxes_more(box_first(x,y,z,head <> tail,head),left => boxes_loop(rest,x,y,z,left))
def boxes(shape:Shape) -> List<&2,A.AABB>:
  Shape{x,y,z,+cells} = shape
  boxes_loop(List.length(&2,Cell,cells),x,y,z,cells)
def optimize_boxes(values:List<&2,A.AABB>,current:Shape) -> Result<&2,&2,String,Shape>:
  match values:
    case Nil{}: Done{current}
    case head <> rest:
      do Result<&2,&2,String,Shape>:
        created : Shape <- create(head)
        optimize_boxes(rest,join_unoptimized(current,created,1))
def optimize(shape:Shape) -> Result<&2,&2,String,Shape>: optimize_boxes(boxes(shape),empty())
def join(a:Shape,b:Shape,op:U32) -> Result<&2,&2,String,Shape>: optimize(join_unoptimized(a,b,op))
def clamp(+value:F.F64,+lo:F.F64,+hi:F.F64) -> F.F64:
  pick(F.F64,F.is_lt(value,lo),lo,pick(F.F64,F.is_gt(value,hi),hi,value))
def candidate(point:V.Vec3,box:A.AABB) -> V.Vec3:
  V.Vec3{x,y,z} = point
  A.AABB{a,b,c,d,e,f} = box
  V.Vec3{clamp(x,a,d),clamp(y,b,e),clamp(z,c,f)}
def distance(a:V.Vec3,b:V.Vec3) -> F.F64:
  V.Vec3{ax,ay,az} = a
  V.Vec3{bx,by,bz} = b
  +x = F.sub(ax,bx)
  +y = F.sub(ay,by)
  +z = F.sub(az,bz)
  F.add(F.add(F.mul(x,x),F.mul(y,y)),F.mul(z,z))
def closest_choice(value:V.Vec3,old:V.Vec3,nearer:Bool) -> Maybe<&2,V.Vec3>:
  match nearer:
    case True{}: Some{value}
    case False{}: Some{old}
def closest_more(+point:V.Vec3,+value:V.Vec3,prior:Maybe<&2,V.Vec3>) -> Maybe<&2,V.Vec3>:
  match prior:
    case None{}: Some{value}
    case Some{+old}: closest_choice(value,old,F.is_lt(distance(point,value),distance(point,old)))
def closest_boxes(values:List<&2,A.AABB>,+point:V.Vec3,prior:Maybe<&2,V.Vec3>) -> Maybe<&2,V.Vec3>:
  match values:
    case Nil{}: prior
    case head <> rest: closest_boxes(rest,point,closest_more(point,candidate(point,head),prior))
def closest(shape:Shape,point:V.Vec3) -> Maybe<&2,V.Vec3>: closest_boxes(boxes(shape),point,None{})

def volume_fit_nonzero(a:U32,b:U32,c:U32,budget:U32,empty:Bool) -> Bool:
  match empty:
    case True{}: True{}
    case False{}: U32.is_le(a,U32.div(U32.div(budget,c),b))
def volume_fit(+a:U32,+b:U32,+c:U32,budget:U32) -> Bool:
  volume_fit_nonzero(a,b,c,budget,U32.is_eq(a,0) || U32.is_eq(b,0) || U32.is_eq(c,0))
def join_limited_ready(x:Merge,y:Merge,z:Merge,first:List<&2,Cell>,second:List<&2,Cell>,op:U32,allowed:Bool) -> Result<&2,&2,String,Shape>:
  match allowed:
    case False{}: Fail{"geometry:voxel-budget"}
    case True{}: Done{join_ready(x,y,z,first,second,op)}
def join_limited_axes(+a:Shape,+b:Shape,+op:U32,budget:U32) -> Result<&2,&2,String,Shape>:
  Shape{ax,ay,az,ac} = a
  Shape{bx,by,bz,bc} = b
  +first_only = U32.is_ne(op,0)
  +second_only = U32.is_eq(op,1)
  +x = merge_axis(ax,bx,1,first_only,second_only)
  +y = merge_axis(ay,by,merge_size(x),first_only,second_only)
  +z = merge_axis(az,bz,U32.mul(merge_size(x),merge_size(y)),first_only,second_only)
  join_limited_ready(x,y,z,ac,bc,op,volume_fit(merge_size(x),merge_size(y),merge_size(z),budget))
def join_limited_gate(+a:Shape,+b:Shape,+op:U32,budget:U32,a_empty:Bool,b_empty:Bool) -> Result<&2,&2,String,Shape>:
  match a_empty b_empty:
    case True{} _: Done{pick(Shape,U32.is_eq(op,1),b,empty())}
    case False{} True{}: Done{pick(Shape,U32.is_ne(op,0),a,empty())}
    case False{} False{}: join_limited_axes(a,b,op,budget)
def join_unoptimized_limited(+a:Shape,+b:Shape,op:U32,budget:U32) -> Result<&2,&2,String,Shape>:
  Shape{ax,ay,az,ac} = a
  Shape{bx,by,bz,bc} = b
  join_limited_gate(a,b,op,budget,List.is_empty(&2,Cell,ac),List.is_empty(&2,Cell,bc))
def optimize_limited_boxes(values:List<&2,A.AABB>,current:Shape,+budget:U32) -> Result<&2,&2,String,Shape>:
  match values:
    case Nil{}: Done{current}
    case head <> rest:
      do Result<&2,&2,String,Shape>:
        created : Shape <- create(head)
        next : Shape <- join_unoptimized_limited(current,created,1,budget)
        optimize_limited_boxes(rest,next,budget)
def optimize_limited(shape:Shape,budget:U32) -> Result<&2,&2,String,Shape>: optimize_limited_boxes(boxes(shape),empty(),budget)
def join_limited(a:Shape,b:Shape,op:U32,+budget:U32) -> Result<&2,&2,String,Shape>:
  do Result<&2,&2,String,Shape>:
    joined : Shape <- join_unoptimized_limited(a,b,op,budget)
    optimize_limited(joined,budget)
