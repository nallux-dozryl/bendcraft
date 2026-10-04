import Base
import ../src/player_block_inside_stuck.bend as Inside
import ../src/local_phase_runtime.bend as X
import ../src/local_move_history.bend as MH
import ../src/local_move_world.bend as LM
import ../src/local_input.bend as LI
import ../src/player_runtime.bend as PR
import ../src/player_tick.bend as PT
import ../src/player_pose.bend as P
import ../src/player_pose_world.bend as PW
import ../src/entity_common_tick.bend as ECT
import ../src/player_rotation_tick.bend as Rot
import ../src/player_controls.bend as PC
import ../src/player_input.bend as PI
import ../src/player_look.bend as PL
import ../src/mouse_input.bend as MI
import ../src/client_controls.bend as CC
import ../src/player_fall_history.bend as H
import ../src/local_collision_world.bend as E
import ../src/client_world.bend as W
import ../src/client_render.bend as R
import ../src/movement.bend as M
import ../src/geometry.bend as A
import ../src/f64.bend as F
import ../src/core.bend as C
import ../src/game.bend as G
import ../src/registry.bend as B
import ../src/schedule.bend as Q
import ../src/section.bend as S
import ../src/section_map.bend as SM
import ../src/locomotion.bend as L
import ../src/support.bend as SP
import ../src/travel.bend as T

# Raw fixtures below are serialized independent actual receiver observations.
# Expected gameplay is never calculated in this harness.
type Slot<-T: Data> is Data:
  Slot{value:T,tail:List<&2,Slot<T>>}

def slot_value(-T:Data,slot:Slot<T>) -> T:
  Slot{value,tail} = slot
  value

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
      W.paired(S.Section,List<&2,U32>,List<&1,SM.Entry> & String,S.Section.snapshot(section),
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

def report_sections(+id:String,+saved:Slot<W.View>,registry:B.Registry,
                    tick:Nat,time:Nat,paused:Bool,daylight:Bool,revision:Nat,count:U32,
                    pending:List<&2,Q.Pending<C.Mutation>>,events:List<&2,C.CoreEvent>,
                    result:SM.Sections & String) -> IO(W.State):
  (sections,text) = result
  IO.bind(Unit,W.State,IO.print(id ++ "|sections|" ++ text),unit =>
    IO.pure(W.State,W.attach(G.Engine{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},registry},slot_value(W.View,saved))))

def f64_show(value: F.F64) -> String:
  F.F64{hi, lo} = value
  U32.show(hi) ++ "|" ++ U32.show(lo)

def vector_show(value: M.Vec3) -> String:
  M.Vec3{x, y, z} = value
  f64_show(x) ++ "|" ++ f64_show(y) ++ "|" ++ f64_show(z)

def box_show(value: A.AABB) -> String:
  A.AABB{a, b, c, d, e, f} = value
  f64_show(a) ++ "|" ++ f64_show(b) ++ "|" ++ f64_show(c) ++ "|" ++ f64_show(d) ++ "|" ++ f64_show(e) ++ "|" ++ f64_show(f)

def body_show(value: M.Body) -> String:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = value
  vector_show(position) ++ "|" ++ box_show(box) ++ "|" ++ vector_show(velocity) ++ "|" ++ U32.show(P.raw(width)) ++ "|" ++ U32.show(P.raw(height)) ++ "|" ++ U32.show(Bool.to_u32(ground)) ++ "|" ++ U32.show(Bool.to_u32(horizontal)) ++ "|" ++ U32.show(Bool.to_u32(vertical)) ++ "|" ++ U32.show(Bool.to_u32(below))

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

def report_engine(+id:String,engine:G.Engine,+saved:Slot<W.View>) -> IO(W.State):
  G.Engine{C.World{+tick,+time,+paused,+daylight,+revision,+count,sections,+pending,+events},registry} = engine
  do IO<W.State>:
    IO.print(id ++ "|body|" ++ body_show(E.view_body(slot_value(W.View,saved))))
    IO.print(id ++ "|clock|" ++ Nat.show(tick) ++ "|" ++ Nat.show(time) ++ "|" ++ flag(paused) ++ "|" ++ flag(daylight) ++ "|" ++ Nat.show(revision) ++ "|" ++ Nat.show(Q.length(C.Mutation,pending)) ++ "|" ++ Nat.show(List.length(&2,C.CoreEvent,events)) ++ "|" ++ U32.show(count))
    IO.print(id ++ "|queue|" ++ pending_show(pending) ++ "|" ++ events_show(events))
    IO.print(id ++ "|view|" ++ view(slot_value(W.View,saved)))
    report_sections(id,saved,registry,tick,time,paused,daylight,revision,count,pending,events,sections_snapshot(sections))

def report_taken(id:String,result:G.Engine & W.View) -> IO(W.State):
  (engine,view) = result
  report_engine(id,engine,Slot{view,[]})

def report(id:String,world:W.State) -> IO(W.State):
  report_taken(id,W.take(world))

def reads(values: List<&2, E.Read>) -> String:
  match values:
    case Nil{}: ""
    case E.Read{point, state} <> rest: position(point) ++ "," ++ U32.show(state) ++ ";" ++ reads(rest)

def yielded(value: Maybe<&2, A.AABB>) -> String:
  match value:
    case None{}: "none"
    case Some{box}: box_show(box)

def mutation_done(registry:B.Registry,saved:Slot<W.View>,result:C.World & Result<&2,&2,C.Error,Unit>) -> IO(W.State):
  match result:
    case (world,Done{unit}): IO.pure(W.State,W.attach(G.Engine{world,registry},slot_value(W.View,saved)))
    case (world,Fail{cause}): IO.die(W.State,3,"player-pose-world mutation:" ++ W.error_text(cause))

def mutation_done_allow_exists(registry:B.Registry,saved:Slot<W.View>,result:C.World & Result<&2,&2,C.Error,Unit>) -> IO(W.State):
  match result:
    case (world,Fail{C.SectionExists{key}}): IO.pure(W.State,W.attach(G.Engine{world,registry},slot_value(W.View,saved)))
    case other: mutation_done(registry,saved,other)

def mutate_world(world:W.State,mutation:C.Mutation) -> IO(W.State):
  W.State{G.Engine{core,registry},body,yaw,pitch,palette,region,cache} = world
  mutation_done(registry,Slot{W.View{body,yaw,pitch,palette,region,cache},[]},C.apply(core,mutation))

def section(world:W.State,x:U32,y:U32,z:U32) -> IO(W.State):
  match world:
    case W.State{G.Engine{core,registry},body,yaw,pitch,Some{W.Palette{+air,+stone,+dirt,+planks}},region,cache}:
      mutation_done_allow_exists(registry,Slot{W.View{body,yaw,pitch,Some{W.Palette{air,stone,dirt,planks}},region,cache},[]},
        C.apply(core,C.SectionCreate{C.Position{"minecraft:overworld",x,y,z},air}))
    case _: IO.die(W.State,3,"player-pose-world section needs palette")

def edit_value(world: W.State, x: U32, y: U32, z: U32, value: U32) -> IO(W.State):
  mutate_world(world, C.BlockSet{C.Position{"minecraft:overworld", x, y, z}, value})

def edit_resolved(x:U32,y:U32,z:U32,core:C.World,saved:Slot<W.View>,
                  result:B.Registry & Result<&2,&2,String,U32>) -> IO(W.State):
  match result:
    case (registry,Fail{error}): IO.die(W.State,3,"player-pose-world edit:" ++ error)
    case (registry,Done{value}): edit_value(W.attach(G.Engine{core,registry},slot_value(W.View,saved)),x,y,z,value)

def snapshot_kept(result: W.State & Result<&2, &2, String, R.Snapshot>) -> IO(W.State):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(W.State, 3, "local-collision-world snapshot:" ++ error)
    case Done{snapshot}: IO.pure(W.State, world)

def held_pending(world: W.State) -> IO(W.State):
  W.State{G.Engine{core, registry}, body, yaw, pitch, palette, region, cache} = world
  mutation_done(registry, Slot{W.View{body, yaw, pitch, palette, region, cache}, []},
    C.admit(core, C.Developer{}, Q.Stamp{100n, 9, 0n}, C.TimeSet{999n}))

def section_setup(n: Nat, +index: U32, +air: U32, world: W.State) -> IO(W.State):
  match n:
    case 0n: IO.pure(W.State, world)
    case 1n+rest:
      x = W.choose(U32, 0, 4294967280, U32.is_eq(U32.and(index, 1), 0))
      y = W.choose(U32, 0, 4294967280, U32.is_eq(U32.and(index, 2), 0))
      z = W.choose(U32, 0, 4294967280, U32.is_eq(U32.and(index, 4), 0))
      do IO<W.State>:
        next : W.State <- mutate_world(world, C.SectionCreate{C.Position{"minecraft:overworld", x, y, z}, air})
        section_setup(rest, U32.inc(index), air, next)

