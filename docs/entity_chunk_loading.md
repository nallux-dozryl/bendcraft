# Entity chunk loading: source and kernel checkpoint

High confidence: the current transient metadata implementation passes the original
Bend source checker, and its 13 stated laws pass the independent kernel. The pinned
26.3 Java observations are separate reference evidence. The prepared 507-case
Bend/Java differential has passed source checking but has **not run natively**.
This subsystem is not installed in the live actor. Current cooking delivery work
has priority; no loader producer expansion or native campaign was started.

`src/entity_chunk_loading_model.bend` owns one affine `State`, with complete
active/inactive ticket lists, chunk target and confirmed statuses, pending
promotion identities, entity-storage phases, holder observations, counter and
ordered journal. The implementation never owns or copies a Core world or entity
state. Metadata refusals retain the entire prior loader view. A world name,
dimension, epoch and request counter are explicit Bend callback guards; they are
not fields claimed to exist in Java and do not authenticate a physical world by
themselves.

`entity_chunk_loading_tickets.bend` implements registered identity/level
admission and removal, duplicate timer refresh, exact signed-long countdown,
flag-specific source minima, listener order and per-chunk expiry qualification.
`entity_chunk_loading_math.bend` retains raw Java integer/long words and computes
settled Chebyshev graph values. Settled distance or a target ticket level does
not complete a chunk. A real holder-readiness observation is required for ordinary
timed-ticket expiry; absent observations refuse. Flag 16 follows Java's bypass.
The special graph source sentinel and Java asynchronous dispatcher race ordering
are outside the current differential fixture. Closing-ticket deactivation,
inactive activation and persistent-ticket projection remain unimplemented;
existing inactive lists are carried unchanged.

`entity_chunk_loading.bend` separates scheduling, successful full completion,
entity-future inbox arrival and actual insertion acknowledgement. A changed
level within the same target full-status rank retains its pending request.
Promotion completion requires the current world/epoch, key, request and requested
status; a stale or repeated completion refuses. A read failure records the
failure while retaining `Pending`. Hiding a pending/inbox chunk cannot declare
it unloaded. An existing entity may tick under confirmed `EntityTicking` while
its separate storage phase remains pending, matching the observed Java manager.
These are typed metadata seams; no real provider calls them yet.

The exact current-facts adapter is:

```bend
entity_chunk_loading_observation.current(state, scope)
  -> State & Result<String, List<entity_section_membership_model.Chunk>>
```

`Unavailable` returns an explicit refusal. A present owner emits only retained
confirmed statuses and full-load completion flags with matching scope. It reads
no Core sections, camera footprint or saved membership flags. The intended
consumer is `entity_section_membership_recovery.prepare(image, entities,
runtimes, current)`, followed by actual `ManagedTick` activation. The parent
currently requires `Maybe<View>` for `image` and `Maybe<List<Chunk>>` for
`current`; a missing provider must remain `None`/refusal. This checkpoint does
not invoke or install that consumer.

The concrete missing producers are a transferred sole Core/Engine loading
operation that completes the actual supported terrain stages under a live
request, and a separate actual entity-bundle load completion followed by manager
insertion. `Scene.production_gate`, `SuperflatPopulation.Receipt` and resident
sections are actual generation facts, but they do not establish Java
`ChunkMap.prepareAccessibleChunk`, its radius-one block-ticking future, its
radius-two entity-ticking future, or successful entity-storage reads. No runnable
terrain/bundle adapter has been implemented here. A future adapter must preserve
the sole Core and entity owners, bind receipts to their real world lifetime, and
refuse unsupported generation/storage providers. It must not mint visibility
from recovery images.

The 13 kernel laws cover complete refusal frames and unavailable-provider
observations, pending/inbox versus completed insertion, hidden pending unload
refusal, ticking visibility independent of pending storage, status visibility,
and timeout-zero raw-state retention. They do not establish arbitrary lifecycle
parity, the real completion producers, full TicketStorage parity, transport,
persistence, or performance.

Current evidence is `evidence/entity-chunk-loading-checkpoint-001.json`.
Raw bounded attempts remain under `build/entity-chunk-loading/` and
`build/entity-chunk-loading-reference/`. All owned groups are absent. The
historical Actor012 baseline was untouched. Reproduce the completed scopes with
fresh output directories:

```sh
/Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -B tools/test_entity_chunk_loading.py --mode proof --work build/entity-chunk-loading/proof-NEW
/Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -B tools/test_entity_chunk_loading_reference.py --mode source --work build/entity-chunk-loading-reference/differential-source-NEW
```

The prepared native command is the same differential runner with `--mode native`
and a fresh directory. It remains unexecuted. Reference details and actual Java
probe commands are in [entity_chunk_loading_reference.md](entity_chunk_loading_reference.md).
