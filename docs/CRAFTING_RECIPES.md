# Ordinary crafting recipes

`src/crafting_recipe.bend` implements ordinary shaped and shapeless crafting in
Bend. `src/crafting_recipe_decoder.bend` decodes the actual installed Java 26.3
JSON ingredient/pattern/result schema and the explicit catalog interchange.
Python extracts reference inputs and compares native outputs; Java executes the
untouched pinned recipe receivers. Neither host language supplies game matching.

The jar contains 2042 recipe records: 827 shaped and 375 shapeless. Of these 1202
ordinary recipes, 1185 produce unmodified item defaults. Seventeen ordinary
recipes have suspicious-stew component patches in their result. The component
decoder resolves these against initialized item defaults; all 1202 ordinary jar
recipes are within the implemented decoder domain when defaults are supplied.
A catalog without initialized defaults retains the earlier explicit
`Unsupported{id,kind + "/patched_result"}` result. All 840 recipes of other
subclasses remain `Unsupported{id,kind}`.
The inventory includes the exact subclass counts and patched-result IDs in
`reference/crafting_recipe_inventory.json`; a recorded unknown does not establish
implementation. All 1658 item definitions and 236 item tags come from the installed
reference data/actual item observations. Source recipe JSON and jars remain in
ignored local storage and are not committed.

## Consumer API

Import `src/crafting_recipe.bend` as `R` and the decoder as `D`:

```python
R.Catalog{recipes, tags, items}
R.Grid{width, height, slots}
R.find(catalog, grid)
# Result<String, Maybe<Plan>>
R.Plan{recipe_id, output, before, consumption}
# before is the complete Grid, including dimensions and exact item/count/component
# identities. consumption is an ordered list of:
R.Consumption{slot, count, remainder}
R.current(plan, grid)
R.output_metadata(catalog, key)
# Maybe<Inv.ItemMetadata> for a decoder-produced output identity only.
R.find_with_metadata(catalog, grid, validated_metadata)
# Exact Inv.ItemMetadata values from the component inventory owner.
```

`Grid.slots` is row-major raw menu storage. Dimensions are 1..3 per axis, allowing
the player's 2x2 grid and a future 3x3 crafting table. A successful plan consumes
exactly one item from each occupied slot. `slot` is the original raw grid index,
including any empty border; it never becomes a trimmed Java-input index.
`remainder` is the actual input item's default crafting remainder, including its
count. Remainders belong to occupied input slots and are independent of which
ingredient alternative matched. The plan does not mutate the menu, distribute
remainders, insert result items, award recipes or emit drops.

The named integration is the authoritative `player_inventory.bend` menu owner:
its temporary slots 43..46 become `Grid{2,2,craft}`; a service catalog supplies
recipe/tag/item definitions. Derive menu output from `R.find`. A matched recipe can assemble to `InvEmpty`: the actual Java template creator rejects a declared count above the item limit. Such a plan has no takeable result. Before an atomic
take, recompute or check `R.current`, admit the output destination and all
remainders, then let the existing owner consume/install the plan. Integration
edits belong to that owner; this lane changes no inventory/menu/root files.

`find` returns a result only for supported ordinary recipes. `Done{None{}}` means
no supported ordinary match; it makes no assertion about an `Unsupported` special
recipe. A menu consumer must preserve that boundary rather than presenting this
module as full vanilla crafting. Candidate registry order is caller authority:
the first supported matching candidate wins. The probe independently confirms
that actual `RecipeMap.create/getRecipesFor` preserves the supplied registry order
for colliding recipes. Resource-pack precedence and the previous-recipe shortcut
belong to the outer recipe manager.

Invalid grid dimensions, logical slot length, unknown items, zero/overfull stack
counts, explicit air stacks or component modifications yield `Fail` before a
plan is produced. Ingredient matching itself compares item membership; `find`
admits only the inventory owner's default-component domain. The additive
`find_with_metadata` also admits a modified input key when the component owner
supplies matching `Inv.ItemMetadata`: exact item/component identity, known
non-air item, limit 1..99 and count 1..limit are required. An envelope prefix
does not supply this authority. Ingredient matching then uses item identity
just as Java does. Catalog entries
carry observed per-item limits and remainders. Catalog decoding rejects duplicate
item/tag/recipe IDs, unresolved ingredient IDs/tags, invalid output counts and
unknown remainder items. Tags supplied to the catalog must already have nested
references resolved by the data-pack tag loader.

`D.decode(id,json_value)` / `D.parse(id,source_text)` decode one source recipe.
`D.catalog(json_value)` / `D.parse_catalog(text)` decode:

```json
{
  "items": [{"id":"minecraft:milk_bucket","limit":1,
             "remainder":{"id":"minecraft:bucket","count":1}}],
  "tags": [{"id":"minecraft:planks","items":["minecraft:oak_planks"]}],
  "recipes": [{"id":"minecraft:stick","source":{"type":"minecraft:crafting_shaped",
    "key":{"#":"#minecraft:planks"},"pattern":["#","#"],
    "result":{"id":"minecraft:stick","count":4}}}]
}
```