def floor_setup(n: Nat, +index: U32, +stone: U32, world: W.State) -> IO(W.State):
  match n:
    case 0n: IO.pure(W.State, world)
    case 1n+rest:
      x = U32.add(4294967294, U32.mod(index, 5))
      z = U32.add(4294967294, U32.div(index, 5))
      do IO<W.State>:
        next : W.State <- mutate_world(world, C.BlockSet{C.Position{"minecraft:overworld", x, 0, z}, stone})
        floor_setup(rest, U32.inc(index), stone, next)

def fixture_palette(world: W.State, palette: W.Palette) -> IO(W.State):
  W.Palette{air, stone, dirt, planks} = palette
  do IO<W.State>:
    sections : W.State <- section_setup(8n, 0, air, world)
    floor_setup(25n, 0, stone, sections)

type Seed is Data:
  Seed{body:M.Body,metadata:X.Metadata,support:SP.State,
    minor:LM.MinorState,history:H.History,tail:List<&2,Seed>}

type Step is Data:
  Step{id:String,held:PI.Buttons,request:X.Request,operation:U32,
    tail:List<&2,Step>}

type Scenario is Data:
  Scenario{id:String,seed:Seed,steps:List<&2,Step>,wall:Bool,
    tail:List<&2,Scenario>}

def buttons_word(keys: PI.Buttons) -> U32:
  PI.Buttons{forward,back,left,right,jump,shift,sprint} = keys
  U32.add(Bool.to_u32(forward),U32.add(U32.mul(Bool.to_u32(back),2),
    U32.add(U32.mul(Bool.to_u32(left),4),U32.add(U32.mul(Bool.to_u32(right),8),
    U32.add(U32.mul(Bool.to_u32(jump),16),U32.add(U32.mul(Bool.to_u32(shift),32),U32.mul(Bool.to_u32(sprint),64)))))))

def bools(values:List<&2,Bool>) -> String:
  match values:
    case Nil{}: ""
    case value <> rest: flag(value) ++ "," ++ bools(rest)

def pose_states(values:List<&2,P.State>) -> String:
  match values:
    case Nil{}: ""
    case P.State{pose,eye,tail} <> rest:
      U32.show(P.pose_id(pose)) ++ "," ++ U32.show(P.raw(eye)) ++ "[" ++ pose_states(tail) ++ "]/" ++ pose_states(rest)

def local_show(value:LI.State) -> String:
  LI.State{keys,PI.Vector{x,z},trigger,crouch,bx,by,ox,oy} = value
  U32.show(buttons_word(keys)) ++ "|" ++ U32.show(P.raw(x)) ++ "|" ++ U32.show(P.raw(z)) ++ "|" ++
    U32.show(trigger) ++ "|" ++ flag(crouch) ++ "|" ++ U32.show(P.raw(bx)) ++ "|" ++ U32.show(P.raw(by)) ++ "|" ++ U32.show(P.raw(ox)) ++ "|" ++ U32.show(P.raw(oy))

def player_show(value:PR.Metadata) -> String:
  PR.Metadata{PT.Input{x,y,z},jump,delay,trigger,sync,speed,head} = value
  U32.show(P.raw(x)) ++ "|" ++ U32.show(P.raw(y)) ++ "|" ++ U32.show(P.raw(z)) ++ "|" ++ flag(jump) ++ "|" ++
    U32.show(delay) ++ "|" ++ U32.show(trigger) ++ "|" ++ flag(sync) ++ "|" ++ U32.show(P.raw(speed)) ++ "|" ++ U32.show(P.raw(head))

def look_show(value:PL.State) -> String:
  PL.State{yaw,pitch,oldyaw,oldpitch} = value
  U32.show(P.raw(yaw)) ++ "|" ++ U32.show(P.raw(pitch)) ++ "|" ++ U32.show(P.raw(oldyaw)) ++ "|" ++ U32.show(P.raw(oldpitch))

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

def owned_tail_tags(values:List<&1,X.State>) -> List<&1,X.State> & String:
  match values:
    case Nil{}: ([],"")
    case X.State{motion,tables,+metadata,tail} <> rest:
      W.paired(List<&1,X.State>,String,List<&1,X.State> & String,owned_tail_tags(rest),
        next => tags => (X.State{motion,tables,metadata,tail} <> next,metadata_list([metadata]) ++ "#" ++ tags))

def motion_tail_tags(values:List<&1,MH.State>) -> List<&1,MH.State> & String:
  match values:
    case Nil{}: ([],"")
    case MH.State{world,+support,LM.MinorState{+minor},H.State{+history},tail} <> rest:
      W.paired(List<&1,MH.State>,String,List<&1,MH.State> & String,motion_tail_tags(rest),
        next => tags => (MH.State{world,support,LM.MinorState{minor},H.State{history},tail} <> next,
          support_show(support) ++ "," ++ flag(minor) ++ "," ++ f64_show(MH.history_distance(history)) ++ "#" ++ tags))

def state_report_world(+id:String,tables:L.Tables,+metadata:X.Metadata,
                       tail:List<&1,X.State>,+support:SP.State,+minor:LM.MinorState,
                       +history:H.History,owned:List<&1,MH.State>,world:W.State) -> IO(X.State):
  LM.MinorState{flag_minor} = minor
  do IO<X.State>:
    IO.print(id ++ "|metadata|" ++ metadata_list([metadata]))
    IO.print(id ++ "|support|" ++ support_show(support))
    IO.print(id ++ "|minor|" ++ flag(flag_minor))
    IO.print(id ++ "|history|" ++ f64_show(MH.history_distance(history)))
    next:W.State <- report(id,world)
    return X.State{MH.State{next,support,minor,H.State{history},owned},tables,metadata,tail}

def state_report_owned(+id:String,world:W.State,tables:L.Tables,metadata:X.Metadata,
                       +support:SP.State,+minor:LM.MinorState,+history:H.History,
                       tail:List<&1,X.State>,result:List<&1,MH.State> & String) -> IO(X.State):
  (owned,tags) = result
  do IO<X.State>:
    IO.print(id ++ "|motion-tail|" ++ tags)
    state_report_world(id,tables,metadata,tail,support,minor,history,owned,world)

def state_report_tails(+id:String,world:W.State,tables:L.Tables,metadata:X.Metadata,
                       support:SP.State,minor:LM.MinorState,history:H.History,
                       owned:List<&1,MH.State>,result:List<&1,X.State> & String) -> IO(X.State):
  (tail,tags) = result
  do IO<X.State>:
    IO.print(id ++ "|state-tail|" ++ tags)
    state_report_owned(id,world,tables,metadata,support,minor,history,tail,motion_tail_tags(owned))


def table_report(id:String,result:L.Tables & F32) -> IO(L.Tables):
  (tables,value) = result
  do IO<L.Tables>:
    IO.print(id ++ "|table-sample|" ++ U32.show(P.raw(value)))
    return tables

# These fixture children are canonical leaves. Reporting them separately avoids
# introducing mutually recursive IO through the production owner type.
def state_child_report(+id:String,state:X.State) -> IO(X.State):
  X.State{MH.State{world,support,minor,H.State{history},owned},tables,metadata,tail} = state
  do IO<X.State>:
    next:L.Tables <- table_report(id,L.Tables.at(tables,1234))
    state_report_tails(id,world,next,metadata,support,minor,history,owned,owned_tail_tags(tail))

def state_children_report(+id:String,values:List<&1,X.State>,+index:Nat) -> IO(List<&1,X.State>):
  match values:
    case Nil{}: IO.pure(List<&1,X.State>,[])
    case child <> rest:
      do IO<List<&1,X.State>>:
        next:X.State <- state_child_report(id ++ ":owned:" ++ Nat.show(index),child)
        remaining:List<&1,X.State> <- state_children_report(id,rest,(index+1n : Nat))
        return next <> remaining

def motion_child_returned(+id:String,world:W.State,support:SP.State,minor:Bool,history:H.History,
                         result:List<&1,MH.State> & String) -> IO(MH.State):
  (tail,tags) = result
  do IO<MH.State>:
    IO.print(id ++ "|motion-tail|" ++ tags)
    return MH.State{world,support,LM.MinorState{minor},H.State{history},tail}


