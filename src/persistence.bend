import Base
import ./game.bend as G
import ./core.bend as C
import ./registry.bend as R
import ./live.bend as L
import ./json.bend as J
import ./world_codec.bend as W
import ./nbt.bend as N
import ./atomic_file.bend as A
import ./world_lock.bend as WL

# All format/save policy is Bend. Atomic publication retains its measured OS boundary.
type Limits is Data:
  Limits{world: W.Limits, max_file_bytes: U32}

type State is Type:
  State{engine: G.Engine, registry_identity: String, path: String, highwater: U32, limits: Limits, lease: WL.Lease}

type Ready is Type:
  Ready{state: State, first_peer: U32}

type Saved is Type:
  Saved{world: C.World, highwater: U32}

def default_limits() -> Limits:
  Limits{W.default_limits(), 16781312}

def world_limits(+limits: Limits) -> W.Limits:
  Limits{world, bytes} = limits
  world

def file_limit(+limits: Limits) -> U32:
  Limits{world, bytes} = limits
  bytes

def nbt_byte_limit(limits: N.Limits) -> U32:
  N.Limits{bytes, depth, elements} = limits
  bytes

def envelope_limits(+limits: Limits) -> N.Limits:
  Limits{world, +bytes} = limits
  N.Limits{bytes, 4, U32.min(bytes, nbt_byte_limit(W.nbt_limits(world)))}

def next_peer(+highwater: U32) -> Result<&2, &2, String, U32>:
  match highwater:
    case 4294967295: Fail{"persisted peer identity range exhausted"}
    case actual: Done{U32.inc(actual)}

def effective_highwater(+highwater: U32, max_peer: Maybe<&2, U32>) -> U32:
  match max_peer:
    case None{}: highwater
    case Some{peer}: U32.max(highwater, peer)

def envelope_root(+identity: String, +highwater: U32, bytes: List<&2, U32>) -> N.Root:
  N.Root{W.text("bendex:save"), N.Compound{[
    W.named("format", N.Int{1}), W.named("minecraft", W.string_tag("26.3")),
    W.named("registry", W.string_tag(identity)), W.named("peer_highwater", N.Int{highwater}),
    W.named("world", N.ByteArray{bytes})]}}

def envelope_encode(+limits: Limits, +identity: String, +highwater: U32, bytes: List<&2, U32>) -> Result<&2, &2, String, List<&2, U32>>:
  N.encode_with(envelope_limits(limits), envelope_root(identity, highwater, bytes))

def saved_world(+highwater: U32, result: Result<&2, &1, String, W.Loaded>) -> Result<&2, &1, String, Saved>:
  match result:
    case Fail{message}: Fail{message}
    case Done{W.Loaded{world, max_peer}}: Done{Saved{world, effective_highwater(highwater, max_peer)}}

def envelope_world(+limits: Limits, value: N.Value, +count: U32, +identity: String, +highwater: U32) -> Result<&2, &1, String, Saved>:
  match value:
    case N.ByteArray{bytes}: saved_world(highwater, W.decode_with(world_limits(limits), bytes, count, identity))
    case _: Fail{"save world payload requires ByteArray"}

def envelope_metadata_check(+limits: Limits, +identity: String, +fs: List<&2, W.Field>) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    format : U32 <- W.int_value(W.field(fs, "format"))
    W.require(U32.is_eq(format, 1), "unsupported save envelope format")
    minecraft : String <- W.string_value(world_limits(limits), W.field(fs, "minecraft"))
    W.require(String.eq(minecraft, "26.3"), "save envelope Minecraft version mismatch")
    registry : String <- W.string_value(world_limits(limits), W.field(fs, "registry"))
    W.require(String.eq(registry, identity), "save envelope registry identity mismatch")
    W.int_value(W.field(fs, "peer_highwater"))

def envelope_metadata(+limits: Limits, +count: U32, +identity: String, fs: List<&2, W.Field>, checked: Result<&2, &2, String, U32>) -> Result<&2, &1, String, Saved>:
  match checked:
    case Fail{message}: Fail{message}
    case Done{highwater}: envelope_world(limits, W.field(fs, "world"), count, identity, highwater)

def realtime_step(state: State) -> State:
  State{engine, identity, path, highwater, limits, lease} = state
  State{G.realtime_step(engine), identity, path, highwater, limits, lease}

def observe(state: State, +peer: U32) -> State:
  State{engine, identity, path, highwater, limits, lease} = state
  State{engine, identity, path, U32.max(highwater, peer), limits, lease}

