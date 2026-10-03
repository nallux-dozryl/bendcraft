# Pure Bend uncompressed NBT

`src/nbt.bend` implements the physical Java NBT binary format in pure Bend.
It imports only Base and contains no IO, foreign routine, unsafe definition,
axiom, or unfilled law. It decodes and encodes all tag IDs 0 through 12,
retaining raw numeric bits, named roots, UTF-16 text units, list element types,
and compound member order. Compression, region files, save migration,
world recovery, and the logical Minecraft tag-object transformations are
outside this codec.

Confidence is high in the verified reference observations and native fixture
results reported below. The finite tests and kernel checks do not establish a
general NBT correctness or Minecraft persistence theorem.

## Public API and representation

```python
type Word64 is Data:
  Word64{hi: U32, lo: U32}

type Text is Data:
  Text{units: List<&2, U32>}

type Value is Data:
  End{}
  Byte{bits: U32}
  Short{bits: U32}
  Int{bits: U32}
  Long{bits: Word64}
  Float{bits: U32}
  Double{bits: Word64}
  ByteArray{values: List<&2, U32>}
  StringTag{text: Text}
  ListTag{element: U32, values: List<&2, Value>}
  Compound{members: List<&2, Member>}
  IntArray{values: List<&2, U32>}
  LongArray{values: List<&2, Word64>}

type Member is Data:
  Member{name: Text, value: Value}

type Root is Data:
  Root{name: Text, value: Value}

type Limits is Data:
  Limits{max_bytes: U32, max_depth: U32, max_elements: U32}

default_limits() -> Limits
tag(value: Value) -> U32
decode(bytes: List<&2, U32>) -> Result<&2, &2, String, Root>
decode_with(limits: Limits, bytes: List<&2, U32>) -> Result<&2, &2, String, Root>
encode(root: Root) -> Result<&2, &2, String, List<&2, U32>>
encode_with(limits: Limits, root: Root) -> Result<&2, &2, String, List<&2, U32>>
```

Byte lists are bounded Data lists. Each element must be in `0..255`; decode
checks this before parsing. There is no host byte-array conversion in the
codec. `Byte.bits` and byte-array elements are raw eight-bit patterns;
`Short.bits` is a raw sixteen-bit pattern. For example, signed byte `-1`
is represented by `Byte{255}`, not a negative Bend integer.

`Int.bits` and int-array elements retain all 32 bits. `Word64` stores the high
32 bits followed by the low 32 bits, for both signed long patterns and binary64
patterns. Float and double never pass through Bend numeric conversions.
Negative zero, signaling and quiet NaNs, payload bits, infinities, subnormals,
and integer extrema therefore survive unchanged. All multi-byte integers and
numeric payloads use big-endian order.

`Text.units` stores Java UTF-16 code units in `0..65535`, including isolated
surrogates. It is deliberately distinct from a Bend scalar `String`. Examples:

```python
Text{Nil{}}                              # empty Java string
Text{65 <> 0 <> Nil{}}                    # A followed by NUL
Text{55357 <> 56832 <> Nil{}}             # U+1F600 encoded as a UTF-16 pair
Text{55296 <> Nil{}}                     # isolated high surrogate U+D800
```

The root is a tag byte, a modified-UTF-8 name, and its payload. The special
`End{}` root is exactly one zero byte and must have an empty name. Generic
non-End roots may have any known value tag. A list stores a one-byte declared
element ID, a signed nonnegative 32-bit element count, and homogeneous payloads
without names or per-element tag bytes. A compound stores named entries followed
by an End terminator. End cannot be an ordinary compound member or a list
payload. Empty lists can declare any known ID `0..12`, including zero;
nonempty lists must declare `1..12` and all values must match that ID.

The AST preserves compound member order and duplicate entries. It does not
replace duplicates, sort names, unwrap special list compounds, or infer
Minecraft-specific field meanings. Official structure palette fields are
lowercase `id` and `properties` in 26.3; the codec keeps these names exactly.

## Verified 26.3 string encoding

The installed pinned 26.3 classes `net.minecraft.nbt.StringTag$1` and
`net.minecraft.nbt.CompoundTag$1` call `java.io.DataInput.readUTF`.
Java 25 `DataOutputStream.writeUTF` writes canonical **modified UTF-8**:

| UTF-16 unit | Canonical bytes |
| --- | --- |
| U+0000 | `c0 80` |
| U+0001–U+007F | One byte |
| U+0080–U+07FF | Two bytes |
| U+0800–U+FFFF, including surrogate units | Three bytes |

A supplementary scalar becomes two UTF-16 units and therefore six bytes;
U+1F600 is `ed a0 bd ed b8 80`, not ordinary UTF-8 `f0 9f 98 80`.
A two-byte unsigned length counts encoded bytes, with a maximum of 65,535.
That is a format limit, independent of the configurable resource policy.

Actual Java probes established that `readUTF` accepts literal zero bytes,
overlong two- and three-byte encodings, and isolated UTF-16 surrogates. The Bend
decoder matches this liberal one/two/three-byte behavior and checks continuation
bytes and declared byte boundaries. It rejects four-byte UTF-8 leaders, stray
continuations, invalid leaders, partial characters, and truncated input.
The encoder always writes canonical modified UTF-8. Therefore a successfully
decoded noncanonical string can change bytes when encoded again. A decoded
string whose canonical encoding exceeds 65,535 bytes is retained by `decode`
but rejected by `encode`, as Java `writeUTF` also does.

The exact probes, pinned client/server hashes, named classes, Java version, and
observed results are recorded in `evidence/nbt-reference-java.json`.

