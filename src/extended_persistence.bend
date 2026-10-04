import Base
import ./persistence.bend as P
import ./game.bend as G
import ./core.bend as C
import ./registry.bend as R
import ./live.bend as L
import ./json.bend as J
import ./world_codec.bend as W
import ./nbt.bend as N
import ./atomic_file.bend as A
import ./world_lock.bend as WL

# Codec closures may capture runtime data; operation hooks remain closed templates.
# No plugin source is loaded.
type Codec<-Extra: Type> is Type:
  Codec{namespace: String, schema: U32,
    encode: Extra -> Extra & Result<&2, &2, String, List<&2, U32>>,
    decode: U32 -> List<&2, U32> -> Result<&2, &1, String, Extra>,
    fresh: Unit -> Result<&2, &1, String, Extra>,
    core_only: Unit -> Result<&2, &1, String, Extra>}

type Operation is Data:
  Operation{name: String, access: L.Access, fields: List<&2, L.Field>, description: String}

type Operations<-Extra: Type> is Type:
  Operations{catalog: Unit -> List<&2, Operation>,
    dispatch: G.Engine -> Extra -> L.Session -> L.Envelope -> G.Engine & Extra & Result<&2, &2, L.Fault, J.Value>}

type Limits is Data:
  Limits{world: W.Limits, max_extension_bytes: U32, max_file_bytes: U32}

type State<-Extra: Type> is Type:
  State{base: P.State, extra: Extra, max_extension_bytes: U32, catalog: List<&2, Operation>}

type Ready<-Extra: Type> is Type:
  Ready{state: State<Extra>, first_peer: U32}

type Loaded<-Extra: Type> is Type:
  Loaded{world: C.World, extra: Extra, highwater: U32}

def default_limits() -> Limits:
  Limits{W.default_limits(), 65536, 16846848}

def core_limits(+limits: Limits) -> W.Limits:
  Limits{world, extra, file} = limits
  world

def extra_limit(+limits: Limits) -> U32:
  Limits{world, extra, file} = limits
  extra

def file_limit(+limits: Limits) -> U32:
  Limits{world, extra, file} = limits
  file

def outer_limits(+limits: Limits) -> N.Limits:
  N.Limits{file_limit(limits), 6, 16}

def core_byte_limit(+limits: Limits) -> U32:
  P.nbt_byte_limit(W.nbt_limits(core_limits(limits)))

def ascii_name_char(+code: U32) -> Bool:
  (U32.is_ge(code, 97) && U32.is_le(code, 122)) || (U32.is_ge(code, 48) && U32.is_le(code, 57)) ||
  U32.is_eq(code, 46) || U32.is_eq(code, 95) || U32.is_eq(code, 58) || U32.is_eq(code, 45)

def ascii_name(fuel: Nat, text: String) -> Bool:
  match fuel text:
    case _ SNil{}: True{}
    case 0n SCon{h, t}: False{}
    case 1n+n SCon{h, t}: ascii_name_char(Char.to_u32(h)) && ascii_name(n, t)

def valid_name(+text: String) -> Bool:
  Bool.not(String.is_empty(text)) && ascii_name(128n, text)

def codec_metadata(-Extra: Type, codec: Codec<Extra>) -> String & U32:
  Codec{namespace, schema, encode, decode, fresh, legacy} = codec
  (namespace, schema)

def metadata_checked(pair: String & U32, +limits: Limits) -> Result<&2, &2, String, Unit>:
  (namespace, schema) = pair
  W.require(valid_name(namespace) && U32.is_ne(schema, 0) && U32.is_le(extra_limit(limits), 2147483647), "invalid closed codec namespace, schema or extension budget")

def reserved_core(operations: List<&2, L.Operation>, +name: String) -> Bool:
  match operations:
    case Nil{}: False{}
    case L.Operation{tag, actual, phase, access, fields, scheduled, description} <> rest:
      String.eq(actual, name) || reserved_core(rest, name)

def reserved_game(operations: List<&2, G.Extension>, +name: String) -> Bool:
  match operations:
    case Nil{}: False{}
    case G.Extension{query, actual, fields, description} <> rest: String.eq(actual, name) || reserved_game(rest, name)

def reserved(+name: String) -> Bool:
  String.eq(name, "world.save") || reserved_core(L.catalog(), name) || reserved_game(G.catalog(), name)

def valid_argument(argument: L.Argument) -> Bool:
  match argument:
    case L.Unsigned{lo, hi}: U32.is_le(lo, hi)
    case L.Text{values}: Nat.is_le(List.length(&2, String, values), 64n)
    case _: True{}

def valid_fields(fuel: Nat, fields: List<&2, L.Field>, +seen: List<&2, String>) -> Bool:
  match fuel fields:
    case _ Nil{}: True{}
    case 0n h <> t: False{}
    case 1n+n L.Field{+name, argument, required} <> rest:
      valid_name(name) && Bool.not(L.name_in(seen, name)) && valid_argument(argument) && valid_fields(n, rest, name <> seen)

def valid_catalog(fuel: Nat, operations: List<&2, Operation>, +seen: List<&2, String>) -> Bool:
  match fuel operations:
    case _ Nil{}: True{}
    case 0n h <> t: False{}
    case 1n+n Operation{+name, access, fields, description} <> rest:
      valid_name(name) && Bool.not(reserved(name)) && Bool.not(L.name_in(seen, name)) &&
      valid_fields(64n, fields, []) && Nat.is_le(String.length(description), 1024n) && valid_catalog(n, rest, name <> seen)

def operation_value(operation: Operation) -> J.Value:
  Operation{+name, access, +fields, description} = operation
  L.obj([J.JMember{"name", L.text(name)}, J.JMember{"phase", L.text("extension")}, J.JMember{"permitted_mode", L.text(L.access_name(access))},
    J.JMember{"version", L.text("26.3")}, J.JMember{"status", L.text("implemented-foundation")}, J.JMember{"scheduled", L.boolean(False{})},
    J.JMember{"description", L.text(description)}, J.JMember{"input_schema", L.request_schema(name, fields, False{})}])

def operation_values(operations: List<&2, Operation>) -> List<&2, J.Value>:
  match operations:
    case Nil{}: []
    case h <> t: operation_value(h) <> operation_values(t)

