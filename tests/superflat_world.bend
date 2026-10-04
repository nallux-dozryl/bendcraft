import Base
import ../src/superflat_world.bend as SF
import ../src/client_world.bend as W
import ../src/core.bend as C
import ../src/game.bend as G
import ../src/registry.bend as B
import ../src/section_map.bend as SM
import ../src/section.bend as Section
import ../src/schedule.bend as Q
import ../src/movement.bend as M
import ../src/f64.bend as F
import ../src/geometry.bend as A

def number_result(result:Maybe<&2,U32>) -> U32:
  match result:
    case Some{n}: n
    case None{}: 0

def number(text:String) -> U32:
  number_result(U32.read(text))

def bounds_text(result:Result<&2,&2,String,W.Bounds>) -> String:
  match result:
    case Fail{message}: "fail|" ++ message
    case Done{W.Bounds{x,y,z,w,h,d}}:
      U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ "," ++ U32.show(d)

def body(x:U32,y:U32,z:U32) -> M.Body:
  M.Body.new(M.Vec3{F.from_i32(x),F.from_i32(y),F.from_i32(z)},0.6,1.8,M.Vec3.zero(),True{})

def float_word(word:U32) -> F32:
  match word:
    case U32{bits}: F32{bits}

def scalar(value:F.F64) -> String:
  F.F64{hi,lo} = value
  U32.show(hi) ++ "," ++ U32.show(lo)

def vector(value:M.Vec3) -> String:
  M.Vec3{x,y,z} = value
  scalar(x) ++ "," ++ scalar(y) ++ "," ++ scalar(z)

def box_text(box:A.AABB) -> String:
  A.AABB{a,b,c,d,e,f} = box
  scalar(a) ++ "," ++ scalar(b) ++ "," ++ scalar(c) ++ "," ++ scalar(d) ++ "," ++ scalar(e) ++ "," ++ scalar(f)

def palette_text(palette:W.Palette) -> String:
  W.Palette{a,b,c,d} = palette
  U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d)

def optional_palette_text(value:Maybe<&2,W.Palette>) -> String:
  match value:
    case None{}: "none"
    case Some{palette}: palette_text(palette)

def raw_blocks_text(values:List<&2,W.RawBlock>) -> String:
  match values:
    case Nil{}: ""
    case W.RawBlock{W.Cell{x,y,z,boundary},state,material} <> rest:
      U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ U32.show(boundary) ++ "," ++
      U32.show(state) ++ "," ++ U32.show(material) ++ ";" ++ raw_blocks_text(rest)

def cache_text(value:Maybe<&2,W.SnapshotCache>) -> String:
  match value:
    case None{}: "none"
    case Some{W.SnapshotCache{revision,region,palette,blocks}}:
      Nat.show(revision) ++ "/" ++ bounds_text(Done{region}) ++ "/" ++ palette_text(palette) ++ "/" ++ raw_blocks_text(blocks)

def view_report(state:W.State) -> W.State & String:
  W.State{engine,+body,+yaw,+pitch,+palette,+region,+cache} = state
  M.Body{M.Vec3{x,y,z},box,velocity,width,height,ground,horizontal,vertical,below} = body
  (W.State{engine,body,yaw,pitch,palette,region,cache},
    bounds_text(Done{region}) ++ "|" ++ U32.show(Bool.to_u32(Bool.not(Maybe.is_none(&2,W.SnapshotCache,cache)))) ++
    "|" ++ scalar(x) ++ "," ++ scalar(y) ++ "," ++ scalar(z) ++ "|" ++ box_text(box) ++ "|" ++ vector(velocity) ++
    "|" ++ U32.show(F32.bits(width)) ++ "," ++ U32.show(F32.bits(height)) ++ "," ++ U32.show(Bool.to_u32(ground)) ++
    "," ++ U32.show(Bool.to_u32(horizontal)) ++ "," ++ U32.show(Bool.to_u32(vertical)) ++ "," ++ U32.show(Bool.to_u32(below)) ++
    "|" ++ U32.show(F32.bits(yaw)) ++ "," ++ U32.show(F32.bits(pitch)) ++ "|" ++ optional_palette_text(palette) ++ "|" ++ cache_text(cache))