def pack(+identity: String, +path: String, +highwater: U32, +limits: Limits, lease: WL.Lease, result: G.Engine & L.Session & J.Value) -> State & L.Session & J.Value:
  (engine, session, value) = result
  (State{engine, identity, path, highwater, limits, lease}, session, value)

def success(state: State, +session: L.Session, +id: String, value: J.Value) -> State & L.Session & J.Value:
  State{engine, identity, path, highwater, limits, lease} = state
  pack(identity, path, highwater, limits, lease, G.success(engine, session, id, value))

def failure(state: State, +session: L.Session, +id: String, +code: String, +message: String) -> State & L.Session & J.Value:
  State{engine, identity, path, highwater, limits, lease} = state
  pack(identity, path, highwater, limits, lease, G.failure(engine, session, id, L.bad(code, message)))

def publication_value(outcome: A.Outcome, +bytes: U32, +highwater: U32) -> J.Value:
  match outcome:
    case A.Durable{}:
      L.obj([J.JMember{"status", L.text("durable")}, J.JMember{"published", L.boolean(True{})}, J.JMember{"durable", L.boolean(True{})}, J.JMember{"bytes", L.uint(bytes)}, J.JMember{"peer_highwater", L.uint(highwater)}])
    case A.PublishedUnsynced{code, message}:
      L.obj([J.JMember{"status", L.text("published_unsynced")}, J.JMember{"published", L.boolean(True{})}, J.JMember{"durable", L.boolean(False{})}, J.JMember{"code", L.uint(code)}, J.JMember{"message", L.text(message)}, J.JMember{"bytes", L.uint(bytes)}, J.JMember{"peer_highwater", L.uint(highwater)}])
    case A.NotPublished{code, message}:
      L.obj([J.JMember{"status", L.text("not_published")}, J.JMember{"published", L.boolean(False{})}, J.JMember{"durable", L.boolean(False{})}, J.JMember{"code", L.uint(code)}, J.JMember{"message", L.text(message)}])

def published(state: State, +session: L.Session, +id: String, +bytes: U32, +highwater: U32, outcome: A.Outcome) -> State & L.Session & J.Value:
  match outcome:
    case A.NotPublished{code, message}: failure(state, session, id, "SaveNotPublished", U32.show(code) ++ ": " ++ message)
    case other: success(state, session, id, publication_value(other, bytes, highwater))

def world_count_valid(+valid: Bool, limits: W.Limits, world: C.World, +identity: String) -> C.World & Result<&2, &2, String, List<&2, U32>>:
  match valid:
    case False{}: (world, Fail{"world state count differs from loaded registry"})
    case True{}: W.encode_with(limits, world, identity)

def encode_world(limits: W.Limits, world: C.World, +identity: String, +registry_count: U32) -> C.World & Result<&2, &2, String, List<&2, U32>>:
  C.World{tick, time, paused, daylight, revision, +count, sections, pending, events} = world
  world_count_valid(U32.is_eq(count, registry_count), limits, C.World{tick, time, paused, daylight, revision, count, sections, pending, events}, identity)

def engine_encoded(registry: R.Registry, result: C.World & Result<&2, &2, String, List<&2, U32>>) -> G.Engine & Result<&2, &2, String, List<&2, U32>>:
  (world, encoded) = result
  (G.Engine{world, registry}, encoded)

def encode_registry(limits: W.Limits, +identity: String, world: C.World, registry: R.Registry) -> G.Engine & Result<&2, &2, String, List<&2, U32>>:
  R.Registry{blocks, names, count, +states} = registry
  engine_encoded(R.Registry{blocks, names, count, states}, encode_world(limits, world, identity, states))

def encode_engine(limits: W.Limits, +identity: String, engine: G.Engine) -> G.Engine & Result<&2, &2, String, List<&2, U32>>:
  G.Engine{world, registry} = engine
  encode_registry(limits, identity, world, registry)

def save_publish(state: State, +session: L.Session, +id: String, +bytes: List<&2, U32>) -> IO(State & L.Session & J.Value):
  State{engine, identity, +path, +highwater, limits, lease} = state
  do IO<State & L.Session & J.Value>:
    outcome : A.Outcome <- A.publish(path, "save-" ++ U32.show(L.peer(session)) ++ "-" ++ Nat.show(L.sequence(session)), bytes)
    return published(State{engine, identity, path, highwater, limits, lease}, session, id, U32.from_nat(List.length(&2, U32, bytes)), highwater, outcome)

