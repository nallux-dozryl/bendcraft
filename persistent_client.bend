import Base
import ./client.bend as E
import ./src/client_host.bend as H
import ./src/persistent_client_world.bend as W
import ./src/persistence.bend as P
import ./src/server.bend as S
import ./src/client_render.bend as R
import ./src/archive.bend as A

def ready_world(result:W.State & Result<&2,&2,String,Unit>) -> IO(W.State):
  (state,status) = result
  match status:
    case Fail{message}: IO.die(W.State,1,message)
    case Done{unit}: IO.pure(W.State,state)

def window_start(options:E.Options,assets:R.Assets,handle:S.Handle<W.State>,human:Bool) -> IO(Unit):
  E.Options{fixture,frames,dump,jar} = options
  H.window_start(~W.State,~H.Driver{W.snapshot,W.move,W.look},assets,handle,human,frames,dump,"Minecraft 26.3 — persistent verification scene")

def start_ready(+options:E.Options,assets:R.Assets,ready:P.Ready) -> IO(Unit):
  P.Ready{simulation,first_peer} = ready
  do IO<Unit>:
    state : W.State <- ready_world(W.new(simulation,True{}))
    handle : S.Handle<W.State> <- S.start_effectful_from_peer(~W.State,~S.EffectfulDriver{W.step,W.dispatch},state,first_peer)
    mode : Result<&1,&1,U32 & String,String> <- IO.get_env("BEND_MINECRAFT_LAUNCH_MODE")
    window_start(options,assets,handle,H.interactive(mode))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    options : E.Options <- E.args_options(args)
    +options : E.Options <- E.require_fixture(options)
    loaded : Result<&2,&1,A.Error,R.Assets> <- R.load_assets(E.jar_of(options))
    assets : R.Assets <- E.ready_assets(loaded)
    ready : P.Ready <- P.load()
    start_ready(options,assets,ready)