This abbreviated example illustrates the schema; the real catalog includes all
referenced item/tag definitions. `parse_catalog_with` lets a caller supply JSON
size/depth budgets. The convenience catalog parser uses 8MiB/64 levels; the
single-source parser uses 65536 codepoints/32 levels. These are parser resource
budgets, not Java equivalence claims for arbitrarily large data packs.

## Matching and verification

Shaped decoding trims blank source borders, rejects unequal rows, missing and
unused keys, and bounds source dimensions to 3x3. Matching tests placements and
horizontal reflections, requiring every outside-pattern grid slot to be empty.
Shapeless matching maintains all possible injective ingredient-to-slot
assignments using at most 512 occupied-slot masks. It handles overlapping
alternatives without committing to an incorrect greedy assignment. A stack's
count does not let one grid slot satisfy multiple ingredients.

The Java probe observes 2386 grids through actual `CraftingInput.ofPositioned`,
`RecipeMap`, `ShapedRecipe.matches`, `ShapelessRecipe.matches`, `assemble` and
`getRemainingItems`: every 1185 supported jar recipe has a positive and a missing
occupied-slot case. Additional cases cover order collisions, overlapping
alternatives, source padding, offsets, mixed-tag inputs, horizontal reflection,
empty/extra slots, stack counts and bottle/bucket remainders. A declared 99-stick output is codec-admitted but actual `ItemStackTemplate.create` returns empty after strict stack validation; the Bend plan reproduces that result. Nineteen codec
edge inputs compare acceptance against the actual Java codec. In particular,
Java throws `ArrayIndexOutOfBoundsException` for an all-space shaped pattern;
Bend safely rejects it. This observation is a rejection-domain agreement,
not exception-type parity. Eighteen unsupported smithing-trim recipes cannot be
decoded in this deliberately limited Java registry context because dynamic
`trim_pattern` is absent; their source inventory and explicit Bend unsupported
status remain available and no smithing semantics are claimed.

Eleven matcher/plan laws in `src/crafting_recipe_laws.bend`, proved in the paired production
proof module, establish empty-cell admission/refusal, unsupported refusal,
exhausted injective-search refusal, retained first-match order, invalid-grid
refusal, one-unit consumption, exactly one plan entry per occupied slot, and
invalid-result refusal, and retention of the complete raw grid and validated result. These are statements
about the actual matcher/plan functions and arbitrary lists/owners. They do not
prove universal perfect-matching completeness or whole Java equivalence.

