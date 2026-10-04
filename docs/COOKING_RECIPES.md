# Cooking recipes, pinned Java 26.3

Confidence: **high for the stated decoder domain, pure completion boundary,
and observed arithmetic**. Furnace/campfire blocks are not integrated by this
lane. Recipe resources and registry facts do not establish completed gameplay.

`src/cooking_recipe.bend` implements cooking recipe representation, matching,
trusted output assembly, plan authentication and furnace completion in Bend.
`src/cooking_recipe_decoder.bend` reads the installed resource schema with the
existing Bend JSON parser. `src/cooking_recipe_number.bend` implements the
observed Java float/integer arithmetic. Python extracts primary reference facts,
orchestrates checks and compares outputs; it implements no cooking gameplay.

The installed jar contains **116** cooking recipes: 73 smelting, 25 blasting,
9 smoking and 9 campfire cooking. All 107 furnace recipe resources explicitly
specify a **200-tick base**; all campfire resources specify 600. Blast/smoke
speed is a block/fuel multiplier, not a 100-tick recipe default. The 26.3
`AbstractCookingRecipe.cookingMapCodec` requires `cookingtime` as `Codec.INT`
and has optional `experience` as `Codec.FLOAT`, default 0. It imposes no
positive-time or nonnegative-XP range.

## Stable consumer interface

Import `cooking_recipe.bend as K`, `cooking_recipe_decoder.bend as KD`, and
`cooking_recipe_number.bend as N`.

```text
CookingKind = Smelting | Blasting | Smoking | Campfire
Recipe = Cooking{id,kind,ingredient:R.Ingredient,output:Inv.Slot,
                 cooking_time:U32,experience:F32}
       | Unsupported{id,kind:String}
Catalog{recipes:List<Recipe>,tags:List<R.Tag>,items:List<R.ItemDefinition>}
Plan{recipe_id,kind,output,before:Inv.Slot,cooking_time:U32,experience:F32}
FurnaceSlots{input:Inv.Slot,fuel:Inv.Slot,output:Inv.Slot}
Completion{recipe_id,before:FurnaceSlots,after:FurnaceSlots,experience:F32}

KD.parse_catalog(text) -> Result<String,K.Catalog>
K.find(catalog,kind,input) -> Result<String,Maybe<K.Plan>>
K.find_with_metadata(catalog,kind,input,metadata) -> Result<String,Maybe<K.Plan>>
K.current(plan,input) -> Bool
K.output_metadata(catalog,key) -> Maybe<Inv.ItemMetadata>
K.complete(catalog,plan,slots,metadata,container_limit)
    -> Result<String,K.Completion>
K.completion_current(completion,slots) -> Bool
N.total_time(base_time,speed:F32) -> U32
N.fraction(uses:U32,rate:F32) -> F32
N.experience(uses:U32,rate:F32,next_float_ticket:F32) -> U32
```

**`cooking_time`, effective duration, recipe-use counts and XP amounts cross
the arithmetic boundary as signed Java int bits in U32.** In particular,
4294967295 means -1, and 2147483648 means INT_MIN. They are not unsigned tick
budgets or unsigned XP amounts. The future timer owner must interpret their
signed values when comparing or persisting them. `experience` retains F32 bits,
including negative values, subnormal values and infinity from numeric overflow.

`find` admits the existing default-component item domain. The additive metadata
entry point requires exact canonical key equality with caller-validated
`Inv.ItemMetadata`, limit 1..99, and input count 1..limit. A component-envelope
prefix is never input authority. Java ingredient matching ignores components;
inventory validity is checked before matching. Empty input cannot match even
an invalid manually constructed empty ingredient. Plans retain the full input
key/count snapshot and the recipe's base time and XP rate.

Catalog order is the caller's authoritative registry order. First matching
recipe of the selected cooking type wins. Independent `RecipeMap.create` and
`getRecipesFor` observations cover collisions and reversed order. The real
`RecipeManager` can prefer a still-matching cached recipe before this traversal;
the block owner must retain that cache and select the cached recipe before
falling back to `find`. Resource-pack loading, registry replacement and feature
admission remain loader/consumer responsibilities. Unsupported recipes are
preserved and cannot produce a plan; a pack containing an unsupported matching
recipe has an explicit parity gap rather than an implied vanilla fallback claim.

