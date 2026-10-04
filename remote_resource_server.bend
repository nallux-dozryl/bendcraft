import Base
import ./src/remote_resource_backend.bend as Backend
import ./src/remote_resource_transport.bend as Transport
import ./src/resource_client_wire.bend as Wire
import ./src/local_player_scene.bend as Scene
import ./src/local_player_session.bend as Session
import ./src/local_player_storage.bend as Storage
import ./src/local_player_record.bend as Record
import ./src/player_inventory_codec.bend as InventoryStorage
import ./src/player_item_definitions.bend as ItemDefinitions
import ./src/item_component.bend as ItemComponents
import ./src/player_crafting_authority_load.bend as CraftingLoad
import ./src/player_crafting_authority_startup.bend as CraftingStartup
import ./src/player_crafting_session_adapter.bend as CraftingSession
import ./src/player_crafting_authority_components.bend as CraftingComponents
import ./src/world_generation_settings.bend as Generation
import ./src/nbt.bend as NBT
import ./src/core.bend as Core
import ./src/extended_persistence.bend as Persistence
import ./src/locomotion.bend as Motion
import ./src/server.bend as Server
import ./src/json.bend as JSON
import ./src/framing.bend as Framing

import ./src/resource_server_options.bend as CLI

type Config is Data:
  Config{port:U32,capability:String,nonce:String}

def checked_options(result:Result<&2,&2,String,CLI.Options>) -> IO(CLI.Options):
  match result:
    case Fail{message}: IO.die(CLI.Options,1,message)
    case Done{options}: IO.pure(CLI.Options,options)

def parse_cli(args:List<String>) -> IO(CLI.Options):
  match args:
    case name <> rest: checked_options(CLI.validate(CLI.parse(rest,CLI.defaults())))
    case Nil{}: IO.die(CLI.Options,1,"missing argv")

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

def serving(control:Bool,config:Config,state:Backend.State,first_peer:U32) -> IO(Unit):
  Config{port,capability,nonce} = config
  do IO<Unit>:
    +handle : Server.Handle<Backend.State> <- Server.start_effectful_from_peer(~Backend.State,~Backend.driver(),state,first_peer)
    Transport.start(handle,port)
    controlled(handle,control)

def reserved(control:Bool,+config:Config,result:Session.State & Result<&2,&2,String,Core.Capability>) -> IO(Unit):
  Config{port,capability,nonce} = config
  (state,status) = result
  match status:
    case Fail{message}: IO.die(Unit,1,"local player owner: " ++ message)
    case Done{Core.Player{+peer}}:
      serving(control,config,Backend.new_reserved(state,nonce,capability,Core.Player{peer}),U32.inc(peer))
    case Done{other}: IO.die(Unit,1,"local player owner was not allocated")

def started_mode(fixture:Bool,control:Bool,+config:Config,ready:Session.Ready) -> IO(Unit):
  match fixture:
    case True{}:
      Config{port,capability,nonce} = config
      Session.Ready{state,first_peer} = ready
      serving(control,config,Backend.new(state,nonce,capability),first_peer)
    case False{}:
      Session.Ready{state,first_peer} = ready
      reserved(control,config,Session.reserve_local_player(state))

def started(options:CLI.Options,config:Config,ready:Session.Ready) -> IO(Unit):
  CLI.Options{fixture,profile,creative,run,control,sine} = options
  started_mode(fixture,control,config,ready)

def fixture_loaded(+options:CLI.Options,config:Config,tables:Motion.Tables) -> IO(Unit):
  do IO<Unit>:
    stored : Persistence.Ready<Record.Record> <- Persistence.load_with(~Record.Record,~Storage.codec(),~Session.operations(),Storage.limits())
    ready : Session.Ready <- Session.new(stored,tables)
    initialized : Session.Ready <- Scene.initialize(ready)
    started(options,config,Scene.run_requested(initialized,CLI.running(options)))

def crafting_reserved(control:Bool,+config:Config,context:CraftingSession.Context,
    result:Session.State & Result<&2,&2,String,Core.Capability>) -> IO(Unit):
  Config{port,capability,nonce} = config
  (state,status) = result
  match status:
    case Fail{message}: IO.die(Unit,1,"local player owner: " ++ message)
    case Done{Core.Player{+peer}}:
      serving(control,config,Backend.new_reserved_with_crafting(state,nonce,capability,Core.Player{peer},context),U32.inc(peer))
    case Done{other}: IO.die(Unit,1,"local player owner was not allocated")

