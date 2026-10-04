# Cooking block-entity physical NBT

Confidence: high for the stated physical codec and refusal contract. This is the pinned Java **26.3** cooking-body codec, implemented in Bend. It does not establish a durable region writer or whole block-entity base-component parity.

`src/cooking_block_entity_codec.bend` consumes the existing furnace and campfire authority records directly. `cooking_block_entity_codec_items.Context{recipes:K.Catalog,defaults:List<C.Default>}` must contain actual initialized item defaults and the current item registry definitions. A caller-supplied component envelope is never admission authority.

| API | Result |
| --- | --- |
| `decode_furnace(context,limits:N.Limits,bytes:List<U32>)` | `Result<String,FurnaceDocument{record:FA.Persisted,details:Details}>` |
| `decode_campfire(context,prior:CA.Record,limits,bytes)` | `Result<String,CampfireDocument{record:CA.Record,details:Details}>` |
| `encode_furnace(context,limits,FA.Persisted)` | `Result<String,List<U32>>` |
| `encode_campfire(context,limits,CA.Record)` | `Result<String,List<U32>>` |
| `load_furnace(state:FA.State,context,limits,bytes)` | Same affine owner and `Result<String,Details>` |
| `load_campfire(state:CA.State,context:CI.Context,limits,bytes)` | Same affine owner and `Result<String,Details>` |
| `save_furnace(state,context,limits)` / `save_campfire(state,context,limits)` | Same owner and encoded-byte result |

The encoded root has the empty name and a Compound body. Furnace/blast/smoker kind comes from the existing live owner; campfire kind and LIT also stay with the live block. Recipe caches are omitted from persistence and cleared on successful loads. Failure retains the complete old owner, including timers, cache, inventory backing capacity and hidden backing cells. Furnace writes begin only after `FA.inspect` confirms three logical slots and sufficient backing capacity.

`Details{root_name,extras,inputs,admission,discarded}` is explicit codec metadata. `inputs` retains exact canonical `CI.Input{slot,patch}` values; `admission` contains metadata and fuel profiles rebuilt from initialized defaults and verified effective identity. `extras` retains all physical fields outside the known cooking body, with UTF-16 names, types, duplicate occurrences and values. This includes CustomName, Lock and base BlockEntity `components`. The known-body encoder omits these fields. A base-block-entity/world persistence consumer must retain that sidecar and implement the relevant base codecs before claiming a complete save. Unknown fields are not silently lost during decoding, and unknown base fields are not presented as interpreted cooking state. `discarded` counts invalid or unknown top-level item/component entries; it is not a reproduction of Java's ProblemReporter diagnostics.

The component helper `cooking_block_entity_codec_components.patch(initializedMap,key)` returns a canonical JSON patch only after the shared component decoder and `C.resolve` reproduce the **exact** key. It computes differences against the initialized effective map, removes redundant default assignments and preserves ordered stew effects. It rejects malformed envelopes, unsupported setters, wrong effective identities and invalid resolved combinations. Its envelope parser has the existing 1 MiB/256-depth bound; callers can report that concrete resource boundary. Valid reconstruction does not validate stack count; live admission performs that separate check.

## Receiver semantics

The physical decoder uses the existing uncompressed NBT primitives and caller-supplied limits. Compound fields have Java's last-physical-occurrence semantics. Invalid or noncompound roots return explicit failures.

