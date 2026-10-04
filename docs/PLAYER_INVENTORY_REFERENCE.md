# Pinned 26.3 player inventory reference

Status: **one successful actual extraction and exact fresh-process reproduction**. Confidence is **high for the recorded pinned receivers and exact
method outcomes**, and **unknown for unexecuted gameplay/lifecycle paths**.

The extraction ran one bounded JVM, PID 35513, exiting 0 in approximately 3.41
seconds. All 125 cases were recorded, and every one of the 4,405 loaded official
classes was individually matched against the pinned installed 26.3 client JAR.
All 120 valid cases succeeded without save/load/resave codec diagnostics; five
intentional invalid-selection cases produced their exact expected exceptions.
Actual observations are in `reference/player_inventory.json`; the extraction
receipt is `evidence/player-inventory-reference-extract.json`. Their canonical
observation SHA-256 is
`16274bea0e084efcc2a53fb32876e4a18b82a7e816ce02f04dacdecae6d6489e`.

`tools/reference_player_inventory_probe.py --prepare` verifies the installed
26.3 client, metadata, runtime executable and official library files without
launching Java. It reads classfile declarations and selected complete method
bytecode directly with Python; no `javap` subprocess is used. Preparation is
recorded in `evidence/player-inventory-reference-preparation.json`.

The observed corpus contains 125 independent receiver cases: one default,
nine selected-slot indices, 27 ordinary-slot removals, 81 two-slot insertions,
two empty-source cases, four direct game-type ability updates and one populated
in-memory save/load. Source stacks include count 17 and the complete 64-item
stack. Items are unmodified `minecraft:stone`, `minecraft:dirt` and
`minecraft:oak_planks`; equipment, other items and component patches are outside
this corpus.

The default receiver reports selected slot **0**, selection size **9**, ordinary
main length **36**, total `getContainerSize()` **43**, 36 empty main slots and
`timesChanged=0`. The larger returned container size does not establish equipment
behavior. Valid `setSelectedSlot` inputs 0, 1, 6 and 8 took effect; selected-item
reads returned their actual corresponding stacks. Inputs −2,147,483,648, −1, 9,
35 and 2,147,483,647 reported `isHotbarSlot=false` and threw
`IllegalArgumentException("Invalid selected slot")`. Every invalid case preserved
the complete recorded inventory state, including prior selection 6. Selection
did not increment `timesChanged`.

Ordinary `Inventory.removeItem(1, requested)` was observed for all three supported
items. Removing 7 from source 17 leaves source 10 and returns 7. Requests 17, 64
or 65 from source 17 return 17 and empty the visible source. Requests 63, 64 or
65 from source 64 return 63, 64 or 64 respectively. Amount zero and empty-source
removal return canonical EMPTY without mutation. All recorded removals leave
`timesChanged=0`. Exhaustion retains a noncanonical source object with its original
stored item and raw count zero; its public item/count are air/0. Negative amounts
and equipment removal remain unexecuted.

The insertion call uses actual `new Slot(inventory,34,0,0)` and the source object
still stored in main slot 1. Representative stone outcomes are below; dirt and
oak-plank cases record the corresponding results independently.

| Source before | Destination before | Requested | Source after | Destination after | `timesChanged` delta |
| --- | --- | --- | --- | --- | --- |
| 17 | Empty | 7 | 10 | 7 | 1 |
| 17 | Same item, 1 | 64 | 0 | 18 | 1 |
| 17 | Same item, 63 | 64 | 16 | 64 | 1 |
| 17 | Same item, 64 | 64 | 17 | 64 | 0 |
| 17 | Different item, 5 | 64 | 17 | Different item, 5 | 0 |
| 64 | Empty | 64 | 0 | 64 | 1 |
| 64 | Same item, 63 | 64 | 63 | 64 | 1 |

Amount zero and empty-source insertion preserve both touched slots and the
counter. Every insertion returns the identical source object, including after
exhaustion leaves its original stored item and raw count zero. The public main
slot projection uses null for visible empties; separate raw source/destination
records preserve the distinction. All observed nonempty stack limits are 64.
Only slots 1 and 34 change in insertion cases.

The fresh actual Abilities object and default player's abilities agree. Direct
`GameType.updatePlayerAbilities` on fresh receivers produced:

| Constructor/update | invulnerable | flying | mayfly | instabuild | mayBuild |
| --- | --- | --- | --- | --- | --- |
| Default; SURVIVAL | false | false | false | false | true |
| CREATIVE | true | false | true | true | true |
| ADVENTURE | false | false | false | false | false |
| SPECTATOR | true | true | true | false | false |

Flying speed is binary32 `3d4ccccd` (0.05f); walking speed is `3dcccccd` (0.1f),
unchanged across these fresh-receiver updates. Actual saved abilities use Byte
tags for the flags, case-sensitive key `mayBuild`, and Float `flySpeed`/`walkSpeed`
with those exact words. Existing-flight transitions remain unverified.

The populated save/load row seeds main slots 0=stone64, 8=dirt17,
9=oak_planks63 and 35=stone1, selects 8 and applies the actual CREATIVE ability
update. Actual `saveWithoutId` emits four Inventory Compound entries in ordinary
slot order, each with Byte `Slot`, String `id` and Int `count`, without a component
patch for these unmodified items. `SelectedItemSlot` is Int 8. Actual contextual
`load` into a fresh player restores those four entries, selected dirt17 and
abilities. Source and restored focused projections have identical typed trees
and identical 326-byte uncompressed unnamed-root NBT; the default projection is
150 bytes with an empty Inventory list. Both projections survive actual NbtIo
write/read with unchanged typed tags and no diagnostics. This does not assert
equality of the complete entity save or the project's custom codec.

