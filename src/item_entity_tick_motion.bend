import Base
import ./item_entity_tick_model.bend as T
import ./item_entity_tick_fields.bend as U
import ./item_entity_tick_fluid.bend as D
import ./cooking_effect_entities_model.bend as E
import ./cooking_effect_geometry.bend as G
import ./cooking_effect_geometry_voxel.bend as Grid
import ./movement.bend as M
import ./geometry.bend as A
import ./vanilla_entity_fields.bend as V
import ./random.bend as R
import ./f64.bend as F
import ./support.bend as S
import ./travel.bend as Travel

type MotionResult is Data:
  MotionResult{+snapshot:T.Snapshot,events:List<&2,T.Publication>}
type EscapeChoice is Data:
  EscapeChoice{axis:A.Axis,+positive:Bool,distance:F.F64}
def cell(+context:T.Context,+point:Travel.BlockPos) -> Result<&2,&2,T.Error,T.Cell>:
  T.Context{+items,+g,+cells,+coverage,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+budget,+clip,+context_tail}=context
  Travel.BlockPos{+x,+y,+z}=point
  D.lookup(cells,x,y,z)
def candidate_position(+box:A.AABB) -> Travel.BlockPos:
  A.AABB{+x,+y,+z,+a,+b,+c}=box
  Travel.BlockPos{V.floor_word(x),V.floor_word(y),V.floor_word(z)}
def support_candidates(values:List<&2,G.Obstacle>,+query:A.AABB,+shape:Grid.Shape,+budget:U32) -> Result<&2,&2,T.Error,List<&2,S.Candidate>>:
  match values:
    case Nil{}: Done{[]}
    case +obstacle <> +rest:
      G.Obstacle{+box,+source,+full}=obstacle
      do Result<&2,&2,T.Error,List<&2,S.Candidate>>:
        +hit : Bool <- U.string_result(Bool,G.obstacle_hit(obstacle,query,shape,budget))
        +tail : List<&2,S.Candidate> <- support_candidates(rest,query,shape,budget)
        return List.append(&2,S.Candidate,U.select(List<&2,S.Candidate>,[S.FullCube{candidate_position(box)}],[],hit),tail)
def support_selection(+context:G.Context,+point:V.Vec3,+query:A.AABB) -> Result<&2,&2,T.Error,Maybe<&2,Travel.BlockPos>>:
  G.Context{+d,+coverage,+blocks,+entities,+budget}=context
  do Result<&2,&2,T.Error,Maybe<&2,Travel.BlockPos>>:
    _ : Unit <- U.guard(G.contained(query,coverage),"item support query outside observed geometry")
    +shape : Grid.Shape <- U.string_result(Grid.Shape,Grid.create(query))
    +candidates : List<&2,S.Candidate> <- support_candidates(blocks,query,shape,budget)
    return S.select(U.mv(point),query,candidates)
def support_fallback(+context:G.Context,+point:V.Vec3,+query:A.AABB,+state:S.State,+primary:Maybe<&2,Travel.BlockPos>,+delta:V.Vec3,+needed:Bool) -> Result<&2,&2,T.Error,S.State>:
  match needed:
    case False{}: Done{S.update_cached(state,True{},primary,None{},True{})}
    case True{}:
      do Result<&2,&2,T.Error,S.State>:
        +fallback : Maybe<&2,Travel.BlockPos> <- support_selection(context,point,S.fallback_query(query,U.mv(delta)))
        return S.update_cached(state,True{},primary,fallback,True{})
def support_update(+context:G.Context,+point:V.Vec3,+box:A.AABB,+state:S.State,+ground:Bool,+delta:V.Vec3) -> Result<&2,&2,T.Error,S.State>:
  match ground:
    case False{}: Done{S.empty()}
    case True{}:
      +query=S.primary_query(box)
      do Result<&2,&2,T.Error,S.State>:
        +primary : Maybe<&2,Travel.BlockPos> <- support_selection(context,point,query)
        support_fallback(context,point,query,state,primary,delta,S.needs_fallback(state,True{},primary,Some{U.mv(delta)}))
