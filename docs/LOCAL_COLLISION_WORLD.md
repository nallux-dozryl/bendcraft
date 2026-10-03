# Owned local collision queries — Java 26.3

`src/local_collision_world.bend` drives the verified LocalCollision edge-backoff
state machine against the sole owned ClientWorld/Core. Its production source
and narrow native harness pass ordinary type/termination checking. Fresh direct
actual Java extraction, observer parity, independent repetition and five
integrity injections pass. The installed native build and every admitted
behavioral comparison pass. The full harness independent BendTT kernel exited
with the compiler's TypeScript/BendTT mismatch diagnostic, so its mathematical
verification is unresolved. Confidence is high for the native behavior within
the measured admission; no independent proof claim is made for the five new laws.

## Public contract

```text
backoff_checked(world: ClientWorld.State, request: Request)
  -> ClientWorld.State & Result<Error, Observation>

Request {
  body: Movement.Body,
  requested: Movement.Vec3,
  context: LocalCollision.EdgeContext,
  environment: Environment,
  fuel: Nat,
  tail: List<Request>
}

Environment {
  entities: KnownEmptyEntityCollisions | UnresolvedEntityCollisions,
  border: KnownClearBorderInterior {box: Geometry.AABB} | UnresolvedWorldBorder
}

Observation {corrected: Movement.Vec3, queries: List<QueryRecord>}
QueryRecord {
  box: Geometry.AABB, clear: Bool,
  yielded: Maybe<Geometry.AABB>, reads: List<Read>
}
Read {position: Core.Position, state: U32}
```

The omitted Result/List region arguments in this sketch are `&2` in source.
Construct Request with `tail: []`. The recursive Request/Frame/Scan boxes and
harness Slot boxes prevent native continuations from flattening their large
Body/context/view captures. Tails carry no gameplay meaning. The request body
must equal the current authoritative `W.View.body` in every raw F64/F32 word
and flag. Numerical equality does not admit a signed-zero substitution.

The caller explicitly declares an empty relevant entity-collision set and a
known-clear border interior for this finite neutral fixture. These declarations
are admission evidence supplied by the caller; the module does not discover
entities or resolve a border. Every requested query AABB must be contained in
the declared finite, ordered interior. Unresolved entities/border, invalid
interior, an outside query and insufficient query fuel reject. A finite query
must also pass ClientWorld's signed-i32 floor/bounds admission: each padded axis
extent is 3 through 16. Wider scans and unrepresentable coordinates reject.

The operation resolves the four supported names through the current actual
Registry owner each time: air, stone, dirt and oak_planks, each with one state
and no properties. It verifies the cached View palette matches that current
mapping. Missing or stale palette rejects; it never substitutes cached numeric
IDs for registry resolution. Missing Core sections, unknown block states and
registry failures return an error rather than an air/clear answer.

On success it returns the corrected requested movement and ordered query/read
observations. On failure it returns the original Body, complete View and the
same Core/Registry owners. Body position, box, velocity, dimensions and flags;
camera, region, snapshot cache; Core tick, time, pause/daylight, revision,
registry state count, pending queue and events are retained. The module performs
reads only: it does not call `World.move`, mutate sections, advance clocks or
apply the corrected vector to velocity. The synthetic harness's setup/edit
operations explicitly check their actual Core Result before proceeding.

## Exact query execution

Each LocalCollision EdgeQuery is answered once through actual Core reads and
then passed to `edge_answer_checked`. Query fuel counts these answers, including
an airborne above-ground probe. EdgeDone consumes no further fuel or query.
The adapter uses the existing exact ClientWorld query bounds and Cursor3D cell
ordering: X advances fastest, then Y, then Z. Axis bounds are
`floor(min - 1e-7d) - 1` through `floor(max + 1e-7d) + 1`, inclusive, with each
F64 operation rounded separately by the pure F64 module.

A boundary-type-3 corner is skipped before reading Core. Boundary types 1 and 2
are read, then excluded for these four admitted states because their actual
shapes have neither the large-collision-shape nor MOVING_PISTON exceptions.
Only boundary type 0 yields an intersecting full cube. The first yielded shape
returns `clear = false` immediately; the scan reads nothing after that hit.
A complete scan with no yield returns `clear = true`. Ordered traces include
read shell cells that produce no shape and omit skipped corners.

This behavior is verified against actual `Level.noCollision`/BlockCollisions
read/yield observations, not inferred from the backoff AABB traces. Unknown
states are conservatively rejected even in a shell cell where the admitted
four-state Java path would exclude a nonlarge shape: an unknown state's flags
and shape are unavailable.

Backoff belongs before Entity.collide and its initial/step collision queries;
its result corrects the requested displacement, leaving deltaMovement intact.
The minor hook remains the separate LocalCollision operation with no world
read. Actual Entity.move invokes it only for horizontalCollision, after the
support update and the position-application gate. This adapter does not reorder
or implement those later phases.

