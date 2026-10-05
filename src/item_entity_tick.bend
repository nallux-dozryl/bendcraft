import Base
import ./item_entity_tick_model.bend as T
import ./item_entity_tick_fields.bend as U
import ./item_entity_tick_fluid.bend as D
import ./item_entity_tick_motion.bend as M
import ./item_entity_tick_splash.bend as Splash
import ./item_entity_tick_merge.bend as Merge
import ./item_entity_tick_properties.bend as P
import ./cooking_effect_entities_model.bend as E
import ./entity_common_tick.bend as Common
import ./vanilla_entity_fields.bend as V
import ./f64.bend as F
import ./random.bend as R
import ./geometry.bend as A
import ./cooking_effect_geometry.bend as G
import ./support.bend as S
import ./movement.bend as MV
import ./inventory.bend as I
import ./campfire_authority_items.bend as CI

def common_fields(f:V.Fields) -> V.Fields:
  V.Fields{+p,+v,+o,+old,+l,+h,+b,+fall,+ground,+air,+fire,+portal,+i,+sync}=f
  V.Fields{p,v,p,p,Common.copied_look(l),h,b,fall,ground,air,fire,portal,i,sync}
def common_base(+base:T.BaseState) -> T.BaseState:
  T.BaseState{+inv,+b,+w,+e,+p,+wp,+s,+sw,+f,+silent,+last,+speed}=base
  T.BaseState{Common.decrement(inv),b,w,e,p,wp,s,sw,f,silent,last,speed}
def common_record(+c:E.Common) -> E.Common:
  E.Common{+d,+id,+a,+b,+r,+f,+t,+first,+removed,+accessible,+order}=c
  E.Common{d,id,a,b,r,common_fields(f),U32.inc(t),first,removed,accessible,order}
# Scheduler phase is separate; ItemEntity.tick itself calls baseTick only.
def common_tick(+snapshot:T.Snapshot) -> T.Snapshot:
  T.Snapshot{+r,T.Runtime{+p,+b,+f,+pending,+m,+s,+runtime_tail}}=snapshot
  T.Snapshot{U.with_common(r,common_record(E.common(r))),T.Runtime{p,common_base(b),f,pending,m,s,runtime_tail}}
def previous(last:Maybe<&2,V.Vec3>,+fallback:V.Vec3) -> V.Vec3:
  match last:
    case None{}: fallback
    case Some{+p}: p
def base_started(+base:T.BaseState,+point:V.Vec3,+eye:Bool) -> T.BaseState:
  T.BaseState{+inv,+boarding,+w,+e,+p,+wp,+s,+sw,+f,+silent,+last,+speed}=base
  T.BaseState{inv,U.decrement(boarding),w,eye,False{},p,s,sw,f,silent,Some{point},U.sub(point,previous(last,point))}
def base_prepare(+snapshot:T.Snapshot) -> T.Snapshot:
  T.Snapshot{+record,T.Runtime{+p,+b,+fluids,+pending,+m,+s,+runtime_tail}}=snapshot
  T.Fluids{+w,+l,+eye,+e,+fast}=fluids
  T.Snapshot{record,T.Runtime{p,base_started(b,U.pos(record),eye),fluids,pending,m,s,runtime_tail}}
def needs_splash(+base:T.BaseState,+common:E.Common,+in_water:Bool) -> Bool:
  T.BaseState{+a,+b,+water,+e,+p,+wp,+s,+sw,+f,+silent,+last,+speed}=base
  E.Common{+d,+id,+a,+b,+r,+fields,+t,+first,+removed,+accessible,+order}=common
  in_water && Bool.not(water) && Bool.not(first)
def fluid_base(+base:T.BaseState,+water:Bool) -> T.BaseState:
  T.BaseState{+a,+b,+old,+e,+p,+wp,+s,+sw,+f,+silent,+last,+speed}=base
  T.BaseState{a,b,water,e,p,wp,s,False{},f,silent,last,speed}
