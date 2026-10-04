# Pinned 26.3 furnace authority

`src/furnace_authority.bend` implements the authoritative three-slot furnace,
blast furnace and smoker state machine in Bend. It consumes the committed
`cooking_recipe.Catalog/Plan/complete` contract. Campfire is a separate owner.
This module is ready for a block-entity consumer; it is not a claim that furnace
blocks, menus, world scheduling, player XP or live durable persistence are joined.

## Integration API

Import `furnace_authority.bend as A`, `furnace_authority_fuel.bend as F`,
`furnace_authority_decoder.bend as FD`, `furnace_authority_slots.bend as S`, and
`furnace_authority_xp.bend as X`.

* `A.State{inventory:Inv.Inventory,frame:A.Frame}` owns its array once. Exactly
  three logical slots use a depth-two backing array; the fourth cell is outside
  every furnace slot operation.
  `A.new(kind)` accepts smelting/blasting/smoking and refuses campfire.
* `A.Frame{kind,lit_remaining,lit_total,cooking_spent,cooking_total,speed,cached,uses}`
  carries raw Java signed integer **bits** as U32, F32 speed, an ephemeral cached
  recipe ID, and `List<A.Use{recipe_id,count}>` signed-bit use counters. Counter
  order is not represented as Java identity-hash iteration order.
* `A.inspect(state)` returns `(state,Maybe<A.Snapshot>)`. It checks logical length
  and actual backing capacity before reads. Snapshot contains the frame and
  `K.FurnaceSlots{input,fuel,output}` immutable values.
* `A.step(state,cooking,fuel_catalog,context,profiles,metadata)` returns
  `(state,Result<String,A.Effects>)`. Failed validation/evaluation preserves the
  original owned state. Accepted transitions atomically write the three cells.
  `Effects{dirty,lit_change,drops,completed}` names world effects. The consumer
  must apply them to its actual position and block state at the vanilla 20 Hz
  cadence. Dropped fuel crafting remainders use block integer XYZ in Java.
* `S.put(state,cooking,index,value,metadata)` reproduces low-level
  `Container.setItem`: count clipping to `min(64,item limit)`, input identity
  comparison ignoring count, and progress/time recalculation only for changed
  input identities or clearing. It does not own an external cursor/source slot.
  Menu/hopper consumers must separately perform transfer ownership and permission
  checks. `S.can_place`, `slots_for_face`, and `can_take` expose actual placement
  and face rules; bottom fuel extraction consults the actual
  `minecraft:furnace_fuel_bottom_takeable` item tag.

Caller metadata must admit the **exact complete** `Inv.ItemKey`, a limit 1–99,
and a positive count within that limit. Default stacks use shared item
definitions. No envelope prefix grants metadata or fuel authority. Unsupported
current recipe subclasses remain `K.Unsupported` and cannot be cooked.

The future block consumer owns block validity for the entity type, active-world
context truth, fuel/recipe pack reload, slot transfer permissions, block teardown,
dirty/save scheduling, RNG and XP/player effects. It should retain the owned
state across every call; rendering and menu polling do not advance timers.

## Fuel catalogue and component admission

The pinned initialized registry contains 347 items with `minecraft:cooking_fuel`,
not a small enumerated product fuel table. Its component uses resolvable integer
burn-time and float speed constants or resource keys. The production decoder
derives default fuel definitions **from the complete initialized component maps**;
it does not trust a second item/fuel table.

`FD.catalog(JSON)` accepts `ints`, `floats`, `predicates`, resolved block `tags`,
and `defaults` arrays. Resource rows are `{id,source}`; defaults rows are
`{id,components}`. Duplicate IDs and error-shaped defaults are rejected. Caller
pack precedence must already select one definition per key. The reference tool
writes this loadable catalogue to ignored
`build/furnace-authority-reference/fuel-catalog.json`.

Production expressions implement constants, registry references, integer
`minecraft:div`, integer/float `minecraft:conditional`, and `match_block` block
sets/tags. These cover every installed cooking provider. Unknown expressions
retain their raw JSON in explicit `Other*` variants and refuse evaluation.
Other predicate profiles, including block `state`/`nbt` constraints, are not
silently simplified. Decoder structural depth is 256; `F.Context{block,max_depth}`
supplies the evaluation budget and real block identity. Exhausted/cyclic or
unresolved nested references refuse rather than impersonating valid fuel.

Resolvable missing root provider keys use actual Java fallbacks: integer zero,
float one. Missing fuel components use the same pair. Arithmetic division by
zero is caught as integer zero. Division truncates toward zero and
`MIN_INT / -1` wraps. Provider float nonfinite results become zero; direct
resolvable float constants retain their value. Resource-key and component codec
numeric support is the existing signed-integer-lexeme/F32 JSON domain.

`FD.admit(initialized_defaults,key,patch)` calls the shared `C.resolve`, requires
the exact canonical component identity, applies the same decoded changes, and
derives both metadata and cooking-fuel meaning from that effective map. It returns
`F.FuelProfile{key,fuel,metadata}`. Supported shared setters/removals remain the
crafting component codec domain; a generic `cooking_fuel` setter is explicitly
outside that codec. Resource provider reloads remain data-driven. Removing fuel
from a known profile changes its duration to zero, while unrelated supported
patches preserve the actual fuel component. Canonical marker strings alone and
unverified generic component setters are not admitted.

## Actual transitions

