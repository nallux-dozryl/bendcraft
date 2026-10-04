# Transport-only projection of immutable local_player_session.bend.
# Fixture, atomic, owner, startup and actual Session operation bodies are exact.
import Base
import ../src/local_player_session.bend as S
import ../src/local_player_storage.bend as PS
import ../src/local_player_record.bend as PR
import ../src/local_player_runtime.bend as R
import ../src/local_phase_runtime.bend as X
import ../src/local_move_history.bend as MH
import ../src/local_move_world.bend as LM
import ../src/local_input.bend as LI
import ../src/player_runtime.bend as CommonPR
import ../src/player_tick.bend as PT
import ../src/player_pose.bend as Pose
import ../src/player_fall_history.bend as H
import ../src/entity_common_tick.bend as ECT
import ../src/player_controls.bend as PC
import ../src/player_input.bend as PI
import ../src/player_look.bend as PL
import ../src/mouse_input.bend as MI
import ../src/client_controls.bend as CC
import ../src/client_world.bend as W
import ../src/client_render.bend as CR
import ../src/registry.bend as B
import ../src/game.bend as G
import ../src/core.bend as C
import ../src/section_map.bend as SM
import ../src/section.bend as Section
import ../src/schedule.bend as Q
import ../src/locomotion.bend as L
import ../src/support.bend as SP
import ../src/travel.bend as T
import ../src/movement.bend as M
import ../src/geometry.bend as Geo
import ../src/f64.bend as F
import ../src/extended_persistence.bend as E
import ../src/atomic_file.bend as A
import ../src/world_lock.bend as WL
import ../src/server.bend as Server
import ../src/live.bend as Live
import ../src/json.bend as J

# The actual consumer facade supplies every tick/fits/support/input/save path.
# Only explicitly named fixture operations below are synthetic test controls.

def choose_text(valid:Bool,accepted:Unit -> String,rejected:Unit -> String) -> String:
  match valid:
    case True{}: accepted(Unit{})
    case False{}: rejected(Unit{})

def runs(values:List<&2,U32>, +value:U32, +count:Nat) -> String:
  match values:
    case Nil{}: Nat.show(count) ++ "," ++ U32.show(value) ++ "/"
    case +next <> +rest:
      choose_text(U32.is_eq(next,value),unit => runs(rest,value,1n+count),
        unit => Nat.show(count) ++ "," ++ U32.show(value) ++ "/" ++ runs(rest,next,1n))

def section_words(values:List<&2,U32>) -> String:
  match values:
    case Nil{}: ""
    case value <> rest: runs(rest,value,1n)

def entries_snapshot(entries:List<&1,SM.Entry>) -> List<&1,SM.Entry> & String:
  match entries:
    case Nil{}: ([],"")
    case SM.Entry{+key,section} <> rest:
      W.paired(Section.Section,List<&2,U32>,List<&1,SM.Entry> & String,Section.Section.snapshot(section),
        next => words => W.paired(List<&1,SM.Entry>,String,List<&1,SM.Entry> & String,entries_snapshot(rest),
          remaining => text => (SM.Entry{key,next} <> remaining,key ++ "=" ++ section_words(words) ++ ";" ++ text)))

def sections_snapshot(sections:SM.Sections) -> SM.Sections & String:
  match sections:
    case SM.EmptySections{}: (SM.EmptySections{},"E")
    case SM.Bucket{entries}:
      W.paired(List<&1,SM.Entry>,String,SM.Sections & String,entries_snapshot(entries),
        next => text => (SM.Bucket{next},"K(" ++ text ++ ")"))
    case SM.Branch{left,right}:
      W.paired(SM.Sections,String,SM.Sections & String,sections_snapshot(left),
        next => text => W.paired(SM.Sections,String,SM.Sections & String,sections_snapshot(right),
          other => suffix => (SM.Branch{next,other},"B(" ++ text ++ "," ++ suffix ++ ")")))


def f64_show(value: F.F64) -> String:
  F.F64{hi, lo} = value
  U32.show(hi) ++ "|" ++ U32.show(lo)

