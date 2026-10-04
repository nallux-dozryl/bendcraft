import Base
import ./resource_player_boxed_scene.bend as Scene
import ./player_session.bend as Session
import ./server.bend as Server
import ./client_presenter.bend as Common
import ./window_input.bend as Input
import ./client_render.bend as Pixels
import ./png.bend as PNG
import ./compression.bend as Checksum
import ./world_visibility.bend as Visibility
import ./client_world.bend as World
import ./movement.bend as Movement
import ./f64.bend as Double

# This concrete consumer retains the original actor, resource renderer and OS
# packet implementation. Renderer callbacks do not enter the generic loop.
type Config is Data:
  Config{human:Bool,frames:Maybe<&2,Nat>,width:U32,height:U32,
    trace:Maybe<&2,String>,serial:Nat}

def trace_mode(result:Result<&1,&1,U32 & String,String>) -> Maybe<&2,String>:
  match result:
    case Fail{cause}: None{}
    case Done{""}: None{}
    case Done{path}: Some{path}

def trace_status(status:Result<&1,&1,U32 & String,Unit>) -> Result<&2,&2,String,Unit>:
  match status:
    case Fail{(code,message)}: Fail{"frame readback: " ++ message}
    case Done{unit}: Done{unit}

def trace_closed(result:File & Result<&1,&1,U32 & String,Unit>) -> IO(Result<&2,&2,String,Unit>):
  (file,status) = result
  do IO<Result<&2,&2,String,Unit>>:
    File.close(file)
    return trace_status(status)

def trace_header(file:File,+bytes:List<&2,U32>,status:Result<&1,&1,U32 & String,Unit>) -> IO(Result<&2,&2,String,Unit>):
  match status:
    case Fail{cause}: trace_closed((file,Fail{cause}))
    case Done{unit}:
      do IO<Result<&2,&2,String,Unit>>:
        written : File & Result<&1,&1,U32 & String,Unit> <- File.write_bytes(file,bytes)
        trace_closed(written)

def trace_opened(+image:Image,+width:U32,+height:U32,result:Result<&1,&1,U32 & String,File>) -> IO(Result<&2,&2,String,Unit>):
  match result:
    case Fail{(code,message)}: IO.pure(Result<&2,&2,String,Unit>,Fail{"frame readback: " ++ message})
    case Done{file}:
      do IO<Result<&2,&2,String,Unit>>:
        header : File & Result<&1,&1,U32 & String,Unit> <- File.write(file,"P6\n" ++ U32.show(width) ++ " " ++ U32.show(height) ++ "\n255\n")
        PNG.paired(File,Result<&1,&1,U32 & String,Unit>,IO(Result<&2,&2,String,Unit>),header,
          file => status => trace_header(file,Pixels.ppm_bytes_go(Pixels.pixels_of(image,width,height),[]),status))

def trace_write(path:String,+image:Image,+width:U32,+height:U32) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    opened : Result<&1,&1,U32 & String,File> <- File.open(path,"w")
    trace_opened(image,width,height,opened)

def trace(image:Image,config:Config) -> IO(Result<&2,&2,String,Unit>):
  Config{human,frames,+width,+height,mode,serial} = config
  match mode:
    case None{}: IO.pure(Result<&2,&2,String,Unit>,Done{Unit{}})
    case Some{directory}: trace_write(directory ++ "/" ++ Nat.show(serial) ++ ".ppm",image,width,height)

def closing(window:Window,assets:Scene.Assets,+handle:Server.Handle<Session.State>,code:U32,message:String) -> IO(Unit):
  do IO<Unit>:
    Common.local_release(~Session.State,~Scene.Frame,~Scene.presenter_driver(),handle)
    Window.close(window)
    Scene.close_assets(assets)
    Server.stop(Session.State,handle)
    IO.die(Unit,code,message)

def advance(config:Config) -> Config:
  Config{human,frames,width,height,trace,serial} = config
  Config{human,Common.remaining(frames),width,height,trace,1n+serial}

