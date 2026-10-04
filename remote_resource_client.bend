import Base
import ./src/remote_resource_presenter.bend as Presenter
import ./src/resource_client_wire.bend as Wire
import ./src/resource_frame.bend as RF
import ./src/world_resource_frame.bend as WRF
import ./src/world_visibility.bend as Visibility

# The backend owns the saved world and LocalPlayer. This entry connects to its
# private frame/input capability and owns only real resources/presentation.
type Options is Data:
  Options{frames:Maybe<&2,Nat>,jar:String}

def defaults() -> Options:
  Options{None{},"/Users/chuah/Library/Application Support/minecraft/versions/26.3/26.3.jar"}

def count(options:Options,result:Maybe<&2,U32>) -> Result<&2,&2,String,Options>:
  match options result:
    case _ None{}: Fail{"--frames requires an unsigned integer"}
    case Options{frames,jar} Some{value}: Done{Options{Some{U32.to_nat(value)},jar}}

def parse(args:List<String>,options:Options) -> Result<&2,&2,String,Options>:
  match args options:
    case Nil{} _: Done{options}
    case "--frames" <> value <> rest _:
      do Result<&2,&2,String,Options>:
        next : Options <- count(options,U32.read(value))
        parse(rest,next)
    case "--jar" <> value <> rest Options{frames,jar}: parse(rest,Options{frames,value})
    case value <> rest _: Fail{"unknown/incomplete option " ++ value}

def checked_options(result:Result<&2,&2,String,Options>) -> IO(Options):
  match result:
    case Fail{message}: IO.die(Options,1,message)
    case Done{options}: IO.pure(Options,options)

def cli(args:List<String>) -> IO(Options):
  match args:
    case Nil{}: IO.die(Options,1,"missing argv")
    case name <> rest: checked_options(parse(rest,defaults()))

def human(mode:Result<&1,&1,U32 & String,String>) -> Bool:
  match mode:
    case Done{"hidden"}: False{}
    case _: True{}

def failed(link:Presenter.Link,message:String) -> IO(Unit):
  do IO<Unit>:
    Presenter.release_close(link)
    IO.die(Unit,1,message)

def open_mode(options:Options,link:Presenter.Link,sample:Visibility.Sample,assets:RF.Assets,interactive:Bool) -> IO(Unit):
  Options{frames,jar} = options
  match interactive:
    case True{}: Presenter.open(assets,link,sample,True{},frames,320,180)
    case False{}: Presenter.open(assets,link,sample,False{},frames,128,128)

def assets_ready(options:Options,link:Presenter.Link,sample:Visibility.Sample,result:Result<&2,&1,String,RF.Assets>) -> IO(Unit):
  Options{frames,jar} = options
  match result:
    case Fail{message}: failed(link,"resource scene: " ++ message)
    case Done{assets}:
      do IO<Unit>:
        mode : Result<&1,&1,U32 & String,String> <- IO.get_env("BEND_MINECRAFT_LAUNCH_MODE")
        open_mode(Options{frames,jar},link,sample,assets,human(mode))

def load_frame(+options:Options,link:Presenter.Link,+sample:Visibility.Sample) -> IO(Unit):
  Options{frames,jar} = options
  Visibility.Sample{snapshot,raw,masks,origin,palette,reads} = sample
  do IO<Unit>:
    loaded : Result<&2,&1,String,RF.Assets> <- RF.load(jar,WRF.resource_palette(palette))
    assets_ready(options,link,sample,loaded)

def initial_frame(options:Options,result:Presenter.Link & Result<&2,&2,String,Wire.Reply>) -> IO(Unit):
  (link,status) = result
  match status:
    case Fail{message}: failed(link,"frame query: " ++ message)
    case Done{Wire.FrameReply{epoch,sequence,sample}}: load_frame(options,link,sample)
    case Done{other}: failed(link,"frame query: Wire:ExpectedFrame")

def connected(options:Options,result:Presenter.Link & Result<&2,&2,String,Wire.Reply>) -> IO(Unit):
  (link,status) = result
  match status:
    case Fail{message}: failed(link,message)
    case Done{Wire.HelloAck{epoch,zero}}:
      do IO<Unit>:
        reply : Presenter.Link & Result<&2,&2,String,Wire.Reply> <- Presenter.call(link,Wire.Frame{128,128})
        initial_frame(options,reply)
    case Done{other}: failed(link,"Wire:ExpectedHello")

def connect_valid(options:Options,value:U32,capability:String,valid:Bool) -> IO(Unit):
  match valid:
    case False{}: IO.die(Unit,1,"invalid MC_RENDER_PORT")
    case True{}:
      do IO<Unit>:
        result : Presenter.Link & Result<&2,&2,String,Wire.Reply> <- Presenter.connect(value,capability)
        connected(options,result)

def connect_options(options:Options,port:Maybe<&2,U32>,capability:String) -> IO(Unit):
  match port:
    case Some{+value}: connect_valid(options,value,capability,U32.is_ge(value,1) && U32.is_le(value,65535))
    case None{}: IO.die(Unit,1,"invalid MC_RENDER_PORT")

def configured(options:Options,port:Result<&1,&1,U32 & String,String>,capability:Result<&1,&1,U32 & String,String>) -> IO(Unit):
  match port capability:
    case Done{value} Done{token}: connect_options(options,U32.read(value),token)
    case _ _: IO.die(Unit,1,"MC_RENDER_PORT and MC_RENDER_TOKEN are required")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    options : Options <- cli(args)
    port : Result<&1,&1,U32 & String,String> <- IO.get_env("MC_RENDER_PORT")
    capability : Result<&1,&1,U32 & String,String> <- IO.get_env("MC_RENDER_TOKEN")
    configured(options,port,capability)
