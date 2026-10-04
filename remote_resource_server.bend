import Base
import ./src/remote_resource_backend.bend as Backend
import ./src/remote_resource_transport.bend as Transport
import ./src/resource_client_wire.bend as Wire
import ./src/local_player_scene.bend as Scene
import ./src/local_player_session.bend as Session
import ./src/local_player_storage.bend as Storage
import ./src/local_player_record.bend as Record
import ./src/extended_persistence.bend as Persistence
import ./src/locomotion.bend as Motion
import ./src/server.bend as Server
import ./src/json.bend as JSON
import ./src/framing.bend as Framing

type Options is Data:
  Options{fixture:Bool,run:Bool,control:Bool,sine:String}
type Config is Data:
  Config{port:U32,capability:String,nonce:String}

def defaults() -> Options:
  Options{False{},False{},False{},"generated/reference_mth_sin.f32"}

def parse(args:List<String>,options:Options) -> Result<&2,&2,String,Options>:
  match args options:
    case Nil{} _: Done{options}
    case "--verification-fixture" <> rest Options{fixture,run,control,sine}:
      parse(rest,Options{True{},run,control,sine})
    case "--unpaused" <> rest Options{fixture,run,control,sine}:
      parse(rest,Options{fixture,True{},control,sine})
    case "--stdin-control" <> rest Options{fixture,run,control,sine}:
      parse(rest,Options{fixture,run,True{},sine})
    case "--sine" <> value <> rest Options{fixture,run,control,sine}:
      parse(rest,Options{fixture,run,control,value})
    case value <> rest _: Fail{"unknown/incomplete option " ++ value}

def checked_options(result:Result<&2,&2,String,Options>) -> IO(Options):
  match result:
    case Fail{message}: IO.die(Options,1,message)
    case Done{Options{False{},run,control,sine}}:
      IO.die(Options,1,"A playable world loader is not implemented. This entry requires --verification-fixture.")
    case Done{options}: IO.pure(Options,options)

def parse_cli(args:List<String>) -> IO(Options):
  match args:
    case name <> rest: checked_options(parse(rest,defaults()))
    case Nil{}: IO.die(Options,1,"missing argv")

def port_range(port:U32,valid:Bool) -> IO(U32):
  match valid:
    case False{}: IO.die(U32,1,"MC_RENDER_PORT must be an integer from 1 through 65535")
    case True{}: IO.pure(U32,port)

def port_parsed(value:Maybe<&2,U32>) -> IO(U32):
  match value:
    case None{}: IO.die(U32,1,"MC_RENDER_PORT must be an integer from 1 through 65535")
    case Some{+port}: port_range(port,U32.is_gt(port,0) && U32.is_lt(port,65536))

def required_port(result:Result<&1,&1,U32 & String,String>) -> IO(U32):
  match result:
    case Fail{cause}: IO.die(U32,1,"MC_RENDER_PORT is required")
    case Done{text}: port_parsed(JSON.as_u32(JSON.JNumber{text}))

def text_valid(text:String,name:String,valid:Bool) -> IO(String):
  match valid:
    case False{}: IO.die(String,1,name ++ " must contain nonempty printable ASCII within its bound")
    case True{}: IO.pure(String,text)

def required_text(result:Result<&1,&1,U32 & String,String>,name:String,maximum:Nat) -> IO(String):
  match result:
    case Fail{cause}: IO.die(String,1,name ++ " is required")
    case Done{+text}: text_valid(text,name,Wire.nonempty_ascii(text,maximum))

def configured() -> IO(Config):
  do IO<Config>:
    port_result : Result<&1,&1,U32 & String,String> <- IO.get_env("MC_RENDER_PORT")
    port : U32 <- required_port(port_result)
    capability_result : Result<&1,&1,U32 & String,String> <- IO.get_env("MC_RENDER_TOKEN")
    capability : String <- required_text(capability_result,"MC_RENDER_TOKEN",256n)
    nonce_result : Result<&1,&1,U32 & String,String> <- IO.get_env("MC_RENDER_EPOCH")
    nonce : String <- required_text(nonce_result,"MC_RENDER_EPOCH",32n)
    return Config{port,capability,nonce}