* Furnace `cooking_time_spent`, `cooking_total_time`, `lit_time_remaining` and `lit_total_time` are saved as Int tags and carried as signed Java-int bit patterns. Missing or nonnumeric fields default to zero. Byte/Short sign-extend, Long takes its low word, and Float/Double floor before saturated Java-int conversion. NaN becomes zero.
* `speed_multiplier` is saved as Float and defaults to 1. Numeric coercions follow the actual NumericTag receiver. Signed Long rounds directly once to float, avoiding a double-rounding error. FloatTag/DoubleTag construction normalizes either signed zero to its cached positive zero; a nonzero negative Double that underflows to float retains negative zero in the live record. Saving through FloatTag normalizes that zero and canonicalizes NaN payloads, matching Java. Therefore record→bytes→record normalizes those values rather than preserving arbitrary NaN payloads.
* Items use actual optional Slot and count behavior. Unknown items, air and malformed rows are skipped. Missing/invalid Slot defaults to zero, numeric Slot uses unsigned-byte coercion, out-of-range destination indices are ignored, and the last valid row for a slot wins. Missing, wrong-type or out-of-range count defaults to one; physical count admits 1..99.
* The shared verified component domain supports seven setters: max_stack_size, max_damage, damage, repair_cost, suspicious_stew_effects, unbreakable and enchantment_glint_override, plus registered persistent removals. Unknown/unregistered entries and invalid supported values are discarded as Java codec partials do. Invalid stew effects are removed while valid siblings retain order, including mixed list streams and Java's empty-name list wrapper; an entirely invalid list produces an empty partial effect list. Omitted duration is 160. Boolean NBT values use `Number.doubleValue()!=0.0`, including fractional values and NaN. Redundant default patches disappear.
* A registered persistent setter outside that verified domain, such as a valid custom_name setter, refuses the complete load. The codec does not invent generic setter parity or silently turn valid unsupported data into defaults. Distinct names that normalize to the same component or RecipesUsed identifier also refuse where Java map traversal has not been established.
* RecipesUsed is a Compound of qualified identifiers and Int counts, preserving signed count bits even for deleted recipes. Its codec retains valid entries beside malformed identifiers/values; numeric count conversion truncates, whereas timer fields floor. Missing or wrong-type maps become empty. No recipe lookup or XP award happens while decoding. A valid recipe identifier may be minecraft:air; item admission restrictions do not apply to recipe keys.
* Campfire Items always clear before loading. CookingTimes/CookingTotalTimes are IntArrays. Absent or wrong-type arrays reset all four destinations. A present short array copies its prefix and retains the prior tail; a present empty array retains the entire prior timer array. Long arrays copy only four entries. The two timer arrays are independent.

Physical Java ItemStack decoding accepts coal count99 although its stack limit is64. This codec preserves that record. Existing FA/CA live authorities refuse overstacked state atomically. Supporting such state in live gameplay requires a coordinated authority change; it is not clamped or silently dropped here. Full generic component setters and base BlockEntity component interpretation remain separate concrete seams.

## Verification and integration

`reference/cooking_block_entity_codec.json` records **65 actual Java receiver observations** from normal FurnaceBlockEntity, BlastFurnaceBlockEntity, SmokerBlockEntity and CampfireBlockEntity constructors, `NbtIo.read`, `loadWithComponents`, and `saveCustomOnly`. Inputs cover numeric coercions, signed zero/NaN, the signed64 single-round boundary, count defaults/99, duplicate slots/keys, partial patches/effects, remainders in initialized profiles, RecipesUsed partials and campfire array lengths. No gameplay runs in Python, and no jar or assets are committed.

The native one/four-thread harness compares **64 exact encoded cooking bodies** across the initial changed run and three focused list/recipe-key cases, including physical tag types, empty-list headers, raw numeric bits and ordered patches. It compares all supported record fields/full effective item components, one explicit unsupported-component refusal, two live admission refusals and two malformed-wire refusals. It checks cache retention/reset and the hidden furnace backing cell. Source and output identities are in `evidence/cooking-block-entity-codec.json` and `evidence/cooking-block-entity-codec-lists.json`. The initial 62-receiver observation snapshot remains in `reference/cooking_block_entity_codec_initial.json`; the final reference adds two list-stream observations and an air-named recipe-key regression.

`src/cooking_block_entity_codec_laws.bend` and its proof file cover actual owner refusal, backing refusal, save ownership, integer preservation, item clearing, campfire prefix behavior, record decomposition roundtrip and malformed component/effect sibling retention. All **27** laws pass the ordinary checker. **22** are selected for the independent kernel with unchanged checked types/bodies, no holes, axioms, unsafe declarations or export exclusions. Five full campfire-load/save/item-decode laws reach the existing `json.encode_go` dependency, which the independent kernel rejects as affine live code with descending calls; these remain ordinary checked and native compared. The receipts state that limitation explicitly. No theorem claims complete physical wire roundtrip or full IEEE arithmetic parity.

Reproduce the changed targets:

```
python3 tools/reference_cooking_block_entity_codec.py
python3 tools/test_cooking_block_entity_codec.py
python3 tools/test_cooking_block_entity_codec.py --proof-only
```

The `cooking_world*` owner can consume the direct FA/CA records and atomic wrappers now. Root still owns physical region/chunk framing, compression, durable writes and interruption/corruption recovery. A successful codec build is not a completed live save/reload workflow.