def save_descriptor() -> J.Value:
  L.obj([J.JMember{"name", L.text("world.save")}, J.JMember{"phase", L.text("persistence")}, J.JMember{"permitted_mode", L.text("developer")},
    J.JMember{"version", L.text("26.3")}, J.JMember{"status", L.text("implemented-foundation")}, J.JMember{"scheduled", L.boolean(False{})},
    J.JMember{"description", L.text("Publish the complete foundation snapshot to the configured path; report publication and durability separately.")},
    J.JMember{"input_schema", L.request_schema("world.save", [], False{})}])

def discover_members(members: List<&2, J.Member>) -> List<&2, J.Member>:
  match members:
    case Nil{}: []
    case J.JMember{"operations", J.JArray{values}} <> rest:
      J.JMember{"operations", J.JArray{List.append(&2, J.Value, values, [save_descriptor()])}} <> discover_members(rest)
    case h <> rest: h <> discover_members(rest)

def discovery_value(value: J.Value) -> J.Value:
  match value:
    case J.JObject{members}: J.JObject{discover_members(members)}
    case other: other

def discovery() -> J.Value:
  discovery_value(G.discovery())

def delegate(state: State, +session: L.Session, +token: String, request: J.Value) -> IO(State & L.Session & J.Value):
  State{engine, identity, path, highwater, limits, lease} = state
  IO.pure(State & L.Session & J.Value, pack(identity, path, highwater, limits, lease, G.dispatch(engine, session, token, request)))

def flatten_chunks(chunks: List<&2, List<&2, U32>>) -> List<&2, U32>:
  match chunks:
    case Nil{}: []
    case h <> rest: List.append(&2, U32, h, flatten_chunks(rest))

def read_extra_status(status: Result<&1, &1, U32 & String, List<&2, U32>>, chunks: List<&2, List<&2, U32>>) -> Result<&2, &2, String, List<&2, U32>>:
  match status:
    case Fail{Tuple{code, message}}: Fail{"world file EOF check failed: " ++ U32.show(code) ++ ": " ++ message}
    case Done{Nil{}}: Done{flatten_chunks(List.reverse(&2, List<&2, U32>, chunks))}
    case Done{bytes}: Fail{"world file changed or exceeds measured length"}

def read_chunk_size(+valid: Bool, file: File, +remaining: U32, +size: U32, chunks: List<&2, List<&2, U32>>, bytes: List<&2, U32>, next: File -> U32 -> List<&2, List<&2, U32>> -> IO(Result<&2, &2, String, List<&2, U32>>)) -> IO(Result<&2, &2, String, List<&2, U32>>):
  match valid:
    case False{}:
      do IO<Result<&2, &2, String, List<&2, U32>>>:
        File.close(file)
        return Fail{"world file read exceeds remaining length"}
    case True{}: next(file, U32.sub(remaining, size), bytes <> chunks)

def read_chunk(+remaining: U32, chunks: List<&2, List<&2, U32>>, result: File & Result<&1, &1, U32 & String, List<&2, U32>>, next: File -> U32 -> List<&2, List<&2, U32>> -> IO(Result<&2, &2, String, List<&2, U32>>)) -> IO(Result<&2, &2, String, List<&2, U32>>):
  (file, status) = result
  match status:
    case Fail{Tuple{code, message}}:
      do IO<Result<&2, &2, String, List<&2, U32>>>:
        File.close(file)
        return Fail{"world file read failed: " ++ U32.show(code) ++ ": " ++ message}
    case Done{Nil{}}:
      do IO<Result<&2, &2, String, List<&2, U32>>>:
        File.close(file)
        return Fail{"world file truncated while reading"}
    case Done{+bytes}:
      +size = U32.from_nat(List.length(&2, U32, bytes))
      read_chunk_size(U32.is_le(size, remaining), file, remaining, size, chunks, bytes, next)

def ready_peer(state: State, result: Result<&2, &2, String, U32>) -> IO(Ready):
  match result:
    case Fail{message}: IO.die(Ready, 1, "world startup refused: " ++ message)
    case Done{peer}: IO.pure(Ready, Ready{state, peer})

def ready(state: State) -> IO(Ready):
  State{engine, identity, path, +highwater, limits, lease} = state
  ready_peer(State{engine, identity, path, highwater, limits, lease}, next_peer(highwater))

