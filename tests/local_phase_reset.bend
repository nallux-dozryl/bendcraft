import Base
import ./local_phase_runtime.bend as Old
import ../src/local_phase_runtime.bend as X
import ../src/local_travel_history.bend as TH
import ../src/local_player_runtime.bend as RT
import ../src/local_move_history.bend as MH
import ../src/local_move_world.bend as LM
import ../src/player_fall_history.bend as H
import ../src/player_pose.bend as Pose
import ../src/player_controls.bend as PC
import ../src/player_input.bend as PI
import ../src/player_look.bend as PL
import ../src/fall_reset_world.bend as FR
import ../src/client_world.bend as W
import ../src/game.bend as G
import ../src/core.bend as C
import ../src/locomotion.bend as L
import ../src/support.bend as SP
import ../src/movement.bend as M
import ../src/geometry.bend as A
import ../src/f64.bend as F

# This harness is imported by the next LocalPlayer composite. It does not enable
# the frozen facade's reset path. The literal airborne Body/history is copied
# from actual reference/local_travel_history.json air_miss step0.before.
def air_body() -> M.Body:
  M.Body{M.Vec3{F.F64{1071644672,0},F.F64{1076101120,0},F.F64{1071644672,0}},
    A.AABB{F.F64{1070176665,2147483648},F.F64{1076101120,0},F.F64{1070176665,2147483648},F.F64{1072273817,2684354560},F.F64{1076337049,2550136832},F.F64{1072273817,2684354560}},
    M.Vec3{F.F64{0,0},F.F64{3220307968,0},F.F64{0,0}},Pose.float_bits(1058642330),Pose.float_bits(1072064102),False{},False{},False{},False{}}

def empty_keys() -> PI.Buttons:
  PI.Buttons{False{},False{},False{},False{},False{},False{},False{}}

def air_seed_from(seed:Old.Seed) -> Old.Seed:
  Old.Seed{body,X.Metadata{local,player,sprint,pose,PC.Controller{buttons,look,mouse,options},entity, receiver, error,tail},support,minor,history,owned} = seed
  Old.Seed{air_body(),X.Metadata{local,player,False{},pose,
    PC.Controller{empty_keys(),PL.State{Pose.float_bits(0),Pose.float_bits(0),Pose.float_bits(0),Pose.float_bits(0)},mouse,options},entity, receiver, Some{"retained-reset-anchor"},[]},
    SP.State{None{},False{}},LM.MinorState{False{}},H.History{F.F64{1070805811,858993459}},[]}

def air_seed() -> Old.Seed:
  air_seed_from(Old.seed_0())

def interior() -> A.AABB:
  A.AABB{F.from_i32(4294967232),F.from_i32(4294967232),F.from_i32(4294967232),F.from_u32(64),F.from_u32(64),F.from_u32(64)}

def policy(mode:U32) -> TH.ResetPolicy:
  match mode:
    case 1: TH.ResetPolicy{interior(),2n,FR.DefaultClientOverworldFourState{},[]}
    case 2: TH.ResetPolicy{A.AABB{F.from_u32(0),F.from_u32(0),F.from_u32(0),F.from_u32(1),F.from_u32(1),F.from_u32(1)},128n,FR.DefaultClientOverworldFourState{},[]}
    case 3: TH.ResetPolicy{interior(),128n,FR.UnresolvedTags{},[]}
    case 4: TH.ResetPolicy{interior(),128n,FR.DefaultClientOverworldFourState{},[TH.ResetPolicy{interior(),128n,FR.DefaultClientOverworldFourState{},[]}]}
    case _: TH.ResetPolicy{interior(),128n,FR.DefaultClientOverworldFourState{},[]}

def setup_result(tables:L.Tables,seed:Old.Seed,result:W.State & Result<&2,&2,String,Unit>) -> IO(X.State):
  match result:
    case (W.State{engine,body,yaw,pitch,Some{+palette},region,cache},Done{unit}):
      do IO<X.State>:
        world:W.State <- Old.fixture_palette(W.State{engine,body,yaw,pitch,Some{palette},region,cache},palette)
        timed:W.State <- Old.mutate_world(world,C.TimeSet{777n})
        fixed:W.State <- Old.mutate_world(timed,C.DaylightSet{False{}})
        queued:W.State <- Old.held_pending(fixed)
        cached:W.State <- Old.snapshot_kept(W.snapshot(queued,64,48))
        return Old.seed_world(tables,seed,cached)
    case (world,Fail{cause}): IO.die(X.State,3,"phase reset setup:" ++ cause)
    case (world,Done{unit}): IO.die(X.State,3,"phase reset setup palette")

