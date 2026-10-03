# Owned inventory foundation

Confidence: **high** for the specified typed arithmetic, transaction, and bounds behavior covered below. Minecraft 26.3 container, creative, crafting, and component-resolution parity remains **unknown** at this layer.

`src/inventory.bend` is a pure Bend module. Inventory storage is an affine `Array<Slot>`; a caller passes its single owner into an operation and receives that owner back alongside the result. Runtime slot counts and indices are `U32`.

## Public values and interface

```bend
type ItemKey is Data:
  ItemKey{id: String, components: String}
type ItemMetadata is Data:
  ItemMetadata{key: ItemKey, stack_limit: U32}
type Slot is Data:
  InvEmpty{}
  InvStack{key: ItemKey, count: U32}
type Inventory is Type:
  Inventory{slots: Array<Slot>, length: U32}
type TransferStatus is Data:
  InvMoved{count: U32}
  InvRejected{reason: InventoryError}
```

Import with `import ./inventory.bend as Inv` from another source module. Function signatures use those local type names:

| Function | Result | Behavior |
| --- | --- | --- |
| `new(depth: Nat, length: U32)` | `Maybe<Inventory>` | Creates `2^depth` empty backing slots with the supplied logical length. Accepts depth 0–16 and length 0–capacity. Invalid input returns `None`. |
| `read(inv, index: U32)` | `Inventory & Maybe<&2, Slot>` | Returns a copied immutable slot with its inventory owner. Invalid logical or physical indices return `None` and preserve storage. |
| `load_slot(inv, index: U32, slot: Slot, metadata: ItemMetadata)` | `Inventory & Bool` | Validates and replaces a slot for explicit state initialization. A stack requires exact metadata identity and `0 < count <= stack_limit`. An empty slot needs no metadata match. Invalid input returns `False` and preserves storage. |
| `transfer(inv, source: U32, destination: U32, requested: U32, metadata: ItemMetadata)` | `Inventory & TransferStatus` | Moves up to the requested count into an empty or exactly matching slot, clamped to source availability and destination room. |
| `split(inv, source, destination, requested, metadata)` | `Inventory & TransferStatus` | Uses the same transaction, with an additional empty-destination requirement. The caller supplies the split amount. |
| `merge(inv, source, destination, requested, metadata)` | `Inventory & TransferStatus` | Uses the same transaction, with an additional occupied-destination requirement. |
| `key_equal(a: ItemKey, b: ItemKey)` | `Bool` | Compares both immutable strings exactly. |
| `slot_count(slot: Slot)` | `U32` | Returns 0 for an empty slot. |
| `status_show(status: TransferStatus)` | `String` | Stable diagnostic text: `moved:N` or `rejected:REASON`. |

`load_slot` deliberately replaces counts and is a state-loading primitive. Item acquisition, creative commands, save authentication, and crafting must enforce their own authority before using it. Count conservation applies to transfer, split, and merge.

The logical length may be smaller than the backing capacity. Every public access checks both against the actual `Array.size`, including inventories assembled directly with the public constructor around a valid Base array. Base arrays wrap indices; these operations reject an out-of-range index before calling `Array.get` or `Array.set`. Backing arrays must be balanced power-of-two arrays; native Bend rejects unequal Array branch sizes during construction with a runtime fail-stop. Two separate test probes verify that rejection before inventory code can run. `new` caps depth at 16, allowing 65,536 backing slots while bounding public construction allocations.

## Metadata and exact identity

Metadata is injected by the registry-owning caller for the source item. The supplied `stack_limit` must be positive, and its `ItemKey` must equal the source key. Both touched stacks must already obey that limit. Different IDs or component payloads reject the operation. Metadata does not become part of the item key.

`components` is an opaque immutable string at this foundation layer. The caller must supply canonical payloads if differently serialized equivalent components should merge. Strings `"{}"` and `"{ }"` are different keys here. Registry defaults, component patches, effective limits derived from components, SNBT/JSON interpretation, and vanilla item-specific semantics belong in the metadata/component integration layer. Test payloads are synthetic exact-identity fixtures.

## Transaction behavior

The operation first validates both indices, then rejects same-slot transfers. Split/merge destination requirements are checked next, followed by source presence, destination-stack validity and compatibility, metadata identity, stack count validity, and available room. Every rejected branch returns the inventory owner with every backing slot unchanged.

