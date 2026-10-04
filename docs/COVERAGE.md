# Reference and implementation coverage

The 26.3 release inventory is extracted. **No inventory row counts as implemented or independently verified gameplay.** Confidence in the artifact hashes and the reproduced inventory is high. Confidence in full implementation parity is unknown because the inventory tooling does not assess the Bend implementation.

[reference/coverage.json](../reference/coverage.json) is the machine-readable ledger. Its initial 238 rows include static registries, every bundled data category/pack scope, client resource categories, external asset metadata, 39 non-data behavior groups and five additional product requirements. These rows are work groupings rather than a denominator for a percentage of Minecraft implemented. Counts inside a row describe reference content, not completed behavior.

Each row independently records:

| Field | Meaning |
| --- | --- |
| `reference_inventory_status` / `reference_evidence` | What reference content or source location has been captured |
| `implementation_status` / `implementation_evidence` | What Bend behavior is implemented, with source/build evidence |
| `behavioral_reference_status` / `behavioral_reference_evidence` | Independent Java expectations or observations available for that scope |
| `verification_status` / `verification_evidence` | Comparisons showing the actual implementation matches the pinned behavior |

Initial implementation and verification statuses are `not_assessed`, rather than fabricated success or a claim that other agents' current code has been inspected. Initial behavioral-reference status is `not_collected`, except the tick group, which has a `partial_narrow_fixture`. Updating one field does not automatically advance another.

`python3 tools/reference_coverage.py` refreshes inventory fields while preserving the implementation/verification statuses and evidence, behavioral-reference evidence, and additional rows already present in the ledger. Use evidence that describes exactly what passed. A registry loader accepting 1,286 identifiers proves neither their corresponding block behaviors nor rendering, persistence, commands or multiplayer semantics.

The ledger now also records ten explicit bounded component/reference rows for
owned local travel/history, conditional pose, CPU mipmaps, the slab catalog,
actual vanilla serialization evidence, the resource-client build attempts and
Entity common-tick metadata, CPU sprite animation, owned pose-world queries and
the saved LocalPlayer actor. Its fresh composite passes both primary suites,
1,510codec cases, complete43phase cases twice and3facade guards twice. Root
replay recomputes allphase/facade/codec outputs and28finalbundles; prior phase
interruption and all host failures remain preserved as historical evidence.
The resource row
now records the third failed monolithic attempt and successful Bend actor/
renderer builds. Three actual hidden standing frames, atomic sample and full
saved bundle pass and were independently replayed; the first paired suite then
stopped at a host expectation rejecting the intended stop0 stderr marker. The
exact-marker host adoption then passed the full paired suite: six views, live
edits, actual LocalPlayer fixture inputs, full save/reload, protocol and resource
failure recovery, idle release and real timer callbacks. The lead recomputed
271 compared returned CPU images (4,440,064 RGB pixels), six complete view
bundles and eight actual records. Physical OS input, drawable/GPU presentation,
general resources/gameplay and performance remain unverified.
Each pins its current sources and receipts, states its measured domain and
keeps independent kernel status separate. Parent obligations remain unchanged:
a bounded projection or reproduced reference does not complete its broader
movement, player, asset, rendering or persistence group. The ledger has 253 rows;
these work groupings still provide no meaningful whole-game completion percentage.

## Established reference evidence

| Evidence | Established scope |
| --- | --- |
| [reference_inventory.json](../evidence/reference_inventory.json) | Pinned hashes; official generator; 8,372 byte-equal client/server data files; complete base registry/state/item/command/packet inventories |
| [reference_verification.json](../evidence/reference_verification.json) | Independent reading and comparison of 35,723 emitted states, 7,053 registry entries, 260 packet IDs and 2,475 command nodes |
| [reference_selftest.json](../evidence/reference_selftest.json) | Byte reproducibility of 14 reference outputs; rejection of a corrupt state ID before and after checksum resealing |
| [reference_structures.json](../evidence/reference_structures.json) | Complete parsing of all 1,511 bundled NBT templates; no trailing bytes or unknown palette block identifiers |
| [reference_behavior_inventory.json](../evidence/reference_behavior_inventory.json) | 92 named compiled classes located and verified for 39 curated behavior groups |
| [reference_tick_probe.json](../evidence/reference_tick_probe.json) | Direct Java observations of default tick rate, one noninteger interval, one low-rate clamp and frozen two-step countdown |

