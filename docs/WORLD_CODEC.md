# Checked foundation world snapshots

`src/world_codec.bend` saves and restores every field of the current
`Core.World`: the clock, pause and daylight flags, revision and state count,
every owned section and cell, the complete typed pending queue, and the newest
core event ring. It uses the pure Bend uncompressed NBT codec. It contains no
IO, compression, foreign routine, unsafe definition, axiom, or unfilled law.

This is the versioned **Bendex foundation snapshot format**, pinned to Minecraft
26.3. It is not the Java Minecraft chunk, region, entity, player, or mod save
format. Those complete game persistence semantics remain separate work.
Confidence is high in the native fixture results and independent kernel checks;
these do not establish a universal snapshot roundtrip or crash recovery theorem.

## API and ownership

```python
type Limits is Data:
  Limits{nbt: N.Limits, max_sections: U32, max_map_nodes: U32,
    max_nat_digits: U32, max_string_units: U32}

type Loaded is Type:
  Loaded{world: Core.World, max_peer: Maybe<&2, U32>}

encode(world: Core.World, registry_identity: String)
  -> Core.World & Result<&2, &2, String, List<&2, U32>>
encode_with(limits: Limits, world: Core.World, registry_identity: String)
  -> Core.World & Result<&2, &2, String, List<&2, U32>>
decode(bytes: List<&2, U32>, expected_state_count: U32,
  expected_registry_identity: String) -> Result<&2, &1, String, Loaded>
decode_with(limits: Limits, bytes: List<&2, U32>, expected_state_count: U32,
  expected_registry_identity: String) -> Result<&2, &1, String, Loaded>
```

Encoding returns the same world owner on success and failure. Its traversal
rebuilds the original owned trie, collision buckets, and arrays without changing
cell values or bucket order. It checks the raw public constructors before using
array indices: each section must have precisely a balanced 12-level binary
array containing 4096 leaves. Checking `Array.size` alone would be insufficient,
because Base computes that size from the left branch. Wrong shapes, wrong hash
paths, empty buckets, duplicate keys, or invalid states produce explicit errors
in the checked definitions. The native runtime uses flat arrays and rejects
unequal child allocation classes during `ANode` construction, before the codec
can be invoked; that separate constructor fail-stop is reproduced without the
codec in `evidence/world-codec-array.json`. Native wrong-size balanced arrays
reach the encoder and return its explicit error with their owner preserved.
A finite independent-kernel fixture also checks the abstract unequal-child
shape error and exact original owner return.

Decoding first checks the entire NBT schema into Data records. It publishes an
owned world only after validating every field, every cell, and every queued
operation and historical event. It constructs balanced arrays and the concrete
section map from those checked records. Missing sections remain missing; there
is no implicit air reconstruction. Raw trie shape and collision bucket insertion
order are implementation representation, while every exact key and cell is
persisted. The wire section order is deterministic and independent of that
representation.

`registry_identity` is supplied by the caller and compared exactly on load.
The codec does not invent or weaken the identity algorithm. The caller must use
an identity that binds the registry whose state IDs it supplies. A state count
of zero is representable for an empty foundation world; it permits no cells or
queued block/section state values.

## Wire schema

The named root is `bendex:world`, with a Compound payload. Each Compound has
exactly its specified fields. Decode accepts any member order but rejects
unknown, missing, or duplicate fields. Encode emits the order in this table.

| Root field | NBT type | Meaning |
| --- | --- | --- |
| `format` | Int | Exactly 1 |
| `minecraft` | String | Exactly `26.3` |
| `registry` | String | Caller identity, exact equality |
| `state_count` | Int | Raw U32 state count, equals expected count |
| `tick` | String | Canonical nonnegative Nat decimal |
| `day_time` | String | Canonical nonnegative Nat decimal |
| `paused` | Byte | Exactly 0 or 1 |
| `daylight` | Byte | Exactly 0 or 1 |
| `revision` | String | Canonical nonnegative Nat decimal |
| `sections` | List of Compound | Unique, strictly ascending section keys |
| `pending` | List of Compound | Complete future queue in scheduler order |
| `events` | List of Compound | Complete newest-first event ring |