def cached(state:W.State) -> W.State:
  W.State{engine,body,yaw,pitch,palette,+region,cache} = state
  M.Body{position,box,velocity,width,height,ground,horizontal,vertical,below} = body
  W.State{engine,M.Body{position,box,M.Vec3{F.from_f32(0.125),F.from_f32(F32.neg(0.25)),F.from_f32(0.5)},width,height,False{},True{},True{},True{}},
    1.25,F32.neg(0.5),Some{W.Palette{0,1,10,15}},region,
    Some{W.SnapshotCache{999n,region,W.Palette{0,1,10,15},[W.RawBlock{W.Cell{0,4294967235,0,19},1,1}]}}}

def translated(state:W.State) -> W.State:
  W.State{engine,old,yaw,pitch,palette,region,cache} = state
  W.State{engine,body(1,4294967236,0),yaw,pitch,palette,region,cache}

def follow_state(result:W.State & Unit) -> W.State:
  (state,unit) = result
  state

def digest_words(fuel:Nat,blocks:Array<U32>,+index:U32,digest:U32) -> Array<U32> & U32:
  match fuel:
    case 0n: (blocks,digest)
    case 1n+rest:
      W.paired(Array<U32>,U32,Array<U32> & U32,Array.get(U32,blocks,index),
        kept => word => digest_words(rest,kept,U32.inc(index),U32.mul(U32.xor(digest,word),16777619)))

def section_digest(section:Section.Section) -> Section.Section & U32:
  Section.Section{blocks} = section
  W.paired(Array<U32>,U32,Section.Section & U32,digest_words(4096n,blocks,0,2166136261),
    kept => digest => (Section.Section{kept},digest))

def entry_reports(entries:List<&1,SM.Entry>) -> List<&1,SM.Entry> & String:
  match entries:
    case Nil{}: ([],"")
    case SM.Entry{+key,section} <> rest:
      W.paired(Section.Section,U32,List<&1,SM.Entry> & String,section_digest(section),
        kept => digest => W.paired(List<&1,SM.Entry>,String,List<&1,SM.Entry> & String,entry_reports(rest),
          tail => text => (SM.Entry{key,kept} <> tail,key ++ "=" ++ U32.show(digest) ++ ";" ++ text)))

def section_reports(sections:SM.Sections) -> SM.Sections & String:
  match sections:
    case SM.EmptySections{}: (SM.EmptySections{},"")
    case SM.Bucket{entries}:
      W.paired(List<&1,SM.Entry>,String,SM.Sections & String,entry_reports(entries),
        kept => text => (SM.Bucket{kept},text))
    case SM.Branch{left,right}:
      W.paired(SM.Sections,String,SM.Sections & String,section_reports(left),
        lo => text => W.paired(SM.Sections,String,SM.Sections & String,section_reports(right),
          hi => suffix => (SM.Branch{lo,hi},text ++ suffix)))

def stamp_text(stamp:Q.Stamp) -> String:
  Q.Stamp{tick,peer,sequence} = stamp
  Nat.show(tick) ++ "," ++ U32.show(peer) ++ "," ++ Nat.show(sequence)

def position_text(position:C.Position) -> String:
  C.Position{dimension,x,y,z} = position
  dimension ++ "," ++ U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z)

def mutation_text(mutation:C.Mutation) -> String:
  match mutation:
    case C.SectionCreate{position,fill}: "section," ++ position_text(position) ++ "," ++ U32.show(fill)
    case C.BlockSet{position,state}: "block," ++ position_text(position) ++ "," ++ U32.show(state)
    case C.TimeSet{time}: "time," ++ Nat.show(time)
    case C.DaylightSet{enabled}: "daylight," ++ U32.show(Bool.to_u32(enabled))

def pending_text(values:List<&2,Q.Pending<C.Mutation>>) -> String:
  match values:
    case Nil{}: ""
    case Q.Pending{stamp,mutation} <> rest:
      stamp_text(stamp) ++ "," ++ mutation_text(mutation) ++ ";" ++ pending_text(rest)

def events_text(values:List<&2,C.CoreEvent>) -> String:
  match values:
    case Nil{}: ""
    case C.Applied{stamp,revision} <> rest:
      "applied," ++ stamp_text(stamp) ++ "," ++ Nat.show(revision) ++ ";" ++ events_text(rest)
    case C.Rejected{stamp,error} <> rest:
      "rejected," ++ stamp_text(stamp) ++ "," ++ W.error_text(error) ++ ";" ++ events_text(rest)