None establishes Bend game parity. The state and registry checks validate the extractor's metadata transport; the structure checks validate reading the bundled templates. The tick probe establishes a narrow **Java reference fixture**, with no Bend implementation comparison. Protocol IDs provide dispatch identities, with packet field layouts and semantics still open. Command-tree nodes provide syntax and parser identities, with permissions, selectors, state changes and errors still open.

## Outstanding reference and behavior work

The curated obligation map deliberately does not claim an exhaustive specification. Each group must be expanded into concrete, version-specific behaviors and failure cases as code analysis and reference fixtures expose them.

| Work group | Required evidence beyond the inventory |
| --- | --- |
| Simulation and chunk lifecycle | Default/adjusted cadence, exact stage/update order, freeze/step/sprint/pause, ticket activity and unloading |
| Randomness and world generation | Algorithms, stream consumption, seeds, density/climate/surface/aquifer/structure results, dimension transitions and portals |
| Blocks, fluids and redstone | Shape/placement/support rules, interactions, breaking/tools, scheduled/random ticks, neighbor order and timing quirks |
| Block entities, items and inventories | Every specialized block entity; component values/codecs; use/damage/cooldowns; menus and all click/merge/transaction rules |
| Recipes, loot, enchanting and trades | Exact matching/effects/context/randomness, special recipes, trade progression and experimental pack variants |
| Entities, movement, AI and spawning | Species behavior, numerical physics/collision, riding, damage/effects, pathfinding, brains, caps and despawning |
| Player modes and progression | Abilities and permissions, hunger/XP, respawn, advancement triggers/rewards and statistics |
| Commands, scoreboards, time and environment | Every executable node, selectors/errors, teams/boss bars/waypoints, clocks/timelines/weather/sleep, fire/explosions/light |
| Persistence and networking | Typed field codecs, migration, recovery/corruption/interruption tests, protocol fields/order, actual external multi-client sessions |
| Client presentation | Window/input/client-loop rules, exact geometry/camera/light/transparency, models/textures/equipment, particles/audio/music, all UI/settings/accessibility/localization |
| Packs and game tests | Complete codec schemas/defaults/errors, metadata/ranges/overlays/priority, tags/registry composition, reload and actual test execution |

The 155 data-pack registry locations and observed JSON keys do not replace complete versioned codec schemas. External asset-index names and hashes do not establish decoded media, rendering or playback. Built-in experimental packs require feature-aware behavior and coverage; merely listing their metadata is insufficient.

The project additionally requires typed Bend mods across every subsystem, live/API operations and actual MCP transport, laws/proofs of the real implementation, reproducible macOS client/server packages, and equivalent-workload performance evidence. These are separate ledger rows because vanilla data inventory cannot implement or verify them. Their authoritative acceptance conditions remain in [AGENTS.md](../AGENTS.md), [STATUS.md](STATUS.md) and the persistent user goal.

Completion requires a reconciled reference inventory **and** implementation evidence **and** independent behavior verification, including non-data quirks and the additional product requirements. The current extraction completes one bounded reference task. All larger project completion gates remain open.

The additional `product:visible_native_client_acceptance` row records the
mandatory visible native end-to-end OS input/presentation method. Its
verification remains unassessed: hidden frames and synthetic internal events do
not satisfy it. Progressive scenarios, matched pinned-vanilla comparisons,
package rechecks, separate audio/latency evidence and the focus-preserving
session policy are specified in [VISUAL_ACCEPTANCE.md](VISUAL_ACCEPTANCE.md).