def vector_show(value: M.Vec3) -> String:
  M.Vec3{x, y, z} = value
  f64_show(x) ++ "|" ++ f64_show(y) ++ "|" ++ f64_show(z)

def box_show(value: Geo.AABB) -> String:
  Geo.AABB{a, b, c, d, e, f} = value
  f64_show(a) ++ "|" ++ f64_show(b) ++ "|" ++ f64_show(c) ++ "|" ++ f64_show(d) ++ "|" ++ f64_show(e) ++ "|" ++ f64_show(f)

def body_show(value: M.Body) -> String:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = value
  vector_show(position) ++ "|" ++ box_show(box) ++ "|" ++ vector_show(velocity) ++ "|" ++ U32.show(Pose.raw(width)) ++ "|" ++ U32.show(Pose.raw(height)) ++ "|" ++ U32.show(Bool.to_u32(ground)) ++ "|" ++ U32.show(Bool.to_u32(horizontal)) ++ "|" ++ U32.show(Bool.to_u32(vertical)) ++ "|" ++ U32.show(Bool.to_u32(below))

def flag(value: Bool) -> String:
  U32.show(Bool.to_u32(value))

def bounds(value: W.Bounds) -> String:
  W.Bounds{x, y, z, w, h, d} = value
  U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ "," ++ U32.show(d)

def colors(value: W.Palette) -> String:
  W.Palette{a, b, c, d} = value
  U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d)

def position(value: C.Position) -> String:
  C.Position{dimension, x, y, z} = value
  U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z)

def raw_blocks(values: List<&2, W.RawBlock>) -> String:
  match values:
    case Nil{}: ""
    case W.RawBlock{W.Cell{x, y, z, edge}, state, material} <> rest:
      position(C.Position{"minecraft:overworld", x, y, z}) ++ "," ++ U32.show(edge) ++ "," ++ U32.show(state) ++ "," ++ U32.show(material) ++ ";" ++ raw_blocks(rest)

def cache(value: Maybe<&2, W.SnapshotCache>) -> String:
  match value:
    case None{}: "none"
    case Some{W.SnapshotCache{revision, region, palette, blocks}}:
      Nat.show(revision) ++ "/" ++ bounds(region) ++ "/" ++ colors(palette) ++ "/" ++ raw_blocks(blocks)

def view(value: W.View) -> String:
  match value:
    case W.View{body, yaw, pitch, None{}, region, cached}:
      U32.show(F32.bits(yaw)) ++ "|" ++ U32.show(F32.bits(pitch)) ++ "|none|" ++ bounds(region) ++ "|" ++ cache(cached)
    case W.View{body, yaw, pitch, Some{palette}, region, cached}:
      U32.show(F32.bits(yaw)) ++ "|" ++ U32.show(F32.bits(pitch)) ++ "|" ++ colors(palette) ++ "|" ++ bounds(region) ++ "|" ++ cache(cached)

def stamp(value: Q.Stamp) -> String:
  Q.Stamp{tick, peer, sequence} = value
  Nat.show(tick) ++ "," ++ U32.show(peer) ++ "," ++ Nat.show(sequence)

def mutation(value: C.Mutation) -> String:
  match value:
    case C.SectionCreate{point, fill}: "section," ++ position(point) ++ "," ++ U32.show(fill)
    case C.BlockSet{point, state}: "block," ++ position(point) ++ "," ++ U32.show(state)
    case C.TimeSet{time}: "time," ++ Nat.show(time)
    case C.DaylightSet{enabled}: "daylight," ++ flag(enabled)

def pending_show(values: List<&2, Q.Pending<C.Mutation>>) -> String:
  match values:
    case Nil{}: ""
    case Q.Pending{when, operation} <> rest: stamp(when) ++ "," ++ mutation(operation) ++ ";" ++ pending_show(rest)