def motion_child_report(+id:String,motion:MH.State) -> IO(MH.State):
  MH.State{world,+support,LM.MinorState{+minor},H.State{+history},tail} = motion
  do IO<MH.State>:
    IO.print(id ++ "|support|" ++ support_show(support))
    IO.print(id ++ "|minor|" ++ flag(minor))
    IO.print(id ++ "|history|" ++ f64_show(MH.history_distance(history)))
    next:W.State <- report(id,world)
    motion_child_returned(id,next,support,minor,history,motion_tail_tags(tail))


def motion_children_report(+id:String,values:List<&1,MH.State>,+index:Nat) -> IO(List<&1,MH.State>):
  match values:
    case Nil{}: IO.pure(List<&1,MH.State>,[])
    case child <> rest:
      do IO<List<&1,MH.State>>:
        next:MH.State <- motion_child_report(id ++ ":motion-owned:" ++ Nat.show(index),child)
        remaining:List<&1,MH.State> <- motion_children_report(id,rest,(index+1n : Nat))
        return next <> remaining

def state_report(+id:String,state:X.State) -> IO(X.State):
  X.State{MH.State{world,support,minor,H.State{history},owned},tables,metadata,tail} = state
  do IO<X.State>:
    children:List<&1,X.State> <- state_children_report(id,tail,0n)
    motions:List<&1,MH.State> <- motion_children_report(id,owned,0n)
    next:L.Tables <- table_report(id,L.Tables.at(tables,1234))
    state_report_tails(id,world,next,metadata,support,minor,history,motions,owned_tail_tags(children))


def error_show(error:X.Error) -> String:
  match error:
    case X.NonCanonicalState{field}: "state-tail:" ++ U32.show(field)
    case X.NonCanonicalRequest{}: "request-tail"
    case X.LifecycleError{field}: "lifecycle:" ++ U32.show(field)
    case X.EntityError{cause}: "entity"
    case X.ControllerError{cause}: "controller"
    case X.PoseError{cause}: "pose"
    case X.UnsupportedStablePose{}: "unsupported-stable-pose"
    case X.ControlWorldError{cause}: "control-world:" ++ E.error_text(cause)
    case X.ControlBudget{}: "control-budget"
    case X.InputError{LI.SprintContextMismatch{}}: "input-sprint-context"
    case X.InputError{cause}: "input"
    case X.SprintSetterMismatch{}: "setter-mismatch"
    case X.TravelError{cause}: "travel"
    case X.FinishError{cause}: "finish"
    case X.BlockInsideError{cause}: "block-inside"
    case X.RotationError{cause}: "rotation"
    case X.PoseWorldError{cause}: "late-pose"
    case X.ViewError{reason}: "view:" ++ reason

def queries(+id:String,+phase:String,values:List<&2,PW.QueryRecord>,+index:Nat) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case PW.QueryRecord{pose,E.QueryRecord{box,clear,hit,observed}} <> rest:
      do IO<Unit>:
        IO.print(id ++ "|" ++ phase ++ "|" ++ Nat.show(index) ++ "|" ++ U32.show(P.pose_id(pose)) ++ "|" ++ box_show(box) ++ "|" ++ flag(clear))
        queries(id,phase,rest,1n+index)

def status_report(+id:String,status:Result<&2,&2,X.Error,X.Observation>) -> IO(Unit):
  match status:
    case Fail{cause}: IO.print(id ++ "|error|" ++ error_show(cause))
    case Done{X.Observation{early,updates,attempted,jumped,late,eye,tail}}:
      do IO<Unit>:
        IO.print(id ++ "|ok|" ++ bools(updates) ++ "|" ++ flag(attempted) ++ "|" ++ flag(jumped))
        IO.print(id ++ "|eye|" ++ vector_show(eye))
        queries(id,"early",early,0n)
        queries(id,"late",late,0n)

def result_report(+id:String,result:X.State & Result<&2,&2,X.Error,X.Observation>) -> IO(X.State):
  (state,status) = result
  do IO<X.State>:
    status_report(id,status)
    state_report(id ++ "-after",state)

def physical(metadata:X.Metadata,held:PI.Buttons) -> X.Metadata:
  X.Metadata{local,player,sprint,pose,PC.Controller{old,look,mouse,options},entity, receiver, error,tail} = metadata
  X.Metadata{local,player,sprint,pose,PC.Controller{held,look,mouse,options},entity, receiver, error,tail}

def held(state:X.State,buttons:PI.Buttons) -> X.State:
  X.State{motion,tables,metadata,tail} = state
  X.State{motion,tables,physical(metadata,buttons),tail}

def operation(mode:U32,state:X.State,request:X.Request) -> X.State & Result<&2,&2,X.Error,X.Observation>:
  match mode:
    case 0: X.local_checked(state,request)
    case _: X.scheduled_checked(state,request)

def pulse_report(+id:String,result:X.State & Result<&2,&2,X.Error,Maybe<&2,X.Observation>>) -> IO(X.State):
  (state,status) = result
  match status:
    case Fail{cause}:
      do IO<X.State>:
        IO.print(id ++ "|error|" ++ error_show(cause))
        state_report(id ++ "-after",state)
    case Done{None{}}:
      do IO<X.State>:
        IO.print(id ++ "|paused|true")
        state_report(id ++ "-after",state)
    case Done{Some{observation}}: result_report(id,(state,Done{observation}))

def packet_report(+id:String,result:X.State & Result<&2,&2,X.Error,Unit>) -> IO(X.State):
  (state,status) = result
  match status:
    case Fail{cause}:
      do IO<X.State>:
        IO.print(id ++ "|packet-error|" ++ error_show(cause))
        state_report(id ++ "-after",state)
    case Done{unit}:
      do IO<X.State>:
        IO.print(id ++ "|packet-done|true")
        state_report(id ++ "-after",state)

def queried_report(+id:String,result:X.State & Result<&2,&2,String,R.Snapshot>) -> IO(X.State):
  (state,status) = result
  do IO<X.State>:
    IO.print(id ++ "|queried|true")
    state_report(id ++ "-after",state)

def eye_report(+id:String,result:X.State & Result<&2,&2,P.Error,M.Vec3>) -> IO(X.State):
  (state,status) = result
  match status:
    case Fail{cause}: IO.die(X.State,3,"runtime eye query failed")
    case Done{eye}:
      do IO<X.State>:
        IO.print(id ++ "|read-eye|" ++ vector_show(eye))
        state_report(id ++ "-after",state)

def tick_selected(mode:U32,+id:String,state:X.State,request:X.Request) -> IO(X.State):
  match mode:
    case 2: pulse_report(id,X.realtime_checked(state,request))
    case 3: state_report(id ++ "-after",X.release(state))
    case 4: packet_report(id,X.input_checked(state,PI.Bindings{1,2,3,4,5,6,7},
      CC.Packet{[CC.PlatformEvent{Key{1,True{}},True{}},CC.PlatformEvent{Look{P.float_bits(2143289344),0.0},True{}}],True{},True{}}))
    case 5: packet_report(id,X.input_checked(state,PI.Bindings{1,2,3,4,5,6,7},
      CC.Packet{[CC.PlatformEvent{Key{1,True{}},True{}}],True{},True{}}))
    case 6: queried_report(id,X.query(Result<&2,&2,String,R.Snapshot>,state,world => W.snapshot(world,64,48)))
    case 7: eye_report(id,X.eye_position_checked(state))
    case _: result_report(id,operation(mode,state,request))

def held_for_step(mode:U32,state:X.State,buttons:PI.Buttons) -> X.State:
  match mode:
    case 6: state
    case _: held(state,buttons)

def tick_one(state:X.State,step:Step) -> IO(X.State):
  Step{+id,buttons,request,+mode,tail} = step
  do IO<X.State>:
    before:X.State <- state_report(id ++ "-before",held_for_step(mode,state,buttons))
    tick_selected(mode,id,before,request)

def run_steps(steps:List<&2,Step>,state:X.State) -> IO(X.State):
  match steps:
    case Nil{}: IO.pure(X.State,state)
    case step <> rest:
      do IO<X.State>:
        next:X.State <- tick_one(state,step)
        run_steps(rest,next)

def installed_seed(tables:L.Tables,seed:Seed,result:G.Engine & W.View) -> X.State:
  Seed{body,+metadata,support,minor,history,tail} = seed
  (engine,W.View{old,yaw,pitch,palette,region,cache}) = result
  +look = PR.look(X.controls(metadata))
  X.State{MH.State{W.attach(engine,W.View{body,PL.mul(X.yaw(look),PL.float_bits(1016003125)),PL.mul(X.pitch(look),PL.float_bits(1016003125)),palette,region,cache}),support,minor,H.State{history},[]},tables,metadata,[]}

def seed_world(tables:L.Tables,seed:Seed,world:W.State) -> X.State:
  installed_seed(tables,seed,W.take(world))