Every section Compound has `key: String` and `cells: IntArray`. Its key must be
`dimension/x/y/z`, where dimension is exactly `minecraft:overworld`,
`minecraft:the_nether`, or `minecraft:the_end`. Coordinates are the canonical
unsigned decimal spelling of the section's raw U32 two's-complement bits,
matching `Core.section_key`. The signed section range is -134217728 through
134217727; for example, section -1 is spelled `4294967295`. There are exactly
4096 cells, ordered by index `x + 16*z + 256*y`, and every raw U32 state is less
than the persisted/expected state count. The actual FNV-1a collision between
`minecraft:overworld/12009114/36153475/77999535` and
`minecraft:overworld/21442934/118325841/132352103` is preserved as two distinct
keys and independently tested.

Every pending entry has `tick: String`, `peer: Int`, `sequence: String`, and
`mutation: Compound`. Stamps are nondecreasing under the existing scheduler's
lexicographic `(tick, peer, sequence)` comparison, and every tick must be greater
than the world tick. Equal stamps retain every operation and its exact order;
no deduplication occurs. The pending capacity is 4096.

Mutation Compounds use `kind: Byte` and exactly the following additional fields:

| Kind | Mutation | Additional fields |
| --- | --- | --- |
| 0 | SectionCreate | `dimension: String`, `x/y/z: Int`, `state: Int` |
| 1 | BlockSet | `dimension: String`, `x/y/z: Int`, `state: Int` |
| 2 | TimeSet | `day_time: String` |
| 3 | DaylightSet | `enabled: Byte`, exactly 0 or 1 |

Position coordinates preserve every world U32 bit pattern. Dimensions must be
known and state IDs must be less than the state count. A queued operation may
later fail because its target section does not exist or already exists; the
codec preserves the operation rather than attempting it during load.

Every event has the stamp fields `tick`, `peer`, and `sequence`, plus `kind:
Byte`. Applied kind 0 has `revision: String`, which must be positive and no
greater than the world revision. Rejected kind 1 has `error: Compound`. Events
are nonincreasing by scheduler stamp, every event tick is at most the world
tick, and the ring contains at most 1024 entries. Applied revision payloads are
range checked; no additional ordering constraint is imposed on those payloads.

Error Compounds have `kind: Byte` and these exact additional fields:

| Kind | Core error | Additional fields |
| --- | --- | --- |
| 0 | PermissionDenied | None |
| 1 | UnknownDimension | `dimension: String`, retained as historical text |
| 2 | InvalidState | `state: Int`, any raw U32 |
| 3 | MissingSection | `key: String`, canonical section key |
| 4 | SectionExists | `key: String`, canonical section key |
| 5 | InvalidCoordinate | None |
| 6 | PastTick | None |
| 7 | TooManyPending | None |

Historical errors need not still describe the current world: a missing section
may since have been created, and an UnknownDimension payload is retained even
when its string currently names a known dimension. Historical invalid state
values are not silently clamped or rejected for exceeding the current count.

## Numeric, text, and resource bounds

The installed Bend 2.0.35 native runtime stores Nat in **48 bits**, not U32 or
U64. Native `Nat.read` observations and compiler-source evidence are recorded
in `evidence/world-codec-nat.json`. Every Nat-bearing field is canonical decimal
text with no sign, whitespace, or leading zero except `0`. Before constructing
a Nat, the codec checks decimal length and compares the 15-digit boundary
lexically against `281474976710655`. This also rejects thousands of input
digits without native truncation. Raising `max_nat_digits` never enlarges the
hard native range. Encoding routes its decimal output through the same check,
so a theoretical checker Nat above the native range has an explicit error path.
The foundation clock remains Nat; migration to Java signed-64-bit time is
separate future work.

