import Base
import ./src/client_host.bend as H
import ./src/client_render.bend as R
import ./src/client_world.bend as W
import ./src/server.bend as S
import ./src/game.bend as G
import ./src/png.bend as P
import ./src/archive.bend as A
import ./src/json.bend as J
import ./src/live.bend as L
import ./src/movement.bend as M
import ./src/f64.bend as F

type Options is Data:
  Options{fixture:Bool,frames:Maybe<&2,Nat>,dump:Maybe<&2,String>,jar:String}

def default_options() -> Options:
  Options{False{},None{},None{},"/Users/chuah/Library/Application Support/minecraft/versions/26.3/26.3.jar"}

def option_fixture(options:Options) -> Options:
  Options{fixture,frames,dump,jar} = options
  Options{True{},frames,dump,jar}

def option_frames(options:Options,value:Maybe<&2,U32>) -> Result<&2,&2,String,Options>:
  match options value:
    case Options{fixture,frames,dump,jar} None{}: Fail{"--frames requires a positive integer"}
    case Options{fixture,frames,dump,jar} Some{0}: Fail{"--frames requires a positive integer"}
    case Options{fixture,frames,dump,jar} Some{n}: Done{Options{fixture,Some{U32.to_nat(n)},dump,jar}}

def parse_options(args:List<String>,options:Options) -> Result<&2,&2,String,Options>:
  match args:
    case Nil{}: Done{options}
    case "--verification-fixture" <> tail: parse_options(tail,option_fixture(options))
    case "--frames" <> text <> tail:
      do Result<&2,&2,String,Options>:
        next : Options <- option_frames(options,U32.read(text))
        parse_options(tail,next)
    case "--dump" <> path <> tail:
      Options{fixture,frames,dump,jar} = options
      parse_options(tail,Options{fixture,frames,Some{path},jar})
    case "--jar" <> path <> tail:
      Options{fixture,frames,dump,jar} = options
      parse_options(tail,Options{fixture,frames,dump,path})
    case unknown <> tail: Fail{"unknown/incomplete option " ++ unknown}

def parsed(result:Result<&2,&2,String,Options>) -> IO(Options):
  match result:
    case Fail{message}: IO.die(Options,1,message)
    case Done{options}: IO.pure(Options,options)

def args_options(args:List<String>) -> IO(Options):
  match args:
    case name <> tail: parsed(parse_options(tail,default_options()))
    case Nil{}: IO.die(Options,1,"missing argv")

def fixture_required(options:Options,enabled:Bool) -> IO(Options):
  match enabled:
    case True{}: IO.pure(Options,options)
    case False{}: IO.die(Options,1,"No playable world loader is implemented. Use --verification-fixture for the explicit finite integration scene.")

def require_fixture(+options:Options) -> IO(Options):
  Options{fixture,frames,dump,jar} = options
  fixture_required(options,fixture)

def ready_world(pair:W.State & Result<&2,&2,String,Unit>) -> IO(W.State):
  (world,result) = pair
  match result:
    case Fail{message}: IO.die(W.State,1,message)
    case Done{unit}: IO.pure(W.State,world)

def ready_assets(result:Result<&2,&1,A.Error,R.Assets>) -> IO(R.Assets):
  match result:
    case Fail{error}: IO.die(R.Assets,1,A.error_text(error))
    case Done{assets}: IO.pure(R.Assets,assets)

def camera_of(snapshot:R.Snapshot) -> R.Camera:
  H.camera_of(snapshot)

def snapshot_ready(result:Result<&2,&2,String,R.Snapshot>) -> IO(R.Snapshot):
  H.snapshot_ready(result)

def host_move(state:W.State,delta:M.Vec3,maximum:F32) -> W.State & Result<&2,&2,String,M.Transition>:
  W.move(state,delta,maximum)

def host_look(state:W.State,yaw:F32,pitch:F32) -> W.State & Result<&2,&2,String,Unit>:
  W.look(state,yaw,pitch)

def events_camera(events:List<Event>,handle:S.Handle<W.State>,camera:R.Camera) -> IO(Bool):
  H.events_camera(~W.State,~H.Driver{W.snapshot,host_move,host_look},events,handle,camera)

def interactive(result:Result<&1,&1,U32 & String,String>) -> Bool:
  H.interactive(result)

def window_start(options:Options,assets:R.Assets,handle:S.Handle<W.State>,human:Bool) -> IO(Unit):
  Options{fixture,frames,dump,jar} = options
  H.window_start(~W.State,~H.Driver{W.snapshot,host_move,host_look},assets,handle,human,frames,dump,"Minecraft 26.3 — verification scene")

def jar_of(options:Options) -> String:
  Options{fixture,frames,dump,jar} = options
  jar

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    options : Options <- args_options(args)
    +options : Options <- require_fixture(options)
    loaded : Result<&2,&1,A.Error,R.Assets> <- R.load_assets(jar_of(options))
    assets : R.Assets <- ready_assets(loaded)
    engine : G.Engine <- G.load()
    world : W.State <- ready_world(W.fixture(engine))
    handle : S.Handle<W.State> <- S.start_handle(~W.State,~S.Driver{W.step,W.dispatch},world)
    mode : Result<&1,&1,U32 & String,String> <- IO.get_env("BEND_MINECRAFT_LAUNCH_MODE")
    window_start(options,assets,handle,interactive(mode))