def fixture_wall(wall:Bool,world:W.State) -> IO(W.State):
  match wall world:
    case False{} _: IO.pure(W.State,world)
    case True{} W.State{engine,body,yaw,pitch,Some{W.Palette{air,+stone,dirt,planks}},region,cache}:
      mutate_world(W.State{engine,body,yaw,pitch,Some{W.Palette{air,stone,dirt,planks}},region,cache},C.BlockSet{C.Position{"minecraft:overworld",1,1,0},stone})
    case True{} _: IO.die(W.State,3,"runtime fixture missing palette")

def due_wall(world:W.State) -> IO(W.State):
  match world:
    case W.State{G.Engine{core,registry},body,yaw,pitch,Some{W.Palette{air,+stone,dirt,planks}},region,cache}:
      mutation_done(registry,Slot{W.View{body,yaw,pitch,Some{W.Palette{air,stone,dirt,planks}},region,cache},[]},
        C.admit(core,C.Developer{},Q.Stamp{1n,8,1n},C.BlockSet{C.Position{"minecraft:overworld",0,2,0},stone}))
    case _: IO.die(W.State,3,"runtime due wall needs palette")

def fixture_extra(id:String,world:W.State) -> IO(W.State):
  match id world:
    case "owner-child-first" _: mutate_world(world,C.TimeSet{321n})
    case "owner-child-second" _: mutate_world(world,C.TimeSet{654n})
    case "policy:crawl" W.State{engine,body,yaw,pitch,Some{W.Palette{air,+stone,dirt,planks}},region,cache}:
      mutate_world(W.State{engine,body,yaw,pitch,Some{W.Palette{air,stone,dirt,planks}},region,cache},C.BlockSet{C.Position{"minecraft:overworld",0,2,0},stone})
    case "policy:due-crawl" _: due_wall(world)
    case "policy:paused" W.State{G.Engine{core,registry},body,yaw,pitch,palette,region,cache}:
      IO.pure(W.State,W.State{G.Engine{C.set_paused(core,True{}),registry},body,yaw,pitch,palette,region,cache})
    case "policy:missing-section" W.State{G.Engine{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},registry},body,yaw,pitch,palette,region,cache}:
      IO.pure(W.State,W.State{G.Engine{C.World{tick,time,paused,daylight,revision,count,SM.EmptySections{},pending,events},registry},body,yaw,pitch,palette,region,cache})
    case _ _: IO.pure(W.State,world)










def tables_returned(state:X.State) -> L.Tables:
  X.State{motion,tables,metadata,tail} = state
  tables


def seed_0() -> Seed:
  Seed{M.Body{M.Vec3{F.F64{1071644672, 0}, F.F64{1072693248, 0}, F.F64{1071644672, 0}}, A.AABB{F.F64{1070176665, 2147483648}, F.F64{1072693248, 0}, F.F64{1070176665, 2147483648}, F.F64{1072273817, 2684354560}, F.F64{1074161254, 1610612736}, F.F64{1072273817, 2684354560}}, M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, P.float_bits(1058642330), P.float_bits(1072064102), True{}, False{}, False{}, False{}}, X.Metadata{LI.State{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PI.Vector{P.float_bits(0), P.float_bits(0)}, 0, False{}, P.float_bits(1073741824), P.float_bits(3225419776), P.float_bits(1082130432), P.float_bits(3231711232)}, PR.Metadata{PT.Input{P.float_bits(0), P.float_bits(0), P.float_bits(0)}, False{}, 0, 0, False{}, P.float_bits(1039918957), P.float_bits(1099431936)}, False{}, P.State{P.Standing{}, P.float_bits(1070554153), []}, PC.Controller{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PL.State{P.float_bits(1099431936), P.float_bits(3241148416), P.float_bits(1094713344), P.float_bits(3239051264)}, MI.initial(), MI.default_options()}, ECT.Metadata{M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, 0, 0}, Inside.empty(), None{}, []}, SP.State{Some{T.BlockPos{0, 0, 0}}, False{}}, LM.MinorState{False{}}, H.History{F.F64{0, 0}}, []}

def request_0_0() -> X.Request:
  X.Request{X.NeutralDryLoadedNoParticles{}, ECT.NeutralClientInactiveInterpolation{}, X.ControlFacts{20, LI.Abilities{False{}, False{}}, False{}, 7, LI.Neutral{}}, X.ApplyFacts{T.GroundSample{T.BlockPos{0, 0, 0}, P.float_bits(1058642330)}, T.Attributes{F.F64{1069128089, 2684354560}, F.F64{1068792545, 1202590843}, F.F64{1072693248, 0}, F.F64{1072693248, 0}}, P.float_bits(1058642330), False{}, False{}, False{}, T.NeutralDryAir{}, F.F64{1071309127, 2684354560}, P.float_bits(1065353216), True{}, PT.Neutral{}, F.F64{1070805811, 858993459}}, E.Environment{E.KnownEmptyEntityCollisions{}, E.KnownClearBorderInterior{A.AABB{F.F64{3225419776, 0}, F.F64{3224371200, 0}, F.F64{3225419776, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}}}}, 2n, 64n, 64n, 3n, []}

def request_0_1() -> X.Request:
  X.Request{X.NeutralDryLoadedNoParticles{}, ECT.NeutralClientInactiveInterpolation{}, X.ControlFacts{20, LI.Abilities{False{}, False{}}, False{}, 7, LI.Neutral{}}, X.ApplyFacts{T.GroundSample{T.BlockPos{0, 0, 0}, P.float_bits(1058642330)}, T.Attributes{F.F64{1069128089, 2684354560}, F.F64{1068792545, 1202590843}, F.F64{1072693248, 0}, F.F64{1072693248, 0}}, P.float_bits(1058642330), False{}, False{}, False{}, T.NeutralDryAir{}, F.F64{1071309127, 2684354560}, P.float_bits(1065353216), True{}, PT.Neutral{}, F.F64{1070805811, 858993459}}, E.Environment{E.KnownEmptyEntityCollisions{}, E.KnownClearBorderInterior{A.AABB{F.F64{3225419776, 0}, F.F64{3224371200, 0}, F.F64{3225419776, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}}}}, 2n, 64n, 64n, 3n, []}

def request_0_2() -> X.Request:
  X.Request{X.NeutralDryLoadedNoParticles{}, ECT.NeutralClientInactiveInterpolation{}, X.ControlFacts{20, LI.Abilities{False{}, False{}}, False{}, 7, LI.Neutral{}}, X.ApplyFacts{T.GroundSample{T.BlockPos{0, 0, 0}, P.float_bits(1058642330)}, T.Attributes{F.F64{1069128089, 2684354560}, F.F64{1068792545, 1202590843}, F.F64{1072693248, 0}, F.F64{1072693248, 0}}, P.float_bits(1058642330), False{}, False{}, False{}, T.NeutralDryAir{}, F.F64{1071309127, 2684354560}, P.float_bits(1065353216), True{}, PT.Neutral{}, F.F64{1070805811, 858993459}}, E.Environment{E.KnownEmptyEntityCollisions{}, E.KnownClearBorderInterior{A.AABB{F.F64{3225419776, 0}, F.F64{3224371200, 0}, F.F64{3225419776, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}}}}, 2n, 64n, 64n, 3n, []}

def request_0_3() -> X.Request:
  X.Request{X.NeutralDryLoadedNoParticles{}, ECT.NeutralClientInactiveInterpolation{}, X.ControlFacts{20, LI.Abilities{False{}, False{}}, False{}, 7, LI.Neutral{}}, X.ApplyFacts{T.GroundSample{T.BlockPos{0, 0, 0}, P.float_bits(1058642330)}, T.Attributes{F.F64{1069128089, 2684354560}, F.F64{1068792545, 1202590843}, F.F64{1072693248, 0}, F.F64{1072693248, 0}}, P.float_bits(1058642330), False{}, False{}, False{}, T.NeutralDryAir{}, F.F64{1071309127, 2684354560}, P.float_bits(1065353216), True{}, PT.Neutral{}, F.F64{1070805811, 858993459}}, E.Environment{E.KnownEmptyEntityCollisions{}, E.KnownClearBorderInterior{A.AABB{F.F64{3225419776, 0}, F.F64{3224371200, 0}, F.F64{3225419776, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}}}}, 2n, 64n, 64n, 3n, []}

def scenario_0() -> Scenario:
  Scenario{"scheduled_shift", seed_0(), [Step{"scheduled_shift:0", PI.Buttons{False{}, False{}, False{}, False{}, False{}, True{}, False{}}, request_0_0(), 1, []}, Step{"scheduled_shift:1", PI.Buttons{False{}, False{}, False{}, False{}, False{}, True{}, False{}}, request_0_1(), 1, []}, Step{"scheduled_shift:2", PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, request_0_2(), 1, []}, Step{"scheduled_shift:3", PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, request_0_3(), 1, []}], False{}, []}