def events_show(values: List<&2, C.CoreEvent>) -> String:
  match values:
    case Nil{}: ""
    case C.Applied{when, revision} <> rest: "applied," ++ stamp(when) ++ "," ++ Nat.show(revision) ++ ";" ++ events_show(rest)
    case C.Rejected{when, reason} <> rest: "rejected," ++ stamp(when) ++ "," ++ W.error_text(reason) ++ ";" ++ events_show(rest)


def buttons_word(keys: PI.Buttons) -> U32:
  PI.Buttons{forward,back,left,right,jump,shift,sprint} = keys
  U32.add(Bool.to_u32(forward),U32.add(U32.mul(Bool.to_u32(back),2),
    U32.add(U32.mul(Bool.to_u32(left),4),U32.add(U32.mul(Bool.to_u32(right),8),
    U32.add(U32.mul(Bool.to_u32(jump),16),U32.add(U32.mul(Bool.to_u32(shift),32),U32.mul(Bool.to_u32(sprint),64)))))))

def bools(values:List<&2,Bool>) -> String:
  match values:
    case Nil{}: ""
    case value <> rest: flag(value) ++ "," ++ bools(rest)

def pose_states(values:List<&2,Pose.State>) -> String:
  match values:
    case Nil{}: ""
    case Pose.State{pose,eye,tail} <> rest:
      U32.show(Pose.pose_id(pose)) ++ "," ++ U32.show(Pose.raw(eye)) ++ "[" ++ pose_states(tail) ++ "]/" ++ pose_states(rest)

def local_show(value:LI.State) -> String:
  LI.State{keys,PI.Vector{x,z},trigger,crouch,bx,by,ox,oy} = value
  U32.show(buttons_word(keys)) ++ "|" ++ U32.show(Pose.raw(x)) ++ "|" ++ U32.show(Pose.raw(z)) ++ "|" ++
    U32.show(trigger) ++ "|" ++ flag(crouch) ++ "|" ++ U32.show(Pose.raw(bx)) ++ "|" ++ U32.show(Pose.raw(by)) ++ "|" ++ U32.show(Pose.raw(ox)) ++ "|" ++ U32.show(Pose.raw(oy))

def player_show(value:CommonPR.Metadata) -> String:
  CommonPR.Metadata{PT.Input{x,y,z},jump,delay,trigger,sync,speed,head} = value
  U32.show(Pose.raw(x)) ++ "|" ++ U32.show(Pose.raw(y)) ++ "|" ++ U32.show(Pose.raw(z)) ++ "|" ++ flag(jump) ++ "|" ++
    U32.show(delay) ++ "|" ++ U32.show(trigger) ++ "|" ++ flag(sync) ++ "|" ++ U32.show(Pose.raw(speed)) ++ "|" ++ U32.show(Pose.raw(head))

def look_show(value:PL.State) -> String:
  PL.State{yaw,pitch,oldyaw,oldpitch} = value
  U32.show(Pose.raw(yaw)) ++ "|" ++ U32.show(Pose.raw(pitch)) ++ "|" ++ U32.show(Pose.raw(oldyaw)) ++ "|" ++ U32.show(Pose.raw(oldpitch))

def controller_show(value:PC.Controller) -> String:
  PC.Controller{buttons,look,MI.State{x,y,ax,ay,first},MI.Options{sensitivity,ix,iy,smooth,scoping}} = value
  U32.show(buttons_word(buttons)) ++ "|" ++ look_show(look) ++ "|" ++ f64_show(x) ++ "|" ++ f64_show(y) ++ "|" ++
    f64_show(ax) ++ "|" ++ f64_show(ay) ++ "|" ++ flag(first) ++ "|" ++ f64_show(sensitivity) ++ "|" ++ flag(ix) ++ "|" ++ flag(iy) ++ "|" ++ flag(smooth) ++ "|" ++ flag(scoping)

def entity_show(value:ECT.Metadata) -> String:
  ECT.Metadata{o,old,invulnerable,count} = value
  vector_show(o) ++ "|" ++ vector_show(old) ++ "|" ++ U32.show(invulnerable) ++ "|" ++ U32.show(count)

