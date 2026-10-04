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
Player inputs are exactly raw cells 43..46 in a 2×2 grid. `A.TableGrid` retains
an independent 16-cell array with 9 logical 3×3 inputs; its remaining 7 backing
cells are retained. These constructors do not establish a world crafting-table
interaction or crafting-table UI consumer.

`A.refresh(state)` first validates exact logical lengths and the complete
balanced backing tree:48 of 64 player cells and 9 of 16 bench cells. Public
malformed constructors cannot cause padded snapshots, wrapped writes or hidden
output commits. The shape walk retains every original array node and slot.
It then runs the actual ordinary matcher against the complete active
grid, replaces the cached plan and derived `I.Menu.result`, and leaves the owned
arrays and custom menu revision unchanged. A decoder/matcher refusal retains
the entire original authority. Empty strict assembly produces a cached plan
with no derived or takeable item.

`A.take(state, button)` admits only an open menu and pickup button 0 or 1. It
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
`ResultContainer.removeItem` removes the entire output. The actual 33-case
InventoryMenu/CraftingMenu receiver confirms 4 sticks and 4 bowls for both
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
A successful commit writes the player logical 48 cells through the existing
complete 64-cell write path and, for a bench, the 9 logical cells of its separate
16-cell array. It retains all unrelated backing cells, selection, definitions,
raw saved abilities and open flag, increments the custom revision, and
invalidates the old derived result and plan. The consumer should immediately
call `A.refresh` before publishing its next MenuReply. The returned taken stack
is an observation of the amount now in carried storage, not a second owned
item or a drop request.

The component seam validates the shared
`BendCraftComponents1<TAB>effective_limit<TAB>canonical_effective_map_JSON`
identity through `D.component_defaults` and `C.metadata`. The exact definition
must be enabled, have limit 1 and the observed initialized-default SHA; the
complete effective map and ordered typed effect list are validated. Ingredient
matching receives only those exact validated keys through `R.find_with_metadata`.
`DefaultOnly` refuses every modified key, including apparently well-formed
prefixes. Live `TypedStew` enablement requires the inventory, wire and durable
save consumer join. The isolated capability tests do not establish that join.

`player_crafting_authority_load.bend` is the actual service loader. Its
`service(jar, ordered_ids, item_table, metadata, limits)` loads the real player
definition table, checks all 1658 item IDs/limits and structurally complete default maps, validates
the exact 17-field initialized stew defaults, reads original named JAR entries using
the owned Bend ZIP reader, and invokes the actual recipe decoder. Requests reject
duplicates, missing entries and byte/depth budgets. Every open archive is returned
through the close path on entry failure. Caller order establishes recipe
precedence. Nested-tag resolution and initialized default maps remain explicit
loader inputs, with their recorded source. The complete local production input
is `build/crafting-recipe-components/production-catalog.json`, containing 2042
recipes,1658 initialized item rows and 236 resolved tags. The similarly named
diagnostic catalog is not a production input. Original recipes stay in the JAR;
the service request carries metadata and identifiers rather than copied recipes.

The initialized air component map has `max_stack_size=64`, while the player
definition uses the empty-slot limit 1. The loader admits this explicit pinned
air exception; all other initialized maximum-stack values must equal their
player definitions.

The repaired actual extraction uses full VanillaRegistries RegistryOps for
initialized/effective component encoding. It produces 1658 complete default maps
with zero codec errors. The previous builtin-only extraction contained 100 ERROR
objects;111 encodings changed in total. The 17 patched recipe observations remain
identical. Initialized BuiltIn item/tag lookup remains the recipe codec context,
because construction world lookup cannot dereference loaded item tags.

The loader rejects error-shaped or incomplete defaults, missing player definition
rows, stack-limit contradictions and forged initialized stew defaults. Its
structural checks require 13 common pinned keys and registered persistent member
names. They do not implement every component value codec. Default JSON can vary
with registry lookup context, so other serialized map digests are not treated as
equal to the older player table by assumption. Explicit catalog interchange
reads one byte beyond its configured bound to refuse a valid truncated prefix.
The closed stew digest matches exactly; other component codecs gain no typed
take authority from this loader.

`player_crafting_authority_menu.bend` is the named session/actor request producer.
It owns `A.State` through ordinary opens, player closes and nonresult clicks;
slot 0 Pickup routes through `A.take`, then refreshes the complete derived result
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
observes 33 cases: both buttons, complete/partial/full carried capacity,
incompatible carried keys, offsets and mixed planks, last inputs, strict 99
output rejection, honey-bottle remainders with all inventory disposition
branches,3 bucket remainders and 3×3 bowl recipes. The client prediction fixture
manually installs the actual assembled output because it has no server recipe
synchronization. Its ResultSlot remainder fallback is the actual ClientLevel
branch. RecipeManager selection is separately covered by the recipe lane;
server recipe awards, entity drops and a whole server menu lifecycle are not
established here. Every loaded official class is hashed against the pinned jar.
Original recipe JSON, jars, raw source/output and assets remain ignored.
Committed references contain source identities and observations.