def lookup(operations: List<&2, Operation>, +name: String) -> Maybe<&2, Operation>:
  match operations:
    case Nil{}: None{}
    case +head <> tail:
      Operation{actual, access, fields, description} = head
      J.choose(Maybe<&2, Operation>, Some{head}, lookup(tail, name), String.eq(actual, name))

def allowed(access: L.Access, capability: C.Capability) -> Bool:
  match access:
    case L.Public{}: True{}
    case L.DeveloperOnly{}: C.developer(capability)

def text_name_result(result: Result<&2, &2, String, String>, expected: String) -> Bool:
  match result:
    case Fail{message}: False{}
    case Done{actual}: String.eq(actual, expected)

def text_name(text: N.Text, expected: String) -> Bool:
  text_name_result(W.read_text(W.default_limits(), text), expected)

# Intercept each ByteArray header before generic NBT can allocate its payload.
# The raw bounded input list already exists; these are decoded-payload bounds.
def bytearray_limit(+limits: Limits, frames: List<&2, N.DecodeFrame>) -> Result<&2, &2, String, U32>:
  match frames:
    case N.CompoundFrame{count, members, +name} <> Nil{}:
      do Result<&2, &2, String, U32>:
        W.require(text_name(name, "core") || text_name(name, "world"), "ByteArray is not a core bundle field")
        return U32.min(core_byte_limit(limits), file_limit(limits))
    case N.CompoundFrame{count, members, name} <> N.CompoundFrame{outer_count, outer_members, parent} <> Nil{}:
      do Result<&2, &2, String, U32>:
        W.require(text_name(name, "payload") && text_name(parent, "extension"), "ByteArray is not an extension payload")
        return U32.min(extra_limit(limits), file_limit(limits))
    case _: Fail{"ByteArray outside the exact bundle schema"}

def guarded_array(bound: Result<&2, &2, String, U32>, state: N.DecodeState) -> N.DecodeStep:
  match bound:
    case Fail{message}: N.DecodeRejected{message}
    case Done{maximum}:
      N.DecodeState{+reader, name, frames, mode, depth, N.Limits{bytes, max_depth, elements}} = state
      N.array_header(N.DecodeState{reader, name, frames, mode, depth, N.Limits{bytes, max_depth, maximum}}, 7, N.read_word(4n, reader, 0, 0))

def guarded_step(+limits: Limits, state: N.DecodeState) -> N.DecodeStep:
  match state:
    case N.DecodeState{reader, name, +frames, N.Need{7}, depth, old}:
      guarded_array(bytearray_limit(limits, frames), N.DecodeState{reader, name, frames, N.Need{7}, depth, outer_limits(limits)})
    case N.DecodeState{reader, name, frames, N.Need{9}, depth, old}: N.DecodeRejected{"NBT List is not part of the bundle schema"}
    case N.DecodeState{reader, name, frames, N.Need{11}, depth, old}: N.DecodeRejected{"NBT IntArray is not part of the bundle envelope"}
    case N.DecodeState{reader, name, frames, N.Need{12}, depth, old}: N.DecodeRejected{"NBT LongArray is not part of the bundle envelope"}
    case N.DecodeState{reader, name, frames, mode, depth, old}:
      N.decode_step(N.DecodeState{reader, name, frames, mode, depth, outer_limits(limits)})

# This finite law rejects a declared oversized payload before reading any body byte.
law checked_extension_header_limit:
  {guarded_step(Limits{W.default_limits(), 8, 4096}, N.DecodeState{N.Reader{[0, 0, 0, 9], 0}, W.text("bendex:bundle"),
    [N.CompoundFrame{0, [], W.text("payload")}, N.CompoundFrame{0, [], W.text("extension")}], N.Need{7}, 2, N.Limits{4096, 6, 16}})
    == N.DecodeRejected{"negative or excessive NBT array length"} : N.DecodeStep}

def checked_extension_header_limit():
  {==}

def guarded_run(fuel: Nat, +limits: Limits, step: N.DecodeStep) -> Result<&2, &2, String, N.Root>:
  match fuel step:
    case _ N.DecodeFinished{root, reader}: N.complete(root, reader)
    case _ N.DecodeRejected{message}: Fail{message}
    case 0n N.DecodeContinue{state}: Fail{"bundle decode transition budget exceeded"}
    case 1n+n N.DecodeContinue{state}: guarded_run(n, limits, guarded_step(limits, state))

def guarded_name(+limits: Limits, +size: U32, kind: U32, result: Result<&2, &2, String, N.Read<N.Text>>) -> Result<&2, &2, String, N.Root>:
  match kind result:
    case 10 Done{N.Read{reader, name}}:
      guarded_run(Nat.add(16n, Nat.mul(4n, U32.to_nat(size))), limits, N.DecodeContinue{N.DecodeState{reader, name, [], N.Need{10}, 0, outer_limits(limits)}})
    case _ Fail{message}: Fail{message}
    case _ _: Fail{"bundle root requires Compound"}

def guarded_tag(+limits: Limits, +size: U32, result: Result<&2, &2, String, N.Read<N.Word64>>) -> Result<&2, &2, String, N.Root>:
  match result:
    case Fail{message}: Fail{message}
    case Done{N.Read{reader, N.Word64{hi, kind}}}: guarded_name(limits, size, kind, N.read_text(reader))

def guarded_scanned(+limits: Limits, bytes: List<&2, U32>, checked: Result<&2, &2, String, U32>) -> Result<&2, &2, String, N.Root>:
  match checked:
    case Fail{message}: Fail{message}
    case Done{size}: guarded_tag(limits, size, N.read_word(1n, N.Reader{bytes, 0}, 0, 0))

def envelope_parse(+limits: Limits, +bytes: List<&2, U32>) -> Result<&2, &2, String, N.Root>:
  guarded_scanned(limits, bytes, N.scan(U32.to_nat(file_limit(limits)), bytes, 0))

# Check byte values and declared policy even if an extension encoder ignores it.
def checked_payload(+maximum: U32, +bytes: List<&2, U32>) -> Result<&2, &2, String, List<&2, U32>>:
  do Result<&2, &2, String, List<&2, U32>>:
    size : U32 <- N.scan(U32.to_nat(maximum), bytes, 0)
    return bytes

