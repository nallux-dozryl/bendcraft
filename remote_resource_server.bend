import Base
import ./src/remote_resource_backend.bend as Backend
import ./src/remote_resource_transport.bend as Transport
import ./src/resource_client_wire.bend as Wire
import ./src/local_player_scene.bend as Scene
import ./src/local_player_session.bend as Session
import ./src/local_player_storage.bend as Storage
import ./src/local_player_record.bend as Record
import ./src/local_player_cooking_storage.bend as CookingStorage
import ./src/player_item_definitions.bend as ItemDefinitions
import ./src/item_component.bend as ItemComponents
import ./src/player_crafting_authority_load.bend as CraftingLoad
import ./src/player_crafting_authority_startup.bend as CraftingStartup
import ./src/player_crafting_session_adapter.bend as CraftingSession
import ./src/player_crafting_authority_components.bend as CraftingComponents
import ./src/player_item_catalog.bend as ItemCatalog
import ./src/crafting_recipe.bend as Recipes
import ./src/crafting_recipe_decoder.bend as RecipeDecoder
import ./src/crafting_recipe_components.bend as RecipeComponents
import ./src/cooking_recipe.bend as CookingRecipes
import ./src/cooking_recipe_decoder.bend as CookingDecoder
import ./src/campfire_authority_items.bend as CookingItems
import ./src/furnace_authority_fuel.bend as CookingFuel
import ./src/furnace_authority_decoder.bend as FuelDecoder
import ./src/cooking_world.bend as CookingWorld
import ./src/cooking_block_entity_codec.bend as CookingCodec
import ./src/cooking_world_bindings.bend as CookingBindings
import ./src/cooking_world_bindings_loader.bend as CookingBindingsLoad
import ./src/local_player_cooking.bend as Cooking
import ./src/block_light_registry.bend as LightRegistry
import ./src/block_light_registry_loader.bend as LightLoad
import ./src/block_light_world.bend as LightWorld
import ./src/block_light.bend as Light
import ./src/local_player_runtime.bend as Runtime
import ./src/client_world.bend as ClientWorld
import ./src/game.bend as Game
import ./src/registry.bend as Registry
import ./src/section_map.bend as Sections
import ./src/archive.bend as Archive
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

type Catalogs is Data:
  Catalogs{definitions:ItemDefinitions.Catalog,crafting:Recipes.Catalog,
    cooking:CookingRecipes.Catalog,defaults:List<&2,RecipeComponents.Default>,
    features:Map<&2,Maybe<&2,Bool>>,fuel:CookingFuel.Catalog}
type FuelSource is Data:
  FuelSource{path:String,group:U32,id:String}
type Providers is Data:
  Providers{ints:List<&2,JSON.Value>,floats:List<&2,JSON.Value>,
    predicates:List<&2,JSON.Value>,bytes:U32}
type Terrain is Data:
  Terrain{count:U32,enabled:Map<&2,Bool>,budget:Nat}

def startup_bytes(status:Result<&2,&2,LightLoad.Error,List<&2,U32>>,path:String) -> Result<&2,&2,String,List<&2,U32>>:
  match status:
    case Fail{error}: Fail{"could not read bounded startup input: " ++ path}
    case Done{bytes}: Done{bytes}

def startup_read(+path:String,limit:Nat) -> IO(Result<&2,&2,String,List<&2,U32>>):
  do IO<Result<&2,&2,String,List<&2,U32>>>:
    status:Result<&2,&2,LightLoad.Error,List<&2,U32>> <- LightLoad.read_file(limit,path)
    return startup_bytes(status,path)

def startup_features(values:List<&2,ItemDefinitions.Definition>,entries:Map<&2,Maybe<&2,Bool>>) -> Map<&2,Maybe<&2,Bool>>:
  match values:
    case Nil{}: entries
    case ItemDefinitions.Definition{number,id,description,maximum,set,identity,enabled} <> rest:
      startup_features(rest,Map.set(&2,Maybe<&2,Bool>,entries,id,Some{enabled}))