def entity_boxes(boxes:List<&2,A.AABB>) -> List<&2,A.Collider>:
  match boxes:
    case Nil{}: []
    case +b <> +rest: A.BoxCollider{b} <> entity_boxes(rest)
def boxes(values:List<&2,G.Obstacle>) -> List<&2,A.Collider>:
  match values:
    case Nil{}: []
    case G.Obstacle{+box,+shape,+full} <> +rest: List.append(&2,A.Collider,entity_boxes(Grid.boxes(shape)),boxes(rest))
def no_collision(+context:G.Context,+box:A.AABB) -> Result<&2,&2,T.Error,Bool>:
  G.Context{+d,+coverage,+blocks,+entities,+budget}=context
  do Result<&2,&2,T.Error,Bool>:
    _ : Unit <- U.guard(G.contained(box,coverage),"item collision query outside observed geometry")
    +query : Grid.Shape <- U.string_result(Grid.Shape,Grid.create(box))
    +blocked : Bool <- U.string_result(Bool,G.blocks_hit(blocks,box,query,budget))
    return Bool.not(blocked || G.entities_hit(entities,box))
def physical_no_physics(+p:T.Physical,+v:Bool) -> T.Physical:
  T.Physical{+g,+old,+s,+x,+y,+z,+minor,+stuck}=p
  T.Physical{g,v,s,x,y,z,minor,stuck}
def escape_consider(+prior:EscapeChoice,axis:A.Axis,+positive:Bool,+value:F.F64,+full:Bool) -> EscapeChoice:
  EscapeChoice{+old_axis,+old_positive,+distance}=prior
  U.select(EscapeChoice,EscapeChoice{axis,positive,value},EscapeChoice{old_axis,old_positive,distance},Bool.not(full) && F.is_lt(value,distance))
def full(+cell:T.Cell) -> Bool:
  T.Cell{+state,+x,+y,+z,+w,+l,+h,+ch,+flow,+fluid,+full,+f,+s,+r,+suppress,+inside,+step,+wb,+bubble,+fall,+cell_tail}=cell
  full
def escape_choice(+context:T.Context,+point:V.Vec3) -> Result<&2,&2,T.Error,EscapeChoice>:
  V.Vec3{+x,+y,+z}=point
  +bx=V.floor_word(x)
  +by=V.floor_word(y)
  +bz=V.floor_word(z)
  +fx=F.sub(x,F.from_i32(bx))
  +fy=F.sub(y,F.from_i32(by))
  +fz=F.sub(z,F.from_i32(bz))
  do Result<&2,&2,T.Error,EscapeChoice>:
    +north : T.Cell <- cell(context,Travel.BlockPos{bx,by,U32.sub(bz,1)})
    +south : T.Cell <- cell(context,Travel.BlockPos{bx,by,U32.inc(bz)})
    +west : T.Cell <- cell(context,Travel.BlockPos{U32.sub(bx,1),by,bz})
    +east : T.Cell <- cell(context,Travel.BlockPos{U32.inc(bx),by,bz})
    +up : T.Cell <- cell(context,Travel.BlockPos{bx,U32.inc(by),bz})
    return escape_consider(escape_consider(escape_consider(escape_consider(escape_consider(EscapeChoice{A.AxisY{},True{},F.F64{2146435071,4294967295}},A.AxisZ{},False{},fz,full(north)),A.AxisZ{},True{},F.sub(F.from_u32(1),fz),full(south)),A.AxisX{},False{},fx,full(west)),A.AxisX{},True{},F.sub(F.from_u32(1),fx),full(east)),A.AxisY{},True{},F.sub(F.from_u32(1),fy),full(up))
def record_random(+record:E.Record,+source:R.Source) -> E.Record:
  U.with_common(record,U.set_random(E.common(record),source))
