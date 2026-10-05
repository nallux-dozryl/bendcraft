import Base
import ../src/sky_light_world.bend as W
import ../src/block_light.bend as B
import ../src/block_light_world.bend as BW
import ../src/core.bend as C
import ../src/schedule.bend as Q
import ./block_light_receiver.bend as T

# CLI input contains geometry and observed block/face properties only.
# Java light levels and source heights never enter the native executable.
type Fixture is Data:
  Fixture{properties:Map<&2,Maybe<&2,B.Descriptor>>,edges:Map<&2,Bool>,
    bounds:W.Bounds,enabled:Bool,known_empty:Bool}
def properties(context:Fixture,id:U32) -> Maybe<&2,B.Descriptor>:
  Fixture{entries,edges,bounds,enabled,known} = context
  B.paired(Map<&2,Maybe<&2,B.Descriptor>>,Maybe<&2,B.Descriptor>,Maybe<&2,B.Descriptor>,
    Map.get(Maybe<&2,B.Descriptor>,None{},entries,U32.show(id)),entries => found => found)
def bounds(context:Fixture,dimension:String) -> Maybe<&2,W.Bounds>:
  Fixture{entries,edges,bounds,enabled,known} = context
  Some{bounds}
def enabled(context:Fixture,position:C.Position) -> Bool:
  Fixture{entries,edges,bounds,enabled,known} = context
  enabled
def section_policy(context:Fixture,position:C.Position) -> W.SectionPolicy:
  Fixture{entries,edges,bounds,enabled,known} = context
  match known:
    case True{}: W.KnownEmpty{}
    case False{}: W.Unknown{}
def occludes(context:Fixture,from:B.Descriptor,to:B.Descriptor,direction:B.Direction) -> Bool:
  Fixture{entries,edges,bounds,enabled,known} = context
  T.occludes(edges,from,to,direction)
def flag(value:String) -> Bool:
  U32.is_gt(T.number(value),0)
def catalog(n:Nat,args:List<String>,entries:Map<&2,Maybe<&2,B.Descriptor>>) ->
    Map<&2,Maybe<&2,B.Descriptor>> & List<String>:
  match n args:
    case 0n rest: (entries,rest)
    case 1n+p +id <> dampening <> rest:
      catalog(p,rest,Map.set(&2,Maybe<&2,B.Descriptor>,entries,id,
        Some{B.Descriptor{T.number(id),0,T.number(dampening)}}))
    case _ _: (entries,[])
def applied(result:C.World & Result<&2,&2,C.Error,Unit>) -> C.World:
  (world,status) = result
  world
def configured(world:C.World,time:Nat) -> C.World:
  C.set_paused(applied(C.apply(applied(C.apply(world,C.TimeSet{time})),C.DaylightSet{False{}})),False{})
def sections(n:Nat,args:List<String>,world:C.World,origins:List<&2,C.Position>) ->
    C.World & List<&2,C.Position> & List<String>:
  match n args:
    case 0n rest: (world,List.reverse(&2,C.Position,origins),rest)
    case 1n+p x <> y <> z <> fill <> rest:
      +position : C.Position = C.Position{"minecraft:overworld",T.number(x),T.number(y),T.number(z)}
      sections(p,rest,applied(C.apply(world,C.SectionCreate{position,T.number(fill)})),position <> origins)
    case _ _: (world,origins,[])
def initial_writes(n:Nat,args:List<String>,world:C.World) -> C.World & List<String>:
  match n args:
    case 0n rest: (world,rest)
    case 1n+p x <> y <> z <> id <> rest:
      initial_writes(p,rest,applied(C.apply(world,C.BlockSet{
        C.Position{"minecraft:overworld",T.number(x),T.number(y),T.number(z)},T.number(id)})))
    case _ _: (world,[])
def positions(n:Nat,args:List<String>,out:List<&2,C.Position>) -> List<&2,C.Position> & List<String>:
  match n args:
    case 0n rest: (List.reverse(&2,C.Position,out),rest)
    case 1n+p x <> y <> z <> rest:
      positions(p,rest,C.Position{"minecraft:overworld",T.number(x),T.number(y),T.number(z)} <> out)
    case _ _: (out,[])