def fuel_source_selected(valid:Bool,+path:String,group:U32,prefix:String) -> Maybe<&2,FuelSource>:
  match valid:
    case False{}: None{}
    case True{}:
      +relative = String.drop(path,String.length(prefix))
      Some{FuelSource{path,group,"minecraft:" ++ String.take(relative,Nat.sub(String.length(relative),5n))}}

def fuel_source_int(+path:String,selected:Bool) -> Maybe<&2,FuelSource>:
  match selected:
    case True{}: fuel_source_selected(True{},path,0,"data/minecraft/context_int_provider/")
    case False{}:
      fuel_source_selected(String.starts_with(path,"data/minecraft/context_float_provider/cooking/") && String.ends_with(path,".json"),path,1,"data/minecraft/context_float_provider/")

def fuel_source_predicate(+path:String,selected:Bool) -> Maybe<&2,FuelSource>:
  match selected:
    case True{}: Some{FuelSource{path,2,"minecraft:block/fast_cooking"}}
    case False{}:
      fuel_source_int(path,String.starts_with(path,"data/minecraft/context_int_provider/cooking/") && String.ends_with(path,".json"))

def fuel_source(+path:String) -> Maybe<&2,FuelSource>:
  fuel_source_predicate(path,String.eq(path,"data/minecraft/predicate/block/fast_cooking.json"))

def fuel_sources_cons(value:Maybe<&2,FuelSource>,tail:List<&2,FuelSource>) -> List<&2,FuelSource>:
  match value:
    case None{}: tail
    case Some{source}: source <> tail

def fuel_sources(values:List<&2,String>) -> List<&2,FuelSource>:
  match values:
    case Nil{}: []
    case name <> rest: fuel_sources_cons(fuel_source(name),fuel_sources(rest))

def provider_added(group:U32,row:JSON.Value,bytes:U32,values:Providers) -> Providers:
  match group values:
    case 0 Providers{ints,floats,predicates,old}: Providers{row <> ints,floats,predicates,bytes}
    case 1 Providers{ints,floats,predicates,old}: Providers{ints,row <> floats,predicates,bytes}
    case _ Providers{ints,floats,predicates,old}: Providers{ints,floats,row <> predicates,bytes}

def provider_read(read:Archive.Archive & Result<&2,&2,String,CraftingLoad.Work>,group:U32,values:Providers) -> Archive.Archive & Result<&2,&2,String,Providers>:
  (archive,status) = read
  match status:
    case Fail{message}: (archive,Fail{message})
    case Done{CraftingLoad.Work{row <> Nil{},bytes}}: (archive,Done{provider_added(group,row,bytes,values)})
    case _: (archive,Fail{"invalid cooking provider read"})

def providers_next(read:Archive.Archive & Result<&2,&2,String,Providers>,
    next:Archive.Archive -> Result<&2,&2,String,Providers> -> IO(Archive.Archive & Result<&2,&2,String,Providers>)) -> IO(Archive.Archive & Result<&2,&2,String,Providers>):
  (archive,status) = read
  next(archive)(status)

def providers(values:List<&2,FuelSource>,archive:Archive.Archive,+directory:Archive.Directory,
    status:Result<&2,&2,String,Providers>,+limits:CraftingLoad.Limits) -> IO(Archive.Archive & Result<&2,&2,String,Providers>):
  match values status:
    case _ Fail{message}: IO.pure(Archive.Archive & Result<&2,&2,String,Providers>,(archive,Fail{message}))
    case Nil{} _: IO.pure(Archive.Archive & Result<&2,&2,String,Providers>,(archive,status))
    case FuelSource{path,+group,id} <> rest Done{+work}:
      Providers{ints,floats,predicates,bytes} = work
      do IO<Archive.Archive & Result<&2,&2,String,Providers>>:
        read:Archive.Archive & Result<&2,&2,String,CraftingLoad.Work> <- CraftingLoad.source_found(
          Archive.lookup(directory,path),archive,id,CraftingLoad.Work{[],bytes},limits)
        providers_next(provider_read(read,group,work),archive => status => providers(rest,archive,directory,status,limits))

