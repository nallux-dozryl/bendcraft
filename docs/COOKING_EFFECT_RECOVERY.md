# Cooking effect delivery and durable recovery

`cooking_effect_delivery.deliver` consumes the actual released
`cooking_world_store.Effect` sequence. The current fallback acknowledges
`OwnerReset` only because the live Sidecar has already applied that marker to
its physical Details/incarnation owner. It also acknowledges zero-count
`BlockUpdate` and `BlockChange`, which request zero publications. It stops at
the first unavailable owner and returns that effect and its complete ordered
suffix. It never continues past that refusal, sorts, deduplicates or transfers
drops into player inventory.

The missing owners have concrete meanings. `Drop`, including an empty slot,
requires the level RNG and an owned item-entity insertion path. `Experience`
requires the level RNG plus XP-orb merge/insertion ownership. `Dirty` requires
block-entity dirty marking and comparator publication; Core revision events
are not an equivalent receiver. Nonzero block updates and game events require
their actual publisher. Existing `random.Source` algorithms and
`furnace_authority_xp.award` arithmetic do not create those world owners.
Player recipe awards also have no live owner; teardown XP requests must not
be relabeled as player recipe awards.

The retained 26.3 receiver fixtures are `reference/furnace_authority.json`,
`reference/campfire_authority.json` and `reference/cooking_world.json`.
Their extraction tools identify their actual Java methods and world-I/O
fixtures. The real entity consumer is a separate integration: level RNG,
entity-local RNG, UUID/seed allocation, exact split and spawn arithmetic,
orb merge-query order and subsequent entity ticking must retain their own
owners. In particular an empty container drop consumes level RNG before
the item-empty test. Recovery never invents a seed, ticket, entity, velocity,
XP amount or player award.

`cooking_effect_recovery.encode(limits,effects)` and `decode(limits,bytes)`
frame an internal recovery record named `bendex:cooking-effects`, with inner
format 1 and an ordered Compound list. Stable tags 0 through 5 identify
OwnerReset, Drop, Experience, Dirty, BlockUpdate and BlockChange. Positions
and item counts are raw Int words. XP uses and rate bits are raw Int words;
the codec performs no XP arithmetic. Strings use IntArray character words,
preserving complete component identities, supplementary characters and NUL
without modified-UTF8 length constraints or normalization. Notification
counts use canonical decimal Nat character words. Unknown tags, fields,
formats, wrong types, noncanonical counts, truncation and trailing bytes
refuse the whole decode. Caller-supplied `nbt.Limits` govern byte, depth and
element budgets; an encode failure supplies no truncated recovery payload.

The live save owner adopts these bytes in its existing atomic Core/player/
cooking-body transaction. `local_player_cooking_storage.Saved` includes
`pending:List<Store.Effect>`. Nonempty pending uses the strict format-2 wrapper
with an `effects` ByteArray. Empty pending retains the old player bytes and
format-1 cooking-body bytes. Saving a recovery queue acknowledges durable
retention, not world delivery. Pending ticks, loading and section discovery
still refuse save. Cold restoration must return the exact queue to the live
consumer before attempting further delivery; successful state-transforming
delivery may remove a prefix only after the corresponding real owner has
committed it. Item/XP owner state must be persisted with the same transaction
when that consumer is joined.

Run `python3 tools/test_cooking_effect_recovery.py` for the narrow native
boundary check. Attempt 004 passed thirteen delivery/codec guards, exact
2,758-byte equality against the existing independent physical NBT constructor,
two accepted and seventeen rejected records, and six independently checked
delivery laws with no exporter exclusions. The native fixture supplies XP
bits dynamically and retains NaN payload `0x7fc01211` and negative zero
`0x80000000`. Attempts 002 and 003 retained a default-JS F32 representation
failure: the NaN payload becomes `0x7fc00000`. `--js` reproduces that boundary;
no JavaScript raw-NaN preservation claim follows from the native result.

These laws concern the actual delivery function and preservation of the
complete refused effect suffix. They do not establish entity physics, world
publication, the whole live Sidecar owner, atomic filesystem publication or
cold actor restoration. Those properties require their connected production
consumer and existing actor/save boundary checks.
