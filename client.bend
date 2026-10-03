import Base
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

def snapshot_ready(result:Result<&2,&2,String,R.Snapshot>) -> IO(R.Snapshot):
  match result:
    case Fail{message}: IO.die(R.Snapshot,1,"snapshot: " ++ message)
    case Done{snapshot}: IO.pure(R.Snapshot,snapshot)

def result_unit(result:Result<&2,&2,String,Unit>) -> IO(Unit):
  match result:
    case Fail{message}: IO.print("control rejected: " ++ message)
    case Done{unit}: IO.pure(Unit,Unit{})

def result_motion(result:Result<&2,&2,String,M.Transition>) -> IO(Unit):
  match result:
    case Fail{message}: IO.print("motion rejected: " ++ message)
    case Done{transition}: IO.pure(Unit,Unit{})

def move_delta(+yaw:F32,+forward:F32,+right:F32,vertical:F32) -> M.Vec3:
  M.Vec3{F.from_f32(F32.mul(F32.add(F32.mul(F32.cos(yaw),right),F32.neg(F32.mul(F32.sin(yaw),forward))),0.25)),F.from_f32(F32.mul(vertical,0.25)),F.from_f32(F32.mul(F32.add(F32.mul(F32.sin(yaw),right),F32.mul(F32.cos(yaw),forward)),0.25))}

def move_control(handle:S.Handle<W.State>,yaw:F32,forward:F32,right:F32,vertical:F32) -> IO(Unit):
  delta = move_delta(yaw,forward,right,vertical)
  do IO<Unit>:
    result : Result<&2,&2,String,M.Transition> <- S.local_call(W.State,Result<&2,&2,String,M.Transition>,handle,state => W.move(state,delta,0.6))
    result_motion(result)

def key_control(code:U32,handle:S.Handle<W.State>,yaw:F32) -> IO(Bool):
  match code:
    case 27: IO.pure(Bool,False{})
    case 119:
      do IO<Bool>:
        move_control(handle,yaw,1.0,0.0,0.0)
        return True{}
    case 115:
      do IO<Bool>:
        move_control(handle,yaw,F32.neg(1.0),0.0,0.0)
        return True{}
    case 97:
      do IO<Bool>:
        move_control(handle,yaw,0.0,F32.neg(1.0),0.0)
        return True{}
    case 100:
      do IO<Bool>:
        move_control(handle,yaw,0.0,1.0,0.0)
        return True{}
    case 113:
      do IO<Bool>:
        move_control(handle,yaw,0.0,0.0,F32.neg(1.0))
        return True{}
    case 101:
      do IO<Bool>:
        move_control(handle,yaw,0.0,0.0,1.0)
        return True{}
    case _: IO.pure(Bool,True{})

def events_go(events:List<Event>,+handle:S.Handle<W.State>,+yaw:F32,+pitch:F32,keep:Bool) -> IO(Bool):
  match events:
    case Nil{}: IO.pure(Bool,keep)
    case Close{} <> tail: events_go(tail,handle,yaw,pitch,False{})
    case Key{code,True{}} <> tail:
      do IO<Bool>:
        next : Bool <- key_control(code,handle,yaw)
        events_go(tail,handle,yaw,pitch,next && keep)
    case Look{dx,dy} <> tail:
      +next_yaw = F32.add(yaw,F32.mul(dx,0.0025))
      +next_pitch = F32.clamp(F32.add(pitch,F32.mul(dy,0.0025)),F32.neg(1.5707963),1.5707963)
      do IO<Bool>:
        result : Result<&2,&2,String,Unit> <- S.local_call(W.State,Result<&2,&2,String,Unit>,handle,state => W.look(state,next_yaw,next_pitch))
        result_unit(result)
        events_go(tail,handle,next_yaw,next_pitch,keep)
    case event <> tail: events_go(tail,handle,yaw,pitch,keep)