Airborne eligibility takes the explicit authoritative observed fallDistance
from EdgeContext, together with the actual Body grounded flag and resolved
maxUpStep. Cached Support state is not a substitute. The production integration
that measures and persists fallDistance updates remains open. Flight, swimming,
passengers, noPhysics, effects and unsupported worlds remain rejected by the
checked LocalCollision context. This adapter does not establish a complete
LocalPlayer tick, pose update or general collision-shape/world support.

## Actual reference boundary

`tools/reference_local_collision_world_probe.py` derives its receiver source
in memory from the frozen LC and LI templates, leaving all frozen files
unchanged. It calls untouched actual `Player.maybeBackOffFromEdge` on normally
constructed actual LocalPlayer objects and calls actual super Level.noCollision.
The observed Level wraps the original BlockCollisions iterator while preserving
hasNext/next order and early exit. `getBlockState` records positions and actual
returned state IDs/names only during an active noCollision query. Actual plain
receivers and super-calling observers agree on projected state and results.

The world uses actual ClientLevel/LevelChunk and actual block states: 25 stone
floor cells at x,z=-2..2/y=0, otherwise air, plus explicit sequential writes of
admitted air/stone/dirt/planks. Actor storage is empty and the real default
world border is clear in the fixture interior. Exactly the four external LI
service substitutes are used (Minecraft, ClientPacketListener, Gui, Tutorial);
no LocalPlayer, Player, Entity, Level collision method, predicate or arithmetic
under verification is replaced. The receiver fixture is not a complete running
Minecraft client. Expanded source hashes, service contracts and all loaded
class bytes are pinned in the actual evidence.

The corpus has 106 cases: 102 admitted finite four-state cases and four measured
flight/mover guard contexts outside the checked helper boundary. It contains
932 actual noCollision queries, 35,079 ordered returned block reads and 175
first shape yields. Two source slab cases and one nonfinite-Y case are explicitly
excluded. The ten new world cases include individual stone/dirt/planks/air
floors, mixed and hole edges, sequential replacement and positive/negative edge
boundaries. Fresh extraction and independent actual repetition agree on every
case projection and the entire 4,370 official-class loaded tree.

Final reference SHA-256:
`a72c5f81863fc1af689e1050a00e4aac5f1f8d2e646efbc005891921a1474e05`.
Producer SHA-256:
`52dee95f922a2a1e0e419e5e5fb09d6acec9feb23535b470b371b2a6305b2643`.
Java SOURCE SHA-256:
`9a0618d6c526096862878dbec4295c357e9bb96a6613b51f5b2118bc60338a57`.
The 26.3 client jar SHA-256 is
`4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d`.
The installed runtime is Microsoft OpenJDK 25.0.1+8-LTS.

Tracked actual/debug/independent evidence is compact and hash-links complete raw
reports, event streams, source inventories, loaded class tree and stdout/stderr
in ignored `build/local-collision-world-reference/`. The reference retains all
before/after/result/admission fields and typed query/read/yield rows; only its
duplicate projected raw query-event stream was removed. Five client/runtime/
library/source/read mutations are rejected by provenance/integrity verification.

