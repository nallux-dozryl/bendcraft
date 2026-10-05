# Initialized item component admission

The focused native consumer passes 30 admission/slot-codec cases and 12 raw
physical cases in 3.23 seconds on the recorded source generation. Exact results,
source/binary pins and retained failures are in
`evidence/player-item-components-native-003.json`. Actor transport, pickup and
whole-save recovery remain separate integration obligations.

The player definition catalog has two explicit states. `Catalog` retains the
historical table-only constructor. `InitializedCatalog` additionally carries
the actual complete initialized component maps. The production startup consumer
calls `with_initialized_defaults` only after digest-checking the pinned facts
and checking their rows against the item table; the wrapper performs no second
full startup validation. An untrusted map or a parsed envelope cannot become
that runtime authority on its own.

For an initialized catalog, `metadata` authenticates a modified key by selecting
its registered, enabled, non-air definition and its actual default map. The
existing `cooking_block_entity_codec_components.patch` reconstructs the delta
and requires `crafting_recipe_components.resolve` to reproduce the exact key.
The admitted effective limit follows that authenticated component map. Removing
`max_damage` can therefore make the observed modified sword stackable, while
retaining `max_damage` with a limit above one refuses the invalid combination.
The table-only catalog retains the historical closed suspicious-stew path.

`player_item_components.structural_slot_metadata` is a separate transport
check. It checks canonical effective-map encoding, unique persistent component
names, supported scalar/effect shapes, effective stack limit and the damageable
stack combination. It does not grant registered-item or initialized-default
authority. Inventory's structural gate uses this check; actual mutation and
save admission still use the initialized catalog. A canonical changed but
unsupported component can pass structural transport checks and then refuse at
the actual metadata boundary without modifying the inventory.

The generic slot-codec adapter reconstructs and writes the actual typed patch
through the existing physical component codec. Loading recreates the key from
the same initialized defaults, refuses discarded patch fields and invalid
counts, then runs the exact catalog admission again. The inventory-specific
physical precheck also refuses duplicate or alias-duplicate patch fields,
unknown effects, malformed effect durations and extra/duplicate effect fields.
The cooking decoder's deliberate salvage behavior cannot silently remove such
entries from an inventory load. Old table-only stew codec
behavior remains available. No new component value codec or guessed default
profile is introduced: supported setters remain effects, max stack size, max
damage, damage, repair cost, unbreakable and glint; registered persistent
removals use the existing registry. Other changed value codecs remain an
explicit refusal.

The shared cooking component codec now evaluates each additions/removals tail
once before selecting its branch. The former eager `choose` expression computed
each recursive tail twice. Patch order, values and the existing
`authenticated`/`resolve` checks are retained. The first 42-case batch hit its
30-second runtime cap; a one-stew diagnostic took about 25 seconds, while an
empty fixture took 0.94 seconds. The changed 42-case batch passed in 3.23 seconds.
The exact prior recurrences and structural equivalence obligations are retained
in `player_item_component_patch_laws.bend`; their verification status is
separate from the native observations.

`tools/test_player_item_components.py` is an executor-only native fixture helper.
It compares eleven pinned Java outputs plus targeted invalid/capacity cases,
exact physical slot NBT, and all 64 inventory backing cells with raw abilities,
status and menu fields. Twelve additional raw physical cases exercise loss
refusal and accepted numeric/no-op patches. Its five maps are copied from the observed initialized
maps; the real table contains all 1,658 definitions. This focused test does not
establish full component gameplay, current actor transport or whole-save
recovery. The four connected laws in `player_item_components_laws.bend` cover
missing defaults, disabled definitions and preservation of the definition
owner through initialization and complete inventory preservation when metadata
is missing; mathematical verdict status is recorded in the
evidence separately from source checks and native observations.
