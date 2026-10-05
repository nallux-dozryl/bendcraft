import Base
import ./item_entity_render.bend as R
import ./item_entity_render_model.bend as D
import ./item_entity_render_transform.bend as T
import ./cooking_effect_entities_model.bend as E
import ./vanilla_entity_fields.bend as V
import ./player_look.bend as Look
import ./locomotion.bend as L
import ./random.bend as RNG
import ./f64.bend as F
import ./inventory.bend as I
import ./mesh_render.bend as M
import ./block_bake.bend as K

# The authoritative interpolation vector is xOld/yOld/zOld, independent of
# xo/yo/zo, velocity and the scheduler's simulation sidecars.
law presentation_uses_actual_old_position:
  for current:V.Vec3
  for velocity:V.Vec3
  for xo:V.Vec3
  for old:V.Vec3
  for look:Look.State
  for head:F32
  for body:F32
  for fall:F.F64
  for grounded:Bool
  for air:U32
  for fire:U32
  for portal:U32
  for invulnerable:Bool
  for sync:Bool
  for dimension:String
  for id:U32
  for tick:U32
  for removed:Bool
  for accessible:Bool
  for order:Nat
  {R.render_fields(V.Fields{current,velocity,xo,old,look,head,body,fall,grounded,air,fire,portal,invulnerable,sync},dimension,id,tick,removed,accessible,order) == D.Common{dimension,id,current,old,tick,removed,accessible,order} : D.Common}
def presentation_uses_actual_old_position(current,velocity,xo,old,look,head,body,fall,grounded,air,fire,portal,invulnerable,sync,dimension,id,tick,removed,accessible,order): {==}

law item_projection_preserves_full_components_and_bob:
  for common:E.Common
  for item:I.Slot
  for age:U32
  for delay:U32
  for health:U32
  for thrower:Maybe<&2,E.Uuid>
  for target:Maybe<&2,E.Uuid>
  for bob:F32
  {R.render_record(E.Item{common,item,age,delay,health,thrower,target,bob}) == D.Item{R.render_common(common),item,bob} : D.Record}
def item_projection_preserves_full_components_and_bob(common,item,age,delay,health,thrower,target,bob): {==}

law orb_projection_preserves_actual_value:
  for common:E.Common
  for value:U32
  for age:U32
  for health:U32
  for count:U32
  for following:Maybe<&2,E.Uuid>
  {R.render_record(E.Orb{common,value,age,health,count,following}) == D.Orb{R.render_common(common),value} : D.Record}
def orb_projection_preserves_actual_value(common,value,age,health,count,following): {==}

law snapshot_excludes_simulation_random_and_factory:
  for random:RNG.Source
  for factory:RNG.Bits64
  for cursor:U32
  for order:Nat
  for records:List<&2,E.Record>
  {R.render_snapshot(E.View{random,factory,cursor,order,records}) == D.Bound{R.render_records(records)} : D.Snapshot}
def snapshot_excludes_simulation_random_and_factory(random,factory,cursor,order,records): {==}

law record_projection_preserves_source_sequence:
  for head:E.Record
  for tail:List<&2,E.Record>
  {R.render_records(head <> tail) == R.render_record(head) <> R.render_records(tail) : List<&2,D.Record>}
def record_projection_preserves_source_sequence(head,tail): {==}

law unbound_is_a_refusal_and_retains_numerical_owner:
  for context:D.Context
  for tables:L.Tables
  {R.prepare_bound(D.Unbound{},context,tables) == (tables,Fail{D.Refused{"render:entity snapshot unbound"}}) : L.Tables & Result<&2,&2,D.Error,D.Frame>}
def unbound_is_a_refusal_and_retains_numerical_owner(context,tables): {==}

law hidden_record_preserves_numerical_owner:
  for record:D.Record
  for context:D.Context
  for tables:L.Tables
  {R.record_visible(False{},record,tables,context) == (tables,Done{None{}}) : L.Tables & Result<&2,&2,D.Error,Maybe<&2,D.Draw>>}
def hidden_record_preserves_numerical_owner(record,context,tables): {==}

law exhausted_scan_publishes_no_partial_frame:
  for head:D.Record
  for tail:List<&2,D.Record>
  for context:D.Context
  for tables:L.Tables
  {R.records(0n,head <> tail,tables,context) == (tables,Fail{D.ScanBudget{}}) : L.Tables & Result<&2,&2,D.Error,D.Frame>}
def exhausted_scan_publishes_no_partial_frame(head,tail,context,tables): {==}

law empty_scan_is_a_bound_empty_frame:
  for budget:Nat
  for context:D.Context
  for tables:L.Tables
  {R.records(budget,[],tables,context) == (tables,Done{D.Frame{[],[]}}) : L.Tables & Result<&2,&2,D.Error,D.Frame>}
def empty_scan_is_a_bound_empty_frame(budget,context,tables):
  match budget:
    case 0n: {==}
    case 1n+rest: {==}

law failed_quad_budget_cannot_publish_frame:
  for frame:D.Frame
  {R.checked_frame(False{},frame) == Fail{D.QuadBudget{}} : Result<&2,&2,D.Error,D.Frame>}
def failed_quad_budget_cannot_publish_frame(frame): {==}

law dynamic_light_preserves_texture_tint_and_material:
  for texture:U32
  for tint:U32
  for prior:U32
  for light:U32
  for shade:F32
  for mode:M.Mode
  for address:M.Address
  {T.material(M.Material{texture,tint,prior,shade,mode,address},light) == M.Material{texture,tint,light,shade,mode,address} : M.Material}
def dynamic_light_preserves_texture_tint_and_material(texture,tint,prior,light,shade,mode,address): {==}

law transformed_vertex_preserves_actual_uv:
  for point:M.Vec3
  for uv:M.UV
  for matrix:K.Mat
  for offset:M.Vec3
  for origin:M.Vec3
  {T.vertex(M.Vertex{point,uv},matrix,offset,origin) == M.Vertex{T.moved(point,matrix,offset,origin),uv} : M.Vertex}
def transformed_vertex_preserves_actual_uv(point,uv,matrix,offset,origin): {==}

law no_item_copies_produces_no_geometry:
  for quads:List<&2,M.Quad>
  for matrix:K.Mat
  for origin:M.Vec3
  for light:U32
  {T.clustered([],quads,matrix,origin,light) == [] : List<&2,M.Quad>}
def no_item_copies_produces_no_geometry(quads,matrix,origin,light): {==}

law zero_count_item_stack_is_not_drawn:
  for key:I.ItemKey
  for tables:L.Tables
  for id:U32
  for age:F32
  for position:M.Vec3
  for bob:F32
  for catalog:D.Catalog
  for lights:List<&2,D.Light>
  {R.item(I.InvStack{key,0},tables,id,age,position,bob,catalog,lights) == (tables,Done{None{}}) : L.Tables & Result<&2,&2,D.Error,Maybe<&2,D.Draw>>}
def zero_count_item_stack_is_not_drawn(key,tables,id,age,position,bob,catalog,lights):
  match key:
    case I.ItemKey{name,components}: {==}
