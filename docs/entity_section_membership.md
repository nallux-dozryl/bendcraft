# Entity section membership authority

The production authority is `src/entity_section_membership.bend`, with data
contracts in `src/entity_section_membership_model.bend` and actual Core presence
capture in `src/entity_section_membership_world.bend`. It owns registration IDs,
UUID identity facts, packed section keys, insertion orders, actual query boxes,
section/chunk visibility observations, and tracking/ticking insertion lists.
It contains no `E.State`, entity record, runtime, random source, or sound owner.
The scene retains the sole entity state.

`on_add` admits a prospective record already present once in the supplied
immutable sole-owner snapshot. It rejects duplicate registration/UUID, missing
or contradictory destination facts, a removed record, and insertion cursor
reuse. New/worldgen registration sets `created=True`; loaded registration sets
it to false. Existing section visibility is authoritative. Creating a section
requires one explicit loaded/visibility chunk fact; absent facts refuse.

`on_move` receives the original complete Common and original **registered**
section key, the proposed complete tick snapshot, its actual bounding box, the
real insertion cursor, and the immutable query records. It validates the
original registration and identity before mutation. Packed-key equality keeps
the insertion order, cursor, and callback journal, while updating the actual
query box. A different key detaches the ID, deletes an empty old section,
creates/finds the destination, appends behind its existing members, allocates
the next insertion order, updates the proposed Common accessibility/order, and
stages the exact movement lifecycle callback order before any neighbor query.

`query` uses the registered keys and supplied boxes. Candidate bounds expand
X/Z by two blocks and downward Y by four blocks; signed X and masked Z/Y key
ordering follows actual section storage. Each section retains insertion order.
Hidden sections are skipped. Registration/record inconsistencies refuse rather
than providing an invented empty neighbor result. The returned fixed record
list lets a merge consumer retain Java's single-query iteration order while
rechecking each candidate's changing merge eligibility.

`on_removed` detaches the ID and removes its UUID registration and tick/track
registrations before subsequent scheduling/query. It preserves the supplied
records and insertion cursor. The caller retains removed records and runtimes
as tombstones until the real publication transaction accepts. The destroy flag
is true for Java `KILLED`/`DISCARDED`, false for the three unload/dimension
transfer reasons; the pinned reference observes all five actual values.

`update_chunk` receives an actual loaded/visibility fact and updates existing
sections in packed Y order. For each section, ticking-stop passes precede
tracking transitions and ticking-start passes. This differs deliberately from
movement callbacks. Tracking/ticking journals update the retained ID lists in
actual insertion order. `tracked` implements the visible getter's ID order;
`scheduled` exposes the real ticking registration order. Accessibility alone
does not establish eligibility for tick scheduling.

Every operation produces an immutable `Proposal`, containing the prospective
manager view, insertion cursor, entity record snapshot and ordered callback
journal. `commit` retains the complete actual manager owner on failure. The
managed scene must install the proposed manager and entity cursor/records only
after the complete scene, sound and effect transaction accepts. A manager-only
commit is not an atomic scene transaction.

The Core adapter reads the actual destination physical section through
`Core.read_block`, whose production reader preserves the full trie and bucket
ordering. `capture` also requires a separate `Maybe<Visibility>` observation.
Physical presence does not imply tracking/ticking; `None` refuses. These
functions do not invent a loader, a scheduler clock, a second entity owner, or
persisted visibility recovery. Cold restoration must retain or reconstruct the
complete manager facts from actual loader authority before managed ticking.

This owner currently supports the production ItemEntity and ExperienceOrb
records, both normal entities (`isAlwaysTicking=False`). The pinned reference
also documents always-ticking behavior; it is outside these entity types and
is not approximated by this owner. Full entity kinds, real chunk streaming,
durable manager restoration, public actor adoption and full gameplay/client
acceptance remain separate integration obligations.

Independent specification observations are described in
`docs/entity_section_membership_reference.md`. Ordinary source checking,
independent kernel laws, native parity, and scene integration have separate
evidence and must not be conflated.

## Current verification

The current production manager and Core adapter pass ordinary checking. The
focused native command `python3 tools/test_entity_section_membership.py` passes
44 actual Java cases/127 steps: 35 entirely normal-entity cases and nine
explicit normal-member projections of mixed always-ticking observations. It
also passes ten actual refusal guards, five actual Core-capture cases and a
same-ID record preservation case across dimensions. Exact comparisons cover
section keys/visibility/member order, spatial query order, lifecycle event
order, visible getter insertion order, UUID refusal/release, registration
origins and packed aliases with actual boxes. Scheduler ID order is compared
against insertion/removal driven by the independent Java lifecycle stream.

The native receiver uses the complete original ordinary source checker, then
the existing verified retained-closure producer. It loads 105 source files;
emission takes 6.427 seconds at 806,092,800 bytes sampled peak RSS, clang takes
4.362 seconds at 456,818,688 bytes, and native execution takes 3.187 seconds at
23,887,872 bytes. See `evidence/entity-section-membership-native.json` for the
source pins, exact commands, native boundary and named exclusions. These
checks establish this manager consumer; they do not establish full Java
callback intermediate-state observation, abortable streaming traversal,
entity persistence, actor adoption, or whole-game parity.
