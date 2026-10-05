import Base
import ./f64.bend as F
import ./locomotion.bend as L
import ./vanilla_entity_fields.bend as V
import ./cooking_effect_entities_model.bend as E
import ./inventory.bend as I
import ./mesh_render.bend as M
import ./block_bake.bend as K
import ./item_entity_render_model.bend as D
import ./item_entity_render_transform.bend as T

# JOML's default cosFromSin float arithmetic. Native sin is a named numerical
# boundary; Mth bob/color sin uses the already hash-verified authoritative table.
def cosine_sign(cosine:F32,reduced:F32,negative:Bool) -> F32:
  match negative:
    case False{}: cosine
    case True{}: F32.neg(cosine)
def cosine_reduce(cosine:F32,+reduced:F32,below:Bool) -> F32:
  match below:
    case False{}: cosine_sign(cosine,reduced,F32.is_ge(reduced,3.1415927))
    case True{}: cosine_sign(cosine,F32.add(6.2831855,reduced),F32.is_ge(F32.add(6.2831855,reduced),3.1415927))
def int_word(value:F.Word64) -> U32:
  F.Word64{hi,lo} = value
  lo
def cosine(+sine:F32,+half:F32) -> F32:
  +a = F32.add(half,1.5707964)
  +reduced = F32.sub(a,F32.mul(T.signed(int_word(F.to_java_long(F.from_f32(F32.div(a,6.2831855))))),6.2831855))
  cosine_reduce(F32.sqrt(F32.sub(1.0,F32.mul(sine,sine))),reduced,F32.is_lt(reduced,0.0))
def spin_matrix(+angle:F32) -> K.Mat:
  +half = F32.div(angle,2.0)
  +sine = F32.sin(half)
  K.quaternion(F32.mul(0.0,sine),sine,F32.mul(0.0,sine),cosine(sine,half))
def item_origin(position:M.Vec3,hover:F32) -> M.Vec3:
  M.Vec3{x,y,z} = position
  M.Vec3{x,F32.add(y,hover),z}
def item_draw(+id:U32,+key:I.ItemKey,+age:F32,+position:M.Vec3,+hover:F32,+spin:F32,
    +ground:D.Ground,+light:D.Light,+count:U32) -> D.Draw:
  D.Ground{original,seed,+quads,M.Vec3{lx,ly,lz},M.Vec3{hx,hy,hz},block_light} = ground
  D.Light{lid,b,s,rgb,orb} = light
  +offsets = T.offsets(seed,T.copies(count),F32.sub(hz,lz))
  +origin = item_origin(position,hover)
  D.ItemDraw{id,key,age,position,hover,spin,offsets,D.packed(b,s),block_light,T.clustered(offsets,quads,spin_matrix(spin),origin,rgb)}
def ground_min_y(ground:D.Ground) -> F32:
  D.Ground{k,seed,quads,M.Vec3{lx,ly,lz},high,block} = ground
  ly
def item_sine(id:U32,key:I.ItemKey,+age:F32,position:M.Vec3,+bob:F32,+ground:D.Ground,light:D.Light,count:U32,
    pair:L.Tables & F32) -> L.Tables & Result<&2,&2,D.Error,Maybe<&2,D.Draw>>:
  (tables,sine) = pair
  (tables,Done{Some{item_draw(id,key,age,position,T.hover(ground_min_y(ground),sine),T.spin(age,bob),ground,light,count)}})
def item_ready(value:Result<&2,&2,D.Error,D.ItemInput>,tables:L.Tables,id:U32,key:I.ItemKey,+age:F32,position:M.Vec3,+bob:F32,count:U32) -> L.Tables & Result<&2,&2,D.Error,Maybe<&2,D.Draw>>:
  match value:
    case Fail{error}: (tables,Fail{error})
    case Done{D.ItemInput{ground,light}}: item_sine(id,key,age,position,bob,ground,light,count,L.sin(tables,F.from_f32(F32.add(F32.div(age,10.0),bob))))
def item_data(+catalog:D.Catalog,+lights:List<&2,D.Light>,key:I.ItemKey,id:U32) -> Result<&2,&2,D.Error,D.ItemInput>:
  D.Catalog{items,textures,orb} = catalog
  do Result<&2,&2,D.Error,D.ItemInput>:
    ground : D.Ground <- D.required_ground(D.ground(items,key))
    light : D.Light <- D.required_light(D.light(lights,id))
    return D.ItemInput{ground,light}
def stack_visible(key:I.ItemKey,+count:U32) -> Bool:
  I.ItemKey{id,components} = key
  U32.is_gt(count,0) && U32.is_lt(count,2147483648) && Bool.not(String.eq(id,"minecraft:air"))
