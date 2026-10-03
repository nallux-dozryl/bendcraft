# Pinned Java 26.3 item and stack reference

Confidence is high for the recorded registry identities, initialized default components, metadata, and primitive Java calls. This reference supplies inventory integration inputs. It does not establish inventory-click, menu, UI, network, or gameplay parity.

[The metadata table](../generated/reference_item_metadata.tsv) covers all 1,658 items and is 556,426 bytes. [The fixture and shared dictionaries](../reference/item_stacks.json) contain 3,626 cases, 122 component type records, 3,908 typed component values, 1,689 component sets, and 703 stack snapshots. Repeated values and snapshots are shared by file-local integer indexes, keeping the JSON around 5.28 MB. No generated Bend checker or game assets are included.

## Authority and reproduction

The probe uses the installed Microsoft OpenJDK 25.0.1+8-LTS launcher runtime and the verified official 26.3 server class jar. It verifies the official server bundle, nested class jar, and every manifest library before running. It records the actual runtime version/executable hash, Java helper source hash, 13 named core class hashes, 71 relevant method declarations/body hashes and direct bytecode references, and hashes for the 66 item classes actually observed. No mappings, decompiler, library, or newer Minecraft version is downloaded.

| Artifact | SHA-256 |
| --- | --- |
| Official server bundle | `d052f14d7a173734fba553711e5b570162e2f2a313267ee31a21b975a679be64` |
| Named server class jar | `a362163eec5d1612d520772bc16e5b39c09e3b234fdc045f56bf544284ee8ae6` |
| `net.minecraft.world.item.Item` | `867aecf8c2f0ba85c51ca7100835b6a980dff24c176a2dd6ab3780605c24b9e6` |
| `net.minecraft.world.item.ItemStack` | `c6d650ae8248b529b5db7f0d27376ecb8cf48dfce8eb89bf3280902dcc9ece32` |
| `net.minecraft.world.item.ItemInstance` | `521f3b75429ab5eb64e051e5a3b0f03d7ab2a597f8c9dc5d473015ad3b68b476` |
| `net.minecraft.core.component.DataComponents` | `01c617441b2e5ae67f0f4fd26728f9b37cb8993204d1b8ea8aec0c0c6a4ab6da` |
| `net.minecraft.core.component.PatchedDataComponentMap` | `ad1ef51aa0e44c336c4e957191394a3506a083fe45a7c7e8fafc14991633a9ff` |

Run from `minecraft/`:

```sh
python3 tools/reference_item_probe.py
python3 tools/reference_item_probe.py --verify-existing
python3 tools/reference_item_probe.py --selftest
```

The Java setup calls `SharedConstants.tryDetectVersion()`, `Bootstrap.bootStrap()`, and `VanillaRegistries.createWorldLookup()`. In 26.3, item defaults are initialized through `BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup)` followed by each official `Holder.Reference.bindComponents` call. Bootstrap alone is insufficient for this reference. The official registry-aware serialization context then encodes actual `DataComponentMap` and `TypedDataComponent` values.

Every initialized item component map is equal to its separate official generator report: **1,658 matches, zero mismatches**. The canonical report tree hash is `51e06feb925becc15b1fa24ebd3a02e421282f8d4a51167af089498f6eedef4a`. Equality of these data layers does not establish component behavior, codec decoding, reload composition, or mutable-value semantics.

The Java helper and raw observations remain ignored under `reference/extracted/item_probe` and `reference/cache`. Reflection reads the private stored count, item holder, and component map so the fixture can distinguish internal storage from public empty-stack views. The methods under test execute from unchanged official classes. Every fixture starts with a fresh ordinary stack; the shared `ItemStack.EMPTY` count is reset and its raw patch cleared before each fixture to prevent cross-case contamination. These resets are extraction isolation, not inventory operations.

Evidence is [extraction](../evidence/reference_item_probe.json), [validation](../evidence/reference_item_validation.json), and [two independent runs and malformed-evidence rejection](../evidence/reference_item_selftest.json). The canonical observations hash is `daf82f2e5dea6bc18ea44bed39f42e1a4c0619f2b43de8f15c63df22597bf5bd`. Evidence records the complete JSON and table fingerprints.