def escape_draw(+record:E.Record,+choice:EscapeChoice,result:R.Source & F32) -> E.Record:
  EscapeChoice{+axis,+positive,+distance}=choice
  (+source,+draw)=result
  speed=F.from_f32(F32.mul(U.select(F32,1.0,F32.neg(1.0),positive),F32.add(F32.mul(draw,0.2),0.1)))
  record_random(U.set_velocity(record,U.vv(M.Vec3.with_axis(U.mv(U.scale(U.velocity(record),F.F64{1072168960,0},F.F64{1072168960,0},F.F64{1072168960,0})),axis,speed))),source)
def random(+record:E.Common) -> R.Source:
  E.Common{+d,+id,+a,+b,+r,+f,+t,+first,+removed,+accessible,+order}=record
  r
def escaped(+record:E.Record,+choice:EscapeChoice) -> E.Record:
  escape_draw(record,choice,R.next_float(random(E.common(record))))
def geometry(+context:T.Context) -> G.Context:
  T.Context{+items,+g,+cells,+coverage,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+budget,+clip,+context_tail}=context
  g
def escape_point(+context:T.Context,+record:E.Record,+runtime:T.Runtime,+box:A.AABB) -> Result<&2,&2,T.Error,T.Snapshot>:
  A.AABB{+x,+a,+z,+b,+c,+d}=box
  do Result<&2,&2,T.Error,T.Snapshot>:
    +choice : EscapeChoice <- escape_choice(context,G.shift_y(U.pos(record),F.mul(F.sub(c,a),F.from_f32(0.5))))
    return T.Snapshot{escaped(record,choice),runtime}
def collision_escape(+context:T.Context,+record:E.Record,+runtime:T.Runtime,+blocked:Bool) -> Result<&2,&2,T.Error,T.Snapshot>:
  match blocked:
    case False{}: Done{T.Snapshot{record,runtime}}
    case True{}: escape_point(context,record,runtime,U.body(record))
def collision(+context:T.Context,+snapshot:T.Snapshot) -> Result<&2,&2,T.Error,T.Snapshot>:
  T.Context{+items,+g,+cells,+coverage,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+budget,+clip,+context_tail}=context
  T.Snapshot{+record,T.Runtime{+physical,+base,+fluids,+pending,+movements,+support,+runtime_tail}}=snapshot
  do Result<&2,&2,T.Error,T.Snapshot>:
    +clear : Bool <- no_collision(g,G.inflate(U.body(record),F.neg(A.epsilon())))
    collision_escape(context,record,T.Runtime{physical_no_physics(physical,server && Bool.not(clear)),base,fluids,pending,movements,support,runtime_tail},server && Bool.not(clear))
def magnitude_gate(+v:V.Vec3,+water:Bool,+lava:Bool,+gravity:Bool) -> V.Vec3:
  V.Vec3{+x,+y,+z}=v
  +scale=U.select(F.F64,F.from_f32(0.99),F.from_f32(0.95),water)
  +floating=water || lava
  V.Vec3{U.select(F.F64,F.mul(x,scale),x,floating),
    U.select(F.F64,F.add(y,U.select(F.F64,F.from_f32(0.0005),U.zero(),F.is_lt(y,F.from_f32(0.06)))),U.select(F.F64,F.sub(y,F.F64{1067743969,1202590843}),y,gravity),floating),
    U.select(F.F64,F.mul(z,scale),z,floating)}
def buoyancy(+record:E.Record,+runtime:T.Runtime) -> E.Record:
  T.Runtime{T.Physical{+g,+np,+s,+h,+v,+b,+m,+stuck},+base,T.Fluids{T.Fluid{+wh,+wf,+wn,+wp},T.Fluid{+lh,+lf,+ln,+lp},+ew,+el,+fast},+pending,+movements,+support,+runtime_tail}=runtime
  U.set_velocity(record,magnitude_gate(U.velocity(record),F.is_gt(wh,F.from_f32(0.1)),F.is_gt(lh,F.from_f32(0.1)),Bool.not(g)))