def events_camera(events:List<Event>,handle:S.Handle<W.State>,camera:R.Camera) -> IO(Bool):
  R.Camera{x,y,z,yaw,pitch} = camera
  events_go(events,handle,yaw,pitch,True{})

def frame_dump(dump:Maybe<&2,String>,image:Image) -> IO(Unit):
  match dump:
    case None{}: IO.pure(Unit,Unit{})
    case Some{path}: R.write_ppm(path,image,128,128)

def remaining(frames:Maybe<&2,Nat>) -> Maybe<&2,Nat>:
  match frames:
    case None{}: None{}
    case Some{0n}: Some{0n}
    case Some{1n+p}: Some{p}

def can_continue(frames:Maybe<&2,Nat>) -> Bool:
  match frames:
    case Some{0n}: False{}
    case _: True{}

def closing(window:Window,handle:S.Handle<W.State>) -> IO(Unit):
  do IO<Unit>:
    Window.close(window)
    S.stop(W.State,handle)
    IO.die(Unit,0,"client closed")

def camera_of(snapshot:R.Snapshot) -> R.Camera:
  R.Snapshot{tick,revision,blocks,camera} = snapshot
  camera

def frame_summary(snapshot:R.Snapshot) -> String:
  R.Snapshot{tick,revision,blocks,camera} = snapshot
  "{\"event\":\"client.snapshot\",\"tick\":" ++ Nat.show(tick) ++ ",\"revision\":" ++ Nat.show(revision) ++ ",\"blocks\":" ++ Nat.show(List.length(&2,R.Block,blocks)) ++ "}"

# Only OS-driven client lifetime is unsafe; world, snapshots, asset codecs
# and rendering remain checked Bend. Events submit serialized actor queries.
@unsafe
def loop(window:Window,assets:R.Assets,+handle:S.Handle<W.State>,frames:Maybe<&2,Nat>,+dump:Maybe<&2,String>) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,String,R.Snapshot> <- S.local_call(W.State,Result<&2,&2,String,R.Snapshot>,handle,state => W.snapshot(state,128,128))
    +snapshot : R.Snapshot <- snapshot_ready(result)
    IO.print(frame_summary(snapshot))
    camera : R.Camera = camera_of(snapshot)
    pair : R.Assets & Image = R.render(snapshot,assets,128,128)
    P.paired(R.Assets,Image,IO(Unit),pair,assets => +image => (
      do IO<Unit>:
        frame_dump(dump,image)
        shown : Window & Image & List<Event> <- Window.frame(window,image)
        P.paired(Window,Image & List<Event>,IO(Unit),shown,window => pair => (
          P.paired(Image,List<Event>,IO(Unit),pair,image => events => (
            do IO<Unit>:
              keep : Bool <- events_camera(events,handle,camera)
              +next : Maybe<&2,Nat> = remaining(frames)
              loop_next(window,assets,handle,next,dump,keep && can_continue(next))
          ))
        ))
    ))

@unsafe
def loop_next(window:Window,assets:R.Assets,handle:S.Handle<W.State>,frames:Maybe<&2,Nat>,dump:Maybe<&2,String>,keep:Bool) -> IO(Unit):
  match keep:
    case False{}: closing(window,handle)
    case True{}:
      do IO<Unit>:
        IO.sleep(8)
        loop(window,assets,handle,frames,dump)

def interactive(result:Result<&1,&1,U32 & String,String>) -> Bool:
  match result:
    case Fail{error}: True{}
    case Done{text}: Bool.not(String.eq(text,"hidden"))

def window_start(options:Options,assets:R.Assets,handle:S.Handle<W.State>,human:Bool) -> IO(Unit):
  Options{fixture,frames,dump,jar} = options
  do IO<Unit>:
    window : Window <- IO.try(Window,Window.open("Minecraft 26.3 — verification scene",512,512))
    window : Window <- Window.grab(window,human)
    loop(window,assets,handle,frames,dump)

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