def crafting_started(+options:CLI.Options,config:Config,context:CraftingSession.Context,ready:Session.Ready) -> IO(Unit):
  CLI.Options{fixture,profile,creative,run,control,sine} = options
  Session.Ready{state,first_peer} = ready
  crafting_reserved(control,config,context,Session.reserve_local_player(state))

def profile_loaded(codec:Persistence.Codec<InventoryStorage.Saved>,+options:CLI.Options,config:Config,tables:Motion.Tables,settings:Generation.Settings,context:CraftingSession.Context) -> IO(Unit):
  do IO<Unit>:
    stored : Persistence.Ready<InventoryStorage.Saved> <- Persistence.load_codec(~InventoryStorage.Saved,~Session.inventory_operations(),codec,InventoryStorage.limits())
    ready : Session.Ready <- Session.new_inventory(stored,tables)
    initialized : Session.Ready <- Scene.initialize_generated(ready,settings)
    crafting_started(options,config,context,Scene.run_requested(initialized,CLI.running(options)))

def profile_definitions(+options:CLI.Options,config:Config,tables:Motion.Tables,+definitions:ItemDefinitions.Catalog,context:CraftingSession.Context) -> IO(Unit):
  CLI.Options{fixture,profile,creative,run,control,sine} = options
  +settings = Generation.stone_dirt(NBT.Word64{0,0})
  profile_loaded(InventoryStorage.codec_with(definitions,creative,settings),options,config,tables,settings,context)

def crafting_mode_defaults(value:Maybe<&2,ItemComponents.Defaults>) -> IO(CraftingComponents.Mode):
  match value:
    case None{}: IO.die(CraftingComponents.Mode,1,"initialized suspicious stew component defaults are unavailable")
    case Some{defaults}: IO.pure(CraftingComponents.Mode,CraftingComponents.TypedStew{defaults})

def crafting_mode(definitions:ItemDefinitions.Catalog) -> IO(CraftingComponents.Mode):
  crafting_mode_defaults(ItemDefinitions.component_defaults(definitions,"minecraft:suspicious_stew"))

def crafting_service(+options:CLI.Options,config:Config,tables:Motion.Tables,
    result:Result<&2,&2,String,CraftingLoad.Service>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,1,"crafting startup: " ++ message)
    case Done{CraftingLoad.Service{+definitions,recipes}}:
      do IO<Unit>:
        mode:CraftingComponents.Mode <- crafting_mode(definitions)
        profile_definitions(options,config,tables,definitions,CraftingSession.new_with_components(recipes,mode))

def default_game_jar(result:Result<&1,&1,U32 & String,String>) -> IO(String):
  match result:
    case Fail{cause}: IO.die(String,1,"HOME is required when MC_GAME_JAR is unset")
    case Done{home}: IO.pure(String,home ++ "/Library/Application Support/minecraft/versions/26.3/26.3.jar")

def game_jar_selected(result:Result<&1,&1,U32 & String,String>) -> IO(String):
  match result:
    case Done{path}: IO.pure(String,path)
    case Fail{cause}:
      do IO<String>:
        home:Result<&1,&1,U32 & String,String> <- IO.get_env("HOME")
        default_game_jar(home)

# Registry facts are checked against their extracted digest. Recipe JSON is
# read from the installed 26.3 JAR; its directory order never sets precedence.
def crafting_world(options:CLI.Options,config:Config,tables:Motion.Tables) -> IO(Unit):
  do IO<Unit>:
    selected:Result<&1,&1,U32 & String,String> <- IO.get_env("MC_GAME_JAR")
    jar:String <- game_jar_selected(selected)
    service:Result<&2,&2,String,CraftingLoad.Service> <- CraftingStartup.service(jar,
      "generated/reference_item_metadata.tsv","generated/reference_crafting_authority_metadata.json",CraftingLoad.defaults())
    crafting_service(options,config,tables,service)

def selected_world(+options:CLI.Options,config:Config,tables:Motion.Tables) -> IO(Unit):
  CLI.Options{fixture,profile,creative,run,control,sine} = options
  match fixture:
    case True{}: fixture_loaded(options,config,tables)
    case False{}:
      crafting_world(options,config,tables)

def loaded(+options:CLI.Options,config:Config) -> IO(Unit):
  CLI.Options{fixture,profile,creative,run,control,sine} = options
  do IO<Unit>:
    loaded_tables : Result<&2,&1,Motion.Error,Motion.Tables> <- Motion.Tables.load(sine)
    tables : Motion.Tables <- checked_tables(loaded_tables)
    selected_world(options,config,tables)

def arguments(args:List<String>) -> IO(Unit):
  do IO<Unit>:
    options : CLI.Options <- parse_cli(args)
    config : Config <- configured()
    loaded(options,config)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
