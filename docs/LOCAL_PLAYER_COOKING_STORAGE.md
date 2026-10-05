# Cooking bodies in the atomic world save

`local_player_cooking_storage.Saved` wraps the unchanged
`player_inventory_codec.Saved`, an ordered list of
`Body{position:Core.Position,bytes:List<U32>}`, the pending effect queue, and an
optional complete entity recovery snapshot. Empty cooking state encodes the
existing inventory payload exactly. Nonempty state uses the explicitly named
`bendex:local-player-cooking-record` NBT root with format 1, the existing player
payload as a ByteArray, and physical cooking bodies with their complete
dimension and raw signed-coordinate words. Duplicate positions, unsupported
formats and malformed wrapper fields refuse the complete decode.

Nonempty pending cooking effects use wrapper format 2, which adds an
`effects` ByteArray containing the strict `cooking_effect_recovery` encoding.
The queue keeps its complete order, item keys/counts, positions and notification
counts. Its native codec also preserves raw XP request bits; the default
JavaScript runner canonicalizes NaN payloads, as retained failure attempts
002 and 003 demonstrate. Empty queues retain the existing format 1
body bytes, and an empty body list plus empty queue retains the original
inventory bytes. Format 2 with an empty queue refuses as noncanonical.
An admitted entity owner uses wrapper format 3. Its six required members are
`format`, `player`, `bodies`, `effects`, `entities`, and `clock_inputs`.
`entities` is the strict complete `local_player_effect_entities_codec` ByteArray;
`clock_inputs` is an ordered LongArray of raw high/low constructor timestamp
words. The snapshot retains the actual LEVEL random source, process factory
uniquifier, ID and section-order cursors, and every complete Item/Orb record.
An empty record list still requires format 3: dropping its RNG or cursor state
would change subsequent gameplay. A missing entity owner retains the exact
format 1/2 encoding. A wrong or duplicate clock member, incomplete entity
snapshot, or unsupported format refuses the complete decode. No defaults or
fresh random values fill missing recovery fields.

The outer extension namespace/schema remain `bendex:local-player-record`/1.
Core, player inventory, cooking bodies, pending effects and the entity recovery
snapshot therefore use the existing single
`extended_persistence` atomic publication and acknowledgment. There is no
separately acknowledged cooking file. Legacy player/inventory payloads decode
with an empty body list, effect queue and entity snapshot. The current wrapper
uses the existing NBT defaults:
16 MiB bytes, depth 512 and 1,048,576 elements; the extension admits 16 MiB and
the outer file bound adds that budget to the existing default file bound.
These resource limits remain explicit.

The initialized item catalog is runtime data captured by one codec owner.
`extended_persistence.dispatch_codec` and `encode_codec` carry that owner
through the existing routing and encoding helpers. The closed-codec entry
points delegate to the same helpers. Schema checks, capability checks, peer
observation, request sequencing, atomic publication and acknowledgments
therefore remain shared with the existing world-save path.

The live cooking owner produces known cooking-body bytes. `with_details`
decodes those bytes as a Compound and reinserts the root name and ordered
unknown/base fields retained by the accepted physical load. It preserves
UTF-16 names, duplicate unknown fields, tag types and raw numeric bits.
Malformed or noncompound known bytes refuse the merge. These retained fields
are preserved physical data; this wrapper does not interpret base BlockEntity
components or grant item, fuel or player authority.

Entry restores the existing Core sections first, completes lighting bootstrap
and cooking-owner discovery, then loads each stored body against its actual
registered block. A failed body admission stops startup before ticks or
listeners. The Session save collector must retain the sole Core and affine
owners on any refusal, reject pending discovery/ticks, and collect every
current body and pending effect, plus the complete admitted entity snapshot and
unused clock inputs, before the single atomic transaction. The save collector
retains the original live entity owner; a decoded snapshot is installed once
during cold startup. Accepted
owner-reset markers clear old keyed Details even when a due batch recreates
the same block. These live joins require the coherent actor consumer.

`python3 tools/test_local_player_cooking_storage.py` passed sixteen actual Bend
default-JavaScript guards in attempt 005, in 12.917 seconds. Attempt 006 passed
the same guards in 26.819 seconds after the shared initialized component and
inventory codec changes. The checks cover byte-identical
empty inventory encoding, physical wrapper dimensions/coordinate words/body
order, duplicate positions, format/list rejection, physical extras and
malformed/noncompound merge refusal, the ordered format 2 queue, and empty or
wrong-tag recovery rejection. The four new guards cover an empty entity owner
with nonempty RNG/cursors and ordered raw clock words, absent-owner format 2
byte identity, wrong clock tag, and duplicate clock-member rejection. Attempt
004 retains a fixture-only out-of-range U32 Nat literal parser failure; using
`Nat.add(4294967295n,1n)` tested the intended above-U32 value without changing
production code. Attempt 003 passed the earlier twelve guards; attempt 002
passed nine guards.
Attempt 001 preserves a test-only
matcher-order failure; its repaired fixture passed without a production
change. This is high-confidence evidence for these codec boundaries. It is
not native actor interrupted-save/cold-reload acceptance or an independent
kernel proof. The standalone CLI proof-only command also rejects the existing
43 unsafe/foreign atomic-persistence dependencies; whole effectful actor
typing and mathematical proof scope are separate results.

