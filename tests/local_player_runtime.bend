import Base
import ../src/local_player_runtime.bend as RT
import ../src/local_player_record.bend as Record
import ../src/player_record.bend as Saved
import ../src/player_codec.bend as Codec
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
    case X.Metadata{local,player,sprint,pose,controls,entity,error,tail} <> rest:
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



def installed_seed(tables:L.Tables,seed:Seed,result:G.Engine & W.View) -> X.State:
  Seed{body,+metadata,support,minor,history,tail} = seed
  (engine,W.View{old,yaw,pitch,palette,region,cache}) = result
  +look = PR.look(X.controls(metadata))
  X.State{MH.State{W.attach(engine,W.View{body,PL.mul(X.yaw(look),PL.float_bits(1016003125)),PL.mul(X.pitch(look),PL.float_bits(1016003125)),palette,region,cache}),support,minor,H.State{history},[]},tables,metadata,[]}

def seed_world(tables:L.Tables,seed:Seed,world:W.State) -> X.State:
  installed_seed(tables,seed,W.take(world))

def seed_0() -> Seed:
  Seed{M.Body{M.Vec3{F.F64{1071644672, 0}, F.F64{1072693248, 0}, F.F64{1071644672, 0}}, A.AABB{F.F64{1070176665, 2147483648}, F.F64{1072693248, 0}, F.F64{1070176665, 2147483648}, F.F64{1072273817, 2684354560}, F.F64{1074161254, 1610612736}, F.F64{1072273817, 2684354560}}, M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, P.float_bits(1058642330), P.float_bits(1072064102), True{}, False{}, False{}, False{}}, X.Metadata{LI.State{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PI.Vector{P.float_bits(0), P.float_bits(0)}, 0, False{}, P.float_bits(1073741824), P.float_bits(3225419776), P.float_bits(1082130432), P.float_bits(3231711232)}, PR.Metadata{PT.Input{P.float_bits(0), P.float_bits(0), P.float_bits(0)}, False{}, 0, 0, False{}, P.float_bits(1039918957), P.float_bits(1099431936)}, False{}, P.State{P.Standing{}, P.float_bits(1070554153), []}, PC.Controller{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PL.State{P.float_bits(1099431936), P.float_bits(3241148416), P.float_bits(1094713344), P.float_bits(3239051264)}, MI.initial(), MI.default_options()}, ECT.Metadata{M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, 0, 0}, None{}, []}, SP.State{Some{T.BlockPos{0, 0, 0}}, False{}}, LM.MinorState{False{}}, H.History{F.F64{0, 0}}, []}

def seed_2() -> Seed:
  Seed{M.Body{M.Vec3{F.F64{1071644672, 0}, F.F64{1072693248, 0}, F.F64{1071644672, 0}}, A.AABB{F.F64{1070176665, 2147483648}, F.F64{1072693248, 0}, F.F64{1070176665, 2147483648}, F.F64{1072273817, 2684354560}, F.F64{1074161254, 1610612736}, F.F64{1072273817, 2684354560}}, M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, P.float_bits(1058642330), P.float_bits(1072064102), True{}, False{}, False{}, False{}}, X.Metadata{LI.State{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PI.Vector{P.float_bits(0), P.float_bits(0)}, 0, False{}, P.float_bits(1073741824), P.float_bits(3225419776), P.float_bits(1082130432), P.float_bits(3231711232)}, PR.Metadata{PT.Input{P.float_bits(0), P.float_bits(0), P.float_bits(0)}, False{}, 0, 0, False{}, P.float_bits(1039918957), P.float_bits(1099431936)}, False{}, P.State{P.Standing{}, P.float_bits(1070554153), []}, PC.Controller{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PL.State{P.float_bits(1099431936), P.float_bits(3241148416), P.float_bits(1094713344), P.float_bits(3239051264)}, MI.initial(), MI.default_options()}, ECT.Metadata{M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, 0, 7}, None{}, []}, SP.State{Some{T.BlockPos{0, 0, 0}}, False{}}, LM.MinorState{False{}}, H.History{F.F64{0, 0}}, []}