def checked_tables(result:Result<&2,&1,Motion.Error,Motion.Tables>) -> IO(Motion.Tables):
  match result:
    case Fail{cause}: IO.die(Motion.Tables,1,"could not load the verified sine table")
    case Done{tables}: IO.pure(Motion.Tables,tables)

# Explicit stop releases physical controls, then terminates the actor and the
# owning process. Save acknowledgment is a separate public world.save request.
def stop(+handle:Server.Handle<Backend.State>,input:File,code:U32,message:String) -> IO(Unit):
  do IO<Unit>:
    File.close(input)
    released : Unit <- Server.local_call(Backend.State,Unit,handle,Backend.stop_release)
    Server.stop(Backend.State,handle)
    IO.die(Unit,code,message)

def command(+handle:Server.Handle<Backend.State>,input:File,text:String,rest:File -> IO(Unit)) -> IO(Unit):
  match text:
    case "stop": stop(handle,input,0,"resource backend stopped")
    case _:
      do IO<Unit>:
        IO.print_err("stdin control accepts stop only")
        rest(input)

def lines(+handle:Server.Handle<Backend.State>,records:List<&2,String>,input:File,rest:File -> IO(Unit)) -> IO(Unit):
  match records:
    case Nil{}: rest(input)
    case text <> tail: command(handle,input,text,file => lines(handle,tail,file,rest))

def fed(+handle:Server.Handle<Backend.State>,input:File,result:Result<&1,&1,String,Framing.Buffer & List<&2,String>>,
    rest:File -> Framing.Buffer -> IO(Unit)) -> IO(Unit):
  match result:
    case Fail{message}: stop(handle,input,1,"invalid stdin control framing")
    case Done{Tuple{buffer,records}}: lines(handle,records,input,file => rest(file,buffer))

def read_next(+handle:Server.Handle<Backend.State>,buffer:Framing.Buffer,
    result:File & Result<&1,&1,U32 & String,List<&2,U32>>,rest:File -> Framing.Buffer -> IO(Unit)) -> IO(Unit):
  (input,status) = result
  match status:
    case Fail{cause}: stop(handle,input,1,"stdin control read failed")
    case Done{Nil{}}: stop(handle,input,0,"stdin control ended")
    case Done{bytes}: fed(handle,input,Framing.feed(buffer,bytes),rest)

@unsafe
def control_loop(+handle:Server.Handle<Backend.State>,input:File,buffer:Framing.Buffer) -> IO(Unit):
  do IO<Unit>:
    result : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(input,8192)
    read_next(handle,buffer,result,file => next => control_loop(handle,file,next))

def controlled(handle:Server.Handle<Backend.State>,enabled:Bool) -> IO(Unit):
  match enabled:
    case False{}: IO.pure(Unit,Unit{})
    case True{}:
      do IO<Unit>:
        input : File <- IO.try(File,File.open("/dev/stdin","r"))
        control_loop(handle,input,Framing.new())

def started(options:Options,config:Config,ready:Session.Ready) -> IO(Unit):
  Options{fixture,run,control,sine} = options
  Config{port,capability,nonce} = config
  Session.Ready{state,first_peer} = ready
  do IO<Unit>:
    +handle : Server.Handle<Backend.State> <- Server.start_effectful_from_peer(~Backend.State,~Backend.driver(),Backend.new(state,nonce,capability),first_peer)
    Transport.start(handle,port)
    controlled(handle,control)

def loaded(+options:Options,config:Config) -> IO(Unit):
  Options{fixture,+run,control,sine} = options
  do IO<Unit>:
    loaded_tables : Result<&2,&1,Motion.Error,Motion.Tables> <- Motion.Tables.load(sine)
    tables : Motion.Tables <- checked_tables(loaded_tables)
    stored : Persistence.Ready<Record.Record> <- Persistence.load_with(~Record.Record,~Storage.codec(),~Session.operations(),Storage.limits())
    ready : Session.Ready <- Session.new(stored,tables)
    initialized : Session.Ready <- Scene.initialize(ready)
    started(options,config,Scene.run_requested(initialized,run))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    options : Options <- parse_cli(args)
    config : Config <- configured()
    loaded(options,config)
