import Base
import ../src/block_light_world.bend as W
import ../src/block_light.bend as B
import ../src/core.bend as C
import ../src/section.bend as S
import ../src/schedule.bend as Q
import ./block_light_receiver.bend as T

type Fixture is Data:
  Fixture{properties:Map<&2,Maybe<&2,B.Descriptor>>,edges:Map<&2,Bool>,disabled:Bool}
def properties(context:Fixture,id:U32) -> Maybe<&2,B.Descriptor>:
  Fixture{entries,edges,disabled} = context
  B.paired(Map<&2,Maybe<&2,B.Descriptor>>,Maybe<&2,B.Descriptor>,Maybe<&2,B.Descriptor>,
    Map.get(Maybe<&2,B.Descriptor>,None{},entries,U32.show(id)),entries => result => result)
def enabled(context:Fixture,position:C.Position) -> Bool:
  Fixture{entries,edges,disabled} = context
  Bool.not(disabled)
def occludes(context:Fixture,from:B.Descriptor,to:B.Descriptor,direction:B.Direction) -> Bool:
  Fixture{entries,edges,disabled} = context
  T.occludes(edges,from,to,direction)
def catalog(n:Nat,args:List<String>,entries:Map<&2,Maybe<&2,B.Descriptor>>) ->
    Map<&2,Maybe<&2,B.Descriptor>> & List<String>:
  match n args:
    case 0n rest: (entries,rest)
    case 1n+p +id <> e <> d <> rest:
      catalog(p,rest,Map.set(&2,Maybe<&2,B.Descriptor>,entries,id,
        Some{B.Descriptor{T.number(id),T.number(e),T.number(d)}}))
    case _ _: (entries,[])
def world_applied(result:C.World & Result<&2,&2,C.Error,Unit>) -> C.World:
  (world,status) = result
  world
def initial_cell(world:C.World,+position:C.Position) -> C.World:
  world_applied(C.apply(world_applied(C.apply(world,C.SectionCreate{position,1})),C.BlockSet{position,0}))
def initial(n:Nat,args:List<String>,world:C.World,positions:List<&2,C.Position>) ->
    C.World & List<&2,C.Position> & List<String>:
  match n args:
    case 0n rest: (world,List.reverse(&2,C.Position,positions),rest)
    case 1n+p x <> y <> z <> rest:
      +position : C.Position = C.Position{"minecraft:overworld",T.number(x),T.number(y),T.number(z)}
      initial(p,rest,initial_cell(world,position),position <> positions)
    case _ _: (world,positions,[])
def load_result(result:W.State & Result<&2,&2,W.Error,Unit>,next:W.State -> W.State) -> W.State:
  (state,status) = result
  match status:
    case Fail{error}: state
    case Done{u}: next(state)
def load_progress(result:W.State & W.Progress,next:W.State -> W.State) -> W.State:
  (state,status) = result
  match status:
    case W.Loading{}: next(state)
    case other: state
def load(fuel:Nat,+context:Fixture,state:W.State) -> W.State:
  match fuel:
    case 0n: state
    case 1n+p:
      load_result(W.load_resume(~Fixture,~properties,~enabled,context,256n,state),state =>
        load_progress(W.progress(state),state => load(p,context,state)))
def settled(result:W.State & W.Progress,next:W.State -> W.State) -> W.State:
  (state,status) = result
  match status:
    case W.Propagating{pending}: next(state)
    case other: state
def settle(fuel:Nat,+context:Fixture,+budget:Nat,state:W.State) -> W.State:
  match fuel:
    case 0n: state
    case 1n+p:
      settled(W.advance(~Fixture,~occludes,context,budget,state),state => settle(p,context,budget,state))
def accepted(result:W.State & Result<&2,&2,W.Error,Unit>) -> W.State:
  (state,status) = result
  state