The launcher constructs the actual official `LocalPlayer`, `Inventory`, `Slot`
and `Abilities` receivers. It reuses the frozen normal LocalInput fixture's
declared external service substitutions and synthetic ClientLevel world-query
context. Official loaded class bytes must match the pinned client JAR. There is
no unsafe allocation, game window, native presentation, account access or
installed options/world/save access.

The two-slot operation is the exact official `Slot.safeInsert(sourceStack,
requested)` call. The separate removal operation is
`Inventory.removeItem(mainSlot, requested)`. Neither operation establishes the
project's custom TransferSplit/TransferMerge admission policies, menu click
protocol, creative item acquisition or arbitrary gameplay transfer parity.
Ability cases invoke the actual `GameType.updatePlayerAbilities` method; they
do not establish a server/client game-mode transition. The save/load case uses
actual `saveWithoutId`/`load` and official contextual tag codecs in memory, with
a focused Inventory/SelectedItemSlot/abilities projection written and reread
through official NbtIo. It is not a player-save filesystem or recovery test.

Each command below requires one allocated Java job slot and launches exactly
one source-execution JVM, with a 512 MiB heap and a 120-second process-group
limit. Extraction and a separately allocated fresh-process reproduction have
both completed; future reruns must be separately allocated:

```sh
python3 tools/reference_player_inventory_probe.py --mode extract
python3 tools/reference_player_inventory_probe.py --mode reproduce
```

Unexpected receiver errors or clean-fixture codec diagnostics prevent
publication. Only the five statically identified invalid selected-slot cases
are admitted as expected failures, and each must preserve the complete observed
inventory state. Fresh-process reproduction must match all observed values,
exception details, source/class identities and fixture hashes exactly.

Unique raw receipts retain fixture sources, launcher, exact command, stdout and
stderr before parsing, so failed reruns cannot overwrite prior pinned artifacts.
Interruption/communication failure kills and reaps the JVM, with a bounded
10-second cleanup. Fresh-process reproduction is recorded in
`evidence/player-inventory-reference-reproduce.json`: PID41907, exit0 in
5.499957 seconds, all125 cases and4405 official class identities exact. Custom
split/merge admission, same-slot transfer, menu clicks, quickMoveStack, equipment,
modified components, other items, creative acquisition and filesystem persistence
remain unverified.

## Menu-close return receiver

The additive `--profile menu-close` corpus has 26 actual cases: 18 direct
`Inventory.placeItemBackInInventory(stack,false,Prediction.SERVER_ONLY)` calls,
four normal LocalPlayer `InventoryMenu.removed` calls and four ordered return
receiver sequences. Fresh extraction exited 0 in 6.222263 seconds; fresh-process
reproduction exited 0 in 4.005021 seconds. All 4,355 loaded official classes matched
the pinned 26.3 client JAR. Observation seal:
`6c5c54ac766fa6d765e28a70f01cfe755baf19fbb1eb6ce112d6560ae4915035`.
The separate artifact is `reference/player_inventory_close.json`; the extraction
and reproduction receipts are `evidence/player-inventory-close-reference-extract.json`
and `evidence/player-inventory-close-reference-reproduce.json`.

The executed return receiver merges into the selected slot first, then offhand,
then ascending main slots 0–35. Only after compatible stacks have no room does
it choose the first empty main slot. Empty equipment/offhand cells are not
available main slots. Both survival and creative use this order and retain a
source remainder when this normal LocalPlayer context cannot transfer it into
inventory. Limits 16 and 1 were observed using ender pearls and shields. A full
inventory retains source 17 in both modes; one available stone cell in a
stone 63 stack receives 1 and leaves source 16. Creative does not destroy that
remainder in this actual receiver.

JDK `javap` runs through its ToolProvider inside the same bounded JVM, against
the same pinned classpath. Its exact bytecode establishes server close ordering:
`AbstractContainerMenu.removed` returns carried ownership for a ServerPlayer;
`InventoryMenu.removed` then clears the derived result and, on the server branch,
returns crafting cells 0–3. The executed four ordered sequences call the actual
return receiver in this order. This is executed insertion evidence plus static
server composition evidence; no ServerPlayer world/lifecycle/drop receiver is
fabricated. The four actual LocalPlayer `removed` cases exercise the client
branch and correctly retain temporary items, so they are excluded from Bend
server-close comparisons.

The producer uses one 512 MiB JVM with a 60-second cap and 10-second cleanup:

```sh
python3 tools/reference_player_inventory_probe.py --profile menu-close --mode extract
python3 tools/reference_player_inventory_probe.py --profile menu-close --mode reproduce
```

No actual Bend item-entity/drop consumer exists. Its production close therefore
matches the 16 returnable receiver cases and atomically refuses the six
capacity-exhausted cases, retaining the entire original owner. Those refusals
are an explicit current ownership limitation, not a vanilla world-drop parity
claim. `tools/test_player_inventory.py:close_suite` also prepares three saved
raw-word/permission-retention cases and four derived-output disposition cases;
these additional cases are not relabeled Java observations.
