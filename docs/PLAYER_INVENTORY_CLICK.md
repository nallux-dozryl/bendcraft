# Number-key and offhand inventory swaps

The authoritative `I.menu_click` now routes the existing typed `I.Swap` request
to `player_inventory_click_swap.bend`. The actual session and authenticated
private MenuClick11 path already call that controller and return the full
correlated MenuReply. No protocol or persistence schema changes are needed.
Buttons 0–8 select inventory hotbar cells; button 40 selects the offhand. Other
buttons are successful unchanged vanilla no-ops. The menu must be open.

The pinned Java26.3 receiver is `InventoryMenu.clicked` with
`ContainerInput.SWAP` on a normal LocalPlayer fixture. It observes all 36 main
cells, seven equipment cells, four crafting inputs, carried ownership, derived
result, selection and abilities. Fresh SURVIVAL, CREATIVE and ADVENTURE profiles
use the actual GameType ability update. This is receiver evidence, not a whole
ServerPlayer lifecycle or native keyboard-input claim.

Ordinary two-stack swaps exchange counts even when the item keys match. An
empty destination receives a whole stack up to its actual capacity. Armor
slots admit only the item's verified default equipment slot and one item;
an armor stack such as 64 carved pumpkins therefore leaves 63 in the source.
When an occupied armor slot clips the incoming stack, its displaced old item
returns through the observed selected/offhand/ascending-main merge and empty
main insertion ordering. The existing certified count-movement kernel and
stable close-return insertion foundation implement those moves. Carried
ownership is untouched; ordinary inventory movement does not require maybuild.

Planning reads all 48 logical cells as immutable observations while the actor
retains the sole64-cell Array. The temporary 49th planning observation holds a
displaced stack only while its return is evaluated; it is never an owned cursor
or backing cell. Admission validates every original and proposed logical cell
against the verified 1658-item catalog and checks complete per-item Nat count
ledgers. Queries cover every key occurring before or after. Commit uses the
same proven 48-cell production write path, retaining the other 16 backing cells,
selection, catalog and all raw saved ability words. A changed swap increments
the custom menu revision and invalidates the derived recipe cache. An unchanged
swap retains the entire owner, including that cache and revision.

The actual receiver has one unfinished ownership boundary. If a displaced item
cannot return to a full inventory, survival invokes Player.drop with predicted
disposition; creative
Inventory.add consumes its remainder under hasInfiniteMaterials. The 49-case
observations include both branches: one displaced diamond helmet disappears
from the player inventory. This actor has neither an owned item-entity drop
consumer nor an explicit creative overflow-discard consumer. It therefore
refuses those operations atomically and retains every original item and field.
The receiver observation does not establish a server-owned dropped entity.
These refusals deliberately do not claim Java parity for the missing consumer.
They must join real ownership disposition rather than delete a stack silently.

Crafting result slot 0 remains the recipe output/take dependency. The reserved
recipe consumer supplies authoritative matching and consumption; this change
does not fabricate output or consume ingredients. Outside-menu slots retain
their explicit drop dependency. Quick-move, drag, clone, throw and pickup-all
remain separate missing typed consumers. Native number-key/offhand bindings in
the screen/input presenter are also a separate integration dependency; the
authenticated backend accepts the existing typed Swap command now.

`tools/reference_player_inventory_click_probe.py` uses the existing pinned
launcher, class-hash verifier and bounded raw-first observer. Its49 actual
observations comprise45 count-preserving swaps, two world-drop/creative-discard
branches and two empty result-slot cases. `tests/player_inventory_click.bend`
calls production menu_click and consumes all 64 cells for observation.
`tools/test_player_inventory_click.py:suite` compares57 independent cases:
45 exact Java outcomes, two atomic disposition refusals, two explicit recipe
refusals, three raw ability/permission-retention cases, three derived-cache
cases and two menu/slot authority cases. The helper accepts an executor callback
and performs no build or process launch.

Seven production laws cover admitted complete item-count ledgers, complete
owner refusal, admitted unchanged-owner retention, closed-menu authority,
and complete noninventory owner retention on commit. The conservation theorem
is conditional on the actual full-ledger admission guard; it is not an
unconditional proof of every Java operation or an item-drop theorem. The proof
reuses the independently certified complete-ledger logic and actual 64-cell
write theorem from the stable close foundation. Independent kernel and native
results are recorded separately with exact source generations in the click
evidence files.

The current seven-law source target passes ordinary checking in 3.746 seconds;
the actual executable harness passes in 4.731 seconds. Read-only selective export
checks and pins the complete 13-file source closure, retains all original types,
declarations and proof bodies, and emits all seven new laws plus the reused
complete 64-cell commit theorem with zero holes and zero exclusions. The pinned
independent kernel passes the 18,837,910-byte output in 4.491 seconds. Exact theorem
and implementation hashes are in `evidence/player-inventory-click-proof.json`.

The actual focused CPU native run passes all 57 cases in 2.941 seconds. Its cold
build takes 47.444 seconds with zero retries. The fresh 49-case Java reproduction
matches the complete observation seal and verifies all 4360 loaded official
class hashes against the installed 26.3 jar. Build, native and Java groups are
reaped and absent after cleanup. These receipts establish this inventory
consumer generation; they do not replace future actor/network/save or native
number-key input checks. `evidence/player-inventory-click-native.json` pins
the binary, current sources, independent expectations and raw process receipts.

Reproducible entry points:

```sh
bend src/player_inventory_click_proof.bend --check-only
bend tests/player_inventory_click.bend --check-only
python3 tools/reference_player_inventory_click_probe.py --mode reproduce
```

The native suite uses the existing `build_native.ensure_native` CPU builder and
FRR2 bounded process supervisor with no-retry binding. Its captured exact build
and execution scripts are in `build/player-inventory-click-native-001`.
The read-only compiler-API selection and independent kernel invocation are in
`build/player-inventory-screen/click-selective-export-001`; compiler sources
were unchanged. No binary, generated C or private installation asset belongs
in the commit.