The tick decrements a positive lit timer before deciding whether to cook or
ignite. Fuel speed is evaluated against current block context at ignition and
retained afterward. Installed furnace speed is 1; smoker/blast speed is 2. Fuel
duration is divided by 2 in fast blocks, including odd durations: dried kelp
4001→2000 and wool carpets 67→33. Cooking recipe raw duration stays 200 for all
107 installed furnace-family recipes; effective duration uses the shared float
divide/ceil/Java-int conversion.

Ignition writes duration/total/speed even when duration is nonpositive. It
rescales unfinished positive-total progress using float ratio and ceil. Positive
fuel consumes one unit. Item crafting remainder replaces the emptied fuel slot;
if fuel remains, the complete remainder stack is dropped. Remainders come from
the item definition, not an invented component `use_remainder` rule.

A lit, matched, capacity-accepted tick increments progress with signed wrapping.
Completion resets progress, recalculates time, uses the authenticated shared
completion plan, and increments that recipe's signed use counter once. Full or
incompatible output resets progress. The actual active **recipe miss preserves
progress** and cached ID. Cached matches win before catalogue-order fallback;
a miss never overwrites the previous cache. No active fuel/input branch cools
positive progress by two with Java's signed min/max clamp, even when persisted
total time is negative. Initial total zero can complete immediately on ignition
if no prior input write initialized it.

Lit decrements and ordinary progress increments alone do not emit dirty. Fuel
consumption, completion and lit-state changes do. Wet sponge completion with a
bucket fuel slot uses shared Java behavior: the whole bucket stack becomes one
default water bucket, including after a lava fuel remainder replaced that slot.

## Save and XP seams

`A.save(state)` returns `(state,Result<A.Persisted>)`, preserving the owned array.
`Persisted{slots,cooking_time_spent,cooking_total_time,lit_time_remaining,
lit_total_time,speed_multiplier,recipes_used}` maps exactly to the vanilla
`Items`, four integer fields, float field and `RecipesUsed` unbounded
recipe-key→signed-int map. `A.load(cooking,kind,persisted,metadata)` validates
slot/metadata/count authority and unique valid use keys, then creates the owner;
the ephemeral recipe cache starts absent. The Java receiver resets its item list
before container decoding, defaults missing timer fields to zero, speed to one,
and missing/failed recipe-use decoding to an empty map. A future physical NBT
consumer must implement those ValueInput rules with the existing item-component
codec owner. This typed seam is not an NBT parser or crash-recovery protocol.

`X.pop(catalog,frame)` projects current-registry `XpRequest{id,uses,experience}`
values and **does not clear counters**. Deleted recipe keys are skipped. A
non-cooking current subclass under a used key explicitly fails: the real receiver
casts to `AbstractCookingRecipe` and throws `ClassCastException`. The projection
does not claim Java's partial world side effects if another entry spawned XP
before such a failure. `X.ordered(requests,caller_order,[])` requires every current
request exactly once; it accepts the actual caller traversal order, not a guessed
canonical order. Java `Reference2IntOpenHashMap` traversal depends on process
object identity. Exact shared world RNG sequencing still belongs to the consumer.

`X.award(request,nextFloat_ticket)` and `advances_rng(request)` reuse the checked
shared cooking arithmetic. Award uses current recipe rate, signed uses, float
multiplication, floor and strict nextFloat threshold. `X.clear_state(state)`
preserves all cells/timers/cache and clears only recipe uses; call it after the
consumer's successful player award/recipe-trigger sequence. The Java player
award receiver clears afterward, while pop/break projection does not. Orb merge,
spawn, player pickup and recipe-trigger integration are not implemented here.

## Verification

Run `python3 tools/reference_furnace_authority_probe.py`, then
`python3 tools/test_furnace_authority.py`, and
`python3 tools/test_furnace_authority.py --proof-only` within the shared two-job
limit. No cooking/crafting corpus replay is required.

The headless Java fixture calls actual `serverTick`, `setItem`, fuel receivers,
cached `RecipeManager`, current-registry XP pop and provider/predicate codecs.
Its `ServerLevel` overrides world I/O only; normal ItemEntity and ExperienceOrb
constructors run. The XP spawn fixture supplies empty collision/entity queries.
It loads installed provider JSON through actual `DIRECT_CODEC`s into predeclared
holders and freezes registries. `VanillaRegistries.createWorldLookup` alone lacks
those reloadable registries; the earlier failure is recorded, not replaced by a
default-value table. Reference code is never part of production simulation.

Evidence lives in `reference/furnace_authority.json`,
`evidence/furnace-authority.json` and `evidence/furnace-authority-proof.json`.
The checked native fixture matches 1,041 actual fuel/context receivers
(347 items × three block contexts), 27 owned-state scenarios with 28 operations,
and five current-registry XP receivers using all 1,658 initialized component
maps. One- and four-thread results are identical. All 23 selected law roots
pass the independent kernel, with no exclusions or open holes.
The laws cover real affine rollback/admission, cache retention, exact remainder
routing and count boundary, provider fallbacks, persisted fields, current-subclass
refusal and XP clear preservation. Checked-root export retains original types,
bodies, proof terms and declaration maps before the independent kernel verdict.
These are structural/authority laws, not a whole-world equivalence theorem or
proof of all IEEE arithmetic/array internals.

The separately committed shared dispatch repair is checked by
`tools/test_furnace_authority_dispatch.py`: 80 full recipe/result comparisons
on each of one and four native threads. The controlled seven-file source check
in `tools/furnace_authority_dispatch_memory.py` observes the same unchanged
dependencies on both sides of the repair. These checks exercise both changed
entry points; they do not replay the previous crafting corpus.
