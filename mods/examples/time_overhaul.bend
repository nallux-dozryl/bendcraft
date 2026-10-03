import Base
import ../../src/core.bend as C
import ../../src/game.bend as G
import ../../src/framing.bend as F
import ../../src/json.bend as J
import ../../src/live.bend as L
import ../../src/mods.bend as M
import ../../src/registry.bend as R
import ../../src/server.bend as S

# This mod owns additional simulation state and replaces realtime transitions.
# The standard server transport is specialized to State at compile time.
type State is Type:
  State{engine: G.Engine, ticks_per_pulse: U32, pulses: Nat}

type Operation is Data:
  Operation{name: String, fields: List<&2, L.Field>, description: String}

def new(engine: G.Engine) -> State:
  State{engine, 1, 0n}

def pack(rate: U32, pulses: Nat, result: G.Engine & L.Session & J.Value) -> State & L.Session & J.Value:
  (engine, session, response) = result
  (State{engine, rate, pulses}, session, response)

def pulse_paused(paused: Bool, world: C.World, registry: R.Registry, +rate: U32, pulses: Nat) -> State:
  match paused:
    case True{}: State{G.Engine{world, registry}, rate, pulses}
    case False{}: State{G.Engine{C.advance(U32.to_nat(rate), world), registry}, rate, pulses}

def pulse_clock(result: C.World & C.Clock, registry: R.Registry, rate: U32, pulses: Nat) -> State:
  (world, clock) = result
  C.Clock{tick, time, paused, daylight, revision, pending} = clock
  pulse_paused(paused, world, registry, rate, pulses)

def step(state: State) -> State:
  State{engine, rate, pulses} = state
  G.Engine{world, registry} = engine
  pulse_clock(C.clock(world), registry, rate, 1n+pulses)

def operations() -> List<&2, Operation>:
  [Operation{"mod.time_overhaul.status", [], "Report this mod's owned pulse counter and ticks-per-pulse setting."},
   Operation{"mod.time_overhaul.configure", [L.Field{"ticks_per_pulse", L.Unsigned{1, 10}, True{}}], "Replace realtime tick rate with one through ten simulation ticks per 50ms pulse; explicit stepping remains exact."}]

def operation_value(operation: Operation) -> J.Value:
  Operation{+name, fields, description} = operation
  L.obj([J.JMember{"name", L.text(name)}, J.JMember{"phase", L.text("mod-control")}, J.JMember{"permitted_mode", L.text("developer")},
    J.JMember{"version", L.text("26.3")}, J.JMember{"status", L.text("implemented-mod-example")}, J.JMember{"scheduled", L.boolean(False{})},
    J.JMember{"description", L.text(description)}, J.JMember{"input_schema", L.request_schema(name, fields, False{})}])

def operation_values(ops: List<&2, Operation>) -> List<&2, J.Value>:
  match ops:
    case Nil{}: []
    case head <> tail: operation_value(head) <> operation_values(tail)

def discover_members(members: List<&2, J.Member>) -> List<&2, J.Member>:
  match members:
    case Nil{}: []
    case J.JMember{"operations", J.JArray{values}} <> tail:
      J.JMember{"operations", J.JArray{List.append(&2, J.Value, values, operation_values(operations()))}} <> discover_members(tail)
    case head <> tail: head <> discover_members(tail)

def discover_value(value: J.Value) -> J.Value:
  match value:
    case J.JObject{members}: L.obj(discover_members(members))
    case other: other

def lookup(ops: List<&2, Operation>, +name: String) -> Maybe<&2, Operation>:
  match ops:
    case Nil{}: None{}
    case +head <> tail:
      Operation{actual, fields, description} = head
      J.choose(Maybe<&2, Operation>, Some{head}, lookup(tail, name), String.eq(actual, name))

def status(rate: U32, pulses: Nat) -> J.Value:
  L.obj([J.JMember{"mod", L.text("bendex:time_overhaul")}, J.JMember{"ticks_per_pulse", L.uint(rate)}, J.JMember{"pulses", L.natural(pulses)},
    J.JMember{"tick_interval_ms", L.uint(50)}, J.JMember{"state_owner", L.text("typed-complete-driver")}, J.JMember{"restart_persistence", L.boolean(False{})}])

def configured(result: Result<&2, &2, L.Fault, U32>, engine: G.Engine, old_rate: U32, +pulses: Nat, session: L.Session, id: String) -> State & L.Session & J.Value:
  match result:
    case Fail{fault}: pack(old_rate, pulses, G.failure(engine, session, id, fault))
    case Done{+rate}: pack(rate, pulses, G.success(engine, session, id, status(rate, pulses)))