law checked_encoder_budget:
  {checked_payload(8, [0, 1, 2, 3, 4, 5, 6, 7, 8]) == Fail{"NBT input byte limit exceeded"} : Result<&2, &2, String, List<&2, U32>>}

def checked_encoder_budget():
  {==}

def bundle_root(+identity: String, highwater: U32, namespace: String, schema: U32, core: List<&2, U32>, extra: List<&2, U32>) -> N.Root:
  N.Root{W.text("bendex:bundle"), N.Compound{[
    W.named("format", N.Int{1}), W.named("minecraft", W.string_tag("26.3")), W.named("registry", W.string_tag(identity)),
    W.named("peer_highwater", N.Int{highwater}), W.named("core", N.ByteArray{core}),
    W.named("extension", N.Compound{[W.named("namespace", W.string_tag(namespace)), W.named("schema", N.Int{schema}), W.named("payload", N.ByteArray{extra})]})]}}

def bundle_encoded(+limits: Limits, identity: String, highwater: U32, metadata: String & U32, +core: List<&2, U32>, +extra: List<&2, U32>) -> Result<&2, &2, String, List<&2, U32>>:
  Tuple{+namespace, +schema} = metadata
  do Result<&2, &2, String, List<&2, U32>>:
    metadata_checked((namespace, schema), limits)
    core_checked : List<&2, U32> <- checked_payload(core_byte_limit(limits), core)
    extra_checked : List<&2, U32> <- checked_payload(extra_limit(limits), extra)
    N.encode_with(N.Limits{file_limit(limits), 6, U32.max(core_byte_limit(limits), extra_limit(limits))}, bundle_root(identity, highwater, namespace, schema, core_checked, extra_checked))

def codec_encode(-Extra: Type, codec: Codec<Extra>, extra: Extra) -> Extra & Result<&2, &2, String, List<&2, U32>>:
  Codec{namespace, schema, encode, decode, fresh, legacy} = codec
  encode(extra)

def canonical_payload(-Extra: Type, extra: Extra, checked: Result<&2, &2, String, List<&2, U32>>) -> Result<&2, &1, String, Extra>:
  match checked:
    case Fail{message}: Fail{message}
    case Done{bytes}: Done{extra}

def canonical_status(-Extra: Type, maximum: U32, extra: Extra, encoded: Result<&2, &2, String, List<&2, U32>>) -> Result<&2, &1, String, Extra>:
  match encoded:
    case Fail{message}: Fail{message}
    case Done{bytes}: canonical_payload(Extra, extra, checked_payload(maximum, bytes))

def canonical_encoded(-Extra: Type, maximum: U32, result: Extra & Result<&2, &2, String, List<&2, U32>>) -> Result<&2, &1, String, Extra>:
  (extra, encoded) = result
  canonical_status(Extra, maximum, extra, encoded)

def canonical_extra(-Extra: Type, encode: Extra -> Extra & Result<&2, &2, String, List<&2, U32>>, maximum: U32, decoded: Result<&2, &1, String, Extra>) -> Result<&2, &1, String, Extra>:
  match decoded:
    case Fail{message}: Fail{message}
    case Done{extra}: canonical_encoded(Extra, maximum, encode(extra))

def codec_fresh(-Extra: Type, codec: Codec<Extra>, maximum: U32) -> Result<&2, &1, String, Extra>:
  Codec{namespace, schema, encode, decode, fresh, legacy} = codec
  canonical_extra(Extra, encode, maximum, fresh(Unit{}))

def operation_catalog(-Extra: Type, operations: Operations<Extra>) -> List<&2, Operation>:
  Operations{catalog, dispatch} = operations
  catalog(Unit{})

def byte_array(value: N.Value) -> Result<&2, &2, String, List<&2, U32>>:
  match value:
    case N.ByteArray{bytes}: Done{bytes}
    case _: Fail{"bundle payload requires ByteArray"}

def metadata_value(+limits: Limits, +identity: String, +fs: List<&2, W.Field>) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    format : U32 <- W.int_value(W.field(fs, "format"))
    W.require(U32.is_eq(format, 1), "unsupported bundle format")
    minecraft : String <- W.string_value(core_limits(limits), W.field(fs, "minecraft"))
    W.require(String.eq(minecraft, "26.3"), "bundle Minecraft version mismatch")
    registry : String <- W.string_value(core_limits(limits), W.field(fs, "registry"))
    W.require(String.eq(registry, identity), "bundle registry identity mismatch")
    W.int_value(W.field(fs, "peer_highwater"))

type ExtensionBytes is Data:
  ExtensionBytes{schema: U32, bytes: List<&2, U32>}

def extension_bytes(+limits: Limits, +namespace: String, value: N.Value) -> Result<&2, &2, String, ExtensionBytes>:
  do Result<&2, &2, String, ExtensionBytes>:
    +fs : List<&2, W.Field> <- W.fields(core_limits(limits), value, ["namespace", "schema", "payload"])
    actual : String <- W.string_value(core_limits(limits), W.field(fs, "namespace"))
    W.require(String.eq(actual, namespace), "bundle extension namespace mismatch")
    +schema : U32 <- W.int_value(W.field(fs, "schema"))
    W.require(U32.is_ne(schema, 0), "extension schema must be nonzero")
    bytes : List<&2, U32> <- byte_array(W.field(fs, "payload"))
    checked : List<&2, U32> <- checked_payload(extra_limit(limits), bytes)
    return ExtensionBytes{schema, checked}

def attach_extra(-Extra: Type, world: C.World, highwater: U32, decoded: Result<&2, &1, String, Extra>) -> Result<&2, &1, String, Loaded<Extra>>:
  match decoded:
    case Fail{message}: Fail{message}
    case Done{extra}: Done{Loaded{world, extra, highwater}}

def decode_extra_core(-Extra: Type, encode: Extra -> Extra & Result<&2, &2, String, List<&2, U32>>, maximum: U32, decode: U32 -> List<&2, U32> -> Result<&2, &1, String, Extra>, schema: U32, bytes: List<&2, U32>, core: Result<&2, &1, String, P.Saved>) -> Result<&2, &1, String, Loaded<Extra>>:
  match core:
    case Fail{message}: Fail{message}
    case Done{P.Saved{world, highwater}}: attach_extra(Extra, world, highwater, canonical_extra(Extra, encode, maximum, decode(schema, bytes)))