def water_fall(fields:V.Fields,+water:Bool) -> V.Fields:
  V.Fields{+p,+v,+o,+old,+l,+h,+b,+fall,+g,+a,+fire,+portal,+i,+s}=fields
  V.Fields{p,v,o,old,l,h,b,U.select(F.F64,U.zero(),fall,water),g,a,fire,portal,i,s}
def silence(events:List<&2,T.Publication>,+silent:Bool) -> List<&2,T.Publication>:
  match events:
    case Nil{}: []
    case T.Splash{+p,+v,+pitch,+high} <> +rest: List.append(&2,T.Publication,U.select(List<&2,T.Publication>,[],[T.Splash{p,v,pitch,high}],silent),silence(rest,silent))
    case +event <> +rest: event <> silence(rest,silent)
def silent(runtime:T.Runtime) -> Bool:
  T.Runtime{+p,T.BaseState{+a,+b,+w,+e,+p,+wp,+s,+sw,+f,+silent,+last,+speed},+fluids,+pending,+moves,+support,+runtime_tail}=runtime
  silent
def splash_record(+record:E.Record,result:Splash.SplashResult,+runtime:T.Runtime) -> M.MotionResult:
  Splash.SplashResult{+source,+events}=result
  M.MotionResult{T.Snapshot{M.record_random(record,source),runtime},silence(events,silent(runtime))}
def splash_if(+record:E.Record,+runtime:T.Runtime,+needed:Bool) -> M.MotionResult:
  match needed:
    case False{}: M.MotionResult{T.Snapshot{record,runtime},[]}
    case True{}: splash_record(record,Splash.run(U.pos(record),U.velocity(record),M.random(E.common(record))),runtime)
def fluid_push(result:M.MotionResult,water:T.Fluid,lava:T.Fluid,+fast:Bool) -> M.MotionResult:
  M.MotionResult{T.Snapshot{+record,+runtime},+events}=result
  M.MotionResult{T.Snapshot{U.set_velocity(record,D.current(D.current(U.velocity(record),water,F.F64{1066183688,824633721}),lava,U.select(F.F64,F.F64{1065135112,824633721},F.F64{1063460186,3413067345},fast))),runtime},events}
def fluid_effect(+snapshot:T.Snapshot,frame:D.FluidFrame,+fast:Bool) -> M.MotionResult:
  T.Snapshot{+record,T.Runtime{+p,+b,+f,+pending,+m,+s,+runtime_tail}}=snapshot
  D.FluidFrame{+water,+lava,+ew,+el,+any}=frame
  T.Fluid{+height,+flow,+count,+present}=water
  +wet=F.is_gt(height,U.zero())
  +fields=water_fall(U.fields(record),wet)
  result=splash_if(U.set_fields(record,fields),T.Runtime{p,fluid_base(b,wet),T.Fluids{water,lava,ew,el,fast},pending,m,s,runtime_tail},needs_splash(b,E.common(record),wet))
  fluid_push(result,water,lava,fast)
def observe_fluid(+context:T.Context,+snapshot:T.Snapshot) -> Result<&2,&2,T.Error,M.MotionResult>:
  T.Context{+items,+g,+cells,+coverage,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+budget,+clip,+context_tail}=context
  T.Snapshot{+record,+runtime}=snapshot
  do Result<&2,&2,T.Error,M.MotionResult>:
    +frame : D.FluidFrame <- D.observe(context,record)
    return fluid_effect(snapshot,frame,fast)
def lifecycle_fields(fields:V.Fields,+lava:Bool,+server:Bool) -> V.Fields:
  V.Fields{+p,+v,+o,+old,+l,+h,+b,+fall,+g,+a,+fire,+portal,+i,+s}=fields
  V.Fields{p,v,o,old,l,h,b,U.select(F.F64,F.mul(fall,F.from_f32(0.5)),fall,lava),g,a,U.select(U32,fire,Merge.signed_min(0,fire),server),U.select(U32,U.decrement(portal),portal,server),i,s}
