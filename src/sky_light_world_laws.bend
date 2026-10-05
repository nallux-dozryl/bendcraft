import Base
import ./sky_light_world.bend as W
import ./sky_light.bend as S
import ./block_light.bend as B
import ./block_light_world.bend as BW
import ./block_light_registry.bend as R
import ./core.bend as C
import ./section_map.bend as M
import ./schedule.bend as Q

# The actual sidecar borrows Core; it owns only light facts, source work and
# revision admission. Provider fixtures below are used only in branches whose
# exact results do not depend on invoking those providers.
def unavailable_bounds(catalog:R.Catalog,dimension:String) -> Maybe<&2,W.Bounds>: None{}
def unknown_section(catalog:R.Catalog,position:C.Position) -> W.SectionPolicy: W.Unknown{}
def enabled(catalog:R.Catalog,position:C.Position) -> Bool: True{}
def stored_field(light:S.State) -> B.State:
  S.State{field,columns} = light
  field
def resulting_field(result:W.State & Result<&2,&2,W.Error,Unit>) -> B.State:
  (W.State{light,phase,chunks,domains,repairs,revision},status) = result
  stored_field(light)

law enumeration_returns_exact_affine_section_owner:
  for sections:M.Sections
  exs keys:List<&2,String>
  {BW.section_keys(sections) == (sections,keys) : M.Sections & List<&2,String>}

law begin_returns_complete_original_core_and_fresh_sidecar:
  for world:C.World
  exs keys:List<&2,String>
  {W.begin(world) ==
    (world,W.State{S.new(),W.Enumerate{keys},[],[],[],None{}}) : C.World & W.State}

law zero_load_budget_preserves_both_complete_owners:
  for catalog:R.Catalog
  for world:C.World
  for state:W.State
  {W.load_resume(~R.Catalog,~R.properties,~unavailable_bounds,~unknown_section,~enabled,~R.occludes,
    catalog,0n,world,state) == (world,(state,Done{Unit{}})) :
    C.World & (W.State & Result<&2,&2,W.Error,Unit>)}

law ready_load_preserves_both_owners_for_any_budget:
  for catalog:R.Catalog
  for budget:Nat
  for world:C.World
  for light:S.State
  for chunks:List<&2,W.Chunk>
  for domains:List<&2,C.Position>
  for repairs:List<&2,C.Position>
  for revision:Maybe<&2,Nat>
  {W.load_resume(~R.Catalog,~R.properties,~unavailable_bounds,~unknown_section,~enabled,~R.occludes,
    catalog,budget,world,W.State{light,W.Ready{},chunks,domains,repairs,revision}) ==
    (world,(W.State{light,W.Ready{},chunks,domains,repairs,revision},Done{Unit{}})) :
    C.World & (W.State & Result<&2,&2,W.Error,Unit>)}

law bootstrap_advance_preserves_complete_sidecar:
  for catalog:R.Catalog
  for budget:Nat
  for light:S.State
  for +phase:W.Phase
  for chunks:List<&2,W.Chunk>
  for domains:List<&2,C.Position>
  for repairs:List<&2,C.Position>
  for revision:Maybe<&2,Nat>
  for not_ready:{phase != W.Ready{} : W.Phase}
  {W.advance(~R.Catalog,~R.occludes,catalog,budget,W.State{light,phase,chunks,domains,repairs,revision}) ==
    (W.State{light,phase,chunks,domains,repairs,revision},W.Bootstrap{}) : W.State & W.Progress}

law bootstrap_sampling_preserves_both_complete_owners:
  for positions:List<&2,C.Position>
  for world:C.World
  for light:S.State
  for +phase:W.Phase
  for chunks:List<&2,W.Chunk>
  for domains:List<&2,C.Position>
  for repairs:List<&2,C.Position>
  for revision:Maybe<&2,Nat>
  for not_ready:{phase != W.Ready{} : W.Phase}
  {W.sample_batch(positions,world,W.State{light,phase,chunks,domains,repairs,revision}) ==
    (world,(W.State{light,phase,chunks,domains,repairs,revision},Fail{W.LoadingInProgress{}})) :
    C.World & (W.State & Result<&2,&2,W.Error,W.FrameSamples>)}

law bootstrap_refresh_preserves_both_complete_owners:
  for catalog:R.Catalog
  for position:C.Position
  for world:C.World
  for light:S.State
  for +phase:W.Phase
  for chunks:List<&2,W.Chunk>
  for domains:List<&2,C.Position>
  for repairs:List<&2,C.Position>
  for revision:Maybe<&2,Nat>
  for not_ready:{phase != W.Ready{} : W.Phase}
  {W.refresh_block(~R.Catalog,~R.properties,catalog,position,world,
    W.State{light,phase,chunks,domains,repairs,revision}) ==
    (world,(W.State{light,phase,chunks,domains,repairs,revision},Fail{W.LoadingInProgress{}})) :
    C.World & (W.State & Result<&2,&2,W.Error,Unit>)}