def load_progress(world:C.World,result:W.State & W.Progress,
    next:C.World -> W.State -> C.World & W.State) -> C.World & W.State:
  (state,status) = result
  match status:
    case W.Bootstrap{}: next(world,state)
    case other: (world,state)
def load_more(result:C.World & (W.State & Result<&2,&2,W.Error,Unit>),
    next:C.World -> W.State -> C.World & W.State) ->
    C.World & W.State:
  (world,(state,status)) = result
  match status:
    case Fail{error}: (world,state)
    case Done{u}: load_progress(world,W.progress(state),next)
def load(fuel:Nat,+context:Fixture,world:C.World,state:W.State) -> C.World & W.State:
  match fuel:
    case 0n: (world,state)
    case 1n+p:
      load_more(W.load_resume(~Fixture,~properties,~bounds,~section_policy,~enabled,~occludes,
        context,256n,world,state),world => state => load(p,context,world,state))
def settle_more(result:W.State & W.Progress,next:W.State -> W.State) -> W.State:
  (state,status) = result
  match status:
    case W.Propagating{pending}: next(state)
    case other: state
def settle(fuel:Nat,+context:Fixture,+budget:Nat,state:W.State) -> W.State:
  match fuel:
    case 0n: state
    case 1n+p: settle_more(W.advance(~Fixture,~occludes,context,budget,state),
      state => settle(p,context,budget,state))
def edit_loaded(loaded:C.World & W.State,
    next:C.World -> W.State -> C.World & W.State & List<String>) -> C.World & W.State & List<String>:
  (world,state) = loaded
  next(world,state)
def edit_refreshed(+context:Fixture,result:C.World & (W.State & Result<&2,&2,W.Error,Unit>),
    next:C.World -> W.State -> C.World & W.State & List<String>) -> C.World & W.State & List<String>:
  (world,(state,status)) = result
  match status:
    case Fail{error}: (world,state,[])
    case Done{u}: edit_loaded(load(512n,context,world,state),next)
def edits(n:Nat,+context:Fixture,args:List<String>,world:C.World,state:W.State) ->
    C.World & W.State & List<String>:
  match n args:
    case 0n rest: (world,state,rest)
    case 1n+p x <> y <> z <> id <> rest:
      +position : C.Position = C.Position{"minecraft:overworld",T.number(x),T.number(y),T.number(z)}
      edit_refreshed(context,W.refresh_block(~Fixture,~properties,context,position,
        applied(C.apply(world,C.BlockSet{position,T.number(id)})),state),
        world => state => edits(p,context,rest,world,state))
    case _ _: (world,state,[])
def sidecar_applied(result:W.State & Result<&2,&2,W.Error,Unit>) -> W.State:
  (state,status) = result
  state
def checks(n:Nat,+context:Fixture,args:List<String>,world:C.World,state:W.State) ->
    C.World & W.State & List<String>:
  match n args:
    case 0n rest: (world,state,rest)
    case 1n+p x <> y <> z <> rest:
      edit_refreshed(context,W.refresh_block(~Fixture,~properties,context,
        C.Position{"minecraft:overworld",T.number(x),T.number(y),T.number(z)},world,state),
        world => state => checks(p,context,rest,world,state))
    case _ _: (world,state,[])
def sources(n:Nat,+context:Fixture,args:List<String>,world:C.World,state:W.State) ->
    C.World & W.State & List<String>:
  match n args:
    case 0n rest: (world,state,rest)
    case 1n+p x <> y <> z <> rest:
      B.paired(C.World,W.State,C.World & W.State & List<String>,
        load(512n,context,world,sidecar_applied(W.propagate_sources(
          C.Position{"minecraft:overworld",T.number(x),T.number(y),T.number(z)},state))),
        world => state => sources(p,context,rest,world,state))
    case _ _: (world,state,[])
