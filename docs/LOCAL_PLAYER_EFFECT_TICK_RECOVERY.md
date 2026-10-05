# Complete item tick recovery snapshot

`src/local_player_effect_tick_recovery.bend` projects the actual
`item_entity_tick_model.State` without retaining a second affine entity owner.
`inspect(state)` returns that same sole state beside immutable
`Recovery{entities, runtimes, sound}`. `entities` is the existing complete
`cooking_effect_entities_model.View`; runtimes are the actual ordered
`RuntimeEntry` list. Sound is the separate actual `Level.soundSeedGenerator`
source, never `View.level_random` or an entity's own random source.

`legacy(view)` exposes unavailable runtime and sound authority as `None`.
`Some{[]}` means a known empty runtime list and has a different physical
encoding. `restore` refuses unavailable runtime authority and installs exactly
one entity owner for an available list. An available runtime list may retain
missing or duplicate IDs exactly; the existing tick admission checks still
refuse operations requiring a unique matching entity and runtime. Recovery is
not permission to repair that state or invent runtime entries.

The codec preserves all physical flags and stuck vector; base timers, water,
eye, powder snow, sprint/swim/freezing/silent flags, optional last position and
speed; water/lava height, flow, raw count and presence; eye water/lava and fast
lava flags; ordered pending and completed movements; and support block/cache.
The production tick requires `Runtime.tail=[]`. Both encoding and decoding
refuse a nonempty tail; an inspection or failed encoding leaves the actual
owner intact. No recursive tail is silently discarded by an admitted encoding.

The internal, uncompressed NBT root is named
`bendex:local-player-effect-tick-recovery`. Its exact ordered members are:

1. `format: Int(1)`.
2. `entities: Compound`, using the existing complete entity snapshot schema,
   including its inner format and complete raw entity records.
3. `runtimes: Compound`, either only `present: Int(0)` or
   `present: Int(1), entries: ListTag(10)`.
4. `sound: ListTag(10)`, with zero or exactly one existing raw random-source
   compound.

Each runtime entry contains `id: Int` then its full runtime compound. Runtime
members are `physical, base, fluids, pending, movements, support, tail`, in
that order. Movement lists and tail use element tag 10 even when empty.
Optional last position uses a zero-or-one element tag-11 list. Optional support
position is an IntArray of zero or exactly three raw Java integer words.
Booleans are Int 0 or 1; other integer fields retain all U32 payloads. F64
vectors and scalars use exact raw words. Existing F32 entity fields retain raw
NaN payloads, infinity and signed zero on the native boundary. Random sources
preserve every supplied raw word; recovery performs no seed normalization.
Entity cursor/order Nats use the existing canonical decimal charword encoding,
including its native 48-bit bound.

`encode(N.Limits, Recovery)` and `decode(N.Limits, bytes)` enforce the supplied
byte, depth and element limits over the **whole single NBT tree**, including
the embedded entity compound. Default limits are 16,777,216 bytes, depth 512
and 1,048,576 elements. Unknown, reordered, duplicated, missing or mistyped
fields; malformed optional counts; noncanonical booleans; noncanonical tails;
and malformed, truncated or trailing physical NBT refuse. No additional
product entity-count restriction is introduced by this recovery codec.

The narrow verification entry is
`tests/local_player_effect_tick_recovery.bend`. Its helper reuses the existing
entity-codec single-attempt native builder and bounded process cleanup:

```sh
python3 tools/test_local_player_effect_tick_recovery.py --prepare
python3 tools/test_local_player_effect_tick_recovery.py --ordinary
python3 tools/test_local_player_effect_tick_recovery.py --native
```

Native attempt 003 passes the 9,583-byte independent golden comparison,
sixteen availability/owner/budget guards and all 755 physical fixtures:
13 exact accepted roundtrips and 742 refusals. The cold build took 13.61 seconds;
guards took 0.71 seconds and the physical corpus 5.75 seconds. All owned process
groups were reaped. The binary SHA256 is
`a18ddd6d7911ec03216302661e17dec032901abcff8746f3b501cd8e7faa7296`.
Versioned receipts retain the earlier computed-destructure source failure.

`local_player_effect_tick_recovery_laws.bend` and its proof quantify complete
ordered entity records, the whole sole entity owner, every runtime entry and
independent sound. They establish install/inspect and restore/inspect
composition plus refusal when required authority is absent. All six selected
obligations pass the independent kernel in 0.12 seconds, with zero exclusions
and unchanged checked definitions. These proofs do not claim NBT parser/limit
correctness or durable IO; the physical codec has its separate native corpus.

Root owns a later format5/session join. Current format4 and frozen actor21 are
unchanged. Save interruption/cold restoration and fresh runtime/bootstrap
authority require that real consumer. This module does not create LEVEL,
thread-local or sound RNG authority. In particular, the actual Level startup
distinguishes Netty thread-local `nextLong()` and its subsequent `nextInt()`,
Minecraft LEVEL source creation, and the later thread-safe sound creation;
recovery cannot debit or substitute those streams to fill a missing source.