def execute(name: String, state: State, session: L.Session, id: String, args: J.Value) -> State & L.Session & J.Value:
  match name state:
    case "mod.time_overhaul.configure" State{engine, rate, pulses}: configured(L.get_number(args, "ticks_per_pulse", False{}), engine, rate, pulses, session, id)
    case _ State{engine, +rate, +pulses}: pack(rate, pulses, G.success(engine, session, id, status(rate, pulses)))

def checked(valid: Bool, allowed: Bool, name: String, state: State, session: L.Session, id: String, args: J.Value) -> State & L.Session & J.Value:
  match valid allowed:
    case False{} _:
      State{engine, rate, pulses} = state
      pack(rate, pulses, G.failure(engine, session, id, L.bad("InvalidArguments", "mod arguments do not match the operation schema")))
    case True{} False{}:
      State{engine, rate, pulses} = state
      pack(rate, pulses, G.failure(engine, session, id, L.bad("PermissionDenied", "developer capability required")))
    case True{} True{}: execute(name, state, session, id, args)

def custom_operation(operation: Operation, state: State, +session: L.Session, id: String, +args: J.Value, at: Maybe<&2, Nat>) -> State & L.Session & J.Value:
  Operation{name, fields, description} = operation
  checked(L.validate_args(args, fields) && Maybe.is_none(&2, Nat, at), C.developer(L.capability(session)), name, state, session, id, args)

def discovered(valid: Bool, state: State, session: L.Session, id: String) -> State & L.Session & J.Value:
  match valid state:
    case False{} State{engine, rate, pulses}: pack(rate, pulses, G.failure(engine, session, id, L.bad("InvalidArguments", "discover requires empty args and no at")))
    case True{} State{engine, rate, pulses}: pack(rate, pulses, G.success(engine, session, id, discover_value(G.discovery())))

def custom(found: Maybe<&2, Operation>, envelope: L.Envelope, state: State, session: L.Session, token: String, request: J.Value) -> State & L.Session & J.Value:
  match found:
    case Some{operation}:
      L.Envelope{id, op, args, at} = envelope
      L.Session{peer, sequence, cap} = session
      custom_operation(operation, state, L.Session{peer, 1n+sequence, cap}, id, args, at)
    case None{}:
      State{engine, rate, pulses} = state
      pack(rate, pulses, G.dispatch(engine, session, token, request))

def parsed_envelope(envelope: L.Envelope, state: State, session: L.Session, token: String, request: J.Value) -> State & L.Session & J.Value:
  match envelope:
    case L.Envelope{id, "discover", args, at}:
      L.Session{peer, sequence, cap} = session
      discovered(L.validate_args(args, []) && Maybe.is_none(&2, Nat, at), state, L.Session{peer, 1n+sequence, cap}, id)
    case L.Envelope{id, +name, args, at}:
      custom(lookup(operations(), name), L.Envelope{id, name, args, at}, state, session, token, request)

def parsed(parsed: Result<&2, &2, L.Fault, L.Envelope>, state: State, session: L.Session, token: String, request: J.Value) -> State & L.Session & J.Value:
  match parsed:
    case Fail{fault}:
      State{engine, rate, pulses} = state
      pack(rate, pulses, G.dispatch(engine, session, token, request))
    case Done{envelope}: parsed_envelope(envelope, state, session, token, request)

def dispatch_inner(state: State, session: L.Session, token: String, +request: J.Value) -> State & L.Session & J.Value:
  parsed(L.envelope(request), state, session, token, request)

def dispatch(state: State, session: L.Session, token: String, request: J.Value) -> State & L.Session & J.Value:
  dispatch_inner(state, session, token, request)

# Startup checks the runtime metadata against this compile-time linked driver.
# It loads no code and cannot change the State type or installed handlers.
def startup_catalog_names(ops: List<&2, Operation>) -> List<&2, String>:
  match ops:
    case Nil{}: []
    case Operation{name, fields, description} <> tail: name <> startup_catalog_names(tail)