## Resource and rejection policies

The default limits are:

| Resource | Default |
| --- | ---: |
| Input bytes and encoded output bytes | 16,777,216 |
| Simultaneously open list/compound containers | 512 |
| Elements in each array/list or members in each compound | 1,048,576 |

These are explicit codec policies, configurable through `Limits`. They do not
redefine the NBT format. A scalar root has container depth zero; a root list or
compound has depth one. Array payloads do not add list/compound depth. Empty
containers are allowed with a zero element limit. A zero byte limit rejects
all roots. Decoded offsets are zero-based byte positions; low-level truncation
and text errors include an offset, while policy/tag/type errors may be global.

Decode rejects unknown tag IDs, including unknown declared IDs on empty lists;
negative array/list lengths; excessive lengths or nesting; truncated headers,
strings, scalars and array elements; invalid modified UTF-8; and trailing data.
The strict trailing policy consumes exactly one root and requires EOF. Encode
checks manually constructed values for byte/short/unit ranges, encoded text
length, homogeneous list typing, known element IDs, End placement, depth,
element limits, and total output size. Counts are checked against the signed
NBT count range before they are emitted.

Both decoder and encoder use explicit work states. Decoder transition fuel is
`4 * input_byte_count + 16`; encoder transition fuel is
`4 * maximum_output_bytes + 16`. These budgets derive from the byte policies:
a scalar consumes/emits at least one payload byte, a list emits five header
bytes, and a compound terminates with a byte and each named member has a tag
and two-byte name-length header. Container bookkeeping adds only a bounded
number of transitions per value. They are not arbitrary truncation limits.
Text, byte scans, array reads, and output writes also have direct structural
recursion; their work is not claimed constant-time. Directly constructed text
unit lists are traversed structurally when validated, even if an eventual
encoded-text-length check rejects them.

## Physical wire versus Java tag-object behavior

Actual 26.3/Java 25 observations identify deliberate boundaries:

| Observed Java behavior | This physical codec |
| --- | --- |
| `NbtIo.readUnnamedTag` skips root name bytes, even malformed bytes | Decodes and validates the requested named root |
| Root reader leaves following bytes unread | Requires EOF after the root |
| Empty lists with unknown element IDs are accepted, then written with ID zero | Rejects unknown IDs; preserves known declared empty IDs |
| Compound map insertion replaces an earlier duplicate name | Preserves ordered physical entries, including duplicates |
| Logical ListTag unwraps special empty-name compound wrappers and can represent mixed logical elements | Preserves the homogeneous wire tree and wrapper compounds |
| Float/Double tag construction and Java writing can normalize negative zero or NaN bits | Preserves exact raw payload bits |

These choices support lossless roundtrips of valid canonical physical data.
They do not claim equivalent logical tag-object transformations. Applying those
transformations belongs to a separate Minecraft semantics layer. Gzip/zlib
compression and persistence behavior are also separate.

## Verification

Run from the Minecraft project directory:

```sh
python3 tools/test_nbt.py
```

The runner checks both Bend files, builds `build/nbt-tests`, executes native
construction regressions, and compares decode/encode output bytes against an
independent Python physical-wire oracle. Python decompresses reference gzip
assets and orchestrates tests; parsing and serialization under test execute in
native Bend. No official asset bytes are checked into tracked source files.
The runner also invokes actual pinned Java NBT classes and Java modified-UTF
routines as a second reference, recording their semantic normalizations rather
than mistaking them for physical byte preservation.

The synthetic corpus covers every tag, signed/raw-bit extrema, floating
special patterns, empty/nonempty arrays and lists, member order/duplicates,
named roots, all 65,536 UTF-16 code units, NUL, lone/paired surrogates,
noncanonical modified UTF-8, malformed strings, invalid tags/lengths,
truncation at every offset of a mixed fixture, depth boundaries, and the array
element boundary. Native construction regressions additionally exercise
out-of-range byte/short/text units, heterogeneous AST lists, illegal End values,
and small configurable limits. The full 16 MiB ceiling is not exhaustively
exercised; smaller configurable byte boundaries are tested.

The official corpus contains all 1,511 bundled 26.3 structure templates,
45,290,384 bytes after reference-only gzip decompression. All structures remain
physical byte-for-byte roundtrips, including the palette key spelling and
numeric payloads. The completed native run passed **2,382 independent cases**:
1,931 accepted roots and 451 expected failures, followed by **1,931 successful
canonical roundtrips**. The 41 exact Java observation probes and semantic
comparison of all 1,931 valid reference roots also passed. The latest completed
fixture counts, output/source hashes,
commands, Java observations, and coverage are in
`evidence/nbt-reference-tests.json`.
Some expected failures occur during encoding after a valid liberal string
decode, when canonical modified UTF-8 would exceed the format's 65,535-byte
string ceiling.

Both `src/nbt.bend --verdict` and `tests/nbt.bend --verdict` report
`ALL PROOFS CHECK`. Unlike the existing JSON encoder, NBT recursion uses direct
structural pieces and decreasing transition fuel; it does not reconstruct a
nested container as a supposedly smaller recursive argument. The fixture laws
prove only their stated finite End and raw-float equalities. Kernel validation
establishes that the translated definitions meet the kernel's typing,
affinity and termination rules, not that the codec is generally correct or
that Minecraft saves are implemented. The emitted fixture declarations were
inspected and the cached kernel also accepted `build/nbt.bendtt` directly;
translation/kernel identities and the exact declarations are recorded in
`evidence/nbt-kernel.json`.
