import Base
import ../src/core.bend as C
import ../src/json.bend as J
import ../src/live.bend as L
import ../src/server.bend as S

def dispatch(world: C.World, session: L.Session, token: String, request: J.Value) -> IO(C.World & L.Session & J.Value):
  S.pure_dispatch(C.World, S.Driver{C.realtime_step, S.core_dispatch}, world, session, token, request)

def main() -> IO(Unit):
  S.run_effectful_from_peer(~C.World, ~S.EffectfulDriver{C.realtime_step, dispatch}, C.new(1), 4294967295)
