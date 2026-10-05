import Base
import ./vanilla_block_lighting.bend as L
import ./vanilla_block_lighting_model.bend as M
import ./vanilla_block_lighting_math.bend as F
import ./block_model.bend as B

law no_element_emission_preserves_every_fractional_coordinate_bit:
  for +packed:U32
  {F.with_emission(packed,0) == packed : U32}
def no_element_emission_preserves_every_fractional_coordinate_bit(packed): {==}
law emissive_state_uses_java_full_brightness_without_reading_absent_fields:
  for context:M.Context
  for point:M.Position
  for emission:U32
  {L.light_gate(context,point,emission,True{}) == Done{15728880} : Result<&2,&2,M.Error,U32>}
def emissive_state_uses_java_full_brightness_without_reading_absent_fields(context,point,emission): {==}
law closed_diagonal_preserves_complete_edge_light_and_shade:
  for context:M.Context
  for point:M.Position
  for +edge:M.Corner
  {L.diagonal(context,point,edge,False{}) == Done{edge} : Result<&2,&2,M.Error,M.Corner>}
def closed_diagonal_preserves_complete_edge_light_and_shade(context,point,edge): {==}
law full_face_retains_all_four_corner_results_without_weighting:
  for +corners:M.Corners
  for bounds:M.Bounds
  for adjacency:M.Adjacency
  {L.weighted_gate(corners,bounds,adjacency,False{}) == corners : M.Corners}
def full_face_retains_all_four_corner_results_without_weighting(corners,bounds,adjacency): {==}
law flat_known_light_is_uniform_and_does_not_consult_neighbour_facts:
  for context:M.Context
  for origin:M.Position
  for source:M.StateInfo
  for a:B.Vec3
  for b:B.Vec3
  for c:B.Vec3
  for d:B.Vec3
  for direction:B.Direction
  for override:Maybe<&2,B.Direction>
  for +emission:U32
  for +side:F32
  for +packed:U32
  {L.flat(context,origin,source,M.Quad{a,b,c,d,direction,override,emission},side,Some{packed}) == Done{L.flat_appearance(packed,side,emission)} : Result<&2,&2,M.Error,M.Appearance>}
def flat_known_light_is_uniform_and_does_not_consult_neighbour_facts(context,origin,source,a,b,c,d,direction,override,emission,side,packed):
  match source:
    case M.StateInfo{id,e,r,s,f,p,h}: {==}
law missing_state_information_is_refused:
  for position:M.Position
  for block:Maybe<&2,U32>
  for sky:Maybe<&2,U32>
  {L.information(M.Cell{position,None{},block,sky}) == Fail{M.Refused{"block lighting: actual state properties unavailable"}} : Result<&2,&2,M.Error,M.StateInfo>}
def missing_state_information_is_refused(position,block,sky): {==}
law missing_block_brightness_is_refused:
  for position:M.Position
  for state:Maybe<&2,M.StateInfo>
  for sky:Maybe<&2,U32>
  for emission:U32
  {L.levels(M.Cell{position,state,None{},sky},emission) == Fail{M.Refused{"block lighting: actual raw block/sky brightness unavailable"}} : Result<&2,&2,M.Error,U32>}
def missing_block_brightness_is_refused(position,state,sky,emission):
  match sky:
    case None{}: {==}
    case Some{value}: {==}
