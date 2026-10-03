# Typed extension bundles

`src/extended_persistence.bend` atomically saves one checked `Core.World` and
one affine extension owner in the same uncompressed NBT file. It reuses the
existing registry identity, bounded file reader, world codec, atomic publication,
exclusive world lease, and effectful transport. The existing core-only
persistence and client/server entries are unchanged.

This is a foundation extension ABI. The demonstrated extension is an eight-cell
owned `Array<U32>` with a generation number; it is not a player, inventory, mod,
entity, vanilla chunk, or Minecraft save implementation. A future player/mod
composition can supply a typed product of its owners and a checked codec for
that product. This wrapper does not load executable plugin source from disk.

## Closed API

```python
type Codec<-Extra: Type> is Type:
  Codec{namespace: String, schema: U32,
    encode: Extra -> Extra & Result<&2, &2, String, List<&2, U32>>,
    decode: U32 -> List<&2, U32> -> Result<&2, &1, String, Extra>,
    fresh: Unit -> Result<&2, &1, String, Extra>,
    core_only: Unit -> Result<&2, &1, String, Extra>}

type Operation is Data:
  Operation{name: String, access: Live.Access,
    fields: List<&2, Live.Field>, description: String}

type Operations<-Extra: Type> is Type:
  Operations{catalog: Unit -> List<&2, Operation>,
    dispatch: Game.Engine -> Extra -> Live.Session -> Live.Envelope
      -> Game.Engine & Extra & Result<&2, &2, Live.Fault, Json.Value>}

type Limits is Data:
  Limits{world: WorldCodec.Limits,
    max_extension_bytes: U32, max_file_bytes: U32}

type State<-Extra: Type> is Type:
  State{base: Persistence.State, extra: Extra,
    max_extension_bytes: U32, catalog: List<&2, Operation>}

type Ready<-Extra: Type> is Type:
  Ready{state: State<Extra>, first_peer: U32}

type Loaded<-Extra: Type> is Type:
  Loaded{world: Core.World, extra: Extra, highwater: U32}

load(~Extra, ~codec, ~operations) -> IO(Ready<Extra>)
load_with(~Extra, ~codec, ~operations, limits) -> IO(Ready<Extra>)
realtime_step(-Extra, state) -> State<Extra>
dispatch(~Extra, ~codec, ~operations, state, session, token, request)
  -> IO(State<Extra> & Live.Session & Json.Value)
encode(~Extra, ~codec, state)
  -> State<Extra> & Result<&2, &2, String, List<&2, U32>>
decode(~Extra, ~codec, limits, bytes, state_count, registry_identity)
  -> Result<&2, &1, String, Loaded<Extra>>
```

The public codec/dispatch/load functions receive `~codec` and `~operations` as
**closed compile-time template values**. Their function fields have ordinary
affine parameter quantities; callbacks with reusable `+` parameters need an
ordinary adapter matching the declared function type. Reusable runtime function
closures are not stored in the state or read from the save.

`Persistence.State` inside `base` owns the sole `Game.Engine` and sole acquired
world lease. The extension owner sits beside it. A save error returns the entire
state, including both owners and the lease. The ABI enforces affine use; it does
not prove arbitrary supplied codecs preserve their owners' semantic contents or
that a namespace/version authenticates source code. Those properties belong to
the actual closed codec's checked implementation and laws.

## Envelope and bounds

The named root is `bendex:bundle`, an exact Compound schema:

| Field | NBT type | Contract |
| --- | --- | --- |
| `format` | Int | Exactly 1 |
| `minecraft` | String | Exactly `26.3` |
| `registry` | String | Exact loaded canonical Registry.identity |
| `peer_highwater` | Int | Raw U32 maximum observed session peer |
| `core` | ByteArray | Complete checked WorldCodec snapshot |
| `extension` | Compound | Exact extension fields below |

The extension Compound contains exactly `namespace: String`, `schema: Int`,
and `payload: ByteArray`. Namespace must equal the closed codec's namespace.
Schema is a nonzero raw U32; the codec's checked decoder decides exactly which
versions and migrations it supports. The writer always declares the codec's
current schema. All Compounds accept arbitrary member order and reject missing,
duplicate, unknown, or incorrectly typed fields. Both inner payload decoders
must reject their own trailing data; the outer NBT parser rejects trailing data.

