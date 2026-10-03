# Section storage

`src/section.bend` implements pure Bend storage for a 16 × 16 × 16 section of U32 block-state IDs. This is a storage component, not a world generator, block-state registry, palette codec, chunk format, or claim of Minecraft Java 26.3 parity.

## Representation and ownership

`Section` is `Type`, containing one affine `Array<U32>`. `Section.new(state)` constructs a balanced 4,096-slot array initialized with `state`. All public reads and writes consume a section and return its owner beside a fallible result. Block-state IDs accept the full U32 range; semantic registry validity belongs to the caller.

The raw `Section{blocks}` constructor and dotted implementation helpers are visible because Bend modules do not provide an opaque type boundary here. Callers must construct sections through `Section.new` and use the checked functions below. The 4,096-slot invariant is maintained by those functions; this module does not certify arbitrary hand-constructed arrays as sections.

No array is marked reusable. No `Array.fork`, unsafe definition, foreign implementation, or axiom is used. `Section.clone` creates two independent owners through `Array.clone`; it copies the 4,096 U32 values. `Section.snapshot` returns the original owner and a copied `List<&2, U32>` in increasing index order. It reads each slot once, backwards, and prepends the copied scalar to the list.

## Checked API

Import the module with an alias, for example `import ./section.bend as Storage`, then use `Storage.Section.get(...)`.

| Name | Inputs | Output |
| --- | --- | --- |
| `Section.new` | `state: U32` | `Section` |
| `Section.local_index` | `x, y, z: U32` | `Result<&2, &2, Section.Error, U32>` |
| `Section.index_local` | `index: U32` | `Result<&2, &2, Section.Error, Section.Local>` |
| `Section.get` | `section: Section`, `x, y, z: U32` | `Section & Result<&2, &2, Section.Error, U32>` |
| `Section.set` | `section: Section`, `x, y, z, state: U32` | `Section & Result<&2, &2, Section.Error, Unit>` |
| `Section.get_index` | `section: Section`, `index: U32` | `Section & Result<&2, &2, Section.Error, U32>` |
| `Section.set_index` | `section: Section`, `index, state: U32` | `Section & Result<&2, &2, Section.Error, Unit>` |
| `Section.clone` | `section: Section` | `Section & Section` |
| `Section.snapshot` | `section: Section` | `Section & List<&2, U32>` |

`Section.Local` is the Data record `Local{x: U32, y: U32, z: U32}`. Local coordinates must each lie in `[0, 15]`; indices must lie in `[0, 4095]`. The layout is:

```text
index = x + 16*z + 256*y
x is fastest, then z, then y.
```

An invalid coordinate returns `Fail{BadLocal{x,y,z}}`; an invalid index returns `Fail{BadIndex{index}}`. Rejected reads and writes return the unmodified owner. The implementation validates before invoking Base array access. Base arrays wrap internally, but wrapping is never the behavior of these checked public functions.

## Signed coordinate utility

World and section coordinates use two's-complement I32 bit patterns encoded in U32. Encoding an integer `w` means `w modulo 2^32`. All U32 values represent one I32 coordinate. This component does not impose a Minecraft dimension height or world-border limit.

| Name | Behavior |
| --- | --- |
| `Coord.section(world: U32) -> U32` | Signed floor division by 16; arithmetic right shift with sign extension. |
| `Coord.local(world: U32) -> U32` | Euclidean remainder in `[0,15]`, including negative coordinates. |
| `Coord.split(world: U32) -> U32 & U32` | Encoded section coordinate and local remainder. |
| `Coord.compose(section: U32, local: U32) -> Result<&2, &2, Section.Error, U32>` | Checked inverse: section must represent an integer in `[-134217728,134217727]`, and local must lie in `[0,15]`. |

Composition rejects an out-of-range section with `BadSection{coordinate}` and an out-of-range remainder with `BadRemainder{local}`. Section validity is checked first. It computes `16*section + local` modulo `2^32` only after both checks, so the accepted signed result fits I32.

| Signed world | Encoded world | Signed section | Encoded section | Local |
| ---: | ---: | ---: | ---: | ---: |
| -17 | 4294967279 | -2 | 4294967294 | 15 |
| -16 | 4294967280 | -1 | 4294967295 | 0 |
| -1 | 4294967295 | -1 | 4294967295 | 15 |
| 0 | 0 | 0 | 0 | 0 |
| 16 | 16 | 1 | 1 | 0 |
| -2147483648 | 2147483648 | -134217728 | 4160749568 | 0 |
| 2147483647 | 2147483647 | 134217727 | 134217727 | 15 |

## Verification and proof scope

`src/section_laws.bend` contains 17 implementation laws, proved in `src/section_proof.bend` without unsafe or foreign dependencies. The checker and separate BendTT kernel accept them with Bend 2.0.35. They establish:

- Invalid checked index and local-coordinate reads/writes return the same owner and exact failure payload for every section and every scalar input satisfying the stated invalidity premise.
- The local-coordinate gate accepts or rejects according to its validation predicate.
- Checked composition rejects an invalid section, or an invalid local remainder under a valid section.
- Constructor-based read-after-write and opposite-corner isolation at indices 0 and 4095 hold for arbitrary initial and written U32 states.
- Clone isolation at index 0 holds for arbitrary initial and written U32 states.
- Concrete axis-order, negative-boundary, and signed I32 endpoint computations hold.

These laws do **not** assert a universally quantified read-after-write/isolation theorem over all possible sections and indices, a universal signed round-trip theorem, array-shape validity for arbitrary raw constructors, or Java behavioral parity. The exhaustive and independent boundary tests below provide additional execution evidence.

`tests/section.bend` checks all 4,096 local coordinates against traversal indices, using division/modulo to independently generate expected inverse coordinates. It verifies every initial cell, every written cell immediately after writing, neighbor isolation after every write, every final cell through coordinate and index access, both directions of clone isolation, and all 4,096 snapshot cells after later updates. Seven invalid indices and ten invalid local triples are rejected, and a full subsequent scan verifies rejected writes altered no slot. Thirty-three explicit signed world fixtures were generated by Python integer `//16` and `%16`, including I32 endpoints and negative section boundaries. Composition overflow, remainder rejection, and error priority are checked separately.

The evaluator and native CPU executable both report zero failures. Emitted C uses a contiguous U32 buffer, `blk_read` and `blk_write` on accepted array accesses, and `blk_copy` for explicit cloning. The inspected get/set routines have no `term_keep`, `ctr_take`, or `rfc_seal` calls. The snapshot traversal uses reads and list allocation while retaining the section owner. These are ownership/code-generation observations, not a performance benchmark.

Reproduce from the `minecraft` directory:

```sh
/Users/chuah/.bend/bin/bend src/section_proof.bend --check-only
/Users/chuah/.bend/bin/bend src/section_proof.bend --verdict
/Users/chuah/.bend/bin/bend tests/section.bend
/Users/chuah/.bend/bin/bend tests/section.bend -o /tmp/minecraft-section-tests.c
/Users/chuah/.bend/bin/bend tests/section.bend -o /tmp/minecraft-section-tests
/tmp/minecraft-section-tests --gpu off
```

Evidence summaries are in `evidence/section-verification.json` and the independent signed fixtures in `evidence/section-coordinate-fixtures.json`. Generated C and executables are temporary build artifacts.