def catalogs(metadata:JSON.Value,+definitions:ItemDefinitions.Catalog,context:CraftingLoad.Context,
    sources:List<&2,JSON.Value>,provider_status:Result<&2,&2,String,Providers>) -> Result<&2,&2,String,Catalogs>:
  match context provider_status:
    case _ Fail{message}: Fail{message}
    case CraftingLoad.Context{+items,+tags} Done{Providers{ints,floats,predicates,bytes}}:
      do Result<&2,&2,String,Catalogs>:
        +item_rows:List<&2,JSON.Value> <- RecipeDecoder.array(items)
        +defaults:List<&2,RecipeComponents.Default> <- RecipeDecoder.defaults_rows(item_rows,[])
        +raw:JSON.Value = JSON.JObject{[JSON.JMember{"items",items},JSON.JMember{"tags",tags},JSON.JMember{"recipes",JSON.JArray{sources}}]}
        crafting:Recipes.Catalog <- RecipeDecoder.catalog(raw)
        cooking:CookingRecipes.Catalog <- CookingDecoder.catalog(raw)
        fuel:CookingFuel.Catalog <- FuelDecoder.catalog(JSON.JObject{
          [JSON.JMember{"ints",JSON.JArray{List.reverse(&2,JSON.Value,ints)}},
           JSON.JMember{"floats",JSON.JArray{List.reverse(&2,JSON.Value,floats)}},
           JSON.JMember{"predicates",JSON.JArray{List.reverse(&2,JSON.Value,predicates)}},
           JSON.JMember{"tags",JSON.JArray{[]}},JSON.JMember{"defaults",JSON.JArray{item_rows}}]})
        return Catalogs{definitions,crafting,cooking,defaults,startup_features(ItemDefinitions.all(definitions),MTip{}),fuel}

def catalogs_closed(metadata:JSON.Value,definitions:ItemDefinitions.Catalog,context:CraftingLoad.Context,
    sources:List<&2,JSON.Value>,read:Archive.Archive & Result<&2,&2,String,Providers>) -> IO(Result<&2,&2,String,Catalogs>):
  (archive,status) = read
  do IO<Result<&2,&2,String,Catalogs>>:
    Archive.Archive.close(archive)
    return catalogs(metadata,definitions,context,sources,status)

def recipes_loaded(metadata:JSON.Value,definitions:ItemDefinitions.Catalog,context:CraftingLoad.Context,
    +directory:Archive.Directory,+limits:CraftingLoad.Limits,
    read:Archive.Archive & Result<&2,&2,String,CraftingLoad.Work>) -> IO(Result<&2,&2,String,Catalogs>):
  (archive,status) = read
  match status:
    case Fail{message}:
      do IO<Result<&2,&2,String,Catalogs>>:
        Archive.Archive.close(archive)
        return Fail{message}
    case Done{CraftingLoad.Work{recipes,bytes}}:
      do IO<Result<&2,&2,String,Catalogs>>:
        read:Archive.Archive & Result<&2,&2,String,Providers> <- providers(fuel_sources(Archive.entry_names(directory)),
          archive,directory,Done{Providers{[],[],[],bytes}},limits)
        catalogs_closed(metadata,definitions,context,List.reverse(&2,JSON.Value,recipes),read)

def startup_directory(metadata:JSON.Value,definitions:ItemDefinitions.Catalog,context:CraftingLoad.Context,
    ids:List<&2,String>,+limits:CraftingLoad.Limits,read:Archive.Archive & Archive.Directory) -> IO(Result<&2,&2,String,Catalogs>):
  (archive,+directory) = read
  do IO<Result<&2,&2,String,Catalogs>>:
    sources:Archive.Archive & Result<&2,&2,String,CraftingLoad.Work> <- CraftingLoad.sources(ids,archive,directory,Done{CraftingLoad.Work{[],0}},limits)
    recipes_loaded(metadata,definitions,context,directory,limits,sources)