def toggles(n:Nat,args:List<String>,state:W.State) -> W.State & List<String>:
  match n args:
    case 0n rest: (state,rest)
    case 1n+p x <> y <> z <> enable <> rest:
      toggles(p,rest,sidecar_applied(W.set_enabled(
        C.Position{"minecraft:overworld",T.number(x),T.number(y),T.number(z)},flag(enable),state)))
    case _ _: (state,[])
def phase_checks(context:Fixture,result:C.World & W.State & List<String>) -> C.World & W.State & List<String>:
  (world,(state,args)) = result
  match args:
    case count <> rest: checks(U32.to_nat(T.number(count)),context,rest,world,state)
    case _: (world,state,[])
def phase_sources(+context:Fixture,world:C.World,result:W.State & List<String>) -> C.World & W.State & List<String>:
  (state,args) = result
  match args:
    case count <> rest: phase_checks(context,sources(U32.to_nat(T.number(count)),context,rest,world,state))
    case _: (world,state,[])
def phase_toggles(context:Fixture,result:C.World & W.State & List<String>) -> C.World & W.State & List<String>:
  (world,(state,args)) = result
  match args:
    case count <> rest: phase_sources(context,world,toggles(U32.to_nat(T.number(count)),rest,state))
    case _: (world,state,[])

def bool_text(value:Bool) -> String:
  match value:
    case False{}: "f"
    case True{}: "t"
def clock_text(clock:C.Clock) -> String:
  C.Clock{tick,time,paused,daylight,revision,pending} = clock
  Nat.show(tick) ++ "/" ++ Nat.show(time) ++ "/" ++ bool_text(paused) ++ "/" ++
    bool_text(daylight) ++ "/" ++ Nat.show(revision) ++ "/" ++ Nat.show(pending)
def run_same(same:Bool,equal:Unit -> String,different:Unit -> String) -> String:
  match same:
    case True{}: equal(Unit{})
    case False{}: different(Unit{})
def run_text(rest:List<&2,U32>,+id:U32,+count:U32) -> String:
  match rest:
    case Nil{}: U32.show(id) ++ ":" ++ U32.show(count)
    case +following <> +tail: run_same(U32.is_eq(id,following),
      unit => run_text(tail,id,U32.inc(count)),
      unit => U32.show(id) ++ ":" ++ U32.show(count) ++ "," ++ run_text(tail,following,1))
def cells_text(cells:Maybe<&2,List<&2,U32>>) -> String:
  match cells:
    case None{}: "?"
    case Some{Nil{}}: "empty"
    case Some{id <> rest}: run_text(rest,id,1)
def snapshot_text(origins:List<&2,C.Position>,world:C.World) -> C.World & String:
  match origins:
    case Nil{}: (world,"")
    case origin <> rest:
      B.paired(C.World,Maybe<&2,List<&2,U32>>,C.World & String,
        BW.snapshot(world,C.section_key(origin)),world => cells =>
          B.paired(C.World,String,C.World & String,snapshot_text(rest,world),world => tail =>
            (world,cells_text(cells) ++ ";" ++ tail)))
def owner_text(+origins:List<&2,C.Position>,world:C.World) -> C.World & String:
  B.paired(C.World,C.Clock,C.World & String,C.clock(world),world => clock =>
    B.paired(C.World,String,C.World & String,snapshot_text(origins,world),world => arrays =>
      (world,"owner " ++ clock_text(clock) ++ " " ++ arrays)))
def observation_text(cells:List<&2,W.Observation>) -> String:
  match cells:
    case Nil{}: ""
    case W.Observation{position,block,level} <> rest:
      T.show_level(block) ++ ":" ++ T.show_level(level) ++ " " ++ observation_text(rest)
def error_text(error:W.Error) -> String:
  match error:
    case W.InvalidBounds{dimension}: "bounds"
    case W.UnknownSection{position}: "unknown"
    case W.MissingDescriptor{id}: "descriptor"
    case W.LoadingInProgress{}: "loading"
    case W.LightPending{pending}: "pending"
    case W.StaleRevision{}: "stale"
    case other: "other"