law missing_revision_sampling_preserves_both_complete_owners:
  for positions:List<&2,C.Position>
  for world:C.World
  for light:S.State
  for chunks:List<&2,W.Chunk>
  for domains:List<&2,C.Position>
  for repairs:List<&2,C.Position>
  {W.sample_batch(positions,world,W.State{light,W.Ready{},chunks,domains,repairs,None{}}) ==
    (world,(W.State{light,W.Ready{},chunks,domains,repairs,None{}},Fail{W.StaleRevision{}})) :
    C.World & (W.State & Result<&2,&2,W.Error,W.FrameSamples>)}

law stale_revision_sampling_preserves_both_complete_owners:
  for positions:List<&2,C.Position>
  for tick:Nat
  for time:Nat
  for paused:Bool
  for daylight:Bool
  for +current:Nat
  for count:U32
  for sections:M.Sections
  for pending:List<&2,Q.Pending<C.Mutation>>
  for events:List<&2,C.CoreEvent>
  for light:S.State
  for chunks:List<&2,W.Chunk>
  for domains:List<&2,C.Position>
  for repairs:List<&2,C.Position>
  for +saved:Nat
  for stale:{Nat.is_eq(saved,current) == False{} : Bool}
  {W.sample_batch(positions,C.World{tick,time,paused,daylight,current,count,sections,pending,events},
      W.State{light,W.Ready{},chunks,domains,repairs,Some{saved}}) ==
    (C.World{tick,time,paused,daylight,current,count,sections,pending,events},
      (W.State{light,W.Ready{},chunks,domains,repairs,Some{saved}},Fail{W.StaleRevision{}})) :
    C.World & (W.State & Result<&2,&2,W.Error,W.FrameSamples>)}

law pending_light_sampling_preserves_both_complete_owners:
  for positions:List<&2,C.Position>
  for tick:Nat
  for time:Nat
  for paused:Bool
  for daylight:Bool
  for +current:Nat
  for count:U32
  for sections:M.Sections
  for pending:List<&2,Q.Pending<C.Mutation>>
  for events:List<&2,C.CoreEvent>
  for cells:Map<&2,Maybe<&2,B.Cell>>
  for front:List<&2,C.Position>
  for back:List<&2,C.Position>
  for queued:Set()
  for +remaining:Nat
  for columns:Map<&2,Maybe<&2,S.Column>>
  for chunks:List<&2,W.Chunk>
  for domains:List<&2,C.Position>
  for repairs:List<&2,C.Position>
  for +saved:Nat
  for admitted:{Nat.is_eq(saved,current) == True{} : Bool}
  {W.sample_batch(positions,C.World{tick,time,paused,daylight,current,count,sections,pending,events},
      W.State{S.State{B.State{cells,front,back,queued,1n+remaining},columns},W.Ready{},chunks,domains,repairs,Some{saved}}) ==
    (C.World{tick,time,paused,daylight,current,count,sections,pending,events},
      (W.State{S.State{B.State{cells,front,back,queued,1n+remaining},columns},W.Ready{},chunks,domains,repairs,Some{saved}},
        Fail{W.LightPending{1n+remaining}})) : C.World & (W.State & Result<&2,&2,W.Error,W.FrameSamples>)}

# The read service returns the sole Core owner. This law preserves that returned
# owner and the entire prior sky state; it does not assume arbitrary reads leave
# Core unchanged.
law core_read_failure_refresh_preserves_entire_sidecar:
  for catalog:R.Catalog
  for +position:C.Position
  for world:C.World
  for returned:C.World
  for light:S.State
  for chunks:List<&2,W.Chunk>
  for domains:List<&2,C.Position>
  for repairs:List<&2,C.Position>
  for revision:Maybe<&2,Nat>
  for +error:C.Error
  for failed:{C.read_block(world,position) == (returned,Fail{error}) : C.World & Result<&2,&2,C.Error,U32>}
  {W.refresh_block(~R.Catalog,~R.properties,catalog,position,world,
      W.State{light,W.Ready{},chunks,domains,repairs,revision}) ==
    (returned,(W.State{light,W.Ready{},chunks,domains,repairs,revision},Fail{W.CoreFailure{error}})) :
    C.World & (W.State & Result<&2,&2,W.Error,Unit>)}