def seed_3() -> Seed:
  Seed{M.Body{M.Vec3{F.F64{1071644672, 0}, F.F64{1072693248, 0}, F.F64{1071644672, 0}}, A.AABB{F.F64{1070176665, 2147483648}, F.F64{1072693248, 0}, F.F64{1070176665, 2147483648}, F.F64{1072273817, 2684354560}, F.F64{1074161254, 1610612736}, F.F64{1072273817, 2684354560}}, M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, P.float_bits(1058642330), P.float_bits(1072064102), True{}, False{}, False{}, False{}}, X.Metadata{LI.State{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PI.Vector{P.float_bits(0), P.float_bits(0)}, 0, False{}, P.float_bits(1073741824), P.float_bits(3225419776), P.float_bits(1082130432), P.float_bits(3231711232)}, PR.Metadata{PT.Input{P.float_bits(0), P.float_bits(0), P.float_bits(0)}, False{}, 0, 0, False{}, P.float_bits(1039918957), P.float_bits(1099431936)}, False{}, P.State{P.Standing{}, P.float_bits(1070554153), []}, PC.Controller{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PL.State{P.float_bits(1099431936), P.float_bits(3241148416), P.float_bits(1094713344), P.float_bits(3239051264)}, MI.initial(), MI.default_options()}, ECT.Metadata{M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, 0, 0}, None{}, []}, SP.State{Some{T.BlockPos{0, 0, 0}}, False{}}, LM.MinorState{False{}}, H.History{F.F64{0, 0}}, []}

def seed_6() -> Seed:
  Seed{M.Body{M.Vec3{F.F64{1071644672, 0}, F.F64{1072693248, 0}, F.F64{1071644672, 0}}, A.AABB{F.F64{1070176665, 2147483648}, F.F64{1072693248, 0}, F.F64{1070176665, 2147483648}, F.F64{1072273817, 2684354560}, F.F64{1074161254, 1610612736}, F.F64{1072273817, 2684354560}}, M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, P.float_bits(1058642330), P.float_bits(1072064102), True{}, False{}, False{}, False{}}, X.Metadata{LI.State{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PI.Vector{P.float_bits(0), P.float_bits(0)}, 0, False{}, P.float_bits(1073741824), P.float_bits(3225419776), P.float_bits(1082130432), P.float_bits(3231711232)}, PR.Metadata{PT.Input{P.float_bits(0), P.float_bits(0), P.float_bits(0)}, False{}, 0, 0, False{}, P.float_bits(1039918957), P.float_bits(1099431936)}, False{}, P.State{P.Standing{}, P.float_bits(1070554153), []}, PC.Controller{PI.Buttons{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, PL.State{P.float_bits(1099431936), P.float_bits(3241148416), P.float_bits(1094713344), P.float_bits(3239051264)}, MI.initial(), MI.default_options()}, ECT.Metadata{M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, M.Vec3{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}}, 0, 0}, None{}, []}, SP.State{Some{T.BlockPos{0, 0, 0}}, False{}}, LM.MinorState{False{}}, H.History{F.F64{0, 0}}, []}

# Fixture controls use the actual public facade packet path. No expected motion
# or apply facts are constructed here; the closed driver owns fact sampling.
def packet(buttons:PI.Buttons) -> CC.Packet:
  PI.Buttons{f,b,l,r,j,c,s} = buttons
  CC.Packet{[CC.Release{},CC.PlatformEvent{Key{1,f},True{}},CC.PlatformEvent{Key{2,b},True{}},
    CC.PlatformEvent{Key{3,l},True{}},CC.PlatformEvent{Key{4,r},True{}},CC.PlatformEvent{Key{5,j},True{}},
    CC.PlatformEvent{Key{6,c},True{}},CC.PlatformEvent{Key{7,s},True{}}],True{},True{}}

