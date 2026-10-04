import Base
import ./core.bend as C
import ./schedule.bend as Q
import ./player_core_edit.bend as Edit
import ./section_map.bend as Map
import ./player_core_edit_laws.bend as Laws

def Laws.unauthorized_edit_rollback(world,cap,position,state,expected,sequence,maybuild,denied):
  match maybuild:
    case False{}: {==}
    case True{}:
      %Equal.sym(Maybe<&2,U32>,Edit.player_peer(cap),None{},denied) :
        {Edit.checked(world,position,state,expected,sequence,True{},_) ==
          (world,Fail{Edit.PermissionDenied{}}) : C.World & Result<&2,&2,Edit.Error,Unit>}
      {==}

def Laws.observer_edit_rollback(world,position,state,expected,sequence,maybuild):
  match maybuild:
    case False{}: {==}
    case True{}: {==}

def Laws.invalid_player_edit_rollback(world,position,state,expected,sequence,maybuild):
  match maybuild:
    case False{}: {==}
    case True{}: {==}

def Laws.disabled_build_edit_rollback(world,cap,position,state,expected,sequence):
  {==}

def Laws.invalid_sequence_gate_rollback(world,stamp,position,state,count,expected,revision,matching):
  {==}

def Laws.stale_revision_gate_rollback(world,stamp,position,state,count,expected,revision):
  {==}

def Laws.invalid_mutation_gate_rollback(world,stamp,position,state,cause):
  {==}

def Laws.missing_read_gate_rollback(world,stamp,position,state,cause):
  {==}

def Laws.failed_write_gate_rollback(world,stamp,cause):
  {==}

def Laws.successful_commit_receipt(tick,time,paused,daylight,revision,count,sections,pending,events,stamp):
  {==}

def current_succeeds(-world:C.World,+stamp:Q.Stamp,+position:C.Position,+state:U32,+count:U32,expected:Nat,revision:Nat,
    -read_world:C.World,-written_world:C.World,old:U32,
    valid:{C.validate(C.BlockSet{position,state},count) == Done{Unit{}} : Result<&2,&2,C.Error,Unit>},
    loaded:{C.read_block(world,position) == (read_world,Done{old}) : C.World & Result<&2,&2,C.Error,U32>},
    written:{C.write_block(read_world,position,state) == (written_world,Done{Unit{}}) : C.World & Result<&2,&2,C.Error,Unit>}) ->
    {Edit.current(world,stamp,position,state,count,expected,revision,True{},True{}) ==
      (C.accepted(written_world,stamp),Done{Unit{}}) : C.World & Result<&2,&2,Edit.Error,Unit>}:
  %Equal.sym(Result<&2,&2,C.Error,Unit>,C.validate(C.BlockSet{position,state},count),Done{Unit{}},valid) :
    {Edit.validated(world,stamp,position,state,_) == (C.accepted(written_world,stamp),Done{Unit{}}) : C.World & Result<&2,&2,Edit.Error,Unit>}
  %Equal.sym(C.World & Result<&2,&2,C.Error,U32>,C.read_block(world,position),(read_world,Done{old}),loaded) :
    {Edit.present(stamp,position,state,_) == (C.accepted(written_world,stamp),Done{Unit{}}) : C.World & Result<&2,&2,Edit.Error,Unit>}
  %Equal.sym(C.World & Result<&2,&2,C.Error,Unit>,C.write_block(read_world,position,state),(written_world,Done{Unit{}}),written) :
    {Edit.finished(stamp,_) == (C.accepted(written_world,stamp),Done{Unit{}}) : C.World & Result<&2,&2,Edit.Error,Unit>}
  {==}