def seed_1() -> Seed:
  Seed{M.Body{M.Vec3{F.F64{1071644672, 0}, F.F64{1072693248, 0}, F.F64{1071644672, 0}}, A.AABB{F.F64{1070176665, 2147483648}, F.F64{1072693248, 0}, F.F64{1070176665, 2147483648}, F.F64{1072273817, 2684354560}, F.F64{1074161254, 1610612736}, F.F64{1072273817, 2684354560}}, M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, P.float_bits(1058642330), P.float_bits(1072064102), True{}, False{}, False{}, False{}}, X.Metadata{LI.State{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PI.Vector{P.float_bits(0), P.float_bits(0)}, 0, False{}, P.float_bits(1073741824), P.float_bits(3225419776), P.float_bits(1082130432), P.float_bits(3231711232)}, PR.Metadata{PT.Input{P.float_bits(0), P.float_bits(0), P.float_bits(0)}, False{}, 0, 0, False{}, P.float_bits(1039918957), P.float_bits(1099431936)}, False{}, P.State{P.Standing{}, P.float_bits(1070554153), []}, PC.Controller{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PL.State{P.float_bits(1099431936), P.float_bits(3241148416), P.float_bits(1144537088), P.float_bits(1135509504)}, MI.initial(), MI.default_options()}, ECT.Metadata{M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, 0, 40}, Inside.empty(), None{}, []}, SP.State{Some{T.BlockPos{0, 0, 0}}, False{}}, LM.MinorState{False{}}, H.History{F.F64{0, 0}}, []}

def request_1_0() -> X.Request:
  X.Request{X.NeutralDryLoadedNoParticles{}, ECT.NeutralClientInactiveInterpolation{}, X.ControlFacts{20, LI.Abilities{False{}, False{}}, False{}, 7, LI.Neutral{}}, X.ApplyFacts{T.GroundSample{T.BlockPos{0, 0, 0}, P.float_bits(1058642330)}, T.Attributes{F.F64{1069128089, 2684354560}, F.F64{1068792545, 1202590843}, F.F64{1072693248, 0}, F.F64{1072693248, 0}}, P.float_bits(1058642330), False{}, False{}, False{}, T.NeutralDryAir{}, F.F64{1071309127, 2684354560}, P.float_bits(1065353216), True{}, PT.Neutral{}, F.F64{1070805811, 858993459}}, E.Environment{E.KnownEmptyEntityCollisions{}, E.KnownClearBorderInterior{A.AABB{F.F64{3225419776, 0}, F.F64{3224371200, 0}, F.F64{3225419776, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}}}}, 2n, 64n, 64n, 3n, []}

def request_1_1() -> X.Request:
  X.Request{X.NeutralDryLoadedNoParticles{}, ECT.NeutralClientInactiveInterpolation{}, X.ControlFacts{20, LI.Abilities{False{}, False{}}, False{}, 7, LI.Neutral{}}, X.ApplyFacts{T.GroundSample{T.BlockPos{0, 0, 0}, P.float_bits(1058642330)}, T.Attributes{F.F64{1069128089, 2684354560}, F.F64{1068792545, 1202590843}, F.F64{1072693248, 0}, F.F64{1072693248, 0}}, P.float_bits(1058642330), False{}, False{}, False{}, T.NeutralDryAir{}, F.F64{1071309127, 2684354560}, P.float_bits(1065353216), True{}, PT.Neutral{}, F.F64{1070805811, 858993459}}, E.Environment{E.KnownEmptyEntityCollisions{}, E.KnownClearBorderInterior{A.AABB{F.F64{3225419776, 0}, F.F64{3224371200, 0}, F.F64{3225419776, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}}}}, 2n, 64n, 64n, 3n, []}

def request_1_2() -> X.Request:
  X.Request{X.NeutralDryLoadedNoParticles{}, ECT.NeutralClientInactiveInterpolation{}, X.ControlFacts{20, LI.Abilities{False{}, False{}}, False{}, 7, LI.Neutral{}}, X.ApplyFacts{T.GroundSample{T.BlockPos{0, 0, 0}, P.float_bits(1058642330)}, T.Attributes{F.F64{1069128089, 2684354560}, F.F64{1068792545, 1202590843}, F.F64{1072693248, 0}, F.F64{1072693248, 0}}, P.float_bits(1058642330), False{}, False{}, False{}, T.NeutralDryAir{}, F.F64{1071309127, 2684354560}, P.float_bits(1065353216), True{}, PT.Neutral{}, F.F64{1070805811, 858993459}}, E.Environment{E.KnownEmptyEntityCollisions{}, E.KnownClearBorderInterior{A.AABB{F.F64{3225419776, 0}, F.F64{3224371200, 0}, F.F64{3225419776, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}}}}, 2n, 64n, 64n, 3n, []}

def request_1_3() -> X.Request:
  X.Request{X.NeutralDryLoadedNoParticles{}, ECT.NeutralClientInactiveInterpolation{}, X.ControlFacts{20, LI.Abilities{False{}, False{}}, False{}, 7, LI.Neutral{}}, X.ApplyFacts{T.GroundSample{T.BlockPos{0, 0, 0}, P.float_bits(1058642330)}, T.Attributes{F.F64{1069128089, 2684354560}, F.F64{1068792545, 1202590843}, F.F64{1072693248, 0}, F.F64{1072693248, 0}}, P.float_bits(1058642330), False{}, False{}, False{}, T.NeutralDryAir{}, F.F64{1071309127, 2684354560}, P.float_bits(1065353216), True{}, PT.Neutral{}, F.F64{1070805811, 858993459}}, E.Environment{E.KnownEmptyEntityCollisions{}, E.KnownClearBorderInterior{A.AABB{F.F64{3225419776, 0}, F.F64{3224371200, 0}, F.F64{3225419776, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}}}}, 2n, 64n, 64n, 3n, []}

def scenario_1() -> Scenario:
  Scenario{"direct_shift", seed_1(), [Step{"direct_shift:0", PI.Buttons{False{}, False{}, False{}, False{}, False{}, True{}, False{}}, request_1_0(), 0, []}, Step{"direct_shift:1", PI.Buttons{False{}, False{}, False{}, False{}, False{}, True{}, False{}}, request_1_1(), 0, []}, Step{"direct_shift:2", PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, request_1_2(), 0, []}, Step{"direct_shift:3", PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, request_1_3(), 0, []}], False{}, []}

def seed_2() -> Seed:
  Seed{M.Body{M.Vec3{F.F64{1071644672, 0}, F.F64{1072693248, 0}, F.F64{1071644672, 0}}, A.AABB{F.F64{1070176665, 2147483648}, F.F64{1072693248, 0}, F.F64{1070176665, 2147483648}, F.F64{1072273817, 2684354560}, F.F64{1074161254, 1610612736}, F.F64{1072273817, 2684354560}}, M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, P.float_bits(1058642330), P.float_bits(1072064102), True{}, False{}, False{}, False{}}, X.Metadata{LI.State{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PI.Vector{P.float_bits(0), P.float_bits(0)}, 0, False{}, P.float_bits(1073741824), P.float_bits(3225419776), P.float_bits(1082130432), P.float_bits(3231711232)}, PR.Metadata{PT.Input{P.float_bits(0), P.float_bits(0), P.float_bits(0)}, False{}, 0, 0, False{}, P.float_bits(1039918957), P.float_bits(1099431936)}, False{}, P.State{P.Standing{}, P.float_bits(1070554153), []}, PC.Controller{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PL.State{P.float_bits(1099431936), P.float_bits(3241148416), P.float_bits(1094713344), P.float_bits(3239051264)}, MI.initial(), MI.default_options()}, ECT.Metadata{M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, 0, 7}, Inside.empty(), None{}, []}, SP.State{Some{T.BlockPos{0, 0, 0}}, False{}}, LM.MinorState{False{}}, H.History{F.F64{0, 0}}, []}

def request_2_0() -> X.Request:
  X.Request{X.NeutralDryLoadedNoParticles{}, ECT.NeutralClientInactiveInterpolation{}, X.ControlFacts{20, LI.Abilities{False{}, False{}}, False{}, 7, LI.Neutral{}}, X.ApplyFacts{T.GroundSample{T.BlockPos{0, 0, 0}, P.float_bits(1058642330)}, T.Attributes{F.F64{1069589463, 284541584}, F.F64{1068792545, 1202590843}, F.F64{1072693248, 0}, F.F64{1072693248, 0}}, P.float_bits(1058642330), True{}, False{}, False{}, T.NeutralDryAir{}, F.F64{1071309127, 2684354560}, P.float_bits(1065353216), True{}, PT.Neutral{}, F.F64{1070805811, 858993459}}, E.Environment{E.KnownEmptyEntityCollisions{}, E.KnownClearBorderInterior{A.AABB{F.F64{3225419776, 0}, F.F64{3224371200, 0}, F.F64{3225419776, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}}}}, 2n, 64n, 64n, 3n, []}

