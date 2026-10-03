import Base
import ./src/server.bend as S
import ./src/extended_persistence.bend as E
import ./tests/extended_persistence.bend as F
import ./src/world_codec.bend as W

# Example closed composition. Production player state supplies its own hooks.
def run(ready: E.Ready<F.Extra>) -> IO(Unit):
  E.Ready{state, first_peer} = ready
  S.run_effectful_from_peer(~E.State<F.Extra>,
    ~S.EffectfulDriver{w => E.realtime_step(F.Extra, w), w => s => t => r => E.dispatch(~F.Extra, ~F.codec(), ~F.operations(), w, s, t, r)}, state, first_peer)

# Every branch names a fixed closed codec/catalog. No program is loaded from data.
def configured(mode: String) -> IO(E.Ready<F.Extra>):
  match mode:
    case "normal": E.load(~F.Extra, ~F.codec(), ~F.operations())
    case "core-init": E.load(~F.Extra, ~F.explicit_core_init_codec(), ~F.operations())
    case "reserved": E.load(~F.Extra, ~F.codec(), ~F.reserved_operations())
    case "duplicate": E.load(~F.Extra, ~F.codec(), ~F.duplicate_operations())
    case "invalid-schema": E.load(~F.Extra, ~F.codec(), ~F.invalid_operations())
    case "bad-namespace": E.load(~F.Extra, ~F.bad_namespace_codec(), ~F.operations())
    case "bad-schema": E.load(~F.Extra, ~F.bad_schema_codec(), ~F.operations())
    case "fresh-fail": E.load(~F.Extra, ~F.failed_initial_codec(), ~F.operations())
    case "small-budget": E.load_with(~F.Extra, ~F.codec(), ~F.operations(), E.Limits{W.default_limits(), 32, 4096})
    case _: IO.die(E.Ready<F.Extra>, 1, "unknown compiled MC_BUNDLE_FIXTURE choice")

def selected(result: Result<&1, &1, U32 & String, String>) -> IO(E.Ready<F.Extra>):
  match result:
    case Fail{error}: configured("normal")
    case Done{mode}: configured(mode)

def main() -> IO(Unit):
  do IO<Unit>:
    mode : Result<&1, &1, U32 & String, String> <- IO.get_env("MC_BUNDLE_FIXTURE")
    ready : E.Ready<F.Extra> <- selected(mode)
    run(ready)
