# Current production proof targets

Pure correctness work starts with these production contracts. Run the affected
target after its implementation or interface changes. Ordinary checking checks
the Bend derivation; independent-kernel acceptance additionally requires a
successful `--verdict`. A timeout, exporter failure or foreign boundary is an
open obligation, not a passing proof.

The root `LAWS.bend` / `PROOF.bend` aggregation imports the 35 historical
foundation laws (two schedule, seventeen section and sixteen inventory) and
the eleven current player CoreEdit laws. This changed 46-law aggregation passes
ordinary checking and the independent kernel (0.261 / 0.775 seconds), recorded
in `evidence/production-root-proof.json`. Its scope does not include the saved
client or the other targets below.
Subsystem targets avoid forcing unrelated implementations into one enormous
kernel graph. Their statements must remain about the actual production functions
and complete owners, with service premises and excluded boundaries explicit.

| Production target | Contract and current status | Execution entry |
| --- | --- | --- |
| Player core edits | Eleven authority/refusal, commit-receipt and successful-edit contracts over `player_core_edit.bend`. The persistent production module passes ordinary checking and the independent kernel (0.130 / 0.237 seconds) on stable closures. No claim about arbitrary section-array contents or global rollback representation. | `src/player_core_edit_proof.bend`; receipt: `build/player-block-interaction-proofs/persistent-core-kernel-1791112077240692000/receipt.json` |
| Block interaction | Five complete Engine/Tables authority/build-denial laws compose with the eleven CoreEdit laws above. Earlier combined ordinary checking passed for the recorded generation; current dependency changes still need their final check. Full kernel checking is blocked by imported JSON descent. An exact retained `BI.execute` implementation closure excludes the serializer but reveals an actual unsupported `F32.neg` reference. CoreEdit-only acceptance does not prove interaction laws. | `src/player_block_interaction_proof.bend`; diagnostic: `build/player-block-interaction-proofs/bi-closure/receipt.json` |
| Required reset travel and saved facade | Three conditional whole-owner laws cover required travel success, refusal rollback through TH/X/runtime/save, and scheduled/direct preparation after one common tick. Stable ordinary checking passes. Restricting the read-only compiler API's export roots to these actual laws preserves the complete referenced implementations/types/proofs and emits 1,201,351 bytes with no exclusions; the pinned independent kernel passes in 0.199 seconds. Broad export timeouts remain preserved. Float-service premises and operational call-count limits remain explicit. | `src/local_player_reset_proof.bend`; `evidence/local-player-reset-proof-002.json`; `build/local-player-reset-proof/selective-kernel-001/summary.json` |
| Presentation allocation and event mapping | Seven laws cover actual tile/frame backing allocation, dimension interface, look/key/order preservation and rejection of outside pointer coordinates. Current ordinary checking passes (5.15 seconds). Selective export preserves the actual seven checked terms and referenced definitions, emits 132,573 bytes with no exclusions, and passes the independent kernel (0.024 seconds). The full-graph timeout remains preserved. These laws establish allocation/interface behavior; native U32 range/division, IEEE arithmetic, frame rates and OS input require their stated separate boundaries. | `src/player_presentation_proof.bend`; `build/player-presentation-proof/selective-kernel-001/summary.json` |
| Presentation focus, capture and projection | Nine laws cover suppression after loss of focus/capture, consumed capture click, untouched world subtree, matching projection and invisible padding. Current full dependency checking is in progress; earlier attempts found item-definition ownership errors. Independent-kernel acceptance remains open. | `src/player_presentation_input_proof.bend` |
| Full player inventory, menu and saved state | Base inventory has sixteen certified laws. Three existing player-profile refusal laws do not establish the expanded 43-slot durable / 46-slot menu contract. Full menu item conservation, temporary-item disposition, authority/controller composition and codec preservation are required and are being implemented with the production expansion. | Existing inline laws in `src/player_inventory.bend`; full-profile law/proof target remains to be completed |
| Generation settings and demand population | WG/codec/population/SF production modules pass ordinary checking. Actual loaded-owner identity, fresh-only/no-overwrite population, layer/dimension geometry and demand/follow composition law/proof modules are authored; their derivations and independent-kernel acceptance are still pending. Settings/codec composition, normal noise/biome/structure generation and eviction remain gaps. | `src/superflat_world_proof.bend`; actual pure Scene initialization: `src/superflat_player.bend` |

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
