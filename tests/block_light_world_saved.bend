import Base
import ../src/block_light_world.bend as W
import ../src/block_light.bend as B
import ../src/core.bend as C
import ../src/section.bend as S
import ../src/section_map.bend as M
import ../src/schedule.bend as Q
import ./block_light_receiver.bend as T
import ./block_light_world_receiver.bend as R

type Summary is Data:
  Summary{sections:Nat,cells:Nat,checksum:U32}
def nat_result(value:Maybe<&2,Nat>) -> Nat:
  match value:
    case None{}: 0n
    case Some{n}: n
def nat(value:String) -> Nat: nat_result(Nat.read(value))
def flag(value:String) -> Bool: String.eq(value,"1")
def fill(fuel:Nat,+index:U32,+id:U32,section:S.Section) -> S.Section:
  match fuel:
    case 0n: section
    case 1n+p:
      fill(p,U32.inc(index),id,B.paired(S.Section,Result<&2,&2,S.Section.Error,Unit>,S.Section,
        S.Section.set_index(section,index,id),section => status => section))
def runs(n:Nat,+index:U32,args:List<String>,section:S.Section) -> S.Section & List<String>:
  match n args:
    case 0n rest: (section,rest)
    case 1n+p +count <> id <> rest:
      runs(p,U32.add(index,T.number(count)),rest,fill(nat(count),index,T.number(id),section))
    case _ _: (section,[])
def sections(n:Nat,args:List<String>,owned:M.Sections) -> M.Sections & List<String>:
  match n args:
    case 0n rest: (owned,rest)
    case 1n+p key <> count <> rest:
      B.paired(S.Section,List<String>,M.Sections & List<String>,runs(nat(count),0,rest,S.Section.new(0)),
        section => tail => sections(p,tail,M.set(owned,key,section)))
    case _ _: (owned,[])
def events(n:Nat,args:List<String>) -> List<&2,C.CoreEvent> & List<String>:
  match n args:
    case 0n rest: ([],rest)
    case 1n+p tick <> peer <> sequence <> revision <> rest:
      B.paired(List<&2,C.CoreEvent>,List<String>,List<&2,C.CoreEvent> & List<String>,events(p,rest),
        events => tail => (C.Applied{Q.Stamp{nat(tick),T.number(peer),nat(sequence)},nat(revision)} <> events,tail))
    case _ _: ([],[])
def checksum(cells:List<&2,U32>,acc:U32) -> U32:
  match cells:
    case Nil{}: acc
    case id <> rest: checksum(rest,U32.mul(U32.xor(acc,id),16777619))
def summary_increment(key:String,+cells:List<&2,U32>,result:C.World & Summary) -> C.World & Summary:
  (world,Summary{sections,count,hash}) = result
  (world,Summary{1n+sections,Nat.add(List.length(&2,U32,cells),count),U32.xor(hash,checksum(cells,M.hash(key)))})
def summary_cell(world:C.World,key:String,result:Maybe<&2,List<&2,U32>>,
    rest:C.World -> C.World & Summary) -> C.World & Summary:
  match result:
    case None{}: rest(world)
    case Some{+cells}:
      summary_increment(key,cells,rest(world))
def summarize_keys(keys:List<&2,String>,world:C.World) -> C.World & Summary:
  match keys:
    case Nil{}: (world,Summary{0n,0n,0})
    case +key <> rest:
      B.paired(C.World,Maybe<&2,List<&2,U32>>,C.World & Summary,W.snapshot(world,key),
        world => cells => summary_cell(world,key,cells,world => summarize_keys(rest,world)))
def summarize(world:C.World) -> C.World & Summary:
  C.World{tick,time,paused,daylight,revision,count,sections,pending,events} = world
  B.paired(M.Sections,List<&2,String>,C.World & Summary,W.section_keys(sections),sections => keys =>
    summarize_keys(keys,C.World{tick,time,paused,daylight,revision,count,sections,pending,events}))