law descriptor_failure_refresh_preserves_both_complete_owners:
  for world:C.World
  for state:W.State
  for position:C.Position
  for +error:W.Error
  for chunk:Maybe<&2,W.Chunk>
  {W.refresh_found(world,state,position,Fail{error},chunk) == (world,(state,Fail{error})) :
    C.World & (W.State & Result<&2,&2,W.Error,Unit>)}

law missing_chunk_refresh_preserves_both_complete_owners:
  for world:C.World
  for state:W.State
  for +position:C.Position
  for descriptor:B.Descriptor
  {W.refresh_found(world,state,position,Done{descriptor},None{}) ==
    (world,(state,Fail{W.MissingCell{position}})) : C.World & (W.State & Result<&2,&2,W.Error,Unit>)}

law unknown_section_cannot_fabricate_empty_loaded_cells:
  for world:C.World
  for light:S.State
  for +position:C.Position
  for +todo:List<&2,C.Position>
  for chunks:List<&2,W.Chunk>
  for domains:List<&2,C.Position>
  for repairs:List<&2,C.Position>
  for revision:Maybe<&2,Nat>
  for chunk:Maybe<&2,W.Chunk>
  {W.load_empty(world,W.State{light,W.Loading{position <> todo,None{}},chunks,domains,repairs,revision},
    position,todo,W.Unknown{},chunk) ==
    (world,(W.State{light,W.Loading{position <> todo,None{}},chunks,domains,repairs,revision},
      Fail{W.UnknownSection{position}})) : C.World & (W.State & Result<&2,&2,W.Error,Unit>)}

law missing_scan_cell_preserves_complete_sidecar:
  for catalog:R.Catalog
  for light:S.State
  for +todo:List<&2,C.Position>
  for +fresh:Bool
  for +position:C.Position
  for +minimum:U32
  for +height:U32
  for +remaining:Nat
  for +above:B.Descriptor
  for +enabled:Bool
  for chunks:List<&2,W.Chunk>
  for domains:List<&2,C.Position>
  for repairs:List<&2,C.Position>
  for revision:Maybe<&2,Nat>
  {W.scan_read(~R.Catalog,~R.occludes,catalog,
      W.State{light,W.Sources{todo,Some{W.Scan{position,minimum,height,remaining,above,enabled}},fresh},chunks,domains,repairs,revision},
      todo,fresh,W.Scan{position,minimum,height,remaining,above,enabled},None{}) ==
    (W.State{light,W.Sources{todo,Some{W.Scan{position,minimum,height,remaining,above,enabled}},fresh},chunks,domains,repairs,revision},
      Fail{W.MissingCell{position}}) : W.State & Result<&2,&2,W.Error,Unit>}

# A discovered source threshold updates only source facts. The complete queued
# field, including every stored level, remains owned and unchanged until repair.
law blocked_source_scan_retains_complete_stored_light_field:
  for field:B.State
  for columns:Map<&2,Maybe<&2,S.Column>>
  for phase:W.Phase
  for chunks:List<&2,W.Chunk>
  for domains:List<&2,C.Position>
  for repairs:List<&2,C.Position>
  for revision:Maybe<&2,Nat>
  for todo:List<&2,C.Position>
  for fresh:Bool
  for +dimension:String
  for +x:U32
  for +y:U32
  for +z:U32
  for minimum:U32
  for height:U32
  for remaining:Nat
  for above:B.Descriptor
  for enabled:Bool
  for below:B.Descriptor
  {resulting_field(W.scan_blocked(W.State{S.State{field,columns},phase,chunks,domains,repairs,revision},todo,fresh,
    W.Scan{C.Position{dimension,x,y,z},minimum,height,remaining,above,enabled},below,True{})) == field : B.State}

law enabled_refresh_schedules_column_repair_and_invalidates_revision:
  for world:C.World
  for ignored:S.State
  for light:S.State
  for phase:W.Phase
  for chunks:List<&2,W.Chunk>
  for domains:List<&2,C.Position>
  for repairs:List<&2,C.Position>
  for revision:Maybe<&2,Nat>
  for +top:C.Position
  {W.refresh_top(world,W.State{ignored,phase,chunks,domains,repairs,revision},top,True{},(light,Done{Unit{}})) ==
    (world,(W.State{light,W.Sources{[top],None{},False{}},chunks,domains,[top],None{}},Done{Unit{}})) :
    C.World & (W.State & Result<&2,&2,W.Error,Unit>)}