def physics_flags(+p:T.Physical,+np:Bool,+h:Bool,+v:Bool,+b:Bool,+stuck:V.Vec3) -> T.Physical:
  T.Physical{+g,+old,+s,+x,+y,+z,+m,+previous}=p
  T.Physical{g,np,s,h,v,b,False{},stuck}
def fields_motion(f:V.Fields,+position:V.Vec3,+velocity:V.Vec3,+fall:F.F64,+ground:Bool) -> V.Fields:
  V.Fields{+p,+v,+o,+old,+l,+h,+b,+previous,+g,+a,+fire,+portal,+i,+sync}=f
  V.Fields{position,velocity,o,old,l,h,b,fall,ground,a,fire,portal,i,sync}
def fall_fields(f:V.Fields) -> F.F64:
  V.Fields{+p,+v,+o,+old,+l,+h,+b,+fall,+g,+a,+fire,+portal,+i,+s}=f
  fall
def restitution(+velocity:V.Vec3,+delta:V.Vec3,+gravity:F.F64,+r:F.F64,+vertical:Bool,+below:Bool,+xb:Bool,+zb:Bool) -> V.Vec3:
  V.Vec3{+x,+y,+z}=velocity
  V.Vec3{+a,+dy,+b}=delta
  +ratio=U.select(F.F64,F.div(dy,y),U.zero(),F.is_gt(r,U.zero()))
  +g=F.mul(ratio,gravity)
  +drag=F.add(F.from_u32(1),F.mul(ratio,F.sub(F.from_f32(0.98),F.from_u32(1))))
  V.Vec3{U.select(F.F64,F.mul(F.neg(x),U.zero()),x,xb),U.select(F.F64,F.mul(F.mul(F.sub(g,y),drag),r),y,vertical),U.select(F.F64,F.mul(F.neg(z),U.zero()),z,zb)}
def air_drag(+velocity:V.Vec3,+friction:F32,+ground:Bool) -> V.Vec3:
  V.Vec3{+x,+y,+z}=velocity
  +horizontal=F.from_f32(U.select(F32,F32.mul(0.98,friction),0.98,ground))
  +v=U.scale(velocity,horizontal,F.from_f32(0.98),horizontal)
  U.select(V.Vec3,U.scale(v,F.from_u32(1),F.from_f32(F32.neg(0.5)),F.from_u32(1)),v,ground && F.is_lt(y,U.zero()))
def speed_cell(+current:T.Cell,+below:T.Cell) -> F32:
  T.Cell{+state,+x,+y,+z,+w,+l,+h,+ch,+flow,+fluid,+full,+f,+s,+r,+suppress,+inside,+step,+water,+bubble,+fall,+cell_tail}=current
  T.Cell{+state,+x,+y,+z,+w,+l,+h,+ch,+flow,+fluid,+full,+f,+bs,+r,+suppress,+inside,+step,+wb,+bc,+fall,+cell_tail}=below
  U.select(F32,s,U.select(F32,bs,s,F32.is_eq(s,1.0)),water || bubble)
def bounciness(+cell:T.Cell,+down_speed:F.F64,+gravity:F.F64,+suppress:Bool) -> F.F64:
  T.Cell{+state,+x,+y,+z,+w,+l,+h,+ch,+flow,+fluid,+full,+f,+s,+r,+suppresses,+inside,+step,+water,+bubble,+fall,+cell_tail}=cell
  U.select(F.F64,U.zero(),F.from_f32(F32.mul(r,0.8)),F.is_le(down_speed,gravity) || suppress || suppresses)
def friction(+cell:T.Cell) -> F32:
  T.Cell{+state,+x,+y,+z,+w,+l,+h,+ch,+flow,+fluid,+full,+f,+s,+r,+suppress,+inside,+step,+wb,+bubble,+fall,+cell_tail}=cell
  f
