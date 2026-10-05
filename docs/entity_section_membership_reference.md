# Pinned Java 26.3 entity section membership reference

Confidence: **high for the observed manager operations**. `tools/reference_entity_section_membership.py` executes the installed, fingerprint-verified Java 26.3 `PersistentEntitySectionManager`, its actual nested `Callback`, `EntitySectionStorage`, `EntitySection`, `EntityLookup`, and `LevelEntityGetterAdapter`. The classes are not copied or reimplemented in the harness. The pinned client SHA-256 is `4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d`.

The harness supplies a small `EntityAccess` with deterministic identity, position, bounding box, removal state, and callback storage. Its persistence adapter returns already-completed empty chunk loads; it never saves. This isolates actual membership and lifecycle behavior without booting a world. It does not establish item physics, real chunk streaming, save recovery, networking, rendering, or full client parity.

Run from the Minecraft repository:

```sh
python3 tools/reference_entity_section_membership.py
```

The reference has **71 scenarios and 220 recorded steps** in `reference/entity_section_membership.json`. Ignored reconstruction artifacts are under `build/entity-section-membership-reference/`: the generated Java harness, output, stdout/stderr, and actual receiver bytecode. The committed fixture records source, harness, bytecode, client, metadata, runtime, and official-library fingerprints. The extraction rejects unexpected runtime observations using assertions derived from a separate bytecode audit.

## Observed operations

Registration first reserves the UUID, computes the packed section key, creates or finds that section, appends membership, and installs the manager callback. New and world-generation registration then publish `created`; legacy loaded registration skips it. Tracking starts next, with visible lookup insertion before `tracking_start`. Ticking starts last. Duplicate UUID admission returns false before section or callback mutation. A hidden section still contains the entity, even if the visible lookup and spatial query omit it.

Movement compares the actual `SectionPos.asLong(entity.blockPosition())` against the callback's current packed key. Equal keys cause no removal, append, or lifecycle event. The cases include movement within one section and aliases separated by a whole packed X, Y, or Z coordinate period.

For different keys, movement captures the old raw visibility, removes old membership, removes the old section if empty, creates or finds the destination, appends the entity to its membership, and replaces the callback's current section and key. Visibility callbacks run after those mutations. An existing destination therefore retains its current members and receives the moved entity at the end. Moving back likewise appends behind remaining source members.

For normal entities, cross-section movement publishes these lifecycle callbacks in order:

| Old visibility | Destination visibility | Callback events |
|---|---|---|
| HIDDEN | HIDDEN | none |
| HIDDEN | TRACKED | tracking_start, section_change |
| HIDDEN | TICKING | tracking_start, ticking_start, section_change |
| TRACKED | HIDDEN | tracking_end |
| TRACKED | TRACKED | section_change |
| TRACKED | TICKING | ticking_start, section_change |
| TICKING | HIDDEN | tracking_end, ticking_end |
| TICKING | TRACKED | ticking_end, section_change |
| TICKING | TICKING | section_change |

`tracking_end` executes before visible lookup removal. Callback snapshots therefore still include the departing entity in `global_ids`; its section membership and spatial accessibility already reflect the new destination.

Removal first detaches section membership. It then publishes `ticking_end` when applicable, `tracking_end` when applicable, and `destroyed` only when the removal reason's actual `shouldDestroy()` is true. UUID removal follows, then callback replacement with `EntityInLevelCallback.NULL`, then empty-section cleanup. Removal callbacks still see the known UUID; the detached empty section still exists until final cleanup. Subsequent movement through the cleared callback makes no manager mutation. Registration of a new object using the released UUID succeeds.

All five actual removal enum values are exercised: `KILLED` and `DISCARDED` destroy; `UNLOADED_TO_CHUNK`, `UNLOADED_WITH_PLAYER`, and `CHANGED_DIMENSION` do not. Only `UNLOADED_TO_CHUNK` has `shouldSave()` true.

## Chunk visibility changes have a different event order

The actual chunk visibility method first updates the chunk visibility map and load/unload bookkeeping. It visits existing sections in packed Y order. For each section it sets the new raw visibility, completes a pass stopping ticking entities, completes the tracking transition pass, then completes a pass starting ticking entities. No `section_change` event is published by this method.

Consequently a TICKING-to-HIDDEN **movement** publishes tracking end before ticking end, while a TICKING-to-HIDDEN **chunk visibility change** publishes ticking end before tracking end. The latter completes each pass for the entire current section before proceeding. The multi-entity visibility fixture observes Y=0, then Y=1, then Y=-1; within Y=0 it observes both ticking ends before both tracking ends.

An always-ticking entity's effective lifecycle visibility is always TICKING. Registration/removal use that effective visibility, every cross-section move publishes only `section_change`, and chunk visibility transition passes exclude the entity. Spatial queries still use the section's raw accessibility. The reference therefore observes an always-ticking entity in a raw HIDDEN section in `global_ids`, while omitting it from `query_ids`.

## Query traversal order

The spatial storage expands candidate section bounds by X/Z `[min - 2, max + 2]` and Y `[min - 4, max]`, then converts coordinates through the actual section coordinate conversion. It traverses X numerically ascending. Within one X it traverses sorted packed keys, which order **masked Z, then masked Y** ascending. Nonnegative Z/Y precede negative Z/Y; this is not ordinary signed coordinate lexicographic order. The final signed Y/Z range tests exclude out-of-range sections. Null, empty, and raw-inaccessible sections are skipped.

Each section's list preserves insertion order. The complete fixture query over deliberately scrambled insertion returns `[4, 10, 5, 12, 6, 2, 7, 3, 9, 8, 1, 11]`; moving entity 1 into the existing origin section changes that order to `[4, 10, 5, 12, 1, 6, 2, 7, 3, 9, 8, 11]`. The abortable query stops the entire traversal after `[4, 10, 5]`.

The ordinary visible entity getter uses the visible lookup's insertion order. It is a different order from section-based spatial traversal. Leaving tracking removes the lookup entry; entering tracking inserts it at the end.

## Fixture schema

Each case has an `id`, `category`, operation parameters, and `steps`. A step records `action`, any direct return value such as registration `accepted`, ordered lifecycle `events`, and final `state`. Each section includes a packed unsigned 64-bit key as `[high32, low32]`, decoded `[x, y, z]`, raw visibility `status`, and ordered `members` IDs. Callback events snapshot membership, actual spatial query, actual visible lookup, known UUID availability, and the callback key at publication time.

`query_ids` use the recorded `default_query_box`, with each controlled entity's AABB extending X/Z by 0.125 and Y upward by 0.25. `global_ids` come from the actual getter's `getAll()`. `callback_keys` distinguish registered callbacks from NULL callbacks. `known_ids` mean that each controlled object's **UUID** is known to the manager: after a duplicate UUID attempt or a replacement admission, multiple controlled objects may share the same known UUID. That field does not claim object admission.