## Default metadata

The TSV includes actual item protocol ID, identifier, class, description ID, item-level default maximum stack size, default-stack maximum size/damage/count, stackability/damageability, container nesting, required feature names and default-feature enablement, rarity, use animation, foil/enchantable observations, crafting remainder, component-set index, and independent runtime/report component fingerprints.

| Observation | Count |
| --- | ---: |
| Item defaults with maximum stack size 64 | 1,342 |
| Item defaults with maximum stack size 16 | 68 |
| Item defaults with maximum stack size 1 | 248 |
| Default stacks with positive maximum damage / damageable | 84 |
| Default stacks observed enchantable | 77 |
| Items accepting container nesting | 1,641 |
| Items rejecting container nesting | 17 |
| Items requiring the vanilla feature flag | 1,658 |
| Items with a crafting remainder template | 5 |

The 17 nesting rejections are the uncolored and 16 colored shulker boxes. The five crafting remainders are water/lava/milk buckets producing one bucket and dragon breath/honey bottles producing one glass bottle. These are observed templates; the probe does not execute crafting or consume/use remainder workflows.

Air is the sole default stack that exposes count zero and is empty. Its item default maximum is 64, while its empty stack reports maximum stack size 1. Consequently the default-stack distribution is 1,341 at 64, 68 at 16, and 249 at 1. This distinction is explicit in separate TSV columns. The observed item constants are default maximum 64, absolute maximum 99, and bar width 13. Primitive count setters are separately observed and do not enforce those stack-size constants.

Default rarity counts are 1,543 common, 78 uncommon, 18 rare, and 19 epic. Use-animation values and flags are actual calls on default stacks. They are metadata observations; animation rendering, use duration, entity interactions, and effects remain outside this probe.

## Fixture and dictionary interface

Schema version is 1. `observations.cases` stores `id`, `operation`, `input`, `tags`, and `expected`. Expected stack states reference `stack_snapshots` by integer index; immutable component-map observations reference `component_sets`. All registry item/type IDs are the official pinned IDs. Dictionary indexes are file-local references and must not be confused with registry IDs.

- `component_types` preserves each registered component identifier, protocol ID, transient/swap flags, and actual `DataComponents` generic field declaration.
- `component_values` preserves the type ID and identifier, actual Java value class, transient flag, official codec-encoded JSON value or codec error, and exact raw primitive value for Integer/Boolean/String values. Each record has a canonical payload hash. Unit, Boolean, Integer, absent, and removed components are distinct.
- `component_sets` contains sorted `[type_id, component_value_index]` pairs. Its hash is over the pairs with value hashes substituted for indexes. Duplicate types and wrong type/value references are rejected.
- `stack_snapshots` preserves signed stored count, its eight-digit two's-complement bits, observable count, stored/observable item, shared-empty identity, public/stored component-set indexes, public component patch, damage and stack predicates. `stored_item: null` is the shared singleton's absent internal holder; it is not an item identifier.

The public and stored component maps are both retained. An ordinary zero/negative-count stack can hide its original item/components through its public methods while retaining those fields internally. A later primitive mutation may expose them again. Snapshot hashes substitute component-set hashes for file-local indexes, making content identity independent of dictionary indexing.

| Operation | Cases |
| --- | ---: |
| Construct/default patch observation | 73 |
| `copy` | 66 |
| `copyWithCount` | 569 |
| `split` | 569 |
| `grow` | 569 |
| `shrink` | 569 |
| `setCount` | 569 |
| `limitSize` | 469 |
| Item/component equality and `matches` | 133 |
| `setDamageValue` | 32 |
| Copy then replace primitive or name components | 6 |
| Deliberately mutate a shared literal-name value | 1 |
| Immutable map snapshot followed by source mutation | 1 |

Targeted cases cover air, stone, egg, diamond sword, potion, and shulker box; signed count edges include `Integer.MIN_VALUE`, negative/zero counts, 1/16/64 boundaries, and `Integer.MAX_VALUE`. The shared empty singleton has an explicit lane. Another 500 cases use independently generated signed 32-bit counts/amounts, from seed `26316585023`. Expected answers come exclusively from actual Java execution; Python does not implement arithmetic or component-equality expectations.

