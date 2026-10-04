# Durable generator settings and demand population

The regular saved client startup selects durable `world_generation_settings.Settings`
for a new save and retains the saved settings for a loaded save. The current
configured client profile is `bendex:stone-dirt-superflat`: stone 1, dirt 2, stone 1,
at Overworld minY=-64, height 384. It is an explicitly chosen custom profile.
`WG.normal` retains the installed normal Overworld noise-settings and multi-noise
preset identifiers; its terrain pipeline is unavailable and is refused explicitly.

This contract replaces the fixed 5×5 terrain instrument as the regular startup
path. A demand is a rectangular set of complete chunk columns, not a world bound.
The default spawn at `(0.5,-60,0.5)` requests four horizontal chunks and 26 sections
per chunk: all 24 dimension sections plus one air section on either vertical side.
That is 104 complete sections and 425,984 resident cells. Generation can request
other signed chunk coordinates without clamping the player to the old footprint.

## Settings and durable schema

`src/world_generation_settings.bend` owns dimensions, signed minY, positive
16-aligned height, all 64 seed bits, and a typed Flat/Noise generator sum.
Flat retains profile, biome, ordered layers, ordered block properties, feature
and lake requests, and the distinction between unspecified structures and an
explicit empty or nonempty structure request. Noise retains its settings ID and
MultiNoisePreset/EndBiomes/FixedBiome source. Resource names are validated as ASCII
resource identifiers; syntactic validation does not assert registry existence.
The actual resolver validates block/property requests against the loaded registry.

`src/world_generation_settings_codec.bend` stores this identity in a standalone,
strict NBT format 1 root named `bendex:world-generation-settings`. The root has
`format`, `kind`, and `payload`; the Settings payload has `dimension`, `min_y`,
`height`, `seed`, and `generator`. Generator alternatives have their own kind and
payload. Properties and layers retain list order. Structure metadata contains
`specified` and `entries`; unspecified metadata with nonempty entries is refused.
The bound is 16,384 bytes, depth 8, and 4,096 elements. Unknown/duplicate fields,
wrong types, unsupported versions and invalid settings are refused. This is
Bendex save metadata, not a vanilla level.dat codec.

The inventory codec's saved owner carries a fourth `generation` field and the
session carries it through detach, attach and dispatch. New format 3 saves encode
nonlegacy settings as this bounded ByteArray. Legacy and version 2 decode to
`WG.Unspecified`; their retained byte contracts belong to the inventory codec.
The fresh/load Boolean is nondurable provenance: only the initializer sets it
true, every decoder sets it false, and Scene marks it false after initialization.
An empty decoded Core remains loaded and must not reset its player record.

`reference/world_generation_settings.json` records three exact installed 26.3 ZIP
members for normal preset, flat world preset and Overworld dimension type.
The classic-flat member reuses the existing pinned observation. The installed
classic generator preset asks for villages; the flat world preset separately
asks for strongholds and villages. `WG.classic` retains the classic request and
therefore cannot enter the base-only generation path. The configured Java column
probe in `reference/superflat_world.json` uses explicit empty structure overrides
for both layer arrangements; it does not establish default preset structure parity.

## Population and ownership

`src/superflat_population.bend` receives a resolved Flat, signed chunk/section
rectangle, typed Budget, current Schedule stamp and the actual Core owner.
It admits the complete request before writing, bounds the request index to U32,
and validates coordinates, dimension geometry, state IDs, resident sections and
newly generated cells. Its default budget is 512 requested sections, 512 total
resident sections and 2,097,152 new cells, matching the current world codec limit.
Existing sections count toward the total across all dimensions.

Each absent section starts with 4096 air cells and receives all 4096 canonical
index writes. `y=index/256` chooses the ordered flat layer state; cells outside
the dimension or above the configured layers remain air. Population tests
presence without pop/reinsert, retains collision-bucket order and exact existing
section owners, and inserts only absent section keys. An existing edit is never
replaced with regenerated terrain.

Successful residency changes increment the Core revision exactly once, which
invalidates revision-sensitive snapshots. They retain tick, time, pause,
daylight, state count, pending mutations and public events exactly. Residency is
not a user BlockSet and does not append an Applied event ahead of same-tick
pending work. The typed Receipt reports requested, created and total loaded
section counts. A fully loaded demand is whole-world idempotent, including
revision and events. Admission or clock/order refusal returns the retained owner.
Fresh initialization alone may append its one Applied marker after the pristine
Core guard establishes that no pending mutations or previous events exist.