## Verification commands and status

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_collision_world_probe.py --extract
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_collision_world_probe.py --rerun
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_collision_world_probe.py --verify-existing --selftest
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_collision_world.py --ordinary-only
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_collision_world.py --prepare-only
# Run only after the lead grants one heavy slot:
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_collision_world.py
```

The final command runs one content-pinned native build capped at 600 seconds,
all native/reference/policy/remap comparisons, then one independent kernel
attempt capped at 60 seconds, sequentially. Process-group RSS/virtual-size
samples are compiler resource observations, not gameplay performance measures.
The existing content-checked build tool preserves and pins its preflight emitted
C, compiler, source/native dependencies and executable. The native CLI internally
compiles another temporary C file; those original temporary bytes were not
retained directly. The retained C is labelled the associated content-pinned
preflight emission, rather than the native CLI's original temporary C. No new
emission was run after verification. A failure or timeout is recorded honestly
without becoming a proof claim.

The native harness supplies eight actual air sections covering [-16,15]^3,
then checks all 25 floor writes and actual reference world edits. It compares
raw corrected movement, exact query boxes, each clear Bool, first shape, and
every ordered Core read against the actual Java trace. It records complete
Body/View/cache/clock/queue values before and after. Extra policy cases exercise
signed-zero body mismatch, unresolved entities/border, invalid/outside interior,
zero query budget, absent/stale palette, unknown glass state, missing section
and six unsupported contexts, each followed by a valid operation using the
retained sole world. A running world with nondefault time/daylight and a real
pending mutation tests that reads neither advance nor consume its queue. Four
actual world cases are rerun against an alternate registry whose dynamically
resolved state IDs are air=2, stone=1, dirt=3, planks=0. Python only serializes
inputs and compares actual outputs; it implements no query or movement logic.

Five quantified source laws ordinary-check: body mismatch returns the complete
world, unresolved environment returns the complete world, outside queries and
zero budget retain Core, and cursor corners perform no Core read. Their
independent mathematical kernel verdict remains unverified; ordinary checking
alone is not that verdict. Reference/ordinary preparation is recorded in
`evidence/local-collision-world-prepared.json` and
`evidence/local-collision-world-ordinary-final.json`.

## Final native and kernel observations

The unchanged admitted corpus passed natively: 102 cases, 932 exact query boxes
and answers, 35,079 ordered reads and 175 first yields. All four measured guard
rejections, 16 policy rejections with same-owner recovery, the nondefault
running clock/pending case, and four dynamic-remap cases passed. No gameplay
source, oracle, fixture, expected-result or comparison change was needed.
The raw results are 127 stdout/stderr pairs under ignored
`build/local-collision-world-verification/`.

The content-pinned build passed in 24.491251 seconds (600-second cap). Its
internal receipt reports 7.321518 seconds for preflight C emission and
14.609995 seconds for the installed native CLI phase; the latter includes
native emission/checking/compilation and is not a pure Clang timing. The
successful immutable executable is 2,171,128 bytes, SHA-256
`5d6dd678f84f3f9cc9540f422bcf6ddd113ef0ba87e3373a9b5df87135b84574`.
The retained preflight C is 4,231,455 bytes, SHA-256
`b9b16e7115a48aa3313647e1d93d746d7342b2707def926c76c357db9a05f918`.
Apple Clang 17 used the installed route's `-std=c11 -O3 -lpthread -lm` flags.
This is compiler work, not a Minecraft gameplay benchmark.

The one sequential full-harness kernel attempt exited 1 after 20.090484
seconds (60-second cap), with the installed diagnostic stating that its
TypeScript implementation and formal BendTT kernel disagree and cannot yet
validate the proofs. It named no source law or gameplay mismatch. This
observation does not prove the laws false and does not establish their
independent validity. No retry, standalone diagnostic or source change was
run. The process groups were reaped and the slot was released.

The originally executed runner SHA-256 is
`7b9fcf5e235a1f2bc0e4759218741f60acee5758df8a3b7e28bc3317d063c8c4`.
It originally wrote the aggregate summary only after the kernel attempt; that
failure prevented finalization, although all native comparisons had completed.
The preserved native outputs were subsequently rechecked with its unchanged
serialization/comparison functions, substituting cached reads for subprocess
execution. `evidence/local-collision-world-native-verification.json` explicitly
records this receipt recovery. Individual native-case durations were not
retained and are not inferred.

The lead authorized a reporting-only fix for future runs: persist the native
pass before starting the independent proof attempt, then separately finalize
success or an unverified kernel status. Current runner SHA-256 is
`6e33058fba3b11aadb26b7987ea76cff9acba8c8315e55df99f389a29b5e166b`.
Only `main` changed; all 20 other function ASTs and nonfunction ASTs are identical,
including native protocol, actual expected/comparison, build and generation
helpers. No native, Java or Bend execution followed this reporting change.
`evidence/local-collision-world-reporting-split.json` seals the original runner
copy and executed receipts separately from the current reporting producer.

The final read-only audit rechecked all 56 Bend/Base/effect inputs, all 1,650
native/compiler/header dependency lookup targets, sizes and hashes, six
executed runner tools (with the explicit reporting-only driver exception), two
additional Python helpers, release metadata, default block registry, reference,
retained C and immutable executable. Generation SHA-256 is
`f2e8bbd904d85ab49478b9f0425a6e6a9ec1a0c4ab25f44d8cf8bfa8164a0398`.
Source SHA-256 is
`4e6e46737890c1203fb66ee95859e26825b306a6db865a1869e8663a7b9a2346`;
harness SHA-256 is
`0a7bc0f88e948d1f6e8d53ed34e71475ce6d42ee9d3a0371da848e7504dce1b8`.
See `evidence/local-collision-world-native-closure.json`, the separate build and
kernel receipts, and final `evidence/local-collision-world-verification.json`.
Source and actual fixtures remain frozen. Native parity is checkpointable;
independent kernel verification and full integration remain explicit open work.

## Receipt storage compaction

The duplicated full build/native dependency manifests and repetitive per-run
receipt metadata are compact tracked summaries. Exact original JSON bytes stay
under ignored `build/local-collision-world/`, linked by size and SHA-256. The
1,650-row native manifest retains its canonical digest/count. The 127 raw native
stdout/stderr pairs remain unchanged, and all actual case/guard/recovery/remap
summary fields are equivalent to the full original native result.
`evidence/local-collision-world-storage.json` records storage and equivalence.

Reproduce only formatting and its read-only audit with:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_collision_world.py --compact-existing
```

This command performs no Java, Bend, native or kernel execution. The only new
helper is report formatting; all 20 executed helpers and nonfunction ASTs remain
identical. The original executed runner hash and kernel failure are retained.
The preflight C is still distinguished from the native CLI internal temporary C.
