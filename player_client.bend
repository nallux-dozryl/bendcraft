import Base
import ./src/player_scene.bend as Scene
import ./src/player_session.bend as Session
import ./src/player_storage.bend as Storage
import ./src/player_record.bend as Record
import ./src/extended_persistence.bend as Persistence
import ./src/locomotion.bend as Motion
import ./src/client_presenter.bend as Presenter
import ./src/client_render.bend as Render
import ./src/client_host.bend as Host
import ./src/archive.bend as Archive
import ./src/server.bend as Server

type Options is Data:
  Options{fixture:Bool,run:Bool,frames:Maybe<&2,Nat>,jar:String,sine:String}

def defaults() -> Options:
  Options{False{},False{},None{},"/Users/chuah/Library/Application Support/minecraft/versions/26.3/26.3.jar","generated/reference_mth_sin.f32"}

def frame_count(options:Options,result:Maybe<&2,U32>) -> Result<&2,&2,String,Options>:
  match options result:
    case _ None{}: Fail{"--frames requires an unsigned integer"}
    case Options{fixture,run,frames,jar,sine} Some{count}:
      Done{Options{fixture,run,Some{U32.to_nat(count)},jar,sine}}

def parse(args:List<String>,options:Options) -> Result<&2,&2,String,Options>:
  match args options:
    case Nil{} _: Done{options}
    case "--verification-fixture" <> rest Options{fixture,run,frames,jar,sine}:
      parse(rest,Options{True{},run,frames,jar,sine})
    case "--unpaused" <> rest Options{fixture,run,frames,jar,sine}:
      parse(rest,Options{fixture,True{},frames,jar,sine})
    case "--frames" <> value <> rest _:
      do Result<&2,&2,String,Options>:
        next : Options <- frame_count(options,U32.read(value))
        parse(rest,next)
    case "--jar" <> value <> rest Options{fixture,run,frames,jar,sine}:
      parse(rest,Options{fixture,run,frames,value,sine})
    case "--sine" <> value <> rest Options{fixture,run,frames,jar,sine}:
      parse(rest,Options{fixture,run,frames,jar,value})
    case value <> rest _: Fail{"unknown/incomplete option " ++ value}

def checked_options(result:Result<&2,&2,String,Options>) -> IO(Options):
  match result:
    case Fail{message}: IO.die(Options,1,message)
    case Done{Options{False{},run,frames,jar,sine}}:
      IO.die(Options,1,"A playable world loader is not implemented. This entry requires --verification-fixture.")
    case Done{options}: IO.pure(Options,options)

def parse_cli(args:List<String>) -> IO(Options):
  match args:
    case name <> rest: checked_options(parse(rest,defaults()))
    case Nil{}: IO.die(Options,1,"missing argv")

def checked_tables(result:Result<&2,&1,Motion.Error,Motion.Tables>) -> IO(Motion.Tables):
  match result:
    case Fail{cause}: IO.die(Motion.Tables,1,"could not load the verified sine table")
    case Done{tables}: IO.pure(Motion.Tables,tables)

def checked_assets(result:Result<&2,&1,Archive.Error,Render.Assets>) -> IO(Render.Assets):
  match result:
    case Fail{cause}: IO.die(Render.Assets,1,Archive.error_text(cause))
    case Done{assets}: IO.pure(Render.Assets,assets)

def start(options:Options,assets:Render.Assets,ready:Session.Ready) -> IO(Unit):
  Options{fixture,run,frames,jar,sine} = options
  Session.Ready{state,first_peer} = ready
  do IO<Unit>:
    handle : Server.Handle<Session.State> <- Server.start_effectful_from_peer(~Session.State,~Server.EffectfulDriver{Scene.realtime_step,Scene.dispatch},state,first_peer)
    mode : Result<&1,&1,U32 & String,String> <- IO.get_env("BEND_MINECRAFT_LAUNCH_MODE")
    Presenter.open(~Session.State,~Render.Snapshot,~Render.Assets,~Scene.presenter_driver(),~Scene.renderer(),assets,handle,Host.interactive(mode),frames,128,128,"Minecraft 26.3 — continuous player integration scene")

def load_options(+options:Options) -> IO(Unit):
  Options{fixture,+run,frames,+jar,sine} = options
  do IO<Unit>:
    loaded_tables : Result<&2,&1,Motion.Error,Motion.Tables> <- Motion.Tables.load(sine)
    tables : Motion.Tables <- checked_tables(loaded_tables)
    loaded_assets : Result<&2,&1,Archive.Error,Render.Assets> <- Render.load_assets(jar)
    assets : Render.Assets <- checked_assets(loaded_assets)
    stored : Persistence.Ready<Record.Record> <- Persistence.load_with(~Record.Record,~Storage.codec(),~Session.operations(),Storage.limits())
    ready : Session.Ready <- Session.new(stored,tables)
    initialized : Session.Ready <- Scene.initialize(ready)
    start(options,assets,Scene.run_requested(initialized,run))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    options : Options <- parse_cli(args)
    load_options(options)