def scheduled(window:Window,assets:Scene.Assets,handle:Server.Handle<Session.State>,config:Config,captured:Bool,keep:Bool,resume:Window -> Scene.Assets -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  match keep:
    case False{}: closing(window,assets,handle,0,"client closed")
    case True{}:
      do IO<Unit>:
        IO.sleep(8)
        resume(window,assets,config,captured)

def input_config(window:Window,assets:Scene.Assets,handle:Server.Handle<Session.State>,+config:Config,captured:Bool,keep:Bool,resume:Window -> Scene.Assets -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  Config{human,frames,width,height,trace,serial} = config
  scheduled(window,assets,handle,config,captured,keep && Common.continuing(frames),resume)

def input_ready(assets:Scene.Assets,handle:Server.Handle<Session.State>,config:Config,result:Window & Bool & Bool,resume:Window -> Scene.Assets -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (window,captured,keep) = result
  input_config(window,assets,handle,advance(config),captured,keep,resume)

def image_description(+image:Image,config:Config) -> IO(Unit):
  Config{human,frames,+width,+height,mode,serial} = config
  match mode:
    case None{}: IO.pure(Unit,Unit{})
    case Some{directory}: IO.print("resource.image|" ++ Nat.show(serial) ++ "|" ++ U32.show(width) ++ "|" ++ U32.show(height) ++ "|" ++ U32.show(Checksum.crc32(PNG.rgba_bytes(Pixels.pixels_of(image,width,height)))))

def input_presented(window:Window,assets:Scene.Assets,+handle:Server.Handle<Session.State>,+config:Config,captured:Bool,allowed:Bool,image:Image,pending:List<Event>,resume:Window -> Scene.Assets -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  Config{+human,frames,width,height,trace,serial} = config
  do IO<Unit>:
    image_description(image,config)
    input : Window & Bool & Bool <- Common.frame_input(~Session.State,~Scene.Frame,~Scene.presenter_driver(),window,handle,pending,human && allowed,captured)
    input_ready(assets,handle,config,input,resume)

def traced(window:Window,assets:Scene.Assets,+handle:Server.Handle<Session.State>,+config:Config,captured:Bool,allowed:Bool,+image:Image,pending:List<Event>,status:Result<&2,&2,String,Unit>,resume:Window -> Scene.Assets -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  match status:
    case Fail{error}: closing(window,assets,handle,1,error)
    case Done{unit}: input_presented(window,assets,handle,config,captured,allowed,image,pending,resume)

def presented(assets:Scene.Assets,+handle:Server.Handle<Session.State>,+config:Config,captured:Bool,allowed:Bool,result:Window & Image & List<Event>,resume:Window -> Scene.Assets -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (window,+image,pending) = result
  do IO<Unit>:
    written : Result<&2,&2,String,Unit> <- trace(image,config)
    traced(window,assets,handle,config,captured,allowed,image,pending,written,resume)

def image_ready(window:Window,assets:Scene.Assets,+handle:Server.Handle<Session.State>,+config:Config,captured:Bool,allowed:Bool,status:Result<&2,&2,String,Image>,resume:Window -> Scene.Assets -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  match status:
    case Fail{error}: closing(window,assets,handle,1,"render: " ++ error)
    case Done{image}:
      do IO<Unit>:
        shown : Window & Image & List<Event> <- Window.frame(window,image)
        presented(assets,handle,config,captured,allowed,shown,resume)

def drawn(window:Window,handle:Server.Handle<Session.State>,config:Config,captured:Bool,allowed:Bool,value:Scene.Assets & Result<&2,&2,String,Image>,resume:Window -> Scene.Assets -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (assets,status) = value
  image_ready(window,assets,handle,config,captured,allowed,status,resume)

# Observation-only DTOs never supply resources, geometry or expected pixels.
def words(values:List<&2,U32>) -> String:
  match values:
    case Nil{}: ""
    case [value]: U32.show(value)
    case value <> tail: U32.show(value) ++ "," ++ words(tail)

def block_rows(values:List<&2,Pixels.Block>) -> String:
  match values:
    case Nil{}: ""
    case Pixels.Block{x,y,z,state,material} <> tail:
      words([F32.bits(x),F32.bits(y),F32.bits(z),state,material]) ++ ";" ++ block_rows(tail)

def raw_rows(values:List<&2,World.RawBlock>) -> String:
  match values:
    case Nil{}: ""
    case World.RawBlock{World.Cell{x,y,z,boundary},state,material} <> tail:
      words([x,y,z,boundary,state,material]) ++ ";" ++ raw_rows(tail)

def mask_rows(values:List<&2,Visibility.Visibility>) -> String:
  match values:
    case Nil{}: ""
    case Visibility.Visibility{World.Cell{x,y,z,boundary},state,visible} <> tail:
      words([x,y,z,boundary,state,visible]) ++ ";" ++ mask_rows(tail)

def sample_line(serial:Nat,sample:Visibility.Sample) -> String:
  Visibility.Sample{Pixels.Snapshot{tick,revision,blocks,Pixels.Camera{x,y,z,yaw,pitch}},raw,masks,
    Movement.Vec3{Double.F64{xh,xl},Double.F64{yh,yl},Double.F64{zh,zl}},
    World.Palette{air,stone,dirt,planks},reads} = sample
  "resource.sample|" ++ Nat.show(serial) ++ "|" ++ Nat.show(tick) ++ "|" ++ Nat.show(revision) ++ "|" ++
    words([F32.bits(x),F32.bits(y),F32.bits(z),F32.bits(yaw),F32.bits(pitch)]) ++ "|" ++
    words([xh,xl,yh,yl,zh,zl]) ++ "|" ++ words([air,stone,dirt,planks]) ++ "|" ++ U32.show(reads) ++ "|" ++
    block_rows(blocks) ++ "|" ++ raw_rows(raw) ++ "|" ++ mask_rows(masks)

def frame_description(frame:Scene.Frame,config:Config) -> IO(Unit):
  Scene.Frame{sample,tail} = frame
  Config{human,frames,width,height,mode,serial} = config
  match mode:
    case None{}: IO.pure(Unit,Unit{})
    case Some{directory}: IO.print(sample_line(serial,sample))

def snapshot_ready(window:Window,assets:Scene.Assets,handle:Server.Handle<Session.State>,+config:Config,captured:Bool,status:Result<&2,&2,String,Scene.Frame>,resume:Window -> Scene.Assets -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  Config{human,frames,width,height,trace,serial} = config
  match status:
    case Fail{error}: closing(window,assets,handle,1,"frame query: " ++ error)
    case Done{+frame}:
      do IO<Unit>:
        IO.print(Scene.describe(frame))
        frame_description(frame,config)
        drawn(window,handle,config,captured,Scene.canonical(frame),Scene.draw(frame,assets,width,height),resume)

@unsafe
def loop(window:Window,assets:Scene.Assets,+handle:Server.Handle<Session.State>,+config:Config,captured:Bool) -> IO(Unit):
  Config{human,frames,+width,+height,trace,serial} = config
  do IO<Unit>:
    sampled : Result<&2,&2,String,Scene.Frame> <- Server.local_call(Session.State,Result<&2,&2,String,Scene.Frame>,handle,state => Scene.snapshot(state,width,height))
    snapshot_ready(window,assets,handle,config,captured,sampled,w => a => next => capture => loop(w,a,handle,next,capture))

def starting(window:Window,assets:Scene.Assets,handle:Server.Handle<Session.State>,+config:Config,capture:Bool) -> IO(Unit):
  Config{human,frames,width,height,trace,serial} = config
  match frames:
    case Some{0n}: closing(window,assets,handle,0,"client closed")
    case _: loop(window,assets,handle,config,capture)

def captured(assets:Scene.Assets,handle:Server.Handle<Session.State>,+config:Config,value:Window & Bool) -> IO(Unit):
  (window,capture) = value
  starting(window,assets,handle,config,capture)

def opened(assets:Scene.Assets,+handle:Server.Handle<Session.State>,+config:Config,result:Result<&1,&1,U32 & String,Window>) -> IO(Unit):
  Config{human,frames,width,height,trace,serial} = config
  match result:
    case Fail{(code,message)}:
      do IO<Unit>:
        Common.local_release(~Session.State,~Scene.Frame,~Scene.presenter_driver(),handle)
        Scene.close_assets(assets)
        Server.stop(Session.State,handle)
        IO.die(Unit,code,"window open: " ++ message)
    case Done{window}:
      do IO<Unit>:
        actual : Window & Bool <- Input.capture(window,human)
        captured(assets,handle,config,actual)

def open(assets:Scene.Assets,+handle:Server.Handle<Session.State>,human:Bool,frames:Maybe<&2,Nat>,width:U32,height:U32,title:String) -> IO(Unit):
  do IO<Unit>:
    mode : Result<&1,&1,U32 & String,String> <- IO.get_env("BEND_MINECRAFT_FRAME_DIR")
    window : Result<&1,&1,U32 & String,Window> <- Window.open(title,512,512)
    opened(assets,handle,Config{human,frames,width,height,trace_mode(mode),0n},window)
