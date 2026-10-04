import Base
import ./cooking_effect_geometry.bend as P
import ./cooking_effect_geometry_voxel.bend as S
import ./cooking_effect_geometry_world.bend as W
import ./cooking_effect_entities_model.bend as E
import ./vanilla_entity_fields.bend as V
import ./geometry.bend as A
import ./slab_collision.bend as C
import ./game.bend as G

law clear_initial_body_retains_exact_base_position:
  for context:P.Context
  for point:V.Vec3
  for body:A.AABB
  for center:V.Vec3
  for search:S.Shape
  for outer:A.AABB
  {P.place_clear(context,P.Prepared{point,body,center,search,outer},True{}) == Done{point} : Result<&2,&2,String,V.Vec3>}
def clear_initial_body_retains_exact_base_position(context,point,body,center,search,outer): {==}

law no_free_space_retains_exact_base_position:
  for point:V.Vec3
  {P.unstuck_result(point,None{}) == point : V.Vec3}
def no_free_space_retains_exact_base_position(point): {==}

law initial_block_collision_cannot_be_overridden_by_entity_list:
  for entities:List<&2,A.AABB>
  for box:A.AABB
  {P.no_collision_more(True{},entities,box) == False{} : Bool}
def initial_block_collision_cannot_be_overridden_by_entity_list(entities,box): {==}

law unstuck_search_never_subtracts_nonintersecting_blocks:
  for obstacle:P.Obstacle
  for current:S.Shape
  for budget:U32
  {P.union_hit(obstacle,current,budget,False{}) == Done{current} : Result<&2,&2,String,S.Shape>}
def unstuck_search_never_subtracts_nonintersecting_blocks(obstacle,current,budget): {==}

law closest_point_keeps_first_candidate_when_not_strictly_nearer:
  for candidate:V.Vec3
  for old:V.Vec3
  {S.closest_choice(candidate,old,False{}) == Some{old} : Maybe<&2,V.Vec3>}
def closest_point_keeps_first_candidate_when_not_strictly_nearer(candidate,old): {==}

law closest_point_installs_strictly_nearer_candidate:
  for candidate:V.Vec3
  for old:V.Vec3
  {S.closest_choice(candidate,old,True{}) == Some{candidate} : Maybe<&2,V.Vec3>}
def closest_point_installs_strictly_nearer_candidate(candidate,old): {==}

law first_free_box_supplies_first_candidate:
  for point:V.Vec3
  for candidate:V.Vec3
  {S.closest_more(point,candidate,None{}) == Some{candidate} : Maybe<&2,V.Vec3>}
def first_free_box_supplies_first_candidate(point,candidate): {==}

law empty_free_shape_has_no_position:
  for point:V.Vec3
  {S.closest(S.empty(),point) == None{} : Maybe<&2,V.Vec3>}
def empty_free_shape_has_no_position(point): {==}

law empty_subtraction_keeps_the_complete_search_shape:
  for shape:S.Shape
  for budget:U32
  {S.join_limited_gate(shape,S.empty(),2,budget,False{},True{}) == Done{shape} : Result<&2,&2,String,S.Shape>}
def empty_subtraction_keeps_the_complete_search_shape(shape,budget): {==}

law rejected_voxel_budget_cannot_allocate_a_boolean_result:
  for x:S.Merge
  for y:S.Merge
  for z:S.Merge
  for first:List<&2,S.Cell>
  for second:List<&2,S.Cell>
  for op:U32
  {S.join_limited_ready(x,y,z,first,second,op,False{}) == Fail{"geometry:voxel-budget"} : Result<&2,&2,String,S.Shape>}
def rejected_voxel_budget_cannot_allocate_a_boolean_result(x,y,z,first,second,op): {==}

law placement_refusal_is_the_entity_consumers_refusal:
  for reason:String
  {P.entity_result(Fail{reason}) == Fail{E.Refused{reason}} : Result<&2,&2,E.Error,V.Vec3>}
def placement_refusal_is_the_entity_consumers_refusal(reason): {==}

law refused_capture_returns_both_complete_affine_owners:
  for engine:G.Engine
  for catalog:C.Catalog
  for request:W.Request
  for reason:String
  {W.capture_gate(engine,catalog,request,Fail{reason}) == (engine,catalog,Fail{reason}) : G.Engine & C.Catalog & Result<&2,&2,String,P.Context>}
def refused_capture_returns_both_complete_affine_owners(engine,catalog,request,reason): {==}

law capture_refusal_branch_retains_complete_world_registry_and_catalog:
  for engine:G.Engine
  for catalog:C.Catalog
  for reason:String
  {W.capture_refused(engine,catalog,reason) == (engine,catalog,Fail{reason}) : G.Engine & C.Catalog & Result<&2,&2,String,P.Context>}
def capture_refusal_branch_retains_complete_world_registry_and_catalog(engine,catalog,reason): {==}

law refused_scanner_cannot_publish_partial_geometry:
  for request:W.Request
  for reason:String
  {W.context(request,Fail{reason}) == Fail{reason} : Result<&2,&2,String,P.Context>}
def refused_scanner_cannot_publish_partial_geometry(request,reason): {==}