def scenario_2() -> Scenario:
  Scenario{"scheduled_sprint_jump", seed_2(), [Step{"scheduled_sprint_jump:0", PI.Buttons{True{}, False{}, False{}, False{}, False{}, False{}, True{}}, request_2_0(), 1, []}], False{}, []}

def seed_3() -> Seed:
  Seed{M.Body{M.Vec3{F.F64{1071644672, 0}, F.F64{1072693248, 0}, F.F64{1071644672, 0}}, A.AABB{F.F64{1070176665, 2147483648}, F.F64{1072693248, 0}, F.F64{1070176665, 2147483648}, F.F64{1072273817, 2684354560}, F.F64{1074161254, 1610612736}, F.F64{1072273817, 2684354560}}, M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, P.float_bits(1058642330), P.float_bits(1072064102), True{}, False{}, False{}, False{}}, X.Metadata{LI.State{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PI.Vector{P.float_bits(0), P.float_bits(0)}, 0, False{}, P.float_bits(1073741824), P.float_bits(3225419776), P.float_bits(1082130432), P.float_bits(3231711232)}, PR.Metadata{PT.Input{P.float_bits(0), P.float_bits(0), P.float_bits(0)}, False{}, 0, 0, False{}, P.float_bits(1039918957), P.float_bits(1099431936)}, False{}, P.State{P.Standing{}, P.float_bits(1070554153), []}, PC.Controller{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PL.State{P.float_bits(1099431936), P.float_bits(3241148416), P.float_bits(1094713344), P.float_bits(3239051264)}, MI.initial(), MI.default_options()}, ECT.Metadata{M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, 0, 0}, Inside.empty(), None{}, []}, SP.State{Some{T.BlockPos{0, 0, 0}}, False{}}, LM.MinorState{False{}}, H.History{F.F64{0, 0}}, []}

def request_3_0() -> X.Request:
  X.Request{X.NeutralDryLoadedNoParticles{}, ECT.NeutralClientInactiveInterpolation{}, X.ControlFacts{20, LI.Abilities{False{}, False{}}, False{}, 7, LI.Neutral{}}, X.ApplyFacts{T.GroundSample{T.BlockPos{0, 0, 0}, P.float_bits(1058642330)}, T.Attributes{F.F64{1069128089, 2684354560}, F.F64{1068792545, 1202590843}, F.F64{1072693248, 0}, F.F64{1072693248, 0}}, P.float_bits(1058642330), False{}, False{}, False{}, T.NeutralDryAir{}, F.F64{1071309127, 2684354560}, P.float_bits(1065353216), True{}, PT.Neutral{}, F.F64{1070805811, 858993459}}, E.Environment{E.KnownEmptyEntityCollisions{}, E.KnownClearBorderInterior{A.AABB{F.F64{3225419776, 0}, F.F64{3224371200, 0}, F.F64{3225419776, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}}}}, 2n, 64n, 64n, 3n, []}

def request_3_1() -> X.Request:
  X.Request{X.NeutralDryLoadedNoParticles{}, ECT.NeutralClientInactiveInterpolation{}, X.ControlFacts{20, LI.Abilities{False{}, False{}}, False{}, 7, LI.Neutral{}}, X.ApplyFacts{T.GroundSample{T.BlockPos{0, 0, 0}, P.float_bits(1058642330)}, T.Attributes{F.F64{1069128089, 2684354560}, F.F64{1068792545, 1202590843}, F.F64{1072693248, 0}, F.F64{1072693248, 0}}, P.float_bits(1058642330), False{}, False{}, False{}, T.NeutralDryAir{}, F.F64{1071309127, 2684354560}, P.float_bits(1065353216), True{}, PT.Neutral{}, F.F64{1070805811, 858993459}}, E.Environment{E.KnownEmptyEntityCollisions{}, E.KnownClearBorderInterior{A.AABB{F.F64{3225419776, 0}, F.F64{3224371200, 0}, F.F64{3225419776, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}}}}, 2n, 64n, 64n, 3n, []}

def scenario_3() -> Scenario:
  Scenario{"scheduled_jump", seed_3(), [Step{"scheduled_jump:0", PI.Buttons{True{}, False{}, False{}, False{}, True{}, False{}, False{}}, request_3_0(), 1, []}, Step{"scheduled_jump:1", PI.Buttons{True{}, False{}, False{}, False{}, False{}, False{}, False{}}, request_3_1(), 1, []}], False{}, []}

def seed_4() -> Seed:
  Seed{M.Body{M.Vec3{F.F64{1071644672, 0}, F.F64{1072693248, 0}, F.F64{1071644672, 0}}, A.AABB{F.F64{1070176665, 2147483648}, F.F64{1072693248, 0}, F.F64{1070176665, 2147483648}, F.F64{1072273817, 2684354560}, F.F64{1074161254, 1610612736}, F.F64{1072273817, 2684354560}}, M.Vec3{F.F64{1072273817, 2576980378}, F.F64{3216611737, 2576980378}, F.F64{0, 0}}, P.float_bits(1058642330), P.float_bits(1072064102), True{}, False{}, False{}, False{}}, X.Metadata{LI.State{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PI.Vector{P.float_bits(0), P.float_bits(0)}, 0, False{}, P.float_bits(1073741824), P.float_bits(3225419776), P.float_bits(1082130432), P.float_bits(3231711232)}, PR.Metadata{PT.Input{P.float_bits(0), P.float_bits(0), P.float_bits(0)}, False{}, 0, 0, False{}, P.float_bits(1039918957), P.float_bits(3266576384)}, False{}, P.State{P.Standing{}, P.float_bits(1070554153), []}, PC.Controller{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PL.State{P.float_bits(3266576384), P.float_bits(3241148416), P.float_bits(3266576384), P.float_bits(3239051264)}, MI.initial(), MI.default_options()}, ECT.Metadata{M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, 0, 0}, Inside.empty(), None{}, []}, SP.State{Some{T.BlockPos{0, 0, 0}}, False{}}, LM.MinorState{False{}}, H.History{F.F64{0, 0}}, []}

def request_4_0() -> X.Request:
  X.Request{X.NeutralDryLoadedNoParticles{}, ECT.NeutralClientInactiveInterpolation{}, X.ControlFacts{20, LI.Abilities{False{}, False{}}, False{}, 7, LI.Neutral{}}, X.ApplyFacts{T.GroundSample{T.BlockPos{0, 0, 0}, P.float_bits(1058642330)}, T.Attributes{F.F64{1069128089, 2684354560}, F.F64{1068792545, 1202590843}, F.F64{1072693248, 0}, F.F64{1072693248, 0}}, P.float_bits(0), False{}, False{}, False{}, T.NeutralDryAir{}, F.F64{1071309127, 2684354560}, P.float_bits(1065353216), True{}, PT.Neutral{}, F.F64{1070805811, 858993459}}, E.Environment{E.KnownEmptyEntityCollisions{}, E.KnownClearBorderInterior{A.AABB{F.F64{3225419776, 0}, F.F64{3224371200, 0}, F.F64{3225419776, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}}}}, 2n, 64n, 64n, 3n, []}

def scenario_4() -> Scenario:
  Scenario{"scheduled_blocked", seed_4(), [Step{"scheduled_blocked:0", PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, request_4_0(), 1, []}], True{}, []}

def seed_5() -> Seed:
  Seed{M.Body{M.Vec3{F.F64{1071644672, 0}, F.F64{1072693248, 0}, F.F64{1071644672, 0}}, A.AABB{F.F64{1070176665, 2147483648}, F.F64{1072693248, 0}, F.F64{1070176665, 2147483648}, F.F64{1072273817, 2684354560}, F.F64{1074161254, 1610612736}, F.F64{1072273817, 2684354560}}, M.Vec3{F.F64{1072273817, 2576980378}, F.F64{3216611737, 2576980378}, F.F64{0, 0}}, P.float_bits(1058642330), P.float_bits(1072064102), True{}, False{}, False{}, False{}}, X.Metadata{LI.State{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PI.Vector{P.float_bits(0), P.float_bits(0)}, 0, False{}, P.float_bits(1073741824), P.float_bits(3225419776), P.float_bits(1082130432), P.float_bits(3231711232)}, PR.Metadata{PT.Input{P.float_bits(0), P.float_bits(0), P.float_bits(0)}, False{}, 0, 0, False{}, P.float_bits(1039918957), P.float_bits(3266576384)}, False{}, P.State{P.Standing{}, P.float_bits(1070554153), []}, PC.Controller{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PL.State{P.float_bits(3266576384), P.float_bits(3241148416), P.float_bits(3266576384), P.float_bits(3239051264)}, MI.initial(), MI.default_options()}, ECT.Metadata{M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, 0, 0}, Inside.empty(), None{}, []}, SP.State{Some{T.BlockPos{0, 0, 0}}, False{}}, LM.MinorState{False{}}, H.History{F.F64{0, 0}}, []}