def input_kept(result:X.State & Result<&2,&2,String,Unit>) -> IO(X.State):
  match result:
    case (state,Done{unit}): IO.pure(X.State,state)
    case (state,Fail{error}): IO.die(X.State,3,"fixture input:" ++ error)

def eye_printed(+id:String,result:X.State & Result<&2,&2,String,M.Vec3>) -> IO(X.State):
  match result:
    case (state,Done{value}):
      do IO<X.State>:
        IO.print(id ++ "|eye|" ++ vector_show(value))
        return state
    case (state,Fail{error}): IO.die(X.State,3,"fixture eye:" ++ error)

def motion_steps(buttons:List<&2,PI.Buttons>,+name:String,+index:Nat,state:X.State) -> IO(X.State):
  match buttons:
    case Nil{}: IO.pure(X.State,state)
    case next <> rest:
      +id = name ++ ":" ++ Nat.show(index)
      do IO<X.State>:
        held:X.State <- input_kept(RT.input(state,PI.Bindings{1,2,3,4,5,6,7},packet(next)))
        before:X.State <- state_report(id ++ "-before",held)
        after:X.State <- state_report(id ++ "-after",RT.step(RT.driver(),before))
        queried:X.State <- eye_printed(id,RT.eye(after))
        motion_steps(rest,name,(index+1n : Nat),queried)

def setup_result(tables:L.Tables,seed:Seed,result:W.State & Result<&2,&2,String,Unit>) -> IO(X.State):
  match result:
    case (W.State{engine,body,yaw,pitch,Some{+palette},region,cache},Done{unit}):
      do IO<X.State>:
        world:W.State <- fixture_palette(W.State{engine,body,yaw,pitch,Some{palette},region,cache},palette)
        timed:W.State <- mutate_world(world,C.TimeSet{777n})
        fixed:W.State <- mutate_world(timed,C.DaylightSet{False{}})
        queued:W.State <- held_pending(fixed)
        return seed_world(tables,seed,queued)
    case (world,Fail{error}): IO.die(X.State,3,"fixture new:" ++ error)
    case (world,Done{unit}): IO.die(X.State,3,"fixture palette missing")

def setup(tables:L.Tables,seed:Seed) -> IO(X.State):
  do IO<X.State>:
    engine:G.Engine <- G.load()
    setup_result(tables,seed,W.new(engine))

def take_tables(state:X.State) -> L.Tables:
  X.State{motion,tables,metadata,tail} = state
  tables

def actual(tables:L.Tables) -> IO(L.Tables):
  do IO<L.Tables>:
    shift:X.State <- setup(tables,seed_0())
    shifted:X.State <- motion_steps(
      [PI.Buttons{False{},False{},False{},False{},False{},True{},False{}},
       PI.Buttons{False{},False{},False{},False{},False{},True{},False{}},PI.empty(),PI.empty()],"scheduled_shift",0n,shift)
    jump:X.State <- setup(take_tables(shifted),seed_3())
    jumped:X.State <- motion_steps(
      [PI.Buttons{True{},False{},False{},False{},True{},False{},False{}},PI.Buttons{True{},False{},False{},False{},False{},False{},False{}}],"scheduled_jump",0n,jump)
    sprint:X.State <- setup(take_tables(jumped),seed_2())
    sprinted:X.State <- motion_steps(
      [PI.Buttons{True{},False{},False{},False{},False{},False{},True{}}],"scheduled_sprint_jump",0n,sprint)
    zero:X.State <- setup(take_tables(sprinted),seed_6())
    stopped:X.State <- motion_steps([PI.empty()],"scheduled_zero",0n,zero)
    return take_tables(stopped)