def item_chosen(show:Bool,+key:I.ItemKey,count:U32,tables:L.Tables,+id:U32,age:F32,position:M.Vec3,bob:F32,catalog:D.Catalog,lights:List<&2,D.Light>) -> L.Tables & Result<&2,&2,D.Error,Maybe<&2,D.Draw>>:
  match show:
    case False{}: (tables,Done{None{}})
    case True{}: item_ready(item_data(catalog,lights,key,id),tables,id,key,age,position,bob,count)
def item(slot:I.Slot,tables:L.Tables,id:U32,age:F32,position:M.Vec3,bob:F32,catalog:D.Catalog,lights:List<&2,D.Light>) -> L.Tables & Result<&2,&2,D.Error,Maybe<&2,D.Draw>>:
  match slot:
    case I.InvEmpty{}: (tables,Done{None{}})
    case I.InvStack{+key,+count}: item_chosen(stack_visible(key,count),key,count,tables,id,age,position,bob,catalog,lights)
def orb_color(red_sine:F32,blue_sine:F32) -> U32:
  +red = F32.to_u32(F32.mul(F32.mul(F32.add(red_sine,1.0),0.5),255.0))
  +blue = F32.to_u32(F32.mul(F32.mul(F32.add(blue_sine,1.0),0.1),255.0))
  U32.or(2147483648,U32.or(U32.shln(red,16n),U32.or(65280,blue)))
def orb_vertex(x:F32,y:F32,u:F32,v:F32,matrix:K.Mat,origin:M.Vec3) -> M.Vertex:
  M.Vertex{T.moved(M.Vec3{F32.mul(x,0.3),F32.mul(y,0.3),0.0},matrix,M.Vec3{0.0,0.0,0.0},origin),M.UV{u,v}}
def orb_quad(+icon:U32,texture:U32,+color:U32,+rgb:U32,+billboard:D.Quaternion,position:M.Vec3) -> M.Quad:
  +u0 = F32.div(F32.from_nat(U32.to_nat(U32.mul(U32.mod(icon,4),16))),64.0)
  +u1 = F32.add(u0,0.25)
  +v0 = F32.div(F32.from_nat(U32.to_nat(U32.mul(U32.div(icon,4),16))),64.0)
  +v1 = F32.add(v0,0.25)
  +origin = item_origin(position,0.1)
  +matrix = D.matrix(billboard)
  M.Quad{orb_vertex(F32.neg(0.5),F32.neg(0.25),u0,v1,matrix,origin),orb_vertex(0.5,F32.neg(0.25),u1,v1,matrix,origin),orb_vertex(0.5,0.75,u1,v0,matrix,origin),orb_vertex(F32.neg(0.5),0.75,u0,v0,matrix,origin),M.Material{texture,color,rgb,1.0,M.Translucent{},M.Clamp{}},M.NoCull{},0}
def orb_draw(id:U32,age:F32,+position:M.Vec3,value:U32,texture:U32,light:D.Light,billboard:D.Quaternion,red:F32,blue:F32) -> D.Draw:
  D.Light{lid,block,sky,item,rgb} = light
  +icon = T.icon(value)
  +color = orb_color(red,blue)
  D.OrbDraw{id,age,position,icon,D.packed(U32.min(15,U32.add(block,7)),sky),color,orb_quad(icon,texture,color,rgb,billboard,position)}
def orb_blue(id:U32,age:F32,position:M.Vec3,value:U32,texture:U32,light:D.Light,billboard:D.Quaternion,red:F32,pair:L.Tables & F32) -> L.Tables & Result<&2,&2,D.Error,Maybe<&2,D.Draw>>:
  (tables,blue) = pair
  (tables,Done{Some{orb_draw(id,age,position,value,texture,light,billboard,red,blue)}})
def orb_red(id:U32,+age:F32,position:M.Vec3,value:U32,texture:U32,light:D.Light,billboard:D.Quaternion,pair:L.Tables & F32) -> L.Tables & Result<&2,&2,D.Error,Maybe<&2,D.Draw>>:
  (tables,red) = pair
  orb_blue(id,age,position,value,texture,light,billboard,red,L.sin(tables,F.from_f32(F32.add(F32.div(age,2.0),4.1887903))))
def orb_ready(result:Result<&2,&2,D.Error,D.OrbInput>,tables:L.Tables,id:U32,+age:F32,position:M.Vec3,value:U32,billboard:D.Quaternion) -> L.Tables & Result<&2,&2,D.Error,Maybe<&2,D.Draw>>:
  match result:
    case Fail{error}: (tables,Fail{error})
    case Done{D.OrbInput{texture,light}}: orb_red(id,age,position,value,texture,light,billboard,L.sin(tables,F.from_f32(F32.div(age,2.0))))
