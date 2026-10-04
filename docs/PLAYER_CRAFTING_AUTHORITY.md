# Ordinary player crafting authority

`player_crafting_authority.bend` is the outer owner of the existing
`player_inventory.bend` state, the ordinary `crafting_recipe.bend` catalog,
a player-grid or separate owned crafting-table array, and the cached recipe
plan. The inventory foundation remains independent of recipe matching. No
inventory, screen, session, persistence or wire module is changed by this lane.

`A.new(player, catalog)` adopts the existing player owner in `DefaultOnly` mode.
`A.new_with_components` takes an explicit component capability; `TypedStew`
admits only the closed initialized suspicious-stew profile. `A.inspect` observes
all player menu fields beside the complete active `R.Grid` and cached plan.
Player inputs are exactly raw cells43..46 in a2x2 grid. `A.TableGrid` retains
an independent16-cell array with9 logical3x3 inputs; its remaining7 backing
cells are retained. These constructors do not establish a world crafting-table
interaction or crafting-table UI consumer.

`A.refresh(state)` first validates exact logical lengths and the complete
balanced backing tree:48 of64 player cells and9 of16 bench cells. Public
malformed constructors cannot cause padded snapshots, wrapped writes or hidden
output commits. The shape walk retains every original array node and slot.
It then runs the actual ordinary matcher against the complete active
grid, replaces the cached plan and derived `I.Menu.result`, and leaves the owned
arrays and custom menu revision unchanged. A decoder/matcher refusal retains
the entire original authority. Empty strict assembly produces a cached plan
with no derived or takeable item.

`A.take(state, button)` admits only an open menu and pickup button0 or1. It
requires a cached plan, compares its complete before-grid geometry, item keys,
component identities and counts using `R.current`, then independently repeats
`R.find` and checks the entire selected plan. A stale grid, changed recipe
catalog/selection, missing plan, malformed grid, empty output, incompatible or
insufficient carried capacity, unsupported component metadata, or undisposed
remainder refuses before owned mutation. Failed takes retain the complete
player array, table array, all backing cells, selection, catalog, raw abilities,
menu revision/open flag, derived output and cached plan.

Both left and right pickup take the complete assembled output. The menu's
right-click half-count request alone would give the wrong answer:
`ResultContainer.removeItem` removes the entire output. The actual33-case
InventoryMenu/CraftingMenu receiver confirms4 sticks and4 bowls for both
buttons. A matching existing carried stack must have space for the complete
output; different keys or partial room leave the Java receiver unchanged.
The adapter reports an explicit refusal for that unchanged receiver domain.

The pure transaction planner removes exactly the plan's one unit from each
occupied original input cell. A crafting remainder occupies its emptied
input cell, merges with a remaining equal item key, or follows the current
selected/offhand/ascending-main merge then empty-main insertion order. The
entire proposed state and all item limits are checked before either array
changes. The current actor lacks an owned world-drop/creative-overflow
consumer: an unreturnable remainder therefore refuses the whole craft. The
reference explicitly observes the Java disappearance branch; it is not
presented as implemented item-entity ownership.

The transaction compares complete per-key transformation ledgers:

`before-owned + produced-output-and-remainders = after-owned + consumed-inputs`.

Queries include every key appearing in the complete before/after player and
active grid or in any consumed/produced stack. Ordinary crafting changes item
identities, so unchanged per-item counts would be the wrong conservation law.
A successful commit writes the player logical48 cells through the existing
complete64-cell write path and, for a bench, the9 logical cells of its separate
16-cell array. It retains all unrelated backing cells, selection, definitions,
raw saved abilities and open flag, increments the custom revision, and
invalidates the old derived result and plan. The consumer should immediately
call `A.refresh` before publishing its next MenuReply. The returned taken stack
is an observation of the amount now in carried storage, not a second owned
item or a drop request.

The component seam validates the shared
`BendCraftComponents1<TAB>effective_limit<TAB>canonical_effective_map_JSON`
identity through `D.component_defaults` and `C.metadata`. The exact definition
must be enabled, have limit1 and the observed initialized-default SHA; the
complete effective map and ordered typed effect list are validated. Ingredient
matching receives only those exact validated keys through `R.find_with_metadata`.
`DefaultOnly` refuses every modified key, including apparently well-formed
prefixes. Live `TypedStew` enablement requires the inventory, wire and durable
save consumer join. The isolated capability tests do not establish that join.

