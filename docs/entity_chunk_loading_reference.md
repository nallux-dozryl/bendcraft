# Pinned 26.3 chunk and entity loading reference

The reference producer is `tools/reference_entity_chunk_loading.py`. Its actual
runtime probe invokes the installed Java classes; it does not implement chunk
loading in Python. Run 001 passed in 3.5164 seconds with five entity-load cases,
28 entity steps, 462 real simulation graph cells, 15 level cases, nine registered
ticket types, and the ticket timer/listener checks. The runtime result is
`reference/entity_chunk_loading.json`. The actual Java and javap processes were
absent in the final process inventory. **Confidence: high** for the recorded
boundaries; the named full-cache execution boundaries remain unobserved.

The installed client is
`/Users/chuah/Library/Application Support/minecraft/versions/26.3/26.3.jar`,
SHA-256 `4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d`.
Version metadata SHA-256 is
`9a7b39dae3b9c8d30006b650e357aae220629b7852fa0fc7221db7a8646bd5e4`.
The JAR contains directly named classes; a mapping transform is unnecessary for
these targets. The reproducible probe records receiver class hashes, complete
`javap -c -p -constants` hash, runtime/library provenance, and command receipt.

## Status and completion are different facts

`ChunkLevel.fullStatus(int)` uses signed integer comparisons:

| Ticket loading level | Full status | Entity visibility | Accessible | Ticking |
| --- | --- | --- | --- | --- |
| ≤ 31 | `ENTITY_TICKING` | `TICKING` | true | true |
| 32 | `BLOCK_TICKING` | `TRACKED` | true | false |
| 33 | `FULL` | `TRACKED` | true | false |
| ≥ 34 | `INACCESSIBLE` | `HIDDEN` | false | false |

Authority: `ChunkLevel.fullStatus`, bytecode offsets 0–33;
`Visibility.fromFullChunkStatus`, offsets 0–31. `FullChunkStatus.isOrAfter` is an
ordinal comparison in order INACCESSIBLE, FULL, BLOCK_TICKING, ENTITY_TICKING.
`ChunkLevel.isLoaded` additionally includes generation-stage levels through
`MAX_LEVEL`; FULL's accumulated generation dependency radius determines that
maximum. The actual runtime confirms radius **11**, MAX_LEVEL **44**, and
unavailable loading level **45**. Normal nonnegative generation requirements are
FULL through level 33, INITIALIZE_LIGHT at 34, TERRAIN at 35, BIOMES at 36, and
STRUCTURE_STARTS at 37–44. At 45 the generation requirement is null. The observed
negative/extreme integer cases call the raw Java helper directly; they do not
claim persisted tickets accept negative levels. At Integer.MIN_VALUE,
generationStatus's integer subtraction wraps and returns null even though the
full-status helper says ENTITY_TICKING.

`GenerationChunkHolder.getFullStatus()` derives a target from its current ticket
level. That getter is not a completion witness. `ChunkHolder.updateFutures`
creates separate accessible, block-ticking, and entity-ticking futures when
their respective thresholds are crossed. `scheduleFullChunkPromotion` cancels
the old confirmation gate, installs a new gate, and completes it only through
`ChunkResult.ifSuccess`. Its callback runs on the supplied executor and calls
`ChunkMap.onFullChunkStatusChange`, which forwards to the status listener. A
failed result does not confirm a promotion. Demotion cancels the gate and calls
the listener synchronously. Cancellation does not establish that an already
scheduled executor callback can be revoked: no such race is observed by this
probe.

Crossing several thresholds in one update prepares them in FULL →
BLOCK_TICKING → ENTITY_TICKING order and replaces each earlier confirmation
gate. The listener therefore need not observe every intermediate promotion.
Leaving a threshold completes its unresolved future with the unloaded result
and replaces the field with the shared unloaded future. Re-entering entity
ticking when its field is not that shared unloaded future throws
`IllegalStateException`.

`ChunkMap.prepareAccessibleChunk` requires a radius-one chunk range with
generation dependencies; `prepareTickingChunk` requires all nine radius-one
chunks at FULL and then, on the main-thread executor, post-processes the center
and starts its ticking. `prepareEntityTickingChunk` requires all 25 radius-two
chunks at FULL. Range enumeration is increasing z, then increasing x, with
Chebyshev radius. A missing updating holder returns an unloaded range result;
successful results select the center. These are bytecode observations of the
real classes; the prepared runtime fixture does not instantiate ChunkMap or a
real world.

ServerLevel passes `entityManager.updateChunkStatus` as the actual chunk status
listener. PersistentEntitySectionManager separately owns default FRESH,
PENDING, and LOADED entity-file state. An accessible status queues a storage
load only when the state is FRESH. `requestChunkLoad` writes PENDING before
calling `EntityPersistentStorage.loadEntities`; its successful future appends
ChunkEntities to a concurrent inbox. Future success alone leaves the status
PENDING. `processPendingLoads` registers the returned entities in their order,
using the current section visibility, and only then writes LOADED. Loaded
registration omits `onCreated`, but installs each callback before tracking and
ticking callbacks. A successful empty list also establishes LOADED.

Failure logs `Failed to read chunk` and leaves PENDING without enqueueing,
fabricating LOADED, or retrying on a repeated accessible status. Hiding a chunk
ends active callbacks immediately and queues unloading. Entity manager `tick`
drains pending successes before processing unloads; unload while PENDING is
deferred. A successful hidden completion can therefore register hidden entities
and be stored and removed in that same tick. Normal entities remain hidden;
`isAlwaysTicking` entities still activate, as in the existing membership
reference. Unloading removes the load-status entry back to default FRESH;
reactivation then requests storage again. Reactivation while already PENDING
cancels the queued unload and retains the same request.