def core_reported(registry:B.Registry,view:W.View,+tick:Nat,+time:Nat,+paused:Bool,+daylight:Bool,+revision:Nat,
    +count:U32,+pending:List<&2,Q.Pending<C.Mutation>>,+events:List<&2,C.CoreEvent>,
    result:SM.Sections & String) -> W.State & String:
  (sections,text) = result
  (W.attach(G.Engine{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},registry},view),
    Nat.show(tick) ++ "," ++ Nat.show(time) ++ "," ++ U32.show(Bool.to_u32(paused)) ++ "," ++
    U32.show(Bool.to_u32(daylight)) ++ "," ++ Nat.show(revision) ++ "," ++ U32.show(count) ++ "|" ++ text ++
    "|" ++ pending_text(pending) ++ "|" ++ events_text(events))

def core_report_taken(result:G.Engine & W.View) -> W.State & String:
  (G.Engine{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},registry},view) = result
  core_reported(registry,view,tick,time,paused,daylight,revision,count,pending,events,section_reports(sections))

def core_report(state:W.State) -> W.State & String:
  core_report_taken(W.take(state))

def report(id:String,result:W.State & String) -> IO(W.State):
  (state,text) = result
  IO.bind(Unit,W.State,IO.print(id ++ "|" ++ text),unit => IO.pure(W.State,state))

def initialized_view(result:W.State & Result<&2,&2,String,Unit>) -> IO(W.State):
  (W.State{engine,old,yaw,pitch,palette,region,cache},status) = result
  IO.pure(W.State,W.State{engine,body(0,4294967236,0),yaw,pitch,palette,SF.initial_region(),None{}})

def follow_tests(engine:G.Engine) -> IO(Unit):
  do IO<Unit>:
    initial : W.State <- initialized_view(W.new(engine))
    before : W.State <- report("follow-before",view_report(cached(initial)))
    same : W.State <- report("follow-same",view_report(follow_state(SF.follow(before))))
    changed : W.State <- report("follow-crossing-before",view_report(translated(same)))
    moved : W.State <- report("follow-moved",view_report(follow_state(SF.follow(changed))))
    final : W.State <- report("follow-core",core_report(moved))
    IO.pure(Unit,Unit{})

def read_result(view:W.View,registry:B.Registry,result:C.World & Result<&2,&2,C.Error,U32>) -> W.State & String:
  (world,status) = result
  match status:
    case Fail{error}: (W.attach(G.Engine{world,registry},view),"fail:" ++ W.error_text(error))
    case Done{state}: (W.attach(G.Engine{world,registry},view),U32.show(state))

def read_taken(position:C.Position,result:G.Engine & W.View) -> W.State & String:
  (G.Engine{world,registry},view) = result
  read_result(view,registry,C.read_block(world,position))

def read(state:W.State,position:C.Position) -> W.State & String:
  read_taken(position,W.take(state))

def probes(positions:List<&2,C.Position>,state:W.State) -> IO(W.State):
  match positions:
    case Nil{}: IO.pure(W.State,state)
    case +position <> rest:
      C.Position{dimension,x,y,z} = position
      do IO<W.State>:
        kept : W.State <- report("cell|" ++ U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z),read(state,position))
        probes(rest,kept)

def column(+x:U32,+z:U32) -> List<&2,C.Position>:
  [C.Position{"minecraft:overworld",x,4294967215,z},
   C.Position{"minecraft:overworld",x,4294967216,z},
   C.Position{"minecraft:overworld",x,4294967231,z},
   C.Position{"minecraft:overworld",x,4294967232,z},
   C.Position{"minecraft:overworld",x,4294967233,z},
   C.Position{"minecraft:overworld",x,4294967234,z},
   C.Position{"minecraft:overworld",x,4294967235,z},
   C.Position{"minecraft:overworld",x,4294967236,z},
   C.Position{"minecraft:overworld",x,4294967263,z},
   C.Position{"minecraft:overworld",x,4294967264,z}]