## Scene and view consumer

`src/superflat_world.bend` exposes `demand`, `demand_current`, `configure_production`
and `ensure_current`. Demand retains the complete Body/View/cache; configure
alone changes the region and invalidates its cache when bounds differ. The
request covers the view's one-cell neighbor halo and all complete dimension
columns. Signed coordinate checks account for both neighbors, including INT_MIN.
A malformed policy, unsupported generator or exceeded budget yields an explicit
error; it never changes the authoritative Body to fit a region or treats missing
sections as air.

`src/superflat_player.bend` is the pure player composition used by the actual
Scene. Loaded initialization is exact identity over the complete player owner.
Ensure retains tables, support, movement minor state, fall history, metadata,
motion history and outer history while querying the actual World. Only a proven
fresh session selects a new spawn and uses `R.fresh` to initialize those owners.
The actual player adapter explicitly refuses non-Overworld generator settings
before demand, since its World/support/collision positions still assume Overworld.
The durable record decoder already refuses non-Overworld player records, and the
session validates manually assembled records before attachment. Generic settings
and Core population retain dimension identity without claiming a dimension-aware
player adapter. Loaded startup ensures/configures the saved generator before the first read;
requested CLI settings cannot replace a loaded generator. `WG.Unspecified`
preserves the existing verification-fixture behavior.

`src/local_player_scene.bend` ensures residency before realtime ticks and each
scheduled `simulation.step` tick and follows the resulting Body afterward. The
session's runtime callback is invoked only after the existing developer/schema
and authentication gates. A generation failure stops further ticks, records the
actual error and shapes a successful step reply into `PlayerStepUnavailable`.
Each actual scheduled/realtime tick threads the retained inventory Status through
`S.run_with_status` and the runtime status driver. Runtime failure or pause retains
that status exactly; successful flight handling commits only its flying flag,
retaining invulnerable/mayfly and both raw speed words. Multi-tick advancement
stops on a recorded tick error. The backend's frame path ensures before snapshotting a valid frame, and its
private action path demands terrain only after retained Player authority,
instabuild/maybuild and button admission. Those backend guards belong to the
interaction subsystem.

The default transient view is 8×8×8 with a 512-cell admission policy. A fully solid
view has at most 3072 full-cube source quads, below today's 4096 pre-occlusion
model-producer limit. This is a renderer resource policy, not a Minecraft world
bound. Image dimensions and render scale do not enlarge world visibility.
Parameterized larger views require chunk batching/culling and an independent
scene memory/time budget before they can be treated as production visibility.

## Executable correctness scope

`src/superflat_world_laws.bend` and `src/superflat_world_proof.bend` contain 30
contracts about the actual generator, section map, World and pure player/Scene
composition. They cover loaded whole-owner identity; retention of every View and
cache field during demand; local-player tables, metadata and history retention;
unchanged and changed-view follow composition; arbitrary trie/collision-bucket
and count-prepass owner retention; pending/event/clock retention during residency
commit; empty-plan identity; layer intervals and dimension air; complete spawn
demand arithmetic; neighbor limits; clock refusal; unsupported player dimensions;
signed spawn-surface overflow refusal; and actual Section boundary writes/refusal.
Boundary write laws reuse the existing Section laws/proofs. Returned-pair equality
witnesses consume each actual section owner once rather than copying an affine
array into a model.

All 30 current terrain roots pass ordinary checking and the pinned independent
kernel. Their exact checked types and proof bodies were admitted across three
disjoint selections with identical source pins: the existing 27 roots,
the two unsupported-dimension roots, and the signed spawn-overflow root.
Their outputs contain 1,575,496, 1,350,885 and 543,164 bytes; kernel times were 4.285,
0.220 and 0.100 seconds. Each exporter retains all original declaration maps and
checked terms and includes every referenced dependency with zero exclusions.
The combined 30-root export hit a translator stack overflow after source checking;
that failed script, selection and streams remain preserved. Its checked-term and
source pins exactly match the successful selections. These are three independent
certificates, not a claim that the combined export succeeded.