The separate narrow native recovery consumer passed thirteen guards and an
independent 2,758-byte NBT comparison, including XP NaN `0x7fc01211`, signed
zero `0x80000000`, Unicode/NUL item components and ordered duplicate effects.
Its nineteen-case strict corpus accepted two valid encodings and refused the
seventeen malformed encodings. See
`evidence/cooking-effect-recovery-004.json`.

The complete entity codec separately passed eleven native guards and 385
independent physical cases, preserving raw F32/F64 NaN payloads, signed zero,
all entity fields, UUIDs, local and LEVEL RNGs, and actual native Nat orders.
See `evidence/local-player-effect-entities-codec-002.json`; its default-JS
surrogate-character failure remains recorded separately. These native codec
results do not extend the JavaScript wrapper guards to every raw numeric or
character value.

The frozen actor019 consumer passed five complete atomic save comparisons and
two actual SIGKILL/cold restores with format 2 pending effects. See
`evidence/playable-client-cooking-native-011.json`.

The actual frozen actor020 consumer subsequently passed five complete format 3
atomic byte comparisons and two SIGKILL/cold restores in 111.939 seconds. It
published two complete Item records and an Orb worth 7, matched actual
constructor clock intervals and 45 primitive LEVEL draws, cleared old keyed
Details on recreation, then preserved every record/factory/ID across the
second restore and continued 18 primitive EmptyDrop draws. Its final effect
and clock queues are empty. The kills follow acknowledged durable saves;
crashing during an unfinished atomic write remains a separate case. See
`evidence/playable-client-cooking-entities-native-005.json`. This consumer uses
the declared isolated overworld factory/allocator and supported remove-to-air
geometry. Entity ticking, pickup, rendering and wider collision admission
remain separate joins.

The additive format 4 wrapper carries the complete publication recovery in a
seventh required ByteArray member, `publication`. Its other six members retain
the format 3 names and physical types. An empty `entities` ByteArray represents
an unbound entity owner and requires an empty `clock_inputs` LongArray. A bound
owner retains its complete existing entity encoding and ordered clocks. When
publication recovery is absent, formats 1, 2 and 3 retain their exact encoding.
The outer extension namespace and schema remain unchanged.

`local_player_cooking_publication_codec` preserves the complete incarnation
Patricia tree, including counters for removed owners, plus the journal sequence,
ordered unsaved chunks and complete last receipt. Tree nodes are serialized
directly rather than reconstructed from a flattened map. Decoding checks
canonical position keys, native 48-bit natural bounds, nonempty children,
strictly increasing branch positions and the actual key-bit partition. Journal
validation checks the registered dimensions, signed chunk bounds, unique chunk
keys, positive bounded revisions and exact latest receipt/source position. A
historical receipt's incarnation may be lower than the saved position counter;
it may not exceed it. Binding and string words are preserved as IntArrays.
This internal codec does not authenticate a binding against the actual loaded
catalog; `cooking_effect_publication.restore_journal` performs that separate
runtime admission before installing the sole affine publisher.

New `OwnedDirty` effects use tag 6 with the full producer position, cached
binding and incarnation. Their inner effects root uses format 2; a queue with
only existing effect kinds retains the exact format 1 bytes, including legacy
tag 3 `Dirty`. The parser rejects an owned effect whose duplicated position
disagrees with its captured source, or whose source is structurally invalid.
Format 4 is required whenever an owned notification is persisted; the older
wrappers refuse it instead of recovering an owner from the queue.

Attempt 008 passed all 22 actual default-JavaScript wrapper guards, including
six new checks for absent-publication byte identity, both entity binding states,
complete format 4 recovery, owned notifications without publication recovery,
legacy-wrapper admission and orphan clock refusal. See
`evidence/local-player-cooking-storage-008.json`. Attempt 007 retains the actual
parser error in the newly added owned-effect helper; its repaired helper was
checked in 008. Standalone native recovery bytes, the Session carrier and the
actual durable actor save/restore join remain separate consumers.

The additive format 5 branch retains the same seven-member topology and the
five-field `Saved`/`Projection` ABI. `EntityRecovery.TickRecovery` carries one
complete tick snapshot, the remaining real constructor clocks, and optional
complete manager Data. Its `entities` ByteArray contains the strict versioned
`local_player_cooking_tick_storage` envelope, with one complete entity image
inside the tick recovery. Formats 1–4 retain their existing encoder branches.
Missing runtime, sound or manager information remains explicitly unavailable;
decoding does not manufacture fresh values or loader authority. Empty
publication bytes are allowed only without pending `OwnedDirty` effects.

Attempt 009 passed all 30 **native** wrapper guards, including a complete actual
player/body/owned-effect/publication/tick encode/decode/re-encode round trip and
eight format 5 availability/refusal checks. The build took 209.674 seconds and
the native guards 0.769 seconds. The standalone tick component additionally
passed 15 guards and 47 independent physical cases, including a nonempty
complete manager image. Five actual full-owner/sidecar/clock laws passed the
independent kernel with zero exclusions. See
`evidence/local-player-cooking-storage-009.json` and
[the complete format 5 contract](LOCAL_PLAYER_COOKING_TICK_STORAGE.md).
Format 5 live carrier/save/interruption/cold-restart acceptance remains the
subsequent coherent actor consumer; actor021's immutable format 4 source is
unchanged by this join.