def loaded_state(state: State, result: Result<&2, &1, String, Saved>) -> IO(Ready):
  State{G.Engine{old_world, registry}, identity, path, highwater, limits, lease} = state
  match result:
    case Fail{message}: IO.die(Ready, 1, "world startup refused: " ++ message)
    case Done{Saved{world, next_highwater}}: ready(State{G.Engine{world, registry}, identity, path, next_highwater, limits, lease})

def state_count(state: State) -> State & U32:
  State{G.Engine{world, R.Registry{blocks, names, count, +states}}, identity, path, highwater, limits, lease} = state
  (State{G.Engine{world, R.Registry{blocks, names, count, states}}, identity, path, highwater, limits, lease}, states)

def missing_file(+allowed: Bool, state: State) -> IO(Ready):
  match allowed:
    case False{}: IO.die(Ready, 1, "world startup refused: missing file requires MC_WORLD_MISSING=create")
    case True{}: ready(state)

def policy(result: Result<&1, &1, U32 & String, String>) -> IO(Bool):
  match result:
    case Fail{error}: IO.pure(Bool, False{})
    case Done{"refuse"}: IO.pure(Bool, False{})
    case Done{"create"}: IO.pure(Bool, True{})
    case Done{other}: IO.die(Bool, 1, "MC_WORLD_MISSING must be create or refuse")

def required_path(result: Result<&1, &1, U32 & String, String>) -> IO(String):
  match result:
    case Fail{error}: IO.die(String, 1, "MC_WORLD_PATH must be explicitly configured")
    case Done{SNil{}}: IO.die(String, 1, "MC_WORLD_PATH must be nonempty")
    case Done{actual}: IO.pure(String, actual)

def envelope_fields_result(+limits: Limits, +count: U32, +identity: String, fields: Result<&2, &2, String, List<&2, W.Field>>) -> Result<&2, &1, String, Saved>:
  match fields:
    case Fail{message}: Fail{message}
    case Done{+fs}:
      envelope_metadata(limits, count, identity, fs,
        envelope_metadata_check(limits, identity, fs))

def save_envelope(state: State, +session: L.Session, +id: String, encoded: Result<&2, &2, String, List<&2, U32>>) -> IO(State & L.Session & J.Value):
  match encoded:
    case Fail{message}: IO.pure(State & L.Session & J.Value, failure(state, session, id, "SaveEncodingFailed", message))
    case Done{bytes}: save_publish(state, session, id, bytes)

def save_world_bytes(state: State, +session: L.Session, +id: String, +limits: Limits, +identity: String, +highwater: U32, encoded: Result<&2, &2, String, List<&2, U32>>) -> IO(State & L.Session & J.Value):
  match encoded:
    case Fail{message}: IO.pure(State & L.Session & J.Value, failure(state, session, id, "SaveEncodingFailed", message))
    case Done{bytes}: save_envelope(state, session, id, envelope_encode(limits, identity, highwater, bytes))

def read_extra_result(result: File & Result<&1, &1, U32 & String, List<&2, U32>>, chunks: List<&2, List<&2, U32>>) -> IO(Result<&2, &2, String, List<&2, U32>>):
  (file, status) = result
  do IO<Result<&2, &2, String, List<&2, U32>>>:
    File.close(file)
    return read_extra_status(status, chunks)

def read_extra(file: File, chunks: List<&2, List<&2, U32>>) -> IO(Result<&2, &2, String, List<&2, U32>>):
  do IO<Result<&2, &2, String, List<&2, U32>>>:
    result : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, 1)
    read_extra_result(result, chunks)

def read_loop(fuel: Nat, file: File, +remaining: U32, chunks: List<&2, List<&2, U32>>) -> IO(Result<&2, &2, String, List<&2, U32>>):
  match fuel remaining:
    case _ 0: read_extra(file, chunks)
    case 0n other:
      do IO<Result<&2, &2, String, List<&2, U32>>>:
        File.close(file)
        return Fail{"world file read work limit exceeded"}
    case 1n+n other:
      do IO<Result<&2, &2, String, List<&2, U32>>>:
        result : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, U32.min(32768, remaining))
        read_chunk(remaining, chunks, result, file => left => chunks => read_loop(n, file, left, chunks))

def envelope_fields(+limits: Limits, value: N.Value, +count: U32, +identity: String) -> Result<&2, &1, String, Saved>:
  envelope_fields_result(limits, count, identity, W.fields(world_limits(limits), value, ["format", "minecraft", "registry", "peer_highwater", "world"]))