def prior_error(value:Maybe<&2,String>) -> String:
  match value:
    case None{}: "none"
    case Some{value}: "some:" ++ value

def metadata_list(values:List<&2,X.Metadata>) -> String:
  match values:
    case Nil{}: ""
    case X.Metadata{local,player,sprint,pose,controls,entity, receiver, error,tail} <> rest:
      local_show(local) ++ ";" ++ player_show(player) ++ ";" ++ flag(sprint) ++ ";" ++ pose_states([pose]) ++ ";" ++
        controller_show(controls) ++ ";" ++ entity_show(entity) ++ ";" ++ prior_error(error) ++ "{" ++ metadata_list(tail) ++ "}/" ++ metadata_list(rest)

def support_show(value:SP.State) -> String:
  match value:
    case SP.State{None{},ground}: "none|" ++ flag(ground)
    case SP.State{Some{T.BlockPos{x,y,z}},ground}: U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "|" ++ flag(ground)


# Separate primitive interruption lane: actual leased Atomic.publish_with over
# independently encoded bundle bytes. Session.dispatch's quiet save is exercised
# separately; this hook only exposes deterministic publication-stage pauses.
def atomic_pause_selected(valid:Bool) -> IO(Unit):
  match valid:
    case True{}: IO.sleep(30000)
    case False{}: IO.pure(Unit,Unit{})

def atomic_pause(name:String,stage:A.Stage) -> IO(Unit):
  atomic_pause_selected(String.eq(name,A.stage_name(stage)))

def atomic_pause_result(stage:A.Stage,result:Result<&1,&1,U32 & String,String>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.pure(Unit,Unit{})
    case Done{name}: atomic_pause(name,stage)

def atomic_observe_inner(+stage:A.Stage) -> IO(Unit):
  do IO<Unit>:
    IO.print(A.stage_name(stage))
    name : Result<&1,&1,U32 & String,String> <- IO.get_env("MC_ATOMIC_PAUSE")
    atomic_pause_result(stage,name)

def atomic_observe(stage:A.Stage) -> IO(Unit):
  atomic_observe_inner(stage)

def atomic_loaded(result:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(List<&2,U32>):
  (file,status) = result
  do IO<List<&2,U32>>:
    File.close(file)
    IO.pass(List<&2,U32>,status)

def atomic_read(path:String) -> IO(List<&2,U32>):
  do IO<List<&2,U32>>:
    file : File <- IO.try(File,File.open(path,"r"))
    result : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,16846848)
    atomic_loaded(result)

def atomic_lease(path:String,suffix:String,payload:String,lease:WL.Lease) -> IO(Unit):
  do IO<Unit>:
    bytes : List<&2,U32> <- atomic_read(payload)
    result : A.Outcome <- A.publish_with(~atomic_observe,path,suffix,bytes)
    released : Result<&1,&1,U32 & String,Unit> <- WL.release(lease)
    IO.pass(Unit,released)
    IO.print(A.outcome_text(result))

def atomic_acquired(path:String,suffix:String,payload:String,result:Result<&1,&1,U32 & String,WL.Lease>) -> IO(Unit):
  match result:
    case Fail{(code,message)}: IO.die(Unit,1,message)
    case Done{lease}: atomic_lease(path,suffix,payload,lease)

def atomic(+path:String,suffix:String,payload:String) -> IO(Unit):
  do IO<Unit>:
    lease : Result<&1,&1,U32 & String,WL.Lease> <- WL.acquire(path ++ ".lock")
    atomic_acquired(path,suffix,payload,lease)


def table_words(fuel:Nat,array:Array<F32>,+index:U32,digest:U32) -> Array<F32> & U32:
  match fuel:
    case 0n: (array,digest)
    case 1n+rest:
      W.paired(Array<F32>,F32,Array<F32> & U32,Array.get(F32,array,index),
        kept => value => table_words(rest,kept,U32.inc(index),U32.mul(U32.xor(digest,Pose.raw(value)),16777619)))

def table_report(tables:L.Tables) -> L.Tables & J.Value:
  L.Tables{array} = tables
  W.paired(Array<F32>,U32,L.Tables & J.Value,table_words(65536n,array,0,2166136261),
    kept => digest => (L.Tables{kept},Live.uint(digest)))

def world_report_sections(+saved_view:W.View,registry:B.Registry,+tick:Nat,+time:Nat,+paused:Bool,+daylight:Bool,+revision:Nat,+count:U32,
    +pending:List<&2,Q.Pending<C.Mutation>>,+events:List<&2,C.CoreEvent>,result:SM.Sections & String) -> W.State & J.Value:
  W.View{body,yaw,pitch,palette,region,cache} = saved_view
  (sections,text) = result
  (W.attach(G.Engine{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},registry},saved_view),Live.obj([
    J.JMember{"body",Live.text(body_show(body))},J.JMember{"view",Live.text(view(W.View{body,yaw,pitch,palette,region,cache}))},
    J.JMember{"clock",J.JArray{[Live.natural(tick),Live.natural(time),Live.boolean(paused),Live.boolean(daylight),Live.natural(revision),Live.uint(count)]}},
    J.JMember{"pending",Live.text(pending_show(pending))},J.JMember{"events",Live.text(events_show(events))},J.JMember{"sections",Live.text(text)}]))