def first_done(+common:E.Common) -> E.Common:
  E.Common{+d,+id,+a,+b,+r,+f,+t,+first,+removed,+accessible,+order}=common
  E.Common{d,id,a,b,r,f,t,False{},removed,accessible,order}
def fire_neutral(fields:V.Fields,+server:Bool) -> Result<&2,&2,T.Error,Unit>:
  V.Fields{+p,+v,+o,+old,+l,+h,+b,+fall,+g,+a,+fire,+portal,+i,+s}=fields
  U.guard(Bool.not(server && U.positive(fire)),"item active fire damage/resistance receiver unavailable")
def point_y(+point:V.Vec3) -> F.F64:
  V.Vec3{+x,+y,+z}=point
  y
def lifecycle_finish(+record:E.Record,+runtime:T.Runtime,+lava:Bool,+server:Bool,+min_y:U32) -> T.Snapshot:
  +r=U.set_fields(record,lifecycle_fields(U.fields(record),lava,server))
  +c=first_done(E.common(r))
  +updated=U.with_common(r,c)
  T.Snapshot{U.select(E.Record,U.discard(updated),updated,F.is_lt(point_y(U.pos(record)),F.from_i32(U32.sub(min_y,64)))),runtime}
def lifecycle(+context:T.Context,+snapshot:T.Snapshot) -> Result<&2,&2,T.Error,T.Snapshot>:
  T.Context{+items,+g,+cells,+coverage,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+budget,+clip,+context_tail}=context
  T.Snapshot{+record,T.Runtime{+p,+base,+fluids,+pending,+m,+s,+runtime_tail}}=snapshot
  T.BaseState{+a,+b,+w,+e,+powder,+wp,+sprint,+sw,+freeze,+silent,+last,+speed}=base
  T.Fluids{+water,T.Fluid{+lava,+lflow,+ln,+lp},+ew,+el,+fast}=fluids
  do Result<&2,&2,T.Error,T.Snapshot>:
    _ : Unit <- U.guard(portal && mount && Bool.not(sprint) && Bool.not(freeze),"item portal, mount, sprint or freezing service unavailable")
    _ : Unit <- fire_neutral(U.fields(record),server)
    return lifecycle_finish(record,T.Runtime{p,base,fluids,pending,m,s,runtime_tail},F.is_gt(lava,U.zero()),server,min)
def item_start_fields(fields:V.Fields) -> V.Fields:
  V.Fields{+p,+v,+o,+old,+l,+h,+b,+fall,+g,+a,+fire,+portal,+i,+s}=fields
  V.Fields{p,v,p,old,l,h,b,fall,g,a,fire,portal,i,s}
def item_start_common(+common:E.Common) -> E.Common:
  E.Common{+d,+id,+a,+b,+r,+f,+t,+first,+removed,+accessible,+order}=common
  E.Common{d,id,a,b,r,item_start_fields(f),t,first,removed,accessible,order}
def item_start(+record:E.Record) -> E.Record:
  match record:
    case E.Item{+c,+item,+age,+delay,+h,+t,+target,+b}: E.Item{item_start_common(c),item,age,U.select(U32,U.decrement(delay),delay,U32.is_ne(delay,32767)),h,t,target,b}
    case +r: r
def residue(+value:U32,+modulus:U32) -> Bool:
  U32.is_zero(U32.mod(U.select(U32,U32.sub(0,value),value,U32.is_ge(value,2147483648)),modulus))
def should_move(+record:E.Record) -> Bool:
  Bool.not(U.ground(record)) || F.is_gt(MV.Vec3.horizontal_squared(U.mv(U.velocity(record))),F.from_f32(0.00001)) || residue(U32.add(U.tick_count(record),E.record_id(record)),4)