def bundle_values(-Extra: Type, encode: Extra -> Extra & Result<&2, &2, String, List<&2, U32>>, decode: U32 -> List<&2, U32> -> Result<&2, &1, String, Extra>, +limits: Limits, +count: U32, +identity: String, checked: Result<&2, &2, String, W.Both<U32, W.Both<List<&2, U32>, ExtensionBytes>>>) -> Result<&2, &1, String, Loaded<Extra>>:
  match checked:
    case Fail{message}: Fail{message}
    case Done{W.Both{highwater, W.Both{core, ExtensionBytes{schema, bytes}}}}:
      decode_extra_core(Extra, encode, extra_limit(limits), decode, schema, bytes, P.saved_world(highwater, W.decode_with(core_limits(limits), core, count, identity)))

def bundle_fields(+limits: Limits, +count: U32, +identity: String, +namespace: String, value: N.Value) -> Result<&2, &2, String, W.Both<U32, W.Both<List<&2, U32>, ExtensionBytes>>>:
  do Result<&2, &2, String, W.Both<U32, W.Both<List<&2, U32>, ExtensionBytes>>>:
    +fs : List<&2, W.Field> <- W.fields(core_limits(limits), value, ["format", "minecraft", "registry", "peer_highwater", "core", "extension"])
    highwater : U32 <- metadata_value(limits, identity, fs)
    core : List<&2, U32> <- byte_array(W.field(fs, "core"))
    ext : ExtensionBytes <- extension_bytes(limits, namespace, W.field(fs, "extension"))
    return W.Both{highwater, W.Both{core, ext}}

def decode_bundle(-Extra: Type, codec: Codec<Extra>, +limits: Limits, +count: U32, +identity: String, value: N.Value) -> Result<&2, &1, String, Loaded<Extra>>:
  Codec{namespace, schema, encode, decode, fresh, legacy} = codec
  bundle_values(Extra, encode, decode, limits, count, identity, bundle_fields(limits, count, identity, namespace, value))

def decode_legacy_result(-Extra: Type, encode: Extra -> Extra & Result<&2, &2, String, List<&2, U32>>, maximum: U32, legacy: Unit -> Result<&2, &1, String, Extra>, core: Result<&2, &1, String, P.Saved>) -> Result<&2, &1, String, Loaded<Extra>>:
  match core:
    case Fail{message}: Fail{message}
    case Done{P.Saved{world, highwater}}: attach_extra(Extra, world, highwater, canonical_extra(Extra, encode, maximum, legacy(Unit{})))

def decode_legacy(-Extra: Type, codec: Codec<Extra>, +limits: Limits, bytes: List<&2, U32>, count: U32, identity: String) -> Result<&2, &1, String, Loaded<Extra>>:
  Codec{namespace, schema, encode, decode, fresh, legacy} = codec
  decode_legacy_result(Extra, encode, extra_limit(limits), legacy, P.envelope_decode(P.Limits{core_limits(limits), file_limit(limits)}, bytes, count, identity))

def decode_name(-Extra: Type, codec: Codec<Extra>, +limits: Limits, bytes: List<&2, U32>, count: U32, identity: String, value: N.Value, name: Result<&2, &2, String, String>) -> Result<&2, &1, String, Loaded<Extra>>:
  match name:
    case Fail{message}: Fail{message}
    case Done{"bendex:bundle"}: decode_bundle(Extra, codec, limits, count, identity, value)
    case Done{"bendex:save"}: decode_legacy(Extra, codec, limits, bytes, count, identity)
    case Done{other}: Fail{"wrong bundle root name"}

def decode_parsed(-Extra: Type, codec: Codec<Extra>, +limits: Limits, bytes: List<&2, U32>, count: U32, identity: String, parsed: Result<&2, &2, String, N.Root>) -> Result<&2, &1, String, Loaded<Extra>>:
  match parsed:
    case Fail{message}: Fail{message}
    case Done{N.Root{name, value}}: decode_name(Extra, codec, limits, bytes, count, identity, value, W.read_text(core_limits(limits), name))

def decode(~Extra: Type, ~codec: Codec<Extra>, +limits: Limits, +bytes: List<&2, U32>, count: U32, identity: String) -> Result<&2, &1, String, Loaded<Extra>>:
  decode_parsed(Extra, codec, limits, bytes, count, identity, envelope_parse(limits, bytes))

def realtime_step(-Extra: Type, state: State<Extra>) -> State<Extra>:
  State{base, extra, maximum, catalog} = state
  State{P.realtime_step(base), extra, maximum, catalog}

def observe(-Extra: Type, state: State<Extra>, peer: U32) -> State<Extra>:
  State{base, extra, maximum, catalog} = state
  State{P.observe(base, peer), extra, maximum, catalog}

def pack(-Extra: Type, extra: Extra, maximum: U32, catalog: List<&2, Operation>, result: P.State & L.Session & J.Value) -> State<Extra> & L.Session & J.Value:
  (base, session, value) = result
  (State{base, extra, maximum, catalog}, session, value)

def success(-Extra: Type, state: State<Extra>, session: L.Session, id: String, value: J.Value) -> State<Extra> & L.Session & J.Value:
  State{base, extra, maximum, catalog} = state
  pack(Extra, extra, maximum, catalog, P.success(base, session, id, value))

def failure(-Extra: Type, state: State<Extra>, session: L.Session, id: String, fault: L.Fault) -> State<Extra> & L.Session & J.Value:
  State{base, extra, maximum, catalog} = state
  L.Fault{code, message} = fault
  pack(Extra, extra, maximum, catalog, P.failure(base, session, id, code, message))

def state_limits(-Extra: Type, state: State<Extra>) -> State<Extra> & Limits:
  State{P.State{engine, identity, path, highwater, P.Limits{+world_limits, +file_bytes}, lease}, extra, +maximum, catalog} = state
  (State{P.State{engine, identity, path, highwater, P.Limits{world_limits, file_bytes}, lease}, extra, maximum, catalog}, Limits{world_limits, maximum, file_bytes})