def startup_opened(metadata:JSON.Value,definitions:ItemDefinitions.Catalog,context:CraftingLoad.Context,
    ids:List<&2,String>,limits:CraftingLoad.Limits,status:Result<&2,&1,Archive.Error,Archive.Archive>) -> IO(Result<&2,&2,String,Catalogs>):
  match status:
    case Fail{error}: IO.pure(Result<&2,&2,String,Catalogs>,Fail{Archive.error_text(error)})
    case Done{archive}: startup_directory(metadata,definitions,context,ids,limits,Archive.Archive.directory(archive))

def startup_admitted(metadata:JSON.Value,definitions:ItemDefinitions.Catalog,ids:List<&2,String>,limits:CraftingLoad.Limits) -> Result<&2,&2,String,CraftingLoad.Context>:
  do Result<&2,&2,String,CraftingLoad.Context>:
    CraftingLoad.request_guard(ids,limits)
    CraftingLoad.context_with(metadata,definitions)

def startup_context(status:Result<&2,&2,String,CraftingLoad.Context>,jar:String,metadata:JSON.Value,definitions:ItemDefinitions.Catalog,ids:List<&2,String>,+limits:CraftingLoad.Limits) -> IO(Result<&2,&2,String,Catalogs>):
  match status:
    case Fail{message}: IO.pure(Result<&2,&2,String,Catalogs>,Fail{message})
    case Done{context}:
      CraftingLoad.Limits{archive,count,entry,total,depth} = limits
      do IO<Result<&2,&2,String,Catalogs>>:
        opened:Result<&2,&1,Archive.Error,Archive.Archive> <- Archive.load(jar,Archive.UTF8Fallback{},archive)
        startup_opened(metadata,definitions,context,ids,limits,opened)

def startup_catalogs(jar:String,+metadata:JSON.Value,+definitions:ItemDefinitions.Catalog,+ids:List<&2,String>,+limits:CraftingLoad.Limits) -> IO(Result<&2,&2,String,Catalogs>):
  startup_context(startup_admitted(metadata,definitions,ids,limits),jar,metadata,definitions,ids,limits)

# Enumerate the actual owner and return its exact section trie. Enabled light
# keys encode block origins, while Core keys encode section coordinates.
def terrain_enabled_origin(entries:Map<&2,Bool>,status:Result<&2,&2,LightWorld.Error,Core.Position>,
    next:Map<&2,Bool> -> Result<&2,&2,String,Map<&2,Bool>>) -> Result<&2,&2,String,Map<&2,Bool>>:
  match status:
    case Fail{error}: Fail{"invalid loaded terrain section key"}
    case Done{position}: next(Map.set(&2,Bool,entries,Light.key(position),True{}))

def terrain_enabled(values:List<&2,String>,entries:Map<&2,Bool>) -> Result<&2,&2,String,Map<&2,Bool>>:
  match values:
    case Nil{}: Done{entries}
    case key <> rest: terrain_enabled_origin(entries,LightWorld.key_origin(key),entries => terrain_enabled(rest,entries))

def terrain_metadata(count:U32,+keys:List<&2,String>) -> Result<&2,&2,String,Terrain>:
  do Result<&2,&2,String,Terrain>:
    enabled:Map<&2,Bool> <- terrain_enabled(keys,MTip{})
    return Terrain{count,enabled,Nat.add(Nat.mul(List.length(&2,String,keys),4099n),1n)}

def terrain_sections(world:Core.World,registry:Registry.Registry,view:ClientWorld.View,read:Sections.Sections & List<&2,String>) -> ClientWorld.State & Result<&2,&2,String,Terrain>:
  Core.World{tick,time,paused,daylight,revision,+count,empty,pending,events} = world
  (sections,keys) = read
  (ClientWorld.attach(Game.Engine{Core.World{tick,time,paused,daylight,revision,count,sections,pending,events},registry},view),terrain_metadata(count,keys))