`canPositionTick` checks visibility only. Existing in-memory entities can start
ticking while an entity-file request remains PENDING. ServerLevel explicitly
separates these consumers:

- `areEntitiesLoaded`: entity-file LOADED only.
- `areEntitiesActuallyLoadedAndTicking`: entity-file LOADED and TICKING visibility.
- `isPositionTickingWithEntitiesLoaded`: entity-file LOADED and the cache's
  successful block-ticking future plus simulation block range.
- `isPositionEntityTicking`: TICKING visibility and simulation entity range.

A Core block read, terrain population count, target ticket status, or viewport
presence does not substitute for the completion required by one of those
specific consumers.

## Tickets, timers, and graph authority

TicketStorage uses packed signed-long chunk keys and ordered per-chunk ticket
lists. Ticket deduplication uses **TicketType object identity and integer level**,
not TicketType record equality, remaining lifetime, or a caller identifier.
Adding a duplicate resets the existing object's timer and returns false without
notifying listeners. A distinct level or equal-valued distinct type object
remains a distinct ticket. Direct removal finds the first type-identity/level
match.

Adding a new ticket notifies Simulation then Loading only when it lowers each
eligible minimum. Direct removal notifies Simulation then Loading for the
removed flags, including unchanged minima. Bulk expiry/removal reverses that
order to Loading then Simulation, after any removal carrying those flags.

`getTicketLevelAt(chunk, simulation)` takes the minimum level among tickets with
the requested bit. No eligible ticket returns MAX_LEVEL + 1. ChunkTracker
propagates over all eight horizontal neighbors at cost one, so the converged
level is the minimum source level plus Chebyshev distance, capped by its graph.
SimulationChunkTracker stores only levels below 33 and returns 33 otherwise;
its graph level count is 34. LoadingChunkTracker has unavailable MAX_LEVEL + 1
and graph level count MAX_LEVEL + 2. Loading-only tickets do not supply the
simulation graph, and simulation-only tickets do not supply the loading graph.

The flags are persist 1, loading 2, simulation 4, keep dimension active 8, and
expiry qualification bypass 16. Exact registered defaults from TicketType's
static initializer are:

| Type | Signed-long timeout | Flags |
| --- | ---: | ---: |
| PLAYER_SPAWN | 20 | 2 |
| SPAWN_SEARCH | 1 | 2 |
| DRAGON | 0 | 6 |
| PLAYER_LOADING | 0 | 2 |
| PLAYER_SIMULATION | 0 | 12 |
| FORCED | 0 | 15 |
| PORTAL | 300 | 15 |
| ENDER_PEARL | 40 | 14 |
| UNKNOWN | 1 | 18 |

Ticket `ticksLeft` is a Java signed-long countdown, initialized/reset from its
type timeout. Timeout zero means no timeout. A timed ticket is expired exactly
when ticksLeft < 0, so timeout T > 0 survives decrement T at zero and expires
on eligible decrement T + 1. Subtraction uses wrapping Java `lsub`, without
checked overflow or saturation. The actual custom-type extremum test observes
Long.MIN_VALUE decrement to Long.MAX_VALUE; this does not assert that
vanilla's registered types use negative timeouts.

An expiry decrement is eligible only if timeout is nonzero and either flag 16
is present, the updating holder is absent, or its holder is ready for saving.
A present holder not ready for saving pauses ordinary timed tickets. The
actual runtime TTL probe uses UNKNOWN/custom flag-16 types with a null
ChunkMap, which the actual method short-circuits before consulting a holder.
Holder readiness qualification is bytecode-audited and remains unprobed.
ServerChunkCache purges before distance updates when the tick rate manager runs
normally or the tick method's boolean argument is false. Wall time and API
polling do not define countdown decrements.

DistanceManager updates natural spawn, simulation, player loading, and loading
trackers in that order. When holders need future updates, it first updates all
highest allowed statuses, then all futures, clears that set, and returns;
dispatcher-release work waits for a later update call. Player simulation source
level is max(0, 31 − simulationDistance), using Java int arithmetic. Player
loading admission uses PLAYER_LOADING level 31 and rechecks the current player
distance on the main thread before adding a dispatched ticket. Leaving range
requests dispatcher release plus main-thread removal. Java's constructor uses
simulation distance 10 and dispatcher limit 4; these are actual Java values,
not proposed product limits.

No world epoch or request token occurs in the audited native ticket/manager
fields. A Bend owner may bind external completions to a world/dimension/epoch
and unique request identity to reject stale responses, but such identifiers are
an adaptation of ownership, not quoted Java fields or invented observations.

## Observed runtime scope

Reproduce when the shared heavy-job capacity permits:

```sh
/Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -B tools/reference_entity_chunk_loading.py --work build/entity-chunk-loading-reference/run-001
```

The fixture covers actual level/visibility boundaries, nine registered ticket
types, duplicate refresh and type identity, both listener orderings, timeout
zero/one and signed-long extrema, six simulation graph states, and five entity
load scenarios: successful load/unload/reload, hidden pending completion,
reactivation of one pending request, exceptional storage completion, and an
existing entity that activates before file loading completes.

Controlled EntityAccess positions and in-memory storage are declared fixture
inputs. The actual Java manager performs registration, callback activation,
load completion, and unloading. Actual Java SimulationChunkTracker performs
distance propagation. The fixture does not observe real terrain generation,
ChunkMap/ServerChunkCache completion execution, disk entity files, transport,
renderer, world restart, full dispatcher race ordering, or whole-game parity.