def motion_move(+context:T.Context,+snapshot:T.Snapshot) -> Result<&2,&2,T.Error,M.MotionResult>:
  T.Snapshot{+record,+runtime}=snapshot
  T.Runtime{T.Physical{+g,+np,+s,+h,+v,+b,+m,+stuck},+base,+f,+pending,+moves,+support,+runtime_tail}=runtime
  M.move_gate(context,record,runtime,np)
def history(runtime:T.Runtime) -> List<&2,T.Movement>:
  T.Runtime{+p,+b,+f,+pending,+moves,+s,+runtime_tail}=runtime
  moves
def motion_last(+context:T.Context,+snapshot:T.Snapshot) -> Result<&2,&2,T.Error,M.MotionResult>:
  M.stationary(context,snapshot)
type MotionFrame is Data:
  MotionFrame{context:T.Context,snapshot:T.Snapshot,tail:List<&2,MotionFrame>}
def motion_frame_move(frame:MotionFrame) -> Result<&2,&2,T.Error,M.MotionResult>:
  MotionFrame{+context,+snapshot,+tail}=frame
  motion_move(context,snapshot)
def motion_frame_last(frame:MotionFrame) -> Result<&2,&2,T.Error,M.MotionResult>:
  MotionFrame{+context,+snapshot,+tail}=frame
  motion_last(context,snapshot)
def motion_gate(+frame:MotionFrame,move:Bool) -> Result<&2,&2,T.Error,M.MotionResult>:
  match move:
    case True{}: motion_frame_move(frame)
    case False{}: motion_frame_last(frame)
def moving_record(snapshot:T.Snapshot) -> E.Record:
  T.Snapshot{+record,+runtime}=snapshot
  record
def motion_framed(+frame:MotionFrame) -> Result<&2,&2,T.Error,M.MotionResult>:
  MotionFrame{+context,+snapshot,+tail}=frame
  motion_gate(frame,should_move(moving_record(snapshot)))
def move_snapshot(+context:T.Context,+snapshot:T.Snapshot) -> Result<&2,&2,T.Error,M.MotionResult>:
  motion_framed(MotionFrame{context,snapshot,[]})
def idle_fire(fields:V.Fields) -> V.Fields:
  V.Fields{+p,+v,+o,+old,+l,+h,+b,+fall,+g,+a,+fire,+portal,+i,+s}=fields
  V.Fields{p,v,o,old,l,h,b,fall,g,a,0,portal,i,s}
def after_blocks(+snapshot:T.Snapshot,+server:Bool) -> T.Snapshot:
  T.Snapshot{+record,+runtime}=snapshot
  T.Runtime{T.Physical{+g,+np,+s,+h,+v,+b,+m,+stuck},+base,+f,+pending,+moves,+support,+runtime_tail}=runtime
  T.Snapshot{U.select(E.Record,record,U.set_fields(record,idle_fire(U.fields(record))),np || U.removed(record) || Bool.not(server)),runtime}
def merge_due(+first:V.Vec3,+second:V.Vec3,+count:U32) -> Bool:
  V.Vec3{+x,+y,+z}=first
  V.Vec3{+a,+b,+c}=second
  residue(count,U.select(U32,2,40,U32.is_ne(V.floor_word(x),V.floor_word(a)) || U32.is_ne(V.floor_word(y),V.floor_word(b)) || U32.is_ne(V.floor_word(z),V.floor_word(c))))
def age_next(+age:U32) -> U32:
  U.select(U32,age,U32.inc(age),U32.is_eq(age,4294934528))
def age_record(+record:E.Record) -> E.Record:
  match record:
    case E.Item{+c,+item,+age,+d,+h,+t,+target,+b}: E.Item{c,item,age_next(age),d,h,t,target,b}
    case +r: r
def age(+record:E.Record) -> U32:
  match record:
    case E.Item{+c,+i,+a,+d,+h,+t,+target,+b}: a
    case E.Orb{+c,+v,+a,+h,+n,+f}: a
