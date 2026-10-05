# Entity section membership recovery and fresh registration

`src/entity_section_membership_recovery.bend` activates a decoded membership
image against the actual retained entity and runtime snapshot. Decoding the
format-5 membership payload establishes its internal structure; it does not
establish current loader visibility or authorize scheduling.

The recovery proposal contains immutable `E.View`, runtime, manager and callback
data. It contains no second `E.State`. `activate` inspects the actual scene owner;
`commit` installs both proposed owners only after publication acceptance. A
validation, visibility reconciliation or publication failure returns the full
original scene and manager, including entity RNG, UUIDs, poses, record order,
runtime fields, sound RNG and cursor values.

## Activation policy

`prepare(image, entities, runtimes, current)` requires `Some` for both the
decoded image and current loader observations, including a known empty image.
Every retained live record must have one registration and one runtime. Removed
records must be detached and retain their runtime tombstone. IDs are globally
unique because the current scene runtime owner is keyed by ID. Orphan and
duplicate runtimes refuse.

The image's section membership, UUID linkage, section insertion lists,
tracking/ticking lists and cached chunk status must first pass the production
membership codec validator. Each registration must then agree with the retained
record's UUID, insertion order, accessibility and actual entity bounding box.
Insertion orders must be unique and below the retained next-order cursor. The
global member list must have descending insertion orders, as actual manager
add/move callbacks prepend their newly allocated order. Together with the
codec's section-list linkage this checks actual section insertion chronology.
Tracking/ticking list order is preserved independently; status transitions can
append registry entries without moving their section membership.
The
registered packed key must agree with the record's completed position callback.
This is a consistency check; recovery preserves the saved key and box instead
of rebuilding them from the current position. Packed-coordinate aliases remain
valid. Stale halfway-moved images refuse.

Actual ItemEntity boxes are 0.25 by 0.25; ExperienceOrb boxes are 0.5 by 0.5 in
the admitted vanilla domain. Recovery dispatches by record kind. The item-only
`item_entity_tick_fields.body` function is never used as orb geometry. Nonfinite
or inconsistent saved boxes refuse activation even though the structural codec
can retain their raw words.

`current` is an ordered list of actual `M.Chunk` loader observations. Every saved
chunk fact, including a cached chunk with no current members, needs one current
observation. Aliased duplicate observations refuse. Extra current world chunks
are accepted and become current manager facts. `loaded` means actual chunk
availability; it does not mean that the separate entity-storage load is complete.
A chunk at EntityTicking with entity storage Pending may therefore provide
`loaded=True, Ticking`. Accessible status without loaded evidence refuses.
An explicitly observed unloaded Hidden chunk is accepted.

The caller supplies real current chunk availability and visibility. Physical
block-section presence alone does not establish visibility. The Java loader
mapping is Full/BlockTicking to Tracked and EntityTicking to Ticking; missing
observations are never replaced by an always-visible default.

After validating the saved state, recovery calls the production
`Manager.update_chunk` in the supplied observation order. This applies the actual
per-section callback passes and changes Common accessibility before any managed
scheduling. It retains registered keys, boxes, insertion orders and the entity
cursor. Existing tracking/ticking order survives unchanged status; transitions
remove and append IDs using the actual manager callback rules. The proposal's
ordered callback journal is published with the complete owner transaction.

This is a logical-session recovery policy: reconcile the saved status to the
current loader status once. It does not invent unavailable historical loader
events or replay entity-created callbacks. Java does not decode this project's
format-5 image. The independent Java specification for status transitions is
the actual pinned manager receiver described in
`entity_section_membership_reference.md`.

## Additive integration API

The existing `T.State` representation remains unchanged. The manager remains a
separate affine `M.State`.

```text
prepare(Maybe<M.View>, E.View, List<T.RuntimeEntry>, Maybe<List<M.Chunk>>)
  -> Result<T.Error, RecoveryModel.Plan>

commit(T.State, M.State, Result<T.Error, Plan>, Result<T.Error, Unit>)
  -> T.State & M.State & Result<T.Error, List<M.CallbackEvent>>

activate(T.State, M.State, Maybe<M.View>, Maybe<List<M.Chunk>>,
         Result<T.Error, Unit>)
  -> T.State & M.State & Result<T.Error, List<M.CallbackEvent>>
```

The publication result must come from the real surrounding lifecycle/effect
transaction. `prepare` supports staging that transaction; `activate` is the
convenience wrapper when acceptance is already known. The successfully returned
manager can be passed directly to `item_entity_tick_managed_scene.tick_id`.
Scheduling reads its actual `Manager.scheduled` insertion list.

## Fresh constructors

An actual fresh constructor already assigns `pre_order` and advances its
proposed `E.View.next_section_order` once. Before invoking that constructor, call
`constructor_ready(before)` to refuse native Nat48 cursor exhaustion without
evaluating an overflowing addition. Then supply its actual `E.Plan` and actual
fresh runtime to `fresh` or the corresponding prepared/commit functions.

```text
constructor_ready(E.View) -> Result<T.Error, Unit>

fresh_prepare(E.View, M.View, List<T.RuntimeEntry>, E.Plan, U32, T.Runtime,
              Maybe<List<M.Chunk>>) -> Result<T.Error, RecoveryModel.Fresh>

fresh(T.State, M.State, E.Plan, U32, T.Runtime, Maybe<List<M.Chunk>>,
      Result<T.Error, Unit>)
  -> T.State & M.State & Result<T.Error, RecoveryModel.FreshPublication>
```

`fresh` inspects both actual owners. It validates and reconciles their existing
registrations, checks exactly one new identity, requires the new record's order
to equal the old cursor, and requires the constructor cursor to equal old plus
one. The manager registers using the old cursor, so the committed cursor equals
the constructor result and is not advanced a second time. Existing records come
from the actual retained owner, with only visibility reconciliation applied;
a copied constructor prefix cannot replace their poses, identities or RNG.

Fresh registration uses the actual manager `on_add` path, including new-entity
creation, tracking and ticking callbacks. It requires real destination facts,
preserves the constructor's RNG/UUID and remaining entropy tickets, appends one
runtime, and publishes only after acceptance. `FreshPublication` contains the
ordered callback journal and remaining constructor times. Failure returns both
complete original owners without consuming their state.

The focused new native and independent-kernel evidence is recorded separately
in `evidence/entity-section-membership-recovery-native.json` and
`evidence/entity-section-membership-recovery-proof.json`; the proof statements
are described in `entity_section_membership_recovery_proof.md`. These results
do not establish actor adoption, real storage streaming, all entity types or
full gameplay/client completion.