def orb_texture(value:Maybe<&2,U32>) -> Result<&2,&2,D.Error,U32>:
  match value:
    case None{}: Fail{D.Refused{"render:actual experience orb atlas not loaded"}}
    case Some{slot}: Done{slot}
def orb_data(catalog:D.Catalog,lights:List<&2,D.Light>,id:U32) -> Result<&2,&2,D.Error,D.OrbInput>:
  D.Catalog{items,count,orb} = catalog
  do Result<&2,&2,D.Error,D.OrbInput>:
    slot : U32 <- orb_texture(orb)
    light : D.Light <- D.required_light(D.light(lights,id))
    return D.OrbInput{slot,light}
def visible(common:D.Common,+dimension:String) -> Bool:
  D.Common{actual,id,current,old,tick,removed,accessible,order} = common
  String.eq(actual,dimension) && Bool.not(removed) && accessible
def record_dispatch(record:D.Record,tables:L.Tables,+id:U32,age:F32,position:M.Vec3,catalog:D.Catalog,lights:List<&2,D.Light>,billboard:D.Quaternion) -> L.Tables & Result<&2,&2,D.Error,Maybe<&2,D.Draw>>:
  match record:
    case D.Item{base,slot,bob}: item(slot,tables,id,age,position,bob,catalog,lights)
    case D.Orb{base,value}: orb_ready(orb_data(catalog,lights,id),tables,id,age,position,value,billboard)
def positioned(record:D.Record,tables:L.Tables,id:U32,tick:U32,current:V.Vec3,old_position:V.Vec3,context:D.Context) -> L.Tables & Result<&2,&2,D.Error,Maybe<&2,D.Draw>>:
  D.Context{dimension,camera,+partial,billboard,catalog,lights,scan,quads} = context
  record_dispatch(record,tables,id,T.age(tick,partial),T.relative(old_position,current,camera,partial),catalog,lights,billboard)
def common_record(record:D.Record,tables:L.Tables,common:D.Common,context:D.Context) -> L.Tables & Result<&2,&2,D.Error,Maybe<&2,D.Draw>>:
  D.Common{d,id,current,old,tick,removed,accessible,order} = common
  positioned(record,tables,id,tick,current,old,context)
def common(record:D.Record) -> D.Common:
  match record:
    case D.Item{base,item,bob}: base
    case D.Orb{base,value}: base
def record_visible(show:Bool,+record:D.Record,tables:L.Tables,context:D.Context) -> L.Tables & Result<&2,&2,D.Error,Maybe<&2,D.Draw>>:
  match show:
    case False{}: (tables,Done{None{}})
    case True{}: common_record(record,tables,common(record),context)
def record(+record:D.Record,tables:L.Tables,+context:D.Context) -> L.Tables & Result<&2,&2,D.Error,Maybe<&2,D.Draw>>:
  D.Context{dimension,camera,partial,billboard,catalog,lights,scan,quads} = context
  record_visible(visible(common(record),dimension),record,tables,context)
def draw_quads(value:D.Draw) -> List<&2,M.Quad>:
  match value:
    case D.ItemDraw{id,key,age,origin,hover,spin,copies,light,block,quads}: quads
    case D.OrbDraw{id,age,origin,icon,light,color,quad}: [quad]
def append_draw(value:Maybe<&2,D.Draw>,draws:List<&2,D.Draw>,quads:List<&2,M.Quad>) -> D.Frame:
  match value:
    case None{}: D.Frame{draws,quads}
    case Some{+head}: D.Frame{head <> draws,List.append(&2,M.Quad,draw_quads(head),quads)}
def append_frame(value:Maybe<&2,D.Draw>,frame:D.Frame) -> D.Frame:
  D.Frame{draws,quads} = frame
  append_draw(value,draws,quads)
def appended_frame(draw:Maybe<&2,D.Draw>,pair:L.Tables & Result<&2,&2,D.Error,D.Frame>) -> L.Tables & Result<&2,&2,D.Error,D.Frame>:
  (tables,result) = pair
  (tables,Result.map(&2,&2,D.Error,D.Frame,D.Frame,frame => append_frame(draw,frame),result))
def records_result(tables:L.Tables,result:Result<&2,&2,D.Error,Maybe<&2,D.Draw>>,
    next:L.Tables -> L.Tables & Result<&2,&2,D.Error,D.Frame>) -> L.Tables & Result<&2,&2,D.Error,D.Frame>:
  match result:
    case Fail{error}: (tables,Fail{error})
    case Done{draw}: appended_frame(draw,next(tables))