`src/world_generation_settings_laws.bend` and its proof contain 12 additional
contracts: validation identity/refusal, invalid encode refusal, all 64 seed bits,
ordered structure requests, unspecified/empty request distinctions, and explicit
normal/default-flat unavailability. A fresh current-source export retained all 12
roots without exclusions and produced 286,621 bytes, identical to the earlier
certificate despite the unrelated travel import change. Its pinned kernel passed
in 0.053 seconds. The later runtime ability-selection extraction adds one imported module. Fresh
terrain exports capture the resulting 64-file source closure and reproduce every
checked type, proof body and output byte exactly. The prior pinned kernel verdicts
therefore apply to those identical proof inputs; no new kernel execution is claimed.
All shared source pins agree across the current artifacts.
`evidence/world-generation-production-proof.json` records the exact admitted roots,
checked-term/source pins, reproduction commands and retained receipt/failure references.
Repeated historical manifests remain in a fingerprinted local detail archive.

The concrete `existing_section_population_is_identity` theorem remains in
`src/superflat_population_pending_laws.bend` and its proof file, outside the
admitted aggregation. Its original 26-root kernel attempt reported `out of fuel`;
the unchanged statement and reflexivity body, failed input and streams remain
retained. It is excluded from the admitted count.

The separate `src/superflat_section_shape_laws.bend` and proof observe both
children of the actual Array and certify seven generic contracts: exact owner
retention through `Array.size`, topology preservation through actual Array/Section
writes and arbitrary-fuel `Population.fill`, perfect allocation topology, perfect
tree capacity, and the depth 12 Section constructor. Their current 65,840-byte
export has zero exclusions and passed the pinned kernel in 0.016 seconds. Main
ordinary/export checking passed in 0.527 seconds; source and checked-term identity
are recorded in `evidence/superflat-section-shape-proof.json`. Together with the
terrain 30 and settings 12 scopes, these are 49 exact admitted current laws across
five artifacts, with consistent shared source pins.

The two closed `Population.complete_section` topology/capacity corollaries remain
unchanged in `src/superflat_complete_section_pending_laws.bend` and its proof,
outside the admitted aggregation. Their source check passes and their statement
hashes match the original nine-root attempt, whose kernel reported `out of fuel`.
No completed-section topology or 4096-cell capacity certificate is claimed for
those pending statements. The original source snapshots, failed proof inputs and
the unsuccessful proof-wiring diagnostics remain retained.
Full 4096-write value induction, count-value correctness, complete codec roundtrips
and broader Scene/tick correctness remain separate obligations.

## Remaining product dependencies

Normal Minecraft requires the density/noise, biome, surface, carver, feature,
lake, structure and spawn pipelines. Flat base layers cannot substitute for them.
The runtime driver and reset policy still use a known-clear interior AABB
`[-64,64]^3`, plus an explicitly neutral dry/loaded environment. Those are
caller admission facts for an instrument, not Minecraft world-border or full
travel facts. They require actual world-border/environment providers.
General block collision/shape and visual state support must cover the loaded
registry; the retained stone/dirt/planks world adapter domain is not full-state
parity. View batching/culling must admit larger visibility under an explicit
scene budget. Region persistence and eviction must preserve edited sections and
scheduled ownership before exploration can exceed the 512-section durable owner.
All these dependencies remain open. Source checking and bounded reference
observations alone establish no native gameplay, streaming performance or
complete Minecraft generation parity.

The focused `tests/world_generation_settings_roundtrip.bend` harness passes
ordinary source checking and is prepared for the existing shared artifact via
`tools/test_world_generation_settings.py`. It compares all returned typed fields
for eight actual codec calls, including full seed words, identifiers longer
than 64 characters and absent/empty/ordered structure requests. Five injected
comparator corruptions are refused. This remains prepared-only until the native
artifact executes it; it does not substitute for a general codec roundtrip proof.

The same helper exposes `stone_dirt_root(seed)` and `stone_dirt_bytes(seed)` for
independent format 3 fixture preparation. Seed 0 produces 499 bytes with
SHA256 `1dcbeaaeaaf19a585d8662d82e52db8c1e543948b1bd9f216e4a235e3831708b`,
exactly matching the inventory subsystem's separately constructed metadata
fixture. Host NBT encode/parse equality and the five comparator corruptions pass;
these checks establish fixture preparation, not execution of the production decoder.
