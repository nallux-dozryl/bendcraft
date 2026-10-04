# Owned menu-close disposition

`I.menu_close` is the production close path used by `S.menu_close`
and authenticated private MenuClose10. The current actor002 native binary is
an immutable earlier generation; these return semantics join the next actor
generation. The screen waits for the correlated full MenuReply and retains
its open menu and released capture when close refuses.

The complete owner contains 43 durable slots, four temporary crafting inputs,
carried ownership, selection, seven saved ability values, the verified item
catalog, derived result and menu revision. The derived result is a cache, not
an additional owned stack. Close never counts or returns it as an item.

`player_inventory_return.bend` builds an immutable plan from all 48 logical
slots. Actual pinned 26.3 receiver observations establish compatible merge order:
selected main slot, offhand 40, ascending main0–35, then first empty main0–35.
The carried slot 47 returns before crafting 43–46. Only compatible default item
keys merge; actual metadata controls stack limits. Survival and creative both
retain unreturnable items in the observed return receiver. Creative ability
does not authorize destroying a close remainder.

The sole actor-owned Array remains untouched while planning. Admission checks
all 48 original and final slots against actual metadata, temporary emptiness,
and complete per-item Nat count ledgers. Ledger queries include every nonempty
key appearing before or after; counts sum every logical cell. New keys and
removed keys cannot escape admission. Moves use the existing certified
`Inv.move_counts` transfer kernel. Once admitted, the actual `Inv.load_valid`
path writes 48 cells into the existing 64-cell backing Array. The other 16 cells,
selection, catalog and saved abilities retain their owners and values.

No actual item-entity/drop ownership receiver exists in this actor. If any
temporary item cannot fit, the entire original state is retained, including
earlier return candidates, carried/crafting cells, derived cache, revision and
open flag. The reply refuses close. This atomic refusal deliberately preserves
ownership where vanilla can transfer a remainder to a world entity. It must
be replaced by a real ownership transfer when that entity consumer exists;
deleting a remainder or a host-only simulated drop is not closing correctly.

Successful close clears the derived result and closes the menu. A changed
inventory or cleared derived cache increments the actor's menu revision. An
already empty menu with no result retains its revision. Durable encoding still
rejects temporary ownership; after accepted close, the presenter can request
the normal acknowledged world.save operation.

The actual 26-case Java corpus and its exact fresh-process reproduction are
documented in `PLAYER_INVENTORY_REFERENCE.md`. Production close proofs target
complete count ledgers, complete owner refusal/retention and all 64 backing
cells under the actual48-cell commit. `tests/player_inventory_close.bend`
calls the production close and consumes all 64 cells for observation.
`tools/test_player_inventory.py:close_suite` supplies 29 independent cases:
16 exact returnable Java outcomes, six atomic ownership refusals, three raw
ability/permission-retention cases and four derived-cache disposition cases.
The caller supplies the native executor; this helper never builds or launches
a process. Ordinary checking, independent-kernel verdicts and native execution
remain separate generation-specific evidence.

The twelve-law target (seven production contracts and five supporting logic
lemmas) passes ordinary checking in 3.974 seconds. Read-only selective export
pins the complete ten-file import graph before load, checks the unmodified
whole book with zero holes, retains all referenced types/implementations/proofs
and emits 118,723 bytes with no exclusions. The pinned independent kernel
passes that complete output in 2.067 seconds. The complete 64-cell commit law
quantifies over all 48 replacement cells and all 64 original cells, retaining
the last 16 original cells. It is not a small projected arithmetic model.
Exact generation-specific receipts and theorem-body pins are recorded in
`evidence/player-inventory-close-proof.json` and
`build/player-inventory-screen/close-selective-export-001`.

The focused ordinary CPU native build also passes all 29 independent cases.
Cold build takes 14.630 seconds with zero retries; the native replay takes
1.949 seconds and compares every backing cell and saved ability value. Build
and native process groups are absent after their unconditional cleanup.
`evidence/player-inventory-close-native.json` pins the exact current sources,
binary, independent expectations and raw receipts. This is actual inventory
execution, not a new actor/network/save verdict. The next actor generation must
still verify correlated MenuClose and acknowledged save together.