def neutral_cells(cells:List<&2,T.Cell>,+box:A.AABB) -> Result<&2,&2,T.Error,Unit>:
  match cells:
    case Nil{}: Done{Unit{}}
    case T.Cell{+state,+x,+y,+z,+w,+l,+h,+ch,+flow,+fluid,+full,+f,+s,+r,+suppresses,+inside,+step,+wb,+bubble,+fall,+cell_tail} <> +rest:
      do Result<&2,&2,T.Error,Unit>:
        _ : Unit <- U.guard(inside || Bool.not(A.AABB.intersects(box,A.AABB{F.from_i32(x),F.from_i32(y),F.from_i32(z),F.from_i32(U32.inc(x)),F.from_i32(U32.inc(y)),F.from_i32(U32.inc(z))})),"item inside-block callback unavailable for swept cells")
        neutral_cells(rest,box)
def effects_neutral(+context:T.Context,+box:A.AABB) -> Result<&2,&2,T.Error,Unit>:
  T.Context{+items,+g,+cells,+coverage,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+budget,+clip,+context_tail}=context
  do Result<&2,&2,T.Error,Unit>:
    _ : Unit <- U.guard(G.contained(box,coverage),"item inside-block swept region outside observed cells")
    +bounds : D.ScanBounds <- D.bounds(box)
    _ : D.FluidFrame <- D.scan_ready(cells,box,U.vec(),U.zero(),bounds,budget)
    neutral_cells(cells,box)
def clip_fall_gate(+fall:F.F64,observation:Maybe<&2,Bool>,+needed:Bool) -> Result<&2,&2,T.Error,F.F64>:
  match observation needed:
    case _ False{}: Done{fall}
    case Some{+reset} True{}: Done{U.select(F.F64,U.zero(),fall,reset)}
    case None{} True{}: Fail{T.Refused{"item fall-resetting raycast observation unavailable"}}
def clip_fall(+fall:F.F64,+delta:V.Vec3,observation:Maybe<&2,Bool>) -> Result<&2,&2,T.Error,F.F64>:
  clip_fall_gate(fall,observation,F.is_ne(fall,U.zero()) && F.is_ge(U.length(delta),F.from_u32(1)))
def fall_after(+fall:F.F64,+delta:V.Vec3,+water:Bool,+ground:Bool) -> F.F64:
  V.Vec3{+x,+y,+z}=delta
  U.select(F.F64,U.zero(),U.select(F.F64,F.sub(fall,F.from_f32(F.to_f32(y))),fall,Bool.not(water) && F.is_lt(y,U.zero())),ground)
def neutral_step(+cell:T.Cell) -> Bool:
  T.Cell{+state,+x,+y,+z,+w,+l,+h,+ch,+flow,+fluid,+full,+f,+s,+r,+suppress,+inside,+step,+wb,+bubble,+fall,+cell_tail}=cell
  step
def compact_movement(values:List<&2,T.Movement>,large:Bool) -> List<&2,T.Movement>:
  match values large:
    case T.Movement{+a,+b,+request} <> T.Movement{+c,+d,+other} <> +rest True{}: T.Movement{a,d,U.sub(d,a)} <> rest
    case +values _: values
def recorded(+pending:List<&2,T.Movement>,movement:T.Movement) -> List<&2,T.Movement>:
  List.append(&2,T.Movement,compact_movement(pending,Nat.is_ge(List.length(&2,T.Movement,pending),100n)),[movement])
def history_end(values:List<&2,T.Movement>,+position:V.Vec3) -> List<&2,T.Movement>:
  match values:
    case Nil{}: []
    case T.Movement{+a,+b,+request} <> Nil{}:
      List.append(&2,T.Movement,[T.Movement{a,b,request}],U.select(List<&2,T.Movement>,[T.Movement{b,position,U.sub(position,b)}],[],F.is_gt(U.length(U.sub(b,position)),F.F64{1037794527,3221225472})))
    case +h <> rest: h <> history_end(rest,position)