def world_report_taken(result:G.Engine & W.View) -> W.State & J.Value:
  (G.Engine{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},registry},view) = result
  world_report_sections(view,registry,tick,time,paused,daylight,revision,count,pending,events,sections_snapshot(sections))

def world_report(world:W.State) -> W.State & J.Value:
  world_report_taken(W.take(world))

def motion_leaf_report(motion:MH.State) -> MH.State & J.Value:
  MH.State{world,+support,LM.MinorState{+flag_minor},H.State{+history},tail} = motion
  W.paired(W.State,J.Value,MH.State & J.Value,world_report(world),kept => value =>
    (MH.State{kept,support,LM.MinorState{flag_minor},H.State{history},tail},Live.obj([J.JMember{"world",value},J.JMember{"support",Live.text(support_show(support))},
      J.JMember{"minor",Live.boolean(flag_minor)},J.JMember{"history",Live.text(f64_show(MH.history_distance(history)))}])))

def state_leaf_report(state:X.State) -> X.State & J.Value:
  X.State{motion,tables,+metadata,tail} = state
  W.paired(MH.State,J.Value,X.State & J.Value,motion_leaf_report(motion),kept => value =>
    W.paired(L.Tables,J.Value,X.State & J.Value,table_report(tables),table => digest =>
      (X.State{kept,table,metadata,tail},Live.obj([J.JMember{"motion",value},J.JMember{"table_digest",digest},
        J.JMember{"metadata",Live.text(metadata_list([metadata]))}]))))

def state_children(values:List<&1,X.State>) -> List<&1,X.State> & List<&2,J.Value>:
  match values:
    case Nil{}: ([],[])
    case child <> rest:
      W.paired(X.State,J.Value,List<&1,X.State> & List<&2,J.Value>,state_leaf_report(child),next => value =>
        W.paired(List<&1,X.State>,List<&2,J.Value>,List<&1,X.State> & List<&2,J.Value>,state_children(rest),remaining => values =>
          (next <> remaining,value <> values)))

def motion_children(values:List<&1,MH.State>) -> List<&1,MH.State> & List<&2,J.Value>:
  match values:
    case Nil{}: ([],[])
    case child <> rest:
      W.paired(MH.State,J.Value,List<&1,MH.State> & List<&2,J.Value>,motion_leaf_report(child),next => value =>
        W.paired(List<&1,MH.State>,List<&2,J.Value>,List<&1,MH.State> & List<&2,J.Value>,motion_children(rest),remaining => values =>
          (next <> remaining,value <> values)))

