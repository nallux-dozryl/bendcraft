import Base
import ./src/server.bend as Server
import ./src/game.bend as Game

# Runtime metadata is validated before creating the world or accepting peers.
def main() -> IO(Unit):
  do IO<Unit>:
    engine : Game.Engine <- Game.load()
    Server.run(~Game.Engine, ~Server.Driver{Game.realtime_step, Game.dispatch}, engine)