def outcome(result:Result<&2,&2,W.Error,Unit>) -> String:
  match result:
    case Done{u}: "accepted"
    case Fail{error}: error_text(error)
def frame_text(result:Result<&2,&2,W.Error,W.FrameSamples>) -> String:
  match result:
    case Fail{error}: "refused:" ++ error_text(error)
    case Done{W.FrameSamples{clock,cells}}:
      "stable " ++ clock_text(clock) ++ " " ++ observation_text(cells)
def render_phase(+context:Fixture,+budget:Nat,+origins:List<&2,C.Position>,
    +samples:List<&2,C.Position>,world:C.World,state:W.State,next:C.World -> W.State -> IO(Unit)) -> IO(Unit):
  B.paired(C.World,W.State & Result<&2,&2,W.Error,W.FrameSamples>,IO(Unit),
    W.sample_batch(samples,world,settle(4096n,context,budget,state)),world => result =>
      B.paired(W.State,Result<&2,&2,W.Error,W.FrameSamples>,IO(Unit),result,state => frame =>
        B.paired(C.World,String,IO(Unit),owner_text(origins,world),world => owner => (
          do IO<Unit>:
            IO.print(frame_text(frame))
            IO.print(owner)
            next(world,state)
        ))))
def phases(n:Nat,+context:Fixture,+budget:Nat,+origins:List<&2,C.Position>,
    +samples:List<&2,C.Position>,args:List<String>,world:C.World,state:W.State) -> IO(Unit):
  match n args:
    case 0n _: IO.pure(Unit,Unit{})
    case 1n+p count <> rest:
      B.paired(C.World,W.State & List<String>,IO(Unit),phase_toggles(context,
        edits(U32.to_nat(T.number(count)),context,rest,world,state)),world => result =>
        B.paired(W.State,List<String>,IO(Unit),result,state => tail =>
          render_phase(context,budget,origins,samples,world,state,
            world => state => phases(p,context,budget,origins,samples,tail,world,state))))
    case _ _: IO.die(Unit,1,"sky_light_receiver: incomplete phases")
def initial_loaded(+context:Fixture,+budget:Nat,+origins:List<&2,C.Position>,
    +samples:List<&2,C.Position>,loaded:C.World & W.State,args:List<String>) -> IO(Unit):
  (world,state) = loaded
  match args:
    case count <> rest: render_phase(context,budget,origins,samples,world,state,
      world => state => phases(U32.to_nat(T.number(count)),context,budget,origins,samples,rest,world,state))
    case _: IO.die(Unit,1,"sky_light_receiver: missing phase count")
def samples_loaded(+context:Fixture,+budget:Nat,+origins:List<&2,C.Position>,
    world:C.World,result:List<&2,C.Position> & List<String>) -> IO(Unit):
  (samples,args) = result
  B.paired(C.World,String,IO(Unit),owner_text(origins,world),world => owner => (
    do IO<Unit>:
      IO.print(owner)
      B.paired(C.World,W.State,IO(Unit),W.begin(world),world => state =>
        initial_loaded(context,budget,origins,samples,load(512n,context,world,state),args))
  ))
def geometry_written(+context:Fixture,+budget:Nat,+origins:List<&2,C.Position>,
    result:C.World & List<String>) -> IO(Unit):
  (world,args) = result
  match args:
    case count <> rest:
      samples_loaded(context,budget,origins,world,positions(U32.to_nat(T.number(count)),rest,[]))
    case _: IO.die(Unit,1,"sky_light_receiver: missing samples")
def sections_loaded(+context:Fixture,+budget:Nat,result:C.World & List<&2,C.Position> & List<String>) -> IO(Unit):
  (world,(origins,args)) = result
  match args:
    case count <> rest: geometry_written(context,budget,origins,initial_writes(U32.to_nat(T.number(count)),rest,world))
    case _: IO.die(Unit,1,"sky_light_receiver: missing writes")