def sync_fields(fields:V.Fields,+value:Bool) -> V.Fields:
  V.Fields{+p,+v,+o,+old,+l,+h,+b,+fall,+g,+a,+fire,+portal,+i,+s}=fields
  V.Fields{p,v,o,old,l,h,b,fall,g,a,fire,portal,i,s || value}
def after_fluid(+record:E.Record,+old_velocity:V.Vec3,+server:Bool,+any:Bool) -> E.Record:
  +next=U.set_fields(record,sync_fields(U.fields(record),any || (server && F.is_gt(U.length(U.sub(U.velocity(record),old_velocity)),F.F64{1065646817,1202590843}))))
  U.select(E.Record,U.discard(next),next,server && Bool.not(U.signed_lt(age(record),6000)))
def has_removal(events:List<&2,T.Publication>,+id:U32) -> Bool:
  match events:
    case Nil{}: False{}
    case T.Removed{+key} <> +rest: U32.is_eq(key,id) || has_removal(rest,id)
    case +head <> +rest: has_removal(rest,id)
def fields_sync(fields:V.Fields) -> Bool:
  V.Fields{+p,+v,+o,+old,+l,+h,+b,+fall,+g,+a,+fire,+portal,+i,+sync}=fields
  sync
def sync_flag(record:E.Record) -> Bool: fields_sync(U.fields(record))
def final_publications(+events:List<&2,T.Publication>,+before:E.Record,+after:E.Record) -> List<&2,T.Publication>:
  List.append(&2,T.Publication,events,List.append(&2,T.Publication,
    U.select(List<&2,T.Publication>,[T.Synced{E.record_id(after)}],[],sync_flag(after) && Bool.not(sync_flag(before))),
    U.select(List<&2,T.Publication>,[T.Removed{E.record_id(after)}],[],U.removed(after) && Bool.not(has_removal(events,E.record_id(after))))))
def finished_fluid(records:List<&2,E.Record>,events:List<&2,T.Publication>,+old:V.Vec3,+server:Bool,result:M.MotionResult,frame:D.FluidFrame) -> Result<&2,&2,T.Error,T.Plan>:
  M.MotionResult{T.Snapshot{+record,+runtime},+extra}=result
  D.FluidFrame{+w,+l,+e,+el,+any}=frame
  +next=after_fluid(record,old,server,any)
  Done{T.Plan{T.Snapshot{next,runtime},Merge.replace(records,next),final_publications(List.append(&2,T.Publication,events,extra),record,next)}}
def finish(+context:T.Context,+snapshot:T.Snapshot,records:List<&2,E.Record>,events:List<&2,T.Publication>,+old:V.Vec3) -> Result<&2,&2,T.Error,T.Plan>:
  T.Context{+items,+g,+cells,+coverage,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+budget,+clip,+context_tail}=context
  T.Snapshot{+record,+runtime}=snapshot
  do Result<&2,&2,T.Error,T.Plan>:
    +frame : D.FluidFrame <- D.observe(context,record)
    finished_fluid(records,events,old,server,fluid_effect(snapshot,frame,fast),frame)
def merged(+context:T.Context,+runtime:T.Runtime,events:List<&2,T.Publication>,+old:V.Vec3,neighbours:Merge.Neighbours) -> Result<&2,&2,T.Error,T.Plan>:
  Merge.Neighbours{+record,+records,+extra}=neighbours
  finish(context,T.Snapshot{age_record(record),runtime},records,List.append(&2,T.Publication,events,extra),old)
def skip_merge(+context:T.Context,+snapshot:T.Snapshot,records:List<&2,E.Record>,events:List<&2,T.Publication>,+old:V.Vec3) -> Result<&2,&2,T.Error,T.Plan>:
  T.Snapshot{+record,+runtime}=snapshot
  merged(context,runtime,events,old,Merge.Neighbours{record,records,[]})