def checked_report(+id:String,result:X.State & Result<&2,&2,String,Record.Record>) -> IO(X.State):
  (state,status) = result
  do IO<X.State>:
    IO.print(id ++ "|record-admitted|" ++ flag(Result.is_done(&2,&2,String,Record.Record,status)))
    state_report(id ++ "-checked-after",state)

def packet_report(+id:String,result:X.State & Result<&2,&2,String,Unit>) -> IO(X.State):
  (state,status) = result
  do IO<X.State>:
    IO.print(id ++ "|packet-admitted|" ++ flag(Result.is_done(&2,&2,String,Unit,status)))
    state_report(id ++ "-after",state)

def data_tail(state:X.State) -> X.State:
  X.State{motion,tables,+metadata,tail} = state
  X.Metadata{local,player,sprinting,pose,controls,entity,error,old} = metadata
  X.State{motion,tables,X.Metadata{local,player,sprinting,pose,controls,entity,Some{"retained-diagnostic"},[metadata]},tail}

def restore_current(result:X.State & Record.Record) -> X.State & Result<&2,&2,String,Unit>:
  (state,value) = result
  RT.restore(state,value)

def paused(world:W.State) -> W.State & Unit:
  W.State{G.Engine{core,registry},body,yaw,pitch,palette,region,cache} = world
  (W.State{G.Engine{C.set_paused(core,True{}),registry},body,yaw,pitch,palette,region,cache},Unit{})

def discard_query(result:X.State & Unit) -> X.State:
  (state,unit) = result
  state

def child_time_returned(view:W.View,registry:B.Registry,result:C.World & Result<&2,&2,C.Error,Unit>) -> W.State & Unit:
  (core,status) = result
  (W.attach(G.Engine{core,registry},view),Unit{})

def child_time(time:Nat,world:W.State) -> W.State & Unit:
  W.State{G.Engine{core,registry},body,yaw,pitch,palette,region,cache} = world
  child_time_returned(W.View{body,yaw,pitch,palette,region,cache},registry,C.apply(core,C.TimeSet{time}))

def child_loaded(time:Nat,result:Result<&2,&1,L.Error,L.Tables>) -> IO(X.State):
  match result:
    case Fail{cause}: IO.die(X.State,3,"fixture child sine table")
    case Done{tables}:
      do IO<X.State>:
        state:X.State <- setup(tables,seed_0())
        return discard_query(RT.query(Unit,state,world => child_time(time,world)))

def child(time:Nat) -> IO(X.State):
  do IO<X.State>:
    tables:Result<&2,&1,L.Error,L.Tables> <- L.Tables.load("generated/reference_mth_sin.f32")
    child_loaded(time,tables)

def child_motion(state:X.State) -> MH.State:
  X.State{motion,tables,metadata,tail} = state
  motion

def owner_children(state:X.State,first:X.State,second:X.State,third:X.State,fourth:X.State) -> X.State:
  X.State{MH.State{world,support,minor,history,owned},tables,metadata,tail} = state
  X.State{MH.State{world,support,minor,history,[child_motion(third),child_motion(fourth)]},tables,metadata,[first,second]}

def owned_detour(tables:L.Tables) -> IO(L.Tables):
  do IO<L.Tables>:
    base:X.State <- setup(tables,seed_0())
    first:X.State <- child(321n)
    second:X.State <- child(654n)
    third:X.State <- child(123n)
    fourth:X.State <- child(456n)
    before:X.State <- state_report("owned-before",owner_children(data_tail(base),first,second,third,fourth))
    after:X.State <- state_report("owned-after",RT.reattach(RT.detach(before)))
    refused:X.State <- checked_report("owned",RT.record_checked(after))
    before_tick:X.State <- state_report("owned-tick-before",refused)
    after_tick:X.State <- state_report("owned-tick-after",RT.step(RT.driver(),before_tick))
    return take_tables(after_tick)