def records_pair(pair:L.Tables & Result<&2,&2,D.Error,Maybe<&2,D.Draw>>,
    next:L.Tables -> L.Tables & Result<&2,&2,D.Error,D.Frame>) -> L.Tables & Result<&2,&2,D.Error,D.Frame>:
  (tables,result) = pair
  records_result(tables,result,next)
def records(left:Nat,values:List<&2,D.Record>,tables:L.Tables,+context:D.Context) -> L.Tables & Result<&2,&2,D.Error,D.Frame>:
  match left values:
    case _ Nil{}: (tables,Done{D.Frame{[],[]}})
    case 0n _: (tables,Fail{D.ScanBudget{}})
    case 1n+rest head <> tail: records_pair(record(head,tables,context),tables => records(rest,tail,tables,context))
def quads_fit(left:Nat,values:List<&2,M.Quad>) -> Bool:
  match left values:
    case _ Nil{}: True{}
    case 0n _: False{}
    case 1n+rest head <> tail: quads_fit(rest,tail)
def checked_frame(fit:Bool,frame:D.Frame) -> Result<&2,&2,D.Error,D.Frame>:
  match fit:
    case False{}: Fail{D.QuadBudget{}}
    case True{}: Done{frame}
def finished(result:L.Tables & Result<&2,&2,D.Error,D.Frame>,budget:Nat) -> L.Tables & Result<&2,&2,D.Error,D.Frame>:
  (tables,status) = result
  match status:
    case Fail{error}: (tables,Fail{error})
    case Done{+frame}:
      D.Frame{draws,quads} = frame
      (tables,checked_frame(quads_fit(budget,quads),frame))
def valid(context:D.Context) -> Bool:
  D.Context{dimension,camera,+partial,q,catalog,lights,scan,quads} = context
  V.Vec3{x,y,z} = camera
  D.Quaternion{a,b,c,d} = q
  F.is_finite(x) && F.is_finite(y) && F.is_finite(z) && M.finite(partial) && F32.is_ge(partial,0.0) && F32.is_le(partial,1.0) && M.finite(a) && M.finite(b) && M.finite(c) && M.finite(d)
def prepare_bound(snapshot:D.Snapshot,+context:D.Context,tables:L.Tables) -> L.Tables & Result<&2,&2,D.Error,D.Frame>:
  match snapshot:
    case D.Unbound{}: (tables,Fail{D.Refused{"render:entity snapshot unbound"}})
    case D.Bound{values}:
      D.Context{dimension,camera,partial,billboard,catalog,lights,scan,quads} = context
      finished(records(scan,values,tables,context),quads)
def prepare_gate(ok:Bool,context:D.Context,snapshot:D.Snapshot,tables:L.Tables) -> L.Tables & Result<&2,&2,D.Error,D.Frame>:
  match ok:
    case False{}: (tables,Fail{D.Refused{"render:invalid camera/interpolation context"}})
    case True{}: prepare_bound(snapshot,context,tables)
def render_fields(fields:V.Fields,dimension:String,id:U32,tick:U32,removed:Bool,accessible:Bool,order:Nat) -> D.Common:
  D.render_fields(fields,dimension,id,tick,removed,accessible,order)
def render_common(common:E.Common) -> D.Common: D.render_common(common)
def render_record(record:E.Record) -> D.Record: D.render_record(record)
def render_records(values:List<&2,E.Record>) -> List<&2,D.Record>: D.render_records(values)
def render_snapshot(view:E.View) -> D.Snapshot: D.render_snapshot(view)
def prepare_snapshot(+context:D.Context,snapshot:D.Snapshot,tables:L.Tables) -> L.Tables & Result<&2,&2,D.Error,D.Frame>:
  prepare_gate(valid(context),context,snapshot,tables)
# Numerical table stays affine. No entity RNG, ID, age or tick advances here.
def prepare(+context:D.Context,view:E.View,tables:L.Tables) -> L.Tables & Result<&2,&2,D.Error,D.Frame>:
  prepare_snapshot(context,render_snapshot(view),tables)
def capture_result(state:E.State,pair:L.Tables & Result<&2,&2,D.Error,D.Frame>) -> E.State & L.Tables & Result<&2,&2,D.Error,D.Frame>:
  (tables,result) = pair
  (state,tables,result)
def captured(context:D.Context,tables:L.Tables,snapshot:E.State & E.View) -> E.State & L.Tables & Result<&2,&2,D.Error,D.Frame>:
  (state,view) = snapshot
  capture_result(state,prepare(context,view,tables))
def capture(context:D.Context,state:E.State,tables:L.Tables) -> E.State & L.Tables & Result<&2,&2,D.Error,D.Frame>:
  captured(context,tables,E.inspect(state))
