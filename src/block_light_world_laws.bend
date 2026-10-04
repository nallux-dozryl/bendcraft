import Base
import ./block_light_world.bend as W
import ./block_light.bend as B
import ./core.bend as C
import ./schedule.bend as Q

def unavailable(context:Unit,state:U32) -> Maybe<&2,B.Descriptor>: None{}
def enabled(context:Unit,position:C.Position) -> Bool: True{}
def open(context:Unit,from:B.Descriptor,to:B.Descriptor,direction:B.Direction) -> Bool: False{}
def retained(-A:Type,result:W.State & A) -> W.State:
  (state,value) = result
  state

law zero_load_budget_preserves_both_actual_owners:
  for state:W.State
  {W.load_resume(~Unit,~unavailable,~enabled,Unit{},0n,state) ==
    (state,Done{Unit{}}) : W.State & Result<&2,&2,W.Error,Unit>}

law bootstrap_refuses_actual_world_mutations:
  for world:C.World
  for light:B.State
  for +cursor:W.Cursor
  for mutation:C.Mutation
  {W.apply(~Unit,~unavailable,~enabled,Unit{},W.State{world,light,Some{cursor}},mutation) ==
    (W.State{world,light,Some{cursor}},Fail{W.LoadingInProgress{}}) :
    W.State & Result<&2,&2,W.Error,Unit>}

law bootstrap_cannot_advance_simulation_clock:
  for world:C.World
  for light:B.State
  for +cursor:W.Cursor
  {W.step(~Unit,~unavailable,~enabled,Unit{},W.State{world,light,Some{cursor}}) ==
    (W.State{world,light,Some{cursor}},Fail{W.LoadingInProgress{}}) :
    W.State & Result<&2,&2,W.Error,Unit>}

law bootstrap_refuses_frame_sampling_without_touching_world:
  for world:C.World
  for light:B.State
  for +cursor:W.Cursor
  for positions:List<&2,C.Position>
  {W.sample_batch(positions,W.State{world,light,Some{cursor}}) ==
    (W.State{world,light,Some{cursor}},Fail{W.LoadingInProgress{}}) :
    W.State & Result<&2,&2,W.Error,W.FrameSamples>}

law failed_preflight_preserves_both_actual_owners:
  for state:W.State
  for +error:W.Error
  {W.apply_checked(state,Fail{error}) == (state,Fail{error}) :
    W.State & Result<&2,&2,W.Error,Unit>}

law pending_field_cannot_enter_a_frame:
  for world:C.World
  for cells:Map<&2,Maybe<&2,B.Cell>>
  for front:List<&2,C.Position>
  for back:List<&2,C.Position>
  for queued:Set()
  for +remaining:Nat
  for positions:List<&2,C.Position>
  {W.sample_batch(positions,W.State{world,B.State{cells,front,back,queued,1n+remaining},None{}}) ==
    (W.State{world,B.State{cells,front,back,queued,1n+remaining},None{}},Fail{W.LightPending{1n+remaining}}) :
    W.State & Result<&2,&2,W.Error,W.FrameSamples>}

law daylight_edit_preserves_complete_block_light_owner:
  for world:C.World
  for light:B.State
  for value:Bool
  {W.apply(~Unit,~unavailable,~enabled,Unit{},W.State{world,light,None{}},C.DaylightSet{value}) ==
    (W.State{C.set_daylight(world,value),light,None{}},Done{Unit{}}) :
    W.State & Result<&2,&2,W.Error,Unit>}

law unknown_world_and_field_sample_remain_unknown:
  for +position:C.Position
  for key:String
  {W.observed(position,Fail{C.MissingSection{key}},None{}) ==
    Done{W.Observation{position,None{},None{}}} : Result<&2,&2,W.Error,W.Observation>}

law field_without_world_cell_is_rejected_as_residency_mismatch:
  for +position:C.Position
  for key:String
  for level:U32
  {W.observed(position,Fail{C.MissingSection{key}},Some{level}) ==
    Fail{W.ResidencyMismatch{position}} : Result<&2,&2,W.Error,W.Observation>}
