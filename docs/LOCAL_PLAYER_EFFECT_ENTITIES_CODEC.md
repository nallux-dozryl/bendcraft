# Complete cooking entity snapshots

`src/local_player_effect_entities_codec.bend` encodes and decodes the immutable
`cooking_effect_entities_model.View`. The live model supplies this snapshot
beside its sole affine `State` through `inspect`; restoring a successfully
decoded snapshot uses the model's `install` once. The codec never creates,
duplicates, or advances an entity owner or either random source.

```python
encode(limits: N.Limits, view: E.View)
  -> Result<&2, &2, String, List<&2, U32>>
decode(limits: N.Limits, bytes: List<&2, U32>)
  -> Result<&2, &2, String, E.View>
```

The internal uncompressed NBT root is `bendex:cooking-effect-entities`, format
1. This framing preserves the complete implementation state, including fields
that vanilla entity save/load projects away. In particular, it does not call
`vanilla_entity_fields.load`, `.save`, or their canonical numeric projection.
Embedding these bytes in the actual atomic player/world save belongs to
`local_player_cooking_storage`; isolated codec tests do not establish that
publication or cold restore.

Every Compound has exactly its listed members in the listed order. Missing,
extra, duplicate, reordered, or wrongly typed members refuse the complete
snapshot. Root-name/version, entity kind, random kind, fixed word-array length,
strict booleans, canonical Nat spelling, truncation, and trailing bytes are
also checked. Errors begin `local-player-effect-entities:`. Existing NBT
byte/depth/element limits apply to the complete encode or decode, and return an
error rather than a partial snapshot.

| Root member | Representation |
| --- | --- |
| `format` | Int, exactly 1 |
| `level_random` | Compound: `kind`, `words` |
| `seed_uniquifier` | IntArray of two raw U32 words, high first |
| `last_id` | Int, raw U32 |
| `next_section_order` | IntArray of canonical decimal character words |
| `records` | List of Compound, retaining every record in order |

Random `kind` 0 is Legacy with two seed words; kind 1 is Xoroshiro with four
words, low pair followed by high pair. Decoding uses the raw constructors,
without reseeding, masking Legacy words, replacing an all-zero Xoroshiro pair,
or consuming random values.

Each record is a Compound with `kind`, `common`, `payload`. Kind 0 is Item,
kind 1 is Orb. `common` contains, in order, `dimension`, `id`, `uuid_most`,
`uuid_least`, `random`, `fields`, `tick_count`, `first_tick`, `removed`,
`accessible`, `section_order`. The dimension is a character-word IntArray;
IDs/tick counts are raw Ints; UUID halves are two-word IntArrays. The three
booleans are Ints exactly 0 or 1. Section order uses canonical decimal
character words.

`fields` contains all fourteen model members in order: `position`, `velocity`,
`position_o`, `position_old`, `look`, `head_yaw`, `body_yaw`, `fall_distance`,
`on_ground`, `air`, `fire`, `portal_cooldown`, `invulnerable`, `needs_sync`.
Each vector is an IntArray of six binary64 words, XYZ high/low pairs. Look is
an IntArray of four raw binary32 words: yaw, pitch, previous yaw, previous
pitch. Head/body yaw are raw binary32 Ints; fall distance is two binary64
words. The remaining numeric fields are raw U32 Ints and all booleans are
strict 0/1 Ints. No float arithmetic, finiteness admission, clamp, canonical
NaN, signed narrowing, or previous-field reconstruction occurs.

Item payload members are `item`, `age`, `pickup_delay`, `health`, `thrower`,
`target`, `bob`. An empty item is an empty Compound. A stack Compound contains
`id`, `components`, `count`; both strings are complete character-word
IntArrays and count is a raw U32 Int. Thrower/target are empty IntArrays for
None or four UUID words for Some. Bob is a raw binary32 Int. Orb payload
members are `value`, `age`, `health`, `count`, `following`, with the same
optional UUID representation. The codec retains zero/raw counts, duplicate
records, nonfinite numeric words, NUL, non-BMP characters, isolated surrogate
character words, and all component-key text without normalization.

Bend 2.0.35's native Nat is 48 bits, as established by the existing
`world-codec-nat` evidence and `Base.Nat.read.fits`. Both encoding and decoding
validate canonical decimal values through that installed reader. Orders above
U32 are retained through 281474976710655; larger values refuse. This does not
enlarge or silently narrow the live DTO's native Nat representation.

Four production laws state reversibility of raw vectors, raw RNG sources,
optional UUID words, and raw binary32 words. The complete original Bend source
check passed in 1.187 seconds. Independent kernel verification of these four
laws has not run; source typing is the stated proof result.

The native codec passed 11 targeted guards and 385 independent physical cases:
four accepted byte-exact roundtrips and 381 expected refusals. The tests cover
every raw field, duplicate Item/Orb order, invalid/high Legacy seed words,
all-zero Xoroshiro words, all optional UUID cases, isolated surrogate character
words, raw F32/F64 NaN payloads, negative zero, and orders through the actual
native Nat maximum. Its complete 5450-byte constructed snapshot equals the
independent expected NBT. One affine install/inspect retains the complete snapshot.
The single native build took 11.299 seconds, with zero retries; all four owned
process groups exited and were reaped. The binary SHA256 is
`a819747898ec3a3f3cbecf4a416a5d5ead2e9bbc81fd21ae8dd9c9494cf5a779`.
Results are in `evidence/local-player-effect-entities-codec-002.json`.
Confidence is high in this measured native codec contract; actor atomic
publication and cold restore remain the actual integration consumer's work.

The optional default-JS diagnostic failed before running any guards:
`bend: 55296 is not a Unicode scalar value`. Source typing passed, but the
JavaScript lowering rejected the fixture's isolated surrogate Char. This
measured negative is retained in
`evidence/local-player-effect-entities-codec-003-failure.json`; it is not a
product PASS and did not reach a NaN byte comparison. Existing recovery codec
evidence separately establishes default-JS NaN payload canonicalization. The
runner recognizes the exact measured surrogate failure for future diagnostics
and refuses other failures; no equivalent JS retry was performed.

Reproduce native acceptance with the bundled Python runtime and
`tools/test_local_player_effect_entities_codec.py --native`. The independent
physical corpus lives in the runner, rather than in committed NBT binaries.
Native binaries, emitted C, complete source/tool manifests, and raw process
logs remain under `build/local-player-effect-entities-codec`.