## Decoder and item identity

The interchange is the shared crafting schema:

```text
{items:[{id,limit,remainder,components?:<initialized effective map>}],
 tags:[{id,items:[id]}],
 recipes:[{id,source:<26.3 recipe JSON>}]}.
```

Tags must already be resolved by the authoritative data-pack tag loader.
Ingredient item strings, tag strings, and nonempty direct-item alternatives
reuse the checked crafting ingredient decoder and matcher. Item/tag definitions
are checked; duplicate recipe/item/tag identities and unknown ingredient/output
definitions are rejected. Known recipe types use shared `ItemStackTemplate`
component-patch decoding, initialized-default resolution, canonical effective
identity and strict assembly. The arbitrary component codec domain is exactly
the one documented in `CRAFTING_RECIPES.md`; this lane introduces no alternative
component string format and no recipe-ID dispatch table.

Signed integer lexemes through INT_MIN..INT_MAX are supported for cooking time,
including zero and negative values. Java also accepts coercions such as numeric
1.9 -> 1 and 2147483648 -> INT_MIN; these spellings are explicitly retained as
`Unsupported{...,".../unsupported_codec_domain"}`. XP accepts bounded valid JSON
number tokens (128 codepoints) with native float decoding, plus missing/null
optional values -> 0. Invalid nonnumeric XP is rejected. Optional book fields
are validated against Java's string/bool and food/blocks/misc category codecs;
they do not yet provide recipe-book UI state. Required malformed fields fail;
unimplemented output setters/missing initialized maps and unknown subclasses
remain explicit Unsupported values.

Component defaults are trusted registry initialization data, not public wire
metadata. The cooking reference initializes real item components and encodes
**177 cooking-related item maps using the full VanillaRegistries lookup**.
The older builtin-only crafting reference contains 101 serialization-error
objects, including damage-type references in netherite items. The new extractor
overrides relevant rows with full maps and omits remaining error rows; the new
decoder rejects any error-shaped defaults rather than accepting them as maps.
Missing defaults for a nonempty patch remain an explicit unsupported seam.
Default unpatched items use the shared empty component identity, regardless of
whether a map was needed for patch resolution. The seventeen suspicious-stew
profiles used by the current player consumer have fully encoded defaults and
are unaffected by those other missing registry contexts.

## Furnace completion contract

The receiver uses slots **0=input, 1=fuel, 2=output**. `complete` is the pure
accepted-completion boundary, not a tick function. It:

1. Refuses Campfire plans, stale input snapshots, invalid slot counts or missing
   component authority.
2. Reconstructs the selected recipe plan from the catalog and current input,
   comparing ID, cooking kind, canonical output, full input snapshot, time bits
   and XP bits. Caller-created output/count modifications cannot mint items.
3. Requires a nonempty strictly assembled result, then checks the actual
   `canBurn` capacity rules: an empty destination accepts the result without a
   container-limit check; a nonempty destination requires complete item/component
   equality and `existing.count + result.count <= min(container_limit,result.limit)`.
   A negative signed container-limit value refuses a nonempty destination.
4. Copies the full result into an empty destination or grows the existing stack
   by the full result count, consumes exactly one input, and clears its last unit.
5. When input is wet sponge and nonempty fuel is a bucket, replaces the entire
   fuel stack with one default water bucket. This discards bucket components and
   extra bucket units exactly as the observed private Java `burn` receiver does.
   The replacement must itself have an admitted item definition. Other fuel is
   preserved; this function does not burn fuel.

The returned Completion owns complete before/after data snapshots. The caller
must atomically check `completion_current` and apply all three slots; it owns the
actual affine inventory arrays, block revision/timer/fuel state, notifications,
sided slot rules, persistence and synchronization. Record **one recipe use per
accepted completion**, irrespective of result count, in the furnace's real
`recipesUsed` state. Output pickup and accumulated XP/recipe awards are separate
authoritative operations. Empty assembled results may satisfy raw `canBurn` with
an empty destination, but Java `serverTick` rejects them before calling `burn`;
the complete guard preserves that distinction.

