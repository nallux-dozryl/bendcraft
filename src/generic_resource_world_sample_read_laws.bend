import Base
import ./generic_resource_world_sample_read.bend as Read
import ./generic_resource_world_sample.bend as GS
import ./client_world.bend as W
import ./core.bend as C
import ./game.bend as G
import ./registry.bend as B
import ./movement.bend as MV
import ./client_render.bend as R

law camera_uses_the_supplied_pose_eye_as_origin:
  for body:MV.Body
  for +yaw:F32
  for +pitch:F32
  for palette:Maybe<&2,W.Palette>
  for region:W.Bounds
  for cache:Maybe<&2,W.SnapshotCache>
  {Read.camera(W.View{body,yaw,pitch,palette,region,cache}) ==
    R.Camera{0.0,0.0,0.0,yaw,pitch} : R.Camera}

law invalid_region_snapshot_preserves_the_complete_world_owner:
  for engine:G.Engine
  for +body:MV.Body
  for +yaw:F32
  for +pitch:F32
  for +palette:Maybe<&2,W.Palette>
  for +region:W.Bounds
  for +cache:Maybe<&2,W.SnapshotCache>
  for +origin:MV.Vec3
  for +identity:String
  for policy:GS.Policy
  for invalid:{W.bounds_valid(region) == False{} : Bool}
  {Read.snapshot(W.State{engine,body,yaw,pitch,palette,region,cache},origin,identity,policy) ==
    (W.State{engine,body,yaw,pitch,palette,region,cache},Fail{"generic-resource:invalid-region"}) :
    W.State & Result<&2,&2,String,GS.Sample>}

law prior_read_refusal_stops_every_remaining_cell:
  for n:Nat
  for index:U32
  for region:W.Bounds
  for policy:GS.Policy
  for world:C.World
  for +error:String
  {Read.collect(n,index,region,policy,world,Fail{error}) ==
    (world,Fail{error}) : C.World & Result<&2,&2,String,List<&2,GS.Cell>>}

law exhausted_traversal_returns_the_complete_prefix_in_cell_order:
  for index:U32
  for region:W.Bounds
  for policy:GS.Policy
  for world:C.World
  for +reversed:List<&2,GS.Cell>
  {Read.collect(0n,index,region,policy,world,Done{reversed}) ==
    (world,Done{List.reverse(&2,GS.Cell,reversed)}) : C.World & Result<&2,&2,String,List<&2,GS.Cell>>}

law read_refusal_retains_the_returned_core_and_exact_diagnostic:
  for point:W.Cell
  for policy:GS.Policy
  for reversed:List<&2,GS.Cell>
  for world:C.World
  for +error:C.Error
  {Read.read_value(point,policy,reversed,(world,Fail{error})) ==
    (world,Fail{W.error_text(error)}) : C.World & Result<&2,&2,String,List<&2,GS.Cell>>}

# No air or catalog whitelist premise: every raw U32 ID becomes an observation.
law every_observed_state_retains_point_seed_appearance_and_prefix:
  for +point:W.Cell
  for +state:U32
  for +policy:GS.Policy
  for +reversed:List<&2,GS.Cell>
  for world:C.World
  {Read.read_value(point,policy,reversed,(world,Done{state})) ==
    (world,Done{GS.cell_value(point,state,policy) <> reversed}) :
    C.World & Result<&2,&2,String,List<&2,GS.Cell>>}

# The premise is the actual Core read interface, not a second world or reader.
law single_actual_core_read_returns_its_owner_and_all_observed_data:
  for +index:U32
  for +region:W.Bounds
  for +policy:GS.Policy
  for +reversed:List<&2,GS.Cell>
  for world:C.World
  for next:C.World
  for +state:U32
  for observed:{C.read_block(world,W.position(W.cell(region,index))) ==
    (next,Done{state}) : C.World & Result<&2,&2,C.Error,U32>}
  {Read.collect(1n,index,region,policy,world,Done{reversed}) ==
    (next,Done{List.reverse(&2,GS.Cell,GS.cell_value(W.cell(region,index),state,policy) <> reversed)}) :
    C.World & Result<&2,&2,String,List<&2,GS.Cell>>}

law failed_sample_retains_registry_and_complete_original_view:
  for world:C.World
  for registry:B.Registry
  for +view:W.View
  for origin:MV.Vec3
  for identity:String
  for tick:Nat
  for revision:Nat
  for tail:List<&2,Read.Capture>
  for +error:String
  {Read.finished((world,Fail{error}),registry,Read.Capture{view,origin,identity,tick,revision,tail}) ==
    (W.attach(G.Engine{world,registry},view),Fail{error}) : W.State & Result<&2,&2,String,GS.Sample>}

law admitted_sample_retains_registry_view_and_clock_metadata:
  for world:C.World
  for registry:B.Registry
  for +view:W.View
  for +origin:MV.Vec3
  for +identity:String
  for +tick:Nat
  for +revision:Nat
  for tail:List<&2,Read.Capture>
  for +cells:List<&2,GS.Cell>
  for admitted:{GS.sample_valid(GS.Sample{identity,tick,revision,origin,Read.camera(view),cells}) == True{} : Bool}
  {Read.finished((world,Done{cells}),registry,Read.Capture{view,origin,identity,tick,revision,tail}) ==
    (W.attach(G.Engine{world,registry},view),Done{GS.Sample{identity,tick,revision,origin,Read.camera(view),cells}}) :
      W.State & Result<&2,&2,String,GS.Sample>}

law invalid_sample_retains_registry_and_complete_original_view:
  for world:C.World
  for registry:B.Registry
  for +view:W.View
  for +origin:MV.Vec3
  for +identity:String
  for +tick:Nat
  for +revision:Nat
  for tail:List<&2,Read.Capture>
  for +cells:List<&2,GS.Cell>
  for invalid:{GS.sample_valid(GS.Sample{identity,tick,revision,origin,Read.camera(view),cells}) == False{} : Bool}
  {Read.finished((world,Done{cells}),registry,Read.Capture{view,origin,identity,tick,revision,tail}) ==
    (W.attach(G.Engine{world,registry},view),Fail{"generic-resource:invalid-sample"}) :
    W.State & Result<&2,&2,String,GS.Sample>}
