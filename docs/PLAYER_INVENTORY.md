# Owned local-player inventory

The playable LocalPlayer session owns 36 main slots, seven durable equipment
slots, four temporary crafting inputs and carried ownership. Slots 0–8 are the
hotbar; selection is restricted to that range. The production profile loads the
verified 1658-row item table and uses each item's actual default stack limit
and equipment admission. The three-item profile remains an explicit legacy
fixture interface. Full menu topology, native controller and current dependency
gaps are documented in `PLAYER_INVENTORY_SCREEN.md`; owned close disposition is
documented in `PLAYER_INVENTORY_CLOSE.md`.

`src/player_inventory.bend` owns the affine backing array and uses the existing
`src/inventory.bend` checked transfer kernel. A transfer clamps to the source
count, requested count and destination space. Empty source, different item,
full destination, equal indices and bounds failures preserve the entire owned
inventory. Split requires an empty destination; merge requires a destination
stack. Counts of zero produce no transfer when the remaining admission checks
permit it. These custom split/merge admission names are not assertions about
vanilla mouse-click protocols.

Creative acquisition replaces a single slot and requires the player's
`instabuild` ability. It accepts a table-backed item and count up to that item's
actual limit; zero clears the slot. Modified components, unknown item IDs and invalid indices/counts are
refused. Acquisition does not change either build ability. `maybuild` is a
separate permission consumed by block interaction. Public transport has no
operation that grants either ability.

## Session interface

The typed session operations are `inventory_inspect`, `inventory_selected`,
`inventory_select`, `inventory_transfer`, `inventory_acquire` and
`inventory_abilities`. Each returns the same authoritative session beside its
result. Inventory reads and changes do not tick or duplicate the world.

The additive public catalog contains:

| Operation | Required arguments | Result |
| --- | --- | --- |
| `inventory.inspect` | none | `selected`, 36 `slots`, `abilities` |
| `inventory.selected` | none | `index`, `slot` |
| `inventory.select` | `slot`: 0–8 | `selected` |
| `inventory.transfer` | `source`, `destination`: 0–35; `count`: unsigned U32; `mode`: `transfer`, `split`, `merge` | `moved`; rejected transfers return a fault |
| `inventory.acquire` | `slot`: 0–35; `item`: verified catalog ID; `count`: unsigned U32 admitted by actual metadata | `acquired`; ability/state refusals return a fault |

Empty slots are JSON `null`; occupied slots contain exact `id`, `components`
(the empty default marker) and `count`. Duplicate/unknown fields, invalid numeric
lexemes, omitted required fields, out-of-range values and scheduled `at` fields
are rejected by the existing extension admission path before mutation.

Public MCP reads are Public; select, transfer and acquire are DeveloperOnly
because that API has no live player authentication. The private native-client
wire instead uses the retained authenticated Player capability and saved
abilities. Ordinary inventory movement does not require maybuild.

`S.operations()` and `S.new()` remain the legacy record-only catalog/adoption
contract. `S.inventory_operations()` and `S.new_inventory()` adopt the additive
saved inventory contract. A legacy catalog does not admit the new operations.

## Save contract and startup provenance

The outer extension remains namespace `bendex:local-player-record`, schema 1.
When selection is zero, all 36 slots are empty and abilities are the default
`instabuild=false, maybuild=true`, the payload is the original LocalPlayer
record bytes exactly. The original `Record`, storage codec, helpers and fixture
routes are retained.

The production format 3 payload extends the complete inner root with equipment,
all five additional saved ability fields (including exact raw binary32 words),
and standalone typed generation bytes. Temporary menu ownership is excluded
and prevents save until close returns it or a future real drop consumer takes
ownership. Eligible legacy/default and format 2 payloads retain exact bytes.
Decoding restores the actual saved profile without a launch-mode override.

The explicit legacy nondefault format 2 interface uses inner root
`bendex:local-player-inventory-record`. Its exact fields are `format` Int 2,
`record` ByteArray (the complete existing LocalPlayer record), `selected` Int,
`instabuild` and `maybuild` Boolean Bytes, and `slots` List of exactly 36
Compounds. Empty slot Compounds have no members. Occupied slots have String
`id` and Int `count`. Field sets and tag types are strict. Canonical encoding
checks supported IDs, component defaults, selection and counts; decoding
restores the saved abilities rather than applying a launch profile.

`IC.codec_creative()` changes only missing-world fresh initialization. Existing
legacy payloads restore default abilities; versioned payloads restore their
explicit abilities. There is no implicit Core-only or plain-Player migration.

`IC.Saved.fresh` and the session's matching flag are transient provenance, not a
saved field. Fresh initialization sets it true; every decode sets it false.
`S.fresh` exposes it without losing ownership and `S.mark_initialized` clears
it. The terrain initializer uses this flag so an empty loaded Core is preserved
and a loaded player's position/history are never reset as a side effect of
terrain inspection.

`S.reserve_local_player` reserves the renderer's real `C.Player` peer from the
durable highwater allocator before public listeners open. It refuses exhaustion
when there would be no public ID left. `S.block_action` passes that capability,
the lease sequence, saved build abilities and selected held item to the block
interaction consumer while preserving all transient runtime fields.

## Verification status

`tests/player_inventory.bend` drives production transitions and encoding. The
independent Python fixture comparator in `tools/test_player_inventory.py` owns
62 focused transition expectations and 50 physical codec cases: 11 accepted
(including two fresh profiles), 39 rejected. It accepts a supervised executor;
it never launches a process or builds a binary itself. It compares all 36 slots
and both abilities after every transition, exact canonical bytes for accepted
payloads, refusal without output files for malformed payloads, legacy empty
byte equality and transient fresh/load provenance.

The following ordinary-check counts describe the historical legacy generation,
not the expanded current actor. Preparation and host corpus self-checks pass. The pure inventory source reaches
ordinary `ALL PROOFS CHECK`; the codec and harness reach only the existing 42
foreign durability/locking/persistence definitions. The session reaches only
58 effect dependents, without syntax, type or law diagnostics. This is ordinary
compiler checking, not a mathematical kernel verdict or native execution.

Actual Java extraction observed 125 cases in one bounded JVM, with all 4,405
loaded official classes checked against the pinned client JAR. The native
`reference_suite` is deliberately limited to 91 observed supported cases: nine
selected-slot cases and 82 direct `Slot.safeInsert` cases. It compares the exact
36 slots, selected index and the two supported build abilities; it does not
equate custom rejection labels with vanilla results. Its host fixture setup
has been checked against the observed data, but native replay is still pending.
The other Java observations are reference evidence, not added implementation
coverage.

Supervised native execution, atomic save/cold restart and a fresh JVM reference
reproduction remain pending. The shared playable-session acceptance owner is
responsible for actual native transport/save/restart comparison. Java execution
and its separately scoped claims are recorded in
`docs/PLAYER_INVENTORY_REFERENCE.md`.