def owner_report(state:X.State) -> X.State & J.Value:
  X.State{MH.State{world,support,minor,history,owned},tables,metadata,tail} = state
  W.paired(List<&1,X.State>,List<&2,J.Value>,X.State & J.Value,state_children(tail),children => a =>
    W.paired(List<&1,MH.State>,List<&2,J.Value>,X.State & J.Value,motion_children(owned),motions => b =>
      W.paired(X.State,J.Value,X.State & J.Value,state_leaf_report(X.State{MH.State{world,support,minor,history,motions},tables,metadata,children}),
        kept => value => (kept,Live.obj([J.JMember{"root",value},J.JMember{"state_children",J.JArray{a}},J.JMember{"motion_children",J.JArray{b}}])))))

def transient_value(player:X.State) -> X.State & J.Value:
  X.State{motion,tables,X.Metadata{local,stored,sprint,pose,PC.Controller{+buttons,+look,+mouse,+options},entity, receiver, +error,tail},owned} = player
  (X.State{motion,tables,X.Metadata{local,stored,sprint,pose,PC.Controller{buttons,look,mouse,options},entity, receiver, error,tail},owned},Live.obj([
    J.JMember{"buttons",Live.uint(PI.mask(buttons))},J.JMember{"controls",Live.text(controller_show(PC.Controller{buttons,look,mouse,options}))},
    J.JMember{"last_error",Live.text(prior_error(error))}]))

def bindings() -> PI.Bindings:
  PI.Bindings{101,102,103,104,105,106,107}

def key_action(code:U32,down:Bool) -> CC.Action:
  CC.PlatformEvent{Key{code,down},True{}}

def buttons_packet(buttons:PI.Buttons) -> CC.Packet:
  PI.Buttons{forward,back,left,right,jump,shift,sprint} = buttons
  CC.Packet{[CC.Release{},key_action(101,forward),key_action(102,back),key_action(103,left),key_action(104,right),
    key_action(105,jump),key_action(106,shift),key_action(107,sprint)],True{},True{}}

def input_packet(mask:U32) -> CC.Packet:
  buttons_packet(PI.from_mask(mask))

def input_done(session:Live.Session,id:String,result:S.State & Result<&2,&2,String,Unit>) -> S.State & Live.Session & J.Value:
  match result:
    case (state,Done{unit}): S.success(state,session,id,Live.obj([J.JMember{"applied",Live.boolean(True{})}]))
    case (state,Fail{cause}): S.failure(state,session,id,Live.bad("FixtureInputFailed",cause))

def input_decoded(state:S.State,session:Live.Session,id:String,result:Result<&2,&2,Live.Fault,U32>) -> S.State & Live.Session & J.Value:
  match result:
    case Fail{fault}: S.failure(state,session,id,fault)
    case Done{mask}: input_done(session,id,S.input(state,bindings(),input_packet(mask)))

def read_result(session:Live.Session,id:String,result:S.State & J.Value) -> S.State & Live.Session & J.Value:
  (state,value) = result
  S.success(state,session,id,value)

def block_values(blocks:List<&2,CR.Block>) -> List<&2,J.Value>:
  match blocks:
    case Nil{}: []
    case CR.Block{x,y,z,state,material} <> rest:
      J.JArray{[Live.uint(Pose.raw(x)),Live.uint(Pose.raw(y)),Live.uint(Pose.raw(z)),Live.uint(state),Live.uint(material)]} <> block_values(rest)

def snapshot_value(value:CR.Snapshot) -> J.Value:
  CR.Snapshot{tick,revision,blocks,CR.Camera{x,y,z,yaw,pitch}} = value
  Live.obj([J.JMember{"tick",Live.natural(tick)},J.JMember{"revision",Live.natural(revision)},
    J.JMember{"camera",J.JArray{[Live.uint(Pose.raw(x)),Live.uint(Pose.raw(y)),Live.uint(Pose.raw(z)),Live.uint(Pose.raw(yaw)),Live.uint(Pose.raw(pitch))]}},
    J.JMember{"blocks",J.JArray{block_values(blocks)}}])

def snapshot_result(session:Live.Session,id:String,result:S.State & Result<&2,&2,String,CR.Snapshot>) -> S.State & Live.Session & J.Value:
  match result:
    case (state,Done{value}): S.success(state,session,id,snapshot_value(value))
    case (state,Fail{cause}): S.failure(state,session,id,Live.bad("FixtureSnapshotFailed",cause))