def terrain_taken(read:Game.Engine & ClientWorld.View) -> ClientWorld.State & Result<&2,&2,String,Terrain>:
  (Game.Engine{Core.World{tick,time,paused,daylight,revision,count,sections,pending,events},registry},view) = read
  terrain_sections(Core.World{tick,time,paused,daylight,revision,count,Sections.EmptySections{},pending,events},registry,view,LightWorld.section_keys(sections))

def terrain_world(world:ClientWorld.State) -> ClientWorld.State & Result<&2,&2,String,Terrain>:
  terrain_taken(ClientWorld.take(world))

def terrain(state:Session.State) -> Session.State & Result<&2,&2,String,Terrain>:
  Session.query(Result<&2,&2,String,Terrain>,state,player => Runtime.query(Result<&2,&2,String,Terrain>,player,terrain_world))

def cooking_failed(state:Session.State,message:String) -> IO(Session.Ready):
  Session.State{player,shell} = state
  Session.startup_failed(shell,"cooking startup: " ++ message)

def cooking_bodies_next(result:Session.State & Result<&2,&2,String,CookingCodec.Details>,
    next:Session.State -> Session.State & Result<&2,&2,String,Unit>) -> Session.State & Result<&2,&2,String,Unit>:
  (state,status) = result
  match status:
    case Fail{message}: (state,Fail{message})
    case Done{details}: next(state)

def cooking_bodies(values:List<&2,CookingStorage.Body>,state:Session.State) -> Session.State & Result<&2,&2,String,Unit>:
  match values:
    case Nil{}: (state,Done{Unit{}})
    case CookingStorage.Body{position,bytes} <> rest:
      cooking_bodies_next(Session.cooking_load_body(state,position,CookingStorage.nbt_limits(),bytes,Core.Developer{}),
        state => cooking_bodies(rest,state))

def cooking_bodies_ready(first_peer:U32,result:Session.State & Result<&2,&2,String,Unit>) -> IO(Session.Ready):
  (state,status) = result
  match status:
    case Fail{message}: cooking_failed(state,message)
    case Done{unit}: IO.pure(Session.Ready,Session.Ready{state,first_peer})

def cooking_resumed(first_peer:U32,bodies:List<&2,CookingStorage.Body>,result:Session.State & Result<&2,&2,String,Bool>) -> IO(Session.Ready):
  (state,status) = result
  match status:
    case Fail{message}: cooking_failed(state,message)
    case Done{False{}}: cooking_failed(state,"terrain bootstrap did not complete its derived work budget")
    case Done{True{}}: cooking_bodies_ready(first_peer,cooking_bodies(bodies,state))

def cooking_begun(first_peer:U32,bodies:List<&2,CookingStorage.Body>,budget:Nat,result:Session.State & Result<&2,&2,String,Unit>) -> IO(Session.Ready):
  (state,status) = result
  match status:
    case Fail{message}: cooking_failed(state,message)
    case Done{unit}: cooking_resumed(first_peer,bodies,Session.cooking_resume_loading(state,budget))

def cooking_context(catalogs:Catalogs,enabled:Map<&2,Bool>,light:Result<&2,&2,LightLoad.Error,LightRegistry.Catalog>,bindings:Result<&2,&2,String,CookingBindings.Catalog>) -> Result<&2,&2,String,Cooking.Context>:
  match catalogs light bindings:
    case _ Fail{error} _: Fail{"authenticated light registry does not match the actual world"}
    case _ Done{registry} Fail{message}: Fail{message}
    case Catalogs{definitions,crafting,cooking,defaults,features,fuel} Done{registry} Done{catalog}:
      Done{Cooking.Context{registry,enabled,CookingWorld.Context{catalog,CookingItems.Context{cooking,defaults,features},fuel,256n},[]}}

def cooking_configured(first_peer:U32,bodies:List<&2,CookingStorage.Body>,budget:Nat,state:Session.State,status:Result<&2,&2,String,Cooking.Context>) -> IO(Session.Ready):
  match status:
    case Fail{message}: cooking_failed(state,message)
    case Done{context}: cooking_begun(first_peer,bodies,budget,Session.cooking_begin(state,context))