def query_merge(+context:T.Context,+snapshot:T.Snapshot,records:List<&2,E.Record>,events:List<&2,T.Publication>,+old:V.Vec3) -> Result<&2,&2,T.Error,T.Plan>:
  T.Context{+items,+g,+cells,+coverage,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+budget,+clip,+context_tail}=context
  T.Snapshot{+record,+runtime}=snapshot
  do Result<&2,&2,T.Error,T.Plan>:
    _ : Unit <- U.guard(complete,"item neighbour query is unavailable or incomplete")
    +neighbours : Merge.Neighbours <- Merge.neighbours(items,budget,record,records)
    merged(context,runtime,events,old,neighbours)
def do_merge_gate(+context:T.Context,+snapshot:T.Snapshot,records:List<&2,E.Record>,events:List<&2,T.Publication>,+old:V.Vec3,eligible:Bool) -> Result<&2,&2,T.Error,T.Plan>:
  match eligible:
    case False{}: skip_merge(context,snapshot,records,events,old)
    case True{}: query_merge(context,snapshot,records,events,old)
def do_merge(+context:T.Context,+snapshot:T.Snapshot,records:List<&2,E.Record>,events:List<&2,T.Publication>,+old:V.Vec3) -> Result<&2,&2,T.Error,T.Plan>:
  T.Context{+items,+g,+cells,+coverage,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+budget,+clip,+context_tail}=context
  T.Snapshot{+record,+runtime}=snapshot
  do Result<&2,&2,T.Error,T.Plan>:
    +meta : I.ItemMetadata <- Merge.metadata_for(items,record)
    do_merge_gate(context,snapshot,records,events,old,Merge.eligible(meta,record))
def merge_phase(+context:T.Context,+snapshot:T.Snapshot,records:List<&2,E.Record>,events:List<&2,T.Publication>,+old:V.Vec3,+due:Bool) -> Result<&2,&2,T.Error,T.Plan>:
  match due:
    case False{}: skip_merge(context,snapshot,records,events,old)
    case True{}: do_merge(context,snapshot,records,events,old)
def section_axis(+value:F.F64,+mask:U32) -> U32:
  U32.and(U32.shrn(V.floor_word(value),4n),mask)
# Actual SectionPos.asLong masks section X/Z to 22 bits and Y to 20 bits.
# Logical shift has the same masked result as Java's signed block >> 4.
def same_section(first:V.Vec3,second:V.Vec3) -> Bool:
  V.Vec3{+x,+y,+z}=first
  V.Vec3{+a,+b,+c}=second
  U32.is_eq(section_axis(x,4194303),section_axis(a,4194303)) && U32.is_eq(section_axis(y,1048575),section_axis(b,1048575)) && U32.is_eq(section_axis(z,4194303),section_axis(c,4194303))
def section_merge(+context:T.Context,records:List<&2,E.Record>,events:List<&2,T.Publication>,+old_position:V.Vec3,+old_velocity:V.Vec3,+snapshot:T.Snapshot) -> Result<&2,&2,T.Error,T.Plan>:
  T.Context{+items,+g,+cells,+coverage,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+budget,+clip,+context_tail}=context
  T.Snapshot{+record,+runtime}=snapshot
  merge_phase(context,snapshot,records,events,old_velocity,server && merge_due(old_position,U.pos(record),U.tick_count(record)))
def section_refused() -> Result<&2,&2,T.Error,T.Plan>:
  Fail{T.Refused{"item entity-section migration/visibility callback authority unavailable"}}
def section_ready(+context:T.Context,records:List<&2,E.Record>,events:List<&2,T.Publication>,+old_position:V.Vec3,+old_velocity:V.Vec3,+snapshot:T.Snapshot,+same:Bool) -> Result<&2,&2,T.Error,T.Plan>:
  match same:
    case False{}: section_refused()
    case True{}: section_merge(context,records,events,old_position,old_velocity,snapshot)