def fixture_run(state:S.State,session:Live.Session,id:String,op:String,args:J.Value) -> S.State & Live.Session & J.Value:
  match op:
    case "fixture.input": input_decoded(state,session,id,Live.get_number(args,"held_mask",False{}))
    case "fixture.release": S.success(S.release(state),session,id,Live.obj([J.JMember{"released",Live.boolean(True{})}]))
    case "fixture.transient": read_result(session,id,S.query(J.Value,state,transient_value))
    case "fixture.owners": read_result(session,id,S.query(J.Value,state,owner_report))
    case "fixture.snapshot": snapshot_result(session,id,S.snapshot(state,64,48))
    case _: S.failure(state,session,id,Live.bad("UnknownOperation","unknown explicit fixture operation"))

def fixture_allowed(state:S.State,session:Live.Session,id:String,op:String,args:J.Value,valid:Bool,allowed:Bool) -> S.State & Live.Session & J.Value:
  match valid allowed:
    case False{} _: S.failure(state,session,id,Live.bad("InvalidArguments","explicit fixture schema"))
    case True{} False{}: S.failure(state,session,id,Live.bad("PermissionDenied","developer fixture capability required"))
    case True{} True{}: fixture_run(state,session,id,op,args)

def fixture_schema(op:String) -> List<&2,Live.Field>:
  match op:
    case "fixture.input": [Live.Field{"held_mask",Live.Unsigned{0,127},True{}}]
    case _: []

def fixture_request(state:S.State,session:Live.Session,envelope:Live.Envelope) -> S.State & Live.Session & J.Value:
  Live.Session{+peer,sequence,+capability} = session
  Live.Envelope{id,+op,+args,at} = envelope
  fixture_allowed(S.observed(state,peer),Live.Session{peer,1n+sequence,capability},id,op,args,
    Live.validate_args(args,fixture_schema(op)) && Maybe.is_none(&2,Nat,at),C.developer(capability))

def fixture_operation(+op:String) -> Bool:
  String.eq(op,"fixture.input") || String.eq(op,"fixture.release") || String.eq(op,"fixture.transient") || String.eq(op,"fixture.owners") || String.eq(op,"fixture.snapshot")

def parsed_selected(state:S.State,session:Live.Session,token:String,request:J.Value,envelope:Live.Envelope,valid:Bool) -> IO(S.State & Live.Session & J.Value):
  match valid:
    case True{}: IO.pure(S.State & Live.Session & J.Value,fixture_request(state,session,envelope))
    case False{}: S.dispatch(~R.driver(),state,session,token,request)

def parsed(state:S.State,session:Live.Session,token:String,request:J.Value,result:Result<&2,&2,Live.Fault,Live.Envelope>) -> IO(S.State & Live.Session & J.Value):
  match result:
    case Done{+envelope}:
      Live.Envelope{id,op,args,at} = envelope
      parsed_selected(state,session,token,request,envelope,fixture_operation(op))
    case _: S.dispatch(~R.driver(),state,session,token,request)

def dispatch(state:S.State,session:Live.Session,token:String,+request:J.Value) -> IO(S.State & Live.Session & J.Value):
  parsed(state,session,token,request,Live.envelope(request))

def serve(first:U32,state:S.State) -> IO(Unit):
  Server.run_effectful_from_peer(~S.State,~Server.EffectfulDriver{state => S.realtime_step(R.driver(),state),state => session => token => request => dispatch(state,session,token,request)},state,first)

def child_table(tables:L.Tables,mark:U32) -> L.Tables:
  L.Tables{array} = tables
  L.Tables{Array.set(F32,array,1234,Pose.float_bits(mark))}