The default world policy is `WorldCodec.default_limits()`, extension payload
budget is **65536 bytes**, and whole-file budget is **16846848 bytes**
(16 MiB + 64 KiB + 4 KiB envelope allowance). These policies are configurable
through `load_with`; no payload or owned state is truncated to fit them.
The inherited hard native Nat boundary is `0..281474976710655`.

Namespace and operation/argument names use 1–128 ASCII characters from
`a-z`, `0-9`, `.`, `_`, `:`, and `-`. Codec schema zero and extension budgets
above signed NBT array-length capacity are rejected. The typed catalog policy
allows at most 128 operations, 64 fields per operation, 64 text-enumeration
members per field, and 1024 characters per description. These are explicit
wrapper policy limits, not restrictions of physical NBT or Minecraft formats.

The file reader checks the whole-file budget before allocation and reads exactly
the measured size, followed by an EOF probe. Its raw Data byte list already
exists when parsing starts: this is not streaming file decoding. A custom checked
NBT stepping wrapper intercepts each core/extension ByteArray header. It checks
the **separate field budget before allocating a decoded payload**, including
negative/excessive array lengths. Lists and numeric arrays are not allowed in
the outer schema. Generic NBT handles modified UTF-8, scalar bits, Compound
framing, depth, and byte validation; no host decoder supplies runtime semantics.

The wrapper independently scans every encoder-produced payload for byte values
and its budget before publishing, even when a hook ignores that budget. It also
runs canonical owner-retaining encode and byte-budget validation after fresh
initialization, decode, and migration, before adopting a ready state. A hook
must validate its own complete private representation and bound its own
allocation behavior; the wrapper cannot inspect an abstract `Extra` or prove
an arbitrary callback's semantic correctness.

## Catalog, dispatch and ownership

Startup validates the closed typed operation catalog before acquiring state or
opening a listener. Names must be unique and cannot match any current Core/Game
operation, `discover`, or `world.save`. Field names must be unique and unsigned
bounds must be ordered. The wrapper derives each exact JSON request schema from
`Live.Field`; a hook cannot supply an unrelated arbitrary JSON schema.

Every actual dispatched request observes its peer in the inherited high-water
metadata. Invalid envelopes and ordinary Core/Game operations delegate to the
existing Game dispatcher. Discovery, save, and recognized extension requests
increment session sequence exactly once in the wrapper; delegated requests
increment once in Game. Session authentication, error envelopes and peer
allocation retain the existing transport behavior.

For an extension request the wrapper validates its strict arguments, refuses
`at`, and checks Public/DeveloperOnly capability **before invoking the hook**.
The hook receives that validated envelope and once-incremented session and must
return both the engine and extension owner on every success or error. The
catalog determines routing; it cannot silently intercept reserved operations.
Discovery appends the exact bundle `world.save` descriptor and typed extension
catalog to actual Game discovery. The existing MCP bridge discovers their names
and schemas through the real transport without an extension whitelist.

One actor serializes both owners before one `Atomic.publish` call. There is no
extension sidecar or second publication point. The file therefore contains the
core and extension from the same actor transition. An extension can encode a
private generation field for its own contract; this wrapper does not fabricate a
global cross-owner generation number.

Publication uses the existing adjacent exclusive temporary-file suffix
`save-<peer>-<session-sequence>`. Outcomes retain the core-only live response
shape: Durable reports `published: true, durable: true`; PublishedUnsynced reports
`published: true, durable: false` and the original OS code/message; NotPublished
returns `SaveNotPublished`. Encoding or budget errors return `SaveEncodingFailed`.
The byte count covers the complete bundle. Every outcome returns every owner;
unsynced publication is never promoted to a durable acknowledgment.

## Startup, migration and peer identity

Startup requires `MC_WORLD_PATH` and acquires the adjacent `.lock` before registry
loading, binary reading, or listening. Missing files require the explicit
`MC_WORLD_MISSING=create` policy and a successful `fresh` hook. Existing malformed
or incompatible files are never treated as fresh. Both payloads, version,
namespace, identity, count, and limits must validate before replacing the engine's
world or adopting the extension owner. Any migration error refuses startup.

An old `bendex:save` core-only envelope enters only the closed `core_only` hook.
The default example hook returns Fail. An explicitly selected migration/init
hook may initialize an extension after strict old-core validation; it does not
pretend an absent extension was persisted. An existing extension bundle always
enters its decoder and cannot silently become a fresh or core-only world.

