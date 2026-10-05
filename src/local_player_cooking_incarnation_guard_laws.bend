import Base
import ./core.bend as C
import ./section_map.bend as M
import ./section_map_update.bend as Update
import ./block_light.bend as L
import ./block_light_world.bend as W
import ./cooking_world.bend as CW
import ./cooking_world_store.bend as S
import ./cooking_world_bindings.bend as B
import ./schedule.bend as Q
import ./local_player_cooking_incarnation_guard.bend as G

# These projections observe the complete affine owner, not a hash, cell list,
# clock or normalized map. All arrays, malformed nodes and collision order
# remain part of the equation.
def sections(result:M.Sections & Result<&2,&2,C.Error,Unit>) -> M.Sections:
  (owner,status) = result
  owner

law prospective_left_owner:
  for hi:M.Sections
  for result:M.Sections & Result<&2,&2,C.Error,Unit>
  {sections(C.prospective_left(hi,result)) == M.Branch{sections(result),hi} : M.Sections}

law prospective_right_owner:
  for lo:M.Sections
  for result:M.Sections & Result<&2,&2,C.Error,Unit>
  {sections(C.prospective_right(lo,result)) == M.Branch{lo,sections(result)} : M.Sections}

law every_actual_admission_path_retains_complete_trie:
  for +route:List<&2,Bool>
  for owner:M.Sections
  for +key:String
  for +creating:Bool
  {sections(C.prospective_route(route,owner,key,creating)) == owner : M.Sections}

# The actual successful-create overlay supplies later membership without
# constructing a second World or Section. Both result branches retain World.
law created_key_overlay_retains_complete_world:
  for world:C.World
  for key:String
  for +creating:Bool
  {C.prospective_overlay(True{},world,key,creating) ==
    (world,C.prospective_present(creating,key,True{})) : C.World & Result<&2,&2,C.Error,Unit>}

law rejected_application_cannot_advance_lifecycle_scan:
  for operation:G.Operation
  for scan:G.Scan
  for error:C.Error
  {G.accepted(operation,scan,Fail{error}) == Done{scan} : Result<&2,&2,String,G.Scan>}

# The premise is the real Store binding identity test; arbitrary property/LIT
# differences, later duplicate headers and arbitrary counters remain allowed.
law same_block_change_has_no_owner_reset:
  for candidate:C.Position
  for previous:B.Binding
  for position:C.Position
  for +next:B.Binding
  for rest:List<&2,G.Header>
  for same:{B.same_block(previous,next) == True{} : Bool}
  {G.found(candidate,previous,position,B.Cooking{next},rest) ==
    G.Change{G.Header{candidate,next} <> rest,None{}} : G.Change}

# This proves the actual exhausted branch on arbitrary payloads. The concrete
# MAX48 comparison feeding it is a separate, currently open arithmetic law.
law exhaustion_branch_refuses_before_increment:
  for key:String
  for values:List<&2,G.Header>
  for incarnations:Map<&2,Nat>
  for current:Nat
  {G.counted(False{},key,values,incarnations,current) ==
    Fail{"local-cooking:incarnation-exhausted"} : Result<&2,&2,String,G.Scan>}

# Acknowledgement counts reset markers, independent of positions, Drop/XP
# effects and duplicate headers. No Map lookup/write occurs in this branch.
law acknowledged_reset_preserves_counter_map:
  for remaining:Nat
  for position:C.Position
  for values:List<&2,G.Header>
  for incarnations:Map<&2,Nat>
  {G.reset(1n+remaining,position,values,incarnations) ==
    Done{G.Scan{values,incarnations,remaining}} : Result<&2,&2,String,G.Scan>}

law refused_scan_cancels_all_later_due_admission:
  for operations:List<&2,G.Operation>
  for statuses:List<&2,Result<&2,&2,C.Error,Unit>>
  for message:String
  {G.walk(operations,statuses,Fail{message}) == Fail{message} : Result<&2,&2,String,Unit>}

# This is the actual CW publication continuation. The rejected input retains
# every Core clock/pending/event/section field, light FIFO, Entry array,
# loading cursor, phase and key. No owner projection is substituted.
law guard_refusal_retains_complete_cooking_world:
  for views:List<&2,S.View>
  for light:L.State
  for loading:Maybe<&2,W.Cursor>
  for entries:List<&1,S.Entry>
  for phase:CW.Phase
  for keys:List<&2,String>
  for future:List<&2,Q.Pending<C.Mutation>>
  for ops:List<&2,CW.Operation>
  for world:C.World
  for text:String
  {CW.owned_guarded(views,light,loading,entries,phase,keys,future,ops,(world,Fail{text})) ==
    (CW.State{W.State{world,light,loading},entries,phase,keys},Fail{CW.Authority{text}}) :
    CW.State & Result<&2,&2,CW.Error,Unit>}

law prepared_guard_failure_precedes_all_clock_and_due_publication:
  for +views:List<&2,S.View>
  for future:List<&2,Q.Pending<C.Mutation>>
  for +ops:List<&2,CW.Operation>
  for incarnations:Map<&2,Nat>
  for acknowledged:Nat
  for world:C.World
  for light:L.State
  for loading:Maybe<&2,W.Cursor>
  for entries:List<&1,S.Entry>
  for phase:CW.Phase
  for keys:List<&2,String>
  for text:String
  for refused:{G.check(world,views,CW.incarnation_operations(ops),incarnations,acknowledged) ==
    (world,Fail{text}) : C.World & Result<&2,&2,String,Unit>}
  {CW.owned_ready(views,future,ops,incarnations,acknowledged,
    CW.State{W.State{world,light,loading},entries,phase,keys}) ==
    (CW.State{W.State{world,light,loading},entries,phase,keys},Fail{CW.Authority{text}}) :
    CW.State & Result<&2,&2,CW.Error,Unit>}
