# Architecture and implementation sequence

## Authority and ownership

One Bend simulation owns world sections, entities, inventories, block-update queues, registries and mod state. Integrated singleplayer and the dedicated server call the same transition functions. Rendering consumes snapshots/candidates without mutating simulation. Host effects handle OS resources and return owned handles; pure gameplay code does not depend on host effects.

The vanilla tick interval is 50 ms. Explicit stepping advances integer ticks. Requests are ordered at tick boundaries by target tick, connection identity and monotonically increasing request sequence; ownership leases arbitrate continuous controls. Wall time drives scheduling only. Randomness and save state are explicit inputs.

## Modules

- Reference tooling: pinned official metadata, installed jar hashes, full data inventory, behavioral/source fixtures. Generated identifiers never imply implemented behavior.
- Storage: 16³ sections with explicit index validation and signed-coordinate conversion; chunk maps and immutable/owned snapshots. Persistent formats version independently of Java saves.
- Core: typed state transitions, tick queues, transactional inventory changes, player permissions, entity/block/world systems.
- Packs: native pinned resource/data pack loading, registry composition and diagnostics. Packs and code mods have separate lifecycles.
- Mods: typed Bend hooks in each subsystem, dependency/order/conflict validation, migrations, client/server agreement, discoverable operation schemas.
- Renderer: Bend scene construction/culling/model processing and balanced tile work, native surface/input/audio boundaries. Pixel fidelity precedes optimizations.
- Interfaces: one operation catalog and dispatcher for client controls, local live sessions, scenario runner and MCP. Player/developer checks live in the dispatcher.
- Persistence: Bend codecs, checksums, journal/snapshot recovery; narrow durability effects if Base lacks fsync/rename.

## Verification

Data inventory is one layer; it does not specify all behavior. Coverage rows carry implementation evidence and verification evidence separately. Pure unit laws target conservation, order, isolation, indexing and serialization. Independent tests compare pinned source/reference behavior, frames/audio, actual transports and interrupted-write recovery. Performance results are accepted only for equivalent workloads.

Visible native end-to-end acceptance through computer use or equivalent real OS
input/presentation automation is mandatory. Start a bounded smoke scenario when
controls become stable, expand it with relevant UI/world/multiplayer features,
and repeat representative paths from the packaged client. Preserve the user's
focus through genuine desktop isolation or a coordinated foreground session.
Hidden pixels and synthetic events remain separate evidence. Audio and latency
need their own measurements. See `docs/VISUAL_ACCEPTANCE.md` for scenarios,
recording requirements and the current unverified status.

## First integration slice

Establish parsers and typed operation envelopes; section ownership; an authoritative deterministic tick/action kernel; native headless server and external request tests; root laws/proofs. This slice is foundation work and cannot satisfy vanilla gameplay parity.

Subsequent work must expand coverage continuously through exact collision/movement, block behavior and updates, inventory recipes and entities, worldgen/dimensions, presentation, packs, deep mods and all remaining vanilla systems. Work is ordered by dependencies, not by declaring difficult systems optional.
