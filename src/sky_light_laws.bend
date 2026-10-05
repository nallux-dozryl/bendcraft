import Base
import ./sky_light.bend as S
import ./block_light.bend as B
import ./block_light_registry.bend as R
import ./core.bend as C

# These contracts describe the actual sky field owner and its production
# registry/transfer interfaces. Java observations separately validate the
# source thresholds and registry face data; these laws do not prove parity.
def owner_after(result:S.State & B.Status) -> S.State:
  (state,status) = result
  state

# A supplied edge result isolates the propagation law from the provider's
# geometric contract without substituting a second light implementation.
def edge(closed:Bool,source:B.Descriptor,target:B.Descriptor,direction:B.Direction) -> Bool:
  closed

law non_source_never_injects_block_emission:
  for state:U32
  for emission:U32
  for dampening:U32
  {S.descriptor(B.Descriptor{state,emission,dampening},False{}) ==
    B.Descriptor{state,0,dampening} : B.Descriptor}

law direct_source_injects_fifteen_independently_of_block_emission:
  for state:U32
  for emission:U32
  for dampening:U32
  {S.descriptor(B.Descriptor{state,emission,dampening},True{}) ==
    B.Descriptor{state,15,dampening} : B.Descriptor}

law disabled_column_has_no_sources:
  for y:U32
  for lowest:S.Lowest
  for minimum:U32
  for height:U32
  {S.source_y(y,S.Column{lowest,False{},minimum,height}) == False{} : Bool}

law below_column_field_minimum_has_no_sources:
  for +y:U32
  for +lowest:S.Lowest
  for +enabled:Bool
  for +minimum:U32
  for +height:U32
  for below:{S.signed_ge(y,minimum) == False{} : Bool}
  {S.source_y(y,S.Column{lowest,enabled,minimum,height}) == False{} : Bool}

law at_or_above_column_field_limit_has_no_sources:
  for +y:U32
  for +lowest:S.Lowest
  for +enabled:Bool
  for +minimum:U32
  for +height:U32
  for outside:{S.signed_lt(y,U32.add(minimum,height)) == False{} : Bool}
  {S.source_y(y,S.Column{lowest,enabled,minimum,height}) == False{} : Bool}

law below_known_source_threshold_has_no_sources:
  for +y:U32
  for +threshold:U32
  for +enabled:Bool
  for +minimum:U32
  for +height:U32
  for below:{S.signed_ge(y,threshold) == False{} : Bool}
  {S.source_y(y,S.Column{S.From{threshold},enabled,minimum,height}) == False{} : Bool}

law unknown_column_cannot_supply_a_source:
  for position:C.Position
  {S.source(position,None{}) == False{} : Bool}

# Catalog Faces already apply canOcclude && useShapeForLightOcclusion.
# This statement fixes source-to-target direction and both effective faces.
law source_blocking_uses_opacity_or_upper_down_lower_up_union:
  for +catalog:R.Catalog
  for +above:U32
  for above_emission:U32
  for above_dampening:U32
  for +below:U32
  for below_emission:U32
  for +below_dampening:U32
  {S.blocks_source(~R.Catalog,~R.occludes,catalog,
      B.Descriptor{above,above_emission,above_dampening},
      B.Descriptor{below,below_emission,below_dampening}) ==
    (U32.is_gt(below_dampening,0) ||
      R.conservative(R.occlusion_faces(catalog,R.state_face(catalog,above,B.Down{}),
        R.state_face(catalog,below,B.Up{})))) : Bool}

law positive_target_opacity_blocks_column_source:
  for +catalog:R.Catalog
  for +above:B.Descriptor
  for +below:B.Descriptor
  for opaque:{U32.is_gt(B.dampening(below),0) == True{} : Bool}
  {S.blocks_source(~R.Catalog,~R.occludes,catalog,above,below) == True{} : Bool}

law transparent_open_edge_preserves_column_source:
  for +catalog:R.Catalog
  for +above:B.Descriptor
  for +below:B.Descriptor
  for transparent:{U32.is_gt(B.dampening(below),0) == False{} : Bool}
  for open:{R.occludes(catalog,above,below,B.Down{}) == False{} : Bool}
  {S.blocks_source(~R.Catalog,~R.occludes,catalog,above,below) == False{} : Bool}

law unknown_column_publication_preserves_complete_state:
  for state:S.State
  for +position:C.Position
  for physical:B.Descriptor
  {S.publish_found(state,position,physical,None{}) ==
    (state,Fail{S.MissingColumn{position}}) : S.State & Result<&2,&2,S.Error,Unit>}

law rejected_descriptor_preserves_complete_state:
  for state:S.State
  for position:C.Position
  for +physical:B.Descriptor
  for invalid:{B.descriptor_valid(physical) == False{} : Bool}
  {S.publish(state,position,physical) == (state,Fail{S.InvalidDescriptor{}}) :
    S.State & Result<&2,&2,S.Error,Unit>}

law missing_physical_cell_preserves_complete_state:
  for state:S.State
  for +position:C.Position
  {S.resource_found(state,position,None{}) == (state,Fail{S.MissingCell{position}}) :
    S.State & Result<&2,&2,S.Error,Unit>}