def cooking_bindings(+identity:String,count:U32,status:Result<&2,&2,String,List<&2,U32>>) -> Result<&2,&2,String,CookingBindings.Catalog>:
  match status:
    case Fail{message}: Fail{message}
    case Done{bytes}: CookingBindingsLoad.parse(identity,count,65536n,bytes)

def cooking_actual(catalogs:Catalogs,first_peer:U32,bodies:List<&2,CookingStorage.Body>,terrain:Terrain,state:Session.State) -> IO(Session.Ready):
  Terrain{+count,enabled,budget} = terrain
  Session.State{player,Session.Shell{+identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking}} = state
  state : Session.State = Session.State{player,Session.Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation,cooking}}
  do IO<Session.Ready>:
    light:Result<&2,&2,LightLoad.Error,LightRegistry.Catalog> <- LightLoad.load(identity,count,1048576n,"reference/block_light_registry.tsv")
    bytes:Result<&2,&2,String,List<&2,U32>> <- startup_read("reference/cooking_world_bindings.tsv",65536n)
    cooking_configured(first_peer,bodies,budget,state,cooking_context(catalogs,enabled,light,cooking_bindings(identity,count,bytes)))

def cooking_terrain(catalogs:Catalogs,first_peer:U32,bodies:List<&2,CookingStorage.Body>,result:Session.State & Result<&2,&2,String,Terrain>) -> IO(Session.Ready):
  (state,status) = result
  match status:
    case Fail{message}: cooking_failed(state,message)
    case Done{observed}: cooking_actual(catalogs,first_peer,bodies,observed,state)

# One bootstrap unit per acquisition/cell/release and one discovery unit per
# loaded section. The budget scales with the actual terrain; it is not a world
# size limit. All physical saved bodies are admitted before ticks/listeners.
def cooking_initialized(catalogs:Catalogs,bodies:List<&2,CookingStorage.Body>,ready:Session.Ready) -> IO(Session.Ready):
  Session.Ready{state,first_peer} = ready
  cooking_terrain(catalogs,first_peer,bodies,terrain(state))

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

def fixture_loaded(+options:CLI.Options,config:Config,tables:Motion.Tables,catalogs:Catalogs) -> IO(Unit):
  do IO<Unit>:
    stored : Persistence.Ready<Record.Record> <- Persistence.load_with(~Record.Record,~Storage.codec(),~Session.operations(),Storage.limits())
    ready : Session.Ready <- Session.new(stored,tables)
    initialized : Session.Ready <- Scene.initialize(ready)
    cooking : Session.Ready <- cooking_initialized(catalogs,[],initialized)
    started(options,config,Scene.run_requested(cooking,CLI.running(options)))

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

def profile_adopted(+options:CLI.Options,config:Config,settings:Generation.Settings,context:CraftingSession.Context,catalogs:Catalogs,adopted:Session.Ready & List<&2,CookingStorage.Body>) -> IO(Unit):
  (ready,bodies) = adopted
  do IO<Unit>:
    initialized : Session.Ready <- Scene.initialize_generated(ready,settings)
    cooking : Session.Ready <- cooking_initialized(catalogs,bodies,initialized)
    crafting_started(options,config,context,Scene.run_requested(cooking,CLI.running(options)))

def profile_loaded(codec:Persistence.Codec<CookingStorage.Saved>,options:CLI.Options,config:Config,tables:Motion.Tables,settings:Generation.Settings,context:CraftingSession.Context,catalogs:Catalogs) -> IO(Unit):
  do IO<Unit>:
    stored : Persistence.Ready<CookingStorage.Saved> <- Persistence.load_codec(~CookingStorage.Saved,~Session.cooking_inventory_operations(),codec,CookingStorage.limits())
    adopted : Session.Ready & List<&2,CookingStorage.Body> <- Session.new_cooking_inventory(stored,tables)
    profile_adopted(options,config,settings,context,catalogs,adopted)