def encode_extra_result(-Extra: Type, base: P.State, maximum: U32, catalog: List<&2, Operation>, core: Result<&2, &2, String, List<&2, U32>>, extra_encoded: Extra & Result<&2, &2, String, List<&2, U32>>) -> State<Extra> & Result<&2, &2, String, W.Both<List<&2, U32>, List<&2, U32>>>:
  (extra, extension) = extra_encoded
  (State{base, extra, maximum, catalog},
    (do Result<&2, &2, String, W.Both<List<&2, U32>, List<&2, U32>>>:
      core_bytes : List<&2, U32> <- core
      extra_bytes : List<&2, U32> <- extension
      return W.Both{core_bytes, extra_bytes}))

def encode_core_result(-Extra: Type, codec: Codec<Extra>, +identity: String, path: String, highwater: U32, limits: P.Limits, lease: WL.Lease, extra: Extra, maximum: U32, catalog: List<&2, Operation>, core: G.Engine & Result<&2, &2, String, List<&2, U32>>) -> State<Extra> & Result<&2, &2, String, W.Both<List<&2, U32>, List<&2, U32>>>:
  (engine, encoded) = core
  encode_extra_result(Extra, P.State{engine, identity, path, highwater, limits, lease}, maximum, catalog, encoded, codec_encode(Extra, codec, extra))

def encode_owners(-Extra: Type, codec: Codec<Extra>, state: State<Extra>) -> State<Extra> & Result<&2, &2, String, W.Both<List<&2, U32>, List<&2, U32>>>:
  State{P.State{engine, +identity, path, highwater, +limits, lease}, extra, maximum, catalog} = state
  encode_core_result(Extra, codec, identity, path, highwater, limits, lease, extra, maximum, catalog, P.encode_engine(P.world_limits(limits), identity, engine))

def encode_checked(metadata: String & U32, limits: Limits, identity: String, highwater: U32, encoded: Result<&2, &2, String, W.Both<List<&2, U32>, List<&2, U32>>>) -> Result<&2, &2, String, List<&2, U32>>:
  match encoded:
    case Fail{message}: Fail{message}
    case Done{W.Both{core, extension}}: bundle_encoded(limits, identity, highwater, metadata, core, extension)

def encode_bytes(-Extra: Type, metadata: String & U32, +limits: Limits, result: State<Extra> & Result<&2, &2, String, W.Both<List<&2, U32>, List<&2, U32>>>) -> State<Extra> & Result<&2, &2, String, List<&2, U32>>:
  (state, encoded) = result
  State{P.State{engine, +identity, path, +highwater, old_limits, lease}, extra, maximum, catalog} = state
  (State{P.State{engine, identity, path, highwater, old_limits, lease}, extra, maximum, catalog},
    encode_checked(metadata, limits, identity, highwater, encoded))

def encode_codec_counted(~Extra: Type, codec: Codec<Extra>, counted: State<Extra> & Limits) -> State<Extra> & Result<&2, &2, String, List<&2, U32>>:
  Codec{+namespace, +schema, encode, decode, fresh, legacy} = codec
  (state, limits) = counted
  encode_bytes(Extra, (namespace, schema), limits,
    encode_owners(Extra, Codec{namespace, schema, encode, decode, fresh, legacy}, state))

def encode_codec(~Extra: Type, codec: Codec<Extra>, state: State<Extra>) -> State<Extra> & Result<&2, &2, String, List<&2, U32>>:
  encode_codec_counted(~Extra, codec, state_limits(Extra, state))

def encode_counted(~Extra: Type, ~codec: Codec<Extra>, counted: State<Extra> & Limits) -> State<Extra> & Result<&2, &2, String, List<&2, U32>>:
  encode_codec_counted(~Extra, codec, counted)

def encode(~Extra: Type, ~codec: Codec<Extra>, state: State<Extra>) -> State<Extra> & Result<&2, &2, String, List<&2, U32>>:
  encode_counted(~Extra, ~codec, state_limits(Extra, state))

def save_encoded(-Extra: Type, encoded: Result<&2, &2, String, List<&2, U32>>, state: State<Extra>, +session: L.Session, +id: String) -> IO(State<Extra> & L.Session & J.Value):
  match encoded:
    case Fail{message}: IO.pure(State<Extra> & L.Session & J.Value, failure(Extra, state, session, id, L.bad("SaveEncodingFailed", message)))
    case Done{+bytes}:
      State{P.State{engine, identity, +path, +highwater, limits, lease}, extra, maximum, catalog} = state
      do IO<State<Extra> & L.Session & J.Value>:
        outcome : A.Outcome <- A.publish(path, "save-" ++ U32.show(L.peer(session)) ++ "-" ++ Nat.show(L.sequence(session)), bytes)
        return pack(Extra, extra, maximum, catalog,
          P.published(P.State{engine, identity, path, highwater, limits, lease}, session, id, U32.from_nat(List.length(&2, U32, bytes)), highwater, outcome))

def save_result(-Extra: Type, session: L.Session, id: String, encoded: State<Extra> & Result<&2, &2, String, List<&2, U32>>) -> IO(State<Extra> & L.Session & J.Value):
  (state, bytes) = encoded
  save_encoded(Extra, bytes, state, session, id)

def save_codec(~Extra: Type, codec: Codec<Extra>, state: State<Extra>, session: L.Session, id: String) -> IO(State<Extra> & L.Session & J.Value):
  save_result(Extra, session, id, encode_codec(~Extra, codec, state))

def save(~Extra: Type, ~codec: Codec<Extra>, state: State<Extra>, session: L.Session, id: String) -> IO(State<Extra> & L.Session & J.Value):
  save_codec(~Extra, codec, state, session, id)

def save_descriptor() -> J.Value:
  L.obj([J.JMember{"name", L.text("world.save")}, J.JMember{"phase", L.text("persistence")}, J.JMember{"permitted_mode", L.text("developer")},
    J.JMember{"version", L.text("26.3")}, J.JMember{"status", L.text("implemented-foundation")}, J.JMember{"scheduled", L.boolean(False{})},
    J.JMember{"description", L.text("Atomically publish the complete Core and typed extension bundle to the configured path; report publication and durability separately.")},
    J.JMember{"input_schema", L.request_schema("world.save", [], False{})}])