Error constructors and diagnostic strings are:

| Constructor | String | Condition |
| --- | --- | --- |
| `InvBounds` | `bounds` | Either index exceeds logical length or physical capacity. |
| `InvSameSlot` | `same_slot` | Source and destination indices are equal. |
| `InvSplitNeedsEmpty` | `split_needs_empty` | Split targets an occupied slot. |
| `InvMergeNeedsStack` | `merge_needs_stack` | Merge targets an empty slot. |
| `InvNoSource` | `no_source` | Source is empty. |
| `InvInvalidStack` | `invalid_stack` | An occupied destination has count 0; source count is 0; or either touched count exceeds the supplied limit. |
| `InvDifferentItem` | `different_item` | Occupied destination has a different ID or components string. |
| `InvBadMetadata` | `bad_metadata` | Metadata key differs from source, or limit is 0. |
| `InvFull` | `full` | Compatible destination is already at the supplied limit. |

Successful movement returns `InvMoved` with the actual amount. Source depletion produces `InvEmpty`; a positive destination preserves the complete source key. An otherwise eligible zero request returns `InvMoved{0}` with exact state identity, including an empty destination remaining empty. An ineligible zero request still returns its validation error; full destinations reject with `InvFull`.

Examples with limit 64:

- Moving 30 from count 64 into count 63 moves 1, yielding counts 63 and 64.
- Splitting 50 from count 3 into an empty slot moves 3, empties the source, and gives the destination the source's exact key.
- Equal IDs with different component strings reject and preserve both slots.
- Index 4 on a four-slot backing array rejects even if an externally assembled inventory claims a larger logical length.

## Arithmetic, ownership, and cost

After validation, the U32 transaction passes the request, source count, destination count, and checked free room into `move_counts`. This calls the tail-recursive `move_counts_loop` used by the proofs. Each step decreases source and room while increasing destination and the reported moved count by one. It stops at the first exhausted request, source, or room.

The Nat arithmetic kernel is on the actual implementation path; it is not a detached specification. Its output crosses back to U32 only in `commit_counts`. Validated source counts and bounded room keep the resulting counts in the U32 range. The two array writes occur only after successful validation and completed pure planning. A zero-move commit returns the original owner without writes.

Array access and updates use O(log backing capacity) tree paths. Planning uses O(actual moved count) iterations and constant continuation space. Ordinary bounded stacks keep that loop short; metadata with very large limits and equally large transfers can take correspondingly long. This foundation does not establish a performance comparison with Minecraft.

## Verification and precise proof scope

`src/inventory_laws.bend` and `src/inventory_proof.bend` contain mechanically checked laws for:

- Exact Nat source-plus-destination conservation in the actual loop and its public count wrapper.
- Exact source decrement equal to the reported moved count.
- Identity for zero requests and zero room.
- Exact affine inventory identity in the actual bounds, same-slot, full-destination, incompatible-item, invalid-stack, invalid-metadata, mode-error, and empty-source branches.
- Exact zero-move commit identity.

Auxiliary Nat equations support those implementation laws. The formal conservation scope is the actual arithmetic kernel. The public U32 conversions, array updates, equality classifiers, bounds computation, and registry metadata correctness are covered by type checking and native testing; they do not have a complete end-to-end conservation theorem in this module. Rollback equations cover the named real guard branches, rather than proving the caller's Boolean validation computation.

`tests/inventory.bend` executes the real module in a compiled native CPU binary. `tools/test_inventory.py` supplies an independent Python integer/clamping oracle; it never implements observed gameplay transitions. The test compares status and every physical slot, checks per-item count conservation, and checks exact state preservation on errors. Fixtures include injected limits, malformed counts, empty slots, immutable component distinctions, self-transfer, logical and physical bounds, oversized logical lengths, maximum U32 counts/requests, construction, loading, and reads.

Reproduce:

```sh
python3 tools/test_inventory.py --verdict
```

The default run checks 13,671 oracle cases and two unsupported Array construction probes, including 5,000 deterministic fuzz cases with seed 2,630,103. `evidence/inventory-oracle.json` records the checker/kernel result, native backend, fixture digest, source hashes, commands, counts, and measured orchestration time. These are independent arithmetic and transaction tests. They are not Java-reference fixtures and establish no Minecraft 26.3 menu, recipe, creative, or component-resolution parity.