def envelope_name_valid(+valid: Bool, +limits: Limits, value: N.Value, +count: U32, +identity: String) -> Result<&2, &1, String, Saved>:
  match valid:
    case False{}: Fail{"wrong save envelope root name"}
    case True{}: envelope_fields(limits, value, count, identity)

def save_world_result(+identity: String, +path: String, +highwater: U32, +limits: Limits, lease: WL.Lease, +session: L.Session, +id: String, encoded: G.Engine & Result<&2, &2, String, List<&2, U32>>) -> IO(State & L.Session & J.Value):
  (engine, result) = encoded
  save_world_bytes(State{engine, identity, path, highwater, limits, lease}, session, id, limits, identity, highwater, result)

def save(state: State, +session: L.Session, +id: String) -> IO(State & L.Session & J.Value):
  State{engine, +identity, path, highwater, +limits, lease} = state
  save_world_result(identity, path, highwater, limits, lease, session, id, encode_engine(world_limits(limits), identity, engine))

def local_valid(+valid: Bool, +allowed: Bool, +op: String, state: State, +session: L.Session, +id: String) -> IO(State & L.Session & J.Value):
  match valid allowed op:
    case False{} _ _: IO.pure(State & L.Session & J.Value, failure(state, session, id, "InvalidArguments", "operation requires empty arguments and no at field"))
    case True{} False{} _: IO.pure(State & L.Session & J.Value, failure(state, session, id, "PermissionDenied", "developer capability required"))
    case True{} True{} "world.save": save(state, session, id)
    case True{} True{} _: IO.pure(State & L.Session & J.Value, success(state, session, id, discovery()))

def local(+op: String, state: State, +session: L.Session, +id: String, args: J.Value, at: Maybe<&2, Nat>) -> IO(State & L.Session & J.Value):
  local_valid(L.validate_args(args, []) && Maybe.is_none(&2, Nat, at), String.eq(op, "discover") || C.developer(L.capability(session)), op, state, session, id)

def chosen(+custom: Bool, envelope: L.Envelope, state: State, +session: L.Session, +token: String, request: J.Value) -> IO(State & L.Session & J.Value):
  match custom:
    case False{}: delegate(state, session, token, request)
    case True{}:
      L.Envelope{id, op, args, at} = envelope
      L.Session{peer, sequence, capability} = session
      local(op, state, L.Session{peer, 1n+sequence, capability}, id, args, at)

def parsed(envelope: Result<&2, &2, L.Fault, L.Envelope>, state: State, +session: L.Session, +token: String, request: J.Value) -> IO(State & L.Session & J.Value):
  match envelope:
    case Fail{fault}: delegate(state, session, token, request)
    case Done{+value}:
      L.Envelope{id, +op, args, at} = value
      chosen(String.eq(op, "world.save") || String.eq(op, "discover"), value, state, session, token, request)

def dispatch_inner(state: State, +session: L.Session, +token: String, +request: J.Value) -> IO(State & L.Session & J.Value):
  parsed(L.envelope(request), observe(state, L.peer(session)), session, token, request)

# File.size rejects >U32 files. Read partial chunks with an explicit fuel bound,
# require exactly the measured size and one additional EOF probe, then close.
def dispatch(state: State, session: L.Session, token: String, request: J.Value) -> IO(State & L.Session & J.Value):
  dispatch_inner(state, session, token, request)


def envelope_named(+limits: Limits, value: N.Value, +count: U32, +identity: String, name: Result<&2, &2, String, String>) -> Result<&2, &1, String, Saved>:
  match name:
    case Fail{message}: Fail{message}
    case Done{actual}: envelope_name_valid(String.eq(actual, "bendex:save"), limits, value, count, identity)

def envelope_decoded(+limits: Limits, +count: U32, +identity: String, decoded: Result<&2, &2, String, N.Root>) -> Result<&2, &1, String, Saved>:
  match decoded:
    case Fail{message}: Fail{message}
    case Done{N.Root{name, value}}: envelope_named(limits, value, count, identity, W.read_text(world_limits(limits), name))

def envelope_decode(+limits: Limits, bytes: List<&2, U32>, +count: U32, +identity: String) -> Result<&2, &1, String, Saved>:
  envelope_decoded(limits, count, identity, N.decode_with(envelope_limits(limits), bytes))