Runtime sessions are not persisted. The bundle high-water mark includes all
observed request peers, including save callers and extension-only requests.
Startup combines it with the maximum pending/event peer in the core codec and
allocates from maximum plus one. U32 exhaustion refuses startup. Future extension
identities using transport peers must coordinate their own persisted maxima;
this ABI does not infer peer references inside abstract extension bytes.

## Example and verification

```sh
/Users/chuah/.bend/bin/bend extended_persistence_server.bend -o build/extended-persistence-server
/Users/chuah/.bend/bin/bend tests/extended_persistence.bend -o build/extended-persistence-tests
MC_WORLD_PATH=/absolute/stable/bundle.nbt MC_WORLD_MISSING=create \
MC_DEV_TOKEN=your-token MC_LIVE_PORT=47163 \
build/extended-persistence-server --threads 1 --gpu off
python3 tools/test_extended_persistence.py
```

The example uses the actual Array codec in `tests/extended_persistence.bend`.
Its namespace is `bendex:fixture-array`, current schema is 2, and its payload is
named-root `bendex:fixture-array` with exactly `cells: IntArray` (eight raw U32
values) and `generation: Int` (raw U32). Schema 1 contains exactly `cells` and
migrates to generation zero. Other schemas fail. Array shape is validated before
encoding; decode allocates the owned balanced Array after all payload fields and
cardinality checks. Generation exhaustion is an explicit mutation error.

`extra.get` is a public observer query; `extra.set` is developer-only with strict
`index: 0..7, value: 0..U32MAX`; `extra.block` is developer-only with strict
`blocked: Bool`. All refuse `at`. Responses contain all eight cells, generation,
and blocked flag. The deliberate blocked flag prevents encoding, preserves the
owner, and is never persisted. Clearing it allows the same state to save again.

The example-only `MC_BUNDLE_FIXTURE=core-init` explicitly selects its closed
core-only initializer. The normal mode refuses core-only snapshots. Other fixed
compiled choices exercise setup/fresh/budget failures (`reserved`, `duplicate`,
`invalid-schema`, `bad-namespace`, `bad-schema`, `fresh-fail`, `small-budget`).
Unknown choices refuse startup. Production player composition should directly
choose its own closed hooks rather than use this fixture configuration.

The independent actual native TCP/MCP runner recorded ten exact-byte durable
bundle saves, 95 actual startup refusals (85 malformed bundles), real SIGKILL and
restart, lease contention/reacquisition, schema migration, explicit core-only
init/refusal, generation exhaustion, and owner reuse after an encoder failure
and an actual exclusive-temp OS failure. Main integration uses the full pinned
35723-state registry. A valid five-section Core payload above 64 KiB verifies
that the extension budget is not incorrectly applied to Core. Python supplies
independent NBT bytes and protocol/process orchestration; the actual codecs,
mutations, publication and reload run in native Bend.

The final native run used seven ready servers and fifteen actual MCP processes,
with 108 matching stdio request/response pairs. All 33 recorded source/oracle
hashes and three binary hashes matched at the start and end and in a final
independent integrity audit.

The isolated proof artifact contains the verbatim production field-budget and
header guards, actual Array encoder/decoder, and four finite laws. The independent
kernel accepts those definitions and laws: declared over-budget extension header
rejection before any body read, encoder budget rejection, unsupported fixture
schema rejection, and malformed balanced Array encoding with exact owner return.
A declaration-name-only import-alias shim copies the pure `P.nbt_byte_limit` body
so unrelated OS effects need not be imported. This does not certify the entire
extension wrapper or arbitrary future codecs.

The full wrapper imports existing OS/process effects and JSON. Its full proof
commands retain those explicit boundaries; native compilation and integration
are separate evidence. Both wrapper `--check-only` and `--verdict` exit at the
explicit 42-definition unsafe/foreign dependency diagnostic; the example entry
identifies 57 such definitions including existing transport lifetimes. The
isolation generator, exact extracted declaration hashes, translation hash and
direct cached-kernel command are recorded in the kernel evidence. There is no
universal complete bundle roundtrip,
migration, plugin authenticity, journal/orphan recovery, physical power-loss,
vanilla save parity, or performance advantage claim. Schema-valid changed values
are not detected by a file checksum. Confidence is high for the recorded native
and isolated pure-kernel observations; universal effectful and physical-power-loss
claims remain unestablished. See `evidence/extended-persistence-integration.json`
and `evidence/extended-persistence-kernel.json`.