def edits(n:Nat,+context:Fixture,args:List<String>,state:W.State) -> W.State & List<String>:
  match n args:
    case 0n rest: (state,rest)
    case 1n+p x <> y <> z <> id <> rest:
      edits(p,context,rest,accepted(W.apply(~Fixture,~properties,~enabled,context,state,
        C.BlockSet{C.Position{"minecraft:overworld",T.number(x),T.number(y),T.number(z)},T.number(id)})))
    case _ _: (state,[])
def show_cells(cells:List<&2,W.Observation>) -> String:
  match cells:
    case Nil{}: ""
    case W.Observation{p,block,light} <> rest:
      T.show_level(block) ++ ":" ++ T.show_level(light) ++ " " ++ show_cells(rest)
def show_frame(result:Result<&2,&2,W.Error,W.FrameSamples>) -> String:
  match result:
    case Fail{error}: "refused"
    case Done{W.FrameSamples{C.Clock{tick,time,paused,daylight,revision,pending},cells}}:
      "stable " ++ Nat.show(tick) ++ "/" ++ Nat.show(revision) ++ " " ++ show_cells(cells)
def phases(n:Nat,+context:Fixture,+budget:Nat,+positions:List<&2,C.Position>,
    args:List<String>,state:W.State) -> IO(Unit):
  match n args:
    case 0n _: IO.pure(Unit,Unit{})
    case 1n+p count <> rest:
      B.paired(W.State,List<String>,IO(Unit),edits(U32.to_nat(T.number(count)),context,rest,state),state => args =>
        B.paired(W.State,Result<&2,&2,W.Error,W.FrameSamples>,IO(Unit),
          W.sample_batch(positions,settle(100000n,context,budget,state)),state => frame => (
            do IO<Unit>:
              IO.print(show_frame(frame))
              phases(p,context,budget,positions,args,state)
          )))
    case _ _: IO.die(Unit,1,"block_light_world: incomplete edits")
def fixture_initial(+context:Fixture,budget:Nat,
    created:C.World & List<&2,C.Position> & List<String>) -> IO(Unit):
  (world,(positions,args)) = created
  match args:
    case n <> rest:
      phases(U32.to_nat(T.number(n)),context,budget,positions,rest,load(10000n,context,W.begin(world)))
    case _: IO.die(Unit,1,"block_light_world: incomplete phases")
def fixture_edges(entries:Map<&2,Maybe<&2,B.Descriptor>>,budget:Nat,
    result:Map<&2,Bool> & List<String>) -> IO(Unit):
  (edges,args) = result
  match args:
    case n <> rest:
      fixture_initial(Fixture{entries,edges,False{}},budget,initial(U32.to_nat(T.number(n)),rest,C.new(35723),[]))
    case _: IO.die(Unit,1,"block_light_world: incomplete domain")
def fixture_catalog(budget:Nat,result:Map<&2,Maybe<&2,B.Descriptor>> & List<String>) -> IO(Unit):
  (entries,args) = result
  match args:
    case n <> rest: fixture_edges(entries,budget,T.edges(U32.to_nat(T.number(n)),rest,MTip{}))
    case _: IO.die(Unit,1,"block_light_world: incomplete edges")

def guard_context() -> Fixture:
  Fixture{Map.set(&2,Maybe<&2,B.Descriptor>,
    Map.set(&2,Maybe<&2,B.Descriptor>,MTip{},"0",Some{B.Descriptor{0,0,0}}),
    "4926",Some{B.Descriptor{4926,14,0}}),MTip{},False{}}
def guard_world() -> C.World:
  world_applied(C.apply(C.new(35723),C.SectionCreate{C.Position{"minecraft:overworld",0,0,0},0}))
def outcome(result:Result<&2,&2,W.Error,Unit>) -> String:
  match result:
    case Done{u}: "accepted"
    case Fail{W.CoreFailure{C.PermissionDenied{}}}: "permission"
    case Fail{W.CoreFailure{C.InvalidState{id}}}: "invalid"
    case Fail{W.CoreFailure{C.MissingSection{key}}}: "missing"
    case Fail{W.CoreFailure{C.SectionExists{key}}}: "duplicate"
    case Fail{W.MissingDescriptor{id}}: "catalog"
    case Fail{W.InvalidDescriptor{id}}: "descriptor"
    case Fail{W.LoadingInProgress{}}: "loading"
    case Fail{other}: "other"
