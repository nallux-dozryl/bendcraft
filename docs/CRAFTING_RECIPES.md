# Ordinary crafting recipes

`src/crafting_recipe.bend` implements ordinary shaped and shapeless crafting in
Bend. `src/crafting_recipe_decoder.bend` decodes the actual installed Java 26.3
JSON ingredient/pattern/result schema and the explicit catalog interchange.
Python extracts reference inputs and compares native outputs; Java executes the
untouched pinned recipe receivers. Neither host language supplies game matching.

The jar contains 2042 recipe records: 827 shaped and 375 shapeless. Of these 1202
ordinary recipes, 1185 produce unmodified item defaults. Seventeen ordinary
recipes have component patches in their result; they remain explicit
`Unsupported{id,kind + "/patched_result"}` records until the inventory component
owner supports them. Every other subclass is preserved as `Unsupported{id,kind}`.
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
admits only the inventory owner's default-component domain. Catalog entries
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

Eleven laws in `src/crafting_recipe_laws.bend`, proved in the paired production
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
/Users/chuah/.bend/bin/bend src/crafting_recipe_proof.bend --verdict
```

The extractor creates the complete local catalog at
`build/crafting-recipe-reference/catalog.json`; all original source recipes stay
in that ignored directory. Committed references contain observations and source
identities. Native evidence is `evidence/crafting-recipe-native.json`.
Crafting is a bounded sequential CPU operation; this module introduces no GPU
workload. Native tests exercise one and four CPU threads to detect scheduling
differences, and retain source/binary/reference identities.