def request_5_0() -> X.Request:
  X.Request{X.NeutralDryLoadedNoParticles{}, ECT.NeutralClientInactiveInterpolation{}, X.ControlFacts{20, LI.Abilities{False{}, False{}}, False{}, 7, LI.Neutral{}}, X.ApplyFacts{T.GroundSample{T.BlockPos{0, 0, 0}, P.float_bits(1058642330)}, T.Attributes{F.F64{1069128089, 2684354560}, F.F64{1068792545, 1202590843}, F.F64{1072693248, 0}, F.F64{1072693248, 0}}, P.float_bits(1065353216), False{}, False{}, False{}, T.NeutralDryAir{}, F.F64{1071309127, 2684354560}, P.float_bits(1065353216), True{}, PT.Neutral{}, F.F64{1070805811, 858993459}}, E.Environment{E.KnownEmptyEntityCollisions{}, E.KnownClearBorderInterior{A.AABB{F.F64{3225419776, 0}, F.F64{3224371200, 0}, F.F64{3225419776, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}}}}, 2n, 64n, 64n, 3n, []}

def request_5_1() -> X.Request:
  X.Request{X.NeutralDryLoadedNoParticles{}, ECT.NeutralClientInactiveInterpolation{}, X.ControlFacts{20, LI.Abilities{False{}, False{}}, False{}, 7, LI.Neutral{}}, X.ApplyFacts{T.GroundSample{T.BlockPos{1, 1, 0}, P.float_bits(1058642330)}, T.Attributes{F.F64{1069128089, 2684354560}, F.F64{1068792545, 1202590843}, F.F64{1072693248, 0}, F.F64{1072693248, 0}}, P.float_bits(1065353216), False{}, False{}, False{}, T.NeutralDryAir{}, F.F64{1071309127, 2684354560}, P.float_bits(1065353216), True{}, PT.Neutral{}, F.F64{1070805811, 858993459}}, E.Environment{E.KnownEmptyEntityCollisions{}, E.KnownClearBorderInterior{A.AABB{F.F64{3225419776, 0}, F.F64{3224371200, 0}, F.F64{3225419776, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}}}}, 2n, 64n, 64n, 3n, []}

def scenario_5() -> Scenario:
  Scenario{"scheduled_step", seed_5(), [Step{"scheduled_step:0", PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, request_5_0(), 1, []}, Step{"scheduled_step:1", PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, request_5_1(), 1, []}], True{}, []}

def seed_6() -> Seed:
  Seed{M.Body{M.Vec3{F.F64{1071644672, 0}, F.F64{1072693248, 0}, F.F64{1071644672, 0}}, A.AABB{F.F64{1070176665, 2147483648}, F.F64{1072693248, 0}, F.F64{1070176665, 2147483648}, F.F64{1072273817, 2684354560}, F.F64{1074161254, 1610612736}, F.F64{1072273817, 2684354560}}, M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, P.float_bits(1058642330), P.float_bits(1072064102), True{}, False{}, False{}, False{}}, X.Metadata{LI.State{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PI.Vector{P.float_bits(0), P.float_bits(0)}, 0, False{}, P.float_bits(1073741824), P.float_bits(3225419776), P.float_bits(1082130432), P.float_bits(3231711232)}, PR.Metadata{PT.Input{P.float_bits(0), P.float_bits(0), P.float_bits(0)}, False{}, 0, 0, False{}, P.float_bits(1039918957), P.float_bits(1099431936)}, False{}, P.State{P.Standing{}, P.float_bits(1070554153), []}, PC.Controller{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PL.State{P.float_bits(1099431936), P.float_bits(3241148416), P.float_bits(1094713344), P.float_bits(3239051264)}, MI.initial(), MI.default_options()}, ECT.Metadata{M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, 0, 0}, Inside.empty(), None{}, []}, SP.State{Some{T.BlockPos{0, 0, 0}}, False{}}, LM.MinorState{False{}}, H.History{F.F64{0, 0}}, []}

def request_6_0() -> X.Request:
  X.Request{X.NeutralDryLoadedNoParticles{}, ECT.NeutralClientInactiveInterpolation{}, X.ControlFacts{20, LI.Abilities{False{}, False{}}, False{}, 7, LI.Neutral{}}, X.ApplyFacts{T.GroundSample{T.BlockPos{0, 0, 0}, P.float_bits(1058642330)}, T.Attributes{F.F64{1069128089, 2684354560}, F.F64{1068792545, 1202590843}, F.F64{1072693248, 0}, F.F64{1072693248, 0}}, P.float_bits(1058642330), False{}, False{}, False{}, T.NeutralDryAir{}, F.F64{1071309127, 2684354560}, P.float_bits(1065353216), True{}, PT.Neutral{}, F.F64{1070805811, 858993459}}, E.Environment{E.KnownEmptyEntityCollisions{}, E.KnownClearBorderInterior{A.AABB{F.F64{3225419776, 0}, F.F64{3224371200, 0}, F.F64{3225419776, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}, F.F64{1077936128, 0}}}}, 2n, 64n, 64n, 3n, []}

def scenario_6() -> Scenario:
  Scenario{"scheduled_zero", seed_6(), [Step{"scheduled_zero:0", PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, request_6_0(), 1, []}], False{}, []}

def fixtures() -> List<&2,Scenario>:
  [scenario_0(), scenario_1(), scenario_2(), scenario_3(), scenario_4(), scenario_5(), scenario_6()]

def altered_apply(+facts:X.ApplyFacts,code:U32) -> X.ApplyFacts:
  X.ApplyFacts{ground,attributes,maximum,sprint,gravity,discard,travel,strength,factor,affected,tick,sneak} = facts
  match code:
    case 2: X.ApplyFacts{ground,attributes,maximum,Bool.not(sprint),gravity,discard,travel,strength,factor,affected,tick,sneak}
    case _: facts

def altered_control(+facts:X.ControlFacts,code:U32) -> X.ControlFacts:
  X.ControlFacts{food,abilities,mobility,window,mode} = facts
  match code:
    case 8: X.ControlFacts{food,abilities,mobility,window,LI.Swimming{}}
    case 9: X.ControlFacts{food,LI.Abilities{True{},False{}},mobility,window,mode}
    case _: facts

def altered_request(+request:X.Request,code:U32) -> X.Request:
  X.Request{lifecycle,common,control,apply,environment,cf,mf,rf,pf,tail} = request
  match code:
    case 1: X.Request{lifecycle,common,control,apply,environment,0n,mf,rf,pf,tail}
    case 2: X.Request{lifecycle,common,control,altered_apply(apply,2),environment,cf,mf,rf,pf,tail}
    case 3: X.Request{lifecycle,common,control,apply,environment,cf,mf,0n,pf,tail}
    case 4: X.Request{lifecycle,common,control,apply,environment,cf,mf,rf,0n,tail}
    case 5: X.Request{X.UnsupportedLifecycle{77},common,control,apply,environment,cf,mf,rf,pf,tail}
    case 6: X.Request{lifecycle,ECT.ActiveInterpolation{},control,apply,environment,cf,mf,rf,pf,tail}
    case 7: X.Request{lifecycle,common,control,apply,environment,cf,mf,rf,pf,[request]}
    case 8: X.Request{lifecycle,common,altered_control(control,8),apply,environment,cf,mf,rf,pf,tail}
    case 9: X.Request{lifecycle,common,altered_control(control,9),apply,environment,cf,mf,rf,pf,tail}
    case 10: X.Request{lifecycle,common,control,apply,E.Environment{E.UnresolvedEntityCollisions{},E.UnresolvedWorldBorder{}},cf,mf,rf,pf,tail}
    case 11: X.Request{lifecycle,common,control,apply,environment,cf,0n,rf,pf,tail}
    case _: request