def guard_finished(state:W.State) -> IO(Unit):
  +context = guard_context()
  +p : C.Position = C.Position{"minecraft:overworld",0,0,0}
  B.paired(W.State,Result<&2,&2,W.Error,Unit>,IO(Unit),
    W.admit(~Fixture,~properties,~enabled,context,state,C.Developer{},Q.Stamp{1n,1,1n},C.BlockSet{p,4926}),state => admitted =>
    B.paired(W.State,Result<&2,&2,W.Error,Unit>,IO(Unit),
      W.step(~Fixture,~properties,~enabled,Fixture{MTip{},MTip{},False{}},state),state => missing =>
      B.paired(W.State,Result<&2,&2,W.Error,Unit>,IO(Unit),
        W.step(~Fixture,~properties,~enabled,context,state),state => stepped =>
        B.paired(W.State,Result<&2,&2,W.Error,W.FrameSamples>,IO(Unit),
          W.sample_batch([p],state),state => provisional =>
          B.paired(W.State,Result<&2,&2,W.Error,W.FrameSamples>,IO(Unit),
            W.sample_batch([p,C.Position{"minecraft:overworld",16,0,0}],settle(100000n,context,64n,state)),
            state => frame => IO.print(outcome(admitted) ++ " " ++ outcome(missing) ++ " " ++
              outcome(stepped) ++ " " ++ show_frame(provisional) ++ " " ++ show_frame(frame)))))))
def guard_edits(state:W.State) -> IO(Unit):
  +context = guard_context()
  +p : C.Position = C.Position{"minecraft:overworld",0,0,0}
  B.paired(W.State,Result<&2,&2,W.Error,Unit>,IO(Unit),
    W.admit(~Fixture,~properties,~enabled,context,state,C.Observer{},Q.Stamp{1n,1,1n},C.BlockSet{p,1}),state => permission =>
    B.paired(W.State,Result<&2,&2,W.Error,Unit>,IO(Unit),
      W.apply(~Fixture,~properties,~enabled,context,state,C.BlockSet{p,35723}),state => invalid =>
      B.paired(W.State,Result<&2,&2,W.Error,Unit>,IO(Unit),
        W.apply(~Fixture,~properties,~enabled,context,state,C.BlockSet{p,1}),state => catalog =>
        B.paired(W.State,Result<&2,&2,W.Error,Unit>,IO(Unit),
          W.apply(~Fixture,~properties,~enabled,context,state,C.SectionCreate{p,0}),state => duplicate =>
          B.paired(W.State,Result<&2,&2,W.Error,Unit>,IO(Unit),
            W.apply(~Fixture,~properties,~enabled,context,state,
              C.BlockSet{C.Position{"minecraft:overworld",16,0,0},0}),state => missing => (
                do IO<Unit>:
                  IO.print(outcome(permission) ++ " " ++ outcome(invalid) ++ " " ++ outcome(catalog) ++ " " ++
                    outcome(duplicate) ++ " " ++ outcome(missing))
                  guard_finished(state)
              ))))))
def guards() -> IO(Unit):
  guard_edits(settle(100000n,guard_context(),64n,load(10000n,guard_context(),W.begin(guard_world()))))

def run(args:List<String>) -> IO(Unit):
  match args:
    case "guards" <> _: guards()
    case budget <> count <> rest:
      fixture_catalog(U32.to_nat(T.number(budget)),catalog(U32.to_nat(T.number(count)),rest,MTip{}))
    case _: IO.die(Unit,1,"block_light_world: missing args")
def args(args:List<String>) -> IO(Unit):
  match args:
    case program <> rest: run(rest)
    case _: IO.die(Unit,1,"block_light_world: missing argv")
def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
