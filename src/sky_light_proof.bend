import Base
import ./sky_light.bend as S
import ./block_light.bend as B
import ./block_light_registry.bend as R
import ./core.bend as C
import ./sky_light_laws.bend as L

def and_false_right(value:Bool) -> {(value && False{}) == False{} : Bool}:
  match value:
    case False{}: {==}
    case True{}: {==}

def L.non_source_never_injects_block_emission(state,emission,dampening): {==}
def L.direct_source_injects_fifteen_independently_of_block_emission(state,emission,dampening): {==}
def L.disabled_column_has_no_sources(y,lowest,minimum,height): {==}

def L.below_column_field_minimum_has_no_sources(y,lowest,enabled,minimum,height,below):
  %Equal.sym(Bool,S.signed_ge(y,minimum),False{},below) :
    {((enabled && _) && S.signed_lt(y,U32.add(minimum,height)) && S.source_lowest(y,lowest)) == False{} : Bool}
  %Equal.sym(Bool,enabled && False{},False{},and_false_right(enabled)) :
    {(_ && S.signed_lt(y,U32.add(minimum,height)) && S.source_lowest(y,lowest)) == False{} : Bool}
  {==}

def L.at_or_above_column_field_limit_has_no_sources(y,lowest,enabled,minimum,height,outside):
  %Equal.sym(Bool,S.signed_lt(y,U32.add(minimum,height)),False{},outside) :
    {((enabled && S.signed_ge(y,minimum)) && _ && S.source_lowest(y,lowest)) == False{} : Bool}
  %Equal.sym(Bool,(enabled && S.signed_ge(y,minimum)) && False{},False{},
      and_false_right(enabled && S.signed_ge(y,minimum))) :
    {(_ && S.source_lowest(y,lowest)) == False{} : Bool}
  {==}

def L.below_known_source_threshold_has_no_sources(y,threshold,enabled,minimum,height,below):
  %Equal.sym(Bool,S.signed_ge(y,threshold),False{},below) :
    {((enabled && S.signed_ge(y,minimum) && S.signed_lt(y,U32.add(minimum,height))) && _) == False{} : Bool}
  and_false_right(enabled && S.signed_ge(y,minimum) && S.signed_lt(y,U32.add(minimum,height)))

def L.unknown_column_cannot_supply_a_source(position):
  match position:
    case C.Position{dimension,x,y,z}: {==}

def L.source_blocking_uses_opacity_or_upper_down_lower_up_union(catalog,above,above_emission,above_dampening,below,below_emission,below_dampening): {==}

def L.positive_target_opacity_blocks_column_source(catalog,above,below,opaque):
  %Equal.sym(Bool,U32.is_gt(B.dampening(below),0),True{},opaque) :
    {(_ || R.occludes(catalog,above,below,B.Down{})) == True{} : Bool}
  {==}

def L.transparent_open_edge_preserves_column_source(catalog,above,below,transparent,open):
  %Equal.sym(Bool,U32.is_gt(B.dampening(below),0),False{},transparent) :
    {(_ || R.occludes(catalog,above,below,B.Down{})) == False{} : Bool}
  open

def L.unknown_column_publication_preserves_complete_state(state,position,physical):
  match state:
    case S.State{field,columns}: {==}

def L.rejected_descriptor_preserves_complete_state(state,position,physical,invalid):
  %Equal.sym(Bool,B.descriptor_valid(physical),False{},invalid) :
    {S.publish_valid(_,state,position,physical) == (state,Fail{S.InvalidDescriptor{}}) :
      S.State & Result<&2,&2,S.Error,Unit>}
  {==}

def L.missing_physical_cell_preserves_complete_state(state,position): {==}

def L.zero_budget_preserves_complete_state(catalog,state):
  match state:
    case S.State{B.State{cells,front,back,queued,pending},columns}: {==}

def L.settled_field_has_no_work_for_any_budget(catalog,cells,columns,budget):
  match budget:
    case 0n: {==}
    case 1n+remaining: {==}

def L.new_field_distinguishes_unknown_from_dark(position): {==}
def L.missing_physical_read_preserves_unknown_and_owned_field(old,cells,front,back,queued,pending,columns): {==}

def L.unknown_sample_preserves_complete_sky_state(field,columns,position,unknown):
  %Equal.sym(B.State & Maybe<&2,U32>,B.sample(field,position),(field,None{}),unknown) :
    {B.paired(B.State,Maybe<&2,U32>,S.State & Maybe<&2,U32>,_,
      field => level => (S.State{field,columns},level)) == (S.State{field,columns},None{}) :
      S.State & Maybe<&2,U32>}
  {==}

def L.every_non_source_edge_uses_shared_attenuating_transfer(closed,source,target,direction,level):
  match target:
    case B.Descriptor{state,emission,dampening}: {==}

def L.registry_non_source_edge_uses_shared_attenuating_transfer(catalog,source,target,direction,level):
  match source target:
    case B.Descriptor{source_state,source_emission,source_dampening} B.Descriptor{target_state,target_emission,target_dampening}: {==}

def L.advance_retains_columns_and_uses_complete_shared_field_result(catalog,budget,field,advanced,columns,status,result):
  %Equal.sym(B.State & B.Status,B.advance(~R.Catalog,~R.occludes,catalog,budget,field),(advanced,status),result) :
    {B.paired(B.State,B.Status,S.State & B.Status,_,
      field => status => (S.State{field,columns},status)) == (S.State{advanced,columns},status) : S.State & B.Status}
  {==}

def L.registry_closed_edge_prevents_all_sky_transfer(catalog,source,target,direction,level,closed):
  %Equal.sym(U32,
      B.contribution(~R.Catalog,~R.occludes,catalog,S.descriptor(target,False{}),direction,
        Some{B.Cell{S.descriptor(source,False{}),level}}),
      B.transfer(R.occludes(catalog,source,target,direction),level,B.dampening(target)),
      L.registry_non_source_edge_uses_shared_attenuating_transfer(catalog,source,target,direction,level)) :
    {_ == 0 : U32}
  %Equal.sym(Bool,R.occludes(catalog,source,target,direction),True{},closed) :
    {B.transfer(_,level,B.dampening(target)) == 0 : U32}
  {==}

def L.open_level_fifteen_loses_one_in_every_direction(source,target,target_emission,direction): {==}
def L.closed_edge_prevents_all_sky_transfer(source,target,direction,level): {==}
def L.unknown_neighbor_cannot_supply_sky_light(closed,target,direction): {==}