def provider_marker(world:W.State,support:SP.State) -> W.State & Result<&2,&2,X.Error,X.ApplyFacts>:
  W.State{G.Engine{core,registry},body,yaw,pitch,palette,region,cache} = world
  (W.State{G.Engine{C.step(core),registry},body,yaw,pitch,palette,region,cache},Fail{X.ViewError{"observable-provider-ran"}})

def body_drift(world:W.State) -> W.State & Unit:
  W.State{engine,M.Body{M.Vec3{x,+y,+z},box,velocity,+width,+height,ground,horizontal,vertical,below},yaw,pitch,palette,region,cache} = world
  +position : M.Vec3 = M.Vec3{F.add(x,F.from_f32(0.125)),y,z}
  (W.State{engine,M.Body{position,M.make_box(position,width,height),velocity,width,height,ground,horizontal,vertical,below},yaw,pitch,palette,region,cache},Unit{})

def clock_drift(world:W.State) -> W.State & Unit:
  W.State{G.Engine{core,registry},body,yaw,pitch,palette,region,cache} = world
  (W.State{G.Engine{C.step(core),registry},body,yaw,pitch,palette,region,cache},Unit{})

def forged_stage(stage:X.ApplyStage,mode:U32) -> X.ApplyStage:
  X.ApplyStage{state,pending} = stage
  match mode:
    case 0: X.ApplyStage{RT.with_error(state,Some{"forged-stage-diagnostic"}),pending}
    case 1: X.ApplyStage{discard_query(RT.query(Unit,state,body_drift)),pending}
    case _: X.ApplyStage{discard_query(RT.query(Unit,state,clock_drift)),pending}

def stage_report(+id:String,stage:X.ApplyStage) -> IO(X.ApplyStage):
  X.ApplyStage{state,pending} = stage
  do IO<X.ApplyStage>:
    next:X.State <- state_report(id,state)
    return X.ApplyStage{next,pending}

def guarded_resume(+id:String,result:X.State & Result<&2,&2,X.Error,X.Observation>) -> IO(L.Tables):
  (state,status) = result
  match status:
    case Done{value}: IO.die(L.Tables,3,"forged stage unexpectedly resumed")
    case Fail{cause}:
      do IO<L.Tables>:
        IO.print(id ++ "|guard-error|" ++ RT.error_text(cause))
        retained:X.State <- state_report(id ++ "-after",state)
        return take_tables(retained)

def guarded_query(+id:String,result:X.ApplyStage & Result<&2,&2,X.Error,X.ApplyFacts>) -> IO(L.Tables):
  (stage,status) = result
  guarded_resume(id,X.resume_apply_checked(stage,status))

def guarded_prepared(+id:String,mode:U32,result:X.PrepareResult) -> IO(L.Tables):
  match result:
    case X.Rejected{state,cause}: IO.die(L.Tables,3,"guard fixture prepare:" ++ RT.error_text(cause))
    case X.Paused{state}: IO.die(L.Tables,3,"guard fixture paused")
    case X.AwaitApply{stage}:
      do IO<L.Tables>:
        before:X.ApplyStage <- stage_report(id ++ "-before",forged_stage(stage,mode))
        guarded_query(id,X.stage_query(before,provider_marker))

def guard_case_driver(+id:String,mode:U32,tables:L.Tables,driver:RT.Driver) -> IO(L.Tables):
  RT.Driver{request} = driver
  do IO<L.Tables>:
    state:X.State <- setup(tables,seed_0())
    guarded_prepared(id,mode,X.prepare_local_checked(state,request))

def guard_case(id:String,mode:U32,tables:L.Tables) -> IO(L.Tables):
  guard_case_driver(id,mode,tables,RT.driver())

def stage_guards(tables:L.Tables) -> IO(L.Tables):
  do IO<L.Tables>:
    header:L.Tables <- guard_case("stage-header",0,tables)
    body:L.Tables <- guard_case("stage-body",1,header)
    guard_case("stage-clock",2,body)

