# Complete-owner Core refusal

`Core.apply` now routes section creation and block writes through
`section_map_update.bend`. The root-owned Core join replaces the previous
`SectionMap.pop` / `SectionMap.set` round trip.

The old duplicate-create path removed an existing section and prepended it
again. For two hash-colliding keys this changed collision order on a refusal.
The old missing-write path could also normalize `Bucket{[]}` to
`EmptySections{}`. Lookup equivalence did not imply complete-world identity.

The new helper follows the existing hash's 32 low-to-high bits. Its membership
query returns the original owned collision bucket beside the observation.
Duplicate creation refuses before constructing an array. Missing writes retain
every trie constructor. Invalid raw local coordinates refuse after membership
and before any array write. A successful write replaces the first selected
entry at its original position; a successful new section is prepended, as in
the historical map. Malformed create paths refuse without discarding owners.

The public interface is:

```text
Update.create(sections, key, fill) -> Sections & Result<Update.Error, Unit>
Update.write(sections, key, x, y, z, state) -> the same result type
```

Errors are `Existing`, `Missing`, `Malformed`, and
`SectionRejected{Section.Error}`. Core maps these to `SectionExists`,
`MissingSection`, or `InvalidCoordinate` through its actual `updated_sections`
consumer. Core's old internal pop/set helper definitions remain present but
are no longer called by the production create/write/apply paths.

Sixteen new map contracts and four Core contracts pass ordinary checking and
the unchanged complete independent-kernel route. The final `--verdict` takes
1.587 seconds and also includes the seventeen existing Section laws. Four
recursive map laws quantify over arbitrary paths and actual owned tries;
their public corollaries use the real map hash. They prove complete pair
equalities on duplicate, missing, invalid-local and malformed-create refusal,
including every Section array and collision position. The membership
specification reads keys from actual entries; it does not substitute another
map. Core contracts prove the identical complete `World` and exact error for
duplicate/missing/malformed `apply` refusals, plus Section-error composition.

No foreign code, axioms, selective theorem extraction or lookup-only
equivalence establishes these claims. The contracts are in
`src/section_map_update_laws.bend` and `src/core_refusal_laws.bend`; their paired
proof modules are the execution targets.

The cold ordinary native build takes 7.444 seconds; the focused executable
takes 0.705 seconds. Eighteen actual Core/query/map operations cover the existing
canonical FNV collision fixture, repeated duplicate requests interleaved with
real Core reads, missing edits, successful write isolation, retained empty
buckets and side branches, malformed depth with an arbitrary two-leaf array,
and invalid local writes. The native observer traverses actual array topology
and every word, complete trie constructors and bucket order, and all World
metadata, pending actions and events. Both owned process groups are absent
after execution; sources remain unchanged.

World-coordinate writes pass `Coord.local` (0..15), so a bad raw local is a
map-interface refusal and is not manufactured as a reachable Core action.
The contracts do not establish arbitrary-array shape validity, a universal
successful-write content theorem, Java behavioral parity, or transport/save
acceptance. Scheduled `finish` intentionally adds its rejection event; these
whole-world identity claims concern `apply` before that event is added.

Compact evidence: `evidence/core-refusal-001.json`. Raw diagnostics, proof
receipts and native output remain under `build/section-map-update`.

```sh
/Users/chuah/.bend/bin/bend src/core_refusal_proof.bend --check-only
/Users/chuah/.bend/bin/bend src/core_refusal_proof.bend --verdict
python3 tools/build_native.py tests/core_refusal.bend -o build/section-map-update/core-refusal --report build/section-map-update/native-build.json
build/section-map-update/core-refusal --gpu off --threads 2
```
