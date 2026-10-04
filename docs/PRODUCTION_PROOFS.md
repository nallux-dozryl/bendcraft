# Current production proof targets

Pure correctness work starts with these production contracts. Run the affected
target after its implementation or interface changes. Ordinary checking checks
the Bend derivation; independent-kernel acceptance additionally requires a
successful `--verdict`. A timeout, exporter failure or foreign boundary is an
open obligation, not a passing proof.

The root `LAWS.bend` / `PROOF.bend` aggregation imports the 35 historical
foundation laws (two schedule, seventeen section and sixteen inventory), eleven
current player CoreEdit laws and nineteen actual application options laws.
This 65-law aggregation passes ordinary checking and the pinned independent
kernel (0.196 / 0.566 seconds), recorded in `evidence/production-root-proof.json`
and `build/production-root-proof-002/receipt.json`. The prior 46-law receipt is
retained under `build/production-root-proof`. This scope does not include the
saved client or the other targets below.
Subsystem targets avoid forcing unrelated implementations into one enormous
kernel graph. Their statements must remain about the actual production functions
and complete owners, with service premises and excluded boundaries explicit.

| Production target | Contract and current status | Execution entry |
| --- | --- | --- |
| Application options | Nineteen laws cover actual parser steps over arbitrary remaining arguments and complete option records, missing values, retained failures, profile admission/refusal and pause defaults. Full 93,574-byte emitted IR independently passes the pinned kernel (0.043 seconds); also imported by the 65-law root. Native111 observations check argument order/errors/Unicode. This is not a universal equivalence theorem with the historical parser or a full backend build. | `src/resource_server_options_proof.bend`; `build/compiler-parser-proof-001/proof.bendtt`; `evidence/compiler-memory-diagnosis.json` |
| Player core edits | Eleven authority/refusal, commit-receipt and successful-edit contracts over `player_core_edit.bend`. The persistent production module passes ordinary checking and the independent kernel (0.130 / 0.237 seconds) on stable closures. No claim about arbitrary section-array contents or global rollback representation. | `src/player_core_edit_proof.bend`; receipt: `build/player-block-interaction-proofs/persistent-core-kernel-1791112077240692000/receipt.json` |
| Block interaction | Five complete Engine/Tables authority/build-denial laws compose with the eleven CoreEdit laws above. Current ordinary checking passes (6.307 seconds); the complete selective export of the five unchanged checked theorem roots emits 1,179,921 bytes with no exclusions and independently passes the kernel (0.197 seconds). The earlier full-import JSON rejection and retained `BI.execute` closure's unsupported `F32.neg` reference remain historical diagnostics. These five contracts certify authority rollback, not all picking/placement geometry or IEEE behavior. | `src/player_block_interaction_proof.bend`; `build/player-block-interaction-proofs/bi-selective-1791113278529024000/receipt.json` |
| Required reset travel and saved facade | Three conditional whole-owner laws cover required travel success, refusal rollback through TH/X/runtime/save, and scheduled/direct preparation after one common tick. Stable ordinary checking passes. Restricting the read-only compiler API's export roots to these actual laws preserves the complete referenced implementations/types/proofs and emits 1,201,351 bytes with no exclusions; the pinned independent kernel passes in 0.199 seconds. Broad export timeouts remain preserved. Float-service premises and operational call-count limits remain explicit. | `src/local_player_reset_proof.bend`; `evidence/local-player-reset-proof-002.json`; `build/local-player-reset-proof/selective-kernel-001/summary.json` |
| Presentation allocation and event mapping | Seven laws cover actual tile/frame backing allocation, dimension interface, look/key/order preservation and rejection of outside pointer coordinates. Current ordinary checking passes (5.15 seconds). Selective export preserves the actual seven checked terms and referenced definitions, emits 132,573 bytes with no exclusions, and passes the independent kernel (0.024 seconds). The full-graph timeout remains preserved. These laws establish allocation/interface behavior; native U32 range/division, IEEE arithmetic, frame rates and OS input require their stated separate boundaries. | `src/player_presentation_proof.bend`; `build/player-presentation-proof/selective-kernel-001/summary.json` |
| Presentation focus, capture and projection | Nine laws cover suppression after loss of focus/capture, consumed capture click, untouched world subtree, matching projection and invisible padding. Current ordinary checking passes (33.47 seconds). Full selective export of unchanged actual theorem terms emits244,270 bytes with no exclusions and independently passes the pinned kernel (0.130 seconds). Native/IEEE/menu IO/performance boundaries remain separate. | `src/player_presentation_input_proof.bend` |
| Backend menu/frame ownership | Five actual unchanged Backend State/session admission and authority contracts independently pass the pinned kernel (0.375 seconds), with complete 2,336,818-byte referenced IR. Current Transport/frame consumer is source-clean through 104 declared foreign/unsafe boundaries. The sixth Hello contract remains separately excluded by the Nat.show.fin/go mutual-recursion exporter limitation; no native menu/backend/frame acceptance yet. | Inline laws in `src/remote_resource_backend.bend`; `evidence/player-inventory-menu-wire-source-checks.json` |
| Saved player ability publication | Three actual complete-owner laws cover mode-threaded LM/FR/H/T completion, required-ray refusal retaining the complete saved Status, and provider/resume publication retaining every raw status word except the actual returned flying value. Complete 1,266,298-byte unchanged referenced IR passes the pinned kernel (0.194 seconds), no exclusions. The focused native LI/P consumer matches 13 actual Java raw observations exactly. A subsequent focused native target computes the actual production toggle/takeoff selector and also matches all thirteen Java observations. Full travel and the complete actor remain separate checks; source-generation-specific receipts govern each claim. | `src/local_player_abilities_proof.bend`; `evidence/local-player-abilities-proof-002.json` |
| Full player inventory, menu and saved state | Base inventory has sixteen certified laws. Three existing player-profile refusal laws do not establish the expanded 43-slot durable / 46-slot menu contract. Full menu item conservation, temporary-item disposition, authority/controller composition and codec preservation are required and are being implemented with the production expansion. | Existing inline laws in `src/player_inventory.bend`; full-profile law/proof target remains to be completed |
| Inventory Screen authority/controller composition | Nine actual production laws certify retained or installed full MenuSnapshot/catalog authority, complete controller retention on an unadmitted observation, focus-loss idempotence, whole inventory refusal, menu flag updates and production transfer-count conservation. Complete 1,514,020-byte unchanged referenced IR passes the pinned independent kernel (0.399 seconds), no exclusions. Native Screen/controller interaction and OS input remain separate. | `src/player_inventory_screen_proof.bend`; `build/player-inventory-screen/selective-export-002/kernel.receipt.json` |
| Generation settings and demand population | Current WG/codec12 and SF30 actual unchanged theorem roots independently pass the pinned kernel across four zero-exclusion artifacts: WG12 plus disjoint SF1/2/27 partitions. Shared source pins match the current status/dimension join; the failed combined SF30 export is retained. These contracts cover complete View and arbitrary trie/bucket/count-prepass owner retention, clocks/pending/events, empty plans and current dimension/signed-surface admission. Seven additional actual Array/Section/Population topology/capacity roots pass the independent kernel with unchanged 65,840-byte IR and no exclusions. The separate existing-section concrete identity and full 4096-leaf shape/codec completion remain pending. Normal noise/biome/structure generation, non-Overworld runtime readers and eviction remain gaps. | `src/superflat_world_proof.bend`; `src/world_generation_settings_proof.bend`; `evidence/world-generation-production-proof.json`; actual pure Scene initialization: `src/superflat_player.bend` |

For an existing target, run from the Minecraft directory:

```sh
/Users/chuah/.bend/bin/bend src/local_player_reset_proof.bend --check-only
/Users/chuah/.bend/bin/bend src/local_player_reset_proof.bend --verdict
```

Substitute the execution entry from the table. Coordinate the two-heavy-job
limit, bound attempts, retain failure output, and fix a concrete compiler/kernel
blocker before repeating a failed equivalent graph. A retained declaration
closure may exclude unrelated imported definitions only if it preserves every
transitively referenced implementation, type, statement and proof byte-for-byte
and the independent kernel checks that complete closure. Such a workaround does
not certify omitted code; in particular JSON serialization remains a separate
open termination obligation.

Pinned Java reference observations validate the chosen specification. Native
FFI/OS controls, actual TCP/MCP, durable-save interruption, resource decoding and
performance measurements remain boundary checks. Historical pure sample suites
are retained evidence, and targeted regressions remain where no meaningful
proof or specification evidence closes the actual gap. They are not mandatory
unrelated imports in the live product acceptance artifact.