def history_finish(+pending:List<&2,T.Movement>,+from:V.Vec3,+position:V.Vec3,empty:Bool) -> List<&2,T.Movement>:
  match empty:
    case True{}: [T.Movement{from,position,U.sub(position,from)}]
    case False{}: history_end(pending,position)
def old_position(f:V.Fields) -> V.Vec3:
  V.Fields{+p,+v,+o,+old,+l,+h,+b,+fall,+g,+a,+fire,+portal,+i,+s}=f
  old
def finished_history(+record:E.Record,+pending:List<&2,T.Movement>,+movement:T.Movement,+advanced:Bool) -> List<&2,T.Movement>:
  T.Movement{+a,+b,+request}=movement
  +queue=U.select(List<&2,T.Movement>,recorded(pending,movement),pending,advanced)
  history_finish(queue,old_position(U.fields(record)),b,List.is_empty(&2,T.Movement,queue))
def history_neutral(+context:T.Context,values:List<&2,T.Movement>) -> Result<&2,&2,T.Error,Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case T.Movement{+from,+to,+requested} <> +rest:
      do Result<&2,&2,T.Error,Unit>:
        _ : Unit <- effects_neutral(context,G.enclosing(M.make_box(U.mv(from),0.25,0.25),M.make_box(U.mv(to),0.25,0.25)))
        history_neutral(context,rest)
def stationary_step(+context:T.Context,+record:E.Record,+support:S.State,+ground:Bool) -> Result<&2,&2,T.Error,Unit>:
  match ground:
    case False{}: Done{Unit{}}
    case True{}:
      do Result<&2,&2,T.Error,Unit>:
        +under : T.Cell <- cell(context,S.get_on_pos(U.mv(U.pos(record)),support,0.2))
        U.guard(neutral_step(under),"stationary item stepOn callback unavailable")
def stationary_effects(+context:T.Context,+snapshot:T.Snapshot,+affected:Bool) -> Result<&2,&2,T.Error,MotionResult>:
  T.Snapshot{+record,T.Runtime{+physical,+base,+fluids,+pending,+movements,+support,+runtime_tail}}=snapshot
  match affected:
    case False{}: Done{MotionResult{snapshot,[]}}
    case True{}:
      do Result<&2,&2,T.Error,MotionResult>:
        _ : Unit <- stationary_step(context,record,support,U.ground(record))
        _ : Unit <- history_neutral(context,movements)
        return MotionResult{snapshot,[]}
def stationary(+context:T.Context,+snapshot:T.Snapshot) -> Result<&2,&2,T.Error,MotionResult>:
  T.Snapshot{+record,T.Runtime{T.Physical{+g,+np,+s,+h,+v,+b,+m,+stuck},+base,+fluids,+pending,+movements,+support,+runtime_tail}}=snapshot
  stationary_effects(context,snapshot,Bool.not(np || U.removed(record)))
def support_or_legacy(support:S.State,+legacy:Travel.BlockPos) -> Travel.BlockPos:
  match support:
    case S.State{Some{+point},+n}: point
    case _: legacy
def ground_publication(+position:V.Vec3,+support:Travel.BlockPos,+cell:T.Cell) -> T.Publication:
  T.Cell{+state,+x,+y,+z,+w,+l,+h,+ch,+flow,+fluid,+full,+f,+s,+r,+suppresses,+inside,+step,+wb,+bubble,+fall,+cell_tail}=cell
  T.GroundEvent{position,support,state}
def ground_event(+context:T.Context,+position:V.Vec3,+support:S.State,+legacy:Travel.BlockPos,+fall:F.F64,+ground:Bool) -> Result<&2,&2,T.Error,List<&2,T.Publication>>:
  match ground:
    case False{}: Done{[]}
    case True{}:
      +point=support_or_legacy(support,legacy)
      do Result<&2,&2,T.Error,List<&2,T.Publication>>:
        +state : T.Cell <- cell(context,point)
        return [ground_publication(position,point,state)]