def edges_loaded(entries:Map<&2,Maybe<&2,B.Descriptor>>,bounds:W.Bounds,enabled:Bool,budget:Nat,
    result:Map<&2,Bool> & List<String>) -> IO(Unit):
  (edges,args) = result
  match args:
    case count <> rest:
      sections_loaded(Fixture{entries,edges,bounds,enabled,False{}},budget,
        sections(U32.to_nat(T.number(count)),rest,configured(C.new(35723),137n),[]))
    case _: IO.die(Unit,1,"sky_light_receiver: missing sections")
def catalog_loaded(bounds:W.Bounds,enabled:Bool,budget:Nat,
    result:Map<&2,Maybe<&2,B.Descriptor>> & List<String>) -> IO(Unit):
  (entries,args) = result
  match args:
    case count <> rest: edges_loaded(entries,bounds,enabled,budget,T.edges(U32.to_nat(T.number(count)),rest,MTip{}))
    case _: IO.die(Unit,1,"sky_light_receiver: missing edges")

def guard_entries(height:U32,known:Bool,missing:Bool,entries:Map<&2,Maybe<&2,B.Descriptor>>) -> Fixture:
  match missing:
    case True{}: Fixture{MTip{},MTip{},W.Bounds{0,height,0,True{}},True{},known}
    case False{}: Fixture{entries,MTip{},W.Bounds{0,height,0,True{}},True{},known}
def guard_context(height:U32,known:Bool,missing:Bool) -> Fixture:
  guard_entries(height,known,missing,Map.set(&2,Maybe<&2,B.Descriptor>,MTip{},"0",Some{B.Descriptor{0,0,0}}))
def guard_finish(+origins:List<&2,C.Position>,world:C.World,state:W.State) -> IO(Unit):
  +context = guard_context(32,True{},False{})
  B.paired(C.World,W.State,IO(Unit),load(128n,context,world,state),world => state =>
    B.paired(C.World,W.State & Result<&2,&2,W.Error,W.FrameSamples>,IO(Unit),
      W.sample_batch([C.Position{"minecraft:overworld",0,16,0},C.Position{"minecraft:overworld",0,0,0},
        C.Position{"minecraft:overworld",64,0,0}],world,settle(64n,context,64n,state)),world => result =>
        B.paired(W.State,Result<&2,&2,W.Error,W.FrameSamples>,IO(Unit),result,state => frame =>
          B.paired(C.World,String,IO(Unit),owner_text(origins,world),world => owner => (
            do IO<Unit>:
              IO.print("guard " ++ frame_text(frame))
              IO.print(owner)
          )))))
def guard_steps(+origins:List<&2,C.Position>,world:C.World,state:W.State) -> IO(Unit):
  B.paired(C.World,W.State & Result<&2,&2,W.Error,Unit>,IO(Unit),
    W.load_resume(~Fixture,~properties,~bounds,~section_policy,~enabled,~occludes,guard_context(0,False{},False{}),1n,world,state),world => result =>
    B.paired(W.State,Result<&2,&2,W.Error,Unit>,IO(Unit),result,state => invalid =>
      B.paired(C.World,W.State & Result<&2,&2,W.Error,Unit>,IO(Unit),
        W.load_resume(~Fixture,~properties,~bounds,~section_policy,~enabled,~occludes,guard_context(32,False{},False{}),3n,world,state),world => result =>
        B.paired(W.State,Result<&2,&2,W.Error,Unit>,IO(Unit),result,state => unknown =>
          B.paired(C.World,W.State & Result<&2,&2,W.Error,Unit>,IO(Unit),
            W.load_resume(~Fixture,~properties,~bounds,~section_policy,~enabled,~occludes,guard_context(32,True{},False{}),1n,world,state),world => result =>
            B.paired(W.State,Result<&2,&2,W.Error,Unit>,IO(Unit),result,state => permitted =>
              B.paired(C.World,W.State & Result<&2,&2,W.Error,Unit>,IO(Unit),
                W.load_resume(~Fixture,~properties,~bounds,~section_policy,~enabled,~occludes,guard_context(32,True{},True{}),1n,world,state),world => result =>
                B.paired(W.State,Result<&2,&2,W.Error,Unit>,IO(Unit),result,state => absent_descriptor =>
                  B.paired(C.World,W.State & Result<&2,&2,W.Error,Unit>,IO(Unit),
                    W.load_resume(~Fixture,~properties,~bounds,~section_policy,~enabled,~occludes,guard_context(32,True{},False{}),1n,world,state),world => result =>
                    B.paired(W.State,Result<&2,&2,W.Error,Unit>,IO(Unit),result,state => retry => (
                      do IO<Unit>:
                        IO.print("guards " ++ outcome(invalid) ++ " " ++ outcome(unknown) ++ " " ++ outcome(permitted) ++ " " ++
                          outcome(absent_descriptor) ++ " " ++ outcome(retry))
                        guard_finish(origins,world,state)
                    )))))))))))