def discover_members(members: List<&2, J.Member>, +extra: List<&2, Operation>) -> List<&2, J.Member>:
  match members:
    case Nil{}: []
    case J.JMember{"operations", J.JArray{values}} <> rest:
      J.JMember{"operations", J.JArray{List.append(&2, J.Value, values, save_descriptor() <> operation_values(extra))}} <> discover_members(rest, extra)
    case h <> rest: h <> discover_members(rest, extra)

def discovery(value: J.Value, extra: List<&2, Operation>) -> J.Value:
  match value:
    case J.JObject{members}: J.JObject{discover_members(members, extra)}
    case other: other

def discover(-Extra: Type, state: State<Extra>, session: L.Session, id: String) -> State<Extra> & L.Session & J.Value:
  State{base, extra, maximum, +catalog} = state
  success(Extra, State{base, extra, maximum, catalog}, session, id, discovery(G.discovery(), catalog))

def delegate(-Extra: Type, state: State<Extra>, session: L.Session, token: String, request: J.Value) -> IO(State<Extra> & L.Session & J.Value):
  State{P.State{engine, identity, path, highwater, limits, lease}, extra, maximum, catalog} = state
  IO.pure(State<Extra> & L.Session & J.Value, pack(Extra, extra, maximum, catalog, P.pack(identity, path, highwater, limits, lease, G.dispatch(engine, session, token, request))))

def hook_finish(-Extra: Type, answer: Result<&2, &2, L.Fault, J.Value>, state: State<Extra>, session: L.Session, id: String) -> State<Extra> & L.Session & J.Value:
  match answer:
    case Fail{fault}: failure(Extra, state, session, id, fault)
    case Done{value}: success(Extra, state, session, id, value)

def hook_result(-Extra: Type, identity: String, path: String, highwater: U32, limits: P.Limits, lease: WL.Lease, maximum: U32, catalog: List<&2, Operation>, session: L.Session, id: String, result: G.Engine & Extra & Result<&2, &2, L.Fault, J.Value>) -> State<Extra> & L.Session & J.Value:
  (engine, extra, answer) = result
  hook_finish(Extra, answer, State{P.State{engine, identity, path, highwater, limits, lease}, extra, maximum, catalog}, session, id)

def invoke(-Extra: Type, operations: Operations<Extra>, state: State<Extra>, +session: L.Session, +envelope: L.Envelope) -> State<Extra> & L.Session & J.Value:
  Operations{catalog_fn, dispatch} = operations
  State{P.State{engine, identity, path, highwater, limits, lease}, extra, maximum, catalog} = state
  L.Envelope{id, op, args, at} = envelope
  hook_result(Extra, identity, path, highwater, limits, lease, maximum, catalog, session, id, dispatch(engine, extra, session, envelope))

def hook_valid(-Extra: Type, operations: Operations<Extra>, valid: Bool, permitted: Bool, state: State<Extra>, session: L.Session, envelope: L.Envelope) -> State<Extra> & L.Session & J.Value:
  match valid permitted:
    case False{} _:
      L.Envelope{id, op, args, at} = envelope
      failure(Extra, state, session, id, L.bad("InvalidArguments", "extension requires its strict arguments and no at field"))
    case True{} False{}:
      L.Envelope{id, op, args, at} = envelope
      failure(Extra, state, session, id, L.bad("PermissionDenied", "developer capability required"))
    case True{} True{}: invoke(Extra, operations, state, session, envelope)

def hook(-Extra: Type, operations: Operations<Extra>, operation: Operation, state: State<Extra>, +session: L.Session, +envelope: L.Envelope) -> State<Extra> & L.Session & J.Value:
  Operation{name, access, fields, description} = operation
  L.Envelope{id, op, args, at} = envelope
  hook_valid(Extra, operations, L.validate_args(args, fields) && Maybe.is_none(&2, Nat, at), allowed(access, L.capability(session)), state, session, envelope)

def custom_valid(~Extra: Type, codec: Codec<Extra>, valid: Bool, permitted: Bool, +op: String, state: State<Extra>, session: L.Session, id: String) -> IO(State<Extra> & L.Session & J.Value):
  match valid permitted op:
    case False{} _ _: IO.pure(State<Extra> & L.Session & J.Value, failure(Extra, state, session, id, L.bad("InvalidArguments", "operation requires empty arguments and no at field")))
    case True{} False{} _: IO.pure(State<Extra> & L.Session & J.Value, failure(Extra, state, session, id, L.bad("PermissionDenied", "developer capability required")))
    case True{} True{} "world.save": save_codec(~Extra, codec, state, session, id)
    case True{} True{} _: IO.pure(State<Extra> & L.Session & J.Value, discover(Extra, state, session, id))

def custom_codec(~Extra: Type, codec: Codec<Extra>, envelope: L.Envelope, state: State<Extra>, +session: L.Session) -> IO(State<Extra> & L.Session & J.Value):
  L.Envelope{id, +op, args, at} = envelope
  L.Session{peer, sequence, capability} = session
  custom_valid(~Extra, codec, L.validate_args(args, []) && Maybe.is_none(&2, Nat, at), String.eq(op, "discover") || C.developer(capability), op, state, L.Session{peer, 1n+sequence, capability}, id)

def custom(~Extra: Type, ~codec: Codec<Extra>, envelope: L.Envelope, state: State<Extra>, session: L.Session) -> IO(State<Extra> & L.Session & J.Value):
  custom_codec(~Extra, codec, envelope, state, session)

def extra_found(-Extra: Type, operations: Operations<Extra>, found: Maybe<&2, Operation>, envelope: L.Envelope, state: State<Extra>, session: L.Session, token: String, request: J.Value) -> IO(State<Extra> & L.Session & J.Value):
  match found:
    case None{}: delegate(Extra, state, session, token, request)
    case Some{operation}:
      L.Session{peer, sequence, capability} = session
      IO.pure(State<Extra> & L.Session & J.Value, hook(Extra, operations, operation, state, L.Session{peer, 1n+sequence, capability}, envelope))

