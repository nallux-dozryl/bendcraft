# Foundation save and restart integration

`persistence_server.bend` runs the existing foundation Game through the
effectful server driver in `src/persistence.bend`. It saves the complete
current `Core.World` with the checked world codec and reloads it before opening
the loopback listener. Registry metadata is loaded independently and bound by
`Registry.identity`'s canonical SHA-256 identity. The single actor retains the
world, registry, and exclusive world lease throughout dispatch and publication.

This persists the current section-and-tick foundation. It does not implement
Minecraft region/chunk/entity/player/mod save formats, migrations, journaling,
backup generations, or physical power-loss recovery. There is no live load or
reset operation: active session replacement requires a future epoch/restart
architecture.

## Configuration and startup

```sh
/Users/chuah/.bend/bin/bend persistence_server.bend -o build/persistence-server
MC_WORLD_PATH=/absolute/stable/world.nbt \
MC_WORLD_MISSING=create \
MC_DEV_TOKEN=your-configured-token \
MC_LIVE_PORT=47163 \
build/persistence-server --threads 1 --gpu off
```

`MC_WORLD_PATH` is required and must be nonempty. `MC_WORLD_MISSING=create`
explicitly permits a fresh world when opening the configured file returns
ENOENT. `refuse`, or an absent `MC_WORLD_MISSING`, refuses a missing file. Other
policy strings fail startup. The create policy does not create parent
directories or recover an orphan temporary snapshot. Existing malformed,
truncated, incompatible, or unreadable files always fail startup; they are
never treated as empty worlds.

Startup acquires `MC_WORLD_PATH + ".lock"` through the existing narrow world
lease adapter **before registry loading, snapshot reading, or listening**.
A failed acquisition refuses startup. The affine lease remains inside
`Persistence.State`, across every tick, request, and save. The adapter uses an
exclusive nonblocking OS flock on a regular file, rejects symlinks for that
lock, and keeps the same lock inode; it does not unlink the lock file. Process
termination releases the OS lock. Separate persistence processes using the
same configured path therefore cannot both operate that world. Use a stable
canonical path and stable parent directory: the wrapper does not establish
global alias identity or protection against a hostile parent-directory actor.
See `docs/WORLD_LOCK.md` and its independent multi-process evidence.

After loading the validated registry, startup calculates its canonical
identity. It reads the configured binary file with the following explicit
bounds: `File.size` rejects files above U32; the persistence file limit is
checked before allocation; partial reads use chunks of at most 32768 bytes;
exactly the measured byte count and one extra EOF probe are required. The read
loop's fuel is the measured byte count, sufficient even for one-byte partial
reads; an empty read before completion is an explicit truncation error. The
file is closed on every handled read success or failure.

The full envelope and world schema, version, registry identity, state count,
all cells, pending operations, event history, and native numeric ranges are
validated before publishing any decoded owned world or opening the listener.
Registry-source corruption likewise fails before listening. The default block
registry remains `generated/reference_blocks.tsv`; `MC_BLOCK_REGISTRY` selects
an explicit alternate input through the existing Game loader.

## API and envelope

```python
type Limits is Data:
  Limits{world: WorldCodec.Limits, max_file_bytes: U32}

type State is Type:
  State{engine: Game.Engine, registry_identity: String, path: String,
    highwater: U32, limits: Limits, lease: WorldLock.Lease}

type Ready is Type:
  Ready{state: State, first_peer: U32}

load() -> IO(Ready)
load_with(limits: Limits) -> IO(Ready)
realtime_step(state: State) -> State
dispatch(state: State, session: Live.Session, token: String, request: Json.Value)
  -> IO(State & Live.Session & Json.Value)
```

The production entry invokes
`Server.run_effectful_from_peer` with that ready state and peer allocation.
The other Game, live API, core, and server modules retain their existing APIs.
The wrapper delegates every existing operation and adds one persistence tool.

The file is uncompressed NBT, with named root `bendex:save` and an exact
Compound schema. Decode accepts any field order and rejects duplicate,
missing, unknown, or incorrectly typed fields.

| Field | NBT type | Contract |
| --- | --- | --- |
| `format` | Int | Exactly 1 |
| `minecraft` | String | Exactly `26.3` |
| `registry` | String | Exact current canonical Registry.identity |
| `peer_highwater` | Int | Raw U32 maximum observed session peer |
| `world` | ByteArray | Complete uncompressed WorldCodec snapshot bytes |

The inner root and schema are documented in `docs/WORLD_CODEC.md`. The loaded
registry identity has exactly 64 lowercase hexadecimal SHA-256 characters;
it hashes parsed metadata in the documented canonical v1 format, preserving
block/property/domain order and strict UTF-8 string bytes, independently of
TSV/JSON whitespace and unused array capacity. The pinned official metadata
identity is `4f75fa335a12e34cf74be71ff6a0ee530b13233212423f5463bb26a2fe4f3cfc`.
A same-count sibling registry with changed metadata is incompatible.

Defaults are `WorldCodec.default_limits()` and a **16781312-byte file limit**
(16 MiB plus 4 KiB for this fixed envelope). Outer NBT depth is at most 4;
its container-count bound is the minimum of the file bound and the configured
inner world NBT byte bound, which is 16 MiB by default. Thus an oversized world
ByteArray is rejected at its declared length before allocating its decoded
payload. The outer input byte list is still read and scanned first. Policy
limits are explicit and configurable; no world, queue, event, or byte stream is
truncated to fit them. The existing inner hard native Nat range remains
`0..281474976710655` even if a configurable digit count is raised.

## Live save behavior