## Observed signed count and emptiness rules

`isEmpty` is true for the shared singleton, an air item holder, or a stored count at most zero. Empty stacks expose `getCount() == 0`, `getItem() == air`, and empty public component/prototype/patch maps. Ordinary empty stacks retain their original holder, signed count, and stored component map. Air stays empty even with a positive stored count. The shared singleton stays empty by identity even when its count field is set positive.

`setCount(int)` stores the signed integer directly. `grow(int)` adds the amount to **observable `getCount()`**, using Java 32-bit overflow, and stores the result. `shrink(int)` calls grow with Java integer negation. Thus:

- `grow(1)` on stone stored at `Integer.MAX_VALUE` stores `Integer.MIN_VALUE`, which exposes count zero and air.
- `grow(1)` on stone stored at `-1` stores `1` and exposes stone again: the addition starts from public zero.
- `shrink(Integer.MIN_VALUE)` on count 1 stores `-2147483647`, because negating the minimum integer overflows.

`copy()` returns the shared empty singleton when the source is empty. `copyWithCount` first makes the same emptiness check; an empty source stays the singleton regardless of the requested count. For a nonempty source, setting the copy's count to zero/negative produces an ordinary empty copy with its original holder/components, rather than the singleton.

`split(amount)` computes `Math.min(amount,getCount())`, creates a copy with that count, and shrinks the source by it. Negative requests therefore preserve the actual primitive behavior: splitting `-1` from stone count 1 leaves source count 2 and returns an ordinary empty copy with stored count -1. These signed edge observations do not prescribe which external inventory requests should be accepted.

`isSameItemSameComponents` compares public item identity, then returns true if both stacks are empty; otherwise it compares stored patched component maps. Count is ignored by this method. `matches` adds observable count comparison. Empty ordinary stacks with different stored items or different hidden literal names can therefore compare equal, because both expose air and count zero. Positive-count equality fixtures preserve component presence, type, and value separately.

## Observed component mutation and remaining coverage

Explicit patches use actual Java values for maximum stack size, maximum damage, damage, repair cost, unbreakable Unit, glint Boolean, and literal custom name. Setter/removal fixtures cover copy-on-write map behavior and `immutableComponents()` map snapshots. Replacing a copied stack's damage/name values leaves the original map unchanged; later replacing the source repair-cost value leaves the copy unchanged.

This is map isolation. A deliberate `MutableComponent` literal-name test observes that `copy()` shares the custom-name value object. Appending `"-suffix"` through the copy changes both names. That counterexample prevents a false claim that copying a stack deep-copies all component values. The probe does not invent a universal mutable-component model or infer immutability from codec JSON.

`setDamageValue` clamps through the actual maximum-damage getter. Direct `set(DataComponents.DAMAGE, value)` has a separate observed path. Direct internal component setters can retain values rejected by their codecs: maximum stack size zero is stored and exposed, but encoding reports `Value must be within range [1;99]: 0`; negative maximum damage and damage also retain distinct primitive values and recorded codec errors. Codec rejection and primitive setter behavior are separate observations. The probe does not claim complete `ItemStack` serialization or validation coverage.

Verification checks official registry identity, all report comparisons, table integrity, deterministic input generation, every typed value/set/snapshot hash, signed count encoding, and equality with independent Java observations. Two fresh runs reproduce all organized metadata and fixtures. Malformed evidence tests reject a wrong count encoding before and after checksum resealing, a semantically wrong default limit with resealed observation metadata, and a component value assigned the wrong type even after its own checksum is resealed.

World/entity-dependent operations remain unavailable here: inventory ticks, attack/mining/use/place effects, durability break events and randomness, enchantment application, consumable conversion, permissions, entity abilities, crafting execution, recipe matching, container-click modes, menus/slots/cursors, tooltips/localization, resource rendering, stream/network codecs, save/load/decoding, full component mutation coverage, and data-pack reload defaults. Component JSON fingerprints preserve official serialized values, not every nested runtime floating-point bit or hidden behavioral dependency. Subtype hashes establish source identity; they do not prove context independence.
