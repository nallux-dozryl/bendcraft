# Item entity pickup, pinned Java 26.3

Production is `item_entity_pickup.bend`; its collection join is `item_entity_pickup_scene.bend`. Both operate on the existing `cooking_effect_entities_model` owner and the actual `player_inventory.State`/affine inventory Array. They do not own a second player, world or entity collection.

## Actor call

```
Pickup.touch(admission, context, itemEntity, player)
  -> itemEntity & player & Result<Error, Effects>
Scene.touch_id(admission, context, entityId, entitiesState, player, scanBudget)
  -> entitiesState & player & Result<Error, Effects>
```

`Context{items:campfire_authority_items.Context, operation_budget:Nat}` uses the real loaded item registry and initialized defaults. Canonical modified keys are authenticated by reconstructing a patch and requiring the shared component resolver's exact identity. Caller-supplied metadata or an envelope header alone cannot authorize insertion. The existing supported setters are max stack size, max damage, damage, repair cost, unbreakable, glint override and suspicious-stew effects; unchanged initialized defaults for every loaded item remain usable. Other changed setters return explicit refusal through that shared authority. No fixture products or registry-size cap define the production API.

`Admission` contains authoritative touch permission, server/client side, dimension, player entity ID/UUID, whether the receiver is a ServerPlayer, and actual thrower resolution. It must come from the actor's current collision/world scheduling and identity owners. This module does not infer contact, distance, spectator exclusion, loaded residency, or entity accessibility from inventory data. The actor must avoid scheduling removed entities and provide the actual player dimension. The dimension must match the retained item record. Java's receiver itself checks only server side, pickup delay exactly zero and target UUID; thrower does not gate pickup.

Thrower resolution is `UnknownOwner`, `KnownAbsent`, or `ResolvedOwner{uuid,server_player}`. An unknown stored thrower refuses a successful pickup atomically, because advancement publication requires its actual world lookup. Known absence is an observed lookup result, never inferred from a missing provider. A resolved UUID must equal the item record's stored thrower. No thrower needs no lookup. Failed/partial Inventory.add does not call onItemPickup and therefore needs no thrower lookup.

On `Done`, the returned owners are the authoritative state, even when `Effects.inventory_add_returned` is false. On `Fail`, both complete owners are retained; no candidate inventory is installed. For the collection join, list order, all other entities, per-level RNG, constructor seed factory, ID cursor and section-order cursor remain intact. The scan and insertion budgets limit work and produce refusal; they are caller execution budgets, not game capacity limits.

`Effects{inventory_add_returned,inserted,residue,discarded,publications}` distinguishes material actually inserted from creative-discarded residue. `residue` is the live remaining quantity (zero after successful emptying); the discarded Item record retains its original count because Java calls discard then restores count for notifications. An inactive touch reports its unchanged quantity. Keep the removed record until the actor consumes its entity-removal callback.

## Exact insertion and publication

Normal insertion merges into selected hotbar, offhand40, ascending main0..35, then first empty main0..35. It repeats until empty or no progress. The pinned Container limit is 99, intersected with the item's initialized/effective stack limit. Equal item IDs with different complete components never merge. Damaged items use Java's separate first-empty-main whole-copy path, with no merges; unbreakable items are not damaged. Creative behavior derives from the actual retained `P.Abilities.instabuild`, not an admission flag.

A survival insertion that fills the last available space can change inventory and item residue but return false after the final no-progress pass. It produces PopTime updates only. Creative no-progress clears the remaining stack and returns true. Every successful `playerTouch` uses the original whole count for take and pickup-stat quantities, including creative overflow. No cooking/furnace XP is introduced.

Ordered `Publication` values are slot PopTime 5 updates, a take packet when the entity was not already removed, ServerPlayer menu broadcast, entity discard when emptied, original-count item pickup stat, then thrown-item advancement notifications. The owner-server criterion is emitted before the receiver-server criterion, with the final Item stack (including Java's restored original count on discard). The collection join leaves the player menu revision, derived crafting result, profile, abilities, equipment and temporary/carried slots intact; the actor handles the broadcast rather than inventing an Inventory.add menu revision.

The live actor must consume those typed publications through its network/stat/advancement/animation owners and install both returned state owners together. Pickup does not execute an actual packet connection or advancement manager. Motion's admitted contact scheduler, item tick/merge/fluid state, scene render projection and durable player/entity save framing are distinct consumers. The corresponding existing owners must join this API; this document does not claim those hooks installed.

One precise current domain boundary: Java permits a damaged oversized stack to be copied whole into one empty inventory slot. The existing authoritative inventory invariant requires count<=effective stack limit, so that malformed/oversized damaged path is refused atomically. Valid damaged stacks and oversized *undamaged* resource splitting follow the actual receiver. This is recorded as an observed Java difference, not silently clamped or declared parity.

## Evidence

`reference/item_entity_pickup.json` is produced by `python3 tools/reference_item_entity_pickup.py` from the verified installed 26.3 JAR. The fixture invokes actual ItemEntity.playerTouch and actual Inventory.add using actual initialized components, Inventory and EntityEquipment. Only take/awardStat/onItemPickup callbacks are intercepted to observe their call boundary; ServerPlayer packet/menu/advancement details are separately derived from installed bytecode. It is not a fabricated Python insertion oracle.

`python3 tools/test_item_entity_pickup.py` builds the actual Bend owners against that fixture, loads the full pinned item table and 1,658 initialized item maps, and compares exact full identities, slots, entity count/removal, PopTime, take/stat call quantities and focused owner/refusal/scene publication cases. It does not replay the earlier cooking/spawn corpus. The checked original compiler book and emitted artifact are pinned; bounded attempts are retained in ignored build directories.

`item_entity_pickup_laws.bend` states implementation-connected complete-owner rollback, inactive/client admission, partial survival notification behavior, discard count and unrelated fields, creative overflow, thrower lookup and scene scan laws. `item_entity_pickup_proof.bend` is the ordinary target; the independent exporter retains original checked types/bodies/declaration maps and publishes exact selected roots and exclusions. These laws are not collision admission, Java parity, networking or persistence proofs.

Current receipts: 15 ordinary laws and 12 independently checked laws, zero selected-export exclusions. The full inactive/admission/scene gates remain ordinary-only because their transitive real initialized-component admission reaches the existing `json.encode_go` affine-descent kernel restriction. The actual inactive and exhausted-scan branches plus complete candidate rollback use the same production owners and are independently checked. See `evidence/item-entity-pickup-proof.json` for exact roots and checked term/source pins.

Final native comparison: 26 Java observations, 25 exact state/publication-call comparisons and the named oversized-damaged atomic refusal, plus 10 native owner/thrower/collection guards on one and four CPU threads. Full initialized catalog of 1,658 items is loaded. Private `item_entity_pickup_patch` preserves shared JSON equality, field order and exact `C.resolve` authentication while computing one recursive diff tail per member. The original shared helper computes both candidate recursive tails; the earlier full input hit 60s, whereas the changed full input passed in 13.10s/14.45s at about 70MiB. These are boundary timings, not live frame or general-game speedup claims. Failed attempts and the specific repair are retained in `evidence/item-entity-pickup-attempts.json`; final artifact/term pins are in the native/proof receipts.
