import Base
import ./src/remote_resource_presenter.bend as Presenter
import ./src/generic_resource_world_sample_client.bend as GenericClient
import ./src/generic_resource_world_sample.bend as GS
import ./src/generic_resource_world_sample_presenter.bend as Draw
import ./src/resource_catalog_world.bend as CW
import ./src/resource_block_catalog.bend as Catalog
import ./src/resource_block_catalog_profile.bend as Profile
import ./src/registry.bend as Registry
import ./src/resource_client_wire.bend as Wire
import ./src/resource_frame.bend as RF
import ./src/player_presentation.bend as Presentation
import ./src/player_client_options.bend as O

# The backend owns the saved world and LocalPlayer. This entry connects to its
# private catalog-frame/input capability and owns real generic resources/presentation.
# The checked static profile is useful coverage, not all Minecraft renderers.
# Unknown/unloaded state IDs and unavailable tints return explicit diagnostics.
def valid_options(options:O.Options,valid:Bool) -> IO(O.Options):
  match valid:
    case False{}: IO.die(O.Options,1,"presentation requires dimensions 4..4096, render-scale 25..100 and hud-scale 0 (auto)..4")
    case True{}: IO.pure(O.Options,options)

def checked_options(result:Result<&2,&2,String,O.Options>) -> IO(O.Options):
  match result:
    case Fail{message}: IO.die(O.Options,1,message)
    case Done{O.Options{frames,jar,+settings,item_table}}: valid_options(O.Options{frames,jar,settings,item_table},Presentation.valid_requested(settings))

def cli(args:List<String>) -> IO(O.Options):
  match args:
    case Nil{}: IO.die(O.Options,1,"missing argv")
    case name <> rest: checked_options(O.parse(rest,O.defaults()))

def human(mode:Result<&1,&1,U32 & String,String>) -> Bool:
  match mode:
    case Done{"hidden"}: False{}
    case _: True{}

def failed(link:Presenter.Link,message:String) -> IO(Unit):
  do IO<Unit>:
    Presenter.release_close(link)
    IO.die(Unit,1,message)

def open_mode(options:O.Options,link:Presenter.Link,sample:GS.Sample,assets:CW.Assets,interactive:Bool) -> IO(Unit):
  O.Options{frames,jar,settings,item_table} = options
  match interactive:
    case True{}: GenericClient.open_item_table(assets,link,sample,True{},frames,Presentation.resolve(settings,True{}),item_table)
    case False{}: GenericClient.open_item_table(assets,link,sample,False{},frames,Presentation.resolve(settings,False{}),item_table)

def assets_ready(options:O.Options,link:Presenter.Link,sample:GS.Sample,result:Result<&2,&1,String,CW.Assets>) -> IO(Unit):
  O.Options{frames,jar,settings,item_table} = options
  match result:
    case Fail{message}: failed(link,"resource scene: " ++ message)
    case Done{assets}:
      do IO<Unit>:
        mode : Result<&1,&1,U32 & String,String> <- IO.get_env("BEND_MINECRAFT_LAUNCH_MODE")
        open_mode(O.Options{frames,jar,settings,item_table},link,sample,assets,human(mode))

def catalog_loaded(options:O.Options,link:Presenter.Link,sample:GS.Sample,
    value:Registry.Registry & Result<&2,&1,Catalog.Error,CW.Assets>) -> IO(Unit):
  (registry,status) = value
  match status:
    case Fail{error}: failed(link,"resource catalog: " ++ Draw.error_text(error))
    case Done{assets}: assets_ready(options,link,sample,Done{assets})

def registry_loaded(+options:O.Options,link:Presenter.Link,sample:GS.Sample,
    value:Result<&2,&1,Registry.Error,Registry.Registry>) -> IO(Unit):
  O.Options{frames,jar,settings,item_table} = options
  match value:
    case Fail{error}: failed(link,"registry: " ++ Registry.error_text(error))
    case Done{registry}:
      do IO<Unit>:
        loaded:Registry.Registry & Result<&2,&1,Catalog.Error,CW.Assets> <-
          RF.catalog_load(jar,registry,Profile.static_requests(),Profile.static_policy(),Catalog.defaults())
        catalog_loaded(options,link,sample,loaded)

def registry_path(value:Result<&1,&1,U32 & String,String>) -> String:
  match value:
    case Done{path}: path
    case Fail{error}: "generated/reference_blocks.tsv"

def load_frame(+options:O.Options,link:Presenter.Link,sample:GS.Sample) -> IO(Unit):
  do IO<Unit>:
    configured:Result<&1,&1,U32 & String,String> <- IO.get_env("BEND_MINECRAFT_REGISTRY")
    registry:Result<&2,&1,Registry.Error,Registry.Registry> <- Registry.Registry.load(registry_path(configured))
    registry_loaded(options,link,sample,registry)

def initial_frame(options:O.Options,result:Presenter.Link & Result<&2,&2,String,Wire.Reply>) -> IO(Unit):
  (link,status) = result
  match status:
    case Fail{message}: failed(link,"frame query: " ++ message)
    case Done{Wire.CatalogFrameReply{epoch,sequence,sample}}: load_frame(options,link,sample)
    case Done{other}: failed(link,"frame query: Wire:ExpectedFrame")

def connected(options:O.Options,result:Presenter.Link & Result<&2,&2,String,Wire.Reply>) -> IO(Unit):
  (link,status) = result
  match status:
    case Fail{message}: failed(link,message)
    case Done{Wire.HelloAck{epoch,zero}}:
      do IO<Unit>:
        reply : Presenter.Link & Result<&2,&2,String,Wire.Reply> <- Presenter.call(link,Wire.FrameCatalog{128,128})
        initial_frame(options,reply)
    case Done{other}: failed(link,"Wire:ExpectedHello")

def connect_valid(options:O.Options,value:U32,capability:String,valid:Bool) -> IO(Unit):
  match valid:
    case False{}: IO.die(Unit,1,"invalid MC_RENDER_PORT")
    case True{}:
      do IO<Unit>:
        result : Presenter.Link & Result<&2,&2,String,Wire.Reply> <- Presenter.connect(value,capability)
        connected(options,result)

def connect_options(options:O.Options,port:Maybe<&2,U32>,capability:String) -> IO(Unit):
  match port:
    case Some{+value}: connect_valid(options,value,capability,U32.is_ge(value,1) && U32.is_le(value,65535))
    case None{}: IO.die(Unit,1,"invalid MC_RENDER_PORT")

def configured(options:O.Options,port:Result<&1,&1,U32 & String,String>,capability:Result<&1,&1,U32 & String,String>) -> IO(Unit):
  match port capability:
    case Done{value} Done{token}: connect_options(options,U32.read(value),token)
    case _ _: IO.die(Unit,1,"MC_RENDER_PORT and MC_RENDER_TOKEN are required")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    options : O.Options <- cli(args)
    port : Result<&1,&1,U32 & String,String> <- IO.get_env("MC_RENDER_PORT")
    capability : Result<&1,&1,U32 & String,String> <- IO.get_env("MC_RENDER_TOKEN")
    configured(options,port,capability)