def routed(-Extra: Type, operations: Operations<Extra>, +envelope: L.Envelope, state: State<Extra>, session: L.Session, token: String, request: J.Value) -> IO(State<Extra> & L.Session & J.Value):
  L.Envelope{id, op, args, at} = envelope
  State{base, extra, maximum, +catalog} = state
  extra_found(Extra, operations, lookup(catalog, op), envelope, State{base, extra, maximum, catalog}, session, token, request)

def chosen(~Extra: Type, ~operations: Operations<Extra>, codec: Codec<Extra>, own: Bool, envelope: L.Envelope, state: State<Extra>, session: L.Session, token: String, request: J.Value) -> IO(State<Extra> & L.Session & J.Value):
  match own:
    case True{}: custom_codec(~Extra, codec, envelope, state, session)
    case False{}: routed(Extra, operations, envelope, state, session, token, request)

def parsed(~Extra: Type, ~operations: Operations<Extra>, codec: Codec<Extra>, parsed: Result<&2, &2, L.Fault, L.Envelope>, state: State<Extra>, session: L.Session, token: String, request: J.Value) -> IO(State<Extra> & L.Session & J.Value):
  match parsed:
    case Fail{fault}: delegate(Extra, state, session, token, request)
    case Done{+envelope}:
      L.Envelope{id, +op, args, at} = envelope
      chosen(~Extra, ~operations, codec, String.eq(op, "discover") || String.eq(op, "world.save"), envelope, state, session, token, request)

def dispatch_inner(~Extra: Type, ~operations: Operations<Extra>, codec: Codec<Extra>, state: State<Extra>, +session: L.Session, +token: String, +request: J.Value) -> IO(State<Extra> & L.Session & J.Value):
  parsed(~Extra, ~operations, codec, L.envelope(request), observe(Extra, state, L.peer(session)), session, token, request)

def dispatch(~Extra: Type, ~codec: Codec<Extra>, ~operations: Operations<Extra>, state: State<Extra>, session: L.Session, token: String, request: J.Value) -> IO(State<Extra> & L.Session & J.Value):
  dispatch_inner(~Extra, ~operations, codec, state, session, token, request)

# Runtime initialized catalogs are captured by one codec owner, as in
# load_codec. Both entry points use the same schema/permission/sequence routes
# and the same encode, atomic publication and acknowledgment functions.
def dispatch_codec(~Extra: Type, ~operations: Operations<Extra>, codec: Codec<Extra>, state: State<Extra>, session: L.Session, token: String, request: J.Value) -> IO(State<Extra> & L.Session & J.Value):
  dispatch_inner(~Extra, ~operations, codec, state, session, token, request)

# All initial/load hooks must succeed before a State is adopted or a listener exists.
def ready_peer(-Extra: Type, state: State<Extra>, peer: Result<&2, &2, String, U32>) -> IO(Ready<Extra>):
  match peer:
    case Fail{message}: IO.die(Ready<Extra>, 1, "bundle startup refused: " ++ message)
    case Done{first}: IO.pure(Ready<Extra>, Ready{state, first})

def ready(-Extra: Type, state: State<Extra>) -> IO(Ready<Extra>):
  State{P.State{engine, identity, path, +highwater, limits, lease}, extra, maximum, catalog} = state
  ready_peer(Extra, State{P.State{engine, identity, path, highwater, limits, lease}, extra, maximum, catalog}, P.next_peer(highwater))

def fresh_result(-Extra: Type, base: P.State, maximum: U32, catalog: List<&2, Operation>, initial: Result<&2, &1, String, Extra>) -> IO(Ready<Extra>):
  match initial:
    case Fail{message}: IO.die(Ready<Extra>, 1, "bundle startup refused: fresh extension initialization failed: " ++ message)
    case Done{extra}: ready(Extra, State{base, extra, maximum, catalog})

def missing(-Extra: Type, codec: Codec<Extra>, allowed: Bool, base: P.State, +maximum: U32, catalog: List<&2, Operation>) -> IO(Ready<Extra>):
  match allowed:
    case False{}: IO.die(Ready<Extra>, 1, "bundle startup refused: missing file requires MC_WORLD_MISSING=create")
    case True{}: fresh_result(Extra, base, maximum, catalog, codec_fresh(Extra, codec, maximum))

def loaded(-Extra: Type, decoded: Result<&2, &1, String, Loaded<Extra>>, base: P.State, maximum: U32, catalog: List<&2, Operation>) -> IO(Ready<Extra>):
  match decoded:
    case Fail{message}: IO.die(Ready<Extra>, 1, "bundle startup refused: " ++ message)
    case Done{Loaded{world, extra, highwater}}:
      P.State{G.Engine{old_world, registry}, identity, path, old_highwater, limits, lease} = base
      ready(Extra, State{P.State{G.Engine{world, registry}, identity, path, highwater, limits, lease}, extra, maximum, catalog})

def loaded_counted(~Extra: Type, codec: Codec<Extra>, +limits: Limits, catalog: List<&2, Operation>, +bytes: List<&2, U32>, counted: P.State & U32) -> IO(Ready<Extra>):
  (base, count) = counted
  P.State{engine, +identity, path, highwater, old_limits, lease} = base
  loaded(Extra, decode_parsed(Extra, codec, limits, bytes, count, identity, envelope_parse(limits, bytes)), P.State{engine, identity, path, highwater, old_limits, lease}, extra_limit(limits), catalog)

def loaded_bytes(~Extra: Type, codec: Codec<Extra>, limits: Limits, catalog: List<&2, Operation>, base: P.State, bytes: Result<&2, &2, String, List<&2, U32>>) -> IO(Ready<Extra>):
  match bytes:
    case Fail{message}: IO.die(Ready<Extra>, 1, "bundle startup refused: " ++ message)
    case Done{raw}: loaded_counted(~Extra, codec, limits, catalog, raw, P.state_count(base))

def measured_valid(~Extra: Type, codec: Codec<Extra>, +limits: Limits, catalog: List<&2, Operation>, base: P.State, file: File, +size: U32, valid: Bool) -> IO(Ready<Extra>):
  match valid:
    case False{}:
      do IO<Ready<Extra>>:
        File.close(file)
        IO.die(Ready<Extra>, 1, "bundle startup refused: file byte limit exceeded")
    case True{}:
      do IO<Ready<Extra>>:
        bytes : Result<&2, &2, String, List<&2, U32>> <- P.read_loop(U32.to_nat(size), file, size, [])
        loaded_bytes(~Extra, codec, limits, catalog, base, bytes)