def moved_ready(+context:T.Context,records:List<&2,E.Record>,events:List<&2,T.Publication>,+old_position:V.Vec3,+old_velocity:V.Vec3,+snapshot:T.Snapshot) -> Result<&2,&2,T.Error,T.Plan>:
  T.Snapshot{+record,+runtime}=snapshot
  section_ready(context,records,events,old_position,old_velocity,snapshot,same_section(old_position,U.pos(record)))
def after_move(+context:T.Context,records:List<&2,E.Record>,prior:List<&2,T.Publication>,+old_position:V.Vec3,+old_velocity:V.Vec3,result:M.MotionResult) -> Result<&2,&2,T.Error,T.Plan>:
  T.Context{+items,+g,+cells,+coverage,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+budget,+clip,+context_tail}=context
  M.MotionResult{+snapshot,+events}=result
  moved_ready(context,records,List.append(&2,T.Publication,prior,events),old_position,old_velocity,after_blocks(snapshot,server))
def after_base(+context:T.Context,records:List<&2,E.Record>,events:List<&2,T.Publication>,+snapshot:T.Snapshot) -> Result<&2,&2,T.Error,T.Plan>:
  T.Snapshot{+record,+runtime}=snapshot
  +started=item_start(record)
  do Result<&2,&2,T.Error,T.Plan>:
    +escaped : T.Snapshot <- M.collision(context,T.Snapshot{M.buoyancy(started,runtime),runtime})
    +result : M.MotionResult <- move_snapshot(context,escaped)
    after_move(context,records,events,U.pos(started),U.velocity(started),result)
def base_phase(+context:T.Context,records:List<&2,E.Record>,result:M.MotionResult) -> Result<&2,&2,T.Error,T.Plan>:
  M.MotionResult{+snapshot,+events}=result
  do Result<&2,&2,T.Error,T.Plan>:
    +snapshot : T.Snapshot <- lifecycle(context,snapshot)
    after_base(context,records,events,snapshot)
def items(context:T.Context) -> CI.Context:
  T.Context{+items,+g,+cells,+coverage,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+budget,+clip,+context_tail}=context
  items
def record(snapshot:T.Snapshot) -> E.Record:
  T.Snapshot{+record,+runtime}=snapshot
  record
def common_dimension(common:E.Common) -> String:
  E.Common{+d,+id,+a,+b,+r,+f,+t,+first,+removed,+accessible,+order}=common
  d
def dimension(context:T.Context,snapshot:T.Snapshot) -> Bool:
  T.Context{+items,G.Context{+d,+c,+b,+e,+v},+cells,+coverage,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+budget,+clip,+context_tail}=context
  T.Snapshot{+record,+runtime}=snapshot
  String.eq(d,common_dimension(E.common(record)))
def canonical_cells(cells:List<&2,T.Cell>) -> Bool:
  match cells:
    case Nil{}: True{}
    case T.Cell{+state,+x,+y,+z,+w,+l,+h,+ch,+flow,+fluid,+full,+f,+s,+r,+suppress,+inside,+step,+wb,+bubble,+fall,+tail} <> +rest:
      List.is_empty(&2,T.Cell,tail) && canonical_cells(rest)
def server_authority(context:T.Context) -> Bool:
  T.Context{+items,+g,+cells,+coverage,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+budget,+clip,+context_tail}=context
  server
def canonical_context(context:T.Context) -> Bool:
  T.Context{+items,+g,+cells,+coverage,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+budget,+clip,+context_tail}=context
  List.is_empty(&2,T.Context,context_tail) && canonical_cells(cells)
def canonical_runtime(snapshot:T.Snapshot) -> Bool:
  T.Snapshot{+record,T.Runtime{+p,+b,+f,+pending,+moves,+s,+runtime_tail}}=snapshot
  List.is_empty(&2,T.Runtime,runtime_tail)