def load_decoded(+count: U32, bytes: List<&2, U32>, state: State) -> IO(Ready):
  State{engine, +identity, path, highwater, +limits, lease} = state
  loaded_state(State{engine, identity, path, highwater, limits, lease}, envelope_decode(limits, bytes, count, identity))

def loaded_bytes_status(state: State, +count: U32, bytes: Result<&2, &2, String, List<&2, U32>>) -> IO(Ready):
  match bytes:
    case Fail{message}: IO.die(Ready, 1, "world startup refused: " ++ message)
    case Done{raw}: load_decoded(count, raw, state)

def loaded_bytes_counted(bytes: Result<&2, &2, String, List<&2, U32>>, counted: State & U32) -> IO(Ready):
  (state, count) = counted
  loaded_bytes_status(state, count, bytes)

def loaded_bytes(state: State, bytes: Result<&2, &2, String, List<&2, U32>>) -> IO(Ready):
  loaded_bytes_counted(bytes, state_count(state))

def measured_valid(+valid: Bool, state: State, file: File, +size: U32) -> IO(Ready):
  match valid:
    case False{}:
      do IO<Ready>:
        File.close(file)
        IO.die(Ready, 1, "world startup refused: file byte limit exceeded")
    case True{}:
      do IO<Ready>:
        bytes : Result<&2, &2, String, List<&2, U32>> <- read_loop(U32.to_nat(size), file, size, [])
        loaded_bytes(state, bytes)

def measured(state: State, +max_bytes: U32, result: File & Result<&1, &1, U32 & String, U32>) -> IO(Ready):
  (file, status) = result
  match status:
    case Fail{Tuple{code, message}}:
      do IO<Ready>:
        File.close(file)
        IO.die(Ready, 1, "world startup refused: file size failed: " ++ U32.show(code) ++ ": " ++ message)
    case Done{+size}: measured_valid(U32.is_le(size, max_bytes), state, file, size)

def opened(state: State, +max_bytes: U32, +allow_missing: Bool, result: Result<&1, &1, U32 & String, File>) -> IO(Ready):
  match result:
    case Fail{Tuple{2, message}}: missing_file(allow_missing, state)
    case Fail{Tuple{code, message}}: IO.die(Ready, 1, "world startup refused: file open failed: " ++ U32.show(code) ++ ": " ++ message)
    case Done{file}:
      do IO<Ready>:
        size : File & Result<&1, &1, U32 & String, U32> <- File.size(file)
        measured(state, max_bytes, size)

def identified_state(world: C.World, +path: String, +allow_missing: Bool, +limits: Limits, lease: WL.Lease, result: R.Registry & Result<&2, &2, String, String>) -> IO(Ready):
  (registry, identity_result) = result
  match identity_result:
    case Fail{message}: IO.die(Ready, 1, "world startup refused: registry identity failed: " ++ message)
    case Done{identity}:
      do IO<Ready>:
        file : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
        opened(State{G.Engine{world, registry}, identity, path, 0, limits, lease}, file_limit(limits), allow_missing, file)

def load_engine(+path: String, +allow_missing: Bool, +limits: Limits, lease: WL.Lease, engine: G.Engine) -> IO(Ready):
  G.Engine{world, registry} = engine
  identified_state(world, path, allow_missing, limits, lease, R.Registry.identity(registry))

def load_leased(+path: String, +allow_missing: Bool, +limits: Limits, result: Result<&1, &1, U32 & String, WL.Lease>) -> IO(Ready):
  match result:
    case Fail{Tuple{code, message}}: IO.die(Ready, 1, "world startup refused: lease acquisition failed: " ++ U32.show(code) ++ ": " ++ message)
    case Done{lease}:
      do IO<Ready>:
        engine : G.Engine <- G.load()
        load_engine(path, allow_missing, limits, lease, engine)

def load_with(+limits: Limits) -> IO(Ready):
  do IO<Ready>:
    path_result : Result<&1, &1, U32 & String, String> <- IO.get_env("MC_WORLD_PATH")
    +path : String <- required_path(path_result)
    missing_result : Result<&1, &1, U32 & String, String> <- IO.get_env("MC_WORLD_MISSING")
    allow_missing : Bool <- policy(missing_result)
    lease : Result<&1, &1, U32 & String, WL.Lease> <- WL.acquire(path ++ ".lock")
    load_leased(path, allow_missing, limits, lease)

def load() -> IO(Ready):
  load_with(default_limits())
