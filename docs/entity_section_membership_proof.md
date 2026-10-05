# Entity section membership production proofs

Thirty laws about the actual production manager and Core observation adapter
pass both the ordinary Bend checker and the pinned independent kernel. The
authoritative receipt is `evidence/entity-section-membership-proof.json`.
Confidence is high for these stated contracts; they do not establish the whole
entity simulation or complete Minecraft parity.

The receipt records generation 1 against the adopted five-field manager View
and the current dimension-aware record replacement and removal validation.
The original book contains 2,166 declarations from 36 loaded source files.
Its ordinary API check took 0.457379 seconds; checking and exporting together
took 1.477447 seconds. The unchanged 364,865-byte theorem closure passed the
independent kernel in 0.059676 seconds, with zero exclusions and no open holes.
The retained artifact is
`build/entity-section-membership-proof/1791169063349595000/selected.bendtt`
(SHA-256 `1c39f794b3115e80494dafc3db610b7fdc329a1d455ab2b0457a343cd85d2acc`).

## Stated contracts

| Scope | Laws | What the independent kernel establishes |
| --- | ---: | --- |
| Arbitrary removal and actual registries | 10 | Induction over arbitrary ID, Member and Registration lists removes every occurrence of the selected dimension/ID. UUID registration is released under the stated identity invariant. Actual getter/scheduler end callbacks remove their ID; arbitrary callback journals retain complete member, section and chunk owners; actual removal retains the entire prospective entity-record list and insertion cursor and erases membership/UUID registration. |
| Complete manager transaction | 4 | Failed commit retains the entire affine `M.State` and exact error; successful commit installs its View and returns the complete proposal. Actual missing-record removal and stale-record removal composed with actual commit retain the complete manager. |
| Full record patches | 3 | Updating section accessibility/order preserves all other Common fields, including RNG and the entire vanilla Fields record, and preserves every Item and Orb payload field. |
| Callback order | 4 | Ticking-to-hidden movement stops tracking before ticking; a move within ticking emits SectionChange. Chunk transitions perform the complete ticking-end pass before tracking-end, and complete tracking-start before ticking-start, over arbitrary ID lists. |
| Query admission | 3 | A rejected section skips arbitrary entity records/IDs. A hidden section is skipped before querying its arbitrary tail. Missing membership prevents an actual query from publishing a stale retained entity record. |
| Movement, insertion and empty updates | 4 | The same-section branch preserves the complete proposed record/runtime, Common order, insertion cursor, sections/chunks/registries and empty callback journal while updating the box and prospective records. Existing hidden-section insertion appends the new ID after an arbitrary prefix and advances the cursor once. An empty section visibility update retains complete records, and a zero-section chunk update retains complete records/cursor and registration owners. |
| Actual Core observation | 2 | Physical section refusal preserves the complete returned Core and exact refusal. A physically present section with missing visibility refuses rather than fabricating a visibility value. |

The exact thirty named statements are listed in the receipt and in
`src/entity_section_membership_laws.bend`.

## Premises and limits

The UUID invariant `uuid_links` independently requires the dimension/ID match
and dimension/UUID match to designate the same raw members. It does not assume
the theorem's filtered-count conclusion. Under this premise the inductive law
removes UUID reservations even if the raw list contains duplicate registrations.
The actual removal consequence quantifies over the complete actual View,
including arbitrary tracking/ticking lists, sections and chunks.

The insertion law assumes the destination ID count is zero and covers an
existing Hidden destination with both creation flags false. The same-section
law covers the actual `move_key` True branch; it does not prove that every
arbitrary input passes `on_move`'s earlier validation. The empty-section law
covers the admitted `chunk_section` branch, and the zero-membership law covers
an actual View with no sections. The Core laws cover adapter behavior after
the actual Core read returns; they do not prove universal world availability.

The manager owns membership, chunk visibility and tracking/ticking facts.
Immutable prospective records are proposals to the scene's sole entity owner;
these laws do not duplicate or certify the scene's affine `E.State`/`T.State`.
Geometric IEEE behavior, signed packed traversal equivalence to vanilla,
complete scheduler execution, save/load, native transport, and application
scene integration require their own evidence. Independent Java fixtures and
native manager execution are recorded separately; they are not kernel proofs.

## Reproduction

```sh
python3 tools/test_entity_section_membership_proof.py --generation 1
```

The exporter loads and checks the original production book once. It selects
only the thirty actual declared, checked, pure theorem roots by changing
`book.order`; all original declaration maps, types, source bodies and checked
proof bodies remain unchanged. The supported read-only exporter retains their
complete referenced closure, rejects exclusions, and the runner requires the
pinned kernel's exact `ALL PROOFS CHECK` verdict. This is a verdict on that
unchanged theorem closure, not a full-book `--verdict` claim.

Each run retains source/toolchain pins, exact theorem-term pins, process
receipts, stdout/stderr, selection metadata and the emitted artifact in a fresh
directory. A failed, timed-out or interrupted run is recorded as failed and
cleans up its process group; ordinary source acceptance alone is never
published as independent-kernel acceptance.