Reproduce from the Minecraft directory:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_crafting_recipe_probe.py --extract
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_crafting_recipe.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_crafting_recipe_catalog.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_crafting_recipe_components_probe.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_crafting_recipe_components.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_crafting_recipe_inputs_probe.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_crafting_recipe_inputs.py
/Users/chuah/.bend/bin/bend src/crafting_recipe_proof.bend --verdict
```

The extractor creates the complete local catalog at
`build/crafting-recipe-reference/catalog.json`; all original source recipes stay
in that ignored directory. Committed references contain observations and source
identities. Native evidence is `evidence/crafting-recipe-native.json`.
Crafting is a bounded sequential CPU operation; this module introduces no GPU
workload. Native tests exercise one and four CPU threads to detect scheduling
differences, and retain source/binary/reference identities.

## Component result boundary

Item interchange rows may additionally carry `"components": {...}`: the complete
initialized `DataComponentMap.CODEC` output for that exact item from the pinned
runtime. This is authoritative canonical data supplied by the item/data loader,
not an arbitrary user-provided default map. Existing `R.Catalog`, recipe, grid,
plan and consumption constructors are unchanged. `D.catalog` resolves result
patches before publishing recipes. `D.decode` without a catalog preserves a
normalized unresolved patch, which cannot supply output metadata or takeable
items. Explicit empty patches need no defaults.

The codec supports arbitrary combinations within this stated domain, rather
than dispatching on 17 recipe IDs:

- `suspicious_stew_effects`: an ordered list over all 40 pinned effect identities;
  duplicates retain their position and signed integer duration. Omitted or
  nonnumeric duration uses Java's lenient default 160. Explicit 160 is omitted
  from the canonical entry. Fractional/exponent numeric coercions and integers
  outside signed 32-bit JSON lexemes remain explicitly unsupported.
- `max_stack_size` 1..99, `max_damage` 1..2147483647, and `damage`/`repair_cost`
  0..2147483647, with integer normalization.
- Unit-object `unbreakable` and boolean `enchantment_glint_override`.
- Removal of any of the 119 persistent registered component types with an empty
  object. The three transient types and unknown IDs are rejected by both the
  pinned patch codec and this decoder. Other component value setters are
  `Unsupported` with the `/unsupported_component_codec` suffix. Duplicate
  effective keys after namespace normalization are outside this domain.

Untouched default component values are preserved. This does not implement their
mutable game behavior or codec setters. The effect and component registries are
versioned membership data; recipe IDs never select component semantics.

`Inv.ItemKey.components` remains an opaque immutable canonical string. An
effective map equal to the item defaults becomes `""`, even if its source patch
explicitly set a default value or removed an absent component. A modified valid
map becomes exactly:

```text
BendCraftComponents1<TAB>effective_limit<TAB>canonical_effective_map_JSON
```

The map's outer keys are sorted; nested untouched values must already use the
authoritative codec's canonical representation. Implemented setters normalize
their own values. Array order and duplicate effects remain significant. This
identity reproduces the recorded `ItemStack.isSameItemSameComponents` comparisons;
it is not a general equivalence algorithm for arbitrary component codecs.

Unresolved source patches use `BendCraftPatch1<TAB>canonical_patch_JSON`.
Strictly invalid component maps use
`BendCraftInvalidComponents1<TAB>canonical_effective_map_JSON`. Neither marker can
provide output metadata. The actual `ItemStackTemplate.create` rules make a
template empty when its count exceeds the effective limit or when `max_damage`
is present with a stack limit above one. An absent `max_stack_size` has effective
limit one. Excess damage itself is accepted by the recorded strict validator.
Recursive container/bundle/projectile setters remain outside this codec domain;
their valid initialized defaults are preserved and may be removed.

`R.output_metadata(catalog,key)` returns the known item's default limit for
`components == ""`, or the resolved envelope's effective limit for a trusted
decoder-produced result. It preserves the exact key in `Inv.ItemMetadata`.
It only checks envelope shape, limit bounds and nonempty payload; it does not
authenticate a public inventory key or authorize persistence. Its trust boundary
is the output of this decoder, and callers must not accept forged envelope text
on its authority.

The component inventory owner has a narrower reusable admission seam:

```python
C.stew_profile(initialized_stew_default_map, key.components)
# Result<String, J.Value>, canonical ordered effect array on success.
C.stew_metadata(initialized_stew_default_map, key)
# Maybe<Inv.ItemMetadata>, exact suspicious_stew key and limit 1 on success.
```

These functions reconstruct the entire identity from initialized stew defaults
and the normalized effect list, then compare the exact canonical identity.
They refuse removed effects, changes to any other default, incorrect limits,
noncanonical or malformed envelopes, raw patches and non-stew item IDs. The
consumer can store its closed typed ordered effect/duration profile and encode
through `C.resolve(defaults, patch)` to retain the same crafting identity. Signed
duration strings encode the actual signed 32-bit value; list order is retained.
This seam preserves default `find` input-grid admission and does not supply
gameplay for other component types. Supply successfully validated metadata to
`find_with_metadata` when a modified stew key occupies a craft slot. Wrong or
missing metadata refuses the grid before ordinary matching; default keys retain
the existing catalog admission rules. Inventory metadata, wire admission and durable saves are
owned by the independent inventory consumer.

`reference/crafting_recipe_components.json` records initialized defaults, all 17
jar results, targeted codec/default/removal/count cases and actual Java component
comparisons. The targeted native harness exercises the real decoder, matcher,
assembly validation, effective metadata, opaque inventory equality and closed
stew admission. Its receipt is `evidence/crafting-recipe-components.json`. Fourteen
additional component laws state whole-map retention, selected/unrelated removal,
duration canonicalization, unresolved/invalid refusal, exact metadata identity
and closed-profile/input-authority refusal; these complement the matcher/plan laws, rather than
claiming universal codec or Java equivalence.

The original 2386-grid receipt records the earlier default-output domain; it is
not replayed as new component evidence. A narrow decoder check encountered
nested literal-pattern elaboration/substitution blowup before checking
`ordinary_result`; dynamic `Fail{message}` matching followed by `String.eq`
preserves semantics and removes the problematic source shape. The retained
failure receipt names this limitation and the exact terminated process.

The component extractor writes a real 2042-record catalog with initialized maps
to `build/crafting-recipe-components/production-catalog.json`. Its separate
`catalog.json` is a diagnostic fixture containing codec-edge records and must
not be installed as the game registry. The complete-catalog admission receipt
is `evidence/crafting-recipe-component-catalog.json`; that run also retained five
older diagnostics in its superset catalog, and queried the 17 actual jar outputs.
The production materializer explicitly excludes those five records.

`reference/crafting_recipe_inputs.json` independently observes actual Java
ordinary matching, assembly and remainders for 16 component-bearing input
scenarios. Eight native positive scenarios use validated ordered stew profiles;
eight cases refuse absent/wrong authority, overfull/zero counts, invalid metadata
limits, removed effects or a non-stew profile. These authority refusals precede
matching and deliberately make no claim that Java ingredient matching rejects
the corresponding component change. Evidence is
`evidence/crafting-recipe-inputs.json`. All fourteen current component laws pass
ordinary source checking. Thirteen independently pass the kernel through an
unchanged checked-root export with zero exclusions among those selected roots.
`non_stew_identity_cannot_use_closed_stew_authority` remains ordinary-only because
its referenced full stew validator reaches the existing `Nat.show.fin/go`
mutual-recursion exporter limitation. Full-import CLI `--verdict` also remains
limited by machine-stack depth on the component/JSON graph. The proof receipt
retains these distinctions.