def resident(cells:Map<&2,Maybe<&2,B.Cell>>) -> Nat:
  match cells:
    case MTip{}: 0n
    case MLeaf{key,None{}}: 0n
    case MLeaf{key,Some{cell}}: 1n
    case MNode{p,lo,hi}: Nat.add(resident(lo),resident(hi))
def clock(clock:C.Clock) -> String:
  C.Clock{tick,time,paused,daylight,revision,pending} = clock
  Nat.show(tick) ++ "/" ++ Nat.show(time) ++ "/" ++ Nat.show(revision) ++ "/" ++ Nat.show(pending)
def show_summary(summary:Summary) -> String:
  Summary{sections,cells,hash} = summary
  Nat.show(sections) ++ "/" ++ Nat.show(cells) ++ "/" ++ U32.show(hash)
def edit_positions() -> List<&2,C.Position>:
  [C.Position{"minecraft:overworld",0,0,0},C.Position{"minecraft:overworld",1,0,0},
   C.Position{"minecraft:overworld",4294967295,0,0},C.Position{"minecraft:overworld",16,0,0}]
def actual_edit_removed(+context:R.Fixture,state:W.State) -> IO(Unit):
  +p : C.Position = C.Position{"minecraft:overworld",0,0,0}
  B.paired(W.State,Result<&2,&2,W.Error,W.FrameSamples>,IO(Unit),
    W.sample_batch(edit_positions(),R.settle(100000n,context,64n,
      R.accepted(W.apply_finished(Q.Stamp{276n,0,2n},W.apply(~R.Fixture,~R.properties,~R.enabled,
        context,state,C.BlockSet{p,0}))))),state => frame => IO.print("remove " ++ R.show_frame(frame)))
def actual_edit(+context:R.Fixture,state:W.State) -> IO(Unit):
  +p : C.Position = C.Position{"minecraft:overworld",0,0,0}
  B.paired(W.State,Result<&2,&2,W.Error,W.FrameSamples>,IO(Unit),
    W.sample_batch(edit_positions(),R.settle(100000n,context,64n,
      R.accepted(W.apply_finished(Q.Stamp{276n,0,1n},W.apply(~R.Fixture,~R.properties,~R.enabled,
        context,state,C.BlockSet{p,4926}))))),state => frame => (
      do IO<Unit>:
        IO.print("add " ++ R.show_frame(frame))
        actual_edit_removed(context,state)
    ))
def loaded(context:R.Fixture,state:W.State,before:Summary) -> IO(Unit):
  W.State{world,B.State{+cells,front,back,queued,pending},loading} = state
  B.paired(C.World,Summary,IO(Unit),summarize(world),world => after =>
    B.paired(C.World,C.Clock,IO(Unit),C.clock(world),world => current => (
      do IO<Unit>:
        IO.print(show_summary(before) ++ " " ++ show_summary(after) ++ " " ++ clock(current) ++ " " ++ Nat.show(resident(cells)))
        B.paired(W.State,Result<&2,&2,W.Error,W.FrameSamples>,IO(Unit),
          W.sample_batch([],W.State{world,B.State{cells,front,back,queued,pending},loading}),
          state => result => (
            do IO<Unit>:
              IO.print(R.show_frame(result))
              actual_edit(context,state)
          ))
    )))
def seed_line(fuel:Nat,+x:U32,world:C.World) -> C.World:
  match fuel:
    case 0n: world
    case 1n+p:
      seed_line(p,U32.inc(x),R.world_applied(C.apply(world,
        C.BlockSet{C.Position{"minecraft:overworld",x,8,8},0})))
def seed_world() -> C.World:
  +d : String = "minecraft:overworld"
  R.world_applied(C.apply(
    R.world_applied(C.apply(
      R.world_applied(C.apply(
        seed_line(25n,0,R.world_applied(C.apply(
          R.world_applied(C.apply(C.new(35723),C.SectionCreate{C.Position{d,0,0,0},1})),
          C.SectionCreate{C.Position{d,16,0,0},1}))),
        C.BlockSet{C.Position{d,2,8,8},8686})),
      C.BlockSet{C.Position{d,5,8,8},15180})),
    C.BlockSet{C.Position{d,6,8,8},15178}))
