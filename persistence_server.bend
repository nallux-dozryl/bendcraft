import Base
import ./src/server.bend as Server
import ./src/persistence.bend as P

# Registry identity and the entire configured snapshot are checked before listen.
def run(ready: P.Ready) -> IO(Unit):
  P.Ready{state, first_peer} = ready
  Server.run_effectful_from_peer(~P.State, ~Server.EffectfulDriver{P.realtime_step, P.dispatch}, state, first_peer)

def main() -> IO(Unit):
  do IO<Unit>:
    ready : P.Ready <- P.load()
    run(ready)