def sentinel_metadata(metadata:X.Metadata) -> X.Metadata:
  X.Metadata{local,player,sprint,pose,PC.Controller{buttons,look,mouse,options},entity, receiver, error,tail} = metadata
  X.Metadata{local,player,sprint,pose,
    PC.Controller{buttons,look,MI.State{F.from_u32(123),F.from_u32(456),F.F64{1070596096,0},F.F64{3217031168,0},False{}},
      MI.Options{F.F64{1071225241,2576980378},True{},False{},False{},False{}}},
    ECT.Metadata{M.Vec3{F.from_u32(7),F.from_u32(8),F.from_u32(9)},M.Vec3{F.neg(F.from_u32(7)),F.neg(F.from_u32(8)),F.neg(F.from_u32(9))},3,4294967295}, receiver, Some{"retained-before-error"},tail}

def noncanonical_pose(+pose:P.State) -> P.State:
  P.State{value,eye,owned} = pose
  P.State{value,eye,[pose]}

def altered_metadata(+metadata:X.Metadata,code:U32) -> X.Metadata:
  X.Metadata{local,player,sprint,+pose,controls,entity, receiver, error,tail} = metadata
  match code:
    case 12: X.Metadata{local,player,sprint,pose,controls,entity, receiver, error,[metadata]}
    case 13: X.Metadata{local,player,sprint,noncanonical_pose(pose),controls,entity, receiver, error,tail}
    case _: metadata

def ray_body(body:M.Body) -> M.Body:
  M.Body{position,box,velocity,+width,+height,ground,horizontal,vertical,below} = body
  +feet : M.Vec3 = M.Vec3{F.F64{1071644672,0},F.from_u32(5),F.F64{1071644672,0}}
  M.Body{feet,M.make_box(feet,width,height),M.Vec3{F.from_u32(2),M.zero(),M.zero()},width,height,False{},horizontal,vertical,below}

def altered_seed(+seed:Seed,code:U32) -> Seed:
  Seed{+body,metadata,support,minor,history,tail} = seed
  match code:
    case 14:
      Seed{ray_body(body),
        sentinel_metadata(metadata),support,minor,H.History{F.from_u32(5)},tail}
    case _: Seed{body,altered_metadata(sentinel_metadata(metadata),code),support,minor,history,tail}

def seed_variant(code:U32) -> Seed:
  match code:
    case 3: altered_seed(seed_1(),code)
    case 11: altered_seed(seed_4(),code)
    case _: altered_seed(seed_0(),code)

def owner_world_ready(+id:String,tables:L.Tables,result:W.State & Result<&2,&2,String,Unit>) -> IO(X.State):
  match result:
    case (world,Fail{cause}): IO.die(X.State,3,"runtime child world:" ++ cause)
    case (W.State{engine,body,yaw,pitch,Some{+palette},region,cache},Done{unit}):
      do IO<X.State>:
        fixture:W.State <- fixture_palette(W.State{engine,body,yaw,pitch,Some{palette},region,cache},palette)
        timed:W.State <- fixture_extra(id,fixture)
        clocked:W.State <- mutate_world(timed,C.DaylightSet{False{}})
        queued:W.State <- held_pending(clocked)
        cached:W.State <- snapshot_kept(W.snapshot(queued,64,48))
        return seed_world(tables,altered_seed(seed_4(),0),cached)
    case (world,Done{unit}): IO.die(X.State,3,"runtime child palette")


def owner_child_loaded(+id:String,result:Result<&2,&1,L.Error,L.Tables>) -> IO(X.State):
  match result:
    case Fail{cause}: IO.die(X.State,3,"runtime owned child sine table")
    case Done{tables}:
      do IO<X.State>:
        engine:G.Engine <- G.load()
        owner_world_ready(id,tables,W.new(engine))



def owner_child(id:String) -> IO(X.State):
  do IO<X.State>:
    tables:Result<&2,&1,L.Error,L.Tables> <- L.Tables.load("generated/reference_mth_sin.f32")
    owner_child_loaded(id,tables)


def state_with_children(state:X.State,first:X.State,second:X.State) -> X.State:
  X.State{motion,tables,metadata,tail} = state
  X.State{motion,tables,metadata,[first,second]}


def child_motion(child:X.State) -> MH.State:
  X.State{motion,tables,metadata,tail} = child
  motion


def state_with_motion_children(state:X.State,first:X.State,second:X.State) -> X.State:
  X.State{MH.State{world,support,minor,history,owned},tables,metadata,tail} = state
  X.State{MH.State{world,support,minor,history,[child_motion(first),child_motion(second)]},tables,metadata,tail}


def fixture_owners(+id:String,state:X.State) -> IO(X.State):
  match id:
    case "policy:owned-tail":
      do IO<X.State>:
        first:X.State <- owner_child("owner-child-first")
        second:X.State <- owner_child("owner-child-second")
        return state_with_children(state,first,second)
    case "policy:motion-owned-tail":
      do IO<X.State>:
        first:X.State <- owner_child("owner-child-first")
        second:X.State <- owner_child("owner-child-second")
        return state_with_motion_children(state,first,second)
    case _: IO.pure(X.State,state)


def scenario_ready(tables:L.Tables,+scenario:Scenario,result:W.State & Result<&2,&2,String,Unit>) -> IO(X.State):
  Scenario{id,seed,steps,wall,tail} = scenario
  match result:
    case (world,Fail{cause}): IO.die(X.State,3,"runtime world:" ++ cause)
    case (W.State{engine,body,yaw,pitch,Some{+palette},region,cache},Done{unit}):
      do IO<X.State>:
        fixture:W.State <- fixture_palette(W.State{engine,body,yaw,pitch,Some{palette},region,cache},palette)
        blocked:W.State <- fixture_wall(wall,fixture)
        timed:W.State <- mutate_world(blocked,C.TimeSet{777n})
        clocked:W.State <- mutate_world(timed,C.DaylightSet{False{}})
        queued:W.State <- held_pending(clocked)
        cached:W.State <- snapshot_kept(W.snapshot(queued,64,48))
        final:W.State <- fixture_extra(id,cached)
        owned:X.State <- fixture_owners(id,seed_world(tables,seed,final))
        run_steps(steps,owned)
    case (world,Done{unit}): IO.die(X.State,3,"runtime fixture palette")




def run_scenarios(scenarios:List<&2,Scenario>,tables:L.Tables) -> IO(L.Tables):
  match scenarios:
    case Nil{}: IO.pure(L.Tables,tables)
    case scenario <> rest:
      do IO<L.Tables>:
        engine:G.Engine <- G.load()
        completed:X.State <- scenario_ready(tables,scenario,W.new(engine))
        run_scenarios(rest,tables_returned(completed))


def policy(+id:String,+code:U32,operation:U32) -> Scenario:
  Scenario{id,seed_variant(code),[
    Step{id,PI.Buttons{False{},False{},False{},False{},False{},True{},False{}},altered_request(request_0_0(),code),operation,[]},
    Step{id ++ ":query-reuse",PI.Buttons{False{},False{},False{},False{},False{},True{},False{}},request_0_0(),6,[]}],False{},[]}

def policies() -> List<&2,Scenario>:
  [policy("policy:direct-control",1,0),policy("policy:scheduled-control",1,1),
   policy("policy:direct-sprint-context",2,0),policy("policy:scheduled-sprint-context",2,1),
   policy("policy:direct-rotation",3,0),policy("policy:direct-late",4,0),
   policy("policy:scheduled-late",4,1),policy("policy:lifecycle",5,1),
   policy("policy:common",6,1),policy("policy:request-tail",7,1),
   policy("policy:control-mode",8,1),policy("policy:abilities",9,1),
   policy("policy:entities",10,1),policy("policy:move-budget",11,1),
   policy("policy:metadata-tail",12,1),policy("policy:pose-tail",13,1),
   policy("policy:required-ray",14,1),policy("policy:crawl",0,1),
   policy("policy:due-crawl",0,1),policy("policy:missing-section",0,1),
   policy("policy:paused",6,2),policy("policy:release",0,3),
   policy("policy:packet-failure",0,4),policy("policy:packet-success",0,5),
   policy("policy:query",0,6),policy("policy:eye",0,7),
   policy("policy:owned-tail",0,1),policy("policy:motion-owned-tail",0,1)]

def policy_tables(tables:L.Tables) -> IO(Unit):
  do IO<Unit>:
    remaining:L.Tables <- run_scenarios(policies(),tables)
    IO.print("local-phase-runtime|complete|true")

def loaded(result:Result<&2,&1,L.Error,L.Tables>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.die(Unit,3,"runtime sine table")
    case Done{tables}:
      do IO<Unit>:
        remaining:L.Tables <- run_scenarios(fixtures(),tables)
        policy_tables(remaining)

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> path <> rest:
      do IO<Unit>:
        tables:Result<&2,&1,L.Error,L.Tables> <- L.Tables.load(path)
        loaded(tables)
    case _: IO.die(Unit,2,"runtime sine table argument required")

def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),arguments)