def seed_positions(fuel:Nat,+x:U32) -> List<&2,C.Position>:
  match fuel:
    case 0n: [C.Position{"minecraft:overworld",32,8,8}]
    case 1n+p: C.Position{"minecraft:overworld",x,8,8} <> seed_positions(p,U32.inc(x))
def seed_disabled(context:R.Fixture) -> IO(Unit):
  B.paired(W.State,Result<&2,&2,W.Error,W.FrameSamples>,IO(Unit),
    W.sample_batch(seed_positions(25n,0),R.load(10000n,context,W.begin(seed_world()))),
    state => frame => IO.print("disabled " ++ R.show_frame(frame)))
def disable(context:R.Fixture) -> R.Fixture:
  R.Fixture{entries,edges,disabled} = context
  R.Fixture{entries,edges,True{}}
def seed_checks(+context:R.Fixture) -> IO(Unit):
  B.paired(W.State,Result<&2,&2,W.Error,W.FrameSamples>,IO(Unit),
    W.sample_batch([],R.load(10000n,context,W.begin(seed_world()))),state => pending =>
    B.paired(W.State,Result<&2,&2,W.Error,W.FrameSamples>,IO(Unit),
      W.sample_batch(seed_positions(25n,0),R.settle(100000n,context,64n,state)),state => frame => (
        do IO<Unit>:
          IO.print("seed_pending " ++ R.show_frame(pending))
          IO.print("seed " ++ R.show_frame(frame))
          seed_disabled(disable(context))
      )))
def world_ready(+context:R.Fixture,world:C.World) -> IO(Unit):
  do IO<Unit>:
    seed_checks(context)
    B.paired(C.World,Summary,IO(Unit),summarize(world),world => before => (
      do IO<Unit>:
        start : Nat <- IO.now()
        state : W.State <- IO.pure(W.State,R.load(10000n,context,W.begin(world)))
        stop : Nat <- IO.now()
        IO.print("bootstrap_ms " ++ Nat.show(Nat.sub(stop,start)))
        loaded(context,state,before)
    ))
def world_events(context:R.Fixture,tick:Nat,time:Nat,paused:Bool,daylight:Bool,
    revision:Nat,count:U32,sections:M.Sections,result:List<&2,C.CoreEvent> & List<String>) -> IO(Unit):
  (events,tail) = result
  world_ready(context,C.World{tick,time,paused,daylight,revision,count,sections,[],events})
def world_sections(context:R.Fixture,tick:Nat,time:Nat,paused:Bool,daylight:Bool,
    revision:Nat,count:U32,result:M.Sections & List<String>) -> IO(Unit):
  (sections,args) = result
  match args:
    case n <> rest: world_events(context,tick,time,paused,daylight,revision,count,sections,events(nat(n),rest))
    case _: IO.die(Unit,1,"saved-world receiver events missing")
def world_args(context:R.Fixture,args:List<String>) -> IO(Unit):
  match args:
    case tick <> time <> paused <> daylight <> revision <> count <> n <> rest:
      world_sections(context,nat(tick),nat(time),flag(paused),flag(daylight),nat(revision),T.number(count),
        sections(nat(n),rest,M.EmptySections{}))
    case _: IO.die(Unit,1,"saved-world receiver metadata missing")
def with_edges(entries:Map<&2,Maybe<&2,B.Descriptor>>,result:Map<&2,Bool> & List<String>) -> IO(Unit):
  (edges,args) = result
  world_args(R.Fixture{entries,edges,False{}},args)
def with_catalog(result:Map<&2,Maybe<&2,B.Descriptor>> & List<String>) -> IO(Unit):
  (entries,args) = result
  match args:
    case n <> rest: with_edges(entries,T.edges(nat(n),rest,MTip{}))
    case _: IO.die(Unit,1,"saved-world receiver shapes missing")
def run(args:List<String>) -> IO(Unit):
  match args:
    case program <> n <> rest: with_catalog(R.catalog(nat(n),rest,MTip{}))
    case _: IO.die(Unit,1,"saved-world receiver properties missing")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
