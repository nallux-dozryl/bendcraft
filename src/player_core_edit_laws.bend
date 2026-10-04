import Base
import ./core.bend as C
import ./schedule.bend as Q
import ./player_core_edit.bend as Edit
import ./section_map.bend as Map

law unauthorized_edit_rollback:
  for world:C.World
  for +cap:C.Capability
  for position:C.Position
  for state:U32
  for expected:Nat
  for sequence:Nat
  for maybuild:Bool
  for denied:{Edit.player_peer(cap) == None{} : Maybe<&2,U32>}
  {Edit.edit(world,cap,position,state,expected,sequence,maybuild) ==
    (world,Fail{Edit.PermissionDenied{}}) : C.World & Result<&2,&2,Edit.Error,Unit>}

law observer_edit_rollback:
  for world:C.World
  for position:C.Position
  for state:U32
  for expected:Nat
  for sequence:Nat
  for maybuild:Bool
  {Edit.edit(world,C.Observer{},position,state,expected,sequence,maybuild) ==
    (world,Fail{Edit.PermissionDenied{}}) : C.World & Result<&2,&2,Edit.Error,Unit>}

law invalid_player_edit_rollback:
  for world:C.World
  for position:C.Position
  for state:U32
  for expected:Nat
  for sequence:Nat
  for maybuild:Bool
  {Edit.edit(world,C.Player{0},position,state,expected,sequence,maybuild) ==
    (world,Fail{Edit.PermissionDenied{}}) : C.World & Result<&2,&2,Edit.Error,Unit>}

law disabled_build_edit_rollback:
  for world:C.World
  for cap:C.Capability
  for position:C.Position
  for state:U32
  for expected:Nat
  for sequence:Nat
  {Edit.edit(world,cap,position,state,expected,sequence,False{}) ==
    (world,Fail{Edit.PermissionDenied{}}) : C.World & Result<&2,&2,Edit.Error,Unit>}

# The actual execution interface also returns the identical complete owners
# when building is disabled, independently of authority and record validity.
law invalid_sequence_gate_rollback:
  for world:C.World
  for stamp:Q.Stamp
  for position:C.Position
  for state:U32
  for count:U32
  for expected:Nat
  for revision:Nat
  for matching:Bool
  {Edit.current(world,stamp,position,state,count,expected,revision,False{},matching) ==
    (world,Fail{Edit.InvalidSequence{}}) : C.World & Result<&2,&2,Edit.Error,Unit>}

law stale_revision_gate_rollback:
  for world:C.World
  for stamp:Q.Stamp
  for position:C.Position
  for state:U32
  for count:U32
  for +expected:Nat
  for +revision:Nat
  {Edit.current(world,stamp,position,state,count,expected,revision,True{},False{}) ==
    (world,Fail{Edit.StaleRevision{expected,revision}}) : C.World & Result<&2,&2,Edit.Error,Unit>}

law invalid_mutation_gate_rollback:
  for world:C.World
  for stamp:Q.Stamp
  for position:C.Position
  for state:U32
  for +cause:C.Error
  {Edit.validated(world,stamp,position,state,Fail{cause}) ==
    (world,Fail{Edit.CoreError{cause}}) : C.World & Result<&2,&2,Edit.Error,Unit>}

law missing_read_gate_rollback:
  for world:C.World
  for stamp:Q.Stamp
  for position:C.Position
  for state:U32
  for +cause:C.Error
  {Edit.present(stamp,position,state,(world,Fail{cause})) ==
    (world,Fail{Edit.CoreError{cause}}) : C.World & Result<&2,&2,Edit.Error,Unit>}

law failed_write_gate_rollback:
  for world:C.World
  for stamp:Q.Stamp
  for +cause:C.Error
  {Edit.finished(stamp,(world,Fail{cause})) ==
    (world,Fail{Edit.CoreError{cause}}) : C.World & Result<&2,&2,Edit.Error,Unit>}