Strings follow Java modified UTF-8 on wire, via the NBT codec, and scalar Bend
Unicode in world fields. NUL and non-BMP scalar values roundtrip correctly.
Valid surrogate pairs are converted to one scalar; isolated surrogates and
invalid raw Bend characters are rejected. Valid overlong DataInput modified
UTF-8 spellings are accepted and written canonically on re-encoding. A canonical
encoded NBT string must fit the format's 65535-byte length independently of the
configurable UTF-16-unit bound. Ordinary four-byte UTF-8 is not substituted.

Defaults are explicit policy limits, not NBT or Minecraft format claims:

| Limit | Default | Scope |
| --- | --- | --- |
| NBT input/output bytes | 16777216 | Encode and decode |
| NBT nesting depth | 512 | Encode and decode |
| NBT elements per container | 1048576 | Encode and decode |
| Sections | 512 | Encode and decode |
| Raw owned map nodes | 65536 | Encoder ownership traversal |
| Nat decimal digits | 15 | Encode and decode, always also bounded to native 48 bits |
| UTF-16 units per world string | 65535 | Encode and decode |
| Pending queue | 4096 | Fixed current Core capacity |
| Event ring | 1024 | Fixed current Core capacity |

The raw map-node bound includes empty branches left by deletion. Decoder input
has no raw trie representation; it builds a canonical map from the independently
bounded checked section list. Limits can be narrowed or raised through
`encode_with`/`decode_with`; exceeding a relevant bound returns an error, never
a truncated world, queue, event ring, or byte stream.

## Peer identity after restart

`Loaded.max_peer` is the maximum raw U32 peer in **both** pending and event
stamps, or None if neither contains a stamp. Runtime connections and sessions
are not persisted. Transport restart must allocate subsequent identities above
that maximum before accepting cancellation-capable requests, so a new session
cannot cancel an older persisted `(peer, sequence)` identity. Some{4294967295}
means the peer namespace is exhausted; wrapping to zero would reuse identities.
The server's explicit exhaustion path must reject further allocation. A caller
may also persist a larger external high-water mark when coordinating other
identity consumers; the codec's metadata covers precisely the saved core state.

## Verification

Commands:

```sh
/Users/chuah/.bend/bin/bend src/world_codec.bend --check-only
/Users/chuah/.bend/bin/bend src/world_codec.bend --verdict
/Users/chuah/.bend/bin/bend tests/world_codec.bend --check-only
/Users/chuah/.bend/bin/bend tests/world_codec.bend --verdict
/Users/chuah/.bend/bin/bend tests/world_codec.bend -o build/world-codec-tests
build/world-codec-tests
python3 tools/test_world_codec.py
```

The final native run passed **875 independent fixtures: 181 accepted and 694
expected errors**, with 181 exact canonical roundtrips, 181 maximum-peer checks,
and four native constructed worlds matching independently specified bytes.
Source and harness both report `ALL PROOFS CHECK` under `--verdict`; the emitted
translation also passes the cached kernel directly. Results and exact source,
harness, binary, oracle, dependency, and corpus hashes are in
`evidence/world-codec-tests.json`, `evidence/world-codec-kernel.json`, and
`evidence/world-codec-regression.json`.

The independent Python runner assembles and validates NBT snapshots without
calling the Bend codec for expected results. It checks native canonical bytes,
peer metadata, generated valid snapshots, every typed mutation/error variant,
all Nat fields at and beyond the actual native boundary, zero-state worlds,
signed coordinates, the real hash collision, full capacities, malformed
schemas, wrong registry/count/version, duplicate keys, bad cells and stamps,
Unicode/MUTF cases, truncation and trailing bytes. Python orchestrates fixtures
only; it does not implement runtime world loading or saving.

Native builtins additionally check owner preservation across repeated encoding,
full decoded roundtrips, decoded pending actions executing at both scheduled
ticks, full owner recovery after a byte-limit error, correct-path duplicate
bucket rejection, malformed owned map/array rejection with the original
invalid array owner retained, invalid raw scalar strings, and configured limits.
Independent kernel evidence records the checked source translation and the
finite Nat boundary/overflow and abstract malformed-array helper laws. Kernel acceptance establishes the
checked definitions and those precise finite laws; it does not establish a
universal `decode(encode(world)) = world` theorem or save durability.