def player_succeeds(-world:C.World,+stamp:Q.Stamp,+position:C.Position,+state:U32,+count:U32,+expected:Nat,+revision:Nat,+sequence:Nat,
    -read_world:C.World,-written_world:C.World,old:U32,
    positive:{Nat.is_gt(sequence,0n) == True{} : Bool},matching:{Nat.is_eq(expected,revision) == True{} : Bool},
    valid:{C.validate(C.BlockSet{position,state},count) == Done{Unit{}} : Result<&2,&2,C.Error,Unit>},
    loaded:{C.read_block(world,position) == (read_world,Done{old}) : C.World & Result<&2,&2,C.Error,U32>},
    written:{C.write_block(read_world,position,state) == (written_world,Done{Unit{}}) : C.World & Result<&2,&2,C.Error,Unit>}) ->
    {Edit.current(world,stamp,position,state,count,expected,revision,Nat.is_gt(sequence,0n),Nat.is_eq(expected,revision)) ==
      (C.accepted(written_world,stamp),Done{Unit{}}) : C.World & Result<&2,&2,Edit.Error,Unit>}:
  %Equal.sym(Bool,Nat.is_gt(sequence,0n),True{},positive) :
    {Edit.current(world,stamp,position,state,count,expected,revision,_,Nat.is_eq(expected,revision)) == (C.accepted(written_world,stamp),Done{Unit{}}) : C.World & Result<&2,&2,Edit.Error,Unit>}
  %Equal.sym(Bool,Nat.is_eq(expected,revision),True{},matching) :
    {Edit.current(world,stamp,position,state,count,expected,revision,True{},_) == (C.accepted(written_world,stamp),Done{Unit{}}) : C.World & Result<&2,&2,Edit.Error,Unit>}
  current_succeeds(world,stamp,position,state,count,expected,revision,read_world,written_world,old,valid,loaded,written)

def Laws.successful_edit_receipt(tick,time,paused,daylight,revision,count,sections,pending,events,position,state,expected,sequence,peer,
    read_world,old,written_tick,written_time,written_paused,written_daylight,written_revision,written_count,written_sections,written_pending,written_events,
    permitted,positive,matching,valid,loaded,written):
  %Equal.sym(Bool,U32.is_gt(peer,0),True{},permitted) :
    {Laws.snapshot(Edit.checked(C.World{tick,time,paused,daylight,revision,count,sections,pending,events},position,state,expected,sequence,True{},
      Bool.pick(Maybe<&2,U32>,_,Some{peer},None{}))) ==
      Laws.Snapshot{written_tick,written_time,written_paused,written_daylight,1n+written_revision,written_count,written_pending,
        C.Applied{Q.Stamp{tick,peer,sequence},1n+written_revision} <> C.trim_events(written_events,1023n),Done{Unit{}}} : Laws.Snapshot}
  Equal.trans(Laws.Snapshot,
    Laws.snapshot(Edit.player_current(C.World{tick,time,paused,daylight,revision,count,sections,pending,events},position,state,expected,sequence,peer)),
    Laws.snapshot(Edit.finished(Q.Stamp{tick,peer,sequence},
      (C.World{written_tick,written_time,written_paused,written_daylight,written_revision,written_count,written_sections,written_pending,written_events},Done{Unit{}}))),
    Laws.Snapshot{written_tick,written_time,written_paused,written_daylight,1n+written_revision,written_count,written_pending,
      C.Applied{Q.Stamp{tick,peer,sequence},1n+written_revision} <> C.trim_events(written_events,1023n),Done{Unit{}}},
    Equal.cong(C.World & Result<&2,&2,Edit.Error,Unit>,Laws.Snapshot,Laws.snapshot,
      Edit.player_current(C.World{tick,time,paused,daylight,revision,count,sections,pending,events},position,state,expected,sequence,peer),
      Edit.finished(Q.Stamp{tick,peer,sequence},
        (C.World{written_tick,written_time,written_paused,written_daylight,written_revision,written_count,written_sections,written_pending,written_events},Done{Unit{}})),
      player_succeeds(C.World{tick,time,paused,daylight,revision,count,sections,pending,events},Q.Stamp{tick,peer,sequence},position,state,count,expected,revision,sequence,
        read_world,C.World{written_tick,written_time,written_paused,written_daylight,written_revision,written_count,written_sections,written_pending,written_events},old,
        positive,matching,valid,loaded,written)),
    Laws.successful_commit_receipt(written_tick,written_time,written_paused,written_daylight,written_revision,written_count,written_sections,written_pending,written_events,Q.Stamp{tick,peer,sequence}))