def setup(tables:L.Tables,seed:Old.Seed) -> IO(X.State):
  do IO<X.State>:
    engine:G.Engine <- G.load()
    setup_result(tables,seed,W.new(engine))

def request_from_driver(driver:RT.Driver) -> X.PrepareRequest:
  RT.Driver{request} = driver
  request

def prepared_request() -> X.PrepareRequest:
  request_from_driver(RT.driver())

def stage_report(+id:String,stage:X.ApplyStage) -> IO(X.ApplyStage):
  X.ApplyStage{state,pending} = stage
  do IO<X.ApplyStage>:
    next:X.State <- Old.state_report(id,state)
    return X.ApplyStage{next,pending}

def diagnostic(status:Result<&2,&2,X.Error,X.Observation>) -> String:
  match status:
    case Done{value}: "done"
    case Fail{cause}: RT.error_text(cause)

def result_report(+id:String,result:X.State & Result<&2,&2,X.Error,X.Observation>) -> IO(X.State):
  (state,+status) = result
  do IO<X.State>:
    IO.print(id ++ "|diagnostic|" ++ diagnostic(status))
    Old.result_report(id,(state,status))

def facts_resumed(+id:String,mode:U32,result:X.ApplyStage & Result<&2,&2,X.Error,X.ApplyFacts>) -> IO(X.State):
  (stage,status) = result
  result_report(id,X.resume_apply_with_reset_checked(stage,status,policy(mode)))

# Real frozen post-sprint support/attribute provider, closed over the actual
# controls decision. No second control sample, caller clip or fabricated MISS.
def intended(+id:String,mode:U32,result:X.ApplyStage & X.ApplyIntent) -> IO(X.State):
  (stage,X.ApplyIntent{sprinting,updates}) = result
  facts_resumed(id,mode,X.stage_query(stage,world => support => RT.apply_provider(sprinting,world,support)))

def prepared(+id:String,mode:U32,result:X.PrepareResult) -> IO(X.State):
  match result:
    case X.Rejected{state,cause}: IO.die(X.State,3,"phase reset unexpected prepare:" ++ RT.error_text(cause))
    case X.Paused{state}: IO.die(X.State,3,"phase reset unexpected pause")
    case X.AwaitApply{stage}:
      do IO<X.State>:
        anchored:X.ApplyStage <- stage_report(id ++ "-anchor",stage)
        intended(id,mode,X.stage_intent(anchored))

def one(+id:String,mode:U32,scheduled:Bool,state:X.State) -> IO(X.State):
  do IO<X.State>:
    before:X.State <- Old.state_report(id ++ "-before",state)
    prepared(id,mode,X.prepare_checked(before,prepared_request(),scheduled))

def air_case_after(+id:String,mode:U32,state:X.State) -> IO(L.Tables):
  match mode:
    case 0: IO.pure(L.Tables,Old.tables_returned(state))
    case _:
      do IO<L.Tables>:
        recovered:X.State <- one(id ++ ":recovery",0,False{},state)
        return Old.tables_returned(recovered)

def air_case(+id:String,+mode:U32,scheduled:Bool,tables:L.Tables) -> IO(L.Tables):
  do IO<L.Tables>:
    initial:X.State <- setup(tables,air_seed())
    after:X.State <- one(id,mode,scheduled,initial)
    air_case_after(id,mode,after)

# If this provider is incorrectly invoked on a malformed stage, its Core step
# remains observable even if the stage detects authority drift afterwards.
def provider_marker(world:W.State,support:SP.State) -> W.State & Result<&2,&2,X.Error,X.ApplyFacts>:
  W.State{G.Engine{core,registry},body,yaw,pitch,palette,region,cache} = world
  (W.State{G.Engine{C.step(core),registry},body,yaw,pitch,palette,region,cache},Fail{X.ViewError{"observable-reset-provider-ran"}})