# A complete metadata/event observation of the returned production world.
# Sections are consumed without cloning: these success laws concern the actual
# commit receipt, not a theorem about section-map/Array contents after writing.
type Snapshot is Data:
  Snapshot{tick:Nat,time:Nat,paused:Bool,daylight:Bool,revision:Nat,count:U32,
    pending:List<&2,Q.Pending<C.Mutation>>,events:List<&2,C.CoreEvent>,status:Result<&2,&2,Edit.Error,Unit>}

def snapshot(result:C.World & Result<&2,&2,Edit.Error,Unit>) -> Snapshot:
  (world,status) = result
  C.World{tick,time,paused,daylight,revision,count,sections,pending,events} = world
  Snapshot{tick,time,paused,daylight,revision,count,pending,events,status}

law successful_commit_receipt:
  for +tick:Nat
  for +time:Nat
  for +paused:Bool
  for +daylight:Bool
  for +revision:Nat
  for +count:U32
  for sections:Map.Sections
  for +pending:List<&2,Q.Pending<C.Mutation>>
  for +events:List<&2,C.CoreEvent>
  for +stamp:Q.Stamp
  {snapshot(Edit.finished(stamp,
    (C.World{tick,time,paused,daylight,revision,count,sections,pending,events},Done{Unit{}}))) ==
    Snapshot{tick,time,paused,daylight,1n+revision,count,pending,
      C.Applied{stamp,1n+revision} <> C.trim_events(events,1023n),Done{Unit{}}} : Snapshot}

# The premises are facts about the actual Core validator/read/write results,
# not axioms or a second world implementation. They describe a successful
# loaded-section edit. The observation checks every metadata field and the
# complete bounded event stream; the stamp is taken from the input tick, peer
# and private sequence even though read/write thread distinct affine owners.
law successful_edit_receipt:
  for +tick:Nat
  for +time:Nat
  for +paused:Bool
  for +daylight:Bool
  for +revision:Nat
  for +count:U32
  for sections:Map.Sections
  for +pending:List<&2,Q.Pending<C.Mutation>>
  for +events:List<&2,C.CoreEvent>
  for +position:C.Position
  for +state:U32
  for +expected:Nat
  for +sequence:Nat
  for +peer:U32
  for read_world:C.World
  for old:U32
  for +written_tick:Nat
  for +written_time:Nat
  for +written_paused:Bool
  for +written_daylight:Bool
  for +written_revision:Nat
  for +written_count:U32
  for written_sections:Map.Sections
  for +written_pending:List<&2,Q.Pending<C.Mutation>>
  for +written_events:List<&2,C.CoreEvent>
  for permitted:{U32.is_gt(peer,0) == True{} : Bool}
  for positive:{Nat.is_gt(sequence,0n) == True{} : Bool}
  for matching:{Nat.is_eq(expected,revision) == True{} : Bool}
  for valid:{C.validate(C.BlockSet{position,state},count) == Done{Unit{}} : Result<&2,&2,C.Error,Unit>}
  for loaded:{C.read_block(C.World{tick,time,paused,daylight,revision,count,sections,pending,events},position) ==
    (read_world,Done{old}) : C.World & Result<&2,&2,C.Error,U32>}
  for written:{C.write_block(read_world,position,state) ==
    (C.World{written_tick,written_time,written_paused,written_daylight,written_revision,written_count,written_sections,written_pending,written_events},Done{Unit{}}) : C.World & Result<&2,&2,C.Error,Unit>}
  {snapshot(Edit.edit(C.World{tick,time,paused,daylight,revision,count,sections,pending,events},
    C.Player{peer},position,state,expected,sequence,True{})) ==
    Snapshot{written_tick,written_time,written_paused,written_daylight,1n+written_revision,written_count,written_pending,
      C.Applied{Q.Stamp{tick,peer,sequence},1n+written_revision} <> C.trim_events(written_events,1023n),Done{Unit{}}} : Snapshot}
