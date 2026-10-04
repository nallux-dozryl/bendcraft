import Base
import ./player_client.bend as Entry
import ./src/player_scene.bend as Player
import ./src/resource_player_boxed_scene.bend as Scene
import ./src/player_session.bend as Session
import ./src/player_storage.bend as Storage
import ./src/player_record.bend as Record
import ./src/extended_persistence.bend as Persistence
import ./src/locomotion.bend as Motion
import ./src/resource_player_presenter.bend as Presenter
import ./src/resource_frame.bend as Render
import ./src/world_visibility.bend as Visibility
import ./src/client_host.bend as Host
import ./src/server.bend as Server
import ./src/world_lock.bend as Lock

# This concrete presenter keeps the saved Session and actual resource/world
# pipeline. Optional CPU readbacks observe the Image returned by Window.frame.
def failed(ready:Session.Ready,message:String) -> IO(Unit):
  Session.Ready{Session.State{player,Session.Shell{identity,path,highwater,limits,lease,maximum,catalog}},peer} = ready
  do IO<Unit>:
    released : Result<&1,&1,U32 & String,Unit> <- Lock.release(lease)
    IO.die(Unit,1,message)

def start(options:Entry.Options,assets:Scene.Assets,ready:Session.Ready) -> IO(Unit):
  Entry.Options{fixture,run,frames,jar,sine} = options
  Session.Ready{state,first_peer} = ready
  do IO<Unit>:
    handle : Server.Handle<Session.State> <- Server.start_effectful_from_peer(~Session.State,~Server.EffectfulDriver{Player.realtime_step,Player.dispatch},state,first_peer)
    mode : Result<&1,&1,U32 & String,String> <- IO.get_env("BEND_MINECRAFT_LAUNCH_MODE")
    Presenter.open(assets,handle,Host.interactive(mode),frames,128,128,"Minecraft 26.3 — resource player integration scene")

def assets_ready(options:Entry.Options,ready:Session.Ready,result:Result<&2,&1,String,Render.Assets>) -> IO(Unit):
  match result:
    case Fail{message}: failed(ready,"resource scene: " ++ message)
    case Done{assets}: start(options,Scene.assets(assets),ready)

def load_assets(+options:Entry.Options,ready:Session.Ready,palette:Render.Palette) -> IO(Unit):
  Entry.Options{fixture,run,frames,jar,sine} = options
  do IO<Unit>:
    loaded : Result<&2,&1,String,Render.Assets> <- Render.load(jar,palette)
    assets_ready(options,ready,loaded)

def palette_ready(+options:Entry.Options,first_peer:U32,result:Session.State & Result<&2,&2,String,Render.Palette>) -> IO(Unit):
  (state,status) = result
  match status:
    case Fail{message}: failed(Session.Ready{state,first_peer},"resource palette: " ++ message)
    case Done{palette}: load_assets(options,Session.Ready{state,first_peer},palette)

def load_ready(options:Entry.Options,ready:Session.Ready) -> IO(Unit):
  Session.Ready{state,first_peer} = ready
  palette_ready(options,first_peer,Scene.resource_palette(state))

def load_options(+options:Entry.Options) -> IO(Unit):
  Entry.Options{fixture,+run,frames,jar,sine} = options
  do IO<Unit>:
    loaded_tables : Result<&2,&1,Motion.Error,Motion.Tables> <- Motion.Tables.load(sine)
    tables : Motion.Tables <- Entry.checked_tables(loaded_tables)
    stored : Persistence.Ready<Record.Record> <- Persistence.load_with(~Record.Record,~Storage.codec(),~Session.operations(),Storage.limits())
    ready : Session.Ready <- Session.new(stored,tables)
    initialized : Session.Ready <- Player.initialize(ready)
    load_ready(options,Player.run_requested(initialized,run))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    options : Entry.Options <- Entry.parse_cli(args)
    load_options(options)
