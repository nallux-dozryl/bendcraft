# Status

Target: Minecraft Java 26.3. Compiler: Bend 2.0.35. Persistent goal: active.

## Established

- Inspected project root: minecraft was absent. Existing bend, tetris and inker remain untouched.
- Read applicable Bend instructions and all three required guides.
- Compiler source revision verified: 79df8d9c40722ee9507a1e253f283b51025f9d6c.
- Installed reference jar and version metadata exist under the local Minecraft installation.
- Full data inventory extracted reproducibly from hash-verified official artifacts: 1,286 blocks / 35,723 states, 1,658 items, 161 entity types, 95 static registries / 7,053 entries, 94 command roots / 2,475 nodes. Inventory is not behavior implementation.
- Independent Lean 4.34.0 distribution fetched and SHA-256 verified. BendTT kernel built and cached. Root PROOF.bend accepts 35 implementation laws in both checker and independent kernel.

## Current implementation

No gameplay equivalence has been established. The full scope remains open.

| Foundation | Implementation and verification |
| --- | --- |
| Section storage | Owned 16³ arrays, checked indexing, signed coordinate conversion, clone/snapshot. All 4,096 coordinates/cells and 33 independent signed fixtures tested; 17 laws pass independent kernel. |
| Inventory primitives | Exact item/component identity and injected stack limits; checked transfer/split/merge and rollback. 13,671 native oracle fixtures; 16 laws pass kernel, with U32/array boundary explicitly tested rather than falsely proved. |
| Tick queue | Sorted tick/peer/sequence ordering, due/future partition, cancellation. Native tests and two universal queue-conservation laws pass kernel. |
| Authoritative core | One world owner; developer admission checks; scheduled section edits/time/daylight; paused/realtime and explicit stepping; rejection events. Native integration tests pass. No terrain, physics or block behavior implied. |
| Owned section map | Concrete Bend trie/collision buckets avoid unsupported generic array layout. Independent colliding hash fixture, replace/pop/missing-key tests pass native and kernel. |
| JSON | Pure bounded RFC grammar, exact number lexemes, Unicode/duplicates diagnostics. 536 independent native cases and 299 roundtrips. Serializer's ordinary-checker/kernel termination mismatch remains open and is recorded; it is excluded from root proof claims. |
| Automated native launch | Strict project-local generated-window transform; CPU/Metal hidden probes preserve foreground app with no observed activation/Spaces changes. This is OS-boundary evidence, not rendered-game fidelity. |

The TCP actor/server source is being integrated with the pure operation catalog and byte framer. The registry resolver, binary64 substrate and Java block-state physics fixtures are current parallel work. Live/API/MCP, vanilla client, gameplay, worldgen, persistence, deep mods and all other gates remain unfinished.

## Reproducible current checks

- `python3 tools/proof_kernel.py`
- `/Users/chuah/.bend/bin/bend tests/core.bend --verdict`
- `/Users/chuah/.bend/bin/bend tests/core.bend -o build/test-core && ./build/test-core`
- `/Users/chuah/.bend/bin/bend tests/section_map.bend -o build/test-section-map && ./build/test-section-map`
- `python3 tools/test_inventory.py --verdict`
- `python3 tools/test_json.py`
- `python3 tools/platform_test.py`
- Reference reproduction commands and exact limits are in docs/REFERENCE.md and docs/COVERAGE.md.

## Completion gates

1. Release inventory reconciled, including non-data behavior and quirks; implemented and verified fields independent.
2. Client modes/UI, all dimensions/worldgen/content/simulation/progression/commands/settings/resource and data packs verified against pinned Java behavior.
3. Shared integrated/dedicated simulation, robust persistence and external multiplayer sessions verified.
4. Deep typed Bend modding exercised by content and system overhauls, migration and tooling tests.
5. Live API and actual MCP cover every subsystem; external gameplay, editing, mod operations and repeatable assertion scenarios pass.
6. Real implementation laws/proofs check; unsafe/foreign boundaries documented.
7. Packaged macOS client/server, reproducible builds and docs, honest equivalent-workload benchmark evidence.

None of these gates is currently satisfied.