def pending_tail(stage:X.ApplyStage) -> X.ApplyStage:
  X.ApplyStage{state,+pending} = stage
  X.ApplyPending{frame,decision,early,error,tail} = pending
  X.ApplyStage{state,X.ApplyPending{frame,decision,early,error,[pending]}}

def owned_stage(stage:X.ApplyStage,child:X.State) -> X.ApplyStage:
  X.ApplyStage{X.State{motion,tables,metadata,tail},pending} = stage
  X.ApplyStage{X.State{motion,tables,metadata,[child]},pending}

def guard_query(+id:String,result:X.ApplyStage & Result<&2,&2,X.Error,X.ApplyFacts>) -> IO(L.Tables):
  (stage,status) = result
  do IO<L.Tables>:
    after:X.State <- result_report(id,X.resume_apply_with_reset_checked(stage,status,policy(0)))
    return Old.tables_returned(after)

def guard_stage(+id:String,stage:X.ApplyStage) -> IO(L.Tables):
  do IO<L.Tables>:
    before:X.ApplyStage <- stage_report(id ++ "-before",stage)
    guard_query(id,X.stage_query(before,provider_marker))

def guard_selected(+id:String,owned:Bool,stage:X.ApplyStage) -> IO(L.Tables):
  match owned:
    case False{}: guard_stage(id,pending_tail(stage))
    case True{}:
      do IO<L.Tables>:
        child:X.State <- Old.owner_child("owner-child-first")
        guard_stage(id,owned_stage(stage,child))

def guard_prepared(+id:String,owned:Bool,result:X.PrepareResult) -> IO(L.Tables):
  match result:
    case X.Rejected{state,cause}: IO.die(L.Tables,3,"phase reset guard prepare")
    case X.Paused{state}: IO.die(L.Tables,3,"phase reset guard paused")
    case X.AwaitApply{stage}: guard_selected(id,owned,stage)

def guard_case(+id:String,owned:Bool,tables:L.Tables) -> IO(L.Tables):
  do IO<L.Tables>:
    state:X.State <- setup(tables,air_seed())
    guard_prepared(id,owned,X.prepare_scheduled_checked(state,prepared_request()))

def jump_cases(tables:L.Tables) -> IO(L.Tables):
  do IO<L.Tables>:
    initial:X.State <- setup(tables,Old.seed_3())
    jumped:X.State <- one("scheduled_jump:0",0,True{},Old.held(initial,PI.Buttons{True{},False{},False{},False{},True{},False{},False{}}))
    released:X.State <- one("scheduled_jump:1",0,True{},Old.held(jumped,PI.Buttons{True{},False{},False{},False{},False{},False{},False{}}))
    return Old.tables_returned(released)

def cases(tables:L.Tables) -> IO(Unit):
  do IO<Unit>:
    direct:L.Tables <- air_case("reset:air-direct",0,False{},tables)
    scheduled:L.Tables <- air_case("reset:air-scheduled",0,True{},direct)
    work_direct:L.Tables <- air_case("reset:work-direct",1,False{},scheduled)
    work_scheduled:L.Tables <- air_case("reset:work-scheduled",1,True{},work_direct)
    interior_direct:L.Tables <- air_case("reset:interior-direct",2,False{},work_scheduled)
    interior_scheduled:L.Tables <- air_case("reset:interior-scheduled",2,True{},interior_direct)
    profile_direct:L.Tables <- air_case("reset:profile-direct",3,False{},interior_scheduled)
    profile_scheduled:L.Tables <- air_case("reset:profile-scheduled",3,True{},profile_direct)
    policy_tail:L.Tables <- air_case("reset:policy-tail",4,True{},profile_scheduled)
    owned:L.Tables <- guard_case("reset:owned-stage",True{},policy_tail)
    pending:L.Tables <- guard_case("reset:pending-tail",False{},owned)
    remaining:L.Tables <- jump_cases(pending)
    IO.print("local-phase-reset|complete|true")

def loaded(result:Result<&2,&1,L.Error,L.Tables>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.die(Unit,3,"phase reset sine table")
    case Done{tables}: cases(tables)

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> path <> Nil{}:
      do IO<Unit>:
        tables:Result<&2,&1,L.Error,L.Tables> <- L.Tables.load(path)
        loaded(tables)
    case _: IO.die(Unit,2,"phase reset table argument required")

def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),arguments)