def policies(tables:L.Tables) -> IO(L.Tables):
  do IO<L.Tables>:
    initial:X.State <- setup(tables,seed_0())
    before:X.State <- state_report("detour-before",data_tail(initial))
    after:X.State <- state_report("detour-after",RT.reattach(RT.detach(before)))
    refused:X.State <- checked_report("detour",RT.record_checked(after))
    clean:X.State <- setup(take_tables(refused),seed_0())
    packet_before:X.State <- state_report("packet-before",clean)
    packet_after:X.State <- packet_report("packet",RT.input(packet_before,PI.Bindings{1,2,3,4,5,6,7},
      CC.Packet{[CC.PlatformEvent{Key{1,True{}},True{}},CC.PlatformEvent{Look{P.float_bits(2143289344),0.0},True{}}],True{},True{}}))
    paused_before:X.State <- state_report("paused-before",discard_query(RT.query(Unit,packet_after,paused)))
    paused_after:X.State <- state_report("paused-after",RT.realtime_step(RT.driver(),paused_before))
    stepped:X.State <- state_report("paused-explicit-after",RT.step(RT.driver(),paused_after))
    held:X.State <- input_kept(RT.input(stepped,PI.Bindings{1,2,3,4,5,6,7},packet(PI.Buttons{True{},False{},False{},False{},False{},False{},False{}})))
    restore_before:X.State <- state_report("restore-before",held)
    restored:X.State <- packet_report("restore",restore_current(RT.record(restore_before)))
    return take_tables(restored)

def block_rows(values:List<&2,R.Block>) -> String:
  match values:
    case Nil{}: ""
    case R.Block{x,y,z,state,material} <> rest:
      U32.show(F32.bits(x)) ++ "," ++ U32.show(F32.bits(y)) ++ "," ++ U32.show(F32.bits(z)) ++ "," ++ U32.show(state) ++ "," ++ U32.show(material) ++ ";" ++ block_rows(rest)

def snapshot_report(+id:String,result:X.State & Result<&2,&2,String,R.Snapshot>) -> IO(X.State):
  (state,status) = result
  match status:
    case Fail{error}:
      do IO<X.State>:
        IO.print(id ++ "|snapshot-error|" ++ error)
        state_report(id ++ "-after",state)
    case Done{R.Snapshot{tick,revision,blocks,R.Camera{x,y,z,yaw,pitch}}}:
      do IO<X.State>:
        IO.print(id ++ "|snapshot|" ++ Nat.show(tick) ++ "|" ++ Nat.show(revision) ++ "|" ++ block_rows(blocks))
        IO.print(id ++ "|camera|" ++ U32.show(F32.bits(x)) ++ "|" ++ U32.show(F32.bits(y)) ++ "|" ++ U32.show(F32.bits(z)) ++ "|" ++ U32.show(F32.bits(yaw)) ++ "|" ++ U32.show(F32.bits(pitch)))
        state_report(id ++ "-after",state)

def camera_seed(seed:Seed,cell:U32,+crouching:Bool) -> Seed:
  Seed{body,X.Metadata{local,player,sprinting,pose,controls,entity,error,tail},support,minor,history,rest} = seed
  position : M.Vec3 = M.Vec3{F.add(F.from_i32(cell),F.from_f32(0.25)),F.from_u32(1),F.from_f32(0.5)}
  Seed{M.Body.new(position,0.6,W.choose(F32,1.5,1.8,crouching),M.Vec3.zero(),True{}),
    X.Metadata{local,player,sprinting,P.State{W.choose(P.Pose,P.Crouching{},P.Standing{},crouching),W.choose(F32,P.float_bits(1067618140),P.float_bits(1070554153),crouching),[]},controls,entity,error,tail},support,minor,history,rest}