`player_crafting_authority_load.bend` is the actual service loader. Its
`service(jar, ordered_ids, item_table, metadata, limits)` loads the real player
definition table, checks all1658 item IDs/limits and structurally complete default maps, validates
the exact17-field initialized stew defaults, reads original named JAR entries using
the owned Bend ZIP reader, and invokes the actual recipe decoder. Requests reject
duplicates, missing entries and byte/depth budgets. Every open archive is returned
through the close path on entry failure. Caller order establishes recipe
precedence. Nested-tag resolution and initialized default maps remain explicit
loader inputs, with their recorded source. The complete local production input
is `build/crafting-recipe-components/production-catalog.json`, containing2042
recipes,1658 initialized item rows and236 resolved tags. The similarly named
diagnostic catalog is not a production input. Original recipes stay in the JAR;
the service request carries metadata and identifiers rather than copied recipes.

The repaired actual extraction uses full VanillaRegistries RegistryOps for
initialized/effective component encoding. It produces1658 complete default maps
with zero codec errors. The previous builtin-only extraction contained100 ERROR
objects;111 encodings changed in total. The17 patched recipe observations remain
identical. Initialized BuiltIn item/tag lookup remains the recipe codec context,
because construction world lookup cannot dereference loaded item tags.

The loader rejects error-shaped or incomplete defaults, missing player definition
rows, stack-limit contradictions and forged initialized stew defaults. Its
structural checks require13 common pinned keys and registered persistent member
names. They do not implement every component value codec. Default JSON can vary
with registry lookup context, so other serialized map digests are not treated as
equal to the older player table by assumption. Explicit catalog interchange
reads one byte beyond its configured bound to refuse a valid truncated prefix.
The closed stew digest matches exactly; other component codecs gain no typed
take authority from this loader.

`player_crafting_authority_menu.bend` is the named session/actor request producer.
It owns `A.State` through ordinary opens, player closes and nonresult clicks;
slot0 Pickup routes through `A.take`, then refreshes the complete derived result
and plan. Its reply contains a correlated `I.MenuSnapshot`, the observed taken
stack and whether cache refresh succeeded. A derived-cache failure after an
admitted mutation is observable and does not retrospectively label the committed
mutation an atomic refusal. Full validated service catalogs supply the tested
ordinary path. Other result click kinds and bench close without owned input
return/drop disposition refuse with the complete frame retained.

## Reference and verification

`tools/reference_player_crafting_authority_probe.py` uses the normal pinned
LocalPlayer fixture and untouched official InventoryMenu, CraftingMenu,
ResultSlot, ResultContainer, ItemStack and ordinary recipe receivers. It
observes33 cases: both buttons, complete/partial/full carried capacity,
incompatible carried keys, offsets and mixed planks, last inputs, strict99
output rejection, honey-bottle remainders with all inventory disposition
branches,3 bucket remainders and3x3 bowl recipes. The client prediction fixture
manually installs the actual assembled output because it has no server recipe
synchronization. Its ResultSlot remainder fallback is the actual ClientLevel
branch. RecipeManager selection is separately covered by the recipe lane;
server recipe awards, entity drops and a whole server menu lifecycle are not
established here. Every loaded official class is hashed against the pinned jar.
Original recipe JSON, jars, raw source/output and assets remain ignored.
Committed references contain source identities and observations.

The first fixture attempt exposed missing initialized item tags and an external
tutorial notification method. It is retained in ignored raw evidence. The
corrected fixture installs the actual resolved236 item-tag observations and
adds only the external tutorial notification method; it changes no official
menu, recipe, inventory or item receiver.

The earlier native authority corpus passed63 complete-array/profile comparisons on one
and four CPU threads with identical output. It includes the33 actual Java menu
observations,12 stale/forged/admission refusals,17 isolated typed stew takes
compared against Java's actual assembled component maps, and a DefaultOnly
refusal. All64 player backing cells and all16 bench backing cells are compared,
along with full cache consumption entries, selected slot, raw ability bits and
menu revisions. The four missing-disposition branches refuse atomically.