The first fixture attempt exposed missing initialized item tags and an external
tutorial notification method. It is retained in ignored raw evidence. The
corrected fixture installs the actual resolved 236 item-tag observations and
adds only the external tutorial notification method; it changes no official
menu, recipe, inventory or item receiver.

The strengthened frozen native corpus passes 67 complete-owner comparisons on
one and four CPU threads with identical output. It includes the 33 actual Java
menu observations,13 additional stale/forged/component/admission refusals,
four representable malformed-owner refusals and 17 typed stew takes compared
against Java's actual assembled component maps. All 64 player backing cells
and all 16 bench backing cells are compared, along with logical lengths, full
cache consumption entries, selected slot, raw ability bits, menu revisions,
and exact ordered item definitions, recipe catalog and component capability.
Of the 33 Java observations,29 match exact owned item states and four Java
world-drop/discard branches are replaced by atomic missing-disposition refusals.
The two unrepresentable Array constructors are checked separately.

The same binary loads all 2042 original JAR recipe entries against 1658 complete
initialized default maps and 236 resolved tags:1202 ordinary declarations,
including 17 patched stew outputs, and 840 unsupported recipe declarations. Six
actual menu producer transitions also match. Explicit service and pinned
startup runs on one/four CPU threads produce identical output SHA-256
`de5d2a05dfe4747f128292d6e7e9dbdca8c9c2dd1afb1bb102398898a55792c2`.
All 12 loader/default/artifact admission refusals pass, including the original
100 erroneous default maps, forged stew defaults, changed pinned facts and a
valid artifact prefix with bytes beyond its configured bound.

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

The concrete production source join is the nonfixture `remote_resource_server`
startup and the authenticated Backend menu consumer. Startup obtains validated
player definitions and recipe catalog from the original JAR service; it installs
those definitions in the durable codec and supplies the catalog to
`CS.new_with_components`. The Backend retains optional `CS.Context` alongside the
original Session Shell and routes authenticated MenuInspect/Open/Close/Click to
the adapter. The explicit fixture path retains the legacy absent-context route.
The authority native receipt tests the owned producer and loader; the Backend,
entry, transport and visible client require their separate integration receipts.
World crafting-table access, nine-input click topology, recipe awards and owned
drop disposition remain explicit integration work.

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
`generated/reference_crafting_authority_metadata.json`, which contains 1658
observed item/default/remainder rows,236 resolved tags and 2042 ordered recipe
IDs. It contains no recipe source. Startup then runs the actual JAR service and
returns its validated player definitions and recipe catalog. Modified or
truncated registry facts cannot silently become initialized defaults.

The combined 69-fixture literal build exceeded its 600-second bound and was
cleaned up without a native verdict. Its failed snapshot and receipt are
preserved. The repaired test corpus is parsed by Bend from runtime JSON, using
the actual recipe decoder; this avoids compiling a large corpus of literals.
The source model has 69 fixtures. Two unequal-child Array trees cannot be
represented by the ordinary CPU runtime: its `blk_node` constructor requires
equal child physical classes and posts `ERR_TAGS` otherwise. Their observed
exit is 1 with `bend: runtime fail-stop`. They are separate native constructor
boundaries, not authority refusal observations. The earlier attribution to the
refusal observer was incorrect and is corrected in failure 002. The safe physical
tree observer remains useful for representable wrong logical lengths and short
backing arrays; its actual structural kernel law passes.

The subsequent strengthened combined direct build reached 600 seconds while
several other checker jobs were active. Its exact frozen source and cleaned-up
process receipt are preserved in failure 003; no new native cases ran. The test
builder now uses the existing verified modular native cache to prepare exact
Bend C emission, then invokes the installed CLI's ordinary CPU compiler flags
directly. It retains emission separately from linking and validates the complete
source/compiler/header/library closure before publishing the binary.
`--frozen-source` resumes a preserved graph only when every compiled input still
has the recorded identity. The strengthened frozen graph built successfully:
449.878 seconds for emission, 153.062 for native compilation and 2.950 for closure
verification. The total 605.890 seconds comprises separately bounded stages.
The same binary passes 67 representable authority fixtures with complete
physical backing and ordered catalog/component-capability assertions. The two
constructor checks reproduce exit 1 with the exact fail-stop diagnostic and no
authority observation. Evidence is in `player-crafting-authority-native.json`
and `player-crafting-authority-load.json`; earlier failures remain preserved.

The separate authenticated Backend consumer receipt is documented in
`PLAYER_CRAFTING_BACKEND.md`: 15 native cases compare all raw Core fields and all 64
physical inventory cells, including two takes, stale plans, lease/observer
refusals, the absent-context route, close, and an accepted committed take with a
failed cache refresh. That receipt uses its explicitly frozen Core/Runtime
generation and does not establish TCP or full startup execution.