def guards() -> IO(Unit):
  +origin : C.Position = C.Position{"minecraft:overworld",0,16,0}
  world = applied(C.admit(configured(applied(C.apply(C.new(35723),C.SectionCreate{origin,0})),37n),
    C.Developer{},Q.Stamp{1n,1,1n},C.BlockSet{origin,1}))
  B.paired(C.World,String,IO(Unit),owner_text([origin],world),world => owner => (
    do IO<Unit>:
      IO.print(owner)
      B.paired(C.World,W.State,IO(Unit),W.begin(world),world => state =>
        B.paired(C.World,W.State & Result<&2,&2,W.Error,W.FrameSamples>,IO(Unit),W.sample_batch([origin],world,state),world => result =>
          B.paired(W.State,Result<&2,&2,W.Error,W.FrameSamples>,IO(Unit),result,state => provisional => (
            do IO<Unit>:
              IO.print("guard " ++ frame_text(provisional))
              guard_steps([origin],world,state)
          ))))
  ))
def halo_loaded(+context:Fixture,+origins:List<&2,C.Position>,result:C.World & W.State) -> IO(Unit):
  (world,state) = result
  render_phase(context,64n,origins,[C.Position{"minecraft:overworld",0,4294967280,0},
    C.Position{"minecraft:overworld",0,4294967295,0},C.Position{"minecraft:overworld",0,0,0},
    C.Position{"minecraft:overworld",0,15,0},C.Position{"minecraft:overworld",0,16,0},
    C.Position{"minecraft:overworld",0,4294967279,0}],world,state,world => state => IO.pure(Unit,Unit{}))
def halo() -> IO(Unit):
  +below : C.Position = C.Position{"minecraft:overworld",0,4294967280,0}
  +inside : C.Position = C.Position{"minecraft:overworld",0,0,0}
  +origins : List<&2,C.Position> = [below,inside]
  +context = guard_context(16,False{},False{})
  world = configured(applied(C.apply(applied(C.apply(C.new(35723),C.SectionCreate{below,0})),C.SectionCreate{inside,0})),71n)
  B.paired(C.World,String,IO(Unit),owner_text(origins,world),world => owner => (
    do IO<Unit>:
      IO.print(owner)
      B.paired(C.World,W.State,IO(Unit),W.begin(world),world => state =>
        halo_loaded(context,origins,load(256n,context,world,state)))
  ))

def run(args:List<String>) -> IO(Unit):
  match args:
    case "guards" <> _: guards()
    case "halo" <> _: halo()
    case budget <> minimum <> height <> air <> enable <> count <> rest:
      catalog_loaded(W.Bounds{T.number(minimum),T.number(height),T.number(air),True{}},flag(enable),
        U32.to_nat(T.number(budget)),catalog(U32.to_nat(T.number(count)),rest,MTip{}))
    case _: IO.die(Unit,1,"sky_light_receiver: missing arguments")
def args(args:List<String>) -> IO(Unit):
  match args:
    case program <> rest: run(rest)
    case _: IO.die(Unit,1,"sky_light_receiver: missing argv")
def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