law deferred_source_completion_republishes_before_ready:
  for catalog:R.Catalog
  for world:C.World
  for light:S.State
  for chunks:List<&2,W.Chunk>
  for domains:List<&2,C.Position>
  for +repairs:List<&2,C.Position>
  for revision:Maybe<&2,Nat>
  {W.load_resume(~R.Catalog,~R.properties,~unavailable_bounds,~unknown_section,~enabled,~R.occludes,catalog,1n,world,
    W.State{light,W.Sources{[],None{},False{}},chunks,domains,repairs,revision}) ==
    (world,(W.State{light,W.Republishing{repairs,None{}},chunks,domains,repairs,revision},Done{Unit{}})) :
    C.World & (W.State & Result<&2,&2,W.Error,Unit>)}

law completed_republication_returns_core_and_accepts_current_revision:
  for tick:Nat
  for time:Nat
  for paused:Bool
  for daylight:Bool
  for +current:Nat
  for count:U32
  for sections:M.Sections
  for pending:List<&2,Q.Pending<C.Mutation>>
  for events:List<&2,C.CoreEvent>
  for light:S.State
  for chunks:List<&2,W.Chunk>
  for domains:List<&2,C.Position>
  for repairs:List<&2,C.Position>
  for revision:Maybe<&2,Nat>
  {W.republish_unit(C.World{tick,time,paused,daylight,current,count,sections,pending,events},
      W.State{light,W.Republishing{[],None{}},chunks,domains,repairs,revision}) ==
    (C.World{tick,time,paused,daylight,current,count,sections,pending,events},
      (W.State{light,W.Ready{},chunks,domains,[],Some{current}},Done{Unit{}})) :
    C.World & (W.State & Result<&2,&2,W.Error,Unit>)}

law absent_core_section_remains_unknown_in_observation:
  for position:C.Position
  for key:String
  for level:Maybe<&2,U32>
  {W.observed(position,Fail{C.MissingSection{key}},level) ==
    Done{W.Observation{position,None{},None{}}} : Result<&2,&2,W.Error,W.Observation>}

law known_core_cell_without_sky_cell_is_residency_failure:
  for +position:C.Position
  for id:U32
  {W.observed(position,Done{id},None{}) == Fail{W.ResidencyMismatch{position}} :
    Result<&2,&2,W.Error,W.Observation>}

law refused_core_mutation_does_not_publish_sky_work:
  for catalog:R.Catalog
  for mutation:C.Mutation
  for state:W.State
  for world:C.World
  for +error:C.Error
  {W.accept_result(~R.Catalog,~R.properties,catalog,mutation,state,(world,Fail{error})) ==
    (world,(state,Fail{W.CoreFailure{error}})) : C.World & (W.State & Result<&2,&2,W.Error,Unit>)}

law disabling_columns_retains_complete_stored_field:
  for positions:List<&2,C.Position>
  for field:B.State
  for columns:Map<&2,Maybe<&2,S.Column>>
  {stored_field(W.columns_enabled(positions,False{},S.State{field,columns})) == field : B.State}

law disabling_chunk_retains_complete_stored_field:
  for field:B.State
  for columns:Map<&2,Maybe<&2,S.Column>>
  for phase:W.Phase
  for chunks:List<&2,W.Chunk>
  for domains:List<&2,C.Position>
  for repairs:List<&2,C.Position>
  for revision:Maybe<&2,Nat>
  for position:C.Position
  for found:Maybe<&2,W.Chunk>
  {resulting_field(W.enabled_chunk(W.State{S.State{field,columns},phase,chunks,domains,repairs,revision},
    position,False{},found)) == field : B.State}

law actual_disabling_retains_complete_stored_field:
  for field:B.State
  for columns:Map<&2,Maybe<&2,S.Column>>
  for phase:W.Phase
  for +chunks:List<&2,W.Chunk>
  for domains:List<&2,C.Position>
  for repairs:List<&2,C.Position>
  for revision:Maybe<&2,Nat>
  for +position:C.Position
  {resulting_field(W.set_enabled(position,False{},
    W.State{S.State{field,columns},phase,chunks,domains,repairs,revision})) == field : B.State}

law source_propagation_chunk_starts_injection_with_retained_light_owner:
  for light:S.State
  for phase:W.Phase
  for chunks:List<&2,W.Chunk>
  for domains:List<&2,C.Position>
  for repairs:List<&2,C.Position>
  for revision:Maybe<&2,Nat>
  for position:C.Position
  for +chunk:W.Chunk
  {W.propagate_chunk(W.State{light,phase,chunks,domains,repairs,revision},position,Some{chunk}) ==
    (W.State{light,W.Injecting{W.chunk_columns(chunk),None{}},chunks,domains,[],None{}},Done{Unit{}}) :
    W.State & Result<&2,&2,W.Error,Unit>}