law zero_budget_preserves_complete_state:
  for catalog:R.Catalog
  for state:S.State
  {owner_after(S.advance(~R.Catalog,~R.occludes,catalog,0n,state)) == state : S.State}

law settled_field_has_no_work_for_any_budget:
  for catalog:R.Catalog
  for cells:Map<&2,Maybe<&2,B.Cell>>
  for columns:Map<&2,Maybe<&2,S.Column>>
  for budget:Nat
  {S.advance(~R.Catalog,~R.occludes,catalog,budget,
      S.State{B.State{cells,[],[],MTip{},0n},columns}) ==
    (S.State{B.State{cells,[],[],MTip{},0n},columns},B.Stable{}) : S.State & B.Status}

law new_field_distinguishes_unknown_from_dark:
  for position:C.Position
  {S.sample(S.new(),position) == (S.new(),None{}) : S.State & Maybe<&2,U32>}

law missing_physical_read_preserves_unknown_and_owned_field:
  for old:Map<&2,Maybe<&2,B.Cell>>
  for cells:Map<&2,Maybe<&2,B.Cell>>
  for front:List<&2,C.Position>
  for back:List<&2,C.Position>
  for queued:Set()
  for pending:Nat
  for columns:Map<&2,Maybe<&2,S.Column>>
  {S.physical_read(S.State{B.State{old,front,back,queued,pending},columns},(cells,None{})) ==
    (S.State{B.State{cells,front,back,queued,pending},columns},None{}) :
    S.State & Maybe<&2,B.Descriptor>}

law unknown_sample_preserves_complete_sky_state:
  for field:B.State
  for +columns:Map<&2,Maybe<&2,S.Column>>
  for +position:C.Position
  for unknown:{B.sample(field,position) == (field,None{}) : B.State & Maybe<&2,U32>}
  {S.sample(S.State{field,columns},position) == (S.State{field,columns},None{}) :
    S.State & Maybe<&2,U32>}

# No direction branch may replace the shared saturating transfer. This fixes
# the >=1 edge cost over arbitrary levels/dampening, including DOWN.
law every_non_source_edge_uses_shared_attenuating_transfer:
  for +closed:Bool
  for source:B.Descriptor
  for +target:B.Descriptor
  for direction:B.Direction
  for +level:U32
  {B.contribution(~Bool,~edge,closed,S.descriptor(target,False{}),direction,
      Some{B.Cell{S.descriptor(source,False{}),level}}) ==
    B.transfer(closed,level,B.dampening(target)) : U32}

law registry_non_source_edge_uses_shared_attenuating_transfer:
  for +catalog:R.Catalog
  for +source:B.Descriptor
  for +target:B.Descriptor
  for +direction:B.Direction
  for +level:U32
  {B.contribution(~R.Catalog,~R.occludes,catalog,S.descriptor(target,False{}),direction,
      Some{B.Cell{S.descriptor(source,False{}),level}}) ==
    B.transfer(R.occludes(catalog,source,target,direction),level,B.dampening(target)) : U32}

# This binds every sky advance to the complete production relaxation result.
# In particular sky cannot introduce a different DOWN propagation branch.
law advance_retains_columns_and_uses_complete_shared_field_result:
  for +catalog:R.Catalog
  for +budget:Nat
  for field:B.State
  for advanced:B.State
  for +columns:Map<&2,Maybe<&2,S.Column>>
  for +status:B.Status
  for result:{B.advance(~R.Catalog,~R.occludes,catalog,budget,field) == (advanced,status) : B.State & B.Status}
  {S.advance(~R.Catalog,~R.occludes,catalog,budget,S.State{field,columns}) ==
    (S.State{advanced,columns},status) : S.State & B.Status}

law registry_closed_edge_prevents_all_sky_transfer:
  for +catalog:R.Catalog
  for +source:B.Descriptor
  for +target:B.Descriptor
  for +direction:B.Direction
  for +level:U32
  for closed:{R.occludes(catalog,source,target,direction) == True{} : Bool}
  {B.contribution(~R.Catalog,~R.occludes,catalog,S.descriptor(target,False{}),direction,
    Some{B.Cell{S.descriptor(source,False{}),level}}) == 0 : U32}

law open_level_fifteen_loses_one_in_every_direction:
  for source:B.Descriptor
  for target:U32
  for target_emission:U32
  for direction:B.Direction
  {B.contribution(~Bool,~edge,False{},
      S.descriptor(B.Descriptor{target,target_emission,0},False{}),direction,
      Some{B.Cell{S.descriptor(source,False{}),15}}) == 14 : U32}

law closed_edge_prevents_all_sky_transfer:
  for source:B.Descriptor
  for target:B.Descriptor
  for direction:B.Direction
  for level:U32
  {B.contribution(~Bool,~edge,True{},S.descriptor(target,False{}),direction,
    Some{B.Cell{S.descriptor(source,False{}),level}}) == 0 : U32}

law unknown_neighbor_cannot_supply_sky_light:
  for closed:Bool
  for target:B.Descriptor
  for direction:B.Direction
  {B.contribution(~Bool,~edge,closed,S.descriptor(target,False{}),direction,None{}) == 0 : U32}