def edit_core(view:W.View,registry:B.Registry,world:C.World) -> W.State:
  C.World{tick,time,paused,daylight,revision,count,sections,pending,events} = world
  W.attach(G.Engine{C.World{tick,57n,False{},False{},revision,count,sections,
    [Q.Pending{Q.Stamp{5n,7,9n},C.BlockSet{C.Position{"minecraft:overworld",1,4294967235,0},1}}],events},registry},view)

def edit_result(view:W.View,registry:B.Registry,result:C.World & Result<&2,&2,C.Error,Unit>) -> W.State:
  (world,status) = result
  edit_core(view,registry,C.accepted(world,Q.Stamp{0n,7,1n}))

def edit_taken(result:G.Engine & W.View) -> W.State:
  (G.Engine{world,registry},view) = result
  edit_result(view,registry,C.write_block(world,C.Position{"minecraft:overworld",0,4294967235,0},0))

def reinitialized(result:W.State & Result<&2,&2,String,SF.Outcome>) -> IO(W.State):
  (state,status) = result
  match status:
    case Done{SF.Existing{}}: IO.pure(W.State,state)
    case _: IO.die(W.State,2,"edited superflat was regenerated")

def generated(+profile:SF.Profile,result:W.State & Result<&2,&2,String,SF.Outcome>) -> IO(Unit):
  (state,status) = result
  match status:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{outcome}:
      do IO<Unit>:
        first : W.State <- report("generated|" ++ SF.profile_name(profile),core_report(state))
        viewed : W.State <- report("generated-view",view_report(first))
        samples : W.State <- probes(List.append(&2,C.Position,column(4294967264,4294967264),
          List.append(&2,C.Position,column(4294967279,4294967295),
          List.append(&2,C.Position,column(4294967280,0),
          List.append(&2,C.Position,column(4294967295,15),
          List.append(&2,C.Position,column(0,16),
          List.append(&2,C.Position,column(15,31),
          List.append(&2,C.Position,column(16,32),column(47,47)))))))),viewed)
        outside : W.State <- probes([C.Position{"minecraft:overworld",4294967263,4294967232,0},
          C.Position{"minecraft:overworld",48,4294967232,0},C.Position{"minecraft:overworld",0,4294967232,48}],samples)
        before : W.State <- report("edited-before",core_report(edit_taken(W.take(outside))))
        before_view : W.State <- report("edited-view-before",view_report(cached(before)))
        loaded : W.State <- reinitialized(SF.initialize_profile(before_view,profile))
        after : W.State <- report("edited-after",core_report(loaded))
        after_view : W.State <- report("edited-view-after",view_report(after))
        IO.pure(Unit,Unit{})

def world_ready(+profile:SF.Profile,result:W.State & Result<&2,&2,String,Unit>) -> IO(Unit):
  (state,status) = result
  match status:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{unit}: generated(profile,SF.initialize_profile(state,profile))

def command_fields(fields:List<&2,String>) -> IO(Unit):
  match fields:
    case "bounds" <> id <> x <> y <> z <> Nil{}:
      IO.print("bounds|" ++ id ++ "|" ++ bounds_text(SF.body_region(body(number(x),number(y),number(z)))))
    case "bounds-float" <> id <> x <> y <> z <> Nil{}:
      IO.print("bounds|" ++ id ++ "|" ++ bounds_text(SF.body_region(
        M.Body.new(M.Vec3{F.from_f32(float_word(number(x))),F.from_f32(float_word(number(y))),F.from_f32(float_word(number(z)))},0.6,1.8,M.Vec3.zero(),True{}))))
    case "follow" <> Nil{}: IO.bind(G.Engine,Unit,G.load(),follow_tests)
    case "custom" <> Nil{}:
      IO.bind(G.Engine,Unit,G.load(),engine => world_ready(SF.StoneDirtFlat{},W.new(engine)))
    case "classic" <> Nil{}:
      IO.bind(G.Engine,Unit,G.load(),engine => world_ready(SF.ClassicFlat{},W.new(engine)))
    case _: IO.die(Unit,2,"invalid superflat test command")

def command(text:String) -> IO(Unit):
  command_fields(String.split(text,'|'))

def run(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case text <> rest:
      IO.bind(Unit,Unit,command(text),unit => run(rest))

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case exe <> rest: run(rest)
    case Nil{}: IO.pure(Unit,Unit{})

def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),arguments)