`N.total_time` implements actual reflected `getTotalCookTime`: for positive
speed, convert the signed base int to float, divide in float, take ceil, and use
Java's saturating signed-int cast. Nonpositive or NaN speed returns the raw base
int unchanged. Speed and burn duration come from the real cooking-fuel component
and loot context; callers must supply them rather than assume speed from kind.

## XP and campfire boundaries

Actual `createExperience` bytecode computes the product in float, invokes
`Mth.floor(float)` and `Mth.frac(float)`, then calls the server RNG's `nextFloat`
only when the fraction is nonzero. It increments the signed integer amount iff
that ticket is strictly smaller than the fraction. `N.fraction` determines the
RNG advance, and `N.experience` computes the signed amount with the supplied
ticket. `Mth.floor(float)` in this pinned version is Math.floor in double followed
by a saturating int cast. NaN produces amount 0 but a NaN fraction still advances
the RNG; comparison cannot award an increment. IEEE NaN payload/sign propagation
is recorded but not treated as an XP amount or random-threshold distinction.

The reference **invokes actual Mth receivers**, and independently inspects the
world-dependent `createExperience` bytecode for multiplication/RNG/order/orb
call semantics. It does not invoke the whole world receiver or claim XP orb
spawning, pickup, synchronization or persistence integration. Negative XP and
signed overflow remain signed bit results, not unsigned player rewards.

Campfire recipe decoding, matching, base time and template assembly are ready.
Actual campfire block authority has **four slots**; placement consumes one item
and snapshots the recipe time. A lit tick increments each occupied slot's
progress, obtains a current matching recipe (or uses the original item if no
recipe remains), drops the enabled result, and clears that slot. Cooldown,
features, drop spawning, updates and recipe replacement belong to its block
consumer. Campfire `cookTick` does **not award cooking XP**, despite the recipe
class retaining an experience field. A furnace Completion must not be used as a
campfire placement/completion transition.

## Verification and reproduction

The pinned installed jar/classpath fingerprints, resource digests, receiver
facts and cooking-related default maps are in `reference/cooking_recipe.json`.
Original JSON resources, generated Java source, javap dumps and catalogs stay
in ignored `build/cooking-recipe-reference/`. No jar, assets or credentials are
committed. The extractor is independent of the old crafting broad-probe cache;
it reads the installed jar, extracts resolved tags, invokes item metadata and
cooking receivers, and uses committed shared default-map facts where valid.

```sh
python3 tools/reference_cooking_recipe_probe.py
python3 tools/test_cooking_recipe.py
python3 tools/test_cooking_recipe.py --proof-only
```

Only `build/cooking-recipe-reference/production-catalog.json` contains the 116
installed source recipes. `catalog.json` contains diagnostic recipes and invalid
codec cases and must never become a game registry. Full unknown recipe resources
can be passed to KD; they are retained as Unsupported, without another unchanged
crafting-corpus replay.

Native evidence in `evidence/cooking-recipe.json` covers 152 codec cases:
139 supported/accepted, 9 rejected, 4 explicit Unsupported; 834 direct ingredient
matches; 19 registry selection/admission queries; 28 transition cases with 13
accepted completions and 15 refusals; 50 reflected timing cases; and 324 XP
arithmetic cases. One/four CPU threads produce identical output; GPU is off.
The failed initial serialization context and its correction are retained in
`evidence/cooking-recipe-reference-context-failure-001.json`.

Seventeen production laws in `cooking_recipe_laws.bend` are implemented in
`cooking_recipe_proof.bend` and independently checked with zero export exclusions.
They cover unsupported/empty/invalid admission, established registry order,
component-key capacity refusal, empty-result capacity refusal, Java's empty
destination rule, one-unit consumption and last-unit clearing, snapshot retention,
absent catalog authentication, and fuel refusal/preservation. These are laws of
the actual reusable functions. They do not prove IEEE arithmetic, full JSON codec
equivalence, world ticking, orb behavior, metadata authenticity or whole-game
parity. The established checked-root exporter ordinarily checks all source,
retains original declarations/types/bodies and exports exactly these proof roots;
its source and term fingerprints are in `evidence/cooking-recipe-proof.json`.

The next concrete consumer is authoritative three-slot furnace state with real
timer/fuel/recipe-use bookkeeping and snapshot commits; a separate four-slot
campfire authority needs placement and drop completion. Neither integration is
performed by this independent lane.