type FinishFrame is Data:
  FinishFrame{record:E.Record,history:List<&2,T.Movement>,physical:T.Physical,base:T.BaseState,fluids:T.Fluids,support:S.State,requested:V.Vec3,delta:V.Vec3,position:V.Vec3,velocity:V.Vec3,stuck:V.Vec3,ground:Bool,vc:Bool,below:Bool,xb:Bool,zb:Bool,fall:F.F64,legacy:T.Cell,under:T.Cell,current:T.Cell,no_gravity:Bool,suppress:Bool,events:List<&2,T.Publication>,tail:List<&2,FinishFrame>}
def finish_move(frame:FinishFrame) -> MotionResult:
  FinishFrame{+record,+history,+physical,+base,+fluids,+support,+requested,+delta,+position,+velocity,+stuck,+ground,+vc,+below,+xb,+zb,+fall,+legacy,+under,+current,+no_gravity,+suppress,+events,+tail}=frame
  T.Fluids{T.Fluid{+wh,+wf,+wn,+wp},+lava,+ew,+el,+fast}=fluids
  +gravity=U.select(F.F64,U.zero(),F.F64{1067743969,1202590843},no_gravity)
  +bounce=U.select(F.F64,bounciness(legacy,F.neg(M.Vec3.axis(U.mv(velocity),A.AxisY{})),gravity,suppress),U.zero(),below)
  +v=restitution(velocity,delta,gravity,bounce,vc,below,xb,zb)
  +speed=F.from_f32(speed_cell(current,under))
  next_fields=fields_motion(U.fields(record),position,air_drag(U.scale(v,speed,F.from_u32(1),speed),friction(under),ground),fall_after(fall,delta,F.is_gt(wh,U.zero()),ground),ground)
  MotionResult{T.Snapshot{U.set_fields(record,next_fields),T.Runtime{physics_flags(physical,False{},xb || zb,vc,below,stuck),base,fluids,[],history,support,[]}},List.append(&2,T.Publication,events,U.select(List<&2,T.Publication>,[T.Bounce{E.record_id(record)}],[],F.is_gt(bounce,U.zero())))}
def moved(+context:T.Context,+record:E.Record,+physical:T.Physical,+base:T.BaseState,+fluids:T.Fluids,+pending:List<&2,T.Movement>,movements:List<&2,T.Movement>,+support:S.State,+requested:V.Vec3,+velocity:V.Vec3,+stuck:V.Vec3) -> Result<&2,&2,T.Error,MotionResult>:
  T.Context{+items,+g,+cells,+coverage,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+budget,+clip,+context_tail}=context
  G.Context{+dimension,+geom_coverage,+blocks,+entities,+voxel_budget}=g
  T.Physical{+no_gravity,+no_physics,+suppress,+h,+v,+b,+minor,+old_stuck}=physical
  +delta=U.vv(M.collide_with_shapes(U.mv(requested),U.body(record),List.append(&2,A.Collider,boxes(blocks),entity_boxes(entities))))
  +advance=F.is_gt(U.length(delta),A.epsilon()) || F.is_lt(F.sub(U.length(requested),U.length(delta)),A.epsilon())
  +position=U.select(V.Vec3,U.add(U.pos(record),delta),U.pos(record),advance)
  +body=M.make_box(U.mv(position),0.25,0.25)
  +xb=Bool.not(M.equal_movement(M.Vec3.axis(U.mv(requested),A.AxisX{}),M.Vec3.axis(U.mv(delta),A.AxisX{})))
  +zb=Bool.not(M.equal_movement(M.Vec3.axis(U.mv(requested),A.AxisZ{}),M.Vec3.axis(U.mv(delta),A.AxisZ{})))
  +vc=F.is_ne(M.Vec3.axis(U.mv(requested),A.AxisY{}),M.Vec3.axis(U.mv(delta),A.AxisY{}))
  +below=vc && F.is_lt(M.Vec3.axis(U.mv(requested),A.AxisY{}),U.zero())
  +ground=below
  do Result<&2,&2,T.Error,MotionResult>:
    _ : Unit <- U.guard(G.contained(M.expand_towards(U.body(record),U.mv(requested)),geom_coverage),"item swept collision query outside actual geometry")
    +support : S.State <- support_update(g,position,body,support,ground,delta)
    +legacy : T.Cell <- cell(context,S.get_on_pos(U.mv(position),support,0.2))
    +under : T.Cell <- cell(context,S.get_on_pos(U.mv(position),support,0.999999))
    +current : T.Cell <- cell(context,S.block_position(U.mv(position)))
    _ : Unit <- U.guard(neutral_step(legacy),"item stepOn or fallOn callback unavailable")
    +fall : F.F64 <- clip_fall(fall_fields(U.fields(record)),delta,clip)
    +history : List<&2,T.Movement> = finished_history(record,pending,T.Movement{U.pos(record),position,requested},advance)
    _ : Unit <- history_neutral(context,history)
    +events : List<&2,T.Publication> <- ground_event(context,position,support,S.get_on_pos(U.mv(position),support,0.2),fall,ground && F.is_gt(fall_after(fall,delta,D.water_height(fluids),False{}),U.zero()))
    return finish_move(FinishFrame{record,history,physical,base,fluids,support,requested,delta,position,velocity,stuck,ground,vc,below,xb,zb,fall,legacy,under,current,no_gravity,suppress,events,[]})