def profile_definitions(+options:CLI.Options,config:Config,tables:Motion.Tables,+definitions:ItemDefinitions.Catalog,context:CraftingSession.Context,catalogs:Catalogs) -> IO(Unit):
  CLI.Options{fixture,profile,creative,run,control,sine} = options
  +settings = Generation.stone_dirt(NBT.Word64{0,0})
  profile_loaded(CookingStorage.codec_with(definitions,creative,settings),options,config,tables,settings,context,catalogs)

def crafting_mode_defaults(value:Maybe<&2,ItemComponents.Defaults>) -> IO(CraftingComponents.Mode):
  match value:
    case None{}: IO.die(CraftingComponents.Mode,1,"initialized suspicious stew component defaults are unavailable")
    case Some{defaults}: IO.pure(CraftingComponents.Mode,CraftingComponents.TypedStew{defaults})

def crafting_mode(definitions:ItemDefinitions.Catalog) -> IO(CraftingComponents.Mode):
  crafting_mode_defaults(ItemDefinitions.component_defaults(definitions,"minecraft:suspicious_stew"))

def catalogs_ready(+options:CLI.Options,config:Config,tables:Motion.Tables,result:Result<&2,&2,String,Catalogs>) -> IO(Unit):
  match options result:
    case _ Fail{message}: IO.die(Unit,1,"recipe/cooking startup: " ++ message)
    case CLI.Options{True{},profile,creative,run,control,sine} Done{catalogs}: fixture_loaded(options,config,tables,catalogs)
    case CLI.Options{False{},profile,creative,run,control,sine} Done{+catalogs}:
      Catalogs{+definitions,crafting,cooking,defaults,features,fuel} = catalogs
      do IO<Unit>:
        mode:CraftingComponents.Mode <- crafting_mode(definitions)
        profile_definitions(options,config,tables,definitions,CraftingSession.new_with_components(crafting,mode),catalogs)

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

def catalog_definitions(jar:String,facts:CraftingStartup.Facts,status:Result<&2,&2,String,ItemDefinitions.Catalog>) -> IO(Result<&2,&2,String,Catalogs>):
  match facts status:
    case _ Fail{message}: IO.pure(Result<&2,&2,String,Catalogs>,Fail{message})
    case CraftingStartup.Facts{metadata,ids} Done{definitions}:
      startup_catalogs(jar,metadata,definitions,ids,CraftingLoad.defaults())

def catalog_facts(jar:String,status:Result<&2,&2,String,CraftingStartup.Facts>) -> IO(Result<&2,&2,String,Catalogs>):
  match status:
    case Fail{message}: IO.pure(Result<&2,&2,String,Catalogs>,Fail{message})
    case Done{facts}:
      do IO<Result<&2,&2,String,Catalogs>>:
        definitions:Result<&2,&2,String,ItemDefinitions.Catalog> <- ItemCatalog.load("generated/reference_item_metadata.tsv")
        catalog_definitions(jar,facts,definitions)

def decoded_facts(status:Result<&2,&2,String,List<&2,U32>>) -> Result<&2,&2,String,CraftingStartup.Facts>:
  match status:
    case Fail{message}: Fail{message}
    case Done{bytes}: CraftingStartup.decoded(Done{bytes})

# Authenticated initialized registry facts and ordered IDs feed both recipe
# decoders. Recipe and cooking provider JSON share the same actual JAR owner.
def selected_world(options:CLI.Options,config:Config,tables:Motion.Tables) -> IO(Unit):
  do IO<Unit>:
    selected:Result<&1,&1,U32 & String,String> <- IO.get_env("MC_GAME_JAR")
    jar:String <- game_jar_selected(selected)
    bytes:Result<&2,&2,String,List<&2,U32>> <- startup_read("generated/reference_crafting_authority_metadata.json",8388608n)
    catalogs:Result<&2,&2,String,Catalogs> <- catalog_facts(jar,decoded_facts(bytes))
    catalogs_ready(options,config,tables,catalogs)

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