Discovery appends `world.save` to the actual current Game catalog, with its
exact live request schema: developer capability, empty arguments, and no `at`
field. No caller-supplied path or load/reset operation is exposed. The same
actual discovery feeds MCP tool names and schemas through the existing stdio
bridge; it needs no persistence-specific operation whitelist.

The wrapper observes the request's peer before dispatching every actual
request, including discovery, failed requests, and save itself. Save first
checks that the world's state count equals the loaded registry count, encodes
the entire world while retaining its owner, and encodes the envelope. Encoding
errors return `SaveEncodingFailed` and preserve the state owner.

It then calls the existing `Atomic.publish` with suffix
`save-<peer>-<session-sequence>`. Atomic publication exclusively creates the
adjacent temporary file, writes its bytes, syncs the file, renames it into the
configured destination, and syncs the parent directory. A colliding stale or
unowned temporary path is an explicit failure; the wrapper does not delete it,
retry under an invented name, or overwrite it. There is no orphan-recovery
claim. Completed publication replaces the whole snapshot at one actor point;
queued actions and events are preserved, and later live changes remain unsaved
until another successful publication.

| Atomic outcome | Live result |
| --- | --- |
| Durable | `ok: true`, status `durable`, `published: true`, `durable: true` |
| PublishedUnsynced | `ok: true`, status `published_unsynced`, `published: true`, `durable: false`, original OS code/message |
| NotPublished | `ok: false`, error code `SaveNotPublished`, original OS code/message |

Successful/publication results also include the total envelope byte count and
saved peer high-water mark. `ok: true` for PublishedUnsynced acknowledges
publication only; its status and Boolean explicitly say that durability was
not acknowledged. The wrapper reports the adapter's actual outcome and never
promotes it to Durable. The PublishedUnsynced native helper fixture is a finite
response-shape check, not an injected or observed OS directory-sync failure.
Every outcome returns the owned engine and lease, allowing subsequent queries,
actions, or another save.

## Peer identity after restart

Runtime sessions and their capability/sequence state are not persisted. The
saved peer high-water mark includes observed sessions with no mutation stamp,
including the save caller. Startup combines it with the maximum peer in both
inner pending actions and events, then begins allocation at that maximum plus
one. This prevents a new session from sharing an older persisted cancellation
identity. Maximum U32 means the namespace is exhausted and refuses startup;
there is no wrap to zero. Active idle connections without a dispatched request
are not an observed persistence identity and have no persisted cancellation
state. A future broader identity consumer must coordinate its own high-water
metadata with this contract.

## Verification and measured boundaries

```sh
/Users/chuah/.bend/bin/bend persistence_server.bend -o build/persistence-server
/Users/chuah/.bend/bin/bend tests/persistence.bend -o build/persistence-tests
/Users/chuah/.bend/bin/bend mcp.bend -o build/persistence-mcp
build/persistence-tests
build/persistence-tests outcome
python3 tools/test_persistence.py
```

The independent Python runner drives actual native TCP clients and the actual
native MCP stdio bridge. It checks discovery and permission/schema errors,
canonical registry identity and both independent NBT layers, two signed/
dimension sections, paused clock state, typed future actions and event history,
publication, real SIGKILL, fresh sessions after restart, restored state and
future-action execution, and exclusion of later unsaved changes. It also checks
actual same-world lease contention, reacquisition of the same lock inode after
SIGKILL, exclusive temporary-file collision with unchanged old bytes and
continued live owner use, incompatible sibling registries, source corruption,
and binary/schema/limit startup failures with no listener.

The final recorded run passed nine check groups. Seven physical saves matched
independently constructed outer and inner NBT bytes exactly. Its 105 actual
startup refusals include 95 malformed NBT fixtures; two actual SIGKILL/restart
cycles and one actual exclusive-create save failure passed. Six ready native
servers and nine native MCP processes exchanged 65 matching stdio request and
response pairs. All 29 recorded source/adapter/oracle hashes and three native
binary hashes matched before and after execution. The reproducible observations
and exact scope are in `evidence/persistence-integration.json`.

Near-limit rejected input has a measured cost. The first oversized inner
ByteArray probe rejected correctly after 30.783 seconds with about 1.50 GiB
peak child RSS because generic outer decoding allocated its payload before
checking the inner limit. Applying that existing limit at the outer length
header reduced the measured probe to 15.366 seconds and 807534592 bytes of peak
child RSS. The corrected process exited 1 without a ready message or listener.
The same input rejected in 14.747 seconds in the final complete integration run.
The runner uses a documented 60-second deadline for near-limit file fixtures;
that testing deadline is not a format policy or silent work cap. Exact probe
hashes and provenance qualifications accompany integration evidence. This
foundation path makes no performance advantage claim over Minecraft or a
host-language save implementation.

The pure world/NBT codecs have independent kernel acceptance with their stated
finite helper laws. The persistence wrapper imports existing Atomic OS effects
and the world-lease adapter. Its `--check-only` result explicitly identifies
those foreign/unsafe-dependent definitions and their transitive save/startup
callers; it does not certify the complete effectful program. Native compilation
checks the remaining definitions and ownership typing, and actual OS/network
integration verifies observed behavior. No new unsafe definition, native effect,
compiler change, axiom, universal persistence theorem, or physical power-loss
claim is introduced by the wrapper. Existing Atomic interruption evidence and
world-lease evidence retain their precise separate scopes.

Confidence is high for the recorded native ownership, schema, identity, process
crash, lease, and OS-error observations. Physical power-loss behavior and
universal end-to-end effectful correctness remain unestablished. The exact
compiler diagnostics and source hashes are recorded separately in
`evidence/persistence-proof-boundary.json`.