def free_move(+record:E.Record,+physical:T.Physical,+base:T.BaseState,+fluids:T.Fluids,+pending:List<&2,T.Movement>,movements:List<&2,T.Movement>,+support:S.State,+under:T.Cell) -> MotionResult:
  T.Physical{+g,+np,+s,+h,+v,+b,+minor,+stuck}=physical
  +position=U.add(U.pos(record),U.velocity(record))
  +moved=U.set_position(record,position)
  +history=history_finish(pending,old_position(U.fields(record)),position,List.is_empty(&2,T.Movement,pending))
  MotionResult{T.Snapshot{U.set_velocity(moved,air_drag(U.velocity(record),friction(under),U.ground(record))),T.Runtime{physics_flags(physical,True{},False{},False{},False{},stuck),base,fluids,[],history,support,[]}},[]}
def free_runtime(+context:T.Context,+record:E.Record,+runtime:T.Runtime) -> Result<&2,&2,T.Error,MotionResult>:
  T.Runtime{+physical,+base,+fluids,+pending,+movements,+support,+runtime_tail}=runtime
  do Result<&2,&2,T.Error,MotionResult>:
    +under : T.Cell <- cell(context,S.get_on_pos(U.mv(U.add(U.pos(record),U.velocity(record))),support,0.999999))
    return free_move(record,physical,base,fluids,pending,movements,support,under)
def multiply(+v:V.Vec3,+s:V.Vec3) -> V.Vec3:
  V.Vec3{+x,+y,+z}=s
  U.scale(v,x,y,z)
def physical_move(+context:T.Context,+record:E.Record,+runtime:T.Runtime) -> Result<&2,&2,T.Error,MotionResult>:
  T.Runtime{+physical,+base,+fluids,+pending,+movements,+support,+runtime_tail}=runtime
  T.Physical{+g,+np,+s,+h,+v,+b,+m,+stuck}=physical
  +applied=F.is_gt(U.length(stuck),A.epsilon())
  +request=U.select(V.Vec3,multiply(U.velocity(record),stuck),U.velocity(record),applied)
  moved(context,record,physical,base,fluids,pending,movements,support,request,U.select(V.Vec3,U.vec(),U.velocity(record),applied),U.select(V.Vec3,U.vec(),stuck,applied))
def move_gate(+context:T.Context,+record:E.Record,+runtime:T.Runtime,+free:Bool) -> Result<&2,&2,T.Error,MotionResult>:
  match free:
    case True{}: free_runtime(context,record,runtime)
    case False{}: physical_move(context,record,runtime)