def camera_region(cell:U32,world:W.State) -> W.State:
  W.State{engine,body,yaw,pitch,palette,region,cache} = world
  W.State{engine,body,yaw,pitch,palette,W.Bounds{cell,1,0,2,1,1},None{}}


def camera_cells(world:W.State,+cell:U32) -> IO(W.State):
  match world:
    case W.State{engine,body,yaw,pitch,Some{W.Palette{air,+stone,+dirt,planks}},region,cache}:
      do IO<W.State>:
        created:W.State <- section(W.State{engine,body,yaw,pitch,Some{W.Palette{air,stone,dirt,planks}},region,None{}},cell,0,0)
        first:W.State <- edit_value(created,cell,1,0,stone)
        second:W.State <- edit_value(first,U32.inc(cell),1,0,dirt)
        return camera_region(cell,second)
    case _: IO.die(W.State,3,"camera palette")


def camera_taken(tables:L.Tables,seed:Seed,+cell:U32,result:G.Engine & W.View) -> IO(X.State):
  (engine,view) = result
  do IO<X.State>:
    world:W.State <- camera_cells(W.attach(engine,view),cell)
    return seed_world(tables,seed,world)

def missing_sections(world:W.State) -> W.State & Unit:
  W.State{G.Engine{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},registry},body,yaw,pitch,palette,region,cache} = world
  (W.State{G.Engine{C.World{tick,time,paused,daylight,revision,count,SM.EmptySections{},pending,events},registry},body,yaw,pitch,palette,region,None{}},Unit{})

def camera_rebuilt(+id:String,+cell:U32,crouching:Bool,result:G.Engine & Record.Record & RT.Transient) -> IO(L.Tables):
  (engine,record,RT.Transient{tables,palette,region,cache,buttons,mouse,options,error,owned,motion,metadata}) = result
  do IO<L.Tables>:
    installed:X.State <- camera_taken(tables,camera_seed(seed_0(),cell,crouching),cell,(engine,W.View{W.instrument_body(),0.0,0.0,palette,region,cache}))
    first:X.State <- snapshot_report(id,RT.snapshot(installed,64,48))
    second:X.State <- snapshot_report(id ++ "-cache",RT.snapshot(first,64,48))
    absent:X.State <- state_report(id ++ "-missing-before",discard_query(RT.query(Unit,second,missing_sections)))
    failed:X.State <- snapshot_report(id ++ "-missing",RT.snapshot(absent,64,48))
    return take_tables(failed)


def camera_case(+id:String,+cell:U32,crouching:Bool,tables:L.Tables) -> IO(L.Tables):
  do IO<L.Tables>:
    base:X.State <- setup(tables,seed_0())
    result:G.Engine & Record.Record & RT.Transient = RT.detach(base)
    camera_rebuilt(id,cell,crouching,result)


def cameras(tables:L.Tables) -> IO(L.Tables):
  do IO<L.Tables>:
    near:L.Tables <- camera_case("camera-standing",0,False{},tables)
    crouch:L.Tables <- camera_case("camera-crouching",0,True{},near)
    positive:L.Tables <- camera_case("camera-positive",30000000,False{},crouch)
    camera_case("camera-negative",4264967296,True{},positive)

def loaded(result:Result<&2,&1,L.Error,L.Tables>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.die(Unit,3,"facade sine table")
    case Done{tables}:
      do IO<Unit>:
        actual_tables:L.Tables <- actual(tables)
        policy_tables:L.Tables <- policies(actual_tables)
        owner_tables:L.Tables <- owned_detour(policy_tables)
        guarded_tables:L.Tables <- stage_guards(owner_tables)
        camera_tables:L.Tables <- cameras(guarded_tables)
        IO.print("local-player-runtime|complete|true")

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> path <> rest:
      do IO<Unit>:
        result:Result<&2,&1,L.Error,L.Tables> <- L.Tables.load(path)
        loaded(result)
    case _: IO.die(Unit,2,"facade sine table path required")

def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),arguments)