def measured(~Extra: Type, codec: Codec<Extra>, +limits: Limits, catalog: List<&2, Operation>, base: P.State, result: File & Result<&1, &1, U32 & String, U32>) -> IO(Ready<Extra>):
  (file, status) = result
  match status:
    case Fail{Tuple{code, message}}:
      do IO<Ready<Extra>>:
        File.close(file)
        IO.die(Ready<Extra>, 1, "bundle startup refused: file size failed: " ++ U32.show(code) ++ ": " ++ message)
    case Done{+size}: measured_valid(~Extra, codec, limits, catalog, base, file, size, U32.is_le(size, file_limit(limits)))

def opened(~Extra: Type, codec: Codec<Extra>, +limits: Limits, catalog: List<&2, Operation>, base: P.State, allowed: Bool, result: Result<&1, &1, U32 & String, File>) -> IO(Ready<Extra>):
  match result:
    case Fail{Tuple{2, message}}: missing(Extra, codec, allowed, base, extra_limit(limits), catalog)
    case Fail{Tuple{code, message}}: IO.die(Ready<Extra>, 1, "bundle startup refused: file open failed: " ++ U32.show(code) ++ ": " ++ message)
    case Done{file}:
      do IO<Ready<Extra>>:
        size : File & Result<&1, &1, U32 & String, U32> <- File.size(file)
        measured(~Extra, codec, limits, catalog, base, size)

def identified(~Extra: Type, codec: Codec<Extra>, +limits: Limits, catalog: List<&2, Operation>, world: C.World, +path: String, allowed: Bool, lease: WL.Lease, identity: R.Registry & Result<&2, &2, String, String>) -> IO(Ready<Extra>):
  (registry, status) = identity
  match status:
    case Fail{message}: IO.die(Ready<Extra>, 1, "bundle startup refused: registry identity failed: " ++ message)
    case Done{id}:
      do IO<Ready<Extra>>:
        file : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
        opened(~Extra, codec, limits, catalog, P.State{G.Engine{world, registry}, id, path, 0, P.Limits{core_limits(limits), file_limit(limits)}, lease}, allowed, file)

def load_engine(~Extra: Type, codec: Codec<Extra>, limits: Limits, catalog: List<&2, Operation>, path: String, allowed: Bool, lease: WL.Lease, engine: G.Engine) -> IO(Ready<Extra>):
  G.Engine{world, registry} = engine
  identified(~Extra, codec, limits, catalog, world, path, allowed, lease, R.Registry.identity(registry))

def leased(~Extra: Type, codec: Codec<Extra>, limits: Limits, catalog: List<&2, Operation>, path: String, allowed: Bool, result: Result<&1, &1, U32 & String, WL.Lease>) -> IO(Ready<Extra>):
  match result:
    case Fail{Tuple{code, message}}: IO.die(Ready<Extra>, 1, "bundle startup refused: lease acquisition failed: " ++ U32.show(code) ++ ": " ++ message)
    case Done{lease}:
      do IO<Ready<Extra>>:
        engine : G.Engine <- G.load()
        load_engine(~Extra, codec, limits, catalog, path, allowed, lease, engine)

def setup(~Extra: Type, ~codec: Codec<Extra>, ~operations: Operations<Extra>, +limits: Limits) -> Result<&2, &2, String, List<&2, Operation>>:
  +catalog = operation_catalog(Extra, operations)
  do Result<&2, &2, String, List<&2, Operation>>:
    metadata_checked(codec_metadata(Extra, codec), limits)
    W.require(valid_catalog(128n, catalog, []), "invalid extension operation catalog: duplicate/reserved name or invalid schema")
    return catalog

def load_setup(~Extra: Type, codec: Codec<Extra>, +limits: Limits, checked: Result<&2, &2, String, List<&2, Operation>>) -> IO(Ready<Extra>):
  match checked:
    case Fail{message}: IO.die(Ready<Extra>, 1, "bundle startup refused: " ++ message)
    case Done{catalog}:
      do IO<Ready<Extra>>:
        path_result : Result<&1, &1, U32 & String, String> <- IO.get_env("MC_WORLD_PATH")
        +path : String <- P.required_path(path_result)
        missing_result : Result<&1, &1, U32 & String, String> <- IO.get_env("MC_WORLD_MISSING")
        allowed : Bool <- P.policy(missing_result)
        lease : Result<&1, &1, U32 & String, WL.Lease> <- WL.acquire(path ++ ".lock")
        leased(~Extra, codec, limits, catalog, path, allowed, lease)

# Runtime catalogs/settings are captured by the codec closures. Validate only
# their metadata before passing the single codec owner into the existing loader.
def setup_metadata(-Extra: Type, metadata: String & U32, operations: Operations<Extra>, +limits: Limits) -> Result<&2, &2, String, List<&2, Operation>>:
  +catalog = operation_catalog(Extra, operations)
  do Result<&2, &2, String, List<&2, Operation>>:
    metadata_checked(metadata, limits)
    W.require(valid_catalog(128n, catalog, []), "invalid extension operation catalog: duplicate/reserved name or invalid schema")
    return catalog

def load_codec(~Extra: Type, ~operations: Operations<Extra>, codec: Codec<Extra>, +limits: Limits) -> IO(Ready<Extra>):
  Codec{+namespace, +schema, encode, decode, fresh, legacy} = codec
  load_setup(~Extra, Codec{namespace, schema, encode, decode, fresh, legacy}, limits,
    setup_metadata(Extra, (namespace, schema), operations, limits))

def load_with(~Extra: Type, ~codec: Codec<Extra>, ~operations: Operations<Extra>, +limits: Limits) -> IO(Ready<Extra>):
  load_codec(~Extra, ~operations, codec, limits)

def load(~Extra: Type, ~codec: Codec<Extra>, ~operations: Operations<Extra>) -> IO(Ready<Extra>):
  load_with(~Extra, ~codec, ~operations, default_limits())