def startup_contract(manifest: M.Manifest) -> Result<&2, &2, String, Unit>:
  M.Manifest{id, version, api, side, dependencies, before, after, +ops, +queries, events, data, reload} = manifest
  do Result<&2, &2, String, Unit>:
    M.require(String.eq(id, "bendex:time_overhaul"), "CompiledIdentityMismatch: expected bendex:time_overhaul")
    M.require(M.version_eq(version, M.Version{1, 0, 0}), "CompiledVersionMismatch: expected 1.0.0")
    M.require(M.version_eq(api, M.Version{1, 0, 0}), "CompiledAPIMismatch: expected 1.0.0")
    M.require(M.side_eq(side, M.Server{}), "CompiledSideMismatch: expected server")
    M.require(M.names_same(ops, ["mod.time_overhaul.configure"]), "CompiledOperationsMismatch: expected mod.time_overhaul.configure")
    M.require(M.names_same(queries, ["mod.time_overhaul.status"]), "CompiledQueriesMismatch: expected mod.time_overhaul.status")
    M.require(M.names_same(List.append(&2, String, ops, queries), startup_catalog_names(operations())), "CompiledCatalogMismatch: manifest callables differ from installed catalog")
    M.require(M.names_same(events, []), "CompiledEventsMismatch: this driver declares no events")
    M.require(U32.is_eq(data, 0), "CompiledDataVersionMismatch: expected 0")
    M.require(M.reload_same(reload, M.Restart{}), "CompiledReloadMismatch: this driver requires restart")
    M.require(List.is_empty(&2, M.Dependency, dependencies) && List.is_empty(&2, String, before) && List.is_empty(&2, String, after), "CompiledRequirementsMismatch: this driver links no mod dependencies or ordering requirements")

def startup_resolve(+manifest: M.Manifest) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    ordered : List<&2, M.Manifest> <- M.resolve(M.Server{}, M.Version{1, 0, 0}, [manifest])
    startup_contract(manifest)

def startup_decoded(result: Result<&2, &2, String, M.Manifest>) -> Result<&2, &2, String, Unit>:
  match result:
    case Fail{message}: Fail{message}
    case Done{manifest}: startup_resolve(manifest)

def startup_parsed(result: Result<&2, &2, String, J.Value>) -> Result<&2, &2, String, Unit>:
  match result:
    case Fail{message}: Fail{"ManifestJSON: " ++ message}
    case Done{value}: startup_decoded(M.decode(value))

def startup_utf8(result: Result<&2, &2, String, String>) -> Result<&2, &2, String, Unit>:
  match result:
    case Fail{message}: Fail{"ManifestUTF8: " ++ message}
    case Done{text}: startup_parsed(J.parse(text))

def startup_checked(result: Result<&2, &2, String, Unit>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit, 2, "mod manifest startup: " ++ message)
    case Done{unit}: IO.pure(Unit, unit)

def startup_finish(result: Result<&2, &2, String, List<&2, U32>>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit, 2, "mod manifest startup: " ++ message)
    case Done{bytes}: startup_checked(startup_utf8(F.decode_loop(bytes, Done{F.Utf8{0, 0, 0, "", 0}})))

def startup_read_tail(bytes: List<&2, U32>, read: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Result<&2, &2, String, List<&2, U32>>):
  (file, result) = read
  match result:
    case Fail{(code, message)}:
      do IO<Result<&2, &2, String, List<&2, U32>>>:
        File.close(file)
        return Fail{"ManifestReadError: " ++ message}
    case Done{Nil{}}:
      do IO<Result<&2, &2, String, List<&2, U32>>>:
        File.close(file)
        return Done{bytes}
    case Done{_}:
      do IO<Result<&2, &2, String, List<&2, U32>>>:
        File.close(file)
        return Fail{"ManifestSize: file exceeds 65536 bytes"}

def startup_read_body(read: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Result<&2, &2, String, List<&2, U32>>):
  (file, result) = read
  match result:
    case Fail{(code, message)}:
      do IO<Result<&2, &2, String, List<&2, U32>>>:
        File.close(file)
        return Fail{"ManifestReadError: " ++ message}
    case Done{bytes}:
      do IO<Result<&2, &2, String, List<&2, U32>>>:
        next : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, 1)
        startup_read_tail(bytes, next)

def startup_read_open(opened: Result<&1, &1, U32 & String, File>) -> IO(Result<&2, &2, String, List<&2, U32>>):
  match opened:
    case Fail{(code, message)}: IO.pure(Result<&2, &2, String, List<&2, U32>>, Fail{"ManifestReadError: " ++ message})
    case Done{file}:
      do IO<Result<&2, &2, String, List<&2, U32>>>:
        read : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, 65536)
        startup_read_body(read)

def startup_path(result: Result<&1, &1, U32 & String, String>) -> String:
  match result:
    case Fail{error}: "mods/examples/time_overhaul.json"
    case Done{path}: path

def startup_manifest() -> IO(Unit):
  do IO<Unit>:
    configured : Result<&1, &1, U32 & String, String> <- IO.get_env("MC_MOD_MANIFEST")
    opened : Result<&1, &1, U32 & String, File> <- File.open(startup_path(configured), "r")
    bytes : Result<&2, &2, String, List<&2, U32>> <- startup_read_open(opened)
    startup_finish(bytes)

def main() -> IO(Unit):
  do IO<Unit>:
    startup_manifest()
    engine : G.Engine <- G.load()
    S.run(~State, ~S.Driver{step, dispatch}, new(engine))