def child_world(+mark:U32,world:W.State) -> W.State:
  W.State{G.Engine{C.World{tick,time,paused,daylight,rev,count,sections,pending,events},registry},body,yaw,pitch,palette,region,cache} = world
  W.State{G.Engine{C.World{U32.to_nat(mark),U32.to_nat(U32.mul(mark,17)),True{},False{},U32.to_nat(U32.add(mark,5)),count,sections,
    [Q.Pending{Q.Stamp{1000n,mark,3n},C.TimeSet{U32.to_nat(U32.mul(mark,19))}}],events},registry},body,yaw,pitch,palette,region,cache}

def child_ready(+mark:U32,tables:L.Tables,result:W.State & Result<&2,&2,String,Unit>) -> IO(X.State):
  match result:
    case (world,Fail{cause}): IO.die(X.State,3,cause)
    case (world,Done{unit}): IO.pure(X.State,R.fresh(child_world(mark,world),child_table(tables,mark)))

def child_tables(mark:U32,result:Result<&2,&1,L.Error,L.Tables>) -> IO(X.State):
  match result:
    case Fail{cause}: IO.die(X.State,3,"explicit child table load")
    case Done{tables}:
      do IO<X.State>:
        engine:G.Engine <- G.load()
        child_ready(mark,tables,W.new(engine))

def child(mark:U32) -> IO(X.State):
  do IO<X.State>:
    tables:Result<&2,&1,L.Error,L.Tables> <- L.Tables.load("generated/reference_mth_sin.f32")
    child_tables(mark,tables)

def child_motion(state:X.State) -> MH.State:
  X.State{motion,tables,metadata,tail} = state
  motion

def pose_tail(pose:Pose.State) -> Pose.State:
  Pose.State{+value,+eye,tail} = pose
  Pose.State{value,eye,[Pose.State{value,eye,[]}]}

def forge(state:X.State,first:X.State,second:X.State,mode:String) -> X.State:
  X.State{MH.State{world,support,minor,history,motions},tables,+metadata,states} = state
  X.Metadata{local,stored,sprint,pose,controls,entity, receiver, error,tail} = metadata
  match mode:
    case "state-owners": X.State{MH.State{world,support,minor,history,motions},tables,metadata,[first,second]}
    case "motion-owners": X.State{MH.State{world,support,minor,history,[child_motion(first),child_motion(second)]},tables,metadata,states}
    case "metadata-owners": X.State{MH.State{world,support,minor,history,motions},tables,X.Metadata{local,stored,sprint,pose,controls,entity, receiver, error,[metadata]},states}
    case "pose-owners": X.State{MH.State{world,support,minor,history,motions},tables,X.Metadata{local,stored,sprint,pose_tail(pose),controls,entity, receiver, error,tail},states}
    case _: state

def initialized_values(player:X.State,shell:S.Shell,first:U32,+mode:String) -> IO(Unit):
  match mode:
    case "normal": serve(first,S.State{player,shell})
    case _:
      do IO<Unit>:
        a:X.State <- child(17)
        b:X.State <- child(29)
        serve(first,S.State{forge(player,a,b,mode),shell})

def initialized(mode:String,ready:S.Ready) -> IO(Unit):
  S.Ready{S.State{player,shell},first} = ready
  initialized_values(player,shell,first,mode)

def loaded(+mode:String,tables:L.Tables) -> IO(Unit):
  do IO<Unit>:
    stored:E.Ready<PR.Record> <- E.load_with(~PR.Record,~PS.codec(),~S.operations(),PS.limits())
    ready:S.Ready <- S.new(stored,tables)
    initialized(mode,ready)

def table_result(mode:String,result:Result<&2,&1,L.Error,L.Tables>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.die(Unit,2,"verified session sine table load failed")
    case Done{tables}: loaded(mode,tables)

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case exe <> "atomic" <> path <> suffix <> payload <> Nil{}: atomic(path,suffix,payload)
    case exe <> table <> mode <> Nil{}:
      do IO<Unit>:
        result:Result<&2,&1,L.Error,L.Tables> <- L.Tables.load(table)
        table_result(mode,result)
    case _: IO.die(Unit,2,"expected table/mode or atomic path suffix payload")

def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),arguments)