Nineteen actual production laws in `player_crafting_authority_laws.bend` and its
paired proof are ordinarily checked and exported with zero exclusions. They
include exact complete-array retention of the geometry checker and malformed
snapshot observer by induction,
malformed-owner guard refusal retention, complete authority refusal retention, exact transformation-ledger equality
for both actual planners, retention of every noninventory player field on commit,
closed component refusal and retention of the seven bench backing cells. Source
API selection retains all checked types/bodies and full original declaration
tables. The earlier eleven-law independent kernel receipt predates typed metadata.
The complete nineteen-law independent kernel run rejects the shared JSON encoder
`json.encode_go` with `affine live code, calls that descend`. The two actual
structural geometry/observer laws independently pass the kernel on the same
frozen source graph. No complete nineteen-law kernel PASS is claimed here.
These contracts are not a universal Java equivalence theorem.

Reproduce from the Minecraft directory:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_crafting_authority_probe.py --mode reproduce
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_crafting_authority.py --prepare
/Users/chuah/.bend/bin/bend src/player_crafting_authority_proof.bend --check-only
mkdir -p build/player-crafting-authority-proof/fresh
/opt/homebrew/bin/node --experimental-transform-types --stack-size=4096 tools/player_crafting_authority_proof.mjs build/player-crafting-authority-proof/fresh
LEAN_STACK_SIZE_KB=4194304 /Users/chuah/.bend/bendtt/e15042434e73aab0/bendtt build/player-crafting-authority-proof/fresh/selected.bendtt
PYTHONDONTWRITEBYTECODE=1 /Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 tools/test_player_crafting_authority.py --build --native
PYTHONDONTWRITEBYTECODE=1 /Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 tools/test_player_crafting_authority_load.py --build --native
```

The named integration is the session owner currently retaining `I.State`.
Adopt `A.State` at that boundary, preserve it through ordinary noncrafting
inventory operations, invalidate/recompute `A.cache` after any input change,
route menu requests through `player_crafting_authority_menu` and publish its
correlated full MenuReply. Ordinary nonresult player clicks use the existing I
controller inside that producer. Load the service from the actual local JAR and
recorded metadata through `player_crafting_authority_load.service`; use its
definitions for the player profile and its recipes for the authority catalog.
Session/backend/entry adoption is owned by the main integration task. World
crafting-table access,9-input click topology, recipe awards and owned drop
disposition remain explicit integration work.

`player_crafting_session_adapter.bend` supplies the concrete player Session join.
Its immutable `Context{catalog,cache,components}` and `CraftOpen`, `CraftClose`,
`CraftInspect`, `CraftClick` requests reconstruct an ephemeral player-grid authority through the
existing `S.inventory_query`. Only the original Session inventory Array is
returned; Shell and durable bundle layouts stay unchanged. The adapter returns
`S.State & Context & Menu.Reply`. It does not own the bench topology or world
disposition. Menu replies include the active complete grid beside the player
snapshot; unsupported bench input clicks refuse the complete frame.

The Session module imports existing foreign durability/lock primitives. This
adapter adds no foreign declaration and those save/import dependencies remain
outside the pure authority proof scope. Root owns its actual backend/startup and
wire integration.

`player_crafting_authority_startup.service(jar,item_table,facts_path,limits)` is
the named nonfixture startup loader. It verifies the exact SHA-256 of
`generated/reference_crafting_authority_metadata.json`, which contains1658
observed item/default/remainder rows,236 resolved tags and2042 ordered recipe
IDs. It contains no recipe source. Startup then runs the actual JAR service and
returns its validated player definitions and recipe catalog. Modified or
truncated registry facts cannot silently become initialized defaults.

The combined69-fixture literal build exceeded its600-second bound and was
cleaned up without a native verdict. Its failed snapshot and receipt are
preserved. The repaired test corpus is parsed by Bend from runtime JSON, using
the actual recipe decoder; this avoids compiling a large corpus of literals.
The runtime corpus compiled successfully, then its native replay exposed a
fail-stop while observing an unbalanced refused owner. The production observer
now walks the physical Array tree and retains it exactly; its source check and
structural kernel law pass. The fresh combined replay also checks bench logical
length and exact ordered catalog/component-mode retention. Its native verdict
is pending.
