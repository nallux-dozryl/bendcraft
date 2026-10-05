# Cooking dirty publication

`cooking_effect_publication.dirty` implements a deliberately narrow real
`BlockEntity.setChanged` consumer. A cooker menu mutation can change its owned
inventory and enqueue a dirty effect; the old entity delivery path refused
that effect and consequently blocked later actor work. The new consumer marks
the actual chunk unsaved only after it establishes that the original producer
still names the current block entity and that comparator notification has no
receiver in its supported neighbourhood.

## Vanilla authority

The installed Java 26.3 receiver is recorded in
`reference/cooking_effect_publication.json`. Fourteen actual receiver cases
passed in 4.293905 seconds. `BlockEntity.setChanged` calls
`Level.blockEntityChanged`, which marks a loaded chunk unsaved. For a nonair
cached block state, `Level.updateNeighbourForOutputSignal` visits north, east,
south and west. A direct comparator receives `neighborChanged`; a conducting
adjacent state causes a second-cell comparator check. Vertical comparators do
not participate in this operation. All three vanilla air blocks are air and
nonconducting. The receiver fixture supplies a finite block map and chunk
services and records dispatch; it does not claim downstream redstone parity.
Cached-air cases invoke the original protected static receiver because an
actual furnace block entity rejects an invalid air block state. That genuine
fixture failure is retained in the reference evidence.

The Bend consumer requires all four adjacent cells to be loaded and decoded by
the same authenticated registry. It currently accepts only `minecraft:air`,
`minecraft:cave_air` and `minecraft:void_air` with their actual empty property
sets. Conductors, comparators, other blocks and missing sections refuse. Glass
is nonconducting in the actual Java receiver but remains outside this small
admitted palette. No missing cell becomes air, no comparator call is invented,
and the consumer changes no Core block, tick, light or entity RNG owner.

## Producer identity and ownership

The new journal module is independent of `cooking_world_store`, so the effect
model and durable recovery can import its immutable data without an import
cycle. `Source` contains the actual position, cached cooking binding and
incarnation captured at the mutation producer. The current descriptor must
come from the actual retained `Store.Entry` and incarnation map. Both bindings
are authenticated by the current cooking catalog. Matching permits lit and
facing changes within the same block family and incarnation; the original
cached input is retained in the publication receipt. A recreated owner refuses
even when its new block state is identical.

Legacy `Dirty{position}` has no captured identity. A current lookup cannot
retroactively attest it. The new owned effect and the current incarnation map
must both survive atomic recovery; rebuilding the map from the queued source
would erase the distinction between an old producer and a replacement owner.

`initialize(Engine, Bindings.Catalog)` authenticates the immutable registry once
and checks Core, registry and binding catalog state counts. `dirty` receives
and returns the caller's sole Engine and the boxed journal owner. It preflights
the current cooker state and loaded horizontal cells before changing the
journal. Refusal retains both complete owners. The surrounding delivery loop
must retain the current effect and exact ordered suffix while preserving each
already committed prefix.

## Persistence journal

`View` contains the monotonic sequence, unsaved chunk revisions and the latest
complete receipt. Chunk coordinates retain signed section-coordinate bits;
the chunk key includes dimension and the actual X/Z chunk coordinates.
`State` boxes this view as one affine owner. Repeated marking replaces old
entries for the same chunk. A successful dirty publication returns an actual
receipt and retains it in that owner.

`snapshot` returns the retained owner with a save token. The actual full atomic
cooking save writer may issue the affine `FullCookingSaveCommitted` only after
the save commits. Request admission, JSON encoding, and a menu reply are not
save commits. `save_completed` leaves a failed write unchanged. A valid older
save clears only included chunk revisions; later dirt in the same chunk and
new chunks remain unsaved. The latest publication receipt remains observable.

`saved_view` makes the prospective clean immutable save image from a view and
its snapshot. It creates no second journal owner. The live owner remains dirty
until the durable writer returns the successful commit token; the saved bytes
and acknowledged live journal then agree on which revisions were covered.

`view_valid` and `restore` reject duplicate chunk keys, impossible chunk
coordinates, future or zero chunk revisions, and a missing or inconsistent
latest receipt. `restore_journal` additionally authenticates the historical
receipt's cached binding against the actual initialized catalog. It does not
compare that old receipt with a current incarnation which may legitimately be
newer. Pending owned effects still require the current entry and incarnation
at delivery. The incarnation map uses existing canonical `Bindings.key`
position keys and must retain its complete topology and values on recovery.

The native Nat representation permits values through 281474976710655. Public
dirty delivery refuses increment at that maximum. Durable decoding must retain
canonical Nat values within that range and complete raw U32 coordinate bits;
its byte, depth and element limits are supplied by the actual storage codec.
This consumer adds no fixture-sized list or world limit.

## Verification and integration status

The latest complete original proof-entry source checker passed 1,443
declarations with no open holes. Seven meaningful production laws passed the
independent kernel with zero exclusions after the journal recovery and save
image helpers were added. They cover failed full saves, future-token refusal,
repeated chunk marking, old-save/later-dirty chronology, required current
attestation, and lit-transition versus incarnation identity. The subsequent
catalog-authenticated restore helper is checked by the full original source
checker and actual native consumer; it is outside those seven kernel roots.

The actual focused native consumer passed 47 exact observations with identical
outputs on one and four threads: 26 publication cases, seven save-journal cases
and 14 recovery cases. It loads the real full registry and authenticated
cooking catalog, reads loaded Core cells, and compares complete serialized
Core bytes and registry identity. Its actual retained furnace entry includes
four backing cells behind three logical slots, an opaque component tail,
timers, recipe uses and speed bits. Refusal retains all those fields and the
complete prior journal. Successful publication preserves the producer's
cached source through a same-incarnation LIT transition. Sequence exhaustion,
each horizontal refusal position, old-save/later-dirty chronology, malformed
recovery and forged historical bindings are exercised. Native runs took
2.7313 and 2.2405 seconds with approximately 16.9 MB sampled RSS. There was one
native build, no native retries, no imported source drift and no remaining
owned processes. The exact receipts are
`evidence/cooking-effect-publication-native-011.json` and
`evidence/cooking-effect-publication-proof.json`.

Actor 020 is immutable and retains its existing legacy dirty refusal. The next
actor integration owns producer stamping, persistence of current incarnation
and journal data, same-owner delivery dispatch, and the real atomic save
receipt. This module does not admit nonzero block update or game-event effects,
downstream comparator processing, automatic chunk storage scheduling, or
unsolicited menu network publication.
