import Base
import ./generic_resource_world_sample_read_laws.bend as L
import ./generic_resource_world_sample_read.bend as Read
import ./generic_resource_world_sample.bend as GS
import ./client_world.bend as W
import ./core.bend as C
import ./game.bend as G
import ./registry.bend as B
import ./client_render.bend as R
import ./player_look.bend as PL
import ./world_mesh.bend as WM

def L.camera_uses_the_supplied_pose_eye_as_origin(body,yaw,pitch,palette,region,cache):
  {==}

def L.invalid_region_snapshot_preserves_the_complete_world_owner(engine,body,yaw,pitch,palette,region,cache,origin,identity,policy,invalid):
  %Equal.sym(Bool,W.bounds_valid(region),False{},invalid) :
    {Read.gated(W.choose(String,"generic-resource:invalid-region",
      W.choose(String,"generic-resource:invalid-origin",
        W.choose(String,"generic-resource:invalid-camera",
          W.choose(String,"generic-resource:invalid-registry-identity","",String.is_empty(identity)),
          Bool.not(PL.finite(yaw) && PL.finite(pitch) && WM.relative_camera(Read.camera(W.View{body,yaw,pitch,palette,region,cache})))),
        Bool.not(W.finite_relative_origin(origin))),Bool.not(_)),
      engine,W.View{body,yaw,pitch,palette,region,cache},origin,identity,policy) ==
      (W.State{engine,body,yaw,pitch,palette,region,cache},Fail{"generic-resource:invalid-region"}) :
      W.State & Result<&2,&2,String,GS.Sample>}
  {==}

def L.prior_read_refusal_stops_every_remaining_cell(n,index,region,policy,world,error):
  match n:
    case 0n: {==}
    case 1n+rest: {==}

def L.exhausted_traversal_returns_the_complete_prefix_in_cell_order(index,region,policy,world,reversed):
  {==}

def L.read_refusal_retains_the_returned_core_and_exact_diagnostic(point,policy,reversed,world,error):
  {==}

def L.every_observed_state_retains_point_seed_appearance_and_prefix(point,state,policy,reversed,world):
  {==}

def L.single_actual_core_read_returns_its_owner_and_all_observed_data(index,region,policy,reversed,world,next,state,observed):
  %Equal.sym(C.World & Result<&2,&2,C.Error,U32>,
    C.read_block(world,W.position(W.cell(region,index))),(next,Done{state}),observed) :
    {W.paired(C.World,Result<&2,&2,String,List<&2,GS.Cell>>,
      C.World & Result<&2,&2,String,List<&2,GS.Cell>>,
      Read.read_value(W.cell(region,index),policy,reversed,_),
      returned => result => Read.collect(0n,U32.inc(index),region,policy,returned,result)) ==
      (next,Done{List.reverse(&2,GS.Cell,GS.cell_value(W.cell(region,index),state,policy) <> reversed)}) :
      C.World & Result<&2,&2,String,List<&2,GS.Cell>>}
  {==}

def L.failed_sample_retains_registry_and_complete_original_view(world,registry,view,origin,identity,tick,revision,tail,error):
  {==}

def L.admitted_sample_retains_registry_view_and_clock_metadata(world,registry,view,origin,identity,tick,revision,tail,cells,admitted):
  %Equal.sym(Bool,GS.sample_valid(GS.Sample{identity,tick,revision,origin,Read.camera(view),cells}),True{},admitted) :
    {(W.attach(G.Engine{world,registry},view),GS.sample_admitted(_,GS.Sample{identity,tick,revision,origin,Read.camera(view),cells})) ==
      (W.attach(G.Engine{world,registry},view),Done{GS.Sample{identity,tick,revision,origin,Read.camera(view),cells}}) :
      W.State & Result<&2,&2,String,GS.Sample>}
  {==}

def L.invalid_sample_retains_registry_and_complete_original_view(world,registry,view,origin,identity,tick,revision,tail,cells,invalid):
  %Equal.sym(Bool,GS.sample_valid(GS.Sample{identity,tick,revision,origin,Read.camera(view),cells}),False{},invalid) :
    {(W.attach(G.Engine{world,registry},view),GS.sample_admitted(_,GS.Sample{identity,tick,revision,origin,Read.camera(view),cells})) ==
      (W.attach(G.Engine{world,registry},view),Fail{"generic-resource:invalid-sample"}) :
      W.State & Result<&2,&2,String,GS.Sample>}
  {==}