def live_plan(+context:T.Context,+snapshot:T.Snapshot,records:List<&2,E.Record>) -> Result<&2,&2,T.Error,T.Plan>:
  do Result<&2,&2,T.Error,T.Plan>:
    _ : Unit <- U.guard(canonical_context(context) && canonical_runtime(snapshot),"item tick context/runtime frame must be canonical")
    _ : Unit <- U.guard(dimension(context,snapshot),"item tick geometry dimension differs from entity")
    _ : Unit <- U.guard(server_authority(context),"item client authority/network movement receiver unavailable")
    _ : I.ItemMetadata <- Merge.metadata_for(items(context),record(snapshot))
    +first : M.MotionResult <- observe_fluid(context,base_prepare(snapshot))
    base_phase(context,records,first)
def discarded(+snapshot:T.Snapshot,records:List<&2,E.Record>) -> Result<&2,&2,T.Error,T.Plan>:
  T.Snapshot{+record,+runtime}=snapshot
  +removed=U.discard(record)
  Done{T.Plan{T.Snapshot{removed,runtime},Merge.replace(records,removed),[T.Removed{E.record_id(record)}]}}
def empty_plan(+snapshot:T.Snapshot,records:List<&2,E.Record>,+empty:Bool,+context:T.Context) -> Result<&2,&2,T.Error,T.Plan>:
  match empty:
    case False{}: live_plan(context,snapshot,records)
    case True{}: discarded(snapshot,records)
def item_plan(+context:T.Context,+snapshot:T.Snapshot,records:List<&2,E.Record>) -> Result<&2,&2,T.Error,T.Plan>:
  T.Snapshot{+record,+runtime}=snapshot
  empty_plan(snapshot,records,U.empty(U.slot(record)),context)
type PlanFrame is Data:
  PlanFrame{context:T.Context,snapshot:T.Snapshot,records:List<&2,E.Record>,tail:List<&2,PlanFrame>}
def is_item(record:E.Record) -> Bool:
  match record:
    case E.Item{+c,+i,+a,+d,+h,+t,+target,+b}: True{}
    case _: False{}
def plan_item(frame:PlanFrame) -> Result<&2,&2,T.Error,T.Plan>:
  PlanFrame{+context,+snapshot,+records,+tail}=frame
  item_plan(context,snapshot,records)
def plan_kind(+frame:PlanFrame,item:Bool) -> Result<&2,&2,T.Error,T.Plan>:
  match item:
    case False{}: Fail{T.Refused{"ItemEntity tick cannot tick an experience orb"}}
    case True{}: plan_item(frame)
def plan_framed(+frame:PlanFrame) -> Result<&2,&2,T.Error,T.Plan>:
  PlanFrame{+context,+snapshot,+records,+tail}=frame
  plan_kind(frame,is_item(record(snapshot)))
def plan(+context:T.Context,+snapshot:T.Snapshot,records:List<&2,E.Record>) -> Result<&2,&2,T.Error,T.Plan>:
  plan_framed(PlanFrame{context,snapshot,records,[]})
def committed(owner:T.Owner,result:Result<&2,&2,T.Error,T.Plan>) -> T.Owner & Result<&2,&2,T.Error,List<&2,T.Publication>>:
  match result:
    case Fail{+e}: (owner,Fail{e})
    case Done{T.Plan{T.Snapshot{+record,+runtime},+records,+events}}: (T.Owner{E.Entity{record},runtime},Done{events})
def single_context(context:T.Context) -> T.Context:
  T.Context{+items,+g,+cells,+coverage,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+budget,+clip,+context_tail}=context
  T.Context{items,g,cells,coverage,min,server,fast,loaded,False{},rain,portal,mount,budget,clip,context_tail}
# The sole owner is returned unchanged on every refused observation.
def tick(+context:T.Context,owner:T.Owner) -> T.Owner & Result<&2,&2,T.Error,List<&2,T.Publication>>:
  T.Owner{E.Entity{+record},+runtime}=owner
  committed(T.Owner{E.Entity{record},runtime},plan(single_context(context),T.Snapshot{record,runtime},[record]))
